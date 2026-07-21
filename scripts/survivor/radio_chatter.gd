class_name RadioChatter
extends CanvasLayer

## 无线电通讯系统（spec radio-chatter）
##
## 屏幕上方一条带呼号的台词 + 一声电台底噪。核心契约：
##   1. 一次只显示一条，【绝不打断】正在播的那条（用户硬需求）。
##   2. 权重只影响排队顺序与满队淘汰，不影响打断。
##   3. 入队即把说话人快照成【字符串 + Color】，绝不持有 Aircraft 引用 —— 说话人
##      随后阵亡/queue_free 也不会留下悬垂引用（kill feed 早期踩过这个坑）。
##   4. 唯一的 _process 是 O(1) 计时器，不做任何全场扫描（性能守则第 2/4 条）。
##
## ★ 台词 / 权重 / 冷却 / 概率全部住在 resources/chatter/radio_chatter.json，
##   本文件不含任何可调数值 —— 调手感改 JSON，不用碰代码。
##
## 三层节流（spec §2.11），普通语音必须全部通过；剧情语音全部跳过：
##   ① 全局冷却  —— 任何一条普通语音播出后，全场普通语音静默 N 秒
##   ② 自身冷却  —— 同一冷却桶（如所有 RTS 回令共享 "ack" 桶）的最小间隔
##   ③ 概率骰    —— 过了冷却仍要掷骰，制造"偶尔才有人说话"的稀疏感

# ══════════════════════════════════════════════
#  常量（仅结构性，数值一律来自 JSON）
# ══════════════════════════════════════════════

const LAYER_INDEX := 19               ## 夹在 ZoneHint(18) 与升级 UI(20) 之间

const FADE_IN := 0.12
const FADE_OUT := 0.35

## 背景：左右淡出的柔和渐变带（不是硬边矩形）。中段最深，两端透明。
const BG_COLOR := Color(0.02, 0.03, 0.05, 0.66)
const BG_FADE_IN_AT := 0.26      ## 渐变从透明升到满不透明的位置（0=最左）
const BG_FADE_OUT_AT := 0.74     ## 开始向右淡出的位置

## 呼号在上、正文在下的两行结构（参考皇牌空战）
const NAME_FONT_SIZE := 13
const MSG_FONT_SIZE := 15
const OUTLINE_SIZE := 4
const LINE_SPACING := 2          ## 呼号与正文的行距
const PAD_H := 28                ## 左右内边距
const PAD_V := 9                 ## 上下内边距

## 正文两侧的无线电通话标记
const MSG_PREFIX := "<< "
const MSG_SUFFIX := " >>"

## 正文颜色 = 阵营色向白色靠拢的淡色（呼号保持纯阵营色，形成主次）
const MSG_WHITEN := 0.65

## 文本带占屏幕宽度的比例（居中）
const BAND_WIDTH_RATIO := 0.64

## 距屏幕顶端的距离：让开时间(28)/击杀(54)/云层(74)/BOSS 面板(78)/ZoneHint(70~110)
const TOP_MARGIN := 118.0

## 布局在设置文本后需要等容器解算宽度才能得出换行高度；
## 这几帧被 FADE_IN（0.12s ≈ 7 帧）盖住，看不出跳变。
const RELAYOUT_FRAMES := 2

const SFX_RADIO_BEEP := "radio_beep"

enum State { IDLE, SPEAKING, GAP }

# ══════════════════════════════════════════════
#  运行时状态
# ══════════════════════════════════════════════

var lines := ChatterLines.new()

var _queue: Array[Dictionary] = []
var _cooldowns: Dictionary = {}        ## 冷却桶名 → 剩余冷却秒
var _global_cooldown: float = 0.0      ## 全局普通语音冷却剩余秒（剧情语音不受此限）
var _state: int = State.IDLE
var _timer: float = 0.0
var _clock: float = 0.0                ## 本节点存活时长，用于 stale 判定
var _current: Dictionary = {}

