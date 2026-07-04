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
