## SwarmDirector — Mother Goose UAV 蜂群战略层
##
## 1Hz 累加器节拍（不用 _physics_process，由 mother_goose_controller._process 驱动）。
## 每 tick 给每架活 UAV 分配一个角色（SHOOTER / ATTACKER_N|E|S|W / DECOY / GUARD / RESERVE）
## 与 lane 角度（仅 ATTACKER 有意义）。AIController 的 simple_combat 路径读这两个字段
## 决定 target_position 偏移 —— 实现"多轴同步抵达"的协同攻击。
##
## 设计参考：
##   - Shaw《Fighter Combat》第 6-7 章的 2v1 Bracket（两侧夹击）+ Sandwich（前后包夹）的 swarm 化身
##   - 现代 drone swarm 教科书：lane assignment by hash，30°-60° aspect-wedge 避互相干扰
##
## 与既有系统的契约：
##   - MQ-111（反导拦截激光）强制锁 GUARD —— 它的定位是"贴 boss 提供反导/反机覆盖"，
##     被 director 派出去突击会让 boss 失去关键防御层
##   - DESIGNATION 期间（boss 的 designation 状态机 ACTIVE）切高 attacker_pct 模式
##   - ATTACKER 角色的 UAV 在 mother_goose_controller._update_stray_recall 里 explicit skip
##
## 性能：30 UAV × 1Hz × O(N × roles) ≈ 30×9 ops/tick，~0.01ms。per-frame UAV 增量
## 由 AIController 路径承担（两次字段读 + 一次分支 + 一次向量算 < 0.05ms/UAV）。

class_name SwarmDirector
extends RefCounted

## 角色枚举（与 AIController.swarm_role_override 共享同一数值）
## ROLE_NONE = -1 表示 director 还没分配（出生时 / 玩家不在）
enum Role {
	NONE = -1,
	SHOOTER = 0,       ## 当前最佳 Pk —— 全速 lead-chase 直冲玩家
	ATTACKER_N = 1,    ## 玩家航向系前向（0°）
	ATTACKER_E = 2,    ##              右侧（90°）
	ATTACKER_S = 3,    ##              后向（180°）
	ATTACKER_W = 4,    ##              左侧（270°）
	DECOY = 5,         ## 沿玩家航向垂直方向跑，拉空当
	GUARD = 6,         ## 绕 boss 转 + 反导拦截（既有 orbit_squad_leader 行为）
	RESERVE = 7,       ## 巡航油门，绕 boss 恢复能量
}

const NUM_ATTACKER_WEDGES: int = 4   ## N / E / S / W
const ATTACKER_ROLES: Array[int] = [Role.ATTACKER_N, Role.ATTACKER_E, Role.ATTACKER_S, Role.ATTACKER_W]

var _boss_unit: Aircraft = null
var _player_ref: Aircraft = null
var _swarm = null                                ## MotherGooseUAVSwarm（弱类型避循环依赖）
var _designation = null                          ## MotherGooseDesignation（同上）
var _params: SwarmDirectorParams = null
var _accum: float = 0.0
var _started: bool = false


func setup(boss_unit: Aircraft, player_ref: Aircraft, swarm, designation,
		params: SwarmDirectorParams) -> void:
	_boss_unit = boss_unit
	_player_ref = player_ref
	_swarm = swarm
	_designation = designation
	_params = params
	_started = true


## 玩家机换人时重定向（BossEncounter.set_player_ref 契约的末端一环）
func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	_player_ref = p


## 每帧调用，1Hz 触发战略 tick；玩家无效则跳过
func update(delta: float) -> void:
	if not _started or _params == null:
		return
	if _player_ref == null or not is_instance_valid(_player_ref) or _player_ref.is_destroyed:
		return
	if _boss_unit == null or not is_instance_valid(_boss_unit) or _boss_unit.is_destroyed:
		return
	var period: float = 1.0 / maxf(_params.director_hz, 0.1)
	_accum += delta
	if _accum < period:
		return
	_accum = 0.0
	_tick()


