extends RefCounted

const ModelPreview := preload("res://scripts/survivor/aircraft_model_preview.gd")

## 无头验收：进化结算站详情卡（spec aircraft-evolution-tree §5，用户反馈 2026-07-20）
##
## 覆盖：① 全树每个节点都能算出详情数据（档案可解析 / 属性表齐全）
##       ② 属性对比语义（越小越好的锁定时间不能被算成"变差"）
##       ③ 需求行 = 等级门 + 全部 gates（含已达标项，不只缺口）
##       ④ 可进化判定 = 直接出口 且 LV 达标 且 属性门全过
##       ⑤ 悬停不选择、未知机保密、提交锁定后的输入隔离
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
	_test_airfield_binary_decision()
	_test_tree_routes_and_current_marker()
	_test_tree_hides_unreachable_routes()
	_test_hover_does_not_select()
	_test_model_previews()
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
		# 顺带冒烟：show_offer 本身不得抛错，详情浮窗默认关闭。
		var cur_id := StringName(cur.get("id", ""))
		ui.show_offer(cur, EvolutionSystem.exits_of(cur_id), 26,
			SurvivorData.signature_upgrade_for_aircraft(cur_id), true, false,
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


func _test_airfield_binary_decision() -> void:
	print("── F. 机场二选一：按全部出口切换整备类型，与僚机互斥 ──")
	var ui := EvolutionUI.new()
	ui._ready()
	var current := EvolutionSystem.node_of(&"f15")
	var signature := SurvivorData.signature_upgrade_for_aircraft(&"f15")
	var points := {&"gladiator": 8, &"knight": 8, &"schemer": 8}
	ui.show_offer(current, EvolutionSystem.exits_of(&"f15"), 26, signature, true, false, [], points)
	_check("有达标出口只显示进化整备与僚机", ui._evolution_ready and ui._repair_confirm == null
		and ui._evo_confirm != null and not ui._wingman_confirm.disabled, "")
	ui._confirm_repair()
	_check("有出口时拒绝直接请求维修专属", not ui._decision_committed, "")
	ui._confirm_wingman()
	_check("选择僚机同拍锁树和所有选择", ui._decision_committed and not ui._tree.interactive
		and ui._evo_confirm.disabled and ui._wingman_confirm.disabled, "")
	ui.reject_decision()
	_check("权威拒绝后恢复输入", not ui._decision_committed and ui._tree.interactive
		and not ui._wingman_confirm.disabled, "")
	for state in ["ready", "locked", "equipped"]:
		ui.show_offer(current, EvolutionSystem.exits_of(&"f15"), 1, signature,
			state != "locked", state == "equipped", [], points)
		_check("等级不足可完整维修：" + state, not ui._evolution_ready and ui._evo_confirm == null
			and not ui._repair_confirm.disabled, "")
	ui.show_offer(current, EvolutionSystem.exits_of(&"f15"), 26, signature, true, false, [], {})
	_check("等级够但三轴不足改用维修", not ui._evolution_ready and ui._repair_confirm != null, "")
	var placeholder := SurvivorData.signature_upgrade_for_aircraft(&"mig21f13")
	ui.show_offer(EvolutionSystem.node_of(&"mig21f13"), EvolutionSystem.exits_of(&"mig21f13"),
		1, placeholder, false, false, [], {}, {}, false, false)
	_check("占位专属不发奖但可维修；未购僚机不可选", not ui._signature_ready
		and not ui._repair_confirm.disabled and ui._wingman_confirm.disabled, "")
	ui._confirm_repair()
	_check("维修提交锁住两个操作", ui._decision_committed and ui._repair_confirm.disabled
		and ui._wingman_confirm.disabled and not ui._tree.interactive, "")
	ui.free()


# ── G. 树连线与当前机体迁移（用户反馈 2026-08-02）──
func _test_tree_routes_and_current_marker() -> void:
	print("── G. 直角折线 + 进化成功后当前框迁移 ──")
	var tv := EvolutionTreeView.new()
	tv.setup(EvolutionSystem.all_nodes(), &"f15", [&"f15"], 26,
		{&"gladiator": 10, &"knight": 10, &"schemer": 10})
	var expected_edges := 0
	for nd in tv._nodes:
		var exits: Array = nd.get("exits", [])
		for exit_id in exits:
			if tv._rects.has(StringName(str(exit_id))):
				expected_edges += 1
	_check("全部 %d 条数据边都有布局路径" % expected_edges,
		tv._edge_routes.size() == expected_edges, "got %d" % tv._edge_routes.size())
	var bad_routes: Array[String] = []
	for key in tv._edge_routes:
		var route: PackedVector2Array = tv._edge_routes[key]
		if route.size() < 2:
			bad_routes.append("%s 点数不足" % key)
			continue
		for i in range(route.size() - 1):
			var d := route[i + 1] - route[i]
			if not is_zero_approx(d.x) and not is_zero_approx(d.y):
				bad_routes.append("%s 含斜段" % key)
				break
	_check("全 %d 条树边均为水平/垂直折线" % tv._edge_routes.size(), bad_routes.is_empty(),
		", ".join(bad_routes.slice(0, 5)))
	tv._selected = &"f15c"
	tv.set_current(&"f15c", [&"f15", &"f15c"])
	_check("进化后当前节点迁到 f15c", tv._current == &"f15c", str(tv._current))
	_check("进化后候选标记清除", tv._selected == &"", str(tv._selected))
	_check("进化后出口按新当前机重建", tv._exit_lv.has(&"f22"), str(tv._exit_lv.keys()))
	tv.free()


func _test_tree_hides_unreachable_routes() -> void:
	print("── H. 只隐藏结构不可达树枝，可达未知机仍保留？？？ ──")
	var codex_loaded_before := AircraftCodex._loaded
	var codex_before := AircraftCodex._discovered.duplicate(true)
	AircraftCodex._loaded = true
	AircraftCodex._discovered.clear()
	var tv := EvolutionTreeView.new()
	tv.setup(EvolutionSystem.all_nodes(), &"f16", [&"mig21f13", &"mig23", &"f16"], 26,
		{&"gladiator": 8, &"knight": 8, &"schemer": 8})
	_check("历史链节点继续显示", tv._rects.has(&"mig21f13") and tv._rects.has(&"mig23"), "")
	_check("当前机体节点继续显示", tv._rects.has(&"f16"), "")
	_check("当前机体的后继路线继续显示",
		EvolutionSystem.exits_of(&"f16").all(func(nd: Dictionary) -> bool:
			return tv._rects.has(StringName(nd.get("id", "")))), "")
	_check("结构可达但尚未拥有的远端机仍保留为？？？",
		tv._rects.has(&"x44") and not tv._is_revealed(&"x44"), "")
	_check("已经错过且从当前机不可达的旁支完全隐藏",
		not tv._rects.has(&"f15") and not tv._rects.has(&"f14"), "")
	for key in tv._edge_routes:
		var ends := String(key).split(">")
		_check("可见连线两端都属于当前路线：%s" % key,
			ends.size() == 2 and tv._rects.has(StringName(ends[0]))
			and tv._rects.has(StringName(ends[1])), "")
	tv.free()
	AircraftCodex._discovered = codex_before
	AircraftCodex._loaded = codex_loaded_before


func _test_hover_does_not_select() -> void:
	var loaded := AircraftCodex._loaded
	var discovered := AircraftCodex._discovered.duplicate(true)
	AircraftCodex._loaded = true
	AircraftCodex._discovered.clear()
	var tree := EvolutionTreeView.new()
	tree.setup(EvolutionSystem.all_nodes(), &"f16", [&"f16"], 26,
		{&"gladiator": 8, &"knight": 8, &"schemer": 8})
	var events := {"hover": &"", "selected": 0}
	tree.node_hovered.connect(func(id: StringName, _rect: Rect2) -> void: events.hover = id)
	tree.node_selected.connect(func(_id: StringName) -> void: events.selected += 1)
	var motion := InputEventMouseMotion.new()
	motion.position = (tree._rects[&"f35"] as Rect2).get_center()
	tree._gui_input(motion)
	_check("悬停只通知详情，不改变候选或提交选择", events.hover == &"f35"
		and events.selected == 0 and tree._selected == &"", "")
	tree.select_node(&"f35")
	motion.position = (tree._rects[&"f16"] as Rect2).get_center()
	tree._gui_input(motion)
	_check("浏览当前机保留已选后继", tree._selected == &"f35" and events.hover == &"f16", "")
	motion.position = (tree._rects[&"x44"] as Rect2).get_center()
	tree._gui_input(motion)
	_check("未知机体不发出详情信息", events.hover == &"" and tree._selected == &"f35", "")
	tree.interactive = false
	motion.position = (tree._rects[&"f35"] as Rect2).get_center()
	tree._gui_input(motion)
	_check("提交锁定后不接受悬停", events.hover == &"", "")
	tree.free()
	AircraftCodex._loaded = loaded
	AircraftCodex._discovered = discovered


## 同一档案在选机页、树节点和浮窗必须展示相同外形；未知机不创建模型。
func _test_model_previews() -> void:
	var preview := ModelPreview.new()
	var selection := AircraftHologramPreview.new()
	var missing: Array[String] = []
	var mismatched: Array[String] = []
	for nd in EvolutionSystem.all_nodes():
		var profile := AircraftDB.get_profile(StringName(nd.get("profile", "")))
		preview.show_profile(profile)
		selection.show_profile(profile, 0, 1)
		if not preview.has_model():
			missing.append(String(nd.get("id", "")))
		if preview._texture != selection._model._texture \
				or preview.model_key != selection._model.model_key or not selection.has_model_texture():
			mismatched.append(String(nd.get("id", "")))
	_check("全树机型均有真实预览图或已有模型顶视图", missing.is_empty(), str(missing))
	_check("进化预览与选机页共用相同机型和纹理", mismatched.is_empty(), str(mismatched))
	preview.show_profile(AircraftDB.get_profile(&"x44"))
	_check("无 PNG 的 X-44 使用自身模型顶视图", preview.model_key == "x44"
		and preview._texture == null and not preview._projection.is_empty(), "")
	preview.show_profile(null)
	selection.show_locked(0, 1)
	_check("未知/空档案清空前一架机体外形", not preview.has_model() and preview.model_key.is_empty()
		and not selection.has_model_texture() and not selection._model.has_model()
		and not selection._ghost_left.has_model() and not selection._ghost_right.has_model(), "")
	preview.free()
	selection.free()

	var loaded := AircraftCodex._loaded
	var discovered := AircraftCodex._discovered.duplicate(true)
	AircraftCodex._loaded = true
	AircraftCodex._discovered.clear()
	var tree := EvolutionTreeView.new()
	var points := {&"gladiator": 8, &"knight": 8, &"schemer": 8}
	var history := [&"mig21f13", &"mig23", &"f16"]
	tree.setup(EvolutionSystem.all_nodes(), &"f16", history, 26, points)
	_check("当前机、历史机与可进化出口都有外形", tree._models.has(&"f16")
		and tree._models.has(&"mig23") and tree._models.has(&"f35")
		and tree._models[&"f35"].has_model(), "")
	_check("未知远端节点不创建预览组件", not tree._models.has(&"x44"), "")
	var card: Rect2 = tree._rects[&"f35"]
	var model: Control = tree._models[&"f35"]
	_check("缩略图位于卡片内且不挡鼠标", card.encloses(model.get_rect())
		and model.mouse_filter == Control.MOUSE_FILTER_IGNORE, "")
	tree.select_node(&"f35")
	_check("选中反色同时作用于机体", model.modulate == Color.BLACK, "")
	AircraftCodex._discovered["x44"] = true
	tree.setup(EvolutionSystem.all_nodes(), &"f16", history, 1, points)
	_check("已知但本次门槛不足的飞机仍有外形", not tree.can_evolve(&"f35")
		and tree._models.has(&"f35") and tree._models[&"f35"].has_model(), "")
	_check("以前解锁的远端机显示自身模型", tree._models.has(&"x44")
		and tree._models[&"x44"].model_key == "x44" and tree._models[&"x44"].has_model(), "")
	AircraftCodex._discovered.clear()
	tree.setup(EvolutionSystem.all_nodes(), &"f16", history, 26, points)
	_check("重新打开未知机不会残留上次预览", not tree._models.has(&"x44"), "")
	tree.free()
	AircraftCodex._loaded = loaded
	AircraftCodex._discovered = discovered
	var panel := D.new()
	panel.show_node(&"f35", &"f16", 26, points)
	var detail_model := panel.get_node("AircraftModel") as ModelPreview
	_check("悬停详情展示对应机体", detail_model != null and detail_model.model_key == "f35"
		and detail_model.has_model() and detail_model.mouse_filter == Control.MOUSE_FILTER_IGNORE, "")
	panel.show_node(&"x44", &"f16", 26, points)
	detail_model = panel.get_node("AircraftModel") as ModelPreview
	_check("切换浮窗及时替换机体", detail_model != null and detail_model.model_key == "x44"
		and detail_model.has_model(), "")
	panel.free()


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
