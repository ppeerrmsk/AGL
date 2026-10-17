# 2026-10-17 性能诊断：卡顿根因与 C# 迁移待办

status: paused（团队决定先把 GDScript 整体迁移到 C#；本稿记录全部问题，迁移完成后据此在 C# 代码上实施）

返回 [Handoffs 索引](README.md)。

**诊断对象**：分支 `codex/low-frame-streaming-2026-10-15`（HEAD `bffec47`）加当时工作树里 Codex 未提交的改动，安装 M20 东京地图包。`main` 上还没有东京 HLOD 流送等代码（由 `1d58939` 快照提交引入），所以下文的部分路径只存在于该分支。函数位置以写作时的 GDScript 为准，迁移后请对照新代码重新定位。

## 1. 结论

硬件不是瓶颈：GPU 每帧约 2.4ms，后台线程合计不到 0.35 核，CPU 全程睿频。卡顿全部来自**主线程**，分三类：

| 类别 | 玩家感受 | 根因 |
|---|---|---|
| A. 事件型冻结 | 平时流畅，隔一阵卡一下（15–40ms，某事件第一次发生时可达 ~400ms） | 事件触发时在帧内同步做一次性工作：文字排版试探、同步加载音乐/资源、暴力几何判定 |
| B. 高负载物理步超预算 | 大战时掉到 60 以下，偶尔连续 1 秒卡顿 | 每个 60Hz 物理步约 4.7ms 脚本；超时后 `max_physics_steps_per_frame=3` 引发补步螺旋 |
| C. 持续顿挫 | 帧率很高但画面一直不顺 | 物理 60Hz 未开插值，渲染不限帧（100–280 FPS），镜头在 `_process` 里追逐按 tick 跳变的目标 |

## 2. 测量方法与关键数据

- 平台：Ryzen 9 9955HX + RTX 5070 Ti Laptop，300Hz 屏，Godot 4.7.2 Steam tools 版（GDScript 运行在 debug 模式），GL Compatibility，窗口 1600×900。
- 工具（只在诊断分支本地工作树，未提交，依赖该分支接口）：逐帧探针 `scripts/diagnostics/frame_probe.gd`（`AGL_FRAME_PROBE=1`），用引擎信号和两个 ±1e9 优先级节点把每帧拆成互斥阶段，并记录物理步数、节点增删、显存、玩家屏幕位置；自动驾驶 `scripts/diagnostics/frame_probe_autoplay.gd`（`AGL_FRAME_PROBE_AUTOPLAY=<秒>`，经 `bench\run.cmd probe_play …` 启动），按正式流程玩东京湾正式局。另用远程调试协议做了 GDScript 逐函数剖析，以及线程级 CPU 采样。
- **正式局**（4/4/13 分钟三局）：均值 220–280 FPS，p99 8–10ms。13 分钟局加载后的 14 个真实慢帧中，13 个属于 A 类（文字排版 5、切歌 4、战区解锁/王牌刷怪/升级/城市直升机各 1），1 个是渲染端原生尖峰（31.6ms，未定位）。
- **东京 C2**（48 单位）：avg 100–107 FPS，>16.7ms 帧占 4–6%。**无物理步的帧均值 5ms、0 慢帧；有物理步的帧均值 13ms，占慢帧 94%。** 一次实测补步螺旋连续 1.2s 33–65ms/帧。C2 的 133 个慢帧里有 125 个同时发生了东京地图完成件领取。
- **顿挫**：正式局 73–77%、C2 42% 的渲染帧里玩家位置完全没变；屏幕滚动速度逐帧变异系数 1.4–8.5；C2 玩家机屏幕抖动 p95 约 14px。
- **测量纪律**：机器上有其它负载时，同样 13 分钟正式局的慢帧数从 26 个涨到 368 个。前后对比必须在空闲机器上做、交错重复多次。

## 3. 问题清单

### A. 事件型冻结（优先级最高，直接对应"异常卡顿"）

