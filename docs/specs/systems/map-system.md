---
id: map-system
kind: map
status: done
schema_version: 1
spec_version: 5
owner: design
depends_on: [map-boundary, map-geography]
reconstruction_complete: false
---

# 地图 / 地形系统（边界 + 地理 + 渲染 + 三条流水线，含扩展接入图）

> AGL 的地图是**手画地理覆盖 + OSM 烘焙数据 + 底图 PNG** 三层叠加，配一个方形世界边界。正式东京湾保留 PNG + shader；代码在资源缺失时仍 fail-open 到矢量层。
> 当前唯一地图是手画的**东京湾**。本 spec 兼作**加新地图的接入图**（§6）。
> ⚠ `reconstruction_complete: partial`：边界/坐标系/查询 API 已核对源码；Python 流水线脚本细节
> 引用现有 [map-pipeline.md](../../reference/map-pipeline.md) / [manual-map-editing.md](../../reference/manual-map-editing.md)，不在此重抄。

## 1. 设计意图（Why）

- **体验目标**：用真实地理（东京湾）做有辨识度的战场底，同时保留手画覆盖的自由度（港口/跑道/虚构区）。
  陆/海区分驱动玩法（地面单位刷在陆、舰船在海、TacView 网格只画在海面）。
- **反模式规避**：沙盒模式已废弃（见 project_sandbox_deprecated）——地图改动走 `map_feature_renderer` /
  `map_geography`（手画东京湾），**不要动** `terrain_renderer.gd`。

## 2. 架构（四层，已核对文件）

| 层 | 文件 | 职责 |
|---|---|---|
| **MapBoundary** | `map_boundary.gd` | 世界矩形边界、出界/警戒信号、玩家起点 |
| **MapGeography** | `map_geography.gd` | 公共查询 API（`is_on_land` / `is_on_land_strict` / `is_on_solid_land` / `is_ground_spawn_safe` / `find_ground_spawn_near` / HIGHWAYS / URBAN）+ 手画陆地多边形 |
| **MapGeographyData** | `map_geography_data.gd` | JSON 载入器：读 `resources/maps/tokyo_bay.json`（OSM 烘焙几何）填静态数组，`ensure_loaded()` 懒加载一次 |
| **MapFeatureRenderer** | `map_feature_renderer.gd` | 绘制：底图 PNG + OSM 矢量（陆/城区/路）+ 手画 Polygon2D 覆盖 + vignette |
| （编辑器辅助） | `map_manual_background.gd`（@tool） | 编辑器内显示 OSM 预览 + 网格，辅助手画 `scenes/map_manual.tscn` |

## 3. 坐标系与边界常量（已核对）

| 常量 | 值 | 说明 |
|---|---|---|
| `PIXELS_PER_METER`（GameConstants） | 0.5 | **1 px = 2 m** |
| `WORLD_SIZE_M` | 30000 | 地图边长 30 km |
| `WORLD_HALF_PX` | 7500（= 30000×0.5×0.5） | 半边长，世界 = ±7500px = ±15 km |
| `WARN_DISTANCE_M / _PX` | 2000 / 1000 | 接近边界 2km 触发警戒 |
| `CAMERA_MARGIN_M / _PX` | 5000 / 2500 | 相机可越界看 5km |
| `PLAYER_START_OFFSET_PX` | (0, 6400) | 玩家起点（南侧，距南边界 ~1100px≈2.2km，刚出警戒带） |

坐标系：原点 (0,0) = 地图中心（东京湾，约 35.44°N/139.76°E）；X+ 东、Y+ 南；世界 = `Rect2(-7500,-7500,15000,15000)`。

## 4. 查询 API（已核对签名）

