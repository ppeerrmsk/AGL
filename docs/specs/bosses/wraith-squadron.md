---
id: wraith-squadron
kind: boss
status: done
schema_version: 1
spec_version: 8
owner: 用户（设计） / Claude（落地）
depends_on: [ace-squadron-tier, circle-cut-entry, boss-clear-progression, enemy-sensor-stealth]
reconstruction_complete: false
---

# WRAITH 中队（F-47 王牌狙击小队）

> 四架幽灵一样的六代机。它们不跟你比谁转得快 —— 它们**逼你转弯，然后惩罚你转弯**。
> 你会一直觉得"再有一点点就赢了"，然后发现自己已经掉到 3000 米以下、没有能量、被两个方向夹住。

## 1. 设计意图（Why）

### 1.1 目标：本作最强敌人之一

**"最强"不来自数值。**[ace-squadron-tier](../systems/ace-squadron-tier.md) 已经把这条钉死：
王牌中队不堆血、不堆护甲、不做等级缩放。Wraith 的强度必须来自**四架飞机作为一个整体的协同**。

具体来说，它强在四件事上：

1. **两难困境**：骑士组逼你进近距缠斗，狙击组惩罚你进近距缠斗。转身打骑士 → 狙击组拿到导弹解算；
   冲向狙击组 → 骑士组咬住你六点。**没有一个方向是安全的**，这是压力的真正来源。
2. **能量优势**：他们从高位进入，并在每次交战重置时重新爬回高位。你永远在仰头看他们。
3. **不会陷入退化状态**：一旦战斗退化成"共速绕圈"（谁也咬不住谁），他们**主动脱离重整**，
   而不是陪你磨到天荒地老。这既是战术，也是防止 playtest log 20260720_172222 那种绕圈重现的设计保险。
4. **导弹不是答案**：4 枚热诱弹 = 4 条命（tier spec §2.2），你必须打空它们的防御才能开始真正的击杀。

### 1.2 但它必须会犯错

用户定档：**执行精度失误**（不是战术决策失误）。他们的**判断永远正确，但手不是完美的** ——
瞄准会偏、减速会晚、过头会冲出去。这保证：

- 玩家的胜利来自**抓住失误的瞬间**，而不是等 AI 犯傻
- 强度可调：调失误幅度就能调难度，不用动战术层
- 观感上"这是四个很强的飞行员"，而不是"这是四个机器人"

### 1.3 Litmus 自检

- **单杠杆**：难度只有一个总旋钮 = 执行误差幅度。战术层不做难度分级。
- **效果即反馈**：包夹的两难是**空间可见**的（你能看到两侧有人切进来），不需要 HUD 提示。
- **不做二阶机制**：不加狂暴阶段、不加血量阈值转换、不加特殊技能条。

### 1.4 反模式规避

- ❌ **不做"完美 AI + 人为掷骰子放水"**。失误必须是执行层的物理偏差，不是"这次判定我们故意不开火"。
- ❌ **不靠数值碾压**。见 tier spec §1.4。
- ❌ **不做脚本化演出战斗**（"第 30 秒必定包夹"）。战术由态势触发，玩家的动作能改变它。

## 2. 数据定义（What）

### 2.1 编制与角色

四机菱形进入，**spawn 时静态分配角色，运行时不变**：

| # | 呼号 | 角色 | 主武器 | 职责 |
|---|---|---|---|---|
| 0 | WRAITH-01 | **KNIGHT**（骑士） | 机炮 | 长机。近距缠斗，逼玩家进入转弯 |
| 1 | WRAITH-02 | **KNIGHT** | 机炮 | 同上；BRACKET 时默认担任 BAIT |
| 2 | WRAITH-03 | **SNIPER**（狙击手） | 导弹 | 远距站位，惩罚玩家的每一次承诺 |
| 3 | WRAITH-04 | **SNIPER** | 导弹 | 同上 |

