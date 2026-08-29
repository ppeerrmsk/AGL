class_name SurvivorRuntimeReset
extends RefCounted

## 跨场景局内 static 的统一清理入口。场景树销毁不等于 RefCounted/static 运行态终止。

const SurvivorSkillRuntimeScript = preload(
	"res://scripts/survivor/survivor_skill_runtime.gd")


static func reset_cross_scene_state(enable_objectives: bool) -> void:
	AceReinforcementEvent.reset_runtime_state()
	SurvivorSkillRuntimeScript.reset_team_state()
	ObjectiveContext.reset()
	ObjectiveContext.enabled = enable_objectives
	SkillHooks.cloud_relaying = false
	SkillHooks.ghost_buster_team_hp_gained = 0.0
