class_name SurvivorSpawner
extends Node

## 生存模式刷怪系统
## 从 survivor_mode.gd 提取：Token 预算、敌人生成、击杀检测、远距清理、猎手指派、航点刷新

# ── 敌人类型 ──
## ⚠ 新增时必须同步 TOKEN_COST / TOKEN_INSTANCE_CAP / _create_enemy match /
##   _preload / _pick_enemy_type / survivor_debug_spawn.ENEMY_TYPE_LABELS
##
## 分类说明：
## - 普通敌机（载人战机/UAV 系列）：走 _update_spawner / Token 预算 / 编队系统
## - Adds（杂兵，category="adds"）：无反击能力，只沿直线飞行，不走 _update_spawner
##     / Token 预算系统，通过独立 flock 波次刷新，不受远距清理影响。
##     目前成员：TU160, AH64, CH47。敌人参数的 meta("category")="adds" 标识。
enum EnemyType { UAV, UCAV, MIG, INTERCEPTOR, UAV_COMMANDER, F86, MIG31, MIG23, F100, SU27, A7, Q5, TU160, AH64, CH47, F47, F14_POLTERGEIST, AF03, UAV_LASER, F4, F104, SU35, FA18 }

# ── 经验常量 ──
const XP_PER_KILL := 40  ## 基础经验值（MiG）
const XP_PER_KILL_UAV := 25  ## UAV 击杀经验
const MAX_MISSILES_TARGETING_PLAYER := 3  ## 同时飞向玩家的导弹上限

# ── 计时器常量 ──
const HUNTER_INTERVAL := 5.0   ## 每5秒检查一次，指派猎手追踪玩家
const WAYPOINT_UPDATE_INTERVAL := 8.0  ## 每8秒更新敌机巡逻航点跟踪玩家
const SQUAD_CLEANUP_INTERVAL := 3.0  ## 每3秒清理一次无效分队

# ── 动态性能控制常量 ──
const FPS_SAMPLE_INTERVAL := 0.5   ## 每 0.5 秒采样一次 FPS
const FPS_SAMPLE_COUNT := 6        ## 保留最近 6 次采样（3 秒窗口）

# ── 注入依赖（setup 时赋值）──
var mode: Node2D               ## survivor_mode 实例
var player_aircraft: Aircraft
var survivor_player: SurvivorPlayer
var bullet_manager: BulletManager
var missile_manager: MissileManager
var zone_mission: ZoneMission  ## 由 survivor_mode 在自身 setup 序列里注入（避免循环依赖）

# ── 场景/资源引用 ──
var _aircraft_scene: PackedScene
var _enemy_params_base: AircraftParams
var _uav_params_base: AircraftParams
var _ucav_params_base: AircraftParams
var _interceptor_params_base: AircraftParams
var _commander_params_base: AircraftParams
var _f86_params_base: AircraftParams
var _mig31_params_base: AircraftParams
var _mig23_params_base: AircraftParams
var _f100_params_base: AircraftParams
var _su27_params_base: AircraftParams
var _a7_params_base: AircraftParams
var _q5_params_base: AircraftParams
var _tu160_params_base: AircraftParams
var _ah64_params_base: AircraftParams
var _ch47_params_base: AircraftParams
var _f47_params_base: AircraftParams
var _f14_poltergeist_params_base: AircraftParams
var _af03_params_base: AircraftParams         ## AF-03 电磁炮狙击手（Schemer with combat, commit 11/13）
var _uav_laser_params_base: AircraftParams    ## Aegis UAV 激光拦截器（伴 Sentinel, commit 11/13）
var _f4_params_base: AircraftParams           ## F-4 Phantom（Gladiator 中段，导弹卡车）
var _f104_params_base: AircraftParams         ## F-104 Starfighter（Lancer 纯速度截击）
var _su35_params_base: AircraftParams         ## Su-35 Super Flanker（Gladiator 顶级，Su-27 强化版）
var _fa18_params_base: AircraftParams         ## F/A-18C Hornet（Gladiator 均衡舰载机，CSG BOSS 弹射）

# ── 王牌中队 BOSS ──
var _boss: BossEncounter = null               ## 当前活跃的 BOSS encounter（F-47 / CSG / ...）

# ── 刷怪计时器 ──
## 初始延迟：取旅途间隔一半，让开局第一趟路也能刷出一波而不是 3 秒就被偷袭
var _spawn_timer: float = SurvivorData.TRAVEL_SPAWN_INTERVAL_BASE * 0.5
var _hunter_timer: float = 0.0
var _waypoint_update_timer: float = 0.0
var _far_cleanup_timer: float = 0.0
var _squad_cleanup_timer: float = 0.0
var _boss_purge_timer: float = 0.0

# ── 编队 ──
var _squads: Array[Squad] = []  ## 活跃分队列表

# ── 单位编号计数器 ──
var _uav_serial: int = 0
var _tu160_serial: int = 0
var _ah64_serial: int = 0
var _ch47_serial: int = 0
var _fa18_serial: int = 0

# ── Token 烈度控制 ──
var _token_used: int = 0
var _token_count_by_type: Dictionary = {}  ## EnemyType(int) -> 当前数量

# ── 动态性能控制 ──
var _dynamic_enemy_cap: int = SurvivorData.MAX_ENEMIES_DEFAULT
var _fps_samples: Array[float] = []
var _fps_sample_timer: float = 0.0

# ── 击杀计数 ──
var kill_count: int = 0

# ══════════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════════

func setup(p_mode: Node2D, p_player: Aircraft, p_sp: SurvivorPlayer, p_bm: BulletManager, p_mm: MissileManager) -> void:
	mode = p_mode
	player_aircraft = p_player
	survivor_player = p_sp
	bullet_manager = p_bm
	missile_manager = p_mm
	_preload_resources()

## 由 survivor_mode 在创建 zone_mission 之后注入，用于旅途刷怪的战区状态门禁
func set_zone_mission(zm: ZoneMission) -> void:
	zone_mission = zm

func _preload_resources() -> void:
	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_enemy_params_base = preload("res://resources/enemy_fighter.tres")
	_uav_params_base = preload("res://resources/enemy_uav.tres")
	_ucav_params_base = preload("res://resources/enemy_uav_missile.tres")
	_interceptor_params_base = preload("res://resources/enemy_interceptor.tres")
	_commander_params_base = preload("res://resources/enemy_uav_commander.tres")
	_f86_params_base = preload("res://resources/enemy_f86.tres")
	_mig31_params_base = preload("res://resources/enemy_mig31.tres")
	_mig23_params_base = preload("res://resources/enemy_mig23.tres")
	_f100_params_base = preload("res://resources/enemy_f100.tres")
	_su27_params_base = preload("res://resources/enemy_su27.tres")
	_a7_params_base = preload("res://resources/enemy_a7.tres")
	_q5_params_base = preload("res://resources/enemy_q5.tres")
	_tu160_params_base = preload("res://resources/enemy_tu160.tres")
	_ah64_params_base = preload("res://resources/enemy_ah64.tres")
	_ch47_params_base = preload("res://resources/enemy_ch47.tres")
	_f47_params_base = preload("res://resources/enemy_f47.tres")
	_f14_poltergeist_params_base = preload("res://resources/enemy_f14_poltergeist.tres")
	_af03_params_base = preload("res://resources/enemy_af03.tres")
	_uav_laser_params_base = preload("res://resources/enemy_uav_laser.tres")
	_f4_params_base = preload("res://resources/enemy_f4.tres")
	_f104_params_base = preload("res://resources/enemy_f104.tres")
	_su35_params_base = preload("res://resources/enemy_su35.tres")
	_fa18_params_base = preload("res://resources/enemy_fa18.tres")

# ══════════════════════════════════════════════
#  每帧更新（由 survivor_mode._physics_process 调用）
# ══════════════════════════════════════════════

func update(delta: float) -> void:
	# 检测击杀（比较当前敌人数与上一帧）
	_detect_kills()

	# 刷怪
	_update_spawner(delta)

	# Adds 类敌人（Tu-160 / AH-64 / CH-47）不随机刷新——由未来的事件系统按需触发 spawn。
	# 这里仅处理已刷出来单位的生命期超限清理（despawn_after meta）
	_cleanup_expired_adds()

	# BOSS encounter 更新（飞机 / 舰队 / 混合都走这个）
	if _boss:
		_boss.update(delta)

	# 猎手追踪 & 巡逻航点更新
	_update_hunters(delta)
	_update_enemy_waypoints(delta)
	_update_boundary_discipline(delta)

	# 远距清理：释放 Token 预算
	_update_far_cleanup(delta)

	# BOSS 阶段清场：把画面外 + 过远的残余敌机全部撤走（保留画面内）
	if _is_boss_phase():
		_update_boss_phase_purge(delta)

	# 【硬规则看门狗】：扫描所有 Sentinel，若护卫不足 5 架则紧急补刷
	# 不管 Sentinel 从哪条路径登场，只要单独一架就强制配 5 架 UAV 护卫
	_ensure_sentinels_escorted()

	# 定期清理无效分队
	_squad_cleanup_timer -= delta
	if _squad_cleanup_timer <= 0.0:
		_squad_cleanup_timer = SQUAD_CLEANUP_INTERVAL
		_cleanup_squads()

# ══════════════════════════════════════════════
#  公共 API
# ══════════════════════════════════════════════

func get_squads() -> Array[Squad]:
	return _squads

func get_boss() -> BossEncounter:
	return _boss

## 向后兼容：非 AceSquad 的 BOSS（例如 CSG）走 get_active_ace_squad 返回内部飞机子小队
## Phase 2 未触发时 CSG 返回 null（HUD 自动隐藏面板）
func get_ace_squad() -> AceSquad:
	if _boss:
		return _boss.get_active_ace_squad()
	return null

func get_enemy_count() -> int:
	return _count_enemies()

func get_token_usage() -> int:
	return _token_used

# ══════════════════════════════════════════════
#  动态性能控制
# ══════════════════════════════════════════════

func update_fps_sampling(delta: float) -> void:
	_fps_sample_timer += delta
	if _fps_sample_timer < FPS_SAMPLE_INTERVAL:
		return
	_fps_sample_timer -= FPS_SAMPLE_INTERVAL

	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() > FPS_SAMPLE_COUNT:
		_fps_samples.remove_at(0)

	var avg := _get_avg_fps()
	if avg <= 0.0:
		return

	if avg < SurvivorData.TARGET_FPS:
		# 帧率低于目标：缩减上限
		_dynamic_enemy_cap = maxi(_dynamic_enemy_cap - 2, SurvivorData.MIN_ENEMIES_CAP)
	elif avg > SurvivorData.TARGET_FPS + 10 and _dynamic_enemy_cap < SurvivorData.MAX_ENEMIES_HARD:
		# 帧率充裕：缓慢回升
		_dynamic_enemy_cap = mini(_dynamic_enemy_cap + 1, SurvivorData.MAX_ENEMIES_HARD)

func _get_avg_fps() -> float:
	if _fps_samples.is_empty():
		return 0.0
	var total := 0.0
	for s in _fps_samples:
		total += s
	return total / _fps_samples.size()

# ══════════════════════════════════════════════
#  刷怪系统
# ══════════════════════════════════════════════

## 补给加成（玩家边界补给时临时提高 Token 预算，等效于多玩了一段时间）
var token_bonus: int = 0

## 当前 Token 预算（随等级增长 + 补给加成，夹在常量范围内）
func _get_token_budget() -> int:
	var budget := SurvivorData.TOKEN_BUDGET_BASE + int(survivor_player.level * SurvivorData.TOKEN_BUDGET_PER_LEVEL) + token_bonus
	return mini(budget, SurvivorData.TOKEN_BUDGET_MAX)

## 补给：相当于玩了 1 分钟的 Token 涨幅（配合回血作为代价）
## TOKEN_BUDGET_PER_LEVEL = 1.5，1 分钟 ≈ 1 级成长 → 大约 +2 tokens
const SUPPLY_TOKEN_GAIN := 2
func add_supply_token_bonus() -> void:
	token_bonus += SUPPLY_TOKEN_GAIN

## 从场景真实状态重算 Token 占用 & 每种敌人的数量
func _recalc_token_usage() -> void:
	_token_used = 0
	_token_count_by_type.clear()
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var cost: int = int(child.get_meta("token_cost", 1))
			_token_used += cost
			var t_idx: int = int(child.get_meta("enemy_type_idx", -1))
			if t_idx >= 0:
				_token_count_by_type[t_idx] = int(_token_count_by_type.get(t_idx, 0)) + 1

## 指定敌人类型是否可生成（预算 + 实例上限）
func _can_spawn_type(etype_idx: int, remaining_budget: int) -> bool:
	var cost: int = int(SurvivorData.TOKEN_COST.get(etype_idx, 1))
	if cost > remaining_budget:
		return false
	var cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(etype_idx, -1))
	if cap > 0:
		var cur: int = int(_token_count_by_type.get(etype_idx, 0))
		if cur >= cap:
			return false
	return true

