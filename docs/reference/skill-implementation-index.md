# 技能实装索引 —— 配置字段 × 实装模式 × 全 stat 消费点速查

> **这份文档的目的：查任何技能"怎么配置的 / 效果代码在哪"，都不需要通读
> `survivor_data.gd`(2300 行) / `survivor_player.gd`(900 行) / `skill_hooks.gd`(700 行)。**
> 按 §0 路由 → §3 认出模式 → §4 查到消费点，三步定位。
>
> 维护约定：本文写**文件 + 函数/字段名**，刻意不写行号（行号腐烂快、符号名稳定）。
> 加新技能时在 §4 表加一行（同 stat 复用现有行）；新模式（罕见）才动 §3。
> 数值/稀有度/归属的**现状**永远看自动生成的 [skill-table.md](skill-table.md)，本文不重复数值。

---

## 0. 按问题路由（先看这张表）

| 你想知道的 | 去哪 |
|---|---|
| 某技能的数值 / 层数 / 稀有度 / 归属 / 轴 / +1 进度 | [skill-table.md](skill-table.md)（自动生成，165 条，`python tools/dump_skill_table.py` 重刷） |
| 某技能的**效果代码在哪** | 本文 **§4**（先在 skill-table 查到它的 stat / id，再来查消费点） |
| UPGRADES 条目某字段什么意思 | 本文 **§1** |
| 技能从抽卡到生效的整条链路 | 本文 **§2** |
| **加一条新技能** | 本文 **§5 决策树** → 选中模式后照 §3 该模式的"新增步骤" → [playbook §4](playbook.md) 检查单 |
| 为什么这样设计 / 数值权威源 | specs：[skills-720-rework](../specs/systems/skills-720-rework.md)（归属词汇/+1 轴）· [aircraft-signature-skills](../specs/systems/aircraft-signature-skills.md)（43 机签名技）· [evolution-attribute-gates](../specs/systems/evolution-attribute-gates.md)（三轴/里程碑/换机重放） |
| 玩法设计需求 / 未实装的技能想法 | [survivor-skills.md](../systems/survivor-skills.md)（设计层，骑士/恐惧/EMP/环境四系列 backlog） |

---

## 1. 配置层：UPGRADES 条目字段全解

数据源：`scripts/survivor/survivor_data.gd` `const UPGRADES`（表头注释是字段的代码内文档，与本节同步维护）。