| 函数 | 文件 | 用途 |
|---|---|---|
| `MapGeography.is_on_land(pos) -> bool` | map_geography.gd | 陆判（先查 OSM land_mask 多边形，再查手画陆地）；玩法用（刷点/开火/寻路） |
| `MapGeography.is_on_land_strict(pos) -> bool` | map_geography.gd | 仅查 OSM land_mask（更严，地面单位刷点避开港湾内水域） |
| `MapGeography.is_on_solid_land(pos) -> bool` | map_geography.gd | 官方图要求 OSM land_mask 与手画陆块同时命中，排除跨海道路/桥梁外扩；UGC 沿用明确陆地层 |
| `MapGeography.is_ground_spawn_safe(pos, clearance_px=50) -> bool` | map_geography.gd | 正式地面单位硬闸：命中覆盖 60km 全图的 OSM land mask、不落入视觉水面环，并保证中心周围 50px（100m）仍是连续陆地；不再依赖旧 30km 手画轮廓 |
| `MapGeography.find_ground_spawn_near(anchor, max_radius_px, clearance_px=50) -> Vector2` | map_geography.gd | 固定偏移落点不安全时，在附近按确定性同心环寻找安全陆地；无解返回 `Vector2.INF` |
| `MapBoundary.distance_to_edge(pos) -> float` | map_boundary.gd | 到最近边距（>0 内、≤0 外） |
| `MapBoundary.is_safe_inside(pos, margin) -> bool` | map_boundary.gd | 在界内且距边 ≥ margin |
| `MapBoundary.clamp_inside(pos, margin) -> Vector2` | map_boundary.gd | 钳进界内 |
| `MapBoundary.world_half_px()` / `get_player_start()` | map_boundary.gd | 半边长 / 玩家起点 |

信号：`approach_warning(active, distance_m)`（进/出 2km 警戒带）、`boundary_crossed()`（越界，联动出界补给/时间税，见 [survivor-loop §6](survivor-loop.md)）。

## 5. 数据模型与三条流水线

地图陆/海以**多边形**存储（非位图）：手画陆地（`LAND_WEST/EAST/HANEDA` PackedVector2Array，Chaikin 平滑 2 次）
+ OSM 烘焙 `land_mask`（shapely 预合并的大多边形）+ 城区/4 级道路/海岸线。正式东京湾额外读取
`tokyo_bay_vector_preview.json` 的 `water_rings` 作为**只读水面排除蒙版**；它不替换生产 PNG，也不启用纯矢量渲染。

| 流水线 | 工具 | 产物 | 详见 |
|---|---|---|---|
| **A. OSM 烘焙** | `scripts/tools/bake_tokyo_bay.py`（dev 工具，配 FIXED_LAT_C/LON_C/PX_PER_M/WORLD_HALF） | `resources/maps/tokyo_bay.json`（陆/城区/路/land_mask） | [map-pipeline.md](../../reference/map-pipeline.md) |
| **B. 底图下载** | `scripts/tools/download_basemap.py`（CartoDB 瓦片；新图可按设计选用） | `tokyo_bay_bg.png` + `_bg.json` 元数据 | [map-pipeline.md](../../reference/map-pipeline.md) |
| **C. 手画覆盖** | Godot 编辑器画 `scenes/map_manual.tscn` 里的 Polygon2D | 场景文件（渲染时被 MapFeatureRenderer 采集） | [manual-map-editing.md](../../reference/manual-map-editing.md) |

> JSON 而非 GDScript 静态初始化：避开 @tool 大静态数组的懒初始化 bug，运行时 `FileAccess`+`JSON.parse_string` 稳定。
> 正式东京湾的 8704×8704 底图 PNG 是保留的生产视觉资产；“缺失则跳过”只是容错行为，不表示它可从打包删除或由现有纯矢量候选替换。
> 底图缺失或损坏时游戏继续运行并启用旧矢量兜底；正式生存模式必须同时显示本地化红色错误 toast。UGC 纯矢量地图不报错。

## 6. 地图注册与选择 + 扩展接入图 ★

地图在 `survivor_map_select.gd` 的 `MAP_LIST` 注册（id/name(i18n)/tags/desc/locked）；当前只有 `default`（东京湾）
可选，其余 4 槽 locked。选图流程：map_select → 存 `meta("map_id")` → aircraft_select → survivor_mode 读取。

**加新地图（如 shanghai）**：

