extends Node

## 地面战区一次性刷怪的帧成本测量（专项 bench，不进 all）。
## 正式 SurvivorMode 里对有陆地的常规战区按 1~3 星强制刷出地面任务，报告：
##   trigger  触发调用（debug_force_respawn_zone，与正式首刷同一入口）本身的同步墙钟；
##   frames   之后 SETTLE_FRAMES 帧的最大/合计墙钟（分帧生成时工作摊在这些帧里）；
##   units    地面目标 / 驻守敌机 / 战区气氛单位最终数量；
##   banner   3★ 威胁横幅（tier3_threat_changed 激活）出现在触发后第几帧（-1 = 本次未登记 3★ 源）。
## AGL_SPAWN_BURST_MODE=sliced：走正式首刷的分帧续段（debug_force_respawn_zone(id, false)），
##   另报 done_frames（续段与炮兵分片全部完成所用帧数）；
## 默认 sync：调用即生成完毕，并输出 sig（同种子下全部新单位的类型/呼号/位置/航点与全局随机流摘要），
##   用于对照改动前后的一次性生成逐值相同。
## AGL_SPAWN_BURST_PREWARM=notice：本场景不经 BuildingPreloader，进场前先跑一遍 Loading 的
##   3★ 威胁通知字形预热（SurvivorRuntimePrewarm notice 段），对照 3★ 横幅首帧；默认不跑。
## 运行：bench/run.cmd zone_spawn_burst 1 300 Shadow Headless（Visual 同样可用）

const SURVIVOR_MODE_SCENE := preload("res://scenes/survivor_mode.tscn")
const RuntimePrewarmScript := preload("res://scripts/survivor/survivor_runtime_prewarm.gd")
const TRIALS_PER_STAR := 3
const BASELINE_FRAMES := 10
const SETTLE_FRAMES := 45

var _rows: Array[String] = []
var _sliced := OS.get_environment("AGL_SPAWN_BURST_MODE") == "sliced"
var _banner_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 正式战区只在非 bench 模式构造；本场景测的就是正式首刷路径。
	for meta_key in ["bench_mode", "bench_scenario", "bench_duration"]:
		if get_tree().has_meta(meta_key):
			get_tree().remove_meta(meta_key)
	get_tree().set_meta("survivor_map_id", "default")
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/playable_f15.tres")
	if OS.get_environment("AGL_SPAWN_BURST_PREWARM") == "notice":
		var prewarm = RuntimePrewarmScript.new()
		add_child(prewarm)
		var t_prewarm := Time.get_ticks_usec()
		while not prewarm._step_notice_text():
			await get_tree().process_frame
		print("[ZoneSpawnBurst] notice prewarm done (%.1fms wall)" % ((Time.get_ticks_usec() - t_prewarm) / 1000.0))
		prewarm.queue_free()
	var mode = SURVIVOR_MODE_SCENE.instantiate()
	add_child(mode)
	for _frame in range(10):
		await get_tree().process_frame
	var zm: ZoneMission = mode._zone_mission
	var zones: ZoneData = mode._zone_data
	if zm == null or zones == null:
		printerr("[ZoneSpawnBurst] survivor mode did not initialise zone missions")
		get_tree().quit(1)
		return
	mode.player_aircraft.set("invulnerable", true)
	var candidates: Array[StringName] = []
	for z: Dictionary in zones.get_zone_definitions():
		var zid: StringName = z["id"]
		if zones.is_airfield(zid) or zid == &"BOSS" or not z.get("ground_spawn_polygons", []).is_empty():
			continue
		if ZoneData.zone_has_land(zid):
			candidates.append(zid)
	if candidates.is_empty():
		printerr("[ZoneSpawnBurst] no ground-capable zone")
		get_tree().quit(1)
		return
	print("[ZoneSpawnBurst] candidates=%s mode=%s" % [candidates, "sliced" if _sliced else "sync"])
	zm.tier3_threat_changed.connect(_on_tier3_threat_changed)
	var worst_frame_ms := 0.0
	for star in [1, 2, 3]:
		for k in range(TRIALS_PER_STAR):
			var zid := candidates[(k + star) % candidates.size()]
			zones.set_state(zid, ZoneData.State.AVAILABLE)
			zones.set_mission_type(zid, "ground")
			if star == ZoneData.DIFFICULTY_MAX:
				zones.debug_claim_tier3_slot(zid)
			else:
				zones.debug_set_difficulty(zid, star)
			var base := await _measure_frames(BASELINE_FRAMES)
			# 触发前一刻播种：基线帧里 AI 会消耗全局随机数，提前播种会让签名随帧时序漂移。
			seed(7919 * star + k)
			var trigger_frame := Engine.get_process_frames()
			_banner_frame = -1
			var t0 := Time.get_ticks_usec()
			if _sliced:
				zm.call("debug_force_respawn_zone", zid, false)
			else:
				zm.debug_force_respawn_zone(zid)
			var trigger_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var sig := "-" if _sliced else _signature(zm, zid)
			var settle := await _measure_frames(SETTLE_FRAMES, zm, zid)
			var ground: int = (zm._spawned_zones.get(zid, []) as Array).size()
			var garrison: int = (zm._garrison_zones.get(zid, []) as Array).size()
			var atmosphere := 0
			if zm._zone_atmosphere != null:
				atmosphere = int(zm._zone_atmosphere.call("actor_count", zid))
			var frame_peak := maxf(trigger_ms + settle["first_ms"], settle["max_ms"])
			worst_frame_ms = maxf(worst_frame_ms, frame_peak)
			var banner := _banner_frame - trigger_frame if _banner_frame >= 0 else -1
			var row := "f=%d star=%d zone=%s trigger=%.1fms first_frame=%.1fms max_frame=%.1fms settle_sum=%.1fms baseline_max=%.1fms done_frames=%d ground=%d garrison=%d atmosphere=%d banner=%d sig=%s" % [
				trigger_frame, star, zid, trigger_ms, settle["first_ms"], settle["max_ms"], settle["sum_ms"],
				base["max_ms"], settle["done_frames"], ground, garrison, atmosphere, banner, sig]
			_rows.append(row)
			print("[ZoneSpawnBurst] " + row)
	print("[ZoneSpawnBurst] worst spawn frame (trigger+first frame or later frame) = %.1fms" % worst_frame_ms)
	mode.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _on_tier3_threat_changed(_zone_id: StringName, _profile: StringName, active: bool) -> void:
	if active and _banner_frame < 0:
		_banner_frame = Engine.get_process_frames()


