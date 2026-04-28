class_name RocketEquipment
extends EquipmentParams

## 无制导火箭弹装备包装器（commit 3/13 — 装备模块化）
##
## 持有 RocketParams 配置，与 GunEquipment 同模式：
## 装备本身无运行时状态，弹药 / 冷却 / fire 队列仍住在 Aircraft
## （rockets_remaining / _rocket_queue / _rocket_burst_cooldown 等），
## 由 AircraftWeapons.update_rocket 直接读写。
##
## 老路径 publish hack：Aircraft._ready 把 rocket 字段同步到 params.rocket，
## 现存 4 处 `params.rocket` 读取（全在 aircraft_weapons.gd）继续工作。

@export var rocket: RocketParams


func _init() -> void:
	equipment_kind = "rocket"


## 给 commit 8 TacticalPlanner 的接战偏好。
## 火箭弹 = 中距非制导副武器：min/max_fire_range 中段甜点，TAIL_CHASE，低 priority
## （比机炮低，因为多数挂火箭弹的飞机也有机炮，机炮该优先；纯火箭弹机型很少见）。
func desired_engagement(_situation):
	if rocket == null:
		return null
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.TAIL_CHASE
	pref.preferred_range_m = (rocket.min_range + rocket.max_fire_range) * 0.5
	pref.priority = 0.4
	pref.needs_lock = false
	pref.needs_los = true
	pref.rationale = "rocket"
	return pref


func ammo_ratio(ac) -> float:
	if rocket == null or rocket.max_ammo <= 0:
		return 1.0
	return clampf(float(ac.rockets_remaining) / float(rocket.max_ammo), 0.0, 1.0)


func cooldown_ratio(ac) -> float:
	if rocket == null or rocket.burst_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - ac._rocket_burst_cooldown / rocket.burst_cooldown, 0.0, 1.0)
