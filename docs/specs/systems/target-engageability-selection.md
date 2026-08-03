---
id: target-engageability-selection
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 5
owner: ppeerrmsk
depends_on: [squad-ai-escort]
reconstruction_complete: false
---

# 目标选择：可命中性评分（Engageability Selection）

> AI 选谁打，看的是"哪架我现在能干净地打掉"，而不是"哪架离我近"。近但打不中 = 浪费弹 + 不自然；该被跳过。

## 1. 设计意图（Why）

### 起因（观测到的 bug）
长机放着一架近处、已锁定的轰炸机不打，反而慢慢转向去够一架**稍远**的。复盘日志 + 代码定位到两条独立缺陷：

1. **锁定进度无上限**：生存模式主雷达累积 `radar_targets[tgt] = prev + delta*rate`，**不封顶**（副雷达却用 `minf(..., lock_time)` 封了）。于是"盯得越久值越大"，一架先被照射的远目标能累到 lock_time 的 5~10 倍。
2. **评分被锁定时间主导**：`score = (lock_progress/lock_time)*2 + dist_score`，其中 `dist_score = 1000/dist_px` 顶多 0.5~0.7。无上限的 lock_score 涨到 6、10，把距离项彻底淹没。结果"先照到的远目标"碾压"近的、已对正的目标"，且切换门槛又拦着不让换回来。

### 体验目标
- AI **优先打"现在就能命中"的目标**：在机头正前方、进了导弹包络、已锁定、且队友还没打死的那架。
- 近但大偏轴（要大转弯才追得上）→ **不优先**，避免"贴着却打不出 / 盲发浪费弹"。
- 队友已经有足够承诺火力飞向某目标时，导弹优先 AI → **让开**，火力转移到下一个，避免导弹超杀浪费；机炮优先 AI 继续咬住，直到目标确认摧毁。
- 距离只当"打平时谁先死得快"的次要 tiebreaker，绝不主导。

### Litmus 自检（引 DESIGN_PHILOSOPHY）
- **不浪费、不空耗**：不对着打不中的目标盲射 / 干追，每发弹都指向"能收掉"的目标。
- **物理优雅 / 自然**：选择结果与玩家肉眼直觉一致（"它当然该先打那架对着它的"），不出现"放着煮熟的鸭子去够远处的"反直觉走位。
- **AI 原型内部化**：评分因子是通用几何量，不暴露 archetype 词汇。

### 反模式规避
- 不引入"模式 if"（沙盒/生存共用同一评分；数值差异走 params）。
- 不在评分里散点读 `params.*`——飞行性能量走 effective_*/Situation 既有约定。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 候选硬门（不满足直接跳过该候选）

| 门 | 条件 | 说明 |
|---|---|---|
| 有效性 | `is_instance_valid` 且 `not is_destroyed` 且 `team != 我方` | 既有 |
| 最低锁定比 | `lock01 >= min_lock_ratio` | `min_lock_ratio = lerp(1.0, 0.3, ai_aggression)`，既有；高攻击性放宽到 30% 即可参选 |

> 注：硬门只用来**剔除完全不该考虑的**；"已被队友超杀"不做硬门，而是强惩罚倍率（见 §2.3），保证万一全场只剩它时仍能作为兜底目标。

### 2.2 可命中性评分因子（每个归一化到 [0,1]）

| 因子 | 符号 | 公式 | 含义 | 权重 |
|---|---|---|---|---|
| 对正度 | `align01` | `clamp(1 - off_axis_deg / radar_half_angle_deg, 0, 1)` | 目标离我机头多少度；1=正对，0=雷达锥边缘 | **0.45** |
| 包络 | `env01` | 见 §3.2 | 是否在导弹 min~max 射程内；超出/太近线性衰减 | **0.30** |
| 锁定 | `lock01` | `clamp(lock_progress / lock_time, 0, 1)` | 已锁=1（**封顶**，杜绝 runaway）；半锁线性 | **0.15** |
| 邻近 | `prox01` | `clamp(1 - dist_m / missile_max_range_m, 0, 1)` | 近一点 TTK 短，仅做 tiebreaker | **0.10** |

