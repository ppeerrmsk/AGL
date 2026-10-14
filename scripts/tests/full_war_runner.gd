extends Node
## 真实场景入口、队伍切换、派遣、伤害/退出生命周期；Visual额外采集墙钟帧。
const ModeScene := preload("res://scenes/full_war_test.tscn")
const ClockScript := preload("res://scripts/tests/map_frame_clock.gd")
var _fail := 0
var _checks := 0
var _clock := ClockScript.new()
var _sample := false
var auto_run := true

func _process(_delta: float) -> void:
	_clock.observe(_sample)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if auto_run:
		call_deferred("_run")

func _run() -> void:
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		await _run_profile(String(get_tree().get_meta("bench_scenario", "")))
		return
	await run_checks()
	get_tree().quit(0 if _fail == 0 else 1)

func run_checks() -> int:
	await _capacity_case()
	var renderer := BuildingRenderer.new()
	var zoom := Vector2.ONE * 0.13
	var extent := Vector2(1600, 900)
	renderer.consume_view_change(Vector2.ZERO, zoom, extent)
	_check("默认建筑重绘门保持4px", renderer.consume_view_change(Vector2(5, 0), zoom, extent))
	renderer.redraw_roof_error_px = 0.5
	_check("亚像素楼顶变化复用几何", not renderer.consume_view_change(Vector2(35, 0), zoom, extent))
	_check("超过误差界立即重绘", renderer.consume_view_change(Vector2(50, 0), zoom, extent))
	_check("定点缩放立即重绘", renderer.consume_view_change(Vector2(50, 0), zoom * 2.0, extent))
	renderer.free()
	var mode = ModeScene.instantiate()
	add_child(mode)
	await get_tree().process_frame
	_check("第二队留在后备库", mode.ace_squads.size() == 2 and mode.ace_squads[0].members.size() == 4 and mode.ace_squads[1] == null)
	_check("14单位开局且只有4友军", mode.war.living_units().size() == 14 and mode.war.live_count(0) == 4)
	_check("未部署不可接管", not mode.switch_ace(1))
	_check("测试不入生涯", not mode.archive_enabled())
	var primary: Aircraft = mode.player_aircraft
	var damage: float = primary.params.gun.bullet_damage
	mode.command_panel.open()
	mode.command_panel.selected_sector = 2
	mode.command_panel._ace_button.pressed.emit()
	_check("点击派遣才占后备名额", mode.war.stock.ace == 0 and mode.war.orders.size() == 1 and mode.ace_squads[1] == null)
	await get_tree().create_timer(6.5).timeout
	_check("王牌准备后实体入场", mode.ace_squads[1] != null and mode.ace_squads[1].members.size() == 4)
	var dispatched: Aircraft = mode.ace_squads[1].leader
	_check("增援从后方自行飞向任务区", dispatched.global_position.y > 6400 and mode._get_ai(dispatched).waypoints[0].distance_to(mode.SECTORS[2]) < 600)
	var origin := dispatched.global_position
	await get_tree().create_timer(0.7).timeout
	_check("增援实际向前飞行", dispatched.global_position.y < origin.y - 10.0)
	_check("不能重复购买王牌队", not mode.war.request("ace", 1))
	_check("切第二队", mode.switch_ace(1) and mode.player_aircraft != primary)
	_check("原队恢复AI且强化保留", not mode._get_ai(primary).manual_control and is_equal_approx(primary.params.gun.bullet_damage, damage))
	_check("切回第一队", mode.switch_ace(0) and mode.player_aircraft == primary)
	mode.command_panel.open()
	var time_before: float = mode.war.elapsed
	await get_tree().create_timer(0.7).timeout
	_check("Tab不暂停时间", not get_tree().paused and mode.war.elapsed > time_before)
	mode.command_panel.close()
	var supply_before: float = mode.war.supply
	_check("下达订单", mode.war.request("fighter", 0))
	var request_id: int = mode.war.orders[0].id
	_check("订单取消全额退款", mode.war.cancel(request_id) and is_equal_approx(mode.war.supply, supply_before) and mode.war.stock.fighter == 4)
	mode.war.supply = 0
	_check("资源不足拒绝", not mode.war.request("frigate", 1))
	mode.war.supply = 240
	_check("双订单", mode.war.request("strike", 2) and mode.war.request("strike", 0))
	_check("队列上限", not mode.war.request("strike", 1))
	var serial: int = mode._unit_serial
	await get_tree().create_timer(6.5).timeout
	_check("准备完成真实入场", mode._unit_serial >= serial + 2 and mode.war.orders.is_empty())
	var enemy: CombatUnit = null
	for unit: CombatUnit in mode.war.living_units():
		if unit is GroundUnit and unit.team == CombatUnit.TEAM_HOSTILE:
			enemy = unit
			break
	if enemy != null:
		var losses_before: int = mode.war.losses[1]
		enemy.take_damage(100000.0, primary, "test")
		await get_tree().create_timer(0.7).timeout
		_check("真实伤害只计一次损失", mode.war.losses[1] > losses_before)
	else:
		_check("敌方岸基单位存在", false)
	var population: int = mode.peak_population
	var missiles: int = mode.peak_missiles
	# 正式受击入口验证玩家死亡立即失败，非只设is_destroyed。
	if mode.war.active:
		mode.player_aircraft.survivor_bullet_damage_cap = 0.0
		mode.player_aircraft.survivor_missile_damage_cap = 0.0
		mode.player_aircraft.take_damage(100000.0, null, "test")
		await get_tree().create_timer(0.7).timeout
	_check("玩家阵亡终态", not mode.war.active and not mode.war.victory and mode.is_game_over)
	mode.war.finish(true)
	_check("终态互斥", not mode.war.victory and not mode.war.request("fighter", 0))
	mode.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	var second = ModeScene.instantiate()
	add_child(second)
	await get_tree().process_frame
	_check("退出再进清空战局", second.war.active and second.war.losses == [0, 0] and second.war.orders.is_empty())
	second.war.points[1] = 0.0
	await get_tree().create_timer(0.7).timeout
	_check("敌军耗尽胜利", second.war.victory and second.is_game_over)
	second.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	var report: Dictionary = _clock.report()
	var summary := "full_war checks=%d failed=%d peak_units=%d peak_missiles=%d\nwall_clock=%s\n" % [_checks, _fail, population, missiles, str(report)]
	print(summary)
	var output := FileAccess.open("res://bench/results/full_war_focused_latest.txt", FileAccess.WRITE)
	if output != null:
		output.store_string(summary)
	return _fail

