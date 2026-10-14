# 当前完整运行地图：下载、安装与性能问题复现

本页补齐原交接包缺少的**当前实际运行地图**。入口仍是项目设置指定的`res://resources/maps/tokyo_playable/m20/package.json`，没有换地图、优化几何、调整相机或更改渲染设置。返回[研究与接手总索引](2026-10-14-map-upload-guide.md)。

这里的“完整”指当前安装的M20运行依赖闭包，**不代表新的结构概括路线已经覆盖全256块或通过验收**。175包仍是单独的近景实验；重现正常游戏里的卡顿、镜头切档和跨区问题，应先安装本页M20包。

## 1. 下载哪一组

在同一个[map-handoff-2026-10-14 Release](https://github.com/ppeerrmsk/AGL/releases/tag/map-handoff-2026-10-14)下载：

| 文件 | 用途 |
|---|---|
| `tokyo-m20-runtime-20261014-part01.zip`至`part09.zip`，全部9份 | 当前M20几何、纹理、原生组件、目录、覆盖凭据及必要的3D入口归档 |
| `tokyo-m20-runtime-20261014-manifest.json` | 每个安装路径、大小、SHA256、所属分包和Git前置依赖；安装工具读取此文件 |
| `tokyo-m20-runtime-20261014-SHA256SUMS.txt` | 上述附件的外层摘要；与旧175的`SHA256SUMS.txt`是两份文件 |

9个ZIP合7077209021字节，manifest另30081720字节；合计约6.6GiB。安装新增7724179951字节，约7.2GiB。下载、安装及Shadow测试副本同时存在时建议预留至少30GiB磁盘空间；测试还需满足既有7.5GiB空闲RAM门槛。

ZIP里按SHA保存载荷，**不要用Expand-Archive直接解压到项目根**：那只会得到`blobs/`，不会安装地图。请用下面的工具恢复manifest中的真实路径。同一内容只存一份；不能因目录名字相似手工省略分包。

| 固定身份 | 值 |
|---|---|
| 运行源码基线 | `cf5d2a86341300e5138028ccc3b527b96bfba479`；本次比较1036个运行时代码/配置文件，无差异 |
| M20 package SHA256 | `424e4aa1db195308389ffcce30ff672bc5b23851810801847199b4d9d572d858` |
| runtime manifest SHA256 | `67b3983211c200698452b0165fd39f7f441803e538641a6c0a3a2f8790226ca4` |
| 安装清单 | 107108个文件：106811个Release载荷＋297个Git前置文件；包括146张正式lossless WebP底图瓦片 |

运行源码在上述基线；新增安装/复现工具和本页位于`codex/map-handoff-2026-10-14`分支的新提交。Release旧tag仍固定175基线，**不要下载GitHub自动生成的Source code ZIP后就以为有全部新工具/地图**。

各分包的大小、摘要和GitHub下载链接也汇总在[运行包交付记录](map-evidence-20261014/m20-runtime-delivery.json)，可先在网页查看，无需打开30MB逐文件manifest。

## 2. 干净检出与安装

需要Git、GitHub CLI（或网页手动下载）、Python **3.11+**、Godot **4.7+**。本机原路径使用Godot 4.7.1 Steam版与GL Compatibility。不要用4.6.2；工具不随包分发引擎、Python库或缓存。

```powershell
git clone --branch codex/map-handoff-2026-10-14 https://github.com/ppeerrmsk/AGL.git
Set-Location AGL
gh release download map-handoff-2026-10-14 --repo ppeerrmsk/AGL --pattern 'tokyo-m20-runtime-*' --dir tmp/m20-download
python tools/install_tokyo_map_handoff.py --bundle tmp/m20-download --manifest-sha256 67b3983211c200698452b0165fd39f7f441803e538641a6c0a3a2f8790226ca4
if ($LASTEXITCODE -ne 0) { throw '安装未完成，先检查错误，不启动游戏。' }
```

安装时关闭Godot。工具先核验manifest、所有ZIP及解压载荷，确认Git依赖齐全后才写地图；使用项目bench锁，拒绝覆盖任何内容不同的现有文件。已经相同的文件跳过，可在相同包上继续未完成安装。安装失败时保留隔离标记，完整恢复后才解除，防止半套资产被编辑器扫描。

只核验、不安装可加`--verify-only`。其输出`missing_before_install`表示资源尚未落盘的数量；即使ZIP全都合格，缺失数量非零也不表示已安装完毕。

安装完成后用Godot 4.7+打开`project.godot`，等待第一次导入结束。此过程会在本机生成`.godot`、全局类缓存、翻译与贴图导入缓存；这些不应从制作者电脑复制。随后关闭编辑器，再跑下面的受保护Shadow复现。首次导入与首次shader编译的开销要单独记录，不混作已热身运行的性能结论。

## 3. 固定复现入口

[复现工具](../../tools/run_tokyo_map_handoff.ps1)先验证M20 package及必要的3D入口文件，清除调用进程继承的AGL实验开关，显式绑定本包，再调用原`bench/run.cmd`。结束后恢复原环境。输出写入新的`tmp/map-runtime-repro/<时间戳>-<场景>/`，不覆盖旧实验。

```powershell
# Godot不在原机器默认位置时，传自己的4.7+可执行文件。
powershell -ExecutionPolicy Bypass -File tools/run_tokyo_map_handoff.ps1 -Scenario C1 -Duration 36 -Godot 'D:\path\to\godot_console.exe'
```

若`GODOT`环境变量或bench默认位置已正确，可以省略`-Godot`。一次只运行一个场景；保持窗口前台、不最小化，并记录窗口尺寸、显示器刷新率和后台负载。

| `-Scenario` | 测试入口与用途 |
|---|---|
| `C1` | `tokyo_volume_c1`，36名混合海陆空的真实战斗负载；先跑它确认地图与战斗同时存在 |
| `C2` | `tokyo_volume_c2`，48名广域24km战场；观察广域选择、地图与战斗共同成本 |
| `Near` | `tokyo_volume_near`，既有近景镜头节拍与真实战斗；观察原生楼体/切档 |
| `FastWest` | `tokyo_cells_lifecycle`→正式Loading/Survivor路线→west快速相机输入重放；建议`-Duration 48` |
| `FastNorth` | 同上，north区域；建议`-Duration 48` |

FastWest/FastNorth沿既有诊断使用60Hz输入节拍及相应回放上限，输出记录完整环境；不能用其固定节拍结果代替C1/C2的独立墙钟性能判定。测试末尾截图与测量过程分开；本工具不开启175图像读回探针，也不启用关VSync、删战斗负载或扩大内存预算等实验开关。

**保留实际设置再研究性能：** 当前M20路径继承`TokyoVolumeOverlay`中的`MSAA_4X`；175局部fixture使用2×MSAA。两者不是同一条路径。本包保存实际状态，不为迎合交接目标的2×口径而先改运行时；比较时必须记录实际抗锯齿、VSync和输出分辨率。目标约束仍按[规格302](../specs/systems/tokyo-bay-volume-map.md)裁决。

手动正常F5也使用同一M20 package：主菜单进入东京湾，拖拽跨区并从远景缩到近景。手动录屏/操作日志应记录起止位置、缩放、是否刚加载、具体卡顿或缺图时刻；C1/C2是固定比较负载，不宣称与每台电脑的手动操作得到完全相同FPS。

## 4. 怎样确认测到的是同一个问题

先检查`tmp/map-runtime-repro/.../request.json`中的package摘要和环境，再看`wrapper.log`及`bench/results/`本次生成的结果文件：

- 地图状态应出现`hlod=true`、`active=true`，并有实际页、几何/纹理加载计数；`volume=true`本身不够。缺资产、2D回退、空图或加载失败不能算性能通过。
- C1/C2/Near读取`tokyo_wall_clock`中的`samples`、`avg_fps`、`worst_fps`、`max_ms`、`below60`，以及`tokyo_wall_percentiles`。严格门要求有效采样且`below60=0`，不要只报告平均FPS。
- 同时保留地图选择耗时、提交面数、stream峰值、等待/缺口统计、VSync、窗口/输出尺寸、实际战斗单位及运行/退出错误。
- Fast路线看`route/report.json`中的相机输入覆盖、`live_display`、墙钟样本和资源释放；`map_preview_only`或`combat_verified=false`不能改称完整局验收。
- wrapper退出1可能是正在复现的性能/覆盖失败；86是运行时错误门失败，124是超时。保留失败现场，不能改阈值或只看Godot原始退出0。

回传至少包括源码提交号、package与manifest摘要、Godot/GPU/驱动、显示配置、该次request/result/wrapper日志、bench结果文本，以及问题瞬间截图或录屏。比较优化前后时沿用同一包、区域、负载和镜头条件。

## 5. 这次保留与排除的内容

保留M20 package引用的所有档位和覆盖凭据；这些档位都是当前运行依赖，不能按“旧LOD”删除。还保留`tokyo_volume_preview/downtown_lod.res`，因为当前3D启用条件会检查它存在；缺它会使正常路径退回2D。该归档以外的预览实验资源没有一起打包。

排除其他安装版本、顶层旧assets/native重复库、resident候选目录、未被引用的预览资源、OSM/PBF、离线重建中间层、旧探针产物、导出程序及Godot/shader/import缓存。底图146张WebP与导入设置已经在源码分支，manifest将其列为前置文件，没有再次放入ZIP。

这个包使接手者可以运行当前M20，不等于交付全部地图生产链。修改175的生成算法所需325.2MiB直接输入仍属于另一项制作需求，见[总索引的重建缺口](2026-10-14-map-upload-guide.md#7-已提供什么还缺什么)。

## 6. 本次验证边界

已完成：从当前入口递归读取JSON、Godot压缩资源和二进制metadata中的资源路径；排除48752个逻辑页身份；核对4101处JSON绑定；对齐1036个运行时代码/配置；核验所有载荷与已安装源文件的SHA；检查分包内容、路径和安装工具的拒绝覆盖行为。

这轮没有修改游戏运行时代码。本机打包时空闲RAM低于项目7.5GiB门槛，因此未启动新的Godot/Visual性能测试，也没有宣称完成另一台机器的GL重放或性能验收。请用上面的固定入口生成接手者机器上的证据；原175和历史性能报告都不能冒充这次重测。

生产工具与安装工具分开：下载者只需要仓库内标准库安装工具，不需要制作者用于读取RSCC的zstandard包。分包遵循[GitHub Release单文件限制](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas)，不会把这些生成资源提交到Git历史。
