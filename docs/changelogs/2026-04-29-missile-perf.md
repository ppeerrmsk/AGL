# 2026-04-29 — VLS / CSG BOSS 战导弹性能优化

## 背景

CSG（航母战斗群）BOSS 战开打瞬间 8~13 枚 VLS 导弹同时升空（2×CG 各 4 枚 + 1×DDG 5 枚，齐射间隔 0.07s 内全部 spawn），第二相再叠加玩家 + Poltergeist 双方导弹后峰值 20+ 枚。每枚 `Missile` 都是独立 `Node2D`，在 `_physics_process` 里：

- 各自查 `target.global_position` / `heading` / `speed` / `is_cloaked` / `flat_altitude` / `get_altitude_tier()`
- 各自查 `source.radar_targets.get(target, 0.0)`（SARH 锁定进度）
- 各自调 `get_tree().get_first_node_in_group("weather").is_in_cloud(global_position)`（云层穿越）

VLS 齐射弹大多是同源同目标，这些查询完全可以复用一次。开战瞬间帧时间陡增的主因。

## 改动

### 1. MissileManager 帧级共享快照（[missile_manager.gd](../../scripts/missile_manager.gd)）

`_physics_process` 头部新增 `_build_frame_snapshot()`：每帧重建 3 个字典：
- `_target_snap[target_id]` → `{pos, heading, speed, alt, is_destroyed, is_aircraft, is_cloaked, flat_altitude, alt_tier}`
- `_lock_snap["src_id:tgt_id"]` → SARH 锁定进度（仅非 fire-and-forget 弹种）
- `_cloud_snap[grid_256px]` → 云层在位（按 256px 网格量化共享）

`process_priority = -10` 保证 MissileManager 先于 Missile 子节点运行。

新增三个 API 给 Missile 调用：
- `get_target_snap(target) -> Dictionary`（命中返回快照 dict，未命中或开关关闭返回 `{}`）
- `get_lock_progress(source, target) -> float`（命中返回锁定进度，未命中返回 -1.0）
- `get_in_cloud(world_pos) -> bool`（云层网格查询；未启用快照时回退到旧路径）

### 2. Missile 改为从快照读（[missile.gd](../../scripts/missile.gd)）

`_physics_process` 在解析阶段一次性把目标 9 个字段拍成局部变量（`t_pos`、`t_heading`、`t_speed`、`t_alt`、`t_destroyed`、`t_is_aircraft`、`t_is_cloaked`、`t_flat_altitude`、`t_alt_tier`）。优先 `_mm.get_target_snap()`，未命中走直接属性读（保留旧路径，开关关掉行为完全等同）。

`_guidance_degradation_for(t_flat, t_tier)` 接受预解析参数；旧 `_guidance_degradation()` 改为薄壳调用前者，对外行为不变。

### 3. VLS phase 0/1 降帧 tick

VLS 齐射弹的 phase 0（VERTICAL 垂直爬升）和 phase 1（TRANSITION 朝固定 `vls_locked_point` 转向）是**确定性弹道** — 不需要 60Hz：
- 加 `_vls_low_rate_counter`，每 3 帧执行一次（~20Hz），把累积 delta 一次性传入 `_update_vls_non_terminal()`，保证位移/速度积分总量不变。
- phase 切换为 2（TERMINAL）后立刻恢复 60Hz PN，counter 清零。

视觉影响：phase 0 直线垂直爬升、phase 1 平滑大圆弧 — 20Hz 与 60Hz 肉眼不可分辨。火柱齐射观感保持。

### 4. 总开关（[survivor_data.gd](../../scripts/survivor/survivor_data.gd)）

- `ENABLE_MISSILE_FRAME_SNAPSHOT: bool = true`
- `ENABLE_VLS_LOW_RATE_TICK: bool = true`

两者独立，便于 A/B 压测 + 单独回滚。关掉后 Missile 走旧路径，行为完全等同于改动前。

## 预期收益

CSG 战峰值（13 枚 VLS 同 source/target，phase 2 阶段）：
- target 字段查询 13× → 1×
- radar_targets 字典查询 13× → 1×
- weather.is_in_cloud 13× → 1~3×（按位置分组）

VLS phase 0/1 阶段（齐射后 ~4 秒内）：每弹 60Hz → 20Hz，省 ~67% 的 phase 早期算力。