var _panel: PanelContainer     ## 渐变背景 + 内边距，高度随正文换行自动增长
var _vbox: VBoxContainer
var _name_label: Label         ## 呼号（纯阵营色）
var _msg_label: Label          ## 正文（阵营色淡化，自动换行）
var _relayout_countdown: int = 0

## 敌方累计损失（spec §2.6），由 notify_enemy_loss() 累加
var _enemy_losses: int = 0
var _attrition_milestone: int = 0      ## 已触发过的最高 12 倍数

func _ready() -> void:
	layer = LAYER_INDEX
	# 演出期间世界 hard_pause，但台词泵必须继续跑 —— 否则 Wraith 登场的三句对话
	# 全部积压到演出结束后才连播（审计实锤 2026-07-20）。副作用：Tab/升级暂停期间
	# ambient 也会照常播出与过期淘汰，这是可接受的（无线电本就是"环境音"性质）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_panel = PanelContainer.new()
	# 宽度按比例居中；anchor_bottom = anchor_top → 高度完全由 offset_bottom 控制，
	# 便于按正文实际换行行数逐条重算（见 _relayout）。
	var side := (1.0 - BAND_WIDTH_RATIO) * 0.5
	_panel.anchor_left = side
	_panel.anchor_right = 1.0 - side
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_top = TOP_MARGIN
	_panel.offset_bottom = TOP_MARGIN + 40.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _make_gradient_style())
	_panel.visible = false
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", LINE_SPACING)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_vbox)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_name_label)

	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_label.add_theme_font_size_override("font_size", MSG_FONT_SIZE)
	_msg_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	_msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_msg_label)

## 左右淡出的渐变底：两端透明 → 中段 BG_COLOR。
## 用 GradientTexture2D 而非 shader / 外部贴图 —— 自包含，无素材依赖。
func _make_gradient_style() -> StyleBoxTexture:
	var clear := Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, BG_FADE_IN_AT, BG_FADE_OUT_AT, 1.0])
	grad.colors = PackedColorArray([clear, BG_COLOR, BG_COLOR, clear])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 1
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)   # 水平渐变

	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.content_margin_left = PAD_H
	sb.content_margin_right = PAD_H
	sb.content_margin_top = PAD_V
	sb.content_margin_bottom = PAD_V
	return sb

## 按正文实际换行后的高度重算背景带高度（一条台词只做一次，不是每帧）
func _relayout() -> void:
	if _panel == null or _vbox == null:
		return
	var h: float = _vbox.get_combined_minimum_size().y + PAD_V * 2.0
	_panel.offset_bottom = _panel.offset_top + h

# ══════════════════════════════════════════════
#  公开入口
# ══════════════════════════════════════════════

