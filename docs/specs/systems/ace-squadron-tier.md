---
id: ace-squadron-tier
kind: system
status: in-progress
schema_version: 1
spec_version: 15
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

> ⚠ **HP 豁免收窄为 BOSS 专属（2026-07-23 用户定档）**：**除 BOSS 外所有空中敌人一发死。**
> 本节的"HP 100 豁免一击必杀 + 多命"是 **BOSS 专属待遇**。**非 BOSS 王牌中队**（王牌支援中队）
> **不豁免** —— HP ≤ cap（一发死）、只 1 枚 flare（见 [events/ace-support-squadron](../events/ace-support-squadron.md) §2.2）。
> 这推翻了早先"BOSS ⊂ 王牌中队都豁免一击必杀"的前提：**豁免只归 BOSS**；非 BOSS 王牌只继承
> tier 的 LOD 豁免 / 无缩放 / 强 AI / jam 1.00（那 1 枚必定躲），血量与命数不继承。
>
> **命数档位**：`max_flares` 按定位分档——**BOSS 档 4 命 + HP 100 豁免**（Wraith 等，本节数值）/
> **支援档 1 枚 + HP 一发死**（非 BOSS）。BOSS 每个耐久维度都严格更强（§3.6）。

| 字段 | 王牌中队（BOSS 档） | 普通敌机（对照） | 说明 |
|---|---|---|---|
| `max_flares` | **4**（BOSS 专属；非 BOSS 支援档 1） | 1 | 热诱弹 = 命数（仅 BOSS 多命） |
| `burst_count` | **1** | 1 | 每次投放 1 枚 → 1 枚 = 1 条命，严格对应 |
| `cooldown` | 1.2 s | 1.2 s | 两次投放最小间隔 |
| `reload_time` | — | — | **不适用**：`enable_flare_reload = false`，耗尽永不补充 |
| 干扰成功率 | **1.00**（必定成功） | 见 `FlareParams` 概率模型 | 见 §3.3 |
| `fail_chance` | **0.00** | 0.05~0.85 按机型 | "对来袭导弹完全不反应"的骰子。与干扰成功率同理由归零（§3.3）——它会让一条命随机蒸发 |
| `head_on_fail_reduction` | **0.00** | 0~0.25 | 同上，`fail_chance` 归零后本项无意义 |
| 投放距离 | **400 m** | 240 m | `nervousness = 0.5` → `lerp(200, 600, 0.5)` |
| 耗尽后行为 | **不解锁规避机动**，下一发导弹必定命中致死 | — | 见 §3.4 |

**flare 统一铁律（2026-08-01 修订）**：王牌中队默认每架 1 枚 flare；偏离必须由
[ace-rotation-balance](ace-rotation-balance.md) 的 60~90 秒击破预算显式证明。当前只有 VULTURE
整队 0 枚（高速追击已支付 40 秒接近成本）。Teacher 已从零 flare 机动规避型改回 1 枚，
不再叠持续导弹规避。BOSS 档仍为 4 枚。

**机炮闪避分档（2026-07-27 用户新增）**：所有王牌中队成员都具备一定程度的机炮闪避；
**特别难缠的机体给更高档**（由该队 spec 声明）。注入点 = 既有 `bullet_dodge_chance`
字段（子弹命中判定时的闪避骰，线性加和、全局 cap 0.85——机制现成，王牌只是首个敌方用户）：

| 档位 | `bullet_dodge_chance` | 适用 |
|---|---|---|
| 基线 | **0.20** | 全体王牌中队成员（默认，不用声明） |
| 高档 | **0.35** | spec 显式声明的难缠机 |
| 特高 | **0.50** | 顶格操控个体（当前 Teacher；只影响机炮命中，不附赠导弹规避） |

与 §1.3"确定性优于概率"的关系：**导弹轴保持确定性**（flare 必躲、命数可数），机炮轴引入
闪避骰是用户显式定档——机炮是持续弹流，单发闪避在弹流尺度上表现为稳定的 DPS 折减，
读感仍可预期，不产生"6 发导弹全被随机骗掉"式的挫败。

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

> 本原则只约束**装备了机炮的编成**。骑士（lancer）风格是显式豁免：纯导弹无机炮（§3.7），
> 其火力表达全在导弹齐射节奏上 —— 无炮是风格定义，不是火力降档。

### 2.5 机炮开火节奏

王牌中队不再以更长连射窗口表达火力优势。所有敌方 `Aircraft` 统一遵守
[gun-burst-fire §3.3](../weapons/gun-burst-fire.md)：“每次火控机会只启动一梭，梭结束/硬中止后
强制停火 3.0s”。王牌优势继续由更优机炮参数、瞄准、机动与编队战术表达，不能靠连续多梭在
玩家无反应窗口内倾泻致死伤害；WhiteTea 等机炮型王牌同样不得豁免。

### 2.6 登场演出标准（2026-07-26 用户定档）

> **红色 WARNING 闪烁大横幅是 BOSS 专属演出，非 BOSS 王牌中队禁止使用。**
> 横幅是"关卡级事件"的信号；王牌中队只是中途强敌，演出调门压过 BOSS 会稀释 BOSS 的登场分量。

非 BOSS 王牌中队的入场提示 = **三件套**（每一件都刻意低调于 BOSS）：

| surface | 内容 | 层 |
|---|---|---|
| **专属无线电台词（入场主信号）** | 王牌长机开口：`ace_spawn` trigger（`scripted` 类，**必定播出**、豁免三层节流、不占冷却账本），从下方王牌专用台词池随机取 **1 条**。说话人 = 长机的**固定呼号**（§2.7，如 PACER / TEACHER / CARRION） | 声音/文本 |
| 次级提示条（**带中队代号**，2026-07-27） | `show_temp` 常规通报条（非警告横幅），格式含代号："王牌中队 [MARATHON] 来袭——全部击坠 +1:00"语义（`_FMT` key，三语） | HUD 次级 |
| Tab 标记 + 专属涂装 | 战术面板威胁标记 + 中队主色涂装（紫/红系，§2.7） | 空间 |

