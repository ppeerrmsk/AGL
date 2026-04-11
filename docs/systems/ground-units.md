# 地面单位参考

## 概述

地面单位（GroundUnit 子类）高度固定为 0（GROUND 档位），可缓慢地面移动，拥有雷达和武器系统。

---

## 类继承

```
CombatUnit
└── GroundUnit          # 地面基类
    ├── SAMUnit          # 防空导弹车
    ├── AAGunUnit        # 高射炮
    └── RadarStation     # 雷达站
```

---

## GroundUnit 基类

**文件**: `scripts/ground_unit.gd`

### 导出属性

| 属性 | 说明 |
|------|------|
| `params` | AircraftParams（复用飞机参数提供雷达/机炮配置） |
| `initial_heading_deg` | 初始朝向 |

### 移动系统

- `max_ground_speed`: 5.0 m/s（极慢）
- 支持路径移动（waypoints）
- 支持车队跟随（convoy_leader + convoy_follow_distance）
- 转向速率 1.0 rad/s

### 自动目标选择

从 `radar_targets` 中选最近的已锁定敌方单位。

### 战斗（机炮）

与 Aircraft 机炮逻辑类似：
- 射程检查 (×1.2)
- 前置量计算
- 火控角检查
- 按 fire_rate 自动射击

### 雷达锥

标准扇形判定（与 Aircraft 相同算法），参数来自 `params.radar_range` / `params.radar_half_angle`。

### 绘制

方形图标（区别于飞机三角），带方向指示线。

---

## SAMUnit（防空导弹车）

**文件**: `scripts/sam_unit.gd`  
**场景**: `scenes/sam_unit.tscn`  
**参数**: `resources/sam_params.tres`

### 特性

- **360° 圆形雷达**：覆写 `is_in_radar_cone()` 只检查距离不检查角度
- **导弹发射**：锁定后自动发射，检查在飞导弹避免重复
- 不使用机炮（覆写 `_update_combat` / `_update_gun` 为空）

### 导弹：HQ-7

| 参数 | 值 |
|------|-----|
| 最大速度 | 550 m/s |
| 燃烧时间 | 3.5s |
| 加速度 | 150 m/s² |
| 最大过载 | 15G |
| 后半球射程 | 6000m |
| 伤害 | 60 |
| 挂载数 | 4 |
| 冷却 | 6s |

### SAM 单位参数

- HP: 80, 雷达范围 3000px (6km), 360°覆盖, 锁定时间 2.5s

---

## AAGunUnit（高射炮）

**文件**: `scripts/aa_gun_unit.gd`  
**场景**: `scenes/aa_gun_unit.tscn`  
**参数**: `resources/aa_gun_params.tres`

### 特性

- **独立炮塔转向**：`turret_heading` 独立于底盘朝向
- 炮塔转速 `TURRET_TURN_RATE = 2.0 rad/s`
- 宽松开火判定（25° 内就开火，象征性射击）
- 无目标时缓慢旋转

### 机炮：ZU-23

| 参数 | 值 |
|------|-----|
| 射速 | 1200 发/min |
| 单发伤害 | 4 |
| 初速 | 700 m/s |
| 射程 | 600m |
| 散布 | 6° |
| 弹药 | 2000 |

### AAA 单位参数

- HP: 60, 雷达范围 2000px (4km), ±60° 锥, 锁定时间 1.0s

---

## RadarStation（雷达站）

**文件**: `scripts/radar_station.gd`  
**场景**: `scenes/radar_station.tscn`  
**参数**: `resources/radar_station_params.tres`

### 特性

- **超大范围雷达**: 10000px (20km), 360° 覆盖
- **无武器**: 不选定目标，不攻击
- **数据链共享**: 将锁定信息注入 `datalink_range`(4000px) 内的友方地面单位
  - 注入进度上限 = 对方 lock_time - 0.5（不立刻触发开火，需要对方自己补齐最后 0.5s）
- **旋转雷达盘动画**: `DISH_SPIN_RATE = 1.5 rad/s`
- 数据链更新间隔 0.5s

### 参数

- HP: 40, 雷达范围 10000px (20km), 360°覆盖, 锁定时间 2.0s

---

## GroundConvoy（车队系统）

**文件**: `scripts/ground_convoy.gd`

管理地面单位编队移动：
- 头车按路径移动
- 后车通过 `convoy_leader` 跟随前车
- `convoy_follow_distance` 控制间距

---

## 地面单位与空中单位的交互

### 雷达锁定

- 地面单位参与 `main.gd._update_radar_locks()` 循环
- 低空/地面目标锁定速率衰减（杂波干扰）
  - GROUND: ×0.5
  - LOW: ×0.7
  - MID/HIGH: ×1.0

### 导弹交互

- 导弹命中检测中，`GroundUnit` 跳过高度检查
- SAM 发射的导弹也参与 MissileManager 统一管理

### 机炮交互

- BulletManager 命中检测中，涉及 GroundUnit 时跳过高度容差检查
- 地面↔空中交火使用纯 2D 距离判定
