class_name FlareEquipment
extends EvasionModule

## 热诱弹装备包装器（commit 5/13 — 装备模块化）
##
## 第一个 EvasionModule 子类，给 commit 6 的 CobraEvasion / HerbstEvasion 立 pattern。
##
## 持 FlareParams 配置，状态全在 Aircraft：flares_remaining /
## _flare_cooldown / flare_reload_progress 等，由 AircraftFlares.update + release 读写。
##
## should_trigger / execute_evasion 暂留 base 默认（no-op）—— 实际触发仍由
## AircraftFlares.update 自动判定。等 commit 7 TacticalPlanner 投票模型上线后，
## 把判定逻辑搬进来：should_trigger 返回 calc_jam_chance × confidence，
## execute_evasion 调 AircraftFlares.release。

@export var flare: FlareParams


func _init() -> void:
	equipment_kind = "flare"


func ammo_ratio(ac) -> float:
	if flare == null or flare.max_flares <= 0:
		return 1.0
	return clampf(float(ac.flares_remaining) / float(flare.max_flares), 0.0, 1.0)


func cooldown_ratio(ac) -> float:
	if flare == null or flare.cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - ac._flare_cooldown / flare.cooldown, 0.0, 1.0)
