class_name Aircraft
extends CombatUnit

@export var params: AircraftParams
@export var initial_heading_deg: float = 0.0  ## 度 初始航向（0=北, 90=东, 180=南）

# --- 状态 ---
var vertical_speed: float = 0.0     ## m/s
var bank_angle: float = 0.0         ## 弧度
var _prev_bank_for_rate: float = 0.0  ## 上一帧 bank（用于发射稳定性检查计算 roll rate）
var _bank_rate_rad_s: float = 0.0     ## 滚转率，rad/s（EMA 平滑，避免单帧噪声）
var _turn_rate_filt: float = 0.0      ## 低通滤波后的航向角速度，rad/s（PD 控制 D 项输入；破除单帧代数环 Nyquist 抖）
var _prev_tgt_heading_pd: float = NAN ## 上一帧目标方位（算 LOS 角速度用；NAN=未初始化）
var _los_rate_filt: float = 0.0       ## 低通滤波目标 LOS 角速度，rad/s（PD 前馈项：跟随转弯目标时补偿稳态转速，免得 D 项与必要转速对抗成弛豫振荡）
var _committed_turn_sign: float = 0.0  ## 转弯方向锁定：0=未锁定, +1/-1=锁定方向
var g_load: float = 1.0
var is_stalled: bool = false
var _stall_recovery_timer: float = 0.0  ## 失速恢复冷却（防止反复失速抽搐）
## 死亡溯源：take_bullet_damage 在致死的那一击设为 true
## survivor_spawner._detect_kills 据此判断是否触发"机炮击杀恐惧"AOE
var _killed_by_bullet: bool = false
## 玩家专属：恐惧扩散持续时间（>0 时玩家击杀任意敌机后给同小队所有成员挂 FEAR）
var fear_squad_spread_duration: float = 0.0
## 玩家专属：施加 FEAR 时同步附带 SLOW（同 duration）
var fear_applies_slow: bool = false

# --- 目标 ---
var target_position: Vector2 = Vector2.INF  ## 世界坐标, INF=无目标
var keep_target_on_arrival: bool = false    ## true=外部管理target_position，到达时不清除

## ── 预测路径缓存（世界坐标）──
## 玩家专用，~20Hz 重算（每 50ms 一次）。每帧渲染只做 O(N) 的 to_local 转换。
## 不每帧重算的两个原因：
##   ① 600 步 × N 个 helper 的 dictionary 查询太贵，单帧能吃 5-10ms 把 FPS 砸到 30-
##   ② FE 积分在长程上对 state 微扰非常敏感，每帧重算的 "尾端" 会肉眼可见地抖动
## 50ms 间隔下，玩家 800km/h 飞约 11m / 22px，世界点缓存对预测末端的视觉稳定性贡献巨大
## 预测窗口 ~6 秒（360 步 × 1/60s）—— 比 3 秒长是因为 G10 拉 90° 弯本身就要 4-5 秒，
## 短窗口只看得到能量崩溃段（红色），看不到转完恢复（蓝色），视觉上呈现"红短线突然变蓝长线"。
## 6 秒能容纳完整的"拉 G 掉速 → 对准目标 → 加速恢复"能量曲线，自然平滑。
## 性能：20Hz × 360 步 × ~5µs ≈ 36ms/秒（3.6% 预算），可接受。
const PRED_MAX_STEPS: int = 360
var _predicted_path_world: PackedVector2Array = PackedVector2Array()        ## 最新 cache（target，20Hz 跳变）
var _predicted_path_healths: PackedFloat32Array = PackedFloat32Array()
## 平滑视图：每帧 lerp 向 _predicted_path_world，实际渲染用这个
## 修复"6 秒预测推进时高速瞬移"的视觉问题——cache 在 20Hz 离散更新，
## 平滑视图填补 50ms 间隔让线条连续追平
var _predicted_path_smooth_world: PackedVector2Array = PackedVector2Array()
var _predicted_path_smooth_healths: PackedFloat32Array = PackedFloat32Array()
const PRED_SMOOTH_LERP_RATE: float = 24.0  ## 时常数 ~42ms，差不多 cache 间隔
var _predicted_path_cache_ms: int = 0
## 长度平滑保留：处理 arrival_dist 阈值穿越时的边界跳变（极少见）
var _predicted_path_visible_n_smooth: float = 0.0
var _predicted_path_last_draw_ms: int = 0
var _predicted_path_last_target: Vector2 = Vector2.INF
const PREDICTED_PATH_REFRESH_MS: int = 50
const PRED_LEN_LERP_RATE: float = 6.0
const PRED_TARGET_RESET_PX: float = 200.0
## 诊断：保存上次 prediction 用于计算两次 refresh 之间形状偏移量
## 偏移大说明预测线"跳"得厉害；按阈值打 PRED_JUMP 事件方便在 log 里搜出抽搐瞬间
var _predicted_path_prev_world: PackedVector2Array = PackedVector2Array()
var _predicted_path_diag_step: int = 0
const PRED_JUMP_PX_THRESHOLD: float = 80.0
var formation_mode: bool = false            ## true=编队托管模式，直接复制长机状态
## 编队 FAR 归队时放开 bank 上限到满 G（像玩家一样硬转回阵线）；MID/CLOSE 站位保持柔和 0.9 cap。
## 由 AircraftFormation._update_bank_via_pd 每帧按 branch 写。
var _formation_full_bank: bool = false
var _formation_leader: Aircraft = null      ## 编队长机引用（formation_mode时使用）
## 稳定号机号（spec squad-control-switching §2.1）：玩家小队内 1..N，出生即定、永不变。
## 数字键 1-4 切换操控按此映射（键 N → squad_slot==N 的飞机），与会随接管变动的
## AIController.squad_index（0=长机）解耦——保证"按键 N 永远对应同一架物理飞机"。
## 0 = 未分配（非玩家小队成员）。spawn 起始僚机时按生成序赋值。
var squad_slot: int = 0
## 注：_formation_blend / _formation_jitter_phase 单边住在 AIController（_ai_ref._formation_blend 等）。
## 旧 API 把这两个字段在 Aircraft 上镜像了一份导致每帧手动同步，2026-05-04 重构删除。
## 子模块 AircraftFormation 通过 ac._ai_ref 直接读 AI 端的值，单一权威源。
var _ai_ref: AIController = null             ## 由 AIController._ready 回写；编队/规避代码读 blend/jitter
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
## 玩家对【这架机】显式点名下达的攻击命令目标（RTS 铁律）。逐机持有、跨 1/2/3/4 切控持久：
## AI / 自动交战一律不得覆盖；只在目标阵亡、或玩家对本机另下移动/取消/新攻击命令时清除。
## 默认 null（无玩家命令），仅玩家方使用。见 docs/specs/systems/rts-command.md。
var commanded_target: CombatUnit = null
var is_firing: bool = false
var ammo: int = 500
# 自动扫描机炮目标的节流计时器：60Hz 扫描无意义，且每次扫描都是 O(N) 遍历全场单位
var _auto_gun_scan_timer: float = 0.0
var _fire_cooldown: float = 0.0
var _gun_lead_heading: float = 0.0  ## 前置射击方向（由 _update_combat 计算）
## 敌方 AI 机炮 burst-pause 节奏：连续射击 AI_GUN_BURST_DURATION 秒后强制 AI_GUN_PAUSE_DURATION 秒不开火，
## 给玩家挣脱尾追的窗口。仅 team != 0 生效，玩家/玩家僚机不受限。
const AI_GUN_BURST_DURATION: float = 2.5
const AI_GUN_PAUSE_DURATION: float = 3.0
var _ai_gun_burst_timer: float = AI_GUN_BURST_DURATION  ## 当前 burst 剩余可射秒数
var _ai_gun_pause_timer: float = 0.0                    ## 当前 pause 剩余秒数（>0 时禁射）
var _in_rear_hemisphere: bool = false  ## 是否处于敌机后半球（由 _update_combat 计算）
var _overshoot_timer: float = 0.0   ## 近距过顶 extension 计时（秒），>0 时强制沿机头直飞脱离
var ai_override_pursuit: bool = false  ## AI 战术机动时跳过自动追踪，由 AI 直接控制 target_position
var bullet_manager: Node2D = null   ## 由 main.gd 注入
var missile_manager: Node2D = null  ## 由 main.gd 注入

# --- 火箭弹（无制导副武器，全自动扫描齐射） ---
var rockets_remaining: int = 0
var _rocket_burst_cooldown: float = 0.0  ## 齐射冷却
var _rocket_queue: Array[Dictionary] = []  ## 待发射火箭队列 { delay: float, heading: float, pos: Vector2, pylon: int }

# --- 空中鱼雷（规避模式下自动抛出的追踪雷） ---
var _torpedo_cooldown: float = 0.0  ## 抛雷冷却（规避模式下持续倒数）

# --- 忠诚僚机无人机（规避模式下从机尾释放的伴飞 drone） ---
var _loyal_wingman_cooldown: float = 0.0  ## 释放冷却（规避模式下持续倒数）
var _drone_squad: Squad = null            ## 懒创建的无人机 squad（leader=self；与 player.squad 解耦）
var _alive_drones: Array[Aircraft] = []   ## 当前活着的 drone 引用（cap 计数 + 死亡清理）

# --- 导弹 ---
enum WeaponMode { MISSILE, GUN }
var weapon_mode: int = WeaponMode.GUN
var missiles_remaining: int = 0
var secondary_missiles_remaining: int = 0  ## 副导弹槽剩余数（独立计数）
var _missile_cooldown: float = 0.0

