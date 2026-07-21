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

## ── 分火 SPREAD standing order（command-wheel §3.6：目标池内各自接敌）──
var _spread_active := false
var _spread_anchor: CombatUnit = null       ## 锚点单位（存活时池随其漂移，阵亡锚定最后位置）
var _spread_anchor_pos := Vector2.ZERO
var _spread_posture: int = 0                ## 分火命令携带的姿态（随各自目标写入）
var _spread_owned := {}                     ## instance_id -> true：由分火管理目标的成员；
											## 单点点名即退出管理（铁律保护，spread 绝不覆盖玩家显式点名）

## FOCUS 包围轴偏移表（spec §3.6：相邻攻击轴 ≥45°，杜绝一字长蛇追尾）
const SURROUND_OFFSETS_DEG: Array = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]

## ── 全力加速 transit（紧急集合/撤离途中，command-wheel §2.7/§2.7.1）──
## 速度注入见 AircraftPhysics.effective_max/cruise_speed_kmh（COMMAND_SPRINT_MULT=1.4）
enum SprintMode { NONE, REGROUP, EVAC }
var _sprint_mode: int = SprintMode.NONE
var _sprint_point := Vector2.ZERO   ## REGROUP=集合点（到达解除）/ EVAC=圈心（出圈解除）

## ── 撤离限时禁入区（command-wheel §2.7.1/§3.7：决策层过滤，非物理墙）──
var _evac_zone_center := Vector2.INF
var _evac_zone_until_ms: int = 0
var _zone_marker: Node2D = null

## ── TIGHT 整队齐射（formation-discipline §3.1）──
## 长机独自持命令目标飞攻击几何，僚机全程编队跟随（整队进入/拉开由编队跟随自然涌现）；
## **齐射触发器 = 长机开火**：长机（含玩家手动开火）射击瞬间开 1.5s 窗口，窗口内僚机被临时
## 授予 combat_target（volley_fire_active 豁免编队防御清除）在槽位里释放；窗口关即回收=禁补射。
var _tight_target: CombatUnit = null
var _volley_open := false
var _volley_until_ms: int = 0
var _volley_quiet_s: float = 999.0   ## 长机连续停火累计；≥ rearm_quiet 才允许下一轮开窗（首轮立即）

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
	_end_tight()                 # 单点新命令终止整队齐射（长机换目标，齐射语境失效）
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.set_combat_target(enemy)
			ac.commanded_target = enemy   # 逐机持久命令
			ac.attack_posture = Situation.POSTURE_AUTO  # 单点点名不带姿态
			ac.surround_bearing_rad = INF
			ac.command_sprint = false                   # 单点新命令解除本机冲刺
			_spread_owned.erase(ac.get_instance_id())   # 单点点名 → 该机退出分火管理（铁律保护）
	_auto_engage_target = null
	_ack("ack_pursue", [_target_label(enemy)])

## 玩家下巡航航点：放弃攻击命令，全队飞向世界坐标点。
func command_move(world_pos: Vector2) -> void:
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_end_spread()
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.commanded_target = null
			ac.attack_posture = Situation.POSTURE_AUTO
			ac.surround_bearing_rad = INF
			ac.command_sprint = false   # 单点移动解除本机冲刺（其余僚机继续执行原广播命令）
			ac.clear_combat_target()
			ac.target_position = world_pos

## 玩家取消（右键 / 地图右键）：放弃攻击命令 + 清航向 + 终止一切轮盘 standing order。
func cancel() -> void:
	_guard_point = Vector2.INF
	_end_spread()
	_end_tight()
	_clear_sprint()
	_clear_evac_zone()
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.commanded_target = null
			ac.attack_posture = Situation.POSTURE_AUTO
			ac.surround_bearing_rad = INF
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

## 紧急集合：全队中断一切任务（含攻击命令），**全力加速**飞往集合点（spec §3.3）。
## 到达（arrival_radius）逐机解除加速；auto-engage 在途中天然不锁敌（target_position 非 INF）。
func command_regroup(point: Vector2) -> void:
	_broadcast_move_all(point)
	_clear_evac_zone()   # 新广播命令终止禁入区（spec §3.7）
	_sprint_mode = SprintMode.REGROUP
	_sprint_point = point
	for ac in _squad_members():
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.command_sprint = true
	_ack("ack_regroup")

