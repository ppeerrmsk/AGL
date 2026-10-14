# 2026-09-07 海洋群岛三维化验收

海洋图正式菜单默认启用三维地形和基地设施。按沙漠/东京湾的源数据审计、固定机位基线、分区迭代、原位复核、实战性能和终态回归流程完成四轮。行为合同见 [海洋三维地图规格](../specs/systems/ocean-volume-map.md)。原地图仍是原有 preview 玩法；本次没有添加战区、任务或 BOSS 流程。

## 成果与入口

- 主菜单 → 生存模式 → 海洋群岛 → 选机，自动加载；`AGL_OCEAN_VOLUME=off` 回退。源路径与 tile key 双重门控，自制地图不会误加载内置海洋布局。
- 原 16 栋设施、单跑道、原高度及布局作为源；完成装配楼、机库、发射架、塔台和储罐的静态体积、跑道标记与避障服务路。
- 30 张公开 Terrarium z11 原始瓦片配准到原母图，257² 高程输入、129² 固定几何面、146 个离线裁片；单一连续法线纹理避免远景露出三角网格。
- 地图颜色和瓦片纹理从原 Raster owner 借用。实战实际 13 个共享地形节点，21 个地图节点、19 个材质，未运行时构网。静止镜头通过停止重绘断言。
- 资源包约 1.61 MiB，高程 JSON 257994 字节，几何与法线数据预算实际 7767692 字节。数据重建 SHA256 为 `fb237e23e728e74b0fd46e8d0a14a33ccfa2851933da878f4e5f62669038dc2c`。

## 证据矩阵

所有运行通过 `bench/run.cmd`、Shadow 隔离副本、Godot 4.7.2 Steam。Visual 为 GL Compatibility 1600×900，测试全局静音。菜单测试和战斗测试使用 `tmp/ocean-volume/profile` 的隔离 APPDATA。

| 层级 | 最终结果 | 证据 |
|---|---|---|
| 离线来源/几何 | 165 断言通过；原文档/元数据/manifest Git diff 为空；重建 JSON SHA256 一致 | `tmp/ocean-volume/r1/focused-r4.log`、`build-r4.log` |
| Visual / 正式入口 | 13 机位，基线/默认新图、真实菜单、Tab、退出重进零失败 | `tmp/ocean-volume/r4/ocean_visual_manifest.json`；`ocean_r4_*.png` |
| 几何投影/生命周期 | 旋转误差 0.000046px，真实源删除跨 tick 后纹理清空、视口释放 | `tmp/ocean-volume/r1/all-r4.log` 的 Ocean lifecycle |
| 36 混合实战 30s | 36 成员、8km、8/8 巡航、14°；平均 203.05 FPS，P1 126.77，最差 60.60，低于 60 帧数 0 | `bench/results/ocean_volume_c1_20260906_171512.txt`；副本 `tmp/ocean-volume/r4/c1.txt` |
| FINAL WAR 35s | 完整原压力场与额外隐形敌机；8/8、14°；平均 167.31 FPS，P1 103.36，最差 66.50，低于 60 帧数 0，海洋层 active | `bench/results/final_war_ocean_stress_20260906_171430.txt`；副本 `tmp/ocean-volume/r4/final-war.txt` |
| 默认全量 | 98 项测试 / 0 失败；LifecycleGauntlet 90 / 0；wrapper exit 0 | `tmp/ocean-volume/r1/all-r4.log` |
| 静态文档 | 海洋代码锚点、玩家缓存登记、文档断链/spec 元数据/总表一致性、改动 diff 空白检查通过 | `tools/verify_doc_anchors.py`、`verify_player_ref_holders.py`、`verify_docs.ps1` |

## 迭代与实际限制

R1 建立原位结构与裁片。R2 添加工程场地后，审图发现两条服务路穿储罐；R3 修正绕行并加强真实山地光照，13 机位审图发现规则三角明暗；R4 改为离线连续法线，重新检查山地、岸线、基地和总览。R1–R4 日志位于 `tmp/ocean-volume/r1/`，逐轮截图以 `ocean_r1/r2/r3/r4` 前缀保存在 `bench/results/`；最终截图另存 `tmp/ocean-volume/r4/`。带 `_clear` 的额外截图临时隐藏天气，只用于几何和配色审查；同名无后缀图和战斗负载保留正常天气。

早期 R3 FINAL WAR 记录过 5 帧尖峰；关闭海洋层的对照（`final_war_ocean_stress_20260906_171348.txt`）仍有 1 帧尖峰，最差 49 FPS。最终 R4 两个规定负载均通过，但这不是任意机器或无限时长的帧率保证，也没有通过减少战斗参与者来通过性能门。

默认 all 退出仍有 14 个 ObjectDB 和 7 个资源警告，与早期同套全量结果相同；海洋真实菜单退出和节点回收断言通过，不代表全局泄漏清零。本次没有重新导出可执行包；导出所需的 JSON 和内嵌静态资源已采用数据指纹，避免依赖编译后不存在的 GDScript 源码。

当前 `reconstruction_complete: false` 保留对共享建筑原型/合成器合同的依赖；不把本轮地图视觉完成写成整个游戏地图或玩法重建已完备。

## 复跑

1. `python scripts/tools/build_ocean_elevation.py --output-dir tmp/ocean-volume/elevation` 只写临时目录；保留下载源 URL/SHA256。
2. `bench/run.cmd ocean_volume_build 1 120 Shadow Headless` 生成 `bench/results/ocean_volume.res`，验证后在无 bench 写锁时复制到资源目录。
3. `bench/run.cmd ocean_volume 1 120 Shadow Headless`。
4. 使用上述隔离 APPDATA，运行 `bench/run.cmd ocean_volume_visual 80 180 Shadow Visual`。
5. `bench/run.cmd ocean_volume_c1 30 150 Shadow Visual`，以及 `bench/run.cmd final_war_ocean_stress 35 160 Shadow Visual`。
6. `bench/run.cmd all 1 300 Shadow Headless`。
