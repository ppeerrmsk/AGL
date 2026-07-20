---
id: map-editor
kind: system
status: approved     # ✅ 用户定稿 2026-07-04（spec_version 4）；待按 §6 派生代码
schema_version: 1
spec_version: 5
owner: noelu
depends_on: [ugc-editor, map-system, map-expansion]
reconstruction_complete: false
---

# 游戏内地图编辑器（UGC P1）—— 格子笔刷前端 + 矢量多边形后端

> 玩家视角：游戏里打开编辑器，左上角素材库选"陆地/城区/建筑/云"，中间画布上用笔刷涂格子、
> 橡皮擦掉、线条工具拉道路，涂完的地块自动变成和官方地图一样的平滑海岸线；点"试飞"直接开一局。

## 1. 设计意图（Why）

- **体验目标**：零门槛捏地图——像涂色游戏一样涂格子，产出却是官方品质的平滑矢量地图；
  官方自己也用它铺 [map-expansion](map-expansion.md) 的大图（dogfood：工具先行）。
- **核心裁决**：交互用**格子笔刷**（参考 Unity/万人熟悉的 tile 编辑器），存储与渲染用**矢量多边形**
  （与现有地图运行时格式一比一）。两者用"轮廓提取 + 平滑"连接，见 §3.1。
- **Litmus 自检**：编辑器是独立场景不进战斗帧循环（性能守则天然过）；产出走既有
  `is_on_land` / BuildingRenderer / WeatherSystem 查询口，不加新机制。
- **反模式规避**：不发明第二套地图运行时——编辑器只是现有 JSON 数据的"游戏内产线"。
- **⚑ 底图 PNG 退役（用户定 2026-07-04）**：卫星照片底图是风格外来物（项目美术方向 =
  极简线框矢量），编辑器产出**一律纯矢量渲染**；PNG 能提供的视觉（地形色彩变化/纹理颗粒/
  边缘描线）全部由矢量手段等效实现（§2.2 地形覆盖类型 + §2.5 调色板 + §3.5 程序纹理）。
  官方图在编辑器落地后用编辑器重制为矢量版（dogfood），PNG 资产随之从打包移除。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 编辑网格（交互层，不进运行时）

| 字段 | 值 | 说明 |
|---|---|---|
| 世界范围 | 随 map-expansion 主开关（60km 现值 ±15000 px） | 从 `MapBoundary.WORLD_HALF_PX` 派生，改主开关编辑器自动跟随 |
| 地形格边长 | 100 px（= 200 m） | 格数 = 世界边长/格边长，从 MapBoundary 主开关派生（60km 现值 **300×300**）；海岸线精度 ≈ 官方 OSM 烘焙抽稀后水平 |
| 笔刷尺寸 | 1 / 3 / 5 / 9 格（直径） | 圆形笔刷 |
| 云 mask 格边长 | 64×64 格覆盖全图（随主开关；60km 现值 ≈469 px/格） | 云是软边界，低分辨率足够 |
| 撤销栈深度 | 50 步 | 每步 = 一次笔画/放置/删除 |

### 2.2 可编辑图层（素材库分类）

| 图层 | 工具 | 存储形态（进 map JSON） | 运行时消费者 |
|---|---|---|---|
| 陆地 | 笔刷/橡皮 | `land_polygons: [[x,y]...]`（轮廓提取+平滑后） | `is_on_land` + 矢量渲染 |
| 地形覆盖（山地/森林/农田/沙滩） | 笔刷/橡皮 | `terrain_overlays: [{type, polygons}]`（叠在陆地上，替代 PNG 的地形色彩变化） | 矢量渲染（调色板取色） |
| 城区 | 笔刷/橡皮 | `urban_polygons`（同上，叠在陆地上） | 城区底色渲染 |
| 机场/跑道 | 放置（矩形+角度） | `airports: [{center, size, rotation}]` | 渲染 + 着陆判定 |
| 道路 | 线条工具（折线） | `roads: [{points, width_class}]`，width_class ∈ {motorway, primary, secondary} | 道路渲染 |
| 建筑 | 放置（多边形/矩形 + 高度档） | `buildings: [{footprint, h_m}]`，高度档预设 30/80/150/300 m | BuildingRenderer（伪 3D + 低空碰撞） |
| 云层 | 笔刷/橡皮（密度） | `cloud: {seed, coverage, frequency, wind_dir_deg, wind_speed_ms, mask: 64×64 字节}` | WeatherSystem `sample_density` |
| 战区 | 放置（圆：center+radius+type） | `zones: [{center, radius, type}]` | spawner / 战区结算 |
| 玩家出生点 | 放置（单点+朝向） | `spawn: {pos, heading_deg}` | 开局注入 |

