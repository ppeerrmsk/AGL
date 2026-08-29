# 飞机物理 + AI 操控权限重构计划

> status: approved（2026-07-02 用户拍板，含 B1 分层规避策略）· **Phase 0 已落地（2026-07-03）**
> 日期：2026-07-02 · 基线分支：feature/aircraft-evolution
> 输入：三路全库代码体检（物理字段写入者地图 / AI 决策层级与目标所有权 / 时序·LOD·可测试性）
> + [known-seams.md](../architecture/known-seams.md)（13 条 seam 中 7 条落在本范围）
> ⚠ 文中行号为体检当日快照，仅作定位线索，动手前需重新确认。

---

## §1 体检结论（TL;DR）

用户的直觉**完全正确**：bug 多的根源不是某个公式写错，而是**"操控权限"没有所有者**。
飞机的每个控制意图字段都有大量互不知晓的写入者，谁赢取决于 Godot 树序、帧相位和
early-return 守卫的排列顺序，而不是显式优先级。每加一个新控制者（BOSS 剧本 / RTS 命令 /
蜂群 / 机动模块 / buff），都要在 N 个既有写点上打豁免补丁，漏一处就是一个新 bug。

**关键统计**（写入点数量 = 争抢烈度）：

| 字段 | 写入点 | 现状仲裁方式 |
|---|---|---|
| `target_speed_kmh` | ~90 处 | 旗标链 `use_tactical_planner > hard_brake > ai_override_pursuit > EM`，漏设旗即被 60Hz 覆盖 |
| `target_position` | ~45 处 / 10 子系统 | 无仲裁；"最后写者赢" + INF 哨兵；planner 靠比对旧值猜"是不是我写的" |
| `_current_target` / `combat_target` | 12 文件 40+ 处 | 无仲裁；spawner/BOSS/HUD/SwarmDirector 直写，与 AIController 守卫互相设防 |
| `target_altitude` | ~30 处 | 混写，规避退出不还原 |
| `is_afterburner` | ~20 处 | 有守卫入口 `set_afterburner`，但 **9 处裸写绕过**全部检查 |
| `_state`（AI 状态机） | 8 文件 14+ 处 | BOSS/HUD/spawner 绕过 API 直捅私有字段 |
| `lod_level` | ~12 处 / 7 写者 | 每帧拔河，收敛依赖引擎树序；LOD1 非编队分支在生存模式是死代码 |

known-seams 里反复出现的模式（SEAM-001/004/010/011/012/013 ——"同一语义多个分散写点，
改一处漏一处"）全部是这一个根因的不同切面。

---

## §2 六大结构性根因（带证据）

### R1 · 控制意图字段无所有权、无仲裁器

- 仲裁靠散布的布尔旗标 + early-return 守卫矩阵，且矩阵**不完备**：
  `update_speed` / `update_g_load` 只守卫 cobra 不守卫 herbst（aircraft_physics.gd ~219/~361），
  Herbst 被迫每帧"同帧双写 speed + target_speed_kmh"自卫（herbst_maneuver.gd ~114 注释自认）。
- `ai_override_pursuit` 保护旗要 AI 侧 25+ 处手动开关，漏一处速度决策就被 60Hz
  energy_management 静默覆盖。
- 三处外部系统的注释在描述与 AIController 守卫的"军备竞赛"：
  survivor_spawner.gd ~1917（"仅覆盖 combat_target 不够，AI 下一 tick 会覆盖回来"）、
  swarm_director.gd ~165（"必须强设否则 orbit 分支钳住"）、
  poltergeist_squad.gd ~251（"否则 spawn-init guard 会锁进 SQUAD_FOLLOW"）。

### R2 · 正交模态挤在一根 `_state` 轴上

evasion / 编队 / directive / manual_control / swarm 角色 / boss_attacker / escort_cover
都是与 PATROL/ENGAGE 正交的模态，实现为 match 之前的一串旁路 if + 散落 bool。后果：

- 横切行为（leash）要在每个状态各修一遍（SEAM-010 原文）。
- `evasion_mode`（Aircraft 字段）与 `_state==EVADE_MISSILE`（AI 字段）双真值源，
  需手工"清掉防 bounce"。
- **活 bug**：带玩家命令的飞机 `enter_evade` 后，下一 AI tick 被命令铁律
  （`_enforce_commanded_target` 排在 match 之前）强行拉回 ENGAGE → ENGAGE↔EVADE
  按 tick 抖动，且 `evasion_mode` 卡 true → planner 持续输出 EVADE intent（max+AB、
  武器静默）直到玩家重新下令。注释声称"规避优先于命令"（ai_controller.gd ~775），
  代码顺序与之相反。

### R3 · 3.5 套战术执行器并存，公式 2~3 份人肉同步拷贝

- 执行器：旧 BFMTactics 9 战术（沙盒 + 白名单外机型）/ 新 TacticalPlanner 13 intent
  （生存模式主力，`ENABLE_PLANNER_FOR_REGULAR_AI=true`）/ `_process_simple`
  （UAV/Adds，700+ 行内嵌 swarm/standoff/railgun 三层覆盖）/ `_process_drone_engage`。
  同一"lead pursuit"存在 **5 份实现**。
