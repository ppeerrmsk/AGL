# Playbook · "怎么加一个 X" 集中索引

> AGL 里"加一个新东西"的接入点分散在很多文件，本文是**入口索引**——按你想加的"X"分类，
> 列出操作清单 / 链到详细 workflow doc / 标注必读约束。每个新功能开始前先来这里看一眼，
> 避免漏接入点。
>
> 通用约束（**所有改动都要看的**）写在最后一段。

> ## ⚠ 先写 spec，再来执行（spec-first）
>
> AGL 采用 **spec-first** 工作流：本 playbook 回答**"接入点在哪、怎么执行"**；
> [docs/specs/](../specs/_INDEX.md) 才是**设计权威源**，回答**"做什么 + 为什么 + 全部数值"**。
>
> **正确顺序**：复制 [docs/specs/_TEMPLATE.md](../specs/_TEMPLATE.md) → 按
> [docs/README.md 的目录映射](../README.md#设计文档)建 spec
> → 填 §1~§5 设计定稿（status: approved）→ **再回本 playbook**按 spec 的 §6 实现计划派生代码。
> 建档当天就登记 [specs/_INDEX.md](../specs/_INDEX.md)；收尾把文件/符号指针填回 spec §7，
> 同步 reference 索引并把状态改为 done。
>
> 重建底线：spec 写**真实数值、不写行号**；"代码全丢只看 spec 能否一比一重建"是验收线。
> 样板见 [bosses/mother-goose.md](../specs/bosses/mother-goose.md)。

---

## 分类索引

| 你要加的 | 看哪一节 | 已有详细 doc |
|---|---|---|
| 普通敌机 / 王牌 / Adds 杂兵 | [§1 加敌机](#1-加敌机) | [enemy-index.md 13 步清单](enemy-index.md#创建新敌人的完整清单加一个敌人触发短语) |
| BOSS（飞机型 / 海军型 / 复合型） | [§2 加 BOSS](#2-加-boss) | spec 样板 [bosses/mother-goose.md](../specs/bosses/mother-goose.md) |
| 武器 / 装备（gun/missile/rocket/laser/railgun/flare） | [§3 加武器装备](#3-加武器装备) | 暂无 |
| 玩家技能 / 升级 | [§4 加技能升级](#4-加技能升级) | [survivor-skills.md](../systems/survivor-skills.md) |
| 主角飞机 | [§5 加主角飞机](#5-加主角飞机) | [playable-aircraft-workflow.md](playable-aircraft-workflow.md) |
| 战区任务 / 随机事件 | [§6 加事件](#6-加事件) | [event-system.md](../systems/event-system.md) |
| 地面单位（AA/SAM/雷达站） | [§7 加地面单位](#7-加地面单位) | [ground-units.md](../systems/ground-units.md) |
| 地图 / 地形 | [§8 加地图](#8-加地图) | [map-pipeline.md](map-pipeline.md) + [manual-map-editing.md](manual-map-editing.md) |
| 状态效果（FEAR / SLOW / JAM 类新型） | [§9 加状态效果](#9-加状态效果) | 暂无 |
| **无线电台词 / 剧情对话** | [§10 加无线电台词](#10-加无线电台词) | spec [systems/radio-chatter.md](../specs/systems/radio-chatter.md) |
| **演出 / 转场 / BOSS 登场镜头** | 直接看方法论 doc → | [cinematic-authoring.md](cinematic-authoring.md)（陷阱清单 + 最短路径）；数值权威 spec [systems/ui-transition.md](../specs/systems/ui-transition.md) |
| **其它跨实体系统 / 平衡批次** | [§11 加系统](#11-加系统) | [repo-layout.md](repo-layout.md) + [known-seams.md](../architecture/known-seams.md) |

---

## §1 加敌机

先建 `docs/specs/enemies/<name>.md`（`kind: enemy`）并登记总表；敌人不允许只登记
`enemy-index.md` 而没有设计 spec。

走 **[enemy-index.md 13 步清单](enemy-index.md#创建新敌人的完整清单加一个敌人触发短语)**。
要点摘要：

1. `resources/enemy_<name>.tres` AircraftParams + 必要的 gun/missile/rocket .tres
2. `survivor_mode.gd` 的 `EnemyType` 枚举 + 5 处 match 全补 case（`_pick_enemy_type` /
   `_create_enemy` 4 处 + 编队列表）
3. `survivor_data.gd` 加 UNLOCK_LEVEL / CHANCE / TOKEN_COST / TOKEN_INSTANCE_CAP 常量
4. `survivor_debug_spawn.gd` 调试面板下拉
5. 同步 `enemy-index.md` 表 + `code-index.md`

**AI Archetype 是内部词汇**：Gladiator/Lancer/Schemer 不要在 UI / Debug 面板 / display_name
里出现（user memory `feedback_ai_archetype_internal`）。

**事件 / 任务刷点必须沿玩家 heading 前方扇形**（user memory `feedback_event_spawn_ahead`）。

---

## §2 加 BOSS

先建 `docs/specs/bosses/<name>.md`（`kind: boss`）并定稿 BOSS 编成、阶段、全部数值和验收。

参考 Mother Goose 桶 A 的 6 子分支拆法（[changelogs/2026-05-08-mother-goose-boss.md](../changelogs/2026-05-08-mother-goose-boss.md)）。
按依赖顺序操作，每段独立可合 main：

### 第一步：基础设施层（共享层改动）

如果 BOSS 用挂点系统 / 弱点 / 接管伤害路由 / 免锁状态，**先改这些通用 hook**：

- `scripts/naval/mount_target.gd`：parent_ship 类型已是 CombatUnit，飞机型 BOSS 也能挂
- `scripts/aircraft.gd`：
  - `_log_unit_name` 兜底新单位类型（避免 log 出现 `@Node2D@xxx`）
  - `take_damage_at(amount, hit_pos)` 子部件命中入口（已存在）
  - `damage_router` meta 短路（注入 controller 接管多挂点路由）
  - `lock_immune_override` meta（弱点未暴露阶段维持免锁）
- `scripts/combat_unit.gd`：`fear_immune` meta（无飞行员单位拒绝 FEAR）
- `scripts/ai_controller.gd`：`no_kamikaze` meta 例外（专职近距护卫不出列）

→ **加之前先看 [known-seams.md SEAM-007](../architecture/known-seams.md#seam-007--boss-挂点系统的-parent_ship-类型耦合mother-goose-暴露)**。

### 第二步：BOSS 资源 + 武器配置

- `resources/enemy_<boss>.tres` AircraftParams 或 NavalParams（看 BOSS 类别）
- 配套武器 .tres（如 `enemy_<boss>_railgun.tres` 含 `charge_persistent` / `fire_along_nose`）
- 蜂群 / 护卫的 UAV 资源（`enemy_uav_<variant>.tres` + 装备 loadout `uav_<variant>.tres`）

### 第三步：BOSS 主体逻辑（5 个 .gd 一套）

放在 `scripts/survivor/<boss>_*.gd`：

- `<boss>_boss.gd` — `BossEncounter` 子类（飞机型）/ `BossEncounter` 子类（海军型 = CSG）
  - 实现 `spawn` / `update` / `engage` / `get_display_members` 钩子
  - 用 patrol ring / waypoint 等抽象，不写"画 boss 圈"等表现层
- `<boss>_controller.gd` — boss 子节点战斗逻辑（每帧 tick 武器 / 干扰场 / 蜂群）
- `<boss>_jam_shield.gd` — 周期机制状态机（如 COOLDOWN→WARNING→EXPANDING→SUSTAIN）
- `<boss>_shield_overlay.gd` — 视觉层（纯 _draw，不带逻辑）
- `<boss>_uav_swarm.gd` — 蜂群管理（如有）

### 第四步：渲染层

- `scripts/aircraft_renderer.gd` `draw_aircraft_icon` 加 `silhouette == "<boss>"` 分支
- 写 `draw_<boss>_icon` 函数（注意性能守则 §1：静态内容禁止每帧 queue_redraw）
- 大型 BOSS 整体放大 ~9× 战斗机为参考；挂点位置在 boss .gd 里有
  `PROP_OFFSETS_PX` 常量，与 renderer 必须**严格对齐**（任意一处改另一处必同步）

### 第五步：接入 spawn 流程

- `scripts/survivor/boss_registry.gd`：注册 id → class_path / bgm / display_name /
  name_key / callsign_prefix / requires_water
  （`name_key` = 玩家可见名的 i18n key，复用图鉴的 `CODEX_<ID>_NAME`；漏填 → 通关结算副标题
  退回通用文案"敌方主力已被击毁"）
- `scripts/events/boss_encounter_event.gd`：`encounter is <Boss>` 分支调 `_spawn_<boss>`
- `scripts/survivor/boss_debug_select.gd`：调试菜单加条目（含 i18n key）
- `scripts/survivor/survivor_spawner.gd:_spawn_boss`：分支调 `<boss>.spawn(...)`
- `scripts/survivor/survivor_mode.gd`：BOSS 池里加 id（如果走战区机制）
- 战区奖励 / 全局 BOSS 解锁逻辑（如有）

### 第六步：i18n + 索引

- `i18n/translations.csv` 加 `BOSS_DEBUG_<NAME>_NAME` / `_DESC` + tag keys
- 同步三语 `.translation` 二进制文件（Godot 编辑器内打开 csv 自动生成；或手动跑 import）
- `docs/reference/script-index.md` 加 `<boss>_*.gd` 5 行
- `docs/reference/enemy-index.md` 加 BOSS 条目（如果展示在 enemy index）

### 第七步：验证 + changelog

- F5 → 调试菜单选 BOSS → spawn → 撞死它一遍 / 被它打死一遍
- sentinel 压测 FPS 不掉超 15
- `docs/changelogs/<date>-<boss>.md` 写完整流程

**新 BOSS 期间踩到任何重复出血点 → 写进 [known-seams.md](../architecture/known-seams.md)**。

---

## §3 加武器装备

新武器或新机制先建 `docs/specs/weapons/<name>.md`（`kind: weapon`）。只复制现有 `.tres`
做数值变体时，也要把真实数值登记到对应武器 spec；没有对应 spec 就先补档。

装备类继承 `Equipment` 基类（看 `scripts/equipment/*.gd`）。当前 6 类：
GunEquipment / MissileEquipment / RocketEquipment / LaserEquipment / RailgunEquipment / FlareEquipment。

### 完全新机制（如未来加 EMP / 鱼雷类）

1. `scripts/equipment/<weapon>_equipment.gd` 继承 `Equipment`
   - `@export` 暴露所有可调字段（伤害 / 射程 / 冷却 / 充能时长 等）
   - 实现 `tick(ac, s, delta)` 主循环
   - 实现 `fire(ac, s)` 触发逻辑
   - state 用 `Dictionary` 不写实例字段（多个 mount 共用 .gd 类）
2. 配套 `<weapon>_params.tres`（如果参数集合复杂）—— 否则 export 字段直接挂在
   `<weapon>_equipment.gd` 上
3. 飞机 loadout 资源里引用：`flight_loadout.tres` 加 `equipment` 数组项
4. AI 决策接入 `scripts/ai/`：
   - `bfm_tactics.gd` 是否要加新战术（如 SNIPER_HOLD 已存在的"机头对准型武器"通用战术）
   - `target_selection.gd` 武器射程 / 弹药约束
5. HUD 集成：
   - `scripts/hud.gd` / `scripts/survivor/survivor_hud.gd` 武器槽位显示
   - reload bar / ammo / cooldown 进度
6. EventLogger：开火 / 命中 / 报销时 `EventLogger.log_event("<WEAPON>", ...)`
7. 玩家技能挂钩（如有）：
   - `scripts/survivor/skill_hooks.gd` 击杀 / 命中钩子
   - 升级表 UPGRADES 加条目（见 §4）

### 已有装备类的新变种（如新型 missile 参数）

直接复制现有 `.tres` 改字段就行，不需要写 .gd。**踩坑提醒**：
- `Resource` 用 `preload()` + `duplicate(true)` 避免共享修改（CLAUDE.md 已写）
- 参数字段命名沿用现有约定，方便 `effective_*()` accessor 通用扩展

### i18n

装备名 / 升级名一律走 `tr("KEY")`。`AircraftParams.display_name` 是例外（用于
HUD/log 拼接）。详见 [i18n.md](i18n.md)。

---

## §4 加技能升级

单项技能放 `docs/specs/skills/<name>.md`（`kind: skill`）；同一批不可拆分的技能重做可集中到
`docs/specs/systems/<batch>.md`（`kind: balance`），但每项数值和验收仍必须完整出现。

**总入口 = [skill-implementation-index.md](skill-implementation-index.md)**（2026-07-24 起）：
§5 决策树选实装模式（八模式：纯 params / 字段置位 / skill_flag 钩子 / squad_once / 王牌 ace /
计数缩放 / 一次性 dispatch / 武器资源）→ 照该模式"新增步骤"落地 → §6 铁律过一遍。
设计哲学与需求 backlog 在 [survivor-skills.md](../systems/survivor-skills.md)；
数值现状查 [skill-table.md](skill-table.md)。

速记三条最常用模式（细节以实装索引为准）：

- **永久数值** → `apply_upgrade` 加 case 直改 `params.*`。机动类（速度/G/失速/转弯）必须直改
  params 或 `effective_*()` 注入 —— **必经 [SEAM-001](../architecture/known-seams.md#seam-001--机动性-buff-必须走-effective_-accessor)**，
  这是唯一让 AI 战术层感知 buff 的路径。
- **条件态** → Aircraft 字段置位 + 消费点 if 块（高频判定读字段不读 meta）。
- **事件触发** → `stat: "skill_flag"`（apply 无操作）+ `skill_hooks.gd` 钩子读 meta。
  **FEAR / SLOW / JAM 联动**必走集中 helper（`AOEBroadcast.apply_status_in_radius`，
  team_filter 传 `TEAM_HOSTILE`；单体玩家 FEAR 走 `_apply_player_fear`）——
  **必读 [SEAM-004](../architecture/known-seams.md#seam-004--fear-状态有-4-个入口分散在-3-个文件)**。

### onboarding checklist（任何新升级都跑一遍）

- [ ] 实装索引 §5 决策树定模式；单项 spec 或批准过的批量 spec 已登记且状态为 approved
- [ ] `survivor_data.gd:UPGRADES` 加条目（id / name / desc / stat / value / max_stacks / category /
      **axis** / rarity / 归属字段 scope·classes·exclusive_to·requires·requires_skill·milestone_plus 按需）
- [ ] 按模式落效果（M5 王牌字段型必登记 ACE_FIELD_STATS + strip；M4 静态位必配 _ready 清零；M6 必差量幂等）
- [ ] i18n CSV 加 `UPGRADE_<ID>_NAME/_DESC` 三语（列序 keys,zh,en,ja）
- [ ] `python tools/dump_skill_table.py` 重刷全表 + [实装索引 §4](skill-implementation-index.md) 加一行
- [ ] bench 断言（skills720 / sig_skills / attr_gates 择近追加）→ `--bench=all` 回归门
- [ ] 需求 backlog 如相关 → [survivor-skills.md](../systems/survivor-skills.md) 系列表更新状态
- [ ] 验证：升满该升级，EventLogger 可见效果；零升级下行为与 baseline 一致

---

## §5 加主角飞机

先建 `docs/specs/aircraft/<name>.md`（`kind: aircraft`）。玩家版与同名敌版是两个独立 spec，
用相对路径 `aircraft/<name>` / `enemies/<name>` 区分。

走 **[playable-aircraft-workflow.md 完整流程](playable-aircraft-workflow.md)**。

要点：通过 `playable_aircraft.gd` 档案 + `resources/playable_*.tres` 注入，
**禁止在共享层 `aircraft.gd` 里写 `if game_mode == ...`**（见下方“模式边界”硬规则）。

---

## §6 加事件

先建 `docs/specs/events/<name>.md`（`kind: event`）。如果改的是整个事件框架，改建
`docs/specs/systems/<name>.md`（`kind: system`）。

走 **[event-system.md](../systems/event-system.md)**。GameEvent + AIDirective + EventDirector
剧本系统。

要点：
- 事件 / 任务 / Adds 波次默认沿玩家 heading 前方扇形刷出（user memory
  `feedback_event_spawn_ahead`），**不要刷玩家身后**
- 事件类继承 `GameEvent`：实现 `_start` / `update` / `_check_complete`
- 接入 `EventDirector`：注册 + 触发条件 + 冷却

---

## §7 加地面单位

先建 `docs/specs/systems/<name>.md`，`kind` 按内容用 `enemy` 或 `system`；在 §4 明确它与
`CombatUnit`、伤害路由、雷达和 HUD 的组成关系。

走 **[ground-units.md](../systems/ground-units.md)**。三种当前类：SAMUnit / AAGunUnit /
RadarStation 都继承 `GroundUnit extends CombatUnit`。

要点：
- 覆写 `is_in_radar_cone` / `take_damage` / `is_lock_immune`（CLAUDE.md 已写）
- 没有飞行物理，只有原地武器逻辑
- HUD 显示：`scripts/aircraft_renderer.gd` 的 ground 路径 / 或自己 _draw

---

## §8 加地图

新地图或地图机制先建 `docs/specs/systems/<name>.md`（`kind: map`）。单纯修正现有地理数据时，
更新已有 map spec 的版本与变更记录，不另造平行真源。

两条路：
- 程序烘焙：[map-pipeline.md](map-pipeline.md)（OSM 数据 → tile）
- 手画：[manual-map-editing.md](manual-map-editing.md)（Godot 编辑器内手画地块）

**沙盒模式已废弃**（user memory `project_sandbox_deprecated`）。地图改动走
`map_feature_renderer` / `map_geography`，不要动 `terrain_renderer.gd`。

---

## §9 加状态效果

新状态先建 `docs/specs/systems/<name>.md`（`kind: system`）；若它只服务于一项技能，可放入该
技能 spec，但必须写清通用状态语义、免疫、叠加、持续时间和清理条件。

新型 status（FEAR / SLOW / JAM 之外）的接入点：

1. `scripts/status_effects.gd`：
   - 加常量 `const NEW_STATUS := "new_status"`
   - `DISPLAY_ORDER` 数组追加 id（决定 HUD 标签顺序）
   - `english_label` / `icon_color` match 加分支
   - `update(ac, delta)` 内加状态 tick 逻辑
2. `scripts/combat_unit.gd:apply_status` 通用入口已支持，**不需改**
   - 若该状态有"免疫 meta"模式（如 fear_immune），加 if 块
3. `scripts/aircraft.gd`：
   - 派生 active 标志：`var status_<name>_active: bool` 由 `update()` 维护
   - 物理影响通过 `effective_*()` accessor 注入（同 §4 状态 buff 路径）
4. HUD：`aircraft_renderer.gd:draw_data_label` / `draw_data_label_minimal`
   自动通过 `DISPLAY_ORDER` + `status_effects` 字典展示。如有派生 active flag
   不进字典 → 加权威标志兜底（`auth_active = ac.<flag>` match 分支）
5. AOE 触发：用 `scripts/survivor/aoe_broadcast.gd:apply_status_in_radius`，**不要
   自己循环调 apply_status**（关联约束见 SEAM-004 模式）
6. 玩家技能联动钩子在 AOEBroadcast 内集中（见 SEAM-004）

---

## §10 加无线电台词

**多数情况完全不用碰代码** —— 数据全在 `resources/chatter/radio_chatter.json`。
带行号的详细导航见 [code-index.md「无线电通讯」段](code-index.md)。

只增加既有 trigger 的台词是内容维护，直接更新 JSON + i18n，不新建 spec。增加新的触发语义、
节流规则或 BOSS 对话流程属于机制改动，先更新 `radio-chatter` spec；独立事件则建 event spec。

### 加一条台词（最常见）

1. `resources/chatter/radio_chatter.json` → 对应 trigger 的 `lines` 数组加一个 key
2. `i18n/translations.csv` 加一行：`RADIO_XXX,中文,English,日本語`
3. 跑 `--bench=chatter` 校验（会检查每个 key 都有译文）

⚠ 加了 key 之后**必须让 Godot 导入一次**。可用编辑器打开项目，或让相关 bench 通过
`bench/run.cmd` / `bench/run.sh` 的 Shadow 流程触发导入；Agent 禁止直接执行 Godot CLI。
否则 `tr()` 会原样返回 key，台词显示成 `RADIO_XXX`。

### 加一个 BOSS 的专属登场对话

在 JSON 的 `boss_sequences` 加一项，**key 用 `BossRegistry.BOSS_DEFS` 里的 boss id**；
`slot` 是队内序号（0 基），决定这句由谁说，多句交替即成队内对话。
不加则自动走 `_default` 兜底，不会静默。

### 加一个全新触发场景

1. JSON `triggers` 加一项（`class` / `weight` / `cooldown_sec` / `chance` / `lines`）
2. 在事件点调 `RadioChatter.say("<trigger_id>", speaker, color)`
   - 拿得到单位就用 `say_unit("<id>", unit)`，呼号与阵营色自动解析
   - 生存模式内经 `_radio`；其它模块经 `mode.get("_radio")` 并判空

**必读约束**：

- **`class` 决定要不要受节流**：`scripted` = 剧情关键节点，豁免全局冷却/自身冷却/概率骰，
  必定播出；`ambient` = 普通语音，受三层限制。**不写默认按 `ambient`**（保守，不会意外强插）。
- **绝不打断**是硬契约：`weight` 只管排队顺序与满队淘汰，永远不截断正在播的那条。
- **说话人资格**：无人机永不说话（`no_pilot` 硬规则）；机型还要在 `voiced_enemy_types.types`
  白名单里（opt-in，未列 = 沉默）。加新敌人时见 enemy-index 13 步清单第 10 步。
- **文本一律走 `tr()`**，不许把中文字面量写进 JSON 或代码。
- 改完跑 `--bench=chatter` + `--bench=all` 不回归。

---

## §11 加系统

适用于不属于单个敌人、武器、技能或事件的跨实体机制与平衡批次。

1. 建 `docs/specs/systems/<name>.md`；语义上是地图或平衡时分别用 `kind: map` / `balance`。
2. §4 先定所有权边界：生存专属放 `scripts/survivor/`，共享实体模块放现有子系统目录，
   RTS / 事件 / 演出 / 海军 / UGC 分别进入已有目录。完整矩阵见 [docs/README.md](../README.md#代码与资源)。
3. 先查 [known-seams.md](../architecture/known-seams.md)，再查 script-index / code-index 找现有接入点；
   不为单个文件新建目录，也不把跨域逻辑继续塞进 `survivor_mode.gd`。
4. 若新增持有 `player_aircraft` 的子系统，登记 `_set_player_aircraft()` chokepoint 并通过
   `verify_player_ref_holders.py`。
5. 按性能、i18n、模式边界和索引同步清单收尾。


## 通用约束（**所有改动都要看的**）

### 性能（每个新增 _process / _draw / queue_redraw / Aircraft 子节点之前必读）

→ [docs/reference/performance-guidelines.md](performance-guidelines.md) — 8 条硬规则 + 历史
教训。8 条速记：
1. 静态内容禁止每帧 queue_redraw
2. _draw 里不得有全场扫描
3. 多次 draw_polygon / draw_line 要合并
4. _process / _physics_process 禁用 get_parent().get_children()
5. AI 决策默认 20Hz 起步
6. Aircraft / Missile 子节点要先乘实体数
7. 跑生存模式 sentinel + Lv5+ 压测，FPS 掉 >15 回滚
8. 随实体数增长的成本必须支持拥挤度自适应，并给玩家 / BOSS / Sentinel 留豁免

### 模式边界（共享层改动必读）

**沙盒模式已废弃**——验证只需跑生存模式（`scenes/survivor_mode.tscn`）。
但共享层的隔离铁律**依然有效**（保护的是共享层干净，不是两模式对等）：

- **禁止**在共享层（aircraft.gd / ai_controller.gd / combat_unit.gd / missile.gd 等）
  写 `if in_survivor_mode` / `if in_sandbox` / `if game_mode == ...`
- 模式/机型专属 buff 通过参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入
- 新文件放哪：生存专属 → `scripts/survivor/`；RTS 指挥 → `scripts/rts/`；
  共享层 → `scripts/` 根或对应子系统目录

### i18n

→ [docs/reference/i18n.md](i18n.md)。玩家可见 UI / 升级 / 机型 / 地图 / 弹窗文本
**一律走 `tr("KEY")`**，在 `i18n/translations.csv` 定义 key + 三语翻译。
例外：`AircraftParams.display_name` / EventLogger / debug 面板。

### 已知耦合点（修 bug 撞到先看）

→ [docs/architecture/known-seams.md](../architecture/known-seams.md)。修 bug 撞到地基时
先看是否已记，未记 → 加新条目。commit message 加 `[ref:SEAM-XXX]` 跑
`tools/seam-report.ps1` 自动统计票数。

### 索引同步（commit 前 checklist）

任何改动后必同步：
- 新增 / 删除函数 → [docs/reference/script-index.md](script-index.md) +
  [docs/reference/code-index.md](code-index.md)
- 大幅移位（> 50 行）→ 更新受影响行号
- 加新敌人 → 同步 [docs/reference/enemy-index.md](enemy-index.md)
- commit 前检查索引与代码一致性

### 设计哲学（加机制 / 数值 / 敌人 / 技能 / BOSS 前必读）

→ [docs/DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md) — north star + 13 条反模式 + 9 条
Litmus 测试。

---

## 常见错误模式（反面教材）

- **加机动 buff 但 AI 不感知** → 没走 effective_*() accessor
- **加敌人但 _create_enemy 漏 case** → spawn 时 NullRef 崩溃
- **加 BOSS 但 PROP_OFFSETS_PX 与 renderer 不对齐** → 雷达锁定框和飞机模型脱节
- **加 FEAR 联动 buff 但 AOE FEAR 路径漏** → 单体路径有效 / AOE 路径失灵
- **新 status 加权威 active flag 但不进 status_effects 字典** → HUD 不显示
- **改共享层只测一个模式** → 另一模式悄悄崩
- **散修堆在 main 不分支** → "做 X 时顺手改了 Y"，回滚单条变成大手术；按 spec §6
  拆成可独立验证的小步