> 第四件（交战后才出现）：**中队血条**，见 §2.8——入场不亮，打起来才亮。

**王牌中队专用台词池**（`ace_spawn`；全部王牌中队共享，随机取 1 条、不连续重复。
新队可扩充带自己风格的行，扩充必须三语齐全）：

| key | zh | en | ja |
|---|---|---|---|
| `RADIO_ACE_SPAWN_1` | 发现目标，准备开始交战。 | Target in sight. Preparing to engage. | 目標発見、これより交戦に入る。 |
| `RADIO_ACE_SPAWN_2` | 全机跟上，猎物只有一个。 | Stay on my wing. We hunt a single target. | 全機続け、獲物は一つだけだ。 |
| `RADIO_ACE_SPAWN_3` | 这片空域由我们接手。 | We are taking over this airspace. | この空域は我々が引き受ける。 |
| `RADIO_ACE_SPAWN_4` | 捕捉到敌长机，各机自由进入。 | Enemy lead acquired. All aircraft engage at will. | 敵編隊長を捕捉、各機自由に突入せよ。 |
| `RADIO_ACE_SPAWN_5` | 让他们见识一下正规军的打法。 | Time to show them how professionals fly. | 正規部隊の戦い方を見せてやろう。 |

规则：

- **单条即可**。多条队内对话序列（`boss_sequences`）是 BOSS 专属 —— 这是"演出分量低于 BOSS"
  在无线电维度的体现。
- 说话人 = 中队长机呼号（`say_unit`），颜色走精英判定（`COL_ENEMY_ELITE`）。
- 音频素材随 radio-chatter 素材批；当前形态为文本 + 电台底噪。
- trigger 结构登记在 [systems/radio-chatter](radio-chatter.md) §3.3；**台词内容权威在本表**。

### 2.7 中队包装（代号 / 固定呼号 / 徽章 / lore / 留档，2026-07-27 用户定档）

> 王牌中队不再是"一波更强的敌人"，而是**有名有姓的角色**。每支中队（含 BOSS）都有一套
> 完整包装：中队代号、成员固定呼号、线框徽章、一段 lore、专属主色、生涯留档。

**五件套定义**：

1. **中队代号（Squad Codename）**：全大写英文 + 中文名（如 MARATHON / 马拉松）。
   出现在：入场提示条（§2.6）、交战血条上方（§2.8）、Tab 标签、生涯档案。英文代号为
   专有名词不翻译，中文名走 i18n（`ACE_SQUAD_<ID>_NAME` 三语）。
2. **成员固定呼号（Fixed Callsigns）**：每架飞机有**固定**的个人呼号（与中队代号是两个
   东西），逐机绑定 squad 槽位、每次登场都一样。**不得与杂鱼重名**：开局
   `CallsignDB.reserve()` 全部王牌呼号（机制现成），且王牌呼号**永不 recycle** 回池
   （王牌阵亡不释放名字——名字属于角色，不属于尸体）。出现在：无线电说话人、kill feed、
   数据标签。
3. **徽章（Emblem）**：线框矢量图形（贴合极简线框美术），每队一个。出现在：交战血条
   代号旁 + 生涯档案页。具体图形概念在各队 spec，本表只登记概念一句话。
4. **Lore**：一短段队史/性格文本（三语，`ACE_SQUAD_<ID>_LORE`）。出现在：生涯档案页
   （击破后解锁全文——先打到它，再认识它）。
5. **生涯留档（2026-07-27 用户定档）**：王牌中队**被全灭后入生涯档案**（CareerArchive，
   类比 BOSS 的 encounter/defeat 记录）：`record_ace_encounter(id)` 入场记一笔、
   `record_ace_defeat(id)` 全灭记一笔；档案页王牌区块显示 代号+徽章+首次击破日期+
   累计击破次数，未击破的队显示为剪影（???）。

**主色规范（2026-07-27 用户定档）**：王牌中队战斗力强，color code 一律用**紫色或红色色系**
（涂装 icon_color + 血条 + Tab 标记 + 提示条重点色同源）。每队一个专属色相，全部落在
紫/红域内且互相可区分；**此定档取代早先"金橙涂装"方案**（Su-35 队现挂的金橙退役）。
与 FactionPalette 的关系：紫/红仍在"敌方 = 暖色威胁域"的延长线上（精英红 `COL_ENEMY_ELITE`
即先例），紫系是王牌专属的新增威胁档——杂兵永远不用紫。

**包装注册总表**（每队详情权威在各自 spec，本表是总览）：

| 代号 | 中文 | 编成 | 风格 | 登场档 | 主色（草案） | 徽章概念 | 长机呼号 | 留档 id |
|---|---|---|---|---|---|---|---|---|
| **MARATHON** | 马拉松 | Su-35 ×5 | 斗士 | **统一轮换窗** | 猩红 `#FF2E3D` | 不闭合的跑道环 + 终点线竖杠 | PACER | `marathon` |
| **2NDWAVE** | 第二波 | F-4E ×1 + F-15 ×4 | 混编（斗士长机 + 骑士学员） | 统一轮换窗 | 电紫 `#B44DFF` | 双叠浪线，后浪高过前浪 | TEACHER | `2ndwave` |
| **ORION** | 猎户座 | 原创机体 Cre ×1（宿敌单机，§3.8） | 斗士（独狼） | **中期（独立轨道）** | **无——伪装普通敌橙**（§3.8 豁免） | 猎户座腰带三星连线 | Cre-XX（机号即呼号） | `orion`（计数即档案） |
| **GIMMICK** | 把戏 | F-16 ×2 + Mirage 2000 ×2 | 混编（狙击 + 斗士） | 统一轮换窗 | 洋红 `#E23A8E` | 交叉互指的双箭头（调包） | BLUFF | `gimmick` |
| **GOOFIGHTERS** | 怪火 | Su-47 ×2 | 斗士（格斗弹 + 眼镜蛇） | 统一轮换窗 | 深紫罗兰 `#7B3FE4` | 两簇并飞的鬼火圆点 | WISP | `goofighters` |
| **VULTURE** | 秃鹫 | MiG-31 ×8 | 骑士 | **统一轮换窗** | 酒红 `#8E2450` | 三线构成的俯冲展翼 V + 翼下一点 | CARRION | `vulture` |
| **WhiteTea** | WhiteTea | F-CK-1 ×3 | 机炮骑士（joust + 单次 J-turn） | **统一轮换窗** | 覆盆子红 `#C73567` | 三片茶叶 + J 形叶钩 | TEA | `whitetea` |
| WRAITH | 幽灵 | F-47 ×4 | BOSS（专属战术） | BOSS 闸 | 精英红（既有） | 待补（后续批） | WRAITH-01 | 既有 boss 档 |
| POLTERGEIST | 骚灵 | F-14 ×4（CSG 二阶段） | BOSS | BOSS 闸 | 精英红（既有） | 待补（后续批） | 既有 | 既有 boss 档 |
| MOTHER GOOSE | 鹅妈妈 | 飞行翼母舰 | BOSS | BOSS 闸 | 精英红（既有） | 待补（后续批） | 既有 | 既有 boss 档 |

