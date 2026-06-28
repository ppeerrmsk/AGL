---
id: combat-effectiveness-metrics
kind: system
status: draft
schema_version: 1
spec_version: 1
owner: 设计/用户
depends_on: []
reconstruction_complete: false
---

# 战斗效能评估系统（Combat Effectiveness Metrics）

> 把"一次锁定→交战→收场"的过程数值化，量化攻击效率/战斗表现，并且**正确区分**「飞机本身强」与「这个对位难打」——快机打不中慢直升机 ≠ 直升机强。

## 1. 设计意图（Why）

- **体验/工具目标**：给策划一套能回答"这架飞机到底强不强、强在哪、对什么对位拉胯"的数据，用于平衡调参 + AI 战术验证。
- **核心难题（必须解决）**：用**结果**（谁死、谁活久）衡量强弱会被对位几何欺骗。
  - 快速战斗机 vs 近乎静止的直升机：战斗机火力/机动碾压，但因转弯半径 ≈ 交战距离而打不中（见 [[project_turn_physics_test_harness]] / rts-command 慢目标修复）。
  - 若只看"直升机活得久 / 没被打死"，会误判成"直升机强"。其实是战斗机的**对位转化率**低，不是直升机能打。
- **裁决原则（本系统的宪法）**：
  1. **绝不**用"目标是否死亡/存活时长"反推某飞机的强弱。
  2. 飞机强弱只由**它自己的进攻指标**（在多种对位下的转化率×致命度×精度）+ **它自己的防御指标**（生存 + 压低攻击者转化率/精度）决定。
  3. 把每次交战分解成 4 层：**能力（Capability）→ 转化（Conversion/几何）→ 执行（Execution/精度）→ 结果（Outcome）**。对位几何的锅记在"转化"层，不许冒充"能力"。

## 2. 数据定义（What —— 指标目录 + 公式 + 数据源）

**记账单元 = 一次交战（EngagementRecord）**：从 `PURSUIT_ACQUIRE`（攻击者锁上某目标）到收场（目标死 / 自己死 / 主动脱离 / 超时）。一次交战属于「一个攻击者 × 一个目标」。

数据源标注：✅ = 现有 EventLogger 事件已能提供；🟡 = 需新增低频采样（每帧/10Hz envelope 检测）；⚙ = 由 params 静态算。

### 2.1 第 1 层 · 转化/机会（能不能打到 —— 对位几何在这里现形）

| 指标 | 公式 / 定义 | 源 |
|---|---|---|
| `engage_duration` | 收场时刻 − acquire 时刻（秒） | ✅ PURSUIT_ACQUIRE/CLEAR |
| `solution_time` | 目标处于本机**有效武器包络**（在锥 + 在射程 + 锁定就绪）内的累计时长 | 🟡 复用 `is_in_missile_envelope`/gun 锥/lock 判定，10Hz 采样 |
| **`FSR` 火控转化率** | `solution_time / engage_duration` ← **最关键的对位指标** | 派生 |
| `time_to_first_solution` | acquire 到首个有效包络的时间 | 🟡 |
| `shots_initiated`（=用户 1a 总攻击次数） | 机炮 burst 次数 + 导弹发射数 + gun-pass commit 数 | ✅ GUN/MISSILE/PURSUIT_LOCK |
| `churn` 绕圈度 | 交战内 intent 切换次数 + WIDE_TURN/EXTEND 次数（高 = 几何转化挣扎，即"绕圈空转"signature） | ✅ PLAN |

### 2.2 第 2 层 · 执行/精度（打中没打中 —— 用户 1b/1c）

| 指标 | 公式 | 源 |
|---|---|---|
| `shots_total` / `shots_effective` | 发射总数 / 命中数（机炮按发、导弹按枚分别统计） | ✅ GUN(hit)/MISSILE(hit/miss) |
| **`hit_rate`（=用户 1b 有效:无效）** | `shots_effective / shots_total`（分枪/弹两路） | 派生 |
| **`first_pass_hit`（=用户 1c 一发命中）** | 首次发射/首个 gun-pass 是否命中（bool） | ✅ 首个 GUN/MISSILE 结算 |
| `damage_dealt` | 本次交战对目标造成的总伤害 | ✅ DAMAGE |
| `dmg_per_shot` / `dmg_per_solution_sec` | 伤害效率：每发 / 每秒"有解时间" | 派生 |

