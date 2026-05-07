## Mother Goose 无人机蜂群管理
##
## 起始 spawn 12 架围绕 boss 一圈；之后每 12s 检查 alive_count，<30 则 spawn 2。
## 四种型号 + 两种角色：
##   GUARD（保镖）—— simple_ai + orbit + shield_leader，护卫 boss + 自爆拦截导弹
##     45% MQ-109（机炮 UAV，近战）
##     15% MQ-111（激光 UAV，反导拦截器）
##   HUNTER（追猎）—— 全功能 BFM AI，持续追击玩家（不再绕 boss）
##     25% MQ-110（导弹 UAV，远距奔袭打击）
##     15% MQ-112（电磁炮 UAV，远距 telegraph 狙击）
##
## 角色由型号决定（spawn 时一次性配置），不再有周期性 dispatch；蜂群始终维持 ~40%
## hunter 持续给玩家压力，~60% guard 守 boss 自爆拦截。
## 每架 UAV 都加入 boss_squad → CommanderAura 给所有成员施加 buff（不分角色）

class_name MotherGooseUAVSwarm
extends RefCounted

const INITIAL_COUNT: int = 12
const MAX_COUNT: int = 30
const SPAWN_BATCH: int = 2
const SPAWN_INTERVAL: float = 12.0
## UAV 初始相对 boss 的环形半径（像素）—— 紧贴机身，看起来像从 boss 上"涌出"
const SPAWN_RADIUS: float = 250.0

## 四种 UAV 型号（display_name → params 资源路径）
enum Variant { MQ_109_GUN, MQ_110_MISSILE, MQ_111_LASER, MQ_112_RAILGUN }
const VARIANT_PARAMS: Dictionary = {
	Variant.MQ_109_GUN:      "res://resources/enemy_uav.tres",
	Variant.MQ_110_MISSILE:  "res://resources/enemy_uav_missile.tres",
	## MQ-111 用专属双用途激光（intercepts missiles + can_target_aircraft=true）
	## 而非 enemy_uav_laser（仅反导，Sentinel 共用）
	Variant.MQ_111_LASER:    "res://resources/enemy_uav_mg_laser.tres",
	Variant.MQ_112_RAILGUN:  "res://resources/enemy_uav_railgun.tres",
}
const VARIANT_DESIGNATION: Dictionary = {
	Variant.MQ_109_GUN:      "MQ-109",
	Variant.MQ_110_MISSILE:  "MQ-110",
	Variant.MQ_111_LASER:    "MQ-111",
	Variant.MQ_112_RAILGUN:  "MQ-112",
}
## 抽签权重（合 100）：MQ-109 主力 + 三种高级版各占少量
const VARIANT_WEIGHTS: Array = [45, 25, 15, 15]

## 单型号 alive 上限（变体 → 最大同时存在数）。未列入则不限。
## MQ-111 激光太强需限量，避免一群激光把玩家锁死
const VARIANT_ALIVE_CAP: Dictionary = {
	Variant.MQ_111_LASER: 2,
}

## 角色：HUNTER（追猎玩家） / GUARD（护卫 boss + 自爆拦截）
## 由 variant 决定，spawn 时一次性配置，不再周期切换
enum Role { GUARD, HUNTER }
const VARIANT_ROLES: Dictionary = {
	Variant.MQ_109_GUN:      Role.GUARD,
	Variant.MQ_110_MISSILE:  Role.HUNTER,
	Variant.MQ_111_LASER:    Role.GUARD,
	Variant.MQ_112_RAILGUN:  Role.HUNTER,
}

var _scene_root: Node = null
var _aircraft_scene: PackedScene = null
var _boss_unit: Aircraft = null     ## Mother Goose 主体（提供 spawn anchor）
var _variant_params: Dictionary = {}  ## Variant → AircraftParams (基底，spawn 时 duplicate)
var _boss_squad: Squad = null        ## UAV 加入此 squad → CommanderAura 自动 buff + escort
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null
var _uavs: Array[Aircraft] = []
var _spawn_timer: float = 0.0
var _initial_done: bool = false


