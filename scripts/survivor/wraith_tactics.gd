## WRAITH 队级战术状态机（spec bosses/wraith-squadron §2.3 / §3.1~3.4）
##
## ── 它解决什么 ──
## tier 层（AceSquad）只管"是否交战 / 是否隐形"，它不决定四架飞机**作为一个整体**怎么打。
## 缺了这一层，四架 F-47 就是四个各自跑 BFM 的独立强敌 —— 强度只能靠堆数值，
## 而 spec 明确禁止那条路（"最强不来自数值"）。本模块提供的是**编排**：
##
##   PERCH 建立高位 → BRACKET 诱敌包夹 → PRESS 压制 → RESET 重整 → 回 PERCH
##
## 签名战术是 BRACKET：指定一架当诱饵（**不开火**）把玩家拉进追击，其余三机从
## **与"玩家→诱饵"轴线夹角 ≥60°** 的方位切入。60° 是让包夹成为**真两难**的最小几何条件 ——
## 小于它两翼实际在同一侧，玩家一个转弯就能同时规避；≥60° 时玩家的任何转向都会把
## 六点交给另一侧。
##
## ── 与 AI 层的分工（关键约束）──
## 本模块**不每帧覆盖 AI 字段**，只在相位切换时下一次配置：
##   - 需要"走到某个位置"→ 下 AIDirective（PERCH/RESET 的爬升脱离、BAIT 的拉开）
##   - 需要"从某个方位打进来"→ 写 surround_bearing_rad，让 TacticalPlanner 的包围轴
##     机制去执行（先飞到自己扇区的进入门点、近了解除偏置收敛）——**全程真实转弯**，
##     绝不直接挪坐标
##   - PRESS 相**完全不干预**，让 BFM 决策树自己打
##
## ── 失误只在执行层 ──
## 本模块内**禁止**出现"这次不包夹了"这类决策层随机。判断永远正确，手不完美 ——
## 那部分由 EngagementSpeedGovernor 的减速迟滞与机炮瞄准误差承担（spec §2.4）。

class_name WraithTactics
extends RefCounted

# ══════════════════════════════════════════════
#  相位
# ══════════════════════════════════════════════

enum Phase { PERCH, BRACKET, PRESS, RESET }

const PHASE_NAMES := {
	Phase.PERCH: "PERCH",
	Phase.BRACKET: "BRACKET",
	Phase.PRESS: "PRESS",
	Phase.RESET: "RESET",
}

# ══════════════════════════════════════════════
#  数值（spec §2.3，权威源在 spec，这里是落地副本）
# ══════════════════════════════════════════════

## PERCH：建立高位
const PERCH_ALT_GAIN_M := 2000.0      ## 目标高度 = 玩家高度 + 此值
const PERCH_DONE_DIFF_M := 1500.0     ## 高度差达此即视为建立完成
const PERCH_TIMEOUT_S := 12.0
const PERCH_STANDOFF_M := 2500.0      ## 爬升时相对玩家保持的水平距离（不贴脸爬）

## BRACKET：诱敌包夹（签名战术）
const BRACKET_BAIT_DIST_M := 3000.0   ## BAIT 拉开到距玩家此距离
const BRACKET_MIN_SPLIT_DEG := 60.0   ## 两翼与"玩家→BAIT"轴线的最小夹角
const BRACKET_WING_STEP_DEG := 30.0   ## 同侧多机之间再错开的角度
const BRACKET_BITE_S := 4.0           ## 玩家咬住 BAIT 达此时长 → 收网转 PRESS
const BRACKET_BITE_CONE_DEG := 35.0   ## 判定"玩家在咬 BAIT"的机头夹角
const BRACKET_TIMEOUT_S := 20.0

## PRESS：压制
const PRESS_DURATION_S := 15.0

## RESET：重整
const RESET_DURATION_S := 8.0
const RESET_EXTEND_M := 3000.0        ## 拉开至少此距离

## 退化检测（RESET 的核心触发器）
const DEGRADE_SAMPLE_S := 0.5         ## 采样间隔
const DEGRADE_ANGLE_DEG := 50.0       ## 全队平均机头偏角超此算"谁也咬不住谁"
const DEGRADE_HOLD_S := 6.0           ## 连续超标达此时长 → 强制 RESET