海面**不单独存**：不在任何 land 多边形内 = 海（与现行 `is_on_land` 语义一致）。

### 2.3 map JSON schema（`user://ugc/maps/<name>.json`）

```
{ schema_version: 1, display_name, world_size_m,
  land_polygons, urban_polygons, airports, roads,
  buildings, cloud, zones, spawn,
  style: {...},           # 调色板 + 后处理 + 可选底图引用，见 §2.5
  editor_cells: {...},    # 编辑器格子原始数据，仅编辑器回读用，运行时忽略
  layer_dirty: {...},     # 各图层"是否被笔刷改过"标记，见 §3.4 保真策略
  layer_mode: {...} }     # 各图层判定语义 union/even_odd，见 §3.4 判定语义
```

- `editor_cells` 保留涂格原稿 → 二次编辑不丢笔刷精度（多边形反推格子有损）。
- 数值围栏：多边形顶点数单图 ≤ 20000；建筑 ≤ 500 块；zones ≤ 12；越界加载时截断 + 日志。
- 安全红线沿用 [ugc-editor](ugc-editor.md) §2：只收 JSON，坏文件优雅降级。

### 2.4 文件生命周期（保存 / 导入 / 导出）

| 操作 | 行为 |
|---|---|
| 保存（Ctrl+S / 按钮） | 写 `user://ugc/maps/<name>.json`；标题栏未保存标记（`*`）随脏状态显隐 |
| 另存为 | 复制为新名字（兼作"复制地图"） |
| 自动保存 | 每 120 s + 每次点"试飞"前，写 `<name>.autosave.json`（单槽覆盖）；打开地图时若 autosave 比主存档新 → 弹恢复确认 |
| 退出编辑器 | 有未保存改动时弹确认（保存 / 丢弃 / 取消） |
| 导出 | 系统文件对话框（FileDialog ACCESS_FILESYSTEM）导出单文件 **`<name>.aglmap`**（内容 = 同一 JSON，扩展名用于识别/关联），默认到用户下载目录；含 `editor_cells` → 别人拿到可继续编辑 |
| 导入 | 文件对话框选 `.aglmap` / `.json` → 走与加载完全相同的 schema 校验 + 数值围栏 → 通过后拷入 `user://ugc/maps/`（重名自动加后缀）；失败弹原因不崩 |
| 版本迁移 | `schema_version` 低于当前 → 逐版本升级函数链；高于当前 → 拒绝导入并提示升级游戏 |

导入导出即 [ugc-editor](ugc-editor.md) P4"本地分享"的地图部分——单文件随便传（网盘/群文件），
不等创意工坊。安全边界不变：`.aglmap` 是纯数据 JSON，绝无代码执行面。

### 2.5 风格与调色板（style，全部可编辑；默认值 = 官方现值）

现有渲染层的颜色**全部已是常量/@export 参数**，数据驱动化 = 把它们从代码搬进 map JSON 读取，
渲染逻辑零改动。编辑器提供"调色板"面板（色卡 + 滑条）+ 主题预设（默认"TacView 冷灰"= 下表）。

