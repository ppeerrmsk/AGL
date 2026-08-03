class_name CommandWheel
extends CanvasLayer
## 命令轮盘（权威源：docs/specs/systems/command-wheel.md）——长按左键呼出的 marking menu。
## 操作语法：单点 = 只操控自机（survivor_mode 处理），轮盘 = 永远全队广播。
## 交互（用户定稿）：
##   扇区松开 = 执行；中心死区松开 = 回退普通单击（前往/攻击）；左上角红色"取消"槽 = 取消本次
##   轮盘交互（如同没按过）；开关槽悬停弹出二级面板（往深处拉显式选 开/关 等选项）。
## 反馈：悬停槽位画出对应命令的世界范围圈（撤离 5km / 防守 3km 等）；轮盘下方常驻功能说明条。
## 性能：IDLE 时 set_process(false) + 画布隐藏，常驻零开销；仅激活期间每帧重绘。

signal command_selected(context: int, slot_id: String, world_pos: Vector2, target: CombatUnit, option: String)

enum State { IDLE, PRESS_PENDING, ACTIVE }
enum Context { SQUAD, ATTACK }
## end_press 结果：CLICK = 普通单击回放（快速松开 或 中心死区松开）；
## EXECUTED = 槽位命令已执行；CANCELLED = 取消槽松开 / 右键中止 / 无按下记录
enum Outcome { CLICK, EXECUTED, CANCELLED }

const COL_RING := Color(0.55, 0.85, 1.0, 0.30)
const COL_RING_ATTACK := Color(1.0, 0.5, 0.4, 0.35)
const COL_DEAD := Color(0.7, 0.85, 1.0, 0.5)
const COL_TEXT := Color(0.92, 0.97, 1.0, 0.95)
const COL_STATE := Color(0.65, 0.8, 0.9, 0.85)
const COL_HILIT := Color(1.0, 0.85, 0.3, 1.0)
const COL_SLOT_BG := Color(0.06, 0.14, 0.2, 0.6)
const COL_POINTER := Color(0.8, 0.9, 1.0, 0.35)
const COL_CANCEL := Color(0.95, 0.35, 0.3, 0.95)
const COL_CANCEL_BG := Color(0.3, 0.07, 0.06, 0.65)
const COL_RANGE_FILL := Color(0.55, 0.85, 1.0, 0.06)
const COL_RANGE_LINE := Color(0.55, 0.85, 1.0, 0.35)
const COL_TIP_BG := Color(0.04, 0.1, 0.15, 0.85)
## 轮盘激活时的全屏压暗背景：让轮盘成为唯一视觉焦点，其余 HUD/横幅（边界提示等）统一淡出
const COL_BACKDROP := Color(0.0, 0.0, 0.0, 0.35)
## 攻击轮盘按下目标的高亮标记（"我正在对它下令"），与槽位高亮同色系
const COL_TGT_HILIT := Color(1.0, 0.85, 0.3)

const SLOT_W := 116.0
const SLOT_H := 40.0
## 槽位牌中心到轮盘中心的距离 = ring1_outer + 此偏移
const SLOT_OFFSET_PX := 34.0
## 二级面板：指针拉出此半径即进入选项区（锁定父槽，只切换选项）
const RING2_START_PX := 176.0
## 二级选项牌中心到轮盘中心的距离
const RING2_DIST_PX := 218.0
## 二级选项相对父槽方向的角度间隔（度）
const OPTION_SPREAD_DEG := 17.0
const OPTION_W := 88.0
const OPTION_H := 32.0
## 功能说明条（tooltip）
const TIP_W := 340.0
const TIP_OFFSET_Y := 208.0

var params: CommandWheelParams
var _mode: Node = null

var _state: int = State.IDLE
var _context: int = Context.SQUAD
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _press_target: CombatUnit = null
var _press_at_s: float = 0.0
var _hover_slot: String = ""
var _hover_option: String = ""
var _time_scale_applied := false
var _canvas: WheelCanvas = null

