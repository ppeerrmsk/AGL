# 2026-07-28 修"整支航母舰队都在旋转"

**症状**（玩家实机）：航母战打到一定程度后，Ladon 战斗群整支舰队原地转圈。

## 根因

护卫舰是**刚体跟随**旗舰（`NavalUnit._update_formation_follow` 直接复制 `leader.heading`、
按 `formation_offset` 摆位），而旗舰走的是**直线往返 + 端点 180° U-turn**：

| 量 | 值 |
|---|---|
| CV 航速 | 7 m/s = **3.5 px/s** |
| CV `turn_rate` | **0.05 rad/s**（2.86°/s）→ 掉一次头 **63 秒** |
| 巡逻半程 | 1500 px → 到端点要 1500 / 3.5 ≈ **7 分钟**（＝"打到一定程度"） |
| 最外圈护卫舰偏移 | `(1100, ±900)` → r = **1421 px** |
| 掉头时该舰的切向线速度 | 0.05 × 1421 = **71 px/s ≈ 510 km/h**，自身航速的 **20 倍** |

即：每 7 分钟，整支 2.8 km 宽的舰队会以 2.86°/s **原地自转 63 秒**，最外圈护卫舰按超音速划圈。
同一套"直线往返 + 刚体跟随"也用在战区海上任务（`zone_mission` 1★/2★/3★，偏移最大 2400 px），同病。

## 改动

### 1. `scripts/naval/naval_unit.gd` —— 通用闸：旗舰转速按编队尺度收紧

- 新增 `FORMATION_TANGENTIAL_CAP_PXS = 8.0`（px/s ≈ 16 m/s ≈ 31 kn）与 `_effective_turn_rate()`：
  有僚舰时 `ω ≤ 8 / r_max`，**无僚舰的独立船原样透传 `params.turn_rate`**（行为零变化）。
- 僚舰每帧在 `_update_formation_follow` 里**自注册**到 leader 的 `_followers`
  （5 个调用点都是直接写 `formation_leader` 字段，统一在这里兜住）；leader 侧顺带剔除死/换队的僚舰。
- 新增**环形巡航模式** `patrol_center` / `patrol_radius`（+ `PATROL_LOOKAHEAD_RAD = 0.25` 前视 carrot）：
  绕圆心恒定盘旋，稳态角速度恒为 `v / R`，**永远不会掉头**。`patrol_center = INF` 时该模式关闭。

### 2. `scripts/survivor/carrier_strike_group.gd` —— CSG 旗舰改盘旋

- `CV_PATROL_HALF_SPAN = 1500`（直线往返）→ `CV_PATROL_RING_RADIUS = 750`（盘旋半径）。
  CV 出生点放在圆周上（锚点左舷 750 px），初始 heading 恰好是切线 → **无入圈瞬态**。
- 整队转位角速度实测 **0.32°/s**（约 19 分钟一圈），最外圈护卫舰对地 **10.6 px/s** ——
  相对旧行为分别是 1/9 和 1/7。舰队外缘 750 + 1421 ≈ 2170 px，仍在 `BOSS_RADIUS = 2200` 内。
- **摆位地形校验改成对朝向不变**：舰队现在会缓慢转过整圈，只查一个朝向 = 只保证"出生那一刻不搁浅"。
  `_score_placement` 改为 **6 个转位 × (CV 圆周位 + 10 护卫位)**；候选朝向枚举随之删除
  （评分已对朝向不变，扫朝向纯浪费），候选锚点从 5 个扩到 9 个（正交 1800 + 对角 1270）。

### 3. `scripts/tests/test_naval_formation.gd`（新）—— bench key `naval_formation`

逐帧真步进 `NavalUnit._update_movement`（60 Hz），不做几何近似：

- **A. CSG 环形巡航**（15 分钟步进）：转位 ≤ 0.35°/s、僚舰对地 ≤ 12 px/s、圆周半径误差 ≤ 120 px、
  离锚点 ≤ 2450 px、确实在盘旋（≥ 0.5 圈）、**全程无掉头**。
- **B. 直线往返 U-turn 兜底**（覆盖战区海上任务）：即便旗舰仍走 waypoints 掉头，
  僚舰对地速度也 ≤ 12 px/s；并断言**旧行为确实超标**（71 px/s 回归基准）。
- **C. 独立单船**：`_effective_turn_rate()` 原样返回 `params.turn_rate`。

结果：10/10 绿；`--bench=all` **43 项全绿**。

## 为什么不是"让护卫舰各自用真实物理归位"

护卫舰顶速只比航母高约 30%（FFG 9 / DDG 10 / CG 8 vs CV 7 m/s）。任何**转弯半径小于编队尺度**的
机动在物理上都无解 —— 外圈舰要在同样时间里多跑 π × 1400 px。唯一物理自洽的解法是
**把转弯半径放大到编队尺度以上**，即恒定大圆盘旋；刚体跟随本身反而是对的（舰队就该像一个整体航行）。

## 文档同步

- [specs/systems/boss-hunter-doctrine.md](../specs/systems/boss-hunter-doctrine.md) §2.5 表 + §2.5.1
  新增 **(c) 舰队运动：直线往返 → 恒定盘旋**，并改写 (a) 摆位校验规则。
- [reference/code-index.md](../reference/code-index.md)：CSG 摆位/盘旋 4 行 + 海上单位段 4 行（含新测试）。
- [reference/script-index.md](../reference/script-index.md)：新增 `tests/test_naval_formation.gd` 一行。

## 待办

- [ ] playtest：实机看一遍 CSG 战全程（尤其"舰队转过 90° 之后有没有护卫舰蹭岸"）。
- [ ] 战区海上任务（`zone_mission` 1★/2★/3★）目前只吃到通用闸（不再甩僚舰），
      旗舰仍是直线往返；若 playtest 觉得那里的掉头也别扭，可同样改成环形巡航。
