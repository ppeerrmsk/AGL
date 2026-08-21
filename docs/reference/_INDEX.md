# Reference Index — AI 读码与仓库导航

> 最后校订：2026-08-21。这里是 `docs/reference/` 的统一入口，只回答“现在有什么、代码或资源在哪里、下一步读哪份”。
> 设计行为、数值和原因仍以 [Specs Index](../specs/_INDEX.md) 为权威。

## 60 秒读码路径

| 当前问题 | 先读 | 再读 | 不要先做 |
|---|---|---|---|
| 不知道功能属于哪个子系统 | [仓库目录](repo-layout.md) | 下方“代码域地图” | 通读 `scripts/` |
| 已知文件名，想知道职责和入口 | [Script Index](script-index.md) | 只读目标符号附近行段 | 打开整份大型入口脚本 |
| 已知功能名，想找具体实现 | [Code Index](code-index.md) | `rg` 验证符号或引用关系 | 对全仓库做无目标搜索 |
| 要加敌人、技能、武器、BOSS、地图或系统 | [Playbook](playbook.md) | 对应 spec / 专项 workflow | 先写代码再补设计 |
| 要查当前设计、状态或验收 | [Specs Index](../specs/_INDEX.md) | 对应 spec | 把 reference 当数值权威 |
| 修复反复出现的跨系统问题 | [Known Seams](../architecture/known-seams.md) | Script / Code Index | 在调用点继续叠补丁 |

推荐读取顺序：`_INDEX` 定域 → `script-index` 定文件 → `code-index` 定符号 → 用 offset/limit 读 50–100 行上下文。

## 索引层级

| 层级 | 文件 | 回答的问题 | 维护时机 |
|---|---|---|---|
| L0 文档入口 | [docs/README.md](../README.md) | 文档有哪些层、应该写到哪里 | 新增文档类别或改变生命周期 |
| L1 仓库地图 | [repo-layout.md](repo-layout.md) | 目录、场景、AutoLoad 和主要资源在哪 | 新增目录、入口场景或全局服务 |
| L2 文件索引 | [script-index.md](script-index.md) | 哪个脚本负责、类是什么、关键入口是什么 | 新增/删除脚本或函数、职责迁移 |
| L3 功能索引 | [code-index.md](code-index.md) | 某功能落在哪个 `文件:行号 符号` | 功能接线变化或大幅移位 |
| 内容注册表 | [enemy-index.md](enemy-index.md)、[skill-implementation-index.md](skill-implementation-index.md) | 已有哪些敌人 / 技能实现模式 | 对应正式数据源变化 |
| 生成快照 | [skill-table.md](skill-table.md) | 当前技能字段与数值 | 运行生成器刷新，禁止手改 |
| 接入流程 | [playbook.md](playbook.md) | 加一个 X 要碰哪些入口 | 接入路径或硬约定变化 |

## 代码域地图

| 代码域 | 主要路径 | 典型入口 / 真源 | 专项文档 |
|---|---|---|---|
| 场景与正式循环 | `project.godot`、`scenes/`、`scripts/survivor/survivor_mode.gd` | 主菜单 → 地图/机型选择 → Survivor；胜利由 BOSS 事件结算 | [project-overview](../project-overview.md)、[survivor-mode](../systems/survivor-mode.md) |
| 飞机实体与物理 | `scripts/aircraft.gd`、`scripts/aircraft/` | Aircraft 持有状态；physics/weapons/tracking/formation/flares 分模块 | [aircraft-system](../systems/aircraft-system.md) |
| AI 与战术 | `scripts/ai_controller.gd`、`scripts/ai/`、`scripts/ai/tactical/` | Situation → TacticalPlanner → TacticalPlan；执行层与决策层分离 | [ai-system](../systems/ai-system.md) |
| 武器、弹丸与伤害 | `scripts/equipment/`、`scripts/missile*.gd`、`scripts/bullet_manager.gd` | 参数 Resource + 运行时装备组件 + manager | [missile-system](../systems/missile-system.md) |
| 生存成长与内容 | `scripts/survivor/`、`resources/player/`、`resources/evolution/` | `survivor_data.gd`、PlayableAircraft、evolution tree 与各 registry | [skill implementation](skill-implementation-index.md)、[playable aircraft](playable-aircraft-workflow.md) |
| 敌人、王牌与 BOSS | `resources/enemy_*.tres`、`scripts/survivor/*boss*.gd`、`*ace*.gd` | EnemyType / spawner / BossRegistry / encounter | [enemy index](enemy-index.md)、[playbook](playbook.md) |
| 战区、任务与地图 | `scripts/zones/`、`scripts/survivor/zone_*.gd`、`resources/maps/` | ZoneManager、ZoneMission、MapDocument / geography | [map pipeline](map-pipeline.md)、[vector map playbook](vector-map-production-playbook.md) |
| 海军与地面单位 | `scripts/naval/`、`scripts/ground_unit.gd` 及派生类 | CombatUnit 公共生命期；舰船用挂点/弱点路由 | [ground units](../systems/ground-units.md) |
| UI、HUD 与演出 | `scripts/ui/`、`scripts/survivor/*hud*.gd`、`scripts/presentation/` | UI 通用组件；Presentation 是时间与镜头权威 | [UI 规范](../specs/systems/ui-design-guidelines.md)、[cinematic authoring](cinematic-authoring.md) |
| 局外层与本地化 | `scripts/meta/`、`i18n/`、`scripts/i18n_catalog.gd` | Merit/Career/Shop AutoLoad；五份 CSV 是文本真源 | [i18n](i18n.md) |
| 测试、bench 与工具 | `scripts/tests/`、`scenes/tests/`、`scripts/bench/`、`bench/`、`tools/` | 断言测试 / Visual QA / 受保护 Shadow runner / 仓库校验器 | [performance](performance-guidelines.md) |

