class_name AIController
extends Node

## AI 控制器：巡逻 / 交战（战术机动） / 导弹规避 状态机
## 交战时基于 Shaw《Fighter Combat》BFM 决策树选择战术机动

# 显式 preload 兜底新增的 class_name 类（Godot 全局类缓存有时不刷新）
const EscortBehavior := preload("res://scripts/ai/escort_behavior.gd")

enum AIState { PATROL, ENGAGE, EVADE_MISSILE, SQUAD_FOLLOW }
enum EngageTactic {
	LEAD_PURSUIT,    ## 前置追踪：积极闭合
	LAG_PURSUIT,     ## 滞后追踪：保持后半球不冲过
	LEAD_TURN,       ## 提前转弯：迎头时抢角度
	HIGH_YOYO,       ## 高悠悠：拉高防冲过
	LOW_YOYO,        ## 低悠悠：俯冲加速闭合
	BREAK_TURN,      ## 急转：被咬尾时防御
	EXTENSION,       ## 加速脱离：拉开距离
	SCISSORS,        ## 剪刀机动：近距反复交叉
	SNIPER_HOLD,     ## 狙击稳瞄：减速 + 不取 lead，机头死锁玩家当前位置（电磁炮 / 激光等需机头对准武器用）
}

const TACTIC_DISPLAY_NAME: Dictionary = {
	EngageTactic.LEAD_PURSUIT: "",
	EngageTactic.LAG_PURSUIT: "",
	EngageTactic.LEAD_TURN: "",
	EngageTactic.HIGH_YOYO: "高悠悠",
	EngageTactic.LOW_YOYO: "低悠悠",
	EngageTactic.BREAK_TURN: "",
	EngageTactic.EXTENSION: "加速脱离",
	EngageTactic.SCISSORS: "",
	EngageTactic.SNIPER_HOLD: "狙击稳瞄",
}

# ── 基础巡逻 ──
@export var aircraft: Aircraft
@export var waypoints: PackedVector2Array = PackedVector2Array()
@export var patrol_altitude: float = 5000.0
@export var arrival_distance: float = 100.0

# ── 战斗 AI ──
@export var enable_combat: bool = false       ## 是否启用战斗AI
@export var aggression: float = 0.5           ## 攻击倾向 (0=被动, 1=激进)
@export var engage_cooldown: float = 15.0     ## 两次交战间隔（秒）
@export var engage_duration: float = 20.0     ## 单次交战最长时间（秒）
@export var evade_missiles: bool = false      ## 是否规避来袭导弹
## 仅攻击地面单位（对地攻击直升机 / 攻击机专用）：
## 为 true 时 _try_engage_simple 只会选 GroundUnit 目标，永远不对空中单位开火
@export var ground_combat_only: bool = false

## 小队交战模式（僚机 SQUAD_FOLLOW 时使用）
## FREE (0)          : 自由交战——僚机会独立扫描敌机并主动交战（保留编队飞行），
##                     长机锁定目标时仍然协同攻击
## FOLLOW_LEADER (1) : 跟随长机——僚机只会打长机当前锁定的目标，不做独立扫描
enum SquadEngageMode { FREE = 0, FOLLOW_LEADER = 1 }
@export var squad_engage_mode: int = SquadEngageMode.FREE
@export var simple_ai: bool = false           ## 简化 AI：只用前置追踪，跳过 BFM 决策树/SA/压力系统

## AI 拥挤度分级（同屏敌机数过多时按此降决策频率，2026-05-04 起加入）：
##   IMMUNE — BOSS / Sentinel / 玩家方：永不降频
##   NORMAL — 主力载人机（MiG/F-86 等）：温和降频（30+ 敌机时 ×1.5）
##   CHEAP  — UAV/UCAV/Adds：激进降频（30+ 敌机时 ×2，配合 simple_ai 的 base divisor=3 → 6）
## 由 _compute_scaling_class() 在第一帧从 aircraft.team / category meta / params.is_unmanned 自动派生
enum AIScaleClass { IMMUNE = 0, NORMAL = 1, CHEAP = 2 }
const CROWD_THRESHOLD_LOW := 12   ## 同屏 ≤12 单位：不降频
const CROWD_THRESHOLD_HIGH := 30  ## 同屏 ≥30 单位：拉到 max_mult
const NORMAL_MAX_MULT := 1.5      ## NORMAL 类拥挤上限：divisor ×1.5
const CHEAP_MAX_MULT := 2.0       ## CHEAP 类拥挤上限：divisor ×2.0
var _scaling_class_cached: int = -1   ## -1 = 未计算（_physics_process 首次调用时派生）

## AI 决策节流：_physics_process 每 ai_tick_divisor 帧才跑一次，降低 CPU 消耗
## simple_ai 在 _ready 里自动设为 3（UAV/Adds 人海时大幅省运算），全功能 AI 保持 1
var ai_tick_divisor: int = 1
var _tick_phase: int = 0   ## 0..ai_tick_divisor-1，随机错开各 AI 的决策帧
@export var bvr_only: bool = false            ## BVR 狙击模式：只用导弹，不进近距战，被接近则撤退
## bvr_only 距离阈值的 per-AI 覆盖（0 = 用全局 BVR_STANDOFF_MIN/FLEE_DISTANCE 默认）
## 例：AF-03 用 standoff=2500 / flee=4000 → 维持 5-8km 远距站位（电磁炮甜点）
@export var bvr_standoff_min_px_override: float = 0.0
@export var bvr_flee_distance_px_override: float = 0.0

## 偏好"机头对准型武器"（电磁炮 / 激光剑 / 任何需要机头死锁目标的武器）
## 启用后 BFM 在交战阶段优先选 SNIPER_HOLD 战术 —— 减速 + 直瞄目标当前位置（不取 lead），
## 避免 LEAD_PURSUIT 的"追前置点导致永远在转弯"问题。
## 用法：装电磁炮 / 激光剑等武器的 AI 设此为 true（AF-03、未来 BOSS 机型等）。
@export var prefer_nose_aligned_weapon: bool = false
var boss_attacker: bool = false               ## BOSS 攻击手：禁止 EXTENSION/脱离/自保，死追玩家

# ── 事件系统 directive 覆盖 ──
## 由 GameEvent.set_directive 写入，存在期间 _physics_process 顶层完全跳过
## 正常 PATROL/ENGAGE/SQUAD_FOLLOW 路由，只执行 directive 行为。
## directive owner_event 失效时本字段自动清空，AI 回到正常状态。
var _directive: AIDirective = null
## directive 内部状态（如 PATROL_RING 当前角度、FLY_TO_POINT 是否已抵达）
var _directive_state: Dictionary = {}

## 设置事件 directive；null = 释放
func set_event_directive(directive: AIDirective) -> void:
	if _directive == directive:
		return
	# 优先级守卫：高优先级 directive 不被低优先级覆盖
	if directive != null and _directive != null \
			and _directive.is_owner_alive() and directive.priority < _directive.priority:
		return
	_directive = directive
	_directive_state.clear()
	if directive == null and aircraft:
		# 释放时清掉事件期间留下的强制目标，让正常 AI 重新选目标
		aircraft.clear_combat_target()

## 实际 boss_attacker 状态（综合 boss_attacker 标志 + F-47 角色 meta）
## 即使标志延迟一帧未更新，角色 meta 实时检查也能正确判断
func is_boss_attacker() -> bool:
	if boss_attacker:
		return true
	# 兜底检查：F-47 的 CLOSE_FIGHTER(2) 或 RANGED_STRIKER(3) 角色始终是攻击手
	if aircraft and aircraft.has_meta("f47_role"):
		var role: int = aircraft.get_meta("f47_role")
		return role == 2 or role == 3  # CLOSE_FIGHTER or RANGED_STRIKER
	return false

# ── BVR 狙击模式常量 ──
const BVR_STANDOFF_MIN := 2000.0             ## BVR 最小站位距离（像素）— 低于此距离强制脱离
const BVR_FLEE_DISTANCE := 3000.0            ## BVR 撤退后飞到的距离（像素）

# ── 协同齐射（F-47 小队战术） ──
var salvo_leader: bool = false               ## 是否是齐射指挥（leader 发射后通知僚机）
var _salvo_pending: bool = false             ## 收到齐射信号，等待发射
var _salvo_delay: float = 0.0               ## 齐射延迟倒计时（错开发射）

# ── 飞行员能力 ──
@export var skill_level: float = 0.7          ## 战术水平 (0=菜鸟, 1=王牌)
@export var composure: float = 0.6            ## 冷静度/抗压 (0=易慌, 1=冰冷)

# ── 飞行员性格 ──
@export var focus: float = 0.6               ## 目标专注度 (0=容易分心, 1=死盯不放)
@export var self_preservation: float = 0.5   ## 自保意识 (0=不怕死, 1=保命优先)
@export var situational_awareness: float = 0.6 ## 态势感知 (0=隧道视野, 1=全局洞察)

# ── 高度偏好（预留） ──
@export var preferred_altitude_tier: int = -99  ## -99=无偏好，否则为 CombatUnit.AltitudeTier 值

# ── 编队 ──
var squad: Squad = null              ## 所属编队
var squad_index: int = -1            ## 在编队中的序号（0=长机，1+=僚机）

## §C 玩家技能反向索引：每帧检测 _current_target 变化，差量更新 target.engaging_me
## 不在 _current_target 各赋值点散落，集中到 _physics_process 顶层做一次比对
var _prev_target_for_reverse_idx: CombatUnit = null
@export var orbit_squad_leader: bool = false  ## simple_ai 专用：巡逻时围绕长机旋转（指挥 UAV 招募的僚机用）
@export var shield_leader: bool = false       ## orbit 专用：主动飞入来袭导弹路径保护长机（含自爆拦截 @ MISSILE_INTERCEPT_DIST=100px）
## 玩家忠诚僚机 drone 专用：来袭导弹瞄向 squad.leader 时，drone 主动撞毁拦截
## 与 SQUAD_FOLLOW 配合使用；默认 false，不影响普通僚机
@export var kamikaze_intercept: bool = false
const KAMIKAZE_DETONATE_DIST_PX: float = 120.0   ## 60m，drone 与导弹距离 ≤ 此值即同归于尽
const KAMIKAZE_INTERCEPT_RANGE_PX: float = 2400.0 ## 1200m，开始飞向导弹拦截

# ── 护盾系统（shield_leader 模式）──
var _shield_missile: Missile = null           ## 当前帧检测到的来袭导弹
var _shield_threat_dir: Vector2 = Vector2.ZERO ## 威胁方向（用于偏移轨道中心）

