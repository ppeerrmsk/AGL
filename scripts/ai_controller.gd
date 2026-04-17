class_name AIController
extends Node

## AI 控制器：巡逻 / 交战（战术机动） / 导弹规避 状态机
## 交战时基于 Shaw《Fighter Combat》BFM 决策树选择战术机动

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
@export var bvr_only: bool = false            ## BVR 狙击模式：只用导弹，不进近距战，被接近则撤退
var boss_attacker: bool = false               ## BOSS 攻击手：禁止 EXTENSION/脱离/自保，死追玩家

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
@export var orbit_squad_leader: bool = false  ## simple_ai 专用：巡逻时围绕长机旋转（指挥 UAV 招募的僚机用）
@export var shield_leader: bool = false       ## orbit 专用：主动飞入来袭导弹路径保护长机

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
var _squad_attacking_leader_target: bool = false  ## 正在协同攻击长机指定的目标
var _squad_free_engaging: bool = false  ## 正在自由交战模式下独立交战（同样享有 range grace）
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

# ── 编队反应 ──
const FORMATION_SWITCH_THRESH := 30.0      ## 阵型偏移变化触发阈值（像素）
const FORMATION_REACT_BASE := 0.3          ## 阵型反应延迟基准（秒）
const FORMATION_JITTER_AMP := 0.5          ## 阵型扰动振幅
const FORMATION_JITTER_ADD := 1.0          ## 阵型扰动附加延迟（秒）
const WINGMAN_ENGAGE_DELAY_MIN := 0.3      ## 僚机交战反应延迟下限（秒）
const WINGMAN_ENGAGE_DELAY_MAX := 1.5      ## 僚机交战反应延迟上限（秒）

# ── 自由扫描 ──
const SQUAD_FREE_SCAN_RANGE := 2000.0      ## 僚机自由扫描范围（像素）
const SQUAD_FREE_MIN_DIST := 80.0          ## 自由扫描最小距离（防目标残骸）
const SQUAD_SCAN_RADAR_MULT := 1.3         ## 自由扫描雷达范围倍率

# ── BFM 决策阈值 ──
const BEING_CHASED_DOT := -0.3             ## 被追判定点积阈值
const HERBST_ACTIVATION_DIST := 1500.0     ## 赫尔贝特轮触发距离（像素）
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
	if waypoints.is_empty():
		_generate_default_waypoints()
	if aircraft:
		if aircraft.flat_altitude:
			aircraft.set_target_tier(aircraft.target_altitude_tier)
		else:
			aircraft.target_altitude = patrol_altitude
		_set_next_waypoint()
	_scan_timer = randf_range(1.0, 3.0)

## 获取日志用名称
func _log_name() -> String:
	if not aircraft:
		return "???"
	var side := "Friend" if aircraft.team == 0 else "Enemy"
	var dn: String = aircraft.params.display_name if aircraft.params else "???"
	return "%s/%s[%s]" % [side, dn, aircraft.callsign]

## 获取目标日志名称
func _log_target_name(target: CombatUnit) -> String:
	if not target or not is_instance_valid(target):
		return "None"
	if target is Aircraft:
		var ac: Aircraft = target
		var side := "Friend" if ac.team == 0 else "Enemy"
		var dn: String = ac.params.display_name if ac.params else "???"
		return "%s/%s[%s]" % [side, dn, ac.callsign]
	return target.callsign if target.callsign != "" else target.name

func _physics_process(delta: float) -> void:
	if not aircraft or aircraft.is_destroyed:
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

	match _state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.EVADE_MISSILE:
			_process_evade(delta)
		AIState.SQUAD_FOLLOW:
			_process_squad_follow(delta)

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
	return personality.apply_position_error(pos, is_boss_attacker())

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
#  SIMPLE AI — 轻量化逻辑（UAV 等低级敌人）
#  跳过压力/SA/BFM 决策树，只做巡逻+直线追踪
# ══════════════════════════════════════════════

func _process_simple(delta: float) -> void:
	aircraft.keep_target_on_arrival = false

	# ── 护驾长机失效检测（Sentinel 被击坠）──
	# 一旦长机不再有效，立即清除 orbit flag 和 squad 引用，回退为独立 simple AI
	# survivor_mode._update_enemy_waypoints 会在 8 秒内为其补充新航点
	if orbit_squad_leader:
		if not squad or not squad.leader or not is_instance_valid(squad.leader) or squad.leader.is_destroyed:
			orbit_squad_leader = false
			shield_leader = false  # 长机阵亡，恢复为普通 simple AI
			aircraft.orbit_speed_cap = 0.0  # 解除限速
			aircraft.ai_override_pursuit = false
			# 立即撤除 Sentinel 光环 buff（不等 queue_free）
			if aircraft.has_meta("commander_buff_originals"):
				var originals: Dictionary = aircraft.get_meta("commander_buff_originals")
				aggression = originals.get("aggression", aggression)
				if aircraft.params:
					aircraft.params.roll_rate = originals.get("roll_rate", aircraft.params.roll_rate)
					aircraft.params.max_g = originals.get("max_g", aircraft.params.max_g)
					aircraft.params.max_g_structural = originals.get("max_g_structural", aircraft.params.max_g_structural)
					aircraft.params.max_speed = originals.get("max_speed", aircraft.params.max_speed)
					aircraft.params.cruise_speed = originals.get("cruise_speed", aircraft.params.cruise_speed)
					aircraft.params.acceleration = originals.get("acceleration", aircraft.params.acceleration)
					aircraft.params.stall_speed_base = originals.get("stall_speed_base", aircraft.params.stall_speed_base)
				aircraft.remove_meta("commander_buff_originals")
				aircraft.remove_meta("commander_buffed_by")
			squad = null
			squad_index = -1

	# ── 护盾系统（shield_leader 模式，优先级高于一切）──
	# 只在导弹来袭时介入，平时正常轨道飞行
	if shield_leader and orbit_squad_leader and squad and squad.leader \
			and is_instance_valid(squad.leader) and not squad.leader.is_destroyed:
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
				aircraft.take_damage(_shield_missile.params.damage if _shield_missile.params else 80.0)
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
		if orbit_squad_leader and squad and squad.leader and is_instance_valid(squad.leader) \
				and squad.leader != aircraft and not squad.leader.is_destroyed:
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
			if shield_leader and enable_combat:
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
						for child in leader.get_parent().get_children():
							if child is CombatUnit and child.team != aircraft.team and not child.is_destroyed:
								var d: float = child.global_position.distance_to(aircraft.global_position)
								if d < best_edist:
									best_edist = d
									best_enemy = child
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
							_current_target.take_damage(dmg)
							EventLogger.log_event("KAMIKAZE", aircraft.callsign,
								"self-destruct hit %s (dmg=%.0f)" % [_current_target.callsign, dmg])
							# UAV 自毁
							aircraft.take_damage(9999.0)
							_current_target = null
							return
						return  # 自爆机不走后续轨道逻辑
			return

		elif not waypoints.is_empty():
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
	if orbit_squad_leader and squad and squad.leader and is_instance_valid(squad.leader) \
			and not squad.leader.is_destroyed:
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

	# 超出范围或超时脱离
	var max_range := (aircraft.params.radar_range * 1.5) if aircraft.params else 3000.0
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
	for child in aircraft.get_parent().get_children():
		if child is CombatUnit and child.team != aircraft.team and not child.is_destroyed:
			var d: float = child.global_position.distance_to(leader_pos)
			if d < best_dist:
				best_dist = d
				best = child
	if best:
		_current_target = best
		_engage_timer = 0.0
		aircraft.orbit_speed_cap = 0.0  # 交战时解除轨道限速

