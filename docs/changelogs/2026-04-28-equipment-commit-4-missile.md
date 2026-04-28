# 更新日志 — 2026-04-28（commit 4）

## 装备模块化 commit 4/13 — MissileEquipment 包装器（零行为变化）

第四次装备迁移。导弹比前几个稍复杂——主/副双槽（空对空 / 空对地）。

## CIWS 跳过说明

原 13 commit 计划里 commit 4 是 `CIWSEquipment`。重新审视后**跳过 CIWS 不再单独包装**：

- **Aircraft 的 CIWS** 是生存模式技能升级（`gun_ciws_active` flag），**复用 GunParams** 的射程/锥角/弹丸参数，没有独立 `CIWSParams` 资源可包装。CIWS 行为由 GunEquipment 已隐式覆盖
- **Naval 的 CIWS** 走 `WeaponMount` + `WeaponMountParams` 系统（`weapon_type: WeaponType.CIWS`），是 NavalUnit 的子节点，不在 `AircraftParams.equipment` 抽象范围内。把它统一进 EquipmentParams 是更大的重构（要把 NavalUnit 也接入 equipment 模型），不在当前 13 commit 计划里

总 commit 数从 13 → 12，原 commit 5/6/7 各前移一位。

## 本 commit 内容

### 新增 `scripts/equipment/missile_equipment.gd`

```
@export var missile: MissileParams
@export var is_secondary: bool = false   # false=主导弹A2A, true=副导弹A2G
```

`equipment_kind = "missile"` 永远，主/副槽通过 `is_secondary` 字段区分。

`desired_engagement` 给 commit 8 planner 投票：
- 主导弹（A2A）：`LEAD_PURSUIT @ max_range_rear×0.6, priority=0.7`（高于机炮 0.6）
- 副导弹（A2G）：返回 null，对地有独立的 `update_combat_ground_attack` 状态机
- 自主制导（fire_and_forget）→ `needs_lock=false / needs_los=false`，allow planner crank without losing guidance

### 修改 `scripts/aircraft.gd`

`_publish_equipment_to_legacy` 用迭代而非 `get_equipment_of_kind`（因为双槽）：

```gdscript
for eq in params.equipment:
    if eq is MissileEquipment:
        var me: MissileEquipment = eq
        if me.missile == null:
            continue
        if me.is_secondary:
            params.secondary_missile = me.missile
        else:
            params.missile = me.missile
```

### 兼容覆盖

- 24 处 `params.missile` 读取（aircraft_weapons / aircraft_combat_tracking / situation /
  ai_controller / debug_panel / survivor_hud）→ 透明工作
- 9 处 `params.secondary_missile` 读取（debug_panel / aircraft_combat_tracking /
  aircraft_weapons）→ 透明工作

`has_equipment_of_kind("missile")` 对主/副两槽都返回 true（因为 equipment_kind 共用）。
未来如需"只主导弹升级"或"只副导弹升级"过滤，可加 `has_equipment_with_slot` 接口。

## 验证

跑生存模式 5 分钟（含主导弹空战 + 路过 SAM/AAA 时副导弹对地）+ 沙盒 F1 vs F2 编队
30 秒，确认：
- BVR 锁定 + 发射 + multi_lock_salvo 齐射全部正常
- 副导弹对地攻击（F-16 / F-14 装的 secondary_missile）正常
- 玩家 fire_and_forget 导弹（F-14 AIM-120/254）发射后不丢制导
- AIM-7M（半主动）launch quality filter 仍能避开急转/边缘锥发射
- 飞行员 _has_stable_launch_window 检查路径无变化

## 累计进度

```
[完成] commit 1  脚手架
[完成] commit 2  GunEquipment
[完成] commit 3  RocketEquipment
[跳过] commit 4  CIWSEquipment（aircraft 复用 GunParams + naval 走 WeaponMount，无独立 CIWSParams）
[完成] commit 4  MissileEquipment（主+副双槽）
        commit 5  FlareEquipment
        commit 6  CobraEvasion / HerbstEvasion
        commit 7  TacticalPlanner 投票模型
        commit 8  老路径删除
        commit 8' 升级过滤
        commit 9  RailgunEquipment
        commit 9' LaserEquipment
        commit 10' X-02 主角
        commit 10'' 敌人版 + AF-03 + 激光 UAV
        commit 11  阶段清理
```
