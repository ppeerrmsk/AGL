extends Node
##
## FrameProbe — 卡顿飞行记录器（诊断专用；默认不加载，零开销）
##
## 启用：环境变量 AGL_FRAME_PROBE=1。BenchRunner._ready 在任何模式（bench / 正常游玩）
## 下把本节点挂到自身下，跨场景常驻，PROCESS_MODE_ALWAYS（暂停/升级界面也记录）。
##
## 每个引擎迭代（= 一个渲染帧）拆成互斥墙钟阶段（两个边界节点优先级 ±1e9 夹住脚本段）：
##   phys_script  全部物理步里 _physics_process 脚本段之和
##   phys_engine  物理步脚本段之后的引擎工作（deferred / queue_free / 定时器 / PhysicsServer step）
##   proc_script  _process 脚本段
##   pre_render   _process 之后到 frame_pre_draw（deferred 调用、queue_free 释放、RS sync）
##   render       frame_pre_draw → frame_post_draw（Canvas/3D 提交、驱动、SwapBuffers/VSync）
##   post         frame_post_draw → 下一迭代首个回调（音频、_input 事件、OS 消息、帧延迟）
## 另记节点增删、对象/资源/显存、绘制调用、视口 GPU 时间与玩家屏幕位置（顿挫度量）。
## 慢帧另存明细：新增节点类别、PerfBuckets 本帧增量、计数器增量。
## 退出时写 res://bench/results/frame_probe_<tag>_<utc>.csv 与 .hitches.jsonl。

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")
const EDGE_PRIORITY := 1_000_000_000
const DETAIL_THRESHOLD_US := 16_700
const MAX_DETAIL_FRAMES := 600
const MAX_CLASSIFIED_ADDS_PER_FRAME := 4000
const PB_TOP := 14


class Edge extends Node:
	var probe
	var is_first := true

	func _physics_process(_delta: float) -> void:
		if is_first:
			probe.edge_phys_begin()
		else:
			probe.edge_phys_end()

	func _process(_delta: float) -> void:
		if is_first:
			probe.edge_proc_begin()
		else:
			probe.edge_proc_end()


# ── 当前帧累加 ──
var _cur_frame: int = -1
var _frame_start: int = 0
var _mark: int = 0
var _steps: int = 0
var _drawn: bool = false
var _added: int = 0
var _removed: int = 0
var _added_classes: Dictionary = {}
var _pb_base: Dictionary = {}
var _pb_frames_in_window: int = 0
var _counters_base: PackedFloat64Array = PackedFloat64Array()

# ── 显示态（post_draw 时采样，即本帧实际呈现的值）──
## ply_wx/wy/sx/sy 是玩家机【物理插值后的显示位置】（未插值时等于 global_position）；
## 物理位置另记在行尾 ply_px/ply_py，连同插值分数 interp_f 与开关 interp_on。
var _disp := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _disp_phys := PackedFloat64Array([0, 0, 0, 0])

# ── 逐帧列（结束时写 CSV）──
var _rows: Array[PackedFloat64Array] = []
var _details: Array[Dictionary] = []
var _subviewports: Array[WeakRef] = []
var _main_vp_rid: RID
var _started_usec: int = 0
var _dumped: bool = false

const COUNTER_MONITORS := [
	Performance.OBJECT_COUNT, Performance.OBJECT_RESOURCE_COUNT, Performance.OBJECT_NODE_COUNT,
	Performance.OBJECT_ORPHAN_NODE_COUNT, Performance.MEMORY_STATIC,
	Performance.RENDER_TEXTURE_MEM_USED, Performance.RENDER_BUFFER_MEM_USED,
	Performance.RENDER_VIDEO_MEM_USED,
]
const COUNTER_NAMES := ["objects", "resources", "nodes", "orphans", "mem_static",
	"tex_mem", "buf_mem", "vid_mem"]