> BOSS 三队的代号/呼号已在各自 spec；徽章 + lore 档案文本随包装后续批补齐，本批只管
> 非 BOSS 王牌三队。

### 2.8 交战血条（BOSS 式，2026-07-27 用户定档）

**触发**：入场时**不亮**（入场信号是 §2.6 三件套）；**与玩家开始交战后**才显示——
判定 = 中队任一成员**首次开火或首次被伤害**（先到者）。撤离中不新亮；全灭/全员出界收起。

**形态**：复用 BOSS HUD 血条面板通道，但渲染成**分段命条**：

| 项 | 规格 |
|---|---|
| 段数 | = 编成机数（MARATHON 5 段 / 2NDWAVE 5 段 / VULTURE 8 段 / WhiteTea 3 段），一段 = 一架 |
| 段语义 | 非 BOSS 王牌一发死 → 血条即**存活机数条**，击坠一架灭一段（从两端向中间灭？从右向左灭，草案） |
| 代号 | 血条上方显示中队代号（全大写）+ 徽章小图 |
| 颜色 | 中队主色（§2.7） |
| 长机段 | 长机所在段带小三角标记（草案——2NDWAVE 打 Teacher 优先级读得出来） |
| 与 BOSS 条冲突 | BOSS 条优先；BOSS 阶段王牌已撤离，实际同屏窗口极小，王牌条直接隐藏 |

### 2.9 统一轮换窗（2026-08-01 用户定档）

六支非宿敌中队都在 `game_time ≥ 240 s` 进池。新局以无放回洗牌决定顺序，session 内连续
两局的首队不得相同；同局不重复。强弱不再用 240/320/400 秒时段遮蔽，而由
[ace-rotation-balance](ace-rotation-balance.md) 的 60~90 秒标准击破预算约束。其余调度规则
不变（间隔 150 s / 540 s 截止 / 同场 ≤1 支 / BOSS 阶段不触发）。

**ORION 独立轨道（§3.8 宿敌条款）**：单机宿敌不进上表轮换池、**不占"同场 ≤1 支"名额**
（单机压力量级与整队不冲突）；中期（约 300 s，草案）静默入场、每局一次。
**局内时间结束（600 s 阶段闸落下 = BOSS 解锁）→ 在场王牌开始撤离飞离战场；撤离中被击败
不给时间奖励（XP 照给）**——此规则为 tier 通用契约（Su-35 队已实装，所有新队继承）。

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

**例外条款（2026-08-01 修订）——零 flare 只作可量化减负**：当前 VULTURE 全队零 flare，
但不因此开启 beam/notch；其速度、拉远与回转已在 TTK 公式中收取接近成本。Teacher 改回
1 枚 flare 并关闭持续导弹规避。未来若要做零 flare 机动规避个体，必须在独立 spec 中把
确定性动作折为 DU，且预计击破时间仍落在 60~90 秒。

**装备件机动的归类（2026-07-27 用户定档）**：`CobraManeuver` 等**装备声明式机动件**
不属于本节"规避机动"范畴（它是带冷却的自动装备行为，不是 beam/notch 行为链）。
王牌使用规范：**flare 耗尽后才解锁**（触发判定 gated on `flares_remaining == 0`）——
第一层命数读数保持纯净，耗尽后由"防御归零"改为"换上一件冷却可数的备胎"。
首例 GOOFIGHTERS（[events/ace-goofighters](../events/ace-goofighters.md) §2.3）；WhiteTea 的
J-turn 同样遵守分层门，但额外限制为每机整场一次（[events/ace-whitetea-fck1](../events/ace-whitetea-fck1.md)）。

### 3.5 隐形 vs 锁定（一致性铁律）

**任何"隐形中"的飞机，对任何一方的任何锁定/索敌通路，都必须不可见。**

现状漏洞：`is_lock_immune()` 只在雷达累积循环里被执行，而 AI 出于性能考虑大量直接扫
`CombatUnit.all_units` 当传感器，这些通路完全没有隐形语义。必须补齐的通路：

| 通路 | 要求 |
|---|---|
| `AIController._current_target` | 目标进入隐形 → 立即失效并重新选目标 |
| **玩家命令铁律 `commanded_target`（点名交战）** | 目标隐形 → **铁律让位**：交出目标持有权、扳机停火，但**不清点名指针**；解除隐形自动重接 ENGAGE（见下"让位语义"） |
| **玩家亲控机 planner（`Situation` 目标段）** | 目标隐形 → `has_target=false`，扳机哑火 + 不再获得精确位置（补齐"BFM 读位置"在 planner 路径的缺口） |
| 小队协同索敌（绕开雷达锥的"自由交战"扫描） | 过滤 `is_lock_immune()` |
| 简易 AI / tether / 神风 的 `all_units` 扫描 | 同上 |
| 副雷达（QMAAM）锁定累积 | 同上 |
| BFM 机动层读取目标位置 | 目标隐形时不得继续获得精确位置 |
| 副雷达锁定框渲染 | 不得在隐形机位置画框 |
| AA 炮索敌 | 同上 |

