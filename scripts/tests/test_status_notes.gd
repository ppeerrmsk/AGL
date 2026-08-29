extends RefCounted

const _I18N_CATALOG := preload("res://scripts/i18n_catalog.gd")

## 无头验收：升级卡"状态词条脚注"（0729）
##
## 需求：词条说明在 hover / focus 后浮现；介质标签默认只保留技能、稀有度与限定。
## 文案 = StatusEffects.NOTE_I18N_KEY，挂哪张卡 = SurvivorData.status_notes_of。
##
## A 映射：keywords 主路径 / EXTRA 补漏 / OVERRIDE 修个例 / 上限 / 无状态技能不挂
## B 文案：7 个状态词条都有 note key，且 key 在本地化分表里存在
## C UI：基础三卡 / 条件第四卡同尺寸、低档软盘/高档光盘、词条按交互浮现
##
## 运行：godot --headless --path . -- --bench=status_notes（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 升级卡状态词条脚注 ════════")
	_test_mapping()
	_test_i18n_coverage()
	_test_ui_binding()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _notes_of(uid: String) -> Array[String]:
	return SurvivorData.status_notes_of(SurvivorData.upgrade_by_id(uid))


# ── A. 映射 ──────────────────────────────────────────────
func _test_mapping() -> void:
	print("── A. 技能 → 状态词条映射 ──")

	# 主路径：keywords 里写了状态名就自动带脚注
	_check("云中超载 → 超载", _notes_of("cloud_overload") == ["overload"])
	_check("猎杀本能 → 嗜血", _notes_of("skill_kill_bloodlust") == ["bloodlust"])
	_check("对头干扰 → 干扰", _notes_of("head_on_jam") == ["jam"])

	# 顺序按 StatusEffects.DISPLAY_ORDER，不按 keywords 的书写顺序
	_check("惊鸿扩散 → 恐惧",
		_notes_of("fear_squad_spread") == ["fear"])
	_check("恐惧寒意 → 恐惧+减速（DISPLAY_ORDER 序）",
		_notes_of("fear_chills") == ["fear", "slow"],
		str(_notes_of("fear_chills")))

	# EXTRA：施加状态但 keywords 里没写（INVINCIBLE 全靠这条路）
	_check("被弹无敌 → 无敌（keywords 无此词）",
		_notes_of("skill_missile_hit_invul") == ["invincible"])
	_check("复仇 → 无敌+嗜血（EXTRA 与 keywords 合并）",
		_notes_of("squad_revenge") == ["invincible", "bloodlust"],
		str(_notes_of("squad_revenge")))
	_check("暗杀者复仇 → 超载+隐身",
		_notes_of("assassin_revenge") == ["overload", "stealth"],
		str(_notes_of("assassin_revenge")))
	_check("R 闪避 → 无敌", _notes_of("manual_dodge") == ["invincible"])
	_check("幻影 III 魔术 → 无敌（keywords 无此词）",
		_notes_of("sig_mirage3") == ["invincible"])

	# OVERRIDE：keywords 与实际状态语义不符；空数组用于压掉纯主题标签
	_check("MiG-41 近太空冲刺 → 超载（覆盖 stealth 关键词）",
		_notes_of("sig_mig41") == ["overload"],
		str(_notes_of("sig_mig41")))
	for uid in ["vapor_dodge", "ecm_pod", "alt_change_stealth", "sig_a6e", "sig_x09"]:
		_check("%s 的 stealth 仅为主题标签，不挂隐身脚注" % uid,
			_notes_of(uid).is_empty(), str(_notes_of(uid)))
	_check("X-13 只延缓已有负面状态，不挂 JAM 脚注",
		_notes_of("sig_x13").is_empty(), str(_notes_of("sig_x13")))

	# 无状态技能不挂脚注
	_check("纯数值技能不挂脚注（hp_up）", _notes_of("hp_up").is_empty())
	_check("纯数值技能不挂脚注（gun_damage）", _notes_of("gun_damage").is_empty())
	_check("未知 id 安全返回空", SurvivorData.status_notes_of({}).is_empty())

	# 上限：全表任何一条都不超过 STATUS_NOTE_MAX 行
	var over: Array[String] = []
	for u in SurvivorData.UPGRADES:
		if SurvivorData.status_notes_of(u).size() > SurvivorData.STATUS_NOTE_MAX:
			over.append(str(u.get("id", "?")))
	_check("全表脚注行数 ≤ %d" % SurvivorData.STATUS_NOTE_MAX, over.is_empty(), str(over))

	# EXTRA / OVERRIDE 里的 id 必须真实存在（改表时误删/改名会在这里报）
	var ghosts: Array[String] = []
	for uid in SurvivorData.STATUS_NOTE_EXTRA.keys():
		if SurvivorData.upgrade_by_id(str(uid)).is_empty():
			ghosts.append(str(uid))
	for uid in SurvivorData.STATUS_NOTE_OVERRIDE.keys():
		if SurvivorData.upgrade_by_id(str(uid)).is_empty():
			ghosts.append(str(uid))
	_check("EXTRA/OVERRIDE 无幽灵 id", ghosts.is_empty(), str(ghosts))


