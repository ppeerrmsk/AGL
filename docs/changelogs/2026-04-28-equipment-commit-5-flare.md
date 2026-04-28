# 更新日志 — 2026-04-28（commit 5）

## 装备模块化 commit 5/13 — FlareEquipment（第一个 EvasionModule 子类）

第五次装备迁移。**第一个 EvasionModule 子类**——给后续的 CobraEvasion / HerbstEvasion
立 pattern。

## 本 commit 内容

### 新增 `scripts/equipment/flare_equipment.gd`

```gdscript
class_name FlareEquipment extends EvasionModule
@export var flare: FlareParams
func _init(): equipment_kind = "flare"
```

`should_trigger` / `execute_evasion` **暂留 EvasionModule 基类的 no-op**：

- 实际触发判定仍由 `AircraftFlares.update` 自己跑（每帧扫来袭导弹 → calc_jam_chance →
  decide_release）。这个逻辑很成熟（多年迭代），不动它。
- 等 commit 7（TacticalPlanner 投票模型）上线后，把 `should_trigger` 实装为
  "返回 calc_jam_chance × confidence"，`execute_evasion` 调 `AircraftFlares.release`。
  那时 cobra/herbst 也走同一套规避投票，三选一。

### 修改 `scripts/aircraft.gd`

`_publish_equipment_to_legacy` 追加 flare 分支（同 gun/rocket 的 `get_equipment_of_kind`
单槽模式，因为热诱弹只有一个槽位）：

```gdscript
var flare_eq := params.get_equipment_of_kind("flare") as FlareEquipment
if flare_eq != null and flare_eq.flare != null:
    params.flare = flare_eq.flare
```

### 兼容覆盖

41 处 `params.flare` 读取（aircraft_flares / aircraft_renderer / 各种 enemy spawn）→ 透明工作。

## 验证

跑生存模式遭遇带导弹的 MiG-29 / MiG-31 —— 玩家被锁定 → 释放热诱弹 → 导弹被 jam。
另测玩家被多枚导弹连续锁定时的多波 reload + cooldown 行为。F-47 BOSS 用 40 枚电子战
flare 也应正常。

## 累计进度

```
[完成] commit 1  脚手架
[完成] commit 2  GunEquipment
[完成] commit 3  RocketEquipment
[跳过] commit 4  CIWSEquipment
[完成] commit 4  MissileEquipment
[完成] commit 5  FlareEquipment（第一个 EvasionModule 子类）
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
