extends RefCounted

## 全量技能审计：145 条逐项验证“配置 → apply/运行时消费点 → 玩家文案”。
##
## 直接数值/字段技能会真的应用到一架挂满可选装备的最小测试机，并比较应用前后快照；
## skill_flag 事件技能验证正式运行时消费点，避免“表里有、游戏里没人读”的假技能。
## 运行：bench\run.cmd skill_audit 1 180

const RUNTIME_CONSUMER_FILES: Array[String] = [
	"res://scripts/aircraft.gd",
	"res://scripts/aircraft/aircraft_flares.gd",
	"res://scripts/aircraft/aircraft_weapons.gd",
	"res://scripts/missile_manager.gd",
	"res://scripts/rts/squad_command_controller.gd",
	"res://scripts/survivor/dock_point.gd",
	"res://scripts/survivor/skill_hooks.gd",
	"res://scripts/survivor/survivor_mode.gd",
	"res://scripts/survivor/survivor_spawner.gd",
]

## 四条计数缩放技能的消费点与定义同在 survivor_data.gd；不能用“跨文件字面量”规则检查。
const DATA_LOCAL_CONSUMERS: Array[String] = [
	"veteran_hp", "speed_by_knight", "ew_expert", "weapon_master",
]

## X-02 是一次性武器入库动作，不走 apply_upgrade match。
const ONESHOT_IDS: Array[String] = ["sig_x02"]

## 这些词把实现细节泄漏给玩家，卡片文案中禁止出现。
const INTERNAL_TEXT_TOKENS: Array[String] = ["dps_max", "dps_min", "完整 DPS"]

var _pass: int = 0
var _fail: int = 0


func run() -> void:
	print("\n════════ 全量技能审计（逐条 apply / 消费点 / 玩家文案） ════════")
	var translations := _load_translations()
	var apply_source := FileAccess.get_file_as_string("res://scripts/survivor/survivor_player.gd")
	var consumer_source := ""
	for path in RUNTIME_CONSUMER_FILES:
		consumer_source += "\n" + FileAccess.get_file_as_string(path)
	var mode_source := FileAccess.get_file_as_string("res://scripts/survivor/survivor_mode.gd")
	var seen: Dictionary = {}
	for upgrade in SurvivorData.UPGRADES:
		_audit_one(upgrade, translations, apply_source, consumer_source, mode_source, seen)
	_check("全表数量 = 145", SurvivorData.UPGRADES.size() == 145,
		"got %d" % SurvivorData.UPGRADES.size())
	_check("技能 ID 无重复", seen.size() == SurvivorData.UPGRADES.size(),
		"unique=%d total=%d" % [seen.size(), SurvivorData.UPGRADES.size()])
	_test_regression_contracts(mode_source)
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _audit_one(upgrade: Dictionary, translations: Dictionary,
		apply_source: String, consumer_source: String, mode_source: String,
		seen: Dictionary) -> void:
	var uid := str(upgrade.get("id", ""))
	var stat := str(upgrade.get("stat", ""))
	var errors: Array[String] = []
	if uid == "":
		errors.append("缺 id")
	elif seen.has(uid):
		errors.append("重复 id")
	else:
		seen[uid] = true
	if stat == "":
		errors.append("缺 stat")
	if int(upgrade.get("max_stacks", 0)) <= 0:
		errors.append("max_stacks <= 0")
	var rarity := SurvivorData.get_rarity(upgrade)
	if rarity < SurvivorData.Rarity.STABLE or rarity > SurvivorData.Rarity.NEXT_GEN:
		errors.append("稀有度越界")

	var name_key := str(upgrade.get("name", ""))
	var desc_key := str(upgrade.get("desc", ""))
	for key in [name_key, desc_key]:
		if not translations.has(key):
			errors.append("缺三语 key %s" % key)
			continue
		var row: Array = translations[key]
		if row.size() < 3 or str(row[0]) == "" or str(row[1]) == "" or str(row[2]) == "":
			errors.append("三语不完整 %s" % key)
	if translations.has(desc_key):
		var desc_row: Array = translations[desc_key]
		for text in desc_row:
			for token in INTERNAL_TEXT_TOKENS:
				if str(text).contains(token):
					errors.append("玩家文案含实现词 %s" % token)

	if stat == "skill_flag":
		var has_consumer := DATA_LOCAL_CONSUMERS.has(uid) \
			or consumer_source.contains('"%s"' % uid)
		if not has_consumer:
			errors.append("skill_flag 无运行时消费点")
	elif ONESHOT_IDS.has(uid):
		if not mode_source.contains('"%s"' % uid) or not mode_source.contains("_dispatch_sig_oneshot"):
			errors.append("一次性技能无 dispatch")
	else:
		if not apply_source.contains('\t\t"%s":' % stat):
			errors.append("stat 无 apply 分支")
		else:
			var sp := SurvivorPlayer.new()
			var ac := _make_fully_equipped_aircraft()
			if ac == null:
				errors.append("最小测试机创建失败")
			else:
				sp.aircraft = ac
				var before := _fingerprint(ac, sp)
				sp.apply_upgrade(upgrade)
				var after := _fingerprint(ac, sp)
				if before == after:
					errors.append("apply 后无可观察字段变化")
				ac.free()
			sp.free()

	_check("[%s] 配置/生效/文案" % uid, errors.is_empty(), "; ".join(errors))


