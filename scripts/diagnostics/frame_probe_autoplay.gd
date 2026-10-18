extends Node
##
## FrameProbeAutoplay — 诊断专用"自动驾驶"：按正式流程进入生存模式并自动游玩。
##
## 启用：AGL_FRAME_PROBE=1 且 AGL_FRAME_PROBE_AUTOPLAY=<秒>（正式局游玩时长）。
## 主菜单 → 写入与选图/选机界面相同的 meta → building_preloader（正式 Loading 与地图预热）
## → survivor_mode（正式战区/刷怪/HUD/镜头跟随）。玩家机挂 AIController 自主作战，
## 每 3 级的升级卡按真实点击路径选第 1 张；到时 quit，由 FrameProbe 写结果。
## 可选：AGL_FRAME_PROBE_AIRCRAFT=<PlayableAircraft 资源路径>，AGL_FRAME_PROBE_MORTAL=1（玩家可阵亡）。
## 注意：正式局会写 user:// 生涯档案；调用方负责在运行前后备份/还原 user 目录。
## 可选：AGL_FRAME_PROBE_SHOTS=<每组帧数> 在 SHOT_TIMES_S 各拉近到 SHOT_ZOOMS 并连续抓取实际呈现帧
## （frame_post_draw 读视口纹理，裁剪玩家机周边）到 res://tmp/map_visual_qa/frame_probe_shots/，
## 供肉眼检查尾迹/标签/连线与插值后的机体是否脱节；抓帧会造成数十毫秒停顿，勿与帧时统计混用。

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")
const DEFAULT_AIRCRAFT := "res://resources/playable_f15.tres"
const UPGRADE_PICK_DELAY_MS := 700
const SHOT_DIR := "res://tmp/map_visual_qa/frame_probe_shots"
const SHOT_TIMES_S := [40.0, 80.0, 120.0]
const SHOT_ZOOMS := [2.5, 1.2, 0.5]
const SHOT_ZOOM_LEAD_S := 2.5
const SHOT_CROP := Vector2i(960, 720)

var play_seconds: float = 180.0
var _phase := "menu"
var _phase_started_ms: int = 0
var _play_started_ms: int = 0
var _attached := false
var _upgrade_ready_ms: int = 0
var _last_heartbeat_ms: int = 0
var _upgrades_picked := 0
var _boundary_ready_ms: int = 0
var _boundary_cancels := 0
var _evo_ready_ms: int = 0
var _evo_closes := 0
var _paused_since_ms: int = 0
var _stuck_reported := false
var _shot_count := 0
var _shot_burst := -1
var _shot_frames_left := 0
var _shot_saved_zoom := -1.0
var _shot_mode: WeakRef = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	play_seconds = maxf(10.0, float(OS.get_environment("AGL_FRAME_PROBE_AUTOPLAY")))
	_shot_count = maxi(0, int(OS.get_environment("AGL_FRAME_PROBE_SHOTS")))
	_phase_started_ms = Time.get_ticks_msec()
	# 首局教程会等待玩家操作；自动游玩不演示教程（user:// 由调用方备份还原）。
	SurvivorTutorial.mark_done()
	SurvivorTutorial.mark_wingman_switch_done()
	printerr("[Autoplay] armed play_seconds=%.0f" % play_seconds)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var scene := get_tree().current_scene
	match _phase:
		"menu":
			if scene != null and now - _phase_started_ms > 1000:
				var tree := get_tree()
				tree.set_meta("survivor_map_id", "default")
				if tree.has_meta("ugc_map_path"):
					tree.remove_meta("ugc_map_path")
				tree.set_meta("map_preview_only", false)
				var aircraft := OS.get_environment("AGL_FRAME_PROBE_AIRCRAFT")
				tree.set_meta("survivor_aircraft_resource", aircraft if aircraft != "" else DEFAULT_AIRCRAFT)
				printerr("[Autoplay] menu → building_preloader")
				tree.change_scene_to_file("res://scenes/building_preloader.tscn")
				_set_phase("loading")
		"loading":
			if scene != null and scene.get("player_aircraft") != null and scene.has_method("_bench_runtime_status"):
				_set_phase("play")
				_play_started_ms = now
				printerr("[Autoplay] survivor_mode reached after %.1fs loading" % [
					(now - _phase_started_ms) / 1000.0])
		"play":
			_drive(scene, now)


