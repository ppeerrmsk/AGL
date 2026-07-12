class_name NavalWeapons
extends RefCounted

## 海上单位武器派发器（静态模块，仿 aircraft/aircraft_weapons.gd 模式）
## 由 NavalUnit._update_subsystems 每帧调用 update(nu, delta)
## 按挂点类型路由到具体武器更新函数

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

## CIWS 目标获取节流间隔 —— 每 ACQUIRE_INTERVAL 才重做一次"找近距飞机/找来袭导弹/找玩家"扫描
## 期间只复用上次找到的 engaged_missile / cached_close / cached_player 决策
## 0.15s 反应延迟对 CIWS 距离 1400px / 导弹 600m·s 飞行时间 4.7s 来说足够；
## 单舰 12 CIWS × 60Hz × 3 全场扫描 → 12 × 6.7Hz × 3，CSG 时直接砍 ~90% 扫描开销
const CIWS_ACQUIRE_INTERVAL: float = 0.15

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
const CIWS_TRACER_SPREAD_DEG: float = 7.0        ## 朝玩家射击时 ±7° 散布（远距装饰）
const CIWS_TRACER_DAMAGE: float = 3.0            ## 每发真弹对飞机伤害（极低，纯气氛）
const CIWS_TRACER_MAX_ALTITUDE: float = 7500.0   ## 玩家高于此高度 → 不扫射（纯装饰无威胁）

## CIWS 近距反飞机（越过 CIWS_CLOSE_RANGE_PX 时无视导弹锁定，优先攻击玩家）
## 距离内散布更紧 + 伤害更高，让"飞太贴近 CIWS 会被撕碎"
const CIWS_CLOSE_RANGE_PX: float = 650.0         ## 切到近距反飞机模式的距离阈值
const CIWS_CLOSE_SPREAD_DEG: float = 3.5         ## 近距散布（接近拦截导弹的精度）
const CIWS_CLOSE_DAMAGE: float = 8.0             ## 近距真弹伤害（介于 tracer 3 和拦截 10 之间）

# ── SAM 短程 / VLS 常量（步骤 2 只用 SAM_SHORT）──
const SAM_SHORT_COOLDOWN: float = 6.0            ## 短程 SAM 再次发射间隔
const SAM_SHORT_MIN_RANGE_M: float = 300.0       ## 最小射程（米）

## 每帧入口
static func update(nu: NavalUnit, delta: float) -> void:
	if nu == null or nu.is_destroyed:
		return
	# JAM 状态：所有挂点武器禁射（与 aa_gun_unit / aircraft_weapons 早返路径对称）
	if nu.status_jam_active:
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
			WeaponMountParams.WeaponType.NAVAL_AA:
				_update_naval_aa(nu, m, delta)

# ==================================================
#  CIWS — 双模式（导弹拦截优先 / 对空扫射兜底）
# ==================================================

## CIWS 更新入口：连续高射速单发模式（真 Phalanx 观感）
## 优先级（由近到远）：
##   1. 近距反飞机（< CIWS_CLOSE_RANGE_PX）：无视导弹锁定，紧散布 + 真伤打玩家
##   2. 已锁定来袭导弹 → 继续拦截
##   3. 搜索新来袭导弹 → 锁定
##   4. 中远距对空扫射（< CIWS_TRACER_RANGE_PX）：大散布 + 装饰伤害
## 单发一颗，依靠高射速 + 散布制造弹幕感
static func _update_ciws(nu: NavalUnit, mount: WeaponMount, _delta: float) -> void:
	if nu.bullet_manager == null:
		return

	# ── 节流路径（acquire_cooldown > 0）──
	# 复用上次扫描得到的决策。已锁定的导弹仍按帧检查 still_threat（廉价），
	# cached_aircraft_target 仅按帧验证 is_instance_valid，不重做全场扫描。
	if mount.acquire_cooldown > 0.0:
		# 优先：已锁定来袭导弹 → 继续拦截
		if mount.engaged_missile != null:
			var eng_t: Missile = mount.engaged_missile as Missile
			if eng_t == null or not is_instance_valid(eng_t) or not _missile_still_threat(eng_t, nu):
				mount.engaged_missile = null
				mount.engage_cooldown = CIWS_ENGAGE_COOLDOWN
			else:
				_ciws_fire_single(nu, mount, eng_t.global_position, CIWS_MISSILE_SPREAD_DEG, CIWS_DAMAGE_PER_BULLET, true)
				return
		# 次：使用缓存的飞机目标继续开火
		var cached: Node2D = mount.cached_aircraft_target
		if cached != null and is_instance_valid(cached) and not (cached as CombatUnit).is_destroyed:
			match mount.cached_aircraft_kind:
				1:
					_ciws_fire_single(nu, mount, cached.global_position, CIWS_CLOSE_SPREAD_DEG, CIWS_CLOSE_DAMAGE, false)
				2:
					_ciws_fire_single(nu, mount, cached.global_position, CIWS_TRACER_SPREAD_DEG, CIWS_TRACER_DAMAGE, false)
			return
		# 缓存的飞机目标失效 → 让本帧落到下方完整扫描分支去刷新（清掉 cooldown）
		mount.cached_aircraft_target = null
		mount.cached_aircraft_kind = 0
		mount.acquire_cooldown = 0.0

	# ── 完整扫描路径（acquire_cooldown == 0）──
	# 重置缓存，下面分支会按需写回
	mount.cached_aircraft_target = null
	mount.cached_aircraft_kind = 0
	mount.acquire_cooldown = CIWS_ACQUIRE_INTERVAL

	# 模式 0：飞机已经飞到 CIWS 嘴边 → 无视导弹，紧散布 + 真伤轰击玩家
	# 这一层让"贴脸飞过 CIWS"成为不合算的选择：高命中率 + 中等伤害，短时间能撕薄血皮
	var close_ac := _find_aircraft_in_range(nu, mount, CIWS_CLOSE_RANGE_PX, CIWS_TRACER_MAX_ALTITUDE)
	if close_ac != null:
		# 放弃之前锁的导弹（玩家近了才是真威胁）
		if mount.engaged_missile != null:
			mount.engaged_missile = null
			mount.engage_cooldown = CIWS_ENGAGE_COOLDOWN
		mount.cached_aircraft_target = close_ac
		mount.cached_aircraft_kind = 1
		_ciws_fire_single(nu, mount, close_ac.global_position, CIWS_CLOSE_SPREAD_DEG, CIWS_CLOSE_DAMAGE, false)
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
		mount.cached_aircraft_target = player
		mount.cached_aircraft_kind = 2
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
## 优先用 BulletManager 帧级缓存（CSG 战 12 个 CIWS 共用一份预过滤的"敌方活跃导弹"列表，
## 避免 12 × N 次 missile_manager.get_children() 全场扫）
static func _find_incoming_missile_for_ciws(nu: NavalUnit, mount: WeaponMount) -> Node2D:
	if nu.missile_manager == null:
		return null
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var best: Node2D = null
	var best_d := CIWS_INTERCEPT_RANGE_PX

	var candidates: Array = []
	if SurvivorData.ENABLE_BULLET_FRAME_CACHE and nu.bullet_manager != null \
			and nu.bullet_manager.has_method("get_enemy_missiles_for_team"):
		candidates = nu.bullet_manager.get_enemy_missiles_for_team(nu.team)
	if candidates.is_empty():
		# 缓存关闭 / BulletManager 未连 → 走原始路径
		for child in nu.missile_manager.get_children():
			if (child is Missile) and (child as Missile).is_active and CombatUnit.teams_hostile((child as Missile).team, nu.team):
				candidates.append(child)

	for c in candidates:
		if not is_instance_valid(c):
			continue
		var m: Missile = c as Missile
		if m == null or not m.is_active:
			continue
		if not _missile_still_threat(m, nu):
			continue
		# 排除已被本船其他 CIWS engaged 的导弹
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

