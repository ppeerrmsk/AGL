# 性能守则（Performance Guidelines）

> **给未来的自己和 Claude**：做任何新机制（敌人/武器/UI/特效/地图要素）之前先读这份文档。
> 过去的 bug 全部归档在末尾"历史教训"，同类的问题一次就够了。

AGL 帧预算 = 16.6 ms/frame（60 FPS）。**60 FPS 是不可突破的硬底线**——见 [DESIGN_PHILOSOPHY.md §11](../DESIGN_PHILOSOPHY.md)。生存模式 + Sentinel 小队 + 20+ 敌机的压力测试是验收标杆，任何让这个场景**掉一帧**的新代码都要砍掉或改写。不接受"偶发掉到 X FPS"的妥协。

---

## 硬规则（严禁违反）

### R1. 静态内容禁止每帧 `queue_redraw()`
Godot 的 CanvasItem 自带命令列表缓存——**只要不重绘就不重算**。如果内容不变（地图、边界、静态图标、非动画 UI），画一次就够。

❌ 典型错误：
```gdscript
func _process(_delta: float) -> void:
    queue_redraw()  # 地图也不变，UI 也不变，为啥每帧重画？
```

✅ 正确做法：
```gdscript
func _ready() -> void:
    queue_redraw()  # 构造完毕触发一次，之后靠状态变化驱动
func on_state_changed() -> void:
    queue_redraw()  # 只有需要时才重绘
```

**例外**：
- 相机跟随的内容（尾迹、锁定线、预测路径）必须每帧重绘，但见 R2
- 脉冲/动画确实需要视觉变化的 UI 元素（警戒闪烁、HUD 雷达扫描）

### R2. `_draw()` 里不得有 O(N²) 或 O(scene_nodes) 扫描
`_draw()` 每帧调用。里面做全场扫描就是每帧 O(N²)。

❌ 典型错误：
```gdscript
func _draw() -> void:
    for node in get_parent().get_children():   # 扫 200 个节点
        if node is Aircraft and node.team == 0: # 每帧都找玩家
            dist_to_player = ...
```

✅ 正确做法：
- 玩家引用：用 `AircraftRenderer.player_ref`
- 全体战斗单位：用 `CombatUnit.all_units`（每帧由 `survivor_mode._update_aircraft_list` 维护）
- 任何"某某的列表"：由持有人每帧/每物理帧缓存一次，`_draw` 只读

### R3. `draw_polygon` / `draw_line` 不要按条小循环调
GPU 命令提交本身有固定开销。**10000 次画 1 像素的 draw_line 比 1 次画 10000 条线的 `draw_multiline` 慢一个数量级**。

❌ 典型错误：
```gdscript
for i in range(300):
    draw_polygon([...4 个顶点], [...4 个颜色])   # 300 次 API 调用
```

✅ 正确做法（按选项排优先级）：
1. `RenderingServer.canvas_item_add_triangle_array(canvas_item, indices, points, colors)` — 一次提交任意三角形
2. `draw_polyline_colors(points, colors, width)` — 一次画整条折线
3. `draw_multiline_colors(points, colors, width)` — 一次画 N 条不相连的线段

实例：`trail_ribbon.gd` 用 RenderingServer 把 299 次 draw_polygon 合成 1 次，~300× 减少。

### R4. `_process` / `_physics_process` 里不得有 `get_parent().get_children()`
每次 `get_children()` 都分配 Array + O(N) 遍历。**N 包含 UI、音效播放器、临时节点**，比战斗单位数大得多。

✅ 正确做法：
- 玩家飞机 → `AircraftRenderer.player_ref` 或 `survivor_mode.player_aircraft`
- 所有战斗单位 → `CombatUnit.all_units`（静态数组，每帧由主场景刷新）
- 所有敌机 → filter `CombatUnit.all_units`（仅 ~20 项，不是 ~220）
- 任何其他列表 → 做成维护的状态变量，别现查

**注意**：`CombatUnit.all_units` 是跨帧静态，使用前必须 `is_instance_valid()`，否则访问已释放节点会报"previously freed instance"导致崩溃。

### R5. AI 决策 ≠ 60Hz 必须
飞机物理必须 60Hz（移动平滑），但 AI 决策（选目标、算航向、BFM 决策树）**完全不需要**。

