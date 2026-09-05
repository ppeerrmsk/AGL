---
id: aircraft-signature-progression
kind: system
status: approved
schema_version: 1
spec_version: 10
owner: 用户（设计）+ Codex（规格化）
depends_on: [aircraft-signature-skills, evolution-attribute-gates, career-shop, doctrine-unlocks, global-awareness-roe]
reconstruction_complete: true
---

# 机体专属技能成长 —— 机场二选一、功勋解锁、商店分类与 AWACS 支援许可

> 玩家先亲自驾驶一架机，才会在生涯商店看见它的专属技能；购买许可后，停靠机场时可在
> “保留当前机体并装备专属技能”与“进化机体”之间二选一。专属技能不进入任何随机抽选。
> 商店同时保持四类分页，并把友军 AWACS 事件纳入功勋解锁。

## 0. 用户规则与落地裁定

| 用户规则 | 本 spec 落地 | 说明 |
|---|---|---|
| 专属技不得成为第四张随机卡 | 每 3 级保留斗士/骑士/策士三张基础卡；商店“机体战术适配”可能追加的第四张只来自普通池 | 专属技不参与稀有度、pity、流派 steering 或奖励抽取 |
| 停靠后形成机体去留二选一 | 许可已购且本局尚未获得当前机专属技时，规划站必须选择：保留当前机体并立即装备专属技，或进化到一个达标出口 | 未选择时底部按钮保持灰色；选择任一分支后立即结束本次停靠，不能空手跳过奖励，也不能先拿技能再进化 |
| 不进化即可装备 | 保留当前机体分支直接写入玩家层 `upgrade_stacks` 并下发效果；不发普通卡自带的 +1 轴点 | 技能自身显式 `milestone_plus` 仍属于效果定义，照常兑现 |
| 功勋商店购买后才可装备 | 43 条专属技全部默认锁定；亲自获得过对应机体后才揭示并可购买；购买后永久开放机场装备资格 | 未购时规划站展示技能和“许可未购”状态，但保留按钮不可用 |
| 不剧透未知机体/技能 | 未发现机体只显示无编号、不可点击的紧凑 `???` 占位，不显示机体名、技能名、效果、背景、价格、Tier 或所属路线 | “完全不可见具体内容”与“项目显示 ???”同时满足 |
| 商店分类，避免长树状表 | 改为【战术学说】【机体专属】【战场支援】【机体与后勤】四个分页 | 已拥有条目保留，方便回看 |
| 友军 AWACS 也进入功勋商店 | 新商品“预警支援协定”，**3000 功勋**；正式局未购时 AWACS 不生成，购入后恢复现有调度与全部效果 | 不改 AWACS 数值、航线、在站时间或无线电 |

本 spec v7 覆盖此前所有“普通池权重 / 30% 第四槽”获取规则；43 条技能效果、继承、轴归属、
稀有度、发现与购买规则不变。

## 1. 设计意图（Why）

- **体验目标**：把“留在熟悉机体上开发潜力”与“换取新机体性能”放在同一个机场决策里；
  专属技不再被概率吞掉，也不再干扰普通三轴 build 的基础供应。
- **发现 → 购买 → 机场取舍**：先亲自获得机体，再在局外投入功勋，最后在机场决定保留还是进化。
  三步分别承担探索、长期目标与局内路线取舍；购买本身仍不直接赠送战力。
- **Litmus #3 信息察觉**：机场右栏用洋红专属框明确展示当前机体、技能、完整效果与许可/已装备状态；
  进化目标使用独立白色终端框，两者中间固定显示 `OR`。
- **Litmus #9 局外成长节制**：功勋只买“机场装备资格”，不直接加属性；价格仍按 Tier 统一，不做强度榜。
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

### 2.2 机场二选一规则

| 项 | 值 / 规则 |
|---|---|
| 触发事件 | 机场停靠成功并打开规划站；Debug 临时机场按同一 UI/授予路径验收 |
| 方案 A | 保留当前机体；若对应许可已购且本局尚未拥有，则立即装备当前机专属技能 |
| 方案 B | 从当前可达且等级/三轴门均满足的直接出口中选择一架进化；全队跟随换型 |
| 互斥 | 任一方案确认后立刻锁定树与两个按钮、完成本次停靠并关闭规划站；不得先领专属技再进化 |
| 未购许可 | 专属框仍显示机体、技能名、效果与“许可未购”；保留并装备按钮禁用，但玩家可继续当前机体或进化 |
| 已装备 | 显示“本局已装备”，禁止重复授予；玩家可直接继续或进化 |
| 路线尽头 | 无可进化出口时仍可用方案 A；专属已装备/未购时允许直接继续出击 |
| 进度结算 | 机场装备不发普通选卡的 +1 轴点；技能自身显式 `milestone_plus` 仍照常发放 |
| 前置技能 | `requires_skill` 不阻断机场装备；效果在其玩法前提后续满足时自然启用，说明文案必须写明前提 |
| 继承 | 获得后进入玩家层 `upgrade_stacks`；后续换机重放不查 `exclusive_to`，继续跟随玩家 |

