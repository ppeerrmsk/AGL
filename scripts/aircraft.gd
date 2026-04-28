class_name Aircraft
extends CombatUnit

@export var params: AircraftParams
@export var initial_heading_deg: float = 0.0  ## 度 初始航向（0=北, 90=东, 180=南）

# --- 状态 ---
var vertical_speed: float = 0.0     ## m/s
var bank_angle: float = 0.0         ## 弧度
var _committed_turn_sign: float = 0.0  ## 转弯方向锁定：0=未锁定, +1/-1=锁定方向
var g_load: float = 1.0
var is_stalled: bool = false
var _stall_recovery_timer: float = 0.0  ## 失速恢复冷却（防止反复失速抽搐）
## 死亡溯源：take_bullet_damage 在致死的那一击设为 true
## survivor_spawner._detect_kills 据此判断是否触发"机炮击杀恐惧"AOE
var _killed_by_bullet: bool = false
## 玩家专属：机炮击杀附近敌机时给他们注入恐惧的半径，0=未升级
var gun_kill_fear_radius: float = 0.0
## 玩家专属：恐惧衰减率（stress / 秒）。值越小持续越长。0=未升级
var gun_kill_fear_decay_rate: float = 0.0

# --- 目标 ---
var target_position: Vector2 = Vector2.INF  ## 世界坐标, INF=无目标
var keep_target_on_arrival: bool = false    ## true=外部管理target_position，到达时不清除

## ── 预测路径缓存（世界坐标，用于 UI 预测线/航向箭头的稳定渲染）──
## 关键原则：一旦算出就锁定在世界坐标里不动，直到真正需要才重算。
## 原因：每帧重仿会受 Forward Euler 积分固有振荡 + bank 反馈控制环的影响，仿真器
## 本身就有 ±10px 级别的输出抖动，靠低通/平均都压不掉（那是主信号的一部分）。
## 解法：事件驱动重算 —— 目标变了 / 飞机偏离路径 / 缓存快消耗完 才重算。
## 平时每帧只做 O(N) 的 trim（找最近缓存点往前截取），零仿真 → 零抖动。
var predicted_path_cache: PackedVector2Array = PackedVector2Array()
var predicted_path_target: Vector2 = Vector2.INF
var predicted_path_cancel_reached: bool = false
var predicted_path_progress_idx: int = 0          ## 飞机在缓存上的位置（单调递增，防止绕圈时闪烁）
const PREDICTED_PATH_RETARGET_THRESHOLD := 20.0   ## 目标偏移超过此值触发重算
const PREDICTED_PATH_DRIFT_THRESHOLD := 90.0      ## 飞机离最近缓存点超过此值（实际物理偏离预测）触发重算
const PREDICTED_PATH_MIN_REMAINING := 12           ## 从飞机最近点到缓存末尾剩余点数不足时触发重算
const PREDICTED_PATH_SEARCH_WINDOW := 30          ## progress_idx 附近的前瞻搜索窗口（不全局扫描，避免绕圈路径闪烁）
var formation_mode: bool = false            ## true=编队托管模式，直接复制长机状态
var _formation_leader: Aircraft = null      ## 编队长机引用（formation_mode时使用）
var _formation_blend: float = 1.0           ## 编队混合度（0=自主, 1=完全托管，用于过渡）
var _formation_jitter_phase: float = 0.0    ## 个体扰动相位
var target_altitude: float = 5000.0
var target_speed_kmh: float = 900.0  ## km/h, 玩家/AI设定
var target_altitude_tier: int = AltitudeTier.MID   ## 目标高度档位（flat_altitude时使用）

# --- 选择 ---
var selected: bool = false

# --- 光学隐形（F-47 BOSS 专用） ---
var is_cloaked: bool = false          ## 当前是否处于隐形状态
var _cloak_alpha: float = 1.0        ## 渲染透明度（1.0=可见, 0.0=完全隐形）
var suppress_flares: bool = false     ## 抑制热诱弹释放（隐形 CD 已好时由 BOSS 管理器设置）
var bullet_immune: bool = false       ## 子弹完全免疫（BOSS 专属：子弹穿过不造成伤害）
var invulnerable: bool = false        ## 全免伤（用于起飞甲板/出场无敌窗口；导弹与机炮伤害都吃掉）
var boss_flare_immunity: bool = false ## BOSS 释放热诱弹后也享有导弹穿透无敌时间
var infinite_ammo: bool = false       ## 无限弹药（机炮+导弹永不耗尽）
var prefer_gun_mode: bool = false     ## 强制优先机炮模式（近距纠缠组用）

# --- 燃油 / 加力 ---
var fuel: float = 3000.0
var is_afterburner: bool = false
var _ab_cooldown: float = 0.0        ## 加力状态切换冷却

# --- 战斗 ---
var combat_target: CombatUnit = null  ## 锁定追踪的敌机/地面单位
var is_firing: bool = false
var ammo: int = 500
# 自动扫描机炮目标的节流计时器：60Hz 扫描无意义，且每次扫描都是 O(N) 遍历全场单位
var _auto_gun_scan_timer: float = 0.0
var _fire_cooldown: float = 0.0
var _gun_lead_heading: float = 0.0  ## 前置射击方向（由 _update_combat 计算）
var _in_rear_hemisphere: bool = false  ## 是否处于敌机后半球（由 _update_combat 计算）
var _overshoot_timer: float = 0.0   ## 近距过顶 extension 计时（秒），>0 时强制沿机头直飞脱离
var ai_override_pursuit: bool = false  ## AI 战术机动时跳过自动追踪，由 AI 直接控制 target_position
var bullet_manager: Node2D = null   ## 由 main.gd 注入
var missile_manager: Node2D = null  ## 由 main.gd 注入

# --- 火箭弹（无制导副武器） ---
var rockets_remaining: int = 0
var _rocket_burst_cooldown: float = 0.0  ## 齐射冷却
var _rocket_queue: Array[Dictionary] = []  ## 待发射火箭队列 { delay: float, heading: float, pos: Vector2 }

# --- 导弹 ---
enum WeaponMode { MISSILE, GUN }
var weapon_mode: int = WeaponMode.GUN
var missiles_remaining: int = 0
var secondary_missiles_remaining: int = 0  ## 副导弹（空对地等）剩余数
var _missile_cooldown: float = 0.0
var _sfx_gun_cd: float = 0.0  ## 机炮音效节流（每 0.5s 最多一次），防扫射刷声道
var _crank_timer: float = 0.0          ## 发射后保持照射计时（秒），> 0 时飞机维持稳定航向
const CRANK_DURATION: float = 8.0      ## 发射后保持照射的时长
const LOCK_STABLE_BUFFER: float = 1.0  ## 锁定后额外稳定时间才允许发射（AI）

# --- 近距过顶（extension）常量已搬到 scripts/aircraft/aircraft_combat_tracking.gd ---

# 诊断：玩家有目标但无法开火时节流日志
var _msl_block_log_timer: float = 0.0
var _msl_last_block_reason: String = ""
const MSL_BLOCK_LOG_INTERVAL: float = 2.0  ## 最多每 2 秒记录一次阻塞原因

# 诊断：玩家机炮追击决策追踪（仅 use_tactical_preference=true 时写入）
# 设计意图见 docs/changelogs/player-ai-log.md — 用于复现"绕圈方向错"类 bug
# 不触发任何行为变化，纯观测。节流 0.5s 一次快照，分支切换立即打点。
var _pursuit_branch: String = ""              ## 上一帧选中的追击分支名
var _pursuit_log_timer: float = 0.0           ## 快照节流
var _pursuit_last_turn_sign: float = 0.0      ## 上次观察到的 _committed_turn_sign
# PURSUIT_LOG_INTERVAL 已搬到 scripts/aircraft/aircraft_combat_tracking.gd

# 诊断：高 G 机动物理采样（AC_TICK 事件）
# 用于调查"激烈机动时飞机颤抖"bug —— 详见 docs/changelogs/player-ai-log.md 2026-04-20 (6)
# 触发条件（OR）：Herbst/Cobra 机动激活中 / |bank| > 60° / _overshoot_timer > 0
# 10Hz 节流，正常巡航零日志污染，激烈机动时以 0.1s 粒度采样位姿，能看出 60Hz 亚帧颤抖的能量
var _ac_tick_log_timer: float = 0.0
const AC_TICK_LOG_INTERVAL: float = 0.1
const AC_TICK_BANK_THRESHOLD := 60.0  # deg

# Bank 翻转抗振守卫阈值 / 失速物理 / 空气密度常量 已搬到 scripts/aircraft/aircraft_physics.gd

# --- 导弹装填（生存模式）---
var enable_missile_reload: bool = false     ## 生存模式启用自动装填
var _missile_reload_active: bool = false
var _missile_reload_timer: float = 0.0
var missile_reload_duration: float = 20.0   ## 装填总时间（可通过升级缩短）
var missile_reload_progress: float = 0.0    ## 0.0-1.0, HUD 读取用

# --- 机炮攻击提交（生存模式导弹优先）---
## 进入机炮模式向目标发起攻击时锁定为 true，完成这次攻击（飞过目标）前不切回导弹模式
## 防止导弹装填好的瞬间中途切换，造成攻击跑断
var _gun_pass_committed: bool = false

# --- 多目标锁定（生存模式升级）---
var max_simultaneous_locks: int = 1

## 战术偏好模式下是否自动发射导弹（玩家可在战术面板切换）
## ON（默认）：齐射路径自动挑所有锁定目标开火（多锁升级生效）
## OFF：只对玩家手动指定的 combat_target 发射，但锁定成功仍自动开火
##      —— 节流由 `_missile_cooldown` + `count_active_missiles_at <= 1` 承担，
##      不需要"一次点击一发"守卫（2026-04-24 (3)，详见 player-ai-log.md）
var missile_auto_fire: bool = true

## 是否允许机炮/火箭弹自动射击空中目标
## false 时 _auto_gun_scan 跳过所有 Aircraft 候选 —— 用于对地专用机型（AH-64 等）
## 这与 AIController.ground_combat_only 配合：后者防止选空中 combat_target，
## 前者防止 combat_target 为空时自动扫射路过的空中单位
var attack_air_targets: bool = true

# --- 击毁 ---
var _destroy_timer: float = 0.0
var _destroy_spin: float = 0.0      ## 坠落旋转速度（heading 偏航）
var _destroy_bank_rate: float = 0.0  ## 坠落滚转速度（仅轰炸机侧翻用）

