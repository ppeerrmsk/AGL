extends RefCounted

## Bench-only 逐帧尖峰追踪的最小契约测试。

const PerfBucketsScript = preload("res://scripts/util/perf_buckets.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 性能尖峰追踪测试 ════════")
	_test_disabled_dump_is_empty()
	_test_slow_frame_captures_buckets_events_and_load()
	_test_slow_frame_keeps_pre_and_post_context()
	_test_trace_reports_full_run_root_averages()
	_test_extended_cpu_trace()
	_test_map_root_and_context()
	_test_render_partition()
	_test_render_timeline()
	_test_backend_peaks()
	_test_draw_capture()
	_test_runtime_panel_history_and_hotspots()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _test_draw_capture() -> void:
	var observer: RefCounted=load("res://scripts/tests/tokyo_render_trace.gd").new()
	var path := "res://bench/results/draw-capture-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	observer._capture_path=path
	observer._capture_status="waiting"
	observer._clock_anchor={"pid":OS.get_process_id()}
	observer._capture_draw_spike(PackedInt64Array([2000,10000,5000,17000]),17001)
	_check("未武装不得写尖峰文件",not FileAccess.file_exists(path) and observer._capture_status=="waiting")
	var armed := FileAccess.open(path+".armed",FileAccess.WRITE)
	_check("诊断夹具可写",armed!=null)
	if armed==null: return
	armed.store_string("test")
	armed.close()
	observer._capture_draw_spike(PackedInt64Array([2000,7000,9000,18000]),18001)
	observer._capture_draw_spike(PackedInt64Array([2000,8000,6000,16000]),16001)
	_check("仅捕获绘制尖峰且墙钟超预算的帧",not FileAccess.file_exists(path))
	observer._capture_draw_spike(PackedInt64Array([2000,10000,5000,17000]),17001)
	var original := FileAccess.get_file_as_string(path)
	var value: Dictionary=JSON.parse_string(original)
	_check("尖峰记录保存时钟及污染边界",observer._capture_status=="captured" and value.clock_anchor.pid==OS.get_process_id()
		and value.next_ticks_usec==17001 and value.diagnostic_only and value.subsequent_frames_contaminated)
	observer._capture_draw_spike(PackedInt64Array([2000,12000,5000,19000]),19001)
	_check("尖峰只保存一次",FileAccess.get_file_as_string(path)==original)
	observer._capture_status="waiting"
	observer._capture_draw_spike(PackedInt64Array([2000,12000,5000,19000]),19001)
	_check("已有证据拒绝覆盖",observer._capture_status=="refused_existing" and FileAccess.get_file_as_string(path)==original)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path+".armed")


func _test_backend_peaks() -> void:
	var trace: Script = load("res://scripts/tests/tokyo_render_trace.gd")
	var peaks: Dictionary = {}
	var values := {"map_cpu_ms": 480.0, "root_gpu_ms": 0.8, "unknown": 999.0}
	trace.retain_backend_peaks(peaks, values, 10, 20)
	values.map_cpu_ms = 1.0
	trace.retain_backend_peaks(peaks, values, 11, 21)
	_check("后端峰保留同次快照且与输入解耦", peaks.size() == 2 and peaks.map_cpu_ms.value_ms == 480.0
		and peaks.map_cpu_ms.values.map_cpu_ms == 480.0 and peaks.map_cpu_ms.readback_sample == 10)
	trace.retain_backend_peaks(peaks, {"map_cpu_ms": NAN, "aircraft_gpu_ms": -1.0, "root_gpu_ms": "2"}, 12, 22)
	_check("未知和无效后端值不生成零耗时", peaks.size() == 2 and peaks.root_gpu_ms.value_ms == 0.8)
	trace.retain_backend_peaks(peaks, {"aircraft_gpu_ms": 1.0, "root_gpu_ms": 1.2}, 13, 23)
	_check("飞机视口与主视口峰各自保存序号", peaks.size() == 3 and peaks.aircraft_gpu_ms.readback_sample == 13
		and peaks.root_gpu_ms.value_ms == 1.2 and peaks.root_gpu_ms.observed_frame == 23)
	var root := SubViewport.new()
	var map := SubViewport.new()
	var freed_view: Variant = SubViewport.new()
	freed_view.free()
	var observer: RefCounted = trace.new()
	observer.setup(root, map, false, freed_view)
	_check("系统记录锚点保留PID与单调时钟夹逼区间", observer._clock_anchor.pid == OS.get_process_id()
		and observer._clock_anchor.utc_usec > 0 and observer._clock_anchor.ticks_before_usec > 0
		and observer._clock_anchor.ticks_after_usec >= observer._clock_anchor.ticks_before_usec
		and not observer._clock_anchor.same_frame_gpu_proof)
	_check("可选视口拒绝已释放实例", observer._views.size() == 2)
	observer.close()
	_check("关闭清空弱引用并断开绘制监听", observer._views.is_empty() and observer._closed
		and not RenderingServer.frame_pre_draw.is_connected(observer._before_draw)
		and not RenderingServer.frame_post_draw.is_connected(observer._after_draw))
	root.free()
	map.free()


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
	tracker.begin_render_frame(0.010)
	tracker.mark_physics_tick()
	tracker.tick("trail_draw", 1800)
	tracker.count("radar_pairs", 240)
	tracker.mark_frame_event("radar_tick")
	tracker.begin_render_frame(0.020)
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