func _try_engage_simple() -> void:
	var best: CombatUnit = null
	var best_dist := 99999.0
	for child in aircraft.get_parent().get_children():
		if child is CombatUnit and child.team != aircraft.team and not child.is_destroyed:
			# 对地专用机型：跳过所有空中目标（飞机/UAV）
			if ground_combat_only and not (child is GroundUnit):
				continue
			var d := aircraft.global_position.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	var detect_range := (aircraft.params.radar_range * 1.2) if aircraft.params else 2500.0
	# 低空目标更难被发现
	if best:
		var tgt_tier := best.get_altitude_tier()
		if tgt_tier == CombatUnit.AltitudeTier.LOW:
			detect_range *= 0.75
		elif tgt_tier == CombatUnit.AltitudeTier.GROUND:
			detect_range *= 0.6

	# ── 护驾过滤（orbit_squad_leader 专用）──
	# 只攻击进入长机护驾范围内的目标，远处的敌人不管
	if orbit_squad_leader and squad and squad.leader and is_instance_valid(squad.leader) \
			and not squad.leader.is_destroyed and best:
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

	var target_wp := waypoints[current_waypoint_index]
	var dist := aircraft.global_position.distance_to(target_wp)

	if dist < arrival_distance:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		_set_next_waypoint()
	else:
		aircraft.target_position = target_wp

	if evade_missiles and personality.missile_aware and not is_boss_attacker():
		_enter_evade()
		return

	if not enable_combat:
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = lerpf(3.0, 1.0, aggression)
		_try_engage()

# ══════════════════════════════════════════════
#  SQUAD_FOLLOW — 编队跟随 + 掩护长机
# ══════════════════════════════════════════════

func _process_squad_follow(delta: float) -> void:
	if not squad or not squad.leader or not is_instance_valid(squad.leader) or squad.leader.is_destroyed:
		# 编队无效，回退到巡逻
		_state = AIState.PATROL
		squad = null
		aircraft.formation_mode = false
		aircraft._formation_leader = null
		return

	var leader := squad.leader

	# 安全网：若自己就是长机（例如中途原长机阵亡自动晋升）
	# 不能进入跟随分支，否则 get_wingman_target(squad_index≠0) 会算出
	# 一个相对于自身旋转的槽位，飞机陷入追自己尾巴的原地自转死循环
	if leader == aircraft:
		squad_index = 0
		aircraft.formation_mode = false
		aircraft._formation_leader = null
		_formation_blend = 0.0
		_rejoining = false
		_state = AIState.PATROL
		_set_patrol_altitude()
		_set_next_waypoint()
		return

	# ── 导弹规避优先（BOSS 攻击手跳过） ──
	if evade_missiles and personality.missile_aware and not is_boss_attacker():
		_enter_evade()
		return

	# ── 正常编队跟随 ──
	# 防御性清除：确保编队中无残留战斗目标干扰
	if aircraft.combat_target != null:
		aircraft.clear_combat_target()
		aircraft.ai_override_pursuit = false
	_cover_target = null
	aircraft.lod_level = 1  # 编队托管运算
	aircraft.keep_target_on_arrival = true
	aircraft.formation_mode = true
	aircraft._formation_leader = leader
	current_tactic_name = "TACTIC_FOLLOW_FORMATION"

	# 回归编队时渐变混合度（从自主飞行平滑过渡到完全托管）
	if _formation_blend < 1.0:
		_formation_blend = minf(_formation_blend + delta * 0.5, 1.0)  # ~2秒过渡
		current_tactic_name = "TACTIC_REJOIN"
	else:
		_rejoining = false  # 完全融入编队，结束归队状态
	aircraft._formation_blend = _formation_blend

	# 传递个体扰动相位
	aircraft._formation_jitter_phase = _formation_jitter_phase

	# 计算阵型槽位
	var slot_pos := squad.get_wingman_target(squad_index)

	# 检测阵型变换：对比相对长机本地坐标系的偏移
	# （消除长机移动/转向带来的影响，只检测阵型 offset 本身的变化）
	if slot_pos != Vector2.INF:
		var new_offset_local := (slot_pos - leader.global_position).rotated(-leader.heading)
		if _prev_formation_offset_local != Vector2.INF:
			var offset_change := _prev_formation_offset_local.distance_to(new_offset_local)
			if offset_change > FORMATION_SWITCH_THRESH:
				# 阵型切换了：设置个体化反应延迟（0.3~1.3秒）
				# 用个体扰动相位让每架飞机反应略有差异（风格一致）
				var base_delay := FORMATION_REACT_BASE + (sin(_formation_jitter_phase) * FORMATION_JITTER_AMP + 0.5) * FORMATION_JITTER_ADD
				_formation_react_timer = base_delay + randf_range(-0.15, 0.15)
		_prev_formation_offset_local = new_offset_local

	# 反应延迟期间：不更新 target_position（飞机继续向旧槽位飞行）
	# 延迟过后突然更新 slot_pos，会触发 aircraft 编队代码的中距追击分支 → 自然曲线转弯
	if _formation_react_timer > 0.0:
		_formation_react_timer -= delta
		current_tactic_name = "TACTIC_FORMATION_ADJUST"
	else:
		if slot_pos != Vector2.INF:
			aircraft.target_position = slot_pos

	# ── 自由模式：独立扫描附近敌机，优先级低于长机协同 ──
	# 长机无目标时才独立找目标；长机一旦锁定会走下面的协同攻击入口。
	# 跟随长机模式不做独立扫描。
	#
	# 注：这里用的是距离扫描（_scan_squad_nearby_enemy）而不是 _try_engage(雷达锥扫描)。
	# 原因：_try_engage 只能看到"雷达锥内 + 已经锁定 30% 以上"的敌机；玩家平飞飞过
	# 一架敌机时，该敌机会在僚机的雷达锥外或只短暂进入，永远达不到锁定门槛——
	# 结果就是"我明明飞过一架敌机，僚机一动不动"。
	# 距离扫描绕开雷达锥和锁定门槛，让僚机拥有真正的"小队态势感知"。
	if squad_engage_mode == SquadEngageMode.FREE and enable_combat \
			and (leader.combat_target == null or not is_instance_valid(leader.combat_target) or leader.combat_target.is_destroyed):
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = 1.0  # 每秒一次扫描，flyby 不容易漏
			if _cooldown_timer <= 0.0:
				var tgt := _scan_squad_nearby_enemy()
				if tgt:
					# 进 ENGAGE：与协同攻击走一样的过渡，只是 target 是自己找的
					_current_target = tgt
					aircraft.set_combat_target(tgt)
					aircraft.ai_override_pursuit = true
					aircraft.keep_target_on_arrival = false
					aircraft.formation_mode = false
					aircraft._formation_leader = null
					aircraft._formation_blend = 0.0
					_formation_blend = 0.0
					aircraft.lod_level = 0
					_state = AIState.ENGAGE
					_engage_timer = 0.0
					_tactic = EngageTactic.LEAD_PURSUIT
					_tactic_timer = 0.0
					_tactic_min_duration = MIN_DUR_LEAD_PURSUIT
					_squad_attacking_leader_target = false
					_squad_free_engaging = true  # 享有 range grace，避免刚进就被踢出
					_leader_target_lost_timer = 0.0
					_squad_range_grace_timer = 0.0
					current_tactic_name = "TACTIC_FREE_ENGAGE"
					EventLogger.log_event("AI_STATE", _log_name(),
						"SQUAD FREE engage → %s" % _log_target_name(tgt))
					return

	# 跟随长机的交战目标（长机锁定敌机时僚机协同攻击）
	# FREE / FOLLOW_LEADER 都进这里——这是"跟随长机打谁"的入口
	if leader.combat_target and is_instance_valid(leader.combat_target) and not leader.combat_target.is_destroyed:
		# 反应延迟：每架僚机有不同的反应时间（0.3~1.5秒）
		if _engage_delay <= 0.0:
			_engage_delay = randf_range(WINGMAN_ENGAGE_DELAY_MIN, WINGMAN_ENGAGE_DELAY_MAX)
		_engage_delay -= delta
		if _engage_delay <= 0.0:
			_engage_delay = 0.0
			aircraft.keep_target_on_arrival = false
			aircraft.formation_mode = false
			aircraft._formation_leader = null
			aircraft._formation_blend = 0.0
			_formation_blend = 0.0  # 下次回归编队时从0开始混合
			aircraft.set_combat_target(leader.combat_target)
			aircraft.lod_level = 0
			_state = AIState.ENGAGE
			_engage_timer = 0.0
			_tactic = EngageTactic.LEAD_PURSUIT
			_tactic_timer = 0.0
			_tactic_min_duration = MIN_DUR_LEAD_PURSUIT
			_current_target = leader.combat_target
			aircraft.ai_override_pursuit = true
			_squad_attacking_leader_target = true
			_squad_free_engaging = false  # 协同攻击路径互斥
			_leader_target_lost_timer = 0.0
			_squad_range_grace_timer = 0.0
			current_tactic_name = "TACTIC_TEAM_ATTACK"
	else:
		_engage_delay = 0.0  # 长机无目标时重置延迟

