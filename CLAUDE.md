# CLAUDE.md

本文件为 Claude Code 提供 AGL 项目的代码地图与工作约定。每次对话自动加载，作为主索引使用。

## Project Overview

**AGL** 是俯视 2D 战斗机模拟沙盒，用 **Godot 4.6** + **GDScript** + **GL Compatibility** 渲染器。玩家以 RTS 方式点击操控战斗机（点击地图位置 → 飞机自主转弯飞向目标），飞机遵循较真实的航空物理。极简线框美术。2D 场景 + 虚拟高度（高度仅作为数值存在，通过图标缩放可视化）。

两个模式：
- **沙盒**（`scenes/main.tscn`）— 自由飞行/战斗测试，F1-F5 快捷键生成编队
- **生存模式**（`scenes/survivor_mode.tscn`）— 无尽波次，击杀升级，20+ 种升级含进化技能

## Running the Game

- 在 Godot 4.6+ 打开 `project.godot`
- F5 运行，入口场景 `scenes/main_menu.tscn`
- 调试面板在沙盒模式内置
- F9 导出战斗日志。**编辑器模式**写到项目内 `logs/combat_log_*.txt`（`/logs/` 被 .gitignore 排除）；**导出包**写到 `user://combat_log_*.txt`。路径切换逻辑在 `event_logger.gd:dump_to_file`。配合 `.claude/hooks/open-latest-log.sh`（UserPromptSubmit hook）在下次消息时自动打开最新 log
- 生存模式 F11 切换友方僚机编队调试覆盖层（橙线 → 阵型槽位 / 蓝射线 → 当前 hdg / 黄射线 → 目标 hdg / 文本: branch + slot_d + bank delta）；F12 抓一帧编队状态快照到控制台 + EventLogger

无正式测试框架，通过运行时观察 + EventLogger 日志调试。

## Repository Layout

```
AGL/
├── project.godot              # Godot 项目配置（含 AutoLoad: EventLogger, CallsignDB）
├── scenes/
│   ├── main.tscn              # 沙盒主场景（Main + BulletManager + MissileManager + Camera2D）
│   ├── main_menu.tscn         # 主菜单（入口场景）
│   ├── survivor_mode.tscn     # 生存模式
│   ├── survivor_map_select.tscn # 生存模式地图选择（先于机型选择）
│   ├── survivor_select.tscn   # 生存模式机型选择界面
│   ├── aircraft.tscn          # 飞机模板（通用）
│   ├── missile.tscn           # 导弹模板
│   ├── sam_unit.tscn          # 防空导弹车
│   ├── aa_gun_unit.tscn       # 高射炮
│   └── radar_station.tscn     # 雷达站
├── scripts/
│   ├── main.gd                # 沙盒主场景：输入/雷达锁定/编队生成（地形/相机委托共享模块）
│   ├── terrain_renderer.gd    # TerrainRenderer：地形/网格/云层绘制（沙盒+生存共享）
│   ├── camera_controller.gd   # CameraController：缩放/平移/hover/坐标转换（沙盒+生存共享）
│   ├── main_menu.gd           # 主菜单
│   ├── aircraft.gd            # Aircraft 实体（~2500 行，物理+战斗+武器+视觉）
│   ├── aircraft_params.gd     # AircraftParams Resource
│   ├── ai_controller.gd       # AI 状态机（巡逻/交战/规避/编队）
│   ├── combat_unit.gd         # 战斗单位基类（Aircraft/GroundUnit 共享接口）
│   ├── missile.gd             # 导弹实体（PN 制导）
│   ├── missile_manager.gd     # 导弹管理器（命中检测/在飞查询/近炸AOE）
│   ├── missile_params.gd      # MissileParams Resource
│   ├── bullet_manager.gd      # 机炮子弹管理（物理+命中）
│   ├── gun_params.gd          # GunParams Resource
│   ├── rocket_params.gd       # RocketParams Resource（无制导火箭弹）
│   ├── combat_params.gd       # CombatParams Resource（AI 行为风格）
│   ├── flare_params.gd        # FlareParams Resource（含 fail_chance 失误概率 + head_on_fail_reduction 对头减免）
│   ├── playable_aircraft.gd   # PlayableAircraft Resource（主角档案，UI+生存调味）
│   ├── squad.gd               # 编队数据结构 + 6 种阵型计算
│   ├── ground_unit.gd         # 地面单位基类
│   ├── sam_unit.gd            # SAM（防空导弹车，360° 雷达）
│   ├── aa_gun_unit.gd         # AAA（高射炮，独立炮塔）
│   ├── radar_station.gd      # 雷达站（数据链共享）
│   ├── ground_convoy.gd       # 地面车队
│   ├── event_logger.gd        # 全局事件日志（AutoLoad）
│   ├── callsign_db.gd         # 呼号分配器（AutoLoad）
│   ├── trail_ribbon.gd        # 烟迹/尾迹渲染
│   ├── bullet_manager.gd      # 子弹管理器
│   ├── hud.gd                 # 沙盒 HUD
│   ├── debug_panel.gd         # 调试面板（策略显示/生成按钮）
│   ├── game_constants.gd      # 全局物理/队伍颜色常量（GameConstants）
│   ├── theme_colors.gd        # 生存 UI 统一调色板（ThemeColors）
│   ├── terrain_renderer.gd    # 地形/网格/云层绘制（沙盒+生存共享）
│   ├── camera_controller.gd   # 缩放/平移/hover/坐标转换（沙盒+生存共享）
│   ├── aircraft_renderer.gd   # 飞机绘制系统（从 aircraft.gd 提取的 18 个 _draw_*）
│   ├── aircraft_destruction.gd # 坠毁动画（fighter/bomber/heli 三种风格）
│   ├── pilot_personality.gd   # 飞行员心理（压力/SA/判断误差）
│   └── survivor/
│       ├── survivor_mode.gd       # 生存模式主控制器（场景/操控/升级/HUD）
│       ├── survivor_spawner.gd    # 刷怪系统（Token/生成/击杀/清理/猎手）
│       ├── survivor_player.gd     # 经验/等级/升级应用
│       ├── survivor_data.gd       # 升级定义 + 波次参数 + 经验曲线（静态）
│       ├── survivor_hud.gd        # HUD（HP/经验/战术按钮）
│       ├── survivor_upgrade_ui.gd # 升级选择界面
│       ├── survivor_map_select.gd # 地图选择（生存流程第一步）
│       ├── survivor_select.gd     # 机型选择（PlayableAircraft 卡片，4 槽）
│       ├── survivor_playable_setup.gd # PlayableAircraft → Aircraft 实例的应用器
│       ├── survivor_debug_skills.gd # 调试技能面板
│       ├── commander_aura.gd      # Sentinel 指挥 UAV 光环 buff + 招募
│       └── commander_overlay.gd   # 指挥机可视化覆盖层
├── resources/                 # .tres 参数资源（飞机/武器/导弹/战斗风格）
├── docs/                      # 设计文档 + 代码索引 + 更新日志
└── export_presets.cfg         # Godot 导出配置
```

