---
id: rts-command
kind: system
status: approved
schema_version: 1
spec_version: 5
owner: 设计/用户
depends_on: []
reconstruction_complete: true
---

# RTS 指挥模式（战术地图导航 + 自动交战）

> 玩家以 RTS 小队指挥官身份操控编队：在战术地图（Tab）上点目标 → 小队自主巡航过去 → 到点后按开关自动锁敌交战。

## 1. 设计意图（Why）

- **体验目标**：把生存模式从"单机点击走位 + 手动逐个点敌"升级为"下达指挥意图，小队自主执行"的 RTS 体感。玩家在暂停的战术地图上规划，回到战场后编队像真实小队一样自主奔赴、自主接敌，玩家退居指挥位。承接 [[project_rts_direction]]（游戏转向操控小队的 RTS 空战）。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - "操控走位、不精确控速/控枪" —— 玩家只下巡航点与交战开关，具体转弯/开火由飞机物理与既有 AI 战术层完成。
  - "物理优雅" —— 巡航/接敌全程靠既有 `target_position` + `combat_target` 真实转弯抵达，不瞬移、不伪造曲线（[[feedback_formation_physical_elegance]]）。
- **反模式规避**：不新增并行的"移动系统"——复用既有 `Aircraft.target_position`（世界坐标巡航）与 `combat_target`（追击/开火）两条既有通路；僚机跟打复用 `SquadCoordination`，零新编队代码。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 自动交战参数（`RtsCommandParams`，resources/rts_command.tres）

**去硬编码**：以下数值是 `RtsCommandParams extends Resource` 的 `@export` 字段，住在 `resources/rts_command.tres`，Inspector 可调，不再是代码常量。仅约束"自动交战"；玩家命令(commanded_target)走铁律，不受这些参数影响。

| 字段 | 默认值 | 说明 |
|---|---|---|
| `auto_engage_enabled` | `true`（默认开） | 玩家机战术偏好布尔，住在 `Aircraft`（HUD 战术栏 toggle）。只被 `SquadCommandController` 读；敌机不读。 |
| `auto_engage_radius_px` | `1500.0` px（=750 m，`PIXELS_PER_METER=0.5`） | 长机到点/空闲时的搜敌半径，**刻意小**：只自动打"贴脸"的敌人，远处交给玩家手动指挥。 |
| `auto_engage_leash_mult` | `1.5` | 拴绳系数：**自动锁的目标**飞出 `radius×此值`（2250 px）则放弃，回到空闲再重选。**绝不作用于玩家命令目标**。 |
| `auto_engage_interval_s` | `0.3` s | 自动交战决策 tick 频率（低频，遵守性能守则 ≥3 分频）。 |

### 2.1.1 玩家命令目标（铁律，逐机持久）

| 字段 | 位置 | 说明 |
|---|---|---|
| `commanded_target` | `Aircraft`（逐机一个） | 玩家对**这架机**显式点名的攻击命令目标。跨 1/2/3/4 切控持久。AI / 自动交战**一律不得覆盖**（铁律）。只在：目标阵亡 / 玩家对本机另下移动·取消·新攻击命令 时清。 |

### 2.2 巡航目标语义（复用既有字段，无新字段）

| 来源 | 设定的 `target_position` | 备注 |
|---|---|---|
| 战术地图点空白处 | 点击映射的精确世界坐标 | 经 `TacticalMap._map_to_world` 反算。 |
| 选战区 | 战区圆**边缘最近点** `center + (player-center).normalized()×radius` | 飞到近边即进圈，触发既有 ZoneMission。 |
| 既有左键点空地 | 鼠标世界坐标 | 不改。 |

## 3. 行为与公式（How）

### 3.1 指令注入（战术地图 / 关面板后）

| 操作 | 行为 |
|---|---|
| Tab 开图，点**空白处** | 反算世界坐标 → **留琥珀色航点标记** + 发 `nav_point_selected(wp)` → **不关图**（玩家可继续规划，Tab/Esc 才关） → 对全部 `selected_aircraft` 关规避 + `clear_combat_target()` + `target_position = wp` |
| Tab 开图，点 **AVAILABLE 战区** | 原 `zone_selected` 流程不变；**清航点标记** + 额外算边缘点设为巡航目标；**不关图** |
| Tab 开图，**右键** | 发 `nav_cleared` → 清航点标记 + 对 `selected_aircraft` 清目标 + `target_position=INF`（取消巡航指令） |
| 战场内左键点敌机 | 不变（手动指定 `combat_target`，可双击冲锋） |
| 战场内右键 | 不变（清目标 + `target_position=INF`，急刹） |

**航点标记（交互反馈）**：玩家点空白处留下脉冲十字标记（`_nav_marker_world`），告知"这里已被选中"。选战区会清掉它（目标改为战区），地图右键清掉它。地图保持打开 = 可交互规划面板。

### 3.2 玩家命令铁律（最高优先级，逐机持久）

