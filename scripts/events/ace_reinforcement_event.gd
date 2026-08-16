## 王牌支援中队事件（spec events/ace-support-squadron）
##
## 生命周期：
##   _start   玩家 heading 前方扇区边缘生成 AceSupportSquad（Su-35 ×5）→ 立即 engage()
##            （PURSUIT 全员锁玩家、直奔而来，无锚点待机相）→ 长机 ace_spawn 无线电
##            + 次级提示条（红色警告横幅是 BOSS 专属，tier spec §2.6）
##   _update  监护：全灭 → grant_time_extension(60) + 歼灭通报 → end；
##            BOSS 解锁 → 转撤离（直飞最近边界；被伤害立即回头应战，脱离接触后再撤；
##            撤离中被全灭：XP 照给、无时间奖励 —— game_time 已冻结无意义）
##   已购 support_ace_f15：入场同步派 2 架只对空 ALLY F-15；王牌事件终态后物理撤离
##   _finish  静态注册表清引用；managed_units 交 director 兜底回收
##
## 调度（survivor_mode._update_ace_support_event）：六队 game_time≥240s 同窗洗牌；前支结束后
## ≥150s 再触发；game_time≥540s 不新刷；同场 ≤1 支；BOSS 阶段不触发。
class_name AceReinforcementEvent
extends GameEvent

const TIME_EXTENSION_S := 60.0          ## 全灭奖励：整局延长 1 分钟（spec §2.5）
const WITHDRAW_REENGAGE_S := 5.0        ## 撤离被打断 → 回头应战的最短时长
const WITHDRAW_FREE_OUTSET_PX := 800.0  ## 出界此距离即静默释放（同 EGRESS 语义）
const ALLY_SUPPORT_COUNT := 2            ## 已购王牌截击支援固定两架 F-15
const ALLY_SUPPORT_SEPARATION_PX := 180.0
const FactionTransitionScript = preload("res://scripts/events/faction_transition.gd")

## Tab 战术图标记 / HUD 血条共用的静态注册表。
## GameEvent 是 RefCounted，静态强引用会让事件跨场景存活，因此新局/退局必须显式 reset。
static var _active_ref: AceReinforcementEvent = null


## 清除只属于当前一局的注册状态；由 SurvivorMode 在开局与退局两端兜底调用。
static func reset_runtime_state() -> void:
	_active_ref = null

## 编成 profile（spec ace-squadron-tier §2.7；调度器按时段档轮换注入）
var profile_id := "marathon"
var debug_force_battle_bar := false ## Debug 只绕过 HUD 显示门；不改 _battle_joined / TTK 计时

var _squad: AceSupportSquad = null
var _withdrawing := false
var _reengage_timer := 0.0   ## >0 = 撤离被打断、正在回头应战
var _hp_watch := -1.0        ## 撤离期 HP 总和快照（掉血 = 被伤害 → 应战）
var _escaped := 0            ## 撤离出界释放数（>0 = 非全灭，不入"击破"档案）
var _battle_joined := false  ## 交战血条已亮（tier §2.8：首次开火/受击触发，入场不亮）
var _withdraw_reason := ""   ## "boss unlocked" / "ammo dry"（骑士弹尽）
var _encounter_elapsed_s := 0.0 ## 从生成起的在场时长（诊断入场/接敌开销）
var _combat_elapsed_s := 0.0    ## 从首次开火/受击到终态的实际击破计时
var _balance_terminal_logged := false
var _ace_terminal_handled := false
var _whitetea_previous_hostile_count := 0
var _whitetea_surrendered := false
var _surrendered_aircraft: Aircraft = null
var _ally_support: Array[Aircraft] = []
var _ally_support_egressing := false
var _ally_support_reengage_s := 0.0
var _ally_support_hp_watch := 0.0

## Tab 标记：存活支援中队的头号存活机（无则 null）
static func active_leader() -> Aircraft:
	if _active_ref == null or _active_ref._squad == null or not _active_ref._squad.active:
		return null
	for m in _active_ref._squad.members:
		if is_instance_valid(m) and not m.is_destroyed:
			return m
	return null

