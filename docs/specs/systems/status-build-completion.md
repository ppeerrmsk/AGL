---
id: status-build-completion
kind: balance
status: done
schema_version: 1
spec_version: 3
owner: 用户
depends_on: [classified-card-pity, skills-720-rework, afterburner-mode, doctrine-unlocks, bloodlust]
reconstruction_complete: true
---

# 状态词条构筑聚焦、终端保底与六项扩展技能

> 玩家选入超载、嗜血、恐惧或干扰词条后，后续卡池会明显顺着该构筑生长，并在最多三次
> 合格选卡事件内提供一个可用终端；本批同时补入六项状态技能和嗜血基础效果调整。

## 1. 设计意图（Why）

- **体验目标**：保留“斗士／骑士／策士各出一张”的横向探索，同时降低已选词条构筑被无关卡
  稀释的概率；玩家应能把一次入口选择发展成有收束点的流派，而不是只堆零散状态来源。
- **身份目标**：超载完整归入骑士的导弹爆发／追击轴；嗜血继续承担斗士的机炮与持续交战轴；
  恐惧、干扰继续由策士控制轴收束。
- **Litmus 自检**：聚焦只发生在低频选卡事件；终端是“保证出现”而非自动授予；新效果均产生可见的
  状态条、弹药、射界、热诱弹或导弹行为变化。限时玩家增益保持 8 秒级真实交战窗口。
- **反模式规避**：不使用会替玩家自动选卡的确定性脚本；不让 StormⅠ/Ⅱ组成无限超载；不引入
  每帧全场扫描；回血数值不在本批上调。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 构筑元数据字段

| 字段 | 类型 | 语义 |
|---|---|---|
| `build_tags` | `Array[String]`，可选 | 构筑归属；缺省时取 `keywords` 与受支持词条的交集 |
| `build_role` | `source/bridge/support/terminal`，可选 | 供审计与调试显示；不替代玩法前置 |
| `terminal_for` | `Array[String]`，可选 | 该卡能为哪些词条偿还“终端债务” |

受硬终端保底支持的词条为 `overload / bloodlust / fear / jam`。`slow` 仍是控制副产物，
`stealth` 的通用终端仍刻意留空，`invincible` 状态本身即终端，三者只保留原软关键词引导。

### 2.2 软聚焦公式

令 `A(t)` 为本局已拥有、包含词条 `t` 的技能 stack 总数。主词条 `p` 按以下顺序选择：

1. 只考虑 `A(t)>0` 的受支持词条；
2. `A(t)` 高者优先；
3. 相同则按固定顺序 `overload → bloodlust → fear → jam` 裁决，保证可复现。

轴内每张候选卡的最终权重：

```
W = rarity_base × classified_pity × legacy_keyword_steering × status_focus × terminal_debt

status_focus(相关卡) = 1 + 0.75 × sqrt(min(A(p), 4))
status_focus(无关卡) = max(0.65, 1 - 0.15 × A(p))
```

对应倍率：

| 主词条 stack | 相关卡 | 无关卡 |
|---:|---:|---:|
| 1 | ×1.75 | ×0.85 |
| 2 | ×2.06 | ×0.70 |
| 3 | ×2.30 | ×0.65 |
| 4+ | ×2.50 | ×0.65 |

原有普通 keyword steering（每 stack +20%，封顶 +100%；5 级前折半）继续保留，避免非状态构筑退化。
多关键词卡只吃一次 `status_focus`，不按匹配词条数量重复相乘。

### 2.3 终端债务与保底

一个词条满足以下全部条件时进入债务候选：

- 已拥有该词条至少一个 stack；
- 尚未拥有任何 `terminal_for` 包含该词条的卡；
- 本次过滤后的正式卡池中至少存在一个可选终端。

每次选卡事件最多服务一个词条：先比较连续 miss 数，再比较 `A(t)`，最后用固定词条顺序裁决。

| 从入口选择后的合格事件 | 终端候选权重 | 若本轮仍未出现 |
|---:|---:|---|
| 第 1 次 | ×2 | miss 记为 1 |
| 第 2 次 | ×4 | miss 记为 2 |
| 第 3 次 | 对应轴卡位强制从合格终端中抽取 | 出现即清零 |

- “合格事件”指过滤完硬件、机型、品类、学说、互斥、前置和 max stack 后，仍有该词条终端可选。
- 因门控导致零终端时不累计 miss，自动审计报告数据缺口。
- 保底只替换终端所在的既有轴卡位，另外两轴照常提供探索选择。
- 终端只是出现在卡面，不自动授予。玩家跳过也清零，之后可重新累计。
- 自然三轴卡与奖励三轴卡都参与；机体签名第四槽不参与，也不被覆盖。
- 强制出的 `CLASSIFIED` 终端正常计作金卡，会清空原金卡 pity。

### 2.4 六项新增技能

