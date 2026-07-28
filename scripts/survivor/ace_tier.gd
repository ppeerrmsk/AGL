## 王牌中队 tier（Ace Squadron Tier）—— tier 语义的**单一归属地**
##
## 设计权威源：docs/specs/systems/ace-squadron-tier.md
##
## ── 为什么单独成模块 ──
## tier 待遇原本散在三处、各写各的判定：
##   1. LOD 豁免      → survivor_mode 看 `category == "boss"` meta
##   2. 等级缩放豁免  → survivor_spawner 按 EnemyType 枚举逐个列举
##   3. HP cap 豁免   → survivor_spawner 另写一条 `etype != UAV_COMMANDER`
## 加一个新的王牌中队要同时改三处，漏一处就**静默退化成杂兵**（历史上 F-47 正是
## 因为落在 HP cap 里而被任何一发导弹秒杀）。本模块把「谁是王牌中队」+「王牌中队
## 享受什么例外」收成一处，调用方只问不判。
##
## ── 概念层级 ──
## **BOSS ⊂ 王牌中队**。BOSS 额外带 `category == "boss"`（专属演出 + 击败即过关），
## 但 tier 级待遇（不吃 LOD / 无等级缩放 / HP cap 豁免）一律走本模块，**不看 category**
## —— 否则将来加"非 BOSS 的王牌中队"时拿不到这些待遇。

class_name AceTier
extends RefCounted

# ══════════════════════════════════════════════
#  tier 标记
# ══════════════════════════════════════════════

const TIER_META := &"tier"
const TIER_ACE := "ace"

# ══════════════════════════════════════════════
#  数值（spec §2，权威源在 spec，这里是落地副本）
# ══════════════════════════════════════════════

## 王牌中队血量。**高于全部玩家导弹伤害**（最强 AGM-65 = 90）——
## 保证耗尽热诱弹后必定先经过一个残血阶段，而不是当场坠毁。
## 这是与普通飞机"导弹一击必杀"铁律的本质区别（spec §2.3）。
const MAX_HP := 100.0

## 王牌飞行员枪法（spec bosses/wraith-squadron §2.4）。
## 机炮梭起手误差 = lerp(5.0°, 0.5°, skill)，故 0.85 → ±1.175° ≈ ±1.2°。
##
## ⚠ 这不是削弱，是**补上一个从来没生效过的机制**：瞄准误差通路此前被
##   `use_tactical_preference` 门死（那是"玩家有战术偏好面板"的操控标志），
##   全部 AI 敌机——包括 BOSS——一直在打一个完美居中的散布锥。王牌飞行员
##   打得比杂兵准，但**不是机器人**：玩家的胜利应该来自抓住失误的瞬间。
const PILOT_AIM_SKILL := 0.85

# ══════════════════════════════════════════════
#  成员判定
# ══════════════════════════════════════════════

## tier 成员名单（spec §1.2）。加新王牌中队**只改这一处**。
static func is_ace_type(etype: int) -> bool:
	return etype == SurvivorSpawner.EnemyType.F47 \
			or etype == SurvivorSpawner.EnemyType.F14_POLTERGEIST

## 给已生成的单位打 tier 标记（spawn 时调用一次）+ 落地 tier 级的单位属性。
##
## 目前只有"执行精度失误"一项：开瞄准误差通路 + 写王牌枪法。放在这里而不是散到
## f47_ace_squad / poltergeist_squad，是因为本模块是 tier 语义的单一归属地 ——
## 将来加第三个王牌中队不用再想起这件事。
static func mark(unit: Node) -> void:
	if unit == null:
		return
	unit.set_meta(TIER_META, TIER_ACE)
	if unit is Aircraft:
		var ac := unit as Aircraft
		ac.gun_aim_error_enabled = true
		ac.pilot_aim_skill = PILOT_AIM_SKILL

## 运行时查询：这个单位是不是王牌中队？
## LOD / 清理 / 任何需要"关键单位"语义的地方都走这里，不要自己看 meta。
static func is_ace(unit: Node) -> bool:
	return unit != null and unit.has_meta(TIER_META) \
			and String(unit.get_meta(TIER_META)) == TIER_ACE

# ══════════════════════════════════════════════
#  tier 待遇
# ══════════════════════════════════════════════

## 无等级缩放（spec §2.1）：王牌中队按满级玩家平衡，固定参数。
## 返回新字典而非 const —— 调用方可能就地改，不能共享同一实例。
static func no_scale() -> Dictionary:
	return {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}

## 是否豁免 ENEMY_HP_MISSILE_CAP（"导弹一击必杀"铁律）。
## 例外必须显式判定，不靠把数值填到 cap 以下擦边（spec §2.3）。
static func exempt_from_hp_cap(etype: int) -> bool:
	return is_ace_type(etype)

## 参数期应用 tier 血量。在等级缩放与 HP cap 之后调用，让它成为最终值。
static func apply_hp(params: AircraftParams) -> void:
	if params != null:
		params.max_hp = MAX_HP
