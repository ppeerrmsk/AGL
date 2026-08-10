extends RefCounted

const _I18N_CATALOG := preload("res://scripts/i18n_catalog.gd")

## 无头验收：升级卡"状态词条脚注"（0729）
##
## 需求：玩家在选卡时就该知道"这条技能给的超载 / 嗜血本身干什么"，
## 而不是选完一局靠猜。脚注文案 = StatusEffects.NOTE_I18N_KEY，
## 挂哪张卡 = SurvivorData.status_notes_of。
##
## A 映射：keywords 主路径 / EXTRA 补漏 / OVERRIDE 修个例 / 上限 / 无状态技能不挂
## B 文案：7 个状态词条都有 note key，且 key 在本地化分表里存在
## C UI：populate 后有状态的卡显示脚注、无状态的卡隐藏、空位一律隐藏
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
	ui.populate(cards)

	_check("有状态的卡显示脚注", ui._status_notes[0].visible)
	_check("脚注文案非空且是超载那条",
		ui._status_notes[0].text == tr(StatusEffects.note_i18n_key(StatusEffects.OVERLOAD)),
		ui._status_notes[0].text)
	_check("无状态的卡隐藏脚注", not ui._status_notes[1].visible)
	_check("双状态卡两行脚注",
		ui._status_notes[2].visible and ui._status_notes[2].text.count("\n") == 1,
		ui._status_notes[2].text.replace("\n", " | "))
	_check("脚注随整列进入进出场元素表",
		ui.get_transition_elements().has(ui._cards[0])
		and not ui.get_transition_elements().has(ui._status_notes[0]))

	var signature := SurvivorData.upgrade_by_id("sig_f15").duplicate(true)
	signature["signature_offer"] = true
	signature["signature_aircraft_name_key"] = "AIRCRAFT_F15_NAME"
	ui.populate([cards[0], cards[1], cards[2], signature] as Array[Dictionary])
	_check("第四槽完整显示且进入转场",
		ui._buttons[3].visible and ui._cards[3].visible
		and ui.get_transition_elements().size() == 5
		and ui.get_transition_elements().has(ui._cards[3]))
	_check("四卡布局统一放大", ui._buttons[0].custom_minimum_size == Vector2(240, 180)
		and ui._buttons[3].custom_minimum_size == Vector2(240, 180))
	_check("专属卡显示专属徽章", ui._axis_badges[3].text == tr("UPGRADE_SIGNATURE_BADGE"))
	_check("普通 CLASSIFIED 卡需要闪边",
		SurvivorUpgradeUI.should_flash_entry(SurvivorData.upgrade_by_id("f14_squad_lock_slow")))
	_check("低于 CLASSIFIED 的普通卡不闪边",
		not SurvivorUpgradeUI.should_flash_entry(SurvivorData.upgrade_by_id("hp_up")))
	_check("专属卡闪边使用洋红优先色",
		SurvivorUpgradeUI.entry_flash_color(signature) == SurvivorUpgradeUI.SIG_FRAME_COLOR)

	# 只有 2 张卡时第三个位置整列隐藏（含脚注）
	ui.populate([cards[0], cards[1]] as Array[Dictionary])
	_check("空位脚注隐藏", not ui._status_notes[2].visible)

	# 复用同一控件：上一轮有脚注的位置这轮换成无状态技能必须清干净
	ui.populate([cards[1], cards[1], cards[1]] as Array[Dictionary])
	_check("换卡后旧脚注不残留",
		not ui._status_notes[0].visible and not ui._status_notes[2].visible)

	ui.free()
