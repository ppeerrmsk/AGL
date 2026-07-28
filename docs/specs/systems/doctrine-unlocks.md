---
id: doctrine-unlocks
kind: system
status: in-progress
schema_version: 1
spec_version: 3
owner: 用户（2026-07-27 拍板：移除槽位配件系统，只保留 doctrine 词条解锁件并搬进功勋商店）
depends_on: [career-shop, skills-720-rework, aircraft-signature-skills]
reconstruction_complete: false
---

# 战术学说解锁（Doctrine Unlocks）与槽位配件系统退役

> 局外功勋只买"**我这局能抽到什么牌**"，不买"**我这局直接变强多少**"。
> 6 张永久学说许可决定 145 条 in-run 技能里哪 45 条进池；出击前不再有装备界面。

## 0. 裁决记录（2026-07-27 用户拍板）

| # | 议题 | 裁决 |
|---|---|---|
| **D1** | 12 件数值配件整体删除，不做补偿性数值上调 | ✅ 删且不补偿 |
| **D2** | 已购数值件的功勋是否退还 | ❌ **不退**（用户："单机游戏所以不退也没关系"）—— 迁移只搬 doctrine 拥有态，数值件直接丢弃 |
| **D3** | `sig_*` 机体签名技豁免 doctrine 二次门控 | ✅ 豁免 |
| **D4** | 定价公式 `price = 100 × 门控技能数 + 300`（§2.2 表），全买齐 6500 功勋（v3 骑士补技后 6400→6500） | ✅ 草案通过，playtest 校准 |
| **D5** | 删付费刷新后不补新的功勋 sink | ✅ 本批不补，缺了另起 spec |

## 1. 设计意图（Why）

### 1.1 体验目标

- **局外买的是"可能性"，不是"数值"**。玩家攒功勋的动机应该是"我想开一条新流派"（解锁嗜血 → 这局能围绕击杀回血堆一整套），而不是"我的机炮伤害 +12%"。
- **出击路径变短**。选机 → 直接起飞。删掉一整个装备界面（选机与战斗之间那道 3 分钟的摆弄槽位的关卡）。
- **学说的存在感来自局内**，不是局外界面。买了嗜血，感受在于"升级弹窗开始出现嗜血牌"，而不是"机库里多了一个亮着的图标"。

### 1.2 Litmus 自检（引 DESIGN_PHILOSOPHY）

| 条目 | 本 spec 如何满足 |
|---|---|
| **效果即反馈，不加 HUD 中介** | doctrine 没有任何局内 UI；它的唯一表现就是升级卡池里多了一批牌 |
| **单杠杆** | 每张 doctrine 只有一个字段有意义：`unlocks_keywords`。没有 tier、没有槽位、没有装备/卸载状态机 |
| **二阶机制默认不做** | 槽位预算 / 占格 1-2-3 / 随机货架 / 付费刷新 —— 四层二阶机制全删 |
| **反模式：花钱直接买属性** | 12 件数值件正踩此条，本批清除 |
| **设计往简单收敛** | `EquipmentPart` 资源类（30+ 个 @export 字段）与 `resources/equipment/` 整个目录退役，doctrine 降级为一张常量表 |

### 1.3 反模式规避

- ❌ **不做**"学说等级"（嗜血 Lv1/Lv2/Lv3）—— 买了就是买了，布尔值
- ❌ **不做**"学说互斥"（只能同时装 2 个）—— 那会把永久许可变回装备槽
- ❌ **不做** doctrine 影响局内数值 —— 它只改牌池，一个乘数都不给

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 六张学说

`unlocks_keywords` 是唯一有效字段。所有 doctrine 均为**永久拥有制**（无装备/卸载概念）。

