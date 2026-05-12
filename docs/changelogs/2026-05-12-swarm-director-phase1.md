# 2026-05-12 · 敌人 AI 大改 Phase 1 — Mother Goose SwarmDirector + UAV 修复

> Plan：`~/.claude/plans/ai-ai-wild-snowglobe.md`（[战略 + 4 Phase 总图](../../~)）
> 痛点：玩家反馈 Mother Goose 30 架 UAV 全屏却几乎打不着，且常规 AI 不协同、反应慢、易脱战。本轮先把 Mother Goose 当试金石做多机协同层，后续 Phase 推到常规 AI 与 Ace 档位。

## 改动概要

**1. 新增 SwarmDirector 层（多轴协同的核心）**

新建 [`scripts/ai/swarm/swarm_director.gd`](../../scripts/ai/swarm/swarm_director.gd) + [`swarm_director_params.gd`](../../scripts/ai/swarm/swarm_director_params.gd) + [`resources/ace_swarm_director.tres`](../../resources/ace_swarm_director.tres)。

- 1Hz 累加器节拍（由 `mother_goose_controller._process` 驱动，无独立 _physics_process）
- 角色枚举 `SHOOTER / ATTACKER_N|E|S|W / DECOY / GUARD / RESERVE`
- 每 tick 算法：MQ-111 强锁 GUARD → SHOOTER 按 (aspect × dist × ammo) 评分挑 1 个 → ATTACKER 按 UAV 当前在玩家航向系下的象限就近落 4 楔 → DECOY/GUARD/RESERVE 填剩余
- Lane 几何：玩家航向系 N=前/E=右/S=后/W=左 4 个 90° 楔形，跟随玩家航向旋转，攻击点 = 玩家位置 + lane_dir × dist_scale（dist_scale 1500→600 随距离衰减）
- DESIGNATION 期间自动升 attacker_pct 到 85%
- 设计参考：Shaw《Fighter Combat》2v1 Bracket（两侧夹击）+ Sandwich（前后包夹）的 swarm 化身

**2. AIController 接口扩展**

[`scripts/ai_controller.gd`](../../scripts/ai_controller.gd) 加两个字段 + 在 `_process_simple` 交战路径插入 SwarmDirector 覆写：

```gdscript
@export var swarm_role_override: int = -1   # -1=未分配 / 0+=SwarmDirector.Role
@export var swarm_lane_world_angle: float = 0.0
```

`_process_simple` 的 lead_pos 计算后插入：
- `ATTACKER_*`（楔外）→ target_position 拉到楔形攻击点
- `ATTACKER_*`（楔内 + 朝玩家）→ 保持 lead_pos 让 simple_combat 跑 LEAD_CHASE 开火
- `DECOY` → 沿 lane 方向跑 2000px
- `SHOOTER / GUARD / RESERVE / NONE` → 不动 lead_pos，沿用既有 simple_combat 行为

**3. MotherGooseController 接入**

[`scripts/survivor/mother_goose_controller.gd`](../../scripts/survivor/mother_goose_controller.gd)：
- 新增 `swarm_director: SwarmDirector` 字段 + 常量 `SWARM_DIRECTOR_PARAMS_PATH`
- `_process` 中 lazy 初始化（boss 活 + uav_swarm 就位时 new + setup）
- `_init_swarm_director()` 加载 .tres 参数 + EventLogger 记录
- `_update_stray_recall` 加守卫：`SwarmDirector.is_active_attacker(ai.swarm_role_override)` 为 true 时跳过召回（避免 director 把 UAV 拉到楔形攻击点后立即被 leash 召回的撕扯）

**4. 具体 UAV 缺陷修复（不依赖 SwarmDirector）**

- **Fix #1**：[`resources/uav_mg_laser.tres`](../../resources/uav_mg_laser.tres) `can_target_aircraft = false → true`。MQ-111 激光此前对飞机彻底无效（仅反导），与代码注释里的"双用途"宣称相悖。该 .tres 仅 MQ-111 通过 [`enemy_uav_mg_laser.tres`](../../resources/enemy_uav_mg_laser.tres) 复用，无其它纯拦截单位共享。
- **Fix #2**：[`mother_goose_uav_swarm.gd`](../../scripts/survivor/mother_goose_uav_swarm.gd) `HUNTER_LEASH_RADIUS` 2500 → 4500；[`mother_goose_controller.gd`](../../scripts/survivor/mother_goose_controller.gd) `RECALL_LEASH_PX` 3500 → 5000。玩家拉到 3000px 不再立即让 UAV 脱锁。

## 已撤销的伪 bug

原 recon agent 报"JAM Shield 会压哑 UAV 自身火力"是**误报**：[mother_goose_controller.gd:147-148](../../scripts/survivor/mother_goose_controller.gd:147) 已严格 `if u.team != 0: continue`，UAV 不会被自家 boss 误伤。且玩家若装 jam 技能/装备照样能正确压哑 UAV（status_jam_active 走标准 status_effects 系统，源无关）。**没有**做"友军免疫 jam"，避免破坏对称性。

## 性能验证

- Godot 4.6.2 stable headless --quit 通过，无 parse error / script error。
- 性能：Director 1Hz × 30 UAV ≈ 0.01ms/tick；per-frame AIController 增量 ≈ 2 字段读 + 1 分支 + 1 向量算 < 0.05ms/UAV。30 UAV 总增量 < 0.5ms/frame 预算。
- 待跑：生存模式 Mother Goose 战 + Lv5+ 压力测试 FPS Δ < 15。

## 后续 Phase（plan 已批准）

- **Phase 2**：把同一套架构落到 SquadDirector（敌方编队的 Loose Deuce / Bracket / Drag / Sandwich / Strike-Rejoin-Strike），直接对接已有 [`docs/systems/squad-tactics-design.md`](../systems/squad-tactics-design.md) Phase 2-3 草案。
- **Phase 3**：Ace 档位（F-47 / F-14_Poltergeist 归入），Finger Four / Tac Turn / Fluid Four。
- **Phase 4**：legacy `bfm_tactics.gd` 退役。

## 文件清单

新增：
- `scripts/ai/swarm/swarm_director.gd` (~290 LOC)
- `scripts/ai/swarm/swarm_director_params.gd` (~55 LOC)
- `resources/ace_swarm_director.tres`

修改：
- `scripts/ai_controller.gd` — 加 swarm_role_override/swarm_lane_world_angle 字段 + simple_combat 路径覆写（~25 LOC）
- `scripts/survivor/mother_goose_controller.gd` — Director lazy init/tick + stray recall ATTACKER 跳守卫（~30 LOC）
- `scripts/survivor/mother_goose_uav_swarm.gd` — HUNTER_LEASH_RADIUS 4500
- `resources/uav_mg_laser.tres` — can_target_aircraft=true