## 最底层入口：文本已解析完毕。返回是否成功入队。
## trigger 决定分类/权重/冷却/概率，全部查 JSON（spec §2.9~§2.11）。
func say_text(trigger: String, speaker: String, color: Color, text: String) -> bool:
	if text == "":
		return false

	var scripted := ChatterLines.is_scripted(trigger)

	# 演出期间压制 ambient：scripted 照常放行，闲聊一律拒收，
	# 免得积压的喊话把演出台词挤到演出结束之后才出声
	if _ambient_suppressed and not scripted:
		return false

	# ── 三层节流：剧情语音（scripted）全部跳过，必定入队 ──
	if not scripted:
		# ① 全局冷却：任何一条普通语音播出后，全场普通语音静默一段时间
		if _global_cooldown > 0.0:
			return false
		# ② 自身冷却（按冷却桶，例如所有 RTS 回令共享 "ack" 桶）
		var bucket := ChatterLines.cooldown_group_of(trigger)
		if float(_cooldowns.get(bucket, 0.0)) > 0.0:
			return false
		# ③ 概率骰：过了冷却也不一定说，制造"偶尔才有人说话"的稀疏感。
		#    掷骰失败【不起冷却】—— 否则一次失败要闷掉整个冷却窗口。
		var chance := ChatterLines.chance_of(trigger)
		if chance < 1.0 and randf() >= chance:
			return false

	var entry := {
		"trigger": trigger,
		"scripted": scripted,
		"speaker": speaker if speaker != "" else "UNKNOWN",
		"color": color,
		"text": text,
		"weight": ChatterLines.weight_of(trigger),
		"at": _clock,
		# 演出台词的编排时长（0 = 走 line_duration 公式）。入队即快照，
		# 与"绝不持有 Aircraft 引用"同样的理由：出声时刻不确定，覆写值必须跟着条目走
		"dur": _dur_override,
	}
	_dur_override = 0.0   # 一次性：只作用于紧接的这一条

	var qmax := ChatterLines.queue_max()
	if _queue.size() >= qmax:
		# 满队：找权重最低者（同权重取最早入队者），新条目更高才顶掉它
		var worst_i := 0
		for i in range(1, _queue.size()):
			if int(_queue[i]["weight"]) < int(_queue[worst_i]["weight"]):
				worst_i = i
		if int(entry["weight"]) <= int(_queue[worst_i]["weight"]):
			return false
		_queue.remove_at(worst_i)

	_queue.append(entry)

	# 冷却在【成功入队】时起算（不是播出时）：防止一秒内 10 次击杀塞满队列。
	# 剧情语音不占用也不重置任何冷却 —— 它不属于"普通语音"的节流账本。
	if not scripted:
		_global_cooldown = ChatterLines.global_ambient_cooldown()
		var cool := ChatterLines.cooldown_of(trigger)
		if cool > 0.0:
			_cooldowns[ChatterLines.cooldown_group_of(trigger)] = cool
	return true

## 按 trigger 选一条台词说。fmt_args 非空时对 tr 结果做 % 格式化。
func say(trigger: String, speaker: String, color: Color, fmt_args: Array = []) -> bool:
	var key := lines.pick(trigger)
	if key == "":
		return false
	var text := tr(key)
	if not fmt_args.is_empty():
		text = _safe_format(text, fmt_args)
	return say_text(trigger, speaker, color, text)

## 说话人是一个战斗单位：呼号与阵营色从单位解析（spec §3.2）。
func say_unit(trigger: String, unit: Object, fmt_args: Array = []) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return say(trigger, speaker_name_of(unit), color_of(unit), fmt_args)

## BOSS 登场/交战序列：多条台词依次入队，构成一段队内对话（spec §3.3）。
## 返回实际入队条数。
## 演出台词时长覆写（spec ui-transition §2.8.2）。
## >0 时下一条入队的台词用该时长，绕开 line_duration() 的 2.6s 封底。
## ⚠ 仅演出可用 —— ambient 喊话必须保留封底，那是战斗中分心时的可读性下限
var _dur_override: float = 0.0
## ambient 压制（演出期间）：scripted 照常，ambient 一律拒收
var _ambient_suppressed: bool = false

func set_duration_override(sec: float) -> void:
	_dur_override = maxf(sec, 0.0)

## 演出期间压制 ambient 喊话。开启时顺带清空队列里尚未播出的 ambient，
## 否则积压的闲聊会把演出台词挤到演出结束后才出声
func suppress_ambient(on: bool) -> void:
	_ambient_suppressed = on
	if on:
		var kept: Array[Dictionary] = []
		for e in _queue:
			if ChatterLines.is_scripted(String(e.get("trigger", ""))):
				kept.append(e)
		_queue = kept

func is_ambient_suppressed() -> bool:
	return _ambient_suppressed

func say_boss_sequence(boss_id: String, phase: String, callsign_prefix: String) -> int:
	var seq := ChatterLines.boss_sequence(boss_id, phase)
	var prefix := callsign_prefix if callsign_prefix != "" else "BOSS"
	var trigger := "boss_spawn" if phase == "spawn" else "boss_engage"
	var n := 0
	for item in seq:
		var speaker := "%s-%02d" % [prefix, int(item.get("slot", 0)) + 1]
		var text := tr(String(item.get("key", "")))
		if say_text(trigger, speaker, GameConstants.COL_ENEMY_ELITE, text):
			n += 1
	return n

