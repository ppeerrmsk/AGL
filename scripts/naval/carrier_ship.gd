class_name CarrierShip
extends NavalUnit

## CV 航母 —— 3★ BOSS 核心
##
## 4 挂点：全部 CIWS（艏 +180,0 / 艉 -180,0 / 左舷 0,-45 / 右舷 0,+45）HP 50
## 无主武器 —— 自身不射导弹，全靠 CSG 护航舰防御
## 弱点阈值 2，HP 60；总血 1200
##
## 视觉：覆盖基类的 _draw_hull_placeholder，画一个更像真航母的俯视外形：
##   - 长方形主甲板
##   - 左舷（port）斜角甲板突出（模拟 Nimitz 级的 angled deck）
##   - 右舷（starboard）舰岛（island，舰桥所在）
##
## 舰载机起飞（plan §3.10）：
##   - CV spawn 时附带 2 架"停机"状态的敌方战机（process_mode = DISABLED）
##   - 停机期间 CV 每帧把飞机位置锁在甲板上（跟船移动/转向）
##   - launch_escort_aircraft() 解除停机：process_mode 恢复 INHERIT + 初始化 alt/speed + 给 waypoint
##   - AI 立刻接管，飞机起飞加速爬升，遇到玩家就交战

## 停机位偏移（相对船中心的本地坐标，+X=右舷，+Y=船尾方向）
## 2 架飞机停在飞行甲板靠前位置，一左一右
const DECK_PARK_OFFSETS: Array[Vector2] = [
	Vector2(-20, -80),   # 左舷靠前
	Vector2(20, -80),    # 右舷靠前
]

## 停机中的敌方战机列表
var _parked_escort: Array = []

## CV 被 add_child 到 survivor_mode 之后，外部（NavalZone._spawn_3star）调这个 spawn 舰载机
## scene_root: survivor_mode（需要用里面的 _spawner 创建标准敌机实例）
func spawn_escort_aircraft(scene_root: Node) -> void:
	if scene_root == null or not scene_root.has_method("get") or not ("_spawner" in scene_root):
		push_warning("CarrierShip.spawn_escort_aircraft: scene_root has no _spawner")
		return
	var spawner: Node = scene_root._spawner
	if spawner == null:
		return
	for offset in DECK_PARK_OFFSETS:
		var park_pos := _local_to_world(offset)
		# 用 SurvivorSpawner.EnemyType.MIG (2) 作为舰载战机
		var ac: Aircraft = spawner._create_enemy(2, park_pos, rad_to_deg(heading))
		if ac == null:
			continue
		ac.set_meta("park_offset", offset)
		ac.set_meta("parent_carrier", self)
		ac.set_meta("category", "carrier_escort")
		ac.process_mode = Node.PROCESS_MODE_DISABLED  # 停机冻结
		_parked_escort.append(ac)
	EventLogger.log_event("NAVAL", "EscortParked",
		"%s parked %d escort aircraft" % [full_name, _parked_escort.size()])

## 解除停机，所有舰载机启动起飞流程（NavalZone.on_player_entered 调用）
## 简化版：恢复 process_mode + 初始化低空低速 + waypoint 朝前延伸
## AI 立刻接管完成"加速爬升"并寻敌
func launch_escort_aircraft() -> void:
	if _parked_escort.is_empty():
		return
	for ac in _parked_escort:
		if ac == null or not is_instance_valid(ac):
			continue
		# 初始飞行状态：贴海面低速（2D 里看起来像是"刚从甲板起飞"）
		ac.altitude = 100.0
		ac.speed = 28.0  # ~100 km/h 起飞速度
		# waypoint：船头方向 3000 px 外的点（迫使飞机加速直飞离开甲板）
		var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
		ac.target_position = ac.global_position + fwd * 3000.0
		# 恢复正常处理
		ac.process_mode = Node.PROCESS_MODE_INHERIT
		ac.remove_meta("parent_carrier")
	EventLogger.log_event("NAVAL", "EscortLaunched",
		"%s launched %d escort" % [full_name, _parked_escort.size()])
	_parked_escort.clear()

