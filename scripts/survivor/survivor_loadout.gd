extends Node2D

## 生存模式 — 配件机库（Loadout Hangar）
##
## 左侧"市场"每次进入随机刷出有限库存（玩家不一定能买到想要的，要在现有的里挑）。
## 右侧"玩家"展示当前飞机 + 槽位预算 + 已装/未装的配件列表。
##
## 流程：survivor_select → 此场景 → building_preloader → survivor_mode
## meta `survivor_aircraft_resource` 由 survivor_select 设好，本场景保留它给后续用。

const GRID_SPACING := 80.0
const GRID_COLOR := ThemeColors.GRID_COLOR
const LINE_COLOR := ThemeColors.GRID_LINE
const BG_COLOR := ThemeColors.SCENE_BG

const TIER_BORDER: Array[Color] = [
	Color(0.55, 0.55, 0.55, 0.9),  # T1 灰
	Color(0.75, 0.75, 0.85, 0.9),  # T2 银
	Color(0.95, 0.78, 0.30, 1.0),  # T3 金
]

var _profile: PlayableAircraft = null
var _profile_path: String = ""
var _canvas: CanvasLayer
var _shop_root: VBoxContainer
var _slots_label: Label
var _merit_label: Label
var _equipped_root: VBoxContainer
var _inventory_root: VBoxContainer
var _refresh_btn: Button


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_load_profile()
	if _profile == null:
		get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")
		return
	_build_ui()
	_refresh()


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var cols := int(vp.x / GRID_SPACING) + 1
	var rows := int(vp.y / GRID_SPACING) + 1
	for i in range(cols + 1):
		var x := i * GRID_SPACING
		draw_line(Vector2(x, 0), Vector2(x, vp.y), GRID_COLOR, 1.0)
	for j in range(rows + 1):
		var y := j * GRID_SPACING
		draw_line(Vector2(0, y), Vector2(vp.x, y), GRID_COLOR, 1.0)


# ══════════════════════════════════════════════
#  Profile / Shop
# ══════════════════════════════════════════════

func _load_profile() -> void:
	if not get_tree().has_meta("survivor_aircraft_resource"):
		return
	_profile_path = get_tree().get_meta("survivor_aircraft_resource")
	_profile = load(_profile_path)


# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	var screen := VBoxContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_left = 60
	screen.offset_right = -60
	screen.offset_top = 40
	screen.offset_bottom = -40
	screen.add_theme_constant_override("separation", 12)
	_canvas.add_child(screen)

	# ── 顶部标题 ──
	var title := Label.new()
	title.text = tr("LOADOUT_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(title)

	# ── 中部：左市场 / 右玩家 ──
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 24)
	screen.add_child(middle)

	# 左：市场
	var left := _build_panel(tr("LOADOUT_SHOP_HEADER"), Color(0.95, 0.85, 0.4))
	middle.add_child(left)
	var left_inner: VBoxContainer = left.get_meta("inner")
	var hint := Label.new()
	hint.text = tr("LOADOUT_SHOP_HINT")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_inner.add_child(hint)
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_inner.add_child(left_scroll)
	_shop_root = VBoxContainer.new()
	_shop_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_root.add_theme_constant_override("separation", 8)
	left_scroll.add_child(_shop_root)

	# 货架底部：付费刷新按钮
	_refresh_btn = Button.new()
	_refresh_btn.custom_minimum_size = Vector2(0, 34)
	_refresh_btn.add_theme_font_size_override("font_size", 12)
	var rb_sb := StyleBoxFlat.new()
	rb_sb.bg_color = Color(0.18, 0.16, 0.06, 0.9)
	rb_sb.border_color = Color(0.95, 0.85, 0.4, 0.7)
	rb_sb.set_border_width_all(1)
	rb_sb.set_corner_radius_all(3)
	rb_sb.set_content_margin_all(6)
	_refresh_btn.add_theme_stylebox_override("normal", rb_sb)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	left_inner.add_child(_refresh_btn)

	# 右：玩家
	var right := _build_panel(tr("LOADOUT_PLAYER_HEADER"), ThemeColors.TEXT_TITLE_GREEN)
	middle.add_child(right)
	var right_inner: VBoxContainer = right.get_meta("inner")

	# 飞机信息条
	var ac_box := VBoxContainer.new()
	ac_box.add_theme_constant_override("separation", 2)
	right_inner.add_child(ac_box)
	var ac_name := Label.new()
	ac_name.text = "[ %s ]" % tr(_profile.display_name)
	ac_name.add_theme_font_size_override("font_size", 18)
	ac_name.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	ac_box.add_child(ac_name)
	if _profile.codename != "":
		var cn := Label.new()
		cn.text = "「%s」" % _profile.codename
		cn.add_theme_font_size_override("font_size", 12)
		cn.add_theme_color_override("font_color", ThemeColors.TEXT_CODENAME)
		ac_box.add_child(cn)

	# 槽位 + Merit
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 16)
	right_inner.add_child(stat_row)
	_slots_label = Label.new()
	_slots_label.add_theme_font_size_override("font_size", 14)
	stat_row.add_child(_slots_label)
	_merit_label = Label.new()
	_merit_label.add_theme_font_size_override("font_size", 14)
	_merit_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	stat_row.add_child(_merit_label)

	# 已装备区
	var eq_label := Label.new()
	eq_label.text = tr("LOADOUT_EQUIPPED_HEADER")
	eq_label.add_theme_font_size_override("font_size", 13)
	eq_label.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	right_inner.add_child(eq_label)
	_equipped_root = VBoxContainer.new()
	_equipped_root.add_theme_constant_override("separation", 6)
	right_inner.add_child(_equipped_root)

	# 库存区（已购未装）
	var inv_label := Label.new()
	inv_label.text = tr("LOADOUT_INVENTORY_HEADER")
	inv_label.add_theme_font_size_override("font_size", 13)
	inv_label.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	right_inner.add_child(inv_label)
	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.custom_minimum_size = Vector2(0, 160)
	right_inner.add_child(inv_scroll)
	_inventory_root = VBoxContainer.new()
	_inventory_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_root.add_theme_constant_override("separation", 6)
	inv_scroll.add_child(_inventory_root)

	# ── 底部按钮 ──
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	screen.add_child(bottom)
	var back_btn := _make_button(tr("LOADOUT_BACK"), false)
	back_btn.pressed.connect(_on_back_pressed)
	bottom.add_child(back_btn)
	var launch_btn := _make_button(tr("LOADOUT_LAUNCH"), true)
	launch_btn.pressed.connect(_on_launch_pressed)
	bottom.add_child(launch_btn)


## 构造左/右大面板（深色底 + 边框 + 顶部彩色标题）；返回 PanelContainer，
## meta["inner"] 指向供调用方填充的 VBoxContainer。
func _build_panel(header_text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.06, 0.9)
	sb.border_color = ThemeColors.GRID_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	var hd := Label.new()
	hd.text = header_text
	hd.add_theme_font_size_override("font_size", 18)
	hd.add_theme_color_override("font_color", accent)
	inner.add_child(hd)
	var sep := ColorRect.new()
	sep.color = ThemeColors.CARD_SEPARATOR_UNLOCKED
	sep.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep)

	panel.set_meta("inner", inner)
	return panel


func _make_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeColors.SELECT_BTN_NORMAL_BG if primary else Color(0.10, 0.12, 0.10, 0.9)
	sb.border_color = ThemeColors.SELECT_BTN_NORMAL_BORDER if primary else ThemeColors.GRID_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.border_color = ThemeColors.SELECT_BTN_HOVER_BORDER
	sbh.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", sbh)
	return b


# ══════════════════════════════════════════════
#  刷新
# ══════════════════════════════════════════════

