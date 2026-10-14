extends RefCounted

## Wraith 的强化装配策略；通用恐惧模块不认识 BOSS 身份或生涯档案。
const FEAR_UNLOCK_DEFEATS := 3
const FEAR_CONE := preload("res://resources/wraith_fear_cone.tres")

static func fear_cone_for_progression(defeat_count: int) -> SquadFearConeConfig:
	if defeat_count < FEAR_UNLOCK_DEFEATS:
		return null
	return FEAR_CONE.duplicate(true) as SquadFearConeConfig
