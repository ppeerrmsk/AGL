class_name TheCrucibleEncounter
extends BossEncounter

## 沙漠王牌大混战决战事件。The Crucible 只是战斗主题，不是角色、中队或 BOSS；
## 本类继承 BossEncounter 仅复用现有决战阶段的注册、演出、HUD 与胜利结算生命周期。
## 全部已实装非 BOSS Ace 队依次入场，使用运行时 FFA team
## 让雷达、AI、机炮和导弹走同一套真实敌我判定，而不是播放无伤害假交火。

const PROFILE_ORDER: Array[String] = [
	"2ndwave", "gimmick", "goofighters", "whitetea", "vulture", "marathon",
	"moirai", "lash", "ido", "undertow", "croupier", "tallyman", "palimpsest",
	"quorum", "deadeye", "mirror", "funeral", "hound",
]
const OPENING_ENTRY_BEARINGS_DEG: Array[float] = [-110.0, 0.0, 110.0]
const ENTRY_ALLOWED_MIN_DEG := -135.0
const ENTRY_ALLOWED_MAX_DEG := 135.0
const ACTIVE_SQUAD_CAP := 3
const REINFORCEMENT_DELAY_S := 3.0
const ENTRY_DISTANCE_PX := 3600.0
const ENTRY_DISTANCE_MAX_PX := 6000.0
const ENTRY_DISTANCE_STEP_PX := 400.0
const ENTRY_BEARING_SEARCH_STEP_DEG := 15.0
const ENTRY_BEARING_SEARCH_STEPS := 18
const ENTRY_JOIN_RADIUS_PX := 3000.0
const OPENING_MELEE_DURATION_S := 8.0
const RETARGET_INTERVAL_S := 1.0
const REENTRY_RADIUS_PX := 3600.0
const REENTRY_RING_MIN_PX := 900.0
const REENTRY_RING_STEP_PX := 150.0
const REENTRY_RING_LAYERS := 3
const REENTRY_ARRIVAL_RADIUS_PX := 600.0
const REENTRY_DIRECTIVE_PRIORITY := 50
const WORLD_HARD_RAIL_MARGIN_PX := 80.0
const AGGRO_MAX_DISTANCE_PX := 9000.0
const VISIBLE_BATTLE_RADIUS_PX := 3600.0
const VISIBLE_BATTLE_BONUS := 3.0
const KILL_AGGRO_BONUS := 2.0
const PLAYER_HUNTERS_PER_SQUAD := 1
const BACKSTAB_MAX_RANGE_PX := 2600.0
const BACKSTAB_REAR_HALF_ANGLE_DEG := 60.0
const BACKSTAB_BONUS := 8.0
const BACKSTAB_CLAIMS_PER_TARGET := 1
const FIRST_FFA_TEAM := CombatUnit.TEAM_FREE_FOR_ALL_BASE
const CINEMATIC_SQUAD_COUNT := 3
const ENTRY_INGRESS_META := &"crucible_initial_ingress"
const REENTRY_META := &"crucible_reentry"
const REENTRY_PREV_AB_META := &"crucible_reentry_prev_ab"

var _mode: Node = null
var _player: Aircraft = null
var _spawner: SurvivorSpawner = null
var _anchor := Vector2.ZERO
var _squads: Array[AceSupportSquad] = []
var _all_members: Array[Aircraft] = []
var _spawned_profile_count := 0
var _engaged := false
var _reinforcement_elapsed_s := 0.0
var _retarget_elapsed_s := 0.0
var _opening_melee_remaining_s := 0.0


func _init() -> void:
	display_name = "THE CRUCIBLE"
	callsign_prefix = ""
	arrival_radio_enabled = false
	bgm_track = "boss_round_table"
	hud_style = &"ace_roster"


