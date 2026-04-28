class_name AircraftFormation
extends RefCounted

## 编队托管子系统（静态工具类）
## 从 aircraft.gd 提取的 LOD 1 编队托管三段式逻辑。
##
## 状态仍住在 Aircraft（formation_mode / _formation_leader / _formation_blend /
## _formation_jitter_phase / _dbg_* / target_position / target_speed_kmh 等）。
## 本模块不持有状态，只在 ac 上读写 + 调 AircraftPhysics 静态方法。
##
## 调用约定（来自 aircraft.gd _physics_process LOD 1 分支）：
##   if formation_mode and _formation_leader:
##       AircraftFormation.update_follow(self, delta)
##       return
##
## ══════════════════════════════════════════════════════════════════════════
## 架构（2026-04-24 重构）
## ══════════════════════════════════════════════════════════════════════════
## update_follow 拆成 9 个阶段，每个阶段是一个独立函数，通过 Context Dictionary
## 共享中间量。修 bug 时只改一个阶段，不会波及其他。
##
##   ① _build_context        — 采集所有几何量（slot_dist / slot_local / b / jitter /
##                              branch / rejoin_rate_scale / every3 等）
##   ② _resolve_target_heading — 按 branch 算 target_heading + max_bank_ratio
##   ③ _update_heading       — rate-limited lerp 到 target_heading
##   ④ _update_bank          — desired_bank 公式 + leader-bank 混合 + 翻转守卫 + rate-limit
##   ⑤ _update_speed         — fwd_offset 驱动的速度调档
##   ⑥ _log_formation_debug  — FORM_DBG 事件（稳态 1Hz / rejoin 10Hz）
##   ⑦ _update_altitude      — lerp 向长机收敛
##   ⑧ _update_position      — apply_movement + 微漂移
##   ⑨ _periodic_and_visuals — every3 节流更新 + rotation 同步 + queue_redraw
##
## 辅助纯函数（无副作用）：
##   - _compute_leader_bank_blend(branch, slot_dist)
##   - _should_suppress_bank_flip(bank, desired, hdiff)
##
## ══════════════════════════════════════════════════════════════════════════
## 三段式行为（按距阵型槽位的距离分支）
## ══════════════════════════════════════════════════════════════════════════
##   >REJOIN_DIST (800px)  → FAR：纯追击归队（仅 b<0.05 脱离重融合用）
##   CLOSE~REJOIN          → MID：长机航向 + 横向偏置（leader-local frame）
##   <CLOSE_DIST (50px)    → CLOSE：航向同步长机 + 微量漂移修正
##
## ══════════════════════════════════════════════════════════════════════════
## 常见 bug 回溯地图（踩过的坑）
## ══════════════════════════════════════════════════════════════════════════
## 1. 机头乱扭（F11 调试看 MID 分支方位角剧烈摆动）
##    - 原因：早期用"飞机→槽位"世界方位角，长机转弯时 slot 绕长机切向移动
##    - 修复：改用长机本地坐标系 slot_local = (target_pos - pos).rotated(-ldr.heading)
##
## 2. Jinx 规避 360°/s 瞬间扭转
##    - 原因：LOD 1 + formation_mode 让规避也走这里的 lerp_angle，绕过 G 限/bank 速率
##    - 修复：AIController._enter_evade 强制退出编队托管（formation_mode=false + lod=0）
##    - 见 scripts/ai/missile_evasion.gd:81-87 注释
##
## 3. 僚机晋升为新长机后 Mach 8+ 暴走
##    - 原因：僚机带 1.15× 超速目标，晋升链里不断累加
##    - 修复：chase_target 必须 clamp 到 _max_speed_at_altitude（_update_speed 中）
##
## 4. 原长机阵亡后僚机"追自己尾巴原地自转"
##    - 原因：新长机的 squad_index 没同步到 0，仍在计算相对旧长机的槽位
##    - 修复：Squad._sync_leader_squad_index（非本文件，但会影响这里的 slot_dist/slot_local）
##
## 5. "一进编队就瞬间正 bank 归零"
##    - 原因：旧版 lerp(bank, 0, 4*delta) 几帧拉到 0，超结构 G 极限
##    - 修复：bank 由 hdiff 自然推出 + 严格 ≤ params.roll_rate 的 rate-limit（_update_bank）
##
## 6. LOD 切换回 0 时飞机慢吞吞减速追老 target_speed_kmh
##    - 原因：编队分支没同步 target_speed_kmh，切回 LOD 0 时 _update_speed 读到过期值
##    - 修复：每帧同步 target_speed_kmh = speed * 3.6（_update_speed）
##
## 7. 僚机超前于槽位但不会减速
##    - 原因：旧版速度调档只有加速支，fwd_offset < 0 无分支
##    - 修复：加 fwd_offset < -50 的减速分支 chase_target = ldr.speed * 0.92（_update_speed）
##
## 8. 长机硬转时僚机 bank 高频抖动（2026-04-24）
##    - 症状：长机拉 83° bank 时，僚机 slot_dist 在 50px 边界来回跨越，bank 目标在
##            +55°（CLOSE 有 leader-bank 混合）↔ +10°（MID 无混合）之间跳变
##    - 日志证据：combat_log_20260424_160912.txt Charge @ 9.8s→10.8s
##    - 修复：MID 分支也做 leader-bank 混合，按 slot_dist 从 0.55 衰减到 0.30
##            见 _compute_leader_bank_blend
##
## 9. 击毙敌机后 rejoin 过程中机身剧烈抖动（2026-04-24）
##    - 日志证据：combat_log_20260424_160912 Fractal @ 33.9s DISENGAGE 后
##        [34.1] slot_d=786 b=0.08 hdg=4→44 Δ=+41.2° dbank=+63°
##        [73.9] slot_d=620 b=0.09 hdg=-118→0 Δ=+120.6° dbank=+62°
##    - 根因：rejoin 时 wingman 离阵型远，MID 分支 bias_angle 经常贴到 ±60° 硬钳。
##            长机转向让 slot_local.x 翻符号时 bias 从 +60° 跳到 -60°
##            （target_heading 瞬移 120°）→ desired_bank 翻正负 → bank bang-bang
##    - 修复：bank 翻转抗振守卫，见 _should_suppress_bank_flip
##
## 10. 击毙敌机后进入编队瞬间机身"扭曲/拧过去"（2026-04-24 combat_log_163239）
##    - 根因：`_formation_blend` (b) 原本是 rejoin 渐变因子，但只用在高度和速度上。
##            bank/heading rate-limit 始终全速 → combat 残留 -53° 直拉到 formation 的 +29°
##    - 修复：rejoin 期间按 b 缩放 bank/heading 速率（35%→100%），见 _build_context 中
##            的 rejoin_rate_scale
## ══════════════════════════════════════════════════════════════════════════