> 当前最严重的后果：BFM 层对隐形目标保持**零误差位置跟踪**，只是扳机哑火 ——
> 解除隐形瞬间零延迟重新交战，隐形在战术上完全没有价值。

**让位语义（commanded_target 通路，2026-07-26 补）**：玩家点名的 combat target
（`commanded_target`）与 AI 自选目标一样受隐形铁律约束，但由于 BOSS 隐形是**短时循环窗**
（Wraith 5.5s），采用**挂起**而非**硬清**：

- **触发只认 `is_cloaked`（真隐形），不认整个 `is_lock_immune()`**：后者含航母弹射 / 出场的
  短暂锁定免疫窗（目标实体仍在），也含 MountTarget（船挂点）的路由 trick（合法可打），
  对这些丢命令是过度反应。命令**获取侧**仍过滤完整 `is_lock_immune()`（"获取严、维持宽"）。
- **让位 = 主动以 `TS_COMMANDED` 优先级交出目标持有权**（`release_target`），**不能只 return**：
  否则 `disengage` 的 `TS_SCORED` release 会被 `_target_holder_pri`（只在 `is_destroyed` 降级）
  以 4 > 1 拒绝 → 每 tick「铁律 acquire → engage 有效性失败 → disengage 被拒」原地空转
  （即现状 bug 根因：优先级死锁，而非单纯"没过滤隐形"）。
- **不清 `commanded_target` 指针**：解除隐形后铁律下一 tick 自动 `acquire_target(TS_COMMANDED)`
  重接 ENGAGE，玩家**无需重新点名**。挂起期该僚机落回编队待命 / 可临时自由交战别的目标
  （TS_SCORED 良性接管），与 B1 躲弹让位"保留命令、威胁消失自动重接"同一设计语言。
- **姿态/包围方位随让位自然失效**：`attack_posture` / `surround_bearing_rad` 只经 `Situation`
  的姿态门透传，门收紧为 `combat_target == commanded_target` 后，挂起期临时交战别的目标不再
  被点名姿态污染，重接时自动恢复 —— 无需显式挂起/恢复这两个字段。
- **硬清方案否决**：① 5.5s 短窗每次隐形都要玩家重新点名，操作税不可接受；② 签名技以
  `commanded_target == null` 为 buff 终止条件（如 J-36 三段推力），硬清会每次隐形白掐 buff；
  ③ 与 B1 让位语言不一致。

### 3.6 BOSS 附加规格（子集专属）

| 项 | 要求 |
|---|---|
| 强度 | 机体性能与技术水平 **严格强于**同期非 BOSS 王牌中队 |
| 主题 | 专属 BGM |
| 演出 | 专属登场序列（见 `systems/ui-transition`）+ 专属电台**对话序列**（`boss_sequences`，多句队内对话）+ **红色 WARNING 警告横幅（BOSS 专属，非 BOSS 王牌禁用，§2.6）** |
| 队级战术 | 允许专属机制与多相战术状态机（Wraith 四相包夹 / Poltergeist 死锁换手 / 隐形第二防御层） |
| 关卡机制 | **击败全队 → 关卡结束**（触发 VICTORY 结算 + 功勋入账） |

非 BOSS 的王牌中队**不触发关卡结束**，只是生存模式中途的强敌。

### 3.7 战术风格库（一队一套战术，2026-07-26 用户定档）

> 王牌中队与 BOSS 的强度表达方式**刻意不同**：BOSS 靠专属机制与多相队级战术状态机；
> 王牌中队**没有复杂机制、没有夸张的特殊机制** —— 每支队只有**一套战术**，从入场打到全灭。
> 它是对玩家战术水平的**硬考核**：挑战性强、玩家很容易在这里翻车，但成分干净、可学习，
> 不需要做得太夸张。

硬约定：

1. **一队一套战术**：一支王牌中队从入场到退场只运行一个战术循环。无阶段转换 / 护盾 /
   狂暴计时 / 隐形等二阶机制（隐形是 BOSS F-47 专属第二防御层）。
2. **风格从风格库选取**：新中队必须从下表选一个风格；要加新风格，先在本表登记
   （含"玩家反制答案"列）再开中队 spec。
3. **每种风格必须有明确的玩家反制答案**：硬考核要可学习 —— 翻车的玩家必须能说出
   "下次我该怎么打"。答案写进风格表，playtest 按它验收。
4. **词汇边界**：风格内部名复用 AI archetype 词汇（Gladiator / Lancer / Schemer），
   属内部词汇，**不得对 UI / display_name 暴露**；勿与 Wraith BOSS 的队内角色
   `AceRole.KNIGHT / SNIPER` 混用 —— 那是 BOSS 队内分工（单机角色），不是队级风格。

| 风格 | 内部名 | 战术循环（唯一一套） | 装备 | 玩家反制答案 | 实例 |
|---|---|---|---|---|---|
| **斗士** | `gladiator` | 全员 PURSUIT 死死扑向玩家操控机，缠斗咬住不放、永不脱离 | 机炮（`ace_gun`）+ 导弹 | 利用"死咬"的可预测性：拉进队友火网 / 角点速度周旋 / 骗光那枚必躲 flare 后导弹终结 | MARATHON（[events/ace-support-squadron](../events/ace-support-squadron.md)）；2NDWAVE 的 Teacher 单机 |
| **骑士** | `lancer` | 高速掠袭循环：编队高速压过 → 向玩家小队**全体成员**齐射一波导弹 → 直线掠远 → 回转再来一轮 | **纯导弹，无机炮**（§2.4 豁免） | 直线段追不上，答案是**贴近**：抓回转段减速窗口强杀 / 迎头对射窗口 / 齐射来袭时的 flare 纪律 | VULTURE（[events/ace-lancer-mig31](../events/ace-lancer-mig31.md)，draft）；2NDWAVE 的 F-15 学员 element |
| **机炮骑士** | `gun_lancer` | 单机高速切入机炮扫射 → 穿越脱离 → 拉开折返；脱离腿被近距尾追且 flare 已空时，用一次 J-turn 反咬 | **纯机炮，无导弹** | 不尾追直线脱离腿；从侧面截住下一次进入线，逼掉 flare 后再迫使其花掉唯一 J-turn | WhiteTea（[events/ace-whitetea-fck1](../events/ace-whitetea-fck1.md)） |
| **狙击** | `schemer` | **导弹偏好 + 保持距离**：绕外圈游走放弹（站位带 4~6 km 为实现草案）、**被追即跑**——脱离拉开重建距离后继续放弹；不进近、不掠袭、不接受缠斗 | 导弹为主 + 机炮自卫 | 不要去追它（追它 = 进它队友的火网）：先拆它的近战屏障，狙击手失去掩护后只会跑——**追击战玩家占优** | GIMMICK 的 F-16 element（[events/ace-gimmick](../events/ace-gimmick.md)，draft）。复用 Wraith SNIPER `bvr_only` 站位带 + AF-03 Schemer 打带跑基建 |

