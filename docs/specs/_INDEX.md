# Specs Index —— 设计单一数据源（SSOT）总表

`docs/specs/` 是 AGL 的**设计权威源**。每个机制 / 敌人 / 武器 / 技能 / BOSS / 系统都有一份 spec，
完整写下**数值 + 行为 + 公式**，使得"代码全丢、只看 specs 也能一比一重建游戏"。

## 与其它文档的分工（硬约定）

| 层 | 回答 | 权威性 | 行号 |
|---|---|---|---|
| **`docs/specs/`**（本层） | 做什么 + 为什么 + **全部数值/公式/行为** | ✅ 权威源 | ❌ 禁止 |
| `docs/reference/`（enemy-index / script-index / code-index） | 代码**在哪** | 易腐烂的指针 | ✅ 这里放 |
| `docs/systems/` | 跨系统的架构叙述 / 流程 | 叙述，非数值权威 | 少量 |
| `docs/changelogs/` | 某次改动**当时**做了什么 | 历史快照 | 可有 |

迁移方向（进行中）：**把设计意图与数值从 enemy-index / systems 抽进 specs；索引退化为纯指针表。**
新内容一律 **spec 优先**（先写 spec → 定稿 → 按 §6 实现计划派生代码）。

## 工作流（doc → task pipeline）

```
设计  ── 复制 _TEMPLATE.md → 填 §1~§5 → status: draft → review → approved
执行  ── 按 §6 实现计划逐条打勾，代码从 spec 派生（执行 cheap）
收尾  ── 跑 §5 验收 → 更新 §7 锚点 + 同步 reference 索引 → 写 §8 变更记录 → status: done
```

**重建测试**：每份 spec 的 `reconstruction_complete` 字段，标记它是否已能脱离代码重建。
目标是全表为 ✅。

## 状态图例

`draft` 起草中 · `approved` 设计定稿待实现 · `in-progress` 实现中 · `done` 已落地并验收 · `superseded` 被取代

---

## 总表

