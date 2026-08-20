class_name Aircraft
extends CombatUnit

const META_PRESENTATION_FORCE_HIDDEN_VISUAL: StringName = &"presentation_force_hidden_visual"

@export var params: AircraftParams
@export var initial_heading_deg: float = 0.0  ## 度 初始航向（0=北, 90=东, 180=南）

# --- 状态 ---
enum AltitudeAction { NONE, CLIMB, DIVE }
const ALTITUDE_ACTION_THRESHOLD_MPS: float = 30.0
const CLIMB_COUNTER_WINDOW_S: float = 4.0
const GUN_TAILED_CACHE_MS: int = 250
var vertical_speed: float = 0.0     ## m/s
var altitude_action: int = AltitudeAction.NONE ## 统一高度动作真源；不等同于高度档位
var altitude_action_command: int = AltitudeAction.NONE ## 玩家 LOW/HIGH 命令的一次性动作闸门
var altitude_action_enter_serial: int = 0      ## 每次动作切换递增，供进入沿技能消费
var altitude_action_start_tier: int = AltitudeTier.MID ## 当前动作进入沿的高度档
var _climb_counter_remaining_s: float = 0.0
var _gun_tailed_until_ms: int = -1              ## 低频汇总缓存；正式判定仍在 AircraftWeapons
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
## 本局击坠数（ACE 继任依据，spec ace-system §3：王牌阵亡由击坠最高者继任）。
## 在 _record_kill_attribution 里给击杀者 +1；不落盘（session-only）。
var kill_tally: int = 0
## 注：_formation_blend / _formation_jitter_phase 单边住在 AIController（_ai_ref._formation_blend 等）。
## 旧 API 把这两个字段在 Aircraft 上镜像了一份导致每帧手动同步，2026-05-04 重构删除。
## 子模块 AircraftFormation 通过 ac._ai_ref 直接读 AI 端的值，单一权威源。
var _ai_ref: AIController = null             ## 由 AIController._ready 回写；编队/规避代码读 blend/jitter
var _cobra_maneuver_ref: CobraManeuver = null
var _herbst_maneuver_ref: HerbstManeuver = null
var _maneuver_cache_child_count: int = -1
var target_altitude: float = 5000.0
var target_speed_kmh: float = 900.0  ## km/h, 玩家/AI设定
var target_altitude_tier: int = AltitudeTier.MID   ## 目标高度档位（flat_altitude时使用）
## 旋翼机平面速度与机头解耦：速度可切向平移，机头可持续指向地面目标。
var rotorcraft_velocity: Vector2 = Vector2.ZERO    ## m/s，世界坐标方向
var rotorcraft_aim_position: Vector2 = Vector2.INF ## INF=机头跟随速度方向

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
## 攻击姿态（spec command-wheel §2.9）：随 commanded_target 走的铁律附加字段，
## 值域与 Situation.POSTURE_* 一致（0=AUTO 武器推导 / 1=STANDOFF 保持距离 / 2=ASSAULT 突击）。
## 轮盘广播时随命令写入；命令清除/新命令时归 AUTO（SquadCommandController / _enforce_commanded_target 维护）
var attack_posture: int = 0
## FOCUS 包围进入方位（spec command-wheel §3.6）：轮盘集火广播时分配的绝对进入方位（弧度，
## 相邻队友 ≥45°），INF=未分配；生命周期与 attack_posture 相同（随 commanded_target 清理）
var surround_bearing_rad: float = INF
## 紧急集合/撤离途中全力加速（command-wheel §2.7/§2.7.1）：SquadCommandController 设/清
## （集合=到达解除 / 撤离=出圈解除 / 任何新命令解除）；速度经 AircraftPhysics
## effective_max/cruise_speed_kmh 注入 ×COMMAND_SPRINT_MULT（机动性 buff 规范 accessor 通道）
var command_sprint: bool = false
var evac_shift_active: bool = false      ## 720 批"阵地转移"：撤离冲刺加成 + 受伤减半（apply_upgrade 置位）
var guard_zone_buff_active: bool = false ## 720 批"保卫阵地"：防守圈内 buff（SquadCommandController 维护）
var berserk_virus_active: bool = false   ## 狂化病毒：全队持有，只有非亲控直属僚机动态生效
var missile_second_stage_active: bool = false ## 720 批"二段推进"：本机发射的导弹续推+转弯渐强
var missile_chain_active: bool = false ## 战区次世代“连锁弹头”：导弹命中后沿原航向继续飞行
var gun_bullet_penetration_active: bool = false ## X-44 专属：普通机炮/炮舱弹逐目标穿透
## 720 批"胆大妄为"：全队禁普通自动 flare；受控机按 R，AI 僚机威胁自动（flare+滚转+i-frame）
var manual_dodge_active: bool = false
var _manual_dodge_cd: float = 0.0
const MANUAL_DODGE_CD: float = 2.0
const MANUAL_DODGE_IFRAME: float = 0.25
## 五选一 R 主动机动中的两项位移技能；当前操控机按 R，AI 接管机按威胁自动释放。
var displacement_roll_active: bool = false
var vertical_break_active: bool = false
enum ActiveSpecialManeuver { NONE, DISPLACEMENT_ROLL, VERTICAL_BREAK }
const DISPLACEMENT_ROLL_DURATION: float = 1.15
const DISPLACEMENT_ROLL_DISTANCE_PX: float = 350.0
const DISPLACEMENT_ROLL_HEADING_PEAK: float = deg_to_rad(78.0)
const DISPLACEMENT_ROLL_COOLDOWN: float = 15.0
const DISPLACEMENT_ROLL_MISSILE_TRIGGER_PX: float = 900.0 * PIXELS_PER_METER
const VERTICAL_BREAK_DURATION: float = 1.30
const VERTICAL_BREAK_DISTANCE_M: float = 900.0
const VERTICAL_BREAK_MIN_DISTANCE_M: float = 600.0
const VERTICAL_BREAK_MIN_ALTITUDE_M: float = 200.0
const VERTICAL_BREAK_PITCH_MIN_SCALE: float = 0.40
const VERTICAL_BREAK_COOLDOWN: float = 18.0
const VERTICAL_BREAK_MISSILE_TRIGGER_PX: float = 1100.0 * PIXELS_PER_METER
const ACTIVE_SPECIAL_AUTO_INTERVAL: float = 0.10
const ACTIVE_SPECIAL_BOUNDARY_MARGIN_PX: float = 24.0
var _active_special: int = ActiveSpecialManeuver.NONE
var _active_special_elapsed: float = 0.0
var _active_special_prev_ease: float = 0.0
var _active_special_side: float = 1.0
var _active_special_lateral_axis: Vector2 = Vector2.RIGHT
var _active_special_start_altitude: float = 0.0
var _active_special_end_altitude: float = 0.0
var _active_special_start_speed: float = 0.0
var _active_special_last_target_altitude: float = 0.0
var _active_special_queued_altitude: float = INF
var _active_special_heading_offset: float = 0.0
var _active_special_roll_visual: float = 0.0
var _active_special_pitch_visual: float = 0.0 ## 0=水平投影，1=垂直越过中点最大俯仰
var _active_special_auto_timer: float = 0.0
var _active_special_local_cooldown_s: float = 0.0
## TIGHT 齐射窗口开火权（spec formation-discipline §3.1）：窗口期 SquadCommandController
## 临时授予编队僚机 combat_target；置位时 SquadCoordination 的"编队防御性清目标"跳过本机
## ——僚机在编队槽位里开火、不脱队。窗口关闭即回收（禁补射由构造保证）
var volley_fire_active: bool = false
var is_firing: bool = false
var ammo: int = 500
# 自动扫描机炮目标的节流计时器：60Hz 扫描无意义，且每次扫描都是 O(N) 遍历全场单位
var _auto_gun_scan_timer: float = 0.0
var _fire_cooldown: float = 0.0
var _gun_burst_rounds_left: int = 0  ## 当前梭剩余弹数（>0 = 梭承诺中，打完才停；见 specs/weapons/gun-burst-fire.md）
var _auto_gun_target_id: int = 0  ## 3Hz 自动扫描本轮候选；只存实例 ID，避免跨帧攥住已释放节点
var _gun_burst_target_id: int = 0  ## 当前已承诺梭的目标；整梭逐 tick 重算提前点，禁止被 planner 回正
var _gun_lead_heading: float = 0.0  ## 前置射击方向（由 _update_combat 计算）
var _gun_climb_frozen_target_id: int = 0 ## 爬升反制：当前梭冻结旧解的目标实例 ID
var _gun_climb_frozen_heading: float = 0.0 ## 爬升反制：冻结的世界射向
# ── 武器竞选滞回状态（spec weapon-employment-doctrine §2.2；planner 经 Situation 读、
#    _apply_tactical_plan 回写；1.5s 滞回在 WeaponSelector.select 内判定）──
var _primary_weapon_kind: String = ""      ## 当前竞选胜者（""=无战斗/全失格）
var _primary_weapon_hold_s: float = 999.0  ## 胜者已保持秒数（初值大 → 首次竞选立即生效）
var _plan_bank_limit_rad: float = -1.0     ## plan 级坡度上限（LINE_UP 充能平台=30°；-1=无限制）
## 敌方飞机机炮安全门：每次火控机会只准启动一梭，梭结束/硬中止后强制停火。
## 统一执行在 AircraftWeapons.update_gun；仅 HOSTILE 生效，PLAYER / ALLY 不受限。
const AI_GUN_PAUSE_DURATION: float = 3.0
var _ai_gun_pause_timer: float = 0.0  ## 敌机当前强制停火剩余秒数（梭内不递减）
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
## 齐射路径空手诊断节流（见 _log_salvo_skip）
const SALVO_SKIP_LOG_INTERVAL: float = 2.0
var _salvo_skip_log_timer: float = 0.0

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
var _gun_burst_log_until: float = 0.0  # 节流 [GUN_BURST] 诊断：0.5s 一次（梭起始快照，见 aircraft_weapons）

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
## ON（默认）：齐射路径按有效锁数自动挑选锁定目标开火
## OFF：只对玩家手动指定的 combat_target 发射，但锁定成功仍自动开火
##      —— 节流由 `_missile_cooldown` + `count_active_missiles_at <= 1` 承担，
##      不需要"一次点击一发"守卫（2026-04-24 (3)，详见 player-ai-log.md）
var missile_auto_fire: bool = true
## 特殊敌机的导弹由低频队级控制器接管；通用武器循环仍负责冷却/装填，但不自行选目标开火。
var external_missile_control: bool = false

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

## 护卫本机的战斗机（Adds 逃离编队专用）。本机挨打 → 护卫立刻扑向攻击者。
## 敌方护卫此前对"被护送对象被打"完全无反应：护卫学说（Squad.escort_doctrine_enabled）
## 只对玩家队开，try_defend_protectee 也是玩家专属，adds 类还被 ROE 察觉体系整体排除。
## 这条数组是敌方护卫唯一的反应通道，由 spawner 在组队时双向登记。
var escort_guards: Array[Aircraft] = []

# --- 地面机炮火力警觉（spec aa-fire-awareness）---
## 被地面/舰船机炮弹幕命中时刷新（闪避成功也算——弹幕已跨过机体 = 身处火力网）。
## 消费方：bfm_intent 对面 pass 强转 EGRESS + AB 加速脱离；AircraftFormation 编队 AB 冲刺
const AA_FIRE_REACT_S: float = 2.5   ## 警觉窗口时长（秒），每次中弹刷新
var aa_fire_timer: float = 0.0
var aa_fire_source_pos: Vector2 = Vector2.INF

## 装备运行时状态（commit 8/13 起）：每件 EquipmentParams 子类用 equipment_kind 作 key
## 写入 / 读出自己的状态字典。避免 Aircraft 字段污染。
## 例：RailgunEquipment 用 "railgun" key，存 charge_progress / beam_fade / cooldown 等。
var equipment_state: Dictionary = {}

# --- 雷达 ---

# --- 热诱弹 ---
var flares_remaining: int = 0
var _flare_cooldown: float = 0.0
var _flare_particles: Array[Dictionary] = []  ## { pos: Vector2, vel: Vector2, life: float, bright: bool }
var _flare_spawn_queue: Array[Dictionary] = []  ## 待释放粒子波 { delay, heading, pos, count }
var flare_visual_burst_emitted: int = 0  ## 本次 10 枚视觉投放已实际生成数；玩家仪表逐星同步
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
## ── 720 批 T4 按轴计数缩放（同由 recompute_category_bonuses 写；零技能=默认值零变化）──
var veteran_hp_bonus_applied: float = 0.0 ## 历战者：已应用的 HP 加成（差量幂等；换型重放序言清零）
var speed_by_knight_mult: float = 1.0     ## 全速推进：顶速倍率（aircraft_physics.effective_max_speed_kmh 消费）
var ew_expert_radar_bonus_px: float = 0.0 ## 电子战专家：雷达距离加成（王牌；get_radar_range 消费）
var weapon_master_cd_mult: float = 1.0    ## 武器大师：全武器 CD 倍率（王牌；各 CD 赋值点消费）

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

## 是否配有无线电（spec radio-chatter §2.8 等级门）。
## survivor_spawner 按 ChatterLines.VOICED_ENEMY_TYPES 在创建时设置；
## 玩家 / 僚机 / ALLY 默认 true。与 no_pilot 是【与】关系，见 can_speak_on_radio。
var has_radio_voice: bool = true

## 能否在无线电里说话。硬规则：无人机永远不能 —— 没有飞行员就没有人声，
## 这条不可被 has_radio_voice 覆盖（漏设 has_radio_voice 的无人机也不会开口）。
func can_speak_on_radio() -> bool:
	return has_radio_voice and not no_pilot

