extends RefCounted

## 无头验收：进化结算站详情卡（spec aircraft-evolution-tree §5，用户反馈 2026-07-20）
##
## 覆盖：① 全树每个节点都能算出详情数据（档案可解析 / 属性表齐全）
##       ② 属性对比语义（越小越好的锁定时间不能被算成"变差"）
##       ③ 需求行 = 等级门 + 全部 gates（含已达标项，不只缺口）
##       ④ 可进化判定 = 直接出口 且 LV 达标 且 属性门全过
##
## 运行：godot --headless --path . -- --bench=evo_detail（或 --bench=all）

const D := preload("res://scripts/survivor/evolution_detail_panel.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 进化详情卡验收（属性表 / 对比 / 需求行 / 可进化判定） ════════")
	_test_stats_for_all_nodes()
	_test_delta_direction()
	_test_requirement_rows()
	_test_can_evolve()
	_test_panel_never_drifts_offscreen()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 全树属性表 ──
func _test_stats_for_all_nodes() -> void:
	print("── A. 每个节点的档案都能算出完整属性表 ──")
	var bad: Array[String] = []
	for nd in EvolutionSystem.all_nodes():
		var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
		var s: Dictionary = D._effective_stats(prof)
		if s.is_empty():
			bad.append("%s 无属性" % nd.get("id", "?"))
			continue
		for row in D.STAT_ROWS:
			if not s.has(row["id"]):
				bad.append("%s 缺 %s" % [nd.get("id", "?"), row["id"]])
		# 速度/HP 是分母，出现 0 会让对比栏除零
		if float(s["speed"]) <= 0.0 or float(s["hp"]) <= 0.0:
			bad.append("%s 速度/HP 非正" % nd.get("id", "?"))
	_check("全 %d 节点属性表齐全" % EvolutionSystem.all_nodes().size(), bad.is_empty(),
		", ".join(bad.slice(0, 5)))


# ── B. 对比方向 ──
func _test_delta_direction() -> void:
	print("── B. higher_better 语义：锁定时间必须标成 false（越短越好）──")
	for row in D.STAT_ROWS:
		if String(row["id"]) == "lock":
			_check("lock.higher_better == false", not bool(row["higher_better"]), "被标成越大越好")
		elif String(row["id"]) in ["hp", "speed", "g", "missile"]:
			_check("%s.higher_better == true" % row["id"], bool(row["higher_better"]), "方向反了")


# ── C. 需求行 ──
func _test_requirement_rows() -> void:
	print("── C. 需求行覆盖全部 gates（含已达标项）──")
	var panel = D.new()
	var checked := 0
	for nd in EvolutionSystem.all_nodes():
		var gates: Dictionary = EvolutionSystem.gates_of(nd)
		if gates.is_empty():
			continue
		checked += 1
		# 给满点：所有门都应达标，但行数不能因此缩水
		var full := {&"gladiator": 10, &"knight": 10, &"schemer": 10}
		var rows: Array = panel._gate_rows(nd, full)
		if rows.size() != gates.size():
			_check("%s 需求行数 == gates 条数" % nd.get("id", "?"), false,
				"rows=%d gates=%d" % [rows.size(), gates.size()])
			panel.free()
			return
		for r in rows:
			if int(r["have"]) < int(r["need"]):
				_check("%s 满点下所有门达标" % nd.get("id", "?"), false, String(r["label"]))
				panel.free()
				return
	_check("带 gates 的 %d 个节点：行数守恒 + 满点全过" % checked, checked > 0,
		"没有节点带 gates（树数据异常？）")
	panel.free()


