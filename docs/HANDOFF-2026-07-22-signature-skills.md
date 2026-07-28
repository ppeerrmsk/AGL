# 交接工作日志 —— 2026-07-22 机体签名技能批（722）

> 临时交接文档（交接完成后可删）。写给**下一个接手的 AI / 开发者**：本批做到哪、为什么这么做、
> 哪些地方碰了会炸、下一步该干什么。
> 权威源是 spec `docs/specs/systems/aircraft-signature-skills.md`（数值/行为以它为准，本文只讲工程状态与交接要点）。
> 同日另有一份 `docs/HANDOFF-2026-07-22.md`（全局平衡批），两批**共用同一个未提交的工作树**，见 §2。

---

## 0. 一句话状态

**用户 722 表（41 机每机一条专属技能）已 spec-first 全量落地，工程侧闭环：`--bench=sig_skills` 51 断言 + `--bench=all` 回归门 34 项全绿，spec `in-progress` 差 playtest 调数值。**

---

## 1. 用户原始设定（四条，不可擅自改动）

原始需求文件：`C:\Users\noelu\Desktop\722机体原创技能 …md`（41 行表：机型 / 专属技能名 / 轴 / 效果 / 备注）。
用户明确的四条规则：

1. **只有装备并驾驶该飞机时，升级才会有概率刷出这些专属技能**
2. **稀有度一律 4 级**
3. **默认只装备在同机种上；换机种后技能延续到下一架，不断往下带、不会被移除**
4. **之后可能上锁进局外 Meta Progression（花钱解锁）；但现阶段先全部实装做进去**

落地对应：① = `exclusive_to`（按当前 ACE 机型判）；② = `Rarity.CLASSIFIED`（720 表的 1~5 编号里 4 = 机密/金，与 `railgun_double` 交叉验证过）；③ = 玩家层账本 + `_replay_player_upgrades` 无条件重放；④ = 预留（见 §5.4）。

---

## 2. ⚠ 工作树状态（接手第一件事，与另一份 HANDOFF 同一问题）

**工作树里同时躺着三个批次的改动，全部未提交**，最近提交仍是 `c2db772`（720 技能批 T6 收尾）：

| 批次 | 标志物 | 状态 |
|---|---|---|
| **本批**（签名技能） | `scripts/tests/test_sig_skills.gd`、`docs/specs/systems/aircraft-signature-skills.md` | 回归绿，差 playtest |
| 全局平衡批 | `docs/specs/systems/battlefield-tempo-pass.md` 等 | 见 `docs/HANDOFF-2026-07-22.md` |
| boss-hunter + wraith 阶段 2 | `scripts/survivor/wraith_tactics.gd`、`test_boss_hunter.gd` | 据 `_INDEX.md` 回归绿 |

**不能按文件粒度拆提交**：`survivor_mode.gd` / `survivor_data.gd` / `i18n/translations.csv` 三个文件里混着三批改动。
建议**一次性整体提交**（三批同日同轮需求，各自都跑过回归），或 `git add -p` 逐 hunk 挑。

---

## 3. 本批产出文件清单

### 新增
| 文件 | 说明 |
|---|---|
| `docs/specs/systems/aircraft-signature-skills.md` | **权威 spec**（41 条数值全表 §2.2 + 歧义裁定 14 条 §2.3 + 实现锚点 §7） |
| `docs/changelogs/2026-07-22-aircraft-signature-skills.md` | 本批 changelog |
| `scripts/tests/test_sig_skills.gd` | 无头验收，51 断言，bench key = `sig_skills`，已并入 `--bench=all` |

### 修改（按"改了什么"分组，行号见 `code-index.md` 的"722 批 机体签名技能"段）

**数据与文案**
- `survivor_data.gd` — 表尾 **40 条 `sig_*`**（F-14 围猎=既有 `f14_squad_lock_slow` 改名改档，不重复建条）；`milestone_plus_list_of()` 数组化
- `i18n/translations.csv` — **新增 80 键**（40 × NAME/DESC）三语 + 围猎改名 1 键
- `tools/dump_skill_table.py` — `milestone_plus` 数组兼容（表重生成 → **144 条**）

