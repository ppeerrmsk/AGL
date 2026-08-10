---
id: aircraft-signature-progression
kind: system
status: approved
schema_version: 1
spec_version: 6
owner: 用户（设计）+ Codex（规格化）
depends_on: [aircraft-signature-skills, evolution-attribute-gates, career-shop, doctrine-unlocks, global-awareness-roe]
reconstruction_complete: true
---

# 机体专属技能成长 —— 第四槽、功勋解锁、商店分类与 AWACS 支援许可

> 玩家先亲自驾驶一架机，才会在生涯商店看见它的专属技能；购买许可后，每局驾驶该机时有一次高概率的第四卡机会。商店同时改为四类分页，并把友军 AWACS 事件纳入功勋解锁。

## 0. 用户规则与落地裁定

| 用户规则 | 本 spec 落地 | 说明 |
|---|---|---|
| 正常三张牌之外出现第四个机体专属槽 | 每 3 级的三轴卡片事件仍抽斗士/骑士/策士各一张；满足条件时追加第 4 张本机专属卡，形成四选一 | 不让专属技挤掉正常 build 的一个轴位 |
| 新机体的专属技有独立机会遇到 | 每架机每局在“首次符合条件的三轴卡片事件”独立掷 **30%**；命中才显示第四槽 | 起手机也算本局驾驶的第一架机；每次进化到新机可获得该新机自己的独立机会 |
| 不选就刷掉，直到下一把 | 第四卡一旦出现，无论选专属卡还是选普通卡，该机型本局机会立即结算；选普通卡等于明确放弃，本局不再出现 | 同机型反复切控或再次进化回来都不重置 |
| 功勋商店购买后才有机会刷 | 41 条专属技全部默认锁定；亲自获得过对应机体后才揭示并可购买；购买后永久获得“入第四槽资格” | 购买不直接把技能带进局，仍须在局内选卡 |
| 不剧透未知机体/技能 | 未发现机体只显示无编号、不可点击的紧凑 `???` 占位，不显示机体名、技能名、效果、背景、价格、Tier 或所属路线 | “完全不可见具体内容”与“项目显示 ???”同时满足 |
| 商店分类，避免长树状表 | 改为【战术学说】【机体专属】【战场支援】【机体与后勤】四个分页 | 已拥有条目保留，方便回看 |
| 友军 AWACS 也进入功勋商店 | 新商品“预警支援协定”，**3000 功勋**；正式局未购时 AWACS 不生成，购入后恢复现有调度与全部效果 | 不改 AWACS 数值、航线、在站时间或无线电 |

本 spec 获批后，覆盖 `aircraft-signature-skills` 中“签名技直接进入普通池、×2.5 抽取权重”的旧获取方式；41 条技能效果、继承、轴归属与稀有度不变。

## 1. 设计意图（Why）

- **体验目标**：让进化到一架新机时出现明确的“这架机有什么看家本领”时刻。专属卡是额外选择，不破坏三轴 build 的基础供应；放弃它也是一次有代价的主动决定。
- **发现 → 购买 → 局内遇见**：先亲自获得机体，再在局外投入功勋，最后仍需在局内四选一。三步分别承担探索、长期目标与 roguelike 决策，任何一步都不直接送永久战力。
- **Litmus #3 信息察觉**：专属槽使用独立洋红卡框、专属标题与当前机体名；技能名和效果本身已足够，不重复铺陈机体背景。
- **Litmus #9 局外成长节制**：功勋只买“这张牌本局有机会出现”，不直接加属性；全 41 项总价约等于数局收入，不做 30 局进度墙。
- **战场氛围**：AWACS 仍是可见、可听、能改变战区作战方式的支援事件；商店购买只是开启事件资格，不把它降格成菜单数值 buff。
- **反模式规避**：不做专属技等级、装备槽、重复购买、付费刷新、强制领取或暗中保底；不在未知占位上泄露机型路线与技能效果。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 专属技能商品目录

43 架机与 43 条专属技的效果权威表仍为 `aircraft-signature-skills` §2.2。本系统只增加“发现、购买、局内出示”三层状态。