**铁律**：玩家显式点名的 `commanded_target`，任何逻辑都不得干扰/覆盖。逐机持有、跨 1/2/3/4 切控持久——玩家可给不同飞机各下不同攻击命令，切走后该机继续执行自己的命令，直到目标死或玩家对它另下指令。

| 持有者 | 执行点 | 规则 |
|---|---|---|
| 被操控机（manual + planner） | `SquadCommandController.tick` | tick 见 `commanded_target` 非空即跳过自动交战；若 `combat_target != commanded_target` 重新指回。命令绝不被拴绳/最近目标夺走。 |
| 非操控带命令机（切走后） | `AIController._enforce_commanded_target`（路由顶部，manual/simple/规避之后） | 命令目标存活 → 强制 ENGAGE 它、`clear_formation`、绕过 `try_engage` 评分与编队路由；`_process_engage` 跳过 `reevaluate_target`。命令目标死/被清 → 解除 `commanded_target` 回正常 AI（disengage 回编队）。 |

**清除时机**：目标阵亡（持有者检测）/ 玩家对本机下移动·取消·新攻击命令。求生规避优先于命令（规避结束下一 tick 自动重接命令目标）。

### 3.3 自动交战 tick（`SquadCommandController.tick`，每 `auto_engage_interval_s`）

仅在**无玩家命令**时生效；玩家命令在上面 §3.2 已 return。

```
leader = mode.selected_aircraft[0]
若 leader.commanded_target 存活: 维持/指回它, 返回      # 铁律（§3.2）
    （若已阵亡: 解除 commanded_target + 清 target_position 回待命, 落到下面）
若 not player_aircraft.auto_engage_enabled: 返回
若 leader.combat_target 存活（自动锁的）:
    若 ct == _auto_engage_target 且 dist > radius*leash:
        放弃 + target_position=INF 回待命              # 拴绳只对自动锁的目标
    返回
若 _auto_engage_target 刚阵亡: 清 target_position=INF 回待命（不飞向死敌 lead 点）
若 leader.target_position != INF: 返回                # 巡航途中不打，保证抵达
tgt = 半径内最近有效敌方(CombatUnit.all_units, radius)
若 tgt: set_combat_target(tgt); _auto_engage_target = tgt
```

- **僚机**：无需新代码，`SquadCoordination.process_squad_follow` 把 `leader.combat_target` 传播给僚机；带命令机由其自身 `_enforce_commanded_target` 死咬。
- **搜敌**：用 `CombatUnit.all_units`（perf 友好共享表），不扫 `mode.get_children()`。
- **目标选择（v1）**：半径内**最近**。未被点名的"自由僚机"的有限度自主切目标（必中让路/不偏太远）归 [target-engageability-selection](target-engageability-selection.md)，本 spec 不做。

### 3.4 战区导航与任务选择解耦

点击战术地图上**任意可见战区**（`_zone_id_at` 已排除 LOCKED/隐藏）都重新下达"飞向战区边缘"的巡航指令，**与战区状态无关**；仅 `AVAILABLE` 时才额外触发 `select_zone`（任务选择状态机）。修复"战区飞过一次被标 CLEARED 后再点就无法前往"。

### 3.5 开关语义（右侧战术栏）

| 开关 | 行为 |
|---|---|
| 自动交战 = 开（默认） | **无玩家命令**的机到点/空闲后自动锁最近敌机；玩家命令机不受影响 |
| 自动交战 = 关 | 到点纯待命不自动锁敌；玩家点名命令仍照常执行 |

## 4. 结构与组成（Structure）

**模块划分（RTS 逻辑独立于 survivor_mode）**：
- **`RtsCommandParams`**（`scripts/rts/rts_command_params.gd` + `resources/rts_command.tres`）：自动交战可调参数 Resource，去硬编码。
- **`SquadCommandController`**（`scripts/rts/squad_command_controller.gd`，`extends Node`）：RTS 指挥**单一所有者**。`command_attack/command_move/cancel` + `tick`。`survivor_mode` 建它为子节点 + `setup(self, params)`，输入层只转发。
- **`Aircraft.commanded_target`**：逐机玩家命令（铁律），`Aircraft.auto_engage_enabled`：战术偏好。
- **`AIController._enforce_commanded_target`**：非操控机的铁律执行点（路由顶部）+ `_process_engage` reevaluate 门。
- **`TacticalMap`**：`nav_point_selected` / `nav_cleared` 信号 + 航点标记。
- **`SurvivorHUD._btn_auto_engage`**：第 5 个战术 toggle。
- **复用**：`Aircraft.target_position`/`combat_target`、`SquadCoordination`、`CombatUnit.all_units`、`TacticalMap._map_to_world`、`ZoneData.get_zone_by_id`、既有 `disengage`/`LEADER_TARGET_LOST_GRACE`。

