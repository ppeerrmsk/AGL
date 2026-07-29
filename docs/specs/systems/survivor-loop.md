---
id: survivor-loop
kind: system
status: done
schema_version: 1
spec_version: 4
owner: design
depends_on: [token-economy, zone-missions, upgrade-pool]
reconstruction_complete: partial
---

# 生存模式核心循环 · 时间制战区（含扩展接入图）

> 生存模式一局的主循环：**10 分钟战区阶段**（靠 Token 预算前方扇形刷怪、打 zone 任务、击杀升级选卡）
> → 时间到 → **BOSS 阶段**（game_time 冻结、停刷、BOSS 决战）。本 spec 兼作**加新功能的接入图**
> （见 §8）：想加敌人/阶段行为/奖励/全局修正/胜负条件时，直接查"想加 X → 改 Y"。

> ⚠ `reconstruction_complete: partial`：headline 常量与主流程已逐一核对源码；**逐敌刷怪概率表**
> 不在此重列（见各敌人 spec + [enemy-index.md](../../reference/enemy-index.md)），避免重复维护两份。

## 1. 设计意图（Why）

- **体验目标**：把"无尽波次"改造成**有终点的 10 分钟攻坚**——前段自由成长 + 打 zone 拿强卡，
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

一局运行态标志：`game_time`（0–600，BOSS 阶段冻结）、`is_game_over`、`is_paused_for_upgrade`、
`_warzone_phase_ended`（600s 跨越一次性闸）、`upgrade_stacks{id→次数}`、稀有度 pity 计数。

## 3. 时间制战区时间线（What —— 全部数值，权威源）

| 阶段 | 时长/区间 | 行为 | 触发 |
|---|---|---|---|
| **战区 WARZONE** | 0 → 600.0 s（10:00） | Token 预算刷怪、接 zone 任务、升级选卡 | 开局即入 |
| **过渡 TRANSITION** | 600.0s 瞬时（一次性） | `cancel_all_zone_missions()` 清 TGT 标记/已完成区；现存敌机留着给 XP 但**无奖励**；所有可选区置 LOCKED；`boss_unlocked=true` | `game_time >= 600` 且 `not _warzone_phase_ended` |
| **BOSS 阶段** | 600s → 胜/负 | game_time 冻结、停刷、**全场撤离**、BOSS 决战 | 过渡后下一帧 `_update_boss_phase()` 起 BossEncounterEvent |

### 3.1 BOSS 阶段闸门与清场（2026-07-28 修订）

**闸门真源**：`survivor_mode.is_boss_phase()` = `boss_unlocked ∪ selected_id==BOSS ∪ BOSS 已 spawn`。
**BOSS 一解锁就为真**——不要求玩家在战术地图上把 BOSS 圈设为 selected。全部子系统（刷怪总管 /
随机奖励事件 / 战区任务 / 第三方事件）一律问这一个入口。

> ⚠ 历史 bug：闸门原先各自读 `ZoneData.is_boss_phase()`（= `selected_id==BOSS`，只有玩家点了
> BOSS 圈才真），于是 BOSS 已解锁、BossEncounterEvent 正在 PRE_STAGE 接近的整段时间里，旅途刷怪 /
> 猎手指派 / 城区直升机事件 **照常运转**。

闸门为真时的行为（**全部即时生效**）：

| 子系统 | 行为 |
|---|---|
| 旅途刷怪 / 猎手指派 / Sentinel 护卫看门狗 / 开局驻防 | 停摆 |
| 城区直升机等随机奖励事件（ADBS）| 不再触发新事件 |
| 常规战区 A/B/C/D 任务 | 停止刷怪 / 触发 / 完成判定 |
| 王牌支援中队 / 宿敌 Orion / AWACS | 各自事件层转撤离（飞出图外静默释放）|
| 出界补给 | 禁用（见 §6）|

**全场撤离**（`survivor_spawner._update_boss_phase_purge`，1 Hz）——舞台只留 BOSS：

