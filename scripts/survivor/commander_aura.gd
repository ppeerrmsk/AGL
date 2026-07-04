class_name CommanderAura
extends Node

## 指挥 UAV 光环系统
## 功能：
##   1. 招募范围内落单 UAV 加入小队（最多 MAX_WINGMEN 架）
##   2. 小队内 UAV 围绕 Sentinel 飞行并保护它（通过 AI.orbit_squad_leader）
##   3. 在增益范围内的小队成员获得机动/速度/攻击欲望 buff
##   4. 小队成员保持 simple_ai，不使用 BFM 战术（更简单、更稳定）
##   5. Sentinel 自身不参与战斗，也不设定目标（僚机独立扫描并攻击靠近的敌方）

# ── 范围常量 ──
const AURA_RADIUS := 1500.0         ## 增益范围（像素，~3000m）
const RECRUIT_RADIUS := 1800.0      ## 招募范围（像素，稍大于增益范围）
const SCAN_INTERVAL := 0.5          ## 扫描周期（秒）
const MAX_WINGMEN := 5              ## 最大僚机数量（不含指挥机本身）
## 护驾名额：前 GUARD_COUNT 个 recruit 当贴身护驾，剩下 (MAX_WINGMEN-GUARD_COUNT) 当 hunter
## 设计：少量 guard 维持"指挥机被簇拥"的视觉 + 反导拦截能力；多数 hunter 给玩家持续压力，
## 让光环 buff 在 Sentinel 存活时就被玩家感受到，而不是死了才"突然变猛"
const GUARD_COUNT := 2

## Hunter 离 Sentinel 多远开始拽回（像素）—— 超过即刷新 waypoints 牵引到 Sentinel
## simple_ai PATROL 在 waypoints 空时不更新 target_position，hunter 丢目标后会沿残留方向直线漂走
const HUNTER_LEASH_RADIUS := 2500.0

# ── 增益参数（聚焦机动/速度/攻击欲望，不动技能/冷静——simple_ai 也用不上）──
## 设计目标：让玩家明显感觉到 UAV 被增强 —— 回转半径变小、加速更猛、速度更快
const BUFF_AGGRESSION := 0.5        ## 攻击欲望 +0.5
const BUFF_MAX_G_ADD := 6.0         ## 过载 +6G（UAV 4→10G，超越战斗机水准）
const BUFF_STRUCTURAL_G_ADD := 7.0  ## 结构极限 +7G（防止高G时失效）
const BUFF_ROLL_RATE_MULT := 2.5    ## 滚转速率 +150%
const BUFF_SPEED_MULT := 1.5        ## 最大/巡航速度 +50%
const BUFF_ACCEL_MULT := 3.0        ## 加速度 +200%（×3）
const BUFF_STALL_MULT := 0.5        ## 失速速度 ×0.5（允许极紧的低速转弯）

var _scan_timer: float = 0.0
var _commander: Aircraft = null
var buffed_aircraft: Array[Aircraft] = []   ## 当前被增益的单位（供 overlay 读取）

func _ready() -> void:
	_commander = get_parent() as Aircraft
	_scan_timer = randf_range(0.0, SCAN_INTERVAL)  # 错开扫描周期

func _physics_process(delta: float) -> void:
	if not _commander:
		return
	# 指挥机被击坠后：保持 buff 和数据链列表不变，直到坠落动画结束由 _exit_tree 最终清理
	# 这让 overlay 能在坠落过程中淡出（数据链/范围圈逐渐变透明）
	if _commander.is_destroyed:
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_try_recruit()
		_scan_and_buff()
		_cleanup_buffed()
	# Hunter 牵引现在由 AIController.combat_zone_* 在内部处理，不再需要外部刷 waypoint

# ══════════════════════════════════════════════
#  增益扫描（只增益小队成员）
# ══════════════════════════════════════════════

