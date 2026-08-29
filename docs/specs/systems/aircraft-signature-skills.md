---
id: aircraft-signature-skills
kind: system
status: approved
schema_version: 1
spec_version: 10
owner: 用户
depends_on: [skills-720-rework, evolution-attribute-gates, aircraft-evolution-tree, inrun-weapon-inventory, afterburner-mode, zone-reward-docking, rts-command]
reconstruction_complete: true
---

# 机体签名技能 —— 43 机每机一条专属技能（效果表 / 换机永久继承）

> 来源：用户 2026-07-22《722机体原创技能》表与 2026-08-07 EA-18G/F/A-XX 增补。每架可驾驶机型各配一条**签名技能**：
> 一旦获得就**跟玩家走**，换机/进化后继续生效、不断往下带。2026-08-01 起，获取方式由
> `aircraft-signature-progression` 接管：亲自驾驶后在功勋商店揭示并购买，机场停靠时通过
> “保留当前机体并装备 / 进化机体”二选一取得；
> 本文是 43 条技能效果、归属与继承语义的权威源。

## 1. 设计意图（Why）

- **体验目标**：进化选机不只是换参数——每架机附带一条"只有开过它才能拿到"的 build 词条。
  一局的进化路线 = 一串签名技能的收集顺序，"我这局开过什么机"直接写进 build 里。
- **获取机制（用户定案）**：专属技不进入任何随机池。购买对应机体许可后，机场停靠时选择
  保留当前机体即可立即装备；若选择进化则放弃本次旧机专属装备。稀有度一律
  **4 级 = CLASSIFIED（机密/金）**。
- **继承机制（用户定案）**：获得后永久跟玩家（换机种延续到下一架，不会被移除）。
  实现上由升级账本记玩家层，换机重放不查机型门控（`exclusive_to` 只保留身份映射语义）。
- **Meta 获取**：43 条许可全部进入功勋商店；只有亲自驾驶过对应机体才揭示并可购买。
  未发现机体只显示匿名 `???`，完整规则见 `aircraft-signature-progression`。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - 信息察觉：每条都有明确触发条件（满血/低空/加力窗口/停靠/机动完成）或直观状态（STEALTH/INVINCIBLE/FEAR 均有既有视觉）；无纯暗数值。
  - 一击毙命：伤害类 buff 只作用于机炮（多发武器）与地面单位（HP 池），不做"导弹伤害+%"这类无意义项。
  - 全自动开火：超速截击/传感器融合等新发射通道都是**条件自动触发**，不引入手动扳机。
  - 局内 90/10：功勋购买只开放机场装备资格，技能仍须以放弃当次进化为代价主动取得。
- **反模式规避**：不做无感知微调（最小可感知档 ±20% 起）；单条技能单杠杆，复合效果 ≤2 段；
  不为签名技能新造平行系统——全部复用 720 批归属底座（`exclusive_to`/轴/里程碑/重放）。

## 2. 数据定义（What —— 权威源）

### 2.1 系统规则

| 规则 | 值 |
|---|---|
| 数量 | 43 条（进化树 43 机每机一条；F-14 围猎=既有 `f14_squad_lock_slow` 改档，不新建） |
| id 约定 | `sig_<机型id>`（如 `sig_f15`），i18n `UPGRADE_SIG_<ID>_NAME/_DESC` |
| 稀有度 | 全部 CLASSIFIED（显示与实际稀有度都是 CLASSIFIED；不参与普通金卡 pity） |
| max_stacks | 全部 ×1 |
| 装备门控 | `exclusive_to: [<机型id>]` 保留为身份约束；实际获取由对应功勋商品 + 机场保留机体分支控制 |
| 继承 | 已获得的进玩家层账本 `upgrade_stacks`，换机重放**无条件**重挂（永久跟玩家） |
| 轴归属 | 显式 `axis` 字段（斗士/骑士/策士，按 §2.2 表）；用于 build 语义与效果归类，不因机场装备自动 +1 |
| 轴进度 | 机场装备不发普通选卡的 +1 轴点；`milestone_plus` 按表仍兑现：sig_f15→骑士、sig_a6e→策士、sig_x77→骑士、sig_ax00→骑士+策士 |
| scope | 按表逐条：自身条件类=通用全队（同机种僚机同享）；队级机制=squad_once |
| UI 标识 | 机场右栏显示“保留当前机体”洋红框 + 机型、技能、效果、许可/已装备状态 |

#### 2.1.1 机场二选一与视觉标识（2026-08-26 替代第四槽方案）

