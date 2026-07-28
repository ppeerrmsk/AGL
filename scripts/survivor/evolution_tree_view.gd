class_name EvolutionTreeView
extends Control

## 机体进化树视图（参考皇牌空战机体树，自下而上生长）。
## 状态：当前机=金框+光环"当前"｜爬线历史=金色路径｜可进化=亮绿（点击可选）｜
##       等级不够=灰+LV 门槛｜远处节点=暗灰（只看结构）。
## v9 视觉（spec evolution-attribute-gates §3.3）：路线 color code 左缘条（机种类→轴色段）+
## 门槛 pip 徽记（每 1 点一枚，实心=已满足/空心=缺口；合计门自由余量=分瓣色）+ 顶部三轴图例。
## 颜色一律复用 SurvivorData.AXIS_COLORS，不引入新色。
## 纯数据驱动：树 JSON 加节点/档位后无需改本文件。静态绘制，仅 setup/点击重绘（性能守则 1）。

signal node_selected(node_id: StringName)

const ROW_H := 92.0
const NODE_W := 96.0
const NODE_H := 56.0
const COL_GAP := 12.0
const HEADER_H := 26.0             ## 顶部三轴图例行高度
const STRIPE_W := 4.0              ## 路线条宽度（卡左缘）
const PIP_R := 3.0                 ## 门槛 pip 半径
const PIP_GAP := 9.0               ## pip 圆心间距
const CAT_ORDER := { "air": 0, "ew": 1, "attack": 2, "range": 3, "omni": 4,
	"bridge": 5, "stealth": 6, "carrier": 7, "legend": 8 }
## 机种类 → 路线轴色段（spec §3.3：攻击=斗士/远程=骑士/电战=策士；
## 制空·桥接·母舰=斗+骑双段；隐身=骑+策；omni·传说=三色三段）
const CAT_AXES := {
	"attack": [&"gladiator"],
	"range": [&"knight"],
	"ew": [&"schemer"],
	"air": [&"gladiator", &"knight"],
	"bridge": [&"gladiator", &"knight"],
	"carrier": [&"gladiator", &"knight"],
	"stealth": [&"knight", &"schemer"],
	"omni": [&"gladiator", &"knight", &"schemer"],
	"legend": [&"gladiator", &"knight", &"schemer"],
}

var interactive: bool = true       ## 选定进化后由 UI 置 false（只看不点）

var _nodes: Array = []             ## 全部节点 Dictionary
var _rects: Dictionary = {}        ## id(StringName) → Rect2
var _current: StringName = &""
var _history: Array = []           ## 爬线历史节点 id（顺序）
var _exit_lv: Dictionary = {}      ## 当前节点出口 id → 解锁等级
var _team_level: int = 1
var _axis_points: Dictionary = {}  ## 三轴属性点（属性门槛检查，spec evolution-attribute-gates）
var _selected: StringName = &""

func setup(all_nodes: Array, current: StringName, history: Array, team_level: int, axis_points: Dictionary = {}) -> void:
	_nodes = all_nodes
	_current = current
	_history = history.duplicate()
	_team_level = team_level
	_axis_points = axis_points
	_selected = &""
	_exit_lv.clear()
	var cur_nd := EvolutionSystem.node_of(current)
	for eid in cur_nd.get("exits", []):
		var nd := EvolutionSystem.node_of(StringName(eid))
		if not nd.is_empty():
			_exit_lv[StringName(eid)] = EvolutionSystem.min_level_of(nd)
	_layout()
	queue_redraw()

## 布局：档位一行（T1 在底、向上生长）；行内按种类序均匀铺开；顶部留图例行
func _layout() -> void:
	_rects.clear()
	var tiers: Array = []
	var by_tier: Dictionary = {}
	for nd in _nodes:
		var t: int = int(nd.get("tier", 1))
		if not by_tier.has(t):
			by_tier[t] = []
			tiers.append(t)
		by_tier[t].append(nd)
	tiers.sort()
	var max_count := 1
	for t in tiers:
		by_tier[t].sort_custom(func(a, b) -> bool:
			var ca: int = CAT_ORDER.get(a.get("category", ""), 9)
			var cb: int = CAT_ORDER.get(b.get("category", ""), 9)
			return ca < cb if ca != cb else String(a.get("id", "")) < String(b.get("id", "")))
		max_count = maxi(max_count, by_tier[t].size())
	var w := max_count * (NODE_W + COL_GAP) + COL_GAP
	var h := tiers.size() * ROW_H + 16.0 + HEADER_H
	custom_minimum_size = Vector2(w, h)
	for ti in range(tiers.size()):
		var row: Array = by_tier[tiers[ti]]
		var y := h - float(ti + 1) * ROW_H + (ROW_H - NODE_H) * 0.5  # T1 在底
		var slot_w := w / float(row.size())
		for ci in range(row.size()):
			var x := slot_w * (float(ci) + 0.5) - NODE_W * 0.5
			_rects[StringName(row[ci].get("id", ""))] = Rect2(x, y, NODE_W, NODE_H)