# ── 绕长机飞行常量（orbit_squad_leader 模式）──
## 设计约束：
## 1. 切向速度 (ORBIT_RADIUS × ORBIT_ANGULAR_SPEED) 必须 < UAV 实际速度，否则轨道点永远追不上
## 2. UAV 物理转弯半径必须 ≤ ORBIT_RADIUS 才能在轨道上贴合飞行
## 3. ORBIT_TETHER_RADIUS < AURA_RADIUS=600 保证僚机始终在增益圈内
## 多层轨道系统：每架 UAV 按 squad_index 分配不同轨道半径
## 内圈更密、外圈更疏，像行星系统一样分层环绕
const ORBIT_INNERMOST := 60.0        ## 最内圈半径（像素，~120m）— squad_index 1
const ORBIT_SPACING := 40.0          ## 每层轨道间距（像素，~80m）
const ORBIT_MIN_SPEED_KMH := 400.0   ## 轨道最低速度（km/h）— 保持自然飞行感
const ORBIT_TETHER_RADIUS := 750.0   ## 护驾半径：不追击超出此范围的目标

const COVER_SCAN_RANGE := 2500.0     ## 掩护扫描范围（像素）≈5000m
const COVER_SCAN_INTERVAL := 0.5     ## 掩护扫描间隔（秒）
const COVER_DISENGAGE_RANGE := 3500.0 ## 掩护脱离距离（威胁远离后回归）
var _cover_scan_timer: float = 0.0
var _cover_target: Aircraft = null   ## 掩护交战目标（后半球威胁）
var _rejoining: bool = false       ## 交战/规避后正在全速归队
var _scatter_evade_timer: float = 0.0  ## 散开规避方向刷新计时器（玩家传播 evasion 时用）
var _scatter_no_missile_secs: float = 0.0  ## 散开期间累计"无导弹"时长，超阈值强制 exit（防 evasion_mode 卡住飞出地图）
var _squad_attacking_leader_target: bool = false  ## 正在协同攻击长机指定的目标
var _squad_free_engaging: bool = false  ## 正在自由交战模式下独立交战（同样享有 range grace）
## 协同攻击时的小队角色（squad_index → 角色）。NONE=单机/长机，其他=僚机分散战术
## 仅在进入 TEAM_ATTACK 时设置一次，离开协同攻击时复位为 NONE
enum SquadRole { NONE = 0, FLANK_LEFT = 1, FLANK_RIGHT = 2, HIGH_COVER = 3 }
var _squad_lateral_role: int = SquadRole.NONE
var _leader_target_lost_timer: float = 0.0  ## 长机目标丢失后的宽限计时（防止单帧抖动触发脱离）
const LEADER_TARGET_LOST_GRACE := 1.5  ## 长机目标丢失后的宽限时长（秒）
var _squad_range_grace_timer: float = 0.0  ## 长机指定目标超出僚机射程的宽限计时
const SQUAD_RANGE_GRACE := 2.0  ## 超出射程宽限时长（秒）— 允许僚机继续追击长机指定的目标一段时间

# ── 编队护盾/导弹拦截 ──
const MISSILE_THREAT_RANGE := 3000.0       ## 护盾导弹威胁检测范围（像素）
const MISSILE_HEADING_DOT := 0.5           ## 导弹朝向长机判定的点积阈值
const MISSILE_INTERCEPT_DIST := 100.0      ## 触发自爆拦截的距离（像素）
const SHIELD_THREAT_BIAS := 0.6            ## 护盾威胁偏移轨道中心比例
const ORBIT_SPEED_MULT := 1.6             ## 轨道速度 ≥ 长机速度 × 此值
const THREAT_HEADING_DOT := 0.3            ## 威胁朝向判定点积阈值

# ── Flock 散队 jink ──
const FLOCK_LATERAL_JINK := 650.0          ## 侧向闪避振幅（像素）
const FLOCK_FORWARD_JINK := 200.0          ## 前向闪避分量（像素）
const FLOCK_WEAVE_CYCLE := 1.2             ## 蛇形摆动周期倍率

# ── Simple AI 绕圈疲劳 ──
const ORBIT_CLOSE_DIST := 400.0            ## 近距绕圈判定距离（像素）
const ORBIT_FATIGUE_AOT := 40.0            ## 绕圈疲劳攻击角阈值（度）
const CONFUSED_TIMER_MIN := 1.5            ## 发呆最短时长（秒）
const CONFUSED_TIMER_MAX := 3.0            ## 发呆最长时长（秒）
const SIMPLE_ORBIT_THRESH_MIN := 8.0       ## 绕圈疲劳触发阈值最短（秒）
const SIMPLE_ORBIT_THRESH_MAX := 14.0      ## 绕圈疲劳触发阈值最长（秒）
const CONFUSED_FLIGHT_DIST := 1000.0       ## 发呆时直飞距离（像素）
const CONFUSED_SPEED_RATIO := 0.5          ## 发呆时速度比（最大速度 ×）
const REGULAR_UAV_SPEED_RATIO := 0.7       ## 普通 UAV 目标速度比
const REGULAR_UAV_LEAD := 0.5              ## 普通 UAV 拦截提前量
const ESCORT_UAV_LEAD := 1.0               ## 护卫 UAV 拦截提前量

# ── 编队反应（已迁移到 Squad，2026-05-04 重构）──
# Squad.FORMATION_SWITCH_THRESH / FORMATION_REACT_BASE / FORMATION_JITTER_AMP /
# Squad.FORMATION_JITTER_ADD / WINGMAN_ENGAGE_DELAY_MIN / WINGMAN_ENGAGE_DELAY_MAX

# ── 自由扫描 ──
const SQUAD_FREE_SCAN_RANGE := 2000.0      ## 僚机自由扫描范围（像素）
const SQUAD_FREE_MIN_DIST := 80.0          ## 自由扫描最小距离（防目标残骸）
const SQUAD_SCAN_RADAR_MULT := 1.3         ## 自由扫描雷达范围倍率

# ── BFM 决策阈值 ──
const BEING_CHASED_DOT := -0.3             ## 被追判定点积阈值
const HERBST_ACTIVATION_DIST := 1500.0     ## 赫尔贝特轮触发距离（像素）
const HERBST_MIN_ALTITUDE_M := 1500.0      ## J-Turn DECEL 段会刹到 ~69m/s（近失速），低于此高度不触发以免来不及恢复就坠地
const GUN_ATTACK_DOT := 0.3                ## 机炮攻击威胁朝向点积
const GUN_ATTACK_THREAT_DIST := 800.0      ## 机炮攻击威胁距离（像素）
const EVASION_TARGET_DIST := 2000.0        ## 规避目标距离（像素）
const LOCK_AWARE_DEFENSE_MULT := 0.1       ## 锁定感知防御概率乘数
const ALTITUDE_MATCH_THRESH := 500.0       ## 高度匹配阈值（像素）

# ── 拉弗伯雷检测 ──
const LUFBERRY_CLOSE_MULT := 2.0           ## 近距判定 = 机炮射程 × 此值
const LUFBERRY_THRESH_MIN := 2.5           ## 王牌最短触发时间（秒）
const LUFBERRY_THRESH_MAX := 4.0           ## 菜鸟最长触发时间（秒）
const LUFBERRY_COOLDOWN := 6.0             ## 脱出冷却（秒）

# ── 距离倍率（gun_range ×） ──
const BVR_CLOSE_MULT := 5.0               ## BVR 近距判定倍率
const TACTIC_CLOSE_MULT := 2.0            ## 战术选择近距倍率
const TACTIC_MID_MULT := 5.0              ## 战术选择中距倍率

# ── 战斗决策阈值 ──
const HEALTH_EXTEND_THRESH := 0.4          ## 血量低于此比例考虑脱离
const SPEED_EXTEND_THRESH := 0.8           ## 速度比低于此值考虑脱离
const DEFENSIVE_COUNTER_TIME := 5.0        ## 防御累计时间超过此值反击（秒）
const AGGRESSION_COUNTER_THRESH := 0.4     ## 反击所需最低攻击倾向
const SCISSORS_LOW_SPEED := 200.0          ## 低速进入剪刀机动阈值（m/s）
const HEALTH_AGGRESSIVE_EXTEND := 0.25     ## 激进脱离血量阈值
const MAX_MISTAKE_CHANCE := 0.15           ## 战术决策最大失误概率

# ── 战术最小持续时间（秒）──
const MIN_DUR_LEAD_PURSUIT := 0.5
const MIN_DUR_LAG_PURSUIT := 1.0
const MIN_DUR_LEAD_TURN := 1.5
const MIN_DUR_HIGH_YOYO := 2.0
const MIN_DUR_LOW_YOYO := 2.0
const MIN_DUR_BREAK_TURN := 1.5
const MIN_DUR_EXTENSION := 3.0
const MIN_DUR_SCISSORS := 1.0

# ── 闭合率阈值（pixels/frame）──
const CR_HIGHYOYO_CLOSE := 80.0            ## 近距高悠悠闭合率
const CR_LAG_PURSUIT := 50.0               ## 滞后追踪闭合率
const CR_LOWYOYO_FAR := 20.0              ## 远距低悠悠闭合率
const CR_HIGHYOYO_SIDE := 60.0             ## 侧面高悠悠闭合率
const CR_LOWYOYO_SIDE := 10.0             ## 侧面低悠悠闭合率
const SPEED_RATIO_LAG := 1.1               ## 滞后追踪速度比阈值
const MID_RANGE_LOWYOYO := 0.7             ## 中距低悠悠判定比例

# ── 滞后追踪参数 ──
const LAG_OFFSET_MIN := 80.0              ## 滞后偏移最小距离（像素）
const LAG_SPEED_RATIO := 0.95              ## 滞后追踪速度比
const LAG_MIN_SPEED := 400.0               ## 滞后追踪最低速度（km/h）

# ── 前置转弯参数 ──
const LEAD_TURN_CLOSING_ADJ := 50.0        ## 通过时间闭合率调整
const LEAD_TURN_SIXOCLOCK_MIN := 100.0     ## 6 点钟偏移最小值（像素）
const LEAD_TURN_SIXOCLOCK_MULT := 1.2      ## 6 点钟偏移比例乘数

# ── 高悠悠参数 ──
const HIGH_YOYO_CLIMB_MIN := 300.0         ## 爬升刹车高度最小值（米）
const HIGH_YOYO_LAG_RATIO := 0.6           ## 滞后追踪点枪程比
const HIGH_YOYO_LEAD_MIN := 0.3            ## 俯冲阶段提前量最小（秒）
const HIGH_YOYO_LEAD_MAX := 2.0            ## 俯冲阶段提前量最大（秒）

# ── 低悠悠参数 ──
const LOW_YOYO_LEAD_MIN := 0.5             ## 俯冲阶段提前量最小（秒）
const LOW_YOYO_LEAD_MAX := 3.0             ## 俯冲阶段提前量最大（秒）
const LOW_YOYO_APPROACH_SCALE := 0.15      ## 接近速度缩放因子
const LOW_YOYO_CLIMB_LEAD_MIN := 0.3       ## 爬升阶段提前量最小（秒）
const LOW_YOYO_CLIMB_LEAD_MAX := 2.0       ## 爬升阶段提前量最大（秒）

# ── 急转参数 ──
const BREAK_TURN_DIST := 1500.0            ## 急转目标位置距离（像素）
const BREAK_TURN_ALT_REDUCE := 300.0       ## 急转降高（米）
const BREAK_TURN_COUNTER_LEAD := 0.5       ## 反击阶段提前量比例
const BREAK_TURN_COUNTER_SPEED := 1.3      ## 反击速度倍率

