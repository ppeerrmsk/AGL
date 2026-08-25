class_name TrailRibbon
extends Node2D

## 飞行轨迹丝带效果
## 作为子节点挂载到 Aircraft 或 Missile 上

@export var ribbon_color: Color = Color(0.3, 0.5, 1.0, 0.6)
@export var ribbon_width: float = 8.0
@export var max_points: int = 80   ## 性能敏感：300→80，视觉上尾迹稍短但密度不变
@export var sample_interval: float = 0.05  ## 采样间隔（秒）= 采样率 20Hz

## 屏外早退余量（px）：父节点屏幕位置 + 此 margin 仍出视口 → 完全跳过 _draw
## 800px ≈ 1600m，比 80 点 × 0.06s × 600 m/s 的最长导弹尾迹（~1450px）略小，足够避免可见 pop
## 选小一些可以更激进地剔除；选大保险但收益变少
const OFFSCREEN_CULL_MARGIN_PX: float = 800.0
const SAMPLE_PHASE_SLOTS: int = 8
const STRATEGIC_LOD_VIEW_SCALE: float = 0.26
static var _next_sample_phase_slot: int = 0

var _trail_data: Array = []  ## Array of { pos: Vector2, heading: float, bank: float }
var _sample_timer: float = 0.0
var _sample_phase_offset: float = 0.0
var _sample_phase_slot: int = 0
var _missile_batch_canvas: Node2D = null
var _geometry_dirty: bool = true
var _cached_verts := PackedVector2Array()
var _cached_colors := PackedColorArray()
var _cached_indices := PackedInt32Array()
var _cached_fade: float = -1.0
var _cached_color := Color.TRANSPARENT
var _cached_width: float = -1.0
var _cached_point_step: int = 1
var _emission_enabled: bool = true

## 屏外 cull → 进入可见的 fade-in（避免镜头切到飞机时 80 点尾迹"瞬间显形"）
## 初值 true → spawn 时第一帧也算"进入可见"，新尾迹也是渐显出来
var _was_culled: bool = true
var _visibility_fade_in: float = 0.0  ## 0..1，1=完全显示
const FADE_IN_PER_FRAME: float = 0.04  ## ≈ 0.4s @60Hz fully fade in


func _ready() -> void:
	# 多机同帧创建时不能让全部 20Hz 几何重建撞在同一渲染帧；8 相位只改采样时刻，
	# 不改每条尾迹的采样率、点数或视觉长度。
	_sample_phase_slot = _next_sample_phase_slot % SAMPLE_PHASE_SLOTS
	_sample_phase_offset = sample_interval * float(_sample_phase_slot) / float(SAMPLE_PHASE_SLOTS)
	_next_sample_phase_slot += 1
	_sample_timer = _sample_phase_offset
	global_transform = Transform2D.IDENTITY


func assign_missile_batch(batch_canvas: Node2D) -> void:
	_missile_batch_canvas = batch_canvas
	queue_redraw() # 清空自身 Canvas 命令；后续改由 batch_canvas 持有。
	_request_redraw()


func missile_batch_phase_slot() -> int:
	return _sample_phase_slot


func _request_redraw() -> void:
	if _missile_batch_canvas != null and is_instance_valid(_missile_batch_canvas):
		_missile_batch_canvas.queue_redraw()
	else:
		queue_redraw()


func _exit_tree() -> void:
	if _missile_batch_canvas != null and is_instance_valid(_missile_batch_canvas):
		_missile_batch_canvas.queue_redraw()

func add_point(pos: Vector2, heading: float, bank: float) -> void:
	_trail_data.append({ "pos": pos, "heading": heading, "bank": bank })
	if _trail_data.size() > max_points:
		_trail_data.remove_at(0)
	_geometry_dirty = true
	_request_redraw()

## 清空轨迹（用于传送/重生等场景，避免跨越的丝带）
func clear_trail() -> void:
	_trail_data.clear()
	_sample_timer = _sample_phase_offset
	_geometry_dirty = true
	_request_redraw()

## 完全传感器隐形时同时停采样和绘制；恢复时从空轨迹重新淡入，杜绝幽灵尾迹。
func set_emission_enabled(enabled: bool) -> void:
	if _emission_enabled == enabled:
		return
	_emission_enabled = enabled
	clear_trail()
	visible = enabled
	set_process(enabled)
	if enabled:
		_was_culled = true
		_visibility_fade_in = 0.0

