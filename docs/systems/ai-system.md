# AI 系统参考

## 概述

`AIController`（`scripts/ai_controller.gd`）作为子节点附加到 Aircraft 上，通过状态机控制飞机行为。
主体已拆成子模块：战术执行 `ai/bfm_tactics.gd`、导弹规避 `ai/missile_evasion.gd`、
目标选择 `ai/target_selection.gd`、编队协同 `ai/squad_coordination.gd`、战术层 `ai/tactical/`。

> ⚠ 本文是**架构叙述**。具体数值 / 触发阈值以 [docs/specs/](../specs/_INDEX.md) 为准
> （尤其 [global-awareness-roe](../specs/systems/global-awareness-roe.md) ·
> [target-engageability-selection](../specs/systems/target-engageability-selection.md) ·
> [engagement-discipline](../specs/systems/engagement-discipline.md)）。

---

## 状态机

```gdscript
enum AIState { PATROL, ENGAGE, SQUAD_FOLLOW }
```

| 状态 | 说明 |
|------|------|
| PATROL | 按航路点巡逻，定期扫描敌机 |
| ENGAGE | 交战中，运行 BFM 战术决策树 |
| SQUAD_FOLLOW | 编队跟随长机，掩护扫描 |

⚠ **导弹规避不是状态**，是叠加在任意状态之上的一个标志位 `_evading`
（`is_evading()` 查询，`MissileEvasion.enter_evade/exit_evade/process_evade` 驱动）。
早期版本曾有 `AIState.EVADE_MISSILE` 枚举值，**已删除**——规避结束后不需要"回到哪个状态"的记账。

---

## 飞行员属性 (@export)

### 基础巡逻

| 属性 | 类型 | 说明 |
|------|------|------|
| `aircraft` | Aircraft | 控制的飞机 |
| `waypoints` | PackedVector2Array | 巡逻航路点 |
| `patrol_altitude` | float | 巡逻高度 |
| `arrival_distance` | float | 到达判定半径 |

⚠ `patrol_altitude` **不只管巡逻段**：它经 `Situation.combat_altitude_m` 一路传到战术层，
决定这架 AI 的交战高度。所以生存模式给敌人抽高度档时必须**连 `patrol_altitude` 一起跟着档位改**，
只改档位不改它 → 分化只在巡逻时看得见，一交战全都回到同一层。

高度档现按机型分化（2026-07-28 起，此前是所有机型均匀 1/3 随机 LOW/MID/HIGH）：
攻击机（A-7 / Q-5）偏低空、截击机（MiG-31 / F-104 / J-7）与 AF-03 偏高空（取射界）、
多用途机偏中空，无人机偏低 / 中空。未登记的类型（BOSS / Adds / 事件单位，高度由各自 spawn
代码事后覆写）维持均匀随机 + 原来的巡逻高度区间。权重表与档位高度区间在 `SurvivorData`。

### 战斗 AI

| 属性 | 默认 | 说明 |
|------|------|------|
| `enable_combat` | false | 启用战斗 AI |
| `aggression` | 0.5 | 攻击倾向 (0=被动, 1=激进) |
| `engage_cooldown` | 15.0s | 两次交战间隔 |
| `engage_duration` | 20.0s | 单次交战最长时间 |
| `evade_missiles` | false | 是否规避来袭导弹 |
| `simple_ai` | false | 简化 AI（仅前置追踪，跳过 BFM） |

### 飞行员能力

| 属性 | 默认 | 说明 |
|------|------|------|
| `skill_level` | 0.7 | 战术水平 (0=菜鸟, 1=王牌) |
| `composure` | 0.6 | 冷静度/抗压 (0=易慌, 1=冰冷) |
| `focus` | 0.6 | 目标专注度 (0=分心, 1=死盯) |
| `self_preservation` | 0.5 | 自保意识 (0=不怕死, 1=保命优先) |
| `situational_awareness` | 0.6 | 态势感知 (0=隧道视野, 1=全局洞察) |

---

## 战术机动 (EngageTactic)

基于 Shaw《Fighter Combat》的 BFM 决策树。

```gdscript
enum EngageTactic {
    LEAD_PURSUIT,    # 前置追踪：积极闭合
    LAG_PURSUIT,     # 滞后追踪：保持后半球不冲过
    LEAD_TURN,       # 提前转弯：迎头时抢角度
    HIGH_YOYO,       # 高悠悠：拉高防冲过
    LOW_YOYO,        # 低悠悠：俯冲加速闭合
    BREAK_TURN,      # 急转：被咬尾时防御
    EXTENSION,       # 加速脱离：拉开距离
    SCISSORS,        # 剪刀机动：近距反复交叉
    SNIPER_HOLD,     # 狙击稳瞄：减速 + 不取 lead，机头死锁目标当前位置
}
```

