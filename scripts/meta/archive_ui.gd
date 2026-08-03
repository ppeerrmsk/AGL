extends Node2D

## ArchiveUI — 资料库（spec career-archive §2.6 / §2.7）
##
## 主菜单进入的局外界面，两个并列分类（顶部页签切换）：
##   ① 敌人图鉴 —— 全部敌人 + 累计击败数（数据 CareerArchive，清单 EnemyCodex）
##   ② 游戏信息 —— 全部机制说明：鼠标/键位每个操作、加力模式、飞行武器门道、
##      战区循环（清单 GameInfoCodex；战术地图的小技巧在此可回看）
##
## 本类只渲染：条目清单在两个 Codex，包装（王牌主色/lore/徽章）在 AceSquadProfiles。

const BG_COLOR := Color(0.04, 0.06, 0.05)
const COL_DIM := Color(0.45, 0.45, 0.42)
const COL_INFO := Color(0.45, 0.72, 0.95)      ## 游戏信息分类主色（与敌方暖色区分）
const COL_TIP := Color(0.95, 0.55, 0.45)       ## 战场情报角标（对齐 Tab 小技巧的红调）
const ROW_W := 640

## 顺序即页签顺序：先「游戏信息」（新玩家进来最需要的是说明书），再「敌人图鉴」（收集品）
enum Category { INFO, ENEMY }

var _category: int = Category.INFO
var _rows: VBoxContainer
var _tab_buttons: Array[Button] = []

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back_pressed()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)
	canvas.add_child(root)

	var title := Label.new()
	title.text = tr("ARCHIVE_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.8, 0.72, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 分类页签
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	_tab_buttons.clear()
	for spec in [
		{"cat": Category.INFO, "key": "ARCHIVE_TAB_INFO"},
		{"cat": Category.ENEMY, "key": "ARCHIVE_TAB_ENEMY"},
	]:
		var btn := Button.new()
		btn.text = tr(String(spec["key"]))
		btn.custom_minimum_size = Vector2(190, 34)
		btn.add_theme_font_size_override("font_size", 14)
		var cat := int(spec["cat"])
		btn.pressed.connect(func() -> void: _switch_to(cat))
		tabs.add_child(btn)
		_tab_buttons.append(btn)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 2)
	root.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.custom_minimum_size = Vector2(ROW_W + 20, 440)
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.custom_minimum_size = Vector2(ROW_W, 0)
	scroll.add_child(_rows)

	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 10)
	root.add_child(sep2)

	var back_btn := Button.new()
	back_btn.text = tr("LOADOUT_BACK")
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_on_back_pressed)
	root.add_child(back_btn)

	_switch_to(Category.INFO)

func _switch_to(cat: int) -> void:
	_category = cat
	for i in range(_tab_buttons.size()):
		var on := (i == cat)
		_tab_buttons[i].add_theme_color_override("font_color",
			Color(0.95, 0.85, 0.55) if on else Color(0.55, 0.55, 0.5))
		_tab_buttons[i].disabled = on   # 当前页签不可再点，兼作选中态
	_rebuild_rows()

func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	if _category == Category.ENEMY:
		_build_enemy_rows()
	else:
		_build_info_rows()

# ══════════════════════════════════════════════
#  ① 敌人图鉴
# ══════════════════════════════════════════════

func _build_enemy_rows() -> void:
	var prog := EnemyCodex.progress()
	_rows.add_child(_make_caption("%s      %s" % [
		tr("CODEX_SUBTITLE"), tr("CODEX_PROGRESS_FMT") % [prog.x, prog.y]]))
	for section in EnemyCodex.SECTIONS:
		var entries: Array = EnemyCodex.entries_of(int(section["kind"]))
		if entries.is_empty():
			continue
		var done := 0
		for e in entries:
			if EnemyCodex.is_unlocked(e):
				done += 1
		_rows.add_child(_make_section_header(tr(String(section["title_key"])),
			"%d / %d" % [done, entries.size()]))
		for e in entries:
			_rows.add_child(_make_enemy_row(e))

func _make_enemy_row(entry: Dictionary) -> PanelContainer:
	var kind := int(entry["kind"])
	var id := String(entry["id"])
	var defeats: int = EnemyCodex.defeat_count(entry)
	var encounters: int = EnemyCodex.encounter_count(entry)
	var unlocked := EnemyCodex.is_unlocked(entry)
	var col: Color = EnemyCodex.color_of(entry) if unlocked else COL_DIM
	var is_ace := kind == EnemyCodex.Kind.ACE

	var panel := _make_panel(col, unlocked)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	if is_ace:
		var emblem := AceEmblemIcon.new(id, col, 15.0)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(emblem)
	else:
		hbox.add_child(_make_kind_icon(kind, col))

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 1)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_box)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 14 if is_ace else 13)
	if unlocked:
		var nm := tr(EnemyCodex.name_key(entry))
		head.text = "%s · %s" % [AceSquadProfiles.codename(id), nm] if is_ace else nm
		head.add_theme_color_override("font_color", col.lightened(0.25))
	else:
		head.text = "???"
		head.add_theme_color_override("font_color", COL_DIM)
	text_box.add_child(head)

	text_box.add_child(_make_body(
		tr(EnemyCodex.desc_key(entry)) if unlocked else tr("CODEX_LOCKED"),
		Color(0.72, 0.72, 0.66) if unlocked else Color(0.4, 0.4, 0.38, 0.8)))

	var stats := Label.new()
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", Color(0.62, 0.62, 0.58))
	stats.text = _stats_text(entry, defeats, encounters, unlocked)
	text_box.add_child(stats)

	var tally := Label.new()
	tally.text = "×%d" % defeats if unlocked else "—"
	tally.add_theme_font_size_override("font_size", 18)
	tally.add_theme_color_override("font_color", col.lightened(0.2) if unlocked else COL_DIM)
	tally.custom_minimum_size = Vector2(56, 0)
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tally.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(tally)
	return panel