## Architecture

### AutoLoads（初始化顺序）

`project.godot [autoload]`:
1. **CallsignDB** — 呼号分配器（每架飞机 `_ready()` 时调用 `CallsignDB.allocate()`）
2. **EventLogger** — 全局事件环形缓冲区（60 秒窗口，F9 导出）

### 类继承体系

```
Node2D
├── CombatUnit                 # 战斗单位基类（team/hp/altitude/雷达/锁定共享接口）
│   ├── Aircraft               # 飞机实体（物理+战斗+武器）
│   └── GroundUnit             # 地面单位基类
│       ├── SAMUnit            # 防空导弹车
│       ├── AAGunUnit          # 高射炮
│       └── RadarStation       # 雷达站
├── Missile                    # 导弹实体
├── BulletManager / MissileManager  # 弹药管理器
└── TrailRibbon                # 烟迹渲染

Node
└── AIController               # 附加到 Aircraft 的 AI 状态机

RefCounted
├── Squad                      # 编队数据 + 阵型计算
└── SurvivorData               # 生存模式静态数据

Resource
├── AircraftParams / GunParams / RocketParams / MissileParams / CombatParams / FlareParams
```

### AI 原型（Archetype）预设

参照经典空战文献的敌方行为分类，通过 `CombatParams` + `AIController` 参数组合实现：

| 原型 | 行为特征 | 预设文件 | 适用机型 |
|------|---------|----------|----------|
| **Gladiator（斗士）** | 积极近身狗斗，拉近距离，高转弯激进度，低自保 | `gladiator_combat.tres` | F-86, MiG-23 |
| **Lancer（骑士/打带跑）** | 高速一次性突击，闭合率不足即脱离，不缠斗 | `lancer_combat.tres` | J-7（轻量）, F-100（中量编队）, MiG-31（顶级单机） |
| **Schemer（策士）** | 特殊机制（光环 buff/远距狙击/隐身），玩家靠近即脱离 | — | Sentinel 指挥 UAV |
| **Adds（杂兵）** | 无反击能力，直线飞过战场，纯经验奖励；族群波次（非编队） | — | Tu-160（战略轰炸机）。UAV/UCAV 虽然 Token 很便宜但仍会反击 + 受刷怪系统管理，设计上**不归类为 Adds** |
| **主力威胁** | 全能 BFM 战术 + 导弹缠斗 | `default_combat.tres` | MiG-29 |

⚠ 这些原型名称是**纯内部设计词汇**，不要写进玩家可见 UI / debug 面板 / `display_name`。仅可出现在源码注释、`.tres` 注释、设计文档里。

### 敌人索引（Enemy Index）

所有生存模式敌人的完整索引。**新增敌人必须在此表新增一行**，以便下次直接走索引而不通读代码。

`EnemyType` enum 在 `survivor_mode.gd:843`。每个敌人由 7 个位置共同定义：

