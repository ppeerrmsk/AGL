class_name RoeDirector
extends RefCounted
##
## ROE 指挥部（spec global-awareness-roe）—— 中队级察觉 + 任务姿态 + leash 纪律。
##
## 职责边界：本模块只【写】单位 meta（roe_posture / roe_aware_until / roe_zone_* /
## roe_hunt 摘除），共享 AI 层的感知门（ai_controller._roe_allows_scored_engage）只【读】。
## 全部逻辑骑 2s tick（SurvivorSpawner.update 驱动），零每帧全场扫描。
##
## 察觉三来源（§2.2，任一命中即全队察觉，写 roe_aware_until = now + 15s）：
##   1. 感知圈：dist(长机, 玩家小队最近单位) ≤ 长机雷达距离（全向）
##   2. 事件察觉：任一成员掉血（hp 差分）/ 被锁定（is_locked，全局锁定循环现成产物）
##      —— 战区聚合：区内任一敌单位（含地面 TGT / 舰）被伤害 → 全区守军察觉
##   3. datalink：战区雷达站存活 且 玩家单位进 20km → 该区守军察觉
##
## 姿态派生（§2.3，落地修订：由 category / reinf_phase / roe_hunt 派生，不做字段合并迁移）：
##   roe_hunt meta → hunt ｜ reinforcement: transit/egress/patrol ｜ zone_air → garrison
##   其它（adds / boss / zone_naval / 未分类）→ ""（豁免，感知门不约束）

## ── 战斗热度（§2.4）：难度的主动压力杠杆，纯内部量（不上 HUD，效果即反馈）──
## 唯一输出 = hunter 配额 round(2 + 10 × heat/100)；静默基线（heat 贴等级地板）
## 复刻既有配额曲线 max(3, 2 + level/2)，活跃度在其上加成。
const HEAT_KILL := 5.0             ## 玩家小队击杀敌机
const HEAT_GROUND_KILL := 8.0      ## 玩家小队击毁地面 TGT / 舰船
const HEAT_ZONE_CAPTURED := 15.0   ## 攻克战区
const HEAT_PLAYER_HIT := 2.0       ## 玩家小队成员被命中
const HEAT_QUIET_GRACE_S := 6.0    ## 连续无玩家小队交战事件此秒数后开始衰减
const HEAT_DECAY_PER_S := 2.0      ## 衰减速率
const HEAT_TICK_S := 1.0           ## 热度账本 tick

var sp  ## SurvivorSpawner（借 mode / player_aircraft / _get_ai）
var heat: float = 0.0
var _accum: float = 0.0
var _heat_accum: float = 0.0
var _last_combat_event_s: float = -999.0
var _prev_hp: Dictionary = {}          ## instance_id → 上个 tick 的 hp（敌方，伤害事件察觉）
var _prev_player_hp: Dictionary = {}   ## instance_id → 上个热度 tick 的 hp（玩家小队被命中检测）
var _last_logged_quota: int = -1
var _zone_lookup: Dictionary = {}      ## zone_id(String) → {center: Vector2, radius: float}
var _squad_heat_component: float = 0.0 ## 僚机规模产生的动态地板分量
var _last_squad_size: int = 1
var _squad_heat_initialized: bool = false


func _init(spawner) -> void:
	sp = spawner
	for z in ZoneData.ZONES:
		_zone_lookup[String(z["id"])] = {"center": z["center"], "radius": float(z["radius"])}
	# 击杀热度走既有击杀归因信号（air kill；地面击杀由 spawner._detect_kills 直调 add_heat）
	if sp != null:
		EventLogger.kill_recorded.connect(_on_kill_recorded)


## ── 热度纯函数（单测入口，test_roe_director.gd）──

static func heat_floor_for_level(level: int, squad_size: int = 1) -> float:
	return SurvivorData.squad_heat_floor(level, squad_size)

