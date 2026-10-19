# 地图交接证据目录

返回[研究与接手索引](../2026-10-14-map-upload-guide.md)。这里把核心证据变成GitHub上可直接阅读的文件；完整逐组数组、请求、冻结输入与临时制作脚本仍在[Release](https://github.com/ppeerrmsk/AGL/releases/tag/map-handoff-2026-10-14)的ZIP中。

这些都是已有实验的证据，不是本次新跑的结果。副本来源、SHA和转换方式见[provenance.json](provenance.json)。本目录的`.gitattributes`禁止JSON自动转换换行，保留证据摘要；内容仍是可读文本。文件内的本机绝对路径用于标识原始来源，不要求接手者照抄；175重绑定使用仓库工具。

## 先看当前实物

| 文件 | 关键事实与边界 |
|---|---|
| [175候选截图](175-candidate.png)、[同位原生控制](175-control.png) | 两张原始PNG副本。左侧候选、右侧原生，近景局部；不代表全图外观或美术认可 |
| [175-engine.json](175-engine.json) | 实际GL输出：24姿态、VSync/抗锯齿、面数、GPU通道与像素差。`full_map_qualified`、`peak_qualified`、`performance_qualified`均为false |
| [175-build.json](175-build.json) | 离线构建账：2048接受组、阻断源ID、各原生层保留面、10215候选屋顶面及20258侧墙面；候选总140949、控制140012 |
| [175-rebuild-inputs.json](175-rebuild-inputs.json) | 重新生产175的14项直接输入，逐项路径/大小/SHA/是否在ZIP；未包含12项共340990523字节。仅列直接依赖，不宣称整个制作链闭包 |

175原请求位于ZIP的`tmp/tokyo-complete-production-02/joint-boundary-175/request.json`，SHA256为`9e2d5e5635cb9b07b29a8a7469ad0bb625d2bf9a66268fb8dcea57f978027158`。网页引擎报告SHA256为`62aea9c3a3adc6de3d675fa03691165a40a5b68405524790ee9eaa291e410e44`。重绑定会产生新的请求摘要，原件保持不变。

## 成本、来源和验收反例

| 文件 | 证明什么 | 不能据此证明什么 |
|---|---|---|
| [164-summary.json](164-summary.json) | 最高密块2050组的屋顶概括总账，304220→203967面 | 完整楼体收益或其他255块收益；省略逐组`rows`，完整原件在ZIP |
| [172-summary.json](172-summary.json) | 23592栋匹配、2050组中2049组complete、组2031不完整、三层共存 | 所有源都可删除；175仍需共享来源阻断。省略`groups`，完整身份账在ZIP |
| [166-gpu-audit.json](166-gpu-audit.json) | 四段屋顶分别实际加载，合计2892226字节GPU载荷 | 同时驻留、元数据上传峰值、侧墙/地表/保护对象或性能 |
| [169-spatial.json](169-spatial.json) | 256空间格、98个surface/表、1322重复顶点；远档屋顶加地表242212面 | 细分后所有视野过预算；它也未验证实际GPU联合提交 |
| [155-resident-cost.json](155-resident-cost.json) | 特定8字节屋顶布局的乐观全u16三份费用仍达289618092字节 | 所有可能压缩表示都不可能装入192MiB |
| [140-texture-residency.json](140-texture-residency.json) | 旧纹理布局跨批去重后仍无法整体驻留 | 新几何方案的费用或所有地图表示的理论下界 |
| [138-camera-deadline.json](138-camera-deadline.json) | 正式相机没有拖拽速度上限，固定缓冲不能保证正的准备期限 | 选定慢速路线通过即可覆盖任意输入 |
| [174-all.log](174-all.log) | 历史all 102项零失败、生命周期90/0及wrapper0；同时保留14对象/7资源告警 | 新源码Visual合格、严格60FPS或全局退出干净 |

`164-summary.json`和`172-summary.json`明确列出原文件SHA、省略数组及原行/组数；它们是便读投影，不可拿摘要替代原始逐组身份审计。其余上表JSON按字节复制，未修改原字段。174日志网页阅读副本只清理行尾空白和末尾空行，内容顺序不变；逐字节原件保存在ZIP，两个摘要均记在provenance中。

## 全256块来源范围

| 文件 | 内容与正确用法 |
|---|---|
| [full-source-scope.json](full-source-scope.json) | 权威256块、旧31边缘集合及当时各块源/计划状态；`model_generation_complete`、`runtime_integrated`为false。52项旧计划缺口不是当前缺52块源数据 |
| [full-source-spool.json](full-source-spool.json) | 全图来源分片的manifest与摘要绑定；分片文件本身不在此目录 |
| [full-source-routes.json](full-source-routes.json) | 全图来源路由与ownership身份绑定；不包含所有源对象实物 |
| [权威瓦片目录](../../../resources/maps/tokyo_bay_detail_tiles_full.json) | 实际范围依据；SHA256：`9fddfbc1ef61728db3215b75bc0b4b01531ba50295de3f013a511208b0d2f741` |

这三份`full-source-*`是本次补充的本地原始metadata副本，**不在原Release ZIP里**。原`tmp/tokyo-bay-volume/r350-full-owned-source-a/ownership.json`共188835441字节，SHA256为`60aa2c9902c771e51c7a282f44c51fa8e17b6a3a4a4c45b80cc6a7f50b88b851`，未上传；需要逐对象审计时按该身份补齐。旧ZIP内`tmp/full_map_detail/build_manifest.json`选取203块，不能取代本节256块范围。

## 下载包与脚本定位

[archive-manifest.json](archive-manifest.json)列出ZIP的366项证据/脚本及摘要，也记录未上传的PBF身份。包内保留项目相对路径，解压方法和安全重放命令见[接手索引](../2026-10-14-map-upload-guide.md)。

| ZIP内入口 | 用途 |
|---|---|
| `tmp/tokyo_joint_patch_173.py` | 当前实际生成175的局部完整楼体制作器；不要按173文件名判断版本 |
| `tmp/tokyo_structural_tile_164.py` | 结构屋顶表示制作 |
| `tmp/tokyo_native_members_171.py` | 来源匹配与原生替换成员分析；版本以ZIP摘要为准 |
| `tmp/tokyo_tile_batches_165.py`、`tmp/tokyo_tile_gpu_audit_166.py` | 屋顶分段与GPU布局审计 |
| `tmp/tokyo_triangle_spatial_169.py` | 保留三角形的空间分组及成本反例 |
| `tmp/tokyo-complete-production-02/` | 各编号报告、请求、截图和日志；先查manifest再取具体文件 |

临时脚本部分使用NumPy/Shapely/osmium等库，且可能硬编码旧输出目录；它们用于保存现场和研究，不应批量执行。完整生产依赖尚未打包锁定，准备工具的标准库依赖也不能代表所有制作脚本依赖。
