class_name AIController
extends Node

## AI 控制器：巡逻 / 交战（战术机动） / 导弹规避 状态机
## 交战时基于 Shaw《Fighter Combat》BFM 决策树选择战术机动

# 显式 preload 兜底新增的 class_name 类（Godot 全局类缓存有时不刷新）
const EscortBehavior := preload("res://scripts/ai/escort_behavior.gd")

# Phase 2 状态正交化（2026-07-05，重构计划 §5 Phase 2）：
# EVADE 不再是 _state 轴上的值 —— 它与 PATROL/ENGAGE/SQUAD_FOLLOW 正交，实现为
# `_evading` modifier（由 MissileEvasion.enter_evade/exit_evade 独占进出）。
# 躲弹期间背景 _state 保持原值，分发层短路到 process_evade；退出时按上下文三路重定。
# 同理 directive / manual_control 本就是分发层旁路（正交模态），只是没占 _state 轴。
enum AIState { PATROL, ENGAGE, SQUAD_FOLLOW }
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
## GUARD_REAR (2)    : 守护后半球——僚机不打长机的进攻目标，只盯长机六点钟后半球、
##                     攻击其中有威胁的敌机；无后方威胁时保持编队守在长机身后
enum SquadEngageMode { FREE = 0, FOLLOW_LEADER = 1, GUARD_REAR = 2 }
## 默认 FOLLOW_LEADER（spec squad-cohesion §2.1，2026-05-31 由 FREE 改）：小队默认凝聚——
## 僚机只打长机目标（焦点开火 + 维持阵型），玩家可经 HUD「交战模式」按钮切回 FREE 放养。
@export var squad_engage_mode: int = SquadEngageMode.FOLLOW_LEADER
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

## ── SwarmDirector 接口（Mother Goose UAV 协同用）──
## 由 [scripts/ai/swarm/swarm_director.gd] 在 1Hz tick 中写入，simple_combat 路径每帧读
## -1 = 未分配 / 普通 AI（默认）；0+ = 对应 SwarmDirector.Role 枚举
@export var swarm_role_override: int = -1
## SHOOTER/ATTACKER_*: lane 中心在世界系的弧度（玩家航向 + 楔形本地角度）
## DECOY: 跑路方向；GUARD/RESERVE/NONE 时不读
@export var swarm_lane_world_angle: float = 0.0

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
	if directive != null and aircraft:
		# 接管时清护驾/蜂群轨道限速残留（2026-07-03）：directive 分支在轨道代码之前
		# return，期间没人清 cap → 整段 directive 飞行被钳在轨道速度（~280km/h）
		aircraft.orbit_speed_cap = 0.0
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

## 玩家亲控休眠（spec squad-control-switching §3.6）：
## true = 这架被玩家鼠标操控，AI 完全休眠——不写 target_position、不选战术、不设速度/高度，
## 让玩家点击接管导航。与现状"玩家机不挂 AI"体验一致。
## 武器自动开火在 Aircraft 层（不经 AIController），休眠不影响开火；导弹靠玩家走位躲。
## 切换操控时由 survivor_mode 在新/旧长机上翻转此标志。
var manual_control: bool = false

## 降级过渡 grace（spec §3.4 "打完再归队"）：旧长机被卸下操控后唤醒 AI，
## 但此计时器>0 期间保持当前 combat_target/target_position、不强制归位编队。
## 由 combat_target 消失 / 到达 target_position / 计时归零 任一触发归队（在 SQUAD_FOLLOW 路由前消费）。
const TAKEOVER_TRANSITION_GRACE: float = 6.0
var _takeover_transition_timer: float = 0.0

## §C 玩家技能反向索引：每帧检测 _current_target 变化，差量更新 target.engaging_me
## 不在 _current_target 各赋值点散落，集中到 _physics_process 顶层做一次比对
var _prev_target_for_reverse_idx: CombatUnit = null
@export var orbit_squad_leader: bool = false  ## simple_ai 专用：巡逻时围绕长机旋转（指挥 UAV 招募的僚机用）
@export var shield_leader: bool = false       ## orbit 专用：主动飞入来袭导弹路径保护长机（含自爆拦截 @ MISSILE_INTERCEPT_DIST=100px）
## 玩家忠诚僚机 drone 专用：来袭导弹瞄向 squad.leader 时，drone 主动撞毁拦截
## 与 SQUAD_FOLLOW 配合使用；默认 false，不影响普通僚机
@export var kamikaze_intercept: bool = false

## ── 战斗偏好区域（combat zone）──
## 用途：让 boss/Sentinel 的 hunter UAV 在 boss 周围一个圆区域里活动，
## 出界即放弃当前目标 + 强制回返。区内正常跑 AI；目标被引出区外 × SLACK 也放弃。
## 没设 anchor 或 radius=0 = 不启用，对普通 AI 无影响。
@export var combat_zone_anchor: Node = null
@export var combat_zone_radius: float = 0.0
## 区外目标宽限系数：允许追击的目标距区心最多 = radius × 此值，超出则放弃
const COMBAT_ZONE_TARGET_SLACK := 1.3

## ── 远程武器站位距离（standoff range）──
## simple_ai 交战时：若距目标 < standoff_range_px，则反向飞离维持站位距离，不贴脸狗斗
## 0 = 不启用，正常前置追踪。用于电磁炮 / 远距导弹 UAV
@export var preferred_standoff_range_px: float = 0.0

## 横向 flank 偏置（像素）——加到 lead_pos 上让两架同队 hunter 攻击目标不同侧
## 正数 = 目标右翼方向（target_fwd 顺时针 90°），负数 = 目标左翼
## 用于双机编队避免重叠（MQ-X 等精英对子）；普通 UAV 留 0 不影响
@export var flank_offset_lateral_px: float = 0.0

## ── 攻击跑（joust）行为原语（spec: docs/specs/systems/joust-attack-run.md）──
## RUN_IN 对准进入火力窗 → BREAK 脱离拉开 → 折返循环；替代 standoff 切向轨道
## （切向轨道与"锁定/充能要机头对准"结构矛盾 → MQ-112 全场 0 充能死锁）+
## Lancer 骑士型打带跑的统一实现。包络（inner/outer）默认动态读装备 live params。
@export var joust_enabled: bool = false
@export var joust_break_range_px: float = 0.0      ## 0=自动（武器包络 inner）
@export var joust_reentry_range_px: float = 0.0    ## 0=自动（outer × 1.3）
@export var joust_run_speed_kmh: float = 0.0       ## 0=自动（cruise，稳定对准平台）
@export var joust_break_speed_kmh: float = 0.0     ## 0=自动（max，脱离要快）
@export var joust_giveup_closing_mps: float = 0.0  ## 0=关；>0 = 骑士"闭合不够就放弃"阈值
@export var joust_run_max_s: float = 15.0          ## RUN_IN 安全超时
var _joust_phase: int = 0                          ## JoustController.Phase
var _joust_run_timer: float = 0.0
var _joust_lowclose_timer: float = 0.0
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
const ORBIT_TETHER_RADIUS := 750.0   ## 护驾轨道半径：无人机绕长机的轨道距离上限（视觉/护盾拦截需要贴近）
## 护驾交战触发范围：与 CommanderAura.AURA_RADIUS=1500 对齐 —— 玩家踏进光环圈就该被打。
## 解耦原因：轨道半径决定无人机贴 boss 多近（小），交战范围决定它们追多远（大）。
## 之前两者共用 ORBIT_TETHER_RADIUS=750，导致光环 1500 圈内 750~1500 这一段无人机被 buff
## 但不交战，玩家体感"光环没生效"，等 boss 死掉栓绳释放才看到无人机追击。
const ESCORT_ENGAGE_RADIUS := 1500.0

