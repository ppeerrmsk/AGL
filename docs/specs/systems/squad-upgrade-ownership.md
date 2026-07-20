---
id: squad-upgrade-ownership
kind: system
status: draft        # ⏳ 新模型成稿待 review→approved。绑机型 + 全 41 技能归类 + 僚机生产 + Session-only。
schema_version: 1
spec_version: 2
owner: noelu
depends_on: [squad-control-switching, aircraft-evolution, survivor-loop, survivor-skills]
reconstruction_complete: false
---

# 小队升级归属 —— 绑机型 / 专属 vs 全局 / 僚机生产 / Session 内 Roguelike

> ⚠ **本 spec 已整体重写（spec_version 2，2026-06-28）**，取代 v1 的"数值跟队共享 + 独特武器跟机实例"旧模型。
> 用户定调：**升级一律绑机型（aircraft TYPE，不绑实例、不跟队共享）**，只有显式标 `GLOBAL` 的少数技能才全队生效。

> 玩家视角：你这局抽到的强化**绑在机型上**——开 A-10 堆的机炮强化只让"你队里所有 A-10"变强；切到 F-16 僚机时它身上是 F-16 那一套电子战强化，而不是 A-10 的机炮 build。强力的"变身级"技能（自动护盾、眼镜蛇、电磁炮…）是**机型专属**，只在对应机型上生效；这架机只要还在队里，无论你亲自飞还是 AI 托管，效果都在；换成别的机型 / 这架被打掉，效果就没了（除非该技能标了"可继承"）。所有强化只在**这一局**有效，下一局从头开始。

> ⚠⚠ **方向修订（2026-06-28，待重切）**：用户决定**局内/局外彻底分层**（见 [meta-progression](meta-progression.md)）。
> 切分轴 = **"槽位装备 loadout vs 玩法深度"**（**不是**重/轻）：武器/装备/硬件 loadout（电磁炮/激光/机炮弹药/载弹数/槽位）归**局外持久解锁**；改变战术打法的**玩法深度机制**归**局内**。
> 下面 §2.2 的 41 技能归类总表**待按这两类重分**——`affinity=HARDWARE` 及 `missile/gun` 的 loadout 项多半归局外；`TRANSFORM/STATUS` 等玩法机制留局内（局内**不**单薄，是"提升玩法深度"的内容）。绑机型语义仍成立。具体待"局内深度内容"方向定稿（meta-progression §5）。

## 0. 与相邻 spec 的关系（边界）

| spec | 分工 | 本 spec 如何衔接 |
|---|---|---|
| [aircraft-evolution](aircraft-evolution.md) | 机型进化轴 / 战区结算 | 进化=换机型→换一套 PER_TYPE build + **换整套武器**（§3.3）；**武器绑机型不继承**（§2.6，取代旧 §2.5 的"槽位装备跟玩家"） |
| [squad-control-switching](squad-control-switching.md) | 1-N 号机接管 / 换帅 | 绑机型让"切到不同机型=不同 build 手感"成立；本 spec 把按键扩到 1-9（§3.4） |
| [survivor-loop](survivor-loop.md) | 战区循环 / 奖励发放 / XP 经济 | 僚机生产奖励的**发放**归 survivor-loop；本 spec 定义生产后的**编入+build 重放**（§3.2） |
| [survivor-skills](survivor-skills.md) | 技能图鉴（数值/效果权威） | 本 spec 给每条技能加 `ownership` / `affinity` / `flavor` 三个**归类字段**（§2.2 总表） |

## 1. 设计意图（Why）

**核心转变**：废除"经验满→三选一 + 数值跟全队"的旧 roguelike，改为 RTS 化的"**养机型**"——强化属于机型，不属于某一架飞机，也不无脑全队共享。

**为什么绑机型（不绑实例 / 不跟队）**：
- 贴未来愿景：队伍会壮大成**多个战斗群、几十架飞机**。"每架实例各记一套 build"会碎成一地、运算与 UI 都炸；"全队共享一套"又抹掉了机型差异。**绑机型**是唯一可扩展的中间解——A-10 群强在机炮、F-16 群强在电子战，逻辑自洽。
- 战损不毁 build：损失一架 A-10，只要队里还有 A-10（或之后生产/进化出 A-10），机炮 build 立刻重新生效（build 记在机型上，不随实例死亡蒸发）。
- 切换有意义：切到不同机型号机=体验完全不同的 build，强可感知（DESIGN_PHILOSOPHY 原则 3）。

**体验目标**：
- 每条技能在 UI 上**明确标注作用机型 + 图形化飞机标签**（§2.5），玩家一眼知道"这条强化谁吃得到"。
- 强力"变身级"技能（护盾/眼镜蛇/电磁炮…）做成**机型专属**，强化"养这个机型"的投入感。
- 全局技能（经验、心理战光环、数据链共享）少而精，明确标 `GLOBAL`。
- **Session 内 Roguelike**：所有 build 只在本局，下一局清零（§2.7）。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- 原则 3（信息察觉）：✅ 机型标签 + 切换换 build = 强可感知。
- 原则 6（机型=现实×平衡）：✅ A-10 机炮 / F-16 电子战 贴现实机型性格。
- 原则 9（局内 build / 局外节制）：✅ build 是局内主轴、不跨局。
- 原则 11（60FPS）：✅ apply 为事件级；绑机型让"按机型广播"成本 = 机型数（≤个位数）而非实例数。

