class_name NavalWeapons
extends RefCounted

## 海上单位武器派发器（静态模块，仿 aircraft/aircraft_weapons.gd 模式）
## 由 NavalUnit._update_subsystems 每帧调用 update(nu, delta)
## 按挂点类型路由到具体武器更新函数

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

# ── CIWS 常量 ──
# 真 Phalanx 观感：超高射速 + 视觉弹幕，但只有少量子弹真正造成伤害
# 每 N 发里夹 1 发"真弹"参与命中判定，其余是纯视觉装饰（visual_only），
# 避免画面密集但伤害爆炸的失衡，同时保持 CIWS 连射的观感
const CIWS_INTERCEPT_RANGE_PX: float = 1400.0    ## CIWS 拦截导弹射程
const CIWS_TRACER_RANGE_PX: float = 1000.0       ## CIWS 对空扫射射程
const CIWS_FIRE_INTERVAL: float = 0.030          ## 视觉射速：~33 Hz 连射（接近真 Phalanx）
const CIWS_REAL_BULLET_CYCLE: int = 3            ## 每 3 发里 1 发真弹（有效伤害射速 ~11 Hz）
const CIWS_BULLET_SPEED_MS: float = 900.0        ## 子弹初速
const CIWS_ENGAGE_COOLDOWN: float = 0.6          ## 导弹拦截结束后冷却

# 拦截导弹参数
# 目标平衡：玩家连发两枚时 CIWS 只拦得住第一发，第二发穿防
#   60HP 导弹 × 约 3.2Hz 真弹 × ~15% 命中率 × 10HP ≈ 4.8HP/sec
#   → 单发拦截要 ~12 秒才能打完（导弹飞完全程只需 ~4 秒，所以单发也经常漏）
#   → 需要 CIWS 在导弹很近时才真正能打中，观感："拦不下来，但一直在试"
const CIWS_MISSILE_SPREAD_DEG: float = 5.0       ## 锁定导弹时 ±5° 散布
const CIWS_DAMAGE_PER_BULLET: float = 10.0       ## 每发真弹命中导弹 10 HP

# 对空扫射参数
const CIWS_TRACER_SPREAD_DEG: float = 7.0        ## 朝玩家射击时 ±7° 散布
const CIWS_TRACER_DAMAGE: float = 3.0            ## 每发真弹对飞机伤害（极低，纯气氛）
const CIWS_TRACER_MAX_ALTITUDE: float = 7500.0   ## 玩家高于此高度 → 不扫射（纯装饰无威胁）

# ── SAM 短程 / VLS 常量（步骤 2 只用 SAM_SHORT）──
const SAM_SHORT_COOLDOWN: float = 6.0            ## 短程 SAM 再次发射间隔
const SAM_SHORT_MIN_RANGE_M: float = 300.0       ## 最小射程（米）

## 每帧入口
static func update(nu: NavalUnit, delta: float) -> void:
	if nu == null or nu.is_destroyed:
		return

	for m in nu.mounts:
		if m.destroyed or m.params == null:
			continue
		match m.params.weapon_type:
			WeaponMountParams.WeaponType.CIWS:
				_update_ciws(nu, m, delta)
			WeaponMountParams.WeaponType.SAM_SHORT:
				_update_sam_short(nu, m, delta)
			WeaponMountParams.WeaponType.VLS_SALVO:
				_update_vls_salvo(nu, m, delta)

# ==================================================
#  CIWS — 双模式（导弹拦截优先 / 对空扫射兜底）
# ==================================================

