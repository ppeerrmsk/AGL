class_name AircraftFormation
extends RefCounted

## 编队托管子系统（静态工具类）
## 从 aircraft.gd 提取的 LOD 1 编队托管三段式逻辑。
##
## 状态住在 Aircraft（formation_mode / _formation_leader / _dbg_* / target_position 等）+
## AIController（_formation_blend / _formation_jitter_phase 单边权威，2026-05-04 重构后取消镜像）。
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
##   ③④ _update_bank_via_pd  — 全局临界阻尼 PD 控制器（heading+bank 一体，与战斗/巡航同源）
##   ⑤ _update_speed         — fwd_offset 驱动的速度调档
##   ⑥ _log_formation_debug  — FORM_DBG 事件（稳态 1Hz / rejoin 10Hz）
##   ⑦ _update_altitude      — lerp 向长机收敛
##   ⑧ _update_position      — apply_movement + 微漂移
##   ⑨ _periodic_and_visuals — every3 节流更新 + rotation 同步 + queue_redraw
##
## （旧编队私有 _update_heading/_update_bank/leader-bank 混合/翻转守卫已随 2026-06-07
##   PD 重写退役，死代码于 2026-07-03 删除——见 git 历史。）
##
## ══════════════════════════════════════════════════════════════════════════
## 三段式行为（按距阵型槽位的距离分支）
## ══════════════════════════════════════════════════════════════════════════
##   >REJOIN_DIST (400px)  → FAR：纯追击归队（直扑槽位 + 1.4× 加速；越界/脱离/散队回归用）
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
##            （该机制已随 2026-06-07 PD 重写整体退役，问题由 PD 从根上消除）
##
## 9. 击毙敌机后 rejoin 过程中机身剧烈抖动（2026-04-24）
##    - 日志证据：combat_log_20260424_160912 Fractal @ 33.9s DISENGAGE 后
##        [34.1] slot_d=786 b=0.08 hdg=4→44 Δ=+41.2° dbank=+63°
##        [73.9] slot_d=620 b=0.09 hdg=-118→0 Δ=+120.6° dbank=+62°
##    - 根因：rejoin 时 wingman 离阵型远，MID 分支 bias_angle 经常贴到 ±60° 硬钳。
##            长机转向让 slot_local.x 翻符号时 bias 从 +60° 跳到 -60°
##            （target_heading 瞬移 120°）→ desired_bank 翻正负 → bank bang-bang
##    - 修复：bank 翻转抗振守卫（已随 2026-06-07 PD 重写退役，PD 的 D 项阻尼从根上消除 bang-bang）
##
## 10. 击毙敌机后进入编队瞬间机身"扭曲/拧过去"（2026-04-24 combat_log_163239）
##    - 根因：`_formation_blend` (b) 原本是 rejoin 渐变因子，但只用在高度和速度上。
##            bank/heading rate-limit 始终全速 → combat 残留 -53° 直拉到 formation 的 +29°
##    - 修复：rejoin 期间按 b 缩放 bank/heading 速率（35%→100%），见 _build_context 中
##            的 rejoin_rate_scale
## ══════════════════════════════════════════════════════════════════════════

# ── 分支距离阈值 ──
const CLOSE_DIST := 50.0                ## 以内纯航向同步
const REJOIN_DIST := 400.0              ## 以外纯追击归队（800→400，2026-05-31：MID 温和收敛太消极，提早进 FAR 直扑槽位 1.4× 加速）
const LEAD_BIAS_DIST := 250.0           ## MID 横向偏置的虚拟前视距离（越大→偏置越温和）
const MAX_BIAS := PI / 3.0              ## MID 横向偏置最大角度（60° 硬钳）

# ── 稳态亚像素吸附（_update_position；动态归位交给物理 bank，这里只清残差）──
const FORM_SETTLE_DIST := 25.0          ## 仅 <此距离才做微吸附（原 CLOSE_DIST=50，收紧一半）
const FORM_SETTLE_STRENGTH := 0.15      ## 吸附强度系数（原 0.4 → 0.15，肉眼不可见、非强扭）
const FORM_BIAS_DEADZONE := 35.0        ## MID 横向偏置死区(px)：贴近槽位中线不偏置，防 slot_local.x 过中线翻符号导致机身颤抖
const FORM_TH_EMA := 0.08               ## 编队 target_heading EMA：~0.15s 时间常数，滤高频抖(±50°方波→±3°)，真实转弯仅轻微滞后

