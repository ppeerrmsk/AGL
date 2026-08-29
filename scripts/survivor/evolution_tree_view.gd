class_name EvolutionTreeView
extends Control

## 机体进化树视图（参考皇牌空战机体树，自下而上生长）。
## 状态：当前机=醒目金框+光环"当前"｜爬线历史=金色路径｜可进化=亮绿（点击可选）｜
##       等级不够=灰+LV 门槛｜远处节点=暗灰（只看结构）。
## v9 视觉（spec evolution-attribute-gates §3.3）：路线 color code 左缘条（机种类→轴色段）+
## 门槛 pip 徽记（每 1 点一枚，实心=已满足/空心=缺口；合计门自由余量=分瓣色）+ 顶部三轴图例。
## 颜色一律复用 SurvivorData.AXIS_COLORS，不引入新色。
## 纯数据驱动：树 JSON 加节点/档位后无需改本文件。静态绘制，仅 setup/点击重绘（性能守则 1）。

signal node_selected(node_id: StringName)

const ROW_H := 116.0                   ## 为最密档位预留足够的层间正交线槽
const NODE_W := 96.0
const NODE_H := 56.0
const COL_GAP := 12.0
const HEADER_H := 26.0             ## 顶部三轴图例行高度
const STRIPE_W := 4.0              ## 路线条宽度（卡左缘）
const PIP_R := 3.0                 ## 门槛 pip 半径
const PIP_GAP := 9.0               ## pip 圆心间距
const EDGE_LANE_MARGIN := 6.0      ## 层间直角线槽上下留白
const CURRENT_FRAME_GAP := 6.0     ## 当前机体外框与节点卡的间距
const TREE_SIDE_PAD := 12.0        ## 防止最外侧当前机双层框被 ScrollContainer 裁掉
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

var _all_nodes: Array = []         ## 数据源中的全部节点 Dictionary
var _nodes: Array = []             ## 当前历史链与可达后继节点 Dictionary
var _rects: Dictionary = {}        ## id(StringName) → Rect2
var _current: StringName = &""
var _history: Array = []           ## 爬线历史节点 id（顺序）
var _exit_lv: Dictionary = {}      ## 当前节点出口 id → 解锁等级
var _team_level: int = 1
var _axis_points: Dictionary = {}  ## 三轴属性点（属性门槛检查，spec evolution-attribute-gates）
var _selected: StringName = &""
var _edge_routes: Dictionary = {}  ## "from>to" → 正交折线路径（_layout 时一次性缓存）

func setup(all_nodes: Array, current: StringName, history: Array, team_level: int, axis_points: Dictionary = {}) -> void:
	_all_nodes = all_nodes
	_nodes = _relevant_nodes(all_nodes, current, history)
	_current = current
	_history = history.duplicate()
	_team_level = team_level
	_axis_points = axis_points
	_selected = &""
	_refresh_current_exits()
	_layout()
	queue_redraw()


## 只展示本局已经走过的路径，以及当前机体仍可能进入的后继。
## 可达但未拥有的后继仍按战争迷雾显示“？？？”；只有结构上永久不可达的旁支不进入布局。
static func _relevant_nodes(all_nodes: Array, current: StringName, history: Array) -> Array:
	var by_id: Dictionary = {}
	for nd in all_nodes:
		var nid := StringName(nd.get("id", ""))
		if nid != &"":
			by_id[nid] = nd
	if current == &"" or not by_id.has(current):
		return all_nodes.duplicate()

	var visible: Dictionary = {}
	for history_id in history:
		var hid := StringName(str(history_id))
		if by_id.has(hid):
			visible[hid] = true
	var traversed: Dictionary = {}
	var pending: Array[StringName] = [current]
	while not pending.is_empty():
		var nid: StringName = pending.pop_back()
		if traversed.has(nid):
			continue
		traversed[nid] = true
		visible[nid] = true
		for exit_id in (by_id[nid] as Dictionary).get("exits", []):
			var eid := StringName(str(exit_id))
			if by_id.has(eid) and not traversed.has(eid):
				pending.append(eid)

	var result: Array = []
	for nd in all_nodes:
		if visible.has(StringName(nd.get("id", ""))):
			result.append(nd)
	return result

