---
id: offscreen-world-simulation
kind: system
status: done
schema_version: 1
spec_version: 2
owner: 用户 + Codex
depends_on: [survivor-loop, zone-atmosphere-combat, tier-3-zone-global-threats, 60km-density-pass]
reconstruction_complete: true
---

# 未关注战区的最简世界模拟

> 玩家没有选择、没有进入、也不受其影响的普通战区只存在于战略层；真实战斗从玩家关心它的那一刻开始。

## 1. 设计意图（Why）

- **体验目标**：玩家关注的战线保持完整、热闹和可信；地图其它位置不靠不可见的实体与弹道消耗帧预算。
- **玩家权威**：普通战区的真实世界由玩家选择或进入激活。未激活状态不推进飞行、AI、雷达、武器、伤害、击杀、奖励或任务结果。
- **Litmus 自检**：继承设计哲学 7 的“关注战线热闹”和 11 的 60 FPS 红线；不减少玩家实际看见、锁定或正在承受的单位。
- **反模式规避**：不伪造画外胜负，不按隐藏计时器扣血，不用低伤害弹丸假装低成本，也不允许通过取消选择暂停已经启动的战斗。

## 2. 数据定义（What）

### 2.1 战区模拟状态

| 状态 | 实体 | 运算 | 进入条件 | 退出条件 |
|---|---|---|---|---|
| `LATENT` | 0 个正式战斗实体 | 仅保留 `zone_id`、任务类型、星级、奖励、战略位置及生成所需数据 | 普通 1★/2★战区公开为 `AVAILABLE`，但玩家未选择且未进入 | 玩家选择战区，或玩家进入战区半径 |
| `LIVE` | 按该战区既有规格一次性生成 | 完整飞行、AI、雷达、武器、伤害、气氛层与任务判定 | `LATENT` 满足任一激活条件；3★战区公开时直接进入 | 完成、失败、取消、BOSS 转场或既有 reset/清理终态 |

### 2.2 激活与例外

| 条件 | 是否激活 | 原因 |
|---|---:|---|
| 普通 `AVAILABLE`，玩家在战区半径外 | 否 | 战术地图只展示战略信息，不需要真实节点 |
| 普通 `SELECTED` | 是 | 选择是明确关注与出发命令 |
| 普通 `AVAILABLE`，玩家进入战区半径 | 是 | 支持不经 Tab 直接闯入 |
| 已经生成/触发的战区后来失去选择 | 保持 `LIVE` | 防止通过切换选择暂停威胁、重抽编成或回卷 HP/弹药 |
| 3★正式战区 | 是 | 全局威胁有稳定身份、预警和真实来源，已直接影响玩家 |
| BOSS、Sentinel、事件单位、旅途增援 | 不由本状态机管理 | 它们有独立的玩家相关性与生命周期 |

激活判定只使用战区状态、难度、玩家到战区圆心的距离与战区半径，不扫描全场单位。普通战区从
`LATENT` 到 `LIVE` 只允许一次；同一生命周期内不回到 `LATENT`。

### 2.3 玩家预测轨迹 P0 预算

| 项 | 值 |
|---|---:|
| 物理预测窗口 | 360 步 × 1/60 s = 6 s |
| 单渲染帧推进上限 | 24 步 |
| 完整缓存最短刷新间隔 | 200 ms |
| 绘制抽样步长 | 每 4 个物理点取 1 个，且始终保留终点 |
| 正常日志 | 不输出 `PRED_DIAG`；仅显式给玩家机设置诊断标记时输出 |

### 2.4 攻克后的敌机撤离

战区完成判定成立后，未列入任务目标、仍然存活的驻守敌机不再留在战区继续巡逻：