> 狙击位于 2026-07-27 启用（此前刻意留白）。归位已经用户拍板确认：GIMMICK 的 F-16
> **不是掠袭式骑士**——语义就是"更倾向于用导弹、被追的话倾向于跑开"。

**混编条款（2026-07-27，随 2NDWAVE 开）**：允许一队内按机型划分**至多 2 个 element**，
各 element 持风格库中的一套战术、**全程静态分工**——这不违背"一队一套战术"的精神：
禁止的是**相位切换**（打到一半换战术是 BOSS 专属），不是分工。混编队的考核价值恰在
两套压力叠加（2NDWAVE：你不能安心跟 Teacher 单挑，学员的掠袭波次会穿你的缠斗圈）。

### 3.8 宿敌条款（Nemesis，2026-07-27 用户定档，唯一实例 ORION）

单机跨局成长型王牌的特别法。**本条款是白名单制**——每一条都是对 tier 既有铁律的显式
豁免，只对 spec 声明"宿敌"的队生效，现役唯一实例 [events/ace-orion](../events/ace-orion.md)：

| 豁免项 | 内容 | 被豁免的铁律 |
|---|---|---|
| 单机编成 | 王牌"中队"可以只有一个人 | —（编成惯例） |
| **静默登场** | **登场不给任何提示**：无 `ace_spawn` 台词、无提示条、无 Tab 特标——只是出现在地图上，一直坚持追踪玩家正在操控的飞机 | §2.6 三件套（唯一豁免） |
| 伪装涂装 | 用普通敌方橙、外形"看上去普通"——识别通道只有：直奔你的行为、数据标签/kill feed 上的机号、交战后亮的血条 | §2.7 紫红 color code |
| **跨局成长** | 强度随**生涯被击坠计数**（全局存档）爬升：AI / 武器 / 防御 / 机体逐档变强 | §2.1"无等级缩放"**不冲突**——那条禁的是局内玩家等级轴；宿敌的成长轴是玩家亲手喂出来的生涯计数 |
| 机号即呼号 | 呼号 = 当期机号（Cre-XX），每被击坠一次编号 +1 | §2.7 固定呼号（呼号仍固定唯一、不与杂鱼重名，只是会"换人"） |
| 无时间奖励 | 击坠不给 `game_time` 延长（它不是支援事件，是私人恩怨）；计数 +1 就是奖励本体 | §2.9 全灭 +60 s |

宿敌仍**完整继承**的 tier 待遇：实例打标 / LOD 豁免 / `skip_far_cleanup` / token 0 /
armor 0 / 一发死 / BOSS 闸撤离契约。**不许再开第二个宿敌**——这个位置的叙事价值来自
唯一性；想加第二个，先删第一个。

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

### 4.3 加新王牌中队制作清单（生产流程，2026-07-26 规范化）

> 目标形态：加一支新王牌中队 = **1 份 spec + 1 处编成登记 + 可选台词扩充**。
> 禁止为每支新队复制粘贴事件类 / 散点判定 / 专属横幅。

1. **建 spec**：`docs/specs/events/ace-<name>.md`（以 [events/ace-support-squadron](../events/ace-support-squadron.md)
   为样板），`depends_on` 本 spec。§2 必须写明：编成（机型 × 数量）/ **风格（从 §3.7 选，
   混编按混编条款）**/ 生存档（默认 = 一发死 + 1 枚必躲 flare；偏离必须特别声明）/
   机炮闪避档（基线 0.20 默认；高档需声明）/ **包装五件套**（代号 + 中文名 / 成员固定
   呼号表 / 徽章概念 / lore 三语 / 主色——紫红系内选新色相）/ 血条段数（= 机数）/
   **登场时段档（早期 / 后期，§2.9）**/ 触发调度差异（默认沿用支援调度器）。
2. **与用户定稿**（status: approved）后再动代码 —— spec-first 铁律。**包装五件套（尤其
   代号 / 呼号 / lore 文案）属用户 taste 域，必须过目。**
3. **编成落地**：走 profile 单点登记（机型 / 数量 / 风格 / 涂装 / flare / gun（可 null）/
   导弹载量）。第二支队（MiG-31）落地时把 `AceSupportSquad` 的硬编码编成抽成 profile 表；
   此后加队只在表里加一行。
4. **tier 打标**：一律 `AceTier.mark()` **实例打标**。禁止把机型整体划为王牌（杂兵同型不受
   影响）；禁止假设 `category == "boss"`（§4.1）。
5. **战术接线**：斗士 = 既有 PURSUIT 软维护；骑士 = 掠袭循环模块（复用 joust RUN_IN/BREAK
   原语）。新风格先回 §3.7 登记，战术层做成独立小模块（模块化拆分惯例）。
6. **演出与包装接线**：按 §2.6 三件套（不加红横幅；`ace_spawn` 台词池自动生效，可选扩充
   带风格的行）+ **§2.7 包装注册表加行**（代号 / 呼号开局 reserve 且永不 recycle / 徽章 /
   留档 id）+ **§2.8 血条**（编成数即段数，走通用分段条通道，不要每队画一套）。
