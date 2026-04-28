# 更新日志 — 2026-04-28（commit 8）

## 装备模块化 commit 8/13 — RailgunEquipment（电磁炮，第一个全新机制装备）

前 7 个 commit 都是**包装**现有武器，行为零变化。**本 commit 引入第一种全新武器**——
电磁炮，自带 telegraph 充能 + hitscan 即时命中 + 穿透 + 闪电视觉的完整机制。

## 核心机制

### Telegraph 充能（扇形收缩警告）

进入开火意图 → 攻击者机头出发，向充能目标方向画扇形，从初始 30° 半角线性收缩为 0°，
耗时 `charge_duration`（玩家 1.2s / 敌人 2.5s）。扇形仅在目标在射程内 + 弹道可达时渲染。

### 弹道锁定时机（双版本核心区别）

```
enum LockTrajectory {
    AT_CHARGE_START,  ## 敌人版：扇形开始就锁死位置 → 玩家可机动躲掉
    AT_FIRE_TIME,     ## 玩家版：开火瞬间才锁定 → 基本必中
}
```

**敌人版（AF-03）使用 AT_CHARGE_START**：玩家看到扇形出现立即知道弹道已定 →
2.5s 内任意机动都能躲掉，唯独直线匀速飞行会吃满。

**玩家版（X-02）使用 AT_FIRE_TIME**：充能结束的瞬间锁定预测点 → 命中率极高。仅极速目标
（`>fast_target_miss_speed_kmh`，默认 1500 km/h）有少量散布概率。

### Hitscan + 闪电视觉

- `is_hitscan = true`：发射瞬间命中，不模拟弹丸飞行
- `BEAM_FADE_DURATION = 0.25s`：视觉淡出 0.25 秒
- 线条：粗白心 + 外彩光 + 4 段 jitter 闪电抖动
- 颜色：友方蓝白 (`Color(0.7, 0.95, 1.0)`)，敌方红 (`Color(1.0, 0.5, 0.4)`)

### 穿透命中

弹道路径上**所有** CombatUnit / Missile 都受伤（`HIT_RADIUS_PX = 25`，~50m 光束直径）。
战术后果：
- 玩家电磁炮可一击多杀（敌方紧密编队遭殃）
- 敌方电磁炮：玩家的僚机如果在身后会被一起穿（玩家需注意编队站位）
- **导弹被命中直接 queue_free**：电磁炮可拦截敌方导弹（动能 vs 物理弹丸克制）

## 架构

### Aircraft 状态字典（commit 8 起）

```gdscript
# scripts/aircraft.gd
var equipment_state: Dictionary = {}  # 每件装备用 equipment_kind 作 key

# RailgunEquipment.update 写入：
ac.equipment_state["railgun"] = {
    "cooldown": 0.0,
    "charging": false,
    "charge_progress": 0.0,
    "charge_target": <target_unit>,
    "locked_aim_pos": Vector2,
    "beam_start": Vector2,
    "beam_end": Vector2,
    "beam_fade": 0.0,
}
```

避免给 Aircraft 加 5+ 个 `_railgun_*` 字段污染主类。

### Aircraft._update_equipment(delta)

每帧驱动 `params.equipment` 数组每件的 `update(self, delta)`。老装备（GunEquipment/
RocketEquipment 等）的 `update` 是 base no-op；新装备（RailgunEquipment / 即将的
LaserEquipment）实装完整逻辑。

调用点在 `_physics_process` 顶层（所有 LOD 都跑），cost 极小（22 单位 × 60Hz）。

### AircraftRenderer.draw_railgun_telegraph + draw_railgun_beam

两个新静态方法，从 `ac.equipment_state["railgun"]` 读状态：
- telegraph：三角扇形 polygon + 边框，颜色随充能进度逐渐变亮
- beam：主光束粗白心 + 外彩边 + 4 段 jitter 闪电

### Aircraft._draw 集成

```
draw_target_line → draw_cloud_state → draw_railgun_telegraph → draw_aircraft_icon
                                                    ^ 扇形画在飞机图标下方

draw_muzzle_flash → draw_railgun_beam → ...
                          ^ 闪电画在飞机图标上方（视觉冲击）
```

## 没有 .tres / 没有飞机使用

本 commit 只提供机制，不创建任何使用电磁炮的飞机或资源。X-02（commit 10）和 AF-03
（commit 11）会创建对应的 .tres 并装上。

## 验证

跑生存模式确认：
- 老飞机的所有武器表现完全一致（GunEquipment/MissileEquipment/etc 的 update 是 no-op）
- 无 parse error
- FPS 无回归（railgun update 对没装备的飞机早 return）

正式测试要等 commit 10 X-02 出来才能玩。

## 累计进度

```
[完成] commit 1-7  装备包装 + 升级过滤
[完成] commit 8    RailgunEquipment 全新机制
        commit 9   LaserEquipment（360°DoT + 过热 + 云削弱）
        commit 10  X-02 主角
        commit 11  AF-03 + 激光 UAV
        commit 12  TacticalPlanner 投票（视精力情况）
```