static func quota_for_heat(h: float) -> int:
	return int(round(2.0 + 10.0 * clampf(h, 0.0, 100.0) / 100.0))

## 一步热度演化：quiet_s = 距最近一次玩家小队交战事件的秒数
static func step_heat_with_floor(h: float, quiet_s: float, floor_value: float, dt: float) -> float:
	if quiet_s > HEAT_QUIET_GRACE_S:
		h -= HEAT_DECAY_PER_S * dt
	return clampf(h, floor_value, SurvivorData.SQUAD_HEAT_MAX)


static func step_heat_value(h: float, quiet_s: float, level: int, dt: float, squad_size: int = 1) -> float:
	return step_heat_with_floor(h, quiet_s, heat_floor_for_level(level, squad_size), dt)


func hunter_quota() -> int:
	return quota_for_heat(heat)


func add_heat(amount: float) -> void:
	heat = clampf(heat + amount, 0.0, 100.0)
	_last_combat_event_s = EventLogger.get_game_time()


func _on_kill_recorded(_killer: String, _victim: String, _kind: String,
		killer_team: int, victim_team: int, _victim_voiced: bool) -> void:
	# 场景已重开（旧 director 残留连接）→ 自摘
	if sp == null or sp.mode == null or not is_instance_valid(sp.mode):
		if EventLogger.kill_recorded.is_connected(_on_kill_recorded):
			EventLogger.kill_recorded.disconnect(_on_kill_recorded)
		sp = null
		return
	# 仅玩家小队击杀敌军计热（ALLY 的战争不计入，spec §2.4）
	if killer_team == CombatUnit.TEAM_PLAYER and victim_team == CombatUnit.TEAM_HOSTILE:
		add_heat(HEAT_KILL)


func tick(delta: float) -> void:
	if sp == null or sp.mode == null or not is_instance_valid(sp.mode):
		return
	_heat_accum += delta
	if _heat_accum >= HEAT_TICK_S:
		_heat_step(_heat_accum)
		_heat_accum = 0.0
	_accum += delta
	if _accum < SurvivorData.ROE_TICK_S:
		return
	_accum = 0.0
	_run_pass()


## 热度账本 1s tick：玩家被命中检测（hp 差分）→ 衰减/地板 → 配额打点
func _heat_step(dt: float) -> void:
	var seen: Dictionary = {}
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or not (u is Aircraft) or not u.is_player_squad() or u.is_destroyed:
			continue
		var iid := u.get_instance_id()
		seen[iid] = true
		if u.hp < float(_prev_player_hp.get(iid, u.hp)):
			add_heat(HEAT_PLAYER_HIT)
		_prev_player_hp[iid] = u.hp
	for old_id in _prev_player_hp.keys():
		if not seen.has(old_id):
			_prev_player_hp.erase(old_id)

	var quiet_s: float = EventLogger.get_game_time() - _last_combat_event_s
	var level: int = sp.survivor_player.level if sp.survivor_player else 1
	var squad_size: int = maxi(1, seen.size())
	var squad_target: float = SurvivorData.SQUAD_HEAT_PER_WINGMAN * float(squad_size - 1)
	if not _squad_heat_initialized:
		# 开局既有编队直接建立正确基线；仅局中增员需要缓升。
		_squad_heat_component = squad_target
		_squad_heat_initialized = true
	elif squad_size < _last_squad_size:
		# 每损失一架直属僚机，当前热度与地板同步回落 6 点。
		heat = maxf(0.0, heat - SurvivorData.SQUAD_HEAT_PER_WINGMAN * float(_last_squad_size - squad_size))
		_squad_heat_component = squad_target
	else:
		_squad_heat_component = move_toward(
			_squad_heat_component, squad_target, SurvivorData.SQUAD_HEAT_RAMP_PER_SEC * dt)
	_last_squad_size = squad_size
	var level_floor: float = minf(75.0, float(level) * 5.0)
	var effective_floor: float = minf(
		SurvivorData.SQUAD_HEAT_MAX, level_floor + _squad_heat_component)
	heat = step_heat_with_floor(heat, quiet_s, effective_floor, dt)

	# EventLogger 打点（配额变化时一行，F9 回放调参；玩家不可见）
	var q := hunter_quota()
	if q != _last_logged_quota:
		_last_logged_quota = q
		EventLogger.log_event("ROE", "Heat",
			"heat=%.0f floor=%.0f squad=%d quota=%d quiet=%.1fs" % [
				heat, effective_floor, squad_size, q, maxf(quiet_s, 0.0)])