# ── 分支距离阈值 ──
const CLOSE_DIST := 50.0                ## 以内纯航向同步
const REJOIN_DIST := 800.0              ## 以外纯追击归队
const LEAD_BIAS_DIST := 250.0           ## MID 横向偏置的虚拟前视距离（越大→偏置越温和）
const MAX_BIAS := PI / 3.0              ## MID 横向偏置最大角度（60° 硬钳）

# ── 运动控制 ──
const FORMATION_MAX_TURN_RATE := 1.5    ## rad/s，编队归队角速度硬上限（≈86°/s）
const FORMATION_LERP_K := 5.0           ## hdiff lerp 增益

# ── Rejoin 平滑（bug #10）──
const REJOIN_RATE_FLOOR := 0.35         ## b=0 时速率保留 35%（再低会看起来呆滞）

# ── Bank 翻转守卫（bug #9）──
const FORM_BANK_ESTABLISHED_RAD := 0.5236  ## deg_to_rad(30) — 已建立 bank 阈值
const FORM_BANK_COMMIT_RAD := 0.2618       ## deg_to_rad(15) — 翻转提交所需 hdiff

# ── Leader-bank 混合系数（bug #8）──
const BANK_BLEND_CLOSE := 0.6           ## CLOSE 分支固定混合
const BANK_BLEND_MID_NEAR := 0.55       ## MID 贴近 CLOSE 时的混合
const BANK_BLEND_MID_FAR := 0.30        ## MID 贴近 REJOIN 时的混合

# ── 分支枚举（调试字符串仅供 FORM_DBG 日志读）──
enum Branch { FAR = 0, MID = 1, CLOSE = 2 }
const BRANCH_NAMES := ["FAR", "MID", "CLOSE"]