# ── 运动控制 ──
const FORMATION_MAX_TURN_RATE := 1.5    ## rad/s，编队归队角速度硬上限（≈86°/s；现仅 rejoin 无头测试作 ω 上限参考）

# ── Rejoin 平滑（bug #10）──
const REJOIN_RATE_FLOOR := 0.35         ## b=0 时速率保留 35%（再低会看起来呆滞）

# ── 分支枚举（调试字符串仅供 FORM_DBG 日志读）──
enum Branch { FAR = 0, MID = 1, CLOSE = 2 }
const BRANCH_NAMES := ["FAR", "MID", "CLOSE"]
const FORM_BRANCH_HYST := 45.0          ## 分支切换迟滞带宽 px（防边界逐帧翻转导致机头颤抖）


## 带迟滞的分支选择：在阈值 ±FORM_BRANCH_HYST 内维持上一帧分支，越过迟滞带才切换。
## 防 slot_d 在 REJOIN_DIST/CLOSE_DIST 附近抖动时 target_heading 在两套公式间逐帧横跳。
static func _select_branch(slot_dist: float, prev: int) -> int:
	# 维持上一帧分支（若仍在其迟滞带内）
	match prev:
		Branch.FAR:
			if slot_dist > REJOIN_DIST - FORM_BRANCH_HYST:
				return Branch.FAR
		Branch.MID:
			if slot_dist <= REJOIN_DIST + FORM_BRANCH_HYST and slot_dist > CLOSE_DIST - FORM_BRANCH_HYST:
				return Branch.MID
		Branch.CLOSE:
			if slot_dist <= CLOSE_DIST + FORM_BRANCH_HYST:
				return Branch.CLOSE
	# 无前值或已越出迟滞带 → 按硬阈值
	if slot_dist > REJOIN_DIST:
		return Branch.FAR
	elif slot_dist > CLOSE_DIST:
		return Branch.MID
	return Branch.CLOSE


## LOD 1 编队托管主入口。
## 调用方已在 _physics_process 判定 `formation_mode and _formation_leader`。
## 9 阶段流水线：context → heading → bank → speed → log → altitude → position → periodic.
##
## 2026-05-04 性能优化：speed / altitude 降到 20Hz（每 3 帧更新一次，delta×3 抵消频率）。
## bank / heading / position 保持 60Hz —— 视觉敏感，抖动一帧就能看出。speed/altitude 是
## 慢量（飞机加减速秒级），20Hz 决策完全够。各飞机 _lod_frame 错相位天然分散负载峰值。
static func update_follow(ac: Aircraft, delta: float) -> void:
	var ctx := _build_context(ac)
	var target_heading: float = _resolve_target_heading(ac, ctx)
	# 全分支（FAR/MID/CLOSE）统一走全局临界阻尼 PD 控制器（与战斗/巡航同源）。
	# 编队自创的 lerp-heading + turn-rate-bank 在槽位方位角 / bias 翻号时欠阻尼 → 僚机大坡反转颤抖。
	# 只修 FAR 会把抖动挪到 MID（实测 Depth slot_d=182 时 bank -85↔+60 猛翻）。一次接全分支根治：
	# _resolve_target_heading 已按分支算好 target_heading（FAR=指向槽位，MID/CLOSE=长机航向+横向 bias），
	# PD 用 kp·误差 − kd·转速 + 协调转弯反推坡度，参考怎么跳都不来回猛翻。协调转弯 bank 天然随转向
	# 产生 → 编队转弯时僚机自然同步压坡（不再需要旧的 leader-bank 镜像）。
	_update_bank_via_pd(ac, ctx, target_heading, delta)
	if ac._lod_frame % 3 == 0:
		_update_speed(ac, ctx, delta * 3.0)
		_update_altitude(ac, ctx, delta * 3.0)
	_log_formation_debug(ac, ctx, delta)
	_update_position(ac, ctx, delta)
	_periodic_and_visuals(ac, ctx, delta)


# ══════════════════════════════════════════════════════════════════════════
# ① Context: 采集所有几何量，供其他阶段读取
# ══════════════════════════════════════════════════════════════════════════