- 权重和 = 1.0 → **基础分 `base ∈ [0,1]`**。
- `off_axis_deg`：我机头 heading 与"指向目标方向"的夹角绝对值（度）。与发射门 [`_has_stable_launch_window`] 用的同一个量——选择与发射对齐。
- `radar_half_angle_deg`：来自 `params.radar_half_angle`（F-14 = 30°）。

### 2.3 修饰倍率 / 加分（作用于 base 之后，顺序固定）

| 修饰 | 公式 | 说明 |
|---|---|---|
| 视觉遮蔽 | `*= _visibility_score_mult(tgt)` | 既有：低空 0.80 / 云中 0.65，取较强抑制 |
| 队友超杀 | `*= overkill_mult` | **仅非机炮优先 AI**：`team_inbound_damage(tgt, team, exclude=self) >= tgt.hp` 时 `overkill_mult = 0.10`，否则 `1.0`；机炮优先恒为 `1.0` |
| 偏好高度 | `*= 1.3` | 既有：`tgt_tier == preferred_altitude_tier` |
| 护卫加权 | `+= escort_target_bonus(leader, tgt)` | 既有：护卫僚机咬"咬长机者"，绝对加分（叠在 base[0,1] 同尺度上，需复核量级，见 §6 阶段3） |
| **守后优先** | `+= REAR_GUARD_PRIORITY * rear_threat_score` | **仅守后语境**（见 §2.4）：长机后半球且准备攻击长机的敌机大幅提权，主导本次选择。`REAR_GUARD_PRIORITY = 100.0`（与 escort 同加性尺度，远大于 base[0,1]） |
| 目标粘性 | `+= STICKY_BONUS` | 当前目标加 `STICKY_BONUS = 0.10`（替代旧 `focus*5`，适配新 [0,1] 尺度） |

**超杀即时让路**：武器层命中 `TEAM_OVERKILL` 时，仅对非机炮优先、`TS_SCORED` 自动目标催促下一 AI tick 重评（每机 1s 冷却）；本次重评不给已超杀当前目标叠粘性，也不套切换迟滞。机炮优先 AI 不响应此请求，继续保留目标粘性与正常切换迟滞。玩家显式 `commanded_target` / FOCUS 是铁律，绝不触发自动让路。

**武器语义边界**：超杀是导弹/电磁炮等“发射后不可撤回的承诺火力”的弹药纪律，不是目标状态。机炮是持续、可中断且命中不确定的火力；机炮优先 AI 不因队友在途导弹而把目标视为“已死”，但导弹执行层仍禁止它向已有致死承诺伤害的目标重复补射。

#### 2.4 守后优先（守护后方战术专属加权）

**两个作用点**（同源、互补）：

1. **`scan_leader_rear`（主）**：守后行为本身（GUARD_REAR / 自由机互掩）走 `_guard_rear_tick → scan_leader_rear` 直接选定后方威胁，**不经 try_engage 评分**。已从"选最近"改为"按 `rear_threat_score` 选最高威胁"——即正在/准备攻击长机者优先于仅仅最近者。这是用户反馈的主修点。
2. **选择评分（辅）**：守后语境下，`try_engage` / `reevaluate_target` 给候选叠加 `REAR_GUARD_PRIORITY * rear_threat_score`，让已经在交战的守护者重评估时也会切向更高威胁的后方敌机。

**语境门**：`_is_guard_rear_context(ai)` = `squad_engage_mode == GUARD_REAR`。（自由机互掩守后是逐帧瞬态，由 scan_leader_rear 直接接管，不依赖评分路径。）非守后语境守后项 = 0，退回 §2.2 通用评分。