## 逐帧墙钟：first_ms 为触发后第一帧，max/sum 覆盖全部测量帧；done_frames 为续段完成所用帧数。
func _measure_frames(count: int, zm: ZoneMission = null, zid: StringName = &"") -> Dictionary:
	var result := {"first_ms": 0.0, "max_ms": 0.0, "sum_ms": 0.0, "done_frames": 0}
	for i in range(count):
		if zm != null and _pending(zm, zid):
			result["done_frames"] = i + 1
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		if i == 0:
			result["first_ms"] = ms
		result["max_ms"] = maxf(float(result["max_ms"]), ms)
		result["sum_ms"] = float(result["sum_ms"]) + ms
	return result


## 改动前的代码没有续段字段：按名字反射读取，两个版本共用本 runner。
func _pending(zm: ZoneMission, zid: StringName) -> bool:
	var jobs = zm.get("_spawn_jobs")
	if jobs is Dictionary and (jobs as Dictionary).has(zid):
		return true
	var atmosphere = zm.get("_zone_atmosphere")
	return atmosphere != null and atmosphere.has_method("has_pending") \
		and bool(atmosphere.call("has_pending", zid))


## 同步首刷后立即取样：全部新单位的脚本/呼号/位置/航点 + 全局随机流（之后各帧的 AI 抖动不参与）。
func _signature(zm: ZoneMission, zid: StringName) -> String:
	var parts := PackedStringArray()
	for value in zm._spawned_zones.get(zid, []):
		if value is Node2D and is_instance_valid(value):
			parts.append("T:%s:%s:%s" % [_script_name(value), value.get("callsign"),
				Vector2i(value.global_position.round())])
	for value in zm._garrison_zones.get(zid, []):
		if value is Aircraft and is_instance_valid(value):
			var ac := value as Aircraft
			var ai := zm._get_ai_of(ac)
			parts.append("G:%s:%s:%s:%d" % [ac.params.display_name if ac.params else "", ac.callsign,
				Vector2i(ac.global_position.round()), ai.current_waypoint_index if ai else -1])
	if zm._zone_atmosphere != null:
		var entry: Dictionary = zm._zone_atmosphere.get("_engagements").get(zid, {})
		for side in ["allies", "opposition"]:
			for value in entry.get(side, []):
				if value is Node2D and is_instance_valid(value):
					parts.append("A:%s:%s:%s" % [side, value.get("callsign"),
						Vector2i(value.global_position.round())])
	return "%d/%08x/rng%04x" % [parts.size(), hash("|".join(parts)), randi() & 0xffff]


func _script_name(node: Object) -> String:
	var script: Script = node.get_script()
	return script.resource_path.get_file() if script != null else node.get_class()