func setup(scene_root: Node, aircraft_scene: PackedScene, boss_unit: Aircraft,
		boss_squad: Squad, bullet_mgr: BulletManager, missile_mgr: MissileManager) -> void:
	_scene_root = scene_root
	_aircraft_scene = aircraft_scene
	_boss_unit = boss_unit
	_boss_squad = boss_squad
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	# 预加载三种 UAV 资源（spawn 热路径上 duplicate 即可）
	for variant in VARIANT_PARAMS:
		var p: Resource = load(VARIANT_PARAMS[variant])
		if p != null:
			_variant_params[variant] = p
		else:
			push_warning("MotherGooseUAVSwarm: failed to load %s" % VARIANT_PARAMS[variant])

## 立即 spawn 起始 12 架
func spawn_initial() -> void:
	if _initial_done:
		return
	_initial_done = true
	for i in range(INITIAL_COUNT):
		var angle: float = TAU * float(i) / float(INITIAL_COUNT)
		_spawn_one(angle)

func update(delta: float) -> void:
	if not _initial_done:
		return
	# 清理已死的引用
	var alive: Array[Aircraft] = []
	for u in _uavs:
		if is_instance_valid(u) and not u.is_destroyed:
			alive.append(u)
	_uavs = alive

	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer = 0.0
		var slots: int = MAX_COUNT - _uavs.size()
		if slots > 0:
			var batch: int = mini(SPAWN_BATCH, slots)
			for i in range(batch):
				var angle: float = randf() * TAU
				_spawn_one(angle)

## 主体死亡时调；让 UAV 不再补充（残存 UAV 自然战斗）
func stop_replenishing() -> void:
	_initial_done = false   ## 不再 spawn_initial 也不再补给

## 当前存活数量（HUD 用）
func alive_count() -> int:
	return _uavs.size()

## 供 controller 派遣 hunter 用
func get_uavs() -> Array[Aircraft]:
	return _uavs

## 加权抽 variant，过滤已到 alive cap 的型号（如 MQ-111 限量 2）
func _roll_variant() -> int:
	var weights: Array = VARIANT_WEIGHTS.duplicate()
	for v in VARIANT_ALIVE_CAP:
		var cap: int = int(VARIANT_ALIVE_CAP[v])
		if _alive_count_of_variant(int(v)) >= cap:
			weights[int(v)] = 0
	var total: int = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return Variant.MQ_109_GUN   ## 极端兜底：所有 cap 都满 → 默认机炮
	var r: int = randi() % total
	var acc: int = 0
	for i in range(weights.size()):
		acc += int(weights[i])
		if r < acc:
			return i
	return Variant.MQ_109_GUN

## 当前存活的某 variant UAV 数量
func _alive_count_of_variant(variant: int) -> int:
	var name: String = String(VARIANT_DESIGNATION.get(variant, ""))
	if name == "":
		return 0
	var n: int = 0
	for u in _uavs:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if u.params and u.params.display_name == name:
			n += 1
	return n

