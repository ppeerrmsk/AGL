---
id: engagement-discipline
kind: system
status: in-progress
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [target-engageability-selection, joust-attack-run, weapon-employment-doctrine]
reconstruction_complete: true
---

# 交战纪律：无意图不开火 + 反平面同向缠斗

> 敌人不再朝"正好路过机头"的玩家无脑喷机炮；AI 友军不再被又快又持久的高 G 盘旋目标（UAV/UCAV）拽进平面同向缠斗兜圈到能量耗尽被反杀。

## 1. 设计意图（Why）

playtest（combat_log_20260709_220858）暴露两个同源病：**当前没有"交战承诺"这一层**——敌人几何一对上就开火，友军几何一脱开就放弃。

- **体验目标**：
  - **A（敌人开火纪律）**：没有明确攻击目标（`combat_target`）的敌机不该只因玩家从机头前掠过就自动扫射。开火是"我正在攻击你"的信号，不是环境噪声。偶尔的机会射击由**已交战**敌机的追踪解自然产生即可，不需要无目标兜底扫射。
  - **B（反平面同向缠斗）**：AI 友军对付高 G 匀速盘旋的慢圈目标时，不该跟着对方在同一个平面圆圈里比拉杆——那样只会把速度磨到角点、能量清零，最后被匀速盘旋的对手在某一圈抓到快照反杀。能量劣势时应主动打破缠斗、拉开重建能量、换角度重攻（boom-zoom）。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - "敌人行为要可读"：开火=攻击意图，玩家能从"谁在朝我开火"读出威胁，而不是被无意图的流弹背刺。
  - "不要死亡螺旋"（feedback [[feedback_no_stall_from_turning]]）：反平面缠斗正是"转弯转到能量清零"的团队版；能量地板之外再加战术层的"别陷进去"。
  - "僚机要有战术脑"：会 disengage-reattack 的僚机比原地兜圈的僚机更像王牌。
- **反模式规避**：
  - 不搞"敌人永不开火"（会让敌人变傻靶子）——只掐掉**无 `combat_target`** 时的兜底扫射，有目标的开火判定不动。
  - 不改 UAV 数值（不 nerf 敏捷）、不动僚机 2s range-grace 脱战循环（本轮范围外，见 §9 后续）。
  - B 只作用于 **AI 控制**的飞机（僚机 / 敌机），**绝不**强拽人类操控的长机（人类走位是玩家的选择，见 [[feedback_player_command_iron_rule]]）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 特性 A — 敌人开火纪律

| 字段 | 值 | 说明 |
|---|---|---|
| 触发对象 | 非 `use_tactical_preference`（AI 控制）飞机 | 人类操控机（含被接管的长机）不受此约束，保留独立机炮意识 |
| 门条件 | 无有效 `combat_target` | `combat_target == null` 或已 `is_destroyed` / 失效 |
| 效果 | `auto_gun_scan` 早退，不锁 `is_firing`、不扫 `all_units` | AI 只能在**有交战目标**时经追踪开火判定开火 |

> 语义：AI 飞机的机炮开火从此**唯一**来自"有 combat_target 时的追踪解开火判定"。无目标的 AI 一律停火。人类机的独立扫射（2026-04-22 引入）不变。

### 2.2 特性 B — 反平面同向缠斗（能量感知 co-turn breaker）

| 常量 | 值 | 说明 |
|---|---|---|
| `COTURN_BREAK_BANK_DEG` | 60° | 目标 bank 绝对值超此 → 视为"硬盘旋对手"（复用 `HIGH_BANK_DEG`） |
| `COTURN_BREAK_ENERGY_RATIO` | 1.08 | 本机速度 ≤ 角点速度×此值 → 判"能量已被磨到角点，再耗就掉进螺旋" |
| `COTURN_BREAK_ASPECT_DEG` | 70° | 目标 aspect 仍 > 此值（没带到尾后 / 没形成解）→ 判"兜圈没赢角度" |
| `COTURN_BREAK_HOLD_S` | 2.0 | co-turn 类 intent 需已持续 ≥ 此秒（防一进弯就误判） |
| `COTURN_BREAK_EXTEND_S` | 3.0 | 触发后强制脱离/重建能量时长（与 5b boom-zoom 一致） |
| `COTURN_BREAK_AGGR_MAX` | 0.85 | `ai_aggression` > 此值的 Gladiator 不脱离（设计上"死咬"的近战机型，同 5b） |