## 敌方损失计数入口（spec §2.6）。每跨过一个 12 的倍数触发一次哀嚎。
func notify_enemy_loss() -> void:
	_enemy_losses += 1
	var milestone := (_enemy_losses / 12) * 12
	if milestone <= _attrition_milestone or milestone == 0:
		return
	_attrition_milestone = milestone
	say(ChatterLines.attrition_trigger(_enemy_losses),
		tr("RADIO_SPEAKER_ENEMY_COMMAND"), GameConstants.COL_ENEMY_REGULAR)

# ══════════════════════════════════════════════
#  说话人解析（spec §3.2）
# ══════════════════════════════════════════════

func speaker_name_of(unit: Object) -> String:
	if unit == null or not is_instance_valid(unit):
		return "UNKNOWN"
	if "callsign" in unit and String(unit.callsign) != "":
		return String(unit.callsign)
	return "UNKNOWN"

func color_of(unit: Object) -> Color:
	if unit == null or not is_instance_valid(unit):
		return GameConstants.COL_ENEMY_REGULAR
	var t: int = int(unit.team) if "team" in unit else 1
	return color_for_team(t, _is_elite(unit))

static func color_for_team(team: int, elite: bool = false) -> Color:
	match team:
		0:
			return GameConstants.COL_FRIEND_PLAYER
		2:
			return GameConstants.COL_FRIEND_ALLY
		_:
			return GameConstants.COL_ENEMY_ELITE if elite else GameConstants.COL_ENEMY_REGULAR

func _is_elite(unit: Object) -> bool:
	if unit is Node:
		var n := unit as Node
		if n.has_meta("category") and String(n.get_meta("category")) == "boss":
			return true
		if n.has_meta("boss_intro"):
			return true
	return false

# ══════════════════════════════════════════════
#  主循环（O(1)，无全场扫描）
# ══════════════════════════════════════════════

func _process(delta: float) -> void:
	_clock += delta
	_tick_cooldowns(delta)

	match _state:
		State.SPEAKING:
			_timer -= delta
			# 容器解算完宽度后才知道正文换了几行 → 此时才定得下背景带高度
			if _relayout_countdown > 0:
				_relayout_countdown -= 1
				if _relayout_countdown == 0:
					_relayout()
			_apply_alpha()
			if _timer <= 0.0:
				_state = State.GAP
				_timer = ChatterLines.line_gap()
				_panel.visible = false
				_current = {}
		State.GAP:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE
				_pump()
		State.IDLE:
			_pump()

func _tick_cooldowns(delta: float) -> void:
	if _global_cooldown > 0.0:
		_global_cooldown = maxf(0.0, _global_cooldown - delta)
	if _cooldowns.is_empty():
		return
	for k in _cooldowns.keys():
		var v: float = _cooldowns[k] - delta
		if v <= 0.0:
			_cooldowns.erase(k)
		else:
			_cooldowns[k] = v

## 从队列取下一条开播。过期条目丢弃后继续取（while，非递归）。
func _pump() -> void:
	while not _queue.is_empty():
		var idx := _best_index()
		var entry: Dictionary = _queue[idx]
		_queue.remove_at(idx)
		# 剧情语音豁免过期：BOSS 登场是一次性入队的多条序列，最后一条排到队尾时
		# 早已超过阈值 —— 按过期丢会砍掉挑衅的收尾句。过期机制只针对反应式战况播报。
		if not bool(entry.get("scripted", false)) \
				and _clock - float(entry["at"]) > ChatterLines.queue_stale_sec():
			continue   # 过期战况即噪音，静默丢弃
		_begin(entry)
		return

## 权重最高者；同权重取最早入队者
func _best_index() -> int:
	var best := 0
	for i in range(1, _queue.size()):
		var a: Dictionary = _queue[i]
		var b: Dictionary = _queue[best]
		if int(a["weight"]) > int(b["weight"]):
			best = i
		elif int(a["weight"]) == int(b["weight"]) and float(a["at"]) < float(b["at"]):
			best = i
	return best