## Tab 标记：在场中队代号 / 主色（无在场中队时的返回值不会被消费）
static func active_codename() -> String:
	if _active_ref == null:
		return ""
	return AceSquadProfiles.codename(_active_ref.profile_id)

static func active_color() -> Color:
	if _active_ref == null:
		return Color(1.0, 0.3, 0.3)
	return AceSquadProfiles.color(_active_ref.profile_id)

## HUD 交战血条数据源（tier §2.8 分段命条）。正式事件未交战时隐藏；Debug 可只强制呈现。
## alive 数组按 squad 槽位序（下标 0 = 长机段，HUD 画三角标记）
static func battle_bar_info() -> Dictionary:
	if _active_ref == null or _active_ref._squad == null or not _active_ref._squad.active:
		return {}
	if not _active_ref._battle_joined and not _active_ref.debug_force_battle_bar:
		return {}
	var segs: Array = []
	for m in _active_ref._squad.all_members:
		segs.append(is_instance_valid(m) and not m.is_destroyed)
	return {
		"id": _active_ref.profile_id,
		"codename": AceSquadProfiles.codename(_active_ref.profile_id),
		"color": AceSquadProfiles.color(_active_ref.profile_id),
		"alive": segs,
	}

func _start() -> void:
	super._start()
	name = "ace_support"
	var sp = director.spawner
	var player: Aircraft = director.player
	if sp == null or player == null or not is_instance_valid(player) or player.is_destroyed:
		end()
		return
	_squad = AceSupportSquad.new(profile_id)
	# 入场：玩家 heading 前方 ±90° 扇区边缘点（距玩家 ≥5000px，复用 ingress 选点算法；
	# 不从身后出兵 —— 玩家在 Tab 图上看得见一队金橙点直奔自己）
	_squad.entry_origin_override = sp._ingress_spawn_point(player.global_position, true)
	_squad.anchor_position = player.global_position
	_squad.spawn(director.mode, sp._aircraft_scene, Callable(sp, "_create_enemy"),
		player, sp.bullet_manager, sp.missile_manager, sp._squads)
	if not _squad.active or _squad.members.is_empty():
		end()
		return
	for m in _squad.members:
		managed_units.append(m)
	_whitetea_previous_hostile_count = _live_ace_members().size()
	_squad.engage()   # 立即 PURSUIT：无 PRE_STAGE 待机（spec §2.6 进场即咬）
	_spawn_ally_support(sp, player)
	_active_ref = self
	# 入场演出（tier spec §2.6）：红色警告横幅是 BOSS 专属 —— 王牌中队的入场主信号
	# 是长机无线电（ace_spawn，scripted 必定播出）+ 次级提示条
	var radio = director.mode.get("_radio") if director.mode else null
	if radio:
		radio.say_unit("ace_spawn", _squad.members[0])
	var hint = _hint()
	if hint:
		# 精英中队属于顶部紧急通道：滑入后常驻，直到该次遭遇终止。
		hint.show_persistent(
			tr("EVENT_ACE_INBOUND_FMT") % AceSquadProfiles.codename(profile_id))
	# 生涯档案：遭遇记一笔（bench / boss debug 局由 archive_enabled 挡）
	if director.mode and director.mode.has_method("archive_enabled") \
			and director.mode.archive_enabled():
		CareerArchive.record_ace_encounter(profile_id)
	EventLogger.log_event("EVENT", "AceSupport",
		"%s inbound x%d from %s | balance %.0f DU, estimated TTK %.0fs (target %.0f-%.0fs)" % [
			AceSquadProfiles.codename(profile_id), _squad.members.size(),
			_squad.entry_origin_override.round(), AceSquadProfiles.defeat_units(profile_id),
			AceSquadProfiles.estimated_ttk_s(profile_id), AceSquadProfiles.TTK_TARGET_MIN_S,
			AceSquadProfiles.TTK_TARGET_MAX_S])

