# 地图流水线（Map Pipeline）

AGL 生存模式使用**真实地图底图 + 程序化矢量数据 + 手画覆盖层**的三层混合渲染。本文档讲清楚从零建新地图的完整流程、渲染架构、以及判定逻辑。

---

## 0. 地图视觉生产与审核协议（强制）

地图制作者或 agent 必须先自行完成多轮视觉迭代，再请求用户审核。**用户负责美术方向与最终毕业裁决，不负责逐轮调色、找碎边或替 agent 做 QA。** 本协议适用于新地图、官方图矢量化、地图编辑器样式、主地图与 Tab 地图预览。

### 0.1 默认自主迭代循环

1. **建立基线**：固定同一 `MapDocument`、style、视野、分辨率与 zoom，生成参考版、候选版和同位擦除对比；不得拿不同机位或缩小缩略图比较。
2. **分层诊断**：逐项检查 sea/shallow、land/terrain、urban、coast、roads、airport、buildings、grain、vignette；先判断是数据缺层、拓扑错误、样式错误还是 LOD 错误，再改图。
3. **内部迭代至少 3 轮**：每轮必须有明确假设、改动和复测，禁止只改版本号。已有成熟 style profile 且首轮全部过门时可以提前结束；否则未完成 3 轮不得要求用户审核。
4. **连续最多 8 轮**：两轮没有可测改善，或第 8 轮仍过不了客观门时，停止盲调并报告真正阻塞项（例如缺 residential/service 道路、建筑覆盖或 renderer 能力），不得把八张半成品依次丢给用户。
5. **代理自审**：在 100% 与 200% 尺寸检查固定机位；全图、湾区、港区/机场细节、Tab 四档均过门后，才整理 1 个推荐稿；只有存在真正不同的美术方向时才附最多 2 个备选。
6. **用户里程碑审核**：用户只在方向选择、候选里程碑和 PNG 退役毕业门拍板。收到反馈后必须转写成 style/profile/验收规则，后续地图继承，不能让用户在下一张图重新指出同一种问题。

### 0.2 客观预检门

- **拓扑**：海岸描边只能从最终闭合 land/water 面派生；不得有悬空 coastline、碎岛、碎水洞、港池被误填或道路落在无承托海面。
- **局部色准**：按 sea core、land、urban、port land、airport 分区测 mean/stddev；参考图存在时每通道 mean 差目标 `<= 4 RGB`。整帧平均值只能做烟雾检查，不能让海陆偏差互相抵消。
- **信息密度**：按 LOD 统计道路长度/屏幕面积、建筑或街区覆盖、海岸边缘密度；不得用随机噪声伪装缺失的住宅道路、建筑或地形数据。
- **层次**：主路必须有 casing/core；海岸必须有窄边与浅海层；Strategic/Operational/Detail/Tab 各自只显示该档应有信息，连续 zoom 不跳宽、不闪层。
- **清晰度**：交付预览使用原生画幅或可放大的同位擦除，不使用把细节压没的低清三栏图作为主要审核材料。
- **性能结构**：所有内部候选也遵守静态 canvas、批量三角数组和零持续 `queue_redraw`；不能先做一套注定无法生产化的逐 feature/每帧原型再让用户选。
- **LOD 权威**：截图与性能报告必须从 renderer `debug_state.current_lod/target_lod` 读取实际档位，禁止仅按预设 zoom 命名；本方案的 `0.35` 与主要战斗缩放 `0.26` 都是 Detail，真实 Operational 固定门为 `0.18`。
- **缓存纯净**：同名瓦片被重建后，必须重导入或清除对应可再生 `.import` 旁车，再跑三地图 Operational 3×3 同位门；任何新旧分辨率混载、局部错位或颜色块都视为构建失败，不得通过整帧均值掩盖。

### 0.3 允许提前打断用户的情况

仅限：现有资料无法判断的美术方向分叉；缺少关键数据或授权；继续迭代会扩大到用户未授权的生产改造；或客观门与用户明确目标互相冲突。普通色偏、道路宽度、海岸柔化、碎边、细节密度和预览清晰度均属于 agent 应自行解决的问题。

### 0.4 产物与留存

- 所有工作图、参数 sweep、diff 和临时脚本写入 `tmp/<map>/...` 或项目外可视化目录，禁止进入 Godot 扫描目录。
- 默认只保留基线、最近 2 个完整内部 run 和当前里程碑；删除前必须确认目标位于 `tmp/`，不得碰生产资产。
- Notion 只上传用户需要查看的里程碑候选与最终裁决，不上传每轮 scratch 图；里程碑图片必须标注参考/候选、LOD、版本和仍未过门项。
- 每个里程碑至少包含三地图同 zoom 九宫格、两段阈值各 25%/50%/75% 过渡帧、主图/Tab 往返与真实 LOD 性能对照；只要任一自动门失败，agent 继续内部定位和复跑，不把失败稿交给用户逐项找错。