旧的 CLASSIFIED 权重、30% 第四槽与逐机 roll 账本全部废弃。签名技能从三轴卡池、普通三选一、
奖励卡与战区 NEXT_GEN 候选中排除；购买许可后，机场规划站在“保留并装备”与“进化”之间二选一。
详细许可、互斥、关闭时机与未知陈列见 `aircraft-signature-progression` §2~3。

后续新增的“机体战术适配”第四槽只从普通候选池按当前机体身份轴抽取，并独立计算稀有度；
它不使用本表 43 条专属技能，也不改变本节机场唯一获取路径。

**机场专属框：洋红专属边框**：

| 项 | 值 |
|---|---|
| 边框色 | **洋红 `(1.00, 0.25, 0.75)`** |
| 边框宽度 | 在常规卡框基础上**加粗一档** |
| 底色 | 叠 **0.10 alpha** 的同色洋红 |
| 内容 | 当前机体、技能名、完整效果、许可/已装备状态与“保留并装备”按钮 |

洋红是**刻意选在五档稀有度色与三轴色（斗士琥珀 / 骑士青绿 / 策士紫）之外**的空位色——
玩家扫一眼就知道“这是当前机体的专属装备方案”，且不会与白色进化方案或三轴量表撞色。

**"加力状态"统一口径**：本批所有"加力"字样均指**加力激活期**（AfterburnerCharge 充能制，
`afterburner_window_active` 为 true 的整段——从启动到耗尽/关闭），不是普通加力推力。超速截击"打破加力不能开火"正是打破加力期 6 处禁火中的主导弹路。

### 2.2 技能总表（43 条；效果数值为定稿，播 playtest 调）

**T1（4）**
| id | 机型 | 技能名 | 轴 | scope | 效果（数值定稿） |
|---|---|---|---|---|---|
| sig_f15 | F-15 Eagle | 无败之鹰 | 斗士(+骑士进度1) | 通用 | HP 全满时：机炮伤害 ×1.20、锁定速率 ×1.20（逐机判定） |
| （f14_squad_lock_slow） | F-14 Tomcat | 围猎 | 策士 | squad_once | 既有"群猎注视"改名+改档：全僚机共同锁定的敌机持续 SLOW；稀有度 实验→机密 |
| sig_a6e | A-6E Intruder | 盲飞入侵 | 斗士(+策士进度1) | 通用 | 低空（LOW 档）时敌方对本机锁定速率 ×0.60 |
| sig_mirage3 | Mirage III | 幻影 | 策士 | 通用 | flare 保护窗（锁定豁免+导弹穿透窗）时长 ×1.6；flare 成功偏转导弹瞬间 1.5s 无敌（no_refresh） |

