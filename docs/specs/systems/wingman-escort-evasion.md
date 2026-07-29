---
id: wingman-escort-evasion
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 1
owner: ppeerrmsk
depends_on: [rts-command, squad-cohesion, squad-ai-escort]
reconstruction_complete: true
---

# 僚机护卫规避（被打才逃 / 待命护焰）

> 玩家按 E（现为**加力模式**触发键）时，僚机不再无脑加速散开飞离阵型；而是「只有自己真被导弹咬住才加速逃命，否则守在长机身边，并主动投热诱弹替长机挡住追它的导弹」。让小队进入防御姿态时像一支真正护着指挥官的编队，而不是一哄而散。

> ⚠ **术语更新（2026-07）**：本 spec 写成时 E 键 = 语义模糊的"规避模式"（无成本开关）。该键已被 [afterburner-mode](afterburner-mode.md)（充能制加力模式）**资源化改造**：现在 E = 加力模式的开关（有能量即启动 / 耗尽自动结束 / 可再按关闭）。**但本 spec 描述的僚机护卫机制完全不受影响**——加力启动内部仍调长机 `set_evasion_mode(true)`，照旧走 `_propagate_evasion_to_squad` 给僚机置 `escort_cover_active`。下文所有"按 E 进规避"读作"按 E 启动加力（长机进 evasion 态）"即可。

## 1. 设计意图（Why）

- **体验目标**：
  - 玩家按 E 进规避，期望"全队进入防御姿态"，而不是"僚机各自逃命、阵型瓦解、飞到天边"。
  - 僚机应表现出**护卫意识**：自身安全时贴着长机，长机有难时挺身投焰相救。
  - 解决现状缺口：当前 `_propagate_evasion_to_squad` 把 `evasion_mode=true` 广播给僚机 → `ai_controller` 守卫无条件 `enter_evade` → 哪怕僚机毫发无损、根本没被瞄，也走 `_process_scatter_evade` 朝散开扇形 max+AB 飞离（用户实测脱队飞 7km）。

- **Litmus 自检**（引 [DESIGN_PHILOSOPHY.md](../../DESIGN_PHILOSOPHY.md)）：
  - **原则 7（AI 要演戏 / 僚机协同）**：本特性正是该原则点名的"僚机喊 covering 扫长机后半球"的护卫语义落地——僚机替长机投焰是协同演戏的高光时刻。
  - **原则 3（信息察觉优先于数值）**：护卫焰有专属可见反馈（flare 粒子从僚机喷出 + 追长机的导弹被 jam 偏飞 + `ESCORT_FLARE` 日志），玩家一眼能看出"僚机救了我一命"。
  - **原则 5（武器抽象优先于真实）**：护卫焰复用既有 flare 概率干扰机制，不为它造新的"现实弹种"分类。
  - **原则 11（60 FPS）**：护卫扫描挂在僚机已有的 squad-follow 低频路径上，按实体数 × 低频估算，不新增每帧全场扫描。

- **反模式规避**：
  - 不破坏"一击毙命"：护卫焰只是**概率帮长机偏掉**追它的导弹，不给长机加 HP、不做无敌护盾（边缘距离近乎无效 + 单弹单次尝试）。
  - 不污染模式：纯走共享 AI/flare 层 + squad 关系，无 `if in_survivor` 分支。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 状态标志（新增）

| 字段 | 类型/默认 | 说明 |
|---|---|---|
| `Aircraft.escort_cover_active` | bool / false | 僚机护卫姿态标志。由长机按 E 时 `_propagate_evasion_to_squad` 广播置位；关 E 时清零。**与 `evasion_mode` 解耦**：护卫待命期间僚机 `evasion_mode` 必须保持 false，否则 planner 的 `Situation.evasion_intent` 会让它出 `EVADE_MISSILE` intent（max+AB）散开。 |

> 长机（玩家手控机）自身行为**完全不变**：按 E 仍置自己的 `evasion_mode=true`，保留自卫 flare / 眼镜蛇 / 赫尔贝特等全部既有机制。本 spec 只改僚机收到广播后的反应。

### 2.2 护卫 flare 数值

