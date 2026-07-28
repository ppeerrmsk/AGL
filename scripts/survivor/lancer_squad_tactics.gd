## 骑士（lancer）队级掠袭战术（spec events/ace-lancer-mig31 §3.1/§3.2）
##
## ── 它解决什么 ──
## 骑士王牌中队的唯一一套战术循环：
##   CHARGE 横列冲锋 → VOLLEY 齐射（对玩家小队全员分配，1 发/机）→ EXTEND 直线掠远
##   →（回转由 CHARGE 的物理转弯涌现，无独立状态）→ CHARGE …
## 循环直至全灭 / 弹尽（弹尽由事件层转撤离）/ BOSS 闸。
##
## ── 与 AI 层的分工（同 wraith_tactics 铁律：不每帧覆盖 AI 字段）──
##   - CHARGE / EXTEND：成员走 PATROL 航点（横列 = 逐机横向偏移的平行航线，
##     真实 bank 转弯自然归位——编队物理优雅铁律，绝不挪坐标）
##   - VOLLEY：成员 acquire_target(TS_BOSS) + ENGAGE，让既有锁定/发射链路自己打；
##     射出 1 发（弹药差分）即抽回 EXTEND 腿——**不追着拧机头**（骑士纪律：
##     宁可空过也不破坏掠袭直线）
##   - 决策 0.5s 分频（性能守则：AI 决策从低频起步）
##
## 被打断不改相（tier §3.4：王牌不做规避机动）；防御=那 1 枚必躲 flare。
class_name LancerSquadTactics
extends RefCounted

enum Phase { CHARGE, VOLLEY, EXTEND }

const PHASE_NAMES := {Phase.CHARGE: "CHARGE", Phase.VOLLEY: "VOLLEY", Phase.EXTEND: "EXTEND"}

## spec §2.4 数值（PIXELS_PER_METER=0.5：4000m=2000px / 6000m=3000px）
const R_VOLLEY_PX := 2000.0        ## 齐射触发：与玩家小队最近成员距离
const D_EXTEND_PX := 3000.0        ## 掠远距离：拉开到此才回转
const VOLLEY_TIMEOUT_S := 6.0      ## 齐射窗上限（锁不上就放弃本波）
const CHARGE_OVERSHOOT_PX := 2400.0  ## 冲锋航点打到目标质心后方（保证穿越不盘旋）
const EXTEND_LEG_PX := 4500.0      ## 掠远腿长（> D_EXTEND，含裕量）
const WP_REFRESH_NEAR_PX := 400.0  ## 掠远航点快到了还没拉开 → 顺沿续腿
const TICK_S := 0.5                ## 决策分频

var _squad                          ## AceSupportSquad（members/_player/line_spacing）
var phase: int = Phase.CHARGE
var _tick := 0.0
var _volley_t := 0.0
var _volley_ammo0: Dictionary = {}  ## iid → 齐射入窗时的弹数（差分=已射）
var _fired: Dictionary = {}         ## iid → 本波已射（已抽回 EXTEND 腿）


func _init(squad) -> void:
	_squad = squad


## 齐射目标分配（spec §3.2 round-robin）：attacker i → target (i mod n)。
## 纯函数，bench 直接验分配覆盖
static func assign_targets(attacker_count: int, target_count: int) -> Array:
	var out: Array = []
	for i in range(attacker_count):
		out.append(i % maxi(target_count, 1))
	return out


func enter() -> void:
	phase = Phase.CHARGE
	_tick = 0.0
	_enter_charge()

func exit() -> void:
	for m in _alive_members():
		var ai = m._get_ai_controller()
		if ai:
			ai.release_target(AIController.TargetSource.TS_BOSS, "lancer exit")

func update(delta: float) -> void:
	if phase == Phase.VOLLEY:
		_volley_t += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	match phase:
		Phase.CHARGE:
			_tick_charge()
		Phase.VOLLEY:
			_tick_volley()
		Phase.EXTEND:
			_tick_extend()

# ══════════════════════════════════════════════
#  CHARGE —— 横列冲锋（含回转：远处重新冲锋=物理转弯涌现）
# ══════════════════════════════════════════════

func _enter_charge() -> void:
	phase = Phase.CHARGE
	_assign_charge_waypoints()
	EventLogger.log_event("BOSS", _squad.display_name, "lancer → CHARGE")

func _tick_charge() -> void:
	var tgts := _targets()
	if tgts.is_empty():
		return
	# 目标在动：0.5s 刷新平行航线（PATROL 航点只改终点，不打扰转弯控制器）
	_assign_charge_waypoints()
	if _nearest_dist(tgts) <= R_VOLLEY_PX:
		_enter_volley(tgts)

## 平行航线：冲锋轴 = 队质心→目标质心；逐机航点 = 质心后方 overshoot + 槽位横向偏移
func _assign_charge_waypoints() -> void:
	var tgts := _targets()
	if tgts.is_empty():
		return
	var c := _centroid(tgts)
	var sc := _squad_centroid()
	var axis := (c - sc)
	if axis.length_squared() < 1.0:
		axis = Vector2(0, -1)
	axis = axis.normalized()
	var lateral := Vector2(-axis.y, axis.x)
	var alive := _alive_members()
	var n := alive.size()
	for i in range(n):
		var m: Aircraft = alive[i]
		var ai = m._get_ai_controller()
		if not ai:
			continue
		ai.release_target(AIController.TargetSource.TS_BOSS, "lancer charge")
		ai._state = AIController.AIState.PATROL
		var slot: float = (float(i) - float(n - 1) * 0.5) * float(_squad.line_spacing)
		ai.waypoints = PackedVector2Array([_clamp_in_map(c + axis * CHARGE_OVERSHOOT_PX + lateral * slot)])
		ai.current_waypoint_index = 0
		m.is_afterburner = true