| id | 名称 key | 解锁 keyword | 门控技能数 | 价格（D4 草案） |
|---|---|---|---|---|
| `doctrine_chivalry` | `EQUIPMENT_DOCTRINE_CHIVALRY_NAME` | `chivalry` | 5 | 800 |
| `doctrine_bloodlust` | `EQUIPMENT_DOCTRINE_BLOODLUST_NAME` | `bloodlust` | 7 | 1000 |
| `doctrine_fear` | `EQUIPMENT_DOCTRINE_FEAR_NAME` | `fear` | 7 | 1000 |
| `doctrine_overload` | `EQUIPMENT_DOCTRINE_OVERLOAD_NAME` | `overload` | 8 | 1100 |
| `doctrine_jam` | `EQUIPMENT_DOCTRINE_JAM_NAME` | `jam` | 9 | 1200 |
| `doctrine_stealth` | `EQUIPMENT_DOCTRINE_STEALTH_NAME` | `stealth` | 11 | 1400 |

**定价公式**：`price = 100 × 门控技能数 + 300`（取整到百位）。全 6 张合计 **6500**。

### 2.2 三语文案（现有，本批不改）

| key | zh | en | ja |
|---|---|---|---|
| `EQUIPMENT_DOCTRINE_CHIVALRY_NAME` | 战术：骑士 | Tactic: Chivalry | 戦術：騎士 |
| `EQUIPMENT_DOCTRINE_CHIVALRY_DESC` | 解锁【对头触发】系 in-run 升级 | Unlocks head-on trigger in-run upgrades | 正面トリガー系を解禁 |
| `EQUIPMENT_DOCTRINE_CHIVALRY_FLAVOR` | 你在空战中带了一挺骑枪来。 | You brought a lance to a dogfight. | 空中戦にランスを持ち込んできたな。 |
| `EQUIPMENT_DOCTRINE_BLOODLUST_NAME` | 战术：嗜血 | Tactic: Bloodlust | 戦術：血戦 |
| `EQUIPMENT_DOCTRINE_BLOODLUST_DESC` | 解锁【嗜血】系 in-run 升级 | Unlocks bloodlust in-run upgrades | 血戦系を解禁 |
| `EQUIPMENT_DOCTRINE_BLOODLUST_FLAVOR` | 每一击都喂养下一击。 | Each kill feeds the next. | 撃つたびに次が育つ。 |
| `EQUIPMENT_DOCTRINE_FEAR_NAME` | 战术：恐惧 | Tactic: Fear | 戦術：恐怖 |
| `EQUIPMENT_DOCTRINE_FEAR_DESC` | 解锁【恐惧】系 in-run 升级 | Unlocks fear in-run upgrades | 恐怖系を解禁 |
| `EQUIPMENT_DOCTRINE_FEAR_FLAVOR` | 植入动摇。 | Sow wavering. | 動揺を植える。 |
| `EQUIPMENT_DOCTRINE_OVERLOAD_NAME` | 战术：超载 | Tactic: Overload | 戦術：オーバーロード |
| `EQUIPMENT_DOCTRINE_OVERLOAD_DESC` | 解锁【超载】系 in-run 升级 | Unlocks overload in-run upgrades | オーバーロード系を解禁 |
| `EQUIPMENT_DOCTRINE_OVERLOAD_FLAVOR` | 最大化杀伤。 | Maximize the lethality. | 殺傷を最大化。 |
| `EQUIPMENT_DOCTRINE_JAM_NAME` | 战术：干扰 | Tactic: Jamming | 戦術：妨害 |
| `EQUIPMENT_DOCTRINE_JAM_DESC` | 解锁【干扰】系 in-run 升级 | Unlocks jamming in-run upgrades | 妨害系を解禁 |
| `EQUIPMENT_DOCTRINE_JAM_FLAVOR` | 阻断反馈。 | Sever feedback. | 反応を断つ。 |
| `EQUIPMENT_DOCTRINE_STEALTH_NAME` | 战术：隐身 | Tactic: Stealth | 戦術：ステルス |
| `EQUIPMENT_DOCTRINE_STEALTH_DESC` | 解锁【隐身】系 in-run 升级 | Unlocks stealth in-run upgrades | ステルス系を解禁 |
| `EQUIPMENT_DOCTRINE_STEALTH_FLAVOR` | 别眨眼。 | Don't blink. | まばたきしないで。 |

### 2.3 门控覆盖清单（145 条技能里的 45 条）