# ── 护卫学说目标评分加权（spec squad-ai-escort §2.2，仅护卫编队僚机叠加）──
# 与 try_engage / scan 的现有评分同尺度（dist_score≈1/d*1000，自然值 ~0~12）。
# 这两个常量是体感调参项：ATTACKING_LEADER_BONUS 取主导值让"咬长机者"几乎必被优先；
# 近长机加权次之。零威胁时 bonus≈0，自然退回就近交战（护卫优先但不死板）。
const ATTACKING_LEADER_BONUS := 60.0      ## 候选敌机正在咬长机 → 评分主导加权
const LEADER_PROXIMITY_BONUS_MAX := 25.0  ## 候选敌机紧贴长机 → 最大近距加权（按距长机插值 0~此值）

const COVER_SCAN_RANGE := 2500.0     ## 掩护扫描范围（像素）≈5000m（escort 评分近长机加权用）
## 守后半球拦截范围（像素，≈1.8km）：守护者只拦"靠近 + 真威胁"的后方敌机，且 < REAR_GUARD_LEASH_DIST
## 让守护者贴着长机不飞远（spec squad-cohesion：守后体感"贴身守"而非"远射"）
const REAR_GUARD_RANGE := 900.0
const COVER_SCAN_INTERVAL := 0.5     ## 掩护扫描间隔（秒）
const COVER_DISENGAGE_RANGE := 3500.0 ## 掩护脱离距离（威胁远离后回归）
var _cover_scan_timer: float = 0.0
var _cover_target: Aircraft = null   ## 掩护交战目标（后半球威胁）
var _rejoining: bool = false       ## 交战/规避后正在全速归队
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
# ── 小队 leash（spec squad-cohesion §2.2/§3.2）：交战僚机游走出长机此距离 → 强制脱战回编队 ──
# 根治"绕一大圈查无此人"。所有常规 squad 僚机生效（drone/bvr/boss/hunter 各有自己的远距逻辑，跳过）。
const SQUAD_LEASH_DIST := 1800.0  ## 距长机超此像素（≈3600m）触发 break-off（FREE / FOLLOW_LEADER）
const REAR_GUARD_LEASH_DIST := 1200.0  ## 守护后方专属更紧 leash（≈2.4km）：守后要贴身，不许远游（> REAR_GUARD_RANGE 以容拦截+追）
const SQUAD_LEASH_HYSTERESIS := 0.5  ## 越界持续此时长（秒）才触发，防边界抖动

## 当前生效的小队 leash 距离：守护后方用更紧的 REAR_GUARD_LEASH_DIST 贴身守；
## 但守护者去打威胁长机的地面 AA 时放宽到 SQUAD_LEASH_DIST（导弹 standoff 要够得着，不能被紧 leash 拽回）。
func effective_squad_leash() -> float:
	if squad_engage_mode == SquadEngageMode.GUARD_REAR:
		if _current_target is GroundUnit:
			return SQUAD_LEASH_DIST
		return REAR_GUARD_LEASH_DIST
	return SQUAD_LEASH_DIST
var _squad_leash_timer: float = 0.0  ## leash 越界累计计时

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
## Boss/Sentinel hunter（combat_zone_radius > 0 的 simple_ai）：
## 全速 + 全前置 —— hunter 要给玩家持续压力，不能 70% 巡航
const HUNTER_UAV_SPEED_RATIO := 1.0
const HUNTER_UAV_LEAD := 1.0
## Hunter 近战切换距离（像素）：dist < 此值时降速到 cruise_speed 提高转弯率
## 防止 buffed UAV @ 1650 km/h（turn radius ~1800m）冲过玩家不开枪
const HUNTER_CLOSE_COMBAT_DIST := 1200.0

# ── 编队反应（已迁移到 Squad，2026-05-04 重构）──
# Squad.FORMATION_SWITCH_THRESH / FORMATION_REACT_BASE / FORMATION_JITTER_AMP /
# Squad.FORMATION_JITTER_ADD / WINGMAN_ENGAGE_DELAY_MIN / WINGMAN_ENGAGE_DELAY_MAX

# ── 自由扫描 ──
const SQUAD_FREE_SCAN_RANGE := 1500.0      ## 僚机自由扫描范围（像素，=3km）。2026-05-31：2000→800→1500：
										   ## 自由交战接管 ~3km 内靠近的敌机，不再一点就散开去够 4km 外目标（仍 < leash 1800px）
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
var _formation_offset_committed: Vector2 = Vector2.INF  ## 已采纳的阵型偏移（长机本地系，未旋转）；AircraftFormation 每帧旋进长机当前机体系算实时槽位（强相关，消除"慢一拍"）
var _formation_branch: int = -1  ## 上一帧编队分支(FAR/MID/CLOSE)，分支迟滞用——防 slot_d 在阈值附近逐帧翻转导致 target_heading 跳变（机头颤抖）
var _form_th_ema: float = INF    ## 编队 target_heading EMA（角度感知，滤高频抖；源头治 heading+bank 颤抖）
var _formation_react_timer: float = 0.0  ## 阵型变换反应延迟（每架飞机个体化）
var _formation_blend: float = 1.0  ## 编队托管混合度（0=自主飞行, 1=完全托管）
var _engage_delay: float = 0.0     ## 进入交战前的反应延迟
var _formation_jitter_phase: float = 0.0  ## 个体扰动相位（随机初始化）

# ── 内部状态 ──
var current_waypoint_index: int = 0
var _state: AIState = AIState.PATROL
## EVADE modifier（Phase 2）：与 _state 正交的躲弹模态。true 时分发层短路到
## MissileEvasion.process_evade，背景 _state 保持原值。**只允许 MissileEvasion
## enter_evade/exit_evade 写**——与 aircraft.evasion_mode（planner 油门协作位）的
## 双真值源问题由"同一对进出函数写两者"解决。
var _evading: bool = false
var _engage_timer: float = 0.0           ## 当前交战已持续时间
var _cooldown_timer: float = 0.0         ## 交战冷却剩余
var _scan_timer: float = 0.0            ## 扫描计时器
var _evade_target_pos: Vector2 = Vector2.INF  ## 规避目标位置
var _evade_committed_dir: Vector2 = Vector2.ZERO  ## 规避承诺的 break 方向（一次选定保持，防每帧重选垂直向导致 bank 来回摆）
var _evade_reenter_cd: float = 0.0       ## leash 拽回后的规避再入冷却（防 EVADE↔SQUAD_FOLLOW 0.5s 振荡，2026-07-03）
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