**接线**：`survivor_mode` 仅转发——`_on_left_click`(敌)→`command_attack`，`_on_nav_point_selected`/`_on_zone_selected`(边缘)→`command_move`，`_on_nav_cleared`/`_on_right_click`→`cancel`，`_physics_process`→`tick`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] Tab 点空白海域 → 关图后小队转弯飞向该点并停下。
- [ ] Tab 选战区 → 小队飞向战区**边缘**（非圆心），进圈触发任务。
- [ ] 开关 ON + 到点半径内有敌 → 长机自动 `set_combat_target` 最近敌机，僚机跟打。
- [ ] 开关 OFF → 到点纯待命不自动锁敌；手动点敌仍可交战。
- [ ] 巡航途中（target 未到达）**不**触发自动交战。
- [ ] 自动锁的目标飞出 2250 px → 放弃回空闲（不影响玩家命令目标）。
- [ ] **铁律**：点名打 Sentinel（远）→ 全程死咬，AI/自动交战都不夺走。
- [ ] **逐机持久**：操控 2 号机点名打 B → 切 1 号机点名打 A → 两机各打各的，切来切去命令不丢，直到各自目标死。
- [ ] **解除**：对某机下移动/右键 → 放弃攻击命令；命令目标死 → 回编队（不飞向死敌点）。
- [ ] **自由僚机回归**：未点名僚机行为与改动前一致。
- [ ] **去硬编码**：改 `rts_command.tres` 的 `auto_engage_radius_px` 无需改代码即生效。
- [ ] 性能：Sentinel + Lv5+ 压测，0.3s tick FPS 掉幅 < 15（见 performance-guidelines）。
- [ ] i18n：按钮 + tooltip 三语已补（TACTIC_AUTO_ENGAGE_FMT / TOOLTIP_AUTO_ENGAGE_*）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 数据 + 注入
- [x] `Aircraft.auto_engage_enabled` 字段
- [x] `TacticalMap.nav_point_selected` 信号 + 空白点击注入
- [x] `SurvivorMode` 连接信号 + `_on_nav_point_selected` + 战区边缘目标

### 阶段 2 — 自动交战
- [x] `_update_auto_engage` tick（累加器分频）+ `_find_auto_engage_target`

### 阶段 3 — UI + 收尾
- [x] HUD 第 5 个战术开关 + handler + tooltip
- [x] i18n 三语
- [x] 同步 reference 索引

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| RTS 指挥逻辑（命令+自动交战） | `scripts/rts/squad_command_controller.gd`（`SquadCommandController`） |
| 参数 Resource | `scripts/rts/rts_command_params.gd` + `resources/rts_command.tres` |
| 玩家机字段 | `scripts/aircraft.gd`（`commanded_target` / `auto_engage_enabled`） |
| 命令铁律（非操控机） | `scripts/ai_controller.gd`（`_enforce_commanded_target` + `_process_engage` reevaluate 门） |
| 战术地图信号/点击/标记 | `scripts/survivor/tactical_map.gd`（`nav_point_selected` / `nav_cleared` / `_draw_nav_marker`） |
| 接线（瘦身后） | `scripts/survivor/survivor_mode.gd`（`_on_left_click` / `_on_nav_*` / `_set_cruise_to_zone_edge` 仅转发到 `_squad_cmd`） |
| 僚机跟打（复用） | `scripts/ai/squad_coordination.gd` |
| UI 开关 | `scripts/survivor/survivor_hud.gd` |
| 文案 | `i18n/translations.csv`（TACTIC_AUTO_ENGAGE_* / TOOLTIP_AUTO_ENGAGE_*） |
| reference 索引行 | script-index.md / code-index.md 对应行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-06-14 | 1 | 初稿 + 实现（战术地图导航 + 战区边缘巡航 + 到点自动交战 + 右侧开关） |
| 2026-06-14 | 2 | 调整：搜敌半径 4000→1500（足够小）；点图/选战区不再自动关图；新增航点标记 + 地图右键清除（nav_cleared） |
| 2026-06-14 | 3 | 修 bug：①自动交战目标阵亡后清 target_position 回待命（不再飞向死敌 lead 点）②战区导航与 AVAILABLE 状态机解耦（CLEARED 战区也能重新前往） |
| 2026-06-14 | 4 | 修 bug：拴绳误清玩家手动命令的远目标 → 自动交战改抓最近杂兵（来回切 combat target）。新增 `_player_commanded_target` 粘性命令：手动指定目标凌驾自动交战、不被拴绳、丢了重新指回；拴绳改为只对 `_auto_engage_target` 生效 |
| 2026-06-14 | 5 | 重构 + 铁律：①RTS 逻辑抽出独立模块 `SquadCommandController` + 参数 Resource `RtsCommandParams`（去硬编码），survivor_mode 瘦身为接线；②玩家命令升级为**逐机持久铁律** `Aircraft.commanded_target`，跨 1/2/3/4 切控持久，AIController `_enforce_commanded_target` 保证非操控机也死咬命令、跳过 reevaluate；③自由僚机有限度切目标细则归 [[target-engageability-selection]]，本 spec 不做 |
