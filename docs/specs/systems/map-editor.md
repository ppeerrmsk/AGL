---
id: map-editor
kind: system
status: approved     # ✅ 用户定稿；2026-08-08 明确保留正式东京湾 PNG
schema_version: 1
spec_version: 19
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
- **审核责任裁决（用户定 2026-08-05）**：编辑器与 agent 工具链必须支持批量固定机位、同位擦除、
  分层诊断和多轮参数迭代。用户不逐轮调色或查错；agent 先按 [map-pipeline §0](../../reference/map-pipeline.md)
  至少完成 3 轮内部迭代，只提交过客观门的里程碑候选。
- **⚑ 正式底图 PNG 保留（用户定 2026-08-08，替代 2026-07-04 退役决定）**：东京湾主地图与 Tab 地图继续使用
  `tokyo_bay_bg.png` + shader；编辑器不得把“官方图 dogfood”解释为强制重制或删除 PNG。UGC 试飞仍按现有
  vector-only 边界运行，地形覆盖、调色板、颗粒与描边能力服务于 UGC/新增地图，不再承担复刻正式 PNG 的毕业义务。

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
| 地形覆盖（山地/森林/农田/沙滩） | 笔刷/橡皮 | `terrain_overlays: [{type, polygons}]`（叠在陆地上，为 UGC/新增图提供地形变化） | 矢量渲染（调色板取色） |
| 城区 | 笔刷/橡皮 | `urban_polygons`（同上，叠在陆地上） | 城区底色渲染 |
| 机场/跑道 | 放置（矩形+角度） | `airports: [{center, size, rotation}]`（玩法判定）+ `airport_features: [{kind, geometry}]`，kind ∈ {runway, taxiway, apron}（视觉细节） | 渲染 + 着陆判定 |
| 道路 | 线条工具（折线） | `roads: [{points, width_class}]`，width_class ∈ {motorway, trunk, primary, secondary, tertiary, residential, service} | 道路渲染；按 LOD 筛选 |
| 港区设施 | 折线/多边形工具 | `port_features: [{kind, geometry}]`，kind ∈ {pier, breakwater, groyne, industrial_area} | 港池轮廓、工业地块与岸线家具渲染 |
| 建筑 | 放置（多边形/矩形 + 高度档） | `buildings: [{footprint, h_m}]`，高度档预设 30/80/150/300 m | BuildingRenderer（伪 3D + 低空碰撞） |
| 云层 | 笔刷/橡皮（密度） | `cloud: {seed, coverage, frequency, wind_dir_deg, wind_speed_ms, mask: 64×64 字节}` | WeatherSystem `sample_density` |
| 战区 | 放置（圆：center+radius+type） | `zones: [{center, radius, type}]` | spawner / 战区结算 |
| 玩家出生点 | 放置（单点+朝向） | `spawn: {pos, heading_deg}` | 开局注入 |

海面**不单独存**：不在任何 land 多边形内 = 海（与现行 `is_on_land` 语义一致）。

### 2.3 map JSON schema（`user://ugc/maps/<name>.json`）

