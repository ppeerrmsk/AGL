"""Audit canonical aircraft-volume identities, sources, production status and coverage."""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

from audit_aircraft_silhouettes import (
    DISPLAY_NAME_RE,
    ROOT,
    aircraft_param_files,
)


SILHOUETTE_CATALOG = ROOT / "scripts" / "aircraft_silhouette_catalog.gd"
VOLUME_CATALOG = ROOT / "scripts" / "experiments" / "volume_aircraft_catalog.gd"
MOUNT_CATALOG = ROOT / "scripts" / "experiments" / "volume_aircraft_mount_catalog.gd"
SILHOUETTE_MANIFEST = ROOT / "resources" / "aircraft_silhouettes" / "reference_manifest.json"
VOLUME_MANIFEST = ROOT / "resources" / "aircraft_volume_models" / "reference_manifest.json"
FORMAL_OVERLAY = ROOT / "scripts" / "rendering" / "aircraft_volume_overlay.gd"
SURVIVOR_MODE = ROOT / "scripts" / "survivor" / "survivor_mode.gd"
AIRFRAME_LIVERY_SHADER = ROOT / "resources" / "shaders" / "volume_aircraft_livery.gdshader"
COLOR_RE_TEMPLATE = r"^{name}\s*=\s*Color\(([^)]+)\)"


def dictionary_pairs(source: str, start: str, end: str) -> dict[str, str]:
    block = source.split(start, 1)[1].split(end, 1)[0]
    return dict(re.findall(r'"([^"\n]+)"\s*:\s*"([^"\n]+)"', block))


def string_array(source: str, constant_name: str) -> list[str]:
    match = re.search(
        rf"const {re.escape(constant_name)}:\s*Array\[String\]\s*=\s*\[(.*?)\]",
        source,
        re.DOTALL,
    )
    if not match:
        return []
    return re.findall(r'"([^"\n]+)"', match.group(1))


def supported_keys(source: str) -> list[str]:
    return string_array(source, "SUPPORTED_KEYS")


def role_for(path: Path, display_name: str) -> str:
    relative = path.relative_to(ROOT).as_posix()
    if "/player/" in relative or Path(relative).name.startswith("playable_"):
        return "player"
    if Path(relative).name.startswith("enemy_"):
        if display_name in {
            "F-47", "F-14", "Mother Goose", "Hyper-A G0", "Hyper-A G1",
            "Hyper-A G2", "Hyper-A G3",
        }:
            return "boss"
        return "enemy"
    if Path(relative).name.startswith("friendly_") or display_name == "DRONE":
        return "ally"
    return "special"


def resource_color(resource: str, name: str) -> tuple[float, float, float, float] | None:
    match = re.search(COLOR_RE_TEMPLATE.format(name=re.escape(name)), resource, re.MULTILINE)
    if not match:
        return None
    values = [float(value.strip()) for value in match.group(1).split(",")]
    if len(values) != 4:
        return None
    return values[0], values[1], values[2], values[3]


