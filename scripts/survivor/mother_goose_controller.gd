## Mother Goose 战斗逻辑控制器
##
## 挂在 Mother Goose 主体（Aircraft 实例）下作为子节点。
## 每帧：
##   1. 推进 jam_shield 状态机
##   2. 推进 uav_swarm（补给计时）
##   3. 给场内玩家方 Aircraft 施加 jam 效果（status_jam_active + speed_mult meta）
##   4. 绘制 jam_shield 视觉圈（继承父节点 transform，圆形旋转无差别）
##
## 父节点（boss aircraft）销毁时本节点会随之 queue_free。
## 父节点 is_destroyed=true 时停止补给 UAV（残存 UAV 自然战斗，胜利判定不卡）。

class_name MotherGooseController
extends Node2D

## 干扰场每帧给场内玩家方单位续期的状态时长（秒）。略大于 1 帧 (1/60≈0.017s) +
## 一个余量，离开场后 0.5s 自然衰减消失（HUD 状态栏滑落动画看得见）
const JAM_REFRESH_DURATION: float = 0.5

var boss_unit: Aircraft = null
var boss_encounter: MotherGooseBoss = null    ## 反向引用，路由伤害到 mounts/weak_point
var player_ref: Aircraft = null               ## VLS 齐射目标
var missile_manager_ref: MissileManager = null
var jam_shield: MotherGooseJamShield = null
var uav_swarm: MotherGooseUAVSwarm = null
var designation: MotherGooseDesignation = null
## SwarmDirector：1Hz 战略层，把 30 架 UAV 分配到 4 轴楔形 + SHOOTER + DECOY 实现协同突击
## 参数走 res://resources/ace_swarm_director.tres（策划可在 Inspector 调）
var swarm_director: SwarmDirector = null
const SWARM_DIRECTOR_PARAMS_PATH: String = "res://resources/ace_swarm_director.tres"

# ── DESIGNATION（指定猎杀）阶段相关 ──
## ACTIVE 期间存放被改过 AI 的 UAV 原始字段，结束时回滚
## key = AIController（WeakRef 不必要，遍历时 is_instance_valid 守卫即可）
## value = Dictionary { orbit_squad_leader, shield_leader, combat_zone_radius, combat_zone_anchor,
##                       aggression, self_preservation, simple_ai }
var _designation_overrides: Dictionary = {}
## ACTIVE 期间被指派为"前置伏击"角色的 AIController 集合（key = AIController, value = true）
## 这些 UAV 在 _designation_tick 里不被全局 force-target 覆盖：它们应当先飞到伏击点，
## 抵达后自己用雷达重新捕获玩家进入 lead-chase（natural transition）
var _designation_interceptors: Dictionary = {}
## 包围期 hunter leash 半径：设极大值让 `_is_hunter` 在 ai_controller 内被判 true
## （检测条件 combat_zone_anchor != null AND combat_zone_radius > 0），
## 从而让 UAV 在 simple_combat 里走 HUNTER_UAV_SPEED_RATIO 全速分支，
## 同时不会被 leash"出界回返"触发（半径远超地图）。
const DESIG_HUNT_RADIUS: float = 99999.0
## 前置伏击点距玩家像素 —— 30% UAV 当前位于玩家前半球（dot(forward, to_uav) > 0）
## 时把它们派去玩家前方 INTERCEPT_DIST 远处当伏兵，制造"从前方接近"的战术分层。
## 其余 UAV 走纯 lead-chase，无 target_position 干预 —— 处于玩家身后的自然从后半球扑上来，
## 处于侧面的从侧面接近，形成多角度包围。
const DESIG_INTERCEPT_DIST: float = 2400.0
const DESIG_INTERCEPT_RATIO: float = 0.30
## ACTIVE 内两波 UAV 增援：开场一波、过半一波；每波交给 swarm 按 2 架/批节流生成。
const DESIG_UAV_WAVE_SIZE: int = 6
const DESIG_UAV_WAVE_TWO_TIME: float = 7.5
var _designation_wave_two_sent: bool = false

# ── 角度免伤参数 ──
## 与机头夹角越大（越接近从尾部打来）伤害越高：
##   ang ∈ [0, 60°]   front cone：0 伤害（"angle blocked"）
##   ang ∈ (60, 120°] side：30% 伤害
##   ang ∈ (120, 180°] rear：100% 伤害
const FRONT_CONE_DEG: float = 60.0
const SIDE_CONE_DEG: float = 120.0
const SIDE_DAMAGE_MULT: float = 0.3

