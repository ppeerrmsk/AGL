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
const StrategicTargetScript = preload("res://scripts/strategic_target.gd")

## 机炮命中火星：每目标独立节流、单管理器批量绘制，不创建粒子节点。
const HIT_SPARK_DURATION: float = 0.16
const HIT_SPARK_COOLDOWN_MS: int = 110
const MAX_HIT_SPARKS: int = 12
const HIT_SPARK_READY_META: StringName = &"_gun_hit_spark_ready_ms"

## 友方（team 0）弹丸覆盖参数，由生存模式设置
var friendly_hit_radius: float = HIT_RADIUS
var friendly_dmg_full_ratio: float = 0.3   ## 满伤害飞行比例
var friendly_dmg_min_mult: float = 0.2     ## 最远端伤害倍率
var flat_altitude_mode: bool = false       ## 扁平高度模式：跳过高度容差检查

## 弹丸数据：{ pos: Vector2, vel: Vector2, owner: CombatUnit, damage: float, life: float }
var _bullets: Array[Dictionary] = []
var _hit_sparks: Array[Dictionary] = []  ## {pos, age, angle, scale}

## 装饰弹软上限（②，2026-07-24 航母群掉帧修复）：
## 到达上限后**只拒绝新的 visual_only 装饰弹**，真弹 / 火箭永远照常生成（不影响平衡与命中）。
## 装饰弹占 CIWS 出弹的 2/3，封住它就封住了弹幕洪峰；真弹本就受 1/3 射速 + 2s 寿命自然限量。
const MAX_BULLETS: int = 1200

## 命中广相网格（③）：把命中循环从"每弹扫全场"降到"每弹扫 3×3 邻格 + 少量大单位"。
## 详见 scripts/util/unit_grid.gd。GRID_CELL_SIZE 必须 >= 最大小单位命中半径（当前 friendly 20px）。
const GRID_CELL_SIZE: float = 256.0
var _unit_grid: UnitGrid = UnitGrid.new()
var _grid_buf: Array = []   ## 命中循环复用的候选缓冲（大单位 + 邻格小单位），每弹 clear 后重填

## 空中漂浮雷（独立数组，不污染子弹热路径）
## 数据结构：{ pos, drift_vel_px, source, source_team, params, target_id,
##            retarget_timer, life, altitude }
var _torpedoes: Array[Dictionary] = []
## 重型炸弹 / 空爆弹独立数组，避免向普通子弹热路径堆叠分支。
var _bombs: Array[Dictionary] = []
var _airburst_shells: Array[Dictionary] = []
var _area_flashes: Array[Dictionary] = []
## 同屏上限：每个 source 各自最多 21 颗（玩家有技能减 CD 后的极限值）
const MAX_TORPEDOES_PER_SOURCE: int = 21


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
	# 敌方活跃导弹按 "射手 team" 视角分桶（每个 team key 存"敌对阵营的导弹"）
	# 阵营语义（IFF）：HOSTILE(1) 的导弹威胁 PLAYER(0)/ALLY(2)；0/2 的导弹威胁 1
	if missile_manager != null and is_instance_valid(missile_manager):
		var t_friendly_side: Array = []  # 对 0/2 阵营构成威胁的导弹（即 HOSTILE 发射的）
		var t_hostile_side: Array = []   # 对 1 阵营构成威胁的导弹（即 0/2 发射的）
		for child in missile_manager.get_children():
			if not (child is Missile):
				continue
			var m: Missile = child as Missile
			# 渐隐中的导弹（_fading_out=true）已注定坠毁，CIWS 不再瞄它
			if not m.is_active or m._fading_out:
				continue
			if m.team == CombatUnit.TEAM_HOSTILE:
				t_friendly_side.append(m)
			else:
				t_hostile_side.append(m)
		_frame_enemy_missiles_by_team[CombatUnit.TEAM_PLAYER] = t_friendly_side
		_frame_enemy_missiles_by_team[CombatUnit.TEAM_ALLY] = t_friendly_side
		_frame_enemy_missiles_by_team[CombatUnit.TEAM_HOSTILE] = t_hostile_side
	_frame_cache_filled = true