| EnemyType(int) | 显示名 | Archetype | `.tres` 参数 | Token | 实例上限 | 解锁等级 | 生成形式 | `_create_enemy` match 行 | AI 配置行 |
|---|---|---|---|---|---|---|---|---|---|
| `UAV(0)` | UAV | Adds | `enemy_uav.tres` | 1 | ∞ | 1 | 编队(后期) | `:1059` | `:1240`(default) |
| `UCAV(1)` | UCAV | Adds | `enemy_uav_missile.tres` | 2 | ∞ | 1 | 编队(后期) | `:1046` | `:1240`(default) |
| `MIG(2)` | MiG-29 | 主力威胁 | `enemy_fighter.tres` | 4 | ∞ | 7 | 编队 | `:1042` | `:1158` |
| `INTERCEPTOR(3)` | J-7 | Lancer 入门 | `enemy_interceptor.tres` | 5 | ∞ | 5 | 单机→后期编队 | `:1044` | `:1167` |
| `UAV_COMMANDER(4)` | Sentinel | Schemer | `enemy_uav_commander.tres` | 6 | **1** | 4 | 自带 2-3 僚机 | `:1048` | `:1233` |
| `F86(5)` | F-86 | Gladiator 入门 | `enemy_f86.tres` + `f86_gun.tres` + `rocket_ffar.tres` | 3 | ∞ | 2 | 编队 | `:1050` | `:1183` |
| `MIG31(6)` | MiG-31 | Lancer 顶级 | `enemy_mig31.tres` | 8 | **2** | 9 | 单机 | `:1052` | `:1195` |
| `MIG23(7)` | MiG-23 | Gladiator 综合 | `enemy_mig23.tres` | 4 | ∞ | 4 | 编队 | `:1054` | `:1208` |
| `F100(8)` | F-100 | Lancer 编队 | `enemy_f100.tres` | 5 | **3** | 6 | 编队 | `:1056` | `:1220` |
| `SU27(9)` | Su-27 | Gladiator+眼镜蛇 | `enemy_su27.tres` | 7 | **2** | 8 | 单机 | `:1263` | `:1443` |
| `A7(10)` | A-7 | Lancer 亚音速攻击 | `enemy_a7.tres` + `a7_gun.tres` + `a7_rocket.tres` | 3 | ∞ | 3 | 编队 | `:1294` | `:1525` |
| `Q5(11)` | Q-5 | Lancer 超音速攻击 | `enemy_q5.tres` + `q5_gun.tres` + `q5_rocket.tres` | 4 | ∞ | 5 | 编队 | `:1296` | `:1538` |
| `TU160(12)` | Tu-160 "白天鹅" | **Adds 杂兵** | `enemy_tu160.tres`（无武器） | **0** | ∞ | 事件触发 | **族群 Flock**（横列 4 架） | `_create_enemy` Tu160 case | AI 简化(simple_ai) |
| `AH64(13)` | AH-64 Apache | **Adds 直升机（对地）** | `enemy_ah64.tres` + `ah64_gun.tres`（M230 30mm）+ `ah64_rocket.tres`（Hydra 70）+ 1 枚热诱弹 | **0** | ∞ | 事件触发 | **菱形 Flock** 4 架（队长前 + 左右两翼 + 殿后） | `_create_enemy` AH64 case | simple_ai + `ground_combat_only=true` + `attack_air_targets=false` |
| `CH47(14)` | CH-47 Chinook | **Adds 运输直升机** | `enemy_ch47.tres`（1 枚热诱弹，50% 失误概率） | **0** | ∞ | 事件触发 | **纵阵 Flock** 3 架 | `_create_enemy` CH47 case | AI 简化(simple_ai, 与 Tu-160 同) |
| `F47(15)` | F-47 | **BOSS 王牌狙击小队** | `enemy_f47.tres` + `f47_missile.tres`（AIM-260）+ `f47_flare.tres`（40 枚电子战）+ `ace_combat.tres` | **10** | **4** | 事件触发 | **菱形编队** 4 架（队长+两翼+殿后）| `_create_enemy` F47 case + `_spawn_f47_squad` | BVR 狙击模式(bvr_only) + 协同齐射(salvo_leader) |

**Adds 杂兵分类细节**（目前有 Tu-160 横列波次 + AH-64/CH-47 纵阵波次 + SAM/AA 地面单位五种）：
- **无反击、无规避、无雷达**：`enable_combat = false` + `radar_range = 0` + `simple_ai`
- **独立刷新系统**：`_update_tu160_flock`（survivor_mode.gd）自己的 timer，不走 `_update_spawner`
- **不占 Token**（`TOKEN_COST[12]=0`），实例计入 `_count_enemies()` 但不消耗预算
- **不被远距清理**（`skip_far_cleanup` meta → `_update_far_cleanup` 跳过）
- **族群 Flock 而非编队**：4 架直线横向交错排开，各自独立飞向终点，**不使用 `Squad` 类**
- **一击致命**：HP 60，被 `ENEMY_HP_MISSILE_CAP=75` 保证任何导弹都能一发命中
- **特殊坠落动画**：`crash_style="bomber"` meta → `_update_destroy` 走侧翻慢坠分支（5 秒，持续 `bank_angle` 累加模拟侧翻）
- **轰炸机外观**：`silhouette="bomber"` meta → `_draw_bomber_icon()` 大翼展 + 长机身
- **XP 奖励**：Adds 类（Tu-160/AH-64/CH-47）走 `SurvivorData.adds_xp_per_kill(level)`，每 kill = `ceil(xp_for_level(level) / 3)`（即当前等级所需经验的 1/3）。整组（≥3 只）击杀保证升 1 级；若玩家快满级时打一只也可能触发升级，体验更自然
- **完全被动**：不转弯（单点 waypoint 直线飞）、不规避、**被击中无任何反应**（与 UAV 等普通敌机区别开 — adds 是纯靶子）
- **跳过 3 个全局敌机系统**（`category=="adds"` meta 检测）：
  - `_update_hunters` — 不会被指派为玩家追击者
  - `_update_enemy_waypoints` — 每 8s 的"绕玩家圆周航点"不会覆盖其固定航线
  - `_update_far_cleanup` — `skip_far_cleanup` meta 使之不受距离清理
  - 新增 adds 类敌人必须同步排除这些系统，否则会被强制改向追玩家
