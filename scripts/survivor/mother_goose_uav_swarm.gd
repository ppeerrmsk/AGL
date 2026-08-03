## Mother Goose 无人机蜂群管理
##
## 起始 spawn 12 架围绕 boss 一圈；常态每 20s 补 2 架，指定猎杀 ACTIVE 内再追加两波 6 架，封顶 30。
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
const SPAWN_INTERVAL: float = 20.0
## UAV 初始相对 boss 的环形半径（像素）—— 紧贴机身，看起来像从 boss 上"涌出"
const SPAWN_RADIUS: float = 250.0

## 四种 UAV 型号（display_name → params 资源路径）
enum Variant { MQ_109_GUN, MQ_110_MISSILE, MQ_111_LASER, MQ_112_RAILGUN }
const VARIANT_PARAMS: Dictionary = {
	Variant.MQ_109_GUN:      "res://resources/enemy_uav_mg_gun.tres",
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
	Variant.MQ_112_RAILGUN: 3,
}
## MQ-112 是指定猎杀的远距 telegraph 压力源：蜂群中至少保留 2 架，但绝不超过 3 架。
const RAILGUN_MIN_ALIVE: int = 2

## 角色：HUNTER（追猎玩家） / GUARD（护卫 boss + 自爆拦截）
## 由 variant 决定（spawn 时配置）—— MQ-109 按概率分裂，其它型号固定
enum Role { GUARD, HUNTER }
const VARIANT_ROLES: Dictionary = {
	Variant.MQ_109_GUN:      Role.GUARD,    # 实际由 MQ_109_HUNTER_RATIO 决定，见 _resolve_role
	Variant.MQ_110_MISSILE:  Role.HUNTER,
	Variant.MQ_111_LASER:    Role.GUARD,
	Variant.MQ_112_RAILGUN:  Role.HUNTER,
}
## MQ-109 的 hunter 概率：将主力机炮 UAV 大部分扔去追玩家，少量留在 boss 身边当护驾
## 旧设计 100% guard 导致光环 buff 都被栓在 boss 周围，玩家体感"机炮 UAV 直到 boss 死才变猛"
## 调到 0.5：最终蜂群 ≈ 22.5% MQ-109-guard + 15% MQ-111 = 37.5% guard；62.5% hunter
## （0.7 时 hunter 过多，丢目标后大批漂远不返回，反而让玩家接触的 UAV 数量更少）
const MQ_109_HUNTER_RATIO := 0.5

## Hunter 离 boss 多远开始拽回（像素）—— 超过即在 update 里刷新 waypoints 牵引到 boss
## BFM hunter 没有 squad leader 锚点，_process_patrol 在空 waypoints 时不更新 target_position，
## 丢目标后沿残留方向直线漂走。给一个 boss 牵引点让它们打不到玩家就回 boss 附近重新交战。
## 2026-05-12 抬到 4500：原 2500 会在玩家拉远后立刻中断交战（玩家 3000px 处 = 立即脱锁），
## 配合 SwarmDirector 的 ATTACKER 角色（director 指派下不召回）避免中断式来回拉扯。
## 常态出击只允许短暂越出 1500px 强化圈；越过 1800px 立即放弃目标返巢。
## Designation ACTIVE 会由 MotherGooseController 临时覆写成 DESIG_HUNT_RADIUS，不受此限制。
const HUNTER_LEASH_RADIUS := 1800.0

var _scene_root: Node = null
var _aircraft_scene: PackedScene = null
var _boss_unit: Aircraft = null     ## Mother Goose 主体（提供 spawn anchor）
var _variant_params: Dictionary = {}  ## Variant → AircraftParams (基底，spawn 时 duplicate)
var _boss_squad: Squad = null        ## UAV 加入此 squad → CommanderAura 自动 buff + escort
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null
var _uavs: Array[Aircraft] = []
var _advanced_variants_enabled: bool = true ## 首败后才开放 MQ-111/112；默认 true 保持独立测试兼容
var _spawn_timer: float = 0.0
var _initial_done: bool = false
var _replenishing: bool = false

