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

# ── 帧级共享快照（VLS / CSG BOSS 战群弹优化）──────────────────────
# 同一帧内，同源同目标的多枚导弹共用一次查询。每帧 _physics_process 头部重建。
# 详见 SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT。
const _CLOUD_SNAP_GRID_PX: float = 256.0  ## 云层快照量化网格（同格只查一次 weather.is_in_cloud）
var _snap_frame: int = -1
var _target_snap: Dictionary = {}  ## target_id -> {pos, heading, speed, alt, is_cloaked, valid, is_aircraft, missile_phase_timer}
var _lock_snap: Dictionary = {}    ## "src_id:tgt_id" -> lock_progress
var _cloud_snap: Dictionary = {}   ## Vector2i grid -> bool (in cloud)
var _weather_ref: Node = null      ## 帧内缓存的 weather 节点引用（避免每枚导弹查 group）

func _ready() -> void:
	add_to_group("explosion_vfx")
	# 让 MissileManager._physics_process 早于其 Missile 子节点运行 → 子节点能读到当帧快照
	process_priority = -10

func spawn_missile(source: CombatUnit, target: CombatUnit, missile_params: MissileParams, is_secondary: bool = false) -> Missile:
	var missile: Missile = _missile_scene.instantiate()
	missile.params = missile_params
	missile.source = source
	missile.is_secondary_weapon = is_secondary   # QAAM 归因（720 批 qmaam_bloodlust 判 kind）
	missile.target = target
	missile.team = source.team
	missile.speed = source.speed + 50.0  # 初速 = 发射单位速度 + 50 m/s
	missile.altitude = source.altitude
	# AWACS 支援：区内玩家小队发射的导弹追踪 G ×1.25（发射瞬间快照，spec global-awareness-roe §2.6c）
	missile.awacs_g_mult = AwacsSupportEvent.missile_g_mult_for(source)

	# 初始朝向：
	#   VLS 齐射弹 → LOS 方向 + 每发随机 ±25° 散布（模拟"一串火柱方向略散"的齐射观感）
	#   飞机发射 → 用飞机当前朝向（飞机基本已对准目标）
	#   地面 / 舰船 SAM → 用 source→target 的方向，避免船/SAM 朝北导致初始 PN 爆转
	#   HOBS 高离轴弹（QMAAM 等）→ launch_toward_target=true，直接指向 LOS，
	#     和宽锁定锥配套，避免侧面发射后还要先扭机头转弯
	var initial_heading: float
	if missile_params and missile_params.is_vls_salvo and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		var base := atan2(los.x, -los.y)
		initial_heading = base + randf_range(-0.44, 0.44)  # ±25°
	elif missile_params and missile_params.launch_toward_target and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	elif (source is GroundUnit or source is NavalUnit) and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	else:
		initial_heading = source.heading
		# 急转/大坡度发射修正：发射机正在急速滚转或深坡度盘旋时，机头朝向与目标 LOS
		# 严重脱节。沿机头发射 → 导弹在 guidance_delay 盲飞段先朝错误方向冲出去，等制导
		# 接管时目标已被甩出导引头 FOV(±30°) → 永久丢锁射空。改为朝 LOS 发射，消除"继承
		# 滚转机头"的初始误差。仅飞机源 + 有目标时触发，零坡度平飞发射不受影响。
		# （见 2026-06-13 武器有效性诊断：僚机 Solar 在 155°/s 滚转反向中盲发 MRM 连续射空）
		if source is Aircraft and target and is_instance_valid(target):
			var ac_src := source as Aircraft
			var rolling_fast: bool = absf(ac_src._bank_rate_rad_s) > deg_to_rad(60.0)
			var banked_steep: bool = absf(ac_src.bank_angle) > deg_to_rad(45.0)
			if rolling_fast or banked_steep:
				var los_fix := target.global_position - source.global_position
				if los_fix.length() > 1.0:
					initial_heading = atan2(los_fix.x, -los_fix.y)
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

