class_name BuildingRenderer
extends Node2D

const TrianglePacket = preload("res://scripts/rendering/canvas_triangle_packet.gd")

## 横浜伪 3D 城市街区渲染器（生存模式独立模块）
##
## 数据来源：resources/maps/yokohama_buildings.json（由 bake_buildings.py 烘焙）
## 撤回方法：从 survivor_mode.gd 删除 add_child 那一行 + 删除本文件，无副作用
##
## 视觉策略：街区合并 → 每个合并块伪 3D
## - bake 阶段：相邻 ≤10m 的楼合并成街区多边形，simplify 平滑边缘
## - 每个街区视觉高度由其包含的最高楼真实高度驱动（含 Landmark Tower 的街区会高耸）
## - 不渲染单栋建筑，避免"碎片感"

const DATA_PATH := "res://resources/maps/yokohama_buildings.json"

## parallax 强度
@export_range(0.0, 0.3, 0.005) var perspective_k: float = 0.10
## R220 显式候选；完成实景/帧时验证后才推广默认。
var bounded_roof_projection := false
var cache_shadow_geometry := false
## 按楼顶屏幕位移控制重绘，0保持旧4世界像素门；不改几何/碰撞。
var redraw_roof_error_px := 0.0
var shadow_cache_builds := 0
var _shadow_packet: Dictionary = {}
var _shadow_sources := PackedInt32Array()
var _shadow_offset := Vector2.ZERO
var _shadow_tint := Color.TRANSPARENT

## 视觉高度 = max_real_h(米) × 这个系数（像素）
@export_range(0.3, 2.0, 0.05) var district_h_scale: float = 0.6

## 阴影 polygon 比 footprint 外扩多少像素
@export_range(0.0, 30.0, 1.0) var shadow_expand_px: float = 6.0

## 阴影沿光照反方向偏移多少像素
@export_range(0.0, 40.0, 1.0) var shadow_offset_px: float = 10.0

## 光照方向（指向"阳光来自的方向"）
@export var light_dir: Vector2 = Vector2(-0.7, -0.7).normalized()

## 颜色调色板
@export_group("Colors")
@export var roof_color: Color = Color(0.62, 0.59, 0.53, 1.0)
@export var wall_lit_color: Color = Color(0.52, 0.49, 0.43, 1.0)
@export var wall_shade_color: Color = Color(0.26, 0.25, 0.23, 1.0)
@export var shadow_color: Color = Color(0.04, 0.05, 0.07, 0.55)
@export var roof_outline_color: Color = Color(0.10, 0.10, 0.09, 0.6)

const REDRAW_DIST_THRESHOLD := 4.0  # 相机平移 ≥4px 才重画（降低高速飞行时的 redraw 频率）

## 静态缓存（process-wide，跨 scene 切换保留）
## 由 BuildingPreloader 在 survivor_mode 启动前预热，进入战场时秒读
const PRELOAD_SHADOW_EXPAND_PX := 6.0  # 与 @export 默认值保持一致
const PRELOAD_DISTRICT_H_SCALE := 0.6
static var _cache_entries: Array = []
static var _cache_raw_districts: Array = []
static var _cache_idx: int = 0
static var _cache_phase: int = 0  # 0=idle, 1=parsing, 2=processing, 3=done
## 全局 bbox（包住所有街区）+ 全局最高楼，用于 is_position_blocked_at_altitude 的 O(1) 早退
## 在 phase 3 转换时由 _finalize_cache 计算
static var _cache_world_bbox: Rect2 = Rect2()
static var _cache_max_h_global: float = 0.0

var _camera: Camera2D = null
var _last_camera_pos := Vector2(INF, INF)
var _last_camera_zoom := Vector2.ZERO
var _last_view_extent := Vector2.ZERO

## 每个街区: { footprint, tri_indices, center, edge_normals, h_visual,
##             shadow_poly, shadow_tri }
var _districts: Array = []
var _loaded := false
var _volume_sources := PackedInt32Array()
var _volume_hidden: Dictionary = {}
var _volume_owner: WeakRef
var _volume_owner_id := 0


