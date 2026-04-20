# 地图流水线（Map Pipeline）

AGL 生存模式使用**真实地图底图 + 程序化矢量数据 + 手画覆盖层**的三层混合渲染。本文档讲清楚从零建新地图的完整流程、渲染架构、以及判定逻辑。

---

## 1. 架构总览

```
┌──────────────────────────────────────────────────┐
│  scenes/survivor_mode.tscn                       │
│  ├── MapBoundary          游戏世界边界 (±7500px) │
│  ├── MapFeatureRenderer   主地图渲染器            │
│  │    ├── Sprite2D + Shader  底图 PNG            │
│  │    ├── _draw()            矢量层 + vignette   │
│  │    └── manual_overlay    加载 map_manual.tscn │
│  ├── WeatherSystem        云层/天气               │
│  └── TacticalMap          战术缩略图（CRT 风）    │
└──────────────────────────────────────────────────┘
             ↑                            ↑
             │                            │
    MapGeography (API 层)         资源文件
    ├── get_land_mask_polygons() ←┐
    ├── get_road_bands()         │
    ├── is_on_land(pos)          │
    ├── URBAN_DISTRICTS          │
    └── HIGHWAYS                 │
             ↑                    │
             │                    │
    MapGeographyData (加载器)     │
    └── ensure_loaded() ─────────→ resources/maps/tokyo_bay.json
                                   resources/maps/tokyo_bay_bg.png
                                   resources/maps/tokyo_bay_bg.json
```

---

## 2. 从零建一张新地图（完整流程）

假设你要做一张"上海外滩"或"纽约湾"之类的新地图。整个流程约 10 分钟。

### 步骤 1：在 OpenStreetMap 选 bbox，导出 GeoJSON 矢量数据

1. 打开 https://overpass-turbo.eu
2. 在地图上把视口拖到目标区域
3. 左侧代码框粘贴下面的查询，**把 4 个经纬度数字换成你的 bbox**（南, 西, 北, 东）：

```overpass
[out:json][timeout:180];
(
  way["natural"="coastline"](35.25,139.55,35.70,140.15);
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary)$"](35.25,139.55,35.70,140.15);
  way["landuse"~"^(residential|industrial|commercial|retail)$"](35.25,139.55,35.70,140.15);
  way["aeroway"~"^(runway|taxiway|aerodrome)$"](35.25,139.55,35.70,140.15);
);
out body;
>;
out skel qt;
```

4. 点左上 **▶ 运行**，等地图上出现彩色叠加层（海岸线/道路）
5. 顶部 **Export → GeoJSON → download and save**，保存到 `C:/Users/noelu/Downloads/export.geojson`

> **尺寸建议**：bbox 总跨度 40-60 km。再大 Overpass 会超时；太小覆盖不住玩家活动范围。

### 步骤 2：调整烘焙脚本的中心点 + bbox

打开 `scripts/tools/bake_tokyo_bay.py`，改这几行（默认是东京湾 35.44°N, 139.76°E）：

```python
FIXED_LAT_C = 35.44   # 改成你地图的中心纬度
FIXED_LON_C = 139.76  # 中心经度
# 其他参数通常不需要改：
FIXED_PX_PER_M = 0.5  # 1 px = 2 m（对应游戏物理尺度）
WORLD_HALF_PX = 7500.0  # 游戏世界 ±7500 px
```

### 步骤 3：跑矢量烘焙

```bash
cd C:/Users/noelu/Documents/AGL
python scripts/tools/bake_tokyo_bay.py
```

输出：
- `resources/maps/tokyo_bay.json` — 矢量数据（~100KB）
- 控制台打印 `[land_mask] unioned N shapes -> M polygons` 等统计

> **依赖**：脚本需要 `shapely` 和 `pillow`。没装的话 `pip install shapely pillow`。

> **为什么不直接输出 GDScript**：早期试过输出 8000 行 `.gd` 文件，Godot 的 GDScript 解析器在编辑器 @tool 上下文里对 `static var` 懒初始化处理不稳定，class member 查询返回空。JSON 走 `FileAccess.open + JSON.parse_string`，运行时和编辑器行为一致，100% 可靠。

### 步骤 4：下载底图 PNG（无文字）

同样打开 `scripts/tools/download_basemap.py`，改这几行：

```python
TARGET_BBOX = {
    "lat_min": 35.2616,    # 改成你的 bbox
    "lat_max": 35.5540,
    "lon_min": 139.5840,
    "lon_max": 139.9301,
}
ZOOM = 13  # 瓦片缩放级别：13 出 ~4600×4600 px，14 出 ~9200×9200 px
```

**瓦片源已配置为 CartoDB Voyager no-labels**（自然色彩、无文字），URL 模板：
```
https://a.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}@2x.png
```

跑脚本：

```bash
python scripts/tools/download_basemap.py
```

