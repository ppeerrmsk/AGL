extends RefCounted

## 无线电通讯系统回归（spec radio-chatter）
## 覆盖：时长公式 / 阵营色 / 不打断契约 / 队列上限与淘汰 / 冷却 / 过期丢弃与豁免 /
##       BOSS 序列顺序 / 敌方减员里程碑 / 选词防重复
## 运行：godot --headless --path . -- --bench=chatter（或 --bench=all）
##
## 注意：本测试【不断言文本内容】。headless 下 .translation 未必包含新增的 RADIO_* key，
## tr() 会原样返回 key —— 这不影响任何被测逻辑（队列/时序/颜色/顺序全是结构性的）。

var _pass := 0
var _fail := 0

## 手工驱动 _process 的步长（不依赖引擎主循环，保证时序完全确定）
const DT := 1.0 / 60.0


func run() -> void:
	print("\n════════ 无线电通讯（队列/优先级/冷却/BOSS 序列） ════════")

	_test_duration_formula()
	_test_faction_colors()
	_test_never_interrupts()
	_test_queue_cap_and_eviction()
	_test_throttle()
	_test_stale_drop_and_exemption()
	_test_boss_sequence_order()
	_test_attrition_milestones()
	_test_pick_no_repeat()
	_test_i18n_coverage()
	_test_presentation()
	_test_voice_gate()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ══════════════════════════════════════════════
#  1. 时长公式（spec §2.2）
# ══════════════════════════════════════════════

func _test_duration_formula() -> void:
	print("── 时长公式 ──")
	_check("空串取基础时长 2.6",
		is_equal_approx(RadioChatter.line_duration(""), 2.6), "")
	# 18 字 → 2.6 + 0.035*18 = 3.23
	_check("18 字 → 3.23",
		is_equal_approx(RadioChatter.line_duration(_str_of_len(18)), 3.23), "")
	_check("超长文本封顶 5.0",
		is_equal_approx(RadioChatter.line_duration(_str_of_len(500)), 5.0), "")
	_check("时长单调不减",
		RadioChatter.line_duration(_str_of_len(40)) >= RadioChatter.line_duration(_str_of_len(10)), "")


# ══════════════════════════════════════════════
#  2. 阵营色（spec §2.5）—— 必须来自 FactionPalette，不得散写字面量
# ══════════════════════════════════════════════

func _test_faction_colors() -> void:
	print("── 阵营色映射 ──")
	_check("team0 玩家 → 蓝",
		RadioChatter.color_for_team(CombatUnit.TEAM_PLAYER) == GameConstants.COL_FRIEND_PLAYER, "")
	_check("team2 ALLY → 绿",
		RadioChatter.color_for_team(CombatUnit.TEAM_ALLY) == GameConstants.COL_FRIEND_ALLY, "")
	_check("team1 常规 → 橙",
		RadioChatter.color_for_team(CombatUnit.TEAM_HOSTILE) == GameConstants.COL_ENEMY_REGULAR, "")
	_check("team1 精英 → 红",
		RadioChatter.color_for_team(CombatUnit.TEAM_HOSTILE, true) == GameConstants.COL_ENEMY_ELITE, "")
	_check("敌我不同色",
		RadioChatter.color_for_team(0) != RadioChatter.color_for_team(1), "")


# ══════════════════════════════════════════════
#  3. 【核心契约】绝不打断（用户硬需求 / spec §1）
# ══════════════════════════════════════════════

func _test_never_interrupts() -> void:
	print("── 不打断契约 ──")
	var r := _make()

	r.say_text("wingman_join", "ALPHA", Color.WHITE, "low priority line")
	_step(r, 1)   # 开播
	var playing := r.debug_current_text()
	_check("低优先级条目已开播", playing == "low priority line", "实际=%s" % playing)

	# 最高优先级插入：绝不能顶掉正在播的
	r.say_text("boss_spawn", "WRAITH-01", Color.RED, "BOSS interrupt attempt")
	_step(r, 1)
	_check("最高优先级【不打断】正在播的条目",
		r.debug_current_text() == "low priority line",
		"实际=%s" % r.debug_current_text())
	_check("插入的条目在队列里等着", r.debug_queue_size() == 1, "")

	# 等当前这条自然播完 + 间隔，BOSS 那条才接上
	_step(r, int((RadioChatter.line_duration("low priority line") + ChatterLines.line_gap()) / DT) + 4)
	_check("前一条播完后 BOSS 条目接上",
		r.debug_current_text() == "BOSS interrupt attempt",
		"实际=%s" % r.debug_current_text())
	_free(r)


