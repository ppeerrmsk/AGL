# -*- coding: utf-8 -*-
"""提取 UPGRADES 全表 + i18n 中文 → 按三轴归类输出 markdown。
720 批起（spec skills-720-rework）：归属列直读数据字段 scope/classes/requires，
不再维护硬编码 id 集合；轴归类吃显式 "axis" 字段；新增 "+1 轴" 列（milestone_plus）。"""
import re, io, csv, collections

src = io.open("scripts/survivor/survivor_data.gd", encoding="utf-8").read().replace("\r\n", "\n")

zh = {}
with io.open("i18n/translations.csv", encoding="utf-8") as f:
    for row in csv.reader(f):
        if len(row) >= 2:
            zh[row[0]] = row[1]

start = src.index("const UPGRADES")
i = src.index("= [", start) + 2
depth = 0
for j in range(i, len(src)):
    if src[j] == "[":
        depth += 1
    elif src[j] == "]":
        depth -= 1
        if depth == 0:
            end = j
            break
block = src[i:end]

# 按 "id": 切块解析（每个条目从 "id" 开始到下一个 "id" 前）
chunks = re.split(r'(?=\n\s*"id":)', block)
entries = []
for body in chunks:
    if '"id":' not in body:
        continue
    def g(key, b=body):
        mm = re.search(r'"%s":\s*("([^"]*)"|&?"?[^,\n]+)' % key, b)
        if not mm:
            return ""
        v = mm.group(2) if mm.group(2) is not None else mm.group(1)
        return v.strip().strip('"').strip()
    def garr(key, b=body):
        mm = re.search(r'"%s":\s*\[([^\]]*)\]' % key, b)
        if not mm:
            return []
        return [x.strip().strip('"') for x in mm.group(1).split(",") if x.strip().strip('"')]
    entries.append({
        "id": g("id"), "name": g("name"), "desc": g("desc"),
        "value": g("value").split("#")[0].strip().rstrip(","),
        "max_stacks": g("max_stacks").split("#")[0].strip().rstrip(","),
        "category": g("category"), "rarity": g("rarity").replace("Rarity.", "").split("#")[0].strip().rstrip(","),
        "evolved": '"evolved": true' in body,
        "requires": garr("requires"), "exclusive_to": garr("exclusive_to"),
        "classes": garr("classes"), "scope": g("scope"),
        "milestone_plus": g("milestone_plus"), "axis": g("axis"),
    })

AXIS_BY_CAT = {"survival": "斗士", "secondary": "斗士", "mobility": "骑士",
               "missile": "骑士", "weapon": "骑士", "electronic_warfare": "策士"}
OVERRIDE = {"dogfight": "斗士", "fear_squad_spread": "策士", "fear_chills": "策士",
            "skill_gun_kill_flare_drop": "策士", "laser_cooldown": "策士",
            "laser_range": "策士", "laser_heat": "策士"}
AXIS_ZH = {"gladiator": "斗士", "knight": "骑士", "schemer": "策士"}
## 装备门控 = 特殊装备 requires（gun/missile/flare 人人都有，不算门控）
SPECIAL_GEAR = {"railgun", "laser", "rocket", "torpedo", "loyal_wingman", "secondary_missile"}
RAR_ZH = {"STABLE": "稳定", "ADVANCED": "先进", "EXPERIMENTAL": "实验", "CLASSIFIED": "机密", "NEXT_GEN": "次世代"}


def scope(e):
    if e["scope"] == "squad_once":
        return "队级单实例"
    parts = []
    if e["classes"]:
        parts.append("**%s限定**" % "/".join(AXIS_ZH.get(c, c) for c in e["classes"]))
    if e["scope"] == "ace":
        parts.append("**王牌**")
    if parts:
        return "＋".join(parts)
    if set(e["requires"]) & SPECIAL_GEAR:
        return "装备门控"
    return "通用全队"


def plus_axis(e):
    return AXIS_ZH.get(e["milestone_plus"], "—") + ("+1" if e["milestone_plus"] else "")


by_axis = collections.defaultdict(list)
for e in entries:
    if e["axis"]:
        e["axis_zh"] = AXIS_ZH.get(e["axis"], e["axis"])
    else:
        e["axis_zh"] = OVERRIDE.get(e["id"], AXIS_BY_CAT.get(e["category"], "斗士"))
    by_axis[e["axis_zh"]].append(e)

out = []
out.append("# AGL 技能全表（%d 条）\n" % len(entries))
out.append("> 自动生成自 `SurvivorData.UPGRADES` + i18n 中文；归属列直读数据字段（spec skills-720-rework §1.2 归属词汇 v6）\n")
out.append("> ★ = 战区奖励池（不进随机抽卡）· 稀有度：稳定<先进<实验<机密<次世代 · +1 轴 = milestone_plus（里程碑进度，非门槛点）\n")
for axis in ["斗士", "骑士", "策士"]:
    lst = by_axis[axis]
    out.append("\n## %s 轴（%d 条）\n" % (axis, len(lst)))
    out.append("| 技能 | 归属 | 稀有度 | 层数 | +1 轴 | 效果 |")
    out.append("|---|---|---|---|---|---|")
    for e in sorted(lst, key=lambda x: (scope(x) == "通用全队", x["id"])):
        nm = zh.get(e["name"], e["name"])
        if e["evolved"]:
            nm = "★" + nm
        d = zh.get(e["desc"], "").replace("|", "／")
        extra = ""
        if e["exclusive_to"]:
            extra = " ⟨%s 专属⟩" % "/".join(e["exclusive_to"])
        out.append("| %s%s | %s | %s | ×%s | %s | %s |" % (
            nm, extra, scope(e), RAR_ZH.get(e["rarity"], e["rarity"]), e["max_stacks"], plus_axis(e), d))

cnt = collections.Counter(scope(e).replace("*", "") for e in entries)
out.append("\n## 归属统计\n")
out.append("| 归属 | 条数 |")
out.append("|---|---|")
for k, v in sorted(cnt.items(), key=lambda x: -x[1]):
    out.append("| %s | %d |" % (k, v))
mp = collections.Counter(AXIS_ZH.get(e["milestone_plus"], "") for e in entries if e["milestone_plus"])
out.append("\n**+1 轴进度分布**：" + " · ".join("%s+1 ×%d" % (k, v) for k, v in sorted(mp.items(), key=lambda x: -x[1])))

io.open("docs/reference/skill-table.md", "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("wrote docs/reference/skill-table.md — %d skills" % len(entries))
print(dict(cnt), dict(mp))