## 1Hz 战略：分配角色 + lane
func _tick() -> void:
	var uavs: Array = _gather_uavs()
	if uavs.is_empty():
		return

	## 1. 按型号分类：
	##    - MQ-111 (laser interceptor)：强制 GUARD，拦截导弹专职
	##    - MQ-110 (missile) / MQ-112 (railgun)：**永远 SHOOTER** —— 锁定/狙击类武器
	##      靠"机头稳对玩家累 lock"工作，不存在 RESERVE 闲置；nose 切换 lane 会让 railgun
	##      打偏、missile 失锁
	##    - MQ-109 (gun)：默认突击主力，进 ATTACKER 楔形轮转
	var assignable: Array = []   ## 仅 MQ-109，参与 ATTACKER/DECOY/GUARD/RESERVE 轮转
	for uav in uavs:
		if not is_instance_valid(uav):
			continue
		var name: String = uav.params.display_name if (uav.params and uav.params.display_name) else ""
		if name == "MQ-111":
			_assign(uav, Role.GUARD, 0.0)
			continue
		if name == "MQ-110" or name == "MQ-112":
			## standoff 类直接锁定 SHOOTER（永远瞄玩家，让 lock_time / charge_duration 累起来）
			_assign(uav, Role.SHOOTER, 0.0)
			continue
		assignable.append(uav)
	if assignable.is_empty():
		return

	## 2. 算目标配额（按 DESIGNATION 调整）。分母只算 MQ-109 池（assignable）
	var desig_active: bool = _designation != null and _designation.is_active()
	var attacker_pct: float = _params.designation_attacker_pct if desig_active else _params.attacker_pct
	var guard_pct: float = 0.0 if desig_active else _params.guard_pct
	var decoy_pct: float = _params.decoy_pct
	var n_attacker: int = int(round(float(assignable.size()) * attacker_pct))
	var n_decoy: int = int(round(float(assignable.size()) * decoy_pct))
	var n_guard: int = int(round(float(assignable.size()) * guard_pct))

	## 3. 在 MQ-109 中再选一个额外的 SHOOTER（aspect 最佳的机炮型给 LEAD_CHASE）
	var n_extra_shooter: int = 1
	var extra_shooters: Array = _pick_shooters(assignable, n_extra_shooter)
	for sh in extra_shooters:
		assignable.erase(sh)
		_assign(sh, Role.SHOOTER, 0.0)

	## 4. ATTACKER 楔形分配：按 UAV 在玩家航向系下象限就近落槽
	var attackers: Array = _pick_attackers(assignable, n_attacker)
	for at in attackers:
		assignable.erase(at[0])   ## at = [uav, role_int]

	## 5. DECOY / GUARD
	var decoys: Array = _pick_decoys(assignable, n_decoy)
	for d in decoys:
		assignable.erase(d)
	var guards: Array = _pick_guards(assignable, n_guard)
	for g in guards:
		assignable.erase(g)
	## 剩下的 MQ-109 → RESERVE
	for u in assignable:
		_assign(u, Role.RESERVE, 0.0)

	## 6. 写下角色 + lane（SHOOTER 在 step 1 standoff_pool + step 3 extra_shooters 已 inline 分配）
	var player_heading: float = _player_ref.heading
	for at in attackers:
		var uav = at[0]
		var role: int = at[1]
		var lane_local: float = _attacker_local_angle(role)
		var lane_world: float = player_heading + lane_local
		_assign(uav, role, lane_world)
	for d in decoys:
		## DECOY lane = 玩家航向 + 90°（垂直方向跑）
		_assign(d, Role.DECOY, player_heading + PI * 0.5)
	for g in guards:
		_assign(g, Role.GUARD, 0.0)