## 扫描长机后半球威胁
func _scan_leader_rear() -> Aircraft:
	if not squad or not squad.leader:
		return null
	var leader := squad.leader
	var leader_fwd := Vector2(sin(leader.heading), -cos(leader.heading))

	var best_threat: Aircraft = null
	var best_dist := COVER_SCAN_RANGE

	var root := aircraft.get_parent()
	if not root:
		return null

	for child in root.get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.team == aircraft.team or ac.is_destroyed:
			continue

		var to_enemy := ac.global_position - leader.global_position
		var dist := to_enemy.length()
		if dist > COVER_SCAN_RANGE or dist >= best_dist:
			continue

		# 检查是否在长机后半球（与长机航向的夹角 > 90°）
		var angle := leader_fwd.angle_to(to_enemy.normalized())
		if absf(angle) > PI * 0.5:
			best_dist = dist
			best_threat = ac

	return best_threat

## 小队自由交战：距离扫描最近的敌机（绕开雷达锥 + 锁定门槛）
## 设计理念：把"小队整体的感知"与"单机雷达"解耦——
## 即使敌机在僚机身后或侧面、没触发自身雷达锁定，只要在合理距离内就能被发现。
##
## 距离计算：
##   - flat_altitude=true（生存模式）：用 2D 距离，完全忽略高度差
##     —— 生存模式设计上是"任何高度都能到"，不应让高度差影响目标选择
##   - 否则（沙盒模式）：用 effective_distance_px 3D
func _scan_squad_nearby_enemy() -> Aircraft:
	var root := aircraft.get_parent()
	if not root:
		return null
	# max_range_px 必须严格小于 _process_engage 的脱战阈值 (radar_range * 1.5)。
	var max_range_px := SQUAD_FREE_SCAN_RANGE
	if aircraft.params:
		max_range_px = minf(max_range_px, aircraft.params.radar_range * SQUAD_SCAN_RADAR_MULT)
	var best: Aircraft = null
	var best_dist := max_range_px
	var use_2d := aircraft.flat_altitude  # 生存模式走 2D
	for child in root.get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.team == aircraft.team or ac.is_destroyed:
			continue
		var d: float
		if use_2d:
			d = aircraft.global_position.distance_to(ac.global_position)
		else:
			d = Aircraft.effective_distance_px(
				aircraft.global_position, aircraft.altitude,
				ac.global_position, ac.altitude
			)
		if d < SQUAD_FREE_MIN_DIST or d >= best_dist:
			continue
		# 不追刚被别的僚机盯上的目标：避免 3 架同时扑一个
		if _is_target_already_squad_engaged(ac):
			continue
		best_dist = d
		best = ac
	return best

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

## 结束掩护交战，回归编队
func _end_cover_engagement() -> void:
	_cover_target = null
	aircraft.clear_combat_target()
	aircraft.ai_override_pursuit = false
	aircraft.lod_level = 1
	current_tactic_name = "TACTIC_RETURN_FORMATION"

# ══════════════════════════════════════════════
#  ENGAGE — 交战（战术机动决策树）
# ══════════════════════════════════════════════

func _process_engage(delta: float) -> void:
	_engage_timer += delta
	_tactic_timer += delta
	_target_eval_timer += delta

	# ── BVR 狙击模式：太近则触发 Herbst 或强制脱离 ──
	if bvr_only and _current_target and is_instance_valid(_current_target):
		var hm: HerbstManeuver = aircraft.get_herbst()
		# Herbst 反击窗口中 → 暂停 bvr_only 逃跑，像近距狗斗机一样攻击
		if hm and hm.counterattack_timer > 0.0:
			pass  # 跳过 bvr_only 距离检查，继续走正常交战逻辑
		else:
			var bvr_dist := aircraft.global_position.distance_to(_current_target.global_position)
			if bvr_dist < BVR_STANDOFF_MIN:
				# 检查敌人是否在我的后半球（被追逐）
				var to_enemy := (_current_target.global_position - aircraft.global_position).normalized()
				var my_fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
				var is_chased := my_fwd.dot(to_enemy) < BEING_CHASED_DOT  # 敌人在我身后
				# 被追且距离很近 → 尝试 Herbst 急转反杀
				if is_chased and bvr_dist < HERBST_ACTIVATION_DIST:
					if hm and hm.can_activate:
						# 计算转弯方向：朝敌人侧面转
						var cross := my_fwd.x * to_enemy.y - my_fwd.y * to_enemy.x
						hm.activate(cross)
						EventLogger.log_event("AI_TACTIC", _log_name(), "Herbst J-Turn triggered (chased at %.0fpx)" % bvr_dist)
						return
				# Herbst 不可用或未被追 → 正常撤退
				var flee_dir := (aircraft.global_position - _current_target.global_position).normalized()
				aircraft.target_position = aircraft.global_position + flee_dir * BVR_FLEE_DISTANCE
				_disengage()
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
					_disengage()
					_enter_evade()
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
			_disengage()
			_enter_evade()
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
		_disengage()
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
				_disengage()
				return
		else:
			_leader_target_lost_timer = 0.0

	# 超出范围脱离（小队指令的交战都带宽限：允许短暂越界，给飞机调整位置的时间）
	# BOSS 攻击手永不因距离脱离——死追目标
	# flat_altitude=true（生存模式）下距离判定忽略高度差
	if is_boss_attacker():
		pass  # BOSS 攻击手跳过距离脱离
	elif aircraft.params:
		var max_range := aircraft.params.radar_range * 1.5
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
					_disengage()
					return
			else:
				_disengage()
				return
		else:
			_squad_range_grace_timer = 0.0

	# 交战时间限制（BOSS 攻击手无限制）
	if not is_boss_attacker() and _engage_timer > engage_duration:
		_disengage()
		return

	# ── 交战中目标重评估（受 focus 影响） ──
	var eval_interval := lerpf(TARGET_EVAL_INTERVAL_MIN, TARGET_EVAL_INTERVAL_MAX, focus)  # 低专注=3秒重评，高专注=10秒
	if _target_eval_timer >= eval_interval:
		_target_eval_timer = 0.0
		_reevaluate_target()

	# ── 态势评估 ──
	var sit := _assess_situation()

	# ── 交战中提前高度趋近：高度差过大时优先调整高度 ──
	if absf(sit.alt_diff) > ALTITUDE_MATCH_THRESH:
		_match_target_altitude()

	# ── 拉弗伯雷圆圈检测（每帧更新，不受战术切换防抖限制） ──
	_update_lufberry_detection(sit, delta)

	# ── 战术选择（带最小持续时间防抖） ──
	if _tactic_timer >= _tactic_min_duration:
		_choose_tactic(sit)

	# ── 执行当前战术 ──
	aircraft.ai_override_pursuit = true
	match _tactic:
		EngageTactic.LEAD_PURSUIT:
			_execute_lead_pursuit(sit)
		EngageTactic.LAG_PURSUIT:
			_execute_lag_pursuit(sit)
		EngageTactic.LEAD_TURN:
			_execute_lead_turn(sit)
		EngageTactic.HIGH_YOYO:
			_execute_high_yoyo(sit, delta)
		EngageTactic.LOW_YOYO:
			_execute_low_yoyo(sit, delta)
		EngageTactic.BREAK_TURN:
			_execute_break_turn(sit)
		EngageTactic.EXTENSION:
			_execute_extension(sit)
		EngageTactic.SCISSORS:
			_execute_scissors(sit, delta)

	# ── 机炮闪避（斗士型：被追尾射击时叠加蛇形偏移） ──
	_update_gun_jink(sit, delta)

	# 更新战术名称（附带压力和技能信息）
	current_tactic_name = EngageTactic.keys()[_tactic]

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