const CSV_HEADER := "frame,t_ms,total_ms,steps,phys_script,phys_engine,proc_script,pre_render,render,post," \
	+ "added,removed,objects,resources,nodes,orphans,mem_static_mb,tex_mb,buf_mb,vid_mb," \
	+ "canvas_draws,canvas_items,draws3d,prims3d,vp_cpu,vp_gpu,sub_cpu,sub_gpu," \
	+ "cam_x,cam_y,zoom,ply_wx,ply_wy,ply_sx,ply_sy,frame_setup,paused,phys_signal,proc_signal," \
	+ "ply_px,ply_py,interp_f,interp_on"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_usec = Time.get_ticks_usec()
	for first in [true, false]:
		var edge := Edge.new()
		edge.probe = self
		edge.is_first = first
		edge.name = "FrameProbeFirst" if first else "FrameProbeLast"
		edge.process_mode = Node.PROCESS_MODE_ALWAYS
		edge.process_priority = -EDGE_PRIORITY if first else EDGE_PRIORITY
		edge.process_physics_priority = -EDGE_PRIORITY if first else EDGE_PRIORITY
		add_child(edge)
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	_main_vp_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_main_vp_rid, true)
	_counters_base.resize(COUNTER_MONITORS.size())
	if OS.has_environment("AGL_FRAME_PROBE_AUTOPLAY"):
		add_child(load("res://scripts/diagnostics/frame_probe_autoplay.gd").new())
	printerr("[FrameProbe] armed (detail >= %.1f ms)" % (DETAIL_THRESHOLD_US / 1000.0))


# ───────────────────────── 阶段边界 ─────────────────────────
# 每个边界：把距上一边界的墙钟记入 _gap 指定的阶段，再切换 _gap。
# 进入新的引擎迭代（process_frames 变化）时，未闭合的间隙记为上一帧的 post。
enum Gap { PHYS_SIGNAL, PHYS_SCRIPT, PHYS_POST, PROC_SIGNAL, PROC_SCRIPT, PRE_RENDER, RENDER, POST }
var _gap: int = Gap.POST
var _acc := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])


func _boundary(next_gap: int) -> void:
	var t := Time.get_ticks_usec()
	var f := Engine.get_process_frames()
	if f != _cur_frame:
		if _cur_frame >= 0:
			_acc[Gap.POST] += t - _mark
		_begin_frame(t, f)
	else:
		_acc[_gap] += t - _mark
	_mark = t
	_gap = next_gap


func _on_physics_frame() -> void:
	_boundary(Gap.PHYS_SIGNAL)


func _on_process_frame() -> void:
	_boundary(Gap.PROC_SIGNAL)


func edge_phys_begin() -> void:
	_boundary(Gap.PHYS_SCRIPT)
	_steps += 1


func edge_phys_end() -> void:
	_boundary(Gap.PHYS_POST)


func edge_proc_begin() -> void:
	_boundary(Gap.PROC_SCRIPT)


func edge_proc_end() -> void:
	_boundary(Gap.PRE_RENDER)


func _on_pre_draw() -> void:
	_boundary(Gap.RENDER)


func _on_post_draw() -> void:
	_boundary(Gap.POST)
	_drawn = true
	_sample_display()


func _on_node_added(node: Node) -> void:
	_added += 1
	if node is SubViewport:
		_register_subviewport(node as SubViewport)
	if _added > MAX_CLASSIFIED_ADDS_PER_FRAME:
		return
	var key := node.scene_file_path
	if key.is_empty():
		var script: Variant = node.get_script()
		key = (script as Script).resource_path.get_file() if script != null else node.get_class()
	else:
		key = key.get_file()
	_added_classes[key] = int(_added_classes.get(key, 0)) + 1


func _on_node_removed(_node: Node) -> void:
	_removed += 1


func _register_subviewport(vp: SubViewport) -> void:
	_subviewports.append(weakref(vp))
	# SubViewport 进树后 RID 才稳定；延迟一拍打开测时。
	call_deferred("_enable_measure", weakref(vp))


func _enable_measure(ref: WeakRef) -> void:
	var vp: Variant = ref.get_ref()
	if vp != null and is_instance_valid(vp):
		RenderingServer.viewport_set_measure_render_time((vp as SubViewport).get_viewport_rid(), true)


# ───────────────────────── 帧结算 ─────────────────────────

func _begin_frame(t: int, f: int) -> void:
	if _cur_frame >= 0:
		_finish_frame(t)
	_cur_frame = f
	_frame_start = t
	_mark = t
	_steps = 0
	_acc.fill(0)
	_drawn = false
	_added = 0
	_removed = 0
	if not _added_classes.is_empty():
		_added_classes.clear()


