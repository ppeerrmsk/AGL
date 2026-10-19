extends RefCounted

var _pass := 0
var _fail := 0

class Host extends RefCounted:
	var members: Array = []
	var targets: Array = []
	var enabled := true
	func fear_members() -> Array: return members
	func fear_targets() -> Array: return targets
	func fear_enabled() -> bool: return enabled

func run(root: Node, visual: bool = false) -> int:
	var world := Node2D.new()
	root.add_child(world)
	var old_player: Variant = AircraftRenderer.player_ref
	var emitter := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2.ZERO, "SOURCE")
	var victim := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(0, -600), "ACE")
	var immune := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(150, -600), "GRIPEN")
	var source2 := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2(0, -1200), "OTHER")
	AircraftRenderer.player_ref = victim
	var player := SurvivorPlayer.new()
	player.aircraft = immune
	player.apply_upgrade(SurvivorData.upgrade_by_id("sig_gripen_e"))
	_check(immune.sig_status_immune, "正式技能授予设置免疫")
	_check(not FearResponse.apply(immune, emitter), "电战预算拒绝来源 FEAR")
	_check(immune.fear_response == null and not immune.is_afterburner_mode_active() \
		and not FearResponse.obscure(immune), "免疫零控制/零加力/零遮蔽副作用")
	immune.apply_status(StatusEffects.OVERLOAD, 5.0)
	_check(immune.has_status(StatusEffects.OVERLOAD), "免疫不挡增益")
	var cfg := SquadFearConeConfig.new()
	cfg.initial_wait_s = 0.0
	var host := Host.new()
	host.members = [emitter]
	host.targets = [victim, immune]
	var cone := SquadFearConeController.new()
	_check(cone.setup(cfg, host), "通用宿主配置装配")
	cone.start()
	cone.update(0.5)
	_check(cone.phase == SquadFearConeController.Phase.WARNING, "进入预警")
	cone.update(1.0)
	_check(not victim.has_status(StatusEffects.FEAR), "预警无累计无恐惧")
	for i in range(19): cone.update(0.1)
	_check(not victim.has_status(StatusEffects.FEAR), "连续 1.9s 不触发")
	victim.position = Vector2(0, 500)
	cone.update(0.1)
	_check(cone.exposure.is_empty(), "背后离锥清空累计")
	victim.position = Vector2(0, -600)
	for i in range(20): cone.update(0.1)
	_check(FearResponse.controlled(victim), "2s 照射正式触发")
	_check(is_equal_approx(FearResponse.seconds(victim), 5.0), "持续 5s")
	_check(victim.is_afterburner_mode_active(), "零电池要求之外的本机强制加力")
	_check(not immune.has_status(StatusEffects.FEAR) and immune.fear_response == null, "锥体完整采样仍不绕过免疫")
	_check(not FearResponse.apply(victim, source2), "第二来源不刷新/替换")
	victim._resolve_intents(0.1)
	_check(victim.target_position.y < victim.position.y, "已背离来源继续远离，不反向掉头")
	emitter.position = Vector2(-600, -600)
	victim.fear_response.update(victim, 0.1)
	victim._resolve_intents(0.1)
	_check(victim.target_position.x > victim.position.x, "移动来源实时修正逃逸方向")
	victim.hard_brake = true
	victim._resolve_intents(0.1)
	_check(not victim.hard_brake and not victim.try_manual_maneuver(), "急刹/手动机动不能接管")
	var charge := AfterburnerCharge.new()
	charge.charge = 0.0
	_check(not charge.toggle(victim) and victim.is_afterburner_mode_active(), "E 和空电池不取消强制窗口")
	victim.set_afterburner_mode_active(true)
	victim._evasion_overstock_timer = 2.0
	victim.set_afterburner_mode_active(false)
	_check(is_equal_approx(victim._evasion_overstock_timer, 2.0), "来源重叠不重置有效加力计时")
	_check(FearResponse.obscure(emitter), "操控机恐惧遮住敌机信息")
	AircraftRenderer.player_ref = immune
	_check(not FearResponse.obscure(emitter) and FearResponse.obscure(victim), "切控正常机只保留原机遮蔽")
	AircraftRenderer.player_ref = victim
	if visual:
		await _visual(root, world, cone, victim, immune)
	# 真实伤害 + queue_free 后跨过消费者采样，不能解引用来源。
	var destroyed_signal := [0]
	var on_kill := func(_killer: String, victim_name: String, _kind: String, _kt: int, _vt: int, _voiced: bool):
		if victim_name == "SOURCE": destroyed_signal[0] += 1
	EventLogger.kill_recorded.connect(on_kill)
	emitter.take_damage(10000.0, victim, "missile")
	EventLogger.kill_recorded.disconnect(on_kill)
	_check(emitter.is_destroyed and destroyed_signal[0] == 1, "来源真实死亡与 signal")
	emitter.queue_free()
	await root.get_tree().process_frame
	cone.update(0.1)
	victim.fear_response.update(victim, 0.2)
	victim._resolve_intents(0.1)
	_check(victim.fear_response.source_ref == null and victim.target_position.x > victim.position.x,
		"来源释放后快照逃逸且消费者执行到末尾")
	_check(cone.emitter() == null and cone.exposure.is_empty(), "来源终态清空锥与累计")
	victim.set_afterburner_mode_active(true)
	victim.remove_status(StatusEffects.FEAR)
	victim.fear_response.update(victim, 0.1)
	_check(not FearResponse.controlled(victim) and victim.is_afterburner_mode_active(), "解恐惧不取消正常加力来源")
	victim.set_afterburner_mode_active(false)
	_check(not victim.is_afterburner_mode_active(), "两种来源全部退出后窗口关闭")
	_check(not FearResponse.apply(victim, source2), "解控保护拒绝再次恐惧")
	victim.fear_response.update(victim, 3.0)
	_check(FearResponse.apply(victim, source2), "保护结束可以被新来源恐惧")
	victim.take_damage(10000.0, source2, "missile")
	_check(not victim.fear_response.active and victim.fear_response.source_ref == null \
		and not victim.is_afterburner_mode_active(), "受害者真实死亡清空来源与加力")
	var cfg2 := SquadFearConeConfig.new()
	cfg2.range_m = 100.0
	var host2 := Host.new()
	host2.members = [source2]
	host2.targets = [immune]
	var cone2 := SquadFearConeController.new()
	cone2.setup(cfg2, host2)
	cone2.start()
	cone.dispose()
	_check(cone2.phase == SquadFearConeController.Phase.WAIT and cone2.config.range_m == 100.0,
		"不同小队配置/状态/卸载互相隔离")
	cone2.dispose()
	await _flight_and_edges(root, world, player)
	player.free()
	world.queue_free()
	await root.get_tree().process_frame
	AircraftRenderer.player_ref = old_player if is_instance_valid(old_player) else null
	_check(SquadFearConeController.live_controllers().is_empty(), "退出无残留能力登记")
	print("[FearCone] pass=%d fail=%d" % [_pass, _fail])
	return _fail