func _scan_and_buff() -> void:
	var commander_ai := _find_ai(_commander)
	if not commander_ai or not commander_ai.squad:
		return
	var sq := commander_ai.squad

	# 遍历小队成员（跳过指挥机本身）
	for ac in sq.members:
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		if ac == _commander:
			continue

		var dist := _commander.global_position.distance_to(ac.global_position)

		if dist <= AURA_RADIUS:
			# 进入增益范围：若尚未 buff 则施加
			if not ac.has_meta("commander_buffed_by"):
				_apply_buff(ac)
		else:
			# 离开增益范围：撤除增益（但仍保留小队成员身份）
			if ac.has_meta("commander_buffed_by") and is_instance_valid(ac.get_meta("commander_buffed_by")) and ac.get_meta("commander_buffed_by") == _commander:
				_remove_buff(ac)

func _cleanup_buffed() -> void:
	var valid: Array[Aircraft] = []
	for ac in buffed_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			valid.append(ac)
		else:
			if is_instance_valid(ac):
				_remove_buff(ac)
	buffed_aircraft = valid

# ══════════════════════════════════════════════
#  增益施加 / 撤除
# ══════════════════════════════════════════════

func _apply_buff(ac: Aircraft) -> void:
	var ai := _find_ai(ac)
	if not ai or not ac.params:
		return

	# 存储原始值以便撤除时还原
	var originals := {
		"aggression": ai.aggression,
		"roll_rate": ac.params.roll_rate,
		"max_g": ac.params.max_g,
		"max_g_structural": ac.params.max_g_structural,
		"max_speed": ac.params.max_speed,
		"cruise_speed": ac.params.cruise_speed,
		"acceleration": ac.params.acceleration,
		"stall_speed_base": ac.params.stall_speed_base,
	}
	ac.set_meta("commander_buff_originals", originals)
	ac.set_meta("commander_buffed_by", _commander)

	# 施加增益：机动 / 速度 / 攻击欲望
	ai.aggression = clampf(ai.aggression + BUFF_AGGRESSION, 0.0, 1.0)
	ac.params.max_g += BUFF_MAX_G_ADD
	ac.params.max_g_structural += BUFF_STRUCTURAL_G_ADD
	ac.params.roll_rate *= BUFF_ROLL_RATE_MULT
	ac.params.max_speed *= BUFF_SPEED_MULT
	ac.params.cruise_speed *= BUFF_SPEED_MULT
	ac.params.acceleration *= BUFF_ACCEL_MULT
	ac.params.stall_speed_base *= BUFF_STALL_MULT

	buffed_aircraft.append(ac)

func _remove_buff(ac: Aircraft) -> void:
	if not is_instance_valid(ac) or not ac.has_meta("commander_buff_originals"):
		return
	var originals: Dictionary = ac.get_meta("commander_buff_originals")

	var ai := _find_ai(ac)
	if ai:
		ai.aggression = originals.get("aggression", ai.aggression)
	if ac.params:
		ac.params.roll_rate = originals.get("roll_rate", ac.params.roll_rate)
		ac.params.max_g = originals.get("max_g", ac.params.max_g)
		ac.params.max_g_structural = originals.get("max_g_structural", ac.params.max_g_structural)
		ac.params.max_speed = originals.get("max_speed", ac.params.max_speed)
		ac.params.cruise_speed = originals.get("cruise_speed", ac.params.cruise_speed)
		ac.params.acceleration = originals.get("acceleration", ac.params.acceleration)
		ac.params.stall_speed_base = originals.get("stall_speed_base", ac.params.stall_speed_base)

	ac.remove_meta("commander_buff_originals")
	ac.remove_meta("commander_buffed_by")
	buffed_aircraft.erase(ac)

func _remove_all_buffs() -> void:
	var to_remove := buffed_aircraft.duplicate()
	for ac in to_remove:
		if is_instance_valid(ac):
			_remove_buff(ac)
	buffed_aircraft.clear()

# ══════════════════════════════════════════════
#  招募落单无人机（上限 MAX_WINGMEN）
# ══════════════════════════════════════════════