# ── FEAR 状态机（边沿检测 + 解除冷却）──
var _fear_was_active: bool = false      ## 上一帧 FEAR 状态（用于边沿检测）
var _post_fear_no_ab_timer: float = 0.0 ## FEAR 解除后禁加力倒计时（秒）
const POST_FEAR_NO_AB_DURATION: float = 3.0

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

## 该目标是否需要维护 engaging_me 反向索引（spec squad-ai-escort §2.4 集中开关）。
## team0 玩家系：技能反向索引（缠斗恐惧 / 后半球减速光环）依赖，原状保留必须 true。
## 护卫学说编队成员：精英 BOSS 队僚机要反查"谁在咬长机"。
## 杂兵（无 squad 或 squad 未开护卫学说且非 team0）→ false，攻击它们不写 engaging_me。
static func _maintains_engaging_me(target) -> bool:
	if not target is Aircraft:
		return false
	var ac: Aircraft = target
	if ac.team == 0:
		return true
	# squad 引用住在目标自己的 AIController（_ai_ref，由 AIController._ready 回写）
	var sq: Squad = ac._ai_ref.squad if ac._ai_ref else null
	return sq != null and sq.escort_doctrine_enabled

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
	# 维护范围 = _maintains_engaging_me()：team0 玩家系（技能反向索引依赖，原状保留）
	# + 护卫学说编队成员（spec squad-ai-escort §2.4：精英 BOSS 队反杀长机威胁要用）。
	# 杂兵不维护 → 远离 O(N²)。
	if _current_target != _prev_target_for_reverse_idx:
		if is_instance_valid(_prev_target_for_reverse_idx) and _prev_target_for_reverse_idx is Aircraft:
			(_prev_target_for_reverse_idx as Aircraft).engaging_me.erase(aircraft.get_instance_id())
		if is_instance_valid(_current_target) and _maintains_engaging_me(_current_target):
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

	# ── FEAR 边沿 + 解除后禁加力 ──
	# 上升沿：仅记录；下降沿：清战术冷却（立即重选战术 / 归队），开 3s 禁 AB 窗口
	# 禁 AB 用 SLOW 同款写法（status_effects.gd:161），避免 FEAR 一过又全速冲出战场
	# 放在节流门控之前：timer 即使在 throttle skip 帧也照样推进
	var _fear_now: bool = aircraft.status_fear_active
	if _fear_was_active and not _fear_now:
		_post_fear_no_ab_timer = POST_FEAR_NO_AB_DURATION
		_tactic_min_duration = 0.0
		_target_eval_timer = 0.0
	_fear_was_active = _fear_now
	if _post_fear_no_ab_timer > 0.0:
		_post_fear_no_ab_timer -= delta
		aircraft.is_afterburner = false

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

	# ── 玩家亲控休眠（spec squad-control-switching §3.6）──
	# manual_control = true：这架被玩家鼠标操控，AI 完全让位——不写 target_position /
	# 不选战术 / 不设速度高度，由玩家点击接管导航。武器自动开火在 Aircraft 层不受影响。
	if manual_control:
		return

	# ── 降级过渡 grace（spec §3.4 "打完再归队"）──
	# 旧长机被卸下操控后唤醒：grace 期间不强制归队，让正常 AI 延续当前交战；
	# 当前目标打完（combat_target 失效）或计时到 → 融入新长机编队。grace 内不 return，
	# 继续走下面正常 AI（延续交战），只是没归位。
	if _takeover_transition_timer > 0.0:
		_takeover_transition_timer -= delta
		if _takeover_transition_timer <= 0.0 or not is_instance_valid(aircraft.combat_target):
			_takeover_transition_timer = 0.0
			if squad and squad.leader and is_instance_valid(squad.leader) and squad.leader != aircraft:
				aircraft.set_formation_target(squad.leader, squad.get_wingman_target(squad_index))

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

	# ── Phase 2 约束层：区域包含 + 小队 leash 统一执行（分发前，对所有模态生效）──
	# 旧实现散在 zone 块（此处）+ _process_engage leash + process_evade leash 三处拷贝，
	# SEAM-010 根治：现收口 _apply_constraints 单点。
	if _apply_constraints(delta):
		return

	if simple_ai:
		# simple AI 只承袭固定 aggression，不受压力/SA 影响
		aircraft.tactical_aggression = clampf(aggression, 0.0, 1.0)
		# 族群散开：受击时强行中断任何交战追踪，回到 waypoint 分支应用侧向偏移
		if aircraft.flock_scatter_timer > 0.0 and _current_target != null:
			if release_target(TargetSource.TS_SCORED, "flock scatter"):
				aircraft.ai_override_pursuit = false
		_process_simple(delta)
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _evade_reenter_cd > 0.0:
		_evade_reenter_cd -= delta

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
	# Phase 2：加 not _evading 门——躲弹期间背景 _state 可能是 PATROL，此守卫若触发
	# 会把规避机塞回编队托管（LOD1 lerp = 360°/s 扭头旧 bug 复发）
	if _state == AIState.PATROL and not _evading and not bvr_only \
			and squad and is_instance_valid(squad.leader) and not squad.leader.is_destroyed \
			and squad.leader != aircraft:
		enter_squad_follow_state()
		EventLogger.log_event("AI_STATE", _log_name(),
			"auto-enter SQUAD_FOLLOW (spawn init guard, leader=%s)" % squad.leader.callsign)

	# ── 玩家长机传播的护卫规避（spec wingman-escort-evasion §3.1）──
	# 长机按 E 时给僚机置 escort_cover_active（不再直接置 evasion_mode → 否则 planner 的
	# evasion_intent 会让待命僚机也 max+AB 散开飞离）。僚机三分支：
	#   ① 自己真被导弹咬住 → enter_evade 加速逃命（自保优先）
	#   ② 没被威胁 + 无玩家命令 → 召回编队护卫长机（不再自由交战飞远，回槽位待命投护卫 flare）
	#   ③ 没被威胁 + 有玩家命令 → 不拦截，落下方"命令铁律"继续交战（commanded_target 优先）
	if aircraft.escort_cover_active and not _evading \
			and squad and is_instance_valid(squad.leader) and squad.leader != aircraft \
			and not is_boss_attacker():
		# B1 分层门：flare 能兜底就不散开（护卫姿态本来就要求尽量不脱队）
		if MissileEvasion.should_enter_evade(self):
			MissileEvasion.enter_evade(self)
			return
		elif aircraft.commanded_target == null and _state != AIState.SQUAD_FOLLOW:
			# 召回编队待命（与 exit_evade 的归队走同一过渡函数，但不打 EVADE 日志）
			if release_target(TargetSource.TS_SCORED, "escort recall"):
				enter_squad_follow_state()

	# ── EVADE modifier 分发（Phase 2：规避是正交模态，不占 _state 轴）──
	# _evading 由 MissileEvasion 独占进出；期间背景 _state 保持原值，退出时按上下文重定。
	# 位置在铁律之前 = 求生规避优先于命令但有界（B1 定稿）：commanded_target 保留不清，
	# 威胁消失 exit_evade 下一 tick 铁律无缝重接。
	if _evading:
		MissileEvasion.process_evade(self, delta)
		return

	# ── 玩家命令铁律（spec rts-command §3）──
	# 这架机带玩家显式攻击命令(aircraft.commanded_target)且目标存活 → 强制 ENGAGE 它，
	# 绕过评分/编队路由，AI 不得改打别的（逐机持久，跨 1/2/3/4 切控）。
	# 命令目标死/被清 → _enforce 返回 false，自然落回正常 AI（disengage 回编队）。
	# 注：亲控由 controller+planner 管（manual_control 已提前 return）；求生规避优先于命令
	# 但有界（B1 定稿策略）—— 上方 _evading 分发先行让位（不清命令），躲弹入口走
	# should_enter_evade 分层门（flare 能兜底不脱离），威胁消失 exit_evade 下一 tick 重接命令目标。
	if _enforce_commanded_target():
		_process_engage(delta)
		return

	match _state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.SQUAD_FOLLOW:
			SquadCoordination.process_squad_follow(self, delta)

