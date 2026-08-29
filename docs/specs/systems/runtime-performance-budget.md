---
id: runtime-performance-budget
kind: system
status: draft
schema_version: 1
spec_version: 1
owner: user+codex
depends_on: [systems/survivor-loop, systems/battlefield-atmosphere-experiment]
reconstruction_complete: false
---

# 运行时性能预算重构

> 用可复算、按成本域拆分的工作量预算守住 60 FPS；性能降级只降低重复计算频率与远景几何复杂度，不删除正在发生的战斗。

## 1. 设计意图（Why）

- **体验目标**：36 名密集全可见混战与 48 名多战线战场都保留真实 AI、伤害、刷怪、标签、尾迹、弹道和爆炸，同时让性能策略可解释、可测试且不随瞬时 FPS 抖动。
- **Litmus 自检**：对应设计哲学 #7“热闹战场”、#11“60 FPS 硬底线”。性能不足时先消除重复扫描/分配，再按成本域降频；不得把减少敌人或停火包装成优化。
- **现状问题**：旧刷怪器每 `0.5 s` 读取一次 FPS，保留 6 个样本形成约 `3 s` 平均；低于 `30 FPS` 才把敌机上限每次减 2，最低减到 8，并完全停止新刷怪。它既不能在 60 FPS 红线附近及时保护帧预算，又会改变战斗人口和节奏；同一时刻 AI 拥挤度又按全部 `CombatUnit` 计数，使舰船挂点也会把飞机 AI 推入最高降频档。
- **反模式规避**：不建立一个把飞机、挂点、弹丸、地图和 UI 混成单一分数的“万能压力值”；不同成本形状必须使用各自的权威计数和策略。
- **SEAM-016 边界**：本重构只统一工作量输入与调度预算，不新增 `lod_level`/`visible` 写者，也不提前裁定 LOD 的最终所有权。现有 mode/AI 七写者问题仍由物理-AI 控制重构 Phase 4 处理；性能快照不能成为第八个写者。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 内容上限与不可降级合同

| 字段 | 值 | 说明 |
|---|---:|---|
| `ordinary_enemy_cap` | 36 | 正式局默认敌机内容上限；只由玩法预算决定，不受实时 FPS 改写 |
| `hard_enemy_cap` | 48 | 专项/高压内容硬上限；只由明确场景合同启用 |
| `runtime_min_enemy_cap` | 不存在 | 删除旧 8 架动态下限语义 |
| `runtime_spawn_fps_gate` | 不存在 | 不因 FPS 停止正式刷怪 |
| `debug_spawn_cap_override` | `-1` | 仅 bench/Debug：`-1` 使用正式 cap，`0` 禁止自然补刷，`1..48` 固定测试 cap；不得由 FPS 写入 |
| 60 FPS 帧预算 | `16.667 ms` | 诊断与验收红线，不直接作为删减内容的反馈控制器 |

运行时预算不得关闭或减少：正式 AI 状态机、伤害、武器发射、自然刷怪、任务来源、标签、尾迹、弹道、爆炸、玩家 HUD。允许调整的是非关键单位的慢决策频率、远景几何采样和已有 LOD 更新频率；玩家、BOSS、王牌中队、Sentinel 始终继承现有豁免。

### 2.2 每物理帧快照

`PerformanceWorkloadSnapshot` 在 `SurvivorMode` 已完成一次单位缓存更新后生成；同一物理帧内所有消费者只读同一快照，不各自扫描场景树。

| 字段 | 定义 | 消费域 |
|---|---|---|
| `aircraft_count` | 有效且未销毁的 `Aircraft` 数 | AI 决策降频、飞机 LOD |
| `ai_aircraft_count` | `aircraft_count` 中具有有效 `AIController` 的数量 | AI 拥挤度公式 |
| `combat_unit_count` | 有效 `CombatUnit` 总数，包含舰船挂点 | 雷达/目标候选诊断 |
| `ground_count` / `naval_count` / `mount_target_count` | 各真实子类数量 | 分域热点与回归合同 |
| `bullet_count` / `missile_count` | 当前真实弹丸数 | 弹幕专项与批绘诊断 |
| `visible_aircraft_count` | 相机矩形加既有 500 px margin 内的飞机数 | 远近景 LOD 诊断；不改变敌人生命周期 |
| `view_scale` | 相机 zoom 的最小轴值 | 尾迹/标签/挂点已有战略几何 LOD |

