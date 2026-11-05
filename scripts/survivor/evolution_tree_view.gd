class_name EvolutionTreeView
extends Control

## 静态终端路线图：当前机反色、可进化出口强调、远端低对比。
## 文字与框线分层；悬停只发出数据事件，不执行选择或结算。
signal node_selected(node_id: StringName)
signal node_hovered(node_id: StringName, anchor: Rect2)

const ModelPreview := preload("res://scripts/survivor/aircraft_model_preview.gd")
const ROW_H := 216.0
const NODE_W := 200.0
const NODE_H := 162.0
const MODEL_H := 90.0
const COL_GAP := 40.0
const HEADER_H := 18.0
const EDGE_LANE_MARGIN := 18.0
const TREE_SIDE_PAD := 40.0
const CAT_ORDER := {"air": 0, "ew": 1, "attack": 2, "range": 3, "omni": 4,
	"bridge": 5, "stealth": 6, "carrier": 7, "legend": 8}
var _accent: Color = HudPreferences.hud_color()
var _hovered: StringName = &""
var _labels: Dictionary = {}
var _models: Dictionary = {}

func _init() -> void:
	mouse_exited.connect(clear_hover)

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
	_hovered = &""
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

## 进化成功后把“当前机体”标记迁到新节点，并清除旧候选与悬停状态。
func set_current(current: StringName, history: Array = []) -> void:
	if current == &"" or EvolutionSystem.node_of(current).is_empty():
		return
	_current = current
	if not history.is_empty():
		_history = history.duplicate()
	clear_hover()
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
		# 每层独立紧凑居中，远期宽层不能把眼前的几个出口撑到屏幕外。
		var slot_w := NODE_W + COL_GAP
		for ci in range(row.size()):
			var x := w * 0.5 + slot_w * (float(ci) - float(row.size() - 1) * 0.5) - NODE_W * 0.5
			_rects[StringName(row[ci].get("id", ""))] = Rect2(x, y, NODE_W, NODE_H)
	_build_edge_routes(by_tier)
	_build_node_labels()

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
	var far_segments: Array[Vector2] = []
	var locked_segments: Array[Vector2] = []
	var available_segments: Array[Vector2] = []
	var history_segments: Array[Vector2] = []
	for nd in _nodes:
		var from_id := StringName(nd.get("id", ""))
		for eid in nd.get("exits", []):
			var to_id := StringName(eid)
			var key := _edge_key(from_id, to_id)
			if not _edge_routes.has(key):
				continue
			var bucket: Array[Vector2]
			if _edge_in_history(from_id, to_id):
				bucket = history_segments
			elif from_id == _current:
				bucket = available_segments if can_evolve(to_id) else locked_segments
			else:
				bucket = far_segments
			_append_route_segments(bucket, _edge_routes[key])
	_draw_edge_batch(far_segments, Color(_accent, 0.10), 1.0)
	_draw_edge_batch(locked_segments, Color(_accent, 0.35), 1.0)
	_draw_edge_batch(available_segments, _accent, 1.0)
	_draw_edge_batch(history_segments, Color(_accent, 0.45), 1.0)
	for nd in _nodes:
		var nid := StringName(nd.get("id", ""))
		var rect: Rect2 = _rects[nid]
		var important := nid == _current or can_evolve(nid)
		var border := _accent if important or nid == _hovered else Color(_accent, 0.35)
		if not _is_revealed(nid):
			border = Color(_accent, 0.16)
		var inverted := nid == _current or nid == _selected
		draw_rect(rect, _accent if inverted else Color(0, 0, 0, 0.70))
		draw_rect(rect.grow(-0.5), border, false, 1.0)