参考现有节流：
- `AIController.ai_tick_divisor` — simple_ai 默认 3（20Hz），远距 UAV 动态 6（10Hz）
- `Aircraft._auto_gun_scan` — 0.3s 一次
- `survivor_mode._update_radar_locks` — 0.2s 一次
- Spawner._update_hunters / _update_enemy_waypoints / _update_far_cleanup — 自带秒级 timer

新 AI 行为的默认节奏应该是 **"能多慢就多慢"**，从 1-3Hz 起步，只有玩家能察觉不对才加快。

### R6. 挂在高频实体上的子节点要按人头算总成本
Aircraft 有 22 架、Missile 有 10 枚。挂在它们上面的每个子节点（`TrailRibbon` / `CommanderOverlay` / 雷达圈 / 音效播放器）都会乘以这个倍数。

做新效果前先算：**每实体 × 实体数 × 60Hz = 总频率**。
如果得到六位数，就得改。

### R7. 新功能必须跑一下 Sentinel 压力测试
任何加入 `_process` / `_physics_process` / `_draw` 的代码，提交前去生存模式触发 Sentinel 小队 + 打到 level 5+（20+ 敌机），记录 FPS。**60 FPS 不可掉**——只要有一帧低于 60 就立即回滚或改写。这是 [DESIGN_PHILOSOPHY.md §11](../DESIGN_PHILOSOPHY.md) 的硬底线。

### R8. 单帧成本随 N 增长的代码必须支持拥挤度自适应
任何"每个单位都要做的事情"（AI 决策 / 雷达扫描 / 状态广播 / 装备 update），单帧成本随 N 线性或更高增长。**N 不是常数**——生存模式中后期可能突破 30。

**原则**：单帧成本与 N 强相关的代码，**必须**让单位级成本能在 N 大时退化。三档退化优先级：

1. **降频**（首选）：成本不变但频率随 N 减小（见下方"套路 II"）
2. **冻结**（次选）：完全跳过非关键单位（见下方"套路 III"）
3. **简化**（兜底）：用更便宜的算法替代（如 BFM → 直冲 lead pursuit）

**例外**：玩家、BOSS、Sentinel — 永不降级。任何降级方案都要支持"豁免名单"。

**当前实现参考**：
- AI 决策：`AIController.AIScaleClass {IMMUNE/NORMAL/CHEAP}` + 自动派生（team / category / is_unmanned）+ 30+ 敌机时拉到 max_mult
- 雷达锁定：`RADAR_LOCK_STRIDE = 4` 子集轮转 + HOSTILE/非 HOSTILE 候选预分桶
- 屏幕外远距：`FAR_FREEZE_DIST_SQ` 硬冻结（survivor_mode._update_offscreen_lod）

---

## 优化套路（Optimization Patterns）

写新机制时，**先看这 4 个套路里有没有现成模板**。重复造轮子前再考虑特殊情况。

### 套路 I — 共享列表替代 `get_children()`

**何时用**：任何"扫场上某类单位"的循环。

**用法**：
- `CombatUnit.all_units` — 所有飞机+地面单位（survivor_mode 每帧维护）
- `AircraftRenderer.player_ref` — 玩家飞机引用
- 子弹/导弹命中：`bullet_manager.combat_unit_list` / `missile_manager.target_list`

**坑**：`CombatUnit.all_units` 是跨帧静态数组，必须 `is_instance_valid(unit)` 守卫，否则访问僵尸引用崩溃。

### 套路 II — Tick Divisor 节流（固定降频）

**何时用**：行为不需要 60Hz 精度的代码（AI 决策 / 长时累积 / 慢量更新）。

**模式**：
```gdscript
if (Engine.get_physics_frames() + _tick_phase) % divisor != 0:
    return
delta *= float(divisor)  # 放大 delta 让 timers 节奏不变
```

**关键点**：
- `_tick_phase = randi() % divisor` 在 `_ready` 设，错开不同实例的决策帧（防峰谷）
- `delta *= divisor` 抵消频率，让累积量（timers / 距离 / 倒计时）一致
- 速度/高度/燃油等慢量：20Hz 起步（divisor=3）；视觉敏感量（bank/heading/位置）：永远 60Hz