# ── VLS 齐射 ──
## 每 SALVO_INTERVAL 秒触发一轮齐射：每个未损毁的 VLS 挂点连发 SALVO_PER_VLS 枚
## 单个挂点的弹间隔 INTRA_SALVO_DELAY（视觉上 "pop pop pop pop" 而非瞬间齐喷）
const SALVO_INTERVAL: float = 20.0
const SALVO_PER_VLS: int = 4
const INTRA_SALVO_DELAY: float = 0.25
## 母舰专属 VLS 弹（数值 = cg_vls_missile 克隆，只改 display_name）。
## 别再借用巡洋舰那份：导弹 HUD 标签会写成 "CG-VLS"，玩家看到一串"巡洋舰"跟着无人机
## 飞过陆地，会读成"有船开到岸上"（2026-07-28 playtest 报告）
const VLS_MISSILE_PATH: String = "res://resources/goose_vls_missile.tres"
var _salvo_timer: float = 0.0
## 进行中的齐射队列：每个元素 [mount_world_pos, missile_count_left, delay_left]
## 用 Array 而非每个 mount 一个独立计时器，简单且 O(N) 处理
var _salvo_queue: Array = []
var _vls_missile_params: MissileParams = null

# UAV 角色（hunter / guard）由 [mother_goose_uav_swarm.gd:VARIANT_ROLES] 在 spawn 时
# 一次性配置；不再需要周期性 dispatch 系统

# ── 流浪 UAV 召回 ──
## 周期扫描蜂群：脱离 boss 太远且无交战目标的 UAV → 强制返航
## 解决"玩家飞远后 hunter 失去目标在原地打转 / guard 被击退后回不来"的浪费问题
const RECALL_INTERVAL: float = 4.0
## 2026-05-12 抬到 5000（原 3500）：配合 HUNTER_LEASH_RADIUS=4500，
## 让 ATTACKER 角色被 SwarmDirector 拉到 lane 攻击点时不被 stray recall 中断。
## SwarmDirector 指派为 ATTACKER 的 UAV 在 _update_stray_recall 里 explicit skip。
const RECALL_LEASH_PX: float = 5000.0     ## 离 boss 超过此距离 + 无目标 → 召回
var _recall_timer: float = 0.0

## 上一帧被打过 jam 标记的玩家方单位（用于本帧没在场内时主动清理）
func _ready() -> void:
	if jam_shield == null:
		jam_shield = MotherGooseJamShield.new()
		jam_shield.start()
	if designation == null:
		designation = MotherGooseDesignation.new()
		designation.start()
	# SwarmDirector：等 setup_uav_swarm 注入 uav_swarm 后由调用方触发 init_swarm_director()
	# 这里只构造一个空实例占位；params 在 init_swarm_director 中加载
	# 预加载 VLS 导弹参数（齐射热路径不再做 IO）
	var p: Resource = load(VLS_MISSILE_PATH)
	if p is MissileParams:
		_vls_missile_params = p as MissileParams
	# 起始计时偏移：第一轮齐射在 SALVO_INTERVAL 后触发，给玩家适应时间
	_salvo_timer = 0.0


func _process(delta: float) -> void:
	if boss_unit == null or not is_instance_valid(boss_unit):
		queue_free()
		return

	var boss_dead: bool = boss_unit.is_destroyed

	# UAV swarm tick（boss 死后停止补给）
	if uav_swarm:
		if boss_dead:
			uav_swarm.stop_replenishing()
		uav_swarm.update(delta)
		# SwarmDirector lazy 初始化：boss 还活且 uav_swarm 已就位（首批 UAV spawn 后）
		if not boss_dead and swarm_director == null:
			_init_swarm_director()
		# 战略 tick：内部按 director_hz 累加器节流，每帧调一次但 ~1Hz 才真正算
		if swarm_director != null and not boss_dead:
			swarm_director.update(delta)

	# Jam shield 状态机（boss 死后立刻停止）
	if not boss_dead and jam_shield:
		jam_shield.update(delta)
		_apply_jam_field(delta)
	else:
		_clear_jam_field()

	# VLS 齐射调度（boss 死后停止）
	if not boss_dead:
		_update_vls_salvo(delta)
		# 流浪 UAV 召回（boss 死后不再召回 —— 残存 UAV 自然战斗到死）
		_update_stray_recall(delta)
		# DESIGNATION 阶段调度（boss 死后停止，残存 UAV 维持上次设置自然战斗）
		_update_designation(delta)

	# Shield 绘制由独立的 MotherGooseShieldOverlay 接管（脱离 boss transform，
	# 即便 boss 屏外也保证 AOE 圈可见 —— 玩家 gameplay 必须知道范围在哪）


