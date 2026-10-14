extends Node
## 相同 C1 混合交战与镜头，额外每秒两次真实致死事件；A/B 仅切换血色骑士。
var _mode: Node2D
var _enabled := false
var _kills := 0
var _converted := 0
var _fear_samples := 0
var _initial_hp := 0.0

func start(mode: Node2D, enabled: bool) -> void:
	_mode = mode
	_enabled = enabled
	await get_tree().create_timer(2.0).timeout
	# 性能对照固定构筑；继续 add_xp 记账，只停经验条排空引发的随机自动选卡。
	_mode.survivor_player.set_process(false)
	for uid in ["skill_kill_bloodlust", "skill_head_on_perma_hp", "skill_head_on_aoe_fear", "headon_xp"]:
		_mode._apply_upgrade_choice(SurvivorData.upgrade_by_id(uid))
	if enabled: _mode._apply_upgrade_choice(SurvivorData.upgrade_by_id("bloodlust_head_on"))
	_initial_hp = _mode.player_aircraft.params.max_hp
	_mode.player_aircraft.apply_status(StatusEffects.BLOODLUST, 9.0)
	while is_instance_valid(_mode):
		await get_tree().create_timer(0.5).timeout
		var killer: Aircraft = _mode.player_aircraft
		if not is_instance_valid(killer) or killer.is_destroyed: return
		var center: Vector2 = killer.global_position + Vector2(1600, 0)
		for raw in CombatUnit.all_units:
			if is_instance_valid(raw) and raw is Aircraft and not raw.is_destroyed \
					and raw.team == CombatUnit.TEAM_HOSTILE:
				center = raw.global_position + Vector2(100, 0)
				break
		var victim := Aircraft.new()
		victim.params = load("res://resources/default_fighter.tres").duplicate(true)
		victim.team = CombatUnit.TEAM_HOSTILE
		victim.position = center
		_mode.add_child(victim)
		victim.altitude = 5500.0
		# 令受害者背向攻击者，确保样本是技能转换而非几何碰巧对头。
		var away := center - killer.global_position
		victim.heading = atan2(away.x, -away.y)
		victim.take_damage(1000.0, killer, "missile")
		_kills += 1
		if bool(victim.get_meta(SkillHooks.BLOODLUST_HEAD_ON_META, false)): _converted += 1
		for raw in CombatUnit.all_units:
			if is_instance_valid(raw) and raw is Aircraft and not raw.is_destroyed \
					and raw.team == CombatUnit.TEAM_HOSTILE and raw.has_status(StatusEffects.FEAR):
				_fear_samples += 1

func summary() -> String:
	return "bloodlust_head_on enabled=%s kills=%d converted=%d fear_samples=%d hp_growth=%.0f" % [
		_enabled, _kills, _converted, _fear_samples, _mode.player_aircraft.params.max_hp - _initial_hp]

func coverage_ok() -> bool:
	return _kills >= 30 and (_converted >= 30 and _fear_samples > 0 if _enabled else _converted == 0)

func capture() -> void:
	await RenderingServer.frame_post_draw
	var suffix := "enabled" if _enabled else "baseline"
	get_viewport().get_texture().get_image().save_png("res://bench/results/bloodlust_head_on_%s.png" % suffix)
