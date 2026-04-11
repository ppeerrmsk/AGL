# 导弹系统

## 概述

SARH（半主动雷达制导）导弹系统，类似 AIM-7 麻雀。发射机必须持续雷达照射目标，导弹才能制导飞行。导弹使用比例导引律（Proportional Navigation）追踪目标。

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

## 导弹飞行物理（missile.gd）

每帧 `_physics_process` 流程：

```
1. 累加 age → 超时则 is_active = false
2. 动力阶段：age < motor_burn_time → 加速；否则减速
3. 能量耗尽：speed < 80 m/s → is_active = false
4. SARH 照射检查：source.radar_targets[target] >= lock_time → 有制导
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
4. **射程包线**（`_is_in_missile_envelope`）：检查距离、TAA、高度差
5. **发射后 Crank**：进入 `CRANK_DURATION`（8秒）保持照射阶段

### 机炮更优判定（`_should_use_gun`）

仅在距离 < 机炮射程 × 0.8 时返回 true。非常严格，防止模式震荡。

## 与现有系统的集成

### AircraftParams 修改

新增：
```gdscript
@export_group("导弹")
@export var missile: MissileParams
```

### aircraft.gd 修改

- `_physics_process` 新增 `_update_weapon_mode()` 作为第一步
- `_update_bank`：导弹模式按三阶段调整坡度限制
- `_update_energy_management`：导弹模式按三阶段调整速度和加力策略
- `_update_combat`：导弹模式按三阶段调整追踪点
- 数据标签新增 `MSL X` 显示

### main.gd 修改

- 注入 `missile_manager` 引用到每架飞机
- 每帧同步 `missile_manager.aircraft_list`

### main.tscn 修改

- 新增 `MissileManager` 节点

### 资源文件修改

- `default_fighter.tres` / `enemy_fighter.tres`：引用 `default_missile.tres`

## 雷达参数调整

为配合导弹系统，雷达探测距离从原来的 700m/560m 大幅提升：

| 机型 | 雷达探测距离 | 锥角 | 锁定时间 |
|------|-------------|------|----------|
| F-16 | 5000px = 10km | ±30° | 2.5s |
| MiG-29 | 4000px = 8km | ±25° | 3.5s |

## 待实现

- 主动雷达导弹（ARH）：发射后不管，不需要持续照射
- 红外导弹：追热源，可被曳光弹干扰
- 导弹规避 AI：检测来袭导弹，执行规避机动
- 箔条/曳光弹反制
- 多目标同时制导（需新导弹类型支持）
