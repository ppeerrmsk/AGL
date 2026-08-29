---
id: career-shop
kind: system
status: in-progress
schema_version: 1
spec_version: 9
owner: 用户（设计）+ Claude（起草）
depends_on: [career-archive]
reconstruction_complete: true
---

# 起手机解锁与生涯商店（Career Shop）

> 生涯档案提供局外成长：选机页保留既有 F-15 / F-14 / A-6E / Mirage III 四卡及原解锁条件，
> 另追加 MiG-21F-13 / F-104C / J 35F / EA-6B 四卡；新四卡各通过一项生涯商店采购案永久解锁。
> 战区 F-86 / A-10 与王牌来袭时的 F-15 友军支援都必须分别花功勋取得永久授权。
> 机场防空网也属于永久战场支援：购入后，每局解放机场都自动追加一座一次性友军 SAM。

## 0. 用户规则与落地解释（✅ 2026-07-28 用户批准；价格仍为草案待 playtest 校准）

| 用户规则 | 本 spec 落地 | 说明 |
|---|---|---|
| 玩家初始只有 F-15 | 起手四选一保留四张卡位，但 F-14 / A-6E / 幻影 III 变为**占位锁定态**：不加载档案、**不显示任何机体数据**（名字 ???、无武器/数值/描述），只显示解锁条件句 | 2026-07-27 用户改版：未拥有的机型不做数据预览，条件即全部信息（制造追逐目标）；卡位保留不隐藏 |
| 第一次击败航母 BOSS 通关 → 解锁 F-14 | F-14 解锁条件 = 档案 `boss.defeats["CARRIER_STRIKE_GROUP"] ≥ 1` | 实时读 CareerArchive 推导，不另存解锁位 |
| 击败 30 个地面单位 → 解锁 A-6 | A-6E 解锁条件 = 档案 `kills.ground_total ≥ 30` | A-6E 已实装且本就是 T1 攻击线起手；卡片显示进度 (x/30) |
| 可以花钱购买初始的幻影飞机 | 幻影 III = 生涯商店**恒上架**商品，购入后起手可选 | "钱"= 功勋；无解锁条件，商店开门就卖 |
| 第一次机场停靠 → 解锁商品"每次停靠得僚机" | 商品 `dock_wingman` 上架条件 = `runs.dockings["airfield"] ≥ 1`；**现有"每次停靠送 1 架僚机"机制改为购入后才生效** | "机场"停靠才上架；商品效果覆盖机场+航母停靠（与现机制一致）。未购入时停靠的回血/进化/航母扣次/机场失效照旧，只是不送僚机 |
| 第一次撤离 → 解锁商品"行动时间 +30s" | 商品 `op_time_30s` 上架条件 = `runs.retreats ≥ 1`；效果 = 战区阶段总时长 600s → **630s** | "撤离"沿 career-archive §0 定义 = 出界撤退菜单结算 |
| （通用） | 商品均为**一次性买断、不可叠加**（v1）；解锁/购买只在正式局生效，bench / boss debug 局一律视为全解锁（保回归确定性 + debug 全谱选机铁律） | 要做可叠加（+60s、送 2 架）再修订 |
| 把机场 SAM 做进功勋商店，不是技能 | 删除局内 `airfield_sam_network` 升级；新增恒上架商品 `support_airfield_sam`，购入后每局每座解放机场自动追加 SAM×1 | 价格跟战场支援页其它授权统一为 3000；基础 AA×2、战损不重生与敌占编成不变 |
| 第四技能槽做成全局升级 | 新增恒上架商品 `global_airframe_affinity`，3000 功勋；购入后自然升级有 15% 概率追加当前机体身份轴的普通第四卡 | 详细概率、轴选择与抽卡规则由 `airframe-affinity-fourth-card` 统一定义 |

## 1. 设计意图（Why）

