---
id: aircraft-icon-rendering
kind: system
status: done
schema_version: 1
spec_version: 2
owner: user
depends_on: [systems/ui-design-guidelines]
reconstruction_complete: true
---

# 飞机图标渲染权威与历史分支裁决

> 当前权威是逐机型顶视 PNG 目录；历史分支的单张通用 `fighter` Sprite 会降低机型辨识度，因此不移植。

## 1. 设计意图（Why）

- 飞机图标必须优先表达真实机型轮廓，玩家应能仅凭顶视外形辨认主要机型。
- 同型号复用已审的透明 PNG，并由运行时统一换色，避免每架飞机重复维护纹理状态。
- 原创、虚构、旋翼、轰炸机或尚无合格素材的机型保留已有专用多边形绘制，不能用通用战斗机轮廓替代。
- 历史分支的旧性能 HUD、雷达 O(N²) 扫描、子弹 MultiMesh 原型和通用 fighter 烘焙链均不恢复。

## 2. 数据定义（What）

| 字段 | 权威值 |
|---|---|
| 纹理目录 | `resources/aircraft_silhouettes/` |
| 单图尺寸 | `128 × 128` 透明 PNG |
| 机型映射 | `AircraftSilhouetteCatalog.TEXTURE_PATHS` / `DISPLAY_KEYS` |
| 旧绘制保留名单 | `AircraftSilhouetteCatalog.LEGACY_DISPLAY_NAMES` |
| 运行时绘制 | `AircraftSilhouetteCatalog.draw_icon()` |
| 无匹配素材 | 返回 `false`，由 `AircraftRenderer` 继续旧轮廓绘制 |

- PNG 是白色或分层蒙版，由 `AircraftParams.icon_color`、翼色和阵营状态在运行时换色。
- 真实尺寸、高度、滚转、Cobra、Herbst 等姿态缩放继续由当前 `AircraftRenderer` 统一计算。
- 同一素材可服务显示名别名；特殊家族可定义专用缩放，但不得退化为所有 fighter 共用一张图。

## 3. 行为流程（How）

1. `AircraftRenderer.draw_aircraft_icon()` 根据飞机参数向目录查询机型 key。
2. 目录首次使用时解码并缓存对应纹理；后续同型号复用缓存。
3. 已登记机型按当前姿态、尺寸与颜色绘制顶视 PNG。
4. 未登记、明确列入旧绘制名单或纹理不可用时返回 `false`，继续现有专用几何绘制。
5. 选中圈、尾焰、锁定、标签、命中和状态反馈仍由现有绘制层处理。

## 4. 边界情况与异常处理

- 禁止用单张通用 `fighter.png` 覆盖不同真实机型。
- 纹理加载失败必须安全回退，不能显示空飞机或双重机身。
- 不新增飞机级 `_process`、全场扫描、每帧 `get_children()` 或无变化的 `queue_redraw()`。
- 历史分支中的 manifest、烘焙场景和通用 Sprite2D 节点不是当前运行时依赖，不得移植。

## 5. 验收标准（Acceptance / Litmus）

- [x] 已登记的真实机型经 `AircraftSilhouetteCatalog` 绘制各自顶视 PNG，而非通用 fighter 图。
- [x] 原创、虚构与无合格来源的机型保留旧专用轮廓。
- [x] 当前目录保持纹理缓存、同型号复用、运行时换色与安全回退。
- [x] 历史通用 Sprite、旧性能 HUD、雷达 O(N²) 和子弹 MultiMesh 未进入当前分支。
- [x] `aircraft_silhouette_visual` 22 个代表样张与 Sentinel 32 机压力场均通过，现有视觉和性能基线未回归。

## 6. 实现计划

- [x] 对比历史分支的通用 fighter Sprite 与当前逐机型目录。
- [x] 裁定当前 `AircraftSilhouetteCatalog` 为权威，不移植会造成视觉降级的旧实现。
- [x] 排除旧性能 HUD、雷达全表扫描、子弹 MultiMesh 和烘焙链。
- [x] 组合收尾时复跑现有视觉与 Sentinel 验收。

## 7. 代码锚点

- `scripts/aircraft_silhouette_catalog.gd`：纹理路径、别名、旧绘制名单、缓存与绘制。
- `scripts/aircraft_renderer.gd`：飞机图标入口、姿态缩放与旧绘制回退。
- `resources/aircraft_silhouettes/`：已审顶视 PNG 与来源清单。
- `scripts/tests/aircraft_silhouette_visual_qa_runner.gd`：代表机型视觉验收。

## 8. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1 | 2026-08-16 | 从历史 Sprite 分支提取候选范围，并排除已被取代的性能实现。 |
| v2 | 2026-08-16 | 发现主线已有逐机型顶视 PNG 权威；裁定不移植会降级辨识度的通用 fighter Sprite。 |
