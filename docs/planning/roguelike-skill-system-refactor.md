# 肉鸽技能系统模块化重构

status: implemented

## 目标

在不改变 `SurvivorData.UPGRADES` 数值、随机权重、技能归属和触发效果的前提下，拆开原先混在
`survivor_mode.gd` / `survivor_player.gd` 里的四类职责：候选生成、归属投影、队级自动状态、静态效果执行。

## 权威边界

| 责任 | 唯一入口 | 约束 |
|---|---|---|
| 技能定义与数值 | `SurvivorData.UPGRADES` | 不建立第二份技能表 |
| 普通随机候选 / 三轴分组 | `SurvivorSkillCatalog.normal_candidates` / `candidates_by_axis` | 等级卡、奖励卡共用同一过滤链 |
| 玩家总账本 → 单机有效层数 | `SurvivorSkillCatalog.effective_stacks_for_machine` | `scope/classes/ace/squad_once` 只解释一次 |
| 晚入队 / 换型重放计划 | `SurvivorSkillCatalog.replay_layers_for_machine` / `owned_replay_layers` | 不重新检查获得门槛；装备资源层默认跳过 |
| 队级自动状态 | `SurvivorSkillRuntime.sync_team_state` | 只同步真正的队级资源与 static 开关；新局统一 reset |
| 获得时静态效果 | `SurvivorSkillEffects.apply` | 显式接收目标飞机；禁止临时改写当前操控机引用 |
| 低频自动触发 | `SkillHooks` 与既有正式消费点 | 不新增逐机 tick，不复制状态词条逻辑 |

## 数据流

`UPGRADES → Catalog 候选 → 选卡 → upgrade_stacks 总账本 → Catalog 单机投影 → aircraft meta / Runtime 队级状态`

静态属性在获得或重放时走 `SurvivorPlayer.apply_upgrade_to → SurvivorSkillEffects.apply`。动态机动状态仍只从
`aircraft_physics.gd` 的 `effective_*()` accessor 读取，未在物理 tick 新增散点乘区。

## 删除的历史负担

- 删除 `survivor_mode` 中两份普通随机池过滤循环。
- 删除已无数据使用的 `evolves_to` 自动技能进化链。
- 删除 `apply_upgrade_to` 临时替换 `SurvivorPlayer.aircraft` 的隐式上下文技巧。
- 全表技能审计改为检查真实效果模块和队级运行时模块，新增 stat 会在执行器缺分支时报警。

## 回归合同

- `skills720`：随机池过滤、三轴分组、通用/品类/王牌/队级归属、装备重放跳过、目标引用稳定、队级自动状态清零，以及现有复合构筑。
- `skill_audit`：逐条审计全部技能的配置、静态效果或运行时消费点、三语文案和 Debug 可达性。
- 属性与签名专项：`player_params`、`attr_gates`、`sig_skills`。
- 终态：默认 `all`（含 `lifecycle_gauntlet`）。