## 给场内玩家方单位施加 jam + slow 状态 + AOE 滴血
## 走标准 status_effects 系统 → 自动写 status_jam_active / status_slow_active 派生标记，
## 同时玩家 HUD 状态栏会渲染 JAM 绿条 + SLOW 蓝条，玩家明确知道在被干扰减速
##   - JAM  → status_jam_active=true → 武器锁定/发射全断（aircraft_weapons 已有路径）
##   - SLOW → 顶速硬 cap 到 SLOW_SPEED_CAP_KMH=350 km/h，禁加力
##   - AOE  → JAM_FIELD_DPS=5/s 持续掉血，kind="jam_field"
## 离开场内时不主动清，让 0.5s 自然衰减（_last_jammed 跟踪不再需要）
const JAM_FIELD_DPS: float = 5.0   ## 场内每秒掉血（与 SLOW + JAM 叠加压迫）
func _apply_jam_field(delta: float) -> void:
	if jam_shield == null or not jam_shield.is_effect_active():
		return
	if boss_unit == null or not is_instance_valid(boss_unit):
		return
	var bp: Vector2 = boss_unit.global_position
	var dmg: float = JAM_FIELD_DPS * delta
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not u is Aircraft:
			continue
		if not u.is_player_squad():           ## 只影响玩家小队，UAV/boss/ALLY 不受波及
			continue
		var ac: Aircraft = u
		if ac.global_position.distance_to(bp) <= jam_shield.current_radius:
			# 续期：每帧把状态时长刷到 JAM_REFRESH_DURATION
			ac.apply_status(StatusEffects.JAM, JAM_REFRESH_DURATION)
			ac.apply_status(StatusEffects.SLOW, JAM_REFRESH_DURATION)
			# AOE 滴血（按 delta 精确累计，hp 是 float，无需 1.0 阈值）
			ac.take_damage(dmg, CombatUnit.safe_attacker(boss_unit), "jam_field")


## boss 死亡时调；状态栏的 JAM/SLOW 会自动衰减消失，无需主动清理
func _clear_jam_field() -> void:
	pass


## 玩家机换人时重定向（BossEncounter.set_player_ref 契约的下游一环）。
## 本控制器自己持一份 player_ref（VLS 齐射目标 / 指定猎杀几何），
## 且把它传给了 SwarmDirector —— 两处都要改，漏一个就是一个野指针。
func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	player_ref = p
	if swarm_director != null:
		swarm_director.set_player_ref(p)

## 构造 SwarmDirector + 加载 params .tres
func _init_swarm_director() -> void:
	if uav_swarm == null or player_ref == null or not is_instance_valid(player_ref):
		return
	if boss_unit == null or not is_instance_valid(boss_unit):
		return
	var params: SwarmDirectorParams = load(SWARM_DIRECTOR_PARAMS_PATH) as SwarmDirectorParams
	if params == null:
		push_warning("MotherGooseController: failed to load %s — using defaults" % SWARM_DIRECTOR_PARAMS_PATH)
		params = SwarmDirectorParams.new()
	swarm_director = SwarmDirector.new()
	swarm_director.setup(boss_unit, player_ref, uav_swarm, designation, params)
	EventLogger.log_event("BOSS", "MOTHER GOOSE",
		"SwarmDirector online (atk=%.0f%% / decoy=%.0f%% / guard=%.0f%%)" %
		[params.attacker_pct * 100.0, params.decoy_pct * 100.0, params.guard_pct * 100.0])