# ── 脱离参数 ──
const EXTENSION_DISTANCE := 2000.0         ## 脱离目标距离（像素）
const EXTENSION_ESCAPE_MIN := 0.85         ## 逃跑速度最低比
const EXTENSION_ESCAPE_MAX := 0.95         ## 逃跑速度最高比
const EXTENSION_CLIMB := 200.0             ## 脱离爬升（米）
const EXTENSION_SUCCESS_DIST := 800.0      ## 脱离成功判定距离（像素）
const EXTENSION_SUCCESS_MULT := 4.0        ## 脱离成功枪程倍率

# ── 剪刀参数 ──
const SCISSORS_REVERSE_MIN := 0.8          ## 反转间隔最短（秒）
const SCISSORS_REVERSE_MAX := 2.5          ## 反转间隔最长（秒）
const SCISSORS_LATERAL := 300.0            ## 侧向偏移（像素）
const SCISSORS_FORWARD := 50.0             ## 前向接近（像素）
const SCISSORS_SAFE_SPEED := 1.3           ## 最低安全速度比
const SCISSORS_FALLBACK_SPEED := 400.0     ## 兜底速度（km/h）

# ── 机炮闪避 jink ──
const GUN_JINK_RANGE_MULT := 2.5           ## 触发范围 = 机炮射程 × 此值
const GUN_JINK_GRACE := 0.5                ## 停火后继续闪避宽限（秒）
const GUN_JINK_AMP_MIN := 60.0             ## 闪避振幅最小（像素，低技能）
const GUN_JINK_AMP_MAX := 150.0            ## 闪避振幅最大（像素，高技能）
const GUN_JINK_PERIOD_MIN := 0.8           ## 闪避周期最短（秒，高技能）
const GUN_JINK_PERIOD_MAX := 1.5           ## 闪避周期最长（秒，低技能）
const GUN_JINK_NOISE_FREQ := 3.7           ## 低技能噪声频率
const GUN_JINK_NOISE_AMP := 0.4            ## 低技能噪声振幅

# ── 交战速度 ──
const FALLBACK_ENGAGE_SPEED := 900.0       ## 兜底交战速度（km/h）
const ENGAGE_STALL_SAFETY := 1.2           ## 失速速度安全倍率

# ── 导弹规避参数 ──
const MANEUVER_ACTIVATE_DIST := 500.0      ## 后方导弹机动触发距离（像素）
const EVADE_FLIGHT_DIST := 2000.0          ## 规避飞行距离（像素）
const EVADE_TURN_DIST := 2000.0            ## 规避转弯距离（像素）
const EVADE_ALT_CHANGE := 1500.0           ## 规避高度变化（米）
const EVADE_ALT_THRESH := 6000.0           ## 规避高度方向阈值（米）

# ── 高度误差 ──
const ALTITUDE_ERROR_AMP := 500.0          ## 低技能高度判断误差振幅（米）

# ── 目标重评估 ──
const TARGET_EVAL_INTERVAL_MIN := 3.0      ## 低专注目标评估间隔（秒）
const TARGET_EVAL_INTERVAL_MAX := 10.0     ## 高专注目标评估间隔（秒）

var _prev_formation_offset_local: Vector2 = Vector2.INF  ## 上一帧相对长机本地坐标系的阵型偏移
var _formation_react_timer: float = 0.0  ## 阵型变换反应延迟（每架飞机个体化）
var _formation_blend: float = 1.0  ## 编队托管混合度（0=自主飞行, 1=完全托管）
var _engage_delay: float = 0.0     ## 进入交战前的反应延迟
var _formation_jitter_phase: float = 0.0  ## 个体扰动相位（随机初始化）

# ── 内部状态 ──
var current_waypoint_index: int = 0
var _state: AIState = AIState.PATROL
var _engage_timer: float = 0.0           ## 当前交战已持续时间
var _cooldown_timer: float = 0.0         ## 交战冷却剩余
var _scan_timer: float = 0.0            ## 扫描计时器
var _evade_target_pos: Vector2 = Vector2.INF  ## 规避目标位置
var _current_target: CombatUnit = null   ## 当前交战目标（飞机或地面单位）

# ── 战术机动状态 ──
var _tactic: EngageTactic = EngageTactic.LEAD_PURSUIT
var _tactic_timer: float = 0.0          ## 当前战术已持续时间
var _tactic_min_duration: float = 0.0   ## 当前战术最小持续时间（防抖动）
var _yoyo_phase: int = 0                ## Yo-Yo 阶段：0=拉高/俯冲, 1=恢复追踪
var _yoyo_base_alt: float = 0.0         ## Yo-Yo 开始时的高度
var _scissors_side: float = 1.0         ## 剪刀机动当前方向（1 或 -1）
var _scissors_reverse_timer: float = 0.0 ## 剪刀反转计时
var _extension_start_pos: Vector2 = Vector2.ZERO ## 脱离起始位置
var _prev_tactic: EngageTactic = EngageTactic.LEAD_PURSUIT ## 上一个战术（用于调试）
var _defensive_time: float = 0.0        ## 持续处于防御态势的累计时间
var _break_phase: int = 0               ## Break Turn 阶段：0=急转, 1=反转迎头
var _target_eval_timer: float = 0.0     ## 交战中目标重评估计时器

# ── 机炮闪避（斗士型蛇形机动） ──
var _gun_jink_active: bool = false      ## 正在执行机炮闪避蛇形机动
var _gun_jink_timer: float = 0.0        ## 蛇形相位计时器
var _gun_jink_grace: float = 0.0        ## 停火后继续闪避的宽限倒计时

# ── 飞行员心理/性格子系统（压力/SA/判断误差）──
## 性格特征（skill_level/composure/focus 等 @export）保留在本类，由 spawner 设置。
## 派生状态（_stress/_drift_*/_sa_*）和更新逻辑都移到 PilotPersonality。
var personality: PilotPersonality = PilotPersonality.new()

# ── 拉弗伯雷圆圈（mutual orbit）检测 ──
var _lufberry_timer: float = 0.0         ## 处于互相绕圈状态的累计时间
var _lufberry_cooldown: float = 0.0      ## 脱出后冷却，避免反复触发

# ── Simple AI 近距绕圈疲劳（UAV 狗斗削弱） ──
var _simple_orbit_time: float = 0.0      ## 近距持续绕圈累计时间
var _simple_orbit_threshold: float = 10.0 ## 本次绕圈疲劳触发阈值
var _simple_confused: bool = false        ## 是否进入"发呆"状态
var _simple_confused_timer: float = 0.0   ## 发呆剩余时间
var _simple_confused_heading: Vector2 = Vector2.ZERO ## 发呆时的固定飞行方向

## 当前战术名称（供 DebugPanel 读取）
var current_tactic_name: String = ""
## 压力/SA 读取：DebugPanel 通过 ctrl.personality.current_stress / current_sa_level 访问

func _ready() -> void:
	_formation_jitter_phase = randf() * TAU  # 每架飞机不同的扰动相位
	if aircraft:
		aircraft._ai_ref = self  # AircraftFormation / debug 路径走 ac._ai_ref 读 AI 端权威值
	if waypoints.is_empty():
		_generate_default_waypoints()
	if aircraft:
		if aircraft.flat_altitude:
			aircraft.set_target_tier(aircraft.target_altitude_tier)
		else:
			aircraft.target_altitude = patrol_altitude
		_set_next_waypoint()
	_scan_timer = randf_range(1.0, 3.0)
	# simple_ai 性价比极高 → 每 3 物理帧才决策一次，随机相位错开 CPU 峰谷
	# 60Hz 下降到 20Hz，对 UAV/Adds 这种"直线飞/简单追击"足够
	if simple_ai:
		ai_tick_divisor = 3
		_tick_phase = randi() % ai_tick_divisor

## 从 aircraft 标记派生 AI 拥挤降频分级（在 _physics_process 首次调用时缓存）
##   - 玩家方（team 0）→ IMMUNE
##   - meta category=="boss" 或 enemy_type=="uav_commander" → IMMUNE（F-47 / F-14 Poltergeist / Sentinel）
##   - meta category=="adds" 或 params.is_unmanned → CHEAP（杂兵 / UAV / UCAV）
##   - 其它 → NORMAL（载人战机如 MiG/F-86 等）
func _compute_scaling_class() -> int:
	if not aircraft:
		return AIScaleClass.NORMAL
	if aircraft.team == 0:
		return AIScaleClass.IMMUNE
	var cat: String = str(aircraft.get_meta("category", ""))
	if cat == "boss":
		return AIScaleClass.IMMUNE
	if cat == "adds":
		return AIScaleClass.CHEAP
	var et: String = str(aircraft.get_meta("enemy_type", ""))
	if et == "uav_commander":
		return AIScaleClass.IMMUNE
	if aircraft.params and aircraft.params.is_unmanned:
		return AIScaleClass.CHEAP
	return AIScaleClass.NORMAL

## 获取日志用名称
func _log_name() -> String:
	if not aircraft:
		return "???"
	var side := "Friend" if aircraft.team == 0 else "Enemy"
	var dn: String = aircraft.params.display_name if aircraft.params else "???"
	return "%s/%s[%s]" % [side, dn, aircraft.callsign]

## 获取目标日志名称
func _log_target_name(target) -> String:
	# ⚠ 不能加 CombatUnit 类型标注：调用点可能传入 previously freed 的节点
	#   （disengage 在 combat_target 被外部释放后仍会记录"was fighting XXX"），
	#   Godot 的参数类型检查会先于函数体抛错，内部 is_instance_valid 守卫进不去
	if not target or not is_instance_valid(target):
		return "None"
	if target is Aircraft:
		var ac: Aircraft = target
		var side := "Friend" if ac.team == 0 else "Enemy"
		var dn: String = ac.params.display_name if ac.params else "???"
		return "%s/%s[%s]" % [side, dn, ac.callsign]
	return target.callsign if target.callsign != "" else target.name

func _physics_process(delta: float) -> void:
	# Perf 包装：所有 early-return 也计入耗时 → 真实"AI 占了多少帧预算"
	# 包含 throttled-skip 的便宜 return；用 calls_per_frame 可以反推降频是否生效
	var _perf_t0: int = Time.get_ticks_usec()
	_physics_process_impl(delta)
	PerfBuckets.tick("ai_tick", Time.get_ticks_usec() - _perf_t0)


