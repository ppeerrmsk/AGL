class_name BulletManager
extends Node2D

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER
const HIT_RADIUS: float = 12.0   ## 2D命中判定半径（像素）
const ROCKET_HIT_RADIUS: float = 18.0  ## 火箭命中判定半径（略大）
const ALT_TOLERANCE: float = 500.0  ## 米 高度差容差
const TRACER_LENGTH: float = 8.0  ## 曳光弹绘制长度（像素）
const ROCKET_TRAIL_LENGTH: float = 16.0  ## 火箭尾迹绘制长度
const FADE_OUT_DURATION: float = 0.25  ## 寿命最后 0.25s 内逐帧淡出（替代瞬间消失）
const ExplosionVFXScript = preload("res://scripts/explosion_vfx.gd")

## 友方（team 0）弹丸覆盖参数，由生存模式设置
var friendly_hit_radius: float = HIT_RADIUS
var friendly_dmg_full_ratio: float = 0.3   ## 满伤害飞行比例
var friendly_dmg_min_mult: float = 0.2     ## 最远端伤害倍率
var flat_altitude_mode: bool = false       ## 扁平高度模式：跳过高度容差检查

## 弹丸数据：{ pos: Vector2, vel: Vector2, owner: CombatUnit, damage: float, life: float }
var _bullets: Array[Dictionary] = []

## MultiMesh 路径（USE_MULTIMESH_BULLETS 开关）— 仅用于机炮 tracer（非火箭）
## v1 范围：tracer 用 QuadMesh + 单一黄色 + per-instance fade alpha
## 火箭弹和漂浮雷保留 _draw 老路径（视觉太异质难批处理）
## 详见 docs/planning/sprite-multimesh-refactor.md
var _mm_instance: MultiMeshInstance2D = null
var _mm: MultiMesh = null

## 空中漂浮雷（独立数组，不污染子弹热路径）
## 数据结构：{ pos, drift_vel_px, source, source_team, params, target_id,
##            retarget_timer, life, altitude }
var _torpedoes: Array[Dictionary] = []
## 同屏上限：每个 source 各自最多 21 颗（玩家有技能减 CD 后的极限值）
const MAX_TORPEDOES_PER_SOURCE: int = 21


func _ready() -> void:
	# MultiMesh 路径初始化（flag 关时零开销）
	if GameConstants.USE_MULTIMESH_BULLETS:
		_setup_multimesh_tracers()

## 建立 MultiMesh + Quad mesh 用于机炮 tracer 批量渲染
## Quad 大小 = (TRACER_LENGTH, 1.5px)，中心位于本地 (0,0)
## 每帧 _update_multimesh_tracers 写 transform + per-instance color
## 头部位于 Quad 局部 +X / 2，让 vel 方向旋转后头部对齐 b["pos"]
func _setup_multimesh_tracers() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	# 用 QuadMesh（3D 在 2D 上下文也能渲染）
	var quad := QuadMesh.new()
	quad.size = Vector2(TRACER_LENGTH, 1.5)
	_mm.mesh = quad
	_mm.instance_count = 0  # 每帧动态调整
	_mm_instance = MultiMeshInstance2D.new()
	_mm_instance.name = "BulletMultiMesh"
	_mm_instance.multimesh = _mm
	# 无纹理 → 纯色 quad，颜色由 per-instance color modulate
	add_child(_mm_instance)

## 把 _bullets 数组里的"非火箭非装饰"机炮 tracer 写到 MultiMesh
## 火箭、漂浮雷、visual_only 装饰弹保留 _draw 老路径
func _update_multimesh_tracers() -> void:
	if _mm == null:
		return
	# 第一遍：数有几颗要走 MultiMesh
	var count := 0
	for b in _bullets:
		if b.get("is_rocket", false):
			continue
		count += 1
	_mm.instance_count = count
	# 第二遍：写 transform + color
	var i := 0
	for b in _bullets:
		if b.get("is_rocket", false):
			continue
		var pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		# 速度为零的子弹理论上不存在；防御性处理
		var dir: Vector2 = vel.normalized() if vel.length_squared() > 0.01 else Vector2.RIGHT
		var angle: float = atan2(dir.y, dir.x)
		# Quad 中心放在头部后 TRACER_LENGTH/2 处 → 头部对齐 b["pos"]，尾部 b["pos"] - dir*TRACER_LENGTH
		var center: Vector2 = pos - dir * (TRACER_LENGTH * 0.5)
		var xf := Transform2D(angle, center)
		_mm.set_instance_transform_2d(i, xf)
		# fade：寿命末段淡出（与 _draw 老路径一致：alpha = 0.9 * fade）
		var life_left: float = float(b["life"])
		var fade: float = clampf(life_left / FADE_OUT_DURATION, 0.0, 1.0)
		_mm.set_instance_color(i, Color(1.0, 0.95, 0.4, 0.9 * fade))
		i += 1

