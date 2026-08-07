class_name EvolutionDetailPanel
extends VBoxContainer

## 进化树机体详情卡（用户反馈 2026-07-20：结算站要能看清"我现在是什么机 / 那架好在哪 / 差什么才能换"）
##
## 三段式，纯数据驱动（树 JSON + PlayableAircraft 档案，加新机型无需改本文件）：
##   ① 抬头   —— 机型名 + 徽标（当前机 / 进化目标 / 未解锁）+ 种类·档位 + 武器清单 + 标签 + 描述
##   ② 机体特性 —— 关键属性表；非当前机时同时给出**相对当前机的增减**（↑绿 / ↓红 / 持平灰）
##   ③ 进化需求 —— 等级门 + 三轴属性门，逐条 have/need + ✓/✗（spec evolution-attribute-gates §3.3）
##
## 用法：var d := EvolutionDetailPanel.new(); d.show_node(nid, cur_id, team_level, axis_points)
## 性能：只在 show_node() 时重建子节点，无 _process / 无每帧重绘（性能守则 1）。

const CONTENT_W := 420.0

## 属性行定义：id 用于取值，key = i18n 标签，fmt = 数值格式，higher_better = 增大是否为优
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

const COL_UP := Color(0.45, 0.95, 0.5)
const COL_DOWN := Color(0.95, 0.45, 0.4)
const COL_FLAT := Color(0.5, 0.55, 0.5, 0.7)

## 进化种类 → 主题色（与 EvolutionUI.EVO_CAT_COLORS 同源语义）
const CAT_COLORS := {
	"air": ThemeColors.CATEGORY_MOBILITY,
	"ew": ThemeColors.CATEGORY_SYSTEM,
	"range": ThemeColors.CATEGORY_DEFENSE,
	"attack": ThemeColors.CATEGORY_WEAPON,
	"omni": ThemeColors.TEXT_ACCENT,
}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(CONTENT_W, 0)


## 渲染某个节点的详情。current_id = 玩家当前机（用于徽标 + 属性对比基准）。
func show_node(node_id: StringName, current_id: StringName, team_level: int, axis_points: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	var nd := EvolutionSystem.node_of(node_id)
	if nd.is_empty():
		return
	var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
	var is_current: bool = (node_id == current_id)
	var cur_nd := EvolutionSystem.node_of(current_id)
	var cur_prof := AircraftDB.get_profile(StringName(cur_nd.get("profile", ""))) if not cur_nd.is_empty() else null

	_build_header(nd, prof, is_current, node_id, current_id, team_level, axis_points)
	_build_stats(prof, cur_prof if not is_current else null)
	if not is_current:
		_build_requirements(nd, team_level, axis_points)


# ── ① 抬头 ──────────────────────────────────────────────
func _build_header(nd: Dictionary, prof: PlayableAircraft, is_current: bool,
		node_id: StringName, current_id: StringName, team_level: int, axis_points: Dictionary) -> void:
	var cat: String = String(nd.get("category", ""))
	var accent: Color = CAT_COLORS.get(cat, ThemeColors.TEXT_PRIMARY)

	var badge_text: String
	var badge_col: Color
	if is_current:
		badge_text = tr("EVOLUTION_DETAIL_CURRENT")
		badge_col = ThemeColors.TEXT_ACCENT
	elif _can_evolve(node_id, current_id, team_level, axis_points):
		badge_text = tr("EVOLUTION_DETAIL_TARGET")
		badge_col = ThemeColors.HP_OK
	else:
		badge_text = tr("EVOLUTION_DETAIL_LOCKED")
		badge_col = ThemeColors.TEXT_LOCKED

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	head.add_child(_label(tr(String(nd.get("name_key", ""))), 17, accent))
	head.add_child(_label("[%s]" % badge_text, 11, badge_col))

	# 种类 · 档位 · 解锁等级
	add_child(_label("%s · T%d · LV %d" % [
		tr(EvolutionSystem.category_key_of(nd)),
		int(nd.get("tier", 0)),
		EvolutionSystem.min_level_of(nd),
	], 12, ThemeColors.TEXT_MUTED))

	if prof == null:
		return

	var wpn := AircraftDB.weapons_summary(prof)
	if wpn != "":
		add_child(_label("%s：%s" % [tr("EVOLUTION_DETAIL_WEAPONS"), wpn], 12,
			ThemeColors.CATEGORY_WEAPON, true))
	if prof.card_tags.size() > 0:
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 6)
		add_child(tags)
		for t in prof.card_tags:
			tags.add_child(_label(tr("SLOT_TAG_WRAP_FMT") % tr(t), 10, ThemeColors.TEXT_TAG_UNLOCKED))
	if prof.card_desc != "":
		add_child(_label(tr(prof.card_desc), 12, ThemeColors.TEXT_DESC_UNLOCKED, true))


