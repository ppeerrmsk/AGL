class_name TacticalMap
extends CanvasLayer

## 战术地图（Tab 打开）
##
## P2：地图缩略图 + 战区圆（A/B/C/D + Boss）+ 玩家位置 + 悬停/点击选区
## 点击可选战区 → 发信号 zone_selected → survivor_mode 关闭地图 + 激活屏外箭头
## 奖励预览暂时只显示占位文本，具体奖励池由 P3 实现

signal zone_selected(zone_id: StringName)
## 点击地图空白处（非战区）：下达巡航航点。world_pos 已反算成世界坐标。
signal nav_point_selected(world_pos: Vector2)
## 地图上右键：取消当前巡航指令（清航点标记）。
signal nav_cleared()

const BG_COLOR := Color(0.02, 0.03, 0.04, 0.92)
const GRID_COLOR := Color(0.15, 0.35, 0.35, 0.35)
const FRAME_COLOR := Color(0.55, 0.85, 0.85, 0.8)
const TEXT_COLOR := Color(0.7, 0.95, 0.95, 0.95)
## 阵营色走 FactionPalette（spec global-awareness-roe §2.7 订正：蓝=玩家直属 / 绿=中立·第三方）
const PLAYER_COLOR := Color(0.35, 0.65, 1.0, 1.0)   ## 玩家小队 蓝（= COL_FRIEND_PLAYER 系）
const ALLY_COLOR := Color(0.35, 0.82, 0.42, 1.0)    ## 第三方/中立 绿（= COL_FRIEND_ALLY）
const NAV_MARKER_COLOR := Color(1.0, 0.85, 0.3, 1.0)  ## 巡航航点标记（琥珀色十字+脉冲环）

# 战区状态颜色
const ZONE_AVAILABLE := Color(0.8, 0.25, 0.25, 0.75)
const ZONE_AVAILABLE_FILL := Color(0.7, 0.2, 0.2, 0.15)
const ZONE_LOCKED := Color(0.45, 0.45, 0.45, 0.55)
const ZONE_LOCKED_FILL := Color(0.3, 0.3, 0.3, 0.10)
const ZONE_SELECTED := Color(0.4, 1.0, 0.5, 0.95)
const ZONE_SELECTED_FILL := Color(0.3, 0.8, 0.4, 0.20)
const ZONE_CLEARED := Color(0.35, 0.55, 0.8, 0.8)
const ZONE_CLEARED_FILL := Color(0.2, 0.4, 0.7, 0.15)
const ZONE_BOSS := Color(0.95, 0.35, 0.8, 0.9)
const ZONE_BOSS_FILL := Color(0.7, 0.2, 0.6, 0.20)

var _root: Control
var _map_panel: Control
var _info_label: RichTextLabel
var _map_rect: Rect2
var _world_rect: Rect2
var _player: Aircraft
var _zones: ZoneData
var _hover_zone_id: StringName = &""
var _nav_marker_world: Vector2 = Vector2.INF  ## 当前巡航航点标记（世界坐标，INF=无）。选战区时清除。
var _is_open: bool = false
var _adbs: AdbsManager = null  ## 用于在缩略图上画 ADBS 目标实时位置
var _docks: Array = []         ## 停靠点列表（DockPoint，spec zone-reward-docking）
# ── 底部"随机战场简报" + 右下"操作指南" ──
const _TIP_KEYS: Array[String] = [
	"TACTICAL_TIP_BOUNDARY",
	"TACTICAL_TIP_DIFFICULTY",
	"TACTICAL_TIP_WEAPON_SWAP",
	"TACTICAL_TIP_FLARE",
	"TACTICAL_TIP_ALT_HIGH",
	"TACTICAL_TIP_ALT_LOW",
	"TACTICAL_TIP_ALT_CLOUDS",
	"TACTICAL_TIP_SENTINEL",
	"TACTICAL_TIP_STAMINA",
	"TACTICAL_TIP_TURN_RADIUS",
	"TACTICAL_TIP_CORNER_SPEED",
	"TACTICAL_TIP_MISSILE_RANGE",
	"TACTICAL_TIP_MISSILE_SWEET_SPOT",
	"TACTICAL_TIP_CRANK",
	"TACTICAL_TIP_RELOAD",
]
const TIP_BORDER := Color(0.85, 0.25, 0.25, 0.9)
const TIP_FILL := Color(0.15, 0.04, 0.04, 0.55)
const CONTROLS_BORDER := Color(0.35, 0.75, 1.0, 0.9)
const CONTROLS_FILL := Color(0.04, 0.09, 0.14, 0.55)
var _tip_label: RichTextLabel
var _last_tip_idx: int = -1
# ── 左侧"已激活技能"面板 ──
var _game_scene: Node = null              ## survivor_mode，提供 upgrade_stacks
var _upgrades_list: VBoxContainer
var _upgrade_detail: RichTextLabel
var _axis_panel: VBoxContainer            ## 三轴常驻面板（spec evolution-attribute-gates §3.2）
var _status_panel: VBoxContainer          ## 底部状态块：当前加成汇总 + 机体数据（y2k 终端风）

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()

func setup(world_rect: Rect2, player: Aircraft, zones: ZoneData, game_scene: Node = null) -> void:
	_world_rect = world_rect
	_player = player
	_zones = zones
	_game_scene = game_scene

func set_adbs(adbs: AdbsManager) -> void:
	_adbs = adbs

func set_docks(docks: Array) -> void:
	_docks = docks
	if _map_panel:
		_map_panel.queue_redraw()

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open: close()
	else: open()

func open() -> void:
	_is_open = true
	_root.visible = true
	AudioManager.set_music_muffled(true)
	_refresh_upgrades_list()
	_roll_random_tip()
	# 暂停与淡入统一交给表演导演（时间的唯一入口，spec ui-transition §2.2）
	Presentation.present(self, "panel_in")

func close() -> void:
	_is_open = false
	AudioManager.set_music_muffled(false)
	_roll_random_tip()
	# 状态恢复已全部完成，dismiss 只是视觉尾巴（解暂停在 panel_out 第 0 帧）
	Presentation.dismiss(self, "panel_out")

## 表演导演的错开出入场元素（spec ui-transition §4.3）
func get_transition_elements() -> Array[Control]:
	# 必须显式构造 typed array —— `[_root] if _root else []` 的无类型字面量
	# 无法转成 Array[Control]，运行时报错后会静默退化到导演的兜底路径
	var out: Array[Control] = []
	if _root:
		out.append(_root)
	return out

