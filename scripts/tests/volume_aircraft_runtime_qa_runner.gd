extends Node2D
## 真实 Aircraft 节点的三维路由画廊；同时覆盖显示名后缀、AWACS 改名与释放后缓存刷新。

const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const Catalog := preload("res://scripts/aircraft_silhouette_catalog.gd")
const BODY_META := &"volume_3d_body"
const SAMPLES: Array[Dictionary] = [
	{"key": "f14", "path": "res://resources/player/player_f14.tres", "label": "F-14 / WARHOUND"},
	{"key": "a10", "path": "res://resources/player/player_a10.tres", "label": "A-10 / PLAYER"},
	{"key": "f47", "path": "res://resources/player/player_f47.tres", "label": "F-47 / PLAYER"},
	{"key": "f104", "path": "res://resources/player/player_f104c.tres", "label": "F-104C / PLAYER"},
	{"key": "f15", "path": "res://resources/player/player_f15c.tres", "label": "F-15C / PLAYER"},
	{"key": "f16", "path": "res://resources/player/player_f16.tres", "label": "F-16 / PLAYER"},
	{"key": "f22", "path": "res://resources/player/player_f22.tres", "label": "F-22 / PLAYER"},
	{"key": "f35", "path": "res://resources/player/player_f35.tres", "label": "F-35 / PLAYER"},
	{"key": "yf23", "path": "res://resources/player/player_yf23.tres", "label": "YF-23 / PLAYER"},
	{"key": "tu160", "path": "res://resources/enemy_tu160.tres", "label": "TU-160 / AWACS ALIAS"},
	{"key": "b1b", "path": "res://resources/friendly_b1b.tres", "label": "B-1B / ALLY"},
	{"key": "f4", "path": "res://resources/player/player_f4e.tres", "label": "F-4E / PLAYER"},
	{"key": "f86", "path": "res://resources/enemy_f86.tres", "label": "F-86 / ENEMY"},
	{"key": "f100", "path": "res://resources/enemy_f100.tres", "label": "F-100 / ENEMY"},
	{"key": "fa18", "path": "res://resources/enemy_fa18.tres", "label": "F/A-18 / ENEMY"},
	{"key": "mig29", "path": "res://resources/enemy_fighter.tres", "label": "MIG-29 / ENEMY"},
	{"key": "su27", "path": "res://resources/player/player_su27.tres", "label": "SU-27 / PLAYER"},
	{"key": "rafale", "path": "res://resources/player/player_rafale.tres", "label": "RAFALE / PLAYER"},
	{"key": "typhoon", "path": "res://resources/player/player_typhoon.tres", "label": "TYPHOON / PLAYER"},
	{"key": "a6e", "path": "res://resources/player/player_a6e.tres", "label": "A-6E / PLAYER"},
	{"key": "a7", "path": "res://resources/enemy_a7.tres", "label": "A-7 / ENEMY"},
	{"key": "ea6b", "path": "res://resources/player/player_ea6b.tres", "label": "EA-6B / PLAYER"},
	{"key": "f15smtd", "path": "res://resources/player/player_f15smtd.tres", "label": "F-15 S/MTD / PLAYER"},
	{"key": "fa18e", "path": "res://resources/player/player_fa18e.tres", "label": "F/A-18E / PLAYER"},
	{"key": "fck1", "path": "res://resources/enemy_fck1.tres", "label": "F-CK-1 / ENEMY"},
	{"key": "gripen", "path": "res://resources/player/player_gripen_c.tres", "label": "GRIPEN / PLAYER"},
	{"key": "harrier", "path": "res://resources/player/player_harrier.tres", "label": "HARRIER / PLAYER"},
	{"key": "j20", "path": "res://resources/player/player_j20.tres", "label": "J-20 / PLAYER"},
	{"key": "j35f", "path": "res://resources/player/player_j35f.tres", "label": "J 35F / PLAYER"},
	{"key": "j7", "path": "res://resources/enemy_interceptor.tres", "label": "J-7 / ENEMY"},
	{"key": "jaguar", "path": "res://resources/player/player_jaguar.tres", "label": "JAGUAR / PLAYER"},
	{"key": "mig21f13", "path": "res://resources/player/player_mig21f13.tres", "label": "MIG-21F-13 / PLAYER"},
	{"key": "mig23", "path": "res://resources/player/player_mig23.tres", "label": "MIG-23 / PLAYER"},
	{"key": "mig31", "path": "res://resources/player/player_mig31.tres", "label": "MIG-31 / PLAYER"},
	{"key": "mirage3", "path": "res://resources/player/player_mirage3.tres", "label": "MIRAGE III / PLAYER"},
	{"key": "mirage2000", "path": "res://resources/player/player_mirage2000.tres", "label": "MIRAGE 2000 / PLAYER"},
	{"key": "q5", "path": "res://resources/enemy_q5.tres", "label": "Q-5 / ENEMY"},
	{"key": "su34", "path": "res://resources/player/player_su34.tres", "label": "SU-34 / PLAYER"},
	{"key": "su47", "path": "res://resources/enemy_su47.tres", "label": "SU-47 / ENEMY"},
	{"key": "su57", "path": "res://resources/player/player_su57.tres", "label": "SU-57 / PLAYER"},
	{"key": "tornado", "path": "res://resources/player/player_tornado.tres", "label": "TORNADO / PLAYER"},
	{"key": "viggen", "path": "res://resources/player/player_viggen.tres", "label": "VIGGEN / PLAYER"},
	{"key": "a12", "path": "res://resources/player/player_a12.tres", "label": "A-12 / PROJECT CONCEPT"},
	{"key": "ah64", "path": "res://resources/enemy_ah64.tres", "label": "AH-64 / ANIMATED ROTORS", "silhouette": "apache"},
	{"key": "ch47", "path": "res://resources/enemy_ch47.tres", "label": "CH-47 / TANDEM ROTORS", "silhouette": "chinook"},
	{"key": "mq109_family", "path": "res://resources/enemy_uav.tres", "label": "MQ-109 / FAMILY"},
	{"key": "mq112", "path": "res://resources/enemy_uav_railgun.tres", "label": "MQ-112 / RAILGUN"},
	{"key": "mqx", "path": "res://resources/enemy_uav_mqx.tres", "label": "MQ-X / ELITE"},
	{"key": "aegis_uav", "path": "res://resources/enemy_uav_laser.tres", "label": "AEGIS / INTERCEPTOR"},
	{"key": "loyal_wingman", "path": "res://resources/loyal_wingman_drone.tres", "label": "LOYAL WINGMAN / ALLY", "silhouette": "drone"},
	{"key": "probe", "path": "res://resources/drone_probe.tres", "label": "PROBE / DEBUG"},
	{"key": "faxx", "path": "res://resources/player/player_faxx.tres", "label": "F/A-XX / PROJECT CONCEPT"},
	{"key": "fcas", "path": "res://resources/player/player_fcas.tres", "label": "FCAS / PROJECT CONCEPT"},
	{"key": "gcap", "path": "res://resources/player/player_gcap.tres", "label": "GCAP / PROJECT CONCEPT"},
	{"key": "j36", "path": "res://resources/player/player_j36.tres", "label": "J-36 / PROJECT CONCEPT"},
	{"key": "mig41", "path": "res://resources/player/player_mig41.tres", "label": "MIG-41 / PROJECT CONCEPT"},
	{"key": "af03", "path": "res://resources/enemy_af03.tres", "label": "AF-03 / RAILGUN"},
	{"key": "ax00", "path": "res://resources/player/player_ax00.tres", "label": "AX-00 / LEGEND"},
	{"key": "cre", "path": "res://resources/enemy_cre.tres", "label": "CRE / ACE"},
	{"key": "deadair", "path": "res://resources/enemy_deadair.tres", "label": "DEADAIR / EW", "silhouette": "deadair"},
	{"key": "sentinel", "path": "res://resources/enemy_uav_commander.tres", "label": "SENTINEL / COMMAND"},
	{"key": "snowblind", "path": "res://resources/enemy_snowblind.tres", "label": "SNOWBLIND / SHROUD"},
	{"key": "hyper_a", "path": "res://resources/enemy_hyper_a_g0.tres", "label": "HYPER-A G0 / BOSS", "silhouette": "hyper_a"},
	{"key": "x02", "path": "res://resources/player/player_x02.tres", "label": "X-02 / WYVERN"},
	{"key": "x09", "path": "res://resources/player/player_x09.tres", "label": "X-09 / THUNDER OWL"},
	{"key": "x13", "path": "res://resources/player/player_x13.tres", "label": "X-13 / SKYFALCON"},
	{"key": "x21", "path": "res://resources/player/player_x21.tres", "label": "X-21 / LONGREACH"},
	{"key": "x44", "path": "res://resources/player/player_x44.tres", "label": "X-44 / ANVIL"},
	{"key": "x77", "path": "res://resources/player/player_x77.tres", "label": "X-77 / PHANTOM RAVEN"},
	{"key": "x90", "path": "res://resources/player/player_x90.tres", "label": "X-90 / SKYWHALE"},
]
const PAGE_SIZE := 8
const COLUMNS := 4

