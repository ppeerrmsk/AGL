# 雷达系统

## 概述

每架飞机前方有一个扇形雷达照射区域，敌机在该区域内持续停留一定时间后被判定为"锁定"。雷达锥仅在鼠标悬停到飞机上时显示。

## 参数（AircraftParams）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `radar_range` | float | 300.0 | 探测距离（像素，1px = 2m） |
| `radar_half_angle` | float | 30.0 | 扇形半角（度），总张角 = 2 × half_angle |
| `lock_time` | float | 3.0 | 持续照射多久后判定锁定（秒） |

每种机型在 `.tres` 资源文件中独立配置这些参数。

当前机型配置：

| 机型 | radar_range | radar_half_angle | lock_time |
|------|-------------|------------------|-----------|
| F-16 | 350 px (700m) | 30° (60° 总张角) | 2.5s |
| MiG-29 | 280 px (560m) | 25° (50° 总张角) | 3.5s |

## 状态变量（Aircraft）

| 变量 | 类型 | 说明 |
|------|------|------|
| `is_hovered` | bool | 鼠标悬停标记，控制雷达锥是否显示 |
| `radar_targets` | Dictionary `{Aircraft: float}` | 雷达锥内每架敌机的累计照射时间 |
| `is_locked` | bool | 是否被至少一架敌方飞机锁定 |
| `locked_by` | Array[Aircraft] | 当前锁定自己的敌机列表 |

## 锥体判定逻辑

`Aircraft.is_in_radar_cone(target_global_pos)` 方法：

1. 计算目标到本机的距离，超过 `radar_range` 则不在锥内
2. 计算目标相对于本机的方位角：`atan2(diff.x, -diff.y)`（与 heading 同坐标系）
3. 计算方位角与 heading 的差值绝对值
4. 差值 ≤ `radar_half_angle`（转为弧度）则判定在锥内

## 锁定计算流程

每帧在 `main.gd._update_radar_locks(delta)` 中执行：

```
1. 收集场景中所有 Aircraft 节点
2. 重置所有飞机的 is_locked / locked_by
3. 对每架飞机 A，遍历所有不同阵营的飞机 B：
   - B 在 A 的雷达锥内 → radar_targets[B] += delta（累加照射时间）
   - B 不在锥内 → radar_targets 中移除 B（照射时间清零）
4. 遍历所有飞机的 radar_targets：
   - 累计时间 ≥ lock_time → 目标飞机 is_locked = true，加入 locked_by
```

离开雷达锥后照射时间立即清零，需要重新累计。

## 悬停检测

在 `main.gd._update_hover(screen_pos)` 中：

- 将鼠标屏幕坐标转为世界坐标
- 找到距离最近且在 30px 半径内的飞机
- 设置该飞机的 `is_hovered = true`，其余为 `false`

## 视觉表现

### 雷达锥（`_draw_radar_cone`）

- 仅在 `is_hovered = true` 时绘制
- 以飞机位置为圆心，heading 方向为中心轴
- 本地坐标中中心轴为 -Y 方向（-PI/2），因为飞机 rotation = heading
- 颜色：友方（team=0）蓝绿色半透明，敌方（team=1）红色半透明
- 由填充扇形多边形 + 边缘线组成

### 锁定警告（`_draw_lock_indicator`）

- 仅在 `is_locked = true` 时绘制
- 飞机图标周围四个方向各显示一个红色小三角
- 三角带闪烁效果（alpha 随 sin 波动）

## 涉及文件

| 文件 | 职责 |
|------|------|
| `scripts/aircraft_params.gd` | 定义 radar_range / radar_half_angle / lock_time 导出参数 |
| `scripts/aircraft.gd` | 雷达状态变量、锥体判定方法、锥体与锁定指示绘制 |
| `scripts/main.gd` | 鼠标悬停检测、每帧锁定计算循环 |
| `resources/default_fighter.tres` | F-16 雷达参数配置 |
| `resources/enemy_fighter.tres` | MiG-29 雷达参数配置 |

---

## 雷达锁定计算（CLAUDE.md 摘出，2026-05-05）

主循环位置：`main.gd:_update_radar_locks:226`（沙盒）/ `survivor_mode.gd:_update_radar_locks`（生存）。

全局循环每帧：
1. 遍历所有 CombatUnit，重置 `is_locked`
2. 对每单位，检查其雷达锥内的敌方单位
3. 在锥内 → 按 `_lock_rate_for_tier` 速率累加照射时间（地面 ×0.5, 低空 ×0.7）
4. 不在锥内 → 1.5 秒衰减窗口（防边缘震荡）
5. 累计 ≥ `params.lock_time` → 锁定