**实例**：
- `AIController.ai_tick_divisor` — simple_ai 默认 3
- `aircraft_formation.gd:update_follow` — speed/altitude 走 `_lod_frame % 3` + `delta×3`，bank/heading 60Hz

### 套路 III — 拥挤度自适应（动态降频）

**何时用**：成本随 N 增长且 N 可能很大（AI 决策 / 状态广播）。

**模式**：
```gdscript
var n: int = CombatUnit.all_units.size()
var crowd_t: float = clampf(float(n - LOW_THRESH) / float(HIGH_THRESH - LOW_THRESH), 0.0, 1.0)
var max_mult: float = CHEAP_MAX if scaling_class == CHEAP else NORMAL_MAX
var effective_divisor: int = int(ceil(base_divisor * lerpf(1.0, max_mult, crowd_t)))
```

**默认阈值**：
- LOW = 12 单位（≤此值：不降频）
- HIGH = 30 单位（≥此值：拉满 max_mult）
- CHEAP × 2.0（UAV / Adds：30+ 时 6→12，5Hz 决策）
- NORMAL × 1.5（载人战机：30+ 时 3→5，约 13Hz 决策）
- IMMUNE 不降（玩家 / BOSS / Sentinel）

**实例**：`AIController._compute_scaling_class` 自动从 `aircraft.team / category meta / params.is_unmanned` 派生分级。

### 套路 IV — 子集轮转（Stride Rotation）

**何时用**：O(N²) 全场扫描已经按时间节流（如 0.2s 一次），但单 tick 仍然贵。

**模式**：
```gdscript
const STRIDE := 4
var _phase: int = 0

func _full_scan(delta):
    var phase = _phase
    _phase = (_phase + 1) % STRIDE
    var per_unit_delta = delta * float(STRIDE)  # 抵消 1/STRIDE 频率
    for i in range(units.size()):
        if i % STRIDE != phase:
            continue
        # ... 用 per_unit_delta 累积
```

**关键点**：
- 每个单位被处理周期 = 节流间隔 × STRIDE（如 0.2s × 4 = 0.8s）
- `per_unit_delta = step_delta × STRIDE` 抵消频率，累积速率不变
- 全局状态（`is_locked` 等）每 tick 都要 reset，但累积态（`radar_targets` 字典）跨 stride 持久
- 副作用：状态变化最多滞后 (STRIDE-1) × 节流间隔（如 0.6s），需评估玩家可感知性

**实例**：`survivor_mode._update_radar_locks` STRIDE=4，全覆盖 0.8s。

### 套路 V — 屏幕外+远距冻结（完全停 _physics_process）

**何时用**：屏幕外且远离玩家的非关键实体（敌机 / 子弹追踪 / 装饰单位）。

**模式**（参考 `survivor_mode._update_offscreen_lod`）：
```gdscript
if offscreen and dist_sq > FAR_FREEZE_DIST_SQ and not is_critical:
    ac.set_physics_process(false)
    ai_node.set_physics_process(false)
else:
    ac.set_physics_process(true)
    ai_node.set_physics_process(true)
```

**关键点**：
- 必须有 `is_critical` 豁免（BOSS / Sentinel / 玩家），否则游戏会异常停摆
- 进屏 / 靠近时立即解冻，否则会"位置跳跃"
- 当前默认阈值：`FAR_FREEZE_DIST_SQ = 750² = 562500`（1500m，PIXELS_PER_METER=0.5）

---

## 常用共享基础设施（已有，别重复造轮子）

