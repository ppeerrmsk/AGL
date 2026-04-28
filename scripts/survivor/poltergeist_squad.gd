## F-14 Poltergeist 中队 —— CarrierStrikeGroup BOSS 第二阶段子 encounter
##
## 继承 AceSquad 基类复用：
##   - 角色分配（CLOSE_FIGHTER + RANGED_STRIKER 二分 pincer）
##   - anchor_position 盘旋模式（让 4 架紧贴航母，玩家远离即回守）
##
## 与 F-47 (WRAITH) 的差异：
##   - 无隐形、无 J-Turn、无协同齐射 —— 标准 BFM
##   - 攻击欲极强、自保极低（誓死保护航母）
##   - CV 沉没时沿 CV heading 依次弹射起飞（staggered catapult launch），
##     每架走 FROZEN → FADING → CATAPULT → FLYING 四阶段，避免剧透 + 营造起飞仪式感
class_name PoltergeistSquad
extends AceSquad

## 弹射状态机
enum LaunchPhase {
	FROZEN,    ## 甲板待命：不可见、不参与物理、不在 HUD 里露面
	FADING,    ## 淡入：modulate.a 从 0 升到 1（物理关，AI 关）
	CATAPULT,  ## 弹射滑跑：沿 CV heading 强制前进（物理开，AI 关）
	FLYING,    ## 入空：AI 接管，进入 AceSquad 组队战斗
}

const FADE_IN_DURATION: float = 0.6       ## 淡入时间
const CATAPULT_DURATION: float = 1.8      ## 弹射滑跑时间
const CATAPULT_INTERVAL: float = 1.4      ## 相邻两次弹射的间隔（秒）
const CATAPULT_TARGET_DIST: float = 3000.0 ## 弹射目标点在机头正前方的距离

var _launch_phases: Array[int] = []       ## 与 all_members 对齐的阶段数组
var _launch_timers: Array[float] = []     ## 每架当前阶段已过时长
var _catapult_queue_timer: float = 0.0    ## 距下一架解冻的倒计时累计

func _init() -> void:
	squad_size = 4
	intro_duration = 0.0                      # 跳过通场表演，直接走弹射阶段
	intro_pass_dist = 400.0
	callsign_prefix = "PLTGST"
	display_name = "POLTERGEIST"
	enemy_type = SurvivorSpawner.EnemyType.F14_POLTERGEIST

	cloak_enabled = false

	# 站位：贴紧玩家合围
	standoff_radius_min = 1000.0
	standoff_radius_max = 2000.0
	ranged_max_distance = 2800.0
	force_pursuit_distance = 2000.0

	xp_per_kill = 80

## 全部 4 架初始落在 anchor（CV 死亡位置，即"甲板"）。
## 由于 #1..#3 在 FROZEN 阶段不可见，物理几何上的排队没有视觉意义；
## 而 _start_fade_in 还会在每架揭幕时把它再次贴到 anchor_position，
## 这样不论间隔多长，玩家看到的每架 F-14 都从航母位置淡入，而不是"凭空出现在航母后方 600 px 的空海"。
## AceSquad.spawn 中 spawn_origin = anchor + entry_dir*800，因此 offset 取 -entry_dir*800 = forward*800 即落在 anchor。
func _get_formation_offsets(entry_dir: Vector2, _lateral_axis: Vector2) -> Array[Vector2]:
	var forward := -entry_dir
	var out: Array[Vector2] = []
	for _i in range(4):
		out.append(forward * 800.0)
	return out

