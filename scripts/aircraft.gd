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
var pilot_stamina: float = 100.0  ## 飞行员当前耐力

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
var no_stamina: bool = false         ## 跳过耐力系统（UAV 等）
var survivor_missile_damage_cap: float = 0.0  ## 生存模式：导弹伤害上限（0=不限制）
var survivor_bullet_damage_cap: float = 0.0   ## 生存模式：机炮伤害上限（0=不限制）
var hide_data_label: bool = false    ## 隐藏飞机旁的数据标签（HUD 替代显示）

# --- 战术偏好（生存模式玩家手动控制）---
enum WeaponPreference { PREFER_MISSILE, PREFER_GUN }
enum AltitudePreference { PREFER_CLIMB, PREFER_LOW }

var use_tactical_preference: bool = false       ## 启用战术偏好系统（仅玩家飞机）
## 战术激进度 [0..1]：
##   - 1.0 = 完全激进（解除 G 限制，维持角点速度，最小转弯半径）
##   - 0.0 = 保守（沿用原 70% 持续 G 限制与 turn_slow_speed 能量策略）
##   - 默认 1.0，保证没有 AI 的玩家飞机（survivor 模式）开箱即用最激进
##   - AI 控制器每帧根据 effective_skill × aggression 写入此值，使沙盒 AI 随飞行员属性调整
var tactical_aggression: float = 1.0
var weapon_preference: int = WeaponPreference.PREFER_MISSILE
var altitude_preference: int = AltitudePreference.PREFER_CLIMB
var evasion_mode: bool = false
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
		pilot_stamina = params.pilot_stamina
	# 轨迹丝带
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 8.0
	_trail_ribbon.max_points = 360
	# 尾迹渲染在飞机图标之下，避免彩带盖住机身（尤其是轰炸机这种大尺寸图标）
	_trail_ribbon.show_behind_parent = true
	_trail_ribbon.ribbon_color = GameConstants.team_trail_color(team)
	add_child(_trail_ribbon)

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
		AircraftWeapons.update_weapon_mode(self)
		AircraftCombatTracking.update_combat(self, lod_delta)
		AircraftPhysics.update_energy_management(self)
		AircraftPhysics.update_target_heading(self)
		AircraftPhysics.update_bank(self, lod_delta)
		AircraftPhysics.update_heading(self, lod_delta)
		AircraftPhysics.update_speed(self, lod_delta)
		AircraftPhysics.update_altitude(self, lod_delta)
		AircraftPhysics.update_fuel(self, lod_delta)
		AircraftPhysics.update_stall(self)
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
			# ── 编队托管模式 ──
			# 三段式：
			#   >REJOIN_DIST   → 纯追击归队（仅 b<0.05 的脱离重融合用）
			#   CLOSE~REJOIN   → 长机航向 + 横向偏置（leader-local frame，避免 bearing flip）
			#   <CLOSE_DIST    → 航向同步长机 + 微量漂移修正
			var ldr: Aircraft = _formation_leader
			var b := _formation_blend  # 0=自主飞行过渡, 1=正常编队

			# 计算离阵型槽位的距离
			var slot_dist := 0.0
			if target_position != Vector2.INF:
				slot_dist = global_position.distance_to(target_position)

			# 槽位在长机本地坐标系下的偏移（相对僚机）
			# slot_local.x > 0 → 槽位在僚机右侧（leader frame），需向右偏置
			# slot_local.y > 0 → 槽位在僚机后方，僚机需减速让槽位追上
			# slot_local.y < 0 → 槽位在僚机前方，僚机需加速追上
			# 关键：用"长机本地坐标"而不是"飞机→槽位的世界方位角"
			# 后者在长机转弯时 slot 绕长机切向移动 → 方位角剧烈摆动 → 旧 MID 分支机头乱扭
			var slot_local := Vector2.ZERO
			if target_position != Vector2.INF:
				slot_local = (target_position - global_position).rotated(-ldr.heading)

			# 微扰动：基于个体相位的缓慢正弦波
			var t := float(_lod_frame) * 0.02
			var jitter_heading := sin(t + _formation_jitter_phase) * 0.008
			var jitter_bank := sin(t * 0.7 + _formation_jitter_phase + 1.0) * 0.015

			const CLOSE_DIST := 50.0    # 以内纯航向同步
			const REJOIN_DIST := 800.0  # 以外纯追击归队
			const LEAD_BIAS_DIST := 250.0  # 横向偏置的虚拟前视距离（越大→偏置越温和）
			const MAX_BIAS := PI / 3.0     # 横向偏置最大角度（60°）

			# 调试：永远缓存槽位/分支等中间状态（开销可忽略，让 F12 快照不依赖 F11）
			_dbg_slot_pos = target_position
			_dbg_slot_dist = slot_dist
			_dbg_blend_ratio = 0.0
			_dbg_blended_heading = 0.0
			_dbg_slot_heading = 0.0

			# ── 先算好目标航向（由分支决定），然后用统一的"物理层 rate-limit"落位 ──
			# 这样无论走哪个分支，bank/heading 都受 roll_rate / max_g / 协同转弯公式约束，
			# 绝对不会发生瞬间 ±60° bank 或 ±180° 航向跳的情况。
			# 对刚出战的僚机尤其关键——之前 combat 离开时 bank 可能还在 ±80°，
			# 如果用 lerp(bank, 0, 4*delta) 会在几帧内抽回到 0，超过结构 G 极限。
			var target_heading: float = heading  # 默认不变
			var max_bank_ratio := 0.75           # 由分支调整

			if slot_dist > REJOIN_DIST:
				# 真正远距离：纯追击归队
				_dbg_branch = "FAR"
				if target_position != Vector2.INF and slot_dist > 10.0:
					var to_slot := (target_position - global_position).normalized()
					target_heading = atan2(to_slot.x, -to_slot.y)
					max_bank_ratio = 0.7
					_dbg_slot_heading = target_heading
			elif slot_dist > CLOSE_DIST:
				# 中距离：长机航向 + 横向偏置（leader-local frame）
				_dbg_branch = "MID"
				var bias_angle := atan2(slot_local.x, LEAD_BIAS_DIST)
				bias_angle = clampf(bias_angle, -MAX_BIAS, MAX_BIAS)
				target_heading = ldr.heading + jitter_heading + bias_angle
				max_bank_ratio = 0.75
				_dbg_slot_heading = bias_angle      # 复用字段：横向偏置角
				_dbg_blend_ratio = bias_angle / MAX_BIAS
				_dbg_blended_heading = target_heading
			else:
				# 近距离：直接跟长机航向
				_dbg_branch = "CLOSE"
				target_heading = ldr.heading + jitter_heading
				max_bank_ratio = 0.6

			_dbg_target_heading = target_heading

			# ── 统一"平滑且有物理限制"的落位 ──
			# 设计权衡：
			#   - 纯物理公式 (g·tan(bank)/TAS) 在编队中过慢：F-14 在 84° bank 也只有 ~21°/s，
			#     180° 归队要 9 秒，期间僚机会漂得很远。
			#   - 纯 lerp 没有上限，combat 刚结束从 ±80° bank 一瞬间归零，非物理突兀。
			# 折中：
			#   - heading 用 lerp 追目标，但角速度被 FORMATION_MAX_TURN_RATE (1.5 rad/s ≈ 86°/s) 硬夹。
			#     即使大 hdiff 也能在 2 秒左右 180° 翻转，够快但不突兀。
			#   - bank 由当前的 hdiff 自然推出（视觉），并按 params.roll_rate 严格限制滚转速率。
			#     保证 bank 过渡"真实飞机能做到"的那种感觉。
			var hdiff := _angle_diff(target_heading, heading)
			var max_bank_val := AircraftPhysics.max_bank_angle(self)
			var roll_rate_limit := params.roll_rate if params else 3.0

			const FORMATION_MAX_TURN_RATE := 1.5   # rad/s，编队归队的角速度硬上限
			const FORMATION_LERP_K := 5.0          # hdiff lerp 增益
			var desired_step := hdiff * FORMATION_LERP_K * delta
			var max_step := FORMATION_MAX_TURN_RATE * delta
			if absf(desired_step) > max_step:
				desired_step = signf(desired_step) * max_step
			heading = wrapf(heading + desired_step, -PI, PI)

			# 用更新后的 hdiff 推 desired_bank（和航向变化匹配，视觉一致）
			var hdiff_after := _angle_diff(target_heading, heading)
			var desired_bank := signf(hdiff_after) * max_bank_val * clampf(absf(hdiff_after) * 2.5, 0.0, max_bank_ratio)
			if _dbg_branch == "CLOSE":
				# 近距离让 bank 额外向长机 bank 靠拢，编队视觉更统一
				var ldr_target_bnk := ldr.bank_angle + jitter_bank
				desired_bank = lerpf(desired_bank, ldr_target_bnk, 0.6)
			_dbg_hdiff = hdiff
			_dbg_desired_bank = desired_bank

			# Bank 变化 rate-limit：严格 ≤ roll_rate
			# 这保留了用户要求的"不能超过物理极限"——bank 的变化速率永远 ≤ 飞机结构允许的滚转速率。
			var bank_step := clampf(desired_bank - bank_angle, -roll_rate_limit * delta, roll_rate_limit * delta)
			bank_angle += bank_step

			# 速度：根据 leader-local 纵向偏移调档
			# fwd_offset > 0 → 槽位在僚机前方（leader frame）→ 加速追
			# fwd_offset < 0 → 僚机已经超前于槽位 → 必须能减速（旧版只会加速）
			# 重要：所有目标速度都必须 clamp 到 _max_speed_at_altitude，
			# 否则在"长机阵亡 → 僚机(带 1.15x 超速)晋升为新长机"的循环中
			# 速度会被不断放大，后期出现 Mach 8+ 的暴走（见 2026-04-11 修复）
			var max_ms := AircraftPhysics.max_speed_at_altitude(self) / 3.6
			var jitter_speed := sin(t * 0.5 + _formation_jitter_phase + 2.0) * ldr.speed * 0.005
			var fwd_offset := -slot_local.y  # >0 = 槽位在前
			var chase_target: float
			var chase_rate: float
			if slot_dist > REJOIN_DIST:
				# 归队：大幅加速
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
				# 僚机超前于槽位 → 减速等槽位追上
				chase_target = ldr.speed * 0.92 + jitter_speed
				chase_rate = 3.0
			else:
				# 纵向基本对齐：匹配长机速度
				chase_target = ldr.speed + jitter_speed
				chase_rate = 3.0 + b * 3.0
			chase_target = clampf(chase_target, 0.0, max_ms)
			speed = lerpf(speed, chase_target, chase_rate * delta)
			# 同步 target_speed_kmh，避免 LOD 切换回 0 时残留的过期目标速度
			# 让 _update_speed 能无缝接管，而不是慢慢 decel 追老目标
			target_speed_kmh = speed * 3.6

			_dbg_chase_target_kmh = chase_target * 3.6

			# 调试：每秒一次把核心数值打到 EventLogger（仅在 formation_debug=true 时）
			if formation_debug:
				_dbg_log_timer -= delta
				if _dbg_log_timer <= 0.0:
					_dbg_log_timer = 1.0
					EventLogger.log_event("FORM_DBG", callsign,
						"branch=%s slot_d=%.0f b=%.2f hdg=%d→%d Δ=%+.1f° dbank=%+.0f° bank=%+.0f° spd=%d/%d ldrG=%.1f" % [
							_dbg_branch,
							_dbg_slot_dist,
							b,
							int(rad_to_deg(heading)),
							int(rad_to_deg(_dbg_target_heading)),
							rad_to_deg(_dbg_hdiff),
							rad_to_deg(_dbg_desired_bank),
							rad_to_deg(bank_angle),
							int(speed * 3.6),
							int(AircraftPhysics.max_speed_at_altitude(self)),
							ldr.g_load if is_instance_valid(ldr) else 0.0,
						])

			# 高度同步
			altitude = lerpf(altitude, ldr.altitude, (2.0 + b * 2.0) * delta)

			# 正常位移（全部位移通过 AircraftPhysics.apply_movement 走飞行物理）
			AircraftPhysics.apply_movement(self, delta)

			# 近距离微漂移：仅最后 50px 内做细微槽位对齐（很弱，避免平移感）
			if target_position != Vector2.INF and slot_dist > 3.0 and slot_dist < CLOSE_DIST and b > 0.05:
				var correction_dir := (target_position - global_position).normalized()
				var strength := clampf(slot_dist / CLOSE_DIST, 0.1, 1.0) * b * 0.4
				var correction_speed := speed * PIXELS_PER_METER * 0.15 * strength
				var move_px := minf(correction_speed * delta, slot_dist)
				global_position += correction_dir * move_px

			if every3:
				AircraftPhysics.update_fuel(self, delta)
				AircraftPhysics.update_g_load(self)
			_update_visuals()
			if selected or is_hovered or every3:
				queue_redraw()
			return

		# ── 非编队 LOD 1（降低运算频率） ──
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
			AircraftPhysics.update_altitude(self, delta)
			AircraftPhysics.update_fuel(self, delta)
			AircraftPhysics.update_stall(self)
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
	AircraftWeapons.update_weapon_mode(self)
	_update_evasion(delta)
	AircraftCombatTracking.update_combat(self, delta)
	AircraftPhysics.update_energy_management(self)
	AircraftPhysics.update_target_heading(self)
	AircraftPhysics.update_bank(self, delta)
	AircraftPhysics.update_heading(self, delta)
	AircraftPhysics.update_speed(self, delta)
	AircraftPhysics.update_altitude(self, delta)
	AircraftPhysics.update_fuel(self, delta)
	AircraftPhysics.update_shock_absorb(self, delta)
	AircraftPhysics.update_stall(self)
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
## cobra_maneuver.gd / herbst_maneuver.gd 在机动激活时手动调用
func _update_pilot_stamina(delta: float) -> void:
	AircraftPhysics.update_pilot_stamina(self, delta)

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
	return unit.name

