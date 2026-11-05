class_name EvolutionDetailPanel
extends VBoxContainer

## 固定宽度的悬停内容。先回答能否进化，再给武器、对比与专属说明。
const CONTENT_W := 504.0
const ModelPreview := preload("res://scripts/survivor/aircraft_model_preview.gd")
var _accent: Color = HudPreferences.hud_color()
var shown_node: StringName = &""

const STAT_ROWS: Array = [
	{"id": "hp", "key": "EVO_STAT_HP", "fmt": "%d", "higher_better": true},
	{"id": "speed", "key": "EVO_STAT_SPEED", "fmt": "%d km/h", "higher_better": true},
	{"id": "accel", "key": "EVO_STAT_ACCEL", "fmt": "%.0f m/s²", "higher_better": true},
	{"id": "g", "key": "EVO_STAT_G", "fmt": "%.1f G", "higher_better": true},
	{"id": "roll", "key": "EVO_STAT_ROLL", "fmt": "%.1f rad/s", "higher_better": true},
	{"id": "radar", "key": "EVO_STAT_RADAR", "fmt": "%.1f km", "higher_better": true},
	{"id": "lock", "key": "EVO_STAT_LOCK", "fmt": "%.1f s", "higher_better": false},
	{"id": "missile", "key": "EVO_STAT_MISSILE", "fmt": "%d", "higher_better": true},
]


