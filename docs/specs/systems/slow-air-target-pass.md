---
id: slow-air-target-pass
kind: system
status: done
schema_version: 1
spec_version: 1
owner: 用户 + Claude
depends_on: [surface-attack-pass, weapon-employment-doctrine, engagement-discipline]
reconstruction_complete: true
---

# 慢速空中目标交战 pass（Slow Air Target Pass）

> 对直升机这类"几乎不动"的**空中**目标，快机不做缠斗、不咬尾，改做**攻击跑**：
> 对准进入 → 打一波 → 飞越 → 折返再攻。与 [surface-attack-pass](surface-attack-pass.md)
> 共用同一台相位机（SETUP/RUN/EGRESS），只替换三组包络常量与终端瞄准点。

## 0. 问题背景（触发本 spec 的 bug）

**用户报告**：「AI 对付直升机交战效率非常低：绕了好多圈打不中，而且也有锁定上了却不发射导弹的情况。」
**要求**：对慢速几乎不动的目标要做到**一击必杀，不要浪费那么多时间**。

**病灶（log 20260720_115041 实证，F-14 小队 vs CH-47 ×3，t=136~194s）**：
近 60 秒内三架 F-14 反复 `WIDE_TURN→LEAD_TURN→CLOSE_TAIL→overshoot→EXTEND→WIDE_TURN`，
只在 172.5s 偶然凑出一次机炮窗（0.2s 打 9 发击坠 CHK-03）。
全 log 发射阻塞统计（`MSL_BLOCK`，2s/机 节流后）：
`LOCK 133 / WEAPON_MODE 53 / OFF_CONE 21 / TEAM_OVERKILL 11 / UNSTABLE_WIN 3`。

**根因是四层叠加，缺一层都修不好**（历史上每次只修一层，故"反复修了很多次没修好"）：

| # | 层 | 机理 |
|---|---|---|
| 1 | **几何极限环** | 角点速度下最小转弯半径 550m，目标 1 秒只走 60m → 尾追几何不成立。旧补丁只有"太近就 extend 1.5s / 否则 wide_turn"两行：1.5s extend 在 700km/h 下只拉开 ~290m，而重攻门槛 825m，拉完还在圈内立刻重触发 → 极限环。 |
| 2 | **锁定攒不满** | CH-47 在 LOW 档 → 锁定速率 ×0.7 → 需**连续 4.3s** 照射；出雷达锥 0.3s 即清零。绕圈时机头持续扫过目标 → 锁定反复 0.00/1.82 归零。 |
| 3 | **满锁却拒发** | 发射门要求离轴 ≤ `radar_half × 0.55`（F-14 = 19.25°），而 `LEAD_TURN` 等 intent **主动**把机头摆在 27~31° 滞后位 → intent 与发射门互相打架。 |
| 4 | **锁定→转不动死锁** | `_get_missile_phase()` 一旦锁定满就返回 phase 2，坡度上限被压到 35%（为 crank 保稳设计）。若此刻仍在发射锥外，飞机**再也转不进锥**：锁上了→转不动→打不出去→机头飘走→丢锁。无头 sim 实证：满锁 3.30s 时 nose 27°、坡度仅 27.6°/1.1G（可用 7.5G），随后 27°→31°→43° 越飘越远。 |

> 第 4 条是**通用 bug**，不限直升机：任何"锁定完成但机头尚未进锥"的交战都会踩到。

## 1. 设计意图（Why）

- **快机对慢目标的正解是攻击跑，不是缠斗**。真实 BFM 同理：60 m/s 的目标配 550m 转弯半径，
  "咬到六点"在几何上不存在，强行追求它就是绕圈。
- **每趟 pass 必须保证一个射击窗口**。目标是"一趟解决"，不是"贴着磨"。
- **与地面目标同构 → 复用同一台相位机**，不新造第二套状态机（设计哲学：往简单收敛）。
  差异只有两条物理事实：目标**在空中且会缓慢移动**（要提前量/拦截解），
  且**不还击对空火力**（inner 环不必留 AA 安全圈）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 判定门槛