## LOD 1 编队托管主入口。
## 调用方已在 _physics_process 判定 `formation_mode and _formation_leader`。
## 9 阶段流水线：context → heading → bank → speed → log → altitude → position → periodic.
static func update_follow(ac: Aircraft, delta: float) -> void:
	var ctx := _build_context(ac)
	var target_heading: float = _resolve_target_heading(ac, ctx)
	_update_heading(ac, ctx, target_heading, delta)
	_update_bank(ac, ctx, target_heading, delta)
	_update_speed(ac, ctx, delta)
	_log_formation_debug(ac, ctx, delta)
	_update_altitude(ac, ctx, delta)
	_update_position(ac, ctx, delta)
	_periodic_and_visuals(ac, ctx, delta)


# ══════════════════════════════════════════════════════════════════════════
# ① Context: 采集所有几何量，供其他阶段读取
# ══════════════════════════════════════════════════════════════════════════

## 构建 Context Dictionary。所有下游阶段的输入都从这里拿。
## 注意：slot_local 用"长机本地坐标系"而不是"飞机→槽位世界方位角"（见 bug #1）。
static func _build_context(ac: Aircraft) -> Dictionary:
	var ldr: Aircraft = ac._formation_leader
	var b: float = ac._formation_blend  # 0=自主飞行过渡, 1=正常编队

	# 离槽位距离
	var slot_pos: Vector2 = ac.target_position
	var slot_dist := 0.0
	var slot_local := Vector2.ZERO
	if slot_pos != Vector2.INF:
		slot_dist = ac.global_position.distance_to(slot_pos)
		# slot_local.x > 0 → 槽位在僚机右侧；y > 0 → 槽位在僚机后方
		# 用 leader frame 避免长机转弯时方位角摆动（bug #1）
		slot_local = (slot_pos - ac.global_position).rotated(-ldr.heading)

	# 分支解析（单次判定，下游阶段直接用 branch 枚举）
	var branch: int
	if slot_dist > REJOIN_DIST:
		branch = Branch.FAR
	elif slot_dist > CLOSE_DIST:
		branch = Branch.MID
	else:
		branch = Branch.CLOSE

	# 个体微扰动相位（基于 _lod_frame 推进，各飞机 phase 错开）
	var t := float(ac._lod_frame) * 0.02
	var phase: float = ac._formation_jitter_phase

	# Rejoin 速率缩放（bug #10）：b<1 时 bank/heading 速率按 b 线性缩放，
	# 避免 combat 残留 bank 硬拉。稳态 b=1 时 scale=1.0，行为完全等同老代码。
	var rejoin_rate_scale: float = lerpf(REJOIN_RATE_FLOOR, 1.0, b)

	return {
		"ldr": ldr,
		"b": b,
		"slot_pos": slot_pos,
		"slot_dist": slot_dist,
		"slot_local": slot_local,
		"fwd_offset": -slot_local.y,  # >0 = slot in front of wingman in leader frame
		"branch": branch,
		"jitter_t": t,
		"jitter_phase": phase,
		"jitter_heading": sin(t + phase) * 0.008,
		"jitter_bank": sin(t * 0.7 + phase + 1.0) * 0.015,
		"rejoin_rate_scale": rejoin_rate_scale,
		"every3": ac._lod_frame % 3 == 0,
	}


# ══════════════════════════════════════════════════════════════════════════
# ② 目标航向：按分支计算，写 max_bank_ratio 回 ctx，更新调试字段
# ══════════════════════════════════════════════════════════════════════════