**T2（16）**
| id | 机型 | 技能名 | 轴 | scope | 效果（数值定稿） |
|---|---|---|---|---|---|
| sig_mirage2000 | Mirage 2000 | 静不稳定 | 斗士 | 通用 | 永久 max_g +2、滚转率 ×1.30（直改 params，AI 经 effective_* 自动感知） |
| sig_f15c | F-15C | 制空清扫 | 骑士 | 通用 | 雷达锥内每多 1 架敌机，本机锁定速率 +8%（≤+40%，即 5 架封顶） |
| sig_f15e | F-15E | 对地特化 | 斗士 | 通用 | 对地面/舰船单位：锁定速率 ×1.5、所有伤害 ×1.30 |
| sig_fa18e | F/A-18E | 甲板周转 | 骑士 | 通用 | 每次机场/航母停靠离开：机炮+导弹装填至上限 2 倍（耗完不回超）；max_hp 永久 +10（累计 ≤+50） |
| sig_ea18g | EA-18G Growler | 伴随压制 | 策士 | squad_once | 至少 1 名僚机存活，且全体存活僚机共同满锁同一敌方目标时，该目标持续获得 JAM；共锁解除后停止刷新 |
| sig_f16 | F-16 | 智能鹰 | 策士 | squad_once | XP 获取 ×1.25（独立乘区，可与 xp_mult 叠乘；功勋随 XP 结算自然放大） |
| sig_gripen_c | JAS 39C | 公路机场 | 策士 | 通用 | 未被任何敌人锁定时，加力槽充能速率 ×1.5（ACE 充能账本按 ACE 是否被锁判） |
| sig_su27 | Su-27 | 急停机动 | 斗士 | 通用 | 前置：持有特殊机动技（眼镜蛇/破 S 任一）。特殊机动完成瞬间对 1500m 内敌机施加 FEAR 4s |
| sig_a10 | A-10 | 钛浴缸 | 斗士 | 通用 | HP<30% 时受到的致死伤害改为保留 1 HP + 1.5s 无敌；内置 CD 60s |
| sig_rafale | Rafale | SPECTRA | 策士 | 通用 | flare 成功偏转一枚导弹后，对该导弹发射者施加 JAM 5s |
| sig_tornado | Tornado IDS | 地形跟随 | 斗士 | 通用 | 低空（LOW 档）时：极速/巡航 +8%、加力槽充能 ×1.5（游戏无低空速度惩罚，上翻为低空增速——偏差已注 §2.3） |
| sig_typhoon | Typhoon | 超巡爬升 | 骑士 | 通用 | 高度调整速率 ×1.5；爬升不再削目标速度（豁免爬升速度惩罚）；高度调整进行中机炮闪避 +30%（与既有 dodge 合并后走全局 85% 封顶） |
| sig_su34 | Su-34 | 鸭嘴兽厨房 | 斗士 | 通用 | 加力窗口激活期间每秒回复 2 HP |
| sig_viggen | AJ 37 Viggen | 唯一的锁定 | 策士 | 通用 | 我方对目标的锁定在其脱离雷达锥后保持 3s 不衰减（宽限窗）；雷达距离 +500m |
| sig_mig31 | MiG-31 | 超速截击 | 骑士 | 通用 | 加力窗口内对**当前同时位于机头前半球（偏轴 ≤90°）与本机雷达锥内**、已满锁且在包线内的目标每 1.2s 自动发射 1 枚导弹（唯一绕开窗口禁火的通道）；雷达锥即使被扩至 >90° 也不得覆盖后半球，离锥后的残留满锁/锁定宽限同样不得触发；该弹初速/极速 ×1.3 |
| sig_harrier | Harrier GR.7 | VIFFing | 斗士 | 通用 | 减速效率 ×1.5；速度降至 200 km/h 以下瞬间获得 4s 无敌（内置 CD 20s） |

**T3（8）**
| id | 机型 | 技能名 | 轴 | scope | 效果（数值定稿） |
|---|---|---|---|---|---|
| sig_f15smtd | F-15 S/MTD | 矢量鸭翼 | 骑士 | 通用 | 永久 max_g +2（转弯半径应声收紧 ≈−30%）；拉 G 掉速惩罚 ×0.65 |
| sig_su35 | Su-35 | 落叶飘 | 斗士 | 通用 | 前置：持有特殊机动技（任一）。特殊机动完成瞬间获得 6s 无敌 |
| sig_f35 | F-35 | 传感器融合 | 策士 | squad_once | 僚机可对 ACE 满锁的目标直接发射导弹（豁免自机雷达锥/锁定门；包线与发射窗口质量照查） |
| sig_gripen_e | JAS 39E | 电战预算 | 策士 | 通用 | 免疫一切负面状态（JAM / SLOW / FEAR） |
| sig_f22 | F-22 | 先敌开火 | 骑士 | 通用 | 前置：持有任一隐身来源技。进入 STEALTH 瞬间全武器立即装填完毕（机炮弹回满/导弹装填清零/电磁炮 CD 清零）；STEALTH 期间导弹锁定目标数 +2（加算） |
| sig_su57 | Su-57 | 多波段搜索 | 策士 | 通用 | 雷达锥半角 +40°（本技能允许突破常规 90° 上限，封顶 120°） |
| sig_j20 | J-20 | 霹雳长矛 | 骑士 | 通用 | 导弹挂载 +1、导弹射程 ×1.40、导弹生存时间（燃烧+滑翔寿命）×1.5 |
| sig_a12 | A-12 | 不被期待的计划 | 斗士 | 通用 | 被击坠瞬间原地复活：HP 恢复至 30% + 2s 无敌（每局一次，逐机各一次） |

