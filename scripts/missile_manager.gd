class_name MissileManager
extends Node2D

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

## ── 近炸引信 AOE 常量 ──
const AOE_RADIUS_M: float = 120.0       ## AOE 半径（米）
const AOE_DURATION: float = 1.5         ## 持续时间（秒）
const AOE_ALT_TOLERANCE: float = 300.0  ## 高度容差（米）

var _missile_scene: PackedScene = preload("res://scenes/missile.tscn")
const ExplosionVFXScript = preload("res://scripts/explosion_vfx.gd")

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var target_list: Array[CombatUnit] = []

## 活跃的 AOE 区域列表
var _aoe_zones: Array = []  # [{pos, altitude, radius_px, time_left, max_time, damage, team, hit_set}]

## 命中闪光效果（类 3D 白色实色方块，一闪即淡出）
## 全场所有爆炸特效的统一宿主，通过 ExplosionVFX.emit() 接入
const HIT_FLASH_DURATION: float = 0.55
const HIT_FLASH_BASE_SIZE: float = 26.0
var _hit_flashes: Array = []  # [{pos, time_left, heading, scale}]

func _ready() -> void:
	add_to_group("explosion_vfx")

func spawn_missile(source: CombatUnit, target: CombatUnit, missile_params: MissileParams) -> Missile:
	var missile: Missile = _missile_scene.instantiate()
	missile.params = missile_params
	missile.source = source
	missile.target = target
	missile.team = source.team
	missile.speed = source.speed + 50.0  # 初速 = 发射单位速度 + 50 m/s
	missile.altitude = source.altitude

	# 初始朝向：
	#   VLS 齐射弹 → LOS 方向 + 每发随机 ±25° 散布（模拟"一串火柱方向略散"的齐射观感）
	#   飞机发射 → 用飞机当前朝向（飞机基本已对准目标）
	#   地面 / 舰船 SAM → 用 source→target 的方向，避免船/SAM 朝北导致初始 PN 爆转
	var initial_heading: float
	if missile_params and missile_params.is_vls_salvo and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		var base := atan2(los.x, -los.y)
		initial_heading = base + randf_range(-0.44, 0.44)  # ±25°
	elif (source is GroundUnit or source is NavalUnit) and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	else:
		initial_heading = source.heading
	missile.heading = initial_heading

	# 初始位置：沿初始朝向前方 15 px
	var fwd := Vector2(sin(initial_heading), -cos(initial_heading))
	missile.global_position = source.global_position + fwd * 15.0

	# 建筑遮挡参数：
	# - spawned_in_building：源在街区内 → 永久免疫拦截（"从内向外射"规则）
	# - source_tier：源的高度档位 → 决定拦截概率（HIGH 75% / MID 90% / LOW/GND 100%）
	# - _was_in_building：跟踪从外部进入街区的事件，每次进入只 roll 一次
	if source is Aircraft and (source as Aircraft).in_building:
		missile.spawned_in_building = true
	elif source.altitude < 3500.0 and BuildingRenderer.is_position_inside_building(source.global_position):
		missile.spawned_in_building = true
	# source_tier 区分 GROUND（地面/船）和 LOW（低空飞机）：
	# 同样 altitude<3500，但地面发射器视为 GROUND（必拦），飞机视为 LOW（80%）
	if source is GroundUnit or source is NavalUnit:
		missile.source_tier = CombatUnit.AltitudeTier.GROUND
	else:
		missile.source_tier = source.get_altitude_tier()
	missile._was_in_building = missile.spawned_in_building

	# 初始化 LOS 角，避免第一帧 PN 尖峰
	var los := target.global_position - missile.global_position
	missile._prev_los_angle = atan2(los.x, -los.y)

	# 连锁弹头 / 近炸引信进化：仅 Aircraft 有此属性
	if source is Aircraft:
		missile.bounces_remaining = source.missile_bounce_count
		missile.proximity_aoe = source.missile_proximity_aoe
	else:
		missile.bounces_remaining = 0

	add_child(missile)
	return missile

## 是否应把这枚导弹计入"占额度"：丢锁 + 已出玩家视口 → 不算（可以补射）
## 2026-04-22：BOSS 带热诱弹/光学隐形时导弹丢锁后仍按 max_lifetime 飞满 30s，
## 原本会把玩家锁死整整 30 秒。放行条件严格设为"丢锁 && 离屏"，
## 既消除 BOSS 隐形场景下的死锁，又保留玩家屏幕内的弹量节制（防乱射观感）。
func _missile_blocks_slot(m: Missile) -> bool:
	if not m.is_active:
		return false
	if m.has_guidance:
		return true
	return _is_on_screen(m.global_position)

