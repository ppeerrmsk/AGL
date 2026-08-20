#!/usr/bin/env python3
"""AGL 铺量阶段首版量化模型；只读当前仓库，不修改游戏数据。"""

from __future__ import annotations

import argparse
import ast
import json
import math
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = Path(__file__).with_name("agl_quantitative_model_config.json")
CANONICAL_REPORT = ROOT / "docs/audits/2026-08-20-quantitative-model-baseline.md"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


def parse_enemy_rows() -> list[dict]:
    text = read("scripts/survivor/enemy_pool_registry.gd")
    block = text.split("const ROWS:", 1)[1].split("\n]", 1)[0]
    rows: list[dict] = []
    for line in block.splitlines():
        stripped = line.strip().rstrip(",")
        if not stripped.startswith("{"):
            continue
        pythonish = re.sub(r"\btrue\b", "True", stripped)
        pythonish = re.sub(r"\bfalse\b", "False", pythonish)
        rows.append(ast.literal_eval(pythonish))
    return rows


def parse_bosses() -> list[str]:
    text = read("scripts/survivor/boss_registry.gd")
    block = text.split("const BOSS_DEFS:", 1)[1].split("\n}\n", 1)[0]
    return re.findall(r'^\s*"([A-Z0-9_]+)":\s*\{$', block, flags=re.MULTILINE)


def parse_maps() -> dict[str, int]:
    text = read("scripts/survivor/survivor_map_select.gd")
    block = text.split("const MAP_LIST:", 1)[1].split("\n]", 1)[0]
    cards = re.findall(r"\{(.*?)\n\s*\}", block, flags=re.DOTALL)
    counts = Counter()
    for card in cards:
        if '"locked": true' in card:
            counts["locked"] += 1
        elif '"preview_only": true' in card:
            counts["preview"] += 1
        else:
            counts["release_ready"] += 1
    return dict(counts)


def parse_skills() -> dict[str, int]:
    text = read("docs/reference/skill-table.md")
    total_match = re.search(r"（(\d+) 条）", text)
    axes = {name: int(count) for name, count in re.findall(
        r"^## (.+?) 轴（(\d+) 条）", text, flags=re.MULTILINE)}
    return {"total": int(total_match.group(1)) if total_match else sum(axes.values()), **axes}


def parse_specs() -> dict[str, int]:
    counts = Counter()
    for line in read("docs/specs/_INDEX.md").splitlines():
        match = re.match(r"^\| \[[^]]+\]\([^)]+\) \| [^|]+ \| ([^|]+) \|", line)
        if match:
            counts[match.group(1).strip()] += 1
    return dict(counts)


def parse_implemented_merit_sink(evolution: dict) -> dict[str, int]:
    text = read("scripts/meta/meta_shop.gd")
    signature_block = text.split("const SIGNATURE_PRICE_BY_TIER:", 1)[1].split("\n}", 1)[0]
    signature_prices = {int(tier): int(price) for tier, price in re.findall(
        r"^\s*(\d+):\s*(\d+),", signature_block, flags=re.MULTILINE)}
    signature_total = sum(
        int(count) * signature_prices.get(int(tier), 0)
        for tier, count in evolution["tiers"].items())
    catalog_block = text.split("const CATALOG:", 1)[1].split("\n}\n\n##", 1)[0]
    doctrine_block = text.split("const DOCTRINES:", 1)[1].split("\n}\n\n##", 1)[0]
    catalog_total = sum(map(int, re.findall(r'"price":\s*(\d+)', catalog_block)))
    doctrine_total = sum(map(int, re.findall(r'"price":\s*(\d+)', doctrine_block)))
    return {
        "catalog": catalog_total,
        "doctrines": doctrine_total,
        "signatures": signature_total,
        "total": catalog_total + doctrine_total + signature_total,
    }


def parse_evolution() -> tuple[dict, list[dict]]:
    nodes = json.loads(read("resources/evolution/evolution_tree.json"))["nodes"]
    tiers = Counter(int(node["tier"]) for node in nodes)
    levels = Counter(int(node["min_level"]) for node in nodes)
    return ({
        "nodes": len(nodes),
        "edges": sum(len(node.get("exits", [])) for node in nodes),
        "tiers": dict(sorted(tiers.items())),
        "levels": dict(sorted(levels.items())),
        "max_level": max(levels),
    }, nodes)