func _pick_enemy_type() -> EnemyType:
	var lvl := survivor_player.level
	var remaining := _get_token_budget() - _token_used

	# MiG-31（顶级 Lancer，单机）：等级 9+ 优先判定，压过普通 MiG
	if lvl >= SurvivorData.MIG31_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG31), remaining):
		var mig31_chance := clampf(
			(lvl - SurvivorData.MIG31_UNLOCK_LEVEL + 1) * SurvivorData.MIG31_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG31_CHANCE_MAX)
		if randf() < mig31_chance:
			return EnemyType.MIG31
	# AF-03（电磁炮狙击 Schemer，单机）：等级 8+ 稀有出现
	if lvl >= SurvivorData.AF03_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.AF03), remaining):
		var af03_chance := clampf(
			(lvl - SurvivorData.AF03_UNLOCK_LEVEL + 1) * SurvivorData.AF03_CHANCE_PER_LEVEL,
			0.0, SurvivorData.AF03_CHANCE_MAX)
		if randf() < af03_chance:
			return EnemyType.AF03
	# Su-35（顶级 Gladiator + 眼镜蛇 + TVC，单/双机）：等级 9+ 与 MiG-31 同档稀有，先于 Su-27 判定
	if lvl >= SurvivorData.SU35_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.SU35), remaining):
		var su35_chance := clampf(
			(lvl - SurvivorData.SU35_UNLOCK_LEVEL + 1) * SurvivorData.SU35_CHANCE_PER_LEVEL,
			0.0, SurvivorData.SU35_CHANCE_MAX)
		if randf() < su35_chance:
			return EnemyType.SU35
	# Su-27（主力威胁 + 眼镜蛇机动，单机）：等级 8+ 出现
	if lvl >= SurvivorData.SU27_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.SU27), remaining):
		var su27_chance := clampf(
			(lvl - SurvivorData.SU27_UNLOCK_LEVEL + 1) * SurvivorData.SU27_CHANCE_PER_LEVEL,
			0.0, SurvivorData.SU27_CHANCE_MAX)
		if randf() < su27_chance:
			return EnemyType.SU27
	# MiG：等级 7+ 逐步出现
	if lvl >= SurvivorData.MIG_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG), remaining):
		var mig_chance := clampf(
			(lvl - SurvivorData.MIG_UNLOCK_LEVEL) * SurvivorData.MIG_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG_CHANCE_MAX)
		if randf() < mig_chance:
			return EnemyType.MIG
	# F-4 Phantom（Gladiator 中段，导弹卡车，编队）：等级 6+ 逐步出现，先于 F-100 判定
	if lvl >= SurvivorData.F4_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F4), remaining):
		var f4_chance := clampf(
			(lvl - SurvivorData.F4_UNLOCK_LEVEL + 1) * SurvivorData.F4_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F4_CHANCE_MAX)
		if randf() < f4_chance:
			return EnemyType.F4
	# F-100（Lancer 编队，雷达弹）：等级 6+ 逐步出现
	if lvl >= SurvivorData.F100_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F100), remaining):
		var f100_chance := clampf(
			(lvl - SurvivorData.F100_UNLOCK_LEVEL + 1) * SurvivorData.F100_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F100_CHANCE_MAX)
		if randf() < f100_chance:
			return EnemyType.F100
	# 指挥 UAV（Sentinel）：等级 4+ 出现，优先于 J-7 判定
	# 必须同时有预算容纳 Sentinel + 5 架 UAV 僚机，否则跳过（不允许单独出现）
	if lvl >= SurvivorData.COMMANDER_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.UAV_COMMANDER), remaining):
		var cmd_cost: int = int(SurvivorData.TOKEN_COST.get(int(EnemyType.UAV_COMMANDER), 6))
		var uav_cost_for_cmd: int = int(SurvivorData.TOKEN_COST.get(int(EnemyType.UAV), 1))
		var full_squad_cost := cmd_cost + uav_cost_for_cmd * SurvivorData.COMMANDER_SQUAD_MIN
		if remaining >= full_squad_cost:
			var cmd_chance := clampf(
				SurvivorData.COMMANDER_CHANCE_BASE + (lvl - SurvivorData.COMMANDER_UNLOCK_LEVEL) * SurvivorData.COMMANDER_CHANCE_PER_LEVEL,
				0.0, SurvivorData.COMMANDER_CHANCE_MAX)
			if randf() < cmd_chance:
				return EnemyType.UAV_COMMANDER
	# MiG-23（Gladiator 综合型，编队）：等级 4+ 逐步出现
	if lvl >= SurvivorData.MIG23_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG23), remaining):
		var mig23_chance := clampf(
			(lvl - SurvivorData.MIG23_UNLOCK_LEVEL + 1) * SurvivorData.MIG23_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG23_CHANCE_MAX)
		if randf() < mig23_chance:
			return EnemyType.MIG23
	# Q-5（Lancer 超音速攻击机，机炮+火箭弹编队）：等级 5+ 逐步出现
	if lvl >= SurvivorData.Q5_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.Q5), remaining):
		var q5_chance := clampf(
			(lvl - SurvivorData.Q5_UNLOCK_LEVEL + 1) * SurvivorData.Q5_CHANCE_PER_LEVEL,
			0.0, SurvivorData.Q5_CHANCE_MAX)
		if randf() < q5_chance:
			return EnemyType.Q5
	# F-104 Starfighter（Lancer 纯速度截击，编队）：等级 5+ 逐步出现，先于 J-7 判定
	if lvl >= SurvivorData.F104_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F104), remaining):
		var f104_chance := clampf(
			(lvl - SurvivorData.F104_UNLOCK_LEVEL + 1) * SurvivorData.F104_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F104_CHANCE_MAX)
		if randf() < f104_chance:
			return EnemyType.F104
	# 截击机（J-7）：等级 5+ 逐步出现
	if lvl >= SurvivorData.INTERCEPTOR_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.INTERCEPTOR), remaining):
		var int_chance := clampf(
			(lvl - SurvivorData.INTERCEPTOR_UNLOCK_LEVEL) * SurvivorData.INTERCEPTOR_CHANCE_PER_LEVEL,
			0.0, SurvivorData.INTERCEPTOR_CHANCE_MAX)
		if randf() < int_chance:
			return EnemyType.INTERCEPTOR
	# A-7（Lancer 亚音速攻击机，机炮+火箭弹编队）：等级 3+ 逐步出现
	if lvl >= SurvivorData.A7_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.A7), remaining):
		var a7_chance := clampf(
			(lvl - SurvivorData.A7_UNLOCK_LEVEL + 1) * SurvivorData.A7_CHANCE_PER_LEVEL,
			0.0, SurvivorData.A7_CHANCE_MAX)
		if randf() < a7_chance:
			return EnemyType.A7
	# F-86（Gladiator 斗士型）：等级 2+ 逐步出现
	if lvl >= SurvivorData.F86_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F86), remaining):
		var f86_chance := clampf(
			(lvl - SurvivorData.F86_UNLOCK_LEVEL + 1) * SurvivorData.F86_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F86_CHANCE_MAX)
		if randf() < f86_chance:
			return EnemyType.F86
	# 后期：所有概率 roll 未命中时，不再回退到低 Token 杂鱼，
	# 而是从已解锁且满足最低 Token 的类型中随机选一个
	if lvl >= SurvivorData.LATE_GAME_LEVEL:
		var candidates: Array[EnemyType] = []
		for etype_int in SurvivorData.TOKEN_COST:
			if SurvivorData.TOKEN_COST[etype_int] >= SurvivorData.LATE_GAME_MIN_TOKEN \
					and _can_spawn_type(etype_int, remaining):
				candidates.append(etype_int as EnemyType)
		if candidates.size() > 0:
			return candidates[randi() % candidates.size()]
	# UAV/UCAV 是前期杂鱼，达到退场等级后不再使用
	if lvl <= SurvivorData.UAV_RETIRE_LEVEL:
		if _can_spawn_type(int(EnemyType.UCAV), remaining):
			if randf() < 0.5:
				return EnemyType.UCAV
		return EnemyType.UAV
	# 5 级起 UAV 退场：fallback 到已解锁的低 Token 机型
	for fallback in [EnemyType.F86, EnemyType.A7, EnemyType.INTERCEPTOR, EnemyType.MIG23]:
		if _can_spawn_type(int(fallback), remaining):
			return fallback
	# 最坏情况（所有类型被 cap）保底仍返回 UAV，避免上层死循环
	return EnemyType.UAV

## BOSS 阶段统一闸门：玩家选了 BOSS → 旅途刷怪 / 猎手指派 / Sentinel 护卫看门狗 全部停摆
## 系统资源让给 BOSS（F-47 王牌中队），已刷的常规敌机由 zone_mission 在视线外悄悄撤离
func _is_boss_phase() -> bool:
	return mode and "_zone_data" in mode and mode._zone_data \
			and mode._zone_data.is_boss_phase()

func _update_spawner(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	if _is_boss_phase():
		return

	# 玩家正在活跃战区任务里 → 旅途刷怪停摆，留给战区驻守独占
	# 用短轮询而非长 interval，任务完成后第一时间恢复节奏
	if zone_mission and zone_mission.is_player_in_active_mission():
		_spawn_timer = 2.0
		return

	var interval := lerpf(
		SurvivorData.TRAVEL_SPAWN_INTERVAL_BASE,
		SurvivorData.TRAVEL_SPAWN_INTERVAL_MIN,
		clampf(survivor_player.level / 20.0, 0.0, 1.0)
	)
	_spawn_timer = interval

	# 从场景真实状态重算 Token 占用（捕获死亡/远距清理/debug spawn）
	_recalc_token_usage()

	var current_enemies := _count_enemies()
	if current_enemies >= _dynamic_enemy_cap:
		return

	# FPS 低于目标时完全停止刷怪
	var avg_fps := _get_avg_fps()
	if avg_fps > 0.0 and avg_fps < SurvivorData.TARGET_FPS:
		return

	var budget := _get_token_budget()
	if _token_used >= budget:
		return  # Token 已满，本轮跳过

	var count := SurvivorData.ENEMIES_PER_WAVE_BASE + int(survivor_player.level * SurvivorData.ENEMIES_PER_WAVE_GROWTH)
	count = mini(count, _dynamic_enemy_cap - current_enemies)

	EventLogger.log_event("WAVE", "Spawner",
		"wave lvl=%d token=%d/%d cap=%d/%d" % [
			survivor_player.level, _token_used, budget,
			current_enemies, _dynamic_enemy_cap])

	var spawned := 0
	while spawned < count:
		var remaining := budget - _token_used
		if remaining <= 0:
			break

		var etype := _pick_enemy_type()
		if not _can_spawn_type(int(etype), remaining):
			break  # fallback 是 UAV=1，若连它都不够就整轮结束

		var cost: int = int(SurvivorData.TOKEN_COST.get(int(etype), 1))
		var is_late_game := survivor_player.level >= SurvivorData.LATE_GAME_LEVEL

		# MiG-31 永远单机精英；J-7 在后期改走编队（视作低级 Lancer）
		var spawn_as_single := etype == EnemyType.MIG31 \
				or etype == EnemyType.SU27 \
				or etype == EnemyType.AF03 \
				or (etype == EnemyType.INTERCEPTOR and not is_late_game)

		if spawn_as_single:
			# 单机精英 Lancer：一架一架地刷
			_spawn_single(etype)
			_token_used += cost
			_token_count_by_type[int(etype)] = int(_token_count_by_type.get(int(etype), 0)) + 1
			spawned += 1

		elif etype == EnemyType.UAV_COMMANDER:
			# Sentinel + 5 架 UAV 僚机组成小队（固定编成，绝不单独出现）
			# 预算若不足以容纳完整小队则直接跳过本轮选型（_pick_enemy_type 已提前拦截，这里是兜底）
			var uav_cost: int = int(SurvivorData.TOKEN_COST.get(int(EnemyType.UAV), 1))
			var wingman_count: int = SurvivorData.COMMANDER_SQUAD_MAX
			var full_cost := cost + uav_cost * wingman_count
			if remaining < full_cost:
				break
			_spawn_commander_squad(wingman_count)
			_token_used += full_cost
			_token_count_by_type[int(EnemyType.UAV_COMMANDER)] = int(_token_count_by_type.get(int(EnemyType.UAV_COMMANDER), 0)) + 1
			_token_count_by_type[int(EnemyType.UAV)] = int(_token_count_by_type.get(int(EnemyType.UAV), 0)) + wingman_count
			spawned += 1 + wingman_count

		else:
			# MiG / F86 / MiG-23 / F-100 / UCAV / UAV / J-7(后期) ：分队生成
			var squad_size: int
			if etype == EnemyType.MIG or etype == EnemyType.F86 \
					or etype == EnemyType.MIG23 or etype == EnemyType.F100 \
					or etype == EnemyType.INTERCEPTOR \
					or etype == EnemyType.A7 or etype == EnemyType.Q5 \
					or etype == EnemyType.F4 or etype == EnemyType.F104 \
					or etype == EnemyType.SU35:
				squad_size = randi_range(2, 3)
			else:
				squad_size = randi_range(2, 4)
			squad_size = mini(squad_size, count - spawned)
			# Token 约束
			squad_size = mini(squad_size, int(remaining / maxi(cost, 1)))
			# 实例上限约束
			var type_cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(int(etype), -1))
			if type_cap > 0:
				var type_cur: int = int(_token_count_by_type.get(int(etype), 0))
				squad_size = mini(squad_size, type_cap - type_cur)

			# 后期分水岭：低级飞机/杂鱼不允许单架，至少凑成 2 架编队
			# - 早期 min=1（允许尾巴落单），后期 min=2（强制成对）
			# - 凑不齐 min 就 break，等下一个 spawner tick 重新选型
			var min_squad_size := 2 if is_late_game else 1
			if squad_size < min_squad_size:
				break

			if squad_size == 1:
				_spawn_single(etype)
			else:
				_spawn_squad(etype, squad_size)
			_token_used += cost * squad_size
			_token_count_by_type[int(etype)] = int(_token_count_by_type.get(int(etype), 0)) + squad_size
			spawned += squad_size

# ══════════════════════════════════════════════
#  生成函数
# ══════════════════════════════════════════════