- 残余敌机 **画面外** → 立即静默 free（标 `xp_granted`，不算击杀不给 XP）
- 残余敌机 **画面内** → 转撤离：清 AI 目标 + 回 PATROL + 航线改最近出界点 + 开加力，
  **物理飞出去**（铁则：不在玩家画面内瞬消；玩家追打照样还手，不做无敌逃兵）；
  撤离中的机体豁免边界纪律（`boss_evac` meta），飘出画面后由画面外分支释放
- **不动的**：BOSS 本体与 BOSS 自带单位（category 前缀 `boss`）、事件层自管撤离的
  `ace_support` / `ace_nemesis`、停在甲板上的舰载机（`parent_carrier` meta）
- **舰船与地面单位一概保留**：撤离只针对飞机，战区里的船 / SAM / AA 原样留在场上

### 3.2 BOSS 阶段不产 XP（反"决战中继续运营"，2026-07-29）

**设计裁决**：BOSS 阶段是**决战**，不是运营局。玩家不该能靠打 BOSS 的随行小怪继续升级
/ 攒进度 —— 那会让"打不过就绕圈刷怪变强再打"成为最优解，把攻坚战稀释成消耗战。

三条硬规则：

1. **阶段总闸**：从 `is_boss_phase()` 首次为真（即 `boss_unlocked`，包含 PRE_STAGE 演出/接近段）
   开始，任何空中或地面击杀都不再给 XP。击杀计数、击杀回血、侩子手连击、生涯档案仍按
   各自规则处理；这里只封锁经验成长。该闸门不等 `ENGAGED`，因此不存在演出期间刷残敌升级的窗口。
2. **BOSS 自带单位一律不计价**（`no_kill_reward` meta，消费点 `_detect_kills` 唯一一处）：
   无 XP、不入生涯档案（图鉴 + 成就）、不给对头击杀的永久 +max_hp。
   仍算 `kill_count`、仍触发击杀回血 / 侩子手连击 —— 那是玩家用 build 换的**局内**战斗资源。
   名单：Mother Goose 蜂群 UAV、Goose MQ-X 精英对、CSG F/A-18。
   （Wraith 中队 / Poltergeist 是**有限**的 BOSS 本体编成，照常计价——它们就是通关奖励）
3. **任何随 BOSS 补充的单位必须有硬上限**：不许出现"拖时间 = 无限敌机"。
   - Goose 蜂群：同场上限 30（每 12s 补 2）—— 场上封顶，但可无限补，故靠规则 1 归零产出
   - **CSG F/A-18：整场累计上限 8 架**（含开局 2 架，每 120s 补 1）。
     **累计**而非同场：击落不退还名额，弹完机库就空了

配合 §3.1 的闸门（BOSS 解锁即停摆刷怪 / 随机事件 / 战区任务）+ 全场撤离，
BOSS 阶段没有任何击杀 XP 来源；玩家以进入阶段时已经成型的 build 完成决战。

核心常量（已核对 2026-07-26）：
- `WARZONE_PHASE_DURATION = 600.0`（survivor_mode.gd）—— 2026-07-02 由 480.0 上调为 600.0
- `SUPPLY_TIME_COST = 30.0`（出界补给时间税，见 §6）—— 2026-07-28 由 15.0 上调为 30.0
- 超时检查：`if game_time >= WARZONE_PHASE_DURATION and not _warzone_phase_ended` → 置闸 + 取消 zone + 锁区 + `boss_unlocked=true`

⚠ `game_time` 是**可倒拨**的：王牌支援中队全灭 `game_time -= 60`（等于整局 +1 分钟）、
城区直升机 3 架全歼 `-20`（[event-system §3.1](event-system.md)）；出界补给 `+30`。
BOSS 到点因此不是"固定第 10 分钟"，而是"净时间轴跨过 600s"。

HUD：每帧 `hud.set_warzone_remaining(600 - game_time, in_boss_phase)`，倒计时 10:00→0:00，
BOSS 阶段切文字 + 冻结。升级暂停时计时标签仍可见（PROCESS_MODE_ALWAYS）。

## 4. 刷怪总管 & Token 经济

### 4.1 Token 预算（已核对）