- **体验目标**：
  1. 给生涯档案一个**立刻可感的用途**：打赢航母解锁 F-14、炸够地面解锁 A-6E——每条解锁都是"玩法行为 → 内容奖励"的直白因果，构成最早的全局成长循环。
  2. 功勋此前只在机库改装消费（单局收入足以买空全店），生涯商店给它**长期汇**：飞机与持久商品的价格以"局"为单位计，功勋从此值得攒。
  3. 起手收紧让新玩家第一局聚焦 F-15 基底（RTS 化转向的基底机），四条线（制空/远程/攻击/电战）随生涯逐步展开，而不是第一局就面对四选一。
- **Litmus 自检**（引 DESIGN_PHILOSOPHY）：
  - **#9 局外成长节制**：所有解锁条件都在正常游玩 1~3 局内自然达成（首败航母 / 30 地面击杀 / 首次停靠·撤离）；无数值 buff 商品——僚机与时长都是**内容/节奏**商品；不做 30+ 局进度墙。
  - **#3 信息察觉**：锁定卡只显示解锁条件与进度（机体数据隐藏为 ???——条件本身就是全部信息，数据留给解锁瞬间当奖励揭晓）；商店未上架商品灰条显示上架条件；购买立即反馈（按钮三态 + 功勋徽章跳变）。
  - **待用户校准注意**：把"停靠送僚机"从默认改为购买后生效，是**削弱新档案的默认体验**（airfield-liberation-zones 的"降落=回血/进化/僚机"三合一少了一环）。这是用户明确要的门控，记录在案。
- **反模式规避**：不做可叠加数值商品；不把非属性商品塞进 EquipmentPart/装备目录（会被随机货架卷入）；boss debug 链路不受门控（debug 全谱选机铁律）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 起手机解锁表（选机界面八卡）

| 卡位 | id | 解锁判定（实时推导，不落盘） | 锁定时卡片按钮文本 |
|---|---|---|---|
| 1 | `f15` | **恒解锁** | — |
| 2 | `f14` | `CareerArchive.get_boss_defeats("CARRIER_STRIKE_GROUP") ≥ 1` | 「击败 Ladon 战斗群 解锁」 |
| 3 | `a6e` | `CareerArchive.get_ground_kills() ≥ 30` | 「摧毁 30 个地面单位解锁（x/30）」 |
| 4 | `mirage3` | `MetaShop.is_owned("mirage3_starter")` | 「生涯商店有售」 |
| 5 | `mig21f13` | `owned["aircraft_mig21f13"]` | 生涯商店采购后可用 |
| 6 | `f104c` | `owned["aircraft_f104c"]` | 生涯商店采购后可用 |
| 7 | `j35f` | `owned["aircraft_j35f"]` | 生涯商店采购后可用 |
| 8 | `ea6b` | `owned["aircraft_ea6b"]` | 生涯商店采购后可用 |

- 锁定形态 = 选机卡 **locked 占位**分支（**不加载档案**：名字 ???、TAG 未解锁、无武器/数值/描述），按钮文本 = 上表条件句（v1 曾用 dev_locked 全信息形态，2026-07-27 用户裁定改占位）。
- **debug 分流**：`boss_debug_mode` 使用独立 T4 参考名单；正常选机页始终显示八卡。
- 生存模式缺省档案兜底 = F-15（与"恒解锁"一致，无需改动）。

### 2.2 生涯商店基础商品目录（目录写死在代码常量）

> 2026-08-01 扩展并随 43 机树同步：商店改为四分页，当前有 43 条机体专属许可与 `support_awacs`。
> 2026-08-01 再扩展：战场支援页新增两项独立战区支援授权；机体专属商品仍以 `aircraft-signature-progression` 为权威源。

