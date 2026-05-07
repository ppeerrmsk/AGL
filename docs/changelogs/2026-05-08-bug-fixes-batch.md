# 2026-05-08 — Bug Fix 批次（zoom redraw / fear_chills 联动 / multi-lock 齐射）

## 背景

按新工作流（`~/.claude/plans/clever-spinning-hummingbird.md`）首批跑通的三个独立档 1 修复，每条单独分支 + DoD 验证 + `--no-ff` 合 main，目的是验证"任务封套"流程能否运行起来。三个 bug 都在 main 上挂着没合的散修堆里。

## 改动

### A. 船体状态标签缩放重画 [`fix/naval-zoom-redraw`]

**症状**：相机缩放跨级时，船体状态标签（"DDG-776 Marauder / HDG 180 / 14 KTS"）随世界一起放大缩小，与飞机标签的"恒定屏幕大小"行为不一致。表现为新刷出来的船一开始巨大，被攻击后才"突然变正常"。

**根因**：`_draw_status_label` 把 `inv_zoom = 1 / viewport_scale` 烤进 canvas item，但 `_should_redraw` 没有 zoom 触发器。"被攻击后变正常"实为命中暴露 `weak_point.revealed` → 进入每帧重画路径并非伤害本身。

**修法**：`scripts/naval/naval_unit.gd` 在 `_physics_process` 内 LOD 节流之前每帧检测 `viewport_transform.scale` 量化变化，独立 `queue_redraw()`。不放在 `_should_redraw` 末尾是因为：
- 远距船被 LOD 节流跳过 5/6 帧
- `_should_redraw` 早返回路径（hover/lock/weak）会短路末尾的检查

净改动：14 行（commit `7b71213`，迭代了 v1 → v2 一次，详见 commit log）。

### B. fear_chills 联动覆盖三条 AOE FEAR 入口 [`fix/fear-chills-aoe-slow`]

**症状**：玩家持有 `寒颤 / fear_chills`（FEAR 同步附带 SLOW），但只有单体 FEAR 路径有效。AOE FEAR 触发时（机炮震慑 / 惊鸿扩散 / 凝视压迫）目标只上 FEAR、不上 SLOW。

**根因**：FEAR 状态有 4 个入口分散在 3 个文件：
1. `survivor_spawner._apply_player_fear` — 单体 ✓ 原本就有联动
2. `skill_hooks.dispatch_on_kill` gun_kill AOE — ✗ 漏
3. `skill_hooks.dispatch_on_kill` head_on AOE — ✗ 漏（v1 修了这一条）
4. `survivor_mode` 凝视压迫累积锁定 AOE — ✗ 漏

v1 只在 head_on 路径加了 `if killer.fear_applies_slow → 同时调一次 AOE SLOW`，验证时用户在凝视压迫触发的 Tu-160 上发现仍无 SLOW。

**修法**：把 fear_applies_slow 联动检查塞进 `AOEBroadcast.apply_status_in_radius` 内部 —— 三条 AOE FEAR 都过这个 helper，一处改全员通。`source is Aircraft + team==0 + fear_applies_slow + status_effects.has(FEAR)` 同时成立时追加施 SLOW。fear_immune 单位（Mother Goose UAV 预留）的 FEAR 已被 `combat_unit.apply_status` 入口拒绝 → has(FEAR) 为 false → 自然不施 SLOW。

净改动：13 行（aoe_broadcast.gd +11 / skill_hooks.gd +2 -6）。已记入 known-seams 候选条目"FEAR 入口分散到 4 处"。

### C. multi-lock 齐射不再要求 combat_target 出现在 locked_targets [`fix/multi-lock-salvo-combat-target`]

**症状**：玩家拿了 missile_swarm（`max_simultaneous_locks > 1`，齐射成为唯一发射路径）后，点远处尚未进雷达包络的目标 → `combat_target` 设上但 `locked_targets` 里没它 → 齐射函数整体 `return false` → 已锁定的近距目标也跟着不开火。UX：点远了反而卡死。

**根因**：旧逻辑把 `combat_target ∈ locked_targets` 当作"独占发射许可"，与 missile_swarm 语义冲突。

**修法**：`aircraft_weapons.gd:_fire_multi_lock_salvo` 移除独占检查，combat_target 仅作排序优先级提示（下方排序逻辑保留语义）。双击冲锋路径不受影响：上层 `weapon_preference=PREFER_GUN` 早就阻断了导弹分支。

净改动：9 行 +9 -12。

## 拓扑

```
*   ef14061 Merge fix/multi-lock-salvo-combat-target
|\
| * 88a4f1c
*   40f344b Merge fix/fear-chills-aoe-slow
|\
| * 45d1319 v2 集中到 AOEBroadcast
| * 56f7b7d v1
*   3aa97ee Merge fix/naval-zoom-redraw
|\
| * 7b71213 v2 上移到 _physics_process
| * daa6503 v1
* fcb426b (上一次 main)
```

`--no-ff` 保留每条 fix 的独立分支拓扑，回滚单条用 `git revert -m 1 <merge-sha>`。

## 工作流复盘

- A 和 B 都经历 v1 → v2，原因都是"第一次只解决了 1 个表面入口，根本耦合点更深"。这是档 1 升档的典型场景，触发了 plan §"bug 修着修着挖到地基"协议。本批两次都是用 v2 方式做了"轻量重构 + 集中点"而非档 3 大改造，控制在档 2 范围内完成。
- 后续要建 `docs/architecture/known-seams.md`，把这两个收进去：
  - SEAM-NAVAL-LABEL-ZOOM：脏驱动 redraw 漏点（zoom 不在原跟踪字段里）
  - SEAM-FEAR-MULTI-INLET：FEAR 状态有 4 处入口（1 单体 + 3 AOE 分散在 3 个文件）
- 三条 fix 全部走 plan 工作流：分支 → plan 文件 → commit → 用户验证 → `--no-ff` 合 main → 本 changelog。下次目标：把这套套用到桶 C（aura CD + 凝视压迫雷达锥 hover 预览）。