**效果注入（按机制）**
- `survivor_player.gd` — apply 专用分支（params 类 8 条 + 置位类 10 条）、`sig_xp_mult` 第二 XP 乘区
- `survivor_mode.gd` — 锁定管线集中注入、一次性特判 `_dispatch_sig_oneshot`、`_update_sig_gcap` 差量、`_sig_spawn_loyal_drone`、`_spawn_reward_wingman`（抽取）、起飞钩子、加力充能倍率、**静态账本位新局清零**
- `skill_hooks.gd` — `on_special_maneuver_done` / `try_trigger_j36_assault` / `broadcast_combat_cloud` / `whale_pod_share` + 4 个静态账本位
- `aircraft.gd`（+204 行，本批最大头）— 签名字段块、`_update_sig_skills` tick、`_try_sig_death_save`、`apply_status` 覆写扩展（STEALTH 上升沿 / 作战云 / 中继直通）、`_sig_f22_reload_all`、`effective_max_locks`、超速截击发射通道
- `aircraft_physics.gd` — typhoon（爬升免罚 + 爬升率 ×1.5）/ j36（G+2、加减速 ×1.4、滚转 ×1.3）/ mig41（俯冲加速）/ tornado（低空 +8%）
- `aircraft_weapons.gd` — `_sig_f35_relay_ok` 越肩发射 + `effective_max_locks` 三处消费点
- `aircraft_flares.gd` — 幻影（窗口 ×1.6）/ SPECTRA（对射手 JAM）/ 偏转瞬间无敌
- `combat_unit.gd` — 负面状态免疫早退；`status_effects.gd` — X-13 流速 ×0.6
- `missile.gd` / `missile_manager.gd` / `bullet_manager.gd` / `missile_evasion.gd` — 夜枭静默弹、超越地平重索敌、对地伤害 ×1.3、满血机炮 ×1.2
- `cobra_maneuver.gd` / `herbst_maneuver.gd` — 机动完成事件发射点（各 2 行）
- `squad_command_controller.gd` — 三发推力突击触发
- `afterburner_charge.gd` — `update(delta, rate_mult)` 入参 + 窗口内 Su-34 回血
- `bench_runner.gd` — 注册 `sig_skills`
- `tools/verify_player_ref_holders.py` — `AircraftWeapons` 显式裁定入 `NON_HOLDERS`

**文档**
- `docs/specs/_INDEX.md` 新增一行；`code-index.md` 新增 722 段 + **重定位 35 处腐烂锚点**（多为本批插入造成的行号漂移，也顺带修好了另两批遗留的）；`script-index.md` 三处；`docs/systems/survivor-skills.md` 顶部横幅

---

## 4. 实现地图（41 条按挂载机制归类，逐条数值见 spec §2.2）

接手时**不要逐条读代码**，按机制找入口即可：

| 机制类别 | 条数 | 入口 | 代表技能 |
|---|---|---|---|
| 永久 params 直改 | 8 | `survivor_player.apply_upgrade` 722 段 | 静不稳定 / 矢量鸭翼 / 霹雳长矛 / 多波段搜索 / 高速炮艇 |
| 锁定管线集中注入 | 6 | `survivor_mode._update_radar_locks` 722 段 | 无败之鹰 / 制空清扫 / 对地特化 / 盲飞入侵 / 唯一的锁定 |
| physics accessor | 4 | `aircraft_physics` effective_* / update_speed / update_altitude | 三发推力 / 地形跟随 / 超巡爬升 / 近太空冲刺 |
| 每帧条件 tick | 5 | `aircraft._update_sig_skills` | VIFFing / 近太空冲刺 / 超速截击 / 三发推力解除 |
| 事件钩子 | 9 | `skill_hooks.gd` 722 段 + flares/起飞/apply_status | SPECTRA / 引渡人 / 急停机动 / 落叶飘 / 落选者 / 甲板周转 / 作战云 |
| 致死拦截 | 2 | `aircraft._try_sig_death_save` | 钛浴缸 / 不被期待的计划 |
| 武器行为改写 | 4 | `aircraft_weapons` / `missile*` | 传感器融合 / 夜枭 / 超越地平 / 先敌开火 |
| 队级账本（static） | 4 | `_refresh_squad_effective_stacks` 同步 | 全频段压制 / 作战云 / 传感器融合 / 鲸群 |
| 一次性生成/入库 | 3 | `survivor_mode._dispatch_sig_oneshot` | 忠诚僚机编队 / 突击翼龙 / 双子星 |

---

## 5. ⚠ 不变量与陷阱（碰了会炸，按危险度排序）

### 5.1 换机继承靠"重放不查门控"——**别顺手加过滤**
`_replay_player_upgrades` 遍历 `upgrade_stacks` 时**故意不调** `is_upgrade_available_for`。
一旦有人"顺手补个可用性校验"，全部 41 条签名技能会在换机瞬间失效——**用户第 3 条规则当场作废**。
这是本批最脆弱的地方，且看代码时非常像"漏了校验"。

