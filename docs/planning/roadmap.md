# AGL 开发 Roadmap

> # ⚠ 历史快照（2026-04-11），**勿作为现状依据**
>
> 本文停留在 2026-04 的项目状态，此后项目经历了 RTS 化转向、战区/停靠结算循环、
> 41 机进化树、三轴卡片技能制、60km 扩图、沙盒模式废弃等一系列方向变更。
> 下面的 Phase 划分、"大地图战区系统"设想、"技能树重做"方案、模式边界表都已被取代或用别的方案落地。
>
> **现状与在办事项一律看这些**：
> - **[docs/specs/_INDEX.md](../specs/_INDEX.md)** —— 唯一的设计现状源（每份 spec 带 status 与剩余工作）
> - [docs/reference/features.md](../reference/features.md) —— 现在有什么功能
> - [docs/project-overview.md](../project-overview.md) —— 项目现在是什么
> - `docs/changelogs/` —— 具体某次改动
>
> 保留本文只为记录当时的判断依据。**要加新东西请走 spec-first 流程**（[playbook.md](../reference/playbook.md)），
> 不要往本文追加新计划。
>
> 已过时的具体点（举例）：沙盒模式已废弃只打生存包；`survivor_map_select` 5 槽设想已被战区推进循环取代；
> "技能树重做"已由三轴卡片制 + 144 条技能表落地；下面 P0/P1 反馈项多数已解决或被更大改动吞掉。

---

**原文（2026-04-11 快照）如下。**

本文件是 AGL 项目的开发总规划。
- **短期反馈修复**（第 1 段） 与 **长期开发计划**（第 2~3 段） 分开管理，每项带 优先级 / 影响模式 / 涉及文件。
- 完成的条目从主表移到"第 6 段 · 已完成归档"，按季度保留一行简述。
- 新想法直接追加到"第 4 段 · 待规划池"，Review 后再归入正式段。

---

## 0. 模式边界（防混淆约定）

生存模式与沙盒模式共享大量底层代码（`aircraft.gd` / `ai_controller.gd` / `missile.gd` 等），但入口、主控、HUD、刷怪逻辑完全独立。修改任何"共享层"代码前必须明确影响范围。

| 层 | 文件 | 沙盒 | 生存 |
|---|---|---|---|
| 入口场景 | `main_menu.tscn` / `main_menu.gd` | ✔ | ✔ |
| 主控 | `main.gd` / `main.tscn` | ✔ | — |
| 主控 | `survivor/survivor_mode.gd` / `survivor_mode.tscn` | — | ✔ |
| HUD | `hud.gd` | ✔ | — |
| HUD | `survivor/survivor_hud.gd` | — | ✔ |
| 调试面板 | `debug_panel.gd` | ✔ | — |
| 调试面板 | `survivor/survivor_debug_skills.gd` / `survivor_debug_spawn.gd` | — | ✔ |
| 飞机实体 | `aircraft.gd` / `aircraft_params.gd` | ✔ | ✔ |
| AI | `ai_controller.gd` / `combat_params.gd` | ✔ | ✔ |
| 武器 | `missile.gd` / `missile_manager.gd` / `bullet_manager.gd` / `*_params.gd` | ✔ | ✔ |
| 战斗单位 | `combat_unit.gd` / `ground_unit.gd` / `sam_unit.gd` / `aa_gun_unit.gd` / `radar_station.gd` | ✔ | ✔ |
| 编队 | `squad.gd` | ✔ | ✔ |
| AutoLoad | `event_logger.gd` / `callsign_db.gd` | ✔ | ✔ |
| 资源参数 | `resources/*.tres` | ✔ | ✔ |
| 主角档案 | `playable_aircraft.gd` + `resources/playable_*.tres` | — | ✔ |
| 生存专属 | `scripts/survivor/*` 其余文件 | — | ✔ |

