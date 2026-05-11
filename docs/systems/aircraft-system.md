# Aircraft 系统 — 物理流程 / 战斗追踪 / 武器模式

> 本节内容原在 CLAUDE.md，2026-05-05 移出。

## Aircraft 物理演算流程（每帧）

`aircraft.gd:_physics_process` → 按 LOD 分三档，每档调度 `AircraftPhysics` / `AircraftWeapons` / `AircraftCombatTracking` / `AircraftFlares` 静态方法：

- **LOD 0（完整）**：玩家 + 交战中飞机。全部 18 步（武器模式/战斗/能量管理/航向/bank/速度/高度/燃油/失速/G 力/位移/机炮/导弹/热诱弹/视觉）
- **LOD 1（简化）**：编队僚机巡航。大部分步骤每 3 帧运行一次，编队托管有专用三段式航向控制（见 [squad-tactics-design.md](squad-tactics-design.md)；LOD 1 编队托管已拆到 `aircraft/aircraft_formation.gd`，顶部注释有"常见 bug 回溯地图"）
- **LOD 2（屏幕外）**：离屏飞机，每 3 帧完整更新一次，其余帧仅位移

## 战斗追踪与武器模式

飞机内置战斗追踪（`aircraft/aircraft_combat_tracking.gd:update_combat`）处理机炮/导弹的三阶段追踪：接近 → 照射 → 保持。

武器模式切换有滞后防震荡：
- 无导弹 → GUN
- Crank 阶段强制 MISSILE
- GUN 模式需距离 > 机炮射程×2 才切回 MISSILE
- MISSILE 模式需距离 < 机炮射程×0.8 才切 GUN

## 副导弹槽位（独立武器子系统，开发代号 secondary_missile）

> 玩家面叫 **SP**（Special Weapon）。开发代号 `secondary_missile` 是历史 AAM/AGM 双轨制留下的字段名——2026-04-29 因冗余被合并掉，2026-05-10 复活为通用特殊武器槽位（详见 [docs/changelogs/2026-05-10-secondary-slot-revival.md](../changelogs/2026-05-10-secondary-slot-revival.md)）。

**关键正名**：副槽**不是** missile 子类，而是飞机的第二套独立武器子系统。它复用 `MissileParams` 资源结构（飞行物理 / 制导 / 战斗参数）只是工程上方便——但锁定 / 发射 / UI / 升级路径都和 MSL 完全平行：

| 维度 | 主 MSL | 副槽 SP |
|---|---|---|
| 锁定锥 | `params.radar_half_angle` 飞机层 | `MissileParams.lock_cone_half_angle_deg` 武器层（>0 覆盖飞机默认）|
| 锁定距离 | `effective_radar_range_px()` | `MissileParams.lock_max_range_px`（>0 覆盖）|
| 锁定累积 | `Aircraft.radar_targets` 共享 dict | `Aircraft.secondary_radar_targets` 独立 dict |
| 锁定时间 | `params.lock_time` | **共享**（`lock_time` 升级自动透传）|
| 目标选择 | 玩家点击 `combat_target` | 自动按 `target_priority` 策略 |
| 发射触发 | 玩家点击 / 战术齐射 | 自动：锁定满 + envelope 满足 |
| Cooldown | `_missile_cooldown` | `_secondary_cooldown` 独立 |
| 装填 | `_missile_reload_*` | `_secondary_reload_*` 独立 |
| MSL 升级流入 | ✅ 全部 | ❌ **一律不流入**（武器靠 .tres 数值定身份）|
| 基础锁定升级 | ✅ | ✅ `lock_time` 流入；`radar_range` / `radar_angle` 不流入 |
| 敌方对称 | 始终激活 | `secondary_missile_enabled` 标志，默认关，玩家显式开 |
| 多锁齐射 / 协同齐射 | ✅ | ❌ 副槽是"特殊一发"语义 |

**调度路径**（[aircraft/aircraft_weapons.gd](../../scripts/aircraft/aircraft_weapons.gd)）：
- `update_secondary_radar(ac, delta)` — 0.5s tick 节流，扫 `BulletManager.combat_unit_list`，按 `target_filter` 过滤 → 累积到 `secondary_radar_targets`。JAM 期间冻结。
- `update_secondary_missile(ac, delta)` — 独立 cooldown 倒计时；自动选目标（`_pick_secondary_target` 按 `target_priority` 分发）；envelope 通过即 `_fire_missile_at(..., is_secondary=true)`。
- `_is_valid_secondary_candidate` 共享前置：锁定满 + 有效 + **主 MSL 没在打它**（不抢主弹目标，所有副槽武器自动继承这条纪律）。

**MissileParams 副槽相关字段**：`target_filter` / `lock_cone_half_angle_deg` / `lock_max_range_px` / `target_priority`。const 位域：`TARGET_AIR / GROUND / SHIP / MISSILE`；优先级：`TARGET_PRIO_CLOSEST / DOGFIGHT_SIDE`（未来扩展每加一个策略加一个 const）。

**第一把样本武器**：QMAAM ([resources/qmaam_missile.tres](../../resources/qmaam_missile.tres))——70° 宽锁定锥扩到侧面、近距 1500px、单发即转 8s CD、60G 极强机动；优先级策略 `DOGFIGHT_SIDE`（侧面 off-axis 大 + 正在狗斗玩家的敌机）。