## ── 便利贴技能字段（C 阶段批量实装）──
## 各字段由 SurvivorPlayer.apply_upgrade 写入；消费点在对应模块 early-check
var lock_panic_g_mult: float = 1.0          ## 被锁时 effective_max_g 倍率（physics）
var low_hp_flare_reload_mult: float = 1.0   ## hp < 50% 时 flare reload 倍率（flares）
var high_alt_lock_speed_bonus: float = 0.0  ## HIGH 档锁定速率 bonus（main 雷达循环）
var close_range_lock_max_mult: float = 1.0  ## 近距捕获：贴身锁定速率倍率上限（survivor 雷达循环）
var ab_gun_regen_per_sec: float = 0.0       ## AB 时机炮子弹 regen/s（weapons.update_gun）
var altitude_cycle_gun_regen_per_sec: float = 0.0 ## 高度能量循环：DIVE 机炮 regen/s
var altitude_cycle_gun_overstock_mult: float = 1.0 ## 高度能量循环：DIVE 超储上限倍率
var altitude_cycle_ab_regen_per_sec: float = 0.0 ## 高度能量循环：CLIMB 共享加力 regen/s
var alt_change_stealth_factor: float = 0.0  ## 高度变化时锁定衰减系数（main 雷达循环）
var head_on_gun_dodge_bonus: float = 0.0    ## 对头时机炮闪避加成（take_bullet_damage 加查）
var low_alt_gun_dodge_bonus: float = 0.0    ## 低空时机炮闪避加成（take_bullet_damage 在 LOW/GROUND 档位加）
var gun_fire_dr_window: float = 0.0         ## 机炮发射后 N 秒内受到伤害减免（_apply_damage 查）
var gun_fire_dr_amount: float = 0.0         ## 该时间窗内伤害减免比例（0.5 = -50%）
var gunship_mode_active: bool = false       ## 全向自动机炮模式（360°，渲染显示完整射程圈）
var hunter_unlocked: bool = false           ## 猎手：突击命令期间启用动态 buff
var hunter_assault_active: bool = false     ## 猎手运行时标记；命令目标结束即清
var ground_damage_taken_mult: float = 1.0   ## 座舱护甲：地面火力（SAM/AA/CIWS）伤害倍率（_apply_damage 按来源过滤）
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
const AURA_DEBUFF_DURATION: float = 4.0       ## 后半球 SLOW 持续秒数
const JAM_AURA_DURATION: float = 5.0          ## 全向干扰场 JAM 持续秒数
const AURA_INTERNAL_CD: float = 4.0           ## 触发 debuff 后整个光环锁 4s（= debuff 时长，期间不再扫描 / 施加新 debuff）
var _rear_aura_cd_remaining: float = 0.0
var _jam_aura_cd_remaining: float = 0.0

## F-14 专属：全僚机锁定同一敌机时给该敌机施加 SLOW（survivor_mode 雷达循环维护）
var f14_squad_lock_slow_active: bool = false

## 指挥光环运行时注入字段（spec modifier-pipeline）。临时 buff 禁止写 params；
## 物理与 AI 统一经 AircraftPhysics 的 base_*/effective_* accessor 汇入。
var aura_max_g_add: float = 0.0
var aura_g_structural_add: float = 0.0
var aura_roll_rate_mult: float = 1.0
var aura_speed_mult: float = 1.0
var aura_accel_mult: float = 1.0
var aura_stall_mult: float = 1.0
var aura_buff_owner: Node = null

## 云中技能（玩家专用；cloud_state 每 0.2s 采样）
##   cloud_overload_active: 云中刷新短时 OVERLOAD，所有联动统一走 apply_status
##   cloud_weapon_cd_mult:  云中并入 cd_rate("weapon")，不改写运行中倒计时
var cloud_overload_active: bool = false      ## 技能解锁标记：玩家是否选了"云中超载"
var cloud_weapon_cd_mult: float = 1.0        ## 技能：在云中武器 cd 倍率（< 1.0 = 更快）

## 进入 evasion 模式时启用 STEALTH（独立 bool + 派生 OR，避免与其它 STEALTH 来源冲突）
var evasion_stealth_active: bool = false     ## 解锁标记：玩家是否选了"evasion 隐身"
var _in_evasion_stealth: bool = false         ## 运行时：当前是否处于 evasion 模式且解锁
const EVASION_STEALTH_DELAY: float = 2.0      ## 进入 evasion 后多少秒激活隐身
var _evasion_stealth_timer: float = 0.0       ## evasion 进入后累计（仅当 evasion_stealth_active 时累加）

## 弹药打空后获得 5 秒 STEALTH（玩家技能 missile_cd_stealth）
## 与 evasion_stealth 同模式：解锁标记 + 运行时派生标记，status_effects.gd 里 OR 进派生
const MISSILE_DEPLETED_STEALTH_DURATION: float = 4.0   ## 720 批：5→4s
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
## J-Turn（HerbstManeuver）：当前操控机按 R；AI 僚机受威胁时自动反击。
var evasion_herbst_active: bool = false       ## 解锁标记：玩家小队是否获得 J-Turn

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
# （xp_multiplier 已迁 SurvivorPlayer.xp_multiplier——队级单实例，切控不丢；720 T2）
# ── 722 批：机体签名技能字段（spec aircraft-signature-skills；apply_upgrade 置位）──
## 高频判定（每帧 physics/锁定循环/伤害管线）走字段；低频事件型走 meta upgrade_stacks。
## 全部通用 scope（无 ace strip 需求）；进化原地换 params 不销毁实例 → 字段天然继承。
var sig_status_immune: bool = false        ## 鹰狮 E·电战预算：免疫 JAM/SLOW/FEAR
var sig_lock_retention_sec: float = 0.0    ## 维京·唯一的锁定：出锥后锁定保持秒数（0=禁用）
var _sig_lock_grace: Dictionary = {}       ## 唯一的锁定：{ 目标 instance_id → 剩余 grace 秒 }
var sig_f15_active: bool = false           ## 无败之鹰：满血时机炮伤害/锁定 ×1.2
const SIG_F15_HP_RATIO: float = 1.0
const SIG_F15_BONUS_MULT: float = 1.20
var sig_f15c_active: bool = false          ## 制空清扫：锥内每多 1 敌锁定 +8%（cap +40%）
var sig_f15e_active: bool = false          ## 对地特化：对地/舰锁定 ×1.5、伤害 ×1.3
var sig_a6e_active: bool = false           ## 盲飞入侵：低空时敌方锁我 ×0.6
var sig_mig41_active: bool = false         ## 近太空冲刺：高空敌锁 ×0.6 + 俯冲触发超载
var sig_tornado_active: bool = false       ## 地形跟随：低空 +8% 速度（充能走队级账本）
var sig_typhoon_active: bool = false       ## 超巡爬升：高度机动强化 + 变高中机炮闪避
var sig_su34_active: bool = false          ## 鸭嘴兽厨房：加力窗口 +2 HP/s
var sig_mig31_active: bool = false         ## 超速截击：加力窗口自动发射导弹
# （高速炮艇 sig_x44 直改 params.gun.fire_cone_half_angle=90°——扫描/物理门/渲染/AI 全消费点自动生效）
var sig_viffing_active: bool = false       ## 鹞·VIFFing：低速 4s 无敌触发器
var _sig_viffing_cd: float = 0.0           ## VIFFing 内置 CD（20s）计时
var _sig_a10_cheat_cd: float = 0.0         ## 钛浴缸：致死拦截 CD（60s）计时
var _sig_faxx_cd: float = 0.0              ## 穿透打击：机炮击杀隐身 CD（20s）计时
var _sig_a12_revive_used: bool = false     ## 不被期待的计划：每局一次复活已用标记
var _sig_mig41_dash_cd: float = 0.0        ## 近太空冲刺：触发 CD（30s）计时
var _sig_mig41_dive_timer: float = 0.0     ## 近太空冲刺：俯冲加速 buff 残余秒数
var _sig_mig41_seen_action_serial: int = 0 ## 近太空冲刺：已消费的高度动作进入沿
var _sig_mig31_fire_timer: float = 0.0     ## 超速截击：加力窗口内自动发射节拍
var sig_j36_assault_active: bool = false   ## 三发推力：突击 buff 运行时标记（accessor 消费）
var _sig_j36_cd: float = 0.0               ## 三发推力：重触发 CD（15s）计时
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
const COBRA_SKILL_COOLDOWN: float = 25.0    ## 手动/AI 自动触发共用冷却
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
var _ciws_fire_log_until: float = 0.0    ## 玩家方 CIWS_FIRE 诊断节流（区分普通机炮与反导弹道）
var survivor_missile_damage_cap: float = 0.0  ## 生存模式：导弹伤害上限（0=不限制）
var survivor_bullet_damage_cap: float = 0.0   ## 生存模式：机炮伤害上限（0=不限制）
var hide_data_label: bool = false    ## 隐藏飞机旁的数据标签（HUD 替代显示）
var _compact_data_label_active: bool = false  ## 远景战略标签迟滞状态（AircraftRenderer 维护）
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
## 锥的可见度系数 0~1（乘到 alpha 上）。锥是"开火前的预告"，曳光弹一出来它就是纯干扰，
## 所以开火期间淡出、停火（梭射间隙）再慢慢淡回来。威胁条件整体中断时复位为 1。
var _gun_threat_fade: float = 1.0
const GUN_THREAT_FADE_OUT_TIME: float = 0.35
const GUN_THREAT_FADE_IN_TIME: float = 1.5

# 锁定红线状态已搬到 CombatUnit 基类（飞机/SAM/海军共用）
# Aircraft 仅覆写 _lock_line_can_engage_player 与触发 fire 通知


# --- 战术偏好（生存模式玩家手动控制）---
enum WeaponPreference { PREFER_MISSILE, PREFER_GUN }
enum AltitudePreference { PREFER_CLIMB, PREFER_LOW }

var use_tactical_preference: bool = false       ## 启用战术偏好系统（仅玩家飞机）
## 启用机炮瞄准误差（梭级随机偏置 + 机动惩罚，见 AircraftWeapons）。
##
## ⚠ 这条**曾经**被 use_tactical_preference 兼任 —— 而后者是个"玩家有战术偏好面板"的
##   操控模式标志，与"这个飞行员的枪法有多准"毫无关系。兼任的后果：全部 AI 敌机
##   （含 BOSS）永远打一个完美居中的散布锥，零瞄准误差。
##   2026-07-22 按 spec bosses/wraith-squadron §2.4 拆成独立开关
var gun_aim_error_enabled: bool = false
## 减速迟滞状态（王牌中队执行失误，见 EngagementSpeedGovernor.apply_with_lag）。
## latched = 本次进入治理区是否已掷过骰；timer > 0 = 正在迟滞（不压速，会冲过头）
var _ace_decel_lag_latched: bool = false
var _ace_decel_lag_timer: float = 0.0
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
## 对面攻击 pass 相位（spec surface-attack-pass；TacticalPlan.SurfacePhase 0=SETUP/1=RUN/2=EGRESS）
## Situation 读入 → ground_strafe 决策 → _apply_tactical_plan 回写（与 _bfm_prev_intent 同款）
var _strafe_pass_phase: int = 0
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
## 每梭起始抽一次 lead 偏移，整梭共用（梭射节奏见 specs/weapons/gun-burst-fire.md）
var _gun_aim_offset_rad: float = 0.0
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

## ── 加力窗口（spec afterburner-mode）──
## 玩家小队充能资源激活的 6s 强 buff 窗口标志（生存层 AfterburnerCharge 写入全队快照；
## 沙盒/敌机/友军番队恒 false）。与 evasion_mode 解耦：窗口内玩家中途下令会照旧退出
## evasion_mode，但本标志独立倒计时满 6s——强 buff（100% 机炮闪避 / 90% 甩导弹 /
## 武器静默 / 满速地板 + 加速 ×3）不因指挥操作而中断。
var afterburner_window_active: bool = false

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

# ── 控制意图仲裁（Phase 1，见 scripts/aircraft/control_intent.gd 顶注 + 重构计划 §5）──
var _intent_slots: Dictionary = {}   ## source:int → ControlIntent（sticky slot，跨帧保持）
var _intent_winner_sig: String = ""  ## 上次 resolve 胜者签名（变化才打 INTENT_RESOLVE）
var _intent_log_cd: float = 0.0      ## INTENT_RESOLVE 日志节流
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

## 阵营切换后的单次视觉刷新；不进入每帧路径。
func refresh_faction_visuals() -> void:
	if params:
		match team:
			CombatUnit.TEAM_PLAYER:
				params.icon_color = GameConstants.COL_FRIEND_PLAYER
				params.wing_color = Color(0.25, 0.48, 0.85)
			CombatUnit.TEAM_ALLY:
				params.icon_color = GameConstants.COL_FRIEND_ALLY
				params.wing_color = Color(0.22, 0.50, 0.28)
	if _trail_ribbon:
		_trail_ribbon.ribbon_color = GameConstants.team_trail_color(team)
	queue_redraw()

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

func esm_aura_active() -> bool:
	return Time.get_ticks_msec() <= int(get_meta(&"esm_aura_until_ms", -1))

func esm_lock_rate_multiplier() -> float:
	return float(get_meta(&"esm_lock_rate_mult", 1.0)) if esm_aura_active() else 1.0

func esm_reload_rate_multiplier() -> float:
	if not esm_aura_active():
		return 1.0
	return 1.0 / maxf(float(get_meta(&"esm_reload_time_mult", 0.7)), 0.05)

func laser_stall_pressure_active() -> bool:
	return Time.get_ticks_msec() <= int(get_meta(&"laser_stall_pressure_until_ms", -1))

func show_tactic_popup(text: String) -> void:
	_tactic_popup_text = text
	_tactic_popup_timer = TACTIC_POPUP_DURATION

## 高度动作的唯一写入口。普通高度物理和垂直越过都必须经这里发布。
func _set_altitude_action(next_action: int) -> void:
	if next_action == altitude_action:
		return
	var previous: int = altitude_action
	altitude_action = next_action
	altitude_action_enter_serial += 1
	altitude_action_start_tier = get_altitude_tier()
	if next_action == AltitudeAction.CLIMB:
		_climb_counter_remaining_s = CLIMB_COUNTER_WINDOW_S
	elif previous == AltitudeAction.CLIMB:
		_climb_counter_remaining_s = 0.0
	EventLogger.log_event("ALTITUDE_ACTION", _log_name(),
		"%s serial=%d" % [altitude_action_name(), altitude_action_enter_serial])