**权威表**。技能的 `keywords` 数组里带下列词 → 未拥有对应 doctrine 时不进任何随机池。
标注惯例：`head_on` 是**触发词**（不门控），家族词（chivalry/fear/jam）才受门控——
对头系技能必须双词齐全，缺家族词 = 无证进池（headon_xp 曾踩此坑，playtest 2026-07-28 用户上报修复）。

| keyword | 技能 id |
|---|---|
| `chivalry`（5） | `low_alt_gun_dodge` · `skill_head_on_perma_hp` · `skill_lowest_alt_kill_invul` · `head_on_gun_dodge` · `headon_xp` |
| `bloodlust`（7） | `skill_kill_bloodlust` · `skill_damaged_bloodlust` · `overload_to_bloodlust` · `bloodlust_armor_mobility` · `full_hp_kill_perma_hp` · `squad_revenge` · `qmaam_bloodlust` |
| `fear`（7） | `fear_squad_spread` · `fear_chills` · `skill_head_on_aoe_fear` · `skill_gun_kill_fear` · `skill_kill_status_heal` · `fear_on_lock` · **`sig_su27`** |
| `overload`（8） | `cloud_overload` · `skill_evade_missile_overload` · `skill_flare_overload` · `overload_duration_4x` · `overload_extended_ammo` · `overload_to_bloodlust` · `jam_self_overload` · `assassin_revenge` |
| `jam`（9） | `jam_aura` · `skill_flare_aoe_jam` · `skill_gun_kill_flare_drop` · `skill_missile_hit_aoe_jam` · `skill_torpedo_aoe_jam` · `head_on_jam` · `jam_self_overload` · **`sig_rafale`** · **`sig_x13`** |
| `stealth`（11） | `vapor_dodge` · `ecm_pod` · `evasion_stealth` · `alt_change_stealth` · `missile_cd_stealth` · **`sig_a6e`** · **`sig_f22`** · **`sig_yf23`** · **`sig_mig41`** · **`sig_x09`** · **`sig_x77`** |

- keyword 槽位合计 47，**去重后 45 条技能**（`overload_to_bloodlust` 与 `jam_self_overload` 各占两个 keyword —— 二者**任一** doctrine 缺失即被门控，不是"任一拥有即放行"）
- **粗体 9 条为 `sig_*` 机体签名技**，见 D3
- `evasion_stealth` 与 `fear_on_lock` 同时是 `evolved: true`（战区奖励池），见 §3.3

### 2.4 退役清单

| 退役物 | 数量 | 处置 |
|---|---|---|
| 数值配件 `.tres` | 12（gun/missile/radar/ecm 各 T1-T3） | 删除资源文件 |
| `EquipmentPart` 资源类 | 1 | 删除（doctrine 改用常量表，不再需要 Resource） |
| 出击前机库场景 + 脚本 | 1 场景 + 1 脚本（约 560 行） | 删除；选机直连 `building_preloader` |
| `LoadoutLedger` AutoLoad | 1 | 删除；`is_upgrade_gated` / `is_keyword_unlocked` 迁入 `MetaShop` |
| 槽位预算 | `PlayableAircraft.slot_budget` @export | 删除字段（现无任何 `.tres` 写入该值，删除不会导致资源加载报错） |
| 随机货架 + 付费刷新 | `_roll_shop` / `SHOP_TIER_QUOTA` / `SHOP_REFRESH_COST` | 删除 |
| i18n key | 24 条 `EQUIPMENT_*_T{1,2,3}_{NAME,DESC}` + 21 条机库专用 `LOADOUT_*` | 删除 |
| i18n key（**保留**） | `LOADOUT_BTN_BUY_FMT` / `LOADOUT_BTN_OWNED` / `LOADOUT_BTN_NO_FUNDS` / `LOADOUT_BACK` | 生涯商店界面在用，原名保留（不改名以免制造无谓 diff） |
| i18n key（**保留**） | `LOADOUT_KEYWORD_*` ×6 · `LOADOUT_BADGE_DOCTRINE` · `LOADOUT_DOCTRINE_UNLOCKS_FMT` | doctrine 卡片渲染在用 |

