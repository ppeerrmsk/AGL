---
id: rocket-ripple-trajectory
kind: weapon
status: done
schema_version: 1
spec_version: 3
owner: 用户（发射语义）+ Codex（距离与平滑曲线细化）
depends_on: [systems/weapon-employment-doctrine]
reconstruction_complete: true
---

# 火箭弹双侧涟发与延迟散开轨迹

> 敌我飞机的无制导火箭不再以出膛即成形的扇面一次喷出；它们从左右挂点逐发、平行直飞，离机一段距离后才平滑展开为原有散布扇面。

## 1. 设计意图（Why）

- **体验目标**：第一眼先读成“机翼两侧火箭巢连续发射”，随后才读成覆盖目标区域的无制导散布；消除旧版像近距离霰弹枪一样从机头瞬间炸开的观感。
- **敌我一致**：凡是通过 Aircraft 的 `RocketParams` 自动火控发射的火箭，PLAYER / ALLY / HOSTILE 共用同一涟发与弹道状态，不按阵营分支。
- **Litmus 自检**：保持自动开火、原弹量、伤害、引信、射程与最终散布半角；只提高动作可读性和发射质感，不引入现实武器分类或额外操作。
- **性能边界**：复用 BulletManager 的轻量 Dictionary 弹体；每枚火箭每物理帧只增加常数次标量运算，不建 Node、不扫场、不增加 draw call。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 RocketParams 轨迹字段

| 字段 | 默认值 | 单位 | 说明 |
|---|---:|---|---|
| `straight_flight_distance` | 180 | m | 出膛后保持发射瞬间机体航向、完全不施加散布的直飞距离 |
| `spread_transition_distance` | 320 | m | 从 0 散布平滑过渡到该弹最终散布角所需的后续距离 |
| `spread_angle` | 沿用各资源现值 | deg | 最终扇面半角；本机制只改变“何时到达该角度”，不改最终覆盖范围 |

所有现有飞机火箭资源不覆写前两项，统一继承 `180m + 320m`。脚本直发且没有散布偏移的特殊火箭退化为全程直线，不被强行加入扇面。

### 2.2 双侧涟发几何与节拍

| 项目 | 值/规则 |
|---|---|
| 前向挂点偏移 | 沿机头方向 24 px |
| 横向挂点偏移 | 左/右各 18 px |
| 发射顺序 | 左、右、左、右……逐发交替 |
| 单发间隔 | 每枚火箭相隔该资源的 `burst_interval`；不再把左右一对压在同一时刻 |
| 初始航向 | 每枚实际出膛当帧的飞机当前 `heading` |
| 最终散布偏移 | `burst_count_max` 枚在 `[-spread_angle, +spread_angle]` 内等距分配；单发时为 0° |

### 2.3 发射机速度继承

| 项目 | 值/规则 |
|---|---|
| 速度取样时刻 | 每枚火箭实际出膛当帧，不锁存齐射开始时速度 |
| 发射机输入 | Aircraft 当帧前向速度 `max(speed, 0)`，单位 m/s |
| 出膛地速 | `launch_speed = RocketParams.muzzle_velocity + aircraft.speed` |
| 阵营语义 | PLAYER / ALLY / HOSTILE 全部共用，不按机型或阵营分支 |

该加成为全量前向速度继承：飞机每快 `1m/s`，火箭的出膛地速同步提高 `1m/s`。射程仍以世界距离计，因此高速只缩短飞行时间，不额外延长射程。

## 3. 行为与公式（How）

### 3.1 发射状态

1. 自动火控的目标、距离、高差、机头锥、JAM、加力禁攻、冷却与弹药门保持原样。
2. 一次齐射仍取 `burst_count_max` 并受剩余弹药钳制；队列仅保存 delay、左右挂点与最终散布偏移。
3. delay 到期时，从飞机当帧姿态计算挂点与初始航向，并取当帧前向速度叠加到火箭自身初速后交给 BulletManager；飞机在涟发期间转动或变速时，后续火箭自然跟随新的机体姿态出膛。

### 3.2 延迟散开曲线

令 `d` 为该弹累计飞行距离（m），`d0 = 180m`，`ds = 320m`，最终散布偏移为 `A`：

```text
t = clamp((d - d0) / ds, 0, 1)
smooth = t² × (3 - 2t)
target_applied_angle = A × smooth
frame_rotation = target_applied_angle - previous_applied_angle
```

- `d ≤ 180m`：`smooth = 0`，两侧火箭保持平行直飞。
- `180m < d < 500m`：每帧只施加曲线新增的角度，慢慢展开。
- `d ≥ 500m`：累计偏转达到原有 `A`，后续维持当前航向，远端观感回到旧版扇面。
- 使用“逐帧增量旋转”而不是把速度重置到绝对航向，保证玩家的火箭追踪强化仍可叠加；追踪选敌与转向在 180m 直飞段结束后才启用，所有火箭的近机段都保持直线。
- 累计距离按真实速度积分，不按寿命百分比，因此不同初速的火箭都在同一世界距离开始散开。