func _process(delta: float) -> void:
	# 尾迹点本来就是世界坐标；抵消父机变换后，缓存网格可跨帧复用且仍留在原世界位置。
	# show_behind_parent / modulate 等 CanvasItem 继承语义不变。
	global_transform = Transform2D.IDENTITY
	_sample_timer += delta
	if _sample_timer >= sample_interval:
		_sample_timer -= sample_interval
		var parent := get_parent()
		if parent:
			var bank: float = parent.bank_angle if "bank_angle" in parent else 0.0
			var hdg: float = parent.heading if "heading" in parent else parent.rotation
			add_point(parent.global_position, hdg, bank)

	# CanvasItem 会保留上次 draw command；几何未变化时无需每帧清空并重提 triangle array。
	# 屏外状态变化时才清除/恢复，切回期间仍逐帧淡入；常态仅由 20Hz add_point 重画。
	var culled := false
	var parent_node := get_parent()
	if parent_node is Node2D:
		var screen_pos: Vector2 = get_viewport_transform() * (parent_node as Node2D).global_position
		culled = not get_viewport_rect().grow(OFFSCREEN_CULL_MARGIN_PX).has_point(screen_pos)
	if culled:
		PerfBuckets.count("trail_culled")
		if not _was_culled:
			_was_culled = true
			_visibility_fade_in = 0.0
			_geometry_dirty = true
			_request_redraw()
		return
	if _was_culled:
		_was_culled = false
		_visibility_fade_in = 0.0
		_geometry_dirty = true
	if _visibility_fade_in < 1.0:
		_visibility_fade_in = minf(_visibility_fade_in + FADE_IN_PER_FRAME, 1.0)
		_geometry_dirty = true
		_request_redraw()
	elif _cached_color != ribbon_color or not is_equal_approx(_cached_width, ribbon_width):
		_geometry_dirty = true
		_request_redraw()
	var desired_step := _desired_geometry_point_step()
	if desired_step != _cached_point_step:
		_cached_point_step = desired_step
		_geometry_dirty = true
		_request_redraw()


static func geometry_point_step_for(view_scale: float, protected_actor: bool,
		player_owned_missile: bool, is_missile: bool = false) -> int:
	if view_scale >= STRATEGIC_LOD_VIEW_SCALE or protected_actor \
			or player_owned_missile:
		return 1
	return 4 if is_missile else 2


func _desired_geometry_point_step() -> int:
	var parent_node := get_parent()
	var protected_actor := false
	var player_owned_missile := false
	var player: Aircraft = AircraftRenderer.safe_player_ref()
	if parent_node is Aircraft:
		var ac := parent_node as Aircraft
		var category := String(ac.get_meta("category", ""))
		protected_actor = ac == player or category == "boss" or category.begins_with("boss_") \
			or String(ac.get_meta("enemy_type", "")) == "uav_commander"
	elif parent_node is Missile:
		var missile := parent_node as Missile
		player_owned_missile = player != null and is_instance_valid(missile.source) \
			and missile.source == player
		protected_actor = missile.is_incoming_warning_for(player)
	return geometry_point_step_for(AircraftRenderer.label_lod_scale(self),
		protected_actor, player_owned_missile, parent_node is Missile)

## 用 RenderingServer 的三角形索引数组一次性提交整条丝带（GPU 命令 N→1）
## 原：max_points=300 × 60Hz × 22架 ≈ 40 万次 draw_polygon/秒（GPU 命令爆炸）
## 新：1 次/帧 × 20Hz × 22架 ≈ 440 次/秒
func _draw() -> void:
	# Perf 包装：每架飞机的尾迹绘制（trail_data → triangle_array）耗时聚合到 trail_draw 桶
	var _perf_t0: int = Time.get_ticks_usec()
	_draw_impl()
	PerfBuckets.tick("trail_draw", Time.get_ticks_usec() - _perf_t0)