func spawn(scene_root: Node, player: Aircraft, _bullet_mgr: BulletManager,
		_missile_mgr: MissileManager, anchor: Vector2) -> void:
	_mode = scene_root
	_player = player
	_anchor = anchor if anchor != Vector2.INF else player.global_position
	var raw_spawner: Variant = scene_root.get("_spawner") if scene_root != null else null
	if typeof(raw_spawner) != TYPE_OBJECT or not is_instance_valid(raw_spawner) \
			or not (raw_spawner is SurvivorSpawner):
		push_error("TheCrucibleEncounter: survivor spawner unavailable")
		return
	_spawner = raw_spawner as SurvivorSpawner
	active = true
	# 前三队必须在 PRE_STAGE 已有真实演员，分镜依次切真实长机；此时全部禁火。
	for _i in range(CINEMATIC_SQUAD_COUNT):
		_spawn_next_squad()
	if _all_members.is_empty():
		active = false


func engage() -> void:
	if not active:
		return
	_engaged = true
	_opening_melee_remaining_s = OPENING_MELEE_DURATION_S
	# 开场分镜的三队就是首批真实战斗队；不再按绝对时间继续堆人。
	for squad in _squads:
		_activate_squad(squad)
	# 首轮只让 Ace 队际互打；玩家仍可主动介入，但不会当帧被十四架集火。
	_retarget_all(false)


func update(delta: float) -> void:
	if not active:
		return
	for squad in _squads:
		if squad != null and squad.active:
			# combat_phase_active=false：只消费基类的死亡清理，不让 AceSquad 的
			# “全员追玩家”软维护覆盖本 Boss 的自由混战目标。
			squad.update(delta)
			squad.update_theme(delta, false)
	if not _engaged:
		return
	var opening_melee_ended := false
	if _opening_melee_remaining_s > 0.0:
		_opening_melee_remaining_s = maxf(0.0, _opening_melee_remaining_s - delta)
		if _opening_melee_remaining_s <= 0.0:
			opening_melee_ended = true
			EventLogger.log_event("EVENT", display_name,
				"opening melee complete; player hunters enabled")

	# 淘汰接力：只有活跃队伍少于三支才开始计时，每 3s 最多补一队。
	if _spawned_profile_count < PROFILE_ORDER.size() \
			and _active_squad_count() < ACTIVE_SQUAD_CAP:
		_reinforcement_elapsed_s += delta
		if _reinforcement_elapsed_s >= REINFORCEMENT_DELAY_S:
			_reinforcement_elapsed_s = 0.0
			var squad_count_before := _squads.size()
			_spawn_next_squad()
			if _squads.size() > squad_count_before:
				_activate_squad(_squads.back())
	else:
		_reinforcement_elapsed_s = 0.0

	if opening_melee_ended:
		_retarget_elapsed_s = 0.0
		_retarget_all(true)
	else:
		_retarget_elapsed_s += delta
	if not opening_melee_ended and _retarget_elapsed_s >= RETARGET_INTERVAL_S:
		_retarget_elapsed_s = fmod(_retarget_elapsed_s, RETARGET_INTERVAL_S)
		_retarget_all(not is_opening_melee_active())

	if _spawned_profile_count >= PROFILE_ORDER.size() and _live_members().is_empty():
		_cleanup_targets()
		active = false
		EventLogger.log_event("EVENT", display_name, "all ace squadrons eliminated")


func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	_player = p
	for squad in _squads:
		if squad != null:
			squad.set_player_ref(p)


func get_display_members() -> Array:
	return _all_members


func get_hud_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in range(_squads.size()):
		var profile_id := PROFILE_ORDER[i]
		var members: Array[Dictionary] = []
		for ac in _squads[i].all_members:
			if not is_instance_valid(ac) or ac.is_destroyed or ac.is_queued_for_deletion() \
					or not bool(ac.get_meta("crucible_active", false)):
				continue
			members.append({
				"callsign": ac.callsign,
				"hp": ac.hp,
				"max_hp": ac.params.max_hp if ac.params else 75.0,
				"kills": ac.kill_tally,
			})
		# 未入场与全灭中队都不占 HUD 槽；单机阵亡则只移除对应分段。
		if members.is_empty():
			continue
		entries.append({
			"ace_roster": true,
			"id": profile_id,
			"name": AceSquadProfiles.codename(profile_id),
			"color": AceSquadProfiles.color(profile_id),
			"members": members,
		})
	return entries


