class_name SurvivorDebugZone
extends CanvasLayer

## F6 Debug 战区面板 —— 编辑地图上真实的 A/B/C/D/E 战区内容
##
## 核心能力：
##   1. 列出所有战区 (A/B/C/D/E)，显示当前状态 + mission_type
##   2. 为每个战区选择新的 mission_type（ground/air/squadron/naval）
##   3. 一键 "Set & Spawn"：强制战区变为 AVAILABLE + 设定新类型 + 清旧单位 + 刷新内容
##   4. "Mark Cleared" / "Mark Locked" 改战区状态
##   5. "跳到 BOSS 战"：选定关底 BOSS + 计时器清零 → BOSS 立即出场
##
## 面板每 0.5s 刷新一次状态显示，避免卡顿

var game_scene: Node           ## survivor_mode（从这里拿 zone_mission / _zone_data）

# ── UI 根 ──
var _panel: PanelContainer
var _content: VBoxContainer
var _zones_list_container: VBoxContainer
var _boss_opt: OptionButton    ## 关底 BOSS 选择器
var _boss_status: Label        ## BOSS 阶段状态行

## BOSS 下拉选项：id 空串 = 按地图池随机。其余取自 BossRegistry.BOSS_DEFS
var _boss_ids: Array[String] = []

# ── 节流 + 状态指纹（只在战区真正变化时重建，避免把玩家正在操作的下拉覆盖掉）──
const REBUILD_INTERVAL: float = 0.5
var _rebuild_accum: float = 0.0
var _last_state_hash: String = ""

# ── 类型选项 ──
## 所有可用的 mission_type（Debug 用，跨越 zone 原本的限制）
const MISSION_TYPES: Array[String] = ["ground", "air", "squadron", "naval"]
const MISSION_TYPE_LABELS: Dictionary = {
	"ground": "陆基（SAM+AA）",
	"air": "空战（海上）",
	"squadron": "敌机中队",
	"naval": "海军舰队（DDG+FFG）",
}


# ============================================================
#  生命期
# ============================================================

func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		visible = not visible
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_rebuild_accum += delta
	if _rebuild_accum < REBUILD_INTERVAL:
		return
	_rebuild_accum = 0.0
	# BOSS 状态行每 tick 都刷（倒计时在连续变化，不能挂在指纹上）
	_refresh_boss_status()
	# 仅当战区状态真的变化时才重建列表（避免覆盖玩家正在操作的 OptionButton popup）
	var h: String = _compute_state_hash()
	if h == _last_state_hash:
		return
	_last_state_hash = h
	_rebuild_zones_list()

## 战区状态指纹：拼接所有战区的 state + mission_type + difficulty
## 任何维度变化都会导致字符串不同，从而触发重建
func _compute_state_hash() -> String:
	var zd := _get_zone_data()
	if zd == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for zid in ZoneData.get_all_zone_ids():
		parts.append("%s:%d:%s:%d" % [zid, zd.get_state(zid), zd.get_mission_type(zid), zd.get_difficulty(zid)])
	# BOSS 解锁也要进指纹 —— 否则跳转后战区列表不刷新，看不到"全部战区已关闭"
	parts.append("boss:%s" % str(zd.boss_unlocked))
	return "|".join(parts)


