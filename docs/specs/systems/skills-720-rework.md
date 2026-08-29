---
id: skills-720-rework
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 20
owner: 用户
depends_on: [evolution-attribute-gates, afterburner-mode, active-special-maneuvers, inrun-weapon-inventory, command-wheel, zone-reward-docking]
reconstruction_complete: true
---

# 720 技能整改批 —— +1 轴进度 / 归属词汇 v6 / 新增 27 · 改动 ~35 · 移除 1

> 来源：用户 2026-07-20 基于 `docs/reference/skill-table.md`（79 条自动生成表）逐条整改的 720 表。
> 本 spec 是该表的结构化定稿：数值/归属/轴以本文为权威；实施后重跑 `tools/dump_skill_table.py` 刷新参考表。

## 1. 设计意图（Why）

1. **"+1 轴进度"系统（用户新设计）**：部分技能带"某轴+1"备注——激活后奖励的**不是技能点（进化门槛货币），
   而是该轴的里程碑进度**。评估：✅ 合理且巧——
   - 解耦"进化门槛"（只能靠选卡的刻意投入）与"里程碑成长"（可被顺路技能推进）→ 选卡多一层纵深；
   - 当前点数收入上限 8，里程碑 10 点预留档本来摸不到——**"+1"正是够到预留档的通道**（预留档就此激活）；
   - 跨轴 +1（斗士卡带"策士+1"）让偏科 build 也能蹭到他轴首档，呼应"里程碑拉平衡"立意。
   - ⚠ 收支护栏：全表 +1 计 13 条（骑士+1 ×7 / 斗士+1 ×4 / 策士+1 ×2）。同轴全收 = 进度 +7，
     叠 8 点收入远超 10 满档 → **每轴 milestone_bonus 上限 cap = 2**（超出浪费，量表画到顶）。
     ✅ 2026-07-21 定案：采用 **cap = 2**（开工确认按推荐值直采；备选"不 cap、抬 12 档"废弃）。
2. **归属词汇 v6**（表中实际使用的全集，取代 §2.8 v5 的四层）：
   | 归属 | 语义 | 实现载体 |
   |---|---|---|
   | 通用全队 | 全队逐机生效 | scope 缺省 |
   | X 限定（斗士/骑士/策士） | 全队下发、仅品类身份匹配机生效 | `classes` 数组 |
   | **王牌** | 仅当前操控机生效（含"对在操作的飞机生效"）| `scope:"ace"`（v5 退役层回归，仅限 AoE 控场/操作型强技）|
   | X 限定＋王牌 | 品类过滤 ∩ 操控机 | `classes`+`ace` |
   | 装备门控 | 全队、没装备自然无效 | 既有 `requires` |
   | 队级单实例 | 队级记账不逐机（1→**8 条**大扩容）| `scope:"squad_once"` |
   | **机型限定**（A10 限定等） | 仅指定机型 | 既有 `exclusive_to` ✅ 零新建 |
   | **需要词条** | 需先持有前置技能 | 既有 `requires_skill` ✅ 零新建 |
3. 王牌层回归说明：v5 曾整层退役；720 表为 ~7 条 AoE 控场/操作强技恢复王牌（机炮震慑/寒颤号令/凝视压迫/
   武器大师/电子战专家 + 组合位 惊鸿扩散/导弹蜂群/云中超载/后半球减速光环/对锋干扰）——正是 v2 危险叠加
   名单的最凶档，品类过滤仍嫌不够 → 王牌单机是正确终点。**不矛盾，是收敛。**

## 2. 数据定义（What —— 权威源）

### 2.1 "+1 轴进度"清单（新字段 `milestone_plus: "gladiator"|"knight"|"schemer"`）

| 技能 | +1 轴 |
|---|---|
| 漂浮雷·猎手感应 | 策士 |
| 虐弱 | 策士 |
| 漂浮雷：额外 · 加力供弹 · 雾隐机动 · 寒颤号令 · 对锋干扰 · 忠诚僚机.武装 | 骑士 |
| 被锁狂飙 · 噬血共振 · 后半球减速光环 · 机炮余烬 | 斗士 |

### 2.2 新增技能（27 条；轴=卡池归属，实现挂点见 §3 分组）

**斗士轴（10）**
| id（拟） | 技能 | 归属 | 稀 | 层 | 效果 |
|---|---|---|---|---|---|
| torpedo_extra | 漂浮雷：额外 | 装备门控 | 1 | ×2 | 漂浮雷数量 +1/层（骑士+1） |
| qmaam_boost | QAAM 强化 | 装备门控 | 1 | ×2 | 格斗弹 +1、射程 +10%/层；格斗弹击杀 → 10s 嗜血 |
| gun_reserve_mag | 备用弹仓 | 通用 | 3 | ×2 | 机炮弹尽后 30%（双层 50%）概率立刻回满 |
| gun_out_free_missile | 副武器 | 通用 | 2 | ×1 | 机炮弹尽冷却期内发射导弹不消耗弹药 |
| squad_revenge | 复仇之战 | 队级单实例 | 1 | ×1 | 僚机/王牌被击坠 → 全队嗜血+无敌 15s |
| guard_zone_buff | 保卫阵地 | 队级单实例 | 2 | ×1 | 轮盘【防守此区】圈内全队减伤 + 回转/减速强化 |
| cockpit_armor | 座舱护甲 | 通用 | 2 | ×2 | 地面火力（SAM/AA/CIWS）伤害 −50%、机炮闪避 +20%/层 |
| weapon_master | 武器大师 | 王牌 | 2 | ×1 | 按装备武器数降低全武器 CD（每件 5%，上限 30%；起手 gun+msl=10%） |
| veteran_hp | 历战者 | 通用 | 1 | ×1 | 按已持有【斗士轴】技能数 ×(+5 HP) 提升全队血量，上限 +100 |