| 步 | 改哪里 | 做什么 |
|---|---|---|
| 1 | `survivor_map_select.gd:MAP_LIST` | 加 `{id,name,tags,desc,locked:false}` |
| 2 | `bake_tokyo_bay.py` | 改 FIXED_LAT_C/LON_C 为新中心，跑出 `resources/maps/<id>.json` |
| 3 | `download_basemap.py`（可选） | 改 bbox/zoom，跑出 `<id>_bg.png` + `_bg.json` |
| 4 | `scenes/map_<id>.tscn` | 手画 Polygon2D 覆盖（陆/港/跑道） |
| 5 ★ | `map_geography_data.gd` 载入路径 | 改为按 map_id 选 JSON（当前硬编码 tokyo_bay）—— **多图支持的关键改动** |
| 6 ★ | `map_feature_renderer.gd` 路径常量 | 底图/手画场景路径改为按 map_id |
| 7 | `survivor_mode.gd:_ready` | 读 `meta("map_id")` 传给 MapGeography/Renderer |
| 8 | i18n | `MAP_<ID>_NAME` / `_DESC` 三语 |

> ⚠ **当前多图未实现**：MapGeographyData / MapFeatureRenderer 路径硬编码 tokyo_bay，步 5/6 是改造关键。
> 手画无 SVG 导入，必须在 Godot 编辑器画 Polygon2D。

## 7. 验收标准（Acceptance / Litmus）

- [x] 世界 ±7500px（30km），原点 = 地图中心，1px=2m
- [x] is_on_land / is_on_land_strict 区分玩法用陆判 / 严格地面刷点
- [x] is_on_solid_land 阻止海上道路/桥梁外扩承载地面目标或地面单位
- [x] 正式地面单位统一走安全部署判定：港池/河道/桥面排除，中心周围 50px 连续陆地；无安全落点时宁可少刷
- [x] 越界触发警戒信号 + 联动补给时间税
- [x] 底图 PNG 缺失时游戏照常跑
- [x] 正式东京湾主地图与 Tab 默认消费同一 PNG 设计；纯矢量 debug 候选不获得删除/替换授权
- [x] 底图 PNG 缺失/损坏时控制台 `push_error` + 顶部红色 toast 明示旧矢量兜底；UGC 纯矢量路径不误报
- [x] 地图改动走 map_feature_renderer/map_geography，不动 terrain_renderer（沙盒废弃）

## 8. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 边界/起点/出界信号 | `scripts/survivor/map_boundary.gd` |
| 陆判/地理查询 | `scripts/survivor/map_geography.gd` |
| JSON 载入 | `scripts/survivor/map_geography_data.gd` |
| 绘制 | `scripts/survivor/map_feature_renderer.gd` |
| 编辑器辅助 | `scripts/survivor/map_manual_background.gd` · `scenes/map_manual.tscn` |
| 选图注册 | `scripts/survivor/survivor_map_select.gd`（MAP_LIST） |
| 烘焙/底图工具 | `scripts/tools/bake_tokyo_bay.py` · `download_basemap.py` |
| reference 流水线 | map-pipeline.md · manual-map-editing.md |

## 9. 待补 / 不确定

- 多图支持未实现（路径硬编码 tokyo_bay，§6 步 5/6 为改造点）。
- Python 烘焙脚本逐字段细节以 map-pipeline.md 为准（本 spec 只给入口与产物）。

## 10. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 首版 map spec + 扩展接入图；核对边界/坐标/查询 API；流水线细节引用现有 reference 文档 |
| 2026-08-08 | 2 | 用户最终否决东京湾纯矢量替换；正式主地图与 Tab 保留 8704×8704 PNG + shader。资源缺失 fail-open 仍保留，但仅是容错，不再把 PNG 描述为可退役资产。 |
| 2026-08-09 | 3 | 新增实体陆地查询：官方图要求 OSM land mask 与手画陆块同时命中，排除海上道路/桥梁外扩承载地面目标与单位。 |
| 2026-08-10 | 4 | 港区地面部署收口：正式东京湾以覆盖 60km 全图的 OSM land mask 为正集，用视觉水面环排除港池/河道，再要求 50px 连续陆地净空；固定偏移可在附近确定性重定位，无解缩编。旧 30km 手画轮廓不再作为正式部署硬交集；该蒙版只参与玩法查询，不改变 PNG 生产渲染决策。 |
| 2026-08-10 | 5 | 合并 main 的底图失败提示链：四类失败原因统一发信号，正式生存模式显示三语红色错误 toast，同时保留旧矢量层保证战局可继续；UGC 纯矢量模式豁免。 |
