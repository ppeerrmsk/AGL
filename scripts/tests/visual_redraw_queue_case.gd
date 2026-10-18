extends RefCounted
const Redraw := preload("res://scripts/rendering/visual_redraw_queue.gd")

class CounterCanvas:
	extends Node2D
	var coalesced := true
	var state := 0
	var counts: Dictionary = {}
	var physics_states: Dictionary = {}
	var process_states: Dictionary = {}
	var drawn_states: Dictionary = {}
	func _physics_process(_delta: float) -> void:
		state += 1
		physics_states[Engine.get_process_frames()] = state
		if coalesced:
			Redraw.request(self)
			Redraw.request(self)
		else:
			queue_redraw()
	func _process(_delta: float) -> void:
		process_states[Engine.get_process_frames()] = state
	func _draw() -> void:
		var frame := Engine.get_process_frames()
		counts[frame] = int(counts.get(frame, 0)) + 1
		drawn_states[frame] = state
		draw_rect(Rect2(0, 0, 8, 8), Color.WHITE)

class DrawProbe:
	extends RefCounted
	var label := ""
	var subject: WeakRef
	var properties := PackedStringArray()
	var counts: Dictionary = {}
	var physics_states: Dictionary = {}
	var drawn_states: Dictionary = {}
	func snapshot() -> Array:
		var item: Variant = subject.get_ref()
		if typeof(item) != TYPE_OBJECT or not is_instance_valid(item):
			return []
		var values: Array = []
		for property: String in properties:
			values.append(item.get(property))
		return values.duplicate(true)
	func record_physics() -> void:
		physics_states[Engine.get_process_frames()] = snapshot()
	func record() -> void:
		var frame := Engine.get_process_frames()
		counts[frame] = int(counts.get(frame, 0)) + 1
		# CanvasItem在调用脚本_draw前同步发出draw信号；记录其将要消费的真实字段。
		drawn_states[frame] = snapshot()

class PhysicsStateSampler:
	extends Node
	var probes: Array[DrawProbe] = []
	func _physics_process(_delta: float) -> void:
		for probe in probes:
			probe.record_physics()

class LifecycleCanvas:
	extends Node2D
	var state := 0
	var drawn_states: Array[int] = []
	func _draw() -> void:
		drawn_states.append(state)
		draw_rect(Rect2(0, 0, 8, 8), Color.WHITE)

class LifecycleActions:
	extends Node
	var victims: Array[WeakRef] = []
	var calls := 0
	func _physics_process(_delta: float) -> void:
		for index in victims.size():
			var item: Variant = victims[index].get_ref()
			if typeof(item) != TYPE_OBJECT or not is_instance_valid(item):
				continue
			item.drawn_states.clear()
			item.state = index + 1
			Redraw.request(item)
			match index:
				0: item.free()
				1: item.queue_free()
				2: item.get_parent().remove_child(item)
				3:
					var host: Node = item.get_parent()
					host.remove_child(item)
					host.add_child(item)
					item.state = 103
					Redraw.request(item)
				4:
					item.process_mode = Node.PROCESS_MODE_DISABLED
					item.state = 104
			calls += 1
		set_physics_process(false)

class MountLockDriver:
	extends Node
	var proxy: WeakRef
	var ticks := 0
	func _physics_process(_delta: float) -> void:
		var value: Variant = proxy.get_ref() if proxy != null else null
		if typeof(value) != TYPE_OBJECT or not is_instance_valid(value) or not value is MountTarget:
			return
		ticks += 1
		value.incoming_lock_progress = float(ticks % 50 + 1) / 52.0


static func run(parent: Node) -> int:
	var original_cap := Engine.max_fps
	# 限帧仅用于强制补步和验证调度合同，不作为任何性能样本。
	var failures := await _test_frame_contract(parent, 20)
	failures += await _test_frame_contract(parent, 120)
	Engine.max_fps = 20
	failures += await _test_real_callers(parent)
	failures += await _test_lifecycle(parent)
	Engine.max_fps = original_cap
	for n in 2:
		await parent.get_tree().process_frame
	print("[VisualRedraw] all_cases fail=", failures)
	return failures


