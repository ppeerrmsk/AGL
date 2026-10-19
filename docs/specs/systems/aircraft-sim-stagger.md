---
id: aircraft-sim-stagger
kind: system
status: draft
schema_version: 1
spec_version: 1
owner: user+claude
depends_on: [systems/runtime-performance-budget, events/the-crucible, systems/display-pacing]
reconstruction_complete: false
---

# 非玩家飞机错相降频（完整逻辑按 2–3 帧轮转）

> 没有和玩家直接交手的飞机，把完整的飞行、武器、状态更新按 2–3 个物理步轮流做一次，位置仍每步推进。
> 玩家看不出差别；同一战场在 60 帧下能多容纳约两成飞机。

## 1. 设计意图（Why）

- **体验目标**：东京 C2 这类多战线战场在 60 FPS 下容纳更多真实作战的飞机，不删单位、不停火、不冻结。
- **依据**：[2026-10-20 错相降频评估](../../handoffs/2026-10-20-sim-divisor-stagger.md)。C2 同批交错测量中，玩家以外的固定翼按完整
  路径分频后，物理步脚本每步 −17%（N=2）/ −25%（N=3）；"有物理步帧均值 ≤ 16.7 ms"的拐点约从 52 架升到 58 / 62 架，
  "平均 ≥ 60 FPS"约从 55 架升到 61 / 64 架。保真度对照里掉头轨迹 RMS 偏差 ≤ 18 m、持续转速偏差 ≤ 0.3%、脚本化破 S 的导弹命中结果
  0 次翻转，交战统计（规避次数、空射导弹数）与全频一致；代价是机炮补发成团（§3.2）。
- **Litmus 自检**：
  - #1 信息察觉：本规格的目标就是"玩家察觉不到"；当前操控机和与它直接交手的飞机永远全频（§2.1）。
  - #3 手感：玩家机的物理不受影响；其它飞机的指令响应最多晚 2 个物理步（33 ms）。
  - #6 AI 演戏：AI 决策节点（AIController）的分频不变；只降飞机自身物理与武器的更新频率。
  - #11 60 FPS：这是本规格的唯一收益指标，验收见 §5。
- **反模式规避**：
  - 不用"减少敌人 / 停火 / 冻结"换帧率（与 [runtime-performance-budget](runtime-performance-budget.md) 的不可降级合同一致）。
  - 不新增 `lod_level` / `visible` 写者（SEAM-016）；分频档位是独立字段。
  - 不复用现有 `dense_battle_sim_divisor` 的精简分支：它跳过规避计时、自动机炮扫描、CIWS、特殊机动、技能与节点重绘，
    并把雷达改为 16 相。C2 实测它让来袭规避次数少 55–75%、空射导弹少约 20%，等于暗中削弱了战斗。
- **不覆盖**：敌方屏外飞机仍走现有 LOD2（1/3 精简分支）与远距冻结；本规格不改它们。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 分档

每架飞机按下表自上而下取第一条命中的档位：

| 档 | N | 条件 |
|---|---:|---|
| 豁免 | 1 | 当前操控机 |
| 豁免 | 1 | BOSS / 王牌（AceTier）/ Sentinel 长机及原生护卫 / UAV 指挥机（与撤离机、LOD2 冻结共用同一豁免口径） |
| 豁免 | 1 | 旋翼机（阶段 4 前） |
| 豁免 | 1 | `formation_mode` 跟随机（阶段 0 前） |
| 豁免 | 1 | 主动特殊机动进行中（眼镜蛇、赫尔贝特、胆大妄为、签名位移技能） |
| 豁免 | 1 | 与当前操控机直接交手：本机 `combat_target` 是当前操控机，或本机是当前操控机的 `combat_target`，且两机距离 ≤ 4.0 km（退出 4.6 km） |
| 已有 LOD | — | `lod_level ≥ 2` 或已被远距冻结：沿用现有 LOD2 / 冻结，本规格不介入 |
| 屏内 | 2 | 屏内（与离屏 LOD 同一视口判定，余量 500 px；退出再加 200 px 滞回） |
| 屏外 | 3 | 其余（屏外的玩家僚机、第三方友军、未被 LOD2 管理的单位） |