| 键 | 官方默认值（RGBA） | 用途 |
|---|---|---|
| `palette.sea` | (0.16, 0.24, 0.32, 1.0) | 海面底色 |
| `palette.land` | (0.32, 0.35, 0.27, 1.0) | 陆地 mask 填充 |
| `palette.urban` | (0.42, 0.38, 0.28, 1.0) | 城区填充 |
| `palette.road` | (0.88, 0.80, 0.56, 1.0) | 道路线 |
| `palette.road_glow` / `road_core` | (1.00,0.70,0.25,0.35) / (1.00,0.85,0.45,0.95) | 高亮道路发光/芯线 |
| `palette.tacview_cross` | (0.55, 0.75, 0.82, 0.30) | 海面"+"十字 |
| `palette.building_roof` | (0.62, 0.59, 0.53, 1.0) | 建筑屋顶 |
| `palette.building_wall_lit` / `wall_shade` | (0.52,0.49,0.43,1.0) / (0.26,0.25,0.23,1.0) | 建筑受光/背光墙面 |
| `palette.building_shadow` | (0.04, 0.05, 0.07, 0.55) | 建筑投影 |
| `palette.building_outline` | (0.10, 0.10, 0.09, 0.6) | 屋顶描边 |
| `palette.terrain_mountain` | (0.38, 0.36, 0.32, 1.0)（初值，实装调）| 地形覆盖：山地 |
| `palette.terrain_forest` | (0.24, 0.32, 0.22, 1.0)（初值，实装调）| 地形覆盖：森林 |
| `palette.terrain_farmland` | (0.36, 0.36, 0.24, 1.0)（初值，实装调）| 地形覆盖：农田 |
| `palette.terrain_beach` | (0.46, 0.42, 0.32, 1.0)（初值，实装调）| 地形覆盖：沙滩 |
| `post.vignette` | 三环 (0.04,0.05,0.07)×α 0.30/0.55/0.90 @ 280/700/2000 px | 边缘暗角 |
| `post.grain` | 0.03 | 世界空间程序噪声颗粒（替代原底图 shader 的 CRT 噪点） |
| `post.land_outline` | (0.10, 0.12, 0.10, 0.6)，宽 1.5 px | 陆地/地形覆盖多边形描边（替代原 Sobel 边缘感） |

- 光照方向（建筑投影）`style.light_dir`：默认 (-0.7, -0.7) 归一化。
- 围栏：alpha 不设限但 UI 提示"全透明图层会不可见"；无非法值面（颜色天然有界）。
- **底图 PNG 相关键已废除**（§1 退役决定）；编辑器支持"导入参考图"，但**仅编辑态显示**
  （半透明描图垫），不写入成品 JSON、不参与导出、不进游戏渲染。

## 3. 行为与公式（How）

### 3.1 格子 → 多边形流水线（保真核心）

```
涂格 bitmap（随主开关的 N×N bool per 图层，60km 现值 300×300）
  → marching squares 提取闭合轮廓（外环+孔洞）
  → Douglas-Peucker 抽稀（epsilon = 0.4 × 格边长）
  → Chaikin 平滑 ×2 轮（与现有手画地块同参数）
  → 多边形数组（运行时格式）
```

- 触发时机：**笔画结束时**（松开鼠标）对脏区域重算，非每帧；全图重算 < 50 ms 量级。
- 画布上实时显示平滑后的轮廓预览（格子只在笔刷悬停时半透明显示）——所见即所得。

### 3.2 云密度采样（运行时改动，WeatherSystem 唯一注入点）

```
mask_mult(pos) = bilinear(cloud.mask, pos)   # 0..2，默认 1.0（未涂 = 纯噪声）
density(pos)   = clamp(noise(pos) × mask_mult(pos), 0, 1)
```

- mask 锚定"云空间"（随风整体漂移），与现行云行为一致。
- `sample_density` / `is_in_cloud` / 渲染共用此口 → 改一处全生效。
- 官方图 / 未提供 mask 时 mask_mult ≡ 1 → **零 buff 下行为不变**。

