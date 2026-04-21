# 2026-04-21 战区敌情：按玩家等级刷新 + 中队化 + 曲线平滑

## 背景

在此次改动之前，战区（`ZoneData` / `ZoneMission`）的驻守敌机系统存在四个结构性问题：

1. **敌人池和玩家等级完全脱钩**。`zone_mission.gd` 的 `DEFENDER_POOL` 只看 Token 成本和固定权重，Lv 1 开局的玩家有概率在 3 星战区撞到 MiG-31 / Su-27。
2. **开局战区不见 UAV/UCAV**。这两种杂鱼只存在于环境刷怪（`_update_spawner`），而不在战区池里。Lv 1-2 阶段战区里净是 F-86 / MiG-23 这类带炮带弹的，缺乏"软靶子"让玩家上手。
3. **攻克后其他战区不升级**。玩家从 Lv 1 一路打到 Lv 6，途中开放的新战区每次 roll 会用当前等级预算，但**已经存在、尚未攻克**的老战区驻守沿用最初刷新时的参数。
4. **护卫是散装的**。`_spawn_zone_defenders` 用 while + `_pick_defender` 一架一架逐个抽取，每架独立绕圈飞，不构成 `Squad`。任务文案写"击灭敌方中队"，但实际出来的是 6-10 架混编单机。

## 改动清单

### 1. `survivor_data.gd` — 新增等级加权敌人池 API

新增：

- `ZONE_ENEMY_TABLE`：敌人表，每行包含 `type / unlock / peak / retire / base_weight`。
- `_zone_pool_level_factor(level, unlock, peak, retire)`：钟形权重函数。
  - `level < unlock - 1`：0（完全不出现）
  - `unlock - 1 ≤ level < unlock`：0.3（预告）
  - `unlock ≤ level ≤ peak`：0.6 → 1.0 线性爬升
  - `peak < level < retire` 或无 retire：1.0 → 0.4 衰减
  - `level ≥ retire`：2 级内完全淡出
- `get_zone_enemy_pool(player_level, exclude_sentinel, squad_friendly)`：按等级和钟形权重返回 `[{type, cost, weight}]`。
- `zone_defender_budget(difficulty, player_level)`：预算随等级线性加成（每级 +8%，Lv 10 ≈ ×1.72）。
- `pick_zone_enemy(pool, budget, player_level)`：加权随机抽一个能付得起的。

### 等级 → 敌人曲线

| 等级 | 主力（peak） | 仍高频（1.0） | 衰减但保留 | 淡出中 |
|------|---------|---------|---------|--------|
| 1    | UAV | — | — | — |
| 2    | UCAV | UAV, F-86 | — | — |
| 3    | F-86 | UAV, UCAV, A-7 | — | — |
| 4    | A-7 | UCAV, F-86, MiG-23 | UAV | — |
| 5    | MiG-23 | F-86, A-7, J-7, Q-5 | UAV, UCAV | — |
| 6    | J-7 / Q-5 | A-7, MiG-23, F-100 | F-86, UCAV | UAV |
| 7    | F-100 | MiG-23, J-7, Q-5, MiG-29 | A-7, F-86 | UCAV |
| 8    | MiG-29 | F-100, Su-27 | MiG-23, J-7, Q-5 | F-86, A-7 |
| 9    | — | MiG-29, MiG-31 | Su-27, F-100 | J-7, Q-5, MiG-23 |
| 10   | Su-27 | MiG-29, MiG-31 | F-100 | A-7 完全淡出 |

玩家每级都能感觉到"有新种类登场"或"老敌人密度下降"。

### 2. `zone_mission.gd` — 驻守刷怪改为中队制

`_spawn_zone_defenders` 重写为 **while 循环按中队切分预算**：

1. 每轮 `get_zone_enemy_pool(level)` → `pick_zone_enemy` 抽一种机型。
2. 按 cost 决定中队规模（`_squad_size_for_cost`）：
   - cost ≤ 2 → 4 架（UAV/UCAV）
   - cost ≤ 3 → 3 架（F-86/A-7）
   - cost ≤ 4 → 3 架（MiG/MiG-23/Q-5）
   - cost ≤ 5 → 2 架（J-7/F-100）
   - cost ≥ 6 → 2 架（Su-27/MiG-31，通常也被 `TOKEN_INSTANCE_CAP` 夹到单机）
3. 用 `Squad` 对象组合：长机 + 僚机共享盘旋航点，僚机走 `SQUAD_FOLLOW`。
4. 预算不够整队就缩减，一架都刷不出就停。**Token 允许就满编，不足就少刷**，不硬塞。

`_spawn_air_squadron`（air / squadron 任务）也改走等级加权池，不再硬编码 MIG/F86/MIG23 三选一。

新增辅助：
- `_count_type_in_scene(etype)`：场景中某类型当前存活数，用于 `TOKEN_INSTANCE_CAP` 检查。
- `_player_level()`：从 spawner.survivor_player 拿当前等级；无效时回退 1。

### 3. 攻克一个战区 → 其他战区按新等级刷新

新增 `ZoneMission.refresh_active_zones_for_level(except_id)`：

- 遍历所有 AVAILABLE / SELECTED 但**尚未交战**的战区。
- 撤走旧驻守（`_despawn_garrison`）+ 清 TGT 记录。
- 下一帧 `_ensure_spawned_for_active_zones` 用玩家**当前**等级重刷一批。

`survivor_mode._on_zone_mission_completed` 在 `mark_cleared` 之后调用它，并通过 `_zone_hint.show_temp(tr("ZONE_REFRESHED_AFTER_CLEAR"))` 给玩家提示"其他战区敌情升级"。