| 商品 id | 名称 | 价格（功勋） | 上架条件（读档案） | 效果 |
|---|---|---|---|---|
| `mirage3_starter` | 幻影 III 采购案 | **2000** | 恒上架 | 幻影 III 加入起手可选 |
| `aircraft_mig21f13` | MiG-21F-13 采购案 | **1000** | 恒上架 | MiG-21F-13 永久加入可选起手机 |
| `aircraft_f104c` | F-104C 采购案 | **1000** | 恒上架 | F-104C 永久加入可选起手机 |
| `aircraft_j35f` | J 35F 采购案 | **1000** | 恒上架 | J 35F 永久加入可选起手机 |
| `aircraft_ea6b` | EA-6B 采购案 | **1000** | 恒上架 | EA-6B 永久加入可选起手机 |
| `dock_wingman` | 停靠补给僚机 | **3000** | `dockings["airfield"] ≥ 1` | 每次停靠（机场或航母）送 1 架同型僚机（= 门控现有机制） |
| `op_time_30s` | 行动时间延长 | **2500** | `retreats ≥ 1` | 战区阶段总时长 600s → 630s（永久） |
| `global_airframe_affinity` | 机体战术适配 | **3000** | 恒上架 | 自然升级有 15% 概率追加当前机体身份轴的普通第四技能卡 |
| `support_zone_air` | 战区制空支援协定 | **3000** | 恒上架 | 每局首次对空战区 ACTIVE 后生成 2～4 架 F-86 友军 |
| `support_zone_ground` | 战区对地支援协定 | **3000** | 恒上架 | 每局首次非机场对地战区 ACTIVE 后生成 2 架 A-10 友军 |
| `support_ace_f15` | 王牌截击支援协定 | **3000** | 恒上架 | 每局首次非 BOSS 敌军王牌事件生成 2 架 F-15；事件终态后撤离 |
| `support_airfield_sam` | 机场防空网授权 | **3000** | 恒上架 | 每局每座解放机场在 AA×2 后追加一次性 SAM×1 |

- **价格依据**：单局功勋收入 ≈ 2,500~7,500（Lv15~25 结算，XP 1:1 折算；阵亡 ×0.8）。三件定价各 ≈ 半局~一局，合计 7,500 ≈ 一局上好收入——首周目内全部购齐，符合 #9 节制。**数值为草案，playtest 后校准**；现有机库件（80~400）明显低估，本批不动，留经济平衡批统一处理。
- 商品不可叠加、不可退款；`owned` 为 id → true 的集合。
- 未上架商品在商店里显示**灰条 + 上架条件文本**（不隐藏）。

### 2.3 持久化 schema（新账本 MetaShop，`user://meta_shop.cfg`）

| section | key | 类型 | 缺省 | 说明 |
|---|---|---|---|---|
| `shop` | `owned` | Dictionary {String: bool} | {} | 已购商品集合 |

上架条件与飞机解锁**不落盘**——全部实时从 CareerArchive 推导（档案即真源，删档案 = 解锁同步回退）。

### 2.4 i18n 新增 key（三语）