## 3. 行为与公式（How）

### 3.1 门控判定

```
is_keyword_unlocked(kw):
    if kw not in GATED_KEYWORDS:        # 6 词之外一律放行
        return true
    return 已购集合中存在某商品，其 unlocks_keywords 含 kw

is_upgrade_gated(upgrade):
    if D3 采纳 and upgrade.id 以 "sig_" 开头:
        return false                     # 机体签名技豁免二次门控
    for k in upgrade.keywords:
        if k in GATED_KEYWORDS and not is_keyword_unlocked(k):
            return true                  # 任一缺失即门控（AND 语义）
    return false
```

- 判定看**拥有**，不看装备（永久许可，无装备态）
- **非正式局 fail-open**：bench（`--bench=*`）与 boss debug 局一律视为全 doctrine 已拥有，避免自动化测试被局外存档影响（沿 career-shop §3.3 铁律）

### 3.2 商店上架顺序（渐进解锁，沿用现行规则）

| 阶段 | 上架商品 |
|---|---|
| 初始 | `doctrine_bloodlust` · `doctrine_chivalry`（STARTER 两张） |
| 两张 STARTER 均已购后 | 追加 `doctrine_fear` · `doctrine_jam` · `doctrine_stealth` · `doctrine_overload` |

未上架时按 MetaShop 现行三态渲染：灰条 + 描述位显示上架条件句（新增 i18n key，见 §6 阶段 3）。
已购商品保留在列表中显示"已拥有"（与 MetaShop 现有商品一致，**不**像旧机库那样购入后消失 —— 玩家需要能回看自己解锁了什么）。

### 3.3 门控消费点（**必须全覆盖**）

现状有一个漏点，本批一并修。

| 消费点 | 现状 | 目标 |
|---|---|---|
| 升级三选一随机池 | ✅ 已门控 | 不变（改调 MetaShop） |
| 每 3 级三轴卡池 | ✅ 已门控 | 不变（改调 MetaShop） |
| **战区奖励"次世代技术"池** | ❌ **未门控** —— 活路径是 NEXT_GEN 候选过滤（按稀有度/机型/stacks 筛，但不查 doctrine），池中 `evasion_stealth`(stealth) 与 `fear_on_lock`(fear) 可无证获得。（初稿误指旧 evolved 池——那是零调用死代码，本批顺带删除） | ✅ 在 NEXT_GEN 候选过滤处补门控 |
| bench 自动抽技能 | ❌ 未门控 | 保持不门控（压测专用，且 §3.1 fail-open 语义一致） |

### 3.4 存档迁移（一次性）

老存档 `user://loadout.cfg` 的 `[owned] parts` 数组：

```
对每个已购 id：
    若 id 以 "doctrine_" 开头  → 写入 meta_shop.cfg 的已购集合
    否则（12 件数值件）         → 直接丢弃（D2：不退款）
迁移完成后删除 user://loadout.cfg
```

- 迁移只跑一次（以 `loadout.cfg` 是否存在为幂等标志）
- 主菜单"删档"须同时清 `meta_shop.cfg`（`MetaShop.debug_reset` 已覆盖）；`LoadoutLedger.debug_reset` 调用点随 autoload 一起删

### 3.5 出击流程变更

| | 现状 | 目标 |
|---|---|---|
| 正常局 | 选机 → **机库** → building_preloader → survivor_mode | 选机 → building_preloader → survivor_mode |
| boss debug 局 | 选机 → building_preloader（已跳过机库） | 不变 |
| 主菜单 | 主菜单 → 生涯商店（3 件商品） | 主菜单 → 生涯商店（3 件 + 6 张学说，学说排在**上方**独立分区） |

## 4. 结构与组成（Structure）

