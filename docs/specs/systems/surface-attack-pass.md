---
id: surface-attack-pass
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 5
owner: 用户 + Claude
depends_on: [joust-attack-run, weapon-employment-doctrine, command-wheel, rts-command]
reconstruction_complete: false
---

# 对面攻击 pass 循环（Surface Attack Pass）

> 对地面单位 / 舰船这类"几乎不动"的目标，飞机做**俯冲攻击跑**：对准进入 → 打一波 →
> 飞越/脱离 → 折返再攻，循环往复。机炮贴地俯冲穿越，导弹高位保持距离打带跑，
> 由**姿态（STANDOFF / ASSAULT）**分流——同一套 pass 骨架，只换包络/高度/速度。

## 0. 问题背景（触发本 spec 的 bug）

**病灶（log 20260707_221548 实证）**：玩家指挥友机 F-16 机炮打 SAM（`RNG=376m`），
飞机在 `对地 SETUP：转弯对准目标 (off=70°)` 子状态里**卡死 47 秒绕圈**，机头夹角从不收敛。

**根因（几何死锁）**：现 `ground_strafe`（[bfm_intent](../../scripts/ai/tactical/bfm_intent.gd) 机炮分支）
只有 SETUP / RUN / BREAK 三态，其中：
- SETUP 无条件"corner speed 转弯对准目标"；
- 快机在 corner 速度下最小转弯半径 `r = v²/(g·G)` 可达 500~1000m，**目标钻进转弯圆内**
  （376m ≪ r）时机头永远扫不到它 → aim_align 到不了 RUN 门槛 → 永远 SETUP；
- 唯一逃生出口 BREAK 需 `closing < -50 m/s`，但稳定绕圈时闭合率≈0 → **BREAK 永不触发** →
  死循环绕圈。

**病例 2（log 20260711_205142，命令轮盘集火 FFG-753 实证，2026-07-11）**：僚机 F-16 在
**6.2 km 远距**对舰进入 `对面 SETUP[STANDOFF]：转弯对准 (off=163° r=544m)` 后同样绕圈不收敛——
291s~333s 速度全程钉死 corner 695 km/h、对目标方位角反复扫过整圈（+144°→+9°→-111° 循环）、
距离 6→9 km 漂移，40+ 秒未进入 RUN；341.6s 二次下令复现。说明死锁**不止"目标钻进转弯圆内"
一种触发**：远距 SETUP 的对准判定/回写同样存在不收敛路径。玩家观感 = "保持距离命令让僚机
慢速背对目标飞"（实为绕圈外侧弧段）。修复后须以此场景（6 km 对舰 STANDOFF）加回归断言。

> **已修复（2026-07-11, spec v4）**：根因**不是** SETUP 不收敛（无头 sim 证明 SETUP 9s 内收敛），
> 而是 STANDOFF `inner` 误设为远环 `missile_max×0.5`——命令打环内目标（6km 对舰 / 弹程 16km→环 8km）
> 一进 RUN 就 `dist≤inner` → 立即 EGRESS 背身外逃到 reentry(9km) 绕圈。改 `inner` 为固定近距
> `2200m`（"别更近"语义）后，命令打 6km 对舰 → 压入 6→2.2km 全程开火（sim C：min 1700m、EGRESS 28%、
> 不外逃）。回归断言 = `test_surface_pass.gd` 场景 C（`--bench=surface_pass`）。

**同类病早有根治、但排除了地面**：空中慢速目标的同一"太近转不回来"病，
[tactical_planner](../../scripts/ai/tactical/tactical_planner.gd) 优先级 5.9 已用
"贴脸 → 短 extend 拉开 → 远处转回"根治，但该段开头写死 `not s.tgt_is_surface`，
**明确把地面/水面目标排除在外**。2026-04-29 的 strafe 状态机只堵了"越飞越远（拉到 6km）"
那一半，反方向"太近绕死"从未处理。本 spec 补齐地面侧的对称逃生路径，并把它升级成完整 pass 循环。

