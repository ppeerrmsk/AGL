class_name GunEquipment
extends EquipmentParams

## 机炮装备包装器（commit 2/13 — 装备模块化）
##
## 持有一份 GunParams 配置，对外通过 EquipmentParams 接口暴露。
## 装备本身无状态 —— 弹药 / 冷却 / fire 状态仍住在 Aircraft（_fire_cooldown / ammo /
## is_firing / _gun_reload_active 等），由 AircraftWeapons.update_gun 读写。
##
## 迁移期 hack：Aircraft._ready 检测到 GunEquipment 时，会把内部 gun 字段
## 发布到 params.gun，让所有现存 25 处 `params.gun` 读取继续工作（renderer / hud /
## debug / situation / bfm_tactics / aircraft_weapons / aircraft_combat_tracking）。
## 这是 commit 12 清理前的兼容层。

@export var gun: GunParams


func _init() -> void:
	equipment_kind = "gun"


## 给 TacticalPlanner（commit 8 接入）的接战偏好。
## 机炮 = 近战族：贴脸打，preferred_range = max_range × 0.5（甜点距离），CLOSE_TAIL。
func desired_engagement(_situation):
	if gun == null:
		return null
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.CLOSE_TAIL
	pref.preferred_range_m = gun.max_range * 0.5
	pref.priority = 0.6
	pref.needs_lock = false
	pref.needs_los = true
	pref.rationale = "gun"
	return pref


## 弹药剩余比例 0-1
func ammo_ratio(ac) -> float:
	if gun == null or gun.max_ammo <= 0:
		return 1.0
	return clampf(float(ac.ammo) / float(gun.max_ammo), 0.0, 1.0)


## 冷却比例 0-1（1.0 = 就绪）
func cooldown_ratio(ac) -> float:
	if gun == null or gun.fire_rate <= 0.0:
		return 1.0
	var cycle := 60.0 / gun.fire_rate
	if cycle <= 0.0:
		return 1.0
	return clampf(1.0 - ac._fire_cooldown / cycle, 0.0, 1.0)