> ✅ 已落地（2026-07-22）：`AceSquad.AceRole { NONE, KNIGHT, SNIPER }` + `ROLE_META` +
> `role_of()`。此前的 `combat_specialty`（只写不读）与 `f47_role`（只读不写）两个死 meta
> 已删除；`is_boss_attacker()` 的兜底分支与 HUD 标签都改读真正被写入的角色字段。

### 2.2 角色行为参数

| 参数 | KNIGHT | SNIPER | 说明 |
|---|---|---|---|
| 期望交战距离 | 400~1500 m | **4000~6000 m** | SNIPER 被压到 4km 内即视为站位失败，需拉开 |
| 主武器 | 机炮 | 导弹 | `prefer_gun_mode` |
| 高度偏好 | 与玩家同层 | 玩家 **+1500 m** | SNIPER 常驻高位 |
| 交战欲 `aggression` | 0.95 | **0.95** | 见下方"与 tier 的冲突裁决" |
| 自保 `self_preservation` | 0.15 | **0.25** | 同上 |
| 被咬时行为 | 转身对抗 | **拉开，交给 KNIGHT 反咬** | 靠 BVR 站位机制实现，不靠调低交战欲 |

**与 tier 的冲突裁决（2026-07-22）**：本表 v1 给 SNIPER 写的是 `aggression 0.75` /
`self_preservation 0.35`，与 [ace-squadron-tier](../systems/ace-squadron-tier.md) §2.1 的
tier 级铁律（`aggression ≥ 0.90`、`self_preservation ≤ 0.25`）直接冲突，而本 spec §2.5 又
声明"不覆盖 tier"。裁决：**tier 赢**。

理由是"SNIPER 不贪战"这个设计意图本来就**不该由交战欲实现** —— 调低 aggression 会让它
在**所有**情境下都消极（包括该开火的时候），这正是 tier 想禁止的"BOSS 不上头"反面。
真正要的是**空间行为**："被压近了就拉开"。这由 BVR 站位机制表达（低于 4000 m 强制脱离、
拉到 6000 m 重新站位），与交战欲正交 —— SNIPER 因此既保持 tier 级的攻击欲，
又严格守住自己的距离带。

### 2.3 队级战术状态机数值

| 状态 | 时长 / 退出条件 | 关键数值 |
|---|---|---|
| **PERCH**（建立高位） | 高度差 ≥ 1500 m 或 12 s 超时 | 目标高度 = 玩家 + 2000 m |
| **BRACKET**（诱敌包夹） | BAIT 被咬 ≥ 4 s，或 20 s 超时 | BAIT 拉开距离 3000 m；包夹两翼分离轴 **≥ 60°** |
| **PRESS**（压制） | 15 s，或退化检测触发 | KNIGHT 进 1500 m；SNIPER 保持 4~6 km |
| **RESET**（重整） | 8 s | 全队 EXTEND 拉开至 ≥ 3000 m + 爬升，然后回 PERCH |

**退化检测（RESET 的核心触发器）**：
全队**平均机头偏角 > 50° 持续 6 s** → 判定为"共速绕圈，谁也咬不住谁" → 强制 RESET。
这是对 log 20260720_172222 那类死锁的结构性防御。

### 2.4 执行精度失误模型

三项，全部是**物理层偏差**，不是决策层放水：

| 失误 | 数值 | 说明 |
|---|---|---|
| **瞄准误差** | 每个梭起手 `±1.2°` 随机偏置 | 王牌飞行员技能 0.85 → `lerp(5.0°, 0.5°, 0.85) ≈ 1.2°` |
| **机动瞄准惩罚** | 自身 bank > 30° 时最多 +2.0°；目标 bank > 60° 时最多 +1.5° | 与玩家侧同公式 |
| **减速迟滞** | 每次进入近距 pass 时，**25% 概率**延迟 `0.6~1.2 s` 才开始减速 → 冲过头 | 制造可被玩家利用的过头窗口 |