func _spawn_one(angle_offset: float) -> void:
	if _scene_root == null or _aircraft_scene == null or _boss_unit == null:
		return
	if not is_instance_valid(_boss_unit) or _boss_unit.is_destroyed:
		return

	var variant: int = _roll_variant()
	var base_params: AircraftParams = _variant_params.get(variant, null)
	if base_params == null:
		# 兜底回退到 MQ-109
		base_params = _variant_params.get(Variant.MQ_109_GUN, null)
		if base_params == null:
			return
		variant = Variant.MQ_109_GUN
	var designation: String = String(VARIANT_DESIGNATION[variant])

	var boss_pos: Vector2 = _boss_unit.global_position
	var spawn_offset := Vector2(sin(angle_offset), -cos(angle_offset)) * SPAWN_RADIUS
	var spawn_pos: Vector2 = boss_pos + spawn_offset
	if not MapBoundary.is_safe_inside(spawn_pos, 800.0):
		spawn_pos = boss_pos + spawn_offset * 0.4

	var uav: Aircraft = _aircraft_scene.instantiate()
	var params_dup: AircraftParams = base_params.duplicate(true)
	# 嵌套资源也得拷贝（与 _create_enemy 同处理）
	if params_dup.gun:
		params_dup.gun = params_dup.gun.duplicate()
	if params_dup.missile:
		params_dup.missile = params_dup.missile.duplicate()
	if params_dup.secondary_missile:
		params_dup.secondary_missile = params_dup.secondary_missile.duplicate()
	if params_dup.combat:
		params_dup.combat = params_dup.combat.duplicate()
	if params_dup.flare:
		params_dup.flare = params_dup.flare.duplicate()
	# 三型号统一渲染机型代号 —— HUD/EventLogger 显示 "MQ-109/110/111"
	params_dup.display_name = designation
	uav.params = params_dup
	uav.team = 1
	# 呼号即型号名（占位让 Aircraft._ready 不再走 CallsignDB.allocate 抢通用 ID）
	uav.callsign = designation
	uav.position = spawn_pos
	uav.initial_heading_deg = rad_to_deg(angle_offset)
	uav.altitude = _boss_unit.altitude
	uav.flat_altitude = true
	uav.set_target_tier(CombatUnit.AltitudeTier.MID)
	uav.infinite_fuel = true
	uav.infinite_ammo = true
	uav.set_meta("enemy_type", "uav")
	uav.set_meta("category", "boss_mother_goose_uav")
	uav.set_meta("skip_far_cleanup", true)
	uav.set_meta("silhouette", "drone")  ## 复用紧凑无人机外观
	## 硬件平台 = 无情绪 = 无恐惧 —— 跳过 [status_effects.gd] FEAR 应用，
	## 防止玩家 skill_gun_kill_fear 一发把整个蜂群打成"平飞傻子"
	uav.set_meta(&"fear_immune", true)
	# 注入管理器：MQ-110 发导弹 / MQ-111 激光扫描玩家导弹 / MQ-109 子弹命中等全靠这俩
	uav.bullet_manager = _bullet_mgr
	uav.missile_manager = _missile_mgr
	_scene_root.add_child(uav)

	# 角色：guard / hunter（基于 variant，spawn 时一次性配置）
	var role: int = int(VARIANT_ROLES.get(variant, Role.GUARD))
	uav.set_meta("mg_role", role)

	var ai := AIController.new()
	ai.name = "AI_MGUav"
	ai.aircraft = uav
	ai.patrol_altitude = _boss_unit.altitude
	ai.enable_combat = true

	# CommanderAura 在 boss 端扫 boss_squad.members 给 buff —— 把 UAV 加进 list 即可。
	# Squad.members 只是 Array，多 squad 共享同一架飞机不冲突
	if _boss_squad:
		_boss_squad.add_member(uav)

	if role == Role.GUARD:
		# Guard：simple_ai + orbit + shield_leader（自爆拦导弹 + 进圈反击）
		# ai.squad = boss_squad 让 EscortBehavior 知道 leader 是谁，绕 boss 飞
		ai.squad = _boss_squad
		ai.squad_index = _boss_squad.members.size() - 1
		ai.simple_ai = true
		ai.orbit_squad_leader = true
		ai.shield_leader = true
		ai.evade_missiles = false           ## 不规避，反而冲向导弹自爆
		ai.engage_cooldown = 1.5
		ai.engage_duration = 30.0
		ai.aggression = randf_range(0.7, 0.95)
		ai.skill_level = randf_range(0.5, 0.75)
		ai.composure = randf_range(0.4, 0.7)
		ai.focus = randf_range(0.6, 0.85)
		ai.self_preservation = randf_range(0.05, 0.2)
		# MQ-111（激光）：限量 2 + 永不出列自爆 → 始终绕 boss 提供反导/反机覆盖
		if variant == Variant.MQ_111_LASER:
			uav.set_meta(&"no_kamikaze", true)
	else:
		# Hunter：全功能 BFM AI 持续追击玩家，不绕 boss
		# ⚠ 关键：ai.squad **不能**指向 boss_squad —— 否则 [ai_controller.gd:570] 的
		# 自动 SQUAD_FOLLOW 守卫会把它转成"跟随长机"模式（PATROL → SQUAD_FOLLOW），
		# 这就是日志里 MQ-110/MQ-112 平飞不打人的根因。
		# 给一个独立单人 squad（leader=自己），守卫条件 squad.leader != aircraft 不成立 → 跳过
		var solo_squad := Squad.new()
		solo_squad.leader = uav
		solo_squad.add_member(uav)
		ai.squad = solo_squad
		ai.squad_index = 0
		ai.simple_ai = false
		ai.orbit_squad_leader = false
		ai.shield_leader = false
		ai.evade_missiles = true             ## hunter 要活久才能持续给玩家压力
		ai.engage_cooldown = 0.5
		ai.engage_duration = 60.0
		ai.aggression = 0.95
		ai.skill_level = randf_range(0.55, 0.80)
		ai.composure = randf_range(0.5, 0.75)
		ai.focus = randf_range(0.7, 0.9)
		ai.self_preservation = 0.15

	uav.add_child(ai)
	_uavs.append(uav)