### 0.5 当前 lossless WebP 分档 A/B（approved，尚未毕业）

- 当前迁移路线是 [raster-basemap-streaming.md](../specs/systems/raster-basemap-streaming.md)，不是继续完善纯矢量 V44。8704×8704 PNG 继续作为默认、视觉权威和回滚源；只有三图主地图、Tab 图、连续缩放、内存和 Sentinel+Lv5 性能全部过门且用户最终确认后，才允许同时移除大型地图 PNG。
- 东京湾、沙漠铁路和海洋群岛从各自正式 PNG 离线切成**原始 RGB 像素完全无损**的 WebP 瓦片，不把 tint、grain、暗角或地图内容预烘进公共 shader。三个 level 分别为 Strategic 东京 1536²、沙漠/海洋 1504² 单图，Operational 7680² 8×8，Detail 8704² 9×9；瓦片内容 1024px，四周 16px gutter。重新解码后像素 mismatch 为 0。Operational 必须以 `zoom=0.18` 验收；主要战斗缩放 `0.26` 单列为 Battle 并必须落入 Detail，不能把两者混名。
- V36 三图地图金字塔体积实测为东京湾 43.826435 MiB、沙漠 21.605158 MiB、海洋 2.548243 MiB，共 67.979836 MiB；再加跨图共享 `64×64` L8 蓝噪声 `4,228 B` 后总计 67.983868 MiB。Strategic 按图分配为东京湾 1536²、沙漠/海洋 1504²；运行时常驻 Strategic + 当前视野最多 12 格，硬上限 16 格，不再同时解码 8704² 全图。
- LOD 使用带迟滞的三档状态机：Strategic→Operational 名义阈值 `0.10`、Operational→Strategic `<0.08`、Operational→Detail `0.24`、Detail→Operational `<0.20`；若目标可见集超过 12 格则继续保留父层。1920×1080 逻辑视口中，7680 Operational 在约 `0.1066` 才降至 12 格，因此固定 QA 从 `0.107` 起验收升档。整层切换用 0.40s 静态覆盖淡入：目标瓦片层临时置顶从 `0→1`，旧层保持不透明直到结束；降至 Strategic 时才单独淡出旧瓦片层，禁止双层同时淡化露出底色。60 FPS 正弦 alpha 单帧理论上界为 `π/(2×0.40×60)≈0.06545≤0.07`。每 tick 最多请求 4 格、绑定 2 格；不在 `_draw` 中扫描，不每帧重绘地图。每档先取全部可见格，再用 12 格总额的剩余位置做邻接预取；只有可见格完整才升档，禁止截断可见区。大幅滚轮跳档若前后集合会越过 16 格，先以 Strategic 桥接。Visual QA 会在放大/缩小四个方向各抓取 25%/50%/75% 三帧，并断言 alpha、z 顺序、最终像素哈希、亮度/梯度连续性、可见格完整性和 resident 硬门；只改变节点 alpha 但 shader 未消费 `COLOR/modulate` 会直接失败。
- 过渡专用压力场景 `map_raster_transition_stress` 在 Sentinel+52 机下每 `0.8s` 跨一次 Operational/Detail，同时覆盖 Strategic 桥接；V30 12 秒实测平均 `317.78 FPS`、最坏帧 `87.91 FPS`、0 帧低于 60。该场景只在 bench 生效，不给正式 `_process` 增加常驻工作。
- `basemap_streamed.gdshader` 复用正式 PNG 的 saturation/brightness/contrast/tint/Sobel 风格；grain 采样确定性 `shared_blue_noise_64.png`，使用全图 `map_uv×64` 保持三档/瓦片同相位，线性 mip 自动按 footprint 取样，不读 `TIME`、不在 fragment 计算 hash。边缘从当前采样动态求 Sobel，避免 gutter 把轮廓重复烘进内容；Strategic 与 Detail 8704 分别用 `1.15/1.20`，Operational 7680 则按图使用东京/沙漠 `1.17`、海洋 `1.15`。`luma_scale_by_lod` 只在 Sprite 创建时一次性写 `self_modulate`：东京 `0.9895/1.0016/1.0`、沙漠 `1.020/1.0/1.0`、海洋全档 `1.0`；海洋 Strategic `1.003` 因低频结构与平坦区色差恶化而否决。静止与缩放时均不更新 shader。
- debug build 用 `Shift+F8` 同步切换主地图与 Tab 图的 PNG/streamed A/B；`Shift+F10` 仍只进入冻结纯矢量研究。`--raster-basemap-preview` 可让 Visual bench 从 loading 直接走候选；候选初始化成功后不加载 legacy 全图 PNG，失败则原子回滚。自动门还会对三图执行一次实际 `PNG→streamed→PNG→streamed` 主图往返，并实例化正式 TacticalMap 验证 Tab 关闭/重开；回滚截图相对初始 PNG 的平均亮度差绝对值最大 `0.000007`。
- Tab 图直接消费同图 Strategic 原始纹理（东京 1536²、沙漠/海洋 1504²）并沿用正式固定中性乘色，不再重复套主地图 shader或创建第二份 SubViewport 快照；战区、单位、航点和 CRT 层仍走既有动态路径。三张内置图共享 manifest schema；任意外部 UGC 仍保持 vector-only，不能误读某张官方图的 raster 内容。
- `map_raster_visual_qa` 在真实 Godot 4.7.1 GL Compatibility 中对拍三图 full/Operational `0.18`/主要战斗 `0.26`/Detail/实际 680² Tab、Operational 3×3 网格、回滚帧，并让正式 PNG 与候选执行相同 24 点 zoom sweep。V35 东京湾 Operational/主要战斗低通 RGB MAE 为 `0.002586/0.000087`；36 个强结构机位最差道路/海岸与大轮廓 F1 为 `0.955073/0.968759`。候选最大相邻亮度变化 `0.3947%`，正式 PNG 为 `0.1232%`，候选减 PNG 的额外残差 `0.2715% ≤0.5%`；四向 25%/50%/75% 过渡最大相邻亮度变化 `0.000388`、低通梯度相对变化 `9.1622%`。12 格 resident、16 格硬门均通过。东京湾 Strategic 主动消除旧 8704² 无 mip 极缩时的黑色混叠。
- 全图/Tab 另执行孤立暗点门：亮表面上比 3×3 中值暗 `>0.07` 的单像素密度，候选不得超过同位 PNG `1.05×`。1520 相对旧 PNG 的减少率为东京湾 `56.0%/96.4%`、沙漠 `82.6%/100%`、海洋 `33.4%/96.2%`；地图制作规则要求保留低频结构、主路和海岸，但禁止为了追逐 RGB MAE 重新引入旧全图缩放黑点。
- 每次里程碑还须从三图九宫格自动选 RGB MAE 最大区域，输出原尺寸正式 PNG / 候选 / 低频差异放大。东京全档统一 `edge_gain=1.20` 已因 10/11 个中景机位误差上升且亮度跳变恶化到 `0.7910%` 而否决；后续 `1.10/1.15/1.17` 同帧消融证明 Strategic 保持 `1.15` 最稳，1520 东京实机再证明其 Operational 需 `1.17` 才能收拢升档端点；海洋 V8 的同位消融则证明 Operational `1.15` 更接近母版。8192² Operational 因体积增加且 RGB 误差恶化约 `18.2%` 淘汰；7680² `1.18` 虽离线近似更锐，真机却使东京低通误差与 LOD 连续性变差，也已回滚。V9 又否决 Strategic `1.20`（低通梯度 `12.8254% >10%`），改用不增加边缘的一次性 `0.9895` 低频乘色；原尺寸 Detail 仍使用 `1.20`，不得把任一档补偿外推成全档统一值。
- Strategic 先做统一 1024/1280/1344/1408/1472/1520/1536 消融，再于 V36 改为按图分配：东京湾 1536²、沙漠/海洋 1504²，以 `67.979836 MiB` 保持在 68 MiB 内。真实 Godot full/Tab 低通 RGB MAE 为东京 `0.005715/0.001994`、沙漠 `0.001059/0.000499`、海洋 `0.000563/0.000184`；24 点 zoom 最大亮度步进 `0.003885`，没有放宽既有门限。
- Strategic 制作禁忌：不得为了追逐正式 PNG 直接缩小时产生的黑点/混叠，默认追加 Sobel 或 Unsharp。东京 V37 已实测 Sobel 1.20、Unsharp 10% 均使 full 或 zoom 退化；Unsharp 5% 的 Tab 改善仅 `0.000001` 且 full 仍变差。V38 的 `8704→4096→1536` 双阶段 Lanczos 虽改善离线 mip 代理与真实 full，却让 Tab `0.001994→0.002004` 且肉眼无可辨收益，同样否决。新地图必须从原图单阶段 Lanczos 起步，优先按图分配分辨率；锐化或多阶段缩小只有在真实 Godot 的 full 与 Tab **同时产生可见改善**、孤立暗点不增加且 zoom/四向过渡全过时才可晋升，离线代理分数不得单独晋升。
- Godot capture 完成后必须运行 `scripts/tools/audit_raster_basemap_captures.py`。它不会替代引擎渲染，而是对三图 full/Operational/主要战斗/Detail/玩法地标/Tab 与 27 个 Operational 网格共 45 组成对机位执行可失败的平均亮度、逐通道平均 RGB 色偏 `≤0.004`、1.5 px 低通结构、8×8 平坦区、full/Tab 孤立暗点、候选与正式 PNG 同步 zoom 连续性及 `≤0.5%` 额外残差、transition 三帧哈希/亮度/梯度/覆盖及 16 格驻留门；同一工具还对正式 PNG 的 3 px 梯度 `p99≥0.007` 的有效机位执行道路/海岸结构（3 px 低通、92 百分位、3 px 容差）与大轮廓（5 px 低通、94 百分位、4 px 容差）F1，两档均须 `≥0.80`，并要求三图正式 PNG 与候选在主要战斗同机位间隔 `0.5s` 的双帧 SHA-256 相同、最大逐通道像素差 `0`。纯平海和不可见微纹理不强行计分。固定 runner 还会逐图恢复/注入真实 MapDocument 并断言东京湾/沙漠/海洋 `189/15/16` 组建筑缓存。当前门限写在脚本常量并由 `raster-basemap-streaming` §5 授权。
- 三图还必须分别运行 `map_preview_*` / `map_raster_*` Visual bench，在相同确定性天气种子下抓取六张完整 Survivor viewport，再由 `scripts/tools/audit_raster_survivor_composites.py` 执行亮度、1.5 px 低通 RGB、平坦区逐通道色准与低通结构相关硬门。底图专项门通过但完整合成门失败时，不得晋升 profile。V39 在 V38 回退后的当前 V36 复核值为东京/沙漠/海洋低通 RGB MAE `0.000290/0.000753/0.000597`、低通相关 `0.995847/0.989240/0.994665`，六张正式 Survivor viewport 全过且肉眼并排无 streamed 专属层次退化。
- 三张内置地图还必须分别从真实 `survivor_mode.tscn` 抓取 PNG/候选完整 viewport，覆盖天气、玩家、HUD、机场、建筑与底图共同合成。抓图场景向 WeatherSystem 注入同一固定种子；禁止用两次随机云形的差异判断地图明暗或色偏。正式游戏不传该种子，继续随机天气。
- 旧三轮把 `zoom=0.35` 错标为 Operational，实际已进入 Detail，只保留为历史诊断。共享蓝噪声最终保留 `0.014`；受控 `0.016` 因 Detail 连续两轮各有 3 帧 `<60` 而淘汰。V36 最新 52 机三档循环为 `144.82 FPS`、最差帧 `138.81 FPS`、0 帧 `<60`；三图完整 Visual 生存场景最低单帧 `325.78/303.98/258.46 FPS`。Visual QA 按渲染器实际 alpha 逐帧抓四向过渡，不使用固定毫秒等待；会话驻留峰值 `14/16`。客观门通过，仍不代替用户最终视觉确认。

