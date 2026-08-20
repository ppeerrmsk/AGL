# AGENTS.md

本文件为 Codex 提供 AGL 项目的**导航 + 硬约定**。每次对话自动加载，长内容已外移到 `docs/` 下，按需 Read。

## ⚠ 设计哲学

加新机制 / 数值 / 敌人 / 技能 / BOSS 前 **必读** [docs/DESIGN_PHILOSOPHY.md](docs/DESIGN_PHILOSOPHY.md)（north star + 13 条反模式 + 9 条 Litmus 测试）。

新增或修改任何**主界面 / HUD / 游戏内面板 / UI 视觉与交互**前，**必读并默认继承** [UI 设计规范](docs/specs/systems/ui-design-guidelines.md) 中的稳定通用规则。普通 UI 实现、视觉和排版调整默认只改代码与回归，不回写该规范，也不要求为差异另写 spec；只有用户明确要求“写入规范 / 设为通用规则”时才更新规范。不得另建并行 UI 通用规范。

## Project Overview

**AGL** 是俯视 2D 战斗机模拟沙盒，用 **Godot 4.7** + **GDScript** + **GL Compatibility** 渲染器。玩家以 RTS 方式点击操控战斗机（点击地图位置 → 飞机自主转弯飞向目标），飞机遵循较真实的航空物理。极简线框美术。2D 场景 + 虚拟高度（高度仅作为数值存在，通过图标缩放可视化）。

两个模式：
- **沙盒**（`scenes/main.tscn`，**已废弃**，只打生存模式包）— 自由飞行/战斗测试，F1-F5 快捷键
- **生存模式**（`scenes/survivor_mode.tscn`）— 战区推进 → BOSS 战 → **击败 BOSS 即过关**（`BossEncounterEvent` VICTORY 相 → `survivor_mode._on_victory` 结算 + 功勋入账）。数据驱动技能与机型进化详见自动生成的 [skill-table.md](docs/reference/skill-table.md)。**不是无尽波次**

## Running the Game

- 在 Godot 4.7+ 打开 `project.godot`，F5 运行，入口场景 `scenes/main_menu.tscn`
- **禁止用 Godot 4.6.2 跑本项目**：`project.godot` 的 feature tag 是 4.7；旧版 Mono 在无头 bench 中已发生原生访问冲突并卡住崩溃弹窗。CLI/bench 只用 4.7+ 的 `*_console.exe --headless`，命令必须设有限超时；不得把 GUI exe 配进 Codex/MCP 自动启动项
- 本机已验证的 4.7.1 Steam 可执行文件：`D:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。Steam 包没有单独的 `*_console.exe`，CLI 时必须加 `--headless`；优先通过 `bench/run.cmd` / `bench/run.sh` 调用，禁止复用 `.claude/settings*.json` 或历史 changelog 中的 4.6.2 命令
- **Godot bench 并发隔离**：多个 Codex task 共享同一工作树；运行 Godot/import/bench 时不得有其他 task 正在写项目文件。生成图片、宠物、探针脚本等临时产物一律放 `tmp/`（该目录由 `.gdignore` 隔离）或项目外，禁止在 Godot 可扫描目录中边写资源边启动引擎。Agent **只能通过 `bench/run.cmd` / `bench/run.sh` 启动 bench，禁止直接执行 Godot**；默认 `Shadow` 模式把已保存的运行时项目文件同步到系统临时目录的稳定隔离副本，复用其独立 `.godot` 缓存，因此允许原工作区常驻 Godot editor（编辑器内未保存修改不会进入测试）。显式第四参数 `InPlace` 才在原工作区运行，且检测到任何 Godot 进程即拒绝。两种模式共用原工作区带 owner PID 的原子锁拒绝 bench 并发；独立 `watch_godot.ps1` 在超时或调用 agent 消失时显式 `taskkill /T /F` 回收测试进程树，并以 Windows Job Object 作为二次兜底；内部有限超时默认为 `max(120s, duration+90s)`，进程级 error mode 禁止原生崩溃弹窗。`project.godot` 必须保持 `debug/file_logging/enable_file_logging.pc=false`：Godot 4.7.1 的 `RotatedFileLogger` 在本机无头启动时会因 `Ref<RegEx>` 实例化失败而读取空指针 `+0x58`；AGL 已由 EventLogger / bench 结果承担日志。若出现不可复现的 `signal 11`，先检查并发 task 与测试副本自身 `.godot/imported` 的同刻导入记录，不得直接归咎于 GDScript
- F9 导出战斗日志。**编辑器模式**写到项目内 `logs/combat_log_*.txt`（`/logs/` 被 .gitignore 排除）；**导出包**写到 `user://combat_log_*.txt`。路径切换逻辑在 `event_logger.gd:dump_to_file`
- 生存模式 F11 切换友方僚机编队调试覆盖层（橙线 → 阵型槽位 / 蓝射线 → 当前 hdg / 黄射线 → 目标 hdg / 文本: branch + slot_d + bank delta）；F12 抓一帧编队状态快照到控制台 + EventLogger
- 不使用第三方测试框架；项目自有 BenchRunner 提供断言、压力与 Visual 场景，运行时观察 + EventLogger 仍是完整局证据