## 在玩家周围选一个刷怪角度，三条约束：
##   1. 不落在边界外（安全余量 SPAWN_SAFE_MARGIN_PX）
##   2. 不落在警戒区（由 is_safe_inside 判定）
##   3. 不在玩家当前屏幕内（铁则：不在玩家视野中凭空出现）
## 全满足取之；8 次都不满足则放弃第 3 条，再 8 次；最终 fallback 指向地图中心方向。
const SPAWN_SAFE_MARGIN_PX := 1500.0

## `preferred_dir_rad` 为 NAN 时走历史行为（360° 均匀）；否则在
## 以该方向为中心的 ±TRAVEL_SPAWN_FAN_HALF 扇形里选角（用于旅途刷怪："前方扇形"）。
## 注意：这里的 angle 是世界坐标系数学角（0=+X 东，逆时针；atan2(y,x)）。
## 调用方从 Aircraft.heading（0=北，顺时针）换算时应传
## `Vector2.UP.rotated(heading)` 再 atan2(y,x)，或等效地 `heading - PI/2`。
func _pick_safe_spawn_angle(player_pos: Vector2, dist: float, preferred_dir_rad: float = NAN) -> float:
	var has_fan := not is_nan(preferred_dir_rad)
	var fan: float = SurvivorData.TRAVEL_SPAWN_FAN_HALF

	# Pass 1：全部约束
	for i in range(8):
		var a: float
		if has_fan:
			a = preferred_dir_rad + randf_range(-fan, fan)
		else:
			a = randf() * TAU
		var pos := player_pos + Vector2(cos(a), sin(a)) * dist
		if MapBoundary.is_safe_inside(pos, SPAWN_SAFE_MARGIN_PX) \
				and not _is_pos_visible(pos):
			return a
	# Pass 2：放弃可见性约束（玩家极端缩放/贴边时）
	for i in range(8):
		var a: float
		if has_fan:
			a = preferred_dir_rad + randf_range(-fan, fan)
		else:
			a = randf() * TAU
		var pos := player_pos + Vector2(cos(a), sin(a)) * dist
		if MapBoundary.is_safe_inside(pos, SPAWN_SAFE_MARGIN_PX):
			return a
	var inward := (Vector2.ZERO - player_pos)
	if inward.length_squared() < 1.0:
		return randf() * TAU
	inward = inward.normalized()
	return atan2(inward.y, inward.x)

## 包装：有些场景 mode 可能未就绪，安全 fallback
func _is_pos_visible(pos: Vector2) -> bool:
	if mode and mode.has_method("is_world_pos_visible"):
		return mode.is_world_pos_visible(pos)
	return false

## 玩家当前 heading 换算为标准数学角（0=+X 东，逆时针）。
## Aircraft.heading 是 0=北顺时针的弧度 → 数学角 = heading - PI/2。
## 旅途刷怪 3 个入口统一用这个方向作为"前方扇形"中心。
func _player_forward_math_angle() -> float:
	return player_aircraft.heading - PI * 0.5

## 生成单架敌机（不含分队），用于 J-7 截击机
## 【硬规则】Sentinel 永远不允许单独登场 → 自动改走 _spawn_commander_squad
func _spawn_single(etype: EnemyType) -> void:
	if etype == EnemyType.UAV_COMMANDER:
		push_warning("[Spawner] _spawn_single(UAV_COMMANDER) 被拦截 → 改走 _spawn_commander_squad(5)")
		_spawn_commander_squad(SurvivorData.COMMANDER_SQUAD_MAX)
		return
	var spawn_angle := _pick_safe_spawn_angle(player_aircraft.global_position, SurvivorData.SPAWN_DISTANCE, _player_forward_math_angle())
	var spawn_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - spawn_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))
	_create_enemy(etype, spawn_pos, heading)

## 以分队形式生成一组敌机
## 【硬规则】Sentinel 不走普通 Squad（同型编队），改走 _spawn_commander_squad（Sentinel + 5 UAV）
func _spawn_squad(etype: EnemyType, squad_size: int) -> void:
	if etype == EnemyType.UAV_COMMANDER:
		push_warning("[Spawner] _spawn_squad(UAV_COMMANDER) 被拦截 → 改走 _spawn_commander_squad(5)")
		_spawn_commander_squad(SurvivorData.COMMANDER_SQUAD_MAX)
		return
	var sq := SquadFactory.create()

	# 长机生成位置（旅途刷怪：玩家前方扇形）
	var spawn_angle := _pick_safe_spawn_angle(player_aircraft.global_position, SurvivorData.SPAWN_DISTANCE, _player_forward_math_angle())
	var leader_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - leader_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))
	var heading_rad := deg_to_rad(heading)

	for i in range(squad_size):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			# 僚机按编队偏移生成
			var offset := sq.get_formation_offset(i)
			# heading 转换为弧度并旋转偏移（heading: 0=北）
			spawn_pos = leader_pos + offset.rotated(heading_rad)

		var enemy := _create_enemy(etype, spawn_pos, heading)
		if i == 0:
			SquadFactory.register_leader(sq, enemy)
		else:
			# Step 4：显式 set_state=true 直接进 SQUAD_FOLLOW，不再依赖
			# ai_controller.gd:516 自校正守卫（守卫现在只服务 CommanderAura 运行时招募）
			SquadFactory.register_wingman(sq, enemy, true)

	_squads.append(sq)

## 生成指挥 UAV 及其自带小队
func _spawn_commander_squad(wingman_count: int) -> void:
	var sq := SquadFactory.create()

	# 指挥机生成位置（旅途刷怪：玩家前方扇形）
	var spawn_angle := _pick_safe_spawn_angle(player_aircraft.global_position, SurvivorData.SPAWN_DISTANCE, _player_forward_math_angle())
	var leader_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - leader_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))

	# 生成指挥 UAV（leader）
	var commander := _create_enemy(EnemyType.UAV_COMMANDER, leader_pos, heading)
	SquadFactory.register_leader(sq, commander)

	# 挂载光环 + 视觉覆盖
	var aura := CommanderAura.new()
	aura.name = "CommanderAura"
	commander.add_child(aura)

	var overlay := CommanderOverlay.new()
	overlay.name = "CommanderOverlay"
	commander.add_child(overlay)

	# 生成 UAV 僚机（保持 simple_ai + 绕长机飞行 + 自主扫描交战）
	for i in range(wingman_count):
		# 在指挥机附近随机散开生成（不用阵型偏移，简单即可）
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(200.0, 400.0)
		var spawn_pos := leader_pos + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var wingman := _create_enemy(EnemyType.UAV, spawn_pos, heading)
		SquadFactory.register_wingman(sq, wingman, false)  # simple_ai 路径，不切 SQUAD_FOLLOW

		# 设绕飞标志 + 蓝盾守护行为
		for child in wingman.get_children():
			if child is AIController:
				var wai := child as AIController
				wai.orbit_squad_leader = true
				wai.shield_leader = true
				wai.enable_combat = true
				wai.evade_missiles = false
				wai.aggression = randf_range(0.7, 0.95)
				wai.waypoints = PackedVector2Array()
				break

	# Aegis UAV 激光拦截器（commit 11/13）：每只 Sentinel 固定带 1 架
	for i in range(1):
		var laser_angle := PI * 1.0  # 正后方站位
		var laser_pos := leader_pos + Vector2(cos(laser_angle), sin(laser_angle)) * 320.0
		var laser_uav := _create_enemy(EnemyType.UAV_LASER, laser_pos, heading)
		SquadFactory.register_wingman(sq, laser_uav, false)

	_squads.append(sq)

## 【Sentinel 护卫看门狗】：每帧扫描所有 Sentinel，护卫 < MIN_ESCORT 时紧急补刷
## 作为所有刷怪路径的最终兜底 — 不管 Sentinel 怎么被创建出来，只要孤零零一架就补刷
## 每个 Sentinel 只补一次（escort_watchdog_done meta 防重复）
const SENTINEL_MIN_ESCORT := 5
func _ensure_sentinels_escorted() -> void:
	if not mode:
		return
	if _is_boss_phase():
		return
	for child in mode.get_children():
		if not (child is Aircraft):
			continue
		var ac: Aircraft = child
		if ac.is_destroyed or ac.team == 0:
			continue
		if ac.get_meta("enemy_type", "") != "uav_commander":
			continue
		if ac.has_meta("escort_watchdog_done"):
			continue
		# 找出它的 Squad；如果没有 Squad 也视作孤狼
		var leader_ai: AIController = null
		for c in ac.get_children():
			if c is AIController:
				leader_ai = c
				break
		var sq: Squad = leader_ai.squad if leader_ai else null
		var escort_count: int = 0
		if sq:
			for m in sq.members:
				if is_instance_valid(m) and m != ac and not m.is_destroyed:
					escort_count += 1
		if escort_count >= SENTINEL_MIN_ESCORT:
			# 护卫够了，锁定不再重复检查
			ac.set_meta("escort_watchdog_done", true)
			continue
		# 护卫不足 → 紧急补刷
		var missing := SENTINEL_MIN_ESCORT - escort_count
		push_warning("[Watchdog] Sentinel %s 护卫仅 %d 架，紧急补刷 %d 架 UAV" \
				% [ac.callsign, escort_count, missing])
		EventLogger.log_event("SENTINEL", "EscortWatchdog",
			"callsign=%s had=%d spawning=%d" % [ac.callsign, escort_count, missing])
		# 若 Sentinel 没 Squad，临建一个
		if not sq:
			sq = SquadFactory.create()
			SquadFactory.register_leader(sq, ac)
			_squads.append(sq)
		_spawn_sentinel_escort_uavs(ac, sq, missing)
		ac.set_meta("escort_watchdog_done", true)

## 围绕指定 Sentinel 刷若干架 UAV 僚机（watchdog 使用）
func _spawn_sentinel_escort_uavs(commander: Aircraft, sq: Squad, count: int) -> void:
	var leader_pos := commander.global_position
	# 用 Sentinel 当前朝向作为 heading
	var heading_deg := rad_to_deg(commander.heading)
	for i in range(count):
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(200.0, 400.0)
		var spawn_pos := leader_pos + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var wingman := _create_enemy(EnemyType.UAV, spawn_pos, heading_deg)
		if not wingman:
			continue
		SquadFactory.register_wingman(sq, wingman, false)
		for c in wingman.get_children():
			if c is AIController:
				var wai := c as AIController
				wai.orbit_squad_leader = true
				wai.shield_leader = true
				wai.enable_combat = true
				wai.evade_missiles = false
				wai.aggression = randf_range(0.7, 0.95)
				wai.waypoints = PackedVector2Array()
				break

# ══════════════════════════════════════════════
#  Adds 族群系统（独立于 Token / 编队系统）
#  Tu-160 / 其他杂兵通过此系统刷新：
#   - 不占 Token 预算
#   - 不被 _update_far_cleanup 清理（skip_far_cleanup meta）
#   - 不走 Squad 系统（没有阵型偏移 / 长机跟随）
#   - 沿固定直线从 A 飞到 B
# ══════════════════════════════════════════════

## 超过 despawn_after 时间戳的 Adds 静默移除（不触发击杀/经验）
func _cleanup_expired_adds() -> void:
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var ac: Aircraft = child
			if ac.has_meta("despawn_after"):
				var t: float = float(ac.get_meta("despawn_after"))
				if mode.game_time >= t:
					ac.set_meta("xp_granted", true)  # 防止 _detect_kills 当成击杀
					ac.queue_free()

## Adds 航线安全余量：起点 A 至少离边界这么远（保证玩家看得到生成过程）
const ADDS_SPAWN_MARGIN_PX := 1500.0
## Adds 航线终点 B 安全余量：至少离边界这么远（防止一出生就往边界飞）
const ADDS_ENDPOINT_MARGIN_PX := 800.0

## 为 Adds 族群挑选一条"起点 A → 终点 B"的安全航线。
##
## 约束：
##   1. A 距玩家 spawn_dist，且在 MapBoundary 内（余量 ADDS_SPAWN_MARGIN_PX）
##   2. B = A 朝玩家方向延伸 flight_dist（线路必然穿过玩家附近）
##   3. B 也在 MapBoundary 内（余量 ADDS_ENDPOINT_MARGIN_PX）
##
## 退化：如果玩家离边界太近以至于找不到合法路线，则逐步放宽 B 的余量；
## 最终 fallback 把 B 钳制到安全区内（此时 flight 距离会被压缩，但不出图）。
func _pick_safe_flock_route(pp: Vector2, spawn_dist: float, flight_dist: float) -> Dictionary:
	var best_angle := 0.0
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	# Pass 1：严格 — A 和 B 都满足余量
	for i in range(16):
		var a := randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var point_a := pp + dir * spawn_dist
		if not MapBoundary.is_safe_inside(point_a, ADDS_SPAWN_MARGIN_PX):
			continue
		var flight_dir := (pp - point_a).normalized()
		var point_b := point_a + flight_dir * flight_dist
		if MapBoundary.is_safe_inside(point_b, ADDS_ENDPOINT_MARGIN_PX):
			return {"a": point_a, "b": point_b, "angle": a, "dir": flight_dir}
		# 记录一个 fallback（A 合法但 B 超界）
		if best_a == Vector2.ZERO:
			best_angle = a
			best_a = point_a
			best_b = point_b
	# Pass 2：玩家贴边时放宽 — 钳制 B 到安全区内（航线被压缩但方向仍朝中间）
	if best_a == Vector2.ZERO:
		# 极端情况：连 A 都找不到（不应该发生），随便给一个朝地图中心的方向
		var inward: Vector2 = -pp.normalized() if pp.length_squared() > 1.0 else Vector2.UP
		best_angle = atan2(-inward.y, -inward.x)  # A 在反方向，朝玩家飞即是朝 inward
		best_a = MapBoundary.clamp_inside(pp + Vector2(cos(best_angle), sin(best_angle)) * spawn_dist, ADDS_SPAWN_MARGIN_PX)
		best_b = pp + inward * flight_dist
	best_b = MapBoundary.clamp_inside(best_b, ADDS_ENDPOINT_MARGIN_PX)
	var best_dir := (best_b - best_a)
	if best_dir.length_squared() < 1.0:
		best_dir = (pp - best_a)
	best_dir = best_dir.normalized()
	return {"a": best_a, "b": best_b, "angle": best_angle, "dir": best_dir}