# ════════════════════════════════════════════════════════════
# 伤害路由（被 Aircraft.take_damage_at 通过 damage_router meta 调用）
# 入参：amount = 来袭伤害；hit_pos = 命中世界坐标
# 流程：
#   1. 弱点已暴露 → 弱点判定（在半径内）→ apply_damage 到 weak_point
#   2. 否则找最近存活挂点（300px 内）→ 角度过滤 → 应用伤害
#   3. 若所有挂点死光 → 通知 boss 暴露弱点
#   4. 都失败 → 跌落到 boss 自身 take_damage（防止 0 伤害黑洞）
# ════════════════════════════════════════════════════════════
func route_damage(amount: float, hit_pos: Vector2) -> void:
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		return
	if boss_encounter == null:
		boss_unit.take_damage(amount)
		return

	# 1. 弱点（已暴露）——直接判半径内击杀
	var wp: WeakPoint = boss_encounter.weak_point
	if wp != null and wp.revealed:
		var bp: Vector2 = boss_unit.global_position
		if hit_pos.distance_to(bp) <= wp.radius:
			wp.apply_damage(amount)
			return
		# 弱点暴露但命中不在半径内 → 忽略（玩家应瞄准中心）
		return

	# 2. 最近存活挂点
	var nearest: WeaponMount = null
	var nearest_d: float = 400.0   ## 命中容差像素半径
	for m in boss_encounter.mounts:
		if m == null or m.destroyed:
			continue
		var mw: Vector2 = m.world_position(boss_unit.global_position, boss_unit.heading)
		var d: float = hit_pos.distance_to(mw)
		if d < nearest_d:
			nearest_d = d
			nearest = m

	if nearest == null:
		# 命中位置离任何挂点都远 —— 当作 hit boss 主体（不计伤害以维持挂点必须先毁的设计）
		return

	# 3. 角度过滤（attacker direction 相对 boss heading）
	var dmg_mult: float = _compute_angle_damage_mult(hit_pos)
	if dmg_mult <= 0.0:
		# 前向命中：不计伤害；玩家可由 EventLogger 看到提示
		return
	var final_dmg: float = amount * dmg_mult
	if nearest.apply_damage(final_dmg):
		_on_mount_destroyed(nearest)

func _compute_angle_damage_mult(hit_pos: Vector2) -> float:
	if boss_unit == null:
		return 1.0
	# boss 朝向单位向量（heading 0=北=-Y）
	var fwd := Vector2(sin(boss_unit.heading), -cos(boss_unit.heading))
	var to_hit := (hit_pos - boss_unit.global_position).normalized()
	if to_hit.length_squared() < 0.001:
		return 0.0
	# 夹角 = acos(dot)，0=正前方, π=正后方
	var cos_a: float = clampf(fwd.dot(to_hit), -1.0, 1.0)
	var ang_deg: float = rad_to_deg(acos(cos_a))
	if ang_deg <= FRONT_CONE_DEG:
		return 0.0
	if ang_deg <= SIDE_CONE_DEG:
		return SIDE_DAMAGE_MULT
	return 1.0   ## 尾扇区全额伤害

func _on_mount_destroyed(_m: WeaponMount) -> void:
	if boss_encounter and boss_encounter.all_mounts_destroyed():
		boss_encounter.reveal_weak_point()


# ════════════════════════════════════════════════════════════
# VLS 齐射
# 每 SALVO_INTERVAL 秒触发一轮：未损毁 VLS 挂点各排队 SALVO_PER_VLS 枚
# 排队帧逐个发射（INTRA_SALVO_DELAY 间隔），瞄向当前玩家
# VLS 挂点损毁 → 该挂点不再加入队列（玩家奖励）
# ════════════════════════════════════════════════════════════
func _update_vls_salvo(delta: float) -> void:
	if _vls_missile_params == null or missile_manager_ref == null:
		return
	if not is_instance_valid(missile_manager_ref):
		return
	# 周期触发：补给齐射队列
	_salvo_timer += delta
	if _salvo_timer >= SALVO_INTERVAL:
		_salvo_timer = 0.0
		_enqueue_vls_salvo()
	# 推进队列里每条记录的延迟
	var i: int = 0
	while i < _salvo_queue.size():
		var entry: Array = _salvo_queue[i]
		entry[2] = float(entry[2]) - delta
		if float(entry[2]) <= 0.0:
			_fire_one_vls_missile(entry[0])
			entry[1] = int(entry[1]) - 1
			if int(entry[1]) <= 0:
				_salvo_queue.remove_at(i)
				continue
			else:
				entry[2] = INTRA_SALVO_DELAY
		i += 1