| 字段 | 值 | 说明 |
|---|---|---|
| `ESCORT_FLARE_LEADER_RANGE_M` | 800 m | 僚机距长机 ≤ 此值才能护卫投焰（约编队槽位尺度；超出 = 太远，焰云覆盖不到长机周边）。 |
| `ESCORT_BASE_JAM` | 0.70 | 僚机**紧贴**长机（距离≈0）时对追长机导弹的干扰概率上限。 |
| `proximity_factor` | `clamp(1 − d_leader / 800, 0, 1)` | 近度因子：贴脸 1.0 → 800m 处 0.0 线性衰减。 |
| `escort_jam_chance` | `ESCORT_BASE_JAM × proximity_factor` | 实际护卫干扰概率。例：距长机 200m → 0.70×0.75 = **0.525**。 |
| 单弹单次 | — | 每枚导弹**每架僚机只护卫尝试一次**（记在僚机的 `_escort_flare_tried` 集合，按导弹 instance_id）。失败后该僚机不再对这枚重试。 |
| 一次一架（全队裁决） | — | 同一枚追长机的导弹，**任一时刻只有一架僚机出手**：在「同队 + flare 就绪 + 距长机 ≤800m + 这枚对其同样合格（未试过）」的候选里，只有**离长机最近**的那架投焰（平局用 instance_id 决断，保证多架同帧 tick 恰好一架通过）。最近那架若 jam 失败（进 CD + 标记已试），下一帧次近的接手 → 顺序兜底、优先让 jam 概率最高的去做、绝不全队一起喷焰。 |
| 资源消耗（即 CD） | 僚机自己的 flare 弹量 + flare CD | 护卫投焰走僚机自身 flare 池与冷却（与自卫焰**共用** `_flare_cooldown`：F-16 1.5s / F-14 4.0s 等，见 .tres）。投一次即进 CD，期间该僚机护卫/自卫都不能再放；打光走 reload_time 装填。 |

### 2.3 复用的既有阈值（来自 [missile-evasion 现状]）

| 来源 | 字段 | 值 | 本 spec 用途 |
|---|---|---|---|
| `MissileEvasion` | `EVADE_MIN_CLOSING_MS` | 60 m/s | 判"僚机自己是否被真威胁追"（沿用现有威胁门）。 |
| `MissileEvasion` | `EVADE_TTI_THRESHOLD` | 3.5 s | 同上。 |
| `AircraftFlares` | `FLARE_MIN_CLOSING_MS` | 30 m/s | 判"长机是否即将被命中"（护卫触发用长机视角的 `player_flare_should_trigger`）。 |
| `AircraftFlares` | `FLARE_TTI_THRESHOLD` | 1.5 s | 同上：护卫焰是末段救援，只对即将命中长机的导弹投。 |
| `AircraftFlares` | `FLARE_MIN_DIST_M` | 300 m | 同上终端兜底。 |

## 3. 行为与公式（How）

### 3.1 僚机收到长机规避广播后的状态决策

替换现状"无条件 `enter_evade`"守卫。仅对**玩家方僚机**（team 0 + 有长机 + 非 BOSS 攻击手）生效；敌方/长机不走此分支。

| 条件（按序判定） | 行为 |
|---|---|
| `escort_cover_active` 且 **僚机自己被真威胁导弹追、且 flare 兜不住**（`should_enter_evade` 分层门：真威胁（`_is_evasion_threat`）**且** flare 不可用/该弹已被 flare 弃管/无免疫窗 —— flare 就绪时留在阵型由智能 flare 末段处理，**不进 EVADE**） | `enter_evade`（临时自保：照旧垂直规避 + 真威胁才 max+AB；`enter_evade` 内部才把 `evasion_mode` 设 true）。**需求 1 + B1 分层规避（2026-07-03）。** |
| `escort_cover_active` 且 自己没被真威胁 | **不进 EVADE**，落到正常 `SQUAD_FOLLOW` 路由（回编队槽位待命跟随）。在 squad-follow 内跑护卫焰扫描（见 3.2）。**需求 2。** |
| `escort_cover_active = false`（长机没在规避） | 完全走原有 AI 路由，行为不变。 |

> 僚机**自己被导弹追时本来就会自主规避**（既有 missile-aware → EVADE 路径，不依赖本广播），所以"被打才逃"在没按 E 时也成立；本 spec 只是让"按 E 时"不再绕过威胁判定强制散开。

### 3.2 护卫 flare 主循环（僚机在 squad-follow 待命时，低频检查）