## 刷一群 Tu-160 杂兵波次（族群而非编队）
##   - 随机方位选起点 A（距玩家 SPAWN_DISTANCE）
##   - 终点 B = A 的对面方向延伸 TU160_FLIGHT_DISTANCE
##   - 4 架沿 AB 垂直方向排开（有轻微前后错位）
##   - 全程**只沿直线飞**（不转弯，不规避，被击中也没反应）
##   - 超过 120 秒静默消失（防止 skip_far_cleanup 下无限堆积）
func _spawn_tu160_flock() -> void:
	var flock_size: int = SurvivorData.TU160_FLOCK_SIZE
	var pp := player_aircraft.global_position

	# 选一条安全航线：A 和 B 都在地图安全区内，保证玩家有时间拦截
	var route := _pick_safe_flock_route(pp, SurvivorData.SPAWN_DISTANCE, SurvivorData.TU160_FLIGHT_DISTANCE)
	var point_a: Vector2 = route.a
	var point_b: Vector2 = route.b
	var flight_dir: Vector2 = route.dir

	# 横向偏置轴（垂直于 AB）
	var lateral_axis := Vector2(-flight_dir.y, flight_dir.x)

	# 航向（沿 AB 方向）
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 族群统一高度层：战略轰炸机永远在 HIGH 作战
	var flock_tier: int = Aircraft.AltitudeTier.HIGH

	# 排布 4 架：横向槽位左右交错，前后小幅错位
	for i in range(flock_size):
		var lateral_slot := float(i) - (float(flock_size) - 1.0) * 0.5
		var base_lateral: Vector2 = lateral_axis * lateral_slot * SurvivorData.TU160_LATERAL_SPACING
		var stagger: float = (float(i % 2) - 0.5) * 2.0 * SurvivorData.TU160_STAGGER_SPACING
		var stagger_offset: Vector2 = flight_dir * stagger

		var spawn_pos := point_a + base_lateral + stagger_offset
		var target_pos := point_b + base_lateral

		var bomber := _create_enemy(EnemyType.TU160, spawn_pos, heading_deg)
		bomber.set_meta("skip_far_cleanup", true)
		bomber.set_meta("category", "adds")
		bomber.set_meta("crash_style", "bomber")
		bomber.set_meta("silhouette", "bomber")

		# 单点直线目标 — 出生时就朝向终点，完全不转弯
		var ai := _get_ai(bomber)
		if ai:
			ai.waypoints = PackedVector2Array([target_pos])
			ai.current_waypoint_index = 0
			ai.arrival_distance = 250.0
			ai.patrol_altitude = randf_range(7000.0, 9000.0)

		bomber.speed = 650.0 / 3.6  # km/h → m/s
		bomber.target_position = target_pos
		bomber.set_target_tier(flock_tier)
		# 生命期上限：Tu-160 有 skip_far_cleanup 不会被远距清理
		# 给 120 秒的自爆期限（120s × 180 m/s × 0.5 px/m ≈ 10800px，够飞完 8000 px 航线）
		bomber.set_meta("despawn_after", mode.game_time + 120.0)

	EventLogger.log_event("WAVE", "Tu160Flock",
		"spawned %d Tu-160 from %s to %s" % [flock_size, point_a, point_b])

## 通用：配置一架 Adds 单位走固定直线航线（Tu-160 / AH-64 / CH-47 共用）
##   - 设置 adds 分类元数据（跳过 hunter / waypoint-rewrite / far-cleanup 系统）
##   - 单点 waypoint 确保直线飞行
##   - 设置速度、高度层、生命期
##   - **关键**：直接把 altitude 设到 tier 对应高度，避免从默认 5000m 慢慢爬升/
##     下降（直升机 15 m/s 爬升率要 200 秒才能下到低空，整个生命期都耗在换高度）
func _configure_adds_unit(unit: Aircraft, target_pos: Vector2, tier: int,
		cruise_kmh: float, silhouette: String, crash_style: String, lifetime_sec: float) -> void:
	unit.set_meta("skip_far_cleanup", true)
	unit.set_meta("category", "adds")
	unit.set_meta("silhouette", silhouette)
	unit.set_meta("crash_style", crash_style)

	var ai := _get_ai(unit)
	if ai:
		ai.waypoints = PackedVector2Array([target_pos])
		ai.current_waypoint_index = 0
		ai.arrival_distance = 250.0

	unit.speed = cruise_kmh / 3.6
	unit.target_position = target_pos
	unit.set_target_tier(tier)
	# 直接赋值初始高度到目标层，保证一出生就在对应高度作战
	unit.altitude = CombatUnit.TIER_ALTITUDE[tier]
	unit.set_meta("despawn_after", mode.game_time + lifetime_sec)

## 刷一队 AH-64 Apache（4 架菱形/楔形编队）
##   - A→B 直线航线，采用 3 层菱形编队：
##       [0] 队长（前）
##     [1]   [2]  （左右两翼，后方一层）
##       [3] （殿后中线，再后一层）
##   - 每架挂 scatter_on_damage meta + flock_members 引用：任何一架被击中 → 整队散开
func _spawn_ah64_flock() -> void:
	var flock_size: int = SurvivorData.AH64_FLOCK_SIZE
	var pp := player_aircraft.global_position

	var route := _pick_safe_flock_route(pp, SurvivorData.SPAWN_DISTANCE, SurvivorData.AH64_FLIGHT_DISTANCE)
	var point_a: Vector2 = route.a
	var point_b: Vector2 = route.b
	var flight_dir: Vector2 = route.dir
	var lateral_axis := Vector2(-flight_dir.y, flight_dir.x)
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 直升机永远低空飞行
	var flock_tier: int = Aircraft.AltitudeTier.LOW

	# 菱形编队偏移（x = 沿航向前后，y = 侧向；负号代表远离队首）
	var fwd := SurvivorData.AH64_FORWARD_SPACING
	var lat := SurvivorData.AH64_LATERAL_SPACING
	var formation_offsets := [
		Vector2(0.0, 0.0),         # [0] 队长：最前中线
		Vector2(-fwd, -lat),       # [1] 左翼：后一层 + 左偏
		Vector2(-fwd,  lat),       # [2] 右翼：后一层 + 右偏
		Vector2(-fwd * 2.0, 0.0),  # [3] 殿后：再后一层，回到中线
	]

	var heli_list: Array[Aircraft] = []
	for i in range(flock_size):
		var local_off: Vector2 = formation_offsets[i]
		# 把菱形局部坐标旋到世界坐标：x 轴沿 flight_dir，y 轴沿 lateral_axis
		var world_off: Vector2 = flight_dir * local_off.x + lateral_axis * local_off.y
		var spawn_pos := point_a + world_off
		var target_pos := point_b + world_off  # 队形平移飞到终点

		# AH-64 事件触发，固定 V5 武器（"重型攻击直升机"手感，不跟玩家等级走）
		var heli := _create_enemy(EnemyType.AH64, spawn_pos, heading_deg, 5)
		_configure_adds_unit(heli, target_pos, flock_tier, 230.0, "apache", "heli", 140.0)
		heli.set_meta("scatter_on_damage", true)
		heli_list.append(heli)

	# 每架共享同一个 flock_members 列表（受击时 _apply_damage 遍历传播 scatter）
	for heli in heli_list:
		heli.flock_members = heli_list

	EventLogger.log_event("WAVE", "AH64Flock",
		"spawned %d AH-64 (diamond) from %s to %s" % [flock_size, point_a, point_b])

## 刷一队 CH-47 Chinook（纵阵 3 架，间距更大）
func _spawn_ch47_flock() -> void:
	var flock_size: int = SurvivorData.CH47_FLOCK_SIZE
	var pp := player_aircraft.global_position

	var route := _pick_safe_flock_route(pp, SurvivorData.SPAWN_DISTANCE, SurvivorData.CH47_FLIGHT_DISTANCE)
	var point_a: Vector2 = route.a
	var point_b: Vector2 = route.b
	var flight_dir: Vector2 = route.dir
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 运输直升机永远低空飞行
	var flock_tier: int = Aircraft.AltitudeTier.LOW

	for i in range(flock_size):
		var back_offset: Vector2 = -flight_dir * float(i) * SurvivorData.CH47_COLUMN_SPACING
		var spawn_pos := point_a + back_offset
		var target_pos := point_b + back_offset

		var heli := _create_enemy(EnemyType.CH47, spawn_pos, heading_deg)
		_configure_adds_unit(heli, target_pos, flock_tier, 215.0, "chinook", "heli", 150.0)

	EventLogger.log_event("WAVE", "CH47Flock",
		"spawned %d CH-47 (column) from %s to %s" % [flock_size, point_a, point_b])

# ══════════════════════════════════════════════
#  ADBS 事件专用生成（指定起点 + 逃离方向，不穿过玩家）
# ══════════════════════════════════════════════

## ADBS：一队轰炸机从 spawn_pos 沿 flee_dir 逃向边界
func spawn_bomber_flee(spawn_pos: Vector2, flee_dir: Vector2, count: int = 2) -> Array[Aircraft]:
	var flight_dir := flee_dir.normalized() if flee_dir.length_squared() > 0.001 else Vector2(0, -1)
	var point_b := spawn_pos + flight_dir * SurvivorData.TU160_FLIGHT_DISTANCE
	var lateral_axis := Vector2(-flight_dir.y, flight_dir.x)
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))
	var tier: int = Aircraft.AltitudeTier.HIGH
	var spawned: Array[Aircraft] = []
	for i in range(count):
		var lateral_slot := float(i) - (float(count) - 1.0) * 0.5
		var lateral: Vector2 = lateral_axis * lateral_slot * SurvivorData.TU160_LATERAL_SPACING
		var sp := spawn_pos + lateral
		var tp := point_b + lateral
		var bomber := _create_enemy(EnemyType.TU160, sp, heading_deg)
		_configure_adds_unit(bomber, tp, tier, 230.0, "bomber", "bomber", 120.0)
		spawned.append(bomber)
	EventLogger.log_event("ADBS", "BomberFlee",
		"spawned %d bombers at %s heading %.0f°" % [count, spawn_pos, heading_deg])
	return spawned

## ADBS：一队直升机从 spawn_pos 沿 flee_dir 逃向边界
func spawn_heli_flee(spawn_pos: Vector2, flee_dir: Vector2, count: int = 3) -> Array[Aircraft]:
	var flight_dir := flee_dir.normalized() if flee_dir.length_squared() > 0.001 else Vector2(0, -1)
	var point_b := spawn_pos + flight_dir * SurvivorData.CH47_FLIGHT_DISTANCE
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))
	var tier: int = Aircraft.AltitudeTier.LOW
	var spawned: Array[Aircraft] = []
	for i in range(count):
		var back_offset: Vector2 = -flight_dir * float(i) * SurvivorData.CH47_COLUMN_SPACING
		var sp := spawn_pos + back_offset
		var tp := point_b + back_offset
		var heli := _create_enemy(EnemyType.CH47, sp, heading_deg)
		_configure_adds_unit(heli, tp, tier, 215.0, "chinook", "heli", 150.0)
		spawned.append(heli)
	EventLogger.log_event("ADBS", "HeliFlee",
		"spawned %d helis at %s heading %.0f°" % [count, spawn_pos, heading_deg])
	return spawned

# ══════════════════════════════════════════════
#  BOSS encounter（BossRegistry / AceSquad / 未来 CSG 统一入口）
# ══════════════════════════════════════════════

## 生成已实例化的 BOSS encounter（调用方从 BossRegistry 拿实例）
## 不同 BOSS 类型调 spawner 内部分支（飞机类 / 舰队类 ...）
## skip_bgm = true：CSG 预驻阶段调用，不切 BOSS 曲（避免提前剧透）
##              玩家进入 BOSS 圈触发激活时由 survivor_mode 直接调 AudioManager 播放
func _spawn_boss(encounter: BossEncounter, anchor: Vector2 = Vector2.INF, skip_bgm: bool = false) -> void:
	if encounter == null:
		push_error("_spawn_boss: encounter is null")
		return
	if _boss and _boss.active:
		return
	_boss = encounter

	# 按 encounter 类型派发 spawn 参数
	if encounter is CarrierStrikeGroup:
		# 舰队 BOSS：CSG 自己构建舰队 + 管理 Phase 2 飞机子 encounter
		var csg := encounter as CarrierStrikeGroup
		csg.spawn(mode, _aircraft_scene, _create_enemy, player_aircraft,
			bullet_manager, missile_manager, _squads, anchor)
	elif encounter is AceSquad:
		var ace := encounter as AceSquad
		ace.anchor_position = anchor
		ace.spawn(mode, _aircraft_scene, _create_enemy, player_aircraft,
			bullet_manager, missile_manager, _squads)
	elif encounter is MotherGooseBoss:
		var goose := encounter as MotherGooseBoss
		goose.spawn(mode, _aircraft_scene, _create_enemy, player_aircraft,
			bullet_manager, missile_manager, _squads, anchor)
	else:
		push_error("_spawn_boss: unsupported encounter type %s" % encounter.get_class())
		_boss = null
		return

	# BOSS 登场：淡出泛用战斗曲，淡入 BOSS 专用曲
	# bgm_layers 非空 → 层叠模式（CSG 双阶段同步）；否则单轨 crossfade（F-47 等）
	if skip_bgm:
		return
	if not encounter.bgm_layers.is_empty():
		AudioManager.play_layered_music(encounter.bgm_layers, 2.0, 0)
	elif encounter.bgm_track != "":
		AudioManager.crossfade_music(encounter.bgm_track, 2.0)

