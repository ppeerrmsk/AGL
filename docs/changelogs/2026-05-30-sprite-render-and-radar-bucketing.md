# 2026-05-30 · 飞机图标 Sprite2D 化（渲染重构阶段 1）+ 雷达/子弹 O(N²) 根治

> Plan：[docs/planning/sprite-multimesh-refactor.md](../planning/sprite-multimesh-refactor.md)
> 触发：后期全屏大量交战的性能预期（实体峰值 22 → 80~150），先吃掉 _draw 里"飞机图标"这块顶点大头；过程中顺带把真实多源火力暴露的雷达/命中 O(N²) 根治。

## 改动概要

### 1. 飞机图标 Sprite2D 化（渲染重构阶段 1，flag 默认 **on**）

`USE_SPRITE_AIRCRAFT_ICONS` 把 `_draw` 自绘的飞机本体图标换成子 `Sprite2D`，让 Godot 按纹理自动批处理；雷达锥/瞄准锥/特效/标签仍走 `_draw`。

- [`aircraft_renderer.gd`](../../scripts/aircraft_renderer.gd)：抽 `draw_fighter_geometry` / `icon_dynamic_scale` 共享几何+缩放单一来源（live `_draw` 与烘焙器同源，消除三处重复 + drift）
- [`aircraft.gd`](../../scripts/aircraft.gd)：`_setup_sprite_icon` 挂子 Sprite2D，`_update_visuals` 每帧同步 bank/高度/机动 scale；坠毁时隐藏 sprite 让 `_draw` 灰色坠机图标接管
- 运行时烘焙器 [`bake_icons_runtime.gd`](../../scripts/tools/bake_icons_runtime.gd) + `scenes/tools/bake_icons.tscn`（无需编辑器 GUI，可被 godot-mcp / CLI 驱动），烘 `fighter.png` + manifest；缺纹理回退 `_draw`
- v1 只有 fighter silhouette 有烘焙纹理；commander/bomber/apache 等自动回退 `_draw`（待 v2）

**视觉回归修复（逐一确认）**：转弯压缩动画、预测线遮挡图标、坠机外观消失、眼镜蛇纵向"超前压缩"——四处全部修复。眼镜蛇恢复 sy-only 纵向压缩、J-Turn 保持各向同性（快速偏航防抖）。

**A/B 实测（RTX 3080）**：52 架 draw-bound 场景 **FPS +89%**（33→63），27 架 draw CPU **−82%**（529→95µs/帧），视觉零回归 → flag 默认 on。

### 2. 单位标签三档统一配色

[`game_constants.gd`](../../scripts/game_constants.gd) `unit_label_style(team, is_player_controlled)` 单一来源返回 `[bg,text,border]`：操控者→冷白底蓝边；己方非操控→蓝底白边；敌方→红底白边。全程禁纯白防刺眼。ground_unit / missile / naval_unit 的 data label 改走此 accessor + 1px 边框。

### 3. 屏幕外圈受击/异常/治疗反馈（DamageVignette）

[`survivor/damage_vignette.gd`](../../scripts/survivor/damage_vignette.gd) 全屏 Control，按玩家状态在屏幕外圈染色脉冲；add 在 ThreatOverlay 之前。`aircraft._apply_damage` 写 `hud_last_damage_at` 时间戳供其每帧读取。

### 4. 子弹 MultiMesh 化（渲染重构阶段 2，flag 默认 **off**）

`USE_MULTIMESH_BULLETS` 脚手架完成（[`bullet_manager.gd`](../../scripts/bullet_manager.gd) `_setup/_update_multimesh_tracers`，机炮弹走 MultiMeshInstance2D + QuadMesh）。

**评估结论：默认保持 off**。MultiMesh 子弹只在 ~4000 颗（GPU object-bound）才赢（+49% FPS），现实子弹量（100~300，极端 1500）反而略亏——Godot 2D 批处理器本来就把 `draw_line` 批得很好，子弹没有 sprite 那样的 CPU 大头可削。脚手架保留作弱硬件 / 极端弹量后手（objs −89~94% 与分布无关）。

### 5. 雷达/子弹命中 O(N²) 根治（敌我方预分桶）

阶段 2 评估时用「140 AA 炮环射真实子弹」压测，暴露真实多源火力的瓶颈在 **CPU**（雷达 + 命中 O(N²)），非渲染。根治：

- 中央雷达锁定循环（[`survivor_mode._update_radar_locks`](../../scripts/survivor/survivor_mode.gd)）与子弹命中循环（[`bullet_manager._physics_process`](../../scripts/bullet_manager.gd)）原本每个 shooter/子弹全扫 `all_units` 再按 team 跳过同阵营——为找少量对方目标白扫全部 N。
- 改为每帧把单位按敌我方预分桶，shooter/子弹只遍历对方阵营列表。雷达分桶在 `_update_aircraft_list`，子弹分桶在 `bullet_manager._rebuild_team_buckets` 自建（沙盒亦安全）。
- **可证等价**：处理的 (shooter,target) 配对集合完全不变，零行为变化。
- 实测：radar_pairs **2967→38/帧（−98.7%）**，team-1 子弹命中候选 137→1。常规混编 27 单位零回归（FPS 118.5）。
- 共享基建登记进 [performance-guidelines.md](../reference/performance-guidelines.md)「敌我方预分桶」行。

### 6. bench 基建

bench 跑分新增渲染监视器采样（draw_call/FPS/objs/prims/bullets 窗口均值，跳 2s 预热）+ `bullet_storm`（散布汇聚 visual_only 弹，隔离纯渲染）+ `ground_storm`（AA 炮环射真实弹）压测场景。

## feature flag 现状

| flag | 默认 | 说明 |
|---|---|---|
| `USE_SPRITE_AIRCRAFT_ICONS` | **on** | 飞机图标走 Sprite2D；A/B 验证通过 |
| `USE_MULTIMESH_BULLETS` | off | 子弹 MultiMesh；现实量级无收益，留作弱机后手 |
| `SHOW_PERF_HUD` | off | F6 切换 perf HUD |

## 未做 / 后续

- 子弹空间哈希（仅均势大乱斗有边际收益，有船体跨格风险）——暂缓
- 烘焙器 v2：commander/bomber/apache 等 6 个 silhouette
- 单位数本身的 LOD（140 单位场景仍 CPU-bound，属另一议题）
