extends RefCounted

## 表演导演系统回归（spec ui-transition）
## 覆盖：时间栈求解/配平 · 三类泄漏 · 序列时序与 step 边界 · 缓动端点 ·
##       unscaled 推进 · 坏 JSON 容错 · 超时收尾
## 运行：godot --headless --path . -- --bench=presentation（或 --bench=all）
##
## 说明：本测试【不启动 survivor_mode 场景】。TimeAuthority 与 SequencePlayer 都是纯
## RefCounted，可脱离引擎逐帧手动步进——时序因此完全确定，不受帧率影响。

const DT := 1.0 / 60.0
const AircraftSilhouetteCatalog := preload("res://scripts/aircraft_silhouette_catalog.gd")
const BossArrivalBannerScript := preload("res://scripts/ui/boss_arrival_banner.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 表演导演（时间栈/序列/缓动/泄漏） ════════")

	_test_ease_endpoints()
	_test_ease_back_overshoot()
	_test_time_stack_min_wins()
	_test_time_stack_same_id_overwrite()
	_test_time_release_returns_to_one()
	_test_time_blend_unscaled()
	_test_time_clear_all()
	_test_sequence_durations()
	_test_step_boundaries()
	_test_instant_step_fires_once()
	_test_unknown_channel_does_not_abort()
	_test_force_finish()
	_test_timeout_detection()
	_test_upgrade_sequences_wellformed()
	_test_wraith_sequence_wellformed()
	_test_simple_boss_sequences_wellformed()
	_test_boss_banner_contract()
	_test_converge_speed_solve()
	_test_dim_layer_placement()
	_test_arrival_seq_names_match_registry()
	_test_lock_visual_screen_scale()
	_test_compact_aircraft_labels()
	_test_presentation_label_refinements()
	_test_freed_aircraft_reference_safety()
	_test_incoming_missile_warning_rule()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ══════════════════════════════════════════════
#  1. 缓动（spec §2.5）
# ══════════════════════════════════════════════

func _test_ease_endpoints() -> void:
	for name in ["linear", "cubic_out", "cubic_in", "cubic_in_out", "expo_out", "back_out"]:
		_assert_near("ease.%s(0)" % name, EaseLib.apply(name, 0.0), 0.0)
		_assert_near("ease.%s(1)" % name, EaseLib.apply(name, 1.0), 1.0)
	# 未知曲线名回退 linear（热重载写错不该崩）
	_assert_near("ease.unknown→linear", EaseLib.apply("nope", 0.42), 0.42)

## back_out 必须真的过冲——这是"弹入"手感的来源
func _test_ease_back_overshoot() -> void:
	_assert_true("ease.back_out 过冲 >1", EaseLib.back_out(0.7) > 1.0)
	_assert_true("ease.back_out 峰值 <1.2", EaseLib.back_out(0.7) < 1.2)


# ══════════════════════════════════════════════
#  2. 时间栈（spec §2.2 / §3.8）
# ══════════════════════════════════════════════

func _new_time() -> TimeAuthority:
	return TimeAuthority.new(null)   # 不需要 SceneTree：本组不测 hard_pause

func _test_time_stack_min_wins() -> void:
	var t := _new_time()
	t.request(&"wheel", 0.3)
	t.request(&"upgrade", 0.05)
	_assert_near("time.min_wins", t.solve(), 0.05)
	# 释放小的 → 回到大的那档，而不是直接回 1.0
	t.release(&"upgrade")
	_assert_near("time.release_small→次小", t.solve(), 0.3)
	t.clear_all()

func _test_time_stack_same_id_overwrite() -> void:
	var t := _new_time()
	t.request(&"upgrade", 0.5)
	t.request(&"upgrade", 0.2)
	_assert_near("time.same_id 覆盖不叠加", t.solve(), 0.2)
	t.release(&"upgrade")
	_assert_near("time.same_id 一次释放即净空", t.solve(), 1.0)
	t.clear_all()

func _test_time_release_returns_to_one() -> void:
	var t := _new_time()
	t.request(&"a", 0.1)
	t.request(&"b", 0.4)
	t.release(&"a")
	t.release(&"b")
	_assert_near("time.栈空回 1.0", t.solve(), 1.0)
	_assert_near("time.Engine.time_scale 回 1.0", Engine.time_scale, 1.0)
	t.clear_all()

## 混合必须按 unscaled 时间推进：喂 unscaled delta 时，混合时长应与 time_scale 无关
func _test_time_blend_unscaled() -> void:
	var t := _new_time()
	t.request(&"upgrade", 0.05, 0.15)
	var steps := 0
	while t.is_blending() and steps < 600:
		t.tick(DT)
		steps += 1
	_assert_true("time.blend 在 ~0.15s 内收敛", steps <= 10 and steps >= 8)
	_assert_near("time.blend 终值精确", t.current_scale(), 0.05)
	t.clear_all()

## 泄漏防护：clear_all 必须让 Engine.time_scale 干净回 1.0
func _test_time_clear_all() -> void:
	var t := _new_time()
	t.request(&"upgrade", 0.05, 0.2)
	t.tick(DT)   # 混合到一半
	t.clear_all()
	_assert_near("leak.clear_all → time_scale 1.0", Engine.time_scale, 1.0)
	_assert_near("leak.clear_all → 栈空", t.solve(), 1.0)
	_assert_true("leak.clear_all → 无残留混合", not t.is_blending())


# ══════════════════════════════════════════════
#  3. 序列时序（spec §2.3 / §2.4 / §3.1）
# ══════════════════════════════════════════════

