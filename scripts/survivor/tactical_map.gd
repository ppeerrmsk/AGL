class_name TacticalMap
extends CanvasLayer

const VectorPreviewRenderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const RasterPreviewRenderer = preload("res://scripts/survivor/raster_basemap_renderer.gd")

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
## Tab 打开且全场暂停时 SurvivorMode 收不到输入，由本 PROCESS_MODE_ALWAYS 层转发。
signal vector_preview_toggle_requested()
signal raster_preview_toggle_requested()

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
const BOMBER_ROUTE_COLOR := Color(1.0, 0.63, 0.18, 0.58)
const BOMBER_TGT_COLOR := Color(1.0, 0.72, 0.20, 1.0)
const BOMBER_TGT_DARK := Color(0.08, 0.035, 0.01, 0.96)

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
var _detail_prepare_in_progress := false
var _close_after_detail_prepare := false
var _adbs: AdbsManager = null  ## 用于在缩略图上画 ADBS 目标实时位置
var _docks: Array = []         ## 停靠点列表（DockPoint，spec zone-reward-docking）
## 与主地图同步的开发期 V11 纯矢量预览；默认 false，关闭时完全沿用 PNG 路径。
var vector_preview_enabled := false
var _vector_preview_viewport: SubViewport = null
var _vector_preview_renderer: Node2D = null
var raster_preview_enabled := false
var _mm_raster_tex: Texture2D = null
## UGC/内置预览图调色板；空字典保持东京湾缩略图历史配色。
var ugc_palette: Dictionary = {}
var use_basemap := true
var readout_only := false  ## Boss Debug：只保留 build/三轴/里程碑读数，不加载或绘制地图几何。
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
# ── 左栏（三轴/机体状态）+ 右缘"已激活技能"面板 ──
var _game_scene: Node = null              ## survivor_mode，提供 upgrade_stacks
var _weapon_loadout_panel: VBoxContainer  ## Boss Debug：ACE 随机构筑的特殊武器
var _weapon_loadout_label: Label
var _upgrades_list: VBoxContainer         ## 右缘技能清单（2026-07-27 用户令从左栏移出）
var _upgrade_detail: RichTextLabel        ## 右缘 hover 详情框
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
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F8 and event.shift_pressed:
		get_viewport().set_input_as_handled()
		if _detail_prepare_in_progress:
			return
		raster_preview_toggle_requested.emit()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F10 and event.shift_pressed:
		get_viewport().set_input_as_handled()
		if _detail_prepare_in_progress:
			return
		vector_preview_toggle_requested.emit()
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()

func setup(world_rect: Rect2, player: Aircraft, zones: ZoneData, game_scene: Node = null) -> void:
	_world_rect = world_rect
	_player = player
	_zones = zones
	_game_scene = game_scene
	raster_preview_enabled = OS.is_debug_build() \
		and OS.get_cmdline_user_args().has("--raster-basemap-preview")

func set_vector_preview_enabled(enabled: bool) -> bool:
	if enabled:
		if _world_rect.size.x <= 0.0 or not VectorPreviewRenderer.preview_available():
			return false
		if _vector_preview_viewport == null:
			_vector_preview_viewport = SubViewport.new()
			_vector_preview_viewport.name = "VectorMapSnapshot"
			_vector_preview_viewport.size = Vector2i(1024, 1024)
			_vector_preview_viewport.disable_3d = true
			_vector_preview_viewport.transparent_bg = false
			_vector_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(_vector_preview_viewport)

			var preview_camera := Camera2D.new()
			preview_camera.name = "VectorMapCamera"
			preview_camera.position = _world_rect.get_center()
			var fit_zoom := minf(1024.0 / _world_rect.size.x, 1024.0 / _world_rect.size.y)
			preview_camera.zoom = Vector2.ONE * fit_zoom
			preview_camera.enabled = true
			_vector_preview_viewport.add_child(preview_camera)

			_vector_preview_renderer = VectorPreviewRenderer.new()
			_vector_preview_renderer.name = "VectorMapRenderer"
			_vector_preview_viewport.add_child(_vector_preview_renderer)
			if not _vector_preview_renderer.setup(
					preview_camera, _world_rect, VectorPreviewRenderer.LOD_TAB):
				_vector_preview_viewport.queue_free()
				_vector_preview_viewport = null
				_vector_preview_renderer = null
				return false
			# 静态底图只烘焙一帧，之后 Tab 的 10Hz 动态标记不会重绘它。
			_vector_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		vector_preview_enabled = true
	else:
		vector_preview_enabled = false
		if _vector_preview_viewport != null:
			_vector_preview_viewport.queue_free()
			_vector_preview_viewport = null
			_vector_preview_renderer = null
	if _map_panel != null:
		_map_panel.queue_redraw()
	return true