# --- 族群散开（Adds 直升机专用：受击时编队解体 + 扭转闪避）---
## > 0 时 AIController 在 simple_ai 的 waypoint 分支会对目标点施加时变侧向偏移，
## 模拟直升机急停侧跨 + 左右 jink 摆动，且中断任何正在进行的交战
const FLOCK_SCATTER_DURATION: float = 3.5  ## 散开总时长（秒）
var flock_scatter_timer: float = 0.0
var flock_scatter_dir: Vector2 = Vector2.ZERO
## 队友引用（flock_members[0..N-1] 共享同一数组）
## set_meta("scatter_on_damage", true) 时，_apply_damage 会向所有队友传播 scatter
var flock_members: Array[Aircraft] = []

# --- 雷达 ---

# --- 热诱弹 ---
var flares_remaining: int = 0
var _flare_cooldown: float = 0.0
var _flare_particles: Array[Dictionary] = []  ## { pos: Vector2, vel: Vector2, life: float, bright: bool }
var _flare_spawn_queue: Array[Dictionary] = []  ## 待释放粒子队列 { delay: float, heading: float, pos: Vector2 }
var _flare_ignored_missiles: Dictionary = {}  ## 失误判定已拒绝的导弹 { instance_id: true }
var _flare_ignored_cleanup: float = 0.0       ## 清理计时器
var flares_guaranteed: bool = false  ## 生存模式：玩家热诱弹 100% 干扰
var enable_flare_reload: bool = false  ## 生存模式：热诱弹用完后自动装填
var flare_reload_progress: float = 0.0  ## 0.0-1.0, HUD 读取用
## 热诱弹释放后的导弹穿透窗口（秒）。>0 时所有导弹的近炸引信判定跳过此单位，
## 用于解决"已被干扰的导弹靠惯性直飞穿过慢速玩家"的问题。
## 只对 flares_guaranteed 的玩家生效（在 AircraftFlares.release 中启动）
## MISSILE_PHASE_DURATION 常量已搬到 aircraft_flares.gd；cobra/herbst 直接写此 timer
var missile_phase_timer: float = 0.0
var enable_gun_reload: bool = false      ## 生存模式：机炮弹药耗尽后整匣装填
var _gun_reload_active: bool = false
var _gun_reload_timer: float = 0.0
var gun_reload_duration: float = 25.0    ## 装填总时间（比导弹略久；可通过升级缩短）
var gun_reload_progress: float = 0.0     ## 0.0-1.0, HUD 读取用
var infinite_fuel: bool = false      ## 生存模式：无限燃油
var orbit_speed_cap: float = 0.0     ## AI 轨道限速（m/s），0=不限制。由 AIController 设置
var bullet_dodge_chance: float = 0.0  ## 机炮弹丸闪避概率（装甲强化升级）
var lock_resistance_mult: float = 1.0  ## 雷达锁定抗性（强化吊舱升级，每层 ×1.35），敌人对我累积锁定速率 ÷此值
var altitude_authority_mult: float = 1.0  ## 高度操纵权威（云雾机动战区奖励），_update_altitude 三处同步放大
var cloud_lock_stealth: bool = false      ## 云雾隐身（云雾机动战区奖励）：云中任意高度档 lock_rate ×0.1
var ecm_range_mult: float = 1.0           ## ECM 吊舱（战区奖励）：敌人雷达对我的有效距离 × 此值（0.75 = 缩短 25%）
var xp_multiplier: float = 1.0            ## 经验倍率（xp_mult 升级）：击杀获得 XP × 此值，硬顶 1.4
# ── 战区奖励 v2 ──
## 冲击吸收（战区奖励）：受到 ≥2 dmg 时，floor(dmg × SHOCK_ABSORB_RATIO) HP 缓慢回复
## 一击致死时不触发（必死）。1 dmg 时 floor(0.4)=0，自然不触发。
var shock_absorb_active: bool = false
var shock_absorb_pending: float = 0.0     ## 待回复的 HP 池
const SHOCK_ABSORB_RATIO: float = 0.4
# SHOCK_ABSORB_RATE 已搬到 scripts/aircraft/aircraft_physics.gd
## 眼镜蛇机动（机动轴常规升级，单层）：
## 仅在 evasion_mode=ON 时生效；玩家被来袭导弹/后方机炮追尾时自动触发。
## 触发后 cobra 提供 ~3.3 秒无敌窗口（PITCH+HOLD+RECOVER+POST_IMMUNITY），
## 期间 _update_flares 已有的 `if _mf.is_active: return` 守卫保证不浪费 flare。
var cobra_skill_active: bool = false
var _cobra_skill_cooldown: float = 0.0
const COBRA_SKILL_COOLDOWN: float = 25.0    ## 自动触发间冷却
const COBRA_MISSILE_TRIGGER_PX: float = 300.0   ## 来袭导弹近到此距离才触发（接近命中那一刻）
const COBRA_TAIL_DETECT_PX: float = 900.0       ## 后方追尾敌机此距离内 + 正在开火即触发
## 侩子手（战区奖励）：2 杀触发首层，之后每多 1 杀 +1 层（max 5）
## 公式：stacks = clamp(kills - 1, 0, 5)
##   kills=0,1 → 0；kills=2 → 1；kills=3 → 2；kills=4 → 3；kills=5 → 4；kills=6+ → 5
## 受到任意伤害立即清零所有层数 + 计数
var executioner_active: bool = false
var executioner_kills: int = 0            ## 自上次受伤以来的击杀数
var executioner_stacks: int = 0           ## 当前层数 0-5
const EXECUTIONER_FIRST_STACK_KILLS: int = 2  ## 首层所需击杀数（之后每杀 +1 层）
const EXECUTIONER_MAX_STACKS: int = 5
var flare_lock_immunity: float = 0.0  ## 释放热诱弹后的锁定免疫时间（秒）
var _lock_immunity_timer: float = 0.0  ## 当前剩余锁定免疫时间
var kill_heal_amount: float = 0.0     ## 击杀敌机时回复的HP
var gun_extra_barrels: int = 0        ## 额外机炮管数（多管齐射进化）
var missile_bounce_count: int = 0     ## 导弹弹跳次数（连锁弹头进化）
var missile_proximity_aoe: bool = false  ## 近炸引信进化：导弹爆炸产生 AOE
var gun_ciws_active: bool = false        ## 近防炮进化：自动拦截正面来袭导弹
var _ciws_cooldown: float = 0.0          ## CIWS 射速冷却（独立于正常机炮）
var survivor_missile_damage_cap: float = 0.0  ## 生存模式：导弹伤害上限（0=不限制）
var survivor_bullet_damage_cap: float = 0.0   ## 生存模式：机炮伤害上限（0=不限制）
var hide_data_label: bool = false    ## 隐藏飞机旁的数据标签（HUD 替代显示）

# --- 视觉提示：敌方机炮锥威胁显示 ---
## 敌方对玩家持续 weapon_mode==GUN 锁定时累计；≥0.3s 触发显示机炮射界锥
## 条件不满足立即归零（hysteresis 防 weapon_mode GUN/MISSILE 抖动闪锥）
var _gun_threat_timer: float = 0.0
const GUN_THREAT_DISPLAY_DELAY: float = 0.3
const GUN_THREAT_RANGE_MULT: float = 1.5

# 锁定红线状态已搬到 CombatUnit 基类（飞机/SAM/海军共用）
# Aircraft 仅覆写 _lock_line_can_engage_player 与触发 fire 通知


# --- 战术偏好（生存模式玩家手动控制）---
enum WeaponPreference { PREFER_MISSILE, PREFER_GUN }
enum AltitudePreference { PREFER_CLIMB, PREFER_LOW }

var use_tactical_preference: bool = false       ## 启用战术偏好系统（仅玩家飞机）
## P1：启用新版 TacticalPlanner 决策路径（仅玩家飞机）。开启后 _physics_process 顶层调 planner，
## update_weapon_mode / update_combat / update_energy_management 全部 early-return 不再各自决策，
## 玩家飞机的 target_position / target_speed / weapon_mode / is_firing 由 plan 统一写入
var use_tactical_planner: bool = false
var _last_plan: TacticalPlan = null              ## P1：上一帧 plan，便于 update_missile 等读 allow_*_fire
## P2：BFM intent 状态保持，防止边界附近高频翻转
var _bfm_prev_intent: int = -1                   ## 上次 plan 选定的 intent（TacticalPlan.Intent）
var _bfm_intent_started_at: float = 0.0          ## 当前 intent 开始时间（Time.get_ticks_msec/1000）
## P2：EXTEND_RECOVER 计时戳，未到此时刻前 planner 强制保持 EXTEND
var _bfm_extend_until: float = 0.0
## 战术激进度 [0..1]：
##   - 1.0 = 完全激进（解除 G 限制，维持角点速度，最小转弯半径）
##   - 0.0 = 保守（沿用原 70% 持续 G 限制与 turn_slow_speed 能量策略）
##   - 默认 1.0，保证没有 AI 的玩家飞机（survivor 模式）开箱即用最激进
##   - AI 控制器每帧根据 effective_skill × aggression 写入此值，使沙盒 AI 随飞行员属性调整
var tactical_aggression: float = 1.0
var weapon_preference: int = WeaponPreference.PREFER_MISSILE
## 飞行员射击精度（仅玩家用）：0=新手 ±5°lead 误差，1=王牌 ±0.5°
## 由 gun_accuracy 升级 / PlayableAircraft.base_pilot_aim_skill 推升
var pilot_aim_skill: float = 0.3
## 每次火控窗口（is_firing false→true 边沿）抽一次 lead 偏移，整个 burst 共用
var _gun_aim_offset_rad: float = 0.0
var _was_gun_firing: bool = false
var altitude_preference: int = AltitudePreference.PREFER_CLIMB
var evasion_mode: bool = false
## 冲锋攻击：玩家快速双击敌人触发。强制机炮模式 + 屏蔽导弹自动发射，专注当前目标
## 速度由现有战斗逻辑（aircraft_physics.update_energy_management 机炮分支）按距离自适应
## 自动清除：set_combat_target / clear_combat_target 默认清零，由调用方（survivor_mode）在双击时显式置 true
var charge_attack: bool = false
## 玩家右键长按急刹：油门归零 + 跳过失速安全余量，让飞机一路减速到失速坠落
## 期间保持航向（target_position = INF 让 update_bank 回正），加力强制关闭
var hard_brake: bool = false
var _evasion_override: bool = false             ## 玩家手动点击临时覆盖规避
var _evasion_sway_timer: float = 0.0            ## S型机动计时器
var _evade_roll_phase: float = 0.0              ## 规避原地滚转相位（弧度，绘制时叠加到 bank）
var _evade_roll_remaining: float = 0.0          ## 当前滚转动画剩余秒数
var _evade_roll_cooldown: float = 0.0           ## 下次触发滚转的冷却秒数
var _evade_last_missile_id: int = 0             ## 上次触发滚转的来袭导弹实例 id（避免同一导弹重复触发）

