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
| [systems/weapon-employment-doctrine](systems/weapon-employment-doctrine.md) | system | draft | — | 武器使用准则：僚机多武器时"什么距离用什么武器"的竞选规则（距离带+滞回+远程优先）、全武器统一"机头指向路径提前点"瞄准语义（锥角=纪律严格度，电磁炮 ±3° 最苛）、机动跟随主武器（railgun LINE_UP 直线充能 intent）。激活休眠的 EquipmentParams.desired_engagement 投票骨架。**待用户定稿** |

| [systems/combat-effectiveness-metrics](systems/combat-effectiveness-metrics.md) | system | draft | ✗ | 战斗效能评估：交战记录 4 层指标（转化 FSR/执行 hit_rate/结果 TTK/对手规避+CapIndex 差距）+ 两轴 Offense/Defense 评级 + bench 对位矩阵；核心解决"快机打不中慢直升机≠直升机强"。**仅 §1~§6 草稿，待 review** |
| [systems/aircraft-evolution](systems/aircraft-evolution.md) | system | wip-design | ✗ | 战区结算 + 宝可梦式机型进化（F-15 基底 / F-16 降分支）+ Tab 结算坞 + 三选一(武器/红技能/进化) + 槽位装备继承 + 航母外援。**高层骨架，进化树内容/数值待用户补** |
| [systems/aircraft-evolution-tree](systems/aircraft-evolution-tree.md) | system | draft | ✗ | 进化科技树具体名单：5 档位（四代→四代半→五代→六代→虚构超凡）/ 每架 ≥3 出口全列 / 苏美欧中系穿插 / 剔除侦察机 / Su-57·F-22 同档平级 / 档位 5 虚构期待机 7 款占位（X-09/X-13/X-21/X-44/X-77/X-90/AX-00）。**名单/门槛/虚构名待定** |
| [systems/squad-upgrade-ownership](systems/squad-upgrade-ownership.md) | system | draft | ✗ | 升级归属**绑机型**：三归类字段(ownership/affinity/flavor/inheritable) + 全 41 技能归类总表(GLOBAL/GUN-A10/EW-F16/MISSILE/UNIVERSAL/HARDWARE) + 同型共享/战损不丢 build + 僚机生产+build 重放 + 编队上限 9/1-9 接管 + Session 内 Roguelike。**待 review；待拍板硬件继承 A/B** |

| [systems/combat-feed](systems/combat-feed.md) | system | done | ✅ | 战况栏 / kill feed：左上角实时"谁用什么武器击坠谁"，最新 5 条、HOLD 5s+淡出 1.5s、友绿敌红配色；EventLogger.kill_recorded 信号桥接、复用既有击杀归因。同批放宽镜头缩放上限 ZOOM_MIN 0.4→0.2 |
| [systems/meta-progression](systems/meta-progression.md) | system | draft | ✗ | 局内/局外彻底分层，轴=**槽位装备 vs 玩法深度**：局外（功勋持久）解锁机型武器/装备 loadout（A-10 火箭/X-02 电磁炮）；局内（roguelike 清零）= 提升玩法深度的机制 + 进化（每局从初始机起，局外令进化更平滑）。**方向 stub；货币/进化已定，局内深度内容待用户推敲** |

| [systems/ace-system](systems/ace-system.md) | system | draft | ✗ | 王牌系统：长机当前机=ACE（开局默认）；进化分王牌/僚机两类对象（王牌线=进化树深度 / 编队线=数量+品质+loadout 轻成长）；ACE 阵亡由击坠最高者继任、旧加成不继承。调和"单机英雄进化 vs RTS 编队"。**核心已定，资源分配/继任边界待推敲** |

| [systems/map-expansion](systems/map-expansion.md) | system | draft | ✗ | 地图扩展 + 镜头再拉远：世界尺寸单常量主开关（30×30km→N）；Tab 全息图/相机/雷达/spawner 均数据驱动自动适配；硬编码点=战区坐标+手画地理+出生偏移；需图标 LOD。**建议编辑器先行、战区 JSON 化** |
| [systems/ugc-editor](systems/ugc-editor.md) | system | draft | ✗ | 游戏内 UGC 编辑器 + 创意工坊：飞机/地图/编队可行性高（params 纯数据、JSON+user:// 惯例现成）；安全红线只收 JSON+数值围栏；P0 数据化→P1 地图编辑器（兼扩图工具）→P2 飞机→P3 编队→P4 本地分享→工坊（GodotSteam/mod.io） |

| [systems/player-aircraft-power-curve](systems/player-aircraft-power-curve.md) | balance | draft | ✗ | 玩家机战斗力曲线规范：F-14 最弱锚点 / 档位预算 100-115-130% / 同类进化逐轴不倒退 / 单 tradeoff 轴 / 雷达走廊 2800-5000 / 12 机有效值矩阵 / resources/player/ 数据解耦（mult 归 1，敌机 enemy_* 独立）。**矩阵待用户 review 后实装** |

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
- [ ] **weapons/** —— 各武器 GunParams/MissileParams/RocketParams（现在 .tres）。已完成：qmaam（副槽）
- [ ] **aircraft/** —— 各主角机型档案（现走 PlayableAircraft 注入）。已完成：a-10（待补 f-16/f-14/x-02）
- [ ] **bosses/f-47** —— F-47 王牌狙击小队（现 enemy-index 有摘要，无完整 spec）