# ── 指定猎杀增援队列（绕开 SPAWN_INTERVAL，但仍按固定小批次节流）──
var _respawn_pending: int = 0
var _respawn_drain_timer: float = 0.0
const RESPAWN_DRAIN_BATCH: int = 2          ## 每次 drain 最多刷 2 架（与 SPAWN_BATCH 同）
const RESPAWN_DRAIN_INTERVAL: float = 2.0   ## 固定 2s 节拍，玩家可预测且避免单帧整波生成


func setup(scene_root: Node, aircraft_scene: PackedScene, boss_unit: Aircraft,
		boss_squad: Squad, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		allow_advanced_variants: bool = true) -> void:
	_scene_root = scene_root
	_aircraft_scene = aircraft_scene
	_boss_unit = boss_unit
	_boss_squad = boss_squad
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	_advanced_variants_enabled = allow_advanced_variants
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
	# 常态补充从 boss 出现起保持固定 20s 节拍；猎杀相切换不重置该计时器。
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer = 0.0
		var slots: int = MAX_COUNT - _uavs.size()
		if slots > 0:
			var batch: int = mini(SPAWN_BATCH, slots)
			for i in range(batch):
				var angle: float = randf() * TAU
				_spawn_one(angle)

	# 猎杀增援波：固定每 2s 一批，每批最多 2 架。
	if _replenishing and _respawn_pending > 0:
		_respawn_drain_timer += delta
		if _respawn_drain_timer >= RESPAWN_DRAIN_INTERVAL:
			_respawn_drain_timer = 0.0
			var slots: int = MAX_COUNT - _uavs.size()
			var spawn_n: int = mini(mini(RESPAWN_DRAIN_BATCH, _respawn_pending), slots)
			for i in range(spawn_n):
				var angle: float = randf() * TAU
				_spawn_one(angle)
			_respawn_pending -= spawn_n
			# slots 已满（boss UAV cap），队列里剩下的也无地可去 —— 清零避免误堆积
			if slots <= 0:
				_respawn_pending = 0

	# Hunter 不再需要外部 leash —— combat_zone_anchor/_radius 在 AIController 内部处理

## 主体死亡时调；让 UAV 不再补充（残存 UAV 自然战斗）
func stop_replenishing() -> void:
	_initial_done = false   ## 不再 spawn_initial 也不再补给
	_replenishing = false
	_respawn_pending = 0

## 指定猎杀阶段闸门：只控制两波大补队列；常态 20s 补充不受相切换影响。
func set_replenishing(enabled: bool) -> void:
	if _replenishing == enabled:
		return
	_replenishing = enabled
	_respawn_pending = 0
	_respawn_drain_timer = 0.0

## 指定猎杀的显式增援波：只入队，不在一帧内整波实例化。
## 统一走 2 架/批 drain，遵守性能守则的单帧生成预算。
func request_reinforcement_wave(count: int) -> void:
	if not _initial_done or not _replenishing or count <= 0:
		return
	_respawn_pending += count
	# 让下一帧 update() 立即处理首批；后续批次严格每 2s 一次。
	_respawn_drain_timer = RESPAWN_DRAIN_INTERVAL

## 当前存活数量（HUD 用）
func alive_count() -> int:
	return _uavs.size()

## 供 controller 派遣 hunter 用
func get_uavs() -> Array[Aircraft]:
	return _uavs

## 加权抽 variant，过滤已到 alive cap 的型号（如 MQ-111 限量 2）
func _roll_variant() -> int:
	if _advanced_variants_enabled \
			and _alive_count_of_variant(Variant.MQ_112_RAILGUN) < RAILGUN_MIN_ALIVE:
		return Variant.MQ_112_RAILGUN
	var weights: Array = variant_weights_for_progression(1 if _advanced_variants_enabled else 0)
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

