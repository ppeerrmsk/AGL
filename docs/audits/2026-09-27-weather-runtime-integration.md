# 动态体积天气实装与性能验收

用户已批准将认可的动态云/沙尘样板接入真实天气。当前实现保留 opt-in；尚未通过严格实战帧门。

## 实装

- `weather_density_presentation.gd` 接替 opt-in 旧壳体渲染器，共享地图/机体的现有三维视口。`play_weather_volume.cmd` 可进入正式游戏试用；关闭该启动窗口对应的游戏后，普通入口仍沿用原默认配置。
- 云读取 WeatherSystem 云空间的32×32密度遮罩，包含UGC mask。共享64³噪声，不规则云体按块独立28–52秒形变；实际位置跟随源风偏移，剔除包围盒由节点变换同步。缓存最多96块，每帧最多生成2块。
- 云的厚度、内部起伏、点阵与扫描光由GPU完成。CPU仍有分块采样和参数同步成本，不宣称零CPU。
- 沙尘暴读取正式活动状态、中心、宽度、左右方向和曲边公式；前缘隆起、后方低雾及128飞沙同步显示。形变读取天气时钟，暂停不继续漂移。
- 噪声异步生成前保留二维，关闭/释放恢复二维。规则/命中/传感器遮蔽不改；可见体积是密度场的抽象表达，云团之间的视觉空隙不能作为无战斗遮蔽的保证。
- 透明三维视口采用预乘alpha合成；云区实例使用24步，远档16步，无动态阴影、额外灯光或常驻新增视口。

## 已验收

- `runtime-focused.log`：weather focused，wrapper 0。
- `runtime-lifecycle-final.log`：旧/新渲染器均0失败；新实现覆盖异步初始化、配置修订/清空云、关闭/重开、owner释放以及源先释放。wrapper 0。
- `runtime-visual.log`：真实Survivor沙漠/海岛，云近景、远景、密度边缘与沙尘锋面；三种材质各实际预热2帧，暂停检查通过，wrapper 0。
- 实机截图：`bench/results/weather_volume_desert_railway_cloud.png`、`weather_volume_desert_railway_storm_front.png`、`weather_volume_ocean_islands_cloud.png`。
- 文档链接/登记检查通过；两份天气索引各38个强锚点通过。

## 性能门

计划使用 `volume_map_3d_c1/c2 30 180 Shadow Visual`，开启实际沙尘暴，每场景三组成对 on/off，要求8/8巡检、保留36/48混合演员及武器反馈。GPU后端计时另测，不能混入FPS门或与CPU时间相加。

本轮排队前发现 Mechabellum（PID42808）仍占用约43% GPU 3D引擎；当时 Godot 仅运行Headless全回归，独立GPU总利用率65–70%。因此暂停正式性能矩阵，未关闭用户游戏，等待其空闲或用户选择记录受干扰参考样本。不得使用上轮四云小场景的约120FPS冒充本次实战结果。

最终全量 `runtime-all-final.log` wrapper 0：101项测试0失败，LifecycleGauntlet 90通过/0失败；已包含异步源释放保护补丁。日志保留Desert预加载回退、退出14个ObjectDB/7个资源占用诊断，不宣称零警告。用户已退出 Mechabellum，以下12次正式样本均在其退出之后采集。默认开关保持关闭，未宣称60FPS验收通过。


## 三组成对实战结果

RTX 3080 / Godot 4.7.2 GL Compatibility，同一代码版本、真实沙漠三维地图、沙尘暴活动。C1保持36演员/8km，C2保持48演员/24km；全部镜头8/8巡检。保留AI、武器、弹丸、伤害和标签，自然交战导致各次弹丸数量不同，不宣称逐帧内容完全相同。off使用原二维天气，on使用新密度天气。

平均FPS与1%低帧取三次中位数；最慢帧取三次最差。引擎delta与墙钟分别列出，不能只看前者。

| 战场 | 天气 | 平均FPS | 1%低帧FPS | 引擎最差FPS | 墙钟最差ms | 各次墙钟低于60帧数 |
|---|---|---:|---:|---:|---:|---|
| C1 36单位 | 原二维 | 119.26 | 110.00 | 63.46 | 20.703 | 15 / 24 / 15 |
| C1 36单位 | 新体积 | 119.59 | 110.00 | 60.05 | 20.041 | 11 / 6 / 11 |
| C2 48单位 | 原二维 | 114.50 | 78.92 | 40.80 | 37.060 | 29 / 33 / 49 |
| C2 48单位 | 新体积 | 119.35 | 110.00 | 63.42 | 21.719 | 9 / 11 / 26 |

