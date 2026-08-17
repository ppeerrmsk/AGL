extends RefCounted

## 地图云量 + 沙尘暴聚焦回归（bench key: weather）。
var _fail: int = 0


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		print("  [ok] %s %s" % [label, detail])
	else:
		_fail += 1
		printerr("  [FAIL] %s %s" % [label, detail])


func run() -> void:
	print("=== weather system ===")
	_test_map_configs()
	_test_deterministic_capture_seed()
	_test_desert_cloud_reduction()
	_test_sandstorm_timeline_and_altitude()
	_test_aircraft_runtime_effect()
	_test_ocean_distribution()
	_test_runtime_consumers()
	print("WeatherSystem: %s (%d fail)" % ["PASS" if _fail == 0 else "FAIL", _fail])


func _test_deterministic_capture_seed() -> void:
	var camera := Camera2D.new()
	var first := WeatherSystem.new()
	var second := WeatherSystem.new()
	first.setup(camera, 0xA61)
	second.setup(camera, 0xA61)
	_check(first.cloud_seed == second.cloud_seed, "Visual bench 固定云层 seed")
	_check(first.wind_direction.is_equal_approx(second.wind_direction), "Visual bench 固定风向")
	_check(is_equal_approx(first.wind_speed, second.wind_speed), "Visual bench 固定风速")
	first.free()
	second.free()
	camera.free()


func _load_doc(path: String) -> MapDocument:
	var doc := MapDocument.load_from(path)
	_check(doc != null, "地图配置可加载", path)
	return doc


func _test_map_configs() -> void:
	var desert := _load_doc("res://resources/maps/desert_railway_preview.aglmap")
	var ocean := _load_doc("res://resources/maps/ocean_islands_preview.aglmap")
	if desert == null or ocean == null:
		return
	_check(is_equal_approx(float(desert.cloud["frequency"]), 0.00024), "沙漠普通云为大片低频")
	_check(is_equal_approx(float(desert.cloud["coverage"]), 0.26), "沙漠普通云量已下调")
	_check(is_equal_approx(float(desert.cloud["secondary_mix"]), 0.25), "沙漠第二噪声填补量已下调")
	_check(is_equal_approx(float(ocean.cloud["frequency"]), 0.00024), "海岛普通云为大片低频")
	_check(float(ocean.cloud["secondary_mix"]) >= 0.70, "海岛第二噪声填补分布空洞")
	var storm: Dictionary = desert.cloud.get("sandstorm", {})
	_check(bool(storm.get("enabled", false)), "沙漠启用沙尘暴")
	_check(is_equal_approx(float(storm.get("start_ratio", 0.0)), 0.45), "沙尘暴于 45% 局时开始")
	_check(is_equal_approx(float(storm.get("speed_kmh", 0.0)), 180.0), "沙尘暴以 180 km/h 推进")
	_check(is_equal_approx(float(storm.get("band_width_px", 0.0)), 5000.0), "沙尘带宽度缩至 10 km")


func _test_desert_cloud_reduction() -> void:
	var desert := _load_doc("res://resources/maps/desert_railway_preview.aglmap")
	if desert == null:
		return
	var previous: Dictionary = desert.cloud.duplicate(true)
	previous["coverage"] = 0.20
	previous["secondary_mix"] = 0.35
	var reduced_count := _count_cloud_samples(desert.cloud)
	var previous_count := _count_cloud_samples(previous)
	_check(reduced_count < previous_count, "沙漠普通云固定采样少于旧配置",
		"%d -> %d/576" % [previous_count, reduced_count])
	_check(reduced_count >= int(float(previous_count) * 0.55), "沙漠普通云为小幅下调而非清空")


func _count_cloud_samples(config: Dictionary) -> int:
	var weather := WeatherSystem.new()
	weather.apply_ugc_config(config)
	var cloudy := 0
	for yi in range(24):
		for xi in range(24):
			var p := Vector2(-14375.0 + xi * 1250.0, -14375.0 + yi * 1250.0)
			if weather.sample_density(p) > 0.0:
				cloudy += 1
	weather.free()
	return cloudy


func _test_sandstorm_timeline_and_altitude() -> void:
	var weather := WeatherSystem.new()
	weather.apply_ugc_config({
		"seed": 7, "coverage": 1.0, "frequency": 0.00024,
		"sandstorm": {"enabled": true, "seed": 11, "start_ratio": 0.45,
			"speed_kmh": 180.0, "band_width_px": 5000.0, "direction": "west_to_east"},
	})
	weather.set_game_time(269.9, 600.0)
	_check(not weather.is_sandstorm_active(), "中场前不触发")
	weather.set_game_time(270.0, 600.0)
	var start_center := weather.sandstorm_center_world().x
	weather.set_game_time(330.0, 600.0)
	var moved_px := weather.sandstorm_center_world().x - start_center
	_check(is_equal_approx(weather.sandstorm_duration_s, 1400.0), "70 km 全程按 180 km/h 计算为 1400 秒")
	_check(is_equal_approx(moved_px, 1500.0), "速度翻倍后一分钟推进 3 km", "move_px=%.1f" % moved_px)
	weather.set_debug_midgame(300.0, 600.0)
	var center_density := weather.sample_sandstorm_density(Vector2.ZERO)
	_check(weather.is_sandstorm_active() and center_density > 0.5,
		"F6 半局验收把慢速风暴定位到地图中心", "density=%.3f" % center_density)
	_check(weather.sample_obscurant_density(Vector2.ZERO, 2000.0) > 0.0, "LOW 受沙尘遮蔽")
	_check(weather.sample_obscurant_density(Vector2.ZERO, 5500.0) == 0.0, "MID 不受沙尘遮蔽")
	_check(weather.sample_obscurant_density(Vector2.ZERO, 10000.0) == 0.0, "HIGH 无沙尘云")
	var feather_density := weather.sample_sandstorm_density(Vector2(2400.0, 0.0))
	_check(feather_density > 0.0 and feather_density < center_density,
		"沙尘带曲边使用渐变密度羽化", "edge=%.3f" % feather_density)
	weather.free()


