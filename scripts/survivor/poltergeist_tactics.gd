## POLTERGEIST 队级战术 —— 死锁单机换手（Relay Break）
##
## spec: docs/specs/bosses/poltergeist-squadron.md（权威源，数值以 spec 为准，此处为落地副本）
##
## ── 它解决什么 ──
## Poltergeist 的 F-14 被拖进"共速绕圈"死锁时（机头方位角常年 ±90°、低能量、机炮永远
## 咬不上、越绕越慢最后飘走，见 playtest log 20260724_004256），没有任何机制把它拽出来。
## `EngagementSpeedGovernor` 修的是速度几何，管不了"谁也咬不住谁"的死锁——那是 Wraith 靠
## 全队 RESET 解的问题，但 Poltergeist 性格相反（誓死不退），不能抄。
##
## ── Poltergeist 的解法（本模块唯一做的事）──
## 只有**最咬不住的那一架**单独爬升拉开重整能量，其余继续压；**同时最多 1 架**在换手。
## 这直接保证"绝不两架一起变慢变傻"，压迫从不集体消失——这就是 Poltergeist 的 BOSS 级智商。
##
## ── 与 AI 层的分工（关键约束，同 WraithTactics 契约）──
## 不每帧覆盖 AI 字段：只在"进入换手 / 退出换手"两个时点各下一次指令；走位靠真实转弯
## （AIDirective.fly_to + set_target_tier），绝不直接挪坐标。

class_name PoltergeistTactics
extends RefCounted

const PX_PER_M := 0.5                    ## CombatUnit.PIXELS_PER_METER

# ── 数值（spec §2.1，权威源在 spec，这里是落地副本）──
const SAMPLE_S := 0.5                    ## 采样间隔
const DEADLOCK_NOSE_OFF_DEG := 55.0      ## 机头偏角超此 = 这一刻咬不住
const DEADLOCK_HOLD_S := 4.0             ## 连续超标达此 → 进入死锁，可被换手
const DEADLOCK_MAX_DIST_M := 4000.0      ## 仅此距离内判死锁（远距高偏角是正常接近）
const RESET_EXTEND_M := 2200.0           ## 换手机飞向"背离玩家方向"此距离的点
const RESET_DURATION_S := 3.5            ## 换手持续时长
const RESET_COOLDOWN_S := 3.0            ## 换手后冷却，防抖
const MAX_CONCURRENT_RESET := 1          ## 全队任一刻最多几架在换手（灵魂：=1）

var _squad: AceSquad = null
var _log_name := "POLTERGEIST"
var _sample_timer := 0.0

## 按 instance_id 索引的小状态表（成员死亡后每帧过滤，不驻留）
var _deadlock_timer: Dictionary = {}     ## id -> 连续超标累计时长
var _reset_timer: Dictionary = {}        ## id -> 换手剩余时长（>0 = 正在换手）
var _cooldown: Dictionary = {}           ## id -> 换手后冷却剩余

# ══════════════════════════════════════════════
#  生命周期（与 WraithTactics 同构，供 AceSquad 钩子转发）
# ══════════════════════════════════════════════

func setup(squad: AceSquad) -> void:
	_squad = squad
	if squad != null:
		_log_name = squad.display_name

func start() -> void:
	_sample_timer = 0.0
	_deadlock_timer.clear()
	_reset_timer.clear()
	_cooldown.clear()

func stop() -> void:
	# 撤掉本层下过的一切换手指令
	for m in _alive_members():
		if _reset_timer.get((m as Aircraft).get_instance_id(), 0.0) > 0.0:
			_clear_directive(m)
	_deadlock_timer.clear()
	_reset_timer.clear()
	_cooldown.clear()

func update(delta: float) -> void:
	if _squad == null or not _squad.combat_phase_active:
		return
	var player := _player()
	if player == null:
		return
	var alive := _alive_members()
	if alive.is_empty():
		return

	_tick_active_resets(delta, alive)
	_tick_cooldowns(delta)

	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer = SAMPLE_S
	_sample_and_dispatch(alive, player)

# ══════════════════════════════════════════════
#  换手推进 / 冷却
# ══════════════════════════════════════════════

