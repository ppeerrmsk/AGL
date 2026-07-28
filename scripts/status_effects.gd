class_name StatusEffects
extends RefCounted

## 异常状态 / Buff 系统：定时性的状态效果，叠加飞机原有属性
##
## 接入点（minimal hooks）：
##   Aircraft.status_effects: Dictionary[id → 剩余秒数]
##   Aircraft.status_*_active: bool — 派生标记，每帧由 update 重写
##   Aircraft.apply_status / remove_status / has_status — 外部入口
##
## 副作用应用方式：每帧调 update，一次性写完所有派生标记 + 连续作用：
##   - INVINCIBLE → invulnerable=true（带 owner 跟踪：自己置位 → 自己清位）
##   - STEALTH    → is_cloaked=true + _cloak_alpha=0.35（同上）
##   - FEAR       → pilot_personality.stress=1.0
##   - SLOW       → cap target_speed_kmh + is_afterburner=false
##   其余 (JAM/OVERLOAD/BLOODLUST) 在使用点查 status_*_active 标记。

# ── ID 常量 ──────────────────────────────────────────────
const FEAR := "fear"
const JAM := "jam"
const SLOW := "slow"
const INVINCIBLE := "invincible"
const STEALTH := "stealth"
const BLOODLUST := "bloodlust"
const OVERLOAD := "overload"

const ALL_IDS: Array[String] = [
	FEAR, JAM, SLOW,
	INVINCIBLE, STEALTH, BLOODLUST, OVERLOAD,
]

# ── 数值参数 ──────────────────────────────────────────────
const SLOW_SPEED_CAP_KMH := 350.0
const SLOW_ROLL_MULT := 0.6
const OVERLOAD_RELOAD_MULT := 0.4    ## 装填时间 ×0.4
const OVERLOAD_LOCK_MULT := 0.4      ## 锁定时间 ×0.4（=锁定速率 ×2.5）
const OVERLOAD_ACCEL_MULT := 1.6     ## 加/减速 ×1.6

const STEALTH_ALPHA := 0.35
const BLOODLUST_HEAL_PER_KILL := 20.0

# ── 显示元数据 ────────────────────────────────────────────
## 状态条尺寸（飞机正上方水平摆放，顺次往上堆）
const BAR_WIDTH := 56.0
const BAR_HEIGHT := 12.0
const BAR_GAP := 2.0
const BAR_OFFSET_Y := -38.0    ## 第一条距飞机中心的高度（往上）
const BAR_FONT_SIZE := 10

## 显示顺序：buff 在前，debuff 在后
const DISPLAY_ORDER: Array[String] = [
	INVINCIBLE, OVERLOAD, BLOODLUST, STEALTH,
	FEAR, JAM, SLOW,
]

static func is_buff(id: String) -> bool:
	return id == INVINCIBLE or id == STEALTH or id == BLOODLUST or id == OVERLOAD

static func icon_color(id: String) -> Color:
	match id:
		INVINCIBLE: return Color(1.0, 0.85, 0.20)   # 金
		STEALTH:    return Color(0.65, 0.85, 1.00)  # 浅蓝
		BLOODLUST:  return Color(1.00, 0.30, 0.30)  # 血红
		OVERLOAD:   return Color(1.00, 0.55, 0.10)  # 橙
		FEAR:       return Color(0.75, 0.30, 0.95)  # 紫
		JAM:        return Color(0.40, 1.00, 0.45)  # 干扰绿
		SLOW:       return Color(0.55, 0.80, 1.00)  # 冰蓝
	return Color.WHITE

## 状态栏文本里显示的英文短标签（5 字母内，配合 HDG/ALT/G 数据标签风格）
static func english_label(id: String) -> String:
	match id:
		INVINCIBLE: return "INVUL"
		STEALTH:    return "STLTH"
		BLOODLUST:  return "FRENZY"
		OVERLOAD:   return "OVRLD"
		FEAR:       return "FEAR"
		JAM:        return "JAM"
		SLOW:       return "SLOW"
	return id.to_upper()

## 进度条上显示的中文短标签（与 debug 面板共用）
static func short_label(id: String) -> String:
	match id:
		INVINCIBLE: return "无敌"
		STEALTH:    return "隐身"
		BLOODLUST:  return "嗜血"
		OVERLOAD:   return "超载"
		FEAR:       return "恐惧"
		JAM:        return "干扰"
		SLOW:       return "减速"
	return id

# ── 主循环 ───────────────────────────────────────────────
## 722 sig_x13·全频段压制（队级账本位，survivor_mode._refresh_squad_effective_stacks 同步）：
## 被锁定的敌单位身上的负面状态（FEAR/JAM/SLOW）倒计时流速 ×0.6
static var sig_x13_active: bool = false

