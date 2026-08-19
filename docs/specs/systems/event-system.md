---
id: event-system
kind: system
status: done
schema_version: 1
spec_version: 3
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

**指令类型 `Type`（7 种）**：
| 类型 | 行为 |
|---|---|
| `FLY_TO_POINT` | 飞向 `params.target`，距离 < `arrival_radius` 触发 `on_arrival` |
| `PATROL_RING` | 绕 `params.center` 半径 `params.radius` 盘旋（`n_waypoints` 个圆周点） |
| `FOLLOW_PATH` | 沿 `params.waypoints` 飞，可 `loop` |
| `HOLD_POSITION` | 原地（飞机盘旋 / 舰船保持航向） |
| `ENGAGE_TARGET` | 强制 `combat_target=params.target` 进 ENGAGE（`combat_disabled=false`） |
| `PASSIVE` | 不开火不交战、照 waypoints 飞（驻泊兜底） |
| `PURSUE_UNIT` | 持续飞向 `params.target` 这个**会动的单位**，每 `params.refresh_interval`（默认 0.5s）重取一次位置。**无抵达态**（"追到了"由上层裁定，不触发 `on_arrival`）；目标失效自动释放本指令 |

> `PURSUE_UNIT` 由 [boss-hunter-doctrine](boss-hunter-doctrine.md) §3.1 引入。它不是
> "每 0.5s 重下一条 `FLY_TO_POINT`"的语法糖：重下会清 `_directive_state`，且 `FLY_TO_POINT`
> 自带的抵达判定会在贴近时触发 `on_arrival` 分派 —— 追一个会动的单位在语义上根本不是
> "飞到一个点"。

**抵达行为 `OnArrival`（仅 FLY_TO_POINT）**：`HOLD` / `PATROL`（复用 arrival_radius 作半径）/ `RELEASE`（清指令回正常）/ `CALLBACK`（调 `on_complete`）。

字段默认：`type=PASSIVE` · `params={}` · `owner_event=null`（事件死则失效）· `combat_disabled=true` ·
`priority=0`（高优先不被低覆盖）· `arrival_radius=400px（≈800m）` · `on_arrival=RELEASE`。
工厂：`fly_to(target,on_arrival,radius)` · `patrol_ring(center,radius,n=6)` · `follow_path(waypoints,loop)` ·
`hold_position()` · `engage_target(target)` · `passive()` · `pursue(target,refresh_interval=0.5)`。查询：`is_owner_alive()`。

## 3. 事件目录（当前实现）

| 事件类 | 文件 | 触发 | 生命周期 | 做什么 |
|---|---|---|---|---|
| **BossEncounterEvent** | `events/boss_encounter_event.gd` | survivor_mode 在战区阶段结束（`boss_unlocked`）手动 `director.start(...)` | CINEMATIC(PRE_STAGE) → ENGAGED → VICTORY | 经 BossRegistry 选 encounter（CSG/AceSquad/MotherGoose）→ spawn → 立即播放 `<boss_id>_arrival` → 镜头回玩家后立即交战 → 击杀判胜 |
| **AwacsSupportEvent** | `events/awacs_support_event.gd` | survivor_mode 的第三方事件调度（开局 90~150s；被击落/撤离后 ≥180s 可再触发） | 入场 → 在站盘旋 180s → 撤离（超时 90s 兜底）→ end | ALLY 预警机绕**当前战区南侧**跑道形盘旋，给玩家小队锁定 ×3 / 导弹追踪 G ×1.25 的光环；进离场各播一条 scripted 无线电。数值与轨道规格见 [global-awareness-roe §2.6c](global-awareness-roe.md) |
| **AceReinforcementEvent** | `events/ace_reinforcement_event.gd` | 按时段档调度（早期 240s / 中期 320s / 后期 400s，同场 1 支） | 入场 → 交战 → 全灭或 BOSS 闸撤离 | 敌方**王牌中队**（MARATHON / 2NDWAVE / GIMMICK / GOOFIGHTERS / VULTURE）的登场载体；全灭 → `game_time -= 60`。规格见 [ace-squadron-tier](ace-squadron-tier.md) + `events/ace-*` 各队 spec |
| **OrionNemesisEvent** | `events/orion_nemesis_event.gd` | 中期 ~300s 独立轨道，每局一次，不占王牌轮换名额 | 静默入场 → 死咬玩家当前操控机 → 击坠/撤离 | 宿敌 **ORION**（单机、无任何入场提示、跨局成长）。规格见 [events/ace-orion](../events/ace-orion.md) |
| ~~EscortConvoyEvent~~ | ~~`events/escort_convoy_event.gd`~~ | — | — | **2026-07-28 整体删除**（友军直升机护送）：玩家既看不见也没有局内理由去打。废弃记载见 [global-awareness-roe §2.6a](global-awareness-roe.md) |

