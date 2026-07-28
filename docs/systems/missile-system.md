# 导弹系统

> 最后校订：2026-07-26。本文是**架构叙述**；各弹种的具体数值看 `resources/*.tres` 与
> [reference/resources-catalog.md](../reference/resources-catalog.md)，
> 使用准则看 [specs/systems/weapon-employment-doctrine](../specs/systems/weapon-employment-doctrine.md)。

## 概述

导弹用比例导引律（Proportional Navigation）追踪目标。

⚠ **AGL 不做现实武器分类**（红外 / 半主动 / 主动 各写一套逻辑）——所有导弹共用同一套
制导 / 命中 / 规避逻辑，差异只体现在参数上（DESIGN_PHILOSOPHY 原则 5）。
默认弹种需要发射机持续照射（`fire_and_forget = false`）；把 `fire_and_forget` 设为 true
即得到"发射后不管"的弹（QMAAM 等副槽武器就是这么做的），**不需要新的制导代码路径**。
`SARH` / `ARH` 这类术语只是命名风味，不构成机制约束。

## 文件结构

| 文件 | 职责 |
|------|------|
| `scripts/missile_params.gd` | MissileParams Resource：导弹性能参数定义 |
| `scripts/missile.gd` | Missile 实体：飞行物理、PN 制导、烟迹绘制 |
| `scripts/missile_manager.gd` | MissileManager：导弹生成、命中检测、在飞查询 |
| `scenes/missile.tscn` | 导弹场景（Node2D + missile.gd） |
| `resources/default_missile.tres` | AIM-7M 默认参数配置 |

## 参数（MissileParams）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `max_speed` | 1400.0 m/s | 最大飞行速度（约 Mach 4） |
| `motor_burn_time` | 6.0 s | 发动机燃烧时间 |
| `motor_acceleration` | 200.0 m/s² | 燃烧阶段加速度 |
| `drag_deceleration` | 15.0 m/s² | 燃尽后减速率 |
| `max_g` | 35.0 | 导弹最大过载 |
| `nav_constant` | 4.0 | 比例导引常数 N |
| `max_range_rear` | 15000.0 m | 后半球最大射程 |
| `front_rear_ratio` | 4.0 | 前/后半球射程比 |
| `min_range` | 500.0 m | 最小射程（引信武装距离） |
| `max_lifetime` | 60.0 s | 绝对存活时间 |
| `damage` | 80.0 | 命中伤害 |
| `proximity_fuse_radius` | 20.0 m | 近炸引信半径 |
| `proximity_fuse_alt` | 200.0 m | 高度容差 |
| `guidance_delay` | 0.5 s | 发射后制导启动延迟 |
| `max_count` | 2 | 挂载数量 |
| `cooldown` | 3.0 s | 发射间隔 |

后续追加的字段（默认值以 `missile_params.gd` 为准）：

| 参数 | 说明 |
|---|---|
| `seeker_fov` | 导引头视场角（度）|
| `intercept_hp` | 被拦截需要的伤害（激光 / CIWS 打导弹用）|
| `fire_and_forget` | true = 发射后不管，不再检查发射机照射 |
| `launch_toward_target` | 发射瞬间朝目标方向而非机头方向 |
| **副武器槽专用** | `target_filter`（AIR/GROUND/SHIP/MISSILE 位域）/ `lock_cone_half_angle_deg` / `lock_max_range_px` / `target_priority` —— 见 [aircraft-system.md](aircraft-system.md) |
| **VLS 齐射**（舰船垂发） | `is_vls_salvo` / `vls_salvo_size` / `vls_salvo_interval` / `vls_salvo_cooldown` / `vls_point_scatter_px` / `vls_climb_time` / `vls_transition_time` / `vls_transition_turn_rate_degs` / `vls_speed_variance` |

## 导弹飞行物理（missile.gd）

每帧 `_physics_process` 流程：

```
1. 累加 age → 超时则 is_active = false
2. 动力阶段：age < motor_burn_time → 加速；否则减速
3. 能量耗尽：speed < 80 m/s → is_active = false
4. 照射检查：`fire_and_forget` 为 false 时要求 source.radar_targets[target] >= lock_time → 有制导
   （`fire_and_forget = true` 跳过此检查；导弹入云也会丢制导）
5. 比例导引（PN）：
   - LOS 角速率 = (当前LOS角 - 上帧LOS角) / delta
   - 指令加速度 = N × V_closure × ω_LOS
   - 近距 < 200m 切换为纯追踪（防 PN 振荡）
6. 高度趋近目标
7. 位移更新
8. 烟迹记录
```

### SARH 特性

- 零修改现有雷达代码，导弹每帧查询 `source.radar_targets[target]`
- 发射机保持锁定 → 导弹有制导
- 发射机转向 / 目标脱离锥体 → `radar_targets` 自动清零 → 导弹失去制导，直飞至能量耗尽

### 视觉