| 字段 | 必/选 | 语义 | 谁消费它 |
|---|---|---|---|
| `id` | 必 | 唯一标识；账本 key、i18n key 词干、`requires_skill`/`excludes` 引用名 | 全链路 |
| `name` / `desc` | 必 | i18n key（`UPGRADE_<ID大写>_NAME/_DESC`，csv 列序 `keys,zh,en,ja`） | 卡片 UI |
| `stat` | 必 | **实装分派键**：`apply_upgrade` 的 match 按它走分支；`"skill_flag"`=apply 无操作、全靠消费点读账本/meta（§3-M3） | `survivor_player.apply_upgrade` |
| `value` / `max_stacks` | 必 | 单层量 / 可堆层数（×1=开关型）。比例、绝对、开关三种口径见 skill-table 效果列 | apply 分支 |
| `category` | 必 | 旧分类（survival/mobility/electronic_warfare/missile/secondary/weapon）。现存两个作用：①无显式 `axis` 时经 `AXIS_BY_CATEGORY` 兜底归轴 ②`category=="weapon"` 的技能**换机重放跳过**（效果长在武器资源上随武器库迁移）③电子战词条联动 `CATEGORY_BONUSES` 按它计数 | `axis_of_upgrade` / `_replay_player_upgrades` / `recompute_category_bonuses` |
| `axis` | 选 | 显式轴归属（`gladiator/knight/schemer`），优先级最高（> `AXIS_OVERRIDE_BY_ID` > category 兜底）。决定进哪张三选一轴卡 | `SurvivorData.axis_of_upgrade` |
| `rarity` | 选 | 五档 `Rarity` 枚举（稳定/先进/实验/机密/次世代），基础权重 0.50/0.25/0.15/0.08/0.02；自然三轴三卡的 4 级金卡走软 pity：连续未出 `m` 次时 `CLASSIFIED` 候选权重 ×`(1+3.5m)`，普通三卡见金清零（专属第四槽/奖励升级隔离） | `classified_pity_weight_multiplier` / `classified_pity_next_misses` / `pick_card_for_axis` / `_roll_axis_cards` |
| `keywords` | 选 | ①流派引导：已持有同关键词技能越多，同词新卡权重越高（+20%/stack，cap +100%）②**doctrine 门控**：6 词（fear/overload/bloodlust/chivalry/jam/stealth）需在生涯商店购入对应学说才进池（AND 语义；`sig_*` 豁免；spec doctrine-unlocks）③**升级卡状态脚注**：写了 `overload/bloodlust/stealth/fear/jam/slow` 的技能默认自动显示词条解释；主题标签或语义例外由 `STATUS_NOTE_OVERRIDE` 替换/压掉 | `compute_keyword_steering_weights` / `MetaShop.is_upgrade_gated` / `SurvivorData.status_notes_of` |
| `build_tags` / `build_role` / `terminal_for` | 选 | 状态构筑亲和、审计角色、终端归属；缺 `build_tags` 时从四个受支持状态 keyword 推导。软专注与终端债务只改变候选权重/槽位，不绕过任何 eligibility 门 | `compute_status_build_affinity` / `status_focus_multiplier` / `select_terminal_service_tag` |
| `doctrine_any` | 选 | 跨词条终端的学说 OR 组；组内任一学说已购即可通过该组，组外 gated keyword 仍保持 AND | `MetaShop.is_upgrade_gated` |
| `requires` | 选 | 硬件门（`gun/missile/flare/rocket/railgun/laser`…走 `has_equipment_of_kind`），缺硬件不进池 | `is_upgrade_available_for` |
| `requires_skill` | 选 | 前置技能（列表内**任一** stacks>0 即解锁） | 同上 |
| `exclusive_to` | 选 | **机型门**：仅当前 ACE 机型（`_player_profile_id`）在列表内才刷出。⚠ 只管**抽卡**，已获得的换机重放**不查**（=签名技能"跟人走"的机制基础） | 同上 |
| （无字段，靠 `sig_` id 前缀） | — | **签名技识别**：判别式 `SurvivorData.is_signature_upgrade(u)`；正式局普通三轴池统一排除，已购当前机型许可时走每机每局一次的独立第四槽；洋红卡框仍共用该判别式 | `is_normal_random_candidate` / `_append_signature_offer` / `SurvivorUpgradeUI` 卡框 |
| `excludes` | 选 | 互斥：列表内任一已持有 → 本条不再出现（如 cobra ↔ herbst） | 同上 |
| `evolved` | 选 | true = **不进随机池**，走战区奖励发放（获取渠道标记，不是实装模式；字段名是历史遗留，进化链已废） | 池过滤 + `zone_data` 奖励 roll |
| `scope` | 选 | 归属词汇 v6：`""`=通用全队逐机 / `"ace"`=仅当前操控机（切控迁移）/ `"squad_once"`=队级单实例（不落单机，消费点读账本） | `_distribute_upgrade` / `upgrade_applies_to_machine` |
| `classes` | 选 | 品类限定（gladiator/knight/schemer 机种身份）：全队下发、仅身份匹配机生效；全队无人匹配则不进池 | 同上 + `_squad_present_classes` |
| `milestone_plus` | 选 | 选卡时给该轴**里程碑进度** +1（不给门槛点；cap=2/轴）。String 或 **Array**（AX-00 双轴） | `milestone_plus_list_of` → `_grant_milestone_plus` |

**账本与生效子集**（配置读到哪里去了）：
- 队级总账 = `survivor_mode.upgrade_stacks: {id → 层数}`（唯一权威，换机不清）。
- 逐机生效子集 = 每架 `Aircraft` 的 `meta["upgrade_stacks"]`（按 scope/classes/操控机过滤后的子集，
  由 `_refresh_squad_effective_stacks` 在 拿技能/切控/进化/入队 后重建）。**消费点读 meta = 自动尊重归属**；
  squad_once 技能不在 meta 里，消费点必须读队级总账（或它同步出的静态位，见 §3-M4）。

---

## 2. 一条技能的生命周期（七步，全链路锚点）

```
①进池过滤            ②轴卡三选一             ③选卡记账
is_upgrade_available_for → pick_card_for_axis →  upgrade_stacks[id]+=1
(requires/exclusive_to/     (稀有度权重×keyword    + add_axis_point(轴+1)
 excludes/requires_skill/    steering；每3级       + _grant_milestone_plus
 classes/evolved/max_stacks)  三轴各一张；金卡软pity) (milestone_plus 逐轴+1, cap2)
        │                                              │
        ▼                                              ▼
④分发 _distribute_upgrade                    ⑤生效 apply_upgrade(_to)
  squad_once → apply_upgrade(ACE)+特判dispatch   match stat: 改params/置字段/无操作
  其余 → 逐机 upgrade_applies_to_machine 过滤     (skill_flag=无操作)
        │                                              │
        ▼                                              ▼
⑥消费（效果真正发生的地方，§4 查表）        ⑦重放（换机/入队/切控，技能"不丢"的机制）
  params 被物理/武器直接用｜字段被 tick/管线判｜   _replay_player_upgrades(进化后,不查门控)
  钩子读 meta｜队级消费读账本/静态位              _apply_build_to_new_member(新僚机入队)
                                                _migrate_ace_field_upgrades(切控,ACE字段技strip↔apply)
                                                reapply_all_milestones / remount_weapons(同批)
```