func _refresh() -> void:
	var aircraft_id: StringName = _profile.id
	var used: int = LoadoutLedger.get_used_slots(aircraft_id)
	var budget: int = LoadoutLedger.get_slot_budget(aircraft_id, _profile)
	_slots_label.text = tr("LOADOUT_SLOTS_FMT") % [used, budget]
	_slots_label.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.4) if used > budget else ThemeColors.TEXT_PRIMARY)
	_merit_label.text = tr("LOADOUT_MERIT_FMT") % MeritLedger.get_total()

	# ── 左：市场 ──
	for c in _shop_root.get_children():
		c.queue_free()

	# 解锁研究区（doctrine）：固定显示在顶部，已购入则消失
	var unowned_doctrines: Array = LoadoutLedger.get_unowned_doctrines()
	if not unowned_doctrines.is_empty():
		var d_label := Label.new()
		d_label.text = tr("LOADOUT_DOCTRINE_HEADER")
		d_label.add_theme_font_size_override("font_size", 13)
		d_label.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
		_shop_root.add_child(d_label)
		for part in unowned_doctrines:
			_shop_root.add_child(_build_shop_tile(part))
		var sep := ColorRect.new()
		sep.color = ThemeColors.CARD_SEPARATOR_UNLOCKED
		sep.custom_minimum_size = Vector2(0, 1)
		_shop_root.add_child(sep)
		var stock_label := Label.new()
		stock_label.text = tr("LOADOUT_RANDOM_STOCK_HEADER")
		stock_label.add_theme_font_size_override("font_size", 13)
		stock_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		_shop_root.add_child(stock_label)

	for pid in LoadoutLedger.get_shop_ids():
		var part: EquipmentPart = LoadoutLedger.get_part(pid)
		if part != null:
			_shop_root.add_child(_build_shop_tile(part))

	# 刷新按钮：根据当前 Merit 显示价格 / 不足
	var refresh_cost: int = LoadoutLedger.SHOP_REFRESH_COST
	if MeritLedger.get_total() >= refresh_cost:
		_refresh_btn.text = tr("LOADOUT_REFRESH_FMT") % refresh_cost
		_refresh_btn.disabled = false
	else:
		_refresh_btn.text = tr("LOADOUT_REFRESH_NO_FUNDS_FMT") % refresh_cost
		_refresh_btn.disabled = true

	# ── 右：已装备 ──
	for c in _equipped_root.get_children():
		c.queue_free()
	var equipped_ids: Array = LoadoutLedger.get_equipped_ids(aircraft_id)
	if equipped_ids.is_empty():
		var ph := Label.new()
		ph.text = tr("LOADOUT_EMPTY_EQUIPPED")
		ph.add_theme_font_size_override("font_size", 12)
		ph.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
		_equipped_root.add_child(ph)
	else:
		for eid in equipped_ids:
			var part: EquipmentPart = LoadoutLedger.get_part(eid)
			if part != null:
				_equipped_root.add_child(_build_player_tile(part, true, used, budget))

	# ── 右：未装备库存 ──
	for c in _inventory_root.get_children():
		c.queue_free()
	var owned_unequipped: Array = []
	for part in LoadoutLedger.get_catalog():
		var p: EquipmentPart = part
		# Doctrine（解锁件）拥有即生效，不需要装备 → 不在玩家库存里展示
		if not p.unlocks_keywords.is_empty():
			continue
		if LoadoutLedger.is_owned(p.id) and p.id not in equipped_ids:
			owned_unequipped.append(p)
	if owned_unequipped.is_empty():
		var ph := Label.new()
		ph.text = tr("LOADOUT_EMPTY_INVENTORY")
		ph.add_theme_font_size_override("font_size", 12)
		ph.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
		_inventory_root.add_child(ph)
	else:
		owned_unequipped.sort_custom(func(a, b): return a.tier > b.tier if a.tier != b.tier else a.id < b.id)
		for p in owned_unequipped:
			_inventory_root.add_child(_build_player_tile(p, false, used, budget))