## 玩家高度命令唯一写入口：只有 LOW/HIGH 真的发生变化才武装一次普通高度动作。
func command_altitude_preference(next_preference: int) -> void:
	var normalized := clampi(next_preference,
		AltitudePreference.PREFER_CLIMB, AltitudePreference.PREFER_LOW)
	if normalized == altitude_preference:
		return
	altitude_preference = normalized
	altitude_action_command = AltitudeAction.CLIMB \
		if normalized == AltitudePreference.PREFER_CLIMB else AltitudeAction.DIVE
	if _active_special != ActiveSpecialManeuver.VERTICAL_BREAK:
		_set_altitude_action(AltitudeAction.NONE)

func altitude_action_name() -> String:
	match altitude_action:
		AltitudeAction.CLIMB:
			return "CLIMB"
		AltitudeAction.DIVE:
			return "DIVE"
	return "NONE"

func _tick_climb_counter_window(delta: float) -> void:
	if _climb_counter_remaining_s <= 0.0:
		return
	if altitude_action != AltitudeAction.CLIMB:
		_climb_counter_remaining_s = 0.0
		return
	_climb_counter_remaining_s = maxf(_climb_counter_remaining_s - delta, 0.0)

func climb_counter_window_active() -> bool:
	return is_player_squad() and altitude_action == AltitudeAction.CLIMB \
		and _climb_counter_remaining_s > 0.0

func gun_tailed_active() -> bool:
	return Time.get_ticks_msec() <= _gun_tailed_until_ms

## 敌方低频威胁更新上报正式 GUN_TAILED 解；同时消费 4 秒爬升反制窗口。
func report_gun_tailed(attacker: Aircraft) -> void:
	_gun_tailed_until_ms = maxi(_gun_tailed_until_ms,
		Time.get_ticks_msec() + GUN_TAILED_CACHE_MS)
	if not climb_counter_window_active() or attacker == null or not is_instance_valid(attacker):
		return
	if attacker._gun_burst_rounds_left <= 0 \
			or attacker._gun_burst_target_id != get_instance_id() \
			or attacker._gun_climb_frozen_target_id == get_instance_id():
		return
	attacker._gun_climb_frozen_target_id = get_instance_id()
	attacker._gun_climb_frozen_heading = attacker._gun_lead_heading
	show_tactic_popup(tr("POPUP_CLIMB_COUNTER"))
	EventLogger.log_event("CLIMB_GUN_BREAK", _log_name(),
		"froze %s committed burst at %.1fs" % [attacker._log_name(), _climb_counter_remaining_s])

## Missile 自身 60Hz tick 调用；纯运动学门复用 MissileEvasion，不扫描全场。
func try_climb_counter_missile(missile: Missile) -> bool:
	if not climb_counter_window_active() \
			or not MissileEvasion.is_imminent_evasion_threat(self, missile):
		return false
	missile.disrupt_by_climb_break()
	show_tactic_popup(tr("POPUP_CLIMB_COUNTER"))
	EventLogger.log_event("CLIMB_MISSILE_BREAK", _log_name(),
		"disrupted incoming missile at %.1fs" % _climb_counter_remaining_s)
	return true

## 获取挂载的战术机动模块（如有）
func get_maneuver() -> CobraManeuver:
	_refresh_maneuver_cache()
	return _cobra_maneuver_ref

func _get_ai_controller() -> AIController:
	if _ai_ref:
		return _ai_ref
	for child in get_children():
		if child is AIController:
			_ai_ref = child
			return child
	return null

## 当前是否由玩家直接操控。特殊机动据此分流：受控机听 R，AI 接管机按威胁自动释放。
func is_manual_maneuver_controlled() -> bool:
	return _ai_ref != null and _ai_ref.manual_control

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
	_refresh_maneuver_cache()
	return _herbst_maneuver_ref


## Cobra/Herbst 在 AircraftPhysics/AI/武器/规避中每物理帧会查询多次。
## 子节点结构不变时只读 O(1) 缓存；增删/换装通过 CHILD_ORDER_CHANGED 失效。
func _refresh_maneuver_cache() -> void:
	if _maneuver_cache_child_count == get_child_count() \
			and (_cobra_maneuver_ref == null or is_instance_valid(_cobra_maneuver_ref)) \
			and (_herbst_maneuver_ref == null or is_instance_valid(_herbst_maneuver_ref)):
		return
	_maneuver_cache_child_count = get_child_count()
	_cobra_maneuver_ref = null
	_herbst_maneuver_ref = null
	for child in get_children():
		if child is CobraManeuver:
			_cobra_maneuver_ref = child
		elif child is HerbstManeuver:
			_herbst_maneuver_ref = child
	if PerfBuckets.detail_capture_enabled():
		PerfBuckets.count("maneuver_cache_scans")


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_maneuver_cache_child_count = -1

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
	if aa_fire_timer > 0.0:
		aa_fire_timer -= delta
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
	# 主动位移技能必须跨 LOD/切控继续推进；无动作时仅 O(1) 计时，AI 威胁扫描固定 10Hz。
	_update_active_special_maneuver(delta)
	_tick_climb_counter_window(delta)

	# 旋翼机完全绕过固定翼 bank/G/失速链；武器仍复用 AircraftWeapons。
	if params and params.flight_model == AircraftParams.FlightModel.ROTORCRAFT:
		_physics_process_rotorcraft(delta)
		return

	# LOD 2（屏幕外）：每3帧完整处理，其余帧仅位移
	if lod_level >= 2:
		# 编队跟随机：屏外也必须维持编队几何，否则 leader 机动后 follower 漂出阵型
		# （旧版 LOD 2 完全不调 update_follow → 三轰炸机/Sentinel UAV 漂离）
		# update_follow 内部已按 _lod_frame % 3 把 speed/altitude 节流到 20Hz；
		# heading/bank/position 60Hz 是必要开销（leader 转向时槽位变化太快）
		if formation_mode and _formation_leader and is_instance_valid(_formation_leader):
			AircraftFormation.update_follow(self, delta)
			AircraftWeapons.update_passive_gunship(self, delta)
			if _lod_frame % 3 == 0:
				AircraftWeapons.update_formation_passive_missile(self, delta * 3.0)
			AircraftFlares.update(self, delta)  # 编队中也要更新/清除 flare 粒子，否则残留不消失
			return
		if _lod_frame % 3 != 0:
			AircraftPhysics.apply_movement(self, delta)
			AircraftWeapons.update_passive_gunship(self, delta)
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
		_resolve_intents(lod_delta)  # Phase 1：决策后、物理前仲裁契约字段
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
		if gunship_mode_active and is_player_squad():
			AircraftWeapons.update_passive_gunship(self, delta)
		elif combat_target != null:
			AircraftWeapons.update_gun(self, lod_delta)
		if combat_target != null:
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
			AircraftWeapons.update_passive_gunship(self, delta)
			if every3:
				AircraftWeapons.update_formation_passive_missile(self, delta * 3.0)
			AircraftFlares.update(self, delta)  # 编队中也要更新/清除 flare 粒子，否则残留不消失
			return

		# ── 非编队 LOD 1（降低运算频率） ──
		_run_tactical_planner_if_enabled()  # P4：LOD 1 非编队也需 planner 写决策
		AircraftWeapons.update_weapon_mode(self)
		if combat_target != null:
			AircraftCombatTracking.update_combat(self, delta)
		_resolve_intents(delta)  # Phase 1：决策后、物理前仲裁契约字段
		if every3:
			AircraftPhysics.update_energy_management(self)
		AircraftPhysics.update_target_heading(self)
		AircraftPhysics.update_bank(self, delta)
		AircraftPhysics.update_heading(self, delta)
		AircraftPhysics.update_speed(self, delta)
		if every3:
			# ⚠ every3 节流必须 ×3 补偿 delta（同 LOD2 的 lod_delta 教训，2026-07-03 修：
			# 旧版传裸 delta → LOD1 非编队机爬升/燃油/flare CD 全部 1/3 速率演化）
			var every3_delta := delta * 3.0
			AircraftPhysics.update_stall(self)  # 在 update_altitude 前
			AircraftPhysics.update_altitude(self, every3_delta)
			AircraftPhysics.update_fuel(self, every3_delta)
			_check_ground_crash()
			AircraftPhysics.update_g_load(self)
		AircraftPhysics.apply_movement(self, delta)
		if combat_target != null or (gunship_mode_active and is_player_squad()):
			AircraftWeapons.auto_gun_scan(self)
			AircraftWeapons.update_gun(self, delta)
		if combat_target != null:
			AircraftWeapons.update_rocket(self, delta)
			AircraftWeapons.update_missile(self, delta)
		AircraftWeapons.update_torpedo(self, delta)
		AircraftWeapons.update_loyal_wingman(self, delta)
		# 副导弹槽（独立子系统）
		AircraftWeapons.update_secondary_radar(self, delta)
		AircraftWeapons.update_secondary_missile(self, delta)
		if every3:
			AircraftFlares.update(self, delta * 3.0)  # 同款 ×3 补偿：flare CD/粒子寿命
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
		AircraftWeapons.update_passive_gunship(self, delta)
		if _lod_frame % 3 == 0:
			AircraftWeapons.update_formation_passive_missile(self, delta * 3.0)
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
	_resolve_intents(delta)  # Phase 1：决策系统全部跑完 → 仲裁契约字段 → 物理消费

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
	# 胆大妄为：当前操控机听 R；AI 僚机在同一威胁门下自动滚转/投焰。
	_update_manual_dodge_skill()
	# 722 批签名技能杂项 tick（CD 计时 + VIFFing/近太空冲刺/三发推力条件判定）
	_update_sig_skills(delta)
	AircraftFlares.update(self, delta)
	PerfBuckets.tick("ac_phys.evade", Time.get_ticks_usec() - _t_evade)

	var _t_visual: int = Time.get_ticks_usec()
	_update_visuals()
	_log_ac_tick(delta)
	PerfBuckets.tick("ac_phys.visual", Time.get_ticks_usec() - _t_visual)
	# LOD 0 非玩家非悬停：每 2 帧重绘一次，减半 _draw 开销
	if selected or is_hovered or _lod_frame % 2 == 0:
		queue_redraw()

## 旋翼机专用的轻量物理/武器路径。运动由 AircraftPhysics.update_rotorcraft 统一处理，
## 不进入固定翼的失速、G 力、能量管理和 BFM combat tracking。
func _physics_process_rotorcraft(delta: float) -> void:
	var _t_kine: int = Time.get_ticks_usec()
	AircraftPhysics.update_rotorcraft(self, delta)
	AircraftPhysics.update_fuel(self, delta)
	PerfBuckets.tick("ac_phys.kine.rotor", Time.get_ticks_usec() - _t_kine)

	var _t_wpn: int = Time.get_ticks_usec()
	weapon_mode = WeaponMode.GUN
	AircraftWeapons.update_gun(self, delta)
	AircraftWeapons.update_rocket(self, delta)
	PerfBuckets.tick("ac_phys.wpn.rotor", Time.get_ticks_usec() - _t_wpn)

	AircraftFlares.update(self, delta)
	_update_visuals()
	if selected or is_hovered or _lod_frame % 2 == 0:
		queue_redraw()

# ══════════════════════════════════════════════
#  控制意图仲裁（Phase 1 Step 1）
# ══════════════════════════════════════════════

## 提交/替换一份控制意图（sticky：保持有效直到同源覆盖或 withdraw_intent）
func submit_intent(source: int, ci: ControlIntent) -> void:
	_intent_slots[source] = ci


## 撤销某源的意图。进/出状态的生命周期必须对称调用（exit_evade / set_evasion_mode(false)）
func withdraw_intent(source: int) -> void:
	_intent_slots.erase(source)


## 按字段仲裁并写入 target_* —— 每物理帧在决策系统（planner/evasion/combat）之后、
## 物理链（update_target_heading 起）之前调用一次。pursuit/speed/AB 三个契约字段的
## 写入权从"谁后写谁赢"收口到这里（重构计划 R1 根治起点）。
## 未迁移的直写者（旧 BFM / _process_simple / EM / 编队 / BOSS）不受影响：
## 无槽位主张的字段 resolve 不碰，直写值照常生效。
func _resolve_intents(delta: float) -> void:
	_intent_log_cd = maxf(_intent_log_cd - delta, 0.0)
	# 急刹桥接：事件式布尔旗 → BRAKE 槽。速度/AB 满优先级压一切；pursuit 用 25 特例
	# （压 TACTIC、让位 EVADE 蛇形几何——与迁移前帧序行为精确等价）。
	# update_speed 的急刹分支自算失速软地板，不消费这里的速度意图值（仅保持字段语义一致）。
	if hard_brake:
		var b := ControlIntent.new()
		b.clear_pursuit = true
		b.pursuit_pri = 25
		b.target_speed_kmh = 0.0
		b.afterburner = 0
		_intent_slots[ControlIntent.SOURCE_BRAKE] = b
	else:
		_intent_slots.erase(ControlIntent.SOURCE_BRAKE)

	if _intent_slots.is_empty():
		return
	var win_p := -1
	var win_s := -1
	var win_a := -1
	var pri_p := -1
	var pri_s := -1
	var pri_a := -1
	for src in _intent_slots:
		var ci: ControlIntent = _intent_slots[src]
		var pr: int = ControlIntent.PRIORITY[src]
		if ci.pursuit_pos != Vector2.INF or ci.clear_pursuit:
			var ppr: int = ci.pursuit_pri if ci.pursuit_pri >= 0 else pr
			if ppr > pri_p:
				pri_p = ppr
				win_p = src
		if ci.target_speed_kmh >= 0.0 and pr > pri_s:
			pri_s = pr
			win_s = src
		if ci.afterburner >= 0 and pr > pri_a:
			pri_a = pr
			win_a = src
	if win_p >= 0:
		var cw: ControlIntent = _intent_slots[win_p]
		target_position = Vector2.INF if cw.clear_pursuit else cw.pursuit_pos
	if win_s >= 0:
		target_speed_kmh = _intent_slots[win_s].target_speed_kmh
	if win_a >= 0:
		AircraftPhysics.set_afterburner(self, _intent_slots[win_a].afterburner == 1)
	# 可解释性：胜者集合变化时打一行（"飞机为什么这么飞"从翻代码变成看日志）
	if is_player_squad() or selected:
		var sig := "p%d/s%d/a%d" % [win_p, win_s, win_a]
		if sig != _intent_winner_sig and _intent_log_cd <= 0.0:
			_intent_winner_sig = sig
			_intent_log_cd = 0.5
			EventLogger.log_event("INTENT_RESOLVE", _log_name(),
				"pursuit=%s speed=%s ab=%s" % [
					_intent_src_name(win_p), _intent_src_name(win_s), _intent_src_name(win_a)])