| # | 问题 | 实测 | 位置 | 修法 |
|---|---|---|---|---|
| A1 | HUD/无线电新文字排版：逐字号线性试探，每步调用未缓存的 `get_string_size` 并取字形轮廓；墨迹缓存满 2048 条时**整库清空**，导致所有 HUD 文字在同一帧重新测量；计时面板每次重绘对每个数字都重跑一遍 | 5–17ms/次，最高频 | `scripts/ui/terminal_text.gd` `resolve_font_layout` / `layout_fits` / `measure_ink_bounds`；`scripts/survivor/warzone_time_panel.gd` `_draw_text` | 按 (字体, 文本, 区域尺寸) 缓存排版结果；缓存宽度，宽度放得下才测轮廓；缓存改为逐条淘汰。**不要改二分搜索**：字形高度不随字号单调增长，二分可能选出不同字号 |
| A2 | 切歌时同步 `load()` 2–8.6MB OGG；音效 `load(path)` 不持有引用，会反复重载 | 6–22ms/次 | `scripts/audio/audio_manager.gd` `_get_music` / `_get_sfx` | Loading 阶段或提前几秒用线程预载并常驻 |
| A3 | 王牌增援刷怪时运行时 `load()` .tres 再 `duplicate(true)`；资源没人持有，下次重新解析 | 3–5ms/架；冷启动曾观测 382ms | `scripts/survivor/ace_support_squad.gd` `_configure_spawn` | 刷怪用到的资源全部在 Loading 时预载常驻 |
| A4 | 新机型首次绘制时，在 `_draw` 里读盘解码剪影 PNG | 1–2ms/机型，5 架新机型一帧 9.4ms | `scripts/aircraft_silhouette_catalog.gd` `_texture_for` | Loading 时预热全部剪影 |
| A5 | 战区解锁的陆地判定：11 个超大多边形无包围盒预筛，再加 146 个水面多边形，单次判定要做 1168 次点包含测试 | 19ms | `scripts/survivor/map_geography.gd` `is_on_land_strict` / `_point_in_mask_entries` / `is_ground_spawn_safe`；`scripts/survivor/zone_data.gd` `_roll_mission_type` | 栅格查表（已验证可行的设计：128px 格，不被多边形边穿过的格直接返回预存结果，约 17% 的边界格仍走原多边形测试）；每个战区的陆地结果在 Loading 时算好；与原判定做抽样一致性测试 |
| A6 | 城市直升机事件选点：718 个多边形 × 6232 次战区状态查询 | 5–7ms | `scripts/survivor/adbs_manager.gd` `_pick_city_center` / `_pos_in_any_zone` | 预计算候选点与战区归属 |
| A7 | 升级弹窗现场给卡片设中文文本，首次出现的字形要栅格化。项目里没有中文字体，走的是系统回退字体，而且按 1920×1080 基准缩放绘制 | 8–25ms | `scripts/survivor/survivor_upgrade_ui.gd` `populate` | 打包一份中文字体；Loading 时按实际缩放把常用文本真正画一遍来预热 |
| A8 | 击杀播报 | ~2.4ms | `scripts/survivor/survivor_hud.gd` `_on_kill_recorded` | 低优先 |
| A9 | 进入战场时单帧构建约 4 秒；Loading 画面也有 1.5–1.8s 的卡死 | — | `survivor_mode` 构建、`building_preloader` | 分帧构建，保持 Loading 动画 |

通用原则：**战斗中可能第一次用到的资源，都在 Loading 阶段预载并持有引用；O(大 n) 的几何和查询改为预计算查表；事件路径上的工作量要有每帧预算。**

### B. 高负载物理步（C2 每步约 4.7ms 脚本）

| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| B1 | 飞机物理每步 3.24ms（33 架，约 98µs/架）：运动学 0.77、武器 0.52、战术规划 0.39、杂项 0.28、未分桶约 0.9ms | `scripts/aircraft.gd` `_physics_process`；`scripts/aircraft/aircraft_physics.gd` | `effective_*()` 的结果按物理帧对每架飞机缓存（保持"buff 只在 accessor 注入"的语义）；持续 G 与瞬时 G 共用一次 buff 乘数计算 |
| B2 | 热路径小调用过多：`safe_player_ref` 约 620 次/帧、`safe_aircraft_ref` 约 645、`is_berserk_virus_wingman` 约 430、`_refresh_maneuver_cache` 约 466；性能分桶每个物理步约 340 次计时调用（七成是飞机细分桶，字符串键字典加成对读时钟） | 多处；`scripts/util/perf_buckets.gd` `tick` | 每 tick 缓存；细分计时只在诊断采样帧开启 |
| B3 | 雷达锁定每次 4Hz tick 集中花 1.46ms | `survivor_mode` 雷达更新 | 拆成多片，分到不同物理步执行（锁定累积速率保持不变） |
| B4 | 普通 AI 的决策相位全是 0，拥挤降频后全部挤在偶数物理帧决策 | `scripts/ai_controller.gd` | 按单位错开相位 |
| B5 | 补步螺旋：一帧超时，下一帧补 2–3 个物理步，接着持续超时 | `project.godot` `physics/common/max_physics_steps_per_frame=3` | 评估降到 2 或 1，用短暂的时间膨胀代替连锁卡顿 |
| B6 | 负载极不均：有物理步的帧 13ms，没有的只有 5ms；物理步里请求的飞机重绘被合并到同帧的 process 信号段执行（约 1.6ms，只在物理步帧出现） | `scripts/rendering/visual_redraw_queue.gd`（Codex 未提交候选） | 可延后的工作（地图完成件领取、纹理上传、尾迹重建等）优先放到没有物理步的帧执行 |
| B7 | 地图流送：领取完成件时主线程跑 GDScript 逐索引网格校验和 SHA 校验，单张纹理上传约 1.5ms；工作线程端每个文件新开一个线程算 SHA-256，纹理读前读后各算一次 | `scripts/rendering/tokyo_hlod_stream.gd` 等 | 上传按帧预算；完整性校验移到安装期；改用固定线程池 |
| B8 | 正式路径里跑着 experiments 脚本 | `scripts/experiments/volume_world_probe.gd` `_process`（0.2–0.7ms/帧） | 迁移时归入正式模块 |

### C. 顿挫

| # | 问题 | 修法 |
|---|---|---|
| C1 | 物理 60Hz 未开插值，渲染不限帧 | 开启 `physics/common/physics_interpolation`，但把根节点的 `physics_interpolation_mode` 设为 OFF 走白名单：只对只在物理步里移动的单位（飞机、导弹）开启。大量特效、UI、Tween 和镜头在 `_process` 里改变换，全局开启会被引擎按 tick 错误插值 |
| C2 | 镜头在 `scripts/camera_controller.gd` `_update_follow` / `cine_follow_tick` 里追逐每 tick 跳一次的位置 | 镜头跟随插值后的"显示态"位置 |
| C3 | **正式局飞机由三维合成层绘制**：`volume_world_probe.gd` 每个显示帧读 `global_position` / `heading` 摆放 MultiMesh，二维插值对它无效 | 喂显示态的位置和航向（含母鹅挂点） |
| C4 | 其它世界坐标的读取方：世界标签 `WorldUnitStatusOverlay.update_screen_position`、恐惧锥/暴露条、尾迹 `TrailRibbon`（父机插值后，原先每帧把 `global_transform` 设为单位阵会让整条丝带随插值相位抖动） | 改读显示态；尾迹改为抵消父机显示态变换，采样点也取显示态。子弹批绘和飞机 `_draw` 里的目标线/预测航迹可保留 60Hz，需录屏确认 |
| C5 | 传送、出生、切控 | 在 `Aircraft.clear_trail()` 这类统一收口处调用 `reset_physics_interpolation()` |
| C6 | 不限帧，笔记本单核长期满载发热 | 提供帧率上限选项。300Hz 屏上 120 FPS 等于 2.5 个刷新周期，不能均分：**不开插值时只有 60 能均分**；开插值后推荐 150 / 100 / 60 |

## 4. 迁移影响分析：换成 C# 后哪些会自然解决

GDScript 到 C# 的收益只落在"脚本自身的执行开销"上（解释执行、Variant 装箱、函数调用、字典哈希）。C# 调用的是同一套引擎 API，引擎原生代码里的成本不会变；算法和架构问题也会原样带过去。