## 1. 设计意图（Why）

- **体验目标**：对不动的地面/海面目标，飞机像真实对地攻击一样"压下去打一梭 → 拉起来飞越 →
  绕回来再压一轮"。玩家指挥机炮打 SAM 绝不再原地绕圈空转；导弹机对地则高位打带跑、少挨防空火力。
- **North star（承接 joust-attack-run）**：**pass = 可复用行为原语**。joust 已为**空中动目标**
  实现 RUN_IN → BREAK → 折返；本 spec 是它在**面目标（静止）**上的姊妹实现——去掉提前量/闭合放弃，
  加入"最小转弯半径守卫"与"俯冲/保持距离"两姿态。
- **姿态即战术（承接 command-wheel）**：STANDOFF（保持距离）/ ASSAULT（突击）是命令轮盘攻击环
  的姿态轴。本 spec 先落地"姿态驱动的对面 pass"，默认姿态由弹药自动推导，命令轮盘（其 phase 4）
  后续只需覆盖姿态字段即可接管。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - "玩家只控走位、不精确控速"——玩家指挥"打那个 SAM"，飞机自主完成俯冲-脱离-折返，无需微操。
  - "物理优雅、禁止非物理强扭"——折返靠真实 bank/盘旋完成，不瞬移坐标、不伪造曲线。
  - "不让转弯转到失速"——SETUP/RUN 速度地板 = corner speed，脱离用高速，绝不因转弯掉进死亡螺旋。
- **反模式规避**：不新增 `if in_survivor_mode`；纯几何 + 一枚 phase 状态位，走既有
  `_apply_tactical_plan` 回写通道（与 `_bfm_prev_intent` 同源），不散点改物理 tick。

## 2. 数据定义（What —— 权威源）

### 2.1 姿态（Posture）

| 姿态 | 何时 | 打法 | 高度 |
|---|---|---|---|
| **ASSAULT**（突击） | 解析武器 = GUN | 贴地俯冲穿越目标扫射，飞越后拉起折返 | 俯冲到目标高度 `tgt_alt` |
| **STANDOFF**（保持距离） | 解析武器 = MISSILE / railgun | 高位进入到导弹包络就发射，够近前就脱离，绝不俯冲进近距 AA | 保持 MID（玩家走高度偏好） |

**默认姿态推导（无命令轮盘覆盖时）**：直接取 `_apply_combat_weapon` 竞选出的
`plan.weapon_mode`——
- 有导弹且在导弹包络 → 竞选出 MISSILE → **STANDOFF**；
- 无导弹 / 出包络 / 玩家锁机炮 / 双击冲锋 → GUN → **ASSAULT**。

这天然实现用户定义的默认："有导弹就保持距离，没导弹了就机炮"。**无需**单独的弹药判断逻辑。

**命令轮盘覆盖（已接线，2026-07-12 command-wheel phase 4）**：`Situation.attack_posture` 三态
`AUTO(0) / STANDOFF(1) / ASSAULT(2)`，随 `Aircraft.attack_posture` **门控透传**（仅带
commanded_target 时读取，无命令恒 AUTO 防残留）；轮盘 standoff/assault 槽经
`SquadCommandController.command_attack_all(target, posture)` 广播写入。
**与原案的偏离**：强制姿态只切换包络分流、暂不强制武器锁——竞选在对应包络内自然收敛
（test_surface_pass §D 实测：强制 STANDOFF 全程 MISSILE、守住 standoff；强制 ASSAULT
导弹机也俯冲进机炮 pass）。若后续 playtest 出现竞选与姿态打架再补武器锁。

### 2.2 包络（按姿态实时解析，禁止烘焙——承接 weapon-doctrine 原则2）

单位：`_m` 为米（Situation 的 `dist_m` 同域），`_px` 为像素（`× PIXELS_PER_METER=0.5`）。

