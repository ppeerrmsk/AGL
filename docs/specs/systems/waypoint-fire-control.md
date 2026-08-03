---
id: waypoint-fire-control
kind: system
status: in-progress
schema_version: 1
spec_version: 1
owner: user+codex
depends_on: [rts-command, weapon-employment-doctrine, formation-discipline, engagement-discipline]
reconstruction_complete: true
---

# 航点移动机会火控

> 玩家持续点地板控制航线时，自己与编队僚机仍可在“不改变航线、且当前火控解足够可靠”的窗口自动发射导弹。

## 1. 设计意图（Why）

- **体验目标**：服务高频点地板玩家。移动命令只决定飞机去哪；武器在已经具备可靠发射解时自行抓住窗口，不要求玩家另点 `combat_target`。
- **命中优先于出手频率**：第一阶段只补通火控执行链，完全复用现有严格发射质量门；宁可暂时不发，也不允许明显打不中的浪费弹。
- **Litmus 自检**：符合“全武器自动开火”；玩家通过走位进入开火状态；发射仍需完整锁定、包络与稳定窗口，不把自动武器改成无脑 DPS。
- **反模式规避**：不把临时火控候选写入 `combat_target` / `commanded_target`，不让武器反向夺走玩家的航点导航；不对敌方无目标 AI 开放机会发射；不在第一阶段修改锁定、射程、坡度或离轴阈值。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 第一阶段固定值

| 字段 | 值 | 说明 |
|---|---:|---|
| 编队机会火控频率 | 20 Hz | 每 3 个 60 Hz 物理帧评估一次；计时器传入 `delta × 3`，保持冷却真实流速 |
| 玩家亲控机机会火控频率 | 60 Hz planner / 武器更新 | 保留现状，不降频、不增频 |
| 雷达锁定门 | planner/玩家：`lock_progress >= live lock_time` | 不增加锁定记忆；不保留半锁；不缩短锁定时间；旧式无 planner AI 继续沿用更严格的既有 `+1s` buffer |
| 当前雷达锥门 | 必须通过 | 发射当帧目标仍须在本机实时雷达锥内 |
| 导弹包络门 | 必须通过 live missile envelope | 最小/最大距离、高度与前后半球公式全部沿用现有导弹参数 |
| SARH 最大坡度 | 35° | 第一阶段不改 |
| SARH 最大滚转率 | 30°/s | 第一阶段不改 |
| SARH 最大离轴 | `radar_half_angle × 0.50` | 第一阶段不改 |
| 主动弹最大坡度 | 60° | 第一阶段不改 |
| 主动弹滚转率门 | 无 | 维持现状：发射后自主制导，不因发射机滚转拒发 |
| 主动弹最大离轴 | `radar_half_angle × 0.55` | 第一阶段不改 |
| 同目标自机在飞弹 | 0 枚 | 已有自机在飞弹则机会齐射不补射 |
| 团队超杀门 | `team_inbound_damage < target.hp` | 已承诺伤害足以击杀则不发 |

### 2.2 第一阶段适用对象

| 对象 | 航点机会火控 | 说明 |
|---|---|---|
| 当前亲控玩家机 | 保留现状并补测试 | 无 `combat_target` 时复用雷达锁定候选齐射，不改变导航 |
| 玩家小队编队僚机 | 新增 | 仅 `team=0 + formation_mode + missile_auto_fire`；不脱离编队 |
| 已脱离编队、正常交战的玩家僚机 | 现状 | 继续走 planner / `combat_target` 武器链 |
| 敌机或敌方编队僚机 | 禁止 | 维持 engagement-discipline 的“无攻击意图不开火” |
| 自动发射关闭的玩家单位 | 禁止 | 不得绕过玩家开关 |
| 规避/全队加力禁攻期 | 禁止 | 维持现有武器静默硬门 |

### 2.3 第二阶段边界（未批准、不得实现）

锁定记忆、坡度上限、滚转率上限、离轴比例、雷达锥、导弹包络等任何放宽均属于第二阶段。
第二阶段没有默认数值；必须先读取第一阶段 bench + 实战日志中的发射数、`UNSTABLE_WIN`、命中率与弹药浪费，再由用户确认并提升 `spec_version`。

## 3. 行为与公式（How）

### 3.1 火控与导航分离

```text
航点导航：target_position → 编队/物理继续执行（权威，不被武器修改）
火控候选：radar_targets → 逐个套严格发射门 → 本帧局部候选表
发射成功：直接把候选传给导弹管理器
发射结束：不写 combat_target / commanded_target / target_position
```

“fire-only target”是一次评估内的局部候选，不新增持久目标状态。亲控机与编队僚机共用既有多目标齐射过滤器，避免复制两套命中纪律。

### 3.2 候选过滤顺序

候选必须依次满足：

1. 实例有效、未摧毁、与发射机敌对。
2. 若存在玩家显式 `commanded_target`，候选必须就是命令目标；航点移动时通常无命令目标。
3. 雷达锁定进度达到本机 live `lock_time`。
4. 发射当帧仍在本机实时雷达锥内。
5. 通过导弹 live 包络。
6. 自机没有仍在飞向该目标的导弹。
7. 队友有效在飞伤害与充能必中伤害尚不足以击杀目标。
8. 通过 §2.1 的现有稳定发射窗。