| 项 | 合同 |
|---|---|
| 撤离触发 | `mission_completed` 权威边沿成立的同一物理 tick |
| 可见表现 | 清除任务/交战目标，脱离编队，开加力沿最近地图边界物理撤出；玩家画面内绝不瞬移或瞬消 |
| 运算 | 撤离指令直接接管导航并关闭重新选敌/BFM；保留真实飞行、碰撞、受击与坠毁 |
| 离屏宽限 | 连续离开玩家视野 `2.0 s` 后静默释放；期间重新进入视野即把计时清零 |
| 检查频率 | `5 Hz`（每 `0.2 s`），只遍历 `ZoneMission` 自己持有的待撤离数组 |
| 释放预算 | 每次检查最多释放 `4` 架，防止整支编队同帧析构形成终态 spike |
| 奖励 | 静默释放不算击杀，不给 XP、技能触发或生涯记录 |

此合同只由“战区已攻克”触发，不以隐形/显形判定行为，也不改变任务失败、Debug 清理、等级刷新或
BOSS 转场各自既有的终态语义。Sentinel 若属于该战区驻守编成，同样随战区所有权终止而撤离；它的
常规战斗降级豁免不构成任务结束后的永久驻留权。

预测构建由生存模式的单一渲染更新入口推进；飞机 `_draw` 只消费已完成缓存并绘制，不再推进物理预测。
构建完成后原子替换缓存，构建期间保留上一条线。抽样只影响显示点数，不改变 360 步物理解算。

## 3. 行为与公式（How）

### 3.1 普通战区按需实例化

```text
for each zone whose state is AVAILABLE or SELECTED:
    if zone already has spawned roster:
        keep LIVE and continue existing lifecycle
    wants_live = (difficulty >= 3)
              or (state == SELECTED)
              or (distance(player, zone_center) <= zone_radius)
    if not wants_live:
        clear pending spawn announcement timer
        keep LATENT; create no unit and no atmosphere controller entry
        continue
    run existing radio lead, visible-spawn safety and spawn pipeline once
```

可见性安全门保持原语义：若生成范围与当前镜头重叠，优先延后；玩家已经进入或到达选中战区边缘时，
沿既有死锁恢复路径放行。空中单位仍从地图边缘入场，地面/海上单位仍服从安全陆地/全水硬闸。

### 3.2 任务与战略层边界

- `LATENT` 不产生任务目标节点，因此进度为 `0/0`；Tab 仍可从 ZoneData 显示任务类型、星级与奖励。
- `LATENT` 不播放生成广播，不登记气氛战斗，不产生 AI 对 AI 结果，也不给 XP、击杀或生涯进度。
- `LIVE` 完全复用既有任务完成、失败、取消、撤离与 reset 权威；本系统不建立第二套结算。
- 战区完成后，幸存驻守敌机进入 §2.4 的可见撤离；撤离是已完成任务的清理子状态，不会回卷任务结果。
- 3★继续遵守“公开即投射”的专属规格；它不是画外气氛，而是玩家当前必须管理的全局威胁。

### 3.3 预测线更新

```text
process frame:
    if controlled aircraft has a move target and is not in combat:
        begin build when cache missing or completed-cache age >= 200ms
        advance at most 24 of 360 steps
        on completion: decimate display points by stride 4; preserve final point; atomically publish

aircraft draw:
    transform, smooth, color and draw only the published display points
```

## 4. 结构与组成（Structure）

- `ZoneMission` 是 `LATENT → LIVE` 的唯一战区激活权威，并继续拥有生成与终态清理。
- `ZoneData` 保存不需要实体的战略信息；不新增全局 AutoLoad 或第二份战区状态表。
- `SurvivorMode` 每渲染帧只推进当前操控机一份预测工作。
- `AircraftRenderer` 分离“推进预测缓存”和“绘制已发布缓存”；不新增 Aircraft 子节点或每实体 `_process`。

## 5. 验收标准（Acceptance / Litmus）

