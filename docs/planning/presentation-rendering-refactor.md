# 战斗表现层绘制重构

> 状态：已完成（2026-08-28）
> 范围：行为保持；不调整弹丸数值、命中结算、爆点时序、地图素材、LOD 阈值或视觉配色。

## 问题

`BulletManager` 和 `MissileManager` 原先既管理弹体生命周期/命中，又直接包含完整绘制实现；
地图矢量预览、尾迹批次和爆点则各自重复维护 `points / indices / colors` 与
`RenderingServer.canvas_item_add_triangle_array` 调用。修改表现容易误碰战斗逻辑，退化三角、数组长度和
提交签名也只能靠各模块自行守卫。

## 模块边界

- `BulletManager`：弹丸生成、移动、碰撞、命中、回收和表现数据所有权。
- `BulletPresenter`：读取当帧弹丸值数据，绘制曳光、火箭、炸弹、Flak、命中火星和漂浮雷；不修改数组。
- `MissileManager`：导弹/AOE/结构波生命周期与统一爆炸宿主。
- `ExplosionPresenter`：AOE 红圈、普通方框爆点和结构爆点几何；不持有飞机或导弹对象。
- `CanvasTrianglePacket`：无领域语义的三角组包、面积门、顺序索引和一次性 Canvas 提交。
- 地图与尾迹：继续保留各自的静态缓存、LOD 和采样策略，只复用 triangle packet 原语。

## 保持不变的契约

1. 普通/纯视觉曳光仍合为一次单色 multiline；火箭仍逐颗绘制橙红尾迹和白色弹头。
2. Flak、炸弹、命中火星和漂浮雷的颜色、尺寸、时序与确定性视觉噪声不变。
3. 普通爆炸仍是一枚方框；仅大型飞机终点可走四条五点结构波；近轴侧面面积不足时跳过。
4. 地图正式路径仍是 lossless WebP streaming；静态矢量 packet 只在预热/构建阶段生成，不逐帧重烘。
5. 飞机尾迹保持 retained Canvas 缓存，导弹尾迹保持八相合批和战略 LOD 豁免。

## 验证

- `rendering_packets`：共享 packet 对齐、退化面守卫、爆点近轴几何与 Godot 4.7 提交签名。
- `gun_burst` / `map_vector_preview`：现有弹丸表现数据生命周期与地图四档 packet 预算。
- `rocket_trajectory_visual` / `hit_flash_visual` / `map_raster_tokyo`：真实弹丸、爆点和正式地图画面。
- `battlefield_atmosphere_stress_36`：36 名混合海陆空、8/8 相机巡检和表现热路径帧时。
- `all`：全量同步断言、生命周期场与自动运行时错误门。
