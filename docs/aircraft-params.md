# 飞机参数说明（AircraftParams）

`AircraftParams` 继承自 `Resource`，通过 `.tres` 文件定义不同机型。所有参数均为 `@export`，可在 Godot 编辑器中直接调整。

## 参数一览

| 参数 | 类型 | F-16 默认值 | MiG-29 默认值 | 说明 |
|------|------|-------------|---------------|------|
| display_name | String | "F-16" | "MiG-29" | 显示名称 |
| max_hp | float | 100.0 | 80.0 | 血量 |
| armor | float | 0.0 | 0.0 | 装甲减伤（预留） |
| max_speed | float | 2100.0 | 2000.0 | km/h 海平面最大速度 |
| cruise_speed | float | 900.0 | 850.0 | km/h 巡航速度（也是初始速度） |
| stall_speed_base | float | 220.0 | 200.0 | km/h 1G 海平面失速速度 |
| acceleration | float | 50.0 | 45.0 | m/s² 加速/减速能力 |
| max_g | float | 9.0 | 8.0 | 最大过载，决定最大转弯力度 |
| roll_rate | float | 4.0 | 3.5 | rad/s 滚转速率，影响进入转弯的快慢 |
| max_altitude | float | 15000.0 | 14000.0 | 米 实用升限 |
| climb_rate_max | float | 250.0 | 230.0 | m/s 最大爬升率 |
| thrust_to_weight | float | 1.1 | 1.0 | 推重比（预留） |
| drag_coefficient | float | 0.02 | 0.025 | 阻力系数（预留） |
| icon_color | Color | GREEN | RED | 图标线框颜色 |

## 参数如何影响飞行行为

- **max_g** → 最大 bank 角 = `acos(1/max_g)` → 决定最急转弯的弧度和G力
- **roll_rate** → bank 角变化速度 → 影响从直飞到满 bank 转弯需要多久
- **max_speed / cruise_speed** → 速度越快，同 bank 角下转弯半径越大
- **stall_speed_base** → 高 G 转弯时失速速度升高（`V_stall × √G`），限制低速急转
- **acceleration** → 加减速响应快慢
- **max_altitude / climb_rate_max** → 高度变化能力

## 添加新机型

1. 在 `resources/` 下新建 `.tres` 文件
2. 设定 Script 为 `aircraft_params.gd`
3. 调整各项参数
4. 在场景中实例化 `aircraft.tscn`，将 `params` 指向新 `.tres`
