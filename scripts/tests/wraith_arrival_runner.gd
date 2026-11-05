extends Node

## 真实 Boss Debug → 六机演出 → 强化接战 → 六机真实伤害胜利；不写生涯。
const MODE_SCENE := preload("res://scenes/survivor_mode.tscn")
var _fail := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in ["bench_mode", "bench_scenario", "bench_duration"]:
		get_tree().remove_meta(key)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	for count in [0, 1, 3]:
		await _run_case(count)
	print("[WraithArrival] complete failed=%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print("[WraithArrival] %s %s" % ["PASS" if ok else "FAIL", label])
	_fail += int(not ok)

func _run_case(count: int) -> void:
	seed(42)
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "WRAITH_SQUADRON")
	get_tree().set_meta("boss_debug_scenario", "full")
	get_tree().set_meta("survivor_map_id", "boss_debug")
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f47.tres")
	get_tree().set_meta("boss_debug_node_id", "f47")
	var mode := MODE_SCENE.instantiate()
	add_child(mode)
	var event: BossEncounterEvent = null
	for _frame in range(120):
		await get_tree().process_frame
		if mode._event_director != null:
			event = mode._event_director.find_by_name("boss_encounter")
		if event != null:
			break
	_check("真实 Debug 延后启动 BOSS 事件", event != null)
	if event == null:
		mode.queue_free()
		await get_tree().process_frame
		return
	var squad := event.encounter as F47AceSquad
	# Debug 正式入口默认历史零；在演出第一帧前注入强化快照，检验接战层的真实支援与恐惧。
	squad.configure_progression(count)
	_check("历史 %d 生成六本体" % count, squad.members.size() == 6 and squad.all_members.size() == 6)
	var knights := 0
	for member in squad.members:
		knights += int(AceSquad.role_of(member) == AceSquad.AceRole.KNIGHT)
	_check("正式生成四近战两远程", knights == 4)
	_check("支援不进入登场", squad._progression_support.is_empty() and Presentation.cast.actors.size() == 6)
	var marks := [1.0, 3.4, 4.7, 5.7]
	var next := 0
	var started := Time.get_ticks_msec()
	while Presentation._cine_active and Time.get_ticks_msec() - started < 12000:
		await get_tree().process_frame
		var elapsed: float = Presentation._player.elapsed
		if next < marks.size() and elapsed >= float(marks[next]):
			await RenderingServer.frame_post_draw
			if next == 1:
				var complete := true
				var safe_view := get_viewport().get_visible_rect().grow(-60.0)
				for member in squad.members:
					var screen_pos: Vector2 = get_viewport().get_canvas_transform() * member.global_position
					complete = complete and member.visible and member._cloak_alpha > 0.99 and safe_view.has_point(screen_pos)
				_check("六架完整淡入并在安全画幅内", complete)
				_check("演出期间演员状态牌隐藏", squad.members.all(func(member): return preload("res://scripts/ui/unit_status_snapshot.gd").mode(member).is_empty()))
			if next == 3:
				print("[WraithArrival] 实际交汇触发=%s" % str(Presentation.cast._meet_started.values()))
			if count == 0:
				var path := "res://bench/results/wraith_six_%02d.png" % next
				_check("截图 %s" % path, get_viewport().get_texture().get_image().save_png(path) == OK)
			next += 1
	_check("完整经过四个分镜采样", next == marks.size())
	_check("演出结束立即接战", event.phase == BossEncounterEvent.Phase.ENGAGED and squad.combat_phase_active and squad.hud_visible)
	_check("时间舞台镜头演员全部释放", not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0) and Presentation.cast.actors.is_empty() and not Presentation._cine_active)
	var released := true
	for member in squad.members:
		released = released and not member.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE) and member._cloak_alpha > 0.99 and not member.is_cloaked
	_check("六机解除演出隐身", released)
	_check("历史 %d 支援数量正确" % count, squad._progression_support.size() == (2 if count >= 1 else 0))
	_check("历史 %d 恐惧门与单控制器" % count, (squad.fear_cone != null) == (count >= 3))
	for friendly in mode._squad_members_alive():
		friendly.invulnerable = true
	var victims: Array = squad.members.duplicate()
	for i in range(5):
		victims[i].take_damage(1000000.0)
	await get_tree().create_timer(0.7).timeout
	_check("击毁五架仍未结算", squad.active and squad.members.size() == 1 and not mode._is_victory)
	victims[5].take_damage(1000000.0)
	await get_tree().create_timer(0.7).timeout
	_check("第六架真实击毁后胜利，不等待 YF-23", not squad.active and squad.members.is_empty() and mode._is_victory)
	Presentation.clear_all()
	mode.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
