---
id: ace-gimmick
kind: event
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 3
owner: noelu（设计输入 2026-07-27）/ Claude（细化）
depends_on: [ace-squadron-tier, ace-support-squadron, bosses/wraith-squadron]
reconstruction_complete: false
---

# 王牌中队 GIMMICK / 把戏（F-16 ×2 + Mirage 2000 ×2）—— 远近夹击

> 玩家视角：两架幻影贴上来缠斗，缠得凶但不算打不过——直到第一枚不知道从哪来的导弹
> 掠过你的座舱盖。四公里外，两架 F-16 一直在外圈绕，专挑你压坡度最狠的那一秒放弹。
> 你恼了去追 F-16，幻影立刻咬上你的六点。所有人都知道这个套路。所有人还是会上当。

## 1. 设计意图（Why）

- **用户需求（2026-07-27）**：中期登场。F-16 ×2 + Mirage 2000 ×2；F-16 在远处狙击，
  Mirage 2000 近距离狗斗。
- **考核命题**：**目标选择的纪律**。MARATHON 考防守、VULTURE 考拦截、2NDWAVE 考注意力
  分配，GIMMICK 考"先打谁"——追狙击手 = 被斗士咬死，只顾斗士 = 被狙击手放风筝。
  它是 [Wraith](../bosses/wraith-squadron.md)"KNIGHT 逼你转弯 / SNIPER 惩罚你转弯"
  两难的**非 BOSS 简装版**：无队级状态机、无 BRACKET 诱饵相、无执行精度系统——
  只有静态的远近分工。中期打过 GIMMICK 的玩家，等于提前上过 Wraith 的第一课。
- **风格落位**：tier §3.7 混编条款（≤2 element 静态分工）：Mirage element = 斗士
  `gladiator`；F-16 element = **狙击 `schemer`**（本队启用风格库狙击位）。
  **归位已确认（2026-07-27 用户拍板）**：不是高速冲过去骑射再折返的掠袭——F-16 只是
  **更倾向于用导弹，被追的话倾向于跑开**。
- **Litmus 自检**：单杠杆（两个 element 各自只有一套行为，全程不换）；效果即反馈
  （远处的导弹尾烟就是"外圈有人"的提示，无 HUD 中介）；可学习（反制答案 §2.4）。
- **反模式规避**：无二阶机制 / 无等级缩放 / 不占 token；狙击手不做"读玩家操作"的
  预判魔法，用 Wraith SNIPER 既有站位带行为。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 编成与 tier 参数

| 字段 | 值 | 说明 |
|---|---|---|
| 编成 | **F-16 ×2（狙击 element，长机在此）+ Mirage 2000 ×2（斗士 element）** | 2+2 最小两难结构 |
| tier | 全员 `AceTier.mark()` 实例打标；LOD 豁免 / 无缩放 / `skip_far_cleanup` / armor 0 / token 0 | 引 tier §2.1 |
| AI | 王牌档（四维 ≥0.90 / aggression 0.95） | — |
| 生存 | 全员**一发死 + 1 枚必躲 flare**（默认档） | tier §2.2 |
| 机炮闪避 | 全员基线 0.20 | 无难缠档个体 |
| 涂装 | **洋红 `#E23A8E`**（tier §2.7 主色表） | — |
| 登场时段档 | **中期**（`game_time ≥ 320 s` 进轮换池，tier §2.9） | 用户标注中期 |

### 2.2 狙击 element（F-16 ×2）

| 项 | 值（草案） | 说明 |
|---|---|---|
| 战术 | **导弹偏好 + 保持距离**：绕玩家小队外圈游走放弹（站位带 4000~6000 m 为实现草案，非硬几何） | 用户定档语义："更倾向于用导弹"。实现复用 Wraith SNIPER `bvr_only` 站位带行为（AceRole 基建现成） |
| 火力 | 导弹为主（载弹 6 发/机）+ 机炮自卫（`ace_gun`） | 放弹节奏走既有 BVR 交战链路 |
| 施压偏好 | 优先攻击**正在与幻影缠斗**（高 bank / 被咬）的玩家单位 | 惩罚缠斗——两难的另一半；实现走既有目标评分偏置，不新写预判 |
| **被追** | **倾向于跑开**（用户定档）：玩家/僚机压向它就脱离拉开，重建距离后继续放弹（AF-03 打带跑同款），**不接受缠斗** | 狙击手失去屏障后只会跑——追击战玩家占优，反制答案的兑现点 |
| 弹尽 | element 弹尽（机炮还在）→ 继续外圈机炮自卫，**不撤离** | 简单化：残存威胁小，不值得撤离特例 |