# ── 左侧：市场卡片（购买） ──
func _build_shop_tile(part: EquipmentPart) -> Control:
	var owned: bool = LoadoutLedger.is_owned(part.id)
	var can_afford: bool = MeritLedger.get_total() >= part.merit_cost

	var tile := _make_tile_panel(part)
	var inner: VBoxContainer = tile.get_meta("inner")

	# 标题 + tier 徽章
	inner.add_child(_make_tile_header(part))
	# Doctrine 走专用渲染（flavor + 解锁声明）；普通件走数值摘要
	if not part.unlocks_keywords.is_empty():
		_append_doctrine_body(inner, part)
	else:
		inner.add_child(_make_effects_label(part))

	# 操作按钮
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 12)
	if owned:
		btn.text = tr("LOADOUT_BTN_OWNED")
		btn.disabled = true
	elif not can_afford:
		btn.text = tr("LOADOUT_BTN_NO_FUNDS")
		btn.disabled = true
	else:
		btn.text = tr("LOADOUT_BTN_BUY_FMT") % part.merit_cost
		btn.pressed.connect(func(): _on_buy(part.id))
	inner.add_child(btn)
	return tile


## Doctrine 卡片专用渲染：当前 locale 的 flavor + "▸ 解锁【xx】词条的技能"
func _append_doctrine_body(inner: VBoxContainer, part: EquipmentPart) -> void:
	if part.flavor_text_key != "":
		var flavor_text := tr(part.flavor_text_key)
		if flavor_text != part.flavor_text_key:
			var flavor := Label.new()
			flavor.text = flavor_text
			flavor.add_theme_font_size_override("font_size", 11)
			flavor.add_theme_color_override("font_color", Color(0.78, 0.72, 0.88, 0.9))
			flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			inner.add_child(flavor)
	var kw_names: Array[String] = []
	for kw in part.unlocks_keywords:
		var key := "LOADOUT_KEYWORD_%s" % kw.to_upper()
		var nm := tr(key)
		kw_names.append(nm if nm != key else kw)
	var unlock_lbl := Label.new()
	unlock_lbl.text = tr("LOADOUT_DOCTRINE_UNLOCKS_FMT") % "、".join(kw_names)
	unlock_lbl.add_theme_font_size_override("font_size", 11)
	unlock_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	unlock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(unlock_lbl)


# ── 右侧：玩家卡片（装备 / 卸下） ──
func _build_player_tile(part: EquipmentPart, equipped: bool, used: int, budget: int) -> Control:
	var tile := _make_tile_panel(part)
	var inner: VBoxContainer = tile.get_meta("inner")

	inner.add_child(_make_tile_header(part))
	inner.add_child(_make_effects_label(part))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 12)
	if equipped:
		btn.text = tr("LOADOUT_BTN_UNEQUIP")
		btn.pressed.connect(func(): _on_unequip(part.id))
	else:
		var slot_fits: bool = (used + part.slot_cost) <= budget
		if slot_fits:
			btn.text = tr("LOADOUT_BTN_EQUIP")
			btn.pressed.connect(func(): _on_equip(part.id))
		else:
			btn.text = tr("LOADOUT_BTN_NO_SLOTS")
			btn.disabled = true
	inner.add_child(btn)
	return tile


func _make_tile_panel(part: EquipmentPart) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeColors.CARD_UNLOCKED_BG
	if not part.unlocks_keywords.is_empty():
		sb.border_color = Color(0.85, 0.55, 1.0)
		sb.set_border_width_all(2)
	else:
		sb.border_color = TIER_BORDER[part.tier - 1]
		sb.set_border_width_all(2 if part.tier == 3 else 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)
	panel.set_meta("inner", inner)
	return panel


