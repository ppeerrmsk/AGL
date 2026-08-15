---
id: squad-engagement-persistence
kind: system
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [engagement-discipline, squad-cohesion]
reconstruction_complete: true
---

# 小队交战持续性

## 1. 设计意图

僚机已经接受长机目标或自主选中近敌后，不应因为目标短暂越过自身雷达距离就每 2 秒弃战、
重新入场。对快速盘旋 UAV，这会形成可重复的“接敌—弃战”循环，让机炮和 flank 战术永远
无法闭合。

## 2. 数据定义

- 协同攻击 `_squad_attacking_leader_target=true`：不执行“距目标 > 有效雷达距离×1.5”脱离。
- 自主小队交战 `_squad_free_engaging=true`：同上。
- 小队交战的空间边界仍由 `SQUAD_LEASH_DIST` / `REAR_GUARD_LEASH_DIST` 约束距长机距离。
- 协同攻击仍受 `LEADER_TARGET_LOST_GRACE=1.5s` 约束；长机取消目标后正常回编队。
- BOSS、玩家点名目标及独立 AI 的既有规则不变。

## 3. 行为

进入任一小队交战态时只设置对应语义标志，不创建目标距离宽限计时器。交战帧先处理目标
有效性、长机丢目标和小队 leash；只有非小队交战的独立 AI 才执行雷达距离脱离。

## 4. 边界与不变量

- 不取消小队 leash，避免僚机追敌离长机过远。
- 不把玩家点名目标改成可超时放弃。
- 不改变交战总时长 `engage_duration`。

## 5. 验收

- 小队交战目标位于雷达距离×1.5 之外时，连续推进超过 2 秒仍保持 ENGAGE。
- 独立 AI 在同一距离条件下仍脱离。
- 长机取消协同目标超过 1.5 秒后，僚机仍回编队。

## 6. 实现计划

删除小队距离宽限状态；在统一距离脱离门中显式豁免两种小队交战标志；增加无头契约测试。

## 7. 实现锚点

- `scripts/ai_controller.gd` `is_range_disengage_exempt` / `_process_engage`
- `scripts/ai/target_selection.gd` `disengage`
- `scripts/tests/test_local_fix_integration.gd` `run`（`local_fixes` 24/24；另有 `state_machine` 18/18、`target_sel` 42/42）

## 8. 变更记录

| 日期 | 版本 | 内容 |
|---|---:|---|
| 2026-08-15 | 1 | 从旧分叉提取修复语义，适配当前 main 的 leash 与命令铁律。 |