**反模式规避**：
- ❌ 不绑实例（多同型机时 build 碎裂、战损全丢）。
- ❌ 不跟全队共享（抹平机型差异、与"养机型"主轴冲突）。
- ❌ 不跨局继承（破坏 roguelike 重开张力）。

## 2. 数据定义（What —— 权威源）

### 2.1 三个归类字段（每条技能都要标）

每条 `UPGRADES` 追加三个字段，决定它"作用在谁身上 / 属于哪个机型系 / 是什么性质"：

| 字段 | 取值 | 含义 |
|---|---|---|
| **`ownership`** | `GLOBAL` / `PER_TYPE` | `GLOBAL`=全队生效（写进 SquadBuild.global）；`PER_TYPE`=只作用于对应机型（写进 TypeBuild[机型]） |
| **`affinity`** | `UNIVERSAL` / `GUN` / `EW` / `MISSILE` / `HARDWARE` | 仅 `PER_TYPE` 用：该技能属于哪个**机型系**。`UNIVERSAL`=任意机型都能抽、抽到即绑当时所驾机型；`GUN`=机炮系(A-10)；`EW`=电子战系(F-16)；`MISSILE`=导弹系；`HARDWARE`=特殊硬件(唯一实例，railgun/laser) |
| **`flavor`** | `STAT` / `TRANSFORM` / `STATUS` | 性质标签（决定"是否做成专属强力技能"）：`STAT`=纯数值；`TRANSFORM`=变身/开关型玩法机制（多为战区奖励）；`STATUS`=条件触发的自身状态（嗜血/超载/无敌盾家族） |
| ~~`inheritable`~~ | **取消** | 原拟"少数升级换机带走"；§2.6 已定**武器/升级一律绑机型、不跨机型继承**，故无此字段。 |

> **抽卡池门控（§2.3 落地）**：`affinity ∈ {GUN, EW, MISSILE, HARDWARE}` 的技能，只有"当前操控机型拥有对应武器系"时才进抽卡池（复用现有 `requires` = `has_equipment_of_kind`）。`UNIVERSAL` / `GLOBAL` 永远可抽。

### 2.2 全 41 技能归类总表（权威 —— 用户要求"写明白"）

> 数值/效果以 [survivor-skills 图鉴](../../docs/systems/survivor-skills.md) 为准；本表只定**归类**。
> `★` = `evolved` 战区奖励池技能（不进随机抽卡）。

#### 🌐 GLOBAL（全队生效，共 4 条）
| id | affinity | flavor | 为什么全局 |
|---|---|---|---|
| `xp_mult` | — | STAT | 经验经济作用于"这一局"，非某架机 |
| `data_link` | — | TRANSFORM | 本就是"僚机雷达×1.5 + 全队锁定共享"的小队级效果（注：仅 F-14 可抽，但效果全队） |
| `fear_squad_spread` | — | STATUS | 让全小队成员都成为恐惧源（小队光环） |
| `fear_chills` | — | STATUS | 恐惧修饰，跟随全局恐惧源 |

#### 🔫 PER_TYPE · GUN（机炮系 → A-10 性格，共 10 条）
| id | flavor | 备注 |
|---|---|---|
| `gun_damage` | STAT | |
| `gun_ammo` | STAT | |
| `gun_reload` | STAT | |
| `gun_firerate` | STAT | |
| `gun_range` | STAT | |
| `gun_accuracy` | STAT | |
| `aim_assist` | STAT | 自动开火扇区 |
| `gun_multishot` ★ | TRANSFORM | 一次 +2 弹 |
| `gun_ciws` ★ | TRANSFORM | 自动 CIWS 拦弹 |
| `gun_kill_fear` | STATUS | 机炮击杀 AOE 注入恐惧（触发者机炮系） |

#### 📡 PER_TYPE · EW（电子战系 → F-16 性格，共 14 条）
| id | flavor | 备注 |
|---|---|---|
| `flare_cooldown` | STAT | |
| `stealth_pod` | STAT | |
| `radar_range` | STAT | |
| `radar_angle` | STAT | |
| `lock_time` | STAT | |
| `flare_shield` ★ | TRANSFORM | **自动护盾**（用户举的护盾例 → 专属） |
| `vapor_dodge` ★ | TRANSFORM | 切高度×2 + 云中隐身 |
| `ecm_pod` ★ | TRANSFORM | 敌雷达有效距离×0.75 |
| `skill_evade_missile_overload` | STATUS | 规避→自身 OVERLOAD |
| `skill_flare_overload` | STATUS | 投焰→自身 OVERLOAD |
| `jam_self_overload` | STATUS | JAM 命中→自身 OVERLOAD |
| `overload_duration_4x` | STATUS | OVERLOAD 修饰 |
| `overload_extended_ammo` | STATUS | OVERLOAD 修饰 |
| `overload_to_bloodlust` | STATUS | OVERLOAD 修饰 |

#### 🚀 PER_TYPE · MISSILE（导弹系，共 8 条）
| id | flavor | 备注 |
|---|---|---|
| `missile_count` | STAT | |
| `missile_tracking` | STAT | |
| `missile_reload` | STAT | |
| `missile_boost` | STAT | |
| `seeker_fov` | STAT | |
| `multi_lock` | TRANSFORM | 多锁齐射 |
| `proximity_fuze` ★ | TRANSFORM | 近炸 AOE |
| `missile_bounce` ★ | TRANSFORM | 命中弹跳 |