var camera := Camera2D.new()
var _map_features: CanvasItem
var _building_renderer: CanvasItem
var _aircraft: Array[Aircraft] = []
var _probe
var _labels: Array[Label] = []
var _title := Label.new()
var _pass := 0
var _fail := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	add_child(camera)
	camera.zoom = Vector2.ONE * 1.20
	camera.make_current()
	_build_overlay()
	if not _spawn_real_aircraft():
		_finish(1)
		return
	_set_page(0)
	_probe = Probe.new()
	add_child(_probe)
	_probe.setup(self, "volume_3d_aircraft_runtime_qa")
	_run_qa.call_deferred()


func _spawn_real_aircraft() -> bool:
	var positions: Array[Vector2] = []
	for row in 2:
		var row_count := COLUMNS
		for column in row_count:
			positions.append(Vector2((float(column) - 0.5 * float(row_count - 1)) * 240.0,
				(float(row) - 0.5) * 216.0))
	for index in SAMPLES.size():
		var sample := SAMPLES[index]
		var params := load(String(sample.path)) as AircraftParams
		if params == null:
			_check(false, "formal AircraftParams loads: %s" % sample.path)
			return false
		var ac := Aircraft.new()
		ac.params = params.duplicate(true)
		ac.position = positions[index % PAGE_SIZE]
		ac.initial_heading_deg = 0.0
		if sample.has("silhouette"):
			ac.set_meta(&"silhouette", String(sample.silhouette))
		ac.team = CombatUnit.TEAM_HOSTILE if String(sample.key) == "tu160" \
			else (CombatUnit.TEAM_ALLY if String(sample.key) == "b1b" else CombatUnit.TEAM_PLAYER)
		# 两条正式改名路径：后缀呼号与 AWACS display_name 都不能破坏稳定机型身份。
		if String(sample.key) == "f14":
			ac.set_meta(&"airframe_label", ac.params.display_name)
			ac.params.display_name += " Warhound"
		elif String(sample.key) == "tu160":
			ac.set_meta(&"airframe_label", ac.params.display_name)
			ac.params.display_name = "AWACS"
		add_child(ac)
		ac.process_mode = Node.PROCESS_MODE_DISABLED
		_aircraft.append(ac)
		CombatUnit.all_units.append(ac)
		_check(Catalog.canonical_model_key_for(ac) == String(sample.key),
			"stable identity routes %s" % sample.label)
	return true


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var title_background := ColorRect.new()
	title_background.color = Color(0.025, 0.045, 0.06, 0.93)
	title_background.size = Vector2(1600.0, 86.0)
	layer.add_child(title_background)
	_title.position = Vector2(28.0, 10.0)
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("e4f0f4"))
	layer.add_child(_title)
	for index in PAGE_SIZE:
		var row := index / COLUMNS
		var column := index % COLUMNS
		var center := Vector2(800.0, 450.0) + Vector2(
			(float(column) - 0.5 * float(COLUMNS - 1)) * 288.0,
			(float(row) - 0.5) * 259.0)
		var label := Label.new()
		label.position = center + Vector2(-150.0, 43.0)
		label.size = Vector2(300.0, 28.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("c5d8df"))
		layer.add_child(label)
		_labels.append(label)