### 3.3 工具行为

| 工具 | 行为 |
|---|---|
| 笔刷 | 按住拖动连续涂当前素材图层的格子；Shift = 直线涂 |
| 橡皮 | 同笔刷，置空格子；只作用当前图层 |
| 线条 | 点击落顶点 → 折线，双击/Esc 结束；用于道路；拖动已有顶点可修形 |
| 放置 | 素材库选中建筑/战区/出生点后点画布放置；拖动移动、滚轮转角度/改半径、Del 删除 |
| 试飞 | 触发自动保存 → 以本图开一局生存模式（战区/出生点缺省时用默认模板） |
| 保存/导入/导出 | 见 §2.4 文件生命周期 |

### 3.4 官方地图一键转换（"从官方地图新建"）

**关键事实**：官方地图的 gameplay 数据**本来就是矢量 JSON**（`tokyo_bay.json` 陆地/城区/道路 +
`yokohama_buildings.json` 街区+楼高）；PNG 只是最底层的化妆底图，不参与任何判定。
所以"把现在的地图转成编辑器版"不是描图，而是**格式直通**：

```
官方 tokyo_bay.json      → land_polygons / urban_polygons / roads   （逐顶点原样搬）
yokohama_buildings.json  → buildings[{footprint, h_m}]              （逐街区原样搬）
战区/出生点常量           → zones / spawn                            （P0 JSON 化后直通）
云（官方无 mask）         → cloud 参数，mask 全 1.0
渲染颜色常量              → style（§2.5 默认值）
editor_cells             → 由多边形栅格化反推（格心 point-in-polygon，union 语义，一次性）
```

底图 PNG **不参与转换**（§1 退役决定）：转换图直接用矢量渲染；原照片可选作编辑态参考垫。

**判定语义（v5 修订 2026-07-20，替代 v4 的并集方案）**：每个涂格图层带 `layer_mode`——
- `even_odd`（默认）：编辑器烘焙的环组，孔洞=独立环，偶奇计数；
- `union`：官方转换直通多边形（可互相重叠），任一命中即算，与官方 `is_on_land` **一字不差**。

转换图陆地/城区标 `union` 且**逐顶点直通**（含陆地层，比 v4 并集方案保真更高）；用户对
某层动过笔刷 → 该层重烘焙并自动切 `even_odd`。v4 的"转换时布尔并集"已废弃：60km 重烘焙
数据上逐对 `merge_polygons` 出现浮点精度斑点，union 直通语义天然零损失。等价性由测试硬保证：
全部格心上转换图陆判 == 官方 `is_on_land` 逐点一致。

**保真策略（1:1 的关键）——`layer_dirty` 逐图层懒烘焙**：
- 转换后所有图层 `dirty=false`，**原始多边形是权威**，运行时直接用 → 逐顶点等同官方，零损失。
- 只有当用户对某图层**实际动了笔刷**，该图层才置 dirty 并从 editor_cells 重走 §3.1 烘焙。
  没动过的图层永远保持原始精度（栅格化→轮廓提取的往返损耗只发生在你真正改的地方）。

### 3.5 矢量渲染与性能预算（PNG 退役后的硬约束）

替代 PNG 的视觉手段与性能规则（performance-guidelines 第 1/2/3 条是本节的上位法）：

| 项 | 方案 | 性能约束 |
|---|---|---|
| 地图静态层（陆地/地形覆盖/城区/道路） | 画进**静态 canvas item，只画一次**；相机移动/缩放靠 canvas transform，**不触发 queue_redraw**（历史翻车点：地图每帧重算） | 重绘仅在数据变化时（编辑器内笔画结束 / 游戏内永不） |
| 多边形数量 | 官方量级：陆地 ~1000 顶点 + 城区 160 + 道路 1012 条；地形覆盖预计再 +200~500 个多边形 | 同层多边形用 `RenderingServer.canvas_item_add_triangle_array` 合并，禁止逐多边形 draw call 裸奔 |
| 纹理颗粒 | 世界空间噪声 shader 叠在陆地层（单材质、GPU 常数开销） | 一个全屏 pass 以内 |
| 描边 | 多边形轮廓 polyline（数据静态，随层一次画完） | 同静态层规则 |
| 内存 | 退役 PNG 净省 ~7.5 MB 纹理常驻 | — |