## 把每个未损毁 VLS 挂点的 SALVO_PER_VLS 枚导弹排进队列
func _enqueue_vls_salvo() -> void:
	if boss_encounter == null or boss_unit == null:
		return
	if player_ref == null or not is_instance_valid(player_ref) or player_ref.is_destroyed:
		return
	var target_distance_px: float = boss_unit.global_position.distance_to(player_ref.global_position)
	if not vls_can_launch_at_distance(target_distance_px, _vls_missile_params):
		EventLogger.log_event("BOSS", "MOTHER GOOSE",
			"VLS salvo held: player inside %.0fm close zone" \
			% _vls_missile_params.distance_airburst_min_launch_range_m)
		return
	var vls_mounts: Array[WeaponMount] = boss_encounter.alive_vls_mounts()
	if vls_mounts.is_empty():
		return
	var bp: Vector2 = boss_unit.global_position
	var bh: float = boss_unit.heading
	for m in vls_mounts:
		var mw: Vector2 = m.world_position(bp, bh)
		_salvo_queue.append([mw, SALVO_PER_VLS, 0.0])
	EventLogger.log_event("BOSS", "MOTHER GOOSE",
		"VLS salvo: %d mounts × %d missiles" % [vls_mounts.size(), SALVO_PER_VLS])


## Mother Goose 的 VLS 是远距定距空爆武器；近身时整轮停火，给绕后拆挂点留下明确安全区。
static func vls_can_launch_at_distance(distance_px: float, params: MissileParams) -> bool:
	if params == null or params.distance_airburst_min_launch_range_m <= 0.0:
		return true
	return distance_px >= params.distance_airburst_min_launch_range_m \
		* GameConstants.PIXELS_PER_METER

## 单弹发射 —— 用 boss_unit 当 source（含 team / position 偏到 mount 世界坐标后再修正）
## MissileManager.spawn_missile 对 is_vls_salvo 自带 ±25° 散布，无需手动 jitter
func _fire_one_vls_missile(mount_world_pos: Vector2) -> void:
	if missile_manager_ref == null or not is_instance_valid(missile_manager_ref):
		return
	if player_ref == null or not is_instance_valid(player_ref) or player_ref.is_destroyed:
		return
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		return
	var msl: Missile = missile_manager_ref.spawn_missile(boss_unit, player_ref, _vls_missile_params)
	if msl != null:
		# 修正起点到 VLS 挂点世界坐标（spawn_missile 默认 source.global_position + 15px fwd）
		msl.global_position = mount_world_pos


# ════════════════════════════════════════════════════════════
# 流浪 UAV 召回
# 每 RECALL_INTERVAL 秒扫一次蜂群：离 boss > RECALL_LEASH_PX 且没有有效交战目标
# 的 UAV → 强制返航（设 target_position = boss + ai 清残留 + 重置 waypoints 围着 boss）
# 解决：
#   - hunter 失去目标后在远端默认航点圈打转（_generate_default_waypoints 用当前位置）
#   - guard 被击退到边缘后回不来
# 不召回正在交战的 UAV（_current_target 有效 → 视作正常追击）
# ════════════════════════════════════════════════════════════
func _update_stray_recall(delta: float) -> void:
	if uav_swarm == null or boss_unit == null or not is_instance_valid(boss_unit):
		return
	_recall_timer += delta
	if _recall_timer < RECALL_INTERVAL:
		return
	_recall_timer = 0.0

	var bp: Vector2 = boss_unit.global_position
	var leash_sq: float = RECALL_LEASH_PX * RECALL_LEASH_PX
	var recalled: int = 0
	for uav in uav_swarm.get_uavs():
		if uav == null or not is_instance_valid(uav) or uav.is_destroyed:
			continue
		if uav.global_position.distance_squared_to(bp) < leash_sq:
			continue
		var ai: AIController = _find_uav_ai(uav)
		if ai == null:
			continue
		# 正在交战合法目标 → 视作正常追击，不召回
		if ai._current_target != null and is_instance_valid(ai._current_target) \
				and not ai._current_target.is_destroyed:
			continue
		# SwarmDirector 主动派遣的 ATTACKER 角色 → 跳过召回（director 控制其攻击点）
		# 否则会出现"director 把 UAV 拉到楔形攻击点 → 距 boss > leash → 立刻被召回 → 圈空一圈"的撕扯
		if SwarmDirector.is_active_attacker(ai.swarm_role_override):
			continue
		# 强制返航：清残留追击 + 朝"恢复锚点"飞。
		# 玩家比 boss 近时锚点拉到玩家附近（避免 boss 飞远整个蜂群被拽出画面）；
		# 否则锚点是 boss（原行为）。
		var anchor: Vector2 = bp
		if player_ref != null and is_instance_valid(player_ref) and not player_ref.is_destroyed:
			var pp: Vector2 = player_ref.global_position
			if uav.global_position.distance_squared_to(pp) < uav.global_position.distance_squared_to(bp):
				anchor = pp
		if ai.release_target(AIController.TargetSource.TS_BOSS, "stray UAV recall"):
			uav.ai_override_pursuit = false
			uav.target_position = anchor
			# 围锚点的 4 点航点
			var ring_r: float = 600.0
			ai.waypoints = PackedVector2Array([
				anchor + Vector2(ring_r, 0),
				anchor + Vector2(0, ring_r),
				anchor + Vector2(-ring_r, 0),
				anchor + Vector2(0, -ring_r),
			])
			ai.current_waypoint_index = 0
			recalled += 1
	if recalled > 0:
		EventLogger.log_event("BOSS", "MOTHER GOOSE",
			"recalled %d stray UAVs to boss" % recalled)


