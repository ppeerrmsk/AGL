---
id: hunter
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: noelu（设计）/ Codex（规格化与落地）
depends_on: [rts-command, squad-upgrade-ownership]
reconstruction_complete: true
---

# 猎手

## 1. 设计意图（Why）

让“突击”成为一段有明确起止的全队进攻姿态：目标存活时获得强机动与减伤，目标结束时立即回到常态，不增加隐藏计时器或冷却。

## 2. 数据定义（What）

| 项 | 值 |
|---|---|
| 稀有度 | CLASSIFIED |
| 作用范围 | 全队 |
| 层数 | 1 |
| 触发 | ASSAULT 命令或双击敌人突击 |
| 持续 | 当前命令目标有效期间 |
| 持续 G | +2G |
| 加速 / 减速 | ×1.2 |
| G 能量损失 | ×0.7 |
| 承受伤害 | ×0.7 |
| 轴进度 | 斗士 +1 |

## 3. 行为与公式（How）

突击入口为全队适用飞机记录同一个有效目标并开启 Hunter。目标被摧毁、释放或命令清除时关闭。技能不设持续秒数和 CD；更换目标会自然把状态绑定到新目标。机动物理通过统一 effective accessor 与预测路径消费相同倍率，伤害在 Aircraft 受击管线乘 0.7。

## 4. 结构与组成（Structure）

- Squad command 与双击突击共用触发入口。
- Aircraft 保存解锁态、运行态和目标生命周期。
- AircraftPhysics 负责 G、加减速与能量损失。
- Aircraft 伤害管线负责减伤。

## 5. 验收标准（Acceptance / Litmus）

- [x] ASSAULT 与双击突击均触发全队 Hunter。
- [x] live physics 与预测 physics 使用同一组倍率。
- [x] 目标结束时立即失效；没有计时器或冷却残留。
- [x] 卡面为 CLASSIFIED，斗士 +1。
- [x] `skill_audit` 通过。

## 6. 实现计划（Task Pipeline）

- [x] 添加技能数据与 i18n。
- [x] 接入两类突击入口和目标生命周期。
- [x] 接入统一物理 accessor 与伤害管线。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| 触发入口 | `scripts/survivor/skill_hooks.gd`、`scripts/survivor/survivor_mode.gd` |
| 物理倍率 | `scripts/aircraft/aircraft_physics.gd` |
| 运行态与伤害 | `scripts/aircraft.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 1 | 用户定稿并完成落地：突击目标生命周期内全队 +2G、加减速 ×1.2、G 损失 ×0.7、承伤 ×0.7。 |