func _run_pass() -> void:
	var now_s: float = EventLogger.get_game_time()

	# ── 玩家小队单位表（察觉圈的"被看见方"，≤9 个）──
	var player_units: Array = []
	for u in CombatUnit.all_units:
		if is_instance_valid(u) and u is Aircraft and u.is_player_squad() and not u.is_destroyed:
			player_units.append(u)

	# ── 单遍扫描：姿态标记 + hp 差分 + 战区警报聚合 + 雷达站登记 + 中队分组 ──
	var squads: Dictionary = {}         ## key → {members, sensor, hit, zone}
	var zone_alarm: Dictionary = {}     ## zone_id → true（区内任一敌单位被伤害）
	var zone_radar_pos: Dictionary = {} ## zone_id → 存活雷达站位置（datalink）
	var seen_ids: Dictionary = {}       ## _prev_hp 修剪用

	for child in sp.mode.get_children():
		if not (child is CombatUnit) or child.team != CombatUnit.TEAM_HOSTILE:
			continue
		var cu: CombatUnit = child
		var iid := cu.get_instance_id()
		seen_ids[iid] = true
		var hp_dropped: bool = cu.hp < float(_prev_hp.get(iid, cu.hp))
		_prev_hp[iid] = cu.hp
		var zid := str(cu.get_meta("zone_mission", cu.get_meta("zone_garrison", "")))
		if zid != "" and hp_dropped:
			zone_alarm[zid] = true
		if cu is RadarStation and not cu.is_destroyed and zid != "":
			zone_radar_pos[zid] = cu.global_position
		if not (cu is Aircraft) or cu.is_destroyed:
			continue
		var ac: Aircraft = cu

		# 姿态标记 + hunt 归还（目标没了且已回巡逻 → 摘帽还池）
		var posture := _derive_posture(ac)
		var ai = sp._get_ai(ac)
		if posture == "hunt" and ai != null \
				and ai._current_target == null and ai._state == AIController.AIState.PATROL:
			ac.remove_meta(&"roe_hunt")
			posture = _derive_posture(ac)
		ac.set_meta(&"roe_posture", posture)
		if posture == "":
			continue   # 豁免类不进中队察觉体系
		if posture == "garrison" and zid != "" and _zone_lookup.has(zid):
			ac.set_meta(&"roe_zone_center", _zone_lookup[zid]["center"])
			ac.set_meta(&"roe_zone_radius_px", _zone_lookup[zid]["radius"])

		# 中队分组（solo = 自成一组；sensor = 存活长机，长机亡则退化为本机）
		var key: int = iid
		var sensor: Aircraft = ac
		if ai != null and ai.squad != null:
			key = ai.squad.get_instance_id()
			if is_instance_valid(ai.squad.leader) and not ai.squad.leader.is_destroyed:
				sensor = ai.squad.leader
		if not squads.has(key):
			squads[key] = {"members": [], "sensor": sensor, "hit": false, "zone": zid}
		var g: Dictionary = squads[key]
		g["members"].append(ac)
		if sensor != ac:
			g["sensor"] = sensor
		if hp_dropped or ac.is_locked:
			g["hit"] = true

	# _prev_hp 修剪（释放的实例不再累积）
	for old_id in _prev_hp.keys():
		if not seen_ids.has(old_id):
			_prev_hp.erase(old_id)

	# ── 逐中队：三来源察觉判定 → 刷新记忆；leash 纪律 ──
	for key in squads:
		var g: Dictionary = squads[key]
		var aware: bool = g["hit"]
		var zid2: String = g["zone"]
		if not aware and zid2 != "" and zone_alarm.get(zid2, false):
			aware = true
		var sensor2: Aircraft = g["sensor"]
		if not aware and is_instance_valid(sensor2) and not sensor2.is_destroyed:
			var r_px: float = sensor2.effective_radar_range_px() if sensor2.params else 1000.0
			var r_sq := r_px * r_px
			for pu in player_units:
				if sensor2.global_position.distance_squared_to(pu.global_position) <= r_sq:
					aware = true
					break
		if not aware and zid2 != "" and zone_radar_pos.has(zid2):
			var st_pos: Vector2 = zone_radar_pos[zid2]
			var dl_sq := SurvivorData.ROE_DATALINK_RANGE_PX * SurvivorData.ROE_DATALINK_RANGE_PX
			for pu in player_units:
				if st_pos.distance_squared_to(pu.global_position) <= dl_sq:
					aware = true
					break

		var until: float = now_s + SurvivorData.ROE_AWARE_MEMORY_S
		for m in g["members"]:
			if not is_instance_valid(m):
				continue
			if aware:
				m.set_meta(&"roe_aware_until", until)   # 只刷新不清除：记忆靠超时自然过期
			_enforce_leash(m)