const _EVADE_ROLL_DURATION: float = 1.4         ## 单次滚转动画时长（秒，约 1 圈）
const _EVADE_ROLL_COOLDOWN: float = 1.2         ## 两次滚转之间的冷却
const _EVADE_ROLL_TRIGGER_PX: float = 700.0     ## 来袭导弹接近到此距离才触发滚转

# ── 失速物理 / 空气密度 ──
# 已搬到 scripts/aircraft/aircraft_physics.gd（STALL_DIVE_RATE_*, STALL_BANK_*, AIR_DENSITY_SCALE_M）

# ── 追踪提前量 / 机炮追踪 / 地面攻击 / 武器模式切换 常量已搬到 scripts/aircraft/aircraft_combat_tracking.gd ──

# ── 规避 ──
const HIGH_DODGE_THRESH := 0.5                   ## 高闪避率阈值（触发延长冷却）
const BOSS_EVADE_ROLL_CD := 4.0                  ## BOSS 规避滚转冷却（秒）
const DEFAULT_LOCK_TIME := 3.0                   ## 默认锁定时间（威胁评估用）

# ── 热诱弹粒子常量 ──
# 已搬到 scripts/aircraft/aircraft_flares.gd（含 MISSILE_PHASE_DURATION 和 FLARE_*）

# ── 坠毁动画 ──
const BOMBER_CRASH_DURATION := 5.0               ## 轰炸机坠落时长（秒）
const BOMBER_YAW_SPIN_RANGE := 0.8               ## 轰炸机偏航范围（±）
const BOMBER_ROLL_RATE_MIN := 1.8                ## 轰炸机侧翻速率下限
const BOMBER_ROLL_RATE_MAX := 2.6                ## 轰炸机侧翻速率上限
const BOMBER_DESCENT_MPS := 180.0                ## 轰炸机下坠速率（m/s）
const BOMBER_SPEED_DECAY := 15.0                 ## 轰炸机减速率（m/s²）
const BOMBER_MIN_SPEED := 60.0                   ## 轰炸机最低坠落速度（m/s）
const BOMBER_MOVE_SCALE := 0.7                   ## 轰炸机水平移动缩放

const HELI_CRASH_DURATION := 3.5                 ## 直升机坠落时长（秒）
const HELI_YAW_SPIN_RANGE := 6.0                 ## 直升机偏航范围（±）
const HELI_ROLL_RATE_RANGE := 0.6                ## 直升机滚转范围（±）
const HELI_DESCENT_MPS := 220.0                  ## 直升机下坠速率（m/s）
const HELI_SPEED_DECAY := 30.0                   ## 直升机减速率
const HELI_MIN_SPEED := 20.0                     ## 直升机最低速度
const HELI_MOVE_SCALE := 0.3                     ## 直升机水平移动缩放

const FIGHTER_CRASH_DURATION := 3.0              ## 战斗机坠落时长（秒）
const FIGHTER_YAW_SPIN_RANGE := 4.0              ## 战斗机偏航范围（±）
const FIGHTER_DESCENT_MPS := 300.0               ## 战斗机下坠速率（m/s）
const FIGHTER_SPEED_DECAY := 20.0                ## 战斗机减速率
const FIGHTER_MIN_SPEED := 50.0                  ## 战斗机最低速度

# --- LOD ---
var lod_level: int = 0  ## 0=完整, 1=简化（编队僚机巡航）, 2=最小化（屏幕外）
var _lod_frame: int = 0  ## LOD 帧计数器

# --- 云层状态缓存（每帧更新，供渲染/其它系统查询）---
## 0=晴空 / 1=云下方（LOW/MID，头顶有云投影）/ 2=云中（HIGH，享受 buff）
var cloud_state: int = 0
var cloud_density: float = 0.0  ## 对应状态处采样到的密度，0~1
var _cloud_state_accum: float = 0.0  ## 节流计时

# --- 建筑状态缓存（LOW 档位 + 飞机所在位置在街区内时为 true）---
## 物理用 → max_speed × 0.85；导弹/子弹用 → "shooting from inside cluster" 判定
var in_building: bool = false
var _in_building_accum: float = 0.0  ## 节流计时（0.2s 一次）

# --- 能量管理（PE↔KE 转换）---
## 上一帧的 altitude，用于计算 dh/dt（爬升 → 损失速度，俯冲 → 增加速度）
var _prev_altitude_for_pe: float = 5000.0

# --- 编队调试（survivor_mode F11 切换）---
## 打开后会缓存 LOD 1 编队分支的中间状态并在 _draw 中渲染调试覆盖层。
## 仅用于排查"机头乱扭"类问题，正常游戏请保持 false。
var formation_debug: bool = false
var _dbg_branch: String = ""        ## CLOSE / MID / FAR / OFF
var _dbg_slot_pos: Vector2 = Vector2.INF
var _dbg_slot_dist: float = 0.0
var _dbg_slot_heading: float = 0.0  ## 槽位方位角
var _dbg_blended_heading: float = 0.0  ## 中距分支的混合目标航向
var _dbg_target_heading: float = 0.0  ## 实际写入 lerp_angle 的目标航向
var _dbg_hdiff: float = 0.0
var _dbg_desired_bank: float = 0.0
var _dbg_blend_ratio: float = 0.0
var _dbg_chase_target_kmh: float = 0.0
var _dbg_log_timer: float = 0.0    ## 控制台限频打印计时器

# --- 战术提示弹窗 ---
var _tactic_popup_text: String = ""
var _tactic_popup_timer: float = 0.0
const TACTIC_POPUP_DURATION: float = 2.0  ## 提示显示时长（秒）

var _trail_ribbon: TrailRibbon

## 清空飞行轨迹（传送/瞬移时调用，避免丝带跨越穿帮）
func clear_trail() -> void:
	if _trail_ribbon:
		_trail_ribbon.clear_trail()

func _ready() -> void:
	# 分配唯一 callsign
	if callsign == "":
		callsign = CallsignDB.allocate()
	speed = 250.0  # 默认速度 m/s（会被 params 覆盖）
	altitude = 5000.0  # 默认高度
	hp = 100.0
	heading = deg_to_rad(initial_heading_deg)
	rotation = heading
	if params:
		_publish_equipment_to_legacy()
		hp = params.max_hp
		speed = params.cruise_speed / 3.6  # km/h -> m/s
		target_speed_kmh = params.cruise_speed
		fuel = params.fuel_capacity
		if params.gun:
			ammo = params.gun.max_ammo
		if params.rocket:
			rockets_remaining = params.rocket.max_ammo
		if params.missile:
			missiles_remaining = params.missile.max_count
		if params.secondary_missile:
			secondary_missiles_remaining = params.secondary_missile.max_count
		if params.flare:
			flares_remaining = params.flare.max_flares
	# 轨迹丝带
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 8.0
	_trail_ribbon.max_points = 360
	# 尾迹渲染在飞机图标之下，避免彩带盖住机身（尤其是轰炸机这种大尺寸图标）
	_trail_ribbon.show_behind_parent = true
	_trail_ribbon.ribbon_color = GameConstants.team_trail_color(team)
	add_child(_trail_ribbon)

## 装备模块化迁移期兼容层（commit 2/13 起逐步扩展）
## 把 params.equipment 数组里的装备配置发布到对应的传统 params 字段，
## 让 25 处现存 `params.gun` / `params.missile` 等读取无需修改。
## 当所有装备都迁完（commit 12），删除此函数 + 删除 params 上的传统字段。
func _publish_equipment_to_legacy() -> void:
	if params == null:
		return
	var gun_eq := params.get_equipment_of_kind("gun") as GunEquipment
	if gun_eq != null and gun_eq.gun != null:
		params.gun = gun_eq.gun
	var rocket_eq := params.get_equipment_of_kind("rocket") as RocketEquipment
	if rocket_eq != null and rocket_eq.rocket != null:
		params.rocket = rocket_eq.rocket
	# 导弹双槽：遍历找主/副两件 MissileEquipment
	for eq in params.equipment:
		if eq is MissileEquipment:
			var me: MissileEquipment = eq
			if me.missile == null:
				continue
			if me.is_secondary:
				params.secondary_missile = me.missile
			else:
				params.missile = me.missile
	var flare_eq := params.get_equipment_of_kind("flare") as FlareEquipment
	if flare_eq != null and flare_eq.flare != null:
		params.flare = flare_eq.flare

func show_tactic_popup(text: String) -> void:
	_tactic_popup_text = text
	_tactic_popup_timer = TACTIC_POPUP_DURATION

## 获取挂载的战术机动模块（如有）
func get_maneuver() -> CobraManeuver:
	for child in get_children():
		if child is CobraManeuver:
			return child
	return null

func _get_ai_controller() -> AIController:
	for child in get_children():
		if child is AIController:
			return child
	return null

func get_herbst() -> HerbstManeuver:
	for child in get_children():
		if child is HerbstManeuver:
			return child
	return null

