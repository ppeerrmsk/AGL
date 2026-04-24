class_name BulletManager
extends Node2D

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER
const HIT_RADIUS: float = 12.0   ## 2D命中判定半径（像素）
const ROCKET_HIT_RADIUS: float = 18.0  ## 火箭命中判定半径（略大）
const ALT_TOLERANCE: float = 500.0  ## 米 高度差容差
const TRACER_LENGTH: float = 8.0  ## 曳光弹绘制长度（像素）
const ROCKET_TRAIL_LENGTH: float = 16.0  ## 火箭尾迹绘制长度
const ExplosionVFXScript = preload("res://scripts/explosion_vfx.gd")

## 友方（team 0）弹丸覆盖参数，由生存模式设置
var friendly_hit_radius: float = HIT_RADIUS
var friendly_dmg_full_ratio: float = 0.3   ## 满伤害飞行比例
var friendly_dmg_min_mult: float = 0.2     ## 最远端伤害倍率
var flat_altitude_mode: bool = false       ## 扁平高度模式：跳过高度容差检查

## 弹丸数据：{ pos: Vector2, vel: Vector2, owner: CombatUnit, damage: float, life: float }
var _bullets: Array[Dictionary] = []

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var combat_unit_list: Array[CombatUnit] = []

## 导弹管理器引用（CIWS 子弹需要碰撞导弹）
var missile_manager: Node = null

## visual_only: 视觉装饰弹 —— 正常飞行 / 渲染 / 寿命结束，但跳过所有命中判定
## 用于制造"CIWS 密集弹幕"的观感，同时不影响平衡（真实伤害由另一部分子弹承担）
func spawn_bullet(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, is_ciws: bool = false, visual_only: bool = false) -> void:
	var speed_px := speed_ms * PIXELS_PER_METER
	var vel := Vector2(sin(direction), -cos(direction)) * speed_px
	# ⚠ 快照 team 到 dict：弹丸寿命中射手可能被释放，
	#   后续命中判定必须靠 source_team 而不是 source.team。
	_bullets.append({
		"pos": origin,
		"vel": vel,
		"source": source,
		"source_team": source.team if is_instance_valid(source) else -1,
		"damage": damage,
		"life": 2.0,
		"max_life": 2.0,
		"altitude": source.altitude if is_instance_valid(source) else 5000.0,
		"is_rocket": false,
		"is_ciws": is_ciws,
		"visual_only": visual_only,
	})