static func _intent_src_name(src: int) -> String:
	match src:
		ControlIntent.SOURCE_TACTIC: return "TACTIC"
		ControlIntent.SOURCE_EVADE: return "EVADE"
		ControlIntent.SOURCE_BRAKE: return "BRAKE"
	return "none"


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
	# 交战速度治理：压掉"盘旋半径 > 交战距离 → 机头几何上指不到目标 → 满 G 绕圈"的死结。
	# 逻辑全在模块内，这里只有接线（目前只对王牌中队生效，见模块 is_governed）
	if EngagementSpeedGovernor.is_governed(self):
		# 带减速迟滞：25% 概率晚 0.6~1.2s 才开始减速 → 冲过头（wraith spec §2.4 执行失误）。
		# 本函数没有 delta 形参（三个 LOD 分支各自调它），这里直接取物理帧长 ——
		# 对王牌中队成立：该 tier 豁免 LOD，planner 恒为每帧跑一次（ace-squadron-tier §2.1）
		EngagementSpeedGovernor.apply_with_lag(self, s, plan, get_physics_process_delta_time())
	# intent 切换时戳时间（用于下一帧的 hysteresis 判定）+ 诊断日志
	if plan.intent != _bfm_prev_intent:
		# 切换瞬间打 PLAN log，便于追溯"飞机为什么这帧选了这个 intent"
		# 玩家 + 玩家方友军 + 选中机都记录，敌机仍 silenced 避免刷爆日志
		if (is_player_squad() or selected) and not is_destroyed:
			var tgt_name: String = "none"
			if combat_target and is_instance_valid(combat_target):
				tgt_name = _log_unit_name(combat_target)
			var prev_name: String = TacticalPlan.intent_name(_bfm_prev_intent) if _bfm_prev_intent != -1 else "init"
			EventLogger.log_event("PLAN", _log_name(),
				"%s → %s (tgt=%s, why=%s)" % [
					prev_name, TacticalPlan.intent_name(plan.intent), tgt_name, plan.rationale
				])
		_bfm_prev_intent = plan.intent
		# 时钟统一走 Situation.now()：与 Situation 读时序状态同源，无头 sim 才能拨快时间
		_bfm_intent_started_at = Situation.now()
	# extend 触发：本帧 plan 标记触发就把 _bfm_extend_until 推到 now + 触发秒数
	if plan.trigger_extend_seconds > 0.0:
		_bfm_extend_until = Situation.now() + plan.trigger_extend_seconds
	_apply_tactical_plan(plan)
	_last_plan = plan

## 把 plan 输出写到 Aircraft 字段，供后续物理/武器子系统消费。
## ⚠ 这是 plan 唯一接触 Aircraft 状态的位置，便于追溯"为什么这帧 target_speed 是这个值"
func _apply_tactical_plan(plan: TacticalPlan) -> void:
	# Phase 1：pursuit/speed/AB 三个契约字段改走意图仲裁（_resolve_intents 在决策系统
	# 跑完后统一写入）。pursuit=INF 即"不主张"，语义同旧"CRUISE/EVADE 不写、保留给
	# _update_evasion 控制"；急刹覆盖由 resolve 的 BRAKE 槽承担（速度/AB 满优先级、
	# pursuit=25 让位 EVADE 几何，与旧帧序精确等价）。weapon/gun/高度仍直写（后批迁移）。
	var ci := ControlIntent.new()
	ci.pursuit_pos = plan.pursuit_pos
	ci.target_speed_kmh = plan.target_speed_kmh
	ci.afterburner = 1 if plan.afterburner else 0
	submit_intent(ControlIntent.SOURCE_TACTIC, ci)

	# 武器竞选滞回状态回写（spec weapon-employment-doctrine：胜者不变累计保持时长，
	# 变化即归零——WeaponSelector 用它实现 1.5s 防抖）
	if plan.primary_weapon == _primary_weapon_kind:
		_primary_weapon_hold_s += get_physics_process_delta_time()
	else:
		_primary_weapon_kind = plan.primary_weapon
		_primary_weapon_hold_s = 0.0
	# plan 级坡度上限（LINE_UP 充能平台等武器纪律；update_bank/step_bank 消费）
	_plan_bank_limit_rad = deg_to_rad(plan.bank_limit_deg) if plan.bank_limit_deg > 0.0 else -1.0
	# 对面攻击 pass 相位回写（spec surface-attack-pass）；非 GROUND_STRAFE 的 plan 恒填 SETUP → 复位
	_strafe_pass_phase = plan.strafe_pass_phase
	# 武器模式
	# NONE 显式重置为 GUN（防止 weapon_mode 残留 MISSILE 让 salvo 路径在 CRUISE/EVADE 期间走漏发射）
	match plan.weapon_mode:
		TacticalPlan.WeaponMode.GUN, TacticalPlan.WeaponMode.NONE:
			weapon_mode = WeaponMode.GUN
		TacticalPlan.WeaponMode.MISSILE:
			weapon_mode = WeaponMode.MISSILE
		_:
			pass  # BOTH 保留

	# ── 机炮瞄准（2026-07-04 修"机炮侧射"）──
	# 旧实现瞄 plan.pursuit_pos（战术追踪点）：导弹 crank / 僚机侧向位 / lag 等 intent 的
	# 追踪点故意偏离目标，AI 僚机（auto_gun_scan 对非玩家有 combat_target 时整体跳过、
	# 无人修正）就朝追踪点方向侧喷（log 实证 230431 [230.9] Orbit aim_vs_nose=-74°）。
	# 现在：瞄 combat_target 的双迭代提前点（与旧 combat_tracking 路径同款公式）；
	# 地面/船慢目标直接瞄；并补固定机炮物理锥门——瞄准方向偏机头超过
	# gun.fire_cone_half_angle 不开火（真机机炮沿机身固定，不能侧射）。
	var aim_ok := false
	if combat_target != null and is_instance_valid(combat_target) and not combat_target.is_destroyed:
		# 统一提前点公式（spec weapon-employment-doctrine §2.3：全指向性武器共用，
		# 弹速按武器传入——机炮=muzzle_velocity；helper 在 AircraftWeapons）
		var bullet_mps: float = params.gun.muzzle_velocity if (params and params.gun) else 1000.0
		_gun_lead_heading = AircraftWeapons.lead_heading(self, combat_target, bullet_mps)
		var cone_half: float = deg_to_rad(effective_gun_cone_half_angle_deg()) \
				if (params and params.gun) else 0.26
		aim_ok = absf(_angle_diff(_gun_lead_heading, heading)) <= cone_half
	else:
		_gun_lead_heading = heading
	# is_firing：plan 允许 + 提前点在机头锥内 + AI burst 节奏 gate（team != 0 才节流）
	is_firing = _ai_gun_burst_allowed(plan.allow_gun_fire and aim_ok, get_physics_process_delta_time())
	if is_firing and (is_player_squad() or selected) \
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

	# 高度（plan 没指定就保持现状）。先同步 tier，再让显式米数覆写：玩家 HIGH 自然高度带
	# 需要保留 target_altitude_tier=HIGH 的状态语义，同时把实际目标放在约 8400m 而非 10000m。
	if plan.target_altitude_tier >= 0:
		set_target_tier(plan.target_altitude_tier)
	if plan.target_altitude_m >= 0.0:
		target_altitude = plan.target_altitude_m
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

## 722 批签名技能杂项 tick（spec aircraft-signature-skills）：CD 递减 + 条件触发。
## 全 O(1) 字段读；未持有任何签名技能时只付几次 float 比较（60Hz × 9 机可忽略）。
func _update_sig_skills(delta: float) -> void:
	if _sig_a10_cheat_cd > 0.0:
		_sig_a10_cheat_cd -= delta
	if _sig_viffing_cd > 0.0:
		_sig_viffing_cd -= delta
	if _sig_faxx_cd > 0.0:
		_sig_faxx_cd -= delta
	if _sig_mig41_dash_cd > 0.0:
		_sig_mig41_dash_cd -= delta
	if _sig_mig41_dive_timer > 0.0:
		_sig_mig41_dive_timer -= delta
	if _sig_j36_cd > 0.0:
		_sig_j36_cd -= delta
	# VIFFing（Harrier）：速度降到 200 km/h 以下瞬间获得 4s 无敌（内置 CD 20s）
	if sig_viffing_active and _sig_viffing_cd <= 0.0 and speed * 3.6 < 200.0 and not is_destroyed:
		_sig_viffing_cd = 20.0
		apply_status(StatusEffects.INVINCIBLE, 4.0, "no_refresh")
		EventLogger.log_event("SKILL", _log_name(), "VIFFing：低速触发 4s 无敌（CD 20s）")
	# 近太空冲刺（MiG-41）：统一 DIVE 进入沿，且动作起点处于 HIGH。
	if _sig_mig41_seen_action_serial != altitude_action_enter_serial:
		_sig_mig41_seen_action_serial = altitude_action_enter_serial
		if sig_mig41_active and altitude_action == AltitudeAction.DIVE \
				and altitude_action_start_tier == AltitudeTier.HIGH \
				and _sig_mig41_dash_cd <= 0.0:
			_sig_mig41_dash_cd = 30.0
			_sig_mig41_dive_timer = 8.0
			apply_status(StatusEffects.OVERLOAD, 8.0)
			EventLogger.log_event("SKILL", _log_name(), "近太空冲刺：俯冲触发 8s 超载 + 加速强化")
	# 三发推力（J-36）：命令目标被消灭 / 命令解除 → buff 结束（触发在 SquadCommandController）
	if sig_j36_assault_active:
		if commanded_target == null or not is_instance_valid(commanded_target) \
				or commanded_target.is_destroyed:
			sig_j36_assault_active = false
			EventLogger.log_event("SKILL", _log_name(), "三发推力：目标消灭/命令解除，buff 结束")
	if hunter_assault_active:
		if commanded_target == null or not is_instance_valid(commanded_target) \
				or commanded_target.is_destroyed:
			hunter_assault_active = false
			EventLogger.log_event("SKILL", _log_name(), "猎手：目标消灭/命令解除，buff 结束")
	# 超速截击（MiG-31）：加力窗口内对机头前半球∩雷达锥中的满锁+包线目标每 1.2s 自动发射一枚
	# （唯一绕开窗口禁火的通道——独立发射路径不经 _fire_missile_at 的硬断；弹速 ×1.3）
	if sig_mig31_active and afterburner_window_active and params and params.missile \
			and missiles_remaining > 0 and missile_manager:
		_sig_mig31_fire_timer -= delta
		if _sig_mig31_fire_timer <= 0.0:
			var mig_tgt: CombatUnit = _sig_mig31_pick_target()
			if mig_tgt != null:
				_sig_mig31_fire_timer = 1.2
				var fast_msl: MissileParams = params.missile.duplicate()
				fast_msl.max_speed *= 1.3
				missile_manager.spawn_missile(self, mig_tgt, fast_msl)
				notify_missile_fired_at(mig_tgt)
				if not infinite_ammo:
					missiles_remaining -= 1
				EventLogger.log_event("SKILL", _log_name(),
					"超速截击：窗口自动发射 → %s（弹速×1.3）" % _log_unit_name(mig_tgt))
	elif _sig_mig31_fire_timer > 0.0 and not afterburner_window_active:
		_sig_mig31_fire_timer = 0.0


## 超速截击选目标：机头前半球且在雷达锥内 + 满锁 + 出 min_range + 同目标无在飞弹，取最近
func _sig_mig31_pick_target() -> CombatUnit:
	if params == null or params.missile == null:
		return null
	var thr: float = params.lock_time
	var min_px: float = params.missile.min_range * CombatUnit.PIXELS_PER_METER
	var best: CombatUnit = null
	var best_d: float = INF
	for t in radar_targets:
		if not is_instance_valid(t) or t.is_destroyed or not is_hostile_to(t):
			continue
		if float(radar_targets[t]) < thr:
			continue
		# 严格限制机头前半球。即使“多波段搜索”把雷达锥扩到 ±120°，也不能向后半球发射。
		var to_target: Vector2 = t.global_position - global_position
		var target_bearing: float = atan2(to_target.x, -to_target.y)
		if absf(_angle_diff(target_bearing, heading)) > PI * 0.5:
			continue
		# 离锥后可能仍保留满锁（例如“唯一的锁定”宽限窗），当前不在锥内同样拒绝。
		if not is_in_radar_cone(t.global_position):
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d < min_px:
			continue
		if missile_manager.count_active_missiles_at(self, t) >= 1:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


## 眼镜蛇机动技能：当前操控机由 R 入口触发；本函数只服务 AI 接管机的威胁自动触发。
## 触发要求（全部满足）：
##   1. 玩家拥有该升级（cobra_skill_active）
##   2. 当前由 AI 接管（不要求加力/evasion_mode）
##   3. 当前没有正在进行的机动
##   4. 冷却归零
##   5. 来袭导弹 ≤ COBRA_MISSILE_TRIGGER_PX OR 后方有敌机追尾开火
func _update_cobra_skill(delta: float) -> void:
	if not cobra_skill_active:
		return
	_cobra_skill_cooldown = maxf(_cobra_skill_cooldown - delta, 0.0)
	# 当前操控机只听 R；切控后旧机交还 AI，会自然恢复下方威胁自动触发。
	if is_manual_maneuver_controlled():
		return
	if _cobra_skill_cooldown > 0.0 or _shared_maneuver_cooldown() > 0.0 or is_active_special_maneuver():
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
		_start_shared_maneuver_cooldown(COBRA_SKILL_COOLDOWN)

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