# ══════════════════════════════════════════════
#  4. 队列上限与淘汰（spec §3.1）
# ══════════════════════════════════════════════

func _test_queue_cap_and_eviction() -> void:
	print("── 队列上限 / 淘汰 ──")
	var r := _make()
	# 未驱动 _process → 不出队，可以纯测入队逻辑。
	# 每次入队前清节流：本用例只验队列结构，节流本身在 _test_throttle 里单独验。
	# 未登记的 trigger 取默认权重 40 / 默认冷却 0 / 默认 AMBIENT。
	r.debug_clear_throttle()
	_check("入队 1", r.say_text("t1", "A", Color.WHITE, "one"), "")
	r.debug_clear_throttle()
	_check("入队 2", r.say_text("t2", "B", Color.WHITE, "two"), "")
	r.debug_clear_throttle()
	_check("入队 3", r.say_text("t3", "C", Color.WHITE, "three"), "")
	_check("队列已满 = 3", r.debug_queue_size() == ChatterLines.queue_max(), "")

	r.debug_clear_throttle()
	_check("同权重第 4 条被丢弃",
		not r.say_text("t4", "D", Color.WHITE, "four"), "不得挤掉同权重")
	_check("丢弃后队列仍为 3", r.debug_queue_size() == 3, "")

	_check("更高权重顶掉最低者",
		r.say_text("boss_spawn", "WRAITH-01", Color.RED, "boss line"), "")
	_check("顶替后队列仍为 3（不膨胀）", r.debug_queue_size() == 3, "")

	# 高权重必须先出队
	_step(r, 1)
	_check("高权重先播", r.debug_current_speaker() == "WRAITH-01",
		"实际=%s" % r.debug_current_speaker())
	_free(r)


# ══════════════════════════════════════════════
#  5. 三层节流（spec §2.11）—— 语音刷屏的主闸门
#     ① 全局冷却  ② 冷却桶  ③ 概率骰；剧情语音全部跳过
# ══════════════════════════════════════════════

func _test_throttle() -> void:
	print("── 三层节流 ──")

	# ── ① 全局冷却：任何一条普通语音播出后，全场普通语音静默 ──
	# 用 chance=1.0 的 trigger 做确定性测试（splash 等带概率骰的会随机失败，
	# 那是第 ③ 层的行为，不能拿来验第 ① 层）
	var r := _make()
	_check("wingman_join（chance=1.0）确定性入队", ChatterLines.chance_of("wingman_join") == 1.0, "")
	_check("首条普通语音入队成功",
		r.say_text("wingman_join", "ALPHA", Color.WHITE, "joining"), "")
	_check("全局冷却已起算", r.debug_global_cooldown() > 0.0, "")
	_check("全局冷却内【其它 trigger】也被拒（这是全局的意义）",
		not r.say_text("attrition_t1", "CMD", Color.WHITE, "losses"),
		"不同 trigger、不同冷却桶，也必须被全局冷却挡住")

	# 全局冷却到期 → 放行
	_step(r, int(ChatterLines.global_ambient_cooldown() / DT) + 4)
	r.debug_drain_queue()
	_check("全局冷却到期后恢复",
		r.say_text("attrition_t1", "CMD", Color.WHITE, "losses again"), "")
	_free(r)

	# ── ② 冷却桶：不同 trigger 共享同一个桶 ──
	var r2 := _make()
	# attrition_t1/t2/t3 共享 "enemy_attrition" 桶，且 chance=1.0（确定性）
	_check("attrition_t1 入队成功",
		r2.say_text("attrition_t1", "CMD", Color.WHITE, "losses"), "")
	_check("桶冷却已起算",
		r2.debug_cooldown("enemy_attrition") > 0.0, "冷却记在【桶】名下而非 trigger 名下")
	r2.debug_clear_throttle()
	r2.say_text("attrition_t1", "CMD", Color.WHITE, "losses")
	_global_only_clear(r2)
	_check("同桶的【另一个】trigger 也被挡住",
		not r2.say_text("attrition_t2", "CMD", Color.WHITE, "heavy losses"),
		"t1 与 t2 共享 enemy_attrition 桶")
	_free(r2)

	# ── ③ 概率骰：统计验证（宽区间，避免偶发抖动导致假红）──
	var r3 := _make()
	var trials := 2000
	var hits := 0
	for i in trials:
		r3.debug_clear_throttle()
		if r3.say_text("ack_pursue", "ALPHA", Color.WHITE, "pursuing"):
			hits += 1
		r3.debug_drain_queue()
	var rate := float(hits) / float(trials)
	var want := ChatterLines.chance_of("ack_pursue")
	_check("ack 概率骰命中率 ≈ %.2f（实测 %.3f）" % [want, rate],
		absf(rate - want) < 0.08, "2000 次采样，容差 ±0.08")
	_free(r3)

	# ── ④ 剧情语音跳过全部三层 ──
	var r4 := _make()
	r4.say_text("wingman_join", "ALPHA", Color.WHITE, "joining")   # 先把全局冷却打上
	_check("全局冷却确已生效", r4.debug_global_cooldown() > 0.0, "")
	_check("剧情语音【无视全局冷却】必定入队",
		r4.say_text("boss_spawn", "WRAITH-01", Color.RED, "taunt"), "")
	_check("剧情语音不重置全局冷却（不占普通语音的账本）",
		r4.debug_global_cooldown() > 0.0, "")
	_free(r4)

	# 分类判定本身
	_check("boss_spawn 是 scripted", ChatterLines.is_scripted("boss_spawn"), "")
	_check("boss_engage 是 scripted", ChatterLines.is_scripted("boss_engage"), "")
	_check("Hound-1 入场台词是 scripted", ChatterLines.is_scripted("hound_one_contact"), "")
	_check("Hound-2 应答台词是 scripted", ChatterLines.is_scripted("hound_two_follow"), "")
	_check("奖励目标通报是 scripted", ChatterLines.is_scripted("reward_target_available"), "")
	_check("护送任务通报是 scripted", ChatterLines.is_scripted("bomber_escort_available"), "")
	_check("splash 是 ambient", not ChatterLines.is_scripted("splash"), "")
	_check("未登记 trigger 保守按 ambient（不会意外强插）",
		not ChatterLines.is_scripted("some_unknown_trigger"), "")