| 项 | 值 | 说明 |
|---|---|---|
| `SLOW_AIR_SPEED_RATIO` | **0.4** | 目标速度 < 本机角点速度 × 此值 → 慢速空目标。F-14 corner≈700km/h → 门槛 280km/h |
| 互斥 | 与 `tgt_is_surface` 互斥 | 地面/舰船已有自己的 pass 路径，不重复标记 |

命中/不命中样例（回归守卫）：CH-47 216km/h ✅慢；UAV 839km/h ❌快；300km/h 慢速喷气机 ❌快。

### 2.2 包络常量（替换 surface 版）

| 项 | 慢速空中 | 对照：地面版 | 理由 |
|---|---|---|---|
| STANDOFF inner | **800m**（下限 `missile_min×1.5`） | 2200m | 直升机无对空火网；2200 会让 RUN 在锁定攒满前就 EGRESS（雷达 3500m 起锁、需 4.3s 照射 → 至少 1.3km 进场余量） |
| ASSAULT inner | **250m** | 120m | 防空中相撞（地面版是防撞地） |
| 折返 reentry | **inner + max(min_turn_r × 4.0, 1200m)** | max(r×2.5, 1500m) | EGRESS 后机头背对目标，要先做 ~180° 掉头（corner 下 ~7.5s、横向偏移 2r），**再**留出进场段稳定机头。1500m 时掉头刚完成就已冲到脸上 |
| RUN 退出对准 | **cos 45°（0.707）** | cos 30°（进出同阈值） | 目标在动，单阈值会在边界抖（29.2°进→30.0°退→34.5°…每 1.5s 翻一次） |

进入 RUN 仍用 `TAIL_AIM_THRESHOLD`（30°），退出才放宽到 45° = 迟滞带。

### 2.3 各相位的瞄准点与速度

| 相位 | pursuit 瞄准点 | 速度 | 为什么 |
|---|---|---|---|
| SETUP | **碰撞航路交会点** | corner | 纯追踪对横切目标有常驻滞后角（实测卡死 35°，进不了 30° 门）；交会解才收敛 |
| RUN / STANDOFF（导弹） | **目标本体**（纯追踪） | **corner**（不加速） | 发射门量的是"机头 vs 目标本体"离轴角；交会点带 `asin(v_t/v_m)` 常驻偏置，close-in 还会放大到 30°+ → 满锁却拒发。速度也不能加：纯追踪要求转率按 1/R 发散，高速下半径变大反而越追越偏（实测 29°→38°→54°） |
| RUN / ASSAULT（机炮） | **机炮提前点**（弹速解） | cruise×1.4 | 机炮解按弹速 1050m/s 求（前置 ~3°），交会点按本机速度求（前置可达 21°）；拿交会点当机炮引导，机头恒停在离目标 ~10° 掠过，5° 火控锥永不开门（实测两趟 pass 掠到 174m/254m，0 次开火） |
| EGRESS | 沿脱离方向外推 | 转出后 AB 全速 | 同 surface 版 |

高度：两种姿态都**与目标同高**（`target_altitude_m = tgt_alt`）。地面版 STANDOFF 的 MID 硬档
是为躲地面 AA 而设，对直升机无意义，反而制造高度差拉大真实离轴角、拖慢锁定。

### 2.4 导弹相位软化的适用条件（通用修正）

`_get_missile_phase()` 返回 2（坡度上限 35%，为保锁而柔化）的条件收紧为：

- `is_cranking()`（**发射后**的支援照射，几何本就稳定）→ 恒 2，不变；
- 锁定已满 **且 目标已进入发射离轴门**（`radar_half × 0.55`）→ 2；
- 锁定已满 **但仍在门外** → **0（满转弯权限）**。语义 = "还在对准段"。

## 3. 行为与公式（How）

### 3.1 相位机（与 surface-attack-pass 同一台）

```
SETUP  --aim_align ≥ cos30°--> RUN
SETUP  --too_close-----------> EGRESS
RUN    --dist ≤ inner---------> EGRESS
RUN    --¬aligned ∧ too_close-> EGRESS
RUN    --aim_align < cos45°---> SETUP        ← 慢速空目标专用迟滞
EGRESS --dist ≥ reentry-------> SETUP
```

### 3.2 关键公式