## 建筑拦截概率查表（与 missile_manager._building_block_prob_for_tier 一致）
##   HIGH → 40% / MID → 60% / LOW → 80% / GROUND → 100%
static func _building_block_prob_for_tier(source_tier: int) -> float:
	match source_tier:
		CombatUnit.AltitudeTier.HIGH:
			return 0.40
		CombatUnit.AltitudeTier.MID:
			return 0.60
		CombatUnit.AltitudeTier.LOW:
			return 0.80
		_:
			return 1.00

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var combat_unit_list: Array[CombatUnit] = []
## 敌我方预分桶（_rebuild_team_buckets 每帧从 combat_unit_list 自建）：enemies_of_teamT = 所有 team != T 的单位
## 子弹命中循环用，team-0/1 射手只扫对方阵营，避免 O(B×N) 全扫；source_team=-1 等回退 combat_unit_list
var enemies_of_team0: Array[CombatUnit] = []
var enemies_of_team1: Array[CombatUnit] = []

## 每帧从 combat_unit_list 重建敌我方分桶（team_other 对双方都算敌方，与旧 team!= 判定等价）
func _rebuild_team_buckets() -> void:
	var t0: Array[CombatUnit] = []
	var t1: Array[CombatUnit] = []
	var other: Array[CombatUnit] = []
	for u in combat_unit_list:
		if u == null or not is_instance_valid(u):
			continue
		if u.team == 0:
			t0.append(u)
		elif u.team == 1:
			t1.append(u)
		else:
			other.append(u)
	enemies_of_team0 = t1 + other
	enemies_of_team1 = t0 + other

## 导弹管理器引用（CIWS 子弹需要碰撞导弹）
var missile_manager: Node = null

# ── 帧级共享缓存（CSG / 大量 CIWS 子弹场景优化）─────────────────
# 命中循环里的两条热路径都会被多颗子弹重复触发：
#  1. Aircraft.get_maneuver() / get_herbst() 每次走子节点遍历 → 缓存"是否处于免疫机动"
#  2. CIWS 子弹查 missile_manager.get_children() 选目标 → 缓存"按队伍分桶的敌方活跃导弹"
# 详见 SurvivorData.ENABLE_BULLET_FRAME_CACHE
var _frame_cache_filled: bool = false
var _frame_unit_immune: Dictionary = {}            ## unit_instance_id -> bool
var _frame_enemy_missiles_by_team: Dictionary = {} ## team(int) -> Array[Missile]
## 性能 HUD 用：当前活跃弹丸数（机炮 + 火箭弹合计，不含漂浮雷）
func active_bullet_count() -> int:
	return _bullets.size()

## 性能 HUD 用：当前活跃漂浮雷数
func active_torpedo_count() -> int:
	return _torpedoes.size()

## CIWS / 舰载武器复用："射手 team" → 敌方活跃导弹列表（NavalWeapons 也读）
func get_enemy_missiles_for_team(team: int) -> Array:
	if not SurvivorData.ENABLE_BULLET_FRAME_CACHE:
		return []
	if not _frame_cache_filled:
		_build_frame_cache()
	return _frame_enemy_missiles_by_team.get(team, [])

## 建缓存：每帧 _physics_process 顶部调一次
func _build_frame_cache() -> void:
	_frame_unit_immune.clear()
	_frame_enemy_missiles_by_team.clear()
	# 单位免疫：仅 Aircraft 需要查 cobra/herbst/missile_phase；其他 unit 默认 false
	for u in combat_unit_list:
		if u == null or not is_instance_valid(u):
			continue
		if not u is Aircraft:
			continue
		var ac := u as Aircraft
		var immune: bool = false
		var bm := ac.get_maneuver()
		if bm and (bm.is_active or (bm.is_used and ac.missile_phase_timer > 0.0)):
			immune = true
		else:
			var hm := ac.get_herbst()
			if hm and hm.is_active:
				immune = true
		_frame_unit_immune[ac.get_instance_id()] = immune
	# 敌方活跃导弹按 "射手 team" 视角分桶（每个 team key 存"对方导弹"）
	if missile_manager != null and is_instance_valid(missile_manager):
		var t0: Array = []  # team 0 视角下的敌方导弹（即 team != 0 的活跃导弹）
		var t1: Array = []
		for child in missile_manager.get_children():
			if not (child is Missile):
				continue
			var m: Missile = child as Missile
			# 渐隐中的导弹（_fading_out=true）已注定坠毁，CIWS 不再瞄它
			if not m.is_active or m._fading_out:
				continue
			if m.team == 0:
				t1.append(m)
			else:
				t0.append(m)
		_frame_enemy_missiles_by_team[0] = t0
		_frame_enemy_missiles_by_team[1] = t1
	_frame_cache_filled = true