## 通关层对应的基础型号权重（纯函数，供无头回归）。0 次仅 109/110；首败后恢复四型号。
static func variant_weights_for_progression(defeat_count: int) -> Array:
	if defeat_count <= 0:
		return [VARIANT_WEIGHTS[0], VARIANT_WEIGHTS[1], 0, 0]
	return VARIANT_WEIGHTS.duplicate()

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
	uav.no_pilot = true          # 无人机：不吃 FEAR、无无线电人声（spec radio-chatter §2.8）
	uav.has_radio_voice = false
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
	## 蜂群会被母舰无限补充 → 击杀不计价：不给 XP / 不入生涯档案 / 不吃对头永久 +max_hp
	## （消费点 survivor_spawner._detect_kills；否则 BOSS 战 = 无限经验农场）
	uav.set_meta("no_kill_reward", true)
	uav.set_meta("skip_far_cleanup", true)
	uav.set_meta("silhouette", "drone")  ## 复用紧凑无人机外观
	## 硬件平台 = 无情绪 = 无恐惧 —— 跳过 [status_effects.gd] FEAR 应用，
	## 防止玩家 skill_gun_kill_fear 一发把整个蜂群打成"平飞傻子"
	uav.set_meta(&"fear_immune", true)
	## 蜂群 saturation 攻击者 —— 跳过 aircraft_weapons.gd 的 TEAM_OVERKILL 检查，
	## 让 30 架 UAV 同时打满火力（玩家方反正会用 flare/机动消解一部分），
	## 否则 6 架 MQ-110 发 180 inbound damage 就把全队后续导弹锁死
	uav.set_meta(&"saturation_attacker", true)
	# 注入管理器：MQ-110 发导弹 / MQ-111 激光扫描玩家导弹 / MQ-109 子弹命中等全靠这俩
	uav.bullet_manager = _bullet_mgr
	uav.missile_manager = _missile_mgr
	_scene_root.add_child(uav)

	# 角色：guard / hunter（MQ-109 按概率分裂，其它固定）
	var role: int
	if variant == Variant.MQ_109_GUN:
		role = Role.HUNTER if randf() < MQ_109_HUNTER_RATIO else Role.GUARD
	else:
		role = int(VARIANT_ROLES.get(variant, Role.GUARD))
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
		# Hunter：simple_ai 持续追击玩家（不绕 boss）。曾用 BFM（simple_ai=false）但实测
		# BFM 战术层在 boss 战乱场里不太爱拉开火条件 → 火力实际投放偏弱；
		# 切回 simple_ai 后 lead 追踪 + 武器系统接管，开火更直接。
		# 站位距离由 preferred_standoff_range_px 控制（MQ-110/MQ-112 站远）。
		var solo_squad := Squad.new()
		solo_squad.leader = uav
		solo_squad.add_member(uav)
		ai.squad = solo_squad
		ai.squad_index = 0
		ai.simple_ai = true
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
		# 战斗偏好区域：以 boss 为中心、HUNTER_LEASH_RADIUS 为半径
		# 出界即放弃当前目标 + 强制回返；目标飘出 × SLACK 也放弃。
		ai.combat_zone_anchor = _boss_unit
		ai.combat_zone_radius = HUNTER_LEASH_RADIUS
		# 攻击跑（spec joust-attack-run，2026-07-05）：电磁炮/导弹 UAV 的
		# "机头稳对玩家累 lock"由 RUN_IN 对准段保证。旧 standoff 切向轨道在
		# 1.5×standoff(6000m) 就甩头，而电磁炮射程只有 5000m —— 开火包络整个躺在
		# 侧身绕圈区里，全场 0 充能（log 183044 死锁实证）。
		# 包络 inner/outer 由 JoustController 动态读装备 live params（雷达/min_engage），
		# run 速=cruise（稳定对准平台）/ break 速=max（脱离快），全部走默认自动值。
		match variant:
			Variant.MQ_110_MISSILE:
				ai.joust_enabled = true
			Variant.MQ_112_RAILGUN:
				ai.joust_enabled = true

	uav.add_child(ai)
	_uavs.append(uav)
