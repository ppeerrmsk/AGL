---
id: pure-vector-map-preview
kind: system
status: superseded
schema_version: 1
spec_version: 46
owner: noelu
depends_on: [map-system, map-editor]
reconstruction_complete: true
---

# V45 全东京湾纯矢量研究归档与游戏内 A/B

> 本 spec 归档 V1–V44 的研究过程与 debug A/B 证据。用户于 2026-08-08 最终裁定候选达不到正式栅格视觉预期；2026-08-22 生产底图改为同源 lossless WebP 瓦片，但纯矢量候选仍不作为生产迁移目标。

## 1. 设计意图（Why）

- **体验目标**：把离线样张放进真实相机、HUD、天气、建筑与战斗负载中观察，提前暴露“截图好看、游戏里不成立”的问题。
- **Litmus 自检**：变化当帧可见；不改变玩法判定；遵守 60 FPS 硬底线；地图静态内容不持续重绘。
- **反模式规避**：禁止把 V11 截图重新作为地图贴图；预览必须消费普通矢量数据并提交静态绘制批次。
- **最终生产裁决（用户定 2026-08-22）**：正式东京湾与 Tab 使用同源 lossless WebP 瓦片；这次只晋升栅格瓦片方案。V44 纯矢量 renderer、数据、QA 与 `Shift+F10` 仍是冻结的 debug 研究材料，不获得发布授权。
- **恢复条件**：未来若重启纯矢量替换，必须新建并获批后继 spec；不得以本 spec 已完成的结构/性能门绕过新的整图主观视觉验收。

## 2. 数据定义（What）

### 2.1 开关契约

| 字段 | 值 | 说明 |
|---|---|---|
| 输入 | `Shift+F10` | 仅 debug build 响应；普通 `F10` 的 BFM 测试保持不变 |
| 默认状态 | `false` | 每局从 PNG 开始，不持久化到存档 |
| 生效范围 | 正式东京湾主地图 + Tab 地图 | 两处原子同步，禁止一处 PNG、一处矢量 |
| UGC / Boss Debug / bench | 不可切换 | UGC 已是独立 vector-only；空白/无头模式不加载本预览资源 |
| 回滚 | 再按一次 `Shift+F10` | 恢复同一 PNG Sprite 与 Tab PNG，不重新导入资源 |
| 提示 | 屏幕临时提示 + EventLogger | 三语走 `tr()`；记录 on/off 与失败原因 |

### 2.2 V12 全图数据

| 图层 | 数据 | 规则 |
|---|---|---|
| 海陆拓扑 | 一次性矢量化的 water / land-inlay 闭合环 | 海面、浅海带与海岸描边从同一环派生，禁止独立悬空 coastline |
| 城区/主路 | 当前东京湾 JSON | 不修改 gameplay 陆判与道路源 |
| 次级路 | tertiary 10,824 条 | Operational / Detail 使用 |
| 细路 | residential 2,045 条、service 595 条 | residential 从 Operational 起保留；service 仅 Detail，且已过滤短枝 |
| 机场 | runway 12、taxiway 791、apron 19 | 分层渲染，不再只有机场外接面 |
| 港区 | pier/breakwater/groyne 46 条、industrial 29 面 | 与海陆拓扑同坐标系 |
| 建筑 | 199 个 AGDT 的 small/medium/large footprint | 候选 detail：小建筑体块+单层核心线，中大型暖灰屋顶，大建筑追加静态冷暗侧墙；旧横滨 BuildingRenderer 仅属于 PNG 栈；Tab 战略档不画建筑 |

V12 另以 16×16 个 2 km 矢量格覆盖 60 km 世界：203 个入选、199 个非空 AGDT gzip 包，合计约 154.9 MB。Detail 使用 12 格 LRU，一格载入期 3072² 超采样后保留 1536² 内容与 4 px 外挤边；常驻预算 ≤110 MiB、顺序切区峰值 ≤150 MiB。Operational 使用 513×513 的 OSM 派生城市/植被/工业标量场与全图大建筑 packet；它们是静态矢量三角数组，不是承载地图内容的图片。

V22 明确区分运行时资产与构建源：203 个原始 detail JSON 合计约 995 MB，只能保存在 `tmp/full_map_detail/detail_tiles_source/`，由根目录 `tmp/.gdignore` 排除 Godot 扫描和导出；`resources/maps/` 只保留约 154.9 MB AGDT、约 1.46 MB AGLW 和小型 manifest。生产 manifest 的 `json_source_path` 必须指向 `tmp/`，运行时 `data_path` 必须指向 packed AGDT；任何 raw detail JSON 回流 `resources/` 都视为包体回归。

### 2.3 三层信息架构、LOD 与批次

| 信息层 | zoom | 内容 | 透明度/稳定性 |
|---|---:|---|---:|
| Strategic base | 0.20–5.00 | 海陆大形、浅海、最终海岸、城市 mass、motorway/trunk、机场识别层 | `alpha=1`，永不随滚轮变亮/变暗 |
| Operational features | 0.24–5.00 | primary/secondary/tertiary、概括街区骨架、城区/工业区 density mass、铁路、跑道/停机坪与主要港区 | `smoothstep(0.24, 0.38, zoom)`；只淡入透明 feature，不复制底色 |
| Detail features | 0.58–5.00 | building、residential/service、码头、水道、局部地表材质与精细阴影 | `smoothstep(0.58, 0.82, zoom)`；目标瓦片完整缓存后才显示 |
| Tab | 固定全图 | Strategic base 的 1024×1024 `UPDATE_ONCE` 快照 | 不显示 building/detail |

三层来自同一矢量事实源和 style profile，不是三张独立地图。现阶段全图 renderer 仍以单一不透明 Operational packet 承担共享 base；只有完成 feature 拆包后才按上表淡入 Operational。Detail 已按上表独立淡入。相机平移/缩放只改变 Canvas transform 与少量 layer alpha，禁止每帧重新三角化或 `queue_redraw()`。

### 2.4 载入预热与缩放止损

- 正式东京湾的 debug 预览数据与主图 Operational、Tab packet definitions 必须在 `building_preloader` 载入场景分帧预热；进入战斗与首次按 `Shift+F10` 不得再执行完整 JSON 解包或几何三角化。
- Boss Debug、bench、UGC 试飞不预热东京湾候选图；资源缺失时载入流程继续，游戏内开关仍按原契约回滚 PNG。
- **已否决实验**：禁止整张不透明 LOD 根节点做 alpha 交叉合成；半透明城区、terrain wash 与道路重复叠加会造成 zoom 时整体明暗漂移。
- **已否决实验**：禁止把道路密度量化为规则六边形/方格色块；它是与真实城市形态无关的假细节，不能作为缺失 building/block/landuse 数据的替代。
- 正式局点击战区时，战术地图已由 Presentation `panel_in` 真暂停；候选开启时必须把该暂停窗口作为跨区 detail 的唯一运行期预热入口。事务顺序固定为：锁住地图关闭/重复点击 → 以战区圆外扩 1.2 km 请求最多 12 格 → 完成后绑定缓存 → 解除关闭锁并下达巡航。预热期间按 Tab/Esc 只登记“完成后关闭”，不得提前解除暂停。
- 跨区预热失败时记录 EventLogger 并继续使用 Operational 概括层，不阻塞任务、不崩溃；候选未开启、UGC、Boss Debug 与 bench 正常路径不得触发。战斗恢复后 `_streaming_enabled` 仍为 `false`，禁止相机移动自动进入 `_drain_request_queue`。
- 在共享 base + 连续 feature fade 架构完成前，主地图 A/B 暂时固定使用 Operational packet；缩放只改变 Canvas transform，不切整图 LOD。Operational 保留 residential 细路以避免空白，但此状态只用于数据审计，不得申报 PNG 视觉对等。

### 2.5 运行时视觉 QA 基线

- `map_visual_qa` 必须通过 Godot 4.7 GL Compatibility 的真实渲染窗口采集，不得以 Pillow 离线合成替代；统一由 `bench/run.cmd ... Shadow Visual` 启动，继续受项目锁、稳定 shadow 副本、有限超时和进程树回收保护。
- 固定输出 1600×900，同一 renderer、同一 camera transform 依次采集 PNG reference 与 vector candidate。首批机位至少覆盖：全图、东京湾 operational、横滨港 4×4 km detail，以及旧阈值 0.224/0.226、0.749/0.751 两组缩放稳定性对拍。
- 采集产物、manifest、diff、metrics 与 contact sheet 只回收到 `tmp/map_visual_qa/`；不得进入 Godot 扫描目录，也不得作为地图内容被运行时加载。
- 自动报告必须至少包含：尺寸一致性、全图与分块 RGB mean/stddev、亮度、边缘密度、像素差热图、近阈值亮度变化。近阈值成对截图的平均亮度漂移必须 `< 2%`；局部材质参考存在时每通道 mean 差目标 `<= 4 RGB`。
- 当前 V11 允许作为失败基线进入报告，但报告必须明确列出未过门项；只有连续两轮全部客观门通过，才可生成用户里程碑稿。

### 2.6 横滨金样技术裁定

- Godot 4.7 GL Compatibility 的 GLES3 后端不提供 2D MSAA，也不接受 viewport FXAA；大量亚像素建筑线直接提交会形成黑色点噪。故直接矢量只作为一次性烘焙源，不作为 detail 档最终展示面。
- 金样采用载入期 `3072²` 临时 SubViewport 超采样，再由第二个 SubViewport 在 GPU 两级线性降采样至 `1536²`，只读回最终尺寸并释放临时 viewport；4×4 km 样板常驻 RGBA8 为 9 MiB，峰值暂存 45 MiB，主画布只增加 1 draw call。
- detail 特征在 zoom 0.58–0.82 内按 smoothstep 连续淡入，禁止按单点阈值整批出现；底色、海岸和主路属于共享 base，不随 detail tile 淡入。
- 当前金样包含 15,601 栋真实 OSM 建筑以及 landuse / rail / waterway / port 图元；这证明数据与缓存路线可行，不等于全东京湾已达到 PNG 对等。