```
{ schema_version: 1, display_name, world_size_m,
  land_polygons, terrain_overlays, urban_polygons,
  airports, airport_features, roads, port_features,
  buildings, cloud, zones, spawn,
  style: {...},           # UGC 调色板 + 后处理；正式东京湾 PNG 不进入 UGC 文档
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
| `palette.road_shadow` | (0.32, 0.40, 0.40, 0.24) | 道路环境色投影；禁用纯黑阴影 |
| `palette.road_casing` | (0.39, 0.44, 0.44, 0.17) | 道路冷灰绿包边 |
| `palette.road_major` / `road_trunk` | (0.63,0.60,0.47,0.81) / (0.62,0.62,0.53,0.74) | 高速/主干暖灰芯线 |
| `palette.road_primary` / `road_secondary` | (0.60,0.62,0.56,0.64) / (0.59,0.62,0.58,0.47) | 一级/二级道路芯线 |
| `palette.road_tertiary` / `road_center_highlight` | (0.62,0.64,0.60,0.35) / (0.80,0.76,0.60,0.24) | 三级道路与高速克制中心提亮 |
| `palette.tacview_cross` | (0.55, 0.75, 0.82, 0.30) | 海面"+"十字 |
| `palette.building_roof` | (0.62, 0.59, 0.53, 1.0) | 建筑屋顶 |
| `palette.building_wall_lit` / `wall_shade` | (0.52,0.49,0.43,1.0) / (0.26,0.25,0.23,1.0) | 建筑受光/背光墙面 |
| `palette.building_shadow` | (0.34, 0.41, 0.41, 0.13) | 建筑冷灰绿投影；不得压成黑块 |
| `palette.city_block_shadow` | (0.44, 0.49, 0.48, 0.38) | 街区体块阴影 |
| `palette.building_outline` | (0.10, 0.10, 0.09, 0.6) | 屋顶描边 |
| `palette.terrain_mountain` | (0.38, 0.36, 0.32, 1.0)（初值，实装调）| 地形覆盖：山地 |
| `palette.terrain_forest` | (0.24, 0.32, 0.22, 1.0)（初值，实装调）| 地形覆盖：森林 |
| `palette.terrain_farmland` | (0.36, 0.36, 0.24, 1.0)（初值，实装调）| 地形覆盖：农田 |
| `palette.terrain_beach` | (0.46, 0.42, 0.32, 1.0)（初值，实装调）| 地形覆盖：沙滩 |
| `post.vignette` | 三环 (0.04,0.05,0.07)×α 0.30/0.55/0.90 @ 280/700/2000 px | 边缘暗角 |
| `post.grain` | 0.03 | UGC 矢量图的世界空间程序噪声颗粒 |
| `post.land_outline` | (0.10, 0.12, 0.10, 0.6)，宽 1.5 px | UGC 陆地/地形覆盖多边形描边 |

- 光照方向（建筑投影）`style.light_dir`：默认 (-0.7, -0.7) 归一化。
- **阴影色规则（用户反馈 2026-08-05）**：道路、建筑、街区阴影从相邻海陆环境色偏移，默认冷灰绿；
  禁止用高不透明纯黑制造层次。阴影只负责分离 casing/体块，不能替代道路宽度、建筑覆盖或地形数据。
- **道路细节规则（V10）**：所有等级离线生成圆角 join/cap；断开的 OSM way 端点需用 junction pad 闭合视觉缝；
  高速/主干允许克制中心提亮，primary 以下不画发光。住宅装饰路可艺术化偏转与断续，但必须形成连续街区骨架，
  禁止重复“十字”、全局正交网格或随机划痕；具有导航意义的道路仍必须来自正式矢量数据。
- **真实细路与设施规则（V11）**：Detail LOD 的 residential/service 必须来自 OSM 或编辑器显式折线，程序街区纹理只能补材质频率，
  不能代替道路拓扑。service 短枝在烘焙期按屏幕贡献度过滤；Strategic/Operational 不得泄漏住宅细路。机场必须拆出
  runway/taxiway/apron，港区必须支持 pier/breakwater/groyne/industrial_area；这些图元与 land/coast 共用拓扑裁切，禁止漂在海面。
- **三层信息规则（V13）**：编辑器预览与正式 renderer 必须共用 Strategic base / Operational features / Detail features 三层描述。
  sea/land/shallow/final coast/城市大形属于始终不透明的 base；Operational 与 Detail 只能增加透明 feature，禁止交叉淡化两张含完整底色的地图。
  Strategic/Tab 禁止逐建筑；Operational 只允许面积/高度/地标等级筛出的少量 large 概括体块，中小建筑由城市 density mass 与真实街区骨架表达；完整建筑、住宅/service 路和局部港区家具只在 Detail 出现。道路概括必须来自真实道路分级或显式艺术化控制点，禁止规则格子。
- **城市性能预算（V13）**：编辑器烘焙必须分别报告四档建筑数、三角数和 draw call。Operational 默认上限为 large roof `115k` 三角 + 单一 casing `115k` 三角，总静态根层 `1.1M` 三角 / `24` draw calls；超过预算按 `small -> medium -> 非地标 large` 顺序从较远 LOD 剔除，不得逐栋 Node2D、不得在战斗期重建。Detail 只允许 loading/真暂停瓦片缓存恢复完整城市；帧数不达门时优先减中小建筑和道路支线，不牺牲海陆大形、机场识别或主干路。
- **高度层级（V17）**：城区大面积保持 density mass + 街区骨架 + 低浮雕；只有显式高度 `>=80m` 的地标允许突破普通建筑的 52px 投影上限，且最高 122px。编辑器导出时必须用投影后 bbox 分配瓦片，并为这些高层离线三角化同方向偏移顶面；先画全尺寸冷暗 casing，再画约 1.6px 内缩米灰屋顶，形成窄深边。高层墙体必须足够实体，禁止白色悬浮碎片或粗黑顶面；禁止逐栋运行时视差或每帧重绘。
- **远景盐点门（V18）**：编辑器三档预览必须在全图/Tab 尺度自动检查逐建筑是否退化为黑白盐点。Strategic/Tab 不提交逐栋数据；主地图允许在同一不透明根内仅对建筑 feature packet 做连续门控，当前官方阈值为 zoom 0.18–0.30。底色、城市 mass、道路、机场与海岸不得参与淡化，禁止用整图 alpha 解决盐点。
- 围栏：alpha 不设限但 UI 提示"全透明图层会不可见"；无非法值面（颜色天然有界）。
- UGC `MapDocument` 不携带任意大型内容 PNG；编辑器支持“导入参考图”，但**仅编辑态显示**
  （半透明描图垫），不写入成品 JSON、不参与导出、不进 UGC 试飞。正式东京湾 PNG 由官方资源路径独立持有，转换器不得删除或改写它。

## 3. 行为与公式（How）

### 3.1 格子 → 多边形流水线（保真核心）

```
涂格 bitmap（随主开关的 N×N bool per 图层，60km 现值 300×300）
  → marching squares 提取闭合轮廓（外环+孔洞）
  → Douglas-Peucker 抽稀（epsilon = 0.8 × 格边长，v6：0.4→0.8 先杀格距阶梯）
  → Taubin 无收缩平滑 ×3 对（λ=0.5 / μ=−0.53，v6 新增：消格距抖动且不缩水）
  → Chaikin 平滑 ×3 轮（v6：2→3；数学与现有手画地块同款）
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
| 矩形/圆形/三角形（v6） | 拖拽拉出图形 → 精确谓词写格 → 同一平滑管线；左键画/右键擦；Esc 取消拖拽中图形 |
| 导入图片（v6） | 系统对话框选 PNG/JPG → 铺满全图的半透明垫图（仅编辑态，不入成品）；可显隐 |
| 提取到当前图层（v6） | 按亮度阈值把垫图暗（或亮）区域逐格心采样并入当前图层 → 重烘焙平滑。黑白剪影图即"画好形状导入即得"，兜底"PNG 定义形状"需求 |
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

