# 雷达系统

## 概述

每架飞机前方有一个扇形雷达照射区域，敌机在该区域内持续停留一定时间后被判定为"锁定"。雷达锥仅在鼠标悬停到飞机上时显示。

## 参数（AircraftParams）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `radar_range` | float | 300.0 | 探测距离**基础值**（像素，1px = 2m）；实际有效距离随本机高度乘 0.5~1.5 连续倍率，见下"高度对雷达的影响" |
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
| `is_locked` | bool | 含玩家阵营的交战配对中，是否被至少一架敌方单位锁定 |
| `locked_by` | Array[CombatUnit] | 含玩家阵营的交战配对中，当前锁定自己的单位列表 |
| `incoming_lock_progress` | float | 含玩家阵营配对的最大锁定进度；只服务锁框与玩家交战反应 |

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
4. 遍历所有单位的 radar_targets：
   - 战术照射不分玩家是否参与，AI 武器仍可正常读取并开火
   - 只有射手或目标至少一端属于 `TEAM_PLAYER` 时，才把进度汇总到目标的
     `incoming_lock_progress / is_locked / locked_by`
   - 累计时间 ≥ lock_time → 目标 is_locked = true，加入 locked_by
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

### 锁定框 / 锁定警告（`_draw_lock_indicator`）

- 锁定进度或 `is_locked` 仅来自含玩家阵营的锁定配对；玩家小队锁敌、敌军锁玩家小队都可显示。
- `ALLY↔HOSTILE` 的 AI 互锁不绘制红框，也不触发玩家专属被锁反应，但不会停止 AI 武器交战。
- 满锁时为红色四角框并闪烁；未满锁时显示收缩进度框。

## 涉及文件

| 文件 | 职责 |
|------|------|
| `scripts/aircraft_params.gd` | 定义 radar_range / radar_half_angle / lock_time 导出参数 |
| `scripts/aircraft.gd` | 雷达状态变量、锥体判定方法、锥体与锁定指示绘制 |
| `scripts/survivor/survivor_mode.gd` | 每帧锁定计算循环（生存模式，主路径）|
| `scripts/camera_controller.gd` | 鼠标悬停检测 |
| `scripts/main.gd` | 同上（沙盒，**已废弃**，仅调试留存）|
| `resources/*.tres` | 各机型雷达参数；数值见 [resources-catalog.md](../reference/resources-catalog.md) |

---

## 雷达锁定计算（CLAUDE.md 摘出，2026-05-05）

主循环位置：`survivor_mode.gd:_update_radar_locks`（生存，主路径）/ `main.gd:_update_radar_locks`（沙盒，已废弃）。

⚠ 生存模式下这是 O(N²) 循环，走分帧 strided 摊销 + `_all_combat_units_cache` 共享列表。

全局循环每帧：
1. 遍历所有 CombatUnit，重置 `is_locked`
2. 对每单位，检查其雷达锥内的敌方单位
3. 在锥内 → 按 `_lock_rate_for_target` 速率累加照射时间（LOW 档**飞机**目标 ×0.7；地面/舰船目标不折减 ×1.0）
4. 不在锥内 → 1.5 秒衰减窗口（防边缘震荡）
5. 累计 ≥ `params.lock_time` → 锁定（进度封顶 threshold + 稳定缓冲；速率有硬下限保证有效锁定时间 ≤ 12s）

---

## 高度对雷达的影响（survivor 主路径，以代码为准 2026-07-26）

**雷达锥判定本身是纯 2D**：`is_in_radar_cone` 只看平面距离 + 方位角，高度差不影响进锥。
高度通过以下乘数间接起作用：

### 本机有效雷达距离（`aircraft.gd effective_radar_range_px`，锚点线性插值）

| 高度 | 倍率 |
|------|------|
| 0 m | ×0.50 |
| 2000 m（LOW 切档目标） | ×0.60 |
| 5500 m（MID 切档目标） | ×1.00 |
| 10000 m（HIGH 切档目标） | ×1.40 |
| 15000 m | ×1.50 |

爬得越高看得越远——这是 HIGH 档位目标高度定在 10000m（而非 7500m 判定线）的主要连续收益。

### 锁定速率修正（`survivor_mode.gd` 锁定循环内，按目标/射手高度）

| 条件 | 效果 |
|------|------|
| 目标为 LOW 档飞机 | lock_rate ×0.7（地面杂波） |
| 目标 HIGH 档且在云中 | ×0.5（云雾机动奖励持有者任意档 ×0.1） |
| 玩家技能"爬降隐身"（alt_change_stealth_factor） | 升降越快被锁越慢，最低 ×0.1 |
| 玩家技能"平流层雷达"（high_alt_lock_speed_bonus） | 本机 HIGH 档时锁敌速率 +30% |
| 签名技（A-6E 低空 / MiG-41 高空） | 被锁 ×0.6 |