## 从 _TIP_KEYS 随机抽一条，尽量不与上次重复
func _roll_random_tip() -> void:
	if not _tip_label or _TIP_KEYS.is_empty():
		return
	var idx := randi() % _TIP_KEYS.size()
	if _TIP_KEYS.size() > 1 and idx == _last_tip_idx:
		idx = (idx + 1) % _TIP_KEYS.size()
	_last_tip_idx = idx
	var prefix: String = tr("TACTICAL_TIP_PREFIX")
	_tip_label.text = "[color=#ff8080][font_size=10]%s[/font_size][/color]  %s" % [prefix, tr(_TIP_KEYS[idx])]

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	_root.add_child(bg)

	var title := Label.new()
	title.anchor_right = 1.0
	title.offset_top = 30
	title.offset_bottom = 70
	title.text = tr("TACTICAL_MAP_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_root.add_child(title)

	var sub := Label.new()
	sub.anchor_right = 1.0
	sub.offset_top = 68
	sub.offset_bottom = 95
	sub.text = tr("TACTICAL_MAP_SUBTITLE")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.6))
	_root.add_child(sub)

	# 主缩略图（居中方形）
	_map_panel = Control.new()
	_map_panel.anchor_left = 0.5
	_map_panel.anchor_right = 0.5
	_map_panel.anchor_top = 0.5
	_map_panel.anchor_bottom = 0.5
	_map_panel.offset_left = -340
	_map_panel.offset_right = 340
	_map_panel.offset_top = -340
	_map_panel.offset_bottom = 340
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_panel.clip_contents = true  # 裁剪所有绘制到面板矩形内（底图会自然被切齐）
	_map_panel.draw.connect(_on_map_draw)
	_map_panel.gui_input.connect(_on_map_gui_input)
	_map_panel.mouse_exited.connect(func(): _hover_zone_id = &""; _refresh_info(); _map_panel.queue_redraw())
	_root.add_child(_map_panel)
	_map_panel.queue_redraw()

	# 每 0.1 秒刷缩略图（玩家位置移动）
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(func(): _map_panel.queue_redraw())
	_map_panel.add_child(timer)

	# 右侧信息面板（悬停战区 + 奖励提示占位）
	_info_label = RichTextLabel.new()
	_info_label.anchor_left = 0.5
	_info_label.anchor_right = 0.5
	_info_label.anchor_top = 0.5
	_info_label.offset_left = 360
	_info_label.offset_right = 720
	_info_label.offset_top = -340
	_info_label.offset_bottom = 340
	_info_label.bbcode_enabled = true
	_info_label.scroll_active = false
	_info_label.add_theme_font_size_override("normal_font_size", 13)
	_info_label.add_theme_color_override("default_color", TEXT_COLOR)
	_root.add_child(_info_label)
	_refresh_info()

	# 左侧"已激活技能"面板（镜像右侧 info_label 的位置）
	_build_upgrades_panel()

	# 底部"随机战场简报"红框（每次开关面板换一条）
	_build_tip_banner()

	# 右下"操作指南"蓝框（常驻）
	_build_controls_panel()

	# 底部提示
	var hint := Label.new()
	hint.anchor_right = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_top = 1.0
	hint.offset_top = -40
	hint.offset_bottom = -15
	hint.text = tr("TACTICAL_MAP_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.55))
	_root.add_child(hint)

# ══════════════════════════════════════════════
#  缩略图绘制
# ══════════════════════════════════════════════

func _on_map_draw() -> void:
	MapGeography.ensure_ready()
	_ensure_minimap_basemap()
	var size := _map_panel.size
	_map_rect = Rect2(Vector2.ZERO, size)
	# 底色 = 海（如果有底图 PNG 覆盖，下面会盖住）
	_map_panel.draw_rect(_map_rect, MapGeography.SEA_COLOR)
	# 底图 PNG（如果存在）
	_draw_minimap_basemap(size)
	# 矢量细节层（只在没底图时才画 OSM 矢量，避免重复）
	if _mm_basemap_tex == null:
		_draw_geography(size)
		_draw_cities(size)
	# 框
	_map_panel.draw_rect(_map_rect, FRAME_COLOR, false, 2.0)

	# 战区圆 + 标签
	if _zones:
		_draw_zones(size)
		_draw_boss(size)

	# ADBS 目标实时位置（黄色菱形 + 朝向短线，带脉冲）
	_draw_adbs_markers(size)

	# 停靠点（机场/航母，青绿方框 + 短跑道线）
	_draw_dock_markers(size)

	# 巡航航点标记（玩家点空白处留下的目标点）
	_draw_nav_marker(size)

	# 玩家光点
	if _player and is_instance_valid(_player) and _world_rect.size.x > 0.0:
		var p := _world_to_map(_player.global_position, size)
		_map_panel.draw_circle(p, 5.0, PLAYER_COLOR)
		var hd := _player.heading
		var tip := p + Vector2(sin(hd), -cos(hd)) * 14.0
		_map_panel.draw_line(p, tip, Color(PLAYER_COLOR.r, PLAYER_COLOR.g, PLAYER_COLOR.b, 0.9), 2.0)

	_map_panel.draw_string(
		ThemeDB.fallback_font, Vector2(size.x * 0.5 - 5, 14),
		"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.6)
	)

	# 最后叠一层扫描线 + 暗角，形成 CRT 战术屏效果
	_draw_minimap_scanlines_and_vignette(size)

## 缩略图：用 OSM 预烘焙 land mask 作为陆地（和主地图保持一致）
const MINIMAP_LAND_COLOR := Color(0.32, 0.35, 0.27, 1.0)
const MINIMAP_URBAN_COLOR := Color(0.42, 0.38, 0.28, 1.0)
const MINIMAP_ROAD_COLOR := Color(0.86, 0.78, 0.55, 1.0)

## ---- 底图 PNG 缓存（和主地图共享同一张图 + 元数据）----
const MM_BASEMAP_PNG := "res://resources/maps/tokyo_bay_bg.png"
const MM_BASEMAP_META := "res://resources/maps/tokyo_bay_bg.json"
var _mm_basemap_tex: Texture2D = null
var _mm_basemap_world_rect: Rect2 = Rect2()
var _mm_basemap_loaded := false

func _ensure_minimap_basemap() -> void:
	if _mm_basemap_loaded:
		return
	_mm_basemap_loaded = true
	if not ResourceLoader.exists(MM_BASEMAP_PNG):
		return
	var f := FileAccess.open(MM_BASEMAP_META, FileAccess.READ)
	if f == null:
		return
	var meta = JSON.parse_string(f.get_as_text())
	f.close()
	if meta == null:
		return
	var bbox: Dictionary = meta.get("bbox_ll", {})
	var center_ll: Array = meta.get("game_world_center_latlon", [35.44, 139.76])
	var m_per_lat: float = float(meta.get("game_world_meters_per_degree_lat", 111000.0))
	var m_per_lon: float = float(meta.get("game_world_meters_per_degree_lon_at_center", 111000.0 * cos(deg_to_rad(35.44))))
	var px_per_m: float = float(meta.get("game_world_px_per_meter", 0.5))
	var lat_min: float = float(bbox.get("lat_min", 0))
	var lat_max: float = float(bbox.get("lat_max", 0))
	var lon_min: float = float(bbox.get("lon_min", 0))
	var lon_max: float = float(bbox.get("lon_max", 0))
	var cx: float = float(center_ll[1])
	var cy: float = float(center_ll[0])
	var x0 := (lon_min - cx) * m_per_lon * px_per_m
	var x1 := (lon_max - cx) * m_per_lon * px_per_m
	var y0 := -(lat_max - cy) * m_per_lat * px_per_m
	var y1 := -(lat_min - cy) * m_per_lat * px_per_m
	_mm_basemap_world_rect = Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))
	_mm_basemap_tex = load(MM_BASEMAP_PNG) as Texture2D
	print("[TacticalMap] minimap basemap loaded: %s rect=%s" % [
		_mm_basemap_tex.get_size() if _mm_basemap_tex else "null", _mm_basemap_world_rect,
	])

