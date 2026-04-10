class_name CommanderAura
extends Node

## 指挥 UAV 光环系统：增益范围内 UAV/UCAV、招募落单无人机

const AURA_RADIUS := 600.0          ## 增益范围（像素，~1200m）
const RECRUIT_RADIUS := 800.0       ## 招募范围（像素，稍大于增益范围）
const SCAN_INTERVAL := 0.5          ## 扫描周期（秒）

# ── 增益参数 ──
const BUFF_SKILL_LEVEL := 0.15
const BUFF_COMPOSURE := 0.15
const BUFF_AGGRESSION := 0.10
const BUFF_ROLL_RATE_MULT := 1.2    ## 滚转速率 +20%
const BUFF_MAX_G_ADD := 1.0         ## 过载 +1G

var _scan_timer: float = 0.0
var _commander: Aircraft = null
var buffed_aircraft: Array[Aircraft] = []   ## 当前被增益的单位（供 overlay 读取）

func _ready() -> void:
	_commander = get_parent() as Aircraft
	_scan_timer = randf_range(0.0, SCAN_INTERVAL)  # 错开扫描周期

func _physics_process(delta: float) -> void:
	if not _commander or _commander.is_destroyed:
		_remove_all_buffs()
		set_physics_process(false)
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_scan_and_buff()
		_try_recruit()
		_cleanup_buffed()
		_designate_target()

# ══════════════════════════════════════════════
#  目标指派（指挥僚机协同进攻）
# ══════════════════════════════════════════════

## Sentinel 自己不战斗，但会扫描最近的敌机并设为 combat_target
## 僚机通过 SQUAD_FOLLOW 的 leader.combat_target 机制收到进攻指令
func _designate_target() -> void:
	var parent_node := _commander.get_parent()
	if not parent_node:
		return

	# 寻找最近的玩家方飞机（team 0）
	var best_target: Aircraft = null
	var best_dist := AURA_RADIUS * 3.0  # 指派范围 = 光环范围的 3 倍
	for child in parent_node.get_children():
		if not (child is Aircraft):
			continue
		var ac := child as Aircraft
		if ac.team != 0 or ac.is_destroyed:
			continue
		var dist := _commander.global_position.distance_to(ac.global_position)
		if dist < best_dist:
			best_dist = dist
			best_target = ac

	if best_target:
		_commander.combat_target = best_target
	else:
		_commander.combat_target = null

# ══════════════════════════════════════════════
#  增益扫描
# ══════════════════════════════════════════════

func _scan_and_buff() -> void:
	var parent_node := _commander.get_parent()
	if not parent_node:
		return

	for child in parent_node.get_children():
		if not (child is Aircraft):
			continue
		var ac := child as Aircraft
		if ac == _commander or ac.team != 1 or ac.is_destroyed:
			continue

		# 只增益 UAV / UCAV 类
		var etype: String = ac.get_meta("enemy_type", "")
		if etype != "uav" and etype != "ucav":
			continue

		var dist := _commander.global_position.distance_to(ac.global_position)

		if dist <= AURA_RADIUS:
			if not ac.has_meta("commander_buffed_by"):
				_apply_buff(ac)
		else:
			# 离开范围，撤除增益
			if ac.has_meta("commander_buffed_by") and ac.get_meta("commander_buffed_by") == _commander:
				_remove_buff(ac)

func _cleanup_buffed() -> void:
	var valid: Array[Aircraft] = []
	for ac in buffed_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			valid.append(ac)
		else:
			# 已毁的直接清理 meta（安全起见）
			if is_instance_valid(ac):
				_remove_buff(ac)
	buffed_aircraft = valid

# ══════════════════════════════════════════════
#  增益施加 / 撤除
# ══════════════════════════════════════════════

