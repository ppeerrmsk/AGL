# 2026-07-07 — 对面攻击 pass 循环（根治机炮打地面绕圈）

> spec: [systems/surface-attack-pass](../specs/systems/surface-attack-pass.md)（spec_version 2, status in-progress）

## 背景

用户反馈（log 20260707_221548）：指挥友机机炮打 SAM（RNG=376m）时，飞机**死活绕圈 47 秒**，
`对地 SETUP：转弯对准目标 (off=70°)` 从不收敛。

**根因**：现 `ground_strafe` 机炮分支只有 SETUP/RUN/BREAK 三态，缺"最小转弯半径守卫"。
快机在 corner 速度下最小转弯半径 500~1000m，目标钻进转弯圆内（376m ≪ r）时机头永远扫不到 →
永远 SETUP；唯一出口 BREAK 需 `closing<-50`，稳定绕圈时闭合率≈0 → BREAK 永不触发 → 死循环。
同类病空中侧 planner 优先级 5.9 早已根治，但那段写死 `not s.tgt_is_surface` 把地面排除在外。

## 改动

把 `ground_strafe` 重写成**姿态驱动的 pass 循环**（SETUP → RUN → EGRESS），
地面/舰船共用骨架，导弹机炮由姿态分流：

| 姿态 | 触发（AUTO=武器竞选） | 打法 | 高度 |
|---|---|---|---|
| **ASSAULT** | weapon=GUN（含出弹/锁炮/冲锋） | 俯冲穿越目标扫射 → 飞越 → 拉起折返 | 俯冲到 `tgt_alt` |
| **STANDOFF** | weapon=MISSILE | 高位进导弹包络就发射 → 够近前脱离 → 不进 AA | 保持 MID |

**默认姿态直接取武器竞选结果** → 天然实现"有弹保持距离/无弹机炮"，无需单独弹药判断；
`Situation.attack_posture` 预留 command-wheel phase 4 覆盖钩子（本期恒 AUTO）。

**绕圈根治**：加最小转弯半径守卫 `min_turn_r = corner²/(g·7)`，
`dist < min_turn_r × 1.5`（目标在转弯圆内）→ 直接 EGRESS 拉开，而非 SETUP 硬转。
EGRESS 提交到 `dist ≥ reentry`（ASSAULT ≈1.5km / STANDOFF 夹在导弹射程内）才折返 → 完整通场循环。

**相位状态位** `Aircraft._strafe_pass_phase` 走既有 `_apply_tactical_plan` 回写通道
（与 `_bfm_prev_intent` 同款），planner 保持纯函数、零新增每帧扫描。

### 实现前自审修的 3 处数值 bug（见 spec §8 v2）
- C1：SETUP→RUN 去掉 `dist≤outer` 门（远距对准也全速闭合，开火另由包络把关）
- C2：`inner = min(inner, outer×0.6)` 守卫（防短射程 AGM 反向带宽死锁）
- C3：reentry 分姿态、去掉 `outer×1.3`（STANDOFF outer=8km 会算出 10km 折返）

### 触及文件
- `scripts/ai/tactical/bfm_intent.gd`：重写 `ground_strafe` + `_surface_altitude` + 8 个 `SURFACE_*` 常量
- `scripts/ai/tactical/tactical_plan.gd`：`SurfacePhase` 枚举 + `strafe_pass_phase` 字段 + `surface_phase_name`
- `scripts/ai/tactical/situation.gd`：`strafe_pass_phase` + `attack_posture(POSTURE_*)` 字段 + `from_aircraft` 读入
- `scripts/aircraft.gd`：`_strafe_pass_phase` 字段 + `_apply_tactical_plan` 回写
- `scripts/tests/test_bfm_intent.gd`：BREAK 测试改 EGRESS 语义 + 新增 3（绕圈根治/STANDOFF 不俯冲/折返循环）
- `scripts/tests/test_surface_pass.gd`（新）：无头行为 sim（真实物理步进）；`scripts/bench/bench_runner.gd` 注册 `surface_pass`

## 范围
- ✅ 玩家指挥机（走 planner）+ 已迁移 AI 对地攻击机 + 舰船（`tgt_is_surface`）
- ❌ Apache 专用 `aircraft_combat_tracking.update_combat_ground_attack`（`_strafe_state`，不经 planner）— 未动

