# 更新日志 — 2026-04-28（commit 2）

## 装备模块化 commit 2/13 — GunEquipment 包装器（零行为变化）

继 commit 1 的脚手架后，本 commit 加入第一个具体装备子类 `GunEquipment`，
并在 Aircraft 中布置"装备发布到传统字段"的兼容层。所有现存飞机的 `params.equipment`
数组仍然为空，因此**行为完全等价**。

## 本 commit 内容

### 新增 `scripts/equipment/gun_equipment.gd`

机炮配置包装器：

| 字段/方法 | 说明 |
|---|---|
| `gun: GunParams` | 持有原 GunParams 资源引用（damage / fire_rate / max_ammo 等都不动） |
| `_init` | 设 `equipment_kind = "gun"` |
| `desired_engagement(s)` | 给 commit 8 的 TacticalPlanner 用：返回 CLOSE_TAIL preference @ max_range×0.5, priority=0.6 |
| `ammo_ratio(ac)` / `cooldown_ratio(ac)` | UI / debug 用 |

注意：装备本身**无运行时状态**。弹药 / 冷却 / fire 状态仍住在 `Aircraft`
（`_fire_cooldown / ammo / is_firing / _gun_reload_active` 等），由
`AircraftWeapons.update_gun` 直接读写。装备只是配置容器 + planner 投票接口。

### 修改 `scripts/aircraft.gd`

`_ready` 中新增 `_publish_equipment_to_legacy()` 调用，负责把 `params.equipment`
里的装备配置同步发布到对应的传统字段（本 commit 实现 gun，commits 3-7 扩展 missile/rocket/ciws/flare）：

```gdscript
func _publish_equipment_to_legacy() -> void:
    var gun_eq := params.get_equipment_of_kind("gun") as GunEquipment
    if gun_eq != null and gun_eq.gun != null:
        params.gun = gun_eq.gun
```

这是**迁移期兼容层**，让 25 处现存的 `params.gun` 读取（aircraft_renderer / survivor_hud /
debug_panel / situation / bfm_tactics / aircraft_weapons / aircraft_combat_tracking）
**无需任何修改**就能继续工作。

迁移逻辑：
- 老飞机（`equipment` 空 + `params.gun` 已设）→ `gun_eq` 为 null → no-op → 走老路径
- 新飞机（`equipment` 含 `GunEquipment` + `params.gun` 留空）→ publish 把
  `gun_eq.gun` 写进 `params.gun` → 老路径透明工作
- 新飞机（无 GunEquipment 也无 `params.gun`，例 X-02）→ `params.gun` 保持 null
  → `update_gun` 早返回 → 不射击（正确）

`AircraftParams` 在所有刷怪 / 玩家初始化路径都走 `duplicate(true)` 深拷贝
（验证位置：`main.gd:325/385`、`survivor_mode.gd:162/347`、`survivor_spawner.gd:1110`），
所以 publish 修改 params.gun 不会污染共享资源。

## 验证

跑生存模式 5 分钟（玩家 F-16 + 起始僚机 vs 多波敌人）+ 沙盒 F1 友方编队 vs F2 敌方编队，
确认：
- FPS 无波动
- 击杀率正常
- 机炮射击 / 弹药消耗 / 装填动画都和 commit 1 前完全一致
- 因为没有任何 .tres 设过 `equipment` 数组，新代码路径 100% 是 dead code

## 后续 commit 提示

- **commit 3**：RocketEquipment（齐射 / 散布 / 装填）
- **commit 4**：CIWSEquipment（naval 用）
- **commit 5**：MissileEquipment（含 multi_lock_salvo / BVR / fire_and_forget）—— 这是最复杂的一步
- **commit 6**：FlareEquipment（含 jam_chance / fail_chance / 多波 reload）
- **commit 7**：CobraEvasion / HerbstEvasion（包 Node 子节点）

每一步都是同一模式：新建 `XEquipment` 子类 + 在 `_publish_equipment_to_legacy`
追加一个 `params.x = x_eq.x` 分支。直到 commit 8 才会让 TacticalPlanner 真正读 equipment 数组。
