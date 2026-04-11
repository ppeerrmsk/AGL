# 更新日志 — 2026-04-07

## 1. 轨迹丝带系统（TrailRibbon）

新增通用轨迹丝带渲染组件 `TrailRibbon`，替换原有的逐点折线画法。

- **飞机轨迹**：友方蓝色、敌方红色半透明丝带，宽度 8px，最多 150 个采样点
- **导弹烟迹**：导弹也改用 TrailRibbon，宽度 3px，80 个采样点，视觉更统一
- 丝带宽度沿轨迹从尾部到头部渐变，带有透明度衰减，视觉效果更平滑

**涉及文件**：`scripts/trail_ribbon.gd`（新增）、`scripts/aircraft.gd`、`scripts/missile.gd`

## 2. 调试面板（DebugPanel）

新增 CanvasLayer 调试面板，方便开发时查看运行状态。

**涉及文件**：`scripts/debug_panel.gd`（新增）、`scenes/main.tscn`

## 3. 导弹发射逻辑修正

修正导弹目标选择逻辑：导弹现在只对当前交战目标（`combat_target`）发射，而不是自动选择"最佳目标"。

- 移除 `_select_best_missile_target()` 的自动选择行为
- 必须有明确的 `combat_target` 且该目标满足锁定条件才允许发射
- 避免了"没有交战意图却自动发射导弹"的问题

**涉及文件**：`scripts/missile.gd`、`scripts/aircraft.gd`

## 4. 飞行员耐力 & 机体结构G力系统

将原来固定的 9G 上限改为动态的双层G力限制系统：

### 新增参数（AircraftParams）

| 参数 | F-16 | MiG-29 | 说明 |
|------|------|--------|------|
| `max_g` | 9.0 | 8.0 | 飞行员持续耐受G（可长期维持） |
| `max_g_structural` | 12.0 | 11.0 | 机体结构极限G |
| `pilot_stamina` | 100.0 | 80.0 | 飞行员耐力上限 |
| `stamina_drain_rate` | 25.0 | 30.0 | 超G时每秒消耗 |
| `stamina_recovery_rate` | 10.0 | 8.0 | 低G时每秒恢复 |

### 核心公式

```
effective_max_g = max_g + (max_g_structural - max_g) × (stamina / max_stamina)
```

- 耐力满 → 可拉到机体结构极限（F-16: 12G，MiG-29: 11G）
- 耐力耗尽 → 退回飞行员持续耐受值（F-16: 9G，MiG-29: 8G）
- G力越高，耐力消耗越快（按超出比例加权）
- 低G飞行时自动恢复耐力

### HUD 变化

- G力显示改为 `G 4.2/12`（当前G / 有效极限G）
- 新增 `STA 85%` 显示飞行员耐力百分比

**涉及文件**：`scripts/aircraft_params.gd`、`scripts/aircraft.gd`、`resources/default_fighter.tres`、`resources/enemy_fighter.tres`、`docs/aircraft-params.md`
