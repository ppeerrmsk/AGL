# 云体密度shader实机验证

## 范围

用户接受“淡云体＋表面点阵＋局部扫描线”的概念方向，并要求在引擎验证动态、厚度变化和不同尺寸，明确允许shader。本轮只做可实现性样板，不替换默认天气，不修改WeatherSystem、战斗或地图规则；固定示意云区与正式天气判定尚未绑定。IN CLOUD仍来自原天气，不能拿HUD状态证明示意云体的判定边界。

## 实现

- `AGL_WEATHER_DENSITY=1`，通过`bench\run.cmd weather_volume_visual 1 180 Shadow Visual`进入。
- 共用一张64³无缝FastNoiseLite噪声体纹理（固定seed 270927、frequency 0.075、4 octaves）；四个包围盒中做GPU三维密度采样，不是平移静态云图片。
- 四组半尺寸分别为(1850,520,900)、(1450,620,750)、(1100,380,600)、(630,250,340)，独立相位；密度体由四个平滑连接的团块与三尺度侵蚀组成。
- 统一weather_time驱动缓慢漂移、局部高度弯曲、厚度变化及噪声演变。点阵和断续扫描纹样在shader生成。没有逐粒CPU更新；CPU在验收协程中只更新四个材质时钟。
- 默认24步，另测16步。只有48个包围盒三角形，但主要成本是屏幕覆盖像素×体采样次数，不能用低面数冒充低GPU成本。
- 海岛云体经过透明SubViewport，样板临时使用预乘alpha合成材质，消除二次乘alpha暗边；退出恢复原材质。沙漠直接进入不透明视口，不需要额外合成材质。没有修改正式合成器。

## 证据与验收口径

- `bench/results/weather_density_desert_railway_still.png`、`weather_density_ocean_islands_still.png`：真实Godot GL Compatibility、真实地图/单位/HUD，未后期重绘。
- `weather_density_desert_railway_000.png`至`095.png`：固定场景，显式推进0～11.875秒的云时间；用于动态展示而非帧率测量。
- `weather_density_motion.gif`：上述96帧编码，8帧/秒采样，12秒循环；循环末尾时间重置。GIF采样率不代表运行帧率。
- `weather_density_*_steps16.png`：同一时相降低到16步后的画质比较。
- 独立的不含截图读回计时：每地图按off/24步/16步/off，预热30帧、记录120帧；GPU、渲染CPU、平均FPS、最差帧与低于60帧数分开记录于`weather_density_*_timing.json`。GPU和CPU后端计时异步，不能相加当单帧耗时。
- 冻结时钟后检查云区两帧像素一致，避免错误地用不响应暂停的TIME驱动。

## 限制

实机已能看见不同尺寸、厚薄、局部侵蚀与漂移，但比AI概念图更碎、云顶明暗更粗，点阵有局部扭曲，尚未做到同等大块柔和体积感。仅四片云的静态机位，未通过36混合战斗单位、近景最大覆盖、相机巡检、完整局及低端GPU验收。当前RTX 3080上约毫秒量级的云渲染增量，也未达到原spec GPU净增量0.3ms目标，保留默认关闭和in-progress。

## 最终focused结果

`tmp/weather-volume/density-preview-final.log`：Visual wrapper 0；两图冻结云区像素一致；沙漠确认直接不透明根视口、海岛确认AircraftVolumeComposite预乘合成。仅有系统证书存储错误，没有样板合成查找错误或SCRIPT ERROR。96帧GIF已重新编码，12秒、13,546,170字节。

RTX 3080，1600×900，单次短对照（单位毫秒，GPU为整视口后端耗时）：

| 地图 | off前 | 云24步 | 云16步 | off后 | 最差帧（全部采样） | 低于60帧数 |
|---|---:|---:|---:|---:|---:|---:|
| 沙漠 | 1.307 | 2.496 | 2.026 | 1.542 | 8.424 | 0 |
| 海岛 | 0.564 | 2.054 | 1.903 | 1.187 | 8.429 | 0 |

平均FPS约120。前后基线有漂移，不能把差值解释成稳定精确成本；相对于前后基线平均，24步增加约1.07/1.18ms，16步约0.60/1.03ms。上述仅局部成本诊断，不等于C1代表性负载合格，更不等于低端硬件结论。

文档链接/元数据通过，两份天气索引各27个强锚点通过。默认`all 1 300 Shadow Headless` wrapper 0，日志`tmp/weather-volume/density-all.log`。仍有Desert preload timeout回退、退出14个ObjectDB/7个资源占用及系统证书存储诊断，不宣称零警告；这项Headless回归不提供实战GPU性能结论。