# --- 副导弹槽位（开发代号 secondary_missile，玩家面叫 SP）---
# 完全独立子系统：独立锁定锥 / 独立目标 / 独立 cooldown / 独立装填 / 不吃 MSL 升级
# enable 默认关，仅玩家在 SurvivorPlayableSetup 显式开启
var secondary_missile_enabled: bool = false
var secondary_radar_targets: Dictionary = {}    ## CombatUnit -> 锁定累积秒
var secondary_combat_target: CombatUnit = null  ## 自动选定的副槽目标
var _secondary_cooldown: float = 0.0
var _secondary_reload_active: bool = false
var _secondary_reload_timer: float = 0.0
var _secondary_radar_tick_acc: float = 0.0  ## 0.5s tick 累加器（性能：避免每帧扫描）
var _sfx_gun_cd: float = 0.0  ## 机炮音效节流（每 0.5s 最多一次），防扫射刷声道
var _crank_timer: float = 0.0          ## 发射后保持照射计时（秒），> 0 时飞机维持稳定航向
const CRANK_DURATION: float = 8.0      ## 发射后保持照射的时长
const LOCK_STABLE_BUFFER: float = 0.3  ## 锁定后额外稳定时间才允许发射（AI 防抖，原 1.0 让 UAV 高机动下永远咬不到阈值）

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
## deg。默认 60° 只抓硬机动；reversal bench 把它调低到 ~20° 以完整记录每次 180° 反转的全弧（含过零段）
static var AC_TICK_BANK_THRESHOLD := 60.0
var _gun_aim_log_until: float = 0.0  # 节流 [GUN_AIM] 诊断：0.5s 一次

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

## RTS 自动交战（auto-engage）：到达巡航点/空闲时自动在半径内锁最近敌机。
## 仅生存模式玩家长机读取（survivor_mode._update_auto_engage）；敌机不读此字段。
## 默认开，右侧战术栏可关；关闭后小队到点纯待命，手动点敌仍可交战。见 docs/specs/systems/rts-command.md
var auto_engage_enabled: bool = true

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

## 装备运行时状态（commit 8/13 起）：每件 EquipmentParams 子类用 equipment_kind 作 key
## 写入 / 读出自己的状态字典。避免 Aircraft 字段污染。
## 例：RailgunEquipment 用 "railgun" key，存 charge_progress / beam_fade / cooldown 等。
var equipment_state: Dictionary = {}

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
var altitude_authority_mult: float = 1.0  ## 高度操纵权威（云雾机动）：gain/smooth_rate 全幅放大，max_climb 顶 +30% 防 PE↔KE 反抽
var cloud_lock_stealth: bool = false      ## 云雾隐身（云雾机动战区奖励）：云中任意高度档 lock_rate ×0.1
var ecm_range_mult: float = 1.0           ## ECM 吊舱（战区奖励）：敌人雷达对我的有效距离 × 此值（0.75 = 缩短 25%）
var category_radar_mult: float = 1.0      ## 词条联动：电子战类技能数量 → 雷达/锁定范围。由 SurvivorData.recompute_category_bonuses 写

# ── 状态效果系统（StatusEffects 模块管理）──
## 容器 status_effects + JAM 派生标记 status_jam_active 在 CombatUnit 基类，敌我对称
## 这里只保留**仅 Aircraft 生效**的派生标记（地面单位 / 船 / 巨型 BOSS 不会识别）
var status_invincible_active: bool = false ## INVINCIBLE buff 派生标记
var status_stealth_active: bool = false    ## STEALTH buff 派生标记
var status_bloodlust_active: bool = false  ## BLOODLUST buff 派生标记
var status_overload_active: bool = false   ## OVERLOAD buff 派生标记
var status_slow_active: bool = false       ## SLOW debuff 派生标记
var status_fear_active: bool = false       ## FEAR debuff 派生标记

## 无驾驶员标记（UAV / UCAV / Sentinel / Aegis UAV 等）
## 心理类状态（FEAR）不该对无人机生效——无人机不会"恐惧"。
## survivor_spawner 在创建时根据 enemy_type 设置；玩家 + 载人战机默认 false
var no_pilot: bool = false

## ── 便利贴技能字段（C 阶段批量实装）──
## 各字段由 SurvivorPlayer.apply_upgrade 写入；消费点在对应模块 early-check
var lock_panic_g_mult: float = 1.0          ## 被锁时 effective_max_g 倍率（physics）
var low_hp_flare_reload_mult: float = 1.0   ## hp < 50% 时 flare reload 倍率（flares）
var high_alt_lock_speed_bonus: float = 0.0  ## HIGH 档锁定速率 bonus（main 雷达循环）
var ab_gun_regen_per_sec: float = 0.0       ## AB 时机炮子弹 regen/s（weapons.update_gun）
var alt_change_stealth_factor: float = 0.0  ## 高度变化时锁定衰减系数（main 雷达循环）
var head_on_gun_dodge_bonus: float = 0.0    ## 对头时机炮闪避加成（take_bullet_damage 加查）
var low_alt_gun_dodge_bonus: float = 0.0    ## 低空时机炮闪避加成（take_bullet_damage 在 LOW/GROUND 档位加）
var gun_fire_dr_window: float = 0.0         ## 机炮发射后 N 秒内受到伤害减免（_apply_damage 查）
var gun_fire_dr_amount: float = 0.0         ## 该时间窗内伤害减免比例（0.5 = -50%）
var _gun_fire_recently_until: float = 0.0   ## 时间戳：本时刻以前在开火窗口内
var fear_on_lock_threshold: float = 0.0     ## 锁定累积达 N 秒后给目标施加 FEAR（0=禁用）
var _locked_target_seconds: Dictionary = {} ## { instance_id → 累积秒数 }（玩家专用）

## 反向索引：当前正在攻击我（_current_target == self）的敌方 AI 集合
## AIController 在切目标到我时增量写入；切走时移除。0 扫描，纯增量更新
## 配套技能：后半球减速光环 / JAM 光环（依赖此集合判定"和你缠斗中的敌人"）
var engaging_me: Dictionary = {}              ## { Aircraft instance_id → Aircraft }
## 后半球敌人减速光环：每 0.5s 扫描后半球 + 距离内的敌人 → 累加 SLOW
## 累积式光环：累积期不生效；累积满施 Debuff；Debuff 期间不累积；消退后从 0 重新累积
## 离开半径不归零（玩家可短暂脱离再回来续累积，避免取巧）
var rear_aura_slow_radius_px: float = 0.0     ## 0=禁用；半径 px
var _rear_aura_accum_seconds: Dictionary = {} ## { instance_id → 累积秒数 }
## 全向 JAM 光环（同累积模式）
var jam_aura_radius_px: float = 0.0            ## 0=禁用；半径 px
var _jam_aura_accum_seconds: Dictionary = {}   ## { instance_id → 累积秒数 }
## 累积式光环统一参数
const AURA_ACCUMULATE_SECONDS: float = 8.0    ## 累积满需要 8s 持续在半径内
const AURA_DEBUFF_DURATION: float = 4.0       ## Debuff 持续秒数
const AURA_INTERNAL_CD: float = 4.0           ## 触发 debuff 后整个光环锁 4s（= debuff 时长，期间不再扫描 / 施加新 debuff）
var _rear_aura_cd_remaining: float = 0.0
var _jam_aura_cd_remaining: float = 0.0

## F-14 专属：全僚机锁定同一敌机时给该敌机施加 SLOW（survivor_mode 雷达循环维护）
var f14_squad_lock_slow_active: bool = false

## 云中事件触发器（玩家专用，每帧 main 场景检测进/出云事件 → 触发对应钩子）
##   cloud_overload_active: 进云时 apply OVERLOAD，出云时 remove
##   cloud_weapon_cd_mult:  进云时按倍率 scale 武器 cd（与 evasion_modifiers 同模式），出云反向
var cloud_overload_active: bool = false      ## 技能解锁标记：玩家是否选了"云中超载"
var _in_cloud_overload: bool = false          ## 运行时：当前是否处于云中且解锁此技能（StatusEffects.update OR 进派生标记）
var cloud_weapon_cd_mult: float = 1.0        ## 技能：在云中武器 cd 倍率（< 1.0 = 更快）
var _was_in_cloud_last_frame: bool = false   ## 用于检测进/出云边界事件

## 进入 evasion 模式时启用 STEALTH（独立 bool + 派生 OR，避免与其它 STEALTH 来源冲突）
var evasion_stealth_active: bool = false     ## 解锁标记：玩家是否选了"evasion 隐身"
var _in_evasion_stealth: bool = false         ## 运行时：当前是否处于 evasion 模式且解锁
const EVASION_STEALTH_DELAY: float = 2.0      ## 进入 evasion 后多少秒激活隐身
var _evasion_stealth_timer: float = 0.0       ## evasion 进入后累计（仅当 evasion_stealth_active 时累加）

## 弹药打空后获得 5 秒 STEALTH（玩家技能 missile_cd_stealth）
## 与 evasion_stealth 同模式：解锁标记 + 运行时派生标记，status_effects.gd 里 OR 进派生
const MISSILE_DEPLETED_STEALTH_DURATION: float = 5.0
var missile_cd_stealth_active: bool = false   ## 解锁标记：玩家是否选了"弹后潜匿"
var _in_missile_cd_stealth: bool = false       ## 运行时：当前是否处于打空隐身窗口
var _missile_cd_stealth_timer: float = 0.0    ## 残余隐身时间（秒）
var _prev_missiles_remaining: int = -1         ## 上一帧弹药数（边沿检测；-1=未初始化）

## 对头干扰：和我面对面（双向 dot > 0.7）的雷达锥内敌机累计 N 秒后施加 JAM
## 与 fear_on_lock 同模式：每帧扫 radar_targets，单位级累积；JAM 命中后该 entry 重置
var head_on_jam_threshold: float = 0.0        ## 0=禁用；> 0 = 累积秒数
var _head_on_jam_seconds: Dictionary = {}      ## { instance_id → 累积秒数 }
const HEAD_ON_JAM_DOT: float = 0.7             ## 双向 dot 阈值（≈ 45° 对头锥）
const HEAD_ON_JAM_DURATION: float = 5.0        ## 触发后给目标的 JAM 时长
## 进入 evasion 模式时触发 J-Turn（HerbstManeuver）作为反击（被攻击触发，非主动）
var evasion_herbst_active: bool = false       ## 解锁标记：玩家是否选了"evasion J-Turn"