## visual_only: 视觉装饰弹 —— 正常飞行 / 渲染 / 寿命结束，但跳过所有命中判定
## 用于制造"CIWS 密集弹幕"的观感，同时不影响平衡（真实伤害由另一部分子弹承担）
func spawn_bullet(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, is_ciws: bool = false, visual_only: bool = false) -> void:
	var speed_px := speed_ms * PIXELS_PER_METER
	var vel := Vector2(sin(direction), -cos(direction)) * speed_px
	# ⚠ 快照 team 到 dict：弹丸寿命中射手可能被释放，
	#   后续命中判定必须靠 source_team 而不是 source.team。
	# 建筑"从内向外射"规则：spawn 时源在街区内 → 永久免疫建筑拦截
	var spawn_in_b := false
	if is_instance_valid(source) and source.altitude < 3500.0:
		if source is Aircraft and (source as Aircraft).in_building:
			spawn_in_b = true
		elif BuildingRenderer.is_position_inside_building(origin):
			spawn_in_b = true
	var src_tier: int = 0
	if is_instance_valid(source):
		if source is GroundUnit or source is NavalUnit:
			src_tier = CombatUnit.AltitudeTier.GROUND
		else:
			src_tier = source.get_altitude_tier()
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
		"spawn_in_building": spawn_in_b,
		"source_tier": src_tier,
		"was_in_building": spawn_in_b,
	})

## 生成无制导火箭弹
## 与子弹共享物理，但命中半径略大、速度较慢、无伤害衰减、视觉独立
## prox_radius_m / aoe_radius_m / aoe_damage：可选近炸引信 + AOE，0 = 关闭
##
## ⚠ 火箭弹是独立武器类型（不是导弹）：
##   - 不会被 CIWS 拦截（CIWS 只扫 missile_manager.get_children()，rockets 不在那里）
##   - 不被 LaserEquipment 拦截（同上，激光只看 Missile 实例）
##   - 不走导弹伤害 cap（Aircraft.take_damage 只在 kind=="missile" 时套 survivor_missile_damage_cap）
func spawn_rocket(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, max_range_m: float, prox_radius_m: float = 0.0, aoe_radius_m: float = 0.0, aoe_damage: float = 0.0) -> void:
	var speed_px := speed_ms * PIXELS_PER_METER
	var vel := Vector2(sin(direction), -cos(direction)) * speed_px
	# 寿命 = 射程 / 初速；clamp 上限放到 10s 以容纳"长射程 + 高速"的玩家版火箭弹
	var life := clampf(max_range_m / maxf(speed_ms, 50.0), 1.5, 10.0)
	var spawn_in_b := false
	if is_instance_valid(source) and source.altitude < 3500.0:
		if source is Aircraft and (source as Aircraft).in_building:
			spawn_in_b = true
		elif BuildingRenderer.is_position_inside_building(origin):
			spawn_in_b = true
	var src_tier: int = 0
	if is_instance_valid(source):
		if source is GroundUnit or source is NavalUnit:
			src_tier = CombatUnit.AltitudeTier.GROUND
		else:
			src_tier = source.get_altitude_tier()
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
		"prox_radius_px": prox_radius_m * PIXELS_PER_METER,
		"aoe_radius_px": aoe_radius_m * PIXELS_PER_METER,
		"aoe_damage": aoe_damage,
		"min_damage_mult": 1.0,  ## 默认 1.0 = 无衰减；玩家方调用通过 spawn_rocket_with_falloff 覆盖
		"spawn_in_building": spawn_in_b,
		"source_tier": src_tier,
		"was_in_building": spawn_in_b,
	})

## 距离衰减版本：玩家版火箭弹专用，让"贴脸高伤、远端衰减"成为身份特征。
## 与 spawn_rocket 共享路径，只多设一个 min_damage_mult 字段，引爆/命中时按 flight_ratio 插值。
func spawn_rocket_with_falloff(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, max_range_m: float, prox_radius_m: float, aoe_radius_m: float, aoe_damage: float, min_damage_mult: float) -> void:
	spawn_rocket(origin, direction, speed_ms, source, damage, max_range_m, prox_radius_m, aoe_radius_m, aoe_damage)
	# 把刚 append 的最后一颗的 min_damage_mult 改写
	if not _bullets.is_empty():
		_bullets[_bullets.size() - 1]["min_damage_mult"] = min_damage_mult

## 玩家技能 SKILL_ROCKET_HOMING：把上一颗 spawn 的火箭弹标记为追踪型
## 由 AircraftWeapons._launch_rocket 在 spawn 后立即调用
func mark_last_rocket_homing() -> void:
	if _bullets.is_empty():
		return
	var b: Dictionary = _bullets[_bullets.size() - 1]
	if not b.get("is_rocket", false):
		return
	b["homing_active"] = true
	b["homing_target_id"] = 0
	b["homing_retarget_timer"] = 0.0

## 计算距离衰减倍率：基于 flight_ratio (1 - life/max_life) 在 [1.0, min_mult] 间线性插值
## 火箭弹直击 + AOE 引爆都共用这条公式。无 min_damage_mult 字段时返回 1.0。
static func _rocket_falloff_mult(b: Dictionary) -> float:
	var min_mult: float = float(b.get("min_damage_mult", 1.0))
	if min_mult >= 1.0:
		return 1.0
	var max_life: float = float(b.get("max_life", 0.0))
	if max_life <= 0.0:
		return 1.0
	var life: float = float(b.get("life", max_life))
	var flight_ratio: float = clampf(1.0 - life / max_life, 0.0, 1.0)
	return lerpf(1.0, min_mult, flight_ratio)