| 姿态 | `outer_m`（火力窗外缘） | `inner_m`（脱离内缘 = 折返触发） |
|---|---|---|
| ASSAULT | `gun_range_m`（`s.gun_range_m`） | `min(INNER_FLOOR_M=120m, outer×0.6)`（穿越扫射地板，防撞地；min 即 C2 守卫） |
| STANDOFF | `missile_max_range_m`（`s.missile_max_range_m`） | `clamp(STANDOFF_INNER_M=2200m, missile_min×1.5, missile_max×0.6)`（固定近距 AA-standoff） |

**STANDOFF inner = "最小 AA 距离"，不是"远距环"（病例2 定案）**：`inner` 语义是**"别飞得比这更近"**——
RUN 从当前距离一路压入开火，直到 ~2.2km 才 break。**曾误设为远环 `missile_max×0.5`**：命令打环内目标
（6km 对舰、弹程 16km → 环 8km）时，一进 RUN 就 `dist≤inner` → 立刻 EGRESS 背身外逃到 reentry(9km) →
20s 绕圈背飞（= 病例2 log "距离 6→9km 漂移/方位角扫整圈/背对目标飞"）。改回固定近距 inner 后，
命令打 6km 对舰 → 压入 6→2.2km 全程开火（sim C：min 1700m，不外逃）。coast-through 由 corner 硬 break +
预减速 + STANDOFF 侧向 beam break 解决（见 §2.4）。

### 2.3 最小转弯半径守卫（根治绕圈的核心）

```
corner_ms   = corner_speed_kmh / 3.6
min_turn_r  = corner_ms² / (9.81 × TURN_G)          # 估算持续 G 下的最小盘旋半径（米）
too_close   = dist_m < min_turn_r × REATTACK_MULT   # 目标在转弯圆内 → 转不回来

# reentry 分姿态（C3：不含 outer×1.3——STANDOFF outer=8km 会算出 10km 折返）
reentry_m(ASSAULT)  = max(min_turn_r × REENTRY_MULT, REENTRY_FLOOR_M)
reentry_m(STANDOFF) = clamp(inner_m + max(min_turn_r × 2.0, 800), inner_m + 500, outer_m × 0.95)
```

| 常量 | 值 | 说明 |
|---|---|---|
| `TURN_G` | 7.0 | 估算最小转弯半径用的持续 G（与 planner `SLOW_TARGET_TURN_G` 同值） |
| `REATTACK_MULT` | 1.5 | `dist < min_turn_r × 此值` → too_close，判定"转不回来" |
| `REENTRY_MULT` | 2.5 | ASSAULT EGRESS 提交到 `dist ≥ min_turn_r × 此值` 才折返（空间滞回带 + 像样通场距离） |
| `REENTRY_FLOOR_M` | 1500m | ASSAULT 折返地板：短射程机炮也要拉出一段真正的 pass，而非贴脸小翻身 |
| `STANDOFF_INNER_M` | 2200m | STANDOFF 脱离/最小 AA 距离（"别飞更近"，非"退到远环"；病例2 定案，见 §2.2） |
| `EGRESS_OUT_PX` | 3000px | EGRESS 外推点距离（只给方向，飞机在到达前就转出本相位） |

样例（F-16 corner=700km/h）：`corner_ms=194 → min_turn_r=548m`；
`too_close < 822m`；`reentry = max(gun_range×1.3, 1370, 1500) ≈ 1500m`。
376m 的 SAM：`376 < 822` → **触发脱离而非绕圈**。

### 2.4 速度 / 高度 / 加力（按相位 × 姿态）

| 相位 | 姿态 | target_speed_kmh | AB | 高度 |
|---|---|---|---|---|
| SETUP | 通用 | `corner_speed_kmh` | 关 | ASSAULT: `tgt_alt`（保持低空对准）；STANDOFF: MID/偏好 |
| RUN | ASSAULT | `clamp(cruise×1.4, cruise, max×0.75)` | 当前 < 目标×0.95 时开 | **俯冲到 `tgt_alt`** |
| RUN | STANDOFF | `cruise×1.15`；**`dist < inner×1.6` 时预减速到 `corner`** | 关 | MID / 玩家偏好 |
| EGRESS | 通用 | **`corner_speed_kmh`（硬 break）** | 关 | ASSAULT: `tgt_alt`（低空脱离）；STANDOFF: MID/偏好 |

