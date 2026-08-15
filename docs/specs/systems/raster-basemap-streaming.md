---
id: raster-basemap-streaming
kind: map
status: draft
schema_version: 1
spec_version: 1
owner: user
depends_on: [map-system, ui-design-guidelines]
reconstruction_complete: false
---

# 栅格底图分级流送与稳定 Shader

> 保留正式地图 PNG 的美术信息与既有玩法叠层，把单张超大常驻纹理改成同源分辨率金字塔、按视口预取的栅格瓦片和无闪烁的轻量 shader；主地图与 Tab 消费同一份渲染描述。

## 1. 设计意图（Why）

- **体验目标**：地图仍然是玩家已经认可的正式 PNG 风格，海陆、城区、道路、港口与机场信息不因技术迁移而缺失；缩放只改变同一内容的清晰度，不突然生成道路、格子或整片明暗变化。
- **工程目标**：不再让 `8704×8704` RGB8 底图以整张未压缩纹理常驻。当前源文件为 `36,075,000 bytes`，完整 RGB8 像素为 `216.75 MiB`；候选把稳态地图纹理预算压到 `≤64 MiB`，过渡峰值压到 `≤80 MiB`。
- **视觉边界**：本方案不是纯矢量重启，也不重画东京湾。冻结的 V45 矢量候选继续只作研究资料；栅格金字塔的所有层级必须从同一正式源图确定性生成。
- **Litmus 自检**：遵守“先看见，再理解，再精通”。Strategic 让玩家先看海陆和主交通；Operational 补回街区组织；Detail 只提升清晰度，不改变地图语义或玩法判定。
- **反模式规避**：不使用规则格子、随机色块或噪声伪造城市细节；不在战斗中烘焙、GPU readback 或重绘整张地图；不以低画质换取看似更小的包体；不让用户承担逐轮调色 QA。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 源资产与生成物

| 字段 | 值 | 说明 |
|---|---:|---|
| 正式母版 | `8704×8704` RGB PNG | 保留为构建输入和回滚基线；运行时不得整张载入 |
| 母版磁盘大小基线 | `36,075,000 bytes` | 当前东京湾实测 |
| 母版完整 RGB8 像素 | `216.75 MiB` | `8704×8704×3 / 1024²`；当前内存问题的量级基线 |
| 瓦片内容尺寸 | `1024×1024 px` | 标准方形内容区 |
| 过滤外挤 | 四边各 `16 px` | 每张运行时纹理最大 `1056×1056 px`；外挤只供采样，不扩张世界矩形 |
| Strategic 层 | `1024×1024` 单图 | 从母版 Lanczos 下采样；主地图远景与 Tab 常驻 |
| Operational 层 | `4352×4352`，`5×5` 瓦片 | 母版二分之一分辨率；边缘瓦片透明/边色确定性填充到完整内容尺寸 |
| Detail 层 | `8704×8704`，`9×9` 瓦片 | 母版原分辨率；最后一行/列使用确定性边缘填充 |
| mipmap | 每张运行时纹理完整生成 | 缩放过滤使用；禁止依赖无 mip 的远景纹理 |
| manifest | 每地图一份 JSON | 记录 bbox、层级、行列、内容 rect、外挤、hash、色彩 profile 和磁盘字节数 |
| 小型共享纹理 | 最多一张 `64×64` 单通道噪声 | 可跨地图复用，只承载颗粒分布，不得承载地图内容 |

正式母版只允许由离线工具读取。发布包可以只包含 Strategic 与瓦片生成物；在删除或移出母版前，必须先通过 §5 的视觉、性能与回滚门。

### 2.2 三档 LOD 与连续过渡

相机实际缩放范围为 `0.20…5.00`，开局为 `0.35`。LOD 只更换同源分辨率，不裁掉道路、建筑或地形类别。

| 档位 | 主区间 | 预取区间 | 内容 |
|---|---:|---:|---|
| Strategic | `zoom ≤ 0.28` | 常驻 | 一张 `1024²` 全图 |
| Operational | `0.24 < zoom < 0.68` | `0.22…0.74` | 当前视口 + 一圈邻接的半分辨率瓦片 |
| Detail | `zoom ≥ 0.60` | `zoom ≥ 0.54` | 当前视口 + 一圈邻接的原分辨率瓦片 |

- `0.24…0.28` 与 `0.60…0.68` 是重叠带，避免滚轮在单点阈值反复抖动。
- 父子层使用同一色彩 profile；子瓦片在离线阶段对父层同 footprint 做 RGB 均值校正，每通道均值差必须 `≤1/255`。
- 过渡只能在单次绘制中做 `mix(parent_sample, child_sample, t)`，时长 `0.18 s`、smoothstep 曲线；禁止把两张不透明整图以 alpha 叠加，避免缩放时整屏忽明忽暗。
- 瓦片未就绪时继续显示父层；新层不允许露出空白、棋盘格或格子边界。
- Tab 永远只用 Strategic 层，不因打开面板触发 Operational/Detail 载入。