func _drive(mode: Node, now: int) -> void:
	if mode == null or not mode.has_method("_bench_runtime_status"):
		return
	var player: Variant = mode.get("player_aircraft")
	if not _attached and player != null and is_instance_valid(player):
		mode.call("_bench_attach_player_ai")
		# 巡逻环收向地图核心，避免 AI 自主巡逻冲出外缘空域反复触发越界决策。
		var ai: Node = (player as Node).get_node_or_null("AI_BenchPlayer")
		if ai != null:
			var center: Vector2 = MapBoundary.get_player_start() * 0.6
			var loop := PackedVector2Array()
			for corner: Vector2 in [Vector2(2500, -2500), Vector2(2500, 2500), Vector2(-2500, 2500), Vector2(-2500, -2500)]:
				loop.append(MapBoundary.clamp_inside(center + corner, 6000.0))
			ai.set("waypoints", loop)
		if OS.get_environment("AGL_FRAME_PROBE_MORTAL") != "1":
			(player as Node).set("invulnerable", true)
		_attached = true
		printerr("[Autoplay] player AI attached")
	if bool(mode.get("is_paused_for_upgrade")):
		var ui: Variant = mode.get("upgrade_ui")
		if ui != null and is_instance_valid(ui) and not bool(ui.get("_input_locked")) \
				and not bool(ui.get("_selection_locked")):
			if _upgrade_ready_ms == 0:
				_upgrade_ready_ms = now
			elif now - _upgrade_ready_ms >= UPGRADE_PICK_DELAY_MS:
				ui.call("_on_choice_pressed", 0)
				_upgrades_picked += 1
				_upgrade_ready_ms = 0
	else:
		_upgrade_ready_ms = 0
	# 停靠/机场规划站：直接起飞（等价于玩家关闭面板）。
	var evo: Variant = mode.get("_evolution_ui")
	if evo != null and is_instance_valid(evo) and (evo as CanvasLayer).visible \
			and bool(mode.get("is_paused_for_upgrade")):
		if _evo_ready_ms == 0:
			_evo_ready_ms = now
		elif now - _evo_ready_ms >= 1500:
			evo.call("_close")
			_evo_closes += 1
			_evo_ready_ms = 0
	else:
		_evo_ready_ms = 0
	# 卡住检测：树暂停超过 8 秒时打印一次状态，便于补自动处理。
	if get_tree().paused:
		if _paused_since_ms == 0:
			_paused_since_ms = now
		elif now - _paused_since_ms > 8000 and not _stuck_reported:
			_stuck_reported = true
			printerr("[Autoplay] STUCK paused>8s: %s" % String(mode.call("_bench_runtime_status")))
	else:
		_paused_since_ms = 0
		_stuck_reported = false
	# 越界决策面板：按"取消"（游戏自身把机头转向内侧），与真人最常见选择一致。
	var boundary: Variant = mode.get("_boundary_ui")
	if boundary != null and is_instance_valid(boundary) and bool(boundary.get("_menu_visible")):
		if _boundary_ready_ms == 0:
			_boundary_ready_ms = now
		elif now - _boundary_ready_ms >= UPGRADE_PICK_DELAY_MS:
			boundary.call("_on_cancel_pressed")
			_boundary_cancels += 1
			_boundary_ready_ms = 0
	else:
		_boundary_ready_ms = 0
	if _shot_count > 0:
		_drive_shots(mode, (now - _play_started_ms) / 1000.0)
	if now - _last_heartbeat_ms >= 10000:
		_last_heartbeat_ms = now
		var pp: Vector2 = (player as Node2D).global_position if player != null and is_instance_valid(player) else Vector2.ZERO
		printerr("[Autoplay] t=%.0fs picks=%d boundary_cancels=%d pos=%s %s" % [(now - _play_started_ms) / 1000.0,
			_upgrades_picked, _boundary_cancels, str(pp.round()), String(mode.call("_bench_runtime_status"))])
	var over := bool(mode.get("is_game_over")) or bool(mode.get("_is_victory"))
	if now - _play_started_ms >= int(play_seconds * 1000.0) or (over and now - _phase_started_ms > 4000):
		printerr("[Autoplay] finished after %.1fs game time (over=%s)" % [
			(now - _play_started_ms) / 1000.0, str(over)])
		_set_phase("done")
		EventLogger.dump_to_file()
		get_tree().quit(0)


