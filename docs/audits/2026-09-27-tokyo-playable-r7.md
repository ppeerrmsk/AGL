# 东京湾可玩接入与性能收口 R7

日期：2026-09-27。状态：**正式入口可玩烟测通过，整体验收尚未完成**。承接 [R6](2026-09-18-map-repair-r6.md)；执行范围见 [收口计划](../planning/tokyo-playable-closure-2026-09-27.md)。

## 已完成的工序

1. 验证当前安装资源为 `res://resources/maps/tokyo_playable/m20/package.json`，七份catalog的SHA一致；测试未设置候选包替代路径。
2. 先通过Loading进入正式Survivor，再审计四边、四角、多档缩放及额外宽高比的40视图。优化前后两轮覆盖缺口均0，退出释放流送资源。
3. 优化前西区、东北边缘、高楼区各48秒、960次正式相机输入回放，含36个混合战斗实体；优化后西区、东北边缘重跑通过。所有回放隐藏帧、预算失败均0。固定60FPS只用于输入吞吐诊断，不能作为严格性能达标证据。西区优化后有2个短暂清晰度宽限帧，最大17ms、比例1.034；不是旧底图闪回，也不隐去这项记录。
4. 从真实主菜单人工选择海岸线、F-15、出击；实际观察Loading和正式游戏，执行飞行目标点击、升级选择、Tab战术图及暂停/继续。180秒烟测有111.272秒活动时间，飞机移动13449.14世界单位；可见交战、击杀与HP减少。自动报告21589个显示样本中隐藏/预算失败/清晰度宽限均0，返回退出后流送释放。该报告的 `loading_route_ms` 包含人工菜单选择等待，不能解释成加载耗时；专用加载路线约9.3秒。
5. 针对实际测到的地图资格树重复构造做单一优化；focused与默认all通过，再重跑Visual性能与交互/边缘，不重做已认可的地图美术。

以上仅证明当前保存工程在Shadow隔离副本中的正常入口与短程操作；不将自动报告中 `full_run_verified=false` 改成完成，不冒充完整12–20分钟局验收。

## 代码变更及边界

`TokyoHlodManifest.qualified_roots` 按资源身份与 `(lower, upper]` 缩放区间复用一份纯值资格树。原有可见性、投影、预算、空间切割仍重新求解；不缓存跨帧相机结果，不持有新增Object，不改变LOD阈值、模型细节、贴图、阴影、96MiB预算或战斗成本。

测试覆盖阈值正反穿越、资源SHA失效、输入不变，以及3相机中心×3缩放×3预算与原算法完整结果一致（排除计时值）。debug新增构造/复用次数；首轮C1构造1次、复用295次。

对应实现：`scripts/rendering/tokyo_hlod_manifest.gd`、`tokyo_hlod_overlay.gd`；测试 `scripts/tests/test_tokyo_hlod_manifest.gd`。索引已增加符号指针。

## 严格性能：保留失败，不以均值代替最差帧

使用安装M20、真实战斗及巡航（C1/近景36实体，C2为48实体），36秒Shadow Visual；开启独立墙钟记录，未开启系统采集/GPU探针，未改变画质、VSync或限制帧率。

| 场景/结果文件时间（UTC） | 墙钟平均FPS | p99 ms | 最差ms | 超16.67ms帧数 |
|---|---:|---:|---:|---:|
| C1优化前 033510 | 118.843 | 14.949 | 19.713 | 16 |
| C1优化后 034031 | 119.115 | 13.994 | 21.877 | 15 |
| C1优化后 034124 | 119.288 | 14.135 | 20.881 | 13 |
| C1优化后 034216 | 119.688 | 13.612 | 20.519 | 3 |
| C2优化后 034309 | 118.355 | 16.306 | 38.222 | 32 |
| 近景优化后 034401 | 119.692 | 未摘录 | 37.800 | 6 |

结果位于 `bench/results/tokyo_volume_{c1,c2,near}_20260927_<时间>.txt`。所有性能场景退出1，符合严格墙钟失败预期；地图隐藏与预算失败均0。引擎delta在C1报告零低于60帧，而独立墙钟仍发现超时，不得仅引用引擎结果过门。