**骑士轴（9）**
| id（拟） | 技能 | 归属 | 稀 | 层 | 效果 |
|---|---|---|---|---|---|
| ab_kill_charge | 检讨 | 通用 | 1 | ×2 | 击杀的加力充能奖励 +0.6s/层（基线 +0.8s） |
| ab_duration | 强化加力 | 通用 | 1 | ×2 | 加力耗能减慢，续航 +50%/层（满能量 6s→9s→12s） |
| headon_xp | 骑士心脏·历练 | 通用 | 1 | ×1 | 对头击杀获得更多经验 |
| railgun_double | 双发 | 装备门控 | 4 | ×1 | 电磁炮蓄力完成后连发两发 |
| missile_second_stage | 二段推进 | 通用 | 3 | ×1 | 导弹越飞越快、转弯渐强（距离越远越准） |
| adapt_energy | 适应 | 通用 | 4 | ×1 | 击杀低于自己高度的敌人回加力能量；高于自己回 20 HP |
| evac_shift | 阵地转移 | 通用 | 2 | ×1 | 轮盘【撤离此区】后移速更快 + 全伤害 −50% |
| assassin_revenge | 刺客复仇 | 队级单实例 | 1 | ×1 | 僚机/王牌被击坠 → 全队 15s 超载+隐身 |
| manual_dodge | 胆大妄为 | 通用全队 | 3 | ×1 | 全队禁普通自动 flare、flare +6；受控机 R 手动闪避，AI 僚机受威胁自动；无 flare 也可滚转，命中瞬间 i-frame 时机严格 |
| speed_by_knight | 全速推进 | 通用 | 1 | ×1 | 按已持有【骑士轴】技能数提升最高速度，上限 +40% |

**策士轴（8）**
| id（拟） | 技能 | 归属 | 稀 | 层 | 效果 |
|---|---|---|---|---|---|
| levelup_heal | 升级回复 | 队级单实例 | 2 | ×1 | 每次升级全队回 10 HP |
| ground_crew | 地勤优化 | 队级单实例 | 1 | ×1 | 机场/航母停靠耗时更短；起飞后获得一个升级 |
| pack_gaze | 群猎注视 | 队级单实例 | 3 | ×1 | 全僚机共同锁定的敌机持续一定时间后减速（F-14 专属沿用 exclusive_to） |
| blackbox_recovery | 黑匣子回收 | 队级单实例 | 1 | ×1 | 僚机/王牌被击坠 → 获得一个升级 |
| ew_expert | 电子战专家 | 王牌 | 1 | ×1 | 按已持有【策士轴】技能数提升雷达距离，上限 +1km |
| wingman_extra | 忠诚僚机.额外 | 装备门控 | 1 | ×2 | 可存在的忠诚僚机数量 +1/层 |
| wingman_armed | 忠诚僚机.武装 | 装备门控 | 1 | ×1 | 忠诚僚机伤害/射程提升（骑士+1） |
| （群猎注视为 集火枷锁 改版，见 §2.3）| | | | | |

### 2.3 改动技能 delta（以 720 表为准；仅列有变化项，⚠=改数值必须同步三语 desc）

| 技能 | 变化 |
|---|---|
| 激光·分束扩容 | 每层 +2 束 → **+1 束** |
| 贴地骑士→**空中战车** | 改名；斗士限定 → **A10 限定**（exclusive_to） |
| 多管齐射→**机炮吊舱** | 三道(前+左右15°) → **两道翼挂朝前**；归属"斗士限定·全队" |
| 血誓不竭 | 去掉"满血"前置条件（嗜血期间击杀即可）；机密→实验 |
| 枪械精度 | ×4→×2；追加"子弹生存时间加长" |
| 穿甲弹药 | +55%→**每层伤害 +30%、弹仓上限与当前弹药 +50%**、×1→×2 |
| 火力护盾 | 0.4s→0.5s |
| 装甲强化 | +80→**+30**、×1→×2 |
| 战场急救 | 10HP→5HP、×3→×1；2026-08-24 后并入“虐弱”，不再作为独立卡出现 |
| 反击本能/猎杀本能 | 8s→9s |
| 侩子手 | 斗士限定→**骑士**；机密→先进 |
| 骑士心脏/正面回旋 | 斗士轴→**骑士轴**（category 迁移） |
| 导弹蜂群 | 骑士限定+**王牌**；**进战区奖励池**（evolved=true） |
| 电磁炮加速 | −20%→−30%、×3→×2 |
| **电磁炮强化** | **移除**（railgun_damage 删除） |
| 电磁炮射程 | +500m→**+1500m** |
| 飞控升级 | roll+45%→+30%、G+2.5→+1.5、×1→×2 |
| 火箭助推 | ×3→×2 |
| 导弹挂架扩展 | ×1→**×3** |
| 引擎强化 | +30%/+20%→**+20%/+10%**、×1→×2 |
| 平流层雷达/绝境装填 | 策士轴→**骑士轴** |
| 云中超载 | 骑士限定+**王牌**；2026-08-06 起技能轴直接归骑士，不再额外骑士+1 |

### 2.4 2026-08-24 合并收口（取代 §2.2–2.3 中同名旧行）

| 保留 id | 合并结果 |
|---|---|
| `wingman_extra` | 一层；同屏上限 +2，并在获得当下立即部署 2 架忠诚僚机。 |
| `laser_range` | 两层；每层同时获得激光射程 +20% 与同时照射目标 +1；删除 `laser_extra_beams`。 |
| `gun_accuracy` | 两层；每层同时获得散布 -20%、瞄准精度 +18%、弹寿命 +20%、自动开火锥 +25%（半角上限 45°）；删除 `aim_assist`。 |
| `speed_up` | 一层；基础最大速度 +10%、加速 +10%，并保留原“全速推进”的骑士轴计数极速 +5%/条（上限 +40%）；删除 `speed_by_knight`。 |
| `close_range_lock` | 一层、先进级；保留近距锁定曲线并获得机炮装填期导弹免耗；删除 `gun_out_free_missile`。 |

正式技能总数因此由 167 条收口为 163 条；旧 id 不再进入正式池或 F4 动态清单。

