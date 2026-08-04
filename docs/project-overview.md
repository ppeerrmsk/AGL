# AGL — 项目概述

> 最后校订：2026-08-04。本文只写"AGL 是什么 / 由什么组成 / 去哪里查"。
> **设计权威源是 [docs/specs/](specs/_INDEX.md)**，数值与行为一律以那里为准；本文不放数值。

## 是什么

俯视 2D 空战游戏，Godot 4.7 + GDScript + GL Compatibility 渲染器。极简线框美术。
2D 场景 + 虚拟高度（`altitude` 只是数值，通过图标缩放可视化）。

**操控语法是 RTS 式的**：玩家点击地图位置 → 飞机按较真实的航空物理自主转弯飞过去；
武器全部按状态自动开火，玩家只负责把飞机开进"该开火的位置"
（见 [DESIGN_PHILOSOPHY.md](DESIGN_PHILOSOPHY.md) 原则 10）。

项目方向已从"单机吸血鬼幸存者"转为**操控小队的 RTS 空战**：
数字键 1–9 接管对应号机、命令轮盘对全队广播命令、僚机按学说自主配合。

## 两个模式

| 模式 | 场景 | 状态 |
|---|---|---|
| **生存模式** | `scenes/survivor_mode.tscn` | **主玩法**，唯一出包的模式 |
| 沙盒模式 | `scenes/main.tscn` | **已废弃**，只作物理/AI 调试留存。不要给它加新内容 |

游戏入口场景是 `scenes/main_menu.tscn`（`project.godot` 的 `run/main_scene`）。

### 生存模式核心循环

```
起飞（从当前已解锁的起手机型中选择）
  → 战区推进：攻克战区 → 飞到停靠点着陆结算 → 领奖励 / 换机进化
  → 每 3 级触发三轴卡片三选一（斗士 / 骑士 / 策士各一张）
  → 时间到点 → BOSS 阶段
  → 击败 BOSS = 过关（不是无尽波次）
  → 局内 XP 按系数折算为局外"功勋"（MeritLedger）
```

细节权威源：[specs/systems/survivor-loop](specs/systems/survivor-loop.md) ·
[specs/systems/zone-reward-docking](specs/systems/zone-reward-docking.md) ·
[specs/systems/aircraft-evolution-tree](specs/systems/aircraft-evolution-tree.md) ·
[specs/systems/evolution-attribute-gates](specs/systems/evolution-attribute-gates.md)

## 代码构成（粗粒度）

完整目录树见 [reference/repo-layout.md](reference/repo-layout.md)，按文件的职责表见
[reference/script-index.md](reference/script-index.md)，按功能主题的索引见
[reference/code-index.md](reference/code-index.md)。

| 层 | 位置 | 说明 |
|---|---|---|
| 战斗单位 | `scripts/combat_unit.gd` + `aircraft.gd` / `ground_unit.gd` / `naval/` | 共用 team/hp/altitude/雷达/锁定 基类 |
| 飞行物理 | `scripts/aircraft/` | 物理 / 武器 / 战斗追踪 / 编队 / 热诱弹 五个子模块 |
| AI | `scripts/ai_controller.gd` + `scripts/ai/` | 状态机 + TacticalPlanner 战术层 + 蜂群 |
| 武器 | `scripts/equipment/` + `missile*.gd` / `bullet_manager.gd` | 运行时武器组件（不是已退役的局外槽位配件）+ 弹体管理 |
| 生存模式 | `scripts/survivor/` | 主控 / 刷怪 / 战区 / 技能 / 进化 / HUD |
| RTS 指挥 | `scripts/rts/` | 命令轮盘 + 小队命令控制器（独立模块，不塞 survivor_mode） |
| 剧本 | `scripts/events/` | GameEvent + EventDirector + AIDirective |
| 演出 | `scripts/presentation/` | TimeAuthority / SequencePlayer / 舞台隔离 |
| 地图 / UGC | `scripts/zones/` + `scripts/ugc/` | 战区 + 地图编辑器 + 烘焙 |
| 无头测试 | `scripts/tests/` + `scripts/bench/` | `--bench=<name>` 跑断言，无正式测试框架 |

## AutoLoads（初始化顺序）

以 `project.godot [autoload]` 的顺序为准：EventLogger → LocaleManager → AudioManager →
Presentation → MeritLedger → CareerArchive → MetaShop → PerfBuckets → BenchRunner → RuntimeTuner。
`CallsignDB` 是 `class_name` 静态服务，不是 AutoLoad。职责说明见 [AGENTS.md](../AGENTS.md)。

## 从哪里开始查

| 我想…… | 去哪 |
|---|---|
| 了解文档分层或决定新文件放哪 | [README.md](README.md) |
| 加新敌人 / 武器 / 技能 / BOSS / 系统 | [reference/playbook.md](reference/playbook.md)（总入口）→ 先建 spec |
| 知道某个机制**为什么这样设计、数值是多少** | [specs/_INDEX.md](specs/_INDEX.md) |
| 找某段代码在哪 | [reference/script-index.md](reference/script-index.md) → [reference/code-index.md](reference/code-index.md) |
| 知道设计红线 | [DESIGN_PHILOSOPHY.md](DESIGN_PHILOSOPHY.md) + [reference/performance-guidelines.md](reference/performance-guidelines.md) |
| 知道某次改动当时做了什么 | `docs/changelogs/` |