def main() -> None:
    silhouette_source = SILHOUETTE_CATALOG.read_text(encoding="utf-8")
    display_keys = dictionary_pairs(
        silhouette_source, "const DISPLAY_KEYS", "const LEGACY_DISPLAY_NAMES"
    )
    legacy_keys = dictionary_pairs(
        silhouette_source, "const LEGACY_MODEL_KEYS", "const DRAW_SCALE"
    )
    canonical_keys = set(display_keys.values()) | set(legacy_keys.values())
    volume_manifest = json.loads(VOLUME_MANIFEST.read_text(encoding="utf-8"))
    silhouette_manifest = json.loads(SILHOUETTE_MANIFEST.read_text(encoding="utf-8"))["aircraft"]
    manifest_airframes = volume_manifest["airframes"]
    volume_source = VOLUME_CATALOG.read_text(encoding="utf-8")
    produced = supported_keys(volume_source)
    body_lod_excluded = string_array(volume_source, "BODY_LOD_EXCLUDED_KEYS")
    body_lod_keys = set(produced) - set(body_lod_excluded)
    mount_source = MOUNT_CATALOG.read_text(encoding="utf-8")
    mount_kinds = string_array(mount_source, "SUPPORTED_KINDS")
    aircraft_mount_kinds = string_array(mount_source, "AIRCRAFT_KINDS")
    errors: list[str] = []

    if set(manifest_airframes) != canonical_keys:
        errors.append(
            "volume manifest key drift: "
            f"missing={sorted(canonical_keys - set(manifest_airframes))} "
            f"extra={sorted(set(manifest_airframes) - canonical_keys)}"
        )
    if len(produced) != len(set(produced)):
        errors.append("SUPPORTED_KEYS contains duplicates")
    unknown_produced = sorted(set(produced) - canonical_keys)
    if unknown_produced:
        errors.append(f"produced keys are not runtime identities: {unknown_produced}")
    unknown_lod_exclusions = sorted(set(body_lod_excluded) - set(produced))
    if unknown_lod_exclusions:
        errors.append(f"body LOD exclusions are not produced identities: {unknown_lod_exclusions}")
    if body_lod_excluded:
        errors.append(f"visual body LOD must cover every produced aircraft: {body_lod_excluded}")
    budgets = volume_manifest.get("budgets", {})
    if (
        "const BODY_LOD_MEDIUM_TRIANGLE_BUDGET := 320" not in volume_source
        or "const BODY_LOD_LOW_TRIANGLE_BUDGET := 128" not in volume_source
        or "static func build_runtime_lod" not in volume_source
        or "static func _build_medium_body_lod" not in volume_source
        or "static func _build_far_body_lod" not in volume_source
        or budgets.get("lod1_triangle_max") != 320
        or budgets.get("lod2_triangle_max") != 128
    ):
        errors.append("dedicated body LOD1/LOD2 catalog contract is not fully wired")

    legacy_mount_kinds = {
        "gun", "missile", "secondary_missile", "rocket", "flare",
        "torpedo", "loyal_wingman",
    }
    resource_equipment_kinds: set[str] = set()
    for equipment_path in (ROOT / "resources").rglob("*.tres"):
        resource_equipment_kinds.update(re.findall(
            r'^equipment_kind\s*=\s*"([^"\n]+)"',
            equipment_path.read_text(encoding="utf-8"),
            re.MULTILINE,
        ))
    required_mount_kinds = legacy_mount_kinds | resource_equipment_kinds
    missing_mount_kinds = sorted(required_mount_kinds - set(aircraft_mount_kinds))
    if missing_mount_kinds:
        errors.append(f"formal equipment kinds without 3D mount mapping: {missing_mount_kinds}")
    if set(mount_kinds) != set(aircraft_mount_kinds) | {"rotor"}:
        errors.append("mount mesh catalog and Aircraft render-kind catalog drift")
    slot_block = mount_source.split("const NORMALIZED_SLOTS", 1)[1].split(
        "static var _meshes", 1
    )[0]
    slot_kinds = set(re.findall(r'^\s*"([^"\n]+)"\s*:\s*\[', slot_block, re.MULTILINE))
    if slot_kinds != set(aircraft_mount_kinds):
        errors.append(
            "normalized mount slots drift: "
            f"missing={sorted(set(aircraft_mount_kinds) - slot_kinds)} "
            f"extra={sorted(slot_kinds - set(aircraft_mount_kinds))}"
        )

    display_paths: dict[str, list[Path]] = defaultdict(list)
    key_paths: dict[str, list[Path]] = defaultdict(list)
    missing_display_names: dict[str, list[str]] = defaultdict(list)
    dual_livery_resources = 0
    for path in aircraft_param_files():
        resource = path.read_text(encoding="utf-8").split("[resource]", 1)[-1]
        match = DISPLAY_NAME_RE.search(resource)
        if not match:
            continue
        display_name = match.group(1)
        display_paths[display_name].append(path)
        key = display_keys.get(display_name) or legacy_keys.get(display_name)
        if not key:
            missing_display_names[display_name].append(path.relative_to(ROOT).as_posix())
        else:
            key_paths[key].append(path)
        wing_color = resource_color(resource, "wing_color")
        if wing_color is not None and wing_color[3] > 0.01:
            dual_livery_resources += 1
            icon_color = resource_color(resource, "icon_color")
            if icon_color is None or any(channel <= 0.0001 for channel in icon_color[:3]):
                errors.append(
                    f"{path.relative_to(ROOT).as_posix()}: dual-livery ratio requires positive icon RGB"
                )
    if missing_display_names:
        errors.append(f"formal AircraftParams without canonical model key: {dict(missing_display_names)}")

    for key, record in manifest_airframes.items():
        reference = record.get("reference", {})
        kind = reference.get("kind")
        if kind == "silhouette_manifest":
            source_key = reference.get("key")
            if source_key != key or source_key not in silhouette_manifest:
                errors.append(f"{key}: broken silhouette manifest reference")
        elif kind == "project_concept":
            if reference.get("license") != "AGL project-authored":
                errors.append(f"{key}: project concept license boundary missing")
            if not reference.get("source_path") or not reference.get("fidelity"):
                errors.append(f"{key}: project concept source/fidelity missing")
        else:
            errors.append(f"{key}: unknown reference kind {kind!r}")

        status = str(record.get("production_status", ""))
        if key in produced:
            if status == "planned":
                errors.append(f"{key}: produced mesh is still marked planned")
            editable = str(record.get("editable_source") or "")
            if not editable.startswith("res://") or not (ROOT / editable[6:]).is_file():
                errors.append(f"{key}: produced mesh has no valid editable source")
        elif status.startswith("geometry_complete"):
            errors.append(f"{key}: manifest claims geometry but catalog does not build it")

    runtime_aliases = volume_manifest.get("runtime_aliases", {})
    awacs = runtime_aliases.get("AWACS", {})
    awacs_source = (ROOT / "scripts" / "events" / "awacs_support_event.gd").read_text(encoding="utf-8")
    if awacs.get("canonical_key") != "tu160" or 'set_meta("airframe_label"' not in awacs_source:
        errors.append("AWACS runtime rename does not preserve the Tu-160 canonical identity")

    overlay_source = FORMAL_OVERLAY.read_text(encoding="utf-8")
    survivor_source = SURVIVOR_MODE.read_text(encoding="utf-8")
    probe_source = (ROOT / "scripts" / "experiments" / "volume_world_probe.gd").read_text(encoding="utf-8")
    formal_wiring = (
        'const FORMAL_SCENARIO := "volume_3d_formal"' in overlay_source
        and "transparent_bg = true" in overlay_source
        and '"include_map": false' in overlay_source
        and "AircraftVolumeOverlayScript.new()" in survivor_source
        and "_aircraft_volume_overlay.setup(self)" in survivor_source
        and AIRFRAME_LIVERY_SHADER.is_file()
        and "use_custom_data = true" in probe_source
        and "BODY_LOD_ROUTE_PREFIX" in probe_source
        and "BODY_LOD2_ROUTE_PREFIX" in probe_source
        and "body_lod_level_for" in probe_source
        and "body_detail_exempt_for" not in probe_source
        and "mount_detail_exempt_for" not in probe_source
        and "key_unit" not in probe_source
    )
    if not formal_wiring:
        errors.append("main-menu Survivor is not wired to the transparent formal aircraft renderer")

    if errors:
        print("AIRCRAFT VOLUME MODEL AUDIT: FAIL")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)

    qa_complete = sum(
        1 for record in manifest_airframes.values() if all(record.get("qa", {}).values())
    )
    integrated = sum(
        1 for record in manifest_airframes.values()
        if record.get("runtime_integration") == "formal_default"
    )
    print(
        "AIRCRAFT VOLUME MODEL AUDIT: PASS "
        f"({len(display_paths)} AircraftParams display names, {len(canonical_keys)} canonical keys, "
        f"{len(produced)} LOD0 meshes built, {len(body_lod_keys)} dedicated LOD1 meshes, "
        f"{len(body_lod_keys)} dedicated LOD2 meshes, "
        f"{len(mount_kinds)} shared mount meshes, "
        f"{qa_complete} four-view QA complete, {dual_livery_resources} dual-livery resources, "
        f"{integrated} formal-default integrations)"
    )
    print("key\troles\tresources\tstatus\tqa\truntime")
    for key in sorted(canonical_keys):
        paths = key_paths.get(key, [])
        roles = sorted({role_for(path, next(
            name for name, candidates in display_paths.items() if path in candidates
        )) for path in paths})
        record = manifest_airframes[key]
        qa = record.get("qa", {})
        qa_count = sum(bool(qa.get(view, False)) for view in ("top", "side", "front", "gameplay"))
        print(
            f"{key}\t{','.join(roles) or 'runtime-only'}\t{len(paths)}\t"
            f"{record['production_status']}\t{qa_count}/4\t{record['runtime_integration']}"
        )


if __name__ == "__main__":
    main()