- **生命期上限**：`despawn_after` meta 标记 120~150 秒后静默消失（防止 skip_far_cleanup 下无限堆积）
- **不走随机刷新**：Adds 类敌人**永不**由 `_update_spawner` / 任何 timer 自动出现 —— 由未来的事件系统（紧急事件 / 大地图 A→B 任务）手动调用 `_spawn_tu160_flock()` / `_spawn_ah64_flock()` / `_spawn_ch47_flock()` 触发。Debug 面板也能手动触发用于测试。
- **新增 Adds 步骤**：创建 tres → 加 EnemyType 枚举 → `survivor_data.gd` 加 `TOKEN_COST/INSTANCE_CAP/XP/FLOCK_SIZE/FLIGHT_DISTANCE/spacing 等几何参数`（不要加 UNLOCK_LEVEL/WAVE_INTERVAL）→ `_create_enemy` 加 base_params/type_tag/AI 分支 → 新增 `_spawn_xxx_flock()` 函数 → `_configure_adds_unit()` 已自动设置 despawn_after 清理 meta → Debug 面板加条目供手动测试
- **直升机专属细节**（AH-64/CH-47）：
  - `silhouette="apache"` / `silhouette="chinook"` → `aircraft.gd` 里 `_draw_apache_icon` / `_draw_chinook_icon` 画出旋翼盘 + 旋转叶片
  - `crash_style="heli"` → 坠落时尾桨失效自旋（大 yaw 旋转 + 中速下坠）
  - **高度层**：AH-64/CH-47 固定 `AltitudeTier.LOW`（低空突防），Tu-160 固定 `AltitudeTier.HIGH`（战略轰炸）。`_spawn_*_flock` 直接指定单一 tier，不随机
  - **1 枚热诱弹 + fail_chance**：Aircraft 的 `_update_flares` 里已有现成逻辑（FlareParams.fail_chance）—— 来袭导弹近到 release 距离时 roll 概率，命中失误则这枚导弹永远不会再触发 flare。恰好匹配"只用一次 + 概率触发"的设计。`enable_flare_reload=false`（默认）保证 1 枚用完就没了。
  - **AH-64 对地武器 + 空中免疫**：挂 M230 30mm 机炮 + Hydra 70 火箭弹。**两处独立防火**：①`AIController.ground_combat_only=true` 保证 `_try_engage_simple` 只选 `GroundUnit` 作为 `_current_target`。②`Aircraft.attack_air_targets=false` 保证 `_auto_gun_scan` 在 `combat_target` 为空时也不会自动扫射路过的空中敌人（否则 Apache 会对穿过机头的玩家开火）。遇到地面敌方时走 `_update_combat_ground_attack` strafing 状态机。
  - **AH-64 受击散队（jink 机动）**：`scatter_on_damage` meta + `Aircraft.flock_members` 共享引用。任一队员 `_apply_damage` 触发 `_trigger_flock_scatter()` 给所有队友设 `flock_scatter_timer = FLOCK_SCATTER_DURATION (3.5s)` + 随机侧向单位向量。AIController waypoint 分支用时间曲线复合偏移：`sin(progress×π)` 包络 × `sin(progress×τ×1.2)` weave × 侧向 650px ＋ 机头方向 × 200px 前冲 —— 形成明显的 S 型 jink 而非原地压杆。scatter 期间自动清空 `_current_target` 中断地面交战。
  - **AH-64 菱形编队**：4 架偏移在 `_spawn_ah64_flock` 写死：[0] 队长 (0, 0)、[1/2] 两翼 (-fwd, ±lat)、[3] 殿后 (-2×fwd, 0)，全部沿 `flight_dir`/`lateral_axis` 变换到世界坐标。

**F-47 BOSS 王牌狙击小队**（BVR 远距协同齐射 BOSS，事件触发）：
- **核心战术循环**（`F47Tactic` 状态机）：INTRO → ORBIT（环形站位 8-12s）→ ATTACK_RUN（冲向玩家齐射）→ SCATTER（散开到不同方位）→ REGROUP → ORBIT...
- **赫尔贝特轮**（`herbst_maneuver.gd`）：被玩家近距追逐时触发 180° J-Turn 急转反杀。BOSS 专属可重复使用（15s 冷却），由 `ai_controller.gd` bvr_only 分支自动触发
- **协同齐射**：`salvo_leader` 队长发射后广播齐射信号给僚机，0.1-0.4s 内 4 枚导弹齐射
- **光学隐形**：每 60 秒激活 5.5 秒全队隐形（`is_cloaked`）。效果：淡出消失 + 雷达锁定清除 + 导弹丢失制导 + 无法选中。`_update_f47_cloak()` 管理，全队共享计时器
- **热诱弹豁免**：不受敌机 1 枚限制（BOSS 特权），使用完整 f47_flare.tres（40 枚，burst 3）
- **不走随机刷新**：不在 `_pick_enemy_type` 中，不被 `_update_spawner` 管理；由 `_spawn_f47_squad()` 专用函数触发（Debug 面板 / 未来事件系统）
- **独立航点**：`category="boss"` meta 使之跳过 `_update_hunters` 和 `_update_enemy_waypoints`
- **不受远距清理**：`skip_far_cleanup` meta

**所有 Token / 上限 / 解锁常量** 都在 `survivor_data.gd` 里集中定义：
- `TOKEN_COST`（`:338`）/ `TOKEN_INSTANCE_CAP`（`:356`）/ `TOKEN_BUDGET_BASE/PER_LEVEL/MAX`（`:331`）
- `FAR_CLEANUP_DISTANCE`（`:372`）/ `FAR_CLEANUP_INTERVAL`（`:373`）/ `LATE_GAME_LEVEL`（`:379`）
- `LATE_GAME_MIN_TOKEN`（`:383`）/ `ENEMY_HP_MISSILE_CAP`（`:386`）
- 每个敌人的 `*_UNLOCK_LEVEL` / `*_CHANCE_PER_LEVEL` / `*_CHANCE_MAX`（`:288-314`）

### 创建新敌人的完整清单（"加一个敌人"触发短语）

**为避免通读数千行代码**，以下列出新增一个敌人必须同步修改的所有位置。按顺序操作：

1. **创建 `.tres` 参数资源**（`resources/` 下）：
   - `enemy_<name>.tres` (AircraftParams)
   - 必要时同建对应的 `<name>_gun.tres` / `<name>_missile.tres` / `<name>_rocket.tres`
   - 可复用 `gladiator_combat.tres` / `lancer_combat.tres` / `default_combat.tres` 作为 `combat` 字段