## CIWS 更新入口：连续高射速单发模式（真 Phalanx 观感）
## 优先级：已锁定导弹 → 搜索新导弹 → 对玩家扫射
## 单发一颗，依靠高射速 + 高散布制造弹幕感，命中率低
static func _update_ciws(nu: NavalUnit, mount: WeaponMount, _delta: float) -> void:
	if nu.bullet_manager == null:
		return

	# 模式 A：已锁定来袭导弹 → 继续拦截（子弹带 is_ciws=true，能碰撞导弹）
	if mount.engaged_missile != null:
		var eng: Missile = mount.engaged_missile as Missile
		if eng == null or not is_instance_valid(eng) or not _missile_still_threat(eng, nu):
			mount.engaged_missile = null
			mount.engage_cooldown = CIWS_ENGAGE_COOLDOWN
			return
		_ciws_fire_single(nu, mount, eng.global_position, CIWS_MISSILE_SPREAD_DEG, CIWS_DAMAGE_PER_BULLET, true)
		return

	# 模式 A 搜索：冷却结束后寻找新来袭导弹
	if mount.engage_cooldown <= 0.0:
		var target_missile := _find_incoming_missile_for_ciws(nu, mount)
		if target_missile != null:
			mount.engaged_missile = target_missile
			mount.fire_cooldown = 0.0  # 立即开火
			return

	# 模式 B：对空扫射（子弹**不带** is_ciws 标记 —— 只能打飞机，不会误撞路过的导弹）
	# 避免"玩家刚发射导弹，CIWS 朝玩家扫射的子弹把自己发的导弹拦下来"这种违反直觉的场面
	var player := _find_player_in_ciws_range(nu, mount)
	if player != null:
		_ciws_fire_single(nu, mount, player.global_position, CIWS_TRACER_SPREAD_DEG, CIWS_TRACER_DAMAGE, false)

## 单发开火 —— CIWS 的原子射击动作
## 每 CIWS_REAL_BULLET_CYCLE 发里只有 1 发是真弹（参与命中 + 造成伤害），
## 其余都是 visual_only 视觉装饰弹。这样画面密集但伤害曲线不过载。
## target_pos: 瞄准点（导弹 / 玩家当前位置；故意不做前置量，让高射速自行解决）
## spread_deg: 角度散布（拦截导弹小 / 对空扫射大）
## damage: 真弹单发伤害（装饰弹恒为 0）
## can_hit_missile: true=拦截模式（bullet_manager 会把它和导弹碰撞），false=扫射模式（只打飞机）
static func _ciws_fire_single(nu: NavalUnit, mount: WeaponMount, target_pos: Vector2, spread_deg: float, damage: float, can_hit_missile: bool) -> void:
	if mount.fire_cooldown > 0.0:
		return
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var to_tgt := target_pos - mount_pos
	var dist := to_tgt.length()
	if dist < 1.0:
		return

	var base_dir := atan2(to_tgt.x, -to_tgt.y)
	var spread_rad := deg_to_rad(spread_deg)
	var dir := base_dir + randf_range(-spread_rad, spread_rad)

	# 决定这发是真弹还是装饰弹
	mount.ciws_shot_counter += 1
	var is_real: bool = (mount.ciws_shot_counter % CIWS_REAL_BULLET_CYCLE) == 0
	var bullet_dmg: float = damage if is_real else 0.0
	var visual_only: bool = not is_real

	nu.bullet_manager.spawn_bullet(mount_pos, dir, CIWS_BULLET_SPEED_MS, nu, bullet_dmg, can_hit_missile, visual_only)
	mount.fire_cooldown = CIWS_FIRE_INTERVAL

## 查找射程内最近的、未被其他 CIWS engaged 的玩家导弹
static func _find_incoming_missile_for_ciws(nu: NavalUnit, mount: WeaponMount) -> Node2D:
	if nu.missile_manager == null:
		return null
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var best: Node2D = null
	var best_d := CIWS_INTERCEPT_RANGE_PX
	for child in nu.missile_manager.get_children():
		if not is_instance_valid(child):
			continue
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active or m.team == nu.team:
			continue
		if not _missile_still_threat(m, nu):
			continue
		# 排除已被其他 CIWS engaged 的导弹
		if _missile_already_engaged(nu, m, mount):
			continue
		var d := mount_pos.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best