输出：
- `resources/maps/tokyo_bay_bg.png` — 拼好的大图（voyager 风格 ~7-8 MB）
- `resources/maps/tokyo_bay_bg.json` — 元数据（bbox → 游戏坐标系转换参数）

> **尺寸权衡**：ZOOM=13 够用，玩家缩放后不模糊；ZOOM=14 更清晰但 4 倍大小。ZOOM=15 以上不建议（文件暴涨，对 CartoDB 不友好）。

> **换风格**：脚本注释里列了 3 个备选 URL（light_nolabels / dark_nolabels / voyager_nolabels）。换一行重跑即可。

### 步骤 5：（可选）调整手画陆地兜底

`map_geography.gd` 里的 `LAND_WEST / LAND_EAST / HANEDA_AIRPORT` 是**手画的陆地大致轮廓**，主要给 `is_on_land()` 做兜底判定（OSM 没 landuse 标签的山林区）。

如果新地图的陆地形状和东京湾完全不同：
- 要么重新手画这 3 个多边形
- 要么直接删掉，只靠 OSM `LAND_MASK_POLYGONS` 判定

不改也能跑，只是 `is_on_land` 在"OSM 空白 + 手画 LAND 不覆盖"的极端地方会误判为海。

### 步骤 6：重启 Godot

`Ctrl+Shift+T`（Project → Reload Current Project）→ F5 → 新地图生效。

---

## 3. 渲染风格（当前配方，满意就别动）

### 主地图（`MapFeatureRenderer`）

**层级**（从下到上）：
1. `Sprite2D` 底图 + ShaderMaterial（`basemap_tacview.gdshader`）
2. `_draw()` 里依次画：
   - `_draw_sea()`（仅无底图时）
   - `_draw_urban_districts()` + `_draw_highways()`（仅 `basemap_covers_vectors=false` 时）
   - `_draw_manual_overlays()` — 加载 `scenes/map_manual.tscn` 的 Polygon2D
   - `_draw_aqualine()` + `_draw_tacview_crosses()`
   - `_draw_edge_vignette()`

**Shader 参数**（`basemap_tacview.gdshader`）：
- `tint` — 色调 multiply
- `saturation` — 饱和度（0 = 灰度）
- `brightness` / `contrast` — 亮度对比
- `edge_strength` — Sobel 边缘检测强度
- `noise_strength` — CRT 颗粒噪点

**当前满意的默认**（`map_feature_renderer.gd`）：
```gdscript
basemap_tint: Color(0.78, 0.82, 0.80, 1.0)  # 中性冷灰，不染色
basemap_saturation: 0.40
basemap_brightness: 0.70
basemap_contrast: 1.25
basemap_edge_strength: 1.2
basemap_noise: 0.03
basemap_covers_vectors: true  # 矢量层关掉，纯底图
```

**Inspector 里也能实时调**：选中 `MapFeatureRenderer` 节点 → Basemap 分组 → 拖滑条即时生效（通过 `_process` 每帧同步 shader uniform）。

### 战术缩略图（`TacticalMap`）

**Control 节点 `clip_contents=true`** 自动裁剪到面板矩形内。

**绘制顺序**（`_on_map_draw`）：
1. 海色底 (`draw_rect SEA_COLOR`)
2. 底图 PNG 缩放贴图 (`_draw_minimap_basemap`)
3. 战区圆圈 / BOSS / ADBS 标记 / 玩家光点 / 指北
4. **最后**：`_draw_minimap_scanlines_and_vignette` —— 每 3 px 一条暗扫描线 + 四边暗角矩形

**不用 shader 做缩略图**（早期试过 `hint_screen_texture` 在 Control 里不 work，会采样整屏幕）。改为纯 `draw_line` 后绘制扫描线，`draw_rect` 做暗角 —— 效果完全一致，无兼容问题。

### 手画覆盖层（`scenes/map_manual.tscn`）

- 根节点 Root (Node2D)
- 子节点 Background (`MapManualBackground`, `@tool`) —— 编辑器里显示 OSM 预览作为描边参考
- 其他 Polygon2D 子节点 —— 你手画的地块，运行时叠加到主地图

详细手画流程见 **[docs/reference/manual-map-editing.md](manual-map-editing.md)**。

---

## 4. 判定逻辑 `is_on_land(pos)`

**✅ 仍然有效**。位置：`MapGeography.is_on_land(pos: Vector2) -> bool`。

**实现**（`map_geography.gd:407`）：
```gdscript
static func is_on_land(pos: Vector2) -> bool:
    ensure_ready()
    # 1. OSM 陆地 mask 优先 —— 对玩家活动区精确（城区+道路+机场外扩并集）
    for poly in MapGeographyData.LAND_MASK_POLYGONS:
        if Geometry2D.is_point_in_polygon(pos, poly):
            return true
    # 2. 手画 LAND 兜底 —— 覆盖 OSM 没标 landuse 的山林区
    for poly in get_land_polygons():
        if Geometry2D.is_point_in_polygon(pos, poly):
            return true
    return false
```

