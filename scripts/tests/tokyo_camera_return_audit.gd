extends RefCounted
## 正常输入复现：缩远/拉近、持续移开、SPACE 恢复跟随；不直接改镜头。
var cases: Array[Dictionary]=[]
var held: Array[int]=[]
var departure: Array[int]=[]
var departure_paused := false
var departure_resumes := 0
var phase := -1
var active := -1
var wheels := 0
var distance := 0.0
var previous := Vector2.INF
var peak_speed := 0.0
var cycle_ms := 4000
var departure_ms := 2000
var close_range := false
var close_zoom_started := false


static func clamped_position(position: Vector2, bounds: Rect2, half: Vector2) -> Vector2:
	if not bounds.has_area(): return position
	var lower := bounds.position+half
	var upper := bounds.end-half
	for axis in 2:
		if lower[axis]>upper[axis]: lower[axis]=bounds.get_center()[axis];upper[axis]=lower[axis]
	return position.clamp(lower,upper)


static func departure_key(center: Vector2, target: Vector2, bounds: Rect2, size: Vector2, scale: float, preferred: int) -> int:
	# 按最终倍率和地图边界选择能拉开距离的真实WASD方向，避免朝已封死的边界移动。
	# 只选输入方向；不移动镜头/玩家、不跳过失败样本、不放宽原100px起距门。
	var codes: Array[int]=[KEY_D,KEY_W,KEY_A,KEY_S]
	var vectors: Array[Vector2]=[Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN]
	var half := size/(2.0*scale)
	var origin := clamped_position(center,bounds,half)
	var destination := clamped_position(target,bounds,half)
	var best := preferred
	var best_distance := -1.0
	for index in 4:
		var slot := (preferred+index)%4
		var endpoint := clamped_position(origin+vectors[slot]*4000.0/scale,bounds,half)
		var separation := endpoint.distance_squared_to(destination)
		if separation>best_distance:
			best_distance=separation;best=slot
	return codes[best]


static func error_px(battle: Node) -> float:
	var target: Vector2=preload("res://scripts/util/display_pacing.gd").display_origin(battle.player_aircraft)
	var half: Vector2=battle.get_viewport().get_visible_rect().size/(2.0*battle.camera.zoom.x)
	target=clamped_position(target,battle._camera_ctrl._world_bounds,half)
	return target.distance_to(battle.camera.global_position)*battle.camera.zoom.x


func keys(wanted: Array[int]) -> void:
	for code: int in [KEY_W,KEY_A,KEY_S,KEY_D]:
		if (code in held)==(code in wanted): continue
		var event := InputEventKey.new()
		event.keycode=code;event.physical_keycode=code;event.pressed=code in wanted
		Input.parse_input_event(event)
	held=wanted.duplicate()


func wheel_burst(battle: Node, inward: bool, count: int) -> void:
	for index in count:
		var wheel := InputEventMouseButton.new()
		wheel.position=battle.get_viewport().get_visible_rect().size*0.5
		wheel.button_index=MOUSE_BUTTON_WHEEL_UP if inward else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed=true;Input.parse_input_event(wheel)
		wheel=wheel.duplicate();wheel.pressed=false;Input.parse_input_event(wheel);wheels+=1