func _physics_process_impl(delta: float) -> void:
	if not aircraft or aircraft.is_destroyed:
		# 飞机销毁时清掉自己在他人 engaging_me 里的 entry
		if is_instance_valid(_prev_target_for_reverse_idx) and _prev_target_for_reverse_idx is Aircraft:
			(_prev_target_for_reverse_idx as Aircraft).engaging_me.erase(aircraft.get_instance_id() if aircraft else 0)
			_prev_target_for_reverse_idx = null
		return

	# §C 反向索引差量同步：检测 _current_target 变化（每帧一次比对）
	# 仅维护 team 0 玩家系飞机的 engaging_me（其它阵营不需要）
	if _current_target != _prev_target_for_reverse_idx:
		if is_instance_valid(_prev_target_for_reverse_idx) and _prev_target_for_reverse_idx is Aircraft:
			(_prev_target_for_reverse_idx as Aircraft).engaging_me.erase(aircraft.get_instance_id())
		if is_instance_valid(_current_target) and _current_target is Aircraft \
				and (_current_target as Aircraft).team == 0:
			(_current_target as Aircraft).engaging_me[aircraft.get_instance_id()] = aircraft
		_prev_target_for_reverse_idx = _current_target

	# Herbst 激活期间 AI 完全停摆：不再跑 engage/evade/follow/target 选择，
	# 否则每 tick 的 bvr_only flee→_disengage→boss re-engage 闭环会反复刷
	# target_position / combat_target / tactic / _cached_target_heading，
	# 和 Herbst 模块自己的 heading 控制抢写 → 飞机视觉颤抖。
	# Herbst 自带 1.6s 时长 + 5s counterattack 窗口，期间不需要 AI 介入；
	# 机动结束（is_active=false）AI 立即恢复。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (6)
	var _hm_ai := aircraft.get_herbst()
	if _hm_ai and _hm_ai.is_active:
		return

	# ── 事件 directive 顶层覆盖 ──
	# 存在 directive 且其 owner_event 仍 active 时：跳过所有正常 AI 路由，
	# 只执行 directive 指定的 verb（飞向某点 / 盘旋 / 跟航线 / 强制目标 / 被动）。
	# directive 释放或事件结束 → 自然回退到下面的正常流程。
	if _directive != null:
		if not _directive.is_owner_alive():
			set_event_directive(null)
		else:
			_process_directive(delta)
			return

	# 节流：simple_ai 等低优先级 AI 每 N 帧才决策一次，带相位错开
	# 跳过的帧里 Aircraft 物理照常跑，只是 AI 不重新算目标/阵型/规避
	# 拥挤度调节：同屏单位 > 12 时按 ai_scaling_class 放大 divisor（CHEAP UAV 在 30+ 时×2，NORMAL ×1.5）
	if _scaling_class_cached < 0:
		_scaling_class_cached = _compute_scaling_class()
	var effective_divisor: int = ai_tick_divisor
	if _scaling_class_cached != AIScaleClass.IMMUNE:
		var unit_count: int = CombatUnit.all_units.size()
		if unit_count > CROWD_THRESHOLD_LOW:
			var crowd_t: float = clampf(float(unit_count - CROWD_THRESHOLD_LOW) / float(CROWD_THRESHOLD_HIGH - CROWD_THRESHOLD_LOW), 0.0, 1.0)
			var max_mult: float = CHEAP_MAX_MULT if _scaling_class_cached == AIScaleClass.CHEAP else NORMAL_MAX_MULT
			effective_divisor = int(ceil(float(ai_tick_divisor) * lerpf(1.0, max_mult, crowd_t)))
	if effective_divisor > 1:
		if (Engine.get_physics_frames() + _tick_phase) % effective_divisor != 0:
			return
		delta *= float(effective_divisor)  # 放大 delta，让 timers/scan_timer 节奏保持一致

	# ── kamikaze 拦截 hook（玩家忠诚僚机 drone 专用）──
	# 来袭导弹瞄向 squad.leader 且距离合适时，break formation 飞过去撞毁
	# 在 simple_ai / 全功能 AI 路由之前介入，确保拦截优先于其他行为
	if kamikaze_intercept and _try_kamikaze_intercept(delta):
		return

	if simple_ai:
		# simple AI 只承袭固定 aggression，不受压力/SA 影响
		aircraft.tactical_aggression = clampf(aggression, 0.0, 1.0)
		# 族群散开：受击时强行中断任何交战追踪，回到 waypoint 分支应用侧向偏移
		if aircraft.flock_scatter_timer > 0.0 and _current_target != null:
			_current_target = null
			aircraft.clear_combat_target()
			aircraft.ai_override_pursuit = false
		_process_simple(delta)
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	personality.update_stress(self, delta)
	personality.update_drift(self, delta)
	personality.update_situational_awareness(self, delta)

	# 写入 Aircraft 的战术激进度：由 effective_skill × aggression 驱动
	# 高技能高攻击性 → 接近 1（像 survivor 玩家一样拉满结构 G）
	# 低技能或高压力 → 接近 0（保守 70% 持续 G 限制 + turn_speed）
	aircraft.tactical_aggression = clampf(_effective_skill() * aggression, 0.0, 1.0)

	# ── 僚机编队状态自校正守卫（运行时兜底）──
	# 2026-05-04 重构后：所有 spawn 路径（main / survivor_spawner / survivor_mode /
	# zone_mission / aircraft_weapons drone）都通过 SquadFactory.register_wingman(set_state=true)
	# 显式进 SQUAD_FOLLOW，不再依赖本守卫做初始化。
	# 守卫现在只服务 **运行时动态变化** 的兜底：
	#   1. 中队成员重组（如未来招募系统把游离 AI 拉入小队）
	#   2. 罕见的 PATROL 残留路径（_set_next_waypoint 失败 / waypoints 清空等）
	# Sentinel UAV escort 走 simple_ai 路径（ai_controller.gd:481 提前 return），永远不会
	# 触发本守卫——orbit_squad_leader 与 SQUAD_FOLLOW 互不影响。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (5) + 2026-05-04 squad 重构
	if _state == AIState.PATROL and not bvr_only \
			and squad and is_instance_valid(squad.leader) and not squad.leader.is_destroyed \
			and squad.leader != aircraft:
		_state = AIState.SQUAD_FOLLOW
		_rejoining = true
		_formation_blend = 0.0
		aircraft.lod_level = 1
		EventLogger.log_event("AI_STATE", _log_name(),
			"auto-enter SQUAD_FOLLOW (spawn init guard, leader=%s)" % squad.leader.callsign)

	# ── 玩家长机传播的 evasion：僚机立刻散开自保 ──
	# 僚机 aircraft.evasion_mode=true（由长机 _propagate_evasion_to_squad 广播）→ 不论当前状态，
	# 强制进入 EVADE_MISSILE。允许阵型被破坏、各自闪避；exit 由长机关 evasion 时同步广播触发
	if aircraft.evasion_mode and _state != AIState.EVADE_MISSILE \
			and squad and is_instance_valid(squad.leader) and squad.leader != aircraft \
			and not is_boss_attacker():
		MissileEvasion.enter_evade(self)
		return

	match _state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.EVADE_MISSILE:
			MissileEvasion.process_evade(self, delta)
		AIState.SQUAD_FOLLOW:
			SquadCoordination.process_squad_follow(self, delta)

# ══════════════════════════════════════════════
#  飞行员能力系统（委托给 PilotPersonality）
# ══════════════════════════════════════════════

## 有效技能 = 基础技能 × 压力衰减
func _effective_skill() -> float:
	return personality.effective_skill(skill_level, composure)

## 有效自保 = 基线自保 + 压力推升
func _effective_self_preservation() -> float:
	return personality.effective_self_preservation(self_preservation, composure)

## 有效态势感知 = 基础SA × 压力衰减 × 疲劳衰减
func _effective_sa() -> float:
	return personality.effective_sa(situational_awareness, composure, aircraft)

## 给目标位置加上漂移偏差
func _apply_position_error(pos: Vector2) -> Vector2:
	return personality.apply_position_error(pos, _current_target, is_boss_attacker())

## 给速度加上误差
func _apply_speed_error(speed_kmh: float) -> float:
	return personality.apply_speed_error(speed_kmh, is_boss_attacker())

## 给高度加上判断误差
func _apply_altitude_error(alt: float) -> float:
	return personality.apply_altitude_error(alt)

## 获取飞机的 CombatParams（性格参数），用于战术执行中的风格偏移
func _cb() -> CombatParams:
	return aircraft._combat_params()

# ══════════════════════════════════════════════
#  事件 directive 执行
#  GameEvent 通过 set_event_directive 下发；本函数把 verb 翻译成
#  target_position / waypoints / combat_target / enable_combat 写入 Aircraft。
#  执行期间完全跳过正常 AI 路由。
# ══════════════════════════════════════════════

func _process_directive(_delta: float) -> void:
	var d := _directive
	# 通用：不交战时清掉 combat_target，避免残留目标牵制 AI
	if d.combat_disabled:
		aircraft.clear_combat_target()
	match d.type:
		AIDirective.Type.FLY_TO_POINT:
			var tgt: Vector2 = d.params.get("target", aircraft.global_position)
			aircraft.target_position = tgt
			aircraft.keep_target_on_arrival = false
			# 抵达检查
			if aircraft.global_position.distance_to(tgt) < d.arrival_radius:
				_directive_arrival_dispatch()
		AIDirective.Type.PATROL_RING:
			_directive_patrol_ring_step()
		AIDirective.Type.FOLLOW_PATH:
			_directive_follow_path_step()
		AIDirective.Type.HOLD_POSITION:
			# 保持当前位置：飞机原地盘旋（target = 旁边一点让它转圈）
			var p := aircraft.global_position
			aircraft.target_position = p + Vector2(0, -200).rotated(aircraft.heading + PI * 0.5)
		AIDirective.Type.ENGAGE_TARGET:
			var t = d.params.get("target", null)
			if is_instance_valid(t):
				aircraft.combat_target = t
				_current_target = t
				_state = AIState.ENGAGE
				aircraft.target_position = t.global_position
		AIDirective.Type.PASSIVE:
			pass   # 啥也不做，飞机沿 waypoints 飞或保持 target_position

## FLY_TO_POINT 抵达分派
func _directive_arrival_dispatch() -> void:
	var d := _directive
	match d.on_arrival:
		AIDirective.OnArrival.HOLD:
			d.type = AIDirective.Type.HOLD_POSITION
			_directive_state.clear()
		AIDirective.OnArrival.PATROL:
			var center: Vector2 = d.params.get("target", aircraft.global_position)
			# 优先用调用方指定的 _pending_patrol_radius，否则按 arrival_radius × 2
			var r: float = float(d.params.get("_pending_patrol_radius", d.arrival_radius * 2.0))
			d.type = AIDirective.Type.PATROL_RING
			d.params = {"center": center, "radius": r, "n_waypoints": 6}
			_directive_state.clear()
		AIDirective.OnArrival.RELEASE:
			set_event_directive(null)
		AIDirective.OnArrival.CALLBACK:
			if d.on_complete.is_valid():
				d.on_complete.call(self)