func _assess_situation() -> SituationData:
	var s := SituationData.new()
	s.my_pos = aircraft.global_position
	s.tgt_pos = _current_target.global_position
	# 扁平模式：纯2D距离（战斗不受高度限制）；否则含高度的有效距离
	if aircraft.flat_altitude:
		s.dist_px = s.my_pos.distance_to(s.tgt_pos)
	else:
		s.dist_px = Aircraft.effective_distance_px(s.my_pos, aircraft.altitude, s.tgt_pos, _current_target.altitude)
	s.to_target = (s.tgt_pos - s.my_pos).normalized()

	s.tgt_fwd = Vector2(sin(_current_target.heading), -cos(_current_target.heading))
	s.my_fwd = Vector2(sin(aircraft.heading), -cos(aircraft.heading))

	s.my_speed = aircraft.speed
	s.tgt_speed = _current_target.speed
	s.speed_ratio = s.my_speed / maxf(s.tgt_speed, 1.0)

	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	# 闭合率
	s.closing_rate = s.my_fwd.dot(s.to_target) * my_speed_px - s.tgt_fwd.dot(s.to_target) * tgt_speed_px

	# 我在敌机的偏置角（aspect angle）
	var to_me := (s.my_pos - s.tgt_pos).normalized()
	s.aspect_angle = acos(clampf(-s.tgt_fwd.dot(to_me), -1.0, 1.0))
	s.in_rear_hemi = s.aspect_angle < deg_to_rad(90.0)

	# 敌机在我的攻击角（AOT）
	var to_enemy := (s.tgt_pos - s.my_pos).normalized()
	s.my_aot = acos(clampf(s.my_fwd.dot(to_enemy), -1.0, 1.0))

	# 敌机是否在我的后半球
	s.enemy_in_my_rear = s.my_aot > deg_to_rad(90.0)

	# 高度差
	s.alt_diff = aircraft.altitude - _current_target.altitude

	# 机炮射程
	s.gun_range_px = 150.0
	if aircraft.params and aircraft.params.gun:
		s.gun_range_px = aircraft.params.gun.max_range * Aircraft.PIXELS_PER_METER

	# 迎头判定：双方都面朝对方（aspect > 120° 且 my_aot < 60°）
	s.is_head_on = s.aspect_angle > deg_to_rad(120.0) and s.my_aot < deg_to_rad(60.0) and s.closing_rate > 0

	return s

# ══════════════════════════════════════════════
#  拉弗伯雷圆圈（mutual orbit）检测与脱出
# ══════════════════════════════════════════════

## 每帧更新拉弗伯雷检测：双方近距互绕超时则强制切换战术脱出
func _update_lufberry_detection(s: SituationData, delta: float) -> void:
	if _lufberry_cooldown > 0.0:
		_lufberry_cooldown -= delta

	var close_range := s.gun_range_px * LUFBERRY_CLOSE_MULT
	# 条件：近距 + 双方都不在对方后半球 + 都有一定偏置角 → 互绕中
	if s.dist_px < close_range and not s.in_rear_hemi and not s.enemy_in_my_rear \
			and s.my_aot > deg_to_rad(30.0) and s.aspect_angle > deg_to_rad(30.0) \
			and _lufberry_cooldown <= 0.0:
		_lufberry_timer += delta
	else:
		_lufberry_timer = maxf(_lufberry_timer - delta * 2.0, 0.0)

	var lufberry_threshold := lerpf(LUFBERRY_THRESH_MIN, LUFBERRY_THRESH_MAX, 1.0 - _effective_skill())
	if _lufberry_timer > lufberry_threshold:
		_lufberry_timer = 0.0
		_lufberry_cooldown = LUFBERRY_COOLDOWN
		var new_tactic: EngageTactic
		if aggression > 0.5 or _effective_self_preservation() < 0.4:
			new_tactic = EngageTactic.HIGH_YOYO
		else:
			new_tactic = EngageTactic.EXTENSION
		if new_tactic != _tactic:
			_apply_new_tactic(new_tactic)

# ══════════════════════════════════════════════
#  战术选择决策树
# ══════════════════════════════════════════════

func _choose_tactic(s: SituationData) -> void:
	# ── BVR 狙击模式：只用 EXTENSION 或 LEAD_PURSUIT（远距），不选近距战术 ──
	# 反击窗口中则跳过此限制，允许近距战术
	var _hm_tactic: HerbstManeuver = aircraft.get_herbst()
	var in_counterattack := _hm_tactic and _hm_tactic.counterattack_timer > 0.0
	if bvr_only and not in_counterattack:
		if s.dist_px < s.gun_range_px * BVR_CLOSE_MULT:
			# 太近了，强制脱离
			if _tactic != EngageTactic.EXTENSION:
				_apply_new_tactic(EngageTactic.EXTENSION)
		else:
			# 远距保持 LEAD_PURSUIT（导弹追踪）
			if _tactic != EngageTactic.LEAD_PURSUIT:
				_apply_new_tactic(EngageTactic.LEAD_PURSUIT)
		return

	var new_tactic := _tactic
	var close_range := s.gun_range_px * TACTIC_CLOSE_MULT
	var mid_range := s.gun_range_px * TACTIC_MID_MULT
	var aggression_factor := aggression  # 0~1

	var esp := _effective_self_preservation()

	# ── 0. 高自保 + 意识到被锁定：即使没被咬尾也可能切防御 ──
	if personality.lock_aware and esp > 0.6 and not s.enemy_in_my_rear:
		if esp > 0.85:
			new_tactic = EngageTactic.EXTENSION
		elif esp > 0.7:
			new_tactic = EngageTactic.BREAK_TURN

	# ── 1. 被咬尾检测（需要态势感知"看到"后方威胁） ──
	# 如果飞行员没有意识到后方威胁，会继续当前战术（致命失误）
	elif s.enemy_in_my_rear and s.dist_px < mid_range and personality.rear_threat_aware:
		# 低自保飞行员被咬尾也可能反转迎头
		if esp < 0.3 and s.dist_px > close_range:
			new_tactic = EngageTactic.LEAD_TURN
		elif aircraft.hp < aircraft.params.max_hp * HEALTH_EXTEND_THRESH or s.speed_ratio < SPEED_EXTEND_THRESH:
			new_tactic = EngageTactic.EXTENSION
		elif _defensive_time > DEFENSIVE_COUNTER_TIME:
			if aggression_factor > AGGRESSION_COUNTER_THRESH and esp < 0.6:
				new_tactic = EngageTactic.LEAD_TURN
				_defensive_time = 0.0
			else:
				new_tactic = EngageTactic.EXTENSION
				_defensive_time = 0.0
		elif s.dist_px < close_range and s.my_speed < SCISSORS_LOW_SPEED and s.tgt_speed < SCISSORS_LOW_SPEED:
			new_tactic = EngageTactic.SCISSORS
		else:
			# 急转防御
			new_tactic = EngageTactic.BREAK_TURN

	# ── 2. 迎头接近 ──
	elif s.is_head_on:
		new_tactic = EngageTactic.LEAD_TURN

	# ── 3. 我在敌后半球（进攻位置） ──
	elif s.in_rear_hemi:
		if s.closing_rate > CR_HIGHYOYO_CLOSE and s.dist_px < close_range:
			# 闭合率过高 + 近距 → 高悠悠防冲过
			new_tactic = EngageTactic.HIGH_YOYO
		elif s.closing_rate > CR_LAG_PURSUIT and s.dist_px < mid_range and s.speed_ratio > SPEED_RATIO_LAG:
			# 闭合但速度优势明显 → 滞后追踪
			new_tactic = EngageTactic.LAG_PURSUIT
		elif s.dist_px > mid_range and s.closing_rate < CR_LOWYOYO_FAR:
			# 远距离 + 闭合慢 → 低悠悠加速
			new_tactic = EngageTactic.LOW_YOYO
		else:
			# 正常追踪
			new_tactic = EngageTactic.LEAD_PURSUIT

	# ── 4. 侧面/其他位置 ──
	else:
		if s.dist_px > mid_range:
			new_tactic = EngageTactic.LEAD_PURSUIT
		elif s.dist_px < close_range and s.closing_rate > CR_HIGHYOYO_SIDE:
			new_tactic = EngageTactic.HIGH_YOYO
		elif s.dist_px > mid_range * MID_RANGE_LOWYOYO and s.closing_rate < CR_LOWYOYO_SIDE:
			new_tactic = EngageTactic.LOW_YOYO
		else:
			new_tactic = EngageTactic.LEAD_PURSUIT

	# BOSS 攻击手：禁逃跑 + 远距离只允许直追（不做能量管理花式机动）
	if is_boss_attacker():
		if new_tactic == EngageTactic.EXTENSION:
			new_tactic = EngageTactic.LEAD_PURSUIT
		# 远距离（> 2000px ≈ 4km）时只允许 LEAD/LAG_PURSUIT，禁止 LOW_YOYO/HIGH_YOYO/SCISSORS
		# 这些能量管理战术不直接闭合距离，BOSS 应该先赶回来再做机动
		elif s.dist_px > 2000.0:
			if new_tactic in [EngageTactic.LOW_YOYO, EngageTactic.HIGH_YOYO,
					EngageTactic.SCISSORS, EngageTactic.BREAK_TURN]:
				new_tactic = EngageTactic.LEAD_PURSUIT

	# 激进度调整：激进 AI 更倾向进攻战术
	if aggression_factor > 0.7:
		if new_tactic == EngageTactic.EXTENSION and aircraft.hp > aircraft.params.max_hp * HEALTH_AGGRESSIVE_EXTEND:
			new_tactic = EngageTactic.BREAK_TURN

	# ── 决策失误：有概率选到次优战术 ──
	var eff := _effective_skill()
	var mistake_chance := (1.0 - eff) * MAX_MISTAKE_CHANCE  # 最高 15% 失误率
	if randf() < mistake_chance and new_tactic != _tactic:
		new_tactic = _make_mistake(new_tactic)

	if new_tactic != _tactic:
		_apply_new_tactic(new_tactic)