func _draw() -> void:
	var font := get_theme_default_font()
	_draw_legend(font)
	# ── 边（先画，压在节点下）──
	for nd in _nodes:
		var from_id := StringName(nd.get("id", ""))
		if not _rects.has(from_id):
			continue
		var fr: Rect2 = _rects[from_id]
		for eid in nd.get("exits", []):
			var to_id := StringName(eid)
			if not _rects.has(to_id):
				continue
			var tr_: Rect2 = _rects[to_id]
			var a := Vector2(fr.position.x + fr.size.x * 0.5, fr.position.y)          # 起点顶边中
			var b := Vector2(tr_.position.x + tr_.size.x * 0.5, tr_.end.y)           # 终点底边中
			var col: Color
			var width := 1.5
			if _edge_in_history(from_id, to_id):
				col = Color(1.0, 0.8, 0.3, 0.9); width = 2.5                          # 爬过的线：金
			elif from_id == _current and _exit_lv.has(to_id):
				if _team_level >= int(_exit_lv[to_id]) and _gate_gap_text(to_id) == "":
					col = Color(0.4, 1.0, 0.4, 0.8); width = 2.0                      # 可进化：亮绿
				else:
					col = Color(0.55, 0.6, 0.55, 0.5)                                 # 等级/属性门槛不够：灰
			else:
				col = Color(0.3, 0.35, 0.3, 0.18)                                     # 远处：暗
			draw_line(a, b, col, width)
	# ── 节点 ──
	for nd in _nodes:
		var nid := StringName(nd.get("id", ""))
		if not _rects.has(nid):
			continue
		var r: Rect2 = _rects[nid]
		# ── 战争迷雾（用户 2026-07-03）：从没拥有过 + 不是当前出口 → 剪影 ？？？──
		# 揭示条件：当前机 / 本局爬线历史 / 当前机的直接出口（"可以被解锁的"）/ 跨局图鉴（拥有过）
		# 迷雾节点不画路线条/pip，保持神秘
		if not _is_revealed(nid):
			draw_rect(r, Color(0.02, 0.03, 0.02, 0.85))
			draw_rect(r, Color(0.2, 0.24, 0.2, 0.3), false, 1.0)
			draw_string(get_theme_default_font(), Vector2(r.position.x, r.position.y + 32.0),
				tr("EVOLUTION_TREE_UNKNOWN"), HORIZONTAL_ALIGNMENT_CENTER, NODE_W, 13,
				Color(0.35, 0.4, 0.35, 0.5))
			continue
		var name_txt: String = tr(String(nd.get("name_key", "")))
		var lv := EvolutionSystem.min_level_of(nd)
		var bg := Color(0.03, 0.05, 0.03, 0.9)
		var border := Color(0.25, 0.3, 0.25, 0.35)
		var txt_col := Color(0.45, 0.5, 0.45, 0.55)
		var sub := ""
		var sub_col := txt_col
		var near := false                                                             # 当前机/出口=近处，条与 pip 全亮
		if nid == _current:
			near = true
			bg = Color(0.10, 0.08, 0.02, 0.95)                                        # 底色提亮（金调）
			border = ThemeColors.TEXT_ACCENT
			txt_col = ThemeColors.TEXT_ACCENT
			sub = tr("EVOLUTION_TREE_CURRENT")
			sub_col = ThemeColors.TEXT_ACCENT
		elif _exit_lv.has(nid):
			near = true
			var gap := _gate_gap_text(nid)
			if _team_level >= int(_exit_lv[nid]) and gap == "":
				bg = Color(0.05, 0.11, 0.05, 0.95)
				border = ThemeColors.HP_OK                                            # 亮色=可进化
				txt_col = ThemeColors.TEXT_PRIMARY
				sub = "LV %d ✓" % lv
				sub_col = ThemeColors.HP_OK
			else:
				border = Color(0.5, 0.55, 0.5, 0.6)                                   # 灰=不能进化（LV/属性双门）
				txt_col = ThemeColors.TEXT_LOCKED
				# 等级先行显示；等级已够只差属性 → 显示轴缺口徽记（"斗士 1/2"，spec §3.3）
				sub = ("LV %d" % lv) if _team_level < int(_exit_lv[nid]) else gap
				sub_col = ThemeColors.TEXT_LOCKED
		elif _history.has(nid) or _history.has(String(nid)):
			border = Color(1.0, 0.8, 0.3, 0.5)                                        # 走过的机
			txt_col = Color(0.85, 0.75, 0.5, 0.7)
			sub = "LV %d" % lv
		else:
			sub = "LV %d" % lv
		draw_rect(r, bg)
		draw_rect(r, border, false, 3.0 if nid == _current else (2.0 if border == ThemeColors.HP_OK else 1.0))
		if nid == _current:
			draw_rect(r.grow(3.0), Color(ThemeColors.TEXT_ACCENT, 0.4), false, 1.5)   # 外圈光环：树再大也能定位自己
		if nid == _selected:
			draw_rect(r.grow(5.0), Color(1, 1, 1, 0.85), false, 1.5)
		# 路线条（color code）：左缘轴色段，机种类→轴色（spec §3.3）
		_draw_route_stripe(r, String(nd.get("category", "")), 0.95 if near else 0.45)
		draw_string(font, Vector2(r.position.x, r.position.y + 17.0), name_txt,
			HORIZONTAL_ALIGNMENT_CENTER, NODE_W, 12, txt_col)
		if sub != "":
			draw_string(font, Vector2(r.position.x, r.position.y + 31.0), sub,
				HORIZONTAL_ALIGNMENT_CENTER, NODE_W, 11, sub_col)
		# 门槛 pip 徽记：每 1 点一枚，实心=已满足/空心=缺口（spec §3.3）
		_draw_gate_pips(nd, r, 1.0 if near else 0.6)

