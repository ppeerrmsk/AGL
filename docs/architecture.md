# 架构设计与扩展规划

## 核心设计决策

1. **不使用 Godot 物理引擎**：飞机运动完全由自定义公式驱动，在 `_physics_process` 中手动更新 `position`。这样物理行为完全可控。

2. **2D 场景 + 虚拟高度**：使用 Godot 的 2D 系统，`altitude` 作为纯数值变量存在，仅通过图标缩放来可视化。

3. **单位系统**：内部使用 SI 单位（米、m/s），显示时转换为 km/h。地图 1 像素 = 2 米（`PIXELS_PER_METER = 0.5`）。

4. **输入模型**：玩家点击 → 设定 `target_position`，飞机自主执行转弯物理（G 力极限转弯）。不是瞬间转向。

5. **飞机通用模板**：`aircraft.tscn` + `AircraftParams` Resource，通过不同 `.tres` 文件定义不同机型。

6. **AI 组合模式**：`AIController` 作为子节点附加到飞机上，飞机本身不区分玩家/AI，只是目标来源不同。

## 编队扩展预留

当前实现单机操控，但架构上已预留编队支持：

- `selected_aircraft` 是 `Array[Aircraft]`（当前为单选，后续可多选）
- 点击目标时遍历 `selected_aircraft` 设定各机的 `target_position`
- 飞机通过 `team` 标识归属阵营，`selected` 标识是否被选中

后续加入编队时，只需：
1. 支持框选 / Shift 多选飞机
2. 为编队中的僚机计算偏移后的 `target_position`（如楔形/纵队编队阵型）
3. 可选：添加 `formation_controller.gd` 管理编队间距和阵型

## 物理演算流程（每帧）

```
_physics_process(delta)
  ├── _update_weapon_mode()      判定武器模式（MISSILE/GUN），最先执行
  ├── _update_combat(delta)      追踪逻辑（根据武器模式分导弹/机炮策略）
  ├── _update_energy_management() 速度/高度/加力管理（根据武器模式分阶段）
  ├── _update_target_heading()   根据 target_position 计算目标航向
  ├── _update_bank(delta)        滚转角趋近目标 bank（导弹模式三阶段坡度限制）
  ├── _update_heading(delta)     由 bank_angle 算转弯率，更新 heading
  ├── _update_speed(delta)       速度趋近目标速度（受 acceleration 限制）
  ├── _update_altitude(delta)    高度趋近目标高度（受 climb_rate_max 限制）
  ├── _update_fuel(delta)        燃油消耗
  ├── _update_stall()            检查是否失速
  ├── _update_g_load()           计算当前 G 载荷
  ├── _apply_movement(delta)     根据 heading + speed 更新 position
  ├── _update_gun(delta)         机炮射击
  ├── _update_missile(delta)     导弹发射（目标选择 + 包线检查 + crank 计时）
  └── _update_visuals()          rotation = heading
```

## 关键物理公式

| 物理量 | 公式 | 说明 |
|--------|------|------|
| 转弯率 | `ω = g × tan(bank_angle) / speed` | 标准协调转弯 |
| 转弯半径 | `R = speed² / (g × tan(bank_angle))` | |
| G-force | `G = 1 / cos(bank_angle)` | 水平面转弯过载 |
| 失速速度 | `V_stall = V_stall_base × √G` | 过载越大失速速度越高 |
| 空气密度比 | `σ = e^(-altitude / 8500)` | 简化大气模型 |
| 最大速度（高空） | `V_max × √σ` | 高空最大速度下降 |