7. **调度**：注册进 survivor_mode 王牌支援调度器（同场 ≤ 1 支；**时段档 + 轮换**见 §2.9）。
8. **i18n**：Tab 标签 / 通报条 / 新台词三语；跑 `--bench=chatter` 校验 key 齐全。
9. **debug 入口**：F5 面板 FormationType 加项（debug 测试场必须能直接生成该队）。
10. **验收**：`--bench=ace_tier` 回归 + 该队 spec §5 验收 + 性能压测（LOD 豁免编成按机数
    乘满帧成本，8 机队必须过 Sentinel + Lv5 压测）。
11. **收尾**：`_INDEX.md` 加行 / spec §7 锚点 / `verify_doc_anchors.py`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **命数可数**：玩家连续发射导弹，前 4 发均被热诱弹骗飞（100%，无随机失败），第 5 发命中。
- [ ] **迎头同样成立**：迎头交战下前 4 发导弹同样必定被骗（验证已移除角度依赖）。
- [ ] **近距同样成立**：150 m 内发射的导弹同样必定被骗（验证已移除距离惩罚）。
- [ ] **耗尽即残血**：热诱弹耗尽后中一发 MRM（80 伤）不死，剩 20 HP；中一发 AGM-65（90 伤）
      同样不死，剩 10 HP（验证 100 HP 高于全部玩家导弹伤害）。第 6 发必定击坠。
- [ ] **隐形不耗命**：完整经历一次隐形周期，`flares_remaining` 不减少。
- [ ] **隐形不可锁**：隐形期间 AI 僚机无法将其设为 combat target；副雷达不累积锁定；
      不出现锁定框；解除隐形后需重新累积锁定（不得零延迟重连）。
- [ ] **点名铁律隐形让位**：给僚机点名一架王牌 → 它隐形瞬间僚机 `combat_target` 清空（停止空转/停火）、
      落回编队待命，但 `commanded_target` 指针保留；解除隐形后 1~2 tick 内自动重接 ENGAGE，
      玩家无需重新点名；全程无 ENGAGE↔脱离的逐 tick 抖动。
- [ ] **玩家亲控机不零误差跟踪隐形**：玩家亲自驾驶并咬住一架王牌 → 它隐形期间玩家机不再获得
      其精确位置（扳机哑火 + 不精确指向），解除隐形后恢复。
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
- [ ] **玩家命令铁律 `commanded_target` 隐形让位**（2026-07-26 补）：`_enforce_commanded_target`
      在 is_destroyed 检查后加 `is_cloaked` 让位分支，以 `TS_COMMANDED` 主动 release、不清指针
- [ ] **玩家亲控机 planner 隐形失效**（2026-07-26 补）：`Situation` 目标段对 `is_cloaked` 目标
      置 `has_target=false`（补齐 combat_tracking 隐形清除在 planner 路径 early-return 的缺口）
- [ ] **姿态门收紧**（2026-07-26 补）：`Situation` 姿态透传门加 `combat_target == commanded_target`，
      防让位期临时目标被点名姿态/包围方位污染
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

### 阶段 3 — 生存模型落地（依赖 §2.3 数值定稿）✅ 2026-07-22
- [x] 新建王牌中队专属 flare 资源 `resources/ace_flare.tres`：`max_flares = 4`、
      `burst_count = 1`、`nervousness = 0.5`；F-47 与 F-14 Poltergeist 的敌方 params 改挂它
      （**不动** `f14_flare.tres` —— 那份被玩家可驾驶 F-14 共用）
- [x] 干扰判定增加 tier 分支：王牌中队 `jam_chance = 1.00`
- [x] `fail_chance` / `head_on_fail_reduction` 一并归零（见 §2.2 表）——
      与 jam 恒 1.00 同一条理由：那是"对来袭导弹完全不反应"的骰子，会让一条命随机蒸发
- [x] 王牌中队 `max_hp` 定档 = 100（随阶段 2 一并落地：HP cap 豁免不设血量就无从验证）
- [x] 确认 spawn 时 params 走 `duplicate(true)`，隔离玩家升级对敌方资源的污染
      （`survivor_spawner._create_enemy` 对 flare 等嵌套子资源逐个再 `duplicate()`）

> **落地前的真实状态（playtest log 20260722_005100 实证）**：本阶段此前从未实装，
> F-47 挂的是 `max_flares = 2` + `burst_count = 3` → `mini(3,2) = 2`，
> **第一次投放就打光整个弹匣 = 实际只有 1 条命**，而不是 spec 承诺的 4 条。
> 日志里三架 WRAITH 各出现一次 `deployed 2 flares (remaining=0)` 即为此。

### 阶段 4 — 火力对齐
- [x] 新建 `ace_gun.tres`，数值按 §2.4（2026-07-22 随 [events/ace-support-squadron](../events/ace-support-squadron.md) 落地；**支援中队已挂**）
- [ ] BOSS 王牌中队机型（F-47 / F-14 Poltergeist）改挂 `ace_gun.tres`（随 wraith 批，避免未经 playtest 连改 BOSS）
- [x] 机炮占空比 tier 分支取消：统一服从敌机“一次机会一梭 + 3.0s 停火”安全门

### 阶段 6 — 演出与风格规范落地（2026-07-26 批）
- [x] `AceReinforcementEvent` 摘除 `show_warning_banner`（红横幅收回 BOSS 专属）
- [x] 新增 `ace_spawn` scripted trigger + 台词池 5 条三语（`radio_chatter.json` + `translations.csv`）
- [x] `AceReinforcementEvent` 入场改调 RadioChatter（长机说 `ace_spawn`）
- [ ] 编成 profile 参数化（随第二支队落地批，见 §4.3 第 3 步）

### 阶段 7 — 包装批（2026-07-27 用户定档；**2026-07-28 实装批主体落地**）
- [x] profile 单点登记：`AceSquadProfiles`（代号 / 中文名 key / lore key / 主色 / 呼号表 /
      闪避档 / 时段档 / 编成 / 装备 / 战术 / 阵型；加队 = 表里一行）
- [x] 固定呼号：`CallsignDB.reserve_permanent`（开局打标 / 免 recycle / 免 reset）+
      spawn 后按槽位绑定；代号词撞池（Vulture/Orion 等）一并保留
