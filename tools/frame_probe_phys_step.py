#!/usr/bin/env python3
"""FrameProbe 物理步成本与"有/无物理步"帧分组统计。

用法：
  python tools/frame_probe_phys_step.py bench/results/frame_probe_tokyo_volume_c2_*.csv [--json]
  python tools/frame_probe_phys_step.py --group rel=bench/results/*_rel_*.csv --group tools=bench/results/*_tools_*.csv

读取 scripts/diagnostics/frame_probe.gd 写出的逐帧 CSV（需要末列 bench_t），只统计 bench 采样窗口：
bench_t >= --window-start（默认 3.0s，与东京 C1/C2 墙钟采样起点一致），并去掉 bench_t 停止增长后的
收尾帧（截图读回、退出）。暂停帧不计。单位数看同轮 bench 结果 .txt 的 tokyo_unit_census_*。

每个文件输出：
- frames / avg_fps / 帧时 mean、p50、p99、p99.9；>16.7ms、>33.3ms 帧数与占比
- 有物理步帧（steps>=1）与无物理步帧（steps=0）各自的 n、mean、p99、>16.7ms 数；steps=2 帧数
- phys_script_per_step：窗口内 phys_script 总和 / 物理步总数（ms）；单步帧 phys_script 的 p50 / p99
- phys_engine_per_step、phys_signal_per_step：物理步脚本段之后的引擎工作、物理帧信号段
- proc_script / pre_render / render / post 的每帧均值（ms）；有步帧、无步帧各自的八个互斥阶段均值
分组（--group 名=通配）时另给各组跨轮均值与极差。百分位用 nearest-rank，与 tokyo_render_clock 一致。
"""
import argparse
import csv
import glob
import json
import math
import statistics
import sys

SLOW_MS = 16.7
VERY_SLOW_MS = 33.3


def nearest_rank(values, q):
    if not values:
        return float("nan")
    s = sorted(values)
    k = max(0, min(len(s) - 1, math.ceil(q / 100.0 * len(s)) - 1))
    return s[k]


def load_rows(path):
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if "bench_t" not in (reader.fieldnames or []):
            raise SystemExit(f"{path}: 缺少 bench_t 列（探针版本过旧）")
        rows = []
        for r in reader:
            try:
                rows.append({k: float(v) for k, v in r.items() if v not in ("", None)})
            except ValueError:
                continue
    return rows


def window(rows, start):
    t_max = max((r["bench_t"] for r in rows), default=-1.0)
    return [r for r in rows if r["bench_t"] >= start and r["bench_t"] < t_max and r.get("paused", 0.0) == 0.0]


PHASES = ["phys_signal", "phys_script", "phys_engine", "proc_signal", "proc_script", "pre_render", "render", "post"]


def group_stats(frames):
    totals = [r["total_ms"] for r in frames]
    return {
        "n": len(frames),
        "mean_ms": statistics.fmean(totals) if totals else float("nan"),
        "p99_ms": nearest_rank(totals, 99),
        "over16": sum(1 for t in totals if t > SLOW_MS),
        # 每帧各互斥阶段均值（ms），用于拆"有物理步帧比无物理步帧贵在哪"
        "phases_ms": {p: (statistics.fmean(r.get(p, 0.0) for r in frames) if frames else float("nan")) for p in PHASES},
    }


def analyse(path, start):
    frames = window(load_rows(path), start)
    if not frames:
        raise SystemExit(f"{path}: 窗口内没有帧（bench_t >= {start}）")
    totals = [r["total_ms"] for r in frames]
    wall_s = sum(totals) / 1000.0
    steps_total = sum(int(r["steps"]) for r in frames)
    step_frames = [r for r in frames if r["steps"] >= 1]
    idle_frames = [r for r in frames if r["steps"] == 0]
    single = [r["phys_script"] for r in frames if r["steps"] == 1]
    over16 = sum(1 for t in totals if t > SLOW_MS)
    over33 = sum(1 for t in totals if t > VERY_SLOW_MS)

    def per_step(col):
        return sum(r.get(col, 0.0) for r in frames) / steps_total if steps_total else float("nan")

    def per_frame(col):
        return statistics.fmean(r.get(col, 0.0) for r in frames)

    return {
        "file": path,
        "frames": len(frames),
        "window_s": wall_s,
        "bench_t_span": [frames[0]["bench_t"], frames[-1]["bench_t"]],
        "avg_fps": len(frames) / wall_s if wall_s > 0 else float("nan"),
        "mean_ms": statistics.fmean(totals),
        "p50_ms": nearest_rank(totals, 50),
        "p99_ms": nearest_rank(totals, 99),
        "p999_ms": nearest_rank(totals, 99.9),
        "max_ms": max(totals),
        "over16": over16,
        "over16_pct": 100.0 * over16 / len(frames),
        "over33": over33,
        "steps_total": steps_total,
        "steps_per_s": steps_total / wall_s if wall_s > 0 else float("nan"),
        "two_step_frames": sum(1 for r in frames if r["steps"] >= 2),
        "step_frames": group_stats(step_frames),
        "idle_frames": group_stats(idle_frames),
        "phys_script_per_step": per_step("phys_script"),
        "phys_script_single_p50": nearest_rank(single, 50),
        "phys_script_single_p99": nearest_rank(single, 99),
        "phys_engine_per_step": per_step("phys_engine"),
        "phys_signal_per_step": per_step("phys_signal"),
        "proc_script_per_frame": per_frame("proc_script"),
        "pre_render_per_frame": per_frame("pre_render"),
        "render_per_frame": per_frame("render"),
        "post_per_frame": per_frame("post"),
    }