## 把底图按 world → minimap 投影铺在缩略图上
## 色调和主地图保持一致：中性偏暗，不加绿滤镜
const MINIMAP_BASEMAP_MODULATE := Color(0.72, 0.76, 0.75, 1.0)
func _draw_minimap_basemap(size: Vector2) -> void:
	if _mm_basemap_tex == null:
		return
	# 把 basemap world rect 换到 minimap 屏幕坐标
	var p0 := _world_to_map(_mm_basemap_world_rect.position, size)
	var p1 := _world_to_map(_mm_basemap_world_rect.position + _mm_basemap_world_rect.size, size)
	var dst := Rect2(p0, p1 - p0)
	_map_panel.draw_texture_rect(_mm_basemap_tex, dst, false, MINIMAP_BASEMAP_MODULATE)

## 扫描线后绘制覆盖层：半透明暗线 + 暗角，不用 shader，全 draw_line
## 在所有内容画完之后调，叠在最上面做 CRT 感
const SCANLINE_SPACING_PX := 3.0
const SCANLINE_COLOR := Color(0.0, 0.0, 0.0, 0.18)
const VIGNETTE_RINGS: Array[Dictionary] = [
	{"inset": 0.0,  "alpha": 0.35},
	{"inset": 20.0, "alpha": 0.18},
	{"inset": 40.0, "alpha": 0.08},
]
func _draw_minimap_scanlines_and_vignette(size: Vector2) -> void:
	var y := 0.0
	while y < size.y:
		_map_panel.draw_line(Vector2(0, y), Vector2(size.x, y), SCANLINE_COLOR, 1.0)
		y += SCANLINE_SPACING_PX
	# 暗角（四边矩形层叠）
	for r_any in VIGNETTE_RINGS:
		var r: Dictionary = r_any
		var inset: float = r.inset
		var a: float = r.alpha
		var col := Color(0.0, 0.0, 0.0, a)
		# 上
		_map_panel.draw_rect(Rect2(0, 0, size.x, inset + 1), col)
		# 下
		_map_panel.draw_rect(Rect2(0, size.y - inset - 1, size.x, inset + 1), col)
		# 左
		_map_panel.draw_rect(Rect2(0, inset, inset + 1, size.y - 2 * inset), col)
		# 右
		_map_panel.draw_rect(Rect2(size.x - inset - 1, inset, inset + 1, size.y - 2 * inset), col)

## ---- 变换缓存（size 不变就不重算） ----
## 之前每 0.1 秒重绘时都在重新 _map_poly 变换 ~1300 个多边形的所有顶点，
## 相当于 200k Vector2 分配/秒 + 2500+ draw calls/秒 —— 大幅影响 FPS。
## 这里缓存 size 对应的已变换多边形，只在 size 变化时重建。
var _mm_cache_size: Vector2 = Vector2.ZERO
var _mm_cache_land: Array = []       # Array[PackedVector2Array]
var _mm_cache_urban: Array = []
var _mm_cache_roads: Array = []
var _mm_cache_aqualine: PackedVector2Array = PackedVector2Array()

func _rebuild_minimap_geometry_cache(size: Vector2) -> void:
	if _mm_cache_size == size:
		return
	_mm_cache_size = size
	_mm_cache_land.clear()
	_mm_cache_urban.clear()
	_mm_cache_roads.clear()
	var t0 := Time.get_ticks_msec()
	for poly_any in MapGeography.get_land_mask_polygons():
		var m := _map_poly(poly_any, size)
		if m.size() >= 3:
			_mm_cache_land.append(m)
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.size() < 3:
			continue
		var m2 := _map_poly(poly, size)
		if m2.size() >= 3:
			_mm_cache_urban.append(m2)
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		var m3 := _map_poly(pts, size)
		if m3.size() >= 2:
			_mm_cache_roads.append(m3)
	var aq: PackedVector2Array = MapGeography.AQUALINE_PATH
	if aq.size() >= 2:
		_mm_cache_aqualine = _map_poly(aq, size)
	else:
		_mm_cache_aqualine = PackedVector2Array()
	print("[TacticalMap] rebuilt mm geo cache @size=%s land=%d urban=%d roads=%d (%dms)" % [
		size, _mm_cache_land.size(), _mm_cache_urban.size(), _mm_cache_roads.size(),
		Time.get_ticks_msec() - t0,
	])

## 缩略图：海岸线地图（陆地填充）
func _draw_geography(size: Vector2) -> void:
	_rebuild_minimap_geometry_cache(size)
	for poly_any in _mm_cache_land:
		_map_panel.draw_colored_polygon(poly_any, MINIMAP_LAND_COLOR)

## 缩略图：城区多边形 + 高速（都用缓存，道路用单次 draw_polyline）
func _draw_cities(size: Vector2) -> void:
	for poly_any in _mm_cache_urban:
		_map_panel.draw_colored_polygon(poly_any, MINIMAP_URBAN_COLOR)
	# draw_polyline：单次 GPU 调用画整条线，比 per-segment draw_line 快 ~3×
	for mapped_any in _mm_cache_roads:
		var mapped: PackedVector2Array = mapped_any
		if mapped.size() >= 2:
			_map_panel.draw_polyline(mapped, MINIMAP_ROAD_COLOR, 1.0)
	if _mm_cache_aqualine.size() >= 2:
		for i in range(_mm_cache_aqualine.size() - 1):
			_map_panel.draw_dashed_line(_mm_cache_aqualine[i], _mm_cache_aqualine[i + 1], MapGeography.AQUALINE_COLOR, 1.0, 4.0)

