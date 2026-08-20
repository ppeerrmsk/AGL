extends RefCounted

var _passed := 0
var _failed := 0


func run() -> Dictionary:
	print("\n════════ 纯视觉弹丸 SoA 测试 ════════")
	var manager := BulletManager.new()
	var source := CombatUnit.new()
	source.team = CombatUnit.TEAM_HOSTILE
	source.altitude = 5000.0

	manager.spawn_bullet(Vector2.ZERO, 0.0, 500.0, source, 0.0)
	_check(manager.visual_bullet_count() == 1 and manager._bullets.is_empty(),
		"零伤害普通弹进入独立 SoA，不污染真实碰撞数组")
	_check(manager.total_bullet_count() == 1, "总弹量包含视觉 SoA")
	manager._update_visual_bullets(0.5)
	_check(manager._visual_bullet_positions[0].is_equal_approx(Vector2(0, -125)),
		"视觉弹按原速度和 0.5px/m 比例移动")
	manager._update_visual_bullets(1.6)
	_check(manager.visual_bullet_count() == 0, "寿命结束使用 swap-remove 回收")

	manager.spawn_bullet(Vector2.ZERO, 0.0, 500.0, source, 10.0)
	_check(manager._bullets.size() == 1 and manager.visual_bullet_count() == 0,
		"真实伤害弹仍走完整 Dictionary 命中路径")

	var hostile_ship := NavalUnit.new()
	hostile_ship.team = CombatUnit.TEAM_HOSTILE
	var player_ship := NavalUnit.new()
	player_ship.team = CombatUnit.TEAM_PLAYER
	var ally_ship := NavalUnit.new()
	ally_ship.team = CombatUnit.TEAM_ALLY
	manager._unit_grid.rebuild([hostile_ship, player_ship, ally_ship])
	manager._rebuild_large_target_buckets()
	var hostile_targets := manager._large_targets_for_source_team(CombatUnit.TEAM_HOSTILE)
	_check(hostile_targets.has(player_ship) and hostile_targets.has(ally_ship) \
		and not hostile_targets.has(hostile_ship),
		"敌方真弹预分桶排除同阵营舰船并保留 PLAYER/ALLY")
	var player_targets := manager._large_targets_for_source_team(CombatUnit.TEAM_PLAYER)
	_check(player_targets == [hostile_ship], "玩家真弹大型候选只保留敌舰")

	source.free()
	hostile_ship.free()
	player_ship.free()
	ally_ship.free()
	manager.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_passed, _failed])
	return {"passed": _passed, "failed": _failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)