## AutoLoads（初始化顺序）

以 `project.godot [autoload]` 的登记顺序为准：

1. **EventLogger / LocaleManager / AudioManager** — 日志、本地化与音频；
2. **Presentation** — 表演导演与统一时间控制；
3. **MeritLedger / CareerArchive / MetaShop** — 功勋、生涯档案与局外商店；
4. **PerfBuckets / BenchRunner / RuntimeTuner** — 性能分桶、bench 调度与运行时调参。

`CallsignDB` 是 `class_name` 静态服务，**不是 AutoLoad**。新增 AutoLoad 时同步本节、
[project-overview.md](docs/project-overview.md) 与 [repo-layout.md](docs/reference/repo-layout.md)。

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

- `PIXELS_PER_METER = 0.5`（`combat_unit.gd:8` PIXELS_PER_METER，1 像素 = 2 米）
- `GRAVITY = 9.81`（`combat_unit.gd:7` GRAVITY）
- `heading`: 弧度，0=北（屏幕上方），顺时针
- 世界坐标：Y 向下为正，绘制时通过 `rotation = heading` 让图标头朝 heading 方向
- 高度档位：`AltitudeTier { GROUND=-1, LOW=0(<3500m), MID=1(<7500m), HIGH=2(>=7500m) }`
  切档目标高度 `TIER_ALTITUDE`：LOW 2000 / MID 5500 / HIGH 10000（判定边界不等于目标值）

## ⚠ 性能守则（强制）

**任何**新增 `_process` / `_physics_process` / `_draw` / `queue_redraw` / 挂在 Aircraft/Missile 下的子节点，都必须先读 [docs/reference/performance-guidelines.md](docs/reference/performance-guidelines.md)。

8 条硬规则速记：
1. 静态内容禁止每帧 `queue_redraw`（地图/边界都吃过亏）
2. `_draw` 里不得有全场扫描（用 `AircraftRenderer.player_ref` / `CombatUnit.all_units`）
3. 多次 `draw_polygon` / `draw_line` 要合并（用 `RenderingServer.canvas_item_add_triangle_array`）
4. `_process` / `_physics_process` 禁用 `get_parent().get_children()`
5. 现有 simple AI 以 20Hz/10Hz 分频；新增慢决策/扫描默认先从 1–3Hz 起步，确有可见需要再提高
6. 挂到 Aircraft/Missile 子节点要先乘实体数（22 架 × 60Hz）
7. 新增常驻 tick/draw/实体/弹丸必须按性能守则跑代表性负载：核心为 36 名混合海陆空全可见战场 `Shadow Visual`；再按成本形状追加多战线/弹幕/BOSS/地图专项，Sentinel 不再是通用性能标杆
8. 随实体数增长的单帧成本必须支持降频 / 冻结 / 简化，并保留玩家、BOSS、Sentinel 豁免

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

