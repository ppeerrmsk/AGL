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

# ══════════════════════════════════════════════
#  成员判定
# ══════════════════════════════════════════════

## tier 成员名单（spec §1.2）。加新王牌中队**只改这一处**。
static func is_ace_type(etype: int) -> bool:
	return etype == SurvivorSpawner.EnemyType.F47 \
			or etype == SurvivorSpawner.EnemyType.F14_POLTERGEIST

## 给已生成的单位打 tier 标记（spawn 时调用一次）
static func mark(unit: Node) -> void:
	if unit != null:
		unit.set_meta(TIER_META, TIER_ACE)

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
