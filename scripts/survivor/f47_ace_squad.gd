## F-47 王牌狙击小队（WRAITH 中队）
## 继承 AceSquad 基类，定义 F-47 特有的配置和行为：
## - 光学隐形
## - 协同齐射
## - KNIGHT×2 / SNIPER×2 的二二角色分工（基类 _apply_role 落地）
## - **队级战术状态机** PERCH→BRACKET→PRESS→RESET（spec bosses/wraith-squadron §2.3）
##
## 战术状态机住在独立模块 [wraith_tactics.gd]，本类只做持有与转发 ——
## 按 spec §4 的决定，它是 **Wraith 专属窄井**，不下沉为通用小队战术模块。
## 若将来出现第二个需要同款编排的王牌中队，再考虑抽取。
class_name F47AceSquad
extends AceSquad

## 队级战术状态机（PURSUIT 之内运转；tier 层只管是否交战/是否隐形）
var tactics: WraithTactics = null

# ── 通关强化层：两架可选 YF-23 后方潜伏狙击支援（不进入 BOSS members/HUD/胜利判定）──
const YF23_SUPPORT_TRAILING_PX: float = 1800.0
const YF23_SUPPORT_MIN_PLAYER_DISTANCE_PX: float = 5000.0
const YF23_SUPPORT_LATERAL_PX: float = 700.0
var _progression_create_enemy_func: Callable
var _progression_squads_ref: Array[Squad] = []
var _progression_support: Array[Aircraft] = []
var _progression_support_spawned: bool = false
var _member_down_radio_played: bool = false

func _init() -> void:
	squad_size = SurvivorData.F47_SQUAD_SIZE
	intro_duration = SurvivorData.F47_INTRO_DURATION
	intro_pass_dist = SurvivorData.F47_INTRO_PASS_DIST
	callsign_prefix = "WRAITH"
	display_name = "WRAITH SQUADRON"
	bgm_track = "boss"
	enemy_type = 15  # EnemyType.F47
	# 上述 display_name / callsign_prefix / bgm_track 会被 BossRegistry.instantiate 再覆盖，
	# 这里留着是给 Debug 面板等直接 `F47AceSquad.new()` 绕过 registry 的路径兜底

	# 光学隐形
	cloak_enabled = true
	cloak_cycle = SurvivorData.F47_CLOAK_CYCLE
	cloak_duration = SurvivorData.F47_CLOAK_DURATION
	cloak_fade = SurvivorData.F47_CLOAK_FADE
	cloak_cycle_jitter = SurvivorData.F47_CLOAK_CYCLE_JITTER
	cloak_emergency_enabled = false  # Wraith 的 60s CD 不允许来袭导弹绕过

	# 距离
	standoff_radius_min = SurvivorData.F47_STANDOFF_RADIUS_MIN
	standoff_radius_max = SurvivorData.F47_STANDOFF_RADIUS_MAX

## 保存工厂与 squad 容器；四架 BOSS 本体仍完全走 AceSquad 原生成路径。
func spawn(scene_root: Node, aircraft_scene: PackedScene, create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		squads: Array[Squad]) -> void:
	_progression_create_enemy_func = create_enemy_func
	_progression_squads_ref = squads
	_member_down_radio_played = false
	super.spawn(scene_root, aircraft_scene, create_enemy_func, player, bullet_mgr, missile_mgr, squads)

## WRAITH 本战首次减员：由被击毁成员本人用真实呼号说完半句，之后闭锁。
func _on_member_destroyed(member: Aircraft) -> void:
	if _member_down_radio_played or member == null or not is_instance_valid(member):
		return
	if _scene_root == null or not is_instance_valid(_scene_root):
		return
	var radio = _scene_root.get("_radio")
	if radio != null and is_instance_valid(radio) \
			and radio.say_unit("wraith_member_down", member):
		_member_down_radio_played = true

static func support_count_for_progression(defeat_count: int) -> int:
	return 2 if defeat_count >= 1 else 0

## 沿“玩家 → Wraith 队形中心”轴继续向后布置支援，不再以玩家位置为出生中心。
## 最小离玩家 5000px（10km），避免 Wraith 在近处时支援贴脸闪现。
static func support_spawn_positions(player_pos: Vector2, wraith_center: Vector2,
		fallback_away: Vector2) -> Array[Vector2]:
	var away := wraith_center - player_pos
	if away.length_squared() < 1.0:
		away = fallback_away
	if away.length_squared() < 1.0:
		away = Vector2.UP
	away = away.normalized()
	var base_distance := maxf(player_pos.distance_to(wraith_center) + YF23_SUPPORT_TRAILING_PX,
		YF23_SUPPORT_MIN_PLAYER_DISTANCE_PX)
	var base := player_pos + away * base_distance
	var lateral := Vector2(-away.y, away.x)
	return [
		base - lateral * YF23_SUPPORT_LATERAL_PX,
		base + lateral * YF23_SUPPORT_LATERAL_PX,
	]

## 支援机使用普通飞机的锁定规则；“潜伏”是出生几何，不是永久免锁。
static func configure_progression_support_aircraft(ac: Aircraft, index: int) -> void:
	ac.callsign = "BLACKWIDOW-%02d" % (index + 1)
	ac.prefer_gun_mode = false
	ac.set_target_tier(CombatUnit.AltitudeTier.HIGH)
	ac.set_meta(&"category", "boss_support")
	ac.set_meta(&"skip_far_cleanup", true)
	ac.set_meta(&"no_kill_reward", true)
	if ac.has_meta(&"lock_immune_override"):
		ac.remove_meta(&"lock_immune_override")