func set_raster_preview_enabled(enabled: bool) -> bool:
	if enabled:
		if vector_preview_enabled:
			set_vector_preview_enabled(false)
		if not _ensure_raster_basemap():
			return false
		raster_preview_enabled = true
	else:
		raster_preview_enabled = false
		_mm_raster_tex = null
	if _map_panel != null:
		_map_panel.queue_redraw()
	return true

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
	if _detail_prepare_in_progress:
		_close_after_detail_prepare = true
		return
	_is_open = false
	AudioManager.set_music_muffled(false)
	_roll_random_tip()
	# 状态恢复已全部完成，dismiss 只是视觉尾巴（解暂停在 panel_out 第 0 帧）
	Presentation.dismiss(self, "panel_out")


func set_detail_prepare_in_progress(enabled: bool) -> void:
	var was_preparing := _detail_prepare_in_progress
	_detail_prepare_in_progress = enabled
	if was_preparing and not enabled and _close_after_detail_prepare:
		_close_after_detail_prepare = false
		close()


func is_detail_prepare_in_progress() -> bool:
	return _detail_prepare_in_progress

## ZoneData 状态异步变化（尤其 FAILED）时，立即清掉悬停信息而不是等下一次鼠标移动。
func refresh_zone_state() -> void:
	if _hover_zone_id != &"" and _should_hide_zone(_hover_zone_id):
		_hover_zone_id = &""
		_refresh_info()
	if _map_panel:
		_map_panel.queue_redraw()

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

	# 左栏三轴/机体状态（镜像右侧 info_label 的位置）+ 右缘"已激活技能"面板
	_build_axis_column()
	_build_skills_panel()

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
	var size := _map_panel.size
	_map_rect = Rect2(Vector2.ZERO, size)
	if readout_only:
		_map_panel.draw_rect(_map_rect, BG_COLOR)
		_map_panel.draw_rect(_map_rect, FRAME_COLOR, false, 2.0)
		_draw_minimap_scanlines_and_vignette(size)
		return
	MapGeography.ensure_ready()
	if raster_preview_enabled:
		_ensure_raster_basemap()
	elif not vector_preview_enabled and use_basemap:
		_ensure_minimap_basemap()
	# 底色 = 海（如果有底图 PNG 覆盖，下面会盖住）
	_map_panel.draw_rect(_map_rect, _map_color("sea", MapGeography.SEA_COLOR))
	# 底图 PNG（如果存在）
	if vector_preview_enabled:
		_draw_minimap_vector_preview(size)
	elif raster_preview_enabled:
		_draw_minimap_raster(size)
	else:
		_draw_minimap_basemap(size)
	# 矢量细节层（只在没底图时才画 OSM 矢量，避免重复）
	if not vector_preview_enabled and not raster_preview_enabled and _mm_basemap_tex == null:
		_draw_geography(size)
		_draw_cities(size)
	_draw_haneda_airport(size)
	_draw_ugc_airports(size)
	# 框
	_map_panel.draw_rect(_map_rect, FRAME_COLOR, false, 2.0)

	# 战区圆 + 标签
	if _zones:
		_draw_zones(size)
		_draw_boss(size)

	# ADBS 目标实时位置（黄色菱形 + 朝向短线，带脉冲）
	_draw_adbs_markers(size)

	# DEADAIR 移动干扰场（红紫边界 + 菱形核心）；只读控制器快照，不在 _draw 扫全场实体。
	_draw_deadair_field(size)

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
var basemap_png_path: String = MM_BASEMAP_PNG
var basemap_meta_path: String = MM_BASEMAP_META
var _mm_basemap_tex: Texture2D = null
var _mm_basemap_world_rect: Rect2 = Rect2()
var _mm_basemap_loaded := false


func _ensure_raster_basemap() -> bool:
	if _mm_raster_tex != null:
		return true
	if not use_basemap or basemap_png_path.is_empty() or basemap_meta_path.is_empty():
		return false
	var map_key := RasterPreviewRenderer.map_key_from_png_path(basemap_png_path)
	var manifest := RasterPreviewRenderer.load_manifest(map_key)
	if manifest.is_empty() or not _ensure_raster_world_rect():
		return false
	var levels: Dictionary = manifest.get("levels", {}) as Dictionary
	var strategic: Dictionary = levels.get("strategic", {}) as Dictionary
	var tiles: Array = strategic.get("tiles", []) as Array
	if tiles.is_empty():
		return false
	var record := tiles[0] as Dictionary
	var texture_path := "%s/%s/%s" % [
		RasterPreviewRenderer.ROOT_PATH,
		map_key,
		String(record.get("path", "strategic.webp")),
	]
	var texture := RasterPreviewRenderer.load_texture(texture_path)
	if texture == null:
		return false
	# 正式 Tab 从不套主地图 shader，只对底图做固定中性乘色；候选必须保持同一职责，
	# 否则主图色准会在 Tab 被重复处理。直接复用常驻 Strategic，避免第二份快照纹理。
	_mm_raster_tex = texture
	return true


