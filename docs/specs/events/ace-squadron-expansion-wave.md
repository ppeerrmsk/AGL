---
id: ace-squadron-expansion-wave
kind: event
status: done
schema_version: 1
spec_version: 4
owner: noelu / Codex
depends_on: [ace-squadron-tier, ace-support-squadron, events/the-crucible]
reconstruction_complete: true
---

# 王牌中队扩编批次（11 队）

> 把三支旧案与八支新案一次性做成常规王牌轮换，并全部投入沙漠决战 The Crucible；强度处于同一档，但每队只用一个清楚可读的主题改变玩家决策。

## 1. 设计意图（Why）

- **体验目标**：扩充中期强敌的战术题库，避免王牌只剩机型与人数差异；玩家见到代号、编成与动作后能辨认主题并调整目标顺序。
- **Litmus 自检**：每队只有一个主杠杆；一发击落不加血；主题通过高度、站位、目标分配、攻击接力或队形空位直接反馈；所有队共享 60–90 秒标准化击破时间。
- **反模式规避**：无等级膨胀、无随机免伤、无每机常驻新节点、无不可见判定。队级主题在 2 Hz 集中更新；The Crucible 内由统一仇恨导演保留目标所有权。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 统一合同

| 字段 | 值 |
|---|---|
| 调度 | 全队 `pool_time=210 s`，进入两槽无放回常规轮换；每局最多两支 |
| 生存 | 非 BOSS 王牌一发击落；默认每机 1 枚必躲 flare；IDO 例外为全队共享 2 次 |
| AI | `0.94–0.96`；机炮闪避默认 `0.20`，IDO `0.10` |
| 奖励 | 每机 80–120 XP；全灭沿用王牌事件 `game_time −60 s` 与生涯留档 |
| 更新频率 | 主题决策 `2 Hz`；LASH 接力 `6 s`；UNDERTOW 换层 `10 s` |
| The Crucible | 11 支扩编队全部加入；连同既有队与 Hound-1/2，总名册为 18 队 73 架；同屏最多 3 队并按全灭空位接力；保留高 LOD |

### 2.2 编成、包装与强度

| id / 代号 | 编成与固定呼号 | 主色 | 主题 | DU + access = TTK |
|---|---|---|---|---|
| `moirai` / MOIRAI | F-22 Clotho、F-35 Lachesis、YF-23 Atropos | `#C740B8` | 纺线/丈量/剪断固定分工：远距/近距/远距 | 9 + 25 s = 70 s |
| `lash` / LASH | Su-57×4：Handle/Crack/Whipcrack/Tip | `#ED3361` | 每 6 s 轮换唯一贴身“鞭梢”，其余保持远距张力 | 10 + 20 s = 70 s |
| `ido` / IDO | Sentinel A639；MQ-109×2；MQ-110×2；MQ-111；MQ-112；MQ-X2 Rootnode | `#6B5CF2` | 八节点网络，全队共享 2 次 flare；任一成员可消费并同步余量 | 10 + 20 s = 70 s |
| `undertow` / UNDERTOW | Typhoon×3：Wavecrest/Current/Trench | `#5747D1` | 高/中/低三层链，每 10 s 循环换层 | 9 + 25 s = 70 s |
| `croupier` / CROUPIER | F-15E×2 House/Pitboss；Su-34×2 Blackcard/Redcard | `#D12E85` | 把玩家存活单位轮流发给不同成员，主动拆散玩家队 | 8 + 30 s = 70 s |
| `tallyman` / TALLYMAN | Gripen E×4：Ledger/Debit/Credit/Balance | `#AD389E` | 2 Hz 核对 HP 比例，全队追杀最虚弱玩家机 | 8 + 30 s = 70 s |
| `palimpsest` / PALIMPSEST | F-86 Sabre、F-104 Century、F-4E DoubleUgly、F-15C FourthGen | `#944CC2` | 四代机各守一种纯战法：近战/掠袭/远距/近战 | 8 + 30 s = 70 s |
| `quorum` / QUORUM | Rafale Motion、Typhoon Second、Gripen E Veto | `#B840A6` | 三机齐全时一致锁长机；跌破三机后分散、转个人攻击 | 9 + 25 s = 70 s |
| `deadeye` / DEADEYE | Viggen×2 Gunsight/Deflection；Tornado×2 MilDot/Fall | `#E04075` | 成员轮流分配玩家目标，从两种机型/距离形成交叉火力 | 8 + 30 s = 70 s |
| `mirror` / MIRROR | F-15 S/MTD×3：LookingGlass/Argent/Replica | `#7A52DB` | 2 Hz 复制玩家长机当前高度层与机炮/导弹偏好 | 9 + 25 s = 70 s |
| `funeral` / FUNERAL | J-20×4：Bell/Pall/Grave/Lament | `#6B2985` | 严格葬列；出现空位后幸存者转高攻击性贴身“安魂曲” | 10 + 20 s = 70 s |

### 2.3 IDO 资源映射

| 成员 | 参数资源 | 数量 |
|---|---|---|
| Sentinel | `enemy_uav_commander` | 1 |
| MQ-109 | `enemy_uav` | 2 |
| MQ-110 | `enemy_uav_missile` | 2 |
| MQ-111 | `enemy_uav_mg_laser` | 1 |
| MQ-112 | `enemy_uav_railgun` | 1 |
| MQ-X2 | `enemy_uav_mqx` | 1 |

## 3. 行为与公式（How）