## 根据 branch 决定 target_heading 和 max_bank_ratio。
## 副作用：写 ac._dbg_* 调试字段（F12 快照不依赖 F11 开关）。
## 把 max_bank_ratio 写回 ctx 供 _update_bank 读取。
static func _resolve_target_heading(ac: Aircraft, ctx: Dictionary) -> float:
	var ldr: Aircraft = ctx["ldr"]
	var slot_pos: Vector2 = ctx["slot_pos"]
	var slot_dist: float = ctx["slot_dist"]
	var slot_local: Vector2 = ctx["slot_local"]
	var branch: int = ctx["branch"]
	var jitter_heading: float = ctx["jitter_heading"]

	# 调试字段统一默认值
	ac._dbg_slot_pos = slot_pos
	ac._dbg_slot_dist = slot_dist
	ac._dbg_blend_ratio = 0.0
	ac._dbg_blended_heading = 0.0
	ac._dbg_slot_heading = 0.0
	ac._dbg_branch = BRANCH_NAMES[branch]

	var target_heading: float = ac.heading  # 默认不变
	var max_bank_ratio := 0.75

	match branch:
		Branch.FAR:
			# 真正远距离：纯追击归队（目标航向 = 飞机朝槽位）
			if slot_pos != Vector2.INF and slot_dist > 10.0:
				var to_slot := (slot_pos - ac.global_position).normalized()
				target_heading = atan2(to_slot.x, -to_slot.y)
				max_bank_ratio = 0.7
				ac._dbg_slot_heading = target_heading
		Branch.MID:
			# 中距离：长机航向 + 横向偏置（leader-local frame）
			# bias_angle 贴 ±60° 硬钳 + slot_local.x 符号翻转是 bug #9 的起源
			var bias_angle := clampf(atan2(slot_local.x, LEAD_BIAS_DIST), -MAX_BIAS, MAX_BIAS)
			target_heading = ldr.heading + jitter_heading + bias_angle
			max_bank_ratio = 0.75
			ac._dbg_slot_heading = bias_angle  # 复用字段：横向偏置角
			ac._dbg_blend_ratio = bias_angle / MAX_BIAS
			ac._dbg_blended_heading = target_heading
		Branch.CLOSE:
			# 近距离：直接跟长机航向
			target_heading = ldr.heading + jitter_heading
			max_bank_ratio = 0.6

	ac._dbg_target_heading = target_heading
	ctx["max_bank_ratio"] = max_bank_ratio
	return target_heading


# ══════════════════════════════════════════════════════════════════════════
# ③ 航向更新：rate-limited lerp，受 rejoin_rate_scale 缩放
# ══════════════════════════════════════════════════════════════════════════

## 把 heading 向 target 推进一步。
## 原则（2026-04-10）：
##   - 纯物理公式 (g·tan(bank)/TAS) 在编队中过慢：F-14 在 84° bank 也只有 ~21°/s
##   - 纯 lerp 没有上限，combat 刚结束从 ±80° bank 一瞬间归零，非物理突兀
## 折中：lerp 追目标，但角速度被 FORMATION_MAX_TURN_RATE 硬夹（~86°/s 稳态）。
## rejoin 期间（bug #10）再按 b 缩放降速。
static func _update_heading(ac: Aircraft, ctx: Dictionary, target_heading: float, delta: float) -> void:
	var hdiff := Aircraft._angle_diff(target_heading, ac.heading)
	var eff_turn_rate: float = FORMATION_MAX_TURN_RATE * ctx["rejoin_rate_scale"]
	var desired_step := hdiff * FORMATION_LERP_K * delta
	var max_step := eff_turn_rate * delta
	if absf(desired_step) > max_step:
		desired_step = signf(desired_step) * max_step
	ac.heading = wrapf(ac.heading + desired_step, -PI, PI)
	# 缓存 hdiff 供 _update_bank 写调试字段用（与 hdiff_after 区分）
	ctx["hdiff"] = hdiff


# ══════════════════════════════════════════════════════════════════════════
# ④ Bank 更新：desired 公式 + leader 混合 + 翻转守卫 + rate-limit
# ══════════════════════════════════════════════════════════════════════════

## 按 hdiff 推 desired_bank，CLOSE/MID 分支混合长机 bank，触发翻转守卫后 rate-limit 落位。
static func _update_bank(ac: Aircraft, ctx: Dictionary, target_heading: float, delta: float) -> void:
	var ldr: Aircraft = ctx["ldr"]
	var branch: int = ctx["branch"]
	var max_bank_val := AircraftPhysics.max_bank_angle(ac)
	var max_bank_ratio: float = ctx["max_bank_ratio"]

	# 用更新后的 heading 重算 hdiff（和 target 之间的残留），推 desired_bank
	var hdiff_after := Aircraft._angle_diff(target_heading, ac.heading)
	var desired_bank := signf(hdiff_after) * max_bank_val \
			* clampf(absf(hdiff_after) * 2.5, 0.0, max_bank_ratio)

	# Leader-bank 混合（bug #8：CLOSE/MID 边界连续过渡）
	if branch == Branch.CLOSE or branch == Branch.MID:
		var ldr_target_bnk: float = ldr.bank_angle + ctx["jitter_bank"]
		var blend: float = _compute_leader_bank_blend(branch, ctx["slot_dist"])
		desired_bank = lerpf(desired_bank, ldr_target_bnk, blend)

	# 记录"未经翻转守卫处理"的 desired（诊断用，便于观察守卫是否触发）
	ac._dbg_hdiff = ctx["hdiff"]
	ac._dbg_desired_bank = desired_bank

	# Bank 翻转抗振守卫（bug #9）
	if _should_suppress_bank_flip(ac.bank_angle, desired_bank, hdiff_after):
		desired_bank = 0.0

	# Rate-limit（bug #10：rejoin 期间按 b 缩放）
	var roll_rate_limit: float = ac.params.roll_rate if ac.params else 3.0
	var eff_roll_rate: float = roll_rate_limit * float(ctx["rejoin_rate_scale"])
	var bank_step := clampf(desired_bank - ac.bank_angle, -eff_roll_rate * delta, eff_roll_rate * delta)
	ac.bank_angle += bank_step


