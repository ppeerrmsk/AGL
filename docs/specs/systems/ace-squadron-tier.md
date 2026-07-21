---
id: ace-squadron-tier
kind: system
status: in-progress
schema_version: 1
spec_version: 2
owner: 用户（设计） / Claude（落地）
depends_on: []
reconstruction_complete: false
---

# 王牌中队分层标准（Ace Squadron Tier）

> 战场上会出现一类"和杂兵不是一个物种"的敌人。它们不会因为你飞远了就变傻，
> 咬住你就不松口，并且**每一枚热诱弹都是它的一条命** —— 弹尽之时，即是坠机之刻。

## 1. 设计意图（Why）

### 1.1 体验目标

**王牌中队**要让玩家在**看到它的瞬间**就明白"这个不一样"，且这种差异必须来自**行为**而非血条。
AGL 的普通飞机遵守"导弹一击必杀"铁律 —— 这条铁律**不为王牌中队破例**，破例的是
**它有办法让你的导弹打不中它**。

由此得出本 tier 的核心机制：

> **热诱弹 = 命数。**每枚热诱弹**必定**骗掉一枚导弹；热诱弹耗尽，防御归零。

这条设计的好处是**读数清晰**：玩家不需要 HUD 中介，只要数"我已经被骗掉几发导弹"，
就知道对方还剩几条命。击杀过程从"磨血条"变成"拆掉它的防御手段"。

**击杀序列（4 命 + 100 HP 推导，2026-07-20 用户定档）**：

| 第 N 发导弹 | 结果 |
|---|---|
| 1~4 | 必定被热诱弹骗飞（命数 −1） |
| 5 | 命中。最强玩家导弹 AGM-65（90 伤）也打不死 100 HP → **必定进残血** |
| 6 | 必定击坠 |

即"**4 次骗弹 → 1 次残血 → 坠机**"。残血那一格是刻意留的：它把击杀从瞬时事件变成一个
玩家能看见的濒死状态（冒烟的王牌还在拼命咬你），也给机炮补刀留出空间。
注意这与早期草稿"耗尽即必死"不同 —— 100 HP 高于全部玩家导弹伤害，故耗尽后仍需两发。

### 1.2 分层定义

| 概念 | 定位 | 关系 |
|---|---|---|
| **王牌中队**（Ace Squadron） | 宽泛类别：战斗机里最强的一档。生存模式中途定期登场的强敌 / 中 BOSS | 上位概念 |
| **BOSS** | 王牌中队的**子集**：更强 + 专属演出 + 击败即关卡结束 | 下位概念，⊂ 王牌中队 |

**每一个 BOSS 都是王牌中队；不是每一个王牌中队都是 BOSS。**

### 1.3 Litmus 自检（引 DESIGN_PHILOSOPHY）

- **单杠杆**：王牌中队的生存能力只有**一个**杠杆 —— 热诱弹存量。不叠护甲 / 不叠血量 /
  不加闪避概率 / 不加伤害减免。想让某个王牌更耐打，只调这一个数。
- **效果即反馈**：热诱弹生效时导弹明显被骗飞，这就是反馈本身。**不加"剩余命数"HUD 元素**。
- **确定性优于概率**：每枚热诱弹**必定**成功（见 §3.3）。玩家投入的每一发导弹都有确定回报
  —— 要么消耗对方一条命，要么击杀。杜绝"打了 6 发全被随机骗掉"的挫败。

### 1.4 反模式规避

- ❌ **不靠堆血**。王牌中队的 `max_hp` 与普通精英机同级，`armor` 恒为 0。
- ❌ **不加隐藏减伤 / 闪避骰子**。生存全部来自可观察的防御动作。
- ❌ **不做等级缩放**。王牌中队按满级玩家平衡，固定参数（避免"越打越肉"的消耗战）。
- ❌ **不做二阶机制**（护盾档位 / 阶段转换 / 狂暴计时）。playtest 证明必要再补。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 Tier 准入门槛（王牌中队必须全部满足）

