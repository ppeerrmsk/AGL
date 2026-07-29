---
id: map-expansion
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口；编辑器整合由 map-editor 承接
schema_version: 1
spec_version: 6
owner: noelu
depends_on: [map-system, map-editor]
reconstruction_complete: false
---

# 地图扩展 + 战区重排 —— RTS 活动范围升级（落地方案）

> 玩家视角：地图更大、战区之间有真正的"航路"，不再互相贴脸重叠；增援从边缘涌入有
> 完整的入场走廊；镜头（后续阶段）能拉得更远俯瞰整个战场调兵遣将。

## 1. 动机与现状

### 1.1 实证痛点：30×30 km 下战区挤到互相咬合（2026-07-05 量化）

世界 = 30×30 km（±7500 px），5 个战区 A~E 圆面积合计 ≈ 88.7M px²，
占世界面积 **39%**——巡逻圈、BFM 追逐（动辄 1~2 km 位移）必然越区：

| 数据点 | 现值 | 问题 |
|---|---|---|
| C↔E 圆边间隙 | **210 px（420 m）** | 基本贴着；一次转弯就进对方区 |
| D↔E 圆边间隙 | 212 px | 同上 |
| D 距地图边界 | **200 px** | 战区任务直接顶在边界警戒带上 |
| BOSS_SOUTH 与 E | 完全重叠（设计上互斥出现） | 反映的是"没有空位可放"的密度 |
| A↔C 间隙 | 1364 px | 勉强 |

用户实际观察：两个战区的目标互相飞进对方区域 —— 与上表一致，是**几何密度问题**，
不是 AI 拴绳问题；靠加 leash 只会把"越区"换成"贴边打转"，治标不治本。

### 1.2 依赖审计结论（v1 2026-07-02 调查，仍有效）

**世界尺寸是单一权威常量 `MapBoundary.WORLD_SIZE_M`，大部分系统数据驱动，扩图安全**：

| 系统 | 扩图影响 | 结论 |
|---|---|---|
| 相机钳制（set_world_bounds 传 rect） | 全数据驱动 | ✅ 自动适配 |
| Tab 全息图（按 `_world_rect` 归一化） | 无硬编码缩放 | ✅ 自动适配 |
| 雷达小地图（玩家相对，RADAR_RANGE=5000） | 与地图无关 | ✅ 不受影响 |
| 增援刷怪 | [reinforcement-ingress](reinforcement-ingress.md) 全部按 `WORLD_HALF_PX` 相对表达 | ✅ 自动适配 |
| 出界警告/补给 | 警距可配 | ✅ 自动适配 |
| **玩家出生偏移** `PLAYER_START_OFFSET_PX` | 绝对坐标 | 🟡 一行改 |
| **战区坐标**（ZONES center/radius + ground_spawn_polygons + BOSS N/S 锚点） | 绝对坐标硬编码 | ⚠ 需重排（本次主工作量） |
| **地理**（OSM 烘焙 bbox + 手画地块） | 烘焙范围固定 | ⚠ 需扩 bbox 重烘焙；已有手画/烘焙数据坐标不变、仍然有效 |
| 镜头 `ZOOM_MIN` | 拉更远需图标 LOD | 🟡 分期处理（§2.3） |

## 2. 数据定义（What）

### 2.1 尺寸决策表（★ 已拍板：×2 = 60×60 km）

以玩家 1200 km/h 巡航（= 333 m/s = 167 px/s）估算通行时间；战区半径全部维持现值：

| 方案 | 世界 | `WORLD_HALF_PX` | 横穿全图 | C↔E 间隙（中心×同比后） | 战区面积占比 | 增援边缘→中心 |
|---|---|---|---|---|---|---|
| 现状 | 30×30 km | 7500 | 90 s | 210 px | 39% | ~60 s |
| ×1.5 | 45×45 km | 11250 | 135 s | ≈2465 px（4.9 km） | 17.5% | ~90 s |
| **×2（已拍板）** | **60×60 km** | **15000** | 180 s | ≈4720 px（9.4 km） | 9.9% | ~120 s |