| key | zh | en | ja |
|---|---|---|---|
| `MENU_META_SHOP_NAME` | 生涯商店 | Career Shop | キャリアショップ |
| `MENU_META_SHOP_DESC` | 用功勋购买飞机与持久强化 | Spend merit on aircraft and permanent perks | 功績で機体と永続強化を購入 |
| `METASHOP_TITLE` | ── 生涯商店 ── | ── CAREER SHOP ── | ── キャリアショップ ── |
| `METASHOP_ITEM_MIRAGE3_NAME` | 幻影 III 采购案 | Mirage III Procurement | ミラージュ III 調達計画 |
| `METASHOP_ITEM_MIRAGE3_DESC` | 幻影 III 加入起手机名单（电战线起点） | Adds Mirage III to the starting roster (EW line) | ミラージュ III が初期機体に追加（電子戦系統） |
| `METASHOP_ITEM_DOCK_WINGMAN_NAME` | 停靠补给僚机 | Docking Wingman Resupply | 着艦補給ウィングマン |
| `METASHOP_ITEM_DOCK_WINGMAN_DESC` | 每次在机场或航母停靠，补给 1 架同型僚机入队 | Each airfield or carrier docking grants +1 wingman | 飛行場・空母に着くたび僚機 1 機を補充 |
| `METASHOP_ITEM_OP_TIME_NAME` | 行动时间延长 | Extended Operation Time | 作戦時間延長 |
| `METASHOP_ITEM_OP_TIME_DESC` | 战区阶段总时长 +30 秒 | Warzone phase duration +30 seconds | 戦域フェーズ +30 秒 |
| `METASHOP_ITEM_ZONE_AIR_SUPPORT_NAME` | 战区制空支援协定 | Warzone Air Support Accord | 戦域制空支援協定 |
| `METASHOP_ITEM_ZONE_AIR_SUPPORT_DESC` | 每局首次对空战区激活后派遣 2～4 架 F-86 友军 | Dispatches 2–4 allied F-86s to the first air mission each run | 各出撃で最初の対空戦域開始後に友軍 F-86 を 2～4 機派遣 |
| `METASHOP_ITEM_ZONE_GROUND_SUPPORT_NAME` | 战区对地支援协定 | Warzone Ground Support Accord | 戦域対地支援協定 |
| `METASHOP_ITEM_ZONE_GROUND_SUPPORT_DESC` | 每局首次非机场清剿战区激活后派遣 2 架 A-10 | Dispatches two allied A-10s to the first non-airfield ground mission each run | 各出撃で最初の飛行場以外の地上掃討戦域に友軍 A-10 を 2 機派遣 |
| `METASHOP_ITEM_ACE_F15_SUPPORT_NAME` | 王牌截击支援协定 | Ace Intercept Support Accord | エース迎撃支援協定 |
| `METASHOP_ITEM_ACE_F15_SUPPORT_DESC` | 每局首次敌军王牌增援登场时派遣 2 架 F-15 | Dispatches two allied F-15s against the first enemy ace reinforcement each run | 各出撃で最初の敵エース増援に友軍 F-15 を2機派遣 |
| `METASHOP_ITEM_AIRFIELD_SAM_NAME` | 机场防空网授权 | Airfield SAM Network Authorization | 飛行場SAM網許可 |
| `METASHOP_ITEM_AIRFIELD_SAM_DESC` | 每次解放机场时，在友军 AA×2 之外追加 1 座一次性 SAM | Each liberated airfield deploys one single-use SAM in addition to two allied AA guns | 飛行場を解放するたび、友軍対空砲2基に加えて使い切りのSAM1基を配備 |
| `METASHOP_LOCKED_HINT_DOCK_WINGMAN` | 首次在机场停靠后上架 | Listed after your first airfield docking | 初の飛行場着陸後に入荷 |
| `METASHOP_LOCKED_HINT_OP_TIME` | 首次撤离行动后上架 | Listed after your first retreat | 初の撤退後に入荷 |
| `METASHOP_LISTED_TOAST` | 生涯商店新货上架 | New item listed in the Career Shop | キャリアショップに新商品入荷 |
| `UNLOCK_HINT_F14` | 击败 Ladon 战斗群 解锁 | Defeat the Ladon Strike Group to unlock | Ladon 打撃群を撃破で解禁 |
| `UNLOCK_HINT_A6E_FMT` | 摧毁 30 个地面单位解锁（%d/30） | Destroy 30 ground units to unlock (%d/30) | 地上ユニット 30 撃破で解禁（%d/30） |
| `UNLOCK_HINT_MIRAGE3` | 生涯商店有售 | Available in the Career Shop | キャリアショップで購入可能 |

按钮三态复用机库现成 key：`LOADOUT_BTN_BUY_FMT` / `LOADOUT_BTN_OWNED` / `LOADOUT_BTN_NO_FUNDS`。
停靠送僚机的入队提示沿用 `DOCK_WINGMAN_GRANTED`。

## 3. 行为与公式（How）

### 3.1 解锁与上架判定（全部纯推导）