| Spec | kind | status | 重建完整 | 覆盖范围 |
|---|---|---|---|---|
| [bosses/mother-goose](bosses/mother-goose.md) | boss | done | ✅ | Mother Goose 飞行翼母舰：10 挂点 + 弱点、JAM 力场、指定猎杀、UAV 蜂群、VLS 齐射、MQ-X 精英 |
| [enemies/af-03](enemies/af-03.md) | enemy | done | ✅ | AF-03 电磁炮狙击无人机（Schemer）：railgun AT_FIRE_TIME 预测狙击 + BVR 5-8km 打带跑 |
| [skills/bloodlust](skills/bloodlust.md) | skill | done | ✅ | BLOODLUST 嗜血家族：击杀/受伤触发 8s buff，基础回血 + 血怒护甲修饰卡（减伤/拉G/加速，经 SEAM-001 注入） |
| [weapons/qmaam](weapons/qmaam.md) | weapon | done | ✅ | QMAAM 副武器槽近距格斗弹：宽锁定锥 70° + HOBS + 60G 发射后不管，自动补刀狗斗侧面目标；副槽机制完整 |
| [weapons/gun-burst-fire](weapons/gun-burst-fire.md) | weapon | in-progress | ✅ | 敌我飞机机炮匀速滴弹改梭射：burst_count=10/梭，梭内 3.3× 密度 + 梭间 CD，平均射速守恒（DPS 不变）；梭承诺根治"窗口一闪只漏一发孤弹"；--bench=gun_burst 回归门 |
| [systems/survivor-loop](systems/survivor-loop.md) | system | done | ⚠ partial | 生存模式核心循环：8 分钟战区→BOSS 阶段、Token 经济、加权刷怪、XP/升级、出界时间税；★含扩展接入图 |
| [aircraft/a-10](aircraft/a-10.md) | aircraft | done | ✅ | A-10 Warthog 主角机：厚甲无导弹、Hydra 70 自动扇形火箭、漂浮雷、实验忠诚僚机变体；档案注入完整 |
| [systems/event-system](systems/event-system.md) | system | done | ✅ | 剧本系统：GameEvent + EventDirector + AIDirective（6 verb）；BOSS 事件三相；★含扩展接入图 |
| [systems/map-system](systems/map-system.md) | map | done | ⚠ partial | 地图系统：±7500px 边界 + 手画地理 + OSM 烘焙 + 底图三层；陆判 API；★含加新地图接入图 |
| [skills/buff_duration_rebalance](skills/buff_duration_rebalance.md) | balance | done | ⚠ 回顾型 | 自身 buff 时长统一拉到 8s（INVUL/OVERLOAD/FRENZY） |
| [systems/squad-control-switching](systems/squad-control-switching.md) | system | in-progress | ✗ | 操控切换：数字键 1-4 接管号机（squad_slot 稳定）+ set_leader 换帅 + manual_control 休眠 AI + 打完再归队 + 白底/击落接管。**代码全落地，差 §5 playtest** |
| [systems/squad-cohesion](systems/squad-cohesion.md) | system | in-progress | ✗ | 小队凝聚学说（友+敌）：焦点开火（地/船/BOSS 饱和、飞机留自由机互掩）+ 维持阵型 + 防游走 leash + GUARD_REAR 守后 + 敌方成建制/随机阵型。**阶段 1-4 主体落地，差联调/调参/§5** |
| [systems/squad-ai-escort](systems/squad-ai-escort.md) | system | draft | ✗ | 僚机护卫：反杀咬长机者（engaging_me 定向扩展）+ 近长机评分加权。**仅阶段 1-2；守后半球由 squad-cohesion GUARD_REAR 覆盖，escort 自身阶段 3-5 未做** |
| [systems/rts-command](systems/rts-command.md) | system | done | ✅ | RTS 指挥（独立模块 SquadCommandController + 参数 Resource）：战术地图航点/战区边缘巡航 + 到点自动交战 + **玩家命令逐机持久铁律**（commanded_target 跨 1-4 切控、AI 不得覆盖）+ 右侧开关；自由僚机切目标细则归 target-engageability-selection |
| [systems/target-engageability-selection](systems/target-engageability-selection.md) | system | in-progress | ✗ | 目标选择改"可命中性"评分：对正度/包络/锁定(封顶)/邻近四因子 + 队友超杀让路 + 守后优先(rear_threat_score)；根除锁定 runaway。**代码落地 + 单测 7/7，差生存 playtest 调参** |
| [systems/wingman-escort-evasion](systems/wingman-escort-evasion.md) | system | in-progress | ✅ | 僚机护卫规避：玩家按 E 时僚机不再无脑散开——被真威胁才逃，否则召回编队待命 + 投护卫 flare 替长机挡追它的导弹（escort_cover_active 与 evasion_mode 解耦；护卫 jam=0.70×近度，范围 800m）。**代码落地、flare bench 9/9，差 §5 playtest** |
| [systems/weapon-employment-doctrine](systems/weapon-employment-doctrine.md) | system | done | 2026-07-05 | 武器使用准则：僚机多武器时"什么距离用什么武器"的竞选规则（距离带+滞回+命中率优先）、全武器统一"机头指向路径提前点"瞄准语义（锥角=纪律严格度，电磁炮 ±3° 最苛）、机动跟随主武器（railgun LINE_UP 直线充能 intent）+ 电磁炮承诺弹道（指示线=发射线）。验收：MRM 命中 44%→79%（log 175843） |
| [systems/joust-attack-run](systems/joust-attack-run.md) | system | done | ✅ | 攻击跑行为原语：RUN_IN 对准进入火力窗（两段速）→ BREAK 脱离拉开 → 折返循环；包络动态读装备 live params；修 MG 电磁炮 UAV"切向轨道 vs 机头对准"死锁（log 183044 全场 0 充能）+ 骑士型 Lancer（J-7/F-104/F-100/MiG-31）打带跑统一实现（取代 engage_duration 定时器）。bench 7/7 + playtest 手感确认（2026-07-05） |
| [systems/command-wheel](systems/command-wheel.md) | system | in-progress | ✗ | 命令轮盘：按住左键拖拽呼出 marking menu（位置=参数/方向=动词，0.3x 子弹时间）。**操作语法：单点=只操控自机 / 轮盘=永远全队广播**。小队命令轮盘(按空地)=紧急集合+撤离此区(圈内径向散出 3km+20s 限时禁入圈、圈外不生效)+防守此区(3km 圈只打圈内、出圈停追不散阵，_tick_guard 已实装)+开关（自动交战/高度偏好三态循环/自动发射候选）；攻击轮盘(按敌机)=姿态（保持距离 STANDOFF 打带跑/突击 ASSAULT 锚定）×火力分配（集火=同目标+包围轴分离≥45° / 分火=锚点目标池内各自接敌+超杀让路）×阵型纪律开关，挂 commanded_target 铁律；**最新输入覆盖移动命令（单点→自机/轮盘→全队）**；移动指示线只画当前操控机（现状闪烁/僚机误显示 bug 列阶段 1 前置修复）；二级面板=开关显式选项（拉深选值）；左上红色取消槽（两轮盘统一）；悬停范围圈（撤离3km/防守3+1km等世界圈，仅空间语义命令）+ 轮盘下方教程说明条（WHEEL_TIP_* 三语）+ 激活压暗35% + 攻击轮盘目标高亮层；导弹/机炮优先搁置、高度"默认"三态评估后搁置；开关长期收束进轮盘。**代码全落地（阶段 1-4 + 收尾批）**：手势+执行端+二级面板+取消槽+范围圈+说明条+防守拦截+姿态分化[空中 joust 打带跑/面目标 surface pass]+火力分配[FOCUS 包围轴 ≥45°/SPREAD 池内各自接敌]+集合/撤离全力加速（command_sprint ×1.4 accessor）+撤离 20s 禁入区（决策过滤+圈框倒计时）+自动发射队级广播；--bench fire_alloc 15 / wheel_orders 12 / surface_pass 20 断言，**回归门 20 项 PASS**。**只差 playtest** |
| [systems/formation-discipline](systems/formation-discipline.md) | system | draft | ✗ | 阵型纪律与齐射：队级开关 FREE 自由散开（=现状，多角度包围）/ TIGHT 紧密队形（整队进入→齐射窗口 1.5s→整队拉开的队级 STANDOFF 循环；锁定提前 1.3×、禁补射"宁可少打一发也不脱队"、齐射距离走武器准则包络带）；ASSAULT 缠斗临时豁免（已确认）；齐射接火力分配（FOCUS 饱和/SPREAD 一波清一片）；入口=攻击轮盘右槽+HUD 第 6 toggle（长期收束轮盘）。**待 review** |