**2026-07-05 用户拍板 ×2 = 60×60 km**：优先保证战区间隙（9.4 km 真实航路，敌机雷达
3~4.5 km 远够不到邻区）与增援入场走廊的空旷感。**节奏风险显式登记**：横穿全图 180 s +
增援入场 ~120 s，若 playtest 发现战区阶段（`WARZONE_PHASE_DURATION`）完不成 ≥3 个战区（§5 验收项），调节手段
按序尝试 = 战区分布向中环收拢 → 阶段时长 → 巡航速度，另行开单，不回退尺寸。

### 2.2 常量改动清单

| 项 | 现值 | 新值（×2 方案） |
|---|---|---|
| `MapBoundary.WORLD_SIZE_M` | 30000 | **60000**（唯一主开关，`WORLD_HALF_PX` 等派生量自动跟随） |
| `PLAYER_START_OFFSET_PX` | (0, 6400) | (0, **13900**)（维持"距南边界 1100 px、在 1000 px 警戒带外"的原语义） |
| `CAMERA_MARGIN_M` / 边界视觉 / 警距 | 不变 | 不变 |
| `ZOOM_MIN` | 0.2 | **阶段 1 不动**（§2.3） |
| `FAR_CLEANUP_DISTANCE` | 7000 | 不变（角色已被 ingress 收窄为"非增援类别"的兜底） |

### 2.3 镜头分期（把 LOD 工作从扩图里解耦）

- **阶段 1（本次）**：`ZOOM_MIN` 保持 0.2（1920 宽下可视 19.2 km ≈ 43% 图宽）。飞机线框
  在 0.2 的可读性是已经调过的既得成果，不动它就不欠图标 LOD 的债。
- **阶段 2（另立工单，可选）**：战略缩放档（候选 `ZOOM_MIN` 0.12，或"一屏看全图"动态下限
  = viewport/world）**必须**配"战略图标 LOD"（远档切固定屏幕尺寸的点/三角标记），并按
  performance-guidelines 跑 Sentinel + Lv5 压测（更多单位入镜）。
  注意与 [reinforcement-ingress](reinforcement-ingress.md) 的交互：能看全图的缩放档下，
  边缘入场"跨线飞入"会直接可见——这按雷达开机的 RTS 语义**视为特性**（边缘出现的是
  战略图标点，不是"面前 materialize 的线框机"），非 bug。

### 2.4 战区重排约束（新布点的验收几何，权威）

新坐标以"×2 同比缩放为初值、对着新烘焙地理手工修正"产出（编辑器里对照底图挪点），
**必须满足**：

| 约束 | 值 |
|---|---|
| 任意两战区圆边间隙 | ≥ **2000 px（4 km）** |
| 战区圆边距地图边界 | ≥ **1500 px**（留出边界警戒带 + 增援入场走廊） |
| ground 类战区 | 新地理上 `zone_has_land` 必须为真（陆地占比 ≥12% 的既有判定） |
| BOSS_NORTH / BOSS_SOUTH 锚点 | 同比缩放后重新对地理选点（水面吸附逻辑已有，照常兜底） |
| A/D 的 `ground_spawn_polygons` | **作废重画**（绝对坐标手画多边形，中心挪了必须在编辑器里重描） |

战区半径本次维持现值（A~D 2500 / E 1800）——扩的是"之间的空隙"，不是战区本身。
（后记：2026-07-06 [60km-density-pass](60km-density-pass.md) 按 playtest 反馈把半径上调
A/C/D 3500、B 3000（y 内收 -10500）、E 2500，§2.4 约束复验全绿——空间是本 spec 留出来的。）