## 空中漂浮雷生成（A-10 实验武器，规避模式下飞机周围投下）
## 与火箭弹一样不被 CIWS / Laser 拦截 —— 独立武器槽
## drift_angle: 漂移方向（弧度，0=北）；drift_speed_ms: 漂移速度（m/s）
##
## 同屏上限：单个 source 最多 MAX_TORPEDOES_PER_SOURCE 颗，超出则放弃本次 spawn。
## 这样可以让"减 CD 升级"自然撞到天花板，不会无限堆积压垮性能 / 视觉。
func spawn_torpedo(origin: Vector2, drift_angle: float, drift_speed_ms: float, source: CombatUnit, params: TorpedoParams) -> void:
	if params == null:
		return
	# 上限检查：当前 source 名下的活跃漂浮雷计数
	var src_count := 0
	for t in _torpedoes:
		if t["source"] == source:
			src_count += 1
			if src_count >= MAX_TORPEDOES_PER_SOURCE:
				return
	var src_alt: float = source.altitude if is_instance_valid(source) else 5000.0
	# 漂移速度向量（像素/秒）：sin/-cos 与航向系一致
	var drift_vel_px: Vector2 = Vector2(sin(drift_angle), -cos(drift_angle)) * drift_speed_ms * PIXELS_PER_METER
	_torpedoes.append({
		"pos": origin,
		"drift_vel_px": drift_vel_px,    # 水平漂移速度（像素/秒，运行中可被弱追踪旋转）
		"source": source,
		"source_team": source.team if is_instance_valid(source) else -1,
		"params": params,
		"life": params.lifetime,
		"max_life": params.lifetime,
		"altitude": src_alt,
		"target_id": 0,                 # 0 = 未锁定目标（首帧立即扫描）
		"retarget_timer": 0.0,
	})

## 漂浮雷处理：漂移 + 缓降 + 弱追踪 + 近炸扫描
## 弱追踪：scan 内有敌人 → 慢速旋转 drift_vel 向其靠拢；同时**暂停寿命倒数**
## 没目标 → 纯漂移 + 寿命减少
func _update_torpedoes(delta: float) -> void:
	if _torpedoes.is_empty():
		return
	var i := _torpedoes.size() - 1
	while i >= 0:
		var t: Dictionary = _torpedoes[i]
		var tp: TorpedoParams = t["params"]
		var src_team: int = int(t["source_team"])

		# ── 目标重选（节流：retarget_timer > 0 用旧目标）──
		t["retarget_timer"] = float(t["retarget_timer"]) - delta
		var target: CombatUnit = null
		var tid: int = int(t["target_id"])
		if tid != 0:
			var inst: Object = instance_from_id(tid)
			if inst != null and is_instance_valid(inst):
				var maybe_target: CombatUnit = inst as CombatUnit
				if maybe_target != null and not maybe_target.is_destroyed:
					target = maybe_target
		if target == null or t["retarget_timer"] <= 0.0:
			target = _torpedo_pick_target_in_range(t, src_team, tp.tracking_scan_range_m)
			t["target_id"] = target.get_instance_id() if target != null else 0
			t["retarget_timer"] = tp.retarget_interval

		# ── 弱追踪：把 drift_vel 慢慢旋转到指向目标的方向（保持原速度大小）──
		if target != null:
			var to_t: Vector2 = target.global_position - t["pos"]
			if to_t.length_squared() > 0.01:
				var desired_angle: float = atan2(to_t.x, -to_t.y)
				var v: Vector2 = t["drift_vel_px"]
				var current_angle: float = atan2(v.x, -v.y)
				var diff: float = wrapf(desired_angle - current_angle, -PI, PI)
				var max_turn: float = deg_to_rad(tp.tracking_turn_rate_dps) * delta
				var new_angle: float
				if absf(diff) <= max_turn:
					new_angle = desired_angle
				else:
					new_angle = current_angle + signf(diff) * max_turn
				var spd: float = v.length()
				t["drift_vel_px"] = Vector2(sin(new_angle), -cos(new_angle)) * spd

		# ── 寿命：仅在没目标时倒数（追踪中暂停）──
		if target == null:
			t["life"] = float(t["life"]) - delta
			if t["life"] <= 0.0:
				_torpedoes.remove_at(i)
				i -= 1
				continue

		# ── 漂移位移 ──
		t["pos"] += t["drift_vel_px"] * delta

		# ── 缓降 ──
		t["altitude"] = float(t["altitude"]) - tp.descent_rate * delta

		# ── 近炸引信扫描（与火箭弹同语义）──
		var prox_r_px: float = tp.proximity_fuse_radius * PIXELS_PER_METER
		var t_alt: float = float(t["altitude"])
		var prox_triggered := false
		for u in combat_unit_list:
			if not is_instance_valid(u) or u.is_destroyed:
				continue
			if u.team == src_team:
				continue
			if u is Aircraft and (u as Aircraft).is_cloaked:
				continue
			var d: float = t["pos"].distance_to(u.global_position)
			if d > prox_r_px:
				continue
			# 高度容差（地面/海面忽略）
			if not flat_altitude_mode and not (u is GroundUnit) and not (u is NavalUnit):
				if absf(t_alt - u.altitude) > ALT_TOLERANCE:
					continue
			prox_triggered = true
			break

		if prox_triggered:
			_explode_torpedo(t)
			_torpedoes.remove_at(i)
			i -= 1
			continue

		i -= 1