BossEncounterEvent 关键常量：`INBOUND_SPAWN_DISTANCE_PX=6000`（Wraith 演出/出生距离 12km）、
`INBOUND_SPAWN_FAN_DEG=30`（玩家机头前方扇面）。PRE_STAGE 初始指令：CSG / AceSquad → `passive()`
安全垫；Mother Goose → 无；随后演出硬暂停冻结全场，Wraith 的 actor 指令再接管专属飞行分镜。
接战唯一触发器是登场演出收尾；旧 T1~T4 已废止（见 [boss-hunter-doctrine](boss-hunter-doctrine.md) §2.2）。
ENGAGED → `clear_all_directives()` + `encounter.engage()` + HUD 血条 + BGM 交叉淡入 + `mode.on_boss_engaged`。
VICTORY → `mode.on_boss_victory()` + `end()`。详见 [bosses/mother-goose](../bosses/mother-goose.md)。

> ⚠ **GameEvent 不是唯一的事件体系**。zone 任务 / Adds 族群波是**并行的另一套系统**
> （ZoneMission / spawner 直刷），**不是** GameEvent 子类。此外还有 §3.1 的 **ADBS 随机事件体系**。

### 3.1 ADBS 随机事件（并行体系，非 GameEvent）

`adbs_manager.gd` 自管的一套"战场背景事件"，与 GameEvent 平行存在（**不经 EventDirector**，
不下 AIDirective，单位由 spawner 的 flee 系列直刷）。定位：制造"这片天空本来就有别的事在发生"
的战场感，玩家可打可不打。当前两类：

| 事件 | 内容 |
|---|---|
| **开局教程轰炸机** | 出生点前方派生锚点刷 3 架逃跑轰炸机，纯教学靶机练锁定/攻击；**豁免护卫**（`with_escort=false`） |
| **城区直升机** | 城区上空 3 架 CH-47 逃跑组，带 2~4 机战斗机护卫（护卫编成规则见 [zone-reward-docking §2.7](zone-reward-docking.md)） |

**城区直升机事件规则（2026-07-28 三条新增）**：

| 规则 | 内容 | 为什么 |
|---|---|---|
| **护卫反应** | 被护送对象**挨打**时，其护卫机立刻扑向攻击者（伤害结算里唤醒护卫，按"指令级"目标来源指派，压过普通评分选择） | 此前敌方护卫对"被护送对象被打"**完全无反应**——护卫学说只对玩家队开、"保护被护对象"是玩家专属、adds 类还被 ROE 察觉体系整体排除。这是敌方护卫**唯一**的反应通道 |
| **受击散开** | CH-47 挨打即触发**编队散开**（与 AH-64 编队同款：受击散开标记 + 群成员互相登记） | 此前只有 AH-64 编队会散，CH-47 挨打呆立不动 |
| **全歼奖励** | 3 架 CH-47 **全部击落** → **作战时间 +20 s**（`CITY_HELI_TIME_BONUS_S`）+ 横幅提示 | 给这个原本"纯背景"的事件一个**局内**理由（对照 §2.6a 护送事件的废弃教训）。与"王牌中队全灭 +60s"共用同一时间延长注入点；**逃出地图被回收的不算战果，也不阻塞结算** |

> 全歼判定走轮询式击杀追踪（与既有击杀检测同模式），不挂信号、不持 Node 引用。

## 4. zone 任务（并行系统，非 GameEvent）

zone 任务在 `zone_mission.gd` 内自管，流程：**预刷/入场**（沿用既有画外优先 + 抵达死锁恢复；
空战 TGT 与所有驻守空军从地图边界外真实飞入，静态目标语义不变，见 [reinforcement-ingress](reinforcement-ingress.md) §3.8）→ **触发**（玩家进圈
或任一 TGT 被打到 hp<max）→ **完成**（该区 TGT 全灭）→ **奖励**（发 evolved 强卡，见 [survivor-loop §7](survivor-loop.md)）。
任务类型 air/squadron/naval/ground 由 zone_data 运行时 roll（elite 已移除，
spec [early-game-uav-rework](early-game-uav-rework.md) §2.3）。战区空军复用地图边缘候选算法；其它事件仍按各自航线或
"玩家前方扇形"约定（见 feedback_event_spawn_ahead）。
具体常量（编队数/orbit 半径/escort 数等）见 zone_mission.gd —— 不在此重列。