func _apply_buff(ac: Aircraft) -> void:
	var ai: AIController = _find_ai(ac)
	if not ai:
		return

	# 存储原始值
	var originals := {
		"skill_level": ai.skill_level,
		"composure": ai.composure,
		"aggression": ai.aggression,
		"roll_rate": ac.params.roll_rate,
		"max_g": ac.params.max_g,
		"simple_ai": ai.simple_ai,
	}
	ac.set_meta("commander_buff_originals", originals)
	ac.set_meta("commander_buffed_by", _commander)

	# 施加增益
	ai.skill_level = clampf(ai.skill_level + BUFF_SKILL_LEVEL, 0.0, 1.0)
	ai.composure = clampf(ai.composure + BUFF_COMPOSURE, 0.0, 1.0)
	ai.aggression = clampf(ai.aggression + BUFF_AGGRESSION, 0.0, 1.0)
	ac.params.roll_rate *= BUFF_ROLL_RATE_MULT
	ac.params.max_g += BUFF_MAX_G_ADD

	buffed_aircraft.append(ac)

func _remove_buff(ac: Aircraft) -> void:
	if not is_instance_valid(ac) or not ac.has_meta("commander_buff_originals"):
		return
	var originals: Dictionary = ac.get_meta("commander_buff_originals")

	var ai: AIController = _find_ai(ac)
	if ai:
		ai.skill_level = originals.get("skill_level", ai.skill_level)
		ai.composure = originals.get("composure", ai.composure)
		ai.aggression = originals.get("aggression", ai.aggression)
	ac.params.roll_rate = originals.get("roll_rate", ac.params.roll_rate)
	ac.params.max_g = originals.get("max_g", ac.params.max_g)

	ac.remove_meta("commander_buff_originals")
	ac.remove_meta("commander_buffed_by")
	buffed_aircraft.erase(ac)

func _remove_all_buffs() -> void:
	var to_remove := buffed_aircraft.duplicate()
	for ac in to_remove:
		_remove_buff(ac)
	buffed_aircraft.clear()

# ══════════════════════════════════════════════
#  招募落单无人机
# ══════════════════════════════════════════════

func _try_recruit() -> void:
	# 获取指挥机自己的 AI 和分队
	var commander_ai: AIController = _find_ai(_commander)
	if not commander_ai or not commander_ai.squad:
		return
	var sq: Squad = commander_ai.squad
	if sq.members.size() >= SurvivorData.COMMANDER_MAX_SQUAD:
		return

	var parent_node := _commander.get_parent()
	if not parent_node:
		return

	for child in parent_node.get_children():
		if sq.members.size() >= SurvivorData.COMMANDER_MAX_SQUAD:
			break
		if not (child is Aircraft):
			continue
		var ac := child as Aircraft
		if ac == _commander or ac.team != 1 or ac.is_destroyed:
			continue

		var etype: String = ac.get_meta("enemy_type", "")
		if etype != "uav" and etype != "ucav":
			continue

		var ai: AIController = _find_ai(ac)
		if not ai or ai.squad != null:
			continue  # 已有分队，跳过

		var dist := _commander.global_position.distance_to(ac.global_position)
		if dist > RECRUIT_RADIUS:
			continue

		# 纳入分队
		var new_index := sq.members.size()
		sq.add_member(ac)
		ai.squad = sq
		ai.squad_index = new_index

		# 切换为完整 AI 以支持 SQUAD_FOLLOW
		if ai.simple_ai:
			ai.simple_ai = false
			ai.evade_missiles = false
			ai.skill_level = clampf(ai.skill_level + 0.1, 0.0, 0.8)
			ai.composure = clampf(ai.composure + 0.1, 0.0, 0.7)
			ai.focus = 0.5
			ai.self_preservation = 0.3
		# 关键：切换到编队跟随状态，否则会以 PATROL 状态运行完整 BFM AI
		ai._state = AIController.AIState.SQUAD_FOLLOW
		ai._formation_blend = 0.0  # 从0开始渐变，平滑过渡到编队托管
		ai._cover_target = null
		ac.formation_mode = true
		ac._formation_leader = sq.leader
		ac.lod_level = 1

func _exit_tree() -> void:
	_remove_all_buffs()

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

func _find_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null