def token_budget(level: int) -> int:
    return min(8 + int(level * 1.8), 55)


def spawn_interval(level: int) -> float:
    t = min(max(level / 20.0, 0.0), 1.0)
    return 32.0 + (18.0 - 32.0) * t


def xp_to_reach(level: int) -> int:
    return sum(int(15.0 * math.pow(current, 1.3)) for current in range(1, level))


@dataclass
class CurveRow:
    level: int
    budget: int
    interval: float
    enemy_pressure: float
    tier: int
    player_run_power: float
    player_long_upper: float
    relative_difficulty: float


def build_curve(config: dict, nodes: list[dict]) -> list[CurveRow]:
    levels = [1, 4, 10, 16, 20, 22, 27]
    base_pressure = token_budget(1) / spawn_interval(1)
    tier_mult = config["player_power"]["tier_multiplier"]
    gain = config["player_power"]["provisional_build_gain_per_level"]
    cap = config["player_power"]["provisional_build_gain_cap"]
    mastery = config["progression"]["mastery_upper_multiplier"]
    rows = []
    for level in levels:
        budget = token_budget(level)
        interval = spawn_interval(level)
        enemy_pressure = (budget / interval) / base_pressure
        tier = max((int(n["tier"]) for n in nodes if int(n["min_level"]) <= level), default=1)
        build_mult = 1.0 + min(cap, max(0, level - 1) * gain)
        player_run_power = float(tier_mult[str(tier)]) * build_mult
        rows.append(CurveRow(level, budget, interval, enemy_pressure, tier,
                             player_run_power, player_run_power * mastery,
                             enemy_pressure / player_run_power))
    return rows


def hours_for_sink(sink: int, merit_per_run: int, run_minutes: float) -> float:
    return sink / merit_per_run * run_minutes / 60.0