### 2.7 全图同风格扩展（用户批准 2026-08-06）

- 横滨 4×4 km 金样的颜色、建筑描边、环境色阴影和超采样参数锁为 `yokohama_gold_v5_locked`，东京、川崎、横须贺、千叶及乡郊不得分叉色板。
- Detail 格只在 loading 或安全暂停按相机邻近度异步解包/三角化，随后提交一次 SubViewport 与 GPU 降采样；战斗中禁止烘焙/readback，未驻留区域保留 Operational 概括层。已驻留 detail 在 zoom 0.58–0.82 连续淡入，禁止整批跳变。
- 中远景道路用真实主次道路骨架与 OSM 密度 mass 概括，不得用六边形、方格或随机噪点填空。密度透明顶点必须保留同色 RGB，禁止透明白插值形成沿海亮带。
- Operational 的城市中层不追求逐栋复原：以本地 Kanto PBF 的真实 `unclassified/residential/living_street/service` 道路生成确定性的“街区骨架”，先按道路等级、长度与 2 km 分区配额筛选，再做世界空间折线简化。小楼只由连续建筑密度 mass 概括；禁止把全部住宅路或逐栋小楼提交到主画布。
- 街区骨架必须并入既有 `road_core` 静态 packet，新增 draw call 为 0；目标上限为 12,000 条折线、80,000 个线段、160,000 个三角形、gzip 运行时包 8 MiB。超过任一上限先降低 `residential/service` 分区配额，不得牺牲 60 FPS 底线。
- V17 在不改变上述硬上限的前提下，将 2 km 分区配额提高为 `unclassified=22`、`residential=34`、`living_street=2`、`service=3`；目标是约 10,000 条真实骨架。只有固定东京/西岸/千叶中景的街区连通性确实改善且两轮压力样本无低于 60 FPS 帧，才保留该密度。
- 街区骨架使用窄灰绿 casing + 低对比 core 两层，但分别并入既有 `road_casing` / `road_core`，不新增 draw call、不提交 shadow。两层合计仍须低于 160,000 个三角形；若超预算先减住宅路配额。
- V19 必须把横滨金样的“可读建筑肌理”推广到 Operational 全图，但不逐栋复刻造型：保留既有大型建筑真实三角形；中小建筑从同一 AGDT 轮廓离线提取方向包围盒，并按每个 2 km 瓦片 `medium <= 600`、`small <= 1200` 的面积优先配额确定性筛选。所有类别使用顶点色合入既有 `industrial` packet，新增 draw call 为 0；不得生成规则格、随机点、阴影或高光。
- V19 Operational 建筑概括层硬上限为新增 700,000 个四边形、1,400,000 个三角形、gzip 16 MiB；主层总三角形上限 3,000,000、draw calls 仍 `<=24`。东京/西岸/千叶 0.28 固定机位必须显著恢复街区颗粒和陆地层次，但单体不得呈纯黑噪点；性能任一轮出现低于 60 FPS 帧时，按 `small quota -> medium quota -> alpha` 顺序削弱，不得把烘焙或筛选移进战斗帧。
- V20 不再让 Operational 为远看只占数像素的大建筑支付完整凹多边形成本：大/中/小三类全部从真实轮廓离线压成面积守恒的方向包围盒，凹形厂房按原多边形面积等比收缩、不得把空角填成巨大深色块；AGDT Detail 仍保留大型建筑真实形状与静态侧墙，因此近景金样不降级。释放的三角预算只允许换成连续真实街区道路，不得增加总 draw call 或战斗期工作。
- V20 的 2 km 道路配额为 `unclassified=35`、`residential=60`、`living_street=2`、`service=3`；AGOR 上限提高为 20,000 条、60,000 线段、240,000 个 core+casing 合计三角形、gzip 8 MiB。Operational 总三角形必须不高于 V19 的 1,988,392，draw calls 仍 `<=24`；若东京/西岸道路变成黑网或第二轮出现低于 60 FPS 帧，先降 residential 配额，不得恢复大建筑复杂三角。
- V21 的近景高度层禁止按 footprint 面积直接猜测：东京湾大面积对象常是低矮仓库。只消费本地 OSM `height` 或 `building:levels`，换算 `height_m = height` 或 `levels × 3.2m`；仅 `height_m >= 12m` 且 footprint `>=180 px²` 的建筑生成真实高度侧墙，缺高度证据的 large 继续使用 8px 低浮雕。
- V32 每个 AGDT 对应一个可选 AGLW gzip sidecar：每顶点存世界坐标与预烘焙色，所有高度几何合入既有 `building_large_wall` packet，detail draw-call 不增加。投影固定东南向；`<80m` 仍使用 `clamp(height_m × 0.5, 6, 52) px`，只有具备真实高度证据的 `>=80m` 高层使用 `min(122, 52 + (height_m - 80) × 0.28) px` 突破城市地毯。高层顶面先提交全尺寸冷暗 casing，再提交按约 1.6px 内缩的米灰屋顶；两层复用同一耳切索引和 packet，形成批准区域的窄深边。高层墙体必须足够实体，禁止浅色悬浮碎片或粗黑屋顶块。投影 bbox 必须参与跨瓦片分配。sidecar 总 gzip `<=16 MiB`、全图高度几何 `<=210,000` 三角、单瓦片 `<=50,000` 三角，失败/缺包回退旧 8px 浮雕。
- 高度墙不得改变 AGDT 屋顶、碰撞、`is_on_land` 或 gameplay；只能在 loading/安全暂停瓦片烘焙时解码，读回纹理后与源 detail definitions 一并释放。四格接缝峰值仍 `<1.5`，12 格 LRU/110 MiB 常驻与 150 MiB 峰值上限不变；两轮 49 架压力样本仍不得出现低于 60 FPS 帧。
- V23 对最终 detail 缓存纹理统一应用 `Color(1.25, 1.25, 1.24)` 静态乘色，修正超采样后大量半透明 landuse/建筑边缘在主画布系统性偏暗；该乘色不得改变 alpha、几何或 draw call。1.40 倍方案虽更接近 PNG 均值，但使四格接缝峰值达到 1.574，明确否决；1.25 倍必须维持接缝峰值 `<1.5`、三组 zoom 亮度门通过。色阶不得逐瓦片单独调节。
- V24 补齐整图任意导航可达性：候选开启时，在 Tab 空白处左键设置巡航航点，必须复用 TacticalMap 已建立的真暂停，以航点为中心预热 `4.4 km × 4.4 km` Detail 区域；事务期间锁住重复点击并延后 Tab/Esc 关闭，完成或失败后才下达 `command_move`。成功绑定新 LRU 纹理；失败记录 EventLogger 并使用 Operational，不阻断巡航。候选关闭、UGC、Boss Debug 和 bench 正常路径不触发。
- V36 修正正式战区预热的空间预算：禁止把 `center ± (radius+margin)` 的巨大外接方框交给 12 格 LRU 后再按圆心截断。先计算玩家到战区圆的近侧抵达点，再以“抵达点—圆心”中点为预热中心，半边长取 `radius×0.5 + 600px`，保证近侧边缘、圆心和两端各 600px 安全带进入同一预算内走廊。预热成功或 Operational 回退后才下达同一个抵达点；不得让预热区域和实际巡航目标分别计算而漂移。
- V37 以用户实机发现的半屏硬断层为阻断缺陷：安全暂停预热必须按 `zoom=0.82` 的真实视口分别覆盖抵达点、路径中点与战区圆心，并对所需非空瓦片做并集；并集超过 12 格时整批拒绝并保持 Operational，禁止截断后显示半张 Detail。运行时 Detail 根只有在当前可见视口所需的全部非空格都驻留时才可渐入；覆盖不足时整层平滑退回 Operational，禁止暴露瓦片直边。
- V37 Operational 的 51,121 个 large 概括楼恢复一层统一东南偏移的冷暗侧墙，墙体合入单一静态 `building_wall` packet，屋顶仍覆盖其上；不增加逐栋节点、shader、重绘或战斗期计算。新增预算为 `<=105,000` 三角、1 draw call；Operational 总预算调整为 `<=1,220,000` 三角、`<=25` draw calls。中小楼仍由 density mass / 街区骨架概括，帧数门不变。
- V38 不再把 manifest 未登记的网格默认为“海面所以没问题”。全图 16×16 共 256 格必须逐格分类为：199 个非空 Detail、4 个已登记空格、其余未登记格。所有未登记/空格都要在与 gameplay 同源的陆地判定中做规则采样；任何陆地采样命中都视为漏烘焙并阻断整图完成，必须补入 AGDT 或给出显式、可审计的艺术化例外。
- V38 的 PNG 大楼对比必须包含正式游戏的旧 `BuildingRenderer`，而不是只拍 `tokyo_bay_bg.png`。报告必须明确两者不是同一效果：旧栈是横滨局部合并街区、相机相关 parallax 与深阴影；候选是全图静态 large 低浮雕 + OSM 真实高度地标。固定横滨同位截图需分别保留“PNG+旧楼”和“矢量候选”，并记录覆盖范围、建筑数量、是否随相机 redraw 与性能差异。
- V39 只调整三档综合色阶和已有边缘阴影，不新增道路、建筑、噪声或独立图层：Strategic/Tab 压低大面积 density mass 对比；Operational 提高海陆可读性但减弱城市实心块；Detail 保留屋顶辨识度，同时收窄海岸和建筑阴影，避免大片冷黑色块。
- 三档共享同一拓扑和 style profile，只允许 LOD palette / alpha / 既有 packet 的宽度与偏移不同。不得重新启用规则 terrain wash、随机颗粒或逐格 tint；draw call 和三角数不得因为 V39 增加。
- V40 以用户否决的 Operational 大色块和“拉近后细节糊脸”为阻断缺陷。Operational 不得再把城市质量块、large 屋顶、casing/侧墙作为一次同步出现的 feature；必须只重排已有静态 packet 的 zoom opacity，把信息拆成四段：常驻海陆/海岸/主路 → 逐渐退弱的城市 mass → 逐渐加入的概括屋顶 → 最后加入的低浮雕边缘。禁止借此新增道路、建筑、纹理或逐帧几何。
- V40 的 Operational 渐进区间固定为：城市 mass 在 zoom `0.18–0.58` 从 `1.0` 平滑降至 `0.28`；large 屋顶在 `0.24–0.58` 从 0 平滑升至 `0.56`，只作低透明体量暗示，禁止形成第二层实心色块；casing/侧墙在 `0.34–0.74` 从 0 平滑升至 `0.72`，以边缘和低浮雕替代大面积填充。所有曲线使用 `smoothstep`，底层海陆、海岸和主路始终不透明，禁止整根 cross-fade 或 zoom 明暗闪烁；完整建筑填充只由最后淡入的 Detail 层提供。
- V40 Detail 仍使用已预热完整瓦片，但淡入区间从 `0.58–0.82` 放宽为 `0.50–0.98`，并把 smoothstep 结果取 `1.75` 次幂作为感知淡入曲线：zoom `0.65` 只允许约 `7.8%` Detail，`0.80` 约 `51%`，`0.98` 才完整到达。当前视口覆盖不完整时继续整层回退。Detail 只在 Operational 已形成屋顶/边缘层次后逐步补充普通建筑、铁路、地表和真实高度，禁止在单一滚轮步长内把完整纹理“糊到脸上”。
- 浦贺水道等正式纯海域的真实视口并集允许命中 `0` 个非空 Detail 瓦片；这是“无需加载、保持 Operational”的成功结果，不是预热失败。只允许 `0..12` 个完整并集，`>12` 仍整批拒绝；空海域不得显示旧缓存 Detail，也不得阻塞 Tab/Esc。
- loading 的 `BOOTSTRAP_REGION` 必须包含 `MapBoundary.get_player_start()`，并至少覆盖出生点四周一个完整 Detail 视窗；每个正式战区走廊必须与至少一个非空 AGDT 相交。以上都是资产/几何回归，不允许开启战斗期 streaming。
- 直接在战斗主画布下令或不经 Tab 飞入未驻留区时仍只显示 Operational；禁止为追求“走到哪都立刻有 Detail”恢复战斗期相机 streaming。整图完成的定义是所有 199 个非空区块均可由 loading、战区选择或任意 Tab 航点安全预热，不是 199 张纹理同时常驻。
- V25 将中景城市细节预算从双层 neighborhood 道路重新分配为单层真实街巷：移除 neighborhood casing，只保留 `1.15 px @ zoom 0.35`、`Color8(108,121,116,150)` 的低对比 core，并把 2 km 配额提高为 `unclassified=45`、`residential=75`、`living_street=3`、`service=4`。运行包固定为 18,874 条、52,633 线段、105,266 三角、363,231 bytes gzip；必须合入既有 `road_core`，新增 draw call 为 0，Operational 总三角不得高于 V24 的 1,587,192。
- V25 只允许增加来自本地 OSM 的连续街巷，不得补规则格、随机短线或逐栋小楼。固定东京/西岸/千叶 Operational 的道路连通性必须可见改善，但不得形成黑网；亮度三门、接缝 `<1.5` 与连续两轮压力无低于 60 FPS 帧同时通过才保留，否则完整回滚 V24 道路包与样式。
- V26 把 Operational 建筑从深色实心点改为批准近景同源的“浅屋顶 + 冷暗外缘”层次：small 使用 `Color8(132,138,132,150)` 柔和填充；medium/large 分别使用 `Color8(142,144,136,175)` / `Color8(154,152,141,200)`，并在原面积守恒方向体块外扩 `2.1 world px` 生成 `Color8(77,89,89,120)` 静态 casing，原体块随后覆盖为屋顶。casing 必须合为单一 `building_casing` triangle-array packet，新增 draw call 最多 1，禁止逐栋 Node2D、shader 或战斗期重建。
- V26 casing 只服务 Operational，不进入 Strategic/Tab；新增上限为 140,000 个四边形、280,000 三角，Operational 总量 `<=1,988,392`、draw calls `<=24`。固定东京/西岸/千叶必须减少深色噪点、恢复参考区域的暗边浅顶层次；若形成白点、黑网、平均色差恶化或任一压力轮出现低于 60 FPS 帧，整项回滚。
- V27 的 Strategic/Tab 禁止提交任何逐建筑 AGOB 体块。51,121 个“large”方向体块在 1024² Tab 中退化为白色盐点，不具备地标可读性；远景只保留 OSM density 城市质量块、motorway/trunk/primary/secondary 骨架、机场、港区与三重海岸。
- Visual QA 必须额外从与 `TacticalMap.set_vector_preview_enabled` 相同的 `LOD_TAB`、1024²、`UPDATE_ONCE` SubViewport 生成 `candidate_tab_static.png` 并记录 packet/triangle 指标；禁止用主画布 0.03 缩放截图冒充 Tab。Tab 快照不得出现规则格、随机噪点或逐建筑盐点。
- V28 把“帧数是死线、城市允许概括”固化为稳定根层规则：Operational 仅提交 51,121 个 large 方向体块及其单一 casing packet；85,403 个 medium 与 176,738 个 small 不再进入 Operational。中小建筑由连续 density mass 与真实街区骨架概括，zoom 进入 Detail 后由当前驻留 AGDT 瓦片恢复屋顶、轮廓与有高度证据的侧墙。禁止为了 PNG 的逐像素 edge-density 把中小建筑重新加回稳定根层。
- V28 Operational 硬预算为总三角 `<=1,100,000`、draw calls `<=24`、静态定义预热 `<1.0s`（本机参考，不作跨机器绝对门）；large roofs 与 casing 各 `<=115,000` 三角。性能毕业以同机、同场、同 seed 的 PNG/矢量 Sentinel+Lv5+ 120 秒对照为准：矢量平均 FPS 不得比 PNG 低超过 15 FPS，低帧尖峰不得显著多于 PNG 基线；战斗帧仍禁止地图重绘、瓦片烘焙与 readback。
- V33 主地图仍固定一个不透明 Operational 根，禁止恢复整图 LOD 交叉淡化；只允许 `building_casing` 与合并建筑填充的 `industrial` 两个已缓存 feature packet 在 zoom `0.18–0.30` 间 smoothstep。`<=0.18` 完全隐藏亚像素建筑盐点，`>=0.30` 完整恢复大型建筑；sea/land、城市 mass、道路、机场和海岸始终不透明。每帧只写两个 CanvasItem 的 modulate，不遍历建筑、不重建三角、不 redraw。
- V29 新增全覆盖 `map_detail_atlas_qa`：它必须通过 `bench/run.cmd ... Shadow Visual` 逐格调用生产 `MapDetailVectorRenderer` 与 `MapDetailTileCache._bake_tile`，再把透明 Detail 缩略层按真实 16×16 世界网格叠在同源 Operational 底图上。禁止离线重画、禁止只验文件存在、禁止用少数固定机位替代整图覆盖。
- atlas 报告必须覆盖 manifest 全 203 格并显式区分 199 个有内容格与 4 个预期空格；任一非空格预热/烘焙/readback 失败即失败。15 条纵向与 15 条横向边界必须比较边界 RGB 跳变与左右/上下相邻内部梯度，峰值额外跳变 `<3 RGB`；产物固定写 `tmp/map_visual_qa/detail_atlas/`，不进入 Godot 扫描或运行时资源。
- V34 把整图风格异常纳入同一 atlas 自动门，避免再靠用户逐格发现：所有非空缩略格的合成平均亮度须位于 `90–146`，单格生产 Detail 几何须 `<=1,400,000` 三角，并在报告中记录最暗格、最亮格与最重格。该门只捕获漏底色、错误乘色、异常叠层和单格失控，不要求城乡具有相同细节密度；不得按格单独调色，也不得为通过门而补随机建筑或道路。
- V35 增加整图平均色偏门：每个非空格都须满足 `G-R = 3–12`、`B-G = -10–-1` RGB，保持批准灰绿陆地与米灰建筑的统一冷暖关系。报告必须记录两个色差轴的极值及对应格；该门用于抓取发红、发蓝、通道交换或局部错误调色，不限制真实水陆/城乡覆盖造成的亮度和密度变化。
- V16 实测否决建筑密度等值线：它会在中景形成与真实街区无关的大型有机闭环。最终只保留连续 density mass + 真实街区骨架；禁止显示底层格边，禁止以逐栋楼、六边格或随机纹理冒充街区轮廓。
- V41 纠正底图与玩法层的边界：旧横滨 `BuildingRenderer` 的 189 组合并街区同时承担可视地标、相机相关假 3D 与建筑阻挡数据，属于 PNG/矢量底图共同消费的游戏层，不是 PNG 内容。候选开启、回滚 PNG、A/B 截图和性能对照都必须保持该层可见且运行；禁止出现“碰撞仍在、建筑视觉消失”的状态。
- V41 的共享横滨地标只补回已存在的游戏性大楼，不得扩张为全图逐建筑动态 renderer。全图普通建筑仍由 Operational 静态 large 概括与 Detail AGLW 高度数据表达；两套视觉允许在横滨叠加，因为 PNG 正式路径原本也在底图建筑纹理之上叠加该游戏层。
- V41 不增加道路、建筑、纹理或 packet，只重分已有 Operational 顶点色：城市质量块使用冷灰蓝、植被使用灰绿、工业/仓储使用低饱和暖灰，机场/停机坪与港区保持米灰。统一 `URBAN_OPERATIONAL` 覆盖必须减弱，让三类密度色与工业/停机坪面在作战档可辨，但不得形成高饱和分区、规则格或新的明暗闪烁。
- 工业区与停机坪面必须并入既有 `urban` mass packet，以便在作战档随 mass 连续显示；large 建筑屋顶继续留在独立 roof packet 渐入。该重分不得增加 Operational 的 25 draw calls 或 1,192,604 三角预算。
- V42 以用户红圈指出的“棕色 landuse 越出地基漂在海面”为阻断缺陷。工业、停机坪和新增场景块都必须在 loading 静态构图时按同一组视觉 `water` 环做差集，并把与 `land_inlay` 的交集恢复；最终 packet 在 `land_inlay` 后提交。禁止只降 alpha、改色或依赖海色遮盖来掩饰越界。
- V42 参考纸模地形和总平面图的层次，只从已有 `URBAN_DISTRICTS` 中确定性选择面积 `>=20,000 px²` 的低频区域；最多 220 块，每块由同一 packet 内的贴地东南阴影、灰/灰绿/灰褐底面和约 8px 内缩浅面组成。颜色分类只使用现有 density 场与稳定坐标散列，不逐帧随机、不增加道路或普通建筑、不制作真实地形等高线。
- V42 场景块在低/高战斗缩放中保持同一内部 alpha，不参与整层 cross-fade；完整 Detail 仍在其上渐入。只允许新增一个 `terrain_context` triangle-array packet，Operational 上限为 25 draw calls、1,240,000 三角，loading packet 预热本机目标 `<=1.35s`。若形成规则棋盘、大片实心遮盖、海上越界或缩放明暗尖峰，整项回滚。
- V43 把“重要大楼”从普通 Detail 纹理中提升为常驻地标：只允许 OSM 真实 `height` / `building:levels` 推导高度 `>=80m` 的高层进入全图 Operational 地标包；侧墙、窄深屋顶边与米灰顶面在 loading 一次解码后合入一个静态 `landmark` packet。该层不参与普通 large 楼的 zoom opacity，也不依赖 Detail 瓦片是否已驻留，因此最大和最低战斗档都必须保留可辨的假 3D 轮廓。横滨 189 组游戏性 `BuildingRenderer` 继续作为 PNG/矢量共享玩法层，二者不得互相替代。
- V43 低密区域不再用更多道路或小楼补空白：离线烘焙 360 块不规则 6–8 边纸模台地（灰绿 139、冷灰 57、灰褐 164），每块使用互不共心的底面/中面/内面，只有底面保留 2.2px 弱描边。所有边与视觉 water 环做精确相交拒绝，运行时只消费同一 `terrain_context` packet。台地只表达美术层次，不改变 `is_on_land`、高度、碰撞或地形玩法；不得形成规则格、同心靶纹、随机噪点或整块不透明遮盖。城区场景块门槛最终为 `>=75,000 px²`、最多 120 块。
- V43 地标包与场景台地均须在载入阶段完成，战斗帧只提交/显示缓存 packet。最终地标包为 669 栋真实 `>=80m` 高层、29,688 三角、227,154 bytes gzip；Operational 为 26 draw calls、1,240,237 三角，`terrain_context` 为 18,531 三角，视觉水面命中为 0。本机首次 loading 预热实测约 1.42–1.47s，结构门取 `<=1.60s`。若 Sentinel+Lv5 同负载平均 FPS 比 PNG 低超过 15、低帧显著更多，先削减普通场景块与道路，再削弱台地层数；669 栋真实高层与 189 组玩法大楼不得因普通 LOD 或性能降级整层消失。
- V44 以用户提供的纸板总平面参考否决 V43 的“蓝灰城区 + 绿色植被 + 橙褐工业”功能分色。分类数据继续保留，但最终可见的 density、context 与 relief 必须收敛到同一暖灰纸板色相：原始调色锚点应满足 `R-G=0..10`、`G-B=5..16`，类别间主要用明度而不是色相区分；海面仍保持冷灰蓝，以维持陆海识别。禁止为了表达 vegetation/industrial 重新引入绿色或橙色大面。
- V44 将纸模台地从 360 块收敛到 `180..240` 块，宏观采样尺度约 1.1k world px，单块半径约 320–700px；宁可留下连续底色作为呼吸区，也不得均匀铺满视口。三层仍使用非同心轮廓，但中层/内层透明度须低于底层，综合色差只形成纸张叠放和中性边缘阴影，不能读成行政区、生态区或彩色拼布。
- V44 不改变高楼、道路几何、海岸、LOD、draw packet 数或战斗期行为；既有 neighborhood 单层 core 只把偏蓝浅线中和为同亮度暖灰，禁止为了追 PNG edge-density 把全量细路压成黑网。结构回归须证明三个 density 锚点均属于暖纸色族、类别距离保持可辨但不超过 0.08。固定机位须与用户参考一样先读出深浅纸面、主路骨架和假 3D 阴影，再读出功能分类；若综合色块仍能一眼被称为绿块/棕块，则本轮失败。
- 固定 QA 至少覆盖全图、东京/西岸/千叶 Operational、东京/横滨/横须贺/千叶 Detail、四格接缝与三组 zoom 阈值。