# ── ② 机体特性（含相对当前机的增减）──────────────────────
func _build_stats(prof: PlayableAircraft, base_prof: PlayableAircraft) -> void:
	if prof == null or prof.base_params == null:
		return
	var vals := _effective_stats(prof)
	var base_vals: Dictionary = _effective_stats(base_prof) if base_prof != null else {}
	add_child(_section_header(tr("EVOLUTION_DETAIL_PERKS") if base_vals.is_empty()
		else tr("EVOLUTION_DETAIL_PERKS_VS")))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	add_child(grid)
	var any_delta := false
	for row in STAT_ROWS:
		var v: float = vals.get(row["id"], 0.0)
		grid.add_child(_label(tr(String(row["key"])), 11, ThemeColors.TEXT_MUTED))
		grid.add_child(_label(String(row["fmt"]) % v, 11, ThemeColors.TEXT_PRIMARY))
		if base_vals.is_empty():
			grid.add_child(_label("", 11, COL_FLAT))
			continue
		var bv: float = base_vals.get(row["id"], 0.0)
		var pct: float = 0.0 if absf(bv) < 0.0001 else (v - bv) / absf(bv) * 100.0
		if absf(pct) < 0.5:
			grid.add_child(_label("—", 11, COL_FLAT))
			continue
		any_delta = true
		# 越小越好的属性（锁定时间）：下降 = 提升，配色要翻过来
		var improved: bool = (pct > 0.0) == bool(row["higher_better"])
		grid.add_child(_label("%s%.0f%%" % ["+" if pct > 0.0 else "", pct], 11,
			COL_UP if improved else COL_DOWN))
	if not base_vals.is_empty() and not any_delta:
		add_child(_label(tr("EVOLUTION_DETAIL_SAME"), 11, COL_FLAT))


# ── ③ 进化需求（等级门 + 三轴属性门）────────────────────
func _build_requirements(nd: Dictionary, team_level: int, axis_points: Dictionary) -> void:
	add_child(_section_header(tr("EVOLUTION_DETAIL_REQ")))
	var all_ok := true
	var need_lv := EvolutionSystem.min_level_of(nd)
	all_ok = _add_req_row(tr("EVOLUTION_REQ_LEVEL"), team_level, need_lv) and all_ok
	for r in _gate_rows(nd, axis_points):
		all_ok = _add_req_row(String(r["label"]), int(r["have"]), int(r["need"])) and all_ok
	if all_ok:
		add_child(_label(tr("EVOLUTION_REQ_ALL_MET"), 11, ThemeColors.HP_OK))


## 单条需求行：`✓ 等级 13 / 13`；返回是否达标
func _add_req_row(label_text: String, have: int, need: int) -> bool:
	var ok: bool = have >= need
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	row.add_child(_label("✓" if ok else "✗", 12, ThemeColors.HP_OK if ok else COL_DOWN))
	row.add_child(_label(label_text, 12, ThemeColors.TEXT_MUTED))
	row.add_child(_label("%d / %d" % [have, need], 12,
		ThemeColors.HP_OK if ok else ThemeColors.TEXT_LOCKED))
	return ok


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


# ── 小工具 ──────────────────────────────────────────────
func _label(text_: String, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text_
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CONTENT_W, 0)
	return l


func _section_header(text_: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label(text_, 13, ThemeColors.TEXT_TITLE_GREEN))
	box.add_child(HSeparator.new())
	return box