- [x] 远离玩家的普通 `AVAILABLE` 战区保持 `LATENT`，不创建 TGT、驻守机、气氛演员或弹丸。
- [x] 选择普通战区或直接进入其半径会走既有安全生成链；生成后取消选择不会暂停或重抽该批内容。
- [x] 3★战区继续公开即生成并投射；BOSS、事件与旅途增援生命周期不变。
- [x] `LATENT` 不产生击杀、XP、任务完成/失败、无线电生成广播或生涯记录。
- [x] 360 步预测结果与旧物理解算逐点一致；显示缓存不超过 91 点并保留物理终点。
- [x] `_draw` 不调用预测推进函数；正常战斗日志不再按缓存刷新输出 `PRED_DIAG`。
- [x] 性能：C1 36 名/8km 与 C2 48 名/24km `Shadow Visual` 均满足 `<60=0`、p1/worst ≥60；另用 100+ 潜在战区编成验证未激活成员不进入真实单位表。
- [x] 已知 seam：战区可见生成、3★全局威胁、轰炸护送选择触发、reset/cancel/BOSS 清理与切控预测引用未破坏。
- [x] 攻克后幸存驻守敌机物理撤出；可见时不消失，离屏计时可被重新看见清零，持续离屏 2 秒后按每 tick 4 架预算释放。
- [x] 静默释放不触发击杀/XP；`queue_free()` 后越过下一 SceneTree 帧与后续缓存 tick 无残留引用。
- [x] i18n：无新增玩家可见文本。
- [x] 文档：本 spec 已登记 `_INDEX`；相关旧“画外持续战斗”表述已同步；reference 索引与文档检查通过。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 激活门、`_draw` 调用链、退役队列、索引与文档审计 | 普通远距 AVAILABLE 无实例化路径；预测推进只在 SurvivorMode 单一入口；攻克退役仅增加事件级入队与 5 Hz 临时队列扫描，并以每 tick 4 架限制摊平释放 |
| E1 聚焦 Shadow | `offscreen_world` 6/6；`predicted_path` 5/5；`zone_air_support` 73/73；`bomber_rotor_airburst` 135/135 | 激活矩阵、120 潜在成员、单向 LIVE、可见生成、攻克撤离、重新入镜重置宽限、护送广播与预测等价通过 |
| E2 集成 / 压力 Shadow | `all 1 300 Shadow Headless` | 83 项同步测试 0 失败；LifecycleGauntlet 69/69，覆盖真实攻克信号、`queue_free()` 下一帧及下一缓存 tick |
| E3 Visual | C1 `...132500/132910/132952.txt`；C2 `...132548/133210/133254.txt` | 三轮中位数：C1 119.86 avg / 115.21 p1 / 68.52 worst / `<60=0`；C2 119.78 / 110.00 / 79.23 / `<60=0`。六轮正常日志 `PRED_DIAG=0` |
| E4 完整局 | `combat_log_20260823_220033.txt` 为修复前基线 | 135 单位 / 101 飞机时约 18 FPS；待同条件复验 |

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 战区最简模拟
- [x] 在普通战区生成入口加入纯 O(1) 相关性门，保留 3★例外与既有可见生成安全。
- [x] 增加激活矩阵与未激活零实体回归。

### 阶段 2 — 玩家预测线 P0
- [x] 把预测推进移出 `_draw`，限制单帧工作与刷新率，并发布抽样显示缓存。
- [x] 更新逐点等价、完成时机、终点保留与正常日志回归。

### 阶段 3 — 性能与收口
- [x] 跑 focused、全量 Headless、C1/C2 Visual 与 100+ 潜在编成专项。
- [x] 同步受影响 spec、reference 索引和验证证据。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 战区激活与生成 | `scripts/survivor/zone_mission.gd` |
| 战略状态 | `scripts/survivor/zone_data.gd` |
| 预测缓存与绘制 | `scripts/survivor/survivor_mode.gd` / `scripts/aircraft_renderer.gd` / `scripts/aircraft.gd` |
| 回归 | `scripts/tests/test_offscreen_world_simulation.gd` / `scripts/tests/test_predicted_path_incremental.gd` |
| reference 索引 | `docs/reference/script-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-23 | 1 | 用户确立“未关注处不发生真实事件”；定稿普通战区按需实例化、3★例外、单向激活与玩家预测线 P0 预算。 |
| 2026-08-24 | 2 | 用户确立攻克终态：幸存驻守敌机真实撤离，连续离屏 2 秒后按 5Hz/每 tick 4 架的预算静默释放；隐形状态不参与行为判定。 |