func _physics_process(delta: float) -> void:
	_lod_frame += 1
	if _tactic_popup_timer > 0.0:
		_tactic_popup_timer -= delta
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return
	_update_cloud_state(delta)
	_update_in_building(delta)
	_update_gun_threat_indicator(delta)
	update_lock_line_state(delta)

	# LOD 2（屏幕外）：每3帧完整处理，其余帧仅位移
	if lod_level >= 2:
		if _lod_frame % 3 != 0:
			AircraftPhysics.apply_movement(self, delta)
			# rotation = heading 每帧同步，防止 LOD 2 下镜头切回来看到过时朝向
			# （heading 在 full-update 帧已更新，这里只是跟上最新值；成本 1 次赋值）
			# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (10)
			rotation = heading
			# 玩家飞机即使屏幕外也要画锁定线
			if selected and combat_target != null:
				queue_redraw()
			return
		# 每3帧做一次完整更新：用 lod_delta = delta*3 补偿跳过的 2 帧
		# 之前用 delta 直接调会让 heading/bank/speed 以 1/3 真实速率更新，导致
		# BOSS 离屏时转弯慢 3 倍追不上玩家，越飞越远（bug 2026-04-20 (10) Bug 2）。
		# _apply_movement 和计时器类继续用 delta（每帧都要跑 → 累计不变）
		var lod_delta: float = delta * 3.0
		_run_tactical_planner_if_enabled()  # P4：LOD 2 也需 planner 写决策（每 3 帧一次）
		AircraftWeapons.update_weapon_mode(self)
		AircraftCombatTracking.update_combat(self, lod_delta)
		AircraftPhysics.update_energy_management(self)
		AircraftPhysics.update_target_heading(self)
		AircraftPhysics.update_bank(self, lod_delta)
		AircraftPhysics.update_heading(self, lod_delta)
		AircraftPhysics.update_speed(self, lod_delta)
		AircraftPhysics.update_stall(self)  # 必须在 update_altitude 前：stall 设 vertical_speed → altitude 直接施加
		AircraftPhysics.update_altitude(self, lod_delta)
		AircraftPhysics.update_fuel(self, lod_delta)
		_check_ground_crash()
		AircraftPhysics.update_g_load(self)
		AircraftPhysics.apply_movement(self, delta)  # 本帧 1/60s 的位移（前 2 帧已各 apply 一次，合计 3×1/60）
		if combat_target != null:
			AircraftWeapons.update_gun(self, lod_delta)
			AircraftWeapons.update_rocket(self, lod_delta)
			AircraftWeapons.update_missile(self, lod_delta)
		AircraftFlares.update(self, lod_delta)
		_update_visuals()  # rotation = heading；上一轮 LOD 2 fix 漏掉这行导致图标/label 冻结在过时朝向
		# 玩家飞机即使屏幕外也要画锁定线
		if selected and combat_target != null:
			queue_redraw()
		return

	# LOD 1（编队僚机巡航）
	if lod_level == 1:
		var every3 := _lod_frame % 3 == 0

		if formation_mode and _formation_leader:
			# 编队托管三段式已搬到 scripts/aircraft/aircraft_formation.gd
			# 原因：191 行算法塞在 _physics_process 中间，排查编队 bug 时动线长
			# 拆分后常见 bug 回溯地图、三段式分支图都在 AircraftFormation 顶部注释
			AircraftFormation.update_follow(self, delta)
			return

		# ── 非编队 LOD 1（降低运算频率） ──
		_run_tactical_planner_if_enabled()  # P4：LOD 1 非编队也需 planner 写决策
		AircraftWeapons.update_weapon_mode(self)
		if combat_target != null:
			AircraftCombatTracking.update_combat(self, delta)
		if every3:
			AircraftPhysics.update_energy_management(self)
		AircraftPhysics.update_target_heading(self)
		AircraftPhysics.update_bank(self, delta)
		AircraftPhysics.update_heading(self, delta)
		AircraftPhysics.update_speed(self, delta)
		if every3:
			AircraftPhysics.update_stall(self)  # 在 update_altitude 前
			AircraftPhysics.update_altitude(self, delta)
			AircraftPhysics.update_fuel(self, delta)
			_check_ground_crash()
			AircraftPhysics.update_g_load(self)
		AircraftPhysics.apply_movement(self, delta)
		if combat_target != null:
			AircraftWeapons.auto_gun_scan(self)
			AircraftWeapons.update_gun(self, delta)
			AircraftWeapons.update_rocket(self, delta)
			AircraftWeapons.update_missile(self, delta)
		if every3:
			AircraftFlares.update(self, delta)
		_update_visuals()
		if selected or is_hovered or every3:
			queue_redraw()
		return

	# LOD 0（完整）：玩家 / 交战中
	# P1：planner 在最顶层先跑，写 target_position/target_speed/weapon_mode/is_firing；
	# 后面 update_weapon_mode / update_combat / update_energy_management 各自 early-return
	_run_tactical_planner_if_enabled()
	AircraftWeapons.update_weapon_mode(self)
	_update_evasion(delta)
	AircraftCombatTracking.update_combat(self, delta)
	AircraftPhysics.update_energy_management(self)
	AircraftPhysics.update_target_heading(self)
	AircraftPhysics.update_bank(self, delta)
	AircraftPhysics.update_heading(self, delta)
	AircraftPhysics.update_speed(self, delta)
	AircraftPhysics.update_stall(self)  # 必须在 update_altitude 前
	AircraftPhysics.update_altitude(self, delta)
	AircraftPhysics.update_fuel(self, delta)
	AircraftPhysics.update_shock_absorb(self, delta)
	_check_ground_crash()
	AircraftPhysics.update_g_load(self)
	AircraftPhysics.apply_movement(self, delta)
	AircraftWeapons.auto_gun_scan(self)
	AircraftWeapons.update_gun(self, delta)
	AircraftWeapons.update_ciws(self, delta)
	AircraftWeapons.update_rocket(self, delta)
	AircraftWeapons.update_missile(self, delta)
	# 眼镜蛇技能必须在 AircraftFlares.update 之前 —— 一旦激活，flare 会因机动 active 而跳过
	_update_cobra_skill(delta)
	AircraftFlares.update(self, delta)
	_update_visuals()
	_log_ac_tick(delta)
	# LOD 0 非玩家非悬停：每 2 帧重绘一次，减半 _draw 开销
	if selected or is_hovered or _lod_frame % 2 == 0:
		queue_redraw()

## P1：TacticalPlanner 入口。建态势 → 决策 → 应用。
## 仅在 use_tactical_planner=true 时跑，不影响默认旧路径。
func _run_tactical_planner_if_enabled() -> void:
	if not use_tactical_planner:
		return
	var waypoint: Vector2 = target_position
	var s: Situation = Situation.from_aircraft(self)
	var plan: TacticalPlan = TacticalPlanner.plan(s, waypoint)
	# intent 切换时戳时间（用于下一帧的 hysteresis 判定）+ 诊断日志
	if plan.intent != _bfm_prev_intent:
		# 切换瞬间打 PLAN log，便于追溯"飞机为什么这帧选了这个 intent"
		# 只对玩家 / 选中的友方飞机记录，避免敌机刷爆日志
		if (use_tactical_preference or selected) and not is_destroyed:
			var tgt_name: String = "none"
			if combat_target and is_instance_valid(combat_target):
				tgt_name = _log_unit_name(combat_target)
			var prev_name: String = TacticalPlan.intent_name(_bfm_prev_intent) if _bfm_prev_intent != -1 else "init"
			EventLogger.log_event("PLAN", _log_name(),
				"%s → %s (tgt=%s, why=%s)" % [
					prev_name, TacticalPlan.intent_name(plan.intent), tgt_name, plan.rationale
				])
		_bfm_prev_intent = plan.intent
		_bfm_intent_started_at = Time.get_ticks_msec() / 1000.0
	# extend 触发：本帧 plan 标记触发就把 _bfm_extend_until 推到 now + 触发秒数
	if plan.trigger_extend_seconds > 0.0:
		_bfm_extend_until = Time.get_ticks_msec() / 1000.0 + plan.trigger_extend_seconds
	_apply_tactical_plan(plan)
	_last_plan = plan

## 把 plan 输出写到 Aircraft 字段，供后续物理/武器子系统消费。
## ⚠ 这是 plan 唯一接触 Aircraft 状态的位置，便于追溯"为什么这帧 target_speed 是这个值"
func _apply_tactical_plan(plan: TacticalPlan) -> void:
	# CRUISE / EVADE 等不写 target_position（保留 INF 让 _update_evasion 自己控制）
	if plan.pursuit_pos != Vector2.INF:
		target_position = plan.pursuit_pos
	target_speed_kmh = plan.target_speed_kmh
	AircraftPhysics.set_afterburner(self, plan.afterburner)

	# 玩家右键长按急刹：planner 写完立即覆盖 —— 不让 CRUISE/PURSUIT 的目标速度复活油门
	if hard_brake:
		target_speed_kmh = 0.0
		AircraftPhysics.set_afterburner(self, false)
		target_position = Vector2.INF  # 保持当前航向（update_bank 看到 INF 会回正）

	# 武器模式
	# NONE 显式重置为 GUN（防止 weapon_mode 残留 MISSILE 让 salvo 路径在 CRUISE/EVADE 期间走漏发射）
	match plan.weapon_mode:
		TacticalPlan.WeaponMode.GUN, TacticalPlan.WeaponMode.NONE:
			weapon_mode = WeaponMode.GUN
		TacticalPlan.WeaponMode.MISSILE:
			weapon_mode = WeaponMode.MISSILE
		_:
			pass  # BOTH 保留

	# 机炮：is_firing 直接由 plan 决定
	is_firing = plan.allow_gun_fire
	# _gun_lead_heading：朝 pursuit_pos 方向（让 update_gun 朝那里出弹）
	if plan.pursuit_pos != Vector2.INF:
		var to_pos: Vector2 = plan.pursuit_pos - global_position
		_gun_lead_heading = atan2(to_pos.x, -to_pos.y)
	else:
		_gun_lead_heading = heading

	# 高度（plan 没指定就保持现状）
	if plan.target_altitude_m >= 0.0:
		target_altitude = plan.target_altitude_m
	# tier 必须走 set_target_tier() 同步 target_altitude（米数），
	# 直接写字段会让物理插值停在旧高度 → "MID → LOW 永不到达" bug
	if plan.target_altitude_tier >= 0:
		set_target_tier(plan.target_altitude_tier)
	# 交战 intent + flat_altitude → 自动匹配敌机高度档
	if flat_altitude and combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		match plan.intent:
			TacticalPlan.Intent.TAIL_CHASE, TacticalPlan.Intent.CLOSE_TAIL, \
			TacticalPlan.Intent.LEAD_TURN, TacticalPlan.Intent.LEAD_PURSUIT, \
			TacticalPlan.Intent.LAG_PURSUIT, TacticalPlan.Intent.MERGE_PASS:
				set_target_tier(combat_target.get_altitude_tier())