func _map_poly(src: PackedVector2Array, size: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in src:
		out.append(_world_to_map(p, size))
	return out

func _draw_zones(size: Vector2) -> void:
	for z in ZoneData.ZONES:
		var zid: StringName = z["id"]
		if _should_hide_zone(zid):
			continue
		_draw_one_zone(z, zid, size)

func _draw_boss(size: Vector2) -> void:
	if not _zones:
		return
	var z := _zones.boss_zone
	var zid: StringName = z["id"]
	if _should_hide_zone(zid):
		return
	_draw_one_zone(z, zid, size)

## 未解锁（LOCKED）的战区/BOSS 在玩家还没攻克前完全不显示——不剧透
## BOSS 解锁后：其余战区（含 CLEARED / AVAILABLE）全部隐藏，地图只剩 BOSS 圈
##   早先只在 is_boss_phase（玩家已选中 BOSS）才隐藏其他，导致 BOSS 一出来但 CLEARED 标志
##   还挂着直到玩家点 BOSS 才消失 —— 与"BOSS 一出现其他就该消失"的预期不符
func _should_hide_zone(zid: StringName) -> bool:
	if not _zones:
		return true
	if _zones.boss_unlocked and zid != &"BOSS":
		return true
	return _zones.get_state(zid) == ZoneData.State.LOCKED

func _draw_one_zone(z: Dictionary, zid: StringName, size: Vector2) -> void:
	var state := _zones.get_state(zid) if _zones else ZoneData.State.LOCKED
	var color: Color
	var fill: Color
	match state:
		ZoneData.State.AVAILABLE:
			color = ZONE_BOSS if zid == &"BOSS" else ZONE_AVAILABLE
			fill = ZONE_BOSS_FILL if zid == &"BOSS" else ZONE_AVAILABLE_FILL
		ZoneData.State.SELECTED:
			color = ZONE_SELECTED
			fill = ZONE_SELECTED_FILL
		ZoneData.State.CLEARED:
			color = ZONE_CLEARED
			fill = ZONE_CLEARED_FILL
		_:
			color = ZONE_LOCKED
			fill = ZONE_LOCKED_FILL

	var c := _world_to_map(z["center"], size)
	var r: float = float(z["radius"]) * size.x / _world_rect.size.x
	_map_panel.draw_circle(c, r, fill)
	_map_panel.draw_arc(c, r, 0.0, TAU, 48, color, 2.0)

	# hover 高亮
	if _hover_zone_id == zid and state == ZoneData.State.AVAILABLE:
		_map_panel.draw_arc(c, r + 4.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.9), 2.0)

	# 标签 + 难度星（Boss 没难度概念，跳过星）
	var label_s: String = z["label"]
	_map_panel.draw_string(
		ThemeDB.fallback_font, c + Vector2(-6, 5),
		label_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color
	)
	# 战区奖励前置显示（spec zone-reward-docking §2.8）：图标字符 + 名称（圈下方）
	if zid != &"BOSS" and _zones \
			and (state == ZoneData.State.AVAILABLE or state == ZoneData.State.SELECTED):
		var rw: Dictionary = _zones.get_reward(zid)
		if not rw.is_empty():
			var glyph := "◆"
			match String(rw.get("kind", "")):
				"carrier": glyph = "⚓"
				"wingman": glyph = "✚"
				"weapon": glyph = "⌁"
			var rtxt := "%s %s" % [glyph, tr(String(rw.get("name", "")))]
			_map_panel.draw_string(ThemeDB.fallback_font, c + Vector2(-r, r + 13.0),
				rtxt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11,
				Color(0.85, 0.95, 0.90, 0.95))
	if zid != &"BOSS" and _zones and state != ZoneData.State.CLEARED:
		var difficulty: int = _zones.get_difficulty(zid)
		var stars: String = "★".repeat(difficulty)
		_map_panel.draw_string(
			ThemeDB.fallback_font, c + Vector2(-10, -r - 6),
			stars, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.7, 0.4, 0.9)
		)

## 在缩略图上画 ADBS 事件单位（轰炸机/直升机等）实时位置
func _draw_adbs_markers(size: Vector2) -> void:
	if not _adbs or _adbs.active_units.is_empty():
		return
	var pulse := 0.7 + 0.3 * (sin(Time.get_ticks_msec() * 0.006) * 0.5 + 0.5)
	var color := Color(1.0, 0.85, 0.2, pulse)  ## 黄色脉冲
	for u in _adbs.active_units:
		if not is_instance_valid(u) or u.is_destroyed:
			continue
		var pos := _world_to_map(u.global_position, size)
		# 菱形图标
		var r := 5.0
		_map_panel.draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -r),
			pos + Vector2(r, 0),
			pos + Vector2(0, r),
			pos + Vector2(-r, 0),
		]), color)
		# 朝向短线
		var hd: float = u.heading if "heading" in u else 0.0
		var tip := pos + Vector2(sin(hd), -cos(hd)) * 10.0
		_map_panel.draw_line(pos, tip, color, 1.5)