- [x] 涂装换色：MARATHON 金橙 → 猩红（profile 主色，金橙退役）
- [x] 机炮闪避注入：spawn 后处理写 `bullet_dodge_chance`（profile 分档）
- [x] 交战血条：HUD 分段命条面板（首次开火/受击触发 / 段=机数 / 长机段顶边标记 /
      代号头 / BOSS 条优先互斥；徽章小图随徽章批）
- [x] 入场提示条带代号（`EVENT_ACE_INBOUND_FMT` 等三 key 三语；旧 EVENT_ACE_SUPPORT_* 退役）
- [x] 生涯留档数据层：`record_ace_encounter / record_ace_defeat` + 首破日期 +
      真全灭判定（撤离逃掉 ≥1 架不算击破）；orion 击破计数即宿敌成长轴
- [x] 调度器统一 240s 窗 + 新局无放回洗牌 + 连续两局首队防重复 + 同局不重复
- [x] lore/中文名三语入 i18n（`ACE_SQUAD_*_NAME` / `_LORE` ×7 队）
- [x] Tab 标记改中队主色 + 代号标签
- [x] 档案页王牌区块 UI：**击破解锁制**（未击破 = 灰徽章剪影 + "???"，遭遇过附遭遇次数
      "它认识你了"；击破 = 代号/中文名/lore 全文/首破日期/击破数）；ORION 额外显示"下一架"机号。
      ⚠ 2026-07-28 用户扩展需求后，该页**泛化为全敌人图鉴**（七队成为其中一组），
      入口改「敌人图鉴」，规格移交 [career-archive §2.6](career-archive.md)
