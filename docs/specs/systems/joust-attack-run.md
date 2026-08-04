---
id: joust-attack-run
kind: system
status: done
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [weapon-employment-doctrine]
reconstruction_complete: true
---

# 攻击跑行为原语（Joust Attack Run）

> status: **done（2026-07-05 用户 playtest 手感确认）** · spec_version: 3 · 日期：2026-07-05
> 上游：weapon-employment-doctrine（§2 统一瞄准语义）；触发 bug：MG 电磁炮 UAV 全场 0 充能死锁（log 183044）。
> 关联：bosses/mother-goose（MQ-110/112 蜂群 SHOOTER）、enemy-index Lancer 原型（J-7 / F-104 / F-100 / MiG-31）。

## 1. 设计意图（Why）

**病灶 A（MG standoff SHOOTER 死锁，log 183044 实证）**：
MQ-112 的开火链要求"机头稳定对准 5 秒+"（雷达锥 ±25° × lock 2s → 开火锥 ±8° → 充能 2.5s
→ 锁定相位 0.6s），且射程 = 自身雷达 5000m。而 ai_controller 的 standoff 切向轨道在
`1.5 × standoff(2000px) = 3000px = 6000m` 就把机头甩向切线——**开火包络(1500~5000m)整个
躺在"已经侧身绕圈"的区域里**。结果：接近段锁上了（LOCKED@7661m）→ 6000m 甩头 → 锁清零
反复（locking=0.9/2.0s）→ 全场 0 充能。SwarmDirector 注释的设计意图（"SHOOTER = 机头稳
对玩家累 lock"）与移动层实现直接矛盾。

**病灶 B（Lancer 骑士型 = 定时器伪装的打带跑）**：
J-7 / MiG-31 等骑士型靠 `engage_duration 5~9s + engage_cooldown 6~8s` 硬切模拟"一击脱离"，
突击段姿态不保证对准（BFM 战术树可能选出转圈），脱离-再入没有几何承诺，读感是"路过"而非"冲锋"。

**North star**：**攻击跑（joust）成为可复用行为原语**——对准进入(RUN_IN) → 火力窗 →
脱离拉开(BREAK) → 折返再攻，循环往复。武器门（雷达锥/开火锥/锁定时长/充能）在 RUN_IN 段
**天然满足**，无需武器各自求人。骑士读法：玩家看到敌机摆好架势冲一轮、脱离、再折返——
可预判、可对头反打（骑士精神技能系列的天然舞台）。

## 2. 数据定义（What —— 权威源）

### 2.1 状态机

```
RUN_IN（对准进入）──dist≤inner / 超时 / 闭合放弃──▶ BREAK（脱离拉开）
   ▲                                                    │
   └────────────── dist≥reentry / BREAK 超时 ─────────────┘
```

| 相位 | movement 契约 | 速度 |
|---|---|---|
| RUN_IN | `target_position` = 目标 lead 前置点（lead_time = dist/闭合 × 0.6，上限 3s） | **两段速**：火力窗外 = effective_max 全速闭合（bench 实证：cruise 追不上 900km/h 横穿目标，永远吊在带外）；入带后 = `joust_run_speed_kmh`（0=自动 effective_cruise，稳定锁定/充能平台） |
| BREAK | `target_position` = 自机沿"远离目标"方向 1500px 外推点（每 tick 刷新）；近图边时朝地图中心 lerp（复用 FEAR 边界守卫公式） | `joust_break_speed_kmh`（0=自动取 effective_max） |

高度：不由 joust 主张（沿用宿主既有高度逻辑——hunter 跟目标 tier / BFM 跟战术）。
`orbit_speed_cap` 在接管时清零（防旧 standoff 轨道残留限速）。

### 2.2 转换条件（全部权威数值）

| 转换 | 条件 |
|---|---|
| RUN_IN → BREAK | `dist ≤ inner`，或 `run_timer > joust_run_max_s(15s)`（**只计火力窗内时间**——远程转场不烧预算，否则从 reentry 飞回来的路上就把 15s 用光、刚进带就被切走，bench 实测踩过），或闭合放弃（见下）。**充能保持窗期间禁止**：电磁炮 charging/awaiting_fire 时不许切 BREAK（承诺弹道优先，甩头=白费充能） |
| 闭合放弃（骑士语义"闭合不够就脱离"） | `joust_giveup_closing_mps > 0` 时启用：RUN_IN 中且 `dist > outer` 且闭合率 < 阈值持续 **2.0s** → BREAK |
| BREAK → RUN_IN | `dist ≥ reentry`，或 `break_timer > 12s`（目标追着我跑拉不开时强制折返面对） |

