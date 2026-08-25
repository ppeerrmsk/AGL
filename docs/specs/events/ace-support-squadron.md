---
id: ace-support-squadron
kind: event
status: in-progress         # 代码主体落地 + parse/ace_tier 回归绿；差 §5 playtest
schema_version: 1
spec_version: 12
owner: noelu（设计输入）/ Claude（细化 + 落地）
depends_on: [ace-squadron-tier, event-system, survivor-loop, reinforcement-ingress]
reconstruction_complete: true
---

# 王牌中队 MARATHON / 马拉松（Su-35 ×5）—— 敌军支援事件（全灭 = 局时 +1 分钟）

> 玩家视角：战局中段，无线电里响起陌生的敌方声音——"发现目标，准备开始交战。"
> 5 架金色涂装的王牌从你面前的地图边缘压进来，锁的就是你。打不打随你：不打，它们咬住
> 不放；全部击坠，整局游戏时间延长 1 分钟，外加一笔厚 XP。

## 1. 设计意图（Why）

- **用户需求（2026-07-22）**：4-5 架高级飞机组成"王牌中队"，从地图边缘飞入、直接锁定玩家；
  战术面板明确显示"敌军支援"；全部击坠后整局游戏时间延长 1 分钟。
- **tier 落位**：这是 [ace-squadron-tier](../systems/ace-squadron-tier.md) 定义中
  "生存模式中途定期登场的强敌 / 中 BOSS"（非 BOSS 王牌中队）的**第一个实例**。
  BOSS ⊂ 王牌中队，本事件严格弱于同期 BOSS（该 spec §3.6 铁律）。
- **激励对齐**：王牌 `aggression ≥ 0.9`、永不脱离——**不杀它就一直被咬**；全灭 = +60 s
  成长窗口 + 500 XP。没有"养着不打"的钻营空间，奖励方向与压力方向一致。
- **Litmus 自检**：
  - 信息察觉（原则 3）：专属涂装色 + 入场无线电台词（`ace_spawn`）+ 次级提示条 + Tab 标记 +
    FLR 计数（那次 flare break 尝试是否用掉）；红色警告横幅**不用**——那是 BOSS 专属（tier §2.6）；
  - 一击毙命（原则 1）：**本体一发死**（HP≤cap，不豁免——除 BOSS 外都一击必杀）；防御只有 1 次高成功率 flare break 尝试，动作失败或近距追上时首发也能命中；
  - 战场热闹（原则 7）：中段强敌事件，与战区任务/拦截波叠出多线压力；
  - 时间奖励可感知：HUD 战区倒计时当帧 +1:00 跳变，无隐形数值。
- **反模式规避**：无等级缩放（tier 铁律）、无护盾/阶段转换等二阶机制、不占 token 不挤兑
  常规刷怪预算。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 编成与 tier 参数

| 字段 | 值 | 说明 |
|---|---|---|
| 编成 | **Su-35 × 5**（长机 + 4 僚机） | 非 BOSS 天花板 Gladiator（TVC 矢量机动可感知）；固定编成保证"看到即认识" |
| **战术风格** | **斗士 `gladiator`**（tier §3.7 风格库） | 一队一套战术：全员 PURSUIT 死死扑向玩家操控机缠斗。本队是风格库斗士位的实例；反制答案见风格表 |
| tier | `tier = "ace"`（按**实例** AceTier.mark 打标） | **禁止**把 SU35 机型整体划为王牌——普通旅途仍会刷杂兵 Su-35，tier 待遇只跟本事件实例走 |
| tier 待遇 | LOD 豁免 / 无等级缩放 / `skip_far_cleanup` / armor 0 | 全套引 ace-squadron-tier §2.1 |
| aggression | 0.95 | ≥0.90 门槛（对齐 AceSquad._apply_role 既有王牌值） |
| 角色分配 | KNIGHT ×2 + SNIPER ×3 | 沿用基类"前 2 架 KNIGHT"静态规则（机炮近战 / BVR 站位） |
| engage_duration / cooldown | 999 / 0.5 | 永不自动脱离 |
| skill_level / composure / focus / situational_awareness | 王牌级（ace_combat 档） | 经 _apply_role 写入 |
| 涂装 | ~~金橙 #FFB000~~ → **猩红 `#FF2E3D`**（2026-07-27 包装批：王牌 color code 一律紫/红系，tier §2.7 主色表） | 与杂兵 Su-35 一眼区分（原则 3；普通 Su-35 为标准敌方暖色橙，猩红是更高一档威胁色） |
| 机炮闪避 | **基线档 0.20**（tier §2.2 分档，注入 `bullet_dodge_chance`） | 2026-07-27 用户定档：全体王牌具备一定机炮闪避；本队无难缠档个体 |
| token | 0，不占预算；不占 hunter 配额 | 事件供给（自身就是全职猎手） |