底图 PNG 不进入 UGC JSON 的矢量转换；转换器只搬运 gameplay/编辑数据。正式东京湾运行时继续从官方资源路径加载原 PNG，转换与编辑不得删除、覆盖或降质该资源；导入的外部参考图仍只作编辑态描图垫。

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

### 3.5 矢量图层与正式 PNG 共存的性能预算

UGC/编辑器矢量视觉与官方 PNG 路径共同遵守以下规则（performance-guidelines 第 1/2/3 条是本节的上位法）：

| 项 | 方案 | 性能约束 |
|---|---|---|
| 地图静态层（陆地/地形覆盖/城区/道路） | 画进**静态 canvas item，只画一次**；相机移动/缩放靠 canvas transform，**不触发 queue_redraw**（历史翻车点：地图每帧重算） | 重绘仅在数据变化时（编辑器内笔画结束 / 游戏内永不） |
| 多边形数量 | 官方量级：陆地 ~1000 顶点 + 城区 160 + 道路 1012 条；地形覆盖预计再 +200~500 个多边形 | 同层多边形用 `RenderingServer.canvas_item_add_triangle_array` 合并，禁止逐多边形 draw call 裸奔 |
| 纹理颗粒 | 世界空间噪声 shader 叠在陆地层（单材质、GPU 常数开销） | 一个全屏 pass 以内 |
| 描边 | 多边形轮廓 polyline（数据静态，随层一次画完） | 同静态层规则 |
| 正式底图 | 东京湾 8704×8704 PNG + shader 保持生产基线；主地图与 Tab 复用同一资产语义 | 编辑器/矢量图层的预算不得假设 PNG 已删除 |