## 槽位表（spec §2.3/§2.4）：angle 单位度，0=上、顺时针；
## options 非空 = 开关槽（悬停弹二级面板，显式选值；直接在槽上松开 = 翻转/循环）。
## "wheel_cancel" 为两轮盘统一的左上角取消槽（红色）。
var _slots_squad: Array[Dictionary] = [
	{ "id": "regroup", "angle": 0.0, "key": "WHEEL_REGROUP", "options": [] },
	{ "id": "alt_pref", "angle": 90.0, "key": "WHEEL_ALT_PREF", "options": [
		{ "v": "climb", "key": "WHEEL_STATE_CLIMB" }, { "v": "low", "key": "WHEEL_STATE_LOW" }] },
	{ "id": "autofire", "angle": 135.0, "key": "WHEEL_AUTOFIRE", "options": [
		{ "v": "on", "key": "WHEEL_STATE_ON" }, { "v": "off", "key": "WHEEL_STATE_OFF" }] },
	{ "id": "guard_area", "angle": 180.0, "key": "WHEEL_GUARD_AREA", "options": [] },
	{ "id": "evac_area", "angle": 225.0, "key": "WHEEL_EVAC_AREA", "options": [] },
	{ "id": "auto_engage", "angle": 270.0, "key": "WHEEL_AUTO_ENGAGE", "options": [
		{ "v": "on", "key": "WHEEL_STATE_ON" }, { "v": "off", "key": "WHEEL_STATE_OFF" }] },
	{ "id": "wheel_cancel", "angle": 315.0, "key": "WHEEL_CANCEL", "options": [] },
]
var _slots_attack: Array[Dictionary] = [
	{ "id": "standoff", "angle": 0.0, "key": "WHEEL_STANDOFF", "options": [] },
	{ "id": "formation", "angle": 90.0, "key": "WHEEL_FORMATION", "options": [
		{ "v": "free", "key": "WHEEL_STATE_FREE" }, { "v": "tight", "key": "WHEEL_STATE_TIGHT" }] },
	{ "id": "assault", "angle": 180.0, "key": "WHEEL_ASSAULT", "options": [] },
	{ "id": "fire_alloc", "angle": 270.0, "key": "WHEEL_FIRE_ALLOC", "options": [
		{ "v": "focus", "key": "WHEEL_STATE_FOCUS" }, { "v": "spread", "key": "WHEEL_STATE_SPREAD" }] },
	{ "id": "wheel_cancel", "angle": 315.0, "key": "WHEEL_CANCEL", "options": [] },
]


func setup(mode: Node, p: CommandWheelParams) -> void:
	_mode = mode
	params = p


func _ready() -> void:
	layer = 100
	_canvas = WheelCanvas.new()
	_canvas.wheel = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.visible = false
	add_child(_canvas)
	set_process(false)


## 左键按下：记录按下瞬间的参数（世界坐标 / 目标 / 屏幕位置），进入 PRESS_PENDING。
func begin_press(screen_pos: Vector2, world_pos: Vector2, target: CombatUnit) -> void:
	if _state != State.IDLE:
		_reset()
	_state = State.PRESS_PENDING
	_press_screen = screen_pos
	_press_world = world_pos
	_press_target = target
	_context = Context.ATTACK if target != null else Context.SQUAD
	_press_at_s = Time.get_ticks_msec() / 1000.0
	_canvas.visible = true   # PRESS_PENDING 期间绘制蓄力指示圈（有 charge_visual_delay 静默期）
	set_process(true)


