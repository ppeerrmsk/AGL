#!/usr/bin/env python3
"""Audit PNG/streamed basemap pairs captured from the full Survivor viewport.

This is deliberately separate from the isolated basemap capture audit: it keeps
weather, gameplay overlays, aircraft and HUD in the comparison so regressions in
the real composition path cannot be hidden by a clean renderer-only bench.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAPTURE_DIR = ROOT / "bench" / "results"
DEFAULT_OUTPUT = ROOT / "tmp" / "map_visual_qa" / "raster_survivor_composite_audit.json"
MAPS = ("tokyo", "desert", "ocean")

MAX_ABS_LUMA_DELTA = 0.005
MAX_LOWPASS_RGB_MAE = 0.004
MAX_FLAT_CHANNEL_DELTA = 4.0 / 255.0
MIN_LOWPASS_LUMA_CORRELATION = 0.98


def _rgb(path: Path) -> np.ndarray:
	return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def _luma(rgb: np.ndarray) -> np.ndarray:
	return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def _flat_cell_delta(reference: np.ndarray, candidate: np.ndarray) -> tuple[int, float]:
	reference_luma = _luma(reference)
	candidate_luma = _luma(candidate)
	reference_edge = np.maximum(
		np.abs(np.diff(reference_luma, axis=0, prepend=reference_luma[:1])),
		np.abs(np.diff(reference_luma, axis=1, prepend=reference_luma[:, :1])),
	)
	candidate_edge = np.maximum(
		np.abs(np.diff(candidate_luma, axis=0, prepend=candidate_luma[:1])),
		np.abs(np.diff(candidate_luma, axis=1, prepend=candidate_luma[:, :1])),
	)
	flat_mask = (reference_edge < 0.012) & (candidate_edge < 0.012)
	max_delta = 0.0
	valid_cells = 0
	height, width = reference.shape[:2]
	for row in range(8):
		y0 = round(row * height / 8)
		y1 = round((row + 1) * height / 8)
		for column in range(8):
			x0 = round(column * width / 8)
			x1 = round((column + 1) * width / 8)
			cell_mask = flat_mask[y0:y1, x0:x1]
			if int(cell_mask.sum()) < max(32, round(cell_mask.size * 0.10)):
				continue
			reference_mean = reference[y0:y1, x0:x1][cell_mask].mean(axis=0)
			candidate_mean = candidate[y0:y1, x0:x1][cell_mask].mean(axis=0)
			max_delta = max(max_delta, float(np.abs(candidate_mean - reference_mean).max()))
			valid_cells += 1
	return valid_cells, max_delta


def _pair_metrics(reference_path: Path, candidate_path: Path) -> dict[str, object]:
	for path in (reference_path, candidate_path):
		if not path.is_file():
			raise FileNotFoundError(path)
	reference = _rgb(reference_path)
	candidate = _rgb(candidate_path)
	if reference.shape != candidate.shape:
		raise ValueError(
			f"capture size mismatch: {reference_path.name} {reference.shape} != "
			f"{candidate_path.name} {candidate.shape}"
		)
	reference_low = np.asarray(
		Image.open(reference_path).convert("RGB").filter(ImageFilter.GaussianBlur(1.5)),
		dtype=np.float32,
	) / 255.0
	candidate_low = np.asarray(
		Image.open(candidate_path).convert("RGB").filter(ImageFilter.GaussianBlur(1.5)),
		dtype=np.float32,
	) / 255.0
	luma_delta = float(_luma(candidate).mean() - _luma(reference).mean())
	lowpass_rgb_mae = float(np.abs(candidate_low - reference_low).mean())
	correlation = float(
		np.corrcoef(_luma(reference_low).ravel(), _luma(candidate_low).ravel())[0, 1]
	)
	flat_cells, flat_delta = _flat_cell_delta(reference, candidate)
	checks = {
		"luma": abs(luma_delta) <= MAX_ABS_LUMA_DELTA,
		"lowpass_rgb": lowpass_rgb_mae <= MAX_LOWPASS_RGB_MAE,
		"flat_color": flat_cells > 0 and flat_delta <= MAX_FLAT_CHANNEL_DELTA,
		"lowpass_structure": math.isfinite(correlation)
		and correlation >= MIN_LOWPASS_LUMA_CORRELATION,
	}
	return {
		"reference": reference_path.name,
		"candidate": candidate_path.name,
		"size": [int(reference.shape[1]), int(reference.shape[0])],
		"candidate_minus_reference_luma": round(luma_delta, 6),
		"lowpass_rgb_mae_radius_1_5": round(lowpass_rgb_mae, 6),
		"lowpass_luma_correlation_radius_1_5": round(correlation, 6),
		"flat_8x8_cells": flat_cells,
		"flat_8x8_max_channel_mean_delta": round(flat_delta, 6),
		"checks": checks,
		"pass": all(checks.values()),
	}


def audit(capture_dir: Path) -> dict[str, object]:
	maps: dict[str, object] = {}
	for map_key in MAPS:
		maps[map_key] = _pair_metrics(
			capture_dir / f"map_preview_{map_key}_visual_latest.png",
			capture_dir / f"map_raster_{map_key}_visual_latest.png",
		)
	return {
		"pass": all(bool(entry["pass"]) for entry in maps.values()),
		"thresholds": {
			"max_abs_luma_delta": MAX_ABS_LUMA_DELTA,
			"max_lowpass_rgb_mae_radius_1_5": MAX_LOWPASS_RGB_MAE,
			"max_flat_8x8_channel_mean_delta": round(MAX_FLAT_CHANNEL_DELTA, 6),
			"min_lowpass_luma_correlation_radius_1_5": MIN_LOWPASS_LUMA_CORRELATION,
		},
		"maps": maps,
	}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("capture_dir", nargs="?", type=Path, default=DEFAULT_CAPTURE_DIR)
	parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
	args = parser.parse_args()
	report = audit(args.capture_dir.resolve())
	output = args.output.resolve()
	output.parent.mkdir(parents=True, exist_ok=True)
	output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps(report, ensure_ascii=False, indent=2))
	print(f"wrote {output}")
	return 0 if bool(report["pass"]) else 1


if __name__ == "__main__":
	raise SystemExit(main())