static func aggro_score(distance_px: float, candidate_kills: int) -> float:
	var distance01 := clampf(1.0 - maxf(distance_px, 0.0) / AGGRO_MAX_DISTANCE_PX, 0.0, 1.0)
	return 1.0 + distance01 + float(maxi(candidate_kills, 0)) * KILL_AGGRO_BONUS


static func rear_attack_opportunity_score(shooter_position: Vector2,
		candidate_position: Vector2, candidate_heading: float,
		candidate_is_pressuring_player: bool) -> float:
	if not candidate_is_pressuring_player:
		return 0.0
	var candidate_to_shooter := shooter_position - candidate_position
	var distance_px := candidate_to_shooter.length()
	if distance_px <= 0.01 or distance_px > BACKSTAB_MAX_RANGE_PX:
		return 0.0
	var forward := Vector2(sin(candidate_heading), -cos(candidate_heading))
	var rear_alignment := -forward.dot(candidate_to_shooter / distance_px)
	var rear_threshold := cos(deg_to_rad(BACKSTAB_REAR_HALF_ANGLE_DEG))
	if rear_alignment < rear_threshold:
		return 0.0
	var range01 := 1.0 - distance_px / BACKSTAB_MAX_RANGE_PX
	var angle01 := inverse_lerp(rear_threshold, 1.0, rear_alignment)
	return BACKSTAB_BONUS * (0.65 + 0.20 * range01 + 0.15 * angle01)


## 出生方位只相对玩家机头定义。首发三队先占左右翼与正前；后续槽位铺满
## 前方 270° 可用环带，硬性排除正后方 ±45°。
static func entry_relative_bearing_deg_for(profile_index: int) -> float:
	var index := clampi(profile_index, 0, PROFILE_ORDER.size() - 1)
	if index < OPENING_ENTRY_BEARINGS_DEG.size():
		return OPENING_ENTRY_BEARINGS_DEG[index]
	var later_count := PROFILE_ORDER.size() - OPENING_ENTRY_BEARINGS_DEG.size()
	var later_slot := index - OPENING_ENTRY_BEARINGS_DEG.size()
	var t := float(later_slot) / float(maxi(later_count - 1, 1))
	return lerpf(ENTRY_ALLOWED_MIN_DEG, ENTRY_ALLOWED_MAX_DEG, t)


static func entry_position_for(center: Vector2, player_heading: float,
		profile_index: int) -> Vector2:
	var bearing := player_heading + deg_to_rad(entry_relative_bearing_deg_for(profile_index))
	return center + Vector2(sin(bearing), -cos(bearing)) * ENTRY_DISTANCE_PX


## 优先保持 profile 的设计方位，再沿同一方位把出生环向外推；若地图边缘不允许，
## 才以 15° 步进搜索相邻可用方位。正式出生位必须让整个编队（不只是长机）
## 同时位于安全边界内且不在当前镜头内。
func _entry_spawn_position_for(center: Vector2, player_heading: float,
		profile_index: int, squad: AceSupportSquad = null) -> Vector2:
	var preferred_relative := entry_relative_bearing_deg_for(profile_index)
	var bearing_offsets: Array[float] = [0.0]
	for step in range(1, ENTRY_BEARING_SEARCH_STEPS + 1):
		bearing_offsets.append(-float(step) * ENTRY_BEARING_SEARCH_STEP_DEG)
		bearing_offsets.append(float(step) * ENTRY_BEARING_SEARCH_STEP_DEG)
	var first_safe := Vector2.INF
	var distance_steps := roundi((ENTRY_DISTANCE_MAX_PX - ENTRY_DISTANCE_PX) \
		/ ENTRY_DISTANCE_STEP_PX)
	for bearing_offset in bearing_offsets:
		var relative_bearing := preferred_relative + bearing_offset
		if relative_bearing < ENTRY_ALLOWED_MIN_DEG \
				or relative_bearing > ENTRY_ALLOWED_MAX_DEG:
			continue
		var bearing := player_heading + deg_to_rad(relative_bearing)
		var direction := Vector2(sin(bearing), -cos(bearing))
		for distance_step in range(distance_steps + 1):
			var distance_px := ENTRY_DISTANCE_PX \
				+ float(distance_step) * ENTRY_DISTANCE_STEP_PX
			var candidate := center + direction * distance_px
			var lateral_axis := direction.rotated(PI / 2.0)
			var formation_offsets: Array[Vector2] = [Vector2.ZERO] \
				if squad == null else squad._get_formation_offsets(direction, lateral_axis)
			var formation_safe := true
			var formation_offscreen := true
			for offset in formation_offsets:
				var member_pos := candidate + offset
				if not MapBoundary.is_safe_inside(member_pos, 1200.0):
					formation_safe = false
					break
				if _mode != null and _mode.has_method("is_world_pos_visible") \
						and bool(_mode.call("is_world_pos_visible", member_pos)):
					formation_offscreen = false
			if not formation_safe:
				continue
			if first_safe == Vector2.INF:
				first_safe = candidate
			if formation_offscreen:
				return candidate
	if first_safe != Vector2.INF:
		push_error("TheCrucibleEncounter: safe entry candidates are all inside the current camera")
	else:
		push_error("TheCrucibleEncounter: no safe entry candidate inside the map")
	return Vector2.INF


