---
id: esm-pod
kind: weapon
status: done
schema_version: 1
spec_version: 2
owner: noelu（设计）/ Codex（规格化与落地）
depends_on: [zone-reward-arsenal, radar-system]
reconstruction_complete: true
---

# ESM 吊舱

## 1. 设计意图（Why）

ESM 是战区奖励中的团队节奏装备：不直接造成伤害，而是用与 Sentinel 相同大小的数据链范围，让编队更快完成锁定与装填。范围圈与锁定/装填变化必须能被玩家感知。

## 2. 数据定义（What）

| 项 | 值 |
|---|---:|
| 光环半径 | 3000m（1500px） |
| 扫描间隔 | 0.5s |
| 状态有效期 | 0.75s，每次扫描刷新 |
| 友军锁定速率 | ×1.5 |
| 机炮装填时间 | ×0.7 |
| 导弹装填时间 | ×0.7 |
| 热诱弹装填时间 | ×0.7 |
| 获取 | 战区武器奖励，整局唯一 |

“CD”在本装备中只指 reload/装填时间缩短，不改变机炮梭内射击间隔。

## 3. 行为与公式（How）

装备每 0.5 秒扫描 `CombatUnit.all_units`，对半径内非敌对 Aircraft 写入带过期时间的 ESM meta。各锁定、武器和热诱弹消费点读取 meta；离开范围后最多 0.75 秒失效。其它 reload 倍率与 ESM 相乘，不相互覆盖。

## 4. 结构与组成（Structure）

- 一个 `EquipmentParams` 资源和对应更新脚本。
- Aircraft 提供 ESM 锁定/装填倍率 accessor。
- 雷达、机炮、导弹、热诱弹分别在既有计时管线消费倍率。
- AircraftRenderer 只为装备持有者绘制 3000m 范围圈。

## 5. 验收标准（Acceptance / Litmus）

- [x] 范围精确等于 Sentinel 1500px 光环。
- [x] 圈内锁定速率 ×1.5，三类 reload 时间 ×0.7；离圈后恢复。
- [x] 低血热诱弹等其它倍率与 ESM 相乘。
- [x] 扫描频率 2Hz，使用共享单位列表且先校验实例有效性。
- [x] `zone_rewards` 与 `skill_audit` 通过。
- [x] F4 装备区可直接挂载/卸载 ESM；F6 可直接发放 ESM 奖励。
- [x] Sentinel + Lv5+ 最低 60 FPS。

## 6. 实现计划（Task Pipeline）

- [x] 新增 ESM 资源与更新脚本。
- [x] 接入战区奖励、持有过滤与 i18n。
- [x] 接入锁定、机炮、导弹、热诱弹消费点与范围可视化。
- [x] `zone_support_stress` 20 秒：Lv8 / 49 架存活飞机，末秒 145 FPS；样本显式装备 ESM。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 装备行为 | `scripts/equipment/esm_pod_equipment.gd` |
| 装备资源 | `resources/esm_pod.tres` |
| 倍率 accessor | `scripts/aircraft.gd` |
| 奖励接入 | `scripts/survivor/zone_data.gd`、`scripts/survivor/survivor_mode.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 2 | 补齐 F4 装载与 F6 奖励直发入口，并纳入 Debug 覆盖审计。 |
| 2026-08-04 | 1 | 用户定稿并完成落地：3000m、锁定 ×1.5、reload ×0.7、0.5s 扫描。 |