- 公式镜像：`update_*` vs `step_*` 预测线约 6 组公式，注释明文要求人肉同步
  （aircraft_physics.gd ~64，SEAM-012）；编队仍保有**私有的 speed/altitude/position
  第二套物理**（lerp，绕过失速地板/G 掉速/爬升率；bank/heading 已在 2026-06-07 收口成功）。
- 特性静默丢失：PilotPersonality 的位置/速度误差**只有旧执行器消费**——现在的主力
  planner 飞机"飞行员会犯错"特性无声失效，压力系统还在白白累积。
- FEAR 逃跑逻辑三处同步（bfm_tactics 两段近重复 + planner 一段）；overshoot-extend
  两套计时（`_overshoot_timer` vs `_bfm_extend_until`）并存于同一 Aircraft。

### R4 · 双脑双频率，时序健康是用 CPU 买的

- planner 住 Aircraft、60Hz 每帧跑；AIController（目标选择/规避进出/leash）住子节点、
  可分频。两脑靠共享字段隔空通信，`Situation.from_aircraft` 用鸭子类型 + 遍历子节点
  反向读 AI 状态。
- EVADE 是"AIController 管方向、planner 管油门"的分权协作，任何一半没跑另一半悬空
  （R2 的活 bug 即一例）。
- `ai_tick_divisor` 默认 = 1（60Hz），与性能守则"AI 决策 ≥3 分频起步"直接矛盾——
  当前靠 60Hz 掩盖所有双频率张力；**一旦为性能降频，旧 BFM target_position、守后拦截位
  等"慢写快读"点会集体变成 SEAM-011/013 复发点**。

### R5 · 守卫入口与裸写并存，入口守卫不构成不变量

- `set_afterburner` 有冷却/燃油/SLOW 三重守卫，9 处裸写绕过（ace_squad、bfm_tactics、
  cobra/herbst、status_effects、ai_controller FEAR）。
- `set_evasion_mode` 的历史边界差量缩放已在 2026-08-15 改为 `cd_rate` 实时消费；裸写仍会
  绕过清指令/广播等切换副作用，因此入口约束依然成立。
- `params.max_g` 等 Sentinel 运行时改写已在 2026-08-15 改为 Aircraft 临时光环字段，
  `commander_aura` 独占生命周期；`escort_behavior` 不再复制 originals 恢复逻辑。
- 进出状态的字段清单靠人肉对称：enter_evade/exit_evade、进出编队、切控交接各自手写
  6~8 个字段，历史 bug（360°/s 扭头、追旧长机、LOD 切换速度残留）全是漏一个字段。

### R6 · 测试盲区与 bug 密度倒挂

- 已可无头量化：转弯控制器（turn_physics 双指标）、编队归队、flare、weapon aim 跳变、
  BfmIntent/planner 纯函数（73 case，但只能 F10 手动跑，没接 bench_runner）。
- **零覆盖**：AIController 状态机迁移、SquadCoordination、命令铁律执行顺序、切控交接、
  LOD 路由、SquadCommandController 拴绳——恰是历史 seam 主产区。
- bench_runner 是手工 if-chain，无统一断言/退出码/CI。

**附：文档基线失真**——ai-system.md 把 planner 描述为"默认关闭的实验"（实际已是主路径）、
squad-tactics-design.md 主体是未实现草案、script-index 行数漂移近一倍
（aircraft.gd 索引 1254 / 实际 2525）。重构不能拿这两份当基线，可用的权威是
known-seams + aircraft_formation 头部 bug 回溯地图 + specs/。

---

## §3 立即可修的活 bug（不等重构）

> **状态（2026-07-03）：B1~B6 全部落地**，`--bench=all` 回归门 8 项全绿（含新增
> `--bench=cmd_evade` 23 断言）。详见 changelogs/2026-07-03-phase0-refactor-safety-net.md。
> known-seams 新增 SEAM-014（铁律×EVADE，已修）/ SEAM-015（机动守卫，已修）/
> SEAM-016（lod_level 拔河，待 Phase 4）。

按危害排序，每个都是独立小修，可在重构前先落地：

| # | 问题 | 位置线索 | 修法 |
|---|---|---|---|
| B1 | 命令铁律 × EVADE 死锁抖动（R2）：带命令飞机躲弹时 ENGAGE↔EVADE 抖 + `evasion_mode` 卡 true | ai_controller.gd `_enforce_commanded_target` 入口顺序 | 按下方"B1 定稿策略"实施分层规避 + 有界让位；补"带命令躲弹"验收场景 |
| B2 | Herbst 守卫缺口：`update_speed`/`update_g_load` 只查 cobra，Herbst 靠同帧双写自卫 | aircraft_physics.gd ~219 / ~361 | 守卫改查统一的 `is_maneuver_active()`（cobra 或 herbst），删 herbst 的自卫双写 |
| B3 | `evasion_mode` 裸写绕过边界缩放：AI 进出规避不走 `set_evasion_mode` | missile_evasion.gd 4 处 | 全部改走入口（入口需支持"AI 调用不广播 escort_cover"的参数） |
| B4 | 编队死代码误导：旧 `_update_heading`/`_update_bank`/blend 公式仍在文件里，搜"谁写 bank"必命中 | aircraft_formation.gd ~334-428 | 直接删除（live 路径已走 AircraftPhysics PD） |
| B5 | `_update_friendly_squad_lod` docstring 与实现矛盾（说三档、实际全钉 LOD0） | survivor_mode.gd ~2000 | 改注释对齐现实，LOD 归属留给 Phase 4 |
| B6 | test_bfm_intent（73 case）没接 bench_runner，只能游戏内 F10 | bench_runner.gd if-chain | 加 `--bench=bfm_intent` 分支 + 非零退出码 |

