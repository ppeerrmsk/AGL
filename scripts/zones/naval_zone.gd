class_name NavalZone
extends Zone

## 海上战区 —— 三档星级共用同一个类，编队组成由 config.star_level 决定
##
## 实装状态：
##   1★ = 3 FFG 三角队形 + 直线往返
##   2★ = 1 DDG（旗舰）+ 2 FFG，8 字轨迹
##   3★ = 2 CG（其中 1 艘旗舰）+ 2 DDG + 2 FFG，圆周编队（CV 未实装，暂由 CG 当旗舰）
##
## 生存逻辑：
##   - 战区常驻，无失败条件
##   - 旗舰死 → 整个战区 complete
##   - 1★ / 2★ / 3★ 都是"打掉旗舰即胜"的目标结构（简化实装）

const FrigateShipScript := preload("res://scripts/naval/frigate_ship.gd")
const DestroyerShipScript := preload("res://scripts/naval/destroyer_ship.gd")
const CruiserShipScript := preload("res://scripts/naval/cruiser_ship.gd")
const CarrierShipScript := preload("res://scripts/naval/carrier_ship.gd")

# ── 运行时状态 ──
var star_level: int = 1

# ── 舰队参数 ──
var _ffg_params: Resource = preload("res://resources/naval/frigate_ffg.tres")
var _ddg_params: Resource = preload("res://resources/naval/destroyer_ddg.tres")
var _cg_params: Resource = preload("res://resources/naval/cruiser_cg.tres")
var _cv_params: Resource = preload("res://resources/naval/carrier_cv.tres")


# ============================================================
#  生命期钩子
# ============================================================

func spawn_entities() -> void:
	star_level = int(config.get("star_level", 1))

	match star_level:
		1: _spawn_1star()
		2: _spawn_2star()
		3: _spawn_3star()
		_: push_warning("NavalZone: unknown star_level %d" % star_level)


# ──────── 1★ 护卫巡逻 ────────
## 3 FFG V 字编队 + 直线往返（旗舰领航，僚舰刚体跟随）
## 队长在前，左右僚舰在后斜位。整支舰队作为一个刚体移动，不会各自乱转
func _spawn_1star() -> void:
	var leader_heading_deg: float = 90.0   # 向东航行
	var wp_half: float = radius * 0.75
	var leader_spawn: Vector2 = global_position + Vector2(-wp_half, 0)
	var leader_wps: PackedVector2Array = _linear_waypoints(
			Vector2(global_position.x + wp_half, global_position.y),
			Vector2(global_position.x - wp_half, global_position.y))

	# 队长 FFG（旗舰）
	var leader := _make_ship(FrigateShipScript, _ffg_params, leader_spawn, leader_heading_deg, leader_wps)
	leader.is_mission_target = true
	spawned_entities.append(leader)

	# 2 僚舰 FFG：左后 / 右后（leader 本地坐标：+X 船头, +Y 右舷）
	var wing_offsets: Array[Vector2] = [
		Vector2(-2400, -2000),  # 左后
		Vector2(-2400, 2000),   # 右后
	]
	for off in wing_offsets:
		_spawn_formation_escort(FrigateShipScript, _ffg_params, leader, off)


# ──────── 2★ 驱逐舰编队 ────────
## 1 DDG（旗舰）走 8 字轨迹 + 2 FFG 贴身护航（刚体跟随旗舰）
## 整支编队作为一个刚体沿 8 字走，FFG 不再各自相位错开
func _spawn_2star() -> void:
	# 直线往返：整队朝船头方向航行，U-turn 时一起转
	var wp_half: float = radius * 0.75
	var leader_heading_deg: float = 90.0
	var ddg_spawn: Vector2 = global_position
	var linear_wps: PackedVector2Array = _linear_waypoints(
			Vector2(global_position.x + wp_half, global_position.y),
			Vector2(global_position.x - wp_half, global_position.y))
	var leader := _make_ship(DestroyerShipScript, _ddg_params, ddg_spawn, leader_heading_deg, linear_wps)
	leader.is_mission_target = true
	spawned_entities.append(leader)

	# 2 FFG 拉开护航（左后 / 右后）
	var wing_offsets: Array[Vector2] = [
		Vector2(-2200, -2200),
		Vector2(-2200, 2200),
	]
	for off in wing_offsets:
		_spawn_formation_escort(FrigateShipScript, _ffg_params, leader, off)