func _finish_frame(t: int) -> void:
	var total := t - _frame_start
	var post := _acc[Gap.POST]
	var counters := PackedFloat64Array()
	counters.resize(COUNTER_MONITORS.size())
	for i in COUNTER_MONITORS.size():
		counters[i] = Performance.get_monitor(COUNTER_MONITORS[i])
	var pb_delta: Dictionary = _pb_frame_delta()
	var row := PackedFloat64Array([
		_cur_frame, (_frame_start - _started_usec) / 1000.0, total / 1000.0, _steps,
		_acc[Gap.PHYS_SCRIPT] / 1000.0, _acc[Gap.PHYS_POST] / 1000.0, _acc[Gap.PROC_SCRIPT] / 1000.0,
		_acc[Gap.PRE_RENDER] / 1000.0, _acc[Gap.RENDER] / 1000.0, post / 1000.0,
		_added, _removed, counters[0], counters[1], counters[2], counters[3],
		counters[4] / 1048576.0, counters[5] / 1048576.0, counters[6] / 1048576.0,
		counters[7] / 1048576.0,
	])
	row.append_array(_disp)
	row.append(1.0 if get_tree().paused else 0.0)
	row.append(_acc[Gap.PHYS_SIGNAL] / 1000.0)
	row.append(_acc[Gap.PROC_SIGNAL] / 1000.0)
	row.append_array(_disp_phys)
	_rows.append(row)
	if total >= DETAIL_THRESHOLD_US and _details.size() < MAX_DETAIL_FRAMES:
		var counter_delta := {}
		if _counters_base.size() == counters.size():
			for i in counters.size():
				var d := counters[i] - _counters_base[i]
				if absf(d) > 0.0:
					counter_delta[COUNTER_NAMES[i]] = d
		_details.append({
			"frame": _cur_frame, "t_ms": (_frame_start - _started_usec) / 1000.0,
			"total_ms": total / 1000.0, "steps": _steps,
			"phys_signal": _acc[Gap.PHYS_SIGNAL] / 1000.0,
			"phys_script": _acc[Gap.PHYS_SCRIPT] / 1000.0, "phys_engine": _acc[Gap.PHYS_POST] / 1000.0,
			"proc_signal": _acc[Gap.PROC_SIGNAL] / 1000.0,
			"proc_script": _acc[Gap.PROC_SCRIPT] / 1000.0, "pre_render": _acc[Gap.PRE_RENDER] / 1000.0,
			"render": _acc[Gap.RENDER] / 1000.0, "post": post / 1000.0,
			"added": _added, "removed": _removed,
			"added_classes": _top_entries(_added_classes, 12),
			"perf_buckets_ms": _top_entries(pb_delta, PB_TOP),
			"counter_delta": counter_delta,
			"scene": _scene_name(),
		})
	_counters_base = counters


## PerfBuckets._window_us 本帧增量（处理每秒一次的双缓冲轮换）。
func _pb_frame_delta() -> Dictionary:
	var pb: Node = get_node_or_null("/root/PerfBuckets")
	if pb == null:
		return {}
	var now: Dictionary = pb.get("_window_us")
	var fiw: int = int(pb.get("_frames_in_window"))
	var delta := {}
	var rolled := fiw < _pb_frames_in_window
	if rolled:
		var snap: Dictionary = pb.get("_snap_us")
		for k in snap:
			var d := int(snap[k]) - int(_pb_base.get(k, 0))
			if d > 0:
				delta[k] = d / 1000.0
		for k in now:
			delta[k] = float(delta.get(k, 0.0)) + int(now[k]) / 1000.0
	else:
		for k in now:
			var d := int(now[k]) - int(_pb_base.get(k, 0))
			if d > 0:
				delta[k] = d / 1000.0
	_pb_base = now.duplicate()
	_pb_frames_in_window = fiw
	return delta