```
budget = TOKEN_BUDGET_BASE(8) + int(level × TOKEN_BUDGET_PER_LEVEL(1.8)) + token_bonus
budget = min(budget, TOKEN_BUDGET_MAX(55))
```

样例：Lv1=9 · Lv10=26 · Lv20=44 · Lv27+=55（封顶）。补给一次 `token_bonus += SUPPLY_TOKEN_GAIN(2)`。
（2026-07-06 [60km-density-pass](60km-density-pass.md) 上调：原 5 / 1.5 / 45）

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
| 刷怪间隔 | `TRAVEL_SPAWN_INTERVAL_BASE=32.0`（Lv1）→ `TRAVEL_SPAWN_INTERVAL_MIN=18.0`（高等级），按等级插值（07-06 density-pass：原 45/25） |
| 首次延迟 | `BASE × 0.5 = 16 s`（让首批巡逻先就位） |
| 刷怪距离 | `SPAWN_DISTANCE=3200 px`（玩家前方；须 > 最小 zoom 可视对角半径） |
| 刷怪扇形 | `TRAVEL_SPAWN_FAN_HALF = π×70/180`（沿玩家 heading ±70°，前方扇形，**不刷身后**） |
| 单次数量 | 1–3 架（`_pick_enemy_type` 加权抽取） |

跳过刷怪的 gate：玩家死亡 / BOSS 阶段 / 玩家正在任务中（`_spawn_timer=2.0` 缓一下）/ 预算耗尽。

`_pick_enemy_type` 加权抽取（高层）：按"优先级级联"——高威胁机型先按
`clampf(base + (lvl-解锁)×每级, 0, 上限)` 概率 roll，命中且预算够 + 实例未满则选中返回；
逐级回落到前线机（F-86/A-7/J-7）→ F-4E（Lv1~6 平坦 40%，单机 35%/小队，
spec [enemies/f-4e](../enemies/f-4e.md)）；Lv≤`UAV_RETIRE_LEVEL(4)` 循环 MQ-109/MQ-110
无人机杂鱼（更名见 spec [early-game-uav-rework](early-game-uav-rework.md)）；
Lv≥`LATE_GAME_LEVEL(10)` 强制最低 Token ≥3（禁刷杂鱼）；绝对兜底 MQ-109（永不空转）。

### 4.3 清理与性能（已核对）

| 机制 | 值 |
|---|---|
| 远距清理 | 距玩家 > `FAR_CLEANUP_DISTANCE=7000 px`，每 `FAR_CLEANUP_INTERVAL=4.0 s` 检查，移除并释放 Token；**Adds 豁免**（`skip_far_cleanup`） |
| 实例上限 | `MAX_ENEMIES_DEFAULT=36` / `MAX_ENEMIES_HARD=48` / 动态下限 8（07-06 density-pass：原 30/40） |
| 动态降载 | FPS 采样：avg < TARGET_FPS 降 cap、avg > TARGET_FPS+10 升 cap（+1，封顶 40） |

### 4.4 敌人作战高度分档（2026-07-28 新增）

此前**所有机型共用均匀 1/3 随机档**（LOW/MID/HIGH）——攻击机可能刷在万米高空、
截击机可能贴地爬，机种性格在垂直方向上完全没有表达，空战也失去了"高度层"这一维。

**分档表**：每个登记在册的机型给一组 `[LOW, MID, HIGH]` 权重，刷怪时按权重抽档。
当前登记 **18 型**，按机种性格分四类：

| 类别 | 机型 | 偏好 |
|---|---|---|
| **攻击机** | A-7 · Q-5 | **偏低空**（对地打击性格） |
| **截击机** | MiG-31 · F-104 · J-7 | **偏高空**（高空高速拦截） |
| **电磁炮试验机** | AF-03 | **偏高空**（取射界，见 [af-03 §2.3.1](../enemies/af-03.md)） |
| **多用途机** | MiG-29 · Su-27 · Su-35 · F-4 · MiG-23 · F-86 · F-100 · F-4E | **偏中空**（通用交战高度） |
| **无人机** | MQ-109 低空 · MQ-110 低~中空 · Sentinel / Aegis UAV 中~高空 | 按各自定位 |

