---
id: cloud-skill-consistency
kind: system
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [bloodlust, weather-clouds-and-sandstorm]
reconstruction_complete: true
---

# 云中技能一致性

## 1. 设计意图

“云中超载”必须像其它 OVERLOAD 来源一样经过 `apply_status`，才能触发持续时间与嗜血联动；
“云中武器冷却”不能在进出云边界乘除运行中倒计时，否则云内新生成的 CD 和拾取时已在云中
都会产生错配。

## 2. 数据定义

- 云中判定：`cloud_state >= 1`，与既有技能口径一致。
- 天气采样：每 0.2 秒。
- 云中超载基础刷新时长：1.0 秒，`mode="max"`。
- 出云不主动清除 OVERLOAD；timer 自然衰减，避免误删规避/击杀来源。
- 持续时间倍率与固定加时先由 `Aircraft.apply_status` 结算，再以同一最终时长联动 BLOODLUST。
- 云中武器 CD 倍率并入 `cd_rate("weapon")`。

## 3. 行为

每次有效天气采样若玩家小队在云中且技能启用，刷新一次 OVERLOAD。武器、导弹、火箭和副槽
的倒计时按当前云状态读取 CD rate；进出云不修改倒计时数值。

## 4. 边界与不变量

- 无天气节点时状态回晴，既有短时 OVERLOAD 自然结束。
- 刷新频率沿用天气采样，不新增每帧天气查询。
- 状态 UI 从 timed 字典读取，不需要派生常驻 OVERLOAD 标志。

## 5. 验收

- 云中超载会触发 overload-to-bloodlust；出云不会清除其它来源剩余时长。
- 云内新生成的武器 CD 立即按倍率消耗；反复进出云不产生乘除漂移。
- 拾取技能时已经在云中会立即获得一次超载刷新。

## 6. 实现计划

移除 `_in_cloud_overload` 与云边界倒计时缩放；接入统一状态入口与 CD rate；增加测试。

## 7. 实现锚点

- `scripts/status_effects.gd` `CLOUD_OVERLOAD_BASE_DURATION`
- `scripts/aircraft.gd` `cd_rate` / `apply_status` / `_update_cloud_state`
- `scripts/aircraft/aircraft_weapons.gd` `update_gun` / `update_rocket` / `update_missile` / `update_secondary_missile`
- `scripts/tests/test_local_fix_integration.gd` `run` 与 `weather`（37 项）全绿

## 8. 变更记录

| 日期 | 版本 | 内容 |
|---|---:|---|
| 2026-08-15 | 1 | 合并云技能修复，并与当前天气采样和修改器管线统一。 |