## 队友对目标已发的有效在飞导弹累计伤害（不含 exclude_source）
## 用于"队友已发足够伤害则不再补射"的弹药节约判定：
##   if team_inbound_damage(tgt, my_team, self) >= tgt.hp: skip
##
## 过滤条件：
##   - 导弹仍在 active 且未被热诱弹干扰（jammed 视为不会命中）
##   - **仍持有制导**（has_guidance）：丢锁/出 FOV/照射中断的导弹必定射空，
##     绝不能再算进"已发足够伤害"——否则一枚射空的导弹会把整支小队的补射封锁到
##     它寿命耗尽（最长 30s），目标却安然无恙。这是"队友连续射空 + 全队不再开火"的根因。
##     （见 2026-06-13 武器有效性诊断：A-7 Dispatch 50hp 吃下 2 枚射空的 MRM 后，
##      Dolphin/Ultra 被 TEAM_OVERKILL 连封 17s 一弹不发）
##   - 源仍存活且与查询 team 同队
##   - 目标受击伤害 cap 后的有效值（玩家方 survivor_missile_damage_cap），enemy 无 cap 用满伤
func team_inbound_damage(target: CombatUnit, team: int, exclude_source: CombatUnit = null) -> float:
	if not is_instance_valid(target):
		return 0.0
	var total := 0.0
	for child in get_children():
		if not (child is Missile):
			continue
		var m: Missile = child as Missile
		if not m.is_active or m.is_flare_jammed or not m.has_guidance:
			continue
		if m.target != target:
			continue
		if not is_instance_valid(m.source) or m.source.team != team or m.source == exclude_source:
			continue
		var dmg: float = m.params.damage
		# 受击方伤害 cap：仅 Aircraft 上有 survivor_missile_damage_cap，且 > 0 才生效
		if target is Aircraft:
			var cap: float = (target as Aircraft).survivor_missile_damage_cap
			if cap > 0.0:
				dmg = minf(dmg, cap)
		total += dmg
	return total

## 每帧重建：遍历所有活跃 Missile 子节点，把 (target / source-target lock) 拍成快照。
## 云层与 weather 引用按需懒查（Missile 通过 get_in_cloud() 触发）。
func _build_frame_snapshot() -> void:
	if not SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT:
		return
	var pf: int = Engine.get_physics_frames()
	if _snap_frame == pf:
		return
	_snap_frame = pf
	_target_snap.clear()
	_lock_snap.clear()
	_cloud_snap.clear()
	_weather_ref = null

	for child in get_children():
		if not child is Missile:
			continue
		var msl: Missile = child as Missile
		if not msl.is_active:
			continue
		var tgt: CombatUnit = msl.target
		if tgt != null and is_instance_valid(tgt):
			var tid: int = tgt.get_instance_id()
			if not _target_snap.has(tid):
				var is_ac: bool = tgt is Aircraft
				_target_snap[tid] = {
					"pos": tgt.global_position,
					"heading": tgt.heading if "heading" in tgt else 0.0,
					"speed": tgt.speed if "speed" in tgt else 0.0,
					"alt": tgt.altitude,
					"is_destroyed": tgt.is_destroyed,
					"is_aircraft": is_ac,
					"is_cloaked": is_ac and (tgt as Aircraft).is_cloaked,
					"flat_altitude": tgt.flat_altitude,
					"alt_tier": tgt.get_altitude_tier(),
				}
			# SARH 锁定进度（仅 SARH 路径需要）
			var src: CombatUnit = msl.source
			if msl.params and not msl.params.fire_and_forget and src != null and is_instance_valid(src):
				var key: String = "%d:%d" % [src.get_instance_id(), tid]
				if not _lock_snap.has(key):
					_lock_snap[key] = src.radar_targets.get(tgt, 0.0)

## Missile 调用：取目标快照（命中返回 Dictionary，未命中返回空 Dictionary）
func get_target_snap(target: CombatUnit) -> Dictionary:
	if not SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT or target == null:
		return {}
	return _target_snap.get(target.get_instance_id(), {})