### 2.3 斗士 element（Mirage 2000 ×2）

全程 PURSUIT 近距狗斗（MARATHON 同款软维护），目标 = 玩家操控机优先；机炮（`ace_gun`）
+ 导弹（档案默认）。**不protect狙击手、不回防**——静态分工，各打各的（分工本身
就是保护：你去追 F-16，幻影自然出现在你六点，无需协同代码）。

### 2.4 玩家反制答案（写给 playtest 验收）

1. **正解：先拆屏障，再压狙击**。幻影是标准斗士（可预测、可拉进僚机火网）；
   拆掉后 F-16 没有近战屏障，贴近它只会打带跑——追击战玩家占优。
2. **次解：硬吃狙击**。带着幻影的咬尾压向 F-16 站位带，用 flare 纪律扛狙击弹——
   高风险，省时间。
3. **错解：来回摇摆**。谁都打不死，防御资源先见底。这就是"把戏"能一直管用的原因。

### 2.5 调度 / 奖励

中期轮换池（与 GOOFIGHTERS 轮换；间隔 150 s / 540 s 截止 / 同场 ≤1 支 / BOSS 闸撤离
无时间奖励——tier 契约全沿用）。击杀 XP 100/架；全灭 `game_time −60`（+1 分钟）；
留档 `record_ace_defeat("gimmick")`。

### 2.6 包装（tier §2.7 五件套；文案待用户过目）

| 项 | 值 |
|---|---|
| 中队代号 | **GIMMICK / 把戏**（用户命名） |
| 主色 | 洋红 `#E23A8E` |
| 徽章 | 交叉互指的双箭头——调包手法的战术图符号 |
| 血条 | 4 段命条；长机（BLUFF）段带三角标记 |
| 留档 id | `gimmick` |

**成员固定呼号**（骗术主题；开局 reserve、永不 recycle；均不在 CallsignDB 800 池内）：

| 槽位 | 机型 | 呼号 | 味 |
|---|---|---|---|
| 长机 | F-16 | **BLUFF** | 虚张声势——你以为该先打他 |
| 2 号机 | F-16 | FEINT | 佯攻 |
| 3 号机 | Mirage 2000 | BAIT | 饵 |
| 4 号机 | Mirage 2000 | SWITCH | 调包——bait and switch 的后半句 |

**Lore**（`ACE_SQUAD_GIMMICK_LORE`，三语草案）：

- zh：一支只会一套把戏的中队：远处两架让你追，追到一半、幻影从侧面咬住你。
  情报部门早把这套路写进了新兵教材。**所有人都知道，所有人还是会上当**——
  因为知道和做到之间，隔着一整场空战。
- en: A squadron with exactly one trick: two fighters at range daring you to chase,
  and two Mirages on your six the moment you do. Intelligence put the routine in the
  cadet handbook years ago. *Everyone knows it. Everyone still falls for it* — because
  between knowing and doing lies an entire air battle.
- ja: たった一つの手品しか持たない飛行隊。遠くの二機を追えば、その瞬間ミラージュが
  横から食らいつく。この手口はとっくに新兵教本に載っている。**誰もが知っていて、
  誰もが引っかかる**——知ることと出来ることの間には、空戦一回分の距離があるからだ。

## 3. 行为与公式（How）

- 两 element 完全独立驱动（混编条款静态分工）：幻影走 PURSUIT 软维护；F-16 走
  Wraith SNIPER 站位带行为（`AceRole.SNIPER` / `bvr_only` 基建复用，参数 4000~6000 m）；
- 施压偏好 = 狙击 element 的目标评分对"高 bank / 被队友咬住"的玩家单位加权
  （复用既有可命中性评分通道，加一项偏置，不新写扫描）；
- element 间零通信、零接管：一侧全灭另一侧行为不变（EventLogger 可验）。

## 4. 结构与组成（Structure）

- 编成 profile 表一行（elements 字段：`[{f16 ×2, schemer}, {mirage2000 ×2, gladiator}]`）；
- **需新建** `resources/enemy_f16.tres` 与 `resources/enemy_mirage2000.tres`
  （现只有玩家侧档案；数值草案落地批以玩家档降档派生）；