预算结论：不能预设矢量化一定比 PNG 更便宜，必须按真实 GL Compatibility 场景测量；无论哪条路径，
**任何人给静态地图层加每帧 `queue_redraw` 即违规**，验收有对应条目。

### 3.6 视觉 QA 工作台与自主迭代

编辑器必须提供一个开发/审核模式，使新地图不依赖用户逐轮肉眼找错：

- **同位查看**：Reference / Candidate / Wipe / Difference 四种视图；参考图可调透明度但只存在编辑态，不写入 MapDocument、导出包或运行时 cache。
- **固定矩阵批量截图**：一键输出 Strategic / Operational / Detail / Tab，覆盖全图、典型海岸、港区、机场和城区；视野、zoom、输出尺寸与命名稳定，可跨版本逐像素定位。
- **图层 solo**：sea/shallow、land/terrain、urban、coast、roads、airport、buildings、grain、vignette 可独立显隐，避免整图平均色掩盖局部问题。
- **自动报告**：输出分材质 mean/stddev、拓扑异常数、道路/建筑屏幕密度、LOD 层清单、packet/draw-call 预算和未过门项。指标用于拒绝明显失败，不替代最终美术判断。
- **运行时证据硬门**：Pillow/离线合成图只允许筛掉明显失败，不能替代游戏画面或直接把其 palette 数值复制进 triangle-array renderer。候选进入共享 renderer 后，必须从 Godot GL Compatibility 的真实主地图与 Tab 固定机位截图重新计算陆海、层次与道路指标；两条运行时路径都过门前不得向用户宣称视觉改善完成。
- **参数 sweep**：允许对 palette、road width/alpha、coast width/alpha、shallow bands、urban density 做离线批量候选；每轮只采纳有明确改善的参数，禁止运行时每帧调参或重烘焙。
- **审核节奏**：agent 默认内部迭代 3～8 轮；两轮无改善即转为数据/工具缺口诊断。对用户最多提交 1 个推荐稿 + 2 个真正不同方向的备选，不提交连续编号的半成品。
- **反馈沉淀**：用户对色调、道路、海岸、柔化和密度的反馈必须更新为 style profile、固定机位或验收阈值；新地图默认继承，不得再次从零询问同一偏好。
- **整图覆盖门**：局部金样获批后，agent 必须自动把同一 style profile 烘焙到全部非空瓦片，并覆盖全图、中景三岸、至少四个城市近景、四瓦片交点和 LOD 阈值两侧；瓦片外挤只能供纹理过滤，禁止作为世界显示区与邻格重复叠加。
- **整图 atlas 门（V14）**：固定机位通过后还必须逐格调用生产 renderer 与生产超采样/降采样/色阶路径，为清单全部瓦片生成一张世界坐标对齐的缩略 atlas；不得用 Pillow 重画矢量内容。报告必须区分预期空格与真实失败，记录每格 feature/triangle/bake 指标，并比较所有横纵边界与相邻内部像素梯度。东京湾基准为 203 格全部处理、199 非空、4 预期空、真实失败 0；30 条整图边界的平均额外色差约 0.396 RGB、峰值 1.581 RGB，硬门 `<3 RGB`。atlas 与报告只能写入 `tmp/`。
- **性能对拍门**：候选必须在 Godot 4.7 GL Compatibility 的真实 Visual bench 中与 PNG 使用完全相同的 C1 负载、seed、镜头和 UI；另跑 S3 冷启动/transition。三次中位 avg 回退 `≤5%`、p1 回退 `≤10%`，且不得新增低于 60 FPS 的帧或运行中瓦片尖峰；不得交给用户试玩发现。

截图、diff、sweep 与报告只写 `tmp/` 或项目外可视化目录；QA 使用一次性离线烘焙或 `SubViewport.UPDATE_ONCE`，不得让生产地图持续 redraw。

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
| 正式底图 PNG + shader | ✅ 保留为东京湾主地图与 Tab 地图的生产表现；编辑器转换 gameplay 矢量数据时不删除、覆盖或重烘焙该资源。UGC/新增图继续用自身矢量 style |
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
      地形覆盖满涂全图时按 C1 + S3 成对压测，满足当前绝对与相对门。