### 2.2 参数

| 字段 | 值 | 说明 |
|---|---:|---|
| `stagger_onscreen_n` | 2 | 屏内分频 |
| `stagger_offscreen_n` | 3 | 屏外分频 |
| `stagger_engage_enter_km` | 4.0 | 直接交手豁免进入距离 |
| `stagger_engage_exit_km` | 4.6 | 退出距离（滞回 0.6 km） |
| `stagger_screen_hysteresis_px` | 200 | 屏内→屏外的额外余量 |
| `stagger_retier_interval_s` | 0.25 | 档位重算周期；豁免条件（换控、开始特殊机动、进入编队）同步立即生效 |
| `stagger_max_accum_steps` | 4 | 完整帧补偿步长上限（物理步数） |

### 2.3 相位

- 飞机进入某个 N>1 的档位时取全局计数器 `slot`（每次分配 +1），相位 = `slot % N`；同一 N 下各相位人数相差 ≤ 1。
- 换档时重新分配相位；从豁免回到分频档时立即做一次完整更新再开始轮转。

## 3. 行为与公式（How）

### 3.1 每物理步

- **跳帧**：只推进位置——固定翼 `位置 += 航向单位向量 × 速度 × 本步 dt`；被动炮艇照常；坠毁/销毁态照常逐步。
  不更新航向、坡度、速度、计时器、装备与状态效果。
- **完整帧**：跑完整 LOD0 路径（含规避计时、自动机炮扫描、CIWS、特殊机动、技能、战斗追踪、节点重绘请求），
  状态推进步长 = 自上次完整更新以来累计的物理时间（上限 `stagger_max_accum_steps` 步），**位置只推进本步 dt**
  （跳帧已推进过的部分不得再积分）。
- 节点重绘：完整帧请求一次（N=2 与现有 LOD0"每 2 步重绘"相同；N=3 为每 3 步）。
- 雷达锁定分片：保持常规 4 相，不因分频改变。
- AIController：分频、相位与决策不变。

### 3.2 机炮同帧补发

完整帧里机炮按累加器一次补发多发时（N=3 下 60–90% 的弹丸成对/三发同帧同点生成），第 k 发按"本应出膛的时刻"
回推：出膛点沿弹道前移 `muzzle_velocity × age_k`，寿命扣掉 `age_k`，其中 `age_k` 为该发应出膛时刻到本步的时间差。
发数守恒；N=2 时 ≥ 1800 发/分机炮少打 7–14% 的量化损失一并修正（补发不得被梭间 CD 的绝对赋值吞掉）。

### 3.3 与现有 dense 分频的关系

The Crucible（N=4）与撤离机（N≥3）迁移到本机制的同一个门。The Crucible 若仍需要 16 相雷达，由它自己显式声明，
不再由分频字段隐式带出。

## 4. 结构与组成（Structure）

- **档位 owner**：生存模式的工作量快照（[runtime-performance-budget](runtime-performance-budget.md) §2.2）每
  `stagger_retier_interval_s` 写一次 `Aircraft` 上的分频字段（N 与相位）；其它系统只读。
- **门控**：`Aircraft` 物理入口统一门控，给下游两个量：状态 dt（累计）与位移 dt（本步）。编队、旋翼机、LOD 分支里
  自带的 `_lod_frame % k` 节流改读同一相位，不再各取余数（SEAM-055）。
- **AI 透明**：机动性 buff 仍只经 `effective_*()` accessor 注入；分频不改 accessor 语义。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 保真度（`sim_divisor_fidelity`）：S1 掉头轨迹 RMS ≤ 25 m；S2 持续转速偏差 ≤ 1%；S4 命中结果 0 次翻转；
      S5 编队位移比在 N=1/2/3/4 下均为 1.00 ± 0.01；S3 发数与全频相差 ≤ 3%，同帧同点成团 ≤ 10%。
