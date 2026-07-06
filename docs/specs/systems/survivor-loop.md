---
id: survivor-loop
kind: system
status: done
schema_version: 1
spec_version: 1
owner: design
depends_on: [token-economy, zone-missions, upgrade-pool]
reconstruction_complete: partial
---

# 生存模式核心循环 · 时间制战区（含扩展接入图）

> 生存模式一局的主循环：**8 分钟战区阶段**（靠 Token 预算前方扇形刷怪、打 zone 任务、击杀升级选卡）
> → 时间到 → **BOSS 阶段**（game_time 冻结、停刷、BOSS 决战）。本 spec 兼作**加新功能的接入图**
> （见 §8）：想加敌人/阶段行为/奖励/全局修正/胜负条件时，直接查"想加 X → 改 Y"。

> ⚠ `reconstruction_complete: partial`：headline 常量与主流程已逐一核对源码；**逐敌刷怪概率表**
> 不在此重列（见各敌人 spec + [enemy-index.md](../../reference/enemy-index.md)），避免重复维护两份。

## 1. 设计意图（Why）

- **体验目标**：把"无尽波次"改造成**有终点的 8 分钟攻坚**——前段自由成长 + 打 zone 拿强卡，
  到点收束进 BOSS 决战。给玩家清晰的"局节奏"和目标感，而非无限熬。
- **Litmus 自检**（docs/DESIGN_PHILOSOPHY.md）：
  - 难度靠 **Token 预算 + 加权抽取**平滑爬升（非数值海绵）→ 过"难度可读"。
  - 出界回血带**时间税**（推进 game_time）→ 苟边墙要付节奏代价 → 过"安全玩法有成本"。
- **反模式规避**：Adds 杂兵不占 Token、不被远距清理，避免污染预算曲线；后期（Lv10+）禁刷
  UAV 杂鱼，保证强度持续上行而非被杂鱼稀释。

## 2. 主循环结构（每帧）

`survivor_mode.gd:_physics_process(delta)` 主要子系统更新顺序（高层）：

1. game_over / 升级暂停 → 提前返回
2. **时间线**：`game_time += delta`（**BOSS 阶段冻结**，不再累加）
3. 单位表 + 雷达锁定累积（O(N²) 分帧 strided）
4. 性能：FPS 采样 + 离屏单位 LOD 冻结/解冻
5. 友军编队 LOD 重 tick
6. 玩家死亡检查 → game_over
7. **刷怪总管** `spawner.update(delta)`（循环心脏，见 §4）
8. **战区阶段超时检查** `_check_warzone_phase_timeout()`（见 §3）
9. **BOSS 阶段** `_update_boss_phase()`
10. 残骸/过期清理
11. bench 模式计时（压测用）
12. HUD 同步（战区倒计时 + 击杀数）

一局运行态标志：`game_time`（0–480，BOSS 阶段冻结）、`is_game_over`、`is_paused_for_upgrade`、
`_warzone_phase_ended`（480s 跨越一次性闸）、`upgrade_stacks{id→次数}`、稀有度 pity 计数。

## 3. 时间制战区时间线（What —— 全部数值，权威源）

| 阶段 | 时长/区间 | 行为 | 触发 |
|---|---|---|---|
| **战区 WARZONE** | 0 → 480.0 s（8:00） | Token 预算刷怪、接 zone 任务、升级选卡 | 开局即入 |
| **过渡 TRANSITION** | 480.0s 瞬时（一次性） | `cancel_all_zone_missions()` 清 TGT 标记/已完成区；现存敌机留着给 XP 但**无奖励**；所有可选区置 LOCKED；`boss_unlocked=true` | `game_time >= 480` 且 `not _warzone_phase_ended` |
| **BOSS 阶段** | 480s → 胜/负 | game_time 冻结、停刷、BOSS 决战 | 过渡后下一帧 `_update_boss_phase()` 起 BossEncounterEvent |

核心常量（已核对）：
- `WARZONE_PHASE_DURATION = 480.0`（survivor_mode.gd）
- `SUPPLY_TIME_COST = 15.0`（出界补给时间税，见 §6）
- 超时检查：`if game_time >= WARZONE_PHASE_DURATION and not _warzone_phase_ended` → 置闸 + 取消 zone + 锁区 + `boss_unlocked=true`