### 2.2 生存模型 —— **一发死 + 1 次 flare break 尝试**

> ⚠ **核心原则（用户 2026-07-23）**：**除 BOSS 外，所有空中敌人一发死。** 王牌支援中队
> **不是 BOSS**，故本体一击必杀——`max_hp` 不豁免 `ENEMY_HP_MISSILE_CAP`（≤75），主导弹一发解决。
> 它的"王牌"感来自**行为**（5 架直扑 + 极强 AI + 咬住不放）+ 专属标识 + 全灭奖励，**不是血条/命数**。
> 这纠正了 ace-squadron-tier 早先"非 BOSS 王牌中队也豁免一击必杀"的前提——HP 豁免收窄为 BOSS 专属。

| 字段 | 支援中队（本 spec） | BOSS 档（对照，ace-squadron-tier §2.2） |
|---|---|---|
| `max_hp` | **不豁免 cap（≤75）→ 一发死** | 100（豁免 cap，BOSS 专属） |
| `max_flares` | **1** | 4 |
| `burst_count` | 1 | 1 |
| break 执行成功率 | `0.15 + 0.80 × effective_skill` | 同左；王牌档约 87%–95% |
| `fail_chance` | 0（必定释放） | 0 |
| 补充 | 无（耗尽即防御归零） | 无 |
| 耗尽后 | 不解锁规避机动 | 同 |

**击杀序列（单机）**：本体仍是一发死；那枚 flare 只提供一次 1.25 s 的高成功率 break 尝试。
若真实动作达门且等级判定通过，通常需要第 2 发；若轨迹没变、执行骰失败或导弹在动作前追上，第 1 发即可命中。
完整动作门与概率以 [flare-evasion-coupling](../systems/flare-evasion-coupling.md) 为权威。

### 2.3 火力

- 机炮：专属 `ace_gun.tres`，开火节奏与全部敌方飞机一致：每次机会只打一梭，梭后停火
  3.0s；数值权威在 gun-burst-fire §3.3 与 ace-squadron-tier §2.4/§2.5，不在此重列。
  **本事件落地即带动该 spec 阶段 3+4（flare 命数资源 / jam=1.00 / ace_gun）落地**。
- 导弹：Su-35 档案自带（无等级加弹）。

### 2.4 触发与节奏

| 项 | 值 | 说明 |
|---|---|---|
| 第一波 | `game_time ≥ 210 s`（开局 3:30） | 六队新局洗牌；本队预计 TTK 75 s |
| 第二波 | `WARZONE_PHASE_DURATION - game_time ≤ 180 s` | BOSS 前最后 3:00；按真实战区时长计算 |
| 波间冷却 | 无 | 第二槽占场时待触发，前队终态后立即刷新 |
| 同场上限 | 1 支 | — |
| BOSS 阶段 | 不触发；已在场的转撤离（§3.3） | BOSS 独享舞台 |
| 玩家等级门槛 | 无 | 时间门已隐含成长；一发死本体强度可控 |

一局（600 s + 延长）典型 2~3 支。

### 2.5 奖励