任一条件失败：本帧不发、不扣弹、不改导航、不把失败候选升级为 `combat_target`。

### 3.3 编队僚机执行

- 编队物理仍是唯一运动所有者；机会火控只运行导弹冷却与发射执行。
- 每 3 帧调用一次，传入累计等价步长；不得为此退出 `formation_mode`。
- 调用期间可临时打开导弹执行模式，结束后恢复原 `weapon_mode`，避免污染后续战术状态。
- 多锁定时的发射数量、距离排序、超杀与在飞弹限制全部沿用既有齐射规则。
- 玩家方编队机会火控可继续推进/消费旧 `SquadCoordination.process_salvo` 的计时信号，但不得让它强制发射；该历史分支只查包络与雷达锥，必须跳过其开火动作，统一落入完整锁定 + 稳定窗 + 过杀过滤器。

## 4. 结构与组成（Structure）

- 玩家航点 planner：保留现有 `WAYPOINT_MOVE + PASSIVE_AUTO_FIRE` 通路，并纳入回归测试。
- 编队接线：三个 Aircraft LOD 的编队早返分支在 20 Hz 节点调用同一机会导弹 helper。
- 武器执行：扩展既有玩家被动齐射资格到“玩家小队且正在编队的僚机”；候选过滤器保持单一来源。
- 测试：独立 `waypoint_fire` bench，覆盖准发、拒发、导航不受影响和敌方隔离。

## 5. 验收标准（Acceptance / Litmus）

- [x] 玩家无 `combat_target`、正在飞航点、已有合法满锁目标时，导弹可自动发射，`target_position` 保持原值。
- [x] 玩家编队僚机在合法窗口自动发射后仍在编队，且 `combat_target == null`、`commanded_target == null`。
- [x] SARH 坡度 36°、滚转率 31°/s、离轴超过半锥 50% 任一成立时不发射、不扣弹。
- [x] 主动弹坡度 61°、离轴超过半锥 55% 任一成立时不发射、不扣弹。
- [x] 未满锁、出实时雷达锥、过近/过远、已有自机在飞弹、团队已超杀时均不发射。
- [x] 自动发射关闭、敌方编队、规避/加力禁攻期均不走机会火控。
- [x] 编队存在 `_salvo_pending` 且临时目标未满锁时，不得走旧协同齐射简化门发射；到期信号可消费，但弹药必须不变。
- [x] `--bench=waypoint_fire` 全绿；相关 `weapon`、`missile_env`、`fire_discipline`、`tight_volley` 全绿。
- [x] 自动性能：新增评估固定 20 Hz，只挂玩家编队；`stress_swarm` Lv15、10 架玩家方编队、20 敌机、14 地面单位与 CSG 的 10 秒样本保持 145 headless 帧/s，武器物理桶 38 μs/帧。
- [ ] 手动性能：有渲染的 Sentinel + Lv5+ 实战保持 60 FPS；headless bench 不替代这项肉眼验收。
- [x] 无新增 UI 文本，无 i18n 变更。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 导航/火控解耦（本轮，已批准）

- [x] 把玩家编队僚机接入既有严格被动齐射过滤器。
- [x] 三档编队早返路径以 20 Hz 调用机会火控，保持导航与编队状态不变。
- [x] 增加 `waypoint_fire` bench，锁死全部第一阶段门槛与负例。
- [x] 仅经 `bench/run.cmd` 完成最终行为回归；索引与本功能锚点已更新。

### 阶段 2 — 质量门调参（延期，未批准）

- [ ] 汇总第一阶段实战命中率、浪费弹、`UNSTABLE_WIN` 原因分布。
- [ ] 用户确认后才定义放宽数值、修改本 spec 并实现。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 编队机会火控接线 | `scripts/aircraft.gd` |
| 严格候选过滤与发射 | `scripts/aircraft/aircraft_weapons.gd` |
| 航点 planner | `scripts/ai/tactical/bfm_intent.gd` |
| 无头验收 | `scripts/tests/test_waypoint_fire_control.gd` |
| bench 注册 | `scripts/bench/bench_runner.gd` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-07-31 | 1 | 用户确认分两阶段；第一阶段只解耦导航/火控并测试，所有导弹质量门保持原值；第二阶段调参延期。 |
| 2026-07-31 | 1 | 阶段一代码与 bench 落地；协调要求停止 Godot editor/直接调用，最终启动器回归待其他 task idle 后补跑。此前在“旧协同齐射旁路”最终收紧前，waypoint_fire/weapon/fire_discipline/tight_volley/missile_env 均返回 0；该结果只证明主体接线，不作为最终补跑替代。 |
| 2026-08-01 | 1 | 仅经 `bench/run.cmd` 完成正式行为回归：`waypoint_fire` 27/27、`weapon` 7/7、`missile_env` 4/4、`fire_discipline` 10/10、`tight_volley` 10/10、`target_arb` 25/25、`friendly_asset_aggro` 27/27。 |
| 2026-08-01 | 1 | `stress_swarm` 10 秒压力样本通过：33 架飞机/80 单位，末秒 145 headless 帧、`ac_phys.wpn` 38 μs/帧；此前 30 秒样本触发启动器 120 秒超时并被完整回收，未生成结果，因此不计为通过。保留 Sentinel + Lv5+ 有渲染手动验收。 |