| [systems/combat-effectiveness-metrics](systems/combat-effectiveness-metrics.md) | system | draft | ✗ | 战斗效能评估：交战记录 4 层指标（转化 FSR/执行 hit_rate/结果 TTK/对手规避+CapIndex 差距）+ 两轴 Offense/Defense 评级 + bench 对位矩阵；核心解决"快机打不中慢直升机≠直升机强"。**仅 §1~§6 草稿，待 review** |
| [systems/aircraft-evolution](systems/aircraft-evolution.md) | system | wip-design | ✗ | 战区结算 + 宝可梦式机型进化（F-15 基底 / F-16 降分支）+ Tab 结算坞 + 三选一(武器/红技能/进化) + 槽位装备继承 + 航母外援。**高层骨架，进化树内容/数值待用户补** |
| [systems/aircraft-evolution-tree](systems/aircraft-evolution-tree.md) | system | draft | ✗ | 进化科技树具体名单：**5 档恢复（2026-07-19）**T1 起手四选一（+幻影 III）/T2 四代半/T3 五代/T4 现实六代（YF-23/FCAS/GCAP/J-36）/T5 原创超凡（X 系+AX-00 压轴 LV26）/ 每架 ≥3 出口 / 相邻环横跨 / 苏美欧中穿插。**§4 出口重连待 power-curve v7 矩阵定稿后一并做** |
| [systems/evolution-attribute-gates](systems/evolution-attribute-gates.md) | system | draft | ✗ | 进化属性门槛 v3（点数=LV/3，**全局内每局清零**）：**每 3 级卡片三选一=三轴各一张，选卡=技能+1 点**（满级 8 点）；守门 T2/3/4/5=1/2/4/5、制空合计门（1/3/5/6且各2）、同族−1、特例 5 条（AX-00 各2且合计7）；**里程碑成长线**每线 2/4/6/8 档+10 预留（**纯属性无词条无技能**；属性池宽：炮伤/射程/备弹/G/爬升/flareCD/锥角等；递减陡 100/60/25/15 → 均衡 3/3/2≈300 > 专精 8/0/0≈200，**里程碑拉平衡、门槛拉专精**双向张力；**按起手机分化**：基准表+逐机覆写，四机分表用户后续平衡）；**点数/里程碑/卡片技能记玩家层，换型重放**（根治自然成长路径依赖，对齐 modifier-pipeline）；Tab 常驻三轴面板；进化=LV 且 属性双门。**数值待 review** |
| [systems/inrun-weapon-inventory](systems/inrun-weapon-inventory.md) | system | draft | ✗ | 局内武器库（2026-07-19 用户重点调整）：特殊武器（电磁炮/激光/忠诚僚机/QMAAM/漂浮雷）=**局内玩家外部装备，到手即永久、换机/进化全继承（含强化）**；获取=签名机型首驾入库+战区奖励；底线武器（机炮/导弹/flare）仍随机体；**作废**"武器绑机型不继承"（06-28）与 meta-progression"局外多武器 loadout"；重放与属性门槛玩家层同机制。开放点：火箭归类/挂载上限/重复补偿 |
| [systems/squad-upgrade-ownership](systems/squad-upgrade-ownership.md) | system | draft | ✗ | 升级归属**绑机型**：三归类字段(ownership/affinity/flavor/inheritable) + 全 41 技能归类总表(GLOBAL/GUN-A10/EW-F16/MISSILE/UNIVERSAL/HARDWARE) + 同型共享/战损不丢 build + 僚机生产+build 重放 + 编队上限 9/1-9 接管 + Session 内 Roguelike。**待 review；待拍板硬件继承 A/B** |

