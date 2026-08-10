#!/usr/bin/env python3
"""Score real Godot map captures and build a same-view comparison sheet.

The capture manifest is produced by map_visual_qa_runner.gd. This tool never
renders map content; it only rejects obvious runtime regressions and writes QA
artifacts beside the captures (normally under tmp/map_visual_qa/).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageStat


PRIMARY_VIEWS = (
    "full",
    "bay_operational",
    "tokyo_operational",
    "west_operational",
    "chiba_operational",
    "yokohama_gold",
    "yokohama_east",
    "kawasaki_west",
    "kawasaki_east",
    "detail_seam",
)
OPERATIONAL_VIEWS = {
    "full", "bay_operational", "tokyo_operational", "west_operational", "chiba_operational"
}
STRUCTURAL_DETAIL_VIEWS = {"yokohama_east", "detail_seam"}
PROGRESSION_VIEWS = ("020", "035", "050", "065", "080", "098")
WHEEL_VIEWS = ("050", "055", "061", "067", "073", "081", "089", "097")
SWEEP_VIEWS = tuple(f"{value:03d}" for value in range(500, 981, 20))


def image_stats(image: Image.Image) -> dict:
    rgb = image.convert("RGB")
    stat = ImageStat.Stat(rgb)
    luminance = rgb.convert("L")
    edge = luminance.filter(ImageFilter.FIND_EDGES)
    return {
        "mean_rgb": [round(value, 3) for value in stat.mean[:3]],
        "stddev_rgb": [round(value, 3) for value in stat.stddev[:3]],
        "mean_luminance": round(ImageStat.Stat(luminance).mean[0], 3),
        "edge_density": round(ImageStat.Stat(edge).mean[0], 3),
    }


def block_means(image: Image.Image, columns: int = 4, rows: int = 3) -> list[dict]:
    rgb = image.convert("RGB")
    blocks = []
    for row in range(rows):
        for column in range(columns):
            box = (
                round(column * rgb.width / columns),
                round(row * rgb.height / rows),
                round((column + 1) * rgb.width / columns),
                round((row + 1) * rgb.height / rows),
            )
            mean = ImageStat.Stat(rgb.crop(box)).mean[:3]
            blocks.append({
                "column": column,
                "row": row,
                "mean_rgb": [round(value, 3) for value in mean],
            })
    return blocks


def compare_pair(reference: Image.Image, candidate: Image.Image) -> dict:
    if reference.size != candidate.size:
        raise ValueError(f"capture size mismatch: {reference.size} != {candidate.size}")
    ref_stats = image_stats(reference)
    candidate_stats = image_stats(candidate)
    diff = ImageChops.difference(reference.convert("RGB"), candidate.convert("RGB"))
    diff_stat = ImageStat.Stat(diff)
    mean_delta = [
        round(candidate_stats["mean_rgb"][index] - ref_stats["mean_rgb"][index], 3)
        for index in range(3)
    ]
    edge_reference = max(float(ref_stats["edge_density"]), 0.001)
    reference_blocks = block_means(reference)
    candidate_blocks = block_means(candidate)
    block_deltas = []
    for reference_block, candidate_block in zip(reference_blocks, candidate_blocks):
        delta = [
            round(candidate_block["mean_rgb"][index] - reference_block["mean_rgb"][index], 3)
            for index in range(3)
        ]
        block_deltas.append({
            "column": reference_block["column"],
            "row": reference_block["row"],
            "mean_rgb_delta": delta,
            "max_abs_channel_delta": round(max(abs(value) for value in delta), 3),
        })
    return {
        "reference": ref_stats,
        "candidate": candidate_stats,
        "mean_rgb_delta": mean_delta,
        "mean_abs_pixel_delta": round(sum(diff_stat.mean[:3]) / 3.0, 3),
        "edge_density_ratio": round(float(candidate_stats["edge_density"]) / edge_reference, 4),
        "reference_blocks": reference_blocks,
        "candidate_blocks": candidate_blocks,
        "block_deltas": block_deltas,
        "worst_block_channel_delta": max(block["max_abs_channel_delta"] for block in block_deltas),
    }


def stability_delta(first: Image.Image, second: Image.Image) -> dict:
    first_luma = float(image_stats(first)["mean_luminance"])
    second_luma = float(image_stats(second)["mean_luminance"])
    denominator = max(first_luma, 0.001)
    percent = abs(second_luma - first_luma) / denominator * 100.0
    return {
        "first_luminance": round(first_luma, 3),
        "second_luminance": round(second_luma, 3),
        "drift_percent": round(percent, 4),
        "pass": percent < 2.0,
    }


def tile_seam_delta(image: Image.Image) -> dict:
    """Detect the ±padding dark bands around the known four-tile intersection."""
    rgb = image.convert("RGB")
    center_x = rgb.width // 2
    center_y = rgb.height // 2

    def column_delta(x: int) -> float:
        left = rgb.crop((x - 1, 0, x, rgb.height))
        right = rgb.crop((x, 0, x + 1, rgb.height))
        return sum(ImageStat.Stat(ImageChops.difference(left, right)).mean[:3]) / 3.0

    def row_delta(y: int) -> float:
        top = rgb.crop((0, y - 1, rgb.width, y))
        bottom = rgb.crop((0, y, rgb.width, y + 1))
        return sum(ImageStat.Stat(ImageChops.difference(top, bottom)).mean[:3]) / 3.0

    x_band = [column_delta(center_x + offset) for offset in range(-6, 7)]
    y_band = [row_delta(center_y + offset) for offset in range(-6, 7)]
    peak = max(x_band + y_band)
    return {
        "center": [center_x, center_y],
        "x_band_mean_channel_delta": [round(value, 4) for value in x_band],
        "y_band_mean_channel_delta": [round(value, 4) for value in y_band],
        "peak_mean_channel_delta": round(peak, 4),
        "pass": peak < 1.5,
    }


def make_contact_sheet(captures: dict, output: Path) -> None:
    panel_size = (800, 450)
    header_height = 34
    sheet = Image.new(
        "RGB",
        (panel_size[0] * 3, (panel_size[1] + header_height) * len(PRIMARY_VIEWS)),
        (18, 21, 22),
    )
    draw = ImageDraw.Draw(sheet)
    for row, view_id in enumerate(PRIMARY_VIEWS):
        reference = captures[("reference", view_id)].convert("RGB")
        candidate = captures[("candidate", view_id)].convert("RGB")
        difference = ImageEnhance.Contrast(ImageChops.difference(reference, candidate)).enhance(4.0)
        panels = (reference, candidate, difference)
        labels = (f"{view_id} / PNG", f"{view_id} / VECTOR", f"{view_id} / DIFF x4")
        y = row * (panel_size[1] + header_height)
        for column, (panel, label) in enumerate(zip(panels, labels)):
            x = column * panel_size[0]
            draw.text((x + 12, y + 9), label, fill=(225, 230, 226))
            sheet.paste(panel.resize(panel_size, Image.Resampling.LANCZOS), (x, y + header_height))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def make_progression_sheet(captures: dict, output: Path) -> None:
    panel_size = (800, 450)
    header_height = 34
    sheet = Image.new("RGB", (panel_size[0] * 2, (panel_size[1] + header_height) * 3), (18, 21, 22))
    draw = ImageDraw.Draw(sheet)
    for index, zoom_id in enumerate(PROGRESSION_VIEWS):
        row, column = divmod(index, 2)
        image = captures[("candidate", f"progress_{zoom_id}")].convert("RGB")
        x = column * panel_size[0]
        y = row * (panel_size[1] + header_height)
        draw.text((x + 12, y + 9), f"VECTOR ZOOM {zoom_id[0]}.{zoom_id[1:]}", fill=(225, 230, 226))
        sheet.paste(image.resize(panel_size, Image.Resampling.LANCZOS), (x, y + header_height))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def make_wheel_sheet(captures: dict, output: Path) -> None:
    panel_size = (800, 450)
    header_height = 34
    rows = (len(WHEEL_VIEWS) + 1) // 2
    sheet = Image.new("RGB", (panel_size[0] * 2, (panel_size[1] + header_height) * rows), (18, 21, 22))
    draw = ImageDraw.Draw(sheet)
    for index, zoom_id in enumerate(WHEEL_VIEWS):
        row, column = divmod(index, 2)
        image = captures[("candidate", f"wheel_{zoom_id}")].convert("RGB")
        x = column * panel_size[0]
        y = row * (panel_size[1] + header_height)
        draw.text((x + 12, y + 9), f"REAL WHEEL STEP {zoom_id[0]}.{zoom_id[1:]}", fill=(225, 230, 226))
        sheet.paste(image.resize(panel_size, Image.Resampling.LANCZOS), (x, y + header_height))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    capture_dir = manifest_path.parent
    output_dir = (args.output_dir or capture_dir.parent / "analysis").resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    captures: dict[tuple[str, str], Image.Image] = {}
    for entry in manifest["views"]:
        key = (str(entry["mode"]), str(entry["id"]))
        captures[key] = Image.open(capture_dir / entry["file"]).convert("RGB")

    comparisons = {}
    gates = []
    for view_id in PRIMARY_VIEWS:
        comparison = compare_pair(captures[("reference", view_id)], captures[("candidate", view_id)])
        comparisons[view_id] = comparison
        # Coarse smoke gates only. Semantic sea/land masks will replace these in the gold-slice stage.
        color_ok = max(abs(value) for value in comparison["mean_rgb_delta"]) <= 12.0
        edge_ratio = float(comparison["edge_density_ratio"])
        candidate_edge = float(comparison["candidate"]["edge_density"])
        if view_id in OPERATIONAL_VIEWS:
            edge_ok = 1.5 <= candidate_edge <= 8.0
            edge_gate = "structure_density"
        elif view_id in STRUCTURAL_DETAIL_VIEWS:
            edge_ok = 2.5 <= candidate_edge <= 14.0
            edge_gate = "structure_density"
        else:
            edge_ok = 0.65 <= edge_ratio <= 1.35
            edge_gate = "edge_density"
        gates.append({"name": f"{view_id}.coarse_color", "pass": color_ok})
        gates.append({"name": f"{view_id}.{edge_gate}", "pass": edge_ok})
        if view_id == "yokohama_gold":
            strict_color_ok = max(abs(value) for value in comparison["mean_rgb_delta"]) <= 6.0
            strict_edge_ok = 0.75 <= edge_ratio <= 1.30
            gates.append({"name": "yokohama_gold.strict_palette", "pass": strict_color_ok})
            gates.append({"name": "yokohama_gold.strict_edge_density", "pass": strict_edge_ok})

    stability = {}
    for first_id, second_id in manifest["stability_pairs"]:
        name = f"{first_id}_to_{second_id}"
        result = stability_delta(
            captures[("candidate", first_id)],
            captures[("candidate", second_id)],
        )
        stability[name] = result
        gates.append({"name": f"{name}.brightness", "pass": bool(result["pass"])})

    tile_seam = tile_seam_delta(captures[("candidate", "detail_seam")])
    gates.append({"name": "detail_seam.tile_padding_overlap", "pass": bool(tile_seam["pass"])})

    progression = []
    previous_stats = None
    for zoom_id in PROGRESSION_VIEWS:
        stats = image_stats(captures[("candidate", f"progress_{zoom_id}")])
        step = {"zoom": zoom_id, "stats": stats}
        if previous_stats is not None:
            luminance_drift = abs(float(stats["mean_luminance"]) - float(previous_stats["mean_luminance"])) \
                / max(float(previous_stats["mean_luminance"]), 0.001) * 100.0
            edge_increase = (float(stats["edge_density"]) / max(float(previous_stats["edge_density"]), 0.001) - 1.0) * 100.0
            step["luminance_drift_percent"] = round(luminance_drift, 4)
            step["edge_increase_percent"] = round(edge_increase, 4)
            gates.append({"name": f"progress_{zoom_id}.brightness_step", "pass": luminance_drift <= 4.0})
            gates.append({"name": f"progress_{zoom_id}.edge_step", "pass": edge_increase <= 15.0})
        progression.append(step)
        previous_stats = stats

    wheel_progression = []
    previous_stats = None
    for zoom_id in WHEEL_VIEWS:
        stats = image_stats(captures[("candidate", f"wheel_{zoom_id}")])
        step = {"zoom": zoom_id, "stats": stats}
        if previous_stats is not None:
            luminance_drift = abs(float(stats["mean_luminance"]) - float(previous_stats["mean_luminance"])) \
                / max(float(previous_stats["mean_luminance"]), 0.001) * 100.0
            edge_increase = (float(stats["edge_density"]) / max(float(previous_stats["edge_density"]), 0.001) - 1.0) * 100.0
            step["luminance_drift_percent"] = round(luminance_drift, 4)
            step["edge_increase_percent"] = round(edge_increase, 4)
            gates.append({"name": f"wheel_{zoom_id}.brightness_step", "pass": luminance_drift <= 2.25})
            gates.append({"name": f"wheel_{zoom_id}.edge_step", "pass": edge_increase <= 15.0})
        wheel_progression.append(step)
        previous_stats = stats

    zoom_sweep = []
    previous_stats = None
    for zoom_id in SWEEP_VIEWS:
        stats = image_stats(captures[("candidate", f"sweep_{zoom_id}")])
        step = {"zoom": zoom_id, "stats": stats}
        if previous_stats is not None:
            luminance_drift = abs(float(stats["mean_luminance"]) - float(previous_stats["mean_luminance"])) \
                / max(float(previous_stats["mean_luminance"]), 0.001) * 100.0
            edge_increase = (float(stats["edge_density"]) / max(float(previous_stats["edge_density"]), 0.001) - 1.0) * 100.0
            step["luminance_drift_percent"] = round(luminance_drift, 4)
            step["edge_increase_percent"] = round(edge_increase, 4)
            gates.append({"name": f"sweep_{zoom_id}.brightness_step", "pass": luminance_drift <= 1.0})
            gates.append({"name": f"sweep_{zoom_id}.edge_step", "pass": edge_increase <= 8.0})
        zoom_sweep.append(step)
        previous_stats = stats

    passed = all(bool(gate["pass"]) for gate in gates)
    report = {
        "schema_version": 1,
        "source_manifest": str(manifest_path),
        "pass": passed,
        "gates": gates,
        "comparisons": comparisons,
        "stability": stability,
        "tile_seam": tile_seam,
        "progression": progression,
        "wheel_progression": wheel_progression,
        "zoom_sweep": zoom_sweep,
    }
    (output_dir / "metrics.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    make_contact_sheet(captures, output_dir / "contact_sheet.png")
    make_progression_sheet(captures, output_dir / "progression_sheet.png")
    make_wheel_sheet(captures, output_dir / "wheel_progression_sheet.png")

    summary = ["# Map visual QA", "", f"Overall: {'PASS' if passed else 'FAIL'}", "", "## Gates", ""]
    summary.extend(f"- [{'x' if gate['pass'] else ' '}] {gate['name']}" for gate in gates)
    (output_dir / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print(f"[map_visual_qa] {'PASS' if passed else 'FAIL'} -> {output_dir}")
    return 0 if passed or args.allow_fail else 1


if __name__ == "__main__":
    raise SystemExit(main())