## 向后兼容：Debug 面板 / 老代码直接调这个刷 F-47
func _spawn_f47_squad(anchor: Vector2 = Vector2.INF) -> void:
	var enc := BossRegistry.instantiate("WRAITH_SQUADRON")
	if enc:
		_spawn_boss(enc, anchor)

# ══════════════════════════════════════════════
#  敌机创建（核心工厂函数）
# ══════════════════════════════════════════════

## 创建单架敌机并添加到场景（公共逻辑）
func _create_enemy(etype: EnemyType, spawn_pos: Vector2, heading_deg: float, tier_override: int = -1) -> Aircraft:
	# 选择基础参数
	var base_params: AircraftParams
	match etype:
		EnemyType.MIG:
			base_params = _enemy_params_base
		EnemyType.INTERCEPTOR:
			base_params = _interceptor_params_base
		EnemyType.UCAV:
			base_params = _ucav_params_base
		EnemyType.UAV_COMMANDER:
			base_params = _commander_params_base
		EnemyType.F86:
			base_params = _f86_params_base
		EnemyType.MIG31:
			base_params = _mig31_params_base
		EnemyType.MIG23:
			base_params = _mig23_params_base
		EnemyType.F100:
			base_params = _f100_params_base
		EnemyType.SU27:
			base_params = _su27_params_base
		EnemyType.A7:
			base_params = _a7_params_base
		EnemyType.Q5:
			base_params = _q5_params_base
		EnemyType.TU160:
			base_params = _tu160_params_base
		EnemyType.AH64:
			base_params = _ah64_params_base
		EnemyType.CH47:
			base_params = _ch47_params_base
		EnemyType.F47:
			base_params = _f47_params_base
		EnemyType.F14_POLTERGEIST:
			base_params = _f14_poltergeist_params_base
		EnemyType.AF03:
			base_params = _af03_params_base
		EnemyType.UAV_LASER:
			base_params = _uav_laser_params_base
		EnemyType.F4:
			base_params = _f4_params_base
		EnemyType.F104:
			base_params = _f104_params_base
		EnemyType.SU35:
			base_params = _su35_params_base
		EnemyType.FA18:
			base_params = _fa18_params_base
		_:
			base_params = _uav_params_base

	var enemy: Aircraft = _aircraft_scene.instantiate()
	var enemy_params: AircraftParams = base_params.duplicate(true)
	# 手动 duplicate 所有外部子资源，避免累积修改污染基础资源
	# ⚠ duplicate(true) 只深拷贝 AircraftParams 本身，嵌套的 Resource 字段仍是共享引用
	if enemy_params.missile:
		enemy_params.missile = enemy_params.missile.duplicate()
	if enemy_params.secondary_missile:
		enemy_params.secondary_missile = enemy_params.secondary_missile.duplicate()
	if enemy_params.gun:
		enemy_params.gun = enemy_params.gun.duplicate()
	if enemy_params.flare:
		enemy_params.flare = enemy_params.flare.duplicate()
	if enemy_params.rocket:
		enemy_params.rocket = enemy_params.rocket.duplicate()
	if enemy_params.combat:
		enemy_params.combat = enemy_params.combat.duplicate()

	# 敌人武器 V_N 等级注入（机炮 / 后续批次会扩展导弹+火箭弹）
	# 玩家等级决定基线 tier，敌人种类带 ±N 偏移；事件可显式传 tier_override
	_inject_weapon_tier(enemy_params, etype, tier_override)

	# 根据等级缩放（载人战机走 enemy_scale_for_level，含 MiG-31/23/F-100）
	var scale: Dictionary
	if etype == EnemyType.MIG or etype == EnemyType.INTERCEPTOR or etype == EnemyType.F86 \
			or etype == EnemyType.MIG31 or etype == EnemyType.MIG23 or etype == EnemyType.F100 \
			or etype == EnemyType.SU27 or etype == EnemyType.A7 or etype == EnemyType.Q5 \
			or etype == EnemyType.AF03 \
			or etype == EnemyType.F4 or etype == EnemyType.F104 or etype == EnemyType.SU35 \
			or etype == EnemyType.FA18:
		scale = SurvivorData.enemy_scale_for_level(survivor_player.level)
	elif etype == EnemyType.UAV_COMMANDER:
		scale = SurvivorData.commander_scale_for_level(survivor_player.level)
	elif etype == EnemyType.TU160 or etype == EnemyType.AH64 or etype == EnemyType.CH47:
		# Adds 杂兵：无缩放（一击必杀才有设计意义）
		scale = {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}
	elif etype == EnemyType.F47 or etype == EnemyType.F14_POLTERGEIST:
		# BOSS 飞机（F-47 / F-14 Poltergeist）：无缩放（按满级玩家平衡，固定参数）
		scale = {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}
	elif etype == EnemyType.UAV_LASER:
		# 拦截支援机：固定参数（不需要按等级提升 HP/伤害）
		scale = {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}
	else:
		scale = SurvivorData.uav_scale_for_level(survivor_player.level)

	enemy_params.max_hp *= float(scale["hp_mult"])
	# 导弹一击必杀：除 Sentinel 外，HP 不得超过导弹伤害（确保任何等级被导弹命中即死）
	if etype != EnemyType.UAV_COMMANDER:
		enemy_params.max_hp = minf(enemy_params.max_hp, SurvivorData.ENEMY_HP_MISSILE_CAP)
	if enemy_params.missile:
		enemy_params.missile.max_count += int(scale["missile_add"])
	if enemy_params.gun:
		enemy_params.gun.bullet_damage *= float(scale["gun_damage_mult"])
	# 火箭弹伤害随等级轻度增长（命中率低，整体威胁还是有限）
	if (etype == EnemyType.F86 or etype == EnemyType.A7 or etype == EnemyType.Q5) and enemy_params.rocket:
		enemy_params.rocket.rocket_damage *= 1.0 + (survivor_player.level - 1) * 0.04

	# 敌机热诱弹限制：整个生命周期只允许释放一次，且只释放 1 枚
	# （只够干扰玩家第一枚导弹，之后就没弹了，玩家第二发会命中）
	# F-47 BOSS 豁免此限制：6 代电子战允许多次释放
	if enemy_params.flare:
		if etype != EnemyType.F47 and etype != EnemyType.F14_POLTERGEIST:
			enemy_params.flare.burst_count = 1
			enemy_params.flare.max_flares = 1
		# 热诱弹失误概率：编队低级机高失误率，精英单机低失误率
		match etype:
			EnemyType.UAV:
				enemy_params.flare.fail_chance = 0.85
			EnemyType.UCAV:
				enemy_params.flare.fail_chance = 0.80
			EnemyType.F86:
				enemy_params.flare.fail_chance = 0.65
			EnemyType.MIG23:
				enemy_params.flare.fail_chance = 0.55
			EnemyType.INTERCEPTOR:
				enemy_params.flare.fail_chance = 0.50
				enemy_params.flare.head_on_fail_reduction = 0.25
			EnemyType.MIG:
				enemy_params.flare.fail_chance = 0.45
			EnemyType.F100:
				enemy_params.flare.fail_chance = 0.45
				enemy_params.flare.head_on_fail_reduction = 0.20
			EnemyType.MIG31:
				enemy_params.flare.fail_chance = 0.15
				enemy_params.flare.head_on_fail_reduction = 0.10
			EnemyType.SU27:
				enemy_params.flare.fail_chance = 0.15
			EnemyType.SU35:
				enemy_params.flare.fail_chance = 0.10
				enemy_params.flare.head_on_fail_reduction = 0.05
			EnemyType.UAV_COMMANDER:
				enemy_params.flare.fail_chance = 0.0
			EnemyType.AH64:
				# 攻击直升机：战斗机组，反应快但只有 1 枚热诱弹，35% 概率未能释放
				enemy_params.flare.fail_chance = 0.35
			EnemyType.CH47:
				# 运输直升机：机组偏向飞行而非战斗，50% 概率未能释放
				enemy_params.flare.fail_chance = 0.50
			EnemyType.F47:
				# F-47 王牌：6 代电子战套件，不限制为 1 枚（BOSS 豁免热诱弹削弱）
				enemy_params.flare.fail_chance = 0.05
				enemy_params.flare.head_on_fail_reduction = 0.05
			EnemyType.F14_POLTERGEIST:
				# F-14 Poltergeist：舰载 BOSS，标准电子战，比 F-47 弱
				enemy_params.flare.fail_chance = 0.15
				enemy_params.flare.head_on_fail_reduction = 0.10

	enemy.params = enemy_params
	enemy.team = 1
	enemy.infinite_fuel = true
	# 生存模式弹药：所有敌机走"有限弹匣 + 冷却装填"，与玩家一致；越精锐 reload 越快
	enemy.infinite_ammo = false
	enemy.enable_gun_reload = true
	enemy.enable_missile_reload = true
	match etype:
		EnemyType.F47, EnemyType.F14_POLTERGEIST:
			# BOSS 级：高节奏齐射，10 秒回满
			enemy.gun_reload_duration = 10.0
			enemy.missile_reload_duration = 10.0
			if enemy_params.missile:
				enemy_params.missile.cooldown = 1.5
		EnemyType.SU27, EnemyType.MIG31, EnemyType.SU35:
			# 顶级精英单机：15 秒
			enemy.gun_reload_duration = 15.0
			enemy.missile_reload_duration = 15.0
			if enemy_params.missile:
				enemy_params.missile.cooldown = 2.0
		_:
			# 默认 20 秒（与玩家档案默认一致）
			enemy.gun_reload_duration = 20.0
			enemy.missile_reload_duration = 20.0
			if enemy_params.missile:
				enemy_params.missile.cooldown = 2.5

	var type_tag: String
	match etype:
		EnemyType.MIG: type_tag = "mig"
		EnemyType.INTERCEPTOR: type_tag = "interceptor"
		EnemyType.F86: type_tag = "f86"
		EnemyType.MIG31: type_tag = "mig31"
		EnemyType.MIG23: type_tag = "mig23"
		EnemyType.F100: type_tag = "f100"
		EnemyType.SU27: type_tag = "su27"
		EnemyType.A7: type_tag = "a7"
		EnemyType.Q5: type_tag = "q5"
		EnemyType.UCAV: type_tag = "ucav"
		EnemyType.UAV_COMMANDER: type_tag = "uav_commander"
		EnemyType.TU160: type_tag = "tu160"
		EnemyType.AH64: type_tag = "ah64"
		EnemyType.CH47: type_tag = "ch47"
		EnemyType.F47: type_tag = "f47"
		EnemyType.F14_POLTERGEIST: type_tag = "f14_poltergeist"
		EnemyType.AF03: type_tag = "af03"
		EnemyType.UAV_LASER: type_tag = "uav_laser"
		EnemyType.F4: type_tag = "f4"
		EnemyType.F104: type_tag = "f104"
		EnemyType.SU35: type_tag = "su35"
		EnemyType.FA18: type_tag = "fa18"
		_: type_tag = "uav"
	enemy.set_meta("enemy_type", type_tag)
	# Token 系统元数据：便于重算占用与实例计数
	enemy.set_meta("enemy_type_idx", int(etype))
	enemy.set_meta("token_cost", int(SurvivorData.TOKEN_COST.get(int(etype), 1)))

	# 无驾驶员标记：UAV / UCAV / Sentinel / Aegis UAV 不受心理类状态（FEAR）影响
	# 配套 Aircraft.apply_status 覆写，对 no_pilot=true 的飞机静默丢弃 FEAR
	if etype == EnemyType.UAV or etype == EnemyType.UCAV \
			or etype == EnemyType.UAV_COMMANDER or etype == EnemyType.UAV_LASER:
		enemy.no_pilot = true

	# UAV 类不使用代号库，直接用类型+编号
	if etype == EnemyType.UAV or etype == EnemyType.UCAV or etype == EnemyType.UAV_COMMANDER:
		_uav_serial += 1
		enemy.callsign = "%s-%02d" % [type_tag.to_upper(), _uav_serial]
	elif etype == EnemyType.TU160:
		# Tu-160 北约代号 Blackjack
		_tu160_serial += 1
		enemy.callsign = "BLKJK-%02d" % _tu160_serial
	elif etype == EnemyType.AH64:
		_ah64_serial += 1
		enemy.callsign = "APA-%02d" % _ah64_serial
	elif etype == EnemyType.CH47:
		_ch47_serial += 1
		enemy.callsign = "CHK-%02d" % _ch47_serial
	elif etype == EnemyType.FA18:
		_fa18_serial += 1
		enemy.callsign = "HRNT-%02d" % _fa18_serial
	elif etype == EnemyType.F47 or etype == EnemyType.F14_POLTERGEIST:
		# 呼号由当前 BOSS AceSquad 的 _serial + callsign_prefix 共同决定
		# F-47 → WRAITH-XX，F-14 Poltergeist (CSG Phase 2) → PLTGST-XX
		var ace_ref: AceSquad = _boss.get_active_ace_squad() if _boss else null
		if ace_ref:
			ace_ref._serial += 1
			enemy.callsign = "%s-%02d" % [ace_ref.callsign_prefix, ace_ref._serial]
		else:
			enemy.callsign = "BOSS-%02d" % (randi() % 99 + 1)

	enemy.position = spawn_pos
	enemy.initial_heading_deg = heading_deg

	mode.add_child(enemy)

	# 注入管理器
	enemy.bullet_manager = bullet_manager
	enemy.missile_manager = missile_manager
	# 三档高度模式
	enemy.flat_altitude = true
	var enemy_tiers := [Aircraft.AltitudeTier.LOW, Aircraft.AltitudeTier.MID, Aircraft.AltitudeTier.HIGH]
	enemy.set_target_tier(enemy_tiers[randi() % enemy_tiers.size()])

	# AI 控制器
	var ai := AIController.new()
	ai.name = "AI_%s" % enemy.name
	ai.aircraft = enemy
	ai.patrol_altitude = randf_range(4000.0, 8000.0)
	var pp := player_aircraft.global_position
	ai.waypoints = PackedVector2Array([
		pp + Vector2(1200, -1200),
		pp + Vector2(1200, 1200),
		pp + Vector2(-1200, 1200),
		pp + Vector2(-1200, -1200),
	])
	ai.enable_combat = true
	ai.engage_cooldown = 3.0
	ai.engage_duration = 30.0

	match etype:
		EnemyType.MIG:
			ai.evade_missiles = true
			ai.aggression = randf_range(0.6, 0.95)
			ai.engage_cooldown = 2.0
			var level_bonus := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.3, 0.65) + level_bonus, 0.3, 0.95)
			ai.composure = clampf(randf_range(0.2, 0.55) + level_bonus, 0.2, 0.9)
			ai.focus = clampf(randf_range(0.5, 0.85) + level_bonus * 0.5, 0.5, 0.95)
			ai.self_preservation = randf_range(0.1, 0.5)
		EnemyType.INTERCEPTOR:
			# J-7 = Lancer 骑士型打带跑：开加力单次突击后脱离
			ai.evade_missiles = false
			ai.aggression = randf_range(0.6, 0.8)
			ai.engage_cooldown = 8.0
			ai.engage_duration = 5.0
			var level_bonus_int := clampf(float(survivor_player.level) / 20.0, 0.0, 0.2)
			ai.skill_level = clampf(randf_range(0.3, 0.5) + level_bonus_int, 0.3, 0.7)
			ai.composure = clampf(randf_range(0.2, 0.4) + level_bonus_int, 0.2, 0.6)
			ai.focus = clampf(randf_range(0.3, 0.5) + level_bonus_int * 0.5, 0.3, 0.7)
			ai.self_preservation = randf_range(0.3, 0.6)
			if enemy_params.gun:
				enemy_params.gun = enemy_params.gun.duplicate()
				enemy_params.gun.fire_rate = 2000.0
				enemy_params.gun.bullet_damage *= 0.6
				enemy_params.gun.fire_cone_half_angle = 3.0
		EnemyType.F86:
			# F-86 = Gladiator 斗士型：积极近身狗斗 + 火箭弹骚扰
			ai.evade_missiles = false
			ai.aggression = randf_range(0.85, 1.0)   # 极高攻击欲
			ai.engage_cooldown = 1.5                  # 很快就再次冲锋
			ai.engage_duration = 45.0                 # 持续缠斗
			var lbonus_f86 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.4, 0.65) + lbonus_f86, 0.4, 0.9)
			ai.composure = clampf(randf_range(0.35, 0.65) + lbonus_f86, 0.35, 0.9)
			ai.focus = clampf(randf_range(0.65, 0.9) + lbonus_f86 * 0.5, 0.65, 0.95)  # 死盯玩家
			ai.self_preservation = randf_range(0.15, 0.4)  # 不怕死 → 不拉开
			ai.situational_awareness = randf_range(0.4, 0.7)
		EnemyType.MIG31:
			# MiG-31 = Lancer 顶级（最强骑士型）：超高速远距 BVR 截击 + 一击脱离
			# 单机出现，威胁极高；用雷达弹打远距，机炮只是补刀
			ai.evade_missiles = true
			ai.aggression = randf_range(0.7, 0.9)
			ai.engage_cooldown = 6.0                  # 比 J-7 短，但仍长于狗斗机
			ai.engage_duration = 9.0                  # 一次突击 9 秒后脱离
			var lbonus_m31 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.35)
			ai.skill_level = clampf(randf_range(0.6, 0.85) + lbonus_m31, 0.6, 0.98)
			ai.composure = clampf(randf_range(0.55, 0.8) + lbonus_m31, 0.55, 0.95)
			ai.focus = clampf(randf_range(0.7, 0.9) + lbonus_m31 * 0.5, 0.7, 0.98)
			ai.self_preservation = randf_range(0.4, 0.7)
			ai.situational_awareness = randf_range(0.6, 0.85)
		EnemyType.MIG23:
			# MiG-23 = Gladiator 综合型：编队斗士，导弹+机炮通吃，缠斗能力强
			ai.evade_missiles = true
			ai.aggression = randf_range(0.7, 0.95)
			ai.engage_cooldown = 2.0
			ai.engage_duration = 35.0
			var lbonus_m23 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.45, 0.7) + lbonus_m23, 0.45, 0.92)
			ai.composure = clampf(randf_range(0.4, 0.65) + lbonus_m23, 0.4, 0.9)
			ai.focus = clampf(randf_range(0.55, 0.85) + lbonus_m23 * 0.5, 0.55, 0.95)
			ai.self_preservation = randf_range(0.2, 0.5)
			ai.situational_awareness = randf_range(0.45, 0.75)
		EnemyType.F100:
			# F-100 = Lancer 编队型：高速突击编队，雷达弹照射后脱离
			# 比 J-7 强（更高 skill / 雷达弹），但比 MiG-31 弱
			ai.evade_missiles = true
			ai.aggression = randf_range(0.65, 0.85)
			ai.engage_cooldown = 5.0
			ai.engage_duration = 7.0
			var lbonus_f100 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.45, 0.7) + lbonus_f100, 0.45, 0.85)
			ai.composure = clampf(randf_range(0.4, 0.6) + lbonus_f100, 0.4, 0.8)
			ai.focus = clampf(randf_range(0.5, 0.75) + lbonus_f100 * 0.5, 0.5, 0.85)
			ai.self_preservation = randf_range(0.3, 0.55)
			ai.situational_awareness = randf_range(0.5, 0.75)
		EnemyType.SU27:
			# Su-27 = 斗士型 + 眼镜蛇机动：积极近身狗斗 + 一次性眼镜蛇防御
			ai.evade_missiles = true
			ai.aggression = randf_range(0.8, 1.0)         # 极高攻击欲（斗士型）
			ai.engage_cooldown = 1.5                       # 快速再次冲锋
			ai.engage_duration = 40.0                      # 长时间缠斗
			var lbonus_su27 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.55, 0.8) + lbonus_su27, 0.55, 0.95)
			ai.composure = clampf(randf_range(0.5, 0.75) + lbonus_su27, 0.5, 0.9)
			ai.focus = clampf(randf_range(0.7, 0.9) + lbonus_su27 * 0.5, 0.7, 0.95)  # 死盯玩家
			ai.self_preservation = randf_range(0.1, 0.35)  # 不怕死
			ai.situational_awareness = randf_range(0.5, 0.75)
			# 斗士型削弱雷达（偏好狗斗而非 BVR）
			enemy_params.radar_range = 2500.0
			enemy_params.radar_half_angle = 20.0
			# 挂载眼镜蛇机动模块
			var cobra := CobraManeuver.new()
			cobra.name = "CobraManeuver"
			enemy.add_child(cobra)
		EnemyType.SU35:
			# Su-35 = Su-27 强化版（4.5 代 + TVC）：行为同 Su-27 + Cobra，但数值/技能更高
			ai.evade_missiles = true
			ai.aggression = randf_range(0.85, 1.0)
			ai.engage_cooldown = 1.2                       # 比 Su-27 还短，更激进
			ai.engage_duration = 45.0
			var lbonus_su35 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.35)
			ai.skill_level = clampf(randf_range(0.65, 0.88) + lbonus_su35, 0.65, 0.98)
			ai.composure = clampf(randf_range(0.55, 0.8) + lbonus_su35, 0.55, 0.95)
			ai.focus = clampf(randf_range(0.75, 0.92) + lbonus_su35 * 0.5, 0.75, 0.98)
			ai.self_preservation = randf_range(0.1, 0.3)
			ai.situational_awareness = randf_range(0.6, 0.85)
			# 比 Su-27 雷达更强（4.5 代）
			enemy_params.radar_range = 3000.0
			enemy_params.radar_half_angle = 22.0
			# 沿用 Su-27 的眼镜蛇机动（同一模块，复用 CobraManeuver）
			var cobra_su35 := CobraManeuver.new()
			cobra_su35.name = "CobraManeuver"
			enemy.add_child(cobra_su35)
		EnemyType.FA18:
			# F/A-18 = Gladiator 均衡舰载机（CSG BOSS 弹射出现）
			# 海军飞行员训练扎实：技能 / 专注 / 心理素质都比常规敌机高
			# 行为：积极近身狗斗（标志 Gladiator），不害怕缠斗，强调持续高 G 转弯
			# 数值梯度：技能略胜 MiG-23（0.55-0.78 vs 0.45-0.7），低于 Su-27（0.55-0.8）
			ai.evade_missiles = true
			ai.aggression = randf_range(0.85, 1.0)         # 极高攻击欲（Gladiator 标配）
			ai.engage_cooldown = 1.5                       # 快速再次冲锋
			ai.engage_duration = 35.0                      # 长缠斗
			var lbonus_fa18 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.55, 0.78) + lbonus_fa18, 0.55, 0.95)
			ai.composure = clampf(randf_range(0.5, 0.72) + lbonus_fa18, 0.5, 0.92)
			ai.focus = clampf(randf_range(0.7, 0.9) + lbonus_fa18 * 0.5, 0.7, 0.95)
			ai.self_preservation = randf_range(0.15, 0.4)  # 不怕死 → 持续压迫
			ai.situational_awareness = randf_range(0.5, 0.78)
		EnemyType.F4:
			# F-4 Phantom = Gladiator 中段（导弹卡车）：贴上来打导弹齐射，盘旋差但弹量大
			# 类比 MiG-23 但更重更慢，靠双弹种总弹量补偿
			ai.evade_missiles = true
			ai.aggression = randf_range(0.7, 0.95)
			ai.engage_cooldown = 2.5                       # 比 MiG-23 略慢（重）
			ai.engage_duration = 32.0
			var lbonus_f4 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.28)
			ai.skill_level = clampf(randf_range(0.5, 0.72) + lbonus_f4, 0.5, 0.92)
			ai.composure = clampf(randf_range(0.45, 0.7) + lbonus_f4, 0.45, 0.9)
			ai.focus = clampf(randf_range(0.6, 0.85) + lbonus_f4 * 0.5, 0.6, 0.95)
			ai.self_preservation = randf_range(0.25, 0.5)
			ai.situational_awareness = randf_range(0.5, 0.75)
		EnemyType.F104:
			# F-104 = Lancer 纯速度截击（"载人导弹"）：极速通过 + 一次发射后脱离
			# 比 J-7 更激进（更高 aggression / 短 cooldown），但 HP 极低
			ai.evade_missiles = false
			ai.aggression = randf_range(0.65, 0.85)
			ai.engage_cooldown = 7.0                       # 比 J-7 短（更高频突击）
			ai.engage_duration = 5.5
			var lbonus_f104 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.22)
			ai.skill_level = clampf(randf_range(0.35, 0.58) + lbonus_f104, 0.35, 0.78)
			ai.composure = clampf(randf_range(0.25, 0.45) + lbonus_f104, 0.25, 0.65)
			ai.focus = clampf(randf_range(0.4, 0.6) + lbonus_f104 * 0.5, 0.4, 0.78)
			ai.self_preservation = randf_range(0.3, 0.55)
			ai.situational_awareness = randf_range(0.4, 0.65)
		EnemyType.A7:
			# A-7 = Lancer 亚音速攻击机：火神炮+祖尼火箭弹，高HP低机动，编队突击
			# 亚音速无后燃器，靠大弹药量和火箭弹齐射制造威胁
			ai.evade_missiles = false
			ai.aggression = randf_range(0.6, 0.8)
			ai.engage_cooldown = 6.0
			ai.engage_duration = 8.0
			var lbonus_a7 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.2)
			ai.skill_level = clampf(randf_range(0.3, 0.55) + lbonus_a7, 0.3, 0.7)
			ai.composure = clampf(randf_range(0.3, 0.5) + lbonus_a7, 0.3, 0.65)
			ai.focus = clampf(randf_range(0.4, 0.65) + lbonus_a7 * 0.5, 0.4, 0.75)
			ai.self_preservation = randf_range(0.3, 0.55)
			ai.situational_awareness = randf_range(0.35, 0.6)
		EnemyType.Q5:
			# Q-5 = Lancer 超音速攻击机（MiG-19 底子）：23mm双炮+57mm火箭弹，编队突击
			# 比 A-7 更快更灵活，但 HP 更低
			ai.evade_missiles = false
			ai.aggression = randf_range(0.65, 0.85)
			ai.engage_cooldown = 5.5
			ai.engage_duration = 7.0
			var lbonus_q5 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.35, 0.6) + lbonus_q5, 0.35, 0.75)
			ai.composure = clampf(randf_range(0.3, 0.55) + lbonus_q5, 0.3, 0.7)
			ai.focus = clampf(randf_range(0.45, 0.7) + lbonus_q5 * 0.5, 0.45, 0.8)
			ai.self_preservation = randf_range(0.25, 0.5)
			ai.situational_awareness = randf_range(0.4, 0.65)
		EnemyType.UAV_COMMANDER:
			# Sentinel = Schemer 策士型：空中指挥/预警 + 光环 buff 招募僚机
			# 自身无武装，靠特殊机制（CommanderAura）影响战场，玩家靠近即脱离
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.self_preservation = randf_range(0.8, 1.0)
		EnemyType.TU160:
			# Tu-160 = Adds 杂兵：沿固定直线航线飞行，无反击/无规避/无雷达
			# 唯一行为：按 waypoints 直线飞到终点；实际 waypoints 由 _spawn_tu160_flock 设置
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.aggression = 0.0
			ai.self_preservation = 0.0
			ai.orbit_squad_leader = false
		EnemyType.CH47:
			# CH-47 = Adds 运输直升机：纯直线飞行，无武装，无反击
			# 有 1 枚热诱弹（fail_chance 决定是否真的释放，AircraftFlares.update 被动触发）
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.aggression = 0.0
			ai.self_preservation = 0.0
			ai.orbit_squad_leader = false
		EnemyType.F47:
			# F-47 = BOSS 王牌狙击小队：第一要务是消灭玩家
			# bvr_only 由 _update_f47_squad 动态控制（被盯上的逃，其他攻击）
			ai.evade_missiles = true
			ai.bvr_only = false                           # 默认不逃——主动攻击
			ai.boss_attacker = true                       # F-47 全员攻击手（EVADER 角色已废弃）
			ai.aggression = randf_range(0.90, 1.0)        # 极高攻击欲
			ai.engage_cooldown = 0.5                      # 几乎无冷却
			ai.engage_duration = 999.0                    # 永不自动脱离交战
			ai.skill_level = 0.95                         # 王牌
			ai.composure = 0.95
			ai.focus = 0.95
			ai.self_preservation = randf_range(0.10, 0.25) # 低自保——杀玩家优先
			ai.situational_awareness = 0.95
		EnemyType.F14_POLTERGEIST:
			# F-14 Poltergeist = CSG 第二阶段舰载 BOSS 中队
			# 性格：Lancer 骑士型 — 偏好高速对头突击 + 一次发射后脱离换 BVR 站位
			# 与 Gladiator 区分：不缠斗，喜欢和玩家正面对穿（merge pass）
			# Lancer 节奏由 lancer_combat.tres 提供（intercept_range_mult 3.5 / closing_rate 0.20 → 不抱尾，闭合率不足即拉开）
			ai.evade_missiles = true
			ai.bvr_only = false
			ai.boss_attacker = true
			ai.aggression = randf_range(0.75, 0.9)         # 高但比 Gladiator 略克制（突击型）
			ai.engage_cooldown = 5.0                       # Lancer 长冷却（突击间隔）
			ai.engage_duration = 9.0                       # 一次突击 9 秒后脱离 → 拉开重新对头
			ai.skill_level = 0.82                          # 精英级，略低于 F-47
			ai.composure = 0.85
			ai.focus = 0.90
			ai.self_preservation = randf_range(0.20, 0.40) # Lancer 比 Gladiator 高一点（不缠斗 → 注重活着脱离）
			ai.situational_awareness = 0.88
		EnemyType.AH64:
			# AH-64 = Adds 攻击直升机：带机炮+火箭弹，但 ground_combat_only 限定只攻地面
			# 空中永远不交战，主航线仍是直线飞行；途中遇到地面单位会做 strafing 打击
			# 受击后 _apply_damage 会触发 flock_scatter → AIController 做 jink 机动
			ai.simple_ai = true
			ai.enable_combat = true
			ai.ground_combat_only = true     ## AI 选目标时过滤非 GroundUnit
			ai.evade_missiles = false
			ai.aggression = 0.7
			ai.self_preservation = 0.2
			ai.orbit_squad_leader = false
			ai.engage_duration = 12.0        ## 打完 10 多秒就脱离回航线
			ai.engage_cooldown = 4.0
			enemy.attack_air_targets = false  ## _auto_gun_scan 跳过空中目标（防止扫到玩家）
		EnemyType.AF03:
			# AF-03 = 试验机精英狙击手 — 自有"电磁炮甜点距离"策略
			# 三层组合：
			#   1. bvr_only + 自定义 standoff/flee (5-8km)：维持远距站位
			#   2. prefer_nose_aligned_weapon=true：交战时走 SNIPER_HOLD 战术
			#      （直瞄玩家当前位置 + 减速稳瞄，不像 LEAD_PURSUIT 追前置点）
			#   3. Lancer engage_duration/cooldown：打完一发 disengage 拉开
			ai.bvr_only = true
			ai.bvr_standoff_min_px_override = 2500.0  ## 5km
			ai.bvr_flee_distance_px_override = 4000.0 ## 8km
			ai.prefer_nose_aligned_weapon = true      ## 优先 SNIPER_HOLD 而非 LEAD_PURSUIT
			ai.evade_missiles = true
			ai.aggression = 0.95
			ai.engage_cooldown = 7.0
			ai.engage_duration = 10.0
			ai.skill_level = 0.92
			ai.composure = 0.88
			ai.focus = 0.95
			ai.self_preservation = 0.5
			ai.situational_awareness = 0.88
		EnemyType.UAV_LASER:
			# Aegis UAV：拦截特化，无对空武器，不主动交战
			# 跟随 Sentinel 编队，靠激光拦导弹
			ai.simple_ai = true
			ai.enable_combat = false            # 不通过 AI 决策开火（laser update 自己扫描）
			ai.evade_missiles = true
			ai.aggression = 0.0
			ai.self_preservation = 0.95
			ai.orbit_squad_leader = true
			enemy.attack_air_targets = false
		_:
			ai.simple_ai = true
			ai.evade_missiles = false
			ai.aggression = randf_range(0.4, 0.7)

	# 斗士型基础机炮闪避：combat_bank_aggression > 1.0 的机型
	# 按 skill_level 梯度：低技能 5%，高技能 15%
	if enemy_params.combat and enemy_params.combat.combat_bank_aggression > 1.0:
		enemy.bullet_dodge_chance = lerpf(0.05, 0.15, ai.skill_level)

	# ── F-47 BOSS 抗性设定 ──
	if etype == EnemyType.F47:
		enemy.bullet_dodge_chance = 0.60   # 60% 闪避 = 40% 命中率（闪避时触发滚转动画）
		enemy.boss_flare_immunity = true   # 热诱弹释放后享有导弹穿透无敌时间
	elif etype == EnemyType.F14_POLTERGEIST:
		# F-14 Poltergeist：比 F-47 弱的 BOSS 级抗性
		enemy.bullet_dodge_chance = 0.35
		enemy.boss_flare_immunity = true

	# P4：实验性 — TacticalPlanner 接管 BFM 几何/速度决策（关闭 BFMTactics 执行）
	# 由 SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI 主开关控制，默认 false
	# 跳过 adds（Tu-160/AH-64/CH-47，simple_ai 无 BFM）/ Schemer（Sentinel commander_aura buff 系统）
	# F-47/F-14_Poltergeist BOSS 已纳入：BVR flee / Herbst / Cloak 独立模块在 planner 之后写
	# target_position 自然覆写；aggression 0.85+ 自动跳过 BOOM_ZOOM_OUT（commit 设计）
	if SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI:
		var is_planner_eligible: bool = etype in [
			EnemyType.MIG, EnemyType.INTERCEPTOR, EnemyType.F86,
			EnemyType.MIG23, EnemyType.F100, EnemyType.A7, EnemyType.Q5,
			EnemyType.MIG31, EnemyType.SU27,
			EnemyType.F4, EnemyType.F104, EnemyType.SU35,
			EnemyType.FA18,
			EnemyType.F47, EnemyType.F14_POLTERGEIST,  # BOSS 王牌中队
		]
		if is_planner_eligible:
			enemy.use_tactical_planner = true

	enemy.add_child(ai)
	return enemy