func is_opening_melee_active() -> bool:
	return _engaged and _opening_melee_remaining_s > 0.0


func _spawn_next_squad() -> void:
	if _spawned_profile_count >= PROFILE_ORDER.size() or _spawner == null:
		return
	var index := _spawned_profile_count
	var profile_id := PROFILE_ORDER[index]
	var squad := AceSupportSquad.new(profile_id)
	var combat_center := _current_combat_center()
	squad.entry_origin_override = _entry_spawn_position_for(
		combat_center, _player.heading, index, squad)
	if squad.entry_origin_override == Vector2.INF:
		return
	squad.anchor_position = combat_center
	squad.spawn(_mode, _spawner._aircraft_scene, Callable(_spawner, "_create_enemy"),
		_player, _spawner.bullet_manager, _spawner.missile_manager, _spawner._squads)
	if not squad.active or squad.members.is_empty():
		push_error("TheCrucibleEncounter: failed to spawn profile '%s'" % profile_id)
		active = false
		return

	var faction_team := FIRST_FFA_TEAM + index
	var is_hound := profile_id == "hound"
	for ac in squad.all_members:
		if not is_instance_valid(ac):
			continue
		ac.team = faction_team
		ac.set_meta("crucible_profile", profile_id)
		ac.set_meta("crucible_active", false)
		# 镜头外远端生成后先自然压入战区；未进 3000px 前不得被 3600px 脱战回收反向接管。
		ac.set_meta(ENTRY_INGRESS_META, true)
		# 玩家猎手由 encounter 按“每支活跃队一名”集中续任；生成时不得预置全队追玩家。
		ac.set_meta("crucible_player_hunter", false)
		ac.set_meta("crucible_high_lod", true)
		# 高细节绘制保持 LOD0；常规 71 架完整战术/武器更新稳定错分到四帧，位移仍 60Hz；
		# Boss 级 Hound 双机保持完整频率。
		ac.set_meta(&"dense_battle_sim_divisor", 1 if is_hound else 4)
		ac.set_meta(&"dense_battle_sim_phase", 0 if is_hound else _all_members.size() % 4)
		ac.set_meta("skip_far_cleanup", true)
		ac.set_meta("no_kill_reward", true)
		ac.set_meta(CombatUnit.META_FACTION_CONVERSION_LOCKED, true)
		# KNIGHT/SNIPER 角色 meta 在常规 Ace 事件中等价于“BOSS 攻击手”，会屏蔽
		# 规避并强追玩家。Crucible 保留生成期写入的机体/AI 参数，但撤掉该目标语义。
		ac.remove_meta(AceSquad.ROLE_META)
		ac.lod_level = 0
		var ai := ac._get_ai_controller()
		if ai:
			ai.ai_tick_divisor = 1 if is_hound else 3
			ai._tick_phase = 0 if is_hound else _all_members.size() % 3
			if is_hound:
				ai._scaling_class_cached = AIController.AIScaleClass.IMMUNE
		_all_members.append(ac)
	# 禁止原 AceSquad 状态机把目标补回玩家；本 encounter 集中拥有目标重算。
	squad.combat_phase_active = false
	_squads.append(squad)
	_spawned_profile_count += 1
	EventLogger.log_event("EVENT", display_name,
		"wave %d/%d %s x%d team=%d" % [index + 1, PROFILE_ORDER.size(),
			AceSquadProfiles.codename(profile_id), squad.members.size(), faction_team])