**T4（7）**
| id | 机型 | 技能名 | 轴 | scope | 效果（数值定稿） |
|---|---|---|---|---|---|
| sig_yf23 | YF-23 | 落选者 | 策士 | 通用 | 每次从机场/航母起飞（停靠结算离开）获得 20s STEALTH |
| sig_f47 | F-47 NGAD | 忠诚僚机编队 | 斗士 | squad_once | 立即获得 2 架永久忠诚僚机（无离屏消散、无时限；阵亡不补） |
| sig_mig41 | MiG-41 | 近太空冲刺 | 骑士 | 通用 | HIGH 档时敌方对本机锁定速率 ×0.60；从 HIGH 档开始降高瞬间获得 8s OVERLOAD + 俯冲期间加速度 ×1.5（触发 CD 30s） |
| sig_faxx | F/A-XX | 穿透打击 | 斗士 | 通用 | 本机以机炮完成击杀后获得 5s STEALTH；内置 CD 20s，CD 内击杀不刷新；导弹、僚机与其它伤害来源不触发 |
| sig_fcas | FCAS NGF | 作战云 | 策士 | squad_once | ACE 获得的 OVERLOAD/BLOODLUST/STEALTH/INVINCIBLE 同步施加给全队（已有者刷新时长） |
| sig_gcap | GCAP Tempest | 联合突击 | 骑士 | 通用 | 每有 1 名僚机存活：导弹挂载 +1、雷达距离 +5%（≤4 层；僚机阵亡即时重算收回） |
| sig_j36 | J-36 | 三发推力 | 斗士 | 通用 | 下达【突击】命令（攻击轮盘 ASSAULT / 双击攻击线）后：max_g +2、加/减速 ×1.4、滚转 ×1.3，直至该命令目标被消灭或命令解除；重新触发 CD 15s |

**T5（8）**
| id | 机型 | 技能名 | 轴 | scope | 效果（数值定稿） |
|---|---|---|---|---|---|
| sig_x09 | X-09 | 夜枭 | 骑士 | 通用 | 我方每枚导弹发射时 40% 概率成为"静默弹"：目标敌机对其无警觉（不规避、不投 flare；BOSS 不豁免） |
| sig_x13 | X-13 | 全频段压制 | 策士 | 通用 | 被我方任一单位锁定的敌人，其身上的负面状态倒计时流速 ×0.60（等效持续 +67%） |
| sig_x02 | X-02 Wyvern | 突击翼龙 | 斗士 | squad_once | 立即将电磁炮收入武器库（已有则跳过）；电磁炮最短射程清零、充能时间 ×0.70 |
| sig_x21 | X-21 | 超越地平 | 骑士 | 通用 | 我方导弹被 flare 偏转后不再失效：直飞 2s 后在导引头视野内重新索敌并继续制导（每弹一次）；导弹生存时间 ×2 |
| sig_x44 | X-44 | 高速炮艇 | 斗士 | 通用 | 机炮射界设为正面 180°（半角 90°，不与其它射界加算）；普通机炮与机炮吊舱子弹可贯穿多个目标，同一发对同一目标最多伤害一次 |
| sig_x77 | X-77 | 引渡人 | 策士(+骑士进度1) | 通用 | 导弹击杀敌机后进入 5s STEALTH |
| sig_x90 | X-90 Skywhale | 鲸群 | 策士 | squad_once | 每 25s 自动生成 1 架忠诚僚机（本技能来源的存活 ≤3）；血量共享光环：1500m 内任一友军受伤时，伤害由圈内全体（含 ACE）均摊 |
| sig_ax00 | AX-00 | 双子星 | 斗士(+骑士进度1,+策士进度1) | squad_once | 立即复制 1 架同型僚机入队（受编队上限 9 约束，满编则放弃）；新僚机自动重放全队 build（"复制技能"） |

### 2.3 语义精化与偏差说明（逐条歧义裁定）

1. **围猎（f14）**：即 720 批 `f14_squad_lock_slow`（集火枷锁→群猎注视）。本批动作=改名"围猎"（三语）+ 稀有度 实验→机密。效果不动。
2. **地形跟随（tornado）**：原文"低空飞行时速度没有惩罚"——当前游戏**不存在**低空速度惩罚机制（只有爬升惩罚与低空杂波难锁），
   该半句落地为"低空反而更快"（+8%），保留原文意图的"低空突防"风味。
3. **甲板周转（fa18e）**：过量装填=离开停靠点时一次性填到 2×上限，战斗中耗掉不回超；装填计时正常（装填回到 1×上限为止）。
   HP +10 每次停靠离开累计，封顶 +50（防机场反复横跳无限膨胀）。
4. **伴随压制（ea18g）**：复用围猎的“全部存活僚机共同满锁同一目标”集合求交口径，至少 1 名僚机；只把持续施加状态从 SLOW 改为 JAM。目标不再满足时不清除既有 JAM，只停止刷新。
5. **穿透打击（faxx）**：击杀归因必须为 `kind == "gun"`，并由持有该技能的击杀机自身获得 STEALTH；20s 冷却逐机记账，冷却期间不刷新隐身。导弹、QMAAM、僚机及第三方击杀均不触发。
6. **超速截击（mig31）**：只打破主导弹单发路的窗口禁火；机炮/火箭/齐射照旧禁。自动发射条件=满锁+包线内+导弹 CD 好。
7. **特殊机动前置（su27/su35）**：`requires_skill` 至少持有 眼镜蛇（cobra_skill）或 破 S 规避（herbst 系）之一；
   "机动完成瞬间"=机动状态机相位回落到 NONE 的下降沿（新增统一钩子）。