func _build_node_labels() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_labels.clear()
	_models.clear()
	for nd in _nodes:
		var nid := StringName(nd.get("id", ""))
		var rect: Rect2 = _rects[nid]
		# 未知节点不解析机型档案，避免外形先于发现状态泄露。
		if _is_revealed(nid):
			var preview := ModelPreview.new()
			preview.position = rect.position + Vector2(18, 9)
			preview.size = Vector2(NODE_W - 36, MODEL_H - 18)
			preview.show_profile(AircraftDB.get_profile(StringName(nd.get("profile", ""))))
			add_child(preview)
			_models[nid] = preview
		var labels: Array[TerminalText] = []
		for line in range(3):
			var label := TerminalText.new()
			label.position = rect.position + Vector2(0, MODEL_H + (36 if line == 1 else (54 if line == 2 else 0)))
			if not _is_revealed(nid) and line == 0:
				label.position.y = rect.position.y + (NODE_H - 36.0) * 0.5
			label.size = Vector2(NODE_W, 36 if line == 0 else 18)
			label.font_face = TerminalText.FontFace.CHAKRA_PETCH_MEDIUM if line == 0 else TerminalText.FontFace.THEME
			if line == 0:
				label.layout_text = "MMMMMMMMMMMM"
			else:
				label.size_rule = TerminalText.SizeRule.ONE_U_FIXED_15
			add_child(label)
			labels.append(label)
		_labels[nid] = labels
	_update_node_labels()


func _update_node_labels() -> void:
	for nd in _nodes:
		var nid := StringName(nd.get("id", ""))
		var labels: Array = _labels[nid]
		var revealed := _is_revealed(nid)
		var color := _accent if nid == _current or can_evolve(nid) else Color(_accent, 0.65)
		if nid == _selected or nid == _current:
			color = Color.BLACK
		if _models.has(nid):
			(_models[nid] as Control).modulate = color
		labels[0].text = tr(String(nd.get("name_key", ""))) if revealed else tr("EVOLUTION_TREE_UNKNOWN")
		labels[1].text = tr(EvolutionSystem.category_key_of(nd)) if revealed else ""
		labels[2].text = _status_text(nid) if revealed else ""
		for label: TerminalText in labels:
			label.font_color = color if revealed else Color(_accent, 0.3)


func _status_text(nid: StringName) -> String:
	if nid == _current:
		return tr("EVOLUTION_DETAIL_CURRENT")
	if nid == _selected:
		return tr("EVO_SELECTED")
	if can_evolve(nid):
		return tr("EVOLUTION_DETAIL_TARGET")
	if _exit_lv.has(nid):
		if _team_level < int(_exit_lv[nid]):
			return tr("EVOLUTION_LOCKED_FMT") % int(_exit_lv[nid])
		return _gate_gap_text(nid)
	return tr("EVO_HISTORY") if _history.has(nid) or _history.has(String(nid)) else tr("EVO_LATER")


func select_node(nid: StringName) -> void:
	_selected = nid if can_evolve(nid) else &""
	_update_node_labels()
	queue_redraw()


func clear_hover() -> void:
	if _hovered == &"":
		return
	_hovered = &""
	node_hovered.emit(&"", Rect2())
	queue_redraw()


func _append_route_segments(bucket: Array[Vector2], route: PackedVector2Array) -> void:
	for i in range(route.size() - 1):
		bucket.append(route[i])
		bucket.append(route[i + 1])

func _draw_edge_batch(segments: Array[Vector2], color: Color, width: float) -> void:
	if not segments.is_empty():
		draw_multiline(PackedVector2Array(segments), color, width, true)

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
	if event is InputEventMouseMotion:
		var hit: StringName = &""
		for nid in _rects:
			if (_rects[nid] as Rect2).has_point(event.position) and _is_revealed(nid):
				hit = nid
				break
		if hit != _hovered:
			_hovered = hit
			var anchor := Rect2()
			if hit != &"":
				anchor = Rect2(global_position + (_rects[hit] as Rect2).position, (_rects[hit] as Rect2).size)
			node_hovered.emit(hit, anchor)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for nid in _rects:
			if (_rects[nid] as Rect2).has_point(event.position) and _is_revealed(nid):
				if can_evolve(nid):
					select_node(nid)
				node_selected.emit(nid)
				accept_event()
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