## 进化成功后把“当前机体”标记迁到新节点；候选白框清掉，当前金框成为唯一位置指示。
func set_current(current: StringName, history: Array = []) -> void:
	if current == &"" or EvolutionSystem.node_of(current).is_empty():
		return
	_current = current
	if not history.is_empty():
		_history = history.duplicate()
	_selected = &""
	_nodes = _relevant_nodes(_all_nodes, _current, _history)
	_refresh_current_exits()
	_layout()
	queue_redraw()

func _refresh_current_exits() -> void:
	_exit_lv.clear()
	var cur_nd := EvolutionSystem.node_of(_current)
	for eid in cur_nd.get("exits", []):
		var nd := EvolutionSystem.node_of(StringName(eid))
		if not nd.is_empty():
			_exit_lv[StringName(eid)] = EvolutionSystem.min_level_of(nd)

## 布局：档位一行（T1 在底、向上生长）；行内按种类序均匀铺开；顶部留图例行
func _layout() -> void:
	_rects.clear()
	_edge_routes.clear()
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
	var inner_w := max_count * (NODE_W + COL_GAP) + COL_GAP
	var w := inner_w + TREE_SIDE_PAD * 2.0
	var h := tiers.size() * ROW_H + 16.0 + HEADER_H
	custom_minimum_size = Vector2(w, h)
	for ti in range(tiers.size()):
		var row: Array = by_tier[tiers[ti]]
		var y := h - float(ti + 1) * ROW_H + (ROW_H - NODE_H) * 0.5  # T1 在底
		var slot_w := inner_w / float(row.size())
		for ci in range(row.size()):
			var x := TREE_SIDE_PAD + slot_w * (float(ci) + 0.5) - NODE_W * 0.5
			_rects[StringName(row[ci].get("id", ""))] = Rect2(x, y, NODE_W, NODE_H)
	_build_edge_routes(by_tier)

## 每个来源节点占用层间的一条水平线槽；同一来源的分支共用槽位，形成技能树式总线。
## 跨档边也先进入来源档上方的槽位，再垂直抵达目标，避免自由斜线互相穿插。
func _build_edge_routes(by_tier: Dictionary) -> void:
	for tier in by_tier:
		var sources: Array[StringName] = []
		for nd in by_tier[tier]:
			var exits: Array = nd.get("exits", [])
			if not exits.is_empty():
				sources.append(StringName(nd.get("id", "")))
		sources.sort_custom(func(a: StringName, b: StringName) -> bool:
			return (_rects[a] as Rect2).get_center().x < (_rects[b] as Rect2).get_center().x)
		var source_count := sources.size()
		for source_i in range(source_count):
			var from_id := sources[source_i]
			var fr: Rect2 = _rects[from_id]
			var lane_t := (float(source_i) + 0.5) / float(source_count)
			var upper_gap_y := fr.position.y - (ROW_H - NODE_H)
			var upper_lane_y := lerpf(upper_gap_y + EDGE_LANE_MARGIN,
				fr.position.y - EDGE_LANE_MARGIN, lane_t)
			var lower_lane_y := lerpf(fr.end.y + EDGE_LANE_MARGIN,
				fr.end.y + (ROW_H - NODE_H) - EDGE_LANE_MARGIN, lane_t)
			for eid in EvolutionSystem.node_of(from_id).get("exits", []):
				var to_id := StringName(eid)
				if not _rects.has(to_id):
					continue
				var tr_: Rect2 = _rects[to_id]
				var a: Vector2
				var b: Vector2
				var lane_y: float
				if tr_.get_center().y <= fr.get_center().y:  # 正常上行；同档边从卡片上方绕行
					a = Vector2(fr.get_center().x, fr.position.y)
					b = Vector2(tr_.get_center().x,
						tr_.position.y if is_equal_approx(tr_.position.y, fr.position.y) else tr_.end.y)
					lane_y = upper_lane_y
				else:  # 数据容错：若将来出现向下边，镜像走来源档下方线槽
					a = Vector2(fr.get_center().x, fr.end.y)
					b = Vector2(tr_.get_center().x, tr_.position.y)
					lane_y = lower_lane_y
				_edge_routes[_edge_key(from_id, to_id)] = _orthogonal_path(a, b, lane_y)