| 项 | 值 | 说明 |
|---|---|---|
| 击杀 XP | **100 / 架**（同 F-47 档） | 全队 500 XP + 既有对头/倍率加成照常 |
| **全灭奖励** | `game_time −= 60`（下限 0） | game_time 向 600 s 阶段闸爬升，−60 = BOSS 推迟 1 分钟 = **整局延长 1 分钟**；与出界补给时间税（+15 s）同一注入语义、方向相反。封装为 `grant_time_extension(60.0)` |
| 反馈 | HUD 战区倒计时当帧 +1:00 跳变 + 横幅通报"敌军支援已歼灭 剩余时间 +1:00" | 信息察觉 |
| 边界 | 撤离中被全灭：XP 照给，**不给**时间奖励（BOSS 阶段 game_time 已冻结，无意义） | — |

### 2.6 入场

| 项 | 值 |
|---|---|
| 入场点 | 玩家 heading ±90° 扇区内的地图边缘点，距玩家 ≥ 5000 px（复用 `INGRESS_MIN_PLAYER_DIST_PX`，与拦截波同一选点算法；看得见来路，30~45 s 接敌；不从身后偷袭） |
| 生成 | 边界外生成、菱形编队、机头指向玩家（复用 AceSquad 边缘入场机制 entry_origin_override） |
| 进场即咬 | spawn 后**立即** engage（PURSUIT：全员锁定玩家机），不做锚点待机相 |

### 2.7 包装（tier §2.7 五件套，2026-07-27 用户定档；文案待用户过目）

| 项 | 值 |
|---|---|
| 中队代号 | **MARATHON / 马拉松**（用户命名） |
| 登场 | 固定两槽候选（开局 3:30 / BOSS 前最后 3:00） |
| 主色 | 猩红 `#FF2E3D` |
| 徽章 | 不闭合的跑道环，缺口处一道终点线竖杠——终点线永远画在猎物坠机的地方 |
| 血条 | 5 段命条，交战开始亮（tier §2.8） |
| 留档 id | `marathon`（全灭入生涯档案） |

**成员固定呼号**（长跑主题；开局 reserve、永不 recycle；均不在 CallsignDB 800 池内）：

| 槽位 | 呼号 | 味 |
|---|---|---|
| 长机 | **PACER** | 配速员——猎杀的节奏由他定 |
| 2 号机 | MILER | 万米选手，中段耐力 |
| 3 号机 | SPRINTER | 终段爆发 |
| 4 号机 | KICKER | 终点冲刺手 |
| 5 号机 | SWEEPER | 收容车——专收掉队的 |

**Lore**（`ACE_SQUAD_MARATHON_LORE`，三语草案）：

- zh：佣兵中队，只接消耗战合同。队规只有一条：**猎物会先累。**保持着 42 分钟不间断
  咬尾追击的战区纪录——那一单雇主付了双倍，因为目标是在第 41 分钟自己栽进海里的。
- en: A mercenary squadron that only takes attrition contracts. One standing rule: *the prey
  tires first.* Holds the theater record — a 42-minute uninterrupted tail chase. The client
  paid double: the target ditched itself into the sea at minute 41.
- ja: 消耗戦の依頼だけを受ける傭兵飛行隊。隊訓はただ一つ——**先にバテるのは獲物の方だ。**
  42分間ノンストップの追撃という戦域記録を持つ。その依頼の報酬は倍額だった。獲物は
  41分目に自分から海へ墜ちたからだ。

### 2.8 已购 F-15 王牌截击支援

