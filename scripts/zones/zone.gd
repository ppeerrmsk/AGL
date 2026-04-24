class_name Zone
extends Node2D

## 战区基类 —— 所有类型战区（海上 / 空战 / 地面 / BOSS）的公共骨架
##
## 生命期：SPAWNED → ACTIVE → COMPLETED → CLEANING_UP → queue_free
##   SPAWNED       —— 刚创建，等 ZoneManager 调 _finalize_spawn()
##   ACTIVE        —— 正常运行，每帧 update() 检查完成条件 + 玩家进出
##   COMPLETED     —— 条件满足（如旗舰死），触发结算 + 清理动画
##   CLEANING_UP   —— 等所有实体清完，然后 queue_free
##
## 子类必须覆写：
##   spawn_entities()        —— 创建敌人 / 舰队
##   cleanup_entities(completed: bool)  —— 清理残留实体
##   completion_condition() -> bool     —— 何时任务完成
##   get_display_info() -> Dictionary   —— HUD / Debug 面板显示
##
## 子类可选覆写：
##   on_player_entered() / on_player_exited() —— 进出战区事件
##   build_debug_ui(parent)  —— 在 Debug 面板展开时插入子控件
##   _update_active(delta)    —— ACTIVE 状态每帧钩子

enum State { SPAWNED, ACTIVE, COMPLETED, CLEANING_UP }

# ── 基本属性 ──
var type_id: int = ZoneType.TYPE_NONE
var state: int = State.SPAWNED
var config: Dictionary = {}         ## 由 ZoneType.default_config 填充，可被 Debug 面板热改
var radius: float = 8000.0          ## 战区半径（像素）
var spawned_entities: Array = []    ## 本战区 spawn 的敌方实体（Aircraft / NavalUnit / GroundUnit 混合）

# ── 场景引用 ──
var scene_root: Node = null         ## survivor_mode，用来 add_child(entity)
var manager: Node = null            ## ZoneManager ref

# ── 玩家感知 ──
var player_inside: bool = false

# ── 绘制（战区圆环）──
var _draw_pulse_time: float = 0.0

# ── 信号 ──
signal entered(zone)
signal exited(zone)
signal completed(zone)
signal state_changed(zone, old_state, new_state)

# ============================================================
#  生命期
# ============================================================

## ZoneManager 调这个完成 spawn 初始化（add_child 之后调）
func finalize_spawn(_manager: Node, _scene_root: Node, _type_id: int, _config: Dictionary) -> void:
	manager = _manager
	scene_root = _scene_root
	type_id = _type_id
	config = _config.duplicate(true)
	if config.has("radius"):
		radius = float(config["radius"])
	_transition_state(State.SPAWNED)
	spawn_entities()
	_transition_state(State.ACTIVE)

## 由子类覆写：实际 spawn 实体
func spawn_entities() -> void:
	pass

## 由子类覆写：清理敌方实体
## completed=true 表示走正常结算（挂奖励动画），false 表示强制销毁（Debug Clear / Refresh）
func cleanup_entities(_completed: bool) -> void:
	# 默认实现：直接 queue_free 所有存活实体
	for e in spawned_entities:
		if e == null or not is_instance_valid(e):
			continue
		if e.has_method("queue_free"):
			e.queue_free()
	spawned_entities.clear()

## 由子类覆写：任务完成条件（返回 true 就触发 on_complete）
func completion_condition() -> bool:
	return false

## 由子类覆写：HUD 显示信息
## 应返回 {"name": ..., "objective": ..., "star": 1|2|3|0}
func get_display_info() -> Dictionary:
	return {
		"name": ZoneType.display_name(type_id),
		"objective": "-",
		"star": ZoneType.star(type_id),
	}

## 由子类覆写：进入战区时触发（舰载机起飞等）
func on_player_entered() -> void:
	pass

## 由子类覆写：离开战区时触发
func on_player_exited() -> void:
	pass