2. **在 `survivor_mode.gd:843` 的 `EnemyType` 枚举追加新值**（末尾，保持已有值不动）
3. **在 `survivor_mode.gd:43-51` 声明 `_<name>_params_base: AircraftParams` 成员**
4. **在 `survivor_mode.gd:104-112` 的 `_ready` 中 `preload(...)` 加载资源**
5. **在 `survivor_data.gd:220-244` 加解锁/概率常量**（`<NAME>_UNLOCK_LEVEL` / `_CHANCE_PER_LEVEL` / `_CHANCE_MAX`）
6. **在 `survivor_data.gd:TOKEN_COST`（`:261`）和 `TOKEN_INSTANCE_CAP`（`:276`）表里补新枚举值**
7. **在 `survivor_mode.gd:874 _pick_enemy_type` 按威胁等级插入新类型的概率判定分支**
8. **在 `survivor_mode.gd:1038 _create_enemy` 的 5 个 match 全部补新 case**：
   - `match etype` 选基础参数（`:1042`）
   - `enemy_scale_for_level` 适用判定（`:1076`）
   - `no_stamina` 排除判定（`:1103`）
   - `type_tag` 映射（`:1109`）
   - AI 配置分支（`:1157` 起 — 仿照 F-86/MiG-23 写 `aggression`/`engage_cooldown` 等）
9. **在 `survivor_mode.gd:722 _update_spawner` 的 "载人战机编队列表" 判定里追加**（`:808-812`）
10. **更新 `survivor_debug_spawn.gd:_build_ui` 的类型下拉列表**（让调试面板能手动刷这个敌人）
11. **更新本文件（CLAUDE.md）"敌人索引" 表追加一行**
12. **更新 `docs/reference/code-index.md` 对应段落**（如新文件/新函数）

操作时用 Read 的 offset/limit 精确定位，不要通读整个 survivor_mode.gd（1450 行）。每一步改完就 commit 或至少 git diff 看一眼，防止漏 case 导致 NullRef 崩溃。

### 关键文件职责（Script Index）

**模式归属图例**：`[共享]` = 沙盒/生存都使用，改动必须两个模式都测；`[沙盒]` = 只在沙盒模式；`[生存]` = 只在生存模式。**禁止**在共享层代码里写 `if in_survivor_mode` / `if in_sandbox`，模式隔离必须走参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入。详见 [docs/planning/roadmap.md](docs/planning/roadmap.md) 第 0 段。