## 3. 行为与公式（How）

### 3.1 切换事务

```text
Shift+F10
  -> 校验 debug build + 正式东京湾 + 资源可用
  -> enable: 隐藏 PNG Sprite；显示/懒建当前 LOD packet；Tab 建 UPDATE_ONCE 快照
  -> disable: 隐藏矢量 packet；恢复原 PNG Sprite；释放 Tab 快照
  -> 两端成功后显示提示并写 EventLogger
```

任何一端初始化失败时不得留下半切状态：主地图恢复 PNG，Tab 继续 PNG，并提示预览不可用。

### 3.2 线与面

- 多边形在首次使用该 LOD 时三角化并合并成同色 packet。
- 道路每段扩成矩形三角带；主路端点补低边数圆帽；shadow/casing/core 分 packet，residential/service 不画黑 casing。
- 浅海、海岸 outer/glow/core 都由 water 环生成；低透明冷灰绿替代纯黑阴影。
- 世界颗粒只允许低透明、世界坐标固定的大片纸纹；禁止离散黑点。

## 4. 结构与组成（Structure）

- `MapVectorPreviewRenderer`：共享加载 V11 矢量补充数据，以同一实现创建主地图与 Tab 的静态 LOD 节点。
- `MapVectorPreviewRenderer` 的 Operational `landmark` packet：一次性解码 669 栋真实高层的侧墙、窄深边与米灰屋顶；独立于普通 mass/roof/depth opacity，全部战斗 zoom 均保持 alpha 1。
- `MapDetailVectorRenderer`：把横滨 building/landuse/rail/waterway/port 合并成一次性烘焙源；不直接挂到战斗主画布。
- `MapDetailTileCache`：loading 期生成并静态持有 1536² ImageTexture；场景切换后主地图仅绑定缓存 Sprite，失败时不阻塞且继续使用基础候选/PNG 回退。
- `MapFeatureRenderer`：拥有 A/B 状态，控制 PNG Sprite 与预览 renderer 可见性。
- `SurvivorMode`：A/B 事务只切换底图；旧 `BuildingRenderer` 作为共享游戏层在候选与 PNG 两侧始终可见、可处理，视觉状态必须与建筑阻挡状态一致。
- `TacticalMap`：使用同一状态；矢量开启时创建一次性 SubViewport 战略快照，动态图标仍按原 10Hz 绘制。
- `SurvivorMode`：唯一输入与同步入口；不把模式判断下沉到共享地理层。

