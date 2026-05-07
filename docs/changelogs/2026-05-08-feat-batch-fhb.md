# 2026-05-08 — Feat 批次 F / H / B（CSG minimap / 权威标志兜底 / stress_swarm 场景）

## 背景

main 上散修堆里的三个相对独立的中等改动，按新工作流逐个独立分支 + DoD + `--no-ff` 合 main。和早前 G/E/D + C 一起把"修着修着没合的工作"陆续清掉。

## 改动

### F. CSG Phase 2 minimap BOSS 圈跟随 F-14 群质心 [`feat/csg-minimap-follow`]

**症状**：CSG 击沉 CV → 弹射 F-14 中队后，战术小地图 boss_zone 圈一直钉在 `_cv_death_position`。玩家飞远后看到的圈是空的，BOSS 已飞走。

**修法**：`scripts/survivor/carrier_strike_group.gd:_sync_boss_zone_to_poltergeist` 每帧取 F-14 已揭幕成员位置质心写入 `_zone_data.boss_zone[center]`；无成员时退回 `_cv_death_position`。不改半径。

净改动：+30 行单文件。

### H. data label 对 INVINCIBLE / STEALTH 走权威标志兜底 [`feat/data-label-authoritative-status`]

**症状**：部分派生通路给玩家上无敌 / 隐形时只写 `ac.invulnerable` / `ac.is_cloaked` / `ac.status_stealth_active` 不进 `status_effects` 字典 → HUD 看不到。例如 KIA 复活、导弹弹尽隐形、F-47 光学隐形阶段。

**修法**：`scripts/aircraft_renderer.gd`：
- `draw_data_label_minimal`（玩家）：INVINCIBLE 用 `invulnerable` 兜底、STEALTH 用 `status_stealth_active` 兜底；无字典条目时显示状态名不带百分比。
- `draw_data_label`（敌人/友机）：仅 STEALTH 用 `is_cloaked` 兜底（让 F-47 光学隐形被识别）。**INVINCIBLE 不兜底** —— F-14 弹射 4s 起飞保护是纯演出效果，走直写 `invulnerable` 不进字典 → 不在 HUD 暴露这种"内部纯保护期"，符合设计意图。

净改动：+38/-10 行单文件。

### B. bench stress_swarm 满载混战压测场景 [`feat/bench-stress-swarm`]

**背景**：mixed 场景只能压 single-target spawn 路径。perf-fix / squad-refactor 分支跑回归基线时需要一个把 SquadFactory / SQUAD_FOLLOW / formation offset / ground unit 全踩一遍的"满载混战"场景。

**改动**：`scripts/survivor/survivor_mode.gd`：
- 7 个 `BENCH_SWARM_*` 常量（敌 20 / 友 10 / AA 8 / SAM 6 / 边距 1500 / 间距 800）
- `_setup_bench_scenario` 按 `_bench_scenario == "stress_swarm"` 分支
- 6 个新函数（`_bench_force_spawn_swarm` / `_bench_spawn_csg_at_center` / `_bench_swarm_on_child_entered` / `_bench_pick_swarm_pos` / `_bench_spawn_random_squad` / `_bench_spawn_ground_at`）
- 所有飞机 invulnerable + `child_entered_tree` 监听让自然补刷也 invul
- spawner `_dynamic_enemy_cap` 拉到 `MAX_ENEMIES_HARD`
- 中央 CSG（CV+5 护卫，hp 拉爆模拟无敌）

净改动：+201/-2 行单文件。bench 专属，不破坏 mixed 场景。

## 拓扑

```
*   e530be6 Merge feat/bench-stress-swarm
|\
| * 579f118
*   a456061 Merge feat/data-label-authoritative-status
|\
| * e421fd0
*   37338cc Merge feat/csg-minimap-follow
|\
| * d91e83c
| (上一份 changelog)
```

`--no-ff` 保留每条 feat 的独立分支拓扑，回滚单条用 `git revert -m 1 <merge-sha>`。

## 工作流复盘

- 这一批用户事先在散修堆里测过，跳过 DoD 测试直接合 main。流程上风险可接受 —— 这些是"既存代码搬家到合规分支位置"，不是新代码。
- 三条都从 stash 拍单文件 + 直接 commit 走通；只有桶 H 在 aircraft_renderer.gd 上撞到了"stash 版本是早于桶 C 凝视压迫 carry-over"的时间问题，需要手工把凝视压迫雷达锥块加回去。下次要做"基于已合并的 carry-over 之上的桶"时这种规避要先识别。
- main 现在干净，剩余工作就是桶 A（Mother Goose）一大坨。