func set_volume_coverage(owner: Node, sources: PackedInt32Array) -> bool:
	var prior: Variant = _volume_owner.get_ref() if _volume_owner != null else null
	if typeof(prior) == TYPE_OBJECT and is_instance_valid(prior) and prior != owner:
		return false
	for source: int in sources:
		if source < 0 or source >= _districts.size():
			return false
	if _volume_owner_id != owner.get_instance_id():
		_volume_owner = weakref(owner)
		_volume_owner_id = owner.get_instance_id()
		owner.tree_exiting.connect(_clear_volume_coverage.bind(_volume_owner_id), CONNECT_ONE_SHOT)
	if sources == _volume_sources:
		return true
	_volume_sources = sources.duplicate()
	_volume_hidden.clear()
	for source: int in sources:
		_volume_hidden[source] = true
	queue_redraw()
	return true


func _clear_volume_coverage(owner_id: int) -> void:
	if owner_id != _volume_owner_id:
		return
	_volume_owner = null
	_volume_owner_id = 0
	_volume_sources.clear()
	_volume_hidden.clear()
	queue_redraw()


# ══════════════════════════════════════════════
#  静态预热 API（供 BuildingPreloader 调用）
# ══════════════════════════════════════════════

static func cache_is_ready() -> bool:
	return _cache_phase == 3


static func cache_progress() -> float:
	if _cache_phase == 3:
		return 1.0
	if _cache_phase == 0:
		return 0.0
	if _cache_raw_districts.is_empty():
		return 0.0
	return float(_cache_idx) / float(_cache_raw_districts.size())


## UGC 注入生效标志：置位后 _load_data 不得回退官方 JSON（空建筑图也要"忠实地空"——
## 曾因空缓存触发兜底同步加载，官方 193 楼按官方坐标出现在用户图的海上）
static var _ugc_active := false

static func cache_reset() -> void:
	_cache_entries.clear()
	_cache_raw_districts.clear()
	_cache_idx = 0
	_cache_phase = 0
	_ugc_active = false


## UGC 注入口（UgcLoader 调用）：跳过 JSON 读取，直接给 raw districts，
## 复用既有分帧预热流水线（cache_step）构建 entries。官方路径不受影响。
## districts 元素结构与官方 JSON 相同：{footprint: [[x,y]...], max_real_h: float}
static func inject_ugc_districts(districts: Array) -> void:
	cache_reset()
	_ugc_active = true
	_cache_raw_districts = districts
	_cache_phase = 2 if districts.size() > 0 else 3
	if districts.is_empty():
		_finalize_cache()


## 单步预热 N 个街区。返回 true 表示已完成。每帧调一次。
static func cache_step(n: int = 25) -> bool:
	if _cache_phase == 3:
		return true
	if _cache_phase == 0:
		_cache_load_json()
	if _cache_phase == 2:
		var total := _cache_raw_districts.size()
		var end_idx := mini(_cache_idx + n, total)
		while _cache_idx < end_idx:
			var entry = _build_entry_static(_cache_raw_districts[_cache_idx])
			if entry != null:
				_cache_entries.append(entry)
			_cache_idx += 1
		if _cache_idx >= total:
			_cache_phase = 3
			_finalize_cache()
			return true
	return _cache_phase == 3


static func _finalize_cache() -> void:
	if _cache_entries.is_empty():
		_cache_world_bbox = Rect2()
		_cache_max_h_global = 0.0
		return
	var bb: Rect2 = _cache_entries[0]["bbox"]
	_cache_max_h_global = _cache_entries[0]["max_real_h"]
	for i in range(1, _cache_entries.size()):
		var e: Dictionary = _cache_entries[i]
		bb = bb.merge(e["bbox"])
		_cache_max_h_global = maxf(_cache_max_h_global, float(e["max_real_h"]))
	_cache_world_bbox = bb


static func _cache_load_json() -> void:
	_cache_phase = 1
	if not FileAccess.file_exists(DATA_PATH):
		_cache_phase = 3
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		_cache_phase = 3
		return
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if raw is Dictionary:
		_cache_raw_districts = raw.get("districts", [])
	_cache_phase = 2 if _cache_raw_districts.size() > 0 else 3


func setup(camera: Camera2D) -> void:
	_shadow_packet.clear()
	_last_camera_pos=Vector2(INF,INF)
	_last_camera_zoom=Vector2.ZERO
	_last_view_extent=Vector2.ZERO
	_camera = camera
	queue_redraw()


func _ready() -> void:
	z_index = -10
	_load_data()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	if consume_view_change(_camera.global_position,_camera.zoom,get_viewport_rect().size):
		queue_redraw()