## 停靠点标记（spec zone-reward-docking）：青绿方框 + 中线（跑道意象）；航母停靠点跟随实时位置
func _draw_dock_markers(size: Vector2) -> void:
	# AWACS buff 圈（spec global-awareness-roe §2.6c：海绿圈内玩家锁定 ×3 / 导弹 ×1.25）
	var awacs: Aircraft = AwacsSupportEvent.active_awacs()
	if awacs != null:
		var apos := _world_to_map(awacs.global_position, size)
		var r_map: float = AwacsSupportEvent.BUFF_RADIUS_PX / _world_rect.size.x * size.x
		_map_panel.draw_arc(apos, r_map, 0.0, TAU, 64, Color(ALLY_COLOR, 0.55), 1.5)
		_map_panel.draw_circle(apos, 3.0, ALLY_COLOR)
	if _docks.is_empty():
		return
	var font := ThemeDB.fallback_font
	for d_any in _docks:
		var d := d_any as DockPoint
		if not is_instance_valid(d):
			continue
		var pos := _world_to_map(d.global_position, size)
		var is_carrier: bool = d.dock_kind == "carrier"
		var col := Color(0.55, 0.82, 1.0, 1.0) if is_carrier else Color(0.40, 0.96, 0.72, 1.0)
		# ── 图标（先画深色描边衬底，再画亮色主体，让它从浅底图跳出来）──
		if is_carrier:
			# 蓝青菱形（锚泊母舰）
			var d0 := 7.5
			_map_panel.draw_colored_polygon(PackedVector2Array([
				pos + Vector2(0, -d0), pos + Vector2(d0, 0),
				pos + Vector2(0, d0), pos + Vector2(-d0, 0)]), Color(0, 0, 0, 0.6))
			var d1 := 5.5
			_map_panel.draw_colored_polygon(PackedVector2Array([
				pos + Vector2(0, -d1), pos + Vector2(d1, 0),
				pos + Vector2(0, d1), pos + Vector2(-d1, 0)]), col)
		else:
			# 机场：跑道方框 + 中线
			var rw := 6.0
			var rh := 3.6
			_map_panel.draw_rect(Rect2(pos - Vector2(rw + 1, rh + 1),
				Vector2((rw + 1) * 2, (rh + 1) * 2)), Color(0, 0, 0, 0.6), false, 3.0)
			_map_panel.draw_rect(Rect2(pos - Vector2(rw, rh),
				Vector2(rw * 2, rh * 2)), col, false, 1.5)
			_map_panel.draw_line(pos + Vector2(-rw + 2, 0), pos + Vector2(rw - 2, 0), col, 1.5)
		# ── 名称标签：深色背板 + 亮字（和 HUD 数据标签同风格，保证浅底图上可读）──
		var txt := tr(d.display_name_key)
		var fsize := 11
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var lx := pos.x + 10.0
		if lx + tw + 4.0 > size.x:          # 贴右边界 → 名称改画标记左侧
			lx = pos.x - 10.0 - tw
		var ly := pos.y
		_map_panel.draw_rect(Rect2(lx - 3.0, ly - 8.0, tw + 6.0, 15.0), Color(0.05, 0.11, 0.10, 0.72))
		_map_panel.draw_string(font, Vector2(lx, ly + 3.5), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

## 画巡航航点标记：脉冲环 + 十字（琥珀色）。右键清除。
func _draw_nav_marker(size: Vector2) -> void:
	if _nav_marker_world == Vector2.INF or _world_rect.size.x <= 0.0:
		return
	var m := _world_to_map(_nav_marker_world, size)
	var pulse := 0.5 + 0.5 * (sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5)
	var ring_r := 7.0 + 4.0 * pulse
	var col := Color(NAV_MARKER_COLOR.r, NAV_MARKER_COLOR.g, NAV_MARKER_COLOR.b, 0.5 + 0.45 * pulse)
	_map_panel.draw_arc(m, ring_r, 0.0, TAU, 24, col, 1.5)
	# 十字
	_map_panel.draw_line(m + Vector2(-9, 0), m + Vector2(9, 0), col, 1.5)
	_map_panel.draw_line(m + Vector2(0, -9), m + Vector2(0, 9), col, 1.5)
	_map_panel.draw_circle(m, 2.0, NAV_MARKER_COLOR)

func _world_to_map(world_pos: Vector2, map_size: Vector2) -> Vector2:
	var norm := (world_pos - _world_rect.position) / _world_rect.size
	return Vector2(norm.x * map_size.x, norm.y * map_size.y)

func _map_to_world(map_pos: Vector2, map_size: Vector2) -> Vector2:
	var norm := Vector2(map_pos.x / map_size.x, map_pos.y / map_size.y)
	return _world_rect.position + norm * _world_rect.size

# ══════════════════════════════════════════════
#  交互
# ══════════════════════════════════════════════

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_map_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_clear_nav_marker()

## 左键：先试点战区，未命中战区则当作"下巡航航点"（点空白处）。
## 不关闭地图 —— 玩家可继续规划，标记会留在地图上（Tab/Esc 才关）。
func _handle_map_click(map_pos: Vector2) -> void:
	var zid := _zone_id_at(map_pos)
	if zid != &"":
		_try_click_zone(map_pos)
		return
	# 空白处：反算世界坐标 → 下巡航航点 + 留标记（不关图）
	if _world_rect.size.x <= 0.0:
		return
	var wp := _map_to_world(map_pos, _map_panel.size)
	_nav_marker_world = wp
	nav_point_selected.emit(wp)
	_map_panel.queue_redraw()

## 右键：取消当前巡航指令 + 清掉航点标记
func _clear_nav_marker() -> void:
	if _nav_marker_world == Vector2.INF:
		return
	_nav_marker_world = Vector2.INF
	nav_cleared.emit()
	_map_panel.queue_redraw()

func _update_hover(map_pos: Vector2) -> void:
	var new_hover := _zone_id_at(map_pos)
	if new_hover != _hover_zone_id:
		_hover_zone_id = new_hover
		_refresh_info()
		_map_panel.queue_redraw()

func _try_click_zone(map_pos: Vector2) -> void:
	var zid := _zone_id_at(map_pos)
	if zid == &"":
		return
	if not _zones:
		return
	# _zone_id_at 已跳过隐藏/LOCKED 的战区 → 能点到的都可前往（AVAILABLE/SELECTED/CLEARED）。
	# 导航与"任务选择状态机"解耦：每次点击都重新下达巡航指令（不管战区当前状态），
	# 仅 AVAILABLE 时才触发 select_zone（任务选择）。修复"飞过一次变 CLEARED 后再也点不动"。
	if _zones.get_state(zid) == ZoneData.State.AVAILABLE:
		_zones.select_zone(zid)
	# 选战区 = 巡航目标改为战区，清掉之前的空白航点标记（不关图）
	_nav_marker_world = Vector2.INF
	zone_selected.emit(zid)
	_map_panel.queue_redraw()

## 命中检测：返回 map_pos 所在的战区 id（就近），没命中或隐藏的都返回空
func _zone_id_at(map_pos: Vector2) -> StringName:
	if not _zones or _world_rect.size.x <= 0.0:
		return &""
	var size := _map_panel.size
	# Boss 优先级最高（仅在显示时命中）
	var bz := _zones.boss_zone
	if not _should_hide_zone(bz["id"]):
		var bc := _world_to_map(bz["center"], size)
		var br: float = float(bz["radius"]) * size.x / _world_rect.size.x
		if map_pos.distance_to(bc) <= br:
			return bz["id"]
	# 普通战区：隐藏的直接跳过
	for z in ZoneData.ZONES:
		if _should_hide_zone(z["id"]):
			continue
		var c := _world_to_map(z["center"], size)
		var r: float = float(z["radius"]) * size.x / _world_rect.size.x
		if map_pos.distance_to(c) <= r:
			return z["id"]
	return &""

# ══════════════════════════════════════════════
#  左侧"已激活技能"面板
# ══════════════════════════════════════════════

const _AXIS_ORDER: Array[String] = ["survival", "mobility", "missile", "secondary", "electronic_warfare"]
const _AXIS_TITLES := {
	"survival": "▸ 生存",
	"mobility": "▸ 机动",
	"missile": "▸ 导弹",
	"secondary": "▸ 副武器",
	"electronic_warfare": "▸ 电子战",
}
const _AXIS_COLORS := {
	"survival": Color(0.3, 0.7, 0.4),
	"mobility": Color(0.3, 0.6, 0.9),
	"missile": Color(0.9, 0.55, 0.25),
	"secondary": Color(0.9, 0.45, 0.45),
	"electronic_warfare": Color(0.7, 0.45, 0.85),
}

func _build_upgrades_panel() -> void:
	# 容器：左侧镜像 _info_label 的位置（offset_left=-720..-360）
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.offset_left = -720
	panel.offset_right = -360
	panel.offset_top = -340
	panel.offset_bottom = 340
	panel.add_theme_constant_override("separation", 8)
	_root.add_child(panel)

	var title := Label.new()
	title.text = tr("TACTICAL_MAP_UPGRADES_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# 三轴常驻面板（spec evolution-attribute-gates §3.2：点数/里程碑/下一档/路线倾向，只读）
	_axis_panel = VBoxContainer.new()
	_axis_panel.add_theme_constant_override("separation", 1)
	panel.add_child(_axis_panel)

	# 滚动列表（压缩给三轴明细/机体状态腾空间，2026-07-19 y2k 面板改版）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 170)
	panel.add_child(scroll)

	_upgrades_list = VBoxContainer.new()
	_upgrades_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrades_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_upgrades_list)

	# 详情区（hover 时填充）
	var det_label := Label.new()
	det_label.text = tr("TACTICAL_MAP_UPGRADES_HINT")
	det_label.add_theme_font_size_override("font_size", 11)
	det_label.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.55))
	panel.add_child(det_label)

	_upgrade_detail = RichTextLabel.new()
	_upgrade_detail.bbcode_enabled = true
	_upgrade_detail.scroll_active = false
	_upgrade_detail.fit_content = true
	_upgrade_detail.custom_minimum_size = Vector2(0, 90)
	_upgrade_detail.add_theme_font_size_override("normal_font_size", 12)
	_upgrade_detail.add_theme_color_override("default_color", TEXT_COLOR)
	panel.add_child(_upgrade_detail)
	_clear_upgrade_detail()

	# 底部状态块（2026-07-19 用户令）：当前加成汇总 + 机体实时数据（y2k 终端风）
	_status_panel = VBoxContainer.new()
	_status_panel.add_theme_constant_override("separation", 1)
	panel.add_child(_status_panel)

