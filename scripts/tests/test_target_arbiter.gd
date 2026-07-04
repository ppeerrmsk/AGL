extends RefCounted

## 目标所有权仲裁单元测试（Phase 1 目标仲裁器，2026-07-04）
## 验证 AIController.acquire_target / release_target 的核心契约：
##   1. 四级优先级：低级源不得抢占/清除高级源持有的存活目标（军备竞赛终结）
##   2. 同级/更高级可换目标；同目标重申不降级来源
##   3. 目标死亡自动降级：不再受保护，任何源可接管
##   4. release 对称：高级源可清低级源的目标
## 运行：godot --headless --path . -- --bench=target_arb（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 目标所有权仲裁（acquire/release_target） ════════")
	var ai := _make_ai()
	var t_scored := _make_target()
	var t_boss := _make_target()
	var t_cmd := _make_target()

	# ── 1. 基本 acquire + 来源记账 ──
	_check("SCORED 获取空闲目标", ai.acquire_target(t_scored, AIController.TargetSource.TS_SCORED), "")
	_check("combat_target 同步", ai.aircraft.combat_target == t_scored, "入口双写")

	# ── 2. 高级源抢占低级源 ──
	_check("BOSS 抢 SCORED 的目标", ai.acquire_target(t_boss, AIController.TargetSource.TS_BOSS), "2 > 1")
	_check("目标已换", ai._current_target == t_boss, "")

	# ── 3. 低级源不得抢高级源（军备竞赛终结点）──
	_check("SCORED 抢 BOSS 被拒", not ai.acquire_target(t_scored, AIController.TargetSource.TS_SCORED),
			"spawner/swarm 指派不再被评分交战抢写")
	_check("目标未变", ai._current_target == t_boss, "")
	_check("SCORED 清 BOSS 被拒", not ai.release_target(AIController.TargetSource.TS_SCORED),
			"disengage 不能踢掉 BOSS 指派")
	_check("目标仍在", ai._current_target == t_boss, "")

	# ── 4. COMMANDED 压一切 ──
	_check("COMMANDED 抢 BOSS", ai.acquire_target(t_cmd, AIController.TargetSource.TS_COMMANDED), "4 > 2")
	_check("BOSS 抢 COMMANDED 被拒", not ai.acquire_target(t_boss, AIController.TargetSource.TS_BOSS),
			"玩家命令铁律从约定变成代码保证")

	# ── 5. 同目标重申不降级 ──
	_check("SCORED 重申同目标允许", ai.acquire_target(t_cmd, AIController.TargetSource.TS_SCORED),
			"同目标 re-acquire 放行")
	_check("来源保持 COMMANDED", ai._target_source == AIController.TargetSource.TS_COMMANDED,
			"acquire 只升不降")

	# ── 6. 目标死亡自动降级保护 ──
	t_cmd.is_destroyed = true
	_check("死目标不再受保护", ai.acquire_target(t_scored, AIController.TargetSource.TS_SCORED),
			"_target_holder_pri 自动降级 → 评分交战可接管")
	_check("来源更新为 SCORED", ai._target_source == AIController.TargetSource.TS_SCORED, "")

	# ── 7. release 对称 ──
	_check("COMMANDED 清 SCORED 允许", ai.release_target(AIController.TargetSource.TS_COMMANDED),
			"HUD 强制脱战可清任何 AI 目标")
	_check("清空后 combat_target 同步", ai.aircraft.combat_target == null, "")
	_check("空目标 acquire 无效", not ai.acquire_target(null, AIController.TargetSource.TS_BOSS), "判空")

	t_scored.free(); t_boss.free(); t_cmd.free()
	ai.aircraft.free()  # 连同子节点 AIController
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make_ai() -> AIController:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = 1
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _make_target() -> Aircraft:
	var t: Aircraft = load("res://scripts/aircraft.gd").new()
	t.team = 0
	t.global_position = Vector2(1000, 0)
	return t


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
