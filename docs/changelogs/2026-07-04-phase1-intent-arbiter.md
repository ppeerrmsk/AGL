# 2026-07-04 · Phase 1 Step 1：控制意图仲裁器落地

> 上游：[docs/planning/physics-ai-control-refactor.md](../planning/physics-ai-control-refactor.md)
> §5 Phase 1 "Step 1 实施设计"。验收：`--bench=all` **10 项全绿**（新增 intent 14 断言）。

## 新机制

- **`scripts/aircraft/control_intent.gd`**：ControlIntent 值类型（SOURCE_TACTIC/EVADE/BRAKE
  + 优先级表 20/30/40）。哨兵约定：pursuit=INF / speed<0 / ab<0 = 不主张。
- **Aircraft 意图槽**：`submit_intent(source, ci)` / `withdraw_intent(source)` /
  `_resolve_intents(delta)`。sticky slot（AI 分频写入者的主张跨帧有效——SEAM-011
  模式的机制级根治）；**按字段仲裁**（EVADE 只主张方向、planner 的 EVADE intent 只主张
  速度+AB，分权协作零改动表达）；resolve 在决策系统后、物理链前，三条 LOD 路径各一个
  调用点；胜者变化打 `INTENT_RESOLVE` 日志（0.5s 节流）——"飞机为什么这么飞"可归因。

## 首批迁移（三者必须同批，见计划 §5 设计第 4 条）

- **planner**：`_apply_tactical_plan` 的 pursuit/speed/AB 三行直写 + hard_brake 覆盖块
  → 提交 TACTIC 意图（weapon/gun/高度仍直写，后批迁）。
- **hard_brake**：resolve 内桥接为 BRAKE 槽（速度/AB 满优先级；pursuit 用 25 特例
  ——压 TACTIC、让位 EVADE 蛇形几何，与旧"planner 帧顶写 INF → _update_evasion 稍后
  覆盖"的帧序精确等价）。
- **规避几何**：`_update_evasion`（玩家，60Hz）与 `process_evade`（AI，AI-tick）合并进
  同一 EVADE 槽——审计确认两者被 use_tactical_preference 门天然互斥，安全合并。
  withdraw 对称收口：`exit_evade` + `set_evasion_mode(false)`。

## 行为等价性验证

- 回归门 10 项全绿（turn_physics 符号反转 ≤2 / cmd_evade 25 / hard_brake 5 / escort 24 /
  weapon 7 / target_sel 7 / flare 9 / rejoin / bfm_intent 89）。
- 新 `--bench=intent` 14 断言：按字段仲裁 / 优先级 / sticky / withdraw / BRAKE 桥接 /
  "不主张不碰"（与未迁移直写者共存）/ AB 主张过 set_afterburner 守卫（SLOW 挡下）。
- 测试顺带确认一个迁移前既有语义：AB 冷却期内"关加力"请求也被守卫挡（物理无害，
  急刹时 update_speed 不吃 AB 推力）。

## 共存原则（迁移期间的约定）

未迁移的直写者（旧 BFM / `_process_simple` / EM / 编队 / BOSS / RTS 点击）不受影响：
无槽位主张的字段 resolve 不碰，直写值照常生效；planner 的 waypoint echo（读
target_position → 提交回同值）保持外部直写在 planner 机上的兼容。

---

# 追加（同日）：目标所有权仲裁器落地

## 新机制（ai_controller.gd "目标所有权仲裁" 段）

- `enum TargetSource { TS_NONE < TS_SCORED < TS_BOSS < TS_DIRECTIVE < TS_COMMANDED }`
- `acquire_target(tgt, source, why)` / `release_target(source, why)` —— 设/清目标唯一入口：
  低优先级请求不得抢占/清除高优先级持有的**存活**目标；目标死亡自动降级不再受保护；
  同目标重申不降级来源；TARGET_ACQ / TARGET_REL 归因日志。
- 入口只管目标字段 + 来源记账，状态切换/计时器副作用仍由调用方处理（Phase 2 收口）。

## 迁移（30+ 站点，11 文件）

外部直写者全部收口：survivor_hud（强制脱战=TS_COMMANDED）、survivor_spawner（猎手指派/
边界纪律=TS_BOSS）、ace_squad、poltergeist_squad、swarm_director、mother_goose_controller、
commander_aura（均 TS_BOSS）；内部：try_engage/reevaluate/disengage（TS_SCORED）、
squad_coordination 三路、directive（TS_DIRECTIVE）、_process_simple 全家。
返回值全部消化：被高优先级拒绝时跳过后续副作用（这正是仲裁要建立的保护）。
三处"军备竞赛"注释（spawner/swarm_director/poltergeist 描述与守卫层互相设防）删除。

**行为提升（原 bug 类，现在由代码保证）**：
- spawner 猎手/边界纪律不再能清掉玩家 commanded 目标（原靠"敌机没有 commanded"的巧合）；
- BOSS 指派的目标不会被普通 disengage/评分交战踢掉；
- HUD 强制脱战以 TS_COMMANDED 级执行（玩家意志压 AI）。

## 验收

新增 `--bench=target_arb` 17 断言（四级抢占/拒绝/死亡降级/同目标重申不降级/release 对称）。
回归门 **11 项全绿**（intent 14 / cmd_evade 25 / bfm_intent 89 / turn_physics 等全部通过）。
