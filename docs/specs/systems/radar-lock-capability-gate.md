---
id: radar-lock-capability-gate
kind: system
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [qmaam]
reconstruction_complete: true
---

# 雷达对空锁定能力门

## 1. 设计意图

只有真正携带主雷达对空武器的飞机才应画主雷达锥并参与雷达 shooter 的 O(N²) 配对。
纯机炮、火箭、运输和仅对地激光单位既不能消费空中锁定，继续扫描会制造假威胁与无效成本。

## 2. 数据定义

`has_lock_capable_weapon()` 为唯一能力判定：

- 主导弹 `missile != null`：有能力。
- 任一 `railgun` 装备：有能力。
- 任一 `laser` 且 `can_target_aircraft=true`：有能力。
- `secondary_missile` 不计入；它使用独立副槽雷达与独立锥。
- 机炮、火箭、对地激光及无武器：无能力。

## 3. 行为

- hover 主雷达锥仅在能力为真时绘制；光环与副槽锥不受影响。
- 沙盒和生存雷达循环在 shooter 层跳过无能力飞机并清空其 `radar_targets`。
- 被跳过的飞机仍留在全体单位列表中作为 victim；`MountTarget` 规则不变。

## 4. 边界与不变量

- 不删除、过滤或重建 `CombatUnit.all_units`。
- 不改变地面雷达、SAM、MountTarget 或副槽锁定实现。
- 模块化装备发布到 legacy 字段后与旧资源使用同一判定。

## 5. 验收

- 纯机炮 Aircraft 返回 false；主 AAM、railgun、对空 laser 返回 true。
- 对地 laser 返回 false；只有副槽导弹返回 false。
- 无能力 shooter 的旧 `radar_targets` 被清空，但仍可被有能力敌机锁定。

## 6. 实现计划

在 `AircraftParams` 建能力查询；渲染与两套雷达循环共用；增加契约测试。

## 7. 实现锚点

- `scripts/aircraft_params.gd` `has_lock_capable_weapon`
- `scripts/main.gd` / `scripts/survivor/survivor_mode.gd` `_update_radar_locks`
- `scripts/aircraft.gd` `_draw_impl`
- `scripts/tests/test_local_fix_integration.gd` `run`（能力组合断言全绿）
- `zone_support_stress`：45 机样本雷达配对约 17.5→9.8/帧，`radar_locks` 约 14→9µs/帧（与 2026-08-10 同场景基线比较）

## 8. 变更记录

| 日期 | 版本 | 内容 |
|---|---:|---|
| 2026-08-15 | 1 | 从旧分叉移植并按当前 QMAAM 独立副槽契约修订。 |
