# 2026-04-29 — 对地 strafe pass 状态机 + 低空 q-limit 反转

## 背景

玩家反馈两个互相耦合的问题：

1. **对地 strafe 钟摆**：F-16 低空 strafe AAA 时，进入即 84° 压杆 + 10G + 600 m/s，距离从 1.6km 单调拉到 6km+，从未咬上目标。物理诊断：F-16 在 580 m/s 下 10G 转弯半径 ≈ 3460m，几何上吃不下 1.6km 处的目标。
2. **低空速度比高空快接近一倍**：海平面 max ≈ 2100 km/h，15000m max ≈ 870 km/h。和真实战机刚好相反。

## 改动

### 1. `max_speed_at_altitude` 反向（q-limit 模型）

[scripts/aircraft/aircraft_physics.gd:558](../../scripts/aircraft/aircraft_physics.gd:558)

**旧公式**：`v = max_spd × sqrt(exp(-altitude/8500))` —— 海平面拿满 max，高空衰减到 41%。
**新公式**：超音速机 `v = max_spd × lerp(0.7, 1.0, alt/5000)`，海平面 70%、5000m+ 拿满 published max；**亚音速机（max_speed < 1300）跳过 q-limit**（结构动压上限只对超音速有意义）—— 含 F-86 / A-7 / Tu-160 / AH-64 / CH-47。

效果（基础 max_speed=2100 km/h 的 F-16）：

| 高度 | 旧 | 新 |
|---|---|---|
| 0m | 2100 | **1470**（≈ Mach 1.2） |
| 2500m | 1916 | 1785 |
| 5000m | 1741 | **2100** |
| 12000m | 1037 | 2100 |

**俯冲速度奖励保留**：[update_speed:394-397](../../scripts/aircraft/aircraft_physics.gd:394) 的 PE→KE 耦合在 max cap 之后施加，从高空俯冲到低空仍可短暂顶破 q-limit cap，逐渐被减速消耗。

加速度 (`params.acceleration`) 和 AB 推力 (`afterburner_thrust_mult`) 不动。

### 2. `ground_strafe` 状态机

[scripts/ai/tactical/bfm_intent.gd:272](../../scripts/ai/tactical/bfm_intent.gd:272)

机炮分支按几何分三个子状态（同一 `Intent.GROUND_STRAFE`，rationale 区分）：

| 子状态 | 进入条件 | speed | AB | 行为 |
|---|---|---|---|---|
| **SETUP / REENTRY** | `aim_align < cos(30°)` | `corner_speed_kmh` | 关 | corner speed 转弯对准目标 |
| **RUN** | 机头对准 + 远距 | `clamp(cruise×1.4, …, max×0.75)` | 当前 < 目标×0.95 | 直冲 strafe pass |
| **BREAK** | `dist < gun_range×0.4` 且 `closing < -50` | `cruise × 1.1` | 关 | `pursuit_pos = my_pos + my_fwd × 3km` 直线脱离 |

叠加 q-limit 后 F-16 海平面 RUN 入场速度 ≈ `min(1.4×900, 0.75×1470) = 1102 km/h ≈ Mach 0.9`，瞄准窗口够长，可咬住 1.6km 处目标。

导弹分支不变（`cruise×1.15` 不开 AB）。

### 3. UI 介绍同步

[i18n/translations.csv](../../i18n/translations.csv) 三个 key 改写（中/英/日同步）：

- `TOOLTIP_ALT_CLIMB_BODY`：加 "空气稀薄阻力小，顶速更高" 一行
- `TOOLTIP_ALT_LOW_BODY`：删 "顶速更高，适合突击与脱离"，改为 "空气稠密阻力大，顶速较低；从高空俯冲过来可短暂保留速度优势"
- `TACTICAL_TIP_ALT_HIGH/LOW`：同方向重写

### 4. 单元测试

[scripts/tests/test_bfm_intent.gd](../../scripts/tests/test_bfm_intent.gd)

- `test_ground_strafe_charge_uses_max_speed`：原断言 "speed 接近 max"，改为 "speed 受 max×0.75 cap"
- `test_naval_target_uses_strafe`：同上
- 新增 `test_ground_strafe_setup_when_off_axis`：目标在 90° 侧方 → corner speed + 关 AB
- 新增 `test_ground_strafe_break_when_overshoot`：目标在身后 200m → pursuit_pos 在前方而不是 tgt

## 受影响范围

- ✅ 玩家所有主角机（F-16 / F-14 / 后续）
- ✅ 9 种迁移到 TacticalPlanner 的 AI 战机（MIG / F86 / A7 / Q5 等）
- ❌ Apache（走 `update_combat_ground_attack`，不经 planner，0 影响）
- ❌ 未迁移机型（F-47 BOSS / Adds / Sentinel）
