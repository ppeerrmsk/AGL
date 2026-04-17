# 性能守则（Performance Guidelines）

> **给未来的自己和 Claude**：做任何新机制（敌人/武器/UI/特效/地图要素）之前先读这份文档。
> 过去的 bug 全部归档在末尾"历史教训"，同类的问题一次就够了。

AGL 目前帧预算 = 16.6 ms/frame（60 FPS）。生存模式 + Sentinel 小队 + 20+ 敌机的压力测试是验收标杆。任何让这个场景掉到 30 FPS 以下的新代码都要砍掉或改写。

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
任何加入 `_process` / `_physics_process` / `_draw` 的代码，提交前去生存模式触发 Sentinel 小队 + 打到 level 5+（20+ 敌机），记录 FPS。基线从 60 掉到 <45 要立即回滚或改写。

---

## 常用共享基础设施（已有，别重复造轮子）

| 需求 | 用什么 | 在哪 |
|------|--------|------|
| 玩家飞机引用（只读） | `AircraftRenderer.player_ref` | `aircraft_renderer.gd:5` |
| 全场战斗单位列表 | `CombatUnit.all_units` | `combat_unit.gd`，`survivor_mode._update_aircraft_list` 维护 |
| 子弹命中目标列表 | `bullet_manager.combat_unit_list` | 同上维护 |
| 导弹命中目标列表 | `missile_manager.target_list` | 同上维护 |
| AI 决策节流 | `AIController.ai_tick_divisor` | `ai_controller.gd` |
| 屏幕外敌机节流 | `survivor_mode._update_offscreen_lod` | `survivor_mode.gd` |
| simple_ai 预算池 | `SIMPLE_AI_FULL_TICK_BUDGET` | `survivor_mode.gd` |
| 云层采样缓存 | `CombatUnit._cloud_cache_*` + `_cached_is_in_cloud` | `survivor_mode.gd` / `main.gd` |

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

### Sentinel 数据链虚线（commander_overlay.gd）（2026-04-18）
**原因**：每帧画 Sentinel → 每个僚机的虚线连接，小循环拆成 50+ 条 `draw_line`。5 个僚机 × 50 条 × 60Hz = 1.5 万 draw_line/s，纯装饰。

**修复**：直接删除数据链虚线。光环圈（1 个 `draw_circle` + 1 个 `draw_arc`）足够表达"被覆盖"的意图。

**教训** → R3 + R6

---

## 审查清单（PR / 新功能 checklist）

- [ ] 是否加了 `_process` / `_physics_process`？→ 能不能用信号/timer 替代？
- [ ] 是否调了 `queue_redraw`？→ 是真的需要每帧，还是状态驱动？
- [ ] `_draw` 里有没有循环/扫描？→ 用缓存列表，别现查
- [ ] 是否挂到 Aircraft/Missile 下？→ 先乘实体数再判断
- [ ] 新 AI 决策？→ 默认 `ai_tick_divisor ≥ 3` 起步
- [ ] `get_children()`？→ 换成 `CombatUnit.all_units` + `is_instance_valid`
- [ ] 视觉效果有多个 `draw_line` / `draw_polygon`？→ 合并成 `draw_polyline_colors` / `canvas_item_add_triangle_array`
- [ ] 改完了跑一下 Sentinel + Lv5+ 压力测试
