extends RefCounted

## 战场规则流程专项：净时间轴、战区关闭事务、王牌固定槽、宿敌门与跨场景重置。

const EXPECTED_ASSERTIONS := 31
const BattlefieldFlowScript = preload("res://scripts/survivor/battlefield_flow.gd")
const SurvivorRuntimeResetScript = preload(
	"res://scripts/survivor/survivor_runtime_reset.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 战场任务流程重构 ════════")
	_test_time_authority()
	_test_warzone_close_transaction()
	_test_ace_schedule_latch()
	_test_orion_once_gate()
	_test_cross_scene_reset()
	var executed := _pass + _fail
	if executed != EXPECTED_ASSERTIONS:
		_fail += 1
		print("  ✗ 验收未完整执行 assertions=%d expected=%d" % [
			executed, EXPECTED_ASSERTIONS])
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _test_time_authority() -> void:
	print("── A. 净时间轴 ──")
	var flow = BattlefieldFlowScript.new()
	flow.reset_run(600.0)
	flow.advance_time(10.0, false, null)
	_check("正常物理帧推进", is_equal_approx(flow.game_time, 10.0))
	flow.advance_time(5.0, true, null)
	_check("预热/暂停阻断推进", is_equal_approx(flow.game_time, 10.0))
	_check("剩余时间来自同一权威", is_equal_approx(flow.remaining_s(), 590.0))
	_check("补给时间税返回实际推进量",
		is_equal_approx(flow.apply_time_cost(30.0), 30.0)
		and is_equal_approx(flow.game_time, 40.0))
	_check("延长只倒拨到零",
		is_equal_approx(flow.grant_time_extension(60.0, null), 40.0)
		and is_zero_approx(flow.game_time))
	flow.set_game_time(590.0)
	_check("时间税钳在战区终点",
		is_equal_approx(flow.apply_time_cost(30.0), 10.0)
		and is_equal_approx(flow.game_time, 600.0))


func _test_warzone_close_transaction() -> void:
	print("── B. 战区关闭事务 ──")
	var flow = BattlefieldFlowScript.new()
	flow.reset_run(600.0)
	var zones := ZoneData.new(Callable(), false, false)
	zones.select_zone(&"A")
	_check("到点前不关闭", not flow.close_warzone_if_due(zones, null))
	flow.set_game_time(600.0)
	_check("到点只关闭一次", flow.close_warzone_if_due(zones, null))
	_check("阶段先锁存 BOSS", flow.phase == BattlefieldFlowScript.Phase.BOSS)
	_check("ZoneData 同步 phase_ended", zones.phase_ended)
	_check("旧选择清空", zones.selected_id == &"")
	_check("普通战区锁定", zones.get_state(&"A") == ZoneData.State.LOCKED)
	_check("BOSS 解锁并公开", zones.boss_unlocked
		and zones.get_state(&"BOSS") == ZoneData.State.AVAILABLE)
	_check("重复调用幂等", not flow.close_warzone_if_due(zones, null))
	var before: float = float(flow.game_time)
	flow.advance_time(5.0, false, zones)
	_check("BOSS 阶段冻结时间", is_equal_approx(flow.game_time, before))
	_check("BOSS 阶段拒绝时间延长",
		is_zero_approx(flow.grant_time_extension(60.0, zones)))


func _test_ace_schedule_latch() -> void:
	print("── C. 王牌固定双槽 ──")
	var flow = BattlefieldFlowScript.new()
	flow.reset_run(600.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xACE
	flow.set_game_time(AceSquadProfiles.FIRST_WAVE_TIME_S - 0.1)
	_check("3:30 前无王牌", flow.claim_next_ace_profile(rng).is_empty())
	flow.set_game_time(AceSquadProfiles.FIRST_WAVE_TIME_S)
	var first := flow.claim_next_ace_profile(rng)
	_check("3:30 开第一槽", not first.is_empty() and flow.ace_slots_opened() == 1)
	_check("第一支原子记账", flow.ace_squads_used_count() == 1)
	flow.set_game_time(600.0 - AceSquadProfiles.FINAL_WAVE_REMAINING_S)
	_check("占场时第二槽只开放不认领",
		flow.claim_next_ace_profile(rng, true).is_empty()
		and flow.ace_slots_opened() == 2 and flow.ace_squads_used_count() == 1)
	flow.set_game_time(360.0) # 模拟第一支击破后倒拨 60 秒
	var second := flow.claim_next_ace_profile(rng)
	_check("倒拨不关闭已开第二槽", not second.is_empty()
		and flow.ace_slots_opened() == 2)
	_check("同局无放回", second != first and flow.ace_squads_used_count() == 2)
	_check("每局最多两支", flow.claim_next_ace_profile(rng).is_empty())


func _test_orion_once_gate() -> void:
	print("── D. 宿敌一次性门 ──")
	var flow = BattlefieldFlowScript.new()
	flow.reset_run(600.0)
	flow.set_game_time(OrionNemesisEvent.TRIGGER_S - 0.1)
	_check("到点前不认领", not flow.claim_orion_if_due(OrionNemesisEvent.TRIGGER_S))
	flow.set_game_time(OrionNemesisEvent.TRIGGER_S)
	_check("到点认领一次", flow.claim_orion_if_due(OrionNemesisEvent.TRIGGER_S))
	_check("同局不可重复", not flow.claim_orion_if_due(OrionNemesisEvent.TRIGGER_S))
	flow.reset_run(600.0)
	flow.set_game_time(OrionNemesisEvent.TRIGGER_S)
	_check("新局恢复宿敌门", flow.claim_orion_if_due(OrionNemesisEvent.TRIGGER_S))


func _test_cross_scene_reset() -> void:
	print("── E. 跨场景 static 重置 ──")
	SkillHooks.sig_fcas_active = true
	SkillHooks.cloud_relaying = true
	SkillHooks.ghost_buster_team_hp_gained = 40.0
	ObjectiveContext.enabled = false
	SurvivorRuntimeResetScript.reset_cross_scene_state(true)
	_check("技能队级开关清零", not SkillHooks.sig_fcas_active)
	_check("天气/累计账本清零", not SkillHooks.cloud_relaying
		and is_zero_approx(SkillHooks.ghost_buster_team_hp_gained))
	_check("新局启用目标上下文", ObjectiveContext.enabled)
	SurvivorRuntimeResetScript.reset_cross_scene_state(false)
	_check("退局禁用目标上下文", not ObjectiveContext.enabled)
