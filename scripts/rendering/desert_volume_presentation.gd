extends "res://scripts/experiments/volume_world_probe.gd"
## 正式沙漠入口策略；共享地图/机体后端，不继承实验场景的玩法覆写。
const ENV_OVERRIDE := "AGL_DESERT_VOLUME"


static func enabled_for(source_path: String, external_experiment: bool = false,
		override_value: String = "") -> bool:
	return source_path == MAP_PATH and not external_experiment \
		and override_value.strip_edges().to_lower() not in ["0", "false", "off", "2d"]


func setup_formal(mode: Node, aircraft_enabled: bool = true) -> void:
	var prepared: Dictionary = preload("res://scripts/rendering/desert_map_preload.gd").take(mode, self)
	setup(mode, "volume_3d_desert_formal", {"include_map": true,
		"hide_2d_map": true, "prewarm_catalog": true, "prepared_map": prepared})
	set_bodies_enabled(aircraft_enabled)