| 分类 | 涉及条目 | 迁移后 | 说明 |
|---|---|---|---|
| ① 脚本执行开销 | B1、B2，飞机/尾迹/HUD 的 `_draw` 内部逻辑 | **大幅改善**，通常数倍 | 物理步里是成百上千次小函数调用、字典/Variant 操作和数学计算，正是 C# 最擅长的部分，也是高负载掉帧的主因。前提是热路径使用 C# 原生类型 |
| ② 引擎原生成本 | A1 文字塑形/字形轮廓、A7 字形栅格化、A2/A3/A4 资源加载/解析/解码、B7 纹理上传 | **基本不变** | 这部分时间在引擎内部。必须改成预载、缓存、Loading 预热 |
| ③ 算法问题 | A1 线性试探与整库清空、A5 暴力点包含（`Geometry2D.is_point_in_polygon` 本身已是原生）、A6、B3 雷达集中爆发、B4 AI 相位聚集 | **常数项变小，但仍是尖峰** | 必须改算法或调度：查表、缓存、错峰 |
| ④ 架构与配置 | C1–C6 插值/镜头/显示态、B5 补步上限、B6 负载均衡、B7 主线程校验、A9 构建冻结 | **完全不变** | 与语言无关，迁移时按本稿设计重做 |

**迁移可能引入的新卡顿来源（需要提前约束）：**

- **GC 停顿**：C# 每帧分配托管对象（`string` 拼接、LINQ、闭包、装箱成 `Variant`、每帧新建 `Godot.Collections.Array/Dictionary`）会触发垃圾回收，造成新的周期性卡顿。热路径要零分配：对象池、`struct`、复用缓冲区。
- **跨语言封送**：C# 每次调用 Godot API 都要做参数转换。`Godot.Collections` 容器和 `Variant` 往返很贵；内部数据用 C# 原生集合，`StringName`/`NodePath` 缓存成静态字段，不在循环里反复按字符串取节点或属性。
- **混合语言过渡期**：GDScript 与 C# 互相调用比各自内部调用慢得多，热路径应整体迁移，不要拆在两种语言之间。
- **构建与导出**：需要 .NET 版编辑器和 **mono 导出模板**（`Godot_v4.7.2-stable_mono_export_templates.tpz`），与本机已装的标准模板不同。

**建议的迁移顺序**：先把 ④ 中的配置项（插值白名单、补步上限、帧率上限）和 ② 中的预载/预热，作为迁移基线的一部分一次做对；热路径（①）迁移时同时按上面的零分配约束写；③ 的算法问题在迁移对应模块时一并替换。

## 5. 未完成 / 待确认

- **release 与 debug 差距未测**：已安装 4.7.2 标准导出模板（`%APPDATA%\Godot\export_templates\4.7.2.stable`，SHA-512 与官方一致），对比测试在开始前暂停。迁移后应直接比较 C# release 包与当前 GDScript release 包。
- `scripts/survivor/building_preloader.gd` 的矢量地图预热只在 debug 构建执行，release 包的加载流程与地图层会不同，验收时要分别看。
- 13 分钟局里 1 个 31.6ms 的渲染端原生尖峰未定位（需要原生剖析）。
- 382ms 的冷启动冻结只在第一次遇到某事件时出现，剖析复跑未复现，按 A2/A3 的预载原则处理。
- 4.8 目前只到 beta1，暂不建议用于本项目；4.7.2 是最新稳定版。

## 6. 暂停中的实施工作

三个实施会话（事件型冻结 / 物理步减负 / 物理插值）已按暂停指令停下：改动保存为补丁，工作树已恢复到开工前状态（逐字节核对）。补丁只在诊断机器本地的 `tmp/paused-work/`（被 `.gitignore` 排除，不在本 PR 中），全部**未经运行验证**，只作为设计参考，不必套用到 C# 代码：

- `event-hitch-fix.patch`：A1、A2、A3、A4、A5、A6 的修法草稿；预载函数已写好但还没有调用方；A7 未实施。
- `physics-tick-budget.patch`：B1–B4、B6 的修法草稿，带临时 A/B 开关 `AGL_PHYS_OPT_OFF`。
- `physics-interpolation.patch` 与 `physics-interpolation.NOTES.md`：C1–C6 的设计与半成品（新增的 `display_pacing.gd` 还没有接入调用方，当前不能编译）。

## 7. C# 版验收建议

- 沿用本稿口径：东京 C1/C2 固定负载加正式局自动游玩，各跑多次，交错重复，在空闲机器上测。报告按"本帧是否有物理步"分组的均值和 p99、>16.7ms 与 >33ms 帧数、补步帧数、事件型慢帧清单，以及顿挫指标（无位移帧比例、屏幕速度变异系数）。
- 探针与自动驾驶是 GDScript 实现，迁移后需要同步迁移，或在 C# 侧重写同等探针。