### 0.6 游戏内 V44 A/B 入口（冻结研究）

- **最终生产裁决（用户定 2026-08-08）**：V44 整图视觉未达到预期，正式东京湾主地图与 Tab 地图保留 8704×8704 `tokyo_bay_bg.png` + shader。不得删除、覆盖、降质或把该 PNG 标成过渡资产。
- debug build 中的 `Shift+F10` A/B、候选 renderer、矢量包与 QA 仅冻结作研究/回归材料；它们不再是当前生产迁移路径。未来重启须新建 approved spec 并重新经过整图主观视觉验收。
- 中远景数据是 `tokyo_bay_vector_preview.json` + `tokyo_bay_operational_density.agod.gz` + `tokyo_bay_operational_buildings.agob.gz` + `tokyo_bay_operational_roads.agor.gz`；道路包是从本地 Kanto PBF 按 2 km 分区配额简化出的 18,874 条真实街区骨架，不是全量住宅路。neighborhood 只提交单层低对比 core；Operational 仅保留 large 概括体块与单一 casing。近景由 `tokyo_bay_detail_tiles_full.json` 索引 199 个 AGDT gzip 矢量包；AGLW 只消费 OSM `height` / `building:levels`，普通楼不超过 52px 投影，真实 `>=80m` 地标按分段曲线放宽到最多 122px，并用投影 bbox 跨瓦片分配。所有侧墙仍合入原 packet，缺高度建筑继续低浮雕。运行时不读取 `tmp/`，截图、diff 与缓存纹理都不得作为地图内容资产。
- 203 个原始 detail JSON 是约 995 MB 的构建中间产物，只能放在 `tmp/full_map_detail/detail_tiles_source/`；`prepare_tokyo_bay_detail_grid.py`、`bake_tokyo_bay_full_detail.py` 和 `pack_tokyo_bay_detail_tiles.py` 必须维持该边界。`resources/maps/` 只放 AGDT/AGLW 与 manifest，禁止把 raw JSON 为了方便回流到 Godot 扫描目录。
- Detail 缓存 Sprite 统一使用 `Color(1.25, 1.25, 1.24)` 静态乘色，补偿透明细节在最终主画布的系统性压暗；所有瓦片只能共用一个值。1.40 倍因四格接缝峰值 1.574 已否决，当前 1.25 倍峰值 1.4888；不得用逐格调色掩盖数据或接缝问题。
- `building_preloader` 在正式局载入阶段预热 Operational 主图、Tab packet definitions 与出生区 detail；主场景只绑定缓存数组/静态纹理，首次开关不得现场做完整全图三角化。帧数是硬门：战斗中禁止 SubViewport 烘焙/GPU readback，未驻留区域保持 Operational 概括层；detail 只能在 loading 或安全暂停显式预热。12 格 LRU 上限约 110 MiB。Boss Debug 与 UGC 跳过东京湾预热；地图 Visual bench 显式走真实 GL 后端。
- 候选开启后点击战区，`SurvivorMode` 只在 TacticalMap `panel_in` 已建立的真暂停里预热战区圆外扩 1.2 km、最多 12 格；在 Tab 空白处设置任意航点时，同样必须先预热以航点为中心的 4.4 km 方区，再下达 `command_move`。两条事务都锁住重复点击与关闭，Tab/Esc 只登记完成后关闭。失败直接使用 Operational，不阻塞任务或巡航；恢复战斗后 streaming 必须仍为 false。直接在战斗主画布移动或飞入未驻留区不得触发烘焙。
- v6 的整图 LOD alpha 淡入已被实机否决：它会让半透明图层重复合成并造成 zoom 时整体明暗漂移。共享 base + feature 级连续淡化完成前，主图固定一个不透明 Operational 根，不随滚轮切整图。
- v6 的规则道路密度格与 V16 试验的建筑密度等值线均被实机否决：前者是假结构，后者形成大型有机闭环。Strategic/Tab 不提交逐栋建筑；Operational 保留真实主次路、分区限额街区骨架、连续 density mass、51,121 个 large 概括体块、220 块不规则暖灰纸模台地与 669 栋常驻真实高层。最终硬预算为 1,300,000 三角 / 26 draw calls；不追求 PNG 的逐像素 edge-density。
- 整图完成不得只凭固定机位：运行 `bench/run.cmd map_detail_atlas_qa 300 480 Shadow Visual`，逐格复用生产 Detail renderer/cache 并输出 `tmp/map_visual_qa/detail_atlas/`。东京湾基准必须为 203/203 格处理、199 非空、4 预期空、真实失败 0；30 条世界网格边界的额外 RGB 跳变峰值 `<3`。该 atlas 是 QA 产物，不得被游戏加载。
- V34 atlas 还必须自动检查全部非空格的合成平均亮度 `90–146` 与单格生产几何 `<=1,400,000` 三角，并报告最暗、最亮、最重格；这是漏底色、错误乘色、异常叠层和单格预算失控门，不得用逐格调色抹平城乡差异。
- V35 atlas 同时检查每个非空格 `G-R=3–12`、`B-G=-10–-1` RGB，阻断亮度正确但整块发红、发蓝或通道错误；真实城乡/水陆覆盖差异继续保留。
- V36 战区预热不再用整个战区圆的巨大外接方框：以玩家近侧抵达点到圆心的中点为中心，按 `radius×0.5+600px` 生成走廊，并把抵达点和圆心作为 12 格截断的优先点。loading 出生区必须包含 `MapBoundary.get_player_start()`；战斗期 streaming 仍关闭。
- V37 禁止把超过 12 格的预热集合截断后继续显示：抵达点、路径中点、圆心各按 1600×900、zoom 0.82 的真实视口求非空瓦片并集；装不下就完整回退 Operational。Detail 显示端低频检查当前视口，缺任一非空格时整层 0.18 秒渐退，不再暴露水平/垂直瓦片边。
- Operational 的 large 概括楼保留单一东南偏移冷暗侧墙；V44 另有 669 栋真实 `>=80m` 高层常驻 `landmark` packet 与 220 块非同心暖灰纸模台地。最终总量 26 draw calls / 1,236,202 三角；中小楼仍不回填，战斗期仍无地图 bake/readback/redraw。
- V38 将审计范围从 manifest 的 203 格扩展为完整 16×16=256 格：53 个省略格必须全部证明为严格海面/界外；4 个注册空格必须显式分类。`detail_10_06` 与 `detail_14_04` 主体为海面，只有极小严格陆地/桥梁擦边，且本地 PBF 没有分配支持图元，固定 0.8 zoom PNG/vector 对拍后作为精确锁定的海岸边缘例外；例外集合发生增减即回归失败。
- PNG 参考截图必须实例化正式 `BuildingRenderer` 的 189 个横滨相机相关玩法街区，不能只截 PNG 底图；候选也必须保留同一共享层。除此之外，Operational 是 51,121 个全图静态 large 体块与 669 栋常驻真实高层，Detail 另消费 6,371 个有 OSM 高度的建筑墙体；职责差异必须写入截图 manifest。
- Tab 消费同一 renderer 的 1024×1024 `SubViewport.UPDATE_ONCE` 快照，动态战区、单位与 CRT 层仍沿用原 10Hz 路径。
- 横滨 `BuildingRenderer` 是玩法建筑/阻挡层，候选与 PNG 两侧都必须保持可见；它与全图底图建筑 packet 职责不同，允许像正式 PNG 栈一样叠加。
- detail 纹理的 4 px 外挤只允许被采样，不得扩张 Sprite 世界矩形；相邻格重复叠加会在接缝两侧形成暗线。
- 当前入口只用于冻结研究的诊断与历史回归，不是 PNG 退役授权。数据或任一端初始化失败会同时回滚到 PNG；UGC 与 Boss Debug 不暴露该开关，bench 只用专用 map 场景进入。