### 2.3 驻留、预取与内存预算

| 字段 | 值 |
|---|---:|
| 稳态 LRU 上限 | `12` 张瓦片 |
| 过渡硬上限 | `16` 张瓦片 |
| 请求评估频率 | 相机跨瓦片/LOD 阈值事件触发；兜底最多 `10 Hz` |
| 同帧新请求上限 | `4` 张 |
| 同帧纹理绑定上限 | `2` 张 |
| Strategic 常驻预算 | `≤5 MiB` |
| 地图纹理稳态预算 | `≤64 MiB` |
| LOD 过渡峰值预算 | `≤80 MiB` |

- LRU 不得淘汰当前可见瓦片、其父层或正在 `0.18 s` 过渡的瓦片。
- 开局载入阶段必须完成 Strategic、玩家出生视口和一圈邻接瓦片预热；进入战斗后只允许读取已生成的磁盘纹理并绑定，不允许现场生成像素或 mipmap。
- 战区 Tab 打开时继续使用已常驻 Strategic，不创建第二份同内容纹理。

### 2.4 色彩与轻量 shader profile

推荐 V3 profile 以当前正式 shader 为基线，只修复黑噪点、过硬描边和低可读性；预览参数是 draft，必须经 Godot 同位 A/B 后才能转 approved。

| 字段 | 当前 | 候选 V3 |
|---|---:|---:|
| saturation | `0.40` | `0.42` |
| brightness | `0.70` | `0.73` |
| contrast | `1.25` | `1.22` |
| tint RGB | `(0.78, 0.82, 0.80)` | `(0.80, 0.84, 0.82)` |
| edge strength | `1.20` 实时 8 邻域 Sobel | 离线柔化边，等效 gain `0.85`、上限 `0.55` |
| edge color RGB | `(0.10, 0.12, 0.10)` | `(0.15, 0.17, 0.16)` |
| grain | `0.03`、含 `TIME` | `0.004`、固定世界空间 |
| vignette | 既有独立覆盖 | 继续独立覆盖；候选预览强度 `0.025` |

- 结构边在瓦片生成阶段烘入 RGB：先从母版亮度计算 Sobel，`0.55 px` Gaussian 柔化，再限幅合成；运行时 shader 不再对每像素额外采 8 个邻居。
- 颗粒坐标以世界空间为准，不使用 `TIME`，静止与缩放时不得闪烁或改变相位。
- 运行时 shader 只保留全局 tint/saturation/brightness/contrast、固定颗粒与必要的父子层混合；静止地图的 uniform 只在创建、设置改变或短暂 LOD 过渡时写入。
- 主地图和 Tab 使用同一 profile；Tab 的既有扫描线、标记与暗角仍属于 UI 后绘制，不重复烘入瓦片。

### 2.5 UI 规范继承

Tab 地图继续继承 `ui-design-guidelines` 的面板、输入、裁切和刷新规则。本方案不改变 Tab 布局、文字、标记、交互与动态层，因此没有 UI 规范例外；只把面板底图来源改为同一地图的 Strategic 纹理。

### 2.6 磁盘格式策略

1. 第一验收候选使用无损 PNG 瓦片，先证明与母版同源且无接缝。
2. 通过无损视觉门后，才生成 GL Compatibility 可用的 GPU 压缩候选；压缩候选必须与无损候选同位 A/B，不能仅凭文件大小替换。
3. 任何压缩候选出现道路断线、海岸色带、建筑糊边或远景 shimmer，即回退无损瓦片；运行时内存目标优先由“只驻留可见瓦片”实现，不依赖有损压缩强行过门。

## 3. 行为与公式（How）

### 3.1 离线构建

```text
read formal master once
apply deterministic color + softened structural-edge profile
build Strategic / Operational / Detail pyramid from the same processed master
for every tile:
  crop content rect
  copy 16 px neighbor gutter on all sides
  pad only outside-map pixels deterministically
  generate mipmaps
  record hash + footprint + parent mapping
verify every same-level seam and every parent/child mean
write manifest last
```

生成失败时不得覆盖上一份完整 manifest。工具产出的 scratch、diff 和参数 sweep 全部写入 `tmp/`；只有通过离线检查的最终瓦片才进入 Godot 扫描目录。

### 3.2 载入与显示状态