## 5. 验收标准（Acceptance / Litmus）

- [x] 正式局默认仍显示当前 PNG；`Shift+F10` 可在同局往返切换，普通 `F10` 行为不变。
- [x] 主地图与 Tab 每次同步切换；Tab 不再在矢量开启时硬编码显示东京湾 PNG。
- [x] 开关不改变 `is_on_land`、战区、出生点、建筑碰撞或任何 gameplay 数据。
- [x] 主地图静态层加载后零持续 `queue_redraw`；zoom 不改变地图根节点或全局 alpha。
- [x] 正式载入场景完成后主图 Operational 与 Tab packet definitions 命中缓存；首次开关不再现场构图。
- [x] 横滨 detail 缓存在 `building_preloader` 阶段完成；正式主地图从静态缓存绑定，首次开关不执行 viewport 烘焙、CPU resize 或 GPU readback。
- [x] 全图 199 个非空 detail 包可在 loading、战区选择或任意 Tab 航点的真暂停中按区域加载；任意航点固定预热 4.4 km 方区，完成/失败后才下达巡航；12 格 LRU 常驻 ≤110 MiB、顺序切区峰值 ≤150 MiB，战斗 streaming 始终关闭。
- [x] 当前可见视口覆盖不足时 Detail 整层回退，不得出现横向/纵向半屏硬断层；战区抵达点、路径中点和圆心在 0.82 zoom 的预热并集必须完整且不超过 12 格。
- [x] Operational 全图 large 楼具有批量冷暗侧墙 + 浅屋顶的伪立体层次；新增最多 1 draw call / 105,000 三角，性能对照不得显著劣于 PNG。
- [x] 16×16 的全部 256 格都有明确分类；53 个 manifest 外格与 4 个登记空格不存在未解释的陆地采样命中。`detail_10_06` / `detail_14_04` 是截图与 PBF 分配记录支持的显式海岸边缘例外，集合精确锁定。
- [x] PNG 对照截图包含正式旧 `BuildingRenderer`；横滨大楼同位对比与“旧局部动态 / 新全图静态”差异已写入 manifest 与制作规则。
- [x] Strategic/Operational/Detail 三档固定机位均证明综合色阶更柔和，城市大色块减少，海陆和建筑边缘仍可读；缩放稳定性不回退。固定机位低频色块标准差由 V38 的 3.980/4.147/7.741 降至 V39 的 1.604/2.309/6.145（湾区 Operational / 东京 Operational / 横滨 Detail），边缘密度同步小幅下降而未消失。
- [x] V39 不增加任何地图内容、draw call 或三角数；金样、全图 atlas、真实 GL 截图和成对性能门通过。最终 LOD0/1/2/Tab 为 19/25/23/19 draw calls、651,238/1,192,604/1,354,086/630,202 三角，与 V38 几何规模一致；120 秒同机 Visual 压力矢量 112.32 FPS / 最低 43.29 / 9 低帧，随后 PNG 105.12 / 42.00 / 35，未出现 >15 FPS 回退。
- [x] V40 同一横滨机位 zoom `0.20/0.35/0.50/0.65/0.80/0.98` 必须显示单调增加的信息层次：大色块逐步退让、街区骨架始终可读、概括屋顶先于阴影边缘、完整 Detail 最后到达；不得出现某一步突然被大量细线或建筑糊满。
- [x] V40 自动视觉门按 zoom 语义评分，不再要求远景 edge density 机械追平含纹理/旧动态楼的 PNG：`full/Operational` 候选绝对边缘密度必须在 `1.5..8.0`，`0.8+` 结构 Detail 必须在 `2.5..14.0`，防止空白或噪点；六档渐进相邻画面平均亮度漂移 `<=4%`、边缘密度单步增幅 `<=15%`。PNG 仍承担色板（全图 `<=12 RGB`、横滨金样 `<=6 RGB`）和近景层次对照，不得取消并排人工验收。
- [x] V40 Detail 起止门槛两侧固定截图平均亮度漂移 `<2%`，六档 edge-density 不出现超过前一档 `15%` 的单步跃升；滚轮往返后同 zoom 截图稳定。Operational/Detail draw call 与三角数不高于 V39，战斗中仍无地图 bake/readback/redraw。
- [x] V40 金样、全图 atlas、真实 GL 渐进矩阵与 Sentinel + Lv5+ 成对性能门通过；任一失败完整回滚 V39 opacity 曲线，PNG 默认与回滚路径不变。
- [x] V40 还必须按正式滚轮 `target_zoom ×1.10` 的稳定落点补采 zoom `0.50/0.55/0.605/0.666/0.732/0.805/0.886/0.974`；相邻目标最终画面平均亮度总变化 `<=2.25%`、edge-density 不得单步增加 `>15%`。由于正式相机用 `lerp(delta×10)` 连续追赶 target，另在 `0.50–0.98` 每 `0.02` zoom 扫频：相邻插值采样亮度漂移 `<=1.0%`、edge-density 增幅 `<=8%`，用来拒绝淡入曲线内部的真实尖峰。这两组密采证据优先于稀疏六档矩阵。
- [x] 四瓦片交点与内部接缝在 0.58/0.82 两侧无裂缝、重复暗边或突跳；1536² 内容区裁切显示，4 px 外挤仅供双线性采样，不再叠入相邻世界区域。
- [x] 东京、西岸、千叶 Operational 与东京、横滨、横须贺、千叶 Detail 固定机位均能消费同一 style profile。
- [x] V41 游戏内候选与 PNG 两侧都显示同一组 189 个横滨假 3D 游戏地标；候选开启后地标视觉、相机视差与建筑阻挡保持一致。
- [x] V41 固定横滨最大战斗档截图中，工业/仓储、植被、普通城区、机场/停机坪与港区至少形成四类可辨的低饱和综合色阶；不得退化为单一巨大灰块，且 Operational 保持 `<=25` draw calls / `<=1,192,604` 三角。
- [x] V41 PNG/候选固定机位与 120 秒同负载成对性能门都包含共享 `BuildingRenderer`；矢量平均 FPS 不得比 PNG 低超过 15，低于 60 FPS 的帧不得显著多于 PNG。
- [x] V42/V43 用户红圈对应港区及全部固定海岸机位不存在棕/灰场景面越出视觉陆地底盘；Operational `terrain_context` 的 relief/district/facility 三类视觉水面命中均为 0。
- [x] V43 低/高战斗缩放都能读出灰、灰绿、灰褐三类低频场景块及贴地窄暗边；最终 360 块均为不规则、非同心纸模面，不依赖更多道路、小楼、噪点或真实等高线，滚轮亮度/edge-density 门通过。
- [x] V43 Operational 只新增 `terrain_context` 与常驻 `landmark` 两个语义 packet；最终 26 draw calls / 1,240,237 三角，首次 loading 预热约 1.42–1.47s，低于 1.60s 结构门。
- [x] V43 全图 669 栋 `>=80m` 真实高层在 Operational 常驻 `landmark` packet；最大/最低战斗缩放和 Detail 未驻留回退都能看到实体侧墙、窄深边和米灰顶面，不依赖普通 large 楼 opacity；横滨 189 组玩法假 3D 大楼在 PNG/矢量两侧继续共享。
- [x] V44 Operational 固定机位不再出现可直接辨认的绿块/橙褐块；density、context、relief 三组分类全部落入同一暖灰纸板色族，视觉层次主要来自明度与中性阴影。三个 density 锚点均通过暖纸色族与 `0.02..0.08` 距离门。
- [x] V44 全图纸模台地为 220 块（旧版 360），单屏分布存在呼吸区且不呈均匀拼布；Operational `terrain_context` 三类水面命中继续为 0，669 栋常驻高楼与全部缩放稳定性不回退。
- [x] V44 真实 GL 固定机位、六档/滚轮/连续扫频与结构门全部通过；Operational 为 26 draw calls / 1,236,202 三角，低于 V43。120 秒同负载 PNG 117.91 FPS / 3 低帧，矢量 119.33 FPS / 1 低帧，未触发 -15 FPS 门；两组后半程战斗结果不同，不宣称矢量更快。
- [x] 止损态主地图固定 Operational，连续滚轮不切整图 LOD、无双根 alpha 合成。
- [x] 规则道路密度格已移除；不得再用程序格子冒充 PNG 的建筑/街区肌理。
- [x] Godot 4.7 Visual Shadow 固定矩阵能重复产出 PNG/candidate/diff/metrics；近阈值亮度漂移 <2%。
- [x] 固定视野能看到全图真实细路、机场内部和港区设施，且无纯黑噪点、悬空海岸或蓝色道路。
- [x] 资源缺失/解析失败时原子回滚 PNG，不崩溃。
- [x] 性能：Godot 4.7.1 GL Compatibility、Sentinel + Lv5+、共享 189 组玩法大楼的 120 秒同负载路径。V44 同机连续样本为 PNG 平均 117.91 FPS、最低 38.12、3 帧低于 60；矢量平均 119.33 FPS、最低 29.87、1 帧低于 60。两侧起始均为 49 架/38 敌方，最终 PNG 43 架/击杀 6、矢量 46 架/击杀 3，后半程负载不同，因此只证明未触发 -15 FPS 地图回退，不宣称矢量更快；战斗中仍禁止地图重绘、detail 烘焙/readback。
- [x] 已知 seam：UGC vector-only、Boss Debug 空白图与 bench 跳图行为不变。
- [x] i18n：开关提示三语齐全。
- [x] 文档：本 spec 已登记 `_INDEX.md`，当前文档校验通过。
- [x] V45 用户最终视觉裁决未通过：生产默认永久回到/保持 PNG，主地图与 Tab 不删除、不改名、不以候选资产覆盖；本 spec 状态改为 `superseded`。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与静态 renderer
- [x] 生成自包含 V11 预览补充 JSON，并保留 OSM 来源元数据。
- [x] 实现共享 source、面三角化、道路三角带与四档 LOD。