### 2.3 包络动态解析（SEAM-001 / weapon-doctrine 定稿原则 2：距离带禁止烘焙）

每次相位判定实时读装备 live params：

| 主武器 | outer（火力窗外缘） | inner（脱离内缘） |
|---|---|---|
| 电磁炮 | `_effective_max_range_m × PPM`（= 本机雷达） | `min_engage_range_m × PPM` |
| 导弹 | `missile.max_range × PPM` | `missile.min_range × PPM` |
| 机炮 | `gun.max_range × PPM` | 200px 地板（穿越扫射，防撞近距） |
| 无武器兜底 | 2000px | 200px |

`reentry` 默认 = `outer × 1.3`（可用 `joust_reentry_range_px` 覆写）；
`inner` 可用 `joust_break_range_px` 抬高（取两者较大值）。

### 2.4 AIController 参数（@export，spawner/swarm 接线时设置）

| 参数 | 默认 | 说明 |
|---|---|---|
| `joust_enabled` | false | 总开关 |
| `joust_break_range_px` | 0 | 0=自动（包络 inner） |
| `joust_reentry_range_px` | 0 | 0=自动（outer × 1.3） |
| `joust_run_speed_kmh` | 0 | 0=自动（cruise；充能/锁定平台要稳） |
| `joust_break_speed_kmh` | 0 | 0=自动（max；脱离要快） |
| `joust_giveup_closing_mps` | 0 | 0=关闭；>0 = 骑士"闭合不够就放弃"阈值 |
| `joust_run_max_s` | 15 | RUN_IN 安全超时 |

### 2.5 接线表（本次实装）

| 机型 | 接线点 | 参数 | 备注 |
|---|---|---|---|
| MQ-112（MG 电磁炮 UAV） | mother_goose_uav_swarm | enabled + standoff 置 0（退役切向轨道） | 包络自动=750~2500px；run=cruise 750kmh，从 2500px 闭合到 750px 有 >10s 对准窗 ≫ 充能链 5.1s |
| MQ-110（MG 导弹 UAV） | 同上 | 同上 | 包络自动=导弹 min/max；RUN_IN 段 35° 锁定锥轻松满足 |
| J-7（INTERCEPTOR） | survivor_spawner | enabled + giveup=60mps；engage_duration 5→30（joust 自循环取代定时器伪打带跑） | 机炮穿越扫射；engage_cooldown 保留 |
| MiG-31 | survivor_spawner | enabled + giveup=40mps；engage_duration 9→45 | 雷达弹 RUN_IN 远距齐射 + 折返 |
| F-104 / F-100 | survivor_spawner（若有独立 AI 配置块） | 同 J-7 | Lancer 全家统一 |

**明确不接**：AF-03（planner LINE_UP 已是电磁炮纪律的上位实现）、Gladiator/Schemer 原型、
玩家方僚机（RTS 命令语义优先）。

## 3. 行为细节（How）

- **武器链零改动**：joust 只写 movement 契约字段。机炮锥门 / 导弹锁定 / 电磁炮充能
  全部由既有系统在"机头恰好对准"的姿态下自然满足。
- **与电磁炮稳头守卫的配合**：充能/锁定相位时 ai_controller 的"Railgun 充能稳头守卫"
  优先级更高（钉 locked_aim_pos），joust 让位；充能结束回 joust 循环。
- **与防御行为的关系**：BFM 路径上 Herbst 反咬 / 导弹规避 / 机炮防御的 return 都在
  joust 钩子之前——防御永远压过攻击跑。simple 路径同理（EVADE 状态在状态机层先行）。
- **闭合放弃后**不进入冷却惩罚：BREAK 拉开到 reentry 自然折返，形成"追不上就换角度再来"。

## 4. 阶段（Milestones）

1. JoustController 原语 + AIController 参数/状态字段
2. 双路径钩子（simple hunter 块 + _process_engage BFM 块）
3. MG MQ-110/112 接线（退役切向轨道）
4. Lancer 四型接线
5. bench `--bench=joust` + 回归门全绿

## 5. 验收（Acceptance）

