---
id: ace-2ndwave
kind: event
status: in-progress         # 728 实装批核心落地（bench 混编断言绿 + 回归门 41 项），差 playtest
schema_version: 1
spec_version: 2
owner: noelu（设计输入 2026-07-27）/ Claude（细化）
depends_on: [ace-squadron-tier, ace-support-squadron, ace-lancer-mig31, joust-attack-run]
reconstruction_complete: false
---

# 王牌中队 2NDWAVE / 第二波（F-4E ×1 + F-15 ×4）—— 混编首例

> 玩家视角：一架老得不该出现在这个战场的 F-4E 咬住了你，而且**甩不掉**——你打它，它躲；
> 你锁它，它没有热诱弹可骗，它直接从你的导弹底下滚出去。等你终于沉下心跟这位老先生
> 单挑，四架崭新的 F-15 已经排成一线，从你的缠斗圈外侧压了进来。
> 无线电里那个平静的声音说：开始上课。

## 1. 设计意图（Why）

- **用户需求（2026-07-27）**：早期登场的第二支王牌中队。F-4E 后面带四架 F-15：
  F-4 是斗士型、F-15 是骑士型；F-4 代号固定 **Teacher**，AI 很高操作很好，
  **没有 flare 也会靠机动躲避玩家攻击，被机炮追也会闪避**；玩家和 F-4 缠斗时
  会被 F-15 围攻。
- **考核命题**：MARATHON 考"被咬住怎么办"、VULTURE 考"追不上怎么办"，2NDWAVE 考
  **注意力分配**——最硬的目标（Teacher）在你脸上，但你不能只看它。是先杀了绕圈的
  老师，还是先拆外围的波次？两个答案都对，两个答案都要付代价。
- **混编合法性**：tier §3.7 混编条款首例——2 个 element 静态分工（Teacher 斗士 /
  学员骑士），全程**无相位切换**（那是 BOSS 专属）。
- **Litmus 自检**：
  - 单杠杆：Teacher 的强度只有**闪避**一根杠杆（导弹机动规避 + 特高档机炮闪避），
    HP 仍一发死、机体不魔改；学员的强度只有掠袭协同，机体不魔改；
  - 确定性让位声明：Teacher 是 tier §3.4 例外条款的首个个体——零 flare 机动规避型，
    防御预算从"确定命数"换轴到"持续周旋"（用户显式定档）；学员维持 1 枚必躲的确定性；
  - 效果即反馈：Teacher 从导弹下滚出去本身就是演出；学员横列压圈可肉眼预读；
  - 可学习：反制答案见 §2.4。
- **反模式规避**：无二阶机制、无等级缩放、不占 token；Teacher 的"难缠"全部来自
  可观察的机动，不加隐藏减伤。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 编成与 tier 参数

| 字段 | 值 | 说明 |
|---|---|---|
| 编成 | **F-4E ×1（长机 Teacher）+ F-15 ×4（学员）** | 老机带新机——机体代差本身就是叙事 |
| element 分工 | Teacher = 斗士 `gladiator`；学员 = 骑士 `lancer`（tier §3.7 混编条款，静态、不切换） | — |
| tier | 全员 `AceTier.mark()` 实例打标 | F-4E 杂兵 / 将来可能的杂兵 F-15 不受影响 |
| tier 待遇 | LOD 豁免 / 无等级缩放 / `skip_far_cleanup` / armor 0 / token 0 | 引 tier §2.1 |
| Teacher AI | `skill_level / composure / focus / situational_awareness = 1.0`（**顶格**，高于王牌门槛 0.90）；aggression 0.95 | 用户："AI 很高操作很好" |
| 学员 AI | 王牌档（同 MARATHON：≥0.90 / aggression 0.95） | — |
| 涂装 | **电紫 `#B44DFF`**（tier §2.7 主色表） | 紫/红系；与 MARATHON 猩红、VULTURE 酒红可区分 |
| 登场时段档 | **早期**（240 s 门槛，tier §2.9；2026-07-28 Marathon 改中期后为**唯一早期队**——本局第一支王牌总是 2NDWAVE） | 用户标注早期登场 |

### 2.2 生存模型（双轨）

| 项 | Teacher（F-4E） | 学员（F-15 ×4） |
|---|---|---|
| `max_hp` | 不豁免 cap（≤75）→ **一发死** | 同左，一发死 |
| flare | **0 枚**（tier §2.2 统一铁律的"特别声明"例外） | **1 枚必定躲**（默认档：jam 1.00 / fail 0 / 不补充） |
| 导弹防御 | **机动规避开启**（tier §3.4 例外条款：beam/notch 等既有规避行为对其解锁） | 不做规避机动（默认） |
| 机炮闪避 | **特高档 0.50**（tier §2.2 分档——被机炮追也会闪，这是它唯一的防御轴） | 基线档 0.20 |

