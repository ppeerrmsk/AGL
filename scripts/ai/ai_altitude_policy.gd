class_name AIAltitudePolicy
extends RefCounted

## AI 高度目标策略（无状态静态模块）
##
## 巡逻、远距作战与近距高度匹配是飞行剖面策略，不属于任何具体 BFM 执行器。
## 独立后，AIController / MissileEvasion / TacticalPlanner 过渡均不再依赖旧 BFMTactics。

const COMBAT_ALT_TARGET_MARGIN := 2500.0


## 近距 / 机炮战：直接匹配当前目标高度。
static func match_target(ai: AIController) -> void:
	if not ai._current_target:
		return
	if ai.aircraft.flat_altitude:
		ai.aircraft.set_target_tier(ai._current_target.get_altitude_tier())
	else:
		ai.aircraft.target_altitude = ai._current_target.altitude


## 远距 / 导弹战：保留自身巡逻偏好，但钳在目标 ±2500m 内。
static func use_combat_preference(ai: AIController) -> void:
	if not ai._current_target:
		set_patrol(ai)
		return
	var tgt_alt: float = ai._current_target.altitude
	var prefer: float = ai.patrol_altitude if ai.patrol_altitude > 0.0 else tgt_alt
	var combat_alt := clampf(
		prefer, tgt_alt - COMBAT_ALT_TARGET_MARGIN, tgt_alt + COMBAT_ALT_TARGET_MARGIN)
	if ai.aircraft.flat_altitude:
		var tgt_tier: int = ai._current_target.get_altitude_tier()
		var prefer_tier := altitude_to_tier(prefer)
		ai.aircraft.set_target_tier(clampi(prefer_tier, tgt_tier - 1, tgt_tier + 1))
	else:
		if ai.aircraft.params:
			combat_alt = clampf(combat_alt, 200.0, ai.aircraft.params.max_altitude - 200.0)
		ai.aircraft.target_altitude = combat_alt


## 状态过渡 / 脱险恢复：回到本机巡逻高度。
static func set_patrol(ai: AIController) -> void:
	if ai.aircraft.flat_altitude:
		ai.aircraft.set_target_tier(Aircraft.AltitudeTier.MID)
	else:
		ai.aircraft.target_altitude = ai.patrol_altitude


static func altitude_to_tier(altitude: float) -> int:
	if altitude < 3500.0:
		return CombatUnit.AltitudeTier.LOW
	if altitude < 7500.0:
		return CombatUnit.AltitudeTier.MID
	return CombatUnit.AltitudeTier.HIGH