## 姿态派生（读 meta，纯函数）
func _derive_posture(ac: Aircraft) -> String:
	if ac.has_meta(&"roe_hunt"):
		return "hunt"
	var cat := str(ac.get_meta("category", ""))
	if cat == "reinforcement":
		var ph := str(ac.get_meta("reinf_phase", "onstation"))
		if ph == "transit":
			return "transit"
		if ph == "egress":
			return "egress"
		return "patrol"
	if cat == "zone_air":
		return "garrison"
	return ""


## leash 纪律（§3.2）：守区目标出圈 → 停追回环；巡逻追离锚点/巡逻线超限 → 放弃返航。
## 经 release_target(TS_SCORED) 走优先级仲裁 —— hunter（TS_BOSS 持有）天然不受 leash。
func _enforce_leash(ac: Aircraft) -> void:
	var ai = sp._get_ai(ac)
	if ai == null or ai._current_target == null or not is_instance_valid(ai._current_target):
		return
	var posture := str(ac.get_meta(&"roe_posture", ""))
	var over := false
	if posture == "garrison":
		var zc: Vector2 = ac.get_meta(&"roe_zone_center", Vector2.INF)
		if zc == Vector2.INF:
			return
		var zr: float = float(ac.get_meta(&"roe_zone_radius_px", 0.0))
		over = ai._current_target.global_position.distance_to(zc) \
				> zr + SurvivorData.ROE_GARRISON_LEASH_PX
	elif posture == "patrol":
		var ring: PackedVector2Array = ac.get_meta("reinf_ring", PackedVector2Array())
		var ref_d: float
		if ring.size() == 2:
			# 线路巡逻：leash 取距线段最近点（spec §2.3）
			var cp := Geometry2D.get_closest_point_to_segment(ac.global_position, ring[0], ring[1])
			ref_d = ac.global_position.distance_to(cp)
		else:
			var anchor: Vector2 = ac.get_meta("reinf_anchor", Vector2.INF)
			if anchor == Vector2.INF:
				return
			ref_d = ac.global_position.distance_to(anchor)
		over = ref_d > SurvivorData.ROE_PATROL_LEASH_PX
	if over:
		if ai.release_target(AIController.TargetSource.TS_SCORED, "roe leash"):
			ai._state = AIController.AIState.PATROL
			ac.ai_override_pursuit = false
