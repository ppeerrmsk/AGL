# 更新日志 — 2026-04-28（commit 3）

## 装备模块化 commit 3/13 — RocketEquipment 包装器（零行为变化）

继续装备迁移。火箭弹比机炮简单 —— 只有 4 处 `params.rocket` 读取，全在
`aircraft_weapons.gd`，pattern 与 commit 2 GunEquipment 完全相同。

## 本 commit 内容

### 新增 `scripts/equipment/rocket_equipment.gd`

火箭弹配置包装器：
- `rocket: RocketParams` 引用
- `equipment_kind = "rocket"`
- `desired_engagement(s)` 返回 `EngagementPreference(intent=TAIL_CHASE, range=(min+max_fire)/2, priority=0.4)`
  - `priority = 0.4` 比机炮（0.6）低，因为火箭弹通常是副武器，机炮该优先 vote
- `ammo_ratio` / `cooldown_ratio` 状态查询

### 修改 `scripts/aircraft.gd`

`_publish_equipment_to_legacy` 追加 rocket 分支：

```gdscript
var rocket_eq := params.get_equipment_of_kind("rocket") as RocketEquipment
if rocket_eq != null and rocket_eq.rocket != null:
    params.rocket = rocket_eq.rocket
```

迁移期 publish 逻辑与 gun 完全对称，所有现存 `params.rocket` 读取无需修改。

## 验证

跑生存模式（碰到 F-86 / A-7 / Q-5 时观察其火箭弹齐射）+ 沙盒 F1 友方 vs F2 敌方
30 秒，确认火箭弹发射 / 齐射间隔 / 弹药消耗 / 大散布弹道都和 commit 2 前完全一致。

## 累计进度

```
[完成] commit 1  脚手架（EquipmentParams / EngagementPreference / EvasionModule）
[完成] commit 2  GunEquipment + Aircraft._publish_equipment_to_legacy 兼容层
[完成] commit 3  RocketEquipment
        commit 4  CIWSEquipment（naval 用）
        commit 5  MissileEquipment（含 multi_lock_salvo / BVR / fire_and_forget）
        commit 6  FlareEquipment
        commit 7  CobraEvasion / HerbstEvasion
        commit 8  TacticalPlanner 投票模型
        commit 9  老路径删除
        commit 9'  升级过滤
        commit 10  RailgunEquipment
        commit 10' LaserEquipment
        commit 11' X-02 主角
        commit 11'' 敌人版 + AF-03 + 激光 UAV
        commit 12  阶段清理
```