### 2.3 分域预算

| 成本域 | 低阈值 | 高阈值 | 拥挤度公式 | 最大降频 |
|---|---:|---:|---|---|
| AI 决策 | `ai_aircraft_count = 12` | `ai_aircraft_count = 30` | `clamp((N-12)/(30-12), 0, 1)` | NORMAL `×1.5`；CHEAP `×2.0`；IMMUNE `×1.0` |
| HUD 雷达重绘 | `combat_unit_count < 30` | `combat_unit_count >= 30` | 二档 | `30 Hz → 20 Hz` |
| 普通尾迹几何 | `view_scale > 0.26` | `view_scale <= 0.26` | 复用既有 zoom 判定 | 战略视距隔点构网格；不缩短路径 |

AI 有效 divisor 继续使用 `ceil(base_divisor × lerp(1, max_multiplier, crowd_t))`。变化只在 `N` 的权威来源：从包含地面单位、舰船和挂点的 `CombatUnit.all_units.size()` 改为 `ai_aircraft_count`。计时器仍乘有效 divisor 补偿真实时间。

### 2.4 诊断与控制边界

| 数据 | 用途 | 是否控制玩法 |
|---|---|---|
| `avg_fps / p1_fps / worst_frame_fps / frames_below_60` | F3、F9、bench 与验收 | 否 |
| `PerfBuckets` 各桶 | 定位 CPU/绘制热点 | 否 |
| `PerformanceWorkloadSnapshot` | 选择确定性的分域更新频率/LOD | 是，但不得改变 §2.1 内容合同 |
| `RuntimeTuner` | Debug A/B，当前实例临时调参 | 否；正式游戏代码不得依赖 |

### 2.5 性能监控证据口径

| 输出 | 时间窗口 | 用途 |
|---|---|---|
| F3 帧历史 | 最近 120 个渲染帧 | 交互观察 avg/p95/worst/<60；关闭面板即清空 |
| F3/F9 Perf Snapshot | 最近完成的约 1 秒窗口 | 当前态热点与调用量；不得单独冒充整段 bench 结论 |
| Bench Frame Trace | 3 秒预热后的全部完成帧 | p95/p99/max、慢帧上下文、事件相关性与全程根桶均值 |
| 慢帧上下文 | 每簇前 120 / 后 30 帧，最多 8 簇 | 判断尖峰前因、同帧事件与恢复过程 |

Frame Trace 必须同时输出：`trace_roots frames`、根桶 `known_avg`、全帧 `frame_avg`、保守 `known_share`，以及每个根桶的“全程每帧均值 + 活跃帧数/总帧数”。`known_share` 仅表示已埋点根桶占墙钟帧时间的比例，不是 CPU 利用率，也不得把未覆盖时间自动归因给 GPU。

根桶互不嵌套。`survivor_cache` 覆盖当帧单位缓存与友军据点仇恨，`radar_locks` 独立；`survivor_lod` 覆盖旧 FPS 采样及敌我 LOD，`survivor_spawner` 覆盖 Spawner 主 tick。`spawn_enemy` 保留为子热点/事件，但不再与 `survivor_spawner` 同时计入根桶总和。

## 3. 行为与公式（How）

### 3.1 每物理帧顺序

1. `SurvivorMode` 对直属正式战斗单位做一次 O(N) 分类，产出飞机缓存、全单位缓存和分域计数。
2. 同一批缓存写入 BulletManager、MissileManager、雷达候选桶和 `PerformanceWorkloadSnapshot`。
3. 离屏 LOD、友军可见性和 AI 预算只遍历飞机缓存；不得再次 `get_children()`，不得逐机扫描子节点找 AI。
4. AIController 读取同一快照的 `ai_aircraft_count` 计算 divisor；无可用快照时只回退到自身基础 divisor，不做全场扫描。
5. FPS 与 PerfBuckets 在帧尾记录，仅用于诊断和验收，不反向修改敌机 cap 或刷怪许可。

### 3.2 刷怪许可