8. **先敌开火（f22）**：`requires_skill` 至少持有任一 STEALTH 来源技（弹后潜匿/刺客复仇；后续隐身来源入池自动扩列）。
   "进入隐身"以 STEALTH 状态上升沿判定，来源不限（作战云广播/落选者起飞隐身同样触发）。
   STEALTH 期间的锁数是在当前有效永久锁数上加 2，不设固定下限、不替换其它来源；齐射仍受正常冷却约束。
9. **钛浴缸 vs 复活（a10/a12）**：共用同一"致死拦截"底座。钛浴缸=HP<30% 才生效、保 1 HP、CD 60s 可反复；
   A-12=无血线前提、直接回 30% HP、每局每机一次。两者同机时钛浴缸先判（CD 好则先保 1，复活留底）。
10. **作战云（fcas）**：广播源=ACE 获得四类增益瞬间；广播用 max 模式（已有者=刷新到更长者）；防递归（广播落地不再二次广播）。
11. **鲸群（x90）**：均摊后每机伤害 = 原伤害 ÷ 圈内友军数（含承伤者），逐机走各自减伤管线；均摊出去的份额不再二次均摊。
12. **静默弹（x09）**：静默标记在导弹生成时 roll 一次；敌机来袭导弹检测/规避/投 flare 全部无视静默弹（等于看不见）；
    对 ace/BOSS 同样生效（其 flare 命数被绕过属预期强度，playtest 观察）。
13. **全频段压制（x13）**：判定=该敌机 `locked_by` 含任意我方单位；负面状态=FEAR/JAM/SLOW。
14. **双子星（ax00）**：复制的是"同机型僚机 + 全队 build 重放"（入队补挂机制现成）；不复制签名技能的 squad_once 账本（全队共享本就生效）。
15. **智能鹰（f16）**：独立乘区不占 xp_mult 的 ×1.4 硬顶（两者叠乘上限 1.4×1.25=1.75）。
16. **锁定速率类表述**：本 spec"锁定速率 ×N"=照射进度累积速度乘 N（等效锁定时间 ÷N）；"敌方锁定速率 ×0.6"=敌人锁我更慢。
17. **高速炮艇（x44）**：正面 180° 是绝对射界而非在现有角度上加 180°；若炮艇模式已提供 360°，不把射界缩窄。贯穿只作用于普通机炮/机炮吊舱，不作用于 CIWS；一发子弹以命中目标集合防止对同一目标重复伤害。

## 3. 行为与公式（How）

### 3.1 获取与继承流

```
亲自驾驶机体 → 功勋商店揭示该机专属许可 → 购买
机场停靠 → 保留当前机并装备专属技 / 进化机体（二选一）
保留装备 → upgrade_stacks[signature_id] = 1（玩家层账本）→ 不发普通 +1 轴点 → milestone_plus 照常兑现
进化换机 → _replay_player_upgrades 无条件重放（不查 exclusive_to）→ 技能延续到新机
```

### 3.2 致死拦截（钛浴缸/复活共用）

```
_apply_damage 结算后 hp ≤ 0 时（按序判定，命中一条即止）：
  1. sig_a10 且 拦截 CD 就绪 且 受击前 hp/max_hp < 0.30 → hp=1，无敌 1.5s(no_refresh)，CD=60s
  2. sig_a12 且 本机本局未用过 → hp = 0.30×max_hp，无敌 2s(no_refresh)，标记已用
  否则照常坠机
```

### 3.3 条件态注入点分类（复用 CLAUDE.md 机动 buff 规范）