| 状态 | 触发 | 显示 | 允许工作 |
|---|---|---|---|
| BOOT | 进入地图载入 | loading 画面 | 载入 Strategic，预取出生视口 |
| READY | Strategic 可用 | Strategic 不透明底 | 最多 `4` 请求/帧 |
| PREFETCH | 相机进入预取区 | 旧层保持 | 后台读取当前视口 + 一圈邻接 |
| TRANSITION | 新层当前视口完整 | 单次采样混合 `0.18 s` | 最多 `2` 绑定/帧；仅过渡期更新 mix |
| STABLE | 过渡完成 | 新层不透明 | 停止 shader 参数写入与地图更新 |
| FALLBACK | manifest/瓦片失败 | 最近可用父层 | 记录错误；不阻塞战斗 |

### 3.3 视口瓦片集合

```text
visible_rect = camera_world_rect.expanded(one_tile_world_size)
required = tiles_intersecting(visible_rect, target_lod)

if required.size > 12:
  keep parent lod
else:
  request missing required tiles by distance_to_view_center
```

任一目标瓦片缺失时不得只显示半套子层；当前视口完整前继续用父层。相机平移只改变增量集合，不重新提交已经驻留的静态瓦片。

### 3.4 失败与回滚

- 单瓦片损坏：显示父层对应区域，开发日志记录地图 id、LOD、行列和 hash；战斗不中断。
- manifest 损坏：只显示 Strategic；Strategic 也失败时回到现有正式单 PNG 路径，直到毕业迁移完成。
- 候选开关关闭：完整走当前正式 PNG + shader，不混用候选 tile cache。
- 在主图和 Tab 同时通过毕业门前，不删除、不覆盖、不降质 `tokyo_bay_bg.png`。

## 4. 结构与组成（Structure）

- **BasemapBuildProfile**：离线 profile，持有三档尺寸、瓦片/外挤、色彩、柔化边和 hash 规则。
- **BasemapTileManifest**：每地图运行时只读描述，映射世界 bbox、LOD、父子 footprint 和资源路径。
- **RasterBasemapTileCache**：异步请求、12 张 LRU、可见集合完整性和失败回退；不持有玩法地理。
- **RasterBasemapRenderer**：一个常驻 Strategic canvas + 最多 12 个静态可见瓦片 canvas；只在集合变化时增删，过渡结束即停止处理。
- **MapFeatureRenderer adapter**：继续承载正式玩法覆盖、机场、建筑和 vignette；底图来源由开关选择旧单 PNG 或共享 tile renderer。
- **TacticalMap adapter**：只取得共享 Strategic 纹理，继续绘制战区、单位、扫描线与暗角。
- **离线 QA**：固定全图、湾区、横滨港/机场、Tab 四机位，生成同位擦除、差分、接缝和亮度报告。

## 5. 验收标准（Acceptance / Litmus）

### 5.1 视觉

- [ ] 同一色彩 profile 下，无损 Detail 与正式母版的可见区域逐像素一致；只允许定义过的外挤与 mip 过滤差异。
- [ ] 全图、湾区、横滨港/机场、Tab 四档在 100% 与 200% 检查：无格线、接缝、空白、道路断线、海岸色带或漂在海上的图元。
- [ ] sea core、land、urban、port land、airport 五区每通道 mean 与正式参考差 `≤4 RGB`；候选 V3 若主动改色，必须先由用户拍板再更新参考。
- [ ] 任一 LOD 过渡前后整帧平均亮度变化 `≤1%`，局部分区 mean 变化 `≤2 RGB`；滚轮连续操作不出现整屏忽明忽暗。
- [ ] 缩放不新增或删减地图 feature；只提升纹理清晰度。没有规则格子、随机色块或突然出现的道路/建筑。
- [ ] 颗粒静止、世界空间锁定；连续两帧静止截图的底图 RGB 差为 `0`。
- [ ] 正式 `BuildingRenderer` 的玩法建筑/假 3D 楼、机场覆盖及其它共享上层在旧 PNG 与候选两侧完全一致，不被瓦片底图删掉或遮住。
- [ ] 用户只审核完成内部至少 3 轮自审后的单一推荐稿；反馈必须回写本 spec/profile，不能让下一张地图重新调同一问题。

### 5.2 性能与内存

- [ ] 启动 loading 结束前 Strategic 和出生视口已就绪；进入战斗后的首次滚轮不触发同步解码、mipmap 生成或 SubViewport 烘焙。
- [ ] 地图纹理稳态 `≤64 MiB`、过渡峰值 `≤80 MiB`；报告同时列当前整图基线 `216.75 MiB`。
- [ ] 静止相机下：地图 `queue_redraw=0`、纹理请求 `0`、shader uniform 写入 `0`、地图专用 `_process` 自动停用。
- [ ] 主地图底图 draw call：Strategic `1`；Operational/Detail `≤13`（1 个父层 + 最多 12 个子瓦片）；Tab 底图 `1`。
- [ ] 运行 Sentinel + Lv5 和 Lv8 同场景 A/B：候选平均 FPS 不低于正式 PNG `5 FPS` 以上，且不新增低于 `60 FPS` 的帧；若不满足，优先减少预取圈、过渡并发和颗粒，而不是删地图信息。
- [ ] 切换相机与打开 Tab 不超过同帧 `4` 个新请求、`2` 个纹理绑定；无单帧磁盘风暴。

