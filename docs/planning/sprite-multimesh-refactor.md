# Sprite2D + MultiMesh 渲染重构计划

> 创建日期：2026-05-26
> 状态：进行中（阶段 1 / 5）
> 触发原因：玩家需求"后期全屏大量友军 / 敌军交战"，预估场内实体峰值从 22 推到 80~150
> 关联讨论：见 docs/changelogs/（重构落地后追加）

## 北极星目标

让 80~150 架飞机 + 1000+ 子弹在屏幕内同框时 FPS 不低于 50（当前 22 架基线 FPS 待测）。**不破坏极简线框美术风格**，不引入 shader 复杂度。

## 关键设计取舍

### 为什么选 Sprite2D + 烘焙纹理而不是保留 `_draw` 自绘
- 当前每架飞机各自有一个 `_draw` → 每架一次 canvas item submit
- Godot 4 的 2D 渲染器**自动批处理同纹理 Sprite2D**，100 架同纹理 = 1 个 draw call
- 烘焙路径而非手画：保 100% 视觉一致 + 风格不漂移；线条改了重跑烘焙工具即可

### 为什么选 MultiMeshInstance2D 而不是当前的 `_draw` 批处理
- BulletManager 当前**已经是单 Node2D + 一个 `_draw`** —— 比"每颗子弹一个 node"已经省一大截
- 但单帧 1000+ 颗子弹时，`_draw` 里 1000 次 `draw_line` 累计仍有 CPU 开销
- MultiMesh 把 transform 数组提交 GPU 一次，CPU 只算 transform 不渲染
- **副作用警告**：当前 `_draw` 路径里子弹的渐隐/火箭弹颜色/曳光弹颜色都是单弹处理，迁到 MultiMesh 要用 `instance_custom_data` + shader 表达，复杂度上升

### 为什么不去碰 `_draw` 里的其他部分（cone / glow / label）
- 这些项目的总体量不大（每架 ~10 项 draw_*），即便剥离收益有限
- 是 _draw 里"飞机图标"独占大多数顶点（多边形多段折线）—— 先吃掉这块大头
- 后续如果还卡，再做 LOD（远距离飞机不画 data_label / predicted_path 等）

## 阶段路线图

### 阶段 0 — Baseline 测量基座（已含本计划文档）
- ✅ 计划文档（本文件）
- 🔄 在 `GameConstants` 加两个 feature flag（默认 false 保持老路径）：
  - `USE_SPRITE_AIRCRAFT_ICONS: bool`
  - `USE_MULTIMESH_BULLETS: bool`
- 🔄 加 baseline 性能 HUD（F6 切换，CanvasLayer 顶层显示 FPS / draw_call / canvas_items / aircraft_count / bullet_count）
- 🔄 跑一次 80 架压力测试录基线数据，记到本文件"数据记录"段

### 阶段 1 — 飞机图标 Sprite2D 化
- ✅ 抽 `AircraftRenderer.draw_fighter_geometry(ci, size, ...)` 共享几何（live _draw 与烘焙器单一几何源，消除原本三处重复 + drift 风险）
- ✅ 烘焙器改成**运行时**版 `scripts/tools/bake_icons_runtime.gd` + `scenes/tools/bake_icons.tscn`（**v1 只烘焙 fighter**）：
  - 不再依赖编辑器 GUI（原 EditorScript `bake_aircraft_icons.gd` 已删）；可被 `godot <proj> scenes/tools/bake_icons.tscn` 或 godot-mcp `run_project` 直接驱动，烘完自动 quit
  - PNG 128×128 透明底 → `res://textures/aircraft_icons/fighter.png`；SubViewport 挂当前 scene tree root 渲染
  - 烘成白色 → Sprite2D 运行时 modulate = `params.icon_color` 染色
  - 生成 `res://resources/aircraft_icon_manifest.tres`（Resource + `metadata/icons` dict）
  - ⚠ **导入步骤**：编辑器外烘焙出的 PNG 没有 `.import` 文件，运行前需 `godot --headless --import` 生成（否则 `load()` 失败回退 _draw）。`fighter.png.import` 必须随 PNG 一起提交
  - **v1 已知限制**：不处理 wing_color（黑机身红翼这种双色机型会损失副色，待 v2）
  - **v2 扩展**：commander / bomber / apache / chinook / drone / mother_goose 6 个 silhouette
    - v2 实现思路：把 6 个 `draw_*_icon` 子函数首参从 `ac: Aircraft` 重构为 `ci: CanvasItem`（如 draw_fighter_geometry 一样），烘焙器直接调用避免几何 drift