- 最小转弯半径：`r = v_corner² / (g · 7.0)`
- 碰撞航路交会点：解 `|P_t + V_t·t − P_m| = v_m·t` 的最小正根 t，取 `P_t + V_t·t`。
  无解（追不上）时回落到纯追踪（瞄目标本体）。
- 折返距离：`reentry = inner + max(r × 4.0, 1200m)`

### 3.3 优先级位置（关键）

慢速空目标分流必须置于 **优先级 4.5**，即紧随"优先级 4：地面/水面目标"，
且**在 5a/5b（overshoot / boom-zoom / co-turn breaker）之前**。

理由：5a/5b 全是为"又快又能拉 G 的战斗机"设计的能量学规则，对直升机语义不成立却会抢先命中——
飞越直升机必然满足 overshoot（近距 + 负闭合），高 aspect 也必然满足 co-turn breaker，
于是每趟 pass 刚脱离就被塞进 2~3 秒强制 EXTEND，把相位机踢回起点。
无头 sim 实证：放在 5.9 时全程在 ~1200m 环上摆头 78°↔140°，45s 打不出一次机炮窗。
与优先级 4 并列 = "按目标类别分流"，语义上本就该在同一层。

## 4. 结构与组成（Structure）

- 判定：`Situation.tgt_is_slow_air`（`_recompute` 派生，外部只读）
- 分流：`TacticalPlanner.plan` 优先级 4.5
- 相位机与动作：`BfmIntent.ground_strafe`（由 `tgt_is_slow_air` 内部切换包络）
- 转弯权限：`Aircraft._get_missile_phase` + `_target_within_launch_cone`
- 测试时钟：`Situation.now()` / `Situation.sim_time_override`

## 5. 验收标准（Acceptance / Litmus）

无头验收 `--bench=slow_air_pass`，**必须同时步进真实物理 + 真实 planner，并如实复刻游戏内三道发射门**
（锁定积分含 LOW ×0.7 与出锥 0.3s 清零 / 武器模式 min_range+150m 滞回 / 发射窗口 off-axis 门）——
"打得中"必须是三门齐开的结果，不能是几何单测的纸面对准。

| # | 场景 | 判据 | 实测 |
|---|---|---|---|
| A | 导弹机 vs CH-47，起手侧后背对 | 30s 内打出真实发射窗；锁定攒满；连续 SETUP < 15s；发射距离 ≥ min_range | ✅ t=17.1s, 2929m, 离轴 1.7° |
| B | 机炮机 vs CH-47 | 30s 内打出真实机炮窗；窗口 ≥ 0.3s（log 实证 0.2s 足够击坠）；不绕圈 | ✅ t=17.4s, 累计 4.57s |
| C | 贴脸起手 244m（目标钻进转弯圆） | 30s 内开火；距离幅度 > 1200m（对照旧补丁 ~290m）；不绕圈 | ✅ t=20.1s, 幅度 2674m |
| D | 回归守卫 | CH-47 判慢 / UAV 839km/h 判快 / 300km/h 判快 / 地面目标不重复标记 | ✅ |

回归：`--bench=all` 其余全绿，`surface_pass` 28/28 不受影响。
`bfm_intent` 新增 2 条边界断言（同一几何下快目标走 overshoot、慢目标走 pass）。

## 6. 实现计划（Task Pipeline）

已完成（2026-07-20 单批落地）。

## 7. 索引锚点（Where）

- `scripts/ai/tactical/situation.gd` — `SLOW_AIR_SPEED_RATIO` / `tgt_is_slow_air` / `now` / `sim_time_override`
- `scripts/ai/tactical/bfm_intent.gd` — `SLOW_AIR_*` 常量 / `ground_strafe` / `_intercept_point`
- `scripts/ai/tactical/tactical_planner.gd` — 优先级 4.5 分流
- `scripts/aircraft.gd` — `_get_missile_phase` / `_target_within_launch_cone`
- `scripts/tests/test_slow_air_pass.gd` — 无头验收（bench key `slow_air_pass`）

## 8. 变更记录

- **2026-07-20 v1**：立项 + 落地。根因四层（几何极限环 / 锁定攒不满 / 满锁拒发 / 锁定→转不动死锁）
  一并根治，14 条无头断言全绿。触发来源：用户报告 + log 20260720_115041。