签名技能从所有随机来源中排除：三轴普通池、普通三选一后备入口、奖励三轴卡与战区 NEXT_GEN
池均不得产生签名技。唯一正式局获取入口是本节机场方案 A；F4 Debug 可显式授予以验收效果。

### 2.3 机场决策界面

| 元素 | 规则 |
|---|---|
| 顶部 | 白色终端标题 + 横跨面板的二选一说明条，明确写出“保留并装备 / 进化并放弃本次装备” |
| 左栏 | 可滚动进化树；亮色为当前可进化，点击任意节点更新中栏详情 |
| 中栏 | 机体参数、相对当前机差异、门槛，并对全部 43 节点展示其专属技能名与完整效果 |
| 右栏 | 三轴量表 + 方案 A 洋红专属框 + 固定 `OR` + 方案 B 白色进化框 |
| 专属识别 | 洋红 `(1.00, 0.25, 0.75)` 2 px 边框与低 alpha 底色；显示当前机体、技能名、描述和许可/装备状态 |
| 进化识别 | 白色终端 1 px 边框；未选目标时给出操作提示，选中后显示目标机名并启用确认 |
| 底部主按钮 | 有待领取的专属技时显示二选一提示并保持灰色不可点，不默认代选任何奖励；玩家必须主动确认右侧专属技能，或在左侧科技树选择达标节点并确认进化。专属未购、已装备或占位未完成时才显示普通“继续出击” |
| 输入锁 | 点击任一有效方案后树、两个方案按钮与继续按钮同拍锁定，防双击跨分支 |

普通升级 UI 预建 **4 个** `240×300 px` 物理卡位：前三个承担斗士/骑士/策士基础抽选，第四个只供
`airframe-affinity-fourth-card` 的普通轴卡稀有追加。它不包含专属 badge、当前机体标签或洋红专属样式；
第四卡继续按自身稀有度显示介质、边框与 CLASSIFIED 闪边。

### 2.4 功勋商店分类与陈列

商店不再把所有条目堆成单列长表，改为四分页；每页独立滚动，切页不改变购买态。

| 分页 | 内容 | 排序 |
|---|---|---|
| 战术学说 | 既有 6 张 doctrine | 入门两张在前，其余按现有上架顺序 |
| 机体专属 | 43 条签名许可 | 已发现条目按 Tier 升序、同 Tier 按机体本地化名；未发现占位统一放末尾 |
| 战场支援 | `support_awacs`；后续战场事件类商品只进此页 | 价格升序 |
| 机体与后勤 | 幻影 III 采购案、停靠补给僚机、行动时间延长、机体战术适配 | 机体采购在前，后勤项目在后 |

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
| `SETTLEMENT_DECISION_HEADER` | 地勤决策 | Ground crew decision | 地上クルー判断 |
| `SETTLEMENT_RETAIN_CONFIRM` | 保留机体并装备专属技能 | Retain airframe + equip signature | 現行機を維持 + 専用スキル装備 |
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
  → 扣除 Tier 价格 → 写入 MetaShop.owned → 永久取得机场装备资格
```

bench、boss debug、测试场不得写入 AircraftCodex。现有发现调用点必须统一经过“正式局”闸，避免调试全谱把 43 个商店谜面全部掀开。

### 3.2 停靠决策流

```text
on_docked(current_node):
  signature = signature_upgrade_for_aircraft(current_node)
  license_owned = MetaShop owns signature_<current_node>
  equipped = upgrade_stacks[signature.id] >= signature.max_stacks
  show_planning_station(current_node, signature, license_owned, equipped)

choose_retain_and_equip(signature):
  revalidate current_node mapping + license + max_stacks
  distribute signature through normal ownership path
  upgrade_stacks[signature.id] = 1
  grant signature.milestone_plus only       # no generic +1 axis point
  close settlement