文件：①②`survivor_data.gd` ③④⑦`survivor_mode.gd` ⑤`survivor_player.gd` ⑥见 §4。
里程碑（三轴 2/4/6/8 档属性）不是技能：走 `_apply_milestone_effect` 独立 match，归 attr-gates spec 管。
里程碑的**归属**与技能同语义（跟玩家不跟机体、下发全队）：逐机记账挂飞机 meta `SurvivorPlayer.MILESTONE_RECORD_META`，
下发目标由 `SurvivorPlayer.milestone_targets_provider`（survivor_mode 注 `_squad_members_alive`）提供，
逐机 API = `apply_crossed_milestones_to` / `apply_all_milestones_to` / `reapply_all_milestones_to` / `_apply_milestone_effect_to`。

**②的金卡软 pity**：仅自然等级升级的普通三卡读取 `_classified_pity_misses`，三轴共享同一倍率；
三卡生成后见 `CLASSIFIED` 即清零，否则 +1。随后才执行签名技第四槽分支，因此第四槽不会消费累计。
奖励升级调用 `_roll_axis_cards()` 的缺省分支，倍率恒 1.0 且不改累计。权威数值见
[classified-card-pity](../specs/systems/classified-card-pity.md)。

**②的签名技分支**：`sig_*` 已从普通池排除；已购当前机型许可时，每机每局第一次符合的自然卡片事件
独立以 30% 概率追加第四槽。卡框色 `SurvivorUpgradeUI.SIG_FRAME_COLOR`，稀有度徽章仍显示真稀有度色。

---

## 3. 实装八模式（认出模式 = 知道去哪改）

> 每条技能属于且基本只属于一种模式。判别顺序：看 `stat` → 看 `scope` → 看消费点。

### M1 · 纯 params/资源直改（apply 即终点，无运行时判定）
- **识别**：apply 分支直接 `p.xxx = / *= / +=`，此后物理/武器读 params 自然生效。
- **适用**：永久数值（HP/伤害/射程/G/滚转/弹量/锥角/装填…）。机动类必须直改 params（AI 经 `effective_*()` 自动感知，AGENTS.md 类别 1）。
- **改哪**：`survivor_player.apply_upgrade` 加 case；**duplicate 再改**共享子资源（gun/missile 先 `p.gun = p.gun.duplicate()`——虽然产生路径已深拷，双保险防污染，见 §6-4）。
- **新增步骤**：表条目（专用 stat 名）→ apply case → 完事（消费零改动）。
- **成员**：见 §4.1 标 M1 的行。

### M2 · Aircraft 字段置位 + 高频消费点（条件态）
- **识别**：apply 只 `aircraft.xxx_active = true` / 写阈值字段；效果在每帧/管线里 `if ac.xxx` 判定。
- **适用**：高频判定（物理 tick、锁定循环、伤害管线、武器扫描）——这些地方读 meta 字典太贵，读 bool 字段便宜。
- **改哪**：apply case 置位 + 消费点加 if 块。机动 buff 的消费点**只准**是 `aircraft_physics.effective_*()` 或 `_g_buff_mult`（SEAM-001）；锁定类集中在 `survivor_mode._update_radar_locks` 722 段；伤害类在 `aircraft._apply_damage` / `take_bullet_damage`。
- **新增步骤**：表条目（专用 stat）→ Aircraft 声明字段 → apply 置位 → 消费点 if 块（≤5 行）。
- **成员**：§4.1 标 M2 的行。

### M3 · skill_flag + 事件钩子读 meta（低频触发型）
- **识别**：`stat: "skill_flag"`（apply **无操作**）；效果代码在事件点里 `int(meta_stacks.get("<id>",0)) > 0` 早退判定。
- **适用**：击杀/受击/投焰/躲弹/升级/停靠/阵亡/机动完成/命令下达… 低频事件触发。
- **改哪**：钩子集中地 = `skill_hooks.gd`（`dispatch_on_kill` / `dispatch_on_hit` / `on_evade_missile` / `on_flare_release` / `on_special_maneuver_done` / `try_gun_reserve_mag` 等静态函数）；事件源本身缺钩子才去事件点新增一行 dispatch。
- **新增步骤**：表条目（stat=skill_flag）→ 在对应钩子函数里加早退段；无现成事件 → 事件源加一行调 SkillHooks 新静态函数。
- **成员**：§4.2 全表。