## 由子类覆写：Debug 面板展开时插入专属控件
## 父级给子类自己加 Button / HSlider 等
func build_debug_ui(_parent: Container) -> void:
	pass

## 子类可选：ACTIVE 状态每帧钩子（轨迹更新等）
func _update_active(_delta: float) -> void:
	pass

# ============================================================
#  主循环（由 ZoneManager 调用）
# ============================================================

## ZoneManager._process 调
## 1. 玩家进出检测
## 2. 完成条件检测
## 3. 走子类每帧钩子
func update(player: Node2D, delta: float) -> void:
	_draw_pulse_time += delta
	queue_redraw()

	if state == State.ACTIVE:
		_update_player_proximity(player)
		_update_active(delta)
		if completion_condition():
			# 走 manager 的 complete_zone 保证 active_zones 列表同步清理
			if manager and manager.has_method("complete_zone"):
				manager.complete_zone(self)
			else:
				mark_complete()

func _update_player_proximity(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var inside: bool = global_position.distance_to(player.global_position) <= radius
	if inside and not player_inside:
		player_inside = true
		on_player_entered()
		entered.emit(self)
	elif not inside and player_inside:
		player_inside = false
		on_player_exited()
		exited.emit(self)

## 正常完成（外部可调，Debug 面板 Mark Complete 也走这里）
func mark_complete() -> void:
	if state != State.ACTIVE and state != State.SPAWNED:
		return
	_transition_state(State.COMPLETED)
	cleanup_entities(true)
	completed.emit(self)
	_transition_state(State.CLEANING_UP)
	# 给清理动画留一点时间（暂定 2s），然后 queue_free
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		queue_free()

## 强制销毁（Debug 面板 Clear / Refresh / Change Type 用）
func force_despawn() -> void:
	cleanup_entities(false)
	queue_free()

## 刷新：保留位置 / 半径 / 类型，内部敌人重 spawn
func refresh() -> void:
	if state == State.CLEANING_UP:
		return
	cleanup_entities(false)
	spawn_entities()
	if state != State.ACTIVE:
		_transition_state(State.ACTIVE)

# ============================================================
#  状态切换
# ============================================================

func _transition_state(new_state: int) -> void:
	if state == new_state:
		return
	var old := state
	state = new_state
	state_changed.emit(self, old, new_state)

# ============================================================
#  绘制（战区圆环边界）
# ============================================================

func _draw() -> void:
	var color := _color_for_star()
	var pulse: float = 0.5 + 0.5 * sin(_draw_pulse_time * TAU * 0.5)  # 0.5 Hz 柔和脉动
	var alpha_base: float = 0.35 if state == State.ACTIVE else 0.15
	var alpha: float = alpha_base + 0.25 * pulse

	# 外边界虚线圆
	_draw_dashed_circle(radius, Color(color.r, color.g, color.b, alpha), 64, 0.04)
	# 内圈填充（非常淡）
	_draw_filled_circle(radius, Color(color.r, color.g, color.b, alpha * 0.08), 32)
	# 中心小十字
	var cross_size: float = 40.0
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), Color(color.r, color.g, color.b, alpha * 1.3), 2.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), Color(color.r, color.g, color.b, alpha * 1.3), 2.0)

func _color_for_star() -> Color:
	# 1★ 绿 / 2★ 黄 / 3★ 红（BOSS）/ 默认紫
	var s := ZoneType.star(type_id)
	match s:
		1: return Color(0.4, 0.85, 0.3)
		2: return Color(0.95, 0.75, 0.2)
		3: return Color(0.95, 0.3, 0.2)
	return Color(0.7, 0.4, 0.9)

func _draw_dashed_circle(r: float, color: Color, segments: int, gap_ratio: float) -> void:
	var seg_angle: float = TAU / segments
	for i in range(segments):
		var a0: float = seg_angle * i
		var a1: float = seg_angle * (i + 1) - seg_angle * gap_ratio
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		draw_line(p0, p1, color, 2.0)

func _draw_filled_circle(r: float, color: Color, segments: int) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)