func _load_real_sequences() -> Dictionary:
	var f := FileAccess.open("res://resources/presentation/sequences.json", FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _test_sequence_durations() -> void:
	var defs := _load_real_sequences()
	_assert_true("seq.JSON 可解析", not defs.is_empty())
	if defs.is_empty():
		return
	var p := SequencePlayer.new()
	p.load_sequence("upgrade_in", defs.get("upgrade_in", {}))
	_assert_near("seq.upgrade_in 总时长 0.60", p.total_duration(), 0.60)
	p.load_sequence("upgrade_out", defs.get("upgrade_out", {}))
	_assert_near("seq.upgrade_out 总时长 0.30", p.total_duration(), 0.30)
	_test_stagger_span_invariant(defs)

## 错开动画的跨度不变式：dur ≥ elem_dur + stagger*(n-1)。
## 违反则最后一个元素的进度跑不满，会永久停在半透明——本项目已经踩过一次
func _test_stagger_span_invariant(defs: Dictionary) -> void:
	const PANEL_ELEMS := 5    ## 标题 + 最多 4 张卡（机体专属第四槽）
	for seq_name in defs.keys():
		if typeof(defs[seq_name]) != TYPE_DICTIONARY:
			continue
		for s in defs[seq_name].get("steps", []):
			if String(s.get("ch", "")) != "panel":
				continue
			var span := float(s.get("dur", 0.0))
			var elem := float(s.get("elem_dur", span))
			var stag := float(s.get("stagger", 0.0))
			var need: float = elem + stag * (PANEL_ELEMS - 1)
			_assert_true("stagger.%s 跨度足够（%.2f ≥ %.2f）" % [seq_name, span, need],
				span >= need - 0.001)

## step 必须在 at 激活、在 at+dur 恰好抵达终值
func _test_step_boundaries() -> void:
	var p := SequencePlayer.new()
	p.load_sequence("t", {"steps": [
		{"at": 0.10, "ch": "overlay", "op": "dim", "dur": 0.20, "ease": "linear"},
	]})
	# t=0.05：尚未激活
	p.advance(0.05)
	_assert_true("step.at 之前不激活", p.advance(0.0).is_empty())
	# 推到 0.15（step 内部进度 0.05/0.20 = 0.25）
	var ticks := p.advance(0.10)
	_assert_true("step.at 之后激活", ticks.size() == 1)
	if ticks.size() == 1:
		_assert_near("step.中段进度", ticks[0].raw_t, 0.25)
		_assert_true("step.首帧 first=true", ticks[0].first)
	# 推到终点
	var last: Variant = null
	for i in range(30):
		var arr := p.advance(DT)
		if arr.size() > 0:
			last = arr[0]
		if p.is_done():
			break
	_assert_true("step.抵达终点 last=true", last != null and last.last)
	_assert_near("step.终值 t=1.0", last.raw_t if last else -1.0, 1.0)

## 瞬时 step（无 dur）只发一次，且 t=1.0
func _test_instant_step_fires_once() -> void:
	var p := SequencePlayer.new()
	p.load_sequence("t", {"steps": [{"at": 0.05, "ch": "time", "op": "pause", "to": 1}]})
	p.advance(0.10)                       # 跨过 at
	var second := p.advance(DT)
	_assert_true("step.瞬时只发一次", second.is_empty())

## 坏数据容错：未知 ch/op 不该中断整条序列（SequencePlayer 层原样透传，由导演跳过）
func _test_unknown_channel_does_not_abort() -> void:
	var p := SequencePlayer.new()
	p.load_sequence("t", {"steps": [
		{"at": 0.00, "ch": "bogus_channel", "op": "nope"},
		{"at": 0.05, "ch": "overlay", "op": "dim", "dur": 0.10},
	]})
	var seen_overlay := false
	for i in range(30):
		for tk in p.advance(DT):
			if String(tk.step.get("ch", "")) == "overlay":
				seen_overlay = true
		if p.is_done():
			break
	_assert_true("seq.坏 step 之后的 step 仍执行", seen_overlay)
	_assert_true("seq.坏 step 序列仍能跑完", p.is_done())

## 超时/打断收尾：force_finish 把未完成的 step 全推到终点
func _test_force_finish() -> void:
	var p := SequencePlayer.new()
	p.load_sequence("t", {"steps": [
		{"at": 0.00, "ch": "overlay", "op": "dim", "dur": 1.00},
		{"at": 0.50, "ch": "camera", "op": "zoom", "dur": 1.00},
	]})
	p.advance(0.10)
	var forced := p.force_finish()
	_assert_true("seq.force_finish 覆盖全部未完成 step", forced.size() == 2)
	for tk in forced:
		_assert_near("seq.force_finish 推到终值", tk.t, 1.0)
	_assert_true("seq.force_finish 后无残留", p.force_finish().is_empty())

func _test_timeout_detection() -> void:
	var p := SequencePlayer.new()
	p.load_sequence("t", {"max_sec": 0.20, "steps": [
		{"at": 0.00, "ch": "overlay", "op": "dim", "dur": 5.00},
	]})
	p.advance(0.10)
	_assert_true("seq.未超时", not p.is_timed_out())
	p.advance(0.20)
	_assert_true("seq.超时可检出", p.is_timed_out())


# ══════════════════════════════════════════════
#  4. 真实序列的结构约束（spec §2.3 / §2.4）
# ══════════════════════════════════════════════

func _test_upgrade_sequences_wellformed() -> void:
	var defs := _load_real_sequences()
	if defs.is_empty():
		return

	# 入场：必须先请求缩放、再 hard_pause（顺序反了会在正常速度下直接冻住，急刹感全失）
	var in_steps: Array = defs.get("upgrade_in", {}).get("steps", [])
	var t_request := -1.0
	var t_pause := -1.0
	for s in in_steps:
		if String(s.get("ch", "")) == "time":
			if String(s.get("op", "")) == "request":
				t_request = float(s.get("at", 0.0)) + float(s.get("dur", 0.0))
			elif String(s.get("op", "")) == "pause":
				t_pause = float(s.get("at", 0.0))
	_assert_true("upgrade_in: 有 time.request", t_request >= 0.0)
	_assert_true("upgrade_in: 有 time.pause", t_pause >= 0.0)
	_assert_true("upgrade_in: 缩放跑完才 hard_pause", t_pause >= t_request - 0.001)

	# 退场：解除暂停与释放缩放都必须在 at=0（状态恢复不得延后，守 Litmus #2）
	var out_steps: Array = defs.get("upgrade_out", {}).get("steps", [])
	var unpause_at := -1.0
	var release_at := -1.0
	for s in out_steps:
		if String(s.get("ch", "")) != "time":
			continue
		if String(s.get("op", "")) == "pause" and int(s.get("to", 1)) == 0:
			unpause_at = float(s.get("at", 0.0))
		elif String(s.get("op", "")) == "release":
			release_at = float(s.get("at", 0.0))
	_assert_near("upgrade_out: 第 0 帧解除暂停", unpause_at, 0.0)
	_assert_near("upgrade_out: 第 0 帧释放缩放", release_at, 0.0)

	# 入场请求的 id 必须与退场释放的 id 一致，否则时间缩放永久泄漏
	var in_id := ""
	var out_id := ""
	for s in in_steps:
		if String(s.get("ch", "")) == "time" and String(s.get("op", "")) == "request":
			in_id = String(s.get("id", ""))
	for s in out_steps:
		if String(s.get("ch", "")) == "time" and String(s.get("op", "")) == "release":
			out_id = String(s.get("id", ""))
	_assert_true("leak.请求/释放 id 配平（%s vs %s）" % [in_id, out_id],
		in_id != "" and in_id == out_id)


# ══════════════════════════════════════════════
#  5. Wraith 登场演出（spec §2.8~§2.11）
# ══════════════════════════════════════════════

func _test_wraith_sequence_wellformed() -> void:
	var defs := _load_real_sequences()
	var seq: Dictionary = defs.get("wraith_squadron_arrival", {})
	_assert_true("wraith: 序列存在", not seq.is_empty())
	if seq.is_empty():
		return

	var p := SequencePlayer.new()
	p.load_sequence("wraith_squadron_arrival", seq)
	var total := p.total_duration()
	_assert_true("wraith: 总时长 ≤ 硬上限 7.0s（实际 %.2f）" % total, total <= 7.0)
	_assert_true("wraith: max_sec 已设为 7.0", absf(p.max_sec - 7.0) < 0.001)

	var steps: Array = seq.get("steps", [])
	var t_of := func(ch: String, op: String) -> float:
		for s in steps:
			if String(s.get("ch", "")) == ch and String(s.get("op", "")) == op:
				return float(s.get("at", -1.0))
		return -1.0

	# 幕序：清舞台 → 进场 → 交汇 → 隐身 → 散开/淡回 → 解暂停+释放
	var t_clear: float = t_of.call("stage", "clear")
	var t_ingress: float = t_of.call("actor", "echelon_ingress")
	var t_conv: float = t_of.call("actor", "converge")
	var t_cloak: float = t_of.call("actor", "cloak_on_meet")
	var t_scatter: float = t_of.call("actor", "scatter")
	var t_restore: float = t_of.call("stage", "restore")
	var t_release: float = t_of.call("actor", "release")
	_assert_true("wraith: 清舞台在最前", t_clear >= 0.0 and t_clear <= t_ingress)
	_assert_true("wraith: 进场 → 交汇", t_ingress < t_conv)
	# 交汇即隐身：隐身窗与交汇同启（贴上长机才触发，非定时）
	_assert_true("wraith: 隐身窗与交汇同启", absf(t_cloak - t_conv) < 0.11)
	var cloak_end := -1.0
	for st in steps:
		if String(st.get("op", "")) == "cloak_on_meet":
			cloak_end = float(st.get("at", 0.0)) + float(st.get("dur", 0.0))
			_assert_true("wraith: 交汇触发半径合理（%.0f ≥ 到点半径 80）" % float(st.get("radius", 0.0)),
				float(st.get("radius", 0.0)) >= 80.0)
	_assert_true("wraith: 隐身窗覆盖到散开（%.2f ≥ %.2f）" % [cloak_end, t_scatter],
		cloak_end >= t_scatter - 0.001)
	_assert_true("wraith: 散开与世界淡回同步（散开无观众）", absf(t_scatter - t_restore) < 0.001)
	_assert_true("wraith: release 在最后", t_release >= t_restore)

	# 收拢必须在第 3 句台词之后起（「交战自由」卡住收拢起点）
	var t_line3 := -1.0
	for s in steps:
		if String(s.get("ch", "")) == "radio" and String(s.get("key", "")).ends_with("SPAWN_3"):
			t_line3 = float(s.get("at", -1.0))
	_assert_true("wraith: 第 3 句台词卡在收拢起点", t_line3 >= 0.0 and t_line3 <= t_conv)

	# 三句台词都必须给编排时长（否则走 2.6s 封底，三句连播 8.5s 撑爆演出）
	var radio_n := 0
	for s in steps:
		if String(s.get("ch", "")) != "radio":
			continue
		radio_n += 1
		_assert_true("wraith: 台词 %s 有编排时长" % String(s.get("key", "")),
			float(s.get("dur", 0.0)) > 0.0)
	_assert_true("wraith: 三句台词齐全", radio_n == 3)

	# 演出必须自带配乐（playtest 反馈：大阵仗登场配巡航曲 = 气氛断档）
	var has_bgm := false
	for st in steps:
		if String(st.get("ch", "")) == "audio" and String(st.get("op", "")) == "boss_bgm":
			has_bgm = true
	_assert_true("wraith: 演出开场切 BOSS 曲（audio.boss_bgm）", has_bgm)

	# 演出必须自带收尾（release），否则演员永远停在免战脚本模式
	_assert_true("leak.wraith 有 actor.release 收尾", t_release >= 0.0)

	# 镜头必须跟随长机而非定点（playtest 回归："镜头看着战区正中央的空气"）。
	# 且进场 step 必须排在 cut_to 之前 —— 切镜要读演员传送后的定位，数组序即执行序
	var idx_ingress := -1
	var idx_cut := -1
	var cut_follow := false
	for i in range(steps.size()):
		match String(steps[i].get("op", "")):
			"echelon_ingress":
				idx_ingress = i
			"cut_to":
				idx_cut = i
				cut_follow = bool(steps[i].get("follow", false))
	_assert_true("wraith: cut_to 开启跟随长机（follow=true）", cut_follow)
	_assert_true("wraith: 进场先于切镜（idx %d < %d）" % [idx_ingress, idx_cut],
		idx_ingress >= 0 and idx_ingress < idx_cut)
	# 交汇到点半径必须收紧，300px 下四条线交不成一个点
	for s in steps:
		if String(s.get("op", "")) == "converge":
			_assert_true("wraith: 交汇到点半径已收紧（%.0f ≤ 100）" % float(s.get("arrive_radius", 999)),
				float(s.get("arrive_radius", 999)) <= 100.0)

func _test_simple_boss_sequences_wellformed() -> void:
	var defs := _load_real_sequences()
	for seq_name in ["carrier_strike_group_arrival", "mother_goose_arrival", "black_star_arrival"]:
		var seq: Dictionary = defs.get(seq_name, {})
		_assert_true("%s: 序列存在" % seq_name, not seq.is_empty())
		if seq.is_empty():
			continue
		var p := SequencePlayer.new()
		p.load_sequence(seq_name, seq)
		_assert_true("%s: 总时长 ≤ 7s（%.2f）" % [seq_name, p.total_duration()],
			p.total_duration() <= 7.0)
		var has_cut := false
		var has_return := false
		var has_radio := false
		var has_release := false
		var return_at := -1.0
		var release_at := -1.0
		for s in seq.get("steps", []):
			var ch := String(s.get("ch", ""))
			var op := String(s.get("op", ""))
			if ch == "camera" and op == "cut_to":
				has_cut = bool(s.get("follow", false))
			if ch == "camera" and op == "return_to_player":
				has_return = true
				return_at = float(s.get("at", -1.0))
			if ch == "radio" and op == "line":
				has_radio = true
			if ch == "actor" and op == "release":
				has_release = true
				release_at = float(s.get("at", -1.0))
		_assert_true("%s: 镜头跟随 BOSS 主体" % seq_name, has_cut)
		_assert_true("%s: 播放登场无线电" % seq_name, has_radio)
		_assert_true("%s: 镜头回玩家" % seq_name, has_return)
		_assert_true("%s: 回镜后释放演出" % seq_name,
			has_release and release_at >= return_at)

## 所有注册 BOSS 共用同一横幅通道；身份数据留在注册表，镜头必须等横幅退完才切。
func _test_boss_banner_contract() -> void:
	var defs := _load_real_sequences()
	for boss_id in BossRegistry.BOSS_DEFS.keys():
		var definition: Dictionary = BossRegistry.BOSS_DEFS[boss_id]
		var name_key := String(definition.get("banner_name_key", ""))
		var role_key := String(definition.get("banner_role_key", ""))
		var motto_key := String(definition.get("banner_motto_key", ""))
		var palette_id := String(definition.get("banner_palette", ""))
		_assert_true("banner.%s 有 name key" % boss_id, not name_key.is_empty())
		_assert_true("banner.%s 有 role key" % boss_id, not role_key.is_empty())
		_assert_true("banner.%s 有 motto key" % boss_id, not motto_key.is_empty())
		_assert_true("banner.%s palette 可解析" % boss_id,
			BossArrivalBannerScript.has_palette(palette_id))
		_assert_true("banner.%s 有 callsign" % boss_id,
			not String(definition.get("callsign_prefix", "")).is_empty())

		var seq_name := "%s_arrival" % String(boss_id).to_lower()
		var steps: Array = defs.get(seq_name, {}).get("steps", [])
		var reveal_at := -1.0
		var reveal_end := -1.0
		var dismiss_at := -1.0
		var dismiss_end := -1.0
		var first_cut := INF
		for s in steps:
			var ch := String(s.get("ch", ""))
			var op := String(s.get("op", ""))
			var at := float(s.get("at", 0.0))
			var finish := at + float(s.get("dur", 0.0))
			if ch == "banner" and op == "reveal":
				reveal_at = at
				reveal_end = finish
			elif ch == "banner" and op == "dismiss":
				dismiss_at = at
				dismiss_end = finish
			elif ch == "camera" and op == "cut_to":
				first_cut = minf(first_cut, at)
		_assert_near("banner.%s reveal 从第 0 秒开始" % boss_id, reveal_at, 0.0)
		_assert_true("banner.%s 留足逐窗动画时长" % boss_id,
			reveal_end - reveal_at >= 1.0)
		_assert_true("banner.%s reveal 先于 dismiss" % boss_id,
			reveal_end > 0.0 and dismiss_at >= reveal_end)
		_assert_true("banner.%s 完全退场后才切镜" % boss_id,
			dismiss_end > 0.0 and first_cut < INF and first_cut >= dismiss_end - 0.001)

	for index in range(1, BossArrivalBannerScript.WINDOW_COUNT):
		var next_start: float = float(index) * BossArrivalBannerScript.WINDOW_REVEAL_STAGGER
		var previous_progress: float = BossArrivalBannerScript.warning_reveal_progress(
			index - 1, next_start)
		var current_progress: float = BossArrivalBannerScript.warning_reveal_progress(
			index, next_start)
		_assert_true("banner.窗口 %d 完成后窗口 %d 才出现" % [index, index + 1],
			previous_progress >= 0.999 and current_progress <= 0.001)
	var last_window_end: float = \
		float(BossArrivalBannerScript.WINDOW_COUNT - 1) \
		* BossArrivalBannerScript.WINDOW_REVEAL_STAGGER \
		+ BossArrivalBannerScript.WINDOW_REVEAL_DURATION
	_assert_true("banner.五个警告窗完成后才展开主身份",
		BossArrivalBannerScript.MAIN_REVEAL_START >= last_window_end - 0.001)

	var mother := BossRegistry.banner_metadata_for("MOTHER_GOOSE")
	_assert_true("banner.Mother Goose 主标题 key", String(mother.get("name_key")) \
		== "BOSS_BANNER_MOTHER_GOOSE_NAME")
	_assert_true("banner.Mother Goose 角色 key", String(mother.get("role_key")) \
		== "BOSS_BANNER_MOTHER_GOOSE_ROLE")
	_assert_true("banner.Mother Goose 呼号 GOOSE", String(mother.get("callsign")) == "GOOSE")
	_assert_true("banner.包装英文翻译资源已生成",
		TranslationServer.translate("BOSS_BANNER_MOTTO") == "INVADERS MUST DIE")
	_assert_true("banner.Mother Goose 名称翻译资源已生成",
		TranslationServer.translate("BOSS_BANNER_MOTHER_GOOSE_NAME") == "MOTHER GOOSE")
	_assert_true("banner.Mother Goose 角色翻译资源已生成",
		TranslationServer.translate("BOSS_BANNER_MOTHER_GOOSE_ROLE") == "AIRBORNE UAV CARRIER")
	var wraith := BossRegistry.banner_metadata_for("WRAITH_SQUADRON")
	_assert_true("banner.Wraith 左上包装 key",
		String(wraith.get("motto_key")) == "BOSS_BANNER_WRAITH_MOTTO")
	_assert_true("banner.Wraith 使用蓝黑 palette",
		String(wraith.get("palette")) == "wraith_blue")
	_assert_true("banner.Wraith 左上包装翻译资源已生成",
		TranslationServer.translate("BOSS_BANNER_WRAITH_MOTTO") == "NOTHING BUT THIEVES")
	var csg := BossRegistry.banner_metadata_for("CARRIER_STRIKE_GROUP")
	_assert_true("banner.CSG 左上包装 key",
		String(csg.get("motto_key")) == "BOSS_BANNER_CSG_MOTTO")
	_assert_true("banner.CSG 保持终端绿 palette",
		String(csg.get("palette")) == "terminal_green")
	_assert_true("banner.CSG 左上包装翻译资源已生成",
		TranslationServer.translate("BOSS_BANNER_CSG_MOTTO") == "AN AWESOME WAVE")

## 同时抵达要按距离反解速度：远的必须更快，否则四线依次穿过而非汇于一点。
## 且【全部机位的所需速度必须落在机体包线内】—— 超出会被钳速，同时抵达随之失效。
## 这条断言就是为了守住"空间尺度必须从速度反推"这个教训（早期 5200px 进场需 41 秒）
const F47_MAX_KMH := 2800.0     ## resources/enemy_f47.tres
const F47_CRUISE_KMH := 1600.0

func _test_converge_speed_solve() -> void:
	var defs := _load_real_sequences()
	var steps: Array = defs.get("wraith_squadron_arrival", {}).get("steps", [])
	var offsets: Array = []
	var ingress_dist := 0.0
	var ingress_speed := 0.0
	var conv_dur := 0.0
	var ingress_at := 0.0
	var conv_at := 0.0
	for s in steps:
		match String(s.get("op", "")):
			"echelon_ingress":
				offsets = s.get("offsets", [])
				ingress_dist = float(s.get("ingress_dist", 0.0))
				ingress_speed = float(s.get("speed", 0.0))
				ingress_at = float(s.get("at", 0.0))
			"converge":
				conv_dur = float(s.get("dur", 0.0))
				conv_at = float(s.get("at", 0.0))
	if offsets.is_empty() or conv_dur <= 0.0:
		_assert_true("converge: 序列参数可读", false)
		return

	var px_per_sec := func(kmh: float) -> float:
		return kmh / 3.6 * CombatUnit.PIXELS_PER_METER
	var kmh_for := func(dist: float, t: float) -> float:
		return (dist / t) / CombatUnit.PIXELS_PER_METER * 3.6

	# 进场段：ingress_dist 必须约等于 速度 × 可见时长，否则演出结束时飞机还没到位
	var ingress_time: float = conv_at - ingress_at
	var reachable: float = px_per_sec.call(ingress_speed) * ingress_time
	_assert_true("ingress: %.0fpx 在 %.1fs 内飞得完（可达 %.0fpx）" % [
		ingress_dist, ingress_time, reachable], ingress_dist <= reachable * 1.05)
	_assert_true("ingress: 速度不超包线（%.0f ≤ %.0f）" % [ingress_speed, F47_MAX_KMH],
		ingress_speed <= F47_MAX_KMH)

	# 交汇段：CP 取锚点前方 250px（与 boss_encounter_event 的 cp 保持一致）
	const CP_AHEAD := 250.0
	var slowest := 1e9
	var fastest := 0.0
	for o in offsets:
		var dx: float = CP_AHEAD - float(o[0])
		var dy: float = -float(o[1])
		var dist: float = sqrt(dx * dx + dy * dy)
		var need: float = kmh_for.call(dist, conv_dur)
		slowest = minf(slowest, need)
		fastest = maxf(fastest, need)
		_assert_true("converge: 机位 %s 所需 %.0f km/h 在包线内" % [str(o), need],
			need <= F47_MAX_KMH)
	_assert_true("converge: 远机比近机快（%.0f > %.0f）" % [fastest, slowest], fastest > slowest)


# ══════════════════════════════════════════════
#  6. 压暗层高度（playtest 回归：战术地图被自己的遮罩压黑）
# ══════════════════════════════════════════════

## 压暗层必须【永远低于】被展示的面板，否则面板被自己的转场遮罩盖住。
## 实测踩过：战术图在 CanvasLayer 15，而压暗层固定 16 → 打开 Tab 地图整个变黑。
## 规则：dim_layer = min(DIM_LAYER, panel.layer - 1)
func _test_dim_layer_placement() -> void:
	const DIM_DEFAULT := 16
	var solve := func(panel_layer: int) -> int:
		return mini(DIM_DEFAULT, maxi(panel_layer - 1, 1))
	# 各面板的实际 layer（与各自 _ready 中的赋值一致）
	var cases := {
		"战术图": 15,
		"升级面板": 20,
		"进化站": 20,
		"边界菜单": 20,
	}
	for label in cases:
		var pl: int = cases[label]
		var dim: int = solve.call(pl)
		_assert_true("dim.%s(layer %d) 压暗层 %d 在其下" % [label, pl, dim], dim < pl)
	# 面板高于默认值时，压暗层不该被抬上去 —— 否则会盖住无线电(19)/战区提示(18)
	_assert_true("dim.面板在 20 时压暗层仍为 16（留无线电在亮处）", solve.call(20) == 16)
	# 极端：面板在 layer 1，压暗层不得降到 0 以下
	_assert_true("dim.面板在最低层时压暗层 ≥ 1", solve.call(1) >= 1)


# ══════════════════════════════════════════════
#  7. 登场演出的命名契约（playtest 回归：演出没播，静默回落旧路径）
# ══════════════════════════════════════════════

## BossEncounterEvent 按 `boss_id.to_lower() + "_arrival"` 找序列，找不到就【静默】
## 回落到"横幅+无线电"的旧路径 —— 表现是"只听见无线电、镜头不动"，不报任何错。
## 实测踩过：序列命名 `wraith_arrival`，而 boss_id 是 `WRAITH_SQUADRON`，
## 派生名 `wraith_squadron_arrival` 对不上 → 演出从未播出。
## 本测试双向校验：每个 *_arrival 序列都要对应真实 BOSS，且命名必须可被派生出来。
func _test_arrival_seq_names_match_registry() -> void:
	var defs := _load_real_sequences()
	var valid_names: Array[String] = []
	for boss_id in BossRegistry.BOSS_DEFS.keys():
		valid_names.append("%s_arrival" % String(boss_id).to_lower())

	var found_any := false
	for seq_name in defs.keys():
		var n := String(seq_name)
		if not n.ends_with("_arrival"):
			continue
		found_any = true
		_assert_true("arrival.'%s' 能被某个 boss_id 派生出来" % n, valid_names.has(n))
	_assert_true("arrival: 至少有一个登场演出", found_any)

	# 反向：每个注册 BOSS 都必须有演出；缺一个就会退化成无镜头直接接战。
	for expected in valid_names:
		_assert_true("arrival: 注册 BOSS 演出已就位（%s）" % expected, defs.has(expected))

	# 回归：边界补给的 panel_out 若与 10 分钟 BOSS arrival 相撞，Presentation 只会发
	# 替代序列的完成信号。玩法层必须 fail-open 进入 ENGAGED，不能重挂后永久卡 PRE_STAGE。
	var interrupted := BossEncounterEvent.new(Vector2.ZERO, 0.0, "default")
	interrupted.encounter = BossEncounter.new()
	interrupted.encounter.bgm_track = ""
	interrupted.encounter.active = true
	interrupted.active = true
	interrupted.phase = BossEncounterEvent.Phase.PRE_STAGE
	interrupted._on_arrival_cinematic_done("panel_out", "wraith_squadron_arrival")
	_assert_true("arrival: UI 序列打断后立即进入 ENGAGED",
		interrupted.phase == BossEncounterEvent.Phase.ENGAGED)
	_assert_true("arrival: UI 序列打断后仍开启 BOSS 血条",
		interrupted.encounter.hud_visible)


# ══════════════════════════════════════════════
#  8. 锁定表现屏幕尺寸（presentation-foundation-rework DEC-001）
# ══════════════════════════════════════════════

func _test_lock_visual_screen_scale() -> void:
	for view_scale in [0.2, 0.35, 1.0, 2.0, 5.0]:
		var inv: float = AircraftRenderer.inverse_screen_scale_for(view_scale)
		_assert_near("lock_visual.zoom %.2f 屏幕尺寸恒定" % view_scale,
			view_scale * inv, 1.0)
	# Canvas scale 意外为 0 时必须安全钳制，不能把 INF 写进 draw transform。
	_assert_near("lock_visual.zero_scale 安全钳制",
		AircraftRenderer.inverse_screen_scale_for(0.0), 100.0)


func _test_compact_aircraft_labels() -> void:
	# 标签 LOD 必须剥离窗口拉伸。否则 4K 最大化（stretch=2）时，
	# 最远相机 zoom 0.20 会被误读成 0.40，永远无法进入 0.35 简略档。
	for stretch_scale in [1.0, 4.0 / 3.0, 2.0]:
		var normalized := AircraftRenderer.label_lod_scale_for(
			0.35 * stretch_scale, stretch_scale)
		_assert_near("label_lod.stretch %.2f 不改变相机档位" % stretch_scale,
			normalized, 0.35)
	_assert_true("label_lod.4K 最大化后最远 zoom 仍进入战略档",
		AircraftRenderer.next_compact_label_state(false,
			AircraftRenderer.label_lod_scale_for(0.20 * 2.0, 2.0)))

	var compact := AircraftRenderer.next_compact_label_state(false, 0.40)
	_assert_true("label_lod.放大到 0.40 保持详细", not compact)
	compact = AircraftRenderer.next_compact_label_state(compact, 0.35)
	_assert_true("label_lod.默认 0.35 进入战略档", compact)
	compact = AircraftRenderer.next_compact_label_state(compact, 0.38)
	_assert_true("label_lod.迟滞区保持战略档", compact)
	compact = AircraftRenderer.next_compact_label_state(compact, 0.40)
	_assert_true("label_lod.稍微放大到 0.40 恢复详细", not compact)
	_assert_true("label_lod.战略档正常显示精简",
		AircraftRenderer.compact_label_visible(true, false))
	_assert_true("label_lod.Alt 临时强制完整",
		not AircraftRenderer.compact_label_visible(true, true))

	# 远景维持旧锚点；近景必须按机体屏幕半径外移，避免白底盖住机翼。
	var far_anchor := AircraftRenderer.data_label_screen_offset_for(
		26.0, 0.35, Vector2.ZERO)
	_assert_true("data_label.远景保持 24px 旧锚点", far_anchor == Vector2(24.0, -12.0))
	var near_anchor := AircraftRenderer.data_label_screen_offset_for(
		26.0, 5.0, Vector2.ZERO)
	_assert_true("data_label.5x 近景保持至少 8px 机外间距",
		near_anchor.x >= 26.0 * 5.0 + 8.0)
	# 高速移动最容易暴露亚像素文字采样；标签最终屏幕原点必须落在整数像素。
	var moving_origin := Vector2(100.25, 200.75)
	var snapped_offset := AircraftRenderer.data_label_screen_offset_for(
		26.0, 5.0, moving_origin)
	var snapped_origin := moving_origin + snapped_offset
	_assert_true("data_label.高速移动时原点像素对齐",
		is_equal_approx(snapped_origin.x, roundf(snapped_origin.x))
		and is_equal_approx(snapped_origin.y, roundf(snapped_origin.y)))


func _test_presentation_label_refinements() -> void:
	_assert_near("lock_box.ground_scale", AircraftRenderer.lock_box_altitude_scale_for(0.0), 0.55)
	_assert_near("lock_box.low_scale", AircraftRenderer.lock_box_altitude_scale_for(2000.0), 0.70)
	_assert_near("lock_box.mid_scale", AircraftRenderer.lock_box_altitude_scale_for(5500.0), 0.85)
	_assert_near("lock_box.high_scale", AircraftRenderer.lock_box_altitude_scale_for(10000.0), 1.0)
	_assert_near("lock_box.high_scale_is_max", AircraftRenderer.lock_box_altitude_scale_for(16000.0), 1.0)
	_assert_true("lock_box.scale_grows_with_altitude",
		AircraftRenderer.lock_box_altitude_scale_for(3000.0)
		< AircraftRenderer.lock_box_altitude_scale_for(8000.0))

	var status_ac := Aircraft.new()
	status_ac.status_overload_active = true
	status_ac.status_effects[StatusEffects.BLOODLUST] = 5.0
	status_ac.status_initial_durations[StatusEffects.BLOODLUST] = 10.0
	var status_entries := AircraftRenderer.status_label_entries(status_ac)
	_assert_true("compact_status.includes_derived_and_timed",
		status_entries.size() == 2
		and status_entries[0]["id"] == StatusEffects.OVERLOAD
		and status_entries[1]["id"] == StatusEffects.BLOODLUST)
	_assert_true("compact_status.includes_remaining_percent",
		status_entries[1]["text"] == "FRENZY 50%")
	status_ac.free()

	_assert_true("label_name.已有尾部代号不重复",
		SurvivorPlayableSetup.display_name_with_codename("F-15 Eagle", "Eagle") == "F-15 Eagle")
	_assert_true("label_name.复合代号不重复",
		SurvivorPlayableSetup.display_name_with_codename("F-15E Strike Eagle", "Strike Eagle") == "F-15E Strike Eagle")
	_assert_true("label_name.缺失代号正常追加",
		SurvivorPlayableSetup.display_name_with_codename("F-16C", "SmartFalcon") == "F-16C SmartFalcon")
	var player := Aircraft.new()
	player.params = AircraftParams.new()
	player.params.display_name = "F-14 Tomcat"
	var profile := PlayableAircraft.new()
	profile.codename = "Warhound"
	SurvivorPlayableSetup.apply(player, profile)
	player.callsign = "Ultra"
	_assert_true("label_name.机体字段只保留纯机型编号",
		AircraftRenderer.airframe_identity_label(player) == "F-14")
	_assert_true("label_name.战场标签完整保留呼号",
		AircraftRenderer.controlled_identity_label(player) == "F-14 [Ultra]")
	_assert_true("label_name.单词机名后缀缩为首字母",
		AircraftRenderer.compact_aircraft_name("F-15 Eagle") == "F-15 E")
	_assert_true("label_name.多词机名后缀也只留一个首字母",
		AircraftRenderer.compact_aircraft_name("Su-35 Super Flanker") == "Su-35 S")
	_assert_true("label_name.完整运行时名称仍保留",
		player.params.display_name == "F-14 Tomcat Warhound")
	_assert_true("silhouette.player_f14.档案代号不应触发旧轮廓回退",
		AircraftSilhouetteCatalog.key_for(player) == "f14")
	player.free()
	var mq_family := Aircraft.new()
	mq_family.params = AircraftParams.new()
	var mq_keys := PackedStringArray()
	for model in ["MQ-109", "MQ-110", "MQ-111"]:
		mq_family.params.display_name = model
		mq_keys.append(AircraftSilhouetteCatalog.key_for(mq_family))
	_assert_true("silhouette.mq109_family.三型号共用新轮廓",
		mq_keys == PackedStringArray(["mq109_family", "mq109_family", "mq109_family"]))
	mq_family.params.display_name = "MQ-112"
	_assert_true("silhouette.mq112.未点名型号继续旧绘制",
		AircraftSilhouetteCatalog.key_for(mq_family).is_empty())
	mq_family.params.display_name = "MQ-109"
	_assert_near("silhouette.mq109_family.保持无人机小尺寸",
		AircraftSilhouetteCatalog.draw_scale_for(mq_family), 0.53)
	mq_family.free()
	_assert_true("reload_hint.仅 FLR/GUN/MSL 且顺序固定",
		AircraftRenderer.reload_indicator_tokens(true, true, true)
		== PackedStringArray(["FLR", "GUN", "MSL"]))
	_assert_true("reload_hint.僚机主弹装填可独立显示",
		AircraftRenderer.reload_indicator_tokens(false, true, false)
		== PackedStringArray(["MSL"]))
	_assert_true("reload_hint.无装填则不显示",
		AircraftRenderer.reload_indicator_tokens(false, false, false).is_empty())
	_assert_true("reload_hint.蓝色玩家小队显示",
		AircraftRenderer.reload_indicator_team_visible(CombatUnit.TEAM_PLAYER))
	_assert_true("reload_hint.绿色第三方友军不显示",
		not AircraftRenderer.reload_indicator_team_visible(CombatUnit.TEAM_ALLY))
	_assert_true("reload_hint.敌机不显示",
		not AircraftRenderer.reload_indicator_team_visible(CombatUnit.TEAM_HOSTILE))
	var normal_msl := AircraftRenderer.reload_indicator_style("MSL", false)
	var inverse_msl := AircraftRenderer.reload_indicator_style("MSL", true)
	var normal_flr := AircraftRenderer.reload_indicator_style("FLR", false)
	var inverse_flr := AircraftRenderer.reload_indicator_style("FLR", true)
	var normal_gun := AircraftRenderer.reload_indicator_style("GUN", false)
	var inverse_gun := AircraftRenderer.reload_indicator_style("GUN", true)
	var wing_msl := AircraftRenderer.reload_indicator_style("MSL", false, false)
	var wing_msl_inverse := AircraftRenderer.reload_indicator_style("MSL", true, false)
	_assert_true("reload_hint.non_controlled_missiles_use_white_text",
		wing_msl[0].is_equal_approx(Color.WHITE)
		and wing_msl_inverse[0].is_equal_approx(Color.WHITE)
		and AircraftRenderer.weapon_label_color("MSL_RELOAD", false).is_equal_approx(Color.WHITE)
		and AircraftRenderer.weapon_label_color("SP_RELOAD", false).is_equal_approx(Color.WHITE))
	_assert_true("reload_hint.MSL 蓝底白字且可反相",
		normal_msl[1].is_equal_approx(Color.html("#5599ff"))
		and normal_msl[0].r > 0.9 and inverse_msl[0].is_equal_approx(Color.html("#5599ff")))
	_assert_true("reload_hint.FLR 橙色与深蓝反相",
		normal_flr[1].is_equal_approx(Color.html("#ff9d2e"))
		and normal_flr[0].is_equal_approx(Color.html("#00237d"))
		and inverse_flr[0].is_equal_approx(Color.html("#ff9d2e")))
	_assert_true("reload_hint.GUN 褐色与白色反相",
		normal_gun[1].is_equal_approx(Color.html("#8b5a2b"))
		and normal_gun[0].r > 0.9
		and inverse_gun[0].is_equal_approx(Color.html("#8b5a2b")))


func _test_freed_aircraft_reference_safety() -> void:
	var live := Aircraft.new()
	AircraftRenderer.player_ref = live
	_assert_true("player_ref.存活飞机可安全收窄",
		AircraftRenderer.safe_aircraft_ref(live) == live)
	var stale: Variant = live
	live.free()
	_assert_true("player_ref.已释放 Variant 回落 null",
		AircraftRenderer.safe_aircraft_ref(stale) == null)
	_assert_true("player_ref.全局缓存自动清除",
		AircraftRenderer.safe_player_ref() == null and AircraftRenderer.player_ref == null)

	var survivor := SurvivorPlayer.new()
	var cached := Aircraft.new()
	var hud := SurvivorHUD.new()
	survivor.aircraft = cached
	hud.survivor_player = survivor
	cached.free()
	_assert_true("player_ref.HUD 强类型缓存已释放不报错",
		hud._safe_player_aircraft() == null)
	hud.free()
	survivor.free()


func _test_incoming_missile_warning_rule() -> void:
	_assert_true("missile_warning.真实来袭显示",
		Missile.incoming_warning_rule(true, true, false, true, true, true, false))
	_assert_true("missile_warning.未发射无实体不显示",
		not Missile.incoming_warning_rule(false, true, false, true, true, true, false))
	_assert_true("missile_warning.丢失制导立即消失",
		not Missile.incoming_warning_rule(true, false, false, true, true, true, false))
	_assert_true("missile_warning.热诱弹骗走立即消失",
		not Missile.incoming_warning_rule(true, true, true, true, true, true, false))
	_assert_true("missile_warning.目标不是当前操控机不显示",
		not Missile.incoming_warning_rule(true, true, false, false, true, true, false))
	_assert_true("missile_warning.友方导弹不显示",
		not Missile.incoming_warning_rule(true, true, false, true, false, true, false))
	_assert_true("missile_warning.常规弹飞越后消失",
		not Missile.incoming_warning_rule(true, true, false, true, true, false, false))
	_assert_true("missile_warning.VLS 预末段离架即显示",
		Missile.incoming_warning_rule(true, true, false, true, true, false, true))


# ══════════════════════════════════════════════
#  断言辅助
# ══════════════════════════════════════════════

func _assert_true(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s" % label)

func _assert_near(label: String, actual: float, expected: float, tol: float = 0.002) -> void:
	if absf(actual - expected) <= tol:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s: 期望 %.4f 实际 %.4f" % [label, expected, actual])