func _ensure_raster_world_rect() -> bool:
	if _mm_basemap_world_rect.size.x > 0.0:
		return true
	var file := FileAccess.open(basemap_meta_path, FileAccess.READ)
	if file == null:
		return false
	var meta = JSON.parse_string(file.get_as_text())
	file.close()
	if not meta is Dictionary:
		return false
	var bbox: Dictionary = meta.get("bbox_ll", {})
	var center_ll: Array = meta.get("game_world_center_latlon", [35.44, 139.76])
	var m_per_lat: float = float(meta.get("game_world_meters_per_degree_lat", 111000.0))
	var m_per_lon: float = float(meta.get("game_world_meters_per_degree_lon_at_center", 111000.0 * cos(deg_to_rad(35.44))))
	var px_per_m: float = float(meta.get("game_world_px_per_meter", 0.5))
	var lat_min: float = float(bbox.get("lat_min", 0.0))
	var lat_max: float = float(bbox.get("lat_max", 0.0))
	var lon_min: float = float(bbox.get("lon_min", 0.0))
	var lon_max: float = float(bbox.get("lon_max", 0.0))
	var cx: float = float(center_ll[1])
	var cy: float = float(center_ll[0])
	var x0 := (lon_min - cx) * m_per_lon * px_per_m
	var x1 := (lon_max - cx) * m_per_lon * px_per_m
	var y0 := -(lat_max - cy) * m_per_lat * px_per_m
	var y1 := -(lat_min - cy) * m_per_lat * px_per_m
	_mm_basemap_world_rect = Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))
	return _mm_basemap_world_rect.size.x > 0.0

func _ensure_minimap_basemap() -> void:
	if _mm_basemap_loaded:
		return
	_mm_basemap_loaded = true
	if not use_basemap or basemap_png_path == "" or basemap_meta_path == "":
		return
	if not ResourceLoader.exists(basemap_png_path) and not FileAccess.file_exists(basemap_png_path):
		return
	var f := FileAccess.open(basemap_meta_path, FileAccess.READ)
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
	_mm_basemap_tex = load(basemap_png_path) as Texture2D if ResourceLoader.exists(basemap_png_path) else null
	if _mm_basemap_tex == null and FileAccess.file_exists(basemap_png_path):
		var image := Image.load_from_file(basemap_png_path)
		if image != null and not image.is_empty():
			_mm_basemap_tex = ImageTexture.create_from_image(image)
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


func _draw_minimap_raster(size: Vector2) -> void:
	if _mm_raster_tex == null:
		return
	var p0 := _world_to_map(_mm_basemap_world_rect.position, size)
	var p1 := _world_to_map(_mm_basemap_world_rect.end, size)
	_map_panel.draw_texture_rect(
		_mm_raster_tex, Rect2(p0, p1 - p0), false, MINIMAP_BASEMAP_MODULATE)

func _draw_minimap_vector_preview(size: Vector2) -> void:
	if _vector_preview_viewport == null:
		return
	var texture := _vector_preview_viewport.get_texture()
	if texture != null:
		_map_panel.draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)

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
var _mm_cache_airports: Array = []
var _mm_cache_aqualine: PackedVector2Array = PackedVector2Array()

func _rebuild_minimap_geometry_cache(size: Vector2) -> void:
	if _mm_cache_size == size:
		return
	_mm_cache_size = size
	_mm_cache_land.clear()
	_mm_cache_urban.clear()
	_mm_cache_roads.clear()
	_mm_cache_airports.clear()
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
	for poly_any in MapGeography.OSM_AERODROMES:
		var airport := _map_poly(poly_any, size)
		if airport.size() >= 3:
			_mm_cache_airports.append(airport)
	var aq: PackedVector2Array = MapGeography.AQUALINE_PATH
	if aq.size() >= 2:
		_mm_cache_aqualine = _map_poly(aq, size)
	else:
		_mm_cache_aqualine = PackedVector2Array()
	print("[TacticalMap] rebuilt mm geo cache @size=%s land=%d urban=%d roads=%d airports=%d (%dms)" % [
		size, _mm_cache_land.size(), _mm_cache_urban.size(), _mm_cache_roads.size(),
		_mm_cache_airports.size(),
		Time.get_ticks_msec() - t0,
	])

## 缩略图：海岸线地图（陆地填充）
func _draw_geography(size: Vector2) -> void:
	_rebuild_minimap_geometry_cache(size)
	for poly_any in _mm_cache_land:
		_map_panel.draw_colored_polygon(poly_any, _map_color("land", MINIMAP_LAND_COLOR))

## 缩略图：城区多边形 + 高速（都用缓存，道路用单次 draw_polyline）
func _draw_cities(size: Vector2) -> void:
	for poly_any in _mm_cache_urban:
		_map_panel.draw_colored_polygon(poly_any, _map_color("urban", MINIMAP_URBAN_COLOR))
	# draw_polyline：单次 GPU 调用画整条线，比 per-segment draw_line 快 ~3×
	for mapped_any in _mm_cache_roads:
		var mapped: PackedVector2Array = mapped_any
		if mapped.size() >= 2:
			_map_panel.draw_polyline(mapped, _map_color("road", MINIMAP_ROAD_COLOR), 1.0)
	if not MapGeography.ugc_mode and _mm_cache_aqualine.size() >= 2:
		for i in range(_mm_cache_aqualine.size() - 1):
			_map_panel.draw_dashed_line(_mm_cache_aqualine[i], _mm_cache_aqualine[i + 1], MapGeography.AQUALINE_COLOR, 1.0, 4.0)