## 底部红色"战场简报"横幅：带红边、半透明深色背景，内嵌一行随机提示
func _build_tip_banner() -> void:
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.5
	holder.anchor_bottom = 0.5
	holder.offset_left = -340
	holder.offset_right = 340
	holder.offset_top = 350
	holder.offset_bottom = 420
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)

	var style := StyleBoxFlat.new()
	style.bg_color = TIP_FILL
	style.border_color = TIP_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)

	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.scroll_active = false
	_tip_label.fit_content = true
	_tip_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tip_label.offset_left = 12
	_tip_label.offset_right = -12
	_tip_label.offset_top = 8
	_tip_label.offset_bottom = -6
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_font_size_override("normal_font_size", 12)
	_tip_label.add_theme_color_override("default_color", Color(1.0, 0.88, 0.85, 0.95))
	holder.add_child(_tip_label)
	_roll_random_tip()

## 右下蓝色"操作指南"框：常驻，列玩家可用按键
func _build_controls_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CONTROLS_FILL
	style.border_color = CONTROLS_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	var bg := PanelContainer.new()
	bg.anchor_left = 1.0
	bg.anchor_right = 1.0
	bg.anchor_top = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = -280
	bg.offset_right = -20
	bg.offset_top = -260
	bg.offset_bottom = -60
	bg.add_theme_stylebox_override("panel", style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(inner)

	var title := Label.new()
	title.text = tr("TACTICAL_CONTROLS_TITLE")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", CONTROLS_BORDER)
	inner.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	inner.add_child(spacer)

	var rows: Array[String] = [
		"TACTICAL_CONTROLS_LMB",
		"TACTICAL_CONTROLS_RMB",
		"TACTICAL_CONTROLS_MMB",
		"TACTICAL_CONTROLS_WHEEL",
		"TACTICAL_CONTROLS_SPACE",
		"TACTICAL_CONTROLS_TAB",
		"TACTICAL_CONTROLS_ESC",
	]
	for key in rows:
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.scroll_active = false
		row.fit_content = true
		row.custom_minimum_size = Vector2(0, 18)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.text = tr(key)
		row.add_theme_font_size_override("normal_font_size", 12)
		row.add_theme_font_size_override("bold_font_size", 12)
		row.add_theme_color_override("default_color", Color(0.82, 0.92, 1.0, 0.9))
		inner.add_child(row)

func _refresh_upgrades_list() -> void:
	_refresh_axis_panel()
	_refresh_status_panel()
	if not _upgrades_list:
		return
	for child in _upgrades_list.get_children():
		child.queue_free()
	_clear_upgrade_detail()

## 三轴常驻面板（spec evolution-attribute-gates §3.2）：
## 每轴一行 = 轴名 + 点数 + ●○ 进度（到下一档刻度）+ 下一档预览；标题行 = 总点数 + 路线倾向。
func _refresh_axis_panel() -> void:
	if not _axis_panel:
		return
	for c in _axis_panel.get_children():
		c.queue_free()
	if not _game_scene or not "survivor_player" in _game_scene or _game_scene.survivor_player == null:
		return
	var sp = _game_scene.survivor_player
	var profile = _game_scene._player_profile if "_player_profile" in _game_scene else null
	# 标题：总点数/可得 + 路线倾向（最高轴；全 0 = 未定）
	var best: StringName = &""
	var best_v: int = 0
	for axis in SurvivorData.AXES:
		if sp.get_axis_points(axis) > best_v:
			best_v = sp.get_axis_points(axis)
			best = axis
	var route: String = tr("ATTR_ROUTE_NONE") if best == &"" \
		else tr("ATTR_ROUTE_FMT") % tr(str(SurvivorData.AXIS_I18N_KEY[best]))
	var head := Label.new()
	head.text = "%s %d/%d · %s" % [tr("ATTR_PANEL_TITLE"), sp.total_axis_points(),
		SurvivorData.axis_points_earnable(sp.level), route]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", TEXT_COLOR)
	_axis_panel.add_child(head)
	# 三轴量表（竖条分格视觉，2026-07-19 用户 mockup；里程碑刻度圈随档位亮起）
	var bars := AxisBarsPanel.new()
	bars.show_state(sp.axis_points, profile)
	bars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_axis_panel.add_child(bars)
	# 里程碑明细三列（2026-07-19 用户令：每档写明具体强化什么，不只留标题）
	# 三态：■ 已达成（轴色亮）｜▶ 下一档（白色高亮）｜□ 远档（轴色暗）
	_axis_panel.add_child(_y2k_header(tr("ATTR_MILESTONE_DETAIL")))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 5)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_axis_panel.add_child(grid)
	for axis in SurvivorData.AXES:
		var col: Color = SurvivorData.AXIS_COLORS.get(axis, TEXT_COLOR)
		var pts: int = sp.get_axis_points(axis)
		var vb := VBoxContainer.new()
		vb.custom_minimum_size = Vector2(114, 0)
		vb.add_theme_constant_override("separation", 0)
		grid.add_child(vb)
		var head_l := Label.new()
		head_l.text = "◤%s" % tr(str(SurvivorData.AXIS_I18N_KEY[axis]))
		head_l.add_theme_font_size_override("font_size", 11)
		head_l.add_theme_color_override("font_color", col)
		vb.add_child(head_l)
		var next_marked := false
		for m in SurvivorData.milestones_for(axis, profile):
			var tier: int = int(m["points"])
			var reached: bool = pts >= tier
			var mark: String
			var c: Color
			if reached:
				mark = "■"
				c = col
			elif not next_marked:
				next_marked = true
				mark = "▶"
				c = Color(1.0, 1.0, 1.0, 0.95)
			else:
				mark = "□"
				c = Color(col.r, col.g, col.b, 0.35)
			var row := Label.new()
			row.text = "%s%d│%s" % [mark, tier, _fmt_milestone_bonus(m)]
			row.add_theme_font_size_override("font_size", 10)
			row.add_theme_color_override("font_color", c)
			row.clip_text = true
			vb.add_child(row)

	if not _game_scene or not "upgrade_stacks" in _game_scene:
		var empty := Label.new()
		empty.text = tr("TACTICAL_MAP_UPGRADES_EMPTY")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_upgrades_list.add_child(empty)
		return

	var stacks: Dictionary = _game_scene.upgrade_stacks
	# 按 5 轴分桶
	var buckets: Dictionary = {}
	for axis in _AXIS_ORDER:
		buckets[axis] = []
	for u in SurvivorData.UPGRADES:
		var uid: String = u["id"]
		if stacks.get(uid, 0) <= 0:
			continue
		var cat: String = u.get("category", "survival")
		if not buckets.has(cat):
			buckets[cat] = []
		buckets[cat].append(u)

	var any_added := false
	for axis in _AXIS_ORDER:
		var bucket: Array = buckets.get(axis, [])
		if bucket.is_empty():
			continue
		any_added = true
		var axis_title := Label.new()
		axis_title.text = _AXIS_TITLES.get(axis, axis)
		axis_title.add_theme_font_size_override("font_size", 12)
		axis_title.add_theme_color_override("font_color", _AXIS_COLORS.get(axis, TEXT_COLOR))
		_upgrades_list.add_child(axis_title)
		for u in bucket:
			_upgrades_list.add_child(_make_upgrade_row(u, stacks))

	if not any_added:
		var empty := Label.new()
		empty.text = tr("TACTICAL_MAP_UPGRADES_EMPTY")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_upgrades_list.add_child(empty)