# ══════════════════════════════════════════════
#  远距清理 & 猎手 & 航点
# ══════════════════════════════════════════════

## 远距清理：飞出战区的敌机静默移除，释放占用的 Token
## 不触发击杀逻辑（不播坠毁动画、不给经验）
func _update_far_cleanup(delta: float) -> void:
	_far_cleanup_timer -= delta
	if _far_cleanup_timer > 0.0:
		return
	_far_cleanup_timer = SurvivorData.FAR_CLEANUP_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return

	var pp := player_aircraft.global_position
	var cleanup_d2 := SurvivorData.FAR_CLEANUP_DISTANCE * SurvivorData.FAR_CLEANUP_DISTANCE
	var removed := 0
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var ac: Aircraft = child
			# Adds 杂兵（Tu-160 等族群）不受远距清理影响，它们沿固定航线飞过战场
			if ac.has_meta("skip_far_cleanup") and ac.get_meta("skip_far_cleanup"):
				continue
			if ac.global_position.distance_squared_to(pp) > cleanup_d2:
				# 防止 _detect_kills 在同帧误判为击杀
				ac.set_meta("xp_granted", true)
				ac.queue_free()
				removed += 1

	if removed > 0:
		EventLogger.log_event("TOKEN", "FarCleanup", "despawned %d distant enemies" % removed)

