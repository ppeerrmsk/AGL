class_name EquipmentParams
extends Resource

## 装备基类（武器 / 反制 / 规避模块统一抽象）
##
## 设计目标：让 Aircraft 持一个 equipment: Array[EquipmentParams]，
## 没装就没行为 —— 武器、热诱弹、机动模块都通过同一接口注入。
##
## 子类按需覆写虚方法。基类返回中性默认值，未覆写即 no-op。
## 详细分阶段重构计划见 docs/changelogs/2026-04-28-equipment-scaffolding.md

@export_group("身份")
## 装备种类标识。生存模式升级过滤通过此字段判定 requires_equipment_kind。
## 约定值："gun" / "missile" / "rocket" / "ciws" / "flare" / "railgun" / "laser"
##         / "cobra" / "herbst" / "chaff" / "ecm"
@export var equipment_kind: String = ""

## 显示名（debug / EventLogger 用，玩家可见 UI 走 i18n key）
@export var display_name: String = ""


# ─────────── 攻击装备虚接口 ───────────

## 当前是否能开火（射程 / 锁定 / 弹药 / 冷却 / 过热 综合判定）
## ac: Aircraft 实例。target: 候选目标（CombatUnit/Missile/null）。
func can_fire(_ac, _target) -> bool:
	return false


## 给 TacticalPlanner 的接战偏好。返回 null 表示"我无意见"。
## 返回 EngagementPreference 表示"我希望飞机做某种 BFM 行为"。
func desired_engagement(_situation):
	return null


## 实际开火。由 TacticalPlanner 投票胜出后调用。
func fire(_ac, _target) -> void:
	pass


## 每帧更新（冷却 / 弹药再装 / 过热散热 / 视觉效果维护）
func update(_ac, _delta: float) -> void:
	pass


# ─────────── 状态查询（UI / debug 用） ───────────

## 弹药剩余比例 0-1（无弹药概念返回 1.0）
func ammo_ratio(_ac) -> float:
	return 1.0


## 冷却比例 0-1（1.0 = 就绪）
func cooldown_ratio(_ac) -> float:
	return 1.0
