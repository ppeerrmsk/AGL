class_name ZoneManager
extends Node

## 战区管理器 —— 挂在 survivor_mode 下作为子节点
##
## 职责：
##   - spawn_zone(type, pos) / complete_zone / despawn_zone / refresh_zone / change_zone_type
##   - 上限 3 个并存战区（超出时覆盖最老的）
##   - 每帧调各战区 update(player, delta)，驱动玩家进出检测 + 完成判定
##
## 本模块类型无关 —— 任何 Zone 子类都能托管，Debug 面板通过 ZoneType.META 自动发现

const MAX_ACTIVE_ZONES: int = 3

# ── 场景引用 ──
var scene_root: Node = null     ## survivor_mode，用来 add_child 战区 Node2D
var player_ref: Node2D = null   ## player_aircraft

# ── 活跃战区列表 ──
var active_zones: Array[Zone] = []

# ── 信号 ──
signal zone_spawned(zone)
signal zone_completed(zone)
signal zone_despawned(zone)


# ============================================================
#  初始化 / 每帧循环
# ============================================================

func setup(_scene_root: Node, _player_ref: Node2D) -> void:
	scene_root = _scene_root
	player_ref = _player_ref

func _process(delta: float) -> void:
	# 懒更新玩家引用（玩家可能在战区之后重生）
	# 注意：Game Over 时 scene_root.player_aircraft 可能是已释放的实例，
	# 直接赋值给类型化字段会抛 "Trying to assign invalid previously freed instance"
	if player_ref == null or not is_instance_valid(player_ref):
		player_ref = null
		if scene_root and "player_aircraft" in scene_root:
			var pa = scene_root.player_aircraft
			if pa != null and is_instance_valid(pa):
				player_ref = pa

	var zones_snapshot := active_zones.duplicate()  # 防迭代中 complete
	for z in zones_snapshot:
		if z == null or not is_instance_valid(z):
			active_zones.erase(z)
			continue
		z.update(player_ref, delta)


# ============================================================
#  公开 API
# ============================================================

## 生成新战区。如果已达 MAX_ACTIVE_ZONES 上限，自动移除最老的
func spawn_zone(type_id: int, pos: Vector2) -> Zone:
	if scene_root == null:
		push_error("ZoneManager: scene_root not set")
		return null

	var script_path := ZoneType.script_path(type_id)
	if script_path == "":
		push_error("ZoneManager: no script registered for type %d" % type_id)
		return null

	var zone_script: Script = load(script_path)
	if zone_script == null:
		push_error("ZoneManager: failed to load zone script %s" % script_path)
		return null

	# 上限检查：覆盖最老的
	while active_zones.size() >= MAX_ACTIVE_ZONES:
		var oldest := active_zones[0]
		despawn_zone(oldest)

	var zone: Zone = zone_script.new()
	zone.global_position = pos
	scene_root.add_child(zone)

	var cfg := ZoneType.default_config(type_id)
	zone.finalize_spawn(self, scene_root, type_id, cfg)

	active_zones.append(zone)
	zone_spawned.emit(zone)
	EventLogger.log_event("ZONE", "spawn", "%s @ %.0f,%.0f" % [
		ZoneType.display_name(type_id), pos.x, pos.y])
	return zone

## 正常完成战区（走 mark_complete 流程：结算 + 清理动画）
func complete_zone(zone: Zone) -> void:
	if zone == null or not is_instance_valid(zone):
		return
	if not active_zones.has(zone):
		return
	active_zones.erase(zone)
	zone_completed.emit(zone)
	EventLogger.log_event("ZONE", "complete", ZoneType.display_name(zone.type_id))
	zone.mark_complete()

## 强制销毁（Clear / Refresh / Change Type 用）
func despawn_zone(zone: Zone) -> void:
	if zone == null or not is_instance_valid(zone):
		return
	if active_zones.has(zone):
		active_zones.erase(zone)
	zone_despawned.emit(zone)
	EventLogger.log_event("ZONE", "despawn", ZoneType.display_name(zone.type_id))
	zone.force_despawn()

## 刷新（保留位置 / 类型，内部敌人重 spawn）
func refresh_zone(zone: Zone) -> void:
	if zone == null or not is_instance_valid(zone):
		return
	zone.refresh()
	EventLogger.log_event("ZONE", "refresh", ZoneType.display_name(zone.type_id))

## 原地切换类型（位置 / 半径保留）
func change_zone_type(zone: Zone, new_type: int) -> Zone:
	if zone == null or not is_instance_valid(zone):
		return null
	var pos := zone.global_position
	despawn_zone(zone)
	return spawn_zone(new_type, pos)

## 一键 Skip to BOSS：活跃战区全部 complete，然后在玩家附近 spawn 当前阶段 BOSS
func skip_all_and_spawn_boss() -> Zone:
	var zones_snapshot := active_zones.duplicate()
	for z in zones_snapshot:
		complete_zone(z)

	var boss_type := ZoneType.find_boss_type()
	if boss_type == ZoneType.TYPE_NONE:
		push_warning("ZoneManager: no BOSS zone type registered")
		return null

	var spawn_pos := _pick_spawn_pos_near_player(6000.0)
	return spawn_zone(boss_type, spawn_pos)

## 全清（Debug 用）
func clear_all() -> void:
	var zones_snapshot := active_zones.duplicate()
	for z in zones_snapshot:
		despawn_zone(z)

## 只读 getter（Debug 面板用）
func get_active_zones() -> Array[Zone]:
	var valid: Array[Zone] = []
	for z in active_zones:
		if z != null and is_instance_valid(z):
			valid.append(z)
	return valid


# ============================================================
#  工具
# ============================================================

## 在玩家附近（指定距离）随机取一个 spawn 位置
func _pick_spawn_pos_near_player(distance: float) -> Vector2:
	if player_ref and is_instance_valid(player_ref):
		var angle := randf() * TAU
		return player_ref.global_position + Vector2(cos(angle), sin(angle)) * distance
	return Vector2.ZERO