func _set_page(page_index: int) -> void:
	var start := page_index * PAGE_SIZE
	var page_count := mini(PAGE_SIZE, SAMPLES.size() - start)
	for index in _aircraft.size():
		var local_index := index - start
		_aircraft[index].visible = local_index >= 0 and local_index < page_count
		if _aircraft[index].visible:
			var row := local_index / COLUMNS
			var column := local_index % COLUMNS
			_aircraft[index].position = Vector2(
				(float(column) - 0.5 * float(COLUMNS - 1)) * 240.0,
				(float(row) - 0.5) * 216.0)
	for index in _labels.size():
		_labels[index].visible = index < page_count
		_labels[index].text = String(SAMPLES[start + index].label) if index < page_count else ""
	_title.text = "AGL DEDICATED AIRCRAFT 3D — REAL AIRCRAFT ROUTING QA — PAGE %d/%d\n%d formal resources · PNG fallback remains available outside the adapter" % [
		page_index + 1, ceili(float(SAMPLES.size()) / PAGE_SIZE), SAMPLES.size()]


func _run_qa() -> void:
	var seen: Dictionary = {}
	var page_total := ceili(float(SAMPLES.size()) / PAGE_SIZE)
	for page_index in page_total:
		_set_page(page_index)
		for _frame in 12:
			await get_tree().process_frame
		_probe._process(0.11)
		var start := page_index * PAGE_SIZE
		var page_count := mini(PAGE_SIZE, SAMPLES.size() - start)
		var page_has_ah64 := false
		var page_has_ch47 := false
		_check(_probe.last_body_count == page_count, "visible real Aircraft page receives 3D bodies")
		_check(_probe.last_fallback_count == SAMPLES.size() - page_count,
			"only hidden gallery pages remain on PNG fallback")
		for local_index in page_count:
			var index := start + local_index
			var sample := SAMPLES[index]
			var ac := _aircraft[index]
			_check(ac.has_meta(BODY_META), "2D body hidden only while 3D body is active: %s" % sample.label)
			var body_route := String(sample.key)
			if int(_probe._counts.get(body_route, 0)) == 0:
				body_route = Probe.BODY_LOD_ROUTE_PREFIX + body_route
			if int(_probe._counts.get(body_route, 0)) == 0:
				body_route = Probe.BODY_LOD2_ROUTE_PREFIX + String(sample.key)
			_check(int(_probe._counts.get(body_route, 0)) == 1,
				"one routed runtime instance: %s" % sample.label)
			var body_batch: MultiMeshInstance3D = _probe._batches.get(body_route)
			var expected_livery := Probe.livery_ratio_for(ac.params.icon_color, ac.params.wing_color)
			var actual_livery := body_batch.multimesh.get_instance_custom_data(0) \
				if body_batch != null else Color.TRANSPARENT
			_check(body_batch != null and absf(actual_livery.r - expected_livery.r) < 0.03 \
				and absf(actual_livery.g - expected_livery.g) < 0.03 \
				and absf(actual_livery.b - expected_livery.b) < 0.03,
				"runtime batch carries this AircraftParams wing livery: %s" % sample.label)
			seen[String(sample.key)] = true
			page_has_ah64 = page_has_ah64 or String(sample.key) == "ah64"
			page_has_ch47 = page_has_ch47 or String(sample.key) == "ch47"
		if page_has_ah64 and page_has_ch47:
			_check(int(_probe._counts.get("mount_rotor", 0)) == 4,
				"AH-64 主/尾旋翼与 CH-47 前/后旋翼均走共享动态批次")
			var rotor_batch: MultiMeshInstance3D = _probe._batches.get("mount_rotor")
			var before_spin := rotor_batch.multimesh.get_instance_transform(0)
			_probe._process(0.1)
			var after_spin := rotor_batch.multimesh.get_instance_transform(0)
			_check(not before_spin.is_equal_approx(after_spin), "旋翼变换随运行时状态持续转动")
		await RenderingServer.frame_post_draw
		var output := "res://bench/results/volume_aircraft_runtime_qa_page_%02d.png" % [page_index + 1]
		var error := get_viewport().get_texture().get_image().save_png(output)
		_check(error == OK, "real Aircraft routing screenshot page saved")
	_check(seen.size() == SAMPLES.size(), "every produced canonical key is exercised by a real Aircraft")
	_check(_probe.max_projection_error_px < 0.1, "3D bodies stay aligned to 2D gameplay anchors")

	# 生命周期：真实移除一架，跨下一成员刷新，不能保留 freed WeakRef 或旧实例计数。
	_set_page(0)
	for _frame in 3:
		await get_tree().process_frame
	_probe._process(0.11)
	var released := _aircraft[0]
	var released_ref: WeakRef = weakref(released)
	CombatUnit.release_target_refs(released)
	CombatUnit.all_units.erase(released)
	released.queue_free()
	await get_tree().process_frame
	_probe._process(0.11)
	_check(released_ref.get_ref() == null, "released real Aircraft is freed")
	_check(int(_probe._counts.get("f14", 0)) == 0, "adapter drops freed Aircraft on next cache tick")

	# 适配器离场必须恢复幸存飞机的二维 fallback；然后才清理 fixture。
	_probe.queue_free()
	await get_tree().process_frame
	var restored := true
	for index in range(1, _aircraft.size()):
		restored = restored and not _aircraft[index].has_meta(BODY_META)
	_check(restored, "adapter teardown restores PNG fallback for every survivor")
	for index in range(1, _aircraft.size()):
		var ac := _aircraft[index]
		CombatUnit.release_target_refs(ac)
		CombatUnit.all_units.erase(ac)
		ac.queue_free()
	await get_tree().process_frame
	_finish(1 if _fail > 0 else 0)


func _finish(code: int) -> void:
	print("[Volume aircraft runtime QA] pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(code)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("[Volume aircraft runtime QA] PASS: " + label)
	else:
		_fail += 1
		push_error("Volume aircraft runtime QA: " + label)