## 截帧调度：提前 SHOT_ZOOM_LEAD_S 秒把镜头拉到目标缩放，到点后连续 _shot_count 个呈现帧截图。
func _drive_shots(mode: Node, play_s: float) -> void:
	if _shot_frames_left > 0:
		return
	var next := _shot_burst + 1
	if next >= SHOT_TIMES_S.size():
		return
	var cam_ctrl: Variant = mode.get("_camera_ctrl")
	if cam_ctrl == null or not is_instance_valid(cam_ctrl):
		return
	if play_s >= float(SHOT_TIMES_S[next]) - SHOT_ZOOM_LEAD_S and _shot_saved_zoom < 0.0:
		_shot_saved_zoom = float(cam_ctrl.get("target_zoom"))
		cam_ctrl.set("target_zoom", float(SHOT_ZOOMS[next]))
	if play_s >= float(SHOT_TIMES_S[next]) and not get_tree().paused:
		_shot_burst = next
		_shot_frames_left = _shot_count
		_shot_mode = weakref(mode)
		if not RenderingServer.frame_post_draw.is_connected(_on_shot_post_draw):
			RenderingServer.frame_post_draw.connect(_on_shot_post_draw)


func _on_shot_post_draw() -> void:
	var mode: Variant = _shot_mode.get_ref() if _shot_mode != null else null
	if _shot_frames_left <= 0 or typeof(mode) != TYPE_OBJECT or not is_instance_valid(mode):
		_finish_shot_burst(mode)
		return
	var player: Variant = mode.get("player_aircraft")
	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()
	if image != null and typeof(player) == TYPE_OBJECT and is_instance_valid(player):
		var player_screen := DisplayPacing.display_screen_origin(player as Node2D)
		var screen: Vector2 = viewport.get_final_transform() * player_screen
		var crop := Rect2i(Vector2i(screen) - SHOT_CROP / 2, SHOT_CROP).intersection(
			Rect2i(Vector2i.ZERO, image.get_size()))
		if crop.has_area():
			image = image.get_region(crop)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
		var tag := "on" if DisplayPacing.interpolation_enabled() else "off"
		var index := _shot_count - _shot_frames_left
		image.save_png("%s/interp_%s_b%d_z%.1f_f%d_frac%.2f.png" % [SHOT_DIR, tag, _shot_burst,
			float(SHOT_ZOOMS[_shot_burst]), index, Engine.get_physics_interpolation_fraction()])
	_shot_frames_left -= 1
	if _shot_frames_left <= 0:
		_finish_shot_burst(mode)


func _finish_shot_burst(mode: Variant) -> void:
	_shot_frames_left = 0
	if RenderingServer.frame_post_draw.is_connected(_on_shot_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_shot_post_draw)
	if typeof(mode) == TYPE_OBJECT and is_instance_valid(mode) and _shot_saved_zoom > 0.0:
		var cam_ctrl: Variant = mode.get("_camera_ctrl")
		if cam_ctrl != null and is_instance_valid(cam_ctrl):
			cam_ctrl.set("target_zoom", _shot_saved_zoom)
	_shot_saved_zoom = -1.0
	printerr("[Autoplay] shot burst %d saved" % _shot_burst)


func _set_phase(next: String) -> void:
	_phase = next
	_phase_started_ms = Time.get_ticks_msec()