| 文件 | 类/类型 | 职责 | 关键入口 |
|------|---------|------|----------|
| `aircraft.gd` | `Aircraft extends CombatUnit` | [共享] 飞机物理+战斗+武器（~3091 行，绘制委托 aircraft_renderer.gd，坠毁委托 aircraft_destruction.gd） | `_physics_process` `_update_combat` `_update_gun` `_update_rocket` `_update_weapon_mode` `_update_missile` `_effective_missile_range_px` `_missile_cannot_hit_but_gun_can` `_should_commit_gun_pass` `_is_gun_pass_finished` `_release_flares(target_missile)` `set_evasion_mode` `_corner_speed_kmh` `get_maneuver` `_draw()` |
| `aircraft_renderer.gd` | `AircraftRenderer extends RefCounted` | [共享] 飞机绘制系统（~865 行，18 个静态 `draw_*` 方法） | `draw_radar_cone` `draw_gun_cone` `draw_lock_indicator` `draw_muzzle_flash` `draw_afterburner_glow` `draw_flare_particles` `draw_aircraft_icon` `draw_commander_icon` `draw_bomber_icon` `draw_apache_icon` `draw_chinook_icon` `draw_data_label` `draw_tactic_popup` `draw_target_line` `draw_predicted_path` `draw_formation_debug` |
| `aircraft_destruction.gd` | `AircraftDestruction extends RefCounted` | [共享] 坠毁动画系统（fighter/bomber/heli 三种风格） | `start(ac)` `update(ac, delta)` |
| `cobra_maneuver.gd` | `CobraManeuver extends Node` | [共享] 眼镜蛇机动模块（挂载到 Aircraft 子节点） | `activate` `_physics_process`（三阶段状态机） |
| `herbst_maneuver.gd` | `HerbstManeuver extends Node` | [生存] 赫尔贝特轮 J-Turn 模块（F-47 BOSS 专属，可重复使用） | `activate` `_physics_process`（DECEL→TURN→ACCEL） |
| `survivor/ace_squad.gd` | `AceSquad extends RefCounted` | [生存] 王牌中队 BOSS 基类（通用飞机类 BOSS 框架） | `spawn` `update` `_assign_roles` `_apply_role` `_maintain_role` `_update_cloak` `_force_engage` |
| `survivor/f47_ace_squad.gd` | `F47AceSquad extends AceSquad` | [生存] F-47 王牌小队具体实现（隐形+J-Turn+齐射+二二组合战术） | `_configure_spawn` `_configure_close_fighter_combat` `_configure_ranged_striker_combat` |
| `rocket_params.gd` | `RocketParams extends Resource` | [共享] 无制导火箭弹参数（齐射数/散布/冷却） | — |
| `ai_controller.gd` | `AIController extends Node` | [共享] AI 状态机 + BFM 战术决策树 + 导弹拦截（~2269 行，心理子系统委托 pilot_personality.gd） | `_process_patrol` `_process_squad_follow` `_process_engage` `_choose_tactic` `_process_evade` `_find_leader_threat` `_compute_intercept_pos` `_find_member_ai` |
| `pilot_personality.gd` | `PilotPersonality extends RefCounted` | [共享] 飞行员心理子系统：压力/态势感知/判断误差（~223 行） | `update_stress(ai, delta)` `update_situational_awareness(ai, delta)` `update_drift(ai, delta)` `effective_skill` `effective_sa` `apply_position_error` `apply_speed_error` `apply_altitude_error` |
| `combat_unit.gd` | `CombatUnit extends Node2D` | [共享] 战斗单位基类（通用接口） | `take_damage:81` `is_in_radar_cone:94` `get_altitude_tier:65` |
| `missile.gd` | `Missile extends Node2D` | [共享] 导弹飞行物理（PN 制导/SARH） | `_physics_process:37` `_guidance_degradation:238` |
| `missile_manager.gd` | `MissileManager extends Node2D` | [共享] 导弹生成+命中+连锁弹头+近炸引信AOE | `spawn_missile:20` `_physics_process:56` `_spawn_aoe:109` `_update_aoe_zones:126` `_draw:157` `_find_bounce_target:166` |
| `bullet_manager.gd` | `BulletManager extends Node2D` | [共享] 子弹/火箭物理+命中+伤害衰减（162 行） | `spawn_bullet:23` `spawn_rocket:38` `_physics_process` |
| `terrain_renderer.gd` | `TerrainRenderer extends Node2D` | [共享] 地形/网格/云层绘制（子节点，自动 `_draw`） | `setup(camera)` `_draw_terrain` `_draw_grid` `_get_terrain_type` |
| `weather_system.gd` | `WeatherSystem extends Node2D` | [共享] 全局天气：高空云层（随机风向 + 噪声密度场 + 漂移 + 半透明绘制）。加入 group `"weather"` 供战斗代码查询 | `setup(camera)` `sample_density(world_pos)` `is_in_cloud(world_pos)` `_draw` |
| `camera_controller.gd` | `CameraController extends Node` | [共享] 缩放/平移/hover/坐标转换 | `setup(camera)` `update_zoom(delta)` `handle_zoom_input(factor)` `screen_to_world(screen_pos)` `handle_drag(relative)` `update_hover(screen_pos, units)` |
| `main.gd` | `Main extends Node2D` | [沙盒] 沙盒主控：输入/雷达锁定/编队/LOD（地形/相机委托共享模块，~427 行） | `_update_radar_locks` `_spawn_friendly_squad` `_update_lod` |
| `squad.gd` | `Squad extends RefCounted` | [共享] 6 种阵型偏移计算 | `get_formation_offset:51` `get_wingman_target:114` `cycle_formation:128` |
| `ground_unit.gd` | `GroundUnit extends CombatUnit` | [共享] 地面单位基类（机炮+雷达+移动） | `_update_movement:63` `_update_combat:131` `_update_gun:164` |
| `sam_unit.gd` | `SAMUnit extends GroundUnit` | [共享] SAM：360° 雷达 + HQ-7 导弹 | `_update_sam_missile:26` `is_in_radar_cone:54`（覆写圆形） |
| `aa_gun_unit.gd` | `AAGunUnit extends GroundUnit` | [共享] AAA：独立炮塔 + ZU-23 | `_update_turret:69` `_update_aa_target_selection:30` |
| `radar_station.gd` | `RadarStation extends GroundUnit` | [共享] 雷达站：20km 雷达 + 数据链共享 | `_update_datalink:35` `_update_dish:29` |
| `survivor/survivor_mode.gd` | 生存模式主控（~797 行） | [生存] 场景初始化/操控/雷达/升级/HUD（地形+相机委托共享模块，刷怪委托 spawner） | `_physics_process` `_update_radar_locks` `_on_player_leveled_up` `_spawn_starting_wingmen` |
| `survivor/survivor_spawner.gd` | `SurvivorSpawner extends Node` | [生存] 刷怪系统：Token 预算/敌人生成/击杀检测/远距清理/猎手指派/航点刷新（~1340 行） | `update` `_update_spawner` `_pick_enemy_type` `_create_enemy` `_spawn_single` `_spawn_squad` `_spawn_commander_squad` `_detect_kills` `_update_far_cleanup` `_update_hunters` `_update_enemy_waypoints` `_spawn_tu160_flock` `_spawn_ah64_flock` `_spawn_ch47_flock` `_spawn_f47_squad` — **EnemyType enum** |
| `survivor/survivor_debug_spawn.gd` | `SurvivorDebugSpawn extends CanvasLayer` | [生存] F5 刷怪调试面板（279 行） | `_build_ui:60` `_on_type_changed:226` `_on_spawn_pressed:236` `_on_clear_pressed:264` `_on_dump_pressed:276` |
| `survivor/survivor_player.gd` | `SurvivorPlayer extends Node` | [生存] 经验/等级/升级应用 | `add_xp:20` `apply_upgrade:30` |
| `survivor/survivor_data.gd` | `SurvivorData extends RefCounted` | [生存] 升级表/波次常量/Token 预算/经验曲线 | `UPGRADES:12`（含 `requires`/`exclusive_to` 字段说明） `is_upgrade_available_for(upgrade, aircraft_id, params)` `TOKEN_COST` `TOKEN_INSTANCE_CAP` `TOKEN_BUDGET_*` `FAR_CLEANUP_DISTANCE` `LATE_GAME_LEVEL` `LATE_GAME_MIN_TOKEN` `ENEMY_HP_MISSILE_CAP` `xp_for_level` `enemy_scale_for_level` |
| `survivor/commander_aura.gd` | `CommanderAura extends Node` | [生存] Sentinel 光环 buff + 招募 UAV | `_apply_buff:93` `_try_recruit:155` |
| `playable_aircraft.gd` | `PlayableAircraft extends Resource` | [生存] 主角档案：UI 元数据 + base_params 引用 + 生存模式调味（属性/武器/战斗/热诱弹覆盖）+ 起始僚机配置 | 全部 `@export` 字段；详见 docs/reference/playable-aircraft-workflow.md |
| `survivor/survivor_playable_setup.gd` | `SurvivorPlayableSetup extends RefCounted` | [生存] 把 PlayableAircraft 应用到 Aircraft 实例（替代旧的 survivor_mode 内联 buff 块） | `apply(aircraft, profile)` `deep_dup_weapons(params)` |
| `survivor/survivor_select.gd` | 生存模式机型选择界面 | [生存] 4 槽 PlayableAircraft 卡片（F-16/F-14 解锁 + 2 占位） | `PLAYABLE_LIST:21` `_build_aircraft_card:157` `_on_aircraft_selected` |
| `survivor/survivor_map_select.gd` | 生存模式地图选择界面 | [生存] 5 槽地图卡片（1 解锁 + 4 占位）；ESC→主菜单 | `MAP_LIST:18` `_build_map_card` `_on_map_selected` |
| `debug_panel.gd` | 调试面板 | [沙盒] 状态文本/飞行员信息/生成按钮 | `_get_strategy_text:266` `_get_combat_strategy:303` `_get_pilot_info:318` |
| `event_logger.gd` | EventLogger (AutoLoad) | [共享] 全局事件环形日志 | `log_event:22` `dump_to_file:31` |
| `callsign_db.gd` | CallsignDB (AutoLoad) | [共享] 呼号分配+回收 | `allocate` / `release` |
| `locale_manager.gd` | LocaleManager (AutoLoad) | [共享] i18n 控制：启动读 user://locale.cfg（zh/en/ja），主菜单按钮切换+持久化+重载场景 | `_ready` `set_locale_persistent(code)` `get_current_locale()` `trm(key)` — 详见 [docs/reference/i18n.md](docs/reference/i18n.md) |

