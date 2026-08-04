---
id: flee
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: noelu（设计）/ Codex（规格化与落地）
depends_on: [skills-720-rework, global-awareness-roe]
reconstruction_complete: true
---

# 逃离

## 1. 设计意图（Why）

把 FEAR build 的控制结果转成可见的“敌人失去战意并撤退”，给普通载人敌机增加演戏感，同时避免一项控制技能直接跳过王牌或 BOSS 内容。

## 2. 数据定义（What）

| 项 | 值 |
|---|---|
| 稀有度 | EXPERIMENTAL |
| 作用范围 | 全队唯一 `squad_once` |
| 层数 | 1 |
| 前置 | 任意可施加 FEAR 的技能 |
| 触发率 | 新 FEAR 成功落地时 40% |
| 有效目标 | 普通载人敌机 |
| 排除 | 无人机、ACE、BOSS、BOSS 生成物、无击杀奖励单位 |
| 经验 | 目标开始撤离时按正常击杀经验结算一次 |
| 轴进度 | 策士 +1 |

## 3. 行为与公式（How）

玩家小队首次为目标施加一段新的 FEAR 时掷 40%。命中后目标清除战斗目标和编队关系，使用加力飞向地图外退场点；45 秒仍未离场则释放。XP 在进入撤离时结算并写一次性标记，之后不得因释放或其它伤害重复发放。

## 4. 结构与组成（Structure）

技能表提供 FEAR 前置与 squad_once；`SkillHooks.on_player_fear_landed` 做资格与概率判定；Spawner 提供只发一次的正常 XP 结算；既有 AI/ROE 承担物理撤退。

## 5. 验收标准（Acceptance / Litmus）

- [x] 所有玩家小队 FEAR 来源进入统一触发点。
- [x] 只有新 FEAR 掷一次 40%，刷新同一状态不重复掷。
- [x] 普通载人敌机真实飞离，不是当场删除。
- [x] 无人机、ACE、BOSS 与 BOSS 生成物完全豁免。
- [x] XP 只结算一次。
- [x] `skill_audit` 通过。

## 6. 实现计划（Task Pipeline）

- [x] 添加技能数据、前置、i18n 与策士进度。
- [x] 接入 FEAR 落地钩子、撤退状态与 XP 一次性结算。
- [x] 添加技能审计覆盖。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| FEAR 判定与撤退 | `scripts/survivor/skill_hooks.gd` |
| XP 结算 | `scripts/survivor/survivor_spawner.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 1 | 用户定稿并完成落地：新 FEAR 40% 令普通载人敌机撤离并正常结算一次 XP。 |