## 应用新战术并重置相关状态
func _apply_new_tactic(new_tactic: EngageTactic) -> void:
	var eff := _effective_skill()
	var old_tactic := _tactic
	_prev_tactic = _tactic
	_tactic = new_tactic
	_tactic_timer = 0.0
	_yoyo_phase = 0
	if aircraft:
		aircraft.show_tactic_popup(TACTIC_DISPLAY_NAME.get(_tactic, ""))
	EventLogger.log_event("TACTIC", _log_name(),
		"%s → %s (target=%s, stress=%.2f, skill_eff=%.2f)" % [
			TACTIC_DISPLAY_NAME.get(old_tactic, "?"),
			TACTIC_DISPLAY_NAME.get(_tactic, "?"),
			_log_target_name(_current_target),
			personality.stress, eff])

	var reaction_mult := 1.0 + (1.0 - eff) * 1.0
	match _tactic:
		EngageTactic.LEAD_PURSUIT:
			_tactic_min_duration = MIN_DUR_LEAD_PURSUIT * reaction_mult
		EngageTactic.LAG_PURSUIT:
			_tactic_min_duration = MIN_DUR_LAG_PURSUIT * reaction_mult
		EngageTactic.LEAD_TURN:
			_tactic_min_duration = MIN_DUR_LEAD_TURN * reaction_mult
		EngageTactic.HIGH_YOYO:
			_tactic_min_duration = MIN_DUR_HIGH_YOYO * reaction_mult
			_yoyo_base_alt = aircraft.altitude
		EngageTactic.LOW_YOYO:
			_tactic_min_duration = MIN_DUR_LOW_YOYO * reaction_mult
			_yoyo_base_alt = aircraft.altitude
		EngageTactic.BREAK_TURN:
			_tactic_min_duration = MIN_DUR_BREAK_TURN * reaction_mult
			_break_phase = 0
		EngageTactic.EXTENSION:
			_tactic_min_duration = MIN_DUR_EXTENSION * reaction_mult
			_extension_start_pos = aircraft.global_position
		EngageTactic.SCISSORS:
			_tactic_min_duration = MIN_DUR_SCISSORS * reaction_mult
			_scissors_side = 1.0
			_scissors_reverse_timer = 0.0

	personality.alt_error = randf_range(-1.0, 1.0) * (1.0 - eff) * ALTITUDE_ERROR_AMP

## 决策失误：返回一个"次优"战术替代正确选择
func _make_mistake(correct: EngageTactic) -> EngageTactic:
	# 每种正确战术对应的常见失误
	match correct:
		EngageTactic.HIGH_YOYO:
			# 该防冲过时继续追 → 冲过
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.LAG_PURSUIT:
			# 该控制节奏时莽冲
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.LOW_YOYO:
			# 该加速闭合时选了保守跟踪
			return EngageTactic.LAG_PURSUIT
		EngageTactic.BREAK_TURN:
			# 该急转时慌了选剪刀（犹豫不决）
			return EngageTactic.SCISSORS if randf() > 0.5 else EngageTactic.EXTENSION
		EngageTactic.EXTENSION:
			# 该跑时却转向（不甘心）
			return EngageTactic.BREAK_TURN
		EngageTactic.LEAD_TURN:
			# 该提前转时直冲（没有战术意识）
			return EngageTactic.LEAD_PURSUIT
		EngageTactic.SCISSORS:
			# 该剪刀时选了脱离（太慌张）
			return EngageTactic.EXTENSION
		_:
			return correct

# ══════════════════════════════════════════════
#  战术执行
# ══════════════════════════════════════════════

## 前置追踪：瞄准敌机前方，积极闭合距离
func _execute_lead_pursuit(s: SituationData) -> void:
	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	# 复用距离+速度感知的动态追踪（远距直追→中距过渡→近距战术）
	var pursuit_pos := aircraft._choose_dogfight_pursuit_pos(
			s.my_pos, s.dist_px, s.tgt_pos, s.tgt_fwd,
			tgt_speed_px, my_speed_px, s.in_rear_hemi)

	aircraft.target_position = _apply_position_error(pursuit_pos)
	_match_target_altitude()
	_set_engage_speed(s, 1.2)

## 滞后追踪：瞄准敌机后方，防止冲过，保持后半球位置
func _execute_lag_pursuit(s: SituationData) -> void:
	# 性格偏移：斗士贴近六点钟(0.18)，骑士保持距离(0.45)
	var lag_offset := maxf(LAG_OFFSET_MIN, s.gun_range_px * _cb().six_oclock_offset_ratio)
	var pursuit_pos := s.tgt_pos - s.tgt_fwd * lag_offset

	aircraft.target_position = _apply_position_error(pursuit_pos)
	_match_target_altitude()

	# 匹配敌机速度，略低以防冲过
	var target_speed_kmh := _current_target.speed * 3.6 * LAG_SPEED_RATIO
	aircraft.target_speed_kmh = _apply_speed_error(clampf(target_speed_kmh, LAG_MIN_SPEED, aircraft.params.max_speed if aircraft.params else 2000.0))

## 提前转弯：迎头接近时提前转向敌机飞行路径后方
func _execute_lead_turn(s: SituationData) -> void:
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	var pass_time := s.dist_px / maxf(s.closing_rate + LEAD_TURN_CLOSING_ADJ, 100.0)
	var future_tgt_pos := s.tgt_pos + s.tgt_fwd * tgt_speed_px * pass_time
	# 性格偏移：六点钟偏移 × 1.2（lead_turn 天然比 lag 更远一些）
	var six_pos := future_tgt_pos - s.tgt_fwd * maxf(LEAD_TURN_SIXOCLOCK_MIN, s.gun_range_px * _cb().six_oclock_offset_ratio * LEAD_TURN_SIXOCLOCK_MULT)

	aircraft.target_position = _apply_position_error(six_pos)
	_match_target_altitude()
	_set_engage_speed(s, 1.0)