func _find_uav_ai(uav: Aircraft) -> AIController:
	for child in uav.get_children():
		if child is AIController:
			return child
	return null


# ════════════════════════════════════════════════════════════
# DESIGNATION（指定猎杀）阶段
# 节奏：COOLDOWN 180s → WARNING 3s（tether 红线伸出预警）→ ACTIVE 15s →
#       回 COOLDOWN
# ACTIVE 期间：
#   - 全场 team=1 飞机的 AI._current_target 强制锁定玩家（含远端散兵）
#   - UAV 蜂群临时切 hunter 模式（guard 解除 orbit/shield、combat_zone leash 解除）
#   - UAV target_position 写到玩家前方扇形格 → "卡位包围 + 阻塞前进路线"
#   - aggression=1.0 / self_preservation=0.05，全员死撑追击
# 结束：回滚每架 UAV AI 字段到 ACTIVE 开始前的原值（saved in _designation_overrides）
# ════════════════════════════════════════════════════════════
func _update_designation(delta: float) -> void:
	if designation == null:
		return
	var prev_active: bool = designation.is_active()
	designation.update(delta)
	var now_active: bool = designation.is_active()
	if not prev_active and now_active:
		_designation_begin()
	elif prev_active and not now_active:
		_designation_end()
	if now_active:
		_designation_tick()