预算结论：矢量化后地图渲染成本 ≤ 现状（PNG 每帧全屏 shader 采样反而更贵）；风险不在量而在
模式——**任何人给地图层加每帧 `queue_redraw` 即违规**，验收有对应条目。

## 4. 结构与组成（Structure）

独立编辑器场景（主菜单入口"地图工坊"），三区布局（用户定 2026-07-04）：

- **左上：素材库面板** —— 图层分类列表（§2.2 的 8 类），点选后成为当前笔刷/放置对象；
  每项带小图标 + 名称（tr() 走 i18n）。
- **中间：画布** —— 复用 CameraController 缩放/平移；底层画海色 + 已成形矢量层
  （与 MapFeatureRenderer 同一套绘制函数，抽成共享模块避免两处维护）；上层画格子预览/控制点。
- **顶部/侧边：工具栏** —— 笔刷 / 橡皮 / 线条 / 放置 / 撤销重做 / 笔刷尺寸 / 存读 / 试飞。

组成模块：
- `MapEditorScene`（UI 骨架 + 工具状态机）
- `CellCanvas`（涂格位图 + 笔刷逻辑）
- `ContourBaker`（§3.1 流水线，纯函数可单测）
- `MapDocument`（schema 读写 + 撤销栈 + 数值围栏）
- 运行时侧：`UgcLoader.load_map()`（多边形注入 MapGeography、建筑注入 BuildingRenderer、
  cloud 注入 WeatherSystem、zones/spawn 注入 spawner）—— 属 [ugc-editor](ugc-editor.md) P0 交付物。

### 与官方地图的保真对照（"能做出跟现在地图一样的东西"逐项）

| 官方地图成分 | 编辑器能否等效产出 |
|---|---|
| 陆地/海岸线（平滑多边形） | ✅ 同格式同平滑参数 |
| 城区/道路/机场矢量层 | ✅ 同格式 |
| 建筑伪 3D + 低空碰撞 | ✅ 同 JSON 结构（footprint + 高度） |
| 云层 | ✅ 参数 + mask，能力超过官方（官方纯噪声） |
| 战区/出生点 | ✅（顺带完成 ugc-editor P0 的"战区布局 JSON 化"） |
| 卫星底图 PNG + shader | **已退役**（§1）：PNG 的视觉职能由矢量等效承接——地形色彩变化→地形覆盖图层、纹理感→程序噪声颗粒、边缘感→多边形描边（§3.5）。官方图将用编辑器重制为矢量版 |
| 渲染颜色/风格 | ✅ 全部进 `style` 调色板（§2.5），默认值即官方现值，能力超过官方（官方不可改色） |

## 5. 验收标准（Acceptance / Litmus）

- [ ] 用编辑器从零复刻一张"简化东京湾"（陆地轮廓 + 3 城区 + 2 机场 + 若干道路/建筑 + 5 战区），
      开局后与官方图玩法无差异（is_on_land / 建筑碰撞 / 战区结算全部生效）。
- [ ] 涂格 → 海岸线平滑度肉眼与官方手画地块无差异（Chaikin 同参数）。
- [ ] 云 mask：涂 0 区域导弹/雷达视线无云判定，涂 2 区域肉眼可见浓云；官方图（无 mask）行为逐帧不变。
- [ ] 坏 JSON / 越界数值：加载不崩、钳制 + EventLogger 日志。
- [ ] 文件闭环：保存 → 导出 `.aglmap` → 删除本地存档 → 导入 → 继续编辑（editor_cells 无损）→ 试飞，全程无差异。
- [ ] 自动保存：强杀进程后重开编辑器，恢复弹窗能找回最后 ≤120 s 的改动。
- [ ] **官方图转换闭环**：一键转换 → 不做任何编辑 → 试飞，gameplay 逐项一致（is_on_land 抽查 /
      建筑碰撞 / 战区），矢量层逐顶点等同；只涂改一个图层 → 其余图层顶点数据不变（layer_dirty 懒烘焙生效）。