**`rear_threat_score(leader, candidate) → [0,1]`**（体现"已经/正准备攻击长机 > 只是接近 > 闲晃"）：

| 情形（须在长机后半球 `angle(leader_fwd, leader→cand) > 90°` 且 `dist <= REAR_GUARD_RANGE`） | threat | 最终值 = `threat × (0.7 + 0.3 × prox)` |
|---|---|---|
| 已咬长机（`leader.engaging_me.has(cand.id)`） | 1.0 | **0.7 ~ 1.0** |
| 朝长机逼近（`enemy_fwd · (leader-enemy)dir > 0.3`，机头指向长机=准备攻击） | 0.6 | **0.42 ~ 0.6** |
| 在后半球但既不咬也不逼近（远处闲晃） | 0 | **0.0**（不提权，守护者不去追闲敌） |
| 不在后半球 / 超 REAR_GUARD_RANGE / dist<1 | 0 | **0.0** |

- `prox = 1 - clamp(dist / REAR_GUARD_RANGE, 0, 1)`：档内贴长机近者优先（tiebreak），但**任一"已咬"必压过任一"逼近"**（0.7 底 > 0.6 顶）。
- `REAR_GUARD_RANGE` 用 AIController 既有常量（当前 900px ≈ 1800m），与 scan_leader_rear 同源，未来调一处即可。

> **与 `escort_target_bonus` 的关系**：escort_bonus 是通用护卫（咬长机 +60 / 贴长机近 0~25，对所有护卫僚机生效）；守后优先是**守后语境专属、且要求后半球**的更强提权（+100 × threat），专门把"正从背后逼近、尚未咬住"的威胁也提前拦下。两者加性叠加，语义互补。

### 2.5 切换迟滞（防抖）

| 场景 | 阈值 | 说明 |
|---|---|---|
| try_engage 进入交战换目标 | `SWITCH_MARGIN_ENTER = 0.12` | 新目标须 `best > current + 0.12` 才换 |
| reevaluate_target 交战中换目标 | `SWITCH_MARGIN_REEVAL = 0.18` | 交战中更黏，避免来回横跳 |

> 这两个替代旧的 `focus*2 / focus*3`（旧值在新 [0,1] 尺度下会大到永不换 / 小到乱换）。具体数值待 §5 playtest 调。

## 3. 行为与公式（How）

### 3.1 单个候选打分（伪代码）

```
for tgt in radar_targets:
    if not valid(tgt) or tgt.destroyed or tgt.team == me.team: continue
    lock01 = clamp(lock_progress(tgt) / lock_time, 0, 1)
    if lock01 < lerp(1.0, 0.3, ai_aggression): continue          # 最低锁定门

    off_axis_deg = abs(angle_diff(heading_to(tgt), my_heading))
    align01 = clamp(1 - off_axis_deg / radar_half_angle_deg, 0, 1)
    env01   = envelope_factor(dist_m)                            # §3.2
    prox01  = clamp(1 - dist_m / missile_max_range_m, 0, 1)

    base = 0.45*align01 + 0.30*env01 + 0.15*lock01 + 0.10*prox01

    base *= visibility_mult(tgt)
    if not gun_priority and team_inbound_damage(tgt, team, exclude=me) >= tgt.hp:
        base *= 0.10                                             # 超杀让路
    if tgt_tier == preferred_altitude_tier: base *= 1.3
    if escort_leader: base += escort_target_bonus(escort_leader, tgt)

    if guard_rear_context(ai):                                  # §2.4 守后专属
        base += REAR_GUARD_PRIORITY * rear_threat_score(leader, tgt) # 后方威胁主导

    if tgt == current_target: base += STICKY_BONUS              # 粘性 0.10

    track best
```

权重/常量实测值：`W_ALIGN=0.45 W_ENV=0.30 W_LOCK=0.15 W_PROX=0.10`、`OVERKILL_MULT=0.10`、
`PREFERRED_ALT_MULT=1.3`、`STICKY_BONUS=0.10`、`REAR_GUARD_PRIORITY=100.0`、
`SWITCH_MARGIN_ENTER=0.12`、`SWITCH_MARGIN_REEVAL=0.18`。`prox01` 用 `missile.max_range_rear`（无导弹时 8000m 兜底）。