**B1 定稿策略（2026-07-02 用户拍板）——分层规避 + 有界让位**：

1. **仅被锁定 / 周围只有打不到自己的导弹** → 不进入 EVADE、不脱离命令。威胁判定必须
   过滤"根本无法命中"的导弹（非本机目标 / 能量学上追不上 / 已越过最近点），被持续锁定
   本身不构成脱离命令的理由。
2. **有真实威胁导弹 + flare 可用** → 扔 flare，继续执行命令航线，**不改航向不进 EVADE**
   （多数导弹到此为止）。
3. **flare 不可用**（弹尽/冷却）或 flare 后导弹仍逼近 → 进入运动学规避（加速/急转），
   此时命令铁律让位：`commanded_target` 保留不清，脱险即恢复追命令目标。
4. **EVADE 的维持条件 = 每 tick 重新确认存在真实威胁导弹**，条件消失立即退出——
   从机制上杜绝"因被锁/不构成威胁的导弹而无限脱离命令"。

---

## §4 重构目标与原则

**目标**：不是重写物理或 AI 算法（PD 控制器、planner 的 intent 都是好的），而是给
"谁可以在什么时候写飞机的哪个字段"建立**单一所有权 + 显式仲裁**，让新增控制者的成本
从"全矩阵补 if"降到"注册一个带优先级的请求"。

**原则**：

1. **意图与执行分离**：所有控制者（planner/旧 BFM/规避/编队/机动/BOSS/玩家/directive）
   只允许**提交意图**（我想让飞机去哪/多快/什么高度，来源+优先级），每帧由唯一仲裁点
   决出最终意图，物理层只读最终意图。物理字段（speed/heading/bank/altitude/position）
   只有 AircraftPhysics 一个写者。
2. **正交模态显式化**：`_state` 只保留行为模式，evasion/directive/manual/编队是叠加
   modifier；横切行为（leash）实现一次、对全模式生效。
3. **进出状态过渡函数收口**：每个模态的 enter/exit 是唯一一对函数，字段清单只写一遍。
4. **每阶段有 harness 验收 + 可独立回滚**——沿用 SEAM-012 的成功经验（无头量化，
   不靠肉眼）。turn_physics / rejoin / weapon / escort / target_sel 基准在每阶段前后
   跑一遍作为回归防线。
5. **小步走**：禁止大爆炸重写。每阶段结束游戏可玩、bench 全绿、可以停在那里。

---

## §5 分阶段计划

### Phase 0 · 安全网 + 速赢（风险：极低）

- §3 的 B1~B6 全部落地。
- bench_runner 统一化：所有测试输出统一 PASS/FAIL + 非零退出码，一条命令跑全量
  （`--bench=all`），作为后续每阶段的回归门。
- 新增两个**行为级**验收场景（无头）：①带命令躲弹恢复（B1 的守护测试）；
  ②切控交接后旧机状态收敛。
- known-seams 追加本文档发现的新 seam 条目（herbst 守卫缺口、lod_level 拔河、
  铁律×EVADE）。

**验收**：`--bench=all` 全绿；游戏行为无预期外变化。

### Phase 1 · 控制意图收口（核心，风险：中）

> **Step 1 已落地（2026-07-04）**：ControlIntent + Aircraft 意图槽（submit/withdraw/
> _resolve_intents，按字段 sticky 仲裁）+ 首批迁移 planner/hard_brake/规避（三者同批，
> 见下方实施设计）。验收 `--bench=intent` 14 断言 + 回归门 10 项全绿。
> 关键实现事实：①`_update_evasion` 几何写有 use_tactical_preference 门（仅玩家），
> 与 AI 的 process_evade 天然互斥 → 安全合并进同一 EVADE 槽；②BRAKE 桥接 pursuit
> 用 25 特例优先级（压 TACTIC 让位 EVADE），与旧帧序精确等价；③AB 主张过
> set_afterburner 守卫（冷却连关也挡，迁移前同语义）。
> **目标仲裁器已落地（2026-07-04）**：`acquire_target(tgt, source)` / `release_target(source)`
> 四级仲裁（TS_COMMANDED > TS_DIRECTIVE > TS_BOSS > TS_SCORED），低级源不得抢占/清除
> 高级源持有的存活目标（死亡自动降级）。全库 30+ 直写点迁移完成（外部：HUD/spawner/
> ace/poltergeist/swarm/mother_goose/commander_aura；内部：try_engage/reevaluate/
> disengage/squad 三路/directive/simple 全家），三处"军备竞赛"注释删除——玩家命令铁律
> 与 BOSS 指派从"靠约定"变成"靠代码"。验收 `--bench=target_arb` 17 断言 + 回归门 11 项全绿。
> **剩余步骤**：BOSS/剧本的 pursuit 直写迁移（step 4，低优先级——simple 机无槽位冲突）
> → 旧 BFM/_process_simple 的 pursuit 提交（step 5）→ Phase 2 状态正交化。