## 全队广播"清一切任务 + 飞向点"（紧急集合/防守 TRANSIT 共用骨架）
func _broadcast_move_all(point: Vector2) -> void:
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_end_spread()
	_end_tight()
	_clear_sprint()
	_auto_engage_target = null
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.commanded_target = null
		ac.attack_posture = Situation.POSTURE_AUTO
		ac.surround_bearing_rad = INF
		ac.clear_combat_target()
		ac.target_position = point

## 撤离此区：圈内成员**全力加速**径向散出至圈外（出圈逐机解除加速），圈外成员不生效；
## 圈本身成为限时禁入区（evac_duration_s，AI 决策过滤 + 圈框倒计时标记）。spec §3.7。
func command_evacuate(point: Vector2) -> void:
	var radius := wheel_params.evac_radius_px if wheel_params != null else 1500.0
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_end_spread()
	_end_tight()
	_clear_sprint()
	_auto_engage_target = null
	var any_fleeing := false
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
		ac.attack_posture = Situation.POSTURE_AUTO
		ac.surround_bearing_rad = INF
		ac.clear_combat_target()
		ac.target_position = point + dir * radius * 1.1  # 10% 余量防出圈判定抖动
		ac.command_sprint = true   # 全力逃出（用户定稿"等同规避加速"，同 accessor 注入通道）
		any_fleeing = true
	if any_fleeing:
		_sprint_mode = SprintMode.EVAC
		_sprint_point = point
		_ack("ack_evac")   # 圈外成员不受影响时不回令（没人真的在撤）
	# 限时禁入区：期间 AI 自主决策过滤圈内（_find_target / 拴绳），玩家显式输入不受限
	var dur_s := wheel_params.evac_duration_s if wheel_params != null else 20.0
	_evac_zone_center = point
	_evac_zone_until_ms = Time.get_ticks_msec() + int(dur_s * 1000.0)
	_spawn_zone_marker(point, radius)

## 防守此区（spec §3.4，用户订正定稿）：全队前往该点驻防，只打警戒圈内敌人，
## 敌机飞出圈 × 滞回立刻放弃回防——不深追、不散阵；与点名攻击的区别就在"只守这片区域"。
## 拦截逻辑在 _tick_guard（standing order，铁律之下、自动交战之上，不受自动交战开关约束）。
## TRANSIT 为普通巡航速度（防守无加速条款，区别于紧急集合）。
func command_guard(point: Vector2) -> void:
	_broadcast_move_all(point)   # TRANSIT：清任务飞向圆心（内部先清旧 guard/spread/sprint）
	_clear_evac_zone()           # 新广播命令终止禁入区
	_guard_point = point
	_ack("ack_cover")

## 攻击轮盘广播（spec §3.6 按 fire_allocation 分流）：
##   FOCUS  = 全队统一咬 target（铁律通道）+ 包围轴分离（≥2 机、散开阵型时分配进入方位）；
##   SPREAD = 以 target 为锚点的目标池内各自接敌（_begin_spread）。
## posture = Situation.POSTURE_*：空中 STANDOFF 走 joust 打带跑；面目标走 ground_strafe 分流。
func command_attack_all(target: CombatUnit, posture: int = Situation.POSTURE_AUTO) -> void:
	if target == null or not is_instance_valid(target) or target.is_destroyed:
		return
	_guard_point = Vector2.INF   # 最新输入覆盖 standing order
	_clear_sprint()
	_clear_evac_zone()           # 新广播命令终止禁入区
	_auto_engage_target = null
	if fire_allocation == FireAllocation.SPREAD:
		_begin_spread(target, posture)
		_ack("ack_pursue", [_target_label(target)])   # 分火 = 各自接敌，语义是追击不是包围
		return
	_end_spread()
	# TIGHT 紧密阵型（formation-discipline）：整队齐射路径；ASSAULT 豁免（缠斗物理上不成阵）
	if formation_tight and posture != Situation.POSTURE_ASSAULT:
		_begin_tight_engage(target, posture)
		_ack("ack_pursue", [_target_label(target)])
		return
	_end_tight()
	var members: Array = []
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.set_combat_target(target)
		ac.commanded_target = target   # 逐机持久命令；非操控机由 _enforce_commanded_target 死咬
		ac.attack_posture = posture
		ac.surround_bearing_rad = INF
		members.append(ac)
	_assign_surround_axes(members, target)
	# 包围只在 ≥2 机且非紧密阵型时真的发生（见 _assign_surround_axes）；否则语义退回追击
	var surrounding := not formation_tight and members.size() >= 2
	_ack("ack_surround" if surrounding else "ack_pursue", [_target_label(target)])