## CV 每帧把停机中的飞机位置锁在甲板上（船在移动/转向，飞机也要跟着）
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_destroyed:
		return
	for ac in _parked_escort:
		if ac == null or not is_instance_valid(ac):
			continue
		var offset: Vector2 = ac.get_meta("park_offset", Vector2.ZERO)
		ac.global_position = _local_to_world(offset)
		ac.rotation = rotation
		ac.heading = heading

## 航母特殊轮廓 —— 替换基类默认的"船型多边形"
## 本地绘制坐标系：船头朝 -Y（上屏），船尾朝 +Y（下屏），+X = 右舷
func _draw_hull_placeholder() -> void:
	if params == null:
		return
	var L: float = params.hull_length
	var W: float = params.hull_width
	var color: Color = GameConstants.team_color(team)
	var outline_color: Color = color.darkened(0.35)

	# 基础尺寸（本地坐标，船头朝 -Y）
	var half_L: float = L * 0.5
	var half_W: float = W * 0.5
	# 斜角甲板最远伸出点（port 方向加宽）
	var angled_extra: float = half_W * 0.7

	# 主体航母轮廓：10 点多边形（从船头 port 边顺时针）
	# 点的顺序要求：先走右舷一圈到船尾，再从船尾 port 走回船头
	var body: PackedVector2Array = PackedVector2Array([
		# 船头（微收窄，不做尖锐）
		Vector2(0, -half_L),
		Vector2(half_W * 0.7, -half_L * 0.94),
		# 右舷：正常宽度 → 中部舰岛位置有轻微外凸
		Vector2(half_W, -half_L * 0.55),
		Vector2(half_W * 1.08, -half_L * 0.1),   # island 外凸
		Vector2(half_W, half_L * 0.55),
		# 船尾右角 → 船尾 → 船尾 port 角
		Vector2(half_W * 0.92, half_L),
		Vector2(-half_W * 0.92, half_L),
		# Port 舷：斜角甲板从船尾 port 一直伸到船头方向，最宽点在船中偏前
		Vector2(-half_W, half_L * 0.6),
		Vector2(-(half_W + angled_extra), half_L * 0.15),     # 斜角最宽处
		Vector2(-(half_W + angled_extra * 0.6), -half_L * 0.3),
		Vector2(-half_W * 0.6, -half_L * 0.8),
	])
	draw_colored_polygon(body, color)
	# 轮廓线
	for i in range(body.size()):
		var a: Vector2 = body[i]
		var b: Vector2 = body[(i + 1) % body.size()]
		draw_line(a, b, outline_color, 1.5)

	# 飞行甲板中线（视觉：主跑道 + 斜跑道标记）
	var line_color: Color = Color(outline_color.r, outline_color.g, outline_color.b, 0.55)
	# 主跑道：从船尾到斜甲板末端（略 port 偏），呈斜线
	draw_line(
		Vector2(-half_W * 0.15, half_L * 0.95),
		Vector2(-(half_W + angled_extra * 0.4), -half_L * 0.35),
		line_color, 1.5
	)
	# 直跑道（艏尾对齐）
	draw_line(
		Vector2(half_W * 0.05, half_L * 0.9),
		Vector2(half_W * 0.05, -half_L * 0.9),
		line_color, 1.0
	)

	# 舰岛（右舷中部一小块深色矩形，体现舰桥位置）
	var island_color: Color = outline_color.darkened(0.15)
	var island_rect := Rect2(half_W * 0.55, -half_L * 0.2, half_W * 0.35, half_L * 0.3)
	draw_rect(island_rect, island_color)
	# 舰岛外框
	draw_rect(island_rect, color.lightened(0.1), false, 1.0)
