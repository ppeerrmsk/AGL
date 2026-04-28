class_name MissileEquipment
extends EquipmentParams

## 导弹装备包装器（commit 4/13 — 装备模块化）
##
## 同一类同时承载主导弹（空对空，对应 params.missile）和副导弹（空对地，
## params.secondary_missile）。`is_secondary` 字段决定 publish 路径。
##
## 状态全在 Aircraft：missiles_remaining / secondary_missiles_remaining /
## _missile_cooldown / _crank_timer / _was_locking_missile / _multi_lock_targets
## / _multi_lock_armed 等，由 AircraftWeapons.update_missile +
## _fire_missile_at + _fire_multi_lock_salvo 读写。
##
## equipment_kind 永远是 "missile"。生存模式升级过滤
## `has_equipment_of_kind("missile")` 对主/副导弹都返回 true。
## 如未来需要"只主导弹升级"，可加 has_equipment_with_slot 接口。

@export var missile: MissileParams

## false = 主导弹（空对空），发布到 params.missile
## true  = 副导弹（空对地），发布到 params.secondary_missile
@export var is_secondary: bool = false


func _init() -> void:
	equipment_kind = "missile"


## 给 commit 8 TacticalPlanner 的接战偏好。
## 主导弹（空对空）：MERGE_PASS / LEAD_PURSUIT 中长距，priority=0.7（高于机炮）
## 副导弹（空对地）：不参与 BFM 投票，对地走独立 update_combat_ground_attack 状态
func desired_engagement(_situation):
	if missile == null or is_secondary:
		return null
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.LEAD_PURSUIT
	pref.preferred_range_m = missile.max_range_rear * 0.6
	pref.priority = 0.7
	pref.needs_lock = not missile.fire_and_forget
	pref.needs_los = not missile.fire_and_forget
	pref.rationale = "missile_a2a"
	return pref


func ammo_ratio(ac) -> float:
	if missile == null or missile.max_count <= 0:
		return 1.0
	var remaining: int = ac.secondary_missiles_remaining if is_secondary else ac.missiles_remaining
	return clampf(float(remaining) / float(missile.max_count), 0.0, 1.0)


func cooldown_ratio(ac) -> float:
	if missile == null or missile.cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - ac._missile_cooldown / missile.cooldown, 0.0, 1.0)
