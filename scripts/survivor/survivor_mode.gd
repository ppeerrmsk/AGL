extends Node2D

const HackedAllyForceScript = preload("res://scripts/survivor/hacked_ally_force.gd")

## 生存模式主控制器
## 操控/镜头/武器/雷达 全部与沙盒模式一致
## 在此基础上叠加：敌机波次刷新、经验球、等级升级

# ── 共享模块 ──
var _map_features: MapFeatureRenderer
var _ugc_doc: MapDocument = null  ## UGC 试飞中的地图文档（null = 官方图）
var _camera_ctrl: CameraController
var _weather: WeatherSystem

# ── 场景/资源引用 ──
@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var _aircraft_scene: PackedScene
var _player_params_base: AircraftParams

# ── 刷怪系统（委托给 SurvivorSpawner）──
var _spawner: SurvivorSpawner

# ── 地面单位场景/参数（Debug 面板用）──
var _sam_scene: PackedScene
var _sam_params: Resource
var _aa_scene: PackedScene
var _aa_params: Resource

# ── 海上单位参数（Debug 面板用，船没有 .tscn，直接 FrigateShip.new()）──
var _ffg_params: Resource
var _ddg_params: Resource
var _cg_params: Resource
var _cv_params: Resource
var _ss_params: Resource

# ── 通用战区系统（所有 ZoneType 共用）──
var zone_manager: ZoneManager

# ── 操控状态 ──
var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

# 双击敌人 = 冲锋攻击（max speed + AB + 机炮优先 + 导弹通道仍允许）
const DOUBLE_CLICK_WINDOW := 0.3
var _last_left_click_time: float = -1000.0

# ── 生存模式状态 ──
var player_aircraft: Aircraft
var _player_profile_id: StringName = &""  ## 当前主角的 PlayableAircraft.id（用于专属技能筛选）
var _starting_profile_id: StringName = &""  ## 本局起始机型；战区武器倾向固定读取，不随进化改变
var _player_profile: PlayableAircraft = null  ## 当前主角档案引用（三轴里程碑覆写表 / 专属技能筛选）
var _wingman_formation_debug: bool = false  ## F11 切换：友方僚机编队调试覆盖层
## 当前玩家小队（spec squad-control-switching）：数字键 1-4 切换操控 / 击落接管 / 换帅监听。
## 仅有起始僚机的主角（如 F-14）会建立；单机主角为 null（无切换）。
var _squad: Squad = null
var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var is_game_over: bool = false
## 进化系统（垂直切片，spec ace-system §2.4）：战区结算后置旗，等其他暂停 UI 关完再开进化面板
var _evolution_ui: EvolutionUI = null
var _evolution_pending: bool = false
var is_paused_for_upgrade: bool = false
var upgrade_stacks: Dictionary = {}
## ── 720 批 T3：僚机阵亡事件 watcher + 奖励升级队列 ──
var _squad_watch_timer: float = 0.0        ## 0.5s 周期的阵亡检测/弹窗顺延计时
var _squad_known_alive: Array = []         ## 上周期存活成员快照（检测 alive→destroyed 沿）
var _pending_bonus_upgrades: int = 0       ## 待弹的奖励升级数（黑匣子回收/地勤优化）
var _dock_settlement_open: bool = false    ## 本次结算面板是否由停靠打开（地勤优化判起飞）

## ── 阶段制（2026-05-09）──
## 战区阶段时长（10 分钟，2026-06-28 从 8 分钟延长；后续模式重做时可能再调）。到点后关闭其他战区，玩家在打的可结算后进 BOSS。
## var 而非 const（career-shop §3.2）：生涯商店 op_time_30s 购入后 _ready 里 +30s；
## 顺带让 survivor_debug_zone 的 get() 读取真正可用（const 不在属性表里读到 null）
var WARZONE_PHASE_DURATION := 600.0
## 出界回血时间税：玩家点 SUPPLY 满血但 game_time 前进 30 秒，把 BOSS 拉近
const SUPPLY_TIME_COST := 30.0
## 战区阶段已结束（game_time 跨过 WARZONE_PHASE_DURATION 时置 true，仅触发一次）
var _warzone_phase_ended: bool = false

## §5 抽卡 pity 计数：{ Rarity → int }，本局生效
## SurvivorData.pick_3_upgrades 每次升级时读 + 写
var _pity_counter: Dictionary = {}
## 4 级金卡软 pity：只统计自然等级升级产生的普通三轴三卡；专属第四槽/奖励升级不读写。
var _classified_pity_misses: int = 0
## 状态词条终端债务：tag → 连续合格事件未出终端次数；出示（无论选不选）即清零。
var _terminal_offer_misses: Dictionary = {}

const OFFSCREEN_MARGIN := 500.0    ## 屏幕外判定余量（像素）

# ── 雷达锁定节流（每 RADAR_LOCK_INTERVAL 秒跑一次 O(N²) 循环）──
const RADAR_LOCK_INTERVAL := 0.2
## 雷达锁定子集轮转：每 tick 只扫 1/RADAR_LOCK_STRIDE 单位作为 shooter，
## 全覆盖周期 RADAR_LOCK_INTERVAL × RADAR_LOCK_STRIDE = 0.8s（2026-05-04 加入）。
## 每个 shooter 看到的 step_delta 仍然是"完整间隔"（× stride 抵消频率），锁定累积速率不变。
## 副作用：目标离开雷达锥后的衰减最多滞后 0.6s（旧 0.2s），实测无感知。
const RADAR_LOCK_STRIDE := 4
var _radar_lock_phase: int = 0  ## 当前轮到的 stride 索引（0..RADAR_LOCK_STRIDE-1）
var _radar_lock_accum: float = 0.0
var _all_combat_units_cache: Array[CombatUnit] = []   ## _update_aircraft_list 填充，_update_radar_locks 复用

# ── RTS 指挥（命令 + 自动交战）—— 逻辑全在 SquadCommandController，本文件只接线 ──
# 数值见 resources/rts_command.tres；设计见 docs/specs/systems/rts-command.md
const RTS_COMMAND_PARAMS := preload("res://resources/rts_command.tres")
const COMMAND_WHEEL_PARAMS := preload("res://resources/command_wheel.tres")
var _squad_cmd: SquadCommandController = null
var _command_wheel: CommandWheel = null
var _pending_click_double := false

# ── HUD / UI ──
var hud: SurvivorHUD
var upgrade_ui: SurvivorUpgradeUI
## 机体专属第四槽：每个进化节点在一局中只结算一次机会。
enum SignatureOfferState { UNSEEN, OFFERED, RESOLVED }
var _signature_offer_state: Dictionary = {}  ## node_id(StringName) → SignatureOfferState
var _signature_offered_node: StringName = &""  ## 当前弹窗快照，选任意卡都结算它
## 加力模式充能资源（spec afterburner-mode，充能制）：小队级单实例，开局满能量。
## _physics_process 驱动（升级暂停/游戏结束自然冻结）；E 键与 HUD 按钮走 toggle 开关。
var afterburner_charge := AfterburnerCharge.new()
var _tutorial: SurvivorTutorial  ## 首次进入生存模式的浮现式教程
var _wingman_tutorial: SurvivorWingmanTutorial  ## 首次获得僚机后的数字键切控提示

# ── 大地图边界 / 战术地图（P1）──
var _map_boundary: MapBoundary
var _dock_points: Array[DockPoint] = []   ## 停靠点（固定机场 + 航母甲板，spec zone-reward-docking）
## 机场授权 SAM 的一次性承诺账本：生成即记，战损不重生（spec airfield-sam-network）。
var _airfield_sam_committed: Dictionary = {}  ## zone_id(StringName) → true

## ── ALLY 第三方事件调度（spec global-awareness-roe §2.6）──
var _awacs_spawn_timer: float = 120.0     ## _ready 里 roll 90~150
var _awacs_was_active: bool = false

## 王牌支援中队调度（spec events/ace-support-squadron §2.4）
## 王牌中队调度（spec ace-squadron-tier §2.9）：首触发时间按各队时段档进池
## （AceSquadProfiles.pool_at），不再有统一的 FIRST_S 门
const ACE_SUPPORT_COOLDOWN_S := 150.0  ## 前支结束（全灭/撤离）后的再触发间隔
const ACE_SUPPORT_CUTOFF_S := 540.0    ## 最后 1 分钟不新刷（避免刚进场撞阶段闸）
var _ace_support_cd: float = 0.0
var _ace_squads_used: Dictionary = {}      ## 本局已出场过的队（同局不重复同队）
var _ace_run_order: Array = []             ## 本局无放回随机顺序（开局生成）
static var _ace_previous_first: String = "" ## session 内避免连续两局首队相同
var _orion_spawned := false                ## 宿敌 ORION：独立轨道，每局一次（tier §3.8）
var _friendly_carrier: NavalUnit = null   ## 在场的友军航母（奖励召唤，同时最多一艘）
var _friendly_asset_aggro := FriendlyAssetAggro.new() ## 玩家把战斗带近机场/航母时的有限分流
var _boundary_ui: BoundaryUI
var _pause_menu: PauseMenu        ## 暂停菜单（spec pause-menu，ESC 打开）
var _tactical_map: TacticalMap
var _zone_data: ZoneData
var _zone_arrow: ZoneArrow
var _zone_hint: ZoneHint
var _pending_basemap_error_reason: String = ""
var _radio: RadioChatter          ## 无线电通讯（spec radio-chatter）
var _zone_mission: ZoneMission
var _adbs: AdbsManager
var _event_director: EventDirector
var _hacked_ally_force = HackedAllyForceScript.new()
## BOSS 阶段状态（P4）
var _boss_unlock_announced: bool = false  ## 已提示过"BOSS 出现"
var _boss_spawned: bool = false            ## BOSS 已激活进入战斗
var _map_id: String = "default"            ## 当前地图 id（BOSS 池 lookup 用）
var _is_victory: bool = false              ## 已胜利，阻止重复触发
## F6 Debug 面板指定的关底 BOSS id（空 = 按地图池随机）。仅 debug_skip_to_boss 写入
var debug_boss_id_override: String = ""

# ── Boss Debug 模式 ──
## 进入路径：survivor_map_select 按 B → boss_debug_select 选 boss → set_meta → 此处读取
## 与正常生存模式的差异：跳过地图渲染（空白）、跳过 BuildingRenderer、_ready 末尾 _setup_boss_debug_scenario()
## 自动跳到 15 级 + 主题化随机 build + 立即触发 BossEncounterEvent
var _boss_debug_mode: bool = false
var _boss_debug_id: String = ""
var _boss_debug_theme: String = ""              ## 当前主题名（HUD 显示用，备用）
var _boss_debug_picks: Array[Dictionary] = []    ## 当前 build 的 14 张技能
var _player_profile_path: String = ""            ## boss debug F8 重启需要原档案路径

# ── Bench 模式（headless 性能压测）──
## 入口：BenchRunner autoload 解析 --bench=<scenario> CLI → set_meta → 切到 survivor_mode.tscn
## 与 boss_debug 类似（跳 UI/教程/战区），区别：
##   - 玩家挂 AIController 自动接管交战
##   - 升级自动选随机（无视 max_stacks/requires/exclusive，无限堆叠 → 自我放大压力）
##   - 跑 _bench_duration 秒后回调 BenchRunner.bench_finish() 写 PerfBuckets dump 并 quit
var _bench_mode: bool = false
var _bench_scenario: String = ""
var _bench_duration: float = 30.0
var _bench_elapsed: float = 0.0
var _bench_finished: bool = false
var _bench_wall_started_msec: int = 0
var _bench_last_heartbeat_msec: int = 0
var _bench_pause_started_msec: int = 0
var _growth_bench: EvolutionGrowthBenchmark = null
var _growth_bench_config_ok: bool = false
## demo 模式：复用 bench 的"玩家挂AI+force-spawn敌机+相机跟随"，但渲染运行、不退出、
## 持续补充敌人——供肉眼观察物理/表现/小队战术（2026-06-07）
var _bench_demo: bool = false
var _bench_demo_topup_timer: float = 0.0

func _exit_tree() -> void:
	_hacked_ally_force.shutdown()
	_friendly_asset_aggro.reset()
	# 王牌事件是 RefCounted，HUD 静态强引用不会随 EventDirector 节点自动释放。
	AceReinforcementEvent.reset_runtime_state()
	# UGC 试飞收尾：清除静态注入（MapGeography/建筑缓存），防污染下一局官方图
	if _ugc_doc != null:
		UgcLoader.clear()
		_ugc_doc = null
	# 战场引力上下文是 static（跨场景存活）→ 退局必清，防残留污染下一局/沙盒
	ObjectiveContext.reset()


func _ready() -> void:
	# 确保 SurvivorMode 在所有子节点（含 AI 控制器）之前执行
	# 这样 _f47_assign_roles 设置的 boss_attacker 等标志在 AI 运行时已经生效
	process_priority = -10
	process_physics_priority = -10

	# 新局入口再兜底一次：保证 HUD/Tab 不会读取上局未正常终态的王牌事件。
	AceReinforcementEvent.reset_runtime_state()

	# 新一局开始：清空上一局的战报累计统计（击坠/命中/脱靶），避免跨局污染 F9 战报汇总
	EventLogger.reset_stats()

	# 722 签名技能的队级账本位是 static（跨场景实例存活）→ 新局必须显式清零，
	# 否则上一局拿过 X-13/FCAS/F-35/X-90 的开关会残留到这一局（本局账本为空却仍生效）。
	# 正常运行期由 _refresh_squad_effective_stacks 按 upgrade_stacks 同步。
	StatusEffects.sig_x13_active = false

	# 战场引力上下文（spec battlefield-gravity）：新局清零后启用（仅生存模式；沙盒恒 disabled）。
	# protectee 由 _set_player_aircraft chokepoint 写入；objective 由 _update_objective_context 低频填充。
	ObjectiveContext.reset()
	ObjectiveContext.enabled = true
	SkillHooks.sig_fcas_active = false
	SkillHooks.sig_f35_active = false
	SkillHooks.sig_x90_active = false
	SkillHooks.hush_active = false
	SkillHooks.cloud_relaying = false

	# Boss Debug meta 必须在所有渲染器/边界初始化之前读取（决定后续是否跳过 MapFeatureRenderer）
	if get_tree().has_meta("boss_debug_mode"):
		_boss_debug_mode = bool(get_tree().get_meta("boss_debug_mode"))
		get_tree().remove_meta("boss_debug_mode")
	if get_tree().has_meta("boss_debug_id"):
		_boss_debug_id = String(get_tree().get_meta("boss_debug_id"))
		get_tree().remove_meta("boss_debug_id")

	# Bench 模式 meta（BenchRunner 在 autoload _ready 写入；这里读完即清，防止重启场景时残留）
	if get_tree().has_meta("bench_mode"):
		_bench_mode = bool(get_tree().get_meta("bench_mode"))
		get_tree().remove_meta("bench_mode")
	if get_tree().has_meta("bench_scenario"):
		_bench_scenario = String(get_tree().get_meta("bench_scenario"))
		get_tree().remove_meta("bench_scenario")
	if get_tree().has_meta("bench_duration"):
		_bench_duration = float(get_tree().get_meta("bench_duration"))
		get_tree().remove_meta("bench_duration")
	if get_tree().has_meta("bench_demo"):
		_bench_demo = bool(get_tree().get_meta("bench_demo"))
		get_tree().remove_meta("bench_demo")
	if _bench_scenario == "evolution_growth":
		_growth_bench = EvolutionGrowthBenchmark.new()
		_growth_bench_config_ok = _growth_bench.configure_from_environment(_bench_duration)

	# 生涯档案（spec career-archive）：正式局开局计数 + 成就解锁 toast 订阅。
	# bench/boss debug 不入档（入档铁律 §3.5）；订阅无守卫——非正式局根本不会有解锁事件
	if archive_enabled():
		CareerArchive.record_run_started()
	if not CareerArchive.achievement_unlocked.is_connected(_on_achievement_unlocked):
		CareerArchive.achievement_unlocked.connect(_on_achievement_unlocked)

	# 生涯商店 op_time_30s（spec career-shop §3.2）：正式局购入后战区阶段 +30s。
	# bench/boss debug 不加成，时长恒 600s 保回归确定性
	if archive_enabled() and MetaShop.is_owned(MetaShop.ITEM_OP_TIME):
		WARZONE_PHASE_DURATION += MetaShop.OP_TIME_BONUS_S

	# UGC 试飞 meta（地图编辑器写入）：必须在渲染器/边界初始化之前注入地理
	if get_tree().has_meta("ugc_map_path"):
		var ugc_path := String(get_tree().get_meta("ugc_map_path"))
		get_tree().remove_meta("ugc_map_path")
		_ugc_doc = UgcLoader.load_map(ugc_path)
		if _ugc_doc != null:
			UgcLoader.apply_geography(_ugc_doc)
			UgcLoader.apply_buildings(_ugc_doc)
			# 同步跑完建筑分帧预热（一次性 ~10-30ms），否则 BuildingRenderer.setup
			# 会因 cache 未就绪回退到官方 JSON 同步加载
			while not BuildingRenderer.cache_step(200):
				pass
			print("[SurvivorMode] UGC 地图已注入: %s" % ugc_path)
		else:
			push_warning("[SurvivorMode] UGC 地图加载失败，回退官方图: %s" % ugc_path)

	# Boss Debug 模式：把空白背景调到柔和深色（默认黑底太刺眼），与海岸线地图颜调一致
	if _boss_debug_mode:
		RenderingServer.set_default_clear_color(Color(0.10, 0.13, 0.16))

	# 海岸线地图：两首战斗泛用 BGM 轮播（播完自动切下一首，周而复始）
	# BOSS 登场时 crossfade 到 boss 曲，会自动退出 playlist 模式
	AudioManager.play_music_playlist(["battle_coast", "battle_coast_2"], 2.0, 2.0)

	# 海岸线大地图：用固定几何数据替代原 TerrainRenderer 的噪声
	# Boss Debug / Bench 模式跳过：boss_debug 是空白地图省 shader+几何；bench 是 headless 不渲染
	if not _boss_debug_mode and not _bench_mode:
		_map_features = MapFeatureRenderer.new()
		_map_features.show_behind_parent = true
		_map_features.ugc_vector_only = _ugc_doc != null  # UGC 图跳过官方底图/手画层
		_map_features.basemap_load_failed.connect(_on_basemap_load_failed)
		if _ugc_doc != null:
			_map_features.ugc_overlay_layers = UgcLoader.overlay_layers_from(_ugc_doc)
		add_child(_map_features)
		move_child(_map_features, 0)
		# _map_features.setup() 会在 _map_boundary 创建后调用（见下方）

	# 天气系统（高空云层，绘制在地形之上、单位之下）
	_weather = WeatherSystem.new()
	_weather.show_behind_parent = true
	add_child(_weather)
	_weather.setup(camera)
	_weather.add_to_group("weather")
	move_child(_weather, 1)
	if _ugc_doc != null:
		UgcLoader.apply_to_weather(_weather, _ugc_doc)  # 覆盖 seed/风/coverage + mask（setup 之后）

	# 横浜高建筑伪 3D 渲染（独立模块；删除以下 4 行 + building_renderer.gd 即可完整撤回）
	# Boss Debug / Bench 模式跳过
	if not _boss_debug_mode and not _bench_mode:
		var buildings := BuildingRenderer.new()
		buildings.show_behind_parent = true
		add_child(buildings)
		buildings.setup(camera)

	# 相机控制器
	_camera_ctrl = CameraController.new()
	add_child(_camera_ctrl)
	_camera_ctrl.setup(camera)
	# 表演导演接管镜头电影层（zoom 系数 / offset / shake）。退出时 clear_all 会 unbind
	Presentation.clear_all()
	Presentation.bind_camera(_camera_ctrl)

	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_sam_scene = preload("res://scenes/sam_unit.tscn")
	_sam_params = preload("res://resources/sam_params.tres")
	_aa_scene = preload("res://scenes/aa_gun_unit.tscn")
	_aa_params = preload("res://resources/aa_gun_params.tres")
	_ffg_params = preload("res://resources/naval/frigate_ffg.tres")
	_ddg_params = preload("res://resources/naval/destroyer_ddg.tres")
	_cg_params = preload("res://resources/naval/cruiser_cg.tres")
	_cv_params = preload("res://resources/naval/carrier_cv.tres")
	_ss_params = preload("res://resources/naval/submarine_ss.tres")

	# 读取选择的机型档案（PlayableAircraft），缺省用 F-15（起手基底，spec aircraft-evolution §2.6）
	var profile_path: String = "res://resources/playable_f15.tres"
	if get_tree().has_meta("survivor_aircraft_resource"):
		profile_path = get_tree().get_meta("survivor_aircraft_resource")
		get_tree().remove_meta("survivor_aircraft_resource")
	# weapon_demo（spec weapon-employment-doctrine 阶段4 观察场）：强制 X-02 满装备档案
	# （基础档案自带 x02_railgun + 导弹 + 机炮）——验收武器竞选/LINE_UP/距离带切换
	if _bench_scenario == "weapon_demo":
		profile_path = "res://resources/playable_x02.tres"
	elif _bench_scenario == "evolution_growth" and _growth_bench_config_ok:
		profile_path = _growth_bench.profile_path()
	_player_profile_path = profile_path  # 保存供 boss debug F8 重启使用
	var profile: PlayableAircraft = load(profile_path)
	if profile == null or profile.base_params == null:
		push_error("survivor_mode: 无效的 PlayableAircraft：%s" % profile_path)
		return
	# demo 模式：强制 4 架僚机，方便观察编队跟随/归队（默认机型 wingman_count 多为 0）
	if _bench_demo and profile.wingman_count < 4:
		profile = profile.duplicate()
		profile.wingman_count = 4
	# reversal 模式：玩家方为 4 机编队（长机 + 3 僚机）对抗敌方编队
	elif _bench_scenario == "reversal":
		profile = profile.duplicate()
		profile.wingman_count = 3
	elif _bench_scenario == "enemy_pool_stress":
		profile = profile.duplicate()
		profile.wingman_count = 8
	elif _bench_scenario == "evolution_growth" and _growth_bench_config_ok:
		profile = _growth_bench.apply_squad_size(profile)
	_player_params_base = profile.base_params
	_player_profile_id = profile.id  # 用于专属技能筛选
	if _starting_profile_id == &"":
		_starting_profile_id = profile.id
	_player_profile = profile  # 保留档案引用（自然成长曲线 / 后续配件系统用）
	# 图鉴记账（用户规则：**获得即记录**，开局拿到起手机这一刻就算"拥有过"，不等首次结算）
	var _start_node: StringName = EvolutionSystem.node_id_for_profile(profile.id)
	if _start_node != &"" and archive_enabled():
		AircraftCodex.mark_discovered(_start_node)

	# 读取选择的地图（占位：当前仅 default 一张实装，其它为预留位）
	# 后续在此根据 map_id 切换噪声 seed/frequency/地形配色
	if get_tree().has_meta("survivor_map_id"):
		_map_id = String(get_tree().get_meta("survivor_map_id"))
		get_tree().remove_meta("survivor_map_id")

	# 友方子弹命中判定增强（生存模式全局，不依赖具体机型）
	bullet_manager.friendly_hit_radius = 20.0   # 命中半径 12→20px
	bullet_manager.friendly_dmg_full_ratio = 0.5  # 满伤害区间 30%→50%
	bullet_manager.friendly_dmg_min_mult = 0.4    # 最远衰减 20%→40%
	bullet_manager.flat_altitude_mode = true       # 扁平高度：无高度容差限制
	bullet_manager.missile_manager = missile_manager  # CIWS 子弹需要碰撞导弹

	# 生成玩家飞机
	player_aircraft = _aircraft_scene.instantiate()
	player_aircraft.callsign = "Ultra"  # 生存模式固定代号
	CallsignDB.reserve("Ultra")
	player_aircraft.params = _player_params_base.duplicate(true)  # 深拷贝，升级修改不影响原资源
	# 手动 duplicate 外部子资源，避免多实例共享同一 Resource
	SurvivorPlayableSetup.deep_dup_weapons(player_aircraft.params)
	# 应用机型档案的全部生存模式强化（数据驱动，逻辑见 survivor_playable_setup.gd）
	SurvivorPlayableSetup.apply(player_aircraft, profile)

	# 通用主角实例配置（与机型无关）
	player_aircraft.hide_data_label = true          # HUD 替代显示
	player_aircraft.flat_altitude = true            # 三档高度模式
	player_aircraft.use_tactical_preference = true  # 启用战术偏好面板
	# 机炮瞄准误差（此前由 use_tactical_preference 兼任，2026-07-22 拆开）。
	# 玩家侧行为逐字节不变；拆开是为了让王牌中队也能吃到误差（wraith spec §2.4）
	player_aircraft.gun_aim_error_enabled = true
	# P1：启用新版 TacticalPlanner（仅玩家），出问题可注释这行回退
	player_aircraft.use_tactical_planner = true
	# 开局即处于最高高度档（起手不爬升）；实际 altitude / 全速在 add_child 之后设（_ready 会重置）
	player_aircraft.set_target_tier(Aircraft.AltitudeTier.HIGH)
	player_aircraft.team = 0
	# RTS 指挥控制器（命令 + 自动交战的单一所有者；本文件只转发输入）
	_squad_cmd = SquadCommandController.new()
	_squad_cmd.name = "SquadCommandController"
	add_child(_squad_cmd)
	_squad_cmd.setup(self, RTS_COMMAND_PARAMS)
	_squad_cmd.wheel_params = COMMAND_WHEEL_PARAMS
	# 命令轮盘（按住左键拖拽的手势层，spec command-wheel）
	_command_wheel = CommandWheel.new()
	_command_wheel.name = "CommandWheel"
	add_child(_command_wheel)
	_command_wheel.setup(self, COMMAND_WHEEL_PARAMS)
	_command_wheel.command_selected.connect(_on_wheel_command)
	player_aircraft.position = MapBoundary.get_player_start()
	# 相机初始对准玩家起始点 + 启用跟随
	camera.global_position = player_aircraft.position
	_camera_ctrl.set_follow_target(player_aircraft)
	_camera_ctrl.follow_enabled = true
	player_aircraft.bullet_manager = bullet_manager
	player_aircraft.missile_manager = missile_manager
	player_aircraft.selected = true
	# 机型档案 stamp（skills-720 §1.2 品类身份查询用；进化换型时同步重打）
	player_aircraft.set_meta("profile_id", profile.id)
	# 生效技能子集 meta（skill_hooks / aircraft_flares / bullet_manager 读它判触发技能）
	# 由 _refresh_squad_effective_stacks() 维护：获得升级/切控/进化/入队时重建。
	# 王牌技只在操控机、品类技只落身份匹配机——不再把整本队级账本共享引用给单机。
	player_aircraft.set_meta("upgrade_stacks", {})
	add_child(player_aircraft)
	# 起手直接落在最高高度 + 全速巡航（避免开局爬升/巡航速度的慢启动）。
	# 必须在 add_child 之后：Aircraft._ready() 会把 altitude 重置为 5000、target_speed_kmh 重置为 cruise。
	player_aircraft.altitude = Aircraft.TIER_ALTITUDE[Aircraft.AltitudeTier.HIGH]
	player_aircraft.target_altitude = player_aircraft.altitude
	var _start_spd_kmh: float = AircraftPhysics.effective_max_speed_kmh(player_aircraft)
	player_aircraft.target_speed_kmh = _start_spd_kmh
	player_aircraft.speed = _start_spd_kmh / 3.6
	AircraftRenderer.player_ref = player_aircraft
	# 引擎环境音：只给玩家一个循环源，按缩放+视野动态调音量
	AudioManager.start_player_engine(player_aircraft)
	selected_aircraft.append(player_aircraft)

	# 生存模式状态
	survivor_player = SurvivorPlayer.new()
	survivor_player.aircraft = player_aircraft
	# 三轴里程碑与技能同样按"跟玩家不跟机体"下发全队：注入队员提供器后，
	# add_axis_point / add_milestone_bonus 的全部调用点自动覆盖僚机，无需逐处补
	survivor_player.milestone_targets_provider = _squad_members_alive
	survivor_player.leveled_up.connect(_on_player_leveled_up)
	add_child(survivor_player)

	# 刷怪系统（委托给 SurvivorSpawner）
	_spawner = SurvivorSpawner.new()
	add_child(_spawner)
	_spawner.setup(self, player_aircraft, survivor_player, bullet_manager, missile_manager)

	# 起始僚机（小队主控）：仅当档案声明 wingman_count > 0 时生成
	# 必须在 _spawner 初始化之后，因为 _spawn_starting_wingmen 会往 _spawner.get_squads() 追加队伍
	if profile.wingman_count > 0:
		_spawn_starting_wingmen(profile)

	# HUD
	hud = SurvivorHUD.new()
	hud.survivor_player = survivor_player
	hud.game_scene = self
	hud.afterburner_charge = afterburner_charge
	# 720 批："适应"击杀回能经静态引用触达队级充能（场景重建时覆盖旧引用）
	SkillHooks.afterburner = afterburner_charge
	add_child(hud)

	# 升级UI
	upgrade_ui = SurvivorUpgradeUI.new()
	upgrade_ui.upgrade_selected.connect(_on_upgrade_selected)
	add_child(upgrade_ui)

	# Debug 技能面板 (F4)
	var debug_skills := SurvivorDebugSkills.new()
	debug_skills.game_scene = self
	debug_skills.survivor_player = survivor_player
	add_child(debug_skills)

	# Debug 刷怪面板 (F5) — 不暂停游戏，可即时测试
	var debug_spawn := SurvivorDebugSpawn.new()
	debug_spawn.game_scene = self
	add_child(debug_spawn)

	# 通用战区系统 + F6 Debug 面板
	zone_manager = ZoneManager.new()
	zone_manager.name = "ZoneManager"
	add_child(zone_manager)
	zone_manager.setup(self, player_aircraft)

	var debug_zone := SurvivorDebugZone.new()
	debug_zone.game_scene = self
	# 新 F6 面板直接从 game_scene 里读 _zone_data / _zone_mission，不再需要 zone_manager
	add_child(debug_zone)

	# 王牌中队固定呼号永久保留（spec ace-squadron-tier §2.7：杂鱼抽不到、死亡不回池）
	AceSquadProfiles.reserve_callsigns()
	if not _boss_debug_mode and not _bench_mode:
		_prepare_ace_run_order()

	# ── 大地图边界系统 + 撤退菜单（P1）──
	_map_boundary = MapBoundary.new()
	_map_boundary.player = player_aircraft
	add_child(_map_boundary)
	# 相机钳制：比游戏边界稍大（CAMERA_MARGIN_PX），允许玩家看到边界外少许空域
	_camera_ctrl.set_world_bounds(_map_boundary.get_camera_bounds())
	# 地图特征绘制现在有了世界矩形（Boss Debug 模式 _map_features 为 null，跳过）
	if _map_features:
		_map_features.setup(camera, _map_boundary.get_world_rect())

	_boundary_ui = BoundaryUI.new()
	add_child(_boundary_ui)
	_map_boundary.approach_warning.connect(_boundary_ui.on_approach)
	_map_boundary.boundary_crossed.connect(_boundary_ui.on_crossed)
	_boundary_ui.retreat_confirmed.connect(_on_retreat_confirmed)
	_boundary_ui.supply_confirmed.connect(_on_supply_confirmed)
	_boundary_ui.cancelled.connect(_on_retreat_cancelled)

	# ── 暂停菜单（spec pause-menu）：ESC 改为"冻结 + 确认页"，不再一键丢整局 ──
	# bench/headless 无人按 ESC，省一个 CanvasLayer
	if not _bench_mode:
		_pause_menu = PauseMenu.new()
		add_child(_pause_menu)
		_pause_menu.quit_to_menu.connect(_on_pause_quit_to_menu)

	# ── 无线电通讯（spec radio-chatter）──
	# 刻意建在战区 if 之外：boss_debug 模式就是用来看 BOSS 登场台词的，不能被跳过。
	_radio = RadioChatter.new()
	add_child(_radio)
	# 演出的 radio 通道走它渲染（编排权归演出、渲染权归无线电，spec ui-transition §3.5）
	Presentation.bind_radio(_radio)
	EventLogger.kill_recorded.connect(_on_radio_kill_recorded)
	EventLogger.evasion_started.connect(_on_radio_evasion_started)
	EventLogger.afterburner_engaged.connect(_on_radio_afterburner_engaged)
	EventLogger.wingman_joined.connect(_on_radio_wingman_joined)

	# ── 战术地图 + 战区系统（P2）──
	# Boss Debug / Bench 模式跳过：bench 不要战区任务/ADBS 干扰压力测试样本
	if not _boss_debug_mode and not _bench_mode:
		# 构造时注入奖励上下文：开局 A/B 要保底各出一件武器与一项可用的次世代技能，
		# 因此首 roll 也必须经过机型 / 学说 / 已持有装备过滤。
		_zone_data = ZoneData.new(_build_reward_roll_context)
		# BoundaryUI 需要 _zone_data 来检测 BOSS 阶段（切换警告文案 + 补给阻断由 _on_supply_confirmed 做）
		if _boundary_ui:
			_boundary_ui.zones = _zone_data

		_tactical_map = TacticalMap.new()
		add_child(_tactical_map)
		_tactical_map.setup(_map_boundary.get_world_rect(), player_aircraft, _zone_data, self)
		_tactical_map.zone_selected.connect(_on_zone_selected)
		_tactical_map.nav_point_selected.connect(_on_nav_point_selected)
		_tactical_map.nav_cleared.connect(_on_nav_cleared)

		# ── 机场解放战区（spec airfield-liberation-zones）──
		# 三座机场开局是敌占战区（ZoneData 里 AF_* 条目），补给点 + 友军防空伞
		# 都在解放时才由 _liberate_airfield 生成；开局不再造 active dock / 全场 ALLY 驻军。
		# ALLY 事件首触发窗口
		_awacs_spawn_timer = randf_range(90.0, 150.0)

		_zone_arrow = ZoneArrow.new()
		add_child(_zone_arrow)
		_zone_arrow.setup(player_aircraft, camera, _zone_data)

		_zone_hint = ZoneHint.new()
		add_child(_zone_hint)
		_zone_hint.show_persistent(tr("ZONE_HINT_NEW_OPENED"))
		if not _pending_basemap_error_reason.is_empty():
			_show_basemap_error(_pending_basemap_error_reason)

		_zone_mission = ZoneMission.new()
		add_child(_zone_mission)
		_zone_mission.setup(self, _zone_data, player_aircraft,
			_sam_scene, _sam_params, _aa_scene, _aa_params,
			bullet_manager, missile_manager, _spawner)
		_zone_mission.mission_triggered.connect(_on_zone_mission_triggered)
		_zone_mission.mission_completed.connect(_on_zone_mission_completed)
		# 回注给 spawner：旅途刷怪需查询"玩家当前是否在战区任务里"
		_spawner.set_zone_mission(_zone_mission)

		# ── ADBS 随机事件系统（P4）──
		_adbs = AdbsManager.new()
		add_child(_adbs)
		_adbs.setup(self, _spawner, player_aircraft, _zone_hint)
		_tactical_map.set_adbs(_adbs)

	# ── 事件系统（GameEvent / AIDirective 调度器）──
	# 当前承载 BOSS 战剧本（PRE_STAGE → ENGAGED → VICTORY）
	# 后续要做"剧情演出"等新事件直接 EventDirector.start(MyEvent.new(...))
	_event_director = EventDirector.new()
	_event_director.name = "EventDirector"
	_event_director.mode = self
	_event_director.player = player_aircraft
	_event_director.spawner = _spawner
	add_child(_event_director)

	# ── 首次进入生存模式：浮现式教程 ──
	# Boss Debug / Bench 模式跳过教程（前者来测 boss，后者是 headless 没人看）
	if not _boss_debug_mode and not _bench_mode and SurvivorTutorial.should_show():
		_start_first_run_tutorial()
	_maybe_start_wingman_switch_tutorial()

	# ── Boss Debug 场景化设置（所有正常 setup 完成后） ──
	# 跳到 15 级 + 主题化随机 build + 立即启动 BossEncounterEvent
	if _boss_debug_mode:
		call_deferred("_setup_boss_debug_scenario")

	# ── Bench 场景化设置（headless 性能压测）──
	# 玩家挂 AIController + boost 到 15 级（升级路径走 _on_player_leveled_up bench 分支）
	# + 立即批量 spawn 敌机 + 启动 duration 倒计时
	if _bench_mode:
		call_deferred("_setup_bench_scenario")