# ============================================================
#  UI 构建
# ============================================================

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.05, 0.95)
	style.border_color = Color(0.3, 0.7, 0.9, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(20, 20)
	_panel.custom_minimum_size = Vector2(440, 0)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_panel.add_child(_content)

	# 标题
	var title := Label.new()
	title.text = "[ DEBUG — 战区管理 (F6) ]"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	_content.add_child(_make_sep())

	# ── BOSS 战区块：选关底 BOSS + 一键跳转 ──
	var boss_title := Label.new()
	boss_title.text = "[ BOSS 战 ]"
	boss_title.add_theme_font_size_override("font_size", 13)
	boss_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(boss_title)

	_boss_status = Label.new()
	_boss_status.add_theme_font_size_override("font_size", 11)
	_boss_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_boss_status)

	var boss_row := HBoxContainer.new()
	boss_row.add_theme_constant_override("separation", 4)
	_content.add_child(boss_row)

	# 关底 BOSS 选择器：第 0 项随机，其余枚举 BossRegistry（含不在地图池里的 MOTHER_GOOSE）
	_boss_opt = OptionButton.new()
	_boss_opt.add_theme_font_size_override("font_size", 10)
	_boss_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_ids.clear()
	_boss_ids.append("")
	_boss_opt.add_item("🎲 按地图池随机", 0)
	for boss_id in BossRegistry.BOSS_DEFS.keys():
		var def: Dictionary = BossRegistry.BOSS_DEFS[boss_id]
		var in_pool: bool = _is_boss_in_map_pool(String(boss_id))
		# 池外 BOSS 标 ✱ —— 正常流程刷不到，只有这里能测（例如 MOTHER_GOOSE）
		var label: String = "%s%s" % [String(def.get("display_name", boss_id)), "" if in_pool else "  ✱池外"]
		_boss_opt.add_item(label, _boss_ids.size())
		_boss_ids.append(String(boss_id))
	boss_row.add_child(_boss_opt)

	var skip_btn := Button.new()
	skip_btn.text = "⚡ 跳到 BOSS 战"
	skip_btn.add_theme_font_size_override("font_size", 11)
	_apply_btn_style(skip_btn, Color(0.9, 0.25, 0.25))
	skip_btn.pressed.connect(_on_skip_to_boss)
	boss_row.add_child(skip_btn)

	_content.add_child(_make_sep())

	# 全局操作
	var global_row := HBoxContainer.new()
	global_row.add_theme_constant_override("separation", 8)
	_content.add_child(global_row)

	var unlock_e_btn := Button.new()
	unlock_e_btn.text = "🔓 强制解锁 E"
	unlock_e_btn.add_theme_font_size_override("font_size", 12)
	unlock_e_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(unlock_e_btn, Color(0.4, 0.75, 0.4))
	unlock_e_btn.pressed.connect(func(): _apply_zone_change(&"E", "naval"))
	global_row.add_child(unlock_e_btn)

	# 战区计时快进 60s：测"时间到点自动进 BOSS"的自然路径，不绕过任何逻辑
	var fast_btn := Button.new()
	fast_btn.text = "⏩ 战区计时 +60s"
	fast_btn.add_theme_font_size_override("font_size", 12)
	fast_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(fast_btn, Color(0.8, 0.7, 0.3))
	fast_btn.pressed.connect(_on_fast_forward)
	global_row.add_child(fast_btn)

	# 机场 Debug：复用正式停靠结算链，立即解放/访问机场并打开进化树。
	var visit_airfield_btn := Button.new()
	visit_airfield_btn.text = "✈ 立即访问机场 / 进化树"
	visit_airfield_btn.add_theme_font_size_override("font_size", 12)
	visit_airfield_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(visit_airfield_btn, Color(0.25, 0.75, 0.65))
	visit_airfield_btn.pressed.connect(_on_visit_airfield)
	_content.add_child(visit_airfield_btn)

	_content.add_child(_make_sep())

	# 战区列表容器
	var zones_title := Label.new()
	zones_title.text = "[ 战区列表 A/B/C/D/E ]"
	zones_title.add_theme_font_size_override("font_size", 13)
	zones_title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	zones_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(zones_title)

	_zones_list_container = VBoxContainer.new()
	_zones_list_container.add_theme_constant_override("separation", 6)
	_content.add_child(_zones_list_container)

	var hint := Label.new()
	hint.text = "F6 关闭  |  Set & Spawn: 强制 AVAILABLE + 换类型 + 刷新内容  |  跳 BOSS 会清掉全部战区残兵"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.65, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hint)