## 通用入口：任何 CombatUnit 子类（地面单位 / 船 / 巨型 BOSS）都可以调。
## 只做两件事：① 倒计时 + 自动移除；② 写 status_jam_active（唯一对所有单位生效的标记）。
## 其它派生状态全是 Aircraft 专属（INVINCIBLE/STEALTH/BLOODLUST/OVERLOAD/SLOW/FEAR），
## 由 update_aircraft 在调完本函数后再算 + 应用副作用。
static func tick(unit: CombatUnit, delta: float) -> void:
	if not unit.status_effects.is_empty():
		var x13_suppress: bool = sig_x13_active \
			and unit.team == CombatUnit.TEAM_HOSTILE and unit.is_locked
		var to_remove: Array[String] = []
		for id in unit.status_effects.keys():
			var eff_delta: float = delta
			if x13_suppress and (id == FEAR or id == JAM or id == SLOW):
				eff_delta = delta * 0.6
			var remaining: float = float(unit.status_effects[id]) - eff_delta
			if remaining <= 0.0:
				to_remove.append(id)
			else:
				unit.status_effects[id] = remaining
		for id in to_remove:
			unit.status_effects.erase(id)
			unit.status_initial_durations.erase(id)
	unit.status_jam_active = unit.status_effects.has(JAM)


## Aircraft 专用：在 tick 之后跑，应用所有飞行单位独占的派生标记和连续副作用。
static func update(ac: Aircraft, delta: float) -> void:
	tick(ac, delta)

	# ── 重算派生标记（Aircraft 专属）──
	ac.status_invincible_active = ac.status_effects.has(INVINCIBLE)
	# STEALTH 派生 OR 三源：status_effects 限时来源 + evasion 常驻 + 导弹 cd / 装填常驻
	# 各来源独立 bool，避免相互覆盖（_in_evasion_stealth / _in_missile_cd_stealth 由 aircraft.gd 派生）
	ac.status_stealth_active = ac.status_effects.has(STEALTH) or ac._in_evasion_stealth or ac._in_missile_cd_stealth
	ac.status_bloodlust_active = ac.status_effects.has(BLOODLUST)
	# OVERLOAD 派生 OR 两源：status_effects 中的限时来源 + 云中常驻来源（_in_cloud_overload）
	# 两源独立避免出云误清（详见 aircraft._on_cloud_boundary 注释）
	ac.status_overload_active = ac.status_effects.has(OVERLOAD) or ac._in_cloud_overload
	ac.status_slow_active = ac.status_effects.has(SLOW)
	ac.status_fear_active = ac.status_effects.has(FEAR)

	# ── 连续副作用（owner-tracked，避免与其它系统打架）──
	# INVINCIBLE → invulnerable
	if ac.status_invincible_active:
		if not ac.invulnerable:
			ac.invulnerable = true
			ac._status_owns_invul = true
	elif ac._status_owns_invul:
		ac.invulnerable = false
		ac._status_owns_invul = false

	# STEALTH → is_cloaked + 半透明
	if ac.status_stealth_active:
		if not ac.is_cloaked:
			ac.is_cloaked = true
			ac._status_owns_cloak = true
		ac._cloak_alpha = STEALTH_ALPHA
	elif ac._status_owns_cloak:
		ac.is_cloaked = false
		ac._status_owns_cloak = false
		ac._cloak_alpha = 1.0

	# FEAR → 直接拉满 AI 的 stress（玩家无 AIController，对玩家无效果，纯视觉）
	## fear_immune 单位通过 [combat_unit.gd:apply_status] 入口直接拒绝 FEAR 状态，
	## 这里 status_fear_active 自然为 false，无需再检查
	if ac.status_fear_active:
		var ai := ac.get_node_or_null("AIController") as AIController
		if ai and ai.personality:
			ai.personality.stress = 1.0

	# SLOW → 屏蔽 AB（速度上限的 cap 在消费点 aircraft_physics.update_speed 里 cap，
	# 防止 AI / TacticalPlanner 之后覆盖 target_speed_kmh 把 cap 抹掉）
	if ac.status_slow_active:
		ac.is_afterburner = false


# ── 击杀回调 ─────────────────────────────────────────────
## 任意飞机死亡时（不分敌我），由归因系统调用一次。
## 集中处理所有"杀人时触发的 buff/debuff 副作用"，敌我对称：
##   - BLOODLUST 攻击者 → +HP
## 之后调用 SkillHooks.dispatch_on_kill 跑玩家系击杀触发型技能链
##   （机炮击杀恐惧 / 对头击杀 +HP / 最低空击杀无敌 等，均按 upgrade_stacks 早退）
static func on_kill(killer: Aircraft, victim: Aircraft) -> void:
	if killer == null or not is_instance_valid(killer) or killer.is_destroyed:
		return
	if killer.status_bloodlust_active:
		var max_hp_val: float = killer.params.max_hp if killer.params else 100.0
		killer.hp = minf(killer.hp + BLOODLUST_HEAL_PER_KILL, max_hp_val)
	# 玩家系技能钩子链
	SkillHooks.dispatch_on_kill(killer, victim)