**适用范围裁决（2026-07-26）**：本表 2000/1500 只约束**可自由布点的随机战区**
（A–G + BOSS 锚点）。机场解放战区（AF_*，圆心＝现实机场烘焙质心，不可挪）**豁免**，
改按弱化下限（凡机场参与的组合缘距 ≥1000 / 机场圆离边 ≥0）——完整裁决与实测值见
[airfield-liberation-zones §2.5](airfield-liberation-zones.md)；`test_map_expansion.gd`
按 `airfield` 字段分派双阈值强校验。

### 2.5 地理重烘焙

- `tools/bake_tokyo_bay.py` 的 bbox 按 ×2 扩大重跑（真实 OSM 东京湾 60 km 视野，
  烘焙 JSON 自动进 `map_geography_data`，管线已就绪，见 map-pipeline.md）。
- 已有手画地块（map_manual.tscn）与旧烘焙数据**坐标不变、原地有效**——扩图是向外
  加空间，不是缩放旧内容；新增的外圈大部分是海面，白给不用画。
- 烘焙后抽查 `is_on_land`：新外圈海岸线 / 各 ground 战区新址落点。

## 3. 与 reinforcement-ingress 的耦合与实施顺序

1. **先扩图（本 spec 阶段 1）再落 ingress**：ingress 的锚点盘 / 入场走廊全部按
   `WORLD_HALF_PX` 相对表达，先定几何再调参，避免在 30 km 图上调一遍、45 km 再调一遍。
2. ingress 的 EGRESS / 开局驻防距离参数在新尺寸下过一遍 sanity（spec 内数值已按
   相对量写，预期无需改）。
3. 事件/奖励任务"机头沿途"的刷出距离、Adds 航线 margin、supply 位置：按新尺度
   跑一遍确认（多为相对量，预期小改或不改）。

### 3.1 落地路径复审（2026-07-05）：经 map-editor 授权，本 spec 不再手改代码

与 [map-editor](map-editor.md)（v4 approved 2026-07-04，feature/map-editor 分支）撞车三处：
①底图 PNG 已判退役（编辑器产出一律纯矢量渲染）→ 底图重下载作废；②zones / spawn 将进
地图 JSON（编辑器 §2.2 图层表）→ 手改 zone_data.gd 注定被数据驱动取代；③官方 60km 大图
明确"用编辑器铺"（dogfood 工具先行）。据此复审：

- **决议保留**：60×60 km 尺寸、§2.4 战区几何约束、§2.1 节奏风险登记——继续有效，
  变的只是"由谁落地"（手改 gd → 编辑器授权 + 地图 JSON）。
- **本轮已回滚**（2026-07-05）：map_boundary / zone_data / 两个烘焙脚本 / map_manual_background /
  survivor_debug_spawn / 地图三件套共 9 个文件恢复原状。`WORLD_SIZE_M` 翻 60000 的时机 =
  编辑器铺完官方 60km 图后随图激活。
