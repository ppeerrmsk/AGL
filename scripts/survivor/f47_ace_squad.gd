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

	# 距离
	standoff_radius_min = SurvivorData.F47_STANDOFF_RADIUS_MIN
	standoff_radius_max = SurvivorData.F47_STANDOFF_RADIUS_MAX

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