func _flight_and_edges(root: Node, world: Node2D, player: SurvivorPlayer) -> void:
	var source := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2.ZERO, "FLIGHT_SOURCE")
	var ac := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(600, 0), "FLIGHT")
	var cfg := SquadFearConeConfig.new()
	var host := Host.new()
	host.members = [source]
	host.targets = [ac]
	var cone := SquadFearConeController.new()
	cone.setup(cfg, host)
	ac.position = Vector2(750, -1299.038)
	_check(cone.contains(source, ac), "3000m/30度外边界计入")
	ac.position = Vector2(751, -1299.038)
	_check(not cone.contains(source, ac), "角度或距离越界不命中")
	ac.position = Vector2(0, -600)
	ac.altitude = 10000.0
	_check(cone.contains(source, ac), "虚拟高度不改变平面命中")
	ac.no_pilot = true
	_check(not FearResponse.apply(ac, source), "无人驾驶拒绝恐惧")
	ac.no_pilot = false
	ac.set_meta(&"fear_immune", true)
	_check(not FearResponse.apply(ac, source), "心理免疫拒绝恐惧")
	ac.remove_meta(&"fear_immune")
	cone.start()
	cone.debug_cast()
	cone.update(1.0)
	for i in range(19): cone.update(0.1)
	player.apply_upgrade_to(ac, SurvivorData.upgrade_by_id("sig_gripen_e"))
	cone.update(0.1)
	_check(not ac.has_status(StatusEffects.FEAR) and cone.exposure.is_empty(), "累计中正式授予免疫立即清空且不施控")
	# 审计真实 F4 控件与回调，普通状态按钮也必须走带来源入口。
	var debug := SurvivorDebugSkills.new()
	debug._content = VBoxContainer.new()
	debug.add_child(debug._content)
	debug._build_fear_controls()
	debug._refresh_fear_choices()
	for index in range(debug._fear_target_choice.item_count):
		if debug._fear_target_choice.get_item_metadata(index) == ac.get_instance_id():
			debug._fear_target_choice.select(index)
	for index in range(debug._fear_source_choice.item_count):
		if debug._fear_source_choice.get_item_metadata(index) == source.get_instance_id():
			debug._fear_source_choice.select(index)
	_check(debug._content.get_child(0).get_child_count() == 5, "F4 来源/目标与三种动作均可达")
	debug._on_apply_status(StatusEffects.FEAR)
	_check(not ac.has_status(StatusEffects.FEAR) and ac.fear_response == null, "F4 正式状态入口仍尊重免疫")
	debug.free()
	_check(cone.emitter() == source, "施放者登记有效")
	cone = null
	_check(not source.has_meta(&"fear_cone_emitting"), "宿主卸载控制器时释放可见性占用")
	var flyer := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(600, 0), "PHYSICS")
	flyer.heading = 0.0
	flyer.auto_engage_enabled = false
	_check(FearResponse.apply(flyer, source), "无 AIController 飞机接受恐惧")
	var start := flyer.position
	for i in range(120):
		flyer.hard_brake = true
		flyer._physics_process(1.0 / 60.0)
	_check(flyer.position.distance_to(source.position) > start.distance_to(source.position) \
		and flyer.heading > 0.05 and flyer.heading < PI, "真实物理滚转朝远离侧转弯并拉开距离")
	_check(flyer.is_afterburner and not flyer.hard_brake, "真实物理持续加力且急刹不覆盖")
	var last_source := flyer.fear_response.source_position
	source.team = CombatUnit.TEAM_PLAYER
	source.position = Vector2(3000, 0)
	flyer.fear_response.update(flyer, 0.1)
	_check(flyer.fear_response.source_ref == null and flyer.fear_response.source_position == last_source,
		"来源变阵营冻结末次合法位置")
	for i in range(190): flyer._physics_process(1.0 / 60.0)
	_check(not FearResponse.controlled(flyer) and not flyer.is_afterburner_mode_active() \
		and flyer.fear_response.protection_s > 2.5, "真实物理满五秒退出加力并恢复控制")
	_check(not flyer._intent_slots.has(ControlIntent.SOURCE_FEAR), "到期撤销最高优先级控制意图")
	var edge := Vector2(MapBoundary.world_half_px() - 310.0, 0)
	var escape := FearResponse.escape_point(edge, edge - Vector2(600, 0), Vector2.RIGHT)
	_check(MapBoundary.is_safe_inside(escape, 299.0) and absf(escape.y) > 100.0,
		"边界附近沿边逃逸而非顶墙")
	await root.get_tree().process_frame