### M4 · squad_once 队级单实例（账本/静态位消费）
- **识别**：`scope: "squad_once"`；`upgrade_applies_to_machine` 恒 false → **meta 里没有它**，消费点读 `survivor_mode.upgrade_stacks` 或它同步出的**静态开关**。
- **静态位现役**：`StatusEffects.sig_x13_active`、`SkillHooks.sig_fcas_active / sig_f35_active / sig_x90_active`（`_refresh_squad_effective_stacks` 尾部同步；**新局必须在 `survivor_mode._ready` 清零**——bench sig_skills §J 源码守卫）。
- **适用**：队级资源/全队一份的机制（数据链、充能加成、XP 乘区、光环、周期生成）。
- **新增步骤**：表条目（scope=squad_once）→ 消费点读账本；高频消费才加静态位（同步 + _ready 清零 + 断言，三件套缺一不可）。
- **成员**：§4 备注 squad_once 的行。

### M5 · 王牌 ace（只随操控机，切控迁移）
- **识别**：`scope: "ace"`。触发型（skill_flag）走 meta 子集天然迁移；**字段/params 型必须登记 `ACE_FIELD_STATS` 白名单 + 在 `strip_upgrade_from` 写逆操作**，否则切控双重叠加（720 铁律）。
- **改哪**：`survivor_data.ACE_FIELD_STATS` + `survivor_player.strip_upgrade_from` + 迁移点 `survivor_mode._migrate_ace_field_upgrades`。
- **成员**：missile_swarm / fear_on_lock / fear_squad_spread / head_on_jam / rear_aura_slow / cloud_overload（=白名单全集）＋触发型王牌若干（weapon_master/ew_expert/凝视类，走 meta 不登记）。

### M6 · 计数缩放（recompute 幂等重算）
- **识别**：效果=「按某个动态数量 × 每单位加成」；apply 是 skill_flag，真身在 `recompute_axis_count_skills`（挂 `recompute_category_bonuses` 尾部，拿技能/换机/入队都会重跑）或专用 watch 重算。
- **铁律**：**差量幂等记账**（`veteran_hp_bonus_applied` / meta `sig_gcap_layers` 模式）——换机重放序言清账、重算整额补回；直接 `+=` 会随重算无限叠。
- **成员**：veteran_hp（斗士轴技能数×HP）/ speed_by_knight（骑士轴×极速）/ ew_expert（策士轴×雷达）/ weapon_master（装备数×CD）/ sig_gcap（僚机存活数×导弹+雷达，0.5s watch）。

### M7 · 一次性 dispatch（生成/入库类即时动作）
- **识别**：获得瞬间做一次性动作（生成僚机/武器入库），不是持续效果。挂 `_distribute_upgrade` 的 squad_once 分支 → `_dispatch_sig_oneshot`，**`_sig_oneshot_done` 字典防换机重放重复执行**。
- **成员**：sig_f47（2 架永久忠诚僚机）/ sig_x02（电磁炮入库+参数）/ sig_ax00（克隆 1 僚机，复用 `_spawn_reward_wingman`+build 补挂）。战区武器领取 `_claim_weapon_reward` 是同类语义的姐妹路径。

### M8 · 武器资源改动（category="weapon"，随武器库迁移）
- **识别**：效果长在**武器/装备资源**上（railgun/laser/torpedo/qmaam/loyal_wingman params）。`category: "weapon"` → **换机重放跳过**（防双叠），继承靠 `record_special_weapons`（进化前快照资源引用，强化随引用走）+ `remount_weapons`。
- **改哪**：apply case 里改对应资源字段（同样 duplicate 语义）；武器本体逻辑在 `equipment/*.gd` / `missile.gd`。
- **成员**：railgun_charge/range/double、laser_cooldown/range/heat/extra_beams、torpedo_extra/tracking_boost、qmaam_boost、wingman_extra/armed、sig_wyvern。

---

## 4. 全 stat 消费点速查（163 条全覆盖）

> 用法：skill-table 查到技能的 id → 在 4.1 按 stat（专用 stat 名≈id）或 4.2 按 id 找行。
> 消费点 = "效果真正发生"的文件+函数/字段。`survivor_player.gd apply_upgrade` 是所有条目的公共 apply 处，不重复写。

### 4.1 专用 stat（92 条；M=模式）

**生存/伤害管线**（消费集中在 `aircraft.gd`）

