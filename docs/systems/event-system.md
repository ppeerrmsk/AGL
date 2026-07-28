# 事件系统（GameEvent + AIDirective）

> 最后校订：2026-07-28。数值与行为的权威源在
> [specs/systems/event-system](../specs/systems/event-system.md)（含扩展接入图）。

剧本驱动的 AI 命令系统。BOSS 战 / 第三方事件 / 演出走这套，避免在 AceSquad / spawner 里硬塞特殊状态机。

## 三层结构

1. **`EventDirector`**（survivor_mode 子节点）—— 持有所有 active 事件，每帧 tick；事件结束自动撤销其下发的 directive
2. **`GameEvent`**（RefCounted 基类）—— 一段剧本的生命周期 + managed_units 列表；子类覆盖 `_start/_update/_finish`
3. **`AIDirective`**（RefCounted）—— 给单架 AI / NavalUnit 的声明式覆盖指令；存在期间 AIController 顶层完全跳过 PATROL/ENGAGE 路由，只执行 directive verb

## directive 类型

FLY_TO_POINT（含 OnArrival HOLD/PATROL/RELEASE/CALLBACK）/ PATROL_RING / FOLLOW_PATH /
HOLD_POSITION / ENGAGE_TARGET / PASSIVE / **PURSUE_UNIT**。

`PURSUE_UNIT` 持续飞向一个**会动的单位**（周期重取其实时位置），**无抵达态**，
目标失效则自动释放——BOSS 猎手准则用它取代"飞到锚点等玩家"
（见 [specs/systems/boss-hunter-doctrine](../specs/systems/boss-hunter-doctrine.md)）。

`combat_disabled=true`（默认）时 AI 跳过雷达锁定 + 武器开火。

## 集成点

- `AIController._physics_process` 顶层判断 `_directive` → 调 `_process_directive(delta)` → return
- `NavalUnit._update_subsystems` 顶层判断 `_directive_active() and combat_disabled` → 跳过 NavalWeapons.update
- `GameEvent.set_directive(unit, d)` 自动写入 + 加 managed_units，事件结束 `clear_all_directives()` 统一撤销

## 当前剧本

`scripts/events/` 下：

| 事件 | 说明 |
|---|---|
| `BossEncounterEvent` | BOSS 战三相 PRE_STAGE → ENGAGED → VICTORY（替代旧的散在 ace_squad/csg/survivor_mode 的状态机）|
| `AceReinforcementEvent` | 王牌支援中队（非 BOSS 的王牌中队实例）|
| `AwacsSupportEvent` | AWACS 绕**当前战区**盘旋撑 buff 区；在站 180s 到点后转向南界外撤离，进 / 离场各有无线电 |
| `AllyForce` | 友军力量基础设施（机场防空伞等）|

**已删除**：`EscortConvoyEvent`（护送直升机 A→B 的第三方 ALLY 事件，2026-07-28 移除）——
奖励是纯局外功勋、Tab 图不画护送队、也没有无线电，玩家既找不到它也没有局内理由去打，属纯噪音事件。

⚠ **演出（cinematic）不走这套**，走 `scripts/presentation/`
（TimeAuthority + SequencePlayer）；但演出下发给演员的指令**必须委托 `GameEvent`**
复用其 owner/cleanup，绝不造第二套所有权——泄漏的表现是"BOSS 永不参战且不报错"。
见 [specs/systems/ui-transition](../specs/systems/ui-transition.md)。

## 加新剧本步骤

1. 写 `extends GameEvent` 类（`scripts/events/<name>_event.gd`）
2. 在 `_start` 里挑单位 + 下发 directive
3. 在 `_update` 里推进 phase / 检测完成条件 → `end()`
4. 调用方：`event_director.start(MyEvent.new(...))`
