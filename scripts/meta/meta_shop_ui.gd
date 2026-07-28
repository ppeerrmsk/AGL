extends Node2D

## MetaShopUI — 生涯商店界面（spec career-shop §4 + doctrine-unlocks §3.5）
##
## 主菜单进入的局外界面；数据层全在 MetaShop autoload（本类只渲染与转发购买）。
## 全代码构建 UI，两个分区：【战术学说】（doctrine 词条解锁件，原配件机库搬入）
## 在上、【生涯商品】在下；商品条目三态按钮复用 LOADOUT_BTN_BUY_FMT / OWNED / NO_FUNDS。

const BG_COLOR := Color(0.04, 0.06, 0.05)

var _items_box: VBoxContainer

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()
	# 功勋变化（购买扣费 / 调试热键）→ 刷新按钮三态
	MeritLedger.merit_changed.connect(func(_total: int, _delta: int) -> void: _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	canvas.add_child(root)

	# 标题
	var title := Label.new()
	title.text = tr("METASHOP_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 功勋徽章 + 余额（样式同主菜单 _build_merit_display，实时刷新走 _refresh 整体重建）
	var merit_row := HBoxContainer.new()
	merit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	merit_row.add_theme_constant_override("separation", 8)
	root.add_child(merit_row)
	var coin := preload("res://scripts/meta/merit_coin_icon.gd").new()
	coin.radius = 11.0
	merit_row.add_child(coin)
	var merit_label := Label.new()
	merit_label.name = "MeritLabel"
	merit_label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), MeritLedger.get_total()]
	merit_label.add_theme_font_size_override("font_size", 18)
	merit_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	merit_row.add_child(merit_label)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	root.add_child(sep)

	# 商品列表（居中定宽）
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 10)
	_items_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_items_box.custom_minimum_size = Vector2(560, 0)
	root.add_child(_items_box)

	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 16)
	root.add_child(sep2)

	# 返回
	var back_btn := Button.new()
	back_btn.text = tr("LOADOUT_BACK")
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_on_back_pressed)
	root.add_child(back_btn)

	_refresh()

## 重建全部条目（购买/余额变化后整体重刷，条目 ≤9 件无性能压力）
func _refresh() -> void:
	if _items_box == null or not is_instance_valid(_items_box):
		return
	for c in _items_box.get_children():
		c.queue_free()
	var merit_label := find_child("MeritLabel", true, false) as Label
	if merit_label:
		merit_label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), MeritLedger.get_total()]
	# ── 分区一：战术学说（doctrine 词条解锁件）──
	_items_box.add_child(_make_section_label(tr("LOADOUT_DOCTRINE_HEADER"), Color(0.85, 0.55, 1.0)))
	for did in MetaShop.DOCTRINES:
		_items_box.add_child(_build_doctrine_tile(String(did)))
	# ── 分区二：生涯商品 ──
	_items_box.add_child(_make_section_label(tr("METASHOP_SECTION_ITEMS"), Color(0.85, 0.75, 0.35)))
	for item_id in MetaShop.CATALOG:
		_items_box.add_child(_build_item_tile(String(item_id)))

func _make_section_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	return lbl