**硬规则**：
1. 修改"共享层"文件时，必须同时验证两个模式的行为，不能只测其中一个。
2. 生存模式特有的 buff / 平衡 / 调味 只能通过 `survivor_playable_setup.gd` 或参数资源 `duplicate(true)` 注入，**禁止**在 `aircraft.gd` / `ai_controller.gd` 里写 `if in_survivor_mode`。
3. 需要模式隔离的功能（例如"生存模式下僚机不烧油"）优先级：参数化 → 由主控在生成飞机时覆盖 → 在 PlayableAircraft 档案里写死。**永远不要在共享代码里加 `if game_mode == ...` 分支。**
4. 新增文件时：生存专属放 `scripts/survivor/`，沙盒专属不带前缀放 `scripts/`，共享层直接放 `scripts/`。命名即语义。

---

## 1. 反馈修复（Feedback Fixes）

收到玩家/自测反馈后的优化项，按优先级排序。每项完成后移到第 6 段。

### P0 · 必改

- [ ] **敌人 AI 对机炮追尾无反应**
  - **症状**：玩家从 6 点钟机炮追击时，AI 仍按 LEAD_PURSUIT / LAG_PURSUIT 飞行，既不 BREAK_TURN 也不做能量规避
  - **根因推测**：`ai_controller.gd` 的威胁感知只看"被导弹锁定"，不看"被机炮瞄准 + 处于后方射程内"
  - **方案**：新增 `_has_gun_threat_from_rear()` 输入 — 后方 60° 扇区 / 距离 < 机炮有效射程 ×1.5 / 敌方速度矢量对准自己 → 触发 BREAK_TURN 或 EXTENSION
  - **涉及**：`ai_controller.gd:_choose_tactic:952` + 新判定函数；需要同步更新 `CombatParams` 暴露激进度参数
  - **模式**：共享层（两种模式都受益）

- [ ] **玩家对自己机炮射程的感知**
  - **症状**：玩家不知道机炮什么时候打得到，盲射浪费子弹
  - **方案候选**：
    - A. 准星圆圈 — 目标在射程内时 HUD 出现机炮准星
    - B. 目标图标变色 — 距离 < 有效射程时敌机图标染色
    - C. 发射按钮 / 十字线颜色反馈
  - **涉及**：`survivor/survivor_hud.gd`（主） + 同步 `hud.gd`（沙盒一并加）
  - **模式**：两种

### P1 · 玩法扩展

- [ ] **后期源源不断的 UAV 刷新**
  - **症状**：后期关卡几乎全是 UAV，体验单调，Build 没有发挥空间
  - **方案候选**：
    - Token 预算对 UAV 单独封顶（`survivor_data.gd:TOKEN_INSTANCE_CAP` 已有，可加"每波 UAV 占比上限"）
    - 高等级后 `_pick_enemy_type` 禁用 UAV 作为主力刷新源（只在编队护航 / 地面拦截等情境出现）
    - 配合 2.1 大地图系统把 UAV 限定为"无人机战区"专属敌人
  - **涉及**：`survivor_data.gd` / `survivor_mode.gd:_pick_enemy_type:874`
  - **模式**：生存

- [ ] **对得起 Build 的挑战**
  - **症状**：升级 Build 成型后缺乏匹配难度的敌人，中后期体验疲软
  - **方案**：精英敌人 / 王牌编队 / mini-boss（见 2.3 BOSS 战）
  - **模式**：生存

- [ ] **更多使用火箭弹的敌人**
  - **症状**：火箭弹机制（F-86 FFAR）表现不足，需要更多持续输出带来压力
  - **方案**：新增 1~2 个携带火箭弹的敌人（例如 Su-7 / MiG-19 / A-1H Skyraider 风格的对地/空战混合机）
  - **涉及**：走 CLAUDE.md "创建新敌人完整清单" 12 步流程
  - **模式**：生存

---

## 2. 开发计划（主要特性）

按模块分段，每个模块独立推进，不必按顺序。

### 2.1 生存模式 · 大地图系统（P1，最大模块）

不同主题的战区作为生存模式的"章节选择"，玩家自由选择攻略方式。