#### ✈ PER_TYPE · UNIVERSAL（任意机型可抽、抽到即绑当时机型，共 11 条）
| id | flavor | 备注 |
|---|---|---|
| `hp_up` | STAT | |
| `armor_up` | STAT | |
| `kill_heal` | STAT | |
| `speed_up` | STAT | |
| `maneuver_up` | STAT | |
| `dogfight` | STAT | 综合格斗包 |
| `shock_absorb` ★ | TRANSFORM | 伤害转回血 |
| `cobra_skill` ★ | TRANSFORM | 眼镜蛇机动 |
| `executioner` ★ | TRANSFORM | 击杀叠层提速 |
| `skill_kill_bloodlust` | STATUS | 击杀→自身 FRENZY |
| `skill_damaged_bloodlust` | STATUS | 受伤→自身 FRENZY |

#### ✈ PER_TYPE · UNIVERSAL（续 —— 状态家族，共 7 条）
| id | flavor | 备注 |
|---|---|---|
| `skill_missile_hit_invul` | STATUS | 被弹→自身 INVUL（**无敌盾**，专属强技） |
| `skill_lowest_alt_kill_invul` | STATUS | 低空击杀→自身 INVUL |
| `bloodlust_armor_mobility` | STATUS | 嗜血修饰（减伤+G+加速） |
| `full_hp_kill_perma_hp` | STATUS | 满血嗜血击杀→永久+HP（仅本局） |
| `skill_head_on_perma_hp` | STATUS | 对头击杀→永久+HP（仅本局） |
| `skill_head_on_aoe_fear` | STATUS | 对头击杀→AOE 恐惧（触发者绑机型） |
| `skill_kill_status_heal` | STATUS | 击杀异常状态敌→回血 |

#### ⚙ PER_TYPE · HARDWARE（机型自带特色武器，§2.6：绑机型不继承，共 6 条）
| id | flavor | 备注 |
|---|---|---|
| `railgun_charge` | STAT | 电磁炮（X-02 等机型自带；离开该机型即无） |
| `railgun_range` | STAT | |
| `railgun_damage` | STAT | |
| `laser_cooldown` | STAT | 激光（载机自带） |
| `laser_range` | STAT | |
| `laser_heat` | STAT | |

> **统计**：GLOBAL 4 · GUN 10 · EW 14 · MISSILE 8 · UNIVERSAL 18 · HARDWARE 6 ＝ 60 行（含状态家族细分），对应代码 41 条 `UPGRADES`（部分一条多效）。新增技能必须在本表登记三字段。

### 2.3 机型系 ↔ 机型 映射（affinity 落到具体机型）

| affinity（武器系） | 现实性格 | 进化树代表机型（具体见 aircraft-evolution 子 spec） |
|---|---|---|
| `GUN` | 机炮猛、厚甲、对地 | **A-10**（确认）；后续对地分支 |
| `EW` | 战术灵活、电子战、隐身 | **F-16**（确认）；电子战分支 |
| `MISSILE` | BVR / 截击 / 载弹 | F-15 基底 / 截击分支（待进化树定稿） |
| `UNIVERSAL` | 飞行/生存通性 | 任意机型 |
| `HARDWARE` | 实验武器平台 | X-02（电磁炮）/ 激光载机 |

> affinity 用**武器系**而非写死机型名 → 对进化树未定稿稳健；门控直接复用 `requires`（机型装备表有无 gun/missile/flare/railgun/laser）。

### 2.4 绑机型的语义（关键裁定）

| 问题 | 裁定 |
|---|---|
| build 记在哪 | 每个机型一份 **TypeBuild**（该机型的 `PER_TYPE` 技能栈）；外加一份 **SquadBuild.global**（`GLOBAL` 技能） |
| 同型多架 | **共享**同一份 TypeBuild（队里 3 架 A-10 吃同一套机炮 build） |
| 战损 | 实例死亡**不清** TypeBuild；只要之后还有同机型实例（生产/进化/复活），自动重放该机型 build（§3.2） |
| 抽到 PER_TYPE 技能时，归到哪个机型 | 归到**当前操控机型**（玩家正驾驶的那架的机型）。GUN/EW/MISSILE 还要求当前机型有对应武器系才进池 |
| 切换操控 | 零成本：各机型 build 已落在各自实例 params，切谁都是该机型满 build |

### 2.5 UI 标注（用户要求）

| 要求 | 规则 |
|---|---|
| 技能描述写明机型 | 升级卡 desc 末尾追加"作用机型：<机型/系>"（走 tr() 三语；`GLOBAL` 显示"全队"） |
| 图形化飞机标签 | 升级卡角标画对应机型/系的**飞机线框小图标**（GUN→A-10 剪影 / EW→F-16 / MISSILE→导弹机 / UNIVERSAL→通用翼 / GLOBAL→小队三机 / HARDWARE→该硬件载机） |
| 专属高亮 | `flavor=TRANSFORM` 的强技用稀有色边框（区分"变身级"与普通 STAT） |

### 2.6 武器绑机型、一律不继承（✅ 用户定 2026-06-28）

**决议：武器/装备是机型的固有属性，换机型即换整套武器，旧武器一律不带走。** 取代 [aircraft-evolution §2.5](aircraft-evolution.md) 旧的"槽位装备跟玩家继承"写法。

