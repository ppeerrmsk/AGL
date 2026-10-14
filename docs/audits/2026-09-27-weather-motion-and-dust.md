# 云层独立动态与沙尘体积锋面

用户认可密度shader方向，要求各云持续循环活动、随时间移动、形状各异，并加入沙尘暴特效。本轮继续在独立实机样板验证，不改变正式天气权威或默认开关。

## 实现

- 云：四个不同尺寸，28/35/43/52秒形变周期，独立噪声相位、团块位置/比例、漂移速度；体内采用闭合噪声采样轨迹，局部伸展、变厚和边缘侵蚀持续发生。漂移不随形变周期跳回。
- 循环检查：关闭漂移，只显示第一片云，对比0秒和28秒的同一云区像素，平均字节误差阈值0.02；这检查形变接缝，不把动图播放末尾的重置算作shader接缝。
- 沙尘：三维密度锋面，18秒噪声翻卷；厚前缘、波浪边界、逐渐压低/消散的后侧尘雾。示意锋面向前25px/s，对应现有180km/h速度。另加128个GPU实例飞沙，以独立相位进入/淡出后循环，避免逐粒CPU tick。
- 两类体积共享密度shader和噪声资源；仅在沙尘分支选择暖灰棕配色与锋面形状，关闭云的扫描点阵。云使用16/24步对照，沙尘同样测试。
- 样板仍使用固定包围盒，没有接入全地图天气分块、实际密度判定、无限时间的回收或生产LOD。当前包围盒/culling只覆盖本次短时展示，不能直接当作正式长局实现。

## 复现与产物

云：`AGL_WEATHER_DENSITY=1`，运行`bench\run.cmd weather_volume_visual 1 180 Shadow Visual`。

沙尘：同上再加`AGL_WEATHER_DUST=1`，仅跑沙漠机位。

- `bench/results/weather_animated_cloud_motion.gif`：云层12秒实机采样动画。
- `bench/results/weather_dust_motion.gif`：沙尘12秒实机采样动画。
- 同目录`weather_animated_cloud_desert_railway_still.png`、`weather_animated_cloud_ocean_islands_still.png`、`weather_dust_desert_railway_still.png`：全分辨率截图。
- 每段96张原始PNG，0.125秒一个时相；GIF按8帧/秒编码，不代表游戏运行帧率，播放末尾会重置12秒展示片段。没有AI重绘或后期添加特效。
- `weather_animated_cloud_*_timing.json`、`weather_dust_*_timing.json`：独立于截图采集的短时off/24/16/off诊断；前后各30帧预热，每组120帧。GPU/CPU后端计时不可相加当作单帧时间。

## 验收边界

小场景证据仅证明动态与可实现性。云和沙尘分别渲染，尚未证明同时覆盖战场的成本；36混合单位实战、满屏云、相机巡检、长局回收与低端硬件性能仍未验收。目标仍为60FPS硬底线，不得用这些样板代替正式性能门。

## 本轮实机结果

- `tmp/weather-volume/dynamic-cloud-final.log`：两地图Visual wrapper 0；冻结检查通过；云周期接缝平均字节误差0.00004783，远小于0.02阈值。
- `tmp/weather-volume/dynamic-dust-final.log`：沙漠Visual wrapper 0；冻结检查通过。前缘增厚、后侧低矮尘雾与飞沙同屏，已检查首尾静帧与动画产物。
- GIF均96帧/12秒；云12,075,862字节，沙尘13,386,091字节。当前图像有明显循环内变化；GIF12秒回放重置不等于云内部28～52秒形变周期。
- RTX 3080、1600×900，所有120帧短样本平均约120FPS；云沙漠/海岛最差帧分别8.478/8.467ms，沙尘8.436ms，三组均frames_below_60=0。
- GPU后端整视口毫秒（off前/24步/16步/off后）：云沙漠1.010/1.950/1.450/0.840；云海岛0.562/1.665/1.263/0.666；沙尘1.193/1.056/1.339/0.857。沙尘次序反转与基线漂移说明该短样本不足以估算稳定GPU净增量，不能声称沙尘零成本；云24步仍约增加1ms量级，高于原0.3ms目标。
- 文档检查通过，两份天气索引各29个强锚点通过；默认`all 1 300 Shadow Headless` wrapper 0，日志`tmp/weather-volume/dynamic-all-final.log`。保留日志中的Desert preload timeout回退、退出14个ObjectDB/7个资源占用诊断；不宣称零警告，也不将Headless通过当作实战GPU性能证明。