## 验证

**自动**：暂无导弹专项测试。`scripts/tests/test_bfm_intent.gd` 不涉及导弹，但 PN/制导公式未改 → 行为应等同。

**手测**：
1. 沙盒 F-14 多枚发射：普通空空导弹命中率 ≥ 80%（10 发抽样）
2. 生存模式 CSG BOSS 战：开战 5 秒平均 FPS 应较 main 分支 ≥ +10
3. 目视确认 VLS 火柱齐射弹道顺滑、phase→phase 切换无跳跃
4. 关闭两个 ENABLE_* 开关跑一次 CSG 战，确认行为完全等同改动前

**回滚**：`SurvivorData.ENABLE_MISSILE_FRAME_SNAPSHOT = false` + `ENABLE_VLS_LOW_RATE_TICK = false` 即可。

## 第二轮（2026-04-29 续）— CIWS 子弹热点

第一轮跑下来 CSG 战仍卡。诊断后发现 CIWS 才是大头：12 个 CIWS × 33Hz 视觉射速 = ~800 颗子弹同时在飞。`bullet_manager.gd:_physics_process` 命中循环里：

1. **每颗子弹 × 每架飞机** 都调 `Aircraft.get_maneuver()` + `Aircraft.get_herbst()` — 两次都遍历 Aircraft 的所有子节点。264 真弹 × 5 飞机 × 2 调用 = **2640 次子节点遍历/帧**
2. **每颗 CIWS 子弹** 都跑 `missile_manager.get_children()` 找敌方导弹 — 264 子弹 × 13 导弹 = **3432 次遍历/帧**
3. `naval_weapons._find_incoming_missile_for_ciws` 12 个 CIWS 各扫一次同样的 `missile_manager.get_children()`，6.7Hz 节流后仍 **80 次/秒**

### 改动

**[bullet_manager.gd](../../scripts/bullet_manager.gd)** — `_physics_process` 顶部新增 `_build_frame_cache()`：
- `_frame_unit_immune[unit_id] -> bool` — 提前合并 cobra/herbst/missile_phase 三个免疫源，所有子弹共用一份
- `_frame_enemy_missiles_by_team[team] -> Array[Missile]` — 按"射手 team 视角"预过滤的活跃敌方导弹列表

子弹命中循环里：单位免疫从字典查（O(1) 替代两次子节点遍历）；CIWS 子弹查导弹遍历预过滤的小数组（替代 missile_manager 全员 + 类型/活跃/team 三重 filter）。

**[naval_weapons.gd:_find_incoming_missile_for_ciws](../../scripts/naval/naval_weapons.gd)** — 优先调 `bullet_manager.get_enemy_missiles_for_team(nu.team)` 共用同一份缓存；缓存关闭或未连接时回退原始 `get_children()` 路径。

**[survivor_data.gd](../../scripts/survivor/survivor_data.gd)** — 加 `ENABLE_BULLET_FRAME_CACHE: bool = true`。

### 预期收益（CSG 战峰值 800 子弹 + 13 导弹 + 5 飞机）

- 子弹命中循环子节点遍历：2640 次/帧 → 0（缓存命中替代）
- CIWS 子弹查导弹：3432 次迭代/帧 → 264 × ~5 (filter 后 candidate 数) ≈ 1320 次（直接读小数组，无类型/活跃/team filter）
- naval_weapons CIWS 锁定扫描：12 mounts × 6.7Hz × 13 导弹 → 12 × 6.7Hz × 共享 candidate（开销与单次构建持平）

### 验证（追加项）

- 沙盒 F-14 用机炮打 AI（确保普通机炮命中链路未坏）
- CSG 战开战瞬间 FPS 较第一轮再 +5～+10
- 玩家发射的导弹被 CIWS 拦下时仍记录 EventLogger("CIWS", "Player", "intercepted missile")
- 关闭 `ENABLE_BULLET_FRAME_CACHE` 跑一次 CSG，确认行为完全等同

---

## 不做的事

- 不重写 PN 公式 / 不合并 Missile 节点为扁平数据数组（性价比低、影响 trail/AOE/draw）
- 不缓存跨帧目标位置（一帧一刷新，不引入插值误差）
- 不改命中检测循环（13×3 = 39 次距离检查/帧不是热点）