## FOCUS 包围轴分配（spec §3.6）：基准 = 发令瞬间"目标 → 小队质心"方位，第 i 机偏移
## SURROUND_OFFSETS_DEG[i]（相邻 ≥45°）。TIGHT 阵型不包围（整队单轴，归 formation-discipline）；
## 单机不包围。消费端 = TacticalPlanner._apply_surround_axis（远于收敛距时飞向自己扇区门点）。
func _assign_surround_axes(members: Array, target: CombatUnit) -> void:
	if formation_tight or members.size() < 2:
		return
	var centroid := Vector2.ZERO
	for ac in members:
		centroid += ac.global_position
	centroid /= float(members.size())
	var d: Vector2 = centroid - target.global_position
	var base: float = atan2(d.x, -d.y) if d.length_squared() > 1.0 else 0.0
	for i in members.size():
		var off_deg: float = SURROUND_OFFSETS_DEG[mini(i, SURROUND_OFFSETS_DEG.size() - 1)]
		members[i].surround_bearing_rad = base + deg_to_rad(off_deg)

# ══════════════════════════════════════════════
#  全力加速 transit + 撤离禁入区（command-wheel §2.7/§2.7.1/§3.7）
# ══════════════════════════════════════════════

func _clear_sprint() -> void:
	if _sprint_mode == SprintMode.NONE:
		return
	_sprint_mode = SprintMode.NONE
	for ac in _squad_members():
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.command_sprint = false

## 冲刺解除判定（挂主 tick，0.3s 分频）：集合=进 arrival_radius / 撤离=出 evac 圈，逐机先到先解除
func _tick_sprint() -> void:
	if _sprint_mode == SprintMode.NONE:
		return
	var arrival := wheel_params.arrival_radius_px if wheel_params != null else 600.0
	var evac_r := wheel_params.evac_radius_px if wheel_params != null else 1500.0
	var any_active := false
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed or not ac.command_sprint:
			continue
		var d: float = ac.global_position.distance_to(_sprint_point)
		var done: bool = (d <= arrival) if _sprint_mode == SprintMode.REGROUP else (d >= evac_r)
		if done:
			ac.command_sprint = false
		else:
			any_active = true
	if not any_active:
		_sprint_mode = SprintMode.NONE

func _evac_zone_active() -> bool:
	return _evac_zone_center != Vector2.INF and Time.get_ticks_msec() < _evac_zone_until_ms

## 禁入区过滤（决策层，非物理墙）：AI 自主目标选择跳过圈内；玩家显式点名不经此处（铁律不受限）
func _in_evac_zone(pos: Vector2) -> bool:
	if not _evac_zone_active():
		return false
	var radius := wheel_params.evac_radius_px if wheel_params != null else 1500.0
	return pos.distance_to(_evac_zone_center) < radius

func _clear_evac_zone() -> void:
	_evac_zone_center = Vector2.INF
	if _zone_marker != null and is_instance_valid(_zone_marker):
		_zone_marker.queue_free()
	_zone_marker = null

func _spawn_zone_marker(point: Vector2, radius: float) -> void:
	if _zone_marker != null and is_instance_valid(_zone_marker):
		_zone_marker.queue_free()
	if _mode == null:
		return
	var m := EvacZoneMarker.new()
	m.radius = radius
	m.until_ms = _evac_zone_until_ms
	m.position = point
	_mode.add_child(m)
	_zone_marker = m