> ✅ 已落地（2026-07-22）：瞄准误差与机动惩罚此前被 `use_tactical_preference` 门死
> ——那是个"玩家有战术偏好面板"的**操控模式**标志，与枪法毫无关系，兼任的后果是
> 全部 AI 敌机（含 BOSS）永远打一个完美居中的散布锥。现已拆出独立开关
> `Aircraft.gun_aim_error_enabled`，由 `AceTier.mark()` 在打 tier 标记时一并开启并写入
> `pilot_aim_skill = 0.85`。减速迟滞落在 `EngagementSpeedGovernor.apply_with_lag()`
> （该模块本就只对王牌中队生效）。

### 2.5 与 tier 的关系

血量 / 热诱弹命数 / 不吃 LOD / 无等级缩放 / 隐形，**全部继承 [ace-squadron-tier](../systems/ace-squadron-tier.md)**，
本 spec 不重复定义，也不覆盖。本 spec 只管**战术与角色**。

### 2.6 通关强化支援

历史击败数为 0 时仍为原四架 F-47。历史击败数 ≥1 时，在正式接战而非登场演出阶段追加两架
YF-23 `BLACKWIDOW-01/02` 远距支援：在 Wraith 队形后方成对潜伏、保持 4–6 km 距离带；不具备永久免锁，
但启用传感器隐形，只有维持有效雷达接触时才可按普通飞机规则锁定；不进入 Wraith
`members/all_members`、不进入 BOSS 血条且不阻塞胜利。完整机体数值、出生几何与结算边界由
[boss-clear-progression §2.2](../systems/boss-clear-progression.md) 定义；第二强化层暂不追加机制。

### 2.7 双层隐形与目标释放

- 四架 F-47 本体与强化层 YF-23 均显式开启 [enemy-sensor-stealth](../systems/enemy-sensor-stealth.md)：光学隐身窗外，脱离全部有效玩家小队雷达照射且处于全部玩家机 1000px 外满 5.0s 后才丢失接触。YF-23 没有永久锁定免疫；被有效雷达照射或进入 1000px 近距圈即显形，建立接触后仍按普通飞机规则可锁定。
- 原有 5.5s 周期光学隐身不被替换，但节奏削弱为：开战后先等 60.0s，使用结束后再进入严格 60.0s CD，CD 完成可重复使用；取消来袭导弹绕过 CD 的紧急触发。淡入/淡出各 1.0s。
- 当前操控玩家机进入任一 Wraith 成员 1000px（2000m）内时，全队光学 cloak 不得启动；若已启动则提前结束并显形。传感器隐形与 `is_cloaked` 分别持有生命周期和透明度，重叠时除该近距揭露规则外不得互相覆盖。
- 任何一层进入隐形时，所有存活玩家小队成员对该 F-47 的 `combat_target`、主雷达锁和副雷达锁必须立即释放。
- 光学短窗保留既有 `commanded_target` 指针，显形后自动重接；传感器硬失联清除该点名。两者都不得影响 Wraith 自身对玩家的目标。
- 保留点名不等于保留火控：所有玩家小队 `combat_target` 写入入口必须拒绝隐形 Wraith，防止 RTS 命令铁律在下一 tick 把点名重新挂回。
- 左下雷达盘在两种隐形期间都继续显示低亮度匿名位置提示，帮助玩家追索；该提示不恢复世界模型、目标数据、锁定或武器制导。

## 3. 行为与公式（How）

### 3.1 队级状态机

```
        ┌──────────────────────────────────────────┐
        ↓                                          │
   [PERCH 建立高位] ──高度差达标/超时──> [BRACKET 诱敌包夹]
        ↑                                          │
        │                              BAIT 被咬 / 超时
        │                                          ↓
        └────── 8s 后 ────── [RESET 重整] <── [PRESS 压制]
                                  ↑                │
                                  └── 退化检测 ────┘
                                      (平均机头偏角 >50° 持续 6s)
```

进入战斗（tier 的 PURSUIT）后即进 PERCH。四个状态循环，**没有终止态** —— 战斗结束只因为有人死。

### 3.2 BRACKET（诱敌包夹）—— 本 BOSS 的签名战术

这是用户点名的"利用有人拉远距离并吸引火力，其他人趁机包夹"：

