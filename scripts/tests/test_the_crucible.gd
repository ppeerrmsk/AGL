extends RefCounted

const BOSS_SCRIPT := preload("res://scripts/survivor/the_crucible_boss.gd")

var _pass := 0
var _fail := 0


class VisibilityProbe:
	extends Node
	var visible_radius_px := 4200.0

	func is_world_pos_visible(world_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return world_pos.length() <= visible_radius_px


func run() -> void:
	print("\n════════ The Crucible 测试 ════════")
	_test_registry_and_music()
	_test_wave_contract()
	_test_opening_geometry()
	_test_free_for_all_roe()
	_test_kill_aggro()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_registry_and_music() -> void:
	var enc := BossRegistry.instantiate("THE_CRUCIBLE")
	var desert_pool: Array = BossRegistry.MAP_POOLS.get("desert_railway_preview", [])
	_check("The Crucible 决战事件已接入沙漠终局生命周期",
		enc != null and enc.get_script() == BOSS_SCRIPT)
	_check("The Crucible 主题没有人格化无线电或呼号",
		enc != null and not enc.arrival_radio_enabled and enc.callsign_prefix.is_empty())
	var radio_i18n := FileAccess.get_file_as_string("res://i18n/radio.csv")
	_check("The Crucible 旧台词与专属 i18n key 已移除",
		not radio_i18n.contains("RADIO_CRUCIBLE_"))
	_check("沙漠池同时包含列车与 The Crucible",
		desert_pool == ["ARMORED_TRAIN", "THE_CRUCIBLE"])
	_check("Round Table / Midnight March / Ace 路径已登记",
		AudioManager.MUSIC_FILES.get("boss_round_table", "").ends_with("round_table.ogg")
		and AudioManager.MUSIC_FILES.get("boss_midnight_march", "").ends_with("midnight_march.ogg")
		and AudioManager.MUSIC_FILES.get("ace_desert", "").ends_with("ace_desert.ogg"))
	_check("三首正式派生资源均可加载",
		AudioManager.has_music("boss_round_table")
		and AudioManager.has_music("boss_midnight_march")
		and AudioManager.has_music("ace_desert"))
	var train := BossRegistry.instantiate("ARMORED_TRAIN")
	_check("两个沙漠 Boss 命中专属 BGM 而非 fallback",
		enc != null and enc.bgm_track == "boss_round_table"
		and train != null and train.bgm_track == "boss_midnight_march")


func _test_wave_contract() -> void:
	_check("17 支王牌与 Hound 双机组成 18 队 73 架",
		BOSS_SCRIPT.PROFILE_ORDER.size() == 18 and _profile_aircraft_total() == 73)
	_check("Hound 固定为最终接力且不进入常规王牌池",
		BOSS_SCRIPT.PROFILE_ORDER.back() == "hound"
		and not AceSquadProfiles.pool_at(INF).has("hound"))
	var hound: Dictionary = AceSquadProfiles.get_profile("hound")
	var hound_elements: Array = hound.get("elements", [])
	_check("Hound 背叛版是 Crucible-only Boss 级 F-15 双机",
		bool(hound.get("crucible_only", false))
		and bool(hound.get("boss_grade", false))
		and hound.get("callsigns", []) == ["Hound-1", "Hound-2"]
		and hound_elements.size() == 2
		and int((hound_elements[0] as Dictionary).get("missile_count", 0)) == 10
		and int((hound_elements[1] as Dictionary).get("flares", 0)) == 3)
	_check("开场预生成前三队供真实长机切镜", BOSS_SCRIPT.CINEMATIC_SQUAD_COUNT == 3)
	_check("MARATHON 延后到第 6 批且不再参与首发",
		BOSS_SCRIPT.PROFILE_ORDER.slice(0, 3) == ["2ndwave", "gimmick", "goofighters"]
		and BOSS_SCRIPT.PROFILE_ORDER[5] == "marathon")
	_check("同屏最多三支王牌中队", BOSS_SCRIPT.ACTIVE_SQUAD_CAP == 3)
	_check("灭队后三秒才补入下一队",
		is_equal_approx(BOSS_SCRIPT.REINFORCEMENT_DELAY_S, 3.0))
	_check("新队至少从玩家 7.2km 外汇入主战场",
		is_equal_approx(BOSS_SCRIPT.ENTRY_DISTANCE_PX, 3600.0)
		and BOSS_SCRIPT.ENTRY_DISTANCE_MAX_PX > BOSS_SCRIPT.ENTRY_DISTANCE_PX)
	_check("越过 7.2km 交战半径必须返场",
		is_equal_approx(BOSS_SCRIPT.REENTRY_RADIUS_PX, 3600.0))
	_check("返场落点与外圈形成明确滞回",
		BOSS_SCRIPT.REENTRY_RING_MIN_PX
			+ BOSS_SCRIPT.REENTRY_RING_STEP_PX * float(BOSS_SCRIPT.REENTRY_RING_LAYERS - 1)
			+ BOSS_SCRIPT.REENTRY_ARRIVAL_RADIUS_PX < BOSS_SCRIPT.REENTRY_RADIUS_PX)
	var center := Vector2(120.0, -80.0)
	var first := BOSS_SCRIPT.reentry_target_for(center, 0)
	var second := BOSS_SCRIPT.reentry_target_for(center, 1)
	_check("固定名册槽使用分散且有界的返场环落点",
		first != second
		and first.distance_to(center) >= BOSS_SCRIPT.REENTRY_RING_MIN_PX - 0.01
		and second.distance_to(center) <= BOSS_SCRIPT.REENTRY_RING_MIN_PX
			+ BOSS_SCRIPT.REENTRY_RING_STEP_PX * float(BOSS_SCRIPT.REENTRY_RING_LAYERS - 1) + 0.01)


func _test_free_for_all_roe() -> void:
	_check("原 0/1/2 阵营语义不变",
		CombatUnit.teams_hostile(CombatUnit.TEAM_PLAYER, CombatUnit.TEAM_HOSTILE)
		and CombatUnit.teams_hostile(CombatUnit.TEAM_ALLY, CombatUnit.TEAM_HOSTILE)
		and not CombatUnit.teams_hostile(CombatUnit.TEAM_PLAYER, CombatUnit.TEAM_ALLY))
	var a := CombatUnit.TEAM_FREE_FOR_ALL_BASE
	var b := a + 1
	_check("FFA 同队友好、异队互相敌对",
		not CombatUnit.teams_hostile(a, a) and CombatUnit.teams_hostile(a, b)
		and CombatUnit.teams_hostile(a, CombatUnit.TEAM_PLAYER)
		and CombatUnit.teams_hostile(a, CombatUnit.TEAM_HOSTILE)
		and CombatUnit.teams_hostile(a, CombatUnit.TEAM_ALLY))


func _test_opening_geometry() -> void:
	_check("开局纯 Ace 混战窗固定为 8 秒",
		is_equal_approx(BOSS_SCRIPT.OPENING_MELEE_DURATION_S, 8.0))
	_check("首发三队占据左翼、正前与右翼包围槽",
		BOSS_SCRIPT.entry_relative_bearing_deg_for(0) == -110.0
		and BOSS_SCRIPT.entry_relative_bearing_deg_for(1) == 0.0
		and BOSS_SCRIPT.entry_relative_bearing_deg_for(2) == 110.0)
	var all_slots_avoid_six := true
	for i in range(BOSS_SCRIPT.PROFILE_ORDER.size()):
		var relative_deg: float = BOSS_SCRIPT.entry_relative_bearing_deg_for(i)
		all_slots_avoid_six = all_slots_avoid_six and absf(relative_deg) <= 135.0
	_check("全部 18 个出生槽排除玩家六点钟后方 ±45°", all_slots_avoid_six)
	var center := Vector2(300.0, -500.0)
	var north_pos: Vector2 = BOSS_SCRIPT.entry_position_for(center, 0.0, 1)
	var east_pos: Vector2 = BOSS_SCRIPT.entry_position_for(center, PI / 2.0, 1)
	_check("最小出生环随玩家航向旋转且保持 3600px 距离",
		is_equal_approx(north_pos.distance_to(center), BOSS_SCRIPT.ENTRY_DISTANCE_PX)
		and is_equal_approx(east_pos.distance_to(center), BOSS_SCRIPT.ENTRY_DISTANCE_PX)
		and north_pos.y < center.y and east_pos.x > center.x)
	var encounter = BOSS_SCRIPT.new()
	var visibility := VisibilityProbe.new()
	encounter._mode = visibility
	var wide_squad := AceSupportSquad.new("ido")
	var offscreen_pos: Vector2 = encounter._entry_spawn_position_for(
		Vector2.ZERO, 0.0, 1, wide_squad)
	var entry_dir := offscreen_pos.normalized()
	var all_formation_members_offscreen := true
	for offset in wide_squad._get_formation_offsets(entry_dir, entry_dir.rotated(PI / 2.0)):
		all_formation_members_offscreen = all_formation_members_offscreen \
			and not visibility.is_world_pos_visible(offscreen_pos + offset)
	_check("出生导演沿设计方位外推至整队离开当前镜头",
		offscreen_pos.distance_to(Vector2.ZERO) > visibility.visible_radius_px
		and offscreen_pos.distance_to(Vector2.ZERO) <= BOSS_SCRIPT.ENTRY_DISTANCE_MAX_PX
		and all_formation_members_offscreen)
	var player := Aircraft.new()
	var entrant := Aircraft.new()
	encounter._player = player
	entrant.global_position = Vector2(0.0, -5000.0)
	entrant.set_meta(BOSS_SCRIPT.ENTRY_INGRESS_META, true)
	encounter._force_reentry_if_strayed(entrant)
	var retained_ingress := bool(entrant.get_meta(BOSS_SCRIPT.ENTRY_INGRESS_META, false))
	entrant.global_position = Vector2(0.0, -2800.0)
	encounter._force_reentry_if_strayed(entrant)
	_check("初次远端入场不会误触脱战回收，进入 3000px 后才交还返场导演",
		retained_ingress and not entrant.has_meta(BOSS_SCRIPT.ENTRY_INGRESS_META))
	encounter._player = null
	encounter._mode = null
	entrant.free()
	player.free()
	visibility.free()


func _test_kill_aggro() -> void:
	var zero_close := BOSS_SCRIPT.aggro_score(0.0, 0)
	var one_far := BOSS_SCRIPT.aggro_score(BOSS_SCRIPT.AGGRO_MAX_DISTANCE_PX, 1)
	var two_equal := BOSS_SCRIPT.aggro_score(4500.0, 2)
	var zero_equal := BOSS_SCRIPT.aggro_score(4500.0, 0)
	_check("每个真实击坠固定增加 2 点仇恨",
		is_equal_approx(two_equal - zero_equal, 4.0))
	_check("一杀远距 Ace 仍高于零杀贴身目标", one_far > zero_close)
	_check("每支活跃中队只保留一名玩家猎手",
		BOSS_SCRIPT.PLAYER_HUNTERS_PER_SQUAD == 1)
	var candidate := Vector2(0.0, -500.0)
	var rear := BOSS_SCRIPT.rear_attack_opportunity_score(
		Vector2(0.0, 0.0), candidate, 0.0, true)
	var front := BOSS_SCRIPT.rear_attack_opportunity_score(
		Vector2(0.0, -1000.0), candidate, 0.0, true)
	var not_pressuring := BOSS_SCRIPT.rear_attack_opportunity_score(
		Vector2(0.0, 0.0), candidate, 0.0, false)
	var too_far := BOSS_SCRIPT.rear_attack_opportunity_score(
		Vector2(0.0, candidate.y + BOSS_SCRIPT.BACKSTAB_MAX_RANGE_PX + 1.0),
		candidate, 0.0, true)
	_check("仅玩家缠斗机暴露的后半球近距位置获得渔翁抢攻",
		rear > BOSS_SCRIPT.VISIBLE_BATTLE_BONUS
		and is_zero_approx(front) and is_zero_approx(not_pressuring)
		and is_zero_approx(too_far))
	_check("同一缠斗目标每轮最多被一名机会主义者认领",
		BOSS_SCRIPT.BACKSTAB_CLAIMS_PER_TARGET == 1)
	_check("玩家附近目标获得可见混战权重",
		BOSS_SCRIPT.visible_battle_score(0.0) > BOSS_SCRIPT.visible_battle_score(
			BOSS_SCRIPT.VISIBLE_BATTLE_RADIUS_PX))


func _profile_aircraft_total() -> int:
	var total := 0
	for id in BOSS_SCRIPT.PROFILE_ORDER:
		var profile: Dictionary = AceSquadProfiles.get_profile(id)
		var elements: Array = profile.get("elements", [])
		if elements.is_empty():
			total += int(profile.get("squad_size", 0))
		else:
			for element in elements:
				total += int((element as Dictionary).get("count", 0))
	return total


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