static func _test_frame_contract(parent: Node, cap: int) -> int:
	Engine.max_fps = cap
	var legacy := CounterCanvas.new()
	legacy.coalesced = false
	var candidate := CounterCanvas.new()
	parent.add_child(legacy)
	parent.add_child(candidate)
	var first_frame := Engine.get_process_frames() + 3
	for n in 18:
		await parent.get_tree().process_frame
	# 当前 process_frame 的 _process/_draw 尚未结束；只检查已完整结束的帧。
	var end_frame := Engine.get_process_frames()
	legacy.set_physics_process(false)
	candidate.set_physics_process(false)
	for n in 2:
		await parent.get_tree().process_frame
	var failures := int(legacy.state != candidate.state or candidate.state <= 0)
	var visual := DisplayServer.get_name() != "headless"
	var checked := 0
	var legacy_peak := 0
	var candidate_peak := 0
	if visual:
		for frame in range(first_frame, end_frame):
			# 不再以 has(frame) 跳过未观察到的阶段：缺 _process、缺该画的帧均失败。
			if not candidate.process_states.has(frame):
				failures += 1
				continue
			var draws := int(candidate.counts.get(frame, 0))
			candidate_peak = maxi(candidate_peak, draws)
			legacy_peak = maxi(legacy_peak, int(legacy.counts.get(frame, 0)))
			failures += int(draws > 1)
			if candidate.physics_states.has(frame):
				failures += int(draws != 1)
				failures += int(candidate.process_states[frame] != candidate.physics_states[frame])
			if draws > 0:
				failures += int(candidate.drawn_states.get(frame, -1) != candidate.process_states[frame])
				# process_frame 的回调可早于 _process 绘制；等帧结束后比较，证明
				# 消费的是本次补步的最终物理状态，而非依赖回调先后跳过检查。
			checked += 1
		failures += int(checked < 10 or candidate_peak != 1)
		if cap == 20:
			failures += int(legacy_peak < 2)
	print("[VisualRedraw] cap=", cap, " visual=", visual, " states=", candidate.state,
		" checked=", checked, " legacy_peak=", legacy_peak, " candidate_peak=", candidate_peak,
		" fail=", failures)
	legacy.queue_free()
	candidate.queue_free()
	for n in 2:
		await parent.get_tree().process_frame
	return failures


static func _observe(item: CanvasItem, label: String, probes: Array[DrawProbe]) -> void:
	var probe := DrawProbe.new()
	probe.label = label
	probe.subject = weakref(item)
	# 采实际绘制消费的权威字段，不用DrawProbe自己的计数冒充actor状态。
	probe.properties = PackedStringArray(["global_transform"])
	if item is CombatUnit:
		probe.properties.append_array(PackedStringArray(["heading", "is_destroyed", "incoming_lock_progress", "is_locked"]))
	if item is GroundUnit:
		probe.properties.append_array(PackedStringArray(["hp", "_destroy_timer"]))
	if item is Aircraft:
		probe.properties.append_array(PackedStringArray(["speed", "bank_angle", "_lod_frame"]))
	if item is RadarStation:
		probe.properties.append("_dish_rotation")
	if item is AAGunUnit:
		probe.properties.append("turret_heading")
	if item is NavalUnit:
		probe.properties.append_array(PackedStringArray(["hull_hp", "_weak_pulse_time", "_destroy_timer"]))
	if item is Missile:
		probe.properties.append_array(PackedStringArray(["age", "heading", "bank_angle", "is_active"]))
	if item is ArmoredTrainUnit:
		probe.properties.append("speed")
	item.draw.connect(probe.record)
	probes.append(probe)


