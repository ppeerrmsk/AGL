#!/usr/bin/env python3
"""Generate the 43-aircraft, three-axis static growth audit.

This intentionally reads the shipped tree/profile/params resources rather than
copying the balance table.  Output is deterministic and suitable for review or
CI diffs; it never starts Godot and never mutates game data.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path
from statistics import median


AXES = ("gladiator", "knight", "schemer")
GLADIATOR_GUN_FLOORS = {
    2: {"gun_damage_mult": 1.30, "gun_range": 1200.0, "gun_cone": 8.0, "aim_skill": 0.65},
    3: {"gun_damage_mult": 1.40, "gun_range": 1300.0, "gun_cone": 9.0, "aim_skill": 0.70},
    4: {"gun_damage_mult": 1.50, "gun_range": 1400.0, "gun_cone": 10.0, "aim_skill": 0.75},
    5: {"gun_damage_mult": 1.60, "gun_range": 1500.0, "gun_cone": 11.0, "aim_skill": 0.80},
}
NUMERIC_FIELDS = (
    "max_hp", "max_speed", "cruise_speed", "max_g", "roll_rate",
    "acceleration", "deceleration", "radar_range", "radar_half_angle",
    "lock_time",
)


def section(text: str, header: str) -> str:
    marker = f"[{header}]"
    start = text.find(marker)
    if start < 0:
        return ""
    end = text.find("\n[", start + len(marker))
    return text[start:] if end < 0 else text[start:end]


def scalar(block: str, key: str, default: float = 0.0) -> float:
    match = re.search(rf"(?m)^{re.escape(key)}\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*$", block)
    return float(match.group(1)) if match else default


def ext_resources(text: str) -> dict[str, str]:
    found: dict[str, str] = {}
    pattern = re.compile(r'^\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"[^\]]*\]$', re.M)
    for path, resource_id in pattern.findall(text):
        found[resource_id] = path.replace("res://", "")
    return found


def referenced_ext_id(block: str, key: str) -> str:
    match = re.search(rf'(?m)^{re.escape(key)}\s*=\s*ExtResource\("([^"]+)"\)', block)
    return match.group(1) if match else ""


def subresource_block(text: str, resource_id: str) -> str:
    marker = f'id="{resource_id}"'
    start = text.find("[sub_resource", 0)
    while start >= 0:
        line_end = text.find("\n", start)
        if marker in text[start:line_end]:
            end = text.find("\n[", line_end)
            return text[start:] if end < 0 else text[start:end]
        start = text.find("[sub_resource", line_end)
    return ""


def resource_id_for(block: str, key: str, kind: str) -> str:
    match = re.search(rf'(?m)^{re.escape(key)}\s*=\s*{kind}\("([^"]+)"\)', block)
    return match.group(1) if match else ""


def parse_signature_blocks(text: str) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for match in re.finditer(r'\{\s*\n\s*"id":\s*"(sig_[^"]+|f14_squad_lock_slow)"', text):
        start = match.start()
        end = text.find("\n\t},", start)
        if end < 0:
            continue
        block = text[start:end]
        entry: dict[str, str] = {"id": match.group(1)}
        for key in ("axis", "name", "desc", "scope"):
            value = re.search(rf'"{key}":\s*"([^"]+)"', block)
            if value:
                entry[key] = value.group(1)
        words = re.search(r'"keywords":\s*\[([^\]]*)\]', block)
        entry["keywords"] = ",".join(re.findall(r'"([^"]+)"', words.group(1))) if words else ""
        result[entry["id"]] = entry
    return result


def parse_aircraft_paths(text: str) -> dict[str, str]:
    return dict(re.findall(r'&"([^"]+)"\s*:\s*"res://([^"]+\.tres)"', text))


def load_aircraft(root: Path, node: dict, path_map: dict[str, str], signatures: dict) -> dict:
    aircraft_id = node["id"]
    profile_path = root / path_map[aircraft_id]
    profile_text = profile_path.read_text(encoding="utf-8")
    profile_res = section(profile_text, "resource")
    ext = ext_resources(profile_text)
    base_id = referenced_ext_id(profile_res, "base_params")
    params_path = root / ext[base_id]
    params_text = params_path.read_text(encoding="utf-8")
    params = section(params_text, "resource")

    row: dict[str, object] = {
        "id": aircraft_id,
        "tier": int(node["tier"]),
        "category": node.get("category", ""),
        "min_level": int(node.get("min_level", 1)),
        "profile": profile_path.relative_to(root).as_posix(),
        "params": params_path.relative_to(root).as_posix(),
    }
    display = re.search(r'(?m)^display_name\s*=\s*"([^"]+)"', params)
    row["display_name"] = display.group(1) if display else aircraft_id
    for field in NUMERIC_FIELDS:
        row[field] = scalar(params, field)

    missile_id = resource_id_for(params, "missile", "SubResource")
    missile = subresource_block(params_text, missile_id) if missile_id else ""
    row["missile_count"] = int(scalar(missile, "max_count"))
    missile_override = int(scalar(profile_res, "missile_count_override", -1.0))
    if missile_override >= 0:
        row["missile_count"] = missile_override
    row["missile_damage"] = scalar(missile, "damage")

    flare_id = referenced_ext_id(profile_res, "flare_override")
    if flare_id:
        flare_path = root / ext.get(flare_id, "")
    else:
        flare_id = referenced_ext_id(params, "flare")
        flare_path = root / ext_resources(params_text).get(flare_id, "")
    flare_text = flare_path.read_text(encoding="utf-8") if flare_id and flare_path.is_file() else ""
    row["flare_count"] = int(scalar(section(flare_text, "resource"), "max_flares"))

    gun_id = referenced_ext_id(params, "gun")
    gun_text = (root / ext_resources(params_text).get(gun_id, "")).read_text(encoding="utf-8") if gun_id else ""
    gun = section(gun_text, "resource")
    row["gun_damage_mult"] = scalar(profile_res, "gun_damage_mult", 1.0)
    row["gun_damage"] = scalar(gun, "bullet_damage") * float(row["gun_damage_mult"])
    row["gun_fire_rate"] = scalar(gun, "fire_rate")
    row["gun_ammo"] = int(scalar(gun, "max_ammo"))
    range_override = scalar(profile_res, "gun_range_override")
    cone_override = scalar(profile_res, "gun_cone_override")
    row["gun_range"] = range_override if range_override > 0.0 else scalar(gun, "max_range")
    row["gun_cone"] = cone_override if cone_override > 0.0 else scalar(gun, "fire_cone_half_angle")
    row["aim_skill"] = scalar(profile_res, "base_pilot_aim_skill")

    signature_id = "f14_squad_lock_slow" if aircraft_id == "f14" else f"sig_{aircraft_id}"
    sig = signatures.get(signature_id, {})
    row["signature_id"] = signature_id
    row["axis"] = sig.get("axis", "schemer" if aircraft_id == "f14" else "")
    row["signature_scope"] = sig.get("scope", "general")
    row["signature_keywords"] = sig.get("keywords", "")
    return row


def pct(new: float, old: float, inverse: bool = False) -> float:
    if old == 0:
        return 0.0
    value = (new / old - 1.0) * 100.0
    return -value if inverse else value


def tier_summary(rows: list[dict]) -> list[dict]:
    grouped: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for row in rows:
        grouped[(str(row["axis"]), int(row["tier"]))].append(row)
    fields = ("max_hp", "max_g", "roll_rate", "acceleration", "gun_damage",
              "gun_range", "gun_cone", "aim_skill", "radar_range", "lock_time",
              "missile_count", "flare_count")
    output: list[dict] = []
    for axis in AXES:
        for tier in range(1, 6):
            group = grouped.get((axis, tier), [])
            if not group:
                continue
            item: dict[str, object] = {"axis": axis, "tier": tier, "aircraft_count": len(group)}
            for field in fields:
                item[field] = round(median(float(row[field]) for row in group), 3)
            previous = next((x for x in reversed(output) if x["axis"] == axis), None)
            if previous:
                gains = [pct(float(item[f]), float(previous[f]), f == "lock_time") for f in fields]
                item["enhanced"] = sum(v > 2.0 for v in gains)
                item["flat"] = sum(-2.0 <= v <= 2.0 for v in gains)
                item["regressed"] = sum(v < -2.0 for v in gains)
            else:
                item.update({"enhanced": 0, "flat": 0, "regressed": 0})
            output.append(item)
    return output


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def gladiator_gun_violations(rows: list[dict]) -> list[str]:
    violations: list[str] = []
    for row in rows:
        tier = int(row["tier"])
        if row["axis"] != "gladiator" or tier < 2:
            continue
        floor = GLADIATOR_GUN_FLOORS[tier]
        for field, minimum in floor.items():
            actual = float(row[field])
            if actual + 1e-6 < minimum:
                violations.append(f"{row['id']} T{tier} {field}={actual:g} < {minimum:g}")
    return violations


def expected_missile_count(row: dict) -> int:
    tier = int(row["tier"])
    if tier <= 2:
        return 2
    if tier <= 4:
        return 3
    return 5 if row["category"] == "range" else 4


def ordnance_violations(rows: list[dict], nodes: list[dict]) -> list[str]:
    violations: list[str] = []
    by_id = {str(row["id"]): row for row in rows}
    for row in rows:
        expected_missile = expected_missile_count(row)
        if int(row["missile_count"]) != expected_missile:
            violations.append(
                f"{row['id']} T{row['tier']} missile_count={row['missile_count']} != {expected_missile}"
            )
        expected_flare = int(row["tier"]) + 1
        if int(row["flare_count"]) != expected_flare:
            violations.append(
                f"{row['id']} T{row['tier']} flare_count={row['flare_count']} != {expected_flare}"
            )
    for node in nodes:
        source = by_id[str(node["id"])]
        for target_id in node.get("exits", []):
            target = by_id[str(target_id)]
            if int(target["tier"]) > int(source["tier"]) \
                    and int(target["missile_count"]) < int(source["missile_count"]):
                violations.append(
                    f"edge {source['id']} T{source['tier']} M{source['missile_count']} -> "
                    f"{target['id']} T{target['tier']} M{target['missile_count']} regresses"
                )
    return violations


def render_report(rows: list[dict], summary: list[dict], gun_violations: list[str],
                  ordnance_errors: list[str]) -> str:
    by_axis = {axis: [r for r in rows if r["axis"] == axis] for axis in AXES}
    lines = [
        "# 43 机三轴静态成长审计",
        "",
        "> 自动读取正式 `.tres`、进化树与签名技能表。这里只判定机体自身基数；不把随机技能计入成长。",
        "",
        f"覆盖：{len(rows)} / 43 机；斗士 {len(by_axis['gladiator'])}、骑士 {len(by_axis['knight'])}、策士 {len(by_axis['schemer'])}。",
        "",
        "## 各轴 Tier 中位数变化",
        "",
        "| 轴 | Tier | 机数 | HP | G | 滚转 | 加速 | 炮伤 | 炮距 | 开火半角 | 瞄准 | 雷达 | 锁定秒 | 导弹 | Flare | 增强/持平/倒退 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    axis_names = {"gladiator": "斗士", "knight": "骑士", "schemer": "策士"}
    for item in summary:
        rendered = dict(item)
        rendered["axis_label"] = axis_names[str(item["axis"])]
        lines.append(
            "| {axis_label} | T{tier} | {aircraft_count} | {max_hp:g} | {max_g:g} | {roll_rate:g} | "
            "{acceleration:g} | {gun_damage:g} | {gun_range:g} | {gun_cone:g} | {aim_skill:g} | {radar_range:g} | "
            "{lock_time:g} | {missile_count:g} | {flare_count:g} | {enhanced}/{flat}/{regressed} |".format(
                **rendered
            )
        )

    fighter = [item for item in summary if item["axis"] == "gladiator"]
    gun_fields = ("gun_damage", "gun_range", "gun_cone", "aim_skill")
    gun_growth_ok = all(
        all(float(current[field]) > float(previous[field]) for field in gun_fields)
        for previous, current in zip(fighter, fighter[1:])
    )
    verdict = "通过" if not gun_violations and gun_growth_ok else "不通过"
    lines.extend([
        "",
        "## 斗士线结论",
        "",
        f"**{verdict}**。斗士 T2–T5 的炮伤倍率、射程、开火半角和瞄准全部达到 Tier 下限，四项 Tier 中位数也必须逐档上升；导弹和 flare 不计入斗士机炮成长。",
        "",
        "Tier 下限：T2=1.30×/1200m/8°/0.65，T3=1.40×/1300m/9°/0.70，T4=1.50×/1400m/10°/0.75，T5=1.60×/1500m/11°/0.80。射速 3000 rpm 与弹药 200 保持共同基线。",
        "",
        "违规项：" + ("无" if not gun_violations else "；".join(gun_violations)),
        "",
        "## 导弹与 Flare 分档",
        "",
        "主导弹默认挂载：T1/T2=2、T3/T4=3、T5=4；仅 T5 远程专精 X-21=5。Flare 保持 T1→T5 = 2/3/4/5/6。",
        "",
        "分档与直接进化边违规项：" + ("无" if not ordnance_errors else "；".join(ordnance_errors)),
        "",
        "## 解释边界",
        "",
        "- 用户已取消 320 局实战；本轮完成条件只按正式参数与 Tier 下限判定，不使用两局残留样本。",
        "- 策士的 JAM/团队收益属于行为能力，CSV 以签名关键词和 scope 保留证据，最终可靠性必须由行为 bench 验证。",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--out", type=Path, default=Path("bench/results/evolution_growth"))
    args = parser.parse_args()
    root = args.root.resolve()
    out = args.out if args.out.is_absolute() else root / args.out

    tree = json.loads((root / "resources/evolution/evolution_tree.json").read_text(encoding="utf-8"))
    path_map = parse_aircraft_paths((root / "scripts/survivor/aircraft_db.gd").read_text(encoding="utf-8"))
    signatures = parse_signature_blocks((root / "scripts/survivor/survivor_data.gd").read_text(encoding="utf-8"))
    rows = [load_aircraft(root, node, path_map, signatures) for node in tree["nodes"]]
    if len(rows) != 43:
        raise SystemExit(f"expected 43 aircraft, got {len(rows)}")
    missing_axes = [row["id"] for row in rows if row["axis"] not in AXES]
    if missing_axes:
        raise SystemExit(f"missing signature axis: {missing_axes}")

    summary = tier_summary(rows)
    gun_violations = gladiator_gun_violations(rows)
    ordnance_errors = ordnance_violations(rows, tree["nodes"])
    out.mkdir(parents=True, exist_ok=True)
    write_csv(out / "aircraft_growth.csv", rows)
    write_csv(out / "axis_tier_summary.csv", summary)
    (out / "aircraft_growth.json").write_text(
        json.dumps({"aircraft": rows, "tier_summary": summary}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (out / "growth_audit.md").write_text(
        render_report(rows, summary, gun_violations, ordnance_errors), encoding="utf-8"
    )
    print(f"growth audit: {len(rows)} aircraft -> {out}")
    if gun_violations:
        print("gladiator gun floor violations:")
        for violation in gun_violations:
            print(f"- {violation}")
    if ordnance_errors:
        print("missile/flare tier violations:")
        for violation in ordnance_errors:
            print(f"- {violation}")
    if gun_violations or ordnance_errors:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