| 字段 | 值 / 规则 |
|---|---|
| 商品 id | `signature_<evolution_node_id>`，例如 `signature_f15` |
| 对应升级 id | 默认 `sig_<evolution_node_id>`；唯一例外：`signature_f14 → f14_squad_lock_slow`（“围猎”） |
| 数量 | 43，必须与进化树节点和签名技能表一一对应，禁止缺项或重复 |
| 持久态 | 复用 MetaShop 的 `owned` 集合；购买一次永久拥有，不可叠加、不可退款 |
| 上架资格 | `AircraftCodex.is_discovered(node_id) == true`，即玩家曾用它开局或亲自进化到它 |
| 未发现形态 | 匿名 `???` 占位；不可购买、不可 hover 查看、不可显示价格和任何关联信息 |
| 已发现未购 | 显示机体名、Tier、专属技能名、效果、价格与购买按钮 |
| 已购 | 内容完整显示，按钮为“已拥有”；仍留在原位 |
| 老存档迁移 | **不自动赠送**任何专属许可；更新后所有专属商品按上述发现态揭示、购买态默认为未购 |

价格只按机体 Tier 决定，不按技能强度单独估价，避免制造“官方强度榜”与维护负担：

| 机体 Tier | 单项价格 | 数量 | 全购小计 |
|---|---:|---:|---:|
| T1 | 500 | 4 | 2000 |
| T2 | 600 | 16 | 9600 |
| T3 | 700 | 8 | 5600 |
| T4 | 800 | 7 | 5600 |
| T5 | 900 | 8 | 7200 |
| **合计** | — | **43** | **30000** |

### 2.2 第四槽出示规则

| 项 | 值 / 规则 |
|---|---|
| 触发事件 | 每 3 级一次的三轴卡片升级事件 |
| 正常卡 | 保持斗士 / 骑士 / 策士各 1 张，不受第四槽影响 |
| 专属出示概率 | **30%**，每个机型、每局只掷一次 |
| 掷骰时机 | 本局第一次驾驶该机型之后，首次发生三轴卡片事件时 |
| 出示前提 | 对应商品已购；对应技能本局未拥有；该机型本局机会未结算 |
| 未购行为 | 不掷骰、不显示第四槽；若本局稍后无法在战斗中购买，等同本局无资格 |
| 掷骰失败 | 该机型本局机会结算，不补掷；下一局重新获得一次 30% 机会 |
| 出示后选专属 | 正常获得技能、按该技能轴 +1 点、发放其 `milestone_plus`，该机机会结算 |
| 出示后选普通 | 正常获得所选普通技能并按其轴 +1 点；专属卡放弃，该机机会结算 |
| 多机路线 | 同一局进化到另一新机型后，新机型拥有自己独立的一次 30% 机会 |
| 重回旧机 | 不重置旧机已结算机会 |
| 既有稀有度 | 专属卡仍显示 CLASSIFIED；第四槽概率不再读取 CLASSIFIED 权重或 pity |
| 前置技能 | 第四槽**不使用 `requires_skill` 作为出示门槛**；可以先选专属技，效果在其玩法前提满足后自然生效。卡面照常明确写出前提 |

签名技能从所有普通随机来源中移除：三轴卡池、普通三选一后备入口、战区 NEXT_GEN 池均不得产生签名技。唯一局内随机入口就是本节第四槽；debug/bench 可走显式测试授予，不受此限制。

### 2.3 第四卡界面