## BOSS 阶段清场：只保留画面内的残余敌机；画面外或距离过远的都撤走。
## 铁则：不在玩家画面内消失。
##   - 画面外（+ margin 200 px）→ 立即 queue_free
##   - 画面内但距离玩家 > BOSS_PURGE_NEAR_DISTANCE → 入 zone_mission._pending_despawn
##     队列（飘出画面后才 free；不会瞬消）
## BOSS 本体（category="boss"）和 adds（skip_far_cleanup meta）不受此影响。
const BOSS_PURGE_INTERVAL := 1.0
const BOSS_PURGE_NEAR_DISTANCE := 4000.0  ## 超过此距离的残余敌机强制进入延迟撤离队列
func _update_boss_phase_purge(delta: float) -> void:
	_boss_purge_timer -= delta
	if _boss_purge_timer > 0.0:
		return
	_boss_purge_timer = BOSS_PURGE_INTERVAL
	if not mode or not player_aircraft or player_aircraft.is_destroyed:
		return

	var pp := player_aircraft.global_position
	var near_d2 := BOSS_PURGE_NEAR_DISTANCE * BOSS_PURGE_NEAR_DISTANCE
	var freed := 0
	var scheduled := 0
	for child in mode.get_children():
		if not (child is Aircraft):
			continue
		var ac: Aircraft = child
		if ac.team == 0 or ac.is_destroyed:
			continue
		# BOSS 本体（F-47 小队）不动
		var cat: String = ac.get_meta("category", "")
		if cat == "boss":
			continue
		# Adds（Tu-160/AH-64/CH-47）按固定航线飞过战场，保留观感
		if ac.has_meta("skip_far_cleanup") and ac.get_meta("skip_far_cleanup"):
			continue

		# 画面外 → 立即静默 free（释放 Token）
		if not mode.is_world_pos_visible(ac.global_position, 0.0):
			ac.set_meta("xp_granted", true)
			ac.queue_free()
			freed += 1
			continue

		# 画面内但距离过远 → 入延迟撤离队列（飘出画面才 free）
		if ac.global_position.distance_squared_to(pp) > near_d2:
			if zone_mission and zone_mission.has_method("_schedule_despawn"):
				ac.set_meta("xp_granted", true)
				zone_mission._schedule_despawn(ac)
				scheduled += 1

	if freed > 0 or scheduled > 0:
		EventLogger.log_event("BOSS", "PhasePurge",
			"offscreen_freed=%d far_deferred=%d" % [freed, scheduled])

## 猎手系统：定期指派空闲敌机主动追击玩家
func _update_hunters(delta: float) -> void:
	_hunter_timer -= delta
	if _hunter_timer > 0.0:
		return
	_hunter_timer = HUNTER_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	if _is_boss_phase():
		return

	# 统计当前正在交战玩家的敌机数量
	var engaging_count := 0
	var idle_enemies: Array[Aircraft] = []
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			# Adds 杂兵和 Boss 不参与猎手系统（Adds 沿航线飞，Boss 有独立战术循环）
			var cat: String = child.get_meta("category", "")
			if cat == "adds" or cat == "boss" or cat == "zone_air":
				continue
			var ai := _get_ai(child)
			if ai:
				if ai._current_target == player_aircraft:
					engaging_count += 1
				elif ai._state == AIController.AIState.PATROL and ai._cooldown_timer <= 0.0:
					idle_enemies.append(child)

	# 确保至少有一定比例的敌机在追击玩家
	# 最少2架，随等级增加
	var desired_hunters := maxi(2, 1 + survivor_player.level / 3)
	var need := desired_hunters - engaging_count

	if need > 0 and not idle_enemies.is_empty():
		# 按距离排序，优先指派近的
		idle_enemies.sort_custom(func(a: Aircraft, b: Aircraft) -> bool:
			return a.global_position.distance_squared_to(player_aircraft.global_position) < \
				   b.global_position.distance_squared_to(player_aircraft.global_position)
		)
		for i in range(mini(need, idle_enemies.size())):
			var enemy := idle_enemies[i]
			var ai := _get_ai(enemy)
			if ai:
				# 强制进入交战状态
				ai._current_target = player_aircraft
				enemy.set_combat_target(player_aircraft)
				ai._state = AIController.AIState.ENGAGE if not ai.simple_ai else AIController.AIState.PATROL
				ai._engage_timer = 0.0
				ai._cooldown_timer = 0.0
				if ai.simple_ai:
					ai._current_target = player_aircraft
				else:
					ai._tactic = AIController.EngageTactic.LEAD_PURSUIT
					ai._tactic_timer = 0.0
					ai._tactic_min_duration = 0.5
					ai._target_eval_timer = 0.0
					enemy.ai_override_pursuit = true