**谁在用**：
- `map_feature_renderer.gd` — 海面上画 TacView "+" 十字（陆地上跳过）
- `zone_mission.gd` — 战区任务生成点筛选（"只在陆上刷"）

**性能**：
- `LAND_MASK_POLYGONS` 共 3 个大多边形（~1000 顶点总）— shapely 预烘焙合并
- 手画 LAND 共 3 个 Chaikin 平滑的多边形（~170 顶点）
- 最坏情况 6 次 `is_point_in_polygon` = 千 ns 级，高频调用也不是瓶颈

**新地图如何确保 `is_on_land` 工作**：
- 跑完 `bake_tokyo_bay.py`，`MapGeographyData.LAND_MASK_POLYGONS` 会自动填充新 bbox 的 OSM 陆地
- 如果新地图里有 OSM 数据稀疏的区域（大片山林没 landuse 标签），手画 LAND_WEST/EAST 作为兜底；否则 OSM mask 单靠就够

---

## 5. 性能与数据规格

| 项 | 数量 / 大小 | 说明 |
|---|---|---|
| LAND_MASK_POLYGONS | 3 个大多边形，~1000 顶点 | shapely union 减少 overdraw |
| URBAN_POLYGONS | ~160 个 | OSM landuse |
| ROADS_MOTORWAY/TRUNK/PRIMARY/SECONDARY | 1012 条总计 | 短于 200px 的丢 |
| COASTLINE_LINES | 21 段 | OSM 海岸线 |
| 底图 PNG | 4608×4608 px / ~7.5 MB | ZOOM=13 |
| JSON 数据 | ~100 KB | FileAccess + JSON.parse |
| 启动加载 | ~30 ms | 一次性 `ensure_loaded` |

## 6. 故障排查速查

| 症状 | 原因 | 修法 |
|---|---|---|
| 主地图空白 | `tokyo_bay_bg.png` 缺失 / 元数据 JSON 损坏 | 重跑 `download_basemap.py` |
| 主地图全是海色 | 底图 PNG 被 `_draw_sea` 遮住（z 顺序 bug） | `map_feature_renderer._draw` 里确认底图存在时跳过 `_draw_sea` |
| `is_on_land` 永远返回 false | `MapGeographyData.ensure_loaded()` 没被调 | 已在 `is_on_land` 开头自动调；若自定义入口，手动调一次 |
| 战术地图空白/全是扫描线 | `minimap_retro.gdshader` 的 `hint_screen_texture` 在 Control 里 bug | 已移除，改用 `clip_contents=true` + 后绘制 `draw_line` |
| 编辑器 MapManualBackground 显示 `land 0 / urban 0 / roads 0` | class_name 懒初始化 bug | 已改用 JSON 加载，强制 `MapGeographyData.ensure_loaded()` |
| 主地图发绿 / 海面变绿 | `basemap_tint` 绿色分量过重 | 改 Inspector 的 tint 到中性 `(0.78, 0.82, 0.80, 1)` |
| OSM 数据飘在海上 / 陆地形状对不上 | 手画 LAND 和 OSM 坐标系对不齐 | 烘焙脚本已固定用 `(FIXED_LAT_C, FIXED_LON_C)` 对齐，重跑即可 |

---

## 7. 文件清单

### 工具脚本（不进打包，开发时用）
- `scripts/tools/bake_tokyo_bay.py` — OSM GeoJSON → JSON 矢量数据 + 陆地 mask union
- `scripts/tools/download_basemap.py` — CartoDB 瓦片拼接 → 底图 PNG + 元数据

### 运行时代码
- `scripts/survivor/map_geography.gd` — 公开 API（is_on_land / URBAN_DISTRICTS / HIGHWAYS / get_*）
- `scripts/survivor/map_geography_data.gd` — JSON 加载器（从 `tokyo_bay.json` 填充静态数组）
- `scripts/survivor/map_feature_renderer.gd` — 主地图渲染（Sprite2D 底图 + 矢量 + vignette）
- `scripts/survivor/map_manual_background.gd` — @tool 编辑器预览（显示 OSM 给你描边用）
- `scripts/survivor/tactical_map.gd` — 战术缩略图（含 CRT 扫描线 / 暗角后绘制）

### 资源
- `resources/maps/tokyo_bay.json` — 矢量数据
- `resources/maps/tokyo_bay_bg.png` — 底图
- `resources/maps/tokyo_bay_bg.json` — 底图元数据
- `resources/shaders/basemap_tacview.gdshader` — 主地图 shader
- `scenes/map_manual.tscn` — 手画覆盖层场景

### 相关文档
- **[manual-map-editing.md](manual-map-editing.md)** — Polygon2D 手画地块的完整操作指南