- **烘焙产物已归档** `C:\Users\noelu\Downloads\agl_60km_bake\`（60km 矢量 JSON + GeoJSON 原料 +
  Overpass 原始响应 + 最小转换器 + 查询语句，附 README 重跑方法）——将来编辑器
  OfficialMapConverter / 烘焙管线铺官方大图的现成输入。60km 底图 PNG 按退役决议未存档。
- **候选布局表**（编辑器授权时的输入；几何约束已数值验证，陆地占比待对新地理核）：

| 战区 | 候选 center | radius | 备注 |
|---|---|---|---|
| A | (-6400, -5000) | 2500 | 川崎/横滨北内陆城区，ground |
| B | ~~(7600, -7600)~~ → **(6000, -11000)** | 2500 | 市川/船桥湾岸，ground（×2 初值落湾里占比 0.00，land_mask 网格扫描修正为 0.65） |
| C | (-8200, 7600) | 2500 | 横须贺/三浦东岸海域，air |
| D | (9600, 9000) | 2500 | 房总西岸（君津/富津），ground，⚠ 陆地占比风险最高，或需向湾岸城带内收 |
| E | (800, 7000) | 1800 | 浦贺水道北口，naval/elite |
| BOSS_N | (2500, -3000) | 2200 | 湾北水域桥南（湾形是硬约束，不做 ×2 外推，靠水面吸附兜底） |
| BOSS_S | (0, 7000) | 2200 | 同 E 位（沿用"南 BOSS 占 E 位"的互斥设计） |

该表最小缘距 C↔E ≈ 4720 px（9.4 km）、离边最小 B = 1500 px（恰达标），全部满足 §2.4；
A/D 旧手画 ground_spawn_polygons 已作废删除（走 center+0.85R 散布 fallback），后续可在编辑器里对新地理重描。

**尾注（2026-07-05 同日二次复审）**：用户决定**保留本轮手改落地**（"做都做了，先别回滚"）——
上文"已回滚"作废，9 文件改动 + 60km 地图三件套已在工作区（回滚又重放）。与 map-editor 的
调和方式改为：现状 60km 官方图将来经 OfficialMapConverter 转入编辑器管线；底图 PNG 维持
**过渡资产**身份（编辑器矢量渲染接管官方图后按退役决议移除）；zones/spawn 的 JSON 化仍由
编辑器时代完成，届时以本表落位值为初始数据。落地验证：`tests/test_map_expansion.gd` 无头
回归全绿（几何约束 15/15 + ground 陆地占比 A 1.00 / B 0.65 / D 1.00 + BOSS 南北锚点天然在
水面 + is_on_land 新外圈抽查），其中 B 初值落湾里由回归抓出、经 land_mask 网格扫描修正。

## 4. 结构与组成（Structure）

- 改动集中在：`MapBoundary`（一行主开关 + 出生点）、`ZoneData`（ZONES 表 + BOSS 锚点 +
  重画多边形）、烘焙产物 JSON。**不新增任何节点/系统**。
- 战区坐标 JSON 化（为 [ugc-editor](ugc-editor.md) 铺路）**降级为可选顺手项**：本次以
  游戏体验痛点驱动，手工重排（约 1~2 h）可接受；若重排时发现来回改 gd 很烦，再顺势抽
  JSON，不作为本 spec 的验收项。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 改 `WORLD_SIZE_M` 后：相机钳制 / Tab 全息图 / 出界补给 / 增援入场全部自动正确（无逐处手改）
- [ ] 新战区布点满足 §2.4 全部几何约束（间隙 ≥4 km、离边 ≥1500 px）
- [ ] 两个相邻战区同时活跃开打：各自目标全程不进入对方圆（越区追逐随间距消失）
- [ ] ground 战区在新地理上正常刷 SAM/AA（`zone_has_land` 通过 + 落点全在陆地）
- [ ] `is_on_land` 新外圈抽查正确（海岸线 / 战区新址）
- [ ] 玩家出生位置语义不变（南侧、距边 1100 px、警戒带外、Tab 图定位正确）
- [ ] 战区阶段节奏可玩：单局能完成 ≥3 个战区（playtest 主观确认不发闷）
- [ ] 性能：更大世界不引入新的每帧成本（边界绘制 tick 数随周长增加，确认无掉帧）；Sentinel + Lv5 压测 FPS 掉幅 < 15
- [ ] i18n：无新增玩家可见文本

## 6. 实现计划（Task Pipeline —— 工作令）

> 2026-07-05 二次复审（§3.1 尾注）：手改落地**保留**。编辑器整合退为后续（converter 吃现状）。

### 阶段 1 — 主开关与地理
- [x] `WORLD_SIZE_M` 30000→60000 + `PLAYER_START_OFFSET_PX` (0,13900)
- [x] `bake_tokyo_bay.py` bbox ×2 重烘焙（经 Overpass API 全量拉取，产物另归档 Downloads\agl_60km_bake）+ `is_on_land` 抽查（无头回归）
- [x] 底图 ×2 重下（过渡资产，34MB；编辑器矢量渲染接管后移除）
- [ ] 快速烟测（进游戏）：边界绘制 / 相机钳制 / Tab 图 / 出界补给

### 阶段 2 — 战区重排
- [x] ZONES 表新坐标（×2 初值 → B 经 land_mask 网格扫描修正 (6000,-11000)，过 §2.4 约束 15/15）
- [x] A/D 旧 `ground_spawn_polygons` 作废删除（散布 fallback）；编辑器重描留待后续（可选）
- [x] BOSS_NORTH (2500,-3000) / BOSS_SOUTH (0,7000) 重选点（无头验证天然在水面）
- [ ] 双活跃战区越区回归观察（playtest）

### 阶段 3 — 连带调参与收尾
- [ ] 事件/任务/Adds/supply 距离 sanity pass（playtest 时顺带）
- [x] （衔接）reinforcement-ingress 在新几何上落地（同批完成，见该 spec §8 v2）
- [x] 同步 reference 索引 + 无头回归脚本 `tests/test_map_expansion.gd` 入库；§8 变更记录
- [ ] playtest：单局 ≥3 战区节奏确认（§2.1 风险登记的验收）→ status: done

### 阶段 4（可选另立）— 战略缩放档
- [ ] 图标 LOD + `ZOOM_MIN` 0.12 + 性能压测（§2.3）

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 位置 |
|---|---|
| 世界尺寸常量 / 出生点 | `scripts/survivor/map_boundary.gd` |
| 镜头上限 | `scripts/camera_controller.gd` |
| Tab 图世界→屏幕 | `scripts/survivor/tactical_map.gd` |
| 战区坐标 / BOSS 锚点 / 陆地判定 | `scripts/survivor/zone_data.gd` |
| 手画地理 / 烘焙 | `scripts/survivor/map_geography.gd` / `map_geography_data.gd` / `tools/bake_tokyo_bay.py` |
| 手画多边形流程 | `docs/reference/manual-map-editing.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-02 | 1 | 可行性调查 + 计划初稿：单常量主开关；硬编码点=战区坐标+手画地理+出生偏移；建议编辑器先行、战区 JSON 化 |
| 2026-07-05 | 2 | 升级为落地方案：量化战区拥挤实证（C↔E 210 px / D 离边 200 px / 面积占比 39%）；尺寸决策表（推荐 ×1.5=45 km）；战区重排几何约束；镜头/LOD 解耦分期；与 reinforcement-ingress 定序；编辑器先行降级为可选 |
| 2026-07-05 | 3 | **定稿 approved**：用户拍板 ×2 = 60×60 km（节奏风险显式登记 + 调节序列）；出生点/清单数值按 ×2 落定 |
| 2026-07-05 | 4 | **落地路径复审**：发现与 map-editor v4（07-04 approved）撞车（PNG 退役 / zones 进地图 JSON / 官方大图 dogfood），阶段 1 手改（主开关+烘焙+战区 ×2 初值）整体回滚；60km 烘焙产物归档 Downloads\agl_60km_bake；候选布局表存档 §3.1；后续经编辑器授权落地 |
| 2026-07-05 | 5 | **二次复审：保留手改落地**（用户决定）——回滚重放；B 战区初值落湾里由无头回归抓出、网格扫描修正 (6000,-11000)；无头回归 `tests/test_map_expansion.gd` 全绿；PNG 定性过渡资产；status → in-progress，差 playtest 节奏验收 |
| 2026-07-26 | 6 | §2.4 适用范围裁决：2000/1500 只管随机战区（A–G+BOSS）；机场解放战区（AF_*，现实坐标不可挪）豁免为 缘距 ≥1000 / 离边 ≥0，裁决全文见 airfield-liberation-zones §2.5 |