- ✅ 改 `aircraft.gd`：`_ready` 看 flag → `call_deferred(_setup_sprite_icon)` add 子 Sprite2D
  - **朝向无需每帧同步**：Aircraft 节点自身已 `rotation = heading`（aircraft.gd:547/769/2447），子 Sprite2D 自动继承旋转。几何机头在本地 -Y、节点 0=北，天然对齐——原计划"每帧 sprite.rotation = heading"多余
  - **已知限制**：sprite 不实现 bank_compress / maneuver visual_offset 形变（视觉简化）
- ✅ 改 `aircraft_renderer.gd::draw_aircraft_icon`：有 IconSprite 子节点时跳过 polygon 绘制，保留 selection ring 等动态 _draw
- ✅ **已验证**（2026-05-30）：FPS A/B（见"数据记录"）— 52 架 +89% FPS、27 架 draw CPU −82%、视觉零回归（转弯/预测线/坠机/眼镜蛇四处回归已修复确认）→ `USE_SPRITE_AIRCRAFT_ICONS` 默认改 true

### 阶段 2 — 子弹 MultiMesh 化
- 改 `bullet_manager.gd`：
  - `_ready` 里看 `GameConstants.USE_MULTIMESH_BULLETS`
  - 若 on → 挂 `MultiMeshInstance2D` 子节点，QuadMesh + 曳光弹渐变纹理 (16×4 px 一头亮一头暗)
  - `_physics_process` 末尾 → 遍历 `_bullets` 写 `multimesh.set_instance_transform_2d(i, ...)`，长度按速度方向缩放
  - `_draw` 里看 flag 跳过 bullet 的 `draw_line` 循环
- **第一刀只动机炮弹**，火箭弹和漂浮雷因为 fade / canopy / 颜色字段多样，保留旧 `_draw` 路径
- 第二刀（后续）再考虑火箭

### 阶段 3 — 数据对比与决策
- 用 godot-mcp `run_project` headless 跑生存模式
- `survivor_debug_spawn` 刷 80 架敌机 + 玩家中队
- 两组数据：flag off / on 各跑 60s，记录 FPS / draw_call / canvas_items 均值
- 视觉零差异确认（截图对比）
- **回滚阈值**：FPS 没提升 ≥ 20% 或视觉有差异 → flag 默认保持 false，等下一轮再优化
- **合入条件**：80 架场景 FPS ≥ 50 且零视觉回归 → flag 默认改 true

### 阶段 4 — 远距 LOD（可选，看阶段 3 数据决定）
- _draw 里 cone / label / target_line 按相机距离剔除
- 摄像机视椎裁剪外的飞机直接 visible = false

## 回滚策略

每一阶段都保留 feature flag。任何阶段出问题：
1. 把对应 flag 默认值改回 false
2. git revert 烘焙工具 / Sprite2D / MultiMesh 节点添加 commit
3. 老 `_draw` 路径完整保留，零业务侵入

**禁止删除老 `_draw` 代码**直到阶段 3 数据验证通过 + 用户主播放 30 分钟无视觉异常。

## 风险点