# ============================================================
#  战区列表重建
# ============================================================

func _get_zone_data() -> ZoneData:
	if game_scene and "_zone_data" in game_scene:
		return game_scene._zone_data
	return null

func _get_zone_mission() -> Node:
	if game_scene and "_zone_mission" in game_scene:
		return game_scene._zone_mission
	return null

func _rebuild_zones_list() -> void:
	for child in _zones_list_container.get_children():
		child.queue_free()

	var zd := _get_zone_data()
	if zd == null:
		var nope := Label.new()
		nope.text = "(ZoneData 未初始化 —— 是否在主菜单？)"
		nope.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
		_zones_list_container.add_child(nope)
		return

	for zid in ZoneData.get_all_zone_ids():
		_zones_list_container.add_child(_build_zone_row(zid, zd))

	# 更新指纹，避免下一个 _process tick 立即再 rebuild 一次
	_last_state_hash = _compute_state_hash()

func _build_zone_row(zid: StringName, zd: ZoneData) -> PanelContainer:
	var row := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.05, 0.08, 0.1, 0.7)
	row_style.border_color = Color(0.4, 0.6, 0.75, 0.4)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(3)
	row_style.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", row_style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	# 头部：编号 / 状态 / 当前 mission_type
	var state: int = zd.get_state(zid)
	var state_str: String = _state_label(state)
	var is_active: bool = (state == ZoneData.State.AVAILABLE or state == ZoneData.State.SELECTED)
	var mt_str: String = zd.get_mission_type(zid) if is_active else "(未激活)"
	var label: String = String(zd.get_zone_by_id(zid).get("label", String(zid)))
	var star_str: String = "★".repeat(zd.get_difficulty(zid)) if is_active else ""

	var header := Label.new()
	header.text = "[%s]  %s  %s  当前: %s" % [label, state_str, star_str, mt_str]
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", _state_color(state))
	col.add_child(header)

	# Mission type 下拉 + Set & Spawn 按钮
	var apply_row := HBoxContainer.new()
	apply_row.add_theme_constant_override("separation", 4)
	col.add_child(apply_row)

	var type_opt := OptionButton.new()
	type_opt.add_theme_font_size_override("font_size", 10)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(MISSION_TYPES.size()):
		var mt := MISSION_TYPES[i]
		type_opt.add_item(MISSION_TYPE_LABELS.get(mt, mt), i)
	# 默认选中当前 mission_type
	for i in range(MISSION_TYPES.size()):
		if MISSION_TYPES[i] == mt_str:
			type_opt.selected = i
			break
	apply_row.add_child(type_opt)

	var apply_btn := Button.new()
	apply_btn.text = "Set & Spawn"
	apply_btn.add_theme_font_size_override("font_size", 10)
	_apply_btn_style(apply_btn, Color(0.3, 0.7, 0.9))
	apply_btn.pressed.connect(func():
		var idx := type_opt.selected
		if idx < 0 or idx >= MISSION_TYPES.size():
			return
		_apply_zone_change(zid, MISSION_TYPES[idx]))
	apply_row.add_child(apply_btn)

	# 状态按钮：Mark Cleared / Mark Locked / Purge Only
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 4)
	col.add_child(state_row)

	var clear_btn := Button.new()
	clear_btn.text = "✓ Clear"
	clear_btn.add_theme_font_size_override("font_size", 10)
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(clear_btn, Color(0.4, 0.8, 0.4))
	clear_btn.pressed.connect(func(): _on_mark_cleared(zid))
	state_row.add_child(clear_btn)

	var lock_btn := Button.new()
	lock_btn.text = "🔒 Lock"
	lock_btn.add_theme_font_size_override("font_size", 10)
	lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(lock_btn, Color(0.6, 0.5, 0.3))
	lock_btn.pressed.connect(func(): _on_mark_locked(zid))
	state_row.add_child(lock_btn)

	# Purge 专按钮：只擦敌人，不改 state，保留任务可再次进入
	var purge_btn := Button.new()
	purge_btn.text = "✖ Purge"
	purge_btn.add_theme_font_size_override("font_size", 10)
	purge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_btn_style(purge_btn, Color(0.75, 0.3, 0.3))
	purge_btn.pressed.connect(func(): _on_purge_only(zid))
	state_row.add_child(purge_btn)

	return row