## evasion 模式中每 N 秒装填 1 发导弹，可突破 max_count×2 上限
## value=4.0 表示每 4s 一发；超过 max_count×2 不再装
var evasion_overstock_interval: float = 0.0   ## 0=禁用；>0 = 装填周期秒数
var _evasion_overstock_timer: float = 0.0     ## 当前周期计时（仅 evasion ON 时累加）
var _alt_velocity: float = 0.0              ## abs 高度变化速率（m/s 平滑），主场景每帧累算
var _alt_velocity_prev: float = 0.0         ## 上一帧 altitude，用于差分
## owner 追踪：状态系统是否是 invulnerable / is_cloaked 的当前置位者
## 防止状态结束时把别的系统（航母弹射 / F-47 BOSS cloak）的设值也清掉
var _status_owns_invul: bool = false
var _status_owns_cloak: bool = false
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
var is_drone: bool = false           ## 忠诚僚机无人机标记：跳过预测线 / 数据标签 / 高度文本，纯 2D 视觉

## 玩家光环技能 ID（仅长机持有；&""=无）。当前实现：&"data_link"（F-14 专属）
## 在 survivor_mode._update_radar_locks 由全局逻辑读取，本类自身不消费此字段。
var aura_skill: StringName = &""

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

## ── 僚机护卫姿态（spec wingman-escort-evasion）──
## 长机（玩家）按 E 时由 _propagate_evasion_to_squad 广播给僚机置位；关 E 清零。
## 与 evasion_mode 解耦：护卫待命期间僚机 evasion_mode 必须为 false，否则 planner 的
## Situation.evasion_intent 会让待命僚机也出 EVADE_MISSILE intent（max+AB）散开飞离阵型。
## 僚机收到后：自己被真威胁才 enter_evade 逃命；否则回编队待命 + 替长机投护卫 flare。
var escort_cover_active: bool = false
## 护卫 flare 单弹单次记录（导弹 instance_id → true）：每枚导弹本机只护卫尝试一次，
## 防止多架僚机/多帧轮流 jam 同一弹让长机无敌。由 AircraftFlares 清理失效引用。
var _escort_flare_tried: Dictionary = {}

## ── §1.2 evasion_modifiers：模式切换时按差量缩放运行时倒计时（避免每帧重算） ──
## 技能 apply 时往该 dict 写倍率（< 1.0 = cd 缩短，> 1.0 = cd 延长）；
## set_evasion_mode 切换瞬间一次性 scale/unscale 各 cd —— 进行中的倒计时按比例缩放，
## 不会"倒回去"。默认 1.0 = 无修饰。技能消费点（cruise_speed_mult 等）每帧直接查表。
var evasion_modifiers: Dictionary = {
	"weapon_cd_mult": 1.0,        ## 机炮 + 导弹 + 火箭三路 cd（_fire_cooldown / _missile_cooldown / _rocket_burst_cooldown）
	"flare_cd_mult": 1.0,         ## 热诱弹冷却（_flare_cooldown）
	"missile_reload_mult": 1.0,   ## 导弹装填（_missile_reload_timer）
	"cruise_speed_mult": 1.0,     ## 巡航速度上限倍率（physics 每帧查）
}

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
	# Perf：360→80（与 missile/default 一致）。原 360 在 30s 后 trail 填满 → per-call _draw 成本
	# 4.7× 增长（80 → 360 个三角形条带顶点 + to_local 调用）。bench/results 5s vs 30s 对比定位。
	# 视觉上尾迹更短（80 点 × 0.05s = 4s 长度）但战斗中差异不明显。
	_trail_ribbon.max_points = 80
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
	# Cobra / Herbst 没有 params 字段；equipment 声明 → 自动挂载 Node 子节点
	# 已存在的子节点（survivor_player / spawner / poltergeist_squad 手动 add_child 路径）跳过
	if params.has_equipment_of_kind("cobra") and get_maneuver() == null:
		add_child(CobraManeuver.new())
	if params.has_equipment_of_kind("herbst") and get_herbst() == null:
		add_child(HerbstManeuver.new())

## 装备运行时驱动器（commit 8/13 起）
## 每帧调用 params.equipment 数组每件的 update(self, delta)。
## 老装备（GunEquipment/RocketEquipment 等）的 update 是 base no-op —— 它们的实际逻辑
## 仍在 AircraftWeapons.update_gun 等里跑。
## 新装备（RailgunEquipment / LaserEquipment）在 update 里实现完整逻辑。
func _update_equipment(delta: float) -> void:
	if params == null or params.equipment.is_empty():
		return
	for eq in params.equipment:
		if eq != null:
			eq.update(self, delta)

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
	if _ai_ref:
		return _ai_ref
	for child in get_children():
		if child is AIController:
			_ai_ref = child
			return child
	return null

## 进入/更新编队托管态。统一收口避免散布在多处的 4-5 行字段写入块。
##   - formation_mode = true / _formation_leader = leader
##   - target_position = slot_pos（INF 时跳过）
##   - keep_target_on_arrival = keep_arrival
##   - lod_level = 1（编队托管走 LOD 1 简化路径）
func set_formation_target(leader: Aircraft, slot_pos: Vector2, keep_arrival: bool = true) -> void:
	formation_mode = true
	_formation_leader = leader
	if slot_pos != Vector2.INF:
		target_position = slot_pos
	keep_target_on_arrival = keep_arrival
	lod_level = 1

## 退出编队托管（切到 ENGAGE / EVADE / 长机阵亡 / 规避来袭等）
##   - formation_mode = false / _formation_leader = null
##   - keep_target_on_arrival = false / ai_override_pursuit = false
##   - lod_level = 0（恢复完整模拟）
## 注：不动 combat_target —— 调用方按需自己 set/clear，避免清掉刚锁定的目标
func clear_formation() -> void:
	formation_mode = false
	_formation_leader = null
	keep_target_on_arrival = false
	ai_override_pursuit = false
	lod_level = 0
	# 清掉残留的编队槽位 target_position：否则脱离编队后被动开火/巡航会朝旧槽位压满坡度抖动
	# （进 ENGAGE 会被 combat_tracking 立即重设 lead 点，无副作用；2026-06-07 修 PASSIVE_AUTO_FIRE 抖）
	target_position = Vector2.INF

func get_herbst() -> HerbstManeuver:
	for child in get_children():
		if child is HerbstManeuver:
			return child
	return null

func _physics_process(delta: float) -> void:
	# Perf 包装：整个飞机物理 / 武器 / 战斗追踪 / 装备 / 状态效果聚合到 aircraft_phys 桶
	# 这是 LOD 0 主要工作，按 N 架 × 60Hz 缩放，疑似 CSG/Phase2 掉帧主因
	var _perf_t0: int = Time.get_ticks_usec()
	_physics_process_impl(delta)
	PerfBuckets.tick("aircraft_phys", Time.get_ticks_usec() - _perf_t0)


