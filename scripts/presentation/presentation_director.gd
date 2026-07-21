extends Node

## 表演导演（autoload `Presentation`）—— spec ui-transition
##
## 职责：序列运行 + 通道分发 + 遮罩层持有 + 热重载。
## 阶段 1 通道：time / camera / overlay / panel
## 阶段 2 追加：stage / actor / radio
##
## ⚠ 性能：IDLE 时 set_process(false)，零开销。不做任何全场扫描。
## ⚠ 时序：process_mode = ALWAYS，保证 hard_pause 期间仍收到 _process；
##        且一律用 unscaled delta 推进（§3.2），否则时间缩到 0.05 后转场会慢 20 倍。

signal sequence_finished(seq_name: String)

const SEQ_PATH := "res://resources/presentation/sequences.json"
## 压暗层的【默认】高度：压世界/HUD(10)/战术图(15)，留战区提示(18)/无线电(19)/面板(20) 在亮处。
## ⚠ 但面板自身若低于此值（战术图 = 15），固定 16 会把面板一起压黑 ——
##   故实际高度取 min(DIM_LAYER, panel.layer - 1)，见 _place_dim_below()
const DIM_LAYER := 16
const FX_LAYER := 25      ## 闪白/渐黑，高于全部面板

enum State { IDLE, PLAYING, SETTLED }

var state: int = State.IDLE

var time: TimeAuthority
var _seq_defs: Dictionary = {}
var _player: SequencePlayer

# ── 遮罩 ──
var _dim_layer: CanvasLayer
var _dim_rect: ColorRect
var _fx_layer: CanvasLayer
var _fx_rect: ColorRect

# ── 绑定 ──
var _camera: CameraController = null
var _panel_node: CanvasLayer = null          ## 当前 present 的面板
var _panel_elements: Array[Control] = []
var _panel_hide_on_finish: bool = false
var _hide_target = null   ## dismiss 跑完要隐藏的节点（缺省=面板本身）。
						  ## ⚠ 刻意无类型：既可能是 CanvasLayer（面板本身）也可能是
						  ## CanvasItem（面板子节点），俩在继承树上不搭边，只共享 visible 属性

# ── 演出（阶段 2）──
var _radio: Node = null                      ## RadioChatter
var stage: StageIsolator
var cast: CinematicCast
var _cine_ctx: Dictionary = {}               ## anchor / cp / inbound / extra_layers / owner
var _cine_active: bool = false

# ── 面板元素基线（stagger 用）──
const PANEL_SCALE_FROM := 0.92
const PANEL_SCALE_OUT := 0.96

# ── 各通道的插值起点（step 首帧快照，支持"从当前值续插"）──
var _cam_zoom_from: float = 1.0
var _dim_from: float = 0.0
var _fx_from: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	time = TimeAuthority.new(get_tree())
	_player = SequencePlayer.new()
	stage = StageIsolator.new()
	cast = CinematicCast.new()
	_build_overlays()
	reload_sequences()
	set_process(false)


func _build_overlays() -> void:
	_dim_layer = CanvasLayer.new()
	_dim_layer.layer = DIM_LAYER
	add_child(_dim_layer)
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rect.visible = false
	_dim_layer.add_child(_dim_rect)

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = FX_LAYER
	add_child(_fx_layer)
	_fx_rect = ColorRect.new()
	_fx_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.visible = false
	_fx_layer.add_child(_fx_rect)


# ============================================================
#  序列加载 / 热重载
# ============================================================

func reload_sequences() -> bool:
	var f := FileAccess.open(SEQ_PATH, FileAccess.READ)
	if f == null:
		push_error("Presentation: 打不开 %s" % SEQ_PATH)
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Presentation: %s 不是合法 JSON 对象" % SEQ_PATH)
		return false
	_seq_defs = parsed
	return true

## F8：重读 JSON 并重放当前序列。仅编辑器模式注册（见 _unhandled_input）
func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("editor"):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		var last := _player.seq_name
		if reload_sequences():
			print("[Presentation] 序列已热重载：", _seq_defs.keys())
			if last != "":
				debug_replay(last)
		get_viewport().set_input_as_handled()

