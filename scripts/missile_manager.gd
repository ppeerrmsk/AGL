class_name MissileManager
extends Node2D

const WeaponHitResolverScript = preload("res://scripts/weapon_hit_resolver.gd")

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

## ── 近炸引信 AOE 常量 ──
const AOE_RADIUS_M: float = 120.0       ## AOE 半径（米）
const AOE_DURATION: float = 1.5         ## 持续时间（秒）
const AOE_ALT_TOLERANCE: float = 300.0  ## 高度容差（米）
## 必须大于所有非舰船单位的最大导弹有效引信半径；舰船由 UnitGrid.large_units 恒扫。
const TARGET_GRID_CELL_SIZE: float = 256.0
const MISSILE_TRAIL_BATCH_SLOTS: int = TrailRibbon.SAMPLE_PHASE_SLOTS

var _missile_scene: PackedScene = preload("res://scenes/missile.tscn")
const MissileTrailBatchScript = preload("res://scripts/missile_trail_batch.gd")
const ExplosionVFXScript = preload("res://scripts/explosion_vfx.gd")
const ExplosionPresenterScript = preload("res://scripts/rendering/explosion_presenter.gd")

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var target_list: Array[CombatUnit] = []
var _target_grid: UnitGrid = UnitGrid.new()
var _target_grid_buf: Array = []
var _target_order_by_id: Dictionary = {}
var _missile_trail_batches: Array[Node2D] = []
var _missile_trail_batch_root: Node2D = null

## 活跃的 AOE 区域列表
var _aoe_zones: Array = []  # [{pos, altitude, radius_px, time_left, max_time, damage, team, hit_set}]

## 命中闪光效果（类 3D 白色实色方块，一闪即淡出）
## 全场所有爆炸特效的统一宿主，通过 ExplosionVFX.emit() 接入
const HIT_FLASH_DURATION: float = ExplosionPresenterScript.HIT_FLASH_DURATION
const HIT_FLASH_BASE_SIZE: float = ExplosionPresenterScript.HIT_FLASH_BASE_SIZE
const AIRFRAME_WAVE_INTERVAL: float = 0.11
enum AirframeWaveRoute {
	NOSE_PORT_SWEEP,
	NOSE_STARBOARD_SWEEP,
	TAIL_RETURN,
	WING_ZIGZAG,
}
const AIRFRAME_WAVE_ROUTE_COUNT: int = 4
const AIRFRAME_STRUCTURE_POINTS := [
	Vector2(0.78, 0.00),  # 机头
	Vector2(0.12, -0.72), # 左翼根
	Vector2(0.00, 0.00),  # 机身中心
	Vector2(-0.12, 0.72), # 右翼根
	Vector2(-0.78, 0.00), # 尾段
]
const AIRFRAME_WAVE_ORDERS := [
	[0, 1, 2, 3, 4],
	[0, 3, 2, 1, 4],
	[4, 1, 2, 3, 0],
	[1, 0, 3, 4, 2],
]
const AIRFRAME_POINT_SCALES := [0.60, 0.68, 0.82, 0.68, 0.58]
var _hit_flashes: Array = []  # [{pos, time_left, delay, heading, scale, turn_sign, route}]
var _hit_flash_serial: int = 0
var _airframe_wave_serial: int = 0

# ── 帧级共享快照（VLS / CSG BOSS 战群弹优化）──────────────────────
# 同一帧内，同源同目标的多枚导弹共用一次查询。每帧 _physics_process 头部重建。
# 详见 SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT。
const _CLOUD_SNAP_GRID_PX: float = 256.0  ## 云层快照量化网格（同格只查一次 weather.is_in_cloud）
var _snap_frame: int = -1
var _target_snap: Dictionary = {}  ## target_id -> {pos, heading, speed, alt, is_cloaked, sensor_contact_hidden, valid, is_aircraft}
var _lock_snap: Dictionary = {}    ## "src_id:tgt_id" -> lock_progress
var _cloud_snap: Dictionary = {}   ## Vector2i grid -> bool (in cloud)
var _weather_ref: Node = null      ## 帧内缓存的 weather 节点引用（避免每枚导弹查 group）