- [ ] 临界规避：在 `flare_impact_ab` 的真实 `MissileEvasion → ControlIntent → AircraftPhysics → Missile` 链上补分频对照，
      按低/中/高/王牌 × 3000/800/300 m 统计生存率，N=2/3 与全频相差 ≤ 3 个百分点（现有 S4 的脚本化破 S 从不脱靶，测不出这一项）。
- [ ] C2 分档 48 / 72 / 96 / 120 演员（另加 84 / 108）与全频交错各 ≥ 2 轮：拐点"有步帧均值 ≤ 16.7 ms"不低于全频 +8 架；
      规避次数与空射导弹数与全频相差 ≤ 15%。
- [ ] 回归：turn_physics、bfm_intent、rejoin、gun_burst、gun_evasion、missile_env、flare、escort、cmd_evade、the_crucible、
      offscreen_world、gun_evasion_flight、desert_theater 与基线结果一致；`all` 失败集合不变。
- [ ] 性能：生存模式 Sentinel + Lv5+ 压力测试（Shadow Visual）FPS 不低于基线；记录 avg / p1 / worst / <60。
- [ ] Visual：屏内 N=2 飞机无可见卡顿或航向跳变；状态栏刷新 ≥ 20 Hz；机炮曳光不成团。
- [ ] 已知 seam：SEAM-016（不新增 LOD 写者）、SEAM-055（补偿步长叠加）已处理。
- [ ] 文档：本 spec 已登记 _INDEX；script-index / code-index 同步。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 读码：现有 dense 门、LOD2 分支、编队、旋翼机、雷达分片 | 见评估报告 §3 |
| E1 聚焦 Shadow | `bench\run.cmd sim_divisor_fidelity 1 900 Shadow Headless`（诊断门） | 运动学与脚本化破 S 无差异；编队位移重复积分、机炮成团；临界规避未测，见报告 §6 |
| E2 集成 / 压力 Shadow | C2 × 6 档 × d1/N2/N3（诊断门，Shadow Visual，VSync 关） | 见报告 §5；正式实现后需重测 |
| E3 Visual | — | 未做 |
| E4 完整局 | — | 未做 |

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 修现有错相缺陷（The Crucible 正在用）
- [ ] 门控给出"状态 dt / 位移 dt"两个量；编队 `_update_position` 只用位移 dt
- [ ] 编队速度/高度节流与编队机会武器改读分频相位，去掉 `_lod_frame % 3` / `% N` 二次门控
- [ ] 补偿步长改为累计时间，换档不丢不重
- [ ] S5 在 N=1/2/3/4 下位移比 1.00；the_crucible、desert_theater 断言不变

### 阶段 1 — 完整路径分频
- [ ] 分频飞机命中相位后走完整 LOD0 路径；雷达分片与分频解耦（Crucible 显式保留 16 相）
- [ ] The Crucible / 撤离机迁移到同一字段

### 阶段 2 — 分档 owner
- [ ] 工作量快照按 §2.1 / §2.2 写档位与相位；滞回与立即豁免
- [ ] F3/诊断面板显示各档架数

### 阶段 3 — 机炮补发回推（§3.2）

### 阶段 4 — 旋翼机
- [ ] 跳帧按 `rotorcraft_velocity` 推进位置，完整帧速度积分只推进状态；移出豁免表

### 阶段 5 — 验收（§5 全部）

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 现有错相门（诊断用） | `scripts/aircraft.gd` `_physics_process_impl` |
| 雷达分片 | `scripts/survivor/survivor_mode.gd` `_run_radar_slice` |
| 编队跟随位移 | `scripts/aircraft/aircraft_formation.gd` `update_follow` / `_update_position` |
| 诊断开关 | `scripts/tests/tokyo_volume_combat_runner.gd` `_configure_sim_divisor` |
| 保真度对照 | `scripts/tests/test_sim_divisor_fidelity.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-10-20 | 1 | 初稿：依据 2026-10-20 错相降频评估提出分档、参数与前置修复；待用户确认 |