### 阶段 2 — 主地图与 Tab A/B
- [x] `MapFeatureRenderer` 接入 PNG/矢量可见性事务。
- [x] `TacticalMap` 接入同源 `UPDATE_ONCE` 战略快照。
- [x] `SurvivorMode` 接入 `Shift+F10`、toast 与 EventLogger。

### 阶段 3 — 验证
- [x] 数据/packet 单元回归。
- [x] Godot 4.7 Shadow 定向回归；实机查看各 zoom 与 Tab 仍待人工视觉门。
- [x] Sentinel + Lv15 同负载 PNG/矢量 Operational 与 Detail 性能采样。

### 阶段 4 — 金样与自动迭代
- [x] 建立 Godot 4.7 Visual Shadow 固定矩阵采集器与离线 metrics/contact-sheet 工具。
- [x] 横滨港 4×4 km 补齐 building/block/landuse/rail/waterway/port 数据，分别验证直接矢量与一次性超采样缓存。
- [x] 完成至少 10 轮诊断→修改→运行时复测；横滨金样的色调、边缘和信息层级已锁为全图 style profile。
- [x] 扩展为全东京湾 199 个非空 detail tile；东京、西岸、横滨、横须贺、千叶与四瓦片接缝均进入固定矩阵，接缝外挤重叠已修复。