## PATROL_RING：每帧推进一个圆周航点，到达就跳下一个
func _directive_patrol_ring_step() -> void:
	var d := _directive
	var center: Vector2 = d.params.get("center", Vector2.ZERO)
	var radius: float = float(d.params.get("radius", 1000.0))
	var n: int = int(d.params.get("n_waypoints", 6))
	var idx: int = int(_directive_state.get("idx", -1))
	if idx < 0:
		# 首次进入：选离当前位置最近的航点开始
		var best := 0
		var best_d2 := INF
		for i in range(n):
			var a := float(i) / float(n) * TAU
			var pt := center + Vector2(cos(a), sin(a)) * radius
			var dd: float = aircraft.global_position.distance_squared_to(pt)
			if dd < best_d2:
				best_d2 = dd
				best = i
		idx = best
	var ang := float(idx) / float(n) * TAU
	var wp := center + Vector2(cos(ang), sin(ang)) * radius
	aircraft.target_position = wp
	aircraft.keep_target_on_arrival = false
	if aircraft.global_position.distance_to(wp) < 250.0:
		idx = (idx + 1) % n
	_directive_state["idx"] = idx

## FOLLOW_PATH：沿 waypoints 一路飞，可循环
func _directive_follow_path_step() -> void:
	var d := _directive
	var wps: PackedVector2Array = d.params.get("waypoints", PackedVector2Array())
	if wps.is_empty():
		return
	var loop: bool = bool(d.params.get("loop", false))
	var idx: int = int(_directive_state.get("idx", 0))
	if idx >= wps.size():
		if loop:
			idx = 0
		else:
			# 抵达终点：HOLD_POSITION（让事件层决定是否切其他指令）
			d.type = AIDirective.Type.HOLD_POSITION
			return
	var wp := wps[idx]
	aircraft.target_position = wp
	aircraft.keep_target_on_arrival = false
	if aircraft.global_position.distance_to(wp) < 300.0:
		idx += 1
	_directive_state["idx"] = idx

# ══════════════════════════════════════════════
#  SIMPLE AI — 轻量化逻辑（UAV 等低级敌人）
#  跳过压力/SA/BFM 决策树，只做巡逻+直线追踪
# ══════════════════════════════════════════════

func _process_simple(delta: float) -> void:
	aircraft.keep_target_on_arrival = false

	# ── 护驾长机失效检测（Sentinel 被击坠）──
	# 一旦长机不再有效，立即清除 orbit flag 和 squad 引用，回退为独立 simple AI
	# survivor_mode._update_enemy_waypoints 会在 8 秒内为其补充新航点
	if orbit_squad_leader and not EscortBehavior.is_active(self):
		EscortBehavior.cleanup_after_leader_lost(self)

	# ── 护盾系统（shield_leader 模式，优先级高于一切）──
	# 只在导弹来袭时介入，平时正常轨道飞行
	if shield_leader and EscortBehavior.is_active(self):
		var _leader := squad.leader

		# ── 每帧导弹扫描 ──
		_shield_missile = null
		var _mm := aircraft.missile_manager
		if _mm:
			var best_dist := INF
			var leader_pos := _leader.global_position
			for child in _mm.get_children():
				if not child is Missile:
					continue
				var m: Missile = child
				if not m.is_active or m.is_flare_jammed:
					continue
				if m.team == _leader.team:
					continue
				var msl_to_leader := leader_pos - m.global_position
				var dist_to_leader := msl_to_leader.length()
				if dist_to_leader > MISSILE_THREAT_RANGE:
					continue
				var msl_fwd := Vector2(sin(m.heading), -cos(m.heading))
				if msl_fwd.dot(msl_to_leader.normalized()) < MISSILE_HEADING_DOT:
					continue
				if dist_to_leader < best_dist:
					best_dist = dist_to_leader
					_shield_missile = m

		# ── 导弹自爆拦截（100px 内触发，带 AOE 视觉指示）──
		if _shield_missile and _shield_missile.is_active:
			var msl_dist := _shield_missile.global_position.distance_to(aircraft.global_position)
			if msl_dist < MISSILE_INTERCEPT_DIST:
				# 真正执行自爆的这一瞬间显示"舍身"（只有这一架 UAV，不会编队刷屏）
				current_tactic_name = "TACTIC_KAMIKAZE"
				aircraft.show_tactic_popup(tr("TACTIC_KAMIKAZE"))
				# 在爆炸点生成 AOE 视觉圈（和玩家近炸引信一样的红圈提示）
				var mm := aircraft.missile_manager as MissileManager
				if mm:
					mm._aoe_zones.append({
						"pos": aircraft.global_position,
						"altitude": aircraft.altitude,
						"radius_px": 50.0,  # 自爆指示圈半径（比近炸引信小一些）
						"time_left": 1.0,
						"max_time": 1.0,
						"damage": 0.0,      # 纯视觉，不造成额外伤害
						"team": aircraft.team,
						"hit_set": { aircraft.get_instance_id(): true },
					})
					mm.queue_redraw()
				# UAV 承受伤害
				aircraft.take_damage(_shield_missile.params.damage if _shield_missile.params else 80.0, _shield_missile, "missile")
				# 销毁导弹
				_shield_missile.is_active = false
				_shield_missile.queue_free()
				EventLogger.log_event("MISSILE",
					_shield_missile.params.display_name if _shield_missile.params else "MSL",
					"intercepted by %s (shield)" % aircraft.callsign)
				_shield_missile = null
				return
			# 不改变轨道——继续绕圈

		# ── 威胁感知：检测正在瞄准长机的敌机（用于偏移轨道中心）──
		# 玩家瞄准 Sentinel 时，所有 UAV 的轨道向威胁方向偏移
		# 这样 UAV 自然集中在导弹来袭方向，大幅提高拦截概率
		var _threat_bias := Vector2.ZERO
		if _shield_missile:
			# 有导弹在飞：偏移向导弹方向
			_threat_bias = (_shield_missile.global_position - _leader.global_position).normalized()
		else:
			# 检查是否有敌机正在瞄准/接近长机
			var parent_node := _leader.get_parent()
			if parent_node:
				var closest_threat_dist := SHIELD_ENGAGE_RANGE
				for child in parent_node.get_children():
					if not child is Aircraft or child.team == _leader.team or child.is_destroyed:
						continue
					var ac := child as Aircraft
					var dist_to_leader := ac.global_position.distance_to(_leader.global_position)
					if dist_to_leader >= closest_threat_dist:
						continue
					# 检查敌机是否朝着长机方向飞
					var to_leader := (_leader.global_position - ac.global_position).normalized()
					var ac_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
					if ac_fwd.dot(to_leader) > THREAT_HEADING_DOT:  # 大致朝向长机
						closest_threat_dist = dist_to_leader
						_threat_bias = (ac.global_position - _leader.global_position).normalized()
		# 将偏移量存入实例变量，供轨道代码使用
		_shield_threat_dir = _threat_bias

	# 巡逻：走航点 or 绕长机飞行
	if not _current_target or not is_instance_valid(_current_target) or _current_target.is_destroyed:
		_current_target = null

		# ── 多层轨道环绕（指挥 UAV 编队）──
		# 每架 UAV 按 squad_index 分配不同半径轨道，像行星系统分层环绕
		if EscortBehavior.is_active(self) and squad.leader != aircraft:
			var leader := squad.leader
			# 轨道中心：有威胁时向威胁方向偏移（UAV 集中在导弹来袭侧）
			var center := leader.global_position
			if _shield_threat_dir != Vector2.ZERO:
				# 偏移量 = 轨道半径的 60%，让 UAV 密集覆盖威胁方向
				var bias_amount := (ORBIT_INNERMOST + float(maxi(squad_index, 1) - 1) * ORBIT_SPACING) * SHIELD_THREAT_BIAS
				center += _shield_threat_dir * bias_amount

			# 按 squad_index 分配轨道半径：index 1=最内圈，逐层向外
			var slot := maxi(squad_index, 1)
			var radius := ORBIT_INNERMOST + float(slot - 1) * ORBIT_SPACING

			# 轨道速度：物理公式，但必须 > 长机速度才能真正绕圈
			var leader_speed_kmh := leader.speed * 3.6
			var orbit_speed_kmh := ORBIT_MIN_SPEED_KMH
			if aircraft.params:
				var radius_m := radius / Aircraft.PIXELS_PER_METER
				var g_avail := aircraft.params.max_g * 0.5
				orbit_speed_kmh = maxf(sqrt(radius_m * 9.81 * g_avail) * 3.6, ORBIT_MIN_SPEED_KMH)
			# 关键：轨道速度必须比长机快，否则只能跟在后面
			orbit_speed_kmh = maxf(orbit_speed_kmh, leader_speed_kmh * ORBIT_SPEED_MULT)

			# 角速度 = 线速度 / 半径
			var orbit_speed_px := orbit_speed_kmh / 3.6 * Aircraft.PIXELS_PER_METER
			var ang_speed := orbit_speed_px / maxf(radius, 1.0)
			# 按 squad_index 均匀错开相位
			var members_count := maxi(squad.members.size() - 1, 1)
			var phase := float(slot - 1) * (TAU / float(members_count))
			var angle := Time.get_ticks_msec() / 1000.0 * ang_speed + phase

			aircraft.target_position = center + Vector2(cos(angle), sin(angle)) * radius
			aircraft.ai_override_pursuit = true
			aircraft.target_speed_kmh = orbit_speed_kmh
			aircraft.orbit_speed_cap = orbit_speed_kmh / 3.6
			# 高度匹配长机
			if aircraft.flat_altitude:
				aircraft.set_target_tier(leader.get_altitude_tier())
			else:
				aircraft.target_altitude = leader.altitude

			# ── 自爆攻击模式（最外圈 UAV 飞向敌人自爆）──
			# 根据编队规模指派自爆机：<8 架 = 1 架自爆，≥8 架 = 2 架自爆
			# 自爆机 = squad_index 最大的 1~2 架
			# 例外：飞机带 "no_kamikaze" meta 永不出列（Mother Goose MQ-111 等专职近距护卫）
			if shield_leader and enable_combat and not aircraft.has_meta(&"no_kamikaze"):
				var _total_members := squad.members.size() - 1
				var _kamikaze_count := 2 if _total_members >= 8 else 1
				var _is_kamikaze := squad_index > _total_members - _kamikaze_count

				if _is_kamikaze:
					# 寻找最近的敌人（不限距离，自爆机可以飞出 Sentinel 范围追杀）
					_scan_timer -= delta
					if _scan_timer <= 0.0:
						_scan_timer = 0.5
						var best_enemy: CombatUnit = null
						var best_edist := INF
						# 用共享列表代替 get_parent().get_children() (perf: 节点数 N >> 单位数)
						for unit in CombatUnit.all_units:
							if unit and unit.team != aircraft.team and not unit.is_destroyed:
								var d: float = unit.global_position.distance_to(aircraft.global_position)
								if d < best_edist:
									best_edist = d
									best_enemy = unit
						_current_target = best_enemy if best_enemy else null

					if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
						# 目标超出光环范围：放弃追击，返回轨道
						var tgt_to_leader: float = _current_target.global_position.distance_to(leader.global_position)
						if tgt_to_leader > SHIELD_ENGAGE_RANGE:
							_current_target = null
							aircraft.clear_combat_target()

					if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
						# 飞向敌人（前置追踪）
						var tgt_fwd := Vector2(sin(_current_target.heading), -cos(_current_target.heading))
						var dist_to_tgt := aircraft.global_position.distance_to(_current_target.global_position)
						var lead_time := dist_to_tgt / maxf(aircraft.speed * Aircraft.PIXELS_PER_METER, 1.0)
						var lead_pos := _current_target.global_position + tgt_fwd * _current_target.speed * Aircraft.PIXELS_PER_METER * lead_time * 0.8
						aircraft.target_position = lead_pos
						aircraft.ai_override_pursuit = true
						aircraft.orbit_speed_cap = 0.0  # 解除限速，全速追击
						if aircraft.params:
							aircraft.target_speed_kmh = aircraft.params.max_speed
						aircraft.set_combat_target(_current_target)

						# 自爆判定：100px 内触发
						if dist_to_tgt < 100.0:
							# 真正执行自爆的瞬间显示"舍身"（只有这一架 UAV 会走到这里）
							current_tactic_name = "TACTIC_KAMIKAZE"
							aircraft.show_tactic_popup(tr("TACTIC_KAMIKAZE"))
							# AOE 视觉指示
							var mm := aircraft.missile_manager as MissileManager
							if mm:
								mm._aoe_zones.append({
									"pos": aircraft.global_position,
									"altitude": aircraft.altitude,
									"radius_px": 50.0,
									"time_left": 1.0,
									"max_time": 1.0,
									"damage": 0.0,
									"team": aircraft.team,
									"hit_set": { aircraft.get_instance_id(): true },
								})
								mm.queue_redraw()
							# 对敌人造成导弹级伤害
							var dmg := 80.0
							if aircraft.params and aircraft.params.missile:
								dmg = aircraft.params.missile.damage
							_current_target.take_damage(dmg, aircraft, "collision")
							EventLogger.log_event("KAMIKAZE", aircraft.callsign,
								"self-destruct hit %s (dmg=%.0f)" % [_current_target.callsign, dmg])
							# UAV 自毁（自身爆炸，无攻击者）
							aircraft.take_damage(9999.0, null, "collision")
							_current_target = null
							return
						return  # 自爆机不走后续轨道逻辑
			return

		elif not waypoints.is_empty():
			if current_waypoint_index >= waypoints.size():
				current_waypoint_index = 0
			var target_wp := waypoints[current_waypoint_index]
			if aircraft.global_position.distance_to(target_wp) < arrival_distance:
				current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
			var final_wp: Vector2 = waypoints[current_waypoint_index]
			# ── 族群散开：受击闪避（直升机 jink 机动）──
			# 相比单纯"侧向偏移"，这里用 weave 摆动 + 时间曲线：
			#   1) sin 曲线幅度：头尾 0、中段峰值，形成"侧跨→回中"的姿态
			#   2) 方向来回旋转 ±45°：头 1 秒左跨、中 1 秒正前推进、尾 1 秒右跨
			#      整体视觉是一个明显的 S 型 jink，不再只是原地压杆
			#   3) 基向量 sin 分量加在侧方、cos 分量加在前方：保证飞机不会只侧
			#      移而没有前进，始终沿航向往前"挪"
			if aircraft.flock_scatter_timer > 0.0:
				aircraft.flock_scatter_timer = maxf(aircraft.flock_scatter_timer - delta, 0.0)
				var duration := Aircraft.FLOCK_SCATTER_DURATION
				var progress := clampf(1.0 - aircraft.flock_scatter_timer / duration, 0.0, 1.0)
				var ramp := sin(progress * PI)                        ## 0 → 1 → 0 的平滑包络
				var weave := sin(progress * TAU * FLOCK_WEAVE_CYCLE)                ## 完整 1.2 个周期的左右摆动
				var dir := aircraft.flock_scatter_dir                 ## 侧向单位向量（左/右随机）
				var fwd_axis := Vector2(sin(aircraft.heading), -cos(aircraft.heading))  ## 机头方向
				var lateral := dir * (ramp * weave * FLOCK_LATERAL_JINK)           ## 横向 jink（带来回）
				var forward := fwd_axis * (ramp * FLOCK_FORWARD_JINK)              ## 前冲分量（避免原地打转）
				final_wp = final_wp + lateral + forward
			aircraft.target_position = final_wp

		# 简单扫描：只有非 shield_leader 的普通 UAV 才会进入交战模式
		_scan_timer -= delta
		if _scan_timer <= 0.0 and enable_combat and not shield_leader:
			_scan_timer = 1.0 if orbit_squad_leader else 3.0
			_try_engage_simple()
		return

	# 交战：前置追踪
	# flat_altitude（生存模式）下忽略高度差
	var dist: float
	if aircraft.flat_altitude:
		dist = aircraft.global_position.distance_to(_current_target.global_position)
	else:
		dist = Aircraft.effective_distance_px(aircraft.global_position, aircraft.altitude, _current_target.global_position, _current_target.altitude)

	# ── 护驾系统（orbit_squad_leader 专用）──
	if EscortBehavior.is_active(self):
		var leader_pos := squad.leader.global_position
		var self_to_leader := aircraft.global_position.distance_to(leader_pos)
		var tgt_to_leader := _current_target.global_position.distance_to(leader_pos)
		if self_to_leader > ORBIT_TETHER_RADIUS or tgt_to_leader > ORBIT_TETHER_RADIUS:
			aircraft.clear_combat_target()
			aircraft.ai_override_pursuit = false
			_current_target = null
			_engage_timer = 0.0
			_simple_orbit_time = 0.0
			_simple_confused = false
			return

	# 超出范围或超时脱离（用有效雷达范围 → 高度档位影响 AI 缠斗持续半径）
	var max_range := (aircraft.effective_radar_range_px() * 1.5) if aircraft.params else 3000.0
	_engage_timer += delta
	if dist > max_range or _engage_timer > engage_duration:
		aircraft.clear_combat_target()
		aircraft.ai_override_pursuit = false
		_current_target = null
		_engage_timer = 0.0
		_simple_orbit_time = 0.0
		_simple_confused = false
		_simple_orbit_threshold = randf_range(SIMPLE_ORBIT_THRESH_MIN, SIMPLE_ORBIT_THRESH_MAX)
		return

	aircraft.set_combat_target(_current_target)
	aircraft.ai_override_pursuit = true

	# ── 护驾 UAV 跳过发呆机制（始终保持追踪） ──
	var _is_sentinel_escort := orbit_squad_leader and shield_leader

	if not _is_sentinel_escort:
		# ── 近距绕圈疲劳检测（非护驾 UAV 才用）──
		var close_threshold := ORBIT_CLOSE_DIST
		if dist < close_threshold:
			var to_tgt := (_current_target.global_position - aircraft.global_position).normalized()
			var my_fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
			var aot := absf(my_fwd.angle_to(to_tgt))
			if aot > deg_to_rad(ORBIT_FATIGUE_AOT):
				_simple_orbit_time += delta
			else:
				_simple_orbit_time = maxf(_simple_orbit_time - delta * 0.5, 0.0)
		else:
			_simple_orbit_time = maxf(_simple_orbit_time - delta * 2.0, 0.0)

		if not _simple_confused and _simple_orbit_time > _simple_orbit_threshold:
			_simple_confused = true
			_simple_confused_timer = randf_range(CONFUSED_TIMER_MIN, CONFUSED_TIMER_MAX)
			_simple_confused_heading = Vector2(sin(aircraft.heading), -cos(aircraft.heading))
			_simple_orbit_time = 0.0
			_simple_orbit_threshold = randf_range(SIMPLE_ORBIT_THRESH_MIN, SIMPLE_ORBIT_THRESH_MAX)

		if _simple_confused:
			_simple_confused_timer -= delta
			if _simple_confused_timer <= 0.0:
				_simple_confused = false
				_simple_orbit_time = 0.0
				_simple_orbit_threshold = randf_range(SIMPLE_ORBIT_THRESH_MIN, SIMPLE_ORBIT_THRESH_MAX)
			else:
				aircraft.target_position = aircraft.global_position + _simple_confused_heading * CONFUSED_FLIGHT_DIST
				aircraft.target_altitude = aircraft.altitude
				aircraft.target_speed_kmh = aircraft.params.max_speed * CONFUSED_SPEED_RATIO if aircraft.params else 600.0
				return

	# 前置追踪（护驾 UAV 用更激进的预判系数）
	var tgt_fwd := Vector2(sin(_current_target.heading), -cos(_current_target.heading))
	var closing_speed := maxf(aircraft.speed + _current_target.speed, 1.0) * Aircraft.PIXELS_PER_METER
	var lead_time := dist / closing_speed
	var lead_factor := ESCORT_UAV_LEAD if _is_sentinel_escort else REGULAR_UAV_LEAD  # 护驾 UAV 100% 前置，普通 50%
	var lead_pos := _current_target.global_position + tgt_fwd * _current_target.speed * Aircraft.PIXELS_PER_METER * lead_time * lead_factor
	aircraft.target_position = lead_pos
	if aircraft.flat_altitude:
		aircraft.set_target_tier(_current_target.get_altitude_tier())
	else:
		aircraft.target_altitude = _current_target.altitude
	# 护驾 UAV 全速追击，普通 UAV 70% 速度
	aircraft.target_speed_kmh = aircraft.params.max_speed if _is_sentinel_escort else (aircraft.params.max_speed * REGULAR_UAV_SPEED_RATIO if aircraft.params else 800.0)

