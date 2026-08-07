#!/usr/bin/env python3
"""Aggregate deterministic evolution-growth bench runs into review artifacts."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median
from typing import Any, Iterable


STARTERS = ("f15", "f14", "a6e", "mirage3")
SQUAD_SIZES = (1, 3, 5, 9)


def percentile(values: Iterable[float], p: float) -> float | None:
    ordered = sorted(float(v) for v in values)
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * p
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[lower]
    weight = rank - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def load_runs(raw_dir: Path) -> list[dict[str, Any]]:
    runs: list[dict[str, Any]] = []
    for path in sorted(raw_dir.glob("*.json")):
        try:
            row = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"warning: skip {path}: {exc}")
            continue
        if row.get("schema_version") != 1:
            print(f"warning: skip unsupported schema {path}")
            continue
        row["_source"] = path.name
        runs.append(row)
    return runs


def rounded(value: float | None, digits: int = 2) -> float | None:
    return None if value is None else round(value, digits)


def group_row(starter: str, squad_size: int, runs: list[dict[str, Any]]) -> dict[str, Any]:
    levels = [float(r["final_level"]) + float(r["level_progress_pct"]) / 100.0 for r in runs]
    xp = [float(r["total_xp"]) for r in runs]
    kpm = [float(r["kills_per_min"]) for r in runs]
    tiers = [float(r["final_tier"]) for r in runs]
    row: dict[str, Any] = {
        "starter": starter,
        "squad_size": squad_size,
        "valid_samples": len(runs),
        "level_p50": rounded(percentile(levels, 0.50)),
        "level_p75": rounded(percentile(levels, 0.75)),
        "level_p90": rounded(percentile(levels, 0.90)),
        "xp_p50": rounded(percentile(xp, 0.50), 1),
        "xp_p75": rounded(percentile(xp, 0.75), 1),
        "kills_per_min_p50": rounded(percentile(kpm, 0.50), 3),
        "kills_per_min_p75": rounded(percentile(kpm, 0.75), 3),
        "tier_p75": rounded(percentile(tiers, 0.75)),
        "tier_distribution": dict(sorted(Counter(int(v) for v in tiers).items())),
        "ace_kills_p50": rounded(percentile((r["ace_kills"] for r in runs), 0.50), 1),
        "wingman_kills_p50": rounded(percentile((r["wingman_kills"] for r in runs), 0.50), 1),
        "missed_settlements_total": sum(int(r["missed_settlements"]) for r in runs),
    }
    for tier in (2, 3, 4):
        reached = [
            float(r["first_tier_time_s"][str(tier)])
            for r in runs
            if float(r["first_tier_time_s"].get(str(tier), -1.0)) >= 0.0
        ]
        row[f"tier{tier}_time_p50_s"] = rounded(percentile(reached, 0.50), 1)
        row[f"tier{tier}_time_p75_s"] = rounded(percentile(reached, 0.75), 1)
        row[f"tier{tier}_reach_rate"] = rounded(len(reached) / max(len(runs), 1), 3)
    for axis in ("gladiator", "knight", "schemer"):
        row[f"missing_{axis}_count"] = sum(
            int(r["missing_axis_counts"].get(axis, 0)) for r in runs
        )
        row[f"missing_{axis}_wait_s"] = rounded(
            sum(float(r["missing_axis_wait_s"].get(axis, 0.0)) for r in runs), 1
        )
    return row


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def build_conclusions(groups: list[dict[str, Any]]) -> dict[str, Any]:
    complete = [g for g in groups if g["valid_samples"] > 0]
    tier_p75_values = [float(g["tier_p75"]) for g in complete if g["tier_p75"] is not None]
    overall_target = int(round(median(tier_p75_values))) if tier_p75_values else None
    compensation: list[dict[str, Any]] = []
    by_starter = defaultdict(dict)
    for group in complete:
        by_starter[group["starter"]][int(group["squad_size"])] = group
    for starter, size_map in by_starter.items():
        base = size_map.get(1)
        if not base or not base.get("xp_p75"):
            continue
        for size in (3, 5, 9):
            current = size_map.get(size)
            if not current or not current.get("xp_p75"):
                continue
            loss = 1.0 - float(current["xp_p75"]) / float(base["xp_p75"])
            level_loss = float(base["level_p75"]) - float(current["level_p75"])
            suggested = 1.0
            if loss > 0.10 or level_loss > 0.50:
                suggested = min(1.50, float(base["xp_p75"]) / float(current["xp_p75"]))
            compensation.append(
                {
                    "starter": starter,
                    "squad_size": size,
                    "xp_loss_pct_vs_solo": round(loss * 100.0, 1),
                    "level_loss_vs_solo": round(level_loss, 2),
                    "suggested_additional_xp_multiplier": round(suggested, 3),
                }
            )
    return {
        "good_run_target_tier": overall_target,
        "target_basis": "median of the 16 group P75 final tiers",
        "squad_compensation": compensation,
    }


def render_markdown(summary: dict[str, Any]) -> str:
    matrix = summary["matrix"]
    conclusions = summary["conclusions"]
    lines = [
        "# 14 分钟进化成长基准",
        "",
        f"- 有效样本：**{matrix['valid_runs']} / {matrix['expected_runs']}**",
        f"- 无效样本：**{matrix['invalid_runs']}**（不计入分位数）",
        f"- 完整组合：**{matrix['complete_groups']} / 16**",
        f"- P75 良好局合理目标：**T{conclusions['good_run_target_tier']}**"
        if conclusions["good_run_target_tier"] is not None
        else "- P75 良好局合理目标：**样本不足**",
        "",
        "## 分组结果",
        "",
        "| 起手机 | 小队 | n | 等级 P50/P75/P90 | XP P50/P75 | 击杀/分 P50 | 最终 Tier P75 | T2/T3/T4 首达 P50(s) |",
        "|---|---:|---:|---|---|---:|---:|---|",
    ]
    for g in summary["groups"]:
        lines.append(
            "| {starter} | {squad_size} | {valid_samples} | {level_p50}/{level_p75}/{level_p90} | "
            "{xp_p50}/{xp_p75} | {kills_per_min_p50} | {tier_p75} | {tier2_time_p50_s}/{tier3_time_p50_s}/{tier4_time_p50_s} |".format(
                **g
            )
        )
    lines += ["", "## 小队经验补偿", ""]
    if not conclusions["squad_compensation"]:
        lines.append("样本不足，暂不判断。")
    else:
        lines += [
            "| 起手机 | 小队 | XP 损失 | 等级损失 | 建议额外倍率 |",
            "|---|---:|---:|---:|---:|",
        ]
        for row in conclusions["squad_compensation"]:
            lines.append(
                f"| {row['starter']} | {row['squad_size']} | {row['xp_loss_pct_vs_solo']}% | "
                f"{row['level_loss_vs_solo']} | ×{row['suggested_additional_xp_multiplier']} |"
            )
    lines += [
        "",
        "## 口径",
        "",
        "- 每组只使用 `valid=true` 的样本；死亡、未满 14:00 或有效战斗时间不足 80% 的局由调度器补跑。",
        "- P75 表示“较好一局”，同时保留 P50/P90，不以单局最高值代替平衡结论。",
        "- 固定 60 Hz 加速模拟只取消墙钟同步，不跳过物理 tick、XP、选卡、门槛、死亡或战斗规则。",
        "- 补偿倍率是审查建议，不会自动写回正式数值。",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--expected-per-group", type=int, default=20)
    args = parser.parse_args()

    all_runs = load_runs(args.raw_dir)
    valid = [r for r in all_runs if bool(r.get("valid", False))]
    invalid = [r for r in all_runs if not bool(r.get("valid", False))]
    grouped: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for run in valid:
        grouped[(str(run["starter"]), int(run["squad_size"]))].append(run)

    groups = [group_row(starter, size, grouped[(starter, size)]) for starter in STARTERS for size in SQUAD_SIZES]
    expected_runs = 16 * args.expected_per_group
    summary = {
        "schema_version": 1,
        "matrix": {
            "expected_runs": expected_runs,
            "valid_runs": len(valid),
            "invalid_runs": len(invalid),
            "complete_groups": sum(g["valid_samples"] >= args.expected_per_group for g in groups),
            "expected_per_group": args.expected_per_group,
        },
        "groups": groups,
        "conclusions": build_conclusions(groups),
    }

    args.out.mkdir(parents=True, exist_ok=True)
    flat_runs = []
    for run in all_runs:
        flat_runs.append(
            {
                "run_id": run.get("run_id"),
                "starter": run.get("starter"),
                "squad_size": run.get("squad_size"),
                "seed": run.get("seed"),
                "valid": run.get("valid"),
                "invalid_reasons": ";".join(run.get("invalid_reasons", [])),
                "final_level": run.get("final_level"),
                "level_progress_pct": run.get("level_progress_pct"),
                "total_xp": run.get("total_xp"),
                "kills_per_min": run.get("kills_per_min"),
                "final_node": run.get("final_node"),
                "final_tier": run.get("final_tier"),
                "combat_ratio": run.get("combat_ratio"),
                "source": run.get("_source"),
            }
        )
    if flat_runs:
        write_csv(args.out / "runs.csv", flat_runs)
    write_csv(args.out / "group_summary.csv", groups)
    (args.out / "evolution_growth_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (args.out / "growth_benchmark.md").write_text(render_markdown(summary), encoding="utf-8")
    print(
        f"growth aggregate: valid={len(valid)}/{expected_runs} invalid={len(invalid)} "
        f"complete_groups={summary['matrix']['complete_groups']}/16"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