正式增援只由以下条件否决：玩家/局状态、BOSS 阶段、任务状态、固定内容 cap、Token 预算、机型实例上限、冷却和正式出生规则。FPS 不是许可条件。Bench/Debug 可显式设置 `debug_spawn_cap_override` 固定压力场人口；该值不进入发布局存档、不由正式流程写入，也不能冒充自动性能降载。

### 3.3 生命周期与回退

- 快照只保存当帧 typed 数量与有效对象数组，不跨帧持有新对象引用。
- 飞机缓存中的元素在每个消费者入口仍执行 `is_instance_valid()` 与 `is_destroyed` 守卫。
- AIController 的 `Aircraft._ai_ref` 是 AI 权威引用；为空时跳过 AI 预算写入，不扫描子节点补找。
- 玩家、BOSS、王牌中队、Sentinel 的现有 LOD/AI 豁免不变。

## 4. 结构与组成（Structure）

- `SurvivorMode`：每物理帧唯一工作量快照生产者；持有飞机/全单位缓存，负责相机相关 LOD。
- `PerformanceWorkloadSnapshot`：无场景树访问的 typed 数据对象；只表达当前工作量，不保存 FPS 控制状态。
- `AIController`：只消费 `ai_aircraft_count` 和自身 `AIScaleClass`，保留现有 divisor 公式。
- `SurvivorSpawner`：删除 FPS 样本、动态敌机 cap 与低 FPS 停刷；正式流程只消费固定内容 cap 和玩法预算，bench 可使用独立 `debug_spawn_cap_override`。
- `PerfBuckets`：保持诊断职责，不成为玩法 authority。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 静态审计：正式运行时不存在 `TARGET_FPS=30`、FPS 驱动 `_dynamic_enemy_cap` 或低 FPS 停刷分支。
- [ ] 聚焦回归：注入低 FPS 诊断样本不会改变敌机 cap、Token、下一波许可或真实成员数。
- [ ] 聚焦回归：`debug_spawn_cap_override=-1/0/48` 分别保持正式 cap、关闭自然补刷、固定 hard-cap 测试人口；发布流程无法写入该字段。
- [ ] 聚焦回归：12/30 架 AI 边界与 IMMUNE/NORMAL/CHEAP divisor 数值准确；舰船挂点数量变化不再改变飞机 AI divisor。
- [ ] 生命周期：同帧释放飞机后，LOD/友军可见性/AI 预算消费者不发生 freed-object 或 typed boundary 错误。
- [ ] SEAM-016：`lod_level` / `visible` 写者集合没有增加，语义隐藏与演出隐藏的两个既有 meta 合并点保持不变。
- [ ] 性能：C1 与 C2 各跑连续三次 `Shadow Visual`；`frames_below_60=0`、P1/最差帧均不低于 60，平均/P1 中位相对同条件基线不越门，8/8 镜头巡检与演员/弹丸合同完整。
- [ ] 性能：C2 结果明确记录 `aircraft_count` 与 `combat_unit_count`，证明挂点只影响目标/雷达域，不污染 AI 域。
- [x] 监控：Frame Trace 输出全程根桶均值与活跃帧覆盖，不再用最后 1 秒热点代表整段 bench；focused `perf_trace` 12/12。
- [x] 监控：C1/C2 三轮 A/B 证明新增监控覆盖未越过 avg/P1 observer-tax 回退门；结果包含 `survivor_cache/lod/spawner`。
- [x] 全量 `all`、LifecycleGauntlet 与运行时错误门通过。
- [ ] 已知 seam 未触碰 / 已妥善处理（见 architecture/known-seams.md）。
- [ ] 文档：本 spec 已登记 `_INDEX`；状态/重建标记一致；当前文档无失效相对链接。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 2026-08-29 审计 `SurvivorSpawner` / `SurvivorMode` / `AIController` | 发现 30 FPS 才降 cap/停刷、LOD 重复树扫描、AI 计数混入 MountTarget |
| E3 baseline | C1 三轮；C2 一轮，Godot 4.7.2，`Shadow Visual` | C1 中位 avg `363.56`、P1 `200.00`、最差帧最低 `60.27`、`<60=0`；C2 avg `341.04`、P1 `180.00`、最差 `60.08`、`<60=0` |
| E3 Phase 0 | C1/C2 三轮，复用飞机缓存后 | C1 中位 avg `353.07`（-2.9%，门内）、P1 `210.00`（+5%）、最差帧最低 `60.27`、`<60=0`；C2 三轮 avg `379.61 / 379.32 / 377.34`、P1 `240.98 / 213.54 / 216.87`、最差帧最低 `60.28`、`<60=0`，47/48 名成员与 9 发炮弹稳定。结构优化保留，但 C1 平均值尚不能宣称提升 |
| E2 Phase 0 | `all 1 300 Shadow Headless` | 全量回归 `87/87`、LifecycleGauntlet `82/82`；运行时错误门退出 0 |
| E3 监控链 | C1/C2 各三轮 `Shadow Visual`；`performance_hud_visual`；`perf_trace` | C1 中位 avg `363.47`（相对 Phase 0 +2.9%）、P1 `220.00`；C2 优化聚合后中位 avg `371.74`（-2.0%）、P1 `217.49`；两组最差帧最低 `60.45 / 60.68` 且 `<60=0`、镜头 `8/8`、成员与炮弹合同完整。全程报告稳定包含 `survivor_cache/lod/spawner`；F3 Visual 已显示同名三域；focused `12/12`。首次全根桶逐帧扫描曾令 C2 中位约 -5.7%，已改为只扫描本帧实际桶后复测收回门内 |
| E2 监控链 | `all 1 300 Shadow Headless` | 全量运行时错误门退出 0，LifecycleGauntlet `82/82` |
| E4 完整局 | 待实现后 12–20 分钟真实操作 | 待补 |

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 去掉重复扫描（语义不变）

