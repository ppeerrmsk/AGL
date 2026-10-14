# 正式飞机画质修复验收（2026-09-06）

权威：[战斗实体立体表现 v18](../specs/systems/combat-entity-volume-prototype.md)。以下最终证据来自 `C:/Users/noelu/Documents/AGL` 的正式检出，不沿用 F6 独立入口或旧 0.45× 结果。

## 已实装

- 正式飞机层恢复实际输出像素尺寸、2× MSAA、线性合成；不再 0.45× 最近邻放大。
- 删除 60 Hz 提交节流、physics 错相和压力切换，逐显示帧在正式相机之后消费当前姿态。物理仍为 60 Hz，本次没有新增物理插值。
- 真实击坠保留原机体网格、涂装和死亡前 LOD；缩放与透明度消费原坠毁流程，淡出材质共享原 ArrayMesh，释放前不闪回 PNG。隐身/传感器保密条件不放宽。
- 保留同期地图视角、相机静态去重、地形/瓦片回归；没有提交或推送。

## 已取得证据

环境：Godot 4.7.2 Steam / GL Compatibility / NVIDIA RTX 3080 / 610.47；Visual 输出 1600×900。全部经 `bench/run.cmd` 的 Shadow 与运行时错误门。

| 验证 | 结果与边界 |
|---|---|
| `volume_world 1 180 Shadow Headless` | 200/200；覆盖专属机型、几何/LOD、正式接线及同期地图回归 |
| `volume_formal_quality 1 120 Shadow Visual` | 14/14；移动/旋转/缩放相机的最大真实投影偏差 0.00378 px；人工检查正式与同源 F6 对照、致死后同网格与淡出截图 |
| `all 1 300 Shadow Headless` | 默认全量通过，正式视口生命周期 23/23，gauntlet 86/86，wrapper 退出 0；包含真实伤害和跨帧释放 |
| 36 名 / 8 km / 30 秒正式 Visual | 平均 119.74 FPS，P1 110.00，最慢 85.04，低于 60 FPS 帧数 0；36/36，巡检 8/8；LOD0/1/2 实际提交 3818/44883/14972 |
| 48 名 / 24 km / 30 秒正式 Visual | 平均 119.59 FPS，P1 110.00，最慢 69.31，低于 60 FPS 帧数 0；48/48，巡检 8/8；LOD0/1/2 实际提交 574/21708/36621 |
| 静态 | 定向 code-index 522 锚点通过；文档/注册通过；玩家引用漏登记 0；`git diff --check` 通过 |

Visual 图片在正式 `bench/results/volume_quality_{formal_alive,f6_reference_alive,formal_before_damage,formal_after_damage,formal_fade}.png`；性能原始报告为 `battlefield_atmosphere_stress_36_20260906_091716.txt`、`battlefield_atmosphere_stress_48_24km_20260906_091900.txt`。

## 未完成与已知边界

- C1/C2 当前各一轮；补足三轮的请求遇到另一项正式地图测试占锁，wrapper 正确退出 2，未绕过。不能把这两轮宣称为稳定收益或完成三轮成对矩阵。
- S1/S2/S3、适用 BOSS/Adds 与 12–20 分钟完整局尚未完成；manifest 保持 `formal_default_pending_validation`。
- 引擎退出仍有 ObjectDB/resource/CanvasItem 警告；本轮没有宣称泄漏自由或把退出 0 当作内存验收。
- 新 Visual fixture 的第一次执行因 WeakRef 类型推断失败而超时；第二次把 deferred 安装帧误计入稳定显示采样，两个断言失败。修正显式类型并先完成三帧预热后，工作树与正式检出均 14/14，未放宽 0.1 px 投影门。