# ══════════════════════════════════════════════
#  模态过渡函数（Phase 2 状态正交化，2026-07-05）
#  所有 _state 写入必须走这三个函数——字段清单唯一化，进出对称由此保证。
#  （EVADE modifier 的进出对 = MissileEvasion.enter_evade/exit_evade，独占 _evading）
# ══════════════════════════════════════════════

## 进入/维持 ENGAGE。前置：目标已由 acquire_target 建立（本函数不碰目标所有权）。
## reset_tactic=true：新交战，重置战术选择；false：软重连/恢复交战
## （BOSS 维持、躲弹后恢复——不打断进行中的 BFM 战术选择）。
func enter_engage_state(reset_tactic: bool = true) -> void:
	_state = AIState.ENGAGE
	_engage_timer = 0.0
	if reset_tactic:
		_tactic = EngageTactic.LEAD_PURSUIT
		_tactic_timer = 0.0
		_tactic_min_duration = MIN_DUR_LEAD_PURSUIT


## 进入 SQUAD_FOLLOW（编队跟随）。snap=false：从 0 开始渐变归队（常规）；
## snap=true：跳过 rejoin 渐变直接落位（玩家 UI 强制切模式用）。
func enter_squad_follow_state(snap: bool = false) -> void:
	_state = AIState.SQUAD_FOLLOW
	_cover_target = null
	_rejoining = not snap
	_formation_blend = 1.0 if snap else 0.0
	aircraft.ai_override_pursuit = false
	aircraft.lod_level = 1


## 进入 PATROL。pick_waypoint=true：设巡逻高度 + 选下一航点（常规脱战）；
## false：调用方自己接管航点（combat_zone 回拉等自带航点的路径）。
func enter_patrol_state(pick_waypoint: bool = true) -> void:
	_state = AIState.PATROL
	aircraft.ai_override_pursuit = false
	if pick_waypoint:
		BFMTactics.set_patrol_altitude(self)
		_set_next_waypoint()


## EVADE modifier 查询（外部读者用；写入只归 MissileEvasion）
func is_evading() -> bool:
	return _evading

# ══════════════════════════════════════════════
#  约束层（Phase 2 · SEAM-010 根治，2026-07-05）
#  横切约束（区域包含 / 小队 leash）统一在分发前执行一次，对所有模态生效——
#  从此加新状态/模态不需要人肉遍历"每个状态各修一遍 leash"。
#  未来 anchor 区域保护（命令轮盘"防守此区"，重构计划 §7.1）在此层接入。
# ══════════════════════════════════════════════

## 玩家命令交战判定（铁律豁免共用：leash / 超距脱离都不得拽回玩家点名的交战）
func _cmd_engage_active() -> bool:
	return aircraft.commanded_target != null \
			and aircraft.commanded_target == _current_target \
			and is_instance_valid(aircraft.commanded_target) and not aircraft.commanded_target.is_destroyed


## 统一约束执行点。返回 true = 本 tick 已被约束接管（调用方直接 return）。
## 在节流之后、simple/全功能分发之前调用（zone 对 simple hunter 生效；leash 不管 simple——
## simple 有自己的 escort tether；drone 的 kamikaze 分支在更上游 return）。
func _apply_constraints(delta: float) -> bool:
	# ── 约束 1：战斗偏好区域（combat_zone containment，hunter UAV 专用）──
	# 锚点是飞机/单位且已被击坠：解除区域，回退到正常 AI（追玩家 / 自由扫描）
	if combat_zone_anchor is CombatUnit and (combat_zone_anchor as CombatUnit).is_destroyed:
		combat_zone_anchor = null
		combat_zone_radius = 0.0
	if combat_zone_anchor != null and is_instance_valid(combat_zone_anchor) and combat_zone_radius > 0.0:
		var zone_center: Vector2 = combat_zone_anchor.global_position
		var self_dist := aircraft.global_position.distance_to(zone_center)
		if self_dist > combat_zone_radius:
			# 出界：强制回返（release 被高优先级拒绝时跳过整段回返）
			if release_target(TargetSource.TS_SCORED, "combat zone exit"):
				enter_patrol_state(false)  # 航点自带（下方 zone_center）
				waypoints = PackedVector2Array([zone_center])
				current_waypoint_index = 0
				aircraft.target_position = zone_center
				if aircraft.flat_altitude and combat_zone_anchor is Aircraft:
					aircraft.set_target_tier((combat_zone_anchor as Aircraft).get_altitude_tier())
				if aircraft.params:
					aircraft.target_speed_kmh = aircraft.params.max_speed
				return true
		elif _current_target != null and is_instance_valid(_current_target):
			var target_dist := _current_target.global_position.distance_to(zone_center)
			if target_dist > combat_zone_radius * COMBAT_ZONE_TARGET_SLACK:
				if release_target(TargetSource.TS_SCORED, "target left combat zone"):
					aircraft.ai_override_pursuit = false

	# ── 约束 2：小队 leash（spec squad-cohesion §3.2，交战/躲弹一视同仁）──
	# 根治"飞着飞着绕一大圈查无此人"（SEAM-010：旧实现散在 _process_engage 与
	# process_evade 两份拷贝，漏一个状态就是一个脱队 bug）。
	# 豁免：simple(有 escort tether) / bvr_only / boss / hunter(zone 管) /
	# 命令铁律（玩家点名打远目标不许拽回；躲弹中无此豁免——保持旧 evade-leash 语义）。
	if simple_ai:
		return false
	var leash_applicable: bool = _evading \
			or (_state == AIState.ENGAGE and not _cmd_engage_active())
	if leash_applicable and squad and is_instance_valid(squad.leader) and squad.leader != aircraft \
			and not bvr_only and not is_boss_attacker() and combat_zone_anchor == null:
		var leash_d := aircraft.global_position.distance_to(squad.leader.global_position)
		if leash_d > effective_squad_leash():
			_squad_leash_timer += delta
			if _squad_leash_timer >= SQUAD_LEASH_HYSTERESIS:
				_squad_leash_timer = 0.0
				if _evading:
					# 躲弹拽回：清 evasion_mode（走入口保边界缩放对称）+ 再入冷却
					# （防威胁仍在时下一 tick 立即重进躲 → EVADE↔SQUAD_FOLLOW 振荡）
					aircraft.set_evasion_mode(false)
					_evade_reenter_cd = MissileEvasion.LEASH_REENTER_SUPPRESS_S
					EventLogger.log_event("AI_STATE", _log_name(),
						"LEASH break-off (evade %.0fpx from leader) → rejoin (evade suppressed %.1fs)" % [
							leash_d, MissileEvasion.LEASH_REENTER_SUPPRESS_S])
					MissileEvasion.exit_evade(self)
				else:
					EventLogger.log_event("AI_STATE", _log_name(),
						"LEASH break-off (%.0fpx from leader) → rejoin" % leash_d)
					TargetSelection.disengage(self)
					# 拽回后设交战冷却，否则归队下一帧又咬同一个远目标 → ENGAGE↔编队反复横跳
					_cooldown_timer = maxf(engage_cooldown, 3.0)
				return true
		else:
			_squad_leash_timer = 0.0
	else:
		_squad_leash_timer = 0.0
	return false