## 只清全局冷却，保留桶冷却（用于验证桶本身在起作用）
func _global_only_clear(r: RadioChatter) -> void:
	var saved := r.debug_cooldown("enemy_attrition")
	r.debug_clear_throttle()
	r.debug_set_cooldown("enemy_attrition", saved)


# ══════════════════════════════════════════════
#  6. 过期丢弃 + BOSS 豁免（spec §3.1）
# ══════════════════════════════════════════════

func _test_stale_drop_and_exemption() -> void:
	print("── 过期丢弃 / BOSS 豁免 ──")
	# 6a. 反应式战况：排到很后面就该丢
	var r := _make()
	var long_text := _str_of_len(200)   # 时长封顶 5.0s
	r.debug_clear_throttle()
	r.say_text("t_a", "A", Color.WHITE, long_text)
	r.debug_clear_throttle()
	r.say_text("t_b", "B", Color.WHITE, long_text)
	r.debug_clear_throttle()
	r.say_text("t_c", "C", Color.WHITE, "stale victim")
	# A 播 5s → gap 0.3 → B 播 5s → gap 0.3 → 轮到 C 时 age ≈ 10.6s > 6s
	_step(r, int(11.5 / DT))
	_check("排队超过 6s 的战况条目被丢弃",
		r.debug_current_text() != "stale victim",
		"实际=%s" % r.debug_current_text())
	_check("丢弃后队列清空", r.debug_queue_size() == 0, "")
	_free(r)

	# 6b. BOSS 剧本序列：必须豁免，收尾句不能被砍
	var r2 := _make()
	r2.say_text("boss_spawn", "WRAITH-01", Color.RED, long_text)
	r2.say_text("boss_spawn", "WRAITH-02", Color.RED, long_text)
	r2.say_text("boss_spawn", "WRAITH-01", Color.RED, "the punchline")
	_step(r2, int(11.5 / DT))
	_check("BOSS 序列的收尾句【不】被过期丢弃",
		r2.debug_current_text() == "the punchline",
		"实际=%s" % r2.debug_current_text())
	_free(r2)


# ══════════════════════════════════════════════
#  7. BOSS 登场序列（范例场景，spec §3.3）
# ══════════════════════════════════════════════