func _sample_display() -> void:
	var ct := get_viewport().canvas_transform
	_disp[0] = RenderingServer.viewport_get_render_info(_main_vp_rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_disp[1] = RenderingServer.viewport_get_render_info(_main_vp_rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	_disp[2] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_disp[3] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_disp[4] = RenderingServer.viewport_get_measured_render_time_cpu(_main_vp_rid)
	_disp[5] = RenderingServer.viewport_get_measured_render_time_gpu(_main_vp_rid)
	var sub_cpu := 0.0
	var sub_gpu := 0.0
	for i in range(_subviewports.size() - 1, -1, -1):
		var vp: Variant = _subviewports[i].get_ref()
		if vp == null or not is_instance_valid(vp):
			_subviewports.remove_at(i)
			continue
		var rid: RID = (vp as SubViewport).get_viewport_rid()
		sub_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		sub_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_disp[6] = sub_cpu
	_disp[7] = sub_gpu
	_disp[8] = ct.origin.x
	_disp[9] = ct.origin.y
	_disp[10] = ct.x.length()
	var player: Variant = AircraftRenderer.safe_player_ref()
	var wx := 0.0
	var wy := 0.0
	var sx := 0.0
	var sy := 0.0
	var px := 0.0
	var py := 0.0
	if player != null:
		# 本帧实际呈现的是插值显示态；post_draw 仍处于同一引擎迭代，插值分数未变。
		var wp: Vector2 = DisplayPacing.display_origin(player as Node2D)
		var sp: Vector2 = ct * wp
		var phys: Vector2 = (player as Node2D).global_position
		wx = wp.x
		wy = wp.y
		sx = sp.x
		sy = sp.y
		px = phys.x
		py = phys.y
	_disp[11] = wx
	_disp[12] = wy
	_disp[13] = sx
	_disp[14] = sy
	_disp[15] = RenderingServer.get_frame_setup_time_cpu()
	_disp_phys[0] = px
	_disp_phys[1] = py
	_disp_phys[2] = Engine.get_physics_interpolation_fraction()
	_disp_phys[3] = 1.0 if DisplayPacing.interpolation_enabled() else 0.0


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return String(scene.name) if scene != null else ""


static func _top_entries(values: Dictionary, limit: int) -> Array:
	var entries: Array = []
	for k in values:
		entries.append([String(k), values[k]])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return entries.slice(0, limit)


# ───────────────────────── 输出 ─────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_PREDELETE:
		dump()


func dump() -> void:
	if _dumped or _rows.is_empty():
		return
	_dumped = true
	var tag := "play"
	var runner: Node = get_parent()
	if runner != null and String(runner.get("bench_scenario")) != "":
		tag = String(runner.get("bench_scenario"))
	if OS.has_environment("AGL_FRAME_PROBE_TAG"):
		tag += "_" + OS.get_environment("AGL_FRAME_PROBE_TAG").validate_filename()
	var ts := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	var dir := "res://bench/results"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var base := "%s/frame_probe_%s_%s" % [dir, tag, ts]
	var csv := FileAccess.open(base + ".csv", FileAccess.WRITE)
	if csv == null:
		push_error("[FrameProbe] cannot write %s" % base)
		return
	csv.store_line(CSV_HEADER)
	for row in _rows:
		var cells := PackedStringArray()
		for v in row:
			cells.append(("%d" % v) if v == floorf(v) and absf(v) < 1e12 else ("%.4f" % v))
		csv.store_line(",".join(cells))
	csv.close()
	var jl := FileAccess.open(base + ".hitches.jsonl", FileAccess.WRITE)
	if jl != null:
		jl.store_line(JSON.stringify({
			"godot": Engine.get_version_info().get("string", "?"),
			"renderer": RenderingServer.get_video_adapter_name(),
			"vsync": DisplayServer.window_get_vsync_mode(),
			"refresh_hz": DisplayServer.screen_get_refresh_rate(),
			"max_fps": Engine.max_fps, "physics_tps": Engine.physics_ticks_per_second,
			"max_physics_steps": Engine.max_physics_steps_per_frame,
			"physics_interpolation": DisplayPacing.interpolation_enabled(),
			"physics_jitter_fix": Engine.physics_jitter_fix,
			"window": DisplayServer.window_get_size(), "frames": _rows.size(),
		}))
		for d in _details:
			jl.store_line(JSON.stringify(d))
		jl.close()
	printerr("[FrameProbe] wrote %s.csv (%d frames, %d detailed)" % [
		ProjectSettings.globalize_path(base), _rows.size(), _details.size()])