## 高悠悠：拉高减速防止冲过，然后俯冲回来继续追踪
func _execute_high_yoyo(s: SituationData, delta: float) -> void:
	if _yoyo_phase == 0:
		# 阶段0：拉高
		if aircraft.flat_altitude:
			# 扁平模式：切到上一档
			aircraft.set_target_tier(aircraft.tier_above())
		else:
			# 性格偏移：斗士爬升幅度小(600m)，骑士爬升高(1000m)
			var climb_height := _cb().climb_brake_height
			var climb_target := _yoyo_base_alt + _apply_altitude_error(climb_height)
			if aircraft.params:
				climb_target = clampf(climb_target, _yoyo_base_alt + HIGH_YOYO_CLIMB_MIN, aircraft.params.max_altitude - ALTITUDE_MATCH_THRESH)
			aircraft.target_altitude = climb_target

		var lag_pos := s.tgt_pos - s.tgt_fwd * s.gun_range_px * HIGH_YOYO_LAG_RATIO
		aircraft.target_position = _apply_position_error(lag_pos)

		# 性格偏移：斗士减速更猛(0.80)，骑士保速(0.90)
		aircraft.target_speed_kmh = _apply_speed_error(_current_target.speed * 3.6 * _cb().dive_speed_ratio)

		if aircraft.flat_altitude:
			# 扁平模式：到达目标档位即切阶段
			if aircraft.get_altitude_tier() >= aircraft.target_altitude_tier or _tactic_timer > 4.0:
				_yoyo_phase = 1
		else:
			if aircraft.altitude >= aircraft.target_altitude - 100.0 or _tactic_timer > 4.0:
				_yoyo_phase = 1
	else:
		# 阶段1：俯冲回来
		_match_target_altitude()
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), HIGH_YOYO_LEAD_MIN, HIGH_YOYO_LEAD_MAX)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		_set_engage_speed(s, 1.1)

		if aircraft.flat_altitude:
			if aircraft.get_altitude_tier() == _current_target.get_altitude_tier():
				_tactic_timer = _tactic_min_duration
		else:
			if absf(aircraft.altitude - _current_target.altitude) < 200.0:
				_tactic_timer = _tactic_min_duration

## 低悠悠：俯冲加速缩短距离，再拉高攻击
func _execute_low_yoyo(s: SituationData, delta: float) -> void:
	if _yoyo_phase == 0:
		# 阶段0：俯冲加速
		if aircraft.flat_altitude:
			# 扁平模式：切到下一档
			aircraft.set_target_tier(aircraft.tier_below())
		else:
			# 性格偏移：斗士俯冲更深(1500m)，骑士浅俯冲(800m)
			var dive_target := _yoyo_base_alt - _apply_altitude_error(_cb().dive_depth)
			if aircraft.params:
				dive_target = clampf(dive_target, _cb().dive_floor, _yoyo_base_alt - 200.0)
			aircraft.target_altitude = dive_target

		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), LOW_YOYO_LEAD_MIN, LOW_YOYO_LEAD_MAX)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)

		# 性格偏移：骑士俯冲加速更猛，斗士稍温和
		_set_engage_speed(s, 1.2 + _cb().approach_speed_mult * LOW_YOYO_APPROACH_SCALE)

		if aircraft.flat_altitude:
			if aircraft.get_altitude_tier() <= aircraft.target_altitude_tier or _tactic_timer > 4.0:
				_yoyo_phase = 1
		else:
			if aircraft.altitude <= aircraft.target_altitude + 100.0 or _tactic_timer > 4.0:
				_yoyo_phase = 1
	else:
		# 阶段1：拉高回到敌机高度
		_match_target_altitude()
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), LOW_YOYO_CLIMB_LEAD_MIN, LOW_YOYO_CLIMB_LEAD_MAX)
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		_set_engage_speed(s, 1.1)

		if aircraft.flat_altitude:
			if aircraft.get_altitude_tier() == _current_target.get_altitude_tier():
				_tactic_timer = _tactic_min_duration
		else:
			if absf(aircraft.altitude - _current_target.altitude) < 200.0:
				_tactic_timer = _tactic_min_duration

## 急转脱离：被咬尾时急转增大偏置角，然后反转迎头
## Shaw 原则：Break Turn 是初始防御，之后必须反转或脱离，不能一直平转
func _execute_break_turn(s: SituationData) -> void:
	if _break_phase == 0 and _tactic_timer < 2.0:
		# 阶段0（前2秒）：急转垂直于威胁方向，建立偏置角
		var threat_dir := (aircraft.global_position - s.tgt_pos).normalized()
		var perp_a := Vector2(threat_dir.y, -threat_dir.x)
		var perp_b := Vector2(-threat_dir.y, threat_dir.x)

		var heading_a := atan2(perp_a.x, -perp_a.y)
		var heading_b := atan2(perp_b.x, -perp_b.y)
		var diff_a := absf(_angle_diff(heading_a, aircraft.heading))
		var diff_b := absf(_angle_diff(heading_b, aircraft.heading))
		var chosen_dir := perp_a if diff_a < diff_b else perp_b

		aircraft.target_position = _apply_position_error(aircraft.global_position + chosen_dir * BREAK_TURN_DIST)

		if aircraft.flat_altitude:
			pass  # 扁平模式：急转时保持当前档位
		elif aircraft.altitude > 3000.0:
			aircraft.target_altitude = aircraft.altitude - BREAK_TURN_ALT_REDUCE
		else:
			aircraft.target_altitude = aircraft.altitude

		_set_engage_speed(s, 1.0)
	else:
		# 阶段1（2秒后）：反转迎头
		_break_phase = 1
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		aircraft.target_position = _apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * BREAK_TURN_COUNTER_LEAD)
		_match_target_altitude()
		_set_engage_speed(s, BREAK_TURN_COUNTER_SPEED)

## 加速脱离：远离敌机拉开距离
func _execute_extension(s: SituationData) -> void:
	var away_dir := (aircraft.global_position - s.tgt_pos).normalized()
	# 低技能飞行员脱离方向可能有偏差
	aircraft.target_position = _apply_position_error(aircraft.global_position + away_dir * EXTENSION_DISTANCE)

	# 性格偏移：骑士脱离更快(approach_speed_mult=1.75→0.95×max)，
	# 斗士脱离较慢(1.55→0.89×max)，但斗士本身很少选 extension
	if aircraft.params:
		var escape_mult := lerpf(EXTENSION_ESCAPE_MIN, EXTENSION_ESCAPE_MAX, _cb().approach_speed_mult / 2.0)
		aircraft.target_speed_kmh = _apply_speed_error(aircraft.params.max_speed * escape_mult)
	else:
		aircraft.target_speed_kmh = _apply_speed_error(1800.0)

	# 脱离时爬升保能
	if aircraft.flat_altitude:
		aircraft.set_target_tier(aircraft.tier_above())
	else:
		aircraft.target_altitude = aircraft.altitude + EXTENSION_CLIMB

	var separation := aircraft.global_position.distance_to(_extension_start_pos)
	if separation > EXTENSION_SUCCESS_DIST and s.dist_px > s.gun_range_px * EXTENSION_SUCCESS_MULT:
		_tactic_timer = _tactic_min_duration

## 剪刀机动：近距反复交叉反转，利用低速优势抢位
func _execute_scissors(s: SituationData, delta: float) -> void:
	_scissors_reverse_timer += delta

	# 剪刀反转间隔（根据距离和速度调整）
	var reverse_interval := clampf(s.dist_px / maxf(s.my_speed * Aircraft.PIXELS_PER_METER, 30.0), SCISSORS_REVERSE_MIN, SCISSORS_REVERSE_MAX)

	if _scissors_reverse_timer >= reverse_interval:
		_scissors_side *= -1.0
		_scissors_reverse_timer = 0.0

	# 计算交叉方向：垂直于我与敌机连线
	var to_tgt_dir := s.to_target
	var cross_dir := Vector2(to_tgt_dir.y, -to_tgt_dir.x) * _scissors_side

	# 目标位置：侧向偏移 + 略微朝向敌机
	var scissors_pos := aircraft.global_position + cross_dir * SCISSORS_LATERAL + to_tgt_dir * SCISSORS_FORWARD
	aircraft.target_position = _apply_position_error(scissors_pos)

	# 减速！剪刀机动中低速优势是关键（低技能飞行员可能减速不够）
	if aircraft.params:
		var min_safe_speed := aircraft.params.stall_speed_base * SCISSORS_SAFE_SPEED
		aircraft.target_speed_kmh = _apply_speed_error(min_safe_speed)
	else:
		aircraft.target_speed_kmh = _apply_speed_error(SCISSORS_FALLBACK_SPEED)

	_match_target_altitude()