## 学说条目。三态：未上架灰条（先集齐入门学说）/ 已拥有 / 可买·买不起
## 内容 = 名称 + 词条声明（▸ 解锁【xx】词条的技能）+ flavor 文
func _build_doctrine_tile(doctrine_id: String) -> Control:
	var def: Dictionary = MetaShop.DOCTRINES[doctrine_id]
	var listed: bool = MetaShop.is_listed(doctrine_id)
	var owned: bool = MetaShop.is_owned(doctrine_id)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeColors.CARD_UNLOCKED_BG if listed else ThemeColors.CARD_LOCKED_BG
	sb.border_color = (def["color"] as Color) * Color(1, 1, 1, 0.7) if listed else ThemeColors.CARD_LOCKED_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 3)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)

	# 名称行：徽章 + 名称
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	text_box.add_child(name_row)
	var badge := Label.new()
	badge.text = tr("LOADOUT_BADGE_DOCTRINE")
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", def["color"] if listed else ThemeColors.TEXT_LOCKED)
	name_row.add_child(badge)
	var name_lbl := Label.new()
	name_lbl.text = tr(String(def["name_key"]))
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color",
		ThemeColors.TEXT_PRIMARY if listed else ThemeColors.TEXT_LOCKED)
	name_row.add_child(name_lbl)

	if listed:
		# 词条声明：▸ 解锁【xx】词条的技能
		var unlocks_lbl := Label.new()
		unlocks_lbl.text = tr("LOADOUT_DOCTRINE_UNLOCKS_FMT") % tr(String(def["kw_key"]))
		unlocks_lbl.add_theme_font_size_override("font_size", 11)
		unlocks_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
		text_box.add_child(unlocks_lbl)
		# flavor 文（当前 locale）
		var flavor_lbl := Label.new()
		flavor_lbl.text = tr(String(def["flavor_key"]))
		flavor_lbl.add_theme_font_size_override("font_size", 11)
		flavor_lbl.add_theme_color_override("font_color", (def["color"] as Color) * Color(1, 1, 1, 0.85))
		flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(flavor_lbl)
	else:
		# 未上架：显示上架条件句（信息察觉）
		var hint_lbl := Label.new()
		hint_lbl.text = tr("METASHOP_LOCKED_HINT_DOCTRINE")
		hint_lbl.add_theme_font_size_override("font_size", 11)
		hint_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
		text_box.add_child(hint_lbl)

	if listed:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.add_theme_font_size_override("font_size", 12)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if owned:
			btn.text = tr("LOADOUT_BTN_OWNED")
			btn.disabled = true
		elif MeritLedger.get_total() < MetaShop.get_price(doctrine_id):
			btn.text = tr("LOADOUT_BTN_NO_FUNDS")
			btn.disabled = true
		else:
			btn.text = tr("LOADOUT_BTN_BUY_FMT") % MetaShop.get_price(doctrine_id)
			btn.pressed.connect(func() -> void:
				if MetaShop.buy(doctrine_id):
					_refresh())
		row.add_child(btn)

	return panel

## 单件商品条目。三态：未上架灰条（条件文本）/ 已拥有 / 可买·买不起
func _build_item_tile(item_id: String) -> Control:
	var def: Dictionary = MetaShop.CATALOG[item_id]
	var listed: bool = MetaShop.is_listed(item_id)
	var owned: bool = MetaShop.is_owned(item_id)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeColors.CARD_UNLOCKED_BG if listed else ThemeColors.CARD_LOCKED_BG
	sb.border_color = Color(0.85, 0.75, 0.35, 0.7) if listed else ThemeColors.CARD_LOCKED_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 3)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)

	var name_lbl := Label.new()
	name_lbl.text = tr(String(def["name_key"]))
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color",
		ThemeColors.TEXT_PRIMARY if listed else ThemeColors.TEXT_LOCKED)
	text_box.add_child(name_lbl)

	var desc_lbl := Label.new()
	# 未上架：描述位显示上架条件（信息察觉——玩家知道怎么解锁这件货）
	desc_lbl.text = tr(String(def["desc_key"])) if listed else tr(String(def["locked_hint_key"]))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color",
		ThemeColors.TEXT_DESC_UNLOCKED if listed else ThemeColors.TEXT_LOCKED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc_lbl)

	if listed:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.add_theme_font_size_override("font_size", 12)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if owned:
			btn.text = tr("LOADOUT_BTN_OWNED")
			btn.disabled = true
		elif MeritLedger.get_total() < MetaShop.get_price(item_id):
			btn.text = tr("LOADOUT_BTN_NO_FUNDS")
			btn.disabled = true
		else:
			btn.text = tr("LOADOUT_BTN_BUY_FMT") % MetaShop.get_price(item_id)
			btn.pressed.connect(func() -> void:
				if MetaShop.buy(item_id):
					_refresh())
		row.add_child(btn)

	return panel

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