C1选择耗时总和由单轮基线814258µs降至三轮中位615871µs（约24%），属于局部趋势，不是三轮配对试验或整场性能改善24%。C2最差帧38.222ms中的已知CPU桶不足以解释整帧，不能继续把剩余时间归因于已优化的资格树，也不能直接归给GPU。

## 系统采集与待办

管理员采集 `tmp/map-lod-acceptance/r7/capture-20260927-120500/cpu-gpu.etl`：295.253秒、0 lost events/0 lost buffers；包含前置同步，不把同步耗时算作游戏。Godot PID5372、主线程40468在trace227.10秒开始，237–273秒为选取的36秒游戏窗口。上下文切换统计主线程CPU约34810.7ms，约单核96.7%，**不是整机CPU96.7%**。采样同时出现Godot、系统内核、NVIDIA OpenGL驱动；仅凭模块采样不能判定GPU利用率或驱动故障。

此ETL是海洋FINAL WAR共享链诊断，不替代东京湾验收。微软WPA模板导出仅获得Unknown/MemoryTransfer记录，不能据此说GPU空闲；没有绝对时间锚定的同帧归因证据，不把异步CPU/GPU均值相加，不把未埋点时间称作GPU等待。

补充东京湾C2渲染诊断（不当作性能验收）：

- `tokyo_volume_c2_20260927_040855.txt`：36秒，默认VSync、后端计时开启；地图GPU均值0.568ms、飞机GPU0.353ms、主视口GPU0.797ms，各视口独立记录，不与CPU相加。最差墙钟22.863ms，其中before/draw/after分别3.728/10.766/8.369ms。GPU确实参与渲染，均值不支持持续GPU饱和，但不证明某一慢帧的具体等待原因。
- `041014`：显式关闭VSync的诊断对照，平均帧间隔4.953ms，却出现339.723ms尖峰（after段334.582ms）。不能将其作为修复，正式设置未修改。
- `041233`：默认VSync、无GPU读回，只记阶段；60秒最差21.248ms、超时27帧、全部8巡航段覆盖，隐藏/预算失败0。最差before/draw/after为3.185/10.482/7.581ms。证明尖峰并非必须由GPU读回探针触发，仍须系统级同帧对齐。

新增仅诊断的PID/UTC/单调时钟夹逼锚点，慢帧记录begin/pre/post/next原始tick；不改变正常游戏、性能门或GPU结果语义。`perf_trace` 34通过/0失败，后续默认all退出0、生命周期90通过/0失败。系统采集脚本 `tmp/map-lod-acceptance/r7/capture_tokyo_timeline.ps1` 只等待自己启动的受保护bench进程树；Godot出现后才启动WPR，排除Shadow复制，保留600秒总监督上限和引擎180秒看门狗。需要Windows管理员权限，不绕过UAC。

计时接口定义参考 [Godot官方RenderingServer文档](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)；帧预算结论仍以本机实际独立墙钟为准。

下一步只针对未解释长帧继续定位，再复验性能；完整长局、退出重进覆盖和严格60FPS收口仍是未关闭门。不得扩充地图细节、重复优化HUD布局或将平均119FPS描述成全部达标。

## 回归和证据位置

- `tmp/map-lod-acceptance/r7/qualification-focused.log`：focused退出0。
- `all-qualification.log`（同目录）：默认all退出0，生命周期90通过/0失败；仍有14个ObjectDB及7资源退出警告，不宣称零泄漏。
- `tokyo-cache-edges/report.json` 与 `edge_*.png`：优化后40视图。
- `tokyo-cache-fast-west/report.json`、`tokyo-cache-fast-northeast_edge/report.json`：优化后输入回放。
- `tokyo-main-menu-play/report.json`、`play_start.png`、`play_end.png`：正式菜单烟测和引擎实拍；人工交互补充本记录，不改写自动报告的验证字段。
- 本轮缓存持有者校验通过，登记遗漏0；改动路径 `git diff --check` 通过；文档链接、登记、元数据与Script/Code索引锚点通过（新增诊断移位锚点已刷新）。
- 固定近景实拍：`tmp/map-lod-acceptance/r7/tokyo-near-verified.png`，来自本轮近景战斗测试，不是生成概念图。

未提交、未推送。共享工作区既有改动均保留；其他任务占用bench时等待，不抢锁、不杀其进程。