## 顶部三轴图例：轴色点 + 轴名（复用 ATTR_* i18n key，无新 key）
func _draw_legend(font: Font) -> void:
	var x := 10.0
	var cy := HEADER_H * 0.5
	for ax in SurvivorData.AXES:
		var col: Color = SurvivorData.AXIS_COLORS.get(ax, Color.WHITE)
		draw_circle(Vector2(x, cy), 4.0, col)
		var axis_name := tr(str(SurvivorData.AXIS_I18N_KEY.get(ax, "")))
		draw_string(font, Vector2(x + 8.0, cy + 5.0), axis_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.9))
		x += 8.0 + font.get_string_size(axis_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0

## 路线条：卡左缘竖条，按 CAT_AXES 轴色均分段
func _draw_route_stripe(r: Rect2, cat: String, alpha: float) -> void:
	var axes: Array = CAT_AXES.get(cat, [])
	if axes.is_empty():
		return
	var seg_h := r.size.y / float(axes.size())
	for k in range(axes.size()):
		var col: Color = SurvivorData.AXIS_COLORS.get(axes[k], Color.WHITE)
		draw_rect(Rect2(r.position.x, r.position.y + seg_h * float(k), STRIPE_W, seg_h),
			Color(col, alpha))

## 门槛 pip 行：卡内下缘居中一排
func _draw_gate_pips(nd: Dictionary, r: Rect2, alpha: float) -> void:
	var slots := _pip_slots(EvolutionSystem.gates_of(nd))
	if slots.is_empty():
		return
	var total_w := float(slots.size() - 1) * PIP_GAP
	var cx := r.position.x + r.size.x * 0.5 - total_w * 0.5
	var cy := r.position.y + NODE_H - 11.0
	for s in slots:
		_draw_pip(Vector2(cx, cy), s["colors"], bool(s["filled"]), alpha)
		cx += PIP_GAP

## gates → pip 槽位列表 [{colors: Array[Color], filled: bool}]（spec §3.3）：
## 单轴门 = 轴色纯色 pip；合计门（sum_gk/sum_all）自由余量 = 双/三色分瓣 pip；
## 或门（any）= 一枚分瓣 pip。填充按当前 _axis_points 实时判定。
func _pip_slots(g: Dictionary) -> Array:
	var slots: Array = []
	if g.is_empty():
		return slots
	if g.has("any"):
		var alt: Dictionary = g["any"]
		var any_ok := false
		var cols: Array = []
		for ak in alt:
			cols.append(_axis_color(StringName(String(ak))))
			if int(_axis_points.get(StringName(String(ak)), 0)) >= int(alt[ak]):
				any_ok = true
		slots.append({"colors": cols, "filled": any_ok})
	var mins: Dictionary = {}
	for ax in SurvivorData.AXES:
		mins[ax] = int(g.get(String(ax), 0))
	# 各轴最低承诺：纯色 pip
	for ax in SurvivorData.AXES:
		var have: int = int(_axis_points.get(ax, 0))
		for i in range(int(mins[ax])):
			slots.append({"colors": [_axis_color(ax)], "filled": i < have})
	# 合计门自由余量：分瓣 pip（配比玩家自定，只查总投入）
	if g.has("sum_gk"):
		var committed: int = int(mins[SurvivorData.AXIS_GLADIATOR]) + int(mins[SurvivorData.AXIS_KNIGHT])
		var free: int = maxi(0, int(g["sum_gk"]) - committed)
		var have_sum: int = int(_axis_points.get(SurvivorData.AXIS_GLADIATOR, 0)) \
			+ int(_axis_points.get(SurvivorData.AXIS_KNIGHT, 0))
		var filled_free: int = clampi(have_sum - committed, 0, free)
		for i in range(free):
			slots.append({"colors": [_axis_color(SurvivorData.AXIS_GLADIATOR),
				_axis_color(SurvivorData.AXIS_KNIGHT)], "filled": i < filled_free})
	if g.has("sum_all"):
		var committed_all: int = 0
		var have_all: int = 0
		var cols_all: Array = []
		for ax in SurvivorData.AXES:
			committed_all += int(mins[ax])
			have_all += int(_axis_points.get(ax, 0))
			cols_all.append(_axis_color(ax))
		var free_all: int = maxi(0, int(g["sum_all"]) - committed_all)
		var filled_all: int = clampi(have_all - committed_all, 0, free_all)
		for i in range(free_all):
			slots.append({"colors": cols_all, "filled": i < filled_all})
	return slots

func _axis_color(ax: StringName) -> Color:
	return SurvivorData.AXIS_COLORS.get(ax, Color.WHITE)

## 单枚 pip：纯色 = 圆 / 分瓣 = 扇形楔（实心）或彩色弧段（空心描边）
func _draw_pip(c: Vector2, colors: Array, filled: bool, alpha: float) -> void:
	var n: int = colors.size()
	if filled:
		if n == 1:
			draw_circle(c, PIP_R, Color(colors[0], alpha))
			return
		for k in range(n):
			var a0 := -PI * 0.5 + TAU * float(k) / float(n)
			var a1 := -PI * 0.5 + TAU * float(k + 1) / float(n)
			var pts := PackedVector2Array([c])
			for s in range(9):
				var ang := lerpf(a0, a1, float(s) / 8.0)
				pts.append(c + Vector2(cos(ang), sin(ang)) * PIP_R)
			draw_colored_polygon(pts, Color(colors[k], alpha))
	else:
		for k in range(n):
			var a0 := -PI * 0.5 + TAU * float(k) / float(n)
			var a1 := -PI * 0.5 + TAU * float(k + 1) / float(n)
			draw_arc(c, PIP_R - 0.4, a0, a1, 8, Color(colors[k], alpha * 0.85), 1.2, true)

## 节点是否揭示（非剪影）：当前机 / 本局爬线历史 / 当前机直接出口（可被解锁=直接显示）/ 跨局图鉴
func _is_revealed(nid: StringName) -> bool:
	if nid == _current or _exit_lv.has(nid):
		return true
	if _history.has(nid) or _history.has(String(nid)):
		return true
	return AircraftCodex.is_discovered(nid)

## 爬线历史相邻对 = 走过的边
func _edge_in_history(a: StringName, b: StringName) -> bool:
	for i in range(_history.size() - 1):
		if StringName(str(_history[i])) == a and StringName(str(_history[i + 1])) == b:
			return true
	return false

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for nid in _rects:
			if (_rects[nid] as Rect2).has_point(event.position):
				# 已揭示的节点都可点开详情（含"差什么才能进化"）；能否真进化由 can_evolve 判定，
				# 确认按钮据此开关（用户 2026-07-20：灰色机体也要看得到需求）
				if _is_revealed(nid):
					_selected = nid
					queue_redraw()
					node_selected.emit(nid)
				return

## 该节点现在能不能进化：当前机直接出口 且 LV 达标 且 属性门全过（spec evolution-attribute-gates）
func can_evolve(nid: StringName) -> bool:
	return _exit_lv.has(nid) and _team_level >= int(_exit_lv[nid]) and _gate_gap_text(nid) == ""

## 属性门槛缺口短文本（缺口徽记）："斗士 1/2"（多条缺口取第一条 + "+N"）；无缺口返回 ""。
func _gate_gap_text(nid: StringName) -> String:
	var missing: Array = EvolutionSystem.gates_missing(EvolutionSystem.node_of(nid), _axis_points)
	if missing.is_empty():
		return ""
	var m: Dictionary = missing[0]
	var label: String
	if String(m["key"]) == "sum_gk":
		label = "%s+%s" % [tr("ATTR_GLADIATOR"), tr("ATTR_KNIGHT")]
	elif String(m["key"]) == "sum_all":
		label = tr("ATTR_SUM_ALL")
	else:
		label = tr(str(SurvivorData.AXIS_I18N_KEY.get(StringName(String(m["key"])), "")))
	var extra: String = ("+%d" % (missing.size() - 1)) if missing.size() > 1 else ""
	return "%s %d/%d%s" % [label, int(m["have"]), int(m["need"]), extra]
