extends Node2D

const TerminalPageShellScript := preload("res://scripts/ui/terminal_page_shell.gd")
const TerminalUiStyleScript := preload("res://scripts/ui/terminal_ui_style.gd")

## MetaShopUI — 生涯商店界面（spec aircraft-signature-progression §2.4）
##
## 主菜单进入的局外界面；数据层全在 MetaShop autoload（本类只渲染与转发购买）。
## 全代码构建四分页：【战术学说】【机体专属】【战场支援】【机体与后勤】。

const BG_COLOR := Color("010202")

var _tabs: TabContainer
var _doctrine_box: VBoxContainer
var _signature_box: VBoxContainer
var _support_box: VBoxContainer
var _career_box: VBoxContainer

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
	var shell := TerminalPageShellScript.new()
	canvas.add_child(shell)
	var frame := TerminalUiStyleScript.build_page(
		shell.content, tr("METASHOP_TITLE"), tr("MENU_META_SHOP_DESC"), "MERIT // 03")
	var body := frame["body"] as PanelContainer
	var footer := frame["footer"] as HBoxContainer
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	body.add_child(root)

	# 功勋徽章 + 余额（样式同主菜单 _build_merit_display，实时刷新走 _refresh 整体重建）
	var merit_row := HBoxContainer.new()
	merit_row.alignment = BoxContainer.ALIGNMENT_END
	merit_row.add_theme_constant_override("separation", 8)
	merit_row.custom_minimum_size = Vector2(0, 34)
	root.add_child(merit_row)
	var coin := preload("res://scripts/meta/merit_coin_icon.gd").new()
	coin.radius = 11.0
	merit_row.add_child(coin)
	var merit_label := Label.new()
	merit_label.name = "MeritLabel"
	merit_label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), MeritLedger.get_total()]
	TerminalUiStyleScript.apply_terminal_label(
		merit_label, 15, TerminalUiStyleScript.accent())
	merit_row.add_child(merit_label)

	# 四分页：每页独立滚动，购买刷新时保留当前页。
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 0)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TerminalUiStyleScript.apply_tab_container(_tabs, TerminalUiStyleScript.accent())
	root.add_child(_tabs)
	_doctrine_box = _add_page("METASHOP_TAB_DOCTRINE")
	_signature_box = _add_page("METASHOP_TAB_SIGNATURE")
	_support_box = _add_page("METASHOP_TAB_SUPPORT")
	_career_box = _add_page("METASHOP_TAB_CAREER")

	TerminalUiStyleScript.build_footer_hint(
		footer, "%s  //  %s" % [tr("MENU_MERIT_LABEL"), str(MeritLedger.get_total())])
	TerminalUiStyleScript.build_footer_button(
		footer, tr("LOADOUT_BACK"), _on_back_pressed, 220.0)

	_refresh()

func _add_page(title_key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title_key
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, tr(title_key))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(850, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	return box

## 重建全部条目（购买/余额变化后整体重刷；仅菜单事件触发）。
func _refresh() -> void:
	if _tabs == null or not is_instance_valid(_tabs):
		return
	for box in [_doctrine_box, _signature_box, _support_box, _career_box]:
		for c in box.get_children():
			c.queue_free()
	var merit_label := find_child("MeritLabel", true, false) as Label
	if merit_label:
		merit_label.text = "%s  %d" % [tr("MENU_MERIT_LABEL"), MeritLedger.get_total()]

	# 战术学说
	for did in MetaShop.DOCTRINES:
		_doctrine_box.add_child(_build_doctrine_tile(String(did)))

	# 机体专属：已发现两列完整卡；未知只在页底显示无信息六列 ???。
	_build_signature_page()

	# 战场支援 / 机体与后勤
	for item_id in MetaShop.CATALOG:
		var category := String((MetaShop.CATALOG[item_id] as Dictionary).get("category", "career"))
		if category == "support":
			_support_box.add_child(_build_item_tile(String(item_id)))
		else:
			_career_box.add_child(_build_item_tile(String(item_id)))

func _make_section_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	TerminalUiStyleScript.apply_terminal_label(lbl, 13, color)
	return lbl

func _build_signature_page() -> void:
	var revealed: Array[Dictionary] = []
	var unknown_count := 0
	for raw in MetaShop.signature_nodes():
		var nd := raw as Dictionary
		var node_id := StringName(nd.get("id", ""))
		if node_id != &"" and AircraftCodex.is_discovered(node_id):
			revealed.append(nd)
		else:
			unknown_count += 1
	revealed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var tier_a := int(a.get("tier", 0))
		var tier_b := int(b.get("tier", 0))
		if tier_a != tier_b:
			return tier_a < tier_b
		return tr(String(a.get("name_key", ""))).naturalnocasecmp_to(
			tr(String(b.get("name_key", "")))) < 0)

	if not revealed.is_empty():
		var known_grid := GridContainer.new()
		known_grid.columns = 2
		known_grid.add_theme_constant_override("h_separation", 0)
		known_grid.add_theme_constant_override("v_separation", 0)
		known_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_signature_box.add_child(known_grid)
		for nd in revealed:
			known_grid.add_child(_build_signature_tile(nd))

	if unknown_count > 0:
		_signature_box.add_child(_make_section_label(
			tr("METASHOP_SIGNATURE_UNKNOWN"), ThemeColors.TEXT_LOCKED))
		var unknown_grid := GridContainer.new()
		unknown_grid.columns = 6
		unknown_grid.add_theme_constant_override("h_separation", 0)
		unknown_grid.add_theme_constant_override("v_separation", 0)
		unknown_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_signature_box.add_child(unknown_grid)
		for _i in unknown_count:
			unknown_grid.add_child(_build_unknown_signature_tile())