## 正式底图失败时保留旧矢量地图保证战局可继续，但必须把降级状态明确展示给玩家。
## 理论上信号在首帧 _draw 才到；pending 分支守住未来渲染时序变化导致 ZoneHint 尚未创建的情况。
func _on_basemap_load_failed(reason_key: String) -> void:
	_pending_basemap_error_reason = reason_key
	if _zone_hint != null:
		_show_basemap_error(reason_key)

func _show_basemap_error(reason_key: String) -> void:
	if _zone_hint == null:
		return
	_zone_hint.show_error_temp(
		tr("MAP_BASEMAP_ERROR_FMT") % tr(reason_key),
		10.0)
	_pending_basemap_error_reason = ""

## ════════════════════════════════════════════════
##  Boss Debug 场景化设置
## ════════════════════════════════════════════════
##
## 在 _ready 末尾 deferred 调用：
##   1. 玩家直接到 15 级（不触发 leveled_up 信号 → 无升级 UI 弹窗）
##   2. 按主题随机 roll 14 张升级（level 1→15 的总升级次数）
##   3. 批量 apply（走 SurvivorPlayer.apply_upgrade + 维护 upgrade_stacks）
##   4. 启动 BossEncounterEvent，强制使用 _boss_debug_id 而非地图池随机
const BOSS_DEBUG_LEVEL := 15
const BOSS_DEBUG_BOSS_DISTANCE_PX := 4500.0  ## 玩家正前方多远生成 boss anchor

func _setup_boss_debug_scenario() -> void:
	if not _boss_debug_mode:
		return
	if not survivor_player or not is_instance_valid(player_aircraft):
		return

	# 1. 直接拉到 15 级（绕过 add_xp 动画 + leveled_up 信号 → 不触发升级 UI 暂停）
	survivor_player.level = BOSS_DEBUG_LEVEL
	survivor_player.xp = 0
	survivor_player.xp_to_next = SurvivorData.xp_for_level(BOSS_DEBUG_LEVEL + 1)
	survivor_player._awaiting_level_up = false
	# 自然成长已退役——跳级不再补 HP/导弹（等级纯门槛）。
	# boss debug 的三轴点数补发（floor(15/3)=5 点随机/主题分配）随属性门槛豁免一并接（gates §3.4）。

	# 2. 主题化 roll
	var roll: Dictionary = BossDebugBuilds.roll_build(
		BOSS_DEBUG_LEVEL, _player_profile_id, player_aircraft.params)
	_boss_debug_theme = String(roll.get("theme", ""))
	_boss_debug_picks = roll.get("picks", []) as Array[Dictionary]

	EventLogger.log_event("BOSS_DEBUG", "Setup",
		"level=%d theme=%s picks=%d boss=%s" % [
			BOSS_DEBUG_LEVEL, _boss_debug_theme, _boss_debug_picks.size(), _boss_debug_id])

	# 3. 批量 apply 每张升级（与升级 UI 选择路径走同一份逻辑：归属分流 + "+1 轴进度"）
	for upgrade in _boss_debug_picks:
		_distribute_upgrade(upgrade)
		var uid: String = String(upgrade["id"])
		upgrade_stacks[uid] = int(upgrade_stacks.get(uid, 0)) + 1
		_grant_milestone_plus(upgrade)
	# 生效子集 + 词条联动逐机重建（与正常升级链一致）
	_refresh_squad_effective_stacks()

	# 3.5 三轴点数补发（自然成长退役后跳级点数为 0）：按主题 build 的轴分布补满
	# floor(15/3)=5 点，里程碑随加点自动生效——回填 debug 机体强度；debug 不查进化门槛
	var _earnable: int = SurvivorData.axis_points_earnable(BOSS_DEBUG_LEVEL)
	for pi in _earnable:
		var ax: StringName = SurvivorData.AXIS_GLADIATOR
		if not _boss_debug_picks.is_empty():
			ax = SurvivorData.axis_of_upgrade(_boss_debug_picks[pi % _boss_debug_picks.size()])
		survivor_player.add_axis_point(ax, _player_profile)

	# 4. 启动 BossEncounterEvent（PRE_STAGE → 玩家飞近自动 ENGAGED → VICTORY）
	if _event_director == null:
		push_error("Boss Debug: _event_director is null")
		return
	var anchor: Vector2 = player_aircraft.position + Vector2.UP * BOSS_DEBUG_BOSS_DISTANCE_PX
	# 玩家从南往北飞 → boss 朝南面对玩家（heading=180°）
	var ev := BossEncounterEvent.new(anchor, 180.0, _map_id, _boss_debug_id)
	_event_director.start(ev)

	if _zone_hint:
		_zone_hint.show_temp(
			tr("BOSS_DEBUG_HUD_LOADED_FMT") % [_boss_debug_theme.to_upper(), _boss_debug_id], 5.0)

## ════════════════════════════════════════════════
##  Bench 模式场景化设置（headless 性能压测）
## ════════════════════════════════════════════════
##
## 在 _ready 末尾 deferred 调用：
##   1. 玩家无敌（duration 期间持续输出，不会死掉）
##   2. 玩家挂 AIController 接管交战（替代手动点击操控）
##   3. add_xp 直接拉满经验 → 触发 leveled_up 信号链 → 走 _on_player_leveled_up
##      bench 分支自动随机抽技能（无视 max_stacks/requires/exclusive 全堆叠）
##   4. 立即 force-spawn 一批混编敌机覆盖所有"重 AI 路径"
##   5. spawner 仍在每帧 update（_physics_process 不跳）→ 之后按 token budget 自然补刷
const BENCH_PLAYER_LEVEL := 15
const BENCH_INITIAL_ENEMY_COUNT := 26  ## 立即 force-spawn 总数，足够 26+ 编队对抗
## stress_swarm 场景：20 敌 + 10 友全图随机小队混战
const BENCH_SWARM_ENEMY_COUNT := 20
const BENCH_SWARM_FRIENDLY_COUNT := 10
const BENCH_SWARM_AA_COUNT := 8     ## AA 炮散布数（团队 1，自动打 team 0）
const BENCH_SWARM_SAM_COUNT := 6    ## SAM 散布数（团队 1，自动打 team 0）
const BENCH_SWARM_SPAWN_MARGIN_PX := 1500.0  ## 离世界边界至少留这么远，避免一刷出来就被 boundary clamp
const BENCH_SWARM_MIN_SEPARATION_PX := 800.0 ## 同方刷点间距下限，防止开局重叠

# boss_mother_goose scenario：满配玩家 + 20 友军挑战 Mother Goose
const BENCH_BOSS_MG_FRIENDLY_COUNT := 20
const BENCH_BOSS_MG_FRIENDLY_RING_MIN_PX := 2000.0
const BENCH_BOSS_MG_FRIENDLY_RING_MAX_PX := 3500.0
var _bench_death_stage := 0
var _bench_death_original_id := 0
var _bench_takeover_verified := false

func _setup_bench_scenario() -> void:
	if not _bench_mode:
		return
	if not survivor_player or not is_instance_valid(player_aircraft):
		push_error("[Bench] setup: missing survivor_player or player_aircraft")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bench_wall_started_msec = Time.get_ticks_msec()
	_bench_last_heartbeat_msec = _bench_wall_started_msec
	if _bench_scenario == "evolution_growth":
		if not _growth_bench_config_ok:
			_bench_finish_now("terminal=invalid_growth_configuration\n", 1)
			return
		seed(_growth_bench.seed_value)
		player_aircraft.global_position = Vector2.ZERO
		player_aircraft.clear_trail()
		_bench_attach_player_ai()
		if not _growth_bench.setup(self):
			_bench_finish_now("terminal=growth_setup_failed\n", 1)
			return
		EventLogger.log_event("BENCH", "GrowthSetup",
			"run=%s duration=%.1fs starter=%s squad=%d seed=%d" % [
				_growth_bench.run_id, _bench_duration, _growth_bench.starter_id,
				_growth_bench.squad_size, _growth_bench.seed_value])
		return
	# 0. 固定 RNG seed → 同 scenario 多次跑得到相同 spawn 几何 / AI 抖动 / 战斗节拍
	#    没这一步：33-144 fps 的 spread 完全淹没"优化前后对比"信号
	seed(42)

	# 1. 玩家无敌（防止 duration 期间 KIA 中断压力）
	player_aircraft.invulnerable = true
	# 生存模式默认出生点贴近南边界；AI 大转向时会先冲出边界，
	# 触发需人工点击的撤退菜单，使无头 bench 表现为永久暂停。压测统一在地图中心展开。
	player_aircraft.global_position = Vector2.ZERO
	player_aircraft.clear_trail()

	# 2. 玩家挂 AIController（覆盖默认的"鼠标点击 → target_position"操控路径）
	#    与 spawner 给敌机挂 AI 的方式一致；team=0 让目标选择只挑敌方
	_bench_attach_player_ai()

	# 3. 一次性灌满 1→15 级所需经验 → SurvivorPlayer 的 _process 排空时连续 emit 14 次
	#    leveled_up → 每次走 _on_player_leveled_up bench 分支随机选技能（一帧内全部完成）
	#    *2 是冗余，保证溢出不会让最后一次缺一点点经验
	survivor_player.add_xp(SurvivorData.xp_for_level(BENCH_PLAYER_LEVEL + 1) * 2)

	# 4. 批量 force-spawn 敌机（按 scenario 分支）
	if _spawner:
		if _bench_scenario == "survivor_death":
			_bench_setup_survivor_death()
		elif _bench_scenario == "stress_swarm":
			_bench_force_spawn_swarm()
		elif _bench_scenario == "enemy_pool_stress":
			_bench_force_enemy_pool_stress()
		elif _bench_scenario == "boss_mother_goose":
			_bench_force_spawn_boss_mg()
		elif _bench_scenario == "reversal":
			_bench_force_spawn_reversal()
		elif _bench_scenario == "zone_support_stress":
			_bench_force_spawn_mixed(BENCH_INITIAL_ENEMY_COUNT)
			_bench_force_zone_support()
		elif _bench_scenario == "naval_zone_stress":
			_bench_force_naval_zone()
			_bench_force_spawn_mixed(BENCH_INITIAL_ENEMY_COUNT)
		elif _bench_scenario == "ace_support_stress":
			_bench_force_spawn_mixed(BENCH_INITIAL_ENEMY_COUNT)
			_bench_force_ace_support()
		else:
			_bench_force_spawn_mixed(BENCH_INITIAL_ENEMY_COUNT)

	EventLogger.log_event("BENCH", "Setup",
		"scenario=%s duration=%.1fs initial_enemies=%d level_target=%d" % [
			_bench_scenario, _bench_duration, BENCH_INITIAL_ENEMY_COUNT, BENCH_PLAYER_LEVEL])
	print("[Bench] scenario ready: %s, duration=%.1fs, initial_enemies=%d" % [
		_bench_scenario, _bench_duration, BENCH_INITIAL_ENEMY_COUNT])


func _bench_attach_player_ai() -> void:
	var ai := AIController.new()
	ai.name = "AI_BenchPlayer"
	ai.aircraft = player_aircraft
	ai.patrol_altitude = 5500.0
	var pp: Vector2 = player_aircraft.global_position
	ai.waypoints = PackedVector2Array([
		pp + Vector2(2000, -2000),
		pp + Vector2(2000, 2000),
		pp + Vector2(-2000, 2000),
		pp + Vector2(-2000, -2000),
	])
	ai.enable_combat = true
	ai.engage_cooldown = 1.0
	ai.engage_duration = 60.0
	ai.aggression = 0.95
	ai.skill_level = 0.85
	ai.composure = 0.7
	ai.focus = 0.85
	ai.self_preservation = 0.4
	ai.evade_missiles = true
	player_aircraft.add_child(ai)


## 扩池专项：直属 9 机同时面对雪幕、F-22 四锁、两类常规多锁与近/远两原型。
## 只复用现有实体/控制器；不新增常驻测试节点。全部无敌并跳过远距清理，保持样本密度。
func _bench_force_enemy_pool_stress() -> void:
	player_aircraft.global_position = Vector2.ZERO
	_spawner._dynamic_enemy_cap = SurvivorData.MAX_ENEMIES_HARD
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.SNOWBLIND, 1,
		Vector2(0.0, -3500.0), 180.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.F22, 3,
		Vector2(0.0, -2500.0), 180.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.GRIPEN_E, 3,
		Vector2(2800.0, 0.0), 270.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.RAFALE, 2,
		Vector2(-2800.0, 0.0), 90.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.SU57, 2,
		Vector2(0.0, 2800.0), 0.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.J20, 2,
		Vector2(2200.0, -2200.0), 225.0)
	_bench_spawn_enemy_squad_at(SurvivorSpawner.EnemyType.F15_REGULAR, 4,
		Vector2(-2200.0, 2200.0), 45.0)
	for unit in CombatUnit.all_units:
		if unit is Aircraft and is_instance_valid(unit):
			var ac := unit as Aircraft
			ac.invulnerable = true
			ac.set_meta("skip_far_cleanup", true)
	print("[Bench] enemy_pool_stress: 9 direct friendlies vs 17 expanded-pool enemies")


## 双 3★ 对空 + 单对地支援最坏场景：常规 26 敌压力样本上再放 8 F-86 + 2 A-10。
## ZoneMission 只负责完成一次真实生成，随后停自身 tick，避免预刷其它战区污染样本。
func _bench_force_zone_support() -> void:
	# 性能守则要求 Sentinel + Lv5+ 样本；bench 玩家为 Lv15，另加标准 5 护卫指挥机群。
	# 本轮军械库改动把 ESM 显式挂进压力样本，覆盖其 0.5s 全单位扫描与范围圈。
	if player_aircraft.params.get_equipment_of_kind("esm_pod") == null:
		player_aircraft.params.equipment.append(load("res://resources/esm_pod.tres").duplicate(true))
		player_aircraft._publish_equipment_to_legacy()
	_spawner._spawn_commander_squad(5)
	_zone_data = ZoneData.new(Callable())
	_zone_mission = ZoneMission.new()
	add_child(_zone_mission)
	_zone_mission.setup(self, _zone_data, player_aircraft,
		_sam_scene, _sam_params, _aa_scene, _aa_params,
		bullet_manager, missile_manager, _spawner)
	for zid: StringName in [&"A", &"B"]:
		_zone_data.debug_set_available(zid)
		_zone_data.set_mission_type(zid, "squadron")
		_zone_data.set_airfield_difficulty(zid, 3)
		_zone_mission._start_air_support_if_needed(zid, _zone_data.get_zone_by_id(zid))
	_zone_data.debug_set_available(&"C")
	_zone_data.set_mission_type(&"C", "ground")
	_zone_data.set_airfield_difficulty(&"C", 3)
	_zone_mission._start_air_support_if_needed(&"C", _zone_data.get_zone_by_id(&"C"))
	_zone_mission._update_air_support(ZoneMission.SUPPORT_TICK_S)
	_zone_mission.set_physics_process(false)
	var support_count := 0
	for child in get_children():
		if child is Aircraft and child.has_meta("zone_support"):
			support_count += 1
	print("[Bench] zone_support_stress spawned support=%d (expected 10)" % support_count)

## 3★ 对舰任务最坏样本：常规混编 + Sentinel/5 护卫 + 六舰全目标编成。
## 玩家放进舰队交战半径并设为无敌，确保 VLS/CIWS/Flak 与全部舰载挂点持续工作整段样本。
func _bench_force_naval_zone() -> void:
	var center := Vector2(800.0, 7000.0)
	player_aircraft.global_position = center + Vector2(0.0, -1200.0)
	player_aircraft.invulnerable = true
	_spawner._spawn_commander_squad(5)
	_zone_data = ZoneData.new(Callable())
	_zone_mission = ZoneMission.new()
	add_child(_zone_mission)
	_zone_mission.setup(self, _zone_data, player_aircraft,
		_sam_scene, _sam_params, _aa_scene, _aa_params,
		bullet_manager, missile_manager, _spawner)
	var spawned := _zone_mission._spawn_naval_formation(&"E", center, 3, _ffg_params)
	_zone_mission.set_physics_process(false)
	var naval_count: int = (_zone_mission._spawned_zones.get(&"E", []) as Array).size()
	print("[Bench] naval_zone_stress spawned=%s naval=%d (expected 6)" % [str(spawned), naval_count])

## 按"占用 AI 时间"加权混编：覆盖所有重战术路径，避免压测样本只反映单一类型
## 编队/单机的选择参考各 EnemyType 在 CLAUDE.md 敌人索引表里的"生成形式"列
func _bench_force_spawn_mixed(_total: int) -> void:
	if _spawner == null:
		return
	# [enemy_type, count, as_squad?]
	# 编队类用 _spawn_squad（走 SquadFactory，触发 SQUAD_FOLLOW AI 路径）
	# 单机类用 _spawn_single（直接 _create_enemy，走 PATROL/ENGAGE）
	var mix: Array = [
		[SurvivorSpawner.EnemyType.MIG, 4, true],            # 4× MiG-29 (主力威胁，默认 BFM)
		[SurvivorSpawner.EnemyType.F86, 4, true],            # 4× F-86 (Gladiator + 火箭弹路径)
		[SurvivorSpawner.EnemyType.MIG23, 3, true],          # 3× MiG-23 (Gladiator 综合)
		[SurvivorSpawner.EnemyType.F100, 3, true],           # 3× F-100 (Lancer 编队)
		[SurvivorSpawner.EnemyType.F4, 3, true],             # 3× F-4 (重导弹卡车，双弹种)
		[SurvivorSpawner.EnemyType.SU27, 3, true],           # 3× Su-27 (Gladiator 顶级 + 眼镜蛇) — 测试场景成建制
		[SurvivorSpawner.EnemyType.MIG31, 2, true],          # 2× MiG-31 (Lancer 顶级) — 测试场景成建制
		[SurvivorSpawner.EnemyType.INTERCEPTOR, 3, true],    # 3× J-7 (Lancer 入门)
		[SurvivorSpawner.EnemyType.F4E, 3, true],            # 3× F-4E — 前期导弹杂鱼（有人机）
		[SurvivorSpawner.EnemyType.UCAV, 3, true],           # 3× MQ-110 — 导弹无人机，测试场景成建制
	]
	# weapon_demo：武器准则观察场——AF-03（敌方电磁炮狙击手，LINE_UP 活体样本）×2
	# + 少量常规敌机（给己方竞选制造远/中/近距离样本），总量小便于肉眼跟踪单机行为
	if _bench_scenario == "weapon_demo":
		mix = [
			[SurvivorSpawner.EnemyType.AF03, 2, false],   # 2× AF-03 单机（bvr 狙击手）
			[SurvivorSpawner.EnemyType.MIG, 3, true],     # 3× MiG-29 编队（中距导弹样本）
			[SurvivorSpawner.EnemyType.UAV, 3, false],    # 3× UAV（近距机炮样本）
		]
	var spawned: int = 0
	for entry in mix:
		var etype: int = entry[0]
		var n: int = entry[1]
		var as_squad: bool = entry[2]
		if as_squad:
			_spawner._spawn_squad(etype, n)
		else:
			for i in range(n):
				_spawner._spawn_single(etype)
		spawned += n
	print("[Bench] force-spawned %d enemies across %d types" % [spawned, mix.size()])

## reversal：专项复现"短时间内 180° 调转机头"。**编队 vs 编队**：玩家方 4 机编队（长机 + 3 僚机，
## 在 _ready 里按 wingman_count=3 生成）对抗一支 4 机敌方成建制小队（Gladiator 原型，
## aggression>0.85 → 不 boom-zoom 撤退），在 ~2km 内头对头：merge → 双方编队反转再咬 → 高频 180° 反转，
## 同时压到 SQUAD_FOLLOW / 编队归位 / 反转 三条路径的交叉。关掉全场导弹规避(聚焦纯转弯，避免 evade 打断)，
## 并把 AC_TICK 采样门槛降到 20° → 完整记录每次反转弧(含过零段)，离线判定"平滑单向反转"vs"来回大坡颤抖"。
## 用法：godot --path . -- --bench=reversal --duration=60（不加 --headless 可肉眼看；结束自动 dump 日志）
func _bench_force_spawn_reversal() -> void:
	if _spawner == null:
		return
	Aircraft.AC_TICK_BANK_THRESHOLD = 20.0  # 全程低门槛采样，捕捉反转全弧
	# ⚠ 把玩家放到地图正中心 (0,0)：默认起点 (0,6400) 只距南边界 1100px（地图半边长仅 7500px），
	#   战斗一散开就撞 survivor_spawner 的边界 disengage 系统（强制 PATROL 朝内飞）→ 与小队
	#   SQUAD_FOLLOW 守卫每帧弹跳（log 实证僚机狂刷 auto-enter SQUAD_FOLLOW、飘边变慢不参战）。
	#   居中后整场战斗远离 ±7500 边界，边界系统永不触发。
	player_aircraft.global_position = Vector2.ZERO
	var pp: Vector2 = Vector2.ZERO
	# 战区锚点固定在地图中心，半径 5000 < 6500（边界警戒线 7500-1000）→ 出圈平滑返航发生在
	# 撞边界之前，边界 disengage 永不触发。锚点用普通 Node2D（非 CombatUnit，不会被击坠解除）。
	var anchor := Node2D.new()
	anchor.name = "ReversalArenaAnchor"
	anchor.global_position = pp
	add_child(anchor)
	# 敌方 4 支 4 机小队，从中心四周 ~3km 朝中心扑来 → 在中心圆内汇成持续大乱斗（玩家方 4 机编队对抗）
	var squads: Array = [
		[SurvivorSpawner.EnemyType.SU27,  pp + Vector2(0, -3000), 180.0],   # 北 → 南
		[SurvivorSpawner.EnemyType.MIG,   pp + Vector2(3000, 0), 270.0],    # 东 → 西
		[SurvivorSpawner.EnemyType.F86,   pp + Vector2(0, 3000), 0.0],      # 南 → 北
		[SurvivorSpawner.EnemyType.MIG23, pp + Vector2(-3000, 0), 90.0],    # 西 → 东
	]
	for sq in squads:
		_bench_spawn_enemy_squad_at(sq[0], 4, sq[1], sq[2])
	# 全场（玩家长机/僚机 + 敌方）统一：commit + 关导弹规避。
	# ⚠ combat_zone 战区约束**只加在小队长机 / 独立机**上，绝不加在僚机上：
	#   combat_zone 出圈会强制 PATROL，与僚机 SQUAD_FOLLOW + spawn 自校正守卫冲突 → 每帧
	#   PATROL↔SQUAD_FOLLOW 弹跳（log 实证 Echo 每 0.1s 刷 auto-enter SQUAD_FOLLOW，飞到边上变慢）。
	#   长机被困住，僚机跟着长机自然留在中心，无冲突。
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or not (unit is Aircraft):
			continue
		for child in (unit as Aircraft).get_children():
			if child is AIController:
				var ai2: AIController = child
				ai2.evade_missiles = false
				ai2.self_preservation = 0.25       # commit，不 extend 拉远
				ai2.aggression = 0.98
				ai2.engage_cooldown = 1.0
				var is_leader: bool = (ai2.squad == null) \
						or (is_instance_valid(ai2.squad.leader) and ai2.squad.leader == unit)
				if is_leader:
					ai2.combat_zone_anchor = anchor    # 仅长机困在中心圆，出圈平滑返航；僚机跟随长机
					ai2.combat_zone_radius = 5000.0    # < 6500 边界警戒线
					# 玩家长机的巡逻航点也收到中心小框（默认是绕旧起点 (0,6400) 贴边）
					if unit == player_aircraft:
						ai2.waypoints = PackedVector2Array([
							Vector2(1500, -1500), Vector2(1500, 1500),
							Vector2(-1500, 1500), Vector2(-1500, -1500),
						])
						ai2.current_waypoint_index = 0
				break
	print("[Bench] reversal: 4v16 困中心(0,0)战区大乱斗（仅长机锚定，半径 5000px）, AC_TICK threshold=20°")


## reversal 用：在指定位置 spawn 一支敌方成建制小队（同 _bench_spawn_friendly_squad_at 但保持 team=enemy）
func _bench_spawn_enemy_squad_at(etype: int, size: int, leader_pos: Vector2, heading_deg: float) -> void:
	var heading_rad: float = deg_to_rad(heading_deg)
	var sq: Squad = SquadFactory.create()
	for i in range(size):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			spawn_pos = leader_pos + sq.get_formation_offset(i).rotated(heading_rad)
		var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
		if ac == null:
			continue
		ac.invulnerable = true                       ## 维持整段对抗不减员
		ac.set_meta("skip_far_cleanup", true)
		if i == 0:
			SquadFactory.register_leader(sq, ac)
		else:
			SquadFactory.register_wingman(sq, ac, true)


## stress_swarm：20 敌 + 10 友全图随机小队混战 + 地面 AA/SAM 骚扰，把 SquadFactory /
## SQUAD_FOLLOW / formation offset / ground unit 路径全都踩一遍。所有飞机 invulnerable，
## 整个 30s 维持满编混战；spawner cap 拉到 MAX_ENEMIES_HARD 让自然补刷尽量补满
func _bench_force_spawn_swarm() -> void:
	if _spawner == null:
		return
	# 与 stress_40 (seed=42) 区分，避免散布几何撞 baseline
	seed(43)
	var rng := RandomNumberGenerator.new()
	rng.seed = 43

	# 放开 spawner 的 dynamic cap，让自然补刷尽量补到 hard cap（默认 30 → 40）
	_spawner._dynamic_enemy_cap = SurvivorData.MAX_ENEMIES_HARD

	# 监听自然补刷：新加进 mode 树的 Aircraft 也设 invulnerable，否则会被无敌友军屠杀完
	# 进不到稳态 cap。child_entered_tree 在 mode.add_child(enemy) 时同步触发
	if not child_entered_tree.is_connected(_bench_swarm_on_child_entered):
		child_entered_tree.connect(_bench_swarm_on_child_entered)

	var used_positions: Array[Vector2] = []

	# 敌方小队（每队 2~4 架，9 类机型轮抽至 20 架）
	var enemy_pool: Array = [
		SurvivorSpawner.EnemyType.MIG, SurvivorSpawner.EnemyType.F86,
		SurvivorSpawner.EnemyType.MIG23, SurvivorSpawner.EnemyType.F100,
		SurvivorSpawner.EnemyType.F4, SurvivorSpawner.EnemyType.SU27,
		SurvivorSpawner.EnemyType.MIG31, SurvivorSpawner.EnemyType.INTERCEPTOR,
		SurvivorSpawner.EnemyType.F4E, SurvivorSpawner.EnemyType.UCAV,
	]
	var enemy_remaining: int = BENCH_SWARM_ENEMY_COUNT
	while enemy_remaining > 0:
		var size: int = mini(rng.randi_range(2, 4), enemy_remaining)
		var etype: int = enemy_pool[rng.randi() % enemy_pool.size()]
		_bench_spawn_random_squad(etype, size, false, rng, used_positions)
		enemy_remaining -= size

	# 友方小队（每队 2~4 架，4 类空优机型轮抽至 10 架）
	var friendly_pool: Array = [
		SurvivorSpawner.EnemyType.SU27, SurvivorSpawner.EnemyType.MIG31,
		SurvivorSpawner.EnemyType.MIG, SurvivorSpawner.EnemyType.F100,
	]
	var friendly_remaining: int = BENCH_SWARM_FRIENDLY_COUNT
	while friendly_remaining > 0:
		var size: int = mini(rng.randi_range(2, 4), friendly_remaining)
		var ftype: int = friendly_pool[rng.randi() % friendly_pool.size()]
		_bench_spawn_random_squad(ftype, size, true, rng, used_positions)
		friendly_remaining -= size

	# 地面骚扰：散布 AA 炮 + SAM（team=1，自动锁 team=0 友军/玩家）
	var ground_count: int = 0
	for i in range(BENCH_SWARM_AA_COUNT):
		var p := _bench_pick_swarm_pos(rng, used_positions)
		used_positions.append(p)
		_bench_spawn_ground_at(_aa_scene, _aa_params, 1, p)
		ground_count += 1
	for i in range(BENCH_SWARM_SAM_COUNT):
		var p := _bench_pick_swarm_pos(rng, used_positions)
		used_positions.append(p)
		_bench_spawn_ground_at(_sam_scene, _sam_params, 1, p)
		ground_count += 1

	# 场地中央刷一个航母战斗群 BOSS（CV + 5 护卫 + Phase 1 F/A-18 弹射）
	_bench_spawn_csg_at_center()

	print("[Bench] swarm: %d enemies + %d friendlies + %d ground (AA+SAM) + CSG boss at center, all units effectively invulnerable" % [
		BENCH_SWARM_ENEMY_COUNT, BENCH_SWARM_FRIENDLY_COUNT, ground_count])