| 字段 | 值 | 说明 |
|---|---|---|
| `tier` meta | `"ace"` | tier 标记。BOSS 额外带 `category = "boss"` |
| LOD 冻结 | **豁免** | 离屏 / 远距不冻结 `_physics_process`、不降 AI 频率 |
| `skip_far_cleanup` | `true` | 不被远距清理回收 |
| 等级缩放 | **无** | `hp_mult = 1.0`、`missile_add = 0`、`gun_damage_mult = 1.0` |
| `aggression` | ≥ 0.90 | 极高攻击欲 |
| `engage_duration` | 999.0 | 永不自动脱离交战 |
| `engage_cooldown` | ≤ 0.5 | 几乎无冷却 |
| `self_preservation` | ≤ 0.25 | 低自保，杀玩家优先 |
| `skill_level` / `composure` / `focus` / `situational_awareness` | ≥ 0.90 | 王牌级操作 |
| `armor` | 0.0 | 恒为 0，本 tier 不使用护甲轴 |
| 机炮 | 专属 `ace_gun.tres` | 不共享 `default_gun.tres`（见 §2.4 与 §4.2） |

### 2.2 生存模型 —— 热诱弹即命数

| 字段 | 王牌中队 | 普通敌机（对照） | 说明 |
|---|---|---|---|
| `max_flares` | **4** | 1 | 整场 4 条命 |
| `burst_count` | **1** | 1 | 每次投放 1 枚 → 1 枚 = 1 条命，严格对应 |
| `cooldown` | 1.2 s | 1.2 s | 两次投放最小间隔 |
| `reload_time` | — | — | **不适用**：`enable_flare_reload = false`，耗尽永不补充 |
| 干扰成功率 | **1.00**（必定成功） | 见 `FlareParams` 概率模型 | 见 §3.3 |
| 投放距离 | **400 m** | 240 m | `nervousness = 0.5` → `lerp(200, 600, 0.5)` |
| 耗尽后行为 | **不解锁规避机动**，下一发导弹必定命中致死 | — | 见 §3.4 |

### 2.3 血量（例外条款）

普通飞机遵守"导弹一击必杀"（`ENEMY_HP_MISSILE_CAP = 75.0`，低于最弱玩家导弹 80 伤害）。
**王牌中队是这条铁律的显式例外** —— 豁免该 cap，但只豁免到"残血"的程度：

| 字段 | 值 | 推导 |
|---|---|---|
| `ENEMY_HP_MISSILE_CAP` | 王牌中队 **豁免** | 例外必须显式写在代码里，不靠数值擦边 |
| 王牌中队 `max_hp` | **100.0** | 70（原值）+ 30。2026-07-20 用户定档 |

**热诱弹耗尽后**被各类玩家导弹命中的结果（100 HP）：

| 玩家导弹 | 伤害 | 剩余 | 结果 |
|---|---|---|---|
| QMAAM | 70 | 30 | 残血 |
| MRM（默认） | 80 | 20 | 残血 |
| AGM-65 | 90 | 10 | 残血 |
| 近炸引信 AoE（120 m 全额伤害） | 80 | 20 | 残血（全队同时残血） |

**100 这个数的含义**：它高于全部玩家导弹伤害（最高 AGM-65 = 90），因此
**任何单发导弹都无法直接击坠王牌中队** —— 耗尽热诱弹后必定先经过一个残血阶段。
这是与普通飞机"导弹一击必杀"铁律最本质的区别，也是本 tier 唯一使用血量轴的地方。

### 2.4 机炮（修正"BOSS 不如小兵"）

现状缺陷：王牌中队共享 `default_gun.tres`（M61A1），而后期杂兵挂 `enemy_gun_v8`，
**射程 / 伤害 / 精度三项全面碾压王牌中队**。新建专属资源修正：

| 字段 | `ace_gun.tres`（新） | `default_gun.tres`（现状） | `enemy_gun_v8`（杂兵天花板） |
|---|---|---|---|
| `bullet_damage` | **15.0** | 8.0 | 13.5 |
| `max_range` | **1400.0** m | 1000.0 | 1350.0 |
| `muzzle_velocity` | **1200.0** m/s | 1050.0 | 1200.0 |
| `spread_angle` | **1.0°** | 1.5° | 1.1° |
| `fire_rate` | 3000.0 rpm | 3000.0 | 3000.0 |
| `fire_cone_half_angle` | 5.0° | 5.0 | 5.0 |
| `max_ammo` | 600 | 200 | 520 |

**原则：王牌中队的每一项武器指标都必须 ≥ 同期杂兵的天花板。**否则 tier 名不副实。