func _test_slow_frame_keeps_pre_and_post_context() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.configure_frame_trace(true)
	# 两个快帧上下文。
	tracker.begin_render_frame(0.010)
	tracker.begin_render_frame(0.010)
	tracker.begin_render_frame(0.011)
	tracker.mark_physics_tick()
	tracker.tick("aircraft_draw", 12000)
	# 结算慢帧，再补两个后续快帧；窗口此时仍是合法的 partial capture。
	tracker.begin_render_frame(0.020)
	tracker.begin_render_frame(0.010)
	tracker.begin_render_frame(0.010)
	var dump := tracker.format_frame_trace_dump()
	_check("追踪报告包含 p95/p99/max 与保守归因率",
		dump.contains("detail_stride=4") and dump.contains("frame_ms p95=")
		and dump.contains("conservative_attribution=1/1 (100.0%)")
		and dump.contains("class=script_hotspot"), dump)
	_check("慢帧保留前后上下文",
		dump.contains("context_windows=1 pre_limit=120 post_target=30")
		and dump.contains("pre_frames=2")
		and dump.contains("triggers=[3]")
		and dump.contains("complete=false")
		and dump.contains("! f=3 dt=20.000"), dump)
	tracker.free()


func _test_trace_reports_full_run_root_averages() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.tick("aircraft_phys", 1000)
	tracker.tick("survivor_lod", 500)
	tracker.begin_render_frame(0.010)
	tracker.tick("aircraft_phys", 3000)
	tracker.begin_render_frame(0.020)
	var dump := tracker.format_frame_trace_dump()
	_check("逐帧根桶输出全程均值而非最后一秒",
		dump.contains("trace_roots frames=2 known_avg=2.250ms frame_avg=15.000ms")
		and dump.contains("aircraft_phys=2.000ms@2/2")
		and dump.contains("survivor_lod=0.250ms@1/2"), dump)
	tracker.free()