func _designation_begin() -> void:
	_designation_overrides.clear()
	_designation_interceptors.clear()
	_designation_wave_two_sent = false
	if uav_swarm != null:
		uav_swarm.set_replenishing(true)
		uav_swarm.request_reinforcement_wave(DESIG_UAV_WAVE_SIZE)
	if uav_swarm == null or player_ref == null or not is_instance_valid(player_ref):
		EventLogger.log_event("BOSS", "MOTHER GOOSE", "DESIGNATION: target acquired (no swarm/player)")
		return

	## 第一遍：保存原字段 + 切 hunter（解 orbit/shield/leash，全速、激进、不惜命）
	## MQ-111 激光 UAV 被跳过 —— 它们是反导拦截器（限量 2，no_kamikaze），定位是"贴 boss 提供
	## 反导/反机覆盖"，被改 hunter 派出去追玩家会让 boss 失去关键防御层；保留它们继续 shield_leader
	var ai_list: Array[AIController] = []
	for uav in uav_swarm.get_uavs():
		if uav == null or not is_instance_valid(uav) or uav.is_destroyed:
			continue
		if uav.params and uav.params.display_name == "MQ-111":
			continue
		var ai: AIController = _find_uav_ai(uav)
		if ai == null:
			continue
		_designation_overrides[ai] = {
			"orbit_squad_leader": ai.orbit_squad_leader,
			"shield_leader": ai.shield_leader,
			"combat_zone_radius": ai.combat_zone_radius,
			"combat_zone_anchor": ai.combat_zone_anchor,
			"aggression": ai.aggression,
			"self_preservation": ai.self_preservation,
			"simple_ai": ai.simple_ai,
			"evade_missiles": ai.evade_missiles,
		}
		ai.orbit_squad_leader = false
		ai.shield_leader = false
		## 关键：保留 anchor + 极大 radius → ai_controller 把它判为 hunter → 走 HUNTER_UAV_SPEED_RATIO
		## 全速分支（line 1202）；radius 极大不会触发"出界回返"
		ai.combat_zone_anchor = boss_unit
		ai.combat_zone_radius = DESIG_HUNT_RADIUS
		ai.aggression = 1.0
		ai.self_preservation = 0.05
		ai.simple_ai = true
		ai.evade_missiles = true   ## hunter 要活久才能持续给压力
		ai_list.append(ai)

	## 第二遍：挑选"前置伏击"UAV —— 当前位于玩家前半球（与 player forward 同向）且
	## 距玩家最远的几架，派去前方 INTERCEPT_DIST 当伏兵；其余走纯 lead-chase 自然包围
	var ppos: Vector2 = player_ref.global_position
	var fwd := Vector2(sin(player_ref.heading), -cos(player_ref.heading))
	var candidates: Array = []   ## [ai, score]，score = dot(forward, to_uav) * dist（前方且远）
	for ai in ai_list:
		if ai == null or not is_instance_valid(ai) or ai.aircraft == null:
			continue
		var to_uav: Vector2 = ai.aircraft.global_position - ppos
		var d: float = to_uav.length()
		if d < 1.0:
			continue
		var dot: float = fwd.dot(to_uav / d)
		if dot <= 0.0:
			continue   ## 在玩家后半球，不当伏兵（让它从后追）
		candidates.append([ai, dot * d])
	candidates.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var n_intercept: int = int(round(float(ai_list.size()) * DESIG_INTERCEPT_RATIO))
	var intercept_point: Vector2 = ppos + fwd * DESIG_INTERCEPT_DIST
	for i in range(mini(n_intercept, candidates.size())):
		var ai: AIController = candidates[i][0]
		if ai == null or not is_instance_valid(ai):
			continue
		## 清当前目标 + 单点航点 → 走 patrol 路径直冲伏击点；
		## 到达后用雷达重新捕获玩家 → 自动切回 simple_combat lead-chase
		## （经 release_target(TS_BOSS) 清目标，优先级仲裁防抢写）
		if ai.release_target(AIController.TargetSource.TS_BOSS, "designation interceptor"):
			_designation_interceptors[ai] = true
			if ai.aircraft:
				ai.aircraft.ai_override_pursuit = false
				ai.aircraft.target_position = intercept_point
			ai.waypoints = PackedVector2Array([intercept_point])
			ai.current_waypoint_index = 0

	EventLogger.log_event("BOSS", "MOTHER GOOSE",
		"DESIGNATION: target acquired — %d hunters / %d interceptors" %
		[ai_list.size() - _designation_interceptors.size(), _designation_interceptors.size()])


