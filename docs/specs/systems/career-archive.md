---
id: career-archive
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 2
owner: 用户（设计）+ Claude（起草）
depends_on: []
reconstruction_complete: true
---

# 玩家生涯档案（Career Archive）

> 跨局持久记录玩家的生涯战绩（分机型击坠 / BOSS 战绩 / 通关·阵亡·撤退·停机计数），
> 并第一次把"档案"变成玩法输入：**BOSS 按档案轮换登场** + **成就解锁新的战区奖励**。
> 这是后续"全局成长系统"的数据地基。

## 0. 命名与语义澄清（✅ 2026-07-28 用户批准）

用户口述需求中的几个词，本 spec 按以下方式落地（用户"可以执行"批准全表）。**将来若调整，改这里再改代码**：

| 用户用词 | 本 spec 落地 | 依据 |
|---|---|---|
| "Race"（第一个 BOSS） | **WRAITH_SQUADRON**（雷斯中队 / F-47 四机） | 代码与文档全仓无 "Race" BOSS；BossRegistry 仅有 WRAITH / CSG / GOOSE 三个，拼读最接近 Wraith，且三个 BOSS 恰好与用户列的三顺位一一对应 |
| "航母"（第二个 BOSS） | **CARRIER_STRIKE_GROUP**（Ladon 战斗群，二阶段 Poltergeist F-14） | 唯一船类 BOSS；内部 id 保留 CARRIER_STRIKE_GROUP，玩家可见名走 `CODEX_CARRIER_STRIKE_GROUP_NAME` |
| "打过某个 BOSS" | **击败过**（defeats > 0），不是"遇到过" | 轮换规则"打过了下次一定换"只有按击败解释才自洽 |
| "遇到 BOSS" | BOSS 战**进入 ENGAGED 接战相**的那一刻 | 复用现成 `on_boss_engaged` 回调，零新 API；PRE_STAGE 登场未接战即全灭属极罕见（猎手准则下 BOSS 主动追人） |
| "撤离" | **出界撤退菜单确认**（retreat_confirmed，即结束本局的那条路径） | 本仓 "撤离" 有三义（撤退结算 / 轮盘撤离此区 / 编辑器 extract）；档案只记结算义，字段一律命名 `retreat` 不用 extract/evac |
| "停机" | **停靠点 docked 判定成功一次**（机场/航母减速着陆 ≤阈值持续 1s） | zone-reward-docking 的停靠语义 |
| "某一关" | **一张地图 = 一关**（victories 按 map_id 计） | 现状一局=一关、仅 default 图；按 map_id 建键为 5 槽地图预留 |
| "UAV 类敌人" | enemy_type ∈ **{uav, ucav, uav_commander, uav_laser}**（全部无人机 tag；MQ-X/蜂群刷出时也打 "uav"） | spawner 的 enemy_type meta 是唯一稳定机型标识 |

## 1. 设计意图（Why）

- **体验目标**：
  1. 玩家的每一局都在生涯里**留下痕迹**——打了几百架什么机、倒在哪个 BOSS 手上、通关几次，这些数据是未来全局成长系统（图鉴/称号/解锁树）的原料。
  2. BOSS 登场从纯随机改为**档案驱动的递进轮换**：新玩家按固定顺序初见每个 BOSS（雷斯中队 → 航母 → Mother Goose），打赢一个下次必换，形成"生涯层面的 BOSS 图鉴推进感"；同时顺手把 MOTHER_GOOSE 正式上线（它做完了却一直不在地图池里）。
  3. 第一个成就作为实验样板：**累计击坠 30 架 UAV 族 → 弹成就 → 忠诚僚机进入战区奖励池**。跑通"档案 → 成就 → 解锁"的完整链路，后续成就照此复制。
- **Litmus 自检**（引 DESIGN_PHILOSOPHY）：
  - **#9 局外成长节制**：档案只做**记录 + 内容解锁**（换 BOSS、开奖励条目），不加任何局外数值 buff；30 UAV 一两局即可达成，不是进度墙。局内 90/10 比例不受影响。
  - **#3 信息察觉**：每次解锁都有明确反馈（成就 toast）；BOSS 轮换本身就是最强感知（"这局 BOSS 换了"）。
  - **#11 60 FPS**：全部记录都是事件驱动的字典自增（击杀/结算/停靠时刻），零每帧成本；写盘走脏标记 + 低频冲刷，绝不逐击杀写盘。
