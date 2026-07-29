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