### 阶段 5 — 决策收口
- [x] 用户整图视觉验收否决纯矢量生产替换；保留正式 PNG 主图与 Tab 图。
- [x] 候选 renderer/数据/QA 仅冻结为 debug 研究材料；本轮不删除候选资产，也不再继续生产化迭代。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 静态预览 renderer | `scripts/survivor/map_vector_preview_renderer.gd` |
| 主地图 A/B | `scripts/survivor/map_feature_renderer.gd` |
| Tab 快照 | `scripts/survivor/tactical_map.gd` |
| 输入事务 | `scripts/survivor/survivor_mode.gd` |
| 数据 | `resources/maps/tokyo_bay_vector_preview.json` |
| 回归 | `scripts/tests/test_map_vector_preview.gd` |
| 真实画面采集 | `scripts/tests/map_visual_qa_runner.gd`、`scenes/tests/map_visual_qa.tscn` |
| 横滨金样矢量源与缓存 | `scripts/survivor/map_detail_vector_renderer.gd`、`scripts/survivor/map_detail_tile_cache.gd` |
| 金样数据与烘焙 | `resources/maps/yokohama_gold_slice_preview.json`、`scripts/tools/bake_yokohama_gold_slice.py` |
| 图像评分 | `scripts/tools/map_visual_qa.py` |
| OSM 实际高度侧墙 | `scripts/tools/bake_tokyo_bay_landmark_walls.py`、`resources/maps/tokyo_bay_landmark_walls.json`、`resources/maps/detail_landmark_walls/` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-05 | 1 | 用户授权实现游戏内 A/B：默认 PNG、Shift+F10、主图/Tab 同步、静态 LOD packet、失败原子回滚、禁止以截图冒充矢量 |
| 2026-08-05 | 2 | 首轮游戏内反馈：移除未受陆地 mask 约束、会污染海面的 terrain wash；提高陆海明度分离并柔化次级道路；建立 PNG 局部色差、陆海可读性、道路边缘、黑/蓝伪影自动评分，5 轮从 39.00 提升到 63.15；Godot 4.7 Shadow 四档 LOD 回归通过。 |
| 2026-08-05 | 3 | 用户实机截图发现 Tab 海陆主体缺失。根因是面积 628566 px²、1788 点的主 water ring 自交，`Geometry2D.triangulate_polygon()` 整环失败，而旧回归只检查“存在少量水三角形”导致假绿。失败回退现用 Clipper `offset_polygon` 清理/拆环后再合并三角；四档主水环零失败，Tab water triangles 617→3233，draw call 不增加。 |
| 2026-08-05 | 4 | 用户实机主地图截图发现运行时仍呈大块灰白。根因是把带 mask/blur/织理的离线合成色板直接用于无后处理的 triangle-array 直绘。运行时 profile 独立校准：压暗海面而非继续提亮陆地；terrain wash 改在 water 前提交，由水环静态覆盖越海部分；Operational/Detail 城区轮廓与 fill 合并为同 packet；Operational 补 secondary 骨架并提高道路直绘 alpha。四档维持 20/24/24/20 draw calls。 |
| 2026-08-05 | 5 | 用户实机截图显示正式战斗视野的细节仍近乎消失。根因是 LOD 与线宽沿用离线原型假设：主相机实际从 0.35 开始、最远 0.20，而旧阈值把 `<0.35` 全降为只画 motorway/trunk，Operational 线宽又按 0.70 标定，导致 0.35 下 tertiary 仅约 0.39 屏幕像素。现将 Strategic 收窄到 0.20–0.225，Operational 按开局 0.35 标定并保留 residential，Detail 从 0.75 起；最远档也保留 primary/secondary 骨架，同时提高城区/次路直绘对比。新增正式相机 zoom→LOD 与道路密度硬回归。 |
| 2026-08-05 | 6 | 用户要求把候选图在载入阶段提前准备，并消除缩放时细节整批跳变。新增 `building_preloader` 四档 packet definitions 分帧预热；主地图采用 0.35 秒 smoothstep 交叉淡化与双向迟滞；Strategic/Operational 将 tertiary+residential 聚合为世界空间街区色块，Operational 仅保留 tertiary 骨架，Detail 才显示 residential/service 细线。色块复用 urban packet，draw call 上限不变。 |
| 2026-08-05 | 7 | 实机否决 v6：规则道路格与 PNG 城市肌理差异巨大；整图根节点淡入让半透明图层重复合成，滚轮时整体忽明忽暗。立即移除格子与整图交叉淡入，主图暂锁 Operational 并恢复 residential，loading 仅预热 Operational+Tab。裁定当前 V11 不具备 PNG 对等资格；后续必须先补 building/block/landuse 数据并做共享 base + 连续 feature fade 或运行时矢量瓦片缓存垂直切片。 |
| 2026-08-06 | 8 | 用户授权自主推进。新增 Godot 4.7 Visual Shadow 运行时 QA 契约：1600×900 固定矩阵、PNG/candidate 同位采集、阈值两侧亮度稳定性、diff/metrics/contact sheet 全部回收到 `tmp/`；当前 V11 先登记为失败基线，横滨港 4×4 km 金样连续两轮过门后才请求用户审核。 |
| 2026-08-06 | 9 | 完成横滨 4×4 km 金样与 6+ 轮内部复测：15,601 栋 OSM 建筑；确认 GL Compatibility 不支持 2D MSAA/FXAA，否决 detail 直接矢量展示，改用载入期 2× 超采样 + Lanczos 一次性缓存；1536² 常驻 9 MiB、主画布 1 draw call、缓存烘焙约 0.72s，zoom 阈值亮度漂移 0.078%。金样局部色调/边缘门已通过，全图仍失败，PNG 保留。 |
| 2026-08-06 | 10 | 用户要求在游戏内实试当前金样。将金样 renderer/cache 从 tests 提升到 survivor 共享层；`building_preloader` 在 Operational+Tab 后生成静态 detail texture，`MapFeatureRenderer` 的现有 Shift+F10 A/B 事务绑定同一缓存并按相机 zoom 连续淡入。PNG 仍为默认与失败回退，Tab 保持战略档。Visual QA 改为先预热再实例化正式 renderer，确保截图覆盖真实生产消费路径。 |
| 2026-08-06 | 11 | 用户认可横滨金样并批准扩展。固化 Strategic base / Operational features / Detail features 三层信息架构：底色永远不淡化，只有透明特征按重叠区间连续加入。首批生产验证扩为西岸连续 8×8 km 四瓦片，规定 36 MiB 常驻、≤76 MiB 峰值、4 draw calls、逐瓦片释放源几何与接缝固定机位。 |
| 2026-08-06 | 12 | 用户明确要求按批准的整块效果完成全图。完成 16×16 网格、199 个非空 AGDT 包、12 格 LRU、513² OSM 密度场与全图大建筑 packet；新增东京/西岸/千叶中景和四方向近景矩阵。Operational 保持单一不透明 base，detail 仅局部连续淡入；修复透明白插值亮带。规定候选与旧横滨 BuildingRenderer 互斥，并新增同负载 PNG/矢量 Visual bench 门；PNG 仍保留直到并排视觉与性能毕业。 |
| 2026-08-06 | 13 | 全图收口：detail Sprite 只显示 1536² 内容区，4 px 外挤不再覆盖相邻世界区域，消除四格交点 ±4 px 半透明重复暗边；Godot 4.7.1 RTX 3080 Visual bench 以 49 架同样本跑满 30 秒，矢量 118.68 FPS、最差 75.20、低于 60 FPS 为 0，相对 PNG 平均掉幅 0.64%。视觉与性能候选门通过，但 PNG 删除仍等待用户最终整图裁决。 |
| 2026-08-06 | 14 | 用户确立“帧数是死线”：所有建筑体块保留，小建筑改为单层柔和核心轮廓，仅中大型建筑保留阴影/高光，横滨金样降至 339,120 三角形、18 静态批次、约 159 ms packet 构建。用实测否决战斗内 GPU 烘焙/readback（最低 16.55 FPS），运行时未驻留区域固定回退 Operational 概括层；detail 仅允许 loading/安全暂停预热。修正压力预热围绕实际相机位置，两轮 50 架 30 秒 Visual 样本均无低于 60 FPS 帧。PNG 仍保留。 |
| 2026-08-07 | 15 | 以用户给出的横滨实机区域作为全图标准：所有 199 个 AGDT 共用 small/medium/large 分级色板，大建筑追加载入期静态冷暗侧墙与暖灰屋顶，东京/横滨/千叶/横须贺固定机位均消费同一 renderer；墙宽经三轮从 16→10→8 收口，四格接缝峰值 1.91→1.56→1.251，重新通过 `<1.5` 门。中远景提高陆海明度分离、城区边界和三重海岸对比，不用随机噪点追逐 PNG 边缘密度。V15 连续两轮 49 架压力样本无低于 60 FPS 帧；PNG 对比的中远景 edge-density 仍未毕业，PNG 继续保留。 |
| 2026-08-07 | 16 | 用户明确允许概括城市细节、以帧数为死线。新增本地 Kanto PBF 街区骨架烘焙：从 61,595 条合格本地道路按 2 km 分区的等级/长度配额确定性筛到 6,944 条，Douglas-Peucker 简化后 24,666 线段、49,332 三角、157 KiB gzip；合入既有 `road_core`，Operational 为 23 draw calls、1,384,178 三角。实测否决会形成大型有机闭环的 density 等值线。49 架同负载两轮最低 60.50/60.54 FPS、低于 60 FPS 帧为 0；PNG edge-density 仍不追求逐栋数值复刻，删除门保持关闭。 |
| 2026-08-07 | 17 | 在同一硬预算内把街区骨架提高到 9,911 条、32,316 线段，并增加合批的窄 casing：core+casing 共 129,264 三角、210 KiB gzip，Operational 仍为 23 draw calls、1,464,110 三角，loading 预热约 0.85–0.89s。东京/西岸/千叶固定机位的街区连通性明显改善，东京/千叶 edge-density 较 V16 单层版约提高 13%/28%，无规则格、黑点或有机闭环；两轮 49 架最低 60.50/60.29 FPS、低于 60 FPS 帧为 0。PNG 数值 edge-density 门仍未通过，继续保留。 |
| 2026-08-07 | 18 | 补齐整图跨战区可达性：点击战区时复用 TacticalMap `panel_in` 真暂停，以战区圆外扩 1.2 km、最多 12 格执行 detail 预热；事务期间锁住重复点击与关闭，Tab/Esc 仅登记完成后关闭。失败立即回退 Operational，恢复战斗后 streaming 仍为 false，严禁战斗帧烘焙/readback。真实 GL 暂停跨区样本预热 8 格耗时 189 ms、缓存 12 格约 109.1 MiB；两轮 49 架最低 60.17/60.28 FPS、低于 60 FPS 帧为 0。城市表现继续采用“密度质量块 + 有限真实街区骨架 + 近景分级建筑”，不逐栋复刻小楼；PNG 仍等待并排视觉毕业。 |
| 2026-08-07 | 19 | 对拍证明 V18 近景已接近金样，但东京/西岸/千叶 0.28 Operational 仍过稀、过平。将 AGOB 升级为 v2：保留 554,234 个大型建筑真实三角形，并从 203 个 AGDT 的真实轮廓离线筛选 85,403 个中型、176,738 个小型方向体块；全部以顶点色合入既有 `industrial` packet，不增加 draw call、不生成阴影/高光/随机点。包为 8.51 MiB gzip，Operational 23 draw calls、1,988,392 三角形，静态预热约 1.14–1.15s；两轮 49–50 架最低 60.06/60.46 FPS、低于 60 FPS 帧为 0。东京与西岸街区颗粒显著恢复，千叶保留真实低密度；自动 PNG edge-density 门仍未通过，因此 PNG 继续保留。 |
| 2026-08-07 | 20 | 将同一静态预算从过度精确的中景大建筑重新分配给道路结构：AGOB v2 以面积守恒方向盒概括 51,121 大型、85,403 中型、176,738 小型建筑，凹形厂房不再填满包围盒空角，包降至约 6.08 MiB；AGOR 配额提高为 35/60/2/3，得到 15,431 条、45,014 线段、300 KiB gzip，core+casing 合计 180,056 三角。Operational 从 V19 的 1,988,392 降到 1,587,192 三角，仍为 23 draw calls，loading 静态构建降至约 1.015–1.03s。最终把不透明陆地底色统一抬高 3 个 RGB 阶；东京/西岸/千叶平均像素差分别降至 14.159/16.331/10.878，edge-density 较 V19 约 +0.2%/-0.8%/+10.4%，无过大深色厂房块、黑网或 alpha 漂移。两轮 49 架最低 60.13/60.66 FPS、低于 60 FPS 帧为 0；自动 PNG edge-density 门仍未通过，PNG 继续保留。 |
| 2026-08-07 | 21 | 用户再次确认城市允许概括、帧数是死线。近景高度只使用 OSM `height` / `building:levels`，不按占地面积猜楼高：6,364 栋有证据且达到 12m/180px² 门槛的建筑生成 183,928 个静态侧墙三角，分布于 133 个 AGLW sidecar，gzip 合计 1,536,071 bytes、单瓦片最高 7,796 三角。高度墙在 loading/安全暂停解码并合入既有 `building_large_wall` packet，draw call 不增加；缺高度数据仍用 8px 低浮雕。缩放亮度三组门和四瓦片 padding 接缝门通过；两轮 49 架 Visual 压力最低 60.45/60.51 FPS、低于 60 FPS 帧为 0。自动 PNG edge-density 仍未毕业，继续保留 PNG 默认与回滚路径。 |
| 2026-08-07 | 22 | 整图资产审计发现离线烘焙留下的 203 个原始 detail JSON 仍位于 Godot `resources/`，合计 995,052,271 bytes，虽然运行时不读取却会污染扫描与导出。现完整迁入 `tmp/full_map_detail/detail_tiles_source/` 并修改准备、烘焙、打包工具；重新确定性打包得到 203 个 AGDT、154,880,760 bytes，与迁移前运行内容一致。`map_gold_slice` 新增全 203 AGDT 文件/长度/唯一 id/199 非空格/聚合字节审计，以及全 133 AGLW 解压、三角和预算审计；raw JSON 留在 `.gdignore` 的规则进入自动回归。视觉与帧数未改变，PNG 仍保留。 |
| 2026-08-07 | 23 | 整图固定机位显示 Detail 五处平均色阶比 PNG 低约 14–27 RGB。连续试验 1.12/1.40/1.25 三档静态缓存乘色：1.40 虽把横滨差值压到约 6 RGB，但四格接缝峰值升到 1.574 而否决；最终 1.25 把横滨差值从约 17 降到约 10 RGB、川崎从约 23–27 降到约 14–19，接缝峰值 1.4888，三组 zoom 亮度门全部通过。乘色只作用于已烘焙纹理 RGB，不改变 alpha/几何/draw call。两轮 49/50 架最低 60.38/60.58 FPS、低于 60 FPS 帧为 0；自动 PNG edge-density 仍未毕业，PNG 继续保留。 |
| 2026-08-07 | 24 | 补齐任意 Tab 航点的整图可达路径：候选开启时，空白落点先在 TacticalMap 真暂停内预热以航点为中心的 4.4 km 方区，锁住重复点击与关闭，成功或 Operational 回退后才下达 `command_move`；战斗主画布与普通飞行仍不启用 streaming。实际 Godot 4.7 GL 样本构建 4 格/93 ms，常驻约 109.1 MiB、峰值约 145.1 MiB；三组亮度门及接缝峰值 1.4888 继续通过。两轮 49 架压力最低 60.09/60.06 FPS、低于 60 FPS 帧为 0。城市继续采用密度质量块、有限真实街区骨架与分级地标，不为匹配 PNG edge-density 逐栋补小楼；PNG 删除门保持关闭。 |
| 2026-08-07 | 25 | 中景自审确认剩余主要差距是街区骨架过稀，而不是缺更多独立小楼。将 neighborhood 从双层 casing+core 改为单层 core，把节省的预算换成更多本地 OSM 街巷：配额 45/75/3/4，最终 18,874 条、52,633 线段、105,266 三角、363,231 bytes gzip。0.92px/alpha82 与 1.15px/alpha96 两档在实际 GL 下断续且 edge-density 低于 V24，均否决；最终锁定 1.15px、alpha150，东京/西岸/千叶可读出更连续的真实街区走向且无黑网。Operational 仍为 23 draw calls，总三角从 1,587,192 降至 1,512,402，构建约 0.94–0.97s；两轮 49/50 架最低 60.56/73.11 FPS、低于 60 FPS 帧为 0，三组亮度门与接缝 1.4846 通过。PNG edge-density 仍未毕业，默认/回滚 PNG 与删除门不变。 |
| 2026-08-07 | 26 | 进一步对拍确认 AGOB 数据足够，但深色实心体块把中景建筑退化成灰点。复用批准区域的暗边浅顶语义：small 改为接近陆地的柔和填充；136,524 个 medium/large 方向体块外扩 2.1 world px，合为单一 `building_casing` packet，再由浅屋顶覆盖。首档更亮色阶使接缝峰值刚好 1.5000 而否决；最终色阶把东京/西岸平均像素差降至 13.365/15.194，接缝 1.4983，三组亮度漂移仅 0.0086%/0.0121%/0.0095%。Operational 为 24 draw calls、1,785,450 三角，casing 273,048 三角，静态构建约 1.11s；两轮 50/49 架最低 60.47/60.80 FPS、低于 60 FPS 帧为 0。自动 PNG edge-density 仍未毕业，PNG 保留。 |
| 2026-08-07 | 27 | 首次从生产同源 `LOD_TAB`、1024² `UPDATE_ONCE` SubViewport 采集真实 Tab 快照，发现 51,121 个 large 方向体块在全图尺度退化为白色盐点。Strategic/Tab 现完全省略 AGOB，以 density mass、主干路、机场、港区和三重海岸表达远景；Tab 降为 19 draw calls、630,202 三角、580,911 顶点，一次构建约 330 ms，城市 mass alpha 提到 1.25 以区分东京/横滨与乡郊。主画布缩放亮度和 Detail 几何不变，PNG 继续保留。 |
| 2026-08-07 | 28 | 用户再次明确城市可概括、帧数为死线。两轮 120 秒矢量压力先出现 1/8 个低于 60 FPS 的系统尖峰，遂将 Operational 稳定根层从 large+medium+small 改为只保留 51,121 个 large 屋顶与 casing；中小建筑由 density mass/街区骨架概括，近景继续由 AGDT 恢复，批准区域视觉不变。Operational 从 1,785,450 降到 1,090,362 三角、顶点从 4,046,655 降到 1,961,391，预热从约 1.05s 降到 0.87–0.88s；东京平均像素差 13.313、接缝 1.4879、三组亮度漂移 0.0086%/0.0121%/0.0095%。120 秒矢量平均 321.02 FPS、4 个低帧，与 PNG 基线 278.05 FPS、3 个低帧同属极少系统尖峰，平均性能更高；自动 PNG edge-density 仍未毕业，PNG 默认/回滚与删除门保持关闭。 |
| 2026-08-07 | 30 | 在“城市允许概括、帧数是死线”下恢复批准区域的高度层次，但不恢复旧横滨逐帧 `BuildingRenderer`：仅 OSM 真实高度 `>=80m` 的少量高层突破 52px 平面上限，最高静态投影 122px；投影 bbox 参与跨瓦片分配。AGLW 增至 186,698 三角 / 1,560,988 bytes，draw call 不增加。203/203 整图图集、0 异常、接缝峰值 1.5833 RGB；120 秒压力平均 351.77 FPS、最低 58.53、低于 60 仅 1 帧。PNG 仍为默认与回滚，未获视觉毕业前禁止删除。 |
| 2026-08-07 | 31 | 自审发现只有侧墙仍比批准区域偏平；第一版高层顶面因颜色过亮、墙体过透产生悬浮碎片而否决。第二版仅给 669 栋真实 `>=80m` 高层离线耳切 7,291 个米灰顶面三角，并提高对应墙体不透明度，全部继续合入原 packet、0 新 draw call。AGLW 总计 193,989 三角 / 1,603,641 bytes；203/203 atlas、0 异常、接缝峰值 1.5866 RGB。120 秒压力平均 297.95 FPS、最低 51.61、低于 60 共 2 帧，仍优于 PNG 平均且低帧不多于 PNG。PNG 保持默认与回滚。 |
| 2026-08-07 | 32 | 对照批准区域补齐高层屋顶窄深边：同一耳切顶面先画全尺寸冷暗 casing，再画约 1.6px 内缩米灰屋顶，仍合入原 packet。669 栋高层 casing+填充 14,582 三角，AGLW 总计 201,280 三角 / 1,657,080 bytes；固定机位未形成粗黑块，203/203 atlas、0 异常、接缝峰值 1.5861 RGB。120 秒压力平均 294.93 FPS、最低 54.29、低于 60 共 2 帧。PNG 保持默认与回滚。 |
| 2026-08-07 | 33 | 跨尺度审计发现 Tab 已无逐栋盐点，但主地图全图 zoom 仍把 51,121 个 large 概括退化为黑色噪点。保持单一不透明 Operational 根，只让 building casing 与合并填充 packet 在 zoom 0.18–0.30 连续淡入；全图盐点消失、0.20 湾区只保留质量块/骨架、0.28 中景恢复建筑。三组亮度漂移 0.0118%/0.0121%/0.0095%；120 秒压力平均 288.59 FPS、最低 45.18、低于 60 共 2 帧。 |
| 2026-08-07 | 34 | 把用户反复人工审核暴露出的风险固化为整图自动风格门：`map_detail_atlas_qa` 除覆盖与接缝外，现检查全部非空格的合成平均亮度 `90–146` 与单格生产几何 `<=1,400,000` 三角，并在报告中指出最暗、最亮、最重格。门只抓漏底色、错误乘色、异常叠层和预算失控，不抹平真实城乡密度差异、不允许逐格调色。 |
| 2026-08-07 | 35 | 在亮度之外补充整图平均色偏门：全部非空格须保持 `G-R=3–12`、`B-G=-10–-1` RGB，并记录每轴极值格，防止亮度正确但整块发红、发蓝或通道错误。门仍只运行在 Visual QA，不增加生产 renderer、缓存大小、draw call 或战斗帧成本。 |
| 2026-08-07 | 36 | 完整性审计发现 loading 固定出生区确实覆盖正式出生点，但大半径战区原先把巨大外接方框交给 12 格 LRU，再按圆心截断，可能浪费预算并漏掉玩家实际抵达的近侧边缘。改为以“近侧抵达点—圆心”中点为中心、`radius×0.5+600px` 半边长预热走廊，预热与巡航复用同一抵达点；新增出生区和所有正式战区 AGDT 可达性回归，战斗期 streaming 仍关闭。 |
| 2026-08-07 | 37 | 用户实机截图否决 V36 的“完成”判断：12 格截断只保证入口点/圆心各命中一格，未保证整个视口，造成半屏 Detail 与 Operational 硬断层。正式路径改为对抵达点、路径中点、圆心三个 `zoom=0.82` 真实视口取非空瓦片并集，超过 12 格整批回退；显示端低频检查当前视口，覆盖不足时 0.18s 整层渐退。Operational 的 51,121 个 large 概括楼恢复单一静态东南侧墙 packet（102,242 三角），任何回退区仍有伪立体层次。全战区八向覆盖回归、真实 GL 固定机位和同机 PNG/矢量 120 秒对照通过；PNG 继续保留。 |
| 2026-08-07 | 38 | 完成声明复审发现两个证据盲区：atlas 只遍历 manifest 的 203/256 格，未证明 53 个缺席格没有漏掉陆地；旧 PNG 固定机位没有实例化正式 `BuildingRenderer`，不能代表游戏内旧大楼效果。新增全 256 格缺席/空格陆地采样审计，并将旧横滨伪 3D renderer 纳入 PNG 同位截图与差异报告。两项通过前不得宣称整图完成。 |
| 2026-08-07 | 38 | V38 复审通过：`map_gold_slice` 对 256 格严格采样，53 个缺席格无陆地命中，两个海岸边缘空格精确锁定；atlas 256/256 分类、203 注册、0 失败、接缝峰值 1.5793 RGB。PNG 参考现包含旧 189 街区 `BuildingRenderer`，确认旧版是横滨局部动态大块体，新版是全图静态低浮雕与近景真实高度墙体。结构与性能门通过，但自动 PNG edge-density 仍失败，因此仍不得删除 PNG。 |
| 2026-08-07 | 39 | 用户要求停止堆砌细节，转为三档颜色与边缘阴影精修：减少 Strategic/Tab density mass、Operational 城市实心块与 Detail 冷黑阴影的面积感；只修改 palette、alpha、既有海岸/建筑 packet 宽度和偏移，不新增地图内容或 draw call。固定机位低频色块标准差明显下降，金样、全图 atlas、真实 GL 截图和 zoom 稳定性通过；几何规模与 V38 一致，120 秒同机 Visual 矢量 112.32 FPS、PNG 105.12 FPS，排除 >15 FPS 回退。V39 调色目标完成；整项仍因 PNG edge-density 毕业门未通过而保持 in-progress，PNG 不删除。 |
| 2026-08-07 | 40 | 用户否决 V39 作战距离后完成两轮自审：城市 mass `1→0.28`，large 屋顶最高仅 `0.56`，低浮雕边缘最高 `0.72`；Detail `0.50–0.98` smoothstep 后取 `1.75` 次幂，0.65 仅约 7.8%、0.80 约 51%，消除中景大色块和拉近后的细节墙。六档矩阵之外，按正式 `×1.10` 滚轮目标补采 8 档，最大目标间亮度总变化 2.1067%、最大 edge-density 正增幅 3.4805%；再按 0.02 zoom 扫描完整插值区间，最大亮度漂移 0.9654%、无 edge-density 正向尖峰，证明相机 lerp 过程中没有隐藏细节墙。Operational 仍为 25 draw calls / 1,192,604 三角，203/203 atlas 与金样通过；120 秒同机矢量 116.74 FPS、PNG 116.73 FPS，最差帧 40.00/32.39，低于 60 FPS 为 11/8。纯海域 0 Detail 格成功保持 Operational；PNG 默认、回滚与删除门不变。 |
| 2026-08-07 | 41 | 用户实机指出候选在最大战斗档错误隐藏重要假 3D 大楼，且 Operational 仍像单一巨大灰块。纠正规则与实现：189 组横滨 `BuildingRenderer` 改为 PNG/矢量共享的游戏性地标与阻挡层，不再随底图 A/B 隐藏；普通城市仍保持静态合批。重分既有 density/landuse 顶点色，减弱统一城市覆盖，工业/停机坪并入既有 mass packet，并略提真实街区骨架对比。真实 GL 固定机位与全部缩放亮度/结构门通过；Operational 为 24 draw calls / 1,192,604 三角。120 秒约 49 架同负载中矢量 111.81 FPS、最低 30.00、低于 60 共 8 帧；PNG 98.67 FPS、最低 30.20、低于 60 共 654 帧，两侧均加载 189 组共享大楼。PNG 默认、回滚与删除门不变。 |
| 2026-08-07 | 42 | 用户以红圈指出暖棕 landuse 越出陆地底盘，并以纸模地形/总平面参考要求低频块状层次。新增规则：工业、停机坪与场景块必须按视觉 water 差集并恢复 land inlay；从既有城市多边形确定性生成少量“暗边—底面—内缩浅面”静态台阶，使用灰、灰绿、灰褐三类低饱和色。最多新增 1 packet，禁止新增道路、普通建筑、噪点、逐帧随机或真实地形重建。完成状态等待固定机位、遮罩与性能门。 |
| 2026-08-07 | 43 | 将重要高楼提升为不可被普通 LOD 删除的 Operational 游戏地标：从本地 OSM 生成 669 栋真实 `>=80m` 高层的独立静态包（29,688 三角 / 227,154 bytes gzip），全部战斗 zoom 保持 alpha 1；横滨 189 组玩法 `BuildingRenderer` 继续由 PNG/矢量共享。低密区域最终使用 360 块不规则 6–8 边、非同心的灰绿/冷灰/灰褐纸模台地，离线按视觉 water 边界精确拒绝相交，三类水面命中均为 0。Operational 最终 26 draw calls / 1,240,237 三角，首次预热约 1.42–1.47s；六档、正式滚轮与连续扫频视觉门通过。120 秒同负载 PNG/矢量为 303.97/299.88 FPS，差 -4.09 FPS，低于 60 为 1/3 帧，未触发性能回退。候选明显加强了颜色分区与常驻假 3D 地标，但仍须用户整图裁决，PNG 默认、回滚与删除门保持不变。 |
| 2026-08-08 | 44 | 用户以纸板总平面参考否决 V43 的花绿功能色与均匀拼布感。density/context/relief 保留分类数据但统一为暖灰纸板色相，以明度、纸面叠层和中性阴影区分；三个 density 锚点满足暖纸色族与 `0.02..0.08` 距离门。台地从 360 收至 220 块，宏观采样 1.1k world px、单块半径约 320–700px，Operational `terrain_context` 降至 14,496 三角，总量 26 draw calls / 1,236,202 三角，水面命中 0，首次结构预热 1,327ms。真实 GL 全固定机位、六档/滚轮/连续扫频全部通过；120 秒 PNG/矢量为 117.91/119.33 FPS、低帧 3/1，战斗结果不同故只裁定无性能回退。PNG 默认、回滚与删除门不变。 |
| 2026-08-07 | 29 | 固定机位不足以证明整图完成，新增独立 `map_detail_atlas_qa` Visual bench：逐格复用生产 DirectRenderer 与 3072²→1536² 缓存路径，将 Detail 缩略层叠到世界对齐的 Operational 底图。56.575 秒处理清单全部 203 格，其中 199 非空、4 预期空、真实失败 0；全图 30 条横纵边界平均额外跳变 0.396 RGB、峰值 1.5805 RGB，通过 `<3` 门。atlas 肉眼无黑白坏块、规则格或明显断层；它证明全图数据/样式/接缝一致，不改变 PNG edge-density 尚未毕业与 PNG 保留裁定。 |
| 2026-08-08 | 45 | 用户最终裁定本计划无法达到预期视觉效果，正式东京湾与 Tab 地图保留 8704×8704 PNG + shader。纯矢量候选从生产迁移计划降为冻结的 debug 研究档案，状态改为 `superseded`；本轮不删 PNG、不删候选资产、不改生产默认，未来重启须另立 approved spec 并重新通过整图主观视觉门。 |
| 2026-08-22 | 46 | 同步后续栅格方案毕业：正式底图从整图 PNG 改为同源 lossless WebP 瓦片，不改变本纯矢量候选的 superseded 身份；`Shift+F10` 仍仅作冻结研究入口。 |
