# 2026-05-09 时间制战区循环改造

## 背景

旧机制：累计攻克 3 个战区 → 强制进 BOSS。问题：
- 玩家无法循环刷战区累积升级，节奏由"3 个一到"硬切。
- 出界补给一键满血无代价，反复贴边回血是最优解。
- 局长无硬上限。

## 改动

### 阶段制
- 战区阶段：0–8 分钟（`WARZONE_PHASE_DURATION = 480.0`）。
- BOSS 阶段：8 分钟到点后；`game_time` 冻结。

### 战区刷新
- 攻克 1 个 → 立即开 **2 个**新战区（旧：1 个）。
- 加权抽取：CLEARED 1.5× / LOCKED 1.0× → 已攻克战区有显著概率被重新激活并刷新敌人。
- 删除 `cleared_count >= 3 → boss_unlocked` 触发路径。
- 加 `phase_ended` 守卫：阶段结束后 `_refresh_availability_after_clear` 不再开新战区。

### 8 分钟过渡（即时切换，2026-05-09 二次调整）
- `zone_mission.cancel_all_zone_missions()`：所有战区 TGT 标记清除 / `_spawned_zones` / `_triggered_zones` / `_completed_zones` 全清。敌人**留场**继续战斗，但任务取消、不再发奖励、不再发完成信号。
- 关所有 AVAILABLE / SELECTED 战区为 LOCKED（不留"打完再走"机会）。
- `boss_unlocked = true`，下一帧 `_update_boss_phase` 直接启动事件。
- 提示：`BOSS_ZONE_READY`。
- **撤销**：早期版本里 `_boss_zone_pending` 等结算的路径已删，因为玩家反馈"打完才能进 BOSS"破坏节奏。

### 出界回血时间税
- 点 SUPPLY 满血但 `game_time += 15.0`（clamp 到 `WARZONE_PHASE_DURATION`，避免直接跨过阈值跳过过渡逻辑）。
- BOSS 阶段 SUPPLY 已被早 return 屏蔽，不重复扣时间。

### HUD 倒计时
- `survivor_hud.warzone_timer_label`，顶部最上方常驻，`PROCESS_MODE_ALWAYS`。
- 颜色：≤60s 红 / ≤120s 黄 / 其他常规。
- BOSS 阶段切 `HUD_BOSS_PHASE` 文案。
- 升级面板暂停期间：survivor_mode 在 `is_paused_for_upgrade = true` 那一刻同步刷一次 setter，期间 game_time 不变所以无需持续刷。

## 涉及文件

- [scripts/survivor/zone_data.gd](../../scripts/survivor/zone_data.gd)
- [scripts/survivor/survivor_mode.gd](../../scripts/survivor/survivor_mode.gd)
- [scripts/survivor/survivor_hud.gd](../../scripts/survivor/survivor_hud.gd)
- [i18n/translations.csv](../../i18n/translations.csv) — 4 个新 key（`WARZONE_PHASE_ENDING` / `BOSS_ZONE_READY` / `HUD_WARZONE_TIMER_FMT` / `HUD_BOSS_PHASE`）

## 回滚要点

如需回滚到旧的 3 战区触发：
1. `zone_data.gd._refresh_availability_after_clear` 头部恢复 `if cleared_count >= 3:` 块（参考 git 历史）。
2. `survivor_mode.gd` 删除 `_check_warzone_phase_timeout` / `_is_in_boss_phase` / `_boss_zone_pending` / `WARZONE_PHASE_DURATION` / `SUPPLY_TIME_COST` / `_warzone_phase_ended`。
3. `_physics_process` 移除 `if not _is_in_boss_phase()` 条件，恢复 `game_time += delta`。
4. `_on_supply_confirmed` 移除 `game_time` 推进。
5. HUD `_warzone_timer_label` 与 setter 删除（layout 偏移恢复）。

## 验证

见 [docs/systems/survivor-mode.md](../systems/survivor-mode.md) "阶段制" 章节。手测要点：
- 战区无限刷（5+ 个不触发 BOSS）
- 8 分钟过渡（在打 / 不在打两种状态）
- 时间税（贴边触发 supply → game_time 跳 +15）
- BOSS 阶段 timer 冻结 + HUD 文案切换
- 升级面板打开期间 timer label 保留显示
