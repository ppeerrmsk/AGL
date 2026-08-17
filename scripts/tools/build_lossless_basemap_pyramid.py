from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from raster_basemap_preview import MAPS, apply_color_profile, image_array, luma, sobel


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "tmp" / "raster_basemap_tiles"
CONTENT = 1024
GUTTER = 16
FILTER_HALO = 4
TILE_EXTENSION = ".webp"


def strategic_filename(size: int) -> str:
    return f"strategic{TILE_EXTENSION}" if size == 1024 else f"strategic_{size}{TILE_EXTENSION}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def crop_edge_padded(
    image: Image.Image, box: tuple[int, int, int, int]
) -> Image.Image:
    left, top, right, bottom = box
    clip = (
        max(0, left),
        max(0, top),
        min(image.width, right),
        min(image.height, bottom),
    )
    crop = np.asarray(image.crop(clip), dtype=np.uint8)
    pad = (
        (max(0, -top), max(0, bottom - image.height)),
        (max(0, -left), max(0, right - image.width)),
        (0, 0),
    )
    if any(value for axis in pad for value in axis):
        crop = np.pad(crop, pad, mode="edge")
    return Image.fromarray(crop, mode="RGB")


def process_detail_tile(
    source: Image.Image,
    content_x: int,
    content_y: int,
    profile: dict[str, Any],
) -> Image.Image:
    stored_left = content_x - GUTTER
    stored_top = content_y - GUTTER
    work_left = stored_left - FILTER_HALO
    work_top = stored_top - FILTER_HALO
    work_size = CONTENT + GUTTER * 2 + FILTER_HALO * 2
    work = crop_edge_padded(
        source,
        (work_left, work_top, work_left + work_size, work_top + work_size),
    )
    source_rgb = image_array(work)
    raw_edge = sobel(source_rgb)

    # The 0.55 px Gaussian used by the preview is separable and local. Pillow's
    # implementation is deterministic, so a 4 px halo makes adjacent gutters exact.
    edge_image = Image.fromarray(
        np.uint8(np.clip(raw_edge, 0.0, 1.0) * 255), mode="L"
    )
    # GaussianBlur is imported lazily to keep the tile builder's module surface small.
    from PIL import ImageFilter

    softened = np.asarray(
        edge_image.filter(ImageFilter.GaussianBlur(0.55)), dtype=np.float32
    ) / 255.0
    edge = np.clip(
        (softened - profile["edge_floor"]) * profile["edge_gain"],
        0.0,
        profile["edge_cap"],
    )[..., None]
    edge_color = np.asarray(profile["edge_color"], dtype=np.float32)
    rgb = source_rgb * (1.0 - edge) + edge_color * edge
    rgb = apply_color_profile(
        rgb,
        profile["saturation"],
        profile["brightness"],
        profile["contrast"],
        profile["tint"],
    )

    # Vignette is evaluated in global map coordinates. Grain remains a runtime-only
    # shader term, so it cannot introduce tile seams or inflate the raster pyramid.
    yy, xx = np.mgrid[0:work_size, 0:work_size]
    gx = np.clip(work_left + xx + 0.5, 0.5, source.width - 0.5)
    gy = np.clip(work_top + yy + 0.5, 0.5, source.height - 0.5)
    nx = gx / source.width * 2.0 - 1.0
    ny = gy / source.height * 2.0 - 1.0
    radial = np.clip((nx * nx + ny * ny - 0.30) / 1.35, 0.0, 1.0)[..., None]
    rgb *= 1.0 - radial * profile["vignette_strength"]
    rendered = Image.fromarray(np.uint8(np.clip(rgb, 0.0, 1.0) * 255), mode="RGB")
    return rendered.crop(
        (
            FILTER_HALO,
            FILTER_HALO,
            FILTER_HALO + CONTENT + GUTTER * 2,
            FILTER_HALO + CONTENT + GUTTER * 2,
        )
    )


def save_lossless(image: Image.Image, path: Path) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(
        path,
        format="WEBP",
        lossless=True,
        quality=100,
        method=6,
        exact=True,
    )
    with Image.open(path) as decoded_file:
        decoded = np.asarray(decoded_file.convert("RGB"), dtype=np.uint8)
    source = np.asarray(image, dtype=np.uint8)
    pixel_exact = bool(np.array_equal(source, decoded))
    if not pixel_exact:
        raise RuntimeError(f"lossless round-trip mismatch: {path}")
    return {
        "path": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "pixel_exact": pixel_exact,
    }


