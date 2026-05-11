# 2026-05-10 — 副导弹槽位复活 + 首把样本武器 QMAAM

## 背景

`AircraftParams.secondary_missile` 在 2026-04-29 被合并掉了底层 dispatch（"统一导弹...避免低层 AAM/AGM 双轨制带来的同步、装填、选择路径复杂度"），但**字段定义 / 弹药计数 / F4 切换 UI / 6 架敌机 .tres 配置都还在**——半冬眠状态。

现在为了支持"特殊触发即死武器"（玩家局外讨论确定的方向：拦截弹 / 温压弹 / 自爆无人机 / 格斗弹 等），需要一个**独立装填、独立计数、独立 cooldown、不污染主 MSL 池**的接口。secondary_missile 槽位天然就是为这类东西预留——只是被合并掉了，需要复活。

## 设计正名

> 游戏里 **MSL** 特指主槽（`params.missile`，常规 AAM）。`secondary_missile` 是开发代号——它是一个**通用特殊武器槽**（玩家面叫 **SP**），未来挂载内容差异极大。**完全独立于 MSL**。

副槽**不是** missile 子类，而是飞机的第二套独立武器子系统。复用 MissileParams 资源结构只是工程方便，但锁定 / 发射 / UI / 升级路径都和 MSL 完全平行。

## 改动一览

### 数据层

- **[scripts/missile_params.gd](../../scripts/missile_params.gd)**：加 `target_filter` 位域 const（AIR/GROUND/SHIP/MISSILE）+ `target_priority` 策略 const（CLOSEST/DOGFIGHT_SIDE）+ 4 个 export 字段（`target_filter` / `lock_cone_half_angle_deg` / `lock_max_range_px` / `target_priority`）。默认值保证主 MSL 槽零行为变化。

- **[scripts/aircraft.gd](../../scripts/aircraft.gd)**：加 6 个副槽字段（`secondary_missile_enabled` / `secondary_radar_targets` / `secondary_combat_target` / `_secondary_cooldown` / `_secondary_reload_active` / `_secondary_reload_timer` / `_secondary_radar_tick_acc`）。`_physics_process` 在 LOD 0 / LOD 1 / LOD 2 三档都挂入 `update_secondary_radar` + `update_secondary_missile` 调用。

### 调度层

- **[scripts/aircraft/aircraft_weapons.gd](../../scripts/aircraft/aircraft_weapons.gd)**：新增完整副槽子系统（~155 行）：
  - `update_secondary_radar(ac, delta)` — 0.5s tick 节流，扫 `BulletManager.combat_unit_list`，按 `target_filter` 过滤累积到 `secondary_radar_targets`。JAM 期间冻结（与主雷达对称）。
  - `update_secondary_missile(ac, delta)` — 独立 cooldown / 装填 / 自动开火。
  - `_pick_secondary_target` 分发器 + `_pick_dogfight_side`（QMAAM 专属）+ `_pick_closest_locked`（默认）+ `_is_valid_secondary_candidate` 共享前置。
  - 修改 `_fire_missile_at`：`is_secondary=true` 时**不**写共享 `_missile_cooldown` / `_crank_timer` / 主弹装填触发——副槽 cooldown / reload 全在 `update_secondary_missile` 自管。

### 玩家初始化

- **[scripts/survivor/survivor_playable_setup.gd](../../scripts/survivor/survivor_playable_setup.gd)**：撤回原"清掉 secondary_missile"的硬编码，改为开启 `aircraft.secondary_missile_enabled = true` + 按 `params.secondary_missile` 是否非空初始化 `secondary_missiles_remaining`。

### UI

- **[scripts/survivor/survivor_hud.gd](../../scripts/survivor/survivor_hud.gd)**：MSL 行下方加条件 SP 行（仅 `params.secondary_missile != null` 时显示），用武器自身 `display_name`，独立显示装填 / cooldown / 弹药状态。

- **[scripts/aircraft_renderer.gd](../../scripts/aircraft_renderer.gd)** + **[scripts/aircraft.gd](../../scripts/aircraft.gd) `_draw`**：新增 `draw_secondary_lock_cone(ac)`，仅 `AircraftRenderer.player_ref == self` 时绘制橙色 70° 半透明扇形（vs 主雷达蓝色锥）。装填中褪色至 0.10 alpha，弹尽不画。

- **[scripts/survivor/survivor_debug_skills.gd](../../scripts/survivor/survivor_debug_skills.gd)**：F4 装载面板"副导弹"重命名为"副武器槽 (SP)"+ 加 QMAAM 选项。切换处理同步重置副槽 runtime 状态（cooldown / reload / 锁定累积全清）。

### JAM 一致性补丁

- **[scripts/main.gd](../../scripts/main.gd) `_update_radar_locks`**：补上 `if unit.status_jam_active: unit.radar_targets.clear(); continue`（与 [survivor_mode.gd:1417-1420](../../scripts/survivor/survivor_mode.gd) 已有的逻辑对称）。沙盒模式之前 JAM 不阻断 lock 累积是 bug；现在主雷达 / 副雷达 / 武器发射三处对 JAM 的反应统一。