## 无头行为 sim 暴露并修的 3 处物理 bug（spec v3）

新增 `scripts/tests/test_surface_pass.gd`（`--bench=surface_pass`，真实物理步进 + planner 路径，
模型同 test_joust）。单测（纯几何）过、但行为 sim 揭出三个只有步进物理才暴露的问题：

| # | 症状（sim 实测） | 修法 |
|---|---|---|
| 1 | ASSAULT 机炮**打不到地面**：最低仅 4211m | EGRESS/SETUP 不再爬回 MID，ASSAULT **全程贴 `tgt_alt`**（min 4211→**9m**） |
| 2 | STANDOFF 导弹**穿过目标**：min dist 1m | EGRESS 方向改**背离目标径向**（`-to_target_dir`），非沿机头（头朝目标时会穿过） |
| 3 | STANDOFF 180 折返 **coast 冲进 AA**：min 156m | EGRESS 用 **corner 硬 break**（收紧半径）+ STANDOFF 改**远距 standoff 环脱离**（`missile_max×0.5`），min 156→**1395m** |

## 病例2 修复（2026-07-11，spec v4）—— 命令打 6km 对舰 STANDOFF 绕圈背飞

log 20260711_205142：玩家用命令轮盘集火 6.2km 外的 FFG-753，本机（Ultra）进 `SETUP[STANDOFF]`
后 40+ 秒绕圈不收敛，距离 6→9km 漂移、方位角扫整圈、背对目标慢飞。

**诊断（无头 sim 复现）**：新增 `test_surface_pass.gd` 场景 C（6km 对舰、初始背对、弹程 16km）。
sim 证明 **SETUP 本身 9s 内收敛**（用户"SETUP 不收敛"的假设被证伪），真正根因是 v3 把 STANDOFF
`inner`（脱离/折返环）设成**远环 `missile_max×0.5`**：命令打**环内**目标（6km < 环 8km）时，一进 RUN
就 `dist≤inner` → 立即 EGRESS 背身外逃到 reentry(9km) → 20s 绕圈背飞。

**修法**：
| # | 改动 | 效果（sim） |
|---|---|---|
| 1 | `inner` 改固定近距 `STANDOFF_INNER_M=2200m`（"别飞更近"，非"退到远环"） | 命令打 6km 对舰 → 压入 6→2.2km 全程开火（min 1700m，不外逃） |
| 2 | STANDOFF EGRESS 改**侧向 beam break**（⟂LOS 朝机头侧 −0.5·LOS） | 原 180° 径向反转 head-on coast min 421m → beam ~90-120° 转向 |
| 3 | STANDOFF RUN 逼近脱离环（`dist<inner×1.6`）预减速 corner | 高速进 break 半径大 coast → 减速收紧 break 弧 |

触及：`bfm_intent.gd`（`SURFACE_STANDOFF_INNER_M` 常量 + envelope/EGRESS/RUN 分支）；
`test_surface_pass.gd`（场景 C 病例2 回归 + B 改真实偏轴起手）。

## 验收
- ✅ `--bench=surface_pass` **14/14**：A 机炮绕圈根治（4 pass / 俯冲 9m / U 转弯 10.2s 非 47s 死锁）；
  B 导弹 100% MISSILE + 守住 1168m standoff；**C 病例2：6km 对舰 off-axis 压入 1.7km 开火、不外逃（max 6845m）**
- ✅ `--bench=bfm_intent` 102/102（含 3 新 surface 断言）
- ✅ `--bench=all` 回归门 18 项全绿
- ⏳ 差生存模式 playtest：指挥机炮打 SAM 手感 + 导弹机 standoff 手感（spec §5）

## 已知取舍
- EGRESS 为纯函数无地图边界，未做 joust 那样的 edge-lerp（靠 reentry 折返避免飞出图）。若 playtest
  出现贴图边脱离飞出，再把 map 边界注入 Situation。
- pass 循环与 `JoustController`（空中动目标）功能重叠但服务不同路径（planner intent vs ai_controller 钩子）。
  长期可考虑合并为统一 pass 原语。