## 5. 扩展接入图（加新事件）★ 本 spec 重点

| 想加 | 怎么做 |
|---|---|
| **新剧本事件**（伏击/护航/编排登场） | ① 写 `docs/specs/events/<name>.md`（先 spec）② `scripts/events/<name>_event.gd extends GameEvent` 实现 `_start/_update/_finish` ③ `_start` 里 spawn + `set_directive(unit, AIDirective.xxx())` ④ 在 survivor_mode（或 spawner）按触发条件 `event_director.start(new_event)` ⑤ 奖励调 SurvivorPlayer 或 emit 信号 ⑥ i18n key |
| **新指令 verb**（如"护卫某单位"） | 给 `AIDirective.Type` 加枚举 + 工厂方法 + 在 `AIController._process_directive` 加该 type 的执行分支 |
| **随机/周期事件**（按时间轴自动登场） | 已有两条现成路子：①GameEvent 子类 + survivor_mode 的调度计时器（AWACS / 王牌中队 / 宿敌均如此）②纯背景事件走 ADBS（§3.1，不经 director）。选哪条：**要下指令 / 有相位 / 要生命周期回收 → GameEvent**；只是刷一组飞过去的单位 → ADBS |
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
- [x] 事件类铺开：AwacsSupportEvent（第三方支援）/ AceReinforcementEvent（敌方王牌中队）/
      OrionNemesisEvent（宿敌）；ADBS 背景事件体系并行（§3.1）
- [ ] （扩展位）新指令 verb —— 见 §5

## 8. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 调度器 | `scripts/events/event_director.gd` |
| 事件基类 | `scripts/events/game_event.gd` |
| 指令 | `scripts/events/ai_directive.gd` |
| BOSS 事件 | `scripts/events/boss_encounter_event.gd` |
| AWACS 支援事件 | `scripts/events/awacs_support_event.gd` |
| 王牌中队增援事件 | `scripts/events/ace_reinforcement_event.gd` |
| 宿敌 ORION 事件 | `scripts/events/orion_nemesis_event.gd` |
| ALLY 阵营转换器 | `scripts/events/ally_force.gd` |
| 指令执行 | `scripts/ai_controller.gd`（_process_directive）· `scripts/naval/naval_unit.gd` |
| zone 任务（并行系统） | `scripts/survivor/zone_mission.gd` · `zone_data.gd` |
| ADBS 背景事件（并行系统，§3.1） | `scripts/survivor/adbs_manager.gd` · `scripts/survivor/survivor_spawner.gd`（flee 系列） |
| 启动点 | `scripts/survivor/survivor_mode.gd`（建 director + start 事件） |
| reference 索引 | event-system.md · playbook §6 |

## 9. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-29 | 3 | BossEncounterEvent 相位统一：PRE_STAGE 只承载生成后立即播放的 arrival 演出；镜头回玩家后立即 ENGAGED。旧进圈/贴近/被锁/受伤 T1~T4 退出主流程，序列缺失 fail-open 直接接战。 |
| 2026-07-28 | 2 | **事件目录去腐**（原文"当前只有 BOSS 事件这一种 GameEvent 子类 / 随机事件尚未实现"已严重过时）：①§3 事件目录补齐在役子类 **AwacsSupportEvent / AceReinforcementEvent / OrionNemesisEvent**，并登记 **EscortConvoyEvent 已删除**；②新增 §3.1 **ADBS 随机事件体系**（并行、不经 EventDirector：开局教程轰炸机 / 城区直升机）+ 城区直升机三条新规则（**护卫反应**：被护送对象挨打→护卫指令级扑向攻击者，敌方护卫唯一反应通道；**CH-47 受击散开**：从 AH-64 专属泛化；**全歼 3 架 → 作战时间 +20s** + 横幅，与王牌全灭 +60s 同一注入点，逃出者不计不阻塞）；③§5 接入图的"随机事件系统（当前缺）"改写为 GameEvent / ADBS 二选一的选路指引；④§8 锚点补四个事件类 + adbs_manager |
| 2026-05-30 | 1 | 首版 system spec + 扩展接入图；核对 GameEvent/AIDirective 全 API（6 verb + 生命周期 + owner_event 失效） |
