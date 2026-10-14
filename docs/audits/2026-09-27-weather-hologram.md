# 全息气象同资产展示与实机比较

用户要求渲染图与实机图可直接比较，避免概念图无法落地。本次全部由Godot GL Compatibility直接截图，无图像生成或后期加工。

- 入口：`AGL_WEATHER_HOLO=1`，`bench\run.cmd weather_volume_visual 1 180 Shadow Visual`。
- 展示：`bench/results/weather_holo_display.png`。独立深色背景、斜视正交镜头，复制同一网格及材质，无额外光照或后期。
- 实机：`bench/results/weather_holo_desert_railway_field.png`、`weather_holo_desert_railway_close.png`，以及同名`ocean_islands`版本；真实Survivor地图、单位、HUD与合成链。
- 固定三个示意云区，三层96点轮廓，882线段、282填充三角形、两份网格surface。构建一次，无新增逐帧脚本；GPU片元生成抗锯齿斜线。surface数不是整场实测draw call数。
- focused Visual wrapper 0，五张截图已检查，日志`tmp/weather-volume/holo-preview.log`。
- 默认`all 1 300 Shadow Headless` wrapper 0，LifecycleGauntlet 90通过/0失败，日志`tmp/weather-volume/holo-all.log`；日志仍有退出资源占用（14 ObjectDB、7 resources）和证书存储警告，不宣称零警告。文档链接、元数据及两个天气索引各22个强锚点检查通过。

## 观察及边界

白色实体的玩具感已去掉，沙漠道路和单位可见。展示机位斜视使高度感更强，实机俯视更接近气象等值线；海面背景细线有锯齿/断续，背景相关的线条对比仍需调校。三层同源缩放轮廓还会像地形等高线，未达到最终云区识别度。

仅作静态美术可实现性比较，固定示意形状未绑定WeatherSystem密度；HUD的IN CLOUD来自原天气，不可用它验证示意云区的效果边界。没有修改天气判定、默认开关，也没有以小场景宣称60FPS性能通过。尚未验证实战遮挡、运动、暂停和整场成本；沙尘暴本轮未改。