## 构建 Context Dictionary。所有下游阶段的输入都从这里拿。
## 注意：slot_local 用"长机本地坐标系"而不是"飞机→槽位世界方位角"（见 bug #1）。
static func _build_context(ac: Aircraft) -> Dictionary:
	# 几何长机以权威 squad.leader 为准（与旧 get_wingman_target 一致）。
	# _formation_leader 是缓存副本，控制切换 / 长机变更后可能与 squad.leader 走样
	# （2026-06-07 队友追静止旧长机/slot_d=0 回归的真因）；它仅作"是否在编队"门闸。
	var _fl_raw: Aircraft = ac._formation_leader
	var ldr: Aircraft = _fl_raw
	if ac._ai_ref and ac._ai_ref.squad and is_instance_valid(ac._ai_ref.squad.leader):
		ldr = ac._ai_ref.squad.leader
	# 2026-05-04 重构：blend / jitter_phase 单边住 AIController，从 _ai_ref 读
	# （之前在 Aircraft 上镜像了一份，每帧手动同步 → 已删）
	var b: float = ac._ai_ref._formation_blend if ac._ai_ref else 1.0  # 0=自主飞行过渡, 1=正常编队

	# ── 槽位实时跟随（强相关，消除"慢一拍"）──
	# 槽位 = 长机当前位置 + 已采纳偏移旋进长机当前机体系，每物理帧（60Hz）重算。
	# 旧实现读冻结的 ac.target_position（只在 AI 分频 tick 更新），长机机动时槽位滞后
	# 一个 AI-tick（50~100ms）→ 编队"慢一拍"。改为每帧实时算后，长机一动全队同帧跟动。
	# committed 偏移是"慢变部分"（用哪个阵型/第几槽），由 squad_coordination 在 AI tick 更新。
	var slot_pos: Vector2 = ac.target_position
	var _ai := ac._ai_ref
	if _ai != null:
		# 优先用 committed 偏移（含换阵型 react 平滑）；committed 暂为 INF（竞态/首帧/某些 spawn 路径）
		# 时直接从 squad 实时算 offset，**绝不回退到陈旧 target_position**（否则队友会追长机旧位置）。
		var off: Vector2 = _ai._formation_offset_committed
		if off == Vector2.INF and _ai.squad != null and is_instance_valid(_ai.squad.leader):
			off = _ai.squad.get_formation_offset(_ai.squad_index)
		if off != Vector2.INF and ldr != null:
			slot_pos = ldr.global_position + off.rotated(ldr.heading)
			ac.target_position = slot_pos  # 回写：micro-drift / 调试 / LOD 切换 / 其它读 target_position 处一致
	var slot_dist := 0.0
	var slot_local := Vector2.ZERO
	if slot_pos != Vector2.INF:
		slot_dist = ac.global_position.distance_to(slot_pos)
		# slot_local.x > 0 → 槽位在僚机右侧；y > 0 → 槽位在僚机后方
		# 用 leader frame 避免长机转弯时方位角摆动（bug #1）
		slot_local = (slot_pos - ac.global_position).rotated(-ldr.heading)

	# 分支解析（带迟滞：防 slot_d 在 REJOIN_DIST/CLOSE_DIST 阈值附近逐帧翻转 →
	# target_heading 在"纯追击(FAR)"与"长机航向+偏置(MID)"两套公式间横跳 → 机头颤抖。
	# 在边界 ±FORM_BRANCH_HYST 内维持上一帧分支，只有越过迟滞带才真正切换。）
	var prev_branch: int = ac._ai_ref._formation_branch if ac._ai_ref else -1
	var branch: int = _select_branch(slot_dist, prev_branch)
	if ac._ai_ref:
		ac._ai_ref._formation_branch = branch

	# 个体微扰动相位（基于 _lod_frame 推进，各飞机 phase 错开）
	var t := float(ac._lod_frame) * 0.02
	var phase: float = ac._ai_ref._formation_jitter_phase if ac._ai_ref else 0.0

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
## 把 max_bank_ratio 写回 ctx（原供已删除的旧 _update_bank 读取；PD 路径的 bank 上限
## 由 _formation_full_bank + compute_target_bank 决定，此值现仅留作调试参考）。
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
			# bias_angle：横向偏置。slot_local.x 过中线翻符号 → target_heading 抖 → 机身颤抖。
			# 加死区(2026-06-07)：|x|<FORM_BIAS_DEADZONE 内不偏置(贴近槽位中线时按长机航向走，
			# 残余横向交给微吸附)，超出死区按 |x|-死区 连续起偏 → 无符号跳变。
			var x_eff: float = slot_local.x - signf(slot_local.x) * minf(absf(slot_local.x), FORM_BIAS_DEADZONE)
			var bias_angle := clampf(atan2(x_eff, LEAD_BIAS_DIST), -MAX_BIAS, MAX_BIAS)
			target_heading = ldr.heading + jitter_heading + bias_angle
			max_bank_ratio = 0.75
			ac._dbg_slot_heading = bias_angle  # 复用字段：横向偏置角
			ac._dbg_blend_ratio = bias_angle / MAX_BIAS
			ac._dbg_blended_heading = target_heading
		Branch.CLOSE:
			# 近距离：直接跟长机航向
			target_heading = ldr.heading + jitter_heading
			max_bank_ratio = 0.6

	# 源头平滑 target_heading（角度感知 EMA）：滤掉高频抖动（slot 方位角过中线 / 继承长机航向抖 /
	# 高速 FAR 逼近移动槽位时方位角快摆）。同时根治 heading 抖 + bank 抖（bank 由 heading_step 推出）。
	# 全分支适用(含 FAR)：稳定槽位时 EMA 收敛=不影响果断切弯；槽位方位摆时才平滑（修高速归队 heading 颤抖）。
	if ac._ai_ref:
		var e: float = ac._ai_ref._form_th_ema
		if e == INF:
			e = target_heading
		else:
			e = wrapf(e + Aircraft._angle_diff(target_heading, e) * FORM_TH_EMA, -PI, PI)  # wrap 防累积角漂移
		ac._ai_ref._form_th_ema = e
		target_heading = e

	ac._dbg_target_heading = target_heading
	ctx["max_bank_ratio"] = max_bank_ratio
	return target_heading


