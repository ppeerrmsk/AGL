# 生存模式参考（架构叙述）

> 最后校订：2026-07-28。
>
> **分层约定**（见 [specs/_INDEX.md](../specs/_INDEX.md)）：本文属 `docs/systems/`，只写**跨系统的架构叙述与流程**。
> **全部数值 / 公式 / 触发条件的权威源在 specs**：
> - 核心循环、Token 经济、刷怪、时间税 → [specs/systems/survivor-loop](../specs/systems/survivor-loop.md)
> - 战区奖励与停靠结算 → [specs/systems/zone-reward-docking](../specs/systems/zone-reward-docking.md)
> - 进化树与属性门槛 → [specs/systems/aircraft-evolution-tree](../specs/systems/aircraft-evolution-tree.md) · [evolution-attribute-gates](../specs/systems/evolution-attribute-gates.md)
> - 技能系统 → [systems/survivor-skills.md](survivor-skills.md)（设计层）+ [reference/skill-implementation-index.md](../reference/skill-implementation-index.md)（实装层）
> - 敌人谱 → [reference/enemy-index.md](../reference/enemy-index.md)
>
> 本文**刻意不重列具体常量**——重列必然腐烂（本文 2026-07 前就因此把阶段时长、XP 曲线、
> 刷怪表全写错过一轮）。要数字请去上面的 spec。

---

## 概述

生存模式是 AGL 的**主玩法**（也是唯一出包的模式）。

一局的形状是**有终点的攻坚**，不是无尽波次：

```
起飞（起手机型四选一）
  → 战区阶段：Token 预算持续刷怪 + 打战区任务 + 击杀升级
      · 攻克战区 → 飞到停靠点减速着陆结算 → 领奖励 / 换机进化 / 全队满血
      · 每升 3 级 → 三轴卡片三选一（斗士 / 骑士 / 策士各一张）
  → game_time 跨过 WARZONE_PHASE_DURATION → 战区全部关闭，BOSS 解锁
  → BOSS 阶段：game_time 冻结、停刷、决战
  → 击败 BOSS = 过关（VICTORY）→ 局内 XP 按系数折算成局外功勋（MeritLedger）
```

⚠ 常见误解澄清：
- **不是无尽模式**。`BossEncounterEvent` 进 VICTORY 相 → `survivor_mode._on_victory` 结算。
- **不是单机模式**。玩家操控的是**小队**：数字键 1–9 接管对应号机，命令轮盘对全队广播。
- **不是"每级弹一次三选一"**。等级升级只出 toast，选卡归**每 3 级**的三轴卡片（见 evolution-attribute-gates）。

---

## 文件结构（主干）

完整清单见 [reference/script-index.md](../reference/script-index.md)，此处只列主干骨架。

| 文件 | 说明 |
|------|------|
| `survivor/survivor_mode.gd` | 场景执行：帧循环 / Node 与信号 / 玩家机登记（SEAM-019 chokepoint）/ UI / 胜负 |
| `survivor/battlefield_flow.gd` | 规则状态：净时间轴 / 战区关闭事务 / BOSS 阶段 / 王牌与 ORION 调度 |
| `survivor/survivor_runtime_reset.gd` | 新局与退局共用的跨场景 static 清理 |
| `survivor/survivor_spawner.gd` | 刷怪总管：Token 预算 / 猎手指派 / 增援入场 / FPS 动态降载 |
| `survivor/survivor_data.gd` | 静态数据：技能表 / Token 成本 / 波次与缩放常量 / XP 曲线 |
| `survivor/survivor_player.gd` | 经验 / 等级 / 升级应用（`apply_upgrade`）|
| `survivor/skill_hooks.gd` | 事件触发型技能的钩子层 |
| `survivor/zone_data.gd` / `zone_mission.gd` / `dock_point.gd` | 战区状态机 / 任务 / 停靠点 |
| `survivor/evolution_system.gd` / `evolution_ui.gd` / `evolution_tree_view.gd` | 进化树与结算规划站 |
| `survivor/boss_registry.gd` / `boss_encounter.gd` | BOSS 注册与遭遇战基类 |
| `survivor/ace_tier.gd` / `ace_squad.gd` | 王牌中队分层（LOD 豁免 / 无缩放 / HP cap 豁免）|
| `survivor/roe_director.gd` | 全图察觉与交战规则（热度即难度）|
| `survivor/survivor_hud.gd` / `tactical_map.gd` | HUD / 战术地图 |
| `scenes/survivor_mode.tscn` | 场景（BulletManager + MissileManager + Camera2D）|

RTS 指挥逻辑**不在** `survivor/` 下，独立在 `scripts/rts/`（`SquadCommandController` + 参数 Resource）。

---

## 阶段制

| 阶段 | 区间 | 行为 |
|------|------|------|
| 战区阶段 | `game_time` 0 → `WARZONE_PHASE_DURATION` | 战区可循环刷新；攻克 1 个 → 立即开新战区 |
| 过渡 | 到点瞬时（`BattlefieldFlow` 阶段只允许 WARZONE→BOSS 一次） | 取消全部 zone 任务、锁所有战区、`boss_unlocked = true`；敌人留场（继续给 XP，不再给奖励）|
| BOSS 阶段 | 到点之后 | `game_time` 冻结；`_update_boss_phase` 启动 `BossEncounterEvent` |