```
前置门（任一不满足则跳过）：
  ac.team == 0 且 ac 是僚机（squad.leader 存在且 != ac）
  escort_cover_active == true              # 长机正在规避广播
  leader 存活
  d_leader = dist(ac, leader) ≤ 800m       # ESCORT_FLARE_LEADER_RANGE_M
  ac flare 就绪（flares_remaining>0 且 _flare_cooldown<=0 且未 JAM/隐身/机动中）

选目标：扫所有 active 导弹，挑【追长机】(m.target == leader) 且【即将命中长机】
  (AircraftFlares.player_flare_should_trigger(leader, m) 为真) 的最近一枚 m。
  跳过 m 已在 ac._escort_flare_tried 里的（单弹单次）。

全队裁决（一次一架）：仅当 ac 是这枚 m 的"最佳护卫者"才出手 ——
  遍历 squad.members 中同队就绪僚机（flare_ready（就绪门） + 距长机≤800m + 这枚对其合格），
  若存在比 ac 更近长机的候选 → ac 让位（return）。等距用 instance_id 决断。
  → 任一时刻同一枚导弹只一架投；最近那架失败(进CD+标记已试)后次近接手。

执行：
  记 ac._escort_flare_tried[m.id] = true
  AircraftFlares.release_cover(ac, leader, m)   # 喷焰粒子 + 消耗 flare/CD
    escort_jam_chance = 0.70 × clamp(1 − d_leader/800, 0, 1)
    if randf() < escort_jam_chance:
        m.is_flare_jammed = true               # 下一 tick find_nearest 过滤掉它，长机解除威胁
        log ESCORT_FLARE "covered <leader> jam=<chance>%"
```

- **频率**：挂在 `process_squad_follow`（僚机 AI tick，已分频 ≥10Hz 起），不新增每帧全场扫描；导弹遍历限于 missile_manager 子节点（与既有 flare 扫描同源）。
- **`_escort_flare_tried` 清理**：复用既有 `_flare_ignored_missiles` 的清理节奏（定期剔除失效 instance_id），避免集合无限增长。

### 3.3 与既有 flare / 难度的关系

- 护卫焰是**长机自卫焰之外的额外一层**：两层独立按概率 jam 同一枚导弹 → 提升长机末段存活率，但都受 `player_flare_should_trigger`（即将命中）门约束，不会对慢弹/远弹乱放。
- 单弹单次 + 近度衰减 + 消耗僚机自身弹量三重约束，防止"N 架僚机轮流 jam 同一弹 = 长机无敌"。

## 4. 结构与组成（Structure）

- **新增标志注入**：`Aircraft.escort_cover_active`（运行时 bool）。广播写入点在长机的 `_propagate_evasion_to_squad`（玩家按 E 时；僚机置 `escort_cover_active` 而非 `evasion_mode`）。
- **状态决策改造**：`ai_controller` 的规避广播守卫（现"无条件 enter_evade"）改为 §3.1 三分支。
- **护卫扫描**：`SquadCoordination.process_squad_follow` 内新增护卫焰检查（§3.2 前置门 + 选目标 + 调用）。
- **护卫投焰**：`AircraftFlares` 新增 `release_cover(ac, leader, missile)`——复用 `release` 的粒子/弹量/CD 逻辑，但 jam 判定目标改为"追 leader 的导弹"且用 `escort_jam_chance`（近度公式），不走 `calc_jam_chance`（那套是自卫视角的角度/机动加成）。
- **僚机状态字段**：`_escort_flare_tried`（Dictionary，instance_id → true）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 玩家按 E、僚机**未被任何真威胁导弹瞄准**时：僚机保持/回到编队槽位跟随长机，**不**加速散开、**不**飞离阵型（EventLogger 不出现该僚机的 `EVADE`/scatter；PLAN 不出现 `EVADE_MISSILE`）。
- [ ] 玩家按 E、某僚机**自己被真威胁导弹咬住**时：该僚机照旧 `enter_evade` 加速规避逃命（行为与现状一致）。
- [ ] 长机被即将命中的导弹追、附近（≤800m）有就绪僚机时：僚机投护卫焰（`ESCORT_FLARE` 日志），按 `escort_jam_chance` 概率把追长机的导弹 `is_flare_jammed`，长机威胁解除。
- [ ] 长机自卫焰行为不变；玩家手控机（长机）的 evasion_mode 自卫机制（cobra/herbst/智能焰）零回归。
- [ ] 难度防护：单枚导弹不会被同一僚机重复护卫；距长机 ~800m 边缘护卫概率趋近 0；护卫消耗僚机 flare 弹量。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（见 [performance-guidelines](../../reference/performance-guidelines.md)）。
- [ ] 已知 seam：检查 SEAM-011（长机相对量勿缓存成 AI 分频死点）——护卫触发读 leader 实时位置/导弹，勿缓存（见 [known-seams](../../architecture/known-seams.md)）。
- [ ] i18n：`ESCORT_FLARE` 是 EventLogger 日志（豁免 tr）；若未来加 HUD 提示再走 tr()。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 解耦广播标志（修"无脑散开"）
- [x] `Aircraft` 加 `escort_cover_active: bool = false`（+ `_escort_flare_tried`）。
- [x] `_propagate_evasion_to_squad`：给僚机置 `escort_cover_active = enabled`（不再 `set_evasion_mode`）；长机自身仍 `evasion_mode=true` 不变。
- [x] `ai_controller` 规避广播守卫改 §3.1：`escort_cover_active` + 僚机 + 非 boss → 自己被真威胁(`check_incoming_missile`)才 `enter_evade`；否则无命令机召回 SQUAD_FOLLOW 待命，命令机落铁律继续交战。
- [x] `MissileEvasion.process_evade` 无导弹分支：废除 scatter-on-broadcast，自身威胁解除即清 `evasion_mode` + `exit_evade` 归队；删 `_process_scatter_evade` + SCATTER 常量 + 死字段。
- [ ] 验证（playtest）：按 E 后未被瞄僚机留编队（log 无 scatter）；被瞄僚机仍规避。