const PX_PER_M := 0.5                 ## CombatUnit.PIXELS_PER_METER

# ══════════════════════════════════════════════
#  运行时状态
# ══════════════════════════════════════════════

var phase: int = Phase.PERCH
var phase_timer: float = 0.0

var _squad: AceSquad = null
var _bait: Aircraft = null
var _bite_timer: float = 0.0          ## 玩家咬住 BAIT 的累计时长
var _degrade_timer: float = 0.0       ## 平均机头偏角连续超标的累计时长
var _sample_timer: float = 0.0
var _bait_refresh: float = 0.0
var _log_name: String = "WRAITH"

# ══════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════

func setup(squad: AceSquad) -> void:
	_squad = squad
	_log_name = squad.display_name if squad != null else "WRAITH"

## 进入 PURSUIT 时调用：从 PERCH 起手
func start() -> void:
	phase = Phase.PERCH
	phase_timer = 0.0
	_bite_timer = 0.0
	_degrade_timer = 0.0
	_sample_timer = 0.0
	_enter_phase(Phase.PERCH)

## 离开 PURSUIT（进隐形 / 全灭 / 事件结束）时调用：撤掉本层下过的一切
func stop() -> void:
	_clear_all_directives()
	_clear_all_bearings()
	_bait = null

func update(delta: float) -> void:
	if _squad == null or not _squad.combat_phase_active:
		return
	var player := _player()
	if player == null:
		return
	var alive := _alive_members()
	if alive.is_empty():
		return

	phase_timer += delta
	_tick_degradation(delta, alive, player)

	var next: int = _decide_next(alive, player)
	if next != phase:
		_exit_phase(phase)
		var prev := phase
		phase = next
		phase_timer = 0.0
		_enter_phase(next)
		EventLogger.log_event("WRAITH", _log_name, "战术相位 %s → %s" % [
			PHASE_NAMES[prev], PHASE_NAMES[next]])

	_update_phase(delta, alive, player)

# ══════════════════════════════════════════════
#  相位决策
# ══════════════════════════════════════════════

func _decide_next(alive: Array, player: Aircraft) -> int:
	# 退化检测优先于一切：谁也咬不住谁时，任何相位都该重整
	# （PERCH/RESET 本身就在脱离，不需要再触发）
	if _degrade_timer >= DEGRADE_HOLD_S and phase != Phase.RESET and phase != Phase.PERCH:
		EventLogger.log_event("WRAITH", _log_name,
			"退化检测触发：全队平均机头偏角 >%.0f° 持续 %.1fs → 强制 RESET" % [
				DEGRADE_ANGLE_DEG, DEGRADE_HOLD_S])
		return Phase.RESET

	match phase:
		Phase.PERCH:
			if phase_timer >= PERCH_TIMEOUT_S:
				return Phase.BRACKET
			if _altitude_edge_m(alive, player) >= PERCH_DONE_DIFF_M:
				return Phase.BRACKET
		Phase.BRACKET:
			if _bite_timer >= BRACKET_BITE_S:
				EventLogger.log_event("WRAITH", _log_name,
					"收网：玩家咬住 BAIT %.1fs → 两翼进入攻击" % _bite_timer)
				return Phase.PRESS
			if phase_timer >= BRACKET_TIMEOUT_S:
				return Phase.PRESS
		Phase.PRESS:
			if phase_timer >= PRESS_DURATION_S:
				return Phase.RESET
		Phase.RESET:
			if phase_timer >= RESET_DURATION_S:
				return Phase.PERCH
	return phase

func _enter_phase(p: int) -> void:
	match p:
		Phase.PERCH:
			_clear_all_bearings()
			_perch_enter()
		Phase.BRACKET:
			_bracket_enter()
		Phase.PRESS:
			# 压制相【完全放手】：撤掉所有 directive 与包围偏置，让 BFM 决策树自己打。
			# KNIGHT 的近距参数与 SNIPER 的 BVR 站位带已在 spawn 时静态写入（§3.5），
			# 不需要本层再干预距离
			_clear_all_directives()
			_clear_all_bearings()
		Phase.RESET:
			_clear_all_bearings()
			_reset_enter()