**巡逻高度随档位取值**（`TIER_PATROL_ALTITUDE`）：

| 档位 | 巡逻高度区间 |
|---|---|
| LOW | 1500 ~ 3000 m |
| MID | 4500 ~ 6500 m |
| HIGH | 8500 ~ 11000 m |

> 🎯 **档位与巡逻高度必须同步**：AI 的巡逻高度会经态势层换算成**战术层的交战高度**。
> 只抽档位不改巡逻高度，分档就只影响巡逻段——一进交战高度又被拉回原来的中值，
> 分化白做。这是本次改动里唯一容易漏的一环。

**未登记类型维持原行为**：BOSS / Adds / 事件单位的高度由各自 spawn 代码事后覆写，
不进本表 —— 它们仍走均匀随机档 + 巡逻高度 4000~8000 m。

**BOSS 专属机型不进常规刷怪**（同批修复）：F-47 与 F-14 Poltergeist 是 BOSS 专属机型，
此前**后期随机桶**遍历整张 token 成本表取"成本 ≥3"的机型，这两者靠成本 10 混了进来
（与 enemy-index 记载不符）。现按 BOSS 专属名单显式排除。

## 5. 等级 / XP / 升级（已核对核心）

- XP 曲线：`xp_for_level(L) = int(15.0 × pow(L, 1.3))`（⚠ 是 **15**，非 20）。
  - **2026-07-28 指数 1.15 → 1.3（用户裁决，温和档）**：空中击杀 XP 带 `+level×8` 线性缩放，1.15 指数下
    两边近同速增长 → 每级所需击杀数全程恒定 ≈2–3 杀，等级退化成"击杀数 ÷2.5 的计数器"，
    LV21（T5 开门）中局即到、门槛形同虚设。1.3 让每级击杀数随等级爬升
    （未计乘区：LV10≈2.8 杀/级 → LV20≈3.9 → LV25≈4.1），10 分钟战区内平均局收在 **LV18~22**，
    LV26+ 只属于高节奏局——**顶级机不保底**（联动 [evolution-attribute-gates](evolution-attribute-gates.md) §2.2 收入封顶）。
- 击杀 XP：空中单位统一 `base + level×8`（再乘 `xp_mult`/sig/机体乘区）——
  普通机 `XP_PER_KILL=40` · MQ-109/MQ-110 `25` · F-4E `32` · Sentinel `50` · F-47/王牌 tier `100`（4 架共 400）·
  **Tu-160 `80` · AH-64 `50` · CH-47 `40`**；地面 `25 + level×4`。
  - **2026-07-28 Adds 改普通计价（用户裁决）**："单只 = 当前等级全额经验"（`adds_xp_per_kill`，一组升 3–4 级）
    的等级计价设计**废除**——它对 XP 曲线免疫（曲线改多陡都白调），是等级通胀最大源头。
    Adds 改与普通敌机同一公式，整组击杀 ≈ 1~1.5 级，仍是全场最肥经验事件，但不再一波跳 3–4 级。
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
2. **`game_time += SUPPLY_TIME_COST(30.0)`**，clamp 到 `WARZONE_PHASE_DURATION`(600)（防一次跨过阶段闸）
   —— **2026-07-28 由 15.0 上调为 30.0**（10 分钟战区里 15s 太便宜，来回补给几乎无痛）
3. `token_bonus += 2`（补偿）

**BOSS 阶段禁用**（`_is_in_boss_phase()` 提前返回，不回血不推时间）。
设计意图：苟边墙回血要付"把局往 BOSS 推进 30s"的节奏代价（战区总时长的 1/20）。
边界补给按钮文案写明"战区时间 −30 秒"——代价必须在按下去之前就看得到。

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

- [x] game_time 在 BOSS 阶段冻结；600s 一次性过渡（不重复触发）
- [x] BOSS **解锁**（不是"玩家选中 BOSS 圈"）即停摆刷怪 / 猎手 / 随机奖励事件 / 战区任务（§3.1）
- [x] BOSS 阶段全场撤离：画面外敌机静默释放、画面内物理飞出图外；舰船与地面单位保留
- [x] BOSS 阶段不产出（§3.2）：Goose 蜂群 / MQ-X / CSG F/A-18 击杀 0 XP、不入档、不给永久 +max_hp；
      CSG F/A-18 整场累计上限 8 架（无头回归 `--bench=boss_phase`，26 断言）
