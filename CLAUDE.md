# CLAUDE.md

本文件为 Claude Code 提供 AGL 项目的**导航 + 硬约定**。每次对话自动加载，长内容已外移到 `docs/` 下，按需 Read。

## ⚠ 设计哲学

加新机制 / 数值 / 敌人 / 技能 / BOSS 前 **必读** [docs/DESIGN_PHILOSOPHY.md](docs/DESIGN_PHILOSOPHY.md)（north star + 13 条反模式 + 9 条 Litmus 测试）。

## Project Overview

**AGL** 是俯视 2D 战斗机模拟沙盒，用 **Godot 4.6** + **GDScript** + **GL Compatibility** 渲染器。玩家以 RTS 方式点击操控战斗机（点击地图位置 → 飞机自主转弯飞向目标），飞机遵循较真实的航空物理。极简线框美术。2D 场景 + 虚拟高度（高度仅作为数值存在，通过图标缩放可视化）。

两个模式：
- **沙盒**（`scenes/main.tscn`，**已废弃**，只打生存模式包）— 自由飞行/战斗测试，F1-F5 快捷键
- **生存模式**（`scenes/survivor_mode.tscn`）— 无尽波次，击杀升级，20+ 种升级含进化技能

## Running the Game

- 在 Godot 4.6+ 打开 `project.godot`，F5 运行，入口场景 `scenes/main_menu.tscn`
- F9 导出战斗日志。**编辑器模式**写到项目内 `logs/combat_log_*.txt`（`/logs/` 被 .gitignore 排除）；**导出包**写到 `user://combat_log_*.txt`。路径切换逻辑在 `event_logger.gd:dump_to_file`。配合 `.claude/hooks/open-latest-log.sh`（UserPromptSubmit hook）在下次消息时自动打开最新 log
- 生存模式 F11 切换友方僚机编队调试覆盖层（橙线 → 阵型槽位 / 蓝射线 → 当前 hdg / 黄射线 → 目标 hdg / 文本: branch + slot_d + bank delta）；F12 抓一帧编队状态快照到控制台 + EventLogger
- 无正式测试框架，通过运行时观察 + EventLogger 日志调试

## AutoLoads（初始化顺序）

`project.godot [autoload]`:
1. **CallsignDB** — 呼号分配器（每架飞机 `_ready()` 时调用 `CallsignDB.allocate()`）
2. **EventLogger** — 全局事件环形缓冲区（60 秒窗口，F9 导出）
3. **LocaleManager** — i18n 本地化，启动读 `user://locale.cfg`
4. **AudioManager** — 音频总线 + BGM + SFX + UI + 播放列表；详见 [docs/systems/audio.md](docs/systems/audio.md)
5. **MeritLedger** — 局外货币"功勋"账本，读写 `user://merit.cfg`；局内 XP 按 0.8/1.0 系数折算入账

## 类继承体系

```
Node2D
├── CombatUnit              # 战斗单位基类（team/hp/altitude/雷达/锁定）
│   ├── Aircraft            # 飞机
│   └── GroundUnit → SAMUnit / AAGunUnit / RadarStation
├── Missile / BulletManager / MissileManager / TrailRibbon

Node
└── AIController            # 附加到 Aircraft 的 AI 状态机

RefCounted: Squad / SurvivorData
Resource:   AircraftParams / GunParams / RocketParams / MissileParams / CombatParams / FlareParams
```

## 关键常量与坐标系

- `PIXELS_PER_METER = 0.5`（`combat_unit.gd:9`，1 像素 = 2 米）
- `GRAVITY = 9.81`（`combat_unit.gd:8`）
- `heading`: 弧度，0=北（屏幕上方），顺时针
- 世界坐标：Y 向下为正，绘制时通过 `rotation = heading` 让图标头朝 heading 方向
- 高度档位：`AltitudeTier { GROUND=-1, LOW=0(<3500m), MID=1(<7500m), HIGH=2(>=7500m) }`

## ⚠ 性能守则（强制）

**任何**新增 `_process` / `_physics_process` / `_draw` / `queue_redraw` / 挂在 Aircraft/Missile 下的子节点，都必须先读 [docs/reference/performance-guidelines.md](docs/reference/performance-guidelines.md)。