### 3.2 包络因子 `env01`

实现复用飞机既有 `_is_in_missile_envelope(tgt, msl)`（含 TAA 纵横角 + 高度射程加成的 aspect-correct 判定），
而非手算 max_range，避免与发射端两套包络：

| 情形 | env01 |
|---|---|
| 在导弹包络内（`_is_in_missile_envelope` 为真） | `1.0` |
| 太近（`dist < msl.min_range`，要拉开） | `0.3` |
| 超出包络 | `0.15`（不为 0：仍可作兜底，飞近再打） |
| 无导弹（纯机炮机，msl=null） | `1.0`（不按导弹包络罚分） |

> 注：生存（flat）/ 高空模式下包络的有效 max_range 很大（min 500m ~ 2 万 m+），常见交战距离基本恒为 1.0；
> env01 主要在"太近要 extend"与"完全超界"两端起区分作用。

### 3.3 守后优先判定（`rear_threat_score`）

```
func rear_threat_score(leader, cand) -> float:   # 返回 [0,1]
    to_cand = cand.pos - leader.pos
    dist = to_cand.length()
    if dist > REAR_GUARD_RANGE or dist < 1: return 0.0
    leader_fwd = fwd_from(leader.heading)
    if abs(angle(leader_fwd, to_cand.normalized())) <= 90°: return 0.0   # 不在后半球
    threat = 0.0
    if leader.engaging_me.has(cand.id): threat = 1.0                     # 已咬长机
    else if fwd_from(cand.heading) · (-to_cand).normalized() > 0.3: threat = 0.6  # 朝长机逼近
    if threat <= 0: return 0.0                                           # 后方闲晃，不提权
    prox = 1 - clamp(dist / REAR_GUARD_RANGE, 0, 1)
    return threat * (0.7 + 0.3 * prox)           # 已咬 0.7~1.0 > 逼近 0.42~0.6
```

`guard_rear_context(ai)` = `ai.squad_engage_mode == GUARD_REAR`（自由机互掩守后由 scan_leader_rear 直接接管，不走此评分路径）。

### 3.4 与既有路径的关系
- 本 spec 改 **目标选择层**（`TargetSelection.try_engage` / `reevaluate_target`）+ **守后选定**（`scan_leader_rear` 改按 `rear_threat_score` 排序）。一旦选定 `_current_target`，后续 BFM intent / 发射判定不变。
- `align01` 用的 off-axis 与发射门同源 → 选择天然偏好"已在发射窗里的目标"，**间接缓解**"锁了打不出"，但发射端的 crank≈发射门 重叠（crank=radar_half×0.5≈15° vs 门 16.5°）是**独立问题**，不在本 spec 范围（见 §5 备注 / 另起 spec）。

## 4. 结构与组成（Structure）

- **评分入口**：`TargetSelection.try_engage`（进交战）、`TargetSelection.reevaluate_target`（交战中重评）——两处共用 `TargetSelection._score_candidate(ai, tgt, escort_leader, guard_ctx)`（去重，杜绝两份公式漂移）。
- **守后选定**：`SquadCoordination.scan_leader_rear` 改按 `rear_threat_score` 选最高威胁（替代旧"选最近"）；`rear_threat_score` 为 scan 与评分两处同源。
- **锁定值来源**：`aircraft.radar_targets[tgt]`（秒）。**前置修复**：生存模式主雷达累积处封顶 `minf(..., lock_time + LOCK_STABLE_BUFFER)`——封顶根除 runaway，但留 `LOCK_STABLE_BUFFER`(0.3s) 余量，避免饿死"哑 AI"发射（其阈值 = lock_time + buffer）。选择评分内另有 `lock01 = clamp(progress/lock_time, 0, 1)` 双保险。
- **超杀查询**：`missile_manager.team_inbound_damage(tgt, team, exclude=self)`（武器层 `_fire_multi_lock_salvo` 已在用，选择层复用；missile_manager 为空时跳过）。
- **常量**：`W_ALIGN/W_ENV/W_LOCK/W_PROX / OVERKILL_MULT / PREFERRED_ALT_MULT / STICKY_BONUS / REAR_GUARD_PRIORITY / SWITCH_MARGIN_*` 集中放 `TargetSelection` 顶部常量区，便于调参。