### 2.5 机炮开火节奏

| 字段 | 王牌中队 | 普通 AI | 玩家 |
|---|---|---|---|
| 连射时长 | **4.0 s** | 2.5 s | 无限制 |
| 停火时长 | **1.5 s** | 3.0 s | 无（豁免） |
| 占空比 | **73%** | 45% | 100% |

## 3. 行为与公式（How）

### 3.1 热诱弹消耗流程

```
收到"有导弹锁定本机且距离 ≤ 400 m"
  ├─ 若 is_cloaked 或 suppress_flares → 不投放（隐形期无实体，投放是浪费）
  ├─ 若 flares_remaining == 0        → 不投放，导弹命中 → 结算伤害
  └─ 否则
       flares_remaining -= 1
       该枚导弹【必定】丢失制导（见 §3.3）
       进入 cooldown 1.2 s
```

### 3.2 隐形期的交互（澄清）

隐形（cloak）期间王牌中队**无实体**：不可锁定、子弹穿过、导弹丢失制导。因此：

- **不投放热诱弹**（无威胁可躲，投放即浪费命数）
- 隐形**不消耗**热诱弹命数 —— 它是独立的第二防御层
- 隐形结束瞬间恢复全部可被攻击性

### 3.3 干扰判定 —— 确定性

普通敌机走 `FlareParams` 的概率模型（`base_jam_chance` + 角度/机动/距离修正）。
**王牌中队不走该模型**，改为：

```
jam_chance(ace_tier) = 1.00   # 恒定，不受角度 / 距离 / 机动影响
```

理由：命数模型要求"1 枚热诱弹 = 1 条命"严格成立。若引入概率，
玩家无法从"骗掉几发"推断剩余命数，且迎头交战时（原模型无 `aspect_bonus`，仅 0.65，
150 m 内更跌到 0.35）命数会随机蒸发 —— 这正是当前 Wraith "偶尔一发就死"的体感来源。

### 3.4 导弹规避（明确不做）

王牌中队**不执行 beam / notch 等规避机动**。防御手段只有两层：**热诱弹（命数）+ 隐形**。

理由：规避机动会让王牌中队频繁脱离交战去做几何动作，直接破坏 tier 定义里
"对玩家攻击欲极强、咬住不放"的核心特质。热诱弹耗尽后**不解锁**规避作为最后挣扎 ——
"耗尽即防御归零、两发导弹内必死"是本机制的确定性承诺（2026-07-20 用户确认）。

> 落地注意：现有代码里 `evade_missiles = true` 与 `boss_attacker = true` 并存，
> 而所有规避入口都被 `not is_boss_attacker()` 挡掉 —— **行为正确但配置在骗人**。
> 应删除该行死配置，而非把规避接上。

### 3.5 隐形 vs 锁定（一致性铁律）

**任何"隐形中"的飞机，对任何一方的任何锁定/索敌通路，都必须不可见。**

现状漏洞：`is_lock_immune()` 只在雷达累积循环里被执行，而 AI 出于性能考虑大量直接扫
`CombatUnit.all_units` 当传感器，这些通路完全没有隐形语义。必须补齐的通路：

| 通路 | 要求 |
|---|---|
| `AIController._current_target` | 目标进入隐形 → 立即失效并重新选目标 |
| 小队协同索敌（绕开雷达锥的"自由交战"扫描） | 过滤 `is_lock_immune()` |
| 简易 AI / tether / 神风 的 `all_units` 扫描 | 同上 |
| 副雷达（QMAAM）锁定累积 | 同上 |
| BFM 机动层读取目标位置 | 目标隐形时不得继续获得精确位置 |
| 副雷达锁定框渲染 | 不得在隐形机位置画框 |
| AA 炮索敌 | 同上 |

> 当前最严重的后果：BFM 层对隐形目标保持**零误差位置跟踪**，只是扳机哑火 ——
> 解除隐形瞬间零延迟重新交战，隐形在战术上完全没有价值。

### 3.6 BOSS 附加规格（子集专属）

| 项 | 要求 |
|---|---|
| 强度 | 机体性能与技术水平 **严格强于**同期非 BOSS 王牌中队 |
| 主题 | 专属 BGM |
| 演出 | 专属登场序列（见 `systems/ui-transition`）+ 专属电台台词（见 `systems/radio-chatter`） |
| 关卡机制 | **击败全队 → 关卡结束**（触发 VICTORY 结算 + 功勋入账） |