## 撤离禁入圈标记：暗红圈框 + 中心剩余秒数。到时自毁；4Hz 重绘（倒计时驱动，
## 生命周期 ≤ evac_duration_s，符合性能守则 R1"状态变化才重绘"精神）
class EvacZoneMarker extends Node2D:
	var radius: float = 0.0
	var until_ms: int = 0
	var _accum: float = 0.0

	func _process(delta: float) -> void:
		if Time.get_ticks_msec() >= until_ms:
			queue_free()
			return
		_accum += delta
		if _accum >= 0.25:
			_accum = 0.0
			queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.95, 0.35, 0.3, 0.04))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(0.95, 0.35, 0.3, 0.5), 2.0)
		var secs := ceili(float(until_ms - Time.get_ticks_msec()) / 1000.0)
		draw_string(ThemeDB.fallback_font, Vector2(-40.0, 10.0), str(secs),
				HORIZONTAL_ALIGNMENT_CENTER, 80.0, 28, Color(0.95, 0.4, 0.35, 0.8))

# ══════════════════════════════════════════════
#  TIGHT 整队齐射（spec formation-discipline §3.1）
# ══════════════════════════════════════════════

## TIGHT 集火：只有长机接命令目标（飞攻击几何/玩家亲自带队），僚机保持编队跟随——
## "整队进入/整队拉开"由编队跟随对长机轨迹的复现自然涌现，零新编队代码。
func _begin_tight_engage(target: CombatUnit, posture: int) -> void:
	_end_tight()
	var leader := _leader()
	if leader == null:
		return
	_tight_target = target
	_volley_quiet_s = 999.0   # 首轮：长机一开火立即开窗
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		if ac == leader:
			ac.set_combat_target(target)
			ac.commanded_target = target
			ac.attack_posture = posture
			ac.surround_bearing_rad = INF
		else:
			# 僚机不接目标：留在编队里随长机整队机动（齐射窗口内才临时授予开火权）
			ac.commanded_target = null
			ac.attack_posture = Situation.POSTURE_AUTO
			ac.surround_bearing_rad = INF
			ac.volley_fire_active = false
			ac.clear_combat_target()

func _end_tight() -> void:
	if _volley_open:
		_close_volley()
	_tight_target = null
	_volley_open = false

## 齐射窗口状态机（挂主 tick）：长机开火（机炮 is_firing / 对目标有在飞弹）→ 开窗
## volley_window_s；窗口内僚机持临时 combat_target 在编队槽位里释放（锁定由编队机头
## 几何在进入段自然积累）；到时回收（禁补射）；长机停火 ≥ rearm_quiet 后才允许下一轮开窗。
func _tick_tight_volley(step_s: float) -> void:
	if _tight_target == null:
		return
	if not is_instance_valid(_tight_target) or _tight_target.is_destroyed:
		_end_tight()   # 目标亡 → 齐射结束；长机命令由铁律块清理回待命
		return
	var leader := _leader()
	if leader == null:
		_end_tight()
		return
	if _volley_open:
		if Time.get_ticks_msec() >= _volley_until_ms:
			_close_volley()
		return
	var leader_firing: bool = leader.is_firing \
			or (leader.missile_manager != null \
				and leader.missile_manager.count_active_missiles_at(leader, _tight_target) > 0)
	if leader_firing:
		var quiet_need := wheel_params.volley_rearm_quiet_s if wheel_params != null else 2.0
		if _volley_quiet_s >= quiet_need:
			_open_volley(leader)
		_volley_quiet_s = 0.0
	else:
		_volley_quiet_s += step_s

func _open_volley(leader: Aircraft) -> void:
	_volley_open = true
	var window_s := wheel_params.volley_window_s if wheel_params != null else 1.5
	_volley_until_ms = Time.get_ticks_msec() + int(window_s * 1000.0)
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed or ac == leader:
			continue
		ac.volley_fire_active = true
		ac.set_combat_target(_tight_target)   # 临时开火权；编队防御清除因标志跳过本机