引入 `ControlIntent`（或沿用/扩展 TacticalPlan 的形态）：

```
ControlIntent { source: enum, priority: int,
                pursuit_pos, target_speed_kmh, target_altitude_tier,
                afterburner, weapon_mode, ... }
```

- Aircraft 上一个 `intent_arbiter`：各控制者每 tick `submit(intent)`，物理帧开头
  `resolve()` 决出胜者写入现有 target_* 字段（**物理管线本身不动**，消费端零改动）。
- 优先级固化为一张表（取代散布的 early-return 顺序）：
  `manual > maneuver(cobra/herbst) > evade(有界) > commanded(铁律) > directive > boss/swarm > tactic(planner/BFM) > formation > cruise`
  ——evade 高于 commanded 但**有界**（B1 定稿策略：flare 优先不脱离；仅真实威胁 +
  无 flare 才让位；威胁消失立即归还控制权）。
- 迁移顺序（每步一个 commit，随时可停）：
  1. planner 的 `_apply_tactical_plan` → 提交 intent（行为等价验证）
  2. 规避（missile_evasion + `_update_evasion`）
  3. 机动模块（cobra/herbst 变成提交最高优先级 intent，**删除全部散点守卫 if**——
     R1 的守卫矩阵在这一步整体退役）
  4. BOSS/剧本/spawner 的直写 → 提交 intent（军备竞赛注释随之删除）
  5. 旧 BFM 执行器与 `_process_simple`（写 target_position 的部分）
- `is_afterburner` / `evasion_mode` 裸写全部收进入口（AB 的"压 false"类写者
  ——status_effects/FEAR/没油——改为仲裁器里的 veto 位，而不是事后覆盖）。

**Step 1 实施设计（2026-07-03 细化，动手前必读）**：

1. **Sticky slot 模型**：仲裁器持 `slots: Dictionary[source → ControlIntent]`。
   `submit(intent)` 替换该 source 的槽位（AI 分频写入者的主张在两次 tick 之间保持有效，
   天然解决慢写快读）；`withdraw(source)` 撤销（enter/exit 生命周期对称调用）；
   `resolve()` 在每物理帧**所有决策系统跑完之后、物理链消费之前**执行
   （LOD0 = update_combat 与 energy_management 之间）。
2. **按字段仲裁，不是按槽位整体仲裁**：每个字段（pursuit_pos / target_speed_kmh /
   afterburner）独立取"主张了该字段的最高优先级槽位"。ControlIntent 用哨兵表示
   "不主张"（pursuit=INF / speed=-1 / ab=-1）。这样 EVADE 的分权协作自然表达：
   evade 槽只主张方向，planner 的 EVADE intent 只主张速度+AB —— 现行为零改动。
3. **首批仲裁字段只有 3 个**：pursuit_pos / target_speed_kmh / afterburner。
   weapon_mode / is_firing / _gun_lead_heading / 高度 tier 留在 `_apply_tactical_plan`
   直写（写入者少，后批迁）。
4. **迁移最小集 = planner + hard_brake + 规避（三者一起）**：不能只迁 planner——
   现行为里 `_update_evasion`（帧序③）覆盖 planner（帧序①）的 target_position，
   若 planner 走 resolve（帧序④后）而 evade 仍直写③，planner 会反过来压掉 evade
   → 行为改变。三者必须同批。
5. **⚠ 已知陷阱：规避有两个 target_position 写入者**——`Aircraft._update_evasion`
   （60Hz，evasion_mode 时的 S 型/玩家 E）与 `MissileEvasion.process_evade`
   （AI tick，垂直 break）。当前靠"AIController 树序后跑"决定 process_evade 当帧胜、
   下帧又被③盖。迁移前必须先读清两者各自的触发条件（玩家 vs AI、evasion_mode vs
   _state）并在 EVADE 槽内合并成单一写入者，否则等价性破坏。
6. **共存原则**：未迁移的直写者（旧 BFM 敌机 / _process_simple / EM / 编队）不受影响
   ——非 planner 机没有槽位，resolve 空转；编队短路路径不经过 resolve。
7. **日志**：resolve 胜者集合变化时打一行 `INTENT_RESOLVE`（source→字段清单），
   频率上限 ~2Hz/机防刷屏。
8. **验收**：`--bench=all` 全绿 + demo 场景肉眼对照 + EventLogger 抽查
   "PLAN 与 INTENT_RESOLVE 一致"。
- **目标仲裁器**（`_current_target`/`combat_target` 的 40+ 写点）同模式收口：
  `set_target(source, priority)` 四级 `commanded > directive > boss/swarm > scored`，
  外部系统（HUD/spawner/BOSS/SwarmDirector）不再触碰 `_state` 与私有字段。