func _ready() -> void:
	add_to_group("explosion_vfx")
	# 让 MissileManager._physics_process 早于其 Missile 子节点运行 → 子节点能读到当帧快照
	process_priority = -10
	# 批次节点使用内部子树：默认 get_child_count/get_children 不包含 internal，HUD/测试沿用
	# “直属可见子节点 == 导弹数”的既有契约，同时生命周期自动跟随 Manager。
	_missile_trail_batch_root = Node2D.new()
	_missile_trail_batch_root.name = "MissileTrailBatches"
	_missile_trail_batch_root.z_index = -1
	add_child(_missile_trail_batch_root, false, Node.INTERNAL_MODE_BACK)
	for slot in range(MISSILE_TRAIL_BATCH_SLOTS):
		var batch: Node2D = MissileTrailBatchScript.new()
		batch.name = "MissileTrailBatch%d" % slot
		_missile_trail_batch_root.add_child(batch)
		batch.setup(self, slot)
		_missile_trail_batches.append(batch)


func register_missile_trail(trail: TrailRibbon) -> void:
	if trail == null or _missile_trail_batches.is_empty():
		return
	var slot := trail.missile_batch_phase_slot() % _missile_trail_batches.size()
	trail.assign_missile_batch(_missile_trail_batches[slot])


## 每个物理 tick 只重建一次。order map 保留旧 target_list 的首命中顺序，避免空间查询
## 在多个目标重叠时改变导弹落点/伤害归属。
func _rebuild_target_grid() -> void:
	_target_grid.rebuild(target_list, TARGET_GRID_CELL_SIZE)
	_target_order_by_id.clear()
	for i in range(target_list.size()):
		var raw: Variant = target_list[i]
		if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw):
			continue
		var unit := raw as CombatUnit
		if unit == null:
			continue
		_target_order_by_id[unit.get_instance_id()] = i


func _target_candidate_precedes(a: Variant, b: Variant) -> bool:
	var ai: int = _target_order_by_id.get(a.get_instance_id(), 2147483647)
	var bi: int = _target_order_by_id.get(b.get_instance_id(), 2147483647)
	return ai < bi


## 返回复用缓冲；调用方不得跨帧持有。候选集合是全扫命中集合的超集，并按 target_list 排序。
func _ordered_target_candidates(position: Vector2) -> Array:
	_target_grid_buf.clear()
	_target_grid_buf.append_array(_target_grid.large_units)
	_target_grid.query_into(position, _target_grid_buf)
	_target_grid_buf.sort_custom(_target_candidate_precedes)
	return _target_grid_buf