### 加新东西的顺序（spec-first，强制）

AGL 采用 **spec-first** 工作流：设计/写文档是主要工作，写代码是 cheap 的下游派生。
[docs/specs/](docs/specs/_INDEX.md) 是**设计单一数据源（SSOT）**，目标"代码全丢、只看 specs 也能一比一重建游戏"。

**UI 例外**：普通主界面 / HUD / 游戏内面板的实现、视觉与排版调整不走强制 spec-first，也不自动回写 UI 规范；按本文件顶部的 UI 约定执行。只有用户明确要求写入规范或把设计确立为通用规则时，才把该次 UI 修改纳入 spec-first 流程。

加任何**敌人 / 武器 / 技能 / BOSS / 系统 / 主角机**：

1. 复制 [docs/specs/_TEMPLATE.md](docs/specs/_TEMPLATE.md) → 建 `docs/specs/<kind>/<name>.md`
2. 填 §1~§5（设计意图 + **全部数值/公式/行为** + 验收）→ 与用户确认定稿（status: approved）
3. **再**按 spec 的 §6 实现计划派生代码（接入点查 [playbook.md](docs/reference/playbook.md)）
4. 收尾：跑 §5 验收 → 填 spec §7 锚点 + 同步 reference 索引 → 写 §8 变更记录 → status: done
5. 在 [docs/specs/_INDEX.md](docs/specs/_INDEX.md) 总表追加一行

**硬分工**：`docs/specs/` 写数值/行为/原因（权威，**禁止写行号**）；`docs/reference/`（enemy-index /
script-index / code-index）只写"代码在哪"（纯指针）。样板见 [bosses/mother-goose.md](docs/specs/bosses/mother-goose.md)。

### Debug 可达性（强制）

新增或修改**技能表 / 战区奖励 / 可装备武器 / 状态效果**时，必须保证正式局之外有直接验收入口：

- 技能必须自动出现在 F4 技能面板，并可绕过机型、学说、装备与前置门控强制授予（仍尊重 `max_stacks`）。
- 技能所需装备必须能在 F4 装备区直接挂载；战区奖励必须能在 F6 奖励区逐项直接发放。
- Debug 只绕过“获得条件”，不得伪造运行时触发条件；例如全向干扰场仍需实际挂载 ESM 才生效。
- 更新表后必须补/更新自动审计，确保 Debug 清单覆盖正式数据源，避免“代码已加但测试界面调不出”。

### 查找代码的顺序

1. **先查 Script Index**（[docs/reference/script-index.md](docs/reference/script-index.md)）找文件 + 关键入口
2. **用 Read 的 `offset`/`limit` 只读需要的行段**（通常 50~100 行）
3. **不要通读大型入口脚本**（`aircraft.gd` / `ai_controller.gd` 已拆出 `scripts/aircraft/`、`scripts/ai/` 与 `scripts/ai/tactical/` 子模块；具体规模以索引为准，不在这里硬编码行数）
4. **不要对已索引的功能用 Grep/Glob 全文搜索**

只有这些情况才用 Grep：查找 Script Index 里没覆盖的新功能 / 验证符号是否仍然存在 / 跨文件的引用关系。

更细粒度的索引（按功能主题而非按文件）见 [docs/reference/code-index.md](docs/reference/code-index.md)。

### 索引维护