## 高 G 机动物理采样（AC_TICK 诊断事件）
## 仅在 Herbst/Cobra 激活、或 bank > 60°、或 overshoot extension 中触发，10Hz 采样。
## 用来捕捉"颤抖"bug 的亚 0.5s 频率振荡 —— 看相邻采样的 bnk/spd/hdg/tp_brg 是否在翻跳。
## 输出字段：
##   bnk=<bank°> spd=<m/s> hdg=<deg 归一化±180> tp_brg=<target_position 相对机头方位°>
##   g=<g_load> ab=<y/n> ph=<herbst phase / cobra / - >
func _log_ac_tick(delta: float) -> void:
	var herbst: HerbstManeuver = get_herbst()
	var cobra: CobraManeuver = get_maneuver()
	var maneuver_active: bool = (herbst and herbst.is_active) or (cobra and cobra.is_active)
	var high_bank: bool = absf(rad_to_deg(bank_angle)) > AC_TICK_BANK_THRESHOLD
	var in_overshoot: bool = _overshoot_timer > 0.0
	if not (maneuver_active or high_bank or in_overshoot):
		_ac_tick_log_timer = 0.0  # 条件失效就重置节流，下次进入立即采样
		return
	_ac_tick_log_timer -= delta
	if _ac_tick_log_timer > 0.0:
		return
	_ac_tick_log_timer = AC_TICK_LOG_INTERVAL

	var hdg_norm_deg: float = rad_to_deg(wrapf(heading, -PI, PI))
	var bnk_deg: int = int(rad_to_deg(bank_angle))
	var tp_brg_deg: int = 0
	var tp_dist_m: int = -1  # -1 表示无 target_position
	if target_position != Vector2.INF:
		var to_tp: Vector2 = target_position - global_position
		var tp_heading: float = atan2(to_tp.x, -to_tp.y)
		tp_brg_deg = int(rad_to_deg(_angle_diff(tp_heading, heading)))
		tp_dist_m = int(to_tp.length() / PIXELS_PER_METER)
	var phase_tag := "-"
	if herbst and herbst.is_active:
		match herbst.phase:
			1: phase_tag = "HB_DECEL"
			2: phase_tag = "HB_TURN"
			3: phase_tag = "HB_ACCEL"
			_: phase_tag = "HB_?"
	elif cobra and cobra.is_active:
		phase_tag = "COBRA"
	elif in_overshoot:
		phase_tag = "OVERSHOOT"
	else:
		phase_tag = "HI_BANK"
	var msg := "bnk=%+d° spd=%.0fm/s hdg=%+d° tp_brg=%+d° tp_d=%dm g=%.1f ab=%s ph=%s" % [
		bnk_deg, speed, int(hdg_norm_deg), tp_brg_deg, tp_dist_m,
		g_load, ("y" if is_afterburner else "n"), phase_tag,
	]
	EventLogger.log_event("AC_TICK", _log_name(), msg)

# ========== 物理演算 ==========
# 物理演算实现已搬到 scripts/aircraft/aircraft_physics.gd
# 状态仍住在 Aircraft（heading / bank_angle / speed / altitude / g_load / fuel 等）

var _cached_target_heading: float = 0.0
var _proximity_damping: float = 1.0


static func _angle_diff(target: float, current: float) -> float:
	# 规范化角度差到 [-PI, PI]
	# 旧版用 fmod 在负数情况下返回负值，会让 target/current 跨越 ±π 边界时
	# 得到 |diff| > π 的结果（观测到 off_axis=268° 的 log bug）
	# wrapf 正确处理正负两侧的 wrap
	return wrapf(target - current, -PI, PI)

## [保留委托：外部调用入口] 实际实现在 AircraftPhysics
## survivor_hud.gd:385 读取玩家最大可用 G
func _effective_max_g() -> float:
	return AircraftPhysics.effective_max_g(self)

## 设置目标高度档位（同步 target_altitude 到档位对应值）
func set_target_tier(tier: int) -> void:
	target_altitude_tier = clampi(tier, AltitudeTier.LOW, AltitudeTier.HIGH)
	target_altitude = TIER_ALTITUDE[target_altitude_tier]

## 获取比当前档位高一档（上限 HIGH）
func tier_above() -> int:
	return mini(get_altitude_tier() + 1, AltitudeTier.HIGH)

## 获取比当前档位低一档（下限 LOW）
func tier_below() -> int:
	return maxi(get_altitude_tier() - 1, AltitudeTier.LOW)

# ========== 战区奖励 v2 辅助 ==========
# _update_shock_absorb 已搬到 scripts/aircraft/aircraft_physics.gd

## 侩子手：外部（spawner）在玩家击杀敌机后调用，自增计数并按需升层
## 公式：stacks = clamp(kills - (FIRST_STACK_KILLS - 1), 0, MAX) = clamp(kills - 1, 0, 5)
##   首层需要 2 杀，之后每多 1 杀 +1 层
func bump_executioner_kill() -> void:
	if not executioner_active:
		return
	executioner_kills += 1
	var target_stacks: int = clampi(executioner_kills - (EXECUTIONER_FIRST_STACK_KILLS - 1), 0, EXECUTIONER_MAX_STACKS)
	if target_stacks > executioner_stacks:
		executioner_stacks = target_stacks
		EventLogger.log_event("EXECUTIONER", _log_name(), "stack +1 (now %d, kills=%d)" % [executioner_stacks, executioner_kills])

## 眼镜蛇机动技能：每帧检查触发条件，满足则激活 cobra
## 触发要求（全部满足）：
##   1. 玩家拥有该升级（cobra_skill_active）
##   2. 战术偏好开 + 规避模式 ON
##   3. 当前没有正在进行的机动
##   4. 冷却归零
##   5. 来袭导弹 ≤ COBRA_MISSILE_TRIGGER_PX OR 后方有敌机追尾开火
func _update_cobra_skill(delta: float) -> void:
	if not cobra_skill_active:
		return
	_cobra_skill_cooldown = maxf(_cobra_skill_cooldown - delta, 0.0)
	if not use_tactical_preference or not evasion_mode:
		return
	if _cobra_skill_cooldown > 0.0:
		return
	var mf := get_maneuver()
	if mf == null:
		return
	if mf.is_active:
		return
	if not (_cobra_detect_imminent_missile() or _cobra_detect_tail_gun()):
		return
	# 触发：技能模式允许重复使用，强制重置 is_used 让 activate 通过
	mf.is_used = false
	if mf.activate():
		_cobra_skill_cooldown = COBRA_SKILL_COOLDOWN

## 检测来袭导弹是否已逼近触发距离 + 真的有命中可能
## 三重过滤防止"远处擦边导弹"也触发 cobra：
##   1. 距离 ≤ COBRA_MISSILE_TRIGGER_PX
##   2. has_guidance == true（失锁/被诱骗的导弹直线飞，不构成威胁）
##   3. 导弹机头基本朝向玩家（dot ≥ 0.5，约 ±60° 锥）— 已飞过头的不重复触发
func _cobra_detect_imminent_missile() -> bool:
	if not missile_manager:
		return false
	var trigger_sq: float = COBRA_MISSILE_TRIGGER_PX * COBRA_MISSILE_TRIGGER_PX
	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child as Missile
		if not m.is_active or m.is_flare_jammed or m.target != self:
			continue
		if not m.has_guidance:
			continue
		if global_position.distance_squared_to(m.global_position) > trigger_sq:
			continue
		# 导弹必须朝玩家飞才算威胁
		var to_me := (global_position - m.global_position).normalized()
		var m_heading := Vector2(sin(m.heading), -cos(m.heading))
		if m_heading.dot(to_me) < 0.5:
			continue
		return true
	return false

## 检测后方是否有敌机正在以机炮追尾（敌机在我后半球 + 机头朝我 + 正在开火）
func _cobra_detect_tail_gun() -> bool:
	var trigger_sq: float = COBRA_TAIL_DETECT_PX * COBRA_TAIL_DETECT_PX
	var my_fwd := Vector2(sin(heading), -cos(heading))
	for u in CombatUnit.all_units:
		if u == self or u.team == team or u.is_destroyed:
			continue
		if not u is Aircraft:
			continue
		var enemy: Aircraft = u as Aircraft
		if not enemy.is_firing:
			continue
		if global_position.distance_squared_to(enemy.global_position) > trigger_sq:
			continue
		var to_enemy := (enemy.global_position - global_position).normalized()
		# 要求敌机在我后半球（dot < -0.3，约 110° 后向锥）
		if my_fwd.dot(to_enemy) > -0.3:
			continue
		# 要求敌机头朝我（dot 与 -to_enemy ≥ 0.7，约 ±45°）
		var enemy_fwd := Vector2(sin(enemy.heading), -cos(enemy.heading))
		if enemy_fwd.dot(-to_enemy) < 0.7:
			continue
		return true
	return false

