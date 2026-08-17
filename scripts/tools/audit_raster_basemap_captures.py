#!/usr/bin/env python3
"""Audit paired Godot captures for the streamed raster basemap candidate.

The visual runner owns rendering. This tool only compares its same-camera PNG
pairs and rejects palette, low-frequency structure, LOD transition, or resident
tile regressions. Outputs stay beside the temporary captures by default.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAPTURE_DIR = ROOT / "tmp" / "map_visual_qa" / "raster"
MAPS = ("tokyo", "desert", "ocean")
PRIMARY_VIEWS = ("full", "operational", "battle", "detail", "landmark", "tab")
LOWPASS_LIMITS = {
    "full": 0.007,
    "operational": 0.006,
    "battle": 0.004,
    "detail": 0.004,
    "landmark": 0.004,
    "tab": 0.003,
    "operational_grid": 0.006,
}
MEAN_LUMA_LIMIT = 0.005
MEAN_RGB_CHANNEL_LIMIT = 0.004
FLAT_COLOR_LIMIT = 4.0 / 255.0
ZOOM_LUMA_LIMIT = 0.01
ZOOM_REFERENCE_RESIDUAL_LIMIT = 0.005
ZOOM_EDGE_RELATIVE_LIMIT = 0.10
TRANSITION_LUMA_STEP_LIMIT = 0.005
TRANSITION_EDGE_RELATIVE_STEP_LIMIT = 0.18
TRANSITION_ALPHA_STEP_60HZ_LIMIT = 0.07
HARD_RESIDENT_LIMIT = 16
ISOLATED_DARK_RATIO_LIMIT = 1.05
STRUCTURE_REFERENCE_P99_MIN = 0.007
STRUCTURE_F1_LIMIT = 0.80
STRUCTURE_SCALES = (
    {"name": "structure", "blur_radius": 3.0, "percentile": 92.0, "match_radius": 3},
    {"name": "silhouette", "blur_radius": 5.0, "percentile": 94.0, "match_radius": 4},
)


def rgb_array(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0


def lowpass_array(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        blurred = image.convert("RGB").filter(ImageFilter.GaussianBlur(1.5))
        return np.asarray(blurred, dtype=np.float32) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def structural_edge_mask(
    path: Path,
    blur_radius: float,
    percentile: float,
) -> tuple[np.ndarray, float]:
    with Image.open(path) as image:
        blurred = image.convert("RGB").filter(ImageFilter.GaussianBlur(blur_radius))
        value = luma(np.asarray(blurred, dtype=np.float32) / 255.0)
    gradient = np.hypot(
        np.diff(value, axis=1, append=value[:, -1:]),
        np.diff(value, axis=0, append=value[-1:, :]),
    )
    positive = gradient[gradient > 1e-5]
    if not positive.size:
        return np.zeros_like(gradient, dtype=bool), 0.0
    threshold = float(np.percentile(positive, percentile))
    p99 = float(np.percentile(positive, 99.0))
    return gradient >= threshold, p99


def dilate_edge_mask(mask: np.ndarray, radius: int) -> np.ndarray:
    image = Image.fromarray(mask.astype(np.uint8) * 255, mode="L")
    return np.asarray(image.filter(ImageFilter.MaxFilter(radius * 2 + 1))) > 0


def structural_edge_score(
    reference_path: Path,
    candidate_path: Path,
    scale: dict,
) -> dict:
    reference, reference_p99 = structural_edge_mask(
        reference_path,
        float(scale["blur_radius"]),
        float(scale["percentile"]),
    )
    candidate, candidate_p99 = structural_edge_mask(
        candidate_path,
        float(scale["blur_radius"]),
        float(scale["percentile"]),
    )
    radius = int(scale["match_radius"])
    matched_reference = reference & dilate_edge_mask(candidate, radius)
    matched_candidate = candidate & dilate_edge_mask(reference, radius)
    recall = float(matched_reference.sum() / max(int(reference.sum()), 1))
    precision = float(matched_candidate.sum() / max(int(candidate.sum()), 1))
    f1 = 2.0 * precision * recall / max(precision + recall, 1e-8)
    return {
        "precision": round(precision, 6),
        "recall": round(recall, 6),
        "f1": round(f1, 6),
        "reference_p99": round(reference_p99, 6),
        "candidate_p99": round(candidate_p99, 6),
    }


def isolated_dark_density(path: Path) -> float:
    """Measure isolated black-dot aliasing without treating continuous roads as noise."""
    value = luma(rgb_array(path))
    smooth = luma(lowpass_array(path))
    with Image.open(path) as image:
        median_rgb = np.asarray(
            image.convert("RGB").filter(ImageFilter.MedianFilter(3)),
            dtype=np.float32,
        ) / 255.0
    median = luma(median_rgb)
    surface = smooth > 0.18
    isolated = surface & ((median - value) > 0.07)
    return float(isolated.sum() / max(int(surface.sum()), 1))


def center_luma(path: Path, crop_fraction: float = 0.42) -> float:
    rgb = rgb_array(path)
    height, width = rgb.shape[:2]
    crop_w = round(width * crop_fraction)
    crop_h = round(height * crop_fraction)
    x0 = (width - crop_w) // 2
    y0 = (height - crop_h) // 2
    return float(luma(rgb[y0 : y0 + crop_h, x0 : x0 + crop_w]).mean())


def center_lowpass_gradient(path: Path, crop_fraction: float = 0.42) -> float:
    rgb = lowpass_array(path)
    height, width = rgb.shape[:2]
    crop_w = round(width * crop_fraction)
    crop_h = round(height * crop_fraction)
    x0 = (width - crop_w) // 2
    y0 = (height - crop_h) // 2
    value = luma(rgb[y0 : y0 + crop_h, x0 : x0 + crop_w])
    gradient = np.hypot(
        np.diff(value, axis=1, append=value[:, -1:]),
        np.diff(value, axis=0, append=value[-1:, :]),
    )
    return float(gradient.mean() / max(value.mean(), 1e-8))


def flat_color_delta(reference: np.ndarray, candidate: np.ndarray) -> tuple[int, float]:
    reference_luma = luma(reference)
    candidate_luma = luma(candidate)
    reference_edge = np.maximum(
        np.abs(np.diff(reference_luma, axis=0, prepend=reference_luma[:1])),
        np.abs(np.diff(reference_luma, axis=1, prepend=reference_luma[:, :1])),
    )
    candidate_edge = np.maximum(
        np.abs(np.diff(candidate_luma, axis=0, prepend=candidate_luma[:1])),
        np.abs(np.diff(candidate_luma, axis=1, prepend=candidate_luma[:, :1])),
    )
    flat_mask = (reference_edge < 0.012) & (candidate_edge < 0.012)
    flat_cells = 0
    worst = 0.0
    height, width = reference.shape[:2]
    for row in range(8):
        y0 = round(row * height / 8)
        y1 = round((row + 1) * height / 8)
        for column in range(8):
            x0 = round(column * width / 8)
            x1 = round((column + 1) * width / 8)
            mask = flat_mask[y0:y1, x0:x1]
            if int(mask.sum()) < max(32, round(mask.size * 0.10)):
                continue
            reference_mean = reference[y0:y1, x0:x1][mask].mean(axis=0)
            candidate_mean = candidate[y0:y1, x0:x1][mask].mean(axis=0)
            worst = max(worst, float(np.abs(candidate_mean - reference_mean).max()))
            flat_cells += 1
    return flat_cells, worst


def compare_pair(
    reference_path: Path,
    candidate_path: Path,
    limit: float,
    check_isolated_dark: bool = False,
) -> dict:
    reference = rgb_array(reference_path)
    candidate = rgb_array(candidate_path)
    if reference.shape != candidate.shape:
        raise ValueError(
            f"capture size mismatch: {reference_path.name} {reference.shape} != "
            f"{candidate_path.name} {candidate.shape}"
        )
    reference_lowpass = lowpass_array(reference_path)
    candidate_lowpass = lowpass_array(candidate_path)
    flat_cells, flat_delta = flat_color_delta(reference, candidate)
    mean_luma_delta = float(luma(candidate).mean() - luma(reference).mean())
    mean_rgb_delta = candidate.mean(axis=(0, 1)) - reference.mean(axis=(0, 1))
    mean_rgb_max_delta = float(np.abs(mean_rgb_delta).max())
    lowpass_mae = float(np.abs(candidate_lowpass - reference_lowpass).mean())
    reference_isolated_dark = 0.0
    candidate_isolated_dark = 0.0
    isolated_dark_ratio = 0.0
    if check_isolated_dark:
        reference_isolated_dark = isolated_dark_density(reference_path)
        candidate_isolated_dark = isolated_dark_density(candidate_path)
        isolated_dark_ratio = candidate_isolated_dark / max(reference_isolated_dark, 1e-8)
    checks = {
        "mean_luma": abs(mean_luma_delta) <= MEAN_LUMA_LIMIT,
        "mean_rgb_channels": mean_rgb_max_delta <= MEAN_RGB_CHANNEL_LIMIT,
        "lowpass_rgb_mae": lowpass_mae <= limit,
        "flat_color": flat_cells > 0 and flat_delta <= FLAT_COLOR_LIMIT,
    }
    if check_isolated_dark:
        checks["isolated_dark_not_increased"] = (
            isolated_dark_ratio <= ISOLATED_DARK_RATIO_LIMIT
        )
    result = {
        "mean_luma_delta": round(mean_luma_delta, 6),
        "mean_rgb_delta": [round(float(value), 6) for value in mean_rgb_delta],
        "mean_rgb_max_channel_delta": round(mean_rgb_max_delta, 6),
        "mean_rgb_channel_limit": MEAN_RGB_CHANNEL_LIMIT,
        "rgb_mae": round(float(np.abs(candidate - reference).mean()), 6),
        "lowpass_rgb_mae": round(lowpass_mae, 6),
        "lowpass_limit": limit,
        "flat_8x8_cells": flat_cells,
        "flat_8x8_max_channel_delta": round(flat_delta, 6),
        "checks": checks,
        "pass": all(checks.values()),
    }
    if check_isolated_dark:
        result.update({
            "reference_isolated_dark_density": round(reference_isolated_dark, 7),
            "candidate_isolated_dark_density": round(candidate_isolated_dark, 7),
            "isolated_dark_ratio": round(isolated_dark_ratio, 6),
        })
    return result


def view_limit(view_id: str) -> float:
    if view_id.startswith("operational_grid_"):
        return LOWPASS_LIMITS["operational_grid"]
    return LOWPASS_LIMITS[view_id]


def audit(capture_dir: Path) -> dict:
    manifest_path = capture_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    views = list(PRIMARY_VIEWS) + [f"operational_grid_{index:02d}" for index in range(9)]
    comparisons: dict[str, dict[str, dict]] = {}
    for map_key in MAPS:
        comparisons[map_key] = {}
        for view_id in views:
            comparisons[map_key][view_id] = compare_pair(
                capture_dir / f"{map_key}_reference_{view_id}.png",
                capture_dir / f"{map_key}_candidate_{view_id}.png",
                view_limit(view_id),
                view_id in ("full", "tab"),
            )

    structural_rows = []
    for map_key in MAPS:
        for view_id in views:
            if view_id in ("full", "tab"):
                continue
            reference_path = capture_dir / f"{map_key}_reference_{view_id}.png"
            candidate_path = capture_dir / f"{map_key}_candidate_{view_id}.png"
            scores = {
                str(scale["name"]): structural_edge_score(
                    reference_path, candidate_path, scale
                )
                for scale in STRUCTURE_SCALES
            }
            applicable = (
                scores["structure"]["reference_p99"]
                >= STRUCTURE_REFERENCE_P99_MIN
            )
            passed = not applicable or all(
                score["f1"] >= STRUCTURE_F1_LIMIT for score in scores.values()
            )
            structural_rows.append({
                "map": map_key,
                "view": view_id,
                "applicable": applicable,
                "scores": scores,
                "pass": passed,
            })
    applicable_structural_rows = [
        row for row in structural_rows if row["applicable"]
    ]
    structural_gate = {
        "minimum_reference_structure_p99": STRUCTURE_REFERENCE_P99_MIN,
        "f1_limit": STRUCTURE_F1_LIMIT,
        "scales": list(STRUCTURE_SCALES),
        "applicable_views": len(applicable_structural_rows),
        "worst_structure_f1": round(min(
            (row["scores"]["structure"]["f1"] for row in applicable_structural_rows),
            default=1.0,
        ), 6),
        "worst_silhouette_f1": round(min(
            (row["scores"]["silhouette"]["f1"] for row in applicable_structural_rows),
            default=1.0,
        ), 6),
        "rows": structural_rows,
        "pass": bool(applicable_structural_rows)
        and all(row["pass"] for row in applicable_structural_rows),
    }

    manifest_views = manifest.get("views", [])
    resident_values = [
        int(entry.get("resident_tiles", 0))
        for entry in manifest_views
        if "resident_tiles" in entry
    ]
    session_peaks = [
        int(entry.get("raster_state", {}).get("peak_resident_tiles", 0))
        for entry in manifest_views
    ]
    resident_max = max(resident_values, default=0)
    session_peak = max(session_peaks, default=0)
    resident_gate = {
        "resident_max": resident_max,
        "session_peak": session_peak,
        "limit": HARD_RESIDENT_LIMIT,
        "pass": resident_max <= HARD_RESIDENT_LIMIT
        and session_peak <= HARD_RESIDENT_LIMIT,
    }

    # 两条路径的世界空间颗粒都必须时间稳定：同一主要战斗机位间隔
    # 0.5s 的两帧逐像素一致，防止任何主地图 shader 重新引入 TIME hash。
    temporal_rows = []
    for map_key in MAPS:
        for mode in ("reference", "candidate"):
            entries = [
                entry for entry in manifest_views
                if entry.get("map") == map_key
                and entry.get("mode") == f"{mode}_temporal"
            ]
            entries.sort(key=lambda entry: str(entry.get("id", "")))
            row = {
                "map": map_key,
                "mode": mode,
                "samples": len(entries),
                "pass": False,
            }
            if len(entries) == 2:
                paths = [capture_dir / str(entry["file"]) for entry in entries]
                images = [rgb_array(path) for path in paths]
                same_size = images[0].shape == images[1].shape
                max_channel_delta = (
                    float(np.abs(images[1] - images[0]).max()) if same_size else 1.0
                )
                hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
                row.update({
                    "files": [path.name for path in paths],
                    "same_size": same_size,
                    "sha256": hashes,
                    "same_sha256": hashes[0] == hashes[1],
                    "max_channel_delta": round(max_channel_delta, 8),
                    "pass": same_size
                    and hashes[0] == hashes[1]
                    and max_channel_delta == 0.0,
                })
            temporal_rows.append(row)
    temporal_gate = {
        "interval_s": 0.5,
        "max_channel_delta_limit": 0.0,
        "rows": temporal_rows,
        "pass": len(temporal_rows) == len(MAPS) * 2
        and all(bool(row["pass"]) for row in temporal_rows),
    }

    transition_entries = [
        entry for entry in manifest_views
        if entry.get("mode") == "candidate_transition"
    ]
    transition_checks = []
    transition_groups: dict[str, list[dict]] = {}
    for entry in transition_entries:
        state = entry.get("raster_state", {})
        visible = int(state.get("visible_tile_count", 0))
        required = len(state.get("required_keys", []))
        path = capture_dir / str(entry["file"])
        row = {
            "id": str(entry.get("id", "")),
            "sample_fraction": float(entry.get("sample_fraction", -1.0)),
            "visible_tiles": visible,
            "required_tiles": required,
            "center_mean_luma": round(center_luma(path), 6),
            "center_lowpass_gradient_per_luma": round(
                center_lowpass_gradient(path), 6
            ),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "pass": visible == required,
        }
        transition_checks.append(row)
        transition_groups.setdefault(str(entry.get("transition", "")), []).append(row)

    transition_sequences = []
    for label, rows in sorted(transition_groups.items()):
        rows.sort(key=lambda row: row["sample_fraction"])
        max_luma_step = 0.0
        max_edge_step = 0.0
        for previous, current in zip(rows, rows[1:]):
            max_luma_step = max(
                max_luma_step,
                abs(current["center_mean_luma"] - previous["center_mean_luma"]),
            )
            max_edge_step = max(
                max_edge_step,
                abs(
                    current["center_lowpass_gradient_per_luma"]
                    - previous["center_lowpass_gradient_per_luma"]
                )
                / max(previous["center_lowpass_gradient_per_luma"], 1e-8),
            )
        fractions = [round(row["sample_fraction"], 2) for row in rows]
        distinct_frames = len({row["sha256"] for row in rows}) == len(rows)
        sequence_pass = (
            len(rows) == 3
            and fractions == [0.25, 0.5, 0.75]
            and distinct_frames
            and max_luma_step <= TRANSITION_LUMA_STEP_LIMIT
            and max_edge_step <= TRANSITION_EDGE_RELATIVE_STEP_LIMIT
        )
        transition_sequences.append({
            "transition": label,
            "sample_fractions": fractions,
            "all_frames_distinct": distinct_frames,
            "max_adjacent_center_luma_delta": round(max_luma_step, 6),
            "luma_step_limit": TRANSITION_LUMA_STEP_LIMIT,
            "max_adjacent_lowpass_gradient_relative_delta": round(max_edge_step, 6),
            "gradient_relative_step_limit": TRANSITION_EDGE_RELATIVE_STEP_LIMIT,
            "pass": sequence_pass,
        })
    transition_duration_s = float(manifest.get("transition_duration_s", 0.0))
    transition_alpha_step_60hz = (
        math.pi / (2.0 * transition_duration_s * 60.0)
        if transition_duration_s > 0.0
        else float("inf")
    )
    transition_gate = {
        "checks": transition_checks,
        "sequences": transition_sequences,
        "duration_s": round(transition_duration_s, 6),
        "max_sine_alpha_step_60hz": round(transition_alpha_step_60hz, 6),
        "alpha_step_60hz_limit": TRANSITION_ALPHA_STEP_60HZ_LIMIT,
        "pass": bool(transition_checks)
        and bool(transition_sequences)
        and all(check["pass"] for check in transition_checks)
        and all(sequence["pass"] for sequence in transition_sequences)
        and transition_alpha_step_60hz <= TRANSITION_ALPHA_STEP_60HZ_LIMIT,
    }

    zoom_entries = [
        entry for entry in manifest_views if entry.get("mode") == "candidate_zoom"
    ]
    zoom_entries.sort(key=lambda entry: float(entry["zoom"]))
    reference_zoom_entries = [
        entry for entry in manifest_views if entry.get("mode") == "reference_zoom"
    ]
    reference_zoom_entries.sort(key=lambda entry: float(entry["zoom"]))
    reference_luma_by_zoom = {
        float(entry["zoom"]): center_luma(capture_dir / str(entry["file"]))
        for entry in reference_zoom_entries
    }
    reference_rows = []
    previous_reference_luma = None
    previous_reference_zoom = None
    max_reference_adjacent_delta = 0.0
    for entry in reference_zoom_entries:
        zoom = float(entry["zoom"])
        mean = reference_luma_by_zoom[zoom]
        row = {"zoom": zoom, "center_mean_luma": round(mean, 6)}
        if previous_reference_luma is not None:
            delta = mean - previous_reference_luma
            row["delta_from_previous"] = round(delta, 6)
            if zoom - float(previous_reference_zoom) <= 0.03:
                max_reference_adjacent_delta = max(
                    max_reference_adjacent_delta, abs(delta)
                )
        reference_rows.append(row)
        previous_reference_luma = mean
        previous_reference_zoom = zoom
    zoom_rows = []
    previous_luma = None
    previous_gradient = None
    previous_residual = None
    previous_zoom = None
    max_adjacent_delta = 0.0
    max_adjacent_gradient_delta = 0.0
    max_reference_residual_step = 0.0
    for entry in zoom_entries:
        zoom = float(entry["zoom"])
        path = capture_dir / str(entry["file"])
        mean = center_luma(path)
        gradient = center_lowpass_gradient(path)
        row = {
            "zoom": zoom,
            "center_mean_luma": round(mean, 6),
            "center_lowpass_gradient_per_luma": round(gradient, 6),
        }
        reference_mean = reference_luma_by_zoom.get(zoom)
        residual = None
        if reference_mean is not None:
            residual = mean - reference_mean
            row["reference_center_mean_luma"] = round(reference_mean, 6)
            row["candidate_minus_reference_luma"] = round(residual, 6)
        if previous_luma is not None:
            delta = mean - previous_luma
            row["delta_from_previous"] = round(delta, 6)
            if zoom - float(previous_zoom) <= 0.03:
                max_adjacent_delta = max(max_adjacent_delta, abs(delta))
                if residual is not None and previous_residual is not None:
                    residual_step = residual - previous_residual
                    row["reference_residual_delta_from_previous"] = round(
                        residual_step, 6
                    )
                    max_reference_residual_step = max(
                        max_reference_residual_step, abs(residual_step)
                    )
            if zoom - float(previous_zoom) <= 0.003:
                gradient_delta = abs(gradient - float(previous_gradient)) / max(
                    float(previous_gradient), 1e-8
                )
                row["gradient_relative_delta_from_previous"] = round(
                    gradient_delta, 6
                )
                max_adjacent_gradient_delta = max(
                    max_adjacent_gradient_delta, gradient_delta
                )
        zoom_rows.append(row)
        previous_luma = mean
        previous_gradient = gradient
        previous_residual = residual
        previous_zoom = zoom
    zoom_gate = {
        "samples": zoom_rows,
        "reference_samples": reference_rows,
        "max_adjacent_center_luma_delta": round(max_adjacent_delta, 6),
        "limit": ZOOM_LUMA_LIMIT,
        "max_reference_adjacent_center_luma_delta": round(
            max_reference_adjacent_delta, 6
        ),
        "max_candidate_minus_reference_residual_step": round(
            max_reference_residual_step, 6
        ),
        "reference_residual_limit": ZOOM_REFERENCE_RESIDUAL_LIMIT,
        "max_adjacent_lowpass_gradient_relative_delta": round(
            max_adjacent_gradient_delta, 6
        ),
        "gradient_relative_limit": ZOOM_EDGE_RELATIVE_LIMIT,
        "pass": bool(zoom_rows)
        and len(reference_luma_by_zoom) == len(zoom_rows)
        and max_adjacent_delta <= ZOOM_LUMA_LIMIT
        and max_reference_residual_step <= ZOOM_REFERENCE_RESIDUAL_LIMIT
        and max_adjacent_gradient_delta <= ZOOM_EDGE_RELATIVE_LIMIT,
    }

    comparison_pass = all(
        result["pass"]
        for map_results in comparisons.values()
        for result in map_results.values()
    )
    return {
        "schema_version": 2,
        "source_manifest": str(manifest_path.resolve()),
        "rendering_method": manifest.get("rendering_method", ""),
        "engine": manifest.get("engine", ""),
        "limits": {
            "mean_luma_delta": MEAN_LUMA_LIMIT,
            "flat_8x8_channel_delta": round(FLAT_COLOR_LIMIT, 6),
            "lowpass_rgb_mae": LOWPASS_LIMITS,
            "zoom_luma_delta": ZOOM_LUMA_LIMIT,
            "zoom_lowpass_gradient_relative_delta": ZOOM_EDGE_RELATIVE_LIMIT,
            "transition_luma_step": TRANSITION_LUMA_STEP_LIMIT,
            "transition_lowpass_gradient_relative_step": (
                TRANSITION_EDGE_RELATIVE_STEP_LIMIT
            ),
            "transition_alpha_step_60hz": TRANSITION_ALPHA_STEP_60HZ_LIMIT,
            "resident_tiles": HARD_RESIDENT_LIMIT,
            "temporal_max_channel_delta": 0.0,
            "isolated_dark_ratio": ISOLATED_DARK_RATIO_LIMIT,
            "structural_edge_f1": STRUCTURE_F1_LIMIT,
            "minimum_reference_structure_p99": STRUCTURE_REFERENCE_P99_MIN,
        },
        "comparisons": comparisons,
        "structural_gate": structural_gate,
        "resident_gate": resident_gate,
        "temporal_gate": temporal_gate,
        "transition_gate": transition_gate,
        "zoom_gate": zoom_gate,
        "pass": comparison_pass
        and structural_gate["pass"]
        and resident_gate["pass"]
        and temporal_gate["pass"]
        and transition_gate["pass"]
        and zoom_gate["pass"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture_dir", type=Path, nargs="?", default=DEFAULT_CAPTURE_DIR)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    capture_dir = args.capture_dir.resolve()
    report = audit(capture_dir)
    output = (args.output or capture_dir / "raster_visual_audit.json").resolve()
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "pass": report["pass"],
        "output": str(output),
        "structural_gate": {
            "applicable_views": report["structural_gate"]["applicable_views"],
            "worst_structure_f1": report["structural_gate"]["worst_structure_f1"],
            "worst_silhouette_f1": report["structural_gate"]["worst_silhouette_f1"],
            "limit": report["structural_gate"]["f1_limit"],
            "pass": report["structural_gate"]["pass"],
        },
        "resident_gate": report["resident_gate"],
        "temporal_gate": report["temporal_gate"],
        "transition_gate": report["transition_gate"],
        "zoom_gate": {
            "max_adjacent_center_luma_delta": report["zoom_gate"][
                "max_adjacent_center_luma_delta"
            ],
            "limit": report["zoom_gate"]["limit"],
            "max_reference_adjacent_center_luma_delta": report["zoom_gate"][
                "max_reference_adjacent_center_luma_delta"
            ],
            "max_candidate_minus_reference_residual_step": report["zoom_gate"][
                "max_candidate_minus_reference_residual_step"
            ],
            "reference_residual_limit": report["zoom_gate"][
                "reference_residual_limit"
            ],
            "max_adjacent_lowpass_gradient_relative_delta": report["zoom_gate"][
                "max_adjacent_lowpass_gradient_relative_delta"
            ],
            "gradient_relative_limit": report["zoom_gate"][
                "gradient_relative_limit"
            ],
            "pass": report["zoom_gate"]["pass"],
        },
    }, ensure_ascii=False, indent=2))
    return 0 if report["pass"] or args.allow_fail else 1


if __name__ == "__main__":
    raise SystemExit(main())