修改代码时必须同步：
- **新增/删除函数** → 更新 [docs/reference/script-index.md](docs/reference/script-index.md) + [docs/reference/code-index.md](docs/reference/code-index.md)
- **大幅移位**（> 50 行）→ 更新受影响的行号
- **加新敌人** → 同步 [docs/reference/enemy-index.md](docs/reference/enemy-index.md) 表 + 13 步清单
- **commit 前** 跑 `python tools/verify_player_ref_holders.py` 校验"谁是玩家机"的缓存持有者
  都在 `survivor_mode._set_player_aircraft()` 登记了（SEAM-019；漏登记 → 切控/换帅后攥住已释放旧机）
  - 加新子系统时若 `setup(..., player_aircraft, ...)`，**必须**去 chokepoint 补一行重定向
  - 若确认对方只是传参不存引用 → 加进脚本的 `NON_HOLDERS` 并写明理由（显式裁定，不要注释掉检查）
- **commit 前** 跑 `python tools/verify_doc_anchors.py` 校验索引锚点没写错行号
  （`--doc <file>` / `--section <标题>` 可只校验你动过的那段；退出码 1 = 有腐烂）
  - 文档与锚点数量以校验器实时输出为准，禁止在导航里冻结总数；**现在报红就是真出事了**，请当场修掉；
    可先用 `--fix` 保守机械刷新，多义项仍要人工判断
  - 写锚点**带上符号名**（`aircraft/aircraft_physics.gd:222 update_speed`）才能强校验；
    只写行号只能验"没越界"—— 历史上正是弱锚点掩盖了指错文件的错误
- **commit 前** 跑 `powershell -ExecutionPolicy Bypass -File tools/verify_docs.ps1` 校验当前文档断链、spec 漏登记、元数据与总表漂移

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
- **i18n 约束**：玩家可见的 UI / 升级 / 机型 / 地图 / 弹窗文本**一律走 `tr("KEY")`**，按领域在 `i18n/*.csv` 对应分表定义 key；无线电固定进 `i18n/radio.csv`。新增 UI 文本流程见 [docs/reference/i18n.md](docs/reference/i18n.md)。例外：`AircraftParams.display_name`（HUD/日志拼接用）、EventLogger、debug 面板
- **模式隔离**：禁止在共享层代码里写 `if in_survivor_mode` / `if in_sandbox`，必须走参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入

## 相关文档（按需加载）

**设计单一数据源 SSOT**（docs/specs/）—— **加新东西先来这里**
- [_INDEX.md](docs/specs/_INDEX.md) — 全部 spec 总表 + 分层硬约定 + 重建缺口清单
- [_TEMPLATE.md](docs/specs/_TEMPLATE.md) — 规格模板（复制它起新 spec）
- 权威源：写数值/公式/行为/原因，禁止行号；reference/ 才放代码指针

**入口 / 概述**
- [docs/README.md](docs/README.md) — 文档分层、生命周期与新文件目录落点
- [docs/project-overview.md](docs/project-overview.md) — 项目概述
- [docs/architecture.md](docs/architecture.md) — 物理公式 / 架构决策 / 核心设计取舍

**规划**（docs/planning/）
- [physics-ai-control-refactor.md](docs/planning/physics-ai-control-refactor.md) — 操控权限重构计划（分支布局 / 回归门 / 交接）
- [evolution-vertical-slice.md](docs/planning/evolution-vertical-slice.md) — 进化循环垂直切片
- [content-production-workflow.md](docs/planning/content-production-workflow.md) — 当前铺量顺序、批次/WIP、证据等级与完成线
- [20-hour-content-exposure-plan.md](docs/planning/20-hour-content-exposure-plan.md) — 约 20 小时首次体验窗口、节拍槽与确定的地图/BOSS 内容缺口
- [audio-visual-production-workflow.md](docs/planning/audio-visual-production-workflow.md) — 音效/音乐/机体地图细节/战斗表现素材清单、批次与完成线
- [quantitative-content-balance-model.md](docs/planning/quantitative-content-balance-model.md) — 难度/玩家上限/敌压/新鲜度/时长/内容缺口的可复算模型工作流
- ⚠ `roadmap.md` / `roadmap-overview.md` 是 2026-04 历史快照；当前状态看 [docs/specs/_INDEX.md](docs/specs/_INDEX.md)