func _is_on_screen(world_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return true
	var center := cam.get_screen_center_position()
	var vp_size := get_viewport().get_visible_rect().size
	var zoom_x: float = maxf(cam.zoom.x, 0.0001)
	var zoom_y: float = maxf(cam.zoom.y, 0.0001)
	var half_w := (vp_size.x * 0.5) / zoom_x
	var half_h := (vp_size.y * 0.5) / zoom_y
	# 不加边距：必须真正离开视口才解除封锁，避免边缘闪入导致玩家看到两发同屏
	return absf(world_pos.x - center.x) < half_w \
		and absf(world_pos.y - center.y) < half_h

## 检查某目标是否已有在飞的导弹（由指定发射单位发射）
func has_active_missile_at(source: CombatUnit, target: CombatUnit) -> bool:
	for child in get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.source == source and m.target == target and _missile_blocks_slot(m):
				return true
	return false

## 计数：某射手对某目标在飞的导弹数
func count_active_missiles_at(source: CombatUnit, target: CombatUnit) -> int:
	var count := 0
	for child in get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.source == source and m.target == target and _missile_blocks_slot(m):
				count += 1
	return count

func _physics_process(delta: float) -> void:
	# ── 导弹命中检测 ──
	for child in get_children():
		if not child is Missile:
			continue
		var missile: Missile = child as Missile

		if not missile.is_active:
			missile.queue_free()
			continue

		# 引信武装时间检查
		if missile.age < missile.params.guidance_delay:
			continue

		# 建筑遮挡（按 source 高度档位查表的单次进入 roll）
		# 不在 LOW 或 spawned_in_building 直接跳过
		if missile.altitude < 3500.0 and not missile.spawned_in_building:
			var in_b: bool = BuildingRenderer.is_position_inside_building(missile.global_position)
			# 只在 "外部 → 内部" 跳变时 roll 一次（在内部期间不再 roll，离开后下次进入再 roll）
			if in_b and not missile._was_in_building:
				var p := _building_block_prob_for_tier(missile.source_tier)
				if randf() < p:
					EventLogger.log_event("MISSILE", missile.params.display_name if missile.params else "MSL",
						"intercepted by building @ alt %.0fm (src_tier=%d, p=%.2f)" % [missile.altitude, missile.source_tier, p])
					ExplosionVFXScript.emit(get_tree(), missile.global_position, missile.heading, 1.0)
					var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
					AudioManager.play_sfx_2d(bomb_ids[randi() % 4], missile.global_position, 9.0)
					missile.is_active = false
					missile.queue_free()
					continue
			missile._was_in_building = in_b

		# 命中检测：遍历所有敌方单位
		var fuse_radius_px := missile.params.proximity_fuse_radius * PIXELS_PER_METER
		for unit in target_list:
			if not is_instance_valid(unit) or unit.is_destroyed:
				continue
			if unit.team == missile.team:
				continue
			# 光学隐形：导弹从隐形目标穿过
			if unit is Aircraft and unit.is_cloaked:
				continue
			# 导弹穿透窗口：flare 释放后 1 秒内所有导弹从此单位穿过
			if unit is Aircraft and unit.missile_phase_timer > 0.0:
				continue
			# 2D 距离 + 高度容差（地面单位/flat_altitude 模式跳过高度检查）
			var dist_2d := missile.global_position.distance_to(unit.global_position)
			var flat := unit is Aircraft and unit.flat_altitude
			var alt_ok := flat or unit is GroundUnit or unit is NavalUnit or absf(missile.altitude - unit.altitude) < missile.params.proximity_fuse_alt
			# 船比飞机大一个量级，用船长一半作为有效命中半径（否则默认 fuse 半径太小容易擦边）
			var effective_fuse: float = fuse_radius_px
			if unit is NavalUnit:
				var nu: NavalUnit = unit as NavalUnit
				if nu.params:
					effective_fuse = maxf(fuse_radius_px, nu.params.hull_length * 0.5)
			if dist_2d < effective_fuse and alt_ok:
				# 云中目标：基于云密度的 miss roll（导弹"看不清"目标）
				if unit.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
					var weather := get_tree().get_first_node_in_group("weather")
					if weather and weather.has_method("sample_density"):
						var density: float = weather.sample_density(unit.global_position)
						if density > 0.0 and randf() < 0.35 * density:
							continue  # 擦身而过，导弹继续飞
				var msl_name: String = missile.params.display_name if missile.params else "MSL"
				var hit_unit: CombatUnit = unit as CombatUnit
				var tgt_name: String = hit_unit.callsign if hit_unit.callsign != "" else hit_unit.name
				if unit is Aircraft and unit.params:
					var side := "Friend" if unit.team == 0 else "Enemy"
					tgt_name = "%s/%s[%s]" % [side, unit.params.display_name, unit.callsign]
				EventLogger.log_event("MISSILE", msl_name,
					"hit %s (dmg=%.0f)" % [tgt_name, missile.params.damage])
				var hit_heading: float = unit.heading if "heading" in unit else 0.0
				# 爆炸画在飞机身上（不是导弹位置），击中/击毁均只此一次
				ExplosionVFXScript.emit(get_tree(), unit.global_position, hit_heading, 1.0)
				# 爆炸音效：4 种 bomb_distant 随机选一种
				var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
				AudioManager.play_sfx_2d(bomb_ids[randi() % 4], unit.global_position, 9.0)
				# 归因：把发射单位写到目标 meta，aircraft._record_kill_attribution 在致死时读取
				if is_instance_valid(missile.source) and unit is Aircraft:
					unit.set_meta("_pending_attacker", missile.source)
				if unit is GroundUnit:
					unit.take_missile_damage(missile.params.damage)
				elif unit is NavalUnit:
					# 船走位置感知路由：伤害给最近的挂点或弱点
					(unit as NavalUnit).take_damage_at(missile.params.damage, missile.global_position)
				else:
					unit.take_damage(missile.params.damage)
				# 近炸引信：在爆炸点产生 AOE 区域
				if missile.proximity_aoe:
					_spawn_aoe(missile.global_position, missile.altitude,
						missile.params.damage, missile.team, unit)
				# 连锁弹头：弹跳至最近的其他敌方单位
				if missile.bounces_remaining > 0:
					var next_target := _find_bounce_target(missile, unit)
					if next_target:
						missile.bounces_remaining -= 1
						missile.target = next_target
						missile.is_flare_jammed = false
						missile.has_guidance = true
						var los := next_target.global_position - missile.global_position
						missile._prev_los_angle = atan2(los.x, -los.y)
						var bounce_name: String = next_target.callsign if next_target.callsign != "" else next_target.name
						EventLogger.log_event("MISSILE", msl_name,
							"bounce → %s (bounces_left=%d)" % [
								bounce_name, missile.bounces_remaining])
						break
				missile.is_active = false
				missile.queue_free()
				break

	# ── AOE 区域更新 ──
	_update_aoe_zones(delta)
	# ── 命中闪光更新 ──
	_update_hit_flashes(delta)

## 创建 AOE 区域
func _spawn_aoe(pos: Vector2, alt: float, damage: float, team: int, direct_hit: CombatUnit) -> void:
	var hit_set := {}
	# 直接命中的单位已受伤，不重复伤害
	if is_instance_valid(direct_hit):
		hit_set[direct_hit.get_instance_id()] = true
	var zone := {
		"pos": pos,
		"altitude": alt,
		"radius_px": AOE_RADIUS_M * PIXELS_PER_METER,
		"time_left": AOE_DURATION,
		"max_time": AOE_DURATION,
		"damage": damage,
		"team": team,
		"hit_set": hit_set,
	}
	_aoe_zones.append(zone)
	EventLogger.log_event("AOE", "ProxFuze",
		"spawned at (%.0f,%.0f) alt=%.0f r=%.0fm dmg=%.0f" % [
			pos.x, pos.y, alt, AOE_RADIUS_M, damage])

## 每帧更新 AOE 区域：检测新进入的敌方单位，渐退后移除
func _update_aoe_zones(delta: float) -> void:
	if _aoe_zones.is_empty():
		return
	var needs_redraw := false
	var i := _aoe_zones.size() - 1
	while i >= 0:
		var zone: Dictionary = _aoe_zones[i]
		zone["time_left"] -= delta
		if zone["time_left"] <= 0.0:
			_aoe_zones.remove_at(i)
			needs_redraw = true
			i -= 1
			continue
		# 检测圈内新敌方单位
		var zpos: Vector2 = zone["pos"]
		var zalt: float = zone["altitude"]
		var zradius: float = zone["radius_px"]
		var zteam: int = zone["team"]
		var zdmg: float = zone["damage"]
		var zhit: Dictionary = zone["hit_set"]
		for unit in target_list:
			if not is_instance_valid(unit) or unit.is_destroyed:
				continue
			if unit.team == zteam:
				continue
			var uid := unit.get_instance_id()
			if zhit.has(uid):
				continue
			var dist_2d := zpos.distance_to(unit.global_position)
			var alt_diff := absf(zalt - unit.altitude)
			var alt_ok := alt_diff < AOE_ALT_TOLERANCE or unit is GroundUnit
			if dist_2d < zradius and alt_ok:
				# AOE 仍在飞机本体位置画爆炸（不在 AOE 中心），击中/击毁均只此一次
				var u_head: float = unit.heading if "heading" in unit else 0.0
				ExplosionVFXScript.emit(get_tree(), unit.global_position, u_head, 1.0)
				if unit is GroundUnit:
					unit.take_missile_damage(zdmg)
				else:
					unit.take_damage(zdmg)
				zhit[uid] = true
				var tgt_name: String = unit.callsign if unit.callsign != "" else unit.name
				EventLogger.log_event("AOE", "ProxFuze",
					"hit %s (dmg=%.0f)" % [tgt_name, zdmg])
		needs_redraw = true
		i -= 1
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	# 渲染 AOE 红圈
	for zone in _aoe_zones:
		var ratio: float = zone["time_left"] / zone["max_time"]
		var alpha := ratio * 0.35
		var pos: Vector2 = zone["pos"] - global_position  # 转为本地坐标
		var radius: float = zone["radius_px"]
		# 半透明填充
		draw_circle(pos, radius, Color(1.0, 0.15, 0.1, alpha * 0.4))
		# 描边
		draw_arc(pos, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.1, alpha), 2.0)
	# 命中闪光：白色等距线框方块（类 3D），一闪即淡出
	for flash in _hit_flashes:
		_draw_hit_flash(flash)