1. **指定 BAIT**：默认 WRAITH-02（KNIGHT）。若它已阵亡，顺位取存活的 KNIGHT，再取 SNIPER。
2. **BAIT 行为**：朝玩家方向做一次高可见度的接近，然后转向拉开至 3000 m，**保持在玩家雷达锥内**
   （诱饵必须看起来是能吃下的猎物）。BAIT **不开火** —— 它的任务是被追。
3. **其余三机**：分成左右两翼切入，两翼与"玩家→BAIT"轴线的夹角 **≥ 60°**（Shaw 的 bracket 几何）。
   分离轴不足 60° 时视为包夹失败，重新分配。
4. **收网**：玩家一旦咬住 BAIT ≥ 4 s，两翼同时进入攻击 → 转 PRESS。

**为什么是 60°**：小于这个角度，两翼实际上在同一侧，玩家一个转弯就能同时规避；
≥60° 时玩家的任何转向都会把六点交给另一侧。这是让包夹**成为真两难**的最小几何条件。

### 3.3 PERCH（高度优势）

目标高度 = 玩家高度 + 2000 m，全队爬升。达到 1500 m 高度差即视为建立完成。

**为什么高度是优势**：本作高度是虚拟数值，但俯冲/爬升影响速度（`dive_speed_ratio` /
`climb_speed_ratio`）。高位意味着可以用势能换速度发起攻击，攻击失败后又能爬回去。
这让 Wraith 在每一轮交换中都握有能量主动权。

### 3.4 RESET（重整）与退化检测

**这是防止"绕圈"重现的结构性保险**，与 `EngagementSpeedGovernor`（几何层）互补：
治理层保证他们**能**咬住目标，RESET 保证他们在**咬不住时不会傻转**。

判定：每 0.5 s 采样全队存活成员对当前目标的机头偏角，取平均；
连续 6 s 平均 > 50° → RESET。RESET 期间全队 EXTEND 至 ≥3000 m 并爬升，8 s 后回 PERCH。

### 3.5 角色行为差异（取代死掉的 combat_specialty）

角色必须是**被真正消费的字段**，至少影响三处：

| 消费点 | KNIGHT | SNIPER |
|---|---|---|
| 期望交战距离（战术层站位） | 400~1500 m | 4000~6000 m |
| 武器竞选偏好 | 机炮优先 | 导弹优先 |
| 被咬时的反应 | 转身对抗 | 拉开脱离 |

### 3.6 执行失误的注入位置

| 失误 | 注入层 |
|---|---|
| 瞄准误差 / 机动惩罚 | 机炮开火路径（现有玩家侧误差通路，对王牌中队开门） |
| 减速迟滞 | 近距 pass 的减速决策点 |

**禁止**：在战术决策层加随机（"这次不包夹了"）。失误只发生在**执行**上。

## 4. 结构与组成（Structure）

- **队级战术状态机**住在独立模块 `WraithTactics`，由 `F47AceSquad` 持有并转发 ——
  按用户决定是 **Wraith 专属窄井**，不下沉为通用小队战术模块。若后续有第二个王牌中队
  需要同样的编排，再考虑抽取。
  基类 `AceSquad` 只提供三个空钩子（`_tactics_enter/update/exit`），不实现任何 Wraith 逻辑：
  其它王牌中队不覆写就退化为"各自跑 BFM"的现状行为，零影响。
- **相位与 AI 层的分工**（本层的硬约束）：本层**不每帧覆盖 AI 字段**，只在相位切换时下一次配置。
  - 需要"走到某个位置"（PERCH 爬升 / BAIT 拉开 / RESET 脱离）→ 下 `AIDirective`
  - 需要"从某个方位打进来"（BRACKET 两翼）→ 写包围轴 `surround_bearing`，
    由 `TacticalPlanner` 执行"先飞到自己扇区的进入门点、近于 1500 m 解除偏置收敛"——
    **全程真实转弯**，绝不直接挪坐标
  - **PRESS 相完全不干预**，撤掉一切 directive 与偏置，让 BFM 决策树自己打