## 危机赫尔贝特技能：当前操控机由 R 入口触发；本函数只服务 AI 接管机的威胁自动触发。
## 与眼镜蛇等价（导弹命中前 / 后方机炮追尾自动触发）；三种 R 机动由 UPGRADES.excludes 互斥。
## 触发要求（全部满足）：
##   1. 玩家拥有该升级（evasion_herbst_active）
##   2. 当前由 AI 接管（不要求加力/evasion_mode）
##   3. 当前没有正在进行的机动（cobra/herbst）
##   4. HerbstManeuver.can_activate（内置 15s 冷却）
##   5. 来袭导弹 ≤ COBRA_MISSILE_TRIGGER_PX OR 后方有敌机追尾开火（复用 cobra 检测）
## activate() 内已置 missile_phase_timer + _lock_immunity_timer，机动期间导弹/机炮免疫。
func _update_evasion_herbst_skill(_delta: float) -> void:
	if not evasion_herbst_active:
		return
	# 当前操控机只听 R；AI 僚机仍用来袭导弹/后方追尾条件自保。
	if is_manual_maneuver_controlled():
		return
	if _shared_maneuver_cooldown() > 0.0 or is_active_special_maneuver():
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
		_start_shared_maneuver_cooldown(HerbstManeuver.COOLDOWN)
		EventLogger.log_event("HOOK", "evasion_herbst",
			"victim=%s turn_dir=%.0f (auto-trigger)" % [_log_name(), turn_dir])

## 胆大妄为 AI 自动路径：当前操控机只听 R；AI 僚机用同一近弹/追尾威胁门自保。
func _update_manual_dodge_skill() -> void:
	if not manual_dodge_active or is_manual_maneuver_controlled() or _manual_dodge_cd > 0.0 \
			or _shared_maneuver_cooldown() > 0.0 or is_active_special_maneuver():
		return
	if _cobra_detect_imminent_missile() or _cobra_detect_tail_gun():
		do_manual_dodge(false)

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
			if u == self or not is_hostile_to(u) or u.is_destroyed or not u is Aircraft:
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

## 统一 GUN_TAILED 查询：眼镜蛇、J-Turn、胆大妄为与主动位移机动共用正式火控解。
func _cobra_detect_tail_gun() -> bool:
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or not u is Aircraft:
			continue
		var enemy: Aircraft = u as Aircraft
		if AircraftWeapons.is_gun_tailed_by(enemy, self):
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
	_gun_burst_rounds_left = 0  # 掐断已承诺的机炮梭：目标没了就没有承诺对象，否则残弹对空放枪
	_auto_gun_target_id = 0
	_gun_burst_target_id = 0
	_strafe_state = 0
	_overshoot_timer = 0.0
	_gun_pass_committed = false  # 清目标时解除机炮提交锁定
	_pursuit_branch = ""
	charge_attack = false

## [保留委托：外部/跨模块调用入口]
## 战斗追踪已搬到 scripts/aircraft/aircraft_combat_tracking.gd
## 以下 5 个薄壳保持 ac._xxx() 写法兼容（被 ai_controller / aircraft_weapons 调用）
## 敌机机炮意图门：无副作用，允许同帧被 planner / tracking / scan 重复查询。
## 真正的“一次机会一梭”与 pause 计时统一由 AircraftWeapons.update_gun 执行，避免调用路径绕过。
func _ai_gun_burst_allowed(want_fire: bool, _delta: float) -> bool:
	if team != TEAM_HOSTILE:
		return want_fire
	return want_fire and _ai_gun_pause_timer <= 0.0

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

## 嗜血基础效果：普通机炮与 CIWS 发射不消耗弹药；零弹药/既有装填流程仍照常封锁。
func bloodlust_gun_ammo_free() -> bool:
	return is_player_squad() and status_bloodlust_active

func ratatat_active() -> bool:
	return status_bloodlust_active and SkillHooks.has_skill(self, SkillHooks.SKILL_RATATAT)

func effective_gun_range_m() -> float:
	if not params or not params.gun:
		return 1000.0
	return params.gun.max_range + (SkillHooks.RATATAT_RANGE_BONUS_M if ratatat_active() else 0.0)

func effective_gun_cone_half_angle_deg() -> float:
	if not params or not params.gun:
		return 15.0
	return params.gun.fire_cone_half_angle \
		+ (SkillHooks.RATATAT_CONE_BONUS_DEG if ratatat_active() else 0.0)

func effective_gun_fire_interval(base_interval: float) -> float:
	return base_interval * (SkillHooks.RATATAT_INTERVAL_MULT if ratatat_active() else 1.0)

## 机炮射程（像素）
func _gun_range_px() -> float:
	if params and params.gun:
		return effective_gun_range_m() * PIXELS_PER_METER
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
	# crank 是**发射后**的支援照射（_crank_timer 由 _fire_missile_at 置位），几何本就该是
	# 稳定的侧偏保持 → 维持柔坡不变
	if is_cranking():
		return 2
	if combat_target == null or not is_instance_valid(combat_target):
		return 0
	var lock_progress: float = radar_targets.get(combat_target, 0.0)
	var lock_time_val: float = params.lock_time if params else 3.0
	if lock_progress >= lock_time_val:
		# 已锁定。但"锁定"不等于"能打"——发射还要求目标进离轴门
		# （aircraft_weapons._has_stable_launch_window：radar_half × 0.55）。
		# 若此刻机头离目标仍在门外，就**不能**降到 phase 2 的柔坡（cap 35%）：
		# 那正好锁死在"锁上了→转不动→进不了发射锥→打不出去→机头继续飘→丢锁"的闭环里。
		# 实测（test_slow_air_pass C 段）：满锁 3.30s 时 nose 27°，坡度被压到 27.6°/1.1G
		# （可用 7.5G），离轴角随后 27°→31°→43° 越飘越远，一枪未发。
		# 门外一律按"接近段"给满转弯权限，把机头带进锥内；进锥后再柔化保锁。
		if not _target_within_launch_cone():
			return 0
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

## 目标是否已进入导弹发射离轴门（与 aircraft_weapons 的 skill 插值 off-axis
## 判据同源；此处只关心角度且使用档案基值，不采样 jitter）。供 _get_missile_phase 判断
## "锁定了但还打不出去"，避免过早降低转弯权限。
func _target_within_launch_cone() -> bool:
	if combat_target == null or not is_instance_valid(combat_target) or params == null:
		return false
	var is_faf: bool = params.missile != null and params.missile.fire_and_forget
	var skill: float = params.combat.missile_skill if params.combat != null else 0.0
	var ratio := AircraftWeapons.stable_offaxis_ratio(is_faf, skill)
	var to_tgt: Vector2 = combat_target.global_position - global_position
	var off_axis: float = absf(_angle_diff(atan2(to_tgt.x, -to_tgt.y), heading))
	return off_axis <= deg_to_rad(params.radar_half_angle * ratio)

## 切换规避模式：进入时清空当前指令（等同右键"解除任务"），离开时不动作
## 供 HUD 按钮 / 键位 / 点击逻辑统一调用
##
## CD 修饰走 cd_rate() 速率模型；切换模式不改写运行中倒计时。
## suppress_radio：加力模式激活时传 true —— 抑制 "break" 呼叫（加力另走 afterburner_engaged，
## 语义已从"躲导弹"分离），其余 evasion 副作用照旧。默认 false 保持所有旧调用行为不变。
func set_evasion_mode(enabled: bool, suppress_radio: bool = false) -> void:
	var was_enabled := evasion_mode
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
	else:
		# Phase 1：撤销规避几何主张（sticky 槽必须显式撤，否则 S 型/break 点残留压过 planner）
		withdraw_intent(ControlIntent.SOURCE_EVADE)
	# 关闭时不动作，玩家可手动指定新目标

	# ── 玩家专属：把规避模式同步给僚机（散开自保） ──
	# 规则：仅 use_tactical_preference 飞机（玩家）触发传播；状态变化时才传播，避免递归
	# 僚机 set_evasion_mode 不会再次传播（because they don't have use_tactical_preference）
	if use_tactical_preference and enabled != was_enabled:
		_propagate_evasion_to_squad(enabled)

	# ── 无线电 "break" 呼叫（spec radio-chatter §3.3）──
	# 只在 false→true 上升沿广播；走 EventLogger 全局总线，Aircraft 不认识生存模式/UI 层。
	# 频率控制（冷却）全在订阅方，这里只是一个 O(1) 的信号 emit。
	if enabled and not was_enabled and not suppress_radio and callsign != "" and can_speak_on_radio():
		EventLogger.evasion_started.emit(callsign, team)

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

const BERSERK_VIRUS_WEAPON_CD_RATE: float = 1.40
const BERSERK_VIRUS_FLARE_CD_RATE: float = 1.50

## 狂化病毒的动态身份门：技能旗标跟全队，效果只落当前非亲控直属僚机。
func is_berserk_virus_wingman() -> bool:
	var current_player := AircraftRenderer.safe_player_ref()
	return berserk_virus_active and is_player_squad() and self != current_player \
		and _ai_ref != null and is_instance_valid(_ai_ref) and not _ai_ref.manual_control

## 锁定既有 FREE 语义；不清目标、不切状态，所以显式小队命令仍可临时覆盖。
func enforce_berserk_virus_free_mode() -> void:
	if not is_berserk_virus_wingman():
		return
	if _ai_ref.squad_engage_mode != AIController.SquadEngageMode.FREE:
		_ai_ref.squad_engage_mode = AIController.SquadEngageMode.FREE
	if _ai_ref.squad != null:
		if _ai_ref.squad.engage_mode != Squad.EngageMode.FREE:
			_ai_ref.squad.engage_mode = Squad.EngageMode.FREE
		if _ai_ref.squad.formation != Squad.Formation.COMBAT_SPREAD:
			_ai_ref.squad.formation = Squad.Formation.COMBAT_SPREAD

## CD 速率模型（spec modifier-pipeline）：倒计时写基础时长，tick 侧按
## delta × rate 消耗。mult < 1 表示 CD 更短，因此 rate = 1 / 乘数栈。
func cd_rate(channel: String) -> float:
	var mult := 1.0
	match channel:
		"weapon":
			if evasion_mode:
				mult *= float(evasion_modifiers.get("weapon_cd_mult", 1.0))
			if cloud_weapon_cd_mult != 1.0 and cloud_state >= 1:
				mult *= cloud_weapon_cd_mult
		"flare":
			if evasion_mode:
				mult *= float(evasion_modifiers.get("flare_cd_mult", 1.0))
			if is_player_squad() and low_hp_flare_reload_mult > 0.0 \
					and low_hp_flare_reload_mult != 1.0 and params \
					and hp / maxf(params.max_hp, 1.0) < 0.5:
				mult *= low_hp_flare_reload_mult
		"missile_reload":
			if evasion_mode:
				mult *= float(evasion_modifiers.get("missile_reload_mult", 1.0))
	var rate := 1.0 / maxf(mult, 0.01)
	if is_berserk_virus_wingman():
		if channel == "weapon":
			rate *= BERSERK_VIRUS_WEAPON_CD_RATE
		elif channel == "flare":
			rate *= BERSERK_VIRUS_FLARE_CD_RATE
	return rate

## 触发一次闪避滚转动画（子弹闪避/热诱弹成功时的视觉反馈）
func _trigger_evasion_roll() -> void:
	if _evade_roll_remaining <= 0.0 and _evade_roll_cooldown <= 0.0:
		_evade_roll_remaining = _EVADE_ROLL_DURATION
		# BOSS（高闪避率）给更长冷却，防止一直滚转
		if bullet_dodge_chance >= HIGH_DODGE_THRESH:
			_evade_roll_cooldown = BOSS_EVADE_ROLL_CD  # 4 秒才能再次滚转

## 当前是否处于两项新主动位移技能的 ACTIVE 窗口。
func is_active_special_maneuver() -> bool:
	return _active_special != ActiveSpecialManeuver.NONE

## 新命中资格查询。已有 DoT/坠毁/Debug 不走这些 kind，仍可正常结算。
func can_accept_new_hit(kind: String) -> bool:
	if not is_active_special_maneuver():
		return true
	return kind not in ["gun", "rocket", "bomber_bomb", "airburst", "missile", "qmaam", "aoe", "laser", "railgun", "collision"]

func _maneuver_squad() -> Squad:
	if _ai_ref != null and is_instance_valid(_ai_ref) and _ai_ref.squad != null:
		return _ai_ref.squad
	return null

func _shared_maneuver_cooldown() -> float:
	var sq := _maneuver_squad()
	return sq.active_maneuver_cooldown_s if sq != null else _active_special_local_cooldown_s

## 玩家仪表只读：正常构筑五选一；固定顺序仅使 debug/旧档异常共存时结果确定。
func equipped_r_maneuver_id() -> StringName:
	if vertical_break_active:
		return &"vertical_break"
	if displacement_roll_active:
		return &"displacement_roll"
	if cobra_skill_active:
		return &"cobra_skill"
	if evasion_herbst_active:
		return &"evasion_herbst"
	if manual_dodge_active:
		return &"manual_dodge"
	return &""

## 玩家仪表只读：返回唯一 R 技能的一轮完整冷却秒数。
func r_maneuver_cooldown_total() -> float:
	match equipped_r_maneuver_id():
		&"vertical_break":
			return VERTICAL_BREAK_COOLDOWN
		&"displacement_roll":
			return DISPLACEMENT_ROLL_COOLDOWN
		&"cobra_skill":
			return COBRA_SKILL_COOLDOWN
		&"evasion_herbst":
			return HerbstManeuver.COOLDOWN
		&"manual_dodge":
			return MANUAL_DODGE_CD
	return 0.0

## 玩家仪表只读：返回 Squad 所有的共享剩余冷却；无 Squad 时回退本机账本。
func r_maneuver_cooldown_remaining() -> float:
	if equipped_r_maneuver_id() == &"":
		return 0.0
	return _shared_maneuver_cooldown()

func _start_shared_maneuver_cooldown(seconds: float) -> void:
	var sq := _maneuver_squad()
	if sq != null:
		sq.active_maneuver_cooldown_s = maxf(sq.active_maneuver_cooldown_s, seconds)
	else:
		_active_special_local_cooldown_s = maxf(_active_special_local_cooldown_s, seconds)