- [ ] 调色板：改任一 §2.5 色值即时预览；不含 style 字段的旧图 = 官方默认色，行为不变。
- [ ] **矢量渲染静态性**（§3.5）：游戏内地图层加载后零 `queue_redraw`（用 Godot 监视器/日志证明）；
      地形覆盖满涂全图时 Sentinel + Lv5 压测 FPS 掉幅 < 15。
- [ ] 矢量版官方图与 PNG 版并排截图对比，用户主观验收"该有的地形层次都有"（山地/城区/农田可辨）。
- [ ] 编辑器场景本身 FPS ≥ 60（全图最大涂量下笔画重算无可感卡顿）。
- [ ] 性能：UGC 图跑 Sentinel + Lv5 压测，FPS 掉幅 < 15。
- [ ] i18n：素材库/工具栏/弹窗全部 tr()，三语已补。

## 6. 实现计划（Task Pipeline —— 工作令）

前置：[ugc-editor](ugc-editor.md) P0 的 `UgcLoader` + map schema（本 spec §2.3 即其定稿）。

### 阶段 1 — 数据与烘焙核心（无 UI，可单测）
- [x] `MapDocument`：schema 读写 + 围栏 + 撤销栈 + layer_dirty（2026-07-04，冒烟 7 组过）
- [x] `ContourBaker`：边界追踪 + 抽稀 + Chaikin（对拍 MapGeography 逐点相等；2026-07-04）
- [x] **官方图转换器**（§3.4）：直通映射 + 陆地/城区并集消重叠 + 栅格化反推 + 陆判 22500 格心逐点对拍（2026-07-04，冒烟 5 组过）
- [x] `UgcLoader` 注入——地理（inject_ugc + ugc_mode 偶奇陆判）/ 建筑（复用分帧预热）/ 云（§3.2 sample_density 唯一注入点 + mask 双线性）；官方回归=无头 5 组（注入等价/建筑与官方管线零差异/clear 还原）（2026-07-04）
- [ ] `UgcLoader` 余项：战区/出生点注入（待 ZoneData 读取口数据化）+ style 调色板数据驱动化（渲染层读色，配合阶段 4 面板）+ 官方图 F5 手测回归

### 阶段 2 — 画布与地形笔刷（最先见效）
- [x] 编辑器场景骨架（scenes/map_editor.tscn + 主菜单"地图工坊"入口）+ 三区布局 + CameraController 复用（缩放范围编辑器自管 0.055~3.0 看全图）（2026-07-04）
- [x] 笔刷/橡皮（1/3/5/9 格圆刷 + 连线补点 + 右键快捷擦）涂 6 个涂格图层 + 笔画结束重烘焙轮廓预览 + 试飞按钮（meta → survivor_mode 注入，_exit_tree 自动 clear）（2026-07-04）
- [x] 保存/另存为/120s 自动保存/恢复弹窗/退出确认（§2.4；导入导出归阶段 3）（2026-07-04）
- [ ] **用户 F5 手测**：涂格手感/轮廓保真/试飞闭环/官方图转换编辑（阶段 2 的真正出口）

### 阶段 3 — 线条与放置工具
- [ ] 道路折线工具；机场/建筑/战区/出生点放置工具
- [ ] 导入/导出 `.aglmap`（文件对话框 + 校验 + 重名处理 + 版本迁移骨架）