const MINIMAP_RUNWAY_FILL := Color(0.18, 0.21, 0.20, 0.95)
const MINIMAP_RUNWAY_EDGE := Color(0.78, 0.84, 0.76, 0.92)
const MINIMAP_RUNWAY_CENTER := Color(0.88, 0.90, 0.84, 0.82)
var _mm_haneda_cache_size: Vector2 = Vector2.ZERO
var _mm_cache_haneda_runways: Array[Dictionary] = []

## 正式港湾 Tab 只缓存四条跑道的八个端点，不触发整张 OSM 几何重建。
func _rebuild_haneda_runway_cache(size: Vector2) -> void:
	if _mm_haneda_cache_size == size:
		return
	_mm_haneda_cache_size = size
	_mm_cache_haneda_runways.clear()
	for runway_any in MapGeography.HANEDA_RUNWAYS:
		var runway: Dictionary = runway_any
		_mm_cache_haneda_runways.append({
			"start": _world_to_map(runway.get("start", Vector2.ZERO), size),
			"end": _world_to_map(runway.get("end", Vector2.ZERO), size),
			"width": maxf(2.0, float(runway.get("width", 30.0)) * size.x / _world_rect.size.x),
		})

func _draw_haneda_airport(size: Vector2) -> void:
	if MapGeography.ugc_mode:
		return
	_rebuild_haneda_runway_cache(size)
	for runway_any in _mm_cache_haneda_runways:
		var runway: Dictionary = runway_any
		var start: Vector2 = runway.start
		var finish: Vector2 = runway.end
		var width: float = runway.width
		_map_panel.draw_line(start, finish, MINIMAP_RUNWAY_EDGE, width + 1.5, true)
		_map_panel.draw_line(start, finish, MINIMAP_RUNWAY_FILL, width, true)
		_map_panel.draw_line(start, finish, MINIMAP_RUNWAY_CENTER, 0.8, true)

## PNG 缩略图上方的静态 UGC 跑道标记；几何随面板尺寸缓存。
func _draw_ugc_airports(size: Vector2) -> void:
	if not MapGeography.ugc_mode:
		return
	_rebuild_minimap_geometry_cache(size)
	for airport_any in _mm_cache_airports:
		var airport: PackedVector2Array = airport_any
		_map_panel.draw_colored_polygon(airport, MINIMAP_RUNWAY_FILL)
		var outline := airport.duplicate()
		outline.append(airport[0])
		_map_panel.draw_polyline(outline, MINIMAP_RUNWAY_EDGE, 1.5, true)