func _init() -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(CONTENT_W, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS


func show_node(node_id: StringName, current_id: StringName, team_level: int, axis_points: Dictionary) -> void:
	_accent = HudPreferences.hud_color()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	shown_node = node_id
	var nd := EvolutionSystem.node_of(node_id)
	if nd.is_empty():
		return
	var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
	var current := EvolutionSystem.node_of(current_id)
	var base := AircraftDB.get_profile(StringName(current.get("profile", "")))
	var model := ModelPreview.new()
	model.name = "AircraftModel"
	model.custom_minimum_size = Vector2(CONTENT_W, 144.0)
	model.modulate = _accent
	model.show_profile(prof)
	add_child(model)
	add_child(_label(tr(String(nd.get("name_key", ""))), 36.0, _accent))
	add_child(_label(tr(EvolutionSystem.category_key_of(nd)), 18.0, Color(_accent, 0.65)))
	if prof and not prof.card_desc.is_empty():
		_paragraph(tr(prof.card_desc))
	if node_id != current_id:
		_build_requirements(nd, team_level, axis_points)
		if not current.get("exits", []).has(String(node_id)):
			add_child(_label(tr("EVO_NOT_DIRECT"), 18.0, ThemeColors.UI_WARNING_YELLOW))
	else:
		add_child(_label(tr("EVOLUTION_DETAIL_CURRENT"), 18.0, _accent))
	if prof:
		_section_header(tr("EVOLUTION_DETAIL_WEAPONS"))
		_paragraph(AircraftDB.weapons_summary(prof))
		_build_stats(prof, base if node_id != current_id else null)
	_build_signature(node_id)


func _build_signature(node_id: StringName) -> void:
	_section_header(tr("EVOLUTION_DETAIL_SIGNATURE"))
	var signature := SurvivorData.signature_upgrade_for_aircraft(node_id)
	if signature.is_empty():
		_paragraph(tr("EVO_SIGNATURE_UNAVAILABLE"))
		return
	_paragraph(tr(String(signature.get("name", ""))), _accent)
	_paragraph(tr(String(signature.get("desc", ""))))
	_paragraph(tr("EVO_SIGNATURE_NOTE"))


func _build_stats(prof: PlayableAircraft, base_prof: PlayableAircraft) -> void:
	var vals := _effective_stats(prof)
	var base_vals := _effective_stats(base_prof)
	_section_header(tr("EVOLUTION_DETAIL_PERKS") if base_vals.is_empty() else tr("EVO_BASE_COMPARISON"))
	for row in STAT_ROWS:
		var value: float = vals.get(row["id"], 0.0)
		var delta := "—"
		var color := Color(_accent, 0.65)
		if not base_vals.is_empty():
			var base: float = base_vals.get(row["id"], 0.0)
			var pct := 0.0 if absf(base) < 0.0001 else (value - base) / absf(base) * 100.0
			if absf(pct) >= 0.5:
				delta = "%+.0f%%" % pct
				color = _accent if (pct > 0.0) == bool(row["higher_better"]) else ThemeColors.UI_WARNING_YELLOW
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		add_child(line)
		for data in [[tr(String(row["key"])), 220.0, Color(_accent, 0.65)],
			[String(row["fmt"]) % value, 160.0, _accent], [delta, 124.0, color]]:
			var label := _label(data[0], 18.0, data[2])
			label.custom_minimum_size.x = data[1]
			line.add_child(label)


func _build_requirements(nd: Dictionary, team_level: int, axis_points: Dictionary) -> void:
	_section_header(tr("EVOLUTION_DETAIL_REQ"))
	_add_req_row(tr("EVOLUTION_REQ_LEVEL"), team_level, EvolutionSystem.min_level_of(nd))
	for row in _gate_rows(nd, axis_points):
		_add_req_row(row["label"], row["have"], row["need"])


func _add_req_row(title: String, have: int, need: int) -> void:
	var satisfied := have >= need
	add_child(_label("%s  %s  %d / %d" % ["✓" if satisfied else "×", title, have, need],
		18.0, Color(_accent, 0.65) if satisfied else ThemeColors.UI_WARNING_YELLOW))


## gates 全量行（含已达标的），语义对齐 EvolutionSystem.gates_missing
func _gate_rows(nd: Dictionary, axis_points: Dictionary) -> Array:
	var out: Array = []
	var g := EvolutionSystem.gates_of(nd)
	for k in g:
		var ks := String(k)
		if ks == "any":
			var alt: Dictionary = g[k]
			var labels: PackedStringArray = []
			var ok := false
			var best_have := 0
			var best_need := 0
			for ak in alt:
				labels.append(_axis_label(String(ak)))
			for ak in alt:
				var have_a: int = int(axis_points.get(StringName(String(ak)), 0))
				var need_a: int = int(alt[ak])
				if have_a >= need_a:
					ok = true
					best_have = have_a
					best_need = need_a
					break
				if best_need == 0 or need_a - have_a < best_need - best_have:
					best_have = have_a
					best_need = need_a
			out.append({
				"label": _fmt1("EVOLUTION_GATE_ANY_FMT", " / ".join(labels)),
				"have": best_have if not ok else best_need,
				"need": best_need,
			})
			continue
		var have: int = int(axis_points.get(StringName(ks), 0))
		out.append({"label": _gate_label(ks), "have": have, "need": int(g[k])})
	return out


## 单占位符 tr 格式化，缺翻译时 tr() 原样返回 key（无 %s）会炸格式化 —— 兜底直接返回值本身
func _fmt1(key: String, value: String) -> String:
	var f := tr(key)
	return (f % value) if f.contains("%s") else value


func _gate_label(key: String) -> String:
	return _axis_label(key)


func _axis_label(axis: String) -> String:
	return tr(str(SurvivorData.AXIS_I18N_KEY.get(StringName(axis), axis)))


## 档案生效属性（base_params × PlayableAircraft 倍率），进化前后可直接相减比较
static func _effective_stats(prof: PlayableAircraft) -> Dictionary:
	if prof == null or prof.base_params == null:
		return {}
	var p: AircraftParams = prof.base_params
	return {
		"hp": p.max_hp,
		"speed": p.max_speed * prof.max_speed_mult,
		"accel": p.acceleration * prof.acceleration_mult,
		"g": p.max_g + prof.max_g_bonus,
		"roll": p.roll_rate * prof.roll_rate_mult,
		"radar": p.radar_range * prof.radar_range_mult * 2.0 / 1000.0,  # 像素→km（1px = 2m）
		"lock": p.lock_time * prof.lock_time_mult,
		"missile": float(prof.missile_count_override if prof.missile_count_override >= 0
			else (p.missile.max_count if p.missile else 0)),
	}


## 该节点当前是否可进化（LV + 属性双门 且 是当前机的直接出口）
static func _can_evolve(node_id: StringName, current_id: StringName,
		team_level: int, axis_points: Dictionary) -> bool:
	var cur := EvolutionSystem.node_of(current_id)
	if not cur.get("exits", []).has(String(node_id)):
		return false
	var nd := EvolutionSystem.node_of(node_id)
	return team_level >= EvolutionSystem.min_level_of(nd) \
		and EvolutionSystem.gates_passed(nd, axis_points)



func _label(value: String, height: float, color: Color) -> TerminalText:
	var label := TerminalText.new()
	label.text = value
	label.font_color = color
	label.custom_minimum_size.y = height
	label.font_face = TerminalText.FontFace.THEME
	if height == 18.0:
		label.size_rule = TerminalText.SizeRule.ONE_U_FIXED_15
	else:
		label.font_face = TerminalText.FontFace.CHAKRA_PETCH_MEDIUM
		label.layout_text = "MMMMMMMMMMMMMMMMMMMM"
	return label


func _section_header(value: String) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = 18.0
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(space)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(_accent, 0.65)
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var label := _label(value, 18.0, _accent)
	label.font_face = TerminalText.FontFace.SILKSCREEN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(label)
	add_child(panel)


## 长说明仅在内容重建时分成固定 1u 行；字号、浮窗宽度与主界面边界不随文案变化。
func _paragraph(value: String, color: Color = Color.TRANSPARENT) -> void:
	if color == Color.TRANSPARENT:
		color = Color(_accent, 0.65)
	var font := get_theme_default_font()
	for paragraph in value.split("\n"):
		var line := ""
		for character in paragraph:
			if TerminalText.cached_string_width(font, line + character, 15) > CONTENT_W:
				var split := line.rfind(" ")
				if split > line.length() / 2:
					add_child(_label(line.substr(0, split), 18.0, color))
					line = line.substr(split + 1)
				else:
					add_child(_label(line, 18.0, color))
					line = ""
			line += character
		if not line.is_empty():
			add_child(_label(line, 18.0, color))