- **反模式规避**：不做长线进度墙；不做玩家无感的暗记录（v1 至少成就有 toast，其余数据留给全局成长 UI 消费）；不复活已退役的 ZoneRewardRegistry。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 存档文件 schema

存档：`user://career.cfg`（ConfigFile，UTF-8）。所有键缺省即零值/空表。

| section | key | 类型 | 缺省 | 说明 |
|---|---|---|---|---|
| `kills` | `air` | Dictionary {String: int} | {} | 分机型空中击坠数，键 = enemy_type tag（uav / mig / f47 / …） |
| `kills` | `ground_total` | int | 0 | 敌地面单位摧毁总数（不分型、不归因，粗粒度备将来用） |
| `boss` | `encounters` | Dictionary {String: int} | {} | 每 BOSS 接战次数，键 = boss_id |
| `boss` | `defeats` | Dictionary {String: int} | {} | 每 BOSS 击败次数 |
| `boss` | `last_encountered` | String | "" | 最近一次接战的 boss_id（轮换指针） |
| `runs` | `started` | int | 0 | 开局次数（正式局） |
| `runs` | `victories` | Dictionary {String: int} | {} | 通关次数，键 = map_id |
| `runs` | `deaths` | int | 0 | 阵亡结算次数 |
| `runs` | `retreats` | int | 0 | 撤退结算次数 |
| `runs` | `dockings` | Dictionary {String: int} | {} | 停机次数，键 = dock_kind（airfield / carrier） |
| `achievements` | `unlocked` | Dictionary {String: String} | {} | 已解锁成就，值 = 解锁日期 "YYYY-MM-DD" |

### 2.2 记录事件表（何时记什么）

| 事件 | 档案变更 | 触发语义 |
|---|---|---|
| 正式局开始 | `runs.started += 1` | 生存模式初始化完成（非 bench / 非 boss debug） |
| 敌机被玩家小队击坠 | `kills.air[enemy_type] += 1` | 敌机死亡结算帧，且击杀归因 team == 玩家方（含僚机；见 §3.2） |
| 敌地面单位被摧毁 | `kills.ground_total += 1`；`kills.ground_by_type[tag] += 1` | 地面单位死亡结算帧（不做归因）。tag 由类派生：`sam` / `aa` / `radar`（图鉴逐型展示，2026-07-28 加） |
| 王牌中队入场 / 全灭 | `ace.encounters[id] += 1` / `ace.defeats[id] += 1` + 首破日期 | 见 ace-squadron-tier §2.7（非 BOSS 王牌） |
| BOSS 接战 | `boss.encounters[id] += 1`；`boss.last_encountered = id` | BOSS 事件进入 ENGAGED 相 |
| BOSS 击败 | `boss.defeats[id] += 1` | BOSS 事件 VICTORY 相回调（encounter.active 下降沿） |
| 通关 | `runs.victories[map_id] += 1` | 胜利结算（现状=击败 BOSS 即通关） |
| 阵亡 | `runs.deaths += 1` | 全队覆灭 game over 结算 |
| 撤退 | `runs.retreats += 1` | 出界撤退菜单确认结算 |
| 停机 | `runs.dockings[dock_kind] += 1` | 停靠点 docked 判定成功（每次停靠计一次） |
| 成就达成 | `achievements.unlocked[id] = 日期` | 条件在对应记录函数内即时判定（见 §2.4） |

### 2.3 常量表