### 资源

- **新建 [resources/qmaam_missile.tres](../../resources/qmaam_missile.tres)** — Quick Maneuver Air-to-Air Missile：
  - target_filter = AIR / target_priority = DOGFIGHT_SIDE
  - lock_cone_half_angle_deg = 70°（vs 主雷达 30-45°）
  - lock_max_range_px = 1500（≈ 3km 近距）
  - max_g = 60 / nav_constant = 5 / seeker_fov = 100°（极强机动 + 大 off-boresight）
  - max_count = 1 / cooldown = 8.0（单发即转 reload，"救命武器稀缺资源"）
  - damage = 70 / fire_and_forget = true

## 设计纪律

| 维度 | 决策 | 落实位置 |
|---|---|---|
| MSL 升级不流入副槽 | 武器靠自己 .tres 数值定身份 | [survivor_player.gd](../../scripts/survivor/survivor_player.gd) 的 missile_count / tracking / swarm / seeker_fov / boost 5 处只动 `p.missile`，不动 `p.secondary_missile` |
| `lock_time` 自动流入副槽 | 飞机层共享 | `update_secondary_radar` 直接读 `ac.params.lock_time`，零额外代码 |
| QMAAM 不抢主 MSL 已锁目标 | "不浪费"硬规则 | `_is_valid_secondary_candidate` 共享前置 — 所有未来副槽武器自动继承 |
| QMAAM 不发不咬玩家的敌人 | "救命资源"语义 | `_pick_dogfight_side` 过滤：必须 `enemy.combat_target == ac` 或对玩家 lock 累积 > 0.5×lock_time |
| 敌方副槽不激活 | 避免基线突变 | `secondary_missile_enabled = false` 默认；6 架敌机 .tres 配置保留但不发射 |

## 验证清单

1. **回归（无副弹场景）**：F-16 / F-14 / F-86 / 默认敌机不配副弹时，行为完全不变。无 SP HUD 行 / 无副锁定锥 / 主弹路径零差异。
2. **架构通路**：F4 装载面板把副槽切到 QMAAM → 副锁定锥可见 / SP HUD 显示 1/1。
3. **独立性**：主弹空 + reload 中 → QMAAM 仍可发；QMAAM 空 + reload 中 → 主弹仍可发。
4. **优先级**：3 架敌机进副锥（前方 / 侧面没瞄我 / 侧面咬我尾）→ 选第 3 架。
5. **不抢目标**：主 MSL 已经在打侧面咬尾的那架 → QMAAM 跳过。
6. **JAM 阻断**：BOSS JAM 场内 → 副雷达累积冻结 + QMAAM 不发 + 主雷达 lock 也冻结（沙盒 + 生存对称）。
7. **升级流入**：`lock_time -0.5s` → 主弹 + QMAAM 锁定时间都减少；`missile_count +1` / `seeker_fov ×1.2` / `missile_boost` / `missile_tracking` / `missile_swarm` → 只影响主弹，QMAAM 不变。
8. **EventLogger**：`MISSILE` 事件区分 display_name；`remaining=` 指向正确 counter。
9. **性能**：单玩家场景副雷达 0.5s tick + 单飞机扫一次 combat_unit_list（≤30 单位），开销 < 1ms/s。Lv5+ 压力测试 FPS 不应掉 >2。

## 不在本次范围

- AGM 在玩家场景的应用（保留作敌方 .tres placeholder）
- 其他 3 个候选副槽武器（拦截弹 / 温压弹 / 自爆无人机）—— 未来按本套架构挂载即可
- 敌方副槽激活 —— 配置保留，dispatch 关闭
- 副槽支持手动选目标
- 多锁齐射 / 协同齐射对副槽支持
- 装备系统迁移（长期看应该把副槽挪到 `equipment[]` 数组里）

## 未来挂新副槽武器的模板

每挂一把新武器：
1. 新建 `MissileParams.tres`（或 `.gd` 子类如行为差异大）
2. 设 `target_filter` / `target_priority` / `lock_cone_half_angle_deg` / `lock_max_range_px`
3. 加每把武器自己的 gate 字段（如有需要）+ 在 `_pick_secondary_target` / `_is_valid_secondary_candidate` 加分支
4. 加 const 到 `missile_params.gd` 顶部（如 `TARGET_PRIO_INCOMING_MISSILE` 给拦截弹）
5. F4 调试面板 `_LOADOUT_SLOTS` `secondary_missile.options` 加一项

候选武器规划：

| 候选 | target_filter | target_priority | 需要追加的 gate 字段 |
|---|---|---|---|
| 热感拦截弹 | TARGET_MISSILE | INCOMING_THREAT | `auto_fire_on_threat` / `incoming_only` |
| 温压弹 | AIR \| GROUND | CLOSEST | （无新字段，纯数值——max_speed 低 / cooldown 高 / proximity_fuse_radius 大）|
| 自爆无人机 | TARGET_AIR | DOGFIGHT_SIDE 或新策略 | `reacquire_after_loss` / `reacquire_radius_px` |
| 格斗弹（QMAAM）| TARGET_AIR | DOGFIGHT_SIDE | （已实现）|