func _make_fully_equipped_aircraft() -> Aircraft:
	var ac := Aircraft.new()
	ac.team = CombatUnit.TEAM_PLAYER
	var p := AircraftParams.new()
	p.max_hp = 100.0
	p.max_speed = 1600.0
	p.cruise_speed = 900.0
	p.acceleration = 50.0
	p.deceleration = 80.0
	p.max_g = 9.0
	p.max_g_structural = 12.0
	p.roll_rate = 4.0
	p.radar_range = 2500.0
	p.radar_half_angle = 30.0
	p.lock_time = 3.0
	p.gun = GunParams.new()
	p.gun.bullet_damage = 30.0
	p.gun.max_ammo = 100
	p.gun.max_range = 1000.0
	p.gun.spread_angle = 2.0
	p.gun.fire_cone_half_angle = 10.0
	p.gun.lifetime = 2.0
	p.missile = MissileParams.new()
	p.missile.max_count = 4
	p.missile.max_g = 35.0
	p.missile.max_range_rear = 5000.0
	p.missile.cooldown = 5.0
	p.missile.motor_burn_time = 4.0
	p.missile.motor_acceleration = 100.0
	p.missile.seeker_fov = 60.0
	p.secondary_missile = MissileParams.new()
	p.secondary_missile.max_count = 2
	p.secondary_missile.max_range_rear = 1800.0
	p.secondary_missile.lock_max_range_px = 900.0
	p.flare = FlareParams.new()
	p.flare.max_flares = 8
	p.rocket = RocketParams.new()
	p.torpedo = TorpedoParams.new()
	p.loyal_wingman = LoyalWingmanParams.new()
	p.loyal_wingman.drone_aircraft_params = AircraftParams.new()
	p.loyal_wingman.drone_aircraft_params.gun = GunParams.new()
	p.combat = CombatParams.new()
	var railgun := RailgunEquipment.new()
	railgun.equipment_kind = "railgun"
	var laser := LaserEquipment.new()
	laser.equipment_kind = "laser"
	p.equipment = [railgun, laser]
	ac.params = p
	ac.hp = p.max_hp
	ac.ammo = p.gun.max_ammo
	ac.missiles_remaining = p.missile.max_count
	ac.secondary_missiles_remaining = p.secondary_missile.max_count
	ac.flares_remaining = p.flare.max_flares
	return ac