func spawn_missile(source: CombatUnit, target: CombatUnit, missile_params: MissileParams, is_secondary: bool = false) -> Missile:
	var missile: Missile = _missile_scene.instantiate()
	missile.params = missile_params
	missile.source = source
	# 发射瞬间快照，禁止在途导弹因玩家跨过气氛 LOD 边界而中途变实/变空。
	missile.set_meta(CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER,
		CombatUnit.ambient_damage_multiplier(source))
	# 嘘！：JAM 敌方发射源的新离架导弹立刻进入既有失导契约。
	if SkillHooks.hush_active and source is Aircraft \
			and source.team == CombatUnit.TEAM_HOSTILE \
			and (source as Aircraft).status_jam_active:
		missile.is_flare_jammed = true
	missile.is_secondary_weapon = is_secondary   # QAAM 归因（qmaam_boost 合并嗜血效果判 kind）
	# 二段推进（720 批）：发射方持有技能 → 本弹全程续推 + 转弯渐强
	if source is Aircraft and (source as Aircraft).missile_second_stage_active:
		missile.second_stage = true
	# 连锁弹头：发射瞬间快照；后续换机/失去发射者不会改变在飞弹行为。
	if source is Aircraft and (source as Aircraft).missile_chain_active:
		missile.penetrates_after_hit = true
	# 722 签名技能：夜枭（X-09 每弹 40% 静默）/ 超越地平（X-21 偏转后重索敌）
	if source is Aircraft and source.is_player_squad() and source.has_meta("upgrade_stacks"):
		var sig_stacks: Dictionary = source.get_meta("upgrade_stacks")
		if int(sig_stacks.get("sig_x09", 0)) > 0 and randf() < 0.40:
			missile.sig_silent = true
		if int(sig_stacks.get("sig_x21", 0)) > 0:
			missile.sig_retarget_armed = true
	missile.target = target
	missile.team = source.team
	missile.speed = source.speed + 50.0  # 初速 = 发射单位速度 + 50 m/s
	missile.altitude = source.altitude
	# AWACS 支援：区内玩家小队发射的导弹追踪 G ×1.25（发射瞬间快照，spec global-awareness-roe §2.6c）
	missile.awacs_g_mult = AwacsSupportEvent.missile_g_mult_for(source)

	# 初始朝向：
	#   VLS 齐射弹 → LOS 方向 + 每发随机 ±25° 散布（模拟"一串火柱方向略散"的齐射观感）
	#   HOBS 弹 → 继续按自身契约直接指向当前 LOS
	#   普通飞机发射 → 指向两轮预测前置点，并钳在机头 ±60°
	#   地面 / 舰船 SAM → 用 source→target 的方向，避免船/SAM 朝北导致初始 PN 爆转
	var initial_heading: float
	if missile_params and missile_params.is_vls_salvo and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		var base := atan2(los.x, -los.y)
		initial_heading = base + randf_range(-0.44, 0.44)  # ±25°
	elif source is Aircraft and source.has_meta(&"hyper_a_g0_omnidirectional_salvo") \
			and bool(source.get_meta(&"hyper_a_weapons_enabled", false)) \
			and target and is_instance_valid(target):
		# G0 专属全向离轴发射：弹体直接朝当前 LOS 离架，机体自身不瞬转。
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	elif missile_params and missile_params.launch_toward_target and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	elif (source is GroundUnit or source is NavalUnit) and target and is_instance_valid(target):
		var los := target.global_position - source.global_position
		initial_heading = atan2(los.x, -los.y)
	elif source is Aircraft and target and is_instance_valid(target) and missile_params:
		initial_heading = _compute_lead_launch_heading(source, target, missile_params)
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

	# 近炸引信：仅 Aircraft 有此属性。连锁弹头已统一为直线穿透快照。
	if source is Aircraft:
		missile.proximity_aoe = source.missile_proximity_aoe

	add_child(missile)
	return missile


## 普通飞机导弹的离架方向：两轮 TTI 预测前置点，并限制为机头 ±60°。
## 上层发射纪律通常会把实际偏角收得更小；这里的钳位只防止异常几何爆角。
func _compute_lead_launch_heading(source: CombatUnit, target: CombatUnit,
		msl: MissileParams) -> float:
	var lead := AircraftWeapons.missile_lead_point(
		source.global_position, source.speed,
		target.global_position, target.heading,
		target.speed, msl.max_speed)
	# 与发射门、发射前 planner 共享两轮 TTI 前置点。
	# 此处只保留离架 ±60° 的容错钳位。
	# 正常发射窗口会在上层把实际偏角收得更小。
	# 不在此处重复一套独立的前置解算。

	var to_lead := lead - source.global_position
	var lead_heading := atan2(to_lead.x, -to_lead.y)
	var offset := wrapf(lead_heading - source.heading, -PI, PI)
	return source.heading + clampf(offset, -deg_to_rad(60.0), deg_to_rad(60.0))

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
					"sensor_contact_hidden": is_ac and (tgt as Aircraft).is_hidden_from_player_sensors(),
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

## Missile 调用：战斗遮蔽物在位（按 256px 网格 + 高度档量化共享）
func get_in_cloud(world_pos: Vector2, altitude_m: float = 10000.0) -> bool:
	# 离线测试可显式注入 weather；包络仿真则创建无父节点、无 weather 的管理器。
	var tree: SceneTree = get_tree() if get_parent() != null else null
	if not SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT:
		var w: Node = _weather_ref if _weather_ref != null \
			else (tree.get_first_node_in_group("weather") if tree != null else null)
		if w == null:
			return false
		return w.is_obscured(world_pos, altitude_m) if w.has_method("is_obscured") \
			else (altitude_m >= 7500.0 and w.has_method("is_in_cloud") and w.is_in_cloud(world_pos))
	var altitude_band := 0 if altitude_m < 3500.0 else (2 if altitude_m >= 7500.0 else 1)
	var grid := Vector3i(int(world_pos.x / _CLOUD_SNAP_GRID_PX),
		int(world_pos.y / _CLOUD_SNAP_GRID_PX), altitude_band)
	if _cloud_snap.has(grid):
		return _cloud_snap[grid]
	if _weather_ref == null and tree != null:
		_weather_ref = tree.get_first_node_in_group("weather")
	var in_c: bool = false
	if _weather_ref != null:
		in_c = _weather_ref.is_obscured(world_pos, altitude_m) \
			if _weather_ref.has_method("is_obscured") else \
			(altitude_m >= 7500.0 and _weather_ref.has_method("is_in_cloud") \
			and _weather_ref.is_in_cloud(world_pos))
	_cloud_snap[grid] = in_c
	return in_c