### 核心设计决策

- **不使用 Godot 物理引擎**：飞机运动全部在 `_physics_process` 手动演算，完全可控
- **2D 场景 + 虚拟高度**：`altitude` 是纯 float 变量，仅通过图标缩放可视化
- **单位系统**：内部 SI 单位（米、m/s），显示 km/h。`PIXELS_PER_METER = 0.5`（1 像素 = 2 米）
- **输入模型**：玩家点击 → `target_position` → 飞机自主 G 力极限转弯
- **飞机通用模板**：`aircraft.tscn` + `AircraftParams` Resource，通过不同 `.tres` 定义机型
- **AI 组合模式**：`AIController` 作为子节点附加到飞机，飞机本身不区分玩家/AI，只是目标来源不同

### 关键常量与坐标系

- `PIXELS_PER_METER = 0.5`（`combat_unit.gd:9`）
- `GRAVITY = 9.81`（`combat_unit.gd:8`）
- `heading`: 弧度，0=北（屏幕上方），顺时针
- 世界坐标：Y 向下为正，绘制时通过 `rotation = heading` 让图标头朝 heading 方向
- 高度档位：`AltitudeTier { GROUND=-1, LOW=0(<3500m), MID=1(<7500m), HIGH=2(>=7500m) }`

### Aircraft 物理演算流程（每帧）

`aircraft.gd:_physics_process:154` → 按 LOD 分三档：

- **LOD 0（完整）**：玩家 + 交战中飞机。全部 18 步（武器模式/战斗/能量管理/航向/bank/速度/高度/燃油/失速/G 力/位移/机炮/导弹/热诱弹/视觉）
- **LOD 1（简化）**：编队僚机巡航。大部分步骤每 3 帧运行一次，编队托管有专用三段式航向控制（见下）
- **LOD 2（屏幕外）**：离屏飞机，每 3 帧完整更新一次，其余帧仅位移

### 编队托管三段式（aircraft.gd LOD 1 分支）

| 距槽位距离 | 行为 |
|-----------|------|
| `>800px` 或过渡初期 | 纯追击归队（航向直指槽位 + 激进 bank） |
| `50~800px` | 航向混合长机与槽位 + 自然 bank 转弯（走真实物理） |
| `<50px` | 航向同步长机 + 极弱漂移修正（0.15×speed） |

这样消除了僚机振荡和平移感。阵型变换有 0.3~1.3 秒个体化反应延迟。

### AI 状态机

`ai_controller.gd` 四状态 + 8 战术机动：

- **PATROL** — 航路点巡逻，周期性扫描
- **ENGAGE** — BFM 决策树选择战术机动
  - LEAD_PURSUIT / LAG_PURSUIT / LEAD_TURN / HIGH_YOYO / LOW_YOYO / BREAK_TURN / EXTENSION / SCISSORS
- **EVADE_MISSILE** — 释放热诱弹 + 急转
- **SQUAD_FOLLOW** — 编队跟随 + 掩护扫描（每 0.5s 扫长机后半球）
  - 子状态：`_rejoining`（归队）/ `_formation_react_timer`（阵型调整）/ `_squad_attacking_leader_target`（协同攻击）

### 战斗追踪与武器模式

飞机内置战斗 AI（`aircraft.gd:_update_combat:930`）处理机炮/导弹的三阶段追踪：接近 → 照射 → 保持。
武器模式切换有滞后防震荡：
- 无导弹 → GUN
- Crank 阶段强制 MISSILE
- GUN 模式需距离 > 机炮射程×2 才切回 MISSILE
- MISSILE 模式需距离 < 机炮射程×0.8 才切 GUN

### 雷达锁定计算（main.gd:_update_radar_locks:226）

全局循环每帧：
1. 遍历所有 CombatUnit，重置 `is_locked`
2. 对每单位，检查其雷达锥内的敌方单位
3. 在锥内 → 按 `_lock_rate_for_tier` 速率累加照射时间（地面 ×0.5, 低空 ×0.7）
4. 不在锥内 → 1.5 秒衰减窗口（防边缘震荡）
5. 累计 ≥ `params.lock_time` → 锁定

## ⚠ 性能守则（强制）

**任何**新增 `_process` / `_physics_process` / `_draw` / `queue_redraw` / 挂在 Aircraft/Missile 下的子节点，都必须先读 [docs/reference/performance-guidelines.md](docs/reference/performance-guidelines.md)。