func has_sequence(seq_name: String) -> bool:
	return _seq_defs.has(seq_name)

func debug_replay(seq_name: String) -> void:
	if not _seq_defs.has(seq_name):
		push_warning("Presentation: 未知序列 '%s'" % seq_name)
		return
	_play(seq_name)


# ============================================================
#  绑定
# ============================================================

func bind_camera(cam: CameraController) -> void:
	_camera = cam

func unbind_camera() -> void:
	if _camera:
		_camera.cine_reset()
	_camera = null

func bind_radio(r: Node) -> void:
	_radio = r


# ============================================================
#  演出（cinematic）
# ============================================================

## 播一段演出。
## ctx 必填：owner（GameEvent，演员指令的所有权持有者）、actors（Array[Aircraft]）、
##          anchor（集结点）、player_pos（用于反推进场方向）
## 选填：extra_layers（地图/HUD 等要一起压暗的 CanvasItem）
##
## ⚠ 无 owner 则【拒绝】演出：actor 通道会往 AI 写指令，没有所有权就没有 cleanup 兜底，
##   一旦漏清理四架飞机会永远停在免战脚本模式且不报错（spec §3.3）
func play_cinematic(seq_name: String, ctx: Dictionary) -> bool:
	var owner = ctx.get("owner")
	var actors: Array = ctx.get("actors", [])
	if owner == null or not owner.has_method("set_directive"):
		push_error("Presentation: 演出 '%s' 缺 owner(GameEvent)，拒绝播放" % seq_name)
		return false
	if actors.is_empty():
		push_error("Presentation: 演出 '%s' 无演员，拒绝播放" % seq_name)
		return false
	_cine_ctx = ctx
	_cine_active = true
	cast.bind(actors, owner)
	if _radio and _radio.has_method("suppress_ambient"):
		_radio.suppress_ambient(true)
	_play(seq_name)
	return true

## 演出收尾：释放演员指令、还原尾迹/舞台/镜头、解除 ambient 压制
func _end_cinematic() -> void:
	if not _cine_active:
		return
	_cine_active = false
	var extra: Array = _cine_ctx.get("extra_layers", [])
	stage.force_restore(extra)
	cast.release()
	if _radio and _radio.has_method("suppress_ambient"):
		_radio.suppress_ambient(false)
	if _camera:
		_camera.cine_reset()
	time.hard_pause(false)
	_cine_ctx.clear()


# ============================================================
#  面板出入场（present / dismiss）
# ============================================================

## 显示面板并播入场序列。
## 调用方只负责把内容填好（populate），出场交给导演。
func present(panel: CanvasLayer, seq_name: String) -> void:
	if panel == null:
		return
	_panel_node = panel
	_panel_hide_on_finish = false
	# ⚠ 顺序要紧：必须【先】把元素压到 alpha 0 再 visible = true。
	#   反过来的话，等 size 的那一帧面板会以全不透明闪一下——正是本系统要消灭的"突兀"
	_bind_panel_elements(panel)
	for c in _panel_elements:
		c.modulate.a = 0.0
		c.scale = Vector2(PANEL_SCALE_FROM, PANEL_SCALE_FROM)
	_place_dim_below(panel)
	panel.visible = true
	# 等一帧让 Container 算出 size —— 否则 pivot_offset = size*0.5 会拿到 Vector2.ZERO（§3.5）。
	# 这一帧元素已是全透明，看不见
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	for c in _panel_elements:
		if is_instance_valid(c):
			c.pivot_offset = c.size * 0.5
	_play(seq_name)