func _draw_impl() -> void:
	# 导弹尾迹由同采样相位的 MissileTrailBatch 集中提交；飞机尾迹仍保留独立 CanvasItem。
	if _missile_batch_canvas != null:
		return
	# 屏外切换由 _process 驱动；本次空绘制会清掉保留式 Canvas 命令。
	if _was_culled:
		return

	var count := _trail_data.size()
	if count < 2:
		return
	if _geometry_dirty or not is_equal_approx(_cached_fade, _visibility_fade_in) \
			or _cached_color != ribbon_color or not is_equal_approx(_cached_width, ribbon_width):
		_rebuild_cached_geometry()
	if _cached_indices.is_empty():
		return

	# RenderingServer 层一次性提交缓存网格（比 N 次 draw_polygon 快一个数量级）
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _cached_indices, _cached_verts, _cached_colors
	)


## 将世界坐标缓存追加到导弹批次；几何、颜色、战略 LOD 与淡入语义均沿用独立尾迹。
func append_to_missile_batch(verts: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array) -> void:
	if _was_culled or not visible:
		return
	var count := _trail_data.size()
	if count < 2:
		return
	if _geometry_dirty or not is_equal_approx(_cached_fade, _visibility_fade_in) \
			or _cached_color != ribbon_color or not is_equal_approx(_cached_width, ribbon_width):
		_rebuild_cached_geometry()
	if _cached_indices.is_empty():
		return
	var base := verts.size()
	verts.append_array(_cached_verts)
	var parent_alpha := 1.0
	var parent_item := get_parent() as CanvasItem
	if parent_item != null:
		if not parent_item.visible:
			verts.resize(base)
			return
		parent_alpha = parent_item.modulate.a
	if is_equal_approx(parent_alpha, 1.0):
		colors.append_array(_cached_colors)
	else:
		for color in _cached_colors:
			colors.push_back(Color(color.r, color.g, color.b, color.a * parent_alpha))
	for index in _cached_indices:
		indices.push_back(base + index)


func _rebuild_cached_geometry() -> void:
	var count := _trail_data.size()
	if count < 2:
		_cached_verts.clear()
		_cached_colors.clear()
		_cached_indices.clear()
		_geometry_dirty = false
		return

	var source_indices := PackedInt32Array()
	var source_i := 0
	while source_i < count:
		source_indices.append(source_i)
		source_i += _cached_point_step
	if source_indices[-1] != count - 1:
		source_indices.append(count - 1)
	var visible_count := source_indices.size()
	# 节点全局变换固定为 identity，因此缓存直接使用世界坐标，不再每渲染帧做 80×to_local。
	_cached_verts.resize(visible_count * 2)
	_cached_colors.resize(visible_count * 2)

	var inv_last := 1.0 / float(count - 1)
	var prev_point: Vector2 = _trail_data[source_indices[0]]["pos"]

	for visible_i in range(visible_count):
		var original_i: int = source_indices[visible_i]
		var d: Dictionary = _trail_data[original_i]
		var point: Vector2 = d["pos"]

		var fwd: Vector2
		if visible_i == 0:
			fwd = Vector2(_trail_data[source_indices[1]]["pos"]) - point
		elif visible_i == visible_count - 1:
			fwd = point - prev_point
		else:
			fwd = Vector2(_trail_data[source_indices[visible_i + 1]]["pos"]) - prev_point
		if fwd.length_squared() < 0.01:
			fwd = Vector2.UP
		else:
			fwd = fwd.normalized()
		var perp := Vector2(-fwd.y, fwd.x)

		var bank: float = d["bank"]
		var w := ribbon_width * cos(bank) * 0.5
		var off := perp * ribbon_width * sin(bank) * 0.3

		var alpha := float(original_i) * inv_last * ribbon_color.a * _visibility_fade_in
		var c := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, alpha)

		_cached_verts[visible_i * 2] = point + off + perp * w
		_cached_verts[visible_i * 2 + 1] = point + off - perp * w
		_cached_colors[visible_i * 2] = c
		_cached_colors[visible_i * 2 + 1] = c

		prev_point = point

	# 索引构造三角形（2×(count-1) 个三角形 = 丝带状）
	_cached_indices.resize((visible_count - 1) * 6)
	for i in range(visible_count - 1):
		var base := i * 2
		var idx := i * 6
		_cached_indices[idx] = base
		_cached_indices[idx + 1] = base + 1
		_cached_indices[idx + 2] = base + 2
		_cached_indices[idx + 3] = base + 1
		_cached_indices[idx + 4] = base + 3
		_cached_indices[idx + 5] = base + 2
	_cached_fade = _visibility_fade_in
	_cached_color = ribbon_color
	_cached_width = ribbon_width
	_geometry_dirty = false