# ══════════════════════════════════════════════
#  VOLLEY —— 对玩家小队全员齐射（1 发/机）
# ══════════════════════════════════════════════

func _enter_volley(tgts: Array) -> void:
	phase = Phase.VOLLEY
	_volley_t = 0.0
	_volley_ammo0.clear()
	_fired.clear()
	var alive := _alive_members()
	var mapping := assign_targets(alive.size(), tgts.size())
	for i in range(alive.size()):
		var m: Aircraft = alive[i]
		var ai = m._get_ai_controller()
		if not ai:
			continue
		_volley_ammo0[m.get_instance_id()] = m.missiles_remaining
		if m.missiles_remaining <= 0:
			_fired[m.get_instance_id()] = true   # 空膛机直接走 EXTEND 腿
			_member_extend_leg(m, ai)
			continue
		var tgt: Aircraft = tgts[mapping[i]]
		if is_instance_valid(tgt) and ai.acquire_target(tgt, AIController.TargetSource.TS_BOSS, "lancer volley"):
			ai.enter_engage_state(false)
		m.is_afterburner = true   # 发射不减速（spec §3.1）
	EventLogger.log_event("BOSS", _squad.display_name,
		"lancer → VOLLEY (x%d vs %d targets)" % [alive.size(), tgts.size()])

func _tick_volley() -> void:
	var alive := _alive_members()
	var all_done := true
	for m in alive:
		var iid: int = m.get_instance_id()
		if _fired.has(iid):
			continue
		# 弹药差分：射出 1 发 → 立即抽回 EXTEND 腿（不追着拧）
		if m.missiles_remaining < int(_volley_ammo0.get(iid, m.missiles_remaining)):
			_fired[iid] = true
			var ai = m._get_ai_controller()
			if ai:
				_member_extend_leg(m, ai)
			continue
		all_done = false
	# 全员已射 / 窗口超时（锁不上=本波放弃）→ EXTEND
	if all_done or _volley_t >= VOLLEY_TIMEOUT_S:
		_enter_extend()

# ══════════════════════════════════════════════
#  EXTEND —— 直线掠远（拉开 D_EXTEND 才回转）
# ══════════════════════════════════════════════

func _enter_extend() -> void:
	phase = Phase.EXTEND
	for m in _alive_members():
		if _fired.has(m.get_instance_id()):
			continue   # 已在腿上
		var ai = m._get_ai_controller()
		if ai:
			_member_extend_leg(m, ai)
	EventLogger.log_event("BOSS", _squad.display_name, "lancer → EXTEND")

## 单机掠远腿：沿当前机头直线飞出（穿过玩家队），航点钳在图内
func _member_extend_leg(m: Aircraft, ai) -> void:
	ai.release_target(AIController.TargetSource.TS_BOSS, "lancer extend")
	ai._state = AIController.AIState.PATROL
	var hv := Vector2(sin(m.heading), -cos(m.heading))
	ai.waypoints = PackedVector2Array([_clamp_in_map(m.global_position + hv * EXTEND_LEG_PX)])
	ai.current_waypoint_index = 0
	m.is_afterburner = true

func _tick_extend() -> void:
	var tgts := _targets()
	if tgts.is_empty():
		return
	# 拉开够远 → 回转冲锋（TURNBACK 由 PATROL 航点的物理转弯涌现）
	if _nearest_dist(tgts) >= D_EXTEND_PX:
		_enter_charge()
		return
	# 腿快走完还没拉开（被追/贴边）→ 顺沿续腿
	for m in _alive_members():
		var ai = m._get_ai_controller()
		if not ai or ai.waypoints.is_empty():
			continue
		if m.global_position.distance_to(ai.waypoints[0]) < WP_REFRESH_NEAR_PX:
			_member_extend_leg(m, ai)

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

## 玩家小队全员（含玩家操控机；team 过滤，2Hz 调用不吃性能）
func _targets() -> Array:
	var out: Array = []
	for u in CombatUnit.all_units:
		if u is Aircraft and is_instance_valid(u) and not u.is_destroyed \
				and u.team == CombatUnit.TEAM_PLAYER:
			out.append(u)
	return out

## 本模块只管"骑士标记"成员（ace_tactics_owned）——混编队（2NDWAVE）里
## Teacher 等非骑士成员归基类 PURSUIT，绝不碰
func _alive_members() -> Array:
	var out: Array = []
	for m in _squad.members:
		if is_instance_valid(m) and not m.is_destroyed and m.has_meta(&"ace_tactics_owned"):
			out.append(m)
	return out

func _centroid(list: Array) -> Vector2:
	var c := Vector2.ZERO
	for u in list:
		c += (u as Node2D).global_position
	return c / maxf(list.size(), 1.0)

func _squad_centroid() -> Vector2:
	var alive := _alive_members()
	if alive.is_empty():
		return Vector2.ZERO
	return _centroid(alive)

func _nearest_dist(tgts: Array) -> float:
	var best := INF
	for m in _alive_members():
		for t in tgts:
			best = minf(best, m.global_position.distance_to((t as Node2D).global_position))
	return best

func _clamp_in_map(p: Vector2) -> Vector2:
	var half := MapBoundary.world_half_px() - 600.0
	return Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))