- 狙击行为不新建模块——`AceRole.SNIPER` 站位带从 Wraith 专属提为 tier 可复用件
  （只动归属，不动行为）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **站位带**：F-16 全程保持 4~6 km 外圈，不主动进近；玩家贴近 → 打带跑拉开
- [ ] **惩罚缠斗**：玩家与幻影缠斗（bank>60°）期间，狙击弹到达频率明显高于平飞期
- [ ] **静态分工**：幻影全灭后 F-16 行为不变；反之亦然
- [ ] **反制答案可执行**：先拆幻影后，压 F-16 的追击战玩家胜率显著高于直接追
- [ ] 击杀序列全员 1 骗 + 第 2 发死；机炮闪避 0.20 可测
- [ ] 包装合规：血条 4 段 + BLUFF 段标记 / 代号提示条 / 固定呼号 / 全灭入档 / 洋红涂装
- [ ] 中期档 320 s 进池；与 GOOFIGHTERS 轮换；tier 待遇全套（杂鱼不受影响——
      注意 F-16 / Mirage 2000 当前无杂鱼版，实例打标仍必须走通）
- [ ] 性能 / i18n 三语

## 6. 实现计划（Task Pipeline —— 定稿后执行）

- [ ] 阶段 0：`enemy_f16.tres` / `enemy_mirage2000.tres` 新建（玩家档降档派生）
- [ ] 阶段 1：SNIPER 站位带提为 tier 复用件 + 施压偏好加权
- [ ] 阶段 2：profile 行 + 中期轮换接线
- [ ] 阶段 3：包装接线（血条 / 呼号 / 徽章 / lore / 提示条 / 留档）+ F5 debug
- [ ] 阶段 4：`--bench` 断言（站位带保持 + 施压偏好 sim）+ §5 验收 + playtest

## 7. 索引锚点（Where —— 实装后填写）

| 关注点 | 文件（预期） |
|---|---|
| 编成 profile | `scripts/survivor/ace_squad_profiles.gd` |
| 狙击站位带 | `scripts/survivor/wraith_tactics.gd` → 提出的复用件（落地批定归属） |
| 新机体档案 | `resources/enemy_f16.tres` / `resources/enemy_mirage2000.tres`（新建） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-28 | 3 | **核心落地**（用户"开始执行"）：enemy_f16.tres / enemy_mirage2000.tres 新建；profile elements 混编——F-16×2 归 `AceRole.SNIPER`（**Wraith SNIPER 站位带 4~6km 基建直接复用**，被贴近打带跑=既有 bvr_only 行为，长机 BLUFF 在狙击位）+ 幻影×2 KNIGHT 斗士；全员 ace_gun/1 枚必躲/AI 0.92。**落地修订两则**：①"施压偏好"（优先打缠斗中的玩家单位）v1 未做——狙击输出走既有 BVR 目标选择，偏好加权留 playtest 批②F-16 弹尽机炮自卫续场=is_ammo_dry 骑士限定语义天然成立（本队无骑士成员，永不弹尽撤离）。bench：--bench=lancer_squad B2 断言（4 机编成/狙击斗士角色分配）+ 回归门 41 项 PASS。差 §5 playtest |
| 2026-07-27 | 2 | **用户拍板 F-16 归位**：确认非掠袭骑士——语义即"更倾向于用导弹、被追倾向于跑开"，狙击 `schemer` 归位成立；§2.2 战术/被追两行改按用户原话语义重写（站位带降级为实现草案非硬几何），§9 开放项 1 关闭 |
| 2026-07-27 | 1 | 初稿（draft）：用户需求（F-16 ×2 远处狙击 + Mirage 2000 ×2 近距狗斗，中期登场）→ 混编第二例、风格库**狙击位启用**首队；定位为 Wraith 两难的非 BOSS 简装版。包装（GIMMICK / 洋红 / 双箭头 / 骗术呼号）与数值草案待定稿 |

## 9. 自拍板项（定稿时重点 review）

1. ~~F-16 的风格归位~~ **已拍板（2026-07-27）**：不是掠袭骑士——导弹偏好 + 被追即跑，
   狙击 `schemer` 归位成立
2. 站位带 4000~6000 m / 施压偏好加权幅度
3. F-16 弹尽后不撤离（机炮自卫续场）vs element 撤离
4. 幻影是否优先咬玩家操控机（现案：是）
5. 新机体档案数值（玩家档降多少）