## shield_leader 专用：只攻击进入护驾范围的敌人
## shield_leader 专用：敌人进入光环范围（900px）时交战
const SHIELD_ENGAGE_RANGE := 1500.0   ## 护卫交战范围（像素，~3000m）——比光环范围更大
func _try_engage_in_tether_range() -> void:
	if not squad or not squad.leader or not is_instance_valid(squad.leader):
		return
	var leader_pos := squad.leader.global_position
	var best: CombatUnit = null
	var best_dist := SHIELD_ENGAGE_RANGE
	# 用共享列表代替 get_parent().get_children() (perf)
	for unit in CombatUnit.all_units:
		if unit and unit.team != aircraft.team and not unit.is_destroyed:
			var d: float = unit.global_position.distance_to(leader_pos)
			if d < best_dist:
				best_dist = d
				best = unit
	if best:
		_current_target = best
		_engage_timer = 0.0
		aircraft.orbit_speed_cap = 0.0  # 交战时解除轨道限速

func _try_engage_simple() -> void:
	var best: CombatUnit = null
	var best_dist := 99999.0
	# 用共享列表代替 get_parent().get_children()（后者在 ~200 节点场景里是主瓶颈）
	for unit in CombatUnit.all_units:
		# 列表是上一帧末尾建的，其间可能有单位被 queue_free，先保护性过滤
		if not is_instance_valid(unit):
			continue
		if unit.team == aircraft.team or unit.is_destroyed:
			continue
		# 对地专用机型：跳过所有空中目标（飞机/UAV）
		if ground_combat_only and not (unit is GroundUnit):
			continue
		var d := aircraft.global_position.distance_to(unit.global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	var detect_range := (aircraft.effective_radar_range_px() * 1.2) if aircraft.params else 2500.0
	# 低空 / 云中目标更难被发现 —— 连续插值，无 tier 跳变
	#   贴地    → detect_range × 0.80
	#   3500m+ → detect_range × 1.00
	#   云心    → detect_range × 0.65
	#   取较强抑制（min），与 target_selection 视觉遮蔽逻辑对齐
	if best:
		var alt_obscure := 1.0 - smoothstep(0.0, 3500.0, best.altitude)
		var alt_mult := lerpf(1.0, 0.80, alt_obscure)
		var cloud_mult: float = 1.0
		if best is Aircraft:
			cloud_mult = lerpf(1.0, 0.65, (best as Aircraft).cloud_density)
		detect_range *= minf(alt_mult, cloud_mult)

	# ── 护驾过滤（orbit_squad_leader 专用）──
	# 只攻击进入长机护驾范围内的目标，远处的敌人不管
	if best and EscortBehavior.is_active(self):
		var tgt_to_leader := best.global_position.distance_to(squad.leader.global_position)
		if tgt_to_leader > ORBIT_TETHER_RADIUS:
			return  # 目标不在护驾范围内，不交战

	if best and best_dist < detect_range:
		_current_target = best
		_engage_timer = 0.0

# ══════════════════════════════════════════════
#  PATROL — 巡逻（保持原有逻辑）
# ══════════════════════════════════════════════

func _process_patrol(delta: float) -> void:
	aircraft.keep_target_on_arrival = false
	if waypoints.is_empty():
		return
	# 守卫：waypoints 可能被外部代码重置成更短数组（如 ace_squad / commander_aura），
	# 而 current_waypoint_index 仍指向旧 size。每次访问前 wrap 一下避免 out-of-bounds。
	if current_waypoint_index >= waypoints.size():
		current_waypoint_index = 0

	var target_wp := waypoints[current_waypoint_index]
	var dist := aircraft.global_position.distance_to(target_wp)

	if dist < arrival_distance:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		_set_next_waypoint()
	else:
		aircraft.target_position = target_wp

	if evade_missiles and personality.missile_aware and not is_boss_attacker():
		MissileEvasion.enter_evade(self)
		return

	if not enable_combat:
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = lerpf(3.0, 1.0, aggression)
		TargetSelection.try_engage(self)

# ══════════════════════════════════════════════
#  SQUAD_FOLLOW — 编队跟随 + 掩护长机（已提取到 ai/squad_coordination.gd）
# ══════════════════════════════════════════════

## 检查该目标是否已被队内其他僚机/长机作为 combat_target
## 用来避免"全员冲同一个目标"的抱团浪费
func _is_target_already_squad_engaged(target: Aircraft) -> bool:
	if not squad:
		return false
	for member in squad.members:
		if not is_instance_valid(member) or member == aircraft:
			continue
		if member.combat_target == target:
			return true
	return false

# ══════════════════════════════════════════════
#  ENGAGE — 交战（战术机动决策树）
# ══════════════════════════════════════════════

func _process_engage(delta: float) -> void:
	_engage_timer += delta
	_tactic_timer += delta
	_target_eval_timer += delta

	# ── Drone 直冲式攻击（loyal_wingman 专用）──
	# 用 kamikaze_intercept 标识识别 drone：跳过 BFM 决策树（不需 yo-yo / scissors / lag pursuit），
	# 直冲玩家锁定的目标 + 全速 + 微 lead，进 gun_range 自动开火。目标死/丢自动回编队。
	if kamikaze_intercept:
		if not _current_target or not is_instance_valid(_current_target) or _current_target.is_destroyed:
			TargetSelection.disengage(self)
			return
		_process_drone_engage(delta)
		return

	# ── Herbst J-Turn 反咬触发（独立于 bvr_only）──
	# 任何挂载 HerbstManeuver 模块的飞机被近距追击时尝试触发，与 BVR 撤退解耦
	# F-14 Poltergeist：有 Herbst 模块、bvr_only=false → 触发 J-Turn 反杀
	# F-47：无 Herbst 模块（已转移到 F-14）→ 不触发，纯 BVR 撤退 + 隐身
	var hm: HerbstManeuver = aircraft.get_herbst()
	if hm and _current_target and is_instance_valid(_current_target):
		var to_enemy_h := (_current_target.global_position - aircraft.global_position).normalized()
		var my_fwd_h := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
		var is_chased_h := my_fwd_h.dot(to_enemy_h) < BEING_CHASED_DOT
		var dist_h := aircraft.global_position.distance_to(_current_target.global_position)
		if is_chased_h and dist_h < HERBST_ACTIVATION_DIST and hm.can_activate \
				and aircraft.altitude >= HERBST_MIN_ALTITUDE_M:
			var cross_h := my_fwd_h.x * to_enemy_h.y - my_fwd_h.y * to_enemy_h.x
			hm.activate(cross_h)
			EventLogger.log_event("AI_TACTIC", _log_name(), "Herbst J-Turn triggered (chased at %.0fpx)" % dist_h)
			return

	# ── BVR 狙击模式：太近强制脱离 ──
	if bvr_only and _current_target and is_instance_valid(_current_target):
		# Herbst 反击窗口中 → 暂停 bvr_only 逃跑，像近距狗斗机一样攻击
		if hm and hm.counterattack_timer > 0.0:
			pass  # 跳过 bvr_only 距离检查，继续走正常交战逻辑
		else:
			var bvr_dist := aircraft.global_position.distance_to(_current_target.global_position)
			var standoff_min: float = BVR_STANDOFF_MIN
			if bvr_standoff_min_px_override > 0.0:
				standoff_min = bvr_standoff_min_px_override
			var flee_dist: float = BVR_FLEE_DISTANCE
			if bvr_flee_distance_px_override > 0.0:
				flee_dist = bvr_flee_distance_px_override
			if bvr_dist < standoff_min:
				var flee_dir := (aircraft.global_position - _current_target.global_position).normalized()
				aircraft.target_position = aircraft.global_position + flee_dir * flee_dist
				TargetSelection.disengage(self)
				return

	# 累积防御态势时间
	if _tactic in [EngageTactic.BREAK_TURN, EngageTactic.EXTENSION, EngageTactic.SCISSORS]:
		_defensive_time += delta
	else:
		_defensive_time = maxf(_defensive_time - delta * 0.5, 0.0)

	# ── 战术机动防御：敌机从后方用机炮攻击时触发 ──
	var _me := aircraft.get_maneuver()
	if _me and not _me.is_used and not _me.is_active:
		if _current_target and is_instance_valid(_current_target) and _current_target is Aircraft:
			var enemy: Aircraft = _current_target
			if enemy.is_firing:
				var to_me := (aircraft.global_position - enemy.global_position).normalized()
				var my_fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
				if my_fwd.dot(to_me) > GUN_ATTACK_DOT and enemy.global_position.distance_to(aircraft.global_position) < GUN_ATTACK_THREAT_DIST:
					TargetSelection.disengage(self)
					MissileEvasion.enter_evade(self)
					_me.activate()
					var fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
					aircraft.target_position = aircraft.global_position + fwd * EVASION_TARGET_DIST
					return

	# ── 导弹规避（需要飞行员察觉 + 受 self_preservation 影响） ──
	# BOSS 攻击手不做导弹规避——他们有热诱弹和隐形防御，任务是死追玩家
	if evade_missiles and personality.missile_aware and not is_boss_attacker():
		# 低自保飞行员可能忽略来袭导弹继续攻击
		var evade_chance := lerpf(0.3, 1.0, _effective_self_preservation())
		if randf() < evade_chance or _state != AIState.ENGAGE:
			TargetSelection.disengage(self)
			MissileEvasion.enter_evade(self)
			return

	# ── 被锁定警觉（需要飞行员意识到 + 高自保飞行员主动脱离） ──
	var _esp := _effective_self_preservation()
	if personality.lock_aware and _esp > 0.7:
		# 高自保 + 意识到被锁定 → 如果不在防御战术中，立即切防御
		if _tactic not in [EngageTactic.BREAK_TURN, EngageTactic.EXTENSION, EngageTactic.SCISSORS]:
			var defense_chance := (_esp - 0.5) * LOCK_AWARE_DEFENSE_MULT
			if randf() < defense_chance:
				_tactic_timer = _tactic_min_duration  # 强制允许战术切换

	# 目标有效性检查
	if not _current_target or not is_instance_valid(_current_target) or _current_target.is_destroyed:
		TargetSelection.disengage(self)
		return

	# 编队僚机：长机取消目标时僚机也脱离（带宽限防止单帧抖动）
	# ⚠ 只对"协同攻击长机目标"(_squad_attacking_leader_target) 生效！
	# 独立自由交战(_squad_free_engaging) 下，僚机是自主找的目标，
	# 和长机是否锁定目标完全无关——不能用这个 check 把它们踢出来，
	# 否则会出现"SQUAD FREE engage → 恰好 1.5s 后 DISENGAGE"的 bug
	# （因为 FREE 扫描本身就是在 leader.combat_target == null 时才触发的，
	#  这个 check 第一帧就开始累积，1.5 秒后必定触发 disengage）。
	if _squad_attacking_leader_target and squad and squad.leader and is_instance_valid(squad.leader):
		if not squad.leader.combat_target:
			_leader_target_lost_timer += delta
			if _leader_target_lost_timer >= LEADER_TARGET_LOST_GRACE:
				_leader_target_lost_timer = 0.0
				TargetSelection.disengage(self)
				return
		else:
			_leader_target_lost_timer = 0.0

	# 超出范围脱离（小队指令的交战都带宽限：允许短暂越界，给飞机调整位置的时间）
	# BOSS 攻击手永不因距离脱离——死追目标
	# flat_altitude=true（生存模式）下距离判定忽略高度差
	if is_boss_attacker():
		pass  # BOSS 攻击手跳过距离脱离
	elif aircraft.params:
		var max_range := aircraft.effective_radar_range_px() * 1.5
		var dist: float
		if aircraft.flat_altitude:
			dist = aircraft.global_position.distance_to(_current_target.global_position)
		else:
			dist = Aircraft.effective_distance_px(aircraft.global_position, aircraft.altitude, _current_target.global_position, _current_target.altitude)
		if dist > max_range:
			if _squad_attacking_leader_target or _squad_free_engaging:
				_squad_range_grace_timer += delta
				if _squad_range_grace_timer >= SQUAD_RANGE_GRACE:
					_squad_range_grace_timer = 0.0
					TargetSelection.disengage(self)
					return
			else:
				TargetSelection.disengage(self)
				return
		else:
			_squad_range_grace_timer = 0.0

	# 交战时间限制（BOSS 攻击手无限制）
	if not is_boss_attacker() and _engage_timer > engage_duration:
		TargetSelection.disengage(self)
		return

	# ── 交战中目标重评估（受 focus 影响） ──
	var eval_interval := lerpf(TARGET_EVAL_INTERVAL_MIN, TARGET_EVAL_INTERVAL_MAX, focus)  # 低专注=3秒重评，高专注=10秒
	if _target_eval_timer >= eval_interval:
		_target_eval_timer = 0.0
		TargetSelection.reevaluate_target(self)

	# ── 态势评估 ──
	# P4：planner 模式下整段 BFMTactics 链都跳过（assess_situation / lufberry / choose / execute / gun_jink）
	# 这些原本是为旧 BFMTactics.execute_* 服务，planner 接管后全是死代码 —— 省去每帧 SituationData 构造 + 战术选择 + jink 偏移计算
	if aircraft.use_tactical_planner:
		aircraft.ai_override_pursuit = false  # 让 planner 自由控制 target_position
		# HUD 战术显示：planner 飞机用 plan 的 intent 名（玩家飞机自己更新；AI 飞机用 _last_plan）
		if aircraft._last_plan:
			current_tactic_name = TacticalPlan.intent_name(aircraft._last_plan.intent)
		return

	# ── 旧 BFMTactics 路径（沙盒模式 / 未迁移机型）──
	var sit := BFMTactics.assess_situation(self)

	# ── 交战中默认目标高度：使用自身作战高度（patrol_altitude clamp 到目标 ±2500m），
	# 各战术执行器需要时会覆写为 match_target_altitude（机炮战）──
	if absf(sit.alt_diff) > ALTITUDE_MATCH_THRESH:
		BFMTactics.use_combat_altitude(self)

	# ── 拉弗伯雷圆圈检测（每帧更新，不受战术切换防抖限制） ──
	BFMTactics.update_lufberry_detection(self, sit, delta)

	# ── 战术选择（带最小持续时间防抖） ──
	if _tactic_timer >= _tactic_min_duration:
		BFMTactics.choose_tactic(self, sit)

	# ── 执行当前战术 ──
	aircraft.ai_override_pursuit = true
	match _tactic:
		EngageTactic.LEAD_PURSUIT:
			BFMTactics.execute_lead_pursuit(self, sit)
		EngageTactic.LAG_PURSUIT:
			BFMTactics.execute_lag_pursuit(self, sit)
		EngageTactic.LEAD_TURN:
			BFMTactics.execute_lead_turn(self, sit)
		EngageTactic.HIGH_YOYO:
			BFMTactics.execute_high_yoyo(self, sit, delta)
		EngageTactic.LOW_YOYO:
			BFMTactics.execute_low_yoyo(self, sit, delta)
		EngageTactic.BREAK_TURN:
			BFMTactics.execute_break_turn(self, sit)
		EngageTactic.EXTENSION:
			BFMTactics.execute_extension(self, sit)
		EngageTactic.SCISSORS:
			BFMTactics.execute_scissors(self, sit, delta)
		EngageTactic.SNIPER_HOLD:
			BFMTactics.execute_sniper_hold(self, sit)

	# ── 机炮闪避（斗士型：被追尾射击时叠加蛇形偏移） ──
	BFMTactics.update_gun_jink(self, sit, delta)

	# 更新战术名称（附带压力和技能信息）
	current_tactic_name = EngageTactic.keys()[_tactic]

# ══════════════════════════════════════════════
#  Drone 直冲式 engage（loyal_wingman 专用，跳过 BFM 决策）
# ══════════════════════════════════════════════

## 简单直冲：朝目标位置 + 半秒 lead 飞，全速，机炮自动开火
## 目标死/超距由 _process_engage 入口的有效性检查 + TargetSelection.disengage 处理
func _process_drone_engage(delta: float) -> void:
	var tgt := _current_target
	# 目标 lead：以自身闭合时间为预测窗口（BFM lead pursuit 的简化版本）
	var to_tgt := tgt.global_position - aircraft.global_position
	var dist_px := to_tgt.length()
	var my_speed_px := maxf(aircraft.speed * Aircraft.PIXELS_PER_METER, 1.0)
	var t_to_target := minf(dist_px / my_speed_px, 1.5)  # 上限 1.5s 防过冲
	var tgt_fwd := Vector2(sin(tgt.heading), -cos(tgt.heading))
	var tgt_speed_px := tgt.speed * Aircraft.PIXELS_PER_METER
	var lead_pos := tgt.global_position + tgt_fwd * tgt_speed_px * t_to_target * 0.6

	aircraft.target_position = lead_pos
	aircraft.ai_override_pursuit = true

	# 全速冲（drone 没有加力，max_speed 1800 km/h 已经够快）
	if aircraft.params:
		aircraft.target_speed_kmh = aircraft.params.max_speed

	# 高度匹配目标（生存模式 flat_altitude → 用 tier）
	if aircraft.flat_altitude:
		aircraft.set_target_tier(tgt.get_altitude_tier())
	else:
		aircraft.target_altitude = tgt.altitude

	current_tactic_name = "TACTIC_DRONE_STRIKE"

# ══════════════════════════════════════════════
#  态势评估
# ══════════════════════════════════════════════

class SituationData:
	var dist_px: float          ## 距离（像素）
	var aspect_angle: float     ## 我在敌机的偏置角（0=正后方, PI=正前方）
	var my_aot: float           ## 敌机在我的攻击角（0=正前方, PI=正后方）
	var closing_rate: float     ## 闭合率（正=接近）
	var my_speed: float         ## 我的速度 m/s
	var tgt_speed: float        ## 敌机速度 m/s
	var speed_ratio: float      ## 速度比 我/敌
	var alt_diff: float         ## 高度差（正=我更高）
	var in_rear_hemi: bool      ## 我在敌机后半球
	var enemy_in_my_rear: bool  ## 敌机在我的后半球
	var tgt_pos: Vector2
	var tgt_fwd: Vector2
	var my_pos: Vector2
	var my_fwd: Vector2
	var to_target: Vector2      ## 归一化方向
	var gun_range_px: float
	var is_head_on: bool        ## 迎头接近

# ══════════════════════════════════════════════
#  EVADE_MISSILE — 导弹规避
# ══════════════════════════════════════════════

# process_evade / enter_evade / exit_evade 已提取到 scripts/ai/missile_evasion.gd
# 调用方式：MissileEvasion.process_evade(self, delta) / .enter_evade(self) / .exit_evade(self)

# ══════════════════════════════════════════════
#  交战管理
# ══════════════════════════════════════════════

# try_engage / reevaluate_target / disengage 已提取到 scripts/ai/target_selection.gd
# 调用方式：TargetSelection.try_engage(self) / .reevaluate_target(self) / .disengage(self)

# ══════════════════════════════════════════════
#  导弹威胁检测
# ══════════════════════════════════════════════

# check_incoming_missile / find_nearest_incoming_missile / is_missile_from_rear
# 已提取到 scripts/ai/missile_evasion.gd
# 调用方式：MissileEvasion.check_incoming_missile(self) 等

func _get_missile_manager() -> MissileManager:
	var root := aircraft.get_parent()
	if not root:
		return null
	for child in root.get_children():
		if child is MissileManager:
			return child
	return null

# ══════════════════════════════════════════════
#  导弹拦截（shield_leader 模式）
# ══════════════════════════════════════════════


## 从 Aircraft 子节点找到其 AIController
func _find_member_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

# ══════════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════════

func _set_next_waypoint() -> void:
	if waypoints.is_empty():
		return
	if current_waypoint_index >= waypoints.size():
		current_waypoint_index = 0
	aircraft.target_position = waypoints[current_waypoint_index]

func _generate_default_waypoints() -> void:
	var center := aircraft.global_position if aircraft else Vector2.ZERO
	var radius := 500.0
	waypoints = PackedVector2Array([
		center + Vector2(radius, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius),
		center + Vector2(-radius, -radius),
	])

static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI

# ── kamikaze 拦截：忠诚僚机 drone 专用 ──
## 扫描 missile_manager 找瞄向 squad.leader 的来袭导弹；
## 选最近一枚、距离 ≤ KAMIKAZE_INTERCEPT_RANGE_PX 的 → break formation，飞过去撞毁
## 命中（距离 ≤ KAMIKAZE_DETONATE_DIST_PX）→ ExplosionVFX + 双双 free
## 返回 true 表示本帧已 override（调用者跳过常规 AI 路由）
func _try_kamikaze_intercept(_delta: float) -> bool:
	if squad == null or squad.leader == null or not is_instance_valid(squad.leader) or squad.leader.is_destroyed:
		return false
	var mm: Node = aircraft.missile_manager
	if mm == null or not is_instance_valid(mm):
		return false
	var leader_pos: Vector2 = squad.leader.global_position
	var threat: Missile = null
	var best_dist: float = INF
	for child in mm.get_children():
		if not (child is Missile):
			continue
		var m: Missile = child
		if not m.is_active or m.is_flare_jammed:
			continue
		if m.team == aircraft.team:
			continue
		# 只拦瞄向 leader 的（target == leader 或航向指向 leader）
		var msl_to_leader: Vector2 = leader_pos - m.global_position
		var dist_to_leader: float = msl_to_leader.length()
		if dist_to_leader > MISSILE_THREAT_RANGE:
			continue
		var msl_fwd: Vector2 = Vector2(sin(m.heading), -cos(m.heading))
		if msl_fwd.dot(msl_to_leader.normalized()) < MISSILE_HEADING_DOT:
			continue
		# 选 drone 自己最容易拦到的（距离 drone 最近的那一枚）
		var dist_to_self: float = aircraft.global_position.distance_to(m.global_position)
		if dist_to_self < best_dist:
			best_dist = dist_to_self
			threat = m
	if threat == null:
		return false
	# 太远来不及拦：让常规 AI 接管（drone 还会绕在玩家身边）
	if best_dist > KAMIKAZE_INTERCEPT_RANGE_PX:
		return false

	# break formation，全速朝导弹冲
	aircraft.clear_formation()
	aircraft.target_position = threat.global_position
	aircraft.ai_override_pursuit = true
	if aircraft.params:
		aircraft.target_speed_kmh = aircraft.params.max_speed
	aircraft.orbit_speed_cap = 0.0  # 解除 orbit 限速

	# 进入引爆距离 → 同归于尽
	if best_dist <= KAMIKAZE_DETONATE_DIST_PX:
		current_tactic_name = "TACTIC_KAMIKAZE"
		aircraft.show_tactic_popup("KAMIKAZE")
		# AOE 视觉指示（与 shield_leader 同款）
		var msl_mgr: MissileManager = mm as MissileManager
		if msl_mgr:
			msl_mgr._aoe_zones.append({
				"pos": aircraft.global_position,
				"altitude": aircraft.altitude,
				"radius_px": 50.0,
				"time_left": 1.0,
				"max_time": 1.0,
				"damage": 0.0,
				"team": aircraft.team,
				"hit_set": { aircraft.get_instance_id(): true },
			})
			msl_mgr.queue_redraw()
		# 销毁导弹
		threat.is_active = false
		threat.queue_free()
		# drone 自毁
		aircraft.take_damage(9999.0, null, "collision")
		EventLogger.log_event("KAMIKAZE", aircraft.callsign,
			"drone intercepted missile (dist=%.0f)" % best_dist)
	return true


# ── 协同齐射系统（F-47 小队战术） — 已提取到 ai/squad_coordination.gd ──
