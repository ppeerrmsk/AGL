---
id: aa-fire-awareness
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 3
owner: 用户
depends_on: [surface-attack-pass, command-wheel, rts-command, wingman-escort-evasion]
reconstruction_complete: true
---

# 僚机对地面机炮火力的警觉（AA Fire Awareness）

> 僚机不再傻傻飞进 AA/CIWS 机炮火力网里挨打：中弹立刻加速脱离；"保持距离"姿态下发完导弹就待在火圈外等命中。

## 1. 设计意图（Why）

- **体验目标**：玩家指挥小队打地面 AA 阵地 / CIWS 舰船时，僚机表现得"惜命且专业"——
  1. **加速脱离**：被机炮弹幕命中 = 已身处火力网，此刻最傻的行为是低速转弯对准/继续压入。应立即打断攻击相位、机头转出后开加力全速拉出，不在火网里逗留。
  2. **保持距离**（轮盘 WHEEL_STANDOFF 姿态）：找好角度 → 进导弹包络就发射 → 弹在飞期间在火圈外 crank 等命中，绝不为"继续压入"进入目标的机炮火力半径。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - 效果即反馈：中弹→飞机自己跑，无 HUD 中介、无新图标。
  - 单杠杆：感知信号只有一个——"被地面/舰船机炮**命中**"。不做火力圈预测扫描。
  - 物理优雅：脱离靠真实 bank/AB/转弯；不瞬移不伪造曲线。
  - 复用既有数值：火力半径读威胁源自己的 live 参数；在飞弹判定复用 TEAM_OVERKILL 同源查询。
- **反模式规避**：
  - 不做全场 AA 火力圈地图 / 绕行路径规划（O(N×M) 扫描 + 二阶机制，playtest 证明必要再补）。
  - SAM/导弹威胁**不归本 spec**——走既有导弹规避分层策略（[[wingman-escort-evasion]]）。
  - 不新增 AIState / 不新增轮盘命令；全部塞进既有对面攻击相位机与编队跟随层。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 威胁源（引用值，权威在各威胁源自己的定义；列出便于重建对照）

| 威胁源 | 对空火力半径 | 单发伤害 | 有效射速 | 备注 |
|---|---|---|---|---|
| AAGunUnit（ZU-23） | 600 m | 4 | 1200 发/min | `GunParams.max_range`，射程判定 ×1.2 |
| CIWS 对空扫射 | 2000 m（1000 px） | 3 | **~16.7 Hz 真弹** | "远距装饰"档 |
| CIWS 近距反飞机 | 1300 m（650 px） | 8 | **~16.7 Hz 真弹** | 紧散布，贴脸会被撕碎 |

> CIWS 打的是**任意最近敌对飞机**（不只玩家），僚机同样会被近距模式撕碎——这是本 spec 的直接动机。

**CIWS 真弹周期（2026-07-28 调整）**：CIWS 每 `N` 发弹里只有 1 发是**结算伤害的真弹**
（其余为纯视觉曳光），`N` 由 **3 → 2**。有效伤害射速 ~11 Hz → **~16.7 Hz**，**拦截 DPS ×1.5**。

- CIWS **依然是真实弹道碰撞拦截，不是概率判定** —— 真弹要**真的飞到**目标身上才算数。
- 三重压制**全部不变**：散布 ±5°、命中半径 12 px、距离衰减（≥800 px 无伤）。
- 60 HP 的导弹**仍需 6 发真弹**命中才被拦下 —— 改的是"多久能打出这 6 发"，不是"几发能打掉"。
- 对本 spec 的影响：舰船火力圈内的停留成本变高，§2.3 的 STANDOFF 安全环（CIWS 舰 2500 m）
  与"被命中即脱离"规则**更值钱**，但常量一个未动。

### 2.2 新增常量（本 spec 权威）

| 常量 | 值 | 说明 |
|---|---|---|
| `AA_FIRE_REACT_S` | 2.5 s | 中弹警觉窗口；每次被地面/舰船机炮命中刷新 |
| `AA_EGRESS_AB_ALIGN_DEG` | 45° | EGRESS 中机头与脱离方向夹角 ≤ 此值 → 开 AB 全速 |
| `AA_STANDOFF_SAFETY_MULT` | 1.25 | STANDOFF inner 环相对目标对空火力半径的安全系数 |

### 2.3 目标对空火力半径 `target_aa_range_m`（STANDOFF inner 用）

| 目标类型 | 取值 |
|---|---|
| GroundUnit 带机炮（AAGunUnit） | 其 `GunParams.max_range`（ZU-23 = 600 m） |
| NavalUnit / MountTarget（舰船有 CIWS 挂点） | 2000 m（CIWS 对空扫射半径） |
| 其它（无对空机炮能力） | 0 |