---

## 1. 架构总览

```
┌──────────────────────────────────────────────────┐
│  scenes/survivor_mode.tscn                       │
│  ├── MapBoundary          游戏世界边界 (±7500px) │
│  ├── MapFeatureRenderer   主地图渲染器            │
│  │    ├── Sprite2D + Shader  默认整图 PNG        │
│  │    ├── RasterBasemapRenderer  可选分档瓦片    │
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
- `resources/maps/tokyo_bay_bg.png` — 当前正式东京湾底图（8704×8704，36,075,000 bytes；生产资产，禁止被转换器覆盖）
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
- `grain_texture` / `grain_strength` / `grain_repeat` — 正式 PNG 与候选共享的蓝噪声世界颗粒；两条路径使用统一全图坐标，禁止 `TIME`、按 LOD/瓦片改变相位或恢复程序 hash

**当前满意的默认**（`map_feature_renderer.gd`）：
```gdscript
basemap_tint: Color(0.78, 0.82, 0.80, 1.0)  # 中性冷灰，不染色
basemap_saturation: 0.40
basemap_brightness: 0.70
basemap_contrast: 1.25
basemap_edge_strength: 1.2
basemap_noise: 0.014
basemap_grain_repeat: 64.0
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
| 底图 PNG | 8704×8704 px / 36,075,000 bytes | 当前正式生产资产；主地图 + Tab 保留 |
| Lossless WebP 候选 | 三图金字塔 67.979836 MiB；含共享蓝噪声 67.983868 MiB | Strategic 东京 1536²、沙漠/海洋 1504² / Operational 7680² / Detail 8704²；仍未获 PNG 退役授权 |
| 候选 GPU 纹理常驻 | 稳定约 59.87 MiB / 硬上限约 76.89 MiB | Strategic + 12 格 LRU + 约 5.3 KiB 蓝噪声 mip，绝不常驻完整 8704² |
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
- `scripts/tools/bake_preview_basemaps.py` — 图2 Mount Whaleback / 图3 Ironbottom Sound 各 17×17 张 zoom 13 `@2x` 瓦片 → 两组 8704² PNG + 元数据
- `scripts/tools/refine_preview_basemaps.py` — 图2低对比沙漠地貌来源层 + 坐标稳定道路底图 → v2；图3清除主岛南部保护区/土地覆盖直角色块 → v2
- `scripts/tools/remove_admin_boundaries.py` — 三图母版进入金字塔前的强制离线步骤：只识别与 CARTO `#e1c5c7` 行政边界核心连通的窄像素带并确定性修补；默认写 `tmp/admin-boundary-cleanup/`，显式 `--write-runtime` 才原子替换母图。道路、铁路、河道、海岸与建筑不得进入 mask。
- `scripts/tools/raster_basemap_preview.py` — 三图正式 PNG/profile 同位预览与内部调色诊断；所有图片输出固定写入 `tmp/raster_basemap_preview/`
- `scripts/tools/build_lossless_basemap_pyramid.py` — 三图原始 RGB → Strategic/Operational/Detail lossless WebP + gutter/复解码/父子均值 QA；默认输出 `tmp/raster_basemap_tiles/`。`--operational-only --base-root ... --operational-size 7680` 与 `--strategic-only --base-root ... --strategic-size 1520` 可复制已验证金字塔并只重建单档，避免重复编码 Detail；最终产物仍须先在 `tmp/` 过门再晋升 runtime
- `scripts/tools/build_shared_blue_noise.py` — 确定性生成三图共用的 `64×64` L8 蓝噪声；只承载颗粒分布，输出前校验均值、低频能量与 SHA-256，默认写入 `tmp/`
- 三图 manifest 的 `style_profile.grain_repeat` 只在 Sprite/瓦片材质创建时写入；当前锁定 `64`。V33 真机消融证明 `48/32` 会让三图低频误差单调上升并把最差道路/海岸结构 F1 降到 `0.794665/0.766250`，不得用粗化 shader 颗粒伪造地图层次。
- 正式整图 PNG 的 `basemap_tacview.gdshader` 与 streamed shader 共用 `shared_blue_noise_64.png`、强度 `0.014`、重复 `64` 和全图归一化相位；主地图 shader 禁止 `TIME`、程序 hash 或三角函数动态颗粒。V34 统一后 42 组平均 RGB/低通误差下降到 `0.002083/0.001068`，三图两路径 0.5s 时间双帧均零像素变化。
- `scripts/tools/audit_raster_basemap_captures.py` — 消费 `map_raster_visual_qa` 的三图真实 Godot PNG/streamed 同位截图，输出 `raster_visual_audit.json` 并在色调、低频结构、局部平坦区、LOD 连续性、transition 或驻留超门时返回非零
- `scripts/tools/audit_raster_survivor_composites.py` — 消费三图 PNG/streamed Visual bench 的六张完整 Survivor viewport，在合成亮度、低频色差、平坦区色准或低频结构相关超门时返回非零
- `resources/maps/source/` — 带 `.gdignore` 的离线地貌来源层与生成 prompt；不参与 Godot 导入或运行时打包
- `scripts/tools/build_vector_preview_data.py` — 已审中远景研究矢量 → 自包含运行时预览数据
- `scripts/tools/bake_yokohama_gold_slice.py` — Overpass OSM → 横滨 4×4 km 纯矢量金样
- `scripts/tools/bake_tokyo_bay_full_detail.py` — Kanto PBF → 全东京湾 2 km detail JSON 网格
- `scripts/tools/pack_tokyo_bay_detail_tiles.py` — `tmp/` detail JSON → 量化 AGDT gzip 运行时包；manifest 保留 build-only `json_source_path`
- `scripts/tools/build_tokyo_bay_operational_density.py` — 全图 OSM 城市/植被/工业密度场
- `scripts/tools/pack_tokyo_bay_operational_buildings.py` — 全图大中小建筑面积守恒方向体块 packet
- `scripts/tools/bake_tokyo_bay_operational_roads.py` — 本地 Kanto PBF → 2 km 分区限额、折线简化的中景街区骨架
- `scripts/tools/bake_tokyo_bay_operational_landmarks.py` — 本地 Kanto PBF → 669 栋真实 `>=80m` 高层的常驻 Operational 假 3D 包
- `scripts/tools/bake_tokyo_bay_context_relief.py` — density + 视觉水环 → 220 块不规则、非同心暖灰纸模台地；离线拒绝跨水边
- `scripts/tools/map_visual_qa.py` — 评分真实 Godot 截图并生成 diff/contact sheet，不负责渲染地图
- `tmp/` 中的 raster basemap 截图、分析报告与构建输出 — 只保留工作产物；正式可复现工具位于 `scripts/tools/`，临时图片和瓦片不得进入 Godot 扫描目录