## boss_mother_goose scenario：满配 lv15 玩家 + 20 友军挑战 Mother Goose
## 友军 invul（30s+ 维持火力），boss / MQ-X / MQ-110 等正常 HP（可被打死，测试战斗终局）
## 推荐 --duration=120 看完整战斗（30s 默认只能跑到 MQ-X 出场）
func _bench_force_spawn_boss_mg() -> void:
	if _spawner == null:
		return
	seed(44)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44

	# 关掉 spawner 自然补刷（专注 boss + 友军，避免其它敌人扰乱测试样本）
	_spawner._dynamic_enemy_cap = 0

	# 20 架友军分 5 队（每队 4 架），围玩家 2000-3500px 圆周散布
	var friendly_pool: Array = [
		SurvivorSpawner.EnemyType.SU27,    # Gladiator 顶级 (双弹种 + 眼镜蛇)
		SurvivorSpawner.EnemyType.MIG31,   # Lancer 顶级 (长射程 AAM)
		SurvivorSpawner.EnemyType.MIG,     # MiG-29 默认 BFM
		SurvivorSpawner.EnemyType.F100,    # Lancer 编队
	]
	var player_pos: Vector2 = player_aircraft.global_position
	var friendly_remaining: int = BENCH_BOSS_MG_FRIENDLY_COUNT
	var squad_idx: int = 0
	var total_squads: int = int(ceilf(float(BENCH_BOSS_MG_FRIENDLY_COUNT) / 4.0))
	while friendly_remaining > 0:
		var size: int = mini(4, friendly_remaining)
		var ftype: int = friendly_pool[squad_idx % friendly_pool.size()]
		# 均匀散布在玩家周围圆周，加少量随机抖动避免完美对称
		var base_ang: float = TAU * float(squad_idx) / float(total_squads)
		var ang: float = base_ang + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(BENCH_BOSS_MG_FRIENDLY_RING_MIN_PX, BENCH_BOSS_MG_FRIENDLY_RING_MAX_PX)
		var leader_pos: Vector2 = player_pos + Vector2(cos(ang), sin(ang)) * dist
		# 初始 heading 大致面向中心（玩家方向），AI 会自动选目标接战
		var heading_deg: float = rad_to_deg(atan2(player_pos.x - leader_pos.x, -(player_pos.y - leader_pos.y)))
		_bench_spawn_friendly_squad_at(ftype, size, leader_pos, heading_deg)
		friendly_remaining -= size
		squad_idx += 1

	# Mother Goose 在地图中心 spawn（skip_bgm=true headless 无音频）
	var goose := MotherGooseBoss.new()
	_spawner._spawn_boss(goose, Vector2.ZERO, true)
	if _spawner._boss == null:
		push_error("[Bench] MotherGoose spawn failed")
		return

	print("[Bench] boss_mother_goose: lv%d player + %d friendlies vs MOTHER GOOSE @ (0,0)" % [
		BENCH_PLAYER_LEVEL, BENCH_BOSS_MG_FRIENDLY_COUNT])

## boss_mother_goose 用：在指定位置 spawn 一队同型友军（与 _bench_spawn_random_squad 同款
## 但落点已由调用方决定，且不写 used 数组）
func _bench_spawn_friendly_squad_at(etype: int, size: int, leader_pos: Vector2, heading_deg: float) -> void:
	var heading_rad: float = deg_to_rad(heading_deg)
	var sq: Squad = SquadFactory.create()
	for i in range(size):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			var offset: Vector2 = sq.get_formation_offset(i)
			spawn_pos = leader_pos + offset.rotated(heading_rad)
		var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
		if ac == null:
			continue
		ac.invulnerable = true                       ## 30s+ 维持完整火力
		ac.set_meta("skip_far_cleanup", true)
		_bench_convert_to_friendly(ac)
		if i == 0:
			SquadFactory.register_leader(sq, ac)
		else:
			SquadFactory.register_wingman(sq, ac, true)


## 在地图中心刷一个 CSG（航母战斗群）BOSS，并把所有舰船 HP 拉爆模拟无敌
## 直接调用 _spawner._spawn_boss(skip_bgm=true) 复用现成 spawn 逻辑
## engage() 启动 F/A-18 持续弹射循环（每 120s 补一架，初始 2 架）
func _bench_spawn_csg_at_center() -> void:
	if _spawner == null:
		return
	var csg := CarrierStrikeGroup.new()
	csg.initial_heading_deg = 0.0
	_spawner._spawn_boss(csg, Vector2.ZERO, true)
	if _spawner._boss == null:
		push_error("[Bench] CSG spawn failed")
		return
	# 舰船没有 invulnerable 字段 → 拉爆所有可被打掉的 HP（hull / weak_point / mounts）
	# 任一归零都会触发沉船 / 挂点失能 → 影响 stress 持续性，所以三个都拉
	for ship in (_spawner._boss as CarrierStrikeGroup).get_all_ships():
		if ship == null or not is_instance_valid(ship):
			continue
		ship.hull_hp_max = 1.0e9
		ship.hull_hp = 1.0e9
		if ship.weak_point != null:
			ship.weak_point.hp = 1.0e9
		for mount in ship.mounts:
			if mount != null:
				mount.hp = 1.0e9
	# 启动 Phase 1 F/A-18 持续弹射（正常流程是玩家进 BOSS_ZONE 触发；bench 直接调）
	_spawner._boss.engage()

## 在全图随机点刷一支同型小队（参考 spawner._spawn_squad 但落点改全图随机）
##   etype         — 该小队全队机型（同型编队，与现有 _spawn_squad 一致）
##   size          — 小队人数 (2~4)
##   make_friendly — true 时把该小队整体翻转成 team=0 + invulnerable
func _bench_spawn_random_squad(etype: int, size: int, make_friendly: bool,
		rng: RandomNumberGenerator, used: Array[Vector2]) -> void:
	var leader_pos: Vector2 = _bench_pick_swarm_pos(rng, used)
	used.append(leader_pos)
	var heading_deg: float = rng.randf() * 360.0
	var heading_rad: float = deg_to_rad(heading_deg)

	var sq: Squad = SquadFactory.create()
	for i in range(size):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			# 复用 SquadFactory 的编队偏移（与 spawner._spawn_squad 同款），让 SQUAD_FOLLOW 路径有效
			var offset: Vector2 = sq.get_formation_offset(i)
			spawn_pos = leader_pos + offset.rotated(heading_rad)
			used.append(spawn_pos)
		var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
		if ac == null:
			continue
		# 所有飞机（敌 + 友）全部 invulnerable，30s 维持满编混战，PerfBuckets 样本干净
		ac.invulnerable = true
		# 全图散布 → 离玩家最远可到 ~12000px，远过 FAR_CLEANUP_DISTANCE(7000)。
		# 不挂 skip_far_cleanup meta 会被 _update_far_cleanup 静默清掉
		ac.set_meta("skip_far_cleanup", true)
		if make_friendly:
			_bench_convert_to_friendly(ac)
		if i == 0:
			SquadFactory.register_leader(sq, ac)
		else:
			# set_state=true → 直接进 SQUAD_FOLLOW（与 spawner._spawn_squad 一致）
			SquadFactory.register_wingman(sq, ac, true)

## 全图随机选一个不与已用点过近的位置（最多重试 20 次，兜底返回随机点）
func _bench_pick_swarm_pos(rng: RandomNumberGenerator, used: Array[Vector2]) -> Vector2:
	var half: float = MapBoundary.WORLD_HALF_PX - BENCH_SWARM_SPAWN_MARGIN_PX
	for _attempt in range(20):
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var ok := true
		for u in used:
			if p.distance_to(u) < BENCH_SWARM_MIN_SEPARATION_PX:
				ok = false
				break
		if ok:
			return p
	return Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))

## 在全图随机点刷一个地面单位（AA 炮 / SAM），与 _spawn_ground_unit 类似但落点用传入坐标
## bench 用：HP 拉爆模拟无敌，30s 持续骚扰友军
func _bench_spawn_ground_at(scene: PackedScene, params_res: Resource, team_id: int, pos: Vector2) -> void:
	if scene == null or params_res == null:
		return
	# 复制 params 避免改原始 .tres
	var dup_params: Resource = params_res.duplicate(true)
	dup_params.max_hp = 1.0e9
	var unit: GroundUnit = scene.instantiate()
	unit.params = dup_params
	unit.team = team_id
	unit.position = pos
	unit.initial_heading_deg = randf() * 360.0
	unit.set_meta("category", "adds")
	add_child(unit)
	unit.hp = 1.0e9
	unit.bullet_manager = bullet_manager
	unit.missile_manager = missile_manager

## stress_swarm 自然补刷的新 Aircraft 也设 invulnerable + skip_far_cleanup，维持满编混战
func _bench_swarm_on_child_entered(node: Node) -> void:
	if node is Aircraft:
		var ac := node as Aircraft
		ac.invulnerable = true
		ac.set_meta("skip_far_cleanup", true)

## 把 _create_enemy 出来的 (team=1) Aircraft 翻转成 team=0 友军
##   - team=0 → AIController.enable_combat 自动选 team=1 目标
##   - invulnerable=true → 30s 压测窗口不掉员
##   - callsign 加 ALLY- 前缀方便日志区分
func _bench_convert_to_friendly(ac: Aircraft) -> void:
	ac.team = 0
	ac.invulnerable = true
	ac.callsign = "ALLY-%s" % ac.callsign

## Bench 自动选技能：随机抽一张（剔除 evolved），无视 max_stacks/requires/exclusive
## 设计意图：玩家越打越强 → 击杀更快 → spawner token 越满 → 自我放大压力曲线
func _bench_auto_pick_upgrade() -> void:
	# 候选池：UPGRADES 里所有非进化技能；不做任何门控筛选
	var pool: Array[Dictionary] = []
	for u in SurvivorData.UPGRADES:
		if u.get("evolved", false):
			continue
		pool.append(u)
	if pool.is_empty():
		survivor_player.consume_level_up_display()
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	print("[Bench] auto-pick level=%d id=%s stat=%s" % [
		survivor_player.level, String(pick.get("id", "")), String(pick.get("stat", ""))])
	_distribute_upgrade(pick)
	var uid: String = String(pick["id"])
	upgrade_stacks[uid] = int(upgrade_stacks.get(uid, 0)) + 1
	_grant_milestone_plus(pick)
	# 生效子集 + 词条联动重建（与正常升级链一致）
	_refresh_squad_effective_stacks()
	# 解除"等待升级 UI"，让 SurvivorPlayer._process 继续排空 _pending_xp 触发下次 leveled_up
	survivor_player.consume_level_up_display()

func _count_aircraft_alive() -> int:
	var n: int = 0
	for u in CombatUnit.all_units:
		if not is_instance_valid(u):
			continue
		if u is Aircraft and not (u as Aircraft).is_destroyed:
			n += 1
	return n


## demo 模式补敌用：存活的敌方(team==1)飞机数
func _count_enemy_alive() -> int:
	var n: int = 0
	for u in CombatUnit.all_units:
		if not is_instance_valid(u):
			continue
		if u is Aircraft and u.team == 1 and not (u as Aircraft).is_destroyed:
			n += 1
	return n


## F7：切换玩家无敌（Boss Debug 模式专用）
func _boss_debug_toggle_invuln() -> void:
	if not is_instance_valid(player_aircraft):
		return
	player_aircraft.invulnerable = not player_aircraft.invulnerable
	var msg := "INVULN ON" if player_aircraft.invulnerable else "INVULN OFF"
	if _zone_hint:
		_zone_hint.show_temp(msg, 2.0)
	EventLogger.log_event("BOSS_DEBUG", "Cheat", msg)

## F8：复活 + 重 roll build + 重刷 boss（Boss Debug 模式专用）
## 实现方式：重置 meta + reload_current_scene。最简单可靠，避免半场状态同步问题。
func _boss_debug_respawn_reroll() -> void:
	# 重置 meta（_ready 里会重新读取）
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", _boss_debug_id)
	get_tree().set_meta("survivor_map_id", "boss_debug")
	get_tree().set_meta("survivor_aircraft_resource", _player_profile_path)
	# 立刻关掉游戏暂停态（升级 UI 占了暂停时不重置会卡住）
	# 走导演的全清：同时兜掉时间缩放 / 遮罩 / 镜头系数三类泄漏
	Presentation.clear_all()
	is_game_over = false
	is_paused_for_upgrade = false
	EventLogger.log_event("BOSS_DEBUG", "Respawn", "reload+reroll boss=%s" % _boss_debug_id)
	get_tree().reload_current_scene()

## 首次进入生存模式：浮现操作提示 + 在最上方那架 Tu-160 左侧显示"点击攻击"标签
## （不自己刷 Tu-160，已有 Tu-160 场上时由教程内部轮询挂靶）
func _start_first_run_tutorial() -> void:
	_tutorial = SurvivorTutorial.new()
	_tutorial.find_target_fn = _find_topmost_tu160
	add_child(_tutorial)

## 首次拥有至少一架存活僚机时显示固定号机切控提示；退出本局不结算，只有实际切机才永久消失。
func _maybe_start_wingman_switch_tutorial() -> void:
	if _boss_debug_mode or _bench_mode or is_instance_valid(_wingman_tutorial):
		return
	if not SurvivorTutorial.should_show_wingman_switch():
		return
	var slot := _first_switchable_wingman_slot()
	if slot < 1:
		return
	_wingman_tutorial = SurvivorWingmanTutorial.new()
	_wingman_tutorial.target_slot = slot
	add_child(_wingman_tutorial)

## 当前操控机之外最小的存活固定号机号；提示具体按键，也供无头回归验证映射不压缩。
func _first_switchable_wingman_slot() -> int:
	if not _squad:
		return -1
	var best := 10
	for ac in _squad.members:
		if is_instance_valid(ac) and not ac.is_destroyed and ac != player_aircraft:
			best = mini(best, ac.squad_slot)
	return best if best <= 9 else -1

func _find_topmost_tu160() -> Node2D:
	var best: Aircraft = null
	var best_y := INF
	for child in get_children():
		if not (child is Aircraft) or child.is_destroyed or child.team != CombatUnit.TEAM_HOSTILE:
			continue
		if not child.has_meta("silhouette") or child.get_meta("silhouette") != "bomber":
			continue
		if child.global_position.y < best_y:
			best_y = child.global_position.y
			best = child
	return best

# ══════════════════════════════════════════════
#  起始僚机（"小队主控"型主角专用）
# ══════════════════════════════════════════════

## 确保玩家小队存在并把玩家装配成长机；已存在则直接返回。
## 起手僚机（wingman_count>0）与战区奖励僚机（wingman_count==0 的机型首次拿到 +1 僚机）
## 共用这条长机装配链——否则"33/34 机型没有 _squad → 奖励僚机静默降级成 QMAAM"（bug）。
func _ensure_player_squad() -> Squad:
	if _squad != null:
		return _squad
	if not player_aircraft or not is_instance_valid(player_aircraft):
		return null
	var sq := SquadFactory.create()
	sq.escort_doctrine_enabled = true  # 玩家队吃护卫学说（spec squad-ai-escort）：僚机护长机/反杀咬长机者
	# 战术=阵型：初始阵型跟默认交战模式（FOLLOW_LEADER → 指尖四点）一致（spec squad-cohesion）
	sq.formation = Squad.formation_for_engage_mode(AIController.SquadEngageMode.FOLLOW_LEADER)
	# 长机（玩家）挂休眠 AIController（manual_control=true）：被降为僚机时 AI 能接手。
	# 休眠 AI 早 return，不改变玩家鼠标操控体验（spec squad-control-switching §2.4）。
	# 也是 RTS 轮盘广播的入口：SquadCommandController._squad_members 读 player._ai_ref.squad。
	player_aircraft.squad_slot = 1
	if _get_ai(player_aircraft) == null:
		var leader_ai := AIController.new()
		leader_ai.name = "AI_Leader"
		leader_ai.aircraft = player_aircraft
		leader_ai.enable_combat = true
		leader_ai.evade_missiles = true
		leader_ai.aggression = 1.0
		leader_ai.skill_level = 1.0
		leader_ai.composure = 1.0
		leader_ai.focus = 1.0
		leader_ai.situational_awareness = 1.0
		leader_ai.engage_duration = 99999.0
		leader_ai.engage_cooldown = 2.0
		leader_ai.manual_control = true
		player_aircraft.add_child(leader_ai)
	SquadFactory.register_leader(sq, player_aircraft)
	# 长机是玩家亲控机：绝不能带编队托管标志，否则 keep_target_on_arrival=true 会让
	# 点击移动"到达不停"（飞过头继续飞）。显式清干净，与切换接管时的 clear_formation 一致。
	player_aircraft.clear_formation()
	_squad = sq
	sq.leader_changed.connect(_on_squad_leader_changed)
	# 登记进 spawner 队伍表：HUD 小队指挥面板经 _spawner.get_squads() 反查"玩家为长机的队"，
	# 定期 _cleanup_squads() 也只清理表内队伍。登记点必须在这条**公共**装配链上——
	# 原先只挂在 _spawn_starting_wingmen 末尾，导致懒建队机型（40/41 机）拿到僚机后
	# 小队指挥 UI 永不出现、阵亡僚机也永不从 members 剔除（只有起手带僚机的 F-14 正常）。
	if _spawner and not _spawner.get_squads().has(sq):
		_spawner.get_squads().append(sq)
	return _squad

## 分配一个稳定号机号：取当前**存活**成员里最小的未占用正整数（1=玩家长机）。
## 直接用 members.size()+1 会在"阵亡成员被 cleanup 剪掉"后撞号、在满编时超出数字键范围。
## 只数存活成员（跳过阵亡待清理机）：保证号机号恒 ≤ 存活数 ≤ 9，永远落在数字键 1-9 内；
## 与阵亡残骸的瞬时同号无害——_switch_control_to_slot 本就跳过 is_destroyed，命中的必是活机。
func _next_free_squad_slot() -> int:
	var used: Dictionary = {}
	if _squad:
		for m in _squad.members:
			if is_instance_valid(m) and not m.is_destroyed and m.squad_slot > 0:
				used[m.squad_slot] = true
	var slot := 1
	while used.has(slot):
		slot += 1
	return slot

## 根据 PlayableAircraft 档案在玩家旁边生成 N 架友方僚机，
## 并把它们和玩家组成一个 Squad（玩家为长机）。
## 仅当 profile.wingman_count > 0 时由 _ready 调用。
func _spawn_starting_wingmen(profile: PlayableAircraft) -> void:
	if not profile or profile.wingman_count <= 0 or not player_aircraft:
		return
	var wing_base: AircraftParams = profile.wingman_params
	if wing_base == null:
		wing_base = profile.base_params  # 缺省：与主角同型
	if wing_base == null:
		return

	var sq := _ensure_player_squad()
	if sq == null:
		return

	for i in range(1, profile.wingman_count + 1):
		var ac: Aircraft = _aircraft_scene.instantiate()
		ac.squad_slot = i + 1   # 号机号：长机=1，僚机 2..N（稳定、出生即定，数字键映射）
		ac.params = wing_base.duplicate(true)
		SurvivorPlayableSetup.deep_dup_weapons(ac.params)
		# 僚机走与长机完全相同的档案应用，确保起始属性（雷达/速度/G/武器/装填/伤害上限/
		# 闪避/无限燃油 等）完全一致；is_wingman=true 仅跳过 codename 后缀。
		# 升级按归属分流全队下发（skills-720 T1）：通用/品类匹配技僚机同样吃到。
		SurvivorPlayableSetup.apply(ac, profile, true)
		ac.team = 0
		ac.set_meta("profile_id", profile.id)   # 品类身份 stamp（与长机同型）

		# 阵型槽位
		var offset := sq.get_formation_offset(i)
		var rotated := offset.rotated(player_aircraft.heading)
		ac.position = player_aircraft.global_position + rotated
		ac.initial_heading_deg = rad_to_deg(player_aircraft.heading)
		ac.altitude = player_aircraft.altitude
		ac.target_altitude = player_aircraft.altitude
		ac.bullet_manager = bullet_manager
		ac.missile_manager = missile_manager
		# 生存模式全局规则 + 与长机一致的显示/战术设置
		ac.flat_altitude = true
		ac.hide_data_label = true  # 用与长机一致的精简 HUD 标签（无 MSL/AMM/FLR 细节，详情走小队面板）
		ac.set_target_tier(Aircraft.AltitudeTier.HIGH)  # 与长机一致：开局即最高高度
		# P4 Phase 2：僚机也走 TacticalPlanner（与 ENABLE_PLANNER_FOR_REGULAR_AI 共享开关）
		# 修复：BFMTactics.execute_lag_pursuit 把僚机速度锁到 tgt×0.95，慢目标接战时被强制减速
		if SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI:
			ac.use_tactical_planner = true
		add_child(ac)
		# 与长机一致：起手落在最高高度 + 全速（须在 add_child 之后，_ready 会重置 altitude/target_speed）
		ac.altitude = player_aircraft.altitude
		ac.target_altitude = player_aircraft.altitude
		var _wing_spd_kmh: float = AircraftPhysics.effective_max_speed_kmh(ac)
		ac.target_speed_kmh = _wing_spd_kmh
		ac.speed = _wing_spd_kmh / 3.6

		var ai := AIController.new()
		ai.name = "AI_Wing%d" % i
		ai.aircraft = ac
		ai.enable_combat = true
		ai.evade_missiles = true
		# ── 完美飞行员：所有僚机都完美执行战术，不受压力/技能退化影响 ──
		# skill_level=1 + composure=1 → effective_skill 永远是 1（见 _effective_skill 公式）
		# focus=1 → 永不分心，目标重评不会频繁切换
		# situational_awareness=1 → 态势感知满值
		# self_preservation 保留 0.5 以保证导弹来袭会做规避
		ai.aggression = 1.0
		ai.skill_level = 1.0
		ai.composure = 1.0
		ai.focus = 1.0
		ai.situational_awareness = 1.0
		ai.self_preservation = 0.5
		# 玩家僚机存在的目的就是给玩家打仗 —— 关掉 20s 强制脱离 + 15s 冷却
		# 默认值（20s/15s）是给敌方 AI 的"打打停停"节奏；给玩家僚机用就是 35s 周期里
		# 只有 20s 在交战、且会硬生生在 20s 把还没打死的目标抛掉。
		# 改为：交战到目标死或自己死，DISENGAGE 后 2s 即可再次引擎（让目标切换不那么粘）
		ai.engage_duration = 99999.0
		ai.engage_cooldown = 2.0
		ai.patrol_altitude = player_aircraft.altitude
		ac.add_child(ai)
		SquadFactory.register_wingman(sq, ac)  # squad/squad_index/_state=SQUAD_FOLLOW

		# 预置编队托管态：避免 frame 1 上 lod_level=0 + formation_mode=false 的默认值
		# 让飞机走 LOD 0 全模拟分支（target_position=INF 直行漂移）。
		# set_formation_target 一次性写 formation_mode/_formation_leader/lod=1/keep_arrival/target_position
		# blend / jitter_phase 已单边住 ai._formation_blend / ai._formation_jitter_phase（无需镜像）
		var initial_slot := sq.get_wingman_target(i)
		ac.set_formation_target(player_aircraft, initial_slot)
		# 若 F11 编队调试已开启，新生成的僚机也跟着开
		if _wingman_formation_debug:
			ac.formation_debug = true
	# 队伍登记已上移到 _ensure_player_squad（懒建队路径同样需要），此处不再重复 append

# ══════════════════════════════════════════════
#  编队调试（F11 切换覆盖层 / F12 状态快照）
# ══════════════════════════════════════════════

## F11：在所有友方僚机（team==0 且不是 player_aircraft）上切换 formation_debug 标志。
## 打开后每架僚机会绘制：
##   - 橙色 X 与连线 → 阵型槽位
##   - 蓝色射线 → 当前 heading
##   - 黄色射线 → 编队代码计算的目标 heading
##   - 文本 [BRANCH] slot_d hdg→Δ° bank→ blend spd
##   - 50px CLOSE_DIST 阈值圆
## 同时每架僚机每秒一次写入 EventLogger（F9 导出查看历史）。
func _toggle_wingman_formation_debug() -> void:
	_wingman_formation_debug = not _wingman_formation_debug
	var count := 0
	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or not ac.is_player_squad() or ac.is_destroyed:
			continue
		ac.formation_debug = _wingman_formation_debug
		ac._dbg_log_timer = 0.0  # 让下一帧立刻打一行
		count += 1
	var status := "ON" if _wingman_formation_debug else "OFF"
	print("[WingmanDebug] formation_debug=%s applied to %d wingmen" % [status, count])
	EventLogger.log_event("FORM_DBG", "Survivor", "F11 toggled formation_debug=%s on %d wingmen" % [status, count])

## F12：立即抓一帧友方僚机的编队状态快照，打印到控制台 + EventLogger。
## 不需要先按 F11；这是单次状态读取。
func _dump_wingman_formation_state() -> void:
	var lines := PackedStringArray()
	lines.append("=== Wingman Formation Snapshot @ %.1fs ===" % game_time)
	if player_aircraft and not player_aircraft.is_destroyed:
		lines.append("LEADER %s: pos=(%d,%d) hdg=%d bank=%+.0f° G=%.1f spd=%d alt=%d" % [
			player_aircraft.callsign,
			int(player_aircraft.global_position.x), int(player_aircraft.global_position.y),
			int(rad_to_deg(player_aircraft.heading)),
			rad_to_deg(player_aircraft.bank_angle),
			player_aircraft.g_load,
			int(player_aircraft.speed * 3.6),
			int(player_aircraft.altitude),
		])
	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or not ac.is_player_squad() or ac.is_destroyed:
			continue
		var slot_dist_str := "?"
		if ac._dbg_slot_pos != Vector2.INF:
			slot_dist_str = str(int(ac._dbg_slot_dist))
		lines.append("  %s: lod=%d fmode=%s branch=%s slot_d=%s hdg=%d→%d Δ%+.1f° bank=%+.0f°→%+.0f° spd=%d/%d G=%.1f" % [
			ac.callsign,
			ac.lod_level,
			"Y" if ac.formation_mode else "n",
			ac._dbg_branch if ac._dbg_branch != "" else "?",
			slot_dist_str,
			int(rad_to_deg(ac.heading)),
			int(rad_to_deg(ac._dbg_target_heading)),
			rad_to_deg(ac._dbg_hdiff),
			rad_to_deg(ac.bank_angle),
			rad_to_deg(ac._dbg_desired_bank),
			int(ac.speed * 3.6),
			int(ac._dbg_chase_target_kmh),
			ac.g_load,
		])
	for line in lines:
		print(line)
		EventLogger.log_event("FORM_DBG", "Snapshot", line)

# ══════════════════════════════════════════════
#  输入处理（与 main.gd 一致）
# ══════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	# SPACE：重新启用跟随（镜头平滑回到玩家并锁定，后续持续跟随）
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and player_aircraft and not player_aircraft.is_destroyed:
		get_viewport().set_input_as_handled()
		_camera_ctrl.set_follow_target(player_aircraft)
		_camera_ctrl.snap_to_follow()
		return
	# Tab：切换战术地图（暂停）
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		if _tactical_map:
			_tactical_map.toggle()
		return
	# 战术地图打开时，ESC 也用于关闭而不是退主菜单
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _tactical_map and _tactical_map.is_open():
		get_viewport().set_input_as_handled()
		_tactical_map.close()
		return
	# ESC 分流（spec pause-menu §3.1）：
	#   战局已结束（阵亡/胜利结算面板）→ 直接回主菜单（与结算面板"按 ESC 返回主菜单"提示一致）
	#   否则 → 打开暂停菜单（冻结全场 + 确认页），不再一键丢整局
	# ⚠ "ESC 关闭暂停菜单"由 PauseMenu 自己处理：硬暂停期间本节点收不到输入
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_paused_for_upgrade:
			return  # 选卡是必答题，不许用 ESC 绕过
		if _pause_menu and not is_game_over:
			_pause_menu.open()
			return
		_quit_to_main_menu()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		# 消费事件，避免编辑器调试器捕获 F9 进入断点/暂停状态
		get_viewport().set_input_as_handled()
		# 保险：若被其他机制设为暂停，立即解除。走时间栈而非直写 ——
		# 直写会让 TimeAuthority 仍以为处于暂停态，下次 hard_pause(true) 因状态相同被跳过
		if get_tree().paused and not is_paused_for_upgrade:
			Presentation.time.hard_pause(false)
		var path := EventLogger.dump_to_file()
		if path != "":
			print("Combat log saved: %s" % path)
		return
	# F10：跑 TacticalPlanner / BfmIntent 单元测试，结果输出到控制台
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		BfmIntentTest.run_all()
		return
	# F11：切换友方僚机的编队调试覆盖层
	# R：统一手动机动（眼镜蛇 / J-Turn / 胆大妄为）；未持有或冷却中静默。
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if player_aircraft and is_instance_valid(player_aircraft) and not is_paused_for_upgrade:
			player_aircraft.try_manual_maneuver()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		_toggle_wingman_formation_debug()
		return
	# F12：把当前所有友方僚机的编队状态打印到控制台 + EventLogger
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		_dump_wingman_formation_state()
		return
	# Boss Debug 模式专用热键
	if _boss_debug_mode and event is InputEventKey and event.pressed:
		if event.keycode == KEY_F7:
			get_viewport().set_input_as_handled()
			_boss_debug_toggle_invuln()
			return
		if event.keycode == KEY_F8:
			get_viewport().set_input_as_handled()
			_boss_debug_respawn_reroll()
			return
	if is_game_over or is_paused_for_upgrade:
		return
	# 战术面板快捷键
	if event is InputEventKey and event.pressed and player_aircraft and not player_aircraft.is_destroyed:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				# 切换操控对象到对应号机（spec squad-control-switching）。无小队/无对应号机=no-op。
				# 覆盖 1-9：编队上限 9（spec zone-reward-docking §2.5），奖励僚机能堆满，切控键须够到。
				_switch_control_to_slot(event.keycode - KEY_1 + 1)
				return
			KEY_Q:
				# 高度偏好 toggle（原 KEY_Z；对齐 HUD 按钮与 i18n 标签）
				if player_aircraft.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
					player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
				else:
					player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
				return
			KEY_T:
				# 武器优先 toggle（原 KEY_Q，Q 腾给高度偏好；对齐 HUD 按钮与 i18n 标签）
				if player_aircraft.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
					player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
				else:
					player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
				return
			KEY_E:
				# 加力模式（spec afterburner-mode，充能制）：有能量即可启动，激活中再按关闭。
				# 耗能耗尽自动结束（update 里判定）。启动内部仍走 set_evasion_mode 既有链路
				# （清指令 + planner max/AB + 僚机护卫广播 + radio break）
				if afterburner_charge.toggle(player_aircraft) and is_instance_valid(_tutorial):
					_tutorial.notify_afterburner()
				return
			KEY_F:
				player_aircraft.missile_auto_fire = not player_aircraft.missile_auto_fire
				return
			KEY_C:
				# 小队交战三态循环（自由→跟随→守护）；原 KEY_6 被上方 KEY_1..9 切控拦截成死分支 → 迁 C
				if hud:
					hud._on_squad_engage_pressed()
				return
			KEY_V:
				# 小队武器偏好（导弹 ↔ 机炮）；原 KEY_7 同上被切控拦截 → 迁 V
				if hud:
					hud._on_squad_weapon_pressed()
				return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_camera_ctrl.handle_zoom_input(1.0 + CameraController.ZOOM_STEP)
				if is_instance_valid(_tutorial): _tutorial.notify_zoom()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_camera_ctrl.handle_zoom_input(1.0 - CameraController.ZOOM_STEP)
				if is_instance_valid(_tutorial): _tutorial.notify_zoom()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(event.global_position)
			else:
				_on_left_release()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# 轮盘手势中按右键 = 中止轮盘（不触发取消命令/急刹）
				if _command_wheel and _command_wheel.abort_if_pending():
					return
				_on_right_click()
				_set_hard_brake(true)
			else:
				_set_hard_brake(false)
		MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			if event.pressed:
				drag_start = event.global_position

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		_camera_ctrl.handle_drag(event.relative)
		if is_instance_valid(_tutorial) and event.relative.length_squared() > 1.0:
			_tutorial.notify_pan()
	_camera_ctrl.update_hover(event.global_position, get_children())

## 左键按下：只做记录 + 交给轮盘手势仲裁（spec command-wheel §3.1）。
## 快速松开（< 呼出阈值）由 _on_left_release 按普通单击回放，参数以按下瞬间为准。
func _on_left_press(screen_pos: Vector2) -> void:
	# 任何左键操作都视为放弃急刹（防止右键 release 事件因 alt-tab 等丢失导致永久减速）
	_set_hard_brake(false)
	# 双击窗口检测保持按下间隔语义（窗口内第二次按下 = 冲锋，仅敌机有效）
	var now := Time.get_ticks_msec() / 1000.0
	_pending_click_double = (now - _last_left_click_time) <= DOUBLE_CLICK_WINDOW
	_last_left_click_time = now
	var world_pos := _camera_ctrl.screen_to_world(screen_pos)
	var enemy := _find_enemy_near(world_pos)
	if _command_wheel:
		_command_wheel.begin_press(screen_pos, world_pos, enemy)
	else:
		_execute_left_click(world_pos, enemy, _pending_click_double)