func _close_volley() -> void:
	_volley_open = false
	var leader := _leader()
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed or ac == leader:
			continue
		if ac.volley_fire_active:
			ac.volley_fire_active = false
			if ac.commanded_target == null:   # 玩家点名过的不回收（铁律）
				ac.clear_combat_target()

# ══════════════════════════════════════════════
#  分火 SPREAD（spec command-wheel §3.6：锚点目标池内各自接敌）
# ══════════════════════════════════════════════

func _spread_radius() -> float:
	return wheel_params.spread_cluster_radius_px if wheel_params != null else 2000.0

func _begin_spread(anchor: CombatUnit, posture: int) -> void:
	_end_tight()
	_spread_active = true
	_spread_anchor = anchor
	_spread_anchor_pos = anchor.global_position
	_spread_posture = posture
	_spread_owned.clear()
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac.evasion_mode:
			ac.set_evasion_mode(false)
		ac.commanded_target = null
		ac.attack_posture = Situation.POSTURE_AUTO
		ac.surround_bearing_rad = INF
		ac.clear_combat_target()
		_spread_owned[ac.get_instance_id()] = true
	_tick_spread()   # 发令瞬间立即各自选目标，不等下个 tick

func _end_spread() -> void:
	_spread_active = false
	_spread_anchor = null
	_spread_owned.clear()

## 分火 tick：池 = 锚点周边 spread_cluster_radius 内有效敌方。
## 每机"自主粘性"——现目标活着且没漂出池（×1.2 滞回）就不换；死/出池才重挑：
## 少人打的优先（超杀让路的轻量代理），并列取离自己最近。池清空 → 命令结束回归。
## 玩家单点点名过的成员已退出 _spread_owned，本函数绝不碰它们（铁律）。
func _tick_spread() -> void:
	if _spread_anchor != null and is_instance_valid(_spread_anchor) and not _spread_anchor.is_destroyed:
		_spread_anchor_pos = _spread_anchor.global_position   # 池随锚点漂移
	else:
		_spread_anchor = null                                  # 锚点亡 → 锚定最后位置
	var radius := _spread_radius()
	var pool: Array = []
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or u.team != CombatUnit.TEAM_HOSTILE or u.is_destroyed:
			continue
		if u.is_lock_immune():
			continue
		if u.global_position.distance_to(_spread_anchor_pos) <= radius:
			pool.append(u)
	if pool.is_empty():
		_end_spread()
		return
	var members := _squad_members()
	# 让路记账：各池目标已被几名受管成员选中
	var claim := {}
	for ac in members:
		if not is_instance_valid(ac) or ac.is_destroyed or not _spread_owned.has(ac.get_instance_id()):
			continue
		var cur: CombatUnit = ac.commanded_target
		if cur != null and is_instance_valid(cur) and not cur.is_destroyed \
				and cur.global_position.distance_to(_spread_anchor_pos) <= radius * 1.2:
			claim[cur] = int(claim.get(cur, 0)) + 1
	for ac in members:
		if not is_instance_valid(ac) or ac.is_destroyed or not _spread_owned.has(ac.get_instance_id()):
			continue
		var cur: CombatUnit = ac.commanded_target
		if cur != null and is_instance_valid(cur) and not cur.is_destroyed \
				and cur.global_position.distance_to(_spread_anchor_pos) <= radius * 1.2:
			if ac.combat_target != cur:
				ac.set_combat_target(cur)   # 与铁律 tick 同款重指回
			continue
		var best: CombatUnit = null
		var best_claims: int = 1 << 30
		var best_d := INF
		for t in pool:
			var c := int(claim.get(t, 0))
			var dd: float = ac.global_position.distance_to(t.global_position)
			if c < best_claims or (c == best_claims and dd < best_d):
				best_claims = c
				best_d = dd
				best = t
		if best != null:
			ac.set_combat_target(best)
			ac.commanded_target = best
			ac.attack_posture = _spread_posture
			ac.surround_bearing_rad = INF
			claim[best] = int(claim.get(best, 0)) + 1

# ══════════════════════════════════════════════
#  自动交战 tick（每 params.auto_engage_interval_s）
# ══════════════════════════════════════════════