func set_combat_target(target: CombatUnit) -> void:
	combat_target = target
	is_firing = false
	_strafe_state = 0  # 重置舔地状态机
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 切目标时解除机炮提交锁定
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
	var radar_range_px: float = params.radar_range               # 已经是像素，不要再乘
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
	var effective_dodge: float = bullet_dodge_chance
	if use_tactical_preference and evasion_mode:
		effective_dodge += 0.20  # 规避模式加成
	if get_altitude_tier() == AltitudeTier.HIGH:
		effective_dodge += 0.20  # HIGH 高度加成
	if effective_dodge > 0.0 and randf() < effective_dodge:
		_trigger_evasion_roll()  # 闪避滚转动画
		return  # 闪避成功，无视伤害
	if survivor_bullet_damage_cap > 0.0:
		amount = minf(amount, survivor_bullet_damage_cap)
	amount = _apply_armor(amount, 0.0)  # 机炮不穿甲，护甲全额生效
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
		_start_destroy()

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
	if altitude <= 0.0 and not is_destroyed:
		altitude = 0.0
		_start_destroy()

## 坠毁系统委托给 AircraftDestruction（aircraft_destruction.gd）
func _start_destroy() -> void:
	AircraftDestruction.start(self)

func _update_destroy(delta: float) -> void:
	AircraftDestruction.update(self, delta)

# ========== 雷达 ==========

## 判断目标世界坐标是否在本机雷达锥内
func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	var radar_r := params.radar_range if params else 300.0
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
		AircraftRenderer.draw_gun_cone(self)
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

# ========== 热诱弹系统 ==========

func is_lock_immune() -> bool:
	return _lock_immunity_timer > 0.0 or is_cloaked

## HUD 用：热诱弹冷却比例（委托 AircraftFlares）
func get_flare_cooldown_ratio() -> float:
	return AircraftFlares.cooldown_ratio(self)


func _update_visuals() -> void:
	rotation = heading