| id / 名称 | 轴 / 稀有度 / scope | 前置 | 角色 | 完整效果 |
|---|---|---|---|---|
| `storm_i` / 风暴Ⅰ StormⅠ | 骑士 / STABLE / 通用全队 | 无 | OVERLOAD 来源 | 每次加力启动后累计**实际消耗** 3.0 点加力能量；达到阈值时给本次加力窗口成员 OVERLOAD 8.0s；每次启动最多触发一次 |
| `storm_ii` / 风暴Ⅱ StormⅡ | 骑士 / ADVANCED / 通用全队 | 任一 OVERLOAD 来源 | OVERLOAD 终端 | 当前操控机处于 OVERLOAD 时：加力模式激活期间耗能率为 0；未激活时被动充能率 ×4.0 |
| `ratatat` / 哒哒哒 Ratatat | 斗士 / ADVANCED / 通用全队 | 任一 BLOODLUST 来源 | BLOODLUST 终端 | BLOODLUST 期间机炮有效射程 +500m、实际射击间隔 ×0.70、有效射击锥半角 +8°；AI 规划、火控、渲染射界共用有效值 |
| `mental_confusion` / 精神错乱 | 策士 / ADVANCED / 通用全队 | 任一 FEAR 来源 | FEAR 终端 | 只在玩家来源 FEAR 的上升沿判定一次：普通 50%、ACE 25%、BOSS 10%；成功时在可用动作中随机浪费一次热诱弹或一枚导弹，错误导弹立即失去制导且不能命中或触发热诱弹 |
| `hush` / 噤声 Hush | 策士 / ADVANCED / `squad_once` | 任一 JAM 来源 | JAM 终端 | JAM 中敌机不能释放热诱弹；以 JAM 中敌机为来源的现存及新发射敌对导弹立即失去制导、不能命中、不会计入威胁或触发热诱弹 |
| `stasis` / 停滞 Stasis | 斗士 / EXPERIMENTAL / `ace` | 无 | SLOW 来源 | 当前操控机实际承受 `kind=missile` 且伤害大于 0 的命中后，对 2km 内敌方施加 SLOW 4.0s；被闪避、无敌拦截、零伤害和 AOE 不触发 |

### 2.5 既有词条调整

| 项 | 定稿 |
|---|---|
| BLOODLUST 基础状态 | 保留击杀回复 20 HP；**追加普通机炮与机炮 CIWS 开火不消耗弹药**。弹药已为 0 时不凭空恢复，也不跳过既有装填状态 |
| `cloud_overload` | CLASSIFIED → ADVANCED |
| `skill_flare_overload` | ADVANCED → CLASSIFIED |
| `jam_self_overload` | EXPERIMENTAL → STABLE |
| `fear_squad_spread` | EXPERIMENTAL → ADVANCED；FEAR 5s → 6s |
| `skill_gun_kill_fear` | EXPERIMENTAL → STABLE；半径 2.4km → 2km；FEAR 5s → 6s |
| `skill_head_on_aoe_fear` | CLASSIFIED → STABLE |
| `flee` | 显示名改为“逃吧 Run”，id 与 40% 撤离规则不变 |
| `skill_kill_status_heal` | 前置改为任一 FEAR 或 JAM 来源；击杀任意异常状态敌人回 30 HP 的效果不变 |

### 2.6 终端登记与来源闭合

| 词条 | 终端 |
|---|---|
| OVERLOAD | `overload_duration_4x`、`overload_extended_ammo`、`overload_to_bloodlust`、`storm_ii` |
| BLOODLUST | `bloodlust_armor_mobility`、`full_hp_kill_perma_hp`、`ratatat` |
| FEAR | `fear_chills`、`flee`、`skill_kill_status_heal`、`mental_confusion` |
| JAM | `jam_self_overload`、`invasion_algorithm`、`skill_kill_status_heal`、`hush` |

嗜血终端前置必须承认合并后的 `qmaam_boost` 与 `squad_revenge`；恐惧终端必须承认 `fear_on_lock`
与 `sig_su27`；签名来源可以解锁普通终端，但签名卡自身仍不进入普通三轴池。

## 3. 行为与公式（How）

### 3.1 选卡事件

```
构建三轴正式候选池
→ 计算词条 affinity 与主词条
→ 选一个需要服务且本轮有合法终端的债务词条
→ 三轴分别按最终权重抽卡
→ 若债务 miss >= 2，则对应轴改抽合法终端
→ 结算本轮是否出现服务词条终端，更新 miss
→ 结算原 CLASSIFIED pity
```

### 3.2 Storm 防循环

```
加力启动：storm_i_spent = 0，storm_i_triggered = false
激活且非 StormⅡ 免费窗口：
  consumed = effective_drain × delta
  charge -= consumed
  storm_i_spent += consumed
  若 spent >= 3 且未触发：全窗口成员 OVERLOAD 8s；本次启动锁定已触发

StormⅡ 免费窗口：charge 不变，storm_i_spent 也不增加
```

因此 StormⅠ触发后，StormⅡ可以保存剩余能量，但免费时间不能继续推进 StormⅠ，也不能靠自身刷新超载。

### 3.3 精神错乱与噤声优先级