func _test_extended_cpu_trace() -> void:
	# 测试自行保存环境；不把专项开关泄漏到后面的采样契约测试。
	var environment: Dictionary = {}
	for key in ["AGL_BENCH_EXTENDED_CPU_TRACE", "AGL_BENCH_FRAME_TRACE_MODE"]:
		environment[key] = {"present": OS.has_environment(key), "value": OS.get_environment(key)}
	OS.unset_environment("AGL_BENCH_EXTENDED_CPU_TRACE")
	OS.set_environment("AGL_BENCH_FRAME_TRACE_MODE", "sampled")
	var tracker := PerfBucketsScript.new()
	_check("扩展诊断创建时默认关闭", not tracker.extended_cpu_trace_enabled)
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.finish_extended_cpu("missile_phys", Time.get_ticks_usec() - 2000, 0)
	_check("未显式启用不产生额外计时或注册新根", tracker._trace_frame_us.is_empty()
		and not tracker._trace_root_total_us.has("extended.missile_phys.exclusive"))
	OS.set_environment("AGL_BENCH_EXTENDED_CPU_TRACE", "1")
	_check("环境变化只在配置入口生效", not tracker.extended_cpu_trace_enabled)
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	var all_registered := true
	for root_name in tracker.EXTENDED_CPU_TRACE_ROOT_BUCKETS:
		all_registered = all_registered and tracker._trace_root_total_us.has(root_name)
	_check("显式启用注册全部独立扩展根", tracker.extended_cpu_trace_enabled and all_registered)

	# 构造同一作用域中的三个共享叶；音效内部子项不能再次扣除。
	tracker.tick("event_log", 120)
	tracker.tick("audio_sfx_play", 80)
	tracker.tick("radio_play", 20)
	tracker.tick("audio_sfx.load", 30)
	_check("共享计数仅记录已有叶根", tracker.extended_cpu_shared_usec == 220)
	var started_usec := Time.get_ticks_usec() - 2000
	tracker.finish_extended_cpu("missile_phys", started_usec, 0)
	var ended_usec := Time.get_ticks_usec()
	var total_usec := int(tracker._trace_frame_us.get("extended.missile_phys.total", -1))
	var exclusive_usec := int(tracker._trace_frame_us.get("extended.missile_phys.exclusive", -1))
	_check("真实时钟只要求落在调用夹逼区间", total_usec >= 2000
		and total_usec <= ended_usec - started_usec)
	_check("共享叶只扣一次且诊断总量不重复计根", exclusive_usec == total_usec - 220
		and int(tracker._trace_frame_us.get("extended.missile_phys.shared", -1)) == 220
		and tracker._trace_known_root_us() == total_usec)

	# 父根内部 event_log 已由父根覆盖；新增余量只能再扣父根外的音效。
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.tick("event_log", 80)
	tracker.tick("survivor_cache", 600)
	tracker.tick("audio_sfx_play", 120)
	var existing_roots_usec: int = tracker._trace_known_root_us()
	tracker.finish_extended_cpu("survivor_phys", Time.get_ticks_usec() - 2000, 0, 600, 80)
	total_usec = int(tracker._trace_frame_us.get("extended.survivor_phys.total", -1))
	exclusive_usec = int(tracker._trace_frame_us.get("extended.survivor_phys.exclusive", -1))
	_check("覆盖父根内的共享叶不会二次扣减", exclusive_usec == total_usec - 600 - 120
		and int(tracker._trace_frame_us.get("extended.survivor_phys.covered", -1)) == 600
		and int(tracker._trace_frame_us.get("extended.survivor_phys.shared", -1)) == 120)
	_check("新增根仅添加净余量并保留原有根口径", tracker._trace_known_root_us()
		== existing_roots_usec + exclusive_usec)

	# 缺少共享叶计时的 sampled 帧，应把该工作保留在净余量而不是凭空扣除。
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.finish_extended_cpu("prediction_prepare", Time.get_ticks_usec() - 1000, 0)
	_check("没有已计父项时整段进入新增根", tracker._trace_frame_us.get(
		"extended.prediction_prepare.exclusive") == tracker._trace_frame_us.get(
		"extended.prediction_prepare.total"))
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.finish_extended_cpu("missile_phys", Time.get_ticks_usec() - 1000, 1)
	tracker.finish_extended_cpu("sam_phys", Time.get_ticks_usec() - 1000, 0, 1 << 60)
	_check("负共享量与过度覆盖均显式拒绝归因", int(tracker._trace_frame_counts.get(
		"extended_cpu_invalid_scope", 0)) == 2 and int(tracker._trace_frame_events.get(
		"extended_cpu_invalid_scope", 0)) == 2
		and not tracker._trace_frame_us.has("extended.missile_phys.exclusive")
		and not tracker._trace_frame_us.has("extended.sam_phys.exclusive")
		and int(tracker._trace_frame_us.get("extended.sam_phys.invalid", 0)) < 0
		and tracker._trace_known_root_us() == 0)

	# 用已知常量验证结算与输出，不让时钟调度噪声决定全程均值。
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.tick("aircraft_phys", 500)
	tracker.tick("extended.missile_phys.exclusive", 1000)
	tracker.tick("extended.trail_process.exclusive", 200)
	tracker.tick("extended.missile_phys.total", 900000)
	tracker.tick("extended.missile_phys.shared", 800000)
	tracker.begin_render_frame(0.010)
	tracker.tick("extended.missile_phys.exclusive", 3000)
	tracker.tick("extended.prediction_prepare.exclusive", 400)
	tracker.tick("extended.survivor_phys.covered", 700000)
	tracker.begin_render_frame(0.010)
	var dump: String = tracker.format_frame_trace_dump()
	_check("新根逐帧累加并保存各自活跃帧数", tracker._trace_total_known_us == 5100
		and tracker._trace_root_total_us.get("extended.missile_phys.exclusive") == 4000
		and tracker._trace_root_active_frames.get("extended.missile_phys.exclusive") == 2
		and tracker._trace_root_total_us.get("extended.trail_process.exclusive") == 200
		and tracker._trace_root_active_frames.get("extended.trail_process.exclusive") == 1)
	_check("全程输出只把扩展净值加入均值", dump.contains("trace_roots frames=2 known_avg=2.550ms")
		and dump.contains("extended.missile_phys.exclusive=2.000ms@2/2")
		and dump.contains("extended.trail_process.exclusive=0.100ms@1/2")
		and dump.contains("extended.prediction_prepare.exclusive=0.200ms@1/2"), dump)
	tracker.configure_frame_trace(false)
	_check("关闭配置清空扩展根及共享计数", not tracker.extended_cpu_trace_enabled
		and tracker.extended_cpu_shared_usec == 0
		and not tracker._trace_root_total_us.has("extended.missile_phys.exclusive"))
	OS.set_environment("AGL_BENCH_FRAME_TRACE_MODE", "off")
	tracker.configure_frame_trace(true)
	_check("追踪总开关关闭时扩展请求不越权开启", not tracker.frame_trace_enabled
		and not tracker.extended_cpu_trace_enabled)
	OS.set_environment("AGL_BENCH_FRAME_TRACE_MODE", "sampled")
	tracker.enabled = false
	tracker.configure_frame_trace(true)
	_check("性能采集关闭时扩展请求不启动", not tracker.extended_cpu_trace_enabled)
	tracker.free()
	for key in environment:
		if bool(environment[key].present):
			OS.set_environment(key, String(environment[key].value))
		else:
			OS.unset_environment(key)