| stat | M | apply 做什么 → 消费点 |
|---|---|---|
| max_hp / armor / kill_heal | M1 | 直改 params（kill_heal 消费在 `survivor_spawner._kill_heal`） |
| bullet_dodge_flat / low_alt_gun_dodge / head_on_gun_dodge | M2 | 字段 → `aircraft.take_bullet_damage` 闪避累加区（全局 cap 0.85） |
| gun_fire_dr | M2 | 窗口字段 → `aircraft._apply_damage`（开火后减伤窗） |
| cockpit_armor | M2 | `ground_damage_taken_mult` → `_apply_damage`（地面来源过滤） |
| shock_absorb | M2 | 字段 → `_apply_damage` 排队回血 + `aircraft_physics` 缓回 tick |
| evac_shift | M2 | 字段 → `_apply_damage`（撤离减伤）+ `aircraft_physics` accessor（冲刺提速） |
| xp_mult / sig_xp_wisdom | M4 | `SurvivorPlayer.xp_multiplier / sig_xp_mult` → `survivor_spawner._detect_kills` 两处乘（同乘区还有第三因子：机体特性 `PlayableAircraft.xp_gain_mult`，非技能 stat，幻影 III=1.1，经 `_aircraft_xp_mult()` 读 `_player_profile`） |

**机动/物理**（消费集中在 `aircraft/aircraft_physics.gd`；SEAM-001）

| stat | M | 消费点 |
|---|---|---|
| speed / maneuver / dogfight / sig_relaxed_stability / sig_vectored_canard | M1 | 直改 params（max_speed/accel/max_g/roll/stall/g_drag），物理直读 |
| lock_panic_g | M2 | `_g_buff_mult`（被锁 +G） |
| evasion_speed_boost / evasion_weapon_cd | M2 | `aircraft.evasion_modifiers` 字典 → `set_evasion_mode` 进出缩放 + effective_* |
| sig_tornado | M2 | `effective_max/cruise_speed_kmh`（LOW +8%）+ 充能倍率（survivor_mode AB update 处） |
| sig_typhoon | M2 | `update_speed` 爬升免罚 / `update_altitude` 爬升率×1.5 / `take_bullet_damage` 变高闪避 |
| sig_viffing | M1+M2 | params.deceleration×1.5 + `aircraft._update_sig_skills` 低速无敌 |
| vapor_dodge | M2 | `altitude_authority_mult`（physics cap1.3）+ `cloud_lock_stealth`（锁定循环） |
| alt_change_stealth | M2 | `update_altitude` 维护 `_alt_velocity` → 锁定循环按爬降速率减敌方锁率 |
| hunter | M2 | ASSAULT/双击突击开启，目标生命周期关闭；physics effective accessor 注入 +2G、加减速 ×1.2、G 损失 ×0.7，`aircraft._apply_damage` 承伤 ×0.7 |
| berserk_virus | M2 | 全队字段置位 + 非亲控直属僚机动态门；`aircraft` 锁 FREE 与 weapon/flare CD rate，`aircraft_physics` 注入 G/滚转/加减速，`skill_hooks.dispatch_on_kill` 施加标准 BLOODLUST；主动切控与 C 模式切换分别由 survivor_mode/HUD 拦截 |

**雷达/锁定管线**（消费集中在 `survivor_mode._update_radar_locks`，722 集中注入段）

| stat | M | 消费点 |
|---|---|---|
| sig_lock_retention | M1+M2 | params.radar_range+250px + 出锥 grace 冻结窗（`_sig_lock_grace` 字典） |
| sig_f15c / sig_f15e / sig_a6e / sig_mig41 / sig_f15 | M2 | 锁定循环 722 段（f15/f15e 的伤害半段在 bullet_manager / missile_manager 命中处） |
| high_alt_lock_speed | M2 | 锁定循环（HIGH 档我方锁敌加速） |
| close_range_lock | M2 | Aircraft 缓存贴身倍率上限 → 锁定循环按“当前距离 / 当前有效雷达射程”线性计算（边缘 ×1、贴身最高 ×2） |
| ecm_pod | M2 | `ecm_range_mult` → 锁定循环（敌雷达对我有效距离缩短） |
| data_link / f14_squad_lock_slow | M4 | 锁定循环尾部两个队级账本段（照射共享拉平 / 共锁 SLOW） |
| sig_multiband | M1 | params.radar_half_angle+40°（cap120） |
| fear_on_lock / head_on_jam | M5 | 阈值字段 → 锁定循环（fear）/ `aircraft` 对头累计 tick（jam）；ACE_FIELD_STATS |
| fire_control_saturation | M3+M5 | 数据链合并后的低频锁定 tick → `SkillHooks.try_fire_control_saturation`；单局 CD/五锁沿由 survivor_mode 持有，OVERLOAD 期间 `aircraft.effective_max_locks` +2 |