## 生成无制导火箭弹
## 与子弹共享物理，但命中半径略大、速度较慢、无伤害衰减、视觉独立
func spawn_rocket(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, max_range_m: float) -> void:
	var speed_px := speed_ms * PIXELS_PER_METER
	var vel := Vector2(sin(direction), -cos(direction)) * speed_px
	# 寿命 = 射程 / 初速
	var life := clampf(max_range_m / maxf(speed_ms, 50.0), 1.5, 6.0)
	_bullets.append({
		"pos": origin,
		"vel": vel,
		"source": source,
		"source_team": source.team if is_instance_valid(source) else -1,
		"damage": damage,
		"life": life,
		"max_life": life,
		"altitude": source.altitude if is_instance_valid(source) else 5000.0,
		"is_rocket": true,
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

		# 视觉装饰弹 —— 完全跳过命中检测（只用于 CIWS 密集弹幕观感）
		if b.get("visual_only", false):
			i -= 1
			continue

		# 命中检测
		# ⚠ 不能直接给带类型变量赋值 b["source"]：如果射手已被释放，
		#   Godot 会抛 "Trying to assign invalid previously freed instance"。
		#   先用 Variant 接住，再查 validity；team 已在 spawn 时快照到 dict。
		var hit := false
		var source_raw: Variant = b["source"]
		var source_alive: bool = is_instance_valid(source_raw)
		var source_team: int = int(b.get("source_team", -1))
		for ac in combat_unit_list:
			if not is_instance_valid(ac) or ac.is_destroyed:
				continue
			# 射手还活着：跳过打到自己
			if source_alive and ac == source_raw:
				continue
			# 跳过同队（无论射手死活都用快照 team 判定）
			if ac.team == source_team:
				continue
			# 光学隐形：子弹/火箭弹穿过隐形目标
			if ac is Aircraft and ac.is_cloaked:
				continue
			# 战术机动中及结束后缓冲期内免疫所有弹药
			if ac is Aircraft:
				var _bm = ac.get_maneuver()
				if _bm and (_bm.is_active or (_bm.is_used and ac.missile_phase_timer > 0.0)):
					continue
				# Herbst J-Turn 全程免疫（和眼镜蛇机动对称：模块激活期间子弹穿过）
				var _hm_b = ac.get_herbst()
				if _hm_b and _hm_b.is_active:
					continue
			# 命中判定：2D 距离 + 高度容差（分别检查）
			var dist_2d: float = b["pos"].distance_to(ac.global_position)
			var alt_diff: float = absf(float(b["altitude"]) - ac.altitude)
			var is_friendly := source_team == 0
			var is_rocket: bool = b.get("is_rocket", false)
			var hit_r: float
			if is_rocket:
				hit_r = ROCKET_HIT_RADIUS
			else:
				hit_r = friendly_hit_radius if is_friendly else HIT_RADIUS
			# 船的命中半径跟船长挂钩（否则 12px 半径对 80-280 px 船体太小了）
			if ac is NavalUnit:
				var nu: NavalUnit = ac as NavalUnit
				if nu.params:
					hit_r = maxf(hit_r, nu.params.hull_length * 0.5)
			# 涉及地面 / 海上单位时跳过高度检查（俯视视角用 2D 判定）
			var source_is_ground := source_alive and (source_raw is GroundUnit or source_raw is NavalUnit)
			var alt_ok := flat_altitude_mode or alt_diff < ALT_TOLERANCE or ac is GroundUnit or ac is NavalUnit or source_is_ground
			if dist_2d < hit_r and alt_ok:
				var dmg_mult: float = 1.0
				if not is_rocket:
					# 子弹：按飞行距离衰减
					var full_r: float = friendly_dmg_full_ratio if is_friendly else 0.3
					var min_m: float = friendly_dmg_min_mult if is_friendly else 0.2
					var flight_ratio: float = 1.0 - float(b["life"]) / float(b["max_life"])
					if flight_ratio < full_r:
						dmg_mult = 1.0
					else:
						dmg_mult = lerpf(1.0, min_m, (flight_ratio - full_r) / (1.0 - full_r))
				# 火箭：无衰减，全射程恒定伤害
				var actual_dmg: float = float(b["damage"]) * dmg_mult
				var src_name := "???"
				if source_alive:
					var src_unit: CombatUnit = source_raw
					if src_unit is Aircraft and src_unit.params:
						var side := "Friend" if src_unit.team == 0 else "Enemy"
						src_name = "%s/%s[%s]" % [side, src_unit.params.display_name, src_unit.callsign]
					else:
						src_name = src_unit.callsign if src_unit.callsign != "" else String(src_unit.name)
				var tgt_unit: CombatUnit = ac as CombatUnit
				var tgt_name: String = tgt_unit.callsign if tgt_unit.callsign != "" else String(tgt_unit.name)
				if ac is Aircraft and ac.params:
					var side2 := "Friend" if ac.team == 0 else "Enemy"
					tgt_name = "%s/%s[%s]" % [side2, ac.params.display_name, ac.callsign]
				var evt_tag := "ROCKET" if is_rocket else "GUN"
				EventLogger.log_event(evt_tag, src_name,
					"hit %s (dmg=%.1f)" % [tgt_name, actual_dmg])
				if is_rocket:
					# 火箭不进入子弹闪避系统
					# 爆炸画在目标本体位置（不是命中点），击中/击毁均只此一次
					var r_head: float = ac.heading if "heading" in ac else 0.0
					ExplosionVFXScript.emit(get_tree(), ac.global_position, r_head, 1.0)
					if ac is NavalUnit:
						# 火箭对船体总血削 50%，可以打穿弱点（破甲效果）
						(ac as NavalUnit).take_damage_at(actual_dmg, b["pos"], 0.5, true)
					else:
						ac.take_damage(actual_dmg)
				elif ac is Aircraft:
					ac.take_bullet_damage(b["damage"] * dmg_mult)
				elif ac is NavalUnit:
					# 机炮子弹：
					#   - 总血削 15%（高射速高伤害 → 低总血贡献，避免一梭子秒船）
					#   - 不能一发斩杀弱点（can_hit_weak_point=false）—— 弱点要留给导弹
					#   - 挂点仍然按全额扣（机炮剥部件依然有效）
					(ac as NavalUnit).take_damage_at(b["damage"] * dmg_mult, b["pos"], 0.15, false)
				else:
					ac.take_damage(b["damage"] * dmg_mult)
				hit = true
				break

		# CIWS 子弹 vs 敌方导弹碰撞（仅带 is_ciws 标记的子弹）
		# 伤害按"导弹到源（防守方）的距离"衰减：
		#   - 导弹离防守单位很近（< 250 px，约末端引信距离）→ 满伤害
		#   - 远距（> 800 px）→ 0 伤害（bullets 只是装饰，穿过导弹不受影响）
		# 避免"玩家刚发射导弹就被 CIWS 的在飞子弹拦下"的反直觉场景
		if not hit and b.get("is_ciws", false) and missile_manager:
			for child in missile_manager.get_children():
				if not (child is Missile):
					continue
				var m: Missile = child as Missile
				if not m.is_active or m.team == source_team:
					continue
				var dist_m: float = Vector2(b["pos"]).distance_to(m.global_position)
				if dist_m < HIT_RADIUS:
					# 距离衰减因子：导弹离 CIWS 发射源越近，拦截伤害越高
					var msl_to_src: float = 9999.0
					var factor: float = 0.0
					if source_alive:
						msl_to_src = m.global_position.distance_to(source_raw.global_position)
						factor = clampf((800.0 - msl_to_src) / 550.0, 0.0, 1.0)
					# 累积伤害到 intercept_hp；归零才真正击落
					var dmg: float = float(b["damage"]) * factor
					if dmg > 0.0:
						m.intercept_hp -= dmg
						if m.intercept_hp <= 0.0:
							m.is_active = false
							EventLogger.log_event("CIWS", "Player",
								"intercepted missile (final dist=%.0f, factor=%.2f)" % [msl_to_src, factor])
					hit = true
					break

		if hit:
			_bullets.remove_at(i)

		i -= 1

	queue_redraw()

func _draw() -> void:
	for b in _bullets:
		var dir: Vector2 = b["vel"].normalized()
		if b.get("is_rocket", false):
			# 火箭：橙红色较长尾迹 + 亮白头
			var tail: Vector2 = b["pos"] - dir * ROCKET_TRAIL_LENGTH
			draw_line(b["pos"], tail, Color(1.0, 0.45, 0.15, 0.85), 2.2, true)
			draw_circle(b["pos"], 2.0, Color(1.0, 0.95, 0.8, 1.0))
		else:
			# 曳光弹：亮黄色短线
			var tail: Vector2 = b["pos"] - dir * TRACER_LENGTH
			draw_line(b["pos"], tail, Color(1.0, 0.95, 0.4, 0.9), 1.5, true)