func _fingerprint(ac: Aircraft, sp: SurvivorPlayer) -> String:
	var lines: Array[String] = []
	_append_primitives(lines, "ac.", ac)
	_append_primitives(lines, "sp.", sp)
	_append_primitives(lines, "p.", ac.params)
	_append_primitives(lines, "gun.", ac.params.gun)
	_append_primitives(lines, "missile.", ac.params.missile)
	_append_primitives(lines, "secondary.", ac.params.secondary_missile)
	_append_primitives(lines, "flare.", ac.params.flare)
	_append_primitives(lines, "rocket.", ac.params.rocket)
	_append_primitives(lines, "torpedo.", ac.params.torpedo)
	_append_primitives(lines, "wingman.", ac.params.loyal_wingman)
	_append_primitives(lines, "drone_p.", ac.params.loyal_wingman.drone_aircraft_params)
	_append_primitives(lines, "drone_gun.", ac.params.loyal_wingman.drone_aircraft_params.gun)
	for eq in ac.params.equipment:
		_append_primitives(lines, "%s." % eq.equipment_kind, eq)
	lines.append("evasion_modifiers=%s" % var_to_str(ac.evasion_modifiers))
	lines.append("children=%d" % ac.get_child_count())
	lines.sort()
	return "\n".join(lines)


func _append_primitives(out: Array[String], prefix: String, obj: Object) -> void:
	if obj == null:
		return
	for info in obj.get_property_list():
		var name := str(info.get("name", ""))
		if name == "" or name == "script":
			continue
		var value: Variant = obj.get(name)
		var t := typeof(value)
		if t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
				TYPE_VECTOR2, TYPE_COLOR]:
			out.append("%s%s=%s" % [prefix, name, str(value)])


func _load_translations() -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open("res://i18n/translations.csv", FileAccess.READ)
	if file == null:
		return result
	var first := true
	while not file.eof_reached():
		var row := file.get_csv_line()
		if first:
			first = false
			continue
		if row.size() >= 4 and row[0] != "":
			result[row[0]] = [row[1], row[2], row[3]]
	return result


func _test_regression_contracts(mode_source: String) -> void:
	print("── 跨技能回归契约 ──")
	var replay_pos := mode_source.find("func _replay_player_upgrades")
	var replay_tail := mode_source.substr(replay_pos, 2400) if replay_pos >= 0 else ""
	_check("换型重放先重置玩家级 XP 乘区",
		replay_tail.contains("survivor_player.xp_multiplier = 1.0")
		and replay_tail.contains("survivor_player.sig_xp_mult = 1.0"), "")
	_check("扰乱投弹真实 JAM 时长 = 3s",
		is_equal_approx(SkillHooks.FLARE_AOE_JAM_DURATION, 3.0),
		"got %.1f" % SkillHooks.FLARE_AOE_JAM_DURATION)
	var fear := SurvivorData.upgrade_by_id("fear_on_lock")
	_check("凝视压迫阈值 = 4s（次世代收益目标）",
		is_equal_approx(float(fear.get("value", 0.0)), 4.0), str(fear))
	_check("局内永久 HP 在进化重放中恢复",
		replay_tail.contains("head_on_perma_hp_gained")
		and replay_tail.contains("bloodlust_perma_hp_gained"), "")
	_check("无败之鹰保持基线 = 满血门槛 / +20%",
		is_equal_approx(Aircraft.SIG_F15_HP_RATIO, 1.0)
		and is_equal_approx(Aircraft.SIG_F15_BONUS_MULT, 1.20), "")
	_check("鸭嘴兽厨房保持基线 = 2 HP/s",
		is_equal_approx(AfterburnerCharge.SIG_SU34_HEAL_PER_SEC, 2.0), "")
	_check("引渡人保持基线 = 5s 隐身",
		is_equal_approx(SkillHooks.SIG_X77_STEALTH_DURATION, 5.0), "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s%s" % [label, " — " + detail if detail != "" else ""])