func _activate_squad(squad: AceSupportSquad) -> void:
	if squad == null:
		return
	for ac in squad.members:
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		var ai := ac._get_ai_controller()
		if ai:
			# 远端 Ace 生成流程可能留有玩家目标；激活前由 Boss 级所有者显式清空，
			# 保证开局混战窗从第一帧起就没有玩家目标。
			ai.release_target(AIController.TargetSource.TS_BOSS, "crucible activation")
			ai.enable_combat = true
			ai.boss_attacker = false
			ai.enter_patrol_state(false)
		ac.set_meta("crucible_active", true)


func _retarget_all(include_player: bool = true) -> void:
	var shooters: Array[Aircraft] = []
	for shooter in _live_engaged_members():
		if not _force_reentry_if_strayed(shooter):
			shooters.append(shooter)
	if shooters.is_empty():
		return
	_assign_player_hunters(shooters)
	var candidates := _target_candidates(include_player)
	if candidates.is_empty():
		return
	# 第一阶段先兑现“始终有人压玩家”。这样第二阶段能真实识别哪些 Ace 正在缠斗玩家。
	if include_player:
		for shooter in shooters:
			if bool(shooter.get_meta("crucible_player_hunter", false)):
				_try_acquire_player(shooter)
	var backstab_claims: Dictionary = {}
	# 第二阶段只处理混战位；玩家从它们的候选中彻底排除。
	for shooter in shooters:
		if include_player and bool(shooter.get_meta("crucible_player_hunter", false)):
			continue
		var best: CombatUnit = null
		var best_score := -INF
		var best_backstab_id := 0
		for candidate in candidates:
			if candidate == shooter or candidate.team == shooter.team \
					or candidate.is_player_squad() or not shooter.is_hostile_to(candidate) \
					or candidate.is_lock_immune():
				continue
			var kills: int = candidate.kill_tally if candidate is Aircraft \
					and candidate.has_meta("crucible_profile") else 0
			var score := aggro_score(
				shooter.global_position.distance_to(candidate.global_position), kills)
			if is_instance_valid(_player):
				score += visible_battle_score(
					candidate.global_position.distance_to(_player.global_position))
			var backstab_score := 0.0
			var candidate_id := candidate.get_instance_id()
			if candidate is Aircraft and int(backstab_claims.get(candidate_id, 0)) \
					< BACKSTAB_CLAIMS_PER_TARGET:
				backstab_score = rear_attack_opportunity_score(
					shooter.global_position, candidate.global_position, candidate.heading,
					_is_pressuring_player(candidate as Aircraft))
				score += backstab_score
			# 稳定微扰把同分候选摊开，不使用每秒随机数制造目标抖动。
			score += float((shooter.get_instance_id() + candidate.get_instance_id()) % 17) * 0.0001
			if score > best_score:
				best_score = score
				best = candidate
				best_backstab_id = candidate_id if backstab_score > 0.0 else 0
		if best == null:
			continue
		if _acquire_target(shooter, best, "crucible aggro") and best_backstab_id != 0:
			backstab_claims[best_backstab_id] = int(
				backstab_claims.get(best_backstab_id, 0)) + 1


func _assign_player_hunters(ready_members: Array[Aircraft]) -> void:
	for squad in _squads:
		if squad == null:
			continue
		var eligible: Array[Aircraft] = []
		var incumbent: Aircraft = null
		for ac in squad.members:
			if not is_instance_valid(ac):
				continue
			if squad.active and not ac.is_destroyed and ready_members.has(ac):
				eligible.append(ac)
			if not ac.is_destroyed and ready_members.has(ac) \
					and bool(ac.get_meta("crucible_player_hunter", false)):
				incumbent = ac
		for ac in squad.all_members:
			if is_instance_valid(ac):
				ac.set_meta("crucible_player_hunter", false)
		if eligible.is_empty():
			continue
		# Hound-2 是近身追杀者；其它队首次由离玩家最近者承担缠斗，阵亡前不抖动换手。
		var hunter := incumbent
		if hunter == null and squad.profile_id == "hound":
			hunter = eligible.back()
		if hunter == null:
			hunter = eligible[0]
			if is_instance_valid(_player):
				for candidate in eligible:
					if candidate.global_position.distance_squared_to(_player.global_position) \
							< hunter.global_position.distance_squared_to(_player.global_position):
						hunter = candidate
		hunter.set_meta("crucible_player_hunter", true)