func _physics_process_impl(delta: float) -> void:
	_lod_frame += 1
	if _tactic_popup_timer > 0.0:
		_tactic_popup_timer -= delta
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return
	# Perf 子桶 ac_phys.misc.* —— 拆 6 段精确定位 misc 膨胀来源
	# 全 LOD 共用，每段单独埋点，misc 总和仍由 PerfBuckets 自然累加（看 sum 即可）
	var _t_misc1: int = Time.get_ticks_usec()
	_update_cloud_state(delta)
	PerfBuckets.tick("ac_phys.misc.cloud", Time.get_ticks_usec() - _t_misc1)
	var _t_misc2: int = Time.get_ticks_usec()
	_update_in_building(delta)
	PerfBuckets.tick("ac_phys.misc.building", Time.get_ticks_usec() - _t_misc2)
	var _t_misc3: int = Time.get_ticks_usec()
	_update_gun_threat_indicator(delta)
	PerfBuckets.tick("ac_phys.misc.gun_threat", Time.get_ticks_usec() - _t_misc3)
	var _t_misc4: int = Time.get_ticks_usec()
	update_lock_line_state(delta)
	PerfBuckets.tick("ac_phys.misc.lock_line", Time.get_ticks_usec() - _t_misc4)
	var _t_misc5: int = Time.get_ticks_usec()
	_update_equipment(delta)
	PerfBuckets.tick("ac_phys.misc.equipment", Time.get_ticks_usec() - _t_misc5)
	var _t_misc6: int = Time.get_ticks_usec()
	StatusEffects.update(self, delta)
	PerfBuckets.tick("ac_phys.misc.status_fx", Time.get_ticks_usec() - _t_misc6)

	# LOD 2（屏幕外）：每3帧完整处理，其余帧仅位移
	if lod_level >= 2:
		# 编队跟随机：屏外也必须维持编队几何，否则 leader 机动后 follower 漂出阵型
		# （旧版 LOD 2 完全不调 update_follow → 三轰炸机/Sentinel UAV 漂离）
		# update_follow 内部已按 _lod_frame % 3 把 speed/altitude 节流到 20Hz；
		# heading/bank/position 60Hz 是必要开销（leader 转向时槽位变化太快）
		if formation_mode and _formation_leader and is_instance_valid(_formation_leader):
			AircraftFormation.update_follow(self, delta)
			AircraftFlares.update(self, delta)  # 编队中也要更新/清除 flare 粒子，否则残留不消失
			return
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
		AircraftWeapons.update_torpedo(self, lod_delta)
		AircraftWeapons.update_loyal_wingman(self, lod_delta)
		# 副导弹槽（独立子系统，不依赖 combat_target）
		AircraftWeapons.update_secondary_radar(self, lod_delta)
		AircraftWeapons.update_secondary_missile(self, lod_delta)
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
			AircraftFlares.update(self, delta)  # 编队中也要更新/清除 flare 粒子，否则残留不消失
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
		AircraftWeapons.update_torpedo(self, delta)
		AircraftWeapons.update_loyal_wingman(self, delta)
		# 副导弹槽（独立子系统）
		AircraftWeapons.update_secondary_radar(self, delta)
		AircraftWeapons.update_secondary_missile(self, delta)
		if every3:
			AircraftFlares.update(self, delta)
		_update_visuals()
		if selected or is_hovered or every3:
			queue_redraw()
		return

	# LOD 0 编队跟随（2026-06-07 修）：与 LOD1/2 一致，formation_mode 时走 update_follow。
	# 之前 LOD0 缺这个分支 → 屏内编队僚机落到下面的 planner WAYPOINT_MOVE 纯追击，
	# 没有"长机机体系槽位 + bank 镜像 + 切弯"逻辑，长机一转弯就严重掉队（log 落后到 2000px+）。
	# 玩家(formation_mode=false，spawn 时 clear_formation) / 交战僚机(进 ENGAGE 时 clear_formation)
	# 都不会命中此分支，照走下面完整 LOD0；只有真正编队跟随的僚机走 update_follow。
	if formation_mode and _formation_leader and is_instance_valid(_formation_leader):
		AircraftFormation.update_follow(self, delta)
		AircraftFlares.update(self, delta)  # 编队中也要更新/清除 flare 粒子，否则残留不消失
		return

	# LOD 0（完整）：玩家 / 交战中
	# P1：planner 在最顶层先跑，写 target_position/target_speed/weapon_mode/is_firing；
	# 后面 update_weapon_mode / update_combat / update_energy_management 各自 early-return
	#
	# Perf 子桶（仅 LOD 0 实装；27 架混战时 90% 走这条路径）：
	#   ac_phys.combat — planner / weapon_mode / evasion / combat_tracking
	#   ac_phys.kine   — physics 全家（energy/heading/bank/speed/stall/altitude/fuel/g/movement）
	#   ac_phys.wpn    — auto_gun_scan / gun / ciws / rocket / missile / torpedo / loyal_wingman
	#   ac_phys.evade  — cobra / herbst / flares
	#   ac_phys.visual — _update_visuals / _log_ac_tick
	# 配合 ac_phys.misc（顶部）+ aircraft_phys 总桶 → 看哪个子桶随时间膨胀

	# ac_phys.combat.* — 拆 4 段：哪个真正在膨胀
	# planner 调 BfmIntent + Situation.from_aircraft（涉及全场态势抽样）
	# combat_tracking 调 BFM lead 计算 + 武器锁定 + 雷达扫描
	# weapon_mode + evasion 通常很轻
	var _t_planner: int = Time.get_ticks_usec()
	_run_tactical_planner_if_enabled()
	PerfBuckets.tick("ac_phys.combat.planner", Time.get_ticks_usec() - _t_planner)
	var _t_wmode: int = Time.get_ticks_usec()
	AircraftWeapons.update_weapon_mode(self)
	PerfBuckets.tick("ac_phys.combat.wmode", Time.get_ticks_usec() - _t_wmode)
	var _t_evade1: int = Time.get_ticks_usec()
	_update_evasion(delta)
	PerfBuckets.tick("ac_phys.combat.evasion", Time.get_ticks_usec() - _t_evade1)
	var _t_track: int = Time.get_ticks_usec()
	AircraftCombatTracking.update_combat(self, delta)
	PerfBuckets.tick("ac_phys.combat.track", Time.get_ticks_usec() - _t_track)

	var _t_kine: int = Time.get_ticks_usec()
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
	PerfBuckets.tick("ac_phys.kine", Time.get_ticks_usec() - _t_kine)

	var _t_wpn: int = Time.get_ticks_usec()
	AircraftWeapons.auto_gun_scan(self)
	AircraftWeapons.update_gun(self, delta)
	AircraftWeapons.update_ciws(self, delta)
	AircraftWeapons.update_rocket(self, delta)
	AircraftWeapons.update_missile(self, delta)
	AircraftWeapons.update_torpedo(self, delta)
	AircraftWeapons.update_loyal_wingman(self, delta)
	# 副导弹槽（独立子系统，不走 update_missile 的统一池路径）
	AircraftWeapons.update_secondary_radar(self, delta)
	AircraftWeapons.update_secondary_missile(self, delta)
	PerfBuckets.tick("ac_phys.wpn", Time.get_ticks_usec() - _t_wpn)

	var _t_evade: int = Time.get_ticks_usec()
	# 眼镜蛇技能必须在 AircraftFlares.update 之前 —— 一旦激活，flare 会因机动 active 而跳过
	_update_cobra_skill(delta)
	# 危机赫尔贝特：与眼镜蛇共用触发条件（来袭导弹 / 后方机炮追尾），二选一
	_update_evasion_herbst_skill(delta)
	AircraftFlares.update(self, delta)
	PerfBuckets.tick("ac_phys.evade", Time.get_ticks_usec() - _t_evade)

	var _t_visual: int = Time.get_ticks_usec()
	_update_visuals()
	_log_ac_tick(delta)
	PerfBuckets.tick("ac_phys.visual", Time.get_ticks_usec() - _t_visual)
	# LOD 0 非玩家非悬停：每 2 帧重绘一次，减半 _draw 开销
	if selected or is_hovered or _lod_frame % 2 == 0:
		queue_redraw()

## P1：TacticalPlanner 入口。建态势 → 决策 → 应用。
## 仅在 use_tactical_planner=true 时跑，不影响默认旧路径。
func _run_tactical_planner_if_enabled() -> void:
	if not use_tactical_planner:
		return
	# ── 目标死亡守卫（与 aircraft_combat_tracking.update_combat 73-76 行对称）──
	# planner 的 CRUISE intent 不写 target_position（保留给 evade 自己控制），
	# 因此必须在这里显式清掉 target_position，否则飞机会继续飞向死敌的最后 lead 点
	# ⚠ 但 target_position 同时承载玩家 click waypoint / 编队槽位 / 巡逻点 等"非战斗写入"，
	# 一律清成 INF 会摧毁玩家 click + 触发"敌人死 → click 丢失 → 自动锁新敌人 → target_position
	# 单帧跳到对侧 → bank 翻越 0 度（机身 roll）"病态链。
	# 仅当上一帧 target_position 本身就是 planner 写入的战斗 lead 点时才清。
	if combat_target != null and (not is_instance_valid(combat_target) or combat_target.is_destroyed):
		var was_combat_pos: bool = _last_plan != null \
				and _last_plan.pursuit_pos != Vector2.INF \
				and target_position == _last_plan.pursuit_pos
		clear_combat_target()
		if was_combat_pos:
			target_position = Vector2.INF
	var waypoint: Vector2 = target_position
	var s: Situation = Situation.from_aircraft(self)
	var plan: TacticalPlan = TacticalPlanner.plan(s, waypoint)
	# intent 切换时戳时间（用于下一帧的 hysteresis 判定）+ 诊断日志
	if plan.intent != _bfm_prev_intent:
		# 切换瞬间打 PLAN log，便于追溯"飞机为什么这帧选了这个 intent"
		# 玩家 + 玩家方友军（team=0）+ 选中机都记录，敌机仍 silenced 避免刷爆日志
		if (team == 0 or selected) and not is_destroyed:
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

	# 机炮：is_firing 由 plan 决定 + AI burst 节奏 gate（team != 0 才会节流）
	is_firing = _ai_gun_burst_allowed(plan.allow_gun_fire, get_physics_process_delta_time())
	# _gun_lead_heading：朝 pursuit_pos 方向（让 update_gun 朝那里出弹）
	# ⚠ planner 的 pursuit_pos 不一定是真机炮 lead（LEAD_TURN/LAG_PURSUIT 等故意偏到目标侧后方），
	# 用作机炮瞄准会导致子弹方向偏离目标 —— Q1"机炮偏左"诊断字段
	if plan.pursuit_pos != Vector2.INF:
		var to_pos: Vector2 = plan.pursuit_pos - global_position
		_gun_lead_heading = atan2(to_pos.x, -to_pos.y)
	else:
		_gun_lead_heading = heading
	if is_firing and (team == 0 or selected) \
			and combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		var now_s: float = Time.get_ticks_msec() / 1000.0
		if now_s >= _gun_aim_log_until:
			_gun_aim_log_until = now_s + 0.5
			var to_tgt: Vector2 = combat_target.global_position - global_position
			var hdg_to_tgt: float = atan2(to_tgt.x, -to_tgt.y)
			var aim_off_deg: int = int(rad_to_deg(_angle_diff(_gun_lead_heading, hdg_to_tgt)))
			var nose_off_deg: int = int(rad_to_deg(_angle_diff(_gun_lead_heading, heading)))
			EventLogger.log_event("GUN_AIM", _log_name(),
				"intent=%s tgt=%s aim_vs_tgt=%+d° aim_vs_nose=%+d°" % [
					TacticalPlan.intent_name(plan.intent),
					_log_unit_name(combat_target), aim_off_deg, nose_off_deg
				])

	# 高度（plan 没指定就保持现状）
	if plan.target_altitude_m >= 0.0:
		target_altitude = plan.target_altitude_m
	# tier 必须走 set_target_tier() 同步 target_altitude（米数），
	# 直接写字段会让物理插值停在旧高度 → "MID → LOW 永不到达" bug
	if plan.target_altitude_tier >= 0:
		set_target_tier(plan.target_altitude_tier)
	# 交战 intent + flat_altitude → 自动匹配敌机高度档
	# ⚠ 玩家（use_tactical_preference）跳过本节：玩家高度永远走 altitude_preference，
	# 不向敌机靠拢（详见 bfm_intent._apply_target_altitude 注释）。
	if flat_altitude and not use_tactical_preference \
			and combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
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


## 瞬时结构 G 上限（猛拉短暂可达）——HUD G 表分母用它，保证"当前 G ≤ 显示上限"
func _effective_max_g_instant() -> float:
	return AircraftPhysics.effective_max_g_instant(self)

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
	# 互斥：J-Turn 进行中不触发 cobra（两动画叠加视觉混乱）
	var hm := get_herbst()
	if hm != null and hm.is_active:
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