static func _test_real_callers(parent: Node) -> int:
	var host := Node2D.new()
	parent.add_child(host)
	var probes: Array[DrawProbe] = []
	# 真实覆写 _physics_process 的地面类，不能用基类或 CounterCanvas 代替接线证据。
	var ground: Array[GroundUnit] = [GroundUnit.new(), AAGunUnit.new(), AirburstAAUnit.new(),
		SAMUnit.new(), RadarStation.new(), ArmoredTrainSegment.new(), Tier3SuperCannonPart.new()]
	var names := ["ground", "aa", "airburst", "sam", "radar", "train_segment", "super_cannon"]
	for index in ground.size():
		var unit := ground[index]
		unit.params = AircraftParams.new()
		unit.params.display_name = "REDRAW QA"
		unit.params.max_hp = 100.0
		unit.position = Vector2(120 + index * 60, 200)
		unit.is_hovered = true
		_observe(unit, names[index], probes)
		host.add_child(unit)
	var radar := ground[4] as RadarStation
	var initial_dish := radar._dish_rotation
	var ciws := Tier3SiegeCIWS.new()
	ciws.params = AircraftParams.new()
	ciws.configure(ground[0], Vector2(30, 0))
	_observe(ciws, "ciws", probes)
	host.add_child(ciws)

	var leader := Aircraft.new()
	leader.params = preload("res://resources/default_fighter.tres").duplicate(true)
	leader.callsign = "REDRAW LEADER"
	host.add_child(leader)
	leader.set_physics_process(false)
	var wingman := Aircraft.new()
	wingman.params = leader.params.duplicate(true)
	wingman.callsign = "REDRAW WINGMAN"
	wingman.position = Vector2(200, 300)
	wingman.selected = true
	_observe(wingman, "formation", probes)
	host.add_child(wingman)
	wingman.set_formation_target(leader, Vector2(120, -240), false)

	var ship := NavalUnit.new()
	ship.params = NavalParams.new()
	ship.params.weak_point_enabled = false
	ship.is_hovered = true
	ship.position = Vector2(500, 200)
	_observe(ship, "naval", probes)
	host.add_child(ship)
	# 舰船默认远距门仍保留；这里只要求发生过重绘且同帧不重复。
	var missile := Missile.new()
	missile.params = MissileParams.new()
	missile.params.max_lifetime = 30.0
	missile.params.motor_burn_time = 30.0
	missile.position = Vector2(600, 400)
	_observe(missile, "missile", probes)
	host.add_child(missile)

	var target := StrategicTarget.new()
	target.params = AircraftParams.new()
	target.params.max_hp = 100.0
	target.position = Vector2(700, 200)
	_observe(target, "strategic_destroyed", probes)
	host.add_child(target)
	target.take_bomber_damage(1000.0, CombatUnit.TEAM_HOSTILE)

	var driver := MountLockDriver.new()
	driver.process_physics_priority = -100
	var proxy := MountTarget.new()
	proxy.parent_ship = ship
	driver.proxy = weakref(proxy)
	host.add_child(driver)
	_observe(proxy, "mount_lock", probes)
	host.add_child(proxy)
	var train := ArmoredTrainUnit.new()
	_observe(train, "train_controller", probes)
	host.add_child(train)
	var sampler := PhysicsStateSampler.new()
	# 所有真实actor及MountLockDriver完成后记录；补步覆盖同一呈现帧的旧样本。
	sampler.process_physics_priority = 1000000
	sampler.probes = probes
	host.add_child(sampler)
	var first_frame := Engine.get_process_frames() + 3
	for n in 12:
		await parent.get_tree().process_frame
	var end_frame := Engine.get_process_frames()
	var failures := int(wingman._lod_frame < 12 or not wingman.formation_mode)
	failures += int(is_equal_approx(radar._dish_rotation, initial_dish) or missile.age <= 0.0)
	failures += int(not target.is_destroyed or driver.ticks < 12)
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		for probe in probes:
			var peak := 0
			var draws := 0
			for frame in range(first_frame, end_frame):
				var count := int(probe.counts.get(frame, 0))
				peak = maxi(peak, count)
				draws += count
				failures += int(count > 1)
				if probe.label != "naval":
					failures += int(count != 1)
				if count > 0:
					failures += int(not probe.physics_states.has(frame) or not probe.drawn_states.has(frame) \
						or probe.drawn_states.get(frame) != probe.physics_states.get(frame))
			failures += int(draws < 3)
			print("[VisualRedraw] actor=", probe.label, " peak=", peak, " draws=", draws)
	print("[VisualRedraw] real_callers visual=", visual, " fail=", failures)
	host.queue_free()
	for n in 3:
		await parent.get_tree().process_frame
	return failures


static func _test_lifecycle(parent: Node) -> int:
	var actions := LifecycleActions.new()
	for n in 5:
		var victim := LifecycleCanvas.new()
		parent.add_child(victim)
		actions.victims.append(weakref(victim))
	parent.add_child(actions)
	for n in 4:
		await parent.get_tree().process_frame
	var failures := int(actions.calls != 5 or not Redraw._pending.is_empty())
	failures += int(actions.victims[0].get_ref() != null or actions.victims[1].get_ref() != null)
	for index in range(2, 5):
		var item: Variant = actions.victims[index].get_ref()
		if typeof(item) != TYPE_OBJECT or not is_instance_valid(item):
			failures += 1
			continue
		failures += int(item.is_inside_tree() != (index != 2))
		if DisplayServer.get_name() != "headless":
			if index == 2:
				failures += int(not item.drawn_states.is_empty())
			else:
				# 重入或禁用发生在请求之后；首个真实_draw也必须看见最终状态。
				failures += int(item.drawn_states.is_empty())
				for observed: int in item.drawn_states:
					failures += int(observed != 100 + index)
		if index == 4:
			failures += int(item.process_mode != Node.PROCESS_MODE_DISABLED)
		item.free()
	actions.queue_free()
	for n in 2:
		await parent.get_tree().process_frame
	failures += int(not Redraw._pending.is_empty())
	print("[VisualRedraw] lifecycle fail=", failures)
	return failures