- **目标**：玩家选择一张战区地图 → 该地图有特定的敌人池 / 奖励池 / 环境 / 技能池
- **战区候选**：
  - 开阔海域：UAV 舰载 + 反舰任务 + SAM 船
  - 山谷：地形遮蔽 + 低空突防 + AAA 密集
  - 城市 / 工业区：高价值目标 + 地面车队
  - 冰原 / 极地：雷达干扰 + 能见度低
  - 沙漠基地：AWACS + 护航编队
- **奖励差异化**：通关地图解锁特定升级 / 技能 / 机型 → 对接 2.8 局外升级
- **影响文件**：`scenes/survivor_map_select.tscn`（已占位） / `survivor/survivor_map_select.gd`（已占位 5 槽）/ 新增战区参数资源 `resources/survivor_regions/*.tres` / `survivor_mode.gd` 接受地图参数
- **模块拆分**：
  1. 战区数据结构（Resource）
  2. 选择界面扩展 —— 5 槽 → 实际数据
  3. survivor_mode.gd 接受 region 参数并切换敌人池 / 环境
  4. 战区专属奖励挂到升级池

### 2.2 生存模式 · 敌人扩展（P1）

- [ ] **非攻击性杂鱼类**：类似直升机 / 运输机 / 侦察机，高经验低威胁
  - 新 EnemyType + 新 AI 分支 `non_combatant`（只巡逻，被击即死）
  - 复用 `aircraft.tscn` 或 `ground_unit` 新变体
- [ ] **火箭弹敌人**（见 1.P1 反馈）
- [ ] **精英版敌人**：普通敌人 ×1.5 属性 + 武器升级
  - 不增加 EnemyType，由"精英标记"在生成时 duplicate params 调整
- [ ] **王牌飞行员**：特殊呼号 + 独特技能（例如冷血射手 / 高机动大师），击杀有额外奖励

### 2.3 生存模式 · BOSS 战（P1）

- [ ] **巨型 Boss**：多部位 / 多阶段 / 免疫小口径武器
  - 候选：Su-34 / B-52 / AC-130 风格
  - 新建 `survivor/survivor_boss.gd`
- [ ] **王牌中队**：4~6 架精英 MiG-29 或 F-15 编队，每架带呼号/涂装 / 独立 AI 个性
  - 新建 `survivor/boss_ace_squadron.gd`
- [ ] **触发方式**：每 N 波触发一次 / 特定等级解锁 / 地图终点
- [ ] **奖励**：强力 / 专属升级，喂给 2.4 技能树稀有度

### 2.4 生存模式 · 技能树重做（P1）

当前 `survivor_data.gd:UPGRADES` 是扁平表，需要重构为分层/图状结构。

- [ ] **共通技能**：所有机型都能选
- [ ] **独特技能**：机型限定（F-14 僚机控制 / F-16 多目标交战 等），`exclusive_to` 字段已占位
- [ ] **稀有度**：普通 / 稀有 / 史诗 / 传说，影响升级 UI 配色与刷新概率
- [ ] **地图专属技能**：某些升级只在特定战区出现（对接 2.1 大地图）
- [ ] **前置依赖**：`requires` 字段已经在 `SurvivorData` 占位，可直接扩展
- [ ] **重构文件**：`survivor_data.gd` UPGRADES 表 / `survivor_upgrade_ui.gd` 支持稀有度渲染

### 2.5 生存模式 · 经验/等级曲线改善（P2）

- [ ] 重新评估 `xp_for_level` 曲线（当前是否过陡/过缓）
- [ ] 经验来源多样化：击杀 / 任务达成 / 支援友机 / 护僚机存活
- [ ] 连杀 / 连击奖励（短时间内多杀触发倍率）

### 2.6 生存模式 · 僚机加入与退出（P1）