## 漂浮雷目标选择：在 scan_range 内挑最近的敌方（含地面）
## 节流由调用方控制（retarget_timer），这里纯线性扫描
func _torpedo_pick_target_in_range(t: Dictionary, src_team: int, scan_range_m: float) -> CombatUnit:
	var scan_r_px: float = scan_range_m * PIXELS_PER_METER
	var pos: Vector2 = t["pos"]
	var best: CombatUnit = null
	var best_d: float = scan_r_px
	for u in combat_unit_list:
		if not is_instance_valid(u) or u.is_destroyed:
			continue
		if u.team == src_team:
			continue
		if u is Aircraft and (u as Aircraft).is_cloaked:
			continue
		var d: float = pos.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

## 漂浮雷引爆：直接复用 _explode_rocket 的 AOE 逻辑（同语义：半径内统一伤害）
## 玩家技能 SKILL_TORPEDO_AOE_JAM 命中时再向外发一圈 JAM
func _explode_torpedo(t: Dictionary) -> void:
	var tp: TorpedoParams = t["params"]
	# 构造一个临时 dict 喂给 _explode_rocket（aoe 字段语义一致）
	var fake_b := {
		"source": t["source"],
		"source_team": t["source_team"],
		"altitude": t["altitude"],
		"aoe_radius_px": tp.aoe_radius * PIXELS_PER_METER,
		"aoe_damage": tp.aoe_damage,
	}
	_explode_rocket(fake_b, t["pos"])

	# 玩家技能：漂浮雷引爆后范围干扰（类似热诱弹的 SKILL_FLARE_AOE_JAM）
	var src: CombatUnit = t["source"]
	if not is_instance_valid(src) or src.team != 0 or not src is Aircraft:
		return
	var ac: Aircraft = src as Aircraft
	if not ac.has_meta("upgrade_stacks"):
		return
	var stacks: Dictionary = ac.get_meta("upgrade_stacks")
	if int(stacks.get(SkillHooks.SKILL_TORPEDO_AOE_JAM, 0)) <= 0:
		return
	var hits: int = AOEBroadcast.apply_status_in_radius(
		t["pos"],
		SkillHooks.TORPEDO_AOE_JAM_RADIUS_PX,
		1, StatusEffects.JAM,
		SkillHooks.TORPEDO_AOE_JAM_DURATION,
		ac)
	SkillHooks.on_player_jam_landed(ac, hits)

## 火箭弹引爆：在指定位置应用 AOE 伤害 + VFX
## 由近炸引信触发或直接命中后调用
## exclude_unit：直接命中时已扣血的单位，避免双重计算
func _explode_rocket(b: Dictionary, world_pos: Vector2, exclude_unit: CombatUnit = null) -> void:
	var aoe_r: float = float(b.get("aoe_radius_px", 0.0))
	# AOE 伤害也按距离衰减（玩家版火箭弹身份特征）；min_damage_mult=1 时 mult=1.0 不变
	var falloff_mult: float = _rocket_falloff_mult(b)
	var aoe_dmg: float = float(b.get("aoe_damage", 0.0)) * falloff_mult
	var src_team: int = int(b.get("source_team", -1))
	var src_alive: bool = is_instance_valid(b["source"])
	# VFX 缩放：AOE 大小决定爆炸尺寸（aoe 100px ≈ scale 1.4）
	var vfx_scale: float = 1.0 if aoe_r <= 0.0 else clampf(aoe_r / 80.0, 0.8, 2.0)
	ExplosionVFXScript.emit(get_tree(), world_pos, 0.0, vfx_scale)
	if aoe_r <= 0.0 or aoe_dmg <= 0.0:
		return
	# AOE 杀伤：扫所有敌方单位，半径内统一伤害（不衰减，简洁）
	var rocket_alt: float = float(b.get("altitude", 5000.0))
	for unit in combat_unit_list:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit == exclude_unit:
			continue
		if unit.team == src_team:
			continue
		# 跳过免疫（cobra/herbst 等）
		if unit is Aircraft:
			if SurvivorData.ENABLE_BULLET_FRAME_CACHE:
				if _frame_unit_immune.get(unit.get_instance_id(), false):
					continue
			if (unit as Aircraft).is_cloaked:
				continue
		var d2: float = world_pos.distance_to(unit.global_position)
		if d2 > aoe_r:
			continue
		# 高度容差（地面/海面单位忽略）
		if not flat_altitude_mode and not (unit is GroundUnit) and not (unit is NavalUnit):
			if absf(rocket_alt - unit.altitude) > ALT_TOLERANCE:
				continue
		if src_alive and unit is Aircraft:
			unit.set_meta("_pending_attacker", b["source"])
		if unit is NavalUnit:
			if src_alive:
				(unit as NavalUnit).set_meta("_pending_attacker", b["source"])
				(unit as NavalUnit).set_meta("_last_damage_kind", "rocket")
			(unit as NavalUnit).take_damage_at(aoe_dmg, world_pos, 0.5, true)
		else:
			unit.take_damage(aoe_dmg, b["source"], "rocket")