## 5. 验收标准（Acceptance / Litmus）

> 自动化覆盖：`scripts/tests/test_target_selection.gd`（`godot --headless --path . -- --bench=target_sel`）—— 7/7 通过。

- [x] **场景A 近偏轴 vs 远正对**：近(2000m)25°偏轴 vs 远(3000m)正对，均满锁 → 选远正对。`s_far=0.980 > s_near=0.612` ✓（单测）
- [x] **场景B 队友超杀**：同目标，队友 80dmg 制导弹在途（hp=60）→ 分骤降。`0.987 → 0.099 (×0.10)` ✓（单测）
- [x] **场景B2 机炮优先免疫目标超杀**：相同在途伤害下，机炮优先 AI 评分不降、即时换目标请求不生效；导弹补射门保持不变。
- [x] **场景C 全等 → 比距离**：均正对/锁定/包络内，仅距离差 → 选近。`s_near=0.990 > s_far=0.977` ✓（单测）
- [x] **场景D 守后优先**（`rear_threat_score`）：已咬 `0.800` > 逼近 `0.480` > 前方 `0.000` ✓（单测）
- [x] **runaway 根除**：lock_progress 3s vs 30s（同位同向）→ 同分。`0.987 == 0.987`（lock01 封顶）✓（单测）
- [ ] **回归 单目标 / 不横跳**：生存模式 playtest 观察（待）——只有一架敌机仍进交战；势均力敌不来回切（迟滞生效）。
- [ ] 性能：选择层仍每 `_target_eval` 周期跑一次（非每帧），新增 team_inbound 查询不抬帧耗；跑生存 Sentinel + Lv5+ 压测 FPS 掉幅 < 15（待 playtest）。
- [x] 已知 seam 未触碰（选择层不碰 SEAM-011/013 编队/转弯）。
- [x] i18n：本改动无新增玩家可见文本（评分内部量）。
- [x] 回归套件：weapon 7/0、flare 9/0、rejoin ✓、turn_physics 48/0 全平滑。

> **备注（范围外，另立）**：发射端 crank 角(radar_half×0.5≈15°) 与发射门(radar_half×0.55≈16.5°) 几乎相等导致"锁了打不出"，是与本 spec 并列的第二个修法方向，本 spec 不含；若 §5 playtest 仍见"选对了但打不出"，再起 firing-window spec。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 锁定 runaway 根除（前置）✅
- [x] 生存模式主雷达累积封顶 `minf(prev + delta*rate, lock_time + LOCK_STABLE_BUFFER)`（封顶 + 留发射余量）
- [x] 选择评分内 `lock01 = clamp(progress/lock_time, 0, 1)` 双保险（runaway 单测验证）

### 阶段 2 — 可命中性评分 ✅
- [x] 抽出 `TargetSelection._score_candidate(ai, tgt, escort_leader, guard_ctx)`，实现 §3.1 公式 + §3.2 env01（复用 `_is_in_missile_envelope`）
- [x] try_engage / reevaluate_target 改用 `_score_candidate`，删旧 `lock_score*2 + dist_score`
- [x] 顶部常量区加 四因子权重 / STICKY_BONUS / SWITCH_MARGIN_* / OVERKILL_MULT / REAR_GUARD_PRIORITY
- [x] 切换迟滞改用 SWITCH_MARGIN_ENTER / REEVAL（替换 focus*N）

