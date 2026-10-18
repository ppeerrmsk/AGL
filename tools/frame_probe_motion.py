#!/usr/bin/env python3
"""FrameProbe 运动顿挫指标（显示态）。

用法：python tools/frame_probe_motion.py bench/results/frame_probe_*.csv [--warmup 5] [--json]

读取 scripts/diagnostics/frame_probe.gd 写出的逐帧 CSV（ply_wx/wy/sx/sy 为玩家机呈现位置：
新版探针是物理插值后的显示态，旧版等于物理位置），对每个文件输出：

- frames / fps / 帧时 p50/p95/p99、>16.7ms、>33.3ms 占比（只算正式局、未暂停帧）
- no_move：玩家呈现世界位置与上一帧完全相同的帧占比（未插值时只在有物理步的帧移动）
- move_gap_ms_mean / move_gap_cv：两次呈现位移之间的墙钟间隔均值与变异系数。未插值时位移只在
  有物理步的帧出现（均值≈16.7ms）；插值后每帧都有位移，该项退化为帧间隔，应与 frame_gap_cv 对照读
- frame_gap_cv：相邻呈现帧墙钟间隔的变异系数（帧节拍本身的均匀度）
- scroll_cv：1s 窗口内逐帧屏幕滚动速度（画布原点 px/s）的变异系数，取窗口中位数 / p90
- jitter p50/p95/p99：玩家屏幕位置相对前后两帧按时间线性插值的偏差（px），即二阶抖动
- phys_lag：显示态与物理态的世界距离均值（插值时 ≈ 半个 tick 的位移，未插值时 0）
- 与 2026-10-17 诊断口径一致的三项：world_speed_cv（逐帧世界速度 CV）、scroll_cv_all
  （全程逐帧屏幕滚动速度 CV）、screen_step_p95（玩家逐帧屏幕位移 p95，px）

缩放变化帧、暂停帧、玩家缺失帧与前 warmup 秒不计入运动指标。
"""
import argparse
import csv
import json
import math
import statistics
import sys


def pct(values, q):
    if not values:
        return float("nan")
    s = sorted(values)
    k = (len(s) - 1) * q / 100.0
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return s[int(k)]
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def cv(values):
    if len(values) < 2:
        return float("nan")
    m = statistics.fmean(values)
    if m <= 0:
        return float("nan")
    return statistics.pstdev(values) / m


def load(path):
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    out = []
    for r in rows:
        try:
            out.append({k: float(v) for k, v in r.items() if v not in ("", None)})
        except ValueError:
            continue
    return out