# ══════════════════════════════════════════════
#  目标所有权仲裁（Phase 1 目标仲裁器，2026-07-04，重构计划 §5）
# ══════════════════════════════════════════════
## 四级优先级（大者胜）：commanded > directive > boss/swarm > scored。
## 低优先级请求不得抢占/清除高优先级持有的**存活**目标——终结"谁后写谁赢"：
## 此前 spawner/SwarmDirector/BOSS 的注释都在描述与 AIController 守卫的军备竞赛
## （survivor_spawner ~1917 / swarm_director ~165 / poltergeist ~251），根因就是
## 目标写入无来源标记。目标已死/失效 = 不再受保护（_target_holder_pri 自动降级）。
enum TargetSource { TS_NONE = 0, TS_SCORED = 1, TS_BOSS = 2, TS_DIRECTIVE = 3, TS_COMMANDED = 4 }
var _target_source: int = TargetSource.TS_NONE

const _TS_NAMES := ["none", "SCORED", "BOSS", "DIRECTIVE", "COMMANDED"]


## 当前持有优先级；目标死/失效即不再受保护
func _target_holder_pri() -> int:
	if _current_target == null or not is_instance_valid(_current_target) \
			or _current_target.is_destroyed:
		return TargetSource.TS_NONE
	return _target_source


## 设目标唯一入口：目标字段 + 来源记账 + 归因日志。
## ⚠ 只管目标本身——状态切换/计时器/编队清理等副作用仍由调用方处理（Phase 2 再收口）。
## 返回 false = 被更高优先级持有者拒绝，调用方应放弃本次指派（不要绕过直写！）。
func acquire_target(tgt: CombatUnit, source: int, why: String = "") -> bool:
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return false
	if tgt != _current_target and source < _target_holder_pri():
		return false
	var changed := tgt != _current_target
	_current_target = tgt
	if changed or source >= _target_source:
		_target_source = source
	aircraft.set_combat_target(tgt)
	if changed and (aircraft.team == 0 or aircraft.selected):
		EventLogger.log_event("TARGET_ACQ", _log_name(), "%s ← %s%s" % [
			_log_target_name(tgt), _TS_NAMES[source],
			(" (" + why + ")") if why != "" else ""])
	return true


## 清目标唯一入口：低优先级不得清除高优先级的存活目标。
## 返回 false = 目标受更高优先级保护，调用方应跳过本次清理。
func release_target(source: int, why: String = "") -> bool:
	if source < _target_holder_pri():
		return false
	if _current_target != null and (aircraft.team == 0 or aircraft.selected):
		EventLogger.log_event("TARGET_REL", _log_name(), "%s by %s%s" % [
			_log_target_name(_current_target), _TS_NAMES[source],
			(" (" + why + ")") if why != "" else ""])
	_current_target = null
	_target_source = TargetSource.TS_NONE
	aircraft.clear_combat_target()
	return true