## 3. 行为与公式（How）

### 3.1 中弹感知（机制 1 触发器）

```
Aircraft.take_bullet_damage(amount, attacker):
    若 attacker 是 GroundUnit 或 NavalUnit 或 MountTarget:
        aa_fire_timer = AA_FIRE_REACT_S      # 重复中弹刷新
        aa_fire_source_pos = attacker.global_position
```
- 只认**机炮弹幕**（本函数天然只收子弹伤害）；导弹伤害不触发（走导弹规避）。
- 空对空机炮（attacker 是 Aircraft）不触发——狗斗中弹是 BFM 层的事。

### 3.2 中弹反应（按当时状态分派）

| 当时状态 | 反应 |
|---|---|
| 对面攻击 pass 的 SETUP / RUN | **立即转 EGRESS**（打断慢速转弯对准与压入——火网内最危险姿态） |
| 对面攻击 pass 的 EGRESS | 按 §3.3 加速规则拉出（本来就在跑，跑快点） |
| SQUAD_FOLLOW / 巡航移动 | **不改航向、不脱队**：AB + max_speed 冲刺至窗口结束，直线快速穿出火区；窗口结束由编队/巡航逻辑自然收速归位。（铁律与编队优雅约束：不因中弹丢玩家命令或破坏编队几何） |
| EVADE_MISSILE | 不干预（导弹威胁优先级更高） |
| manual_control 操控机 | 不反应（玩家全权，速度归玩家/既有辅助） |

### 3.3 EGRESS 加速规则（敌我通用的普适改进）

```
EGRESS 相位中:
    align = dot(机头方向, 归一化(pursuit_pos - my_pos))
    若 align ≥ cos(AA_EGRESS_AB_ALIGN_DEG):    # 机头已转出
        target_speed = max_speed, afterburner = true
    否则:                                        # 仍在硬 break 转向段
        target_speed = corner_speed, afterburner = false   # 现状不变
```
- 现状 EGRESS 恒 corner + 无 AB：break 转向段合理，但转出后仍慢速爬行 = 在火网里多泡好几秒。
- 该规则对所有走对面攻击 pass 的单位生效（含敌机）——对称，敌机也不该傻。

### 3.4 STANDOFF 火圈外投射（机制 2，仅 STANDOFF 姿态分支）

**inner 环公式**（替换现行 `inner = clamp(2200, missile_min×1.5, missile_max×0.6)`）：

```
inner_m = clamp( max(2200, target_aa_range_m × AA_STANDOFF_SAFETY_MULT),
                 missile_min_range_m × 1.5,
                 missile_max_range_m × 0.6 )
```
样例：ZU-23 阵地 600×1.25=750 → 沿用 2200；CIWS 舰 2000×1.25=**2500 m**（现行 2200 会擦进 CIWS 扫射圈，正是"僚机蹭 CIWS 被磨死"的来源）。

**F-Pole 等待（发弹后不压入）**——RUN 相位新增前置判定：

```
RUN 相位中（STANDOFF）:
    no_more_ordnance_needed =
        自己对该目标有仍在制导的在飞导弹
        或 MissileManager.team_inbound_damage(目标, 本队, null) ≥ 目标剩余 hp   # TEAM_OVERKILL 同源
    若 no_more_ordnance_needed:
        不再闭合：pursuit 设为 standoff 环上的 crank 保锁点（复用既有 _missile_engage_pos 语义），
        维持 dist ≥ inner_m；弹命中/失效后恢复正常 RUN 压入
```
- 这正是用户要的"锁定发射之后尽可能不进入 AA 火力范围"：发射动作本身已由既有开火门控制，本条只是堵住"弹已出手还傻傻往里飞"。
- TEAM_OVERKILL 判定与开火封锁同源 → 不会出现"想发弹却被 hold 在圈外发不了"的自锁。

## 4. 结构与组成（Structure）

