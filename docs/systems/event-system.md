# 事件系统（GameEvent + AIDirective）

> 本节内容原在 CLAUDE.md，2026-05-05 移出。

剧本驱动的 AI 命令系统。BOSS 战 / 未来剧情演出走这套，避免在 AceSquad / spawner 里硬塞特殊状态机。

## 三层结构

1. **`EventDirector`**（survivor_mode 子节点）—— 持有所有 active 事件，每帧 tick；事件结束自动撤销其下发的 directive
2. **`GameEvent`**（RefCounted 基类）—— 一段剧本的生命周期 + managed_units 列表；子类覆盖 `_start/_update/_finish`
3. **`AIDirective`**（RefCounted）—— 给单架 AI / NavalUnit 的声明式覆盖指令；存在期间 AIController 顶层完全跳过 PATROL/ENGAGE 路由，只执行 directive verb

## directive 类型

FLY_TO_POINT（含 OnArrival HOLD/PATROL/RELEASE/CALLBACK）/ PATROL_RING / FOLLOW_PATH / HOLD_POSITION / ENGAGE_TARGET / PASSIVE。

`combat_disabled=true`（默认）时 AI 跳过雷达锁定 + 武器开火。

## 集成点

- `AIController._physics_process` 顶层判断 `_directive` → 调 `_process_directive(delta)` → return
- `NavalUnit._update_subsystems` 顶层判断 `_directive_active() and combat_disabled` → 跳过 NavalWeapons.update
- `GameEvent.set_directive(unit, d)` 自动写入 + 加 managed_units，事件结束 `clear_all_directives()` 统一撤销

## 当前剧本

**BossEncounterEvent**（替代旧的散在 ace_squad/csg/survivor_mode 的 PRE_STAGE / Engage / Victory 三段状态机）

## 加新剧本步骤

1. 写 `extends GameEvent` 类（`scripts/events/<name>_event.gd`）
2. 在 `_start` 里挑单位 + 下发 directive
3. 在 `_update` 里推进 phase / 检测完成条件 → `end()`
4. 调用方：`event_director.start(MyEvent.new(...))`