**验收**：turn_physics/rejoin/weapon/escort 无回归；EventLogger 加一条
`INTENT_RESOLVE`（谁提交、谁胜出）——**从此调试"飞机为什么这么飞"变成看一行日志**，
这是本次重构对 debug 体验的最大回报。

### Phase 2 · 状态机正交化（风险：中）

> **已落地（2026-07-05）**：`--bench=state_machine` 15 断言 + 回归门 17 项全绿。
> 关键实现事实：
> ①`AIState` 收缩为三值，`_evading` modifier 由 MissileEvasion enter/exit 独占（enter 幂等；
>   exit 三路重定复用过渡函数）；分发层 `if _evading` 短路排在铁律之前（B1 让位保持）。
> ②过渡函数 `enter_engage_state(reset_plan)` / `reset_tactical_plan()` / `enter_squad_follow_state(snap)` /
>   `enter_patrol_state(pick_waypoint)` 收口全部 23 个 _state 写点（含 HUD/ace/poltergeist
>   外部直写→API）。软重连语义（reset_plan=false）覆盖 BOSS 维持/躲弹恢复/directive。
> ③约束层 `_apply_constraints`（节流后、分发前）：combat_zone + 小队 leash 合一，
>   交战/躲弹一视同仁（SEAM-010 三份拷贝退役）；铁律豁免仅 ENGAGE（EVADE 无豁免=旧语义）。
> ④踩点修正：spawn 守卫/escort 分支/pilot_personality 压力累积各加 `not _evading` 门
>   （背景 _state 滞留 ENGAGE/PATROL 时旧读者会误判）。
> ⑤已知小改（记录在案）：躲弹恢复交战时 `_engage_timer` 重置（旧不重置——
>   躲完的机 engage_duration 重新计时，脱离稍晚，可接受）；zone 出界时若在躲弹，
>   现在躲完才回拉（旧代码直改 _state 会泄漏 evade 意图槽——顺手修了个潜在 bug）。

- `_state` 收缩为 `PATROL / ENGAGE / SQUAD_FOLLOW`；EVADE 变成 modifier
  （`_evading: bool`，由 missile_evasion 独占进出），directive/manual 已天然是旁路，
  显式登记为 modifier。
- 每个模态一对 `enter_x()/exit_x()` 过渡函数，字段清单唯一化；切控交接复用同一套。
- leash / containment 等横切行为移到状态机外的统一位置（每 tick 一次，对所有模式生效），
  SEAM-010 的"约束"段从此不需要人肉遍历状态清单。
- `_state` 的外部直写（HUD/spawner/BOSS 剩余）全部改走 API。

**验收**：新增状态机迁移无头测试（输入 状态+威胁快照 → 断言 next state + 字段写集合）；
带命令躲弹、僚机护卫、BOSS 追击三个场景回归。

### Phase 3 · 战术执行器归一（风险：中低，收益：删代码）

> **物理子切片 1 已落地（2026-08-27）**：速度目标约束与速度积分提取为
> `AircraftPhysics._speed_target_ms` / `_integrate_speed_ms`，实飞 `update_speed` 与预测
> `step_speed` 只保留状态解包薄壳，删除约 85 行镜像公式；同时修正 Typhoon 超巡爬升
> 豁免只存在于实飞侧的预测漂移。`predicted_path` 新增正常飞行 180 步 + 急刹 120 步
> 逐帧同值断言；focused 与 `all`（83 项 + lifecycle 82）通过。
> **物理子切片 2 已落地（2026-08-27）**：目标航向、协调转弯航向积分、高度积分继续
> 提取为 `_target_heading_state` / `_integrate_heading_rad` / `_integrate_altitude_state`；
> `predicted_path` 扩到 12 项逐帧同值断言，并收掉 Typhoon 爬升率 ×1.5 仅存在于实飞侧的
> 第二处预测漂移。至此除 bank 控制器外，主要 update/step 物理镜像均已单一化。
> **物理子切片 3 已落地（2026-08-27）**：方向锁状态迁移、坡度帽、滚转权限、失速回正及
> bank-rate EMA 积分提取为共享纯函数，`update_bank` / `step_bank` 只保留状态与日志薄壳；
> `predicted_path` 扩到 13 项，新增滚转 240 步逐帧同值断言。至此主要 update/step 飞行物理
> 镜像已全部单一化，SEAM-017 不再依赖人肉同步。
> **AI 子切片 1 已落地（2026-08-27）**：巡逻、远距作战偏好与近距匹配高度从 legacy
> `BFMTactics` 移入无状态 `AIAltitudePolicy`；AI 状态过渡与导弹规避恢复不再为一个飞行
> 剖面 helper 依赖整套旧执行器。`state_machine` 增加连续高度、包线钳制、近距匹配与
> 扁平档位 4 项行为断言。
> **AI 子切片 2 已落地（2026-08-27）**：新增无状态 `PursuitGeometry`，把机炮两轮前置、
> simple UAV、护驾自爆机与忠诚无人机的闭合时间外推收进同一几何模块；各调用点保留原
> 预测窗、闭合速度与 lead 系数，`bfm_intent` 以公式等价断言防行为漂移。
> **AI 子切片 3 已落地（2026-08-27）**：全功能 AI 主路由强制启用 TacticalPlanner，
> simple AI 保留低成本独立路径；删除已不可达的 `BFMTactics` 九执行器、分发块与迁移期开关
> `ENABLE_PLANNER_FOR_REGULAR_AI`。演出体若关闭 planner，必须同时停用 AIController。