## Leader-bank 混合系数（纯函数）。
## CLOSE 固定 0.6；MID 按 slot_dist 从 0.55（贴近 CLOSE）衰减到 0.30（贴近 REJOIN）。
## 目的：消除 CLOSE/MID 边界的 bank 目标跳变（bug #8）。
static func _compute_leader_bank_blend(branch: int, slot_dist: float) -> float:
	if branch == Branch.CLOSE:
		return BANK_BLEND_CLOSE
	if branch == Branch.MID:
		var dist_ratio := clampf((slot_dist - CLOSE_DIST) / (REJOIN_DIST - CLOSE_DIST), 0.0, 1.0)
		return lerpf(BANK_BLEND_MID_NEAR, BANK_BLEND_MID_FAR, dist_ratio)
	return 0.0


## Bank 翻转守卫判定（纯函数，见 bug #9）。
## 条件：|bank|>30° 且 desired 要反向，但 hdiff 还不够大（<15°）。
## 用途：rejoin 时 bias_angle 贴 ±60° 钳位翻符号导致 desired_bank bang-bang。
## 返回 true 时调用方应把 desired_bank 归零（先回中再考虑翻）。
static func _should_suppress_bank_flip(current_bank: float, desired_bank: float, hdiff_after: float) -> bool:
	if absf(current_bank) <= FORM_BANK_ESTABLISHED_RAD:
		return false
	if signf(desired_bank) == 0.0:
		return false
	if signf(desired_bank) == signf(current_bank):
		return false
	return absf(hdiff_after) < FORM_BANK_COMMIT_RAD


# ══════════════════════════════════════════════════════════════════════════
# ⑤ 速度：根据 leader-local 纵向偏移调档
# ══════════════════════════════════════════════════════════════════════════