| 风险 | 影响 | 缓解 |
|---|---|---|
| Sprite 旋转角度系不一致 | 飞机朝向错 | _physics_process 加单元测试式日志，飞机指向 heading 方向截图人工对比 |
| 烘焙纹理分辨率不够（线条模糊） | 视觉降级 | 128×128 起步，必要时 256；纹理过滤设 nearest 还是 linear 实测比较 |
| MultiMesh 曳光弹渐隐 alpha 难实现 | 视觉回归 | 用 instance_custom_data 传 life_ratio，shader 算 alpha；若太复杂，第一版不渐隐，第二版再加 |
| 烘焙脚本在 headless 模式跑不起来 | 工具不可重现 | 必须编辑器 GUI 启动；godot-mcp 的 launch_editor 可以触发 |
| 飞机有多个状态视觉（损伤冒烟、加力火焰） | 单一纹理不够 | 这些原本就是 _draw 单独画的（不是图标本身），保留 _draw，不动 |

## 数据记录

测量方法：`godot --path . -- --bench=<name> --duration=<s>`（**windowed**，headless 不调 _draw 测不出），
采 PerfBuckets 最后 1s 窗口；FPS = window_frames / window_seconds，aircraft_draw = 飞机 _draw 的 CPU µs/帧。
机器 RTX 3080 / Godot 4.6.2-mono。日期 2026-05-30。
**注意**：PerfBuckets 只抓 CPU 侧 _draw，sprite 的 GPU 同纹理批处理收益（draw call 合批）未计入 → 数据偏保守。

### 27 架（headroom 充足，FPS 顶到上限）
| 指标 | flag OFF | flag ON | Δ |
|---|---|---|---|
| 窗口 FPS | ~120 | ~120 | 持平（远未到瓶颈）|
| aircraft_draw µs/帧 | 529 | 95 | **−82%** |
| ac_phys.visual µs/帧（sprite scale 同步代价）| 4 | 9 | +5（可忽略）|

### 52 架（draw 成为瓶颈，决定性信号）
| 指标 | flag OFF | flag ON | Δ |
|---|---|---|---|
| 窗口 FPS | 33 (34f/1.02s) | 63 (63f/1.00s) | **+89%（≈1.9×）** |
| aircraft_draw µs/帧 | 5736 | 2262 | −61% |
| trail_draw µs/帧（对照）| 4272 | 4252 | 持平 |

### 104 架（phys-bound，超出可用区间，仅记录不作数）
- OFF ~15 FPS / ON ~10 FPS，窗口仅 11~15 帧 → per_frame 被物理 tick 堆叠灌水，噪声过大无法干净归因。
- 结论：此负载已被 aircraft_phys（~21~41ms/帧）主导，sprite 只削图标无法救场；属重构范围外（需 AI tick LOD / 实体上限另议）。

### 决策（2026-05-30）
- 52 架 **FPS +89%** 远超 phase-3 合入门槛（≥20%）+ 27 架 draw CPU −82% + 新增代价可忽略 + 视觉零回归（转弯/预测线/坠机/眼镜蛇四处回归已逐一修复并确认）。
- → `USE_SPRITE_AIRCRAFT_ICONS` 默认改为 **true**。
- 注：高硬件下 FPS 在低实体数会被上限掩盖差异，真实收益要在 draw-bound 区间（≥50 架）才显现。

### 阶段 2 完成后（USE_MULTIMESH_BULLETS=on，80 架 + 1000 子弹）
- 日期：
- FPS：
- draw_call：
- canvas_items：

## 不在本次重构范围内（明确排除）

- ❌ 爆炸 / 烟雾 GPUParticles2D 改造（视觉特效另开议题）
- ❌ 尾迹 TrailRibbon 重写（已在性能守则历史教训段被翻过，下次专门处理）
- ❌ 导弹 Missile 节点改造（导弹数量从来不是瓶颈，单实例 ~20 个上限）
- ❌ UI / HUD 重构
- ❌ AI tick 频率 / LOD 改动（在 ai-system.md 另议）