- [ ] **正式 PNG 保留回归**：官方图经转换器打开、保存或试飞后，主地图与 Tab 仍消费同一张原始 PNG + shader，像素尺寸/资源文件不被编辑器改写；UGC vector-only 行为不变。
- [ ] **自主迭代闭环**：从同一基线连续完成至少 3 轮内部诊断→修改→复测，只向用户展示过客观门的里程碑；测试记录能证明不是把每轮半成品交给用户查错。
- [ ] **视觉 QA 工作台**：四档固定矩阵、同位擦除、Difference、图层 solo、局部 mean/stddev 与拓扑/密度报告可重复生成；输出全部位于 `tmp/` 或项目外。
- [ ] **反馈可继承**：批准的 style profile 应用于第二张测试地图后，无需用户再次指出黑色噪点、悬空海岸、道路层级、低清预览或整体色调基线问题。
- [ ] **阴影与道路回归**：固定 detail 机位中，阴影无纯黑块；五级道路层级可辨，join/cap 无针刺、断头和十字重复纹；Operational/Strategic LOD 不泄漏住宅细路。
- [ ] **真实密度与设施回归**：固定横滨 detail 机位的 residential/service 来自正式矢量或编辑器显式图元，不能用程序网格冒充；机场 runway/taxiway/apron 与港区 pier/breakwater/industrial_area 在对应 LOD 层级可辨、无悬空、无越过 land/coast 裁切。
- [ ] 编辑器场景本身 FPS ≥ 60（全图最大涂量下笔画重算无可感卡顿）。
- [ ] 性能：UGC 图按 C1 + S3 同条件成对跑暖稳态、冷启动和 transition；实际全图覆盖与 UI 必须可见。
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
- [ ] 道路折线工具（七级 width_class + LOD 预览）；机场 gameplay footprint + runway/taxiway/apron；港区 pier/breakwater/groyne/industrial_area；建筑/战区/出生点放置工具
- [ ] 导入/导出 `.aglmap`（文件对话框 + 校验 + 重名处理 + 版本迁移骨架）

### 阶段 4 — 云层与美术风格
- [ ] WeatherSystem mask 注入点（§3.2）+ 云笔刷 + 参数面板（seed/coverage/风）
- [ ] 调色板面板（§2.5 色卡 + 滑条 + 主题预设）+ 编辑态参考图导入（不进成品）
- [ ] 矢量视觉替代包（§3.5）：地形覆盖渲染 + 噪声颗粒 shader + 多边形描边 + 三角合并
- [ ] 视觉 QA 工作台（§3.6）：固定矩阵批量截图 + wipe/diff/layer solo + 指标报告 + 离线参数 sweep；产物写 `tmp/`