**`game_time` 是可倒拨的时间轴，不等于真实秒表**：
- 出界补给回血 → `game_time += SUPPLY_TIME_COST`（把 BOSS 拉近的"时间税"；BOSS 阶段已屏蔽）
- 王牌支援中队全灭 → `game_time -= 60`（整局延长 1 分钟）
- 城区 CH-47 直升机三架全歼 → 走同一个 `grant_time_extension` 注入点再延长一段

所以"BOSS 什么时候来"取决于玩家怎么打，不是固定钟点。

**已攻克战区再激活**：`_refresh_availability_after_clear` 用加权抽取（CLEARED 权重高于 LOCKED）
从候选池开新战区 → 已攻克战区有显著概率被重新激活并刷新敌人。

**HUD**：`survivor_hud.set_warzone_remaining(seconds, in_boss_phase)`，顶部常驻，
`PROCESS_MODE_ALWAYS` 保证升级面板暂停时也显示。

**已废弃路径**：旧的 `cleared_count >= 3` 触发 BOSS 已删除，改由时间闸驱动。

---

## 与沙盒模式的关系

**沙盒模式（`scenes/main.tscn`）已废弃**，只作物理 / AI 调试留存，不打包、不加新内容。
不要再按"两个模式都要测"的旧规矩排期——但**共享层代码的模式隔离铁律仍然有效**：

> 禁止在共享层（`aircraft.gd` / `ai_controller.gd` / `missile.gd` 等）写
> `if in_survivor_mode` / `if in_sandbox`。模式差异必须走参数资源 `duplicate(true)`
> 或 PlayableAircraft 档案注入。

生存模式相对沙盒的行为差异（弹药自动装填、无限燃油、扁平高度档、伤害上限、
同时飞向玩家的导弹上限等）全部是**通过参数注入实现的**，不是分支判断。

---

## 经验与升级

- XP 曲线、乘区、功勋折算系数 → [survivor-skills.md 经验曲线段](survivor-skills.md)
- 击杀 XP 与 Adds 特例 → [specs/systems/survivor-loop](../specs/systems/survivor-loop.md)
- 升级池筛选：`is_upgrade_available_for(upgrade, aircraft_id, params)` 处理
  `requires`（装备门控）/ `requires_skill`（词条依赖）/ `exclusive_to`（机型签名）/ `max_stacks`
- 应用入口：`survivor_player.apply_upgrade()` 把 stat 写到 Aircraft / AircraftParams（已 `duplicate(true)`）
- ⚠ **进化链 `evolves_to` 已废弃**，新技能不做"满级自动进化"

三轴点数 / 里程碑 / 已选技能全部**记玩家层，换机重放不丢**（局内 roguelike，局外清零）。

---

## 刷怪与压力

- **Token 预算制**：每个敌人有 Token 成本与实例上限，预算随等级爬升；Adds 杂兵不占 Token
- **可信入场几何**：普通增援从地图边缘进入中央锚点；hunter 缺口时的拦截波才从玩家前方边缘压来；
  任务/护送/追击按自身航线与实时目标关系派生，不使用一条全局前方扇形硬规则
- **BOSS 专属机型不进常规池**：F-47 / F-14 Poltergeist 只由 BOSS 遭遇战投放，随机桶里显式排除
- **作战高度按机型分档**：不再是所有机型均匀随机 LOW/MID/HIGH，改为按 EnemyType 加权抽档
  （攻击机偏低空 / 截击机偏高空 / 多用途机偏中空），且 `patrol_altitude` 跟随抽到的档位——
  否则档位分化只影响巡逻段、交战高度仍是老样子。未登记的类型（BOSS / Adds / 事件单位，
  高度由各自 spawn 代码事后覆写）维持原来的均匀随机行为
- **增援入场**：不再离屏凭空刷，改为边缘中队涌入 → 中央锚点驻空 → token 饿时物理飞离
- **猎手指派**：定期从空闲敌机中指派猎手追踪玩家，配额由 ROE 热度驱动
- **动态性能控制**：周期采样 FPS，低于目标即收敛敌机上限，恢复后逐步放开
- **导弹上限**：同时飞向玩家的导弹数量有硬上限，防止瞬间秒杀

全部具体数值见 [specs/systems/survivor-loop](../specs/systems/survivor-loop.md) §4 与
[specs/systems/60km-density-pass](../specs/systems/60km-density-pass.md)、
[specs/systems/reinforcement-ingress](../specs/systems/reinforcement-ingress.md)。

---

## 敌人强度铁律

除 BOSS 外，**所有空中敌人一发死**：普通敌机 HP 被 `ENEMY_HP_MISSILE_CAP` 强制夹取，
保证任何导弹都能一发解决（DESIGN_PHILOSOPHY 原则 1）。

**王牌中队（AceTier）是显式豁免层**，不是"数值堆高的杂兵"：
- 不吃 LOD 降频、不吃等级缩放
- HP cap 豁免（但只到"残血"档）
- 生存靠**热诱弹即命数**：固定枚数、必定成功、不补充、耗尽即必死

见 [specs/systems/ace-squadron-tier](../specs/systems/ace-squadron-tier.md)。