| [systems/combat-feed](systems/combat-feed.md) | system | done | ✅ | 战况栏 / kill feed：左上角实时"谁用什么武器击坠谁"，最新 5 条、HOLD 5s+淡出 1.5s、友绿敌红配色；EventLogger.kill_recorded 信号桥接、复用既有击杀归因。同批放宽镜头缩放上限 ZOOM_MIN 0.4→0.2 |
| [systems/meta-progression](systems/meta-progression.md) | system | draft | ✗ | 局内/局外彻底分层，轴=**槽位装备 vs 玩法深度**：~~局外（功勋持久）解锁机型武器/装备 loadout~~（**2026-07-19 局外多武器作废**，武器改纯局内继承 → [inrun-weapon-inventory](systems/inrun-weapon-inventory.md)；局外层新用途待本 spec 自身修订）；局内（roguelike 清零）= 玩法深度 + 进化 + 三轴属性/武器库。**方向 stub 待重写** |

| [systems/ace-system](systems/ace-system.md) | system | draft | ✗ | 王牌系统：长机当前机=ACE（开局默认）；进化分王牌/僚机两类对象（王牌线=进化树深度 / 编队线=数量+品质+loadout 轻成长）；ACE 阵亡由击坠最高者继任、旧加成不继承。调和"单机英雄进化 vs RTS 编队"。**核心已定，资源分配/继任边界待推敲** |