## 危机赫尔贝特技能：每帧检查触发条件，满足则启动 J-Turn
## 与眼镜蛇等价（导弹命中前 / 后方机炮追尾自动触发），互斥已通过 UPGRADES.excludes 在抽卡层禁止同时持有。
## 触发要求（全部满足）：
##   1. 玩家拥有该升级（evasion_herbst_active）
##   2. 战术偏好开 + 规避模式 ON
##   3. 当前没有正在进行的机动（cobra/herbst）
##   4. HerbstManeuver.can_activate（内置 15s 冷却）
##   5. 来袭导弹 ≤ COBRA_MISSILE_TRIGGER_PX OR 后方有敌机追尾开火（复用 cobra 检测）
## activate() 内已置 missile_phase_timer + _lock_immunity_timer，机动期间导弹/机炮免疫。
func _update_evasion_herbst_skill(_delta: float) -> void:
	if not evasion_herbst_active:
		return
	if not use_tactical_preference or not evasion_mode:
		return
	var hm := get_herbst()
	if hm == null:
		return
	if not hm.can_activate:
		return
	# 互斥：眼镜蛇进行中不触发 J-Turn（cobra 优先，更短暂）
	var mf := get_maneuver()
	if mf != null and mf.is_active:
		return
	if not (_cobra_detect_imminent_missile() or _cobra_detect_tail_gun()):
		return
	# 转向方向：朝威胁源（追尾敌机或来袭导弹方向）
	var turn_dir: float = _herbst_pick_turn_direction()
	if hm.activate(turn_dir):
		EventLogger.log_event("HOOK", "evasion_herbst",
			"victim=%s turn_dir=%.0f (auto-trigger)" % [_log_name(), turn_dir])

## 选 J-Turn 转向：优先朝最近来袭导弹的方向反转；没导弹则朝后方追尾敌机方向
## 返回 +1（右转）/ -1（左转）/ 0（随机，由 HerbstManeuver.activate 兜底）
func _herbst_pick_turn_direction() -> float:
	var threat_pos: Vector2 = Vector2.ZERO
	var found := false
	# 优先：最近来袭导弹
	if missile_manager:
		var best_d_sq: float = INF
		for child in missile_manager.get_children():
			if not child is Missile:
				continue
			var m: Missile = child as Missile
			if not m.is_active or m.is_flare_jammed or m.target != self or not m.has_guidance:
				continue
			var d_sq := global_position.distance_squared_to(m.global_position)
			if d_sq < best_d_sq:
				best_d_sq = d_sq
				threat_pos = m.global_position
				found = true
	# 退而求其次：后方追尾敌机
	if not found:
		var my_fwd := Vector2(sin(heading), -cos(heading))
		var best_d_sq: float = INF
		for u in CombatUnit.all_units:
			# all_units 跨帧静态：必须 is_instance_valid 守卫；否则 `is Aircraft` /
			# `.team` 访问 freed 实例会爆 "previously freed instance"
			if not is_instance_valid(u):
				continue
			if u == self or u.team == team or u.is_destroyed or not u is Aircraft:
				continue
			var enemy: Aircraft = u as Aircraft
			if not enemy.is_firing:
				continue
			var to_enemy := (enemy.global_position - global_position).normalized()
			if my_fwd.dot(to_enemy) > -0.3:
				continue
			var d_sq := global_position.distance_squared_to(enemy.global_position)
			if d_sq < best_d_sq:
				best_d_sq = d_sq
				threat_pos = enemy.global_position
				found = true
	if not found:
		return 0.0
	var to_threat: Vector2 = (threat_pos - global_position).normalized()
	var my_right: Vector2 = Vector2(cos(heading), sin(heading))
	return signf(my_right.dot(to_threat))

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
## OVERLOAD 状态会乘进同样的位置：装填/锁定 ×0.4，速度/减速 ×1.6
func _executioner_speed_mult() -> float:
	# 每层 +5% 最大速度，5 层 +25%
	var m := (1.0 + 0.05 * float(executioner_stacks)) if (executioner_active and executioner_stacks > 0) else 1.0
	if status_overload_active:
		m *= StatusEffects.OVERLOAD_ACCEL_MULT
	return m

func _executioner_decel_mult() -> float:
	# 每层 +10% 减速能力，5 层 +50%
	var m := (1.0 + 0.10 * float(executioner_stacks)) if (executioner_active and executioner_stacks > 0) else 1.0
	if status_overload_active:
		m *= StatusEffects.OVERLOAD_ACCEL_MULT
	return m