# ══════════════════════════════════════════════════════════════════════════
# ③④ 航向 + Bank：全局临界阻尼 PD 控制器（2026-06-07 重写，取代编队私有公式）
# ══════════════════════════════════════════════════════════════════════════

## 编队转弯统一走全局 PD 转弯控制器（与 AircraftPhysics.update_bank/update_heading 同源）。
## 全分支适用：target_heading 已由 _resolve_target_heading 按分支算好(FAR=指向槽位，
## MID/CLOSE=长机航向+横向 bias，均经角度 EMA 平滑) → 直接喂 PD：kp·误差 − kd·转速 +
## 协调转弯反推坡度，临界阻尼，参考(槽位方位/bias)怎么跳都不来回猛翻。
## 与"归位/编队靠真实 bank/盘旋自然到位、禁止伪造转速"的偏好一致。
static func _update_bank_via_pd(ac: Aircraft, ctx: Dictionary, target_heading: float, delta: float) -> void:
	var hdiff := Aircraft._angle_diff(target_heading, ac.heading)
	ac._cached_target_heading = target_heading
	ac._proximity_damping = 1.0
	ctx["hdiff"] = hdiff
	ctx["heading_step"] = 0.0  # 供 _log_formation_debug / 下游读
	# FAR 归队放开 bank 到满 G（像玩家硬转回阵）；MID/CLOSE 站位仍走柔和 0.9 cap 防颤抖。
	# 旧版编队 bank 恒被 compute_target_bank 的 formation 分支钳到 0.9×max_bank → ~4.4G，
	# 远不及玩家的满 G（~12.5G），归队转弯半径大、慢（用户反馈"僚机像只能用 4G"）。
	ac._formation_full_bank = int(ctx["branch"]) == Branch.FAR
	# PD 控制器（随后真实 ω=g·tan(bank)/v 积分航向）
	AircraftPhysics.update_bank(ac, delta)
	AircraftPhysics.update_heading(ac, delta)
	ac._dbg_hdiff = hdiff
	ac._dbg_desired_bank = ac.bank_angle


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

	# ── 归队追赶速度（2026-06-13 提速重写，根治"飞回长机身边龟速、不踩油门"）──
	# 旧版三个龟速因：①唯一的 1.4× 冲刺档只在 slot_d>400px 有效，一进 400px 倍率即塌到
	# 1.05~1.15×（仅比长机快 5~15%）→ 最后 350px 蹭进去；②追赶倍率以纵向 fwd_offset 为判据，
	# 横向落后(fwd_offset≈0)直接落 1.0× 纯跟速、零追赶；③速度全相对长机，长机巡航不快时归队全程都慢。
	# 实测基线：从 600/400px 起 30s 都归不了队（见 test_formation_rejoin / changelog）。
	#
	# 新版：以【总距离 slot_dist】(含横向)连续插值 长机速度 → 本机满速。距离越远越接近满速冲刺
	# （= 踩满油门/加力的绝对速度，不再被长机巡航速度封顶），贴近槽位时连续收敛到 1.05× 平滑停靠，
	# 无 400px 悬崖。fwd_offset<-50 的"超前减速"分支保留（防冲过槽位后来回振荡）。
	var chase_target: float
	var chase_rate: float
	if fwd_offset < -50.0:
		# 已超前于槽位 → 减速让槽位追上（bug #7，保留：防超调振荡）
		chase_target = ldr.speed * 0.92 + jitter_speed
		chase_rate = 3.0
	elif slot_dist > CLOSE_DIST:
		# 落后/远离槽位：按总距离连续插值 长机速度(1.05×, 贴近) → 满速(满油门, 远距)
		var t: float = clampf((slot_dist - CLOSE_DIST) / (REJOIN_DIST - CLOSE_DIST), 0.0, 1.0)
		var dist_target: float = lerpf(ldr.speed * 1.05, max_ms, t)
		# ── 航向对齐门（2026-06-14 修回归：max 速度归队转不回来、原地绕大圈越飞越远）──
		# 转弯率 ω=g·tan(bank)/v 与速度成反比：满速(555m/s)+77°bank ≈ 4°/s，槽位在侧/后时
		# 永远转不到 → slot_d 反而越飞越远（日志 Yard 飞到 12km）。机头未对准槽位方向时压到
		# 角点速度（最佳转弯率）先把机头转过去，对准后再松开到全速冲刺。"先转向再加速"。
		var corner_ms: float = AircraftPhysics.effective_corner_speed_kmh(ac) / 3.6
		var align: float = 1.0
		var slot_pos: Vector2 = ctx["slot_pos"]
		if slot_pos != Vector2.INF:
			var to_slot: Vector2 = slot_pos - ac.global_position
			if to_slot.length() > 1.0:
				var slot_hdg: float = atan2(to_slot.x, -to_slot.y)
				var head_err: float = absf(Aircraft._angle_diff(slot_hdg, ac.heading))
				align = clampf(1.0 - head_err / (PI * 0.5), 0.0, 1.0)  # 0°→1(全速) / ≥90°→0(角点)
		chase_target = lerpf(corner_ms, dist_target, align) + jitter_speed
		chase_rate = 4.0
	else:
		# CLOSE（<50px）：匹配长机，稳定停靠
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

