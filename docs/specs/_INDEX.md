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