## 左键松开：返回 { "outcome": Outcome, "world_pos": Vector2, "target": CombatUnit }。
func end_press() -> Dictionary:
	var result := {
		"outcome": Outcome.CANCELLED,
		"world_pos": _press_world,
		"target": _press_target,
	}
	match _state:
		State.PRESS_PENDING:
			result["outcome"] = Outcome.CLICK
			_reset()
		State.ACTIVE:
			var slot := _hover_slot
			var option := _hover_option
			var ctx := _context
			var wpos := _press_world
			var tgt := _press_target
			_reset()
			if slot == "" :
				# 中心死区松开 = 回退普通单击（移动/点名，按下参数回放）
				result["outcome"] = Outcome.CLICK
			elif slot == "wheel_cancel":
				# 取消本次轮盘交互（不动任何正在进行的战斗/移动状态）
				result["outcome"] = Outcome.CANCELLED
			else:
				result["outcome"] = Outcome.EXECUTED
				command_selected.emit(ctx, slot, wpos, tgt, option)
		_:
			pass  # IDLE：无按下记录（如场景切换后残留的 release），按取消处理
	return result


## 其他输入打断（如轮盘期间按右键）：中止轮盘。返回是否确实中止了一次手势。
func abort_if_pending() -> bool:
	if _state == State.IDLE:
		return false
	_reset()
	return true


func _process(_delta: float) -> void:
	# 安全阀 1：手势中途游戏被暂停（升级面板等）/ game over → 直接中止，避免 time_scale 残留
	if get_tree().paused:
		_reset()
		return
	if _mode != null and "is_game_over" in _mode and _mode.is_game_over:
		_reset()
		return
	# 安全阀 2：左键 release 事件丢失（alt-tab / 窗口失焦）→ 轮询兜底中止。
	# 正常松开时 release 事件先于本帧 _process 处理，届时已回 IDLE，不会误吞。
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_reset()
		return
	var mouse := _canvas.get_local_mouse_position()
	match _state:
		State.PRESS_PENDING:
			var held := Time.get_ticks_msec() / 1000.0 - _press_at_s
			if held >= params.hold_threshold_s:
				_activate()
			else:
				_canvas.queue_redraw()   # 蓄力指示圈动画（仅按住期间，快速单击几乎不可见）
		State.ACTIVE:
			_update_hover(mouse)
			_canvas.queue_redraw()  # 指针连线/高亮/范围圈跟随指针，仅激活期间有此成本


## 悬停判定：一环区选槽位；拉进二级区（RING2_START 外）且父槽有选项 → 锁定父槽只切换选项
func _update_hover(mouse: Vector2) -> void:
	var dist := mouse.distance_to(_press_screen)
	if dist >= RING2_START_PX and _hover_slot != "" and not _slot_options(_hover_slot).is_empty():
		_hover_option = _pick_option(mouse)
		return
	_hover_slot = _pick_slot(mouse)
	_hover_option = ""


func _activate() -> void:
	_state = State.ACTIVE
	_hover_slot = ""
	_hover_option = ""
	# 走时间栈而非直写 Engine.time_scale —— 与升级急刹叠加时按"最小值获胜"仲裁，
	# 谁先释放都不会把对方的缩放一起撤掉（spec ui-transition §2.2）
	Presentation.time.request(&"wheel", params.time_scale_in_wheel, 0.0)
	_time_scale_applied = true
	_canvas.visible = true
	_canvas.queue_redraw()


func _reset() -> void:
	_state = State.IDLE
	_hover_slot = ""
	_hover_option = ""
	if _time_scale_applied:
		Presentation.time.release(&"wheel", 0.0)
		_time_scale_applied = false
	if _canvas:
		_canvas.visible = false
	set_process(false)


func _exit_tree() -> void:
	# 场景切换保险：绝不把 0.3x 时间流速带出本场景。
	# 必须走时间栈释放而非直写 —— 直写会让栈里仍记着 wheel 的请求，
	# 下一次任何 request/release 重算时 0.3x 会被"复活"
	if _time_scale_applied:
		_time_scale_applied = false
		var pres = Engine.get_main_loop().root.get_node_or_null("Presentation")
		if pres and pres.time:
			pres.time.release(&"wheel", 0.0)
		else:
			Engine.time_scale = 1.0


func _active_slots() -> Array[Dictionary]:
	return _slots_attack if _context == Context.ATTACK else _slots_squad