| 元素 | 规则 |
|---|---|
| 无专属候选时 | 保持现有 3 卡居中布局，不留空白第四格 |
| 有专属候选时 | 同一横排显示 4 卡；四卡最小尺寸统一为 **240×180 px**，间距 **20 px** |
| 专属识别 | 洋红 `(1.00, 0.25, 0.75)` 边框、常规签名底色 `alpha 0.16`、边框比同稀有度普通卡再粗 1 px |
| 顶部标签 | `机体专属` + 当前机体本地化名称；替代普通卡左上轴徽章的位置 |
| 主体 | 专属技能名 + 现有效果描述 |
| 轴与归属 | 底部仍显示真实轴、作用范围、`milestone_plus`；若属性点封顶则去掉 `+1`，与普通卡一致 |
| 稀有度 | 右上仍显示真实 CLASSIFIED 徽章，不因专属槽改档 |
| 动画 | 第四卡加入现有错开入场与退场序列；选择任意一张后四卡一起退场 |
| 入场闪边 | 任意 **4 级（CLASSIFIED）技能卡**或**机体专属卡**完成入场时，按下表闪亮一次；两条件同时满足时只播放一次，专属语义优先 |

入场闪边是一次性视觉强调，不循环、不影响可点击时机：

| 时间 | 边框表现 |
|---:|---|
| 0.00~0.12s | 从常态快速提亮到 100%，边框宽度在常态上 **+2 px** |
| 0.12~0.22s | 保持峰值 |
| 0.22~0.55s | 平滑回落到常态颜色与宽度 |

- 普通 CLASSIFIED 卡用其真实 4 级稀有度色闪亮。
- 机体专属卡用洋红 `SIG_FRAME_COLOR` 闪亮；由于全部专属卡也是 CLASSIFIED，按“专属优先”只闪洋红一次。
- 动画在该卡错开入场结束后开始；不因 hover、焦点切换或同一弹窗重排而重播。
- 实现使用一次性 Tween/动画轨，不新增 `_process`、`_physics_process` 或循环计时器。

### 2.4 功勋商店分类与陈列

商店不再把所有条目堆成单列长表，改为四分页；每页独立滚动，切页不改变购买态。

| 分页 | 内容 | 排序 |
|---|---|---|
| 战术学说 | 既有 6 张 doctrine | 入门两张在前，其余按现有上架顺序 |
| 机体专属 | 43 条签名许可 | 已发现条目按 Tier 升序、同 Tier 按机体本地化名；未发现占位统一放末尾 |
| 战场支援 | `support_awacs`；后续战场事件类商品只进此页 | 价格升序 |
| 机体与后勤 | 幻影 III 采购案、停靠补给僚机、行动时间延长 | 机体采购在前，后勤项目在后 |

“机体专属”页使用两种密度：

- 已发现条目：两列完整卡，显示机体、技能、效果、价格/拥有态。
- 未发现条目：页底六列紧凑 `???` 方格；全部无编号、无 hover、无价格、无 Tier 色与路线色。它只表达“还有未亲自获得的机体”，不泄露是哪一架或有什么技能。

### 2.5 AWACS 商品

| 字段 | 值 / 规则 |
|---|---|
| 商品 id | `support_awacs` |
| 名称 | 预警支援协定 |
| 价格 | **3000 功勋** |
| 上架 | 恒上架 |
| 未购正式局 | AWACS 调度器关闭：不递减生成计时器、不创建事件 |
| 已购正式局 | 完全恢复现有行为：开局 **90~150s** 首次入场；事件结束后 **180s** 冷却再入场 |
| 现有效果 | 半径 **8000m**；玩家小队锁定速率 ×**3**；区内发射导弹追踪 G ×**1.25** |
| 生命周期 | 绕当前战区南侧盘旋；在站 **180s** 后撤离；撤离超时 **90s** 兜底；进/离场无线电不变 |
| 非正式局 | bench / boss debug 按 fail-open 视为已购，保持验证确定性；BOSS 阶段原有停摆规则不变 |

### 2.6 玩家可见文本（三语）

机体名、技能名与效果继续复用既有 i18n key；只新增系统通用文本：