- [x] bench A（MQ-112 死锁修复）：joust UAV（电磁炮包络）vs 250m/s 横穿目标，90s 内
  锁定稳定窗（±25° 雷达锥 × dist∈[inner,outer]）实测 **16.1s** ≥ 充能链 5.1s；
  完整循环 1 个；**真实 RailgunEquipment 步进实弹 2 发**（对照 log 183044 = 0）。
  （验收口径修正 v2：原写"±8° 连续窗 ≥5.1s"是误分析——±8° 开火锥只在充能启动一瞬
  需要，uav_railgun `charge_persistent=true` 充能期不查锥；连续性要求落在 ±25° 锁定稳定上）
- [x] bench B（骑士节奏）：机炮包络 joust vs 横穿目标，60s **13 个**完整循环，
  最长机炮窗（≤10°、gun 包络内）**1.82s**（口径修正 v2：600px 机炮带 × ~500px/s
  穿越闭合的物理窗本就在 0.8~2s 量级，门槛定 ≥0.6s）
- [x] bench C（闭合放弃）：目标 2.5× 速度逃逸，give-up 于 t=2.0s 转 BREAK，不死追
- [x] 回归门 --bench=all 16 项全绿
- [x] playtest：MG 战 MQ-112 出现充能 telegraph + 实弹（对照 log 183044 的 0 次）；
  Lancer 突击读感"冲锋-脱离-折返"（2026-07-05 用户手感确认）

## 6. 实现计划（§4 各阶段 → 文件）

- [x] `scripts/ai/joust_controller.gd`（新，静态类）
- [x] `scripts/ai_controller.gd`：@export 参数 ×7 + 状态字段 ×3 + simple 钩子 + engage 钩子
- [x] `scripts/survivor/mother_goose_uav_swarm.gd`：MQ-110/112 接线
- [x] `scripts/survivor/survivor_spawner.gd`：Lancer 接线（J-7 / MiG-31 / F-100 / F-104）
- [x] `scripts/tests/test_joust.gd` + bench_runner 注册
- [x] 索引同步（script-index / _INDEX）

## 7. 索引锚点（Where）

| 职责 | 文件 · 符号 |
|---|---|
| 原语本体（状态机 + 包络解析 + 边界守卫） | `scripts/ai/joust_controller.gd` · `update` / `_resolve_outer_px` / `_resolve_inner_px` / `_closing_mps` |
| 参数 + 状态字段 | `scripts/ai_controller.gd` · `joust_*` @export 组 / `_joust_phase` 等 |
| simple 路径钩子（MG hunter） | `scripts/ai_controller.gd` · simple combat 的 `_joust_handled` 分支（standoff 切向轨道之前） |
| BFM 路径钩子（Lancer） | `scripts/ai_controller.gd` · `_process_engage` 态势评估之前的 joust 分支 |
| MG 接线 | `scripts/survivor/mother_goose_uav_swarm.gd` · hunter 分支 variant match |
| Lancer 接线 | `scripts/survivor/survivor_spawner.gd` · INTERCEPTOR / MIG31 / F100 / F104 配置块 |
| 验收 bench | `scripts/tests/test_joust.gd`（--bench=joust，7 断言 + 真实电磁炮步进） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-05 | 3 | 用户 playtest 手感确认 → **done**。 |
| 2026-07-05 | 2 | 全量落地 + bench 7/7。实现中两处设计修正：①RUN_IN 超时只计火力窗内时间（转场不烧预算）；②RUN_IN 两段速（带外全速闭合/入带稳巡航——cruise 追不上横穿目标）。验收口径修正：连续窗要求落在 ±25° 锁定稳定（±8° 开火锥只需启动一瞬）；机炮窗门槛 0.6s（物理窗 0.8~2s 量级）。剩 playtest。 |
| 2026-07-05 | 1 | 初稿 + 用户拍板方向（对话确认："joust 听上去不错……一并修改实装"）。 |
| 2026-07-12 | 4 | **慢速空中目标统一路由 joust**（log 181952 实证：4×F-14 围 CH-47 在 extend/wide-turn 循环空转 53s 零命中，最后靠偶然窗口机炮收）：`AIController._slow_air_joust`——空中目标速度 ≤ 100 m/s（直升机档，UAV 233m/s/轰炸机/喷气机不受影响）即路由 joust pass（BFM/simple 双钩子，与 command-wheel 姿态路由同机制）；RUN_IN 对准承诺取代绕圈，"直升机 = 会飞的面目标"。验收 --bench=fire_discipline §B。 |
