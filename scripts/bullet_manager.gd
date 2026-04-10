class_name BulletManager
extends Node2D

const PIXELS_PER_METER: float = 0.5
const HIT_RADIUS: float = 12.0   ## 2D命中判定半径（像素）
const ALT_TOLERANCE: float = 500.0  ## 米 高度差容差
const TRACER_LENGTH: float = 8.0  ## 曳光弹绘制长度（像素）

## 友方（team 0）弹丸覆盖参数，由生存模式设置
var friendly_hit_radius: float = HIT_RADIUS
var friendly_dmg_full_ratio: float = 0.3   ## 满伤害飞行比例
var friendly_dmg_min_mult: float = 0.2     ## 最远端伤害倍率
var flat_altitude_mode: bool = false       ## 扁平高度模式：跳过高度容差检查

## 弹丸数据：{ pos: Vector2, vel: Vector2, owner: CombatUnit, damage: float, life: float }
var _bullets: Array[Dictionary] = []

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var combat_unit_list: Array[CombatUnit] = []

func spawn_bullet(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float) -> void:
	var speed_px := speed_ms * PIXELS_PER_METER
	var vel := Vector2(sin(direction), -cos(direction)) * speed_px
	_bullets.append({
		"pos": origin,
		"vel": vel,
		"source": source,
		"damage": damage,
		"life": 2.0,
		"max_life": 2.0,
		"altitude": source.altitude if is_instance_valid(source) else 5000.0,
	})

func _physics_process(delta: float) -> void:
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		b["pos"] += b["vel"] * delta
		b["life"] -= delta

		# 寿命到期
		if b["life"] <= 0.0:
			_bullets.remove_at(i)
			i -= 1
			continue

		# 命中检测
		var hit := false
		var source: CombatUnit = b["source"]
		var source_team: int = source.team if is_instance_valid(source) else -1
		for ac in combat_unit_list:
			if not is_instance_valid(ac) or ac.is_destroyed:
				continue
			if ac == source or ac.team == source_team:
				continue
			# 命中判定：2D 距离 + 高度容差（分别检查）
			var dist_2d: float = b["pos"].distance_to(ac.global_position)
			var alt_diff: float = absf(float(b["altitude"]) - ac.altitude)
			var is_friendly := source_team == 0
			var hit_r: float = friendly_hit_radius if is_friendly else HIT_RADIUS
			# 涉及地面单位时跳过高度检查（地面↔空中交火，俯视视角用2D判定）
			var source_is_ground := is_instance_valid(source) and source is GroundUnit
			var alt_ok := flat_altitude_mode or alt_diff < ALT_TOLERANCE or ac is GroundUnit or source_is_ground
			if dist_2d < hit_r and alt_ok:
				var full_r: float = friendly_dmg_full_ratio if is_friendly else 0.3
				var min_m: float = friendly_dmg_min_mult if is_friendly else 0.2
				var flight_ratio: float = 1.0 - float(b["life"]) / float(b["max_life"])
				var dmg_mult: float
				if flight_ratio < full_r:
					dmg_mult = 1.0
				else:
					dmg_mult = lerpf(1.0, min_m, (flight_ratio - full_r) / (1.0 - full_r))
				var actual_dmg: float = float(b["damage"]) * dmg_mult
				var src_name := "???"
				if is_instance_valid(source):
					if source is Aircraft and source.params:
						var side := "Friend" if source.team == 0 else "Enemy"
						src_name = "%s/%s[%s]" % [side, source.params.display_name, source.callsign]
					else:
						src_name = source.callsign if source.callsign != "" else source.name
				var tgt_unit: CombatUnit = ac as CombatUnit
				var tgt_name: String = tgt_unit.callsign if tgt_unit.callsign != "" else tgt_unit.name
				if ac is Aircraft and ac.params:
					var side2 := "Friend" if ac.team == 0 else "Enemy"
					tgt_name = "%s/%s[%s]" % [side2, ac.params.display_name, ac.callsign]
				EventLogger.log_event("GUN", src_name,
					"hit %s (dmg=%.1f)" % [tgt_name, actual_dmg])
				if ac is Aircraft:
					ac.take_bullet_damage(b["damage"] * dmg_mult)
				else:
					ac.take_damage(b["damage"] * dmg_mult)
				hit = true
				break

		if hit:
			_bullets.remove_at(i)

		i -= 1

	queue_redraw()

func _draw() -> void:
	for b in _bullets:
		var dir: Vector2 = b["vel"].normalized()
		var tail: Vector2 = b["pos"] - dir * TRACER_LENGTH
		# 曳光弹：亮黄色短线
		draw_line(b["pos"], tail, Color(1.0, 0.95, 0.4, 0.9), 1.5, true)