## 已发现专属商品：此处才加载机体档案与技能字典；未知占位绝不调用本函数。
func _build_signature_tile(nd: Dictionary) -> Control:
	var node_id := StringName(nd.get("id", ""))
	var item_id := MetaShop.signature_item_id(node_id)
	var upgrade := SurvivorData.signature_upgrade_for_aircraft(node_id)
	var owned := MetaShop.is_owned(item_id)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	sb.border_color = Color(SurvivorUpgradeUI.SIG_FRAME_COLOR, 0.72)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var badge := Label.new()
	badge.text = "%s · T%d" % [tr("UPGRADE_SIGNATURE_BADGE"), int(nd.get("tier", 0))]
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", SurvivorUpgradeUI.SIG_FRAME_COLOR)
	box.add_child(badge)
	var aircraft := Label.new()
	aircraft.text = tr(String(nd.get("name_key", "")))
	aircraft.add_theme_font_size_override("font_size", 16)
	aircraft.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	box.add_child(aircraft)
	var skill := Label.new()
	skill.text = tr(String(upgrade.get("name", "")))
	skill.add_theme_font_size_override("font_size", 14)
	skill.add_theme_color_override("font_color", Color(1.0, 0.78, 0.92))
	box.add_child(skill)
	var desc := Label.new()
	desc.text = tr(String(upgrade.get("desc", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
	box.add_child(desc)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
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
	TerminalUiStyleScript.apply_button(btn, TerminalUiStyleScript.accent())
	box.add_child(btn)
	return panel

func _build_unknown_signature_tile() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 54)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.58)
	sb.border_color = Color(TerminalUiStyleScript.accent(), 0.20)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = tr("METASHOP_SIGNATURE_UNKNOWN")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	panel.add_child(label)
	return panel

## 学说条目。三态：未上架灰条（先集齐入门学说）/ 已拥有 / 可买·买不起
## 内容 = 名称 + 词条声明（▸ 解锁【xx】词条的技能）+ flavor 文
func _build_doctrine_tile(doctrine_id: String) -> Control:
	var def: Dictionary = MetaShop.DOCTRINES[doctrine_id]
	var listed: bool = MetaShop.is_listed(doctrine_id)
	var owned: bool = MetaShop.is_owned(doctrine_id)

	var panel := PanelContainer.new()
	TerminalUiStyleScript.apply_panel(panel,
		Color(TerminalUiStyleScript.accent(), 0.72 if listed else 0.20),
		Color(0.0, 0.0, 0.0, 0.78 if listed else 0.52), 9.0)

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
		TerminalUiStyleScript.apply_button(btn, TerminalUiStyleScript.accent())
		row.add_child(btn)

	return panel

## 单件商品条目。三态：未上架灰条（条件文本）/ 已拥有 / 可买·买不起
func _build_item_tile(item_id: String) -> Control:
	var def: Dictionary = MetaShop.CATALOG[item_id]
	var listed: bool = MetaShop.is_listed(item_id)
	var owned: bool = MetaShop.is_owned(item_id)

	var panel := PanelContainer.new()
	TerminalUiStyleScript.apply_panel(panel,
		Color(TerminalUiStyleScript.accent(), 0.72 if listed else 0.20),
		Color(0.0, 0.0, 0.0, 0.78 if listed else 0.52), 9.0)

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
		TerminalUiStyleScript.apply_button(btn, TerminalUiStyleScript.accent())
		row.add_child(btn)

	return panel

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
