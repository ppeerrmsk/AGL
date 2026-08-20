# 铺量阶段量化模型工作流

> 状态：2026-08-20 首版。本文定义模型如何使用、什么能下结论、什么必须等待遥测。

## 1. 目的

本模型同时回答六个问题：总体难度曲线、玩家能力上限、敌人战斗力、玩家获得新刺激的节奏、完成长期目标所需时间，以及仍需生产多少内容。

它不把所有东西压成一个“战力数字”。纸面能力、实战转化、遭遇压力、新鲜度、经济时间和性能容量分别建模，最后才在同一时间轴上比较。

## 2. 权威输入

- 玩家机与解锁门槛：`resources/evolution/evolution_tree.json` + `player-aircraft-power-curve`；
- 技能库存：自动生成的 `docs/reference/skill-table.md`；
- 常规敌机：`EnemyPoolRegistry.ROWS` 的解锁、角色、Token 与编成；
- 单局节奏：`survivor-loop` 的 Token、刷新、XP 与 600 秒战区阶段；
- BOSS / 地图：`BossRegistry` 与 `SurvivorMapSelect.MAP_LIST`；
- 长期经济：当前 `MetaShop` 与 `aircraft-mastery-progression` 草案；
- 实战转化：后续接入 `combat-effectiveness-metrics` 的交战记录；
- 性能容量：C1 混合海陆空全可见场及其专项剖面。

任何从草案或规划引入的数值必须标 C；没有统一数据源的维度标 D，不得用主观估算伪装成现状。

## 3. 六条曲线

1. **玩家纸面曲线 P**：机体 Tier、当前 build、编队规模与未来熟练度分开输出；永久成长与局内成长不得相加后丢失来源。
2. **敌人单位能力 E_unit**：先以 Token 作为当前生产预算代理；后续用静态 CapIndex 与真实 FSR/命中/TTK 校准每 Token 的有效威胁。
3. **遭遇难度 D**：在场总威胁、刷新速率、任务注意力、地形和 attrition 共同决定；BOSS 机制另列，不能混成普通血包。
4. **新鲜度 N**：只计算首次看见、首次理解、首次改变决策的内容；重复出现按实测衰减，不按资源文件数计分。
5. **时间 T**：以实际局长、功勋收入分布、首次曝光和购买时刻计算；20 小时是持续展开目标，不是强制拖延时长。
6. **内容缺口 G**：`目标节拍 - 已排期且可感知节拍`。库存存在但没有首次曝光时刻的内容，记“待编排”，不直接记完成。

## 4. 使用方式

运行：

```powershell
python tools/analysis/agl_quantitative_model.py --write-report docs/audits/2026-08-20-quantitative-model-baseline.md
python tools/analysis/agl_quantitative_model.py --check
```

配置在 `tools/analysis/agl_quantitative_model_config.json`。A/B 级输入原则上由仓库自动读取；C 级参数集中放配置，替换时必须写明证据批次，禁止散落进脚本。

## 5. 决策门

- 没有至少 20 个种子的成功率/TTK 分布，不用 D 曲线直接调敌人 HP、Token 或玩家伤害；
- 没有真实首次曝光数据，不用新鲜度积分宣布“内容够了”；
- 没有结算功勋分布，不拍死商店价格；
- 没有 C1 + 对应专项性能证据，不批准会增加常驻实体、弹丸或 draw 的铺量批；
- 数学模型发现缺口后，新增敌人、技能、BOSS、系统仍逐项走 spec-first 与设计哲学 Litmus。

## 6. 当前输出

首版报告见 [量化内容与难度模型基线](../audits/2026-08-20-quantitative-model-baseline.md)。
20 小时窗口和节拍槽见 [20 小时内容首次体验排期骨架](20-hour-content-exposure-plan.md)。当前最重要的 D 级空白是跨局曝光日程：下一轮要给机体、技能、功能、任务、BOSS 层和地图逐项增加 `first_seen` 计划与真实遥测。