**EGRESS = corner speed 硬 break（sim 定案）**：早期用巡航高速拉开，转弯半径太大 → 头朝目标触发时
coast 冲进目标（STANDOFF sim min 562m）。corner 是最大转率/最小半径，收紧折返弧。

**EGRESS 方向按姿态（sim 定案）**：
- **ASSAULT**：径向背离 `-to_target_dir`（飞越后目标已在身后，径向≈机头，顺势拉开）。
- **STANDOFF**：**侧向 beam break** `(⟂LOS 朝机头偏侧 − 0.5·LOS) 归一` ——头朝目标触发 EGRESS 时，
  180° 径向反转要 coast 冲进 AA（head-on sim min 421m）；beam 只需 ~90-120° 转向，coast 小又开距。
- **RUN 预减速**：STANDOFF 逼近脱离环（`dist < inner×1.6`）预减速到 corner，使 break 弧更紧
  （高速进 break → 半径大 → coast）。realistic 偏轴进入 sim min 1168~1700m。

**ASSAULT 全程低空（sim 定案）**：早期 EGRESS/SETUP 爬回 MID → 高度 churn 永远打不到地面（sim min 4211m）。
改为 ASSAULT 全相位 `tgt_alt`——俯冲下去就贴地扫射/脱离/折返，不爬回（sim min 9m ✓）。

（玩家 `is_tactical_preference_user` 全程高度自治走 `altitude_preference`。）

## 3. 行为与公式（How）

### 3.1 Pass 状态机（一个 `Intent.GROUND_STRAFE`，rationale 区分相位）

phase 状态位 `strafe_pass_phase ∈ {SETUP=0, RUN=1, EGRESS=2}`，住 `Aircraft._strafe_pass_phase`，
经 Situation 读入、TacticalPlan 输出、`_apply_tactical_plan` 回写（与 `_bfm_prev_intent` 完全同款通道，纯函数不写 Aircraft）。

令 `aligned = aim_align ≥ TAIL_AIM_THRESHOLD`（cos，≈ 机头夹角 < 30°）。

```
                 aligned & dist≤outer
      ┌──────────────────────────────────────► RUN
 SETUP│                                          │ dist≤inner  (打完/飞越)
   ▲  │  (aim<TAA & too_close: 转不回来)          │  或 aim<TAA & too_close (贴脸丢准)
   │  └──────────────────────────────────────►  │
   │                    EGRESS ◄────────────────┘
   │                       │
   └───────────────────────┘  dist ≥ reentry_m  (拉够了 → 折返，SETUP 重新对准)
```

| 转换 | 条件 | 目的 |
|---|---|---|
| SETUP → RUN | `aligned`（C1：去掉 `dist≤outer` 门——远距对准也进 RUN 全速闭合，开火另由包络 `allow_*_fire` 把关） | 对准 → 闭合/开打 |
| SETUP → EGRESS | `not aligned` 且 `too_close` | **绕圈根治**：转弯圆吃不下目标，先拉开 |
| RUN → EGRESS | `dist_m ≤ inner_m`（飞越/到脱离内缘） 或（`not aligned` 且 `too_close`） | 打完一波 → 飞越脱离 |
| RUN → SETUP | `not aligned` 且 `not too_close` | 丢准但有空间 → 原地重新对准（不必拉远） |
| EGRESS → SETUP | `dist_m ≥ reentry_m` | 拉够距离 → 折返，SETUP 把头转回目标 |
| （EGRESS 保持） | `dist_m < reentry_m` | 提交外推，直到拉出 reentry（空间滞回，杜绝边界抖动） |