func _visual(root: Node, world: Node2D, cone: SquadFearConeController, victim: Aircraft, immune: Aircraft) -> void:
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(0, -550)
	camera.zoom = Vector2(0.55, 0.55)
	camera.make_current()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var overlay := WorldUnitStatusOverlay.new()
	layer.add_child(overlay)
	var panel := PlayerInstrumentPanel.new()
	layer.add_child(panel)
	panel.update_display(victim, AfterburnerCharge.new())
	panel.position = Vector2(root.get_viewport().get_visible_rect().size.x - panel.size.x - 24.0, 100)
	# 恐惧快照里保持锥的来源可见，使用正式绘制与面板。
	cone.emitter().position = Vector2.ZERO
	victim.queue_redraw()
	immune.queue_redraw()
	await root.get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/map_visual_qa/fear")
	root.get_viewport().get_texture().get_image().save_png("res://tmp/map_visual_qa/fear/feared.png")
	AircraftRenderer.player_ref = immune
	panel.update_display(immune, AfterburnerCharge.new())
	await root.get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://tmp/map_visual_qa/fear/immune.png")
	AircraftRenderer.player_ref = victim
	cone.emitter().position = Vector2(-600, -600)

func _aircraft(world: Node2D, team: int, pos: Vector2, callsign: String) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = load("res://resources/default_fighter.tres").duplicate(true)
	ac.params.armor = 0.0
	ac.team = team
	ac.position = pos
	ac.callsign = callsign
	world.add_child(ac)
	ac.set_physics_process(false)
	ac.speed = 180.0
	ac.altitude = 5500.0
	ac.target_altitude = 5500.0
	ac.hp = 100.0
	return ac

func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[FearCone] %s %s" % ["PASS" if ok else "FAIL", label])
