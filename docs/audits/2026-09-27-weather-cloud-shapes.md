# 云体A/B/C实机造型比较

用户否决9月25日的叶片状壳体后，要求制作多个版本。此次只增加离线资源与造型验收入口，未替换正式天气生成器，也未改变战斗判定或默认开关。

## 三版与实际观察

| 版本 | 每个云体三角形（3个不同模型） | 观察 |
|---|---|---|
| A 不规则层积云 | 3632 / 3364 / 3668 | 横向连续，起伏比较克制；边缘仍偏整块，缺少细碎变化 |
| B 厚融合云团 | 4116 / 3908 / 4276 | 高度和厚度更明显；偏棉花团，容易显得卡通 |
| C 破碎尾部云带 | 2828 / 2844 / 2884 | 前后尺度不同、风向可辨；尾端仍尖，部分剪影像动物，不宜直接定稿 |

建议以A继续修轮廓，仅在局部借用B的厚度。这三版仍是造型探索，没有达到此前概念图的自然碎云效果。

## 方法与成本边界

离线对多尺度椭球高斯密度求和，用 marching tetrahedra 提取等值面。各个隆起在同一个场内融合，不再叠放透明椭圆壳。固定种子生成每组3个不同网格；游戏里只加载数据建Mesh。比较使用同一哑光不透明shader、同一镜头和摆位，暂时剥离透明混合产生的灰边。没有运行时体积场、实时云影或新常驻tick。

脚本：`tools/bake_weather_cloud_shapes.py`；离线重建附件：`resources/weather_cloud_shapes/compare.json`；测试加载器：`scripts/tests/weather_cloud_shape_preview.gd`。最终采样步长0.18，位置保留8位、法线6位小数。曾发现忽略过小三角形会在C中留下孔洞，已保留非零小面并提高位置精度。最终9个模型均有限、闭合、无非流形边或退化三角形；三种风格的首个模型重建与保存数据完全一致。

面数明显高于上一版192面壳体；这些数据只证明3个局部云体的可渲染性。没有用这次画面测试宣称完整云层、GPU耗时或严格60 FPS通过。铺场前仍需LOD、批绘及可见预算。

## 真实截图与验证

- [A 沙漠全景](../../bench/results/weather_shapes_desert_railway_a_field.png) / [近景](../../bench/results/weather_shapes_desert_railway_a_close.png)
- [B 沙漠全景](../../bench/results/weather_shapes_desert_railway_b_field.png) / [近景](../../bench/results/weather_shapes_desert_railway_b_close.png)
- [C 沙漠全景](../../bench/results/weather_shapes_desert_railway_c_field.png) / [近景](../../bench/results/weather_shapes_desert_railway_c_close.png)
- [A 海岛](../../bench/results/weather_shapes_ocean_islands_a_field.png) / [B 海岛](../../bench/results/weather_shapes_ocean_islands_b_field.png) / [C 海岛](../../bench/results/weather_shapes_ocean_islands_c_field.png)

`AGL_WEATHER_COMPARE=1` + `bench\run.cmd weather_volume_visual 1 180 Shadow Visual`。最终Godot 4.7.2 GL Compatibility：两地图×三版本×两镜头共12张截图，wrapper 0，输出Weather shape comparison PASS。比较模式不走原暂停断言，已经将结尾提示分开，不能借用原Visual的暂停验收。日志为`tmp/weather-volume/sep27-shapes-final.log`。

本轮只有测试入口、离线工具与样板资源变化，未重跑全量玩法回归；上一轮全量退出超时仍未解除。