func _update(delta: float) -> void:
	_encounter_elapsed_s += delta
	if _battle_joined:
		_combat_elapsed_s += delta
	if _squad == null:
		end()
		return
	_squad.update(delta)
	_try_whitetea_surrender()
	if not _ally_support_egressing:
		_maintain_ally_support_targets()
	# 交战血条触发（tier §2.8）：入场不亮，打起来才亮；撤离中不新亮
	if not _battle_joined and not _withdrawing:
		_battle_joined = _detect_battle_joined()
		if _battle_joined:
			_combat_elapsed_s = 0.0
			EventLogger.log_event("BALANCE", "AceTTK",
				"%s combat start | estimated=%.1fs" % [AceSquadProfiles.codename(profile_id),
					AceSquadProfiles.estimated_ttk_s(profile_id)])
	# 全灭 / 撤离释放完毕（active 由 AceSquad.update 的存活过滤翻 false）
	if not _squad.active:
		if not _ace_terminal_handled:
			_handle_ace_terminal()
		var terminal_ready := true
		if _whitetea_surrendered and not _tick_surrender_egress():
			terminal_ready = false
		if _ally_support_egressing and not _tick_ally_support_egress(delta):
			terminal_ready = false
		if terminal_ready:
			end()
		return
	# BOSS 解锁 → 让位撤离（spec §3.1 WITHDRAWING：BOSS 独享舞台）
	if not _withdrawing and director.mode and director.mode._is_in_boss_phase():
		_begin_withdraw("boss unlocked")
	# 骑士弹尽 → 打完就走（spec ace-lancer-mig31 §2.3；玩家没抓住窗口 = 无时间奖励）
	if not _withdrawing and _squad.is_ammo_dry():
		_begin_withdraw("ammo dry")
	if _withdrawing:
		_tick_withdraw(delta)

## 已购生涯权益：敌军王牌成功入场后，从另一侧边界外派两架只对空 F-15。
func _spawn_ally_support(sp, player: Aircraft) -> void:
	var formal_run := false
	if director.mode and director.mode.has_method("archive_enabled"):
		formal_run = bool(director.mode.archive_enabled())
	if not MetaShop.is_ace_f15_support_entitled(formal_run):
		return
	var spawn_origin: Vector2 = sp._ingress_spawn_point(player.global_position, false)
	# 两队若抽到同一边，友机直接叠在王牌脸上会把“截击线”演成出生互殴；改从对侧入场。
	if spawn_origin.distance_to(_squad.entry_origin_override) < 2000.0:
		spawn_origin = -_squad.entry_origin_override
	var to_battle := (player.global_position - spawn_origin).normalized()
	var heading_rad := atan2(to_battle.x, -to_battle.y)
	var heading_deg := rad_to_deg(heading_rad)
	var sq := SquadFactory.create()
	for i in range(ALLY_SUPPORT_COUNT):
		var lateral := Vector2(cos(heading_rad), sin(heading_rad)) \
				* (float(i) - 0.5) * ALLY_SUPPORT_SEPARATION_PX
		var ac: Aircraft = sp._create_enemy(sp.EnemyType.F15, spawn_origin + lateral, heading_deg)
		if ac == null:
			continue
		AllyForce.convert_aircraft(ac)
		ac.callsign = "ALLY-%s" % ac.callsign
		ac.set_meta("ace_intercept_support", true)
		ac.set_meta("air_targets_only", true)
		if _ally_support.is_empty():
			SquadFactory.register_leader(sq, ac)
		else:
			SquadFactory.register_wingman(sq, ac, true)
		var ai: AIController = ac._get_ai_controller()
		if ai:
			ai.enable_combat = true
		_ally_support.append(ac)
		managed_units.append(ac)
	_ally_support_hp_watch = _ally_support_hp()
	_maintain_ally_support_targets()
	if not _ally_support.is_empty():
		EventLogger.log_event("EVENT", "AceInterceptSupport",
			"F-15 x%d inbound from %s vs %s" % [_ally_support.size(), spawn_origin.round(),
			AceSquadProfiles.codename(profile_id)])

func _live_ace_members() -> Array[Aircraft]:
	var live: Array[Aircraft] = []
	if _squad == null:
		return live
	for m in _squad.members:
		if is_instance_valid(m) and not m.is_destroyed and m.team == CombatUnit.TEAM_HOSTILE:
			live.append(m)
	return live

static func should_whitetea_surrender(profile: String, previous_hostiles: int,
		current_hostiles: int, withdrawing: bool, boss_phase: bool) -> bool:
	return profile == "whitetea" and previous_hostiles == 2 and current_hostiles == 1 \
		and not withdrawing and not boss_phase