### 阶段 2 — 护卫 flare 机制
- [x] `AircraftFlares.release_cover(ac, leader, missile, d_leader_m)`：粒子/弹量/CD 复用 `release`；jam 判定对 `missile.target == leader`，概率用 `escort_jam_chance = ESCORT_BASE_JAM × proximity`；成功置 `is_flare_jammed` + `ESCORT_FLARE` 日志。
- [x] `AircraftFlares.try_cover_flare(ac, leader)`：前置门 + 选目标（追 leader + `player_flare_should_trigger(leader,m)` + 未尝试过最近一枚）+ 调 `release_cover`。
- [x] `Aircraft._escort_flare_tried` 字段 + 复用既有 ignored-missile 清理节奏。
- [x] `SquadCoordination.process_squad_follow` 加 §3.2：`escort_cover_active` → `AircraftFlares.try_cover_flare`。
- [ ] 验证（playtest）：长机被追、僚机在 800m 内 → 出 `ESCORT_FLARE` + 导弹被 jam；边缘距离概率趋零；单弹不重复。

### 阶段 3 — 收尾
- [x] 护卫 bench（`--bench=escort`，`scripts/tests/test_escort_evasion.gd`）**24/24 通过**：jam 概率公式 / flare 就绪门 / 目标合格判定 / 「一次一架」全队裁决（含 CD 兜底·超界排除·平局决断）/ **端到端**（真实 missile_manager 扫描→裁决→投焰→消耗 flare→进 CD→单弹单次）/ **jam 应用率**（贴脸 3000 发 ≈ 0.69）。
- [x] flare 单元 bench（`--bench=flare`）9/9 通过（既有威胁门未回归）；全项目编译干净。
- [ ] 跑 Sentinel + Lv5+ 压测确认 60 FPS（playtest）。
- [x] 同步 `script-index.md` / `code-index.md`；写 `docs/changelogs/` 当日记录 + `player-ai-log.md`。
- [x] `_INDEX.md` 总表登记；本 spec `reconstruction_complete: true`，待 playtest 后转 `done`。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 广播标志 / 长机 evasion | `scripts/aircraft.gd`（`_propagate_evasion_to_squad` / `set_evasion_mode`） |
| 僚机状态决策守卫 | `scripts/ai_controller.gd`（规避广播守卫 + state dispatch） |
| 护卫焰主循环 | `scripts/ai/squad_coordination.gd`（`process_squad_follow`） |
| 护卫投焰 + jam | `scripts/aircraft/aircraft_flares.gd`（新增 `release_cover`） |
| 自身规避机动 | `scripts/ai/missile_evasion.gd`（`enter_evade` / `find_nearest_incoming_missile` / `_is_evasion_threat`） |
| reference 索引行 | script-index.md（aircraft_flares / squad_coordination / ai_controller 行）+ code-index.md（规避 / flare 主题） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-06-15 | 1 | 初稿（draft）：定义 escort_cover_active 解耦 + 护卫 flare 机制 + 三分支决策。待用户定稿。 |
| 2026-06-16 | 2 | 用户定稿（护卫概率 0.70/范围 800m 采纳）→ 阶段 1+2 代码落地：解耦广播标志、三分支守卫（含召回编队）、废除 scatter-on-broadcast、`try_cover_flare`/`release_cover`。flare bench 9/9 通过、编译干净。剩 playtest（§5）转 done。 |
| 2026-07-03 | 3 | B1 分层规避（用户定稿，见 planning/physics-ai-control-refactor.md §3）：全部 `enter_evade` 入口（含 §3.1 广播分支、ENGAGE/PATROL/SQUAD_FOLLOW）统一走 `should_enter_evade` 三层门——真威胁 + flare 可用 → 只扔 flare 不脱队；flare 不可用才运动学规避；躲弹期间命令铁律让位但有界（威胁消失立即恢复命令目标）。就绪门 `_escort_flare_ready` 改名 `flare_ready` 三方共用。验收：`--bench=cmd_evade` 23/23 + `--bench=escort` 24/24。 |
