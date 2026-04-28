# 更新日志 — 2026-04-28

## 装备模块化重构 — Commit 1：脚手架（零行为变化）

启动一项跨 13 个 commit 的大重构：把 Aircraft 的"机炮 / 导弹 / 火箭弹 / 热诱弹"四类硬编码槽位抽象成统一的 `EquipmentParams` 装备列表。目标是支持**新主角 X-02**（电磁炮 + 360° 激光，无传统枪炮导弹）和**新敌人 AF-03 / 激光 UAV**，同时让生存模式升级池能根据"装了什么装备"过滤——没装机炮就不出机炮升级。

完整设计讨论见对话记录（设计阶段已锁定 13 个 commit 的提交计划）。本 commit 只放脚手架，不改任何已有行为。

## 本 commit 内容

### 新增 `scripts/equipment/`

三个基类，全部空虚方法，只定义接口契约：

| 文件 | 职责 |
|---|---|
| `equipment_params.gd` | 装备基类 `EquipmentParams extends Resource`。字段 `equipment_kind: String`（"gun"/"missile"/"railgun"/"laser"/"flare"/"cobra"/"herbst"/...）；虚方法 `can_fire / desired_engagement / fire / update / ammo_ratio / cooldown_ratio` |
| `engagement_preference.gd` | 投票值类型 `EngagementPreference extends RefCounted`。给 `TacticalPlanner` 收集装备投票时用 — 字段 `preferred_range_m / preferred_intent / needs_lock / needs_los / priority / preferred_speed_kmh / prefers_afterburner / rationale` |
| `evasion_module.gd` | 规避模块基类 `EvasionModule extends EquipmentParams`。增 `should_trigger / execute_evasion` 虚方法 |

### 修改 `aircraft_params.gd`

- 新增 `@export var equipment: Array[EquipmentParams] = []`
- 新增 `has_equipment_of_kind(kind: String) -> bool`：先查新数组，再 fallback 查旧字段（gun/missile/secondary_missile/rocket/flare），保证迁移期两条路径都能用
- 新增 `get_equipment_of_kind(kind) -> EquipmentParams`：取首件
- **旧字段（gun/rocket/missile/secondary_missile/flare/combat）一行未动**，所有现存 .tres 完全兼容

## 后续 commit 路线图

```
[完成] Commit 1  脚手架 + AircraftParams.equipment + has_equipment_of_kind
        Commit 2  GunEquipment 子类 + aircraft_weapons.gd 老路径加守卫
        Commit 3  RocketEquipment
        Commit 4  CIWSEquipment
        Commit 5  MissileEquipment（含 multi_lock_salvo / BVR）
        Commit 6  FlareEquipment（含 jam_chance / fail_chance / 多波 reload）
        Commit 7  CobraEvasion / HerbstEvasion（包 Node 子节点）
        Commit 8  TacticalPlanner 投票模型 + USE_EQUIPMENT_VOTING 主开关
        Commit 9  老路径删除（验证期后）
        Commit 9' 升级过滤：UPGRADES 加 requires_equipment_kind + 现有表全审
        Commit 10  RailgunEquipment（hitscan + 闪电视觉 + 穿透 + telegraph 收缩扇形）
        Commit 10' LaserEquipment（DoT + 360° + 过热 + 云层削弱 + target_filter）
        Commit 11' X-02 主角 + 玩家版 .tres + survivor_select 第 3 槽接入
        Commit 11'' 敌人版 .tres + pilot_personality 误差集成
        Commit 11''a AF-03 敌人（Schemer with combat，纯电磁炮远程狙击）
        Commit 11''b 激光 UAV（Sentinel 永久带 2 架，纯导弹拦截器）
        Commit 12 阶段清理（删 aircraft_weapons.gd / aircraft_flares.gd / WeaponMode 枚举）
```

## 验证

- 跑生存模式 5 分钟，确认 FPS / 击杀率 / EventLogger 无回归 — 因为没有任何代码读 `equipment` 数组，旧字段也未动，行为应完全等价
- Godot 4.6+ 打开 `project.godot` 编辑器加载 .tres 不应报警告（新 `equipment` 数组默认为空）

## 关键设计决策

1. **单一装备数组（武器 + 规避同住）** — `EvasionModule` 继承 `EquipmentParams`，所有装备扔进同一个 `equipment` 数组。简化 Aircraft 的字段和 .tres 编辑流程
2. **`equipment_kind: String` 而非 enum** — 字符串 kind 让新装备类型零代码注册（设计师建 .tres 填字符串即可），生存模式升级表的 `requires_equipment_kind` 也是字符串配对，避免每加一种装备就改 enum
3. **迁移期双查 has_equipment_of_kind** — 新数组优先、旧字段 fallback。这是 commit 9' 升级过滤能在 commit 2-7 完成前就先用的关键
4. **旧字段保留到 commit 12** — 给每一步迁移留 grace period，发现问题可以单步回滚而不破坏其他装备类型