`SNIPER_HOLD` 是机头对准型武器（电磁炮 / 激光）专用：AI 通过
`prefer_nose_aligned_weapon = true` 启用，给装备稳定的锁定 + 充能窗口。

### 战术决策逻辑（简化）

```
态势分析（每帧更新）:
├── 距离/闭合率/aspect angle
├── 速度差/高度差/能量状态
├── 是否在后半球/被咬尾
└── 压力值/态势感知

决策树:
├── 被咬尾 + 能量差 → BREAK_TURN（急转防御）
├── 近距离 + 速度快 → HIGH_YOYO（拉高防冲过）
├── 远距离 + 能量不足 → LOW_YOYO（俯冲加速）
├── 互相绕圈（Lufberry） → SCISSORS / EXTENSION（打破僵局）
├── 后半球优势 → LAG_PURSUIT（滞后追踪）
├── 迎头接近 → LEAD_TURN（提前转弯抢角度）
└── 默认 → LEAD_PURSUIT（前置追踪）
```

---

## 飞行员压力系统

```
_stress: float (0~1)

增加压力:
  - 被命中（大幅增加）
  - 被锁定（缓慢增加）
  - 来袭导弹（大幅增加）
  - 持续处于防御（缓慢增加）

降低压力:
  - 时间流逝自然恢复
  - composure 属性影响恢复速率

压力效果:
  - 高压力 → 判断失误（漂移噪声增大）
  - 高压力 → 速度控制误差增大
  - 高压力 → 可能提前脱离交战
```

---

## 态势感知系统

```
影响因素:
  - situational_awareness 基础值
  - _stress 减少感知
  - skill_level 影响检查频率

感知延迟:
  - 被锁定 → _sa_lock_delay 后才意识到
  - 导弹来袭 → _sa_missile_delay 后才意识到
  - 后方威胁 → 定期"检查六点钟"

效果:
  - 低感知 → 可能不知道被锁定
  - 低感知 → 可能不及时发现导弹
  - 高感知 → 提前预警、更好决策
```

---

## Simple AI 模式

`simple_ai = true` 用于 MQ-109/MQ-110 等低能力单位：

- 仅使用前置追踪（跳过 BFM 决策树）
- 跳过压力系统和态势感知
- 近距绕圈疲劳：持续盘旋超过阈值后进入"发呆"状态，直飞一段时间再恢复
- 适用于 MQ-109/MQ-110（EnemyType.UAV/UCAV）等自动化程度高但战术能力低的无人单位

---

## 编队跟随 (SQUAD_FOLLOW)

### 状态流程

```
SQUAD_FOLLOW
├── 正常跟随 → 飞向阵型位置
├── 掩护扫描 → 每 0.5s 检查队友后半球威胁
│   └── 发现威胁 → ENGAGE（掩护交战）
├── 导弹来袭 → 置 _evading（不切状态）
└── 交战/规避结束 → _rejoining（全速归队）→ SQUAD_FOLLOW
```

### 编队混合

`_formation_blend` (0-1) 控制编队模式过渡：
- 1.0 = 完全编队（轨迹平滑但响应慢）
- 0.0 = 自主飞行（交战/规避时）
- 过渡：`_formation_blend` 平滑趋近目标值

### 敌方护卫的反应通道（Adds 护送编组）

上面的掩护扫描 + 护卫学说（`Squad.escort_doctrine_enabled` / `try_defend_protectee`）**只对玩家队开**，
Adds 类还被 ROE 察觉体系整体排除——结果是敌方护卫机长期对"被自己护送的对象正在挨打"完全无反应。

2026-07-28 补上唯一的反应通道：护卫机在组队时登记到被护送对象的 `escort_guards` 列表上，
被护送对象在受伤结算里回头唤醒护卫，护卫以 **`TS_DIRECTIVE` 目标来源**（优先级高于自主选目标）
`acquire_target(攻击者)` 扑过去。这条路不经过 ROE / 掩护扫描，是纯粹的"挨打→点名"。

---

## 导弹规避（`_evading` 标志，非状态）