新体积的6次wrapper均0，引擎计数frames_below_60均0；C2原二维第2、3次因引擎各1帧低于60返回1，保留失败样本，没有重跑覆盖。所有12次墙钟仍有超预算帧，因此严格60FPS门未通过。当前证据支持没有平均FPS回退、C2表现改善；不支持零开销、任何硬件均稳定60、完整局已验收。

新天气最终可见云块C1=8/C2=12，缓存16/24，pending=0，24步，storm=true、grit=128；单块构建峰值C1=0.746–0.771ms，C2=0.766–0.814ms。这是单块构建峰值，不是每帧CPU平均增量。冷启动与长局内存回收、低端硬件、东京地图、超过28k跨度触发的远档仍未完成专项验证。

### 样本索引

- `runtime-volume_map_3d_c1-off-1` → `bench\results\volume_map_3d_c1_20260927_063009.txt`。
- `runtime-volume_map_3d_c1-off-2` → `bench\results\volume_map_3d_c1_20260927_063127.txt`。
- `runtime-volume_map_3d_c1-off-3` → `bench\results\volume_map_3d_c1_20260927_063245.txt`。
- `runtime-volume_map_3d_c1-on-1` → `bench\results\volume_map_3d_c1_20260927_063048.txt`。
- `runtime-volume_map_3d_c1-on-2` → `bench\results\volume_map_3d_c1_20260927_063206.txt`。
- `runtime-volume_map_3d_c1-on-3` → `bench\results\volume_map_3d_c1_20260927_063324.txt`。
- `runtime-volume_map_3d_c2-off-1` → `bench\results\volume_map_3d_c2_20260927_063403.txt`。
- `runtime-volume_map_3d_c2-off-2` → `bench\results\volume_map_3d_c2_20260927_063522.txt`。
- `runtime-volume_map_3d_c2-off-3` → `bench\results\volume_map_3d_c2_20260927_063755.txt`。
- `runtime-volume_map_3d_c2-on-1` → `bench\results\volume_map_3d_c2_20260927_063443.txt`。
- `runtime-volume_map_3d_c2-on-2` → `bench\results\volume_map_3d_c2_20260927_063716.txt`。
- `runtime-volume_map_3d_c2-on-3` → `bench\results\volume_map_3d_c2_20260927_063835.txt`。


## 独立GPU后端诊断

下列四次启用AGL_VOLUME_RENDER_TIMING=1，单独运行，不混入上述12次FPS门。每组2969–3215样本，非零GPU计时完整，无跳帧/非法计时。GPU和CPU均为整视口渲染后端异步计时，不能相加成单帧，也不能把差值精确归因为云层本身。

| 场景 | 天气 | GPU平均ms | CPU后端平均ms | 可见3D draw平均 |
|---|---|---:|---:|---:|
| volume_map_3d_c1 | off | 2.2718 | 2.2634 | 31.72 |
| volume_map_3d_c1 | on | 1.9904 | 1.5413 | 37.47 |
| volume_map_3d_c2 | off | 2.6093 | 2.6796 | 26.71 |
| volume_map_3d_c2 | on | 1.9987 | 1.4074 | 35.68 |

- `runtime-gpu-volume_map_3d_c1-off` → `bench\results\volume_map_3d_c1_20260927_063917.txt`。
- `runtime-gpu-volume_map_3d_c1-on` → `bench\results\volume_map_3d_c1_20260927_063957.txt`。
- `runtime-gpu-volume_map_3d_c2-off` → `bench\results\volume_map_3d_c2_20260927_064038.txt`。
- `runtime-gpu-volume_map_3d_c2-on` → `bench\results\volume_map_3d_c2_20260927_064118.txt`。

结论：本机所测合同没有平均FPS回退；保留24步质量，无需依据当前数据降低云体细节。但墙钟严格帧门尚未通过，故维持可选试用而非默认开启；未将诊断差值或单一RTX3080结果推广到其他硬件。
