# 2026-08-20 性能验证流刷新与 C1 基线

## 为什么旧门失效

旧通用句式“Sentinel + Lv5 / `stress_40` / 末秒 FPS”没有固定同屏比例、弹丸密度、camera zoom、
draw 组合与低帧统计。它可以证明普通人口下没有崩溃，不能证明铺量阶段的大规模战斗气氛守得住 60 FPS。

当前权威已改为 [performance-guidelines](../reference/performance-guidelines.md)：C1 使用 36 名/8 km
混合海陆空全可见战场，C2 使用 48 名/24 km 多战线；再按武器/BOSS/地图/UI 成本追加专项。

## 首次 C1 三次 Visual 基线

- 日期：2026-08-20
- 命令：`bench\run.cmd battlefield_atmosphere_stress_36 30 180 Shadow Visual`
- Godot：4.7.2 stable Steam；GL Compatibility；NVIDIA GeForce RTX 3080
- 确定性：性能采样前修正 bench 自动选卡，改为按等级从稳定池序取值；三次 build 完全一致，
  不再因全局 RNG 消耗顺序改变 CIWS/武器/draw 负载。
- 统计：场景预热 3 秒后采样；三次均 `live_members=36`、`span_km=8.0`、`shells=5`；
  末秒为 57–58 CombatUnit、65–97 bullets、1–2 missiles，负载合同成立。

| 样本 | avg FPS | 1% low | worst FPS | <60 帧 |
|---|---:|---:|---:|---:|
| 1 | 133.18 | 66.67 | 47.46 | 9 |
| 2 | 121.51 | 60.00 | 39.87 | 21 |
| 3 | 115.89 | 60.00 | 42.69 | 17 |
| **三次中位** | **121.51** | **60.00** | **42.69** | **17** |

## 裁定

**当前 C1 基线失败**：平均帧率有余量，但低帧与最差帧没有守住 60，且三次都出现低于 60 的帧，
不是单次冷启动噪声。铺量前应把它作为 P0 性能债处理；不能再用 headless 145 FPS 或 `stress_40`
覆盖本结论。

末秒 PerfBuckets 的稳定大项为：`trail_draw` 约 1.22–1.29 ms/frame、`aircraft_phys`
约 0.91–1.07 ms/frame、`aircraft_draw` 约 0.62–0.70 ms/frame，bullet 物理随 65–97 发在
0.43–0.50 ms/frame。它们是诊断入口，不足以单独证明低帧根因；下一批应增加时间序列/尖峰归因，
再决定优化点，不能凭末秒均值直接砍视觉。

制作人同日补充约束：后续优化必须守住“大规模战斗群互相交战、地图多处同时发生有趣战斗”的 fantasy，
不得靠减员、停火、静音或把远处变成完全静止背景来跑绿。优先调查战斗群/小队级共享目标、攻击、脱离
与重整决策，以减少逐机重复运算；这只是优化方向，实际 AI 合同需先进入独立 approved spec。

三次退出都保留既有 1 个 CanvasItem RID / 1 个 ObjectDB 泄漏警告；它们不是本轮新增崩溃，但应在
长局 L1 泄漏检查中继续追踪。

在确定性修正前曾做三次探索性运行，自动选卡不同，因此不纳入正式中位；它们同样全部出现 `<60`
帧，只作为发现“全局 seed 不等于 build 确定性”的流程证据保留在本地 bench 结果中。
