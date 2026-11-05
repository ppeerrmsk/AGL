# 世界单位状态栏检查与重写（2026-10-24）

范围：飞机完整/精简/远景/无人机/坠毁标签，地面与派生单位、舰船、导弹世界信息牌；遵循现有 UI 规范，未新建通用规范。

## 已修复

- F-4E 等非编队飞机在 LOD 1/2 失去目标后不再跳过主弹/机炮恢复计时；真实发射、目标死亡与装填完成由生产入口验证。
- 编队副槽装填继续；密集战场错相已门控的成员不再被第二道相位门永久跳过，也不重复放大时间。
- JAM/规避/加力的禁射条件与已开始的恢复计时分离；F-22 隐身即时补弹同时清除装填标志和进度。
- 状态栏不再靠机体 `_draw` 烘焙数字。统一只读快照按墙钟 2Hz 错峰采样，结构/切控/显隐/密度变化在下次 50ms 检测时刷新，动画独立更新颜色，位置仍跟随屏幕显示变换。
- 飞机全部显示档共用武器/状态构建；修复精简栏电磁炮/激光被热诱弹装填条件错误包裹，无人机漏状态、失速漏行和非操控机直写无敌误报。
- 雷达站补通用状态倒计时；追踪数过滤已死/已释放对象。SAM 缺观察者距离为 RNG ---；导弹零距离有效，目标释放后为未知距离。
- 隐藏/复现和来源死亡/离树正确清理；字宽缓存改为有界逐项淘汰，避免清空全部缓存后的集中重算。

## 验证

Godot 4.7.2 Steam，均通过 bench/run.cmd、Shadow 隔离运行；验证时已与另外两个工作区任务协调冻结。

| 检查 | 结果 | 证据 |
|---|---|---|
| unit_status Headless | 128 项，0 失败，wrapper 0 | tmp/status-bar-rewrite/focused-4.log |
| unit_status Visual | 同一 125 项，0 失败；24%→71%→完成行消失 | tmp/status-bar-rewrite/visual-progress.log；bench/results/unit_status_reload_*.png |
| 兵种/受伤反相/远景 Visual | wrapper 0；人工检查三张截图，文本水平、颜色与密度档正确 | tmp/status-bar-rewrite/visual-layout.log；bench/results/unit_status_label_visual*.png |
| presentation | 402 通过、0 失败，wrapper 0 | tmp/status-bar-rewrite/presentation.log |
| perf_trace | wrapper 0，包含另一任务新增墙钟长停顿回归 | tmp/status-bar-rewrite/perf-trace.log |
| 静态检查 | 玩家引用持有者、文档链接/元数据、索引锚点通过 | 对应校验器 |

专项已接入默认 lifecycle_gauntlet；完整功能与性能证据见下。这里不把 wrapper 0 当作严格 60 FPS 通过。

开发期首次专项发现快照布尔类型推断错误（wrapper 86）；第二次发现测试未给无机炮的 F-4E 挂载机炮却要求其恢复，已修正测试前提。失败日志 focused.log / focused-2.log 保留。误用 perf_frame_trace 键的运行不计作专项，随后使用已核实的 perf_trace 键通过。


## 最终冻结版本结果

- `all 1 300 Shadow Headless`：105 项同步测试组通过，UnitStatus 128/0，GunEvasionLifecycle 12/0，LifecycleGauntlet 93/0，wrapper 0；运行时错误门、已释放对象与退出残留检查无报错，音频退出 clean。日志：`tmp/status-bar-rewrite/all-2.log`。
- 首次联合 all 曾发现新增发射用例消费了已有 EncounterDirector 的攻击名额：LOD1/2 后续发射共 6 个断言失败，并影响后续机炮出弹用例。修复测试场景隔离：每个真实发射场景独立创建交战账本，仍经过正式发射门，结束时 shutdown 并恢复原 active。新增账本释放断言；生产禁射规则未放宽。首次失败日志仍在 `tmp/map-entry-burst-20261024/all.log`。
- C1/C2 均为 30 秒 Shadow Visual，Godot 4.7.2 Steam / RTX 3080 / 1600×900 / 2×MSAA，完整 8/8 镜头巡检；实际启用了 FrameProbe（2026-10-25 根据原始日志更正）：当时将 AGL_FRAME_PROBE 设为 0，但入口只检查环境变量是否存在，因此 c1.log/c2.log 均记录了 [FrameProbe] armed。扩展 CPU 和墙钟尖峰探针未启用。两套正式计时在这两个带探针样本中通过严格 60 门，不能标作无额外探针的终态性能验收。负载成员没有删减；这是各一次验证，不能声称三轮稳定性或与旧版本的同条件性能收益，另一个性能任务继续负责最终重复样本。`satellite=disabled`，不替代东京地图验收。

| 场景 | 成员/跨度 | 平均 FPS | 1% low | 最差 FPS | 引擎/墙钟慢帧 | 墙钟最差 ms | 状态栏末秒平均 ms/帧 | 结果文件 |
|---|---|---:|---:|---:|---|---:|---:|---|
| C1 | 36/36，8km | 209.25 | 84.93 | 68.63 | 0 / 0 | 16.026 | 0.322 | bench/results/battlefield_atmosphere_stress_36_20261024_080237.txt |
| C2 | 48/48，24km | 200.08 | 79.42 | 62.70 | 0 / 0 | 15.888 | 0.434 | bench/results/battlefield_atmosphere_stress_48_24km_20261024_080316.txt |

C1 末秒仍有 59 发子弹，C2 末秒有 4 枚导弹；场景分别记录 5/9 发环境炮弹。末秒快照不是全程峰值。完整日志 `tmp/status-bar-rewrite/c1.log`、`c2.log`；本次代码指纹在 `tmp/status-bar-rewrite/validated-sources.json`。当前运行中的用户游戏未被终止，重新运行会加载已保存的新实现。


### 2026-10-25 证据标注更正

上述 C1/C2 数值保留，但“无额外探针”的原标注撤回。原始 FrameProbe CSV 同样核对了 bench_t 3–30 秒、非暂停窗口：C1 为 5652 个样本、0 慢帧、最差 14.569ms；C2 为 5403 个样本、0 慢帧、最差 15.954ms。不同采样时点不与正式墙钟逐帧等同，也不混用最差值。

证据分别为 `bench/results/frame_probe_battlefield_atmosphere_stress_36_20261024_080311.csv` 和 `bench/results/frame_probe_battlefield_atmosphere_stress_48_24km_20261024_080350.csv`。状态栏专项、完整功能回归及 Visual 布局结论不变；无额外探针的重复性能验收由正在进行的性能任务重新完成。本次仅更正文档，不修改状态栏实现或测试代码。