func _test_boss_sequence_order() -> void:
	print("── BOSS 登场序列 ──")
	var r := _make()
	var n := r.say_boss_sequence("WRAITH_SQUADRON", "spawn", "WRAITH")
	_check("WRAITH 登场序列入队 3 条", n == 3, "实际=%d" % n)

	# 第 1 句
	_step(r, 1)
	_check("第 1 句说话人 = WRAITH-01",
		r.debug_current_speaker() == "WRAITH-01", "实际=%s" % r.debug_current_speaker())
	_check("BOSS 台词为精英红",
		r.debug_current_color() == GameConstants.COL_ENEMY_ELITE, "")
	var t1 := r.debug_current_text()

	# 第 2 句：换人说
	_step(r, int((RadioChatter.line_duration(t1) + ChatterLines.line_gap()) / DT) + 4)
	_check("第 2 句说话人 = WRAITH-02（队内对话，不是同一人自言自语）",
		r.debug_current_speaker() == "WRAITH-02", "实际=%s" % r.debug_current_speaker())
	var t2 := r.debug_current_text()

	# 第 3 句：说回长机
	_step(r, int((RadioChatter.line_duration(t2) + ChatterLines.line_gap()) / DT) + 4)
	_check("第 3 句说话人 = WRAITH-01",
		r.debug_current_speaker() == "WRAITH-01", "实际=%s" % r.debug_current_speaker())
	_check("三句台词互不相同", t1 != t2 and t2 != r.debug_current_text(), "")
	_free(r)

	# 未登记的 BOSS 走默认挑衅，不得静默
	var r2 := _make()
	var n2 := r2.say_boss_sequence("POLTERGEIST_NOT_REGISTERED", "spawn", "PLTGST")
	_check("未登记 BOSS 回退默认序列（不静默）", n2 >= 1, "实际=%d" % n2)
	_step(r2, 1)
	_check("默认序列呼号用传入前缀",
		r2.debug_current_speaker() == "PLTGST-01", "实际=%s" % r2.debug_current_speaker())
	_free(r2)


# ══════════════════════════════════════════════
#  8. 敌方减员里程碑（spec §2.6）
# ══════════════════════════════════════════════

func _test_attrition_milestones() -> void:
	print("── 敌方减员哀嚎 ──")
	_check("档位 <36 → t1", ChatterLines.attrition_trigger(12) == "attrition_t1", "")
	_check("档位 36 → t2", ChatterLines.attrition_trigger(36) == "attrition_t2", "")
	_check("档位 71 → t2", ChatterLines.attrition_trigger(71) == "attrition_t2", "")
	_check("档位 72 → t3", ChatterLines.attrition_trigger(72) == "attrition_t3", "")

	var r := _make()
	for i in 11:
		r.notify_enemy_loss()
	_check("11 次损失不触发（未跨 12 的倍数）", r.debug_queue_size() == 0, "")
	r.notify_enemy_loss()   # 第 12 次
	_check("第 12 次触发哀嚎", r.debug_queue_size() == 1, "")

	# 冷却内不再触发，即使又跨了一个里程碑
	for i in 12:
		r.notify_enemy_loss()
	_check("25s 冷却内不重复触发", r.debug_queue_size() == 1, "")
	_free(r)


# ══════════════════════════════════════════════
#  9. 选词防重复（spec §3.5）
# ══════════════════════════════════════════════

func _test_pick_no_repeat() -> void:
	print("── 选词防重复 ──")
	var lines := ChatterLines.new()
	var prev := ""
	var repeats := 0
	for i in 60:
		var k := lines.pick("splash")
		if k == prev:
			repeats += 1
		prev = k
	_check("连抽 60 次无相邻重复", repeats == 0, "重复次数=%d" % repeats)
	_check("未知组返回空串（调用方跳过）", lines.pick("no_such_group") == "", "")

	# 覆盖度：多抽几次应当能抽到组内多个不同 key
	var seen := {}
	for i in 60:
		seen[lines.pick("eject")] = true
	_check("eject 组抽到 ≥2 个不同 key", seen.size() >= 2, "实际=%d" % seen.size())


# ══════════════════════════════════════════════
#  10. i18n 覆盖（spec §5）
# ══════════════════════════════════════════════
##
## tr() 查不到 key 时会【原样返回 key】—— 台词就会显示成 "RADIO_SPLASH_1"。
## 这是 csv 打字错误/漏行最典型的翻车方式，且在游戏里只有那一句台词恰好触发时才看得见。
## 这里把台词表里每一个 key 都过一遍，把它变成开局就能发现的回归。