### 5.2 签名技能全是通用 / squad_once，**没有一条 `scope:"ace"`**
所以不需要登记 `ACE_FIELD_STATS`。若将来把某条改成王牌层（只对操控机生效），
**必须**同步 `ACE_FIELD_STATS` + `strip_upgrade_from` 逆操作，否则切控双重叠加（720 批的铁律，spec skills-720 §7 有原文）。

### 5.3 差量记账三处，换机重放序言必须清零
`veteran_hp_bonus_applied`（720）/ `sig_gcap_layers`（联合突击）/ `sig_fa18e_hp_gained`（甲板周转，**反过来是补回不是清零**）。
新增同类"按状态量重算的加成"时照抄这个模式，否则换机后要么翻倍要么丢失。

### 5.4 队级账本位是 `static var`，跨局不自动清零
四个：`StatusEffects.sig_x13_active` / `SkillHooks.sig_fcas_active` / `.sig_f35_active` / `.sig_x90_active`（+ `cloud_relaying` 守卫）。
**本批已在 `survivor_mode._ready` 显式清零**，并加了防回归断言（bench §J 读源码校验）。
新增 static 账本位时**必须**同时加到 `_ready` 清零列表 + 断言列表。

### 5.5 作战云的中继守卫
`SkillHooks.cloud_relaying = true` 期间，`Aircraft.apply_status` 覆写**直通 super**，跳过全部乘区。
目的：防止 OVERLOAD 的 ×4/+6 乘区被广播二次放大 + 防递归自激。
任何在 `apply_status` 覆写里新增的逻辑，都要想清楚"中继期间该不该跑"。

### 5.6 致死拦截绕过了正常坠机链
`_try_sig_death_save` 返回 true 时直接 `return`，**不走** `_record_kill_attribution` / `_start_destroy`。
同帧连击穿透靠手动置 `invulnerable = true` + `_status_owns_invul = true`（状态系统当 owner，下帧由它正常回收）。
若将来在 `_apply_damage` 的 `hp<=0` 分支加新逻辑（例如击坠统计），要考虑被拦截的这一支。

### 5.7 夜枭静默弹只过滤一处
`missile_evasion.find_nearest_incoming_missile` 是**规避与投焰共用**的检测入口，所以一处过滤覆盖两个行为。
若将来 flare 触发改走别的检测路径，必须补上 `sig_silent` 过滤，否则"敌人看不见导弹"只剩一半。

### 5.8 高速炮艇是直改 `params.gun.fire_cone_half_angle`（不是新字段）
好处：渲染扇形 / AI 开火判定 / 物理锥门 / 扫描全部消费点自动跟随。
代价：`aim_assist` 的 45° cap 会把 90° 缩回去——**已改成 cap 不低于当前值**。将来任何给该字段设 cap 的技能都要照做。

---

## 6. 验证与复跑

```bash
# 本批专项（51 断言）
godot --headless --path . -- --bench=sig_skills
# 全量回归门（34 项，含上面这项）
godot --headless --path . -- --bench=all
# 索引/引用校验（commit 前必跑，CLAUDE.md 硬约定）
python tools/verify_player_ref_holders.py
python tools/verify_doc_anchors.py
# 技能表重生成（改了 UPGRADES 或 i18n 后）
python tools/dump_skill_table.py       # → docs/reference/skill-table.md，当前 144 条
```

Godot 可执行文件在 `C:\Users\noelu\Downloads\Godot_v4.6.2-stable_mono_win64\...\Godot_v4.6.2-stable_mono_win64_console.exe`。

**当前状态**：上述四项全绿（锚点 426 个全部一致）。
**没跑的**：生存模式 playtest、Sentinel + Lv5+ 性能压测、Godot 编辑器 `--import`（改了 i18n csv，**进引擎前需要 import 一次**否则 `tr()` 原样返回 key）。

---

## 7. 遗留项 / 下一步

### 7.1 playtest（唯一阻塞项，需要用户实机）
1. **门控体感**：驾驶 F-15 时 sig_f15 是否刷得出来（CLASSIFIED 8% + 8 次保底），换机后旧技能是否还在
2. **数值调档**：本批数值多为保守初值，见 §7.3
3. **强度异常观察**：夜枭静默弹（40%）绕过王牌中队的热诱弹命数体系——**这是预期设计但可能过强**；鲸群均摊是否让小队过肉
4. **性能**：Sentinel + Lv5+ 压测，FPS 掉幅 < 15（本批全部 O(1) 字段读，理论无影响，但 x90 均摊会在受伤帧扫一次 all_units）

### 7.2 未做的小项
- **卡面"签名"专属角标**：归属角标机制（`survivor_upgrade_ui._scope_badges`）现成，样式建议 playtest 时和用户一起定
- **Meta 上锁**（用户第 4 条）：现阶段刻意全开。将来只需在 `is_upgrade_available_for` 加一层"局外解锁表"查询，数据结构已够用，不用改表