- 每个机型**自带**它那套武器档案（A-10=机炮+火箭弹；F-14=远程导弹；X-02=电磁炮…），由机型 params 定义。
- 进化/换机型 → 直接用**新机型**的武器，旧机型的武器（含电磁炮/激光这类 HARDWARE）**消失**。
- 因此 `inheritable` 字段**取消**——没有任何升级跨机型带走；武器不是玩家携带物，是机型属性。
- `HARDWARE`（电磁炮/激光）不再是"全队唯一、玩家携带"的独特武器，而是"某机型自带的特色武器"（拥有该机型即有、离开即无）。
- `STAT/TRANSFORM/STATUS` 技能仍按 `PER_TYPE` 绑机型（见 §2.4：build 记在机型栈，换回该机型可恢复），但**不**跨机型继承。

> 连带影响（待确认）：aircraft-evolution §2.4 的"战区结算三选一"里若有"拿武器/装备"选项，与"武器=机型自带、不携带"语义冲突，可能需改为"二选一（红技能/进化）"或重定义该奖励。已在 aircraft-evolution 标注。

### 2.7 Session 限制（Roguelike，用户确认）

| 项 | 规则 |
|---|---|
| 作用域 | 所有 TypeBuild + SquadBuild.global + 僚机编成 = **单局（session）内**有效 |
| 开局 | 重置为基底机型（F-15，见 aircraft-evolution §2.6）、零升级、初始僚机数 |
| 不跨局 | 升级/强化**绝不**写入 `user://`（MeritLedger 局外货币是另一套，不在此 spec） |
| 重开 | 新一局从头 roll/养 |

### 2.8 生效范围（2026-07-20 用户定调 v2，**权威版**——取代 §2.2 的 GLOBAL/PER_TYPE 生效范围语义；affinity 归类仍用于卡片三轴映射）

> **基本原则（用户）：默认大多数技能全队生效**——长机独强会导致僚机物理掉队
> （编队跟随速度被各自 max_speed_at_altitude 钳制，用户实测吻合）。
> **四层归属（2026-07-20 用户 v4："品类限定"系统取代"王牌专属"）**：
> 1. **通用标配 → 全队直给**（基础数值，每架都有不奇怪；含双体现触发类 B 表）
> 2. **品类限定 → 全队下发、按机种类过滤生效**（强技/稀有技只在特定品类飞机上生效——
>    CIWS 只给攻击机、光环只给骑士系、电战技只给电战机；队里无该品类机 = 该卡不进池）
> 3. **装备门控 → 天然自限**（railgun/laser/rocket/torpedo 强化：没装备=无效）
> 4. **队级单实例**（xp_mult：全局池不逐机相乘）
> —— 原"王牌专属"层**退役**：危险叠加靠品类数量天然限幅（混编队同系只有 1~2 架）；
>    满编单系队吃到全系强化 = 刻意凑 build 的收益，保留（D 观察名单盯量级）。

**飞机品类身份 = 其进化门槛的轴**（与 gates / 卡片三轴同一套词汇，零新概念）：

| 机种类 | 品类身份 |
|---|---|
| 攻击 | 斗士系 |
| 远程 | 骑士系 |
| 电战 | 策士系 |
| 制空 | 斗士+骑士 双系 |
| 桥接（F/A-18E）· 母舰（X-90） | 斗士+骑士 |
| 隐身渗透（X-77） | 骑士+策士 |
| omni（X-02）· 传说（AX-00） | 三系全通 |

#### A. 品类限定表（**只收强技/稀有技**——全队下发、仅品类身份匹配的飞机生效）

> **收窄原则（v5 用户）**：不是所有技能都归品类——玩家得**先加点进化**才能拿到品类机，
> 锁太多 = 前期卡池荒。品类限定只收 ★强技/稀有技（危险叠加档 + 品类招牌技）；
> 中坚触发技与数值技一律通用保卡池厚度（目标：每轴卡池中品类限定占比 ≤ ⅓）。
> 危险叠加由品类数量天然限幅：混编队同系 1~2 架 = 安全；满编单系队 = 刻意 build 收益（D 观察）。

**斗士系**（攻击/制空/桥接/母舰/omni 持有斗士身份的机，4 条）：

| 技能 | 原危险点 | 归系理由 |
|---|---|---|
| gun_ciws | CIWS ×N 敌导弹全灭 | ★用户点名"攻击机才有"——攻击机队近防网=品类特色 |
| skill_missile_hit_invul | 全队轮流无敌 | 强技：近战肉的保命底牌 |
| skill_lowest_alt_kill_invul | 同上 | 强技：低空=攻击机地盘 |
| executioner | 逐机 streak 速度发散 | 稀有技；攻击机速度基线低发散可控（D 观察） |

**骑士系**（远程/制空/桥接/母舰/隐身/omni 持有骑士身份的机，10 条）：

| 技能 | 原危险点 | 归系理由 |
|---|---|---|
| jam_aura | 光环 ×N 全场覆盖 | ★用户点名"光环给骑士" |
| rear_aura_slow | 同上 | 同上 |
| missile_swarm | 饱和 alpha | 远程弹雨=骑士大招（大弹舱机型才玩得转） |
| **超载家族 ×7**：skill_evade_missile_overload / skill_flare_overload / jam_self_overload / cloud_overload / overload_duration_4x / overload_extended_ammo / overload_to_bloodlust | OVERLOAD uptime ×N | ★用户点名"超载类给骑士"——机动生存爆发=骑士性格 |