```
aircraft_unlocked(id):
  f15      → true
  f14      → defeats["CARRIER_STRIKE_GROUP"] ≥ 1
  a6e      → ground_total ≥ 30
  mirage3  → owned["mirage3_starter"]
  mig21f13 → owned["aircraft_mig21f13"]
  f104c    → owned["aircraft_f104c"]
  j35f     → owned["aircraft_j35f"]
  ea6b     → owned["aircraft_ea6b"]
  其它/未列 → true（向后兼容：新增起手机默认不锁）

item_listed(id):
  五项机体采购 / support_awacs / support_zone_air / support_zone_ground / support_ace_f15 / support_airfield_sam → true
  dock_wingman    → dockings["airfield"] ≥ 1
  op_time_30s     → retreats ≥ 1

buy(id)：已拥有 → 拒绝；未上架 → 拒绝；MeritLedger.spend(price) 失败 → 拒绝；
        成功 → owned[id]=true，落盘，发 owned_changed 信号
```

### 3.2 商品效果消费点（各一处，正式局限定）

| 商品 | 消费点行为 |
|---|---|
| 五项机体采购 | 仅影响选机界面解锁判定（§2.1），局内无消费点 |
| `dock_wingman` | 停靠结算的"送 1 架僚机"段加门控：`正式局 且 未拥有 → 跳过赠送`；**非正式局（bench/boss debug）视为已拥有**，保旧行为与回归确定性 |
| `op_time_30s` | 战区阶段时长常量改为运行时变量：开局初始化时 `正式局 且 已拥有 → 时长 += 30`；HUD 倒计时/超时判定/补给时间税 clamp/F6 跳 BOSS 全部读同一变量，自动自洽 |
| `support_zone_air` | 战区任务执行器在本局首次 `air/squadron` ACTIVE 时查询；正式局未购不生成，非正式局 fail-open；出动后本局不再响应后续同类战区 |
| `support_zone_ground` | 战区任务执行器在本局首次非机场 `ground` ACTIVE 时查询；正式局未购不生成，非正式局 fail-open；与制空额度分账 |
| `support_ace_f15` | 本局首次非 BOSS 王牌轮换事件成功生成后查询；正式局未购不生成，非正式局 fail-open；生成 Hound-1/2 两架只对空 F-15，后续王牌事件不再派遣 |
| `support_airfield_sam` | 机场解放时创建驻防计划：正式局已购则 AA×2 后追加一次性 SAM×1，未购只有 AA×2；非正式局 fail-open |

- 首次**机场**停靠（dockings.airfield 0→1）且 `dock_wingman` 未拥有时，停靠结算额外弹一条
  `METASHOP_LISTED_TOAST`（信息察觉：告诉玩家商店上新了）。撤离触发的上架不弹（撤离直接进结算屏，无 toast 位），玩家回主菜单商店可见。

### 3.3 入档与调试铁律（沿 career-archive §3.5）

- 解锁判定读的是档案 → bench/boss debug 局不写档案，条件自然不会被污染。
- **门控自身在非正式局一律放行**（选机 debug 全解锁、dock_wingman 视为已拥有、op_time 不加成——加成读真实购买态但 bench 从不购买，行为恒 baseline）。
- MetaShop 不持有任何 Node 引用；主菜单删存档必须调 `MetaShop.debug_reset()`。

## 4. 结构与组成（Structure）

