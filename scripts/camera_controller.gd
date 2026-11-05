class_name CameraController
extends Node

## 共享相机操控：缩放/平移/hover/坐标转换
## 沙盒和生存模式共用核心操控逻辑。
## 用法：
##   var cam_ctrl := CameraController.new()
##   add_child(cam_ctrl)
##   cam_ctrl.setup(camera)
##   cam_ctrl.set_world_bounds(Rect2(...))  # 可选：开启相机位置钳制

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")
const ZOOM_MIN := 0.2       ## 最大缩小倍率（越小视野越大；0.2 ≈ 1920 屏宽下可视 9600 px / 19.2 km，可俯瞰大半张图）
const START_ZOOM := 0.35    ## 开局镜头（比 ZOOM_MIN 略紧，避免开局飞机太小；玩家可滚轮拉到 ZOOM_MIN 看全场）
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const ZOOM_IN_FACTOR := 1.0 + ZOOM_STEP
const ZOOM_OUT_FACTOR := 1.0 / ZOOM_IN_FACTOR  ## 一进一退恢复原倍率，避免反复滚轮逐渐漂离换档边界。
## 连续滚轮仍完整累积目标，显示镜头按比例推进，避免一帧跨越多档地图资格。
const ZOOM_LOG_SPEED := 2.0
## 地图中间机位按最大可行进度先试；每一步仍经完整覆盖与资源就绪检查。
const MAP_MOTION_FRACTIONS := [0.875,0.75,0.625,0.5,0.25,0.125,0.0625]
const HOVER_RADIUS := 30.0  ## 鼠标悬停判定半径（屏幕像素，不随镜头缩放缩水）

# ── WASD 自由镜头参数（屏幕像素/秒，按 zoom 自动换算世界速度）──
const WASD_SPEED_MIN := 450.0   ## 刚按下时的基础速度
const WASD_SPEED_MAX := 2400.0  ## 长按达到的峰值速度
const WASD_RAMP_TIME := 1.2     ## 从 MIN 加速到 MAX 所需秒数
const WASD_ACCEL := 10.0        ## 速度 lerp 平滑率（越大越贴近目标速度 / 越小越有惯性）
const FOLLOW_LERP := 7.0        ## 跟随模式下相机追赶目标的速率

var camera: Camera2D
var target_zoom: float = 1.0

# ── 电影层（表演导演驱动，spec ui-transition §2.6）──
## ⚠ zoom 反馈环：原实现回读 camera.zoom.x 作 lerp 起点。若把 cine_zoom_mult 直接乘进
##   camera.zoom，下一帧回读值已含系数 → 自乘发散。故拆出 _base_zoom 只跟 target_zoom 走，
##   系数在写 camera.zoom 的最后一步才乘。
var _base_zoom: float = 1.0
var cine_zoom_mult: float = 1.0        ## 乘到基础 zoom 上（zoom 越大越推近）
## 镜头偏移写 camera.offset 而【不是】global_position ——
## 后者会被 _clamp_camera_position 钳制并污染跟随逻辑
var cine_offset: Vector2 = Vector2.ZERO
var cine_shake_trauma: float = 0.0
## 演出期间的临时跟随目标（Node2D）。非空时接管 _update_follow，演出结束置 null 即还原
var cine_target: Node2D = null
var cine_follow_lerp: float = 7.0      ## 演出跟随速率（同 FOLLOW_LERP 手感）
var _saved_target_zoom: float = -1.0   ## cut_to 前的玩家 zoom，return_to_player 用
var _player_zoom_prediction := true

const CINE_SHAKE_DECAY := 1.8          ## trauma 每秒衰减
const CINE_SHAKE_MAX_PX := 14.0        ## 位移幅度 = MAX_PX * trauma²（平方使尾部收干净）

## 当前悬停的战斗单位（由父场景通过 update_hover 更新）
var hovered_unit: CombatUnit = null

## 相机位置钳制矩形（世界坐标）。size 为 0 表示不启用（沙盒默认）。
## 开启后相机不会被拖拽/缩放到该矩形外，配合视口半宽保证画面始终落在矩形内。
var _world_bounds: Rect2 = Rect2()

## 跟随目标（Node2D，通常是玩家飞机）
var follow_target: Node2D = null
## 跟随开关：WASD / 中键拖拽会关掉，空格重新打开
var follow_enabled: bool = true