**状态/buff 系**（`status_effects.gd` + `skill_hooks.gd` + `aircraft.apply_status` 覆写）

> ⚠ 新加"涉及真实状态词条"的技能：卡片脚注走 `SurvivorData.status_notes_of`。
> keywords 里写了状态名默认自动带上；**只有两种情况要手动登记**——
> ① 施加状态但关键词里没写（INVINCIBLE 没有对应关键词，全走 `STATUS_NOTE_EXTRA`）；
> ② 关键词与实际状态语义不符（`STATUS_NOTE_OVERRIDE` 整条替换；空数组可压掉只用于流派/主题的状态词，如 `vapor_dodge`）。
> 文案 = `StatusEffects.NOTE_I18N_KEY`；回归门 `--bench=status_notes`。

| stat | M | 消费点 |
|---|---|---|
| cloud_overload / cloud_weapon_cd | M5/M2 | `aircraft._update_cloud_state` 每 0.2s 刷新 timed OVERLOAD；`aircraft.cd_rate("weapon")` 按当前云态消费，不改写运行中倒计时 |
| evasion_stealth / missile_cd_stealth | M2 | `aircraft` 派生标记 → `StatusEffects.update` 三源 OR 进 STEALTH |
| sig_status_immunity | M2 | `combat_unit.apply_status` 头部负面早退 |
| jam_aura / rear_aura_slow | M5 | `aircraft` 累积式光环 tick（0.5s；ACE_FIELD_STATS） |
| fear_squad_spread | M5 | `survivor_spawner._trigger_squad_fear`（击杀后同队扩散） |
| fear_chills | M2 | `AOEBroadcast.apply_status_in_radius` 联动段 + spawner 单体路径（FEAR 附带 SLOW） |
| executioner | M2 | `aircraft` 层数/连击字段 → physics（速度/减速）+ weapons（装填）+ 锁定循环（`_executioner_lock_mult`） |

**热诱弹/规避**（`aircraft/aircraft_flares.gd` + `aircraft.gd`）

| stat | M | 消费点 |
|---|---|---|
| flare_shield | M2 | `flare_lock_immunity` → flares release 清锁+豁免窗；bonus_flares 直改 params |
| low_hp_flare_reload | M2 | flares 低血装填加速段 |
| manual_dodge | M5 | 全队下发；`aircraft.try_manual_maneuver → do_manual_dodge`（受控机 R）/ `_update_manual_dodge_skill`（AI 威胁自动）+ flares 禁普通自动早退；占用五选一主动机动槽 |
| cobra_skill / evasion_herbst / manual_dodge / displacement_roll / vertical_break | M2 | 当前操控机由 `aircraft.try_manual_maneuver` 响应 R；AI 僚机按技能各自威胁距离自动触发；五项 `excludes` 双向互斥，冷却写 `Squad.active_maneuver_cooldown_s`；新两项轨迹与命中资格走 `aircraft._update_active_special_maneuver / can_accept_new_hit` |
| evasion_overstock | M2 | `aircraft` evasion 期间周期装填 tick |
| sig_mirage3（skill_flag，见 4.2） | — | flares 保护窗 ×1.6 + 偏转瞬间无敌（release 722 段） |

**武器：机炮/导弹**（`aircraft/aircraft_weapons.gd` + `missile*.gd` + `bullet_manager.gd`）

| stat | M | 消费点 |
|---|---|---|
| gun_damage / gun_accuracy / aim_assist / sig_x44 | M1 | 直改 params.gun；X-44 为正面 180°绝对射界并开启普通机炮/炮舱子弹逐目标贯穿 |
| gunship_mode / heavy_gun | M1 | 全队机炮半角设 180°且 max_speed ×0.60；当前机与 AI 僚机各自以 3Hz `auto_gun_scan` 扫描最近敌对 Aircraft/GroundUnit，不受 planner 当前目标锁池或 MISSILE 主武器模式静默；`update_gun` 整梭锁存扫描目标并逐 tick 刷新提前点，炮口随射向旋转；CIWS 保持独立正面 5°锥 / 全队机炮 range +1000m |
| gun_multishot | M2 | `gun_extra_barrels` → `_fire_gun_round` 翼挂双点 |
| gun_ciws | M2 | weapons CIWS 自动拦截段 |
| ab_gun_regen | M2 | 加力时机炮回弹（aircraft + weapons） |
| altitude_energy_cycle | M2 | `Aircraft` 字段保存定稿参数；每架玩家小队机由 `AircraftWeapons.update_altitude_cycle_ammo` 在 `DIVE` 时以 25 发/s 回复至 `2×max_ammo`，编队提前返回路径同样独立结算；`survivor_mode` 只读取当前操控机 `CLIMB`，向共享 `AfterburnerCharge.update` 注入 +0.2/s，不按小队人数叠加 |
| missile_count / missile_boost / sig_long_spear | M1 | 直改 params.missile |
| multi_lock / missile_swarm | M1 | 全队加算 `max_simultaneous_locks`（每层 +1 / 一次 +3）；蜂群另有弹舱 +4、追踪 G ×0.85；`_fire_multi_lock_salvo` 按有效锁数截断且正常冷却 |
| missile_bounce（连锁弹头） | M2 | `SurvivorPlayer.apply_upgrade` 开启发射快照；`MissileManager` 命中后不销毁，`Missile` 逐弹记录已命中目标并沿原航向直飞 |
| proximity_fuze | M2 | `missile_proximity_aoe` → `missile_manager` 命中分支 |
| missile_second_stage | M2 | `missile.second_stage`（spawn 打标）→ missile 续推/渐强曲线 |
| rocket_firerate_range | M1/M8 | 直改 rocket params（A-10 族；火箭现属外部装备） |