### 2.5 2026-08-24 稀有度与穿甲弹药追补

| 技能 | 定稿调整 |
|---|---|
| `squad_revenge`（复仇之战） | 稀有度由实验级改为稳定级；触发条件、15 秒嗜血与无敌效果、单层队级语义不变。 |
| `assassin_revenge`（刺客复仇） | 稀有度由先进级改为稳定级；触发条件、15 秒超载与隐身效果、单层队级语义不变。 |
| `gun_damage`（穿甲弹药） | 保持稳定级两层；每层机炮伤害 +30%，并同步令机炮弹仓上限与当前弹药 +50%。多层按每次获得时的当前值乘算。 |

| 雾隐机动 | 策士限定→**通用全队**；骑士+1；**进战区奖励池** |
| 寒颤 | 策士限定→通用 |
| 惊鸿扩散 | 策士限定+**王牌**；8s→5s |
| 全向干扰场 | 骑士限定→**斗士限定**；干扰时长明确 4s |
| 共振反馈 | 骑士限定＋需要词条（requires_skill：**JAM 来源技**——729 修正，原写"超载入门技"是错的，见 §8 v9）；技能轴归骑士 |
| 激光散热（合并激光过载） | ×2；每层散热效率 +40%、过热阈值 +50% |
| 激光增距 | ×3→×2 |
| 过载/燃尽/噬血共振 | 骑士限定→**通用＋需要词条**；技能轴均归骑士（噬血共振保留斗士+1 跨轴桥） |
| 后半球减速光环 | 骑士限定→**斗士限定＋王牌**；斗士+1 |
| 机炮震慑 | 策士限定→**王牌** |
| 机炮余烬 | 策士限定→**斗士限定**；斗士+1 |
| 寒颤号令 | 策士限定→**王牌**；3km→2km；骑士+1 |
| 寒蝉效应 | 策士限定→通用；800px→**2km**；⚠ 修友军误伤 bug（§4） |
| 数据链 | **取消 F-14 专属**；队级单实例；雷达+50%→+20%；⚠ 生效性排查（§4） |
| 集火枷锁→**群猎注视** | 改名；队级单实例（仍 F-14） |
| 凝视压迫 | 通用→**王牌**；实验→次世代 |
| 对锋干扰 | 通用→**骑士限定＋王牌**；骑士+1 |
| 弹后潜匿 | 5s→4s |
| QAAM/漂浮雷/忠诚僚机强化 | 见 §2.2 新增（装备门控家族扩容） |
| 稀有度全表 | 按 720 表数字列重标（1~5 → 稳定~次世代） |

### 2.6 2026-08-24 虐弱 / 战场急救合并

保留 `skill_kill_status_heal`（虐弱），删除独立 `kill_heal`（战场急救）。合并卡保持先进级、一层、
通用全队、策士里程碑 +1 与原有恐惧/JAM 词条前置：

- 每次由玩家小队成员完成击杀时，实际击杀者回复 5 HP；
- 被击杀目标带任意异常状态时，再额外回复 30 HP，即合计 35 HP；
- 地面目标不经过 Aircraft 击杀钩子，由 `survivor_spawner` 的地面结算入口补齐同一数值；
- 正式技能总数由 163 条收口为 162 条，旧 id 不再进入正式池或 F4 动态清单。

### 2.7 2026-08-24 座舱护甲 / 闪避机动合并

保留 `cockpit_armor`（座舱护甲），删除独立 `bullet_dodge`（闪避机动）。合并卡保持先进级、两层、
通用全队；每层同时提供：

- 来自地面火力（SAM/高炮/CIWS）的伤害 ×0.5；
- 机炮闪避 +20%，继续受全局 85% 闪避上限约束；
- 正式技能总数由 162 条收口为 161 条，旧 id 不再进入正式池或 F4 动态清单。

### 2.8 2026-08-25 QAAM 强化 / QAAM 嗜血合并

保留 `qmaam_boost`（QAAM 强化），删除独立 `qmaam_bloodlust`（QAAM 嗜血）。合并卡保持稳定级、
两层、斗士轴与格斗弹装备门控，并继承 `bloodlust` 词条门控：

- 每层格斗弹携带量 +1、射程 +10%；
- 从第一层起，格斗弹击杀使实际击杀者进入嗜血状态 10 秒；
- 三个嗜血终端的合法来源由旧 id 改为 `qmaam_boost`；
- 正式技能总数由 161 条收口为 160 条，旧 id 不再进入正式池或 F4 动态清单。

### 2.9 2026-08-25 激光散热 / 激光过载合并

保留 `laser_cooldown`（激光散热），删除独立 `laser_heat`（激光过载）。合并卡保持先进级、两层、
策士轴与激光装备门控；每层同时提供：

- 散热效率 +40%；
- 过热阈值 +50%；
- 两层按每次获得时的当前值乘算，满层分别为基线 ×1.96 与 ×2.25；
- 正式技能总数由 160 条收口为 159 条，旧 id 不再进入正式池或 F4 动态清单。

### 2.10 2026-08-25 地表狂奔 / 空中战车合并

保留 `low_alt_gun_dodge`（地表狂奔），删除独立 `skill_lowest_alt_kill_invul`（空中战车）。合并卡为
机密级、一层、通用全队，不再带 A-10 或任何机型限定，并继续要求机炮：

- LOW/GROUND 档位受到机炮攻击时，机炮闪避 +50%，继续受全局 85% 闪避上限约束；
- LOW/GROUND 档位击杀敌人后，自身获得 8 秒无敌；
- 正式技能总数由 159 条收口为 158 条，旧 id 不再进入正式池或 F4 动态清单。

### 2.4 超载技能轴统一（2026-08-06 定稿）

超载是骑士的**导弹爆发/追击窗口**。归轴按技能的主要产出决定，而不是沿用旧 `electronic_warfare`
类别：产生 OVERLOAD、消费其窗口、延长它或把其它状态转成它的技能，均进骑士轴卡池。

