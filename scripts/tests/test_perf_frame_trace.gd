extends RefCounted

## Bench-only 逐帧尖峰追踪的最小契约测试。

const PerfBucketsScript = preload("res://scripts/util/perf_buckets.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 性能尖峰追踪测试 ════════")
	_test_disabled_dump_is_empty()
	_test_slow_frame_captures_buckets_events_and_load()
	_test_runtime_panel_history_and_hotspots()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _test_disabled_dump_is_empty() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.configure_frame_trace(false)
	_check("关闭时不输出逐帧追踪", tracker.format_frame_trace_dump().is_empty())
	tracker.free()


func _test_slow_frame_captures_buckets_events_and_load() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.set_value("all_units.total", 72)
	tracker.set_value("missile_count", 14)
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.020)
	tracker.mark_physics_tick()
	tracker.tick("trail_draw", 1800)
	tracker.count("radar_pairs", 240)
	tracker.mark_frame_event("radar_tick")
	tracker.begin_render_frame(0.010)
	var dump: String = tracker.format_frame_trace_dump()
	_check("慢帧被捕获", dump.contains("below60=1 captured=1"), dump)
	_check("已测与未归因帧时间分离",
		dump.contains("known=1.800ms") and dump.contains("unaccounted=18.200ms"))
	_check("桶与计数随慢帧保存",
		dump.contains("trail_draw=1800us") and dump.contains("radar_pairs=240"))
	_check("事件与负载随慢帧保存",
		dump.contains("radar_tick=1") and dump.contains("units=72")
		and dump.contains("missiles=14"))
	tracker.free()


func _test_runtime_panel_history_and_hotspots() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.configure_runtime_panel(true)
	for index in range(108):
		tracker.begin_render_frame(0.010)
	for index in range(12):
		tracker.begin_render_frame(0.020)
	var stats: Dictionary = tracker.runtime_frame_stats()
	_check("F3 keeps a fixed recent-frame history",
		int(stats.get("samples", 0)) == 120
		and int(stats.get("below_60", 0)) == 12
		and absf(float(stats.get("worst_ms", 0.0)) - 20.0) < 0.01,
		str(stats))
	tracker.tick("aircraft_phys", 4200)
	tracker.tick("bullet_phys", 2100)
	tracker.count("skill_events", 3)
	tracker.set_value("all_units.total", 57)
	tracker.set_value("bullet_count", 80)
	tracker.set_value("boss.phase", 1)
	tracker._process(1.0)
	var hotspots := tracker.ranked_runtime_hotspots(2)
	var text := "\n".join(tracker.format_detailed_hud_lines())
	_check("F3 ranks the completed one-second CPU buckets",
		hotspots.size() == 2
		and String(hotspots[0].get("name", "")) == "aircraft_phys"
		and String(hotspots[1].get("name", "")) == "bullet_phys")
	_check("F3 detailed text includes frame, engine, simulation and load domains",
		text.contains("最近 120/120 渲染帧")
		and text.contains("引擎监视")
		and text.contains("运算根桶")
		and text.contains("绘制CPU")
		and text.contains("HUD CPU")
		and text.contains("单位  total 57")
		and text.contains("BOSS PHASE")
		and text.contains("skill 3.0")
		and text.contains("bullets 80"), text)
	tracker.configure_runtime_panel(false)
	_check("closing F3 disables detail capture and clears frame history",
		not tracker.detail_capture_enabled()
		and int(tracker.runtime_frame_stats().get("samples", -1)) == 0)
	tracker.free()