func _on_left_release() -> void:
	if not _command_wheel:
		return
	var res := _command_wheel.end_press()
	if res["outcome"] == CommandWheel.Outcome.CLICK:
		var tgt: CombatUnit = res["target"]
		if tgt != null and not is_instance_valid(tgt):
			tgt = null
		_execute_left_click(res["world_pos"], tgt, _pending_click_double)

## 既有单击语义（原 _on_left_click 的执行体，参数改为按下瞬间快照）
func _execute_left_click(world_pos: Vector2, enemy: CombatUnit, is_double_click: bool) -> void:
	# 点名敌方单位 → 玩家点名攻击命令（铁律目标，逻辑在 SquadCommandController）
	if enemy != null and is_instance_valid(enemy):
		if _squad_cmd:
			_squad_cmd.command_attack(enemy)  # 内部 set_combat_target + commanded_target + 清规避
		if is_double_click:
			# 双击冲锋：强制机炮 + 屏蔽导弹自动发射（输入时序留在 mode 层）
			for ac in selected_aircraft:
				if is_instance_valid(ac) and not ac.is_destroyed:
					ac.charge_attack = true
					# 722 sig_j36·三发推力：双击攻击线也算突击命令
					SkillHooks.try_trigger_j36_assault(ac)
			if is_instance_valid(_tutorial):
				_tutorial.notify_assault()
		if is_instance_valid(_tutorial): _tutorial.notify_click_attack()
		return

	# 无敌机：普通移动指令（自动关闭规避，放弃攻击命令）
	if _squad_cmd:
		_squad_cmd.command_move(world_pos)

## 轮盘命令入口：广播命令转发 _squad_cmd（轮盘=永远全队），开关翻转/显式设值 + HUD 同步。
## option 来自轮盘二级面板（"" = 直接在槽上松开 → 翻转；非空 = 显式选值）。
## 姿态差异（保持距离/突击）、防守盘旋拦截、撤离禁入区、加速注入按 spec 阶段 3-4 推进。
func _on_wheel_command(context: int, slot_id: String, world_pos: Vector2, target: CombatUnit, option: String) -> void:
	match slot_id:
		# ── 小队命令轮盘：位置命令 ──
		"regroup":
			if _squad_cmd: _squad_cmd.command_regroup(world_pos)
		"evac_area":
			if _squad_cmd: _squad_cmd.command_evacuate(world_pos)
		"guard_area":
			if _squad_cmd: _squad_cmd.command_guard(world_pos)
		# ── 小队命令轮盘：状态开关（与 HUD 战术栏同源字段，改后同步按钮文案）──
		"auto_engage":
			if player_aircraft and not player_aircraft.is_destroyed:
				var new_ae := not player_aircraft.auto_engage_enabled if option == "" else option == "on"
				player_aircraft.auto_engage_enabled = new_ae
				if hud: hud._update_tactical_buttons()
		"alt_pref":
			if player_aircraft and not player_aircraft.is_destroyed:
				var to_climb: bool
				if option == "":
					to_climb = player_aircraft.altitude_preference != Aircraft.AltitudePreference.PREFER_CLIMB
				else:
					to_climb = option == "climb"
				player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB \
						if to_climb else Aircraft.AltitudePreference.PREFER_LOW
				if hud: hud._update_tactical_buttons()
		"autofire":
			if player_aircraft and not player_aircraft.is_destroyed:
				var new_af := not player_aircraft.missile_auto_fire if option == "" else option == "on"
				# 轮盘 = 全队语法：广播到全队（F 键保持只切自机，两入口作用域刻意不同）
				if _squad_cmd:
					for ac in _squad_cmd._squad_members():
						if is_instance_valid(ac) and not ac.is_destroyed:
							ac.missile_auto_fire = new_af
				else:
					player_aircraft.missile_auto_fire = new_af
				if hud: hud._update_tactical_buttons()
		# ── 攻击轮盘：广播集火 + 姿态（spec §2.9/§3.5：STANDOFF 空中走 joust 打带跑、
		# 面目标走 surface pass 分流；ASSAULT = 锚定缠斗/俯冲扫射）──
		"standoff":
			if _squad_cmd: _squad_cmd.command_attack_all(target, Situation.POSTURE_STANDOFF)
		"assault":
			if _squad_cmd: _squad_cmd.command_attack_all(target, Situation.POSTURE_ASSAULT)
		# ── 攻击轮盘：队级战术状态 ──
		"fire_alloc":
			if _squad_cmd:
				var to_spread: bool
				if option == "":
					to_spread = _squad_cmd.fire_allocation == SquadCommandController.FireAllocation.FOCUS
				else:
					to_spread = option == "spread"
				_squad_cmd.fire_allocation = SquadCommandController.FireAllocation.SPREAD \
						if to_spread else SquadCommandController.FireAllocation.FOCUS
		"formation":
			if _squad_cmd:
				_squad_cmd.formation_tight = not _squad_cmd.formation_tight if option == "" else option == "tight"
	# 统一留痕（F9 战报可查每次轮盘操作）
	var ctx_name := "ATTACK" if context == CommandWheel.Context.ATTACK else "SQUAD"
	var tgt_name := "-"
	if target != null and is_instance_valid(target):
		tgt_name = str(target.callsign) if "callsign" in target else str(target.name)
	EventLogger.log_event("wheel", "player",
			"%s wheel -> %s%s @(%.0f, %.0f) target=%s" % [ctx_name, slot_id,
			("" if option == "" else ":" + option), world_pos.x, world_pos.y, tgt_name])

func _on_right_click() -> void:
	if _squad_cmd:
		_squad_cmd.cancel()

## 右键长按急刹（2026-07-03 用户定稿）：作用于全体 selected（整队一起减速），
## 但物理端有失速软地板（update_speed 急刹分支：减到 stall×1.05 最小可控速度为止，
## 刹不进失速 → **无法通过减速自杀坠机**，任何高度档都安全）；
## 减速率 = 各机自己的 params.deceleration × 随速度衰减的阻力因子
## （高速段刹得动、低速段效率自然变差，低级机天然刹得肉）。验收：--bench=hard_brake。
## 持续到松开右键；期间保持航向（target_position 已被 _on_right_click 清成 INF）
func _set_hard_brake(active: bool) -> void:
	for ac in selected_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.hard_brake = active

func _find_enemy_near(world_pos: Vector2) -> CombatUnit:
	# 第一优先级：常规可锁定目标（飞机、地面单位）—— 用 HOVER_RADIUS 精确判定
	var best_dist := CameraController.HOVER_RADIUS
	var best: CombatUnit = null
	# 第二优先级：船体范围内点击 —— 自动选择该船最近的 MountTarget 代理
	# 跳过锁定免疫的目标（NavalUnit 船体）—— 雷达循环不累积它的 radar_targets，
	# 直接锁船会导致导弹发射逻辑看不到锁定进度。船体由下面的 ship_in_range 单独处理。
	var ship_in_range: NavalUnit = null
	var ship_dist_sq := INF
	var mother_goose_in_range: Aircraft = null
	for child in get_children():
		if child is CombatUnit and child.team == CombatUnit.TEAM_HOSTILE and not child.is_destroyed:
			if child is NavalUnit:
				var dh := _distance_to_ship_hull(child, world_pos)
				if dh <= 0.0:
					# 落在船身矩形内：按船中心距离取最近的一艘
					var dc2: float = world_pos.distance_squared_to(child.global_position)
					if dc2 < ship_dist_sq:
						ship_dist_sq = dc2
						ship_in_range = child
				continue
			if child is Aircraft and child.get_meta("enemy_type", "") == "mother_goose" \
					and _is_inside_mother_goose_hull(child, world_pos):
				mother_goose_in_range = child
				continue
			if child.is_lock_immune():
				continue
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	## 巨型飞翼本体覆盖其上的普通 UAV：用户明确点中机身时，优先解释为攻坚挂点命令。
	if mother_goose_in_range != null:
		return _find_nearest_mount_target_on(mother_goose_in_range, world_pos)
	if best != null:
		return best
	if ship_in_range != null:
		return _find_nearest_mount_target_on(ship_in_range, world_pos)
	return null

## Mother Goose 飞翼可点击区域（与 renderer 的 9× 图标近似包围盒一致）。
## 本体锁定免疫时，点击机身只用于把命令转发到最近的可攻击 MountTarget。
func _is_inside_mother_goose_hull(goose: Aircraft, world_pos: Vector2) -> bool:
	var local: Vector2 = world_pos - goose.global_position
	var fwd := Vector2(sin(goose.heading), -cos(goose.heading))
	var stb := Vector2(cos(goose.heading), sin(goose.heading))
	return absf(local.dot(stb)) <= 225.0 and absf(local.dot(fwd)) <= 85.0

## 点击位置到舰船船体矩形（hull_length × hull_width）的最短距离
## 落在矩形内返回 0，外面返回正距离
func _distance_to_ship_hull(ship: NavalUnit, world_pos: Vector2) -> float:
	if ship.params == null:
		return INF
	var local := world_pos - ship.global_position
	var fwd := Vector2(sin(ship.heading), -cos(ship.heading))
	var stb := Vector2(cos(ship.heading), sin(ship.heading))
	var local_y := local.dot(fwd)   # +Y 船头方向（船头 +half_l）
	var local_x := local.dot(stb)   # +X 右舷方向
	var half_l: float = ship.params.hull_length * 0.5
	var half_w: float = ship.params.hull_width * 0.5
	var dx := maxf(0.0, absf(local_x) - half_w)
	var dy := maxf(0.0, absf(local_y) - half_l)
	return sqrt(dx * dx + dy * dy)

## 在指定母体的所有 MountTarget 代理（挂点 + 暴露弱点）中找离 world_pos 最近的。
## MountTarget 是 survivor_mode 的子节点（不挂在母体下，避免 rotation 干扰）。
func _find_nearest_mount_target_on(ship: CombatUnit, world_pos: Vector2) -> CombatUnit:
	var best: CombatUnit = null
	var best_d2 := INF
	for child in get_children():
		if not (child is MountTarget):
			continue
		var mt: MountTarget = child
		if mt.is_destroyed or mt.parent_ship != ship:
			continue
		var d2: float = world_pos.distance_squared_to(mt.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = mt
	return best


# ══════════════════════════════════════════════
#  RTS 指挥：战术地图信号转发 → SquadCommandController
#  指挥逻辑（命令/自动交战）全在 scripts/rts/squad_command_controller.gd
#  设计见 docs/specs/systems/rts-command.md
# ══════════════════════════════════════════════

## 战术地图点空白处 → 下达巡航航点（精确世界坐标）。
func _on_nav_point_selected(world_pos: Vector2) -> void:
	if _squad_cmd:
		_squad_cmd.command_move(world_pos)

## 战术地图右键：取消当前巡航/攻击指令。
func _on_nav_cleared() -> void:
	if _squad_cmd:
		_squad_cmd.cancel()


# ══════════════════════════════════════════════
#  主循环
# ══════════════════════════════════════════════

func _process(delta: float) -> void:
	_camera_ctrl.update(delta)
	# WASD 自由镜头也算完成"平移"教程项
	if is_instance_valid(_tutorial) and (
			Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A)
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)):
		_tutorial.notify_pan()
	_cleanup_references()
	if _bench_mode and not _bench_finished:
		_bench_wall_watchdog()
	# MapFeatureRenderer 自己每帧 queue_redraw，不需要在这里触发
	# ⚠ _update_aircraft_list() + _update_radar_locks() 已迁移到 _physics_process —
	#   原因：_process 是渲染帧率，窗口失焦 / Alt-Tab / 最小化时 Godot 会把它节流到
	#   1-30Hz，单次 delta 可达 0.5-1.0s。雷达进度按 delta 累积 + RADAR_LOCK_STRIDE×4
	#   倍率 → 一次 tick 灌进 4s 的锁定时间，玩家看到"切出画面后导弹瞬间发射"。
	#   _physics_process 固定 60Hz 不受焦点影响，是正确的累积时基。

func _physics_process(delta: float) -> void:
	if is_game_over or is_paused_for_upgrade:
		return
	if _bench_scenario == "survivor_death":
		_bench_update_survivor_death()

	# 加力充能/窗口计时（spec afterburner-mode）：放早退之后 → 升级暂停/游戏结束自然冻结
	# 722 签名技能充能倍率：公路机场（鹰狮 C·ACE 未被锁 ×1.5）/ 地形跟随（狂风·ACE 低空 ×1.5）
	var sig_ab_rate: float = 1.0
	if player_aircraft and is_instance_valid(player_aircraft) and not player_aircraft.is_destroyed:
		if int(upgrade_stacks.get("sig_gripen_c", 0)) > 0 and not player_aircraft.is_locked:
			sig_ab_rate *= 1.5
		if player_aircraft.sig_tornado_active \
				and player_aircraft.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
			sig_ab_rate *= 1.5
	var storm_ii_active: bool = int(upgrade_stacks.get("storm_ii", 0)) > 0 \
		and player_aircraft != null and is_instance_valid(player_aircraft) \
		and not player_aircraft.is_destroyed and player_aircraft.status_overload_active
	afterburner_charge.update(delta, sig_ab_rate, storm_ii_active)

	# 720 批：僚机阵亡事件（复仇之战/刺客复仇/黑匣子回收）+ 奖励升级弹窗顺延
	_tick_squad_watch(delta)

	# BOSS 阶段后 game_time 不再累加（HUD 自然停在 00:00 / "BOSS PHASE"）
	if not _is_in_boss_phase():
		game_time += delta
	# 雷达锁定累积放在物理帧（固定 60Hz）：失焦/最小化时不会因 _process 大 delta 暴涨。
	# 必须在所有 AI/武器子系统之前跑，因为 update_missile 读 radar_targets 决定开火。
	_update_aircraft_list()
	# 友军据点仇恨固定 1 Hz；复用刚生成的全单位缓存，不另做场景树扫描。
	_friendly_asset_aggro.tick(delta, player_aircraft, _all_combat_units_cache)
	_update_radar_locks(delta)
	# RTS 自动交战：到点/空闲时长机自动锁最近敌机（僚机经 SquadCoordination 跟打）
	if _squad_cmd:
		_squad_cmd.tick(delta)

	# 战场引力上下文低频刷新（spec battlefield-gravity §2.4：BOSS 质心 / 最近 triggered 战区 / 兜底操控机）
	_update_objective_context(delta)

	# 动态性能控制
	_spawner.update_fps_sampling(delta)
	_update_offscreen_lod()
	_update_friendly_squad_lod()

	# 战区结算改停靠制（spec zone-reward-docking §2.2）：攻克后不再自动弹结算面板——
	# _evolution_pending 仅作"有新结算内容"标记；面板由停靠点 docked → _on_dock_docked 打开。
	# （旧行为：此处首个未暂停帧自动 _open_evolution_offer，2026-07-06 移除）

	# 检查玩家是否死亡
	if player_aircraft and player_aircraft.is_destroyed and not is_game_over:
		# 长机被击坠 → 先尝试接管存活僚机（squad-control-switching：全队覆灭才 GameOver）。
		# 不能等 spawner 的 3s 周期 cleanup（那在本死亡检查之后、且节流），否则总是先 GameOver。
		if not _try_takeover_after_leader_down():
			_on_player_died()
		return

	# 刷怪系统（击杀检测/刷怪/猎手/航点/远距清理/分队清理 全部委托给 spawner）
	# Boss Debug 模式跳过：不刷杂兵 / 不分配猎手 / 不重写敌机航点（仅 boss 在场）
	if not _boss_debug_mode:
		_spawner.update(delta)
		if _bench_scenario == "evolution_growth" and _growth_bench != null:
			_growth_bench.tick(delta)
		# ALLY 第三方事件调度（AWACS 支援 / 护送任务，spec global-awareness-roe §2.6）
		_update_ally_events(delta)
		# 敌方王牌支援中队调度（spec events/ace-support-squadron）
		_update_ace_support_event(delta)
		_update_orion_event()

	# 战区阶段倒计时检查（10 分钟到点 → 关闭其他战区 / 解锁 BOSS）
	if not _boss_debug_mode and not _bench_mode:
		_check_warzone_phase_timeout()

	# BOSS 阶段：10 分钟到点（或当前 SELECTED 战区结算后）解锁 BOSS，刷 F-47 小队 + 胜利判定
	# Boss Debug / Bench 模式跳过：boss_debug 走 BossEncounterEvent，bench 不需要战区驱动
	if not _boss_debug_mode and not _bench_mode:
		_update_boss_phase()

	# 清理已坠毁的敌机（节省性能）
	_cleanup_destroyed_enemies()

	# Bench 倒计时：duration 到点 → 回调 BenchRunner 写 dump + quit
	# 用 path 查 autoload 而非裸 `BenchRunner.xxx()` —— 后者依赖编辑器静态识别 autoload，
	# 项目重载前会报 "Identifier not declared"。get_node_or_null 在 headless / 编辑器
	# 都能稳定工作，且 BenchRunner 没注册时静默 no-op
	# demo 模式：不计时退出，改为持续补充敌人，供长时间观察小队战斗
	if _bench_demo:
		_bench_demo_topup_timer -= delta
		if _bench_demo_topup_timer <= 0.0:
			_bench_demo_topup_timer = 6.0
			if _spawner and _count_enemy_alive() < 8:
				_bench_force_spawn_mixed(6)
	elif _bench_mode and not _bench_finished:
		_bench_elapsed += delta
		if _bench_elapsed >= _bench_duration:
			var summary: String
			if _bench_scenario == "evolution_growth" and _growth_bench != null:
				summary = _growth_bench.finish("duration")
			else:
				summary = "tick_at=%.2fs aircraft_alive=%d enemies_killed=%d\n" % [
					_bench_elapsed, _count_aircraft_alive(), (_spawner.kill_count if _spawner else 0)]
			# boss_mother_goose scenario：附加 boss 终态信息
			if _bench_scenario == "boss_mother_goose" and _spawner and _spawner._boss:
				var boss: BossEncounter = _spawner._boss
				var boss_alive: bool = boss.active and boss.boss_unit != null \
						and is_instance_valid(boss.boss_unit) and not boss.boss_unit.is_destroyed
				var boss_hp_pct: float = 0.0
				if boss.boss_unit and is_instance_valid(boss.boss_unit) and boss.boss_unit.params:
					boss_hp_pct = boss.boss_unit.hp / maxf(boss.boss_unit.params.max_hp, 1.0) * 100.0
				summary += "boss=MOTHER_GOOSE alive=%s hp_pct=%.1f%%\n" % [
					"YES" if boss_alive else "NO (defeated)", boss_hp_pct]
			_bench_finish_now(summary)

	# 更新HUD
	hud.game_time = game_time
	hud.kill_count = _spawner.kill_count
	# 战区阶段倒计时（在 BOSS 阶段切换为"BOSS PHASE"文案，game_time 已冻结）
	var _remaining: float = maxf(0.0, WARZONE_PHASE_DURATION - game_time)
	hud.set_warzone_remaining(_remaining, _is_in_boss_phase())

func _cleanup_references() -> void:
	var valid: Array[Aircraft] = []
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			valid.append(ac)
	selected_aircraft = valid

func _update_aircraft_list() -> void:
	var all_aircraft: Array[Aircraft] = []
	var all_units: Array[CombatUnit] = []
	# Perf 计数（按 CombatUnit 子类分桶，看 all_units 的真实膨胀来源）
	var n_ac: int = 0
	var n_gr: int = 0
	var n_nv: int = 0
	var n_mt: int = 0
	for child in get_children():
		if child is Aircraft:
			all_aircraft.append(child)
			all_units.append(child)
			n_ac += 1
		elif child is GroundUnit:
			all_units.append(child)
			n_gr += 1
		elif child is NavalUnit:
			all_units.append(child)
			n_nv += 1
		elif child is CombatUnit:
			# 兜底：MountTarget 等不是 Aircraft/GroundUnit/NavalUnit 的 CombatUnit 子类
			# 它们是船上挂点的锁定代理，必须进 all_units 才能被雷达锁定循环看见
			# （NavalUnit 船体 is_lock_immune=true，玩家锁的是 mount 而不是船本身；
			#  从 all_units 摘掉 mount 会让 radar_targets[mount] 永远累不到 → 玩家彻底
			#  无法对船开火。曾尝试摘除已回滚。深度 ship-level 雷达重构需要同时改写
			#  lock_immune / 导弹 firing block 路径，改动量很大）
			all_units.append(child)
			n_mt += 1
	bullet_manager.combat_unit_list = all_units
	missile_manager.target_list = all_units
	_all_combat_units_cache = all_units
	CombatUnit.all_units = all_units  # AI / 武器扫描共享引用，消灭多处 get_children() 扫描

	# Perf 快照：all_units 分类 + 衍生 AI 拥挤度（驱动 ai_controller 的 effective_divisor）
	# 这样在 HUD / F9 dump 里能直接看到 "MountTarget 把 N 推到 50 → AI 全员降频" 这类因果链
	var n_total: int = all_units.size()
	PerfBuckets.set_value("all_units.total", n_total)
	PerfBuckets.set_value("all_units.aircraft", n_ac)
	PerfBuckets.set_value("all_units.naval", n_nv)
	PerfBuckets.set_value("all_units.ground", n_gr)
	PerfBuckets.set_value("all_units.mount_target", n_mt)
	var crowd_t: float = 0.0
	if n_total > AIController.CROWD_THRESHOLD_LOW:
		crowd_t = clampf(
			float(n_total - AIController.CROWD_THRESHOLD_LOW)
			/ float(AIController.CROWD_THRESHOLD_HIGH - AIController.CROWD_THRESHOLD_LOW),
			0.0, 1.0)
	PerfBuckets.set_value("ai.crowd_t", crowd_t)
	# 把"基础 divisor=3 在当前拥挤度下的有效 divisor"算出来贴标签
	# （ai_controller._physics_process 里同样的 ceil(base × lerp(1, max_mult, crowd_t)) 公式）
	PerfBuckets.set_value("ai.normal_div_at_base3",
		int(ceil(3.0 * lerpf(1.0, AIController.NORMAL_MAX_MULT, crowd_t))))
	PerfBuckets.set_value("ai.cheap_div_at_base3",
		int(ceil(3.0 * lerpf(1.0, AIController.CHEAP_MAX_MULT, crowd_t))))

func _update_radar_locks(delta: float) -> void:
	# 节流：每 RADAR_LOCK_INTERVAL 秒跑一次 O(N²) 循环
	# 锁定时间 2-4s，0.2s 粒度对玩家不可感知，却把这段最重的循环从 60Hz 降到 5Hz
	_radar_lock_accum += delta
	if _radar_lock_accum < RADAR_LOCK_INTERVAL:
		return
	var _perf_t0: int = Time.get_ticks_usec()
	var _perf_pairs: int = 0
	var step_delta := _radar_lock_accum
	_radar_lock_accum = 0.0
	# 防御：单次累积超过 2× 周期视为异常大 delta（窗口失焦 / 物理帧暂停后恢复）。
	# 不 clamp 会让 per_shooter_delta = step_delta×STRIDE 灌入数秒锁定进度。
	# 阈值取 RADAR_LOCK_INTERVAL × 2 = 0.4s（正常 60Hz 下永远不到 0.2s+1 帧）
	var max_step: float = RADAR_LOCK_INTERVAL * 2.0
	if step_delta > max_step:
		EventLogger.log_event("RADAR_TICK", "survivor",
			"step_delta=%.2fs clamped to %.2fs（疑似失焦/暂停恢复）" % [step_delta, max_step])
		step_delta = max_step

	# 复用 _update_aircraft_list 已经构建的列表
	var all_units := _all_combat_units_cache

	for unit in all_units:
		# 守卫：cache 跨帧静态，单位可能在 _update_aircraft_list 之后被 queue_free
		if not is_instance_valid(unit):
			continue
		unit.is_locked = false
		unit.locked_by.clear()
		unit.incoming_lock_progress = 0.0

	# 子集轮转：本 tick 只把 phase ≡ i % STRIDE 的 shooter 当雷达发起方扫一遍
	# 累积速率 × STRIDE 抵消频率（保证 lock_time 体感不变）
	var phase := _radar_lock_phase
	_radar_lock_phase = (_radar_lock_phase + 1) % RADAR_LOCK_STRIDE
	var per_shooter_delta := step_delta * float(RADAR_LOCK_STRIDE)

	for i in range(all_units.size()):
		if i % RADAR_LOCK_STRIDE != phase:
			continue
		var unit: CombatUnit = all_units[i]
		if not is_instance_valid(unit):
			continue
		# MountTarget 不当雷达发起方：它的 radar_targets 字典永远为空（挂点武器获取
		# 走 weapon_mount.acquire_cooldown 自己的扫描），跑这一圈纯属浪费 N 次配对。
		# 仍保留它作为 victim 让飞机能锁/打它（玩家锁船依赖此路径，不能动）。
		if unit is MountTarget:
			continue
		var keys_to_remove: Array = []
		for key in unit.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			unit.radar_targets.erase(key)

		# JAM 状态：被干扰者完全无法累积锁定（飞机 + 地面单位 SAM/AA 等）
		if unit.status_jam_active:
			unit.radar_targets.clear()
			continue

		for other in all_units:
			_perf_pairs += 1  # 雷达对计数（含早 filter 部分；后续 reverse-engineer N²/STRIDE 用）
			if not is_instance_valid(other) or other == unit or not unit.is_hostile_to(other):
				continue
			# Snowblind 传感器幕：复用既有 5Hz O(N²) 配对，禁止另开全场扫描。
			if unit.is_sensor_engagement_obscured(other):
				unit.radar_targets.erase(other)
				continue
			# 锁定免疫期间：无法对该目标累积雷达照射
			if other.is_lock_immune():
				unit.radar_targets.erase(other)
				continue
			var in_cone := unit.is_in_radar_cone(other.global_position)
			# ECM 吊舱（战区奖励）：目标自身缩短敌方雷达有效距离
			if in_cone and other is Aircraft and other.ecm_range_mult < 1.0 \
					and unit.params and "radar_range" in unit.params:
				var ecm_range: float = unit.params.radar_range * other.ecm_range_mult
				if unit.global_position.distance_to(other.global_position) > ecm_range:
					in_cone = false
			if in_cone:
				# 低空飞机更难锁定（地面单位不受此影响）
				var lock_rate := _lock_rate_for_target(other)
				# AWACS 支援 buff：区内玩家小队锁定速率 ×3（spec global-awareness-roe §2.6c；
				# 每帧仅玩家小队 shooter 多一次距离比较，静态注册表 validity 自守卫）
				if unit is Aircraft and unit.is_player_squad():
					lock_rate *= AwacsSupportEvent.lock_rate_mult_for(unit)
					lock_rate *= unit.esm_lock_rate_multiplier()
				# 云层锁定衰减：
				#   - 默认：HIGH 档在云里 ×0.5
				#   - 云雾机动（战区奖励）：任意档位云里 ×0.1（近乎无法锁定）
				if _weather and _cached_is_in_cloud(other):
					if other is Aircraft and other.cloud_lock_stealth:
						lock_rate *= 0.1
					elif other.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
						lock_rate *= 0.5
				# 目标自身的锁定抗性（强化吊舱升级）
				if other is Aircraft and other.lock_resistance_mult > 1.0:
					lock_rate /= other.lock_resistance_mult
				# ── 722 批签名技能：锁定管线集中注入（spec aircraft-signature-skills）──
				if unit is Aircraft:
					var sig_u := unit as Aircraft
					# 无败之鹰（F-15）：HP≥90% 时锁定速率 ×1.3
					if sig_u.sig_f15_active and sig_u.params \
							and sig_u.hp >= sig_u.params.max_hp * Aircraft.SIG_F15_HP_RATIO:
						lock_rate *= Aircraft.SIG_F15_BONUS_MULT
					# 制空清扫（F-15C）：锥内每多 1 个照射中目标 +8%，cap +40%
					if sig_u.sig_f15c_active:
						var extra_n: int = maxi(sig_u.radar_targets.size() - 1, 0)
						lock_rate *= 1.0 + minf(0.08 * float(extra_n), 0.40)
					# 对地特化（F-15E）：对地面/舰船/挂点锁定 ×1.5
					if sig_u.sig_f15e_active and not (other is Aircraft):
						lock_rate *= 1.5
					# 唯一的锁定（Viggen）：重新入锥 → 清除该目标的出锥 grace 计时
					if sig_u.sig_lock_retention_sec > 0.0 and not sig_u._sig_lock_grace.is_empty():
						sig_u._sig_lock_grace.erase(other.get_instance_id())
				if other is Aircraft:
					var sig_o := other as Aircraft
					# 盲飞入侵（A-6E）：低空时敌方锁我 ×0.6（字段仅玩家小队会置位）
					if sig_o.sig_a6e_active and sig_o.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
						lock_rate *= 0.6
					# 近太空冲刺（MiG-41）：高空时敌方锁我 ×0.6
					if sig_o.sig_mig41_active and sig_o.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
						lock_rate *= 0.6
				# §C 玩家技能"高度变化时更难锁"：仅作用于玩家被锁路径
				# alt_velocity_norm = clamp(_alt_velocity / max_climb, 0..1)，rate ×= 1 − norm × factor
				if other is Aircraft and other.is_player_squad() and other.alt_change_stealth_factor > 0.0 and other.params:
					var max_climb: float = maxf(other.params.climb_rate_max, 1.0)
					var alt_v_norm: float = clampf(other._alt_velocity / max_climb, 0.0, 1.0)
					lock_rate *= maxf(1.0 - alt_v_norm * other.alt_change_stealth_factor, 0.1)
				# §C 玩家技能"最高度锁定加快"：仅作用于玩家锁敌路径
				if unit is Aircraft and unit.is_player_squad() and unit.high_alt_lock_speed_bonus > 0.0:
					if unit.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
						lock_rate *= (1.0 + unit.high_alt_lock_speed_bonus)
				# 斗士稳定技能“近距捕获”：复用当前 O(N²) 锁定循环，不新增扫描或 process。
				if unit is Aircraft and unit.is_player_squad() and unit.close_range_lock_max_mult > 1.0:
					lock_rate *= SurvivorData.close_range_lock_mult(
						unit.global_position.distance_to(other.global_position),
						unit.effective_radar_range_px(),
						unit.close_range_lock_max_mult)
				# 硬下限：保证 effective_lock_time = threshold / rate ≤ MAX_EFFECTIVE_LOCK_TIME_S
				var shooter_threshold: float = unit.params.lock_time if unit.params else 3.0
				var min_rate: float = shooter_threshold / CombatUnit.MAX_EFFECTIVE_LOCK_TIME_S
				if lock_rate < min_rate:
					lock_rate = min_rate
				var prev: float = unit.radar_targets.get(other, 0.0)
				# 锁定进度封顶 = 阈值 + 稳定缓冲。哑 AI 发射需 threshold+LOCK_STABLE_BUFFER，
				# 不能 cap 到 threshold 否则饿死其发射；但必须封顶，杜绝无上限累积让
				# "盯得久=分高"碾压目标选择的可命中性评分（spec target-engageability-selection §2.2）。
				var lock_cap: float = shooter_threshold + Aircraft.LOCK_STABLE_BUFFER
				unit.radar_targets[other] = minf(prev + per_shooter_delta * lock_rate, lock_cap)
				# §C 玩家技能"被你锁定的敌人累积恐惧"：仅 unit==玩家 + other 是飞机
				# 累积模式：状态期间不累积；累积满 → 施 FEAR → 归零；状态消退后重新累积
				if unit is Aircraft and unit.is_player_squad() \
						and unit.fear_on_lock_threshold > 0.0 \
						and other is Aircraft and unit.is_hostile_to(other):
					var oid: int = other.get_instance_id()
					# 关键修复：目标已有 FEAR 时跳过累积，等状态消退后再开始
					if not other.status_effects.has(StatusEffects.FEAR):
						var sec: float = float(unit._locked_target_seconds.get(oid, 0.0)) + per_shooter_delta
						unit._locked_target_seconds[oid] = sec
						if sec >= unit.fear_on_lock_threshold:
							AOEBroadcast.apply_status_in_radius(
								other.global_position, 50.0, 1, StatusEffects.FEAR, 6.0, unit)
							unit._locked_target_seconds[oid] = 0.0
			else:
				# 不在锥内：极短衰减（0.3 秒）—— 仅挡住雷达锥边缘 1-2 帧的几何抖动；
				# 不再做长记忆，避免脱离照射的"幽灵锁定"被 _fire_multi_lock_salvo
				# 继续当目标发弹（玩家观感"导弹乱射"）。SARH 物理上也是不照射即丢锁。
				var prev: float = unit.radar_targets.get(other, 0.0)
				# 唯一的锁定（722 sig_viggen）：已满锁目标出锥后先冻结 grace 秒不衰减
				if prev > 0.0 and unit is Aircraft and (unit as Aircraft).sig_lock_retention_sec > 0.0:
					var sig_vg := unit as Aircraft
					var vg_oid: int = other.get_instance_id()
					var vg_grace: float = float(sig_vg._sig_lock_grace.get(vg_oid, -1.0))
					if vg_grace < 0.0:
						# 出锥沿：仅满锁目标授予 grace（半锁不给，防蹭锁）
						var vg_thr: float = sig_vg.params.lock_time if sig_vg.params else 3.0
						vg_grace = sig_vg.sig_lock_retention_sec if prev >= vg_thr else 0.0
					vg_grace -= per_shooter_delta
					if vg_grace > 0.0:
						sig_vg._sig_lock_grace[vg_oid] = vg_grace
						continue  # 冻结期：进度不衰减（fear 累积同样视为仍在锁定，不清零）
					sig_vg._sig_lock_grace.erase(vg_oid)
				if prev > 0.0:
					unit.radar_targets[other] = prev - per_shooter_delta / 0.3
					if unit.radar_targets[other] <= 0.0:
						unit.radar_targets.erase(other)
				else:
					unit.radar_targets.erase(other)
				# 离开锥外清零累积（让玩家必须持续锁定才能触发）
				if unit is Aircraft and unit.is_player_squad() and unit.fear_on_lock_threshold > 0.0 \
						and other is Aircraft:
					unit._locked_target_seconds.erase(other.get_instance_id())

	# ── 数据链光环（F-14）：team 0 飞机间共享 radar_targets（取每个目标最大照射时间） ──
	# 队友锁的玩家也算锁；玩家锁的队友也算锁。jam 中的飞机不参与共享（被干扰雷达失能）。
	# 注意：发射仍受 cone / envelope / range 校验（aircraft_weapons.gd），不会出现"看不见就开火"。
	# 队级账本判定（skills-720 T0 缺口①根治：切控/换帅后共享不再静默关闭）
	if player_aircraft and not player_aircraft.is_destroyed \
			and player_aircraft is Aircraft and int(upgrade_stacks.get("data_link", 0)) > 0:
		var team0_ac: Array = []
		for u in all_units:
			if u is Aircraft and u.is_player_squad() and not u.is_destroyed and not u.status_jam_active:
				team0_ac.append(u)
		if team0_ac.size() >= 2:
			var max_progress: Dictionary = {}
			for ally in team0_ac:
				for t in ally.radar_targets:
					if not is_instance_valid(t):
						continue
					var p: float = ally.radar_targets[t]
					if p > max_progress.get(t, 0.0):
						max_progress[t] = p
			for ally in team0_ac:
				for t in max_progress:
					var v: float = max_progress[t]
					if ally.radar_targets.get(t, 0.0) < v:
						ally.radar_targets[t] = v

	# F-14 围猎 / EA-18G 伴随压制：全部存活僚机共同满锁同一敌机 → 持续刷新 SLOW / JAM。
	# 结构真源只读 Squad.members；至少 1 名僚机，ACE 自己不参与共锁交集。
	if player_aircraft and not player_aircraft.is_destroyed \
			and player_aircraft is Aircraft \
			and (int(upgrade_stacks.get("f14_squad_lock_slow", 0)) > 0 \
				or int(upgrade_stacks.get("sig_ea18g", 0)) > 0):
		var wingmen: Array[Aircraft] = []
		if _squad != null:
			for member in _squad.members:
				if member is Aircraft and member != player_aircraft and is_instance_valid(member) \
						and not member.is_destroyed and not member.status_jam_active:
					wingmen.append(member)
		if not wingmen.is_empty():
			# 从第一名僚机的满锁目标开始求交集；每机使用自己的 lock_time。
			var common_locks: Dictionary = {}
			var first: Aircraft = wingmen[0]
			var first_thresh: float = first.params.lock_time if first.params else 3.0
			for tgt in first.radar_targets:
				if not is_instance_valid(tgt) or tgt.team != CombatUnit.TEAM_HOSTILE:
					continue
				if float(first.radar_targets[tgt]) >= first_thresh:
					common_locks[tgt] = true
			for ally in wingmen.slice(1):
				var ally_thresh: float = ally.params.lock_time if ally.params else 3.0
				var to_keep: Dictionary = {}
				for tgt in common_locks:
					if float(ally.radar_targets.get(tgt, 0.0)) >= ally_thresh:
						to_keep[tgt] = true
				common_locks = to_keep
				if common_locks.is_empty():
					break
			# 仅当交集恰好为 1（"全僚机聚焦同一目标"）才触发。
			if common_locks.size() == 1:
				var the_target: CombatUnit = common_locks.keys()[0]
				if the_target is Aircraft:
					if int(upgrade_stacks.get("f14_squad_lock_slow", 0)) > 0:
						the_target.apply_status(StatusEffects.SLOW, 3.0)
					if int(upgrade_stacks.get("sig_ea18g", 0)) > 0:
						the_target.apply_status(StatusEffects.JAM, 3.0)

	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		var lock_time_val: float
		if unit is Aircraft and unit.params:
			lock_time_val = unit.params.lock_time
			# 侩子手：玩家锁定时间 ×0.90/层
			lock_time_val *= unit._executioner_lock_mult()
		elif unit is GroundUnit and unit.params:
			lock_time_val = unit.params.lock_time
		else:
			lock_time_val = 3.0
		for target in unit.radar_targets:
			if not is_instance_valid(target):
				continue
			var t: CombatUnit = target
			var progress: float = clampf(unit.radar_targets[target] / lock_time_val, 0.0, 1.0)
			if progress > t.incoming_lock_progress:
				t.incoming_lock_progress = progress
			if unit.radar_targets[target] >= lock_time_val:
				t.is_locked = true
				t.locked_by.append(unit)

	# 限制同时飞向玩家的导弹数量（最多 SurvivorSpawner.MAX_MISSILES_TARGETING_PLAYER）
	if player_aircraft and missile_manager:
		var missiles_at_player := _count_missiles_targeting_player()
		if missiles_at_player >= SurvivorSpawner.MAX_MISSILES_TARGETING_PLAYER:
			# 阻止更多敌机对玩家发射导弹：清除尚未发射的敌机对玩家的锁定
			# 只清除那些还没有在飞导弹指向玩家的敌机的锁定
			for ac in _get_enemies_without_active_missile_at_player():
				var lock_val: float = ac.radar_targets.get(player_aircraft, 0.0)
				var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
				if lock_val >= lock_time_val:
					# 将锁定进度压回刚好低于锁定阈值，阻止发射但保持追踪
					ac.radar_targets[player_aircraft] = lock_time_val - 0.5

	# Perf 收尾：本 tick 总耗时 + 总评估对数（O(N²)/STRIDE 验证用）
	PerfBuckets.tick("radar_locks", Time.get_ticks_usec() - _perf_t0)
	PerfBuckets.count("radar_pairs", _perf_pairs)