前提：沙盒模式已按项目入口约定废弃，只保留物理调试用途，不再作为正式玩法兼容目标。

- ~~全功能 AI 统一走 planner，整体删除 BFMTactics 9 执行器。~~ **执行器与分发已删除；**
  旧兼容状态字段仍有目标选择、飞行员心理、王牌脚本与测试引用，留待下一小切片逐项改名/
  删除。yo-yo 若实测需要，作为新 intent 重新设计，不恢复旧执行器。
- PilotPersonality 误差注入在 planner 路径补对等接入点（apply 到 resolve 后的 intent，
  单点注入，符合 SEAM-001 的 accessor 哲学）——恢复"飞行员会犯错"。
- ~~`_process_simple` 与 `_process_drone_engage` 的 lead-pursuit 换用共享纯函数。~~
  **首批已完成**：机炮 / simple / drone / kamikaze 四条外推路由已归入 `PursuitGeometry`；
  特殊 swarm lane、standoff、joust 继续保留各自战术语义。
- ~~`update_*` vs `step_*`：逐对提取共享纯函数（`compute_target_bank` 已是样板），
  两侧变成薄壳，"人肉同步"注释删除。~~ **已完成（2026-08-27，物理子切片 1~3）。**
- 编队私有 speed/altitude/position 物理收口到 AircraftPhysics
  （复制 2026-06-07 bank/heading 收口的成功路径）；收口后删除
  "每帧回写 target_speed_kmh 防残留"补丁。

**验收**：turn_physics + rejoin + weapon 全绿；净删代码量预期 1000+ 行；
FEAR/overshoot 等"多处同步"清单归一。

### Phase 4 · 频率与 LOD 所有权（风险：低，最后做）

- `lod_level` 单一 owner：survivor_mode 是唯一决策者，AI/编队通过请求位表达需求
  （或反转：Aircraft 自决，mode 只提供相机信息——二选一，定稿时决定）；
  删除生存模式不可达的 LOD1 非编队死分支。
- 在 Phase 1~3 消掉"慢写快读"死点之后，把 `ai_tick_divisor` 恢复 ≥3 并用 harness
  验证（守后拦截位等参照 SEAM-011 的"缓存本地系不变量"模式改造）——把性能守则
  从"形同虚设"变回事实。
- survivor_mode._physics_process 的隐式时序依赖显式化（顺序注释 → 断言或
  process_priority 声明）。

**验收**：divisor=3 下 turn_physics/编队/躲弹全绿 + Lv5 压力测试 FPS 不降反升。

### 收尾 · 文档对齐

- ai-system.md 重写为"planner 是主路径"的现实架构；squad-tactics-design.md 草案部分
  标注 superseded；script-index / code-index 全量刷新行号；
  CLAUDE.md 类树修正（Squad extends Resource）。

---

## §6 排期与依赖

```
Phase 0 (安全网)  ──►  Phase 1 (意图仲裁)  ──►  Phase 2 (状态正交化+约束层)  ──►  Phase 3 (执行器归一)  ──►  Phase 4 (频率/LOD)
   独立小修                核心，最大收益            依赖 P1 的仲裁器                依赖沙盒废弃决定           依赖 P1-P3 消死点
                                                        │
                                                        └──►  Phase 5 (小队学说层，可选后续)
                                                              角色分配 + 包抄/护卫协同，见 §7
```

- P0 可与进化系统开发并行；P1 起建议独立 `refactor/control-authority` 分支，
  避免与 feature/aircraft-evolution 的未提交工作互踩。
- P1 是收益/风险比最高的一段：完成后"加新控制者"与"debug 谁在抢权"两个日常痛点
  直接解决；P2~P4 可视精力逐个排期，每段之间游戏始终可玩。

## §7 目标战术行为的接入映射（2026-07-02 增补）

用户提出三类目标行为，作为重构架构的设计约束与验收用例登记于此。共同原则：
**新行为 = 新意图纯函数 / 新约束 / 新角色，各自只有一个注入点**，禁止再出现
"散点写 target_position + 全矩阵补守卫"的接法。

### 7.1 区域保护（anchor / 围绕区域作战）

历史症状"飞机莫名其妙飞远、debug 查不出"= R1（target_position 无主）+ SEAM-010
（leash 按状态散点实现漏 EVADE）的直接体感。落点：