## 导弹是否还是威胁：活跃 + 朝本船或附近飞
static func _missile_still_threat(m: Missile, nu: NavalUnit) -> bool:
	if not m.is_active:
		return false
	# 粗略：导弹速度向量指向本船方向即视为威胁
	var to_ship: Vector2 = nu.global_position - m.global_position
	if to_ship.length() < 1.0:
		return true
	var m_fwd := Vector2(sin(m.heading), -cos(m.heading))
	return m_fwd.dot(to_ship.normalized()) > 0.0

## 检查某导弹是否已被本船其他 CIWS 挂点锁定
static func _missile_already_engaged(nu: NavalUnit, m: Missile, current_mount: WeaponMount) -> bool:
	for other in nu.mounts:
		if other == current_mount or other.destroyed:
			continue
		if other.params == null or other.params.weapon_type != WeaponMountParams.WeaponType.CIWS:
			continue
		if other.engaged_missile == m:
			return true
	return false

## 查找 CIWS 对空扫射射程内的玩家飞机（team=0）
## 门禁比导弹拦截严：距离 < CIWS_TRACER_RANGE_PX 且高度 < CIWS_TRACER_MAX_ALTITUDE
## 不满足两条件之一 → CIWS 保持静默，不做"无意义扫射"
static func _find_player_in_ciws_range(nu: NavalUnit, mount: WeaponMount) -> CombatUnit:
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var best: CombatUnit = null
	var best_d := CIWS_TRACER_RANGE_PX
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed or u.team == nu.team:
			continue
		# ⚠ is_instance_valid + is_destroyed 之后再做 `is Aircraft`，防护顺序不能反
		if not u is Aircraft:
			continue
		# 高度门禁：HIGH 档以上不开火（散布太大，纯装饰无威胁，干脆静默）
		if u.altitude >= CIWS_TRACER_MAX_ALTITUDE:
			continue
		var d := mount_pos.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ==================================================
#  SAM 短程（FFG 主武器）
# ==================================================

static func _update_sam_short(nu: NavalUnit, mount: WeaponMount, _delta: float) -> void:
	if nu.missile_manager == null:
		return
	if mount.fire_cooldown > 0.0:
		return
	if mount.params == null or mount.params.weapon_params == null:
		return
	var missile_params := mount.params.weapon_params as MissileParams
	if missile_params == null:
		return

	# 搜索目标：射程内最近的玩家方飞机
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var max_range_px: float = missile_params.max_range_rear * missile_params.front_rear_ratio * PIXELS_PER_METER
	var min_range_px: float = SAM_SHORT_MIN_RANGE_M * PIXELS_PER_METER

	var target: CombatUnit = null
	var best_d := max_range_px
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed or u.team == nu.team:
			continue
		if not u is Aircraft:
			continue
		if u.is_lock_immune() or (u is Aircraft and u.is_cloaked):
			continue
		var d := mount_pos.distance_to(u.global_position)
		if d < min_range_px or d > max_range_px:
			continue
		if d < best_d:
			best_d = d
			target = u

	if target == null:
		return

	# 限制：每船每目标一枚在飞（避免过载）
	if nu.missile_manager.has_active_missile_at(nu, target):
		return

	nu.missile_manager.spawn_missile(nu, target, missile_params)
	mount.fire_cooldown = SAM_SHORT_COOLDOWN