## visual_only: 视觉装饰弹 —— 正常飞行 / 渲染 / 寿命结束，但跳过所有命中判定
## 用于制造"CIWS 密集弹幕"的观感，同时不影响平衡（真实伤害由另一部分子弹承担）
func spawn_bullet(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit, damage: float, is_ciws: bool = false, visual_only: bool = false, life_seconds: float = 2.0) -> void:
	# 装饰弹软上限：弹幕洪峰时丢弃多余的纯视觉弹，真弹不受影响（②）
	if visual_only and _bullets.size() >= MAX_BULLETS:
		return
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
		"life": life_seconds,
		"max_life": life_seconds,
		"altitude": source.altitude if is_instance_valid(source) else 5000.0,
		"is_rocket": false,
		"is_ciws": is_ciws,
		"visual_only": visual_only,
		"spawn_in_building": spawn_in_b,
		"source_tier": src_tier,
		"was_in_building": spawn_in_b,
	})

## 轰炸机炸弹：保留释放瞬间 85% 平面速度，定时落地后只伤敌对地面单位。
func spawn_bomber_bomb(origin: Vector2, horizontal_velocity_px: Vector2, source: CombatUnit,
		fall_time: float = 3.2, radius_m: float = 160.0, damage: float = 75.0) -> void:
	_bombs.append({
		"pos": origin,
		"vel": horizontal_velocity_px,
		"source": source,
		"source_team": source.team if is_instance_valid(source) else -1,
		"life": fall_time,
		"max_life": fall_time,
		"start_altitude": source.altitude if is_instance_valid(source) else 10000.0,
		"radius_px": radius_m * PIXELS_PER_METER,
		"damage": damage,
	})