## 远距气氛导弹只跟踪自己的既定目标并在其附近播放命中表现。
## 返回 true 表示该弹伤害倍率为 0，调用方必须跳过全体目标命中扫描。
func _update_visual_only_ambient_missile(missile: Missile, fuse_radius_px: float) -> bool:
	var ambient_mult := float(missile.get_meta(
		CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 1.0))
	if ambient_mult > 0.0:
		return false
	# 跨帧对象边界必须先按 Variant 验证，不能先做 typed assignment。
	var target_value: Variant = missile.target
	if typeof(target_value) != TYPE_OBJECT or target_value == null \
			or not is_instance_valid(target_value):
		return true
	var target := target_value as CombatUnit
	if target == null or target.is_destroyed:
		return true
	var effective_fuse := fuse_radius_px
	if target is NavalUnit:
		var naval_target := target as NavalUnit
		if naval_target.params:
			effective_fuse = maxf(effective_fuse, naval_target.params.hull_length * 0.5)
	var flat := target is Aircraft and target.flat_altitude
	var alt_ok := flat or target is GroundUnit or target is NavalUnit \
		or absf(missile.altitude - target.altitude) < missile.params.proximity_fuse_alt
	if missile.global_position.distance_to(target.global_position) >= effective_fuse or not alt_ok:
		return true
	var missile_name: String = missile.params.display_name if missile.params else "MSL"
	var target_name: String = target.callsign if target.callsign != "" else target.name
	EventLogger.log_event("MISSILE", missile_name,
		"visual hit %s (dmg=0)" % target_name)
	var hit_heading: float = target.heading if "heading" in target else 0.0
	ExplosionVFXScript.emit(get_tree(), target.global_position, hit_heading, 1.0)
	var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
	AudioManager.play_sfx_2d(bomb_ids[randi() % 4], target.global_position, 9.0)
	missile.is_active = false
	missile.queue_free()
	return true