def cut_processed_level(
    image: Image.Image,
    level_dir: Path,
    rows: int,
    columns: int,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for row in range(rows):
        for column in range(columns):
            x = column * CONTENT
            y = row * CONTENT
            tile = crop_edge_padded(
                image,
                (x - GUTTER, y - GUTTER, x + CONTENT + GUTTER, y + CONTENT + GUTTER),
            )
            filename = f"r{row:02d}_c{column:02d}{TILE_EXTENSION}"
            file_record = save_lossless(tile, level_dir / filename)
            records.append(
                {
                    **file_record,
                    "row": row,
                    "column": column,
                    "content_rect": [
                        x,
                        y,
                        min(CONTENT, image.width - x),
                        min(CONTENT, image.height - y),
                    ],
                }
            )
    return records


def seam_metrics(level_dir: Path, rows: int, columns: int) -> dict[str, Any]:
    max_abs = 0
    mismatch_pixels = 0
    comparisons = 0
    for row in range(rows):
        for column in range(columns - 1):
            left = np.asarray(Image.open(level_dir / f"r{row:02d}_c{column:02d}{TILE_EXTENSION}"))
            right = np.asarray(Image.open(level_dir / f"r{row:02d}_c{column + 1:02d}{TILE_EXTENSION}"))
            diff = np.abs(left[:, CONTENT : CONTENT + GUTTER * 2].astype(np.int16) - right[:, : GUTTER * 2].astype(np.int16))
            max_abs = max(max_abs, int(diff.max()))
            mismatch_pixels += int(np.count_nonzero(diff))
            comparisons += 1
    for row in range(rows - 1):
        for column in range(columns):
            top = np.asarray(Image.open(level_dir / f"r{row:02d}_c{column:02d}{TILE_EXTENSION}"))
            bottom = np.asarray(Image.open(level_dir / f"r{row + 1:02d}_c{column:02d}{TILE_EXTENSION}"))
            diff = np.abs(top[CONTENT : CONTENT + GUTTER * 2, :].astype(np.int16) - bottom[: GUTTER * 2, :].astype(np.int16))
            max_abs = max(max_abs, int(diff.max()))
            mismatch_pixels += int(np.count_nonzero(diff))
            comparisons += 1
    return {
        "comparisons": comparisons,
        "max_abs_rgb": max_abs,
        "mismatch_channel_values": mismatch_pixels,
        "pass": max_abs == 0 and mismatch_pixels == 0,
    }


def rgb_mean(image: Image.Image) -> list[float]:
    values = np.asarray(image, dtype=np.float64).reshape(-1, 3).mean(axis=0) / 255.0
    return [round(float(value), 7) for value in values]


def build_map(
    key: str,
    config: dict[str, Any],
    output_root: Path,
    bake_style: bool,
    operational_size: int,
    strategic_size: int,
) -> dict[str, Any]:
    map_dir = output_root / key
    if map_dir.exists():
        shutil.rmtree(map_dir)
    detail_dir = map_dir / "detail"
    operational_dir = map_dir / "operational"
    profile = config["profile"]

    with Image.open(config["source"]) as source_file:
        source = source_file.convert("RGB")
    processed_master = Image.new("RGB", source.size) if bake_style else source
    detail_records: list[dict[str, Any]] = []
    rows = math.ceil(source.height / CONTENT)
    columns = math.ceil(source.width / CONTENT)
    for row in range(rows):
        for column in range(columns):
            x = column * CONTENT
            y = row * CONTENT
            if bake_style:
                tile = process_detail_tile(source, x, y, profile)
            else:
                tile = crop_edge_padded(
                    source,
                    (x - GUTTER, y - GUTTER, x + CONTENT + GUTTER, y + CONTENT + GUTTER),
                )
            filename = f"r{row:02d}_c{column:02d}{TILE_EXTENSION}"
            file_record = save_lossless(tile, detail_dir / filename)
            valid_w = min(CONTENT, source.width - x)
            valid_h = min(CONTENT, source.height - y)
            content_image = tile.crop(
                (GUTTER, GUTTER, GUTTER + valid_w, GUTTER + valid_h)
            )
            if bake_style:
                processed_master.paste(content_image, (x, y))
            detail_records.append(
                {
                    **file_record,
                    "row": row,
                    "column": column,
                    "content_rect": [x, y, valid_w, valid_h],
                }
            )
    operational = processed_master.resize(
        (operational_size, operational_size), Image.Resampling.LANCZOS
    )
    strategic = processed_master.resize(
        (strategic_size, strategic_size), Image.Resampling.LANCZOS
    )
    operational_rows = math.ceil(operational_size / CONTENT)
    operational_columns = math.ceil(operational_size / CONTENT)
    operational_records = cut_processed_level(
        operational,
        operational_dir,
        rows=operational_rows,
        columns=operational_columns,
    )
    strategic_record = save_lossless(strategic, map_dir / strategic_filename(strategic_size))

    detail_seams = seam_metrics(detail_dir, rows=rows, columns=columns)
    operational_seams = seam_metrics(
        operational_dir, rows=operational_rows, columns=operational_columns
    )
    means = {
        "detail": rgb_mean(processed_master),
        "operational": rgb_mean(operational),
        "strategic": rgb_mean(strategic),
    }
    parent_delta = max(
        abs(means["detail"][channel] - means["operational"][channel])
        for channel in range(3)
    )
    strategic_delta = max(
        abs(means["detail"][channel] - means["strategic"][channel])
        for channel in range(3)
    )
    disk_bytes = (
        strategic_record["bytes"]
        + sum(record["bytes"] for record in operational_records)
        + sum(record["bytes"] for record in detail_records)
    )
    manifest = {
        "schema_version": 1,
        "map_id": key,
        "source": config["source"].name,
        "source_sha256": sha256(config["source"]),
        "style_profile_id": config["profile_id"],
        "style_profile": profile,
        "codec": "lossless_webp",
        "style_baked": bake_style,
        "content_size": CONTENT,
        "gutter": GUTTER,
        "runtime_grain_strength": profile["noise_strength"],
        "runtime_grain_repeat": profile.get("grain_repeat", 64.0),
        "levels": {
            "strategic": {
                "size": [strategic_size, strategic_size],
                "rows": 1,
                "columns": 1,
                "tiles": [strategic_record],
            },
            "operational": {
                "size": [operational_size, operational_size],
                "rows": operational_rows,
                "columns": operational_columns,
                "tiles": operational_records,
            },
            "detail": {
                "size": [8704, 8704],
                "rows": rows,
                "columns": columns,
                "tiles": detail_records,
            },
        },
        "qa": {
            "disk_bytes": disk_bytes,
            "disk_mib": round(disk_bytes / 1024 / 1024, 3),
            "rgb_means": means,
            "detail_to_operational_max_mean_delta": round(parent_delta, 8),
            "detail_to_strategic_max_mean_delta": round(strategic_delta, 8),
            "parent_mean_gate": parent_delta <= 2 / 255 and strategic_delta <= 2 / 255,
            "detail_seams": detail_seams,
            "operational_seams": operational_seams,
        },
    }
    manifest_path = map_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if bake_style:
        processed_master.close()
    source.close()
    operational.close()
    strategic.close()
    print(
        f"{key}: {manifest['qa']['disk_mib']:.3f} MiB, "
        f"detail_seams={detail_seams['pass']}, "
        f"operational_seams={operational_seams['pass']}, "
        f"parent_mean={manifest['qa']['parent_mean_gate']}"
    )
    return manifest


def build_operational_only(
    key: str,
    config: dict[str, Any],
    output_root: Path,
    base_root: Path,
    operational_size: int,
) -> dict[str, Any]:
    """Copy a validated pyramid and replace only its raw-pixel Operational level."""
    source_map_dir = (base_root / key).resolve()
    map_dir = (output_root / key).resolve()
    if not source_map_dir.is_dir():
        raise FileNotFoundError(f"missing base pyramid: {source_map_dir}")
    if map_dir == source_map_dir or source_map_dir in map_dir.parents:
        raise ValueError("operational-only output must not overwrite or nest inside the base pyramid")
    if map_dir.exists():
        shutil.rmtree(map_dir)
    shutil.copytree(source_map_dir, map_dir)

    manifest_path = map_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if bool(manifest.get("style_baked", False)):
        raise ValueError(f"{key}: operational-only rebuild requires a raw-pixel base")
    if manifest.get("source_sha256") != sha256(config["source"]):
        raise ValueError(f"{key}: source PNG does not match the base manifest")

    operational_dir = map_dir / "operational"
    if operational_dir.exists():
        shutil.rmtree(operational_dir)
    with Image.open(config["source"]) as source_file:
        source = source_file.convert("RGB")
    operational = source.resize(
        (operational_size, operational_size), Image.Resampling.LANCZOS
    )
    rows = math.ceil(operational_size / CONTENT)
    columns = math.ceil(operational_size / CONTENT)
    records = cut_processed_level(
        operational,
        operational_dir,
        rows=rows,
        columns=columns,
    )
    seams = seam_metrics(operational_dir, rows=rows, columns=columns)
    operational_mean = rgb_mean(operational)
    detail_mean = manifest["qa"]["rgb_means"]["detail"]
    strategic_mean = manifest["qa"]["rgb_means"]["strategic"]
    parent_delta = max(
        abs(detail_mean[channel] - operational_mean[channel])
        for channel in range(3)
    )
    strategic_delta = max(
        abs(detail_mean[channel] - strategic_mean[channel])
        for channel in range(3)
    )
    manifest["levels"]["operational"] = {
        "size": [operational_size, operational_size],
        "rows": rows,
        "columns": columns,
        "tiles": records,
    }
    manifest["qa"]["rgb_means"]["operational"] = operational_mean
    manifest["qa"]["detail_to_operational_max_mean_delta"] = round(parent_delta, 8)
    manifest["qa"]["detail_to_strategic_max_mean_delta"] = round(strategic_delta, 8)
    manifest["qa"]["parent_mean_gate"] = (
        parent_delta <= 2 / 255 and strategic_delta <= 2 / 255
    )
    manifest["qa"]["operational_seams"] = seams
    manifest["qa"]["disk_bytes"] = sum(
        int(record["bytes"])
        for level in manifest["levels"].values()
        for record in level["tiles"]
    )
    manifest["qa"]["disk_mib"] = round(
        manifest["qa"]["disk_bytes"] / 1024 / 1024, 3
    )
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    source.close()
    operational.close()
    print(
        f"{key}: Operational {operational_size}, {manifest['qa']['disk_mib']:.3f} MiB, "
        f"seams={seams['pass']}, parent_mean={manifest['qa']['parent_mean_gate']}"
    )
    return manifest


def build_strategic_only(
    key: str,
    config: dict[str, Any],
    output_root: Path,
    base_root: Path,
    strategic_size: int,
) -> dict[str, Any]:
    """Copy a validated pyramid and replace only its raw-pixel Strategic level."""
    source_map_dir = (base_root / key).resolve()
    map_dir = (output_root / key).resolve()
    if not source_map_dir.is_dir():
        raise FileNotFoundError(f"missing base pyramid: {source_map_dir}")
    if map_dir == source_map_dir or source_map_dir in map_dir.parents:
        raise ValueError("strategic-only output must not overwrite or nest inside the base pyramid")
    if map_dir.exists():
        shutil.rmtree(map_dir)
    shutil.copytree(source_map_dir, map_dir)

    manifest_path = map_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if bool(manifest.get("style_baked", False)):
        raise ValueError(f"{key}: strategic-only rebuild requires a raw-pixel base")
    if manifest.get("source_sha256") != sha256(config["source"]):
        raise ValueError(f"{key}: source PNG does not match the base manifest")

    with Image.open(config["source"]) as source_file:
        source = source_file.convert("RGB")
    strategic = source.resize(
        (strategic_size, strategic_size), Image.Resampling.LANCZOS
    )
    strategic_path = map_dir / strategic_filename(strategic_size)
    old_strategic_path = map_dir / strategic_filename(1024)
    if strategic_path != old_strategic_path and old_strategic_path.exists():
        old_strategic_path.unlink()
    strategic_record = save_lossless(strategic, strategic_path)
    strategic_mean = rgb_mean(strategic)
    detail_mean = manifest["qa"]["rgb_means"]["detail"]
    operational_mean = manifest["qa"]["rgb_means"]["operational"]
    parent_delta = max(
        abs(detail_mean[channel] - operational_mean[channel])
        for channel in range(3)
    )
    strategic_delta = max(
        abs(detail_mean[channel] - strategic_mean[channel])
        for channel in range(3)
    )
    manifest["levels"]["strategic"] = {
        "size": [strategic_size, strategic_size],
        "rows": 1,
        "columns": 1,
        "tiles": [strategic_record],
    }
    manifest["qa"]["rgb_means"]["strategic"] = strategic_mean
    manifest["qa"]["detail_to_operational_max_mean_delta"] = round(
        parent_delta, 8
    )
    manifest["qa"]["detail_to_strategic_max_mean_delta"] = round(
        strategic_delta, 8
    )
    manifest["qa"]["parent_mean_gate"] = (
        parent_delta <= 2 / 255 and strategic_delta <= 2 / 255
    )
    manifest["qa"]["disk_bytes"] = sum(
        int(record["bytes"])
        for level in manifest["levels"].values()
        for record in level["tiles"]
    )
    manifest["qa"]["disk_mib"] = round(
        manifest["qa"]["disk_bytes"] / 1024 / 1024, 3
    )
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    source.close()
    strategic.close()
    print(
        f"{key}: Strategic {strategic_size}, {manifest['qa']['disk_mib']:.3f} MiB, "
        f"parent_mean={manifest['qa']['parent_mean_gate']}"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--maps", nargs="+", choices=tuple(MAPS.keys()), default=tuple(MAPS.keys())
    )
    parser.add_argument(
        "--bake-style",
        action="store_true",
        help="Bake color/edge/vignette into tiles. Default keeps source pixels exact and applies style in runtime shader.",
    )
    parser.add_argument(
        "--operational-size",
        type=int,
        default=7680,
        choices=(4352, 6144, 7168, 7680),
        help="Square Operational parent resolution; 7680 is the approved production default, lower sizes are research sweeps only.",
    )
    parser.add_argument(
        "--operational-only",
        action="store_true",
        help="Copy an existing validated raw pyramid and rebuild only Operational tiles.",
    )
    parser.add_argument(
        "--strategic-size",
        type=int,
        default=1520,
        choices=(1024, 1280, 1344, 1408, 1472, 1504, 1520, 1536),
        help="Square Strategic resolution; 1520 is the approved fidelity/memory candidate, while the other sizes are research sweeps.",
    )
    parser.add_argument(
        "--strategic-only",
        action="store_true",
        help="Copy an existing validated raw pyramid and rebuild only Strategic.",
    )
    parser.add_argument(
        "--base-root",
        type=Path,
        default=ROOT / "resources" / "maps" / "basemap_tiles",
        help="Base pyramid copied by --operational-only.",
    )
    args = parser.parse_args()
    runtime_output = (ROOT / "resources" / "maps" / "basemap_tiles").resolve()
    if args.bake_style and args.output.resolve() == runtime_output:
        parser.error("styled tiles are research-only and cannot overwrite runtime basemap_tiles")
    if args.operational_only and args.bake_style:
        parser.error("--operational-only cannot be combined with --bake-style")
    if args.strategic_only and args.bake_style:
        parser.error("--strategic-only cannot be combined with --bake-style")
    if args.operational_only and args.strategic_only:
        parser.error("--operational-only and --strategic-only are mutually exclusive")
    if args.operational_only and args.output.resolve() == args.base_root.resolve():
        parser.error("--operational-only output must differ from --base-root")
    if args.strategic_only and args.output.resolve() == args.base_root.resolve():
        parser.error("--strategic-only output must differ from --base-root")
    args.output.mkdir(parents=True, exist_ok=True)
    if args.operational_only:
        manifests: dict[str, dict[str, Any]] = {
            key: build_operational_only(
                key,
                MAPS[key],
                args.output,
                args.base_root,
                args.operational_size,
            )
            for key in args.maps
        }
    elif args.strategic_only:
        manifests = {
            key: build_strategic_only(
                key,
                MAPS[key],
                args.output,
                args.base_root,
                args.strategic_size,
            )
            for key in args.maps
        }
    else:
        manifests = {
            key: build_map(
                key,
                MAPS[key],
                args.output,
                args.bake_style,
                args.operational_size,
                args.strategic_size,
            )
            for key in args.maps
        }
    for key in MAPS:
        manifest_path = args.output / key / "manifest.json"
        if key not in manifests and manifest_path.exists():
            existing = json.loads(manifest_path.read_text(encoding="utf-8"))
            if bool(existing.get("style_baked", False)) == args.bake_style:
                manifests[key] = existing
    total_bytes = sum(manifest["qa"]["disk_bytes"] for manifest in manifests.values())
    summary = {
        "maps": {
            key: {
                "style_profile_id": manifest["style_profile_id"],
                **manifest["qa"],
            }
            for key, manifest in manifests.items()
        },
        "total_bytes": total_bytes,
        "total_mib": round(total_bytes / 1024 / 1024, 3),
        "all_seams_pass": all(
            manifest["qa"]["detail_seams"]["pass"]
            and manifest["qa"]["operational_seams"]["pass"]
            for manifest in manifests.values()
        ),
        "all_parent_mean_gates_pass": all(
            manifest["qa"]["parent_mean_gate"] for manifest in manifests.values()
        ),
        "disk_budget_68_mib_pass": total_bytes <= 68 * 1024 * 1024,
    }
    (args.output / "qa_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