func _capacity_case() -> void:
	var ledger := preload("res://scripts/rts/war_ledger.gd").new()
	var units: Array[CombatUnit] = []
	var neutral: Array[int] = [-1, -1, -1]
	var arrivals: Array[int] = []
	ledger.dispatched.connect(func(_kind, _sector, id): arrivals.append(id))
	for i in range(12):
		var unit := CombatUnit.new()
		unit.team = CombatUnit.TEAM_ALLY
		add_child(unit)
		units.append(unit)
		ledger.register_unit(unit, 0, 4.0)
	_check("满员仍可准备增援", ledger.request("fighter", 0))
	ledger.tick(6.5, neutral)
	_check("己方满员不能挤占敌方空位", arrivals.is_empty() and ledger.orders.size() == 1 and ledger.orders[0].remaining == 0.0)
	for i in range(4):
		units[i].take_damage(1000, null, "test")
		units[i].queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	ledger.tick(0.6, neutral)
	_check("真实损失释放容量并只到场一次", arrivals.size() == 1 and ledger.orders.is_empty() and ledger.losses[0] == 4 and ledger.records.size() == 8)
	ledger.tick(0.6, neutral)
	_check("后续tick不重复派遣或扣损", arrivals.size() == 1 and ledger.losses[0] == 4)
	for i in range(4, units.size()):
		units[i].queue_free()
	await get_tree().process_frame
	ledger.shutdown()