## spawn 后：#0 立刻进入 FADING 阶段；#1..#3 冻结+隐藏等待按序弹射
func spawn(scene_root: Node, aircraft_scene: PackedScene, create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		squads: Array[Squad]) -> void:
	super.spawn(scene_root, aircraft_scene, create_enemy_func, player, bullet_mgr, missile_mgr, squads)
	_launch_phases.clear()
	_launch_timers.clear()
	_catapult_queue_timer = 0.0
	for i in range(all_members.size()):
		_launch_phases.append(LaunchPhase.FROZEN)
		_launch_timers.append(0.0)
		var ac: Aircraft = all_members[i]
		if is_instance_valid(ac):
			# AceSquad.spawn 默认把 BOSS 的 target_tier 设为 HIGH（10000m）。
			# 我们要的是甲板起飞 → LOW → HIGH 的渐进。先压在地面 + 全免伤直到弹射结束。
			ac.altitude = 0.0
			ac.target_altitude = 0.0
			ac.target_altitude_tier = CombatUnit.AltitudeTier.GROUND
			ac.invulnerable = true
		if i > 0 and is_instance_valid(ac):
			ac.process_mode = Node.PROCESS_MODE_DISABLED
			ac.visible = false
	if all_members.size() > 0:
		_start_fade_in(0)
	EventLogger.log_event("BOSS", display_name,
			"catapult sequence armed: %d F-14 (interval=%.1fs)" % [all_members.size(), CATAPULT_INTERVAL])

## 把索引 i 的 F-14 从 FROZEN 切到 FADING（解冻物理、不可见→可见、α=0 开始淡入）
## AI 依旧冻结（到 CATAPULT 结束才还给 AceSquad）
func _start_fade_in(i: int) -> void:
	if i < 0 or i >= all_members.size():
		return
	var ac: Aircraft = all_members[i]
	if not is_instance_valid(ac):
		return
	# 揭幕瞬间贴到当前 anchor（=CV 死亡位置），保证视觉上从"航母位置"淡入而不是 600 px 后方的空海。
	if anchor_position != Vector2.INF:
		ac.global_position = anchor_position
	ac.process_mode = Node.PROCESS_MODE_INHERIT
	ac.visible = true
	ac.modulate.a = 0.0
	var ai: AIController = ac._get_ai_controller()
	if ai:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	_launch_phases[i] = LaunchPhase.FADING
	_launch_timers[i] = 0.0

func update(delta: float) -> void:
	if not active:
		return

	# 1. 每架推进阶段状态机（FADING 淡入 / CATAPULT 倒计时）
	for i in range(all_members.size()):
		var ac: Aircraft = all_members[i]
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		_tick_phase(i, delta)

	# 2. 弹射队列：按 CATAPULT_INTERVAL 把下一架 FROZEN 拨到 FADING
	_catapult_queue_timer += delta
	if _catapult_queue_timer >= CATAPULT_INTERVAL:
		var idx := _find_next_frozen()
		if idx >= 0:
			_start_fade_in(idx)
			_catapult_queue_timer = 0.0

	# 3. 组装 FLYING 成员 + 检查真正全灭
	var flying: Array[Aircraft] = []
	var any_pending: bool = false
	for i in range(all_members.size()):
		var ac2: Aircraft = all_members[i]
		if not is_instance_valid(ac2) or ac2.is_destroyed:
			continue
		if _launch_phases[i] == LaunchPhase.FLYING:
			flying.append(ac2)
		else:
			any_pending = true

	if flying.is_empty() and not any_pending:
		# 全部死光（含在弹射流水线里也挂了的）
		active = false
		EventLogger.log_event("BOSS", display_name, "%s eliminated" % display_name)
		return

	# 4. FROZEN/FADING/CATAPULT 阶段：把高度锁死在地面（弹射滑跑期间不准爬升）
	#    + CATAPULT 阶段强制前进目标点（防 AceSquad 外部写入干扰）
	for i in range(all_members.size()):
		var phase_i: int = _launch_phases[i]
		if phase_i == LaunchPhase.FLYING:
			continue
		var ac3: Aircraft = all_members[i]
		if not is_instance_valid(ac3) or ac3.is_destroyed:
			continue
		ac3.altitude = 0.0
		ac3.target_altitude = 0.0
		ac3.target_altitude_tier = CombatUnit.AltitudeTier.GROUND
		ac3.vertical_speed = 0.0
		if phase_i == LaunchPhase.CATAPULT:
			var fwd := Vector2(sin(ac3.heading), -cos(ac3.heading))
			ac3.target_position = ac3.global_position + fwd * CATAPULT_TARGET_DIST
			ac3.combat_target = null

	# 5. FLYING 阶段：先爬到 LOW，到了再放手让 BOSS 自然爬到 HIGH
	for i in range(all_members.size()):
		if _launch_phases[i] != LaunchPhase.FLYING:
			continue
		var ac4: Aircraft = all_members[i]
		if not is_instance_valid(ac4) or ac4.is_destroyed:
			continue
		if not ac4.has_meta("pltgst_climbed_low"):
			if ac4.altitude >= CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.LOW] * 0.9:
				ac4.set_meta("pltgst_climbed_low", true)
				ac4.set_target_tier(CombatUnit.AltitudeTier.HIGH)

	# 6. 有 FLYING 再把组队战斗逻辑交给 AceSquad（否则直接跳过，不让 super 判"空列表=死亡"）
	if flying.is_empty():
		return
	members = flying
	super.update(delta)