def analyze(path, warmup_s):
    rows = load(path)
    # 正式局：玩家存在（屏幕坐标非零）、未暂停。
    play = [r for r in rows if r.get("paused", 0.0) < 0.5
            and (abs(r.get("ply_sx", 0.0)) > 0.0 or abs(r.get("ply_sy", 0.0)) > 0.0)]
    if len(play) < 10:
        return {"file": path, "frames": len(play), "error": "too few play frames"}
    t0 = play[0]["t_ms"] + warmup_s * 1000.0
    play = [r for r in play if r["t_ms"] >= t0]
    totals = [r["total_ms"] for r in play]
    span_s = (play[-1]["t_ms"] - play[0]["t_ms"]) / 1000.0 if len(play) > 1 else 0.0

    no_move = 0
    moves = 0
    move_times = []
    scroll = []      # (t_ms, speed px/s)
    jitter = []
    lag = []
    world_speed = []
    screen_step = []
    for i in range(1, len(play)):
        a, b = play[i - 1], play[i]
        if abs(b["zoom"] - a["zoom"]) > 1e-6:
            continue
        dt = (b["t_ms"] - a["t_ms"]) / 1000.0
        if dt <= 0:
            continue
        moves += 1
        dw = math.hypot(b["ply_wx"] - a["ply_wx"], b["ply_wy"] - a["ply_wy"])
        world_speed.append(dw / dt)
        screen_step.append(math.hypot(b["ply_sx"] - a["ply_sx"], b["ply_sy"] - a["ply_sy"]))
        if dw < 1e-4:
            no_move += 1
        else:
            move_times.append(b["t_ms"])
        scroll.append((b["t_ms"], math.hypot(b["cam_x"] - a["cam_x"], b["cam_y"] - a["cam_y"]) / dt))
        if "ply_px" in b:
            lag.append(math.hypot(b["ply_wx"] - b["ply_px"], b["ply_wy"] - b["ply_py"]))
        if i + 1 < len(play):
            c = play[i + 1]
            if abs(c["zoom"] - b["zoom"]) > 1e-6:
                continue
            t_a, t_b, t_c = a["t_ms"], b["t_ms"], c["t_ms"]
            if t_c <= t_a:
                continue
            w = (t_b - t_a) / (t_c - t_a)
            ex = a["ply_sx"] + (c["ply_sx"] - a["ply_sx"]) * w
            ey = a["ply_sy"] + (c["ply_sy"] - a["ply_sy"]) * w
            jitter.append(math.hypot(b["ply_sx"] - ex, b["ply_sy"] - ey))

    gaps = [move_times[i] - move_times[i - 1] for i in range(1, len(move_times))]
    frame_gaps = [play[i]["t_ms"] - play[i - 1]["t_ms"] for i in range(1, len(play))]
    windows = {}
    for t, v in scroll:
        windows.setdefault(int(t // 1000), []).append(v)
    window_cv = [cv(v) for v in windows.values() if len(v) >= 10 and statistics.fmean(v) > 30.0]
    window_cv = [x for x in window_cv if not math.isnan(x)]
    return {
        "file": path,
        "frames": len(play),
        "seconds": round(span_s, 1),
        "fps": round(len(play) / span_s, 1) if span_s > 0 else float("nan"),
        "frame_ms_p50": round(pct(totals, 50), 3),
        "frame_ms_p95": round(pct(totals, 95), 3),
        "frame_ms_p99": round(pct(totals, 99), 3),
        "slow_16_pct": round(100.0 * sum(t > 16.7 for t in totals) / len(totals), 3),
        "slow_33_count": sum(t > 33.3 for t in totals),
        "no_move_pct": round(100.0 * no_move / moves, 2) if moves else float("nan"),
        "move_gap_ms_mean": round(statistics.fmean(gaps), 3) if gaps else float("nan"),
        "move_gap_cv": round(cv(gaps), 3),
        "frame_gap_cv": round(cv(frame_gaps), 3),
        "scroll_cv_median": round(statistics.median(window_cv), 3) if window_cv else float("nan"),
        "scroll_cv_p90": round(pct(window_cv, 90), 3) if window_cv else float("nan"),
        "jitter_px_p50": round(pct(jitter, 50), 3),
        "jitter_px_p95": round(pct(jitter, 95), 3),
        "jitter_px_p99": round(pct(jitter, 99), 3),
        "phys_lag_px_mean": round(statistics.fmean(lag), 3) if lag else float("nan"),
        "world_speed_cv": round(cv(world_speed), 3),
        "scroll_cv_all": round(cv([v for _, v in scroll]), 3),
        "screen_step_p95": round(pct(screen_step, 95), 3),
        "interp_on": play[-1].get("interp_on", float("nan")),
    }


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="+")
    ap.add_argument("--warmup", type=float, default=5.0, help="跳过正式局开头秒数")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    results = [analyze(p, args.warmup) for p in args.csv]
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return 0
    keys = ["interp_on", "frames", "fps", "frame_ms_p50", "frame_ms_p99", "slow_16_pct", "slow_33_count",
            "no_move_pct", "move_gap_ms_mean", "move_gap_cv", "frame_gap_cv", "scroll_cv_median", "scroll_cv_p90",
            "jitter_px_p50", "jitter_px_p95", "jitter_px_p99", "phys_lag_px_mean",
            "world_speed_cv", "scroll_cv_all", "screen_step_p95"]
    for r in results:
        print(r["file"])
        if "error" in r:
            print("   ", r["error"])
            continue
        print("    " + "  ".join("%s=%s" % (k, r.get(k)) for k in keys))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
