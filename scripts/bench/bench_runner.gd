extends Node
##
## BenchRunner — headless 性能压测入口（AutoLoad）
##
## 用法：
##   godot --headless --path . -- --bench=stress_40 --duration=30   # 性能压测
##   godot --headless --path . -- --bench=weapon                    # 单跑一项无头测试
##   godot --headless --path . -- --bench=all                       # 全量回归门（任一失败退出码=1）
##
## 流程：
##   1. _ready 解析 OS.get_cmdline_args()，找 --bench=<name> / --duration=<sec>
##   2. 命中 → 写 SceneTree.meta（bench_mode/bench_scenario/bench_duration）+ 切场景到
##      survivor_mode.tscn（绕过主菜单/机型/地图选择）
##   3. survivor_mode 在 _ready 里读 meta，进入 bench 分支：
##        - 跳 UI / 教程 / 战区 / Boss debug
##        - 玩家挂 AIController + 升 Level boost
##        - 升级自动选（无视 max_stacks / requires / exclusive）
##        - 批量 force-spawn 敌机
##        - duration 秒后调 BenchRunner.bench_finish()
##   4. bench_finish 把 PerfBuckets.format_full_dump() 写到 bench/results/，quit(0)
##
## 输出文件：bench/results/<scenario>_<utc>.txt（相对项目根）
##
## 注意：headless 模式下 _draw 不调用 → aircraft_draw / naval_draw / trail_draw 三个桶值=0
## 物理 / AI / radar_locks / mount_target_phys 桶值仍正常，足够定位 90% 的掉帧根因。

const DEFAULT_DURATION: float = 30.0
const OUT_DIR_REL: String = "bench/results"

## 无头测试注册表：--bench=<key> 单跑 / --bench=all 全跑（回归门）。
## 约定：实例 run() 跑完后若有 `_fail` 计数属性 → 读它判定退出码；
## 纯指标报告型测试（turn_physics / rejoin 自带阈值打印，靠人读指标）无 _fail → 记 0。
## "bfm_intent" 特例：BfmIntentTest.run_all() 静态入口，返回 bool。
const UNIT_TESTS: Dictionary = {
	"turn_physics": "res://scripts/tests/test_turn_physics.gd",
	"flare": "res://scripts/tests/test_flare_timing.gd",
	"rejoin": "res://scripts/tests/test_formation_rejoin.gd",
	"weapon": "res://scripts/tests/test_weapon_behavior.gd",
	"escort": "res://scripts/tests/test_escort_evasion.gd",
	"target_sel": "res://scripts/tests/test_target_selection.gd",
	"cmd_evade": "res://scripts/tests/test_commanded_evade.gd",
	"cmd_cloak": "res://scripts/tests/test_commanded_cloak.gd",
	"hard_brake": "res://scripts/tests/test_hard_brake.gd",
	"intent": "res://scripts/tests/test_intent_arbiter.gd",
	"target_arb": "res://scripts/tests/test_target_arbiter.gd",
	"gun_aim": "res://scripts/tests/test_gun_aim.gd",
	"gun_burst": "res://scripts/tests/test_gun_burst.gd",
	"weapon_doctrine": "res://scripts/tests/test_weapon_doctrine.gd",
	"missile_env": "res://scripts/tests/test_missile_envelope.gd",
	"joust": "res://scripts/tests/test_joust.gd",
	"lancer_squad": "res://scripts/tests/test_lancer_squad.gd",
	"state_machine": "res://scripts/tests/test_state_machine.gd",
	"bfm_intent": "res://scripts/tests/test_bfm_intent.gd",
	"surface_pass": "res://scripts/tests/test_surface_pass.gd",
	"fire_alloc": "res://scripts/tests/test_fire_allocation.gd",
	"wheel_orders": "res://scripts/tests/test_wheel_orders.gd",
	"roe": "res://scripts/tests/test_roe_director.gd",
	"fire_discipline": "res://scripts/tests/test_fire_discipline.gd",
	"attr_gates": "res://scripts/tests/test_attribute_gates.gd",
	"player_params": "res://scripts/tests/test_player_params.gd",
	"chatter": "res://scripts/tests/test_radio_chatter.gd",
	"tight_volley": "res://scripts/tests/test_tight_volley.gd",
	"ace_tier": "res://scripts/tests/test_ace_tier.gd",
	"boss_hunter": "res://scripts/tests/test_boss_hunter.gd",
	"speed_governor": "res://scripts/tests/test_speed_governor.gd",
	"poltergeist_tactics": "res://scripts/tests/test_poltergeist_tactics.gd",
	"slow_air_pass": "res://scripts/tests/test_slow_air_pass.gd",
	"presentation": "res://scripts/tests/test_presentation.gd",
	"evo_detail": "res://scripts/tests/test_evolution_detail.gd",
	"skills720": "res://scripts/tests/test_skills_720.gd",
	"sig_skills": "res://scripts/tests/test_sig_skills.gd",
	"bullet_grid": "res://scripts/tests/test_bullet_grid.gd",
	"zone_rewards": "res://scripts/tests/test_zone_rewards.gd",
	"career_archive": "res://scripts/tests/test_career_archive.gd",
	"meta_shop": "res://scripts/tests/test_meta_shop.gd",
	"spawn_pool": "res://scripts/tests/test_spawn_pool.gd",
}

var bench_active: bool = false
var bench_scenario: String = ""
var bench_duration: float = DEFAULT_DURATION
var _out_path: String = ""