| 常量 | 值 | 说明 |
|---|---|---|
| 存档路径 | `user://career.cfg` | 与 merit.cfg / aircraft_codex.cfg 同级 |
| `BOSS_ROTATION` | `["WRAITH_SQUADRON", "CARRIER_STRIKE_GROUP", "MOTHER_GOOSE"]` | 生涯递进顺序（唯一顺序源；将来加新 BOSS 追加到表尾即可） |
| `ROTATION_ADVANCE_CHANCE` | `0.5` | 未击败当前 BOSS 时，下次仍推进到下一个的概率（单杠杆；打赢则 100% 换） |
| `UAV_FAMILY` | `{"uav", "ucav", "uav_commander", "uav_laser"}` | UAV 族 enemy_type 集合 |
| UAV 猎手门槛 | `30` | UAV 族累计击坠达标线 |
| 成就 toast 时长 | `6.0 s` | ZoneHint 临时提示，不用红色警告横幅（红横幅 = BOSS 专属语义） |

### 2.4 成就表（v1 仅一条，作系统样板）

| id | 条件（读档案） | 解锁效果 | 反馈 |
|---|---|---|---|
| `uav_hunter` | Σ `kills.air[t]`，t ∈ UAV_FAMILY ≥ 30 | 战区奖励武器子池新增 **忠诚僚机** 条目（此前该条目不参与 roll） | 局内 toast（§2.5 文案）+ EventLogger `ARCHIVE` 事件 |

忠诚僚机的**其它获取渠道不受门控**：A-10 变体自带、机体签名/首驾入库（inrun-weapon-inventory）照旧。门控只作用于战区奖励 roll 这一条通道。

### 2.5 i18n 新增 key（前缀 `ACHIEVEMENT_*` / `CODEX_*`，需回填 reference/i18n.md 前缀表）

| key | zh | en | ja |
|---|---|---|---|
| `ACHIEVEMENT_UAV_HUNTER_TOAST` | 成就解锁：无人机猎手 —— 战区奖励新增「忠诚僚机」 | Achievement unlocked: Drone Hunter — Loyal Wingman added to zone rewards | 実績解除：ドローンハンター —— 戦区報酬に「ロイヤルウィングマン」追加 |

（将来每条新成就加一条 `ACHIEVEMENT_<ID>_TOAST`。）
图鉴文案走 `CODEX_*` 前缀：页面壳 14 条 + 分组标题 5 条 + **每条敌人两条**
（`CODEX_<ID>_NAME` 机型名 / `CODEX_<ID>_DESC` 一行定位）——加新敌人时与图鉴条目同批加。

### 2.6 敌人图鉴（呈现层，2026-07-28 用户）

> 用户需求：档案页显示**所有敌人**——包括小杂兵与 BOSS，打败过就有计数。
> 这把原「王牌档案」页泛化为全局图鉴：档案系统积攒的击坠数第一次有了展示出口。

**入口**：主菜单「敌人图鉴」（原「王牌档案」条目改名并扩容）。

**解锁语义（全局统一，承王牌档案的 tier §2.7 "先打到它，再认识它"）**：

| 状态 | 呈现 |
|---|---|
| 击败数 = 0 且从未遭遇 | 剪影行：灰图标 + `???` + "尚未遭遇" |
| 击败数 = 0 但遭遇过（仅王牌 / BOSS 有遭遇计数） | 剪影行 + "已遭遇 N 次——它认识你了" |
| 击败数 > 0 | 名称 + 一行简介 + 战绩 + 右侧 `×N` 大字计数 |

**分组与计数口径**（顺序 = 页面渲染顺序）：

| 组 | 条目 | 计数口径 | 措辞 |
|---|---|---|---|
| 空中敌人 | 19 型常规机（MQ-109 → Aegis UAV，按威胁递增排序） | `kills.air[tag]` | 累计击坠 |
| 非战斗机群 | Tu-160 / AH-64 / CH-47 | 同上 | 累计击坠 |
| 地面单位 | SAM / AA / 雷达站 | `kills.ground_by_type[tag]` | 累计摧毁 |
| 王牌中队 | 6 支（含宿敌 ORION） | `ace.defeats[id]` | 击破次数 + 遭遇次数 + 首破日期；**额外解锁 lore 全文 + 专属徽章**；ORION 附"下一架"机号 |
| BOSS | Wraith 中队 / Ladon 战斗群 / 鹅妈妈 | `boss.defeats[id]` | 击败次数 + 遭遇次数 |