SUMMARY_KEYS = [
    "avg_fps", "mean_ms", "p99_ms", "over16_pct", "over33", "phys_script_per_step",
    "phys_script_single_p99", "phys_engine_per_step", "proc_script_per_frame", "render_per_frame",
]


def fmt(v):
    return f"{v:.3f}" if isinstance(v, float) else str(v)


def print_file(s):
    sf, idle = s["step_frames"], s["idle_frames"]
    print(f"== {s['file']}")
    print(f"  frames={s['frames']} window={s['window_s']:.1f}s avg_fps={s['avg_fps']:.1f} "
          f"mean={s['mean_ms']:.2f} p50={s['p50_ms']:.2f} p99={s['p99_ms']:.2f} p99.9={s['p999_ms']:.2f} max={s['max_ms']:.2f}")
    print(f"  >16.7ms={s['over16']} ({s['over16_pct']:.2f}%)  >33.3ms={s['over33']}  "
          f"steps={s['steps_total']} ({s['steps_per_s']:.1f}/s)  2-step frames={s['two_step_frames']}")
    print(f"  step frames n={sf['n']} mean={sf['mean_ms']:.2f} p99={sf['p99_ms']:.2f} >16.7={sf['over16']} | "
          f"idle frames n={idle['n']} mean={idle['mean_ms']:.2f} p99={idle['p99_ms']:.2f} >16.7={idle['over16']}")
    print(f"  phys_script/step={s['phys_script_per_step']:.3f}ms (1-step p50={s['phys_script_single_p50']:.3f} "
          f"p99={s['phys_script_single_p99']:.3f})  phys_engine/step={s['phys_engine_per_step']:.3f}  "
          f"phys_signal/step={s['phys_signal_per_step']:.3f}")
    print(f"  per frame: proc_script={s['proc_script_per_frame']:.3f} pre_render={s['pre_render_per_frame']:.3f} "
          f"render={s['render_per_frame']:.3f} post={s['post_per_frame']:.3f}")
    for name, part in (("step", sf), ("idle", idle)):
        if part["n"]:
            print(f"  {name} frame phases: " + " ".join(f"{p}={v:.2f}" for p, v in part["phases_ms"].items()))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--group", action="append", default=[], help="名=通配，例如 rel=bench/results/*_rel_*.csv")
    ap.add_argument("--window-start", type=float, default=3.0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    groups = {}
    for spec in args.group:
        name, _, pattern = spec.partition("=")
        groups[name] = sorted(glob.glob(pattern))
    if args.files:
        groups.setdefault("", []).extend(args.files)
    if not any(groups.values()):
        ap.error("没有输入文件")

    report = {}
    for name, files in groups.items():
        stats = [analyse(f, args.window_start) for f in files]
        agg = {}
        for k in SUMMARY_KEYS:
            vals = [s[k] for s in stats]
            agg[k] = {"mean": statistics.fmean(vals), "min": min(vals), "max": max(vals)}
        for part in ("step_frames", "idle_frames"):
            for k in ("mean_ms", "p99_ms"):
                vals = [s[part][k] for s in stats]
                agg[f"{part}.{k}"] = {"mean": statistics.fmean(vals), "min": min(vals), "max": max(vals)}
        report[name] = {"runs": stats, "aggregate": agg}

    if args.json:
        json.dump(report, sys.stdout, ensure_ascii=False, indent=1)
        return
    for name, data in report.items():
        if name:
            print(f"######## group {name} ({len(data['runs'])} runs)")
        for s in data["runs"]:
            print_file(s)
        if len(data["runs"]) > 1:
            print("  -- aggregate mean [min, max]")
            for k, v in data["aggregate"].items():
                print(f"     {k}: {fmt(v['mean'])} [{fmt(v['min'])}, {fmt(v['max'])}]")


if __name__ == "__main__":
    main()