## 播退场序列，跑完把面板隐藏。
## ⚠ 调用方必须在调用本函数【之前】完成全部游戏状态恢复（升级生效 / 解除暂停标志 /
##    鼠标状态重置）。导演只负责视觉，绝不延后任何玩法状态变更（守 Litmus #2）。
## hide_node：序列跑完后要隐藏的节点，缺省是面板本身。
## 传子节点用于"CanvasLayer 还有别的东西要继续画"的面板（如 boundary_ui 的越界警告）
func dismiss(panel: CanvasLayer, seq_name: String, hide_node: CanvasItem = null) -> void:
	if panel == null:
		return
	_panel_node = panel
	_place_dim_below(panel)
	_hide_target = hide_node if hide_node != null else panel
	_panel_hide_on_finish = true
	_bind_panel_elements(panel)
	_play(seq_name)

## 把压暗层挪到被展示面板的正下方，且不高于 DIM_LAYER。
## 战术图在 15：固定 16 会盖住它自己（playtest 实测"战术地图变得很黑"）；
## 升级/进化/边界菜单在 20：取 16，无线电(19) 与战区提示(18) 仍留在亮处
func _place_dim_below(panel: CanvasLayer) -> void:
	if _dim_layer == null or panel == null:
		return
	_dim_layer.layer = mini(DIM_LAYER, maxi(panel.layer - 1, 1))

func _bind_panel_elements(panel: CanvasLayer) -> void:
	_panel_elements.clear()
	if panel.has_method("get_transition_elements"):
		var arr: Array = panel.get_transition_elements()
		for e in arr:
			if e is Control and is_instance_valid(e):
				_panel_elements.append(e)
	if _panel_elements.is_empty():
		# 退化：没实现协议的面板整体淡入（取第一个 Control 子节点）
		for c in panel.get_children():
			if c is Control:
				_panel_elements.append(c)
				break


# ============================================================
#  播放主循环
# ============================================================

func _play(seq_name: String) -> void:
	if not _seq_defs.has(seq_name):
		push_warning("Presentation: 未知序列 '%s'，跳过" % seq_name)
		_finish()
		return
	_player.load_sequence(seq_name, _seq_defs[seq_name])
	state = State.PLAYING
	set_process(true)

func _process(delta: float) -> void:
	# unscaled 还原：_process 收到的 delta 已被 Engine.time_scale 缩放（§3.2）
	var ud: float = delta / maxf(Engine.time_scale, 0.001)

	if state == State.PLAYING:
		if _player.is_timed_out():
			push_warning("Presentation: 序列 '%s' 超时，强制收尾" % _player.seq_name)
			for tk in _player.force_finish():
				_apply_tick(tk)
			_finish()
			return
		for tk in _player.advance(ud):
			_apply_tick(tk)
		if _player.is_done():
			_finish()
			return

	time.tick(ud)

	# ⚠ 暂停期镜头泵（审计实锤 2026-07-20）：camera.zoom 的实际应用在
	# CameraController.update_zoom，由 survivor_mode._process 驱动 —— 而 hard_pause
	# 期间 survivor_mode 整个被冻结。不在这里代泵的话，演出中段的推近（wraith 4.2s
	# zoom ×1.3）和升级急刹的 zoom punch 只改了 cine_zoom_mult、永远不落到镜头上。
	# 只在世界停/慢时代泵，正常速度下仍由 survivor_mode 泵（避免双泵双倍 lerp）
	if _camera and (get_tree().paused or Engine.time_scale < 0.999):
		_camera.update_zoom(ud)
		_camera.cine_follow_tick(ud)   # 演出期间跟住 cine_target（长机），不是定点看战区

	# 混合跑完且序列已结束 → 彻底停机
	if state != State.PLAYING and not time.is_blending():
		set_process(false)

func _finish() -> void:
	state = State.SETTLED
	if _panel_hide_on_finish and _hide_target and is_instance_valid(_hide_target):
		_hide_target.visible = false
		_panel_hide_on_finish = false
		_hide_target = null
	# 演出跑完/超时都要收尾。序列里若已有 actor.release 步骤，这里是幂等的第二道闸
	if _cine_active:
		_end_cinematic()
	sequence_finished.emit(_player.seq_name)
	if not time.is_blending():
		set_process(false)