- **包围轴通道的复用**：`surround_bearing` 原为命令轮盘 FOCUS 集火（相邻 ≥45°）而建，
  与本 spec 的包夹是同一个几何概念，故复用而非另造。`Situation` 侧原本以
  `commanded_target != null` 为读取门（那是玩家点名专用，敌机没有），
  为王牌中队开了一个窄口子：`tier == ace` 时同样读取，仍以 `INF` 作"未分配"哨兵。
- **角色字段**：取代 `combat_specialty`（只写不读）与 `f47_role`（只读不写），两者都要删。
- **战术状态机**与 tier 的 `AceSquad.SquadState`（INTRO/PURSUIT/CLOAK）是**两层**：
  tier 层管"是否交战 / 是否隐形"，本 spec 的战术层在 PURSUIT 之内运转。
  进 CLOAK 时战术层整个撤场（撤 directive + 清包围轴），回 PURSUIT 时从 PERCH 重新起手 ——
  否则隐形期间四机还在执行上一相的站位，出隐形时相位与实际脱节。
- **依赖** `EngagementSpeedGovernor`：没有它，任何战术都执行不了（半径 > 距离时机头指不到目标）。
- **依赖** [circle-cut-entry](../systems/circle-cut-entry.md)：PRESS 阶段的收网执行层 ——
  KNIGHT 把玩家拖进转弯圈后，另一架从圈外横切收网走该共享几何，本 spec 不重复实现。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **角色可辨**：观察 60 s，KNIGHT 平均交战距离 < 2000 m，SNIPER > 3500 m，两组不混。
- [ ] **包夹成立**：BRACKET 触发时，两翼与"玩家→BAIT"轴的夹角 ≥ 60°；玩家咬住 BAIT 后 4 s 内两翼进入攻击。
- [ ] **诱饵不开火**：BAIT 在诱敌阶段全程不开火。
- [ ] **高度优势**：PERCH 结束时全队高度 ≥ 玩家 + 1500 m。
- [ ] **不再绕圈**：整场平均机头偏角 < 35°；连续 6 s 平均 > 50° 时必定触发 RESET（可从日志验证）。
- [ ] **会失误**：机炮命中率明显低于 100%；能观察到过头（overshoot）后被玩家反咬的窗口。
- [ ] **失误只在执行层**：日志中不存在"本可包夹但随机放弃"的决策记录。
- [ ] **战术有变化**：60 s 内至少经历 2 个不同的队级战术状态。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（见 performance-guidelines）
- [ ] 已知 seam 未触碰 / 已妥善处理（见 architecture/known-seams.md）
- [ ] i18n：玩家可见文本走 tr()，三语已补（见 reference/i18n.md）
- [x] 初见不生成额外支援；首败后接战在 Wraith 队形后方生成两架启用传感器隐形、接触建立后可正常锁定的 YF-23，且不参与演出、血条或胜利判定
- [x] 四架 F-47 与两架 YF-23 均开启传感器隐形；传感器/光学任一隐形沿都立即清除所有玩家小队成员的 `combat_target`，且光学显形后点名可自动重接
- [x] Wraith 光学 cloak 开战后 60s 才首次可用；每次结束后严格等待 60s 可再次使用，导弹来袭不能提前触发
- [x] 任一玩家小队成员进入目标 1000px 内时传感器隐形立即揭露；当前操控玩家机进入任一 Wraith 1000px 内时光学 cloak 禁止启动或提前结束；左下雷达在隐形期间保留匿名位置提示
- [x] 光学短窗保留的 `commanded_target` 在隐形中不能被任何 RTS/AI 路径重写为 `combat_target`，显形后才自动重接

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 角色真实化（清死代码）✅ 2026-07-22
- [x] 定义被真正消费的角色字段，取代 `combat_specialty` / `f47_role`
      （`AceSquad.AceRole` + `ROLE_META` + `role_of()`）
