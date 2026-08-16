class_name XpGainVfx
extends Control

## 生存模式经验表现层（终端/Y2K 极简风，全部收束在底部经验条附近）：
##   - 击杀：小号琥珀"+N"在条上方淡入，向下"沉入"经验条后消失（不上浮、不横跨屏幕）
##
## 升级表现由 BottomExperiencePanel 逐板反色负责；这里不再绘制 LEVEL UP 弹字。
## 美术对齐：文字使用琥珀色并带极淡 CRT 辉光（多次偏移绘制）。
## 纯表现层，不读写游戏状态。挂在 SurvivorHUD（CanvasLayer）下，用屏幕坐标 _draw。
##
## 性能：自管理数组，空闲 set_process(false)；仅在动画期间 queue_redraw；无 _process 全场扫描。

# 由 SurvivorHUD._layout_ui 每帧写入的经验条屏幕矩形（本节点据此定位一切）
var bar_rect: Rect2 = Rect2()

# ── "+N" 掉落数字 ──
const GAIN_DURATION := 0.55        ## 单个数字生命周期（秒）
const GAIN_MAX := 20               ## 在场数字上限（防刷屏/bench）
const GAIN_FONT_SIZE := 13
const GAIN_RISE_ABOVE := 13.0      ## 起手在条顶之上的像素（随后向下沉入）
const GAIN_SLOTS := 5              ## 横向错开槽位数（连杀不重叠）
const GLOW_COLOR := Color(1.0, 0.85, 0.45)   ## 琥珀（略偏亮，作辉光/文字）

## 每项 {amount:int, t:float, slot:int}
var _gains: Array = []
var _gain_counter: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(false)


## 击杀掉落经验：仅传数值，落点固定在经验条上。
func add_gain(amount: int) -> void:
	if amount <= 0 or _gains.size() >= GAIN_MAX:
		return
	_gains.append({"amount": amount, "t": 0.0, "slot": _gain_counter % GAIN_SLOTS})
	_gain_counter += 1
	set_process(true)


func _process(delta: float) -> void:
	var active := false

	var i := _gains.size() - 1
	while i >= 0:
		_gains[i]["t"] += delta / GAIN_DURATION
		if _gains[i]["t"] >= 1.0:
			_gains.remove_at(i)
		else:
			active = true
		i -= 1

	if active:
		queue_redraw()
	else:
		queue_redraw()   # 最后一帧清空残影
		set_process(false)


func _draw() -> void:
	if bar_rect.size.x <= 0.0:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	_draw_gains(font)


func _draw_gains(font: Font) -> void:
	if _gains.is_empty():
		return
	var cx := bar_rect.position.x + bar_rect.size.x * 0.5
	var top := bar_rect.position.y
	for g in _gains:
		var t: float = g["t"]
		var txt := "+%d" % int(g["amount"])
		# 横向错开：以条中心为基准，槽位左右铺开
		var slot_off := (float(g["slot"]) - float(GAIN_SLOTS - 1) * 0.5) * 22.0
		# 纵向：条顶上方 GAIN_RISE_ABOVE → 沉入条内约 40% 高度（向下，不上浮）
		var ease := 1.0 - (1.0 - t) * (1.0 - t)   # ease-out：入条时减速
		var y := lerpf(top - GAIN_RISE_ABOVE, top + bar_rect.size.y * 0.4, ease)
		# 透明度：快速淡入（前 12%）→ 后 45% 淡出
		var a := 1.0
		if t < 0.12:
			a = t / 0.12
		elif t > 0.55:
			a = 1.0 - (t - 0.55) / 0.45
		a = clampf(a, 0.0, 1.0)
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, GAIN_FONT_SIZE)
		var origin := Vector2(cx + slot_off - sz.x * 0.5, y)
		_draw_glow_string(font, origin, txt, GAIN_FONT_SIZE, GLOW_COLOR, a)


## 极淡 CRT 辉光：先叠几笔低透明偏移，再压一笔清晰文字。
func _draw_glow_string(font: Font, origin: Vector2, txt: String,
		font_size: int, col: Color, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var glow := Color(col.r, col.g, col.b, alpha * 0.28)
	for off in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		font.draw_string(get_canvas_item(), origin + off, txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow)
	font.draw_string(get_canvas_item(), origin, txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col.r, col.g, col.b, alpha))