**相位切换与动作同帧**：读入 prev phase → 按几何算 next phase → **按 next phase 产出动作**（与 joust 同款，
不延迟一帧）。目标切换/丢失时 phase 由其它 intent 的默认 SETUP 重置（几何在 1~2 帧内自校正，可接受）。

**相位动作**：
- **SETUP**：`pursuit_pos = tgt_pos`，corner speed，关 AB。（几何上等于"朝目标转"，
  但因非 too_close，转弯圆能带到目标 → aim_align 会收敛。）
- **RUN**：`pursuit_pos = tgt_pos`（ASSAULT 与 STANDOFF **均为纯追踪**）。按 2.4 设速度/高度/AB。
  开火由既有 `_apply_combat_weapon` 设的 `allow_gun_fire / allow_missile_fire` +
  `update_gun/update_missile` 自理。
  **STANDOFF 不 crank（2026-07-26 定案，spec v5）**：曾用 `_missile_engage_pos(s)` crank 保锁，
  但 crank 稳态离轴 = `radar_half×0.5` 恰在发射窗口质量门（`radar_half×0.5(SARH)/0.55(f&f)`）
  外沿——SETUP 刚对准、一进 RUN 反被拧出发射门，UNSTABLE_WIN 永拒（log 20260726_165536：
  长机+僚机对 SAM/AAA 40s 离轴恒 21~31°、0 发）。静止面目标纯追踪 LOS 零旋转 → 机头收敛
  0 离轴即稳态，锁最快攒满、发射门必过；发射后保距由 F-Pole 环外等待接管（§aa-fire-awareness）。
  与慢速空目标终端纯追踪（slow-air pass）同病同修。
- **EGRESS**：`pursuit_pos = my_pos + (−to_target_dir) × EGRESS_OUT_PX`（**背离目标径向**，
  不是沿机头——STANDOFF 头朝目标触发时沿机头会穿过目标，实测 min 1m）；corner speed 硬 break（收紧半径）。
  纯函数无地图边界，不做 edge lerp；靠 reentry 折返避免飞出图（若 playtest 出现贴边飞出再注入 map 边界）。

### 3.2 与既有系统的关系

- **武器链零改动**：pass 只写 movement 契约 + phase。机炮锥门 / 导弹锁定 / 电磁炮充能全部
  由既有系统在"机头恰好对准"姿态下自然满足（与 joust 同理）。
- **规避永远压过 pass**：planner 优先级 1（EVADE_MISSILE）在 GROUND_STRAFE 之前 return；
  被导弹咬时先规避，规避完回 pass 循环（phase 保持，几何自续）。
- **武器竞选/姿态**：`_apply_combat_weapon` + `_apply_weapon_lock` 先跑，得 `weapon_mode` →
  推导姿态。玩家双击冲锋 / UI 锁机炮 → 强制 GUN → ASSAULT；出弹自动落 GUN → ASSAULT。
- **僚机横向偏移**：ASSAULT RUN 段沿用 `_apply_squad_lateral_offset`（多机同打一个地面目标错开进入线）。
- **hysteresis**：GROUND_STRAFE 已在 `_is_combat_intent` 集合内；pass 全程一个 intent，
  子相位切换不经 intent hysteresis（靠 3.1 的空间滞回带自稳）。

### 3.3 替换关系

本 spec 的机制**取代** `bfm_intent.ground_strafe` 现有的 SETUP/RUN/BREAK 三态实现
（重写同名函数）。导弹分支从"稳定推进保持锁定"直线怼上去，升级为 STANDOFF pass（会脱离折返）。
Apache 专用的 `aircraft_combat_tracking.update_combat_ground_attack`（`_strafe_state` 那套，
不经 planner）**不在本 spec 范围**，保持原状。

## 4. 结构与组成（Structure）

