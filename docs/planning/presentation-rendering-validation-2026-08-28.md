# 表现层重构智能测试报告（2026-08-28）

## 结论

本轮对弹丸、爆点、尾迹、导弹与地图表现层重构进行了专项、Visual、性能和全量生命周期验证。未发现玩法或视觉合同变化，未发现性能回退、脚本运行时错误、释放对象访问或闪退。

性能 A/B 只采用同一场景、相同 30 秒时长、Shadow Visual、相同镜头巡航合同的结果。测试中曾出现外部 120 FPS 上限漂移；受限样本只用于 60 FPS 门槛判断，不进入 A/B 中位数。

## 功能与视觉合同

- `rendering_packets`：16/16。覆盖共享三角 packet、退化三角拒绝、矩形批次、爆点四个 heading 以及 Godot 4.7 triangle-array 提交签名。
- `visual_bullet_soa`：7/7。视觉弹 SoA、真实伤害弹命中路径与阵营候选隔离保持正常。
- `trail_ribbon_lod`：7/7。远景降采样以及玩家、Boss、Sentinel、来袭导弹豁免保持正常。
- `missile_visual_lod`：8/8。远景标签、弹体和警告语义保持正常。
- `map_vector_preview`、`map_gold_slice`：通过。地图 packet 数量、LOD 分层、预热与跨战区 Detail 路径保持正常。
- `hit_flash_visual`、`rocket_trajectory_visual`、`map_raster_tokyo`：本轮重构后的 Visual 场景通过，人工检查未见弹丸、命中爆点、火箭轨迹或地图层级的可见差异。

## 同场景性能对比

以下为三次有效样本的中位数；旧版基线取 2026-08-24 的同合同结果。

| 场景 | 版本 | 平均 FPS | P1 FPS | 低于 60 帧 | bullet_draw | trail_draw | missile_draw | missile_trail_draw |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| C1：36 单位 / 8 km | 旧版 | 353.97 | 221.52 | 0 | 5 us/f | 81 us/f | - | - |
| C1：36 单位 / 8 km | 当前 | 363.31 | 270.00 | 0 | 5 us/f | 68 us/f | - | - |
| C2：48 单位 / 24 km | 旧版 | 378.35 | 220.00 | 0 | 0 us/f | 56 us/f | 2 us/f | 1 us/f |
| C2：48 单位 / 24 km | 当前 | 381.71 | 239.37 | 0 | 1 us/f | 56 us/f | 2 us/f | 1 us/f |

- C1 平均 FPS 中位数约提升 2.6%，P1 约提升 21.9%；弹丸绘制持平，尾迹绘制桶由 81 降至 68 us/f。
- C2 平均 FPS 中位数约提升 0.9%，P1 约提升 8.8%；导弹和尾迹绘制桶基本持平。
- 海战弹幕三次当前样本中位数为 592.00 FPS / P1 420.00 FPS，低于 60 帧中位数为 0。历史海战结果受 120 FPS 上限、测试时长和采样口径漂移影响，不作百分比 A/B。
- 地图缩放转场三次当前样本中位数为 466.30 FPS / P1 274.73 FPS，低于 60 帧中位数为 0。
- 地图稳态三次均通过，但其中两次被外部 120 FPS 上限锁定；唯一无上限样本为 482.22 FPS / P1 270.00 FPS。旧地图结果为 Godot 4.7.1 Headless 10 秒样本，不能与当前 Visual 30 秒结果直接比较。
- 地图细节层专项当前样本为 425.20 FPS / P1 270.00 FPS，低于 60 帧为 0。

## 稳定性与终态

- `bench/run.cmd all 1 300 Shadow Headless`：退出码 0；全量同步断言通过。
- `lifecycle_gauntlet`：82/82，通过真实终态并跨消费者下一帧。
- 本轮 28 份相关结果文件扫描：`SCRIPT ERROR`、`RUNTIME ERROR`、非法 call/access/type、freed object、`signal 11`、crash 命中数为 0。
- 所有性能与 Visual 进程均由 wrapper 正常回收，没有超时、退出码 86 或原生闪退。

## 非阻断警告

- 地图 Visual 进程退出时稳定报告 1 个 `CanvasItem` RID 与 1 个 `ObjectDB` 实例未释放；无跨帧访问、无崩溃、无错误门失败。共享 packet 本身不创建 RID，因此当前证据不指向新 presenter 的所有权泄漏，但地图缓存清理仍值得后续单独收口。
- Headless 单元测试退出时会报告少量 `ObjectDB` / Resource still in use；按项目验证约定与断言结果分开记录。
- Wacom 配置、shader cache 与系统根证书读取失败属于 Shadow Visual 本机环境噪声，不是游戏脚本错误。

## 代表性证据

- C1 当前：`bench/results/battlefield_atmosphere_stress_36_20260828_000938.txt`、`001018.txt`、`001059.txt`
- C1 旧版：`bench/results/battlefield_atmosphere_stress_36_20260824_110651.txt`、`110737.txt`、`110824.txt`
- C2 当前：`bench/results/battlefield_atmosphere_stress_48_24km_20260828_001151.txt`、`001235.txt`、`001316.txt`
- C2 旧版：`bench/results/battlefield_atmosphere_stress_48_24km_20260824_110911.txt`、`110958.txt`、`111045.txt`
- 海战当前：`bench/results/naval_zone_stress_20260828_001356.txt`、`001437.txt`、`001517.txt`
- 地图当前：`bench/results/map_raster_stress_20260828_000250.txt`、`000332.txt`、`000510.txt`；`map_raster_transition_stress_20260828_000554.txt`、`000634.txt`、`000714.txt`；`map_raster_detail_stress_20260828_000757.txt`