## 侩子手 4 个属性乘数（仅在 executioner_active 且 stacks > 0 时偏离 1.0）
func _executioner_speed_mult() -> float:
	# 每层 +5% 最大速度，5 层 +25%
	return 1.0 + 0.05 * float(executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0

func _executioner_decel_mult() -> float:
	# 每层 +10% 减速能力，5 层 +50%
	return 1.0 + 0.10 * float(executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0

func _executioner_reload_mult() -> float:
	# 每层 -8% 装填时间（=×0.92），5 层 ×0.659（-34%）
	return pow(0.92, executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0

func _executioner_lock_mult() -> float:
	# 每层 -10% 锁定时间（=×0.90），5 层 ×0.590（-41%）
	return pow(0.90, executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0

# ========== 燃油 / 能量管理 ==========
# _set_afterburner / _update_fuel / _update_energy_management 已搬到
# scripts/aircraft/aircraft_physics.gd（set_afterburner / update_fuel / update_energy_management）


# ========== 战斗 ==========

func _log_name() -> String:
	var side := "Friend" if team == 0 else "Enemy"
	var dn: String = params.display_name if params else "???"
	return "%s/%s[%s]" % [side, dn, callsign]

func _log_unit_name(unit: CombatUnit) -> String:
	if not unit or not is_instance_valid(unit):
		return "None"
	if unit is Aircraft:
		var ac: Aircraft = unit
		var side := "Friend" if ac.team == 0 else "Enemy"
		var dn: String = ac.params.display_name if ac.params else "???"
		return "%s/%s[%s]" % [side, dn, ac.callsign]
	# 舰船挂点代理：log 显示 "船名 [挂点符号]"，避免出现 @Node2D@454 难以追溯
	if unit is MountTarget:
		var mt: MountTarget = unit
		if mt.parent_ship and is_instance_valid(mt.parent_ship):
			var ship_label: String = mt.parent_ship.full_name if mt.parent_ship.full_name != "" else "Ship"
			if mt.mount_ref and mt.mount_ref.params:
				return "%s[%s]" % [ship_label, mt.mount_ref.params.display_symbol]
			if mt.weak_point_ref:
				return "%s[WP]" % ship_label
			return ship_label
		return "MountTarget"
	return unit.name

func set_combat_target(target: CombatUnit) -> void:
	combat_target = target
	is_firing = false
	_strafe_state = 0  # 重置舔地状态机
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 切目标时解除机炮提交锁定
	charge_attack = false  # 默认清除冲锋（双击调用方在 set 之后显式置 true）
	if use_tactical_preference and target != null:
		EventLogger.log_event("PURSUIT_ACQUIRE", _log_name(),
			"tgt=%s wpn=%s" % [_log_unit_name(target),
				"GUN" if weapon_mode == WeaponMode.GUN else "MSL"])

func clear_combat_target() -> void:
	if use_tactical_preference and combat_target != null:
		EventLogger.log_event("PURSUIT_CLEAR", _log_name(),
			"(was %s)" % _log_unit_name(combat_target))
	combat_target = null
	_committed_turn_sign = 0.0
	is_firing = false
	_strafe_state = 0
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 清目标时解除机炮提交锁定
	_pursuit_branch = ""
	charge_attack = false

## [保留委托：外部/跨模块调用入口]
## 战斗追踪已搬到 scripts/aircraft/aircraft_combat_tracking.gd
## 以下 5 个薄壳保持 ac._xxx() 写法兼容（被 ai_controller / aircraft_weapons 调用）
func _missile_cannot_hit_but_gun_can() -> bool:
	return AircraftCombatTracking.missile_cannot_hit_but_gun_can(self)

func _should_commit_gun_pass() -> bool:
	return AircraftCombatTracking.should_commit_gun_pass(self)

func _is_gun_pass_finished() -> bool:
	return AircraftCombatTracking.is_gun_pass_finished(self)

func _is_in_missile_envelope(target_unit: CombatUnit, msl: MissileParams) -> bool:
	return AircraftCombatTracking.is_in_missile_envelope(self, target_unit, msl)

func _choose_dogfight_pursuit_pos(
		my_pos: Vector2,
		dist: float,
		tgt_pos: Vector2,
		tgt_fwd: Vector2,
		tgt_speed_px: float,
		my_speed_px: float,
		in_rear: bool
) -> Vector2:
	return AircraftCombatTracking.choose_dogfight_pursuit_pos(
			self, my_pos, dist, tgt_pos, tgt_fwd, tgt_speed_px, my_speed_px, in_rear)

var _strafe_state: int = 0       ## 0=进入, 1=攻击, 2=脱离, 3=掉头
var _strafe_extend_dist: float = 0.0  ## 脱离时已飞距离
## 战斗参数（带懒加载默认值）
var _default_combat: CombatParams

func _combat_params() -> CombatParams:
	if params and params.combat:
		return params.combat
	if not _default_combat:
		_default_combat = CombatParams.new()
	return _default_combat

## 机炮射程（像素）
func _gun_range_px() -> float:
	if params and params.gun:
		return params.gun.max_range * PIXELS_PER_METER
	return 500.0

## 导弹射程（像素）
func _missile_range_px() -> float:
	if params and params.missile:
		# 使用后半球射程的 60% 作为理想交战距离参考
		return params.missile.max_range_rear * 0.6 * PIXELS_PER_METER
	return 500.0

## 有效导弹交战距离（像素）= min(导弹射程, 雷达范围)
## 导弹虽可飞远但雷达外无法锁定，所以真正可打击距离由雷达限制
## 扁平模式下导弹射程有 alt_factor=1.5 加成，与 _is_in_missile_envelope 一致
## ⚠ 单位注意：missile.max_range_rear 是米，radar_range 是像素（见 aircraft_params.gd:44）
func _effective_missile_range_px() -> float:
	if not params or not params.missile:
		return 1500.0
	var missile_range_m: float = params.missile.max_range_rear
	if flat_altitude:
		missile_range_m *= 1.5
	var missile_range_px := missile_range_m * PIXELS_PER_METER  # 米 → 像素
	# 用有效雷达范围（已含高度档位倍率）—— LOW 视野短，HIGH 看得远，导弹有效射程也跟着走
	var radar_range_px := effective_radar_range_px()
	return minf(missile_range_px, radar_range_px)

## 当前武器有效交战距离（像素）
func _effective_range_px() -> float:
	if weapon_mode == WeaponMode.MISSILE:
		return _missile_range_px()
	return _gun_range_px()

## 导弹交战阶段：0=接近（积极机动），1=照射（目标在锥内），2=保持（已锁定/crank）
func _get_missile_phase() -> int:
	if is_cranking():
		return 2
	if combat_target == null or not is_instance_valid(combat_target):
		return 0
	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	var lock_time_val: float = params.lock_time if params else 3.0
	if lock_progress >= lock_time_val:
		# 已锁定
		return 2
	if lock_progress > 0.0:
		# 目标在锥内，正在累积
		return 1
	# 目标不在锥内
	return 0

## 判断是否已经近到应该用机炮（非常严格，防止模式震荡）
func _should_use_gun() -> bool:
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	if combat_target.is_destroyed:
		return false
	var dist := global_position.distance_to(combat_target.global_position)
	var gun_range := _gun_range_px()
	# 只有在机炮射程内才考虑（不是 1.2 倍，是 0.8 倍——必须非常近）
	return dist < gun_range * 0.8

## 是否正在保持照射（发射后维持锁定阶段）
func is_cranking() -> bool:
	return _crank_timer > 0.0

## 切换规避模式：进入时清空当前指令（等同右键"解除任务"），离开时不动作
## 供 HUD 按钮 / 键位 / 点击逻辑统一调用
func set_evasion_mode(enabled: bool) -> void:
	evasion_mode = enabled
	if enabled:
		# 取消当前移动指令和交战目标，专心躲避
		clear_combat_target()
		target_position = Vector2.INF
		_evasion_override = false
	# 关闭时不动作，玩家可手动指定新目标

## 触发一次闪避滚转动画（子弹闪避/热诱弹成功时的视觉反馈）
func _trigger_evasion_roll() -> void:
	if _evade_roll_remaining <= 0.0 and _evade_roll_cooldown <= 0.0:
		_evade_roll_remaining = _EVADE_ROLL_DURATION
		# BOSS（高闪避率）给更长冷却，防止一直滚转
		if bullet_dodge_chance >= HIGH_DODGE_THRESH:
			_evade_roll_cooldown = BOSS_EVADE_ROLL_CD  # 4 秒才能再次滚转

## 规避模式更新（生存模式玩家）
func _update_evasion(delta: float) -> void:
	# 冷却与动画倒计时
	_evade_roll_cooldown = maxf(_evade_roll_cooldown - delta, 0.0)
	if _evade_roll_remaining > 0.0:
		# 正在滚转：按固定速率推进相位（一圈 / _EVADE_ROLL_DURATION）
		var roll_speed := TAU / _EVADE_ROLL_DURATION
		_evade_roll_phase += roll_speed * delta
		if _evade_roll_phase > PI:
			_evade_roll_phase -= TAU
		_evade_roll_remaining -= delta
		if _evade_roll_remaining <= 0.0:
			_evade_roll_remaining = 0.0
			_evade_roll_cooldown = _EVADE_ROLL_COOLDOWN
	else:
		# 无滚转：相位平滑回正（机翼水平）
		_evade_roll_phase = lerp_angle(_evade_roll_phase, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		if absf(_evade_roll_phase) < 0.02:
			_evade_roll_phase = 0.0

	if not use_tactical_preference or not evasion_mode:
		return

	# 检测来袭导弹（最近的一枚）
	var incoming_missile: Missile = null
	var closest_dist := INF
	if missile_manager:
		for child in missile_manager.get_children():
			if child is Missile:
				var m: Missile = child as Missile
				if m.is_active and not m.is_flare_jammed and m.target == self:
					var d := global_position.distance_squared_to(m.global_position)
					if d < closest_dist:
						closest_dist = d
						incoming_missile = m

	if incoming_missile:
		var dist_px := sqrt(closest_dist)
		# 触发一次短促的桶滚动画：导弹首次进入触发距离 + 冷却就绪 + 不同的来袭导弹
		var mid := incoming_missile.get_instance_id()
		if dist_px < _EVADE_ROLL_TRIGGER_PX \
				and _evade_roll_cooldown <= 0.0 \
				and _evade_roll_remaining <= 0.0 \
				and mid != _evade_last_missile_id:
			_evade_roll_remaining = _EVADE_ROLL_DURATION
			_evade_last_missile_id = mid

		# 规避方向：垂直于导弹来袭方向
		var missile_dir := (global_position - incoming_missile.global_position).normalized()
		var evade_dir := Vector2(missile_dir.y, -missile_dir.x)
		var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
		var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
		var diff_a := absf(angle_difference(heading, evade_heading_a))
		var diff_b := absf(angle_difference(heading, evade_heading_b))
		var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir
		target_position = global_position + chosen_dir * 2000.0
		# 高度规避：切换档位
		if flat_altitude:
			if get_altitude_tier() == AltitudeTier.LOW:
				set_target_tier(AltitudeTier.HIGH)
			else:
				set_target_tier(AltitudeTier.LOW)
	else:
		# 无来袭导弹：S 型机动，不依赖 _evasion_override（该标志已废弃）
		_evade_last_missile_id = 0
		_evasion_sway_timer += delta
		var sway_period := 3.0
		var sway_angle := sin(_evasion_sway_timer * TAU / sway_period) * 0.8
		var sway_heading := heading + sway_angle
		target_position = global_position + Vector2(sin(sway_heading), -cos(sway_heading)) * 1500.0

## 节流记录玩家导弹发射被阻塞的原因（每 MSL_BLOCK_LOG_INTERVAL 最多一次）
## 同一 reason 连续触发时不重复记录，直到 reason 改变或间隔到期
func _log_msl_block(reason: String, detail: String) -> void:
	if not use_tactical_preference:
		return
	if combat_target == null or not is_instance_valid(combat_target):
		return
	if _msl_block_log_timer > 0.0 and _msl_last_block_reason == reason:
		return
	_msl_block_log_timer = MSL_BLOCK_LOG_INTERVAL
	_msl_last_block_reason = reason
	var tgt_name := _log_unit_name(combat_target)
	EventLogger.log_event("MSL_BLOCK", _log_name(),
		"%s → %s: %s" % [reason, tgt_name, detail])

## 威胁态势快照：转储所有正在攻击玩家的导弹 + 所有正在锁定/已锁定玩家的敌方单位
## 在导弹开火时打到日志，便于事后排查"为什么打了这一发"
func _log_threat_picture(context: String) -> void:
	if not missile_manager:
		return

	# 1. 正在攻击我的导弹（target == self 的在飞导弹）
	var attacking: Array[String] = []
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if not m.is_active or m.target != self:
				continue
			var msl_name: String = m.params.display_name if m.params and m.params.display_name else "MSL"
			var src_label := "?"
			var src_dist := 0.0
			if is_instance_valid(m.source):
				src_label = _log_unit_name(m.source)
				src_dist = global_position.distance_to(m.source.global_position) / PIXELS_PER_METER
			var time_to_impact := global_position.distance_to(m.global_position) / maxf(m.speed * PIXELS_PER_METER, 1.0)
			attacking.append("%s<-%s @%.0fm eta=%.1fs" % [msl_name, src_label, src_dist, time_to_impact])

	# 2. 正在/准备锁定我的敌方单位（其 radar_targets 里有 self）
	var locking: Array[String] = []
	for unit in missile_manager.target_list:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit.team == team:
			continue
		var their_lock: float = unit.radar_targets.get(self, 0.0)
		if their_lock <= 0.0:
			continue
		var their_lock_time := DEFAULT_LOCK_TIME
		if unit is Aircraft and unit.params:
			their_lock_time = unit.params.lock_time
		elif unit is GroundUnit and unit.params:
			their_lock_time = unit.params.lock_time
		var status := "LOCKED" if their_lock >= their_lock_time else "locking"
		var dist := global_position.distance_to(unit.global_position) / PIXELS_PER_METER
		locking.append("%s %s=%.1f/%.1fs @%.0fm" % [
			_log_unit_name(unit), status, their_lock, their_lock_time, dist])

	if attacking.is_empty() and locking.is_empty():
		return  # 无威胁就不打日志

	var parts: Array[String] = ["[%s]" % context]
	if not attacking.is_empty():
		parts.append("attacking=[%s]" % "; ".join(attacking))
	if not locking.is_empty():
		parts.append("locking=[%s]" % "; ".join(locking))
	EventLogger.log_event("THREAT", _log_name(), " ".join(parts))

## 从雷达锁定的目标中选出最优的一个（命中概率最高）
## 评分标准：距离近 + 机头偏差小 + 锁定时间长 = 分高
func _select_best_missile_target() -> CombatUnit:
	var best: CombatUnit = null
	var best_score: float = -1.0
	var my_fwd := Vector2(sin(heading), -cos(heading))

	for target_key in radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_unit: CombatUnit = target_key as CombatUnit
		if target_unit == null or target_unit.is_destroyed:
			continue
		if target_unit.team == team:
			continue
		# 必须有一定锁定累积（至少在锥内待过一会儿）
		var lock_progress: float = radar_targets[target_key]
		if lock_progress < 0.5:
			continue

		var to_tgt := (target_unit.global_position - global_position)
		var dist := to_tgt.length()
		if dist < 1.0:
			continue

		# 机头偏差（越小越好）
		var angle_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var nose_diff := absf(_angle_diff(angle_to_tgt, heading))

		# 闭合率（正值=接近，越高越好命中）
		var tgt_fwd := Vector2(sin(target_unit.heading), -cos(target_unit.heading))
		var tgt_speed_px := target_unit.speed * PIXELS_PER_METER
		var my_speed_px := speed * PIXELS_PER_METER
		var to_tgt_dir := to_tgt.normalized()
		var closing := my_fwd.dot(to_tgt_dir) * my_speed_px - tgt_fwd.dot(to_tgt_dir) * tgt_speed_px

		# 评分：距离近（归一化）+ 偏差小 + 闭合率高 + 锁定时间长
		var dist_score := clampf(1.0 - dist / 10000.0, 0.0, 1.0)
		var angle_score := clampf(1.0 - nose_diff / deg_to_rad(60.0), 0.0, 1.0)
		var closing_score := clampf(closing / 500.0, -0.5, 1.0)
		var lock_score := clampf(lock_progress / 5.0, 0.0, 1.0)

		var score := dist_score * 0.25 + angle_score * 0.35 + closing_score * 0.25 + lock_score * 0.15

		if score > best_score:
			best_score = score
			best = target_unit

	return best

## 受到伤害（通用：导弹/火箭/爆炸等战斗部伤害）
## 战斗部类伤害：受"弹头穿甲"系数影响，只计一半护甲（见 MISSILE_ARMOR_PENETRATION）
func take_damage(amount: float) -> void:
	if is_destroyed:
		return
	if invulnerable:
		return
	if survivor_missile_damage_cap > 0.0:
		amount = minf(amount, survivor_missile_damage_cap)
	amount = _apply_armor(amount, MISSILE_ARMOR_PENETRATION)
	_apply_damage(amount)

## 受到机炮伤害（可被装甲闪避）
## 闪避率累加来源：
##   - 基础 bullet_dodge_chance（含生存模式 20% 主角基础 + 装甲强化升级）
##   - 规避模式额外 +20%（战术面板开启“回避/规避模式”时生效）
##   - HIGH 高度档位额外 +20%（高空机炮更难命中）
func take_bullet_damage(amount: float) -> void:
	if is_destroyed:
		return
	if invulnerable:
		return
	# Adds 杂兵（Tu-160/AH-64/CH-47）按设计被击中无任何反应——
	# 不参与闪避也不触发桶滚动画，否则重型轰炸机会像战斗机一样在高空翻滚
	var is_adds: bool = has_meta("category") and get_meta("category") == "adds"
	var effective_dodge: float = bullet_dodge_chance
	if use_tactical_preference and evasion_mode:
		effective_dodge += 0.20  # 规避模式加成
	if get_altitude_tier() == AltitudeTier.HIGH:
		effective_dodge += 0.20  # HIGH 高度加成
	if not is_adds and effective_dodge > 0.0 and randf() < effective_dodge:
		_trigger_evasion_roll()  # 闪避滚转动画
		return  # 闪避成功，无视伤害
	if survivor_bullet_damage_cap > 0.0:
		amount = minf(amount, survivor_bullet_damage_cap)
	amount = _apply_armor(amount, 0.0)  # 机炮不穿甲，护甲全额生效
	# 标记致死来源：survivor_spawner._detect_kills 据此触发"机炮击杀恐惧"AOE
	if hp - amount <= 0.0:
		_killed_by_bullet = true
	_apply_damage(amount)

## 护甲减伤（DOTA 式软上限）：dr = armor_eff / (armor_eff + ARMOR_K)
## penetration ∈ [0,1]：穿甲系数，导弹=0.5 抵消一半护甲，机炮=0 受全额护甲
## armor=0 → dr=0，完全兼容现有无护甲飞机
const ARMOR_K: float = 100.0
const MISSILE_ARMOR_PENETRATION: float = 0.5
func _apply_armor(amount: float, penetration: float) -> float:
	if not params or params.armor <= 0.0:
		return amount
	var armor_eff: float = params.armor * (1.0 - clampf(penetration, 0.0, 1.0))
	if armor_eff <= 0.0:
		return amount
	var dr: float = armor_eff / (armor_eff + ARMOR_K)
	return amount * (1.0 - dr)

func _apply_damage(amount: float) -> void:
	var old_hp := hp
	hp -= amount
	EventLogger.log_event("DAMAGE", _log_name(),
		"took %.0f damage (hp=%.0f→%.0f)" % [amount, old_hp, hp])
	# 侩子手：受到任意伤害 → 清零连击与层数
	if executioner_active and amount > 0.0:
		if executioner_stacks > 0 or executioner_kills > 0:
			EventLogger.log_event("EXECUTIONER", _log_name(), "streak broken (was %d kills, %d stacks)" % [executioner_kills, executioner_stacks])
		executioner_kills = 0
		executioner_stacks = 0
	# 冲击吸收：未致死时按比例排队回血（floor，1dmg 自然不触发）
	if shock_absorb_active and hp > 0.0 and amount >= 2.0:
		# 重置而非累加：新伤害"断掉"上一次还没回完的回血池，
		# 只为这次伤害排队 floor(dmg × 0.4) HP。
		# 设计意图：冲击吸收只救偶发大伤害；被连续打会反复打断回血，惩罚 DPS。
		shock_absorb_pending = floorf(amount * SHOCK_ABSORB_RATIO)
	# 族群散开触发：即使自己会被这一击打爆，也要把 scatter 信号传给队友
	# （设计：某一架被击中时，其余幸存队友立刻转向散开，避免一发打掉一整列）
	if has_meta("scatter_on_damage") and get_meta("scatter_on_damage"):
		_trigger_flock_scatter()
	if hp <= 0.0:
		hp = 0.0
		_record_kill_attribution()
		_start_destroy()

## 致死瞬间快照攻击者归因 + 双方姿态。bullet/missile manager 在调 take_damage 前
## 用 set_meta("_pending_attacker", source) 写入射手；这里读取并算几何。
## 用 meta 而不是参数：避免改 take_damage 签名（CombatUnit 多个子类都覆写过）。
##
## 写出的 meta（survivor_spawner._detect_kills 读取）：
##   kill_attacker_id   - 攻击者 instance_id（用于精确匹配玩家）
##   kill_attacker_team - 攻击者 team（0=友方）
##   kill_head_on_dot   - −victim_fwd · to_victim：1 = 受害者机头朝攻击者（对头）
##   kill_attacker_aim  - attacker_fwd · to_victim：1 = 攻击者机头朝向受害者
## 「对头击杀」判定：两个 dot 都 > 0.6（双方机头夹角 ≲ 53°，排除偷袭/侧射）
func _record_kill_attribution() -> void:
	if not has_meta("_pending_attacker"):
		return
	var attacker = get_meta("_pending_attacker")
	remove_meta("_pending_attacker")
	if not is_instance_valid(attacker) or not (attacker is Aircraft):
		return
	var atk: Aircraft = attacker
	var delta_pos: Vector2 = global_position - atk.global_position
	if delta_pos.length_squared() < 1.0:
		return
	var to_victim: Vector2 = delta_pos.normalized()
	var atk_fwd := Vector2(sin(atk.heading), -cos(atk.heading))
	var vic_fwd := Vector2(sin(heading), -cos(heading))
	set_meta("kill_attacker_id", atk.get_instance_id())
	set_meta("kill_attacker_team", atk.team)
	set_meta("kill_head_on_dot", -vic_fwd.dot(to_victim))
	set_meta("kill_attacker_aim", atk_fwd.dot(to_victim))

## 触发整个 flock 散开：每架队友朝随机一侧做 jink 闪避数秒，
## 同时中断 AIController 的任何交战追踪（_process_simple 开头会检查并清空 _current_target）
func _trigger_flock_scatter() -> void:
	for member in flock_members:
		if not is_instance_valid(member) or member.is_destroyed:
			continue
		if member.flock_scatter_timer <= 0.0:
			# 首次散开：选个方向（左/右随机）
			var m_fwd := Vector2(sin(member.heading), -cos(member.heading))
			var m_perp := Vector2(-m_fwd.y, m_fwd.x)
			member.flock_scatter_dir = m_perp if randf() < 0.5 else -m_perp
		# 刷新计时（后续受击保持方向、延长时间）
		member.flock_scatter_timer = FLOCK_SCATTER_DURATION

func _check_ground_crash() -> void:
	# 高度为 0 且非起飞状态 → 坠地
	# invulnerable 期间（如航母弹射起飞）放过：滑跑就在地面上，此时不算坠毁
	if altitude <= 0.0 and not is_destroyed and not invulnerable:
		altitude = 0.0
		_start_destroy()

## 坠毁系统委托给 AircraftDestruction（aircraft_destruction.gd）
func _start_destroy() -> void:
	AircraftDestruction.start(self)

func _update_destroy(delta: float) -> void:
	AircraftDestruction.update(self, delta)

# ========== 雷达 ==========

## 高度对雷达范围的连续乘数（基于实际米数，不再因 tier 跳变）
## 锚点对齐 TIER_ALTITUDE 中心，让玩家爬升/俯冲时雷达锥跟着平滑收缩 / 扩张
##   0m     → 0.50 (贴地杂波最严重)
##   2000m  → 0.60 (LOW 中心)
##   5500m  → 1.00 (MID 中心)
##   10000m → 1.40 (HIGH 中心)
##   15000m → 1.50 (上限缓和)
const RADAR_RANGE_ALT_KEYS := [
	[0.0, 0.50],
	[2000.0, 0.60],
	[5500.0, 1.00],
	[10000.0, 1.40],
	[15000.0, 1.50],
]


## 雷达有效距离（params.radar_range × 当前高度连续倍率）
## 是否要 ECM/buff 由调用方决定，这里只算"我的雷达高度修正"
func effective_radar_range_px() -> float:
	var base: float = params.radar_range if params else 300.0
	var alt: float = altitude
	# 锚点表线性插值 — 与 AircraftRenderer.altitude_base_scale 同思路
	for i in range(RADAR_RANGE_ALT_KEYS.size() - 1):
		var lo: Array = RADAR_RANGE_ALT_KEYS[i]
		var hi: Array = RADAR_RANGE_ALT_KEYS[i + 1]
		if alt <= float(hi[0]):
			var t := (alt - float(lo[0])) / maxf(float(hi[0]) - float(lo[0]), 0.001)
			var mult: float = lerpf(float(lo[1]), float(hi[1]), clampf(t, 0.0, 1.0))
			return base * mult
	return base * float(RADAR_RANGE_ALT_KEYS[RADAR_RANGE_ALT_KEYS.size() - 1][1])


## 判断目标世界坐标是否在本机雷达锥内
func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	var radar_r := effective_radar_range_px()
	var half_deg := params.radar_half_angle if params else 30.0
	var half_rad := deg_to_rad(half_deg)

	var to_target := target_global_pos - global_position
	var dist := to_target.length()
	if dist > radar_r or dist < 1.0:
		return false

	# heading: 0=北(上), 顺时针正; atan2(x, -y) 与 heading 同系
	var angle_to := atan2(to_target.x, -to_target.y)
	var diff := absf(_angle_diff(angle_to, heading))
	return diff <= half_rad

# ========== 绘制 ==========

## 标签字体（延迟加载）
var _font: Font

func _draw() -> void:
	if not _font:
		_font = ThemeDB.fallback_font
	if is_destroyed:
		AircraftRenderer.draw_aircraft_icon_destroyed(self)
		# 坠毁时仍绘制 tactic popup（例如 UAV "舍身"自爆瞬间会走这里）
		AircraftRenderer.draw_tactic_popup(self)
		return
	# 光学隐形：完全隐形时只画战术 popup（例如 BOSS "光学迷彩" 激活提示），其余跳过
	if _cloak_alpha <= 0.0:
		if self_modulate.a < 1.0:
			self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		AircraftRenderer.draw_tactic_popup(self)
		return
	# 半透明淡入/淡出：通过 self_modulate 控制整体透明度
	if _cloak_alpha < 1.0:
		self_modulate = Color(1.0, 1.0, 1.0, _cloak_alpha)
	elif self_modulate.a < 1.0:
		self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	if is_hovered:
		AircraftRenderer.draw_radar_cone(self)
	# 友方 hover 时显示参考机炮锥；敌方对玩家提交机炮攻击时持续显示锥（条件在 draw_gun_cone 内判）
	AircraftRenderer.draw_gun_cone(self)
	LockWarning.draw(self, AircraftRenderer.player_ref)
	AircraftRenderer.draw_target_line(self)
	AircraftRenderer.draw_cloud_state(self)
	AircraftRenderer.draw_aircraft_icon(self)
	AircraftRenderer.draw_lock_indicator(self)
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	if is_firing:
		AircraftRenderer.draw_muzzle_flash(self)
	if is_afterburner:
		AircraftRenderer.draw_afterburner_glow(self)
	AircraftRenderer.draw_flare_particles(self)
	if hide_data_label:
		AircraftRenderer.draw_data_label_minimal(self)
	else:
		AircraftRenderer.draw_data_label(self)
	AircraftRenderer.draw_tactic_popup(self)
	if formation_debug:
		AircraftRenderer.draw_formation_debug(self)

## [保留委托：外部调用入口] 实际实现在 AircraftPhysics
## aircraft_renderer.gd:1217 画预测路径时用
func _max_bank_angle_at_speed(spd: float, stall_base_ms: float) -> float:
	return AircraftPhysics.max_bank_angle_at_speed(self, spd, stall_base_ms)

# ========== 云层状态缓存 ==========

## 每 0.2 秒查询一次天气系统，更新 cloud_state / cloud_density。
## 状态：0=晴空 / 1=云下方（LOW/MID）/ 2=云中（HIGH）。
## 供渲染层画光晕/阴影、其它系统（missile AI 等）直接读。
func _update_cloud_state(delta: float) -> void:
	_cloud_state_accum += delta
	if _cloud_state_accum < 0.2:
		return
	_cloud_state_accum = 0.0
	var weather := get_tree().get_first_node_in_group("weather")
	if weather == null or not weather.has_method("sample_density"):
		cloud_state = 0
		cloud_density = 0.0
		return
	var density: float = weather.sample_density(global_position)
	cloud_density = density
	if density <= 0.0:
		cloud_state = 0
	elif get_altitude_tier() == AltitudeTier.HIGH:
		cloud_state = 2
	else:
		cloud_state = 1


## 每 0.2 秒采样一次建筑遮挡，更新 in_building（LOW 档位且位置在任意街区内）
## 用于物理速度惩罚 + 弹药 spawn-from-inside 判定
func _update_in_building(delta: float) -> void:
	_in_building_accum += delta
	if _in_building_accum < 0.2:
		return
	_in_building_accum = 0.0
	if altitude >= 3500.0:
		in_building = false
		return
	in_building = BuildingRenderer.is_position_inside_building(global_position)

# ========== 热诱弹系统 ==========

func is_lock_immune() -> bool:
	return _lock_immunity_timer > 0.0 or is_cloaked

## HUD 用：热诱弹冷却比例（委托 AircraftFlares）
func get_flare_cooldown_ratio() -> float:
	return AircraftFlares.cooldown_ratio(self)


func _update_visuals() -> void:
	rotation = heading


## 敌方对玩家提交机炮攻击时累计计时；持续 ≥0.3s 显示红色机炮锥威胁提示。
## 条件中断立即归零，避免 weapon_mode GUN/MISSILE 抖动时锥反复闪烁。
func _update_gun_threat_indicator(delta: float) -> void:
	if team == 0 or is_destroyed or is_cloaked:
		_gun_threat_timer = 0.0
		return
	if not params or not params.gun:
		_gun_threat_timer = 0.0
		return
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref) or pref.is_destroyed:
		_gun_threat_timer = 0.0
		return
	if combat_target != pref or weapon_mode != WeaponMode.GUN:
		_gun_threat_timer = 0.0
		return
	var range_px: float = params.gun.max_range * PIXELS_PER_METER * GUN_THREAT_RANGE_MULT
	if global_position.distance_squared_to(pref.global_position) > range_px * range_px:
		_gun_threat_timer = 0.0
		return
	_gun_threat_timer += delta


## 覆写 CombatUnit：飞机能否对玩家发射导弹（lock_armed 上升沿条件之一）
func _lock_line_can_engage_player() -> bool:
	if not has_missile_capability():
		return false
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null:
		return false
	return combat_target == pref and _missile_cooldown <= 0.05


## 敌方是否具备对玩家发射导弹的能力（无导弹的飞机不该有锁定线显示）
## infinite_ammo BOSS 永远视为有导弹
func has_missile_capability() -> bool:
	if not params or not params.missile:
		return false
	if infinite_ammo:
		return true
	return missiles_remaining > 0