# ============================================================
#  交互回调
# ============================================================

## 核心：把战区切到 AVAILABLE + 指定 mission_type + 重刷内容
func _apply_zone_change(zid: StringName, new_mission_type: String) -> void:
	var zd := _get_zone_data()
	var zm := _get_zone_mission()
	if zd == null or zm == null:
		return

	# 覆写 mission_type
	zd.debug_set_mission_type(zid, new_mission_type)

	var state := zd.get_state(zid)
	if state == ZoneData.State.LOCKED or state == ZoneData.State.CLEARED:
		# 先解锁（内部会保留我们刚写的 mission_type，因为 debug_set_available 只在没有时才 roll）
		zm.debug_force_unlock_zone(zid)
	else:
		# 已 AVAILABLE / SELECTED → 直接清旧重刷
		zm.debug_force_respawn_zone(zid)

	EventLogger.log_event("ZONE", "DebugApply",
		"id=%s new_mt=%s prev_state=%d" % [zid, new_mission_type, state])
	_rebuild_zones_list()

## 跳到 BOSS 战：选定关底 BOSS → 计时器清零 → BOSS 立即出场
##
## 旧实现只标 A/B/C cleared + cleared_count=3，但【从没设 boss_unlocked】，
## 而真正的解锁只发生在 survivor_mode._check_warzone_phase_timeout()（要求 game_time ≥ 600）。
## 于是 _update_boss_phase() 永远不触发 —— 按钮点了没反应。
## 现改为把解锁全权交给 survivor_mode.debug_skip_to_boss()，此处只负责清场 + 选 BOSS。
func _on_skip_to_boss() -> void:
	var zd := _get_zone_data()
	var zm := _get_zone_mission()
	if zd == null or game_scene == null:
		return
	if not game_scene.has_method("debug_skip_to_boss"):
		push_error("SurvivorDebugZone: survivor_mode 缺 debug_skip_to_boss()")
		return

	# 先清掉战区残兵，避免 BOSS 战里混着上一阶段的杂兵干扰测试
	if zm:
		for zid in ZoneData.get_all_zone_ids():
			zm.debug_purge_zone(zid)

	var idx: int = _boss_opt.selected if _boss_opt else 0
	var boss_id: String = _boss_ids[idx] if idx >= 0 and idx < _boss_ids.size() else ""
	game_scene.debug_skip_to_boss(boss_id)
	_rebuild_zones_list()

## 战区计时 +60s —— 走自然到点路径，用于验证"时间到 → 自动进 BOSS"本身没坏
func _on_fast_forward() -> void:
	if game_scene == null or not ("game_time" in game_scene):
		return
	game_scene.game_time += 60.0
	EventLogger.log_event("ZONE", "DebugFastForward", "game_time=%.0f" % game_scene.game_time)
	_rebuild_zones_list()

## 立即访问机场：由 survivor_mode 选择已开放机场或解放一座机场，
## 最终统一走正式 _on_dock_docked 停靠结算（回血 / 机场消费 / 进化树）。
func _on_visit_airfield() -> void:
	if game_scene == null or not game_scene.has_method("debug_visit_airfield"):
		push_error("SurvivorDebugZone: survivor_mode 缺 debug_visit_airfield()")
		return
	# F6 layer=31 高于进化面板；先收起，避免 Debug 面板盖住结算 UI。
	visible = false
	game_scene.debug_visit_airfield()
	_rebuild_zones_list()

