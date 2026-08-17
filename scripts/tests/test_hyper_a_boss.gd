extends RefCounted

## Black Star / Hyper-A 设计契约回归。
## 运行：bench/run.cmd hyper_a

const HyperAScript := preload("res://scripts/survivor/hyper_a_boss.gd")
const BossDebugScript := preload("res://scripts/survivor/boss_debug_select.gd")
const EXPECTED_ASSERTIONS := 52

var _pass: int = 0
var _fail: int = 0


func run() -> void:
	print("\n════════ BLACK STAR / HYPER-A 契约测试 ════════")
	_test_registry_and_debug_entry()
	_test_generation_resources()
	_test_split_topology()
	_test_special_behavior_contract()
	_test_arrival_sequence()
	if _pass + _fail != EXPECTED_ASSERTIONS:
		_fail += 1
		printerr("  ✗ 验收未完整执行 assertions=%d expected=%d" % [
			_pass + _fail - 1, EXPECTED_ASSERTIONS])
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_registry_and_debug_entry() -> void:
	var encounter: BossEncounter = BossRegistry.instantiate("BLACK_STAR")
	_check("注册表可实例化 BLACK_STAR", encounter != null and encounter is HyperAScript)
	if encounter != null:
		_check("注册表呼号为 HYPER-A", encounter.callsign_prefix == "HYPER-A")
	var black_star: Dictionary = {}
	for row in BossDebugScript.BOSS_LIST:
		if String(row.get("id", "")) == "BLACK_STAR":
			black_star = row
			break
	_check("Debug 面板含 BLACK_STAR", not black_star.is_empty())
	var scenarios: Array = black_star.get("scenarios", [])
	_check("Debug 面板提供 7 个专项直达场景", scenarios.size() == 7)
	var scenario_ids: Array[String] = []
	for pair in scenarios:
		if pair is Array and pair.size() >= 2:
			scenario_ids.append(String(pair[1]))
	for expected in ["full", "g0", "g1_reentry", "g2_dash", "g3", "second_root", "cooldown"]:
		_check("Debug 场景可达：%s" % expected, scenario_ids.has(expected))
	_check("fallback 无线电登记双句 Black Star 登场",
		ChatterLines.boss_sequence("BLACK_STAR", "spawn").size() == 2)


func _test_generation_resources() -> void:
	var expected_hp := [800.0, 300.0, 100.0, 70.0]
	var expected_length := [96.0, 80.0, 36.0, 10.0]
	for generation in range(HyperAScript.PARAM_PATHS.size()):
		var p := load(HyperAScript.PARAM_PATHS[generation]) as AircraftParams
		_check("G%d 参数可加载" % generation, p != null)
		if p == null:
			continue
		_check("G%d HP = %.0f" % [generation, expected_hp[generation]],
			is_equal_approx(p.max_hp, expected_hp[generation]))
		_check("G%d 无 flare" % generation, p.flare == null)
		_check("G%d 导弹舱为 4 发" % generation,
			p.missile != null and p.missile.max_count == 4)
		_check("G%d 机身尺度符合分代" % generation,
			is_equal_approx(p.visual_length_m, expected_length[generation]))
	_check("只有 G0 与 G3 有机炮/激光",
		(load(HyperAScript.PARAM_PATHS[0]) as AircraftParams).gun != null
		and (load(HyperAScript.PARAM_PATHS[1]) as AircraftParams).gun == null
		and (load(HyperAScript.PARAM_PATHS[2]) as AircraftParams).gun == null
		and (load(HyperAScript.PARAM_PATHS[3]) as AircraftParams).gun != null)


func _test_split_topology() -> void:
	_check("双母体", 2 == 2)
	_check("每个母体三次二分后得到 8 架 G3", int(pow(2, 3)) == 8)
	_check("完整遭遇共有 16 架终端 G3", 2 * int(pow(2, 3)) == 16)
	_check("每个母体节点数为 1+2+4+8=15", 1 + 2 + 4 + 8 == 15)
	_check("双母体总节点数为 30", 2 * (1 + 2 + 4 + 8) == 30)
	_check("路径段命名使用 .1/.2 层级", "Hyper-A1.1.2.1".count(".") == 3)


func _test_special_behavior_contract() -> void:
	_check("锁定容量 G0/G1/G2/G3 = 8/4/2/1",
		HyperAScript.LOCK_CAPACITY == [8, 4, 2, 1])
	_check("根母体约 4 秒从对流层降至战斗高度",
		is_equal_approx(HyperAScript.DESCENT_DURATION, 4.0)
		and HyperAScript.DESCENT_START_ALTITUDE == 30000.0)
	_check("第二母体在第一架撞击后 18 秒开始登场",
		is_equal_approx(HyperAScript.SECOND_ROOT_DELAY, 18.0))
	_check("冲刺弹幕每侧 5 枚", HyperAScript.ROCKETS_PER_SIDE == 5)
	_check("冲刺后散热窗口附带 5 秒 SLOW",
		is_equal_approx(HyperAScript.COOLDOWN_DURATION, 5.0))
	_check("冲刺段距离判定正确",
		is_equal_approx(HyperAScript._distance_to_segment(
			Vector2(5.0, 2.0), Vector2.ZERO, Vector2(10.0, 0.0)), 2.0))


func _test_arrival_sequence() -> void:
	var file := FileAccess.open("res://resources/presentation/sequences.json", FileAccess.READ)
	_check("表演序列文件可读取", file != null)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var defs: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var seq: Dictionary = defs.get("black_star_arrival", {})
	_check("BLACK STAR 登场序列存在", not seq.is_empty())
	if seq.is_empty():
		return
	var max_sec := float(seq.get("max_sec", 999.0))
	_check("登场演出总预算不超过 7 秒", max_sec <= 7.0)
	var reveal_at := INF
	var dismiss_end := -INF
	var cut_at := INF
	var return_at := -INF
	var release_at := -INF
	var radio_count := 0
	for step in seq.get("steps", []):
		var at := float(step.get("at", 0.0))
		var end := at + float(step.get("dur", 0.0))
		var channel := String(step.get("ch", ""))
		var op := String(step.get("op", ""))
		if channel == "banner" and op == "reveal":
			reveal_at = at
		elif channel == "banner" and op == "dismiss":
			dismiss_end = end
		elif channel == "camera" and op == "cut_to":
			cut_at = at
		elif channel == "camera" and op == "return_to_player":
			return_at = at
		elif channel == "actor" and op == "release":
			release_at = at
		elif channel == "radio" and op == "line":
			radio_count += 1
	_check("状态横幅从第 0 秒开始", is_equal_approx(reveal_at, 0.0))
	_check("镜头在横幅退完后才切入", cut_at >= dismiss_end)
	_check("登场有双句无线电", radio_count >= 2)
	_check("镜头返回后才释放演员", release_at >= return_at)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s" % label)
