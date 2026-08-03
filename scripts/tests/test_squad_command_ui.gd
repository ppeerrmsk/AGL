extends RefCounted

## 无头验收：小队指挥 UI 的启动条件 = "有僚机入队"，与机型无关
##
## 背景（2026-07-29 用户报）：小队指挥面板只在 F-14 时出现。根因不是 UI 层，
## 而是"玩家队登记进 _spawner.get_squads()"这一步原先只挂在 _spawn_starting_wingmen 末尾——
## 那条路只有 wingman_count>0 的机型（41 机里仅 F-14）会走。其余 40 机走 _ensure_player_squad
## 懒建队路径（战区 +1 僚机奖励 / 停靠送僚机 / 双子星复制），队伍建了却从不登记：
##   - SurvivorHUD._get_player_squad() 反查 _spawner.get_squads() → 永远 null → 指挥面板永不显示
##   - SurvivorSpawner._cleanup_squads() 只清表内队伍 → 阵亡僚机永不从 members 剔除
##
## A 登记点在公共装配链上：任何机型首次 _ensure_player_squad 即入表（幂等，不重复 append）
## B 起手带僚机的机型（F-14 路径）仍只登记一次
## C HUD 反查链路通：_get_player_squad / _get_wingmen 能看到懒建的队
##
## 运行：godot --headless --path . -- --bench=squad_cmd_ui（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 小队指挥 UI 启动条件（与机型无关）════════")
	_test_lazy_squad_registered()
	_test_registration_idempotent()
	_test_hud_can_find_squad()
	_test_fixed_squad_slots()
	_test_wingman_tutorial_slot_hint()
	_test_leader_down_repairs_squad_bindings()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


# ══════════════════════════════════════════════
#  夹具：不挂进场景树 → 不触发 survivor_mode._ready（整局初始化与本测试无关）
# ══════════════════════════════════════════════

func _mk_ac() -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = CombatUnit.TEAM_PLAYER
	ac.altitude = 6000.0
	ac.hp = 100.0
	ac.params = AircraftParams.new()
	return ac


## 返回 [mode, spawner, player]；mode 为裸 SurvivorMode 实例（wingman_count=0 机型的等价态：无 _squad）
func _mk_mode() -> Array:
	var mode: Node2D = load("res://scripts/survivor/survivor_mode.gd").new()
	var spawner := SurvivorSpawner.new()
	var player := _mk_ac()
	mode.player_aircraft = player
	mode._spawner = spawner
	mode.add_child(player)
	return [mode, spawner, player]


# ── A. 懒建队即登记 ──