choose_evolution(target):
  revalidate direct exit + level + all axis gates
  evolve ACE and squad + replay weapons/upgrades/milestones
  close settlement                         # cannot return to take signature
```

Debug/bench 的临时机场对许可 fail-open，便于直接验收 UI 与全部效果；正式局仍以 MetaShop 账本为准。

### 3.3 普通池排除

```text
is_normal_random_candidate(upgrade):
  if signature_upgrade_for_any_aircraft(upgrade.id):
    return false
  return existing availability + doctrine + stacks checks
```

旧 `SIG_SKILL_WEIGHT_MULT = 2.5` 与 `SIGNATURE_OFFER_CHANCE` 均已删除；`is_signature_upgrade`
仍作为普通池排除、机场目录映射、详情展示与测试的统一判别入口，并覆盖 F-14 的
`f14_squad_lock_slow` 特例。

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
- **机场调度**：停靠规划站读取当前 node、签名许可和玩家层账本；保留分支复用升级分发与
  `milestone_plus`，进化分支复用正式换型/重放路径，二者最终走同一停靠关闭收尾。
- **升级 UI**：基础三轴 + 条件普通第四卡；不持有任何专属第四槽状态或样式。
- **机场 UI**：进化树、逐机详情与右侧二选一决策台同屏；洋红只表达“当前机专属装备”。
- **商店 UI**：分页容器 + 各页独立条目构建器；未知专属占位不加载对应机体档案或技能字典。
- **AWACS**：只在既有调度器入口增加权益闸；事件类、飞机、buff 注入、地图圈、无线电全部不改。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 新档案进入商店：专属页只显示匿名 `???` 占位；没有任何机体名、技能名、效果、背景、价格、Tier 或路线泄露。
- [ ] 用 F-15 完成一次正式出击后，商店只揭示已亲自获得的机体；boss debug / bench 全谱不会污染揭示态。
- [x] 未购 `signature_f15`：普通三卡永不出现“无败之鹰”；机场显示完整技能与许可未购状态，装备按钮禁用。
- [x] 已购 `signature_f15`：什么都不选时底部按钮为灰色；玩家必须主动确认右侧“保留并装备”，或选择左侧可进化节点后确认，任一分支成功后立即结算并锁死另一分支。
- [x] 选择进化：正式双门与直接出口复查通过后换型、重放、关闭面板；本次停靠不能再领取旧机专属技。
- [x] 机场装备不发普通 +1 轴点；技能自身 `milestone_plus`、归属分流和后续换机继承照常生效。
- [x] Su-27 / Su-35 / F-22 可在玩法前置尚未拥有时装备；后续满足前提后效果正常工作。
- [x] 43 个进化节点逐一映射到 43 条专属技；F-14 特例与其它机体一样从普通池排除。
- [x] 升级 UI 预建 4 个物理卡位但普通轮次只显示基础三张；可见第四张也只能是普通轴卡，专属 badge/洋红闪边保持删除。
- [x] 商店四分页分类正确；专属页揭示/未购/已购三态、两列完整卡与六列 `???` 占位已落地，四分页 bench 通过。
- [ ] 未购 AWACS 的正式局 10 分钟内零 AWACS；购入后首架在 90~150s 调度窗口进入，后续冷却、buff、撤离、无线电与改前一致。
- [x] 性能：新逻辑只在停靠打开/点击时运行；无新增 `_process` / `_physics_process` / 全场扫描。
- [x] 针对性 bench：`evo_detail` 38/38、`sig_skills` 75/75、`attr_gates` 146/146、
  `status_notes` 47/47、`presentation` 244/244、`meta_shop` 88/88。
- [x] Visual：`upgrade_media_visual` 覆盖基础三卡与机体适配普通第四卡；`evolution_decision_visual` 覆盖许可有效与未购两态，
  1920×1080 三栏布局、翻译命中与完整视口均通过。
- [x] i18n：机场决策通用文本三语齐全；43 技能文本继续复用既有 key。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 用户定稿

- [x] v7 确认机场二选一、彻底退出抽选；Tier 价格 500~900、AWACS 3000 与四分页分类保持。
- [x] status 为 `approved` 后派生代码。

### 阶段 1 — 目录、持久态与发现闸

- [x] 增加 43 项签名目录与完整性纯函数；MetaShop 承接签名购买判定和 Tier 定价。
- [x] 新增 `support_awacs` 商品与购买态。
- [x] AircraftCodex 的三个发现入口统一加正式局闸；补 debug 不污染回归。
- [x] 扩展 `meta_shop` bench：41 对齐、价格、发现门控、购买早退、老档默认锁、AWACS 商品。

### 阶段 2 — 机场二选一调度

- [x] 三轴普通池继续排除全部 43 条签名技，并删除概率常量、逐机 roll 状态账本与追加函数。
- [x] 停靠规划站注入当前 node 的签名技能、许可态与本局装备态；正式局复查许可/max_stacks。
- [x] 保留分支只授予技能与 `milestone_plus`，不发普通 +1 轴点；进化分支成功后同样立即结束停靠。
- [x] `sig_skills` / `evo_detail` 覆盖 43 映射、F-14 特例、随机入口退役、许可态与互斥锁。

### 阶段 3 — 机场与升级 UI

- [x] 机场右栏重做为洋红保留框 / `OR` / 白色进化框，明确许可、已装备、目标与按钮状态。
- [x] 进化详情对全部 43 节点展示专属技能名与效果；映射缺失显红。
- [x] 升级 UI 维持专属技能隔离，并为机体适配普通第四卡重启条件槽位；专属 badge、当前机名与洋红闪边仍删除。
- [x] UI 纯逻辑断言覆盖三卡槽上限、机场不能绕过决策、确认后树与两分支同拍锁定。

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
| 机场二选一调度与正式授予 | `scripts/survivor/survivor_mode.gd` |
| 机场决策界面 / 逐机专属详情 | `scripts/survivor/evolution_ui.gd` / `scripts/survivor/evolution_detail_panel.gd` |
| 基础三轴 / 条件普通第四卡界面 | `scripts/survivor/survivor_upgrade_ui.gd` |
| 功勋商品、购买态与权益 | `scripts/meta/meta_shop.gd` |
| 商店四分页 | `scripts/meta/meta_shop_ui.gd` + `scenes/meta_shop.tscn` |
| 机体发现态 | `scripts/survivor/aircraft_codex.gd` + 获得机体的调用点 |
| AWACS 调度与事件 | `scripts/survivor/survivor_mode.gd` + `scripts/events/awacs_support_event.gd` |
| 验收 bench | `scripts/tests/test_meta_shop.gd` + `scripts/tests/test_sig_skills.gd` |
| i18n | `i18n/skills.csv` / `i18n/gameplay.csv` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-30 | 10 | 用户最终修订结算交互：未选择时底部按钮保持灰色，不替玩家默认领取技能；玩家必须主动选择右侧专属技能或左侧科技树可进化节点。 |
| 2026-08-30 | 9 | 用户修正结算空手跳过：有待领取专属技时，底部主按钮不再显示或执行普通“继续出击”，而是明确提交“保留当前机并装备专属技能”的正式方案 A。 |
| 2026-08-26 | 8 | 第四物理槽以新全局升级重新启用，但只追加当前机体身份轴的普通技能；专属技能仍完全隔离在机场二选一。 |
| 2026-08-26 | 7 | 用户改案：专属技彻底退出随机抽选与第四槽；机场停靠改为“保留当前机并装备专属技 / 进化机体”二选一。升级 UI 固定三卡；机场 UI 重做为双方案决策台并在全树详情展示 43 机专属技。 |
| 2026-08-04 | 5 | 用户调整专属技能出示概率：每机型每局一次由 90% 降为 30%，失败不补掷，其余第四槽规则不变。 |
| 2026-08-01 | 4 | 用户实机复核：机体背景文本重复且挤占卡面，商店专属商品与局内第四卡均移除该段，只保留机体名、技能名和效果。 |
| 2026-08-01 | 3 | 工程落地：第四槽、41 专属商品、四分页、AWACS 权益、CLASSIFIED/专属闪边与对应 bench；状态收口为 done，保留实机视觉/概率手感验收。 |
| 2026-08-01 | 2 | 用户回复“开始”，批准 v2 全案并进入实现。 |
| 2026-08-01 | 2 | 用户追加：4 级（CLASSIFIED）卡和机体专属卡入场时边框闪亮一次。定为 0.55s 单次 Tween（0.12s 提亮 + 0.10s 保持 + 0.33s 回落）、边框峰值 +2px；普通 4 级用稀有度色，专属用洋红且与 4 级条件去重。 |
| 2026-08-01 | 1 | 初稿：第四槽 90% 单次机会、跳过本局消失；41 专属功勋解锁与未知 `???`；商店四分页；AWACS 3000 功勋支援许可。 |