func _slot_by_id(id: String) -> Dictionary:
	for s in _active_slots():
		if s["id"] == id:
			return s
	return {}


func _slot_options(id: String) -> Array:
	var s := _slot_by_id(id)
	if s.is_empty():
		return []
	return s["options"]


## 指针方向 → 槽位 id；死区/无邻近槽位返回 ""
func _pick_slot(mouse: Vector2) -> String:
	var v := mouse - _press_screen
	if v.length() <= params.dead_zone_radius_px:
		return ""
	var ang := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	# 扇区容差 = 半个最小槽位间距（两轮盘都含 45° 相邻槽 → ±22.5）
	var tol := 22.5
	var best := ""
	var best_d := tol + 0.001
	for s in _active_slots():
		var d := absf(_angle_diff_deg(ang, s["angle"]))
		if d < best_d:
			best_d = d
			best = s["id"]
	return best


## 二级选项判定：按角度取父槽选项中最邻近者（进入二级区后必选其一）
func _pick_option(mouse: Vector2) -> String:
	var opts := _slot_options(_hover_slot)
	if opts.is_empty():
		return ""
	var parent := _slot_by_id(_hover_slot)
	var v := mouse - _press_screen
	var ang := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	var best := ""
	var best_d := 1e9
	for i in opts.size():
		var oa := _option_angle(parent["angle"], i, opts.size())
		var d := absf(_angle_diff_deg(ang, oa))
		if d < best_d:
			best_d = d
			best = opts[i]["v"]
	return best


static func _option_angle(parent_angle: float, index: int, count: int) -> float:
	return parent_angle + OPTION_SPREAD_DEG * (float(index) - float(count - 1) * 0.5) * 2.0