func _test_lazy_squad_registered() -> void:
	print("── A. 懒建队路径（40/41 机型）建队即登记 ──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var player: Aircraft = env[2]
	_check("建队前 spawner 队表为空", spawner.get_squads().is_empty(),
		"n=%d" % spawner.get_squads().size())
	var sq: Squad = mode._ensure_player_squad()
	_check("_ensure_player_squad 返回队伍", sq != null)
	_check("玩家被装配为长机", sq != null and sq.leader == player)
	_check("队伍已登记进 spawner 队表（指挥 UI 的反查源）",
		spawner.get_squads().has(sq), "n=%d" % spawner.get_squads().size())
	mode.free()
	spawner.free()


# ── B. 幂等 ──

func _test_registration_idempotent() -> void:
	print("── B. 重复装配不重复登记（起手僚机路径也走这条链）──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var sq: Squad = mode._ensure_player_squad()
	var sq2: Squad = mode._ensure_player_squad()
	_check("二次调用返回同一队伍", sq == sq2)
	_check("队表仍只有 1 条", spawner.get_squads().size() == 1,
		"n=%d" % spawner.get_squads().size())
	mode.free()
	spawner.free()


# ── C. HUD 反查链路 ──

func _test_hud_can_find_squad() -> void:
	print("── C. HUD 反查链路（_get_player_squad / _get_wingmen）──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var player: Aircraft = env[2]
	var hud := SurvivorHUD.new()
	hud.game_scene = mode

	_check("无僚机时 HUD 看不到僚机（面板保持隐藏）", hud._get_wingmen().is_empty())

	var sq: Squad = mode._ensure_player_squad()
	var wing := _mk_ac()
	var ai := AIController.new()
	ai.aircraft = wing
	wing.add_child(ai)
	mode.add_child(wing)
	SquadFactory.register_wingman(sq, wing)

	_check("HUD 找得到玩家队", hud._get_player_squad() == sq)
	var wingmen := hud._get_wingmen()
	_check("HUD 看得到 1 架僚机（指挥面板据此显示）", wingmen.size() == 1,
		"n=%d" % wingmen.size())
	_check("僚机列表不含长机自己", not wingmen.has(player))

	hud.free()
	mode.free()
	spawner.free()


# ── D. 固定号机号 ──

func _test_fixed_squad_slots() -> void:
	print("── D. 数字键固定绑定 squad_slot（不随换帅变化）──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var player: Aircraft = env[2]
	var sq: Squad = mode._ensure_player_squad()
	player.squad_slot = 1
	var wing2 := _mk_ac()
	wing2.squad_slot = 2
	var wing5 := _mk_ac()
	wing5.squad_slot = 5
	mode.add_child(wing2)
	mode.add_child(wing5)
	SquadFactory.register_wingman(sq, wing2)
	SquadFactory.register_wingman(sq, wing5)

	_check("键 2 命中固定 2 号机", mode._aircraft_for_squad_slot(2) == wing2)
	_check("空缺的键 3 不压缩命中 5 号机", mode._aircraft_for_squad_slot(3) == null)
	sq.set_leader(wing5)
	_check("换帅后键 1 仍命中原 1 号机", mode._aircraft_for_squad_slot(1) == player)
	_check("换帅后键 5 仍命中新长机", mode._aircraft_for_squad_slot(5) == wing5)

	mode.free()
	spawner.free()


# ── E. 首次僚机教程沿用固定号机映射 ──

func _test_wingman_tutorial_slot_hint() -> void:
	print("── E. 首次僚机教程提示真实固定号机 ──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var player: Aircraft = env[2]
	var sq: Squad = mode._ensure_player_squad()
	player.squad_slot = 1
	var wing3 := _mk_ac()
	wing3.squad_slot = 3
	var wing7 := _mk_ac()
	wing7.squad_slot = 7
	mode.add_child(wing7)
	mode.add_child(wing3)
	SquadFactory.register_wingman(sq, wing7)
	SquadFactory.register_wingman(sq, wing3)

	_check("提示最小可切固定号机 3（不把空缺压成 2）",
		mode._first_switchable_wingman_slot() == 3)
	sq.set_leader(wing3)
	mode.player_aircraft = wing3
	_check("接管 3 号后提示原 1 号机",
		mode._first_switchable_wingman_slot() == 1)
	_check("首局教程条目包含 E 加力",
		SurvivorTutorial.FIRST_RUN_ITEM_KEYS.has("TUTORIAL_AFTERBURNER"))
	_check("首局教程条目包含双击突击",
		SurvivorTutorial.FIRST_RUN_ITEM_KEYS.has("TUTORIAL_ASSAULT"))

	mode.free()
	spawner.free()


# ── F. 长机阵亡竞态：僚机先解绑，接管时必须原子修复 ──

func _test_leader_down_repairs_squad_bindings() -> void:
	print("── F. 长机阵亡后恢复 AI.squad 与全队广播 ──")
	var env := _mk_mode()
	var mode: Node2D = env[0]
	var spawner: SurvivorSpawner = env[1]
	var old_leader: Aircraft = env[2]
	var sq: Squad = mode._ensure_player_squad()
	old_leader.squad_slot = 1

	var wing2 := _mk_ac()
	wing2.squad_slot = 2
	wing2.kill_tally = 2  # 继任者
	var wing3 := _mk_ac()
	wing3.squad_slot = 3
	for wing in [wing2, wing3]:
		var ai := AIController.new()
		ai.aircraft = wing
		wing.add_child(ai)
		# 裸 mode 未挂入 SceneTree，AIController._ready 不会自动回写；夹具显式补同一接线。
		wing._ai_ref = ai
		mode.add_child(wing)
		SquadFactory.register_wingman(sq, wing)

	# 复现真实物理顺序：mode 本帧死亡检查已结束 → 长机被武器击毁 →
	# 僚机 AI 在同帧 SQUAD_FOLLOW 看见死长机，先把自己的 squad 置空。
	old_leader.is_destroyed = true
	for wing in [wing2, wing3]:
		SquadCoordination.process_squad_follow(wing._ai_ref, 1.0 / 60.0)
	_check("竞态前置已复现：两架僚机 AI 均脱队",
		wing2._ai_ref.squad == null and wing3._ai_ref.squad == null)

	_check("自动接管成功", mode._try_takeover_after_leader_down())
	_check("击坠最高的 2 号机继任", mode.player_aircraft == wing2 and sq.leader == wing2)
	_check("幸存成员 AI.squad 全部重新绑定",
		wing2._ai_ref.squad == sq and wing3._ai_ref.squad == sq)
	_check("角色序号原子重排为 leader=0 / wingman=1",
		wing2._ai_ref.squad_index == 0 and wing3._ai_ref.squad_index == 1,
		"idx=%d/%d" % [wing2._ai_ref.squad_index, wing3._ai_ref.squad_index])
	_check("新长机完整退出旧编队托管",
		not wing2.formation_mode and wing2._formation_leader == null
		and not wing2.keep_target_on_arrival and not wing2.ai_override_pursuit)
	var live_leader_order := Vector2(-1700.0, 800.0)
	wing2.target_position = live_leader_order
	sq.cleanup()
	_check("后续周期 cleanup 不清空存活长机航令", wing2.target_position == live_leader_order)

	var cmd := SquadCommandController.new()
	mode.add_child(cmd)
	cmd.setup(mode, RtsCommandParams.new())
	var regroup_point := Vector2(2400.0, -900.0)
	cmd.command_regroup(regroup_point)
	_check("接管后全队广播仍覆盖全部幸存飞机",
		wing2.target_position == regroup_point and wing3.target_position == regroup_point
		and wing2.command_sprint and wing3.command_sprint)

	mode.free()
	spawner.free()