## 通用版：在给定挂点半径内找最近的敌方飞机
## 供 CIWS 近距反飞机 / NAVAL_AA 共用
static func _find_aircraft_in_range(nu: NavalUnit, mount: WeaponMount,
		max_range_px: float, max_altitude: float) -> CombatUnit:
	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	var best: CombatUnit = null
	var best_d := max_range_px
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed or not nu.is_hostile_to(u):
			continue
		if not u is Aircraft:
			continue
		if u.altitude >= max_altitude:
			continue
		var d := mount_pos.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

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
		if u.is_destroyed or not nu.is_hostile_to(u):
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
#  NAVAL_AA — 舰载对空机炮
# ==================================================
## 与陆基 AAGunUnit 同构但更强：射程更长、伤害偏高（舰载平台稳定 + 火控好）
## 行为：找最近空中敌机 → 前置量 → 按 GunParams.fire_rate 连发
## 参数来自 mount.params.weapon_params 的 GunParams（max_range / fire_rate /
## muzzle_velocity / bullet_damage / spread_angle）

## 高度门禁：默认放开（任何高度都能打），仅作为防御未来需要的预留参数
## 早先设 8000 m 导致玩家飞 HIGH（>7500 m）时 AA 直接无视玩家 → "射了一会儿就不射了"
const NAVAL_AA_MAX_ALTITUDE: float = 20000.0

static func _update_naval_aa(nu: NavalUnit, mount: WeaponMount, _delta: float) -> void:
	if nu.bullet_manager == null:
		return
	if mount.fire_cooldown > 0.0:
		return
	if mount.params == null or mount.params.weapon_params == null:
		return
	var gun := mount.params.weapon_params as GunParams
	if gun == null:
		return

	var range_px: float = gun.max_range * PIXELS_PER_METER
	var ac := _find_aircraft_in_range(nu, mount, range_px, NAVAL_AA_MAX_ALTITUDE)
	if ac == null:
		return

	var mount_pos := mount.world_position(nu.global_position, nu.heading)
	# 前置量：按子弹飞行时间预测目标位置
	var bullet_speed_px: float = gun.muzzle_velocity * PIXELS_PER_METER
	var dist_px: float = mount_pos.distance_to(ac.global_position)
	var time_to_target: float = dist_px / maxf(bullet_speed_px, 1.0)
	var tgt_vel := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * PIXELS_PER_METER
	var lead_pos: Vector2 = ac.global_position + tgt_vel * time_to_target

	var base_dir := atan2((lead_pos - mount_pos).x, -(lead_pos - mount_pos).y)
	var spread_rad := deg_to_rad(gun.spread_angle)
	var dir := base_dir + randf_range(-spread_rad, spread_rad)

	nu.bullet_manager.spawn_bullet(mount_pos, dir, gun.muzzle_velocity, nu, gun.bullet_damage, false, false)
	# fire_rate 单位：发/分钟 → 冷却 = 60 / fire_rate
	mount.fire_cooldown = 60.0 / maxf(gun.fire_rate, 1.0)

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
		if u.is_destroyed or not nu.is_hostile_to(u):
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
	nu.notify_missile_fired_at(target)
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
		if u.is_destroyed or not nu.is_hostile_to(u):
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
		if u.is_destroyed or not nu.is_hostile_to(u):
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
	nu.notify_missile_fired_at(target)

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
