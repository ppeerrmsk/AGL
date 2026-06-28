extends Node
##
## BenchRunner — headless 性能压测入口（AutoLoad）
##
## 用法：
##   godot --headless --path . -- --bench=stress_40 --duration=30
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

	# 特殊场景：纯物理单元仿真（不切 survivor 场景，直接跑 + quit）。
	# 在正常项目上下文运行 → autoload(EventLogger 等)可用 → aircraft_physics 可编译。
	if bench_scenario == "turn_physics":
		var script: GDScript = load("res://scripts/tests/test_turn_physics.gd")
		if script:
			var tpt = script.new()
			if tpt and tpt.has_method("run"):
				tpt.run()
		else:
			printerr("[Bench] turn_physics: 测试脚本加载失败")
		get_tree().quit(0)  # 无论成败都退出，避免 headless 挂起超时
		return

	# 智能放焰验证（2026-06-14 玩家方 TTI 放焰）
	if bench_scenario == "flare":
		var fscript: GDScript = load("res://scripts/tests/test_flare_timing.gd")
		if fscript:
			var ft = fscript.new()
			if ft and ft.has_method("run"):
				ft.run()
		else:
			printerr("[Bench] flare: 测试脚本加载失败")
		get_tree().quit(0)
		return

	# 编队归队速度验证（2026-06-13 _update_speed 提速修复）
	if bench_scenario == "rejoin":
		var rscript: GDScript = load("res://scripts/tests/test_formation_rejoin.gd")
		if rscript:
			var rt = rscript.new()
			if rt and rt.has_method("run"):
				rt.run()
		else:
			printerr("[Bench] rejoin: 测试脚本加载失败")
		get_tree().quit(0)
		return

	# 武器行为验证（2026-06-13 武器有效性修复回归测试）
	if bench_scenario == "weapon":
		var wscript: GDScript = load("res://scripts/tests/test_weapon_behavior.gd")
		if wscript:
			var wt = wscript.new()
			if wt and wt.has_method("run"):
				wt.run()
		else:
			printerr("[Bench] weapon: 测试脚本加载失败")
		get_tree().quit(0)
		return

	# 僚机护卫规避验证（2026-06-16 spec wingman-escort-evasion）
	if bench_scenario == "escort":
		var escript: GDScript = load("res://scripts/tests/test_escort_evasion.gd")
		if escript:
			var et = escript.new()
			if et and et.has_method("run"):
				et.run()
		else:
			printerr("[Bench] escort: 测试脚本加载失败")
		get_tree().quit(0)
		return

	if bench_scenario == "target_sel":
		var tscript: GDScript = load("res://scripts/tests/test_target_selection.gd")
		if tscript:
			var tt = tscript.new()
			if tt and tt.has_method("run"):
				tt.run()
		else:
			printerr("[Bench] target_sel: 测试脚本加载失败")
		get_tree().quit(0)
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
	if bench_scenario == "demo":
		get_tree().set_meta("bench_demo", true)

	printerr("[Bench] scenario=%s duration=%.1fs out=%s" % [bench_scenario, bench_duration, _out_path])
	# 切场景必须 deferred —— autoload _ready 早于主场景实例化，直接 change_scene 会撞到
	# "current scene not yet ready" 的内部断言
	call_deferred("_swap_to_survivor")


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