**策士系**（电战/隐身/omni 持有策士身份的机，11 条）：

| 技能 | 原危险点 | 归系理由 |
|---|---|---|
| skill_gun_kill_fear / head_on_aoe_fear | FEAR uptime ×N | ★心理战=策士定义 |
| skill_flare_aoe_jam / missile_hit_aoe_jam / torpedo_aoe_jam | JAM uptime ×N | 电子战触发技 |
| skill_gun_kill_flare_drop | flare 经济无限 | 电子对抗资源技 |
| fear_squad_spread / fear_chills | 天然队级 | **策士系 + 队级单实例**：只有策士系成员成为恐惧源=双重限幅 |
| ecm_pod / evasion_stealth / vapor_dodge | — | ★用户点名"电战技只给电战机" |

**v5 退回通用**（从 v4 品类表收窄回 E 层，保卡池厚度）：skill_kill_bloodlust · skill_damaged_bloodlust ·
skill_head_on_perma_hp · low_alt_gun_dodge · skill_kill_status_heal · evasion_speed_boost / weapon_cd /
overstock / herbst · cobra_skill（双体现语义不变，见 B 表）。

**层 4·队级单实例**：xp_mult（XP 全局池，stacks 记队级不逐机相乘）。

#### B. 触发/模式强化——**全队·双体现**（2026-07-20 用户裁定：僚机不依赖玩家 E 键，自动触发）

> **代码现状（查实）**：`MissileEvasion.enter_evade` 已让 AI 躲导弹时 `set_evasion_mode(true)`——
> 与玩家 E 键走**同一个门**（`ac.evasion_mode`），技能全队下发后僚机自动吃到，**零新接线**。
> 双体现 = 同一技能、同一效果门，两套触发源，逐条写明。
> **品类标注（v5 收窄后）**：机动五件套 + cobra = **通用**（全队双体现，保卡池厚度）；
> stealth / vapor = **策士系**（用户点名电战技）——即"策士系的机 × 各自触发源"双重过滤。

| 技能 | 玩家体现（E 键手动开关） | 僚机体现（AI 自动） |
|---|---|---|
| evasion_speed_boost | E 期间 cruise ×1.4 冲刺 | 躲导弹自动进 evasion_mode，期间同款冲刺 |
| evasion_weapon_cd | E 期间武器 CD ×0.5 | 同上——躲弹期间反击更快 |
| evasion_stealth | E 期间隐身 | 躲弹期间隐身（甩锁更强） |
| evasion_overstock | E 期间每 4s 补 1 弹 | 躲弹期间自动补弹 |
| evasion_herbst | E 触发 Herbst J-Turn | 躲弹时 AI 自动 Herbst（复用 F-47 模块） |
| cobra_skill | E/评估触发眼镜蛇 | 被咬尾/机炮防御时 AI 自动眼镜蛇 |
| vapor_dodge | 入云隐身 + 切高度 ×2（被动条件） | 同款被动（条件型，无需任何模式） |

⚠ 数值观察点：僚机躲弹频率远高于玩家手动 E → overstock/weapon_cd 的**全队 uptime** 明显高于单人手感，
量级入 D 观察名单随 playtest 盯；玩法上"全队被弹幕逼出集体隐身/冲刺"是想要的戏剧性，保留。

#### C. 武器门控自限（**放心全队**——只有装备该武器的机受益，天然限幅）

railgun_charge/range/damage · laser_cooldown/range/heat/extra_beams · skill_laser_damage · rocket_firerate_range · torpedo_tracking_boost
→ 全队语义 + `requires_equipment_kind` 现成门控：僚机没有电磁炮/激光/火箭 = 自然无效；武器库武器跟王牌走，强化随资源引用迁移（inrun-weapon-inventory）。

#### D. 观察名单（全队放行，bench/playtest 盯量级）

| 技能 | 关注点 |
|---|---|
| gun_multishot（+2 管/机） | 子弹生成量 ×3/机 ×N 机 ≈ 12× 基线 → BulletManager 压测（性能守则 6） |
| proximity_fuze / missile_bounce | AoE/链爆 ×N 对蜂群的清场速度（数值强但线性，先放行） |
| skill_head_on_perma_hp | AI 僚机 joust 对头频率高 → 永久 HP farm 速度 ×N（考虑加单局 cap） |
| skill_kill_bloodlust / damaged_bloodlust | FRENZY 临时 G/速度 buff 逐机异步 → 交战中编队松散可接受，盯 rejoin 收敛 |

#### E. 通用标配：**默认全队直给**（基础数值 + 中坚触发技，卡池厚度的基本盘——用户裁定）

hp_up · armor_up · bullet_dodge · speed_up · maneuver_up · dogfight · flare_shield · shock_absorb · kill_heal ·
missile_count · missile_boost · gun_damage · gun_accuracy · aim_assist ·
skill_kill_bloodlust · skill_damaged_bloodlust · skill_head_on_perma_hp · low_alt_gun_dodge · skill_kill_status_heal ·
evasion_speed_boost · evasion_weapon_cd · evasion_overstock · evasion_herbst · cobra_skill（后五条=全队双体现，B 表）
（+后续新技能默认入此类，除非命中识别模式）