## `reference/` 现有内容

### 导航与注册表

- [repo-layout.md](repo-layout.md)：稳定目录树、主要场景、AutoLoad 与子系统边界。
- [script-index.md](script-index.md)：按脚本列职责、类型和关键入口；找文件的第一站。
- [code-index.md](code-index.md)：按功能主题列精确代码锚点；找符号的第二站。
- [features.md](features.md)：已实现功能快照，不代替 spec 状态。
- [enemy-index.md](enemy-index.md)：敌人注册路径、Adds / 王牌细节与创建清单。
- [resources-catalog.md](resources-catalog.md)：`.tres` 资源指针。
- [scripts-reference.md](scripts-reference.md)：脚本 API 参考；先用前两个索引缩小范围再进入。

### 实施与生产流程

- [playbook.md](playbook.md)：新增内容的总入口。
- [skill-implementation-index.md](skill-implementation-index.md) / [skill-table.md](skill-table.md)：技能实现模式 / 自动生成现状表。
- [playable-aircraft-workflow.md](playable-aircraft-workflow.md)：新增玩家机流程。
- [map-pipeline.md](map-pipeline.md) / [manual-map-editing.md](manual-map-editing.md) / [vector-map-production-playbook.md](vector-map-production-playbook.md)：地图生产路径。
- [i18n.md](i18n.md)：本地化 key、分表与构建流程。
- [cinematic-authoring.md](cinematic-authoring.md)：表演与登场演出的编排方法。
- [performance-guidelines.md](performance-guidelines.md)：热路径硬规则与验证剖面。

## 文档结构地图

| 目录 | 性质 | 读取规则 |
|---|---|---|
| `docs/specs/` | 设计 SSOT | 查行为、数值、公式、验收与状态；新内容先建 spec |
| `docs/reference/` | 易腐烂的代码/资源指针 | 查“在哪”；允许行号，改代码后同步 |
| `docs/systems/` | 跨文件架构叙述 | 用于理解流程；数值必须回链 spec |
| `docs/architecture/`、`docs/architecture.md` | 架构决策与已知 seam | 修地基或跨系统 bug 前读 |
| `docs/planning/` | 活跃生产计划与历史计划 | 先看文件头与 `docs/README` 判断是否仍活跃 |
| `docs/audits/` | 某次审计与证据 | 是时间点结论，不自动代表今天状态 |
| `docs/changelogs/` | 已发生改动的历史快照 | 不作为当前设计真源 |
| `docs/handoffs/` | 阶段性交接上下文 | 任务关闭后只作上下文，决策回写 spec |
| `docs/design reference/` | 外部教材与研究材料 | 参考资料，不是项目契约 |

## 索引未命中时

1. 先在目标索引内搜索文件名、类名、功能名和 UI key。
2. 只在索引没有覆盖时，用 `rg` 查 `class_name`、`func`、signal 或资源 preload。
3. 跨文件引用验证优先精确搜符号，不用泛化概念词扫全仓库。
4. 找到新稳定入口后，把结果补回 `script-index` / `code-index`，避免下一位维护者重复探索。

提交前运行 `tools/verify_doc_anchors.py`、`tools/verify_docs.ps1`；索引锚点要写成
`path:line symbol`，不要只写裸行号，也不要在入口文档冻结会快速过期的文件数、行数或锚点总数。