### 运行时代码
- `scripts/survivor/map_geography.gd` — 公开 API（is_on_land / URBAN_DISTRICTS / HIGHWAYS / get_*）
- `scripts/survivor/map_geography_data.gd` — JSON 加载器（从 `tokyo_bay.json` 填充静态数组）
- `scripts/survivor/map_feature_renderer.gd` — 主地图渲染（Sprite2D 底图 + 矢量 + vignette）
- `scripts/survivor/raster_basemap_renderer.gd` — 三档静态 raster 瓦片 renderer；迟滞、0.40s crossfade、请求/绑定预算和 12 格 LRU
- `scripts/survivor/map_vector_preview_renderer.gd` — 冻结的 V44 debug 研究 renderer；不作为正式东京湾 PNG 替换路径
- `scripts/survivor/map_detail_vector_renderer.gd` — Detail AGDT + 可选 AGLW 实际高度侧墙静态合批 renderer；仅供 loading/安全暂停的一次性临时 viewport 使用
- `scripts/tools/bake_tokyo_bay_landmark_walls.py` — 从本地 OSM 高度标签离线生成 AGLW sidecar
- `scripts/survivor/map_detail_tile_cache.gd` — 2× 超采样、1536² 内容 + 4 px 过滤外挤、12 格 LRU；正式主图绑定静态 texture
- `scripts/tests/map_visual_qa_runner.gd` — PNG/vector 固定机位真实运行时采集
- `scripts/tests/map_raster_visual_qa_runner.gd` — 三图 PNG/streamed 同位对拍；逐图注入真实 MapDocument 的玩法地标/假 3D 建筑近景与数量断言；实际主图往返回滚、正式 Tab 关闭/重开、zoom sweep、resident/亮度连续性门
- `scripts/survivor/map_manual_background.gd` — @tool 编辑器预览（显示 OSM 给你描边用）
- `scripts/survivor/tactical_map.gd` — 战术缩略图（含 CRT 扫描线 / 暗角后绘制）

