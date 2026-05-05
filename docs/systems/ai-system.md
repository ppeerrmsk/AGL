# AI 系统参考

## 概述

`AIController`（`scripts/ai_controller.gd`，~1500 行）作为子节点附加到 Aircraft 上，通过状态机控制飞机行为。

---

## 状态机

```gdscript
enum AIState { PATROL, ENGAGE, EVADE_MISSILE, SQUAD_FOLLOW }
```

| 状态 | 说明 |
|------|------|
| PATROL | 按航路点巡逻，定期扫描敌机 |
| ENGAGE | 交战中，运行 BFM 战术决策树 |
| EVADE_MISSILE | 规避来袭导弹（释放热诱弹+机动） |
| SQUAD_FOLLOW | 编队跟随长机，掩护扫描 |

---

## 飞行员属性 (@export)

### 基础巡逻

| 属性 | 类型 | 说明 |
|------|------|------|
| `aircraft` | Aircraft | 控制的飞机 |
| `waypoints` | PackedVector2Array | 巡逻航路点 |
| `patrol_altitude` | float | 巡逻高度 |
| `arrival_distance` | float | 到达判定半径 |

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
}
```

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

`simple_ai = true` 用于 UAV 等低能力单位：

- 仅使用前置追踪（跳过 BFM 决策树）
- 跳过压力系统和态势感知
- 近距绕圈疲劳：持续盘旋超过阈值后进入"发呆"状态，直飞一段时间再恢复
- 适用于 UAV/UCAV 等自动化程度高但战术能力低的单位

---

## 编队跟随 (SQUAD_FOLLOW)

### 状态流程

```
SQUAD_FOLLOW
├── 正常跟随 → 飞向阵型位置
├── 掩护扫描 → 每 0.5s 检查队友后半球威胁
│   └── 发现威胁 → ENGAGE（掩护交战）
├── 导弹来袭 → EVADE_MISSILE
└── 交战/规避结束 → _rejoining（全速归队）→ SQUAD_FOLLOW
```

### 编队混合

`_formation_blend` (0-1) 控制编队模式过渡：
- 1.0 = 完全编队（轨迹平滑但响应慢）
- 0.0 = 自主飞行（交战/规避时）
- 过渡：`_formation_blend` 平滑趋近目标值

---

## 导弹规避 (EVADE_MISSILE)

```
检测: 每帧扫描 MissileManager 中针对本机的在飞导弹
进入条件: evade_missiles = true 且检测到来袭导弹

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

## AI 状态机（CLAUDE.md 摘出，2026-05-05）

`ai_controller.gd` 四状态 + 8 战术机动（战术执行委托 `ai/bfm_tactics.gd`，规避 `ai/missile_evasion.gd`，目标选择 `ai/target_selection.gd`，编队 `ai/squad_coordination.gd`）：

- **PATROL** — 航路点巡逻，周期性扫描
- **ENGAGE** — BFM 决策树选择战术机动
  - LEAD_PURSUIT / LAG_PURSUIT / LEAD_TURN / HIGH_YOYO / LOW_YOYO / BREAK_TURN / EXTENSION / SCISSORS
  - **SNIPER_HOLD** — 机头对准型武器专用（电磁炮 / 激光剑等）。直瞄目标当前位置（不取 lead）+ 减速 → 给装备稳定锁定+充能窗口。AI 通过 `prefer_nose_aligned_weapon=true` 启用，目标在前 80° 锥内+不太近+未被咬尾时自动选用
- **EVADE_MISSILE** — 释放热诱弹 + 急转
- **SQUAD_FOLLOW** — 编队跟随 + 掩护扫描（每 0.5s 扫长机后半球）
  - 子状态：`_rejoining`（归队）/ `_formation_react_timer`（阵型调整）/ `_squad_attacking_leader_target`（协同攻击）

## TacticalPlanner（P4 重构，玩家 + 僚机 + 9 种敌机走的统一决策路径）

新设计核心：**决策（planner） / 执行（physics/weapons/combat_tracking）分离**。详见 [scripts/ai/tactical/](../../scripts/ai/tactical/) 4 文件。

**接入方式**：`Aircraft.use_tactical_planner = true` → `_physics_process` 顶层调 `_run_tactical_planner_if_enabled()`：
1. `Situation.from_aircraft(self)` 抽快照
2. `TacticalPlanner.plan(s, waypoint)` → 13 种 intent 之一
3. `_apply_tactical_plan(plan)` 写入 `target_position` / `target_speed_kmh` / `is_afterburner` / `weapon_mode` / `is_firing` / `_gun_lead_heading`
4. 后续 `update_weapon_mode` / `update_combat` / `update_energy_management` 全部检查 `use_tactical_planner` early-return

**已迁移**：玩家 / 玩家僚机 / MIG / INTERCEPTOR / F86 / MIG23 / F100 / A7 / Q5 / MIG31 / SU27（9 种常规战机）

**未迁移**（保留旧 BFMTactics 路径）：F-47 / F-14_Poltergeist BOSS（特殊：BVR/Herbst/cloak/salvo）/ Adds（Tu-160/AH-64/CH-47，simple_ai）/ Sentinel（commander_aura buff）

**主开关**：`SurvivorData.ENABLE_PLANNER_FOR_REGULAR_AI`（默认 false，flip 即启用所有迁移机型）

**13 种 intent**（按优先级）：EVADE_MISSILE / EXTEND_RECOVER（残余）/ CRUISE / WAYPOINT_MOVE / PASSIVE_AUTO_FIRE / GROUND_STRAFE / 5b: overshoot 触发 EXTEND / 5b: BOOM_ZOOM_OUT 触发 EXTEND / WIDE_TURN / MERGE_PASS / TAIL_CHASE / CLOSE_TAIL / LEAD_TURN / LAG_PURSUIT / LEAD_PURSUIT

**关键防抖与守卫**：
- Hysteresis：战斗 intent 至少持 0.5s 才允许切到不同战斗 intent（防几何边界翻转）
- BOOM_ZOOM_OUT：仅 `ai_aggression ≤ 0.85` 触发（Gladiator 拒绝撤退）
- Lock-aware crank：`target_locked = false` 时强制 LOS 直瞄不 crank（防止甩出雷达锥）
- Launch quality（仅玩家）：cone 边缘 + bank > 60° 时跳过发射；`fire_and_forget` 导弹绕过此检查

**单元测试**：[scripts/tests/test_bfm_intent.gd](../../scripts/tests/test_bfm_intent.gd) 共 73 个 case，调用 `BfmIntentTest.run_all()` 跑（无框架，console 输出 PASS/FAIL）