func _try_recruit() -> void:
	# 获取指挥机自己的 AI 和分队
	var commander_ai := _find_ai(_commander)
	if not commander_ai or not commander_ai.squad:
		return
	var sq: Squad = commander_ai.squad
	# 僚机数量 = 小队总人数 - 1（减去指挥机）
	if (sq.members.size() - 1) >= MAX_WINGMEN:
		return

	var parent_node := _commander.get_parent()
	if not parent_node:
		return

	for child in parent_node.get_children():
		if (sq.members.size() - 1) >= MAX_WINGMEN:
			break
		if not (child is Aircraft):
			continue
		var ac := child as Aircraft
		if ac == _commander or ac.team != 1 or ac.is_destroyed:
			continue

		# 只招募无人驾驶飞机（is_unmanned 标签），排除指挥机自身
		if not ac.params or not ac.params.is_unmanned:
			continue
		if ac.get_meta("enemy_type", "") == "uav_commander":
			continue

		var ai := _find_ai(ac)
		if not ai:
			continue

		# ── 过滤已属于指挥小队的单位 ──
		# 关键修正：普通 UAV 编队刷出时就有 ai.squad（_spawn_squad 设置），不能简单 skip
		# 只跳过"已经被另一个指挥机招募的"——即已经有 orbit_squad_leader 标志的
		if ai.orbit_squad_leader and ai.squad != null and ai.squad != sq:
			continue
		# 已在本指挥机小队：跳过
		if ai.squad == sq:
			continue

		var dist := _commander.global_position.distance_to(ac.global_position)
		if dist > RECRUIT_RADIUS:
			continue

		# ── 从旧小队移除（普通 UAV 编队的松散分组）──
		if ai.squad != null and ai.squad != sq:
			ai.squad.remove_member(ac)

		# ── 纳入指挥小队 ──
		var new_index := sq.members.size()
		sq.add_member(ac)
		ai.squad = sq
		ai.squad_index = new_index

		# 角色分配：前 GUARD_COUNT 个 recruit 当贴身护驾（绕长机 + 拦导弹），其余全部当 hunter
		# （脱离轨道、自由追击玩家），保留 simple_ai 路径。
		# 之前 100% guard 导致玩家体感"光环没生效"——Sentinel 死后栓绳释放才看到 UAV 用加力追击。
		var existing_wingmen := (sq.members.size() - 1) - 1  # 减自己（commander）和刚加入的本机
		var is_hunter := existing_wingmen >= GUARD_COUNT

		if is_hunter:
			# Hunter：脱离 boss 轨道，simple_ai engage 模式自由追击玩家，buff 通过 squad 成员身份照常生效
			ai.orbit_squad_leader = false
			ai.shield_leader = false
			ai.enable_combat = true
			ai.evade_missiles = true
			ai.aggression = clampf(ai.aggression + 0.2, 0.0, 1.0)
			# 战斗偏好区域：以 Sentinel 为锚，HUNTER_LEASH_RADIUS 为半径
			# 出界强制回返 + 目标飘出 × SLACK 即放弃，防 hunter 漂走不归
			ai.combat_zone_anchor = _commander
			ai.combat_zone_radius = HUNTER_LEASH_RADIUS
		else:
			# Guard：保持 simple_ai，开启绕长机飞行 + 自爆拦截导弹
			ai.orbit_squad_leader = true
			ai.shield_leader = true
			ai.enable_combat = true
			ai.evade_missiles = false

		# 清理旧航点：它们可能围绕玩家刷出的位置，与绕长机飞行冲突
		ai.waypoints = PackedVector2Array()
		ai.release_target(AIController.TargetSource.TS_BOSS, "sentinel recruit reset")

		print("[Sentinel] recruited %s as %s (squad=%d/%d)" % [ac.callsign, ("hunter" if is_hunter else "guard"), sq.members.size() - 1, MAX_WINGMEN])

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