| 项 | 值 |
|---|---|
| 权益 | 生涯商店永久商品 `support_ace_f15`；正式局必须已购，非正式局 fail-open |
| 触发 | 本局首次成功生成的轮换池 `AceReinforcementEvent` 立即触发；**每局至多一次**，后续王牌事件不再派队 |
| 编成 | **F-15 ×2**，ALLY 第三方阵营；边界外编队生成，物理飞入战场 |
| 呼号 / 标签 | 固定 `Hound-1` / `Hound-2`；`F-15 Eagle` 的名称后缀缩写后，绿色标签写成 `F-15 E Hound-1/2`，不加 `ALLY-`，呼号本身不得缩写 |
| 雷达 | 仅两架友军实例固定 **3000 m**；敌军 F-15 基础资源保持 5200 m |
| 交战 | 只允许攻击 HOSTILE `Aircraft`，优先锁定仍存活的本事件王牌；不攻击地面单位或舰船 |
| 入场无线电 | Hound-1：“发现猎物了，准备交战”；Hound-2：“收到，我跟在你后面”；scripted 双句、每局只播一次 |
| 收益 | 友军击杀不向玩家结算 XP / 功勋；友机可被击坠，阵亡不补充 |
| 撤离 | 王牌全灭后当帧转 EGRESS；若王牌因 BOSS 闸或弹尽撤退，则在该王牌事件终态时同样撤离 |
| EGRESS | 解除目标与编队、关闭主动交战、开加力飞向最近边界外；飞出边界 800 px 后静默释放。撤离中受击可自卫 5 s，随后继续撤离 |

该权益只绑定**非 BOSS 王牌轮换事件**，不在 Wraith / Poltergeist 等 BOSS 战或 ORION 宿敌
独立事件中触发。理由：它是“敌军王牌增援的对等截击响应”，不能削弱 BOSS 独享舞台，也不
把宿敌事件的单挑语义改成固定四机混战。

## 3. 行为与公式（How）

### 3.1 事件状态机（AceReinforcementEvent）

| 相 | 进入 | 行为 | 退出 |
|---|---|---|---|
| INBOUND→ACTIVE | 调度器触发 | 边缘生成 + 警告横幅 + 全员 PURSUIT 锁玩家（0.5 s 软维护：掉出交战即补回、远距开加力） | — |
| ELIMINATED | 存活成员数 = 0 | `grant_time_extension(60)` + 歼灭通报 + 事件 end | 终态 |
| WITHDRAWING | BOSS 解锁（阶段闸落下）时仍有存活 | 清交战指令 → 直线飞向最近边界点撤离；**途中被伤害 → 恢复交战**（不做无敌逃兵）；再次脱离接触 5 s 后继续撤 | 全员出界外 800 px → 静默释放（无时间奖励），或被全灭（XP 照给，无时间奖励） |

玩家全队覆灭 → 事件随局终止（无特殊处理）。

### 3.2 热诱弹 break 流程

引 ace-squadron-tier §3.1（消耗流程）/ §3.3（等级 + 真实 break）/ §3.4（只在投焰后做局部 break），
本队 `max_flares = 1`。无隐形层（隐形为 F-47 专属，本编成不带）。

### 3.3 通报与面板（"敌军支援"）

> **2026-07-26 演出规范修订（tier §2.6）**：入场的红色 WARNING 闪烁横幅**退役**——那是
> BOSS 专属演出，本队原先的用法调门过高。入场主信号改为**长机无线电台词**。
> `EVENT_ACE_SUPPORT_WARN` key 随之删除。

| surface | 内容 |
|---|---|
| 无线电（入场主信号） | 敌王牌长机说 `ace_spawn`；若本局首次 F-15 支援实际生成，再由 Hound-1 / Hound-2 依次说固定双句（均 scripted 必播） |
| 次级提示条（入场） | `EVENT_ACE_SUPPORT_INBOUND`（`show_temp` 5 s，说明事件与奖励；非警告横幅） |
| 提示条（全灭） | `EVENT_ACE_SUPPORT_DOWN`（"敌军支援已歼灭 剩余时间 +1:00"语义，三语） |
| Tab 战术面板 | 中队存活期间：长机位置画暖色菱形标记 + "敌军支援" 标签（仿 AWACS 圈的画法，威胁色）；全灭/撤离即移除 |
| kill feed / 击坠无线电 | 复用既有击杀链路，不新增专属台词 |

## 4. 结构与组成（Structure）

- **AceReinforcementEvent**（GameEvent 子类）：调度→生成→监护→终态，模板糅合
  AwacsSupportEvent（边缘入场+监护+冷却）与 BossEncounterEvent（AceSquad 派发+全灭检测）。