## 推进单架的阶段状态机
func _tick_phase(i: int, delta: float) -> void:
	var phase: int = _launch_phases[i]
	if phase == LaunchPhase.FROZEN or phase == LaunchPhase.FLYING:
		return
	_launch_timers[i] += delta
	var ac: Aircraft = all_members[i]
	var t: float = _launch_timers[i]
	match phase:
		LaunchPhase.FADING:
			ac.modulate.a = clampf(t / FADE_IN_DURATION, 0.0, 1.0)
			if t >= FADE_IN_DURATION:
				ac.modulate.a = 1.0
				_launch_phases[i] = LaunchPhase.CATAPULT
				_launch_timers[i] = 0.0
				EventLogger.log_event("BOSS", display_name,
						"%s fade-in complete, catapult slide begin" % ac.callsign)
		LaunchPhase.CATAPULT:
			if t >= CATAPULT_DURATION:
				_launch_phases[i] = LaunchPhase.FLYING
				_launch_timers[i] = 0.0
				# 离开甲板：先把高度顶离 0（防 _check_ground_crash 在解锁瞬间误杀）+ 给个初始正爬升率
				# 然后解除无敌、目标爬到 LOW（达到 LOW 后由 update() 推到 HIGH）
				ac.altitude = 200.0
				ac.vertical_speed = 30.0
				ac.invulnerable = false
				ac.set_target_tier(CombatUnit.AltitudeTier.LOW)
				var ai: AIController = ac._get_ai_controller()
				if ai:
					ai.process_mode = Node.PROCESS_MODE_INHERIT
				EventLogger.log_event("BOSS", display_name,
						"%s airborne, climbing to LOW" % ac.callsign)

func _find_next_frozen() -> int:
	for i in range(_launch_phases.size()):
		if _launch_phases[i] == LaunchPhase.FROZEN:
			return i
	return -1

## HUD 显示成员：过滤掉 FROZEN（甲板待命的 F-14 不剧透）
## FADING / CATAPULT / FLYING 都上 HUD
func get_display_members() -> Array:
	var out: Array = []
	for i in range(all_members.size()):
		if i < _launch_phases.size() and _launch_phases[i] == LaunchPhase.FROZEN:
			continue
		out.append(all_members[i])
	return out

## 每架 F-14 Poltergeist 挂载赫尔贝特轮（J-Turn 反咬）+ 队长设 salvo_leader
## J-Turn 由 F-47 转移过来：F-47 现在专注 Cloak 隐身特性，F-14 走机动反杀路线
func _configure_spawn(member: Aircraft, index: int, _squad: Squad, ai: AIController) -> void:
	var herbst := HerbstManeuver.new()
	herbst.name = "HerbstManeuver"
	member.add_child(herbst)
	if index == 0 and ai:
		ai.salvo_leader = true