# ══════════════════════════════════════════════
#  速度管理辅助
# ══════════════════════════════════════════════

## 高度匹配敌机（自动适配扁平/连续模式）
func _match_target_altitude() -> void:
	if not _current_target:
		return
	if aircraft.flat_altitude:
		aircraft.set_target_tier(_current_target.get_altitude_tier())
	else:
		aircraft.target_altitude = _current_target.altitude

## 设置巡逻高度（自动适配扁平/连续模式）
func _set_patrol_altitude() -> void:
	if aircraft.flat_altitude:
		aircraft.set_target_tier(Aircraft.AltitudeTier.MID)
	else:
		aircraft.target_altitude = patrol_altitude

## 机炮闪避：被追尾射击时叠加蛇形偏移（仅斗士型，幅度受技能梯度控制）
## 不改变战术状态，只在当前战术的 target_position 上叠加垂直偏移
func _update_gun_jink(s: SituationData, delta: float) -> void:
	# 只有斗士型（combat_bank_aggression > 1.0）才做机炮闪避
	if _cb().combat_bank_aggression <= 1.0:
		_gun_jink_active = false
		return

	# 触发条件：敌机在我后半球开火 + 我意识到了 + 在威胁距离内
	var should_jink := false
	if _current_target and is_instance_valid(_current_target) and _current_target is Aircraft:
		var enemy: Aircraft = _current_target
		if enemy.is_firing and s.enemy_in_my_rear and personality.rear_threat_aware \
				and s.dist_px < s.gun_range_px * GUN_JINK_RANGE_MULT:
			should_jink = true

	if should_jink:
		_gun_jink_active = true
		_gun_jink_grace = GUN_JINK_GRACE  # 停火后继续闪避
	elif _gun_jink_grace > 0.0:
		_gun_jink_grace -= delta
	else:
		_gun_jink_active = false
		_gun_jink_timer = 0.0
		return

	_gun_jink_timer += delta

	# 技能梯度：高技能=大幅快频稳定，低技能=小幅慢频不稳
	var eff := _effective_skill()
	var base_amp := lerpf(GUN_JINK_AMP_MIN, GUN_JINK_AMP_MAX, eff)       # 像素偏移幅度
	var base_period := lerpf(GUN_JINK_PERIOD_MAX, GUN_JINK_PERIOD_MIN, eff)        # 秒/周期（高技能更快切换）
	# 低技能噪声：幅度随机波动，模拟"犯傻"
	var noise := 0.0
	if eff < 0.7:
		noise = sin(_gun_jink_timer * GUN_JINK_NOISE_FREQ) * (1.0 - eff) * GUN_JINK_NOISE_AMP
	var amp := base_amp * (1.0 + noise)
	var sway := sin(_gun_jink_timer * TAU / base_period) * amp

	# 偏移方向：垂直于敌机→我的追尾方向
	var to_me := (aircraft.global_position - _current_target.global_position).normalized()
	var perp := Vector2(to_me.y, -to_me.x)
	aircraft.target_position += perp * sway

func _set_engage_speed(s: SituationData, mult: float) -> void:
	if not aircraft.params:
		aircraft.target_speed_kmh = _apply_speed_error(FALLBACK_ENGAGE_SPEED * mult)
		return
	var cruise := aircraft.params.cruise_speed
	# 性格偏移：斗士近战减速求转弯(0.9)，骑士保持高速保能量(1.15)
	var style := _cb().maneuver_speed_mult
	var target := clampf(cruise * mult * style, aircraft.params.stall_speed_base * ENGAGE_STALL_SAFETY, aircraft.params.max_speed)
	aircraft.target_speed_kmh = _apply_speed_error(target)

# ══════════════════════════════════════════════
#  EVADE_MISSILE — 导弹规避（保持原有逻辑）
# ══════════════════════════════════════════════

func _process_evade(delta: float) -> void:
	var missile := _find_nearest_incoming_missile()
	if not missile:
		_exit_evade()
		return

	# ── 战术机动：后方来袭导弹逼近时一次性触发 ──
	var _mev := aircraft.get_maneuver()
	if _mev and not _mev.is_used and not _mev.is_active:
		var missile_dist := missile.global_position.distance_to(aircraft.global_position)
		if missile_dist < MANEUVER_ACTIVATE_DIST and _is_missile_from_rear(missile):
			_mev.activate()
			var fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
			aircraft.target_position = aircraft.global_position + fwd * EVADE_FLIGHT_DIST
			return
	# 战术机动执行中：保持航向等待完成
	if _mev and _mev.is_active:
		var fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
		aircraft.target_position = aircraft.global_position + fwd * EVADE_FLIGHT_DIST
		return

	var missile_dir := (aircraft.global_position - missile.global_position).normalized()
	var evade_dir := Vector2(missile_dir.y, -missile_dir.x)

	var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
	var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
	var diff_a := absf(_angle_diff(evade_heading_a, aircraft.heading))
	var diff_b := absf(_angle_diff(evade_heading_b, aircraft.heading))
	var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir

	_evade_target_pos = aircraft.global_position + chosen_dir * EVADE_TURN_DIST
	aircraft.target_position = _evade_target_pos

	if aircraft.combat_target:
		aircraft.clear_combat_target()

	if aircraft.flat_altitude:
		# 扁平模式：规避时切换档位（低→中/高，高→中/低）
		if aircraft.get_altitude_tier() == Aircraft.AltitudeTier.LOW:
			aircraft.set_target_tier(Aircraft.AltitudeTier.HIGH)
		else:
			aircraft.set_target_tier(Aircraft.AltitudeTier.LOW)
	else:
		var alt_change := EVADE_ALT_CHANGE if aircraft.altitude < EVADE_ALT_THRESH else -EVADE_ALT_CHANGE
		aircraft.target_altitude = aircraft.altitude + alt_change

func _enter_evade() -> void:
	EventLogger.log_event("EVADE", _log_name(),
		"entering missile evasion (was %s, target=%s)" % [
			AIState.keys()[_state], _log_target_name(_current_target)])
	_state = AIState.EVADE_MISSILE
	aircraft.ai_override_pursuit = false
	_squad_attacking_leader_target = false
	_squad_free_engaging = false
	if aircraft.combat_target:
		aircraft.clear_combat_target()
	# 退出编队托管，规避机动必须走正常飞行物理（LOD 0）
	# 否则 lod_level==1 + formation_mode 会让规避航向变化走
	# aircraft.gd:261 的纯 lerp_angle 分支，绕过 G 限/bank 速率/corner speed，
	# 导致 ~360°/s 的瞬间机头扭转（见 2026-04-11 Jinx 规避 bug）。
	aircraft.formation_mode = false
	aircraft._formation_leader = null
	aircraft._formation_blend = 0.0
	_formation_blend = 0.0  # 规避结束后从 0 开始重新融入编队
	aircraft.lod_level = 0
	aircraft.keep_target_on_arrival = false

func _exit_evade() -> void:
	EventLogger.log_event("EVADE", _log_name(), "exiting missile evasion")
	if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
		aircraft.set_combat_target(_current_target)
		_set_patrol_altitude()
		_state = AIState.ENGAGE
		_tactic_timer = 0.0
	elif squad and is_instance_valid(squad.leader) and not squad.leader.is_destroyed:
		_state = AIState.SQUAD_FOLLOW
		_cover_target = null
		_rejoining = true
		_formation_blend = 0.0  # 从0开始渐变回编队托管
		aircraft.clear_combat_target()
		aircraft.ai_override_pursuit = false
		aircraft.lod_level = 1
	else:
		_current_target = null
		_state = AIState.PATROL
		_set_patrol_altitude()
		aircraft.ai_override_pursuit = false
		_set_next_waypoint()

# ══════════════════════════════════════════════
#  交战管理
# ══════════════════════════════════════════════