func _make_upgrade_row(u: Dictionary, stacks: Dictionary) -> Control:
	var uid: String = u["id"]
	var count: int = stacks.get(uid, 0)
	var max_s: int = int(u["max_stacks"])
	var is_evolved: bool = u.get("evolved", false)

	var row := Button.new()
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_size_override("font_size", 12)
	# 文字
	var prefix: String = "  ★ " if is_evolved else "    "
	var stk_text: String
	if uid == "executioner":
		stk_text = "  [%d]" % (_player.executioner_stacks if _player else 0)
	elif max_s > 1:
		stk_text = "  %d/%d" % [count, max_s]
	else:
		stk_text = ""
	row.text = "%s%s%s" % [prefix, tr(u["name"]), stk_text]
	if is_evolved:
		row.add_theme_color_override("font_color", Color(1.0, 0.83, 0.3))
	else:
		row.add_theme_color_override("font_color", TEXT_COLOR)
	# Hover 显示详情
	var u_capture := u
	row.mouse_entered.connect(func(): _show_upgrade_detail(u_capture))
	row.mouse_exited.connect(func(): _clear_upgrade_detail())
	return row

## 底部状态块（2026-07-19 用户令，y2k 终端风）：当前已生效加成汇总（按 stat 聚合）+ 机体实时数据
func _refresh_status_panel() -> void:
	if not _status_panel:
		return
	for c in _status_panel.get_children():
		c.queue_free()
	if not _game_scene or not "survivor_player" in _game_scene or _game_scene.survivor_player == null:
		return
	var sp = _game_scene.survivor_player
	var profile = _game_scene._player_profile if "_player_profile" in _game_scene else null
	# ── 当前加成（里程碑聚合：add 求和 / mult 连乘）──
	_status_panel.add_child(_y2k_header(tr("ATTR_CURRENT_BONUS")))
	var agg_add: Dictionary = {}
	var agg_mult: Dictionary = {}
	for axis in SurvivorData.AXES:
		var done: Array = sp.applied_milestones.get(axis, [])
		for m in SurvivorData.milestones_for(axis, profile):
			if not done.has(int(m["points"])):
				continue
			var stat := str(m["stat"])
			if str(m.get("kind", "add")) == "mult":
				agg_mult[stat] = float(agg_mult.get(stat, 1.0)) * float(m["value"])
			else:
				agg_add[stat] = float(agg_add.get(stat, 0.0)) + float(m["value"])
	if agg_add.is_empty() and agg_mult.is_empty():
		var none := Label.new()
		none.text = "  ── %s ──" % tr("ATTR_BONUS_NONE")
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.4))
		_status_panel.add_child(none)
	else:
		var parts: Array[String] = []
		for stat in agg_add:
			parts.append("%s %+d" % [tr(str(SurvivorData.MILESTONE_STAT_I18N.get(stat, ""))), int(agg_add[stat])])
		for stat in agg_mult:
			parts.append("%s %+d%%" % [tr(str(SurvivorData.MILESTONE_STAT_I18N.get(stat, ""))),
				int(round((float(agg_mult[stat]) - 1.0) * 100.0))])
		var idx := 0
		while idx < parts.size():
			var row := Label.new()
			row.text = "  ▸ " + parts[idx] + (("    ▸ " + parts[idx + 1]) if idx + 1 < parts.size() else "")
			row.add_theme_font_size_override("font_size", 10)
			row.add_theme_color_override("font_color", TEXT_COLOR)
			_status_panel.add_child(row)
			idx += 2
	# ── 机体数据（live params：一切加成落地后的最终值）──
	var ac = _game_scene.player_aircraft if "player_aircraft" in _game_scene else null
	if ac == null or not is_instance_valid(ac) or ac.params == null:
		return
	var p = ac.params
	_status_panel.add_child(_y2k_header(tr("ATTR_AIRCRAFT_DATA")))
	var cells: Array[String] = [
		"HP %d/%d" % [int(ac.hp), int(p.max_hp)],
		"%s %d" % [tr("ATTR_STAT_SPEED"), int(p.max_speed)],
		"%s %d" % [tr("ATTR_STAT_CRUISE"), int(p.cruise_speed)],
		"G %.1f" % p.max_g,
		"%s %.1fkm ±%d°" % [tr("ATTR_STAT_RADAR_RANGE"), p.radar_range * 2.0 / 1000.0, int(p.radar_half_angle)],
		"%s %.1fs" % [tr("ATTR_STAT_LOCK_TIME"), p.lock_time],
		"%s %d/%d" % [tr("ATTR_STAT_MISSILE_COUNT"), int(ac.missiles_remaining),
			int(p.missile.max_count) if p.missile else 0],
		"%s %d/%d" % [tr("ATTR_STAT_FLARE_COUNT"), int(ac.flares_remaining),
			int(p.flare.max_flares) if p.flare else 0],
	]
	var i2 := 0
	while i2 < cells.size():
		var row2 := Label.new()
		row2.text = "  " + cells[i2] + (("  ┊  " + cells[i2 + 1]) if i2 + 1 < cells.size() else "")
		row2.add_theme_font_size_override("font_size", 10)
		row2.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.85))
		row2.clip_text = true
		_status_panel.add_child(row2)
		i2 += 2