**关键约束**：已触发交战（`_triggered_zones` 有记录）的战区**不**被刷新，避免玩家打到一半敌人换型的割裂感。

### 4. 翻译 key

新增 `ZONE_REFRESHED_AFTER_CLEAR`（zh/en/ja）。

### 5. TGT 目标强度也跟玩家等级走（2026-04-21 补强）

**问题**：初版只调了护卫（garrison），TGT 本身仍是"固定机型"。玩家 Lv 7 在 ★★★ 战区撞到 UCAV TGT + F-86/MiG-23 护卫 — 护卫居然比 TGT 还强，违反直觉。

**解法**：TGT 生成改用"虚拟等级" = `玩家等级 + 星级 boost`，保证 TGT ≥ 护卫：

- `SurvivorData.tgt_level_for_zone(difficulty, player_level)`：★+0 / ★★+2 / ★★★+4
- `SurvivorData.air_squadron_count_for_difficulty()`：★3 架 / ★★4 架 / ★★★5 架
- `SurvivorData.ground_tgt_scale(difficulty, player_level)`：SAM/AA 数量 + HP 倍率 + ★★★ 雷达站

**空战中队 TGT**（`_spawn_air_squadron`）：
- Lv 7 ★★★ → virtual Lv 11 → 池子会抽到 MiG-29 / Su-27 / MiG-31
- Lv 3 ★ → virtual Lv 3 → 仍然 F-86 / A-7 级别（早期不会被虚拟拉高）
- 中队规模同步按星级放大（3/4/5 架）

**地面战区 TGT**（`_spawn_ground_garrison`）：
- ★：2 SAM + 2 AA
- ★★：3 SAM + 3 AA（原设定）
- ★★★：5 SAM + 5 AA
- HP 倍率 = `1 + 0.1×(level-1) + 0.2×(diff-1)`（Lv 7 ★★★ → ×2.0，上限 ×3.0）
- 通过 `params.duplicate(true)` + 覆写 `max_hp` 实现，不污染其他战区的 resource
- ~~★★★ 额外放 1 座雷达站~~：移除 — 雷达站数据链/SARH 照射等功能尚未实装，放在地上也起不到作用，变成纯靶子。等雷达站真正有战术价值时再加回

**精英 TGT**（`_spawn_elite_target`）：
- Sentinel 本身走 `commander_scale_for_level` 自动缩放
- 护卫从"硬编码 UAV/UCAV 交替"改为从 `get_zone_enemy_pool(tgt_lvl)` 随机抽 — 高等级玩家会看到 F-86/MiG-23 甚至 MiG-29 当 Sentinel 的僚机，威慑感大幅提升

**日志**：`PreSpawnAir` / `PreSpawnElite` / `PreSpawnGround` 都追加了 `lvl=` / `tgt_lvl=` / `diff=` 字段便于调试数值。

## 设计决策 / 权衡

- **为什么不让 difficulty 也重新 roll？** 玩家对"A 战区 ★★★"有认知，随意翻滚会破坏地图战略规划。只重刷驻守种类，保留难度星级当作"预算倍率"。
- **为什么预算 ×1.08^(level-1)？** 1.08 取中庸：Lv 10 时 ★★★ 战区从 30 → 52 Token，约等于"难度涨 2 档"的感觉；过高会让后期星级失去区分度。
- **为什么中队化后还要 `TOKEN_INSTANCE_CAP`？** cap 是防止精英（Su-27/MiG-31）刷爆屏幕的硬阀，中队规模只是"单次刷出时的上限"。即使连续刷 3 队 Su-27，cap=2 会让从第二队开始自然收窄到 0-1 架。
- **`exclude squad_friendly=true` 排除 MiG-31 是否让高等级太温和？** 不会 —— MiG-31 仍会通过环境刷怪（`_update_spawner`）作为单机猎手出现。战区里单独 1 架 MiG-31 本来就违和。

## 可能的副作用 / 需要观察

- **攻克后的"换防提示"与现有奖励 toast 重叠**：`_zone_hint` 支持 temp + persistent 共存，但 3 条信息在 5 秒内依次弹出可能过密。观察一下再考虑合并。
- **低等级战区反复攻克**：支持"走回头路"（`cleared_count` 累计），攻克 3 次解锁 Boss。重开的战区会按当前等级生成，所以 Lv 8 回头打 A 战区会看到 MiG-29 护卫，预期内。
- **`pick_zone_enemy` 的加权随机**偶尔可能连抽 4 次同型号 → 战区里一水的 F-86。可接受 —— 现实中一个机场确实常常只驻一种机型。

## 回滚路径

若新系统出问题：

1. 回滚 `zone_mission.gd` 到修改前版本，恢复 `DEFENDER_POOL` / `DEFENDER_BUDGET_BY_DIFFICULTY` / `_pick_defender`。
2. 删除 `survivor_data.gd` 新增的 `ZONE_ENEMY_TABLE` 到 `pick_zone_enemy` 一段（常量和函数均静态，删除无副作用）。
3. 移除 `survivor_mode._on_zone_mission_completed` 里的 `refresh_active_zones_for_level` 调用。
4. 移除翻译 key `ZONE_REFRESHED_AFTER_CLEAR`。

原逻辑文件级自包含，回滚不会影响其他系统。

## 相关文件

- `scripts/survivor/survivor_data.gd`：新增 ~100 行常量 + API
- `scripts/survivor/zone_mission.gd`：重写 `_spawn_zone_defenders`、修改 `_spawn_air_squadron`、新增 `refresh_active_zones_for_level`
- `scripts/survivor/survivor_mode.gd`：`_on_zone_mission_completed` 增加 4 行调用
- `i18n/translations.csv`：新增 1 行翻译 key
