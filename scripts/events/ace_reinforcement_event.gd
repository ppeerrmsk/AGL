## 王牌支援中队事件（spec events/ace-support-squadron）
##
## 生命周期：
##   _start   玩家 heading 前方扇区边缘生成 AceSupportSquad（Su-35 ×5）→ 立即 engage()
##            （PURSUIT 全员锁玩家、直奔而来，无锚点待机相）→ 长机 ace_spawn 无线电
##            + 次级提示条（红色警告横幅是 BOSS 专属，tier spec §2.6）
##   _update  监护：全灭 → grant_time_extension(60) + 歼灭通报 → end；
##            BOSS 解锁 → 转撤离（直飞最近边界；被伤害立即回头应战，脱离接触后再撤；
##            撤离中被全灭：XP 照给、无时间奖励 —— game_time 已冻结无意义）
##   _finish  静态注册表清引用；managed_units 交 director 兜底回收
##
## 调度（survivor_mode._update_ace_support_event）：首支 game_time≥240s；前支结束后
## ≥150s 再触发；game_time≥540s 不新刷；同场 ≤1 支；BOSS 阶段不触发。
class_name AceReinforcementEvent
extends GameEvent

const TIME_EXTENSION_S := 60.0          ## 全灭奖励：整局延长 1 分钟（spec §2.5）
const WITHDRAW_REENGAGE_S := 5.0        ## 撤离被打断 → 回头应战的最短时长
const WITHDRAW_FREE_OUTSET_PX := 800.0  ## 出界此距离即静默释放（同 EGRESS 语义）

## Tab 战术图标记用静态注册表（学 AwacsSupportEvent：validity 守卫，场景重开自然失效）
static var _active_ref: AceReinforcementEvent = null

## 编成 profile（spec ace-squadron-tier §2.7；调度器按时段档轮换注入）
var profile_id := "marathon"

var _squad: AceSupportSquad = null
var _withdrawing := false
var _reengage_timer := 0.0   ## >0 = 撤离被打断、正在回头应战
var _hp_watch := -1.0        ## 撤离期 HP 总和快照（掉血 = 被伤害 → 应战）
var _escaped := 0            ## 撤离出界释放数（>0 = 非全灭，不入"击破"档案）
var _battle_joined := false  ## 交战血条已亮（tier §2.8：首次开火/受击触发，入场不亮）
var _withdraw_reason := ""   ## "boss unlocked" / "ammo dry"（骑士弹尽）

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

## HUD 交战血条数据源（tier §2.8 分段命条）。未交战 / 不在场返回空字典。
## alive 数组按 squad 槽位序（下标 0 = 长机段，HUD 画三角标记）
static func battle_bar_info() -> Dictionary:
	if _active_ref == null or _active_ref._squad == null or not _active_ref._squad.active:
		return {}
	if not _active_ref._battle_joined:
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
	_squad.engage()   # 立即 PURSUIT：无 PRE_STAGE 待机（spec §2.6 进场即咬）
	_active_ref = self
	# 入场演出（tier spec §2.6）：红色警告横幅是 BOSS 专属 —— 王牌中队的入场主信号
	# 是长机无线电（ace_spawn，scripted 必定播出）+ 次级提示条
	var radio = director.mode.get("_radio") if director.mode else null
	if radio:
		radio.say_unit("ace_spawn", _squad.members[0])
	var hint = _hint()
	if hint:
		# 提示条带中队代号（tier §2.6，727 包装批）
		hint.show_temp(tr("EVENT_ACE_INBOUND_FMT") % AceSquadProfiles.codename(profile_id), 5.0)
	# 生涯档案：遭遇记一笔（bench / boss debug 局由 archive_enabled 挡）
	if director.mode and director.mode.has_method("archive_enabled") \
			and director.mode.archive_enabled():
		CareerArchive.record_ace_encounter(profile_id)
	EventLogger.log_event("EVENT", "AceSupport",
		"%s inbound x%d from %s" % [AceSquadProfiles.codename(profile_id),
			_squad.members.size(), _squad.entry_origin_override.round()])

func _update(delta: float) -> void:
	if _squad == null:
		end()
		return
	_squad.update(delta)
	# 交战血条触发（tier §2.8）：入场不亮，打起来才亮；撤离中不新亮
	if not _battle_joined and not _withdrawing:
		_battle_joined = _detect_battle_joined()
	# 全灭 / 撤离释放完毕（active 由 AceSquad.update 的存活过滤翻 false）
	if not _squad.active:
		var codename := AceSquadProfiles.codename(profile_id)
		if not _withdrawing and director.mode and director.mode.has_method("grant_time_extension"):
			director.mode.grant_time_extension(TIME_EXTENSION_S)
			var hint = _hint()
			if hint:
				hint.show_temp(tr("EVENT_ACE_DOWN_FMT") % codename, 5.0)
		# 生涯档案：真全灭才算"击破"（撤离出界逃掉一架都不算，tier §2.7）
		if _escaped == 0 and director.mode and director.mode.has_method("archive_enabled") \
				and director.mode.archive_enabled():
			CareerArchive.record_ace_defeat(profile_id)
		EventLogger.log_event("EVENT", "AceSupport",
			"%s eliminated%s" % [codename,
				" (withdrawing, no bonus)" if _withdrawing else " -> +60s"])
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

func _finish() -> void:
	if _active_ref == self:
		_active_ref = null
	_squad = null