```
检测: 扫描 MissileManager 中针对本机的在飞导弹
进入条件: evade_missiles = true 且 personality.missile_aware 且过分层门（should_enter_evade）

规避策略:
1. 释放热诱弹（如果有）
2. 机动规避（急转 + 改变高度）
3. 尝试使导弹脱离雷达锥

退出条件: 威胁消除（导弹爆炸/失活/脱靶）
```

---

## Lufberry 圆圈检测

检测两架飞机互相绕圈的僵局：
- `_lufberry_timer` 累计互相绕圈时间
- 超过阈值后选择 SCISSORS 或 EXTENSION 打破僵局
- 脱出后有冷却期避免反复触发

---

## 目标评估

交战中周期性重评估目标（`_target_eval_timer`）：
- 当前目标仍然是最优？
- 是否有更高优先级威胁？
- focus 属性影响切换意愿（高 focus → 不轻易切目标）

---

## 状态机小结

`ai_controller.gd` **三状态** + 9 战术机动 + 叠加式规避标志：

- **PATROL** — 航路点巡逻，周期性扫描
- **ENGAGE** — BFM 决策树选择战术机动（9 种，见上）
- **SQUAD_FOLLOW** — 编队跟随 + 掩护扫描（每 0.5s 扫长机后半球）
  - 子状态：`_rejoining`（归队）/ `_formation_react_timer`（阵型调整）/ `_squad_attacking_leader_target`（协同攻击）
- **`_evading`** — 与状态正交的规避标志

## TacticalPlanner（P4 重构，玩家 + 僚机 + 常规敌机走的统一决策路径）

新设计核心：**决策（planner） / 执行（physics/weapons/combat_tracking）分离**。详见 [scripts/ai/tactical/](../../scripts/ai/tactical/) 4 文件。

**接入方式**：`Aircraft.use_tactical_planner = true` → `_physics_process` 顶层调 `_run_tactical_planner_if_enabled()`：
1. `Situation.from_aircraft(self)` 抽快照
2. `TacticalPlanner.plan(s, waypoint)` → 13 种 intent 之一
3. `_apply_tactical_plan(plan)` 写入 `target_position` / `target_speed_kmh` / `is_afterburner` / `weapon_mode` / `is_firing` / `_gun_lead_heading`
4. 后续 `update_weapon_mode` / `update_combat` / `update_energy_management` 全部检查 `use_tactical_planner` early-return

**已迁移**：玩家 / 玩家僚机 / 全部常规战机（MIG / INTERCEPTOR / F86 / MIG23 / F100 / A7 / Q5 / MIG31 / SU27 / SU35 / F4 / F104 / FA18 等）

**未迁移**（保留旧 BFMTactics 路径）：BOSS 王牌中队（特殊：BVR / Herbst / cloak / salvo，另有各自的队级战术模块）/ Adds（Tu-160 / AH-64 / CH-47，simple_ai）/ Sentinel（commander_aura buff）

⚠ 已迁移机型的**准确清单**看 [enemy-index.md](../reference/enemy-index.md) 与代码，
不要依赖本文的举例——敌人谱一直在扩。

**主开关**：`SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI` —— **现已默认 `true`**
（旧文档写"默认 false"是 P4 迁移期的状态，早已 flip）

**13 种 intent**（按优先级）：EVADE_MISSILE / EXTEND_RECOVER（残余）/ CRUISE / WAYPOINT_MOVE / PASSIVE_AUTO_FIRE / GROUND_STRAFE / 5b: overshoot 触发 EXTEND / 5b: BOOM_ZOOM_OUT 触发 EXTEND / WIDE_TURN / MERGE_PASS / TAIL_CHASE / CLOSE_TAIL / LEAD_TURN / LAG_PURSUIT / LEAD_PURSUIT

**关键防抖与守卫**：
- Hysteresis：战斗 intent 至少持 0.5s 才允许切到不同战斗 intent（防几何边界翻转）
- BOOM_ZOOM_OUT：仅 `ai_aggression ≤ 0.85` 触发（Gladiator 拒绝撤退）
- Lock-aware crank：`target_locked = false` 时强制 LOS 直瞄不 crank（防止甩出雷达锥）
- Launch quality（仅玩家）：cone 边缘 + bank > 60° 时跳过发射；`fire_and_forget` 导弹绕过此检查

**单元测试**：[scripts/tests/test_bfm_intent.gd](../../scripts/tests/test_bfm_intent.gd)，
跑 `--bench=bfm_intent`（或 `--bench=all`）。case 数持续增长，**不在此写死数字**——以实际跑出的
PASS 计数为准。相关行为 sim 还有 `--bench=surface_pass` / `slow_air_pass` / `joust` 等。