func _begin(entry: Dictionary) -> void:
	_current = entry
	_state = State.SPEAKING
	var text := String(entry["text"])
	# 演出台词用编排时长；ambient 走公式（含 2.6s 可读性封底）
	var override_dur: float = float(entry.get("dur", 0.0))
	_timer = override_dur if override_dur > 0.0 else line_duration(text)

	var faction: Color = entry["color"]
	_name_label.text = String(entry["speaker"])
	_name_label.add_theme_color_override("font_color", faction)
	# 正文淡化：呼号是纯阵营色，正文向白靠拢 → 一眼分出"谁在说"和"说了什么"
	_msg_label.text = "%s%s%s" % [MSG_PREFIX, text, MSG_SUFFIX]
	_msg_label.add_theme_color_override("font_color", faction.lerp(Color.WHITE, MSG_WHITEN))

	_panel.visible = true
	_relayout_countdown = RELAYOUT_FRAMES   # 等容器解算宽度后按换行行数定高
	_apply_alpha()
	AudioManager.play_radio(SFX_RADIO_BEEP)

## 显示时长（spec §2.2）
static func line_duration(text: String) -> float:
	var base := ChatterLines.duration_base()
	return clampf(base + ChatterLines.duration_per_char() * text.length(),
		base, ChatterLines.duration_max())

func _apply_alpha() -> void:
	if _current.is_empty():
		return
	var total: float = line_duration(String(_current["text"]))
	var elapsed: float = total - _timer
	var a := 1.0
	if elapsed < FADE_IN:
		a = elapsed / FADE_IN
	elif _timer < FADE_OUT:
		a = _timer / FADE_OUT
	_panel.modulate = Color(1, 1, 1, clampf(a, 0.0, 1.0))

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

## 占位符数量与 args 不匹配时 % 会在运行时崩（见 reference/i18n.md 已知风险）。
## 台词是纯氛围输出，绝不值得为它崩一局 —— 格式化失败就退回未格式化的原文。
func _safe_format(text: String, args: Array) -> String:
	if not text.contains("%"):
		return text
	var out: String = text % args   # Array 形式对单参/多参都成立
	return out if out != "" else text

# ── 无头测试用只读视图（不参与游戏逻辑）──
func debug_queue_size() -> int:
	return _queue.size()

func debug_current_text() -> String:
	return String(_current.get("text", ""))

func debug_current_speaker() -> String:
	return String(_current.get("speaker", ""))

func debug_current_color() -> Color:
	return _current.get("color", Color.WHITE)

func debug_state() -> int:
	return _state

## 以下三个读的是【实际 Label】而非队列条目，用于验证呈现层接线没断
func debug_name_label_text() -> String:
	return _name_label.text if _name_label else ""

func debug_msg_label_text() -> String:
	return _msg_label.text if _msg_label else ""

func debug_msg_label_color() -> Color:
	if _msg_label == null:
		return Color.WHITE
	return _msg_label.get_theme_color("font_color")

func debug_name_label_color() -> Color:
	if _name_label == null:
		return Color.WHITE
	return _name_label.get_theme_color("font_color")

func debug_cooldown(bucket: String) -> float:
	return _cooldowns.get(bucket, 0.0)

func debug_global_cooldown() -> float:
	return _global_cooldown

## 清空全部节流账本。仅供测试里"只想验队列结构、不想被节流干扰"的用例使用。
func debug_clear_throttle() -> void:
	_global_cooldown = 0.0
	_cooldowns.clear()

func debug_set_cooldown(bucket: String, sec: float) -> void:
	if sec > 0.0:
		_cooldowns[bucket] = sec
	else:
		_cooldowns.erase(bucket)

## 清空待播队列（测试里做概率采样时用，避免队列满导致假阴性）
func debug_drain_queue() -> void:
	_queue.clear()