## 视口不变不重绘；缩放影响裁剪半径，不能只检查位置。
func consume_view_change(pos: Vector2, zoom: Vector2, extent: Vector2) -> bool:
	# 线性及有界径向投影的相机导数均不超过 perspective_k。
	# 64px上界小于裁剪余量，避免远景误差预算推迟视口入场。
	var roof_scale := maxf(absf(zoom.x), absf(zoom.y)) * absf(perspective_k)
	var threshold := REDRAW_DIST_THRESHOLD
	if redraw_roof_error_px > 0.0:
		threshold = minf(64.0, redraw_roof_error_px / maxf(roof_scale, 0.0001))
	if pos.distance_to(_last_camera_pos)<threshold and zoom==_last_camera_zoom and extent==_last_view_extent:
		return false
	_last_camera_pos=pos
	_last_camera_zoom=zoom
	_last_view_extent=extent
	return true


func _load_data() -> void:
	_shadow_packet.clear()
	if _loaded:
		return
	_loaded = true

	# 优先使用预热缓存（BuildingPreloader 在进游戏前已经准备好）
	# UGC 注入生效时即使为空也用缓存 —— 绝不回退官方 JSON（幽灵楼 bug）
	if cache_is_ready() and (_ugc_active or not _cache_entries.is_empty()):
		_districts = _cache_entries
		print("[BuildingRenderer] using prewarmed cache (%d districts%s)" % [_districts.size(), " / UGC" if _ugc_active else ""])
		return

	# 兜底：没有预热（如直接打开 survivor_mode 调试）— 同步处理
	# 同时把结果灌进静态缓存，让 is_position_blocked_at_altitude 等查询 API 也能用
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("[BuildingRenderer] no data at %s — skip" % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if raw == null or not (raw is Dictionary):
		push_warning("[BuildingRenderer] data parse failed")
		return
	for d_raw in raw.get("districts", []):
		var entry = _build_entry_static(d_raw)
		if entry != null:
			_districts.append(entry)
	# 灌进静态缓存（让查询 API 同步生效）
	_cache_entries = _districts
	_cache_phase = 3
	_finalize_cache()
	print("[BuildingRenderer] synchronous load %d districts" % _districts.size())


## 静态版 _build_entry — 用 PRELOAD_* 常量代替 instance @export
## 缓存预热和兜底同步加载都走这条路径，保持一致
static func _build_entry_static(d_raw: Dictionary):
	var fp_raw: Array = d_raw.get("footprint", [])
	if fp_raw.size() < 3:
		return null
	var max_real_h: float = float(d_raw.get("max_real_h", 30.0))

	var fp := PackedVector2Array()
	fp.resize(fp_raw.size())
	var cx := 0.0
	var cy := 0.0
	for i in fp_raw.size():
		var p: Array = fp_raw[i]
		var v := Vector2(p[0], p[1])
		fp[i] = v
		cx += v.x
		cy += v.y
	var center := Vector2(cx / fp.size(), cy / fp.size())

	var normals := PackedVector2Array()
	normals.resize(fp.size())
	for i in fp.size():
		var a := fp[i]
		var b := fp[(i + 1) % fp.size()]
		var edge := b - a
		var n := Vector2(-edge.y, edge.x).normalized()
		var mid := (a + b) * 0.5
		if n.dot(mid - center) < 0.0:
			n = -n
		normals[i] = n

	var tri := Geometry2D.triangulate_polygon(fp)
	if tri.is_empty():
		return null

	var shadow_poly: PackedVector2Array
	var shadow_tri: PackedInt32Array
	if PRELOAD_SHADOW_EXPAND_PX > 0.0:
		var offset_results := Geometry2D.offset_polygon(fp, PRELOAD_SHADOW_EXPAND_PX, Geometry2D.JOIN_MITER)
		if offset_results.size() > 0:
			var biggest: PackedVector2Array = offset_results[0]
			for arr in offset_results:
				if arr.size() > biggest.size():
					biggest = arr
			shadow_poly = biggest
			shadow_tri = Geometry2D.triangulate_polygon(shadow_poly)
		else:
			shadow_poly = fp
			shadow_tri = tri
	else:
		shadow_poly = fp
		shadow_tri = tri

	# bbox for fast spatial culling（碰撞查询用）
	var bb_min := Vector2(INF, INF)
	var bb_max := Vector2(-INF, -INF)
	for v in fp:
		bb_min.x = minf(bb_min.x, v.x)
		bb_min.y = minf(bb_min.y, v.y)
		bb_max.x = maxf(bb_max.x, v.x)
		bb_max.y = maxf(bb_max.y, v.y)
	var bbox := Rect2(bb_min, bb_max - bb_min)

	return {
		"footprint": fp,
		"tri_indices": tri,
		"center": center,
		"h_visual": max_real_h * PRELOAD_DISTRICT_H_SCALE,
		"edge_normals": normals,
		"shadow_poly": shadow_poly,
		"shadow_tri": shadow_tri,
		"bbox": bbox,
		"max_real_h": max_real_h,
	}


# ══════════════════════════════════════════════
#  碰撞查询 API（导弹遮挡 / 后续导航避障用）
# ══════════════════════════════════════════════

## 检查世界坐标 pos 是否在任意一个街区 footprint 内
## 性能：bbox 预筛 + Geometry2D.is_point_in_polygon
## 调用方应自己根据高度档位判断要不要查（详见 MissileManager）
static func is_position_inside_building(pos: Vector2) -> bool:
	# O(1) 早退：不在城市 bbox 内（水面/外围 95% 子弹直接走这条）
	if _cache_max_h_global > 0.0 and not _cache_world_bbox.has_point(pos):
		return false
	for entry in _cache_entries:
		var bbox: Rect2 = entry["bbox"]
		if not bbox.has_point(pos):
			continue
		var fp: PackedVector2Array = entry["footprint"]
		if Geometry2D.is_point_in_polygon(pos, fp):
			return true
	return false


## 同 is_position_inside_building，但带最大高度过滤
## 只有当某个街区的 max_real_h >= my_altitude_m 时才视为遮挡
## 用于导弹/飞机的"高于此楼时不会被挡"判定
##
## 性能：两层 O(1) 早退（高过最高楼 / 不在城市 bbox 内），适合 AA/CIWS 高频调用
static func is_position_blocked_at_altitude(pos: Vector2, altitude_m: float) -> bool:
	# O(1) 早退 1：高过任何楼
	if altitude_m > _cache_max_h_global:
		return false
	# O(1) 早退 2：不在城市 bbox 内
	if _cache_max_h_global > 0.0 and not _cache_world_bbox.has_point(pos):
		return false
	for entry in _cache_entries:
		var max_h: float = entry["max_real_h"]
		if altitude_m > max_h:
			continue
		var bbox: Rect2 = entry["bbox"]
		if not bbox.has_point(pos):
			continue
		var fp: PackedVector2Array = entry["footprint"]
		if Geometry2D.is_point_in_polygon(pos, fp):
			return true
	return false


func _draw() -> void:
	var trace := PerfBuckets.frame_trace_enabled
	var started := Time.get_ticks_usec() if trace else 0
	_draw_visible_districts()
	if trace:
		PerfBuckets.tick("building_draw", Time.get_ticks_usec() - started)


func _draw_visible_districts() -> void:
	if _camera == null or _districts.is_empty():
		return

	var cam_pos := _camera.global_position
	var view_size: Vector2 = get_viewport_rect().size / maxf(_camera.zoom.x, 0.01)
	var cull_radius: float = view_size.length() * 0.6 + 300.0
	var cull_radius_sq := cull_radius * cull_radius
	var ci := get_canvas_item()

	var visible: Array = []
	var visible_sources := PackedInt32Array()
	for source in _districts.size():
		if _volume_hidden.has(source):
			continue
		var d: Dictionary = _districts[source]
		var center: Vector2 = d["center"]
		var d_sq := center.distance_squared_to(cam_pos)
		if d_sq > cull_radius_sq:
			continue
		visible.append({"d": d, "d_sq": d_sq})
		visible_sources.append(source)

	# Pass 1: 所有阴影合并到 1 个 submit（不需排序，画在最底；半透明叠加由 GPU blend 处理）
	var packet := shadow_packet(visible, visible_sources)
	if not packet.indices.is_empty():
		TrianglePacket.submit_arrays(ci, packet.indices, packet.vertices, packet.colors)

	# Pass 2: 伪 3D 街区（远 → 近排序）
	visible.sort_custom(func(x, y): return x["d_sq"] > y["d_sq"])
	for entry in visible:
		_draw_one(ci, entry["d"], cam_pos)


## 单槽实例缓存，源几何加载后不可变；样式/可见集变化失效。
func shadow_packet(visible: Array, sources: PackedInt32Array) -> Dictionary:
	var shadow_screen_offset := -light_dir * shadow_offset_px
	if cache_shadow_geometry and not _shadow_packet.is_empty() and sources == _shadow_sources \
			and shadow_screen_offset == _shadow_offset and shadow_color == _shadow_tint:
		return _shadow_packet
	var sh_verts := PackedVector2Array()
	var sh_colors := PackedColorArray()
	var sh_indices := PackedInt32Array()
	for entry in visible:
		var d: Dictionary = entry["d"]
		var sp: PackedVector2Array = d["shadow_poly"]
		var st: PackedInt32Array = d["shadow_tri"]
		if st.is_empty():
			continue
		var base := sh_verts.size()
		for v in sp:
			sh_verts.append(v + shadow_screen_offset)
			sh_colors.append(shadow_color)
		for idx in st:
			sh_indices.append(idx + base)
	shadow_cache_builds += 1
	var result := {"indices": sh_indices, "vertices": sh_verts, "colors": sh_colors}
	if cache_shadow_geometry:
		_shadow_sources = sources.duplicate()
		_shadow_offset = shadow_screen_offset
		_shadow_tint = shadow_color
		_shadow_packet = result
	else:
		_shadow_packet.clear()
	return result


## 单街区渲染：把所有墙 + 楼顶合并到 1 个 triangle_array submit，描边用 1 个 polyline
## 之前每街区 ~13 calls，现在 2 calls，~6.5x 减少
func _draw_one(ci: RID, d: Dictionary, cam_pos: Vector2) -> void:
	var fp: PackedVector2Array = d["footprint"]
	var tri: PackedInt32Array = d["tri_indices"]
	var normals: PackedVector2Array = d["edge_normals"]
	var center: Vector2 = d["center"]
	var h_visual: float = d["h_visual"]

	var roof_offset := (center - cam_pos) * perspective_k + Vector2(0, -h_visual * 0.25)
	if bounded_roof_projection:
		roof_offset = bounded_roof_offset(center - cam_pos, h_visual, perspective_k)
	var n_pts := fp.size()
	var roof_pts := PackedVector2Array()
	roof_pts.resize(n_pts)
	for i in n_pts:
		roof_pts[i] = fp[i] + roof_offset

	# 合并 buffer：墙先入，再入楼顶（painter's order：墙在下，顶在上）
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# === 墙（每堵 = 4 vert + 2 tri = 6 indices）===
	for i in n_pts:
		var n: Vector2 = normals[i]
		if n.dot(roof_offset) > 0.0:
			continue  # 背面剔除
		var i_next := (i + 1) % n_pts
		var lit_t: float = clampf(n.dot(light_dir) * 0.5 + 0.5, 0.0, 1.0)
		var col := wall_shade_color.lerp(wall_lit_color, lit_t)
		var base := verts.size()
		verts.append(fp[i])
		verts.append(fp[i_next])
		verts.append(roof_pts[i_next])
		verts.append(roof_pts[i])
		colors.append(col); colors.append(col); colors.append(col); colors.append(col)
		indices.append(base);     indices.append(base + 1); indices.append(base + 2)
		indices.append(base);     indices.append(base + 2); indices.append(base + 3)

	# === 楼顶（按预算的三角化索引）===
	var roof_base := verts.size()
	for v in roof_pts:
		verts.append(v)
		colors.append(roof_color)
	for idx in tri:
		indices.append(idx + roof_base)

	if not indices.is_empty():
		TrianglePacket.submit_arrays(ci, indices, verts, colors)

	# === 描边：单个闭合 polyline（n_pts+1 个点，最后回到起点）===
	var outline := PackedVector2Array()
	outline.resize(n_pts + 1)
	for i in n_pts:
		outline[i] = roof_pts[i]
	outline[n_pts] = roof_pts[0]
	draw_polyline(outline, roof_outline_color, 1.0, true)


## 仅改变表现投影；连续饱和防止远景侧墙无限拉长，不写源高度/碰撞。
static func bounded_roof_offset(delta: Vector2, visual_height: float, strength: float) -> Vector2:
	var height := maxf(visual_height, 0.0)
	if height == 0.0:
		return Vector2.ZERO
	var radial := delta * strength
	var cap := height * 0.5
	return radial / sqrt(1.0 + radial.length_squared() / (cap * cap)) + Vector2(0, -height * 0.25)