- 同一次 FEAR 上升沿最多浪费一个动作；刷新已有 FEAR 不重判。
- 若目标同时 JAM 且玩家持有 Hush，错误热诱弹动作不可用；精神错乱改选错误导弹，若也无导弹则本次成功判定无动作。
- 错误导弹复用 `is_flare_jammed` 的既有丢制导契约，不新增导弹状态机。
- Hush 对导弹的处理只在 JAM 落地事件和导弹生成事件发生，不做每帧全导弹扫描。

## 4. 结构与组成（Structure）

- 选卡纯函数、构筑元数据与终端查询：`SurvivorData`。
- 本局终端 miss 账本、三轴卡组装与金卡 pity 联动：`survivor_mode`。
- Storm 充能、消耗累计和窗口成员状态：`AfterburnerCharge`；当前 ACE 的 StormⅡ条件由生存模式注入。
- BLOODLUST 弹药与 Ratatat 有效机炮参数：`Aircraft` / `AircraftWeapons`，AI 与表现层读同一有效 accessor。
- FEAR/JAM/SLOW 事件：`SkillHooks`；热诱弹禁用：`AircraftFlares`；导弹丢制导：`MissileManager` 既有契约。
- F4 强制授予仍读取同一 `UPGRADES`，只绕获得门控，不伪造状态、受击或加力触发条件。

## 5. 验收标准（Acceptance / Litmus）

- [x] 100000 次模拟中，已选入口且存在合法终端时，第三次合格选卡事件的累计终端出示率为 100%。
- [x] 无构筑 stack 时抽卡权重与旧版一致；非状态 keyword steering 保持原公式。
- [x] 选 1 个主词条后，相关候选倍率 ×1.75、无关候选 ×0.85；另外两轴仍能正常出卡。
- [x] 硬件、学说、机型、品类、互斥、前置、max stack 继续严格生效；无合法终端不累计债务。
- [x] StormⅠ按实际耗能触发一次；StormⅡ免费窗口不推进 StormⅠ，不能形成自刷新无限超载。
- [x] BLOODLUST 期间普通机炮与 CIWS 弹量不下降；状态外恢复原消耗；0 弹不凭空开火。
- [x] Ratatat 的 +500m、间隔 ×0.70、半角 +8°同时进入玩家火控、AI 规划和射界表现。
- [x] 精神错乱只在 FEAR 上升沿判一次；概率分层与一次动作上限正确。
- [x] Hush 阻止 JAM 敌机投焰；现存与新发导弹均失去制导且不命中、不触发 flare。
- [x] Stasis 只在实际 missile 伤害后触发 2km/4s SLOW。
- [x] F4 技能面板可直接授予六项新技能；状态脚注与真实语义一致。
- [x] i18n 三语、自动技能表、script/code/skill implementation 索引同步。
- [x] 文档校验、`skills720`、`skill_audit`、`status_notes`、`attr_gates` 通过。
- [x] 性能：新增全场扫描只在低频 JAM/FEAR/受击事件发生；`stress_40` 10s 样本 146 FPS。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与抽卡
- [x] 为四个可闭合词条登记终端元数据，补齐既有来源前置。
- [x] 实现状态软聚焦、单债务服务、×2/×4/第三次强制与金卡 pity 联动。
- [x] 加入六项 `UPGRADES` 与既有稀有度/数值调整。

### 阶段 2 — 运行时效果
- [x] 实现 StormⅠ/Ⅱ及防循环累计。
- [x] 实现 BLOODLUST 免费机炮弹药与 Ratatat 有效参数。
- [x] 实现精神错乱、Hush、Stasis 的事件钩子。

### 阶段 3 — 可达性与验证
- [x] 补齐三语、F4/自动审计、技能表与索引。
- [x] 跑数学模拟、定向 bench、文档校验和压力回归。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 技能数据、构筑权重与终端查询 | `scripts/survivor/survivor_data.gd` |
| 本局终端债务与三轴出牌 | `scripts/survivor/survivor_mode.gd` |
| 加力资源与 Storm | `scripts/survivor/afterburner_charge.gd` |
| 状态事件技能 | `scripts/survivor/skill_hooks.gd` |
| 机炮有效参数与弹药 | `scripts/aircraft.gd`、`scripts/aircraft/aircraft_weapons.gd` |
| 热诱弹与导弹失导 | `scripts/aircraft/aircraft_flares.gd`、`scripts/missile_manager.gd` |
| 自动验证 | `scripts/tests/test_skills_720.gd`、`scripts/tests/test_skill_audit.gd`、`scripts/tests/test_status_notes.gd` |
| 三语文本 | `i18n/skills.csv` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-25 | 3 | QAAM 嗜血并入 QAAM 强化后，三个 BLOODLUST 终端的来源前置统一改认 `qmaam_boost`。 |
| 2026-08-06 | 2 | 实装完成：158 条技能、六项运行时、BLOODLUST 基础免弹、四词条软聚焦与第三事件终端保证；100000 次强制 100%，定向 bench 全绿，压力样本 146 FPS。卡池降档使旧金卡均值下滑后，将 pity miss 斜率 2.0→3.5 保持原 10 分钟目标。 |
| 2026-08-06 | 1 | 用户确认开始推进：冻结软聚焦、三事件终端保底、六项技能、既有稀有度/闭合调整与 BLOODLUST 基础免费机炮弹药。 |