## 演出结束、正式接战时才生成：因此两架支援机不会混进 Wraith 四机登场分镜。
func engage() -> void:
	super.engage()
	if not _progression_support_spawned and support_count_for_progression(prior_defeats) > 0:
		_spawn_progression_support()

func _spawn_progression_support() -> void:
	_progression_support_spawned = true
	if not _progression_create_enemy_func.is_valid() or _player == null or not is_instance_valid(_player):
		return
	var wraith_center := Vector2.ZERO
	var live_member_count := 0
	for member in members:
		if member != null and is_instance_valid(member) and not member.is_destroyed:
			wraith_center += member.global_position
			live_member_count += 1
	var player_forward := Vector2(sin(_player.heading), -cos(_player.heading))
	if live_member_count > 0:
		wraith_center /= float(live_member_count)
	else:
		wraith_center = _player.global_position + player_forward * YF23_SUPPORT_MIN_PLAYER_DISTANCE_PX
	var spawn_positions := support_spawn_positions(
		_player.global_position, wraith_center, player_forward)
	var support_squad := Squad.new()
	for i in range(support_count_for_progression(prior_defeats)):
		var pos: Vector2 = spawn_positions[i]
		pos = MapBoundary.clamp_inside(pos, 800.0)
		var to_player := (_player.global_position - pos).normalized()
		var heading_deg := rad_to_deg(atan2(to_player.x, -to_player.y))
		var ac: Aircraft = _progression_create_enemy_func.call(
				SurvivorSpawner.EnemyType.YF23, pos, heading_deg)
		if ac == null:
			continue
		configure_progression_support_aircraft(ac, i)
		var ai: AIController = ac._get_ai_controller()
		if ai != null:
			ai.squad = support_squad
			ai.squad_index = i
			ai.boss_attacker = true
			ai.enable_combat = true
			if ai.acquire_target(_player, AIController.TargetSource.TS_BOSS,
					"Wraith progression YF-23"):
				ai.enter_engage_state()
		if i == 0:
			support_squad.leader = ac
		support_squad.add_member(ac)
		_progression_support.append(ac)
	if not support_squad.members.is_empty():
		_progression_squads_ref.append(support_squad)
	EventLogger.log_event("BOSS", display_name,
		"progression tier 1: %d lockable YF-23 snipers deployed behind Wraith" \
		% _progression_support.size())

## SEAM-019：可选支援也缓存/追踪玩家，切控时必须和四架 BOSS 本体一起重定向。
func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	super.set_player_ref(p)
	for ac in _progression_support:
		if ac == null or not is_instance_valid(ac) or ac.is_destroyed:
			continue
		var ai: AIController = ac._get_ai_controller()
		if ai != null and ai.acquire_target(p, AIController.TargetSource.TS_BOSS,
				"Wraith progression player redirect"):
			ai.enter_engage_state()

## 每架 F-47 的额外配置
## F-47 特性：隐身（cloak）+ 协同齐射；不挂 Herbst（J-Turn 已转移到 F-14 Poltergeist）
func _configure_spawn(_member: Aircraft, index: int, _squad: Squad, ai: AIController) -> void:
	# 队长指挥齐射
	if index == 0 and ai:
		ai.salvo_leader = true

# ══════════════════════════════════════════════
#  队级战术层（基类钩子实现）
# ══════════════════════════════════════════════

func _tactics_enter() -> void:
	if tactics == null:
		tactics = WraithTactics.new()
		tactics.setup(self)
	tactics.start()

func _tactics_update(delta: float) -> void:
	if tactics != null:
		tactics.update(delta)

func _tactics_exit() -> void:
	if tactics != null:
		tactics.stop()

## 近距纠缠组：最大 G 力转弯 + 减速拉到最紧
func _configure_close_fighter_combat(member: Aircraft) -> void:
	if not member.params or not member.params.combat:
		return
	var c := member.params.combat
	c.combat_bank_aggression = 1.5
	c.combat_full_bank_diff = 0.05
	c.combat_half_bank_diff = 0.01
	c.approach_speed_mult = 1.6
	c.maneuver_speed_mult = 0.70
	c.closing_speed_mult = 1.4
	c.intercept_range_mult = 1.6
	c.ab_cooldown = 0.5
	c.turn_slow_speed_mult = 0.65
	c.turn_slow_angle = 30.0
	c.turn_slow_max_angle = 90.0

## 远距攻击组：全速冲刺 + 快速掉头 + 猛刹转弯
func _configure_ranged_striker_combat(member: Aircraft) -> void:
	if not member.params or not member.params.combat:
		return
	var c := member.params.combat
	c.combat_bank_aggression = 1.3
	c.combat_full_bank_diff = 0.06
	c.combat_half_bank_diff = 0.015
	c.approach_speed_mult = 1.8
	c.maneuver_speed_mult = 0.80
	c.closing_speed_mult = 1.6
	c.intercept_range_mult = 2.5
	c.ab_cooldown = 0.5
	c.overshoot_speed_margin = 1.3
	c.overshoot_decel_range = 0.8
	c.overshoot_ab_range = 1.0
	c.turn_slow_speed_mult = 0.70
	c.turn_slow_angle = 35.0
	c.turn_slow_max_angle = 100.0