### 3.3 保持不变

| 既有语义 | 处理 |
|---|---|
| 自动开火条件与武器使用准则 | 不变 |
| 齐射弹数、总弹药、齐射大冷却 | 不变 |
| 最终 `spread_angle` | 不变 |
| 资源自身初速 | 数值不变；实际出膛地速额外叠加发射机当帧前向速度 |
| 最大射程、伤害与距离衰减 | 不变 |
| 直击、近炸、AOE、建筑遮挡、高度判定 | 不变 |
| 橙红尾迹与白色弹头 | 不变 |
| Black Star 等脚本直发且无散布偏移的火箭 | 保持其既定直线弹道 |

## 4. 结构与组成（Structure）

- `RocketParams` 持有两段距离参数，敌我资源默认继承。
- Aircraft 武器队列负责逐发左右交替和最终散布槽位分配。
- BulletManager 在已有火箭弹体 Dictionary 中保存累计距离、最终偏移与已施加偏移，并在现有物理循环内更新。
- 视觉仍完全消费 BulletManager 的真实 `pos/vel`；没有独立演出轨迹或仅供截图的替身逻辑。

## 5. 验收标准（Acceptance / Litmus）

- [x] `--bench=rocket_trajectory` 50/50：0–180m 累计偏转严格为 0；250m 处只完成部分偏转；500m 处达到完整原散布角，PLAYER / HOSTILE 实际出膛入口一致。
- [x] 静止发射机仍为资源自身初速；发射机增速 `Δv` 时，火箭出膛地速同步增加 `Δv`；589 kt F-104C 发射 320m/s FFAR 时地速约 623m/s。
- [x] `--bench=rocket_trajectory`：8 发队列按左右交替、每发 `burst_interval` 递增，最终偏移覆盖 `[-spread,+spread]`。
- [x] 敌我均走相同参数与生成入口；无阵营专用弹道分支。
- [x] Visual 样张：近段两条平行火箭流清晰，中段连续展开，远段形成旧版扇面且无画面裁切。
- [x] 原伤害、引信、射程与追踪强化回归通过：weapon 29/29、bullet_grid 8/8、sig_skills 78/78、hyper_a 52/52。
- [x] 性能：无新增 Node / 扫描 / draw call；Sentinel + Lv15、45 架/38 敌压力样本最后一秒 145 帧，BulletManager 物理 45µs/帧。
- [x] 文档：spec、总表与 reference 索引一致，当前文档校验通过。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 参数与发射队列
- [x] RocketParams 增加两段距离默认值。
- [x] 齐射队列改为左右逐发交替、每发独立 delay、出膛时读取当前机体航向。

### 阶段 2 — 共享弹道
- [x] BulletManager 记录累计距离并按 smoothstep 增量施加散布。
- [x] 追踪强化延后到直飞段结束，并与增量散布兼容。

### 阶段 3 — 验证与索引
- [x] 增加 `rocket_trajectory` 无头专项测试并注册。
- [x] 增加真实 BulletManager Visual 样张并检查近/中/远三段。
- [x] 同步 script-index / code-index，跑文档校验与相关回归。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 轨迹参数 | `scripts/rocket_params.gd` |
| 涟发队列与单发出膛 | `scripts/aircraft/aircraft_weapons.gd`（update_rocket / _launch_rocket） |
| 真实弹体与延迟散开 | `scripts/bullet_manager.gd`（spawn_rocket / rocket_spread_progress / _physics_process） |
| 无头回归 | `scripts/tests/test_rocket_trajectory.gd`（--bench=rocket_trajectory） |
| Visual 样张 | `scripts/tests/rocket_trajectory_visual_qa_runner.gd` / `scenes/tests/rocket_trajectory_visual_qa.tscn` |
| reference 索引 | `docs/reference/script-index.md` / `docs/reference/code-index.md` 火箭弹条目 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-17 | 1 | 用户定调敌我通用的“两侧连续直飞，离机一段距离后再渐进散开”；细化为 180m 直飞 + 320m smoothstep 展开。 |
| 2026-08-17 | 2 | 正式实现敌我共享涟发、增量散布与追踪兼容；专项、相关回归、45 架压力样本和真实 Visual 样张通过，状态转 done。 |
| 2026-08-30 | 3 | 火箭在每枚实际出膛时全量继承发射机当帧前向速度；高速攻击跑缩短弹道飞行时间，射程与伤害不变。 |