### 阶段 4 — 云层与美术风格
- [ ] WeatherSystem mask 注入点（§3.2）+ 云笔刷 + 参数面板（seed/coverage/风）
- [ ] 调色板面板（§2.5 色卡 + 滑条 + 主题预设）+ 编辑态参考图导入（不进成品）
- [ ] 矢量视觉替代包（§3.5）：地形覆盖渲染 + 噪声颗粒 shader + 多边形描边 + 三角合并

### 阶段 5 — 官方图矢量化切换（PNG 退役收尾）
- [ ] 用编辑器重制官方东京湾为矢量版（转换 + 地形覆盖补涂）→ 用户并排验收
- [ ] 打包移除 `tokyo_bay_bg.png` + basemap shader 路径；map-pipeline / manual-map-editing 文档同步改写

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 烘焙流水线（§3.1）+ 逆向栅格化 + 并集消重叠 | `scripts/ugc/contour_baker.gd` |
| 文档数据层（§2.3/§2.4 schema/围栏/撤销/dirty） | `scripts/ugc/map_document.gd` |
| 官方图转换器（§3.4） | `scripts/ugc/official_map_converter.gd` |
| 运行时注入器（§4）+ 注入口 | `scripts/ugc/ugc_loader.gd`（+ map_geography.gd `ugc_mode` / map_geography_data.gd `inject_ugc` / building_renderer.gd `inject_ugc_districts` / weather_system.gd `apply_ugc_config`） |
| 阶段 1 冒烟测试 | `scripts/tests/test_map_editor_core.gd` / `test_official_map_converter.gd` / `test_ugc_loader.gd` |
| 现有多边形渲染/判定 | `scripts/survivor/map_feature_renderer.gd` / `map_geography.gd` |
| 现有云系统 | `scripts/weather_system.gd` |
| 现有建筑渲染 | `scripts/survivor/building_renderer.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-04 | 1 | 初稿：格子笔刷前端 + 矢量后端（marching squares + Chaikin 保真）；三区 UI（素材库左上/画布中间/工具栏含笔刷橡皮线条）；8 可编辑图层含云 mask 与建筑；保真对照表（底图 PNG 为唯一不可涂项）；4 阶段实现计划 |
| 2026-07-04 | 2 | 补 §2.4 文件生命周期（用户要求）：保存/另存为/自动保存恢复/退出确认；导入导出单文件 `.aglmap`（=纯 JSON 含 editor_cells，可二次编辑，即 ugc-editor P4 本地分享的地图部分）；schema_version 迁移策略；验收加文件闭环 + 崩溃恢复两条 |
| 2026-07-04 | 3 | 补 §2.5 调色板（全渲染色进 style，默认=官方现值，含建筑五色/vignette/底图 shader 参数）+ §3.4 官方地图一键转换（gameplay 数据本就是 JSON→格式直通；layer_dirty 逐图层懒烘焙保 1:1；底图 PNG 引用官方资源逐像素一致 + 三态开关）；验收加转换闭环 + 调色板两条 |
| 2026-07-04 | 4 | **底图 PNG 退役**（用户定）：编辑器产出一律纯矢量；PNG 视觉职能矢量化承接（新增地形覆盖图层山/林/田/滩 + post.grain 噪声颗粒 + land_outline 描边）；§2.5 删 basemap 键（参考图仅编辑态）；新增 §3.5 矢量渲染性能预算（静态 canvas 零 queue_redraw / 三角合并，上位法=性能守则 1/2/3）；新增阶段 5 官方图矢量化切换；验收加静态性证明 + 并排对比主观验收 |
| 2026-07-04 | 4 | status: draft → **approved**（用户定稿） |
| 2026-07-20 | 5 | 并入 main（60km 扩图之后）适配：编辑网格从 MapBoundary 主开关派生（300×300）；**判定语义改 layer_mode**（union=官方直通一字不差 / even_odd=烘焙环组，废弃 v4 布尔并集——重烘焙数据上有浮点精度斑点）；转换图陆地/城区恢复逐顶点直通；rasterize bbox 剪枝 grow(0.5) 修边缘排除；编辑器缩放下限按世界尺寸自适应 |