## y2k 终端风小节头："─ ⟦ 名称 ⟧ ────────"
func _y2k_header(txt: String) -> Label:
	var l := Label.new()
	l.text = "─ ⟦ %s ⟧ %s" % [txt, "─".repeat(16)]
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.6))
	l.clip_text = true
	return l


## 里程碑效果 → 明细短文（"HP+25" / "机炮伤害+8%" / "锁定耗时-10%"）
func _fmt_milestone_bonus(m: Dictionary) -> String:
	var stat_name := tr(str(SurvivorData.MILESTONE_STAT_I18N.get(str(m.get("stat", "")), "")))
	var v := float(m.get("value", 0.0))
	if str(m.get("kind", "add")) == "mult":
		return "%s%+d%%" % [stat_name, int(round((v - 1.0) * 100.0))]
	return "%s%+d" % [stat_name, int(v)]


func _show_upgrade_detail(u: Dictionary) -> void:
	if not _upgrade_detail:
		return
	var name_text := tr(u["name"])
	var desc_text := tr(u["desc"])
	var axis: String = u.get("category", "survival")
	var axis_title: String = _AXIS_TITLES.get(axis, axis)
	var axis_color: Color = _AXIS_COLORS.get(axis, TEXT_COLOR)
	var axis_hex := "#%02x%02x%02x" % [int(axis_color.r * 255), int(axis_color.g * 255), int(axis_color.b * 255)]
	_upgrade_detail.text = "[b]%s[/b]\n[color=%s][font_size=10]%s[/font_size][/color]\n\n%s" % [name_text, axis_hex, axis_title, desc_text]

func _clear_upgrade_detail() -> void:
	if not _upgrade_detail:
		return
	_upgrade_detail.text = "[color=#666666][font_size=11]%s[/font_size][/color]" % tr("TACTICAL_MAP_UPGRADES_HOVER_HINT")

func _refresh_info() -> void:
	if not _info_label:
		return
	if _hover_zone_id == &"":
		_info_label.text = "[b]%s[/b]\n\n%s" % [tr("TACTICAL_MAP_INFO_TITLE"), tr("TACTICAL_MAP_INFO_BODY")]
		return
	var z := _zones.get_zone_by_id(_hover_zone_id) if _zones else {}
	if z.is_empty():
		_info_label.text = ""
		return
	var state := _zones.get_state(_hover_zone_id)
	var state_text: String
	match state:
		ZoneData.State.AVAILABLE: state_text = tr("ZONE_STATE_AVAILABLE")
		ZoneData.State.SELECTED: state_text = tr("ZONE_STATE_SELECTED")
		ZoneData.State.CLEARED: state_text = tr("ZONE_STATE_CLEARED")
		_: state_text = tr("ZONE_STATE_LOCKED")
	var name_str: String = tr(z["name_key"])
	var lines: PackedStringArray = [
		"[b]%s — %s[/b]" % [z["label"], name_str],
		"",
		"[color=#aaaaaa]%s[/color] %s" % [tr("ZONE_INFO_STATE"), state_text],
	]

	# CLEARED 战区：信息面板极简，不显示奖励 / 任务（重开后会重新滚）
	if state == ZoneData.State.CLEARED:
		_info_label.text = "\n".join(lines)
		return

	# 难度星（1-3）
	var difficulty: int = _zones.get_difficulty(_hover_zone_id)
	var stars: String = "★".repeat(difficulty) + "☆".repeat(ZoneData.DIFFICULTY_MAX - difficulty)
	lines.append("[color=#aaaaaa]%s[/color] [color=#ff9966]%s[/color]" % [tr("ZONE_INFO_DIFFICULTY"), stars])

	# 奖励详情（类别标签 + 具体技能名 + 描述）
	var reward_block: String
	var reward := _zones.get_reward(_hover_zone_id)
	if reward.is_empty():
		reward_block = "  %s" % tr("ZONE_REWARD_HINT_UNKNOWN")
	else:
		var rname: String = tr(reward.get("name", ""))
		var rdesc: String = tr(reward.get("desc", ""))
		var axis: String = reward.get("category", "survival")
		var axis_title: String = _AXIS_TITLES.get(axis, axis)
		var axis_color: Color = _AXIS_COLORS.get(axis, TEXT_COLOR)
		var axis_hex := "#%02x%02x%02x" % [int(axis_color.r * 255), int(axis_color.g * 255), int(axis_color.b * 255)]
		reward_block = "  [color=%s][font_size=10]%s[/font_size][/color]\n  [color=#ffd864]%s[/color]\n  [color=#aaccaa]%s[/color]" % [axis_hex, axis_title, rname, rdesc]

	# 任务描述（按 ground / air / boss 区分）
	var mission_desc_key: String
	if _hover_zone_id == &"BOSS":
		mission_desc_key = "ZONE_MISSION_BOSS"
	else:
		var mission_type: String = _zones.get_mission_type(_hover_zone_id) if _zones else z.get("mission_type", "ground")
		match mission_type:
			"air":       mission_desc_key = "ZONE_MISSION_AIR"
			"squadron":  mission_desc_key = "ZONE_MISSION_SQUADRON"
			"elite":     mission_desc_key = "ZONE_MISSION_ELITE"
			"naval":     mission_desc_key = "ZONE_MISSION_NAVAL"
			_:           mission_desc_key = "ZONE_MISSION_GROUND"

	lines.append("")
	lines.append("[color=#aaaaaa]%s[/color]" % tr("ZONE_INFO_REWARD"))
	lines.append(reward_block)
	lines.append("")
	lines.append("[color=#aaaaaa]%s[/color]" % tr("ZONE_INFO_MISSION"))
	lines.append("  %s" % tr(mission_desc_key))

	if state == ZoneData.State.AVAILABLE:
		lines.append("")
		lines.append("[color=#88ff88]%s[/color]" % tr("ZONE_CLICK_TO_SELECT"))
	_info_label.text = "\n".join(lines)
