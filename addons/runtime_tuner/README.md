# Runtime Tuner

这是独立 Debug 插件的局部说明；项目级代码域和 AutoLoad 导航见
[Reference Index](../../docs/reference/_INDEX.md) 与 [Repository Layout](../../docs/reference/repo-layout.md)。

游戏中实时调试 .tres / Aircraft 字段的滑条 overlay。

## 用法

1. F5 启动生存模式
2. **F10** 切换调试器显示
3. 滑条现场改值，立即看效果
4. 满意时点 **Print to EventLogger** —— 当前值（含 spawn 基线对比）写到 EventLogger
   F9 导出 log 后从里面手动复制回 .tres 文件
5. **Reset All** 还原所有字段到 spawn 时的值
6. 单字段 ↺ 还原单个字段

## 设计原则

- **运行时改值不写盘** —— Godot Resource 默认不持久化，这次会话改的值退出就消失。
  这是故意的，避免误操作毁掉 .tres 平衡值。"Print" 让你显式审视后手动落盘。
- **隔离** —— 游戏运行时代码不引用本 addon。通过 `project.godot` autoload 注入。
  想关掉就把 `RuntimeTuner=...` 那行删了，工具消失，游戏不受影响。
- **字段表硬编码** —— `FIELDS` 常量挑了 12 个最常调的字段。要加新的直接编辑常量。

## 当前字段表

| 字段 | 类型 | 范围 |
|---|---|---|
| Max G | params | 1.0 - 15.0 |
| Max Speed (km/h) | params | 200 - 3500 |
| Cruise Speed (km/h) | params | 200 - 2500 |
| Stall Base (km/h) | params | 100 - 600 |
| Max HP | params | 50 - 500 |
| Radar Range (m) | params | 1000 - 30000 |
| Radar Half Angle (deg) | params | 5 - 90 |
| Lock Time (s) | params | 0.5 - 8.0 |
| Gaze Press Threshold (s) | self | 0 - 30 |
| JAM Aura Radius (px) | self | 0 - 3000 |
| Rear SLOW Aura (px) | self | 0 - 3000 |
| Bullet Dodge Chance | self | 0 - 0.85 |

## 限制

- 仅 hover 玩家飞机（target = AircraftRenderer.player_ref）。要调敌方/僚机的话需要扩展。
- 只支持 float 字段。bool / int 单独显示但都走 HSlider，整数字段会显示为整数但滑动是连续的。
- 不持久化。需要落盘时走 "Print" → 手动复制。
- 关掉 autoload 后游戏正常跑，但项目编辑器会提示找不到该 autoload —— 这是预期。

## 后续

- v2: target 可切换到 hover 的敌机
- v3: 装备字段（railgun.fire_along_nose 等 .tres 嵌套字段）
- v4: "保存到 .tres" 按钮（带 confirm 弹窗）
