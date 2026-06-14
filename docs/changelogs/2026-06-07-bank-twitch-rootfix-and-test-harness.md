# 2026-06-07 — 机身颤抖根治（多层）+ 无头物理测试 harness + 自动战斗 demo

spec: [docs/specs/systems/squad-cohesion.md](../specs/systems/squad-cohesion.md) §3.6 ·
seam: [docs/architecture/known-seams.md](../architecture/known-seams.md) SEAM-011 / SEAM-012

## 起因
用户反复反馈"机身剧烈颤抖/抽搐"：僚机急转、归队、缠斗、躲弹等场景机身来回扭。要求**真实物理优雅**
（俯视全程可见，不靠强扭轨迹），并明确要**建一套能自己模拟+自动测试的系统**，不要每次进引擎手测。

## 新增工具（长期保留）

### 1. 无头物理仿真测试 — `scripts/tests/test_turn_physics.gd`
裸构造 Aircraft（不入树、不触发 _ready），逐帧调 `AircraftPhysics` 转弯物理，统计 bank「大摆幅反向」次数。
跨多机型（F-14/Su-27/F-86/MiG-23）× 多场景（J-turn/90°/30°/追转圈/近目标）。判据：平滑 ≤2~3 次。
运行：`godot --headless --path . -- --bench=turn_physics`（经 BenchRunner，autoload 可用）。

### 2. 自动战斗 demo（可视观察）— `--bench=demo`
复用 survivor bench 基建：玩家小队（强制 4 僚机）+ 全敌机成建制小队 + 玩家挂 AI 自动打 + 相机跟随 +
持续补敌；渲染运行、不退出。运行（**不加** --headless）：`godot --path . -- --bench=demo`。
入口：`bench_runner.gd`（demo 分支设 `bench_demo` meta）+ `survivor_mode.gd`（`_bench_demo`）。

## 颤抖根因（用 harness 逐层定位）+ 根治

| # | 层 | 根因 | 修复 |
|---|---|---|---|
| 1 | 屏内僚机不走编队逻辑 | `aircraft.gd` LOD0 路径**漏了 formation 分支**（LOD1/2 有），屏内僚机落到 planner 纯追击 | LOD0 补 `if formation_mode: update_follow; return` |
| 2 | 编队"慢一拍" | 槽位只在 AI 分频 tick 算成冻结世界死点 | `_build_context` 每帧 `leader.pos + committed_offset.rotated(leader.heading)` 实时算（SEAM-011） |
| 3 | 编队 leader-bank 镜像致"原地打滚" | bank 抄长机坡度，航向不变也镜像 → 滚而不转 | `_update_bank` 改 **bank ∝ 本帧实际转向速率**（协调转弯，bank 永远与航迹一致） |
| 4 | 编队分支边界横跳 | slot_d 在 400/50px 阈值 dither → target_heading 在两公式间逐帧跳 | 分支选择加迟滞 `_select_branch`（±45px） |
| 5 | 编队继承长机微抖 + bias 过中线翻号 | slot_local.x 过中线 bias 翻号；长机航向微抖透传 | bias 死区(35px) + target_heading EMA(0.08) + bank EMA(0.12) |
| 6 | **战斗 bank 台阶 dither** | `compute_target_bank` 全分支硬台阶(0→0.3→1.0×max) → 边界 dither | 全分支改连续 smoothstep 斜坡 |
| 7 | **战斗高 bank 追击过冲极限环**（F-86 类，最硬） | 过冲补偿用粗糙 `0.5·tan(B)` 近似且被 cap 卡死 → 接近目标不补偿 → 过冲 | 改**滚出航向变化精确积分** `(G/v)·t_roll·(-ln(cosB)/B)` + 允许减到 0 = **临界阻尼**（SEAM-012） |
| 8 | `combat_full_bank_diff` 过激进 | 3~9° 航向误差就压满坡度 → 对准附近小抖被放大成 ±84° 猛甩 | 全 combat .tres 放宽到 ~14~20° 成比例 |
| 9 | 脱队后朝旧槽位压坡（PASSIVE_AUTO_FIRE 抖） | `clear_formation` 没清 target_position，旧编队槽位残留 | clear_formation 清 `target_position = INF` |
| 10 | 躲弹方向 dither | 规避每帧按"哪个垂直向更近"重选 → 左右跳 | 承诺 break 方向（`_evade_committed_dir`，进规避重置） |
| 11 | ENGAGE↔编队 leash thrash | leash 拽回未设冷却 → 归队下一帧又咬同一远目标，0.5s 反复横跳（combat线+槽位线一起抖） | leash break-off 后 `_cooldown_timer = max(engage_cooldown, 3.0)` |
| 12 | flare 残留不消失 | LOD0 formation 分支 return 前漏了 flare 粒子更新 | 三个 formation 分支补 `AircraftFlares.update` |

## harness 验证结果
- 隔离物理：20/20 场景平滑。
- 确定性战斗（mixed seed42）：bank 大摆幅最高 **501 次 → 个位数**。
- demo（编队+全敌队+躲弹）：多次 run 最高反向 4~9（好），偶发慢速机激进缠斗的大坡反转。

## 已知残留（下一任务）
慢速机（F-86 类）在**激进缠斗/硬转机动目标**时仍有少数大坡度反向。本质是飞行模型**战斗转弯控制器
欠阻尼**——本轮一路打补丁治标，要在任何激进机动下都丝滑需把控制器**重写成临界阻尼 PD**（target_turn_rate
= Kp·误差 − Kd·当前转速）。属有分量、需多轮、动全体战斗手感的工程，已记 SEAM-012，harness 可验证。

## 改动文件
- `scripts/aircraft.gd`（LOD0 formation 分支 + flare 更新 + clear_formation 清 target）
- `scripts/aircraft/aircraft_formation.gd`（实时槽位 / 转向速率 bank / 分支迟滞 / bias死区 / EMA×2 / 稳态吸附）
- `scripts/aircraft/aircraft_physics.gd`（compute_target_bank 连续斜坡 / 滚出精确积分临界阻尼）
- `scripts/ai_controller.gd`（committed offset / branch / EMA / evade committed dir / leash 冷却 字段）
- `scripts/ai/squad_coordination.gd`（process_squad_follow 写 committed + 新鲜槽位）
- `scripts/ai/missile_evasion.gd`（承诺 break 方向）
- `resources/*combat*.tres`（combat_full/half_bank_diff 放宽 ×6）
- `scripts/tests/test_turn_physics.gd`（新增 harness）
- `scripts/bench/bench_runner.gd` + `scripts/survivor/survivor_mode.gd`（demo 模式）