### 资源
- `resources/maps/tokyo_bay.json` — 矢量数据
- `resources/maps/tokyo_bay_bg.png` — 底图
- `resources/maps/tokyo_bay_bg.json` — 底图元数据
- `resources/maps/basemap_tiles/{tokyo,desert,ocean}/` — 三图 lossless WebP 三档瓦片、manifest 与 QA 摘要
- `resources/maps/tokyo_bay_vector_preview.json` — V15 中远景补充矢量（无地图内容栅格）
- `resources/maps/tokyo_bay_operational_density.agod.gz` — 513² 量化 OSM 标量场，不是地图贴图
- `resources/maps/tokyo_bay_operational_buildings.agob.gz` — AGOB v2 全图分级建筑概括 packet
- `resources/maps/tokyo_bay_operational_roads.agor.gz` — 15,431 条分区限额真实街区骨架（约 300 KiB gzip；运行时合批为 casing+core）
- `resources/maps/tokyo_bay_operational_landmarks.aglw.gz` / `.json` — 669 栋真实 `>=80m` 高层，29,688 三角、227,154 bytes gzip；所有战斗 zoom 常驻
- `resources/maps/tokyo_bay_detail_tiles_full.json` / `detail_tiles_packed/*.agdt.gz` — 全图 199 个非空近景矢量包
- `resources/maps/yokohama_gold_slice_preview.json` — 横滨 style 金样源；不含地图内容栅格
- `resources/shaders/basemap_tacview.gdshader` — 主地图 shader
- `resources/shaders/basemap_streamed.gdshader` / `resources/maps/shared_blue_noise_64.png` — 候选稳定世界空间蓝噪声 grain + 运行时 Sobel；共享纹理不含地图内容
- `scenes/map_manual.tscn` — 手画覆盖层场景