func _exit_phase(p: int) -> void:
	match p:
		Phase.BRACKET:
			# 诱饵恢复开火权
			_clear_directive(_bait)
			_bait = null
			_bite_timer = 0.0
		Phase.PERCH, Phase.RESET:
			_clear_all_directives()
		_:
			pass

func _update_phase(delta: float, alive: Array, player: Aircraft) -> void:
	match phase:
		Phase.BRACKET:
			_bracket_update(delta, alive, player)
		_:
			pass

# ══════════════════════════════════════════════
#  PERCH —— 建立高位（§3.3）
# ══════════════════════════════════════════════

## 高位的意义：本作高度是虚拟数值，但俯冲/爬升影响速度。高位 = 可以用势能换速度发起攻击，
## 攻击失败后又能爬回去 —— 每一轮交换都握有能量主动权。
func _perch_enter() -> void:
	var player := _player()
	if player == null:
		return
	var tier: int = _perch_tier(player)
	var alive := _alive_members()
	for i in range(alive.size()):
		var m: Aircraft = alive[i]
		m.set_target_tier(tier)
		# 爬升点：绕到玩家侧后方 standoff 处再爬，不贴脸。四机分散在扇面上避免撞一起
		var ang: float = player.heading + PI + deg_to_rad(-45.0 + 30.0 * float(i))
		var pt: Vector2 = player.global_position \
				+ Vector2(sin(ang), -cos(ang)) * (PERCH_STANDOFF_M * PX_PER_M)
		# combat_disabled=false：爬升途中仍可开火（directive 只接管导航）
		_set_directive(m, _fly_to(pt), false)

## 目标高度档 = 玩家高度 + PERCH_ALT_GAIN_M 落在哪一档（LOW 2000 / MID 5500 / HIGH 10000）
static func perch_tier_for(player_alt_m: float) -> int:
	var want: float = player_alt_m + PERCH_ALT_GAIN_M
	if want >= CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.HIGH]:
		return CombatUnit.AltitudeTier.HIGH
	if want >= CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.MID]:
		return CombatUnit.AltitudeTier.HIGH if want - CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.MID] \
				> CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.HIGH] - want \
				else CombatUnit.AltitudeTier.MID
	return CombatUnit.AltitudeTier.MID

func _perch_tier(player: Aircraft) -> int:
	return perch_tier_for(player.altitude)

## 全队相对玩家的**最大**高度差（有一架站上高位就算建立了优势的前沿）
func _altitude_edge_m(alive: Array, player: Aircraft) -> float:
	var best := 0.0
	for m in alive:
		best = maxf(best, (m as Aircraft).altitude - player.altitude)
	return best

# ══════════════════════════════════════════════
#  BRACKET —— 诱敌包夹（§3.2，签名战术）
# ══════════════════════════════════════════════

func _bracket_enter() -> void:
	var player := _player()
	if player == null:
		return
	var alive := _alive_members()
	_bait = pick_bait(alive)
	_bite_timer = 0.0
	_bait_refresh = 0.0
	if _bait == null:
		return
	# 诱饵：不开火（combat_disabled=true）。它的任务是被追，不是杀人
	_set_directive(_bait, _fly_to(_bait_point(player)), true)
	_assign_wing_bearings(alive, player)
	EventLogger.log_event("WRAITH", _log_name,
		"BRACKET 展开：BAIT=%s（不开火），两翼分离轴 ≥%.0f°" % [
			_bait.callsign, BRACKET_MIN_SPLIT_DEG])

func _bracket_update(delta: float, alive: Array, player: Aircraft) -> void:
	if _bait == null or not is_instance_valid(_bait) or _bait.is_destroyed:
		# 诱饵阵亡 → 顺位重选并重算包围轴（不中断相位，包夹继续）
		_bait = pick_bait(alive)
		if _bait != null:
			_set_directive(_bait, _fly_to(_bait_point(player)), true)
			_assign_wing_bearings(alive, player)
		return

	# 诱饵拉开点随玩家移动刷新（0.5s 一次；每帧重下会清 directive 内部状态）
	_bait_refresh -= delta
	if _bait_refresh <= 0.0:
		_bait_refresh = 0.5
		_set_directive(_bait, _fly_to(_bait_point(player)), true)
		_assign_wing_bearings(alive, player)

	# 收网判定：玩家机头是否咬住诱饵
	if is_biting(player, _bait):
		_bite_timer += delta
	else:
		_bite_timer = maxf(_bite_timer - delta * 2.0, 0.0)   # 松口衰减快于咬住累积