### 5.3 兼容、文档与毕业门

- [ ] Godot `4.7+`、GL Compatibility、Windows 导出包验证；不以编辑器 Forward+ 结果替代。
- [ ] 正式东京湾、图 2/图 3、UGC vector-only 的路径彼此隔离；UGC 不误载东京湾瓦片。
- [ ] Tab 和主图共用 manifest/profile/Strategic，不存在第二套硬编码东京湾底图。
- [ ] 文档：本 spec 已登记 `_INDEX`；批准后同步 map-system、map-pipeline 与 reference 索引。
- [ ] 删除毕业门：连续两次同机 Visual A/B 全部通过本节，用户确认最终整图与 Tab 画面，回滚包已验证，才允许在同一变更中让主图与 Tab 同时停止引用大型单 PNG；此前禁止删除原文件。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — Spec 与离线方向验证
- [x] 建立 draft spec，冻结“同源栅格金字塔 + 稳定 shader”，明确不重启纯矢量。
- [x] 在 `tmp/raster_basemap_preview/` 生成当前 shader / 候选 V1～V3 的同位预览、指标与可擦除对比；未改生产代码。
- [ ] 用户确认候选色彩方向后，把 profile 数值转为 approved。

### 阶段 1 — 无损金字塔与离线 QA
- [ ] 新增确定性 cutter/profile/manifest 工具；母版不进入运行时加载。
- [ ] 生成 Strategic、Operational、Detail 无损瓦片并验证 hash、父子均值、全部横纵接缝和 mip。
- [ ] 输出磁盘、解码、纹理实占和四机位同位报告。

### 阶段 2 — 共享运行时 renderer
- [ ] 实现 manifest、异步 tile cache、12 张 LRU 与可见集合完整性门。
- [ ] 实现单次父子采样混合和稳定世界空间颗粒；移除候选路径的实时 8 邻域 Sobel。
- [ ] 静态态自动停用处理；uniform 只在设置/短暂过渡时更新。

### 阶段 3 — 主地图、载入与 Tab 接线
- [ ] 在正式 loading 阶段预热 Strategic + 出生视口；主图加入 debug A/B 开关，默认仍旧 PNG。
- [ ] TacticalMap 改读共享 Strategic，但 A/B 默认仍旧路径；动态标记和 UI 后处理不变。
- [ ] 保持玩法建筑/假 3D 楼、机场、手画覆盖、天气与所有 gameplay 层在两侧一致。

### 阶段 4 — Visual 与压力验收
- [ ] 跑全图/湾区/港区机场/Tab 100% 和 200% 同位 QA，完成至少 3 轮内部自审。
- [ ] 跑 Sentinel + Lv5、Lv8 同场景长压测，记录启动耗时、请求峰值、draw call、纹理内存、平均/最低 FPS。
- [ ] 如无损瓦片已过门，再单独评估 GPU 压缩候选；失败即保留无损。

### 阶段 5 — 毕业切换与回滚
- [ ] 用户确认最终整图、细节和 Tab 里程碑。
- [ ] 同一变更中把主地图与 Tab 默认切至共享瓦片，验证旧 PNG 回滚开关和回滚包。
- [ ] 仅在两次完整视觉/性能门通过后，另行提议移出或删除大型单 PNG；未获明确授权不得执行。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 当前正式主图 | `scripts/survivor/map_feature_renderer.gd` |
| 当前正式 shader | `resources/shaders/basemap_tacview.gdshader` |
| 当前 Tab 地图 | `scripts/survivor/tactical_map.gd` |
| 当前母版与元数据 | `resources/maps/tokyo_bay_bg.png` / `resources/maps/tokyo_bay_bg.json` |
| 离线 draft 预览 | `tmp/raster_basemap_preview/render_preview.py` |
| 未来共享 renderer | 待阶段 2 落地后登记 |
| reference 索引 | `docs/reference/map-pipeline.md` / `docs/reference/script-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-15 | 1 | 建立栅格金字塔与稳定 shader 的 draft：保留正式 PNG 美术源，三档只切同源分辨率，定义 12 瓦片 LRU、64/80 MiB 预算、无整屏明暗跳变和主图/Tab 同时毕业门；附离线 V1～V3 对比预览。 |