## 定期更新敌机巡逻航点，使其围绕玩家当前位置巡逻
## 边界纪律：防止敌人越界 + 玩家靠近边缘时敌人放弃攻击
## 每帧运行，直接覆写 AI 的 waypoints/state/combat_target。
const BOUNDARY_ENEMY_MARGIN_PX := 2000.0   ## 敌人距边界 ≤4km 强制转向地图中心
const BOUNDARY_DISENGAGE_TARGET_DIST := 4000.0  ## 转向目标点离当前位置的距离
const BOUNDARY_HARD_CLAMP_MARGIN_PX := 40.0     ## 真正越界时 hard clamp 回到边内的安全距

func _update_boundary_discipline(_delta: float) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var pp := player_aircraft.global_position
	# 玩家是否处于警戒区（≤2km 边界距离）→ 触发全局 disengage
	var player_near_edge := MapBoundary.distance_to_edge(pp) <= MapBoundary.WARN_DISTANCE_PX

	for child in mode.get_children():
		if not (child is Aircraft):
			continue
		var ac: Aircraft = child
		if ac.team == 0 or ac.is_destroyed:
			continue
		# Boss / Adds 有独立航点管理，跳过
		var cat: String = ac.get_meta("category", "")
		if cat == "boss" or cat == "adds" or cat == "zone_air":
			continue

		var enemy_edge_dist := MapBoundary.distance_to_edge(ac.global_position)
		var enemy_near_edge := enemy_edge_dist <= BOUNDARY_ENEMY_MARGIN_PX
		var enemy_outside := enemy_edge_dist <= 0.0
		if not enemy_near_edge and not player_near_edge:
			continue

		# 计算向内目标点（朝地图中心）
		var from_pos := ac.global_position
		var inward_dir: Vector2
		var to_center := Vector2.ZERO - from_pos
		if to_center.length_squared() < 1.0:
			inward_dir = Vector2(0, -1)
		else:
			inward_dir = to_center.normalized()
		var inward_pt := from_pos + inward_dir * BOUNDARY_DISENGAGE_TARGET_DIST

		var ai := _get_ai(ac)
		if not ai:
			continue

		# 敌人自身贴边 OR 玩家在警戒区：强制 disengage（清 AI 目标 / 状态 / 机动 flag）
		# 仅覆盖 aircraft.combat_target 是不够的 —— AI 下一 tick 的 set_combat_target 会立刻覆盖回来
		if enemy_near_edge or player_near_edge:
			ac.clear_combat_target()
			ai._current_target = null
			ai._state = AIController.AIState.PATROL
			ai._tactic_timer = 0.0
			ac.ai_override_pursuit = false
			ac.target_position = inward_pt
		# 覆盖 waypoints，让 PATROL 分支朝内飞
		ai.waypoints = PackedVector2Array([inward_pt])

		# 真正越界 → hard clamp 位置 + 航向强制朝内，防止 AI 下一帧还在外面
		if enemy_outside:
			ac.global_position = MapBoundary.clamp_inside(ac.global_position, BOUNDARY_HARD_CLAMP_MARGIN_PX)
			# 航向朝地图中心（heading：0=北，顺时针）
			ac.heading = atan2(inward_dir.x, -inward_dir.y)

func _update_enemy_waypoints(delta: float) -> void:
	_waypoint_update_timer -= delta
	if _waypoint_update_timer > 0.0:
		return
	_waypoint_update_timer = WAYPOINT_UPDATE_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	# BOSS 阶段不再给残余敌机绕玩家航点 —— 让它们按自己航线飘，由 boss 清理 purge 带走
	if _is_boss_phase():
		return

	var pp := player_aircraft.global_position
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			# Adds 杂兵和 Boss 有独立航点管理，不被绕玩家航点覆盖
			var cat2: String = child.get_meta("category", "")
			if cat2 == "adds" or cat2 == "boss" or cat2 == "zone_air":
				continue
			var ai := _get_ai(child)
			if ai and (ai._state == AIController.AIState.PATROL or (ai.simple_ai and ai._current_target == null)):
				# 更新航点围绕玩家当前位置，半径略随机化
				var radius := randf_range(800.0, 1500.0)
				var offset_angle := randf() * TAU
				ai.waypoints = PackedVector2Array([
					pp + Vector2(cos(offset_angle), sin(offset_angle)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.25), sin(offset_angle + TAU * 0.25)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.5), sin(offset_angle + TAU * 0.5)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.75), sin(offset_angle + TAU * 0.75)) * radius,
				])

# ══════════════════════════════════════════════
#  击杀检测 & 经验球
# ══════════════════════════════════════════════

func _detect_kills() -> void:
	for child in mode.get_children():
		# ── 飞机击杀检测 ──
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			if not child.has_meta("xp_granted"):
				child.set_meta("xp_granted", true)
				# 恐惧扩散：友方（玩家或僚机）击杀的任意敌机 → 给同小队成员挂 FEAR
				var pl_ac: Aircraft = survivor_player.aircraft
				if pl_ac and pl_ac.fear_squad_spread_duration > 0.0 \
						and child.get_meta("kill_attacker_team", -1) == 0:
					_trigger_squad_fear(child as Aircraft, pl_ac.fear_squad_spread_duration)
				# UAV/UCAV 给较少经验，MiG 给完整经验
				# Adds（Tu-160/AH-64/CH-47）用 flock 感知公式：整组击杀 ≈ +1 级
				var etype: String = child.get_meta("enemy_type", "mig")
				var xp_value: int
				if etype == "tu160":
					xp_value = SurvivorData.adds_xp_per_kill(survivor_player.level, SurvivorData.TU160_FLOCK_SIZE)
				elif etype == "ah64":
					xp_value = SurvivorData.adds_xp_per_kill(survivor_player.level, SurvivorData.AH64_FLOCK_SIZE)
				elif etype == "ch47":
					xp_value = SurvivorData.adds_xp_per_kill(survivor_player.level, SurvivorData.CH47_FLOCK_SIZE)
				else:
					var base_xp := XP_PER_KILL
					if etype == "uav" or etype == "ucav":
						base_xp = XP_PER_KILL_UAV
					elif etype == "uav_commander":
						base_xp = SurvivorData.XP_PER_KILL_COMMANDER
					elif etype == "f47":
						base_xp = SurvivorData.XP_PER_KILL_F47
					xp_value = base_xp + survivor_player.level * 8
				# xp_mult 升级（累加，硬顶 1.4）
				if survivor_player.aircraft:
					xp_value = int(round(float(xp_value) * survivor_player.aircraft.xp_multiplier))
				survivor_player.add_xp(xp_value)
				kill_count += 1
				_kill_heal()
				_check_head_on_kill_bonus(child)
				## 教程钩子：Tu-160 击落通知（前 3 架击落后首次教程整体淡出）
				if etype == "tu160" and is_instance_valid(mode._tutorial):
					mode._tutorial.notify_bomber_killed()
		# ── 地面单位击杀检测（SAM / AA 炮等）──
		elif child is GroundUnit and child.team != 0 and child.is_destroyed:
			if not child.has_meta("xp_granted"):
				child.set_meta("xp_granted", true)
				var xp_value := SurvivorData.XP_PER_KILL_GROUND + survivor_player.level * 4
				# xp_mult 升级
				if survivor_player.aircraft:
					xp_value = int(round(float(xp_value) * survivor_player.aircraft.xp_multiplier))
				survivor_player.add_xp(xp_value)
				kill_count += 1
				_kill_heal()

## 恐惧扩散：玩家亲自击杀某敌机后，对其同小队幸存成员施加 FEAR
func _trigger_squad_fear(victim: Aircraft, duration: float) -> void:
	var victim_ai := _find_aircraft_ai(victim)
	if victim_ai == null or victim_ai.squad == null:
		return
	for member in victim_ai.squad.members:
		if member == null or member == victim or not is_instance_valid(member) or member.is_destroyed:
			continue
		if not _can_be_feared(member):
			continue
		_apply_player_fear(member, duration, "squad_spread leader=%s" % victim._log_name())

## 通用 helper：施加玩家来源的 FEAR；若玩家持有 fear_chills，同时附带 SLOW
func _apply_player_fear(target: Aircraft, duration: float, log_tag: String) -> void:
	target.apply_status(StatusEffects.FEAR, duration)
	var pl: Aircraft = survivor_player.aircraft
	var slowed := false
	if pl and pl.fear_applies_slow:
		target.apply_status(StatusEffects.SLOW, duration)
		slowed = true
	EventLogger.log_event("FEAR", target._log_name(),
		"%s duration=%.1fs%s" % [log_tag, duration, " +SLOW" if slowed else ""])

## 是否能被恐惧：必须有 AIController + personality + 非 simple_ai + 非完美飞行员（僚机）
func _can_be_feared(target: Aircraft) -> bool:
	var ai := _find_aircraft_ai(target)
	if ai == null or ai.personality == null:
		return false
	if ai.simple_ai:
		return false  # Adds 没有人格状态
	if ai.composure >= 0.99:
		return false  # 玩家僚机免疫
	return true

## 查找 Aircraft 的 AIController 子节点
func _find_aircraft_ai(ac: Aircraft) -> AIController:
	for c in ac.get_children():
		if c is AIController:
			return c
	return null

## 对头击杀奖励：玩家直接击落对头来袭的敌机 → 永久 +5 max_hp
## 判定阈值：双方机头夹角均在 ~53° 内（dot > 0.6）
## 受害者侧的归因 meta 由 aircraft._record_kill_attribution 在致死帧写入。
## 设计预留：后续可放宽到僚机击杀（atk_id 改为 friendly team 全集）以解锁僚机技能。
const HEAD_ON_KILL_HP_BONUS: float = 5.0
const HEAD_ON_DOT_THRESHOLD: float = 0.6
func _check_head_on_kill_bonus(victim: Node) -> void:
	if not victim.has_meta("kill_head_on_dot"):
		return
	var pl_ac: Aircraft = survivor_player.aircraft
	if pl_ac == null or not is_instance_valid(pl_ac) or pl_ac.params == null:
		return
	if victim.get_meta("kill_attacker_id", 0) != pl_ac.get_instance_id():
		return
	var head_on: float = victim.get_meta("kill_head_on_dot", 0.0)
	var atk_aim: float = victim.get_meta("kill_attacker_aim", 0.0)
	if head_on < HEAD_ON_DOT_THRESHOLD or atk_aim < HEAD_ON_DOT_THRESHOLD:
		return
	pl_ac.params.max_hp += HEAD_ON_KILL_HP_BONUS
	pl_ac.hp = minf(pl_ac.hp + HEAD_ON_KILL_HP_BONUS, pl_ac.params.max_hp)
	EventLogger.log_event("HEAD_ON_KILL", pl_ac._log_name(),
		"+%.0f max_hp (now %.0f) head_on=%.2f aim=%.2f" % [
			HEAD_ON_KILL_HP_BONUS, pl_ac.params.max_hp, head_on, atk_aim])

## 击杀回血（_detect_kills 共用）
## 注意：BLOODLUST 状态触发的击杀回血放在 StatusEffects.on_kill，敌我对称生效，不在这里硬编码玩家。
func _kill_heal() -> void:
	if survivor_player.aircraft and survivor_player.aircraft.kill_heal_amount > 0.0:
		var ac := survivor_player.aircraft
		var max_hp_val: float = ac.params.max_hp if ac.params else 100.0
		ac.hp = minf(ac.hp + ac.kill_heal_amount, max_hp_val)
	# 侩子手（战区奖励）：每次击杀后累加连击计数
	if survivor_player.aircraft and survivor_player.aircraft.executioner_active:
		survivor_player.aircraft.bump_executioner_kill()

# ══════════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════════

## 获取飞机的 AI 控制器
func _get_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

func _count_enemies() -> int:
	var count := 0
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			count += 1
	return count

## 敌人武器 V_N 等级注入（仅作用于敌人，玩家不受影响）
##
## 逻辑：
##   1. 计算 tier：tier_override > 0 优先；否则 SurvivorData.get_weapon_tier(etype, level)
##   2. 仅当 enemy_params 已有对应武器槽（非 null）时替换；空槽不注入（保留"该敌人无此武器"语义）
##   3. 替换后的 GunParams 仍是新 .duplicate() 副本，后续 enemy_scale 的 gun_damage_mult 在 V_N 之上叠加
##
## 当前批次：仅机炮。后续批次扩展 missile / rocket / secondary_missile。
func _inject_weapon_tier(p: AircraftParams, etype: int, tier_override: int = -1) -> void:
	var tier: int
	if tier_override > 0:
		tier = clampi(tier_override, 1, 8)
	else:
		var lvl: int = survivor_player.level if survivor_player else 1
		tier = SurvivorData.get_weapon_tier(etype, lvl)
	if p.gun != null:
		p.gun = SurvivorData.ENEMY_GUN_TIERS[tier - 1].duplicate()
	if p.missile != null:
		p.missile = SurvivorData.ENEMY_MISSILE_TIERS[tier - 1].duplicate()
	if p.rocket != null:
		p.rocket = SurvivorData.ENEMY_ROCKET_TIERS[tier - 1].duplicate()
	EventLogger.log_event("WEAPON_TIER", "etype=%d" % etype, "V%d" % tier)

## 清理无效分队（成员被击毁后自动移除）
func _cleanup_squads() -> void:
	var valid_squads: Array[Squad] = []
	for sq in _squads:
		sq.cleanup()
		if sq.members.size() > 0:
			valid_squads.append(sq)
	_squads = valid_squads