8 条硬规则速记：
1. 静态内容禁止每帧 `queue_redraw`（地图/边界都吃过亏）
2. `_draw` 里不得有全场扫描（用 `AircraftRenderer.player_ref` / `CombatUnit.all_units`）
3. 多次 `draw_polygon` / `draw_line` 要合并（用 `RenderingServer.canvas_item_add_triangle_array`）
4. `_process` / `_physics_process` 禁用 `get_parent().get_children()`
5. AI 决策默认从 20Hz 甚至 10Hz 起步（`ai_tick_divisor ≥ 3`）
6. 挂到 Aircraft/Missile 子节点要先乘实体数（22 架 × 60Hz）
7. 新功能必须跑生存模式 Sentinel + Lv5+ 压力测试，FPS 掉 >15 就回滚

历史翻车清单（尾迹 40 万 draw_polygon/秒、地图每帧重算、数据标签 O(N²) 扫描等）见守则末尾"历史教训"段。

## ⚠ 加机动性 buff 的规范（强制）

任何影响**飞机速度 / G 力 / 失速 / 转弯**的玩家 skill / status / upgrade，**只能在两个地方注入乘数**，否则 AI 战术层不会感知到 buff，导致升级名存实亡：

1. **永久升级**（升级一次永久生效）→ 在 [survivor_player.gd:apply_upgrade](scripts/survivor/survivor_player.gd) 直接改 `params.*` 字段。范例：DOGFIGHT_STALL_MULT 改 `p.stall_speed_base`、EXECUTIONER 改 `p.max_speed`。
2. **状态/模式 buff**（BLOODLUST、OVERLOAD、evasion_mode、被锁恐慌等运行时启停）→ 在 [aircraft_physics.gd](scripts/aircraft/aircraft_physics.gd) 对应的 `effective_*()` accessor 里加一段 if 块（不超过 5 行）：
   - `effective_max_g(ac)` — G 力相关
   - `effective_max_speed_kmh(ac)` — 顶速相关
   - `effective_cruise_speed_kmh(ac)` — 巡航速度相关
   - `effective_stall_speed_kmh(ac)` — 失速基数相关
   - `effective_corner_speed_kmh(ac)` — 自动随 effective_max_g 抬升

**禁止**：
- 在 `update_speed` / `update_bank` / `update_heading` 等物理 tick 里散点 if-else 乘 buff（除非是物理 cap 的 buff 抬升，且必须与 accessor 共享同一注入语义）
- 在 [Situation.from_aircraft](scripts/ai/tactical/situation.gd) 里直接读 `ac.params.*` —— 必须经过 effective_*() accessor

**新增 buff 的 onboarding checklist**：
- [ ] 决定 buff 类别（永久 / 状态 / 模式）
- [ ] 在对应位置加注入点（5 行以内 + 一行注释说明 buff 名称）
- [ ] **不需要**改 Situation / TacticalPlanner / BfmIntent / update_speed —— accessor 自动透传到 AI 战术
- [ ] 跑验证：升满 buff，EventLogger 看 AI 设的 `target_speed_kmh` / G 应可见抬升
- [ ] 验证零 buff 下行为不变（accessor 内 if 块未触发时返回值与 baseline 一致）

历史翻车记录：规避加力 +40% / BLOODLUST +G / lock_panic +G / EXECUTIONER +Speed 都曾因 Situation 直读 `params.*` 而对 AI 失明，导致升级体感打折。effective_*() accessor 层是这类问题的统一根治方案。

## 工作约定

### 查找代码的顺序

1. **先查 Script Index**（[docs/reference/script-index.md](docs/reference/script-index.md)）找文件 + 关键入口
2. **用 Read 的 `offset`/`limit` 只读需要的行段**（通常 50~100 行）
3. **不要通读整个 .gd 文件**（`aircraft.gd` 1445 行 + 4 个子模块 274~873 行；`ai_controller.gd` 1235 行 + 4 个子模块 165~574 行）
4. **不要对已索引的功能用 Grep/Glob 全文搜索**

只有这些情况才用 Grep：查找 Script Index 里没覆盖的新功能 / 验证符号是否仍然存在 / 跨文件的引用关系。

更细粒度的索引（按功能主题而非按文件）见 [docs/reference/code-index.md](docs/reference/code-index.md)。

### 索引维护

修改代码时必须同步：
- **新增/删除函数** → 更新 [docs/reference/script-index.md](docs/reference/script-index.md) + [docs/reference/code-index.md](docs/reference/code-index.md)
- **大幅移位**（> 50 行）→ 更新受影响的行号
- **加新敌人** → 同步 [docs/reference/enemy-index.md](docs/reference/enemy-index.md) 表 + 12 步清单
- **commit 前** 检查索引与代码一致性

### 触发短语

- `"用 index"` / `"走索引"` — 严格按 Script Index → Read offset 流程，不读全文件
- `"更新 index"` — 重新扫描代码更新 script-index.md + code-index.md

### 代码规范