## BOSS 阶段状态行：剩余时间 / 是否已解锁 / 实际出场的 BOSS
func _refresh_boss_status() -> void:
	if _boss_status == null:
		return
	if game_scene == null or not ("game_time" in game_scene):
		_boss_status.text = "(未在生存模式)"
		_boss_status.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
		return
	var gt: float = game_scene.game_time
	# survivor_mode.gd 无 class_name，常量只能经实例取
	var total: float = float(game_scene.get("WARZONE_PHASE_DURATION"))
	var in_boss: bool = game_scene._is_in_boss_phase() if game_scene.has_method("_is_in_boss_phase") else false
	if in_boss:
		var forced: String = String(game_scene.debug_boss_id_override) if "debug_boss_id_override" in game_scene else ""
		_boss_status.text = "▶ BOSS 阶段进行中  (%s)" % [forced if forced != "" else "地图池随机"]
		_boss_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	else:
		var remain: float = maxf(0.0, total - gt)
		_boss_status.text = "战区剩余 %d:%02d  →  到点自动进 BOSS" % [int(remain) / 60, int(remain) % 60]
		_boss_status.add_theme_color_override("font_color", Color(0.7, 0.8, 0.85))

## 该 BOSS 是否在当前地图的随机池里（不在池里的只能靠本面板强制指定）
func _is_boss_in_map_pool(boss_id: String) -> bool:
	var map_id: String = String(game_scene._map_id) if game_scene and "_map_id" in game_scene else "default"
	var pool: Array = BossRegistry.MAP_POOLS.get(map_id, BossRegistry.MAP_POOLS.get("default", []))
	return pool.has(boss_id)

func _on_mark_cleared(zid: StringName) -> void:
	var zd := _get_zone_data()
	var zm := _get_zone_mission()
	if zd == null:
		return
	zd.debug_mark_cleared(zid)
	if zm:
		zm.debug_purge_zone(zid)  # 真清单位（视线外延迟 free）
	_rebuild_zones_list()

func _on_mark_locked(zid: StringName) -> void:
	var zd := _get_zone_data()
	var zm := _get_zone_mission()
	if zd == null:
		return
	zd.debug_mark_locked(zid)
	if zm:
		zm.debug_purge_zone(zid)
	_rebuild_zones_list()

## 只清敌人、不改 state —— 下一帧 _ensure_spawned_for_active_zones 会按当前 mission_type 重刷
## 相当于"把这个战区的敌人重置一下，重新打"
func _on_purge_only(zid: StringName) -> void:
	var zm := _get_zone_mission()
	if zm == null:
		return
	zm.debug_purge_zone(zid)
	EventLogger.log_event("ZONE", "DebugPurgeOnly", "id=%s" % zid)
	_rebuild_zones_list()


# ============================================================
#  状态显示辅助
# ============================================================

func _state_label(state: int) -> String:
	match state:
		ZoneData.State.LOCKED: return "🔒锁定"
		ZoneData.State.AVAILABLE: return "✨可选"
		ZoneData.State.SELECTED: return "▶执行中"
		ZoneData.State.CLEARED: return "✓已完成"
	return "?"

func _state_color(state: int) -> Color:
	match state:
		ZoneData.State.LOCKED: return Color(0.55, 0.55, 0.55)
		ZoneData.State.AVAILABLE: return Color(0.9, 0.9, 0.7)
		ZoneData.State.SELECTED: return Color(0.3, 0.85, 1.0)
		ZoneData.State.CLEARED: return Color(0.4, 0.8, 0.4)
	return Color.WHITE


# ============================================================
#  UI 辅助
# ============================================================

func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.6, 0.75, 0.3))
	return sep

func _apply_btn_style(btn: Button, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.85)
	s.border_color = Color(accent, 0.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate()
	h.bg_color = Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 0.95)
	h.border_color = Color(accent, 0.9)
	btn.add_theme_stylebox_override("hover", h)