func _tick_shared_maneuver_cooldown(delta: float) -> void:
	var sq := _maneuver_squad()
	if sq == null:
		_active_special_local_cooldown_s = maxf(_active_special_local_cooldown_s - delta, 0.0)
		return
	# 每个成员都会 physics tick；只能由当前 leader 给同一份 Squad 倒计时一次。
	if sq.leader == self or sq.leader == null or not is_instance_valid(sq.leader):
		sq.active_maneuver_cooldown_s = maxf(sq.active_maneuver_cooldown_s - delta, 0.0)

func _any_r_maneuver_active() -> bool:
	if is_active_special_maneuver():
		return true
	var cobra := get_maneuver()
	if cobra != null and cobra.is_active:
		return true
	var herbst := get_herbst()
	return herbst != null and herbst.is_active

static func _active_special_ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

func _candidate_displacement_score(side: float) -> float:
	var right := Vector2(cos(heading), sin(heading))
	var min_enemy_clearance := 100000.0
	var min_boundary_clearance := INF
	for sample_t in [0.0, 0.5, 1.0]:
		var p := global_position + right * side * DISPLACEMENT_ROLL_DISTANCE_PX * _active_special_ease(sample_t)
		var edge := MapBoundary.distance_to_edge(p)
		if edge < ACTIVE_SPECIAL_BOUNDARY_MARGIN_PX:
			return -INF
		min_boundary_clearance = minf(min_boundary_clearance, edge)
		for unit in CombatUnit.all_units:
			if not is_instance_valid(unit) or unit == self or unit.is_destroyed or not unit is Aircraft:
				continue
			if not is_hostile_to(unit):
				continue
			min_enemy_clearance = minf(min_enemy_clearance, p.distance_to(unit.global_position))
	return min_enemy_clearance + 0.75 * min_boundary_clearance

func _try_start_displacement_roll() -> bool:
	if not displacement_roll_active or is_destroyed or _shared_maneuver_cooldown() > 0.0 \
			or _any_r_maneuver_active() or (params and params.flight_model == AircraftParams.FlightModel.ROTORCRAFT):
		return false
	# 激活当帧唯一一次 O(N) 安全快照；平分固定选右。
	var left_score := _candidate_displacement_score(-1.0)
	var right_score := _candidate_displacement_score(1.0)
	if is_inf(left_score) and left_score < 0.0 and is_inf(right_score) and right_score < 0.0:
		show_tactic_popup(tr("POPUP_MANEUVER_BLOCKED"))
		return false
	_active_special_side = 1.0 if right_score >= left_score else -1.0
	_active_special_lateral_axis = Vector2(cos(heading), sin(heading))
	_active_special = ActiveSpecialManeuver.DISPLACEMENT_ROLL
	_active_special_elapsed = 0.0
	_active_special_prev_ease = 0.0
	_active_special_heading_offset = 0.0
	_active_special_roll_visual = 0.0
	_active_special_pitch_visual = 0.0
	if formation_mode:
		clear_formation()
	_start_shared_maneuver_cooldown(DISPLACEMENT_ROLL_COOLDOWN)
	show_tactic_popup(tr("POPUP_DISPLACEMENT_ROLL"))
	EventLogger.log_event("MANUAL_MANEUVER", _log_name(), "displacement_roll side=%+.0f" % _active_special_side)
	return true

func _try_start_vertical_break() -> bool:
	if not vertical_break_active or is_destroyed or _shared_maneuver_cooldown() > 0.0 \
			or _any_r_maneuver_active() or (params and params.flight_model == AircraftParams.FlightModel.ROTORCRAFT):
		return false
	var climb := get_altitude_tier() == AltitudeTier.LOW
	var hard_limit := params.max_altitude if climb and params else VERTICAL_BREAK_MIN_ALTITUDE_M
	var available := (hard_limit - altitude) if climb else (altitude - VERTICAL_BREAK_MIN_ALTITUDE_M)
	var distance := minf(VERTICAL_BREAK_DISTANCE_M, available)
	if distance < VERTICAL_BREAK_MIN_DISTANCE_M:
		show_tactic_popup(tr("POPUP_MANEUVER_BLOCKED"))
		return false
	_active_special = ActiveSpecialManeuver.VERTICAL_BREAK
	_active_special_elapsed = 0.0
	_active_special_prev_ease = 0.0
	_active_special_start_altitude = altitude
	_active_special_end_altitude = altitude + distance * (1.0 if climb else -1.0)
	_active_special_start_speed = speed
	_active_special_queued_altitude = INF
	_active_special_last_target_altitude = altitude
	target_altitude = altitude
	vertical_speed = 0.0
	_active_special_pitch_visual = 0.0
	altitude_action_command = AltitudeAction.NONE
	_set_altitude_action(AltitudeAction.CLIMB if climb else AltitudeAction.DIVE)
	if formation_mode:
		clear_formation()
	_start_shared_maneuver_cooldown(VERTICAL_BREAK_COOLDOWN)
	show_tactic_popup(tr("POPUP_VERTICAL_BREAK"))
	EventLogger.log_event("MANUAL_MANEUVER", _log_name(), "vertical_break %.0f->%.0fm" % [altitude, _active_special_end_altitude])
	return true

func _finish_active_special_maneuver() -> void:
	var finished := _active_special
	if finished == ActiveSpecialManeuver.VERTICAL_BREAK:
		altitude = _active_special_end_altitude
		vertical_speed = 0.0
		target_altitude = _active_special_queued_altitude if not is_inf(_active_special_queued_altitude) else altitude
		_set_altitude_action(AltitudeAction.NONE)
	_active_special = ActiveSpecialManeuver.NONE
	_active_special_elapsed = 0.0
	_active_special_prev_ease = 0.0
	_active_special_heading_offset = 0.0
	_active_special_roll_visual = 0.0
	_active_special_pitch_visual = 0.0
	_active_special_queued_altitude = INF
	SkillHooks.on_special_maneuver_done(self)

func _advance_active_special_maneuver(delta: float) -> void:
	if not is_active_special_maneuver():
		return
	var duration := DISPLACEMENT_ROLL_DURATION if _active_special == ActiveSpecialManeuver.DISPLACEMENT_ROLL else VERTICAL_BREAK_DURATION
	_active_special_elapsed = minf(_active_special_elapsed + delta, duration)
	var t := _active_special_elapsed / duration
	var eased := _active_special_ease(t)
	var ease_delta := eased - _active_special_prev_ease
	if _active_special == ActiveSpecialManeuver.DISPLACEMENT_ROLL:
		global_position += _active_special_lateral_axis * _active_special_side * DISPLACEMENT_ROLL_DISTANCE_PX * ease_delta
		_active_special_heading_offset = _active_special_side * DISPLACEMENT_ROLL_HEADING_PEAK * sin(PI * t)
		_active_special_roll_visual = _active_special_side * TAU * t
	else:
		# 俯视 2.5D 俯仰投影：中段姿态最陡，首尾回到水平；方向由高度变化区分。
		_active_special_pitch_visual = sin(PI * t)
		# 识别动作中后来写入的高度命令；本帧仍由技能主张绝对高度，EXIT 后只恢复最后一条。
		if absf(target_altitude - _active_special_last_target_altitude) > 1.0:
			_active_special_queued_altitude = target_altitude
		altitude = lerpf(_active_special_start_altitude, _active_special_end_altitude, eased)
		vertical_speed = 0.0 # 禁止把虚拟爬升率再次交给 PE↔KE 反抽
		var climb := _active_special_end_altitude > _active_special_start_altitude
		var skill_speed_delta := _active_special_start_speed * ((0.82 if climb else 1.15) - 1.0) * ease_delta
		speed += skill_speed_delta
		var min_speed := AircraftPhysics.corner_speed_kmh(self) / 3.6
		var max_speed := AircraftPhysics.effective_max_speed_kmh(self) / 3.6
		speed = clampf(speed, min_speed, max_speed)
		target_altitude = altitude
		_active_special_last_target_altitude = target_altitude
	_active_special_prev_ease = eased
	if _active_special_elapsed >= duration:
		_finish_active_special_maneuver()

func _active_special_missile_threat(trigger_px: float) -> bool:
	if missile_manager == null:
		return false
	var trigger_sq := trigger_px * trigger_px
	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var missile := child as Missile
		if not missile.is_active or missile.is_flare_jammed or missile.target != self or not missile.has_guidance:
			continue
		if global_position.distance_squared_to(missile.global_position) <= trigger_sq:
			return true
	return false

func _active_special_tail_threat() -> bool:
	return _cobra_detect_tail_gun()

func _update_active_special_maneuver(delta: float) -> void:
	_tick_shared_maneuver_cooldown(delta)
	if is_active_special_maneuver():
		_advance_active_special_maneuver(delta)
		return
	if is_manual_maneuver_controlled() or (not vertical_break_active and not displacement_roll_active):
		return
	_active_special_auto_timer = maxf(_active_special_auto_timer - delta, 0.0)
	if _active_special_auto_timer > 0.0 or _shared_maneuver_cooldown() > 0.0:
		return
	_active_special_auto_timer = ACTIVE_SPECIAL_AUTO_INTERVAL
	var tail_threat := _active_special_tail_threat()
	if vertical_break_active and (_active_special_missile_threat(VERTICAL_BREAK_MISSILE_TRIGGER_PX) or tail_threat):
		if _try_start_vertical_break():
			return
	if displacement_roll_active and (_active_special_missile_threat(DISPLACEMENT_ROLL_MISSILE_TRIGGER_PX) or tail_threat):
		_try_start_displacement_roll()

## R 键统一机动入口：正常卡池保证五项主动机动互斥。
## 固定优先级只处理旧档/debug 异常共存；失败时继续尝试下一项。
func try_manual_maneuver() -> bool:
	if is_destroyed:
		return false
	if _shared_maneuver_cooldown() > 0.0 or _any_r_maneuver_active():
		return false
	if _try_start_vertical_break():
		return true
	if _try_start_displacement_roll():
		return true
	var cobra: CobraManeuver = get_maneuver()
	var herbst: HerbstManeuver = get_herbst()
	if cobra_skill_active and _cobra_skill_cooldown <= 0.0 \
			and cobra != null and not cobra.is_active \
			and (herbst == null or not herbst.is_active):
		# 技能版可重复使用；模块原生 is_used 仍服务敌机的一次性眼镜蛇。
		cobra.is_used = false
		if cobra.activate():
			_cobra_skill_cooldown = COBRA_SKILL_COOLDOWN
			_start_shared_maneuver_cooldown(COBRA_SKILL_COOLDOWN)
			EventLogger.log_event("MANUAL_MANEUVER", _log_name(), "R -> cobra")
			return true
	if evasion_herbst_active and herbst != null and herbst.can_activate \
			and (cobra == null or not cobra.is_active):
		if herbst.activate(_herbst_pick_turn_direction()):
			_start_shared_maneuver_cooldown(HerbstManeuver.COOLDOWN)
			EventLogger.log_event("MANUAL_MANEUVER", _log_name(), "R -> J-Turn")
			return true
	return do_manual_dodge()

## 胆大妄为动作：滚转动画 + 严格时机 i-frame + 有 flare 则同时投放。
## i-frame 用 no_refresh 短窗（0.25s）：必须掐在命中瞬间才躲得掉，按早了白按。
func do_manual_dodge(manual_input: bool = true) -> bool:
	if not manual_dodge_active or _manual_dodge_cd > 0.0 or is_destroyed \
			or _shared_maneuver_cooldown() > 0.0 or _any_r_maneuver_active():
		return false
	_manual_dodge_cd = MANUAL_DODGE_CD
	_start_shared_maneuver_cooldown(MANUAL_DODGE_CD)
	_evade_roll_remaining = _EVADE_ROLL_DURATION   # 复用规避滚转动画（绘制叠加 bank）
	apply_status(StatusEffects.INVINCIBLE, MANUAL_DODGE_IFRAME, "no_refresh")
	if flares_remaining > 0 and missile_manager != null:
		AircraftFlares.release(self)               # 投焰甩导弹（is_flare_jammed 契约照走）
	EventLogger.log_event("MANUAL_DODGE", _log_name(),
		"%s 闪避（flare=%d, iframe=%.2fs）" % ["R" if manual_input else "AI", flares_remaining, MANUAL_DODGE_IFRAME])
	return true

## 规避模式更新（生存模式玩家）
func _update_evasion(delta: float) -> void:
	# 冷却与动画倒计时
	_evade_roll_cooldown = maxf(_evade_roll_cooldown - delta, 0.0)
	_manual_dodge_cd = maxf(_manual_dodge_cd - delta, 0.0)   # 胆大妄为 R/AI 共用冷却
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
	if is_player_squad() and head_on_jam_threshold > 0.0 and not radar_targets.is_empty():
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
	if is_player_squad() and rear_aura_slow_radius_px > 0.0:
		if _rear_aura_cd_remaining > 0.0:
			_rear_aura_cd_remaining -= delta
		else:
			var fired_rear: Array = [false]
			_tick_aura_accumulator(_rear_aura_accum_seconds,
				rear_aura_slow_radius_px, StatusEffects.SLOW, true, delta, fired_rear,
				AURA_DEBUFF_DURATION)
			if fired_rear[0]:
				_rear_aura_cd_remaining = AURA_INTERNAL_CD

	# §C 玩家技能"全向 JAM 光环"：累积模式 + 内置 CD
	if is_player_squad() and jam_aura_radius_px > 0.0:
		if _jam_aura_cd_remaining > 0.0:
			_jam_aura_cd_remaining -= delta
		else:
			var fired_jam: Array = [false]
			_tick_aura_accumulator(_jam_aura_accum_seconds,
				jam_aura_radius_px, StatusEffects.JAM, false, delta, fired_jam,
				JAM_AURA_DURATION)
			if fired_jam[0]:
				_jam_aura_cd_remaining = AURA_INTERNAL_CD

	# 规避动画与走位每帧只推进一次，不能依赖是否装备/触发光环技能。
	_update_evasion_motion(delta)