**特殊武器/装备（M8 全组）**：railgun_charge/range/double → `equipment/railgun_equipment.gd`；laser_cooldown/range/heat/extra_beams → `equipment/laser_equipment.gd`；torpedo_extra/tracking_boost → torpedo params；qmaam_boost → secondary_missile params；wingman_extra/armed → loyal_wingman params（消费 `aircraft_weapons.update_loyal_wingman`）；sig_wyvern → M7 dispatch + railgun 参数。

### 4.2 skill_flag 72 条（apply 无操作，按消费点分组）

**SkillHooks 击杀/受击/状态钩子**（`survivor/skill_hooks.gd`，入口 `dispatch_on_kill` / `dispatch_on_hit` / `on_player_jam_landed` / `on_evade_missile` / `on_flare_release`）：
skill_kill_bloodlust · skill_damaged_bloodlust · skill_head_on_perma_hp · skill_head_on_aoe_fear ·
skill_missile_hit_invul · skill_lowest_alt_kill_invul · skill_gun_kill_fear · skill_kill_status_heal ·
skill_flare_aoe_jam · skill_gun_kill_flare_drop · skill_missile_hit_aoe_jam · skill_laser_damage · skill_laser_hack ·
skill_torpedo_aoe_jam · skill_rocket_homing · skill_evade_missile_overload · skill_flare_overload ·
overload_duration_4x（`aircraft.apply_status` 覆写乘区）· overload_extended_ammo · overload_to_bloodlust ·
bloodlust_armor_mobility（physics `_g_buff_mult`+accel / `_apply_armor` DR）· full_hp_kill_perma_hp ·
jam_self_overload · invasion_algorithm（JAM→MQ-109～112 坠毁）· flee（新 FEAR→普通载人机撤退）·
stasis（导弹直伤→2km SLOW）· mental_confusion（新 FEAR→浪费 flare/导弹）·
ratatat（BLOODLUST 中机炮有效射程/锥/间隔）· storm_i / storm_ii（AfterburnerCharge 实耗/免费充放）·
fire_control_saturation（当前王牌五锁上升沿→OVERLOAD；20s 单局 CD；状态期间有效锁数 +2）·
hush（JAM 敌机禁 flare + 导弹失导；队级静态位）·
adapt_energy（AB 回能/回血）· qmaam_bloodlust（`missile_manager` kind 归因）

**survivor_mode 事件段**：squad_revenge / assassin_revenge / blackbox_recovery（`_on_squad_member_down` 僚机阵亡 watcher）· levelup_heal（`leveled_up`）· ground_crew（停靠减半 `dock_point` + 起飞奖励卡）· ab_kill_charge / ab_duration（充能账本同步段）· headon_xp（`survivor_spawner` XP 段）

**720 计数缩放 M6**：veteran_hp · speed_by_knight · ew_expert · weapon_master（`survivor_data.recompute_axis_count_skills` → aircraft 字段 → physics/weapons/锁定消费）

**720 弹尽/轮盘**：gun_reserve_mag / gun_out_free_missile（`skill_hooks.try_gun_reserve_mag / in_free_missile_window` ← weapons 扣弹口）· guard_zone_buff / evac_shift 联动（`rts/squad_command_controller` 维护 flag → physics/_apply_damage）