func _physics_process(delta: float) -> void:
	# ── 帧级缓存：每帧重建一次，所有子弹共用 ──
	_frame_cache_filled = false
	if SurvivorData.ENABLE_BULLET_FRAME_CACHE:
		_build_frame_cache()
	# ── 敌我方预分桶：从 combat_unit_list 自建（与谁设 combat_unit_list 解耦，沙盒亦安全）──
	# team-0/1 子弹只扫对方阵营，把命中循环从 O(B×N) 降到 O(B×N_enemy)
	_rebuild_team_buckets()

	# ── 空中鱼雷（独立循环，不污染子弹热路径）──
	_update_torpedoes(delta)

	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]

		# 玩家技能 SKILL_ROCKET_HOMING：标记的火箭弹做轻微转向追踪
		# 节流：retarget_timer 0.4s 一次；scan 1200m 半径选最近敌方；速度大小不变
		if b.get("homing_active", false):
			b["homing_retarget_timer"] = float(b.get("homing_retarget_timer", 0.0)) - delta
			var src_team_h: int = int(b.get("source_team", -1))
			var hid: int = int(b.get("homing_target_id", 0))
			var htgt: CombatUnit = null
			if hid != 0:
				var hi: Object = instance_from_id(hid)
				if hi != null and is_instance_valid(hi):
					var maybe: CombatUnit = hi as CombatUnit
					if maybe != null and not maybe.is_destroyed:
						htgt = maybe
			if htgt == null or float(b["homing_retarget_timer"]) <= 0.0:
				htgt = _torpedo_pick_target_in_range(b, src_team_h, SkillHooks.ROCKET_HOMING_SCAN_PX / PIXELS_PER_METER)
				b["homing_target_id"] = htgt.get_instance_id() if htgt != null else 0
				b["homing_retarget_timer"] = SkillHooks.ROCKET_HOMING_RETARGET_INTERVAL
			if htgt != null:
				var to_h: Vector2 = htgt.global_position - b["pos"]
				if to_h.length_squared() > 0.01:
					var desired_h: float = atan2(to_h.x, -to_h.y)
					var v_h: Vector2 = b["vel"]
					var cur_h: float = atan2(v_h.x, -v_h.y)
					var diff_h: float = wrapf(desired_h - cur_h, -PI, PI)
					var max_t: float = deg_to_rad(SkillHooks.ROCKET_HOMING_TURN_DPS) * delta
					var new_h: float
					if absf(diff_h) <= max_t:
						new_h = desired_h
					else:
						new_h = cur_h + signf(diff_h) * max_t
					var spd_h: float = v_h.length()
					b["vel"] = Vector2(sin(new_h), -cos(new_h)) * spd_h

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

		# 近炸引信（仅火箭弹，prox_radius > 0 启用）
		# 在直接命中检测之前扫一圈：靠近敌方就引爆，触发 AOE
		if b.get("is_rocket", false):
			var prox_r: float = float(b.get("prox_radius_px", 0.0))
			if prox_r > 0.0:
				var src_team_p: int = int(b.get("source_team", -1))
				var rocket_alt_p: float = float(b.get("altitude", 5000.0))
				var prox_triggered := false
				for u_check in combat_unit_list:
					if not is_instance_valid(u_check) or u_check.is_destroyed:
						continue
					if u_check.team == src_team_p:
						continue
					if u_check is Aircraft and (u_check as Aircraft).is_cloaked:
						continue
					var d_check: float = b["pos"].distance_to(u_check.global_position)
					if d_check > prox_r:
						continue
					# 高度容差（地面/海面忽略）
					if not flat_altitude_mode and not (u_check is GroundUnit) and not (u_check is NavalUnit):
						if absf(rocket_alt_p - u_check.altitude) > ALT_TOLERANCE:
							continue
					prox_triggered = true
					break
				if prox_triggered:
					_explode_rocket(b, b["pos"])
					_bullets.remove_at(i)
					i -= 1
					continue

		# 建筑遮挡（按 source 高度档位查表的单次进入 roll）
		# 进入街区那一帧 roll 一次，roll 失败的子弹本次穿楼期间不再 roll
		# 离开街区后下次进入再 roll
		var b_alt: float = float(b["altitude"])
		if b_alt < 3500.0 and not b.get("spawn_in_building", false):
			var bullet_in_b: bool = BuildingRenderer.is_position_inside_building(b["pos"])
			var was_in: bool = b.get("was_in_building", false)
			if bullet_in_b and not was_in:
				var src_tier: int = int(b.get("source_tier", 0))
				var p := _building_block_prob_for_tier(src_tier)
				if randf() < p:
					if b.get("is_rocket", false):
						ExplosionVFXScript.emit(get_tree(), b["pos"], 0.0, 0.6)
						AudioManager.play_sfx_2d("bomb_distant", b["pos"], 5.0)
					_bullets.remove_at(i)
					i -= 1
					continue
			b["was_in_building"] = bullet_in_b

		# 命中检测
		# ⚠ 不能直接给带类型变量赋值 b["source"]：如果射手已被释放，
		#   Godot 会抛 "Trying to assign invalid previously freed instance"。
		#   先用 Variant 接住，再查 validity；team 已在 spawn 时快照到 dict。
		var hit := false
		var source_raw: Variant = b["source"]
		var source_alive: bool = is_instance_valid(source_raw)
		var source_team: int = int(b.get("source_team", -1))
		# 敌我方预分桶：team-0/1 射手只扫对方阵营（避免 O(B×N) 全扫）；其他（source_team=-1）回退全表
		var hit_candidates: Array[CombatUnit]
		if source_team == 0:
			hit_candidates = enemies_of_team0
		elif source_team == 1:
			hit_candidates = enemies_of_team1
		else:
			hit_candidates = combat_unit_list
		for ac in hit_candidates:
			if not is_instance_valid(ac) or ac.is_destroyed:
				continue
			# 射手还活着：跳过打到自己
			if source_alive and ac == source_raw:
				continue
			# 跳过同队（无论射手死活都用快照 team 判定；分桶后正常永不触发，回退路径仍需）
			if ac.team == source_team:
				continue
			# 光学隐形：子弹/火箭弹穿过隐形目标
			if ac is Aircraft and ac.is_cloaked:
				continue
			# 战术机动中及结束后缓冲期内免疫所有弹药（cobra / herbst / 命中后窗口）
			# 帧级缓存：避免每颗子弹都重复 get_maneuver()/get_herbst() 的子节点遍历
			if ac is Aircraft:
				if SurvivorData.ENABLE_BULLET_FRAME_CACHE:
					if _frame_unit_immune.get(ac.get_instance_id(), false):
						continue
				else:
					var _bm = ac.get_maneuver()
					if _bm and (_bm.is_active or (_bm.is_used and ac.missile_phase_timer > 0.0)):
						continue
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
				else:
					# 火箭：按 RocketParams.min_damage_mult 在 [1.0, min_mult] 间线性衰减
					# 默认（敌方 AI 火箭）= 1.0 不衰减；玩家版 0.6-0.8 让贴脸高伤、远端略低
					dmg_mult = _rocket_falloff_mult(b)
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
				# 归因：把射手写到目标 meta，aircraft._record_kill_attribution 在致死时读取
				if is_instance_valid(b["source"]) and ac is Aircraft:
					ac.set_meta("_pending_attacker", b["source"])
				if is_rocket:
					# 火箭不进入子弹闪避系统
					# 爆炸 + AOE 一并处理（_explode_rocket 内部判断 aoe_radius，无 AOE 时仅出 VFX）
					_explode_rocket(b, ac.global_position, ac)
					if ac is NavalUnit:
						# 火箭对船体总血削 50%，可以打穿弱点（破甲效果）
						if is_instance_valid(b["source"]):
							(ac as NavalUnit).set_meta("_pending_attacker", b["source"])
							(ac as NavalUnit).set_meta("_last_damage_kind", "rocket")
						(ac as NavalUnit).take_damage_at(actual_dmg, b["pos"], 0.5, true)
					else:
						ac.take_damage(actual_dmg, b["source"], "rocket")
				elif ac is Aircraft:
					# take_bullet_damage 内部 set_meta("_last_damage_kind", "gun")，这里继续保留旧入口
					# attacker 传入用于"对头机炮闪避"几何检查
					ac.take_bullet_damage(b["damage"] * dmg_mult, b["source"])
				elif ac is NavalUnit:
					# 机炮子弹：
					#   - 总血削 15%（高射速高伤害 → 低总血贡献，避免一梭子秒船）
					#   - 弱点可被机炮磨爆（can_hit_weak_point=true）—— 弱点有 HP 不是"导弹斩杀点"
					#   - 挂点仍然按全额扣（机炮剥部件依然有效）
					if is_instance_valid(b["source"]):
						(ac as NavalUnit).set_meta("_pending_attacker", b["source"])
						(ac as NavalUnit).set_meta("_last_damage_kind", "gun")
					(ac as NavalUnit).take_damage_at(b["damage"] * dmg_mult, b["pos"], 0.15, true)
				else:
					ac.take_damage(b["damage"] * dmg_mult, b["source"], "gun")
				hit = true
				break

		# CIWS 子弹 vs 敌方导弹碰撞（仅带 is_ciws 标记的子弹）
		# 伤害按"导弹到源（防守方）的距离"衰减：
		#   - 导弹离防守单位很近（< 250 px，约末端引信距离）→ 满伤害
		#   - 远距（> 800 px）→ 0 伤害（bullets 只是装饰，穿过导弹不受影响）
		# 避免"玩家刚发射导弹就被 CIWS 的在飞子弹拦下"的反直觉场景
		if not hit and b.get("is_ciws", false) and missile_manager:
			# 帧级缓存：用预过滤的"敌方活跃导弹"列表替代每颗子弹独自 get_children() 扫
			var enemy_missiles: Array
			if SurvivorData.ENABLE_BULLET_FRAME_CACHE:
				enemy_missiles = _frame_enemy_missiles_by_team.get(source_team, [])
			else:
				enemy_missiles = []
				for child in missile_manager.get_children():
					if (child is Missile) and (child as Missile).is_active and (child as Missile).team != source_team:
						enemy_missiles.append(child)
			for m_var in enemy_missiles:
				if not is_instance_valid(m_var):
					continue
				var msl: Missile = m_var as Missile
				if msl == null or not msl.is_active:
					continue
				var dist_m: float = Vector2(b["pos"]).distance_to(msl.global_position)
				if dist_m < HIT_RADIUS:
					# 距离衰减因子：导弹离 CIWS 发射源越近，拦截伤害越高
					var msl_to_src: float = 9999.0
					var factor: float = 0.0
					if source_alive:
						msl_to_src = msl.global_position.distance_to(source_raw.global_position)
						factor = clampf((800.0 - msl_to_src) / 550.0, 0.0, 1.0)
					# 累积伤害到 intercept_hp；归零才真正击落
					var dmg: float = float(b["damage"]) * factor
					if dmg > 0.0:
						msl.intercept_hp -= dmg
						if msl.intercept_hp <= 0.0:
							# CIWS 拦截无爆炸 VFX → 走渐隐 coasting，与寿命到期保持一致视觉
							msl._start_fade_out()
							EventLogger.log_event("CIWS", "Player",
								"intercepted missile (final dist=%.0f, factor=%.2f)" % [msl_to_src, factor])
					hit = true
					break

		if hit:
			_bullets.remove_at(i)

		i -= 1

	# MultiMesh 路径：每帧把存活的 tracer 写到 GPU 实例（flag 关时零开销）
	if GameConstants.USE_MULTIMESH_BULLETS:
		_update_multimesh_tracers()

	queue_redraw()