| 部件 | 注入点类别 | 规模 |
|---|---|---|
| 中弹感知字段 `aa_fire_timer` / `aa_fire_source_pos` | Aircraft 新字段 + `take_bullet_damage` 尾部钩子 | ~6 行 |
| 感知透传 | Situation 新字段（`aa_fire_active` / `target_aa_range_m`），from_aircraft 填充（战术输入直读目标 params，不涉及机动性 buff accessor 规范） | ~8 行 |
| 相位打断 + EGRESS 加速 + inner 公式 + F-Pole hold | bfm_intent.ground_strafe（既有相位机内改写，无新状态） | ~25 行 |
| 编队/巡航 AB 冲刺窗口 | 编队跟随速度层（squad follow 速度匹配处一个 if） | ~5 行 |
| 诊断 | EventLogger 事件 `AA_FIRE`（中弹触发/相位打断/hold 进出，先行落地供验收） | ~5 行 |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **场景 A（加速脱离）**：单僚机 ASSAULT 扫射 ZU-23 阵地，中弹后 ≤0.5s 内相位转 EGRESS；机头转出 45° 内开 AB；EventLogger 统计火力半径内滞留时长较修改前显著下降。
- [ ] **场景 B（保持距离）**：WHEEL_STANDOFF 下命令打 CIWS 舰：全程 dist ≥ 2400 m；发弹后在环外 crank；弹命中/失效后才恢复压入；整场僚机 0 死亡。
- [ ] **场景 C（编队穿越）**：编队巡航穿过 AA 火区被打：僚机不变航向不脱队，AB 冲刺穿出，窗口结束自然归位。
- [ ] **场景 D（铁律）**：commanded_target 点名打 AA 本体：中弹 EGRESS 后仍折返继续攻击，绝不放弃命令目标。
- [ ] **场景 E（玩家）**：manual_control 操控机中弹无任何 AI 抢速度/抢相位。
- [ ] **回归**：敌机（MQ-112 等对面攻击用户）行为无劣化；joust / 空对空 standoff 轨道不受影响（inner 公式只在 surface 分支）。
- [ ] **裸物理 sim 断言**（turn_physics harness 范式）：EGRESS AB 段脱离用时断言 + STANDOFF hold 不进 inner 断言，注册 bench_runner UNIT_TESTS 滚进 `--bench=all`。
- [ ] 性能：中弹钩子 O(1)、无每帧全场扫描；生存模式 Sentinel + Lv5+ 压测 FPS 掉幅 < 15。
- [ ] 已知 seam 未触碰 / 已妥善处理（见 architecture/known-seams.md）。
- [ ] i18n：无新增玩家可见文本（轮盘沿用 WHEEL_STANDOFF）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 感知钩子 + 诊断（先行）
- [x] Aircraft 字段 + take_bullet_damage 钩子 + timer 递减
- [x] EventLogger `AA_FIRE` 事件（hit 触发；interrupt/hold 经 PLAN rationale 归因——planner 纯函数内不落独立事件防 tick 级刷屏）

### 阶段 2 — EGRESS 加速 + 相位打断
- [x] bfm_intent EGRESS 对准判定 → AB/max_speed
- [x] aa_fire_active 时 SETUP/RUN → EGRESS 强制转移

### 阶段 3 — STANDOFF 火圈
- [x] Situation.target_aa_range_m 推导（§2.3 表）
- [x] inner_m 公式替换 + F-Pole hold（team_inbound_damage 复用）

### 阶段 4 — 编队冲刺 + 验收
- [x] squad follow 速度层 AB 窗口（AircraftFormation._update_speed，编队 LOD 满速冲刺）
- [x] planner 纯函数 sim 断言 8 项（test_surface_pass §E，滚进 --bench=all；连同存量 20 项 28/28 绿）
- [ ] §5 场景 A–E 生存模式 playtest + Sentinel 压测

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| CIWS 真弹周期 / 散布 / 命中半径 / 距离衰减 | `scripts/naval/naval_weapons.gd`（CIWS_REAL_BULLET_CYCLE 等） |
| 中弹感知字段/钩子/递减 | `scripts/aircraft.gd`（AA_FIRE_REACT_S / aa_fire_timer / take_bullet_damage / _physics_process_impl） |
| 感知透传 | `scripts/ai/tactical/situation.gd`（aa_fire_active / target_aa_range_m / fpole_hold） |
| 相位打断 + EGRESS AB + inner 公式 + F-Pole | `scripts/ai/tactical/bfm_intent.gd`（ground_strafe + AA_* 常量） |
| 编队冲刺 | `scripts/aircraft/aircraft_formation.gd`（_update_speed） |
| sim 断言 | `scripts/tests/test_surface_pass.gd`（§E，--bench=surface_pass） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-13 | 1 | 初稿（draft，待用户定稿） |
| 2026-07-28 | 3 | **CIWS 真弹周期 3 → 2**（§2.1）：每 2 发 1 发真弹，有效伤害射速 ~11 Hz → ~16.7 Hz、**拦截 DPS ×1.5**。仍是真实弹道碰撞拦截而非概率判定；散布 ±5° / 命中半径 12 px / ≥800 px 无伤三重压制不变；60 HP 导弹仍需 6 发真弹命中。本 spec 的常量（2.5 km 安全环 / 2.5 s 警觉窗 / 45° 脱离门）一个未动，但舰船火力圈的停留成本随之上升 |
| 2026-07-20 | 2 | 用户确认三取舍（EGRESS 加速敌我通用 / 不做火力圈预判 / 编队只加速不变向）→ 全量实现落地 + §E sim 断言 8 项（28/28 绿）。status: in-progress，差 §5 playtest/压测 |
