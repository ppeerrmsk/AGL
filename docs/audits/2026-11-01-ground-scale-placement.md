# 地面单位尺寸与城市摆位复核

日期：2026-11-01。Godot 4.7.2 Steam，GL Compatibility / RTX 3080。

## 根因与实现

普通车辆沿用旧图标尺寸，原SPG/AAA底盘16px等于32m，SAM/雷达24px等于48m；地面部署只避水，SPG椭圆只用16个相位验陆地，没有城市建筑净空。

普通SPG/AAA底盘改为6m，SAM/雷达为8m，三维车体和活动炮塔共用0.125尺度；巨型任务单位及其附属挂点保留自身尺度，LOD和状态牌同步使用实际大小。本批不改战斗数值。

建筑占地取256片lod5_full近景两层楼体，共10,978,981个非垂直投影三角形，加正式游戏楼足迹。来源逐文件SHA核验，输出 resources/maps/tokyo_ground_obstacles.bin（7,387,360字节）及同名JSON来源清单；运行时按固定SHA校验，解压34,047,752字节常驻位图。2px单元，查询额外扩一格，普通车辆净空5px。导出规则包含该bin。UGC使用当前图注入的建筑多边形。

正式出生与普通移动读取局部占地，不扫描全城；SPG整路按最多4px弧长步进并追加2px余量，先完整轨道、再1/4、最后合法位置驻停，之后才沿原有无解缩编规则处理。分帧搜索保持既有预算，缩路不增加常驻tick、实体或绘制。

## 已有证据与边界

- `volume_ground` 最终189/0，包含附属挂点尺度/LOD豁免反例，见 tmp/ground-size-focused-final.log。
- `zone_atmosphere` 71/0，包含独立1440相位路线复查、整次/单步分片方案及RNG一致性。
- `volume_ground_runtime` 修正测试镜头同步与真实像素档位后，真实生命周期46/0、渲染33/0；音频退出clean=true，wrapper退出0。
- 首轮Visual因测试仍在缩小前的像素档位读取不存在批次而触发运行时门86，已保留 tmp/ground-size-visual.log；修正后日志 tmp/ground-size-visual-r2.log。
- 同源城市复核读取原生XYZ近景几何，使用真实GroundUnit、正式presenter与共享投影；两档图为 bench/results/volume_ground_runtime_city_scale_3.png 和 volume_ground_runtime_city_scale_6.png。这是隔离城市几何复核，不是完整地图流送、普通F5长局或最终全图遮挡验收。
- 默认 `all 1 300 Shadow Headless`：105组同步测试0失败，后续生命周期阶段300秒超时，退出124；不能写成全量通过。见 tmp/ground-fix-all.log。
- `battlefield_atmosphere_stress_36 30 180 Shadow Visual`：36/36演员、巡检8/8、30秒，wrapper退出0，音频clean=true；显示统计平均113.40FPS，46帧低于60；墙钟p99=17.630ms、最大53.426ms，41帧超过16.667ms。严格60FPS未通过，未做成对基线，不能据此认定改动引起/解决性能问题。结果 bench/results/battlefield_atmosphere_stress_36_20261101_143931.txt。

## 验证入口

正常游戏直接从主菜单重新开局；占地与模型默认接入。可复查 `volume_ground`、`zone_atmosphere`、`volume_ground_runtime`。城市几何专项使用 AGL_GROUND_CITY_REVIEW 指向原始近景层导出目录，由同一Visual场景读取；这只是制作复核开关，不是玩家使用修复的条件。

## 最终收尾

附属挂点豁免收口后重跑，volume_ground 189/0；volume_ground_runtime 生命周期46/0、渲染33/0，wrapper退出0，音频clean=true，见 tmp/ground-size-visual-final.log。最终默认all仍为105组同步测试0失败，生命周期在300秒被回收，退出124；见 tmp/ground-fix-all-final.log。没有关闭运行时错误门或延长时限冒充默认通过。最终文档锚点、文档链接/规格登记、玩家缓存持有者检查及本次diff格式检查通过。

本轮已停止Godot测试，释放源码、共享索引/文档及测试时段，交接记录 tmp/naval-ground-coordination.json。严格60FPS、完整地图连续操作与普通F5完整局仍未验收。
