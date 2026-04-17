class_name TacticalMap
extends CanvasLayer

## 战术地图（Tab 打开）
##
## P2：地图缩略图 + 战区圆（A/B/C/D + Boss）+ 玩家位置 + 悬停/点击选区
## 点击可选战区 → 发信号 zone_selected → survivor_mode 关闭地图 + 激活屏外箭头
## 奖励预览暂时只显示占位文本，具体奖励池由 P3 实现

signal zone_selected(zone_id: StringName)

const BG_COLOR := Color(0.02, 0.03, 0.04, 0.92)
const GRID_COLOR := Color(0.15, 0.35, 0.35, 0.35)
const FRAME_COLOR := Color(0.55, 0.85, 0.85, 0.8)
const TEXT_COLOR := Color(0.7, 0.95, 0.95, 0.95)
const PLAYER_COLOR := Color(0.4, 1.0, 0.4, 1.0)

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
var _is_open: bool = false
var _adbs: AdbsManager = null  ## 用于在缩略图上画 ADBS 目标实时位置

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

func setup(world_rect: Rect2, player: Aircraft, zones: ZoneData) -> void:
	_world_rect = world_rect
	_player = player
	_zones = zones

func set_adbs(adbs: AdbsManager) -> void:
	_adbs = adbs

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open: close()
	else: open()

func open() -> void:
	_is_open = true
	_root.visible = true
	get_tree().paused = true

func close() -> void:
	_is_open = false
	_root.visible = false
	get_tree().paused = false

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
	# 底色 = 海
	_map_panel.draw_rect(_map_rect, MapGeography.SEA_COLOR)
	# 陆地填充 + 海岸线
	_draw_geography(size)
	# 城区点
	_draw_cities(size)
	# 框
	_map_panel.draw_rect(_map_rect, FRAME_COLOR, false, 2.0)

	# 战区圆 + 标签
	if _zones:
		_draw_zones(size)
		_draw_boss(size)

	# ADBS 目标实时位置（黄色菱形 + 朝向短线，带脉冲）
	_draw_adbs_markers(size)

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

## 缩略图：海岸线地图（陆地填充 + 海岸线 + 城区 + 高速）
func _draw_geography(size: Vector2) -> void:
	var land_list := MapGeography.get_land_polygons()
	# 陆地填充
	for i in range(land_list.size()):
		var poly: PackedVector2Array = land_list[i]
		var mapped := _map_poly(poly, size)
		_map_panel.draw_colored_polygon(mapped, MapGeography.LAND_COLOR)
		var n: int = mapped.size()
		if i < 2:
			# 主陆块：首尾贴地图边不描
			if n >= 4:
				for j in range(1, n - 1):
					_map_panel.draw_line(mapped[j], mapped[j + 1], MapGeography.COAST_COLOR, 1.4)
		else:
			# 岛屿：闭合描
			for j in range(n):
				_map_panel.draw_line(mapped[j], mapped[(j + 1) % n], MapGeography.COAST_COLOR, 1.1)

## 缩略图：城区多边形 + 高速
func _draw_cities(size: Vector2) -> void:
	# 城区
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		var mapped := _map_poly(poly, size)
		if mapped.size() < 3:
			continue
		_map_panel.draw_colored_polygon(mapped, MapGeography.URBAN_FILL)
		for i in range(mapped.size()):
			_map_panel.draw_line(mapped[i], mapped[(i + 1) % mapped.size()], MapGeography.URBAN_LINE, 0.8)
	# 高速
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		var mapped := _map_poly(pts, size)
		var color: Color = hw.get("color", MapGeography.HIGHWAY_SUB)
		for i in range(mapped.size() - 1):
			_map_panel.draw_line(mapped[i], mapped[i + 1], color, 1.2)
	# Aqua-Line 虚线
	var aq: PackedVector2Array = MapGeography.AQUALINE_PATH
	if aq.size() >= 2:
		var mapped_aq := _map_poly(aq, size)
		for i in range(mapped_aq.size() - 1):
			_map_panel.draw_dashed_line(mapped_aq[i], mapped_aq[i + 1], MapGeography.AQUALINE_COLOR, 1.0, 4.0)

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
	var z := ZoneData.BOSS_ZONE
	var zid: StringName = z["id"]
	if _should_hide_zone(zid):
		return
	_draw_one_zone(z, zid, size)

## 未解锁（LOCKED）的战区/BOSS 在玩家还没攻克前完全不显示——不剧透
func _should_hide_zone(zid: StringName) -> bool:
	if not _zones:
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_click_zone(event.position)

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
	if not _zones or _zones.get_state(zid) != ZoneData.State.AVAILABLE:
		return
	if _zones.select_zone(zid):
		zone_selected.emit(zid)
		close()

## 命中检测：返回 map_pos 所在的战区 id（就近），没命中或隐藏的都返回空
func _zone_id_at(map_pos: Vector2) -> StringName:
	if not _zones or _world_rect.size.x <= 0.0:
		return &""
	var size := _map_panel.size
	# Boss 优先级最高（仅在显示时命中）
	var bz := ZoneData.BOSS_ZONE
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

	# 奖励详情（具体技能名 + 描述 + 类别提示）
	var reward_block: String
	var reward := _zones.get_reward(_hover_zone_id)
	if reward.is_empty():
		reward_block = "  %s" % tr("ZONE_REWARD_HINT_UNKNOWN")
	else:
		var rname: String = tr(reward.get("name", ""))
		var rdesc: String = tr(reward.get("desc", ""))
		var rcat: String = tr(_zones.get_reward_category_key(_hover_zone_id))
		reward_block = "  [color=#ffd864]%s[/color]\n  [color=#aaccaa]%s[/color]\n  [color=#888888]%s[/color]" % [rname, rdesc, rcat]

	# 任务描述（按 ground / air 区分）
	var mission_type: String = _zones.get_mission_type(_hover_zone_id) if _zones else z.get("mission_type", "ground")
	var mission_desc_key: String
	match mission_type:
		"air":       mission_desc_key = "ZONE_MISSION_AIR"
		"squadron":  mission_desc_key = "ZONE_MISSION_SQUADRON"
		"elite":     mission_desc_key = "ZONE_MISSION_ELITE"
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