# ==================================================
#  VLS 齐射（DDG / CG 主武器）
# ==================================================
## 一波 salvo_size 枚导弹以 salvo_interval 间隔连续射出，每枚低 PN 增益 + 低最大 G
## 单发威胁弱，靠数量和覆盖面制造压力；玩家可用机动甩掉大部分
static func _update_vls_salvo(nu: NavalUnit, mount: WeaponMount, delta: float) -> void:
	if nu.missile_manager == null or mount.params == null:
		return
	var missile_params := mount.params.weapon_params as MissileParams
	if missile_params == null or not missile_params.is_vls_salvo:
		return

	# 齐射进行中：按 salvo_interval 节奏射出剩余弹
	if mount.salvo_remaining > 0:
		mount.salvo_delay = maxf(mount.salvo_delay - delta, 0.0)
		if mount.salvo_delay <= 0.0:
			_fire_one_vls_missile(nu, mount, missile_params)
			mount.salvo_remaining -= 1
			mount.salvo_delay = missile_params.vls_salvo_interval
		return

	# 两波齐射之间的冷却
	if mount.fire_cooldown > 0.0:
		return

	# 搜索目标：射程内最近的玩家方飞机
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var max_range_px: float = missile_params.max_range_rear * missile_params.front_rear_ratio * PIXELS_PER_METER
	var min_range_px: float = missile_params.min_range * PIXELS_PER_METER

	var target: CombatUnit = null
	var best_d := max_range_px
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed or u.team == nu.team:
			continue
		if not u is Aircraft:
			continue
		if u.is_lock_immune() or (u is Aircraft and u.is_cloaked):
			continue
		var d := mount_pos.distance_to(u.global_position)
		if d < min_range_px or d > max_range_px:
			continue
		if d < best_d:
			best_d = d
			target = u

	if target == null:
		return

	# 启动新的齐射
	mount.salvo_remaining = missile_params.vls_salvo_size
	mount.salvo_delay = 0.0  # 第一发立即射
	mount.fire_cooldown = missile_params.vls_salvo_cooldown
	# 保存目标引用在 mount.engaged_missile 字段（复用，当前已有这个字段）—— 不行，engaged_missile 是导弹类型
	# 用 mount 的一个新字段存 target? 或者每次重新搜索
	# 简化：每发都重新搜索最近目标（齐射过程 0.4s 内目标基本不变，够用）
	# 第一发立即射出
	_fire_one_vls_missile(nu, mount, missile_params)
	mount.salvo_remaining -= 1
	mount.salvo_delay = missile_params.vls_salvo_interval

## 射出单发 VLS 齐射弹 —— 独立搜索目标 + 每发带速度乱数 + 锁定点在玩家附近散布
## 三段式弹道（垂直爬升 → 过渡 → 末端 PN）由 missile.gd::_update_vls_non_terminal 实现
static func _fire_one_vls_missile(nu: NavalUnit, mount: WeaponMount, missile_params: MissileParams) -> void:
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var max_range_px: float = missile_params.max_range_rear * missile_params.front_rear_ratio * PIXELS_PER_METER

	var target: CombatUnit = null
	var best_d := max_range_px
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed or u.team == nu.team:
			continue
		if not u is Aircraft:
			continue
		if u.is_lock_immune() or (u is Aircraft and u.is_cloaked):
			continue
		var d := mount_pos.distance_to(u.global_position)
		if d > max_range_px:
			continue
		if d < best_d:
			best_d = d
			target = u

	if target == null:
		return

	var m := nu.missile_manager.spawn_missile(nu, target, missile_params)
	if m == null:
		return

	# VLS 专属参数：锁死当前玩家位置 + 散布 + 速度乱数
	var scatter: float = missile_params.vls_point_scatter_px
	var off_angle: float = randf() * TAU
	var off_radius: float = randf() * scatter
	m.vls_locked_point = target.global_position + Vector2(cos(off_angle), sin(off_angle)) * off_radius

	# 速度乱数：0.8 ~ 1.2 之间，让同一波齐射弹快慢错开，不完全重叠
	var variance: float = missile_params.vls_speed_variance
	m.speed_multiplier = 1.0 + randf_range(-variance, variance)

	# 每发 VLS 挂点出弹位置也加点随机偏移（避免所有弹同一点起飞）
	var launch_offset: Vector2 = Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	m.global_position += launch_offset