### 阶段 5 — 官方图兼容与 PNG 保留
- [ ] 官方东京湾转换/编辑只修改 gameplay 矢量数据；试飞与正式主地图继续挂接现有 PNG + shader
- [ ] 主地图与 Tab 的 PNG 路径做一致性回归；禁止编辑器保存、导出或打包流程删除/覆盖 `tokyo_bay_bg.png`

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
| 2026-07-20 | 6 | 用户首测反馈落地：①平滑管线重做（DP 0.8×格 + Taubin 无收缩 3 对 + Chaikin ×3；纯拉普拉斯会缩水被环形/往返测试否决）②图形工具矩形/圆形/三角形（拖拽+预览+右键擦）③PNG 垫图导入 + 亮度阈值提取到图层④地形覆盖层游戏内渲染（UgcLoader.overlay_layers_from → MapFeatureRenderer.ugc_overlay_layers，官方图零影响）。城区层游戏内已有建筑块渲染（既有 _draw_urban_districts 白拿）；道路线条工具仍归阶段 3 |
| 2026-08-05 | 7 | 用户明确审核责任：新增 §3.6 视觉 QA 工作台与 3～8 轮 agent 自主迭代协议；固定矩阵/wipe/diff/layer solo/局部色准/拓扑密度报告；半成品不逐轮交用户，反馈沉淀为可跨地图复用的 style profile 与验收回归 |
| 2026-08-05 | 8 | V10 阴影/道路反馈沉淀：黑色投影改为环境冷灰绿；道路拆为 shadow/casing/五级 core/克制中心提亮；圆角 join/cap、junction pad、LOD 隔离与“禁重复十字/全局网格”成为验收硬门 |
| 2026-08-05 | 9 | V11 真实数据补层：道路 schema 扩为七级并要求 residential/service 来自正式矢量；新增 airport_features 与 port_features，规定机场内部、港区设施、短 service 过滤、LOD 隔离及 land/coast 拓扑裁切；对应工具与验收同步补齐 |
| 2026-08-05 | 10 | 实机视觉假绿复盘：离线 Pillow 合成只作预筛，禁止直接复用其 palette 或冒充游戏验收；候选必须以 Godot GL Compatibility 主地图 + Tab 固定机位运行时截图重新评分，两条路径都过门后才可向用户提交视觉里程碑。 |
| 2026-08-06 | 11 | 将用户认可的横滨金样沉淀为跨地图规则：同一 MapDocument/style profile 产出 Strategic/Operational/Detail 三层描述；基础海陆永不参与 LOD alpha，编辑器四档预览必须检查 feature 淡入与瓦片接缝。 |
| 2026-08-06 | 12 | 将全东京湾扩展经验写成新地图默认生产门：批准局部金样后自动覆盖全部非空瓦片与全图固定矩阵；瓦片 padding 仅供过滤、不得重复覆盖世界；真实 Godot Visual bench 必须以同单位样本对拍 PNG，并把运行中流送尖峰纳入 60 FPS 硬门。 |
| 2026-08-07 | 13 | 固化“城市可概括、帧数是死线”：Strategic/Tab 完全不提交逐栋建筑；Operational 仅允许预算内 large 地标体块和单一 casing，中小建筑由 density mass + 真实街区骨架概括；完整屋顶/侧墙只在 loading 或真暂停生成的 Detail 瓦片恢复。编辑器必须按 LOD 报建筑/三角/draw-call，并按 small→medium→非地标 large 顺序自动降级。 |
| 2026-08-07 | 15 | 增加静态高度层规则：普通城市仍为低浮雕概括，仅显式 `>=80m` 地标可按分段曲线投影到最多 122px；导出按投影 bbox 跨瓦片复制，禁止恢复逐栋运行时视差。整图视觉与压力门仍是发布前置。 |
| 2026-08-07 | 16 | 高层导出补齐静态偏移顶面：只对真实 `>=80m` 地标离线耳切，使用米灰顶面与高不透明度墙体，仍并入单批次；第一版发白悬浮方案明确作为反例。 |
| 2026-08-07 | 17 | 高层顶面补窄深 casing：复用同一耳切索引先画全尺寸冷暗底、再画约 1.6px 内缩屋顶，不新增 packet/draw call；整图高度几何硬预算提高但封顶 210k。 |
| 2026-08-07 | 18 | 固化跨尺度盐点审计：全图与 Tab 必须自动检查亚像素逐栋噪点；官方主图只在 zoom 0.18–0.30 连续恢复两个建筑 feature packet，所有不透明 base/骨架层保持固定，禁止整图交叉淡化。 |
| 2026-08-07 | 14 | 增加整图 atlas 毕业门：固定机位不再代替全覆盖证明；显式 Visual bench 必须逐格复用生产 renderer 和缓存色阶，把所有瓦片叠在同一 Operational 世界底图上，并自动审计预期空格、真实失败与 30 条横纵边界的额外 RGB 跳变。产物仅进 `tmp/`。 |
| 2026-08-08 | 19 | 用户最终否决全东京湾纯矢量替换效果，撤销 v4 的 PNG 退役目标：正式主地图与 Tab 保留 8704×8704 `tokyo_bay_bg.png` + shader。编辑器仍提供 UGC vector-only 与 gameplay 矢量编辑能力，但官方转换不得删除、覆盖或重烘焙 PNG；阶段 5 改为官方图兼容与保留回归。 |