**收录边界（显式裁定）**：
- **王牌 / BOSS 专属机型不单列**（F-47、F-14 Poltergeist、F-15、F-16、Mirage 2000、Su-47、Cre）
  —— 它们只随所属中队出现，编成写在该中队条目的简介里；单列会让图鉴出现"打不到的空条目"。
- **舰船不单列**：航母与护卫舰是 CSG BOSS 的组件，由该 BOSS 条目覆盖（无独立击沉计数）。
- 页首显示**总收录进度** `已解锁 / 总条目`，每组标题右侧显示该组进度。

### 2.7 游戏信息手册（资料库第二分类，2026-07-28 用户）

> 用户需求：在敌人图鉴边上再写一个档案库，写清**游戏的所有机制**——左键/右键每个操作
> 能干什么、E 键加力模式有什么用等等；Tab 页面会显示的那些小技巧也收进来。
> 两者分成并列的两个分类。

**形态**：资料库页顶部两个分类页签 —— ①敌人图鉴（§2.6）②游戏信息。
游戏信息**无解锁门槛**（说明书不是收集品，随时可查全文）。

**分组与内容**（7 组约 47 条，顺序 = 先手上的操作、再飞机本身、最后一局怎么打）：

| 组 | 覆盖 |
|---|---|
| 鼠标操作 | 点空域移动 / 点敌人点名 / 双击冲锋 / 按住拖拽呼出轮盘 / 右键解除任务 / 长按右键急刹 / 镜头平移缩放 |
| 键盘 | 1-9 切控 · **E 加力模式**（含充能数值与"期间不能攻击"的代价）· R 手动闪避 · F 自动发射 · Q 高度偏好 · T 武器优先 · C 小队姿态 · V 小队武器 · Tab · Space · ESC |
| 小队指挥 | **单点管自己 / 轮盘管全队** 的操作语法 · 小队命令轮盘 · 攻击轮盘（姿态 × 火力分配）· 点名铁律 · 换机不换命令 |
| 飞行与机动 | 角点速度 · 转弯半径 · 三个高度档 · 高低空取舍 · 云层 · 失速安全地板 |
| 武器与交战 | **除 BOSS 外一发即杀** · 雷达锁定 · 导弹射程/最佳发射距离/发射后照射 · 热诱弹 · 机炮 · 装填 · 武器切换 |
| 一局怎么打 | 战区→BOSS 流程 · 边界补给与时间税 · 停靠领奖/进化 · 升级与三轴 · 机体进化 |
| 战场情报 | 王牌中队 · BOSS · 指挥机 |

**单一数据源约定（关键）**：战术地图（Tab）轮播的 `TACTICAL_TIP_*` 小技巧**不复制文本** ——
手册条目声明 `tip` 字段即直接复用那条译文，改一处两边同步，杜绝"手册说 A、Tab 说 B"。
14 条小技巧因此在手册里可回看，并打「情报」角标。
新增小技巧：进 `tactical_map._TIP_KEYS` 的同时在手册表挂一条。
bench 断言 tip 条目必须指向**轮播表在用**的 key（写错 = 手册显示原始 key）。

**顺带修复**：`TACTICAL_TIP_WEAPON_SWAP` 写着「按 [1/2] 切换武器」——键位早已改为 T
（1-9 是切换操控僚机），属于会误导玩家的过期文案，本批订正。
（`TACTICAL_TIP_STAMINA` 描述的飞行员耐力已从代码移除，但它本就不在轮播表里，不动。）

### 2.8 防腐烂约束（两分类通用）

**图鉴条目 id** 必须与真实系统标识一一对上（AIR/ADDS = `SurvivorSpawner.type_tag_of`
的返回值集合 / ACE = `AceSquadProfiles` 键 / BOSS = `BossRegistry.BOSS_DEFS` 键）。
拼错一个字符不会报错、只会让该条目**永远显示 0**，故由 `--bench=career_archive` 断言守住
（id 对齐 / 无漏收录 / 三语译文齐全 / 分组覆盖）。为此把 spawner 内联的 `type_tag` match
抽成静态 `type_tag_of()`，成为机型标识的唯一源。