func tick(delta: float) -> void:
	_accum += delta
	if _accum < params.auto_engage_interval_s:
		return
	var step := _accum   # 本 tick 实际步长（齐射安静期累计用）
	_accum = 0.0
	var leader := _leader()
	if leader == null:
		_auto_engage_target = null
		return

	# ── 冲刺解除判定（集合到达 / 撤离出圈，逐机先到先解除）──
	_tick_sprint()

	# ── TIGHT 整队齐射窗口管理（不 return：长机命令仍由下方铁律块维持）──
	_tick_tight_volley(step)

	# ── 分火 SPREAD standing order（各自接敌；单点点名成员已退出管理，铁律各自生效）──
	if _spread_active:
		_tick_spread()
		return

	# ── 铁律：玩家命令目标存活 → 死咬，重新指回，绝不被自动交战夺走 ──
	var cmd: CombatUnit = leader.commanded_target
	if cmd != null:
		if not is_instance_valid(cmd) or cmd.is_destroyed:
			# 命令目标阵亡 → 解除命令 + 回待命（不飞向死敌 lead 点），落到下面自动交战
			leader.commanded_target = null
			leader.attack_posture = Situation.POSTURE_AUTO
			leader.surround_bearing_rad = INF
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
		# 拴绳只对自动锁的目标生效；玩家命令目标已在上面 return，走不到这里。
		# 目标遁入撤离禁入区 = 视同出拴绳（spec §3.7：AI 不追进禁入圈）
		if ct == _auto_engage_target \
				and (leader.global_position.distance_to(ct.global_position) \
					> params.auto_engage_radius_px * params.auto_engage_leash_mult \
					or _in_evac_zone(ct.global_position)):
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

## 半径内最近的有效敌方目标（飞机/地面/船挂点）。跳过锁定免疫的 NavalUnit 船体
## 与撤离禁入区内的目标（决策层过滤，spec §3.7；玩家显式点名不经此处）。
## 用 CombatUnit.all_units（perf 友好共享表），不扫 mode.get_children()。
func _find_target(center: Vector2, radius: float) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := radius
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or u.team != CombatUnit.TEAM_HOSTILE or u.is_destroyed:
			continue
		if u.is_lock_immune():
			continue
		if _in_evac_zone(u.global_position):
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

# ══════════════════════════════════════════════
#  无线电回令（spec radio-chatter §3.4）
# ══════════════════════════════════════════════
##
## 中队级粒度：一条命令只回【一句】，由随机一名存活僚机代表全队应答，
## 绝不 4 架各喊一句。玩家不会自己回自己的令 —— 队里只剩玩家时静默。

## 随机选一名可以应答的僚机（存活 + 非当前操控机）
func _ack_speaker() -> Aircraft:
	var pa := _player_aircraft()
	var pool: Array = []
	for ac in _squad_members():
		if not is_instance_valid(ac) or ac.is_destroyed or ac == pa:
			continue
		if not ac.can_speak_on_radio():   # 无人僚机不回令（spec radio-chatter §2.8）
			continue
		pool.append(ac)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func _ack(trigger: String, fmt_args: Array = []) -> void:
	if _mode == null:
		return
	var radio = _mode.get("_radio")
	if radio == null or not is_instance_valid(radio):
		return
	var speaker := _ack_speaker()
	if speaker == null:
		return
	# 所有 ack_* 共享 "ack" 冷却桶 + 概率骰（见 resources/chatter/radio_chatter.json）：
	# 连点下令不会每次都有人应答，这是刻意的稀疏感。
	radio.say_unit(trigger, speaker, fmt_args)

## 被指目标的可读名（呼号 → display_name → 泛指"目标"）
func _target_label(target: CombatUnit) -> String:
	if target == null or not is_instance_valid(target):
		return tr("RADIO_TARGET_GENERIC")
	if "callsign" in target and String(target.callsign) != "":
		return String(target.callsign)
	if "params" in target and target.params != null and "display_name" in target.params \
			and String(target.params.display_name) != "":
		return String(target.params.display_name)
	return tr("RADIO_TARGET_GENERIC")