func _test_i18n_coverage() -> void:
	print("── i18n 覆盖 ──")
	var missing: Array[String] = []
	var keys := ChatterLines.all_line_keys()
	for key in keys:
		if tr(key) == key:
			missing.append(key)
	for k in ["RADIO_SPEAKER_ENEMY_COMMAND", "RADIO_TARGET_GENERIC"]:
		if tr(k) == k:
			missing.append(k)

	_check("JSON 里全部 %d 个台词 key 都有译文" % keys.size(), missing.is_empty(),
		"缺失=%s" % str(missing))
	_check("台词表非空（JSON 加载成功）", keys.size() > 20, "实际=%d" % keys.size())

	# 带 %s 的 key 必须真的含占位符，否则回令里的目标名会凭空消失
	var fmt_bad: Array[String] = []
	for trigger in ["ack_pursue", "ack_surround", "ack_strike"]:
		for key in ChatterLines.lines_of(trigger):
			if not tr(String(key)).contains("%s"):
				fmt_bad.append(String(key))
	_check("_FMT 台词均含 %s 占位符", fmt_bad.is_empty(), "异常=%s" % str(fmt_bad))

	# 每个 trigger 都要有台词可选，否则该事件永远静默（典型的 JSON 打字错）
	var empty_triggers: Array[String] = []
	for tid in ChatterLines.all_trigger_ids():
		if ChatterLines.is_scripted(tid):
			continue   # 剧情类台词住在 boss_sequences，lines 本就为空
		if ChatterLines.lines_of(tid).is_empty():
			empty_triggers.append(tid)
	_check("每个普通 trigger 都有台词", empty_triggers.is_empty(),
		"空的=%s" % str(empty_triggers))


# ══════════════════════════════════════════════
#  11. 呈现层（参考皇牌空战：呼号一行 + << 正文 >> 一行）
# ══════════════════════════════════════════════

func _test_presentation() -> void:
	print("── 呈现层 ──")
	var r := _make()
	r.say_text("boss_spawn", "WRAITH-01", GameConstants.COL_ENEMY_ELITE, "All units.")
	_step(r, 1)

	_check("呼号单独成行（不与正文拼在一起）",
		r.debug_name_label_text() == "WRAITH-01", "实际=%s" % r.debug_name_label_text())
	_check("正文带 << >> 通话标记",
		r.debug_msg_label_text() == "<< All units. >>",
		"实际=%s" % r.debug_msg_label_text())
	_check("呼号用纯阵营色",
		r.debug_name_label_color() == GameConstants.COL_ENEMY_ELITE, "")
	_check("正文比呼号淡（主次分明）",
		r.debug_msg_label_color() != r.debug_name_label_color(), "")
	# 淡化方向必须是"向白靠拢"，不能是变暗（暗色在深色背景上会读不出来）
	var msg_c := r.debug_msg_label_color()
	var name_c := r.debug_name_label_color()
	_check("正文淡化方向为向白，不是变暗",
		msg_c.r >= name_c.r and msg_c.g >= name_c.g and msg_c.b >= name_c.b,
		"name=%s msg=%s" % [str(name_c), str(msg_c)])
	_free(r)


# ══════════════════════════════════════════════
#  12. 说话资格门（spec §2.8）—— 无人机不得有台词
# ══════════════════════════════════════════════

func _test_voice_gate() -> void:
	print("── 说话资格门 ──")

	# 等级门：无人机族 + 被动杂兵一律沉默
	for tag in ["uav", "ucav", "uav_commander", "uav_laser", "af03"]:
		_check("无人机 '%s' 无无线电" % tag, not ChatterLines.type_has_voice(tag), "")
	for tag in ["tu160", "ah64", "ch47"]:
		_check("被动杂兵 '%s' 无无线电" % tag, not ChatterLines.type_has_voice(tag), "")

	# 有人战斗机 + BOSS 有台词
	for tag in ["mig", "mig23", "su27", "su35", "f4", "fa18", "f47"]:
		_check("有人机 '%s' 有无线电" % tag, ChatterLines.type_has_voice(tag), "")

	# 未登记机型默认沉默（opt-in：以后新增敌人不会突然开口）
	_check("未登记机型默认沉默",
		not ChatterLines.type_has_voice("some_future_enemy"), "")

	# 硬规则：no_pilot 压过 has_radio_voice，漏设也不会开口
	var ac := Aircraft.new()
	ac.has_radio_voice = true
	ac.no_pilot = true
	_check("no_pilot 压过 has_radio_voice（硬规则不可绕过）",
		not ac.can_speak_on_radio(), "")
	ac.no_pilot = false
	_check("有人 + 有无线电 → 可说话", ac.can_speak_on_radio(), "")
	ac.has_radio_voice = false
	_check("等级门关闭 → 不可说话", not ac.can_speak_on_radio(), "")
	ac.free()


# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

## 造一个脱离场景树的 RadioChatter，手工调 _ready + _process 驱动。
## 不进树 → 不依赖引擎主循环，时序完全确定，headless 下也不需要视口。
func _make() -> RadioChatter:
	var r := RadioChatter.new()
	r._ready()
	return r

func _free(r: RadioChatter) -> void:
	r.free()

func _step(r: RadioChatter, frames: int) -> void:
	for i in frames:
		r._process(DT)

func _str_of_len(n: int) -> String:
	var s := ""
	for i in n:
		s += "x"
	return s

func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s %s" % [name, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [name, detail])