## WhiteTea 专属 2→1 仲裁：转换成功当帧即关闭敌王牌事件，幸存者本人喊话后被动离场。
func _try_whitetea_surrender() -> void:
	if profile_id != "whitetea" or _whitetea_surrendered or _withdrawing or not _squad.active:
		return
	if director.mode and director.mode._is_in_boss_phase():
		return
	var live := _live_ace_members()
	var current_count := live.size()
	if should_whitetea_surrender(profile_id, _whitetea_previous_hostile_count,
		current_count, _withdrawing, false):
		var survivor: Aircraft = live[0]
		if FactionTransitionScript.convert(survivor, CombatUnit.TEAM_ALLY, "whitetea_surrender"):
			_whitetea_surrendered = true
			_surrendered_aircraft = survivor
			survivor.set_meta("xp_granted", true)
			_squad.members.erase(survivor)
			_squad.active = false
			_command_surrender_exit(survivor)
			if director.spawner and director.spawner.has_method("grant_ace_neutralization_xp"):
				director.spawner.grant_ace_neutralization_xp()
			var radio = director.mode.get("_radio") if director.mode else null
			if radio:
				radio.say_text("whitetea_surrender", survivor.callsign,
					GameConstants.COL_ENEMY_ELITE, tr("RADIO_WHITETEA_SURRENDER_1"))
			EventLogger.log_event("EVENT", "AceSupport",
				"%s surrendered and egressing" % survivor.callsign)
	_whitetea_previous_hostile_count = current_count

func _command_surrender_exit(ac: Aircraft) -> void:
	var ai: AIController = ac._get_ai_controller()
	if ai:
		ai.enable_combat = false
		ai.release_target(ai.get_target_source(), "whitetea surrender")
		ai.enter_patrol_state(false)
		ai.waypoints = PackedVector2Array([_exit_point(ac.global_position)])
		ai.current_waypoint_index = 0
	ac.clear_combat_target()
	ac.clear_formation()
	ac.is_afterburner = true
	if ac.params:
		ac.target_speed_kmh = ac.params.max_speed

func _tick_surrender_egress() -> bool:
	var ac := _surrendered_aircraft
	if ac == null or not is_instance_valid(ac) or ac.is_destroyed or ac.is_queued_for_deletion():
		return true
	if MapBoundary.distance_to_edge(ac.global_position) <= -WITHDRAW_FREE_OUTSET_PX:
		CombatUnit.release_target_refs(ac)
		ac.queue_free()
		return true
	return false

func _live_ally_support() -> Array[Aircraft]:
	var live: Array[Aircraft] = []
	for ac in _ally_support:
		if is_instance_valid(ac) and not ac.is_destroyed and not ac.is_queued_for_deletion():
			live.append(ac)
	return live

## 固定 2×王牌成员数组，零全场扫描；目标失效或被普通敌机抢走时重新压回本事件王牌。
func _maintain_ally_support_targets() -> void:
	var aces := _live_ace_members()
	if aces.is_empty():
		return
	var support := _live_ally_support()
	for i in range(support.size()):
		var ac: Aircraft = support[i]
		if ac.combat_target in aces:
			continue
		var ai: AIController = ac._get_ai_controller()
		if ai:
			ai.acquire_target(aces[i % aces.size()], AIController.TargetSource.TS_BOSS,
				"ace intercept support")