## 写入 AIController 的 swarm_role_override / swarm_lane_world_angle
## 滞回保护：prev_role 若与本轮算出的 best 接近，沿用 prev（防 1Hz 翻牌）
func _assign(uav: Aircraft, role: int, lane_world: float) -> void:
	## defensive guard: tab 切屏 → 多帧累积可能在 _gather_uavs 后某 uav 被 queue_free
	if uav == null or not is_instance_valid(uav) or uav.is_destroyed:
		return
	var ai: AIController = _find_ai(uav)
	if ai == null:
		return
	var prev_role: int = ai.swarm_role_override
	## 滞回：直接覆盖（得分排序已经基于"当前位置就近"分配，本身偏向稳定）
	ai.swarm_role_override = role
	ai.swarm_lane_world_angle = lane_world

	## 经 acquire_target(TS_BOSS) 指派，优先级仲裁防抢写。
	## 注：只在 target 实际变化时调 acquire（内部走 set_combat_target），
	## 避免每秒重置 is_firing 抖机炮 / lock_progress
	if role == Role.SHOOTER \
			or role == Role.ATTACKER_N or role == Role.ATTACKER_E \
			or role == Role.ATTACKER_S or role == Role.ATTACKER_W \
			or role == Role.DECOY:
		if _player_ref != null and is_instance_valid(_player_ref) and not _player_ref.is_destroyed:
			var already_on_target: bool = ai._current_target == _player_ref \
					and uav != null and uav.combat_target == _player_ref
			if already_on_target \
					or ai.acquire_target(_player_ref, AIController.TargetSource.TS_BOSS, "swarm attacker/decoy"):
				if uav != null:
					uav.ai_override_pursuit = true
					uav.orbit_speed_cap = 0.0   ## 解除轨道限速
	elif role == Role.RESERVE:
		## RESERVE 不主动追玩家，但也要解除 orbit_speed_cap 让它能去 reserve 站位
		if uav != null:
			uav.orbit_speed_cap = 0.0

	## 角色变更日志（跨群组切换时记一条）
	if prev_role != role and prev_role != Role.NONE:
		var desig: String = uav.params.display_name if (uav.params and uav.params.display_name) else "UAV"
		EventLogger.log_event("SWARM", desig,
			"role %s → %s" % [_role_name(prev_role), _role_name(role)])


static func _role_name(r: int) -> String:
	match r:
		Role.SHOOTER: return "SHOOTER"
		Role.ATTACKER_N: return "ATTACKER_N"
		Role.ATTACKER_E: return "ATTACKER_E"
		Role.ATTACKER_S: return "ATTACKER_S"
		Role.ATTACKER_W: return "ATTACKER_W"
		Role.DECOY: return "DECOY"
		Role.GUARD: return "GUARD"
		Role.RESERVE: return "RESERVE"
	return "NONE"


## SHOOTER 评分：aspect_align × dist_inv × ammo_ok
func _pick_shooters(pool: Array, k: int) -> Array:
	if k <= 0:
		return []
	var ppos: Vector2 = _player_ref.global_position
	var pfwd := Vector2(sin(_player_ref.heading), -cos(_player_ref.heading))
	var scored: Array = []
	for u in pool:
		if not is_instance_valid(u):
			continue
		var to_player: Vector2 = ppos - u.global_position
		var d: float = to_player.length()
		if d < 1.0:
			continue
		var to_norm: Vector2 = to_player / d
		var u_fwd := Vector2(sin(u.heading), -cos(u.heading))
		## aspect_align: 我机头对准玩家程度（与玩家在我前方）
		var aspect_align: float = clampf(u_fwd.dot(to_norm), 0.0, 1.0)
		## dist_inv: 越近越好（归一到 0-3000px）
		var dist_inv: float = clampf(1.0 - d / 3000.0, 0.0, 1.0)
		## ammo_ok: 简化为 1.0（无弹检查暂占位）
		var ammo_ok: float = 1.0
		var s: float = _params.shooter_weight_aspect * aspect_align \
				+ _params.shooter_weight_dist * dist_inv \
				+ _params.shooter_weight_ammo * ammo_ok
		scored.append([u, s])
	scored.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var out: Array = []
	for i in range(mini(k, scored.size())):
		out.append(scored[i][0])
	return out