- [x] 删除两个死 meta 及其悬空读（`is_boss_attacker` 里的 `f47_role` 分支、HUD 的读取）
- [x] 角色接入三个消费点（交战距离 / 武器偏好 / 被咬反应）
- [x] 无头断言：KNIGHT 与 SNIPER 的距离带分离（`--bench=boss_hunter` §C）

### 阶段 2 — 队级战术状态机 ✅ 2026-07-22
- [x] PERCH / BRACKET / PRESS / RESET 四状态 + 转移条件（独立模块 `wraith_tactics.gd`）
- [x] 退化检测（平均机头偏角 > 50° 持续 6 s，0.5s 采样）
- [x] BAIT 指定与继任顺位（默认二号机 KNIGHT → 存活 KNIGHT → SNIPER）
- [x] 包夹几何：两翼分离轴 ≥ 60° 的分配与校验（复用 `surround_bearing` 包围轴通道）
- [x] 无头断言：`--bench=boss_hunter` §H/§I（包夹几何左右分侧且 ≥60°、四相闭环、
      收网需咬住 4s、退化必触发 RESET）

### 阶段 3 — 执行精度失误 ✅ 2026-07-22
- [x] 机炮瞄准误差通路对王牌中队开门（技能 0.85 → ±1.2°）
- [x] 机动瞄准惩罚同步开门（与 §1 共用 `gun_aim_error_enabled` 一个开关）
- [x] 减速迟滞（25% 概率延迟 0.6~1.2 s，落在 `EngagementSpeedGovernor.apply_with_lag`）
- [x] 无头断言：`--bench=boss_hunter` §F/§G（开关默认关 / tier 标记开门 / 迟滞锁存与解除）
- [ ] 命中率对比测量（无误差基线 vs 现状 vs 杂兵）—— 需 playtest 数据，不能靠断言假设

### 阶段 4 — 收尾
- [ ] 跑 §5 全部验收项 + playtest
- [x] 更新 §7 锚点 + 同步 reference 索引 + `_INDEX.md`
- [x] 跑 `python tools/verify_doc_anchors.py`

## 7. 索引锚点（Where）

<!-- 实现落地后填写 -->