func _try_acquire_player(shooter: Aircraft) -> bool:
	if not is_instance_valid(_player) or _player.is_destroyed or _player.is_lock_immune() \
			or not shooter.is_hostile_to(_player):
		return false
	return _acquire_target(shooter, _player, "crucible player pressure")


func _acquire_target(shooter: Aircraft, target: CombatUnit, reason: String) -> bool:
	var ai := shooter._get_ai_controller()
	if ai == null or not ai.acquire_target(target, AIController.TargetSource.TS_BOSS, reason):
		return false
	ai.enable_combat = true
	ai.enter_engage_state()
	shooter.ai_override_pursuit = true
	return true


func _is_pressuring_player(candidate: Aircraft) -> bool:
	var ai := candidate._get_ai_controller()
	if ai == null:
		return false
	var target: Variant = ai.get("_current_target")
	return typeof(target) == TYPE_OBJECT and target != null and is_instance_valid(target) \
		and target is CombatUnit and (target as CombatUnit).is_player_squad()


func _force_reentry_if_strayed(shooter: Aircraft) -> bool:
	if not is_instance_valid(_player) or _player.is_destroyed:
		return false
	# ace_support 在通用 spawner 中会跳过边界收容；本 encounter 必须自己守住硬边界。
	if not MapBoundary.is_safe_inside(shooter.global_position, WORLD_HARD_RAIL_MARGIN_PX):
		shooter.global_position = MapBoundary.clamp_inside(
			shooter.global_position, WORLD_HARD_RAIL_MARGIN_PX)
		shooter.clear_trail()
	var player_distance_sq := shooter.global_position.distance_squared_to(_player.global_position)
	if bool(shooter.get_meta(ENTRY_INGRESS_META, false)):
		if player_distance_sq <= ENTRY_JOIN_RADIUS_PX * ENTRY_JOIN_RADIUS_PX:
			shooter.remove_meta(ENTRY_INGRESS_META)
		else:
			return false
	var ai := shooter._get_ai_controller()
	if ai == null:
		return false
	if bool(shooter.get_meta(REENTRY_META, false)):
		var current: Variant = ai._directive
		if typeof(current) == TYPE_OBJECT and current != null and is_instance_valid(current) \
				and current is AIDirective \
				and bool((current as AIDirective).params.get("crucible_reentry", false)):
			return true
		# 指令被外部覆盖时允许本 tick 重新建立，不能永远卡在返场 meta。
		shooter.remove_meta(REENTRY_META)
		shooter.remove_meta(REENTRY_PREV_AB_META)
	if player_distance_sq <= REENTRY_RADIUS_PX * REENTRY_RADIUS_PX:
		return false
	var roster_slot := maxi(_all_members.find(shooter), 0)
	var target := reentry_target_for(_player.global_position, roster_slot)
	var directive := AIDirective.fly_to(target, AIDirective.OnArrival.CALLBACK,
		REENTRY_ARRIVAL_RADIUS_PX)
	directive.priority = REENTRY_DIRECTIVE_PRIORITY
	directive.owner_event = weakref(self)
	directive.params["crucible_reentry"] = true
	# 返场首先是 180° 空间恢复：角点速度提供最大转弯率；若压最大速度并开加力，
	# 2000+km/h 的回转半径会让飞机继续向外飞，反而无法满足 20s 回场契约。
	directive.params["target_speed"] = AircraftPhysics.effective_corner_speed_kmh(shooter)
	directive.params["afterburner"] = false
	directive.params["speed_cap_kmh"] = AircraftPhysics.effective_corner_speed_kmh(shooter)
	directive.on_complete = Callable(self, "_complete_reentry").bind(shooter.get_instance_id())
	# Ace 僚机可能仍在 formation_mode 的 LOD1 托管分支；该分支会在完整物理转向前
	# early-return，形成“返场航点已写入但 bank 永远为 0”的假接管。空间恢复期间必须
	# 暂时脱离编队，抵达后由正常目标重算重新进入 ENGAGE。
	shooter.clear_formation()
	shooter.set_meta(REENTRY_META, true)
	shooter.set_meta(REENTRY_PREV_AB_META, shooter.is_afterburner)
	shooter.clear_combat_target()
	shooter.withdraw_intent(ControlIntent.SOURCE_TACTIC)
	shooter.ai_override_pursuit = true
	ai.set_event_directive(directive)
	return true