```
MeritLedger          货币（不变）
CareerArchive        战绩（不变，doctrine 不读它）
MetaShop             局外购买态 —— 本批扩张：
  ├─ CATALOG         3 件生涯商品（不变）
  ├─ DOCTRINE        6 张学说常量表（新增；id / price / i18n key / unlocks_keywords）
  ├─ GATED_KEYWORDS  6 词（从 LoadoutLedger 迁入）
  ├─ is_upgrade_gated / is_keyword_unlocked   （从 LoadoutLedger 迁入）
  └─ meta_shop.cfg   已购集合（学说与生涯商品同一个集合，id 不冲突）

MetaShopUI           两个分区：【战术学说】+【生涯商品】
survivor_mode        3 处门控消费点（升级池 / 三轴池 / 战区奖励池）
```

**为什么 doctrine 不再用 `.tres`**：MetaShop 的既有铁律是"刻意不用 EquipmentPart/.tres —— 商品效果不在 AircraftParams 上，塞进装备目录会被随机货架卷入且 `apply_to()` 够不着消费点"。doctrine 恰好完全符合这条描述：它有效字段只有 4 个（id / 价格 / i18n key / keyword），效果消费点在升级池而非飞机，所以降级为常量表是本来就正确的形态。随机货架消失后，`.tres` 的最后一点存在理由也没了。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 零存档新玩家：主菜单 → 生涯商店，学说区只见嗜血 + 骑士两张，另 4 张灰条显示上架条件
- [ ] 买下嗜血 → 进局升级，`skill_kill_bloodlust` 等 7 条开始出现在三选一 / 三轴卡池
- [ ] 未买隐身：战区奖励池**不再**出现 `evasion_stealth`；未买恐惧：不再出现 `fear_on_lock`（§3.3 漏点已修）
- [ ] 买齐嗜血 + 骑士 → 返回商店，另 4 张转为可购状态
- [ ] D3 若采纳：未买隐身但驾驶 F-22，`sig_f22` 仍可正常抽到
- [ ] 选机后**直接**进入战斗加载，中途无机库界面
- [ ] 老存档（`loadout.cfg` 里有 doctrine + 数值件）启动一次后：doctrine 在商店显示"已拥有"，数值件静默丢弃（D2 不退款），`loadout.cfg` 已删除
- [ ] `--bench=*` 全项绿（回归门）；bench 局无视局外存档，全 doctrine 视为已拥有
- [ ] 性能：无新增 `_process` / `_draw`，本批仅减不加（见 performance-guidelines）
- [ ] i18n：`EQUIPMENT_*_T{1,2,3}_*` 与机库专用 `LOADOUT_*` 已删净，全库 `grep` 无残留引用；新增上架条件句三语齐全
- [ ] 已知 seam：本批删除 `SurvivorPlayableSetup` 的 `apply_to_aircraft` 调用，确认 `evolution_system` 换机链路（注释提到"充能/CD 由 apply 内 LoadoutLedger 处理"）不因此丢失重置行为

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 定稿
- [x] 用户回答 D1~D5（2026-07-27 拍板，见 §0）

### 阶段 1 — MetaShop 承接门控（先加后删，保证任何一步都可运行）
- [x] `MetaShop` 加 `DOCTRINES` 常量表 + `GATED_KEYWORDS` + `is_keyword_unlocked` / `is_upgrade_gated`（含 D3 的 `sig_*` 豁免与 §3.1 fail-open）
- [x] `MetaShop` 加学说购买路径（`buy` 泛化）+ 渐进上架判定 `doctrine_listed_ok`
- [x] 存档迁移 §3.4 `migrate_legacy_loadout`（幂等，_ready 自动触发）
- [x] 无头单测（并入 `--bench=meta_shop`，21→47 断言）：门控 AND 语义 / `sig_*` 豁免 / 渐进上架 / 定价表 / 迁移幂等（doctrine 搬运、数值件丢弃、legacy 文件删除、落盘）

### 阶段 2 — 消费点切换
- [x] `survivor_mode` 两处 `LoadoutLedger.is_upgrade_gated` → `MetaShop.is_upgrade_gated`
- [x] 战区奖励 NEXT_GEN 候选过滤补门控（§3.3 漏点；顺带删除零调用死代码 `_build_reward_pool`）
- [x] 跑回归门确认技能池行为一致（40 项 PASS）