# ============================================================
#  通道分发
# ============================================================

func _apply_tick(tk: SequencePlayer.Tick) -> void:
	var ch := String(tk.step.get("ch", ""))
	match ch:
		"time": _ch_time(tk)
		"camera": _ch_camera(tk)
		"overlay": _ch_overlay(tk)
		"panel": _ch_panel(tk)
		"stage": _ch_stage(tk)
		"audio": _ch_audio(tk)
		"actor": _ch_actor(tk)
		"radio": _ch_radio(tk)
		_:
			# 未知通道跳过但不中断整条序列——热重载写错 JSON 不能把游戏卡死
			if tk.first:
				push_warning("Presentation: 未知通道 '%s'" % ch)

func _ch_time(tk: SequencePlayer.Tick) -> void:
	if not tk.first:
		return
	var op := String(tk.step.get("op", ""))
	match op:
		"request":
			time.request(StringName(String(tk.step.get("id", "seq"))),
				float(tk.step.get("to", 1.0)),
				float(tk.step.get("dur", 0.0)))
		"release":
			time.release(StringName(String(tk.step.get("id", "seq"))),
				float(tk.step.get("dur", 0.0)))
		"pause":
			time.hard_pause(int(tk.step.get("to", 1)) != 0)
		_:
			push_warning("Presentation: time 通道未知 op '%s'" % op)

func _ch_camera(tk: SequencePlayer.Tick) -> void:
	if _camera == null:
		return
	var op := String(tk.step.get("op", ""))
	match op:
		"zoom":
			# 起点默认取"通道当前值"而非硬编码 1.0 —— 被打断时从当前值续插，不跳变（§3.1）
			if tk.first:
				_cam_zoom_from = float(tk.step.get("from", _camera.cine_zoom_mult))
			_camera.cine_zoom_mult = lerpf(_cam_zoom_from, float(tk.step.get("to", 1.0)), tk.t)
		"shake":
			if tk.first:
				_camera.cine_shake(float(tk.step.get("to", 0.5)))
		"cut_to":
			if tk.first:
				var pos: Vector2 = _cine_ctx.get("anchor", Vector2.ZERO)
				var lead = null
				# follow=true：切到长机身上并持续跟随（手感=空格跟随）。
				# playtest 实锤：定点看锚点 = 镜头盯着战区正中央的空气，飞机在画面外进场
				if bool(tk.step.get("follow", false)) and cast.is_bound():
					var live := cast.alive_actors()
					if not live.is_empty():
						lead = live[int(tk.step.get("actor", 0)) % live.size()]
						pos = lead.global_position
				_camera.cine_cut_to(pos, float(tk.step.get("zoom", 0.5)))
				_camera.cine_target = lead   # cine_cut_to 内部会清空，故必须在其后赋值
		"return_to_player":
			_camera.cine_return_to_player(tk.t)
		_:
			push_warning("Presentation: camera 通道未知 op '%s'" % op)

func _ch_overlay(tk: SequencePlayer.Tick) -> void:
	var op := String(tk.step.get("op", ""))
	match op:
		"dim":
			var from_a := float(tk.step.get("from", _dim_rect.color.a))
			if tk.first:
				_dim_from = from_a
				_dim_rect.visible = true
			var a: float = lerpf(_dim_from, float(tk.step.get("to", 0.0)), tk.t)
			_dim_rect.color = Color(0.0, 0.0, 0.0, a)
			if tk.last and a <= 0.001:
				_dim_rect.visible = false
		"flash":
			if tk.first:
				_fx_from = _fx_rect.color.a
				_fx_rect.visible = true
			var fa: float = lerpf(_fx_from, float(tk.step.get("to", 0.0)), tk.t)
			_fx_rect.color = Color(1.0, 1.0, 1.0, fa)
			if tk.last and fa <= 0.001:
				_fx_rect.visible = false
		_:
			push_warning("Presentation: overlay 通道未知 op '%s'" % op)