static func reentry_target_for(center: Vector2, roster_slot: int) -> Vector2:
	# 黄金角让 73 个固定槽均匀铺开；三层半径避免大量飞机汇聚到同一圆周点。
	var slot := maxi(roster_slot, 0)
	var angle := fmod(float(slot) * 2.399963229728653, TAU)
	var radius := REENTRY_RING_MIN_PX \
		+ float(posmod(slot, REENTRY_RING_LAYERS)) * REENTRY_RING_STEP_PX
	return center + Vector2(cos(angle), sin(angle)) * radius


func _complete_reentry(ai_raw: Variant, aircraft_id: int) -> void:
	if typeof(ai_raw) == TYPE_OBJECT and ai_raw != null and is_instance_valid(ai_raw) \
			and ai_raw is AIController:
		(ai_raw as AIController).set_event_directive(null)
	for ac in _all_members:
		if not is_instance_valid(ac) or ac.get_instance_id() != aircraft_id:
			continue
		var previous_afterburner := bool(ac.get_meta(REENTRY_PREV_AB_META, false))
		ac.remove_meta(REENTRY_META)
		ac.remove_meta(REENTRY_PREV_AB_META)
		ac.ai_override_pursuit = false
		ac.reset_tactical_plan_state()
		# 返场强制加力不应泄漏到恢复后的 FFA；清本次切换冷却后恢复进入前状态。
		ac._ab_cooldown = 0.0
		AircraftPhysics.set_afterburner(ac, previous_afterburner)
		break


func _active_squad_count() -> int:
	var count := 0
	for squad in _squads:
		if squad != null and squad.active and not squad.members.is_empty():
			count += 1
	return count


static func visible_battle_score(candidate_distance_to_player_px: float) -> float:
	var center01 := clampf(1.0 - maxf(candidate_distance_to_player_px, 0.0) \
		/ VISIBLE_BATTLE_RADIUS_PX, 0.0, 1.0)
	return center01 * VISIBLE_BATTLE_BONUS


func _current_combat_center() -> Vector2:
	if is_instance_valid(_player) and not _player.is_destroyed:
		return _player.global_position
	return _anchor


func _target_candidates(include_player: bool = true) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit is Aircraft and ((include_player and unit.is_player_squad()) \
				or (unit.has_meta("crucible_profile") and bool(unit.get_meta("crucible_active", false)))):
			out.append(unit)
	return out


func _live_engaged_members() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for ac in _all_members:
		if is_instance_valid(ac) and not ac.is_destroyed and not ac.is_queued_for_deletion() \
				and bool(ac.get_meta("crucible_active", false)):
			out.append(ac)
	return out


func _live_members() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for ac in _all_members:
		if is_instance_valid(ac) and not ac.is_destroyed and not ac.is_queued_for_deletion():
			out.append(ac)
	return out


func _cleanup_targets() -> void:
	for ac in _all_members:
		if is_instance_valid(ac):
			var ai := ac._get_ai_controller()
			if ai != null and bool(ac.get_meta(REENTRY_META, false)):
				ai.set_event_directive(null)
			ac.remove_meta(REENTRY_META)
			ac.remove_meta(REENTRY_PREV_AB_META)
			ac.remove_meta(ENTRY_INGRESS_META)
			CombatUnit.release_target_refs(ac)