- **anchor 是约束（constraint），不是状态**。Phase 2 把 leash/containment 抽成统一
  约束层后，anchor 作为第一等公民接入，在仲裁 `resolve()` **之后**统一执行一次，
  对所有模式（含 EVADE）生效。三个执行点，全部集中在约束层与评分器：
  1. **目标筛选**：target_selection 评分对 anchor 半径外的候选重罚/排除
     （追出去的源头掐掉）；
  2. **几何钳制**：resolve 后的 pursuit_pos 若在 anchor 半径外，投影回半径边界
     （追到边缘自然回卷，形成"围绕区域缠斗"）；
  3. **回归意图**：超出硬半径时由约束层提交高优先级 RETURN_TO_ANCHOR 意图。
- anchor 来源：玩家 RTS 指令（"防守这个区域"，经 SquadCommandController 提交，
  与 commanded_target 同级铁律语义）/ 剧本 directive / 小队学说层（§7.3）。
- **可解释性**：`INTENT_RESOLVE` 日志加 constraint 字段——"为什么飞远了"从猜谜变成
  一行日志（谁的意图胜出 + anchor 约束是否生效 + 钳制前后坐标）。
- **验收**：无头场景"anchor + 波次敌机 + 来袭导弹"，量化指标 = 全程距 anchor
  最大距离 ≤ 硬半径（含规避期间——这正是 SEAM-010 当年漏掉的状态）。

### 7.2 协同作战（护卫长机 / 多机包抄）→ Phase 5 小队学说层

"战术是否生效很难判断" = 小队行为散在 squad_coordination 的扫描分支里，没有
显式的"角色"概念可观察。落点（此层是**新增工作**，计划为 Phase 5，前置 P1+P2）：

- **SquadDoctrine（小队级角色分配器）**：低频（0.5~1s，仿 AceSquad 软重连的正面样板，
  规避 SEAM-011 的慢写快读——只写"角色 + 本地系几何"，不写世界坐标死点）。
  输出每个成员一个 **role**：`ENGAGE(target) / COVER_LEADER / BRACKET_L / BRACKET_R /
  REAR_GUARD / RTB` 等。
- role 是**数据不是控制**：写进 Situation（新字段 `squad_role`），由各机自己的
  TacticalPlanner 在决策树里消化（BRACKET_L → lateral offset 意图；COVER_LEADER →
  盯长机后半球目标优先）。doctrine 层**不直接写任何飞机字段**——与 40+ 直写点的
  历史模式彻底切割。现有 `_apply_squad_lateral_offset` / escort 评分 / 守后逻辑
  是这层的雏形，迁入后归一。
- **可观察性是本层的硬验收**：F11 调试覆盖层（复用现有编队 debug 覆盖层的模式，
  遵守性能守则）给每机画 role + 当前 intent + 仲裁胜者标签；EventLogger 加
  `ROLE_ASSIGN` 事件。"战术有没有生效"从盯行为猜，变成看标签。
- 注：这实质是复活 squad-tactics-design.md 的学说草案，但架构上骑在意图仲裁器上，
  而不是当年设想的直接操纵层。该 spec 届时按 spec-first 流程重写定稿。

### 7.3 进阶物理机动（高性能机 / 高等级驾驶员专属）

**(a) 高度换速度 / 爬升占位**：物理通路已存在（PE↔KE 耦合，SEAM-009），缺的只是
决策表达。落点 = **新 intent 纯函数**（Phase 3 之后加入）：如 `DIVE_EXTEND`
（俯冲脱离，牺牲高度换瞬时加速）、`CLIMB_PERCH`（能量优势时爬升占位，即 yo-yo
族的现代化版本——Phase 3 "yo-yo 若需要作为 intent 补齐"即指此处）。
门控 = Situation 里的 `ai_aggression` / PilotPersonality effective_skill /
机型 params（走 effective_*() accessor，SEAM-001 纪律）——低级驾驶员根本进不了
该决策分支，天然形成"高手才会的巧思"。每个 intent 一个纯函数 + planner 决策树
一个节点 + test_bfm_intent 若干 case，无头可测。

**(b) 导弹弹道预测 + 时机急转**：落点 = **evade modifier 模块内部升级**
（missile_evasion 独占，不新增写入者）。Phase 3 把 update_*/step_* 收口成共享
纯函数后，这些 step 函数可以直接拿来做前向仿真：预测导弹最近点时刻，在最优
时间窗触发 break（替代现在的"进入阈值即 commit 方向"）。技能门控同 (a)。
**验收**：无头 bench 场景批量打弹，量化"脱靶距离 vs 驾驶员等级"曲线单调上升
（和 turn_physics 一样双指标量化，不靠肉眼）。

### 7.4 为什么这套接法不再炸 bug

| 今天加一个行为 | 重构后加一个行为 |
|---|---|
| 新写入者直写 target_position/speed | 提交带来源+优先级的意图，物理只有一个写者 |
| 在 N 个状态/守卫里补 if，漏一处静默失效 | 约束层执行一次，对所有模式生效 |
| 行为对不对靠进游戏肉眼看 | intent 纯函数无头测试 + bench 量化指标 |
| 出问题翻 8 个文件找谁抢了权 | 看 INTENT_RESOLVE / ROLE_ASSIGN 日志 |