| 类别 | 技能 | 注入点 |
|---|---|---|
| 永久 params（类别 1） | 静不稳定 / 矢量鸭翼 / 霹雳长矛 / 多波段搜索 / 唯一的锁定(+500m) / 甲板周转(+HP) | apply_upgrade 直改 params |
| 状态 accessor（类别 2） | 三发推力 / 地形跟随(+速) / VIFFing(减速) / 近太空冲刺(俯冲加速) | aircraft_physics effective_*() 各 ≤5 行 if |
| 锁定管线 | 无败之鹰 / 制空清扫 / 对地特化 / 盲飞入侵 / 近太空冲刺(高空) / 唯一的锁定(宽限) | 锁定循环 `_lock_rate_for_target` 一处集中注入 |
| 事件钩子 | SPECTRA / 引渡人 / 急停机动 / 落叶飘 / 落选者 / 甲板周转(补弹) / 先敌开火 / 作战云 | SkillHooks 既有 dispatch + 3 个新事件（机动完成 / 起飞 / STEALTH 上升沿） |
| 每帧条件判定 | 幻影 / 鸭嘴兽厨房 / 公路机场 / 超巡爬升 / 钛浴缸 / 电战预算 / 全频段压制 | 各所属 update/tick 内 O(1) 字段读 |
| 新行为 | 超速截击 / 传感器融合 / 夜枭 / 超越地平 / 高速炮艇 / 忠诚僚机编队 / 鲸群 / 双子星 / 突击翼龙 | §6 批 C 逐条 |

## 4. 结构与组成（Structure）

- **数据层**：UPGRADES 表共 42 条 `sig_*`（+`f14_squad_lock_slow` 改档）；每条带 `axis`/`exclusive_to`/`rarity: CLASSIFIED`/`scope`/`milestone_plus`。
- **milestone_plus 扩展**：字段允许 `String` 或 `Array[String]`（ax00 双轴）；发放点循环发放，cap=2 语义不变。
- **钩子层**：`skill_hooks.gd` 新增 `on_special_maneuver_done` / `on_takeoff` / STEALTH 上升沿分发；flare 偏转钩子 `on_evade_missile` 复用。
- **拦截层**：`aircraft.gd` 致死拦截（§3.2）；`combat_unit.apply_status` 负面免疫早退 + 作战云广播。
- **武器层**：超速截击（窗口禁火豁免通道）/ 夜枭（导弹静默标记）/ 超越地平（jam 后 retarget）/ 高速炮艇（正面 180° 绝对射界 + 普通机炮贯穿）/ 传感器融合（发射门豁免）。
- **生成层**：忠诚僚机编队 / 鲸群（drone 持久化标记 + 周期生成）/ 双子星（同型僚机入队+build 补挂，复用既有奖励僚机路径）。

## 5. 验收标准（Acceptance / Litmus）

- [x] 身份约束：`exclusive_to` 仍确保 43 条映射与机型一一对应；机场许可与二选一验收见 `aircraft-signature-progression` ✅
- [x] 继承：升级账本记玩家层 + `_replay_player_upgrades` 无条件重放（既有机制，bench attr_gates §E 重放断言覆盖底座；params 类 apply 断言 §D）✅
- [x] milestone_plus 数组：ax00 双轴 list、单值口径兼容（bench §C；cap=2 语义不变——沿用 skills720 §C 双计数断言）✅
- [x] 致死拦截：钛浴缸 CD/血线、A-12 每局一次、共存判序（bench §E 8 断言）✅
- [x] 窗口禁火豁免：sig_mig31 走独立发射通道（不经 `_fire_missile_at` 硬断），其余武器路径六处禁火未动 ✅
- [x] 超速截击发射几何：只从当前机头前半球与雷达锥的交集挑选目标；后半球满锁即使仍落在扩宽至 ±120° 的雷达锥内且距离更近也不得发射（bench `sig_skills` 对照通过）
- [x] 全表 i18n 三语齐；重跑 dump_skill_table → 当前 158 条，milestone_plus 数组已兼容 ✅
- [x] 性能：全部判定 O(1) 字段读 / 复用既有 tick（锁定循环集中注入、0.5s squad watch、25s 周期生成）；无新增每帧扫描 ✅
- [x] 传感器融合行为门：技能关闭/ACE 未满锁/非 ACE 当前目标均拒绝；ACE 满锁同目标时僚机越肩门放行（bench `sig_skills` §J）✅
- [x] F-22 加算锁数、全队范围、超速截击正面发射门与机场渠道隔离由 `sig_skills` 75/75 覆盖。
- [x] **机场二选一（2026-08-26）**：已购许可时保留当前机可立即装备；进化后本次停靠关闭，不能双拿；普通池无专属泄漏
- [x] **机场 UI**：专属框洋红 2 px + 0.10 alpha 底色，与白色进化框、三轴量表不撞色；43 机详情均展示对应专属技
- [ ] playtest：出现率手感 / 各条数值调档 / Sentinel+Lv5 压测（⏳ 用户实机）

## 6. 任务拆分（依赖序）

