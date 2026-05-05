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