| 类型 | 技能 id | 轴 / 额外进度 |
|---|---|---|
| 来源 | `cloud_overload` / `skill_evade_missile_overload` / `skill_flare_overload` / `jam_self_overload` / `assassin_revenge` / `sig_mig41` | 全部骑士；`cloud_overload`、`skill_flare_overload` 删除同轴 `milestone_plus:knight` |
| 终端 | `overload_duration_4x` / `overload_extended_ammo` / `overload_to_bloodlust` | 全部骑士；`overload_to_bloodlust` 保留 `milestone_plus:gladiator` 作为跨轴桥 |

三个终端的 `requires_skill` 采用 OR 语义，必须覆盖上述六个真实 OVERLOAD 来源。`jam_self_overload`
自身仍以前置 JAM 来源解锁；这条前置决定它能否触发，不与它作为后续超载终端的合法来源冲突。

## 3. 实现对照（复用 / 追加 / 新建）

### 3.1 ✅ 纯数据改动（零代码：改表 value/stacks/rarity/classes + i18n 三语）
全部 §2.3 数值 delta、稀有度重标、轴迁移（category 改字）、A10 限定（`exclusive_to` 现成）、
需要词条（`requires_skill` 现成）、导弹蜂群/雾隐进奖励池（`evolved` 现成）。

### 3.2 ✅ 复用既有钩子（小改：新表条目 + 挂现成事件点）
| 技能 | 复用点 |
|---|---|
| 检讨/适应 | `afterburner_charge` 击杀充能钩子（2026-07-20 现成）+ 高度比较 |
| 强化加力 | 加力耗能减慢参数（`duration_mult`） |
| QAAM 强化（合并嗜血） | 击杀归因含武器类型（combat-feed 已做）→ apply_status BLOODLUST |
| 升级回复 | `leveled_up` 信号 → 全队回血 |
| 保卫阵地 | SquadCommandController `_tick_guard` 圈内状态现成 → 注入队 buff |
| 阵地转移 | 撤离 `command_sprint` 状态现成 → 叠减伤/提速 |
| 地勤优化 | zone-reward-docking 停靠计时 + 起飞钩子 → 发一次卡片事件 |
| 群猎注视 | 集火枷锁现有实现改名/调参 |
| 历战者/全速推进/电子战专家/武器大师 | `recompute_category_bonuses` 现成重算点扩"按轴计数缩放"（用户注："每次拿到技能都要重算"——正是该函数的调用时机） |
| QAAM/漂浮雷/忠诚僚机 强化组 | secondary_missile / torpedo / loyal_wingman params 字段直改（apply_upgrade 加 stat 分支，同 railgun 模式） |

### 3.3 🔧 追加新功能（中等：一个新事件点/字段，多技能共用）
| 功能 | 服务技能 |
|---|---|
| **僚机阵亡事件**（Squad 成员 destroyed → 队级信号） | 复仇之战 / 刺客复仇 / 黑匣子回收（三技共用一个钩子） |
| **机炮弹尽事件**（ammo 耗尽瞬间信号） | 备用弹仓 / 副武器 |
| **地面来源减伤 + 机炮闪避**（take_damage 按攻击方 is GroundUnit 过滤；闪避复用既有字段与全局 cap） | 座舱护甲 |
| **子弹寿命字段**（bullet lifetime +） | 枪械精度新增段 |
| **milestone_bonus 轴进度**（§1.1，含量表加成格显示） | 全部 +1 技能（13 条） |
| **品类过滤分流**（squad-upgrade-ownership §2.8 的 classes/ace/squad_once 落地——此前搁置，并入本批） | 全部品类/王牌/单实例技能 |

### 3.4 🆕 全新机制（大：独立实现）
| 机制 | 说明 | 依赖/复用 |
|---|---|---|
| **胆大妄为（R 键手动闪避）** | 禁自动 flare + R 手动（flare+滚转）+ 无 flare 严格时机滚转 i-frame | 复用加力窗口刚做的"滚转甩导弹→is_flare_jammed 偏飞契约"+滚转动画；新增 R 输入与 i-frame 时机判定窗 |
| **机炮吊舱 rework** | gun_extra_barrels 发射位从机头扇形改翼挂双点朝前 | 改 `_fire_gun_round` 出膛偏移 |
| **电磁炮双发** | 蓄力完成连发 ×2 | RailgunEquipment 发射序列小状态机 |
| **导弹二段推进** | 飞行时间→速度/转弯增益曲线 | missile.gd 阶段参数 |

## 4. 排查项（阶段 0 先行）

1. **数据链生效性**：确认锁定共享是否真生效；**关键问题：玩家能否对僚机锁定的目标发射导弹**（武器发射门是否认队友锁）——结论决定"取消 F-14 专属"后它的实际价值。
   - ✅ **结论（2026-07-21）：共享真生效，且玩家可对僚机锁定的目标直接发射。**
     机制：雷达主更新（survivor_mode）每 tick 把全队（team 0、未被 JAM）radar_targets 里同一目标的
     照射进度取最大值互相拉平；导弹发射门（aircraft_weapons 单发与多锁齐射两路）读的正是自机
     radar_targets 累积值 → 共享写入即算自己锁满。发射仍要过三关：导弹包线（min/max range）、
     自机雷达锥（目标须在机头锥内）、发射窗口质量（急转/锥边缘不射）。
     → **实际价值 = 省掉整段锁定累积时间（lock_time 连续照射数秒）**：僚机锁住后，机头一指即射。
     取消 F-14 专属后价值成立，转"队级单实例"合理。
   - ⚠ 顺带查出两个生效性缺口（T1 squad_once 落地时一并根治）：
     ① aura 判定读"当前操控机"的 aura_skill 字段，而该字段只写在拿技能那一架上 → **切控后共享静默关闭**；
     ② 僚机雷达 ×1.5 只应用于拿技能瞬间在场的僚机 → 之后入队的新僚机吃不到。
     squad_once 语义落地 = 标记迁队级账本 + 新成员入队 re-apply，两洞同根治。