## 诱饵拉开点：玩家【机头前方】BRACKET_BAIT_DIST_M 处。
## 之所以是正前方而不是随便一个远点 —— 诱饵必须**保持在玩家雷达锥内**，
## 看起来是一个能吃下的猎物，否则玩家根本不会去追，包夹就无从谈起。
func _bait_point(player: Aircraft) -> Vector2:
	var fwd := Vector2(sin(player.heading), -cos(player.heading))
	return player.global_position + fwd * (BRACKET_BAIT_DIST_M * PX_PER_M)

## BAIT 指定与继任顺位（§3.2-1）：默认二号机（KNIGHT）；阵亡则顺位取存活 KNIGHT，再取 SNIPER。
## 纯函数，可单测。
static func pick_bait(alive: Array) -> Aircraft:
	if alive.is_empty():
		return null
	var knights: Array = []
	var snipers: Array = []
	for v in alive:
		var m := v as Aircraft
		if m == null:
			continue
		if AceSquad.role_of(m) == AceSquad.AceRole.SNIPER:
			snipers.append(m)
		else:
			knights.append(m)
	# 默认二号机 = KNIGHT 里的第二架（spawn 顺序即 squad_index 顺序）
	if knights.size() >= 2:
		return knights[1]
	if knights.size() == 1:
		return knights[0]
	if not snipers.is_empty():
		return snipers[0]
	return null

## "玩家 → BAIT" 轴线，以 **heading 约定**（0=北，顺时针）表达。纯函数，可单测。
## surround_bearing 的消费端用 `Vector2(sin(brg), -cos(brg))` 还原方向，必须同源。
static func axis_heading(from_pos: Vector2, to_pos: Vector2) -> float:
	var d: Vector2 = to_pos - from_pos
	if d.length_squared() < 1.0:
		return 0.0
	return atan2(d.x, -d.y)

## 两翼包围方位分配（§3.2-3）。
##
## 轴线 = 玩家 → BAIT 的方向。其余各机分到轴线**两侧**、夹角 ≥ BRACKET_MIN_SPLIT_DEG，
## 同侧多机再按 BRACKET_WING_STEP_DEG 错开。左右交替保证真的分成"两翼"而不是一边倒。
static func wing_bearings(axis_rad: float, wing_count: int) -> Array:
	var out: Array = []
	for i in range(wing_count):
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var rank: int = i / 2
		var off_deg: float = BRACKET_MIN_SPLIT_DEG + BRACKET_WING_STEP_DEG * float(rank)
		out.append(axis_rad + side * deg_to_rad(off_deg))
	return out

func _assign_wing_bearings(alive: Array, player: Aircraft) -> void:
	if _bait == null:
		return
	# ⚠ surround_bearing 走 **heading 约定**（0=北，方向向量 = (sin, -cos)），
	#   不是标准 atan2(y,x)。用 .angle() 会让整个包围轴偏 90°
	var axis: float = axis_heading(player.global_position, _bait.global_position)
	var wings: Array = []
	for v in alive:
		var m := v as Aircraft
		if m != null and m != _bait:
			wings.append(m)
	var bearings: Array = wing_bearings(axis, wings.size())
	for i in range(wings.size()):
		(wings[i] as Aircraft).surround_bearing_rad = float(bearings[i])

## 玩家是否正在咬 BAIT：机头指向诱饵且诱饵是它的战斗目标之一。
## 只看机头夹角 —— 玩家可能还没锁定就已经在追了，那也算上钩。纯函数，可单测。
static func is_biting(player: Aircraft, bait: Aircraft) -> bool:
	if player == null or bait == null:
		return false
	if not is_instance_valid(player) or not is_instance_valid(bait):
		return false
	if player.is_destroyed or bait.is_destroyed:
		return false
	var to_bait: Vector2 = bait.global_position - player.global_position
	if to_bait.length_squared() < 1.0:
		return true
	var fwd := Vector2(sin(player.heading), -cos(player.heading))
	var ang: float = absf(rad_to_deg(fwd.angle_to(to_bait)))
	return ang <= BRACKET_BITE_CONE_DEG