# ── D. 可进化判定 ──
func _test_can_evolve() -> void:
	print("── D. 可进化 = 直接出口 且 LV 达标 且 属性门全过 ──")
	var start := &"f15"
	var cur := EvolutionSystem.node_of(start)
	if cur.is_empty():
		_check("起手节点 f15 存在", false, "树里找不到")
		return
	var exits: Array = cur.get("exits", [])
	if exits.is_empty():
		_check("f15 有出口", false, "")
		return
	var first := StringName(exits[0])
	var need_lv := EvolutionSystem.min_level_of(EvolutionSystem.node_of(first))
	var full := {&"gladiator": 10, &"knight": 10, &"schemer": 10}
	_check("LV 不足 → 不可进化", not D._can_evolve(first, start, need_lv - 1, full), "")
	_check("LV + 属性齐 → 可进化", D._can_evolve(first, start, need_lv, full), "")
	_check("零属性点 → 被属性门挡住或本就无门",
		D._can_evolve(first, start, need_lv, {}) ==
			EvolutionSystem.gates_of(EvolutionSystem.node_of(first)).is_empty(), "")
	# 非直接出口（自己不是自己的出口）
	_check("当前机自身不算可进化目标", not D._can_evolve(start, start, 99, full), "")


# ── E. 面板不漂出屏幕（用户 2026-07-20 报的 bug 的回归锁）──
## 树宽随档位节点数增长（T2 已 15 格）。旧实现按 size 手动居中，超视口即给负坐标 → 界面整体上移。
## 本例连开两次（模拟"进化到第二架后再开"），断言面板始终贴在视口内且尺寸不失控。
func _test_panel_never_drifts_offscreen() -> void:
	print("── E. 结算面板铺满视口，反复打开不漂移 ──")
	# 离树构建：bench 跑在 _ready 里，root 正忙，add_child 会被拒；锚点/结构断言不需要进树。
	var ui := EvolutionUI.new()
	ui._ready()
	var nodes: Array = EvolutionSystem.all_nodes()
	var first: Dictionary = EvolutionSystem.node_of(&"f15")
	var second: Dictionary = first
	for eid in first.get("exits", []):
		second = EvolutionSystem.node_of(StringName(eid))
		break
	for pass_i in [0, 1]:
		var cur: Dictionary = first if pass_i == 0 else second
		# 顺带冒烟：show_offer 本身不得抛错（三栏构建 / 详情卡默认摊开当前机）
		ui.show_offer(cur, EvolutionSystem.exits_of(StringName(cur.get("id", ""))), 26, [],
			[], {&"gladiator": 4, &"knight": 3, &"schemer": 2})
		var panel: PanelContainer = ui.get_child(0)
		var label := "第 %d 次打开（%s）" % [pass_i + 1, cur.get("id", "?")]
		# 锚点式布局是"不漂移"的**结构性**保证：锚死四边 + 固定留白，与内容尺寸无关。
		# 断言锚点而非等一帧算出的坐标 —— 后者在无头下依赖布局时序，锁不住真正的不变量。
		_check("%s：面板锚死视口四边" % label,
			is_equal_approx(panel.anchor_left, 0.0) and is_equal_approx(panel.anchor_top, 0.0)
			and is_equal_approx(panel.anchor_right, 1.0) and is_equal_approx(panel.anchor_bottom, 1.0),
			"anchors=%.1f/%.1f/%.1f/%.1f" % [panel.anchor_left, panel.anchor_top,
				panel.anchor_right, panel.anchor_bottom])
		_check("%s：四边留白对称且为正" % label,
			panel.offset_left > 0.0 and panel.offset_top > 0.0
			and is_equal_approx(panel.offset_right, -panel.offset_left)
			and is_equal_approx(panel.offset_bottom, -panel.offset_top),
			"offsets=%.0f/%.0f/%.0f/%.0f" % [panel.offset_left, panel.offset_top,
				panel.offset_right, panel.offset_bottom])
		_check("%s：进化树套在 ScrollContainer 里" % label,
			_find_tree_scroll(panel) != null, "树没有滚动容器包裹，超宽会顶飞面板")
	ui.free()
	print("  （树节点 %d，最宽档位由 ScrollContainer 吸收）" % nodes.size())


## 递归找 EvolutionTreeView 的 ScrollContainer 祖先
func _find_tree_scroll(n: Node) -> ScrollContainer:
	if n is EvolutionTreeView:
		var p := n.get_parent()
		return p as ScrollContainer
	for c in n.get_children():
		var found := _find_tree_scroll(c)
		if found != null:
			return found
	return null


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])