| [systems/zone-reward-docking](systems/zone-reward-docking.md) | system | in-progress | ✅ | 战区奖励与停靠结算（修订 aircraft-evolution v2 结算流）：攻克=全队满血+奖励入库，进化/领奖必须**飞到停靠点减速着陆**（≤250km/h 持续 1s；固定机场 3 处：羽田/木更津/調布，南半图=航母价值区）；三类实体奖励（航母限 2 次登舰·击沉清零·用尽南撤 / ACE 升级+同型僚机爆出·满编 9 降级 / 副系统武器：忠诚僚机·尾部漂浮雷·QMAAM）按难度 roll、Tab 圈下前置显示；轰炸机/直升机逃跑组带 2~4 机护卫（普通 XP）；XP 升级现状不动。**阶段 1~6 代码落地 + parse 回归绿，差 playtest** |
| [systems/60km-density-pass](systems/60km-density-pass.md) | balance | in-progress | ✅ | 60km 密度调优（playtest 反馈"敌人少"）：战区半径 A/C/D 3500·B 3000·E 2500 + 盘旋环随半径撑开；任务规模（地面 TGT 3+3/4+4/6+6、中队 4/5/6、驻守预算 12/22/42×1.10^L、精英护卫 6-10）；丰富化（★★+ 雷达站 TGT 削预警层次、中队长机高一档）；热度（token 8+1.8L cap55、间隔 32→18、上限 36/48、驻防 3 队、hunter max(3,2+L/2)）；附带修教程轰炸机锚点（扩图后 10.9km 远→出生点前 3km 派生）。**回归绿，差 playtest+压测** |
| [systems/reinforcement-ingress](systems/reinforcement-ingress.md) | system | in-progress | ✅ | 增援入场：旅途增援改"边缘中队涌入 → 中央锚点驻空绕环 → token 饿着时 EGRESS 物理飞离（被打回头应战）+ 开局驻防 2 队"，根治双根因（离屏刷怪无来路 + FAR_FREEZE 750px 刷出即冻结原地杵）；hunter/token/选型不变；含离屏冻结豁免策略（transit/egress 豁免、onstation 闲置可冻）。**阶段 1~4 代码落地 + 无头回归绿，差 playtest/性能验收** |
| [systems/aa-fire-awareness](systems/aa-fire-awareness.md) | system | draft | ✗ | 僚机对地面机炮火力警觉：①被 AA/CIWS 机炮命中 → 打断 SETUP/RUN 强转 EGRESS + 机头转出 45° 后 AB 全速脱离（EGRESS 加速为敌我通用改进）；编队/巡航被打不脱队只 AB 直线冲刺 2.5s；②STANDOFF inner 环抬到目标对空火力半径 ×1.25（CIWS 舰 2200→2500m）+ F-Pole：弹在飞/TEAM_OVERKILL 时不压入、环外 crank 等命中。单杠杆=只对"被命中"反应，不做火力圈预判扫描。**待 review** |
| [systems/surface-attack-pass](systems/surface-attack-pass.md) | system | in-progress | ✅ | 对面攻击 pass 循环：地面/舰船静止目标做俯冲攻击跑（SETUP→RUN→EGRESS + 最小转弯半径守卫，根治"机炮打 SAM 原地绕圈"死锁）；姿态 STANDOFF（导弹远距 standoff 环脱离不进 AA）/ ASSAULT（机炮贴地俯冲穿越）分流，默认由武器竞选推导（有弹保持距离/无弹机炮），预留 command-wheel 姿态覆盖钩子。相位状态位走 `_apply_tactical_plan` 回写、planner 保持纯函数。**全量落地 + 无头行为 sim `--bench=surface_pass` 9/9 + bfm_intent 102/102 + all 18 项绿，差生存 playtest** |
| [systems/map-expansion](systems/map-expansion.md) | system | in-progress | ✗ | 地图扩展 + 战区重排（**60×60km ×2 已手改落地**，用户二次复审决定保留）：主开关/出生点/60km 重烘焙（矢量+过渡底图）/战区 ×2 重排（B 落湾里经 land_mask 网格扫描修正 (6000,-11000)）；无头回归 `tests/test_map_expansion.gd` 全绿（几何 15/15 + 陆地占比 + BOSS 锚点）。**差 playtest（≥3 战区/局节奏）；编辑器整合退为后续 converter 吃现状，PNG=过渡资产** |
| [systems/ugc-editor](systems/ugc-editor.md) | system | draft | ✗ | 游戏内 UGC 编辑器 + 创意工坊：飞机/地图/编队可行性高（params 纯数据、JSON+user:// 惯例现成）；安全红线只收 JSON+数值围栏；P0 数据化→P1 地图编辑器（兼扩图工具）→P2 飞机→P3 编队→P4 本地分享→工坊（GodotSteam/mod.io） |

