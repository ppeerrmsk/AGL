# 2026-06-13 战斗日志可追踪性增强（KILL 归因 / 导弹脱靶 / 战报汇总）

用户需求：方便后续追踪各类问题。补齐三处日志盲区（都是低频事件点，对性能无感）。

## 1. `KILL` 事件 —— 谁用什么击坠了谁
死亡瞬间打一行，省去人工关联 `fired → hit`。
- 接入点：[aircraft.gd `_record_kill_attribution`](scripts/aircraft.gd)（归因数据现成，只差打印）。
- 武器种类取自 `_last_damage_kind` meta → 中文标签（机炮/导弹/火箭弹/爆炸/坠地），见新增 `_kill_weapon_label`。
- 样例：`[KILL] Friend/F-16 SmartFalcon[Ultra]: 导弹击坠 Enemy/J-7[Nexus]`
- 注：`DESTROY` 行保持不变（只写被击毁者），`KILL` 是补充行。无攻击者的死亡（坠地/燃油）不打 KILL。

## 2. `MISSILE` 脱靶/丢锁事件 —— 让"射空"在日志里可见
命中走 `MissileManager` 直接 `queue_free`，**不经 `_start_fade_out`** → 每次 fade 必是未命中。
在 [missile.gd `_start_fade_out`](scripts/missile.gd) 接入 `_log_miss`，按原因归类：
- `目标已被摧毁(火力浪费)` / `目标已消失`
- `热诱弹干扰` / `末段丢锁(出导引头FOV)` / `寿命耗尽` / `能量耗尽`
- `末段丢锁` 靠新增标志 `_guidance_ever_lost`（FOV 丢锁处置位）区分——**这正是 team_inbound
  幽灵封锁那类 bug 此前在日志里静默无踪的根源**，现在每枚射空弹都留痕。
- 样例：`[MISSILE] Friend/F-16[Ultra]: MRM 脱靶 → Enemy/F-4[Locus] (末段丢锁(出导引头FOV)/寿命耗尽)`

## 3. 局末战报汇总 —— 每机击坠/命中/命中率
[event_logger.gd](scripts/event_logger.gd) 新增轻量累计器 `_stats`：
- `tally(subject, key, n)`：在低频点（KILL / 机炮命中 / 导弹发射·命中·脱靶）各 +1，cost ≈ 1 dict++。
- `format_stats_summary()`：F9 导出时追加到日志末尾，按击坠降序。
- `reset_stats()`：[survivor_mode `_ready`](scripts/survivor/survivor_mode.gd) 新局开始时清零，防跨局污染。
- 接入计数点：`_fire_missile_at` / `_fire_multi_lock_salvo`（msl_fired）、`missile_manager` 命中（msl_hit，
  按 `missile.source` 归到射手）、`missile._log_miss`（msl_miss）、`bullet_manager` GUN 命中（gun_hits）。
  **不**逐子弹计 shots_fired（高频），机炮只计命中数——故无机炮命中率，仅导弹有命中率。
- 样例：`Friend/F-16 SmartFalcon[Ultra] 击坠=2 机炮命中=0 导弹[发射=5 命中=2 脱靶=2 命中率=50%]`

## 性能
全部挂在低频事件点（死亡 / 导弹消亡 / 命中）。机炮按"命中"而非"发射"计数（命中本就稀疏，
全局一局仅数十次）。无 `_process` 轮询、无每帧扫描。`_stats` 内存 = 每机一条 dict。

## 验证
`godot --headless --path . -- --bench=stress_mixed --duration=60`：编译干净，生成的 combat_log 内
三类新行全部出现且分类正确：
```
[16.5] [KILL] Friend/F-16 SmartFalcon[Ultra]: 导弹击坠 Enemy/J-7[Nexus]
[53.8] [MISSILE] Friend/F-16[Ultra]: MRM 脱靶 → Enemy/F-4[Locus] (末段丢锁(出导引头FOV)/寿命耗尽)
=== 战报汇总 (本局累计) ===
Friend/F-16 SmartFalcon[Ultra] 击坠=2 机炮命中=0 导弹[发射=5 命中=2 脱靶=2 命中率=50%]
Enemy/F-4 Phantom[Monsoon]     击坠=0 机炮命中=33 导弹[发射=3 命中=0 脱靶=2 命中率=0%]
```
脱靶原因分类（热诱弹/末段丢锁FOV/寿命耗尽）均按预期触发。
