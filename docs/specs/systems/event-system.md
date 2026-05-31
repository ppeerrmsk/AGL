---
id: event-system
kind: system
status: done
schema_version: 1
spec_version: 1
owner: design
depends_on: [survivor-loop, boss-encounter, zone-missions]
reconstruction_complete: true
---

# 事件 / 剧本系统（GameEvent + EventDirector + AIDirective，含扩展接入图）

> 一套**声明式**剧本框架：用 EventDirector 调度若干 GameEvent，每个事件用通用 verb（AIDirective）
> 命令任意 AI / 舰船做事（飞向、盘旋、巡逻、驻泊、强制交战）。定位：把"一段 BOSS 流程 / 一次刷怪 /
> 一段编排"从 AI 内部状态机里解耦出来，事件结束 AI 无缝回到正常逻辑。本 spec 兼作**加新事件的接入图**（§5）。

## 1. 设计意图（Why）

- **体验目标**：让"剧本化战斗段落"（BOSS 登场、舰队驻泊后启动、王牌编队远端切入）能被**声明式**编排，
  而不是往 AIController 里塞一堆 if。事件层只关心"何时开始/结束、给谁下什么指令"。
- **Litmus 自检**（docs/DESIGN_PHILOSOPHY.md）：
  - 指令是通用 verb，AI 执行期间完全接管、释放后无缝回归 → 过"系统正交、不污染基础层"。
  - directive 绑 `owner_event`，事件死则自动失效 → 防内存泄漏 / 幽灵指令 → 过"失败安全"。
- **反模式规避**：一架单位只持一个 directive（新覆盖旧）；事件结束 `clear_all_directives` 只清自己下的，
  避免多事件互相踩指令。

## 2. 架构（三层，已核对）

### 2.1 EventDirector（`event_director.gd`，survivor_mode 子节点，非 AutoLoad）

中央调度：持有所有活跃 GameEvent，每帧 `_physics_process`：① `_update` 所有事件 → ② 收集 `active=false` 的
→ ③ 对其调 `clear_all_directives()` + `_finish()` 并移除回收。
依赖注入：`_ready` 时接 `mode` / `player` / `spawner`。接口：`start(event)`（立即调 `event._start()` 并入列）、
`find_by_name(name)`、`active_count()`。

### 2.2 GameEvent（`game_event.gd`，RefCounted 基类）

生命周期钩子（子类覆盖）：
| 方法 | 时机 | 用途 |
|---|---|---|
| `_start()` | director.start 调一次 | 置 `active=true`、生成单位、下初始指令 |
| `_update(delta)` | active 期间每帧 | 推进 phase、监控完成、下指令 |
| `_finish()` | active 翻 false 后下一帧回收时一次 | 收尾、通知 mode |

指令工具：`set_directive(unit, d)`（写到飞机 `AIController._directive` 或 `NavalUnit._directive`，自动入 `managed_units` +
绑 `owner_event=weakref(self)`）、`clear_directive(unit)`、`clear_all_directives()`（只清 owner_event==self 的）、
`end()`（置 active=false，下一帧回收）。字段：`name`（log 用）、`active`、`director`、`managed_units`。
调试：`debug_break_enabled`（发行版务必 false）。

### 2.3 AIDirective（`ai_directive.gd`，RefCounted，纯数据 + 工厂，无状态机）

执行模型：`AIController._physics_process` 顶层 `if _directive: _process_directive(); return`（完全接管，跳过
PATROL/ENGAGE/SQUAD_FOLLOW）；`NavalUnit._update_subsystems` 顶层 `if _directive and combat_disabled: return`（跳过开火）。

**指令类型 `Type`（6 种）**：
| 类型 | 行为 |
|---|---|
| `FLY_TO_POINT` | 飞向 `params.target`，距离 < `arrival_radius` 触发 `on_arrival` |
| `PATROL_RING` | 绕 `params.center` 半径 `params.radius` 盘旋（`n_waypoints` 个圆周点） |
| `FOLLOW_PATH` | 沿 `params.waypoints` 飞，可 `loop` |
| `HOLD_POSITION` | 原地（飞机盘旋 / 舰船保持航向） |
| `ENGAGE_TARGET` | 强制 `combat_target=params.target` 进 ENGAGE（`combat_disabled=false`） |
| `PASSIVE` | 不开火不交战、照 waypoints 飞（驻泊兜底） |

**抵达行为 `OnArrival`（仅 FLY_TO_POINT）**：`HOLD` / `PATROL`（复用 arrival_radius 作半径）/ `RELEASE`（清指令回正常）/ `CALLBACK`（调 `on_complete`）。

字段默认：`type=PASSIVE` · `params={}` · `owner_event=null`（事件死则失效）· `combat_disabled=true` ·
`priority=0`（高优先不被低覆盖）· `arrival_radius=400px（≈800m）` · `on_arrival=RELEASE`。
工厂：`fly_to(target,on_arrival,radius)` · `patrol_ring(center,radius,n=6)` · `follow_path(waypoints,loop)` ·
`hold_position()` · `engage_target(target)` · `passive()`。查询：`is_owner_alive()`。

## 3. 事件目录（当前实现）

| 事件类 | 文件 | 触发 | 生命周期 | 做什么 |
|---|---|---|---|---|
| **BossEncounterEvent** | `events/boss_encounter_event.gd` | survivor_mode 在战区阶段结束（`boss_unlocked`）手动 `director.start(...)` | PRE_STAGE → ENGAGED → VICTORY | 经 BossRegistry 选 encounter（CSG/AceSquad/MotherGoose）→ spawn → 初始指令 → 玩家进圈/近身触发交战 → 击杀判胜 |