func _handle_ace_terminal() -> void:
	_ace_terminal_handled = true
	var codename := AceSquadProfiles.codename(profile_id)
	if not _withdrawing and director.mode and director.mode.has_method("grant_time_extension"):
		director.mode.grant_time_extension(TIME_EXTENSION_S)
		var hint = _hint()
		if hint:
			var hint_key := "EVENT_ACE_SURRENDER_FMT" if _whitetea_surrendered else "EVENT_ACE_DOWN_FMT"
			hint.hide_persistent(tr("EVENT_ACE_INBOUND_FMT") % codename)
			hint.show_temp(tr(hint_key) % codename, 5.0)
	# 生涯档案：真全灭才算"击破"（撤离出界逃掉一架都不算，tier §2.7）
	if _escaped == 0 and director.mode and director.mode.has_method("archive_enabled") \
			and director.mode.archive_enabled():
		CareerArchive.record_ace_defeat(profile_id)
	var result_label := "surrendered" if _whitetea_surrendered else "eliminated"
	EventLogger.log_event("EVENT", "AceSupport",
		"%s %s%s | actual combat TTK=%.1fs encounter=%.1fs target=%.0f-%.0fs" % [codename,
			result_label, " (withdrawing, no bonus)" if _withdrawing else " -> +60s",
			_combat_elapsed_s, _encounter_elapsed_s, AceSquadProfiles.TTK_TARGET_MIN_S,
			AceSquadProfiles.TTK_TARGET_MAX_S])
	_log_balance_terminal("surrendered" if _whitetea_surrendered else ("withdrawn" if _escaped > 0 else \
		("eliminated_withdrawing" if _withdrawing else "eliminated")))
	_begin_ally_support_egress("ace event terminal")

func _begin_ally_support_egress(reason: String) -> void:
	var live := _live_ally_support()
	if live.is_empty():
		return
	_ally_support_egressing = true
	_ally_support_reengage_s = 0.0
	_ally_support_hp_watch = _ally_support_hp()
	_command_ally_support_exit()
	EventLogger.log_event("EVENT", "AceInterceptSupport",
		"egress x%d (%s)" % [live.size(), reason])

func _command_ally_support_exit() -> void:
	for ac in _live_ally_support():
		var ai: AIController = ac._get_ai_controller()
		if ai:
			ai.release_target(ai.get_target_source(), "ace intercept support egress")
			ai.enable_combat = false
			ai.enter_patrol_state(false)
			ai.waypoints = PackedVector2Array([_exit_point(ac.global_position)])
			ai.current_waypoint_index = 0
		ac.clear_formation()
		ac.is_afterburner = true
		if ac.params:
			ac.target_speed_kmh = ac.params.max_speed

func _ally_support_hp() -> float:
	var total := 0.0
	for ac in _live_ally_support():
		total += ac.hp
	return total

## 返回 true = 两机均已阵亡或飞出边界，可结束王牌事件。
func _tick_ally_support_egress(delta: float) -> bool:
	var live := _live_ally_support()
	if live.is_empty():
		return true
	var hp_now := _ally_support_hp()
	if hp_now < _ally_support_hp_watch - 0.01 and _ally_support_reengage_s <= 0.0:
		_ally_support_reengage_s = WITHDRAW_REENGAGE_S
		for ac in live:
			var ai: AIController = ac._get_ai_controller()
			if ai:
				ai.enable_combat = true
	_ally_support_hp_watch = hp_now
	if _ally_support_reengage_s > 0.0:
		_ally_support_reengage_s -= delta
		if _ally_support_reengage_s <= 0.0:
			_command_ally_support_exit()
	for ac in live:
		if MapBoundary.distance_to_edge(ac.global_position) <= -WITHDRAW_FREE_OUTSET_PX:
			ac.set_meta("xp_granted", true)
			CombatUnit.release_target_refs(ac)
			ac.queue_free()
	return _live_ally_support().is_empty()

func _begin_withdraw(reason: String = "boss unlocked") -> void:
	_withdrawing = true
	_withdraw_reason = reason
	_squad.combat_phase_active = false   # 停状态机软维护（不再补 ENGAGE）
	_hp_watch = _members_hp()
	_reengage_timer = 0.0
	for m in _squad.members:
		if not is_instance_valid(m):
			continue
		var ai: AIController = m._get_ai_controller()
		if ai:
			ai.release_target(AIController.TargetSource.TS_BOSS, "ace support withdraw")
			ai._state = AIController.AIState.PATROL
			ai.waypoints = PackedVector2Array([_exit_point(m.global_position)])
			ai.current_waypoint_index = 0
		m.is_afterburner = true
	var hint = _hint()
	if hint:
		hint.hide_persistent(
			tr("EVENT_ACE_INBOUND_FMT") % AceSquadProfiles.codename(profile_id))
		hint.show_temp(tr("EVENT_ACE_RETREAT_FMT") % AceSquadProfiles.codename(profile_id), 4.0)
	EventLogger.log_event("EVENT", "AceSupport", "withdraw (%s)" % _withdraw_reason)