## 3. 行为与公式（How）

### 3.1 特性 A — 开火判定表（AI 分支）

| 情形 | 旧行为 | 新行为 |
|---|---|---|
| AI 有 `combat_target` | `auto_gun_scan` 整体跳过，走 combat_tracking 开火判定 | **不变** |
| AI 无 `combat_target` | `auto_gun_scan` 扫 `all_units`，任意敌对进 ±`fire_cone`+射程 → 开火 | **早退，不开火** |
| 人类机（`use_tactical_preference`） | 独立扫射（有/无 combat_target 都可） | **不变** |

伪代码（`auto_gun_scan` 顶部，AI 分支）：
```
if not ac.use_tactical_preference:
    if has_valid_combat_target(ac):
        return   # 旧：有目标整体跳过（走 combat_tracking）
    else:
        return   # 新：无目标 AI 一律停火，不再兜底扫射 all_units
```
（等价于：AI 分支无条件 `return`——AI 永不经 auto_gun_scan 开火；开火全权交给 combat_tracking 的追踪解。）

### 3.2 特性 B — co-turn breaker 判定

在 TacticalPlanner 决策树里，紧跟现有 "5b boom-zoom（held>8s + aspect>80°）" 之后，加一条**能量触发**的旁路（不依赖 intent 持续 8s，避免 intent 抖动时永远攒不满 8s）：

```
# 5b.2 能量感知 co-turn breaker（仅 AI 控制）
if not s.is_tactical_preference_user \
    and not s.tgt_is_surface \
    and s.ai_aggression <= COTURN_BREAK_AGGR_MAX \
    and abs(s.tgt_bank_deg) > COTURN_BREAK_BANK_DEG \
    and s.aspect_angle_deg > COTURN_BREAK_ASPECT_DEG \
    and (s.my_speed_ms * 3.6) <= s.corner_speed_kmh * COTURN_BREAK_ENERGY_RATIO \
    and _is_combat_intent(s.prev_intent) \
    and s.prev_intent_held_for > COTURN_BREAK_HOLD_S:
        plan = BfmIntent.extend_recover(s)
        plan.intent = BOOM_ZOOM_OUT
        plan.trigger_extend_seconds = COTURN_BREAK_EXTEND_S
        plan.rationale = "能量劣势平面缠斗 → boom-zoom 重建能量再攻"
        return plan
```

判定直觉：**"对方在硬盘旋 + 我已经磨到角点 + 还没带到它尾后 + 已经这么兜了 ≥2s"** → 我正在输掉这个平面缠斗，脱出去用能量/垂直重攻。EXTEND_RECOVER 的残余计时（现有机制）保证脱离后先拉开 3s 再回头，不会脱一帧又扑回来。

与现有分支的关系：
- 5b（held>8s+aspect>80°）是"打了很久咬不上尾"的**时间**触发；5b.2 是"能量已空"的**能量**触发。两者互补：能量先空的走 5b.2（更早），打得久但能量没空的走 5b。
- 慢目标过顶分支（`heading_diff>90°` + `tgt_speed < corner×0.5`）只处理**慢**目标绕圈；co-turn breaker 处理**快而持久的高 G 盘旋**（UAV 233m/s 不算"慢"，旧分支抓不到）。

## 4. 结构与组成（Structure）