static func _orthogonal_path(a: Vector2, b: Vector2, lane_y: float) -> PackedVector2Array:
	var route := PackedVector2Array()
	for p in [a, Vector2(a.x, lane_y), Vector2(b.x, lane_y), b]:
		if route.is_empty() or not route[-1].is_equal_approx(p):
			route.append(p)
	return route

static func _edge_key(from_id: StringName, to_id: StringName) -> String:
	return "%s>%s" % [from_id, to_id]

func _draw() -> void:
	var font := get_theme_default_font()
	_draw_legend(font)
	# ── 边（先画，压在节点下）── 四类线各批量提交一次，点击重绘也不逐段 draw_line
	var far_segments: Array[Vector2] = []
	var locked_segments: Array[Vector2] = []
	var available_segments: Array[Vector2] = []
	var history_segments: Array[Vector2] = []
	for nd in _nodes:
		var from_id := StringName(nd.get("id", ""))
		if not _rects.has(from_id):
			continue
		for eid in nd.get("exits", []):
			var to_id := StringName(eid)
			var key := _edge_key(from_id, to_id)
			if not _edge_routes.has(key):
				continue
			var bucket: Array[Vector2]
			if _edge_in_history(from_id, to_id):
				bucket = history_segments
			elif from_id == _current and _exit_lv.has(to_id):
				if _team_level >= int(_exit_lv[to_id]) and _gate_gap_text(to_id) == "":
					bucket = available_segments
				else:
					bucket = locked_segments
			else:
				bucket = far_segments
			_append_route_segments(bucket, _edge_routes[key])
	_draw_edge_batch(far_segments, Color(0.3, 0.35, 0.3, 0.18), 1.5)
	_draw_edge_batch(locked_segments, Color(0.55, 0.6, 0.55, 0.5), 1.5)
	_draw_edge_batch(available_segments, Color(0.4, 1.0, 0.4, 0.8), 2.0)
	_draw_edge_batch(history_segments, Color(1.0, 0.8, 0.3, 0.9), 2.5)
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
		if nid == _current:
			draw_rect(r.grow(CURRENT_FRAME_GAP), Color(ThemeColors.TEXT_ACCENT, 0.12))
		draw_rect(r, bg)
		draw_rect(r, border, false, 3.0 if nid == _current else (2.0 if border == ThemeColors.HP_OK else 1.0))
		if nid == _current:
			draw_rect(r.grow(CURRENT_FRAME_GAP), ThemeColors.TEXT_ACCENT, false, 3.0)
			draw_rect(r.grow(CURRENT_FRAME_GAP + 4.0),
				Color(ThemeColors.TEXT_ACCENT, 0.35), false, 1.0)                     # 双层外框：树再大也能定位自己
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

func _append_route_segments(bucket: Array[Vector2], route: PackedVector2Array) -> void:
	for i in range(route.size() - 1):
		bucket.append(route[i])
		bucket.append(route[i + 1])

func _draw_edge_batch(segments: Array[Vector2], color: Color, width: float) -> void:
	if not segments.is_empty():
		draw_multiline(PackedVector2Array(segments), color, width, true)

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
## 具体轴门 = 轴色纯色 pip；或门（any）= 一枚分瓣 pip。
## 填充按当前 _axis_points 实时判定。
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
	var label: String = tr(str(SurvivorData.AXIS_I18N_KEY.get(StringName(String(m["key"])), "")))
	var extra: String = ("+%d" % (missing.size() - 1)) if missing.size() > 1 else ""
	return "%s %d/%d%s" % [label, int(m["have"]), int(m["need"]), extra]