**Teacher 击杀读数**：没有"骗 N 发"的确定序列——它的防御是**概率与几何**。反制不是
堆弹，是**质量**：好角度的迎头/大离轴发射、缠斗中贴到它规避半径以内再开火、或者用
机炮弹流磨（0.50 闪避在弹流尺度 = 稳定 50% DPS 折减，不是免疫）。命中一发即坠
（一发死不豁免）——**难打中，不难打死**。

### 2.3 火力

| 项 | Teacher | 学员 |
|---|---|---|
| 机炮 | `ace_gun.tres`（tier §2.4） | **无**（骑士风格纯导弹） |
| 导弹 | F-4E 档案默认弹，撤销等级加弹 | 档案默认弹；载弹 **6 发/机** = 6 波预算 |
| 弹尽 | 不弹尽（机炮在） | 全 element 弹尽 → 该 element 转撤离（Teacher 不走，战至全灭或 BOSS 闸） |

### 2.4 战术（两套并行，互不切换）

**Teacher（斗士）**：全程 PURSUIT 死咬**玩家操控机**（引 MARATHON 同款软维护），
永不脱离、永不撤离（BOSS 闸除外）。

**学员 element（骑士）**：四机横列掠袭循环（引 VULTURE 状态机，参数收窄）：

| 参数 | 草案值 | 说明 |
|---|---|---|
| `R_volley` | **3500 m** | F-15 速度低于 MiG-31，圈收近一档 |
| 每波投射 | 1 发/机 ×4 | 目标分配引 VULTURE §3.2（对玩家小队存活成员 round-robin） |
| `D_extend` | **5000 m** | — |
| 掠袭轴 | 指向**Teacher 当前缠斗对手的位置**（= 玩家操控机所在缠斗圈） | "玩家和 F-4 缠斗时会被 F-15 围攻"的实现——轴线穿圈，波次自然打进玩家的缠斗空域 |
| 回转 | 减速至角点速度物理回转 | 同 VULTURE，玩家的强杀窗口 |

**玩家反制答案**（写给 playtest 验收）：

1. **先拆学员**：学员是标准骑士——回转窗口贴近强杀，每拆一架，围攻密度线性下降；
   Teacher 虽难缠但**杀不死你队友**的速度有限（一门炮 + 有限导弹）。
2. **先杀老师**：把缠斗拖进己方僚机火网，用机炮弹流磨掉 0.50 闪避的期望值；
   学员的齐射来袭帧管好 flare 纪律。
3. 最差答案是**两头摇摆**——谁都没杀掉，防御资源先耗光。考核考的就是这个决断。

### 2.5 触发与调度

早期档（tier §2.9）：`game_time ≥ 240 s` 进池。2026-07-28 Marathon 改中期后本队为
**唯一早期队**；320 s 起中期三队进池，轮换指针在已进池队伍间轮转（同局不重复同队）。
间隔 150 s / 540 s 截止 / 同场 ≤1 支 / BOSS 阶段不触发——全部沿用。BOSS 闸落下：全队转撤离（含 Teacher），
撤离中击败无时间奖励（tier §2.9 通用契约）。

### 2.6 奖励

| 项 | 值 |
|---|---|
| 击杀 XP | 学员 100/架；**Teacher 200**（难缠档溢价，草案） |
| 全灭奖励 | `game_time −60`（+1 分钟）+ 歼灭通报（同 MARATHON） |
| 留档 | `record_ace_defeat("2ndwave")` |

### 2.7 包装（tier §2.7 五件套；文案待用户过目）

| 项 | 值 |
|---|---|
| 中队代号 | **2NDWAVE / 第二波**（用户命名） |
| 主色 | 电紫 `#B44DFF` |
| 徽章 | 双叠浪线——第二道浪比第一道高（后浪盖过前浪；也是"第二波攻势"的战术图符号） |
| 血条 | 5 段命条；**Teacher 段带长机三角标记**（tier §2.8——打谁先，读条就知道） |
| 留档 id | `2ndwave` |

**成员固定呼号**（学籍主题；TEACHER 为用户定名；开局 reserve、永不 recycle；
均不在 CallsignDB 800 池内）：

