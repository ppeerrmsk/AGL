# -*- coding: utf-8 -*-
"""提取 UPGRADES 全表 + i18n 中文名/描述 → 按三轴归类输出 markdown"""
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
    entries.append({
        "id": g("id"), "name": g("name"), "desc": g("desc"),
        "value": g("value").split("#")[0].strip().rstrip(","),
        "max_stacks": g("max_stacks").split("#")[0].strip().rstrip(","),
        "category": g("category"), "rarity": g("rarity").replace("Rarity.", "").split("#")[0].strip().rstrip(","),
        "evolved": '"evolved": true' in body,
        "requires": g("requires"), "exclusive_to": g("exclusive_to"),
    })

AXIS_BY_CAT = {"survival": "斗士", "secondary": "斗士", "mobility": "骑士",
               "missile": "骑士", "weapon": "骑士", "electronic_warfare": "策士"}
OVERRIDE = {"dogfight": "斗士", "fear_squad_spread": "策士", "fear_chills": "策士",
            "skill_gun_kill_flare_drop": "策士", "laser_cooldown": "策士",
            "laser_range": "策士", "laser_heat": "策士"}
GLAD = {"gun_ciws", "skill_missile_hit_invul", "skill_lowest_alt_kill_invul", "executioner"}
KNIGHT = {"jam_aura", "rear_aura_slow", "missile_swarm", "skill_evade_missile_overload",
          "skill_flare_overload", "jam_self_overload", "cloud_overload",
          "overload_duration_4x", "overload_extended_ammo", "overload_to_bloodlust"}
SCHEMER = {"skill_gun_kill_fear", "skill_head_on_aoe_fear", "skill_flare_aoe_jam",
           "skill_missile_hit_aoe_jam", "skill_torpedo_aoe_jam", "skill_gun_kill_flare_drop",
           "fear_squad_spread", "fear_chills", "ecm_pod", "evasion_stealth", "vapor_dodge"}
GEAR = {"railgun_charge", "railgun_range", "railgun_damage", "laser_cooldown", "laser_range",
        "laser_heat", "laser_extra_beams", "skill_laser_damage", "rocket_firerate_range",
        "torpedo_tracking_boost"}
ONCE = {"xp_mult"}
RAR_ZH = {"STABLE": "稳定", "ADVANCED": "先进", "EXPERIMENTAL": "实验", "CLASSIFIED": "机密", "NEXT_GEN": "次世代"}

def scope(e):
    i = e["id"]
    if i in GLAD: return "**斗士限定**"
    if i in KNIGHT: return "**骑士限定**"
    if i in SCHEMER: return "**策士限定**"
    if i in GEAR: return "装备门控"
    if i in ONCE: return "队级单实例"
    return "通用全队"

by_axis = collections.defaultdict(list)
for e in entries:
    e["axis"] = OVERRIDE.get(e["id"], AXIS_BY_CAT.get(e["category"], "斗士"))
    by_axis[e["axis"]].append(e)

out = []
out.append("# AGL 技能全表（%d 条）\n" % len(entries))
out.append("> 自动生成自 `SurvivorData.UPGRADES` + i18n 中文；归属列 = spec squad-upgrade-ownership §2.8 v5\n")
out.append("> ★ = 战区奖励池（不进随机抽卡）· 稀有度：稳定<先进<实验<机密<次世代\n")
for axis in ["斗士", "骑士", "策士"]:
    lst = by_axis[axis]
    out.append("\n## %s 轴（%d 条）\n" % (axis, len(lst)))
    out.append("| 技能 | 归属 | 稀有度 | 层数 | 效果 |")
    out.append("|---|---|---|---|---|")
    for e in sorted(lst, key=lambda x: (scope(x) == "通用全队", x["id"])):
        nm = zh.get(e["name"], e["name"])
        if e["evolved"]:
            nm = "★" + nm
        d = zh.get(e["desc"], "").replace("|", "／")
        extra = ""
        if e["exclusive_to"]:
            extra = " ⟨%s 专属⟩" % e["exclusive_to"]
        out.append("| %s%s | %s | %s | ×%s | %s |" % (
            nm, extra, scope(e), RAR_ZH.get(e["rarity"], e["rarity"]), e["max_stacks"], d))

cnt = collections.Counter(scope(e).replace("*", "") for e in entries)
out.append("\n## 归属统计\n")
out.append("| 归属 | 条数 |")
out.append("|---|---|")
for k, v in sorted(cnt.items(), key=lambda x: -x[1]):
    out.append("| %s | %d |" % (k, v))

io.open("docs/reference/skill-table.md", "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("wrote docs/reference/skill-table.md — %d skills" % len(entries))
print(dict(cnt))