func _test_map_root_and_context() -> void:
	var tracker := PerfBucketsScript.new()
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.010)
	tracker.tick("tokyo_map_process", 500)
	tracker.tick("tokyo_map_stream", 100)
	tracker.tick("building_draw", 100)
	tracker.tick("tokyo_map_camera", 200)
	tracker.tick("tokyo_map_geometry", 200)
	tracker.tick("tokyo_map_bind", 50)
	tracker.tick("tokyo_map_update_request", 1)
	for name in ["aircraft_phys", "ai_tick", "bullet_phys", "radar_locks"]:
		tracker.tick(name, 1000)
	tracker.begin_render_frame(0.020)
	var dump := tracker.format_frame_trace_dump()
	_check("地图与旧楼根桶不重复累计内部相机/几何/绑定子桶", dump.contains("known=4.700ms"))
	_check("旧楼绘制有独立全程平均根桶", dump.contains("building_draw=0.100ms"))
	_check("被战斗top4挤掉的地图子桶仍有逐帧专栏",
		dump.contains("map=[tokyo_map_process=500us") and dump.contains("tokyo_map_update_request=1us"))
	tracker.configure_frame_trace(false)
	_check("关闭追踪清空地图记录", tracker.format_frame_trace_dump().is_empty())
	tracker.free()