func _stats_text(entry: Dictionary, defeats: int, encounters: int, unlocked: bool) -> String:
	var kind := int(entry["kind"])
	if not unlocked:
		return tr("CODEX_MET_FMT") % encounters if encounters > 0 else tr("CODEX_NEVER_MET")
	var parts := PackedStringArray()
	match kind:
		EnemyCodex.Kind.GROUND:
			parts.append(tr("CODEX_DESTROYED_FMT") % defeats)
		EnemyCodex.Kind.ACE, EnemyCodex.Kind.BOSS:
			parts.append(tr("CODEX_DEFEATED_FMT") % defeats)
			if encounters > 0:
				parts.append(tr("CODEX_ENCOUNTERS_FMT") % encounters)
		_:
			parts.append(tr("CODEX_SHOTDOWN_FMT") % defeats)
	if kind == EnemyCodex.Kind.ACE:
		var first: String = CareerArchive.get_ace_first_defeat_date(String(entry["id"]))
		if first != "":
			parts.append(tr("CODEX_FIRST_FMT") % first)
		if String(entry["id"]) == "orion":
			parts.append(tr("CODEX_ORION_UNIT_FMT") % OrionNemesisEvent.designation(defeats))
	return "  ·  ".join(parts)

## 分类图标（非王牌）：极简线框——飞机三角 / 双横杠 / 地面方块 / BOSS 菱形
func _make_kind_icon(kind: int, col: Color) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func() -> void:
		var c := icon.size * 0.5
		var r := 10.0
		var w := 1.6
		match kind:
			EnemyCodex.Kind.AIR:
				icon.draw_polyline(PackedVector2Array([
					c + Vector2(0, -r), c + Vector2(r * 0.75, r * 0.7),
					c + Vector2(0, r * 0.3), c + Vector2(-r * 0.75, r * 0.7),
					c + Vector2(0, -r)]), col, w)
			EnemyCodex.Kind.ADDS:
				icon.draw_line(c + Vector2(-r, -r * 0.35), c + Vector2(r, -r * 0.35), col, w)
				icon.draw_line(c + Vector2(-r * 0.7, r * 0.45), c + Vector2(r * 0.7, r * 0.45), col, w)
			EnemyCodex.Kind.GROUND:
				icon.draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.7), Vector2(r * 1.2, r * 1.0)), col, false, w)
				icon.draw_line(c + Vector2(-r, r * 0.5), c + Vector2(r, r * 0.5), col, w)
			_:
				icon.draw_polyline(PackedVector2Array([
					c + Vector2(0, -r), c + Vector2(r, 0),
					c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, w)
	)
	return icon

# ══════════════════════════════════════════════
#  ② 游戏信息
# ══════════════════════════════════════════════

func _build_info_rows() -> void:
	_rows.add_child(_make_caption(tr("INFO_SUBTITLE")))
	for section in GameInfoCodex.SECTIONS:
		var entries: Array = GameInfoCodex.entries_of(String(section["id"]))
		if entries.is_empty():
			continue
		_rows.add_child(_make_section_header(tr(String(section["title_key"])), ""))
		for e in entries:
			_rows.add_child(_make_info_row(e))

func _make_info_row(entry: Dictionary) -> PanelContainer:
	var is_tip: bool = GameInfoCodex.is_tip(entry)
	var col := COL_TIP if is_tip else COL_INFO
	var panel := _make_panel(col, true)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# 按键徽标（有 key 的条目）：等宽小方块，扫一眼就知道按哪个
	var label := GameInfoCodex.key_label(entry)
	var badge := Label.new()
	badge.custom_minimum_size = Vector2(74, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	if label != "":
		badge.text = "[ %s ]" % label
		badge.add_theme_color_override("font_color", Color(1.0, 0.88, 0.54))
	elif is_tip:
		badge.text = tr("INFO_BADGE_TIP")
		badge.add_theme_color_override("font_color", COL_TIP)
	else:
		badge.text = "·"
		badge.add_theme_color_override("font_color", COL_DIM)
	hbox.add_child(badge)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 1)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_box)

	var head := Label.new()
	head.text = tr(GameInfoCodex.title_key(entry))
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", col.lightened(0.25))
	text_box.add_child(head)

	# 小技巧正文自带 BBCode（Tab 轮播复用同一条译文）→ 统一用 RichTextLabel 渲染
	text_box.add_child(_make_body(tr(GameInfoCodex.body_key(entry)), Color(0.76, 0.78, 0.76)))
	return panel

# ══════════════════════════════════════════════
#  公共构件
# ══════════════════════════════════════════════

func _make_panel(col: Color, solid: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.07, 0.9)
	style.border_color = Color(col.r, col.g, col.b, 0.5 if solid else 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_body(text: String, col: Color) -> RichTextLabel:
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = text
	body.add_theme_font_size_override("normal_font_size", 11)
	body.add_theme_font_size_override("bold_font_size", 11)
	body.add_theme_color_override("default_color", col)
	return body

func _make_caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", COL_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _make_section_header(title: String, suffix: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 12)
	box.add_child(pad)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.5))
	box.add_child(label)
	if suffix != "":
		var count := Label.new()
		count.text = suffix
		count.add_theme_font_size_override("font_size", 11)
		count.add_theme_color_override("font_color", COL_DIM)
		count.size_flags_vertical = Control.SIZE_SHRINK_END
		box.add_child(count)
	return box

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