| key | zh | en | ja |
|---|---|---|---|
| `METASHOP_TAB_DOCTRINE` | 战术学说 | Doctrines | 戦術ドクトリン |
| `METASHOP_TAB_SIGNATURE` | 机体专属 | Aircraft Signatures | 機体専用 |
| `METASHOP_TAB_SUPPORT` | 战场支援 | Battlefield Support | 戦場支援 |
| `METASHOP_TAB_CAREER` | 机体与后勤 | Aircraft & Logistics | 機体・兵站 |
| `UPGRADE_SIGNATURE_BADGE` | 机体专属 | AIRCRAFT SIGNATURE | 機体専用 |
| `UPGRADE_SIGNATURE_AIRCRAFT_FMT` | 当前机体：%s | Current aircraft: %s | 現在の機体：%s |
| `METASHOP_SIGNATURE_UNKNOWN` | ？？？ | ??? | ？？？ |
| `METASHOP_ITEM_AWACS_NAME` | 预警支援协定 | AWACS Support Accord | AWACS 支援協定 |
| `METASHOP_ITEM_AWACS_DESC` | 允许友军预警机在正式行动中进场支援 | Enables allied AWACS support during formal operations | 正式作戦で友軍 AWACS の支援を解禁 |

## 3. 行为与公式（How）

### 3.1 发现与购买

```text
正式局获得机体（起手机 / 进化成功）
  → AircraftCodex.mark_discovered(node_id)
  → 返回商店后，该机专属条目从 ??? 变为完整可购卡

buy(signature_<node_id>)
  → 必须：机体已发现 && 商品未拥有 && 功勋足够
  → 扣除 Tier 价格 → 写入 MetaShop.owned → 永久取得第四槽资格
```

bench、boss debug、测试场不得写入 AircraftCodex。现有发现调用点必须统一经过“正式局”闸，避免调试全谱把 43 个商店谜面全部掀开。

### 3.2 每机每局一次的出示状态机

每局维护 `signature_offer_state[node_id]`：

| 状态 | 含义 | 转移 |
|---|---|---|
| `UNSEEN` | 本局尚未为该机处理机会 | 首次符合条件的三轴事件时掷 30% |
| `OFFERED` | 本次弹窗正在显示第四卡 | 选任意卡后转 `RESOLVED` |
| `RESOLVED` | 本局该机机会已消耗 | 本局不再变化 |

```text
on_three_axis_upgrade_event(current_node):
  normal_cards = roll_three_axis_cards()
  signature = none

  if state[current_node] == UNSEEN
     and MetaShop owns signature_<current_node>
     and current signature skill not owned in this run:
       if randf() < 0.30:
         signature = signature_upgrade_for(current_node)
         state[current_node] = OFFERED
       else:
         state[current_node] = RESOLVED

  show(normal_cards + optional signature)

on_any_card_selected(card):
  if current popup contained signature:
     state[offered_node] = RESOLVED
  apply selected card through existing upgrade distribution and axis-point path
```

`offered_node` 在弹窗打开时快照；暂停期间即使其它系统改变当前引用，也不能把机会记到错误机型。

### 3.3 普通池排除

```text
is_normal_random_candidate(upgrade):
  if signature_upgrade_for_any_aircraft(upgrade.id):
    return false
  return existing availability + doctrine + stacks checks
```

旧 `SIG_SKILL_WEIGHT_MULT = 2.5` 不再参与任何自然抽卡；`is_signature_upgrade` 仍作为卡面、目录映射与测试的统一判别入口，但必须覆盖 F-14 的 `f14_squad_lock_slow` 特例。

### 3.4 AWACS 权益消费

```text
awacs_entitled = not formal_run or MetaShop.is_owned("support_awacs")

update_ally_events(delta):
  if not awacs_entitled:
    return                    # 计时器冻结，不积攒“买完立刻刷”的债
  run existing AWACS scheduler unchanged
```

## 4. 结构与组成（Structure）