## ATTACKER 楔形分配：每个 UAV 算它当前在玩家航向系下的方位，落到最近的楔形
func _pick_attackers(pool: Array, k: int) -> Array:
	if k <= 0 or pool.is_empty():
		return []
	var ppos: Vector2 = _player_ref.global_position
	var p_heading: float = _player_ref.heading
	## 每个 wedge 想填的目标数（均分）
	var per_wedge: int = maxi(1, int(round(float(k) / float(NUM_ATTACKER_WEDGES))))
	## bucket[i] = [uav, dist_to_player]，已按距离升序（楔内优先近的）
	var buckets: Array = [[], [], [], []]
	for u in pool:
		if not is_instance_valid(u):
			continue
		var rel: Vector2 = u.global_position - ppos
		var d: float = rel.length()
		if d < 1.0:
			continue
		## 玩家航向系下方位：0=N(航向前方)、90=E(右)、180=S(后)、270=W(左)
		var local_angle: float = rel.angle() - (p_heading - PI * 0.5)   ## angle() 是 +x 轴起，
		## 玩家 heading=0(北)对应 -y 方向 = angle() = -PI/2，所以减 (heading - PI/2) 把"前方"对齐到 0
		local_angle = fposmod(local_angle, TAU)
		## 落到象限：[315°,45°)=N=0, [45°,135°)=E=1, [135°,225°)=S=2, [225°,315°)=W=3
		var deg: float = rad_to_deg(local_angle)
		var wedge_idx: int
		if deg < 45.0 or deg >= 315.0:
			wedge_idx = 0
		elif deg < 135.0:
			wedge_idx = 1
		elif deg < 225.0:
			wedge_idx = 2
		else:
			wedge_idx = 3
		buckets[wedge_idx].append([u, d])
	## 每 bucket 排序，挑前 per_wedge 个
	var out: Array = []
	var filled: int = 0
	for i in range(NUM_ATTACKER_WEDGES):
		buckets[i].sort_custom(func(a, b): return float(a[1]) < float(b[1]))
		var take: int = mini(per_wedge, buckets[i].size())
		for j in range(take):
			out.append([buckets[i][j][0], ATTACKER_ROLES[i]])
			filled += 1
			if filled >= k:
				return out
	## 还差就从未填满的 bucket 里平铺补
	if filled < k:
		var more: Array = []
		for i in range(NUM_ATTACKER_WEDGES):
			for j in range(per_wedge, buckets[i].size()):
				more.append([buckets[i][j][0], ATTACKER_ROLES[i]])
		for m in more:
			out.append(m)
			filled += 1
			if filled >= k:
				break
	return out


## DECOY：挑最远 + 能量比较高的几架（要能跑远 + 不浪费 SHOOTER 候选）
func _pick_decoys(pool: Array, k: int) -> Array:
	if k <= 0 or pool.is_empty():
		return []
	var ppos: Vector2 = _player_ref.global_position
	var scored: Array = []
	for u in pool:
		if not is_instance_valid(u):
			continue
		var d: float = u.global_position.distance_to(ppos)
		scored.append([u, d])
	scored.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var out: Array = []
	for i in range(mini(k, scored.size())):
		out.append(scored[i][0])
	return out


## GUARD：MQ-109 偏好（机炮近战）；离 boss 近的优先
func _pick_guards(pool: Array, k: int) -> Array:
	if k <= 0 or pool.is_empty():
		return []
	var bp: Vector2 = _boss_unit.global_position
	var scored: Array = []
	for u in pool:
		if not is_instance_valid(u):
			continue
		var d: float = u.global_position.distance_to(bp)
		## MQ-109 加权（偏好机炮当 guard）
		var pref: float = 1.0
		if u.params and u.params.display_name == "MQ-109":
			pref = 0.7   ## 距离系数 ×0.7 = 等效更近，优先选
		scored.append([u, d * pref])
	scored.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var out: Array = []
	for i in range(mini(k, scored.size())):
		out.append(scored[i][0])
	return out


func _gather_uavs() -> Array:
	if _swarm == null:
		return []
	var out: Array = []
	for u in _swarm.get_uavs():
		if u != null and is_instance_valid(u) and not u.is_destroyed:
			out.append(u)
	return out


func _find_ai(uav: Aircraft) -> AIController:
	if uav == null or not is_instance_valid(uav):
		return null
	for child in uav.get_children():
		if child is AIController:
			return child
	return null


## ATTACKER 楔形中心相对玩家航向的本地角度（弧度）
## N=0 / E=PI/2 / S=PI / W=3PI/2
static func _attacker_local_angle(role: int) -> float:
	match role:
		Role.ATTACKER_N: return 0.0
		Role.ATTACKER_E: return PI * 0.5
		Role.ATTACKER_S: return PI
		Role.ATTACKER_W: return PI * 1.5
	return 0.0


## 给外部查询：某 UAV 当前角色（mother_goose_controller._update_stray_recall 用以跳过 ATTACKER）
static func role_of(uav: Aircraft) -> int:
	if uav == null or not is_instance_valid(uav):
		return Role.NONE
	for child in uav.get_children():
		if child is AIController:
			return (child as AIController).swarm_role_override
	return Role.NONE


## 判断角色是否属于 ATTACKER 簇（4 楔形 + SHOOTER）—— 这些角色受 director 主动控制，
## stray recall 应跳过它们
static func is_active_attacker(role: int) -> bool:
	return role == Role.SHOOTER \
			or role == Role.ATTACKER_N or role == Role.ATTACKER_E \
			or role == Role.ATTACKER_S or role == Role.ATTACKER_W