- **AceSquad 参数化**：现硬编码 `category="boss"` —— 增加非 BOSS 构造开关：不打 boss
  category、tier 待遇一律走 `AceTier.mark()`（正是 ace-squadron-tier §4.1 的要求）。
- **调度器**：survivor_mode 内仿 ALLY 事件（AWACS/护送）的周期调度，遵守 §2.4 门槛。
- 不新增每帧全场扫描：全灭检测骑事件 tick 的存活过滤（既有 AceSquad.update 模式）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **击杀序列**：对单架王牌连射导弹：投焰后不立刻失导；有效 break 成功时第 1 发偏飞，
      保持原轨迹、执行失败或近距提前追上时第 1 发命中**即死**（HP≤75）
- [ ] **全灭奖励**：击坠全部 5 架瞬间，HUD 战区倒计时 +1:00 跳变 + 歼灭横幅；BOSS 到来
      推迟 60 s
- [ ] **进场可读**：长机 `ace_spawn` 无线电台词必定播出（**无**红色警告横幅）+ 次级提示条
      （三语）+ Tab 暖色标记；入场点在玩家前方扇区边缘；专属涂装与杂兵 Su-35 可肉眼区分
- [ ] **直奔玩家**：入场后不绕锚点、不游荡，径直逼近玩家并交战；玩家跑图全程咬住
- [ ] **BOSS 让位**：阶段闸落下时存活王牌转撤离；追杀撤离者会回头应战；出界静默释放
- [ ] **tier 待遇**：LOD 不冻结（离屏仍机动）、Lv1 与 Lv20 参数完全一致、不占 token、
      普通杂兵 Su-35 不受影响（实例打标验证）
- [x] 触发节奏：3:30 第一波 / BOSS 前 3:00 第二波 / 无终态冷却 / 同场 1 支 / BOSS 阶段不触发
- [x] **F-15 权益**：未购正式局不生成；购入后仅在本局首次王牌轮换事件生成 2 架 ALLY F-15，
      固定呼号 Hound-1/2、雷达 3000m，优先攻击本事件王牌且不攻击地面/舰船；友军击杀 0 XP/功勋；
      入场固定双句无线电只播一次；王牌全灭后两机立即物理撤离，阵亡不补，后续王牌事件不再派队
- [ ] 性能：Sentinel + Lv5+ 压测 + 王牌中队在场，FPS 掉幅 < 15
- [ ] i18n：EVENT_ACE_SUPPORT_* 三语；已知 seam 未触碰

## 6. 实现计划（Task Pipeline）

### 阶段 0 — 前置：tier 生存/火力层（= ace-squadron-tier 阶段 3+4，工单在该 spec §6）
- [x] 支援档 flare 资源 `ace_support_flare.tres`（2 命 / burst 1 / fail 0；BOSS 档 4 命资源
      留 wraith-squadron 落地批，避免未经 playtest 连改 BOSS）
- [x] jam=1.00 tier 分支（aircraft_flares 按 AceTier.is_ace 判定，已在）+ 耗尽不规避（无补充）
- [x] `ace_gun.tres` 新建（§2.4 数值）+ 支援中队挂载
- [ ] 机炮占空比 tier 分支（4.0/1.5）——占空比机制位置待查，留待 wraith 批一并做

### 阶段 1 — AceSquad 非 BOSS 化
- [x] 子类 `AceSupportSquad` 覆写 `_configure_spawn` 后处理：category="ace_support"（不打
      boss）、AceTier.mark 实例打标、撤销杂兵等级缩放（HP/机炮/导弹挂载回 base）
- [x] 编成注入：Su-35 × 5 + 金橙涂装（icon_color）+ 角色沿用基类 KNIGHT×2/SNIPER×3

