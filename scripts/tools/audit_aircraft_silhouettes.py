"""Audit aircraft silhouette PNGs and current AircraftParams coverage."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "scripts" / "aircraft_silhouette_catalog.gd"
ASSET_DIR = ROOT / "resources" / "aircraft_silhouettes"
MANIFEST = ASSET_DIR / "reference_manifest.json"
TEXTURE_RE = re.compile(r'"([^\"]+)": "res://([^\"]+\.png)"')
DISPLAY_RE = re.compile(r'"([^\"]+)": "([^\"]+)"')
DISPLAY_NAME_RE = re.compile(r'^display_name\s*=\s*"([^\"]+)"', re.MULTILINE)


def aircraft_param_files() -> list[Path]:
    result: list[Path] = []
    for path in (ROOT / "resources").rglob("*.tres"):
        source = path.read_text(encoding="utf-8")
        script_match = re.search(
            r'\[ext_resource type="Script" path="res://scripts/aircraft_params\.gd" id="([^\"]+)"\]',
            source,
        )
        resource_block = source.split("[resource]", 1)[-1]
        altitude_match = re.search(r'^max_altitude\s*=\s*([0-9.]+)', resource_block, re.MULTILINE)
        is_airborne = altitude_match is None or float(altitude_match.group(1)) > 0.0
        if script_match and is_airborne and f'script = ExtResource("{script_match.group(1)}")' in resource_block:
            result.append(path)
    return result


def main() -> None:
    source = CATALOG.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))["aircraft"]
    texture_pairs = dict(TEXTURE_RE.findall(source))
    display_block = source.split("const DISPLAY_KEYS", 1)[1].split("const LEGACY_DISPLAY_NAMES", 1)[0]
    display_pairs = dict(DISPLAY_RE.findall(display_block))
    legacy_block = source.split("const LEGACY_DISPLAY_NAMES", 1)[1].split("const DRAW_SCALE", 1)[0]
    legacy_names = set(re.findall(r'"([^\"]+)"', legacy_block))
    errors: list[str] = []

    missing_manifest_keys = sorted(set(display_pairs.values()) - set(manifest))
    if missing_manifest_keys:
        errors.append(f"display aliases reference undocumented keys: {missing_manifest_keys}")
    reviewed_keys = {key for key, entry in manifest.items() if entry["status"] == "reviewed"}
    if set(texture_pairs) != reviewed_keys:
        errors.append(
            "catalog must contain exactly reviewed manifest entries: "
            f"catalog_only={sorted(set(texture_pairs) - reviewed_keys)} "
            f"manifest_only={sorted(reviewed_keys - set(texture_pairs))}"
        )
    for key in reviewed_keys:
        entry = manifest[key]
        if not entry.get("source_url") and not entry.get("source_kind"):
            errors.append(f"{key}: reviewed entry has no reference source")
        if not entry.get("production_file"):
            errors.append(f"{key}: reviewed entry has no production_file")

    used_names: dict[str, list[str]] = {}
    for path in aircraft_param_files():
        resource_block = path.read_text(encoding="utf-8").split("[resource]", 1)[-1]
        match = DISPLAY_NAME_RE.search(resource_block)
        if match:
            used_names.setdefault(match.group(1), []).append(path.relative_to(ROOT).as_posix())
    overlap_names = sorted(set(display_pairs) & legacy_names)
    if overlap_names:
        errors.append(f"display names cannot use both PNG and legacy renderer: {overlap_names}")
    missing_names = sorted(set(used_names) - set(display_pairs) - legacy_names)
    if missing_names:
        missing_details = {name: used_names[name] for name in missing_names}
        errors.append(f"AircraftParams display names without direct mapping: {missing_details}")

    for key, relative in sorted(texture_pairs.items()):
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"{key}: missing {relative}")
            continue
        with Image.open(path) as image:
            if image.mode != "RGBA" or image.size != (128, 128):
                errors.append(f"{key}: expected 128x128 RGBA, got {image.size} {image.mode}")
                continue
            rgba = image.copy()
        alpha = rgba.getchannel("A")
        expected_hash = manifest[key].get("reference_alpha_sha256")
        if expected_hash:
            actual_hash = hashlib.sha256(alpha.tobytes()).hexdigest()
            if actual_hash != expected_hash:
                errors.append(f"{key}: alpha contour differs from reviewed reference hash")
        bbox = alpha.getbbox()
        if bbox is None:
            errors.append(f"{key}: empty alpha mask")
            continue
        if any(alpha.getpixel(corner) != 0 for corner in ((0, 0), (127, 0), (0, 127), (127, 127))):
            errors.append(f"{key}: a canvas corner is not transparent")
        visible = sum(1 for value in alpha.get_flattened_data() if value >= 16)
        coverage = visible / (128 * 128)
        if not 0.02 <= coverage <= 0.55:
            errors.append(f"{key}: suspicious alpha coverage {coverage:.3f}")
        rgb = rgba.convert("RGB")
        for channel in rgb.split():
            if channel.getextrema() != (255, 255):
                errors.append(f"{key}: visible source must use white RGB")
                break
        mirrored = alpha.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        asymmetry = sum(ImageChops.difference(alpha, mirrored).get_flattened_data()) / (255 * 128 * 128)
        # 扫描/抠图参考可保留轻微左右误差；禁止为了过审而强制镜像重画。
        max_asymmetry = float(manifest[key].get("max_asymmetry", 0.03))
        if asymmetry > max_asymmetry:
            errors.append(f"{key}: horizontal asymmetry {asymmetry:.4f}")

    if errors:
        print("AIRCRAFT SILHOUETTE AUDIT: FAIL")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)

    print(
        "AIRCRAFT SILHOUETTE AUDIT: PASS "
        f"({len(texture_pairs)} reviewed PNGs, {len(used_names)} AircraftParams display names, "
        f"{len(display_pairs)} PNG aliases, {len(legacy_names)} legacy aliases)"
    )


if __name__ == "__main__":
    main()
