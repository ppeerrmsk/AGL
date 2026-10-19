# 东京湾色调纠偏：重复底色相乘

用户重新确认旧图的浅灰绿屋顶、橄榄绿地面、蓝绿水及简洁深色侧面为标杆；不以LOD与性能为理由改成暗浑风格。

## 原因与修复边界

GLES3最终合成已经执行 `diffuse_light *= albedo`，原地图shader的light函数又乘ALBEDO，形成重复底色相乘，深色类别受影响更大。[Godot官方实现](https://github.com/godotengine/godot/blob/master/drivers/gles3/shaders/scene.glsl)；[空间材质light文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html#light-built-ins)。

只在HLOD新材质派生中修复，普通地表/楼体和正式楼一致；公共shader、源色板、AO贴图、几何、LOD资格及共享预算不变。legacy_tint默认false，仅用于诊断对照。这解释已观察到的一部分漂移，不代表源色板/近景已经恢复。

## 已执行证据

- focused `tokyo_cells_lifecycle` 的HLOD stream入口：包装0，共享、取消、摘要、预算、闲置缓存及材质默认反例通过。
- 正式Loading→Survivor，`AGL_TOKYO_HLOD_COLOR_REVIEW=1`：两处正常最远zoom0.2，53426/4764面，包装0。相同overlay/viewport、预热与owner退出验证通过。显式诊断跳过巡航，不冒充完整玩家范围。
- 文件 `tmp/tokyo-bay-volume/m1-color-repair-a/color_00_before.png` / `color_00_after.png` 及01对应组：同一场景只切换材质uniform。两组alpha逐像素相同。RGB均值分别从(68.79,77.37,71.71)变为(98.90,108.66,102.99)，从(64.41,74.39,62.91)变为(94.69,105.84,93.13)。均值只证明变化，不代表审美验收。
- 当前已目检城区after：整体压黑减轻，轮廓未作更改；不能以远景代替用户近景金样对拍。
- Visual退出仍有1 CanvasItem RID/1 ObjectDB警告及shader缓存、Wacom、证书环境提示；不声称无泄漏或帧时通过。

## 未完成

正常出生/近景接入、标杆近景同位色板对拍、中景密集区预算、实战帧时间和三地图Visual仍未完成，不沿旧生产队列重复烘焙。

本批全量 `bench/run.cmd all 1 600 Shadow Headless` 包装退出0，LifecycleGauntlet 90/0；原有14 ObjectDB/7资源退出提示仍在，不当作无泄漏通过。索引锚点、player_ref、文档链接/元数据和git diff --check通过。当前无本任务运行中的bench。