## Missile 调用：取 SARH 锁定进度（命中返回 float，未命中返回 -1.0）
func get_lock_progress(source: CombatUnit, target: CombatUnit) -> float:
	if not SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT or source == null or target == null:
		return -1.0
	var key: String = "%d:%d" % [source.get_instance_id(), target.get_instance_id()]
	return _lock_snap.get(key, -1.0)

## Missile 调用：云层在位（按 256px 网格量化共享）
func get_in_cloud(world_pos: Vector2) -> bool:
	if not SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT:
		var w := get_tree().get_first_node_in_group("weather")
		return w != null and w.has_method("is_in_cloud") and w.is_in_cloud(world_pos)
	var grid := Vector2i(int(world_pos.x / _CLOUD_SNAP_GRID_PX), int(world_pos.y / _CLOUD_SNAP_GRID_PX))
	if _cloud_snap.has(grid):
		return _cloud_snap[grid]
	if _weather_ref == null:
		_weather_ref = get_tree().get_first_node_in_group("weather")
	var in_c: bool = false
	if _weather_ref != null and _weather_ref.has_method("is_in_cloud"):
		in_c = _weather_ref.is_in_cloud(world_pos)
	_cloud_snap[grid] = in_c
	return in_c

func _physics_process(delta: float) -> void:
	# ── 导弹命中检测 ──
	for child in get_children():
		if not child is Missile:
			continue
		var missile: Missile = child as Missile

		if not missile.is_active:
			missile.queue_free()
			continue

		# ── 热诱弹干扰弹不参与命中检测（2026-07-03 修）──
		# 语义 = "jammed 视为不会命中"（与 team_inbound_damage / CIWS 拦截过滤同一契约：
		# CIWS 不拦 jammed 弹、队友补射不把 jammed 弹算进伤害，都建立在它无害的前提上）。
		# 旧 bug：jammed 只关制导（直线飞行），近炸引信却照常起爆——尾追被干扰的导弹正对
		# 目标航迹直飞，目标因"威胁列表已滤掉 jammed"不再规避 → 直线弹撞直线机。
		# 日志实证：184619 [120.3] Watch flare jam 成功(100%) → [121.8] 同弹命中 Watch。
		if missile.is_flare_jammed:
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
			if not CombatUnit.teams_hostile(unit.team, missile.team):
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
				# 加力窗口滚转躲弹（spec afterburner-mode）：命中瞬间 90% 甩偏——
				# 弹置 is_flare_jammed 走既有偏飞契约（不再参与命中/CIWS 拦截/补射计伤），
				# 目标触发滚转动画；10% = "非常极限的情况"照常命中。jam 后本弹不会再进
				# 此分支、失败当帧即爆 → 每弹天然只 roll 一次。与热诱弹无关（无 flare 兜底层）。
				if unit is Aircraft and unit.afterburner_window_active:
					if randf() < 0.90:
						missile.is_flare_jammed = true
						unit._trigger_evasion_roll()
						EventLogger.log_event("AB_MISSILE_DODGE", unit._log_name(),
							"rolled off %s" % msl_name)
						continue
				var hit_unit: CombatUnit = unit as CombatUnit
				var tgt_name: String = hit_unit.callsign if hit_unit.callsign != "" else hit_unit.name
				if unit is Aircraft and unit.params:
					var side := "Friend" if unit.team == 0 else "Enemy"
					tgt_name = "%s/%s[%s]" % [side, unit.params.display_name, unit.callsign]
				EventLogger.log_event("MISSILE", msl_name,
					"hit %s (dmg=%.0f)" % [tgt_name, missile.params.damage])
				# 战报：命中归到射手名下（命中行主体是弹种，这里按 source 计数）
				if is_instance_valid(missile.source):
					var _shooter := missile.source
					var _sn: String = _shooter._log_name() if _shooter.has_method("_log_name") \
							else (_shooter.callsign if ("callsign" in _shooter and _shooter.callsign != "") else String(_shooter.name))
					EventLogger.tally(_sn, "msl_hit")
				var hit_heading: float = unit.heading if "heading" in unit else 0.0
				# 爆炸画在飞机身上（不是导弹位置），击中/击毁均只此一次
				ExplosionVFXScript.emit(get_tree(), unit.global_position, hit_heading, 1.0)
				# 爆炸音效：4 种 bomb_distant 随机选一种
				var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
				AudioManager.play_sfx_2d(bomb_ids[randi() % 4], unit.global_position, 9.0)
				# 归因：把发射单位写到目标 meta，aircraft._record_kill_attribution 在致死时读取
				if is_instance_valid(missile.source):
					unit.set_meta("_pending_attacker", missile.source)
					unit.set_meta("_last_damage_kind", "qmaam" if missile.is_secondary_weapon else "missile")
				if unit is GroundUnit:
					unit.take_missile_damage(missile.params.damage)
				elif unit is NavalUnit:
					# 船走位置感知路由：伤害给最近的挂点或弱点
					(unit as NavalUnit).take_damage_at(missile.params.damage, missile.global_position)
				else:
					unit.take_damage(missile.params.damage, CombatUnit.safe_attacker(missile.source),
						"qmaam" if missile.is_secondary_weapon else "missile")
				# 近炸引信：在爆炸点产生 AOE 区域
				if missile.proximity_aoe:
					_spawn_aoe(missile.global_position, missile.altitude,
						missile.params.damage, missile.team, unit, missile.source)
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
	# ── 帧级共享快照构建（放在命中检测之后；保证击杀已结算的目标 is_destroyed=true 写入快照，
	#    供同帧后运行的 Missile._physics_process 读取，与改动前直接读 target.is_destroyed 一致）──
	_build_frame_snapshot()