func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_rebuild_target_grid()
	var broadphase_queries := 0
	var broadphase_candidates := 0
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

		# 定距空爆弹在达到累计路径前不建立直接命中；到点只生成 AOE 并销毁弹体。
		# 放在建筑拦截之后，保留低空 VLS 被街区挡下的既有规则。
		if missile.params.distance_airburst_distance_m > 0.0:
			if not distance_airburst_ready(missile):
				continue
			_detonate_distance_airburst(missile)
			continue

		# 命中检测：空间网格只返回邻近小单位 + 全部舰船；候选仍按旧 target_list 顺序处理。
		var fuse_radius_px := missile.params.proximity_fuse_radius * PIXELS_PER_METER
		if _update_visual_only_ambient_missile(missile, fuse_radius_px):
			continue
		var target_candidates: Array = _ordered_target_candidates(missile.global_position)
		broadphase_queries += 1
		broadphase_candidates += target_candidates.size()
		for unit_value in target_candidates:
			if typeof(unit_value) != TYPE_OBJECT or unit_value == null \
					or not is_instance_valid(unit_value):
				continue
			var unit := unit_value as CombatUnit
			if unit == null or unit.is_destroyed:
				continue
			if not CombatUnit.teams_hostile(unit.team, missile.team):
				continue
			if missile.penetrates_after_hit and missile.already_penetrated(unit):
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
				# ACTIVE 窗口内不建立接触/近炸命中；导弹保留目标并继续飞行。
				var direct_kind := "qmaam" if missile.is_secondary_weapon else "missile"
				if not WeaponHitResolverScript.can_accept_unit_hit(unit, direct_kind):
					continue
				# 普通云/HIGH 与沙尘暴/LOW 共用同一密度 miss roll（导弹“看不清”目标）。
				var weather := get_tree().get_first_node_in_group("weather")
				if weather:
					var density: float = weather.sample_obscurant_density(unit.global_position, unit.altitude) \
						if weather.has_method("sample_obscurant_density") else \
						(weather.sample_density(unit.global_position) \
						if unit.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH \
						and weather.has_method("sample_density") else 0.0)
					if density > 0.0 and randf() < 0.35 * density:
						continue  # 擦身而过，导弹继续飞
				var msl_name: String = missile.params.display_name if missile.params else "MSL"
				# 加力窗口滚转躲弹（spec afterburner-mode）：命中瞬间 90% 甩偏——
				# 弹置 is_flare_jammed 走既有偏飞契约（不再参与命中/CIWS 拦截/补射计伤），
				# 目标触发滚转动画；10% = "非常极限的情况"照常命中。jam 后本弹不会再进
				# 此分支、失败当帧即爆 → 每弹天然只 roll 一次。与热诱弹无关（无 flare 兜底层）。
				if unit is Aircraft and (unit as Aircraft).is_afterburner_mode_active():
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
				var ambient_mult := float(missile.get_meta(
					CombatUnit.META_AMBIENT_DAMAGE_MULTIPLIER, 1.0))
				var effective_damage := missile.params.damage * ambient_mult
				EventLogger.log_event("MISSILE", msl_name,
					"hit %s (dmg=%.0f)" % [tgt_name, effective_damage])
				# 战报：命中归到射手名下（命中行主体是弹种，这里按 source 计数）
				if is_instance_valid(missile.source):
					var _shooter := missile.source
					var _sn: String = _shooter._log_name() if _shooter.has_method("_log_name") \
							else (_shooter.callsign if ("callsign" in _shooter and _shooter.callsign != "") else String(_shooter.name))
					EventLogger.tally(_sn, "msl_hit")
				var hit_heading: float = unit.heading if "heading" in unit else 0.0
				var incoming_velocity := Vector2(sin(missile.heading), -cos(missile.heading)) \
					* missile.speed
				var impact_pos := unit.global_position
				if unit is Aircraft:
					impact_pos = AircraftDestruction.record_hit(
						unit as Aircraft, missile.global_position, incoming_velocity)
				# 命中只播放一次普通方框，并贴合真实机体分区而不是永远落在中心。
				ExplosionVFXScript.emit(get_tree(), impact_pos, hit_heading, 1.0)
				# 爆炸音效：4 种 bomb_distant 随机选一种
				var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
				AudioManager.play_sfx_2d(bomb_ids[randi() % 4], unit.global_position, 9.0)
				var sig_msl_dmg: float = effective_damage
				# 722 sig_f15e·对地特化：对地面/舰船单位导弹伤害 ×1.3（发射者持有技能时）
				if is_instance_valid(missile.source) and missile.source is Aircraft \
						and (missile.source as Aircraft).sig_f15e_active and not (unit is Aircraft):
					sig_msl_dmg *= 1.3
				if ambient_mult > 0.0:
					var resolved_damage: float = effective_damage if unit is Aircraft else sig_msl_dmg
					WeaponHitResolverScript.resolve_unit_hit(
						unit, resolved_damage, missile.source, direct_kind,
						missile.global_position, incoming_velocity)
				# 近炸引信：在爆炸点产生 AOE 区域
				if missile.proximity_aoe and effective_damage > 0.0:
					var aoe_source: Node = CombatUnit.safe_attacker(missile.source)
					_spawn_aoe(missile.global_position, missile.altitude,
						effective_damage, missile.team, unit, aoe_source)
				# 连锁弹头逐目标去重。
				if missile.penetrates_after_hit:
					missile.remember_penetration_hit(hit_unit)
				# 连锁弹头：不追踪新目标，严格沿命中瞬间的原航向继续。
				if missile.penetrates_after_hit:
					missile.continue_after_penetration(hit_unit)
					EventLogger.log_event("MISSILE", msl_name,
						"penetrated %s (hits=%d)" % [tgt_name, missile.penetration_hit_count])
					break
				missile.is_active = false
				missile.queue_free()
				break

	# ── AOE 区域更新 ──
	PerfBuckets.count("missile_target_full_pairs", broadphase_queries * target_list.size())
	PerfBuckets.count("missile_target_candidates", broadphase_candidates)
	_update_aoe_zones(delta)
	# ── 命中闪光更新 ──
	_update_hit_flashes(delta)
	# ── 帧级共享快照构建（放在命中检测之后；保证击杀已结算的目标 is_destroyed=true 写入快照，
	#    供同帧后运行的 Missile._physics_process 读取，与改动前直接读 target.is_destroyed 一致）──
	_build_frame_snapshot()
	# 性能埋点（此前 MissileManager 全无 PerfBuckets 覆盖）：命中检测 + AOE + 命中闪光 + 快照
	PerfBuckets.tick("missile_phys", Time.get_ticks_usec() - _t0)
	PerfBuckets.set_value("missile_count", get_child_count())