HUD：每帧 `hud.set_warzone_remaining(480 - game_time, in_boss_phase)`，倒计时 8:00→0:00，
BOSS 阶段切文字 + 冻结。升级暂停时计时标签仍可见（PROCESS_MODE_ALWAYS）。

## 4. 刷怪总管 & Token 经济

### 4.1 Token 预算（已核对）

```
budget = TOKEN_BUDGET_BASE(5) + int(level × TOKEN_BUDGET_PER_LEVEL(1.5)) + token_bonus
budget = min(budget, TOKEN_BUDGET_MAX(45))
```

样例：Lv1=5 · Lv10=20 · Lv20=35 · Lv27+=45（封顶）。补给一次 `token_bonus += SUPPLY_TOKEN_GAIN(2)`。

每个敌人的 `TOKEN_COST` / `TOKEN_INSTANCE_CAP` / 解锁等级 / 加权概率**不在此重列**——
见 [enemy-index.md](../../reference/enemy-index.md) 大表 + 各敌人 spec（如 [af-03](../enemies/af-03.md)）。
Adds（Tu-160/AH-64/CH-47/FA-18）`TOKEN_COST=0`，不占预算。

### 4.2 刷怪节奏与位置（已核对）

> ⚠ **位置机制已被取代（2026-07-05）**：本节"刷怪距离 3200 / 前方 ±70° 扇形"的**位置**部分
> 由 [reinforcement-ingress](reinforcement-ingress.md) 取代——增援改从地图边缘成建制入场、
> 飞向中央锚点驻空、token 饿着时物理飞离；远距清理对增援停用（改 EGRESS）。
> **节奏**（间隔 45→25s / 单次数量 / gate）仍以本节为准。下表位置两行仅作历史记录。

| 项 | 值 |
|---|---|
| 刷怪间隔 | `TRAVEL_SPAWN_INTERVAL_BASE=45.0`（Lv1）→ `TRAVEL_SPAWN_INTERVAL_MIN=25.0`（高等级），按等级插值 |
| 首次延迟 | `BASE × 0.5 = 22.5 s`（让首批巡逻先就位） |
| 刷怪距离 | `SPAWN_DISTANCE=3200 px`（玩家前方；须 > 最小 zoom 可视对角半径） |
| 刷怪扇形 | `TRAVEL_SPAWN_FAN_HALF = π×70/180`（沿玩家 heading ±70°，前方扇形，**不刷身后**） |
| 单次数量 | 1–3 架（`_pick_enemy_type` 加权抽取） |

跳过刷怪的 gate：玩家死亡 / BOSS 阶段 / 玩家正在任务中（`_spawn_timer=2.0` 缓一下）/ 预算耗尽。

`_pick_enemy_type` 加权抽取（高层）：按"优先级级联"——高威胁机型先按
`clampf(base + (lvl-解锁)×每级, 0, 上限)` 概率 roll，命中且预算够 + 实例未满则选中返回；
逐级回落到前线机（F-86/A-7/J-7）；Lv≤`UAV_RETIRE_LEVEL(4)` 循环 UAV/UCAV 杂鱼；
Lv≥`LATE_GAME_LEVEL(10)` 强制最低 Token ≥3（禁刷杂鱼）；绝对兜底 UAV（永不空转）。

### 4.3 清理与性能（已核对）

| 机制 | 值 |
|---|---|
| 远距清理 | 距玩家 > `FAR_CLEANUP_DISTANCE=7000 px`，每 `FAR_CLEANUP_INTERVAL=4.0 s` 检查，移除并释放 Token；**Adds 豁免**（`skip_far_cleanup`） |
| 实例上限 | `MAX_ENEMIES_DEFAULT=30` / `MAX_ENEMIES_HARD=40` / 动态下限 8 |
| 动态降载 | FPS 采样：avg < TARGET_FPS 降 cap、avg > TARGET_FPS+10 升 cap（+1，封顶 40） |

## 5. 等级 / XP / 升级（已核对核心）