func _test_render_partition() -> void:
	var trace: Script = load("res://scripts/tests/tokyo_render_clock.gd")
	_check("同步呈现诊断只接受有效刷新率下的显式余量", trace.diagnostic_cap("", -1.0)==0
		and trace.diagnostic_cap("117",120.0)==117 and trace.diagnostic_cap("120",120.0)==-1
		and trace.diagnostic_cap("60",120.0)==-1 and trace.diagnostic_cap("117",-1.0)==-1
		and trace.diagnostic_cap("117",NAN)==-1 and trace.diagnostic_cap("bad",120.0)==-1
		and trace.diagnostic_cap("1001",2000.0)==-1)
	_check("实际时钟分段守恒", trace.partition(10, 15, 22, 30) == PackedInt64Array([5, 7, 8, 20]))
	_check("缺绘制回调拒绝拼接", trace.partition(10, 0, 22, 30).is_empty())
	_check("倒序时间拒绝归因", trace.partition(10, 22, 15, 30).is_empty())
	_check("未开始样本拒绝归因", trace.partition(0, 15, 22, 30).is_empty())
	_check("真实帧时60FPS边界严格且缺样本不通过", trace.frame_within_budget(16666)
		and not trace.frame_within_budget(16667) and not trace.frame_within_budget(0))
	var samples := PackedInt64Array([30000, 1000, 2000, 4000])
	var measured: Dictionary = trace.percentiles_usec(samples)
	_check("墙钟分位数使用最近秩且不改输入", measured.p50_ms == 2.0 and measured.p95_ms == 30.0
		and measured.p99_ms == 30.0 and measured.samples == 4 and samples[0] == 30000)
	_check("尾部帧率取最慢样本均值倒数", measured.p999_ms==30.0 and measured.over30==0
		and is_equal_approx(measured.low1_fps,1000.0/30.0) and is_equal_approx(measured.low01_fps,1000.0/30.0))
	_check("缺失或无效墙钟样本不伪造零耗时", trace.percentiles_usec(PackedInt64Array()).is_empty()
		and trace.percentiles_usec(PackedInt64Array([0])).is_empty())
	var slow: Array[Dictionary] = []
	for index in range(32):
		trace.retain_slowest(slow, {"frame":index,"wall_us":17000+index})
	_check("晚到长帧不会被前32帧挤掉", trace.retain_slowest(slow, {"frame":1000,"wall_us":70000,"draw_us":53000})
		and slow.size()==32 and slow.any(func(row: Dictionary) -> bool: return row.get("draw_us")==53000))
	_check("更短或等长记录不顶替已保留样本", not trace.retain_slowest(slow, {"frame":1001,"wall_us":100})
		and not trace.retain_slowest(slow, {"frame":1002,"wall_us":17001}) and slow.size()==32)
	var expected: Array[int] = []
	for index in range(1000):
		var cost := 18000+((index*37)%1000)
		expected.append(cost)
		trace.retain_slowest(slow, {"frame":index+2000,"wall_us":cost})
	expected.append(70000)
	expected.sort()
	var actual: Array[int] = []
	for row: Dictionary in slow:
		actual.append(int(row.wall_us))
	actual.sort()
	_check("长序列仅保留真实最大32个耗时且容量不增长", actual==expected.slice(-32) and slow.size()==32)
	var previous := slow.duplicate(true)
	_check("无效诊断输入不破坏已有记录", not trace.retain_slowest(slow,{"wall_us":0})
		and not trace.retain_slowest(slow,{"wall_us":80000},0) and slow==previous)
	var tracker := PerfBucketsScript.new()
	tracker.configure_frame_trace(true)
	tracker.begin_render_frame(0.01)
	tracker.tick("tokyo_map_process", 100)
	tracker.tick("tokyo_map_wall_draw", 10000)
	tracker.begin_render_frame(0.02)
	_check("渲染墙钟段不计作脚本CPU根桶", tracker.format_frame_trace_dump().contains("known=0.100ms"))
	tracker.free()


func _test_render_timeline() -> void:
	var observer: RefCounted=load("res://scripts/tests/tokyo_render_trace.gd").new()
	var previous := PerfBuckets.frame_trace_enabled
	PerfBuckets.frame_trace_enabled=true
	observer._closed=false
	observer._timeline_enabled=true
	observer._begin=10000;observer._pre=15000;observer._post=18000
	observer._engine_frame=123;observer._frame=456
	observer._latest={"map_gpu_ms":1.25};observer._backend_samples=9
	observer.begin_frame(0.02,30000)
	var row: Dictionary=observer._phase_frames[0] if not observer._phase_frames.is_empty() else {}
	observer._latest.map_gpu_ms=2.0
	_check("全帧分段保持同一原始时钟与引擎帧身份",row.get("begin_ticks_usec")==10000 and row.get("next_ticks_usec")==30000
		and row.get("engine_frame")==123 and row.get("wall_us")==20000 and row.get("before_draw_us",0)+row.get("draw_us",0)+row.get("after_draw_us",0)==20000)
	_check("后端快照解耦且明确不是同帧GPU证明",row.get("backend_not_same_frame_proof",{}).get("map_gpu_ms")==1.25 and row.get("backend_readback_sample")==9)
	observer._timeline_enabled=false
	observer._pre=35000;observer._post=38000
	observer.begin_frame(0.02,50000)
	_check("关闭详细诊断不追加全帧分段",observer._phase_frames.size()==1)
	observer.close()
	_check("结束锚点保留时钟夹逼范围",observer._clock_end_anchor.get("ticks_after_usec",0)>=observer._clock_end_anchor.get("ticks_before_usec",1))
	PerfBuckets.frame_trace_enabled=previous


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
	tracker.tick("survivor_cache", 300)
	tracker.tick("survivor_lod", 200)
	tracker.tick("survivor_spawner", 100)
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
		and text.contains("生存主循环  缓存 0.30  LOD 0.20  刷怪器 0.10 ms")
		and text.contains("单位  total 57")
		and text.contains("BOSS PHASE")
		and text.contains("skill 3.0")
		and text.contains("bullets 80"), text)
	tracker.configure_runtime_panel(false)
	_check("closing F3 disables detail capture and clears frame history",
		not tracker.detail_capture_enabled()
		and int(tracker.runtime_frame_stats().get("samples", -1)) == 0)
	tracker.free()