- 主题控制器以中队为单位累计 `0.5 s` 决策 tick；遍历本队存活成员，不创建 Node。
- 常规王牌战中，目标分配使用 AI 的 `TS_BOSS` 入口；The Crucible 调用同一控制器但传入 `allow_targeting=false`，只保留高度、角色和共享资源主题。
- IDO 共享 flare：初值 2；任一存活成员余量下降时，`shared=min(所有存活成员余量)`，随后把所有存活成员同步为 `shared`。
- IDO 的 MQ-X2 三发点射沿用全局机炮梭射：`is_firing` 只代表火控意图，机头发射闪光只在每发真实出膛后保留 0.06 s；team≥3 的 Crucible 实例与普通敌机共用梭后 3.0 s 停火门，不得留下常亮机头特效。
- TALLYMAN 目标：最小化 `hp / max_hp`；同值按稳定实例顺序。
- LASH 当前鞭梢：`floor(elapsed / 6) mod alive_count`。
- The Crucible 目标仇恨见 `events/the-crucible`；本批不得绕过统一目标导演。

## 4. 结构与组成（Structure）

- `AceSquadProfiles`：11 队编成、包装、DU、主题 id 的 SSOT。
- `AceSupportSquad`：消费 profile、允许 element 覆写既有参数资源，并挂一个 `AceSquadThemeController`。
- `AceSquadThemeController`：低频队级主题，不持有场景生命周期。
- Debug F5、敌人图鉴、线框徽章与三语名称/lore 全部登记；The Crucible 无线电按用户监修保持禁用。

## 5. 验收标准（Acceptance / Litmus）

- [x] 11 队可分别从 F5 强制生成，编成、呼号、武器/flare 与 profile 一致。
- [x] 11 队全部进入常规无放回轮换，且每队估算 TTK 在 60–90 s。
- [x] 每队主题状态可观察；IDO 全队合计只能消费两次 flare。
- [x] IDO MQ-X2 的点射弹与机头闪光同源；停止真实出弹后闪光在 0.06 s 内消失，FFA 阵营不绕过敌机梭射停火门。
- [x] 本批 11 队全部进入 The Crucible；加入 Hound 后总名册为 18 队 73 架，开场三队、同屏最多三队，未激活队不会被提前选中或开火。
- [x] 图鉴、徽章、名称、lore 与 11 条入场无线电三语齐全。
- [x] 性能：`battlefield_atmosphere_stress_36` 与历史 The Crucible 71 架上界 `Shadow Visual` 均保持 `frames_below_60=0`；当前正式玩法以最多三队的接力节奏运行，不以隐藏、停火或静默删除单位伪装降载。
- [x] 生命周期：全灭/撤离/场景退出后跨一帧无失效引用。
- [x] 文档、i18n 与代码锚点校验通过。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | profile、i18n、Debug、图鉴、文档校验 | 通过；本地化 1572 行四列一致，11 队图鉴译文齐全 |
| E1 聚焦 Shadow | `gun_burst`、`the_crucible`、`desert_theater` | 25/25、32/32、62/62 通过；覆盖 IDO FFA 停火门、真实出弹枪口闪光与整队离屏入场 |
| E2 集成 / 压力 Shadow | `all` | 91 组零失败；`lifecycle_gauntlet` 86/86 |
| E3 Visual | 36 混合战场 + 48/24 km 多战线 + The Crucible 正式三队 | 历史两场密集战场与本次 Crucible 最终样本均 `frames_below_60=0`；本次 Crucible avg/p1 120.00 / worst 117.92 FPS，另保留两份各有 1 个无游戏桶归因桌面尖峰的红样本 |
| E4 完整局 | 沙漠完整局 | 未验收 |

## 6. 实现计划（Task Pipeline —— 工作令）

- [x] 阶段 1：建立 11 队 profile、包装、i18n 与图鉴。
- [x] 阶段 2：实现队级主题控制器与 IDO 参数资源/共享防御。
- [x] 阶段 3：接入 F5、常规轮换与 The Crucible 17 队接力序列。
- [x] 阶段 4：自动回归与 Visual 性能验收；完整局保留给用户实机监修。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 编成/强度/包装 | `scripts/survivor/ace_squad_profiles.gd` |
| 主题控制 | `scripts/survivor/ace_squad_theme_controller.gd` |
| 生成消费 | `scripts/survivor/ace_support_squad.gd` |
| 沙漠决战 | `scripts/survivor/the_crucible_boss.gd` |
| Debug / 图鉴 / 徽章 | `scripts/survivor/survivor_debug_spawn.gd` / `scripts/meta/enemy_codex.gd` / `scripts/meta/ace_emblem_icon.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-09-02 | 3 | The Crucible 终局追加 Hound-1/2；作为 Crucible-only 第 18 队，不进入 17 支常规 Ace 轮换。 |
| 2026-09-05 | 4 | 修复 IDO MQ-X2 绘制：FFA 实例纳入敌机梭射停火门，枪口闪光改由真实出弹短窗驱动，不再随持续火控意图残留在机头。 |
| 2026-09-02 | 2 | The Crucible 改为同屏最多三队、全灭空位后逐队补入；扩编 11 队与 71 架总名册不变，无线电保持禁用。 |
| 2026-09-02 | 1 | 11 队、常规轮换、图鉴/Debug/i18n、The Crucible 接入及三组 Visual 性能门全部完成。 |
| 2026-09-01 | 1 | 用户要求把 MOIRAI/LASH/IDO 与八支新提案全部制作并装入游戏；常规轮换与 The Crucible 同步接入。 |