非 BOSS 的王牌中队**不触发关卡结束**，只是生存模式中途的强敌。

## 4. 结构与组成（Structure）

### 4.1 概念层级与类继承

概念上 **BOSS ⊂ 王牌中队**。现有类继承是 `BossEncounter → AceSquad → F47AceSquad`，
即 BOSS 是基类、王牌中队是派生 —— **与概念层级倒置**。

本 spec **不要求立即重构**（改动面大、收益低），但要求：

- 新增"非 BOSS 王牌中队"时，**不得**假设它必然带 `category == "boss"` meta
- tier 属性（LOD 豁免 / 无缩放 / 热诱弹命数）一律挂 `tier == "ace"`，**不得**挂 `category == "boss"`
- 概念倒置登记进 `architecture/known-seams.md`，作为下一轮 refactor 排期输入

### 4.2 资源归属

`gun_accuracy` 玩家升级会**原地修改** `GunParams` Resource。由于王牌中队现在共享
`default_gun.tres`，玩家升级可能顺带改到敌方参数。新建 `ace_gun.tres` 顺带根治此问题。
仍需确认 spawn 时是否对 params 做了 `duplicate(true)`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **命数可数**：玩家连续发射导弹，前 4 发均被热诱弹骗飞（100%，无随机失败），第 5 发命中。
- [ ] **迎头同样成立**：迎头交战下前 4 发导弹同样必定被骗（验证已移除角度依赖）。
- [ ] **近距同样成立**：150 m 内发射的导弹同样必定被骗（验证已移除距离惩罚）。
- [ ] **耗尽即残血**：热诱弹耗尽后中一发 MRM（80 伤）不死，剩 20 HP；中一发 AGM-65（90 伤）
      同样不死，剩 10 HP（验证 100 HP 高于全部玩家导弹伤害）。第 6 发必定击坠。
- [ ] **隐形不耗命**：完整经历一次隐形周期，`flares_remaining` 不减少。
- [ ] **隐形不可锁**：隐形期间 AI 僚机无法将其设为 combat target；副雷达不累积锁定；
      不出现锁定框；解除隐形后需重新累积锁定（不得零延迟重连）。
- [ ] **不吃 LOD**：飞出屏幕 / 远离玩家 3000 m 后，其 `_physics_process` 仍在跑，AI 决策频率不降。
- [ ] **火力不输杂兵**：`ace_gun.tres` 每项指标 ≥ `enemy_gun_v8`。
- [ ] **无等级缩放**：Lv1 与 Lv20 下同一王牌中队的 HP / 机炮伤害 / 导弹数完全一致。
- [ ] **不做规避**：全程不出现 beam/notch 规避机动，热诱弹耗尽后亦然。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（见 performance-guidelines）
- [ ] 已知 seam 未触碰 / 已妥善处理（见 architecture/known-seams.md）
- [ ] i18n：玩家可见文本走 tr()，三语已补（见 reference/i18n.md）

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 纯 bug 修复（不依赖数值定稿，可先行）
- [x] 删除王牌中队的 `evade_missiles = true` 死配置（行为不变，消除误导）
- [x] 修正 `enemy-index.md` 的错误记载：热诱弹"40 枚"→ 实际值；隐形周期"60s"→ 实际值
- [x] 修正 `CLAUDE.md` 中"生存模式 = 无尽波次"的过期描述（实际打完 BOSS 即过关）
- [x] `AIController._current_target` 增加隐形失效判定
- [x] 小队协同"自由交战"扫描增加 `is_lock_immune()` 过滤
- [x] 简易 AI / tether / 神风 三处 `all_units` 扫描增加 `is_lock_immune()` 过滤
- [x] 副雷达锁定累积增加 `is_lock_immune()` 过滤
- [x] 隐形机不再被绘制副雷达锁定框
- [x] AA 炮索敌增加隐形过滤
- [x] 机炮前置解：统一两处 lead 计算的弹速来源（消除硬编码 1050 m/s 与真实 muzzle_velocity 的分歧）

### 阶段 2 — tier 基础设施