| 需求 | 用什么 | 在哪 |
|------|--------|------|
| 玩家飞机引用（只读） | `AircraftRenderer.player_ref` | `aircraft_renderer.gd:5` |
| 全场战斗单位列表 | `CombatUnit.all_units` | `combat_unit.gd`，`survivor_mode._update_aircraft_list` 维护 |
| 子弹命中目标列表 | `bullet_manager.combat_unit_list` | 同上维护 |
| 导弹命中目标列表 | `missile_manager.target_list` | 同上维护 |
| AI 决策节流（固定降频） | `AIController.ai_tick_divisor` | `ai_controller.gd` |
| AI 拥挤度自适应分级 | `AIController.AIScaleClass` + `_compute_scaling_class()` | `ai_controller.gd`（按 team / category / is_unmanned 自动派生） |
| 拥挤阈值常量 | `AIController.CROWD_THRESHOLD_LOW=12 / HIGH=30 / CHEAP_MAX_MULT=2 / NORMAL_MAX_MULT=1.5` | `ai_controller.gd` |
| 屏幕外敌机节流 | `survivor_mode._update_offscreen_lod` | `survivor_mode.gd` |
| 屏幕外远距冻结距离 | `FAR_FREEZE_DIST_SQ`（1.5km²） | `survivor_mode.gd` |
| simple_ai 预算池 | `SIMPLE_AI_FULL_TICK_BUDGET` | `survivor_mode.gd` |
| 雷达锁定子集轮转 + ROE 候选预分桶 | `RADAR_LOCK_STRIDE=4` + `_radar_lock_phase` + `_rebuild_radar_target_buckets` | `survivor_mode.gd:_update_radar_locks` |
| 云层采样缓存 | `CombatUnit._cloud_cache_*` + `_cached_is_in_cloud` | `survivor_mode.gd` / `main.gd` |
| LOD 1 编队降频边界 | `aircraft/aircraft_formation.gd:update_follow`（speed/altitude 20Hz，bank/heading 60Hz） | 套路 II 实例 |

---

## 历史教训（踩过的坑，勿再犯）

### 地图系统加入后从 60 FPS 掉到 10 FPS（2026-04-18）
**原因**：
- `MapFeatureRenderer._process` 每帧 `queue_redraw`，但地图完全静态
- 每帧重新计算海岸光晕外扩多边形（PackedVector2Array 分配）、内陆高光、重心、~150 条 draw_line
- `MapBoundary._process` 每帧画 300+ 条虚线边界（非警戒时完全不需要）

**修复**：删除 `_process` 里的无脑 `queue_redraw`，海面一次性画满 world_rect；边界只在警戒状态变化时重绘。

**教训** → R1

### TrailRibbon 是 40 万次 draw_polygon/秒的元凶（2026-04-18）
**原因**：
- 每架飞机的 TrailRibbon 存 `max_points=300` 个历史点
- `_draw` 循环调 299 次 `draw_polygon`
- 22 架飞机 × 60 FPS × 300 = **40 万 draw 调用/秒**

**修复**：
- `max_points` 300 → 80
- 用 `RenderingServer.canvas_item_add_triangle_array` 一次性提交整条丝带
- **注意**：trail 存的是世界坐标，每帧 `to_local` 换算时，Aircraft transform 变化，所以 `queue_redraw` 必须每帧跑，**不能节流到采样率** — 否则尾迹会跟飞机抖

**教训** → R3 + R6

### `draw_data_label` 每帧扫全场找玩家（2026-04-18）
**原因**：`for node in get_parent().get_children()` 在每架飞机的 `_draw` 里跑，N(飞机) × M(节点) = O(N²)，21 架 × 219 节点 = 4600 次迭代/帧。

**修复**：加了 `AircraftRenderer.player_ref` 静态引用。

**教训** → R2 + R4

### `_auto_gun_scan` 60Hz 全场扫描（2026-04-18）
**原因**：每架飞机每帧 `get_parent().get_children()` 找机炮目标，60Hz。子弹 600 m/s 下根本用不到 60Hz 扫描精度。

**修复**：加 0.3s 扫描节流 + 用 `CombatUnit.all_units`。

**教训** → R4 + R5

### `CombatUnit.all_units` 持有僵尸引用导致崩溃（2026-04-18）
**原因**：静态数组跨帧，中间 aircraft.queue_free() 后，下一帧 `is Aircraft` 访问已释放节点爆 "Left operand of 'is' is a previously freed instance"。

**修复**：所有 `for unit in CombatUnit.all_units` 循环开头加 `is_instance_valid(unit)` 守卫。

**教训** → R4 注意事项