func _try_engage() -> void:
	if _cooldown_timer > 0.0:
		return

	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_target_score := -1.0

	for target_key in aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or target_ac.team == aircraft.team:
			continue

		var lock_progress: float = aircraft.radar_targets[target_key]
		var lock_time: float = aircraft.params.lock_time if aircraft.params else 3.0

		var dist := aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 低空目标攻击欲望降低
		var tgt_tier := target_ac.get_altitude_tier()
		if tgt_tier == CombatUnit.AltitudeTier.LOW:
			score *= 0.65
		elif tgt_tier == CombatUnit.AltitudeTier.GROUND:
			score *= 0.5

		# 偏好高度加成
		if preferred_altitude_tier != -99 and tgt_tier == preferred_altitude_tier:
			score *= 1.3

		# 目标粘性：当前目标获得专注度加成
		if target_ac == _current_target:
			score += focus * 5.0
			current_target_score = score

		var min_lock_ratio := lerpf(1.0, 0.3, aggression)
		if lock_score < min_lock_ratio:
			continue

		if score > best_score:
			best_score = score
			best_target = target_ac

	if best_target:
		# 切换目标需要超越当前目标的粘性阈值
		if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
			if best_target != _current_target and current_target_score > 0.0:
				var switch_threshold := focus * 2.0
				if best_score < current_target_score + switch_threshold:
					return  # 新目标不够优，维持当前目标

		var prev_state := _state
		_current_target = best_target
		aircraft.set_combat_target(best_target)
		_state = AIState.ENGAGE
		_engage_timer = 0.0
		_tactic = EngageTactic.LEAD_PURSUIT
		_tactic_timer = 0.0
		_tactic_min_duration = MIN_DUR_LEAD_PURSUIT
		_target_eval_timer = 0.0
		aircraft.ai_override_pursuit = true
		_squad_attacking_leader_target = false  # 独立交战
		_squad_free_engaging = false
		var dist_m := aircraft.global_position.distance_to(best_target.global_position) / CombatUnit.PIXELS_PER_METER
		EventLogger.log_event("AI_STATE", _log_name(),
			"%s → ENGAGE (target=%s, dist=%.0fm, score=%.2f)" % [
				AIState.keys()[prev_state], _log_target_name(best_target), dist_m, best_score])

## 交战中重评估目标（受 focus 影响）
func _reevaluate_target() -> void:
	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_score := -1.0

	for target_key in aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or target_ac.team == aircraft.team:
			continue

		var lock_progress: float = aircraft.radar_targets[target_key]
		var lock_time: float = aircraft.params.lock_time if aircraft.params else 3.0

		var dist := aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 当前目标获得专注度粘性加成
		if target_ac == _current_target:
			score += focus * 5.0
			current_score = score

		if score > best_score:
			best_score = score
			best_target = target_ac

	if not best_target or best_target == _current_target:
		return

	# 必须显著优于当前目标才切换
	var switch_threshold := focus * 3.0
	if current_score > 0.0 and best_score < current_score + switch_threshold:
		return

	# 切换目标
	var old_target := _current_target
	_current_target = best_target
	aircraft.set_combat_target(best_target)
	_tactic_timer = 0.0
	_yoyo_phase = 0
	EventLogger.log_event("TARGET", _log_name(),
		"switched target: %s → %s (old_score=%.2f, new_score=%.2f)" % [
			_log_target_name(old_target), _log_target_name(best_target),
			current_score, best_score])

func _disengage() -> void:
	EventLogger.log_event("AI_STATE", _log_name(),
		"DISENGAGE (was fighting %s, engaged %.1fs)" % [
			_log_target_name(_current_target), _engage_timer])

	# ── BOSS 攻击手：不真正脱离，立即重新进入交战 ──
	if is_boss_attacker():
		# 即使 _current_target 丢失也不脱离——重新锁定玩家
		var player: Aircraft = null
		if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
			player = _current_target as Aircraft
		else:
			# 搜索玩家（team 0 的飞机）
			for child in aircraft.get_parent().get_children():
				if child is Aircraft and child.team == 0 and not child.is_destroyed:
					player = child
					break
		if player:
			_current_target = player
			aircraft.combat_target = player
			_engage_timer = 0.0
			_cooldown_timer = 0.0
			_tactic_timer = 0.0
			_tactic_min_duration = 0.0
			_apply_new_tactic(EngageTactic.LEAD_PURSUIT)
			EventLogger.log_event("AI_STATE", _log_name(), "BOSS re-engage immediately")
			return

	aircraft.clear_combat_target()
	aircraft.ai_override_pursuit = false
	aircraft.keep_target_on_arrival = false
	_current_target = null
	_cooldown_timer = engage_cooldown
	current_tactic_name = ""
	_squad_attacking_leader_target = false
	_squad_free_engaging = false
	_leader_target_lost_timer = 0.0
	_squad_range_grace_timer = 0.0
	# 有编队且长机不是自己 → 回归编队；否则（独行或自己就是长机）回巡逻
	# bvr_only（F-47 逃跑手）不进编队跟随——走巡逻执行逃跑航点
	# 不能让单机长机/新晋升长机进 SQUAD_FOLLOW，否则会对着自己算槽位原地自转
	if not bvr_only and squad and is_instance_valid(squad.leader) and not squad.leader.is_destroyed \
			and squad.leader != aircraft:
		_state = AIState.SQUAD_FOLLOW
		_cover_target = null
		_rejoining = true
		_formation_blend = 0.0  # 从0开始渐变回编队托管
		aircraft.lod_level = 1
	else:
		# 独自存活的长机走巡逻，顺便把 squad_index 归零（以防 squad 尚在但已是孤雁）
		if squad and squad.leader == aircraft:
			squad_index = 0
		aircraft.formation_mode = false
		aircraft._formation_leader = null
		_state = AIState.PATROL
		_set_patrol_altitude()
		_set_next_waypoint()

# ══════════════════════════════════════════════
#  导弹威胁检测
# ══════════════════════════════════════════════

func _check_incoming_missile() -> bool:
	return _find_nearest_incoming_missile() != null

func _find_nearest_incoming_missile() -> Missile:
	var missile_manager := _get_missile_manager()
	if not missile_manager:
		return null

	var nearest: Missile = null
	var nearest_dist := 99999.0

	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active:
			continue
		if m.target != aircraft:
			continue
		if m.is_flare_jammed:
			continue  # 已被热诱弹干扰，不再构成威胁
		var dist := m.global_position.distance_to(aircraft.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = m

	return nearest

## 判断导弹是否从后半球逼近（用于眼镜蛇触发）
## 同时检查两个条件：
##   1. 导弹在飞机后方（位置判定）
##   2. 导弹正朝飞机飞来（速度方向判定，排除已飞过的导弹）
func _is_missile_from_rear(missile: Missile) -> bool:
	var missile_to_ac := (aircraft.global_position - missile.global_position).normalized()
	var ac_fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
	# 条件 1：导弹在飞机后方锥内
	if ac_fwd.dot(missile_to_ac) <= 0.3:
		return false
	# 条件 2：导弹的飞行方向朝向飞机（而非已经飞过去了）
	var missile_fwd := Vector2(sin(missile.heading), -cos(missile.heading))
	return missile_fwd.dot(missile_to_ac) > 0.3

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

# ── 协同齐射系统（F-47 小队战术） ──

## leader 发射导弹后广播齐射信号给编队僚机
func broadcast_salvo() -> void:
	if not squad:
		return
	for member in squad.members:
		if not is_instance_valid(member) or member.is_destroyed or member == aircraft:
			continue
		var mai: AIController = _find_member_ai(member)
		if mai and not mai._salvo_pending:
			mai._salvo_pending = true
			mai._salvo_delay = randf_range(0.1, 0.4)  # 0.1~0.4 秒错开

## 处理齐射倒计时（在 aircraft._update_missile 中每帧调用）
func process_salvo(delta: float) -> bool:
	if not _salvo_pending:
		return false
	_salvo_delay -= delta
	if _salvo_delay <= 0.0:
		_salvo_pending = false
		return true  # 通知 aircraft 强制发射
	return false
