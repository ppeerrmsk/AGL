# 生存模式技能系统 —— 设计哲学与需求（设计层文档）

> **三层分工（2026-07-24 重构，查东西先认层）：**
> - **数值/归属现状** → [skill-table.md](../reference/skill-table.md)（自动生成；当前 158 条，`python tools/dump_skill_table.py` 重刷）
> - **配置字段 / 实装模式 / 效果代码在哪** → [skill-implementation-index.md](../reference/skill-implementation-index.md)（八模式 + 全 stat 消费点速查，**AI 查代码首选入口**）
> - **数值为什么这样 / 权威定稿** → specs：[skills-720-rework](../specs/systems/skills-720-rework.md) · [aircraft-signature-skills](../specs/systems/aircraft-signature-skills.md) · [evolution-attribute-gates](../specs/systems/evolution-attribute-gates.md) · [afterburner-mode](../specs/systems/afterburner-mode.md)
>
> 本文只管**设计层**：哲学 / 系统概念 / 触发基础设施能力清单 / 四大主题系列的需求 backlog。
> 本文不再维护逐技能数值表（旧 41 条图鉴表已删，被 skill-table 取代）。

## 索引

- [设计哲学](#设计哲学)
- [系统概念现状](#系统概念现状)（三轴卡片 / 归属词汇 / 签名技能 / 加力模式 / 获取渠道）
- [触发基础设施能力清单](#触发基础设施能力清单)（设计新技能时"现成能挂什么"）
- [四大主题系列（需求 backlog）](#四大主题系列需求-backlog)：骑士精神 / 恐惧心理战 / EMP / 环境天气
- [扩展约束](#扩展约束)

---

## 设计哲学

**必过 [DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md) Litmus**（信息察觉 / 一击毙命 / 全自动开火 / 60FPS）。技能层追加：

1. **几何门槛优先于状态机**：新技能尽量用"当帧几何条件"触发（heading dot、距离、高度、速度），
   不引入额外计时器或外部状态。玩家从视觉就能预判会不会触发，没有"我做对了但系统没认"的挫败。
2. **两种增益曲线并存**：线性堆叠（`max_stacks > 1`，常规池主体）与一次性强技（×1 开关，CLASSIFIED/战区奖励）。
   ⚠ 进化链（`evolves_to`）已废弃，新技能不再做"满级自动进化"。
3. **单杠杆、效果即反馈**（feedback 铁律）：一条技能一个杠杆；效果直接可见（爆炸/状态图标/数值跳动），
   不加 HUD 中介层。档位·滞回·惩罚项等二阶机制默认不做，playtest 证明必要再补。
4. **归属明确**：每条技能想清楚"谁生效"——全队 / 品类限定 / 王牌（仅操控机）/ 队级单实例 / 机型签名。
   词汇表见 [skills-720-rework §1.2](../specs/systems/skills-720-rework.md)。
5. **数值可感知档**：最小可感知加成 ±20% 起（拒绝 +5% 暗数值）；伤害类 buff 只作用于机炮（多发武器）
   与地面单位（HP 池）——导弹一发死，"+导弹伤害"无意义。

---

## 系统概念现状

（机制细节与代码锚点全部在 [实装索引](../reference/skill-implementation-index.md)，这里只写"是什么"。）

工程侧保持四层单向数据流：`UPGRADES` 是唯一技能定义；`SurvivorSkillCatalog` 负责候选、归属与
重放投影；`SurvivorSkillEffects` 显式执行获得时静态效果；`SurvivorSkillRuntime` / `SkillHooks`
分别承接队级状态与低频自动触发。场景控制器只编排流程，不得复制候选过滤或隐式替换当前飞机引用。

### 三轴卡片制（2026-07-19 起，取代旧"每级三选一"）

- **每升 3 级**触发基础卡片三选一：斗士 / 骑士 / 策士**各一张**（家系池内按稀有度+流派引导抽）。
- 生涯商店购买“机体战术适配”后，自然升级有 **15%** 概率追加一张当前机体身份轴的普通第四卡；
  多轴机先等概率选轴，第四卡完整继承普通门控、稀有度、构筑引导与 pity，详见
  [airframe-affinity-fourth-card](../specs/systems/airframe-affinity-fourth-card.md)。
- 本轮普通卡连续没出 4 级金卡时，下一轮 `CLASSIFIED` 候选权重按 `1+3.5×未出次数` 隐性递增；
  任一普通卡见金即清零。机场专属技能与奖励升级不参与，权威规则见
  [classified-card-pity](../specs/systems/classified-card-pity.md)。
- 选卡 = 技能入手 **且** 该轴 +1 技能点（进化门槛货币）；部分技能带 `milestone_plus`（额外 +1 里程碑进度）。
- 三轴点数、里程碑、已选技能全部**记玩家层，换机重放不丢**（roguelike 局内清零）。
- 里程碑（每轴 2/4/6/8 点档的纯属性奖励）**不是技能**，归 [evolution-attribute-gates](../specs/systems/evolution-attribute-gates.md)。
  归属与技能一致：**跟玩家不跟机体，且下发全队**（2026-07-28 起）——记账从"玩家级单账本"改成**逐机记账**，
  所以晚入队的僚机会补挂、换型（进化）全队重挂、换帅（1–9 切控 / 长机阵亡顶替）后新操控机也不再是白板。

### 归属词汇 v6（720 批）

通用全队 / 品类限定（classes）/ **王牌**（仅操控机，切控迁移）/ 队级单实例（squad_once）/
装备门控（requires）/ 需要词条（requires_skill）/ **机型签名**（exclusive_to）。

### 机型签名技能（722 批）

进化树 43 机**每机一条专属技**：驾驶该机型并完成生涯揭示/购买后，在机场停靠时必须二选一——保留当前机体并装备专属技能，或进化到所选后继机体。专属技能不进入等级三选一、奖励卡或战区奖励池；获得后永久跟玩家（换机不丢）。
权威源 [aircraft-signature-skills](../specs/systems/aircraft-signature-skills.md)。

- **获取隔离**：机场右栏用洋红框表示“保留当前机并装备专属技能”；普通升级面板不显示专属技能。
- **第四槽不等于专属槽**：机体战术适配追加的是该机体身份轴的普通技能，仍由普通池独立计算稀有度。
当前已接入生涯揭示与功勋购买，具体获取规则以
[aircraft-signature-progression](../specs/systems/aircraft-signature-progression.md) 为准；不再走“全开放普通池”。

### 加力模式（充能制）—— 玩家的核心战术按钮

> 权威定义在 [specs/systems/afterburner-mode.md](../specs/systems/afterburner-mode.md)（SSOT，含全部数值/公式/16 项冲突裁定）。本节是给技能作者的速览——凡写"加力模式 / 加力期间 / 加力充能"的技能都指这个模式。

E 键 / HUD 按钮触发的**小队级充能资源**（前身是语义模糊的"规避模式"，2026-07 资源化改造）。**充能制（电池模型）**：

- **能量池**：`charge` 一池连续能量，上限 `CHARGE_MAX = 6s`（满能量最多连烧 6 秒）。被动 `0.2/s` 回充（空→满 ≈30s），小队击杀 `+0.8s`。开局满格。
- **开关语义（`AfterburnerCharge.toggle`）**：**有能量（charge > 0）即可一键启动**，不必满格；激活中**再按 E 立即关闭**（剩余能量保留）；能量为 0 时按键无效。
- **耗能自动结束**：激活中按 `1.0/s` 实时耗能，耗尽（≤0）自动关闭。`duration_mult`（强化加力技能）减慢耗能，续航 6→9→12s。
- **激活期全队强 buff**（以 `Squad.members` 弱引用快照，每架成员通过 `is_afterburner_mode_active()` 查询）：
  - 机炮 **100% 闪避**（唯一绕全局 dodge cap 0.85 的通道）
  - 导弹 **90% 滚转甩偏**（走 flare-jam 偏飞契约，10% 极限命中保留"一击毙命"张力）
  - **禁攻击**（机炮/导弹/火箭静默；空射鱼雷 TORP、忠诚僚机 WMN 例外照旧投放；`commanded_target` 不清除，关闭即恢复开火；722 例外通道：MiG-31 超速截击可在激活期自动发射导弹）
  - **满速地板 = 有效顶速** + 加速度 ×3（点哪全速飞哪的"脱离-重整-再入"）
- **底层复用与硬边界**：内部仍走 `set_evasion_mode(true)` 获得 planner EVADE 与 `escort_cover_active` 护卫广播；但肉鸽加力技能、TORP/WMN、签名技能与 HUD **只认加力窗口 accessor**。AI 自保规避（`evasion_mode`）和物理发动机 AB（`is_afterburner`）都不能代判；普通 AI 规避仅保留旧弱 buff 及历史 flare/导弹装填修饰器。
- **无线电**：启动喊"全队加力，冲！"（`RADIO_AFTERBURNER_*`，玩家主动脱离语义），**不再喊躲导弹的"break"**——真·躲导弹（AI enter_evade）才走 break（见 [radio-chatter](../specs/systems/radio-chatter.md)）。

> 键于本模式的技能（全部随激活期存续）：超频加力 / 蓄势狂暴 / 弹仓过载 / 雾隐机动 / 加力供弹按每架窗口成员同拍生效；检讨 / 强化加力 / 适应 / 暴风雨 I/II 修改队级资源；Su-34 鸭嘴兽厨房 / MiG-31 超速截击也只认该窗口。**眼镜蛇与危机赫尔贝特已从加力触发链拆出**：当前操控机按 R 手动释放，AI 僚机受威胁自动释放。

**R 机动槽**：眼镜蛇 / 危机赫尔贝特（J-Turn）/ 胆大妄为 / 位移滚转 / 垂直越过五向互斥，
玩家只持有一种；均不要求先开加力。技能全队下发：当前操控机按 R，AI 僚机按各自威胁条件自动释放。
共享冷却、切控续播与不可命中规则以
[active-special-maneuvers](../specs/systems/active-special-maneuvers.md) 为权威。

### 获取渠道三条

| 渠道 | 标记 | 说明 |
|---|---|---|
| 常规轴卡池 | （默认） | 每 3 级三选一 |
| 战区奖励 | `evolved: true` | 不进随机池；战区通关按星级 roll（zone-reward-arsenal） |
| 机型签名 | `exclusive_to` | 驾驶该机型才刷出 |

**特殊武器不走技能系统**：火箭/电磁炮/激光/忠诚僚机/漂浮雷/QMAAM = 玩家外部装备，
战区获取、换机全继承、**不烤入任何机体**（2026-07-23 用户令，[inrun-weapon-inventory](../specs/systems/inrun-weapon-inventory.md)）。
针对这些武器的**强化技能**（railgun_charge 等）仍是技能，装备门控 `requires`。

### 经验曲线

```gdscript
static func xp_for_level(level: int) -> int:
    return int(15.0 * pow(level, 1.3))
```

指数 1.3（2026-07-28 等级通胀整治，[survivor-loop](../specs/systems/survivor-loop.md) §5）：
每级击杀数随等级爬升，平均局收 LV18~22，顶级机不保底。
乘区两层：`xp_mult`（队级，硬顶 ×1.4）× `sig_xp_mult`（F-16 签名，×1.25 独立乘区）。
局外功勋 = 局内总 XP 按 0.8/1.0 系数折算（MeritLedger）。

---

## 触发基础设施能力清单

设计新技能时，这些事件/查询**已经有钩子**，直接挂（代码锚点见实装索引 §3/§4）：

| 能力 | 说明 |
|---|---|
| 击杀归因 | 击杀者/武器类型（gun/missile/qmaam/rocket）/对头几何（双向 dot + 3km 距离门）/低空判定 |
| 受击钩子 | 受伤类型与来源（含地面来源过滤）、致死拦截点（保命/复活类共用判序底座） |
| flare 事件 | 释放 / 成功偏转（可拿到那发导弹与其发射者） |
| 特殊机动完成 | 眼镜蛇 / 破 S 相位收尾沿 |
| 停靠与起飞 | 着陆结算 / 结算关闭（=起飞）沿 |
| 僚机阵亡 | 0.5s watcher（复仇/黑匣子类共用） |
| 升级事件 | leveled_up 信号 |
| RTS 命令 | 攻击轮盘姿态（ASSAULT/STANDOFF）/ 双击冲锋 / 防守圈内状态 / 撤离冲刺状态 |
| 加力模式 | 队级能量池、激活期（`afterburner_window_active`）、击杀充能沿 |
| 状态系统 | FEAR/JAM/SLOW/STEALTH/INVINCIBLE/OVERLOAD/BLOODLUST 施加与上升沿；AOE 群体施加（AOEBroadcast） |
| 高度/云 | AltitudeTier 档位、进出云沿、爬降速率 |
| 锁定管线 | 我方锁敌速率乘区、敌方锁我乘区、被锁状态（is_locked/locked_by）、照射共享 |
| 敌 AI 心理 | pilot_personality 的 stress/SA（FEAR 的底层；对 simple_ai 杂兵无效、BOSS ×0.4 削减） |

---

## 四大主题系列（需求 backlog）

> 设计需求池：✅=已实装（含"以变体形态实装"）· ⏳=未实装想法。
> 状态随批次更新；实装后数值以 skill-table / spec 为准，这里只留设计意图。

### 骑士精神系列（Chivalry）

鼓励**反偷袭**的正面交锋：对头、近距、低空、高速。不惩罚保守玩法，只奖励勇敢。

| 状态 | 名称 | 设计 |
|---|---|---|
| ✅ | 对头猎手 | 对头击杀 → 永久 +5 max_hp（`skill_head_on_perma_hp`；对头几何判据=双向 dot>0.6 + ≤3km） |
| ✅ | 对头恐惧 | 对头击杀 → 大范围 FEAR（`skill_head_on_aoe_fear`） |
| ✅ | 骑士心脏·历练 | 对头击杀 XP ×1.5（`headon_xp`，720 批——即旧"正面对决 Joust Bonus"想法） |
| ✅ | 对头机炮闪避 | 与攻击者对头时机炮闪避 +60%（`head_on_gun_dodge`） |
| ✅ | 地表狂奔 | LOW/GROUND 档机炮闪避 +50%，且击杀后自身获得 8s 无敌（`low_alt_gun_dodge`；已合并“空中战车”并移除 A-10 限定） |
| ⏳ | 冲锋盾 | 低空+高速+机头对敌 → 前方 wedge 能量盾（吸收 50，缓充；护盾在 armor 外层）。实现思路：Aircraft 字段 + bullet/missile 命中前 wedge 几何判定 + renderer 光晕 |
| ⏳ | 直面 BVR（Stare Down） | 被锁定时机头朝锁定者 ±20° → 敌方锁定速率 ×0.5（锁定循环有现成乘区位） |
| ⏳ | 决斗者（Duelist） | 5s 内 1v1 → 伤害 +25%，第三方介入打破 |
| ⏳ | 近距加成（Knife Fight） | 机炮命中 <400px → 暴击 ×1.5 |
| ⏳ | 冲撞免疫（Last Stand） | HP<20% 对头击杀 → 回 20 HP（每局一次；可复用 722 致死拦截底座的判序思路） |

### 恐惧 / 心理战系列（Fear/PsyWar）

利用敌 AI `stress`/`SA` 压迫判断。**约束**：对 simple_ai 杂兵（Tu-160/AH-64/CH-47）无效；BOSS ×0.4。

| 状态 | 名称 | 设计 |
|---|---|---|
| ✅ | 机炮震慑 | 机炮击杀 → AOE FEAR（`skill_gun_kill_fear`，720 批改王牌层） |
| ✅ | 凝视压迫 | 锁定累积 N 秒 → 目标 FEAR（`fear_on_lock`，王牌） |
| ✅ | 恐惧扩散/寒颤/寒蝉 | 击杀扩散同队 FEAR（`fear_squad_spread`）；FEAR 附带 SLOW（`fear_chills`）；被弹 AOE JAM（寒蝉） |
| ✅（变体） | 对头威慑 → 对锋干扰 | 原想法"瞪谁谁慌"落地为对头累积 → JAM（`head_on_jam`，王牌）——形态从 stress 改 JAM，压迫语义保留 |
| ✅（变体） | 死神光环 → 减速/干扰光环 | 原"辐射 stress 光环"落地为后半球 SLOW 光环（`rear_aura_slow`）与全向 JAM 光环（`jam_aura`），累积式 0.5s tick |
| ⏳ | 斩首吓阻 | 击杀敌方**长机** → 全队 stress=1.0 + SA 减半 5s（长机判定 squad_index==0；奖励"先掐头"） |
| ⏳ | 战吼 | 加力激活瞬间脉冲：1200px 内敌机 stress=0.6。冷却 15s（加力满能量续航仅 6s、充满约需 30s，脉冲天然不会每次开加力都触发）。设计意图：给加力模式额外一层主动控场价值 |

### EMP / 电子瘫痪系列

> **现状裁定（2026-07-24）**：原系列的核心诉求"短时让敌方雷达/锁定失效"已由 **JAM 状态**全面覆盖
> （JAM=清空照射+禁止累积，入口：jam_aura / 寒蝉 / SPECTRA / 对锋干扰 / flare AOE JAM）。
> 剩余想法的增量是"**连武器也瘫痪** + 弹种/区域形态"——做之前先问：JAM 不够吗？
> （全自动开火哲学下"主动按键释放 EMP"与原则 10 冲突，若做需改为条件自动触发。）

| 状态 | 名称 | 设计 |
|---|---|---|
| ✅（语义覆盖） | 雷达瘫痪类 | 全部 JAM 家族技能 |
| ⏳ | EMP 弹头 | 专用弹种：命中不伤害，AOE 瘫痪（雷达+**武器**）4s。需 MissileParams 加 is_emp 分支 |
| ⏳ | EMP 区域 | 击杀位置留 8s 瘫痪云（复用 missile_manager `_aoe_zones` 加 is_emp 标记） |
| ⏳ | 链式瘫痪 | EMP 中的敌机被击杀 → 半径 600px 再放 1.5s 短 EMP |

统一约束（若推进）：BOSS 时长 ×0.4；Adds 免疫；不瘫友军；视觉=蓝白电弧+雷达锥消失。

### 环境 / 天气系列（设计记录，未实施）

用 [WeatherSystem](../../scripts/weather_system.gd) 云层做战术资源。已有环境互动：云中锁定衰减
（HIGH×0.5 / 雾隐 ×0.1）、导弹入云丢制导、AOE 云中衰减——全部走 `sample_density/is_in_cloud` 查询接口，
**任何"云"系扩展只要密度走这套接口，战斗逻辑零改动**。性能有余量（云系统不在预算 top20）。

核心基建想法：**局部云团 `spawn_puff(pos, radius, lifetime, …)`**（全局 noise 与 puff 列表 max 合并），
一个 API 吃下全部场景：被命中烟幕脱身（挨打→身后出云→导弹冲进去丢制导→奖励"回头反咬"）、
战场积烟、烟雾弹、EMP 云、BOSS 入场云散（negative puff）。
全局调控 API 草案（coverage/wind/tint 渐变）与实现细节（CLOUD_TINT 需从烘焙挪到绘制层，否则动态变色
每次 rebake ~200ms）见 git 历史版本（本文 2026-07-24 精简前的完整设计记录），推进时再展开。

推进前先决定：最小切片（只做"被命中生成云"）还是完整 puff 基建；全局调控与局部 puff 谁优先。

---

## 扩展约束

1. **加新技能走** [实装索引 §5 决策树](../reference/skill-implementation-index.md) 选模式 +
   [playbook §4](../reference/playbook.md) 检查单。⚠ 不是所有技能都要加 apply 分支——
   `skill_flag` 型（事件触发类）apply 无操作，效果全在钩子/消费点。
2. **战区奖励技能**：`evolved: true` + zone_data 奖励权重；机型签名：`exclusive_to`（**不要**在
   apply 里写 `if aircraft_id == ...`）。
3. **进化链已废**：`evolves_to` 不要再用。
4. **性能**：光环/心理战类周期 tick 默认 0.5s；禁每帧扫场景（复用 `CombatUnit.all_units`）；
   详见 [performance-guidelines](../reference/performance-guidelines.md)。
5. **i18n 强制**：`UPGRADE_<ID>_NAME/_DESC` 三语；改数值必同步 desc（feedback 铁律）。
6. **模式隔离**：升级逻辑全挂生存模式入口，沙盒不感知任何 stat。
7. **铁律清单**（重放不查门控 / ACE strip / static 清零 / 深拷契约 / 差量幂等）见
   [实装索引 §6](../reference/skill-implementation-index.md)——改技能系统底座前必读。