> **归系识别模式**（新技能自检）：①光环/AoE 控场 ×N 覆盖全场；②无敌/拦截类防御 uptime ×N 归零敌威胁；
> ③逐机异步速度 buff 破编队；④全局池经济逐机相乘；⑤饱和 alpha 弹幕；⑥效果有明确品类性格（心理战/机动/近战）。
> 命中任一 → 归入对应品类（A 表）或队级单实例；实在无法归系的超模技才考虑削数值。

#### 附带裁定项（⏳ 用户点头后生效）

1. **三轴里程碑加成同样全队**（纯属性小额，含速度/G——编队一致性同款理由）。
2. **切控散落怪癖自然消解**：技能改全队/品类下发后与"选卡当时开哪架"无关；原"王牌层记玩家层重放"方案随王牌层退役一并作废。

#### 实装草图（用户 review 本表后执行；v4 品类模型）

1. `SurvivorData.UPGRADES` 逐条加 `"classes": ["gladiator"|"knight"|"schemer", ...]`（品类数组；
   缺省/空 = 通用标配全队）+ `"squad_once": true`（xp_mult / fear_squad_spread / fear_chills）。
2. **飞机品类身份查询**：按其进化节点的 gates 轴导出（机种类映射表：attack=斗 / range=骑 / ew=策 /
   air·bridge·carrier=斗骑 / stealth=骑策 / omni·legend=三系）——挂 EvolutionSystem 静态函数。
3. `apply_upgrade` 分流：通用 → 全队逐机；品类 → 全队中**身份匹配**的机；squad_once → 队级记账不逐机写。
4. **抽卡门控**：品类技能只有"队里存在该品类机"才进对应轴的卡池（复用 is_upgrade_available_for 通道）。
5. 重放扩展：僚机补员/进化 → 按新机品类重算生效子集再重放；换型后品类变了 = 技能生效集自然增减。
6. 卡面角标：通用 `◈ 全队` / 品类 = 系名+轴色（AXIS_COLORS 同源），选卡时"谁吃得到"可见。
7. bench：品类过滤断言（策士技不落攻击机）+ 单系满编 uptime 压测（CIWS×N/光环×N）+ 编队 rejoin 收敛。

## 3. 行为与公式（How）

### 3.1 apply_upgrade 按归类分流
```
apply_upgrade(up, acquiring_ac):
    if up.ownership == GLOBAL:
        SquadBuild.global[up.id] += 1
        for ac in 全队存活 team0:           # 广播；含 GLOBAL 的小队级效果
            _apply_global(ac, up)
    else:  # PER_TYPE
        t = (up.affinity == HARDWARE) ? acquiring_ac.instance_key : acquiring_ac.type_id
        TypeBuild[t][up.id] += 1            # 记在机型(或硬件实例)栈
        for ac in 全队存活 team0 where ac.type_id == acquiring_ac.type_id:
            _apply_per_type(ac, up)         # 同机型全部落地
```

### 3.2 僚机生产 + 编入 + build 重放（核心机制）
```
on 奖励"生产 N 架 <机型 M>":                 # 发放归 survivor-loop；几何沿玩家机头前方扇形(见 memory event-spawn-ahead)
    if squad.members.size() + N > MAX_SQUAD(=9): N = 9 - size   # 封顶 9
    for k in N:
        ac = spawn_aircraft(M, team=0)
        SquadFactory.register_wingman(ac, squad, set_state=true)  # 进 SQUAD_FOLLOW，已有 API
        ac.squad_slot = 下一个空号(2..9)
        replay_build(ac):                    # 立即吃满该机型 build
            for id,n in TypeBuild[M]: apply ×n
            for id,n in SquadBuild.global: apply ×n
```
> "同机型保留强化"由此成立：生产的新 M 机直接重放 `TypeBuild[M]`——哪怕之前的 M 机已战损，build 仍在机型栈里。

### 3.3 进化/换机型时的 build 切换
```
on 进化 cur: 机型 X → 机型 Y:                 # 实例不销毁，只换档案(aircraft-evolution §3.1)
    剥离 X 的全部 PER_TYPE 效果（绑机型，一律不带走 §2.6）
    武器换成 Y 自带的武器档案（X 的武器含 HARDWARE 一律丢弃 §2.6）
    应用 Y：replay TypeBuild[Y]（若该局已在别的 Y 机上养过技能，直接满；否则空）
    SquadBuild.global 不变（跟机型无关）
```

