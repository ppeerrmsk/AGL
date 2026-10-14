# 地图验收失败排查与修复 R4

结论：**两处确定缺陷已修复并验证；完整性能验收仍不通过。** 不改变地图资产、色调、AO、原生分辨率、4×地图MSAA、战斗人数、武器或伤害。未提交/推送Git。

## 1. 已修复的根因

### 正式菜单每退出一次遗留一个 Node2D

`SurvivorDebugSpawn._build_coord_hud` 提前分配 `_coord_axes`，但仅打开F5后才把它加入世界。整局不打开F5时，它始终无父节点；原面板没有退出清理，因此不随场景释放。

修复前真实菜单两次进入/退出，verbose重复报告2 CanvasItem RID及2 ObjectDB节点残留。`Node.get_orphan_node_ids()`与场景阶段记录将其定位为每次进入一个原生Node2D，而不是地图LOD网格。此API用法参考[Godot Node文档](https://docs.godotengine.org/en/4.5/classes/class_node.html#class-node-method-get-orphan-node-ids)，实测引擎为4.7.2。

修复：面板 `_exit_tree` 对仍有效的坐标轴执行queue_free并清空引用，兼容未入树与已挂世界的兄弟节点。不是遍历清除所有孤立节点。

验证：新增 `debug_spawn_lifecycle_case.gd`，真实SceneTree覆盖未打开、打开后整场退出、单独销毁面板，释放后跨两个process帧；三例零失败并接入默认all。修复后真实2D/3D菜单循环两次退出的orphan ID列表均为空；原2 RID/2 ObjectDB警告消失。游戏进行时仍保留待用坐标轴，不能把在局中的待用节点误判为退出泄漏。

### FINAL WAR 性能失败仍可返回成功

原测试依赖引擎delta统计且未将帧率指标转成失败退出码。新 `final_war_frame_probe.tscn` 继承完整正式Survivor场景，保持原FINAL WAR元数据、编成和巡航，仅加独立单调时钟及结果门。引擎慢帧或墙钟超16.667ms均返回失败；无样本也失败。GPU阶段诊断仅显式环境开关开启，正式复验不启用。

## 2. 复验记录

索引：`tmp/map-lod-acceptance/verify-r4-results.json`；脚本 `verify_r4.py`，逐场串行执行，首次失败即停止，不筛选重跑结果。

| 检查 | 结果 |
|---|---|
| focused lifecycle_gauntlet | 退出0，主门90/0，新增坐标轴3例0失败 |
| 真实菜单13视图/Tab/两次退出 | 退出0，fail=0，退出orphan=[]，原2/2泄漏告警消失 |
| `bench/run.cmd all 1 300 Shadow Headless` | 退出0，101组0失败，主生命周期90/0，新增3例0失败 |
| FINAL WAR第1轮36秒 | 引擎平均187.40 FPS、最差80.88；墙钟最差15.734ms，低于60帧数0；巡航8/8；退出0 |
| FINAL WAR第2轮36秒 | 引擎平均179.89 FPS、最差78.72、引擎慢帧0；墙钟最差**19.611ms、慢帧1**；巡航8/8；正确退出1 |
| FINAL WAR第3轮 | 因第2轮失败未执行 |

正式两轮原始结果为 `bench/results/final_war_ocean_stress_20260918_102637.txt`、`final_war_ocean_stress_20260918_102721.txt`。菜单日志为 `tmp/map-lod-acceptance/menu-r4-fixed.log`，完整回归为 `all-r4-fixed.log`。人工检查本轮 `bench/results/ocean_r4_base_065_clear.png`，未用此单张检查替代全部边缘或战斗验收。

## 3. 慢帧归因边界

前置诊断 `final_war_ocean_stress_20260918_100449.txt`：17.584ms墙钟尖峰，阶段记录中导弹根桶4.338ms、地图处理0.038ms。完整细分诊断 `20260918_100937.txt`：两帧墙钟尖峰，17.607ms时HUD武器区7.208ms；18.115ms时导弹根桶6.930ms。地图处理分别0.029/0.032ms。

这些是热点位置，不是已证明的最终根因。`after_draw` 包括下次process前的物理处理及其他等待，不能全部算GPU；异步后端读回不是同帧证据；音效请求未证明是这些尖峰原因。没有据此盲改声音、字体、导弹逻辑或降低画质。正式第2轮再次失败，证明不能用菜单泄漏修复来宣称卡顿已根治。

## 4. 保留的失败与下一步

- 全量测试仍报告14 ObjectDB/7资源退出残留，与菜单2/2问题分开，尚未定位；不宣称全项目无泄漏。
- 下一步应对正式墙钟失败保留同期更细的HUD文字布局、导弹处理与主线程等待证据，建立可重复反例，再做针对性性能改动；禁止只刷测试直到通过。
- 当前事件驱动版本40边缘快滚、完整长局、导出包尚未在本轮重验。R3剩余验收边界继续有效，spec保持in-progress。
- 本轮自身两次测试构建错误也保留：第一版FINAL WAR探针误用空Node2D场景，缺正式Camera2D等子节点，已改为继承完整场景；`fw-diagnostic-r4.log`为无效夹具失败，不能计入游戏性能。新增生命周期测试曾遗漏WeakRef显式类型，被严格编译门拦下并超时，修正后focused及all通过。不得把这两次失败解释为生产游戏回归。

## 5. 工序约束

仅通过bench wrapper运行Godot，Shadow隔离、单一owner锁、有限超时、错误门保持启用；运行期间未修改可扫描项目文件。新增 `AGL_BENCH_VERBOSE=1` 只追加引擎verbose参数。索引与玩家引用持有者检查通过，最终文档静态检查另以实际输出为准。
