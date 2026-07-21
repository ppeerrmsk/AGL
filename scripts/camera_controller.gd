class_name CameraController
extends Node

## 共享相机操控：缩放/平移/hover/坐标转换
## 沙盒和生存模式共用核心操控逻辑。
## 用法：
##   var cam_ctrl := CameraController.new()
##   add_child(cam_ctrl)
##   cam_ctrl.setup(camera)
##   cam_ctrl.set_world_bounds(Rect2(...))  # 可选：开启相机位置钳制

const ZOOM_MIN := 0.2       ## 最大缩小倍率（越小视野越大；0.2 ≈ 1920 屏宽下可视 9600 px / 19.2 km，可俯瞰大半张图）
const START_ZOOM := 0.35    ## 开局镜头（比 ZOOM_MIN 略紧，避免开局飞机太小；玩家可滚轮拉到 ZOOM_MIN 看全场）
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const HOVER_RADIUS := 30.0  ## 鼠标悬停判定半径（像素）

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

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	# 初始镜头用 START_ZOOM（俯瞰但飞机不至于太小）；上限放宽到 ZOOM_MIN 供玩家拉远看全场
	camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	target_zoom = START_ZOOM
	_base_zoom = START_ZOOM

## 启用相机位置钳制（传入世界矩形；生存模式传 MapBoundary.get_world_rect()）
func set_world_bounds(rect: Rect2) -> void:
	_world_bounds = rect

## 每帧调用：平滑缩放 + 电影层叠加 + 位置钳制
## _base_zoom 只跟 target_zoom 走（不回读 camera.zoom，避免与 cine_zoom_mult 形成自乘反馈环）；
## camera.zoom = _base_zoom × cine_zoom_mult。_clamp_camera_position 仍读实际 zoom ——
## 这是对的，钳制应基于真实视野
func update_zoom(delta: float) -> void:
	_base_zoom = lerpf(_base_zoom, target_zoom, delta * 10.0)
	var eff: float = _base_zoom * cine_zoom_mult
	camera.zoom = Vector2(eff, eff)
	_update_cine_offset(delta)
	_clamp_camera_position()

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
	if _saved_target_zoom < 0.0:
		_saved_target_zoom = target_zoom
	cine_target = null
	target_zoom = zoom
	_base_zoom = zoom          # 瞬切不留 lerp 拖尾
	if camera:
		camera.global_position = world_pos
		camera.zoom = Vector2(zoom * cine_zoom_mult, zoom * cine_zoom_mult)
		_clamp_camera_position()

## 演出跟随泵：hard_pause 期间 survivor_mode 的 update() 不跑，导演代泵本函数
## 让镜头持续咬住 cine_target（手感 = 空格跟随，同 FOLLOW_LERP 量级的 lerp）
func cine_follow_tick(delta: float) -> void:
	if camera == null or cine_target == null or not is_instance_valid(cine_target):
		return
	var lt: float = clampf(delta * cine_follow_lerp, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(cine_target.global_position, lt)
	_clamp_camera_position()

## 演出收尾：还原玩家 zoom 与跟随。t 为 0..1 进度，用于平滑过渡回去
func cine_return_to_player(t: float) -> void:
	# 归位一开始就停止追演员 —— 此刻演员多半已隐身/散开，镜头不该追着看不见的目标跑
	cine_target = null
	if _saved_target_zoom < 0.0:
		return
	target_zoom = lerpf(target_zoom, _saved_target_zoom, clampf(t, 0.0, 1.0))
	if t >= 1.0:
		target_zoom = _saved_target_zoom
		_saved_target_zoom = -1.0
		cine_target = null
		follow_enabled = true

## 电影层归位。演出结束 / 场景切换 / 导演 clear_all 必调
func cine_reset() -> void:
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
	update_zoom(delta)
	_update_wasd(delta)
	_update_follow(delta)

## 指定跟随目标（通常是玩家飞机）。传 null 取消
func set_follow_target(target: Node2D) -> void:
	follow_target = target

## 重新启用跟随（空格键入口）
func snap_to_follow() -> void:
	follow_enabled = true
	_wasd_velocity = Vector2.ZERO
	_wasd_hold_time = 0.0

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
	else:
		_wasd_hold_time = 0.0

	# 平滑加减速 → 手感有惯性与曲线
	var lerp_t: float = clampf(delta * WASD_ACCEL, 0.0, 1.0)
	_wasd_velocity = _wasd_velocity.lerp(target_vel, lerp_t)

	if _wasd_velocity.length_squared() > 1.0:
		var zoom_x: float = maxf(camera.zoom.x, 0.001)
		camera.global_position += _wasd_velocity * delta / zoom_x
		_clamp_camera_position()

func _update_follow(delta: float) -> void:
	# 演出接管：cine_target 非空时优先跟它（无视 follow_enabled，演出期间玩家没有输入权）
	if cine_target != null and is_instance_valid(cine_target):
		var lt: float = clampf(delta * cine_follow_lerp, 0.0, 1.0)
		camera.global_position = camera.global_position.lerp(cine_target.global_position, lt)
		_clamp_camera_position()
		return
	if not follow_enabled or follow_target == null or not is_instance_valid(follow_target):
		return
	var target_pos: Vector2 = follow_target.global_position
	var lerp_t: float = clampf(delta * FOLLOW_LERP, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(target_pos, lerp_t)
	_clamp_camera_position()

## 滚轮缩放输入
func handle_zoom_input(factor: float) -> void:
	target_zoom = clampf(target_zoom * factor, ZOOM_MIN, ZOOM_MAX)

## 屏幕坐标 → 世界坐标
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := camera.get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

## 鼠标拖拽平移相机（中键拖拽会关闭跟随）
func handle_drag(relative: Vector2) -> void:
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
	var half := vp_size / (2.0 * camera.zoom.x) + Vector2(margin_px, margin_px)
	var rel := world_pos - camera.global_position
	return absf(rel.x) <= half.x and absf(rel.y) <= half.y

## hover 检测：遍历单位列表，标记距离最近的单位
func update_hover(screen_pos: Vector2, units: Array) -> CombatUnit:
	var world_pos := screen_to_world(screen_pos)
	# 清除旧悬停
	if hovered_unit and is_instance_valid(hovered_unit):
		hovered_unit.is_hovered = false
	hovered_unit = null

	var best_dist := HOVER_RADIUS
	for child in units:
		if child is CombatUnit:
			# 跳过锁定代理节点（船上的挂点 MountTarget）—— 让 hover 落到整艘船上
			if child is MountTarget:
				continue
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				hovered_unit = child

	if hovered_unit:
		hovered_unit.is_hovered = true
	return hovered_unit
