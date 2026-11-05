# 2026-11-05 近期工作上传前验证

## 范围与结论

在 main 基线 `87848001e3781b6bfc79ef2e8d50ea616d10faf1` 上复核当前累计修改，涵盖东京地图流送与镜头、进化及状态界面、机体挂载、舰船避岸、场外增援、轰炸护送和入侵算法。用户授权验证后直接提交并上传源码。

功能专项、全量同步回归、真实生命周期与静态检查通过。默认 300 秒全量命令超时；同一测试以 900 秒有限上限重跑后退出 0。严格 60 FPS 未通过，人工 F5 完整护送、整局节奏以及重新制作导出发行包不属于本次已完成的证据。

## 本次验证

引擎为 Godot 4.7.2 Steam；所有引擎测试经 `bench/run.cmd`，Shadow 隔离，串行运行，保留静音、进程树回收与运行时错误门。测试期间未发现其它活跃项目测试，也未修改运行时源码；全量结束后只移除两个文件末尾的额外空行。

| 检查 | 本次结果 |
|---|---|
| `bomber_rotor_airburst 1 180 Shadow Headless` | 169 项通过，退出 0 |
| `offscreen_world 1 180 Shadow Headless` | 27 项通过，退出 0 |
| `zone_air_support 1 180 Shadow Headless` | 84 项通过，退出 0 |
| `invasion_algorithm 1 180 Shadow Headless` | 8 项通过，退出 0 |
| `naval_formation 1 180 Shadow Headless` | 21 项通过，退出 0 |
| `naval_zone_water 1 180 Shadow Headless` | 43 项通过，退出 0 |
| `volume_world 1 180 Shadow Headless` | 三维 focused 213 项通过，退出 0；包含真实网格与挂载检查 |
| `all 1 300 Shadow Headless` | 同步 105 组、失败 0；生命周期未完成即超时，退出 124 |
| `all 1 900 Shadow Headless` | 同步 105 组、失败 0；LifecycleGauntlet 100 项通过、失败 0；退出 0 |
| 玩家引用持有者、索引锚点、文档校验 | 全部通过 |
| shader / RID / timeout 错误门自检 | 全部通过；自检故意输出的错误样本不代表游戏运行失败 |
| 舰船净空与地面障碍二进制 | SHA-256 与各自 JSON 清单一致 |

全量日志无运行时致命诊断或退出资源泄漏报告。测试中的预期负例 warning（未知属性、缺失探针贴图和预加载超时回退等）保留，不据此更改错误门。

## 可视性能

两项均为 `30 180 Shadow Visual`，真实 GL Compatibility、正式三维表现开启，镜头巡检 8/8，维持约定人数。wrapper 均退出 0，但逐帧指标仍明确判严格性能未通过。

| 场景 | 引擎平均 FPS | 独立墙钟最长帧 | 墙钟超过 16.667 ms | 严格 60 FPS |
|---|---:|---:|---:|---|
| 36 人 / 8 km | 116.61 | 21.902 ms | 26 / 3147 | 未通过 |
| 48 人 / 24 km | 114.51 | 20.169 ms | 30 / 3091 | 未通过 |

这两轮不构成改动前后的配对性能比较，也不能替代东京地图连续操作或人工完整局验收；不据此宣称性能改善或毕业。

## 提交边界与证据

源码、规格、索引、审计及常规运行资源纳入本次提交。`resources/maps/tokyo_playable/` 与 `resources/maps/tokyo_volume_preview/` 按既有[独立地图分发规格](../specs/systems/tokyo-map-distribution.md)不入源码仓库；补入忽略规则，不删除本地文件。本次未重建、发布或上传东京独立 PCK。测试日志与临时实验产物留在 `tmp/` 和 `bench/results/`。

原始本次日志在 `tmp/upload-validation-20261105/`；[结构化验证记录](2026-11-05-upload-validation-evidence.json)保存命令退出码、日志摘要及两份可视性能报告的路径、摘要和完整核心指标。上传前重新检查暂存差异、静态门及远端主线，正常快进推送，不重写历史。