func _executioner_reload_mult() -> float:
	# 每层 -8% 装填时间（=×0.92），5 层 ×0.659（-34%）
	var m := pow(0.92, executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0
	if status_overload_active:
		m *= StatusEffects.OVERLOAD_RELOAD_MULT
	return m

func _executioner_lock_mult() -> float:
	# 每层 -10% 锁定时间（=×0.90），5 层 ×0.590（-41%）
	var m := pow(0.90, executioner_stacks) if (executioner_active and executioner_stacks > 0) else 1.0
	if status_overload_active:
		m *= StatusEffects.OVERLOAD_LOCK_MULT
	return m

# 状态效果：apply_status / has_status / remove_status / clear_all_statuses 在 CombatUnit


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
	# 舰船 / Mother Goose 挂点代理：log 显示 "船名 [挂点符号]"，避免 @Node2D@454 难追溯
	if unit is MountTarget:
		var mt: MountTarget = unit
		if mt.parent_ship and is_instance_valid(mt.parent_ship):
			# parent_ship 既可能是 NavalUnit（有 full_name），也可能是 Aircraft（用 callsign）
			var ship_label: String = "Ship"
			if mt.parent_ship is NavalUnit and (mt.parent_ship as NavalUnit).full_name != "":
				ship_label = (mt.parent_ship as NavalUnit).full_name
			elif mt.parent_ship.callsign != "":
				ship_label = mt.parent_ship.callsign
			if mt.mount_ref and mt.mount_ref.params:
				return "%s[%s]" % [ship_label, mt.mount_ref.params.display_symbol]
			if mt.weak_point_ref:
				return "%s[WP]" % ship_label
			return ship_label
		return "MountTarget"
	# NavalUnit 本体（船体）：log 显示 full_name 而非 @Node2D@xxx
	if unit is NavalUnit:
		var nv: NavalUnit = unit
		return nv.full_name if nv.full_name != "" else "Ship"
	# GroundUnit：用 params.display_name 兜底
	if unit is GroundUnit and unit.params and "display_name" in unit.params:
		var gn: String = unit.params.display_name
		if gn != "":
			return gn
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
## AI 机炮 burst 节奏：仅对敌方 AI（team != 0）生效；玩家/玩家僚机直接放行 want_fire。
## want_fire = 本帧战术层希望开火与否。返回是否实际允许开火（含 burst/pause 自洽 tick）。
func _ai_gun_burst_allowed(want_fire: bool, delta: float) -> bool:
	if team == 0:
		return want_fire
	if _ai_gun_pause_timer > 0.0:
		_ai_gun_pause_timer -= delta
		if _ai_gun_pause_timer > 0.0:
			return false
		_ai_gun_burst_timer = AI_GUN_BURST_DURATION
	if not want_fire:
		return false
	_ai_gun_burst_timer -= delta
	if _ai_gun_burst_timer <= 0.0:
		_ai_gun_pause_timer = AI_GUN_PAUSE_DURATION
		return false
	return true

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
##
## §1.2 边界差量：进入 / 退出 evasion 时一次性按 evasion_modifiers 倍率
## 缩放 / 还原所有运行时倒计时，避免每帧 `if evasion: cd *= mult` 引起的边界抖动
## （在云边缘 / 模式频繁切换时 cd 反复重置）。
func set_evasion_mode(enabled: bool) -> void:
	var was_enabled := evasion_mode
	if enabled and not was_enabled:
		_apply_evasion_modifiers(true)
	elif not enabled and was_enabled:
		_apply_evasion_modifiers(false)
	evasion_mode = enabled
	# §C 玩家技能"evasion 隐身"：进入不立即激活，由 _update_evasion 累计 2s 后置位
	# 派生标记由 StatusEffects.update OR 进 status_stealth_active
	if evasion_stealth_active:
		if enabled:
			_evasion_stealth_timer = 0.0
			_in_evasion_stealth = false   # 进入瞬间一定不隐身
		else:
			_in_evasion_stealth = false
			_evasion_stealth_timer = 0.0
	# §C 玩家技能"evasion 4s 装填"：进入时重置 timer（避免短停短进取巧累积）
	if enabled and evasion_overstock_interval > 0.0:
		_evasion_overstock_timer = 0.0
	if enabled:
		# 取消当前移动指令和交战目标，专心躲避
		clear_combat_target()
		target_position = Vector2.INF
		_evasion_override = false
	# 关闭时不动作，玩家可手动指定新目标

	# ── 玩家专属：把规避模式同步给僚机（散开自保） ──
	# 规则：仅 use_tactical_preference 飞机（玩家）触发传播；状态变化时才传播，避免递归
	# 僚机 set_evasion_mode 不会再次传播（because they don't have use_tactical_preference）
	if use_tactical_preference and enabled != was_enabled:
		_propagate_evasion_to_squad(enabled)

## 把规避状态广播给本机为长机的所有僚机（仅玩家调用）
## spec wingman-escort-evasion：广播置位的是僚机的 escort_cover_active（护卫姿态），
## 不再直接置 evasion_mode —— 否则 planner 的 evasion_intent 会让待命僚机 max+AB 散开。
## 僚机收到后：自己被真威胁才 enter_evade 逃命；否则回编队待命 + 替长机投护卫 flare。
func _propagate_evasion_to_squad(enabled: bool) -> void:
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not (u is Aircraft) or u == self or u.team != team:
			continue
		var ac: Aircraft = u
		# 跳过忠诚僚机 drone：它有自己的 kamikaze 导弹拦截路径（不靠 EVADE_MISSILE 状态机），
		# 收到 evasion 广播会被 ai_controller.gd:535 的强制 EVADE 守卫卡住，永远不能跟玩家
		# 攻击 combat_target，看起来"无视玩家锁定的敌人"。
		if ac.is_drone:
			continue
		# 通过 AIController 找 squad
		for child in ac.get_children():
			if child is AIController:
				var ai_ctrl: AIController = child
				if ai_ctrl.squad and ai_ctrl.squad.leader == self:
					ac.escort_cover_active = enabled
					if not enabled:
						ac._escort_flare_tried.clear()  # 关 E：清护卫尝试记录
				break

## 进入(true) / 退出(false) evasion 时缩放 cd —— 进入按 mult 缩短，退出反向除回
## 只动倒计时本身，不动 max 装填时间 / 弹药数等"配置"
func _apply_evasion_modifiers(entering: bool) -> void:
	var weapon_m: float = float(evasion_modifiers.get("weapon_cd_mult", 1.0))
	var flare_m: float = float(evasion_modifiers.get("flare_cd_mult", 1.0))
	var reload_m: float = float(evasion_modifiers.get("missile_reload_mult", 1.0))
	if entering:
		_fire_cooldown *= weapon_m
		_missile_cooldown *= weapon_m
		_rocket_burst_cooldown *= weapon_m
		_flare_cooldown *= flare_m
		_missile_reload_timer *= reload_m
	else:
		if weapon_m > 0.0:
			_fire_cooldown /= weapon_m
			_missile_cooldown /= weapon_m
			_rocket_burst_cooldown /= weapon_m
		if flare_m > 0.0:
			_flare_cooldown /= flare_m
		if reload_m > 0.0:
			_missile_reload_timer /= reload_m

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
	# §C 玩家技能"evasion 4s 装填"：仅 evasion ON 时累加 timer，退出 evasion 不进入此分支
	if evasion_mode and evasion_overstock_interval > 0.0 and params and params.missile:
		_evasion_overstock_timer += delta
		if _evasion_overstock_timer >= evasion_overstock_interval:
			_evasion_overstock_timer -= evasion_overstock_interval
			# 突破 max_count 上限到 max_count×2；超出不再装
			var hard_cap: int = params.missile.max_count * 2
			if missiles_remaining < hard_cap:
				missiles_remaining += 1
				EventLogger.log_event("EVASION_OVERSTOCK", _log_name(),
					"+1 missile (now %d / cap %d)" % [missiles_remaining, hard_cap])

	# §C 玩家技能"evasion 隐身"：进入 evasion 后持续 2s 才激活
	if evasion_mode and evasion_stealth_active and not _in_evasion_stealth:
		_evasion_stealth_timer += delta
		if _evasion_stealth_timer >= EVASION_STEALTH_DELAY:
			_in_evasion_stealth = true
			EventLogger.log_event("EVASION_STEALTH_ON", _log_name(), "")

	# §C 玩家技能"弹后潜匿"：弹药全部打空时触发 5 秒一次性隐身
	if missile_cd_stealth_active:
		var cur_missiles: int = missiles_remaining
		# 边沿检测：>0 → 0 时启动定时器（_prev=-1 的首帧不触发，避免开局空载误触发）
		if _prev_missiles_remaining > 0 and cur_missiles == 0:
			_missile_cd_stealth_timer = MISSILE_DEPLETED_STEALTH_DURATION
			EventLogger.log_event("MISSILE_CD_STEALTH_ON", _log_name(),
				"depleted → stealth %.1fs" % MISSILE_DEPLETED_STEALTH_DURATION)
		_prev_missiles_remaining = cur_missiles
		if _missile_cd_stealth_timer > 0.0:
			_missile_cd_stealth_timer -= delta
			_in_missile_cd_stealth = _missile_cd_stealth_timer > 0.0
		else:
			_in_missile_cd_stealth = false
	else:
		_in_missile_cd_stealth = false
		_missile_cd_stealth_timer = 0.0
		_prev_missiles_remaining = -1

	# §C 玩家技能"对头干扰"：扫 radar_targets，双向 dot > 0.7 的目标累积秒数 → 阈值施 JAM
	if team == 0 and head_on_jam_threshold > 0.0 and not radar_targets.is_empty():
		var my_fwd_h: Vector2 = Vector2(sin(heading), -cos(heading))
		var to_remove_h: Array = []
		for tgt_key in radar_targets.keys():
			if tgt_key == null or not is_instance_valid(tgt_key):
				continue
			var tgt_ac := tgt_key as Aircraft
			if tgt_ac == null or tgt_ac.is_destroyed:
				continue
			# 已 JAM 中：暂停累积，等状态消退后再开始
			if tgt_ac.status_effects.has(StatusEffects.JAM):
				continue
			var to_target: Vector2 = (tgt_ac.global_position - global_position).normalized()
			var tgt_fwd: Vector2 = Vector2(sin(tgt_ac.heading), -cos(tgt_ac.heading))
			# 双向对头：我机头朝目标 + 目标机头朝我，且距离 ≤ 3km
			if my_fwd_h.dot(to_target) > HEAD_ON_JAM_DOT and tgt_fwd.dot(-to_target) > HEAD_ON_JAM_DOT:
				if global_position.distance_squared_to(tgt_ac.global_position) > SkillHooks.HEAD_ON_RANGE_PX * SkillHooks.HEAD_ON_RANGE_PX:
					continue
				var tid: int = tgt_ac.get_instance_id()
				var sec: float = float(_head_on_jam_seconds.get(tid, 0.0)) + delta
				_head_on_jam_seconds[tid] = sec
				if sec >= head_on_jam_threshold:
					tgt_ac.apply_status(StatusEffects.JAM, HEAD_ON_JAM_DURATION)
					_head_on_jam_seconds[tid] = 0.0
					EventLogger.log_event("SKILL_HOOK", _log_name(),
						"head_on_jam → %s JAM %.1fs" % [tgt_ac._log_name(), HEAD_ON_JAM_DURATION])
					SkillHooks.on_player_jam_landed(self, 1)
		# 清掉离开雷达锥的累积
		for tid_check in _head_on_jam_seconds.keys():
			var still_in: bool = false
			for tk in radar_targets.keys():
				if is_instance_valid(tk) and tk.get_instance_id() == tid_check:
					still_in = true
					break
			if not still_in:
				to_remove_h.append(tid_check)
		for k in to_remove_h:
			_head_on_jam_seconds.erase(k)

	# §C 玩家技能"后半球减速光环"：累积模式 + 内置 CD
	# - 累积期不生效，每个目标在我后半球 + 距离内累加 → 满 8s 时施 SLOW 4s
	# - SLOW 期间不再累积；状态消退后从 0 重新累积
	# - 触发 debuff 后整段锁 AURA_INTERNAL_CD 秒，避免短时间内多次 VFX 脉冲叠加（性能）
	if team == 0 and rear_aura_slow_radius_px > 0.0:
		if _rear_aura_cd_remaining > 0.0:
			_rear_aura_cd_remaining -= delta
		else:
			var fired_rear: Array = [false]
			_tick_aura_accumulator(_rear_aura_accum_seconds,
				rear_aura_slow_radius_px, StatusEffects.SLOW, true, delta, fired_rear)
			if fired_rear[0]:
				_rear_aura_cd_remaining = AURA_INTERNAL_CD

	# §C 玩家技能"全向 JAM 光环"：累积模式 + 内置 CD
	if team == 0 and jam_aura_radius_px > 0.0:
		if _jam_aura_cd_remaining > 0.0:
			_jam_aura_cd_remaining -= delta
		else:
			var fired_jam: Array = [false]
			_tick_aura_accumulator(_jam_aura_accum_seconds,
				jam_aura_radius_px, StatusEffects.JAM, false, delta, fired_jam)
			if fired_jam[0]:
				_jam_aura_cd_remaining = AURA_INTERNAL_CD


## 累积式光环通用 tick：统一处理 rear_slow / jam_aura（未来加新光环可复用）
##   accum_dict: { instance_id → 累积秒数 }（每光环各自一个）
##   radius_px: 生效半径
##   status_id: 累积满后施加的状态 id
##   require_rear: true=需要在我后半球（dot(my_back, to_enemy) > 0.3）
##   delta: 帧时长
## out_fired: 1 元素数组（[bool]），由调用方提供；本帧触发了 debuff 时置 true
## 用 out 参数而非 return，因为函数体内（历史遗留）混入了 _update_evasion 的 evade-roll 逻辑，不能 early-return
func _tick_aura_accumulator(accum_dict: Dictionary,
		radius_px: float, status_id: String,
		require_rear: bool, delta: float, out_fired: Array = []) -> void:
	var r_sq: float = radius_px * radius_px
	var my_back: Vector2 = Vector2.ZERO
	if require_rear:
		my_back = -Vector2(sin(heading), -cos(heading))
	# 收集本帧需要"达阈值施加 Debuff"的目标位置（用于 VFX 一次性脉冲）
	var debuff_hits: Array[Vector2] = []
	# 收集失效条目（destroyed / 离开半径），统一删除避免遍历时改 dict
	var to_remove: Array = []
	# 第一遍：扫描半径内的敌方飞机，更新累积
	# 用 set 跟踪本帧"在半径内"的 id，方便第二遍清理离开的
	var in_radius_ids: Dictionary = {}
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not (u is Aircraft):
			continue
		if u.team == team:
			continue
		var d_sq: float = u.global_position.distance_squared_to(global_position)
		if d_sq > r_sq:
			continue
		if require_rear:
			var to_e: Vector2 = (u.global_position - global_position).normalized()
			if my_back.dot(to_e) <= 0.3:
				continue
		var oid: int = u.get_instance_id()
		in_radius_ids[oid] = true
		# 状态期间不累积
		if u.status_effects.has(status_id):
			continue
		var sec: float = float(accum_dict.get(oid, 0.0)) + delta
		if sec >= AURA_ACCUMULATE_SECONDS:
			u.apply_status(status_id, AURA_DEBUFF_DURATION)
			accum_dict[oid] = 0.0
			debuff_hits.append(u.global_position)
			if status_id == StatusEffects.JAM:
				SkillHooks.on_player_jam_landed(self, 1)
		else:
			accum_dict[oid] = sec
	# 第二遍：离开半径的目标累积**保留**（不归零，让玩家短暂脱离不丢累积）
	# 但已经死的 / freed 的清理掉避免泄漏
	for k in accum_dict.keys():
		# 通过 instance_from_id 查找；不在 in_radius 里且对象已 free → 清掉
		if not in_radius_ids.has(k):
			var inst = instance_from_id(k)
			if inst == null or not is_instance_valid(inst) or (inst as Aircraft).is_destroyed:
				to_remove.append(k)
	for k in to_remove:
		accum_dict.erase(k)
	# 累积式光环是逐目标异步达阈值（不是瞬时 AOE），不放范围脉冲 VFX；
	# 敌方头上的 status 图标 / 百分比已足够提示。范围脉冲只用于"瞬间全部生效"的真 AOE。
	if debuff_hits.size() > 0:
		if out_fired.size() > 0:
			out_fired[0] = true

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

## 节流记录导弹发射被阻塞的原因（每 MSL_BLOCK_LOG_INTERVAL 最多一次）
## 同一 reason 连续触发时不重复记录，直到 reason 改变或间隔到期
## 范围：玩家 + 玩家方友军（team=0），以便排查"僚机决定 combat_target 却不开火"类问题
func _log_msl_block(reason: String, detail: String) -> void:
	if team != 0:
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

## 重写 apply_status：对无驾驶员的飞机过滤心理类状态
## - FEAR 不该对 UAV 生效（无人机不会"恐惧"）
## 其它状态（INVINCIBLE / STEALTH / JAM / SLOW 等）正常生效，因为它们都是物理/电子层面的
func apply_status(id: String, duration: float, mode: String = "max") -> void:
	if no_pilot and id == StatusEffects.FEAR:
		# 静默丢弃，不计入 status_effects；既不显示状态条，也不触发 AI panic
		return
	# 玩家技能"过载共振"系列：OVERLOAD 时长 / 联动嗜血
	# 仅影响走 apply_status 的 timed 来源；云中常驻 _in_cloud_overload 派生 OR 不经此路径
	var also_bloodlust: bool = false
	if id == StatusEffects.OVERLOAD and team == 0 and has_meta("upgrade_stacks"):
		var stacks: Dictionary = get_meta("upgrade_stacks")
		# 时长 ×4
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_DURATION_4X, 0)) > 0:
			duration *= SkillHooks.OVERLOAD_DURATION_MULT
		# 燃尽自如：再 +4s
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_EXTENDED_AMMO, 0)) > 0:
			duration += SkillHooks.OVERLOAD_DURATION_FLAT_BONUS
		# 噬血共振：进入 OVERLOAD 时同时获得 BLOODLUST 同时长
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_TO_BLOODLUST, 0)) > 0:
			also_bloodlust = true
	super.apply_status(id, duration, mode)
	if also_bloodlust:
		# 用同一 duration（已被乘 4 / +4 处理过）。BLOODLUST 不会被本钩子再次乘上倍率
		super.apply_status(StatusEffects.BLOODLUST, duration, mode)


