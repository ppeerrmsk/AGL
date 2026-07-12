class_name TacticalPlan extends RefCounted

## 战术决策输出 —— TacticalPlanner 的产物，所有执行模块（physics / combat_tracking / weapons）只读不写。
##
## 设计要点：
## 1. **值类型**。每帧由 planner 重新生成，存活到下一帧被替换。
## 2. **完整描述**。一张 plan 包含本帧所有动作意图，不依赖隐式状态（_gun_pass_committed 之类的模态锁）。
## 3. **可比较**。便于检测"上一帧 plan 与本帧 plan 的差异"做 log/动画过渡。

## 战术意图（替代旧的事后命名分支）
enum Intent {
	CRUISE,           ## 无目标巡航
	WAYPOINT_MOVE,    ## 玩家点击移动
	PASSIVE_AUTO_FIRE,## 无 combat_target 但雷达锁着敌人 + auto-fire 开 → 让 salvo 自动打
	TAIL_CHASE,       ## 已咬尾 + 在射程内 → 匹配速度稳定射击
	CLOSE_TAIL,       ## 已咬尾 + 远超射程 → 加力闭合
	LEAD_TURN,        ## 后半球未对准 → corner speed 抢占
	LEAD_PURSUIT,     ## 侧翼 / 中等 closing → 前置拦截
	LAG_PURSUIT,      ## 侧翼 + 目标急转 → 内切圆滞后追踪
	MERGE_PASS,       ## 对头交汇 → 不减速穿过
	WIDE_TURN,        ## hdg 偏差 >90° → 大角度修正
	EXTEND_RECOVER,   ## 已飞过目标 → 直线脱离重整
	BOOM_ZOOM_OUT,    ## 转不过敌人 → 拉远后再回头
	GROUND_STRAFE,    ## 对地扫射
	EVADE_MISSILE,    ## 来袭导弹规避
	LINE_UP,          ## 电磁炮射击纪律：平直对准提前点直线航线（spec weapon-employment-doctrine 阶段3）
}

## 武器装备状态
enum WeaponMode {
	NONE,             ## 不开火
	GUN,              ## 仅机炮（导弹挂机不发射）
	MISSILE,          ## 仅导弹
	BOTH,             ## 机炮 + 导弹双开（保留：未来配合 charge）
}

## 对面攻击 pass 子相位（spec surface-attack-pass）。GROUND_STRAFE intent 内部用，
## 由 Situation.strafe_pass_phase 读入、本字段写出、Aircraft._apply_tactical_plan 回写。
enum SurfacePhase {
	SETUP,            ## 对准进入：corner speed 转弯（未 too_close）
	RUN,              ## 已对准：俯冲/闭合开火
	EGRESS,           ## 飞越/脱离：直线拉开到 reentry 再折返
}

# ── 决策字段 ──
var intent: int = Intent.CRUISE
var pursuit_pos: Vector2 = Vector2.INF        ## combat_tracking 写入 ac.target_position
var target_speed_kmh: float = 900.0            ## physics 写入 ac.target_speed_kmh
var afterburner: bool = false                  ## physics 调 set_afterburner
var weapon_mode: int = WeaponMode.NONE         ## weapons 据此选模式
var allow_gun_fire: bool = false               ## 火控允许开火
var allow_missile_fire: bool = false           ## 火控允许发射导弹
var primary_weapon: String = ""
var bank_limit_deg: float = -1.0               ## 坡度上限（武器纪律用，LINE_UP=30；-1=无限制；消费点 update_bank/step_bank）                ## 武器竞选胜者（spec weapon-employment-doctrine；""=全失格/无战斗）
var target_altitude_m: float = -1.0            ## -1 = 保持，否则覆写 target_altitude
var target_altitude_tier: int = -1             ## -1 = 保持，否则覆写 target_altitude_tier
## 对面攻击 pass 下一相位（spec surface-attack-pass）；非 GROUND_STRAFE 的 intent 恒填 SETUP → 复位
var strafe_pass_phase: int = SurfacePhase.SETUP

## 调试：每个 intent 函数填一行解释为什么选这个 intent
var rationale: String = ""

## EXTEND_RECOVER 自动触发：检测到穿过目标时由 intent / planner 写入秒数，
## Aircraft._apply_tactical_plan 看到 > 0 就把 _bfm_extend_until 推到 now + 这个秒数。
## 默认 -1 表示不触发。
var trigger_extend_seconds: float = -1.0

# ══════════════════════════════════════════════
#  辅助
# ══════════════════════════════════════════════

static func intent_name(intent_id: int) -> String:
	match intent_id:
		Intent.CRUISE: return "CRUISE"
		Intent.WAYPOINT_MOVE: return "WAYPOINT_MOVE"
		Intent.PASSIVE_AUTO_FIRE: return "PASSIVE_AUTO_FIRE"
		Intent.TAIL_CHASE: return "TAIL_CHASE"
		Intent.CLOSE_TAIL: return "CLOSE_TAIL"
		Intent.LEAD_TURN: return "LEAD_TURN"
		Intent.LEAD_PURSUIT: return "LEAD_PURSUIT"
		Intent.LAG_PURSUIT: return "LAG_PURSUIT"
		Intent.MERGE_PASS: return "MERGE_PASS"
		Intent.WIDE_TURN: return "WIDE_TURN"
		Intent.EXTEND_RECOVER: return "EXTEND_RECOVER"
		Intent.BOOM_ZOOM_OUT: return "BOOM_ZOOM_OUT"
		Intent.GROUND_STRAFE: return "GROUND_STRAFE"
		Intent.EVADE_MISSILE: return "EVADE_MISSILE"
		Intent.LINE_UP: return "LINE_UP"
		_: return "UNKNOWN"

static func surface_phase_name(phase_id: int) -> String:
	match phase_id:
		SurfacePhase.SETUP: return "SETUP"
		SurfacePhase.RUN: return "RUN"
		SurfacePhase.EGRESS: return "EGRESS"
		_: return "UNKNOWN"

static func weapon_mode_name(mode_id: int) -> String:
	match mode_id:
		WeaponMode.NONE: return "NONE"
		WeaponMode.GUN: return "GUN"
		WeaponMode.MISSILE: return "MISSILE"
		WeaponMode.BOTH: return "BOTH"
		_: return "UNKNOWN"

func to_dict() -> Dictionary:
	return {
		"intent": intent_name(intent),
		"pursuit": pursuit_pos,
		"spd_kmh": target_speed_kmh,
		"ab": afterburner,
		"wpn": weapon_mode_name(weapon_mode),
		"gun_fire": allow_gun_fire,
		"msl_fire": allow_missile_fire,
		"alt_m": target_altitude_m,
		"alt_tier": target_altitude_tier,
		"why": rationale,
	}