### 2.3 第 3 层 · 结果（用户 2a）

| 指标 | 公式 | 源 |
|---|---|---|
| `killed` | 目标是否被本机打死（bool） | ✅ KILL |
| **`TTK` 击杀速度（=用户 2a）** | 首个有效解 → 目标死亡的时长 | ✅ |
| **`effective_DPS`** | `target_effective_HP / TTK`（按目标有效 HP 归一，跨血量可比） | 派生 |
| `self_damage_taken` / `self_killed` | 交战内自己掉血 / 是否被反杀 | ✅ DAMAGE/DESTROY |

### 2.4 第 4 层 · 对手行为（用户 2b）

| 指标 | 公式 | 源 |
|---|---|---|
| **`target_evasions`（=用户 2b 规避动作数）** | 交战内目标的规避机动计数：break turn / EVADE_MISSILE 进入 / 热诱弹 / 高 G jink | ✅ AI_STATE/FLARE/PLAN |
| `target_speed_avg` | 目标平均速度（识别"慢目标对位"） | 🟡 |

### 2.5 第 5 层 · 能力差距（用户 2c）—— 静态 CapIndex

`CapIndex`：纯由 params 算的"纸面战力"，与任何交战结果无关（⚙）。加权公式（权重待调）：

```
CapIndex = w_dps  · 武器DPS潜力(机炮dps + 导弹齐射当量/冷却)
         + w_turn · 持续转弯率(effective_max_g, corner_speed → deg/s)
         + w_spd  · max_speed
         + w_hp   · max_hp
         + w_snsr · radar_range + 锁定速度
         + w_def  · 热诱弹/反制/规避模块
```

| 指标 | 公式 |
|---|---|
| **`cap_gap`（=用户 2c 战斗力差距）** | `attacker.CapIndex − target.CapIndex`（或比值） |

## 3. 评估模型（How —— 把指标合成"正确"的强弱判断）

### 3.1 两轴能力画像（关键：让对位几何无处藏身）

不要合成单一"强度分"。每架飞机产出**两个独立维度**，各自跨"对手面板"聚合：

- **进攻评级 Offense** = 跨多种对位的 `FSR × hit_rate × effective_DPS` 的聚合（它**自己**能多有效地把能力变成击杀）。
- **防御/难缠评级 Defense** = `生存率` + `把攻击者的 FSR/hit_rate 压低多少`（它让别人多难打中自己）。

### 3.2 直升机案例（验证模型正确性）

| | 战斗机(打直升机) | 直升机(打战斗机) |
|---|---|---|
| FSR | **低**（绕圈打不准） | 低（追不上） |
| 致命度 effective_DPS | **高**（一旦命中秒杀） | 低 |
| 读法 | 高致命/低转化 = **平台强、此对位几何难** | 低致命/低转化 = **平台弱** |

→ Offense：战斗机高、直升机低。Defense：直升机"靠慢难被快机瞄"得中等，但 Offense 极低 → 正确判为**niche/弱**，而非"强"。**"直升机活得久"被归因到战斗机的低 FSR（对位转化），不计入直升机强度**——铁律②落地。

### 3.3 "正确评估某飞机实力"的方法

单场不可信。跑**对手面板**（round-robin / vs 一组参考机型），每个对位重复 N 次取均值 + 方差：

- 飞机实力 = f(进攻评级 across 面板, 转化率的**鲁棒性**/方差)。对很多对位都能转化的 > 只能打慢目标的。
- 方差大（只在某些对位转化）= 偏科，显式暴露而非被均值掩盖。
- 对位矩阵（A vs B 的 FSR/hit/TTK 热力图）直接告诉你"谁打谁难"。

## 4. 结构与组成（Structure —— 怎么用代码实现）