2. **寒蝉效应友军误伤 bug**（用户实测）：被弹 AoE JAM 疑似波及队友——查实现加 team 过滤。
   - ✅ **实锤并已修复（2026-07-21）**：AOE 广播（aoe_broadcast.apply_status_in_radius）的 team_filter
     传了 -1（语义=不过滤队伍）→ 半径内友军全中，连受害者自己（圆心距离 0）也被 JAM；顺带把
     on_player_jam_landed 命中计数灌水（jam_self_overload"JAM 命中≥1 敌→自身超载"因自己算 1 发而必触发）。
     修复：改传 TEAM_HOSTILE。**同病同修**：机炮击杀落 flare（skill_gun_kill_flare_drop）的 JAM
     同样传 -1，一并修复；对照组 flare_aoe_jam / torpedo_aoe_jam 本来就传敌方过滤，无恙。

## 5. 验收

- [x] +1 轴进度：选带 milestone_plus 的卡 → 对应轴里程碑进度 +1（cap 2）、量表加成格可见、gates 点数不变（双计数断言）。✅ bench `skills720` C 组
- [x] 品类/王牌/单实例过滤：策士限定不落攻击机、王牌技只在操控机、单实例不逐机（bench 断言）。✅ bench B/D 组 + 王牌 strip 往返 F 组
- [x] 新技能 27 条逐条烟测（触发钩子类打 EventLogger 标记）；移除电磁炮强化后旧存档/奖励池无悬空引用。✅ 核心钩子 bench E/G/H 组覆盖 + 全部触发点带 EventLogger 标记（F4 面板可逐条灌注实测）；railgun_damage 全仓零残引
- [x] 数值 delta 全表三语 desc 同步（⚠ feedback 铁律）；重跑 dump_skill_table 与 720 表零 diff。✅ 三语 63 改/46 新键；生成表 104 条与数据零 diff（720 原始表未入库，按 §2 明细执行）
- [x] 排查双项闭环（数据链结论写回本 spec；寒蝉 team 过滤修复）。✅ §4
- [x] 超载轴统一：9 条相关技能全归骑士；云中超载/焰诱共振无同轴重复 +1；3 个终端均接受 6 个真实来源。✅ bench `skills720` I 组
- [x] 2026-08-25 今日技能改动全装共存：以非 A-10 的 F-16 身份测试机，经正式 `_distribute_upgrade` / `_refresh_squad_effective_stacks` 路径装入 13 张保留卡、共 19 层；机炮、引擎、座舱、激光、QAAM、近距捕获与低空防御复合效果同时成立，忠诚僚机上限 2→4 且即时生成 2 架。低空 QAAM 击杀 JAM 目标同时回复 35 HP、触发 10 秒嗜血与 8 秒无敌；队员阵亡时复仇之战与刺客复仇共同触发嗜血/无敌/超载/隐身四个 15 秒状态。✅ `skills720` F2h 22 项；focused 350/350；`all` 83 组 0 失败，lifecycle 80/80
- [ ] 回归门全绿 ✅（32 项）+ **playtest ⏳（待用户：吊舱手感/胆大妄为时机窗/保守暂定数值调档——历练 ×1.5、适应 +3s、保卫 30%/15%、转移 15%/50%、全速 +5%/条、专家 +100m/条、QAAM +10%、僚机 +30%/20%、子弹寿命 +20%）**

## 6. 任务拆分（依赖序）

- [x] **T0 排查批**：数据链生效性 + 僚机锁可射性结论；寒蝉效应 team 过滤修复。（½ 天级）✅ 2026-07-21
- [x] **T1 归属底座**：`classes`/`scope:"ace"`/`squad_once`/`milestone_plus` 四字段 + apply_upgrade 品类过滤分流 + 品类身份查询（squad-upgrade-ownership §2.8 实装并入）+ milestone_bonus 双计数与量表加成格 + 卡面角标。**本批地基，先行。**✅ 2026-07-21（bench `skills720` 31 断言 + 回归门 32 项全绿；含 T0 缺口根治：数据链/集火改队级账本判定、切控王牌迁移 chokepoint、新僚机入队补挂钩子、F4 面板同语义）
- [x] **T2 纯数据批**：§2.3 全部 delta（value/stacks/rarity/轴迁移/A10 限定/需要词条/奖励池迁移/移除 railgun_damage）+ 27 条新表条目中零代码可落的（QAAM/漂浮雷/忠诚僚机强化组、座舱护甲字段版）+ i18n 三语全同步 + 重跑生成器。✅ 2026-07-21（83 条；+1 分布 骑8/斗4/策2 按 §2.1 表；生成器 v6 化直读 scope/classes/milestone_plus）
- [x] **T3 钩子批**：僚机阵亡事件（3 技共用）/ 弹尽事件（2 技）/ 升级回复 / 轮盘联动 ×2 / 地勤优化 / 检讨·适应·强化加力（AB 钩子）/ QAAM 嗜血。✅ 2026-07-22（14 条新技能 + headon_xp；skills720 bench 45 断言全绿）
- [x] **T4 计数缩放批**：历战者/全速推进/电子战专家/武器大师（recompute 扩展一次做四条）。✅ 2026-07-22（recompute_axis_count_skills 挂 recompute_category_bonuses 尾部；skills720 bench 54 断言）
- [x] **T5 新机制批**：胆大妄为 R 手动闪避 → 机炮吊舱 rework → 电磁炮双发 → 导弹二段推进（各自独立可拆单）。✅ 2026-07-22（§2.2 全部 27 行到位 → 全表 104 条；skills720 bench 66 断言）
- [x] **T6 收尾**：bench 断言全套 + 表重生成 + spec §7 锚点 + playtest 调数值。✅ 2026-07-22 工程侧闭环（skills720 66 断言 / 104 条表 / §7 回填 / changelog）；**playtest 调数值待用户**（暂定值清单见 §5 末条）