- [ ] 玩家可以在游戏中**招募**敌方 UAV 或从地图奖励招募僚机
- [ ] 僚机可以**主动离队**（被击落后离场 / 弹药耗尽返航 / 任务完成后返航）
- [ ] 扩展 `commander_aura.gd` 的招募机制为**通用招募系统**（拆出 `survivor_recruit.gd` ？）
- [ ] F-14 的僚机技能对接此系统（见 2.4 独特技能）

### 2.7 新机型（P1，持续）

- [ ] 规划下一批 playable 机型（参考 `docs/reference/playable-aircraft-workflow.md`）
- [ ] 候选：F-18 / Su-27 / Mirage 2000 / F-4 Phantom / A-10
- [ ] 每个机型要有明确的"玩法定位"（空战 / 截击 / 对地 / 多用途）以避免功能重复

### 2.8 局外全局升级系统（P2）

玩家在一局局外积累资源 → 永久升级（Hades / Rogue Legacy 风格）。

- [ ] 存档系统：JSON 写到 `user://save.json`
- [ ] 解锁树：机型 / 起始升级 / 战区 / 局外属性小加成
- [ ] 新增 `scripts/meta_progression.gd` 作 AutoLoad
- [ ] 主菜单新"局外升级"按钮 / 界面

---

## 3. 表现层 / Polish（P2，并行推进）

这些可以在主玩法开发的空档插入，不必全部集中做。

- [ ] **飞机图标表现升级**：当前线框图标，考虑 2D 精灵 / 多角度帧动画（仍保持俯视线框美学）
- [ ] **受击特效**：爆炸分级 / 火光 / 烟柱轨迹 / 击落慢动作
- [ ] **音效**：引擎 / 机炮 / 导弹发射 / 命中 / 锁定告警 / UI 交互
- [ ] **音乐**：主菜单 / 战斗 / BOSS / 紧急，基于 `_pressure` 动态切换
- [ ] **本地化 / 多语言**：至少中英双语，Godot 内置 CSV 导入
  - 影响 UI：主菜单 / HUD / 升级面板 / 调试面板 / 机型选择 / 地图选择
  - 新增 `resources/locale/` 目录存放翻译表
  - 需要把硬编码中文字符串抽成 `tr("KEY")` 调用

---

## 4. 待规划池（Brainstorm Bucket）

放未成熟 / 待 Review 的想法，Review 后提升到正式段落：

- _（当前空）_

---

## 5. 索引维护约定（防混淆）

为了防止生存/沙盒模式混淆 bug，所有修改必须遵守：

1. **新增共享层功能** → 在 CLAUDE.md "Script Index" 表的"职责"列里注明"(共享)"，并在第 0 段表格补一行；两种模式都要手动测一次
2. **新增生存专属功能** → 文件放 `scripts/survivor/` 目录，Script Index 单独列在"survivor/"段
3. **新增沙盒专属功能** → 文件不带 survivor 前缀直接放 `scripts/`，并在 CLAUDE.md 备注"(沙盒)"
4. 任何时候发现共享代码里出现 `if in_survivor_mode` / `if in_sandbox` → **立刻重构**为参数注入或 PlayableAircraft 档案覆盖
5. 更新本 roadmap 后必须同步更新 CLAUDE.md 的"相关文档"段，加一行 `[docs/planning/roadmap.md] — 长期开发规划` 引用

---

## 6. 已完成归档

保留每项一行简述，便于快速回顾项目史。

### 2026 Q2

- ✅ 2026-04-10 新增 4 款敌机（F-86 / MiG-31 / MiG-23 / F-100）+ Token 预算 + 战术激进度 + 火箭弹系统 + 指挥 UAV 护驾 + 机炮整匣装填（commit `87e19d6`）
- ✅ 2026-04 编队系统 + 地面单位 + 协同攻击 + 代码索引 + 编队振荡修复（commit `c783634`）

### 2026 Q1

- ✅ 生存模式敌人平衡调整 / 新增 J-7 截击机 / 锁定上限 / 雷达导弹警告（commit `f737423`）
- ✅ 实装战术 AI / 热诱弹 / 飞行物理改进 / 主菜单 / 生存模式框架（commit `2705eb6`）
