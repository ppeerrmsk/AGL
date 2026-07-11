# 2026-07-09 交战纪律：无意图不开火 + AI 反平面同向缠斗

spec: [systems/engagement-discipline](../specs/systems/engagement-discipline.md)（in-progress，差 playtest）
来源 playtest：`logs/combat_log_20260709_220858.txt`（用户反馈两条）

## 诊断（两个同源病：缺"交战承诺"层）

1. **敌人无意图却机炮背刺路过玩家**：LOD0 每帧无条件调 `auto_gun_scan`，其 AI 分支在敌机**无 `combat_target`**（巡逻/刚脱战/丢目标）时会扫全场 `all_units`，任意敌对进 ±`fire_cone`+射程就锁 `is_firing` 开火。
2. **僚机+主角打一架 UAV 费劲还被反杀**：UAV 匀速高 G 大圈（log 233m/s / 5.8g / bank −80°）；主角被拽进平面同向缠斗，狂拉 11.5g 速度 362→195m/s 贴角点、`tp_brg` 常年 100~146° 机头带不到；UAV 匀速盘旋反在某圈抓快照反杀（324.8 UAV-10 击坠 Sorcerer；171.6 F-86 同款尾追机炮 2s 泼死 Warhound）。

## 改动

### A — 敌人开火纪律（`aircraft_weapons.gd` `auto_gun_scan`）
- AI 分支（`not use_tactical_preference`）**无条件 return**：机炮开火从此**唯一**来自"有 `combat_target` 时 combat_tracking 的追踪解开火判定"。无目标 AI 一律停火，不再兜底扫 `all_units`。
- 人类机（`use_tactical_preference`）独立扫射意识不变（2026-04-22 引入的路径保留）。
- 附带净收益：去掉一次无目标 AI 的全场 `all_units` 扫描 + 僚机不再对空放空枪。

### B — 反平面同向缠斗（`tactical_planner.gd` `_decide`）
- 新增"5b.2 能量感知 co-turn breaker"旁路 + `COTURN_BREAK_*` 6 常量。
- 触发（**仅 AI 控制机**，`not is_tactical_preference_user`）：`ai_aggression≤0.85` + `|tgt_bank|>60°`（硬盘旋）+ `aspect>70°`（没带到尾后）+ `my_speed≤corner×1.08`（能量磨到角点）+ 战斗 intent 已持续 `>2s` → 强制 `BOOM_ZOOM_OUT`（extend 3s 重建能量再换角度重攻）。
- 与既有 5b（`held>8s + aspect>80°`）互补：5b 是**时间**触发，5b.2 是**能量**触发（intent 抖动时攒不满 8s 也能脱出）。
- **绝不**强拽人类操控的长机——玩家走位是玩家的选择（[[feedback_player_command_iron_rule]] / [[feedback_no_stall_from_turning]]）。

## 验证
- `--bench=bfm_intent`：**92/92**（+2 新 case：能量空触发 BOOM_ZOOM_OUT / 人类机同条件不触发）。
- 回归：`gun_burst` 9/9 · `gun_aim` 6/6 · `weapon` 7/7 全绿。
- [ ] 生存 playtest：僚机对 UAV 会脱出重攻不被反杀；无意图敌机不再流弹背刺。

## 本轮范围外（用户明确未选）
- 僚机 2s `SQUAD_RANGE_GRACE` 脱战循环（log 264.7~284.9s Vigor 对 UAV-10 反复 acquire/2s-disengage 10+ 次）——"僚机打不动"的另一独立根因，建议下轮处理。
- UAV 敏捷不降（不 nerf 数值）。