### 3.4 编队上限 9 + 1-9 接管
- `MAX_SQUAD = 9`（1 长机 + 8 僚机）。复用既有常量 `COMMANDER_MAX_SQUAD := 9`。
- 接管按键扩 `KEY_1..KEY_9`（`survivor_mode.gd` 的按键 case 一行 case 扩展；公式 `keycode - KEY_1 + 1` 已天然算 1-9）。
- 阵型偏移已对 N≥4 泛化（[squad.gd](../../scripts/squad.gd) finger-four/combat-spread/wedge fallback），**无需改阵型数学**。
- 满 9 架时生产奖励改发"其它奖励"或转化资源（避免溢出静默丢弃 —— perf/UX 守则：不静默截断，要 log/提示）。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `SquadBuild`（global 栈 + 各 `TypeBuild[机型]` 栈 + 硬件实例栈） | 本局 build 单一真源（session 级） | **新增**（survivor 局内单例） |
| `UPGRADES` 加 `ownership/affinity/flavor/inheritable` | 归类权威（§2.2） | 改（survivor_data.gd 数据表） |
| `apply_upgrade` 按归类分流 | GLOBAL 广播 / PER_TYPE 按机型落地 | 改（survivor_player.gd） |
| 抽卡池门控（affinity×当前机型武器系） | 只 roll 当前机型吃得到的 | 改（升级筛选，复用 requires） |
| 僚机生产 + register + replay_build | 奖励即时扩编 + 吃满机型 build | **新增** |
| 进化 build 切换（剥 X 应用 Y） | 换机型换 build | **新增**（接 aircraft-evolution §3.1） |
| 1-9 接管 + MAX_SQUAD=9 | 大编队操控 | 改（1 行按键 + 上限常量） |
| 升级卡机型标签 + 图标 | UI 标注（§2.5） | **新增**（HUD/升级 UI） |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **绑机型落地**：抽 `gun_damage`（GUN）只让队里 A-10 伤害↑，F-16 僚机机炮不变；切到 F-16 操控验证无该加成。
- [ ] **同型共享**：队里 2 架 A-10，抽一次 `gun_damage` 两架都↑；新生产的第 3 架 A-10 自动满机炮 build。
- [ ] **战损不丢 build**：A-10 全损后，生产/进化出新 A-10 → 立即重放 `TypeBuild[A-10]`（机炮 build 回来）。
- [ ] **GLOBAL 全队**：抽 `xp_mult`/`fear_squad_spread` → 全队（含异型僚机）生效。
- [ ] **抽卡门控**：操控无机炮的机型时，池里不出现 `GUN` 系；切到 A-10 才出现。
- [ ] **僚机生产**：奖励"+2 僚机"→ 即时编入 SQUAD_FOLLOW、占号机 2..9、满该机型 build；满 9 时不溢出且有提示。
- [ ] **1-9 接管**：生产到 6 架后按 1..6 都能接管对应号机；按 7-9 在不足时 no-op。
- [ ] **进化换 build**：A-10→某 Y 机 → 机炮 STAT 回退、应用 Y 的 build；硬件按 §2.6 裁定保留/丢失。
- [ ] **UI 标注**：每张升级卡显示作用机型文字 + 飞机图标；TRANSFORM 强技高亮。
- [ ] **Session 重置**：重开新局 → 全部 build 清零、回 F-15 基底（验证不写 user://）。
- [ ] 性能：apply 事件级；按机型广播成本=机型数；9 机 + Lv5+ 压测 FPS 掉幅 <15。
- [ ] 已知 seam：升级不再假设单架玩家机（player_ref）；与 control-switching 换帅、squad-ai-escort 无竞态（登记 known-seams）。
- [ ] i18n：机型标签/作用机型/生产提示走 tr() 三语。

## 6. 实现计划（Task Pipeline）

### 阶段 0 — 前置（依赖定稿）
- [ ] 确认 §2.6 硬件继承 A/B；确认 §2.2 归类无异议。
- [ ] aircraft-evolution 机型 id（A-10/F-16/F-15…）与 affinity 映射对齐（§2.3）。

### 阶段 1 — 归类数据 + SquadBuild 地基
- [ ] `UPGRADES` 全 41 条补 `ownership/affinity/flavor/inheritable`（照 §2.2）。
- [ ] 新增 `SquadBuild`（global + TypeBuild 字典 + 硬件实例栈），survivor 局内单例，**session 级、不落盘**。

### 阶段 2 — apply 分流 + 抽卡门控
- [ ] `apply_upgrade`：GLOBAL 广播 / PER_TYPE 按 type_id（HARDWARE 按实例）落地（§3.1）。
- [ ] 升级筛选按 affinity×当前机型武器系门控（复用 requires）。

### 阶段 3 — 僚机生产 + 编队扩编
- [ ] `MAX_SQUAD=9`；按键扩 `KEY_1..KEY_9`。
- [ ] 生产奖励 → spawn + register_wingman + 占号 + `replay_build`（§3.2）；满 9 处理。
- [ ] 阵型/HUD 面板验 N≤9（数学已泛化，主要验 UI 布局宽度）。

### 阶段 4 — 进化 build 切换 + UI 标注
- [ ] 进化时剥 X / 应用 Y（§3.3），接 aircraft-evolution §3.1。
- [ ] 升级卡机型文字 + 飞机图标 + TRANSFORM 高亮（§2.5）。