- [x] 徽章线框绘制：`AceEmblemIcon`（七队几何线框：跑道环/双叠浪/猎户三星/调包双箭头/
      双鬼火/俯冲 V/三茶叶 J 钩；静态绘制仅变更时重画）——血条代号旁小图 + 档案页大图两处挂载

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
| 王牌登场台词（§2.6） | `resources/chatter/radio_chatter.json`（`ace_spawn` trigger）、`scripts/events/ace_reinforcement_event.gd`（入场调用点） |
| 机炮闪避骰（§2.2 注入点） | `scripts/aircraft.gd`（`bullet_dodge_chance` 字段 + `take_bullet_damage` 判定） |
| 固定呼号 reserve（§2.7） | `scripts/callsign_db.gd`（`reserve` / `recycle`） |
| 生涯留档（§2.7） | `scripts/meta/career_archive.gd` |
| 徽章绘制（§2.7） | `scripts/meta/ace_emblem_icon.gd`（AceEmblemIcon，血条 + 图鉴页共用） |
| 王牌档案呈现（§2.7） | **已并入敌人图鉴**：`scripts/meta/enemy_codex.gd` + `scripts/meta/enemy_archive_ui.gd`（王牌为其中一组，规格见 [career-archive §2.6](career-archive.md)） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-02 | 15 | 全敌机机炮安全门统一：删除王牌 4.0s/1.5s 连射特权；每次机会只打一梭，梭后停火 3.0s，WhiteTea 等机炮王牌无豁免。 |
| 2026-08-02 | 14 | 新增 WhiteTea：F-CK-1×3 机炮骑士，240s 入统一池；纯机炮 joust 打带逃、每机 1 flare 后一次性 J-turn；补七队包装、70s TTK 与 `gun_lancer` 风格。 |
| 2026-08-01 | 13 | **轮换/TTK 平衡修订**：五支非宿敌统一 240s 新局洗牌；flare 默认 1 的显式例外改为 VULTURE 全队 0；Teacher 改 1 且撤下 evade；详细 DU 公式与实测闭环下沉 ace-rotation-balance。 |
| 2026-07-20 | 1 | 初稿。确立王牌中队/BOSS 分层定义、热诱弹=命数生存模型、tier 准入门槛、隐形一致性铁律。`max_hp` 定档待裁决 |
| 2026-07-20 | 2 | 用户定档：`max_hp = 100`、干扰成功率 1.00。因 100 高于全部玩家导弹伤害，§1.1「耗尽即必死」修正为「耗尽即防御归零 → 必经残血 → 第 6 发击坠」。**阶段 1 + 阶段 2 落地**：隐形一致性 7 处通路补齐、`evade_missiles` 死配置删除、机炮前置解弹速统一；新建 `AceTier` 模块收敛 tier 三处散点判定，`--bench=ace_tier` 20 断言全绿 |
| 2026-07-22 | 3 | §2.2 命数**分档**（BOSS 4 / 支援 2，随首个非 BOSS 王牌实例 [events/ace-support-squadron](../events/ace-support-squadron.md) 落地）；阶段 3 jam=1.00 分支 + 支援档 flare 资源 + 阶段 4 `ace_gun.tres` 落地（BOSS 换挂/占空比留 wraith 批）。§4.1 预言的"通用机型非 BOSS 王牌"路径走通：AceTier.mark 实例打标，杂兵 Su-35 零影响（bench 断言守住） |
| 2026-07-26 | 5 | §3.5 铁律通路表补两条：**玩家命令铁律 `commanded_target`**（隐形→挂起让位，非硬清）+ **玩家亲控机 planner `Situation` 目标段**（补齐 combat_tracking 隐形清除在 planner early-return 的缺口）。定"挂起"语义：只认 `is_cloaked`、以 `TS_COMMANDED` 主动 release 破优先级死锁、不清指针解隐形自动重接；姿态门收紧防污染。修复根因是**优先级死锁**（现状每 tick 铁律 acquire vs disengage TS_SCORED release 被拒空转），非单纯漏过滤 |
| 2026-07-28 | 12 | **包装收尾批**：档案页 + 徽章落地（阶段 7 清零）——主菜单"王牌档案"入口（击破解锁制：未击破灰剪影 "???"、遭遇过显示"它认识你了"、击破解锁 lore 全文+首破日期；ORION 显示"下一架"机号）+ `AceEmblemIcon` 六队线框徽章（血条代号旁 + 档案页）。i18n ACE_ARCHIVE_* ×10 三语。**tier 全部实装项完成，余全六队 playtest** |
| 2026-07-28 | 11 | **中期三队 + 宿敌实装批**（续 v10）：**六队全部落地**——2NDWAVE（elements 混编首实装：Teacher 零 flare evade 解锁 `ace_evader` meta + 学员 lancer element）/ GIMMICK（狙击位=AceRole.SNIPER 站位带直接复用）/ GOOFIGHTERS（cobra 分层门进 CobraManeuver：`is_ace && flares>0` 拒绝，敌用件一次性=flare 1 命+cobra 1 次；顺带管住 Marathon Su-35 眼镜蛇）/ ORION（OrionNemesisEvent 独立轨道+档位表+生涯计数）。基类新增 `_member_type/_member_role` 钩子 + `ace_tactics_owned`/`ace_evader` meta 分流；新机型 5 型（f15/f16/mirage2000/su47/cre，王牌专属不进随机池，缩减 13 步清单）。--bench=lancer_squad 39 断言 + **回归门 41 项 PASS**。余：档案页 UI / 徽章 / playtest |
| 2026-07-28 | 10 | **实装批**（用户"开始执行"+ Marathon 改档中期 320 s）：阶段 7 包装主体落地（AceSquadProfiles 单点登记 / 呼号永久保留 / 猩红换色 / 闪避注入 / 交战血条 HUD / 代号提示条 / 留档数据层 / 时段档轮换调度）+ **VULTURE 落地**（编成 profile 泛化 + lancer_squad_tactics + 弹尽撤离 + `--bench=lancer_squad` 19 断言）。验证：ace_tier 42 / chatter 87 / lancer_squad 19 / **回归门 41 项 PASS**。余：档案页 UI / 徽章绘制 / 其余三队（2NDWAVE·GIMMICK·GOOFIGHTERS·ORION） |
| 2026-07-27 | 9 | **用户双拍板**：① GIMMICK F-16 归位确认——非掠袭骑士，语义="导弹偏好 + 被追即跑"，§3.7 狙击行按此重写（站位带降为实现草案）；② §3.4 新增装备件机动归类——CobraManeuver 不算"规避机动"，王牌使用规范=**flare 耗尽后才解锁**（GOOFIGHTERS 分层防御：第 1 层命数纯净 / 第 2 层眼镜蛇 25 s 冷却备胎） |
| 2026-07-27 | 8 | **中期三队批**（用户设计输入）：① §2.7 注册总表 +3 行——**ORION 猎户座**（原创机体 Cre 宿敌单机）/ **GIMMICK 把戏**（F-16×2 狙击 + Mirage 2000×2 斗士）/ **GOOFIGHTERS 怪火**（Su-47×2 格斗弹+眼镜蛇斗士）；② §2.9 新增**中期档 320 s** + ORION 独立轨道（不进轮换池、不占同场名额、~300 s 静默入场每局一次）；③ §3.7 **启用狙击 `schemer` 风格位**（BVR 站位带施压，复用 Wraith SNIPER / AF-03 基建；注记用户原话"骑士型远处狙击"的归位裁量）；④ 新增 §3.8 **宿敌条款**（白名单制六项豁免：单机/静默登场/伪装涂装/跨局成长/机号即呼号/无时间奖励；唯一实例铁律）。三队 spec 均 draft 待定稿 |
| 2026-07-27 | 7 | **包装批**（用户定档）：① §2.7 中队包装五件套——代号/成员固定呼号（开局 reserve、永不 recycle）/线框徽章/lore/生涯留档（CareerArchive 类比 BOSS），主色规范改**紫红系**（金橙退役），包装注册总表（MARATHON/2NDWAVE/VULTURE + BOSS 三队占位）；② §2.8 交战血条——入场不亮、首次开火/受击亮，分段命条（段=机数）+代号+徽章+长机段标记；③ §2.9 登场时段档（早期 240s=MARATHON/2NDWAVE 轮换、后期 400s=VULTURE）+"局时结束撤离、击败无时间奖励"升为 tier 通用契约；④ §2.2 flare 统一铁律（默认 1 枚，特别声明才偏离）+ **机炮闪避分档**（基线 0.20/高档 0.35/特高 0.50，注入 bullet_dodge_chance）；⑤ §3.4 例外条款——零 flare 机动规避型个体（Teacher）；⑥ §3.7 混编条款（≤2 element 静态分工，禁相位切换）。新队 2NDWAVE spec 开档 |
| 2026-07-26 | 6 | **王牌中队规范化批**（用户定档）：① 新增 §2.6 登场演出标准 —— 红色 WARNING 横幅收回 **BOSS 专属**，非 BOSS 王牌入场主信号改为专属无线电台词（`ace_spawn` scripted 必播 + 台词池 5 条三语）+ 次级提示条 + Tab/涂装三件套；② 新增 §3.7 战术风格库 —— 一队一套战术 / 禁二阶机制 / 反制答案必填，登记斗士（gladiator，Su-35 队）与骑士（lancer，MiG-31 队 draft）两风格；③ 新增 §4.3 加新王牌中队制作清单（11 步，目标 = 1 spec + 1 处 profile 登记）；④ §2.4 机炮原则加骑士无炮豁免条款。阶段 6 演出部分已落地 |
| 2026-07-23 | 4 | **HP 豁免收窄为 BOSS 专属**（用户"除 BOSS 外所有空中敌人一发死"）：§2.2 非 BOSS 王牌中队（支援中队）**不再豁免**一击必杀（HP≤cap 一发死）、命数 2→**1 枚**；只继承 tier 的 LOD 豁免 / 无缩放 / 强 AI / jam 1.00（那 1 枚必定躲）。**推翻早先"BOSS ⊂ 王牌都豁免一击必杀"前提** → HP 豁免 + 多命只归 BOSS。落地见 ace-support-squadron v3（代码仅 flare max_flares 1 + 删 apply_hp）。⚠ `AceTier.apply_hp`/`exempt_from_hp_cap` 现仅 BOSS 型（is_ace_type）走，支援中队实例打标但不调 apply_hp |