## 云层采样缓存（0.3s 有效期 + 位置 >200px 自动失效）
## 雷达锁定循环对每个 HIGH 目标都会查云，节流后仍是 10+ 次/tick，缓存消除噪声采样开销
func _cached_is_in_cloud(unit: CombatUnit) -> bool:
	if not _weather:
		return false
	var now := game_time
	var pos := unit.global_position
	if now - unit._cloud_cache_time < 0.3 and pos.distance_squared_to(unit._cloud_cache_pos) < 40000.0:
		return unit._cloud_cache_result
	unit._cloud_cache_time = now
	unit._cloud_cache_pos = pos
	unit._cloud_cache_result = _weather.is_in_cloud(pos)
	return unit._cloud_cache_result

## 低空飞行目标锁定速率衰减（仅对 Aircraft 生效；地面单位恒定 1.0）
static func _lock_rate_for_target(target: CombatUnit) -> float:
	if not (target is Aircraft):
		return 1.0
	if target.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
		return 0.7
	return 1.0

## simple_ai 敌机的"全速物理"预算：最近 N 架每帧跑，超出名额的隔帧跑
## 人海战术（大量 UAV）场景下这是最关键的 CPU 节流开关，可按性能需求调
const SIMPLE_AI_FULL_TICK_BUDGET := 6

## 远距冻结距离²：屏幕外 + 距玩家 > 此距离的敌方 AI 完全停 _physics_process（2026-05-04 加入）
## 1500 米（PIXELS_PER_METER=0.5 → 750 像素 → 750² = 562500）
## 进屏幕或回到 < 1500m 时 _update_offscreen_lod 自动 set_physics_process(true) 解冻
## BOSS / Sentinel（category=="boss" / enemy_type=="uav_commander"）跳过冻结
const FAR_FREEZE_DIST_SQ: float = 750.0 * 750.0

func _update_offscreen_lod() -> void:
	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)
	var player_pos := player_aircraft.global_position if player_aircraft and not player_aircraft.is_destroyed else cam_pos

	# 先收集所有 onscreen simple_ai 敌机，按距离玩家排序，超出预算的隔帧节流
	var simple_enemies: Array = []   # [ {ac, ai, dist} ]

	for child in get_children():
		if not child is Aircraft or child == player_aircraft:
			continue
		var ac: Aircraft = child
		if ac.is_destroyed:
			continue
		# 友方僚机由 _update_friendly_squad_lod 管；ALLY 第三方 LOD 由事件系统自管（阶段 5）
		if ac.team != CombatUnit.TEAM_HOSTILE:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		var ai_node: AIController = null
		for c in ac.get_children():
			if c is AIController:
				ai_node = c
				break

		if offscreen:
			# 离屏：走 Aircraft 自己的 LOD 2 机制（内部处理节流）+ 不画
			# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (8)
			ac.lod_level = 2
			ac.visible = false
			# 远距冻结（2026-05-04 加入）：屏幕外 + 距玩家 > FAR_FREEZE_DIST 的非关键敌人
			# 完全停 _physics_process，AI/Aircraft 都不跑，零成本。回屏幕或靠近自动解冻。
			# 豁免清单：
			#   - BOSS / Sentinel：必须保持机动
			#   - adds（教程轰炸机/CH-47/AH-64）：有 waypoint 任务（飞向城区/逃离），冻结
			#     就永远走不到目标 → 表现为"没移动"+"V 阵型崩塌"（玩家 2026-05-07 报告）
			#   - formation_mode follower：必须跟 leader，冻结会跑到 leader 后面距离爆炸，
			#     视觉上 UAV 飞出 Sentinel 圈外（同上报告）
			# 王牌中队（含 BOSS）不吃 LOD —— 走 AceTier 而非 category=="boss"，
			# 让将来的非 BOSS 王牌中队也拿到豁免（spec ace-squadron-tier §2.1）
			var is_critical_off: bool = AceTier.is_ace(ac) \
					or (ac.has_meta("category") and ac.get_meta("category") == "boss")
			if not is_critical_off and ac.has_meta("enemy_type") and ac.get_meta("enemy_type") == "uav_commander":
				is_critical_off = true
			if not is_critical_off and ac.has_meta("category") and ac.get_meta("category") == "adds":
				is_critical_off = true
			#   - 增援（spec reinforcement-ingress）：TRANSIT/EGRESS 是位移任务（同 adds 理由，
			#     冻结就永远到不了锚点/飞不出边界）；ONSTATION 被点名交战（非 PATROL）也不能冻。
			#     仅"驻空 + 闲置巡逻"允许冻结省性能——被观察/被 hunter 点名后下一帧自动解冻恢复绕环。
			if not is_critical_off and ac.has_meta("category") and ac.get_meta("category") == "reinforcement":
				var rphase: String = str(ac.get_meta("reinf_phase", "onstation"))
				if rphase != "onstation":
					is_critical_off = true
				elif ai_node and ai_node._state != AIController.AIState.PATROL:
					is_critical_off = true
			if not is_critical_off and ac.formation_mode and ac._formation_leader and is_instance_valid(ac._formation_leader):
				is_critical_off = true
			var freeze: bool = (not is_critical_off) and ac.global_position.distance_squared_to(player_pos) > FAR_FREEZE_DIST_SQ
			ac.set_physics_process(not freeze)
			if ai_node:
				ai_node.set_physics_process(not freeze)
			continue

		# 屏幕内
		# ⚠ 必须把 lod_level 重置回 0，否则敌机从离屏回屏幕内时 lod_level 卡在 2，导致：
		# 1) _draw/queue_redraw 节流 → label 数据停留在离屏瞬间的 HDG/spd/RNG/FLR 不更新
		# 2) label 跟飞机一起转（inv_rot 用的是过时 rotation 计算的角度补偿）
		# 3) LOD 2 内部 delta*3 物理在屏幕内还继续跑 → 转向过激
		# 敌机（含 simple_ai）屏幕内都应该走完整 LOD 0 路径，用户能看到细节渲染
		# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (11)
		ac.visible = true
		ac.lod_level = 0
		# 王牌中队 / BOSS 之类关键目标强制全速，不参与预算排队（spec ace-squadron-tier §2.1）
		var is_critical: bool = AceTier.is_ace(ac) \
				or (ac.has_meta("category") and ac.get_meta("category") == "boss")
		if is_critical or not (ai_node and ai_node.simple_ai):
			ac.set_physics_process(true)
			if ai_node:
				ai_node.set_physics_process(true)
			continue

		# simple_ai 敌机入预算池
		simple_enemies.append({
			"ac": ac,
			"ai": ai_node,
			"dist": ac.global_position.distance_squared_to(player_pos),
		})

	# 按距离玩家升序：前 N 架全速 AI 决策（divisor=3，simple_ai 默认），剩下的放大到 divisor=6
	# Aircraft 本体物理一直每帧跑 → 移动平滑无卡顿；只是 AI 重新选目标/设航向的频率降下来
	simple_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	for i in range(simple_enemies.size()):
		var item: Dictionary = simple_enemies[i]
		item["ac"].set_physics_process(true)
		if not item["ai"]:
			continue
		item["ai"].set_physics_process(true)
		item["ai"].ai_tick_divisor = 3 if i < SIMPLE_AI_FULL_TICK_BUDGET else 6

## 友方编队 LOD：每帧把玩家 + 全部友方僚机钉在 LOD 0（60Hz 完整物理）。
## ⚠ 注意：这里每帧覆盖会压过 AI 侧（set_formation_target / exit_evade 等）写入的
## lod=1/2 —— 收敛依赖"父先子后"树序（本函数先写、Aircraft 后读）。lod_level 的
## 单一所有权归属留给重构计划 Phase 4（docs/planning/physics-ai-control-refactor.md）。
## 历史：旧策略 cruise→LOD1 / 离屏→LOD2 让僚机进入 1/3 速率简化路径，表现为
## "决定 combat_target 却迟迟不去攻击""反应慢半拍"，故全钉 LOD 0（成本 ~0.3ms/frame）。
func _update_friendly_squad_lod() -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	# 玩家长机始终 LOD 0
	player_aircraft.lod_level = 0
	player_aircraft.visible = true

	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)

	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or not ac.is_player_squad() or ac.is_destroyed:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		# 玩家僚机一律 LOD 0：与玩家同级别响应频率（60Hz 完整物理）
		# 旧策略 offscreen→LOD2 / cruise→LOD1 让僚机进入 1/3 速率简化路径，
		# 表现为"决定 combat_target 却迟迟不去攻击""反应慢半拍"。
		# 玩家方最多 3 架僚机，全 LOD 0 的 CPU 成本可忽略（~0.3ms/frame）。
		ac.lod_level = 0
		ac.visible = not offscreen

func _cleanup_destroyed_enemies() -> void:
	for child in get_children():
		if child is Aircraft and child.team != CombatUnit.TEAM_PLAYER and child.is_destroyed:
			if child._destroy_timer > 5.0:
				child.queue_free()

## 获取飞机的 AI 控制器
func _get_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

# ──────────────────────────────────────────────
# 操控对象切换（spec squad-control-switching）
# ──────────────────────────────────────────────

## 数字键入口（固定号机号，spec §3.1）：键 N 永远接管 squad_slot == N 的存活飞机。
## squad_slot 是飞机出生时分配的稳定身份，不随换帅或列表顺序变化；阵亡后的空号保持为空。
func _switch_control_to_slot(slot: int) -> void:
	if not _squad or slot < 1:
		return
	var target := _aircraft_for_squad_slot(slot)
	if target == null or target == player_aircraft:
		return
	_switch_player_to(target)
	if is_instance_valid(_wingman_tutorial):
		_wingman_tutorial.complete()

## 固定号机号查询。独立成纯查询入口，供输入与无头回归测试共用。
func _aircraft_for_squad_slot(slot: int) -> Aircraft:
	if not _squad or slot < 1:
		return null
	for ac in _squad.members:
		if is_instance_valid(ac) and not ac.is_destroyed and ac.squad_slot == slot:
			return ac
	return null

## 接管流程（spec §3.2）：新机上手 + 换帅 + 旧机降级 + 重定向操控真源。
func _switch_player_to(new_ac: Aircraft) -> void:
	if not new_ac or not is_instance_valid(new_ac) or new_ac == player_aircraft:
		return
	var old_ac := player_aircraft
	var new_ai := _get_ai(new_ac)
	if new_ai:
		new_ai.manual_control = true
		new_ai._takeover_transition_timer = 0.0
	# 彻底清掉僚机残留（formation_mode + keep_target_on_arrival + ai_override_pursuit），
	# 否则 keep_target_on_arrival=true 会让点击移动永不清除 target_position → 飞过头不停（bug）。
	new_ac.clear_formation()
	new_ac.target_position = Vector2.INF  # 接管即清旧航路，等玩家下新指令
	new_ac.selected = true
	if _squad:
		_squad.set_leader(new_ac)
	if old_ac and is_instance_valid(old_ac):
		old_ac.selected = false
		# 问题3：旧机降级时取消移动指令（target_position 清空），仅保留战斗（combat_target 不动）
		old_ac.target_position = Vector2.INF
		# 按住右键急刹时切控：旧机的刹车旗必须清（它随后离开 selected，release 事件
		# 不再覆盖它），否则 AI 接管后 hard_brake 残留 → 永久钳在失速地板速度
		old_ac.hard_brake = false
		var old_ai := _get_ai(old_ac)
		if old_ai:
			old_ai.manual_control = false
			old_ai._takeover_transition_timer = AIController.TAKEOVER_TRANSITION_GRACE
	_set_player_aircraft(new_ac)
	EventLogger.log_event("CONTROL_SWITCH", "Survivor",
		"-> slot %d (%s)" % [new_ac.squad_slot, new_ac.callsign])

## 战场引力上下文低频填充（spec battlefield-gravity §2.4，0.5s；单槽：BOSS > 最近 triggered 战区 > 无）。
## objective 成员集只认实例表（BossEncounter.get_display_members / 战区已刷单位）——
## 禁字符串匹配 category（"ace_support" 含 "ace" 会误伤，spec §2.4 硬约定）。
var _objective_ctx_timer: float = 0.0
func _update_objective_context(delta: float) -> void:
	_objective_ctx_timer -= delta
	if _objective_ctx_timer > 0.0:
		return
	_objective_ctx_timer = 0.5
	# ① BOSS 优先（真 BOSS 登场时战区已清，二者不同时存在——用户定档）
	var boss: BossEncounter = _spawner.get_boss() if _spawner else null
	if boss != null and boss.active:
		ObjectiveContext.set_boss_objective(boss.get_display_members())
		if ObjectiveContext.has_objective:
			return  # 成员全灭时 set_boss_objective 内部已退化为 no_objective，落到 ②
	# ② 战区：最近 triggered 未完成
	if _zone_mission != null and player_aircraft and is_instance_valid(player_aircraft):
		var zobj := _zone_mission.get_nearest_triggered_objective(player_aircraft.global_position)
		if not zobj.is_empty():
			ObjectiveContext.set_zone_objective(zobj["units"], zobj["center"])
			return
	# ③ 无任务：锚退化为操控机（ObjectiveContext.effective_anchor 实时读，不吃刷新延迟）
	ObjectiveContext.set_no_objective()

## 操控真源单一 chokepoint（spec §3.2 步骤5）：原子重定向所有"谁是玩家机"的消费者。
func _set_player_aircraft(ac: Aircraft) -> void:
	if not ac or not is_instance_valid(ac):
		return
	var prev_controlled: Aircraft = player_aircraft
	player_aircraft = ac
	AircraftRenderer.player_ref = ac
	_hacked_ally_force.set_leader(ac)
	# 战场引力生存层保护对象 = 当前操控机（spec battlefield-gravity §2.3，SEAM-019 同款重定向）
	ObjectiveContext.protectee = ac
	if survivor_player:
		survivor_player.aircraft = ac
	selected_aircraft = [ac]
	if _camera_ctrl:
		_camera_ctrl.set_follow_target(ac)
		_camera_ctrl.snap_to_follow()
	# ⚠ 下面这批消费者在 _ready 里 setup(player_aircraft) 缓存了初始机引用。
	# 漏掉任何一个 → 切控/换帅后旧机被击落释放，消费者持有已 free 实例：
	# spawner 曾因此在 BOSS 生成时把 freed Aircraft 当 arg4 传进 CarrierStrikeGroup.spawn 崩溃。
	if _spawner:
		_spawner.player_aircraft = ac
	if zone_manager:
		zone_manager.player_ref = ac
	if _map_boundary:
		_map_boundary.player = ac
	if _tactical_map:
		_tactical_map._player = ac
	if _zone_arrow:
		_zone_arrow._player = ac
	if _zone_mission:
		_zone_mission._player = ac
	if _adbs:
		_adbs._player = ac
	if _event_director:
		_event_director.player = ac
		# 王牌支援中队（spec events/ace-support-squadron）：PURSUIT 锁的是"当前操控机"，
		# 切控/换帅后重定向（SEAM-019 同款；AceSquad.set_player_ref 基类契约）
		var ace_ev = _event_director.find_by_name("ace_support")
		if ace_ev != null and ace_ev.get("_squad") != null:
			ace_ev._squad.set_player_ref(ac)
	# AudioManager._engine_host 同样是缓存：不重绑的话引擎声会留在旧机上，
	# 旧机被击落后 is_instance_valid 守卫让它静默消音（不崩，但玩家侧"没声了"）。
	# 脱离 SceneTree 的测试夹具/场景切换边界不能启动 AudioStreamPlayer2D；正式局飞机恒在树内。
	if ac.is_inside_tree():
		AudioManager.start_player_engine(ac)
	# 王牌技随操控机迁移 + 全队生效子集重建（skills-720 T1；切控/换帅统一走本 chokepoint）
	if prev_controlled != ac:
		_migrate_ace_field_upgrades(prev_controlled, ac)
		_refresh_squad_effective_stacks()

## 通用能力入口：装备完成敌机转换后，把它交给当前长机的非玩家可控护航账本。
func adopt_hacked_ally(ac: Aircraft) -> void:
	_hacked_ally_force.adopt(ac)

## 换帅信号回调（spec §3.7 击落自动接管）：当前操控机阵亡 → 自动接管新长机。
func _on_squad_leader_changed(new_leader: Aircraft) -> void:
	if not new_leader or not is_instance_valid(new_leader):
		return
	if player_aircraft == null or not is_instance_valid(player_aircraft) or player_aircraft.is_destroyed:
		var new_ai := _get_ai(new_leader)
		if new_ai:
			new_ai.manual_control = true
			new_ai._takeover_transition_timer = 0.0
		# 自动接管必须与手动切控走同一套完整退出编队语义：清 leader 缓存、
		# keep_target_on_arrival / ai_override_pursuit / 旧槽位，避免新长机仍带僚机残态。
		new_leader.clear_formation()
		new_leader.selected = true
		_set_player_aircraft(new_leader)
		EventLogger.log_event("CONTROL_TAKEOVER", "Survivor",
			"leader down -> slot %d (%s)" % [new_leader.squad_slot, new_leader.callsign])


func _count_missiles_targeting_player() -> int:
	var count := 0
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.target == player_aircraft:
				count += 1
	return count

func _get_enemies_without_active_missile_at_player() -> Array[Aircraft]:
	# 找出有锁定玩家但没有在飞导弹指向玩家的敌机
	var has_missile: Dictionary = {}  # Aircraft -> bool
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.target == player_aircraft and is_instance_valid(m.source):
				has_missile[m.source] = true
	var result: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft and child.team == CombatUnit.TEAM_HOSTILE and not child.is_destroyed:
			if not has_missile.has(child):
				result.append(child)
	return result

# ══════════════════════════════════════════════
#  地面单位生成（Debug 面板用，不走 Spawner）
# ══════════════════════════════════════════════

## 在玩家附近生成一辆敌方 SAM（防空导弹车）
func _spawn_enemy_sam() -> void:
	_spawn_ground_unit(_sam_scene, _sam_params, 1, 1500.0)

## 在玩家附近生成一辆敌方 AA 炮（高射炮）
func _spawn_enemy_aa() -> void:
	_spawn_ground_unit(_aa_scene, _aa_params, 1, 800.0)

## 在玩家附近生成一艘敌方 FFG 护卫舰（Debug 面板用）
## 直线往返 waypoint：玩家前方 1500 px 附近起刷，两条 5000 px 对角 waypoint 组成往返
func _spawn_enemy_ffg() -> void:
	_spawn_naval_ship(_ffg_params, FrigateShip)

## 在玩家附近生成一艘敌方 DDG 驱逐舰
func _spawn_enemy_ddg() -> void:
	_spawn_naval_ship(_ddg_params, DestroyerShip)

## 在玩家附近生成一艘敌方 CG 巡洋舰
func _spawn_enemy_cg() -> void:
	_spawn_naval_ship(_cg_params, CruiserShip)

## 在玩家附近生成一艘敌方 CV 航母（BOSS 级，非常肉）
## 用 preload 而非 class_name 引用 —— 防止 Godot 全局 class 缓存未更新时 "CarrierShip not declared"
func _spawn_enemy_cv() -> void:
	var cv_script: GDScript = preload("res://scripts/naval/carrier_ship.gd")
	_spawn_naval_ship(_cv_params, cv_script)

## 在玩家附近生成一艘敌方 SS 核潜艇（预留事件 BOSS，目前默认浮出可直接打）
func _spawn_enemy_ss() -> void:
	var ss_script: GDScript = preload("res://scripts/naval/submarine_ship.gd")
	_spawn_naval_ship(_ss_params, ss_script)

## 通用海上单位 spawn：在玩家附近刷一艘，配上直线往返 waypoint + 注入武器管理器
func _spawn_naval_ship(params_res: Resource, ship_class: GDScript) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var pp := player_aircraft.global_position
	var angle := randf() * TAU
	var spawn_pos := pp + Vector2(cos(angle), sin(angle)) * 3000.0

	var ship: NavalUnit = ship_class.new()
	ship.params = params_res
	ship.position = spawn_pos

	# 朝向：沿切线方向（垂直于玩家-船连线）
	var tangent := Vector2(-sin(angle), cos(angle))
	ship.initial_heading_deg = rad_to_deg(atan2(tangent.x, -tangent.y))

	# 直线往返 waypoint（船开起来比较容易观察火力）
	var wp_dir := tangent * 4000.0
	ship.waypoints = PackedVector2Array([spawn_pos + wp_dir, spawn_pos - wp_dir])

	ship.set_meta("category", "adds")
	ship.set_meta("skip_far_cleanup", true)

	add_child(ship)
	ship.bullet_manager = bullet_manager
	ship.missile_manager = missile_manager

## 地面单位通用生成（与沙盒 debug_panel._spawn_ground_unit 同构）
## 地面单位归类为 Adds：不占 Token、不随机刷新、只由事件/Debug 面板触发
func _spawn_ground_unit(scene: PackedScene, params_res: Resource, team_id: int, distance: float) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var pp := player_aircraft.global_position
	var angle := randf() * TAU
	var spawn_pos := pp + Vector2(cos(angle), sin(angle)) * distance
	var unit: GroundUnit = scene.instantiate()
	unit.params = params_res
	unit.team = team_id
	unit.position = spawn_pos
	var to_player := (pp - spawn_pos).normalized()
	unit.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))
	# Adds 分类标记：不被 _update_hunters / _update_enemy_waypoints 影响（它们只查 Aircraft）
	# Token 消耗 = 0（地面单位不参与 _recalc_token_usage，后者只查 Aircraft）
	unit.set_meta("category", "adds")
	add_child(unit)
	# 注入管理器
	unit.bullet_manager = bullet_manager
	unit.missile_manager = missile_manager

# ══════════════════════════════════════════════
#  升级流程
# ══════════════════════════════════════════════

func _on_player_leveled_up(_new_level: int) -> void:
	# 自然成长已退役（spec player-aircraft-power-curve §6 阶段2）：等级只做门槛，
	# 成长全部由三轴里程碑（卡片加点跨档）+ 进化换档承担。

	# 表现层：屏幕中上方弹出 LEVEL UP（bench 压测跳过——一帧多级会刷屏）
	if not _bench_mode and hud:
		hud.show_level_up(_new_level)

	# 升级回复（720 批，队级单实例）：每次升级全队回 10 HP
	if int(upgrade_stacks.get("levelup_heal", 0)) > 0:
		for m in _squad_members_alive():
			if m.params:
				m.hp = minf(m.hp + 10.0, m.params.max_hp)
		EventLogger.log_event("SKILL_HOOK", "Squad", "levelup_heal → 全队 +10 HP")

	# Bench 模式：随机自动拿一张升级（压力放大器：越强→杀越快→负载越大）
	if _bench_mode:
		if _bench_scenario == "evolution_growth" and _growth_bench != null:
			_growth_bench.handle_level_up()
			return
		_bench_auto_pick_upgrade()
		return

	# 卡片三选一回归（用户 2026-07-19，spec evolution-attribute-gates §2.2）：
	# 每 3 级触发——三卡 = 斗士/骑士/策士各一张，选卡 = 得技能 + 该轴 +1 属性点。
	# 恢复旧暂停弹窗节奏（1/3 频率的低频打断）；非 3 倍数等级仍只 toast 不打断。
	if _new_level % 3 == 0:
		var cards: Array[Dictionary] = _roll_axis_cards(true)
		_append_signature_offer(cards)
		if not cards.is_empty():
			is_paused_for_upgrade = true
			AudioManager.set_music_muffled(true)
			# 急刹车转场（spec ui-transition §2.3）：导演负责时间缩放 → hard_pause →
			# 镜头推近 → 卡片错开弹入。面板只填内容
			upgrade_ui.populate(cards, _axis_points_capped())
			Presentation.present(upgrade_ui, "upgrade_in")
			upgrade_ui.schedule_entry_flashes()
			return  # consume_level_up_display 由 _on_upgrade_selected 收
	survivor_player.consume_level_up_display()
	if _zone_hint:
		_zone_hint.show_temp(tr("LEVEL_UP_TOAST_FMT") % _new_level, 2.5)

## 从升级池按现行规则（专属筛选/doctrine 门控/稀有度分槽/pity）抽三选一。
## 战区结算规划站调用（原等级弹窗逻辑原样抽出复用）。空数组 = 无可抽。
func _roll_upgrade_choices() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	var p: AircraftParams = player_aircraft.params if player_aircraft else null
	var present_classes: Array = _squad_present_classes()
	for u in SurvivorData.UPGRADES:
		if u.get("evolved", false):
			continue  # 战区奖励池技能不进随机池
		if not SurvivorData.is_normal_random_candidate(u):
			continue  # 专属技唯一自然入口 = 每机每局一次的第四槽
		if not SurvivorData.is_upgrade_available_for(u, _player_profile_id, p, upgrade_stacks, present_classes):
			continue
		if MetaShop.is_upgrade_gated(u):
			continue  # Doctrine 门控：需先在生涯商店购入对应学说
		var stacks: int = upgrade_stacks.get(u["id"], 0)
		if stacks < int(u["max_stacks"]):
			available.append(u)
	if available.is_empty():
		return []
	var level: int = survivor_player.level if survivor_player else 1
	return SurvivorData.pick_3_upgrades(available, upgrade_stacks, _pity_counter, level)