func _designation_end() -> void:
	if uav_swarm != null:
		uav_swarm.set_replenishing(false)
	var n_restored: int = 0
	var bp: Vector2 = boss_unit.global_position if (boss_unit and is_instance_valid(boss_unit)) else Vector2.ZERO
	for key in _designation_overrides.keys():
		## 关键：`key as AIController` 在 key 已被 queue_free 时直接崩"Trying to cast a freed object"
		## —— 必须先 is_instance_valid 才能 cast（UAV 战损释放会带走其 AIController 子节点）
		if not is_instance_valid(key):
			continue
		var ai: AIController = key as AIController
		if ai == null:
			continue
		var saved: Dictionary = _designation_overrides[key]
		ai.orbit_squad_leader = bool(saved.get("orbit_squad_leader", false))
		ai.shield_leader = bool(saved.get("shield_leader", false))
		ai.combat_zone_radius = float(saved.get("combat_zone_radius", 0.0))
		ai.combat_zone_anchor = saved.get("combat_zone_anchor", null)
		ai.aggression = float(saved.get("aggression", 0.5))
		ai.self_preservation = float(saved.get("self_preservation", 0.5))
		ai.simple_ai = bool(saved.get("simple_ai", true))
		ai.evade_missiles = bool(saved.get("evade_missiles", true))
		## 主动清交战状态 + 重置 waypoints —— 否则 UAV 会卡在
		##   "_current_target=player（被 designation_tick 强行设的）→
		##    被 combat_zone_radius*1.5 守卫拉 target 之前一直冲玩家方向 →
		##    脱锁后无 waypoints / 在外圈漂走（hunter 用 solo_squad，没"跟长机"路径）"
		## 强制把所有被 mod 过的 UAV 拉回 boss 周围环形 4 点航点（与 stray_recall 同处理）
		## （经 release_target(TS_BOSS) 清目标，优先级仲裁防抢写）
		if ai.release_target(AIController.TargetSource.TS_BOSS, "designation end recall"):
			if ai.aircraft and is_instance_valid(ai.aircraft):
				ai.aircraft.ai_override_pursuit = false
				ai.aircraft.target_position = bp
			var ring_r: float = 600.0
			ai.waypoints = PackedVector2Array([
				bp + Vector2(ring_r, 0),
				bp + Vector2(0, ring_r),
				bp + Vector2(-ring_r, 0),
				bp + Vector2(0, -ring_r),
			])
			ai.current_waypoint_index = 0
		n_restored += 1
	_designation_overrides.clear()
	_designation_interceptors.clear()
	_designation_wave_two_sent = false
	EventLogger.log_event("BOSS", "MOTHER GOOSE",
		"DESIGNATION: hunt ended, %d UAVs restored & recalled" % n_restored)


func _designation_tick() -> void:
	if player_ref == null or not is_instance_valid(player_ref) or player_ref.is_destroyed:
		return
	if not _designation_wave_two_sent and designation != null \
			and designation.state_timer >= DESIG_UAV_WAVE_TWO_TIME:
		_designation_wave_two_sent = true
		if uav_swarm != null:
			uav_swarm.request_reinforcement_wave(DESIG_UAV_WAVE_SIZE)
		EventLogger.log_event("BOSS", "MOTHER GOOSE", "DESIGNATION: UAV reinforcement wave 2")
	## 全场 team=1 飞机强制把玩家设为当前目标（覆盖远端散兵 + orbit guard），
	## 但跳过被指派为"前置伏击"的 UAV —— 它们需要先飞到伏击点，途中不应被 lead-chase 拉回。
	## 不再覆写 target_position —— 让 simple_combat 自己跑 lead 追击 / patrol 自己跑伏击航点。
	## 这是修复"全部减速停在前置点"的核心：上版每帧用静态点覆盖 lead_pos 导致 AI 路径震荡。
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not u is Aircraft:
			continue
		if u.team != 1:
			continue
		if u == boss_unit:
			continue
		var ac: Aircraft = u
		## MQ-111 反导激光 UAV 在 designation 期间继续守 boss，不强行换目标到玩家
		if ac.params and ac.params.display_name == "MQ-111":
			continue
		var ai: AIController = _find_uav_ai(ac)
		if ai == null:
			continue
		## ACTIVE 中途生成的增援没有经过 _designation_begin 第一遍；首次看见时补登记并切 hunter。
		if ac.get_meta("category", "") == "boss_mother_goose_uav" \
				and not _designation_overrides.has(ai):
			_designation_overrides[ai] = {
				"orbit_squad_leader": ai.orbit_squad_leader,
				"shield_leader": ai.shield_leader,
				"combat_zone_radius": ai.combat_zone_radius,
				"combat_zone_anchor": ai.combat_zone_anchor,
				"aggression": ai.aggression,
				"self_preservation": ai.self_preservation,
				"simple_ai": ai.simple_ai,
				"evade_missiles": ai.evade_missiles,
			}
			ai.orbit_squad_leader = false
			ai.shield_leader = false
			ai.combat_zone_anchor = boss_unit
			ai.combat_zone_radius = DESIG_HUNT_RADIUS
			ai.aggression = 1.0
			ai.self_preservation = 0.05
			ai.simple_ai = true
			ai.evade_missiles = true
		if _designation_interceptors.has(ai):
			continue
		## 经 acquire_target(TS_BOSS) 指派，优先级仲裁防抢写
		ai.acquire_target(player_ref, AIController.TargetSource.TS_BOSS, "designation force player")
