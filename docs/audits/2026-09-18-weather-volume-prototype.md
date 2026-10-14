# GPU 天气样板：实现与验收记录

2026-09-18。对应[天气三维表现规格](../specs/systems/weather-volume-presentation.md)。用户授权先做样板并尽量使用GPU。当前为可试用、默认关闭的in-progress版本，未宣称严格60 FPS完成。

## 实际实现

- 云为同源密度场裁切的分块三维切面表面；加载/跨块时CPU生成少量网格，GPU执行风漂和起伏。固定世界格点扰动减少方格感，相邻块共边同源；远景扩大网格尺度并保留覆盖。
- 沙带使用原曲边、中心、宽度和方向生成立体前缘及风带。纹样滚动、表面起伏、128个飞沙实例的运动/显隐均在shader执行；无逐粒子CPU tick、无粒子碰撞。
- 复用地图/飞机三维视口；没有新增常驻全屏合成层、实时云影或体积雾。三个32×32临时预热视口只在初始化绘制两帧后释放，实际普通Mesh/MultiMesh变体均验证rendered=true。沙带网格提前准备。
- WeatherSystem仍拥有天气密度、时间、UGC配置和按高度战斗效果。修复暂停时天气时钟仍推进；配置使用整数版本，无逐帧mask哈希。
- GPU位移同步CPU剔除包围盒；关闭三维合成恢复二维天气；源释放后隐藏代理，退出时只撤销自己的owner。

## 试用

运行仓库根目录 `play_weather_volume.cmd`，它只为本次正常游戏进程设置 `AGL_WEATHER_VOLUME=on`，沿用已有游戏启动器。正常入口默认仍为二维天气；`AGL_WEATHER_VOLUME=off`显式回退。沙漠F6“跳到半局”可直接定位风暴中段。

最终画面：
- [海岛近景](../../bench/results/weather_volume_ocean_islands_cloud.png)
- [海岛远景](../../bench/results/weather_volume_ocean_islands_cloud_far.png)
- [沙漠云层](../../bench/results/weather_volume_desert_railway_cloud.png)
- [沙尘锋面](../../bench/results/weather_volume_desert_railway_storm_front.png)

当前艺术表现为克制、半透明的低多边形云面和低矮沙带，仍需用户实玩评估厚度与轮廓；不把截图当作完整局验收。

## 自动与Visual验证

Godot 4.7.2 Steam、GL Compatibility、RTX 3080、1600×900，全部由bench/run.cmd Shadow启动。测试缓存使用独立 `tmp/weather-volume/profile`，未修改用户常规设置。

- `weather 1 180 Shadow Headless`：PASS，0 fail；原云量、LOW-only、真实Aircraft/MissileManager状态及新增几何确定性/预算通过。
- `weather_volume_lifecycle 1 180 Shadow Headless`：0 fail；真实树中关闭、恢复、代理释放、源释放后跨帧消费者通过。
- `weather_volume_visual 1 180 Shadow Visual`：最终PASS；沙漠/海岛真实Survivor合成、近远镜头、旋转、暂停、换图，三种材质两帧实际预热通过。初次暂停反例曾失败，修复源时钟后复测通过；初次owner缺失元数据错误也已修复，不用wrapper退出0掩盖原诊断。
- `all 1 300 Shadow Headless`：最终wrapper0；同步101项测试0失败，LifecycleGauntlet 90/0，天气释放场景同时由默认生命周期链调用。预热前后各一次全量通过。
- 文档登记、元数据、玩家引用持有者检查通过。新增索引锚点按最终代码刷新并校验。
- 全量保留既有退出资源警告与证书存储环境诊断，不能据此宣称无泄漏。

原始过程日志在 `tmp/weather-volume/`：`focused-final.log`、`lifecycle-final.log`、`visual-final.log`、`all-prewarmed.log`。场景性能结果保存在 `bench/results/`。

## 性能：未通过严格零掉帧门

C1/C2都使用同一沙漠三维地图、天气种子、正式混合战斗和巡检镜头，只切天气渲染。`AGL_WEATHER_STORM_TEST=1`仅在测试适配器设置同一正式Debug中段风暴；双方天气效果一致。全部完成8/8镜头段，保留武器、伤害、弹丸和反馈。

| 场景/天气 | 结果时间戳（UTC） | avg FPS | p1 FPS | worst FPS | 引擎<60帧 | 墙钟超16.67ms帧 / 最大ms |
|---|---|---:|---:|---:|---:|---|
| C1 GPU A，初次缓存 | 131424 | 119.75 | 120.00 | 30.05 | 1 | 1 / 53.280 |
| C1 旧天气 A | 131517 | 118.60 | 110.00 | 73.33 | 0 | 29 / 21.706 |
| C1 GPU B | 131650 | 119.95 | 120.00 | 73.04 | 0 | 1 / 17.611 |
| C1 旧天气 B | 131728 | 118.78 | 109.34 | 76.88 | 0 | 23 / 21.537 |
| C1 GPU C | 131807 | 119.89 | 120.00 | 76.89 | 0 | 2 / 18.136 |
| C1 旧天气 C | 131845 | 119.70 | 110.00 | 92.57 | 0 | 7 / 19.985 |
| C2 GPU | 132049 | 119.40 | 110.00 | 73.37 | 0 | 10 / 21.024 |
| C2 旧天气 | 132127 | 118.20 | 91.07 | 73.00 | 0 | 23 / 20.771 |
| 最终预热版 C1 GPU | 132756 | 119.97 | 120.00 | 89.76 | 0 | 1 / 17.607 |

原始文件格式：`bench/results/volume_map_3d_c1_20260918_<时间戳>.txt`（C2换为c2）。三组成对C1平均FPS中位数：GPU119.89、旧天气118.78；这是120 FPS上限下的整体样本，不是GPU耗时节省百分比。最终预热改动后只补了一次C1，不能替代新的三组成对冷/暖矩阵。

最终C1样本末帧：8个可见非空云块、589云面、2048沙带面、128飞沙三角形；单块构建峰值453µs。该计数不是全地图最坏上限，也不是GPU时间测量。

尚欠：尖峰原因定位、最终版三组C2/冷启动/首次风暴转场、东京Visual、12–20分钟完整局、独立CPU/GPU净增量与资源峰值。现有基线也有墙钟超预算，但不能因此豁免新路径。保持默认关闭，不把较高平均帧率当成严格60 FPS完成。