## 创建 AOE 区域
func _spawn_aoe(pos: Vector2, alt: float, damage: float, team: int, direct_hit: CombatUnit, source: Node = null) -> void:
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
		"source": source,
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
			if not CombatUnit.teams_hostile(unit.team, zteam):
				continue
			var uid := unit.get_instance_id()
			if zhit.has(uid):
				continue
			var dist_2d := zpos.distance_to(unit.global_position)
			var alt_diff := absf(zalt - unit.altitude)
			# 地表单位（地面/船/挂点代理）altitude=0，AOE 引爆点在空中时 alt_diff 必然超容差
			# → 必须把这些类型显式列在 alt_ok 例外里，否则 AOE 永远扫不到船
			var alt_ok := alt_diff < AOE_ALT_TOLERANCE \
					or unit is GroundUnit or unit is NavalUnit or unit is MountTarget
			if dist_2d < zradius and alt_ok:
				# AOE 仍在飞机本体位置画爆炸（不在 AOE 中心），击中/击毁均只此一次
				var u_head: float = unit.heading if "heading" in unit else 0.0
				ExplosionVFXScript.emit(get_tree(), unit.global_position, u_head, 1.0)
				# AOE 区域在导弹爆炸后还要存活 AOE_DURATION 秒，这期间发射者被击落是常态
				# → 必须净化，否则 take_damage_from 的实参类型检查直接崩
				var zsrc: Node = CombatUnit.safe_attacker(zone.get("source", null))
				if unit is GroundUnit:
					unit.take_missile_damage(zdmg)
				elif unit is NavalUnit:
					# 走位置感知路由：用 AOE 中心而不是船中心，让 mount/弱点 routing 更准
					if zsrc != null and is_instance_valid(zsrc):
						unit.set_meta("_pending_attacker", zsrc)
						unit.set_meta("_last_damage_kind", "aoe")
					(unit as NavalUnit).take_damage_at(zdmg, zpos)
				else:
					unit.take_damage_from(zdmg, zsrc, "aoe")
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
		if unit == just_hit or not CombatUnit.teams_hostile(unit.team, missile.team):
			continue
		var dist := missile.global_position.distance_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best
