class_name EvolutionTreeView
extends Control

## 机体进化树视图（参考皇牌空战机体树，自下而上生长）。
## 状态：当前机=金框"当前"｜爬线历史=金色路径｜可进化=亮绿（点击可选）｜
##       等级不够=灰+LV 门槛｜远处节点=暗灰（只看结构）。
## 纯数据驱动：树 JSON 加节点/档位后无需改本文件。

signal node_selected(node_id: StringName)

const ROW_H := 92.0
const NODE_W := 96.0
const NODE_H := 46.0
const COL_GAP := 12.0
const CAT_ORDER := { "air": 0, "ew": 1, "attack": 2, "range": 3, "omni": 4 }

var interactive: bool = true       ## 选定进化后由 UI 置 false（只看不点）

var _nodes: Array = []             ## 全部节点 Dictionary
var _rects: Dictionary = {}        ## id(StringName) → Rect2
var _current: StringName = &""
var _history: Array = []           ## 爬线历史节点 id（顺序）
var _exit_lv: Dictionary = {}      ## 当前节点出口 id → 解锁等级
var _team_level: int = 1
var _selected: StringName = &""

func setup(all_nodes: Array, current: StringName, history: Array, team_level: int) -> void:
	_nodes = all_nodes
	_current = current
	_history = history.duplicate()
	_team_level = team_level
	_selected = &""
	_exit_lv.clear()
	var cur_nd := EvolutionSystem.node_of(current)
	for eid in cur_nd.get("exits", []):
		var nd := EvolutionSystem.node_of(StringName(eid))
		if not nd.is_empty():
			_exit_lv[StringName(eid)] = EvolutionSystem.min_level_of(nd)
	_layout()
	queue_redraw()

## 布局：档位一行（T1 在底、向上生长）；行内按种类序均匀铺开
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
	var h := tiers.size() * ROW_H + 16.0
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
				if _team_level >= int(_exit_lv[to_id]):
					col = Color(0.4, 1.0, 0.4, 0.8); width = 2.0                      # 可进化：亮绿
				else:
					col = Color(0.55, 0.6, 0.55, 0.5)                                 # 等级不够：灰
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
		if not _is_revealed(nid):
			draw_rect(r, Color(0.02, 0.03, 0.02, 0.85))
			draw_rect(r, Color(0.2, 0.24, 0.2, 0.3), false, 1.0)
			draw_string(get_theme_default_font(), Vector2(r.position.x, r.position.y + 28.0),
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
		if nid == _current:
			border = ThemeColors.TEXT_ACCENT
			txt_col = ThemeColors.TEXT_ACCENT
			sub = tr("EVOLUTION_TREE_CURRENT")
			sub_col = ThemeColors.TEXT_ACCENT
		elif _exit_lv.has(nid):
			if _team_level >= int(_exit_lv[nid]):
				bg = Color(0.05, 0.11, 0.05, 0.95)
				border = ThemeColors.HP_OK                                            # 亮色=可进化
				txt_col = ThemeColors.TEXT_PRIMARY
				sub = "LV %d ✓" % lv
				sub_col = ThemeColors.HP_OK
			else:
				border = Color(0.5, 0.55, 0.5, 0.6)                                   # 灰=不能进化
				txt_col = ThemeColors.TEXT_LOCKED
				sub = "LV %d" % lv
				sub_col = ThemeColors.TEXT_LOCKED
		elif _history.has(nid) or _history.has(String(nid)):
			border = Color(1.0, 0.8, 0.3, 0.5)                                        # 走过的机
			txt_col = Color(0.85, 0.75, 0.5, 0.7)
			sub = "LV %d" % lv
		else:
			sub = "LV %d" % lv
		draw_rect(r, bg)
		draw_rect(r, border, false, 2.0 if (nid == _current or border == ThemeColors.HP_OK) else 1.0)
		if nid == _selected:
			draw_rect(r.grow(3.0), Color(1, 1, 1, 0.85), false, 1.5)
		draw_string(font, Vector2(r.position.x, r.position.y + 18.0), name_txt,
			HORIZONTAL_ALIGNMENT_CENTER, NODE_W, 12, txt_col)
		if sub != "":
			draw_string(font, Vector2(r.position.x, r.position.y + 36.0), sub,
				HORIZONTAL_ALIGNMENT_CENTER, NODE_W, 11, sub_col)

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
				# 只有"亮色可进化"节点可选
				if _exit_lv.has(nid) and _team_level >= int(_exit_lv[nid]):
					_selected = nid
					queue_redraw()
					node_selected.emit(nid)
				return