func _ready() -> void:
	# Godot 4 把 `--` 之后的用户参数放 get_cmdline_user_args() 而非 get_cmdline_args()
	# 两个都读一遍，兼容 `godot ... -- --bench=X` 和 `godot ... --bench=X` 两种调用
	var args: PackedStringArray = PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	printerr("[Bench] BenchRunner._ready — args(engine=%d, user=%d)" % [
		OS.get_cmdline_args().size(), OS.get_cmdline_user_args().size()])
	for a in args:
		if a.begins_with("--bench="):
			bench_scenario = a.substr(8)
		elif a.begins_with("--duration="):
			bench_duration = maxf(1.0, float(a.substr(11)))
	if bench_scenario == "":
		printerr("[Bench] no --bench= arg, BenchRunner idle")
		return

	# ── 无头单元/行为测试（不切 survivor 场景，直接跑 + quit）──
	# --bench=<key> 单跑一项；--bench=all 全跑（Phase 0 回归门，重构计划 §5）。
	# 退出码：任一失败 → quit(1)，全绿 → quit(0)，可直接做 CI / 提交前检查。
	# 在正常项目上下文运行 → autoload(EventLogger 等)可用 → aircraft_physics 可编译。
	if bench_scenario == "all" or UNIT_TESTS.has(bench_scenario):
		var keys: Array = UNIT_TESTS.keys() if bench_scenario == "all" else [bench_scenario]
		var total_fail: int = 0
		for k in keys:
			total_fail += _run_unit_test(String(k))
		if bench_scenario == "all":
			print("[Bench] ══════ 回归门 %s：共 %d 项测试，失败 %d ══════" % [
				"PASS ✓" if total_fail == 0 else "FAIL ✗", keys.size(), total_fail])
		get_tree().quit(1 if total_fail > 0 else 0)
		return

	bench_active = true

	# 输出路径：bench/results/<scenario>_<UTC YYYYMMDD_HHMMSS>.txt
	var ts: String = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	_out_path = "res://%s/%s_%s.txt" % [OUT_DIR_REL, bench_scenario, ts]
	# 确保输出目录存在（编辑器 / dev 模式下 res:// = 项目根）
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://%s" % OUT_DIR_REL))

	# 把开关写到 SceneTree.meta，survivor_mode._ready 读这些 meta 进入 bench 分支
	get_tree().set_meta("bench_mode", true)
	get_tree().set_meta("bench_scenario", bench_scenario)
	get_tree().set_meta("bench_duration", bench_duration)
	# demo 模式（--bench=demo）：渲染运行 + 不退出 + 持续补敌，供肉眼观察小队战斗/物理/表现。
	# 用法（注意：不要加 --headless）：godot --path . -- --bench=demo
	if bench_scenario == "demo" or bench_scenario == "weapon_demo":
		get_tree().set_meta("bench_demo", true)

	printerr("[Bench] scenario=%s duration=%.1fs out=%s" % [bench_scenario, bench_duration, _out_path])
	# 切场景必须 deferred —— autoload _ready 早于主场景实例化，直接 change_scene 会撞到
	# "current scene not yet ready" 的内部断言
	call_deferred("_swap_to_survivor")


## 跑一项注册表测试，返回失败数（加载失败 = 1）
func _run_unit_test(key: String) -> int:
	print("[Bench] ────── %s ──────" % key)
	if key == "bfm_intent":
		return 0 if BfmIntentTest.run_all() else 1
	var script: GDScript = load(String(UNIT_TESTS[key]))
	if script == null:
		printerr("[Bench] %s: 测试脚本加载失败（%s）" % [key, String(UNIT_TESTS[key])])
		return 1
	var t = script.new()
	if t == null or not t.has_method("run"):
		printerr("[Bench] %s: 无 run() 入口" % key)
		return 1
	t.run()
	var f = t.get("_fail")
	return int(f) if f != null else 0


func _swap_to_survivor() -> void:
	printerr("[Bench] swapping to survivor_mode.tscn")
	var err: int = get_tree().change_scene_to_file("res://scenes/survivor_mode.tscn")
	if err != OK:
		push_error("[Bench] failed to load survivor_mode.tscn (err=%d)" % err)
		get_tree().quit(1)


## 由 survivor_mode 在 bench duration 到点时回调
func bench_finish(extra_summary: String = "") -> void:
	if not bench_active:
		return
	var dump: String = PerfBuckets.format_full_dump()
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f:
		f.store_string("=== AGL BENCH RESULT ===\n")
		f.store_string("scenario : %s\n" % bench_scenario)
		f.store_string("duration : %.2fs\n" % bench_duration)
		f.store_string("godot    : %s\n" % Engine.get_version_info().get("string", "?"))
		f.store_string("headless : %s\n" % str(DisplayServer.get_name() == "headless"))
		f.store_string("\n")
		if extra_summary != "":
			f.store_string(extra_summary)
			f.store_string("\n")
		f.store_string(dump)
		f.close()
		print("[Bench] wrote %s" % ProjectSettings.globalize_path(_out_path))
	else:
		push_error("[Bench] failed to write %s" % _out_path)
	# 同时 dump EventLogger 事件日志（确定性场景的 churn/twitch 离线分析用）
	if Engine.has_singleton("EventLogger") or EventLogger:
		EventLogger.dump_to_file()
	# 给 print 一帧时间被 stdout 吐出
	await get_tree().process_frame
	get_tree().quit(0)