### 阶段 3 — 修饰项接回 + 守后优先 ✅
- [x] visibility_mult / preferred_altitude / escort_bonus 接回
- [x] 量级决策：base 保持 [0,1]，escort_bonus(60/25) 与 REAR_GUARD_PRIORITY(100) 保持大尺度绝对加分——威胁目标主导、无威胁时 base 独立决定（无需缩放 escort_bonus，沿用旧尺度）
- [x] 超杀倍率接入（team_inbound_damage 查询，missile_manager 空守卫）
- [x] 机炮优先豁免目标超杀：不降权、不移除粘性、不响应武器层即时换目标请求；导弹执行层超杀门不变
- [x] **守后优先接入**：`rear_threat_score` + `_is_guard_rear_context`；`scan_leader_rear` 改按 `rear_threat_score` 选最高威胁（两处同源）

### 阶段 4 — 验收与调参
- [x] 写 `test_target_selection.gd` 覆盖场景 A/B/C/D + runaway，接入 bench_runner（`--bench=target_sel`）→ 7/7
- [x] 回归套件全绿（weapon/flare/rejoin/turn_physics）
- [ ] **playtest（待）**：生存模式实战观察换目标手感 + 守后拦截 + 调 SWITCH_MARGIN_* / 权重 / OVERKILL_MULT
- [ ] playtest 通过后：同步 reference 索引 + 验证"选对了能否打出"（决定是否另起 firing-window spec）→ status: done

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 评分主逻辑（`_score_candidate` / `_envelope_factor` / `_is_guard_rear_context` + 常量） | `scripts/ai/target_selection.gd` |
| 守后选定 + `rear_threat_score` | `scripts/ai/squad_coordination.gd`（`scan_leader_rear`）|
| 锁定累积封顶 | `scripts/survivor/survivor_mode.gd`（`_update_radar_locks` 主雷达累积处）|
| 超杀查询 | `scripts/missile_manager.gd`（`team_inbound_damage`）|
| 验收单测 | `scripts/tests/test_target_selection.gd` + `scripts/bench/bench_runner.gd`（`target_sel` 分支）|
| reference 索引行 | script-index.md `ai/target_selection.gd` / `ai/squad_coordination.gd` 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-06-14 | 1 | 初稿（draft）：起因诊断 + 可命中性四因子评分 + 超杀让路 + 锁定封顶前置 |
| 2026-06-14 | 2 | 加 §2.4 守后优先：守后语境下长机后半球且咬/逼近长机的敌机 +REAR_GUARD_PRIORITY 主导选择（已咬=1.0 / 逼近=0.6），与 scan_leader_rear 同源；补场景 D/D-边界 验收 + 阶段3 接入任务 |
| 2026-06-16 | 3 | **代码落地**（status→in-progress）：四因子评分 + 超杀 + 守后优先全实现并单测 7/7；scan_leader_rear 改按 rear_threat_score 排序；锁定封顶在 lock_time+LOCK_STABLE_BUFFER；实测常量 REAR_GUARD_PRIORITY=100/SWITCH 0.12/0.18；env01 复用 _is_in_missile_envelope；回归套件全绿。差生存 playtest 调参 → done |
| 2026-07-29 | 4 | combat log 230005 实证：自动僚机虽被 `TEAM_OVERKILL` 禁火，生存粘性仍让必死目标滞留 3~10s。新增仅限 `TS_SCORED` 的 1s 冷却即时重评；超杀当前目标在该次重评中不吃粘性/迟滞。commanded/FOCUS 铁律保持不变。 |
| 2026-08-03 | 5 | 用户定调“机炮不需要超杀”：超杀收窄为导弹/电磁炮的承诺火力纪律。机炮优先 AI 不因在途导弹降低目标评分、失去粘性或触发即时换目标，持续攻击至确认摧毁；导弹执行层仍禁止重复补射。 |