## 每 3 级卡片三选一（spec evolution-attribute-gates §2.2）：三轴各抽一张。
## 可用池过滤规则与 _roll_upgrade_choices 完全一致；某轴无可用卡 → 合成"专注"卡（纯 +1 点）。
## apply_classified_pity 仅由自然等级升级传 true；奖励升级保持基础权重且不改累计。
func _roll_axis_cards(apply_classified_pity: bool = false) -> Array[Dictionary]:
	var by_axis: Dictionary = {}
	for a in SurvivorData.AXES:
		by_axis[a] = []
	var p: AircraftParams = player_aircraft.params if player_aircraft else null
	var present_classes: Array = _squad_present_classes()
	for u in SurvivorData.UPGRADES:
		if u.get("evolved", false):
			continue  # 战区奖励池技能不进随机池
		if not SurvivorData.is_normal_random_candidate(u):
			continue  # 普通三轴卡永不吞掉机体专属位
		if not SurvivorData.is_upgrade_available_for(u, _player_profile_id, p, upgrade_stacks, present_classes):
			continue
		if MetaShop.is_upgrade_gated(u):
			continue
		if int(upgrade_stacks.get(u["id"], 0)) >= int(u["max_stacks"]):
			continue
		(by_axis[SurvivorData.axis_of_upgrade(u)] as Array).append(u)
	var all_available: Array = []
	for a in SurvivorData.AXES:
		all_available.append_array(by_axis[a] as Array)
	var build_affinity: Dictionary = SurvivorData.compute_status_build_affinity(upgrade_stacks)
	var focus_tag: String = SurvivorData.primary_status_build_tag(build_affinity)
	var service_tag: String = SurvivorData.select_terminal_service_tag(
		all_available, upgrade_stacks, _terminal_offer_misses, build_affinity)
	var service_misses: int = int(_terminal_offer_misses.get(service_tag, 0)) if service_tag != "" else 0
	var force_terminal: bool = service_tag != "" \
		and service_misses >= SurvivorData.TERMINAL_GUARANTEE_MISSES
	# 先冻结唯一强制槽位；否则在抵达可强制轴前，早先轴仍可能按债务倍率自然抽中同类终端，
	# 造成一次事件出现两个终端，违背“只服务一条终端债务”的约束。
	var force_axis: StringName = &""
	if force_terminal:
		for axis in SurvivorData.AXES:
			if not SurvivorData.eligible_terminals_for(by_axis[axis], service_tag).is_empty():
				force_axis = axis
				break
	var forced_once := false
	var cards: Array[Dictionary] = []
	var lvl: int = survivor_player.level if survivor_player else 1
	var classified_mult: float = SurvivorData.classified_pity_weight_multiplier(
		_classified_pity_misses) if apply_classified_pity else 1.0
	for a in SurvivorData.AXES:
		var c: Dictionary = {}
		if force_terminal and a == force_axis:
			c = SurvivorData.pick_terminal_for_tag(
				by_axis[a], service_tag, upgrade_stacks, lvl, classified_mult)
			forced_once = not c.is_empty()
		if c.is_empty():
			var debt_mult: float = SurvivorData.terminal_debt_weight(service_misses) \
				if service_tag != "" and not force_terminal else 1.0
			c = SurvivorData.pick_card_for_axis(
				by_axis[a], upgrade_stacks, lvl, classified_mult,
				focus_tag, int(build_affinity.get(focus_tag, 0)), service_tag, debt_mult)
		if c.is_empty():
			# 收入封顶后"专注"纯加点卡已无意义（加点被 add_axis_point 闸掉）→ 该轴不出卡
			if _axis_points_capped():
				continue
			c = SurvivorData.make_axis_focus_card(a)
		cards.append(c)
	if service_tag != "":
		var terminal_offered := false
		for card in cards:
			if SurvivorData.is_terminal_for(card, service_tag):
				terminal_offered = true
				break
		_terminal_offer_misses[service_tag] = 0 if terminal_offered else service_misses + 1
		EventLogger.log_event("UPGRADE_BUILD", "Player",
			"tag=%s affinity=%d miss=%d→%d terminal=%s forced=%s" % [
				service_tag, int(build_affinity.get(service_tag, 0)), service_misses,
				int(_terminal_offer_misses[service_tag]), str(terminal_offered), str(forced_once),
			])
	if apply_classified_pity and not cards.is_empty():
		var previous_misses := _classified_pity_misses
		_classified_pity_misses = SurvivorData.classified_pity_next_misses(
			cards, _classified_pity_misses)
		EventLogger.log_event("UPGRADE_PITY", "Player",
			"classified miss %d→%d (weight x%.1f, gold=%s)" % [
				previous_misses, _classified_pity_misses, classified_mult,
				str(_classified_pity_misses == 0),
			])
	return cards

## 当前操控机对应的进化节点；起手机在首次停靠前还没有 evo_node meta，回退档案映射。
func _current_evolution_node_id() -> StringName:
	if player_aircraft and is_instance_valid(player_aircraft):
		var node_id: StringName = player_aircraft.get_meta("evo_node", &"")
		if node_id != &"":
			return node_id
	return EvolutionSystem.node_id_for_profile(_player_profile_id)

## 每 3 级普通三卡抽完后独立追加专属第四槽。前置技能不参与出示门控；
## 选择后效果仍由原技能自身的玩法条件自然启用。
func _append_signature_offer(cards: Array[Dictionary]) -> void:
	_signature_offered_node = &""
	var node_id := _current_evolution_node_id()
	if node_id == &"":
		return
	if int(_signature_offer_state.get(node_id, SignatureOfferState.UNSEEN)) \
			!= SignatureOfferState.UNSEEN:
		return
	if not MetaShop.is_signature_owned_for_aircraft(node_id):
		return
	var signature := SurvivorData.signature_upgrade_for_aircraft(node_id)
	if signature.is_empty():
		_signature_offer_state[node_id] = SignatureOfferState.RESOLVED
		push_warning("专属第四槽缺少技能映射：%s" % node_id)
		return
	var uid := String(signature.get("id", ""))
	if int(upgrade_stacks.get(uid, 0)) >= int(signature.get("max_stacks", 1)):
		_signature_offer_state[node_id] = SignatureOfferState.RESOLVED
		return
	if not SurvivorData.signature_offer_hit(randf()):
		_signature_offer_state[node_id] = SignatureOfferState.RESOLVED
		EventLogger.log_event("UPGRADE", "Player", "专属第四槽未命中：%s" % node_id)
		return
	var card: Dictionary = signature.duplicate(true)
	card["signature_offer"] = true
	card["signature_aircraft_name_key"] = _player_profile.display_name if _player_profile else ""
	cards.append(card)
	_signature_offer_state[node_id] = SignatureOfferState.OFFERED
	_signature_offered_node = node_id
	EventLogger.log_event("UPGRADE", "Player", "专属第四槽出现：%s/%s" % [node_id, uid])

## 三轴点数是否触顶（spec evolution-attribute-gates §2.2 v9）：卡面 +1 标签与专注卡据此关停
func _axis_points_capped() -> bool:
	return survivor_player != null \
		and survivor_player.total_axis_points() >= SurvivorData.AXIS_POINT_CAP

## ════════════════════════════════════════════════
##  升级归属分流（spec skills-720-rework T1 / squad-upgrade-ownership §2.8 实装）
## ════════════════════════════════════════════════

## 玩家小队存活成员（含长机）。无编队主角 = [player_aircraft]。
func _squad_members_alive() -> Array:
	var out: Array = []
	if _squad:
		for m in _squad.members:
			if is_instance_valid(m) and m is Aircraft and not m.is_destroyed:
				out.append(m)
	if out.is_empty() and player_aircraft and is_instance_valid(player_aircraft) \
			and not player_aircraft.is_destroyed:
		out.append(player_aircraft)
	return out

## 某架玩家小队机的品类身份（进化节点机种类 → 轴集合）。
## 档案 id 读 meta "profile_id"（出生/进化时 stamp）；长机兜底 _player_profile_id。
func _class_identity_of(ac: Aircraft) -> Array:
	if ac == null or not is_instance_valid(ac):
		return []
	var pid := StringName(str(ac.get_meta("profile_id", "")))
	if pid == &"" and ac == player_aircraft:
		pid = _player_profile_id
	return EvolutionSystem.class_identity_of_profile(pid)

## 队伍现有品类身份并集（卡池品类门控用：全队没人吃得到的品类技不进池）。
func _squad_present_classes() -> Array:
	var got: Dictionary = {}
	for m in _squad_members_alive():
		for c in _class_identity_of(m):
			got[c] = true
	return got.keys()

## 按归属把一条升级下发到应生效的机上：通用→全队逐机；品类→身份匹配机；
## 王牌→仅当前操控机；squad_once→只应用一次长机侧效果（队级效果由消费点读账本）。
## 调用方负责 upgrade_stacks 记账，批量结束后调 _refresh_squad_effective_stacks()。
func _distribute_upgrade(upgrade: Dictionary) -> void:
	if survivor_player == null:
		return
	if SurvivorData.upgrade_scope(upgrade) == "squad_once":
		survivor_player.apply_upgrade(upgrade)
		var uid := str(upgrade.get("id", ""))
		_dispatch_sig_oneshot(uid)
		return
	for m in _squad_members_alive():
		if SurvivorData.upgrade_applies_to_machine(
				upgrade, _class_identity_of(m), m == player_aircraft):
			survivor_player.apply_upgrade_to(m, upgrade)

## 722 签名技能：一次性即时动作（生成/入库类；spec aircraft-signature-skills §4 生成层）。
## 幂等：_sig_oneshot_done 防换机重放 _replay_player_upgrades 重复执行（局内不清零）。
var _sig_oneshot_done: Dictionary = {}

func _dispatch_sig_oneshot(uid: String) -> void:
	if not uid.begins_with("sig_") or _sig_oneshot_done.has(uid):
		return
	match uid:
		"sig_f47":
			# 忠诚僚机编队（F-47）：立即获得 2 架永久忠诚僚机（无离屏消散；阵亡不补）
			_sig_oneshot_done[uid] = true
			var got: int = 0
			for i in 2:
				if _sig_spawn_loyal_drone("sig_f47_drone") != null:
					got += 1
			EventLogger.log_event("SKILL", "Player", "忠诚僚机编队：生成 %d 架永久忠诚僚机" % got)
		"sig_x02":
			# 突击翼龙（X-02）：电磁炮入库（已有则跳过）+ 最短射程清零 + 充能 ×0.7
			_sig_oneshot_done[uid] = true
			if player_aircraft and is_instance_valid(player_aircraft) and player_aircraft.params:
				if player_aircraft.params.get_equipment_of_kind("railgun") == null:
					_claim_weapon_reward("railgun")
				var rg = player_aircraft.params.get_equipment_of_kind("railgun")
				if rg != null:
					rg.min_engage_range_m = 0.0
					rg.charge_duration *= 0.7
					EventLogger.log_event("SKILL", "Player",
						"突击翼龙：电磁炮就绪（无最短射程 / 充能 ×0.7）")
		"sig_ax00":
			# 双子星（AX-00）：立即复制 1 架同型僚机入队（编队上限 9；超出放弃）；
			# 新僚机经 _spawn_reward_wingman 尾部 build 补挂 →"复制技能"
			_sig_oneshot_done[uid] = true
			var cloned: int = 0
			# 懒建队：AX-00 起手无僚机（wingman_count=0），不先装配长机则
			# _spawn_reward_wingman 整段静默 early-return（复制 0 架却仍会记账）
			if _ensure_player_squad() != null:
				for i in 1:
					var alive_n: int = _squad_members_alive().size()
					if alive_n >= 9:
						break
					_spawn_reward_wingman()
					cloned += 1
			EventLogger.log_event("SKILL", "Player", "双子星：复制 %d 架同型僚机（含全套 build）" % cloned)

## 722 签名：生成签名忠诚僚机 drone（f47 一次性 / x90 周期）。
## 刻意不进 ac._alive_drones（离屏 despawn 体系）→ 天然永久存在；死亡即消失不补。
func _sig_spawn_loyal_drone(tag: String) -> Aircraft:
	if not player_aircraft or not is_instance_valid(player_aircraft) or player_aircraft.is_destroyed:
		return null
	var lw: LoyalWingmanParams = null
	if player_aircraft.params and player_aircraft.params.loyal_wingman:
		lw = player_aircraft.params.loyal_wingman
	else:
		lw = load("res://resources/a10_loyal_wingman.tres")
	if lw == null or lw.drone_aircraft_params == null:
		return null
	var drone: Aircraft = AircraftWeapons._spawn_loyal_wingman_drone(player_aircraft, lw)
	if drone != null:
		drone.set_meta(tag, true)
	return drone

## 722 sig_x90·鲸群：周期生成计时（_tick_squad_watch 0.5s 粒度驱动）
var _sig_x90_spawn_timer: float = 0.0

## 获得技能时的"+1 轴进度"（spec skills-720-rework §1.1；cap 逻辑在 SurvivorPlayer）。
## 只挂在获得点（选卡/战区奖励/debug 灌注）；换型重放不重发。
func _grant_milestone_plus(upgrade: Dictionary) -> void:
	if survivor_player == null:
		return
	# 722 批：milestone_plus 允许数组（AX-00 双轴 +1），逐轴发放；cap 逻辑不变
	for axis in SurvivorData.milestone_plus_list_of(upgrade):
		survivor_player.add_milestone_bonus(axis, _player_profile)

## 重建全队"生效技能子集"meta + 逐机重算词条联动。
## skill_hooks / aircraft_flares / bullet_manager 读各机 meta 判触发技能：
## 王牌技随当前操控机走、品类技只落身份匹配机、squad_once 不落单机（账本级）。
## 调用点：upgrade_stacks 变更后 / 切控换帅后 / 进化重放后 / 新僚机入队后。
func _refresh_squad_effective_stacks() -> void:
	for m in _squad_members_alive():
		var eff: Dictionary = {}
		var identity: Array = _class_identity_of(m)
		var is_ctrl: bool = (m == player_aircraft)
		for u in SurvivorData.UPGRADES:
			var uid: String = str(u.get("id", ""))
			var n: int = int(upgrade_stacks.get(uid, 0))
			if n > 0 and SurvivorData.upgrade_applies_to_machine(u, identity, is_ctrl):
				eff[uid] = n
		m.set_meta("upgrade_stacks", eff)
		SurvivorData.recompute_category_bonuses(m, eff)
	# 加力队级资源的账本同步（720 批：检讨/强化加力——队级单实例语义，不逐机应用）
	if afterburner_charge:
		afterburner_charge.kill_charge_bonus = 0.6 * float(upgrade_stacks.get("ab_kill_charge", 0))
		afterburner_charge.duration_mult = 1.0 + 0.5 * float(upgrade_stacks.get("ab_duration", 0))
	# 722 签名技能：全频段压制（X-13）/ 作战云（FCAS）/ 传感器融合（F-35）/ 鲸群（X-90）
	# 队级账本位 → 静态开关
	StatusEffects.sig_x13_active = int(upgrade_stacks.get("sig_x13", 0)) > 0
	SkillHooks.sig_fcas_active = int(upgrade_stacks.get("sig_fcas", 0)) > 0
	SkillHooks.sig_f35_active = int(upgrade_stacks.get("sig_f35", 0)) > 0
	SkillHooks.sig_x90_active = int(upgrade_stacks.get("sig_x90", 0)) > 0
	SkillHooks.hush_active = int(upgrade_stacks.get("hush", 0)) > 0

## 王牌 scope 中"写飞机字段/params"的技能在切控/换帅时迁移（旧机剥离 → 新机应用）。
## 触发型王牌技（skill_flag 走 meta）由 _refresh_squad_effective_stacks 覆盖，不走这里。
## 白名单 SurvivorData.ACE_FIELD_STATS + 逆操作 SurvivorPlayer.strip_upgrade_from 配对登记。
func _migrate_ace_field_upgrades(prev: Aircraft, next: Aircraft) -> void:
	if prev == next or survivor_player == null:
		return
	for u in SurvivorData.UPGRADES:
		if SurvivorData.upgrade_scope(u) != "ace":
			continue
		if not SurvivorData.ACE_FIELD_STATS.has(str(u.get("stat", ""))):
			continue
		var n: int = int(upgrade_stacks.get(str(u.get("id", "")), 0))
		for i in n:
			if prev and is_instance_valid(prev) and not prev.is_destroyed:
				survivor_player.strip_upgrade_from(prev, u)
			survivor_player.apply_upgrade_to(next, u)

## 新僚机入队（生产/增援/换补）：按队级账本补挂对其生效的技能层 + 刷新生效子集。
## 开局建队时账本为空 = 天然 no-op。weapon 类跳过（效果长在长机武器资源上，随武器库迁移）。
func _apply_build_to_new_member(ac: Aircraft) -> void:
	if survivor_player == null or ac == null or not is_instance_valid(ac):
		return
	var identity: Array = _class_identity_of(ac)
	for u in SurvivorData.UPGRADES:
		if str(u.get("category", "")) == "weapon":
			continue
		var n: int = int(upgrade_stacks.get(str(u.get("id", "")), 0))
		if n <= 0 or not SurvivorData.upgrade_applies_to_machine(u, identity, ac == player_aircraft):
			continue
		for i in n:
			survivor_player.apply_upgrade_to(ac, u)
	# squad_once 的逐机成分：数据链的僚机雷达加成（T0 排查缺口②——晚入队补挂）
	if int(upgrade_stacks.get("data_link", 0)) > 0 and ac != player_aircraft and ac.params:
		for u in SurvivorData.UPGRADES:
			if str(u.get("id", "")) == "data_link":
				ac.params.radar_range *= (1.0 + float(u.get("value", 0.0)))
				break
	# 三轴里程碑补挂：新机没赶上之前的跨档，按玩家当前进度全量重放（逐机记账，幂等）
	survivor_player.apply_all_milestones_to(ac, _player_profile)
	_refresh_squad_effective_stacks()

## ── 720 批 T3：僚机阵亡事件 + 奖励升级弹窗 ─────────────────

## 0.5s 周期：检测小队成员 alive→destroyed 沿（复仇三技共用钩子）+ 顺延奖励升级弹窗。
## 同周期多人阵亡只触发一次（团灭不连发）；暂停中物理帧停走、天然冻结。
func _tick_squad_watch(delta: float) -> void:
	_squad_watch_timer -= delta
	if _squad_watch_timer > 0.0:
		return
	_squad_watch_timer = 0.5
	for m in _squad_known_alive:
		if m == null or not is_instance_valid(m) or (m as Aircraft).is_destroyed:
			_on_squad_member_down()
			break
	_squad_known_alive = _squad_members_alive()
	_update_sig_gcap()
	# 722 sig_x90·鲸群：每 25s 生成 1 架忠诚僚机（本技能来源的存活 ≤3）
	if int(upgrade_stacks.get("sig_x90", 0)) > 0 \
			and player_aircraft and is_instance_valid(player_aircraft) and not player_aircraft.is_destroyed:
		_sig_x90_spawn_timer -= 0.5
		if _sig_x90_spawn_timer <= 0.0:
			_sig_x90_spawn_timer = 25.0
			var pod_n: int = 0
			for d in get_tree().get_nodes_in_group("loyal_wingman"):
				if is_instance_valid(d) and not d.is_destroyed and d.has_meta("sig_x90_drone"):
					pod_n += 1
			if pod_n < 3:
				if _sig_spawn_loyal_drone("sig_x90_drone") != null:
					EventLogger.log_event("SKILL", "Player", "鲸群：生成忠诚僚机（%d/3）" % (pod_n + 1))
	_try_present_bonus_upgrade()

## 722 sig_gcap·联合突击：每存活僚机 → 导弹挂载 +1、雷达 +5%（≤4 层）。
## 差量幂等（meta sig_gcap_layers 记账）；僚机阵亡由 0.5s watch 周期自动减层；
## 换型重放序言清账 → 本函数下个周期整额补回（与历战者同模式）。
func _update_sig_gcap() -> void:
	if int(upgrade_stacks.get("sig_gcap", 0)) <= 0:
		return
	var alive: Array = _squad_members_alive()
	var wing_n: int = clampi(alive.size() - 1, 0, 4)
	for m in alive:
		if not (m is Aircraft):
			continue
		var gc_ac: Aircraft = m
		var prev: int = int(gc_ac.get_meta("sig_gcap_layers", 0))
		if prev == wing_n or gc_ac.params == null:
			continue
		var d: int = wing_n - prev
		if gc_ac.params.missile:
			gc_ac.params.missile = gc_ac.params.missile.duplicate()
			gc_ac.params.missile.max_count = maxi(gc_ac.params.missile.max_count + d, 1)
			gc_ac.missiles_remaining = clampi(
				gc_ac.missiles_remaining + maxi(d, 0), 0, gc_ac.params.missile.max_count)
		gc_ac.params.radar_range *= pow(1.05, float(d))
		gc_ac.set_meta("sig_gcap_layers", wing_n)
		EventLogger.log_event("SKILL", gc_ac._log_name(),
			"JointAssault layers %d→%d (missile%+d radar x%.2f)" % [prev, wing_n, d, pow(1.05, float(d))])

## 僚机/王牌被击坠 → 三技钩子（spec skills-720-rework §3.3 僚机阵亡事件）
func _on_squad_member_down() -> void:
	if is_game_over:
		return
	var alive: Array = _squad_members_alive()
	if int(upgrade_stacks.get("squad_revenge", 0)) > 0:
		for m in alive:
			m.apply_status(StatusEffects.BLOODLUST, 15.0)
			m.apply_status(StatusEffects.INVINCIBLE, 15.0)
		EventLogger.log_event("SKILL_HOOK", "Squad", "squad_revenge → 全队嗜血+无敌 15s")
	if int(upgrade_stacks.get("assassin_revenge", 0)) > 0:
		for m in alive:
			m.apply_status(StatusEffects.OVERLOAD, 15.0)
			m.apply_status(StatusEffects.STEALTH, 15.0)
		EventLogger.log_event("SKILL_HOOK", "Squad", "assassin_revenge → 全队超载+隐身 15s")
	if int(upgrade_stacks.get("blackbox_recovery", 0)) > 0:
		_queue_bonus_upgrade("blackbox_recovery")

func _queue_bonus_upgrade(reason: String) -> void:
	_pending_bonus_upgrades += 1
	EventLogger.log_event("UPGRADE", "Player",
		"奖励升级 +1（%s，待弹 %d）" % [reason, _pending_bonus_upgrades])

## 奖励升级与升级弹窗同一呈现（卡片三选一 + 选卡得点）；暂停/结算面板打开时顺延
func _try_present_bonus_upgrade() -> void:
	if _pending_bonus_upgrades <= 0 or is_paused_for_upgrade or is_game_over or _bench_mode:
		return
	if _evolution_ui and _evolution_ui.visible:
		return
	var cards: Array[Dictionary] = _roll_axis_cards()
	if cards.is_empty():
		_pending_bonus_upgrades = 0
		return
	_pending_bonus_upgrades -= 1
	is_paused_for_upgrade = true
	AudioManager.set_music_muffled(true)
	upgrade_ui.populate(cards, _axis_points_capped())
	Presentation.present(upgrade_ui, "upgrade_in")
	upgrade_ui.schedule_entry_flashes()

## 应用一条升级（归属分流 + 记栈 + "+1 轴进度" + 旧进化链检测 + 生效子集重建）。
## 返回触发的旧进化技能名（无则 ""）。供 结算规划站 / 旧 upgrade_ui 信号 两个入口共用（不含暂停/恢复）。
func _apply_upgrade_choice(upgrade: Dictionary) -> String:
	var stk: int = upgrade_stacks.get(upgrade["id"], 0) + 1
	EventLogger.log_event("UPGRADE", "Player",
		"selected '%s' (stack %d/%d)" % [
			tr(upgrade["name"]), stk, int(upgrade["max_stacks"])])
	_distribute_upgrade(upgrade)
	var uid: String = upgrade["id"]
	upgrade_stacks[uid] = upgrade_stacks.get(uid, 0) + 1
	_grant_milestone_plus(upgrade)

	# ── 旧进化链检测（evolves_to 残留机制）──
	var evolved_name := ""
	if upgrade.has("evolves_to"):
		var stacks: int = upgrade_stacks.get(uid, 0)
		if stacks >= int(upgrade["max_stacks"]):
			var evo_id: String = upgrade["evolves_to"]
			for u in SurvivorData.UPGRADES:
				if u["id"] == evo_id:
					_distribute_upgrade(u)
					upgrade_stacks[evo_id] = 1
					_grant_milestone_plus(u)
					evolved_name = tr(u["name"])
					break

	_refresh_squad_effective_stacks()
	return evolved_name

func _on_upgrade_selected(upgrade: Dictionary) -> void:
	if _signature_offered_node != &"":
		_signature_offer_state[_signature_offered_node] = SignatureOfferState.RESOLVED
		_signature_offered_node = &""
	var evolved_name := ""
	if str(upgrade.get("stat", "")) != "axis_focus":
		evolved_name = _apply_upgrade_choice(upgrade)
	# 三轴加点（spec evolution-attribute-gates §2.2）：选卡 = 该轴 +1，
	# 跨档里程碑在 add_axis_point 内自动应用（含起手机覆写表）
	survivor_player.add_axis_point(SurvivorData.axis_of_upgrade(upgrade), _player_profile)

	survivor_player.consume_level_up_display()
	is_paused_for_upgrade = false
	AudioManager.set_music_muffled(false)

	# 归零暂停期间被吞掉 release 事件的鼠标按键状态，
	# 防止"右键急刹/中键拖图卡住 → 升级后飞机永远朝某方向直飞"
	_set_hard_brake(false)
	is_dragging = false

	# ⚠ 以上全部状态恢复必须在 dismiss【之前】完成（spec ui-transition §3.9）：
	# 退场动画只是视觉尾巴，绝不延后任何玩法状态变更或输入恢复（守 Litmus #2）。
	# 解除暂停由 upgrade_out 的第 0 帧 pause=0 完成
	Presentation.dismiss(upgrade_ui, "upgrade_out")

	# 进化提示
	if evolved_name != "":
		if survivor_player.aircraft:
			survivor_player.aircraft.show_tactic_popup(tr("POPUP_EVOLUTION_FMT") % evolved_name)

## 换型后重放已选升级（spec evolution-attribute-gates §2.7：技能记玩家层，换机不丢；
## skills-720 T1 起走归属分流——通用/品类落全队、王牌落操控机，僚机进化后同步吃满）。
## category=="weapon" 的强化跳过：其效果长在武器资源上、已随武器库引用迁移，重放会双重叠加。
## 序言重置每架机上存活于 aircraft 实例的乘法字段（SurvivorPlayableSetup 不管它们）——
## 其余实例字段要么被 setup 重置（bullet_dodge_chance）要么是幂等赋值（extra_barrels 等）；
## 锁定目标数是加算字段，必须先回基础 1 再重放技能，随后里程碑在第三步补回自己的 +1。
func _replay_player_upgrades() -> void:
	if survivor_player == null or player_aircraft == null:
		return
	# 玩家级乘区也会随 squad_once 条目进入下方重放；先归一再重建，避免每次进化把
	# 一层经验倍率从 ×1.2 错叠到 ×1.4。签名 XP 是赋值型，但一起归一保持同一语义。
	survivor_player.xp_multiplier = 1.0
	survivor_player.sig_xp_mult = 1.0
	for m in _squad_members_alive():
		m.missile_reload_duration = 20.0  # aircraft.gd 字段默认值
		m.gun_reload_duration = 25.0
		m.max_simultaneous_locks = 1
		m.veteran_hp_bonus_applied = 0.0  # 历战者差量记账清零：换型后由 recompute 整额补回（720 T4）
		m.set_meta("sig_gcap_layers", 0)  # 联合突击差量清零：新 params 无加成，watch 周期整额补回（722）
		# 两条“局内永久 HP”技能的战果账本跟飞机实例走；进化只换 params，需把已赚收益补回。
		var earned_hp: float = float(m.get_meta("head_on_perma_hp_gained", 0.0)) \
			+ float(m.get_meta("bloodlust_perma_hp_gained", 0.0))
		if earned_hp > 0.0 and m.params:
			m.params.max_hp += earned_hp
			m.hp += earned_hp
		# 甲板周转（722 sig_fa18e）"永久 +10 HP"跨换机：新 params 按 meta 记账整额补回
		var fa18_hp: float = float(m.get_meta("sig_fa18e_hp_gained", 0.0))
		if fa18_hp > 0.0 and m.params:
			m.params.max_hp += fa18_hp
			m.hp += fa18_hp
	var replayed: int = 0
	for u in SurvivorData.UPGRADES:
		var stacks: int = int(upgrade_stacks.get(u["id"], 0))
		if stacks <= 0:
			continue
		if str(u.get("category", "")) == "weapon":
			continue
		for i in stacks:
			_distribute_upgrade(u)
		replayed += stacks
	_refresh_squad_effective_stacks()
	if replayed > 0:
		EventLogger.log_event("UPGRADE", "Player", "换型重放 %d 层升级（归属分流全队；weapon 类随武器库迁移已跳过）" % replayed)

## 长机被击坠时立即尝试接管存活僚机（不等 spawner 3s 周期 cleanup）。
## `_squad.cleanup()` 过滤死亡成员 + 晋升存活僚机为新长机 → 同步发 leader_changed →
## `_on_squad_leader_changed` 把 player_aircraft 重指派到新长机。
## 返回 true=接管成功（有存活僚机），false=全队覆灭（调用方走 _on_player_died）。
func _try_takeover_after_leader_down() -> bool:
	if _squad == null:
		return false
	_squad.cleanup()  # 同步晋升 + 发 leader_changed（_on_squad_leader_changed 接管 player_aircraft）
	return player_aircraft != null and is_instance_valid(player_aircraft) and not player_aircraft.is_destroyed

func _on_player_died() -> void:
	is_game_over = true
	if archive_enabled():
		CareerArchive.record_death()
	var merit_earned := MeritLedger.settle_run(
		survivor_player.total_xp_gained, MeritLedger.SETTLE_KIA)
	hud.show_game_over(survivor_player.level, game_time, _spawner.kill_count,
		survivor_player.total_xp_gained, merit_earned)

# ══════════════════════════════════════════════
#  暂停菜单回调（spec pause-menu）
# ══════════════════════════════════════════════

## 确认退出：不结算功勋（功勋只在 KIA / 撤退 / 胜利三个出口结算，确认页已明写）
func _on_pause_quit_to_menu() -> void:
	var lvl: int = survivor_player.level if survivor_player else 0
	var kills: int = _spawner.kill_count if _spawner else 0
	EventLogger.log_event("PAUSE", "QuitToMenu",
		"lvl=%d time=%.0fs kills=%d" % [lvl, game_time, kills])
	_quit_to_main_menu()

func _quit_to_main_menu() -> void:
	# 场景切换前必须全清表演层：否则时间缩放 / 遮罩 / 镜头系数会带进主菜单
	Presentation.clear_all()
	AudioManager.stop_music(1.0)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ══════════════════════════════════════════════
#  边界 / 撤退菜单回调（P1）
# ══════════════════════════════════════════════

func _on_retreat_confirmed() -> void:
	# 撤退 = 结束本局，走死亡结算入口（沿用 HUD 的 game_over 面板）
	EventLogger.log_event("BOUNDARY", "Retreat",
		"lvl=%d time=%.0fs kills=%d" % [survivor_player.level, game_time, _spawner.kill_count])
	is_game_over = true
	if archive_enabled():
		CareerArchive.record_retreat()
	var merit_earned := MeritLedger.settle_run(
		survivor_player.total_xp_gained, MeritLedger.SETTLE_RETREAT)
	hud.show_game_over(survivor_player.level, game_time, _spawner.kill_count,
		survivor_player.total_xp_gained, merit_earned)

func _on_supply_confirmed() -> void:
	# BOSS 阶段禁用补给 —— 防止玩家反复贴边回血刷 BOSS
	# 显示 toast 告诉玩家「无法补给，返回战场」，并把机头转回内部
	# 闸门与其他 BOSS 阶段停摆项同源（spec survivor-loop §3.1/§6）：解锁即禁用，
	# 不是"玩家选中 BOSS 圈后才禁用"（旧写法在 PRE_STAGE 段仍可无限回血）
	if _is_in_boss_phase():
		if _zone_hint:
			_zone_hint.show_temp(tr("BOUNDARY_SUPPLY_BLOCKED_BOSS"), 4.0)
		_turn_player_inward()
		EventLogger.log_event("BOUNDARY", "SupplyBlockedBoss", "boss_phase")
		return
	# 回血 + Token 加成（代价是敌人变强）
	if player_aircraft and not player_aircraft.is_destroyed and player_aircraft.params:
		player_aircraft.hp = player_aircraft.params.max_hp
	if _spawner:
		_spawner.add_supply_token_bonus()
	# 时间税：把 game_time 推进 15s（clamp 到 WARZONE_PHASE_DURATION，
	# 避免一次回血直接跨过阈值时跳过 _check_warzone_phase_timeout 的过渡逻辑）
	var time_before := game_time
	game_time = minf(game_time + SUPPLY_TIME_COST, WARZONE_PHASE_DURATION)
	# 机头转向地图中心，玩家自然飞回内部
	_turn_player_inward()
	EventLogger.log_event("BOUNDARY", "Supply",
		"hp_restored, token +%d, time_cost=%.1fs (%.1f→%.1f)" % [
			SurvivorSpawner.SUPPLY_TOKEN_GAIN, game_time - time_before, time_before, game_time])

func _on_retreat_cancelled() -> void:
	# 取消：机头转向地图中心，不传送，玩家自己飞回
	_turn_player_inward()