func step(battle: Node, elapsed: int, input_open: bool) -> void:
	if previous.is_finite(): distance+=previous.distance_to(battle.camera.global_position)
	previous=battle.camera.global_position
	peak_speed=maxf(peak_speed,battle._camera_ctrl._wasd_velocity.length())
	if not input_open:
		departure_paused=departure_paused or not held.is_empty()
		keys([]);return
	if active>=0:
		var row: Dictionary=cases[active]
		var error := error_px(battle)
		row["samples"]=int(row.get("samples",0))+1
		var step_px: float=battle.camera.global_position.distance_to(row.last_camera)*battle.camera.zoom.x
		if row.samples==1: row["first_step_px"]=step_px
		row["max_step_px"]=maxf(float(row.get("max_step_px",0.0)),step_px)
		row["last_camera"]=battle.camera.global_position
		row["last_error_px"]=error
		# 正常 FOLLOW_LERP 自带速度/7 的稳态跟随距离，不应把它误报为地图等待。
		# 只扣除该既有上界；250ms 响应、1500ms 回归及额外20px容差均不放宽。
		row["peak_follow_speed"]=maxf(float(row.peak_follow_speed),float(battle.player_aircraft.speed)*CombatUnit.PIXELS_PER_METER)
		row["tracking_allowance_px"]=float(row.peak_follow_speed)/CameraController.FOLLOW_LERP*battle.camera.zoom.x
		row["excess_error_px"]=maxf(0.0,error-float(row.tracking_allowance_px))
		if row.response_ms<0 and float(row.initial_error_px)-error>=minf(30.0,float(row.initial_error_px)*0.1): row.response_ms=elapsed-int(row.start_ms)
		if row.settled_ms<0 and float(row.excess_error_px)<=20.0:
			row.settled_ms=elapsed-int(row.start_ms);row["settled_samples"]=row.samples
	var next := int(maxi(0,elapsed-1000)/cycle_ms) if elapsed>=1000 else -1
	var phase_ms := (elapsed-1000)%cycle_ms if elapsed>=1000 else -1
	if next!=phase:
		active=-1;phase=next
		var target: Vector2=preload("res://scripts/util/display_pacing.gd").display_origin(battle.player_aircraft)
		var inward := not close_range and phase%2!=0
		var factor := CameraController.ZOOM_IN_FACTOR if inward else CameraController.ZOOM_OUT_FACTOR
		var final_zoom := clampf(float(battle._camera_ctrl.target_zoom)*pow(factor,40 if close_range else 32),CameraController.ZOOM_MIN,CameraController.ZOOM_MAX)
		var direction := departure_key(battle.camera.global_position,target,battle._camera_ctrl._world_bounds,
			battle.get_viewport().get_visible_rect().size,final_zoom,phase%4)
		departure.assign([direction])
		departure_paused=false
		close_zoom_started=false
		wheel_burst(battle,inward,40 if close_range else 32)
	if close_range and phase>=0 and phase_ms>=4000 and not close_zoom_started:
		close_zoom_started=true
		wheel_burst(battle,true,40)
	# 模态关闭输入只释放实际按键；恢复后继续同一段拉远，不能等下一阶段才重按。
	if phase>=0 and phase_ms<departure_ms and active<0:
		departure_resumes+=int(departure_paused)
		departure_paused=false
		keys(departure)
	if phase>=0 and phase_ms>=departure_ms and active<0:
		keys([])
		cases.append({"phase":phase,"start_ms":elapsed,"zoom":battle.camera.zoom.x,
			"initial_error_px":error_px(battle),"last_error_px":error_px(battle),"response_ms":-1,"settled_ms":-1,
			"peak_follow_speed":float(battle.player_aircraft.speed)*CombatUnit.PIXELS_PER_METER,
			"last_camera":battle.camera.global_position,"samples":0})
		active=cases.size()-1
		var space := InputEventKey.new()
		space.keycode=KEY_SPACE;space.physical_keycode=KEY_SPACE;space.pressed=true;Input.parse_input_event(space)
		space=space.duplicate();space.pressed=false;Input.parse_input_event(space)


func finish() -> Dictionary:
	keys([])
	var failures := int(cases.size()<6 or distance<1000.0 or peak_speed<2300.0)
	for row: Dictionary in cases:
		failures+=int(float(row.initial_error_px)<100.0 or int(row.response_ms)<0 or int(row.response_ms)>250 \
			or int(row.settled_ms)<0 or int(row.settled_ms)>1500)
		if close_range:
			failures+=int(float(row.zoom)<4.95 or float(row.initial_error_px)<2000.0)
			if OS.get_environment("AGL_TOKYO_DIRECT_RETURN")=="1":
				failures+=int(int(row.settled_ms)>50 or int(row.get("settled_samples",999))>2)
	return {"fail":failures,"cases":cases,"distance":distance,"peak_speed":peak_speed,"wheel_events":wheels,"departure_resumes":departure_resumes,
		"first_response_limit_ms":250,"settle_limit_ms":1500,"settle_error_px":20,"departure_ms":departure_ms,"cycle_ms":cycle_ms,"close_range":close_range}