## 按 fwd_offset 选档：前方→加速 / 后方→减速 / 对齐→匹配。
## 所有目标速度 clamp 到 max_speed_at_altitude，防止晋升链 Mach 8+ 暴走（bug #3）。
## 写 target_speed_kmh 保证 LOD 切换无缝（bug #6）。
static func _update_speed(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	var ldr: Aircraft = ctx["ldr"]
	var b: float = ctx["b"]
	var fwd_offset: float = ctx["fwd_offset"]
	var slot_dist: float = ctx["slot_dist"]

	var max_ms := AircraftPhysics.max_speed_at_altitude(ac) / 3.6
	var jitter_speed: float = sin(ctx["jitter_t"] * 0.5 + ctx["jitter_phase"] + 2.0) * ldr.speed * 0.005

	var chase_target: float
	var chase_rate: float
	if slot_dist > REJOIN_DIST:
		# 归队：大幅加速追上
		chase_target = ldr.speed * 1.4
		chase_rate = 4.0
	elif fwd_offset > 200.0:
		# 槽位远在前方
		chase_target = ldr.speed * 1.15 + jitter_speed
		chase_rate = 4.0
	elif fwd_offset > 50.0:
		# 槽位前方
		chase_target = ldr.speed * 1.05 + jitter_speed
		chase_rate = 3.0
	elif fwd_offset < -50.0:
		# 超前于槽位 → 减速（bug #7）
		chase_target = ldr.speed * 0.92 + jitter_speed
		chase_rate = 3.0
	else:
		# 纵向基本对齐：匹配长机
		chase_target = ldr.speed + jitter_speed
		chase_rate = 3.0 + b * 3.0

	chase_target = clampf(chase_target, 0.0, max_ms)
	ac.speed = lerpf(ac.speed, chase_target, chase_rate * delta)
	ac.target_speed_kmh = ac.speed * 3.6  # 同步避免 LOD 切换残留（bug #6）
	ac._dbg_chase_target_kmh = chase_target * 3.6


# ══════════════════════════════════════════════════════════════════════════
# ⑥ FORM_DBG 日志：稳态 1Hz / rejoin 10Hz
# ══════════════════════════════════════════════════════════════════════════

## 节流：稳态编队不污染日志，rejoin 期间（b<0.95）升到 10Hz 便于排查 60Hz 抖动包络。
## 位置：在速度后、altitude/movement 前——保持和老代码相同的采样时序。
static func _log_formation_debug(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	if not ac.formation_debug:
		return
	ac._dbg_log_timer -= delta
	if ac._dbg_log_timer > 0.0:
		return
	var b: float = ctx["b"]
	ac._dbg_log_timer = 0.1 if b < 0.95 else 1.0
	var ldr: Aircraft = ctx["ldr"]
	EventLogger.log_event("FORM_DBG", ac.callsign,
		"branch=%s slot_d=%.0f b=%.2f hdg=%d→%d Δ=%+.1f° dbank=%+.0f° bank=%+.0f° spd=%d/%d ldrG=%.1f" % [
			ac._dbg_branch,
			ac._dbg_slot_dist,
			b,
			int(rad_to_deg(ac.heading)),
			int(rad_to_deg(ac._dbg_target_heading)),
			rad_to_deg(ac._dbg_hdiff),
			rad_to_deg(ac._dbg_desired_bank),
			rad_to_deg(ac.bank_angle),
			int(ac.speed * 3.6),
			int(AircraftPhysics.max_speed_at_altitude(ac)),
			ldr.g_load if is_instance_valid(ldr) else 0.0,
		])


# ══════════════════════════════════════════════════════════════════════════
# ⑦ 高度：向长机收敛
# ══════════════════════════════════════════════════════════════════════════

## altitude lerp，b 越大衰减越快（稳态 b=1 时系数 4，rejoin b=0 时系数 2）。
static func _update_altitude(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	var ldr: Aircraft = ctx["ldr"]
	var b: float = ctx["b"]
	ac.altitude = lerpf(ac.altitude, ldr.altitude, (2.0 + b * 2.0) * delta)


# ══════════════════════════════════════════════════════════════════════════
# ⑧ 位移：apply_movement + 微漂移
# ══════════════════════════════════════════════════════════════════════════

## 正常位移走 AircraftPhysics.apply_movement（与非编队路径一致），然后 CLOSE 范围内
## 做一次细微的槽位对齐（避免"隔着 30px 卡位"的视觉 bug）。
static func _update_position(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	AircraftPhysics.apply_movement(ac, delta)

	# 微漂移：仅 CLOSE 范围内（3~50px）做细微槽位对齐
	var slot_pos: Vector2 = ctx["slot_pos"]
	var slot_dist: float = ctx["slot_dist"]
	var b: float = ctx["b"]
	if slot_pos == Vector2.INF or slot_dist <= 3.0 or slot_dist >= CLOSE_DIST or b <= 0.05:
		return
	var correction_dir := (slot_pos - ac.global_position).normalized()
	var strength := clampf(slot_dist / CLOSE_DIST, 0.1, 1.0) * b * 0.4
	var correction_speed := ac.speed * CombatUnit.PIXELS_PER_METER * 0.15 * strength
	var move_px := minf(correction_speed * delta, slot_dist)
	ac.global_position += correction_dir * move_px


# ══════════════════════════════════════════════════════════════════════════
# ⑨ 节流更新 + 视觉同步
# ══════════════════════════════════════════════════════════════════════════

## every3 帧做一次 fuel / g_load 更新（LOD 1 节流）；每帧同步 rotation 和重绘。
static func _periodic_and_visuals(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	if ctx["every3"]:
		AircraftPhysics.update_fuel(ac, delta)
		AircraftPhysics.update_g_load(ac)
	ac._update_visuals()
	if ac.selected or ac.is_hovered or ctx["every3"]:
		ac.queue_redraw()