- **MetaShop**（新 AutoLoad，scripts/meta/，排 CareerArchive 之后）：商品目录常量 + 纯静态判定函数（可注入数值做无头单测）+ owned 持久化 + `buy()` + `owned_changed` 信号。**刻意不用 EquipmentPart/.tres**：这两件商品的效果不在 AircraftParams 上，塞进装备目录会被随机货架 `_roll_shop` 卷入、且 `apply_to()` 够不着消费点。
- **选机界面**：`PLAYABLE_LIST` 条目补 `id` 字段；新增 `_effective_list()` 在建卡前按解锁判定翻 `dev_locked` 标志 + 附解锁提示文本（boss debug 放行）；卡片按钮 dev_locked 时显示提示文本。
- **生涯商店 UI**：新场景（主菜单新按钮进入）；复用机库的面板/条目/三态按钮样板与功勋徽章；商品条目 = 名称 + 描述 + 价格按钮；未上架 = 灰条 + 条件文本。
- **消费点**：停靠结算送僚机段一行门控；战区时长 const → var（顺带修好 F6 调试面板经 `get()` 读常量取 null 的隐性 bug）。
- **与其它账本分工**：MeritLedger=货币；CareerArchive=战绩（解锁条件真源）；AircraftCodex=图鉴迷雾；**MetaShop=局外购买态**（生涯商品 + doctrine 学说；LoadoutLedger 已随槽位配件系统退役，见 spec doctrine-unlocks）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 选机页共八卡：原四卡与原解锁条件保持；新四卡未购时显示 ??? + 商店条件，购买后显示完整档案并可出击
- [ ] 击败航母 BOSS 通关一次后，F-14 卡解锁可选；地面击杀累计 30 后 A-6E 解锁；商店购入幻影后幻影解锁
- [ ] boss debug（选图页按 B）链路四卡恒解锁，不受档案影响
- [ ] 生涯商店：幻影恒上架；首次机场停靠后 dock_wingman 上架（停靠当帧弹上架 toast）；首次撤离后 op_time_30s 上架；未上架商品灰条显示条件
- [ ] 购买三态正确（可买/买不起/已拥有），扣功勋后主菜单徽章立即刷新；删存档后购买态清零且不被内存写回
- [ ] 未购 dock_wingman 时停靠：回血/进化/航母扣次/机场失效照旧但**不送僚机**；购入后恢复送 1 架；bench 行为不变
- [ ] 购入 op_time_30s 后 HUD 倒计时从 10:30 起跳，600s 超时判定/补给 clamp 同步 630s；未购/bench 恒 600s
- [ ] 战场支援页显示 AWACS + 四项战斗支援；机场 SAM 授权 3000 功勋、可独立永久购买，正式局门控解放机场 SAM，非正式局 fail-open
- [ ] 性能：全部事件驱动/一次性初始化，无每帧逻辑
- [ ] i18n 三语齐全；既有回归（--bench=all）不破
- [ ] verify_player_ref_holders / verify_doc_anchors 通过

## 6. 实现计划（Task Pipeline）

### 阶段 1 — MetaShop autoload
- [x] scripts/meta/meta_shop.gd：目录常量 + 纯静态判定 + owned 读写 + buy + debug_reset + 信号
- [x] project.godot 注册；main_menu 删存档登记
- [x] 无头单测 test_meta_shop.gd：判定纯函数 + 购买早退 + roundtrip（注入测试路径，真功勋零变动）

### 阶段 2 — 选机门控
- [x] PLAYABLE_LIST 补 id；_effective_list()（dev_locked 翻牌 + 提示文本 + debug 放行）
- [x] 卡片按钮 dev_locked 显示条件文本（A-6E 进度 FMT）

### 阶段 3 — 消费点
- [x] 停靠送僚机门控 + 首次机场停靠上架 toast
- [x] WARZONE_PHASE_DURATION const → var + 开局 +30 注入

### 阶段 4 — 商店 UI
- [x] meta_shop 场景 + 主菜单按钮；商品条目三态/灰条；功勋徽章
- [x] `meta.csv` + `interface.csv` 三语（§2.4 全表）

### 阶段 5 — 收尾
- [x] 跑单测（--bench=meta_shop 21 断言）+ --bench=all（40 项 PASS）+ verify 工具双绿
- [x] §7 锚点 + reference 索引 + specs/_INDEX + changelog；status → in-progress（差价格校准 + playtest）