复用现有 EventLogger 事件流（PURSUIT/GUN/MISSILE/MSL_BLOCK/DAMAGE/KILL/PLAN 已覆盖大部分），只补"有效包络采样"。三个部件：

1. **`EngagementRecord`**（RefCounted，纯数据）：上面所有字段 + acquire/close 时间戳。
2. **`CombatTelemetry`**（新 Autoload 或 survivor 子节点）：
   - 监听 acquire/clear → 开/关 record；shot/hit/kill/damage/evasion 事件 → record++（低频，零感知）。
   - 10Hz `tick`：对**被追踪的攻击者**调既有包络判定（`is_in_missile_envelope` / gun 锥 / lock）累计 `solution_time`。**性能门控**：默认只追踪「玩家小队 + 其目标」或一个 telemetry focus 集；遵守性能守则（≥3 分频、不全场扫描）。
   - 收场把 record 推入本局 list；F9 dump 末尾新增「交战效能表」段（每条交战一行 + 按机型聚合的 Offense/Defense）。
3. **`--bench=duel A B`**（接 [[project_turn_physics_test_harness]] 现有 bench 框架）：脚本化 1v1（可 NvN）重复对决，无头跑，导出对位矩阵 + 每机两轴评级。**这是"正确评估飞机实力"的主力工具**——不靠玩家手感，跑全机型 × 参考面板。

数据出口：①F9 log 末尾表（看实时局）②bench CSV / 矩阵（看平衡）。

## 5. 验收标准（Acceptance）

- [ ] 一次交战能产出完整 EngagementRecord（含 FSR / hit_rate / TTK / evasions / cap_gap）。
- [ ] **直升机案例**：战斗机 vs 直升机 → 报告显示战斗机**高 effective_DPS + 低 FSR**；直升机被评为**低 Offense**（不因"活得久"被判强）。✅ 模型核心验证点。
- [ ] bench duel 能跑全机型 × 参考面板，导出对位矩阵 + 两轴评级。
- [ ] 性能：telemetry 10Hz 采样在 Sentinel + Lv5 下 FPS 掉幅 < 5（默认只追踪玩家小队）。
- [ ] CapIndex 与实测 Offense 大方向一致（纸面强的实战 Offense 不应系统性垫底——除非对位/AI 有 bug，那正是本系统要暴露的）。

## 6. 实现计划（Task Pipeline —— 待用户确认后再开工）

### 阶段 1 — 记录骨架（不碰采样）
- [ ] `EngagementRecord` 数据类 + `CombatTelemetry` 监听 acquire/clear/shot/hit/kill/damage/evasion，纯用现有事件填 1a/1b/1c/2a/2b。
- [ ] F9 dump 末尾出「交战效能表」（先不含 FSR）。

### 阶段 2 — FSR 采样（性能敏感）
- [ ] 10Hz 包络采样（复用既有 envelope/锥/lock 判定）累计 solution_time → FSR / time_to_first_solution / churn。
- [ ] 性能门控（focus 集 + 分频）+ 压测。

### 阶段 3 — CapIndex + 两轴评级
- [ ] `CapIndex` 静态公式（params 驱动，权重 @export 可调）。
- [ ] 按机型聚合 Offense/Defense 两轴 + cap_gap。

### 阶段 4 — bench duel 矩阵
- [ ] `--bench=duel`：脚本化对决 + 重复 N 次 + 对位矩阵/CSV 导出。

## 7. 索引锚点（Where —— 实装后填）

| 关注点 | 文件 |
|---|---|
| 事件源（复用） | `scripts/event_logger.gd`（log_event/tally/format_stats_summary）|
| 包络判定（复用） | `aircraft/aircraft_combat_tracking.gd`（is_in_missile_envelope 等）、`aircraft/aircraft_weapons.gd` |
| 采集器 | `scripts/...`（待定 CombatTelemetry）|
| bench | bench 框架（见 turn_physics harness）|

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-06-15 | 1 | 初稿（draft）：指标目录 4 层 + 两轴评级模型 + 直升机对位案例 + 代码结构 + 实现阶段。待 review。 |