func _test_aircraft_runtime_effect() -> void:
	var weather := WeatherSystem.new()
	weather.apply_ugc_config({
		"seed": 7, "coverage": 1.0, "frequency": 0.00024,
		"sandstorm": {"enabled": true, "seed": 11, "start_ratio": 0.45,
			"speed_kmh": 180.0, "band_width_px": 5000.0, "direction": "west_to_east"},
	})
	weather.set_debug_midgame(300.0, 600.0)
	var aircraft := Aircraft.new()
	aircraft.team = CombatUnit.TEAM_HOSTILE
	aircraft.global_position = Vector2.ZERO
	aircraft.altitude = 2000.0
	aircraft._update_cloud_state(0.21, weather)
	_check(aircraft.cloud_state == 2 and aircraft.cloud_density > 0.0,
		"真实 Aircraft 在 LOW 沙带内进入战斗遮蔽状态",
		"state=%d density=%.3f" % [aircraft.cloud_state, aircraft.cloud_density])
	aircraft.altitude = 5500.0
	aircraft._update_cloud_state(0.21, weather)
	_check(aircraft.cloud_state == 0, "同一 Aircraft 到 MID 后退出沙尘遮蔽")
	var manager := MissileManager.new()
	manager._weather_ref = weather
	_check(manager.get_in_cloud(Vector2.ZERO, 2000.0), "MissileManager 在 LOW 实际读到沙尘遮蔽")
	_check(not manager.get_in_cloud(Vector2.ZERO, 5500.0), "MissileManager 在 MID 不误判沙尘遮蔽")
	manager.free()
	aircraft.free()
	weather.free()


func _test_ocean_distribution() -> void:
	var ocean := _load_doc("res://resources/maps/ocean_islands_preview.aglmap")
	if ocean == null:
		return
	var weather := WeatherSystem.new()
	weather.apply_ugc_config(ocean.cloud)
	var quadrants := [0, 0, 0, 0]
	var cloudy := 0
	for yi in range(24):
		for xi in range(24):
			var p := Vector2(-14375.0 + xi * 1250.0, -14375.0 + yi * 1250.0)
			if weather.sample_density(p) <= 0.0:
				continue
			cloudy += 1
			quadrants[(1 if p.x >= 0.0 else 0) + (2 if p.y >= 0.0 else 0)] += 1
	var qmin: int = quadrants.min()
	var qmax: int = quadrants.max()
	_check(cloudy >= 120, "海岛图总云量充足", "cloudy=%d/576" % cloudy)
	_check(qmin >= int(float(qmax) * 0.30), "海岛四象限分布不过度偏科", str(quadrants))
	weather.free()


func _test_runtime_consumers() -> void:
	var weather_src := FileAccess.get_file_as_string("res://scripts/weather_system.gd")
	var missile_src := FileAccess.get_file_as_string("res://scripts/missile.gd")
	var manager_src := FileAccess.get_file_as_string("res://scripts/missile_manager.gd")
	var survivor_src := FileAccess.get_file_as_string("res://scripts/survivor/survivor_mode.gd")
	var debug_src := FileAccess.get_file_as_string("res://scripts/survivor/survivor_debug_zone.gd")
	_check(weather_src.contains("_draw_sandstorm_streamlines")
		and weather_src.contains("_draw_sandstorm_observations")
		and weather_src.contains("_draw_sandstorm_front"), "沙尘暴使用气象图式矢量纹样")
	_check(not weather_src.contains("_draw_sandstorm_sprite"), "沙尘暴视觉不复用云贴图")
	_check(missile_src.contains("get_in_cloud(global_position, altitude)"), "导弹制导按高度查询遮蔽")
	_check(missile_src.contains("CLOUD_LOSS_PER_SECOND: float = 0.12")
		and missile_src.contains("_cloud_guidance_loss = minf"), "导弹在遮蔽中每秒累计 12% 制导损失")
	_check(manager_src.contains("sample_obscurant_density(unit.global_position, unit.altitude)"),
		"导弹命中失误复用统一遮蔽密度")
	_check(manager_src.contains("randf() < 0.35 * density"), "导弹命中失误率为 35% × 沙尘密度")
	_check(survivor_src.contains("_weather.is_obscured(pos, unit.altitude)")
		and survivor_src.contains("lock_rate *= 0.5"), "沙尘遮蔽使实际锁定速率减半")
	_check(debug_src.contains("debug_skip_to_midgame")
		and survivor_src.contains("set_debug_midgame"), "F6 半局入口可直接验收慢速沙带")