- **特性 A**：改 `auto_gun_scan`（AircraftWeapons）一处 AI 分支的早退条件。无新字段、无新节点。
- **特性 B**：TacticalPlanner 决策树加一条旁路 + 7 个常量；复用现有 `BfmIntent.extend_recover` + `BOOM_ZOOM_OUT` intent + EXTEND 残余计时。Situation 无需新字段（`is_tactical_preference_user` / `tgt_bank_deg` / `aspect_angle_deg` / `my_speed_ms` / `corner_speed_kmh` / `ai_aggression` / `prev_intent_held_for` 皆已有）。
- **迁移开关**：B 只对走 planner 的飞机生效（僚机 + 已迁移 9 种敌机）。敌方 UAV/UCAV 是 simple_ai 不走 planner——但**友军僚机**走 planner，正是被反杀的一方，覆盖到位。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **A**：无 `combat_target` 的敌机从玩家机头前掠过时，F9 日志无该敌机的 `[GUN]` 命中玩家记录；有 `combat_target` 且对准时照常开火。
- [ ] **A**：友军僚机无目标时不再出现 `[GUN_BURST]` 对空放空枪（复用 2026-07-07 诊断）。
- [ ] **B**：AI 僚机对高 G 盘旋 UAV 交战时，日志出现 `PLAN ... → BOOM_ZOOM_OUT (why=能量劣势平面缠斗)`，且不再出现连续 >4s 的 `bnk≈±85° g≈11 spd 贴角点` 平面兜圈。
- [ ] **B**：人类操控的长机（`is_tactical_preference_user`）交战时**不**被 co-turn breaker 强制拉扯（玩家走位不受干扰）。
- [ ] **B**：零 buff / 常规对头交战下行为不变（新分支条件不满足时不触发）。
- [ ] 单测 `test_bfm_intent.gd` 全绿（新增 ≥2 case：能量空触发 boom-zoom / 人类机不触发）。
- [ ] 物理无回归：`--bench=turn_physics` 双指标未劣化（见 [[project_turn_physics_test_harness]]）。
- [ ] 性能：无新增每帧全场扫描（A 是**去掉**一次 all_units 扫描，净收益；B 仅多几个标量比较）。
- [ ] 已知 seam 未触碰（effective_corner_speed 经 accessor 层，未直读 params）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 特性 A（敌人开火纪律）
- [x] `auto_gun_scan` AI 分支：无有效 `combat_target` → 早退（AI 分支无条件 return，不扫 all_units、不锁 is_firing）。
- [x] 保留人类机（`use_tactical_preference`）独立扫射路径不变。
- [ ] 手测 / 日志核对：无目标敌机 & 无目标僚机停火（playtest 待跑）。

### 阶段 2 — 特性 B（反平面同向缠斗）
- [x] TacticalPlanner 加 6 常量 + "5b.2 能量感知 co-turn breaker" 旁路（仅 `not is_tactical_preference_user`）。
- [x] `test_bfm_intent.gd` 加 case：能量空+高 bank+aspect 高 → BOOM_ZOOM_OUT；人类机同条件 → 不触发。

### 阶段 3 — 验收 & 收尾
- [x] 跑 `BfmIntentTest.run_all()`（92/92 通过，含 2 新 case）+ 回归 gun_burst 9/9 · gun_aim 6/6 · weapon 7/7。
- [ ] playtest：UAV 缠斗僚机会脱出重攻、不被反杀；敌人不再流弹背刺。
- [x] 填 §7 锚点 + 同步 reference 索引（script-index tactical_planner 行）+ §8 变更记录。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 特性 A 开火纪律 | `scripts/aircraft/aircraft_weapons.gd`（`auto_gun_scan`） |
| 特性 B co-turn breaker | `scripts/ai/tactical/tactical_planner.gd`（`_decide`） |
| B 复用 intent | `scripts/ai/tactical/bfm_intent.gd`（`extend_recover`） |
| Situation 字段 | `scripts/ai/tactical/situation.gd` |
| 单测 | `scripts/tests/test_bfm_intent.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-09 | 1 | 初稿（playtest combat_log_20260709_220858 派生）：特性 A 无目标不开火（最小修）+ 特性 B AI 反平面同向缠斗 |

## 9. 后续（本轮范围外）

- 僚机 2s `SQUAD_RANGE_GRACE` 脱战循环（log 264.7~284.9s Vigor 对 UAV-10 反复 acquire/2s-disengage）——本轮用户未选，但是"僚机打不动"的另一独立根因，建议下轮处理（让僚机对够得着的目标咬住闭合，而非每 2s 放弃）。
- 是否给人类长机加"能量劣势提示"（HUD），提醒玩家别死拉平面圈——待定。