- 弹体：小菱形（~5px），橙色（友方）/ 红色（敌方）
- 烟迹：灰白色渐隐线段（最多 50 点）
- 发动机火焰：燃烧阶段尾部闪烁三角

## 命中检测（missile_manager.gd）

- 每帧遍历所有在飞导弹 × 所有敌方飞机
- 条件：2D 距离 < proximity_fuse_radius × PIXELS_PER_METER **且** 高度差 < proximity_fuse_alt
- 引信武装：age > guidance_delay 后才激活
- 命中后调用 `aircraft.take_damage(damage)`

## 武器模式系统（aircraft.gd）

### WeaponMode 枚举

```
enum WeaponMode { MISSILE, GUN }
```

### 模式切换规则（`_update_weapon_mode`，每帧最先执行）

```
无导弹 → GUN
Crank 阶段 → 强制 MISSILE
当前 GUN 且有导弹 → 距离 > 机炮射程×2 才切回 MISSILE（滞后防震荡）
当前 MISSILE → 距离 < 机炮射程×0.8 才切 GUN
```

核心原则：**有导弹就贯彻导弹策略，只有非常近才切机炮。**

### 导弹交战三阶段（`_get_missile_phase`）

| 阶段 | 条件 | 机动 | 速度 | 追踪策略 |
|------|------|------|------|----------|
| **0 接近** | 目标不在雷达锥内 | 积极（与机炮相同） | 接近速度，可加力 | 前置拦截 |
| **1 照射** | 目标在锥内，锁定累积中 | 适度稳定（20-60%坡度） | 巡航，无加力 | 平滑前置跟踪 |
| **2 保持** | 已锁定 / crank | 极稳定（10-35%坡度） | 巡航×0.95，无加力 | 直追目标 |

### 发射逻辑（`_update_missile`）

1. **目标选择**（`_select_best_missile_target`）：从所有雷达锁定目标中选出**唯一最优**的一个
   - 评分权重：机头偏差 35% + 距离 25% + 闭合率 25% + 锁定时间 15%
   - 路过的目标（闭合率负、偏差大）得分低，不会被选中
2. **单目标约束**：同一目标已有在飞导弹 → 不发第二枚，等结果
3. **锁定稳定缓冲**：锁定后额外等待 `LOCK_STABLE_BUFFER`（1秒）才允许发射
4. **射程包线**（`_is_in_missile_envelope`）：检查距离、TAA、高度差。
   高度差 >5000m 拒发**仅对空中目标**（拦 yoyo/extension 过渡态盲发）；面目标（地面/舰船）
   豁免——STANDOFF 学说的 MID 上半带（>5000m）与玩家爬升偏好曾恒触此门导致对地导弹
   无声永拒（2026-07-26，log 20260726_165536）
5. **发射后 Crank**：进入 `CRANK_DURATION`（8秒）保持照射阶段

### 机炮更优判定（`_should_use_gun`）

仅在距离 < 机炮射程 × 0.8 时返回 true。非常严格，防止模式震荡。

## 与其它系统的关系

- **AircraftParams** 通过 `missile`（主槽）/ `secondary_missile`（副武器槽 SP）两个字段挂载弹种；
  新机型也可以走 `equipment` 数组（模块化装备系统）。
- **Aircraft** 侧的武器模式切换、三阶段追踪、bank/能量策略在 `scripts/aircraft/`
  的 `aircraft_weapons.gd` / `aircraft_combat_tracking.gd` / `aircraft_physics.gd`，
  见 [aircraft-system.md](aircraft-system.md)。
- **MissileManager** 由场景持有，负责生成 / 命中检测 / 在飞查询；
  AI 的来袭导弹检测（`ai/missile_evasion.gd`）也查它。
- **发射决策**（什么距离用什么武器、瞄准语义、发射门）归
  [weapon-employment-doctrine](../specs/systems/weapon-employment-doctrine.md)。

具体代码位置查 [reference/code-index.md](../reference/code-index.md) 的"武器系统 — 导弹"段。

## 已实装的相关机制

早期版本这里列过一张"待实现"表，其中绝大多数早已落地，现状如下：

| 早期条目 | 现状 |
|---|---|
| 主动雷达导弹（发射后不管） | ✅ `MissileParams.fire_and_forget` |
| 红外导弹 / 弹种差异化 | ⚠ **刻意不做**分类逻辑，差异一律走参数（原则 5）|
| 导弹规避 AI | ✅ `ai/missile_evasion.gd`（分层门 + 热诱弹优先不脱队策略）|
| 曳光弹 / 热诱弹反制 | ✅ FlareParams + `aircraft_flares.gd`，带 `fail_chance` |
| 多目标同时制导 | ✅ 多锁齐射 / 协同齐射（主槽；副槽是"特殊一发"语义，刻意不做齐射）|

> 本段只作历史澄清，**不要**再往这里追加新的 TODO —— 待办归 spec 的 §6 实现计划。