- XP 曲线：`xp_for_level(L) = int(15.0 × pow(L, 1.15))`（⚠ 是 **15**，非 20）。
- 击杀 XP：普通机 `XP_PER_KILL=40` · UAV `25` · Sentinel `50` · F-47 `100`（4 架共 400）· 地面 `25 + level×4`。
  Adds（Tu-160/AH-64/CH-47）：单只 = 当前等级所需全额（一组可升 3–4 级，`ADDS_XP_DIVISOR=1`）。
- `xp_mult` 升级：每层 +20%，封顶 ×1.4。
- 升级流程：击杀 add_xp → 逐帧把 `_pending_xp` 灌进可见 xp 条 → 满则暂停弹 UI → 三选一 →
  `apply_upgrade()` 写入 → `upgrade_stacks[id]++`。
- 稀有度 + pity：STABLE/ADVANCED/EXPERIMENTAL/CLASSIFIED/NEXT_GEN，高稀有度有 pity 保底
  （具体权重/保底数见 survivor-skills.md，不在此重列）。

### 5.1 敌人随等级缩放

- HP 乘子：`1 + (level-1) × mult`，MiG 类 mult=0.15（已核对，见 af-03 spec）；
  其余 archetype 的 mult（UAV/Sentinel 等）见 survivor_data 缩放段（⚠ 未逐一核对）。
- 机炮伤害乘子：同型公式（mult≈0.08）。导弹数：`初始 + floor((level-1)/4)`。

## 6. 出界回血时间税（Supply，已核对）

玩家在地图边界按补给：
1. 回满 HP
2. **`game_time += SUPPLY_TIME_COST(15.0)`**，clamp 到 480（防一次跨过阶段闸）
3. `token_bonus += 2`（补偿）

**BOSS 阶段禁用**（`_is_in_boss_phase()` 提前返回，不回血不推时间）。
设计意图：苟边墙回血要付"把局往 BOSS 推进 15s"的节奏代价。

## 7. 奖励 / 战区强卡池

- zone 任务完成 → 发**战区专属强卡**：`UPGRADES` 中标 `evolved: true` 的进化技能，
  **只**经战区奖励发放，**不**进随机升级池（`is_upgrade_available_for` 对 evolved 过滤）。
- 抽取按稀有度加权 + `max_stacks` / `exclusive_to` / `requires` 过滤。
- 具体进化技能清单见 survivor-skills.md（⚠ 不在此重列，避免双份维护）。

## 8. 扩展接入图（Extension Seams）★ 本 spec 重点

> 想加新功能时查这张表。"想加 X → 改 Y"。已有专属 spec 的链到对应 spec。

| 想加 | 改哪里（接入点） | 备注 / 参考 |
|---|---|---|
| **普通敌机** | `EnemyType` enum + `TOKEN_COST`/`TOKEN_INSTANCE_CAP` + 解锁等级常量 + `_pick_enemy_type` 分支 + `_create_enemy` case + 资源 preload + `ENEMY_TIER_OFFSET` | 走 [playbook §1](../../reference/playbook.md) + [enemy-index 12 步](../../reference/enemy-index.md)；样板 [af-03](../enemies/af-03.md) |
| **Adds 族群波** | `EnemyType` + flock 尺寸/间距常量 + 独立 spawn 事件（`_spawn_xxx_flock`）+ 资源 preload | 不占 Token、远距豁免；仿 Tu-160/AH-64 |
| **改阶段时长/结构** | `WARZONE_PHASE_DURATION` + `_check_warzone_phase_timeout()` | 多阶段需扩 zone_data 状态机；记得同步 HUD 计时 |
| **新全局修正**（昼夜难度等） | `_get_token_budget()` 乘子 / `_create_enemy` 缩放 / 存 `mode.global_difficulty_mult` | 单点注入，避免散落 |
| **新升级技能** | `UPGRADES` 加条目 + `apply_upgrade()` 匹配 `stat` + i18n 三语 + （触发型）`SkillHooks` 钩子 | 走 [playbook §4](../../reference/playbook.md)；机动 buff 必经 effective_*() accessor（SEAM-001）；样板 [bloodlust](../skills/bloodlust.md) |
| **新副武器** | `qmaam` 同款：MissileParams + `target_priority` 分支 + 槽位接入 | 样板 [qmaam](../weapons/qmaam.md) |
| **新战区奖励** | `UPGRADES` 加 `evolved:true` + zone 奖励池权重 | 不进随机池 |
| **新胜利条件**（如清 N 区获胜） | survivor_mode 加计数器 + `_update_boss_phase()` 检查 + `_on_victory()` | 可替代纯时间触发 BOSS |
| **新失败条件** | `_physics_process` 检查 + `_on_player_died()` | 玩家死亡已实现 |
| **阶段切换 VFX/音效** | 在 `_check_warzone_phase_timeout()` 内 zone 取消前触发缓存的 CanvasLayer/AudioStreamPlayer | — |
| **动态刷怪率**（按玩家血量等） | `_update_spawner` 里 `_spawn_timer` 斜率 | 当前仅按等级 |
| **新状态/Debuff** | 走 [playbook §9 加状态效果](../../reference/playbook.md) + status_effects.gd | 物理影响经 effective_*() accessor |
| **BOSS** | `boss_registry` 注册 + encounter 类 + spawn 接入 | 样板 [mother-goose](../bosses/mother-goose.md) |