## 统一爆炸闪光接入点（由 ExplosionVFX.emit 路由而来，外部模块不要直接 call）
func spawn_flash(pos: Vector2, heading: float = 0.0, scale: float = 1.0) -> void:
	_spawn_hit_flash(pos, heading, scale)

## 内部实现：加入一条活动闪光记录
func _spawn_hit_flash(pos: Vector2, heading: float = 0.0, scale: float = 1.0) -> void:
	_hit_flashes.append({
		"pos": pos,
		"time_left": HIT_FLASH_DURATION,
		"heading": heading,
		"scale": maxf(scale, 0.1),
	})
	queue_redraw()

func _update_hit_flashes(delta: float) -> void:
	if _hit_flashes.is_empty():
		return
	var i := _hit_flashes.size() - 1
	while i >= 0:
		_hit_flashes[i]["time_left"] -= delta
		if _hit_flashes[i]["time_left"] <= 0.0:
			_hit_flashes.remove_at(i)
		i -= 1
	queue_redraw()

func _draw_hit_flash(flash: Dictionary) -> void:
	var t_left: float = flash["time_left"]
	var ratio: float = clampf(t_left / HIT_FLASH_DURATION, 0.0, 1.0)
	var age: float = 1.0 - ratio
	# 初始亮闪阶段 + 线性淡出
	var intensity: float
	if age < 0.18:
		intensity = 1.0
	else:
		intensity = ratio / 0.82
	var alpha: float = clampf(intensity, 0.0, 1.0)
	# 尺寸略微外扩（age 0 → 1 : 1.0 → 1.5），再按调用方给的 scale 放大
	var flash_scale: float = flash.get("scale", 1.0)
	var size: float = HIT_FLASH_BASE_SIZE * (1.0 + age * 0.5) * flash_scale
	var pos: Vector2 = flash["pos"] - global_position
	var h: float = flash["heading"]
	# 依飞机 heading 建立局部轴：fwd 沿机头，right 沿机身右侧
	var fwd := Vector2(sin(h), -cos(h))
	var right := Vector2(cos(h), sin(h))
	var half: float = size * 0.5
	# 假 3D：顶面整体上移以模拟高度
	var tilt := Vector2(0.0, -size * 0.55)
	# 底面 4 角（b = bottom）
	var b_fr := pos + fwd * half + right * half
	var b_fl := pos + fwd * half - right * half
	var b_bl := pos - fwd * half - right * half
	var b_br := pos - fwd * half + right * half
	# 顶面 4 角（t = top）
	var t_fr := b_fr + tilt
	var t_fl := b_fl + tilt
	var t_bl := b_bl + tilt
	var t_br := b_br + tilt
	# 面颜色：核心白，侧面稍暗以分面
	var col_top := Color(1.0, 1.0, 1.0, alpha * 0.85)
	var col_side_bright := Color(0.92, 0.95, 1.0, alpha * 0.65)
	var col_side_dim := Color(0.78, 0.82, 0.92, alpha * 0.5)
	var col_edge := Color(1.0, 1.0, 1.0, alpha)
	# 可见侧面：outward-normal 屏幕 y>0（面朝下 / 朝观察者）的面才画
	# front 面 (+fwd): 屏幕 y 分量 = fwd.y；同理 right 面 = right.y
	# 先画远端（不可见侧的背面缓冲），再按屏幕 y 从小到大画，保证重叠正确
	var faces: Array = []  # [{verts, color, sort_y}]
	# front 面（+fwd 方向的侧壁）
	if fwd.y > 0.0:
		var verts := PackedVector2Array([b_fr, b_fl, t_fl, t_fr])
		faces.append({"v": verts, "c": col_side_bright if fwd.y > 0.5 else col_side_dim, "y": (b_fr.y + b_fl.y) * 0.5})
	# back 面（-fwd）
	if fwd.y < 0.0:
		var verts2 := PackedVector2Array([b_bl, b_br, t_br, t_bl])
		faces.append({"v": verts2, "c": col_side_bright if fwd.y < -0.5 else col_side_dim, "y": (b_bl.y + b_br.y) * 0.5})
	# right 面 (+right)
	if right.y > 0.0:
		var verts3 := PackedVector2Array([b_br, b_fr, t_fr, t_br])
		faces.append({"v": verts3, "c": col_side_bright if right.y > 0.5 else col_side_dim, "y": (b_br.y + b_fr.y) * 0.5})
	# left 面 (-right)
	if right.y < 0.0:
		var verts4 := PackedVector2Array([b_fl, b_bl, t_bl, t_fl])
		faces.append({"v": verts4, "c": col_side_bright if right.y < -0.5 else col_side_dim, "y": (b_fl.y + b_bl.y) * 0.5})
	# 从远到近（y 小到大）画侧面
	faces.sort_custom(func(a, b): return a["y"] < b["y"])
	for f in faces:
		draw_colored_polygon(f["v"], f["c"])
	# 顶面（最后画，在侧面之上）
	var top_verts := PackedVector2Array([t_fr, t_fl, t_bl, t_br])
	draw_colored_polygon(top_verts, col_top)
	# 线框（棱），增强方块轮廓
	var lw: float = 1.6
	# 顶面
	draw_polyline(PackedVector2Array([t_fr, t_fl, t_bl, t_br, t_fr]), col_edge, lw)
	# 底面
	draw_polyline(PackedVector2Array([b_fr, b_fl, b_bl, b_br, b_fr]), Color(1, 1, 1, alpha * 0.55), lw)
	# 垂直棱
	draw_line(b_fr, t_fr, col_edge, lw)
	draw_line(b_fl, t_fl, col_edge, lw)
	draw_line(b_bl, t_bl, col_edge, lw)
	draw_line(b_br, t_br, col_edge, lw)
	# 中心亮点（强化闪光观感）
	draw_circle(pos + tilt * 0.5, size * 0.18 * (0.4 + ratio * 0.6), Color(1.0, 1.0, 1.0, alpha))

## 建筑拦截概率查表（target 默认在 LOW 档；同 bullet_manager._building_block_prob_for_tier）
##   HIGH (≥7500m) → 40%（陡降弹大多漏过城市间隙）
##   MID  (3500-7500m) → 60%
##   LOW  (<3500m，飞机) → 80%
##   GROUND (SAM/AAA/船) → 100%（地面火力对楼里玩家完全无效）
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


## 寻找弹跳目标：最近的存活敌方单位（排除刚命中的）
func _find_bounce_target(missile: Missile, just_hit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for unit in target_list:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit == just_hit or unit.team == missile.team:
			continue
		var dist := missile.global_position.distance_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best