func _tick_withdraw(delta: float) -> void:
	# 被伤害 → 立即回头应战（不做无敌逃兵，同 reinforcement EGRESS 契约）
	var hp_now := _members_hp()
	if hp_now < _hp_watch - 0.01:
		_reengage_timer = WITHDRAW_REENGAGE_S
		_squad.combat_phase_active = true   # PURSUIT 软维护重新接管（补锁玩家）
		EventLogger.log_event("EVENT", "AceSupport", "withdraw aborted (under fire)")
	_hp_watch = hp_now
	if _reengage_timer > 0.0:
		_reengage_timer -= delta
		if _reengage_timer <= 0.0:
			_begin_withdraw(_withdraw_reason)   # 脱离接触 → 重新撤（保留原因）
		return
	# 出界成员静默释放（防击杀误判、不给 XP —— 同 EGRESS 释放语义）
	for m in _squad.members.duplicate():
		if not is_instance_valid(m) or m.is_destroyed:
			continue
		if MapBoundary.distance_to_edge(m.global_position) <= -WITHDRAW_FREE_OUTSET_PX:
			m.set_meta("xp_granted", true)
			_escaped += 1   # 逃掉≥1 架 = 非全灭，不入"击破"档案
			CombatUnit.release_target_refs(m)   # 静默释放：没走坠机流程，引用得手动摘
			m.queue_free()

## 交战判定（tier §2.8：任一成员首次开火或首次被伤害）。
## 资源快照差分：spawn 时 HP/弹药/热诱弹均为满值，任何一项掉了 = 打过或挨过；
## 已有成员坠机（含一发被秒）也必然算交战
func _detect_battle_joined() -> bool:
	for m_any in _squad.all_members:
		if not is_instance_valid(m_any):
			return true   # 已释放（被击毁回收）→ 必然交战过
		var m: Aircraft = m_any
		if m.is_destroyed:
			return true
		var p: AircraftParams = m.params
		if p == null:
			continue
		if m.hp < p.max_hp - 0.01:
			return true
		if p.gun != null and m.ammo < p.gun.max_ammo:
			return true
		if p.missile != null and m.missiles_remaining < p.missile.max_count:
			return true
		if p.flare != null and m.flares_remaining < p.flare.max_flares:
			return true
	return false

func _members_hp() -> float:
	var total := 0.0
	for m in _squad.members:
		if is_instance_valid(m) and not m.is_destroyed:
			total += m.hp
	return total

## 最近边界方向的出界点（直飞出界；与 spawner 的退场点算法同思路的独立小实现）
func _exit_point(from: Vector2) -> Vector2:
	var half := MapBoundary.world_half_px()
	var out := half + WITHDRAW_FREE_OUTSET_PX + 400.0
	var sx := 1.0 if from.x >= 0.0 else -1.0
	var sy := 1.0 if from.y >= 0.0 else -1.0
	if (half - absf(from.x)) < (half - absf(from.y)):
		return Vector2(sx * out, from.y)
	return Vector2(from.x, sy * out)

func _hint():
	if director and director.mode and "_zone_hint" in director.mode:
		return director.mode._zone_hint
	return null

func _log_balance_terminal(result: String) -> void:
	if _balance_terminal_logged:
		return
	_balance_terminal_logged = true
	EventLogger.log_event("BALANCE", "AceTTK",
		"%s result=%s actual=%.1fs encounter=%.1fs estimated=%.1fs" % [
			AceSquadProfiles.codename(profile_id), result, _combat_elapsed_s, _encounter_elapsed_s,
			AceSquadProfiles.estimated_ttk_s(profile_id)])

func _finish() -> void:
	# 玩家先被击败 / 场景被终止也留样本，但 result 单列，不能混进正常击破 P50。
	if not _balance_terminal_logged and _battle_joined:
		var result := "cancelled"
		if director == null or director.player == null or not is_instance_valid(director.player) \
				or director.player.is_destroyed:
			result = "player_defeated"
		_log_balance_terminal(result)
	if _active_ref == self:
		_active_ref = null
	for ac in _live_ally_support():
		CombatUnit.release_target_refs(ac)
		ac.queue_free()
	_ally_support.clear()
	_squad = null