**翻译表结构断言**（2026-07-28 加）：CSV 字段含 ASCII 逗号却未加引号时，导入会把该行
切成多列 —— zh 仍对、en 被截断、ja 落到第 4 列之外。此时 `tr(key) != key` 依然成立，
"有译文"的检查**抓不到**，玩家看到的却是半句话。故 bench 直接校验
`translations.csv` 全表列数一致。本批据此发现并修复 36 行（34 行本批新写 + 2 行历史遗留：
`TOOLTIP_EVADE_OFF_BODY` / `BOSS_DEBUG_GOOSE_DESC` 的英文长期被截断）。
**写含逗号的译文必须整字段加引号。**

## 3. 行为与公式（How）

### 3.1 BOSS 轮换算法

轮换只在**正式局的 BOSS 事件选型时**生效；debug 覆盖（F6 / boss debug 场）绕过不受影响，也不写档案。

```
输入 history = { last: boss.last_encountered, defeated: {id: defeats[id] > 0} }
n = len(BOSS_ROTATION)

候选序 candidates(history, roll):
  若 last 为空或不在 ROTATION 内:
      → ROTATION 原序          # 生涯首遇：雷斯中队最优先
  i = ROTATION.index(last)
  若 defeated[last]:            # 打过 → 下次必换
      → [i+1, i+2, … (环绕)] + [last 垫底]   # last 只作地形过滤兜底
  否则:                         # 没打过 → roll 决定推进或重复
      若 roll < ROTATION_ADVANCE_CHANCE:
          → [i+1, i+2, … 环绕 … , last 垫底]  # 推进
      否则:
          → [i, i+1, … 环绕]                  # 重复当前 BOSS 优先

最终选择 = 候选序中第一个 通过地图池 ∩ 地形过滤（requires_water）的 boss_id
```

- **地形过滤兜底**：CSG 要求出生点在水面。BOSS 锚点本就会吸附海面；若吸附失败导致 CSG 被滤掉，则顺延候选序取下一个（雷斯/Goose 无水面要求，候选序必非空）。实际刷出谁就记谁为 `last_encountered`——轮换指针永远跟随事实，不会因过滤"跳档"。
- **纯随机回退**：不传 history（bench / 老调用方）时保持原纯随机行为不变。
- **推演样例**（全部打赢的玩家）：局1 雷斯 → 局2 航母 → 局3 Goose → 局4 雷斯（环绕）。
  （一直打不赢雷斯的玩家）：局1 雷斯 → 局2 50% 雷斯 / 50% 航母 → …（每局独立 roll，期望 2 局内见到新 BOSS，不会被卡死）。
- **地图池变更**：`MAP_POOLS.default` 由 `[WRAITH, CSG]` 扩为**全部三个 BOSS**（MOTHER_GOOSE 正式上线，这是本设计的有意变更）。

### 3.2 击坠入档判定

- 挂在敌机死亡结算帧（XP 发放同帧），读 victim 的 `enemy_type` meta 作为机型键。
- **归因规则**：仅当 victim 的击杀归因 team == 玩家方（team 0，含僚机）才入 `kills.air`。无归因的死亡（坠地自杀等）与第三方友军（ALLY，team 2）的击坠**不计**。
- 已知精度边界（接受，不修）：BOSS 编队等非 spawner 生成的敌机若无 enemy_type meta，会落入死亡结算的缺省桶 "mig"；spawner 生成侧缺省桶为 "uav"。加新敌人时按 enemy-index 13 步清单登记 tag 即不受影响。
- "玩家亲手 vs 僚机代劳"**不区分**（与技能层 on_kill 语义一致；切控换帅下"亲手"无稳定定义）。

### 3.3 成就判定与忠诚僚机入池门控

