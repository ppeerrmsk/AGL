# 更新日志 — 2026-04-28（commit 7）

## 装备模块化 commit 7/13 — 升级过滤接入 has_equipment_of_kind

把 `SurvivorData.is_upgrade_available_for` 的硬件检测从硬编码 4 种字段
（gun/missile/flare/rocket）改成走 `AircraftParams.has_equipment_of_kind`。

## 改动

`scripts/survivor/survivor_data.gd:461-491`：

```gdscript
# 原来的 12 行 match：
match str(req):
    "gun":
        if p == null or p.gun == null:
            return false
    ...

# 改成 2 行：
if p == null or not p.has_equipment_of_kind(str(req)):
    return false
```

## 收益

1. **未来 X-02 玩家选择时，升级池自动过滤**：X-02 没有 gun/missile/flare/rocket，
   所有标了 `requires: ["gun"]` 等的升级（约 18 条机炮升级 + 7 条导弹升级 +
   2 条火箭弹 + 2 条热诱弹）都不会出现在 X-02 的抽取池里
2. **新装备类型零代码注册**：未来加 `requires: ["railgun"]` / `["laser"]` /
   `["cobra"]` 直接生效，不需改 `is_upgrade_available_for`
3. **现有 .tres 0 行修改**：所有传统 .tres（用 `params.gun = ...` 字段）继续工作，
   因为 `has_equipment_of_kind` 双查 equipment 数组 + 老字段

## 验证

跑生存模式：玩家 F-16 选满 5 级，确认升级池组成与 commit 6 前完全一致
（gun/missile/flare/rocket 升级正常出现）。

UPGRADES 表现存的 `requires` 标注已经是正确的（commit 1 前就有），不需要重审。
未来加新装备的升级时，按"装备能用什么升级"语义填 `requires` 字段即可。

## 累计进度

```
[完成] commit 1-6  装备类全部到位
[完成] commit 7    升级过滤接入 has_equipment_of_kind
        commit 8   RailgunEquipment（电磁炮：telegraph + hitscan + 闪电视觉）
        commit 9   LaserEquipment（激光：360°DoT + 过热 + 云削弱）
        commit 10  X-02 主角飞机
        commit 11  AF-03 + 激光 UAV
        commit 12  TacticalPlanner 投票模型 + 老路径删除（最后做，因为 publish-to-legacy
                  已经覆盖大部分需求；commit 12 主要是让 AI 在新装备上做更优决策）
```

## 路线调整说明

原计划 commit 7 是 TacticalPlanner 投票模型重构（高风险大改）。重新评估后发现：
publish-to-legacy 兼容层 + Aircraft._physics_process 加 equipment.update() 循环
（在 commit 8 RailgunEquipment 加入），已经能让 X-02 / AF-03 / 激光 UAV 全部
**功能性可玩**——区别只是 AI 用旧 BFM 决策树而非投票模型。

所以投票模型挪到最后（commit 12），优先把新机制 + 新机/新敌人做出来看到效果。
