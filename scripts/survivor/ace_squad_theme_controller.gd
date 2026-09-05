## 非 BOSS 王牌的队级主题控制器。
## 所有决策集中在中队级 2Hz tick；不为每架飞机新增 Node / _process。
class_name AceSquadThemeController
extends RefCounted

const THINK_INTERVAL_S := 0.5
const RELAY_INTERVAL_S := 6.0

var _squad: RefCounted
var _theme := ""
var _player: Aircraft
var _elapsed := THINK_INTERVAL_S
var _phase_elapsed := 0.0
var _phase := 0
var _previous_alive := -1
var _shared_flares := -1


func _init(squad: RefCounted, theme: String, player: Aircraft) -> void:
	_squad = squad
	_theme = theme
	_player = player
	var profile := AceSquadProfiles.get_profile(squad.profile_id)
	_shared_flares = int(profile.get("shared_flare_pool", -1))


func set_player_ref(player: Aircraft) -> void:
	if player != null and is_instance_valid(player):
		_player = player


func update(delta: float, allow_targeting: bool = true) -> void:
	if _theme == "" or _squad == null:
		return
	if _theme == "ido_network":
		_sync_shared_flares()
	_elapsed += delta
	_phase_elapsed += delta
	if _elapsed < THINK_INTERVAL_S:
		return
	_elapsed = fmod(_elapsed, THINK_INTERVAL_S)
	var live := _live_members()
	if live.is_empty():
		return
	for ac in live:
		ac.set_meta("ace_theme_state", _theme.to_upper())
	match _theme:
		"fate_roles":
			_apply_fate_roles(live, allow_targeting)
		"whip_relay":
			_apply_whip_relay(live, allow_targeting)
		"ido_network":
			_apply_ido_network(live, allow_targeting)
		"altitude_chain":
			_apply_altitude_chain(live)
		"deal_targets":
			if allow_targeting: _deal_player_targets(live)
		"weakest_target":
			if allow_targeting: _focus_weakest_player(live)
		"generations":
			_apply_generation_roles(live)
		"consensus":
			_apply_consensus(live, allow_targeting)
		"crossfire":
			if allow_targeting: _deal_player_targets(live)
		"mirror_player":
			_apply_mirror(live, allow_targeting)
		"empty_slot_revenge":
			_apply_funeral(live, allow_targeting)
		"hound_betrayal":
			_apply_hound_betrayal(live, allow_targeting)
	_previous_alive = live.size()


func _live_members() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for ac in _squad.members:
		if is_instance_valid(ac) and not ac.is_destroyed and not ac.is_queued_for_deletion():
			out.append(ac)
	return out


func _player_targets() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for unit in CombatUnit.all_units:
		if unit is Aircraft and is_instance_valid(unit) and not unit.is_destroyed \
				and unit.is_player_squad():
			out.append(unit)
	out.sort_custom(func(a: Aircraft, b: Aircraft): return a.get_instance_id() < b.get_instance_id())
	return out