- 每次 UAV 族击坠入档后即时求和判门槛；达标一次性解锁（幂等，二次达标无事发生），立即写盘 + 发信号 → 局内 toast。
- 战区奖励 roll 的上下文 ctx 增加 `loyal_wingman_unlocked` 布尔；武器子池抽取时该值为 false 则将 `loyal_wingman` 权重清零。
- **缺省 fail-open**：ctx 里没有这个键时视为已解锁（= 旧行为）。正式局的 ctx 构建点是唯一真源，负责传真实值；bench / 旧调用方不传则行为与门控前完全一致，保住既有 zone_rewards 回归断言。

### 3.4 写盘策略（性能守则）

- 所有记录函数只改内存 + 置脏标记。**逐击杀绝不写盘**。
- 冲刷点（低频，每局个位数次）：三条结算路径（阵亡/撤退/通关）、BOSS 接战与击败、停机、成就解锁、开局、窗口关闭通知（WM_CLOSE_REQUEST）。
- 崩溃最多丢**当前未结算局**的击坠增量，可接受。

### 3.5 入档铁律（仿 AircraftCodex）

- **bench 局与 boss debug 局一律不入档**：所有记录调用统一走"正式局"守卫（非 bench、非 boss debug）。BOSS 轮换的 history 在非正式局传空 → 走纯随机，互不污染。
- 主菜单"删除存档"必须同时调用档案的 debug_reset（autoload 内存态 + 删文件），只删文件会被内存态写回。
- 档案不持有任何 Aircraft/Node 引用，只存值类型（SEAM-019 免疫）。

## 4. 结构与组成（Structure）

- **CareerArchive**（新 AutoLoad，scripts/meta/ 下，排在 MeritLedger 之后）：ConfigFile 读写 + 记录 API + `achievement_unlocked(id)` 信号 + `build_boss_history()`（供 BOSS 选型）。
- **记录挂点**（全部在生存模式既有函数内加一行调用，无新节点）：敌机/地面死亡结算、BOSS 接战回调、BOSS 胜利回调（需把被丢弃的事件参数接回来以读 boss_id）、三条结算路径、停靠回调、开局初始化。
- **BossRegistry**：加 `BOSS_ROTATION` 常量 + `rotation_candidates(history, roll)` 纯函数；`pick_for_map` 增加可选 history 参数；`MAP_POOLS.default` 补 MOTHER_GOOSE。BOSS 事件构造时由生存模式注入 history（事件层不直读 autoload，保持可测）。
- **奖池门控**：战区奖励 roll ctx 增加解锁布尔，武器子池按其过滤。
- **与既有持久层的分工**：MeritLedger = 局外货币；AircraftCodex = 机体图鉴（驾驶过哪些机型）；**CareerArchive = 战绩统计 + 成就解锁**。三者各管一段，不合并（各自文件小、语义清晰、删档粒度独立）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 新档案首局 BOSS 必为雷斯中队；击败后下一局 BOSS 必不同（航母优先）；三 BOSS 均击败过后循环轮换
- [ ] 未击败当前 BOSS 时，多局观察约半数重复、半数推进（0.5 概率）
- [ ] BOSS 锚点在纯陆地时不会强刷 CSG（顺延候选），档案记录与实际刷出一致
- [ ] 击坠 UAV 族累计到 30 的当帧弹成就 toast；此后战区奖励可 roll 出忠诚僚机，此前绝不出现（A-10 自带等其它渠道不受影响）
- [ ] 阵亡/撤退/通关/停机各计数在结算后查 user://career.cfg 数值正确；boss debug 局与 bench 局零写入
- [ ] 主菜单删除存档后 career.cfg 归零且不被写回
- [ ] 性能：记录全事件驱动，无每帧逻辑；生存模式 Sentinel + Lv5+ 压测 FPS 无回退（performance-guidelines）
- [ ] 已知 seam：verify_player_ref_holders 通过（档案不持引用）；kill_recorded 信号契约未改动
- [ ] i18n：成就 toast 走 tr()，三语齐全（reference/i18n.md），Godot 重导入 CSV 后三语显示正常
- [ ] 既有回归不破：zone_rewards / boss_hunter / attr_gates 等 bench 全绿

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 档案 autoload
- [x] scripts/meta/career_archive.gd：schema 读写 + 记录 API + 脏标记冲刷 + debug_reset + 成就判定与信号
- [x] project.godot 注册 AutoLoad；主菜单删档处补 debug_reset
- [x] 无头单测：存取 roundtrip + 成就幂等（可注入测试路径，不碰真存档）