func _make_tile_header(part: EquipmentPart) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.text = tr(part.display_name_key) if part.display_name_key != "" else String(part.id)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	var tier_lbl := Label.new()
	if not part.unlocks_keywords.is_empty():
		tier_lbl.text = tr("LOADOUT_BADGE_DOCTRINE")
		tier_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	else:
		tier_lbl.text = "T%d · %d □" % [part.tier, part.slot_cost]
		tier_lbl.add_theme_color_override("font_color", TIER_BORDER[part.tier - 1])
	tier_lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(tier_lbl)
	return row


func _make_effects_label(part: EquipmentPart) -> Label:
	var lbl := Label.new()
	lbl.text = _format_effects(part)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


func _format_effects(part: EquipmentPart) -> String:
	# Doctrine 解锁件走 _append_doctrine_body 专用渲染，此处仅处理普通装备件
	var lines: Array[String] = []
	if part.hp_bonus != 0.0:
		lines.append("+%d HP" % int(part.hp_bonus))
	if part.max_speed_mult != 1.0:
		lines.append("max_speed ×%.2f" % part.max_speed_mult)
	if part.max_g_bonus != 0.0:
		lines.append("+%.1f G" % part.max_g_bonus)
	if part.roll_rate_mult != 1.0:
		lines.append("roll ×%.2f" % part.roll_rate_mult)
	if part.gun_damage_mult != 1.0:
		lines.append("gun_dmg ×%.2f" % part.gun_damage_mult)
	if part.gun_range_mult != 1.0:
		lines.append("gun_range ×%.2f" % part.gun_range_mult)
	if part.gun_firerate_mult != 1.0:
		lines.append("rof ×%.2f" % part.gun_firerate_mult)
	if part.gun_ammo_mult != 1.0:
		lines.append("ammo ×%.2f" % part.gun_ammo_mult)
	if part.missile_tracking_g_mult != 1.0:
		lines.append("msl_G ×%.2f" % part.missile_tracking_g_mult)
	if part.missile_seeker_fov_mult != 1.0:
		lines.append("msl_FOV ×%.2f" % part.missile_seeker_fov_mult)
	if part.missile_reload_mult != 1.0:
		lines.append("msl_reload ×%.2f" % part.missile_reload_mult)
	if part.radar_range_mult != 1.0:
		lines.append("radar ×%.2f" % part.radar_range_mult)
	if part.radar_angle_mult != 1.0:
		lines.append("radar_∠ ×%.2f" % part.radar_angle_mult)
	if part.lock_time_mult != 1.0:
		lines.append("lock_time ×%.2f" % part.lock_time_mult)
	if part.flare_cooldown_mult != 1.0:
		lines.append("flare_cd ×%.2f" % part.flare_cooldown_mult)
	if part.lock_resistance_mult != 1.0:
		lines.append("lock_resist ×%.2f" % part.lock_resistance_mult)
	if part.flare_shield_seconds_bonus != 0.0:
		lines.append("+%.1fs flare_shield" % part.flare_shield_seconds_bonus)
	return "  ".join(lines)


# ══════════════════════════════════════════════
#  动作
# ══════════════════════════════════════════════

func _on_buy(part_id: StringName) -> void:
	if LoadoutLedger.buy_part(part_id):
		_refresh()


func _on_equip(part_id: StringName) -> void:
	if LoadoutLedger.try_equip(_profile.id, part_id, _profile):
		_refresh()


func _on_unequip(part_id: StringName) -> void:
	LoadoutLedger.unequip(_profile.id, part_id)
	_refresh()


func _on_refresh_pressed() -> void:
	if LoadoutLedger.refresh_shop_paid():
		_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")


func _on_launch_pressed() -> void:
	# 进游戏 = 消耗本批货架；下次进店重新随机
	LoadoutLedger.clear_shop()
	get_tree().change_scene_to_file("res://scenes/building_preloader.tscn")