- **签名目录**：集中提供 43 个 `node_id → upgrade_id → Tier 价格` 映射；除 F-14 外按命名约定派生，完整性由 bench 断言。
- **MetaShop**：购买态唯一真源；新增签名商品判定与 AWACS 商品，不复制 AircraftCodex 的发现集合。
- **AircraftCodex**：仍是“玩家亲自获得过哪些机体”的唯一真源；正式局闸补齐，禁止 debug 污染。
- **升级调度**：在三轴三卡已经抽完后独立决定第四卡；选卡继续复用现有升级分发、轴点、里程碑与退出动画。
- **升级 UI**：从固定 3 卡改为最多 4 卡；专属卡使用同一按钮基础组件，仅覆盖标题与视觉样式。
- **商店 UI**：分页容器 + 各页独立条目构建器；未知专属占位不加载对应机体档案或技能字典。
- **AWACS**：只在既有调度器入口增加权益闸；事件类、飞机、buff 注入、地图圈、无线电全部不改。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 新档案进入商店：专属页只显示匿名 `???` 占位；没有任何机体名、技能名、效果、背景、价格、Tier 或路线泄露。
- [ ] 用 F-15 完成一次正式出击后，商店只揭示已亲自获得的机体；boss debug / bench 全谱不会污染揭示态。
- [ ] 未购 `signature_f15`：连续多次等级卡片事件都不会在普通三卡或第四槽出现“无败之鹰”。
- [ ] 已购 `signature_f15`：本局首次符合事件只掷一次 30%；命中时显示 3+1，普通三轴卡内容与无第四槽对照组一致。
- [ ] 第四槽出现后选择普通卡：普通卡正确生效并加对应轴点；F-15 本局后续事件不再显示专属，下一局恢复一次机会。
- [ ] 第四槽选择专属卡：专属技、轴点、`milestone_plus`、归属分流与换机继承全部沿既有规则生效。
- [ ] 同一局 F-15 → F-15C：两机各有独立机会；再回到 F-15 不重复提供已结算机会。
- [ ] Su-27 / Su-35 / F-22 专属卡可在玩法前置尚未拥有时被选择，卡面明确写前提；后续满足前提时效果正常工作。
- [x] F-14 的 `f14_squad_lock_slow` 与其它 40 条行为一致，且普通池不再漏出（映射/普通池断言通过）。
- [x] 任意普通 CLASSIFIED 卡与专属卡闪边条件、专属洋红优先色由 UI bench 断言；0.55s 一次性 Tween 已落地，无循环。
- [ ] 统计 bench 用固定种子验证 100000 次 Bernoulli，实测命中率在 **89.5%~90.5%**；业务断言重点验证“每机每局只掷一次”，不写随机脆弱测试。
- [x] 商店四分页分类正确；专属页揭示/未购/已购三态、两列完整卡与六列 `???` 占位已落地，四分页 bench 通过。
- [ ] 未购 AWACS 的正式局 10 分钟内零 AWACS；购入后首架在 90~150s 调度窗口进入，后续冷却、buff、撤离、无线电与改前一致。
- [ ] 性能：新增逻辑仅发生在商店刷新、进化获得与每 3 级卡片事件；无新增 `_process` / `_physics_process` / 全场扫描。跑 Sentinel + Lv5+ 压测，FPS 掉幅 < 15。
- [ ] 针对性 bench 已通过：`meta_shop` 67、`sig_skills` 63、`status_notes` 31、`presentation` 106；`verify_player_ref_holders.py` 与 script-index 强锚点通过。共享工作树的 `--bench=all` 尚有 23 个非本功能失败（CareerArchive 测试写盘 22 + BOSS cost 护栏 1），code-index 亦有其它并行改动造成的历史漂移，留对应任务收口。
- [x] i18n：新增通用文本三语齐全；41 技能文本继续复用既有 key。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 用户定稿

- [x] 确认 30% / 每机每局一次、Tier 价格 500~900、AWACS 3000、四分页分类。
- [x] status 改为 `approved` 后再写代码。

### 阶段 1 — 目录、持久态与发现闸

- [x] 增加 41 项签名目录与完整性纯函数；MetaShop 承接签名购买判定和 Tier 定价。
- [x] 新增 `support_awacs` 商品与购买态。
- [x] AircraftCodex 的三个发现入口统一加正式局闸；补 debug 不污染回归。
- [x] 扩展 `meta_shop` bench：41 对齐、价格、发现门控、购买早退、老档默认锁、AWACS 商品。

### 阶段 2 — 第四槽调度