func _run_profile(scenario: String) -> void:
	seed(1042026)
	var mode = ModeScene.instantiate()
	var start := Time.get_ticks_usec()
	add_child(mode)
	var setup_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var legacy := scenario == "full_war_baseline"
	if legacy:
		# 仅对照夹具恢复旧44单位；正式入口永远不调用此编成。
		mode._building_renderer.cache_shadow_geometry = false
		mode._building_renderer.redraw_roof_error_px = 0.0
		mode._deploy_second_ace(2)
		for lane in range(3):
			mode._spawn_air(false, lane, 4)
		mode._spawn_air(true, 0, 4, 660.0)
		mode._spawn_air(true, 1, 4, 220.0)
		for side in range(2):
			mode._spawn_ship(side, 1, true)
			mode._spawn_ship(side, 2, false)
		mode._spawn_ground(0, 0)
		mode._spawn_ground(0, 2)
	var starting_units: int = mode.war.living_units().size()
	await get_tree().create_timer(3.0).timeout
	PerfBuckets.configure_frame_trace(true)
	_sample = true
	await get_tree().create_timer(12.0).timeout
	_sample = false
	var opening := _clock.report()
	var opening_trace := PerfBuckets.format_frame_trace_dump()
	PerfBuckets.configure_frame_trace(false)
	_clock = ClockScript.new()
	PerfBuckets.configure_frame_trace(true)
	_sample = true
	if not legacy:
		mode.command_panel.open()
		mode.command_panel.selected_sector = 1
		mode.command_panel._ace_button.pressed.emit()
		(mode.command_panel._order_buttons.fighter as Button).pressed.emit()
		_check("实际点击派遣两支部队", mode.war.orders.size() == 2)
		mode.command_panel.close()
	await get_tree().create_timer(14.0).timeout
	_sample = false
	var combat := _clock.report()
	var combat_trace := PerfBuckets.format_frame_trace_dump()
	PerfBuckets.configure_frame_trace(false)
	_clock = ClockScript.new()
	PerfBuckets.configure_frame_trace(true)
	_sample = true
	mode.command_panel.open()
	await get_tree().create_timer(10.0).timeout
	_sample = false
	var panel := _clock.report()
	var details := PerfBuckets.format_frame_trace_dump()
	PerfBuckets.configure_frame_trace(false)
	await _capture("full_war_command_latest.png")
	mode.command_panel.close()
	await _capture("full_war_battle_latest.png")
	var summary := "scenario=%s setup_ms=%.2f starting_units=%d peak_units=%d peak_missiles=%d active=%s\nopening=%s\ncombat=%s\npanel=%s\nOPENING\n%s\nCOMBAT\n%s\nPANEL\n%s" % [
		scenario, setup_ms, starting_units, mode.peak_population, mode.peak_missiles, str(mode.war.active), str(opening), str(combat), str(panel), opening_trace, combat_trace, details]
	var output := FileAccess.open("res://bench/results/%s_latest.txt" % scenario, FileAccess.WRITE)
	if output != null:
		output.store_string(summary)
	print(summary)
	_check("保持真实交战", mode.peak_missiles > 0)
	if not legacy:
		_check("派遣后仍在交战且达到负载", mode.war.active and mode.peak_population >= 20 and mode.peak_population <= mode.LedgerScript.LIVE_CAP)
	mode.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	get_tree().quit(0 if _fail == 0 and bool(opening.passed) and bool(combat.passed) and bool(panel.passed) else 1)

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	if frame != null:
		frame.save_png("res://bench/results/" + filename)

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_fail += 1
	print("[full_war] %s %s" % ["PASS" if passed else "FAIL", label])