## 规避滚转动画 + 玩家规避模式走位。独立于任何光环扫描，避免无光环时不执行、
## 双光环时执行两次（modifier-pipeline B6）。
func _update_evasion_motion(delta: float) -> void:
	if _evade_roll_remaining > 0.0:
		var roll_speed := TAU / _EVADE_ROLL_DURATION
		_evade_roll_phase += roll_speed * delta
		if _evade_roll_phase > PI:
			_evade_roll_phase -= TAU
		_evade_roll_remaining -= delta
		if _evade_roll_remaining <= 0.0:
			_evade_roll_remaining = 0.0
			_evade_roll_cooldown = _EVADE_ROLL_COOLDOWN
	else:
		_evade_roll_phase = lerp_angle(_evade_roll_phase, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		if absf(_evade_roll_phase) < 0.02:
			_evade_roll_phase = 0.0

	if not use_tactical_preference or not evasion_mode:
		return

	var incoming_missile: Missile = null
	var closest_dist := INF
	if missile_manager:
		for child in missile_manager.get_children():
			if child is Missile:
				var missile := child as Missile
				if missile.is_active and not missile.is_flare_jammed and missile.target == self:
					var d := global_position.distance_squared_to(missile.global_position)
					if d < closest_dist:
						closest_dist = d
						incoming_missile = missile

	if incoming_missile:
		var dist_px := sqrt(closest_dist)
		var missile_id := incoming_missile.get_instance_id()
		if dist_px < _EVADE_ROLL_TRIGGER_PX \
				and _evade_roll_cooldown <= 0.0 \
				and _evade_roll_remaining <= 0.0 \
				and missile_id != _evade_last_missile_id:
			_evade_roll_remaining = _EVADE_ROLL_DURATION
			_evade_last_missile_id = missile_id

		var missile_dir := (global_position - incoming_missile.global_position).normalized()
		var evade_dir := Vector2(missile_dir.y, -missile_dir.x)
		var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
		var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
		var diff_a := absf(angle_difference(heading, evade_heading_a))
		var diff_b := absf(angle_difference(heading, evade_heading_b))
		var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir
		var evade_intent := ControlIntent.new()
		evade_intent.pursuit_pos = global_position + chosen_dir * 2000.0
		submit_intent(ControlIntent.SOURCE_EVADE, evade_intent)
		if flat_altitude:
			if get_altitude_tier() == AltitudeTier.LOW:
				set_target_tier(AltitudeTier.HIGH)
			else:
				set_target_tier(AltitudeTier.LOW)
	else:
		_evade_last_missile_id = 0
		_evasion_sway_timer += delta
		var sway_period := 3.0
		var sway_angle := sin(_evasion_sway_timer * TAU / sway_period) * 0.8
		var sway_heading := heading + sway_angle
		var sway_intent := ControlIntent.new()
		sway_intent.pursuit_pos = global_position \
			+ Vector2(sin(sway_heading), -cos(sway_heading)) * 1500.0
		submit_intent(ControlIntent.SOURCE_EVADE, sway_intent)


## 累积式光环通用 tick：统一处理 rear_slow / jam_aura（未来加新光环可复用）
##   accum_dict: { instance_id → 累积秒数 }（每光环各自一个）
##   radius_px: 生效半径
##   status_id: 累积满后施加的状态 id
##   require_rear: true=需要在我后半球（dot(my_back, to_enemy) > 0.3）
##   delta: 帧时长
## out_fired: 1 元素数组（[bool]），由调用方提供；本帧触发了 debuff 时置 true
func _tick_aura_accumulator(accum_dict: Dictionary,
		radius_px: float, status_id: String,
		require_rear: bool, delta: float, out_fired: Array = [],
		status_duration: float = AURA_DEBUFF_DURATION) -> void:
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
		if not is_hostile_to(u):
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
			u.apply_status(status_id, status_duration)
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

## 节流记录导弹发射被阻塞的原因（每 MSL_BLOCK_LOG_INTERVAL 最多一次）
## 同一 reason 连续触发时不重复记录，直到 reason 改变或间隔到期
## 范围：玩家 + 玩家方友军（team=0），以便排查"僚机决定 combat_target 却不开火"类问题
func _log_msl_block(reason: String, detail: String) -> void:
	var hyper_a_diag: bool = String(get_meta(&"enemy_type", "")) == "hyper_a" \
			and int(get_meta(&"hyper_a_generation", 99)) <= 1
	if not is_player_squad() and not hyper_a_diag:
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

## 节流记录齐射路径"为何一发没打"（每 SALVO_SKIP_LOG_INTERVAL 最多一次）
## 与 _log_msl_block 分开的原因：后者要求 combat_target 非空，而本诊断要覆盖的正是
## "玩家没点目标 → 齐射本该自己找目标却不开火" 这个场景（此时 combat_target 为 null）。
## 记录内容：auto_fire 开关的**运行时实际值** + 每个候选目标被哪道过滤踢掉。
## 用于区分两种病因：开关显示 ON 但运行时 false（UI 脱节） vs 开关真 ON 但过滤器踢光候选。
func _log_salvo_skip(detail: String) -> void:
	var hyper_a_diag: bool = String(get_meta(&"enemy_type", "")) == "hyper_a" \
			and int(get_meta(&"hyper_a_generation", 99)) <= 1
	if not is_player_squad() and not hyper_a_diag:
		return
	# G0/G1 的高速交战窗口可能短于玩家诊断默认的 2s；1s 足以捕获瞬时过滤门，
	# 且最多只覆盖两根 G0 / 四架 G1，不向普通敌群扩散日志成本。
	_salvo_skip_log_timer = 1.0 if hyper_a_diag else SALVO_SKIP_LOG_INTERVAL
	EventLogger.log_event("SALVO_SKIP", _log_name(), detail)

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
		if not is_hostile_to(unit):
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
		if not is_hostile_to(target_unit):
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
	# 722 sig_fcas·作战云中继直通：广播落地绕过本覆写全部钩子（防 OVERLOAD 乘区双乘/防递归），
	# 僚机拿到的时长 = ACE 过完乘区后的最终值（"共享 ACE 的 buff 原样"语义）
	if SkillHooks.cloud_relaying:
		super.apply_status(id, duration, mode)
		return
	# 玩家技能"过载共振"系列：所有 OVERLOAD 来源（含云中超载）统一走本入口。
	var also_bloodlust: bool = false
	if id == StatusEffects.OVERLOAD and is_player_squad() and has_meta("upgrade_stacks"):
		var stacks: Dictionary = get_meta("upgrade_stacks")
		# 时长倍率
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_DURATION_4X, 0)) > 0:
			duration *= SkillHooks.OVERLOAD_DURATION_MULT
		# 燃尽自如：再加固定秒数
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_EXTENDED_AMMO, 0)) > 0:
			duration += SkillHooks.OVERLOAD_DURATION_FLAT_BONUS
		# 噬血共振：进入 OVERLOAD 时同时获得 BLOODLUST 同时长
		if int(stacks.get(SkillHooks.SKILL_OVERLOAD_TO_BLOODLUST, 0)) > 0:
			also_bloodlust = true
	# 722 sig_f22·先敌开火：STEALTH 上升沿（super 前快照，仅 timed 来源；
	# 弹后潜匿等常驻派生隐身不经本路径 → 不会循环触发装填）
	var sig_stealth_rising: bool = id == StatusEffects.STEALTH \
			and not status_effects.has(StatusEffects.STEALTH)
	super.apply_status(id, duration, mode)
	if also_bloodlust:
		# 用同一最终 duration；BLOODLUST 不会被本钩子再次乘上倍率。
		super.apply_status(StatusEffects.BLOODLUST, duration, mode)
	if sig_stealth_rising and is_player_squad() and has_meta("upgrade_stacks") \
			and int((get_meta("upgrade_stacks") as Dictionary).get("sig_f22", 0)) > 0:
		_sig_f22_reload_all()
	# 722 sig_fcas·作战云（队级账本位）：ACE 获得四类增益 → 同步施加全队（已有者刷新）
	if SkillHooks.sig_fcas_active and is_player_squad() \
			and self == AircraftRenderer.safe_player_ref() \
			and (id == StatusEffects.OVERLOAD or id == StatusEffects.BLOODLUST \
			or id == StatusEffects.STEALTH or id == StatusEffects.INVINCIBLE):
		SkillHooks.broadcast_combat_cloud(self, id, duration, mode)


## 722 sig_f22·先敌开火：进入 STEALTH 瞬间全武器立即装填完毕（机炮/导弹/电磁炮 CD）
func _sig_f22_reload_all() -> void:
	if params == null:
		return
	if params.gun and ammo < params.gun.max_ammo:
		ammo = params.gun.max_ammo
		_gun_reload_timer = 0.0
	if params.missile and missiles_remaining < params.missile.max_count:
		missiles_remaining = params.missile.max_count
		_missile_reload_timer = 0.0
	var rg_state: Variant = equipment_state.get("railgun", null)
	if rg_state is Dictionary:
		rg_state["cooldown"] = 0.0
	EventLogger.log_event("SKILL", _log_name(), "先敌开火：隐身瞬间全武器装填完毕")


## 722 sig_f22：STEALTH 期间 +2；火控饱和：OVERLOAD 实际存续期间 +2。
func effective_max_locks() -> int:
	var bonus: int = 0
	if has_meta("upgrade_stacks"):
		var stacks := get_meta("upgrade_stacks") as Dictionary
		if status_stealth_active and int(stacks.get("sig_f22", 0)) > 0:
			bonus += 2
		if status_effects.has(StatusEffects.OVERLOAD) \
				and int(stacks.get(SkillHooks.SKILL_FIRE_CONTROL_SATURATION, 0)) > 0:
			bonus += SkillHooks.FIRE_CONTROL_SATURATION_LOCK_BONUS
	return maxi(max_simultaneous_locks + bonus, 1)


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
	if not can_accept_new_hit(kind if kind != "" else "missile"):
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
func take_bullet_damage(amount: float, attacker: Node = null) -> bool:
	if is_destroyed:
		return false
	if not can_accept_new_hit("gun"):
		return false
	if invulnerable:
		return false
	# Mother Goose 等挂点 BOSS：机炮也走 router（按 boss 中心传 hit_pos，弱点未暴露则被角度过滤）
	if has_meta(&"damage_router"):
		var router: Object = get_meta(&"damage_router")
		if router and is_instance_valid(router) and router.has_method(&"route_damage"):
			if attacker != null:
				set_meta("_pending_attacker", attacker)
			set_meta("_last_damage_kind", "gun")
			router.call(&"route_damage", amount, global_position)
			return true
	# 地面机炮火力警觉（spec aa-fire-awareness §3.1）：被地面/舰船机炮弹幕命中 = 已身处
	# 火力网（放在闪避判定之前——闪避掉的弹同样是"正被弹幕覆盖"信号）。
	# 只认地面/舰船源；空对空中弹是 BFM 层的事。
	if attacker != null and is_instance_valid(attacker) \
			and (attacker is GroundUnit or attacker is NavalUnit):
		if aa_fire_timer <= 0.0 and (team == 0 or selected):
			EventLogger.log_event("AA_FIRE", _log_name(),
				"hit by %s → egress boost %.1fs" % [attacker.name, AA_FIRE_REACT_S])
		aa_fire_timer = AA_FIRE_REACT_S
		aa_fire_source_pos = attacker.global_position
	# Adds 杂兵（Tu-160/AH-64/CH-47）按设计被击中无任何反应——
	# 不参与闪避也不触发桶滚动画，否则重型轰炸机会像战斗机一样在高空翻滚
	var is_adds: bool = has_meta("category") and get_meta("category") == "adds"
	var effective_dodge: float = bullet_dodge_chance
	if evasion_mode:
		effective_dodge += 0.20  # 规避模式加成（玩家手动开 / 长机传播给僚机 / AI 进入 EVADE 状态）
	if get_altitude_tier() == AltitudeTier.HIGH:
		effective_dodge += 0.20  # HIGH 高度加成
	# §C 玩家技能"低空机炮闪避"：LOW/GROUND 档位时加 bonus
	if is_player_squad() and low_alt_gun_dodge_bonus > 0.0:
		var t: int = get_altitude_tier()
		if t == AltitudeTier.LOW or t == AltitudeTier.GROUND:
			effective_dodge += low_alt_gun_dodge_bonus
	# 722 sig_typhoon·超巡爬升：统一 CLIMB/DIVE 动作中机炮闪避 +30%。
	if sig_typhoon_active and altitude_action != AltitudeAction.NONE:
		effective_dodge += 0.30
	# 对头机炮闪避（玩家技能）：仅 team==0 + 持有 SKILL_HEAD_ON_GUN_DODGE
	# 几何门槛 head_on_dot > 0.7（双方机头对冲 ≲ 53°）
	if is_player_squad() and head_on_gun_dodge_bonus > 0.0 and attacker is Aircraft:
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
	# 加力窗口（spec afterburner-mode）：唯一绕 cap 通道——6s 限时 + 30s 充能代价，
	# 换取窗口内机炮完全打不中（100%）。敌机永不置窗口标志，不影响敌方规避闪避。
	if afterburner_window_active:
		effective_dodge = 1.0
	if not is_adds and effective_dodge > 0.0 and randf() < effective_dodge:
		_trigger_evasion_roll()  # 闪避滚转动画
		return false  # 闪避成功，无视伤害，也不触发命中火星
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
	return true