## 正常位移走 AircraftPhysics.apply_movement（与非编队路径一致）。
## 稳态亚像素吸附：仅"几乎到位 + 稳态巡航"时做肉眼不可见的微吸附，消除残留卡位。
## ⚠ 动态归位（拉回阵线）全部交给真实 bank/盘旋（_resolve_target_heading + _update_bank），
##    本函数不再承担动态归位——避免"非物理强扭轨迹"，保持俯视下的优雅跟随感。
static func _update_position(ac: Aircraft, ctx: Dictionary, delta: float) -> void:
	AircraftPhysics.apply_movement(ac, delta)

	# 稳态微吸附：仅 slot_dist < SETTLE_DIST(25px) 且 b>0.9 稳态时，做亚像素级残差对齐
	var slot_pos: Vector2 = ctx["slot_pos"]
	var slot_dist: float = ctx["slot_dist"]
	var b: float = ctx["b"]
	if slot_pos == Vector2.INF or slot_dist <= 3.0 or slot_dist >= FORM_SETTLE_DIST or b <= 0.9:
		return
	var correction_dir := (slot_pos - ac.global_position).normalized()
	var strength := clampf(slot_dist / FORM_SETTLE_DIST, 0.1, 1.0) * b * FORM_SETTLE_STRENGTH
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