| 部件 | 角色 |
|---|---|
| `BfmIntent.ground_strafe(s)` | pass 状态机主体（重写）：解析姿态/包络/守卫 → 按 phase 产出 TacticalPlan |
| `Situation.strafe_pass_phase` / `.attack_posture` | 输入：读 `Aircraft._strafe_pass_phase`；`attack_posture` 本期恒 AUTO |
| `TacticalPlan.strafe_pass_phase` | 输出：本帧决定的下一相位，供回写 |
| `Aircraft._strafe_pass_phase` | 状态位存储（int，初值 SETUP=0） |
| `Aircraft._apply_tactical_plan` | 回写 `_strafe_pass_phase = plan.strafe_pass_phase`（与 `_bfm_prev_intent` 同处） |
| 常量组 | `TURN_G / REATTACK_MULT / REENTRY_MULT / REENTRY_FLOOR_M / INNER_FLOOR_M / STANDOFF_INNER_M / EGRESS_OUT_PX`，置于 bfm_intent（geo 常量）|

## 5. 验收标准（Acceptance / Litmus）

无头行为 sim `--bench=surface_pass`（真实物理步进 + planner 路径，模型同 test_joust）：**14/14 全绿**。

- [x] **绕圈根治（主）**：机炮 vs 贴脸 SAM（500m）——不再绕圈：70s 完成 **4** 个完整 pass
  （EGRESS→SETUP→RUN 循环），距离幅度 1121px（飞出再回，非定半径绕圈），最长连续 SETUP **10.2s**
  （合法 U 转弯，对照 bug 47s 死锁），出现真实机炮对准窗（nose≤10°∧进射程）。
- [x] **机炮 ASSAULT 俯冲**：贴地俯冲到 **9m** 扫射 + 脱离后拉起（高度幅度 4990m）。
- [x] **导弹 STANDOFF 保持距离**：全程 **100% MISSILE** + 最近 **1168m**（守住 standoff 不进近距 AA）
  + 最低高度 5000m（不俯冲）。
- [x] **病例2：远距 off-axis 对舰不外逃（场景 C）**：命令打 6.2km 对舰（弹程 16km）、初始背对 →
  SETUP 9.7s 收敛 RUN → 压入 6.2→**1.7km 开火**（不 flee 到 9km，max 仅 6845m，EGRESS 占比 28%）。
- [x] **默认姿态**：有导弹 → STANDOFF；无导弹 → ASSAULT（由武器竞选推导，单测覆盖）。
- [ ] **舰船同款**：对 NavalUnit（`tgt_is_surface`）行为与地面一致（sim 用裸 CombatUnit 代理已验证 surface 分支；生存实战待 playtest）。
- [x] **不自陷失速**：全程 target_speed 地板 ≥ corner speed（sim 未见失速）。
- [x] ~~已知 seam：不触碰 SEAM-013（crank 翻号）——STANDOFF 复用现成 `_missile_engage_pos` 连续 crank。~~
  **v5 废止**：STANDOFF RUN 已去 crank 改纯追踪（crank 稳态离轴钉在发射门外沿 → 永不出弹，见 §3.1）。
- [x] **必须真出弹（v5 新增，log 20260726_165536 回归）**：sim B（STANDOFF vs SAM）复刻实机发射门
  序列（包络→锥→锁→发射窗质量），首发 **3.2s**、45s 内 ≥2 发（修复前 0 发）；sim C（玩家长机
  `use_tactical_preference` 对 6.2km 舰）≥1 发（实测 9 发，修复前 0 发）。
- [x] **包络高度差门对面目标豁免（v5）**：`is_in_missile_envelope` 的"高度差>5000m 拒发"收窄为
  仅对空中目标——STANDOFF MID 上半带（>5000m）/玩家爬升偏好曾恒触此门 → 对地导弹无声永拒
  且随高度玄学复发。对空语义不变（`--bench=missile_env` 4/4 绿）。
