# 地图研究交接与下载说明

本快照用于让接手者阅读现有源码、重现局部问题并研究方案，不是已通过验收的游戏发布。先读[当前技术瓶颈](../audits/2026-10-14-tokyo-map-technical-status.md)，再读[工程接手需求](2026-10-14-tokyo-map-engineering-requirements.md)；行为与预算仍以[东京湾规格](../specs/systems/tokyo-bay-volume-map.md)为准。

源码分支：`codex/map-handoff-2026-10-14`。配套证据放在同仓库的 [map-handoff-2026-10-14 Release](https://github.com/ppeerrmsk/AGL/releases/tag/map-handoff-2026-10-14)。本地原分支及未提交工作保持原状；该分支包含当前已保存的项目源码快照。

无需下载即可查看[175候选图](map-evidence-20261014/175-candidate.png)和[同位原生控制](map-evidence-20261014/175-control.png)。候选140949面、控制140012面；相邻局部可显示，但候选尚无联合减面收益，不代表全图或美术验收通过。

## 上传取舍

| 内容 | 处理 | 原因 |
|---|---|---|
| GDScript、shader、场景、参数文本、Python/PowerShell工具 | 上传源码分支 | 阅读完整调用链与继续修改所需 |
| 当前规格、索引、计划、审计、交接文件 | 上传源码分支 | 区分正式入口、候选与失败证据 |
| 175号请求、6份压缩输入、实景对照、报告与日志 | 上传证据ZIP | 固定问题现场；不必先重生产整图便可重放局部GL测试 |
| 164/165/166/169/172等关键报告及174全量日志 | 上传证据ZIP | 支撑成本、来源与未验收结论，保留原始记录 |
| 当前临时地图研究Python/PowerShell脚本 | 上传证据ZIP，保留原`tmp/`路径 | 保存当前实际脚本版本；部分脚本内嵌历史输出名，不可直接批量运行 |
| 约14.9GiB的`tokyo_playable`与`tokyo_volume_preview`生成目录 | 不上传 | 大量重复与可生成资源，研究入口无需全量安装 |
| 新生成的`.res`、卫星瓦片、纹理库、原生中间层、数组缓存 | 不上传 | 保存制作代码与来源说明，不把实验产物全部入库 |
| `.godot`、Python缓存、导出程序、机器配置和凭据 | 不上传 | 可再生或与交接无关 |
| 关东OSM PBF原始下载 | 不上传 | 保留本地来源清单与SHA；从来源重新取得，历史快照不可用时须注明数据版本差异 |

已有Git历史中的资源继续保留；“不上传”指本次新增/变化的生成物，不删除本地文件或重写历史。`.uid`是稳定引用标识，保留；`.import`是导入设置，仅随本次实际包含的源文件保留。CSV是翻译真源，本次不提交可重新生成的`.translation`修改。

175号6份压缩二进制是有意保留的最小实物输入：它们固定控制/候选网格和mask，直接被现有测试读取。重新生成它们需要未包含的中间层与来源账，且当前临时脚本有输出版本漂移，不能把“理论上可重建”当成简单可再生缓存。其余整图二进制不随包上传。

## 下载与局部复现

```powershell
git clone --branch codex/map-handoff-2026-10-14 https://github.com/ppeerrmsk/AGL.git
Set-Location AGL
gh release download map-handoff-2026-10-14 --repo ppeerrmsk/AGL --dir tmp/handoff-download
```

先用`Get-FileHash -Algorithm SHA256`核对Release的`SHA256SUMS.txt`，再将`tokyo-map-repro-175-20261014.zip`解压到项目根。ZIP使用原相对路径，只包含选定`tmp/`证据和脚本；建议在新clone中操作，避免覆盖自己的同名实验。包内文件清单记录每个文件的大小和SHA256。

```powershell
Expand-Archive tmp/handoff-download/tokyo-map-repro-175-20261014.zip -DestinationPath .
python tools/prepare_map_handoff_175.py
$env:AGL_TOKYO_PARTITION_STREAM=(Resolve-Path tmp/map-handoff-175-replay/request.json).Path
$env:AGL_TOKYO_PARTITION_STREAM_SHA=(Get-FileHash $env:AGL_TOKYO_PARTITION_STREAM -Algorithm SHA256).Hash.ToLower()
# 若本机Godot不在bench默认位置，设置为自己的4.7+可执行文件。
# $env:GODOT='D:\path\to\godot_console.exe'
try { & bench/run.cmd tokyo_cells_lifecycle 1 180 Shadow Visual }
finally {
    Remove-Item Env:AGL_TOKYO_PARTITION_STREAM -ErrorAction SilentlyContinue
    Remove-Item Env:AGL_TOKYO_PARTITION_STREAM_SHA -ErrorAction SilentlyContinue
}
```

准备工具只核验与重绑定6份输入，并创建新输出目录；拒绝覆盖已有输出。它不安装正式地图、不启动引擎。实际运行仍遵循AGENTS中的锁、并发、内存、Shadow与运行时错误门。工具本身仅依赖Python标准库；原研究制作脚本另有NumPy/Shapely/osmium等依赖。

此ZIP提供175号输入完整性和重绑定能力；本次交接未在一台全新机器上完成Godot导入/GL重放。测试脚本的读回会同步GPU，不能用其耗时证明60FPS。175号也是逐姿态等待稳定测试，不能改称不停顿连续显示或正式F5验收。

## 不随包提供的整图重建

本快照不承诺一条命令重建完整当前地图。制作流程跨越多个历史候选，部分中间产物只在原机器上。请从[地图工程手册](../systems/map-volume-engineering.md)、[地图流水线](../reference/map-pipeline.md)和[当前实施计划](../planning/tokyo-resident-foundation-2026-10-01.md)确认目标分支，避免把旧命令全部重跑。

| 缺省产物 | 已有生产入口 | 必须补齐的依赖 |
|---|---|---|
| 原始地理源与分区 | `scripts/tools/build_tokyo_volume_region.py` | 精确PBF版本、bbox、关系/高度/海陆规则；包中保留build_manifest |
| 三层原生源与归档 | `scripts/tests/build_tokyo_region_archive.gd`、`scripts/tests/build_tokyo_regional_native.gd`及Script Index内原生导出入口 | 对应city/ground来源与配方，不能把三层当互斥LOD |
| HLOD及正式安装包 | `scripts/tests/stage_tokyo_incremental_package.gd`、`tools/install_tokyo_incremental.ps1` | 已验证目录、覆盖凭据、纹理/几何资源和SHA；不是从空目录直接生成 |
| 175控制/候选的重新生产 | ZIP内`tmp/tokyo_joint_patch_173.py` | 172身份账、164屋顶数据、统一来源及04_00/05_00原生attributes；本包只提供报告与冻结后的最终输入 |
| 沙漠、海洋生成资源与候选瓦片 | 各图spec、`tools/build_volume_desert_relief.py`及`scripts/tools/`对应制作器 | 各图源图/高程/导入流程；本次未打包这些生成结果 |

来源下载更新后，原SHA不匹配是有效失败，不能只改期望摘要来冒充旧基线。若研究需要重生产某一特定中间层，再按具体依赖补传；无需先搬运所有历史二进制。

## 交接验证边界

上传前执行文档链、代码锚点、玩家引用登记、Git空白检查以及证据ZIP逐文件摘要校验；另验证175准备工具的输入摘要、解压长度和拒绝覆盖。历史174的全量日志随包保留：102项零失败、生命周期90/0，同时仍有14个ObjectDB和7个资源退出告警。

本次不修改游戏运行时代码，也不重新宣称源码快照通过全量、Visual、全地图覆盖、完整局或性能验收。接手后的代码修改仍须focused→all和对应Visual验收。