- [x] Token 预算 = 8 + int(level×1.8) + bonus，封顶 55（60km 密度调优后的值，见 §4.1）
- [x] 刷怪沿玩家前方 ±70° 扇形、距 3200px，不刷身后
- [x] 远距 7000px/4s 清理，Adds 豁免
- [x] xp_for_level = 15×L^1.3（指数 2026-07-28 由 1.15 上调）
- [x] 出界补给：回血 + game_time **+30s**（clamp 600）+ 2 token；BOSS 阶段禁用；按钮文案写明 −30 秒
- [ ] 高度分档：18 型按权重抽档，巡逻高度随档同步（LOW 1500~3000 / MID 4500~6500 / HIGH 8500~11000）；
      未登记类型（BOSS/Adds/事件单位）行为不变；F-47 / F-14 Poltergeist 不出现在常规刷怪
- [x] 战区强卡（evolved）只经 zone 奖励，不进随机池
- [x] 性能：FPS 动态降 cap；Lv5+ sentinel 压测 FPS 掉 < 15

## 10. 实现计划（Task Pipeline）

> 已落地（status: done，见 changelog 2026-05-09-time-gated-warzone-loop）。保留作重建 + 扩展参考。

- [x] 战区阶段（初版 8 分钟，2026-07-02 改 10 分钟）+ 一次性过渡闸 + BOSS 阶段冻结
- [x] Token 预算 + 加权抽取 + 实例上限 + 前方扇形刷怪
- [x] XP 曲线 + 击杀 XP + 三选一升级 + 稀有度 pity
      （⚠ 升级选卡时机后被 [evolution-attribute-gates](evolution-attribute-gates.md) 改为**每 3 级**
      触发三轴卡片，等级升级本身不再弹窗；本 spec 只管循环骨架，选卡规则以那份 spec 为准）
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
| 2026-07-29 | 4 | BOSS 阶段从 `boss_unlocked`（含演出 PRE_STAGE）起统一封锁全部空中/地面击杀 XP；击杀计数、回血与连击保留。CSG F/A-18 整场累计上限 8 架，击落不返还机库名额。 |
| 2026-05-09 | — | 时间制战区循环落地（8 分钟阶段 + 加权抽取 + 出界时间税，见 changelog） |
| 2026-05-30 | 1 | 回填为 system spec + 扩展接入图；核对 headline 常量；修正 xp_for_level=15（非 20）、UAV_RETIRE=4 |
| 2026-07-28 | 3 | **时间税加倍 + 敌人高度分档**：①出界补给时间税 `SUPPLY_TIME_COST` 15.0 → **30.0**（10 分钟战区里 15s 太便宜，来回补给近乎无痛；边界按钮文案同步写明"战区时间 −30 秒"）；②新增 §4.4 **敌人作战高度分档**——18 型按 `[LOW,MID,HIGH]` 权重抽档（攻击机偏低 / 截击机与 AF-03 偏高 / 多用途偏中 / 无人机按定位），巡逻高度随档取值（1500~3000 / 4500~6500 / 8500~11000），**档位与巡逻高度必须同步**否则分化只作用于巡逻段；未登记类型（BOSS/Adds/事件单位）维持均匀随机 + 4000~8000；③同批修 **F-47 / F-14 Poltergeist 漏进常规刷怪**（后期随机桶按 cost≥3 遍历时靠 cost 10 混入，与 enemy-index 记载不符），改按 BOSS 专属名单显式排除 |
| 2026-07-28 | 2 | **等级通胀整治（用户裁决）**：①XP 曲线指数 1.15→1.3（温和档）——每级击杀数随等级爬升，平均局收 LV18~22，顶级机不保底；②Adds 等级计价废除（单只=一级全额 → 普通公式 Tu-160 80 / AH-64 50 / CH-47 40 + level×8）；③联动 evolution-attribute-gates v9 三轴点数收入封顶 8 |