# ──────── 3★ 航母战斗群（CSG）────────
## 参考真实 CSG 队形：CV 居中，CG 前翼、DDG 后翼、FFG 远后翼，整支舰队作为刚体一起航行
## CV 走一条跨越战区的大型轨迹，所有护航舰刚体跟随（不再各自绕圈）
func _spawn_3star() -> void:
	var wp_half: float = radius * 0.6
	var leader_heading_deg: float = 90.0
	var cv_spawn: Vector2 = global_position + Vector2(-wp_half, 0)
	# CV 走宽松直线往返（大型 CSG 变向很缓慢）
	var cv_wps: PackedVector2Array = _linear_waypoints(
			Vector2(global_position.x + wp_half, global_position.y),
			Vector2(global_position.x - wp_half, global_position.y))

	var cv := _make_ship(CarrierShipScript, _cv_params, cv_spawn, leader_heading_deg, cv_wps)
	cv.is_mission_target = true
	spawned_entities.append(cv)
	if cv is CarrierShip:
		(cv as CarrierShip).spawn_escort_aircraft(scene_root)

	# CSG 护航阵位（leader 本地坐标：+X 船头, +Y 右舷）—— 拉开足够空间让玩家穿插
	# 前翼 2 CG —— 前方两侧防空领头
	_spawn_formation_escort(CruiserShipScript, _cg_params, cv, Vector2(4000, -3000))
	_spawn_formation_escort(CruiserShipScript, _cg_params, cv, Vector2(4000, 3000))
	# 后翼 2 DDG —— 左右两侧拉开
	_spawn_formation_escort(DestroyerShipScript, _ddg_params, cv, Vector2(-800, -4600))
	_spawn_formation_escort(DestroyerShipScript, _ddg_params, cv, Vector2(-800, 4600))
	# 远后翼 2 FFG —— 后方斜位反潜 / 补盲
	_spawn_formation_escort(FrigateShipScript, _ffg_params, cv, Vector2(-4600, -3500))
	_spawn_formation_escort(FrigateShipScript, _ffg_params, cv, Vector2(-4600, 3500))


## 刚体编队护航 spawn：在 leader 编队位置实例化，并设 formation_leader/offset
## offset 在 leader 本地坐标系（+X=船头, +Y=右舷），将被 NavalUnit._update_formation_follow 使用
func _spawn_formation_escort(ship_class: GDScript, ship_params: Resource, leader: NavalUnit, offset: Vector2) -> void:
	var leader_heading: float = leader.heading
	var fwd := Vector2(sin(leader_heading), -cos(leader_heading))
	var stb := Vector2(cos(leader_heading), sin(leader_heading))
	var spawn_pos: Vector2 = leader.global_position + fwd * offset.x + stb * offset.y
	var heading_deg: float = rad_to_deg(leader_heading)
	# 僚舰不吃 waypoints（formation_leader 非空时 _update_movement 会直接跳过）
	var ship := _make_ship(ship_class, ship_params, spawn_pos, heading_deg, PackedVector2Array())
	ship.formation_leader = leader
	ship.formation_offset = offset
	spawned_entities.append(ship)


# ============================================================
#  spawn 辅助
# ============================================================

## 统一 spawn 流程：实例化 → 设 params + 位置 + 朝向 + waypoints → 注入 manager → add_child
func _make_ship(ship_class: GDScript, ship_params: Resource, spawn_pos: Vector2, heading_deg: float, waypoints: PackedVector2Array) -> NavalUnit:
	var ship: NavalUnit = ship_class.new()
	ship.params = ship_params
	ship.position = spawn_pos
	ship.initial_heading_deg = heading_deg
	ship.waypoints = waypoints
	ship.set_meta("category", "naval_zone")
	ship.set_meta("skip_far_cleanup", true)
	scene_root.add_child(ship)
	_inject_managers(ship)
	return ship

func _inject_managers(ship: NavalUnit) -> void:
	if scene_root == null:
		return
	if "bullet_manager" in scene_root:
		ship.bullet_manager = scene_root.bullet_manager
	if "missile_manager" in scene_root:
		ship.missile_manager = scene_root.missile_manager


# ============================================================
#  轨迹生成器
# ============================================================

## 直线往返：A ↔ B 两点
func _linear_waypoints(start: Vector2, end: Vector2) -> PackedVector2Array:
	return PackedVector2Array([start, end])



# ============================================================
#  完成条件 / 显示
# ============================================================

## 玩家进入战区圆 —— 3★ 触发 CV 舰载机起飞
func on_player_entered() -> void:
	if star_level != 3:
		return
	for e in spawned_entities:
		if e and is_instance_valid(e) and e is CarrierShip:
			(e as CarrierShip).launch_escort_aircraft()

## 所有星级都是"旗舰死 = 任务完成"
func completion_condition() -> bool:
	if spawned_entities.is_empty():
		return false
	for e in spawned_entities:
		if e == null or not is_instance_valid(e):
			continue
		if e.is_mission_target:
			return e.is_destroyed
	return false

func get_display_info() -> Dictionary:
	var objective := "未知目标"
	match star_level:
		1: objective = "击毁护卫舰旗舰"
		2: objective = "击毁驱逐舰旗舰（DDG）"
		3: objective = "击毁航母（CV 旗舰）—— BOSS 战斗群"
	return {
		"name": ZoneType.display_name(type_id),
		"objective": objective,
		"star": star_level,
	}


# ============================================================
#  Debug 面板专属控件
# ============================================================

func build_debug_ui(parent: Container) -> void:
	var info_label := Label.new()
	info_label.text = _fleet_status_text()
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75, 0.85))
	parent.add_child(info_label)

func _fleet_status_text() -> String:
	if spawned_entities.is_empty():
		return "舰队空"
	var alive := 0
	var total := 0
	var names := PackedStringArray()
	for e in spawned_entities:
		total += 1
		if e and is_instance_valid(e):
			if not e.is_destroyed:
				alive += 1
			if e is NavalUnit and e.full_name != "":
				var marker := " [旗舰]" if e.is_mission_target else ""
				names.append(e.full_name + marker)
	return "舰队：%d/%d 存活\n%s" % [alive, total, "\n".join(names)]