## 面板元素错开出入场。
## ⚠ 只动 scale 与 modulate ——【不动 position】。卡片是 HBoxContainer 的子节点，
##    Container 每帧 fit_child_in_rect 覆写子节点 position/size，位移会被吃掉（§2.3）
func _ch_panel(tk: SequencePlayer.Tick) -> void:
	if _panel_elements.is_empty():
		return
	var op := String(tk.step.get("op", ""))
	var stagger := float(tk.step.get("stagger", 0.0))
	var span := maxf(float(tk.step.get("dur", 0.0)), 0.001)     ## 整组跨度（SequencePlayer 用它计时）
	# 单元素时长。缺省回退到整组跨度——单元素面板下二者本就相等
	var elem_dur := maxf(float(tk.step.get("elem_dur", span)), 0.001)
	var ease_name := String(tk.step.get("ease", "linear"))
	var going_in := op == "stagger_in"
	if op != "stagger_in" and op != "stagger_out":
		push_warning("Presentation: panel 通道未知 op '%s'" % op)
		return

	# ⚠ 整组跨度必须 ≥ elem_dur + stagger*(n-1)，否则最后一个元素的进度跑不满，
	#   会永久停在半透明。JSON 里 dur 就是按这个公式算出来的
	var group_elapsed: float = tk.raw_t * span
	for i in range(_panel_elements.size()):
		var c := _panel_elements[i]
		if not is_instance_valid(c):
			continue
		var local_t: float = clampf((group_elapsed - stagger * i) / elem_dur, 0.0, 1.0)
		var e: float = EaseLib.apply(ease_name, local_t)
		if going_in:
			c.modulate.a = EaseLib.cubic_out(local_t)
			var s: float = lerpf(PANEL_SCALE_FROM, 1.0, e)
			c.scale = Vector2(s, s)
		else:
			c.modulate.a = 1.0 - EaseLib.cubic_in(local_t)
			var so: float = lerpf(1.0, PANEL_SCALE_OUT, e)
			c.scale = Vector2(so, so)


## 音频通道：演出配乐。BOSS 曲在演出开场即切 —— 配乐是铺垫的一部分，
## 大阵仗登场配日常巡航曲是气氛断档（playtest 反馈）。交战时的原切歌点由
## BossEncounterEvent 幂等守卫（current_music_id 比对），不会重启同一首
func _ch_audio(tk: SequencePlayer.Tick) -> void:
	if not tk.first:
		return
	match String(tk.step.get("op", "")):
		"boss_bgm":
			var fade := float(tk.step.get("fade", 2.0))
			var layers: Array = _cine_ctx.get("bgm_layers", [])
			var track := String(_cine_ctx.get("bgm_track", ""))
			if not layers.is_empty():
				AudioManager.play_layered_music(layers, fade, 0)
			elif track != "":
				AudioManager.crossfade_music(track, fade)
		_:
			push_warning("Presentation: audio 通道未知 op")

func _ch_stage(tk: SequencePlayer.Tick) -> void:
	var extra: Array = _cine_ctx.get("extra_layers", [])
	match String(tk.step.get("op", "")):
		"clear": stage.clear(_cine_ctx.get("actors", []), extra, tk.t)
		"restore": stage.restore(extra, tk.t)
		_: push_warning("Presentation: stage 通道未知 op")