## 护甲减伤（DOTA 式软上限）：dr = armor_eff / (armor_eff + ARMOR_K)
## penetration ∈ [0,1]：穿甲系数，导弹=0.5 抵消一半护甲，机炮=0 受全额护甲
## armor=0 → dr=0，完全兼容现有无护甲飞机
const ARMOR_K: float = 100.0
const MISSILE_ARMOR_PENETRATION: float = 0.5
func _apply_armor(amount: float, penetration: float) -> float:
	# 玩家技能"血怒护甲"：BLOODLUST 期间额外减伤（叠在护甲层之外，独立乘）
	if is_player_squad() and status_bloodlust_active and has_meta("upgrade_stacks"):
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
	# 722 sig_x90·鲸群：血量共享光环——1500m 内友军均摊承伤（relay meta 防递归/防二次均摊）
	if SkillHooks.sig_x90_active and is_player_squad() \
			and not bool(get_meta("_sig_share_relay", false)):
		amount = SkillHooks.whale_pod_share(self, amount)
	# §C 玩家技能"机炮发射时减伤"：在窗口期内乘伤害减免比例
	if is_player_squad() and gun_fire_dr_amount > 0.0 and _gun_fire_recently_until > EventLogger.get_game_time():
		amount *= maxf(1.0 - gun_fire_dr_amount, 0.0)
	# 座舱护甲（720 批）：地面/舰面火力（SAM/AA/CIWS）来源伤害减免
	if is_player_squad() and ground_damage_taken_mult < 1.0:
		var raw_ground_atk: Variant = get_meta("_pending_attacker") \
			if has_meta("_pending_attacker") else null
		var ground_atk: Node = CombatUnit.safe_attacker(raw_ground_atk)
		if ground_atk is GroundUnit or ground_atk is NavalUnit or ground_atk is MountTarget:
			amount *= ground_damage_taken_mult
	# 阵地转移（720 批）：撤离冲刺中受到伤害 -50%
	if is_player_squad() and command_sprint and evac_shift_active:
		amount *= 0.5
	# 保卫阵地（720 批）：防守圈内受到伤害 -30%
	if is_player_squad() and guard_zone_buff_active:
		amount *= 0.7
	# 猎手：仅突击命令存续期间减伤 30%，无计时器、无独立 CD。
	if is_player_squad() and hunter_assault_active:
		amount *= 0.7
	var old_hp := hp
	hp -= amount
	EventLogger.log_event("DAMAGE", _log_name(),
		"took %.0f damage (hp=%.0f→%.0f)" % [amount, old_hp, hp])
	if amount > 0.0 and is_player_squad():
		set_meta(&"hud_last_damage_at", EventLogger.get_game_time())
	# 受击钩子链（玩家系技能：受伤进嗜血 / 被导弹击中无敌 / 周围 JAM 等）
	# early-return：only Aircraft 玩家小队 + has upgrade_stacks → 不命中开销 ≈ 1 dict.has
	if hp > 0.0 and is_player_squad():
		# `_pending_attacker` meta 会一直留到 _record_kill_attribution 才清，
		# 期间攻击者可能已被击落 → 读出来的是野指针，dispatch_on_hit 的 attacker: Node
		# 实参类型检查会直接崩。归因失效只是"这次受击不记凶手"，可以接受。
		var raw_atk: Variant = get_meta("_pending_attacker") \
			if has_meta("_pending_attacker") else null
		var atk: Node = CombatUnit.safe_attacker(raw_atk)
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
	# 护卫反应：被护送对象挨打 → 护卫机转向攻击者（即使这一击致死也要先发出信号）
	if not escort_guards.is_empty():
		_alert_escort_guards()
	if hp <= 0.0:
		# 722 签名：致死拦截（钛浴缸 / 不被期待的计划；spec aircraft-signature-skills §3.2）
		if is_player_squad() and _try_sig_death_save(old_hp):
			return
		hp = 0.0
		_record_kill_attribution()
		_start_destroy()

## 722 批：致死拦截（spec aircraft-signature-skills §3.2）。命中任一 → true（拦截坠机）。
## 钛浴缸（A-10 sig_a10）：受击前 hp<30% 且 CD 就绪 → 保 1 HP + 1.5s 无敌，CD 60s 可反复。
## 不被期待的计划（A-12 sig_a12）：无血线前提、每机每局一次 → 回 30% HP + 2s 无敌。
## 判序：钛浴缸先（CD 好则先保 1，复活留底）。
## 无敌走 apply_status，但派生要等下帧 StatusEffects.update —— 同帧连续中弹会穿透，
## 故手动同帧置 invulnerable + _status_owns_invul（owner 归属状态系统，结束时它负责清）。
func _try_sig_death_save(pre_hit_hp: float) -> bool:
	if not has_meta("upgrade_stacks") or params == null:
		return false
	var ds_stacks: Dictionary = get_meta("upgrade_stacks")
	if int(ds_stacks.get("sig_a10", 0)) > 0 and _sig_a10_cheat_cd <= 0.0 \
			and pre_hit_hp < params.max_hp * 0.30:
		hp = 1.0
		_sig_a10_cheat_cd = 60.0
		apply_status(StatusEffects.INVINCIBLE, 1.5, "no_refresh")
		invulnerable = true
		_status_owns_invul = true
		EventLogger.log_event("SKILL", _log_name(), "钛浴缸：致死一击保 1 HP（CD 60s）")
		return true
	if int(ds_stacks.get("sig_a12", 0)) > 0 and not _sig_a12_revive_used:
		_sig_a12_revive_used = true
		hp = params.max_hp * 0.30
		apply_status(StatusEffects.INVINCIBLE, 2.0, "no_refresh")
		invulnerable = true
		_status_owns_invul = true
		EventLogger.log_event("SKILL", _log_name(), "不被期待的计划：击坠复活 30%% HP（每局一次）")
		return true
	return false

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
		if attacker is Aircraft:
			attacker.kill_tally += 1  # ACE 继任记账（spec ace-system §3）
		# ── 战况栏（kill feed）信号：呼号 + 武器种类 + 双方阵营，survivor_hud 订阅显示 ──
		var atk_call: String = attacker.callsign if ("callsign" in attacker and attacker.callsign != "") else String(attacker.name)
		var atk_team_i: int = attacker.team if ("team" in attacker) else -1
		EventLogger.kill_recorded.emit(atk_call, callsign, dk, atk_team_i, team,
			can_speak_on_radio())
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

## 通知护卫机扑向刚打了本机的人。攻击者从 _pending_attacker meta 取
## （take_damage / take_bullet_damage 在调 _apply_damage 前都已写入）。
## 用 TS_DIRECTIVE 下发：护卫是事件编成，不该被 ROE 察觉门挡住，也不该被自发评分抢回去。
func _alert_escort_guards() -> void:
	var atk: Variant = get_meta("_pending_attacker") if has_meta("_pending_attacker") else null
	if atk == null or not is_instance_valid(atk) or not (atk is Aircraft):
		return
	var target: Aircraft = atk
	if target.is_destroyed:
		return
	for g in escort_guards:
		if not is_instance_valid(g) or g.is_destroyed:
			continue
		if not CombatUnit.teams_hostile(g.team, target.team):
			continue
		var ai: AIController = g._get_ai_controller()
		if ai and ai.acquire_target(target, AIController.TargetSource.TS_DIRECTIVE, "escort_alert"):
			# acquire_target 只建立目标所有权，不切状态；护卫受警必须同拍脱离编队接战。
			g.clear_formation()
			g.ai_override_pursuit = true
			ai.enter_engage_state()

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
	# 合法死亡优先于主动机动；幂等清掉命中窗和表现偏移，不触发“完成机动”技能钩子。
	_active_special = ActiveSpecialManeuver.NONE
	_active_special_heading_offset = 0.0
	_active_special_roll_visual = 0.0
	_active_special_pitch_visual = 0.0
	# 清空全局玩家引用，防止 AircraftRenderer 后续帧把 freed 实例赋给类型化变量崩溃
	# （`var pref: Aircraft = player_ref` 在 player_ref 已 free 时抛 "previously freed"）
	if AircraftRenderer.safe_player_ref() == self:
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
	var base: float = (params.radar_range if params else 300.0) * category_radar_mult \
		+ ew_expert_radar_bonus_px   # 电子战专家（720 批 T4）：按策士轴技能数加距，cap 1km
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
	# 传感器幕只跳过本机 CPU 绘制；Snowblind 的 Polygon2D 子网格仍由 GPU 独立绘制。
	if sensor_hidden:
		return
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
	var draw_section_trace := PerfBuckets.detail_capture_enabled()
	var draw_section_t0: int = Time.get_ticks_usec() if draw_section_trace else 0
	if is_hovered:
		# 无主雷达锁定武器时不画主雷达锥；副槽仍由独立锁定锥表达。
		if params and params.has_lock_capable_weapon():
			AircraftRenderer.draw_radar_cone(self)
		AircraftRenderer.draw_aura_ranges(self)
	# 副导弹槽（仅玩家、装备副弹时画）
	#   - 锁定锥：hover-only（draw_secondary_lock_cone 自身判断 is_hovered）
	#   - 锁定指示括号：长期可见，提示"QMAAM 已就绪可以打"
	if AircraftRenderer.safe_player_ref() == self:
		AircraftRenderer.draw_secondary_lock_cone(self)
		AircraftRenderer.draw_secondary_lock_indicators(self)
	# 友方 hover 时显示参考机炮锥；敌方对玩家提交机炮攻击时持续显示锥（条件在 draw_gun_cone 内判）
	AircraftRenderer.draw_gun_cone(self)
	# drone（忠诚僚机）跳过预测线 / 锁定指示 / 目标括号 / 数据标签 — 纯 2D 极简视觉
	if not is_drone:
		AircraftRenderer.draw_target_line(self)
	AircraftRenderer.draw_esm_aura(self)
	AircraftRenderer.draw_cloud_state(self)
	AircraftRenderer.draw_railgun_telegraph(self)
	if draw_section_trace:
		PerfBuckets.tick("aircraft_draw.overlays", Time.get_ticks_usec() - draw_section_t0)
		draw_section_t0 = Time.get_ticks_usec()
	AircraftRenderer.draw_aircraft_icon(self)
	AircraftRenderer.draw_deadair_exposure(self)
	if draw_section_trace:
		PerfBuckets.tick("aircraft_draw.icon", Time.get_ticks_usec() - draw_section_t0)
		draw_section_t0 = Time.get_ticks_usec()
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
	if draw_section_trace:
		PerfBuckets.tick("aircraft_draw.effects", Time.get_ticks_usec() - draw_section_t0)
		draw_section_t0 = Time.get_ticks_usec()
	var compact_label := false
	if is_drone:
		# drone 用极简一行标签：DRONE + 速度（无 callsign / altitude / HDG / G）
		AircraftRenderer.draw_data_label_drone(self)
	else:
		compact_label = AircraftRenderer.should_draw_compact_label(self)
		if compact_label:
			AircraftRenderer.draw_data_label_compact(self)
		elif hide_data_label:
			AircraftRenderer.draw_data_label_minimal(self)
		else:
			AircraftRenderer.draw_data_label(self)
	if compact_label:
		AircraftRenderer.draw_reload_indicators(self)
	AircraftRenderer.draw_tactic_popup(self)
	if draw_section_trace:
		PerfBuckets.tick("aircraft_draw.labels", Time.get_ticks_usec() - draw_section_t0)
	# 飞机的 buff/debuff 由完整、精简和折叠数据标签统一以文本+百分比形式显示
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
func _update_cloud_state(delta: float, weather_override: Node = null) -> void:
	_cloud_state_accum += delta
	if _cloud_state_accum < 0.2:
		return
	_cloud_state_accum = 0.0
	var weather := weather_override if weather_override != null else get_tree().get_first_node_in_group("weather")
	if weather == null or not weather.has_method("sample_density"):
		cloud_state = 0
		cloud_density = 0.0
		return
	var visual_density: float = weather.sample_density(global_position)
	var combat_density: float = weather.sample_obscurant_density(global_position, altitude) \
		if weather.has_method("sample_obscurant_density") else \
		(visual_density if get_altitude_tier() == AltitudeTier.HIGH else 0.0)
	cloud_density = maxf(visual_density, combat_density)
	if combat_density > 0.0:
		# 普通云=HIGH；沙尘暴=LOW。二者统一为“云中”战斗状态。
		cloud_state = 2
		cloud_density = combat_density
	elif visual_density <= 0.0:
		cloud_state = 0
	else:
		cloud_state = 1
	# 云中超载每 0.2s 刷新一次短时状态；出云不主动清除，剩余时间自然衰减。
	# 这样不会误删规避/击杀等其它 OVERLOAD 来源，且持续时间与嗜血联动统一生效。
	if is_player_squad() and cloud_overload_active and cloud_state >= 1:
		apply_status(StatusEffects.OVERLOAD, StatusEffects.CLOUD_OVERLOAD_BASE_DURATION, "max")


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
	return _lock_immunity_timer > 0.0 or is_cloaked or sensor_hidden

## HUD 用：热诱弹冷却比例（委托 AircraftFlares）
func get_flare_cooldown_ratio() -> float:
	return AircraftFlares.cooldown_ratio(self)


func _update_visuals() -> void:
	rotation = heading + _active_special_heading_offset


## 敌方对玩家提交机炮攻击时累计计时；持续 ≥0.3s 显示机炮锥威胁提示。
## 条件中断立即归零，避免 weapon_mode GUN/MISSILE 抖动时锥反复闪烁。
func _update_gun_threat_indicator(delta: float) -> void:
	if team != TEAM_HOSTILE or is_destroyed or is_cloaked:
		_reset_gun_threat()
		return
	if not params or not params.gun:
		_reset_gun_threat()
		return
	# combat_target 跨帧缓存可能在目标销毁后短暂保留野指针；必须先以 Variant
	# 进入生命周期净化边界，不能直接做 `is` / `as`（会在守卫前硬报错）。
	var target_value: Variant = combat_target
	var threatened: Aircraft = AircraftRenderer.safe_aircraft_ref(target_value)
	if threatened == null or not is_instance_valid(threatened) or threatened.is_destroyed \
			or not threatened.is_player_squad() \
			or not AircraftWeapons.is_gun_tailed_by(self, threatened):
		_reset_gun_threat()
		return
	threatened.report_gun_tailed(self)
	# 机炮锥仍只围绕当前操控机显示；僚机只消费 GUN_TAILED 与爬升反制。
	var pref: Aircraft = AircraftRenderer.safe_player_ref()
	if pref == null or not is_instance_valid(pref) or threatened != pref:
		_reset_gun_threat()
		return
	_gun_threat_timer += delta
	# 开火中淡出（曳光弹本身就是提示），停火后慢淡回，让梭射间隙仍有预警
	if is_firing:
		_gun_threat_fade = maxf(0.0, _gun_threat_fade - delta / GUN_THREAT_FADE_OUT_TIME)
	else:
		_gun_threat_fade = minf(1.0, _gun_threat_fade + delta / GUN_THREAT_FADE_IN_TIME)


func _reset_gun_threat() -> void:
	_gun_threat_timer = 0.0
	_gun_threat_fade = 1.0


## 覆写 CombatUnit：飞机能否对玩家发射导弹（lock_armed 上升沿条件之一）
func _lock_line_can_engage_player() -> bool:
	if not has_missile_capability():
		return false
	var pref: Aircraft = AircraftRenderer.safe_player_ref()
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