### 30 敌机时帧数掉到 25 FPS — 缺乏拥挤度自适应（2026-05-04）
**原因**：固定 `ai_tick_divisor` 不会随场上单位数动态调整。30 架飞机时所有 simple_ai 仍跑 20Hz、全功能 BFM AI 仍跑 60Hz；雷达锁定 O(N²) 哪怕 0.2s 节流，单 tick 成本 N=30 时仍重；屏幕外远距 UAV 仍 `_physics_process` 全跑。

**修复**：
- 加 `AIScaleClass {IMMUNE/NORMAL/CHEAP}` + `CombatUnit.all_units.size()` 拥挤系数；30+ 时 CHEAP UAV ×2、NORMAL 战机 ×1.5
- 雷达锁定 `RADAR_LOCK_STRIDE=4` 子集轮转
- 屏幕外 + 距玩家 >1.5km 非关键敌机 `set_physics_process(false)` 完全冻结
- LOD 1 编队 speed/altitude 降到 20Hz（`_lod_frame % 3` + `delta×3`）

**教训** → R8 + 套路 II/III/IV/V 全部确立。**记住**：单帧成本随 N 增长的代码必须支持降频路径。

### `get_parent().get_children()` 残留 4 处（2026-05-04）
**原因**：squad_coordination 的 scan_leader_rear / scan_squad_nearby_enemy、ai_controller 的 `_try_engage_in_tether_range` / 自爆机扫描、target_selection 的 BOSS 重锁路径，仍用 `get_parent().get_children()`。在 R4 立后没清干净。

**修复**：4 处全部改用 `CombatUnit.all_units` + `is_instance_valid()` 守卫。

**教训** → R4。新规则立时要全仓库扫一遍合规情况，别只改一处样板。

### Sentinel 数据链虚线（commander_overlay.gd）（2026-04-18）
**原因**：每帧画 Sentinel → 每个僚机的虚线连接，小循环拆成 50+ 条 `draw_line`。5 个僚机 × 50 条 × 60Hz = 1.5 万 draw_line/s，纯装饰。

**修复**：直接删除数据链虚线。光环圈（1 个 `draw_circle` + 1 个 `draw_arc`）足够表达"被覆盖"的意图。

**教训** → R3 + R6

---

## 审查清单（PR / 新功能 checklist）

**触发条件**：每个加 `_process` / `_physics_process` / `_draw` 的 PR 都要过一遍。

### 共享列表 + 现有节流
- [ ] 是否加了 `_process` / `_physics_process`？→ 能不能用信号/timer 替代？
- [ ] 是否调了 `queue_redraw`？→ 是真的需要每帧，还是状态驱动？
- [ ] `_draw` 里有没有循环/扫描？→ 用 `CombatUnit.all_units` / `AircraftRenderer.player_ref`
- [ ] `get_children()`？→ 换成 `CombatUnit.all_units` + `is_instance_valid` 守卫
- [ ] 视觉效果有多个 `draw_line` / `draw_polygon`？→ 合并成 `draw_polyline_colors` / `canvas_item_add_triangle_array`

### 频率与挂载倍数
- [ ] 是否挂到 Aircraft/Missile 下？→ 先乘实体数 × 60Hz 再判断（六位数就要改）
- [ ] 新 AI 决策？→ 默认 `ai_tick_divisor ≥ 3`（20Hz）起步
- [ ] 视觉敏感量（bank/heading/位置）：60Hz；慢量（speed/altitude/燃油）：20Hz；累积量（锁定/buff）：5Hz 起步

### 拥挤度自适应（R8）
- [ ] 单帧成本与 N 强相关？→ 必须支持降频/冻结/简化中至少一种（套路 II/III/IV/V）
- [ ] 设置了 IMMUNE 豁免名单？（玩家 / BOSS / Sentinel 永不降级）
- [ ] N 大时降级行为可接受？（用户已明确"允许行为退化"也要确认 BOSS 不退化）

### 验收
- [ ] 改完了跑 Sentinel + Lv5+（20+ 敌机）压力测试 — 60 FPS 不可掉
- [ ] 改完了跑 Lv8+（30+ 敌机）压力测试 — 验证拥挤度自适应是否启动
- [ ] F9 导出 log 看有没有新增 push_warning / null deref
- [ ] 改了 R4-R8 任一硬规则的实现？→ 全仓库 grep 一遍同模式残留