| 槽位 | 机型 | 呼号 | 味 |
|---|---|---|---|
| 长机 | F-4E | **TEACHER** | 教官——从不毕业的那个人 |
| 2 号机 | F-15 | SENIOR | 大四——最像老师的一个 |
| 3 号机 | F-15 | JUNIOR | 大三 |
| 4 号机 | F-15 | SOPHOMORE | 大二 |
| 5 号机 | F-15 | FRESHMAN | 大一——第一个慌的 |

**Lore**（`ACE_SQUAD_2NDWAVE_LORE`，三语草案）：

- zh：敌军高等战术学校的毕业考核编队。四名学员驾驶最新锐的 F-15，而教官那架 F-4E
  比他们的座机整整老两代。开课三十年，没有任何学员在毕业考核里击落过 Teacher——
  **这一届的考题，是你。**
- en: The graduation-exam flight of the enemy's advanced tactics school. Four cadets fly
  factory-new F-15s; the instructor's F-4E is two full generations older than any of them.
  In thirty years, no student has ever scored a kill on Teacher. *This year's exam
  question is you.*
- ja: 敵軍高等戦術学校の卒業試験編隊。四人の学生は最新鋭のF-15を、教官は二世代も古い
  F-4Eを駆る。開校三十年、卒業試験でTeacherを墜とした学生は一人もいない。
  **今年の試験問題は——君だ。**

**专属台词行（可选，向 `ace_spawn` 池外追加专属覆写，实装批定）**：Teacher 入场固定说
"开始上课。/ Class is in session. / 授業を始める。"——比通用池更有角色感；全灭时
学员幸存 0 的瞬间无临终台词（克制，非 BOSS 不做多句演出）。

## 3. 行为与公式（How）

### 3.1 双 element 运行

两 element 完全独立驱动：Teacher 走既有 PURSUIT 软维护（MARATHON 同款）；学员走
VULTURE 掠袭状态机（§2.4 参数覆写 + 掠袭轴改指缠斗圈）。**无任何相互切换 / 接管 /
阶段逻辑**——Teacher 阵亡后学员**不改变行为**（继续掠袭循环直到全灭/弹尽/BOSS 闸），
学员全灭后 Teacher 也不改变行为。这是混编条款"静态分工"的字面执行。

### 3.2 Teacher 的规避（例外条款的行为面）

- 导弹：走既有敌机规避行为链（beam/notch），解锁方式 = 不打 boss_attacker 型
  "规避禁用"标记（实装细节在落地批查既有开关，原则：**复用既有规避行为，不新写机动**）；
- 机炮：`bullet_dodge_chance = 0.50`，闪避判定既有；
- 无 flare：`max_flares = 0`，`enable_flare_reload = false`。

### 3.3 与既有系统关系

引 VULTURE §3.3（joust 原语 / 队级小模块 / flare 链路）；学员 element 直接复用
`lancer_squad_tactics.gd`（参数注入 R_volley/D_extend/掠袭轴），**不复制粘贴**。

## 4. 结构与组成（Structure）

- 走编成 profile 表（tier §4.3 第 3 步）：本队 = profile 一行 + element 分工字段
  （`elements: [{type: f4e, count: 1, style: gladiator, overrides…}, {type: f15,
  count: 4, style: lancer, overrides…}]` 语义）；
- **需新建 `resources/enemy_f15.tres`**（敌用 F-15 档案，当前只有可驾驶版）。数值草案：
  以 Su-27 敌档为基线上调速度档（max_speed ~2650 / cruise ~1350 / max_g 9.0），
  细表落地批定；
- Teacher 直接吃 `enemy_f4e.tres` + spawn 后处理覆写（AI 顶格 / flare 0 / dodge 0.50 /
  ace_gun）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **Teacher 难打中不难打死**：顶格 AI + 规避下，尾追平射导弹大概率被机动甩脱；
      贴近/大离轴/迎头质量弹可命中；命中任意一发即坠
- [ ] **机炮闪避可感**：机炮弹流打 Teacher，命中率≈无闪避对照的一半（0.50 骰）；
      打学员≈八成（0.20）
- [ ] **围攻成立**：玩家与 Teacher 缠斗 ≥20 s 内，至少一波学员齐射穿过缠斗圈、
      玩家操控机被点名
- [ ] **静态分工**：Teacher 阵亡后学员行为不变；学员全灭后 Teacher 行为不变（EventLogger）
- [ ] **学员=标准骑士**：1 骗 + 第 2 发死；回转窗口可强杀；弹尽 element 撤离
- [ ] **包装合规**：血条 5 段 + Teacher 段三角标；代号提示条；固定呼号出现在 kill feed；
      全灭入档 `2ndwave`