- **语言**：GDScript，注释与文档用中文
- **命名**：snake_case 方法/变量，PascalCase 类名和场景
- **类型**：尽量使用类型提示（`var x: float`），避免 Variant
- **信号**：通过 signal 解耦，不用全局变量共享状态
- **Resource 复用**：`.tres` 文件通过 `preload()` 加载，生成子节点时用 `duplicate(true)` 避免共享修改
- **CombatUnit 基类**：所有战斗单位（包括地面）共用 `team/hp/altitude/radar_targets/is_locked`，扩展时覆写 `is_in_radar_cone` / `take_damage` / `is_lock_immune`
- **i18n 约束**：玩家可见的 UI / 升级 / 机型 / 地图 / 弹窗文本**一律走 `tr("KEY")`**，在 `i18n/translations.csv` 定义 key。新增 UI 文本流程见 [docs/reference/i18n.md](docs/reference/i18n.md)。例外：`AircraftParams.display_name`（HUD/日志拼接用）、EventLogger、debug 面板
- **模式隔离**：禁止在共享层代码里写 `if in_survivor_mode` / `if in_sandbox`，必须走参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入

## 相关文档（按需加载）

**入口 / 概述**
- [docs/project-overview.md](docs/project-overview.md) — 项目概述
- [docs/architecture.md](docs/architecture.md) — 物理公式 / 架构决策 / 核心设计取舍

**规划**（docs/planning/）
- [roadmap-overview.md](docs/planning/roadmap-overview.md) — 阶段 / 玩家视角，用于排期
- [roadmap.md](docs/planning/roadmap.md) — 技术向（模式边界 / 反馈修复）

**子系统设计**（docs/systems/）
- [ai-system.md](docs/systems/ai-system.md) — AI 状态机 / 8 战术 / TacticalPlanner P4 / 压力系统
- [aircraft-system.md](docs/systems/aircraft-system.md) — Aircraft 物理流程（LOD 三档）+ 战斗追踪 + 武器模式
- [event-system.md](docs/systems/event-system.md) — GameEvent + AIDirective + EventDirector（剧本系统）
- [squad-tactics-design.md](docs/systems/squad-tactics-design.md) — 编队战术 / 三段式托管
- [survivor-mode.md](docs/systems/survivor-mode.md) — 生存模式波次/升级表
- [survivor-skills.md](docs/systems/survivor-skills.md) — 完整技能图鉴 + 设计哲学 + 战区奖励池
- [missile-system.md](docs/systems/missile-system.md) — 导弹系统
- [radar-system.md](docs/systems/radar-system.md) — 雷达系统 + 锁定算法
- [ground-units.md](docs/systems/ground-units.md) — 地面单位
- [audio.md](docs/systems/audio.md) — 音频系统
- [aircraft-params.md](docs/systems/aircraft-params.md) — 飞机参数字段说明

**架构**（docs/architecture/）
- [known-seams.md](docs/architecture/known-seams.md) — **反复绊倒 fix 的耦合点登记**。修 bug 时撞到地基先来这里看，未记则加新条目。下一轮 refactor 排期的输入。

**查询手册**（docs/reference/）
- [script-index.md](docs/reference/script-index.md) — **关键文件职责大表**（按文件，含行号 + 入口）
- [enemy-index.md](docs/reference/enemy-index.md) — **敌人索引大表 + Adds/F-47 细节 + 创建新敌人 12 步清单 + AI Archetype**
- [repo-layout.md](docs/reference/repo-layout.md) — 完整目录树
- [code-index.md](docs/reference/code-index.md) — 功能主题索引（按武器/物理/AI/视觉等分类）
- [scripts-reference.md](docs/reference/scripts-reference.md) — 脚本 API 参考（变量/方法说明）
- [resources-catalog.md](docs/reference/resources-catalog.md) — 所有 .tres 参数总表
- [playable-aircraft-workflow.md](docs/reference/playable-aircraft-workflow.md) — 加新主角飞机的完整流程
- [i18n.md](docs/reference/i18n.md) — 本地化 / 翻译 key 约定
- [features.md](docs/reference/features.md) — 已实现功能清单
- [performance-guidelines.md](docs/reference/performance-guidelines.md) — 8 条性能硬规则 + 历史教训
- [map-pipeline.md](docs/reference/map-pipeline.md) — 地图流水线（OSM 烘焙 / 底图 / `is_on_land`）
- [manual-map-editing.md](docs/reference/manual-map-editing.md) — Godot 编辑器手画地块流程

**历史 / 变更日志**（docs/changelogs/，按日期命名）
- 最新一份 + 早期记录在 `docs/changelogs/` 下