7 条硬规则速记：
1. 静态内容禁止每帧 `queue_redraw`（地图/边界都吃过亏）
2. `_draw` 里不得有全场扫描（用 `AircraftRenderer.player_ref` / `CombatUnit.all_units`）
3. 多次 `draw_polygon` / `draw_line` 要合并（用 `RenderingServer.canvas_item_add_triangle_array`）
4. `_process` / `_physics_process` 禁用 `get_parent().get_children()`
5. AI 决策默认从 20Hz 甚至 10Hz 起步（`ai_tick_divisor ≥ 3`）
6. 挂到 Aircraft/Missile 子节点要先乘实体数（22 架 × 60Hz）
7. 新功能必须跑生存模式 Sentinel + Lv5+ 压力测试，FPS 掉 >15 就回滚

历史翻车清单（尾迹 40 万 draw_polygon/秒、地图每帧重算、数据标签 O(N²) 扫描等）见守则末尾"历史教训"段。同类问题出现过就不该再出现。

## 工作约定

### 查找代码的顺序

1. **先看本文件的 Script Index 表** — 找到目标文件和关键行号
2. **用 Read 的 `offset`/`limit` 只读需要的行段**（通常 50~100 行）
3. **不要通读整个 .gd 文件**（`aircraft.gd` 2500 行，`ai_controller.gd` 1500 行）
4. **不要对已索引的功能用 Grep/Glob 全文搜索**

只有这些情况才用 Grep：
- 查找 Script Index 里没覆盖的新功能
- 验证符号是否仍然存在（索引可能过时）
- 跨文件的引用关系

更细粒度的索引（按功能主题而非按文件）见 `docs/reference/code-index.md`。

### 索引维护

修改代码时必须同步：
- **新增/删除函数** → 更新 CLAUDE.md 的 Script Index 表 + `docs/reference/code-index.md`
- **大幅移位**（> 50 行）→ 更新受影响的行号
- **重大重构** → 重新扫描对应文件生成新索引
- **commit 前** 检查索引与代码一致性

### 触发短语

- `"用 index"` / `"走索引"` — 严格按 Script Index → Read offset 流程，不读全文件
- `"更新 index"` — 重新扫描代码更新 CLAUDE.md + code-index.md

### 代码规范

- **语言**：GDScript，注释与文档用中文
- **命名**：snake_case 方法/变量，PascalCase 类名和场景
- **类型**：尽量使用类型提示（`var x: float`），避免 Variant
- **信号**：通过 signal 解耦，不用全局变量共享状态
- **Resource 复用**：`.tres` 文件通过 `preload()` 加载，生成子节点时用 `duplicate(true)` 避免共享修改
- **CombatUnit 基类**：所有战斗单位（包括地面）共用 `team/hp/altitude/radar_targets/is_locked`，扩展时覆写 `is_in_radar_cone` / `take_damage` / `is_lock_immune`
- **i18n 约束**：玩家可见的 UI / 升级 / 机型 / 地图 / 弹窗文本**一律走 `tr("KEY")`**，在 `i18n/translations.csv` 定义 key。新增 UI 文本流程见 [docs/reference/i18n.md](docs/reference/i18n.md)。例外：`AircraftParams.display_name`（HUD/日志拼接用）保留原值、EventLogger、debug 面板。
- **不要修改 CLAUDE.md 的 Script Index 之外的段落** 除非是架构级变更

## 相关文档

按需加载，不是每次都读。`docs/` 已按职能分目录：

**入口 / 概述**（docs 根级）
- [docs/project-overview.md](docs/project-overview.md) — 项目概述
- [docs/architecture.md](docs/architecture.md) — 物理公式与架构决策

**规划**（docs/planning/）
- [docs/planning/roadmap-overview.md](docs/planning/roadmap-overview.md) — 规划概览（阶段 / 玩家视角，用于排期决策）
- [docs/planning/roadmap.md](docs/planning/roadmap.md) — 技术向 roadmap（模式边界 / 反馈修复 / 带文件路径）

**子系统设计**（docs/systems/）
- [docs/systems/ai-system.md](docs/systems/ai-system.md) — AI 状态机/战术/压力系统详解
- [docs/systems/survivor-mode.md](docs/systems/survivor-mode.md) — 生存模式波次/升级表
- [docs/systems/ground-units.md](docs/systems/ground-units.md) — 地面单位设计
- [docs/systems/missile-system.md](docs/systems/missile-system.md) — 导弹系统
- [docs/systems/radar-system.md](docs/systems/radar-system.md) — 雷达系统
- [docs/systems/squad-tactics-design.md](docs/systems/squad-tactics-design.md) — 编队战术设计
- [docs/systems/aircraft-params.md](docs/systems/aircraft-params.md) — 飞机参数字段说明

**查询手册**（docs/reference/）
- [docs/reference/code-index.md](docs/reference/code-index.md) — 功能主题索引（武器/物理/AI/视觉等分类）
- [docs/reference/scripts-reference.md](docs/reference/scripts-reference.md) — 脚本 API 参考（所有变量/方法说明）
- [docs/reference/resources-catalog.md](docs/reference/resources-catalog.md) — 所有 .tres 参数总表
- [docs/reference/playable-aircraft-workflow.md](docs/reference/playable-aircraft-workflow.md) — 加新主角飞机的完整流程
- [docs/reference/i18n.md](docs/reference/i18n.md) — 本地化 / 翻译 key 约定 + 新增 UI 文本流程
- [docs/reference/features.md](docs/reference/features.md) — 已实现功能清单

**历史 / 变更日志**（docs/changelogs/，按日期命名）
- [docs/changelogs/2026-04-11.md](docs/changelogs/2026-04-11.md) — 最近一次更新
- 更早的在 `docs/changelogs/` 下，按日期排序