### 阶段 3 — 商店 UI
- [x] `MetaShopUI` 拆两个分区：【战术学说】在上、【生涯商品】在下
- [x] 学说条目渲染 flavor 文 + "▸ 解锁【xx】词条的技能"（复用旧机库 doctrine 卡片样式）
- [x] 新增 i18n key（三语）：`METASHOP_SECTION_ITEMS` / `METASHOP_LOCKED_HINT_DOCTRINE`

### 阶段 4 — 拆除
- [x] 删 `scenes/survivor_loadout.tscn` + `scripts/survivor/survivor_loadout.gd`
- [x] `survivor_select` 出击直连 `building_preloader`（boss debug 与正常局两条路径合一）
- [x] 删 `LoadoutLedger` autoload（`project.godot`）+ 脚本 + `main_menu` 的 `debug_reset` 调用
- [x] 删 `EquipmentPart` 类 + `resources/equipment/` 全 18 个 `.tres`
- [x] 删 `SurvivorPlayableSetup` 的 `apply_to_aircraft` 调用；核对 `evolution_system` 换机重置（载弹/热诱弹重置本就在 evolution_system 自身逻辑内，LoadoutLedger 只管配件乘数，删除无损）
- [x] 删 `PlayableAircraft.slot_budget`（无 `.tres` 写入该字段，删除无资源加载风险）
- [x] 清 i18n 死 key（45 条：21 机库 LOADOUT_* + 24 数值件 EQUIPMENT_*；顺带清了 CSV 3 行历史重复）

### 阶段 5 — 收尾
- [x] `verify_player_ref_holders.py` ✓ + `verify_doc_anchors.py` ✓（顺带回填 39 个腐烂锚点，含上批遗留）
- [x] 更新 `script-index.md` / `code-index.md` / `repo-layout.md` / `skill-implementation-index.md`（门控入口改指 MetaShop）
- [x] 更新 `career-shop.md` §分工行（LoadoutLedger 已退役）
- [x] `_INDEX.md` 行更新；填 §7 锚点；写 §8
- [ ] playtest：定价手感（D4 校准）→ 通过后 status → `done`

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 学说表 + 门控判定 + legacy 迁移 | `scripts/meta/meta_shop.gd`（`DOCTRINES` / `is_upgrade_gated` / `migrate_legacy_loadout`） |
| 商店界面（两分区） | `scripts/meta/meta_shop_ui.gd`（`_build_doctrine_tile`） |
| 门控消费点 | `scripts/survivor/survivor_mode.gd`（`_roll_upgrade_choices` / `_roll_axis_cards`）· `scripts/survivor/zone_data.gd`（`_nextgen_candidates`） |
| 出击直连 | `scripts/survivor/survivor_select.gd`（`_on_aircraft_selected`） |
| 技能 keywords 源 | `scripts/survivor/survivor_data.gd`（`UPGRADES`） |
| 无头单测 | `scripts/tests/test_meta_shop.gd`（bench key `meta_shop`，47 断言） |
| reference 索引行 | script-index.md `meta/meta_shop*` 三行 / skill-implementation-index.md §1 `keywords` 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-27 | 1 | 初稿。用户拍板移除槽位配件系统，doctrine 搬进主菜单功勋商店。附带查明并记录：战区奖励池门控漏点（2 条技能）、9 条 `sig_*` 签名技被 doctrine 二次门控的冲突 |
| 2026-07-28 | 2 | D1~D5 裁决入档（D2 改不退款）；漏点定位修正为 NEXT_GEN 候选过滤；§6 阶段 0~5 全落地（47 断言 + 回归门 40 项 PASS），余 playtest 定价校准 |
| 2026-07-28 | 3 | playtest 首个战果：用户未购骑士学说仍抽到 `headon_xp`（骑士心脏·历练）——720 批漏标家族词 `chivalry`（只带触发词 `head_on`）。补标后 chivalry 4→5 张、定价 700→800、全买 6400→6500；§2.3 补"触发词≠家族词"标注惯例 |