## 受到伤害（通用：导弹/火箭/爆炸等战斗部伤害）
## 位置感知伤害入口：MountTarget 等子部件命中时调，传入命中世界坐标。
## 默认转发给 take_damage(amount)；如果飞机注册了 damage_router meta（例：Mother Goose
## 通过 MotherGooseController 接管路由），则委托给 router.route_damage(amount, hit_pos)。
func take_damage_at(amount: float, hit_pos: Vector2) -> void:
	if has_meta(&"damage_router"):
		var router: Object = get_meta(&"damage_router")
		if router and is_instance_valid(router) and router.has_method(&"route_damage"):
			router.call(&"route_damage", amount, hit_pos)
			return
	take_damage(amount)

## 战斗部类伤害：受"弹头穿甲"系数影响，只计一半护甲（见 MISSILE_ARMOR_PENETRATION）
## 默认 kind="missile"（旧调用点 take_damage(x) 默认按导弹处理）；显式传 kind 覆盖
func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if is_destroyed:
		return
	if invulnerable:
		return
	# Mother Goose / 类似挂点 BOSS：弱点暴露后玩家直锁主体的伤害也要走 router
	## router.route_damage(amount, hit_pos) —— 这里没有命中坐标，传 boss 中心
	if has_meta(&"damage_router"):
		var router: Object = get_meta(&"damage_router")
		if router and is_instance_valid(router) and router.has_method(&"route_damage"):
			if attacker != null:
				set_meta("_pending_attacker", attacker)
			set_meta("_last_damage_kind", kind if kind != "" else "missile")
			router.call(&"route_damage", amount, global_position)
			return
	if attacker != null:
		set_meta("_pending_attacker", attacker)
	# 默认归类导弹（保持向后兼容，老调用点没显式传 kind 多来自导弹/AOE 路径）
	var dk: String = kind if kind != "" else "missile"
	set_meta("_last_damage_kind", dk)
	# survivor_missile_damage_cap 仅作用于导弹（含 AOE 等爆炸类）；火箭弹是独立武器，
	# 不走导弹数值通道（设计原则：火箭弹 ≠ 导弹）。
	if dk == "missile" and survivor_missile_damage_cap > 0.0:
		amount = minf(amount, survivor_missile_damage_cap)
	amount = _apply_armor(amount, MISSILE_ARMOR_PENETRATION)
	_apply_damage(amount)

## 受到机炮伤害（可被装甲闪避）
## 闪避率累加来源（**线性加和 + 全局 cap MAX_BULLET_DODGE_CAP**）：
##   - 基础 bullet_dodge_chance（PlayableAircraft 0.10-0.20 基础 + hp_up 升级 cap 0.40）
##   - 规避模式额外 +20%（战术面板开启"回避/规避模式"时生效）
##   - HIGH 高度档位额外 +20%（高空机炮更难命中）
##   - §C 玩家技能"对头机炮闪避"：与攻击者夹角对头时 +60%
##
## 全局 cap = 0.85：满 build（hp_up 0.40 + evasion 0.20 + HIGH 0.20 + head-on 0.60 = 1.40）
## 必须夹住，否则机炮永远打不到玩家。85% 留 15% 命中窗口让玩家仍能感到"危险"。
##
## 设计权衡：用 cap 而不是乘法递减（1−Π(1−d_i)），简单可读 + 玩家容易心算"我大概多少闪避"。
const MAX_BULLET_DODGE_CAP: float = 0.85
func take_bullet_damage(amount: float, attacker: Node = null) -> void:
	if is_destroyed:
		return
	if invulnerable:
		return
	# Mother Goose 等挂点 BOSS：机炮也走 router（按 boss 中心传 hit_pos，弱点未暴露则被角度过滤）
	if has_meta(&"damage_router"):
		var router: Object = get_meta(&"damage_router")
		if router and is_instance_valid(router) and router.has_method(&"route_damage"):
			if attacker != null:
				set_meta("_pending_attacker", attacker)
			set_meta("_last_damage_kind", "gun")
			router.call(&"route_damage", amount, global_position)
			return
	# Adds 杂兵（Tu-160/AH-64/CH-47）按设计被击中无任何反应——
	# 不参与闪避也不触发桶滚动画，否则重型轰炸机会像战斗机一样在高空翻滚
	var is_adds: bool = has_meta("category") and get_meta("category") == "adds"
	var effective_dodge: float = bullet_dodge_chance
	if evasion_mode:
		effective_dodge += 0.20  # 规避模式加成（玩家手动开 / 长机传播给僚机 / AI 进入 EVADE 状态）
	if get_altitude_tier() == AltitudeTier.HIGH:
		effective_dodge += 0.20  # HIGH 高度加成
	# §C 玩家技能"低空机炮闪避"：LOW/GROUND 档位时加 bonus
	if team == 0 and low_alt_gun_dodge_bonus > 0.0:
		var t: int = get_altitude_tier()
		if t == AltitudeTier.LOW or t == AltitudeTier.GROUND:
			effective_dodge += low_alt_gun_dodge_bonus
	# 对头机炮闪避（玩家技能）：仅 team==0 + 持有 SKILL_HEAD_ON_GUN_DODGE
	# 几何门槛 head_on_dot > 0.7（双方机头对冲 ≲ 53°）
	if team == 0 and head_on_gun_dodge_bonus > 0.0 and attacker is Aircraft:
		var atk: Aircraft = attacker
		if is_instance_valid(atk):
			var to_atk: Vector2 = (atk.global_position - global_position).normalized()
			var my_fwd: Vector2 = Vector2(sin(heading), -cos(heading))
			var atk_fwd: Vector2 = Vector2(sin(atk.heading), -cos(atk.heading))
			# 对头判定：我的机头朝向攻击者 + 攻击者机头朝向我 + 距离 ≤ 3km
			if my_fwd.dot(to_atk) > 0.7 and atk_fwd.dot(-to_atk) > 0.7 \
					and global_position.distance_squared_to(atk.global_position) <= SkillHooks.HEAD_ON_RANGE_PX * SkillHooks.HEAD_ON_RANGE_PX:
				effective_dodge += head_on_gun_dodge_bonus
	# 全局 cap：避免叠 build 后 100%+ 永闪避
	effective_dodge = clampf(effective_dodge, 0.0, MAX_BULLET_DODGE_CAP)
	if not is_adds and effective_dodge > 0.0 and randf() < effective_dodge:
		_trigger_evasion_roll()  # 闪避滚转动画
		return  # 闪避成功，无视伤害
	if survivor_bullet_damage_cap > 0.0:
		amount = minf(amount, survivor_bullet_damage_cap)
	amount = _apply_armor(amount, 0.0)  # 机炮不穿甲，护甲全额生效
	# 标记致死来源：survivor_spawner._detect_kills 据此触发"机炮击杀恐惧"AOE
	if hp - amount <= 0.0:
		_killed_by_bullet = true
	# damage_kind = gun（供机炮发射减伤 / 机炮闪避 / 机炮击杀钩子消费）
	set_meta("_last_damage_kind", "gun")
	if attacker != null:
		set_meta("_pending_attacker", attacker)
	_apply_damage(amount)