## 推进正在换手的成员：到时撤指令、进冷却、交还 BFM
func _tick_active_resets(delta: float, alive: Array) -> void:
	for v in alive:
		var m := v as Aircraft
		var id := m.get_instance_id()
		var remain: float = _reset_timer.get(id, 0.0)
		if remain <= 0.0:
			continue
		remain -= delta
		if remain <= 0.0:
			_reset_timer.erase(id)
			_deadlock_timer.erase(id)
			_cooldown[id] = RESET_COOLDOWN_S
			_clear_directive(m)   ## 交还 AceSquad PURSUIT → 软重连自动重新 ENGAGE 扑入
			EventLogger.log_event("POLTERGEIST", _log_name,
				"%s 换手完成 → 重新扑入" % m.callsign)
		else:
			_reset_timer[id] = remain

func _tick_cooldowns(delta: float) -> void:
	for id in _cooldown.keys():
		var remain: float = _cooldown[id] - delta
		if remain <= 0.0:
			_cooldown.erase(id)
		else:
			_cooldown[id] = remain

# ══════════════════════════════════════════════
#  死锁采样 + 派发（spec §3.2）
# ══════════════════════════════════════════════

func _sample_and_dispatch(alive: Array, player: Aircraft) -> void:
	var resetting := 0
	for v in alive:
		if _reset_timer.get((v as Aircraft).get_instance_id(), 0.0) > 0.0:
			resetting += 1

	# 累计每架的死锁计时；同时挑出"已死锁且可换手"的候选
	var best: Aircraft = null
	var best_off := 0.0
	for v in alive:
		var m := v as Aircraft
		var id := m.get_instance_id()
		# 正在换手 / 冷却 / 起飞保护期(无 combat_target) / 无敌 → 不参与判定
		if _reset_timer.has(id) or _cooldown.has(id) \
				or m.combat_target == null or m.invulnerable:
			_deadlock_timer.erase(id)
			continue
		var off := nose_off_deg(m, player.global_position)
		var dist_m := m.global_position.distance_to(player.global_position) / PX_PER_M
		if dist_m <= DEADLOCK_MAX_DIST_M and off > DEADLOCK_NOSE_OFF_DEG:
			_deadlock_timer[id] = _deadlock_timer.get(id, 0.0) + SAMPLE_S
		else:
			_deadlock_timer.erase(id)
			continue
		if _deadlock_timer[id] >= DEADLOCK_HOLD_S and off > best_off:
			best = m
			best_off = off

	# 同时换手上限：还有名额且有候选 → 派"最咬不住的那一架"去换手
	if best != null and resetting < MAX_CONCURRENT_RESET:
		_begin_reset(best, player)

## 开始换手：爬升 + 背离玩家拉开。combat_disabled=false（路上有解还是打）
func _begin_reset(m: Aircraft, player: Aircraft) -> void:
	var id := m.get_instance_id()
	_reset_timer[id] = RESET_DURATION_S
	_deadlock_timer.erase(id)
	m.set_target_tier(CombatUnit.AltitudeTier.HIGH)
	var away: Vector2 = m.global_position - player.global_position
	var dir: Vector2 = away.normalized() if away.length_squared() > 1.0 \
			else Vector2(sin(m.heading), -cos(m.heading))
	var pt: Vector2 = player.global_position + dir * (RESET_EXTEND_M * PX_PER_M)
	var d := AIDirective.fly_to(pt, AIDirective.OnArrival.HOLD, 500.0)
	d.combat_disabled = false
	var ai: AIController = m._get_ai_controller()
	if ai != null:
		ai.set_event_directive(d)
	EventLogger.log_event("POLTERGEIST", _log_name,
		"%s 死锁换手：爬升拉开重整（其余继续压）" % m.callsign)

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

## 单机对某点的机头偏角（度）。纯函数，可无头单测。
static func nose_off_deg(m: Aircraft, target_pos: Vector2) -> float:
	var to_t: Vector2 = target_pos - m.global_position
	if to_t.length_squared() < 1.0:
		return 0.0
	var fwd := Vector2(sin(m.heading), -cos(m.heading))
	return absf(rad_to_deg(fwd.angle_to(to_t)))

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
		if is_instance_valid(m) and not (m as Aircraft).is_destroyed:
			out.append(m)
	return out

func _clear_directive(m: Aircraft) -> void:
	if m == null or not is_instance_valid(m):
		return
	var ai: AIController = m._get_ai_controller()
	if ai != null:
		ai.set_event_directive(null)
