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
- F9 导出战斗日志到 `user://combat_log_*.txt`

无正式测试框架，通过运行时观察 + EventLogger 日志调试。

## Repository Layout

```
AGL/
├── project.godot              # Godot 项目配置（含 AutoLoad: EventLogger, CallsignDB）
├── scenes/
│   ├── main.tscn              # 沙盒主场景（Main + BulletManager + MissileManager + Camera2D）
│   ├── main_menu.tscn         # 主菜单（入口场景）
│   ├── survivor_mode.tscn     # 生存模式
│   ├── survivor_select.tscn   # 生存模式选择界面
│   ├── aircraft.tscn          # 飞机模板（通用）
│   ├── missile.tscn           # 导弹模板
│   ├── sam_unit.tscn          # 防空导弹车
│   ├── aa_gun_unit.tscn       # 高射炮
│   └── radar_station.tscn     # 雷达站
├── scripts/
│   ├── main.gd                # 沙盒主场景：相机/输入/雷达锁定/编队生成/地形
│   ├── main_menu.gd           # 主菜单
│   ├── aircraft.gd            # Aircraft 实体（~2500 行，物理+战斗+武器+视觉）
│   ├── aircraft_params.gd     # AircraftParams Resource
│   ├── ai_controller.gd       # AI 状态机（巡逻/交战/规避/编队）
│   ├── combat_unit.gd         # 战斗单位基类（Aircraft/GroundUnit 共享接口）
│   ├── missile.gd             # 导弹实体（PN 制导）
│   ├── missile_manager.gd     # 导弹管理器（命中检测/在飞查询）
│   ├── missile_params.gd      # MissileParams Resource
│   ├── bullet_manager.gd      # 机炮子弹管理（物理+命中）
│   ├── gun_params.gd          # GunParams Resource
│   ├── rocket_params.gd       # RocketParams Resource（无制导火箭弹）
│   ├── combat_params.gd       # CombatParams Resource（AI 行为风格）
│   ├── flare_params.gd        # FlareParams Resource
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
│   └── survivor/
│       ├── survivor_mode.gd       # 生存模式主控制器（波次/刷怪/猎手）
│       ├── survivor_player.gd     # 经验/等级/升级应用
│       ├── survivor_data.gd       # 升级定义 + 波次参数 + 经验曲线（静态）
│       ├── survivor_hud.gd        # HUD（HP/经验/战术按钮）
│       ├── survivor_upgrade_ui.gd # 升级选择界面
│       ├── survivor_select.gd     # 模式选择
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
| **Adds（杂鱼）** | UAV/UCAV/地面单位，低威胁+高经验 | — | UAV / UCAV / 地面单位 |
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

**所有 Token / 上限 / 解锁常量** 都在 `survivor_data.gd` 里集中定义：
- `TOKEN_COST`（`:261`）/ `TOKEN_INSTANCE_CAP`（`:276`）/ `TOKEN_BUDGET_BASE/PER_LEVEL/MAX`（`:254`）
- `FAR_CLEANUP_DISTANCE`（`:289`）/ `FAR_CLEANUP_INTERVAL`（`:290`）/ `LATE_GAME_LEVEL`（`:296`）
- 每个敌人的 `*_UNLOCK_LEVEL` / `*_CHANCE_PER_LEVEL` / `*_CHANCE_MAX`（`:220-244`）

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
12. **更新 `docs/code-index.md` 对应段落**（如新文件/新函数）

操作时用 Read 的 offset/limit 精确定位，不要通读整个 survivor_mode.gd（1450 行）。每一步改完就 commit 或至少 git diff 看一眼，防止漏 case 导致 NullRef 崩溃。

### 关键文件职责（Script Index）

| 文件 | 类/类型 | 职责 | 关键入口 |
|------|---------|------|----------|
| `aircraft.gd` | `Aircraft extends CombatUnit` | 飞机物理+战斗+武器+视觉（最核心，~2930 行） | `_physics_process:194` `_update_combat:1107` `_update_gun:1422` `_update_rocket:1468` `_update_weapon_mode:1599` `_update_missile:1811` `_effective_missile_range_px` `_missile_cannot_hit_but_gun_can` `_should_commit_gun_pass` `_is_gun_pass_finished` `_release_flares(target_missile)` `set_evasion_mode` `_corner_speed_kmh` |
| `rocket_params.gd` | `RocketParams extends Resource` | 无制导火箭弹参数（齐射数/散布/冷却） | — |
| `ai_controller.gd` | `AIController extends Node` | AI 状态机 + BFM 战术决策树（~1620 行） | `_process_patrol:553` `_process_squad_follow:583` `_process_engage:736` `_choose_tactic:952` `_process_evade:1341` |
| `combat_unit.gd` | `CombatUnit extends Node2D` | 战斗单位基类（通用接口） | `take_damage:81` `is_in_radar_cone:94` `get_altitude_tier:65` |
| `missile.gd` | `Missile extends Node2D` | 导弹飞行物理（PN 制导/SARH） | `_physics_process:37` `_guidance_degradation:238` |
| `missile_manager.gd` | `MissileManager extends Node2D` | 导弹生成+命中+连锁弹头 | `spawn_missile:11` `_physics_process:46` `_find_bounce_target:101` |
| `bullet_manager.gd` | `BulletManager extends Node2D` | 子弹/火箭物理+命中+伤害衰减（162 行） | `spawn_bullet:23` `spawn_rocket:38` `_physics_process` |
| `main.gd` | `Main extends Node2D` | 沙盒主控：相机/输入/锁定循环/编队/LOD/地形 | `_update_radar_locks:226` `_spawn_friendly_squad:313` `_update_lod:455` |
| `squad.gd` | `Squad extends RefCounted` | 6 种阵型偏移计算 | `get_formation_offset:51` `get_wingman_target:114` `cycle_formation:128` |
| `ground_unit.gd` | `GroundUnit extends CombatUnit` | 地面单位基类（机炮+雷达+移动） | `_update_movement:63` `_update_combat:131` `_update_gun:164` |
| `sam_unit.gd` | `SAMUnit extends GroundUnit` | SAM：360° 雷达 + HQ-7 导弹 | `_update_sam_missile:26` `is_in_radar_cone:54`（覆写圆形） |
| `aa_gun_unit.gd` | `AAGunUnit extends GroundUnit` | AAA：独立炮塔 + ZU-23 | `_update_turret:69` `_update_aa_target_selection:30` |
| `radar_station.gd` | `RadarStation extends GroundUnit` | 雷达站：20km 雷达 + 数据链共享 | `_update_datalink:35` `_update_dish:29` |
| `survivor/survivor_mode.gd` | 生存模式主控（~1450 行） | 波次/刷怪/猎手/升级/Token 预算/远距清理 | `_update_spawner:722` `_pick_enemy_type:874` `_recalc_token_usage:851` `_can_spawn_type:863` `_get_token_budget:846` `_update_far_cleanup:586` `_update_hunters:610` `_spawn_single:934` `_spawn_squad:942` `_spawn_commander_squad:982` `_create_enemy:1038` `_detect_kills:1261` — **EnemyType enum:843** |
| `survivor/survivor_debug_spawn.gd` | `SurvivorDebugSpawn extends CanvasLayer` | F5 刷怪调试面板（279 行） | `_build_ui:60` `_on_type_changed:226` `_on_spawn_pressed:236` `_on_clear_pressed:264` `_on_dump_pressed:276` |
| `survivor/survivor_player.gd` | `SurvivorPlayer extends Node` | 经验/等级/升级应用 | `add_xp:20` `apply_upgrade:30` |
| `survivor/survivor_data.gd` | `SurvivorData extends RefCounted` | 升级表/波次常量/Token 预算/经验曲线 | `UPGRADES:12` `TOKEN_COST:261` `TOKEN_INSTANCE_CAP:276` `TOKEN_BUDGET_*:254` `FAR_CLEANUP_DISTANCE:289` `LATE_GAME_LEVEL:296` `xp_for_level` `enemy_scale_for_level` |
| `survivor/commander_aura.gd` | `CommanderAura extends Node` | Sentinel 光环 buff + 招募 UAV | `_apply_buff:93` `_try_recruit:155` |
| `debug_panel.gd` | 调试面板 | 状态文本/飞行员信息/生成按钮 | `_get_strategy_text:266` `_get_combat_strategy:303` `_get_pilot_info:318` |
| `event_logger.gd` | EventLogger (AutoLoad) | 全局事件环形日志 | `log_event:22` `dump_to_file:31` |
| `callsign_db.gd` | CallsignDB (AutoLoad) | 呼号分配+回收 | `allocate` / `release` |

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

更细粒度的索引（按功能主题而非按文件）见 `docs/code-index.md`。

### 索引维护

修改代码时必须同步：
- **新增/删除函数** → 更新 CLAUDE.md 的 Script Index 表 + `docs/code-index.md`
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
- **不要修改 CLAUDE.md 的 Script Index 之外的段落** 除非是架构级变更

## 相关文档

按需加载，不是每次都读：

- [docs/code-index.md](docs/code-index.md) — 更细的功能主题索引（武器/物理/AI/视觉等分类）
- [docs/scripts-reference.md](docs/scripts-reference.md) — 脚本 API 参考（所有变量/方法说明）
- [docs/ai-system.md](docs/ai-system.md) — AI 状态机/战术/压力系统详解
- [docs/survivor-mode.md](docs/survivor-mode.md) — 生存模式波次/升级表
- [docs/ground-units.md](docs/ground-units.md) — 地面单位设计
- [docs/resources-catalog.md](docs/resources-catalog.md) — 所有 .tres 参数总表
- [docs/architecture.md](docs/architecture.md) — 物理公式与架构决策
- [docs/changelog-2026-04-10.md](docs/changelog-2026-04-10.md) — 最新更新日志
