extends RefCounted

## 无头行为验收：BOSS 阶段闸门 + 全场撤离（spec survivor-loop §3）
##
## A 闸门真源：survivor_mode.is_boss_phase()（BOSS 解锁即为真，不必等玩家选中 BOSS 圈）
## B 画面内残余敌机 → 物理撤离（清目标 + 出界航线 + AB），不瞬消
## C 画面外残余敌机 → 立即静默 free
## D 豁免名单：BOSS 本体/自带单位、事件层自管的王牌支援/宿敌、停在甲板上的舰载机
## E 舰船与地面单位一概不动（"战区里的船保留"）
##
## 运行：godot --headless --path . -- --bench=boss_phase（或 --bench=all）

var _pass := 0
var _fail := 0
var _root: StubMode = null
const EXPECTED_ASSERTIONS: int = 29


## 最小 SurvivorMode 替身：撤离扫描用 get_children / is_world_pos_visible / is_boss_phase，
## 击杀结算（_detect_kills）另用 upgrade_stacks / _player_profile / _bench_mode / archive_enabled
class StubMode extends Node2D:
	var boss_phase := false
	var everything_visible := true
	var game_time := 600.0
	var upgrade_stacks: Dictionary = {}
	var _player_profile = null
	var _bench_mode := true      ## 跳过 HUD 表现层
	var hud = null
	var _tutorial = null
	var afterburner_charge := AfterburnerCharge.new()

	func is_boss_phase() -> bool:
		return boss_phase

	func is_world_pos_visible(_world_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return everything_visible

	## 关掉生涯档案写入：测试不碰 user://career.cfg
	func archive_enabled() -> bool:
		return false


func run() -> void:
	print("\n════════ BOSS 阶段闸门 + 全场撤离 ════════")
	_test_gate_follows_unlock()
	_test_visible_enemy_evacuates()
	_test_offscreen_enemy_freed()
	_test_exemptions()
	_test_ships_untouched()
	_test_boss_uav_grants_no_reward()
	_test_csg_fa18_hangar_cap()
	_test_boss_phase_blocks_all_kill_xp()
	# GDScript 运行时错误只会中断当前测试函数；没有完整性门时会被误报为 0 fail。
	var executed_assertions: int = _pass + _fail
	if executed_assertions != EXPECTED_ASSERTIONS:
		_fail += 1
		print("  ✗ 验收未完整执行 assertions=%d expected=%d" % [
			executed_assertions, EXPECTED_ASSERTIONS])
	if _root != null:
		_root.free()
		_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


# ══════════════════════════════════════════════
#  夹具
# ══════════════════════════════════════════════

## _root 不挂进场景树 → 子节点不触发 _ready（呼号分配/雷达代理与本测试无关）
func _mk_env() -> SurvivorSpawner:
	if _root != null:
		_root.free()
	_root = StubMode.new()
	var spawner := SurvivorSpawner.new()
	spawner.mode = _root
	spawner.player_aircraft = _mk_ac(Vector2.ZERO, CombatUnit.TEAM_PLAYER)
	_root.add_child(spawner.player_aircraft)
	return spawner


func _mk_ac(pos: Vector2, team: int) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = team
	ac.altitude = 6000.0
	ac.global_position = pos
	ac.hp = 100.0
	var p := AircraftParams.new()
	ac.params = p
	return ac


## 场上一架敌机（带 AI），可指定 category
func _mk_enemy(pos: Vector2, category: String = "") -> Aircraft:
	var ac := _mk_ac(pos, CombatUnit.TEAM_HOSTILE)
	if category != "":
		ac.set_meta("category", category)
	var ai := AIController.new()
	ai.aircraft = ac
	ac.add_child(ai)
	_root.add_child(ac)
	return ac


func _get_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null


# ══════════════════════════════════════════════
#  A. 闸门真源
# ══════════════════════════════════════════════

func _test_gate_follows_unlock() -> void:
	print("── A. 闸门跟随 mode.is_boss_phase()（BOSS 解锁即停摆） ──")
	var spawner := _mk_env()
	_check("未解锁 → 闸门关（照常刷怪）", not spawner._is_boss_phase())
	_root.boss_phase = true
	_check("BOSS 解锁 → 闸门开（PRE_STAGE 就停刷，不等玩家选中 BOSS 圈）",
		spawner._is_boss_phase())
	spawner.free()


# ══════════════════════════════════════════════
#  B. 画面内 → 物理撤离
# ══════════════════════════════════════════════

func _test_visible_enemy_evacuates() -> void:
	print("── B. 画面内残余敌机：清目标 + 出界航线 + AB，不瞬消 ──")
	var spawner := _mk_env()
	_root.boss_phase = true
	_root.everything_visible = true
	var enemy := _mk_enemy(Vector2(1200.0, 800.0), "zone_air")
	enemy.is_mission_target = true

	spawner._update_boss_phase_purge(2.0)

	_check("不在画面内消失（仍存活）", not enemy.is_queued_for_deletion())
	_check("已打撤离标记", enemy.has_meta("boss_evac"))
	_check("TGT 标记已摘", not enemy.is_mission_target)
	_check("开加力拉出", enemy.is_afterburner)
	var ai := _get_ai(enemy)
	var half := MapBoundary.world_half_px()
	var wp_ok := ai != null and ai.waypoints.size() == 1 \
			and (absf(ai.waypoints[0].x) > half or absf(ai.waypoints[0].y) > half)
	_check("航线指向图外出界点", wp_ok,
		"wp=%s half=%.0f" % [ai.waypoints[0].round() if (ai and ai.waypoints.size() > 0) else "无", half])
	_check("状态回 PATROL（不再咬玩家）",
		ai != null and ai._state == AIController.AIState.PATROL)
	spawner.free()


# ══════════════════════════════════════════════
#  C. 画面外 → 立即释放
# ══════════════════════════════════════════════

func _test_offscreen_enemy_freed() -> void:
	print("── C. 画面外残余敌机：立即静默 free（不给 XP） ──")
	var spawner := _mk_env()
	_root.boss_phase = true
	_root.everything_visible = false
	var enemy := _mk_enemy(Vector2(9000.0, 0.0), "zone_air")

	spawner._update_boss_phase_purge(2.0)

	_check("画面外即释放", enemy.is_queued_for_deletion())
	_check("标 xp_granted（不被 _detect_kills 误判为击杀）",
		enemy.has_meta("xp_granted"))
	spawner.free()


# ══════════════════════════════════════════════
#  D. 豁免名单
# ══════════════════════════════════════════════

func _test_exemptions() -> void:
	print("── D. 豁免：BOSS 自带单位 / 事件自管中队 / 甲板停机 ──")
	var spawner := _mk_env()
	_root.boss_phase = true
	_root.everything_visible = false   # 最严条件：画面外也不许被 free
	var boss := _mk_enemy(Vector2(500.0, 0.0), "boss")
	var goose_uav := _mk_enemy(Vector2(600.0, 0.0), "boss_mother_goose_uav")
	var csg_air := _mk_enemy(Vector2(700.0, 0.0), "boss_csg_aircraft")
	var ace := _mk_enemy(Vector2(800.0, 0.0), "ace_support")
	var orion := _mk_enemy(Vector2(900.0, 0.0), "ace_nemesis")
	var parked := _mk_enemy(Vector2(1000.0, 0.0), "carrier_escort")
	parked.set_meta("parent_carrier", _root)

	spawner._update_boss_phase_purge(2.0)

	for pair in [[boss, "BOSS 本体"], [goose_uav, "Goose 蜂群 UAV"],
			[csg_air, "CSG 舰载机"], [ace, "王牌支援中队"], [orion, "宿敌 Orion"],
			[parked, "甲板停机"]]:
		var ac: Aircraft = pair[0]
		_check("%s 不被清场" % str(pair[1]),
			not ac.is_queued_for_deletion() and not ac.has_meta("boss_evac"))
	spawner.free()


# ══════════════════════════════════════════════
#  E. 舰船 / 地面单位一概不动
# ══════════════════════════════════════════════

func _test_ships_untouched() -> void:
	print("── E. 战区里的船保留（撤离只针对飞机） ──")
	var spawner := _mk_env()
	_root.boss_phase = true
	_root.everything_visible = false
	var ship: NavalUnit = NavalUnit.new()
	ship.team = CombatUnit.TEAM_HOSTILE
	ship.global_position = Vector2(2000.0, 2000.0)
	ship.set_meta("category", "zone_naval")
	_root.add_child(ship)
	var sam: GroundUnit = GroundUnit.new()
	sam.team = CombatUnit.TEAM_HOSTILE
	sam.global_position = Vector2(2200.0, 2100.0)
	_root.add_child(sam)

	spawner._update_boss_phase_purge(2.0)

	_check("战区舰船原样保留", not ship.is_queued_for_deletion() and not ship.has_meta("boss_evac"))
	_check("地面单位原样保留", not sam.is_queued_for_deletion() and not sam.has_meta("boss_evac"))
	spawner.free()


# ══════════════════════════════════════════════
#  F. BOSS 自带 UAV（Mother Goose 蜂群 / MQ-X）击杀不计价
# ══════════════════════════════════════════════

func _test_boss_uav_grants_no_reward() -> void:
	print("── F. 无限补充的 BOSS 无人机：不给 XP、不给对头永久 +max_hp ──")
	var spawner := _mk_env()
	var sp := SurvivorPlayer.new()
	sp.level = 20
	sp.aircraft = spawner.player_aircraft
	spawner.survivor_player = sp

	var base_hp: float = spawner.player_aircraft.params.max_hp

	_mk_dead_uav("boss_mother_goose_uav", true, spawner.player_aircraft)
	spawner._detect_kills()
	_check("蜂群 UAV 击杀 XP = 0", sp.total_xp_gained == 0,
		"total_xp=%d" % sp.total_xp_gained)
	_check("蜂群 UAV 不给对头永久 +max_hp",
		is_equal_approx(spawner.player_aircraft.params.max_hp, base_hp),
		"max_hp=%.0f（基线 %.0f）" % [spawner.player_aircraft.params.max_hp, base_hp])
	_check("仍计入击杀数（只是不计价）", spawner.kill_count == 1,
		"kill_count=%d" % spawner.kill_count)

	# 对照组：同样是 uav、同样对头击杀，只是没打 no_kill_reward
	_mk_dead_uav("", false, spawner.player_aircraft)
	spawner._detect_kills()
	_check("普通 MQ-109 照常给 XP", sp.total_xp_gained > 0,
		"total_xp=%d" % sp.total_xp_gained)
	_check("普通 MQ-109 照常给对头永久 +max_hp",
		spawner.player_aircraft.params.max_hp > base_hp,
		"max_hp=%.0f（基线 %.0f）" % [spawner.player_aircraft.params.max_hp, base_hp])
	sp.free()
	spawner.free()


# ══════════════════════════════════════════════
#  G. CSG 机库上限：整场最多 8 架 F/A-18，弹完不再补
# ══════════════════════════════════════════════

func _test_csg_fa18_hangar_cap() -> void:
	print("── G. CSG 舰载机机库上限（反「拖时间无限刷」）──")
	_check("累计上限 = 8 架", CarrierStrikeGroup.FA18_TOTAL_CAP == 8,
		"cap=%d" % CarrierStrikeGroup.FA18_TOTAL_CAP)

	var csg := CarrierStrikeGroup.new()
	var cv: NavalUnit = NavalUnit.new()
	cv.team = CombatUnit.TEAM_HOSTILE
	_root.add_child(cv)
	csg._cv = cv
	# 机库已空：唯一守卫点在 _launch_fa18 —— 直接调它必须原地返回（不生成、不计数）
	csg._fa18_launched_total = CarrierStrikeGroup.FA18_TOTAL_CAP
	csg._launch_fa18(0.0)
	_check("上限用尽后 _launch_fa18 不再产机",
		csg._fa18_alive.is_empty() and csg._fa18_launched_total == CarrierStrikeGroup.FA18_TOTAL_CAP,
		"alive=%d total=%d" % [csg._fa18_alive.size(), csg._fa18_launched_total])
	# 定期弹射 tick 同样被挡（击落后不退还名额 —— 不许"打一架补一架"）
	csg._fa18_periodic_timer = 0.01
	csg._update_fa18_periodic_launch(10.0)
	_check("定期弹射 tick 在上限后静默停摆",
		csg._fa18_launched_total == CarrierStrikeGroup.FA18_TOTAL_CAP,
		"total=%d" % csg._fa18_launched_total)
	cv.free()


# ══════════════════════════════════════════════
#  H. BOSS 阶段开启后，全目标统一不产 XP
# ══════════════════════════════════════════════

func _test_boss_phase_blocks_all_kill_xp() -> void:
	print("── H. BOSS 阶段统一 XP 闸门（空中 + 地面）──")
	var spawner := _mk_env()
	var sp := SurvivorPlayer.new()
	sp.level = 5
	sp.aircraft = spawner.player_aircraft
	spawner.survivor_player = sp
	_root.boss_phase = true

	# 普通敌机没有 no_kill_reward；仍必须被阶段总闸挡住。
	_mk_dead_uav("", false, spawner.player_aircraft)
	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	ground.is_destroyed = true
	ground.set_meta("kill_attacker_team", CombatUnit.TEAM_PLAYER)
	_root.add_child(ground)
	spawner._detect_kills()

	_check("BOSS 阶段普通敌机 XP = 0", sp.total_xp_gained == 0,
		"total_xp=%d" % sp.total_xp_gained)
	_check("BOSS 阶段地面目标 XP = 0", sp.total_xp_gained == 0,
		"total_xp=%d" % sp.total_xp_gained)
	_check("XP 封锁不吞击杀内战斗语义", spawner.kill_count == 2,
		"kill_count=%d" % spawner.kill_count)
	sp.free()
	spawner.free()


## 造一架"刚被玩家对头击落"的 UAV 尸体（_detect_kills 的输入形态）
func _mk_dead_uav(category: String, no_reward: bool, killer: Aircraft) -> Aircraft:
	var ac := _mk_ac(Vector2(300.0, 0.0), CombatUnit.TEAM_HOSTILE)
	ac.params.max_hp = 100.0
	ac.is_destroyed = true
	ac.set_meta("enemy_type", "uav")
	if category != "":
		ac.set_meta("category", category)
	if no_reward:
		ac.set_meta("no_kill_reward", true)
	# 对头击杀归因（触发 _check_head_on_kill_bonus 的永久 +max_hp）
	ac.set_meta("kill_attacker_team", CombatUnit.TEAM_PLAYER)
	ac.set_meta("kill_attacker_id", killer.get_instance_id())
	ac.set_meta("kill_head_on_dot", 1.0)
	ac.set_meta("kill_attacker_aim", 1.0)
	_root.add_child(ac)
	return ac