### 阶段 2 — 事件与调度
- [x] AceReinforcementEvent（入场/监护/全灭/撤离，§3.1；managed_units 兜底回收）
- [x] survivor_mode 调度器（§2.4 门槛）+ `grant_time_extension(60.0)` 封装
- [x] 击杀 XP 100/架（_detect_kills 按 AceTier.is_ace 走 F-47 档）
- [x] category 豁免接线：边界纪律 / 绕玩家航点两处 + skip_far_cleanup 天然免 purge/远清

### 阶段 3 — 通报与面板
- [x] 警告/歼灭/撤离横幅 + i18n 三语（EVENT_ACE_SUPPORT_* ×5）
- [x] Tab 战术面板金橙菱形标记 + "敌军支援"标签（存活期间，validity 守卫静态注册表）
- [x] **演出规范修订（2026-07-26，tier §2.6）**：摘除入场红色警告横幅 → 改接长机 `ace_spawn`
      无线电台词；`EVENT_ACE_SUPPORT_WARN` key 删除（横幅专属文案随横幅退役）

### 阶段 3.5 — 包装批（2026-07-27 定档；2026-07-28 实装）
- [x] 涂装金橙 → 猩红；机炮闪避 0.20 注入；归入固定两波轮换
- [x] 固定呼号 PACER/MILER/SPRINTER/KICKER/SWEEPER（reserve_permanent + 免 recycle）
- [x] 血条 5 段 + MARATHON 代号头（跑道环徽章随徽章批）
- [x] 提示条/Tab 改带代号；lore/中文名 i18n 三语
- [x] 全灭留档 `record_ace_defeat("marathon")`（撤离逃掉 ≥1 架不算击破）

### 阶段 4 — 收尾
- [x] debug 生成入口（F5 面板 FormationType.ACE_SUPPORT，走事件调度器同约束）
- [x] 索引同步 + ace-squadron-tier §2.2 命数档位注记
- [ ] §5 验收 playtest 项（命数序列 / +1:00 跳变 / BOSS 让位撤离 / 压力观感）→ status: done

