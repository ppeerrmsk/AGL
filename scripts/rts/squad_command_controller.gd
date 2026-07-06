class_name SquadCommandController
extends Node

## RTS 指挥单一所有者：把"下命令 + 自动交战"逻辑从 survivor_mode 抽出来独立。
## 设计权威源：docs/specs/systems/rts-command.md
##
## 两类目标语义，严格分离：
##   commanded_target  —— 玩家显式点名的攻击命令（铁律）。逐机持有在 Aircraft 上、跨切控持久，
##                        本控制器 + AIController 都不得覆盖；只在目标死/玩家改令时清。
##   _auto_engage_target —— 本控制器自动锁的"贴脸"目标（RTS 自动交战）。可被拴绳/最近目标切换。
##
## 数值全部走 params（RtsCommandParams，resources/rts_command.tres），无硬编码常量。

var params: RtsCommandParams = null
var _mode: Node = null                       ## SurvivorMode（动态访问 selected_aircraft / player_aircraft）
var _auto_engage_target: CombatUnit = null   ## 自动锁的目标（非玩家命令）
var _accum: float = 0.0

## 命令轮盘参数（撤离半径等；由 survivor_mode 在 setup 后注入，spec command-wheel）
var wheel_params: CommandWheelParams = null

## 队级战术状态（轮盘开关的持有处；显示即真实状态，行为接入按 spec 阶段推进）
enum FireAllocation { FOCUS, SPREAD }
var fire_allocation: int = FireAllocation.FOCUS   ## 集火/分火（command-wheel §3.6）
var formation_tight: bool = false                  ## 阵型纪律 FREE/TIGHT（formation-discipline）

## 防守此区 standing order（command-wheel §3.4）：INF = 未激活。
## 用户订正（2026-07-05）：到点后只打圈内敌人，出圈立刻放弃回防——不深追、不散阵。
var _guard_point := Vector2.INF

func setup(mode: Node, p: RtsCommandParams) -> void:
	_mode = mode
	params = p if p != null else RtsCommandParams.new()

# ══════════════════════════════════════════════
#  指令入口（survivor_mode 输入层转发到这里）
# ══════════════════════════════════════════════

## 玩家点名攻击：给被操控机下达持久命令（铁律目标）。
func command_attack(enemy: CombatUnit) -> void:
	if enemy == null:
		return
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.set_combat_target(enemy)
			ac.commanded_target = enemy   # 逐机持久命令
	_auto_engage_target = null

## 玩家下巡航航点：放弃攻击命令，全队飞向世界坐标点。
func command_move(world_pos: Vector2) -> void:
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.commanded_target = null
			ac.clear_combat_target()
			ac.target_position = world_pos

## 玩家取消（右键 / 地图右键）：放弃攻击命令 + 清航向。
func cancel() -> void:
	_guard_point = Vector2.INF
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.commanded_target = null
			ac.clear_combat_target()
			ac.target_position = Vector2.INF

# ══════════════════════════════════════════════
#  命令轮盘广播命令（spec command-wheel：轮盘 = 永远全队）
# ══════════════════════════════════════════════

## 全队成员：玩家小队 leader + 全部僚机；无小队时退化为 selected。
## Squad 引用住在 AIController.squad（Aircraft 无 squad 字段），经 ac._ai_ref 读取。
func _squad_members() -> Array:
	var pa := _player_aircraft()
	if pa != null and pa._ai_ref != null:
		var sq: Squad = pa._ai_ref.squad
		if sq != null and not sq.members.is_empty():
			return sq.members.duplicate()
	return _selected()

## 紧急集合：全队中断一切任务（含攻击命令），飞往集合点（spec §3.3）。
## 阶段 3 待补：途中全力加速（effective_*() accessor 注入）+ 到达判定/交战锁定。
func command_regroup(point: Vector2) -> void:
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_auto_engage_target = null
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.commanded_target = null
		ac.clear_combat_target()
		ac.target_position = point

## 撤离此区：圈内成员径向散出至圈外，圈外成员不生效（spec §3.7）。
## 阶段 3 待补：20s 限时禁入区（AI 决策过滤）+ 规避态全力加速 + 圈框 UI。
func command_evacuate(point: Vector2) -> void:
	var radius := wheel_params.evac_radius_px if wheel_params != null else 1500.0
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_auto_engage_target = null
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		var offset: Vector2 = ac.global_position - point
		if offset.length() >= radius:
			continue  # 已在圈外：逃逸机动不生效（用户定稿）
		var dir := offset.normalized()
		if dir == Vector2.ZERO:
			# 恰在圆心：沿当前机头方向出圈（heading 0=北=-Y，顺时针）
			dir = Vector2(sin(ac.heading), -cos(ac.heading))
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.commanded_target = null
		ac.clear_combat_target()
		ac.target_position = point + dir * radius * 1.1  # 10% 余量防出圈判定抖动

## 防守此区（spec §3.4，用户订正定稿）：全队前往该点驻防，只打警戒圈内敌人，
## 敌机飞出圈 × 滞回立刻放弃回防——不深追、不散阵；与点名攻击的区别就在"只守这片区域"。
## 拦截逻辑在 _tick_guard（standing order，铁律之下、自动交战之上，不受自动交战开关约束）。
func command_guard(point: Vector2) -> void:
	command_regroup(point)       # TRANSIT：清任务飞向圆心（内部会先清旧 guard）
	_guard_point = point

## 攻击轮盘广播：全队清各自目标、统一咬 target（内建集火，走铁律通道）。
## posture 姿态（STANDOFF/ASSAULT 行为差异）与分火 SPREAD 分配归阶段 4。
func command_attack_all(target: CombatUnit) -> void:
	if target == null or not is_instance_valid(target) or target.is_destroyed:
		return
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_auto_engage_target = null
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.set_combat_target(target)
		ac.commanded_target = target   # 逐机持久命令；非操控机由 _enforce_commanded_target 死咬