func _assign(ac: Aircraft, target: Aircraft, reason: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var ai := ac._get_ai_controller()
	if ai and ai.acquire_target(target, AIController.TargetSource.TS_BOSS, reason):
		ai.enable_combat = true
		ai.enter_engage_state()


func _set_role(ac: Aircraft, close_attack: bool, state: String) -> void:
	var ai := ac._get_ai_controller()
	if ai:
		ai.boss_attacker = close_attack
		ai.bvr_only = not close_attack
		ai.aggression = 0.98 if close_attack else 0.88
		ai.self_preservation = 0.12 if close_attack else 0.30
	ac.prefer_gun_mode = close_attack
	ac.set_meta("ace_theme_state", state)


func _apply_fate_roles(live: Array[Aircraft], allow_targeting: bool) -> void:
	for i in range(live.size()):
		_set_role(live[i], i == 1, ["SPIN", "MEASURE", "CUT"][mini(i, 2)])
	if allow_targeting:
		_deal_player_targets(live)


func _apply_whip_relay(live: Array[Aircraft], allow_targeting: bool) -> void:
	if _phase_elapsed >= RELAY_INTERVAL_S:
		_phase_elapsed = fmod(_phase_elapsed, RELAY_INTERVAL_S)
		_phase += 1
	var active_i := _phase % live.size()
	for i in range(live.size()):
		_set_role(live[i], i == active_i, "CRACK" if i == active_i else "FOLLOW")
	if allow_targeting and _player != null and is_instance_valid(_player):
		_assign(live[active_i], _player, "LASH relay")


func _sync_shared_flares() -> void:
	if _shared_flares < 0:
		return
	var observed := _shared_flares
	for ac in _squad.members:
		if is_instance_valid(ac) and not ac.is_destroyed:
			observed = mini(observed, ac.flares_remaining)
	if observed < _shared_flares:
		_shared_flares = observed
	for ac in _squad.members:
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.flares_remaining = _shared_flares


func _apply_ido_network(live: Array[Aircraft], allow_targeting: bool) -> void:
	for i in range(live.size()):
		live[i].no_pilot = true
		live[i].set_meta("ace_theme_state", "NETWORK %d" % _shared_flares)
	if allow_targeting:
		_deal_player_targets(live)


func _apply_altitude_chain(live: Array[Aircraft]) -> void:
	if _phase_elapsed >= 10.0:
		_phase_elapsed = fmod(_phase_elapsed, 10.0)
		_phase += 1
	var tiers := [Aircraft.AltitudeTier.HIGH, Aircraft.AltitudeTier.MID, Aircraft.AltitudeTier.LOW]
	for i in range(live.size()):
		var tier: int = tiers[(i + _phase) % tiers.size()]
		live[i].set_target_tier(tier)
		live[i].set_meta("ace_theme_state", ["LOW", "MID", "HIGH"][tier])


func _deal_player_targets(live: Array[Aircraft]) -> void:
	var targets := _player_targets()
	if targets.is_empty():
		return
	for i in range(live.size()):
		_assign(live[i], targets[i % targets.size()], "ace theme spread")


func _focus_weakest_player(live: Array[Aircraft]) -> void:
	var targets := _player_targets()
	if targets.is_empty():
		return
	var weakest := targets[0]
	var weakest_ratio := weakest.hp / maxf(weakest.params.max_hp if weakest.params else 1.0, 1.0)
	for target in targets:
		var ratio := target.hp / maxf(target.params.max_hp if target.params else 1.0, 1.0)
		if ratio < weakest_ratio:
			weakest = target
			weakest_ratio = ratio
	for ac in live:
		ac.set_meta("ace_theme_state", "TALLY")
		_assign(ac, weakest, "TALLYMAN weakest")


func _apply_generation_roles(live: Array[Aircraft]) -> void:
	for i in range(live.size()):
		_set_role(live[i], i == 0 or i == 3, "GEN-%d" % (i + 1))


func _apply_consensus(live: Array[Aircraft], allow_targeting: bool) -> void:
	var unanimous := live.size() >= 3
	for i in range(live.size()):
		_set_role(live[i], not unanimous or i == 0, "UNANIMOUS" if unanimous else "DISSENT")
	if allow_targeting:
		if unanimous and _player != null and is_instance_valid(_player):
			for ac in live: _assign(ac, _player, "QUORUM vote")
		else:
			_deal_player_targets(live)


func _apply_mirror(live: Array[Aircraft], allow_targeting: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var tier := _player.get_altitude_tier()
	for ac in live:
		ac.set_target_tier(tier)
		ac.prefer_gun_mode = _player.prefer_gun_mode
		ac.set_meta("ace_theme_state", "MIRROR")
		if allow_targeting: _assign(ac, _player, "MIRROR copy")


func _apply_funeral(live: Array[Aircraft], allow_targeting: bool) -> void:
	var profile := AceSquadProfiles.get_profile(_squad.profile_id)
	var loss_happened := live.size() < int(profile.get("squad_size", live.size()))
	for ac in live:
		_set_role(ac, loss_happened or live.size() <= 2, "REQUIEM" if loss_happened else "PROCESSION")
	if allow_targeting and (loss_happened or live.size() <= 2) and _player != null and is_instance_valid(_player):
		for ac in live: _assign(ac, _player, "FUNERAL empty slot")


func _apply_hound_betrayal(live: Array[Aircraft], allow_targeting: bool) -> void:
	if live.size() == 1:
		_set_role(live[0], true, "VENGEANCE")
	elif live.size() >= 2:
		# Hound-1 保持远距火控，Hound-2 近身施压；失去搭档后幸存者转为全力追杀。
		_set_role(live[0], false, "OVERWATCH")
		_set_role(live[1], true, "PURSUER")
	if allow_targeting and _player != null and is_instance_valid(_player):
		for ac in live:
			_assign(ac, _player, "HOUND betrayal")