## 9. 验收标准（Acceptance / Litmus）

- [x] game_time 在 BOSS 阶段冻结；480s 一次性过渡（不重复触发）
- [x] Token 预算 = 5 + int(level×1.5) + bonus，封顶 45
- [x] 刷怪沿玩家前方 ±70° 扇形、距 3200px，不刷身后
- [x] 远距 7000px/4s 清理，Adds 豁免
- [x] xp_for_level = 15×L^1.15（非 20）
- [x] 出界补给：回血 + game_time +15s（clamp 480）+ 2 token；BOSS 阶段禁用
- [x] 战区强卡（evolved）只经 zone 奖励，不进随机池
- [x] 性能：FPS 动态降 cap；Lv5+ sentinel 压测 FPS 掉 < 15

## 10. 实现计划（Task Pipeline）

> 已落地（status: done，见 changelog 2026-05-09-time-gated-warzone-loop）。保留作重建 + 扩展参考。

- [x] 8 分钟战区阶段 + 一次性过渡闸 + BOSS 阶段冻结
- [x] Token 预算 + 加权抽取 + 实例上限 + 前方扇形刷怪
- [x] XP 曲线 + 击杀 XP + 三选一升级 + 稀有度 pity
- [x] 出界回血时间税 + 补给 token 补偿
- [x] 远距清理 + 动态 FPS 降载
- [x] 战区强卡（evolved）池
- [ ] （扩展位）多阶段战区状态机 / 非时间胜利条件 —— 见 §8

## 11. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 主循环 / 阶段 / 时间税 / HUD 同步 | `scripts/survivor/survivor_mode.gd` |
| 刷怪总管 / Token / 加权抽取 / 清理 / FPS 降载 | `scripts/survivor/survivor_spawner.gd` |
| 常量（预算/间隔/距离/清理/XP/解锁） | `scripts/survivor/survivor_data.gd` |
| XP / 升级 apply | `scripts/survivor/survivor_player.gd` |
| zone 任务 / BOSS 解锁 / 阶段判定 | `scripts/survivor/zone_data.gd` · `zone_mission*.gd` |
| 升级池 / 进化技能 | `scripts/survivor/survivor_data.gd`（UPGRADES）+ survivor-skills.md |
| reference 索引 | survivor-mode.md · survivor-skills.md · enemy-index.md |

## 12. 已知不确定 / 待补

- 逐 archetype 缩放 mult（UAV/Sentinel 的 HP/dmg 系数）未逐一核对——用前请验源码。
- 进化技能具体清单、稀有度权重/pity 数值以 survivor-skills.md 为准。
- 多阶段战区状态机尚未实现（当前仅"战区→BOSS"两段）。

## 13. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-09 | — | 时间制战区循环落地（8 分钟阶段 + 加权抽取 + 出界时间税，见 changelog） |
| 2026-05-30 | 1 | 回填为 system spec + 扩展接入图；核对 headline 常量；修正 xp_for_level=15（非 20）、UAV_RETIRE=4 |