### 阶段 6 — 战区支援授权
- [x] 新增 `support_zone_air` / `support_zone_ground` 目录项、权益查询与三语商品文案。
- [x] 战区任务执行器在正式局消费购买态，非正式局 fail-open。
- [x] 扩展 MetaShop / 战区支援回归与四分页断言。

### 阶段 7 — 王牌截击支援授权
- [x] 新增 `support_ace_f15` 目录项、权益查询与三语商品文案。
- [x] `AceReinforcementEvent` 消费权益并管理 2 架 F-15 入场/只对空/撤离。
- [x] 扩展 MetaShop 与王牌事件定向回归。
- [x] `meta_shop` 81/81；玩家引用校验与本 spec 文档校验通过。

### 阶段 8 — 机场防空网永久授权

- [x] 新增 `support_airfield_sam` 目录项、权益查询与三语商品文案。
- [x] 从局内升级池删除 `airfield_sam_network`，机场解放部署改读永久购买态。
- [ ] 扩展 MetaShop / zone_rewards 定向回归并同步索引。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 商店 autoload | `scripts/meta/meta_shop.gd` |
| 选机门控 | `scripts/survivor/survivor_select.gd` |
| 停靠门控 + 时长注入 | `scripts/survivor/survivor_mode.gd` |
| 商店 UI | `scripts/meta/meta_shop_ui.gd` + `scenes/meta_shop.tscn` |
| 主菜单入口/删档 | `scripts/main_menu.gd` |
| 单测 | `scripts/tests/test_meta_shop.gd` |
| i18n | `i18n/meta.csv`（METASHOP_* / UNLOCK_HINT_*）+ `i18n/interface.csv`（MENU_META_SHOP_*） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-26 | 1 | 初稿（起手四卡门控 + 3 件商品 + MetaShop 账本）；同日按 §6 全量落地，--bench=meta_shop 21 断言 + 回归门 40 项 PASS。差 §0 语义确认、价格校准与 §5 playtest 项 |
| 2026-07-27 | 2 | 用户裁定：锁定机型从 dev_locked 全信息形态改 **locked 占位形态**（不加载档案、??? 名 + 仅解锁条件句） |
| 2026-07-28 | 3 | §0 落地解释获用户批准（"可以执行"）；价格仍为草案，余项 = 价格校准 + §5 playtest。同期配件退役批把 6 张学说搬入本商店（见 doctrine-unlocks spec），回归门 41 项 PASS |
| 2026-08-01 | 4 | 战场支援页新增 `support_zone_air` / `support_zone_ground` 两项独立永久授权，各 3000 功勋且恒上架；正式局门控战区 F-86/A-10，非正式局 fail-open。`meta_shop` 76/76。 |
| 2026-08-08 | 7 | 用户裁定：F-86、A-10、F-15 三项已购空中支援分别改为每局首次合资格事件出动一次，不再随每个战区/王牌遭遇重复派遣；同步三语商品说明。Shadow `meta_shop` 88/88。 |
| 2026-08-01 | 5 | 战场支援页新增 `support_ace_f15` 永久授权，3000 功勋且恒上架；正式局门控非 BOSS 王牌轮换的 2 架 F-15 截击支援，非正式局 fail-open。`meta_shop` 81/81、支援链 46/46。 |
| 2026-08-02 | 6 | 用户裁定：机场防空网从局内技能池移除，改为战场支援页 `support_airfield_sam` 永久授权（3000 功勋）；购入后每局每座解放机场自动追加一次性 SAM×1。 |
| 2026-08-26 | 8 | 机体与后勤页新增恒上架全局商品“机体战术适配”（3000 功勋）；购买后启用自然升级 15% 普通第四卡机制。 |
| 2026-08-27 | 9 | 选机页从四卡扩为八卡：原 F-15/F-14/A-6E/Mirage III 与既有门控保留；MiG-21F-13/F-104C/J 35F/EA-6B 各以 1000 功勋采购案永久解锁。 |