var _wasd_hold_time: float = 0.0
var _wasd_velocity: Vector2 = Vector2.ZERO
var _wasd_direction := Vector2.ZERO
var _map_display_pose: Dictionary = {}
var _map_pending_pan := Vector2.ZERO
var _map_pending_wasd := Vector2.ZERO
var _map_pending_zoom := -1.0
var _return_prefetch := preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_GUARD_PREFETCH")
var _return_hint_target_id := 0
var _return_hint_position := Vector2.ZERO
var distance_return_enabled := preload("res://scripts/rendering/tokyo_installed_map.gd").motion_admission_enabled("AGL_TOKYO_DIRECT_RETURN")
var _return_jump_pending := false
var direct_return_count := 0

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	_map_display_pose={};_map_pending_pan=Vector2.ZERO;_map_pending_wasd=Vector2.ZERO;_map_pending_zoom=-1.0
	_return_jump_pending=false
	# 初始镜头用 START_ZOOM（俯瞰但飞机不至于太小）；上限放宽到 ZOOM_MIN 供玩家拉远看全场
	camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	target_zoom = START_ZOOM
	_base_zoom = START_ZOOM
	camera.set_meta(&"map_prediction_zoom_floor", ZOOM_MIN)

## 启用相机位置钳制（传入世界矩形；生存模式传 MapBoundary.get_world_rect()）
func set_world_bounds(rect: Rect2) -> void:
	_world_bounds = rect

## 每帧调用：平滑缩放 + 电影层叠加 + 位置钳制
## _base_zoom 只跟 target_zoom 走（不回读 camera.zoom，避免与 cine_zoom_mult 形成自乘反馈环）；
## camera.zoom = _base_zoom × cine_zoom_mult。_clamp_camera_position 仍读实际 zoom ——
## 这是对的，钳制应基于真实视野
func update_zoom(delta: float) -> void:
	# 大帧不能让线性权重超过1而越过目标；滚轮突发也不能把绝对倍率差当移动速度。
	_base_zoom = next_zoom(_base_zoom, target_zoom, delta)
	var eff: float = _base_zoom * cine_zoom_mult
	camera.zoom = Vector2(eff, eff)
	# 地图只预测正常操控可达的视野；电影层自行控制倍率时不施加普通滚轮边界。
	var prediction_floor := minf(ZOOM_MIN, minf(target_zoom, _base_zoom)) if cine_zoom_mult == 1.0 and _player_zoom_prediction else 0.0
	if camera.get_meta(&"map_prediction_zoom_floor", 0.0) != prediction_floor:
		camera.set_meta(&"map_prediction_zoom_floor", prediction_floor)
	_update_cine_offset(delta)
	_clamp_camera_position()

## 镜头和纯值预取共用一步缩放；靠近目标时也保留真实减速曲线。
static func next_zoom(current: float, target: float, delta: float) -> float:
	var step := clampf(delta,0.0,1.0/30.0)
	var proposed := lerpf(current,target,1.0-exp(-step*10.0))
	var limit := exp(ZOOM_LOG_SPEED*step)
	return clampf(proposed,current/limit,current*limit)

## 电影层偏移 + 抖动 → camera.offset（不碰 global_position）
func _update_cine_offset(delta: float) -> void:
	var off := cine_offset
	if cine_shake_trauma > 0.0:
		cine_shake_trauma = maxf(cine_shake_trauma - CINE_SHAKE_DECAY * delta, 0.0)
		var amp: float = CINE_SHAKE_MAX_PX * cine_shake_trauma * cine_shake_trauma
		off += Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	camera.offset = off

## 触发一次抖动（trauma 叠加并封顶 1.0）
func cine_shake(amount: float) -> void:
	cine_shake_trauma = clampf(cine_shake_trauma + amount, 0.0, 1.0)

## 演出切镜：瞬移到世界坐标 + 指定 zoom。保存玩家原本的 zoom 供归位
func cine_cut_to(world_pos: Vector2, zoom: float) -> void:
	_player_zoom_prediction = false
	if _saved_target_zoom < 0.0:
		_saved_target_zoom = target_zoom
	cine_target = null
	target_zoom = zoom
	_base_zoom = zoom          # 瞬切不留 lerp 拖尾
	if camera:
		camera.global_position = world_pos
		camera.set_meta(&"map_prediction_zoom_floor", 0.0)
		camera.zoom = Vector2(zoom * cine_zoom_mult, zoom * cine_zoom_mult)
		_clamp_camera_position()