## 远距高炮空爆弹：冻结方向和引信时间，飞行中不再修正。
func spawn_airburst_shell(origin: Vector2, direction: float, speed_ms: float, source: CombatUnit,
		fuse_time: float, burst_altitude: float, radius_m: float = 220.0,
		damage: float = 75.0, burst_id: int = 0) -> void:
	var vel := Vector2(sin(direction), -cos(direction)) * speed_ms * PIXELS_PER_METER
	_airburst_shells.append({
		"pos": origin, "vel": vel, "source": source,
		"source_team": source.team if is_instance_valid(source) else -1,
		"life": maxf(fuse_time, 0.1), "max_life": maxf(fuse_time, 0.1),
		"altitude": burst_altitude, "radius_px": radius_m * PIXELS_PER_METER,
		"damage": damage, "burst_id": burst_id,
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
			if not CombatUnit.teams_hostile(u.team, src_team):
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
		if not CombatUnit.teams_hostile(u.team, src_team):
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
	if not is_instance_valid(src) or not src.is_player_squad() or not src is Aircraft:
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
		if not CombatUnit.teams_hostile(unit.team, src_team):
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
			unit.take_damage(aoe_dmg, CombatUnit.safe_attacker(b["source"]), "rocket")

func _update_special_projectiles(delta: float) -> void:
	var i := _bombs.size() - 1
	while i >= 0:
		var b: Dictionary = _bombs[i]
		b["pos"] = Vector2(b["pos"]) + Vector2(b["vel"]) * delta
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0.0:
			_explode_bomber_bomb(b)
			_bombs.remove_at(i)
		i -= 1

	i = _airburst_shells.size() - 1
	while i >= 0:
		var shell: Dictionary = _airburst_shells[i]
		shell["pos"] = Vector2(shell["pos"]) + Vector2(shell["vel"]) * delta
		shell["life"] = float(shell["life"]) - delta
		if float(shell["life"]) <= 0.0:
			_explode_airburst_shell(shell)
			_airburst_shells.remove_at(i)
		i -= 1

	i = _area_flashes.size() - 1
	while i >= 0:
		_area_flashes[i]["age"] = float(_area_flashes[i]["age"]) + delta
		if float(_area_flashes[i]["age"]) >= float(_area_flashes[i]["duration"]):
			_area_flashes.remove_at(i)
		i -= 1


func _explode_bomber_bomb(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var radius_px: float = float(b["radius_px"])
	var source_team: int = int(b["source_team"])
	var attacker: Node = CombatUnit.safe_attacker(b.get("source"))
	_grid_buf.clear()
	_unit_grid.query_into(pos, _grid_buf)
	for unit in _grid_buf:
		if not is_instance_valid(unit) or unit.is_destroyed or not (unit is GroundUnit):
			continue
		if not CombatUnit.teams_hostile(source_team, unit.team):
			continue
		if pos.distance_to(unit.global_position) > radius_px:
			continue
		if unit.get_script() == StrategicTargetScript:
			unit.take_bomber_damage(float(b["damage"]), source_team, attacker)
		else:
			unit.take_damage(float(b["damage"]), attacker, "bomber_bomb")
	_area_flashes.append({"pos": pos, "radius": radius_px, "age": 0.0, "duration": 0.85, "kind": "bomb"})
	ExplosionVFXScript.emit(get_tree(), pos, 0.0, 1.2)
	AudioManager.play_sfx_2d("bomb_distant", pos, 7.0)
	EventLogger.log_event("BOMB", "Impact", "pos=%s r=%.0fm team=%d" % [pos, radius_px / PIXELS_PER_METER, source_team])


func _explode_airburst_shell(shell: Dictionary) -> void:
	var pos: Vector2 = shell["pos"]
	var radius_px: float = float(shell["radius_px"])
	var source_team: int = int(shell["source_team"])
	var burst_altitude: float = float(shell["altitude"])
	var attacker: Node = CombatUnit.safe_attacker(shell.get("source"))
	_grid_buf.clear()
	_unit_grid.query_into(pos, _grid_buf)
	for unit in _grid_buf:
		if not is_instance_valid(unit) or unit.is_destroyed or not (unit is Aircraft):
			continue
		if not CombatUnit.teams_hostile(source_team, unit.team):
			continue
		if pos.distance_to(unit.global_position) > radius_px or absf(unit.altitude - burst_altitude) > 1000.0:
			continue
		unit.take_damage(float(shell["damage"]), attacker, "airburst")
	_area_flashes.append({
		"pos": pos,
		"radius": radius_px,
		"age": 0.0,
		"duration": 1.2,
		"kind": "airburst",
		# 三连发共用 burst_id，但爆点不同；把坐标混入后可得到逐弹稳定、不跳动的烟团形状。
		"visual_seed": int(shell["burst_id"]) * 31 + int(round(pos.x * 3.0 + pos.y * 5.0)),
	})
	AudioManager.play_sfx_2d("bomb_distant", pos, 5.0)
	EventLogger.log_event("AIRBURST", "Flak", "burst=%d pos=%s alt=%.0f" % [int(shell["burst_id"]), pos, burst_altitude])


func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_update_hit_sparks(delta)
	# ── 帧级缓存：每帧重建一次，所有子弹共用 ──
	_frame_cache_filled = false
	if SurvivorData.ENABLE_BULLET_FRAME_CACHE:
		_build_frame_cache()

	# ── 命中广相网格：每物理帧按当前单位位置重建一次，所有真弹共用（③）──
	# 小单位入格 / 大单位（NavalUnit）进 large_units 线性表。命中循环只查邻格 + 大单位。
	_unit_grid.rebuild(combat_unit_list, GRID_CELL_SIZE)
	_update_special_projectiles(delta)

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
					if not CombatUnit.teams_hostile(u_check.team, src_team_p):
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
		# 广相候选集（③）：大单位（NavalUnit）恒扫 + 本弹位置 3×3 邻格的小单位。
		# 等价于旧的"遍历 combat_unit_list"，但候选从全场缩到近邻（无漏判证明见 test_bullet_grid）。
		# ⚠ 候选是本帧快照，循环内仍保留 is_instance_valid + is_destroyed 守卫（同帧可能已被别的弹击毁）。
		_grid_buf.clear()
		_grid_buf.append_array(_unit_grid.large_units)
		_unit_grid.query_into(b["pos"], _grid_buf)
		for ac in _grid_buf:
			if not is_instance_valid(ac) or ac.is_destroyed:
				continue
			# 射手还活着：跳过打到自己
			if source_alive and ac == source_raw:
				continue
			# 跳过非敌对阵营（无论射手死活都用快照 team 判定；PLAYER↔ALLY 互不误伤）
			if not CombatUnit.teams_hostile(ac.team, source_team):
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
				# 722 签名技能：无败之鹰（F-15 满血机炮 ×1.2）/ 对地特化（F-15E 对地面 ×1.3）
				if source_alive and source_raw is Aircraft:
					var sig_src := source_raw as Aircraft
					if sig_src.sig_f15_active and not is_rocket and sig_src.params \
							and sig_src.hp >= sig_src.params.max_hp * Aircraft.SIG_F15_HP_RATIO:
						dmg_mult *= Aircraft.SIG_F15_BONUS_MULT
					if sig_src.sig_f15e_active and not (ac is Aircraft):
						dmg_mult *= 1.3
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
				# 归因：把射手写到目标 meta，aircraft._record_kill_attribution 在致死时读取
				if is_instance_valid(b["source"]) and ac is Aircraft:
					ac.set_meta("_pending_attacker", b["source"])
				var damage_applied: bool = true
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
						ac.take_damage(actual_dmg, CombatUnit.safe_attacker(b["source"]), "rocket")
				elif ac is Aircraft:
					# false = 本发被闪避；此时不记命中、不出火星。
					# attacker 传入用于"对头机炮闪避"几何检查
					damage_applied = ac.take_bullet_damage(
						b["damage"] * dmg_mult, CombatUnit.safe_attacker(b["source"]))
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
					ac.take_damage(b["damage"] * dmg_mult, CombatUnit.safe_attacker(b["source"]), "gun")
				if is_rocket or damage_applied:
					var evt_tag := "ROCKET" if is_rocket else "GUN"
					EventLogger.log_event(evt_tag, src_name,
						"hit %s (dmg=%.1f)" % [tgt_name, actual_dmg])
					if not is_rocket:
						EventLogger.tally(src_name, "gun_hits")
						_emit_hit_spark(b["pos"], b["vel"], tgt_unit)
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
					if (child is Missile) and (child as Missile).is_active and CombatUnit.teams_hostile((child as Missile).team, source_team):
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

	queue_redraw()
	# 性能埋点（此前 BulletManager 全无 PerfBuckets 覆盖 → 帧时间盲区）：
	# 物理+命中循环耗时 + 当前子弹总数（CIWS 弹幕高峰用于诊断）
	PerfBuckets.tick("bullet_phys", Time.get_ticks_usec() - _t0)
	PerfBuckets.set_value("bullet_count", _bullets.size())

## 只推进当前短寿命火星；无火星时零循环开销。
func _update_hit_sparks(delta: float) -> void:
	var i := _hit_sparks.size() - 1
	while i >= 0:
		_hit_sparks[i]["age"] = float(_hit_sparks[i]["age"]) + delta
		if float(_hit_sparks[i]["age"]) >= HIT_SPARK_DURATION:
			_hit_sparks.remove_at(i)
		i -= 1


## 每个目标独立 CD，密集梭射只在弹流命中的开头给一次反馈。
func _emit_hit_spark(pos: Vector2, velocity: Vector2, target: CombatUnit) -> void:
	if not is_instance_valid(target):
		return
	var now_ms: int = Time.get_ticks_msec()
	var ready_ms: int = int(target.get_meta(HIT_SPARK_READY_META, 0))
	if now_ms < ready_ms:
		return
	target.set_meta(HIT_SPARK_READY_META, now_ms + HIT_SPARK_COOLDOWN_MS)
	if _hit_sparks.size() >= MAX_HIT_SPARKS:
		_hit_sparks.remove_at(0)
	_hit_sparks.append({
		"pos": pos,
		"age": 0.0,
		"angle": (-velocity).angle() + randf_range(-0.16, 0.16),
		"scale": randf_range(7.0, 10.0),
	})


func _draw() -> void:
	var _t0 := Time.get_ticks_usec()
	# 曳光弹批量绘制（性能守则 R3）：CIWS 弹幕高峰 ~1400 颗，原先逐颗 draw_line(抗锯齿)
	# = 1400 次 draw call/帧。收集成线段对，一次 draw_multiline 提交（与 naval_unit
	# 边缘线"48 段一调用"同款、已验证可用的 API）。火箭数量少且带圆头/淡出 → 保留逐颗。
	# ⚠ 用单色 draw_multiline，不用 draw_multiline_colors —— 后者 colors 数组长度语义
	#   （逐点 vs 逐段）在不同 Godot 版本不一致，长度不匹配会【静默不画】(曾致曳光弹全消失)。
	#   代价：曳光弹放弃逐颗末段淡出（改为寿命到点瞬间消失，密集弹幕里几乎不可见）。
	var tracer_pts := PackedVector2Array()
	# 重型炸弹：随落地进度略微放大；空爆弹使用冷白短曳光，和普通黄弹流区分。
	for bomb in _bombs:
		var progress: float = 1.0 - float(bomb["life"]) / maxf(float(bomb["max_life"]), 0.01)
		draw_circle(bomb["pos"], lerpf(2.0, 4.5, progress), Color(0.95, 0.72, 0.28, 0.95))
		draw_line(bomb["pos"], bomb["pos"] - Vector2(bomb["vel"]).normalized() * 10.0,
			Color(0.35, 0.25, 0.15, 0.7), 2.0)
	for shell in _airburst_shells:
		var sdir: Vector2 = Vector2(shell["vel"]).normalized()
		draw_line(shell["pos"], shell["pos"] - sdir * 12.0, Color(0.78, 0.9, 1.0, 0.9), 1.8)
	for flash in _area_flashes:
		var ft: float = clampf(float(flash["age"]) / maxf(float(flash["duration"]), 0.01), 0.0, 1.0)
		var flash_pos: Vector2 = flash["pos"]
		if flash["kind"] == "bomb":
			var fr: float = float(flash["radius"]) * ease(ft, -1.5)
			var fc := Color(1.0, 0.58, 0.18, (1.0 - ft) * 0.75)
			draw_arc(flash_pos, maxf(fr, 2.0), 0, TAU, 36, fc, 2.0)
			draw_arc(flash_pos, maxf(fr * 0.65, 1.0), 0, TAU, 28, fc, 1.0)
			continue

		# Flak 不能画成水波：先给一个短促放射爆心，再留下不规则黑灰烟团。
		# AOE 半径只以 0.22s 的断续危险圈提示一次，不做持续扩张同心圆。
		var visual_seed: int = int(flash.get("visual_seed", 0))
		var base_angle := fposmod(float(visual_seed) * 2.399963, TAU)
		var blast_t := clampf(ft / 0.22, 0.0, 1.0)
		if ft < 0.22:
			var danger_segments := PackedVector2Array()
			var danger_radius: float = float(flash["radius"])
			for seg in range(24):
				if seg % 4 == 3:
					continue
				var a0 := float(seg) / 24.0 * TAU
				var a1 := float(seg + 1) / 24.0 * TAU
				danger_segments.push_back(flash_pos + Vector2.from_angle(a0) * danger_radius)
				danger_segments.push_back(flash_pos + Vector2.from_angle(a1) * danger_radius)
			draw_multiline(danger_segments, Color(1.0, 0.42, 0.12, (1.0 - blast_t) * 0.7), 1.2, true)

			var blast_rays := PackedVector2Array()
			for ray in range(10):
				var ray_angle := base_angle + float(ray) / 10.0 * TAU + sin(float(ray * 17 + visual_seed)) * 0.09
				var ray_dir := Vector2.from_angle(ray_angle)
				var ray_len := lerpf(7.0, 34.0 + float(ray % 3) * 3.0, ease(blast_t, -1.6))
				blast_rays.push_back(flash_pos + ray_dir * 3.0)
				blast_rays.push_back(flash_pos + ray_dir * ray_len)
			draw_multiline(blast_rays, Color(1.0, 0.55, 0.16, (1.0 - blast_t) * 0.95), 2.0, true)
			draw_circle(flash_pos, lerpf(8.0, 2.0, blast_t),
				Color(1.0, 0.96, 0.72, (1.0 - blast_t) * 0.95))

		var smoke_in := clampf((ft - 0.04) / 0.16, 0.0, 1.0)
		var smoke_alpha := smoke_in * (1.0 - ft) * 0.72
		var smoke_spread := lerpf(7.0, 20.0, ft)
		for puff in range(7):
			var puff_angle := base_angle + float(puff) / 7.0 * TAU + sin(float(puff * 23 + visual_seed)) * 0.22
			var puff_dist := smoke_spread * (0.45 + 0.08 * float(puff % 4))
			var puff_pos := flash_pos + Vector2.from_angle(puff_angle) * puff_dist
			var puff_radius := (7.0 + float((puff * 5 + absi(visual_seed)) % 6)) * lerpf(0.75, 1.35, ft)
			draw_circle(puff_pos, puff_radius, Color(0.28, 0.31, 0.34, smoke_alpha))
		draw_circle(flash_pos, lerpf(8.0, 14.0, ft), Color(0.12, 0.14, 0.16, smoke_alpha * 0.9))
	for b in _bullets:
		var dir: Vector2 = b["vel"].normalized()
		if b.get("is_rocket", false):
			# 火箭：橙红色较长尾迹 + 亮白头（逐颗——数量少、保留末段淡出）
			var life_left: float = float(b["life"])
			var fade: float = clampf(life_left / FADE_OUT_DURATION, 0.0, 1.0)
			var tail: Vector2 = b["pos"] - dir * ROCKET_TRAIL_LENGTH
			draw_line(b["pos"], tail, Color(1.0, 0.45, 0.15, 0.85 * fade), 2.2, true)
			draw_circle(b["pos"], 2.0, Color(1.0, 0.95, 0.8, fade))
		else:
			# 曳光弹：亮黄色短线（收集，循环后一次性提交）
			var tail: Vector2 = b["pos"] - dir * TRACER_LENGTH
			tracer_pts.push_back(b["pos"])
			tracer_pts.push_back(tail)
	if not tracer_pts.is_empty():
		draw_multiline(tracer_pts, Color(1.0, 0.95, 0.4, 0.9), 1.5)
	# 命中火星最多 12 组，每组 3 道；亮芯/橙边各一次批量提交，固定 2 draw calls。
	var spark_outer := PackedVector2Array()
	var spark_inner := PackedVector2Array()
	for spark in _hit_sparks:
		var life_ratio: float = clampf(1.0 - float(spark["age"]) / HIT_SPARK_DURATION, 0.0, 1.0)
		var reach: float = float(spark["scale"]) * life_ratio
		var origin: Vector2 = spark["pos"]
		var base_angle: float = float(spark["angle"])
		for ray in range(3):
			var dir := Vector2.from_angle(base_angle + (float(ray) - 1.0) * 0.68)
			spark_outer.push_back(origin + dir * 1.2)
			spark_outer.push_back(origin + dir * reach)
			spark_inner.push_back(origin + dir * 1.2)
			spark_inner.push_back(origin + dir * reach * 0.55)
	if not spark_outer.is_empty():
		draw_multiline(spark_outer, Color(1.0, 0.42, 0.08, 0.9), 2.0, true)
		draw_multiline(spark_inner, Color(1.0, 0.96, 0.65, 1.0), 1.0, true)
	PerfBuckets.tick("bullet_draw", Time.get_ticks_usec() - _t0)

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