### 阶段 2 — 记录挂点
- [x] 敌机死亡结算：归因过滤 + enemy_type 入档；地面单位计数
- [x] BOSS 接战/击败：胜利回调把事件参数接回（读 boss_id）
- [x] 三条结算路径 + 停机 + 开局；统一正式局守卫

### 阶段 3 — BOSS 轮换
- [x] BossRegistry：BOSS_ROTATION + rotation_candidates 纯函数 + pick_for_map(history)
- [x] MAP_POOLS.default 补 MOTHER_GOOSE
- [x] BOSS 事件构造链注入 history（正式局才传）
- [x] 无头单测：首遇序 / 击败必换 / 未败 roll 推进 / 环绕 / 地形过滤顺延

### 阶段 4 — 成就与奖池门控
- [x] roll ctx 加 loyal_wingman_unlocked（fail-open 缺省）+ 武器子池过滤
- [x] 成就 toast（ZoneHint 临时条，非红横幅）+ EventLogger 打点
- [x] translations.csv 三语 key

### 阶段 5 — 收尾
- [x] 跑新单测（--bench=career_archive 31 断言）+ 既有回归（--bench=all 39 项 PASS）
- [x] 填 §7 锚点；同步 script-index / code-index / specs/_INDEX / i18n.md 前缀表；写 changelog
- [x] status → in-progress（§0 已获用户批准 2026-07-28；差 playtest）

### 阶段 6 — 敌人图鉴（§2.6，2026-07-28 用户）
- [x] 逐型地面计数：`record_ground_kill(tag)` + `ground_by_type` schema（旧档兼容：无该键 → 逐型 0、总数保留）+ spawner 按类派生 tag
- [x] `SurvivorSpawner.type_tag_of()` 静态化（机型标识唯一源）+ `all_type_tags()` 供校验
- [x] `scripts/meta/enemy_codex.gd`：34 条目注册表（19 空中 / 3 Adds / 3 地面 / 6 王牌 / 3 BOSS）+ 分组 + 计数分派 + 完成度
- [x] 图鉴页 `scripts/meta/enemy_archive_ui.gd` + `scenes/enemy_archive.tscn`（原 ace_archive 页泛化并改名）；主菜单入口改「敌人图鉴」
- [x] i18n：`CODEX_*` 页面壳 14 + 分组 5 + 28 条敌人名称/简介（三语）
- [x] bench 扩 13 断言（id 对齐 / 无漏收录 / 三语齐全 / 分组覆盖 / 计数路由 / 落盘重读 / 旧路径兼容）