- [x] 三轴普通池显式排除全部 41 条签名技，退役签名 ×2.5 权重消费。
- [x] 增加逐机逐局状态账本与 30% 单次 roll；换机后以新 node 独立记账。
- [x] 第四卡选择复用现有 `_apply_upgrade_choice`、轴点与 `milestone_plus` 路径；前置技能不阻止出示。
- [x] 扩展 `sig_skills` bench 覆盖 41 映射、F-14 特例、30% 边界与前置语义。

### 阶段 3 — 升级 UI

- [x] 卡片组件从固定 3 个改为预建最多 4 个；三卡与四卡尺寸/动画按 §2.3。
- [x] 专属卡增加专属 badge 与当前机名；按用户复核移除冗余 `card_desc` 背景段，普通卡呈现不变。
- [x] 为普通 CLASSIFIED 与专属卡接入一次性 0.55s 边框闪亮 Tween；专属优先去重，接在各卡错开入场结束点。
- [x] 加 UI 纯逻辑断言：第四卡可见/转场元素/四卡尺寸/badge/闪边条件与优先色。

### 阶段 4 — 商店重构

- [x] 商店改四分页；迁移 6 学说、3 既有商品、AWACS 与 41 专属条目。
- [x] 专属页实现发现三态与 2 列 / 6 列双密度布局，未知占位严禁读取具体条目内容。
- [x] 补通用 i18n 文本与商店结构验收；最终手感/密度仍留用户实机确认。

### 阶段 5 — AWACS 门控与收尾

- [x] 在既有 AWACS 调度入口增加权益闸，冻结未购计时器；非正式局 fail-open。
- [x] 修订 `aircraft-signature-skills` 获取段、`career-shop` / `doctrine-unlocks` 商店结构段与 `global-awareness-roe` 调度前提。
- [x] 更新 reference 索引、spec 总表与变更记录；自动验证完成，实机 playtest 留作数值/视觉微调。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 专属技能数据、普通池过滤 | `scripts/survivor/survivor_data.gd` |
| 第四槽调度与逐机本局账本 | `scripts/survivor/survivor_mode.gd` |
| 第四卡界面 | `scripts/survivor/survivor_upgrade_ui.gd` |
| 功勋商品、购买态与权益 | `scripts/meta/meta_shop.gd` |
| 商店四分页 | `scripts/meta/meta_shop_ui.gd` + `scenes/meta_shop.tscn` |
| 机体发现态 | `scripts/survivor/aircraft_codex.gd` + 获得机体的调用点 |
| AWACS 调度与事件 | `scripts/survivor/survivor_mode.gd` + `scripts/events/awacs_support_event.gd` |
| 验收 bench | `scripts/tests/test_meta_shop.gd` + `scripts/tests/test_sig_skills.gd` |
| i18n | `i18n/skills.csv` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-04 | 5 | 用户调整专属技能出示概率：每机型每局一次由 90% 降为 30%，失败不补掷，其余第四槽规则不变。 |
| 2026-08-01 | 4 | 用户实机复核：机体背景文本重复且挤占卡面，商店专属商品与局内第四卡均移除该段，只保留机体名、技能名和效果。 |
| 2026-08-01 | 3 | 工程落地：第四槽、41 专属商品、四分页、AWACS 权益、CLASSIFIED/专属闪边与对应 bench；状态收口为 done，保留实机视觉/概率手感验收。 |
| 2026-08-01 | 2 | 用户回复“开始”，批准 v2 全案并进入实现。 |
| 2026-08-01 | 2 | 用户追加：4 级（CLASSIFIED）卡和机体专属卡入场时边框闪亮一次。定为 0.55s 单次 Tween（0.12s 提亮 + 0.10s 保持 + 0.33s 回落）、边框峰值 +2px；普通 4 级用稀有度色，专属用洋红且与 4 级条件去重。 |
| 2026-08-01 | 1 | 初稿：第四槽 90% 单次机会、跳过本局消失；41 专属功勋解锁与未知 `???`；商店四分页；AWACS 3000 功勋支援许可。 |