# ══════════════════════════════════════════════
#  RESET —— 重整（§3.4）
# ══════════════════════════════════════════════

## 与 EngagementSpeedGovernor 互补：治理层保证他们**能**咬住目标（修几何），
## RESET 保证他们在**咬不住时不会傻转**（修死锁）。
func _reset_enter() -> void:
	var player := _player()
	if player == null:
		return
	var alive := _alive_members()
	var tier: int = _perch_tier(player)
	for i in range(alive.size()):
		var m: Aircraft = alive[i]
		m.set_target_tier(tier)   ## 脱离同时爬升，为下一轮 PERCH 预先攒高度
		# 各自沿"背离玩家"的方向散开拉远，扇面避免四机挤成一条线
		var away: Vector2 = m.global_position - player.global_position
		var base_ang: float = away.angle() if away.length_squared() > 1.0 else m.heading
		var ang: float = base_ang + deg_to_rad(-30.0 + 20.0 * float(i))
		var pt: Vector2 = player.global_position \
				+ Vector2(cos(ang), sin(ang)) * (RESET_EXTEND_M * PX_PER_M)
		# combat_disabled=false：脱离是**几何行为**，不是缴械 —— 路上有解还是要打
		_set_directive(m, _fly_to(pt), false)

# ══════════════════════════════════════════════
#  退化检测（§3.4）
# ══════════════════════════════════════════════

## 每 DEGRADE_SAMPLE_S 采样全队对玩家的机头偏角均值；连续 DEGRADE_HOLD_S 超标 → RESET。
## 这是对"共速绕圈、谁也咬不住谁"（playtest log 20260720_172222）的结构性防御。
func _tick_degradation(delta: float, alive: Array, player: Aircraft) -> void:
	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer = DEGRADE_SAMPLE_S
	var avg: float = average_nose_off_deg(alive, player.global_position)
	if avg > DEGRADE_ANGLE_DEG:
		_degrade_timer += DEGRADE_SAMPLE_S
	else:
		_degrade_timer = 0.0

## 全队对某点的机头偏角均值（度）。纯函数，可单测。
static func average_nose_off_deg(members: Array, target_pos: Vector2) -> float:
	var total := 0.0
	var n := 0
	for v in members:
		var m := v as Aircraft
		if m == null or not is_instance_valid(m) or m.is_destroyed:
			continue
		var to_t: Vector2 = target_pos - m.global_position
		if to_t.length_squared() < 1.0:
			continue
		var fwd := Vector2(sin(m.heading), -cos(m.heading))
		total += absf(rad_to_deg(fwd.angle_to(to_t)))
		n += 1
	return total / float(n) if n > 0 else 0.0

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

func _player() -> Aircraft:
	if _squad == null:
		return null
	var p: Aircraft = _squad._player
	if p == null or not is_instance_valid(p) or p.is_destroyed:
		return null
	return p

func _alive_members() -> Array:
	var out: Array = []
	if _squad == null:
		return out
	for m in _squad.members:
		if is_instance_valid(m) and not m.is_destroyed:
			out.append(m)
	return out

func _fly_to(pt: Vector2) -> AIDirective:
	# arrival_radius 给大一点 + on_arrival=HOLD：抵达后原地盘旋等相位切换，
	# 而不是 RELEASE 掉指令让 AI 立刻冲回去（那会毁掉本相位的站位意图）
	return AIDirective.fly_to(pt, AIDirective.OnArrival.HOLD, 500.0)

func _set_directive(m: Aircraft, d: AIDirective, combat_disabled: bool) -> void:
	if m == null or not is_instance_valid(m):
		return
	var ai: AIController = m._get_ai_controller()
	if ai == null:
		return
	d.combat_disabled = combat_disabled
	ai.set_event_directive(d)

func _clear_directive(m: Aircraft) -> void:
	if m == null or not is_instance_valid(m):
		return
	var ai: AIController = m._get_ai_controller()
	if ai != null:
		ai.set_event_directive(null)

func _clear_all_directives() -> void:
	for m in _alive_members():
		_clear_directive(m)

func _clear_all_bearings() -> void:
	for m in _alive_members():
		(m as Aircraft).surround_bearing_rad = INF