## 定距空爆纯规则：用实际累计路径判定，避免弯曲 VLS 用出生点位移提前引爆。
static func distance_airburst_ready(missile: Missile) -> bool:
	if missile == null or missile.params == null:
		return false
	var trigger_m: float = missile.params.distance_airburst_distance_m
	return trigger_m > 0.0 \
		and missile.distance_traveled_px >= trigger_m * PIXELS_PER_METER


func _detonate_distance_airburst(missile: Missile) -> void:
	var p: MissileParams = missile.params
	var msl_name: String = p.display_name if p != null else "MSL"
	ExplosionVFXScript.emit(get_tree(), missile.global_position, missile.heading, 1.4)
	var bomb_ids := ["bomb_distant", "bomb_distant_02", "bomb_distant_03", "bomb_distant_04"]
	AudioManager.play_sfx_2d(bomb_ids[randi() % 4], missile.global_position, 9.0)
	_spawn_aoe(missile.global_position, missile.altitude, p.damage, missile.team, null,
		missile.source, p.distance_airburst_radius_m, p.distance_airburst_duration_s, msl_name)
	EventLogger.log_event("MISSILE", msl_name,
		"distance airburst after %.0fm" % p.distance_airburst_distance_m)
	missile.is_active = false
	missile.queue_free()


## 创建 AOE 区域；半径/持续时间默认沿用玩家近炸引信，BOSS 定距空爆可逐弹覆盖。
func _spawn_aoe(pos: Vector2, alt: float, damage: float, team: int,
		direct_hit: CombatUnit, source: Variant = null, radius_m: float = AOE_RADIUS_M,
		duration_s: float = AOE_DURATION, event_source: String = "ProxFuze") -> void:
	var hit_set := {}
	# 直接命中的单位已受伤，不重复伤害
	if is_instance_valid(direct_hit):
		hit_set[direct_hit.get_instance_id()] = true
	var safe_source: Node = CombatUnit.safe_attacker(source)
	var zone := {
		"pos": pos,
		"altitude": alt,
		"radius_px": maxf(radius_m, 0.0) * PIXELS_PER_METER,
		"time_left": maxf(duration_s, 0.01),
		"max_time": maxf(duration_s, 0.01),
		"damage": damage,
		"team": team,
		"hit_set": hit_set,
		"source": safe_source,
		"event_source": event_source,
	}
	_aoe_zones.append(zone)
	EventLogger.log_event("AOE", event_source,
		"spawned at (%.0f,%.0f) alt=%.0f r=%.0fm dmg=%.0f" % [
			pos.x, pos.y, alt, radius_m, damage])

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
				if not WeaponHitResolverScript.can_accept_unit_hit(unit, "aoe"):
					continue
				# AOE 命中同样只播放一次；飞机按爆心方向贴到机体表面分区。
				var u_head: float = unit.heading if "heading" in unit else 0.0
				var aoe_impact_pos := unit.global_position
				if unit is Aircraft:
					aoe_impact_pos = AircraftDestruction.record_hit(
						unit as Aircraft, zpos, unit.global_position - zpos)
				ExplosionVFXScript.emit(get_tree(), aoe_impact_pos, u_head, 1.0)
				_apply_aoe_damage(unit, zone)
				zhit[uid] = true
				var tgt_name: String = unit.callsign if unit.callsign != "" else unit.name
				EventLogger.log_event("AOE", String(zone.get("event_source", "ProxFuze")),
					"hit %s (dmg=%.0f)" % [tgt_name, zdmg])
		needs_redraw = true
		i -= 1
	if needs_redraw:
		queue_redraw()