## 战术地图选中战区（P2）
func _on_zone_selected(zone_id: StringName) -> void:
	EventLogger.log_event("ZONE", "Selected", "id=%s" % zone_id)
	# 选定后清理"新战区已开放"提示条（持久）
	if _zone_hint:
		_zone_hint.hide_persistent()
	# 消费掉 newly_opened 标记
	if _zone_data:
		_zone_data.take_newly_opened()
	# RTS 巡航：把小队目标设到战区圆的"近边缘点"，飞过去即进圈触发 ZoneMission
	_set_cruise_to_zone_edge(zone_id)

## 计算战区圆边缘上离玩家最近的点，下达为小队巡航目标
func _set_cruise_to_zone_edge(zone_id: StringName) -> void:
	if not _zone_data or not player_aircraft or not is_instance_valid(player_aircraft):
		return
	var z := _zone_data.get_zone_by_id(zone_id)
	if z.is_empty():
		return
	var center: Vector2 = z.get("center", Vector2.INF)
	var radius: float = float(z.get("radius", 0.0))
	if center == Vector2.INF or radius <= 0.0:
		return
	var dir := (player_aircraft.global_position - center)
	# 玩家恰在圆心时给个默认方向，避免归一化得到零向量
	var edge: Vector2 = center + (dir.normalized() if dir.length() > 1.0 else Vector2.UP) * radius
	# 选战区 = 巡航指令（放弃攻击命令），逻辑走 SquadCommandController
	if _squad_cmd:
		_squad_cmd.command_move(edge)

func _on_zone_mission_triggered(zone_id: StringName) -> void:
	# 自动进入战区 = 自动开始任务；同时清掉顶部"新战区已开放"提示
	if _zone_hint:
		_zone_hint.hide_persistent()
		var mt: String = _zone_data.get_mission_type(zone_id) if _zone_data else "ground"
		var fmt_key: String
		match mt:
			"air":       fmt_key = "ZONE_MISSION_STARTED_AIR_FMT"
			"squadron":  fmt_key = "ZONE_MISSION_STARTED_SQUADRON_FMT"
			"naval":     fmt_key = "ZONE_MISSION_STARTED_NAVAL_FMT"
			_:           fmt_key = "ZONE_MISSION_STARTED_FMT"
		_zone_hint.show_temp(tr(fmt_key) % _zone_label(zone_id), 3.0)
	if _zone_data:
		_zone_data.take_newly_opened()

func _on_zone_mission_completed(zone_id: StringName) -> void:
	if not _zone_data:
		return
	# 机场解放战区（spec airfield-liberation-zones §3.1）：奖励＝机场本身，走独立解放路径
	# （不发军械库奖励、不走普通战区 mark_cleared churn）。
	if _zone_data.is_airfield(zone_id):
		_liberate_airfield(zone_id)
		return
	# §4 战区奖励降级：优先查 ZoneRewardRegistry（用户注册的专属奖励，模块化），
	# 未注册时回退到旧 _zone_data.get_reward（目前因 evolved 字段已删 → 池为空 → 返回 {}）
	# 默认行为：只回血，不发技能
	var reward: Dictionary = ZoneRewardRegistry.get_reward_for(zone_id)
	if reward.is_empty():
		reward = _zone_data.get_reward(zone_id)
	# 攻克即领（spec zone-reward-docking 修订 2026-07-24，用户拍板）：僚机/武器/技能类奖励
	# **当场发放、与机场/降落解耦**；进化 + 回血保留为停靠点功能（_on_dock_docked）。
	# 航母奖励仍即时入场（登舰=海上停靠点，兼回血/进化）。
	var reward_name := ""
	if not reward.is_empty():
		reward_name = tr(reward.get("name", ""))
		if String(reward.get("kind", "")) == "carrier":
			_summon_reward_carrier()
		else:
			_grant_reward_now(reward)
	_zone_data.mark_cleared(zone_id)
	# 热度：攻克战区（spec global-awareness-roe §2.4）
	if _spawner and _spawner._roe:
		_spawner._roe.add_heat(RoeDirector.HEAT_ZONE_CAPTURED)
	# 清掉 zone_mission 内部对该战区的记录；下次该战区再进入 AVAILABLE 时会重新刷
	if _zone_mission:
		_zone_mission.reset_zone(zone_id)
		## 2026-04-21：攻克后对其他仍空闲的战区做一次"按当前等级"的敌情升级
		## 已进入交战的战区不会被刷新（避免打到一半敌人换型）
		var refreshed: Array[StringName] = _zone_mission.refresh_active_zones_for_level(zone_id)
		if refreshed.size() > 0 and _zone_hint:
			_zone_hint.show_temp(tr("ZONE_REFRESHED_AFTER_CLEAR"), 3.0)
	EventLogger.log_event("ZONE", "Cleared",
		"id=%s reward=%s" % [zone_id, reward.get("id", "-")])

	# 攻克 toast：奖励攻克即领（不再"待停靠"文案）
	var label := _zone_label(zone_id)
	if _zone_hint:
		var msg: String
		if reward_name != "":
			msg = tr("ZONE_CLEARED_WITH_REWARD_FMT") % [label, reward_name]
		else:
			msg = tr("ZONE_CLEARED_FMT") % label
		_zone_hint.show_temp(msg, 4.5)

	# 常驻提示：进化/回血仍在停靠点（机场/航母）——引导去停靠结算
	var _opened := _zone_data.peek_newly_opened()
	if _zone_hint:
		_zone_hint.show_persistent(tr("DOCK_HINT_GO_SETTLE"))

	# 进化内容标记（面板由停靠点打开，spec zone-reward-docking；旧自动弹已移除）
	_evolution_pending = true


# ══════════════════════════════════════════════
#  进化系统（垂直切片，spec ace-system；docs/planning/evolution-vertical-slice.md）
#  切片简化：ACE = player_aircraft（长机）；僚机默认跟随王牌变同款（§2.3）。
# ══════════════════════════════════════════════

## 打开战区结算规划站（Phase 2，用户反馈 2026-07-02）：进化 + 强化当前机 双栏一体。
## 进化出口可能全锁（等级门槛）→ 仍显示灰卡（可视化"练级解锁进化"目标）。
func _open_evolution_offer() -> void:
	if player_aircraft == null or not is_instance_valid(player_aircraft):
		return
	var cur_id: StringName = player_aircraft.get_meta("evo_node", &"")
	if cur_id == &"":
		cur_id = EvolutionSystem.node_id_for_profile(_player_profile_id)
	var exits: Array = []
	if cur_id != &"":
		exits = EvolutionSystem.exits_of(cur_id)
	# 强化三选一已回归等级流（每 3 级卡片事件，spec evolution-attribute-gates）——
	# 结算站强化栏让位（空数组 → evolution_ui 显示 SETTLEMENT_NO_UPGRADE 空态），
	# 结算站保留进化栏；_roll_upgrade_choices 暂留作后备入口（rarity 分槽+pity 全套抽法）
	var choices: Array[Dictionary] = []
	if exits.is_empty() and choices.is_empty():
		return  # 两栏都空 → 不开面板
	if _evolution_ui == null:
		_evolution_ui = EvolutionUI.new()
		add_child(_evolution_ui)
		_evolution_ui.evolution_chosen.connect(_on_settlement_evolution)
		_evolution_ui.upgrade_chosen.connect(_on_settlement_upgrade)
		_evolution_ui.closed.connect(_on_settlement_closed)
	is_paused_for_upgrade = true
	AudioManager.set_music_muffled(true)
	# 暂停与淡入交给表演导演（时间的唯一入口）
	Presentation.present(_evolution_ui, "panel_in")
	# 暂停期 HUD timer 不刷新 → 同步一次
	if hud:
		var _remaining: float = maxf(0.0, WARZONE_PHASE_DURATION - game_time)
		hud.set_warzone_remaining(_remaining, _is_in_boss_phase())
	var lvl: int = survivor_player.level if survivor_player else 1
	# 起点记账（树视图爬线历史的第一格；首次结算时补写）+ 图鉴（起手机=拥有过）
	if cur_id != &"" and archive_enabled():
		AircraftCodex.mark_discovered(cur_id)
		if not player_aircraft.has_meta("evo_node"):
			player_aircraft.set_meta("evo_node", cur_id)
	var history: Array = player_aircraft.get_meta("evo_history", [])
	if history.is_empty() and cur_id != &"":
		history = [cur_id]
	_evolution_ui.show_offer(EvolutionSystem.node_of(cur_id), exits, lvl, choices, history,
		survivor_player.axis_points if survivor_player else {},
		survivor_player.milestone_bonus if survivor_player else {})

## 规划站·进化栏：ACE 手动进化 + 僚机自动跟随同款（spec ace-system §2.3）。面板保持打开。
func _on_settlement_evolution(node_id: StringName) -> void:
	var nd: Dictionary = EvolutionSystem.node_of(node_id)
	if nd.is_empty():
		return
	# 进化双门兜底（spec evolution-attribute-gates §2.3：LV 且 属性；树视图已过滤，此处防御性复查）
	if survivor_player.level < EvolutionSystem.min_level_of(nd):
		return
	if not EvolutionSystem.gates_passed(nd, survivor_player.axis_points):
		return
	# 武器库快照（spec inrun-weapon-inventory）：换型前把机上特殊武器（含强化）收进玩家武器库
	survivor_player.record_special_weapons()
	if not EvolutionSystem.evolve(player_aircraft, node_id, false, archive_enabled()):
		return
	# 主角档案引用同步（三轴里程碑覆写 / 专属技能筛选 / 品类身份跟新机型走）
	var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
	if prof:
		_player_profile = prof
		_player_profile_id = prof.id
		player_aircraft.set_meta("profile_id", prof.id)
	# 僚机默认跟随王牌 → 直接同款（切片版："最终变同款"的最短路径）。
	# ⚠ 必须先于升级重放：evolve 会重置僚机 params，晚了会把刚重放下发的强化抹掉
	if _squad:
		for m in _squad.members:
			if m != player_aircraft and is_instance_valid(m) and not m.is_destroyed:
				EvolutionSystem.evolve(m, node_id, true, false)
				if prof:
					m.set_meta("profile_id", prof.id)
	# ── 换型重放三连（顺序敏感）──
	# ①武器补挂（先挂，后面 railgun 类升级过滤要查装备在位）
	survivor_player.remount_weapons()
	# ②已选升级重放（归属分流全队下发，skills-720 T1；
	#   作废旧"升级绑机型随 params 失效"设计——squad-upgrade-ownership §2.6 同批作废）
	_replay_player_upgrades()
	# ③三轴里程碑重放：全队 params 都被 evolve 换过了，逐机清账重挂——加成跟玩家不跟机体。
	#   必须每机恰好一次：reapply 会先清账再全量重挂，重复调用等于叠两遍。
	for m in _squad_members_alive():
		survivor_player.reapply_all_milestones_to(m, _player_profile)
	EventLogger.log_event("MILESTONE", "Player", "换型重放完成（斗%d/骑%d/策%d 点，%d 机）" % [
		survivor_player.get_axis_points(SurvivorData.AXIS_GLADIATOR),
		survivor_player.get_axis_points(SurvivorData.AXIS_KNIGHT),
		survivor_player.get_axis_points(SurvivorData.AXIS_SCHEMER),
		_squad_members_alive().size()])
	if _evolution_ui:
		_evolution_ui.mark_evolution_applied(node_id, player_aircraft.get_meta("evo_history", []))
	if _zone_hint:
		_zone_hint.show_temp(tr("EVOLUTION_DONE_FMT") % tr(String(nd.get("name_key", ""))), 4.0)

## 规划站·强化栏：应用所选升级（复用等级弹窗时代的全套规则）。面板保持打开。
func _on_settlement_upgrade(upgrade: Dictionary) -> void:
	var evolved_name := _apply_upgrade_choice(upgrade)
	if evolved_name != "" and survivor_player.aircraft:
		survivor_player.aircraft.show_tactic_popup(tr("POPUP_EVOLUTION_FMT") % evolved_name)

## 规划站关闭：恢复游戏（镜像升级 UI 的收尾：解暂停 + 鼠标状态归零防直飞）
func _on_settlement_closed() -> void:
	is_paused_for_upgrade = false
	AudioManager.set_music_muffled(false)
	_set_hard_brake(false)
	is_dragging = false
	# 地勤优化（720 批）：停靠结算关闭（=起飞）后获得一个升级
	if _dock_settlement_open:
		_dock_settlement_open = false
		if int(upgrade_stacks.get("ground_crew", 0)) > 0:
			_queue_bonus_upgrade("ground_crew")
		# 722 sig_fa18e·甲板周转：起飞时弹药过量装填至 2×上限（耗完不回超）+ max_hp 永久 +10（≤+50）
		if int(upgrade_stacks.get("sig_fa18e", 0)) > 0:
			for m in _squad_members_alive():
				if not (m is Aircraft) or m.params == null:
					continue
				var dk_ac: Aircraft = m
				if dk_ac.params.gun:
					dk_ac.ammo = dk_ac.params.gun.max_ammo * 2
				if dk_ac.params.missile:
					dk_ac.missiles_remaining = dk_ac.params.missile.max_count * 2
				var hp_gain: float = float(dk_ac.get_meta("sig_fa18e_hp_gained", 0.0))
				if hp_gain < 50.0:
					dk_ac.params.max_hp += 10.0
					dk_ac.hp += 10.0
					dk_ac.set_meta("sig_fa18e_hp_gained", hp_gain + 10.0)
			EventLogger.log_event("SKILL", "Player", "甲板周转：弹药过量装填 ×2 + max_hp 永久 +10")
		# 722 sig_yf23·落选者：起飞后全队获得 20s STEALTH
		if int(upgrade_stacks.get("sig_yf23", 0)) > 0:
			for m in _squad_members_alive():
				if m is Aircraft:
					m.apply_status(StatusEffects.STEALTH, 20.0)
			EventLogger.log_event("SKILL", "Player", "落选者：起飞获得 20s 隐身")
	# 状态恢复已全部完成，dismiss 只是视觉尾巴（解暂停在 panel_out 第 0 帧）
	Presentation.dismiss(_evolution_ui, "panel_out")

## 系统铁则：世界坐标是否在玩家屏幕可见范围内
## 供 spawner / zone_mission / adbs_manager 刷新前做可见性检查
const VIEW_SPAWN_MARGIN_PX := 200.0  ## 屏外 200px 缓冲，避免贴边刷新被玩家瞥见
## extra_radius：把以 world_pos 为圆心、半径 extra_radius 的圆视作一个整体来测
## 可见（用于"战区整个生成区域是否会露脸"这种判定，而不只是测中心点）
# ══════════════════════════════════════════════
#  停靠点（spec zone-reward-docking）：固定机场 + 停靠结算入口
# ══════════════════════════════════════════════

## 机场解放后的 ALLY 防空伞渐进部署（spec airfield-sam-network）：
## 基础 AA×2；已购“机场防空网授权”时追加 SAM×1。每 4s 一个，顺序 AA→AA→SAM，
## 不要求玩家降落/停靠。参数复用敌版 .tres，阵营翻 ALLY，击杀不给玩家 XP。
const AIRFIELD_ALLY_SPAWN_INTERVAL := 4.0
const FRIENDLY_CARRIER_HULL_HP: float = 300.0

## 纯数据计划供运行时与 bench 共用；SAM 永远是永久授权追加的第三个单位。
static func airfield_ally_plan(has_sam_network: bool) -> Array[Dictionary]:
	var plan: Array[Dictionary] = [
		{"kind": &"aa", "offset": Vector2(-170.0, 150.0)},
		{"kind": &"aa", "offset": Vector2(-170.0, -150.0)},
	]
	if has_sam_network:
		plan.append({"kind": &"sam", "offset": Vector2(240.0, 0.0)})
	return plan


func _spawn_airfield_ally_unit(kind: StringName, world_pos: Vector2,
		asset_group_id: StringName) -> CombatUnit:
	var scene: PackedScene
	var unit_params: Resource
	match kind:
		&"aa":
			scene = _aa_scene
			unit_params = _aa_params
		&"sam":
			scene = _sam_scene
			unit_params = _sam_params
		_:
			return null
	if scene == null:
		return null
	var u: Node = scene.instantiate()
	u.position = world_pos
	if unit_params and "params" in u:
		u.params = unit_params
	if "bullet_manager" in u:
		u.bullet_manager = bullet_manager
	if "missile_manager" in u:
		u.missile_manager = missile_manager
	AllyForce.convert_ground(u)
	add_child(u)
	if u is CombatUnit:
		_friendly_asset_aggro.register_target(asset_group_id, u as CombatUnit)
		return u as CombatUnit
	return null


## 每座机场只承诺一次授权 SAM；生成前即记账，所以被击毁也不会重生。
func _try_deploy_airfield_sam(zone_id: StringName, center: Vector2,
		asset_group_id: StringName) -> bool:
	if _airfield_sam_committed.has(zone_id):
		return false
	_airfield_sam_committed[zone_id] = true
	var sam := _spawn_airfield_ally_unit(&"sam", center + Vector2(240.0, 0.0), asset_group_id)
	if sam == null:
		_airfield_sam_committed.erase(zone_id)
		return false
	EventLogger.log_event("SUPPORT", "AirfieldSAMDeployed", "id=%s center=%s" % [zone_id, center])
	return true


func _deploy_airfield_ally_gradual(zone_id: StringName, center: Vector2,
		asset_group_id: StringName) -> void:
	var has_sam_network := MetaShop.is_airfield_sam_entitled(archive_enabled())
	var plan := airfield_ally_plan(has_sam_network)
	for i in range(plan.size()):
		if i > 0:
			await get_tree().create_timer(AIRFIELD_ALLY_SPAWN_INTERVAL).timeout
			if is_game_over or not is_inside_tree():
				return
		var d: Dictionary = plan[i]
		var kind: StringName = d["kind"]
		if kind == &"sam":
			_try_deploy_airfield_sam(zone_id, center, asset_group_id)
		else:
			var offset: Vector2 = d["offset"]
			_spawn_airfield_ally_unit(kind, center + offset, asset_group_id)
	EventLogger.log_event("EVENT", "AirfieldAllyDeployed",
		"id=%s center=%s AA×2 SAM×%d" % [
			zone_id, center, 1 if _airfield_sam_committed.has(zone_id) else 0])

## ALLY 第三方事件调度（spec global-awareness-roe §2.6）：
##   AWACS：开局 90~150s 首次入场；撤离/被击落后 ≥180s 可再触发
##
## 2026-07-28：友军直升机护送事件（EscortConvoyEvent）已删除 —— 奖励是纯局外功勋、
## Tab 图不画护送队、无无线电，玩家既找不到它也没有局内理由去打，属于纯噪音事件。
func _update_ally_events(delta: float) -> void:
	if is_game_over or _is_in_boss_phase() or _event_director == null:
		return
	if not MetaShop.is_awacs_entitled(archive_enabled()):
		return  # 未购正式局冻结计时器，不积攒“购买后立刻刷新”的债
	var awacs_active := _event_director.find_by_name("awacs_support") != null
	if _awacs_was_active and not awacs_active:
		_awacs_spawn_timer = 180.0   # 撤离/被击落 → 冷却后可再入场
	_awacs_was_active = awacs_active
	if not awacs_active:
		_awacs_spawn_timer -= delta
		if _awacs_spawn_timer <= 0.0:
			_event_director.start(AwacsSupportEvent.new())
			_awacs_was_active = true

## 王牌中队调度（spec ace-rotation-balance）：
## 五支非宿敌队 240s 同窗入池；每局开局洗牌、同局无放回、连续两局首队不相同；
## 前支结束（全灭/撤离）后 ≥150s；540s 后不新刷；同场 ≤1 支；同局不重复同队；
## BOSS 阶段 / boss debug / bench 不触发。
func _prepare_ace_run_order() -> void:
	if not _ace_run_order.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_ace_run_order = AceSquadProfiles.build_run_order(rng, _ace_previous_first)
	if not _ace_run_order.is_empty():
		_ace_previous_first = String(_ace_run_order[0])
	EventLogger.log_event("BALANCE", "AceRotation", "run_order=%s" % str(_ace_run_order))

func _update_ace_support_event(delta: float) -> void:
	if is_game_over or _is_in_boss_phase() or _event_director == null:
		return
	if _boss_debug_mode or _bench_mode:
		return
	if game_time >= ACE_SUPPORT_CUTOFF_S:
		return
	var candidates: Array = []
	for id in AceSquadProfiles.pool_at(game_time):
		if not _ace_squads_used.has(id):
			candidates.append(id)
	if candidates.is_empty():
		return
	if _event_director.find_by_name("ace_support") != null:
		_ace_support_cd = ACE_SUPPORT_COOLDOWN_S
		return
	_ace_support_cd -= delta
	if _ace_support_cd <= 0.0:
		_prepare_ace_run_order()
		var pick := ""
		for id in _ace_run_order:
			if candidates.has(id):
				pick = String(id)
				break
		if pick.is_empty():
			pick = String(candidates[0]) # fail-open：profile 热更新后仍可生成
		_ace_squads_used[pick] = true
		var ev := AceReinforcementEvent.new()
		ev.profile_id = pick
		_event_director.start(ev)

## 宿敌 ORION 独立轨道（spec events/ace-orion / tier §3.8）：中期静默入场、每局一次、
## 不进王牌轮换池、不占"同场 ≤1 支"名额；BOSS 阶段不新刷
func _update_orion_event() -> void:
	if _orion_spawned or is_game_over or _is_in_boss_phase() or _event_director == null:
		return
	if _boss_debug_mode or _bench_mode:
		return
	if game_time < OrionNemesisEvent.TRIGGER_S:
		return
	_orion_spawned = true
	_event_director.start(OrionNemesisEvent.new())

## 机场解放（spec airfield-liberation-zones §3.1）：打光机场地面防空后调用。
## 奖励＝机场本身：圆心开一次性友军补给点 + 即刻渐进部署 ALLY 防空伞（不 dock 门控）。
## 不发军械库奖励、不走普通战区 mark_cleared churn（走 ZoneData.liberate_airfield 独立路径）。
func _liberate_airfield(zone_id: StringName) -> void:
	if not _zone_data:
		return
	var z := _zone_data.get_zone_by_id(zone_id)
	if z.is_empty():
		return
	var center: Vector2 = z["center"]
	var dock_key := String(z.get("dock_name_key", "DOCK_HANEDA_NAME"))
	var asset_group_id := StringName("airfield_%s" % zone_id)
	_friendly_asset_aggro.register_airfield(asset_group_id, center)
	# 状态置 CLEARED（独立路径）
	_zone_data.liberate_airfield(zone_id)
	# 热度：解放机场同"攻克战区"（spec global-awareness-roe §2.4）
	if _spawner and _spawner._roe:
		_spawner._roe.add_heat(RoeDirector.HEAT_ZONE_CAPTURED)
	# 清 zone_mission 记录（升空迎战残余已在 mission_completed 里 _despawn_garrison 撤离）
	if _zone_mission:
		_zone_mission.reset_zone(zone_id)
	# 一次性友军补给点：圆心开机场停靠点（降落＝回血/进化/送僚机，一次性 _spent）
	var dock := DockPoint.new()
	dock.global_position = center
	dock.display_name_key = dock_key
	dock.dock_kind = "airfield"
	dock.mode = self
	dock.docked.connect(_on_dock_docked)
	add_child(dock)
	_dock_points.append(dock)
	if _tactical_map:
		_tactical_map.set_docks(_dock_points)
	# 友军防空伞：解放即刻逐个刷出（不 dock 门控）
	_deploy_airfield_ally_gradual(zone_id, center, asset_group_id)
	if _zone_hint:
		_zone_hint.show_temp(tr("ZONE_AIRFIELD_LIBERATED_FMT") % tr(dock_key), 4.5)
	EventLogger.log_event("ZONE", "AirfieldLiberated",
		"id=%s dock+ally @ %s" % [zone_id, center])

## 航母增援入场（spec zone-reward-docking §2.4）：南界浦贺水道驶入、北上 ~5km 停泊；
## team0 + CIWS 自卫 + 可被击沉（沉没=剩余登舰机会清零）；甲板挂 DockPoint（登舰=结算+回血）
func _summon_reward_carrier() -> void:
	if not _zone_data or _zone_data.carrier_uses_left <= 0:
		return
	if _friendly_carrier and is_instance_valid(_friendly_carrier):
		if _zone_hint:
			_zone_hint.show_temp(tr("CARRIER_ALREADY_ON_STATION"), 3.0)
		return
	var cv_params: NavalParams = load("res://resources/naval/carrier_cv.tres")
	if cv_params == null:
		push_warning("[Carrier] carrier_cv.tres 缺失，航母奖励跳过")
		return
	# ⚠ carrier_cv.tres 是敌方 BOSS 资源（default_team=1）。NavalUnit._ready 里
	# `team = params.default_team` 会覆盖外部设的 team → 必须 duplicate 一份把 default_team
	# 改成 0，否则友军航母被渲染成敌方红、且玩家能锁能打（2026-07-06 playtest 报告）。
	# duplicate(true) 深拷挂点配置，避免污染共享 BOSS 资源。
	cv_params = cv_params.duplicate(true)
	cv_params.default_team = 0
	# friendly-asset-aggro v2：仅友军奖励实例降为 300 船体；敌方 BOSS 资源仍是 1200。
	cv_params.hull_hp_max = FRIENDLY_CARRIER_HULL_HP
	var cv := CarrierShip.new()
	cv.params = cv_params
	cv.team = 0
	# 入场点：南界水道（x 夹在湾内水道带，y 贴南界内侧），北上一段后由航点自然停泊
	var entry_x := 800.0
	if player_aircraft and is_instance_valid(player_aircraft):
		entry_x = clampf(player_aircraft.global_position.x, -1500.0, 2500.0)
	var entry := Vector2(entry_x, MapBoundary.world_half_px() - 600.0)
	cv.position = entry
	cv.initial_heading_deg = 0.0   # 朝北
	cv.waypoints = PackedVector2Array([Vector2(entry_x, entry.y - 5000.0)])
	cv.set_meta("category", "friendly_carrier")
	cv.set_meta("skip_far_cleanup", true)
	# 先写设施 meta 再入树：NavalUnit._ready 动态创建的 MountTarget 首帧即可
	# 继承 DORMANT 硬门，避免生成后至首个 1 Hz tick 之间被自主选靶。
	_friendly_asset_aggro.register_carrier(&"reward_carrier", cv)
	add_child(cv)
	if "bullet_manager" in self:
		cv.bullet_manager = get("bullet_manager")
	if "missile_manager" in self:
		cv.missile_manager = get("missile_manager")
	cv.tree_exited.connect(_on_friendly_carrier_gone)
	_friendly_carrier = cv
	# 甲板停靠点（跟船走；Tab 标记实时位置）
	var deck := DockPoint.new()
	deck.dock_kind = "carrier"
	deck.display_name_key = "DOCK_CARRIER_NAME"
	deck.radius = 500.0
	deck.mode = self
	deck.docked.connect(_on_dock_docked)
	cv.add_child(deck)
	_dock_points.append(deck)
	if _tactical_map:
		_tactical_map.set_docks(_dock_points)
	if _zone_hint:
		_zone_hint.show_temp(tr("CARRIER_INBOUND_HINT"), 5.0)
	EventLogger.log_event("DOCK", "CarrierSummoned",
		"entry=%s uses_left=%d" % [entry.round(), _zone_data.carrier_uses_left])

## 航母离场/被击沉：清引用 + 剩余次数>0 时视为机会流失（spec §2.4）
func _on_friendly_carrier_gone() -> void:
	if not is_inside_tree():
		return  # 场景整体退出中，不做游戏逻辑
	_friendly_asset_aggro.unregister_group(&"reward_carrier")
	_friendly_carrier = null
	_dock_points = _dock_points.filter(func(d): return is_instance_valid(d))
	if _tactical_map and is_instance_valid(_tactical_map):
		_tactical_map.set_docks(_dock_points)
	if _zone_data and _zone_data.carrier_uses_left > 0:
		_zone_data.carrier_uses_left = 0
		if _zone_hint and is_instance_valid(_zone_hint):
			_zone_hint.show_temp(tr("CARRIER_LOST_HINT"), 4.0)
		EventLogger.log_event("DOCK", "CarrierLost", "登舰机会清零")

## 登舰次数用尽 → 航母南撤离场（缓慢驶离；单个单位，任其驶出不强制回收）
func _depart_friendly_carrier() -> void:
	if not _friendly_carrier or not is_instance_valid(_friendly_carrier):
		return
	# 南撤开始即退出据点仇恨，不让玩家跟着移动航母继续吸怪。
	_friendly_asset_aggro.unregister_group(&"reward_carrier")
	_friendly_carrier.waypoints = PackedVector2Array([
		Vector2(_friendly_carrier.global_position.x, MapBoundary.world_half_px() + 2500.0)
	])
	EventLogger.log_event("DOCK", "CarrierDeparting", "uses exhausted")