- [x] **S0 底座批**：milestone_plus 数组化 + `f14_squad_lock_slow` 改档改名"围猎" + 40 条表条目 + i18n 三语。✅ 2026-07-22（卡面签名角标缓做——归属角标机制已有，专属标识随 playtest 反馈定）
- [x] **S1 纯数据/单点注入批**：14 条全落地（锁定管线集中注入 `_update_radar_locks`；对地伤害两处：bullet_manager + missile_manager）✅ 2026-07-22
- [x] **S2 钩子批**：14 条全落地（新事件点三个：机动完成 `on_special_maneuver_done` / 起飞=停靠结算关闭分支 / STEALTH 上升沿=apply_status 覆写快照）✅ 2026-07-22
- [x] **S3 新行为批**：9 条全落地（超速截击独立发射通道 / f35 越肩发射两门豁免 / 夜枭静默弹一处过滤全覆盖 / x21 重索敌 / 作战云中继直通防双乘）✅ 2026-07-22
- [x] **S4 生成批**：3 条全落地（f47/x90 drone 刻意不进 `_alive_drones` 离屏 despawn 体系=天然永久；ax00 复用 `_spawn_reward_wingman` + 入队 build 补挂）✅ 2026-07-22
- [x] **S5 收尾**：bench sig_skills 47 断言 + 回归门 34 项 + 表重生成（生成器 milestone_plus 数组化）+ 锚点修复 35 处 + verify 双脚本绿 + changelog。✅ 2026-07-22

## 7. 索引锚点（Where —— 纯文件指针，行号见 reference 索引）