### 阶段 5 — 验收调优
- [ ] 跑 §5 全部 + 切换/进化/战损/9 机边界 + 性能压测。
- [ ] 更新 §7 锚点 + reference 索引 + known-seams。
- [ ] status → done，reconstruction_complete → true。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 升级数据表 + 归类字段 | `scripts/survivor/survivor_data.gd`（UPGRADES） |
| apply 分流 | `scripts/survivor/survivor_player.gd`（apply_upgrade） |
| SquadBuild 真源 | `scripts/survivor/...`（新增，session 级） |
| 僚机注册 API | `scripts/squad_factory.gd`（register_wingman） |
| 阵型偏移（已泛化 N） | `scripts/squad.gd`（get_formation_offset） |
| 接管按键 / MAX_SQUAD | `scripts/survivor/survivor_mode.gd`（_switch_control_to_slot / KEY_1..9） |
| 升级卡 UI | `scripts/survivor/survivor_upgrade_ui.gd` / survivor_hud.gd |
| reference 索引行 | script-index.md / code-index.md 升级与编队段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 初稿：数值跟队共享 + 独特武器跟机实例（旧模型）。后标 §0 前提失效待重构。 |
| 2026-06-28 | 2 | **整体重写**（用户定调绑机型）：①三归类字段 `ownership/affinity/flavor/inheritable`；②全 41 技能归类总表（GLOBAL 4 / GUN / EW / MISSILE / UNIVERSAL / HARDWARE）；③绑机型语义（同型共享、战损不丢 build、抽卡按机型武器系门控）；④僚机生产+编入+build 重放、编队上限 9、1-9 接管；⑤UI 机型标签+图标；⑥Session 内 Roguelike 不跨局。 |
| 2026-06-28 | 2 | §2.6 定案（用户）：**武器/升级一律绑机型、不跨机型继承**。取消 `inheritable` 字段；HARDWARE（电磁炮/激光）改为"机型自带特色武器"非玩家携带物；§3.3 进化时换整套新机型武器、旧武器丢弃。取代 aircraft-evolution §2.5 旧"槽位继承"。 |
| 2026-07-20 | 3 | **§2.8 生效范围二分（用户令，权威）**：现状查实=全部技能只写当前操控机（长机吃速度/机动强化 → 僚机被 max_speed 钳制物理掉队）。新二分：**全队 9 条**（speed_up/maneuver_up/dogfight 机动一致性 + hp/armor/dodge/flare_shield/shock_absorb 生存底盘 + xp_mult 经济）/ **王牌 48 条**（武器数值/特殊武器强化/规避操作/光环挂王牌/触发技）。附带裁定项待用户点头：①里程碑同样全队；②王牌技随玩家层（切控/进化重放到当前操控机，根治"技能散落在选卡当时那架"怪癖）。取代 §2.2 的 GLOBAL/PER_TYPE 生效范围语义（affinity 仍用于三轴卡片映射）；实装草图 5 条待 review 后执行。 |
| 2026-07-20 | 4 | **§2.8 v2 方向反转（用户）："默认全队 + 排查危险叠加"**取代 v3 的 9/48 保守二分。A 危险叠加 13 条→王牌专属（光环×N 全场覆盖 jam_aura/rear_aura_slow、防御 uptime×N 归零威胁 gun_ciws/双 invul、AoE 控场触发×5+flare_drop 的 FEAR/JAM 永久 uptime、饱和 alpha missile_swarm、编队速度发散 executioner）+ 队级单实例 3 条（fear_squad_spread/chills 天然队级、xp_mult 不逐机相乘）；B 空转 7 条（evasion_*/cobra/vapor 挂玩家 E 键）暂王牌、待 AI 规避接线转全队；C 武器门控自限全队放行（railgun/laser/rocket/torpedo 强化）；D 观察名单 4 条（multishot 弹幕性能/perma_hp farm cap/bloodlust 编队松散）；E 其余默认全队。附 A 类识别模式 5 条（新技能自检）。scope 三值 squad/ace/squad_once。 |
| 2026-07-20 | 5 | **§2.8 v3 双体现定义（用户："回避类在僚机身上不依赖 E 键自动触发"）**：查实 MissileEvasion.enter_evade 已让 AI 躲弹时 set_evasion_mode(true)（与玩家 E 同门）→ 原 B"空转名单"判断作废，7 条回避/机动技全部转**全队·双体现**（表格逐条写明 玩家=手动 E / 僚机=AI 躲弹自动；herbst/cobra 复用既有 AI 模块，零新接线）。三类定义定稿：①数值强化=全队直给 ②触发/模式强化=全队双体现 ③专属强化=王牌显式清单（A 表 13 条）。僚机躲弹频率高 → overstock/weapon_cd 全队 uptime 入 D 观察名单。 |
| 2026-07-20 | 6 | **§2.8 v4 品类限定系统（用户："强技只出现在特定品类飞机上"）**：王牌专属层退役 → 四层归属=①通用标配全队直给 ②品类限定（全队下发、按机种类过滤生效：CIWS→斗士系攻击机[用户点名]/光环→骑士系[用户点名]/电战·心理战技→策士系[用户点名]+同逻辑扩展 bloodlust·无敌·executioner→斗/missile_swarm·evasion 机动五件套→骑/AoE 控场·stealth 系→策）③装备门控自限 ④队级单实例（xp_mult；fear 双条=策士系+单实例双重限幅）。飞机品类身份=其进化门槛的轴（attack=斗/range=骑/ew=策/air=斗骑/stealth=骑策/omni·legend=三系，零新概念）。危险叠加靠品类数量天然限幅，单系满编=刻意 build 收益入 D 观察。抽卡门控=队里存在该品类机才进池；切控散落怪癖随全队下发自然消解。实装草图 v4（classes 数组/身份查询/过滤分流/品类角标/过滤断言）。 |
| 2026-07-20 | 7 | **§2.8 v5 品类收窄 + 超载归骑士（用户）**：①"不是所有技能都归品类——先加点才能到品类机，锁太多=前期卡荒"→ 品类限定只收强技/稀有技（每轴卡池占比目标 ≤⅓）；v4 过度扩展的 10 条退回通用（嗜血双条/对头永久HP/低空闪避/异常收割/机动五件套/cobra——双体现语义保留）。②**超载家族 ×7 → 骑士系**（用户点名；含 cloud_overload）。终版：斗士系 4（CIWS/双无敌/executioner）· 骑士系 10（双光环/swarm/超载×7）· 策士系 11（AoE 控场×6/恐惧双条/ecm·stealth·vapor）· 通用 24+ · 装备门控 · xp 单实例。 |