## 即时发放一件战区奖励（spec zone-reward-docking 修订 2026-07-24：攻克即领，与机场解耦）。
## 僚机/武器/技能(nextgen)/兼容 upgrade dict 四类当场生效；航母走 _summon_reward_carrier 不进这里。
## 从旧 _on_dock_docked 待领循环抽出——现由 _on_zone_mission_completed 攻克瞬间调用。
func _grant_reward_now(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	match String(reward.get("kind", "")):
		"wingman":
			_claim_wingman_reward()
		"weapon":
			_claim_weapon_reward(String(reward.get("weapon", "tail_mine")))
		"nextgen":
			# 次世代技术（spec zone-reward-arsenal §3.3）：按 id 取全条目走升级分发链，
			# 记账与选卡获取完全一致。换机导致不可用的窗口 → 转发一件武器兜底
			var uid: String = String(reward.get("id", ""))
			var up: Dictionary = SurvivorData.upgrade_by_id(uid)
			if survivor_player and not up.is_empty():
				var pj: AircraftParams = player_aircraft.params \
						if player_aircraft and is_instance_valid(player_aircraft) else null
				if SurvivorData.is_upgrade_available_for(up, _player_profile_id, pj,
						upgrade_stacks, _squad_present_classes()):
					_distribute_upgrade(up)
					upgrade_stacks[uid] = upgrade_stacks.get(uid, 0) + 1
					_grant_milestone_plus(up)
				else:
					_claim_weapon_reward("tail_mine")
		_:
			# 兼容 ZoneRewardRegistry 注册的旧 upgrade dict（归属分流 + "+1 轴进度"同选卡）
			if survivor_player:
				_distribute_upgrade(reward)
				var rid: String = reward.get("id", "")
				if rid != "":
					upgrade_stacks[rid] = upgrade_stacks.get(rid, 0) + 1
				_grant_milestone_plus(reward)
	_refresh_squad_effective_stacks()
	if _zone_hint:
		_zone_hint.show_temp(tr("DOCK_REWARD_CLAIMED_FMT") % tr(reward.get("name", "")), 3.0)


## F6 调试入口：直接发放任意战区奖励，不经过 roll、学说、机型、装备或前置技能门控。
## 仍尊重技能 max_stacks；实际效果的运行时条件（例如全向干扰场需要 ESM）不会伪造。
func debug_grant_zone_reward(kind: String, reward_id: String = "") -> bool:
	if survivor_player == null:
		return false
	match kind:
		"carrier":
			_summon_reward_carrier()
		"wingman":
			_claim_wingman_reward()
		"weapon":
			_claim_weapon_reward(reward_id)
		"nextgen":
			var upgrade: Dictionary = SurvivorData.upgrade_by_id(reward_id)
			if upgrade.is_empty():
				return false
			if int(upgrade_stacks.get(reward_id, 0)) >= int(upgrade.get("max_stacks", 1)):
				return false
			_distribute_upgrade(upgrade)
			upgrade_stacks[reward_id] = int(upgrade_stacks.get(reward_id, 0)) + 1
			_grant_milestone_plus(upgrade)
			_refresh_squad_effective_stacks()
		_:
			return false
	EventLogger.log_event("DEBUG_REWARD", "F6", "%s:%s" % [kind, reward_id])
	return true

## 僚机奖励（一次给 2 架）：侧后爆出同型僚机入队，不再附送等级/XP。
## 满编 9 时能塞几架塞几架，一架都塞不下才降级为武器。切片版 ACE = 玩家长机（spec ace-system 简化）。
## 懒创建小队：wingman_count==0 的机型（34 架里 33 架）起手无 _squad，首次拿到僚机时就地建单机小队。
func _claim_wingman_reward(count: int = 2) -> void:
	if not player_aircraft or not is_instance_valid(player_aircraft) or not _player_profile \
			or _ensure_player_squad() == null:
		_claim_weapon_reward("qmaam")
		return
	var spawned := 0
	for _i in count:
		if _squad_members_alive().size() >= 9:
			break  # 满编（spec §2.5 编队上限 9）
		_spawn_reward_wingman()
		spawned += 1
	if spawned == 0:
		_claim_weapon_reward("qmaam")  # 一架都塞不下 → 降级为武器
		if _zone_hint:
			_zone_hint.show_temp(tr("REWARD_WINGMAN_FULL_HINT"), 3.5)
		return

## 生成一架同型僚机入队（与起始僚机同管线：档案注入 + 完美飞行员 + 编队托管）。
## 复用方：+1 僚机奖励（上方）/ 722 双子星 sig_ax00 克隆（不带 ACE XP 副作用）。
## 尾部补挂全队 build（_apply_build_to_new_member——722 批接线：此前该函数零调用点，
## 奖励僚机一直不吃已有 build，属 720 T1 缺口②的漏接；这里一并修复）。
func _spawn_reward_wingman() -> void:
	if not _squad or not player_aircraft or not is_instance_valid(player_aircraft) or not _player_profile:
		return
	# 爆出同型僚机（与起始僚机同管线：档案注入 + 完美飞行员 + 编队托管）
	var wing_base: AircraftParams = _player_profile.wingman_params
	if wing_base == null:
		wing_base = _player_profile.base_params
	if wing_base == null:
		return
	var leader: Aircraft = _squad.leader if (_squad.leader and is_instance_valid(_squad.leader)) else player_aircraft
	var idx := _squad.members.size()
	var ac: Aircraft = _aircraft_scene.instantiate()
	# 号机号取最小空位（不是 members.size()+1）：杜绝阵亡成员被 cleanup 剪掉后撞号、
	# 以及满编时超出数字键 1-9 范围导致切不了控（bug: 战区奖励僚机切不过去）。
	ac.squad_slot = _next_free_squad_slot()
	ac.params = wing_base.duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	SurvivorPlayableSetup.apply(ac, _player_profile, true)
	ac.team = 0
	var offset := _squad.get_formation_offset(idx)
	ac.position = leader.global_position + offset.rotated(leader.heading)
	ac.initial_heading_deg = rad_to_deg(leader.heading)
	ac.altitude = leader.altitude
	ac.target_altitude = leader.altitude
	ac.bullet_manager = bullet_manager
	ac.missile_manager = missile_manager
	ac.flat_altitude = true
	ac.hide_data_label = true
	ac.set_target_tier(Aircraft.AltitudeTier.MID)
	if SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI:
		ac.use_tactical_planner = true
	add_child(ac)
	var ai := AIController.new()
	ai.name = "AI_Wing%d" % idx
	ai.aircraft = ac
	ai.enable_combat = true
	ai.evade_missiles = true
	ai.aggression = 1.0
	ai.skill_level = 1.0
	ai.composure = 1.0
	ai.focus = 1.0
	ai.situational_awareness = 1.0
	ai.self_preservation = 0.5
	ai.engage_duration = 99999.0
	ai.engage_cooldown = 2.0
	ai.patrol_altitude = leader.altitude
	ac.add_child(ai)
	SquadFactory.register_wingman(_squad, ac)
	_maybe_start_wingman_switch_tutorial()
	ac.set_formation_target(leader, _squad.get_wingman_target(idx))
	if _wingman_formation_debug:
		ac.formation_debug = true
	# 入队补挂：按队级账本把对其生效的技能层挂上（含 722 签名技能——双子星"复制技能"语义）
	_apply_build_to_new_member(ac)
	EventLogger.log_event("DOCK", "WingmanReward",
		"slot=%d alive=%d" % [ac.squad_slot, _squad.members.size()])

## 追加武器奖励（spec §2.6，副系统类不动主武器）：
##   loyal_wingman / tail_mine 共用"机尾释放位"（params 互斥约定）→ 已占位时降级 QMAAM；
##   QMAAM 已有副槽时改为补弹（max_count 叠加）
func _claim_weapon_reward(weapon: String) -> void:
	if not player_aircraft or not is_instance_valid(player_aircraft) or player_aircraft.params == null:
		return
	var p: AircraftParams = player_aircraft.params
	match weapon:
		"loyal_wingman":
			if p.loyal_wingman != null or p.torpedo != null:
				_claim_weapon_reward("qmaam")
				return
			p.loyal_wingman = load("res://resources/a10_loyal_wingman.tres").duplicate(true)
		"tail_mine":
			if p.torpedo != null or p.loyal_wingman != null:
				_claim_weapon_reward("qmaam")
				return
			p.torpedo = load("res://resources/a10_torpedo.tres").duplicate(true)
		"rocket":
			# 军械库扩容（spec zone-reward-arsenal §2.2）：Hydra 火箭泛化全机型（legacy 字段直挂）。
			# 已持有（A-10 系自带/重复奖励，roll 侧已过滤——这里是 roll 后换机窗口的兜底）→ 降级补 QMAAM
			if p.rocket != null:
				_claim_weapon_reward("qmaam")
				return
			p.rocket = load("res://resources/a10_rocket.tres").duplicate(true)
			# inrun_reward meta：现已无人读（record_special_weapons 2026-07-23 去掉门，火箭一律入库）；
			# 留标记仅作"此火箭为战区所得"的溯源，不影响继承逻辑
			p.rocket.set_meta("inrun_reward", true)
			player_aircraft.rockets_remaining = p.rocket.max_ammo
			if survivor_player:
				survivor_player.record_special_weapons()
		"railgun", "laser", "esm_pod":
			# 电磁炮/激光/ESM（equipment 数组类；战区军械库）
			if p.get_equipment_of_kind(weapon) != null:
				_claim_weapon_reward("qmaam")
				return
			var res_path := "res://resources/x02_railgun.tres" if weapon == "railgun" \
					else ("res://resources/x02_laser.tres" if weapon == "laser" else "res://resources/esm_pod.tres")
			if p.equipment == null:
				var arr: Array[EquipmentParams] = []
				p.equipment = arr
			p.equipment.append(load(res_path).duplicate(true))
			player_aircraft._publish_equipment_to_legacy()
			if survivor_player:
				survivor_player.record_special_weapons()
		_:
			var q: MissileParams = load("res://resources/qmaam_missile.tres").duplicate(true)
			if p.secondary_missile != null:
				p.secondary_missile.max_count += q.max_count  # 已有副槽 → 补弹
				if "secondary_missile_count" in player_aircraft:
					player_aircraft.secondary_missile_count += q.max_count
			else:
				p.secondary_missile = q
				if "secondary_missile_count" in player_aircraft:
					player_aircraft.secondary_missile_count = q.max_count
	EventLogger.log_event("DOCK", "WeaponReward", weapon)

## 停靠成功 → 停靠结算（spec zone-reward-docking §2.2，修订 2026-07-24）：
## 回血 + 打开进化面板。战区奖励已在攻克瞬间即领（_grant_reward_now），此处不再领奖。
func _on_dock_docked(dock: DockPoint) -> void:
	EventLogger.log_event("DOCK", "SettlementOpen", dock.display_name_key)
	_dock_settlement_open = true
	# 生涯档案：停机计数（按 dock_kind 分机场/航母；Debug 临时机场不污染档案）
	if archive_enabled() and dock.dock_kind != "debug_airfield":
		CareerArchive.record_docking(dock.dock_kind)
	# 回血（spec 修订 2026-07-24：回血 = 停靠功能，与进化同在机场/航母）：全队满血
	var healed := 0
	for u in CombatUnit.all_units:
		if u is Aircraft and u.is_player_squad() and not u.is_destroyed:
			var acu := u as Aircraft
			if acu.params:
				acu.hp = acu.params.max_hp
				healed += 1
	EventLogger.log_event("DOCK", "SquadHealed", "n=%d" % healed)
	# 停靠必送 1 架僚机（用户 2026-07-24：每次停靠——机场/航母不除外——复制一架王牌机入队）；
	# 满编 9 则跳过（不降级，停靠僚机是额外福利，不是奖励 roll）。
	# 生涯商店门控（career-shop §3.2）：正式局需购入 dock_wingman 才送；
	# 非正式局（bench/boss debug）视为已拥有，保旧行为与回归确定性
	var dock_wingman_active: bool = not archive_enabled() \
			or MetaShop.is_owned(MetaShop.ITEM_DOCK_WINGMAN)
	if dock_wingman_active and _player_profile and _ensure_player_squad() != null \
			and _squad_members_alive().size() < 9:
		_spawn_reward_wingman()
		if _zone_hint:
			_zone_hint.show_temp(tr("DOCK_WINGMAN_GRANTED"), 3.0)
	_evolution_pending = false
	if _zone_hint:
		_zone_hint.hide_persistent()
	# 航母停靠：扣全局登舰次数（限 2 次，用尽即南撤；spec §2.4）。回血已由上方全队处理。
	if dock.dock_kind == "carrier":
		if _zone_data:
			_zone_data.carrier_uses_left = maxi(0, _zone_data.carrier_uses_left - 1)
			if _zone_hint:
				_zone_hint.show_temp(tr("CARRIER_USES_LEFT_FMT") % _zone_data.carrier_uses_left, 3.5)
			EventLogger.log_event("DOCK", "CarrierLanding", "uses_left=%d" % _zone_data.carrier_uses_left)
			if _zone_data.carrier_uses_left <= 0:
				_depart_friendly_carrier()
	elif dock.dock_kind == "airfield":
		# 一次性机场（spec zone-reward-docking §2.2 修订）：停靠一次即失效，标记消失
		# （主图 + Tab）；机场的 ALLY 防空驻军是独立实体，原地保留不受影响。
		dock.mark_spent()
		if _zone_hint:
			_zone_hint.show_temp(tr("DOCK_AIRFIELD_SPENT_FMT") % tr(dock.display_name_key), 3.0)
		EventLogger.log_event("DOCK", "AirfieldSpent", dock.display_name_key)
		# 首次机场停靠 → 生涯商店 dock_wingman 上架提示（career-shop §3.2；后弹覆盖前一条 toast，
		# 上新信息优先于机场关闭信息）
		if archive_enabled() and CareerArchive.get_dockings("airfield") == 1 \
				and not MetaShop.is_owned(MetaShop.ITEM_DOCK_WINGMAN) and _zone_hint:
			_zone_hint.show_temp(tr("METASHOP_LISTED_TOAST"), 5.0)
	_open_evolution_offer()

func is_world_pos_visible(world_pos: Vector2, extra_radius: float = 0.0) -> bool:
	if not _camera_ctrl:
		return false
	return _camera_ctrl.is_world_pos_visible(world_pos, VIEW_SPAWN_MARGIN_PX + extra_radius)

## 是否已进入 BOSS 阶段（BOSS 已解锁 / 玩家选中 BOSS / BOSS 已 spawn 任一即为真）
## 用途：game_time 冻结判定 + HUD 文案切换 + 各种 BOSS 阶段守卫
func _is_in_boss_phase() -> bool:
	if _boss_spawned:
		return true
	if _zone_data and (_zone_data.is_boss_phase() or _zone_data.boss_unlocked):
		return true
	return false

## BOSS 阶段的【唯一对外真源】（spec survivor-loop §3）——
## 子系统（spawner / adbs / 事件层）一律问这里，不要各自读 ZoneData.is_boss_phase()。
## 语义差异是历史 bug 的根：ZoneData.is_boss_phase() 只在玩家把 BOSS 圈设为 selected 后才为真，
## 而 BOSS 一解锁（boss_unlocked=true，BossEncounterEvent 已在 PRE_STAGE 接近中）就该停摆全部
## 常规刷怪 / 随机事件。旧闸门让整个 PRE_STAGE 段仍在刷杂鱼 + 触发城区直升机事件。
func is_boss_phase() -> bool:
	return _is_in_boss_phase()

## 战区奖励 roll 的玩家上下文快照（spec zone-reward-arsenal §3.1，注入给 ZoneData）
func _build_reward_roll_context() -> Dictionary:
	return {
		"aircraft_id": _player_profile_id,
		"start_aircraft_id": _starting_profile_id,
		"params": player_aircraft.params if player_aircraft and is_instance_valid(player_aircraft) else null,
		"stacks": upgrade_stacks,
		"squad_classes": _squad_present_classes(),
		# 成就门控（spec career-archive §3.3）：无人机猎手未解锁 → 忠诚僚机不进武器子池。
		# 本键是正式局唯一真源；缺键 fail-closed，防调用方漏注入时提前泄漏解锁奖励
		"loyal_wingman_unlocked": CareerArchive.is_achievement_unlocked(CareerArchive.ACHIEVEMENT_UAV_HUNTER),
	}

## 生涯档案入档守卫（spec career-archive §3.5）：bench 压测局与 boss debug 局不入档，
## 也不参与 BOSS 档案轮换（history 传空 → BossRegistry 走旧纯随机）
func archive_enabled() -> bool:
	return not _bench_mode and not _boss_debug_mode

## 成就解锁反馈（spec career-archive §2.4）：临时 toast。
## 刻意不用 show_warning_banner —— 红色警告横幅是 BOSS 专属语义（ace-squadron-tier §2.6）
func _on_achievement_unlocked(achievement_id: String) -> void:
	if _zone_hint:
		_zone_hint.show_temp(tr("ACHIEVEMENT_%s_TOAST" % achievement_id.to_upper()), 6.0)

## 局时延长（spec ace-support-squadron §2.5：王牌支援中队全灭 = 整局 +1 分钟）。
## 与出界补给时间税（game_time += 15）同一注入语义、方向相反：game_time 向
## WARZONE_PHASE_DURATION 爬升逼近 BOSS，倒拨 = BOSS 推迟 = 战区阶段延长。
## HUD 倒计时每帧读 game_time → 当帧可见 +1:00 跳变。BOSS 阶段 game_time 已冻结，不适用。
func grant_time_extension(seconds: float) -> void:
	if _is_in_boss_phase():
		return
	game_time = maxf(0.0, game_time - seconds)
	EventLogger.log_event("EVENT", "TimeExtension", "+%.0fs (game_time=%.1f)" % [seconds, game_time])

## 10 分钟战区阶段超时检查（即时切换）
## - 取消所有正在进行的战区任务（TGT 标记去掉、不再发完成信号、不再发奖励）
## - 关闭所有 AVAILABLE 战区（包括玩家正在打的）
## - 立即解锁 BOSS，_update_boss_phase 下一帧会启动 BossEncounterEvent
## - 战区里残留的敌人继续存活，可被击杀给经验，但已不构成"任务"
func _check_warzone_phase_timeout() -> void:
	if _warzone_phase_ended:
		return
	if game_time < WARZONE_PHASE_DURATION:
		return
	if not _zone_data:
		return
	_warzone_phase_ended = true
	_zone_data.phase_ended = true

	# 取消所有战区任务（敌人留场，但 TGT 标记 + 完成信号路径都断掉）
	if _zone_mission:
		_zone_mission.cancel_all_zone_missions()

	# 关掉所有 AVAILABLE / SELECTED 状态的战区
	_zone_data.lock_all_open_zones_except(&"")
	if _zone_data.selected_id != &"" and _zone_data.selected_id != &"BOSS":
		_zone_data.set_state(_zone_data.selected_id, ZoneData.State.LOCKED)
		_zone_data.selected_id = &""

	# 立即解锁 BOSS
	_zone_data.finalize_boss_placement()
	_zone_data.boss_unlocked = true
	_zone_data.set_state(&"BOSS", ZoneData.State.AVAILABLE)

	if _zone_hint:
		_zone_hint.show_temp(tr("BOSS_ZONE_READY"), 5.0)
	EventLogger.log_event("PHASE", "WarzoneTimeout",
		"game_time=%.1f → all zones cancelled, BOSS unlocked" % game_time)

## F6 Debug：通过独立的临时机场进入正式停靠结算链。
## 不读取、解放或消费地图上的三座机场；每次调用创建一个临时 DockPoint，用完即释放，因而无限可用。
func debug_visit_airfield() -> void:
	if _zone_data == null or player_aircraft == null or not is_instance_valid(player_aircraft):
		push_warning("debug_visit_airfield: 战局或玩家机未初始化")
		return
	if _evolution_ui and _evolution_ui.visible:
		return
	var target_dock := DockPoint.new()
	target_dock.global_position = player_aircraft.global_position
	target_dock.display_name_key = "DOCK_HANEDA_NAME"
	target_dock.dock_kind = "debug_airfield"
	target_dock.mode = self
	add_child(target_dock)
	EventLogger.log_event("DOCK", "DebugVisitAirfield", "temporary=true map_airfields_untouched=true")
	_on_dock_docked(target_dock)
	target_dock.queue_free()

## F6 Debug：跳到 BOSS 战。boss_id 为空则按地图池随机
##
## 实现刻意【不复制解锁逻辑】—— 只把 game_time 推到阈值，然后调用真实的
## _check_warzone_phase_timeout()，由它走完取消任务 / 关战区 / finalize_boss_placement /
## boss_unlocked 全套。旧版 debug 只标了 A/B/C cleared 却从没设 boss_unlocked，
## 所以 _update_boss_phase() 永远不触发——按钮点了等于没点。
func debug_skip_to_boss(boss_id: String = "") -> void:
	if _zone_data == null:
		push_warning("debug_skip_to_boss: ZoneData 未初始化")
		return
	if _is_in_boss_phase():
		EventLogger.log_event("ZONE", "DebugSkipBoss", "已在 BOSS 阶段，忽略")
		return

	debug_boss_id_override = boss_id
	# 计时器清零：HUD 的 remaining = WARZONE_PHASE_DURATION - game_time
	game_time = WARZONE_PHASE_DURATION
	# 立即执行（而非等下一物理帧），让按下按钮到 BOSS 出场之间没有不确定的延迟
	_check_warzone_phase_timeout()
	_update_boss_phase()

	EventLogger.log_event("ZONE", "DebugSkipBoss",
		"boss=%s game_time→%.0f" % [boss_id if boss_id != "" else "(random)", game_time])

## BOSS 阶段（P4）—— 10 分钟到点（或当前 SELECTED 战区结算后）→ 启动 BossEncounterEvent（事件层接管全部生命周期）
## 本函数职责单一：检测解锁 → 启动事件。所有 PRE_STAGE/ENGAGED/VICTORY 状态流转、
## directive 下发、UI/BGM 切换都收敛到 BossEncounterEvent；事件回调见 on_boss_*。
func _update_boss_phase() -> void:
	if _is_victory or is_game_over:
		return
	if not _zone_data or not _zone_data.boss_unlocked:
		return
	if _boss_unlock_announced:
		return
	_boss_unlock_announced = true
	if not _event_director:
		push_error("BOSS unlock: EventDirector not initialized")
		return
	var bz := _zone_data.boss_zone
	# debug_boss_id_override 非空 → 绕过地图池随机，强制指定关底 BOSS（F6 面板写入）
	# 生涯档案 BOSS 轮换（spec career-archive §3.1）：正式局注入档案 history；
	# 非正式局传空 → BossRegistry 保持旧纯随机行为
	var boss_history: Dictionary = CareerArchive.build_boss_history() if archive_enabled() else {}
	var ev := BossEncounterEvent.new(bz["center"], _zone_data.boss_heading_deg, _map_id,
		debug_boss_id_override, boss_history)
	_event_director.start(ev)

# ── BossEncounterEvent 回调（事件层主动调用）──

## ENGAGED：进入 boss phase（停摆常规系统）+ 临时提示
func on_boss_engaged(ev) -> void:
	_boss_spawned = true
	if _zone_data and _zone_data.selected_id != &"BOSS":
		_zone_data.select_zone(&"BOSS")
	if _zone_hint:
		_zone_hint.hide_persistent()
		_zone_hint.show_temp(tr("ZONE_HINT_BOSS_ARRIVAL"), 5.0)
	# 生涯档案：BOSS 接战入档（轮换指针跟随实际刷出的 BOSS；spec career-archive §2.2）
	if archive_enabled() and ev != null and "encounter" in ev and ev.encounter != null:
		CareerArchive.record_boss_encounter(String(ev.encounter.boss_id))
	# 无线电：BOSS 进入交战的第二段挑衅（spec radio-chatter §3.3）
	if _radio and ev != null and "encounter" in ev and ev.encounter != null:
		_radio.say_boss_sequence(ev.encounter.boss_id, "engage", ev.encounter.callsign_prefix)

# ══════════════════════════════════════════════
#  无线电：击杀触发（spec radio-chatter §3.3）
# ══════════════════════════════════════════════
##
## 订阅 EventLogger.kill_recorded。注意该信号只带【呼号字符串 + team】，不带单位引用 ——
## 正合本系统"入队即快照、绝不持有 Aircraft 引用"的契约（spec §4）。
## 一次击杀最多产生 2 条（阵亡者弹射 + 击坠者回报），实际频率由全局冷却 + 自身冷却 + 概率三层压制。
func _on_radio_kill_recorded(killer: String, victim: String, _weapon_kind: String,
		killer_team: int, victim_team: int, victim_voiced: bool) -> void:
	# 加力充能：小队空中击杀 +4s（spec afterburner-mode §3.6；不依赖 radio 是否存活。
	# ALLY 番队 team ≠ TEAM_PLAYER 自动排除；地面击杀在 spawner 的 roe 热度挂点同步 +4s）
	if killer_team == CombatUnit.TEAM_PLAYER and victim_team == CombatUnit.TEAM_HOSTILE:
		afterburner_charge.on_kill_charge()
	if _radio == null or not is_instance_valid(_radio):
		return

	# 1) 敌方累计减员 → 阶段性哀嚎。
	# 无人机损失【照常计数】—— 说话的是敌方指挥部（有人），它一样会为损失无人机而哀嚎。
	if victim_team == CombatUnit.TEAM_HOSTILE:
		_radio.notify_enemy_loss()

	# 2) 阵亡者的弹射呼叫。自家人优先级远高于敌方（spec §2.3）。
	# 无人机不喊弹射（没有飞行员可弹射）——spec §2.8 等级门。
	if victim_voiced:
		var eject_trigger := "eject_friendly" if victim_team == CombatUnit.TEAM_PLAYER else "eject"
		_radio.say(eject_trigger, victim, RadioChatter.color_for_team(victim_team))

	# 3) 击坠回报：只有僚机报，玩家本机不自己报给自己听
	if killer_team == CombatUnit.TEAM_PLAYER and killer != "Ultra":
		_radio.say("splash", killer, RadioChatter.color_for_team(killer_team))

## 队友被导弹咬住 → "break break break"。只播自家人的，敌机规避不值得占用频道。
func _on_radio_evasion_started(callsign: String, team: int) -> void:
	if _radio == null or not is_instance_valid(_radio):
		return
	if team != CombatUnit.TEAM_PLAYER:
		return
	_radio.say("break", callsign, RadioChatter.color_for_team(team))

## 玩家启动加力模式（充能制）→ "全队加力冲刺" 呼叫。语义是主动脱离/占位，不是躲导弹。
func _on_radio_afterburner_engaged(callsign: String, team: int) -> void:
	if _radio == null or not is_instance_valid(_radio):
		return
	if team != CombatUnit.TEAM_PLAYER:
		return
	_radio.say("afterburner", callsign, RadioChatter.color_for_team(team))

## 新僚机编入。开局 RADIO_JOIN_SUPPRESS_SEC 内的编入是"建队"不是"归队"，不播。
const RADIO_JOIN_SUPPRESS_SEC := 5.0
func _on_radio_wingman_joined(callsign: String, team: int) -> void:
	if _radio == null or not is_instance_valid(_radio):
		return
	if team != CombatUnit.TEAM_PLAYER or game_time < RADIO_JOIN_SUPPRESS_SEC:
		return
	_radio.say("wingman_join", callsign, RadioChatter.color_for_team(team))

## VICTORY：触发胜利
func on_boss_victory(ev) -> void:
	var boss_id := ""
	if ev != null and "encounter" in ev and ev.encounter != null:
		boss_id = String(ev.encounter.boss_id)
	# 生涯档案：BOSS 击败入档（击败过 → 下局轮换必换；spec career-archive §3.1）
	if archive_enabled() and not boss_id.is_empty():
		CareerArchive.record_boss_defeat(boss_id)
	_on_victory(boss_id)

## 事件结束（任何原因）—— HUD 自动随 encounter.active=false 隐藏，无需特别清理
func on_boss_event_finished(_ev) -> void:
	pass

## boss_id 只用于结算面板副标题（"XX 已被击毁"），空串 → 通用文案
func _on_victory(boss_id: String = "") -> void:
	if _is_victory:
		return
	_is_victory = true
	is_game_over = true  # 复用 game_over 流程，阻止后续物理
	if archive_enabled():
		CareerArchive.record_victory(_map_id)
	EventLogger.log_event("VICTORY", "Clear", "BOSS defeated — game cleared")
	if hud:
		var merit_earned := MeritLedger.settle_run(
			survivor_player.total_xp_gained, MeritLedger.SETTLE_VICTORY)
		hud.show_victory(survivor_player.level, game_time, _spawner.kill_count,
			survivor_player.total_xp_gained, merit_earned, boss_id)

func _zone_label(zone_id: StringName) -> String:
	if not _zone_data:
		return str(zone_id)
	var z := _zone_data.get_zone_by_id(zone_id)
	if z.is_empty():
		return str(zone_id)
	# 机场解放战区：toast 显示机场名（"羽田机场"）而非 ✈ 圆心字符
	if _zone_data.is_airfield(zone_id):
		return tr(String(z.get("dock_name_key", z.get("name_key", ""))))
	return z.get("label", str(zone_id))

## 把玩家传送回边界内侧 + 机头朝向地图中心
## 回归时只钳到边界线上（0 margin），玩家从边缘线继续飞回战区，没有"瞬移闪烁"感
const RESPAWN_MARGIN_PX := 0.0
const RESPAWN_INWARD_TARGET_PX := 2500.0 ## 传送后 target_position 指向原点方向的距离

func _turn_player_inward() -> void:
	if not player_aircraft or not _map_boundary:
		return
	var r := _map_boundary.get_world_rect()
	var p := player_aircraft.global_position
	var was_outside := not r.has_point(p)
	# 只在真越界时钳回边界线上（0 margin，不再把玩家拉离边缘几公里）
	p.x = clampf(p.x, r.position.x, r.end.x)
	p.y = clampf(p.y, r.position.y, r.end.y)
	player_aircraft.global_position = p
	# heading 指向原点（0=北，顺时针）：atan2(-p.x, p.y)
	if not p.is_equal_approx(Vector2.ZERO):
		player_aircraft.heading = atan2(-p.x, p.y)
	player_aircraft.bank_angle = 0.0
	# 只有越界被钳回时才清丝带 + 同步相机，避免边界内点取消菜单出现视觉瞬跳
	if was_outside:
		player_aircraft.clear_trail()
		camera.global_position = p
	var inward := (Vector2.ZERO - p).normalized() if not p.is_equal_approx(Vector2.ZERO) else Vector2(0, -1)
	player_aircraft.target_position = p + inward * RESPAWN_INWARD_TARGET_PX
	# 僚机一起按当前阵型传送到操控机身边（出界回归时避免僚机被甩在界外/远处掉队）。
	# 只在真越界被钳回时执行；slot 用 squad.get_wingman_target（leader=当前操控机，heading 已更新）。
	if was_outside and _squad:
		for wm in _squad.members:
			if not is_instance_valid(wm) or wm.is_destroyed or wm == player_aircraft:
				continue
			var wm_ai := _get_ai(wm)
			var slot_idx: int = wm_ai.squad_index if wm_ai else 1
			var slot_pos: Vector2 = _squad.get_wingman_target(slot_idx)
			if slot_pos == Vector2.INF:
				slot_pos = p  # 兜底：直接落到玩家落点
			wm.global_position = slot_pos
			wm.heading = player_aircraft.heading
			wm.bank_angle = 0.0
			wm.altitude = player_aircraft.altitude
			wm.target_altitude = player_aircraft.target_altitude
			wm.clear_trail()


## Sentinel + Lv15 + 常规混编上叠一支真实王牌事件与已购（bench fail-open）F-15 截击支援。
## 放在文件尾，避免新增 bench helper 让主流程的文档锚点整体漂移。
func _bench_force_ace_support() -> void:
	_spawner._spawn_commander_squad(5)
	var ev := AceReinforcementEvent.new()
	ev.profile_id = "marathon"
	_event_director.start(ev)
	var support_count := 0
	for child in get_children():
		if child is Aircraft and child.has_meta("ace_intercept_support"):
			support_count += 1
	print("[Bench] ace_support_stress spawned F-15 support=%d (expected 2)" % support_count)


## 终局链路：先击坠长机验证存活僚机接管，再同时击坠全队验证 Game Over。
func _bench_setup_survivor_death() -> void:
	_spawner._dynamic_enemy_cap = 0
	_claim_wingman_reward(2)
	_bench_death_original_id = player_aircraft.get_instance_id()
	print("[Bench] survivor_death ready: squad_alive=%d leader_id=%d" % [
		_squad_members_alive().size(), _bench_death_original_id])


func _bench_update_survivor_death() -> void:
	if _bench_death_stage == 0 and _bench_elapsed >= 2.0:
		_bench_death_stage = 1
		player_aircraft.invulnerable = false
		player_aircraft.take_damage(player_aircraft.hp + 1000.0, null, "bench_leader_down")
		print("[Bench] survivor_death: leader down id=%d" % _bench_death_original_id)
	elif _bench_death_stage == 1 and _bench_elapsed >= 3.0:
		_bench_takeover_verified = player_aircraft != null and is_instance_valid(player_aircraft) \
				and player_aircraft.get_instance_id() != _bench_death_original_id \
				and not player_aircraft.is_destroyed
		if not _bench_takeover_verified:
			_bench_finish_now("terminal=takeover_failed\n%s\n" % _bench_runtime_status(), 1)
			return
		_bench_death_stage = 2
		print("[Bench] survivor_death: takeover ok new_leader_id=%d; destroying squad" % \
				player_aircraft.get_instance_id())
		for member in _squad_members_alive():
			member.invulnerable = false
			member.take_damage(member.hp + 1000.0, null, "bench_squad_wipe")


## Bench 墙钟监控：即使 game_over / 升级暂停让 _physics_process 早退，也能留下终态并退出。
## 每 10 秒才做一次单位计数；正式局不进入此分支。
func _bench_wall_watchdog() -> void:
	if _bench_wall_started_msec <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _bench_last_heartbeat_msec >= 10000:
		_bench_last_heartbeat_msec = now
		print("[Bench] heartbeat wall=%.1fs sim=%.1fs %s" % [
			float(now - _bench_wall_started_msec) / 1000.0, _bench_elapsed,
			_bench_runtime_status()])

	if is_game_over:
		if _bench_scenario == "evolution_growth" and _growth_bench != null:
			_bench_finish_now(_growth_bench.finish("game_over") + _bench_runtime_status(), 0)
			return
		var expected := _bench_scenario == "survivor_death"
		_bench_finish_now("terminal=game_over expected=%s\n%s\n" % [
			str(expected), _bench_runtime_status()], 0 if expected else 1)
		return
	if get_tree().paused and not is_paused_for_upgrade:
		_bench_finish_now("terminal=unexpected_tree_pause\n%s\n" % _bench_runtime_status(), 1)
		return

	if is_paused_for_upgrade:
		if _bench_pause_started_msec <= 0:
			_bench_pause_started_msec = now
		elif now - _bench_pause_started_msec >= 5000:
			_bench_finish_now("terminal=upgrade_pause_stuck\n%s\n" % _bench_runtime_status(), 1)
	else:
		_bench_pause_started_msec = 0


func _bench_runtime_status() -> String:
	var player_valid := player_aircraft != null and is_instance_valid(player_aircraft)
	var player_dead := true
	var player_hp := -1.0
	var debug_skills_open := false
	var debug_spawn_open := false
	for child in get_children():
		if child is SurvivorDebugSkills:
			debug_skills_open = child.visible
		elif child is SurvivorDebugSpawn:
			debug_spawn_open = child.visible
	if player_valid:
		player_dead = player_aircraft.is_destroyed
		player_hp = player_aircraft.hp
	return "game_over=%s upgrade_paused=%s tree_paused=%s presentation_state=%s hard_pause=%s debug_skills=%s debug_spawn=%s pause_menu=%s tactical_map=%s takeover=%s victory=%s player_valid=%s player_dead=%s hp=%.1f level=%d aircraft=%d enemies=%d kills=%d" % [
		str(is_game_over), str(is_paused_for_upgrade), str(get_tree().paused),
		str(Presentation.state), str(Presentation.time.is_hard_paused()), str(debug_skills_open),
		str(debug_spawn_open), str(_pause_menu != null and _pause_menu.visible),
		str(_tactical_map != null and _tactical_map.is_open()), str(_bench_takeover_verified),
		str(_is_victory), str(player_valid),
		str(player_dead), player_hp, (survivor_player.level if survivor_player else 0),
		_count_aircraft_alive(), _count_enemy_alive(), (_spawner.kill_count if _spawner else 0)]


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	if _bench_finished:
		return
	_bench_finished = true
	var br: Node = get_tree().root.get_node_or_null("/root/BenchRunner")
	if br and br.has_method("bench_finish"):
		br.call("bench_finish", summary, exit_code)