static func _angle_diff_deg(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0


func _squad_cmd_ref() -> SquadCommandController:
	if _mode != null and "_squad_cmd" in _mode:
		return _mode._squad_cmd
	return null


func _player_ref() -> Aircraft:
	if _mode != null and "player_aircraft" in _mode:
		var cand = _mode.player_aircraft
		if cand != null and is_instance_valid(cand):
			return cand
	return null


## 开关槽位的当前值（与二级面板 option 的 "v" 同一词汇表）
func current_option_value(id: String) -> String:
	var pl := _player_ref()
	match id:
		"auto_engage":
			if pl:
				return "on" if pl.auto_engage_enabled else "off"
		"alt_pref":
			if pl:
				return "climb" if pl.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB else "low"
		"autofire":
			if pl:
				return "on" if pl.missile_auto_fire else "off"
		"fire_alloc":
			var sc := _squad_cmd_ref()
			if sc != null and sc.fire_allocation == SquadCommandController.FireAllocation.SPREAD:
				return "spread"
			return "focus"
		"formation":
			var sc2 := _squad_cmd_ref()
			if sc2 != null and sc2.formation_tight:
				return "tight"
			return "free"
	return ""


## 开关槽位的当前状态显示文本
func slot_state_text(id: String) -> String:
	var cur := current_option_value(id)
	if cur == "":
		return ""
	for o in _slot_options(id):
		if o["v"] == cur:
			return tr(o["key"])
	return ""


## 槽位关联的世界范围圈（悬停时绘制；返回 [{center: 世界坐标, radius: 世界px}, ...]）
func _slot_range_circles(id: String) -> Array:
	match id:
		"regroup":
			return [{ "center": _press_world, "radius": params.arrival_radius_px }]
		"evac_area":
			return [{ "center": _press_world, "radius": params.evac_radius_px }]
		"guard_area":
			return [
				{ "center": _press_world, "radius": params.guard_radius_px },
				{ "center": _press_world, "radius": params.orbit_radius_px },
			]
		"auto_engage":
			var pl := _player_ref()
			var sc := _squad_cmd_ref()
			if pl != null and sc != null and sc.params != null:
				return [{ "center": pl.global_position, "radius": sc.params.auto_engage_radius_px }]
		# 注：火力分配/阵型纪律是模式开关而非空间命令，不画范围圈（用户定稿）
	return []


## 悬停项的功能说明 key（轮盘下方说明条；未悬停时解释中心默认行为）
func _tip_key() -> String:
	if _hover_slot == "":
		return "WHEEL_TIP_CENTER_ATTACK" if _context == Context.ATTACK else "WHEEL_TIP_CENTER_MOVE"
	match _hover_slot:
		"regroup": return "WHEEL_TIP_REGROUP"
		"evac_area": return "WHEEL_TIP_EVAC"
		"guard_area": return "WHEEL_TIP_GUARD"
		"auto_engage": return "WHEEL_TIP_AUTO_ENGAGE"
		"alt_pref": return "WHEEL_TIP_ALT_PREF"
		"autofire": return "WHEEL_TIP_AUTOFIRE"
		"standoff": return "WHEEL_TIP_STANDOFF"
		"assault": return "WHEEL_TIP_ASSAULT"
		"fire_alloc": return "WHEEL_TIP_FIRE_ALLOC"
		"formation": return "WHEEL_TIP_FORMATION"
		"wheel_cancel": return "WHEEL_TIP_CANCEL"
	return ""


# ══════════════════════════════════════════════
#  绘制（仅 ACTIVE；WheelCanvas 代理调用）
# ══════════════════════════════════════════════

func _draw_wheel(c: Control) -> void:
	if _state == State.PRESS_PENDING:
		_draw_charge_ring(c)
		return
	if _state != State.ACTIVE:
		return
	var center := _press_screen
	var font := c.get_theme_default_font()
	var ring_col := COL_RING_ATTACK if _context == Context.ATTACK else COL_RING
	# 0) 全屏压暗背景：轮盘在 layer 100（一切战场 HUD 之上），压暗其下所有横幅/提示
	c.draw_rect(Rect2(Vector2.ZERO, c.get_viewport_rect().size), COL_BACKDROP, true)
	# 1) 悬停命令的世界范围圈（世界坐标 → 屏幕：经 survivor_mode(Node2D) 的 canvas transform）
	_draw_range_circles(c)
	# 1.5) 攻击轮盘：按下目标高亮层（脉冲光圈 + 旋转括环，跟随目标/镜头）
	if _context == Context.ATTACK:
		_draw_target_highlight(c)
	# 1) 指针连线（死区外才画）
	var mouse := c.get_local_mouse_position()
	if mouse.distance_to(center) > params.dead_zone_radius_px:
		c.draw_line(center, mouse, COL_POINTER, 1.0)
	# 2) 中心死区 + 一环
	c.draw_arc(center, params.dead_zone_radius_px, 0.0, TAU, 40, COL_DEAD, 1.5)
	c.draw_arc(center, params.ring1_outer_px, 0.0, TAU, 64, ring_col, 1.0)
	# 3) 死区内提示：中心松开 = 默认单击语义（移动 / 攻击目标）
	if _hover_slot == "":
		var center_key := "WHEEL_CENTER_ATTACK" if _context == Context.ATTACK else "WHEEL_CENTER_MOVE"
		c.draw_string(font, center + Vector2(-40.0, 5.0), tr(center_key),
				HORIZONTAL_ALIGNMENT_CENTER, 80.0, 12, COL_DEAD)
	# 4) 槽位牌
	for s in _active_slots():
		var ang_rad := deg_to_rad(s["angle"])
		var dir := Vector2(sin(ang_rad), -cos(ang_rad))
		var pos := center + dir * (params.ring1_outer_px + SLOT_OFFSET_PX)
		_draw_slot(c, font, pos, s, s["id"] == _hover_slot)
	# 5) 二级面板（悬停开关槽时弹出）
	if _hover_slot != "" and not _slot_options(_hover_slot).is_empty():
		_draw_options(c, font)
	# 6) 功能说明条（tooltip）
	_draw_tip(c, font)


func _draw_range_circles(c: Control) -> void:
	if _hover_slot == "" or not (_mode is Node2D):
		return
	var circles := _slot_range_circles(_hover_slot)
	if circles.is_empty():
		return
	var ct: Transform2D = (_mode as Node2D).get_canvas_transform()
	var zoom := ct.get_scale().x
	for circle in circles:
		var sp: Vector2 = ct * (circle["center"] as Vector2)
		var sr: float = (circle["radius"] as float) * zoom
		c.draw_circle(sp, sr, COL_RANGE_FILL)
		c.draw_arc(sp, sr, 0.0, TAU, 96, COL_RANGE_LINE, 1.5)


## 指挥对象高亮：轮盘期间明确"当前命令针对的是这个单位"（敌机/地面单位通用）。
## 屏幕空间覆盖层实现，不改单位本体渲染；目标阵亡即消失。
func _draw_target_highlight(c: Control) -> void:
	if _press_target == null or not is_instance_valid(_press_target) or not (_mode is Node2D):
		return
	if _press_target.is_destroyed:
		return
	var ct: Transform2D = (_mode as Node2D).get_canvas_transform()
	var sp: Vector2 = ct * _press_target.global_position
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var r := 34.0 + 4.0 * pulse
	# 柔光（两层低透明填充，模拟"变亮"滤镜的观感）
	c.draw_circle(sp, r * 1.5, Color(COL_TGT_HILIT, 0.08))
	c.draw_circle(sp, r * 1.1, Color(COL_TGT_HILIT, 0.13))
	# 主环
	c.draw_arc(sp, r, 0.0, TAU, 48, Color(COL_TGT_HILIT, 0.85), 2.0)
	# 旋转括环：4 段弧慢速旋转，标示"指令进行中"
	var spin := t * 1.6
	for i in 4:
		var a0 := spin + float(i) * TAU * 0.25
		c.draw_arc(sp, r + 7.0, a0, a0 + 0.55, 10, Color(COL_TGT_HILIT, 0.9), 2.5)


## 呼出蓄力指示圈（用户需求 2026-07-20）：按住时"转一个小圈"表示正在进入菜单，转满才呼出。
## 视觉仿机场停靠引导灯：外圈 12 枚引导灯按蓄力进度顺时针依次点亮 + 进度弧 +
## 一段追逐扫描弧（导引灯流动感）；接近转满（>80%）整体切到高亮色预告"即将进入"。
## charge_visual_delay 静默期内不画——普通快速单击零 UI 噪音。
func _draw_charge_ring(c: Control) -> void:
	var held := Time.get_ticks_msec() / 1000.0 - _press_at_s
	var delay := params.charge_visual_delay_s if "charge_visual_delay_s" in params else 0.08
	if held < delay:
		return
	var t := clampf((held - delay) / maxf(params.hold_threshold_s - delay, 0.01), 0.0, 1.0)
	var center := _press_screen
	var near_done := t > 0.8
	var main_col := COL_HILIT if near_done else COL_DEAD
	# 12 枚停靠引导灯：进度点亮（12 点方向起顺时针）
	var lit := int(floor(t * 12.0 + 0.001))
	for i in 12:
		var a := -PI * 0.5 + TAU * float(i) / 12.0
		var dir := Vector2(cos(a), sin(a))
		var col := main_col if i < lit else Color(COL_DEAD, 0.18)
		c.draw_line(center + dir * 16.0, center + dir * 24.0, col, 2.0)
	# 进度弧（外环，12 点方向起顺时针扫满）
	if t > 0.02:
		c.draw_arc(center, 29.0, -PI * 0.5, -PI * 0.5 + TAU * t, 40, main_col, 2.0)
	# 追逐扫描弧：绕圈流动的导引光带
	var spin := held * 5.0
	c.draw_arc(center, 29.0, spin, spin + 0.8, 10, Color(COL_POINTER, 0.45), 1.5)
	# 中心锚点
	c.draw_circle(center, 2.5, main_col)


func _draw_slot(c: Control, font: Font, pos: Vector2, s: Dictionary, hovered: bool) -> void:
	var is_cancel: bool = s["id"] == "wheel_cancel"
	var rect := Rect2(pos - Vector2(SLOT_W * 0.5, SLOT_H * 0.5), Vector2(SLOT_W, SLOT_H))
	c.draw_rect(rect, COL_CANCEL_BG if is_cancel else COL_SLOT_BG, true)
	var border: Color
	if hovered:
		border = COL_CANCEL if is_cancel else COL_HILIT
	elif is_cancel:
		border = Color(COL_CANCEL, 0.55)
	else:
		border = COL_RING_ATTACK if _context == Context.ATTACK else COL_RING
	c.draw_rect(rect, border, false, 2.0 if hovered else 1.0)
	var label := tr(s["key"])
	var label_col: Color
	if is_cancel:
		label_col = COL_CANCEL
	elif hovered:
		label_col = COL_HILIT
	else:
		label_col = COL_TEXT
	var state := slot_state_text(s["id"])
	if state != "":
		c.draw_string(font, Vector2(rect.position.x, rect.position.y + 17.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 13, label_col)
		c.draw_string(font, Vector2(rect.position.x, rect.position.y + 33.0), state,
				HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 12, COL_STATE)
	else:
		c.draw_string(font, Vector2(rect.position.x, rect.position.y + 25.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 14, label_col)


func _draw_options(c: Control, font: Font) -> void:
	var parent := _slot_by_id(_hover_slot)
	var opts := _slot_options(_hover_slot)
	var cur := current_option_value(_hover_slot)
	for i in opts.size():
		var oa := _option_angle(parent["angle"], i, opts.size())
		var dir := Vector2(sin(deg_to_rad(oa)), -cos(deg_to_rad(oa)))
		var pos := _press_screen + dir * RING2_DIST_PX
		var rect := Rect2(pos - Vector2(OPTION_W * 0.5, OPTION_H * 0.5), Vector2(OPTION_W, OPTION_H))
		var o: Dictionary = opts[i]
		var hovered: bool = o["v"] == _hover_option
		var is_current: bool = o["v"] == cur
		c.draw_rect(rect, COL_SLOT_BG, true)
		var border := COL_HILIT if hovered else (COL_TEXT if is_current else COL_STATE)
		c.draw_rect(rect, border, false, 2.0 if hovered else 1.0)
		var col := COL_HILIT if hovered else (COL_TEXT if is_current else COL_STATE)
		c.draw_string(font, Vector2(rect.position.x, rect.position.y + 21.0), tr(o["key"]),
				HORIZONTAL_ALIGNMENT_CENTER, OPTION_W, 13, col)
		# 当前生效值标记（左侧小点）
		if is_current:
			c.draw_circle(Vector2(rect.position.x + 9.0, pos.y), 2.5, COL_TEXT)


func _draw_tip(c: Control, font: Font) -> void:
	var key := _tip_key()
	if key == "":
		return
	var text := tr(key)
	var pos := _press_screen + Vector2(-TIP_W * 0.5, TIP_OFFSET_Y)
	# 视口边缘钳制（说明条永远完整可见）
	var vp := c.get_viewport_rect().size
	pos.x = clampf(pos.x, 8.0, vp.x - TIP_W - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - 72.0)
	var rect := Rect2(pos, Vector2(TIP_W, 58.0))
	c.draw_rect(rect, COL_TIP_BG, true)
	c.draw_rect(rect, Color(COL_STATE, 0.5), false, 1.0)
	c.draw_multiline_string(font, pos + Vector2(10.0, 20.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, TIP_W - 20.0, 12, 3, COL_TEXT)


## 内部画布：全屏 Control，仅代理 _draw 回主类（激活期间才 visible）
class WheelCanvas extends Control:
	var wheel: CommandWheel = null

	func _draw() -> void:
		if wheel:
			wheel._draw_wheel(self)
