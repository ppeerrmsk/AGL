---
id: invasion-algorithm
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: noelu（设计）/ Codex（规格化与落地）
depends_on: [skills-720-rework, early-game-uav-rework]
reconstruction_complete: true
---

# 入侵算法

## 1. 设计意图（Why）

把 JAM build 对无人机的优势从“数值更强”升级为一眼可见的系统接管：干扰命中 MQ-109～112 时立即使其失控坠毁，同时保留正常经验闭环。

## 2. 数据定义（What）

| 项 | 值 |
|---|---|
| 稀有度 | EXPERIMENTAL |
| 作用范围 | 全队唯一 `squad_once` |
| 层数 | 1 |
| 前置 | 任意可施加 JAM 的技能 |
| 有效目标 | MQ-109、MQ-110、MQ-111、MQ-112 系无人机 |
| 效果 | 新施加 JAM 时立即坠毁 |
| 经验 | 按该目标正常击杀经验结算一次 |
| 轴进度 | 策士 +1 |

## 3. 行为与公式（How）

所有玩家小队 JAM 来源在 JAM 成功落地后调用统一钩子。钩子检查目标的无人机标签；命中后以玩家为归因施加足量伤害，沿正常死亡/XP 管线结算。无 JAM 来源时技能不进入候选池。

## 4. 结构与组成（Structure）

技能表声明前置和 squad_once；`SkillHooks.on_player_jam_landed` 汇合各 JAM 来源并处理无人机处决；既有 spawner/死亡管线负责 XP。

## 5. 验收标准（Acceptance / Litmus）

- [x] 任一玩家小队 JAM 来源均可触发。
- [x] MQ-109～112 立即坠毁并只结算一次正常 XP。
- [x] 普通载人机、王牌和 BOSS 不受处决效果。
- [x] 无 JAM 来源时不进入升级候选池。
- [x] `skill_audit` 通过。

## 6. 实现计划（Task Pipeline）

- [x] 添加技能数据、前置、i18n 与策士进度。
- [x] 汇合 JAM 落地钩子并接正常击杀归因。
- [x] 添加技能审计覆盖。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| JAM 落地与处决 | `scripts/survivor/skill_hooks.gd` |
| 经验结算 | `scripts/survivor/survivor_spawner.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 1 | 用户定稿并完成落地：JAM 令 MQ-109～112 立即坠毁并正常结算 XP。 |