## 7. 实现锚点（Where —— 纯指针，行号见 reference 索引）

| 关注点 | 位置 |
|---|---|
| 归属四字段文档 + 查询/谓词/池门控/ACE 白名单 | `scripts/survivor/survivor_data.gd`（UPGRADES 头注释、`upgrade_scope` `upgrade_classes` `milestone_plus_of` `upgrade_applies_to_machine` `is_upgrade_available_for(squad_classes)` `ACE_FIELD_STATS`） |
| 品类身份映射（机种类→轴） | `scripts/survivor/evolution_system.gd`（`CLASS_IDENTITY_BY_CATEGORY` `class_identity_of_profile`） |
| 候选 / 归属 / 重放纯投影 | `scripts/survivor/survivor_skill_catalog.gd`（`normal_candidates` `candidates_by_axis` `effective_stacks_for_machine` `replay_layers_for_machine` `owned_replay_layers`） |
| 归属执行 / 生效子集 meta / 王牌迁移 / 入队补挂 | `scripts/survivor/survivor_mode.gd`（`_distribute_upgrade` `_refresh_squad_effective_stacks` `_migrate_ace_field_upgrades` `_apply_build_to_new_member`，chokepoint `_set_player_aircraft`） |
| +1 轴进度双计数（cap=2） | `scripts/survivor/survivor_player.gd`（`milestone_bonus` `add_milestone_bonus` `get_milestone_progress`）＋发放点 `survivor_mode._grant_milestone_plus` |
| 定向应用 / 静态效果 / 王牌剥离 | `scripts/survivor/survivor_player.gd`（`apply_upgrade_to` `strip_upgrade_from`）→ `scripts/survivor/survivor_skill_effects.gd`（`apply`）；队级自动状态由 `survivor_skill_runtime.gd` 同步 |
| 计数缩放四效 | `scripts/survivor/survivor_data.gd`（`recompute_axis_count_skills` `count_owned_by_axis`；极速计数已并入 `speed_up`）＋ `scripts/aircraft.gd` 四字段＋消费点（`get_radar_range` / CD 赋值点 / physics accessor） |
| 僚机阵亡 / 弹尽 / 升级回复 / 奖励升级 | `scripts/survivor/survivor_mode.gd`（`_tick_squad_watch` `_on_squad_member_down` `_queue_bonus_upgrade` `_try_present_bonus_upgrade`）＋ `scripts/survivor/skill_hooks.gd`（`try_gun_reserve_mag` `in_free_missile_window`） |
| AB 三技（检讨/强化加力/适应） | `scripts/survivor/afterburner_charge.gd`（`kill_charge_bonus` `duration_mult`）＋ `skill_hooks.gd`（`afterburner` 静态引用、dispatch_on_kill 适应段） |
| 轮盘联动（保卫阵地/阵地转移） | `scripts/rts/squad_command_controller.gd`（`_update_guard_zone_buff`）＋ `scripts/aircraft/aircraft_physics.gd`（`GUARD_ZONE_G_MULT` `EVAC_SHIFT_SPRINT_BONUS`）＋ `scripts/aircraft.gd`（`_apply_damage` 720 段） |
| 地勤优化 | `scripts/survivor/dock_point.gd`（hold 减半）＋ `survivor_mode._on_settlement_closed` |
| QAAM 归因链 | `scripts/missile_manager.gd`（`spawn_missile(is_secondary)`）＋ `scripts/missile.gd`（`is_secondary_weapon`）＋ kind `"qmaam"` |
| 新机制四件 | `scripts/aircraft/aircraft_weapons.gd`（机炮吊舱翼挂段）/ `scripts/equipment/railgun_equipment.gd`（`double_shot` followup）/ `scripts/missile.gd`（`second_stage` `_second_stage_g_mult`）/ `scripts/aircraft.gd`（`try_manual_maneuver` / `do_manual_dodge`）＋ R 键入口 `survivor_mode` |
| 量表加成格 / 卡面归属角标 | `scripts/survivor/axis_bars_panel.gd`（`show_state(…, milestone_bonus)`）/ `scripts/survivor/survivor_upgrade_ui.gd`（`_scope_badges`） |
| 生成器 / 现状全表 | `tools/dump_skill_table.py` → `docs/reference/skill-table.md`（当前 158 条） |
| 验收 bench | `scripts/tests/test_skills_720.gd`（`--bench=skills720`；`_test_today_full_build_loadout` 验证今日 13 张/19 层在非 A-10 同机满层共存、忠诚僚机实际生成及复合击杀/阵亡触发；另含超载轴/终端来源闭合与 R 手动/AI 自动/互斥/全队下发；R 槽的当前五向权威与专项证据见 `active-special-maneuvers`；随 `--bench=all` 回归门） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-28 | 20 | 工程等价重构：普通随机候选、三轴分组、单机有效层与重放计划收口到纯 Catalog；队级自动状态独立 Runtime；静态效果显式接收目标飞机，删除临时换操控机引用与无数据使用的 `evolves_to` 残链。数值/归属/触发行为不变。 |
| 2026-08-25 | 19 | 用户要求将今日全部技能改动装备测试：新增非 A-10 测试机 13 张/19 层同机满层共存验收，覆盖忠诚僚机实际生成、低空 QAAM 异常目标复合击杀，以及两张复仇卡并发触发；focused 350/350、全量 83 组 0 失败、lifecycle 80/80。 |
| 2026-08-25 | 18 | 用户定稿“地表狂奔 + 空中战车”：保留机密一层地表狂奔，同时提供低空机炮闪避 +50% 与低空击杀后 8 秒无敌；移除 A-10 限定并删除旧 `skill_lowest_alt_kill_invul`，正式表 159→158。 |
| 2026-08-25 | 17 | 用户定稿“激光散热 + 激光过载”：保留先进两层激光散热，每层同时提供散热效率 +40% 与过热阈值 +50%；删除旧 `laser_heat`，正式表 160→159。 |
| 2026-08-25 | 16 | 用户定稿“QAAM 强化 + QAAM 嗜血”：保留稳定两层 QAAM 强化，每层 +1 格斗弹、射程 +10%，第一层起格斗弹击杀触发 10 秒嗜血；继承嗜血词条门控并替换三个终端来源，删除旧 `qmaam_bloodlust`，正式表 161→160。 |
| 2026-08-24 | 15 | 用户定稿“座舱护甲 + 闪避机动”：保留先进两层座舱护甲，每层同时提供地面伤害 ×0.5 与机炮闪避 +20%；删除旧 `bullet_dodge`，正式表 162→161。 |
| 2026-08-24 | 14 | 用户定稿“虐弱 + 战场急救”：保留先进单层虐弱，普通击杀回复 5 HP，异常目标击杀合计回复 35 HP；删除旧 `kill_heal`，正式表 163→162。 |
| 2026-08-24 | 13 | 用户定稿五组合并：忠诚僚机额外改为单层 +2 并即时部署两机；激光射程并分束、机炮精度并瞄准、引擎强化并全速推进、近距捕获并副武器。删除四张独立卡，正式表 167→163。 |
| 2026-08-06 | 12 | 用户定稿“超载是骑士的导弹流”：7 条旧策士超载卡显式迁骑士，与原有刺客复仇/MiG-41 合计 9 条；删除云中超载/焰诱共振的同轴骑士+1，噬血共振保留斗士+1 跨轴桥；三个超载终端前置补齐共振反馈/刺客复仇/MiG-41，共覆盖 6 个真实来源。 |
| 2026-08-01 | 11 | R 升格为统一机动入口：当前操控机手动、AI 僚机自动，特殊机动不再要求先开加力。眼镜蛇/J-Turn/胆大妄为组成三向互斥组，任取其一后另两张不再出现；代码优先级只作旧档/debug 共存兜底。胆大妄为从 ace scope 改为全队下发：AI 僚机在近弹/后方机炮威胁下自动滚转投焰，数值与“禁普通自动 flare”代价不变。 |
| 2026-07-29 | 10 | F4 技能 Debug 面板从已腐烂的五类（生存/机动/导弹/副武器/电子战）改为读取 `axis_of_upgrade` 的正式三轴（斗士/骑士/策士）分组与 SSOT 配色；Debug `+` 获得技能时补齐正式选卡的对应轴 +1（仍受全局 8 点 cap），实时状态显示三轴计数。 |
| 2026-07-29 | 9 | **共振反馈前置修正**（720 批遗留"前置组合观察"结案）：`jam_self_overload` 的 `requires_skill` 从"超载入门技（云中超载/规避超载/焰诱共振）"改为**全部 JAM 来源技**（扰乱投弹 / 机炮撒焰 / 寒蝉效应 / 雷阵警讯 / 对锋干扰 / 全向干扰场 / SPECTRA）。原写法把因果写反了——本条自身就是 OVERLOAD 的**来源**，需要的是"能把 JAM 打出去"的手段；玩家只拿焰诱共振就会刷出这张卡，而全局无任何 JAM 手段 → 技能永不触发（实测复现）。同批补：SPECTRA（`sig_rafale`）打出的 5s JAM 此前漏调 `on_player_jam_landed`，现补上（否则它作为前置仍不生效）。bench：skills720 新增 §I 前置链自洽段（全表 requires_skill id 有效性 + 共振反馈正反例），110 断言。 |
| 2026-07-22 | 8 | T6 收尾：§5 验收逐项回填（工程侧全过；余 playtest 调数值——保守暂定值清单列于 §5 末条）；§7 实现锚点表回填（纯符号指针）；survivor-skills.md 挂"数值段被本批取代"横幅指向本 spec 与 skill-table；changelog `docs/changelogs/2026-07-22-skills-720-rework.md`（提交序列 bddc8bd→d21789c + 系统级变化 + 已知余项：evolved 战区注册表沿用空表待映射批 / 共振反馈前置组合观察 / 阵亡 watcher 同周期单发）。 |
| 2026-07-22 | 7 | T5 新机制批落地（+3 条 → 104 条；§2.2 的 27 行全部到位）：①机炮吊舱 rework——两道翼挂（±14px 横向偏移）朝前齐射替代旧"机头+左右15°"三道扇形，弹耗 3→2/次（已拿档案表现变化按开工确认接受）；②电磁炮双发——RailgunEquipment.double_shot，首发后 0.22s 沿同一承诺弹道补射（不重蓄力/不再滚 miss，锁定线所见即所得承诺保持）；③导弹二段推进——Missile.second_stage：一段燃尽后温和续推（0.4×加速度，cap ×1.2）+ 转弯 G 随飞行时间渐强（+8%/s cap +50%）→"距离越远越准"；④胆大妄为（王牌）——manual_dodge_active 禁自动 flare + flare+6，R 键手动闪避=规避滚转动画 + 0.25s no_refresh 严格 i-frame + 有 flare 同时投放（is_flare_jammed 契约照走），CD 2s；ACE_FIELD_STATS 登记 + strip 收回 flare。skills720 bench 扩到 66 断言（i-frame/CD/往返/渐强曲线/双发装备位）。 |
| 2026-07-22 | 6 | T4 计数缩放批落地（+4 条 → 101 条）：recompute_axis_count_skills 挂 recompute_category_bonuses 尾部（"每次拿技能都重算"同一重算点；stacks 传生效子集 → 王牌两条天然只算操控机）。历战者=斗士轴技能数 ×+5HP cap100（差量幂等记账，换型重放序言清零后整额补回）；全速推进=骑士轴 ×+5% 顶速 cap40%（effective_max_speed_kmh accessor 注入）；电子战专家=策士轴 ×+100m 雷达 cap1km（get_radar_range 消费）；武器大师=装备武器数 ×−5% 全武器 CD cap30%（gun/missile/齐射/rocket/QAAM 五处 CD 赋值点统一乘，起手 gun+msl=−10% 与表一致）。未定量按 +5%/+100m 落，T6 playtest 调。skills720 bench 扩到 54 断言。 |
| 2026-07-22 | 5 | T3 钩子批落地（+14 条 → 97 条）：①僚机阵亡事件=survivor_mode 0.5s watcher（alive→destroyed 沿；复仇之战 嗜血+无敌15s / 刺客复仇 超载+隐身15s / 黑匣子回收 奖励升级，团灭同周期只触发一次）；②机炮弹尽事件=进装填转换点钩子（备用弹仓 30%/50% 概率回满跳装填；副武器=装填期发射导弹免耗，主/副/齐射三路扣弹口统一过 in_free_missile_window）；③升级回复（leveled_up 全队+10HP）；④轮盘联动：保卫阵地（防守圈内 buff 标志——减伤30% walk _apply_damage、回转+15% 走 _g_buff_mult accessor）+ 阵地转移（撤离冲刺 +15% 速度走 accessor、受伤减半）；⑤地勤优化（停靠判定减半 + 起飞后奖励升级）；⑥AB 三技=队级账本同步（检讨 kill_charge_bonus +3s/层、强化加力窗口 6→9→12s、适应=dispatch_on_kill 静态引用回能/回血）；⑦QAAM 嗜血=导弹归因链新增 is_secondary_weapon → kind"qmaam"；⑧骑士心脏·历练（对头击杀 XP ×1.5，spawner）；⑨群猎注视稀有度按 §2.2 修正（次世代→实验）。奖励升级=复用三选一卡片流（选卡得点语义一致），暂停/结算中顺延。数值未定项按保守值：历练 ×1.5、适应回能 +3s、保卫阵地 30%/15%、阵地转移 15%/50%（T6 playtest 调）。skills720 bench 扩到 45 断言。 |
| 2026-07-21 | 4 | T2 纯数据批落地（83 条）：①§2.3 数值/归属 delta 全表（26 项）+ hooks 常量 6 处（嗜血 8→9s / 寒颤号令 3km→2km / 寒蝉 2km / 弹后潜匿 5→4s / 火力护盾窗 0.5s / 血誓不竭去满血前置）；②§2.1 "+1 轴"14 条落库（骑8/斗4/策2——§1.1 计 13 为笔误，以 §2.1 表为准）；③v5 品类基线一并落库（未被 720 点名的项按 v5 归类）；④移除 railgun_damage（表+apply 分支）；⑤新增 5 条零代码技能 + apply 分支（漂浮雷额外/QAAM 强化/忠诚僚机额外·武装/座舱护甲字段版——地面减伤消费点 T3 接 take_damage）；⑥xp_mult 倍率迁 SurvivorPlayer 层（切控不丢）；⑦ACE_FIELD_STATS 6 项 + strip 逆操作（蜂群/凝视/惊鸿/对锋/后半球/云超载）；⑧数据链去 F-14 专属+squad_once+雷达+20%；集火枷锁改名群猎注视；⑨i18n 29 改 + 10 新 ×三语；生成器 v6 化重跑。⚠ 未定数值按保守值落（QAAM 射程+10%/忠诚僚机+30%·20%/子弹寿命+20%），T6 playtest 调；稀有度"全表重标"以 §2.3 已列明细为准（720 原始表未入库）；evolved 技能的战区注册表（ZoneRewardRegistry）沿用现状空表待战区映射批。 |
| 2026-07-21 | 3 | T1 归属底座落地：①四字段（scope/classes/milestone_plus + ACE_FIELD_STATS 白名单）与纯谓词 upgrade_applies_to_machine；②品类身份=进化节点机种类映射（EvolutionSystem.class_identity_of_profile，9 机种类全覆盖）；③归属分流 _distribute_upgrade 接管全部获得点（选卡/结算/战区奖励/boss debug/bench/F4 面板/换型重放），僚机 meta 记"生效子集"而非共享整本账；④milestone_bonus 双计数（cap=2）+ 量表加成格（半透明+亮边）+ 战术地图明细同判档 + 卡面归属角标（i18n 5 键三语）；⑤王牌切控迁移挂 _set_player_aircraft chokepoint（触发型走 meta 重建、字段型走 strip 白名单）；⑥进化顺序修正：僚机先 evolve 再全队重放（否则重放被 params 重置抹掉）；⑦数据链/集火锁 SLOW 改队级账本判定（T0 缺口①）+ 新僚机入队补挂 _apply_build_to_new_member（缺口②）。bench 新增 `skills720` 31 断言。 |
| 2026-07-21 | 2 | 开工：三项确认按推荐值定案（+1 轴进度 cap=2；王牌=仅当前操控机；机炮吊舱两道翼挂、旧档表现变化接受）。§4 排查双项闭环——①数据链结论：共享真生效、玩家可对僚机锁目标发射（价值=免锁定累积），另记两个 squad_once 缺口（切控失效/晚入队缺加成）留 T1 根治；②寒蝉效应 JAM 误伤实锤修复（team_filter -1→TEAM_HOSTILE），同病的机炮落雷 JAM 一并修。§6 T0 勾选。 |
| 2026-07-20 | 1 | 初稿：结构化用户 720 表——①"+1 轴进度"系统设计评估（合理；预留档通道；cap 2 护栏待二选一）；②归属词汇 v6（王牌层为 AoE 控场强技收敛回归；A10 限定=exclusive_to 复用；需要词条=requires_skill 复用；队级单实例 1→8 条）；③新增 27 条（含 id 拟名与挂点）/ 改动 ~35 条 delta / 移除 railgun_damage；④实现对照四档（纯数据/复用钩子/追加功能/全新机制）——加力模式充能钩子(07-20 现成)、combat-feed 击杀归因、轮盘 guard/sprint 状态、recompute 重算点、AB 滚转偏飞契约全复用；⑤排查双项（数据链生效+僚机锁可射、寒蝉友军 JAM bug）；⑥任务拆分 T0~T6。 |