**排期约束**：三类行为都**不要**在 Phase 2 完成前动工——现在做就是给旧架构再添
三个争抢写入者，重蹈 leash/规避加力的覆辙。建议顺序：区域保护（作为 Phase 2
约束层的首个验收用例）→ Phase 5 学说层 → 进阶机动（依赖 Phase 3 的共享 step 函数）。

## §8 明确不做什么

- 不改 PD 转弯控制器、PN 制导、planner intent 的战术数值（SEAM-012/013 已根治，别碰）。
- 不重写 Situation/BfmIntent/TacticalPlan——它们的纯数据/纯函数形态正是本计划的范本。
- 不动武器系统、雷达、伤害路由（另属其它 seam）。
- 不追求"一个大 FlightController 类"——收口的是**写入权**，不是把代码搬进一个上帝类。

---

## §9 交接快照（2026-07-05，上下文切换点——下个会话从这里展开）

### 分支布局（重要！）
- **refactor/control-authority**（当前工作区所在）：重构 + 武器准则全部工作，tip=ba63ef5。
- **feature/map-editor**：用户的地图编辑器线（tip=46b7406），与重构线同基底（75fea9f）互不包含。
  ⚠ 在 map-editor 分支上武器修复不存在（机炮侧射会复现）——两线终将各自合 main。
- backup/map-editor-premix：分支手术前的保险，确认无误可删。
- 回归门：通过 `bench/run.cmd all` / `bench/run.sh all` 运行；跨分支切换后的导入也交给 wrapper
  的隔离流程处理，禁止 Agent 直接启动 Godot CLI。
- Godot 路径与版本以根目录 `AGENTS.md` 为准（当前要求 4.7+）；观察场通过 `bench/run.cmd weapon_demo` 启动。

### ✅ 电磁炮锁定线 bug（2026-07-05 已修，待用户 playtest 确认）
真因与上一版快照假设不同：enemy_railgun.tres 实为 **AT_FIRE_TIME**（tres 值 1；注释
说敌人用 AT_CHARGE_START 是误导），telegraph 锚点本就消费 locked_aim_pos，逐帧几何
一致。真正分叉：①miss-roll（基础 15%+云 30%+低空 20%）在**发射瞬间**才扰动方向
2.3°~5.7°；②fire_along_nose 型（MQ-112）telegraph 与 _fire 都读**当前机头**，
0.6s 锁定相位机头继续追踪——"扇形冻结在预测线上"从未发生，躲了指示线仍被追着打。
修法：`RailgunEquipment._commit_fire_solution`（充能完成瞬间定死弹道解，miss 扰动
烘焙进 locked_aim_pos）+ telegraph awaiting 锚点优先级/全射程/有效射程同源。
spec weapon-employment-doctrine §8 v5 有完整记录。回归门 14 项全绿。

### 待办（按优先级）
1. ~~电磁炮修复 playtest 确认 + MRM 对比局归因~~ **已结（2026-07-05）**：log 175843
   归因过线（命中 44%→79%、目标已消失/末段丢锁 各 19%→5%）→ spec
   weapon-employment-doctrine **转 done**。
2. **joust 攻击跑 playtest**（spec joust-attack-run，bench 7/7 已过）：用户实测两点
   ①MG 战 MQ-110/112 现在会"对准冲进 5000m→充能/射弹→脱离折返"（对照 log 183044
   全场 0 充能死锁）②骑士型 Lancer（J-7/F-104/F-100/MiG-31）读感"冲锋-脱离-折返"
   （engage_duration 定时器伪打带跑已由 joust 自循环取代）。过 → spec 转 done。
3. 观察项（用户已知，待拍板是否做）：①电磁炮竞选无超杀去重——开局 5 机集火同一 UAV；
   ②QMAAM 格斗弹无人挂载（预留资源，装备位设计机会）；③电磁炮射击节奏（cooldown 数值活）。
4. 重构主线：~~Phase 2 状态正交化+约束层~~ **已落地（2026-07-05）**；
   ~~Phase 3 执行器归一~~ **已落地（2026-08-27）**：全功能 AI 统一 TacticalPlanner，
   旧 BFMTactics、EngageTactic、SituationData 与迁移期开关已删除；update/step 物理积分同源，
   PilotPersonality 改读 TacticalPlan intent。下一块为 Phase 4 频率/LOD → Phase 5 小队学说层（§7）。
   anchor 区域保护（§7.1）的地基已就位（约束层 _apply_constraints），命令轮盘
   "防守此区"实装时直接在约束层加第三条。
5. 小项：legacy AI 直读 params 带（SEAM-001 备注，给敌机加状态型 buff 前必修）、
   `set_target_ground()`（poltergeist 裸写双字段）、hard_brake 多选僚机... （已结清）。

### 本会话累计（供追溯）
Phase 0 安全网 / flare 命中 bug / 物理审计 5 修 / 急刹重设计 / Phase 1 意图仲裁器 +
目标仲裁器 / 机炮侧射修复 / 武器准则 spec 四阶段（竞选/planner 接入/LINE_UP/观察场）/
MRM 包络仲裁仿真（FOV90 定案）。changelogs：2026-07-03-phase0-* 与 2026-07-04-phase1-*。
