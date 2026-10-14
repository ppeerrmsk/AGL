# 东京湾地图问题研究与接手索引

更新：2026-10-14。请从这里接手：**目标是让全256块东京湾地图在正常拖拽、缩放和完整战斗中持续正确显示，并满足既有预算。** 当前M20地图可以安装运行，但仍有性能与覆盖问题；新的结构概括方案已有真实局部楼体与GPU实验，尚未组成通过验收的全图替代路径。最直接的反例是175号完整楼体候选比原生多937面；只优化屋顶还没有解决联合成本。

本页是导航和证据目录，不另立设计规范。行为、保护规则和预算以[东京湾地图规格302](../specs/systems/tokyo-bay-volume-map.md)及最新用户授权为准；发现冲突先指出，不用历史实验数值覆盖现行约束。

**复现正常游戏的整图性能问题：** 先按[当前完整运行地图下载与复现](2026-10-14-current-map-runtime-repro.md)安装新增的M20运行包（9个ZIP，约6.6GiB下载）。原175附件只复现局部结构实验，不能代替当前整图。

## 目录

- [1. 接手阅读顺序](#1-接手阅读顺序)
- [2. 源码与证据版本](#2-源码与证据版本)
- [3. 从问题直接定位](#3-从问题直接定位)
- [4. 三条路径与代码入口](#4-三条路径与代码入口)
- [5. 坐标、来源与资源口径](#5-坐标来源与资源口径)
- [6. 下载与重放175](#6-下载与重放175)
- [7. 已提供什么还缺什么](#7-已提供什么还缺什么)
- [8. 研究推进与验收入口](#8-研究推进与验收入口)
- [9. 已排除的捷径与历史陷阱](#9-已排除的捷径与历史陷阱)
- [10. 上传取舍与交接验证](#10-上传取舍与交接验证)

## 1. 接手阅读顺序

| 顺序 | 入口 | 读完应能回答 |
|---|---|---|
| 1 | [当前技术瓶颈报告](../audits/2026-10-14-tokyo-map-technical-status.md) | 哪些成果已真实运行，哪些只是局部证明，当前卡在哪里？ |
| 2 | [工程接手需求](2026-10-14-tokyo-map-engineering-requirements.md) | 不可改的条件、授权范围、交付物和验收门是什么？ |
| 3 | [当前M20完整运行包与性能入口](2026-10-14-current-map-runtime-repro.md) | 怎样下载当前实际地图并复现整图卡顿、切档和跨区问题？ |
| 4 | [175候选图](map-evidence-20261014/175-candidate.png)、[同位原生控制](map-evidence-20261014/175-control.png)、[原始引擎报告](map-evidence-20261014/175-engine.json) | 当前实物长什么样，显示范围与统计口径有多窄？ |
| 5 | [规格302](../specs/systems/tokyo-bay-volume-map.md) | 普通住宅如何概括、哪些对象必须保护、预算与连续显示怎么裁决？先读当前正文，再查对应历史条目。 |
| 6 | [本页问题表](#3-从问题直接定位)和[代码路径](#4-三条路径与代码入口) | 自己准备解决的瓶颈落在哪一层？ |
| 7 | [可点击证据目录](map-evidence-20261014/README.md) | 结论对应哪份原始记录，哪些数据可以直接下载核对？ |
| 8 | [地图工程手册](../systems/map-volume-engineering.md)、[地图流水线](../reference/map-pipeline.md)、[实施计划](../planning/tokyo-resident-foundation-2026-10-01.md) | 已有生产工具和历史路线有哪些；哪些步骤依赖未上传产物？ |

首次不必顺读全部历史日志或整个巨大规格的变更表。查其他代码域时按[Reference Index](../reference/_INDEX.md) → [Script Index](../reference/script-index.md) → [Code Index](../reference/code-index.md)进入。工程全局约定见[AGENTS.md](../../AGENTS.md)，项目背景见[项目概述](../project-overview.md)。

## 2. 源码与证据版本

| 项目 | 固定身份或入口 |
|---|---|
| 接手分支 | [`codex/map-handoff-2026-10-14`](https://github.com/ppeerrmsk/AGL/tree/codex/map-handoff-2026-10-14)；后续文档补充在此分支 |
| 冻结源码基线 | [`1d58939bd5d7be4a00b12e844237fe213b684fc8`](https://github.com/ppeerrmsk/AGL/commit/1d58939bd5d7be4a00b12e844237fe213b684fc8)，包含交接时已保存的源码与必要文档 |
| 冻结证据Release | [map-handoff-2026-10-14](https://github.com/ppeerrmsk/AGL/releases/tag/map-handoff-2026-10-14)，tag仍指向上述源码基线 |
| 当前整图运行包 | [M20安装与性能复现](2026-10-14-current-map-runtime-repro.md)：9个`tokyo-m20-runtime-20261014-part*.zip`，另有manifest与独立SHA256SUMS |
| 局部实验ZIP | `tokyo-map-repro-175-20261014.zip`，10237248字节；另附`SHA256SUMS.txt` |
| ZIP SHA256 | `38aa06107067cba061ab1fdddb0330422d7cea676991618c6138e1bf159c68fd` |
| ZIP逐文件清单 | [archive-manifest.json](map-evidence-20261014/archive-manifest.json)；包内原件为`tmp/map-handoff-evidence-20261014/MANIFEST.json` |
| 网页证据副本来源 | [provenance.json](map-evidence-20261014/provenance.json)，区分原样副本、大数组摘要和仅清理行尾空白的日志阅读副本 |

分支首页可以继续更新，Release输入与历史报告保持冻结。复现记录须写实际checkout提交号、ZIP摘要、重绑定后的请求摘要和工具版本；不要只写“使用最新代码”。原始`main`的`c27be544...`不包含当时未提交/未跟踪的全部成果，不能代替此交接快照。

## 3. 从问题直接定位

| 当前问题与证据 | 优先读的代码/资料 | 下一项必须形成的证明 |
|---|---|---|
| **完整楼体没有净收益**：175候选140949面，原生140012面；候选屋顶10215、侧墙20258面。见[175构建账](map-evidence-20261014/175-build.json) | [完整楼体GL预览](../../scripts/tests/tokyo_native_joint_preview.gd)、[几何解包](../../scripts/tests/tokyo_selectable_geometry_save.gd)；ZIP中`tmp/tokyo_joint_patch_173.py` | 同一范围、同一尺度、所有层同时存在的实际面数/批次/字节下降；不能只引用164的屋顶降幅 |
| **远景提交超限**：169在scale=0.4、中心`[-8192,-15104]`，屋顶199080＋地表43132＝242212面，尚无完整墙/保留楼。见[169报告](map-evidence-20261014/169-spatial.json) | [空间切线选择器](../../scripts/experiments/tokyo_spatial_cut.gd)、[HLOD overlay](../../scripts/rendering/tokyo_hlod_overlay.gd)；ZIP中`tmp/tokyo_triangle_spatial_169.py` | 近中远和过渡联合≤240000面；同时记录实际surface/draw，不能用更细分组掩盖批次成本 |
| **全驻留超内存**：155特定屋顶布局三份289618092字节，已比192MiB多88291500字节。见[155报告](map-evidence-20261014/155-resident-cost.json) | [压缩屋顶GPU构建](../../scripts/tests/tokyo_local_roof_gpu.gd)、[流送资源账](../../scripts/rendering/tokyo_hlod_stream.gd)、[基础资源队列](../../scripts/rendering/tokyo_cell_stream.gd) | 完整表示的物理身份账；当前、接替、在途、工作区同时存活时仍满足预算 |
| **异步准备没有必然时间窗**：正式拖拽无速度上限，64单位预取边界可被一次输入穿越。见[138报告](map-evidence-20261014/138-camera-deadline.json) | [相机输入](../../scripts/camera_controller.gd)：`handle_drag`、`handle_zoom_input`；overlay的`_target_covers_current_view`、`_commit_ready_target` | 任意合法输入后仍有完整已就绪覆盖；突发跳转、往返、缩放穿档均需反例测试 |
| **来源保护只在局部闭合**：172匹配23592栋；原始2049组complete，175再因共享来源阻断后只接受2048组。见[172摘要](map-evidence-20261014/172-summary.json)、[175构建账](map-evidence-20261014/175-build.json) | [完整来源范围](map-evidence-20261014/full-source-scope.json)、[全图归属路由](map-evidence-20261014/full-source-routes.json)、[覆盖凭据](../../scripts/rendering/tokyo_hlod_coverage.gd)；ZIP中`tmp/tokyo_native_members_171.py` | 全256块来源身份、重复/缺失、保护资格、跨块接缝核对；不能靠坐标接近删原楼 |
| **稳定性被误当连续显示**：175每姿态取首帧后还停两帧，再移动到下一姿态。见[175引擎报告](map-evidence-20261014/175-engine.json) | [预览run](../../scripts/tests/tokyo_native_joint_preview.gd)、[路线探针](../../scripts/tests/tokyo_hlod_route_probe.gd)、[边缘审计](../../scripts/tests/tokyo_hlod_edge_audit.gd) | 第一轮每显示帧推进、不等稳定；第二轮独立稳定参考；再核对独立来源覆盖 |
| **性能和退出仍未过门**：175含同步GPU读回；174 all虽102项零失败、lifecycle90/0，仍有14对象/7资源告警。见[174日志](map-evidence-20261014/174-all.log) | [战斗采样器](../../scripts/tests/tokyo_volume_combat_runner.gd)、[渲染帧时钟](../../scripts/tests/tokyo_render_clock.gd)、[性能守则](../reference/performance-guidelines.md)、[运行时验证流程](../reference/runtime-validation-workflow.md) | 无诊断读回的Visual墙钟数据、完整战斗、全局退出；局部weakref为0只证明局部跟踪对象 |

这些反例否定的是相应实现/布局，不是对所有地图表示作“不可能”的判断。研究者可换结构，但必须保留同一完整目标与验收口径。

## 4. 三条路径与代码入口

### A. 正式地图加载与现有HLOD路径

加载流程先由installed map确定包身份，再由preload准备与转交；MapFeatureRenderer在地图中接收。HLOD overlay负责选取和提交，stream负责资源生命周期。这条路径与下面两个诊断实验不能混为一谈。

| 文件 | 应关注的入口或责任 |
|---|---|
| [tokyo_installed_map.gd](../../scripts/rendering/tokyo_installed_map.gd) | `package_path`、`package_sha`。项目设置`rendering/tokyo_map/installed_package`；显式`AGL_TOKYO_HLOD_PACKAGE`优先；实验`AGL_TOKYO_VOLUME`会影响默认选择 |
| [tokyo_volume_preload.gd](../../scripts/rendering/tokyo_volume_preload.gd) | `script_path`、`start`、`take`、`state_ready`、`cancel`。Loading→正式地图转交同一overlay/viewport/stream及包身份 |
| [map_feature_renderer.gd](../../scripts/survivor/map_feature_renderer.gd) | `TokyoVolumePreload.take`及overlay挂载；追踪地图表现的接收者 |
| [tokyo_hlod_overlay.gd](../../scripts/rendering/tokyo_hlod_overlay.gd) | `_select_hlod`、`_select_native`、`_target_covers_current_view`、`_resources_ready`、`_commit_ready_target`、`_handoff_bytes`、`_clear_current` |
| [tokyo_hlod_stream.gd](../../scripts/rendering/tokyo_hlod_stream.gd) | `residency_request_ledger`、`handoff_increment`、`prepare_target_space`、`_process_stream`、`close`；解码、纹理、在途和显示集合的费用 |
| [tokyo_cell_stream.gd](../../scripts/rendering/tokyo_cell_stream.gd) | `request`、`resource`、`reserve_auxiliary`、`_collect_completed`、`close`；基础加载队列、保留额度与释放 |
| [tokyo_spatial_cut.gd](../../scripts/experiments/tokyo_spatial_cut.gd) | `choose`、`solve`、`_frontier`、`_combine`；候选切线的覆盖/预算与选择CPU费用 |
| [manifest](../../scripts/rendering/tokyo_hlod_manifest.gd)、[coverage](../../scripts/rendering/tokyo_hlod_coverage.gd)、[native](../../scripts/rendering/tokyo_hlod_native.gd)、[cache policy](../../scripts/rendering/tokyo_hlod_cache_policy.gd) | 目录身份、覆盖资格、原生来源与缓存策略；与overlay、stream一起读 |
| [raster_basemap_renderer.gd](../../scripts/survivor/raster_basemap_renderer.gd) | 2D地表瓦片的所有者；底图可见不能证明3D建筑或覆盖已经完整 |

干净clone需要先按[当前运行包说明](2026-10-14-current-map-runtime-repro.md)安装M20资产。bench默认不自动接正式安装包；需要明确包身份与有效资源，或按入口要求设置`AGL_TOKYO_INSTALLED_TEST=1`。不要通过随意开关历史环境变量凑出画面后称为正式路径通过。

### B. 165/166压缩屋顶实验

离线结构屋顶164 → 四段打包165 → 166实际GL布局审计。测试分派位于[vector roof compare](../../scripts/tests/tokyo_vector_roof_compare.gd)，GPU构建与shader位于[tokyo_local_roof_gpu.gd](../../scripts/tests/tokyo_local_roof_gpu.gd)。

该表示用8字节代理顶点、街区RGBAF表和经实际读回核实的u16索引；shader逐顶点查找组表。四段载荷合计2892226字节，但**是分别加载验证**，没有四段同时驻留、完整楼体或性能验收。其逐顶点搜索成本仍需实测。读[166原始审计](map-evidence-20261014/166-gpu-audit.json)，不要把其费用直接套给175。

### C. 175完整楼体最小复现

```text
bench/run.cmd tokyo_cells_lifecycle 1 180 Shadow Visual
  → scenes/tests/tokyo_cells_lifecycle.tscn
  → tokyo_cells_lifecycle_runner.gd::_ready
  → tokyo_partition_stream_probe.gd::run
  → tokyo_vector_roof_compare.gd::run   [vector_roof_compare]
  → tokyo_native_joint_preview.gd::run [native_joint_patch]
  → tokyo_selectable_geometry_save.gd::build
```

直接读：[runner](../../scripts/tests/tokyo_cells_lifecycle_runner.gd) → [partition probe](../../scripts/tests/tokyo_partition_stream_probe.gd) → [vector compare](../../scripts/tests/tokyo_vector_roof_compare.gd) → [joint preview](../../scripts/tests/tokyo_native_joint_preview.gd) → [geometry build](../../scripts/tests/tokyo_selectable_geometry_save.gd)。材质使用[tokyo_hlod_surface.gd](../../scripts/rendering/tokyo_hlod_surface.gd)的`native_code`，投影见[volume_projection.gd](../../scripts/experiments/volume_projection.gd)。

此路径读取冻结的候选/控制属性、索引和mask，构建普通全属性ArrayMesh；没有使用B的压缩屋顶GPU表示。左侧候选、右侧原生只覆盖`detail_04_00`与`detail_05_00`交界的一小块近景：中心`[-6300,-14500]`、位置±64、scale 2至5、24姿态。它不是两块全量，也不是正式地图流送。

## 5. 坐标、来源与资源口径

| 容易混淆的概念 | 阅读约定 |
|---|---|
| 游戏世界与3D显示 | 游戏仍为2D权威＋数值高度；1世界像素＝2米。显示投影将地面2D的`(x,y)`映到3D的`(x,height,z=y)`；不要为修地图改变飞行物理 |
| 投影角与缩放 | 东京诊断显式使用38°；通用投影函数默认值不等于东京调用实参。报告`scale`与实际输出像素比例须核对viewport，不直接当作任意窗口下的Camera2D.zoom |
| 权威范围 | [全图瓦片目录](../../resources/maps/tokyo_bay_detail_tiles_full.json)和[256块来源范围](map-evidence-20261014/full-source-scope.json)。31块只是旧边缘集合；ZIP中旧`tmp/full_map_detail/build_manifest.json`选择203块，也不是本轮256块权威清单 |
| 原生三层 | `fallback_height_buildings`、`tagged_height_buildings`、`fixed_ground`同时存在；它们不是互斥LOD。高度来源标签也不等于重要建筑保护分类 |
| 来源匹配与替换资格 | 172原始2050组中2049组complete、组2031不完整；175再排除与阻断来源共享的组，最终接受2048。不能把源楼匹配成功直接等同所有组可删原楼 |
| 面/页/批次 | 240000面与16逻辑页是不同门；实际surface、draw、材质/纹理对象另外记录，不能互相代称 |
| 内存 | 当前合同192MiB＝201326592字节，保留约定三份保守费用。历史代码中96MiB等实验分支不是现行授权；文件gzip体积、源数组体积、GPU通道和进程峰值分开 |
| 图片稳定与正确 | 175首帧/稳定帧差0，不证明两张图未共同漏对象；候选与原生仍有208657个像素变化、最大通道差85。美术认可与来源完整性单独验收 |

全图scope记录里的`missing_previous_block_plans`是生成该清单时的旧计划缺口，不可解释为现在缺52块原始来源。源生产、候选生成、运行时接入、正式验收是四个独立状态。

## 6. 下载与重放175

下面只重放冻结的局部问题，不需要生成整图。使用新clone，避免同名证据与本地实验互相覆盖。需要Git、Python 3、Godot 4.7+；示例下载使用GitHub CLI，也可从Release页面手动下载两个附件。不要用Godot 4.6.2。

```powershell
git clone --branch codex/map-handoff-2026-10-14 https://github.com/ppeerrmsk/AGL.git
Set-Location AGL
gh release download map-handoff-2026-10-14 --repo ppeerrmsk/AGL --pattern 'tokyo-map-repro-175-20261014.zip' --pattern 'SHA256SUMS.txt' --dir tmp/handoff-download
$handoffZip = 'tmp/handoff-download/tokyo-map-repro-175-20261014.zip'
$handoffExpected = '38aa06107067cba061ab1fdddb0330422d7cea676991618c6138e1bf159c68fd'
if ((Get-FileHash $handoffZip -Algorithm SHA256).Hash.ToLower() -ne $handoffExpected) {
    throw '交接ZIP摘要不匹配；停止，不解压、不重跑。'
}
Expand-Archive $handoffZip -DestinationPath .
python tools/prepare_map_handoff_175.py
if ($LASTEXITCODE -ne 0) { throw '175输入准备失败。' }
$env:AGL_TOKYO_PARTITION_STREAM=(Resolve-Path tmp/map-handoff-175-replay/request.json).Path
$env:AGL_TOKYO_PARTITION_STREAM_SHA=(Get-FileHash $env:AGL_TOKYO_PARTITION_STREAM -Algorithm SHA256).Hash.ToLower()
# 若Godot不在bench默认位置，设置自己的4.7+可执行文件。
# $env:GODOT='D:\path\to\godot_console.exe'
try {
    & bench/run.cmd tokyo_cells_lifecycle 1 180 Shadow Visual
    $handoffBenchExit = $LASTEXITCODE
    Write-Host "bench wrapper exit=$handoffBenchExit"
}
finally {
    Remove-Item Env:AGL_TOKYO_PARTITION_STREAM -ErrorAction SilentlyContinue
    Remove-Item Env:AGL_TOKYO_PARTITION_STREAM_SHA -ErrorAction SilentlyContinue
}
```

[准备工具](../../tools/prepare_map_handoff_175.py)只依赖Python标准库：验证原请求及6份压缩输入SHA和解压长度，重绑定路径，创建新输出目录。它拒绝覆盖已有输出，也不安装地图或启动引擎。重复实验可通过`--output tmp/<新目录>`指定新目录，同时让上面两处环境变量指向该目录的`request.json`。运行后核对新目录`engine/report.json`及截图，并保留wrapper退出码和日志；失败时从首个运行时错误块查起。

引擎只能经[bench wrapper](../../bench/run.cmd)启动。遵守[AGENTS](../../AGENTS.md)及[接手需求的测试前置条件](2026-10-14-tokyo-map-engineering-requirements.md)：锁与唯一写入窗口、内存/磁盘余量、普通TEMP Shadow、Visual、有限超时。退出86为运行时错误门失败，124为超时；Godot自身退出0不能覆盖wrapper判定。

预期是重现局部事实：24姿态、候选140949/控制140012面、候选打包7730244字节、三份23190732字节；报告保留`full_map_qualified=false`、`peak_qualified=false`、`performance_qualified=false`。跨设备图像差异需记录GPU、驱动、引擎和分辨率，不能直接改历史通过记录。

本次已验证输入包、准备工具和远端文件摘要，**未在另一台全新机器完成Godot导入/GL重放**。175含同步GPU读回，不用于60FPS结论；它仍是逐姿态等待测试，不满足规格规定的双轮不停顿连续显示。

## 7. 已提供什么，还缺什么

只读研究可以直接使用[网页证据目录](map-evidence-20261014/README.md)，无需下载ZIP。正常游戏整图复现现在已补齐[当前M20运行包](2026-10-14-current-map-runtime-repro.md)；完整运行依赖与完整离线制作链是两种不同交付。重放175需要ZIP中的6份冻结输入。修改制作算法后重新生成175则需要更多直接输入，不能与重放混写。

| 工作 | 已提供 | 缺口与补齐入口 |
|---|---|---|
| 当前M20整图运行/性能问题复现 | [9个运行分包、manifest、安装和复现工具](2026-10-14-current-map-runtime-repro.md) | 资源逐项校验通过；另一台机器的导入/GL性能结果仍需按固定入口实测 |
| 阅读、定位、重放175 | 完整源码；请求、6份输入、截图、报告、日志和重绑定工具 | 新机器Godot导入与GL重放尚待接手者验证 |
| 重新生成175 | ZIP内`tmp/tokyo_joint_patch_173.py`、164/172完整JSON、[直接依赖清单](map-evidence-20261014/175-rebuild-inputs.json) | 14项直接依赖中12项未随包，合340990523字节（约325.2MiB）：统一来源、164数组、两块原生层manifest/attributes。清单含每项路径、大小、SHA；不是整图重建的传递依赖闭包 |
| 复核全256块来源结构 | [scope](map-evidence-20261014/full-source-scope.json)、[spool manifest](map-evidence-20261014/full-source-spool.json)、[routes](map-evidence-20261014/full-source-routes.json)、权威瓦片目录 | 全体源分片、完整ownership对象、PBF及生成二进制未上传；这些元数据证明范围/绑定关系，不代替源对象实物 |
| 重建原生三层 | [区域源制作器](../../scripts/tools/build_tokyo_volume_region.py)、[归档构建](../../scripts/tests/build_tokyo_region_archive.gd)、[原生构建](../../scripts/tests/build_tokyo_regional_native.gd) | 精确PBF、bbox、city/ground来源、关系/高度/海陆配方与逐步依赖，按工程手册确认目标路线 |
| 生产新的候选安装包 | [增量打包](../../scripts/tests/stage_tokyo_incremental_package.gd)、[安装工具](../../tools/install_tokyo_incremental.ps1) | 已验证资源、目录、覆盖凭据和SHA；安装器不是从空目录重建全地图的生产器 |

PBF原快照`tmp/full_map_detail/kanto-latest.osm.pbf`为483274002字节，SHA256为`4c6abf82e1ca793ef8c498830a103bdc9b209b4b4b65f25f913024de4bb0ecda`，来源记录见[archive manifest](map-evidence-20261014/archive-manifest.json)。重新下载的latest不保证同一数据；若摘要不同，要建立新来源版本，不能改期望摘要冒充原基线。

需要生产某项候选时，先列出所需清单项及其上游，再按需补齐或重建。当前M20可以直接安装运行，但没有可承诺的一条命令从原始地理数据完整重建；不要先下载全部历史生成资源，也不要批量执行ZIP内临时脚本。部分脚本文件名沿用旧编号，实际内容已指向新输出，例如`tokyo_joint_patch_173.py`实际生成175。

## 8. 研究推进与验收入口

按[工程接手需求](2026-10-14-tokyo-map-engineering-requirements.md)推进，不要求沿用失败架构：

1. **冻结并重现基线。** 交付提交号、依赖摘要、环境、请求、原生/候选同位图、实际报告及未通过项。
2. **先证明完整表示有成本出口。** 同一代表性中远范围必须包含地表、保留楼、候选屋顶、侧墙和保护对象。比较三条路径，解释采用哪部分及其总成本；没有净收益就提交反例和结构性替代方案。
3. **在同一路径解决连续覆盖。** 定义当前/接替资源的合法域、来源身份、取消、提交和回收；用不停顿双轮测试、突发输入和独立覆盖核对证明。
4. **扩展全256块。** 有界批次验证身份、保护、接缝、全边缘和近中远；单个最高密块的降幅不能直接外推其他255块。
5. **完成正式运行门。** 候选资格完成后接F5，运行完整战斗、严格Visual性能、全局退出，再决定正式切换。

| 入口 | 适用与边界 |
|---|---|
| `bench/run.cmd tokyo_cells 1 180 Shadow Headless` | 地图focused断言；修改相关运行时代码后先用最窄覆盖测试。不是画面验收 |
| `bench/run.cmd tokyo_cells_lifecycle 1 180 Shadow Visual` | 本页175复现用显式请求；该场景还承担其他诊断，必须记录实际环境和分派路径 |
| `bench/run.cmd all 1 300 Shadow Headless` | focused通过后全量与真实生命周期回归；wrapper错误门及退出告警单独核对 |
| `tokyo_volume_c1/c2`及对应baseline、`tokyo_cells_c1/c2`及对应baseline、`tokyo_cells_near`及baseline | [BenchRunner登记](../../scripts/bench/bench_runner.gd)的地图Visual专项；先按所选路径补齐有效包，不能在缺资产clone上把空地图当通过 |
| `battlefield_atmosphere_stress_36`与所需广域专项 | [性能守则](../reference/performance-guidelines.md)的代表性混合战场；地图专项不能替代完整战斗成本 |
| 正常F5进入/退出、完整局 | 正式安装路径和玩家实际流程；隔离SubViewport成功不能代替 |

连续/边缘路线可参考[route probe](../../scripts/tests/tokyo_hlod_route_probe.gd)和[edge audit](../../scripts/tests/tokyo_hlod_edge_audit.gd)，但需核查实际姿态推进方式与合法域，不能直接把旧路线日志当新表示的资格。性能采样与图像读回分开，保留VSync；研究验收沿用约定的2×MSAA，当前M20原状复现则保留实际4×设置，详见[运行包说明](2026-10-14-current-map-runtime-repro.md#3-固定复现入口)。记录平均、最差、p1、`frames_below_60`、分辨率、GPU/驱动、实际战斗对象和后台活动。

研究回报最少回答：**选哪种统一表示；完整联合费用是多少；任意合法相机输入如何保证覆盖；哪些结论是实物验证、哪些仍是假设；下一项失败会否决什么。** 失败记录与输出目录保留，避免继续堆积无法串成产品路径的独立探针。

## 9. 已排除的捷径与历史陷阱

| 不要重复的推论 | 已有证据/代码导航 |
|---|---|
| 屋顶省33%，所以完整地图也省33% | 164与174/175口径不同；[164摘要](map-evidence-20261014/164-summary.json)、[175构建账](map-evidence-20261014/175-build.json) |
| 压缩屋顶四段各自载入成功，所以完整楼体四段并驻成功 | [166](map-evidence-20261014/166-gpu-audit.json)明确未验证combined residency、元数据上传峰值、地表/侧墙/保护对象 |
| 有64单位缓冲或慢速轨迹通过，所以异步加载必定赶得上 | [138](map-evidence-20261014/138-camera-deadline.json)及正式相机输入反例 |
| 文件很小、GPU登记很小、释放后很小，所以全过程峰值合格 | [155](map-evidence-20261014/155-resident-cost.json)、[140](map-evidence-20261014/140-texture-residency.json)；物理身份、在途与上传暂存另外计 |
| 层更新接口没做出来，必须重试旧2D矩形更新 | [texture update probe](../../scripts/tests/tokyo_texture_update_probe.gd)已有分层更新路径；现在缺完整覆盖/预算方案，不能重复把接口成功当全图成功 |
| 顶视平面atlas、两张稳定截图或一张地表能代表完整楼体 | [known-seams](../architecture/known-seams.md)的SEAM-045、048、051：地理投影、高度遮挡、地表与建筑覆盖必须分开验证 |
| 切线中空`children=[]`、旧目标合法域或旧边缘清单可直接沿用 | [known-seams](../architecture/known-seams.md)的SEAM-046、049、052：重新裁决当前镜头、拒绝零成本假切分、用全256块范围 |
| 把推定/标注高度层当LOD或保护类别，按空间相近删除源 | [known-seams](../architecture/known-seams.md)的SEAM-050及[172](map-evidence-20261014/172-summary.json) |

加载所有权、资源预算饿死、preload就绪协议、提交瞬间峰值分别见同一登记的SEAM-041、042、044、047。这些条目用于定位已有反例，不表示本次已经修复。

## 10. 上传取舍与交接验证

| 内容 | 本次处理 |
|---|---|
| GDScript、shader、场景、参数、制作/安装/校验工具、规格与索引 | 保留源码快照；研究者能沿调用链阅读和修改 |
| 核心JSON、来源metadata、日志及两张代表图 | 在本页的证据目录直接浏览；大数组报告保留ZIP原件，网页摘要明确标明省略字段 |
| 175请求、6份压缩输入、原始报告和临时研究脚本 | 冻结在Release ZIP，保留原tmp相对路径和逐文件SHA |
| 当前M20完整运行依赖及必要3D入口归档 | 已补传Release：只选择当前引用，分包与逐文件SHA固定，不入Git历史 |
| 其他安装版本、重复库、未引用预览资产、缓存、导出程序、PBF | 不上传；保留制作入口、来源与必要缺口清单 |
| 本机配置、凭据、.godot、Python缓存、可生成.translation变化 | 不上传；翻译真源CSV保留 |

175的6份压缩输入是固定问题现场所必需，避免对方先重生产整图；不是允许全量提交生成二进制。已有Git历史资源不重写；`.uid`保留稳定引用，`.import`只跟随实际包含的源文件。首次索引补充只增加文本；后续按用户要求补传当前运行地图的必要二进制，详见[运行包说明](2026-10-14-current-map-runtime-repro.md)。

交接检查包括文档链接、代码锚点、玩家引用登记、Git空白、证据来源与摘要、175准备工具及拒绝覆盖。全量/Visual/完整局/全图/性能的历史证据与当前资格分开；本次整理不改游戏运行时代码，也不把文档检查算作地图修复。后续代码变更仍须focused→all及相应Visual门。