## 玩家命令铁律执行：若本机带存活的 commanded_target，强制/维持对它 ENGAGE，返回 true。
## 命令目标为空/阵亡 → 清除 commanded_target 并返回 false（回正常 AI 目标选择）。
func _enforce_commanded_target() -> bool:
	# ── B1（2026-07-02）：求生规避优先于命令，但有界 ──
	# 躲弹中铁律让位（commanded_target 保留不清），落回 match 派发 process_evade。
	# 有界性：process_evade 每 tick 用带滞回的威胁门重新确认真威胁，威胁消失立即
	# exit_evade → _current_target(=命令目标) 无缝恢复 ENGAGE → 下一 tick 铁律重新接管。
	# 且入口走 should_enter_evade 分层门：flare 能兜底就根本不进 EVADE、不脱离命令。
	# 修复的旧 bug：铁律排在 match 之前无条件拉回 ENGAGE → ENGAGE↔EVADE 按 tick 抖动 +
	# evasion_mode 卡 true（planner 持续 max+AB 武器静默直到玩家重新下令）。
	# Phase 2 后主让位在分发层（_evading 短路先于本函数调用）；此处留防御性双保险。
	if _evading:
		return false
	var cmd: CombatUnit = aircraft.commanded_target
	if cmd == null:
		return false
	if not is_instance_valid(cmd) or cmd.is_destroyed:
		aircraft.commanded_target = null  # 命令目标已亡 → 解除命令，回正常 AI
		return false
	# 设置/维持对命令目标的交战（已在打它就只是空转一次比较）
	if _current_target != cmd or _state != AIState.ENGAGE:
		acquire_target(cmd, TargetSource.TS_COMMANDED, "iron rule")
		aircraft.ai_override_pursuit = true
		if _state != AIState.ENGAGE:
			enter_engage_state()
			aircraft.clear_formation()  # 脱离编队托管去执行命令
	return true

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
				if acquire_target(t, TargetSource.TS_DIRECTIVE, "directive ENGAGE_TARGET"):
					enter_engage_state(false)  # 软进入：不打断已有战术选择
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
		if _current_target != null:
			release_target(TargetSource.TS_SCORED, "simple target invalid")

		# ── SwarmDirector ATTACKER/SHOOTER/DECOY 跳过 orbit 分支 ──
		# Director 已经把 _current_target 设过，但 _process_simple 顶部可能因 target 失效清零；
		# 这里给一个明确兜底：non-GUARD/non-RESERVE 角色不应回 orbit，let _try_engage_simple 重新拉
		var _swarm_skip_orbit: bool = (swarm_role_override == 0 \
				or (swarm_role_override >= 1 and swarm_role_override <= 5))

		# ── 多层轨道环绕（指挥 UAV 编队）──
		# 每架 UAV 按 squad_index 分配不同半径轨道，像行星系统分层环绕
		if not _swarm_skip_orbit and EscortBehavior.is_active(self) and squad.leader != aircraft:
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
						if best_enemy:
							acquire_target(best_enemy, TargetSource.TS_SCORED, "kamikaze nearest enemy")
						else:
							release_target(TargetSource.TS_SCORED, "kamikaze no enemy")

					if _current_target and is_instance_valid(_current_target) and not _current_target.is_destroyed:
						# 目标超出光环范围：放弃追击，返回轨道
						var tgt_to_leader: float = _current_target.global_position.distance_to(leader.global_position)
						if tgt_to_leader > SHIELD_ENGAGE_RANGE:
							release_target(TargetSource.TS_SCORED, "kamikaze target out of shield range")

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
							release_target(TargetSource.TS_SCORED, "kamikaze self-destruct")
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
			# Hunter 0.5s / 护驾 1.0s / 普通 3.0s —— hunter 需要快速重新接敌避免"丢目标 3s 漂走"
			if combat_zone_anchor != null and combat_zone_radius > 0.0:
				_scan_timer = 0.5
			elif orbit_squad_leader:
				_scan_timer = 1.0
			else:
				_scan_timer = 3.0
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
		# 交战期间允许冲到光环边（ESCORT_ENGAGE_RADIUS=1500），脱离后才回 750 轨道
		if self_to_leader > ESCORT_ENGAGE_RADIUS or tgt_to_leader > ESCORT_ENGAGE_RADIUS:
			if release_target(TargetSource.TS_SCORED, "escort tether break"):
				aircraft.ai_override_pursuit = false
				_engage_timer = 0.0
				_simple_orbit_time = 0.0
				_simple_confused = false
				return

	# Hunter 判定：combat_zone 绑定的 simple_ai = boss/Sentinel 的 hunter UAV
	# 全速 + 全前置 + 跳过发呆 + 宽放交战距离上限，给玩家持续压力
	var _is_hunter := combat_zone_anchor != null and combat_zone_radius > 0.0

	# 超出范围或超时脱离（用有效雷达范围 → 高度档位影响 AI 缠斗持续半径）
	# Hunter：用 combat_zone × 1.5 作为脱离距离，与雷达解耦——MQ-110 雷达只 750px 但 hunter 要追远
	var max_range: float
	if _is_hunter:
		max_range = combat_zone_radius * 1.5
	else:
		max_range = (aircraft.effective_radar_range_px() * 1.5) if aircraft.params else 3000.0
	_engage_timer += delta
	if dist > max_range or _engage_timer > engage_duration:
		if release_target(TargetSource.TS_SCORED, "simple disengage (range/timeout)"):
			aircraft.ai_override_pursuit = false
			_engage_timer = 0.0
			_simple_orbit_time = 0.0
			_simple_confused = false
			_simple_orbit_threshold = randf_range(SIMPLE_ORBIT_THRESH_MIN, SIMPLE_ORBIT_THRESH_MAX)
			return

	aircraft.set_combat_target(_current_target)
	aircraft.ai_override_pursuit = true

	# ── 护驾 UAV / Hunter 跳过发呆机制（始终保持追踪） ──
	var _is_sentinel_escort := orbit_squad_leader and shield_leader
	var _skip_fatigue := _is_sentinel_escort or _is_hunter

	if not _skip_fatigue:
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

	# 前置追踪（护驾 UAV / hunter 用更激进的预判系数）
	var tgt_fwd := Vector2(sin(_current_target.heading), -cos(_current_target.heading))
	var closing_speed := maxf(aircraft.speed + _current_target.speed, 1.0) * Aircraft.PIXELS_PER_METER
	var lead_time := dist / closing_speed
	var lead_factor: float
	if _is_sentinel_escort:
		lead_factor = ESCORT_UAV_LEAD
	elif _is_hunter:
		lead_factor = HUNTER_UAV_LEAD
	else:
		lead_factor = REGULAR_UAV_LEAD
	var lead_pos := _current_target.global_position + tgt_fwd * _current_target.speed * Aircraft.PIXELS_PER_METER * lead_time * lead_factor
	# 横向 flank 偏置：让两架同队 hunter 攻击目标不同侧，避免在 lead_pos 收敛重叠
	# 距离衰减：远距(>1500px)满偏 / 近距(<500px)归零，让 AI 贴脸时仍能直瞄开火
	if flank_offset_lateral_px != 0.0:
		var flank_scale: float = clampf((dist - 500.0) / 1000.0, 0.0, 1.0)
		var tgt_right: Vector2 = Vector2(-tgt_fwd.y, tgt_fwd.x)   ## target_fwd 顺时针 90°
		lead_pos += tgt_right * flank_offset_lateral_px * flank_scale

	# ── SwarmDirector 协同覆写（Mother Goose UAV 多轴突击）──
	# ATTACKER_*: dist >2500px 直奔玩家（救回离场 UAV）；dist <2500 + 不在楔形 → 飞楔形攻击点；
	#            在楔形 → 保持 lead_pos 让 simple_combat 走 LEAD_CHASE 开火
	# DECOY: 沿 lane 方向跑路 2000px
	# SHOOTER / GUARD / RESERVE / NONE: 不动 lead_pos，沿用既有 simple_combat 行为
	const SWARM_FERRY_DIST: float = 2500.0   ## 超过此距离的 ATTACKER 直接 beeline 玩家，不走 lane
	if swarm_role_override >= 1 and swarm_role_override <= 4:
		# ATTACKER_N(1) / E(2) / S(3) / W(4)
		var ptgt: Vector2 = _current_target.global_position
		if dist > SWARM_FERRY_DIST:
			## 离场救援：丢弃 lane 直接冲玩家位置（lead_pos 保持上面算好的玩家 lead 前置）
			pass   ## lead_pos 不动，已是玩家 lead 前置点
		else:
			var lane_dir := Vector2(sin(swarm_lane_world_angle), -cos(swarm_lane_world_angle))
			var to_me_v: Vector2 = aircraft.global_position - ptgt
			var to_me_len: float = to_me_v.length()
			var in_wedge: bool = false
			if to_me_len > 1.0:
				var dot: float = lane_dir.dot(to_me_v / to_me_len)
				in_wedge = dot > cos(deg_to_rad(30.0))   ## 楔形半宽 30°
			if not in_wedge:
				## 楔形攻击点收紧到 600~1000px（原 600-1500 范围过远，容易冲出地图）
				var dist_scale: float = lerpf(600.0, 1000.0, clampf(dist / 2000.0, 0.0, 1.0))
				lead_pos = ptgt + lane_dir * dist_scale
			## 在楔形内 → 保持 lead_pos = 纯 lead
	elif swarm_role_override == 5:
		# DECOY: 沿 lane 方向跑（垂直玩家航向），让 director 把 ATTACKER 楔形空位换给别人
		var dec_dir := Vector2(sin(swarm_lane_world_angle), -cos(swarm_lane_world_angle))
		lead_pos = aircraft.global_position + dec_dir * 2000.0

	# ── Railgun 充能稳头守卫 ──
	# fire_along_nose=true 的电磁炮（MQ-112 等）开火方向 = 锁定瞬间机头，charging/awaiting
	# 期间机头乱飘 = 必打偏。检测 equipment_state["railgun"] 的 charging/awaiting_fire，
	# 期间把 target_position 钉到 locked_aim_pos：
	#   charging → 收敛中的路径提前点（RailgunEquipment._nose_lead_point 每 tick 刷新）
	#   awaiting → 冻结的承诺弹道远点（_commit_fire_solution 定死，指示线即发射线）
	var _railgun_aiming: bool = false
	if aircraft.equipment_state.has("railgun"):
		var rs: Dictionary = aircraft.equipment_state["railgun"]
		if rs.get("charging", false) or rs.get("awaiting_fire", false):
			var aim_pos: Vector2 = rs.get("locked_aim_pos", Vector2.ZERO)
			if aim_pos != Vector2.ZERO:
				aircraft.target_position = aim_pos
				_railgun_aiming = true

	# 远程武器站位：贴得太近就往反方向飞，维持狙击距离不打狗斗
	# 旧方案"<standoff 直接飞离"会让机头在 standoff 阈值处来回甩 → 射击 cone 永远不满足。
	# SHOOTER 角色（永远是 standoff 平台）干脆绕开 standoff 又会导致 MQ-112 冲过玩家头顶。
	# 新方案：切向轨道 —— dist < 1.5×standoff 时把 target_position 设在 standoff 圆上、
	# 切向偏置 0.5×standoff 的点。AI 沿弧线绕飞而非反复出/入，机头径向偏 ~27° → 射击 cone 易满足。
	var _joust_handled: bool = false
	if not _railgun_aiming:
		# 攻击跑优先（spec joust-attack-run）：RUN_IN 对准/BREAK 脱离循环接管走位+速度。
		# 切向轨道与"锁定/充能要机头对准"结构矛盾（MQ-112 全场 0 充能死锁，log 183044），
		# joust 机型（MQ-110/112）不再走 standoff 轨道。
		if joust_enabled:
			_joust_handled = JoustController.update(self, delta)
		if not _joust_handled:
			if preferred_standoff_range_px > 0.0 and dist < preferred_standoff_range_px * 1.5 and dist > 1.0:
				var to_me_vec: Vector2 = aircraft.global_position - _current_target.global_position
				var to_me_len: float = to_me_vec.length()
				var radial: Vector2
				if to_me_len > 0.01:
					radial = to_me_vec / to_me_len
				else:
					radial = Vector2(sin(aircraft.heading), -cos(aircraft.heading))
				# 切向方向：与 radial 垂直，选与当前 heading 同侧的方向（避免反复换边震荡）
				var fwd: Vector2 = Vector2(sin(aircraft.heading), -cos(aircraft.heading))
				var tangent_cw: Vector2 = Vector2(-radial.y, radial.x)
				var tangent: Vector2 = tangent_cw if tangent_cw.dot(fwd) >= 0.0 else -tangent_cw
				aircraft.target_position = _current_target.global_position + radial * preferred_standoff_range_px + tangent * (preferred_standoff_range_px * 0.5)
			else:
				aircraft.target_position = lead_pos
	if aircraft.flat_altitude:
		aircraft.set_target_tier(_current_target.get_altitude_tier())
	else:
		aircraft.target_altitude = _current_target.altitude
	# 速度：护驾/hunter 全速，普通 UAV 70%
	# Hunter 自适应：远距 max_speed 闭合，近距 cruise_speed 防止"飞过头不开枪"
	# （buffed UAV 顶速 ~1650 km/h 时 turn radius ~1800m，必须降速才能转弯对准玩家开火）
	# joust 接管时速度已由 JoustController 写好（RUN_IN=cruise / BREAK=max），跳过本段
	if _joust_handled:
		return
	# joust 机型充能稳头期间（_railgun_aiming 钉住机头）：稳定射击平台用巡航速，
	# 不落回 swarm SHOOTER 的 top-speed 策略（充能平台猛加速没意义）
	if joust_enabled and _railgun_aiming:
		aircraft.orbit_speed_cap = 0.0
		aircraft.target_speed_kmh = joust_run_speed_kmh if joust_run_speed_kmh > 0.0 \
				else AircraftPhysics.effective_cruise_speed_kmh(aircraft)
		return
	var speed_ratio: float
	if _is_sentinel_escort or _is_hunter:
		speed_ratio = HUNTER_UAV_SPEED_RATIO
	else:
		speed_ratio = REGULAR_UAV_SPEED_RATIO
	if aircraft.params:
		# SwarmDirector 角色速度策略：
		#   远距 ferry (dist>2500)：max_speed 全速追玩家
		#   近距 ATTACKER：cruise×1.5 保留转弯能力 (max_speed 会冲过头)
		#   SHOOTER：max_speed（赶到能打位置最重要）
		var _swarm_role := swarm_role_override
		var _swarm_is_attacker := _swarm_role >= 1 and _swarm_role <= 4
		var _swarm_is_shooter := _swarm_role == 0
		if _swarm_is_attacker or _swarm_is_shooter:
			var cruise := AircraftPhysics.effective_cruise_speed_kmh(aircraft)
			var top := AircraftPhysics.effective_max_speed_kmh(aircraft)
			if _swarm_is_shooter and preferred_standoff_range_px > 0.0:
				# SHOOTER 速度策略：
				#   远距(>1.5×standoff) → max_speed 闭合
				#   1.0~1.5×standoff   → cruise×1.3（既有能量做圆周运动，又不冲过头）
				#   <standoff          → 跟随目标速度 ×1.1（略快保持外推位 + 不贴脸）
				# 不再用 corner_speed —— 对 1500~2000px 半径的轨道而言 corner_speed 太低，
				# 物理转弯半径远小于 standoff，AI 反而往内冲螺旋
				if dist > preferred_standoff_range_px * 1.5:
					aircraft.target_speed_kmh = top
					aircraft.orbit_speed_cap = 0.0
				else:
					aircraft.target_speed_kmh = minf(cruise * 1.3, top)
					if dist < preferred_standoff_range_px and _current_target is Aircraft:
						# 上限 = 目标速度 × 1.1；floor = cruise × 0.9 防止"悬停感"
						var tgt_kmh: float = _current_target.speed * 3.6 * 1.1
						aircraft.orbit_speed_cap = maxf(tgt_kmh, cruise * 0.9) / 3.6   # → m/s
					else:
						aircraft.orbit_speed_cap = 0.0
			elif _swarm_is_shooter or dist > 2500.0:
				aircraft.orbit_speed_cap = 0.0
				aircraft.target_speed_kmh = top
			else:
				aircraft.orbit_speed_cap = 0.0
				aircraft.target_speed_kmh = minf(cruise * 1.5, top)
		elif _is_hunter and dist < HUNTER_CLOSE_COMBAT_DIST:
			# 近距：用 corner_speed 最大化转弯率，避免 max_speed 1800m turn radius 飞过头不开枪
			aircraft.target_speed_kmh = AircraftPhysics.effective_corner_speed_kmh(aircraft)
		else:
			aircraft.target_speed_kmh = aircraft.params.max_speed * speed_ratio
	else:
		aircraft.target_speed_kmh = 800.0

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
		if acquire_target(best, TargetSource.TS_SCORED, "tether-range engage"):
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
	# Hunter detect range = combat_zone × 1.3，与雷达解耦，让 MQ-110（750px 雷达）也能在
	# 整个 boss 战斗圈内识别玩家；普通 UAV 仍按雷达 × 1.2
	var detect_range: float
	if combat_zone_anchor != null and combat_zone_radius > 0.0:
		detect_range = combat_zone_radius * 1.3
	else:
		detect_range = (aircraft.effective_radar_range_px() * 1.2) if aircraft.params else 2500.0
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
		if tgt_to_leader > ESCORT_ENGAGE_RADIUS:
			return  # 目标超出光环范围才不交战（与 CommanderAura.AURA_RADIUS 对齐）

	if best and best_dist < detect_range:
		if acquire_target(best, TargetSource.TS_SCORED, "simple scan"):
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

	# 巡逻中也只在真有来袭导弹时才规避（同 ENGAGE：should_enter_evade 做门，
	# 否则 evade_missiles=true 的巡逻机每 tick 空转 enter_evade ↔ exit_evade 抖动；
	# B1 分层门：玩家方 flare 能兜底就不进运动学规避）
	if evade_missiles and personality.missile_aware and not is_boss_attacker() \
			and MissileEvasion.should_enter_evade(self):
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
func _is_target_already_squad_engaged(target: CombatUnit) -> bool:
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

	# ── 玩家命令铁律（spec rts-command §3 / memory player-command-iron-rule）──
	# 本机带存活的 commanded_target 且正打它 → 这是玩家显式下达的交战。下面两条"自动"规则
	# （leash 距长机太远拽回 / 超雷达距脱离）都不得覆盖它：否则 _enforce_commanded_target 每帧
	# 强制 ENGAGE ↔ 这里每帧 disengage → 状态 thrash，僚机既不飞 BFM 也不回编队（日志实证：
	# 平飞、不追随长机、DISENGAGE engaged 0.0s 刷屏，距长机 2000px 永不收敛）。
	# 玩家点名打远目标 = 允许脱编队全力扑上去，距离/leash 一律让位。
	var _cmd_engage: bool = _cmd_engage_active()
	# 小队 leash 已上收到 _apply_constraints 约束层（Phase 2，分发前统一执行）——
	# 本函数不再持有 leash 拷贝；_cmd_engage 仍供下方"超距脱离"豁免使用。

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
					# ⚠ 不调 disengage：enter_evade 已置 _evading modifier + 清 combat_target，
					# 但保留 _current_target → exit_evade 防御结束后无缝恢复同一目标。
					# 调 disengage 会 null 掉 _current_target + 设 15s 冷却 → 防御后被迫重新选目标
					# （常是 180° 外的另一架）→ 机身大坡反转 churn（SEAM-012 真实战斗残留根因之一）。
					MissileEvasion.enter_evade(self)
					_me.activate()
					var fwd := Vector2(sin(aircraft.heading), -cos(aircraft.heading))
					aircraft.target_position = aircraft.global_position + fwd * EVASION_TARGET_DIST
					return

	# ── 导弹规避（需要飞行员察觉 + 受 self_preservation 影响） ──
	# BOSS 攻击手不做导弹规避——他们有热诱弹和隐形防御，任务是死追玩家
	# ⚠ 必须先过 should_enter_evade 分层门才 roll 规避：
	#   evade_missiles 是静态配置位（多数机型常 true），不是"有导弹"信号。缺这道门时
	#   randf 每个 ENGAGE tick 空转触发 enter_evade → process_evade 无弹立即 exit → 回 ENGAGE
	#   → 再触发 …… 形成 enter/exit 抖动（实测 evade 进入 18→588）。旧代码靠 disengage 的 15s
	#   冷却把飞机踢出 ENGAGE 才意外压住，但代价是"躲完丢目标重咬另一架 → 大坡反转"churn。
	#   B1 分层门（2026-07-02）：玩家方 flare 能兜底 → 不进运动学规避，继续交战/执行命令。
	if evade_missiles and personality.missile_aware and not is_boss_attacker() \
			and MissileEvasion.should_enter_evade(self):
		# 低自保飞行员可能忽略来袭导弹继续攻击
		var evade_chance := lerpf(0.3, 1.0, _effective_self_preservation())
		if randf() < evade_chance or _state != AIState.ENGAGE:
			# ⚠ 不调 disengage（见上方机炮防御注释）：保留 _current_target → 躲完导弹由
			# exit_evade 无缝恢复同一交战。避免"每次躲弹都丢目标 → 重新咬另一架 → 大坡反转"churn。
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
	# 命令铁律：_cmd_engage（玩家点名的目标）同样永不因距离脱离——玩家要打多远就追多远
	# flat_altitude=true（生存模式）下距离判定忽略高度差
	if is_boss_attacker() or _cmd_engage:
		pass  # BOSS 攻击手 / 玩家命令目标跳过距离脱离
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
	# 玩家命令铁律：本机带存活 commanded_target 时跳过独立重评估，AI 不得改打别的。
	var _has_cmd: bool = aircraft.commanded_target != null \
			and is_instance_valid(aircraft.commanded_target) and not aircraft.commanded_target.is_destroyed
	var eval_interval := lerpf(TARGET_EVAL_INTERVAL_MIN, TARGET_EVAL_INTERVAL_MAX, focus)  # 低专注=3秒重评，高专注=10秒
	if not _has_cmd and _target_eval_timer >= eval_interval:
		_target_eval_timer = 0.0
		TargetSelection.reevaluate_target(self)

	# ── 攻击跑（joust，骑士型 Lancer 统一实现；spec joust-attack-run）──
	# RUN_IN 对准冲锋 → BREAK 脱离拉开 → 折返循环，取代"engage_duration 定时器伪打带跑"。
	# 防御行为（Herbst 反咬 / 躲弹 / 机炮防御）的 return 都在上方——防御永远压过攻击跑；
	# 目标重评估保留在上方。武器（机炮锥门/导弹锁定）由 Aircraft 系统在对准姿态下自然开火。
	if joust_enabled and JoustController.update(self, delta):
		aircraft.ai_override_pursuit = true
		current_tactic_name = "JOUST_RUN_IN" if _joust_phase == JoustController.Phase.RUN_IN else "JOUST_BREAK"
		return

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