### 阶段 7 — 游戏信息手册（§2.7，2026-07-28 用户）
- [x] `scripts/meta/game_info_codex.gd`：7 分组 47 条（鼠标/键盘/小队指挥/飞行/武器/一局流程/情报）；`tip` 字段复用战术地图小技巧译文
- [x] 页面改双分类：`enemy_archive_ui` → `scripts/meta/archive_ui.gd` + `scenes/archive.tscn`（顶部页签切换）；主菜单入口改「资料库」
- [x] i18n：`INFO_*` / `ARCHIVE_*` 三语（手册正文含加力模式充能数值、操作语法、一发即杀等）
- [x] 修 `TACTICAL_TIP_WEAPON_SWAP` 过期键位（[1/2] → [T]）
- [x] bench 扩 4 断言（手册分组覆盖 / 译文齐全 / tip 对齐轮播表 / **CSV 列数一致**）

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 档案 autoload | `scripts/meta/career_archive.gd`（AutoLoad 注册在 project.godot） |
| 击坠/地面入档 | `scripts/survivor/survivor_spawner.gd` `_detect_kills` 内 |
| BOSS/结算/停机/开局挂点 + 入档守卫 | `scripts/survivor/survivor_mode.gd`（archive_enabled / on_boss_engaged / on_boss_victory / _on_victory / _on_player_died / _on_retreat_confirmed / _on_dock_docked / _ready / _on_achievement_unlocked） |
| 轮换算法 | `scripts/survivor/boss_registry.gd`（BOSS_ROTATION / pick_for_map / pick_by_rotation / rotation_candidates） |
| history 注入 | `scripts/events/boss_encounter_event.gd`（_init 第 5 参 + _start） |
| 奖池门控 | `scripts/survivor/zone_data.gd` `_assign_reward` 武器子池 + `survivor_mode` `_build_reward_roll_context` |
| 删存档登记 | `scripts/main_menu.gd` `_on_reset_save_pressed` |
| 单测（bench key `career_archive`） | `scripts/tests/test_career_archive.gd`（注册在 `scripts/bench/bench_runner.gd` UNIT_TESTS） |
| **敌人图鉴条目注册表**（§2.6） | `scripts/meta/enemy_codex.gd`（EnemyCodex：ENTRIES / SECTIONS / defeat_count / progress）——**加新敌人在此加一行** |
| **游戏信息手册注册表**（§2.7） | `scripts/meta/game_info_codex.gd`（GameInfoCodex：ENTRIES / SECTIONS / body_key 的 tip 复用）——**加机制说明在此加一行** |
| 资料库页面（两分类） | `scripts/meta/archive_ui.gd` + `scenes/archive.tscn`；主菜单入口 `scripts/main_menu.gd` `_on_archive_pressed` |
| 战术地图小技巧轮播（手册复用源） | `scripts/survivor/tactical_map.gd` `_TIP_KEYS` |
| 机型标识唯一源 | `scripts/survivor/survivor_spawner.gd` `type_tag_of()` / `all_type_tags()` |
| i18n | `i18n/translations.csv`（ACHIEVEMENT_UAV_HUNTER_TOAST / CODEX_* 段） |
| reference 索引行 | code-index.md「生涯档案」段 / script-index.md meta 组两行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-26 | 1 | 初稿（档案 schema + BOSS 轮换 + uav_hunter 成就样板）；同日按 §6 全量落地代码，--bench=career_archive 31 断言 + 回归门 39 项 PASS。差 §0 用户语义确认与 §5 playtest 项 |
| 2026-07-28 | 2 | §0 全表（Race=Wraith / 打过=击败 / 撤离=撤退结算 / 0.5 推进概率等 8 条）获用户批准（"可以执行"）；余项仅 §5 playtest |
| 2026-07-28 | 4 | **游戏信息手册**（用户："再写一个档案库写清所有机制——左键右键每个操作、E 加力模式等；Tab 的小技巧也收进来；与敌人图鉴分成两个分类"）：新增 §2.7——资料库改**双分类页签**（敌人图鉴 / 游戏信息），手册 7 分组 47 条覆盖鼠标·键盘·小队指挥·飞行·武器·一局流程·情报；**Tab 小技巧不复制文本、由条目 `tip` 字段复用译文**（单一数据源，bench 断言对齐轮播表）。顺带修 `TACTICAL_TIP_WEAPON_SWAP` 过期键位（[1/2]→[T]）。**新增 CSV 列数断言**并据此修复 36 行含逗号未加引号的译文错位（含 2 行历史遗留）。career_archive 48 断言 + 回归门 42 项 PASS |
| 2026-07-28 | 3 | **敌人图鉴**（用户："档案显示所有敌人，包括小杂兵和 BOSS，打败过就有计数"）：新增 §2.6 呈现层规格——原「王牌档案」页泛化为全局图鉴（34 条目 / 5 分组 / 统一"击败即解锁"语义 / 右侧 ×N 计数 / 收录进度）；§2.2 记录表补**逐型地面计数** `ground_by_type`（sam/aa/radar，旧档兼容）与王牌 encounter/defeat 行；收录边界显式裁定（王牌/BOSS 专属机型与舰船不单列）；防腐烂断言 13 条入 bench（career_archive 44 断言 PASS，回归门 41 项 PASS）。附带 `type_tag_of()` 静态化收口机型标识 |
