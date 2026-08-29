class_name SurvivorSkillRuntime
extends RefCounted

## 玩家技能总账本 → 队级运行时资源/静态开关。
## 单机技能触发器读取 aircraft.meta["upgrade_stacks"]；只有真正的队级状态放在这里同步。


static func sync_team_state(stacks: Dictionary, afterburner_charge: AfterburnerCharge) -> void:
	if afterburner_charge != null:
		afterburner_charge.kill_charge_bonus = 0.6 * float(stacks.get("ab_kill_charge", 0))
		afterburner_charge.duration_mult = 1.0 + 0.5 * float(stacks.get("ab_duration", 0))
	StatusEffects.sig_x13_active = int(stacks.get("sig_x13", 0)) > 0
	SkillHooks.sig_fcas_active = int(stacks.get("sig_fcas", 0)) > 0
	SkillHooks.sig_f35_active = int(stacks.get("sig_f35", 0)) > 0
	SkillHooks.sig_x90_active = int(stacks.get("sig_x90", 0)) > 0
	SkillHooks.hush_active = int(stacks.get("hush", 0)) > 0


## static 状态跨场景存活；新局必须显式恢复账本为空时的基线。
static func reset_team_state() -> void:
	StatusEffects.sig_x13_active = false
	SkillHooks.sig_fcas_active = false
	SkillHooks.sig_f35_active = false
	SkillHooks.sig_x90_active = false
	SkillHooks.hush_active = false