**722 签名技（spec aircraft-signature-skills §4 有完整分层）**：
sig_mirage3 / sig_rafale（flares release 722 段）· sig_su27 / sig_su35（`on_special_maneuver_done` ← cobra/herbst 完成点）· sig_x77（dispatch_on_kill 导弹击杀→隐身）· sig_a10 / sig_a12（`aircraft._try_sig_death_save` 致死拦截）· sig_f22（`apply_status` STEALTH 上升沿装填 + `effective_max_locks` 隐身齐射）· sig_fcas（`broadcast_combat_cloud` + apply_status 覆写；静态位）· sig_f35（weapons `_sig_f35_relay_ok` 越肩发射；静态位）· sig_x13（`status_effects.tick` 流速；静态位）· sig_x90（`whale_pod_share` 均摊 ← `_apply_damage` + 25s 周期生成；静态位）· sig_x09（`missile_manager.spawn_missile` 打标 → `ai/missile_evasion` 单点过滤）· sig_x21（spawn 打标 → `missile.gd` 被偏转重索敌）· sig_mig31 / sig_su34（`aircraft._update_sig_skills` 窗口自动发射 / `afterburner_charge.update` 窗口回血）· sig_gripen_c / sig_fa18e / sig_yf23（survivor_mode 充能倍率 / 起飞钩子两条）· sig_j36（`try_trigger_j36_assault` ← 轮盘 ASSAULT+双击冲锋 → physics 三注入）· sig_gcap（`_update_sig_gcap` M6）· sig_f47 / sig_ax00（`_dispatch_sig_oneshot` M7）

---

## 5. 加新技能决策树

```
效果是什么？
├─ 永久改机体数值（HP/速度/G/弹量/射程…） ──────────→ M1（机动类必须直改 params）
├─ 条件成立时的持续修正（低空/满血/被锁/某状态中…）
│    ├─ 判定点是每帧物理/锁定循环/伤害管线 ─────────→ M2（Aircraft 字段）
│    └─ 判定点是低频事件 ────────────────────────→ M3（skill_flag + 钩子）
├─ 事件触发一次性效果（击杀回血/受击无敌/躲弹反制…） ──→ M3
├─ 全队一份的机制（共享/光环/队级资源/XP） ─────────→ M4（squad_once）
├─ 只该操控机有（AoE 控场/操作键） ────────────────→ M5（ace；字段型必登记 ACE_FIELD_STATS+strip）
├─ 按动态数量缩放（技能数/僚机数/装备数 × 加成） ────→ M6（recompute 差量幂等）
├─ 获得瞬间生成/入库 ─────────────────────────────→ M7（oneshot dispatch）
└─ 改特殊武器本身（电磁炮/激光/僚机/雷/QMAAM） ─────→ M8（category="weapon"）

获取渠道另选：常规池（默认）｜战区奖励（evolved:true + zone_data 权重）｜机型签名（exclusive_to）
```

每条新技能收尾四件套：i18n 三语（`UPGRADE_<ID>_NAME/_DESC`）→ `python tools/dump_skill_table.py` 重刷表 →
bench 断言（单机制优先追加 skills720 / sig_skills / attr_gates；全表契约跑 skill_audit）→ 本文 §4 加一行。完整检查单见 [playbook §4](playbook.md)。

---

## 6. 铁律（改技能系统前先读，每条都烧过手）

1. **换机重放不查门控**：`_replay_player_upgrades` 刻意不调 `is_upgrade_available_for` —— 这是"技能跟人走"的根基。看着像漏了校验，**别补**（补了 = 43 条签名技换机全失效）。
2. **ACE 字段技必配 strip**：scope:"ace" 且写字段/params → `ACE_FIELD_STATS` 登记 + `strip_upgrade_from` 逆操作，否则切控双重叠加。
3. **static 账本位三件套**：新加静态开关必须 同步（refresh 尾部）+ 新局清零（`_ready`）+ 源码断言，缺一即跨局残留。
4. **共享资源深拷契约**：玩家机产生的四条路径（出生/起始僚机/奖励僚机/进化）都必须 `deep_dup_weapons`；`duplicate(true)` **不深拷子资源**（实测），少一处 = 玩家升级写进共享 .tres、敌机跟着变强（power-curve §2.7）。
5. **计数缩放必须差量幂等**：M6 用 applied 记账（重放序言清零、重算补回），直接 `+=` 会叠爆。
6. **改数值必同步三语 desc**（feedback 铁律）+ 重跑 dump_skill_table。
7. **FEAR/JAM/SLOW 联动走集中 helper**：AOE 必经 `AOEBroadcast.apply_status_in_radius`（team_filter 传 `TEAM_HOSTILE`，传 -1 会误伤友军——寒蝉 bug 原案）；单体玩家 FEAR 走 `_apply_player_fear`（SEAM-004）。
8. **机动 buff 只在两处注入**（AGENTS.md 强制）：永久 → params；状态 → `effective_*()`。物理 tick 里散点 if-else 会让 AI 战术层失明。