## 演员通道。指令下发全部委托 cast → owner(GameEvent)，导演自己不持有 AIDirective
func _ch_actor(tk: SequencePlayer.Tick) -> void:
	if not cast.is_bound():
		return
	var s := tk.step
	var anchor: Vector2 = _cine_ctx.get("anchor", Vector2.ZERO)
	var inbound: Vector2 = _cine_ctx.get("inbound", Vector2.RIGHT)
	match String(s.get("op", "")):
		"trail_boost":
			if tk.first:
				cast.trail_boost()
		"trail_fade":
			cast.trail_fade(tk.t)
		"echelon_ingress":
			if tk.first:
				cast.echelon_ingress(anchor, inbound, s.get("offsets", []),
					float(s.get("alt_step", 0.0)), float(s.get("speed", 1600.0)),
					float(s.get("ingress_dist", 730.0)))
			# 逐机错开淡入：step 的 dur 就是淡入总跨度（= fade + stagger×(n−1)）
			cast.tick_ingress_fade(tk.raw_t * maxf(float(s.get("dur", 0.0)), 0.001),
				float(s.get("stagger", 0.35)), float(s.get("fade", 0.60)))
		"converge":
			if tk.first:
				cast.converge(_cine_ctx.get("cp", anchor), float(s.get("dur", 1.8)),
					float(s.get("arrive_radius", 80.0)))
		"cloak_vanish":
			# 演出专属视觉隐身（用户裁定）：不碰小队真隐身状态机，release 时解除
			cast.cloak_vanish(tk.t)
		"cloak_on_meet":
			# 交汇即隐身（用户分镜 v2）：贴上长机的瞬间各自淡出
			var span: float = maxf(float(s.get("dur", 0.0)), 0.001)
			cast.cloak_on_meet(tk.raw_t * span, span,
				float(s.get("radius", 140.0)), float(s.get("fade", 0.35)))
		"scatter":
			if tk.first:
				# 背向玩家（= inbound 方向）扇面散开，绝不朝玩家甩 —— 否则贴脸误触 ENGAGED
				cast.scatter(_cine_ctx.get("cp", anchor), inbound,
					float(s.get("fan_deg", 135.0)), float(s.get("dist", 2600.0)))
		"release":
			if tk.first:
				_end_cinematic()
		_:
			push_warning("Presentation: actor 通道未知 op")

## 无线电通道：演出持有台词的【编排权】，但渲染仍走 RadioChatter 的显示带 ——
## 绕过它自己画字幕会与 ambient 同屏叠字，且破坏"绝不打断"契约（spec §3.5）。
## ⚠ 发射后不管：这是入队时刻，不是保证出声时刻，演出时序不得依赖无线电准点
func _ch_radio(tk: SequencePlayer.Tick) -> void:
	if not tk.first or _radio == null or not is_instance_valid(_radio):
		return
	var s := tk.step
	var key := String(s.get("key", ""))
	if key == "":
		return
	var idx := int(s.get("actor", 0))
	var prefix := String(_cine_ctx.get("callsign_prefix", "BOSS"))
	var speaker := "%s-%02d" % [prefix, idx + 1]
	var dur := float(s.get("dur", 0.0))
	if dur > 0.0 and _radio.has_method("set_duration_override"):
		_radio.set_duration_override(dur)
	_radio.say_text("boss_spawn", speaker, GameConstants.COL_ENEMY_ELITE, tr(key))


# ============================================================
#  全清（场景切换 / run reset / 退出）
# ============================================================

## 三类泄漏的统一闸门：时间栈 / 遮罩 / 面板缩放。
## 漏掉任何一条，玩家都会卡在异常状态里（0.05 倍速 / 全屏变黑 / 面板永远半透明）
func clear_all() -> void:
	state = State.IDLE
	set_process(false)
	# 演出的三类泄漏（舞台隐形 / 演员卡在免战 / ambient 永久静音）先收
	if _cine_active:
		_end_cinematic()
	elif stage and stage.is_active():
		stage.force_restore(_cine_ctx.get("extra_layers", []))
	if time:
		time.clear_all()
	if _dim_rect:
		_dim_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		_dim_rect.visible = false
	if _dim_layer:
		_dim_layer.layer = DIM_LAYER
	if _fx_rect:
		_fx_rect.color = Color(1.0, 1.0, 1.0, 0.0)
		_fx_rect.visible = false
	for c in _panel_elements:
		if is_instance_valid(c):
			c.modulate.a = 1.0
			c.scale = Vector2.ONE
	_panel_elements.clear()
	_panel_node = null
	_hide_target = null
	_panel_hide_on_finish = false
	unbind_camera()

func _exit_tree() -> void:
	clear_all()