**子系统设计**（docs/systems/）
- [ai-system.md](docs/systems/ai-system.md) — AI 状态机 / TacticalPlanner / BFM 战术 / 压力系统
- [aircraft-system.md](docs/systems/aircraft-system.md) — Aircraft 物理流程（LOD 三档）+ 战斗追踪 + 武器模式
- [event-system.md](docs/systems/event-system.md) — GameEvent + AIDirective + EventDirector（剧本系统）
- [squad-tactics-design.md](docs/systems/squad-tactics-design.md) — 编队战术 / 三段式托管
- [survivor-mode.md](docs/systems/survivor-mode.md) — 生存模式战区循环 / 进化 / 升级架构
- [survivor-skills.md](docs/systems/survivor-skills.md) — 技能设计哲学 + 系统概念 + 需求 backlog
- [missile-system.md](docs/systems/missile-system.md) — 导弹系统
- [radar-system.md](docs/systems/radar-system.md) — 雷达系统 + 锁定算法
- [ground-units.md](docs/systems/ground-units.md) — 地面单位
- [audio.md](docs/systems/audio.md) — 音频系统
- [aircraft-params.md](docs/systems/aircraft-params.md) — 飞机参数字段说明

**架构**（docs/architecture/）
- [known-seams.md](docs/architecture/known-seams.md) — **反复绊倒 fix 的耦合点登记**。修 bug 时撞到地基先来这里看，未记则加新条目。下一轮 refactor 排期的输入。

**查询手册**（docs/reference/）
- [playbook.md](docs/reference/playbook.md) — **"加新 X" 总入口索引**（敌机 / BOSS / 武器 / 技能 / 主角飞机 / 事件 / 地面单位 / 地图 / 状态 / 无线电台词 / 跨域系统 11 类）
- [script-index.md](docs/reference/script-index.md) — **关键文件职责大表**（按文件，含行号 + 入口）
- [enemy-index.md](docs/reference/enemy-index.md) — **敌人索引大表 + Adds/F-47 细节 + 创建新敌人 13 步清单 + AI Archetype**
- [repo-layout.md](docs/reference/repo-layout.md) — 完整目录树
- [code-index.md](docs/reference/code-index.md) — 功能主题索引（按武器/物理/AI/视觉等分类）
- [skill-implementation-index.md](docs/reference/skill-implementation-index.md) — 技能配置字段、实现模式与消费点总入口；当前数量和数值看自动生成的 [skill-table.md](docs/reference/skill-table.md)
- [scripts-reference.md](docs/reference/scripts-reference.md) — 脚本 API 参考（变量/方法说明）
- [resources-catalog.md](docs/reference/resources-catalog.md) — 所有 .tres 参数总表
- [playable-aircraft-workflow.md](docs/reference/playable-aircraft-workflow.md) — 加新主角飞机的完整流程
- [i18n.md](docs/reference/i18n.md) — 本地化 / 翻译 key 约定
- [features.md](docs/reference/features.md) — 已实现功能清单
- [performance-guidelines.md](docs/reference/performance-guidelines.md) — 8 条性能硬规则 + 混合战场/专项剖面验证流 + 历史教训
- `tools/verify_doc_anchors.py` — 索引锚点校验器（覆盖当前 docs + AGENTS/CLAUDE，刻意不扫 changelogs）
- `tools/verify_docs.ps1` — 当前文档断链 + spec 登记/front matter/总表一致性校验（默认不改写历史层）
- [map-pipeline.md](docs/reference/map-pipeline.md) — 地图流水线（OSM 烘焙 / 底图 / `is_on_land`）
- [manual-map-editing.md](docs/reference/manual-map-editing.md) — Godot 编辑器手画地块流程

**历史 / 变更日志**（docs/changelogs/，按日期命名）
- 最新一份 + 早期记录在 `docs/changelogs/` 下
