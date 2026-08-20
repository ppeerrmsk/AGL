---
id: heavy-gun
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: noelu（设计）/ Codex（规格化与落地）
depends_on: [zone-reward-arsenal, skills-720-rework]
reconstruction_complete: true
---

# 重型机炮

## 1. 设计意图（Why）

用可感知的几何门槛扩大机炮交战窗口，让机炮 build 能在更远距离进入自动射击，而不是增加无感的小比例伤害。

## 2. 数据定义（What）

| 项 | 值 |
|---|---|
| 稀有度 | NEXT_GEN |
| 作用范围 | 全队 |
| 层数 | 1 |
| 前置 | 机炮 |
| 机炮射程 | +1000m |
| 轴进度 | 斗士 +1 |

## 3. 行为与公式（How）

获得时对每架适用飞机的机炮 range 加 1000m；自动扫描、瞄准、散布、伤害和射速保持原样。换机与新僚机入队时按全队账本重放。

## 4. 结构与组成（Structure）

技能数据进入全队升级账本；`SurvivorPlayer.apply_upgrade` 修改每机独立复制的 GunParams。

## 5. 验收标准（Acceptance / Litmus）

- [x] 全队每架机炮射程精确 +1000m。
- [x] 不改变伤害、射速或射界。
- [x] 普通升级池不出现，战区次世代池可出现。
- [x] `skill_audit` 通过。

## 6. 实现计划（Task Pipeline）

- [x] 添加技能数据、i18n 与应用分支。
- [x] 纳入次世代池与技能审计。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| 参数应用 | `scripts/survivor/survivor_player.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 1 | 用户定稿并完成落地：全队机炮射程 +1000m、斗士 +1。 |