- [x] `SurvivorMode` 保存当帧飞机 typed cache，敌方 LOD 与友军可见性复用。
- [x] LOD 读取 `Aircraft._ai_ref`，删除逐机子节点扫描；simple AI 排序删除临时 Dictionary。
- [x] C1 连续三次 A/B + C2 连续三次，确认绝对门与相对回退门通过；全量回归与生命周期通过。

### 阶段 1 — 单一工作量快照

- [ ] 建立 typed `PerformanceWorkloadSnapshot` 与纯函数边界测试。
- [ ] 单次分类产出 §2.2 全部字段，接入 PerfBuckets 标签。
- [ ] AI、雷达 HUD、LOD/尾迹消费者改读各自成本域，不建立万能压力分数。

### 阶段 2 — 刷怪与 FPS 解耦

- [ ] 删除 Spawner FPS 采样数组、timer、动态 cap 和低 FPS 停刷；将现有 bench 对 `_dynamic_enemy_cap` 的直接写入迁移到独立 Debug override。
- [ ] 固定 36/48 内容 cap；补低 FPS 注入不改变刷怪的聚焦回归。
- [ ] 更新 survivor-loop 中旧“FPS 动态降 cap”权威描述与验收项。

### 阶段 3 — 验证与收尾

- [ ] 跑 C1/C2 三轮 Visual、focused、`all`、生命周期与文档校验。
- [ ] 进行完整局观察，确认自然人口、任务/BOSS、Tab 和战斗视觉未被性能策略削减。
- [ ] 回填证据、reference 锚点与状态；满足全部验收后转 `done`。

### 阶段 D — 性能监控证据链

- [x] Frame Trace 累计预热后全程根桶总量、活跃帧数、known/frame 均值与保守覆盖比例。
- [x] 补 `survivor_cache`、`survivor_lod`、`survivor_spawner` 三个主循环盲区；新增根桶只在 F3/trace 开启时计时。
- [x] `spawn_enemy` 从根桶集合降为 `survivor_spawner` 子热点，避免父子双算。
- [x] focused 契约覆盖两帧不同根桶成本，证明输出不是最后 1 秒快照。
- [x] 跑 C1/C2 三轮监控 observer-tax 门、`performance_hud_visual` 与全量回归。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 单位缓存 / 离屏 LOD / 友军可见性 | `scripts/survivor/survivor_mode.gd` |
| 刷怪 cap 与旧 FPS 反馈 | `scripts/survivor/survivor_spawner.gd` |
| AI 拥挤度 divisor | `scripts/ai_controller.gd` |
| 性能诊断 | `scripts/util/perf_buckets.gd` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-29 | 1 | 初稿：记录旧 30 FPS 动态减员问题，定义分域工作量快照、刷怪解耦与 Phase 0 A/B 证据 |