## 护甲减伤（DOTA 式软上限）：dr = armor_eff / (armor_eff + ARMOR_K)
## penetration ∈ [0,1]：穿甲系数，导弹=0.5 抵消一半护甲，机炮=0 受全额护甲
## armor=0 → dr=0，完全兼容现有无护甲飞机
const ARMOR_K: float = 100.0
const MISSILE_ARMOR_PENETRATION: float = 0.5
func _apply_armor(amount: float, penetration: float) -> float:
	# 玩家技能"血怒护甲"：BLOODLUST 期间额外减伤（叠在护甲层之外，独立乘）
	if team == 0 and status_bloodlust_active and has_meta("upgrade_stacks"):
		var bl_stacks: Dictionary = get_meta("upgrade_stacks")
		if int(bl_stacks.get(SkillHooks.SKILL_BLOODLUST_ARMOR_MOBILITY, 0)) > 0:
			amount *= (1.0 - SkillHooks.BLOODLUST_ARMOR_DR)
	if not params or params.armor <= 0.0:
		return amount
	var armor_eff: float = params.armor * (1.0 - clampf(penetration, 0.0, 1.0))
	if armor_eff <= 0.0:
		return amount
	var dr: float = armor_eff / (armor_eff + ARMOR_K)
	return amount * (1.0 - dr)

func _apply_damage(amount: float) -> void:
	# §C 玩家技能"机炮发射时减伤"：在窗口期内乘伤害减免比例
	if team == 0 and gun_fire_dr_amount > 0.0 and _gun_fire_recently_until > EventLogger.get_game_time():
		amount *= maxf(1.0 - gun_fire_dr_amount, 0.0)
	var old_hp := hp
	hp -= amount
	EventLogger.log_event("DAMAGE", _log_name(),
		"took %.0f damage (hp=%.0f→%.0f)" % [amount, old_hp, hp])
	# 受击钩子链（玩家系技能：受伤进嗜血 / 被导弹击中无敌 / 周围 JAM 等）
	# early-return：only Aircraft team==0 + has upgrade_stacks → 不命中开销 ≈ 1 dict.has
	if hp > 0.0 and team == 0:
		var atk: Node = get_meta("_pending_attacker", null)
		var kind: String = String(get_meta("_last_damage_kind", ""))
		SkillHooks.dispatch_on_hit(self, atk, kind, amount)
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
## _last_damage_kind → 中文武器标签（KILL 日志用）
func _kill_weapon_label(kind: String) -> String:
	match kind:
		"gun": return "机炮"
		"missile": return "导弹"
		"rocket": return "火箭弹"
		"aoe": return "爆炸"
		"ground_crash": return "坠地"
		_: return ""

func _record_kill_attribution() -> void:
	if not has_meta("_pending_attacker"):
		return
	var attacker = get_meta("_pending_attacker")
	# ── 击杀归因日志（KILL）：致死瞬间打一行"谁用什么武器击坠了谁"──
	# 低频（每次死亡一次）。attacker 可能是飞机 / 地面 / 舰船；武器种类取自 _last_damage_kind。
	# DESTROY 行只写被击毁者，KILL 行补上凶手 + 武器，省去人工关联 fired→hit。
	if is_instance_valid(attacker):
		var dk: String = String(get_meta("_last_damage_kind", ""))
		var wpn: String = _kill_weapon_label(dk)
		var atk_name: String = attacker._log_name() if attacker.has_method("_log_name") \
				else (attacker.callsign if ("callsign" in attacker and attacker.callsign != "") else String(attacker.name))
		EventLogger.log_event("KILL", atk_name, "%s击坠 %s" % [wpn, _log_name()])
		EventLogger.tally(atk_name, "kills")
		# ── 战况栏（kill feed）信号：呼号 + 武器种类 + 双方阵营，survivor_hud 订阅显示 ──
		var atk_call: String = attacker.callsign if ("callsign" in attacker and attacker.callsign != "") else String(attacker.name)
		var atk_team_i: int = attacker.team if ("team" in attacker) else -1
		EventLogger.kill_recorded.emit(atk_call, callsign, dk, atk_team_i, team)
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
	# 状态系统的击杀钩子（敌我对称：BLOODLUST 等任何 killer-side buff 副作用）
	StatusEffects.on_kill(atk, self)

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
		# damage_kind = ground_crash（与战斗伤害区分，避免触发 on_kill 击杀链等玩家技能）
		set_meta("_last_damage_kind", "ground_crash")
		_start_destroy()

## 坠毁系统委托给 AircraftDestruction（aircraft_destruction.gd）
func _start_destroy() -> void:
	# 清空全局玩家引用，防止 AircraftRenderer 后续帧把 freed 实例赋给类型化变量崩溃
	# （`var pref: Aircraft = player_ref` 在 player_ref 已 free 时抛 "previously freed"）
	if AircraftRenderer.player_ref == self:
		AircraftRenderer.player_ref = null
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
	var base: float = (params.radar_range if params else 300.0) * category_radar_mult
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
	# Perf 包装：把整个飞机绘制成本（含 hover/锁定/HUD/弹道线）汇总到 aircraft_draw 桶
	var _perf_t0: int = Time.get_ticks_usec()
	_draw_impl()
	PerfBuckets.tick("aircraft_draw", Time.get_ticks_usec() - _perf_t0)


func _draw_impl() -> void:
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
		AircraftRenderer.draw_aura_ranges(self)
	# 副导弹槽（仅玩家、装备副弹时画）
	#   - 锁定锥：hover-only（draw_secondary_lock_cone 自身判断 is_hovered）
	#   - 锁定指示括号：长期可见，提示"QMAAM 已就绪可以打"
	if AircraftRenderer.player_ref == self:
		AircraftRenderer.draw_secondary_lock_cone(self)
		AircraftRenderer.draw_secondary_lock_indicators(self)
	# 友方 hover 时显示参考机炮锥；敌方对玩家提交机炮攻击时持续显示锥（条件在 draw_gun_cone 内判）
	AircraftRenderer.draw_gun_cone(self)
	# 守卫：player_ref 在 gameover 时可能持有 freed 引用 → GDScript 严格类型校验在
	# 进入 LockWarning.draw 之前就抛 "previously freed" 类型错误（is_instance_valid 内部
	# 检查反而救不了）。call-site 守卫必不可少。
	if AircraftRenderer.player_ref != null and is_instance_valid(AircraftRenderer.player_ref):
		LockWarning.draw(self, AircraftRenderer.player_ref)
	# drone（忠诚僚机）跳过预测线 / 锁定指示 / 目标括号 / 数据标签 — 纯 2D 极简视觉
	if not is_drone:
		AircraftRenderer.draw_target_line(self)
	AircraftRenderer.draw_cloud_state(self)
	AircraftRenderer.draw_railgun_telegraph(self)
	AircraftRenderer.draw_aircraft_icon(self)
	if not is_drone:
		AircraftRenderer.draw_lock_indicator(self)
		AircraftRenderer.draw_target_bracket(self, is_mission_target)
	if is_firing:
		AircraftRenderer.draw_muzzle_flash(self)
	AircraftRenderer.draw_railgun_beam(self)
	AircraftRenderer.draw_laser_beams(self)
	if is_afterburner:
		AircraftRenderer.draw_afterburner_glow(self)
	AircraftRenderer.draw_flare_particles(self)
	if is_drone:
		# drone 用极简一行标签：DRONE + 速度（无 callsign / altitude / HDG / G）
		AircraftRenderer.draw_data_label_drone(self)
	elif hide_data_label:
		AircraftRenderer.draw_data_label_minimal(self)
	else:
		AircraftRenderer.draw_data_label(self)
	AircraftRenderer.draw_tactic_popup(self)
	# 飞机的 buff/debuff 改由 draw_data_label / draw_data_label_minimal 以文本+百分比形式显示
	# （地面单位 SAM/AAA/ground_unit 仍走 draw_status_icons 的进度条，因其没有数据标签）
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
	# §C 玩家技能：进/出云边界事件（在云中=cloud_state>=1 即视为入云，便于 LOW/MID 也能享受）
	# 仅玩家走这条路径（敌机不需要这些 buff）
	if team == 0:
		var in_cloud: bool = cloud_state >= 1
		if in_cloud != _was_in_cloud_last_frame:
			_on_cloud_boundary(in_cloud)
			_was_in_cloud_last_frame = in_cloud


## §C 云边界事件：进入(true) / 离开(false) 一次性触发，避免每帧重算
func _on_cloud_boundary(entering: bool) -> void:
	# 1) 云中超载：用独立 bool _in_cloud_overload，不进 status_effects
	# 历史 bug：原方案进云时 apply OVERLOAD 9999s + owner flag，若进云前已有
	# evade missile 给的 OVERLOAD 6s，flag 仍被无条件置 true → 出云时
	# remove_status 会把 evade 的 6s 一起清掉。
	# 现在 status_overload_active 派生标记由 StatusEffects.update OR _in_cloud_overload，
	# 两源独立，互不干扰。
	if cloud_overload_active:
		_in_cloud_overload = entering

	# 2) 云中武器 cd：进入按倍率 scale 当前 cd（同 §1.2 evasion 边界差量模式）
	if cloud_weapon_cd_mult != 1.0:
		var mult: float = cloud_weapon_cd_mult
		if entering:
			_fire_cooldown *= mult
			_missile_cooldown *= mult
			_rocket_burst_cooldown *= mult
		else:
			if mult > 0.0:
				_fire_cooldown /= mult
				_missile_cooldown /= mult
				_rocket_burst_cooldown /= mult


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
	# Mother Goose 等接管挂点系统的 BOSS：玩家锁定走 MountTarget 子代理，
	# 主体本身在挂点全死 + 弱点未暴露阶段维持免锁
	if has_meta(&"lock_immune_override"):
		if bool(get_meta(&"lock_immune_override")):
			return true
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