| 关注点 | 位置 |
|---|---|
| 数据表 42 条 `sig_*` + F-14 围猎特例 + milestone_plus_list_of + 43 机映射/判别式（`signature_upgrade_id_for_aircraft` `is_signature_upgrade`） | `scripts/survivor/survivor_data.gd`（表尾 722 段） |
| 机场洋红专属框 / 逐机专属详情 | `scripts/survivor/evolution_ui.gd` / `scripts/survivor/evolution_detail_panel.gd` |
| apply 专用分支（8+10 条）+ sig_xp_mult | `scripts/survivor/survivor_player.gd`（match 尾 722 段） |
| 事件钩子（机动完成/引渡人/三发推力/作战云/鲸群均摊） | `scripts/survivor/skill_hooks.gd`（722 段：`on_special_maneuver_done` `try_trigger_j36_assault` `broadcast_combat_cloud` `whale_pod_share` + 静态账本位） |
| 签名字段块 / 技能 tick / 致死拦截 / STEALTH 上升沿 / 超速截击通道 / effective_max_locks | `scripts/aircraft.gd`（`_update_sig_skills` `_try_sig_death_save` `_sig_f22_reload_all` `_sig_mig31_pick_target`） |
| 负面状态免疫早退 | `scripts/combat_unit.gd`（apply_status 头部） |
| 全频段压制流速 | `scripts/status_effects.gd`（tick + `sig_x13_active`） |
| 锁定管线集中注入 + viggen 出锥 grace | `scripts/survivor/survivor_mode.gd`（`_update_radar_locks` 722 段） |
| 获得点特判 / gcap 重算 / x90 周期 / 起飞钩子 / 充能倍率 | `scripts/survivor/survivor_mode.gd`（`_dispatch_sig_oneshot` `_update_sig_gcap` `_sig_spawn_loyal_drone` `_spawn_reward_wingman` `_on_settlement_closed` 722 段） |
| f35 越肩发射 / f22 齐射消费点 | `scripts/aircraft/aircraft_weapons.gd`（`_sig_f35_relay_ok` + effective_max_locks 三处） |
| flare 窗口/幻影/SPECTRA | `scripts/aircraft/aircraft_flares.gd`（release 722 段） |
| 夜枭/超越地平弹标记 + 重索敌 | `scripts/missile_manager.gd`（spawn 打标）/ `scripts/missile.gd`（`_sig_find_retarget`）/ `scripts/ai/missile_evasion.gd`（silent 过滤） |
| physics 注入（typhoon/j36/mig41/tornado） | `scripts/aircraft/aircraft_physics.gd`（update_speed/update_altitude/effective_* 722 段） |
| 机动完成事件发射点 | `scripts/cobra_maneuver.gd` / `scripts/herbst_maneuver.gd`（phase→NONE 处） |
| 加力充能倍率入参 + 窗口回血 | `scripts/survivor/afterburner_charge.gd`（update rate_mult） |
| 验收 bench | `scripts/tests/test_sig_skills.gd`（`--bench=sig_skills`，75 断言；随 `--bench=all` 回归门） |
| 生成器（milestone_plus 数组兼容） | `tools/dump_skill_table.py` → `docs/reference/skill-table.md`（当前 158 条） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-26 | 9 | 用户改案：43 条专属技能全部退出等级抽选、奖励卡与战区奖励池；机场停靠改为“保留当前机并装备专属技能 / 进化”二选一，新增洋红留机卡、白色进化卡与逐机详情陈列，普通升级 UI 固定三卡。 |
| 2026-08-04 | 7 | 用户订正：X-44 高速炮艇改为正面 180°绝对射界（不加算），并让普通机炮/机炮吊舱子弹贯穿；AX-00 双子星由 3 架改为 1 架同型僚机。 |
| 2026-08-03 | 6 | **超速截击正面发射门**：目标除满锁/包线外，必须同时位于机头前半球（偏轴 ≤90°）和当前雷达锥；即使“多波段搜索”将雷达扩至 ±120°，后方 90°~120° 仍禁止发射；离锥后的残留满锁（含“唯一的锁定”宽限）也不得触发。同步卡面三语，并给 `sig_skills` 增加宽锥下正/后半球回归。 |
| 2026-08-01 | 4 | F-22“先敌开火”从等效多重齐射开关改为 STEALTH 期间导弹锁定目标数 +2（加算），接入统一锁数机制。 |
| 2026-07-28 | 3 | **出率乘区 + 卡面专属边框（§2.1.1）**：①`sig_*` 新增 **×2.5 签名技权重乘区**（基础 CLASSIFIED 0.08 → 等效 0.20 ≈ ADVANCED 档），**轴内抽卡与三选一两条路径都生效**；刻意不改稀有度档位（稀有度还挂着徽章/奖励池/门控多重语义），只动抽取权重=最小单杠杆；抽卡加权与卡面高亮共用同一判别式（id 前缀 `sig_`）。②卡面新增**洋红专属边框** `(1.00, 0.25, 0.75)`：边框加粗一档 + 0.16 alpha 同色底；**刻意避开五档稀有度色与三轴色**（斗士琥珀/骑士青绿/策士紫），三条信息各占一个视觉通道；**稀有度徽章仍显示真稀有度**。理由=签名技是"开过这架机才拿得到"的核心承诺，旧出率下一局常常零刷出，承诺兑现不了 |
| 2026-07-22 | 2 | S0~S5 全量落地（工程闭环）：①40 条入表 + 围猎改档改名 + i18n 三语 80 键；②milestone_plus 数组化（发放循环 + 生成器兼容）；③锁定管线集中注入 6 技 + viggen 出锥 grace（per-pair 冻结窗）；④致死拦截底座（钛浴缸/复活共用判序）；⑤三个新事件点（机动完成/起飞/STEALTH 上升沿）；⑥超速截击=绕窗口禁火的独立发射通道（duplicate params ×1.3 弹速）；⑦作战云中继直通（cloud_relaying 守卫防 OVERLOAD 乘区双乘/防递归）；⑧f35 越肩发射（锥门+锁定门豁免、包线/窗口质量照查）；⑨夜枭静默弹（missile_evasion 单点过滤覆盖规避+投焰）；⑩x21 被偏转重索敌（2s 直飞 + FOV 内 TEAM_HOSTILE 最近）；⑪f47/x90 drone 不进离屏 despawn 体系=天然永久、ax00 复用奖励僚机管线；⑫**顺手修复既有缺口：`_apply_build_to_new_member` 零调用（720 T1 缺口②漏接线）——现挂 `_spawn_reward_wingman` 尾部，奖励僚机/双子星克隆均吃全队 build**；⑬x44 直改 params 锥角（全消费点自动生效）+ aim_assist cap 防倒退；⑭typhoon 闪避走全局 85% cap（§2.2 的"70%"上翻为全局 cap 兜底，与其余 dodge 技能一致）。验收：sig_skills 47 断言 + 回归门 34 项 PASS + 锚点修复 35 处 + verify 双脚本绿；余 playtest（§5 末条）。 |
| 2026-07-22 | 1 | 初稿：结构化用户 722 表——41 机签名技能全表数值定稿；系统规则（驾驶门控/CLASSIFIED/换机继承/轴+milestone_plus 数组化）；歧义裁定 14 条（§2.3）；实现分档 S0~S5。设计源=用户，数值细化=Claude（保守值，playtest 调）。 |