# ══════════════════════════════════════════════
#  自动交战 tick（每 params.auto_engage_interval_s）
# ══════════════════════════════════════════════

func tick(delta: float) -> void:
	_accum += delta
	if _accum < params.auto_engage_interval_s:
		return
	_accum = 0.0
	var leader := _leader()
	if leader == null:
		_auto_engage_target = null
		return

	# ── 铁律：玩家命令目标存活 → 死咬，重新指回，绝不被自动交战夺走 ──
	var cmd: CombatUnit = leader.commanded_target
	if cmd != null:
		if not is_instance_valid(cmd) or cmd.is_destroyed:
			# 命令目标阵亡 → 解除命令 + 回待命（不飞向死敌 lead 点），落到下面自动交战
			leader.commanded_target = null
			leader.clear_combat_target()
			leader.target_position = Vector2.INF
		else:
			if leader.combat_target != cmd:
				leader.set_combat_target(cmd)
			_auto_engage_target = null
			return

	# ── 防守此区 standing order（铁律之下、自动交战之上；显式命令不受自动交战开关约束）──
	if _guard_point != Vector2.INF:
		_tick_guard(leader)
		return

	# ── 自动交战（受 auto_engage_enabled 开关；玩家命令优先级已在上面处理）──
	var pa: Aircraft = _player_aircraft()
	if pa == null or not pa.auto_engage_enabled:
		_auto_engage_target = null
		return
	var ct: CombatUnit = leader.combat_target
	if ct != null and is_instance_valid(ct) and not ct.is_destroyed:
		# 拴绳只对自动锁的目标生效；玩家命令目标已在上面 return，走不到这里
		if ct == _auto_engage_target \
				and leader.global_position.distance_to(ct.global_position) \
					> params.auto_engage_radius_px * params.auto_engage_leash_mult:
			leader.clear_combat_target()
			leader.target_position = Vector2.INF
			_auto_engage_target = null
		return
	# combat_target 空/亡：若是自动锁的目标打完了 → 回待命（清残留 lead 点）
	if _auto_engage_target != null:
		_auto_engage_target = null
		if ct != null:
			leader.clear_combat_target()
		leader.target_position = Vector2.INF
	# 仍在巡航途中（玩家下的航点/战区）→ 不打，保证抵达
	if leader.target_position != Vector2.INF:
		return
	var tgt := _find_target(leader.global_position, params.auto_engage_radius_px)
	if tgt != null:
		leader.set_combat_target(tgt)
		_auto_engage_target = tgt

## 防守此区拦截 tick（spec §3.4 状态机的执行体，长机驱动、僚机经编队传播跟打）：
## TRANSIT = 未到圈（regroup 已设航点，途中不接敌）；
## INTERCEPT = 敌进警戒圈（以防守点为心，非长机位置）→ 打；
## RETURN = 目标死 / 飞出圈×滞回 → 放弃回圆心；
## ORBIT = 无敌时拴在盘旋半径内（超出即飞回圆心，自然形成盘旋）。
func _tick_guard(leader: Aircraft) -> void:
	var gp := _guard_point
	var guard_r := wheel_params.guard_radius_px if wheel_params != null else 1500.0
	var leash := wheel_params.leash_exit_mult if wheel_params != null else 1.15
	var orbit_r := wheel_params.orbit_radius_px if wheel_params != null else 500.0
	# TRANSIT：长机未进圈前不接敌，保证抵达（航点已由 command_guard 设好）
	if leader.global_position.distance_to(gp) > guard_r:
		return
	var ct: CombatUnit = leader.combat_target
	if ct != null and is_instance_valid(ct) and not ct.is_destroyed:
		# 用户订正核心：目标飞出警戒圈 × 滞回 → 立刻放弃、回防圆心（不深追、不散阵）
		if ct.global_position.distance_to(gp) > guard_r * leash:
			leader.clear_combat_target()
			leader.target_position = gp
		return
	if ct != null:
		leader.clear_combat_target()
	# INTERCEPT：以防守点为圆心搜圈内入侵者（不是以长机位置——守区域不守自己）
	var tgt := _find_target(gp, guard_r)
	if tgt != null:
		leader.set_combat_target(tgt)
		return
	# ORBIT：无敌时拴在圆心附近，超出盘旋半径就飞回（转弯物理自然形成绕圈）
	if leader.global_position.distance_to(gp) > orbit_r:
		leader.target_position = gp

## 半径内最近的有效敌方目标（飞机/地面/船挂点）。跳过锁定免疫的 NavalUnit 船体。
## 用 CombatUnit.all_units（perf 友好共享表），不扫 mode.get_children()。
func _find_target(center: Vector2, radius: float) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := radius
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or u.team == 0 or u.is_destroyed:
			continue
		if u.is_lock_immune():
			continue
		var d := center.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ══════════════════════════════════════════════
#  mode 访问辅助
# ══════════════════════════════════════════════

func _selected() -> Array:
	if _mode == null:
		return []
	return _mode.selected_aircraft

func _leader() -> Aircraft:
	var sel := _selected()
	if sel.is_empty():
		return null
	var leader: Aircraft = sel[0]
	if not is_instance_valid(leader) or leader.is_destroyed:
		return null
	return leader

func _player_aircraft() -> Aircraft:
	if _mode == null:
		return null
	var pa: Aircraft = _mode.player_aircraft
	if pa == null or not is_instance_valid(pa) or pa.is_destroyed:
		return null
	return pa