### 7.3 我自行拍板的数值（playtest 时优先质询）
用户表里只给了定性描述的，我按保守值落的：
- 幻影 flare 窗口 ×1.6 + 偏转瞬间 1.5s 无敌；SPECTRA JAM 5s
- 对地特化 锁定 ×1.5 / 伤害 ×1.3；无败之鹰 ×1.2/×1.2
- 甲板周转 HP +10/次 **封顶 +50**（防机场反复横跳无限膨胀，用户表未限制）
- 钛浴缸 CD 60s（用户指定）；VIFFing CD 20s、无敌 4s（用户只给 4s）；三发推力 CD 15s（用户指定）
- 夜枭 40%；全频段压制 ×0.6；鲸群 25s/架 上限 3、光环 1500m
- 智能鹰 XP ×1.25（用户只说"更多功勋"）；联合突击 雷达 +5%/层（用户指定挂载 +1）

### 7.4 落地偏差（spec §2.3 有完整 14 条裁定）
- **地形跟随**"低空无速度惩罚"：游戏里**根本没有**低空速度惩罚这个机制 → 上翻为"低空 +8% 增速"保留突防风味
- **超巡爬升**的 +30% 机炮闪避走全局 85% dodge cap 兜底（与其余 dodge 技能一致），没单设 70%
- **围猎**（F-14）= 720 批的群猎注视改名 + 升档，效果没动

### 7.5 顺手修的既有问题（不属于本批需求，但已一并修掉）
1. **`_apply_build_to_new_member` 全仓零调用** —— 720 批 T1 声称的"新僚机入队补挂"实际漏了接线，奖励僚机一直吃不到已有 build。现挂 `_spawn_reward_wingman` 尾部
2. **`aim_assist` cap 倒退**（见 §5.8）
3. **static 账本位跨局残留**（见 §5.4）

---

## 8. 加第 42 条签名技能的操作手册

1. 读 spec `aircraft-signature-skills.md` §2.1 系统规则，往 §2.2 表加一行（数值定稿在先）
2. `survivor_data.gd` 表尾 722 段加条目：`id: "sig_<机型id>"` / `exclusive_to: ["<机型id>"]` / `rarity: Rarity.CLASSIFIED` / `max_stacks: 1` / 显式 `axis`
3. `i18n/translations.csv` 加 `UPGRADE_SIG_<ID>_NAME` / `_DESC` 三语（列序 `keys,zh,en,ja`）
4. 效果落点按 §4 表选机制：能直改 params 就直改（AI 经 `effective_*()` 自动感知，见 CLAUDE.md 机动 buff 规范）；要新事件就先看 `skill_hooks.gd` 有没有现成钩子
5. `test_sig_skills.gd` 加断言（表约定断言会自动覆盖条数，**记得把 §A 的 `sig_count == 40` 改掉**）
6. 收尾：`--bench=all` → `dump_skill_table.py` → `verify_doc_anchors.py` → 回填 spec §7 锚点 + `code-index.md`

---

## 8.5 后续小批：玩家热诱弹分档（2026-07-23）

同一工作树里还有一个紧随其后的小批（用户发现"有玩家机 32 发热诱弹"）：
**41 机热诱弹按 tier 分档 2/3/4/5/6 + 与敌用 `default_flare` 彻底解耦**。
新增 `resources/player/flare_t1~t5.tres`，41 份基参重指向，摘除 3 处 `flare_override`。
详见 `docs/changelogs/2026-07-23-player-flare-tiers.md` 与 spec `player-aircraft-power-curve §2.6`。
与本批的交集：`manual_dodge`(+6 flare) 的加成语义被写进"新机基数 + Σ加成"契约并加了断言。

---

## 9. 相关文档入口

- **权威 spec**：`docs/specs/systems/aircraft-signature-skills.md`（数值全表 / 歧义裁定 / 锚点）
- 本批 changelog：`docs/changelogs/2026-07-22-aircraft-signature-skills.md`
- 上游依赖 spec：`skills-720-rework`（归属词汇 v6 / ACE_FIELD_STATS 铁律）、`evolution-attribute-gates`（三轴 / 里程碑 / 玩家层重放）、`aircraft-evolution-tree`（41 机 id 与门槛）
- 现状全表：`docs/reference/skill-table.md`（144 条，自动生成）
- 行号指针：`docs/reference/code-index.md` → "722 批 机体签名技能" 段
- 同日另两批：`docs/HANDOFF-2026-07-22.md`（全局平衡）、`docs/changelogs/2026-07-22-boss-hunter-handover.md`