def render_report(config: dict) -> str:
    evolution, nodes = parse_evolution()
    enemies = parse_enemy_rows()
    bosses = parse_bosses()
    maps = parse_maps()
    skills = parse_skills()
    specs = parse_specs()
    implemented_sink = parse_implemented_merit_sink(evolution)
    curve = build_curve(config, nodes)
    target = config["target"]
    progression = config["progression"]
    novelty = config["novelty"]
    expected_runs = target["hours"] * 60.0 / target["run_minutes_expected"]
    novelty_beats = target["hours"] * 60.0 / target["novelty_beat_interval_minutes"]
    major_beats = target["hours"] * 60.0 / target["major_beat_interval_minutes"]
    raw_credits = (evolution["nodes"] * novelty["provisional_credit_per_aircraft"]
                   + skills["total"] * novelty["provisional_credit_per_skill"]
                   + len(bosses) * novelty["provisional_credit_per_boss"]
                   + maps.get("release_ready", 0) * novelty["provisional_credit_per_release_ready_map"])
    token_counts = Counter(int(row["token_cost"]) for row in enemies)
    roles = Counter(str(row["role"]) for row in enemies)
    unlocks = Counter(int(row["unlock"]) for row in enemies)
    first_boss_cycle_hours = len(bosses) * target["run_minutes_expected"] / 60.0
    map_gap = max(0, target["release_ready_maps"] - maps.get("release_ready", 0))
    boss_gap = max(0, target["bosses_minimum"] - len(bosses))

    lines = [
        "# AGL 量化内容与难度模型基线（2026-08-20）", "",
        "> 由 `tools/analysis/agl_quantitative_model.py` 从当前仓库生成。它是规划模型，不是已完成的平衡证明。",
        "> A/B 为当前数据或已批准约束；所有 C 级权重都在配置文件中，可被遥测替换。", "",
        "## 1. 当前可复算库存", "",
        f"- 玩家机：**{evolution['nodes']}** 节点 / **{evolution['edges']}** 条进化边；Tier 分布 {evolution['tiers']}；最高门槛 LV{evolution['max_level']}。（A）",
        f"- 技能：**{skills['total']}** 条；三轴 { {k: v for k, v in skills.items() if k != 'total'} }。（A）",
        f"- 常规敌机池：**{len(enemies)}** 行；角色 {dict(roles)}；Token 档 {dict(sorted(token_counts.items()))}。（A）",
        f"- BOSS：**{len(bosses)}** 组：{', '.join(bosses)}。（A）",
        f"- 地图选择：发布就绪 **{maps.get('release_ready', 0)}**、预览 **{maps.get('preview', 0)}**、锁定位 **{maps.get('locked', 0)}**。（A）",
        f"- Spec 状态：{specs}。（A；只反映索引元数据，不等于实玩质量）", "",
        "## 2. 曲线定义", "",
        "- 玩家局内纸面上限：`P_run(L) = TierMult(L) × (1 + min(0.25, 0.012 × (L-1)))`。TierMult 为 1.00/1.12/1.25/1.38/1.50；后半段为 C 级临时构筑增益，只用于看形状。",
        "- 玩家长期上限：`P_long = P_run × 1.15`。1.15 来自熟练度 M5 草案，未实装、未遥测。（C）",
        "- 敌方同时压力：`E(L) = (TokenBudget(L) / SpawnInterval(L)) / Lv1基线`；预算 `min(8+floor(1.8L),55)`，间隔 `lerp(32,18,clamp(L/20))`。（A）",
        "- 相对难度形状：`D(L) = E(L) / P_run(L)`。它只表达持续压力，不含 BOSS 机制、任务注意力、地形、玩家小队规模与 AI 转化率。（C）", "",
        "| LV | Token预算 | 刷新间隔(s) | 敌压指数 | 可达最高Tier | 玩家局内指数 | 长期上限 | 相对难度 | 累计XP门槛 |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in curve:
        lines.append(f"| {row.level} | {row.budget} | {row.interval:.1f} | {row.enemy_pressure:.2f} | T{row.tier} | {row.player_run_power:.2f} | {row.player_long_upper:.2f} | {row.relative_difficulty:.2f} | {xp_to_reach(row.level)} |")
    level20 = next(r for r in curve if r.level == 20)
    lines += ["",
        f"结论：持续敌压从 LV1 到 LV20 增长到 **{level20.enemy_pressure:.2f}×**，临时玩家纸面曲线约 **{level20.player_run_power:.2f}×**。后期主要靠场上总压力增长；是否合理必须接 FSR/命中率/TTK/存活率验证。", "",
        "## 3. 20 小时时间与经济", "",
        f"- 20 小时按每局 {target['run_minutes_expected']:.0f} 分钟约为 **{expected_runs:.0f} 局**。（C）",
        f"- 当前实现长期消费共 **{implemented_sink['total']:,}** 功勋（基础/支援 {implemented_sink['catalog']:,} + 学说 {implemented_sink['doctrines']:,} + 43 机专属 {implemented_sink['signatures']:,}）：按 2,500–7,500/局，需要 **{hours_for_sink(implemented_sink['total'], progression['merit_per_run_high'], target['run_minutes_expected']):.1f}–{hours_for_sink(implemented_sink['total'], progression['merit_per_run_low'], target['run_minutes_expected']):.1f} 小时**。（A/C）",
        f"- 加上熟练度草案研发项目后约 {progression['planned_long_term_sink']:,} 功勋：需要 **{hours_for_sink(progression['planned_long_term_sink'], progression['merit_per_run_high'], target['run_minutes_expected']):.1f}–{hours_for_sink(progression['planned_long_term_sink'], progression['merit_per_run_low'], target['run_minutes_expected']):.1f} 小时**。只有低收入端接近 20 小时，高收入端会过早买完。（C）",
        f"- 4 个 BOSS 若每局推进一次，首轮看完只需约 **{first_boss_cycle_hours:.1f} 小时**；新增 BOSS、重复击败新层与地图专属首遇必须进入长线排期。", "",
        "## 4. 新鲜度与内容缺口", "",
        f"- 每 {target['novelty_beat_interval_minutes']:.0f} 分钟一个新刺激，20 小时需约 **{novelty_beats:.0f} 个普通节拍**；每 {target['major_beat_interval_minutes']:.0f} 分钟一个大节拍，需约 **{major_beats:.0f} 个**。（C）",
        f"- 临时等价权重下，现有库存约 **{raw_credits:.1f} 新鲜度积分**。这只回答理论排期容量；没有曝光日程的内容不能算交付。（C）",
        f"- 发布地图硬缺口：**{map_gap} 张**（目标 3，当前完成 1，另有 2 张预览）。（A/B）",
        f"- 新 BOSS 最低规划缺口：**{boss_gap} 组**（临时底线 6，当前 4；最终数量由大节拍排期决定）。（C）",
        "- 机体与技能还缺多少目前是 D 级未知：43/165 是库存，没有统一的跨局 first_seen_at、unlock_cost、prerequisite、expected_run 排期表。先补曝光清单，才能判断缺内容还是缺编排。",
        f"- 敌机解锁覆盖 LV{min(unlocks)}–LV{max(unlocks)}；按等级分布 {dict(sorted(unlocks.items()))}。它描述单局压力，不代表跨局新鲜度。", "",
        "## 5. 下一轮必须采集的校准量", "",
        "1. 每局：时长、结算功勋、终局等级、技能选择、首次见到的机体/敌人/BOSS/任务/机制。",
        "2. 每次交战：FSR、命中率、TTK、有效 DPS、受击与脱离；分玩家/僚机/敌机/BOSS。",
        "3. 每 30 秒：在场 Token、实体数、可见 draw 数、FPS 分位与尖峰原因。",
        "4. 每个内容项：`first_seen_run/hour`、`first_used`、`repeat_count`、是否改变决策、刺激评分。",
        "5. 至少 20 个种子 × 起手/中位/上限 build，输出成功率和分位数。", "",
        "## 6. 当前裁决", "",
        "- 先补统一曝光排期与遥测，不立即用临时权重改游戏数值。",
        "- 20 小时窗口、40 个普通节拍 / 10 个大节拍及首批曝光清单见 `docs/planning/20-hour-content-exposure-plan.md`。",
        "- 生产先补 2 张完整地图、至少 2 个新 BOSS 设计槽，并给现有 BOSS 增加长线重复击败层；机制仍逐项 spec-first。",
        "- 性能继续以 36 名混合海陆空全可见 C1 为门；敌压增长必须在大规模战斗气氛下成立，不能靠减员或卸武器换帧。",
    ]
    return "\n".join(lines) + "\n"


def validate_sources(config: dict, report: str) -> None:
    evolution, _nodes = parse_evolution()
    enemies = parse_enemy_rows()
    skills = parse_skills()
    bosses = parse_bosses()
    maps = parse_maps()
    assert config["schema_version"] == 1, "unsupported config schema"
    assert evolution["nodes"] == sum(evolution["tiers"].values()), "evolution tier total drift"
    assert evolution["edges"] > evolution["nodes"], "evolution graph unexpectedly sparse"
    assert skills["total"] == sum(v for k, v in skills.items() if k != "total"), "skill axis total drift"
    assert len({row["id"] for row in enemies}) == len(enemies), "duplicate enemy id"
    assert len({int(row["type"]) for row in enemies}) == len(enemies), "duplicate enemy type"
    assert all(int(row["token_cost"]) > 0 and int(row["unlock"]) > 0 for row in enemies), "invalid enemy budget row"
    assert bosses, "boss registry empty"
    assert maps.get("release_ready", 0) > 0, "no release-ready map"
    assert "D 级未知" in report and "当前裁决" in report, "report lost uncertainty/decision sections"
    if CANONICAL_REPORT.exists():
        assert CANONICAL_REPORT.read_text(encoding="utf-8-sig") == report, "canonical report is stale"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--write-report", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    report = render_report(config)
    if args.write_report:
        target = args.write_report if args.write_report.is_absolute() else ROOT / args.write_report
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(report, encoding="utf-8", newline="\n")
    if args.check:
        validate_sources(config, report)
        print("quantitative model: sources, invariants and canonical report are consistent")
    elif not args.write_report:
        print(report, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