### 相关文档
- **[manual-map-editing.md](manual-map-editing.md)** — Polygon2D 手画地块的完整操作指南
- **[vector-map-production-playbook.md](vector-map-production-playbook.md)** — 冻结研究的金样、LOD、全格覆盖、建筑、性能与自主迭代经验；当前不授权东京湾 PNG 退役

### 真实画面回归命令

```powershell
bench\run.cmd map_gold_slice 1 120 Shadow
bench\run.cmd map_visual_qa 1 240 Shadow Visual
& 'C:\Users\noelu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts\tools\map_visual_qa.py tmp\map_visual_qa\runtime\manifest.json --allow-fail
```

Visual 模式仍走同一项目锁、Shadow 副本、有限超时与进程树回收；窗口被放到屏幕外，但使用真实 GL Compatibility renderer。当前全图门仍失败时 `--allow-fail` 只允许生成研究报告，不代表通过毕业门。

V44 历史基线：Operational 为 26 draw calls、1,236,202 三角；其中 `terrain_context` 14,496 三角、常驻 `landmark` 29,688 三角，视觉水面命中为 0，首次结构预热 1,327ms。120 秒同机同负载 Visual 压力为 PNG 117.91 FPS / 最低 38.12 / 3 个低于 60 FPS 帧，矢量 119.33 / 最低 29.87 / 1 个低帧；后半程战斗结果不同，因此只证明未触发 -15 FPS 门，不宣称矢量更快。2026-08-08 用户最终整图视觉验收未通过，PNG 已确认为正式保留方案，候选停止生产化推进。