BossEncounterEvent 关键常量：`BOSS_ENGAGE_DISTANCE_PX=2500`（近身触发交战）、`FAR_EDGE_INSET_PX=600`（AceSquad 远端切入边距）、
`ANCHOR_PATROL_RADIUS=1600`（抵达后盘旋半径）、`BOSS_ZONE_RADIUS` 默认 2200（可读 zone_data）。
PRE_STAGE 初始指令：CSG → `passive()`；AceSquad → `fly_to(anchor, PATROL)`；MotherGoose → 无（自管巡逻+蜂群）。
ENGAGED → `clear_all_directives()` + `encounter.engage()` + HUD 血条 + BGM 交叉淡入 + `mode.on_boss_engaged`。
VICTORY → `mode.on_boss_victory()` + `end()`。详见 [bosses/mother-goose](../bosses/mother-goose.md)。

> ⚠ **当前只有 BOSS 事件这一种 GameEvent 子类**。zone 任务 / Adds 族群波是**并行的另一套系统**
> （ZoneMission / spawner 直刷），**不是** GameEvent 子类。playbook §6 提到的"随机事件"目前尚未实现 —— 是新事件类型的接入位。

## 4. zone 任务（并行系统，非 GameEvent）

zone 任务在 `zone_mission.gd` 内自管，流程：**预刷**（离屏 + 不在镜头内才刷，防 pop-in）→ **触发**（玩家进圈
或任一 TGT 被打到 hp<max）→ **完成**（该区 TGT 全灭）→ **奖励**（发 evolved 强卡，见 [survivor-loop §7](survivor-loop.md)）。
任务类型 air/squadron/elite/naval/ground 由 zone_data 运行时 roll。刷点遵循"玩家前方扇形"约定（见 feedback_event_spawn_ahead）。
具体常量（编队数/orbit 半径/escort 数等）见 zone_mission.gd —— 不在此重列。

## 5. 扩展接入图（加新事件）★ 本 spec 重点

| 想加 | 怎么做 |
|---|---|
| **新剧本事件**（伏击/护航/编排登场） | ① 写 `docs/specs/events/<name>.md`（先 spec）② `scripts/events/<name>_event.gd extends GameEvent` 实现 `_start/_update/_finish` ③ `_start` 里 spawn + `set_directive(unit, AIDirective.xxx())` ④ 在 survivor_mode（或 spawner）按触发条件 `event_director.start(new_event)` ⑤ 奖励调 SurvivorPlayer 或 emit 信号 ⑥ i18n key |
| **新指令 verb**（如"护卫某单位"） | 给 `AIDirective.Type` 加枚举 + 工厂方法 + 在 `AIController._process_directive` 加该 type 的执行分支 |
| **随机事件系统**（playbook §6 所述、当前缺） | 在 spawner/mode 加轮询计时器，按权重/冷却 `director.start(...)`；事件本体仍是 GameEvent 子类 |
| **新 zone 任务类型** | 走 zone_mission/zone_data（非 GameEvent）：加 mission_type + `_spawn_xxx` + 完成判定；见 [survivor-loop §8](survivor-loop.md) |
| **BOSS** | 走 BossEncounter + boss_registry，由 BossEncounterEvent 复用；样板 [mother-goose](../bosses/mother-goose.md) |

最小子类骨架（参考）：

```gdscript
class_name CustomEvent
extends GameEvent
enum Phase { INTRO, ACTIVE }
var phase := Phase.INTRO
func _init(p_anchor): name = "custom_event"; _anchor = p_anchor
func _start() -> void:
    active = true
    # spawn 单位 + 下初始指令
    set_directive(unit, AIDirective.fly_to(_anchor, AIDirective.OnArrival.PATROL))
func _update(delta) -> void:
    match phase:
        Phase.INTRO:
            if _ready_to_engage(): phase = Phase.ACTIVE; clear_all_directives()
        Phase.ACTIVE:
            if _done(): end()
func _finish() -> void: pass  # 收尾
```

## 6. 验收标准（Acceptance / Litmus）

- [x] directive 期间 AI 完全接管（跳过 PATROL/ENGAGE）；释放后无缝回正常
- [x] 一单位仅一 directive，新覆盖旧；事件死 → owner_event 失效 → AI 自动回归
- [x] `clear_all_directives` 只清 owner_event==self 的，不误清他事件
- [x] 6 种 Type + 4 种 OnArrival + 工厂方法齐全
- [x] BossEncounterEvent 三相（PRE_STAGE/ENGAGED/VICTORY）+ 2500px 近身触发
- [x] zone 任务为并行系统，不混进 GameEvent

## 7. 实现计划（Task Pipeline）

> 已落地（status: done）。保留作重建 + 扩展参考。

- [x] GameEvent 基类（生命周期 + directive 工具 + 自动撤销）
- [x] EventDirector 调度 + 依赖注入
- [x] AIDirective（6 verb + 4 on-arrival + 工厂 + owner_event 失效）
- [x] BossEncounterEvent 三相
- [ ] （扩展位）随机事件系统 / 新指令 verb —— 见 §5

## 8. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 调度器 | `scripts/events/event_director.gd` |
| 事件基类 | `scripts/events/game_event.gd` |
| 指令 | `scripts/events/ai_directive.gd` |
| BOSS 事件 | `scripts/events/boss_encounter_event.gd` |
| 指令执行 | `scripts/ai_controller.gd`（_process_directive）· `scripts/naval/naval_unit.gd` |
| zone 任务（并行系统） | `scripts/survivor/zone_mission.gd` · `zone_data.gd` |
| 启动点 | `scripts/survivor/survivor_mode.gd`（建 director + start 事件） |
| reference 索引 | event-system.md · playbook §6 |

## 9. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 首版 system spec + 扩展接入图；核对 GameEvent/AIDirective 全 API（6 verb + 生命周期 + owner_event 失效） |
