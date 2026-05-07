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
const VLS_MISSILE_PATH: String = "res://resources/naval/cg_vls_missile.tres"
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
const RECALL_LEASH_PX: float = 3500.0     ## 离 boss 超过此距离 + 无目标 → 召回
var _recall_timer: float = 0.0

## 上一帧被打过 jam 标记的玩家方单位（用于本帧没在场内时主动清理）
func _ready() -> void:
	if jam_shield == null:
		jam_shield = MotherGooseJamShield.new()
		jam_shield.start()
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

	# Jam shield 状态机（boss 死后立刻停止）
	if not boss_dead and jam_shield:
		jam_shield.update(delta)
		_apply_jam_field()
	else:
		_clear_jam_field()

	# VLS 齐射调度（boss 死后停止）
	if not boss_dead:
		_update_vls_salvo(delta)
		# 流浪 UAV 召回（boss 死后不再召回 —— 残存 UAV 自然战斗到死）
		_update_stray_recall(delta)

	# Shield 绘制由独立的 MotherGooseShieldOverlay 接管（脱离 boss transform，
	# 即便 boss 屏外也保证 AOE 圈可见 —— 玩家 gameplay 必须知道范围在哪）


## 给场内玩家方单位施加 jam + slow 状态
## 走标准 status_effects 系统 → 自动写 status_jam_active / status_slow_active 派生标记，
## 同时玩家 HUD 状态栏会渲染 JAM 绿条 + SLOW 蓝条，玩家明确知道在被干扰减速
##   - JAM  → status_jam_active=true → 武器锁定/发射全断（aircraft_weapons 已有路径）
##   - SLOW → 顶速硬 cap 到 SLOW_SPEED_CAP_KMH=350 km/h，禁加力
## 离开场内时不主动清，让 0.5s 自然衰减（_last_jammed 跟踪不再需要）
func _apply_jam_field() -> void:
	if jam_shield == null or not jam_shield.is_effect_active():
		return
	if boss_unit == null or not is_instance_valid(boss_unit):
		return
	var bp: Vector2 = boss_unit.global_position
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not u is Aircraft:
			continue
		if u.team != 0:           ## 只影响玩家方（team=0），UAV/boss 不受波及
			continue
		var ac: Aircraft = u
		if ac.global_position.distance_to(bp) <= jam_shield.current_radius:
			# 续期：每帧把状态时长刷到 JAM_REFRESH_DURATION
			ac.apply_status(StatusEffects.JAM, JAM_REFRESH_DURATION)
			ac.apply_status(StatusEffects.SLOW, JAM_REFRESH_DURATION)


## boss 死亡时调；状态栏的 JAM/SLOW 会自动衰减消失，无需主动清理
func _clear_jam_field() -> void:
	pass


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
		# 强制返航：清残留追击 + 直接朝 boss 飞
		ai._current_target = null
		uav.clear_combat_target()
		uav.ai_override_pursuit = false
		uav.target_position = bp
		# 重新生成围 boss 的 4 点航点（避免 _generate_default_waypoints 用 UAV 当前位置 → 远端打转）
		var ring_r: float = 600.0
		ai.waypoints = PackedVector2Array([
			bp + Vector2(ring_r, 0),
			bp + Vector2(0, ring_r),
			bp + Vector2(-ring_r, 0),
			bp + Vector2(0, -ring_r),
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