- [x] 回归门：`--bench=surface_pass` 9/9 + `--bench=bfm_intent` 102/102 + `--bench=all` 18 项全绿。
- [x] i18n：无新增玩家可见 UI 文本（rationale 是 debug 日志，不走 tr）。
- [ ] 性能：生存模式 Sentinel + Lv5+ 压测 FPS 掉幅 < 15（纯几何 + 1 int 状态位，无新增每帧扫描；待 playtest 顺带确认）。
- [ ] 生存实战 playtest：指挥机炮打 SAM 观察循环手感 + 导弹机 standoff 手感。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 状态位管线（跟 `_bfm_prev_intent` 同款）
- [x] `Aircraft`：加 `_strafe_pass_phase: int = 0`（SETUP）
- [x] `Situation`：加字段 `strafe_pass_phase` + `attack_posture(=AUTO)`；`from_aircraft` 读 `ac._strafe_pass_phase`
- [x] `TacticalPlan`：加输出字段 `strafe_pass_phase`（默认 SETUP）+ phase 枚举 `SurfacePhase{SETUP,RUN,EGRESS}`
- [x] `Aircraft._apply_tactical_plan`：回写 `_strafe_pass_phase = plan.strafe_pass_phase`

### 阶段 2 — pass 状态机（重写 ground_strafe）
- [x] 常量组入 bfm_intent（§2.2/§2.3 全部数值）
- [x] 姿态解析：跑 `_apply_combat_weapon`（现成）→ 由 `weapon_mode` 定 STANDOFF/ASSAULT（attack_posture=AUTO 时）
- [x] 包络/守卫解析（`outer_m/inner_m/min_turn_r/too_close/reentry_m`）
- [x] 相位机（§3.1 转换表）+ 三相位动作（§3.1）；EGRESS = 背离径向 + corner 硬 break（无地图边界）
- [x] 速度/高度/AB 按 §2.4（sim 定案：EGRESS corner 硬 break、ASSAULT 全程低空）
- [x] rationale 打 `对面 SETUP/RUN/EGRESS [ASSAULT|STANDOFF] dist=.. r=..`

### 阶段 3 — 接线校验
- [x] planner 优先级 4（`tgt_is_surface → ground_strafe`）不变，仍在 EVADE 之后
- [x] 舰船（NavalUnit）走同路径（`tgt_is_surface` 已含）

### 阶段 4 — 测试 + 收尾
- [x] `test_bfm_intent.gd`：BREAK→EGRESS 命名 + 3 新单测（orbit_breaks_out / standoff_no_dive / reattack_loop）
- [x] `test_surface_pass.gd`（新，无头行为 sim，模型同 test_joust）：`--bench=surface_pass` 9/9
- [x] 更新 §7 锚点 + script-index / code-index；写 §8
- [ ] 生存模式 playtest（指挥机炮打 SAM）→ status → done
- [x] changelog `docs/changelogs/2026-07-07-surface-attack-pass.md`

## 7. 索引锚点（Where —— 落地 2026-07-07）