# ── B. 文案 ──────────────────────────────────────────────
func _test_i18n_coverage() -> void:
	print("── B. 脚注文案 ──")
	var i18n_rows: Dictionary = _I18N_CATALOG.audit().get("rows", {})
	_check("本地化分表可读", not i18n_rows.is_empty())

	var missing_key: Array[String] = []
	var missing_row: Array[String] = []
	for sid in StatusEffects.ALL_IDS:
		var k: String = StatusEffects.note_i18n_key(sid)
		if k == "":
			missing_key.append(sid)
		elif not i18n_rows.has(k):
			missing_row.append(k)
	_check("7 个状态词条都有 note key", missing_key.is_empty(), str(missing_key))
	_check("note key 都在翻译表里", missing_row.is_empty(), str(missing_row))


# ── C. UI ────────────────────────────────────────────────
func _test_ui_binding() -> void:
	print("── C. 卡片挂载 ──")
	var ui := SurvivorUpgradeUI.new()
	ui._ready()   ## 不入树，直接建 UI（脚注只依赖 _build_ui 的静态结构）

	var cards: Array[Dictionary] = [
		SurvivorData.upgrade_by_id("cloud_overload"),
		SurvivorData.upgrade_by_id("hp_up"),
		SurvivorData.upgrade_by_id("squad_revenge"),
	]
	ui.upgrade_selected.connect(func(_upgrade: Dictionary) -> void:
		ui.set_meta("selection_emitted", true))
	ui.populate(cards)

	_check("弹窗入场先锁定全部可见卡", ui._input_locked
		and ui._buttons[0].disabled and ui._buttons[2].disabled
		and ui._buttons[0].mouse_filter == Control.MOUSE_FILTER_STOP)
	ui._on_choice_pressed(0)
	_check("输入保护期点击不会误选", not ui._selection_locked
		and not bool(ui.get_meta("selection_emitted", false)))
	ui._unlock_choice_input(ui._populate_generation)
	_check("保护期结束后恢复选择", not ui._input_locked
		and not ui._buttons[0].disabled and not ui._buttons[2].disabled)
	_check("保护与快速退场时序符合约束",
		SurvivorUpgradeUI.INPUT_UNLOCK_DELAY_S >= 0.75
		and SurvivorUpgradeUI.CONFIRM_INSERT_DURATION_S <= 0.06
		and SurvivorUpgradeUI.CONFIRM_INSERT_SCALE.x >= 0.80
		and SurvivorUpgradeUI.CONFIRM_INSERT_SCALE.y <= 0.06)
	ui._on_choice_pressed(0)
	_check("解锁后点击正常发出选择", ui._selection_locked
		and bool(ui.get_meta("selection_emitted", false)))
	ui.populate(cards)
	ui._unlock_choice_input(ui._populate_generation)

	_check("三卡统一为 240×300 介质", ui._buttons[0].custom_minimum_size == SurvivorUpgradeUI.CARD_SIZE
		and ui._buttons[2].custom_minimum_size == SurvivorUpgradeUI.CARD_SIZE)
	_check("STABLE 使用软盘介质", not ui._media_surfaces[1].optical)
	var stable_badge_style := ui._rarity_badges[1].get_theme_stylebox("normal") as StyleBoxFlat
	var stable_badge_text := ui._rarity_badges[1].get_theme_color("font_color")
	_check("浅色软盘稀有度铭牌保持高对比",
		stable_badge_text.get_luminance() - stable_badge_style.bg_color.get_luminance() >= 0.45
		and ui._rarity_badges[1].get_theme_font_size("font_size") >= 11)
	_check("词条默认不展开", not ui._note_panels[0].visible)
	_check("词条旁注脱离卡面正文层", ui._note_panels[0].get_parent() == ui._note_popup_layer)
	_check("脚注文案非空且是超载那条",
		ui._status_notes[0].text == tr(StatusEffects.note_i18n_key(StatusEffects.OVERLOAD)),
		ui._status_notes[0].text)
	ui._set_card_hovered(0, true)
	_check("hover 后词条浮现", ui._note_panels[0].visible)
	ui._set_card_hovered(0, false)
	_check("hover 离开后词条收回", not ui._note_panels[0].visible)
	_check("无状态的卡没有词条内容", ui._status_notes[1].text == "" and not ui._note_panels[1].visible)
	_check("双状态卡两行脚注",
		ui._status_notes[2].text.count("\n") == 1 and not ui._note_panels[2].visible,
		ui._status_notes[2].text.replace("\n", " | "))
	_check("独立旁注不进入卡列转场元素表",
		ui.get_transition_elements().has(ui._cards[0])
		and not ui.get_transition_elements().has(ui._status_notes[0]))

	_check("升级面板预建四槽，普通三卡只产生标题 + 三卡转场", ui._buttons.size() == 4
		and ui._cards.size() == 4 and ui.get_transition_elements().size() == 4
		and not ui._buttons[3].visible)
	_check("普通 CLASSIFIED 卡需要闪边",
		SurvivorUpgradeUI.should_flash_entry(SurvivorData.upgrade_by_id("f14_squad_lock_slow")))
	_check("低于 CLASSIFIED 的普通卡不闪边",
		not SurvivorUpgradeUI.should_flash_entry(SurvivorData.upgrade_by_id("hp_up")))
	var berserk := SurvivorData.upgrade_by_id("berserk_virus")
	_check("明确代价句使用危险红",
		ui._description_bbcode(berserk, Color.WHITE).contains(ThemeColors.UI_DANGER_RED.to_html(false)))

	# 只有 2 张卡时第三个位置整列隐藏（含脚注）
	ui.populate([cards[0], cards[1]] as Array[Dictionary])
	_check("空位脚注隐藏", ui._status_notes[2].text == "" and not ui._note_panels[2].visible)

	# 复用同一控件：上一轮有脚注的位置这轮换成无状态技能必须清干净
	ui.populate([cards[1], cards[1], cards[1]] as Array[Dictionary])
	_check("换卡后旧脚注不残留",
		ui._status_notes[0].text == "" and ui._status_notes[2].text == ""
		and not ui._note_panels[0].visible and not ui._note_panels[2].visible)

	var airframe_bonus := SurvivorData.upgrade_by_id("speed_up").duplicate(true)
	airframe_bonus["airframe_bonus_offer"] = true
	airframe_bonus["airframe_bonus_axis"] = "knight"
	var four_cards: Array[Dictionary] = [cards[0], cards[1], cards[2], airframe_bonus]
	ui.populate(four_cards)
	_check("机体适配命中时显示第四张并加入转场",
		ui._buttons[3].visible and ui.get_transition_elements().size() == 5)
	_check("第四张显示机体适配来源且保留自身骑士轴色",
		ui._source_badges[3].visible
		and ui._source_badges[3].text.contains(tr("AIRFRAME_AFFINITY_CARD_BADGE"))
		and SurvivorData.axis_of_upgrade(airframe_bonus) == SurvivorData.AXIS_KNIGHT)
	_check("前三张不误显示机体适配来源",
		not ui._source_badges[0].visible and not ui._source_badges[1].visible
		and not ui._source_badges[2].visible)

	ui.free()
