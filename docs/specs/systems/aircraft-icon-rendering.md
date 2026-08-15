---
id: aircraft-icon-rendering
kind: system
status: approved
schema_version: 1
spec_version: 1
owner: user
depends_on: [systems/ui-design-guidelines]
reconstruction_complete: true
---

# 飞机图标 Sprite 渲染

> 将可安全复用的标准战斗机线框烘焙为共享纹理，减少大量飞机的重复多边形提交，同时完整保留姿态、选中、受击与特殊轮廓语义。

## 1. 设计意图（Why）

- 大规模空战中把标准战斗机的静态机身几何改为共享 Sprite，降低渲染提交成本。
- 玩家必须仍能从颜色、滚转、机动压缩、选中圈和受击反馈读懂飞机状态。
- 本功能只替换“标准 fighter 主体”这一段绘制；不得借机恢复旧分支的雷达全表扫描、子弹 MultiMesh 试验或旧性能 HUD。

## 2. 数据定义（What）

| 字段 | 权威值 |
|---|---:|
| 图标类型 | 仅 `fighter` |
| 源纹理尺寸 | `128 × 128` |
| 逻辑机身尺寸 | `16 px` |
| 烘焙缩放 | `3.5` |
| 默认开关 | 仅在 Godot 4.7 Visual + Sentinel 保持硬 60 FPS 且视觉验收通过后才可开启 |

- 白色纹理由 `AircraftParams.icon_color` 调色。
- 以下情况必须回退现有 `_draw()`：特殊轮廓、纹理缺失、`wing_color` 非透明、或任何不能一比一表达的机体装饰。
- Sprite 与原几何共享同一姿态语义，不复制第二套飞机形状定义。

### 2.1 动态缩放

先计算现有高度缩放 `base_scale`，再应用：

```text
x = base_scale * cos(bank + evade_roll)
y = base_scale
Cobra: y *= lerp(1.0, 0.35, cobra_visual)
Herbst: x *= lerp(1.0, 0.40, herbst_visual)
        y *= lerp(1.0, 0.40, herbst_visual)
```

## 3. 行为流程（How）

1. `Aircraft` 完成参数和 meta 初始化后延迟创建图标 Sprite，避免读取未就绪的轮廓信息。
2. 满足 Sprite 资格时只跳过标准 fighter 主体多边形；尾焰、选中圈、状态符号和命中特效继续走现有绘制。
3. 每次视觉姿态变化时更新 Sprite 的颜色、可见性和动态缩放。
4. 进入摧毁状态时立即隐藏 Sprite；节点释放时按正常子节点生命周期清理。

## 4. 边界情况与异常处理

- `wing_color` 含可见 alpha 时回退 `_draw()`，不得丢失翼面颜色。
- 纹理加载失败时静默回退原几何并记录一次诊断，不显示空飞机。
- 任何特殊 icon type 默认回退，直到有独立纹理与视觉验收。
- 本系统不得新增全场扫描、每帧 `get_children()` 或无变化的 `queue_redraw()`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 标准 fighter 的颜色、滚转、Cobra、Herbst、高度缩放与旧几何目视一致。
- [ ] 特殊轮廓、可见 `wing_color`、缺纹理与摧毁状态均正确回退或隐藏。
- [ ] 选中圈、尾焰、锁定/命中反馈未被 Sprite 遮挡。
- [ ] Godot 4.7 Visual 截图覆盖普通、选中、滚转和特殊轮廓；无空白或双重机身。
- [ ] Sentinel 压测保持项目硬 60 FPS 门槛；未通过则默认开关保持关闭。

## 6. 实现计划

- [ ] 移植 manifest、烘焙场景、共享几何函数与 fighter 纹理。
- [ ] 在当前 `AircraftRenderer` 中接入 Sprite 资格与安全回退。
- [ ] 补聚焦视觉 bench 与 Sprite/几何状态断言。
- [ ] 跑 Godot 4.7 Visual 和 Sentinel，再裁定默认开关。

## 7. 代码锚点

- 待实现后填写。

## 8. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1 | 2026-08-16 | 仅保留历史 Sprite 分支的标准 fighter 共享图标路径；明确排除已被取代的性能实现。 |