## AOE 单位伤害路由；正式区域循环与无头回归共用，视觉仍由调用方负责。
func _apply_aoe_damage(unit: CombatUnit, zone: Dictionary) -> void:
	var zdmg: float = float(zone["damage"])
	var zpos: Vector2 = zone["pos"]
	# AOE 区域在导弹爆炸后还要存活一段时间，这期间发射者被击落是常态。
	WeaponHitResolverScript.resolve_unit_hit(
		unit, zdmg, zone.get("source", null), "aoe", zpos,
		unit.global_position - zpos)

func _draw() -> void:
	ExplosionPresenterScript.draw(self, _aoe_zones, _hit_flashes, global_position)

## 统一爆炸闪光接入点（由 ExplosionVFX.emit 路由而来，外部模块不要直接 call）。
func spawn_flash(pos: Vector2, heading: float = 0.0, scale: float = 1.0) -> void:
	_spawn_hit_flash(pos, heading, scale)


## 飞机击毁专用：把五个原地脉冲排在真实机体结构点上，按四条路线依次点火。
## 这里只保存值类型记录，飞机即使在 0.12s 后释放，剩余爆点仍可独立播放。
func spawn_airframe_wave(pos: Vector2, heading: float,
		half_length_px: float, half_span_px: float, scale: float = 1.0,
		route: int = -1, initial_delay: float = 0.0) -> void:
	var resolved_route := route
	if resolved_route < 0 or resolved_route >= AIRFRAME_WAVE_ROUTE_COUNT:
		resolved_route = _airframe_wave_serial % AIRFRAME_WAVE_ROUTE_COUNT
		_airframe_wave_serial += 1
	var fwd := Vector2(sin(heading), -cos(heading))
	var right := Vector2(cos(heading), sin(heading))
	var order: Array = AIRFRAME_WAVE_ORDERS[resolved_route]
	for step in order.size():
		var point_index: int = int(order[step])
		var local_point: Vector2 = AIRFRAME_STRUCTURE_POINTS[point_index]
		var burst_pos := pos + fwd * local_point.x * maxf(half_length_px, 1.0) \
			+ right * local_point.y * maxf(half_span_px, 1.0)
		_spawn_hit_flash(
			burst_pos,
			heading,
			scale * float(AIRFRAME_POINT_SCALES[point_index]),
			maxf(initial_delay, 0.0) + float(step) * AIRFRAME_WAVE_INTERVAL,
			resolved_route,
			point_index)

## 内部实现：加入一条活动闪光记录
func _spawn_hit_flash(pos: Vector2, heading: float = 0.0, scale: float = 1.0,
		delay: float = 0.0, route: int = -1, point_index: int = -1) -> void:
	var turn_sign := -1.0 if (_hit_flash_serial + maxi(point_index, 0)) % 2 == 0 else 1.0
	_hit_flash_serial += 1
	_hit_flashes.append({
		"pos": pos,
		"time_left": HIT_FLASH_DURATION,
		"delay": maxf(delay, 0.0),
		"heading": heading,
		"scale": maxf(scale, 0.1),
		"turn_sign": turn_sign,
		"route": route,
		"point_index": point_index,
	})
	queue_redraw()

func _update_hit_flashes(delta: float) -> void:
	if _hit_flashes.is_empty():
		return
	var i := _hit_flashes.size() - 1
	while i >= 0:
		var flash: Dictionary = _hit_flashes[i]
		var delay: float = float(flash.get("delay", 0.0))
		if delay > 0.0:
			delay -= delta
			flash["delay"] = maxf(delay, 0.0)
			# 跨过起爆时刻的帧把超出的 delta 计入寿命，避免低帧率下整条波变慢。
			if delay < 0.0:
				flash["time_left"] += delay
		else:
			flash["time_left"] -= delta
		if flash["time_left"] <= 0.0:
			_hit_flashes.remove_at(i)
		i -= 1
	queue_redraw()

func _hit_flash_draw_packet(flash: Dictionary) -> Dictionary:
	return ExplosionPresenterScript.hit_flash_draw_packet(flash, global_position)


## 单个假 3D 方块转成三角面 + 棱线 packet；调用方把全场可见爆点合批提交。
func _hit_flash_cube_packet(pos: Vector2, heading: float, size: float,
		alpha: float) -> Dictionary:
	return ExplosionPresenterScript.hit_flash_cube_packet(pos, heading, size, alpha)

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
		if missile.source != null and is_instance_valid(missile.source) \
				and missile.source.is_sensor_engagement_obscured(unit):
			continue
		var dist := missile.global_position.distance_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best