func _map_color(key: String, fallback: Color) -> Color:
	var raw = ugc_palette.get(key, null)
	if raw is Array and raw.size() >= 3:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]),
			float(raw[3]) if raw.size() >= 4 else 1.0)
	return fallback

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
	# 机场解放战区（spec airfield-liberation-zones §3.3）：解放后隐藏红圈，
	# 改由 _draw_dock_markers 画激活后的机场补给点图标
	if _zones.is_airfield(zid) and _zones.get_state(zid) == ZoneData.State.CLEARED:
		return true
	var state := _zones.get_state(zid)
	return state == ZoneData.State.LOCKED or state == ZoneData.State.FAILED

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

	var c := _world_to_map(_zone_primary_center(zid), size)
	var r: float = _zones.get_zone_radius(zid) * size.x / _world_rect.size.x
	var is_bomber_escort := ZoneData.is_optional_mission_type(_zones.get_mission_type(zid))
	if is_bomber_escort:
		# 护送任务只占“目标 + 航线”，不再套用普通战区的大面积填充圆。
		_draw_bomber_route_and_target(zid, c, size, color)
		_draw_bomber_escort_marker(zid, size, color)
	else:
		_map_panel.draw_circle(c, r, fill)
		_map_panel.draw_arc(c, r, 0.0, TAU, 48, color, 2.0)

	# hover 高亮
	if _hover_zone_id == zid and state == ZoneData.State.AVAILABLE:
		var hover_r := 18.0 if is_bomber_escort else r + 4.0
		_map_panel.draw_arc(c, hover_r, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.9), 2.0)

	# 标签 + 难度星（Boss 没难度概念，跳过星）
	var label_s: String = z["label"]
	if is_bomber_escort:
		_map_panel.draw_string(ThemeDB.fallback_font, c + Vector2(15.0, -9.0),
			label_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	else:
		_map_panel.draw_string(
			ThemeDB.fallback_font, c + Vector2(-6, 5),
			label_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color
		)
	# 战区奖励前置显示（spec zone-reward-docking §2.8）：图标字符 + 名称（圈下方）
	if zid != &"BOSS" and _zones \
			and (state == ZoneData.State.AVAILABLE or state == ZoneData.State.SELECTED):
		var rtxt := ""
		if _zones.is_airfield(zid):
			# 机场解放战区：奖励＝机场本身（spec airfield-liberation-zones §3.3）
			rtxt = "✈ %s" % tr("ZONE_REWARD_AIRFIELD")
		elif is_bomber_escort:
			rtxt = tr("ZONE_REWARD_BOMBER_XP_FMT") % ZoneData.bomber_escort_xp_reward(
				_zones.get_difficulty(zid))
		else:
			var rw: Dictionary = _zones.get_reward(zid)
			if not rw.is_empty():
				var glyph := "◆"
				match String(rw.get("kind", "")):
					"carrier": glyph = "⚓"
					"wingman": glyph = "✚"
					"weapon": glyph = "⌁"
				rtxt = "%s %s" % [glyph, tr(String(rw.get("name", "")))]
		if rtxt != "":
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

## 专用航线与固定目标：入口可以在真实边界外，绘图时只钳显示坐标，不改运行时航路。
func _draw_bomber_route_and_target(zid: StringName, center: Vector2, size: Vector2,
		state_color: Color) -> void:
	var route := _zones.get_mission_route(zid)
	if route.size() >= 2:
		var mapped := PackedVector2Array()
		for world_point in route:
			var p := _world_to_map(world_point, size)
			mapped.append(Vector2(clampf(p.x, 3.0, size.x - 3.0), clampf(p.y, 3.0, size.y - 3.0)))
		for i in range(mapped.size() - 1):
			_map_panel.draw_dashed_line(mapped[i], mapped[i + 1], BOMBER_ROUTE_COLOR, 2.0, 7.0)

	var marker_color := BOMBER_TGT_COLOR.lerp(state_color, 0.18)
	var outer := PackedVector2Array([
		center + Vector2(0.0, -13.0), center + Vector2(13.0, 0.0),
		center + Vector2(0.0, 13.0), center + Vector2(-13.0, 0.0),
	])
	var inner := PackedVector2Array([
		center + Vector2(0.0, -9.0), center + Vector2(9.0, 0.0),
		center + Vector2(0.0, 9.0), center + Vector2(-9.0, 0.0),
	])
	_map_panel.draw_colored_polygon(outer, BOMBER_TGT_DARK)
	_map_panel.draw_polyline(PackedVector2Array([outer[0], outer[1], outer[2], outer[3], outer[0]]),
		marker_color, 2.5)
	_map_panel.draw_colored_polygon(inner, Color(marker_color, 0.28))
	_map_panel.draw_circle(center, 3.5, marker_color)
	_map_panel.draw_string(ThemeDB.fallback_font, center + Vector2(-14.0, -17.0),
		"TGT", HORIZONTAL_ALIGNMENT_CENTER, 28.0, 11, marker_color)
	_map_panel.draw_string(ThemeDB.fallback_font, center + Vector2(18.0, -7.0),
		tr("ZONE_OPTIONAL_MISSION_TAG_SHORT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		marker_color.lightened(0.15))

	var status := _zones.get_mission_status(zid)
	var max_hp := maxf(float(status.get("target_max_hp", 150.0)), 1.0)
	var hp_ratio := clampf(float(status.get("target_hp", max_hp)) / max_hp, 0.0, 1.0)
	var bar := Rect2(center + Vector2(-19.0, 17.0), Vector2(38.0, 5.0))
	_map_panel.draw_rect(bar, Color(0.02, 0.02, 0.02, 0.92), true)
	_map_panel.draw_rect(Rect2(bar.position + Vector2.ONE, Vector2((bar.size.x - 2.0) * hp_ratio,
		bar.size.y - 2.0)), marker_color, true)
	_map_panel.draw_rect(bar, Color(marker_color, 0.92), false, 1.0)

## 目标型战区的主圆/点击热区固定在 TGT；导航仍可读取 get_zone_center 跟随编队。
func _zone_primary_center(zid: StringName) -> Vector2:
	if _zones and _zones.get_mission_type(zid) == "bomber_escort":
		return _zones.get_objective_center(zid)
	return _zones.get_zone_center(zid) if _zones else Vector2.INF

## 三枚小箭头沿真实航向排成纵队。场外编队钳到面板边缘，快速开 Tab 仍能看出它在入场。
func _draw_bomber_escort_marker(zid: StringName, size: Vector2, color: Color) -> void:
	if not _zones.has_dynamic_center(zid):
		return
	var actual := _world_to_map(_zones.get_zone_center(zid), size)
	var margin := 22.0
	var center := Vector2(
		clampf(actual.x, margin, size.x - margin),
		clampf(actual.y, margin, size.y - margin))
	var heading := _zones.get_dynamic_heading(zid)
	var forward := Vector2(sin(heading), -cos(heading))
	var right := Vector2(-forward.y, forward.x)
	for i in range(3):
		var p := center - forward * float(i) * 7.0
		_map_panel.draw_colored_polygon(PackedVector2Array([
			p + forward * 5.0,
			p - forward * 4.0 + right * 3.0,
			p - forward * 4.0 - right * 3.0,
		]), color)
	_map_panel.draw_string(ThemeDB.fallback_font, center + right * 9.0 + Vector2(3.0, 4.0),
		"B-1B ×3", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color.lightened(0.2))

## 在缩略图上画 ADBS 事件单位（轰炸机/直升机等）实时位置
func _draw_deadair_field(size: Vector2) -> void:
	if _game_scene == null or _world_rect.size.x <= 0.0:
		return
	var spawner = _game_scene.get("_spawner")
	if spawner == null or not spawner.has_method("deadair_field_snapshot"):
		return
	var snapshot: Dictionary = spawner.deadair_field_snapshot()
	if snapshot.is_empty():
		return
	var world_pos: Vector2 = snapshot["position"]
	var center := _world_to_map(world_pos, size)
	var radius_map := float(snapshot["radius_px"]) / _world_rect.size.x * size.x
	var field_color := Color(0.68, 0.08, 0.47, 0.9)
	_map_panel.draw_circle(center, radius_map, Color(field_color, 0.075))
	_map_panel.draw_arc(center, radius_map, 0.0, TAU, 64, field_color, 2.0)
	var core := PackedVector2Array([
		center + Vector2(0.0, -6.0), center + Vector2(6.0, 0.0),
		center + Vector2(0.0, 6.0), center + Vector2(-6.0, 0.0),
	])
	_map_panel.draw_colored_polygon(core, Color(0.92, 0.22, 0.62, 0.95))


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
		# 淡填充 + 粗描边：玩家要能一眼判断"我在不在锁定加速圈里"，
		# 原来只有一条 1.5px 细弧，在全图缩放下几乎看不见（2026-07-28）
		_map_panel.draw_circle(apos, r_map, Color(ALLY_COLOR, 0.07))
		_map_panel.draw_arc(apos, r_map, 0.0, TAU, 64, Color(ALLY_COLOR, 0.75), 2.5)
		_map_panel.draw_circle(apos, 3.5, ALLY_COLOR)
	# 王牌中队标记（spec ace-squadron-tier §2.7）：中队主色菱形 + 代号标签
	var ace_lead: Aircraft = AceReinforcementEvent.active_leader()
	if ace_lead != null:
		var ace_col: Color = AceReinforcementEvent.active_color()
		var lpos := _world_to_map(ace_lead.global_position, size)
		var dd := 6.0
		_map_panel.draw_colored_polygon(PackedVector2Array([
			lpos + Vector2(0, -dd - 1.5), lpos + Vector2(dd + 1.5, 0),
			lpos + Vector2(0, dd + 1.5), lpos + Vector2(-dd - 1.5, 0)]), Color(0, 0, 0, 0.6))
		_map_panel.draw_colored_polygon(PackedVector2Array([
			lpos + Vector2(0, -dd), lpos + Vector2(dd, 0),
			lpos + Vector2(0, dd), lpos + Vector2(-dd, 0)]), ace_col)
		_map_panel.draw_string(ThemeDB.fallback_font, lpos + Vector2(9, 4),
			AceReinforcementEvent.active_codename(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			ace_col.lightened(0.35))
	if _docks.is_empty():
		return
	var font := ThemeDB.fallback_font
	for d_any in _docks:
		var d := d_any as DockPoint
		if not is_instance_valid(d):
			continue
		if d.is_spent():
			continue  # 一次性机场用尽 → Tab 标记消失（spec zone-reward-docking §2.2 修订）
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
	if _detail_prepare_in_progress:
		return
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
		var bc := _world_to_map(_zone_primary_center(bz["id"]), size)
		var br: float = _zones.get_zone_radius(bz["id"]) * size.x / _world_rect.size.x
		if map_pos.distance_to(bc) <= br:
			return bz["id"]
	# 普通战区：隐藏的直接跳过
	for z in ZoneData.ZONES:
		if _should_hide_zone(z["id"]):
			continue
		var c := _world_to_map(_zone_primary_center(z["id"]), size)
		var r: float = _zones.get_zone_radius(z["id"]) * size.x / _world_rect.size.x
		if _zones.get_mission_type(z["id"]) == "bomber_escort":
			r = maxf(r, 18.0)
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

## 左栏：三轴量表/里程碑明细 + 机体状态块（镜像 _info_label 位置，offset_left=-720..-360）。
## "已激活技能"清单已移到右缘 _build_skills_panel（2026-07-27 用户令）。
func _build_axis_column() -> void:
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -720
	panel.offset_right = -360
	panel.offset_top = -340
	panel.offset_bottom = 340
	panel.add_theme_constant_override("separation", 8)
	_root.add_child(panel)

	# 三轴常驻面板（spec evolution-attribute-gates §3.2：点数/里程碑/下一档/路线倾向，只读）
	_axis_panel = VBoxContainer.new()
	_axis_panel.add_theme_constant_override("separation", 1)
	panel.add_child(_axis_panel)

	# 底部状态块（2026-07-19 用户令）：当前加成汇总 + 机体实时数据（y2k 终端风）
	_status_panel = VBoxContainer.new()
	_status_panel.add_theme_constant_override("separation", 1)
	panel.add_child(_status_panel)

## 右缘"已激活技能"面板：标题 + 滚动清单 + hover 详情框。
## 贴屏幕右缘（anchor=1.0），上缘与缩略图对齐、下缘避开右下"操作指南"框（其顶为 -260）。
func _build_skills_panel() -> void:
	var panel := VBoxContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -240
	panel.offset_right = -20
	panel.offset_top = -340
	panel.offset_bottom = -270
	panel.add_theme_constant_override("separation", 8)
	_root.add_child(panel)

	_weapon_loadout_panel = VBoxContainer.new()
	_weapon_loadout_panel.add_theme_constant_override("separation", 3)
	_weapon_loadout_panel.visible = false
	panel.add_child(_weapon_loadout_panel)

	var weapon_title := Label.new()
	weapon_title.text = tr("TACTICAL_MAP_WEAPONS_TITLE")
	weapon_title.add_theme_font_size_override("font_size", 16)
	weapon_title.add_theme_color_override("font_color", NAV_MARKER_COLOR)
	_weapon_loadout_panel.add_child(weapon_title)

	_weapon_loadout_label = Label.new()
	_weapon_loadout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_loadout_label.add_theme_font_size_override("font_size", 12)
	_weapon_loadout_label.add_theme_color_override("font_color", TEXT_COLOR)
	_weapon_loadout_panel.add_child(_weapon_loadout_label)

	var title := Label.new()
	title.text = tr("TACTICAL_MAP_UPGRADES_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# 滚动列表（吃掉剩余高度）
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
	_refresh_weapon_loadout()
	if not _upgrades_list:
		return
	for child in _upgrades_list.get_children():
		child.queue_free()
	_clear_upgrade_detail()

	# 重建清单必须在清空之后（历史 bug：建行代码曾被劈进 _refresh_axis_panel 尾部、
	# 先建后清 → 清单恒空，2026-07-27 修复）
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


## Boss Debug 只读构筑：展示本局实际抽取并挂到 ACE 的正式特殊武器。
## 普通生存局仍等 inrun-weapon-inventory 的完整图标行批次，不在这里扩张 UI 范围。
func _refresh_weapon_loadout() -> void:
	if not _weapon_loadout_panel or not _weapon_loadout_label:
		return
	_weapon_loadout_panel.visible = false
	_weapon_loadout_label.text = ""
	if not _game_scene or not "_boss_debug_weapons" in _game_scene:
		return
	var weapon_ids: Array = _game_scene._boss_debug_weapons
	if weapon_ids.is_empty():
		return
	var lines: Array[String] = []
	for raw_weapon_id in weapon_ids:
		var weapon_id := String(raw_weapon_id)
		var name_key := String(ZoneData.REWARD_WEAPON_NAME_KEYS.get(weapon_id, ""))
		var display_name := tr(name_key) if not name_key.is_empty() else weapon_id
		lines.append("• %s" % display_name)
	_weapon_loadout_label.text = "\n".join(lines)
	_weapon_loadout_panel.visible = true

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
	bars.show_state(sp.axis_points, profile, sp.milestone_bonus)
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
		var pts: int = sp.get_milestone_progress(axis)   # 判档含 "+1 轴进度"加成（与量表一致）
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
	var prefix: String = "    "
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
			parts.append(_fmt_milestone_value(str(stat), float(agg_add[stat]), "add", true))
		for stat in agg_mult:
			parts.append(_fmt_milestone_value(str(stat), float(agg_mult[stat]), "mult", true))
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
	return _fmt_milestone_value(str(m.get("stat", "")), float(m.get("value", 0.0)),
		str(m.get("kind", "add")), false)


func _fmt_milestone_value(stat: String, value: float, kind: String, spaced: bool) -> String:
	var stat_name := tr(str(SurvivorData.MILESTONE_STAT_I18N.get(stat, "")))
	var gap := " " if spaced else ""
	if kind == "mult":
		return "%s%s%+d%%" % [stat_name, gap, int(round((value - 1.0) * 100.0))]
	if stat == "armor":
		# 里程碑表存 armor 点数；UI 显示其对无穿甲伤害的等效减伤率。
		var dr_percent: int = int(round(value / (value + Aircraft.ARMOR_K) * 100.0))
		return "%s%s%+d%%" % [stat_name, gap, dr_percent]
	if stat == "max_g":
		return "%s%s%+.1f" % [stat_name, gap, value]
	return "%s%s%+d" % [stat_name, gap, int(round(value))]


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
	var mission_type: String = _zones.get_mission_type(_hover_zone_id) if _zones \
		else String(z.get("mission_type", "ground"))
	var is_bomber_escort := ZoneData.is_optional_mission_type(mission_type)
	var name_str: String = tr("ZONE_OPTIONAL_BOMBER_ESCORT_NAME") if is_bomber_escort \
		else tr(z["name_key"])
	var header_label: String = tr("ZONE_OPTIONAL_MISSION_TAG") if is_bomber_escort \
		else String(z["label"])
	var lines: PackedStringArray = [
		"[b]%s — %s[/b]" % [header_label, name_str],
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
	if difficulty == 3:
		lines.append("[color=#ff6b5f]%s[/color]" % tr("ZONE_INFO_TIER3_GLOBAL_THREAT"))

	# 奖励详情（按 reward.kind 渲染，spec airfield-liberation-zones §3.4：
	# 修正旧 desc/category 死路径——新奖励字典只有 kind/quality/id/name/weapon，
	# 读 desc/category 会恒显空描述 + "▸ 生存" 死词）
	# reward_desc = 奖励名下方那行"它到底是个什么"（技能类＝技能介绍，实体奖励＝效果说明）
	var reward_block: String
	var reward_desc: String = ""
	if _zones.is_airfield(_hover_zone_id):
		# 机场解放战区：奖励＝机场本身（ZONE_REWARD_AIRFIELD 自身已说明用途，不另加副行）
		reward_block = "  [color=#ffd864]✈ %s[/color]" % tr("ZONE_REWARD_AIRFIELD")
	elif is_bomber_escort:
		var bomber_xp := ZoneData.bomber_escort_xp_reward(difficulty)
		reward_block = "  [color=#ffd864]%s[/color]" % (tr("ZONE_REWARD_BOMBER_XP_FMT") % bomber_xp)
		reward_desc = tr("ZONE_REWARD_BOMBER_XP_DESC")
	else:
		var reward := _zones.get_reward(_hover_zone_id)
		if reward.is_empty():
			reward_block = "  %s" % tr("ZONE_REWARD_HINT_UNKNOWN")
		else:
			var glyph := "◆"
			match String(reward.get("kind", "")):
				"carrier": glyph = "⚓"
				"wingman": glyph = "✚"
				"weapon": glyph = "⌁"
			var rname: String = tr(String(reward.get("name", "")))
			reward_block = "  [color=#ffd864]%s %s[/color]" % [glyph, rname]
			var dkey := ZoneData.reward_desc_key(reward)
			if dkey != "":
				reward_desc = tr(dkey)

	# 任务描述（按 ground / air / airfield / boss 区分）
	var mission_desc_key: String
	if _hover_zone_id == &"BOSS":
		mission_desc_key = "ZONE_MISSION_BOSS"
	else:
		match mission_type:
			"air":       mission_desc_key = "ZONE_MISSION_AIR"
			"squadron":  mission_desc_key = "ZONE_MISSION_SQUADRON"
			"naval":     mission_desc_key = "ZONE_MISSION_NAVAL"
			"airfield":  mission_desc_key = "ZONE_MISSION_AIRFIELD"
			"bomber_escort": mission_desc_key = "ZONE_MISSION_BOMBER_ESCORT"
			_:           mission_desc_key = "ZONE_MISSION_GROUND"

	lines.append("")
	lines.append("[color=#aaaaaa]%s[/color]" % tr("ZONE_INFO_REWARD"))
	lines.append(reward_block)
	if reward_desc != "":
		lines.append("  [font_size=11][color=#9aa0a6]%s[/color][/font_size]" % reward_desc)
	lines.append("")
	lines.append("[color=#aaaaaa]%s[/color]" % tr("ZONE_INFO_MISSION"))
	lines.append("  %s" % tr(mission_desc_key))
	if _zones.get_mission_type(_hover_zone_id) == "bomber_escort":
		var status := _zones.get_mission_status(_hover_zone_id)
		var phase_key := "ZONE_BOMBER_PHASE_%s" % String(status.get("phase", "standby")).to_upper()
		lines.append("")
		lines.append("[color=#ffb83e][b]%s[/b][/color]" % tr("ZONE_BOMBER_STATUS_TITLE"))
		lines.append("  %s  [color=#ffd66b]%d / %d[/color]" % [tr("ZONE_BOMBER_TARGET_HP"),
			int(ceilf(float(status.get("target_hp", 150.0)))), int(status.get("target_max_hp", 150.0))])
		lines.append("  %s  [color=#ffd66b]%ds[/color]" % [tr("ZONE_BOMBER_TIME_LEFT"),
			int(ceilf(float(status.get("remaining_s", 150.0))))])
		lines.append("  %s  %d / %d    %s  %d / %d" % [tr("ZONE_BOMBER_BOMBERS"),
			int(status.get("bombers_alive", 3)), int(status.get("bombers_total", 3)),
			tr("ZONE_BOMBER_ESCORTS"), int(status.get("escorts_alive", 2)),
			int(status.get("escorts_total", 2))])
		lines.append("  [color=#ff8a66]%s  %d / %d[/color]" % [tr("ZONE_BOMBER_INTERCEPTORS"),
			int(status.get("interceptors_alive", 0)), int(status.get("interceptors_total", 0))])
		lines.append("  %s  %s" % [tr("ZONE_BOMBER_PHASE"), tr(phase_key)])

	if state == ZoneData.State.AVAILABLE:
		lines.append("")
		lines.append("[color=#88ff88]%s[/color]" % tr("ZONE_CLICK_TO_SELECT"))
	_info_label.text = "\n".join(lines)