func _draw() -> void:
	var skip_tracer := GameConstants.USE_MULTIMESH_BULLETS  # tracer 已走 MultiMesh
	for b in _bullets:
		var dir: Vector2 = b["vel"].normalized()
		# 寿命末段淡出（替代瞬间消失）
		var life_left: float = float(b["life"])
		var fade: float = clampf(life_left / FADE_OUT_DURATION, 0.0, 1.0)
		if b.get("is_rocket", false):
			# 火箭：橙红色较长尾迹 + 亮白头（永远走 _draw，MultiMesh 不接管）
			var tail: Vector2 = b["pos"] - dir * ROCKET_TRAIL_LENGTH
			draw_line(b["pos"], tail, Color(1.0, 0.45, 0.15, 0.85 * fade), 2.2, true)
			draw_circle(b["pos"], 2.0, Color(1.0, 0.95, 0.8, fade))
		elif not skip_tracer:
			# 曳光弹：亮黄色短线（flag 关时走 _draw 老路径）
			var tail: Vector2 = b["pos"] - dir * TRACER_LENGTH
			draw_line(b["pos"], tail, Color(1.0, 0.95, 0.4, 0.9 * fade), 1.5, true)

	# 空中漂浮雷：弹体 + 上方降落伞罩（半圆 + 两根伞线）
	for t in _torpedoes:
		var pos: Vector2 = t["pos"]
		var tp: TorpedoParams = t["params"]
		var canopy_col: Color = tp.canopy_color
		var body_col: Color = tp.body_color
		# 寿命末段淡出
		var life_left_t: float = float(t["life"])
		var fade_t: float = clampf(life_left_t / 0.6, 0.0, 1.0)
		# 弹体（小圆）
		draw_circle(pos, 3.0, Color(body_col.r, body_col.g, body_col.b, body_col.a * fade_t))
		# 降落伞罩：屏幕上方 8 px 处一段弧线（用 polyline 模拟）
		var canopy_center := pos + Vector2(0, -8.0)
		var canopy_pts := PackedVector2Array([
			canopy_center + Vector2(-5, 1),
			canopy_center + Vector2(-3, -2),
			canopy_center + Vector2(0, -3),
			canopy_center + Vector2(3, -2),
			canopy_center + Vector2(5, 1),
		])
		draw_polyline(canopy_pts, Color(canopy_col.r, canopy_col.g, canopy_col.b, canopy_col.a * fade_t), 1.5, true)
		# 两根伞线
		draw_line(canopy_pts[0], pos, Color(canopy_col.r, canopy_col.g, canopy_col.b, 0.5 * fade_t), 1.0, true)
		draw_line(canopy_pts[4], pos, Color(canopy_col.r, canopy_col.g, canopy_col.b, 0.5 * fade_t), 1.0, true)
