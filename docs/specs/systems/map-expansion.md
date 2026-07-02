---
id: map-expansion
kind: system
status: draft        # ⏳ 可行性 + 计划（2026-07-02 调查完毕）；未实装
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [map-system, ugc-editor]
reconstruction_complete: false
---

# 地图扩展 + 镜头再拉远 —— RTS 活动范围升级（可行性 + 计划）

> 玩家视角：地图更大、镜头能拉得更远，真正俯瞰整个战场调兵遣将；Tab 全息图同步显示更大的世界。

## 1. 现状（2026-07-02 调查，锚点见 §6）

- **世界 = 30×30 km（±7500 px），单一权威常量** `MapBoundary.WORLD_SIZE_M`——不是散落的魔法数。
- **镜头缩放上限已放宽**：`ZOOM_MIN 0.4→0.2`（≈19 km 视野，已提交 main）。
- 依赖审计结论：**大部分系统是数据驱动的，扩图安全**；少数硬编码点见 §2。

| 系统 | 扩图 2× 影响 | 结论 |
|---|---|---|
| 相机钳制（set_world_bounds 传 rect） | 全数据驱动 | ✅ 安全 |
| **Tab 全息图**（tactical_map `_world_to_map` 按 `_world_rect` 归一化） | 无硬编码缩放，**自动适配** | ✅ 安全（用户关心点：**不需要单独扩** — setup 传新 rect 即可） |
| 雷达小地图（HUD RadarDisplay） | 玩家相对（RADAR_RANGE=5000），与地图无关 | ✅ 安全 |
| 刷怪距离（spawner 读 MapBoundary API） | 跟随常量 | ✅ 安全 |
| 出界警告/时间税 | 警距可配；仅玩家出生偏移硬编码 | 🟡 小改 |
| **战区坐标**（zone_data 5 战区 center/radius + 地面刷怪多边形） | **绝对坐标硬编码** | ⚠ 需重排 |
| **手画地理**（map_geography LAND_WEST/EAST ~170 点 + 东京湾烘焙） | **绝对坐标** | ⚠ 需重烘焙/重画 |

## 2. 改动清单（扩到 2×=60×60 km 为例，尺寸待定）

1. **一行主开关**：`MapBoundary.WORLD_SIZE_M`（30000→N）。相机/Tab 图/spawner/出界自动跟随。
2. **镜头**：`ZOOM_MIN` 随地图再放（候选 0.12~0.15，或"一屏看全图"动态下限 = viewport/world）。⚠ 必须配 **图标 LOD**：拉远后飞机线框小到不可读 → 远缩放档切"战略图标"（固定屏幕尺寸点/三角），过性能守则（更多单位入镜 → 按 performance-guidelines 跑 Sentinel+Lv5 压测）。
3. **玩家出生偏移** `PLAYER_START_OFFSET_PX` 按新边界调整。
4. **战区重排**：5 个战区 center/radius + 地面刷怪多边形重新布点（1~2h 手工）。**建议**：这批坐标顺势**数据化成 JSON**（战区布局文件），为 [ugc-editor](ugc-editor.md) 的关卡编辑铺路——之后扩图/改布局不再动代码。
5. **地理重烘焙**：`bake_tokyo_bay.py` 放大 bbox 重跑 OSM（JSON 自动进 `map_geography_data`，脚本已就绪）；手画 fallback（LAND_WEST/EAST）要么重描要么删掉全走烘焙 JSON。海面向外白给，不用画。
6. **调参连带**：事件/任务刷在机头沿途的距离、supply 位置、BOSS 圈——按新尺度过一遍。

## 3. 结论与顺序建议

**可行，无架构阻碍**；瓶颈是"内容重排"（战区 + 地理，约半天）。
**强烈建议顺序**：先做 [ugc-editor](ugc-editor.md) P1 的**地图编辑器**（战区/地块的交互编辑 + JSON 化），再用编辑器本身来铺大地图——工具先行，扩图变成"用自家编辑器做第一张官方大图"，同一份工作两份产出（用户："我也可以利用这个编辑器自己制作内容"）。

## 4. 验收（骨架）

- [ ] 改 WORLD_SIZE_M 后：相机钳制/Tab 全息图/出界/刷怪自动正确（无需逐个改）。
- [ ] 远缩放档图标可读（战略图标 LOD）；Sentinel+Lv5 压测 FPS 掉幅 <15。
- [ ] 战区布局 JSON 化：改布局不再改 gd 代码。
- [ ] 新地理烘焙 `is_on_land` 正确（海岸线/机场着陆判定抽查）。

## 5. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-02 | 1 | 可行性调查 + 计划初稿：单常量主开关；Tab 图/相机/雷达/spawner 均数据驱动安全；硬编码点=战区坐标+手画地理+出生偏移；建议编辑器先行、战区 JSON 化。 |

## 6. 索引锚点

| 关注点 | 位置 |
|---|---|
| 世界尺寸常量 | `scripts/survivor/map_boundary.gd`（WORLD_SIZE_M / WORLD_HALF_PX） |
| 镜头上限 | `scripts/camera_controller.gd`（ZOOM_MIN / START_ZOOM） |
| Tab 图世界→屏幕 | `scripts/survivor/tactical_map.gd`（setup / _world_to_map） |
| 战区坐标 | `scripts/survivor/zone_data.gd`（ZONES 表 + ground_spawn_polygons） |
| 手画地理 / 烘焙 | `scripts/survivor/map_geography.gd` / `map_geography_data.gd` / `tools/bake_tokyo_bay.py`（见 map-pipeline.md） |