| 关注点 | 文件 |
|---|---|
| 角色枚举 / `ROLE_META` / `role_of()` / `_apply_role` | `scripts/survivor/ace_squad.gd` |
| tier 基座 + 王牌枪法与误差开关的落地点 | `scripts/survivor/ace_tier.gd` |
| 队级战术状态机（PERCH/BRACKET/PRESS/RESET + 退化检测） | `scripts/survivor/wraith_tactics.gd` |
| 战术层持有与转发（`_tactics_enter/update/exit` 钩子实现） | `scripts/survivor/f47_ace_squad.gd` |
| 通关强化 YF-23 支援生成/玩家重定向 | `scripts/survivor/f47_ace_squad.gd` · `resources/enemy_yf23.tres` |
| 战术层钩子的基类虚方法 | `scripts/survivor/ace_squad.gd` |
| 包夹的包围轴执行端（进入门点 → 近距收敛） | `scripts/ai/tactical/tactical_planner.gd`、`scripts/ai/tactical/situation.gd` |
| 速度治理（前置依赖）+ 减速迟滞 | `scripts/ai/tactical/engagement_speed_governor.gd` |
| 机炮误差通路（两处门） | `scripts/aircraft/aircraft_weapons.gd` |
| 误差开关字段 `gun_aim_error_enabled` | `scripts/aircraft.gd` |
| 角色驱动的 `is_boss_attacker()` 兜底 | `scripts/ai_controller.gd` |
| HUD 角色标签（只显示行为，不暴露角色代号） | `scripts/survivor/survivor_hud.gd` |
| F-47 传感器开关 / 隐形沿目标释放 / 双层尾迹所有权 | `resources/enemy_f47.tres` · `scripts/survivor/sensor_stealth_controller.gd` · `scripts/survivor/ace_squad.gd` · `scripts/aircraft.gd` |
| 王牌专属热诱弹资源 | `resources/ace_flare.tres` |
| 无头断言（`--bench=boss_hunter`） | `scripts/tests/test_boss_hunter.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-22 | 8 | 实战可读性削弱：Wraith cloak 改为可重复但每次结束后严格 60s CD（首次也等 60s，取消紧急提前触发），1000px 内禁止/打断光学隐身，光学渐变 1.0s；传感器隐形改为 5s 失联并同样近距揭露；左下雷达保留匿名提示，目标写入权威堵住隐身中 combat_target 重挂。 |
| 2026-08-21 | 7 | 用户追加 YF-23 隐形并反馈隐形沿顿卡：YF-23 开启传感器隐形但不恢复永久免锁；F-47 四机同步光学隐形改为一次批量清理玩家观察者，登场导演演员由虚拟环境所有权隔离。 |
| 2026-08-21 | 6 | F-47/Wraith 纳入敌机传感器隐形首批；保留原周期光学隐身。两层任一隐形沿立即释放全体玩家机 `combat_target` 与雷达锁；光学短窗保留点名供显形重接，传感器硬失联清点名；YF-23 支援保持普通可锁定。 |
| 2026-08-18 | 5 | 根据实战反馈修正通关强化 YF-23：取消永久免锁，改为正常可锁定；生成位置改到 Wraith 队形后方，并设离玩家 5000 px 的最小安全距离，不再在玩家机头前附近突然出现。 |
| 2026-08-01 | 4 | 接入 BOSS 通关强化层：首败后在正式接战阶段追加两架雷达静默 YF-23 远距狙击支援；支援不进入演出、BOSS 血条或胜利判定，第二强化层暂不扩展。 |
| 2026-07-22 | 3 | **阶段 2 落地**：队级战术状态机 `WraithTactics`（独立模块，F47AceSquad 持有转发；基类只留三个空钩子）。PERCH（爬到玩家+2000m 档、高度差 1500m 或 12s 超时）→ BRACKET（BAIT=二号机不开火、拉到玩家机头前方 3000m 保持在雷达锥内，三翼经 `surround_bearing` 从 ≥60° 离轴方位切入，咬住 4s 收网或 20s 超时）→ PRESS（15s，完全放手给 BFM）→ RESET（8s 脱离 3000m + 爬升，`combat_disabled=false` 脱离是几何行为不是缴械）→ 回 PERCH。退化检测 0.5s 采样、平均机头偏角 >50° 持续 6s 强制 RESET。**包夹复用命令轮盘的包围轴通道**（同一几何概念，不另造），为此在 `Situation` 给 tier=ace 开了窄读取口。顺带修 `_pursuit_enter` 无脑置 `bvr_only=false` 会抹掉 SNIPER 站位带的 bug。`--bench=boss_hunter` 97 断言 + 回归门 34 项 PASS |
| 2026-07-22 | 2 | **阶段 1 + 阶段 3 落地**。角色真实化（`AceRole{KNIGHT,SNIPER}` 取代两个死 meta，KNIGHT 转身对抗 / SNIPER `bvr_only` 站位带 4~6km）；执行失误落地（拆出 `gun_aim_error_enabled` 开关根治"敌机零瞄准误差"、王牌枪法 0.85 → ±1.2°、减速迟滞 25%×0.6~1.2s）。**冲突裁决**：§2.2 原给 SNIPER 的 `aggression 0.75`/`self_preservation 0.35` 违反 tier §2.1 铁律，判 tier 赢 —— "不贪战"改由 BVR 站位（空间行为）表达，不靠调低交战欲。阶段 2（PERCH/BRACKET/PRESS/RESET）仍未动 | 
| 2026-07-20 | 1 | 初稿。目标=本作最强敌人之一，强度来源定为**四机协同的两难**而非数值。角色 KNIGHT×2/SNIPER×2 真实化（取代两个死 meta）；队级战术 PERCH→BRACKET→PRESS→RESET 四状态 + 退化检测；执行精度失误三项（用户定档"执行失误"而非"决策失误"）。范围=Wraith 专属窄井（用户定档） |