> 落地方式：新建 **`scripts/survivor/ace_tier.gd`**（`class_name AceTier`）作为 tier 语义的
> 单一归属地。原本散在三处的判定（LOD 看 `category=="boss"` / 缩放按 EnemyType 逐个列举 /
> HP cap 另写一条）全部收敛为对本模块的一行调用，调用方只问不判。
> 加新王牌中队现在**只改 `AceTier.is_ace_type()` 一处**。

- [x] 引入 `tier == "ace"` meta，LOD 豁免判定从 `category == "boss"` 迁移到 tier
- [x] `ENEMY_HP_MISSILE_CAP` 增加王牌中队豁免分支（显式例外）
- [x] 等级缩放豁免从"按 EnemyType 枚举列举"迁移到按 tier 判定

### 阶段 3 — 生存模型落地（依赖 §2.3 数值定稿）
- [ ] 新建王牌中队专属 flare 资源：`max_flares = 4`、`burst_count = 1`、`nervousness = 0.5`
- [ ] 干扰判定增加 tier 分支：王牌中队 `jam_chance = 1.00`
- [x] 王牌中队 `max_hp` 定档 = 100（随阶段 2 一并落地：HP cap 豁免不设血量就无从验证）
- [ ] 确认 spawn 时 params 走 `duplicate(true)`，隔离玩家升级对敌方资源的污染

### 阶段 4 — 火力对齐
- [ ] 新建 `ace_gun.tres`，数值按 §2.4
- [ ] 王牌中队机型改挂 `ace_gun.tres`
- [ ] 机炮开火占空比增加 tier 分支（4.0 s / 1.5 s）

### 阶段 5 — 收尾
- [ ] 跑 §5 全部验收项
- [ ] 派生 `bosses/wraith-squadron.md`（Wraith 具体规格，depends_on 本 spec）
- [ ] 概念层级倒置登记进 `architecture/known-seams.md`
- [ ] 更新 §7 锚点 + 同步 reference 索引 + `_INDEX.md` 总表
- [ ] 跑 `python tools/verify_doc_anchors.py`

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

<!-- 实现落地后填写 -->

| 关注点 | 文件 |
|---|---|
| **tier 语义单一归属地** | `scripts/survivor/ace_tier.gd`（`AceTier`：成员判定 / 缩放豁免 / HP cap 豁免 / 血量） |
| tier 回归测试 | `scripts/tests/test_ace_tier.gd`（`--bench=ace_tier`，20 断言） |
| 王牌中队基类 | `scripts/survivor/ace_squad.gd`、`scripts/survivor/f47_ace_squad.gd` |
| tier 打标 / 缩放 / HP cap 调用点 | `scripts/survivor/survivor_spawner.gd`（`_create_enemy` 末尾 + 缩放块） |
| LOD 豁免调用点 | `scripts/survivor/survivor_mode.gd`（离屏冻结 + 预算排队两处） |
| 热诱弹逻辑 | `scripts/aircraft/aircraft_flares.gd` |
| 隐形锁定过滤 | `scripts/ai_controller.gd`、`scripts/ai/squad_coordination.gd`、`scripts/ai/target_selection.gd`、`scripts/ai/missile_evasion.gd`、`scripts/aircraft/aircraft_weapons.gd`、`scripts/aircraft_renderer.gd`、`scripts/aa_gun_unit.gd` |
| 机炮前置解弹速 | `scripts/ai/tactical/situation.gd`（`gun_muzzle_mps`）、`scripts/ai/tactical/bfm_intent.gd` |
| 参数资源 | `resources/ace_gun.tres`（阶段 4，未建）、王牌中队 flare 资源（阶段 3，未建） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-20 | 1 | 初稿。确立王牌中队/BOSS 分层定义、热诱弹=命数生存模型、tier 准入门槛、隐形一致性铁律。`max_hp` 定档待裁决 |
| 2026-07-20 | 2 | 用户定档：`max_hp = 100`、干扰成功率 1.00。因 100 高于全部玩家导弹伤害，§1.1「耗尽即必死」修正为「耗尽即防御归零 → 必经残血 → 第 6 发击坠」。**阶段 1 + 阶段 2 落地**：隐形一致性 7 处通路补齐、`evade_missiles` 死配置删除、机炮前置解弹速统一；新建 `AceTier` 模块收敛 tier 三处散点判定，`--bench=ace_tier` 20 断言全绿 |