## 演出跟随泵：hard_pause 期间 survivor_mode 的 update() 不跑，导演代泵本函数
## 让镜头持续咬住 cine_target（手感 = 空格跟随，同 FOLLOW_LERP 量级的 lerp）
func cine_follow_tick(delta: float) -> void:
	if camera == null or cine_target == null or not is_instance_valid(cine_target):
		return
	var lt: float = clampf(delta * cine_follow_lerp, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(
		DisplayPacing.display_origin(cine_target), lt)
	_clamp_camera_position()

## 演出收尾：还原玩家 zoom 与跟随。t 为 0..1 进度，用于平滑过渡回去
func cine_return_to_player(t: float) -> void:
	# 归位一开始就停止追演员 —— 此刻演员多半已隐身/散开，镜头不该追着看不见的目标跑
	cine_target = null
	if _saved_target_zoom < 0.0:
		return
	target_zoom = lerpf(target_zoom, _saved_target_zoom, clampf(t, 0.0, 1.0))
	if t >= 1.0:
		_player_zoom_prediction = true
		target_zoom = _saved_target_zoom
		_saved_target_zoom = -1.0
		cine_target = null
		follow_enabled = true

## 电影层归位。演出结束 / 场景切换 / 导演 clear_all 必调
func cine_reset() -> void:
	_player_zoom_prediction = true
	cine_zoom_mult = 1.0
	cine_offset = Vector2.ZERO
	cine_shake_trauma = 0.0
	cine_target = null
	if _saved_target_zoom >= 0.0:
		target_zoom = _saved_target_zoom
		_saved_target_zoom = -1.0
	follow_enabled = true
	if camera:
		camera.offset = Vector2.ZERO

## 每帧综合更新：缩放 + WASD 自由镜头 + 跟随。调用方不需要再单独调 update_zoom。
func update(delta: float) -> void:
	# WASD 只保留短期同向输入；反向或松键立即撤销积压，不能补走几秒前的移动。
	_map_pending_pan-=_map_pending_wasd
	var key_direction := Vector2(float(Input.is_key_pressed(KEY_D))-float(Input.is_key_pressed(KEY_A)),float(Input.is_key_pressed(KEY_S))-float(Input.is_key_pressed(KEY_W))).normalized()
	_map_pending_wasd=key_direction*clampf(_map_pending_wasd.dot(key_direction),0.0,WASD_SPEED_MAX*0.25/maxf(camera.zoom.x,0.001))
	_map_pending_pan+=_map_pending_wasd
	var wasd_backlog := _map_pending_wasd
	_map_pending_wasd=Vector2.ZERO
	var previous := _map_display_pose if not _map_display_pose.is_empty() else {
		"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom}
	var input_position: Vector2=previous.position+_map_pending_pan
	# 等待地图时输入机位仍推进；反向输入立即截断旧方向，不能困在预算无解的交界视野。
	if _map_pending_zoom>0.0:
		_base_zoom=clampf(_map_pending_zoom,minf(previous.base,target_zoom),maxf(previous.base,target_zoom))
	var input_zoom := _base_zoom*cine_zoom_mult
	_map_pending_zoom=-1.0
	camera.global_position+=_map_pending_pan
	_map_pending_pan=Vector2.ZERO
	update_zoom(delta)
	var before_wasd := camera.global_position
	_update_wasd(delta)
	var wasd_step := wasd_backlog+camera.global_position-before_wasd
	_update_follow(delta)
	var jumping := _return_jump_pending and follow_enabled and not is_instance_valid(cine_target)
	var return_ready := true
	var guard_ref: Variant=camera.get_meta(&"map_motion_guard") if camera.has_meta(&"map_motion_guard") else null
	var guard: Variant=guard_ref.get_ref() if guard_ref is WeakRef else null
	if typeof(guard)==TYPE_OBJECT and is_instance_valid(guard) and camera.is_inside_tree():
		camera.force_update_scroll()
		var viewport := camera.get_viewport()
		var logical := viewport.get_visible_rect().size
		var output := Vector2(viewport.size) if viewport is SubViewport else logical*viewport.get_stretch_transform().get_scale()
		var rate := log(camera.zoom.x/maxf(input_zoom,0.001))/maxf(delta,0.001)
		# 中间档只限制本帧实际显示，不能覆盖后台加载使用的完整输入终点。
		var intent := {"position":camera.global_position,"base":_base_zoom,"canvas":viewport.get_canvas_transform()}
		var velocity: Vector2=(camera.global_position-input_position)/maxf(delta,0.001)
		# 远距回中是一次定位，不将空间跳变当作持续扫过地图的速度。
		if jumping: velocity=Vector2.ZERO
		var proposed_scale := viewport.get_canvas_transform().x.length()*output.x/logical.x
		var checkpoint: float=guard.camera_motion_checkpoint(proposed_scale)
		if checkpoint>0.0:
			_base_zoom*=checkpoint/proposed_scale;camera.zoom=Vector2.ONE*(_base_zoom*cine_zoom_mult)
			_clamp_camera_position();camera.force_update_scroll()
		var desired := {"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom,
			"canvas":viewport.get_canvas_transform()}
		var ready: bool=guard.camera_motion_ready(desired.canvas,output,rate,velocity)
		return_ready=ready and checkpoint<=0.0
		if not ready:
			# 联合输入可能一步跨出保护带；先提交仍有完整地图的小步，给逐块交接释放空间。
			var advanced := false
			for fraction: float in MAP_MOTION_FRACTIONS:
				if jumping: break
				camera.global_position=Vector2(previous.position).lerp(desired.position,fraction)
				camera.zoom=Vector2(previous.zoom).lerp(desired.zoom,fraction)
				camera.offset=Vector2(previous.offset).lerp(desired.offset,fraction)
				_base_zoom=lerpf(previous.base,desired.base,fraction)
				_clamp_camera_position();camera.force_update_scroll()
				if guard.camera_motion_ready(viewport.get_canvas_transform(),output,rate,velocity,false):
					advanced=true
					break
			if not advanced:
				camera.global_position=previous.position;camera.zoom=previous.zoom;camera.offset=previous.offset
				_base_zoom=previous.base
				camera.force_update_scroll()
		if not ready or checkpoint>0.0:
			_map_pending_pan=Vector2(intent.position)-camera.global_position
			if wasd_step.length_squared()>0.0:
				var blocked_fraction := clampf(_map_pending_pan.dot(wasd_step)/wasd_step.length_squared(),0.0,1.0)
				_map_pending_wasd=wasd_step*blocked_fraction
			_map_pending_zoom=intent.base
			guard.camera_motion_pending(intent.canvas,output,rate,velocity if jumping else velocity+_map_pending_pan/0.25)
	if jumping and return_ready:
		_return_jump_pending=false
		direct_return_count+=1
	_map_display_pose={"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom}


## 暂停/慢速演出泵：保持原时间步，只合成缩放和演出跟随后共用地图准入门。
func update_presentation_tick(delta: float) -> void:
	if camera==null: return
	var previous := _map_display_pose if not _map_display_pose.is_empty() else {
		"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom}
	var input_zoom := camera.zoom.x
	update_zoom(delta)
	cine_follow_tick(delta)
	var guard_ref: Variant=camera.get_meta(&"map_motion_guard") if camera.has_meta(&"map_motion_guard") else null
	var guard: Variant=guard_ref.get_ref() if guard_ref is WeakRef else null
	if typeof(guard)==TYPE_OBJECT and is_instance_valid(guard) and camera.is_inside_tree():
		camera.force_update_scroll()
		var viewport := camera.get_viewport()
		var logical := viewport.get_visible_rect().size
		var output := Vector2(viewport.size) if viewport is SubViewport else logical*viewport.get_stretch_transform().get_scale()
		if minf(logical.x,logical.y)>0.0 and minf(output.x,output.y)>0.0:
			var rate := log(camera.zoom.x/maxf(input_zoom,0.001))/maxf(delta,0.001)
			var velocity := (camera.global_position-Vector2(previous.position))/maxf(delta,0.001)
			var desired := {"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom,
				"canvas":viewport.get_canvas_transform()}
			if not guard.camera_motion_ready(desired.canvas,output,rate,velocity):
				camera.global_position=previous.position;camera.zoom=previous.zoom;camera.offset=previous.offset
				_base_zoom=previous.base;camera.force_update_scroll()
				_map_pending_zoom=desired.base
				guard.camera_motion_pending(desired.canvas,output,rate,velocity)
			else:
				_map_pending_zoom=-1.0
	_map_display_pose={"position":camera.global_position,"zoom":camera.zoom,"offset":camera.offset,"base":_base_zoom}

## 指定跟随目标（通常是玩家飞机）。传 null 取消
func set_follow_target(target: Node2D) -> void:
	_return_jump_pending=false
	follow_target = target

## 重新启用跟随（空格键入口）
func snap_to_follow() -> void:
	follow_enabled = true
	_wasd_velocity = Vector2.ZERO
	_wasd_hold_time = 0.0
	_wasd_direction=Vector2.ZERO
	_map_pending_pan=Vector2.ZERO;_map_pending_wasd=Vector2.ZERO;_map_pending_zoom=-1.0
	_return_jump_pending=false
	if distance_return_enabled and is_instance_valid(camera) and is_instance_valid(follow_target) and not is_instance_valid(cine_target):
		_return_jump_pending=should_snap_return(DisplayPacing.display_origin(follow_target)-camera.global_position,
			camera.zoom.x,camera.get_viewport().get_visible_rect().size)


static func should_snap_return(displacement: Vector2, zoom: float, size: Vector2) -> bool:
	# 超过一个视口短边即定位；按屏幕距离定义，不随分辨率或缩放改变远近含义。
	return displacement.is_finite() and is_finite(zoom) and zoom>0.0 and size.is_finite() \
		and minf(size.x,size.y)>0.0 and displacement.length()*zoom>minf(size.x,size.y)

func _update_wasd(delta: float) -> void:
	if not camera:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): dir.y += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0

	var target_vel := Vector2.ZERO
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		_wasd_hold_time = minf(_wasd_hold_time + delta, WASD_RAMP_TIME)
		var t: float = _wasd_hold_time / WASD_RAMP_TIME
		# ease-out cubic：起步时就有体面的速度，后段缓慢逼近峰值
		var curve: float = 1.0 - pow(1.0 - t, 3)
		var speed: float = lerpf(WASD_SPEED_MIN, WASD_SPEED_MAX, curve)
		target_vel = dir * speed
		follow_enabled = false
		_return_jump_pending=false
	else:
		_wasd_hold_time = 0.0
	_wasd_direction=dir

	# 平滑加减速 → 手感有惯性与曲线
	var lerp_t: float = clampf(delta * WASD_ACCEL, 0.0, 1.0)
	_wasd_velocity = _wasd_velocity.lerp(target_vel, lerp_t)

	if _wasd_velocity.length_squared() > 1.0:
		var zoom_x: float = maxf(camera.zoom.x, 0.001)
		camera.global_position += _wasd_velocity * delta / zoom_x
		_clamp_camera_position()

## 跟随目标取【物理插值显示态】而非 global_position：后者每 tick 才跳一次，
## 镜头在渲染帧里追一个阶梯目标会让屏幕滚动忽快忽慢、机体相对屏幕抖动。
func _update_follow(delta: float) -> void:
	if _return_prefetch: _publish_map_return_hint(delta)
	# 演出接管：cine_target 非空时优先跟它（无视 follow_enabled，演出期间玩家没有输入权）
	if cine_target != null and is_instance_valid(cine_target):
		_return_jump_pending=false
		var lt: float = clampf(delta * cine_follow_lerp, 0.0, 1.0)
		camera.global_position = camera.global_position.lerp(
			DisplayPacing.display_origin(cine_target), lt)
		_clamp_camera_position()
		return
	if not follow_enabled or follow_target == null or not is_instance_valid(follow_target):
		_return_jump_pending=false
		return
	var target_pos: Vector2 = DisplayPacing.display_origin(follow_target)
	var lerp_t: float = clampf(delta * FOLLOW_LERP, 0.0, 1.0)
	camera.global_position = target_pos if _return_jump_pending else camera.global_position.lerp(target_pos, lerp_t)
	_clamp_camera_position()

## 仅提供纯值预测；不移动镜头，也不改变空格跟随速度。无效/演出目标立即清空。
func _publish_map_return_hint(delta: float) -> void:
	var hint: Dictionary={}
	var target: Variant=follow_target
	if typeof(target)==TYPE_OBJECT and is_instance_valid(target) and target is Node2D \
		and not is_instance_valid(cine_target):
		var position: Vector2=DisplayPacing.display_origin(target)
		var velocity := Vector2.ZERO
		if target.get_instance_id()==_return_hint_target_id and delta>0.0:
			velocity=(position-_return_hint_position)/delta
		_return_hint_target_id=target.get_instance_id();_return_hint_position=position
		if _world_bounds.size.x>0.0:
			var half := camera.get_viewport().get_visible_rect().size/(2.0*camera.zoom.x)
			position=position.clamp(_world_bounds.position+half,_world_bounds.end-half)
			if position.x!=_return_hint_position.x: velocity.x=0.0
			if position.y!=_return_hint_position.y: velocity.y=0.0
		hint={"position":position,"rate":FOLLOW_LERP,"following":follow_enabled,
			"direct_return":distance_return_enabled and (not follow_enabled or _return_jump_pending),
			"screen_pan":not follow_enabled and _wasd_velocity.length_squared()>1.0,
			"pan_direction":_wasd_direction,"pan_hold":_wasd_hold_time,
			"pan_velocity":_wasd_velocity,"pan_zoom":camera.zoom.x,
			"target_velocity":velocity,"step_seconds":maxf(delta,0.0)}
		if _player_zoom_prediction and cine_zoom_mult==1.0: hint["zoom_target"]=target_zoom
	else: _return_hint_target_id=0
	camera.set_meta(&"map_return_hint",hint)

## 滚轮缩放输入
func handle_zoom_input(factor: float) -> void:
	_player_zoom_prediction = true
	target_zoom = clampf(target_zoom * factor, ZOOM_MIN, ZOOM_MAX)

## 屏幕坐标 → 世界坐标
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := camera.get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

## 鼠标拖拽平移相机（中键拖拽会关闭跟随）
func handle_drag(relative: Vector2) -> void:
	_return_jump_pending=false
	camera.global_position -= relative / camera.zoom
	follow_enabled = false
	_clamp_camera_position()

## 把相机位置钳制到 _world_bounds 内，保留视口半宽余量，使画面不越界
func _clamp_camera_position() -> void:
	if _world_bounds.size.x <= 0.0 or not camera:
		return
	var vp_size := camera.get_viewport().get_visible_rect().size
	var half := vp_size / (2.0 * camera.zoom.x)
	var min_pos := _world_bounds.position + half
	var max_pos := _world_bounds.end - half
	# 如果视口比地图还大（理论上极低 zoom 才会），退化为居中
	if min_pos.x > max_pos.x:
		var cx := (_world_bounds.position.x + _world_bounds.end.x) * 0.5
		min_pos.x = cx
		max_pos.x = cx
	if min_pos.y > max_pos.y:
		var cy := (_world_bounds.position.y + _world_bounds.end.y) * 0.5
		min_pos.y = cy
		max_pos.y = cy
	camera.global_position = camera.global_position.clamp(min_pos, max_pos)

## 世界坐标是否出现在当前相机视野内（含 margin_px 缓冲）
## 用于"不在玩家画面内刷敌"的铁则
func is_world_pos_visible(world_pos: Vector2, margin_px: float = 200.0) -> bool:
	if not camera:
		return false
	var vp_size := camera.get_viewport().get_visible_rect().size
	var half := vp_size / (2.0 * camera.zoom) + Vector2(margin_px, margin_px)
	var view_rotation := 0.0 if camera.ignore_rotation else camera.global_rotation
	var rel := (world_pos - camera.get_screen_center_position()).rotated(-view_rotation)
	return absf(rel.x) <= half.x and absf(rel.y) <= half.y


static func hover_radius_world_for_zoom(zoom: float) -> float:
	return HOVER_RADIUS / maxf(absf(zoom), 0.01)


## hover 检测：遍历单位列表，标记距离最近的单位
func update_hover(screen_pos: Vector2, units: Array) -> CombatUnit:
	var world_pos := screen_to_world(screen_pos)
	# 清除旧悬停
	if hovered_unit and is_instance_valid(hovered_unit):
		hovered_unit.is_hovered = false
	hovered_unit = null

	var zoom := camera.zoom.x if camera != null else 1.0
	var best_dist := hover_radius_world_for_zoom(zoom)
	for child in units:
		if typeof(child) != TYPE_OBJECT or not is_instance_valid(child):
			continue
		if child is CombatUnit:
			# 跳过锁定代理节点（船上的挂点 MountTarget）—— 让 hover 落到整艘船上
			if child is MountTarget:
				continue
			var d := world_pos.distance_to(DisplayPacing.display_origin(child))
			if d < best_dist:
				best_dist = d
				hovered_unit = child

	if hovered_unit:
		hovered_unit.is_hovered = true
	return hovered_unit