| [systems/player-aircraft-power-curve](systems/player-aircraft-power-curve.md) | balance | draft | ✗ | 玩家机战斗力曲线规范 **v7 五档 41 机**：F-14 最弱锚点 / 预算 100-112-125-138-150% / LV 带宽 1·4~9·10~15·16~20·21~26（空档仅 LV15，AX-00 压轴 LV26）/ 欧系 2→11 款（幻影 III 起手/幻影 2000/鹰狮 C·E/狂风/雷/鹞/FCAS/GCAP）/ 同类逐轴不倒退 / 单 tradeoff / 王冠互斥 / 档内 ±3% 内插平滑 / resources/player/ 数据解耦。**矩阵待用户 review 后实装** |
| [systems/engagement-discipline](systems/engagement-discipline.md) | system | in-progress | ✅ | 交战纪律（playtest 220858 派生）：A 敌人**无 combat_target → 停火**（去掉 auto_gun_scan 兜底扫 all_units，根治"无意图机炮背刺路过玩家"，人类机独立扫射不变）；B AI 友军**反平面同向缠斗**——对硬盘旋目标(bank>60°)+自己磨到角点(≤corner×1.08)+aspect仍高(>70°)+已兜≥2s → 能量触发 BOOM_ZOOM_OUT 脱出重建能量再攻（仅 AI，不拽人类长机），补 5b 时间触发之外的能量触发。单测 92/92（+2 新 case）。**差 playtest；2s range-grace 脱战循环留后续** |
| [systems/global-awareness-roe](systems/global-awareness-roe.md) | system | in-progress | ✅ | 全图察觉与交战规则（ROE，v2 按 review 简化）：**中队级感知**（感知圈=长机雷达距离全向 + 被打即察觉 + 战区 datalink，15s 记忆；中队三字段 posture/aware/squad_target，不逐机算）+ 任务姿态五型（守区 leash=区+1500m 出圈停追 / 巡逻 leash 6km 含 30% 线路巡逻 / 狩猎全知 / 转场 / 撤离）+ **热度即难度**（heat 0-100 纯内部量不上 HUD，唯一输出 hunter 配额 round(2+10h/100)，静默基线复刻既有曲线、等级地板 min(75,5L) 载难度爬升）+ **第三方事件化三类**（护送直升机 A→B +40 功勋/架 / 机场防空 SAM+AA×3 停靠机场 / AWACS 南带往返 8km buff 区锁定×3·导弹×1.25；ALLY(2) 不可控 0 XP，航母存量收编）+ 阵营色板统一（FactionPalette **蓝=玩家直属/绿=中立·第三方**/橙红=敌；机体无 PNG，敌机 icon_color 审计 ×15 换暖色）+ IFF 收口（is_hostile_to 单 API，四类硬编码迁移清单）。**阶段 1~5 代码全落地**（roe 单测 33/33 + 回归门 21 项 + 30s 冒烟绿；落地修订 §8-v3：posture 派生制/事件察觉 2s 粒度/守区战区聚合/AWACS 无 flare/航母收编暂缓），**差 playtest + 压测** |

<!-- 新增 spec 后在此追加一行。保持按 kind 分组、最新在各组顶部。 -->

---

## 待补 specs（重建缺口清单）

> ✅ **模板验证阶段已完成（2026-05-30）**：8 种 kind（boss/enemy/skill/weapon/system/aircraft/event/map）
> 各有 ≥1 个 reconstruction-grade 样板，模板与工作流已跑通。下一阶段是**批量铺开**（逐个把现有内容转 spec）。
>
> 以下内容目前**只在代码里**，是"靠文档重建"的漏洞。按优先级补 spec。

- [ ] **enemies/** —— 22+ 敌机逐个建 spec（数值现散在 .tres + enemy-index 表 + survivor_mode.gd 刷怪逻辑）。已完成：af-03
- [x] **systems/survivor-loop** —— 时间制战区循环：8 分钟阶段、加权抽取、出界回血时间税（含扩展接入图）✅
- [x] **systems/event-system** —— GameEvent + EventDirective 剧本系统（含扩展接入图）✅
- [x] **systems/map-system** —— 地图边界 + 地理 + 三条流水线（含加新地图接入图）✅
- [ ] **skills/** —— 20+ 升级技能逐个建 spec（效果逻辑在 skill_hooks.gd，数值在常量 + i18n）
- [ ] **weapons/** —— 各武器 GunParams/MissileParams/RocketParams（现在 .tres）。已完成：qmaam（副槽）、gun-burst-fire（机炮梭射节奏）
- [ ] **aircraft/** —— 各主角机型档案（现走 PlayableAircraft 注入）。已完成：a-10（待补 f-16/f-14/x-02）
- [ ] **bosses/f-47** —— F-47 王牌狙击小队（现 enemy-index 有摘要，无完整 spec）