- [ ] **轮换**：与 MARATHON 交替，同局不连出同一队
- [ ] tier 待遇全套（LOD/缩放/token/实例打标——杂兵 F-4E 零影响）
- [ ] 性能：5 机 LOD 豁免过 Sentinel + Lv5 压测；i18n 三语

## 6. 实现计划（Task Pipeline —— 定稿后执行）

### 阶段 0 — 前置
- [ ] 编成 profile 表 + element 分工字段（与 VULTURE 批共享的 tier §4.3 欠账）
- [ ] `resources/enemy_f15.tres` 新建

### 阶段 1 — Teacher
- [ ] spawn 后处理（AI 顶格 / flare 0 / dodge 0.50 / ace_gun / 涂装）
- [ ] 规避解锁接线（复用既有规避行为链，删"王牌不规避"对其的拦截）

### 阶段 2 — 学员 element
- [ ] `lancer_squad_tactics.gd` 参数注入化（R_volley/D_extend/掠袭轴外置）
- [ ] 掠袭轴 = 缠斗圈锚（Teacher 当前对手位置，0.5 s 软更新）

### 阶段 3 — 包装与调度
- [ ] 早期档轮换指针（MARATHON ↔ 2NDWAVE）
- [ ] 血条 / 呼号 / 徽章 / lore / 提示条 / 留档（tier §6 阶段 7 通用件就位后接线）
- [ ] Teacher 专属入场行（可选）
- [ ] F5 debug 面板加项

### 阶段 4 — 收尾
- [ ] `--bench` 断言（Teacher 规避 sim + 学员分配复用 lancer bench）+ §5 验收 + playtest

## 7. 索引锚点（Where —— 实装后填写）

| 关注点 | 文件（预期） |
|---|---|
| 编成 profile | `scripts/survivor/ace_squad_profiles.gd`（新建） |
| 学员战术 | `scripts/survivor/lancer_squad_tactics.gd`（VULTURE 批新建，本批参数化） |
| 敌用 F-15 档案 | `resources/enemy_f15.tres`（新建） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-28 | 2 | **核心落地**（用户"开始执行"）：enemy_f15.tres 新建；AceSquadProfiles elements 混编（tier §3.7 条款首个实装：Teacher=F-4E KNIGHT+ace_gun+零 flare+evade 解锁[ace_evader meta 免 boss_attacker]+dodge 0.50+AI 顶格 1.0；学员=F-15×4 骑士 element 复用 lancer_squad_tactics、载弹 6 硬预算）。**落地修订四则**：①掠袭轴 v1 = 玩家小队质心（spec §9 备选案，"轴指缠斗圈"留 playtest 升级）②Teacher XP 溢价未做（统一 100/架）③学员弹尽不单独撤离——is_ammo_dry 只在"存活成员全为骑士且弹尽"时真（Teacher 死战不退的字面执行；Teacher 阵亡后学员弹尽自然转撤离）④Teacher 专属台词行未加（可选项）。bench：--bench=lancer_squad B2 混编解析断言 + 回归门 41 项 PASS。差 §5 playtest |
| 2026-07-27 | 1 | 初稿（draft）：用户需求（F-4E "Teacher" 带 4× F-15 / 斗士+骑士混编 / Teacher 零 flare 高 AI 靠机动闪避 / 缠斗时被 F-15 围攻 / 早期登场）→ tier §3.7 混编条款首例 + §3.4 零 flare 机动规避型首例。包装（2NDWAVE / 电紫 / 双叠浪 / 学籍呼号）与数值草案待定稿 |

## 9. 自拍板项（定稿时重点 review）

1. Teacher 机炮闪避 0.50 / 学员 0.20（tier 分档草案——Teacher 太不死就降 0.40）
2. Teacher 击杀 XP 200 溢价（不想要差异化就回 100）
3. 学员 R_volley 3500 / D_extend 5000（比 VULTURE 收近一档）
4. 掠袭轴指缠斗圈（备选：指玩家小队质心——围攻感更弱但实现更省）
5. 学员弹尽 element 单独撤离，Teacher 死战不退（备选：学员弹尽后全队撤）
6. enemy_f15 数值基线（Su-27 上调 vs 以可驾驶 F-15 降档派生）
7. 呼号 SENIOR~FRESHMAN 的年级排序（2 号机=大四……5 号机=大一）