| 关注点 | 文件 · 符号 |
|---|---|
| pass 状态机主体 | `scripts/ai/tactical/bfm_intent.gd` · `ground_strafe` / `_surface_altitude` / `SURFACE_*` 常量组 |
| 姿态/相位输入 | `scripts/ai/tactical/situation.gd` · `strafe_pass_phase` / `attack_posture` / `POSTURE_*` |
| 相位输出 + 枚举 | `scripts/ai/tactical/tactical_plan.gd` · `SurfacePhase` / `strafe_pass_phase` / `surface_phase_name` |
| 状态位 + 回写 | `scripts/aircraft.gd` · `_strafe_pass_phase`（字段）/ `_apply_tactical_plan`（回写） |
| 单测 | `scripts/tests/test_bfm_intent.gd` · `test_surface_orbit_breaks_out` / `_standoff_no_dive` / `_reattack_loop`（`--bench=bfm_intent`） |
| 行为 sim | `scripts/tests/test_surface_pass.gd`（`--bench=surface_pass`，真实物理步进；bench_runner UNIT_TESTS 注册） |
| reference 索引行 | script-index.md（bfm_intent / situation / tactical_plan 行）、code-index.md（战斗追踪·对面攻击 pass 行） |
| changelog | `docs/changelogs/2026-07-07-surface-attack-pass.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-26 | 5 | **病例3 修复（log 20260726_165536，僚机+长机 STANDOFF 对 SAM/AAA 40s 0 发导弹）**：两道互相独立的"无声拒发"门叠加。①**crank 钉死发射门**：RUN[STANDOFF] 用 `_missile_engage_pos` crank，稳态离轴 `radar_half×0.5` 恰在发射窗质量门（`×0.5(SARH)/0.55(f&f)`）外沿 → SETUP 对准后一进 RUN 反被拧出发射门，UNSTABLE_WIN 永拒；每 20s 一轮 SETUP→RUN→EGRESS 空转。修：RUN[STANDOFF] 改**纯追踪**（与 slow-air 终端同修），发射后保距走 F-Pole 环外等待。②**包络高度差门**：`is_in_missile_envelope` "高度差>5000m 拒发"对面目标恒触（STANDOFF MID 上半带/玩家爬升偏好 → 高度落哪半带决定发/不发 = 玄学复发）。修：该门收窄为仅对空中目标。**回归加固**：sim B/C 新增"必须真出弹"断言（复刻实机发射门序列：包络→锥→锁→发射窗质量+冷却）——此前验收只断言运动几何、武器层从不在环内，正是 bug 反复穿过验收的原因。sim 32/32 + `--bench=all` 39 项全绿（missile_env 4/4 对空语义不变）。 |
| 2026-07-11 | 4 | **病例2 修复**（log 20260711_205142，命令打 6km 对舰 STANDOFF 绕圈背飞）：无头 sim 证明 SETUP 本身 9s 收敛，根因是 STANDOFF `inner` 误设远环 `missile_max×0.5` → 命令打环内目标一进 RUN 即 `dist≤inner` → EGRESS 外逃绕圈。修：①`inner` 改固定近距 `STANDOFF_INNER_M=2200m`（"别更近"语义，非"退到远环"）；②STANDOFF EGRESS 改**侧向 beam break**（原 180 径向反转 head-on coast min 421m）；③STANDOFF RUN 逼近脱离环预减速 corner（收紧 break 弧）。新增 sim 场景 C（6km 对舰 off-axis）作回归。sim 14/14 + bfm_intent 102/102 + all 18 绿。 |
| 2026-07-07 | 3 | 无头行为 sim（`--bench=surface_pass`，模型同 test_joust）暴露并修 3 处物理 bug：①ASSAULT 全程贴 tgt_alt 不爬回 MID（原高度 churn 打不到地面，sim min 4211m→9m）；②EGRESS 方向改**背离目标径向**（原沿机头，STANDOFF 头朝目标触发时穿过目标 min 1m）；③EGRESS 用 **corner 硬 break** 收紧半径 + STANDOFF 改**远距 standoff 环脱离**（原近环 180 coast 冲进 AA，min 156→1395m）。sim 9/9 + bfm_intent 102/102 + all 18 项绿。 |
| 2026-07-07 | 2 | 实现前自审修 3 处数值 bug：C1 SETUP→RUN 去掉 `dist≤outer` 门（远距对准也全速闭合）；C2 加包络有效性守卫 `inner=min(inner, outer×0.6)`（防短射程 AGM 反向带宽死锁）；C3 reentry 分姿态、去掉 `outer×1.3`（STANDOFF outer=8km 会算出 10km 折返）。status → in-progress。**全量落地**：plumbing 4 处 + ground_strafe 重写 + 3 新单测；`--bench=bfm_intent` 102/102 绿。差生存 playtest。 |
| 2026-07-07 | 1 | 初稿。用户拍板：地面/舰船专用俯冲 pass 循环；导弹机炮共用骨架，姿态 STANDOFF/ASSAULT 分流，默认"有弹保持距离/无弹机炮"。根因 = 现 ground_strafe 缺最小转弯半径守卫（空中侧 planner 5.9 已有、地面被 `not tgt_is_surface` 排除）。 |