### 阶段 5 — 已购 F-15 王牌截击支援
- [x] `AceReinforcementEvent` 接入 2 架 ALLY F-15 的入场、王牌优先目标与 EGRESS 生命周期。
- [x] 正式局读取 `support_ace_f15` 权益，非正式局 fail-open；补 MetaShop / 事件定向回归。
- [x] 三语商品文案、规格索引与 reference 索引同步。

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 事件类 | `scripts/events/ace_reinforcement_event.gd`（新建） |
| 王牌编队基类 / 非 BOSS 化 | `scripts/survivor/ace_squad.gd` |
| tier 语义 | `scripts/survivor/ace_tier.gd` |
| 调度 / 时间延长 | `scripts/survivor/survivor_mode.gd` |
| flare 命数 / jam 分支 | `scripts/aircraft/aircraft_flares.gd` + 王牌 flare 资源 |
| 机炮资源 | `resources/ace_gun.tres` |
| 横幅 / Tab 标记 | `scripts/survivor/zone_hint.gd` / `scripts/survivor/tactical_map.gd` |
| i18n | `i18n/gameplay.csv` EVENT_ACE_SUPPORT_* 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-23 | 12 | 跟随 flare-evasion-coupling：1 枚 flare 从必躲一发改为 1 次高成功率 break 尝试；投焰后仍可命中，必须真实机动并通过等级判定。 |
| 2026-08-23 | 11 | 调度改为固定 3:30 第一波与 BOSS 前最后 3:00 第二波；取消 150s 终态冷却与 540s 截止。 |
| 2026-08-08 | 10 | 用户澄清标签语义：`Eagle` 等机型名称后缀可缩写，Hound-1/2 呼号必须完整保留；标签定为 `F-15 E Hound-1/2`。Shadow `presentation` 149/149、`zone_air_support` 55/55。 |
| 2026-08-08 | 9 | 用户裁定：F-15 截击支援改为每局仅首次非 BOSS 王牌事件出动；友军实例雷达 5200→3000m，固定呼号 Hound-1/2，入场增加两句固定无线电；绿色标签不再显示 `ALLY-`。Shadow `zone_air_support` 55/55、`chatter` 89/89。 |
| 2026-08-02 | 8 | 删除王牌 4.0s/1.5s 连射占空比约定；跟随全敌机“一次机会一梭、梭后停火 3.0s”安全门。 |
| 2026-08-01 | 6 | 接入统一 240s 新局洗牌轮换与 TTK 预算；MARATHON=10 DU+25s access=预计 75s。 |
| 2026-08-01 | 7 | 新增已购 `support_ace_f15` 响应：每次非 BOSS 王牌轮换入场时派 2 架 ALLY F-15，优先截击该队；王牌事件终态后物理撤离。明确不覆盖 BOSS 与 ORION。`meta_shop` 81/81、`zone_air_support` 46/46；Lv15+Sentinel+46 机压力样本 146 headless FPS。 |
| 2026-07-22 | 1 | 初稿并定稿：用户需求（4-5 架高级机支援 / 边缘入场锁玩家 / 面板"敌军支援" / 全灭 +1 分钟）→ 非 BOSS 王牌中队第一实例；数值细化项见 §9 |
| 2026-07-22 | 2 | **同日代码落地**（阶段 0~4 除机炮占空比）：AceSupportSquad 子类 + AceReinforcementEvent + 调度/XP/豁免/横幅/Tab/debug 全接线；aggression 定 0.95、入场距离定 5000（复用 ingress 常量，§9 相应更新）；parse + ace_tier 20 断言回归绿；status → in-progress 差 playtest |
| 2026-07-28 | 6 | **改档中期**（用户："让 Su-35 在中期才出现"）：首支触发 240 → **320 s**（tier §2.9 中期档）；早期档位让给 2NDWAVE。随实装批一并落地 |
| 2026-07-27 | 5 | **包装批**（tier §2.7~2.9 落位）：正名 **MARATHON / 马拉松**；涂装金橙→猩红（紫红系 color code 定档）；成员固定呼号表（PACER 长机 + 长跑主题 ×4）；徽章（跑道环+终点线）与 lore 三语草案；血条 5 段；机炮闪避基线 0.20；登场时段=早期（与 2NDWAVE 轮换）。文案待用户过目 |
| 2026-07-26 | 4 | **演出规范修订**（tier §2.6 落地）：入场红色 WARNING 横幅退役（BOSS 专属化）→ 入场主信号改为长机 `ace_spawn` 无线电台词（scripted 必播）；`EVENT_ACE_SUPPORT_WARN` key 删除；§2.1 补战术风格标注（斗士 gladiator，tier §3.7 风格库实例） |
| 2026-07-23 | 3 | **一发死重定向**（用户："除 BOSS 外所有空中敌人一发死"）：推翻 §2.2 旧"命数"设计——支援中队 HP **不再豁免**一击必杀（≤75，一发死）、热诱弹 2 命 → **1 枚必定躲**（jam 1.00 + fail 0 保留）；击杀序列 骗 1 发 → 第 2 发死（严格 2 发/架）。**HP 豁免收窄为 BOSS 专属**（修订 ace-squadron-tier 前提）。代码仅两处：`ace_support_flare` max_flares 2→1、`ace_support_squad` 删 `apply_hp`；一般敌人 flare 概率不变。`--import` 待验 |

## 9. 自拍板项（playtest 重点复核）

1. 编成 Su-35 × 5 固定（未做等级带轮换；第二编成留 playtest 后加）
2. 支援档 = **一发死 + 1 次高成功率 flare break 尝试**；ace_gun 强化机炮 +
   撤销等级加弹暂留（打玩家火力，不影响一发死），若太猛可降普通 Su-35 档
3. 触发 240 / 150 / 540 三个时间参数
4. 击杀 XP 100/架（对齐 F-47；若 XP 通胀改 80）
5. 王牌在场时**未**削减普通 hunter 配额——若 playtest 压力爆表（王牌 5 + hunter 3 同咬），
   第一杠杆是"王牌在场时 hunter 配额减半"，列为观察项而非预置机制
