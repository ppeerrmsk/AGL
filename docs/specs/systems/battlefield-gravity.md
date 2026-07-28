---
id: battlefield-gravity
kind: system
status: in-progress
schema_version: 1
spec_version: 2
owner: 设计对话 2026-07-24（noelu + Claude）
depends_on: [target-engageability-selection, squad-cohesion, squad-ai-escort, boss-hunter-doctrine]
reconstruction_complete: false
---

# 战场引力 —— 友军目标优先级分层

> 玩家视角：僚机不再各飞各的。它们先替你挡下追你的敌机，再一起压当前该打的目标（BOSS / 战区），绝不跑去 10 公里外单挑一架直升机。

## 1. 设计意图（Why）

### 病征（两份 playtest log 驱动）
- **问题①（log 20260724_222238）**：玩家被咬时，僚机宁可回编队也不去反咬追击者，放弃包抄。根因：守后被三重门锁死（只 1 架、须长机正在攻击、900px 内），且包抄的外绕会踩 leash 被拽回。
- **问题②（log 20260724_222827）**：BOSS 战期间僚机跑去打 6~17km 外的低慢直升机（CH-47 `alt=2000m spd=60m/s`），有的在躲弹逃离。根因：目标评分里**根本没有"离主战场多远"这一维**——一架对正+锁定的远处杂鱼评分和近处 BOSS 一样高；且 BOSS 频繁隐形（一局 14 次 emergency cloak）+ 蹲 9990m 高空，锁不上就退而求其次去打杂鱼。

两个病根其实是同一个：**小队 AI 缺一个统一的"以当前主战场为中心"的空间锚**。现有 leash 只锚"离长机欧氏距离"，太粗——顺着它就杀包抄（①），绕过它（命令 / 慢速 joust / 切控）就放羊（②）。

### North Star
> **玩家要先活命，其次才是当前该打的战术目标；顺手目标永远让位，且不许把人拽离战场。**

一句话规则（本 spec 的宪法）：**决定优先级的不是"这敌人是谁"，而是"它此刻在不在咬玩家 + 它离主战场多远"。**
- BOSS 正在打你 → 自动进生存层（最高）
- BOSS 只是登场没扑你 → 任务层
- 一架杂鱼咬住你、僚机在远处打 BOSS → 杂鱼**升进生存层**，僚机回防

### Litmus 自检（DESIGN_PHILOSOPHY）
- **单杠杆 / 复用既有数值**：不新建战术状态机，只在现有可命中性评分（target-engageability-selection）上叠 3 个加性/乘性项 + 一个已存在的定向扫描（scan_leader_rear 的泛化）。
- **效果即反馈**：玩家不需要读任何 HUD 中介，直接从"僚机往哪飞、打谁"看到优先级。
- **中队级粒度**：引力锚是队级共享量，不逐机各算一套。

### 反模式规避
- 不加"档位/滞回/惩罚项"二阶机制之外的新维度——引力就是一条距离衰减曲线。
- 不写 `if in_survivor / if boss`：任务锚由"当前是否有生效 objective 提供者"数据驱动，共享层零模式分支。
- 不碰玩家命令铁律：本 spec 只管**自主**目标选择；玩家点名的 `commanded_target` 永远盖在三层之上（feedback: 玩家命令是铁律）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 三个优先级带（加在可命中性 base∈[0,1] 上）

评分公式（单候选，友方僚机自主选择时）：

```
score = base01 × visibility × overkill × alt_pref × gravity_mult      # ③顺手层（乘性衰减）
        + objective_term                                              # ②任务层（加性）
        + survival_term                                               # ①生存层（加性）
```

其中 `base01 = 0.45·align + 0.30·env + 0.15·lock + 0.10·prox`（沿用 target-engageability-selection，不改权重）。

| 带 | 常量 | 值 | 贡献区间 | 语义 |
|---|---|---|---|---|
| ① 生存 | `SURVIVAL_BONUS` | 100.0 | `SURVIVAL_BONUS × threat01`，threat01∈[0.6,1.0] → **60~100** | 加性；候选正在咬**当前操控机** |
| ② 任务 | `OBJECTIVE_BONUS` | 40.0 | 存活 objective 成员 = **+40**（其余 0） | 加性；候选 ∈ 当前生效 objective 集 |
| ③ 顺手 | `gravity_mult` | 见 §2.2 | `base01 × [GRAVITY_FLOOR, 1.0]` ⊂ **[0,1]** | 乘性；离战场中心越远越被压 |

**带间隔离（每带严格压过下一带，与 base 无关）**：
- 顺手层上限 = 1.0（base=1×mult=1）。② 下限 40 > 1 → 任务永远压过顺手。
- ② 上限 ≈ 40+1 = 41。① 下限 60（threat01 地板 0.6）> 41 → 生存永远压过任务。
- 三带**可叠加**：BOSS 成员若正在咬你 = +40+ (60~100) → 自然最高，无需特判。

尺度对齐现有加分：`ATTACKING_LEADER_BONUS=60` / `LEADER_PROXIMITY_BONUS_MAX=25` / `REAR_GUARD_PRIORITY=100`（生存层沿用 100 量级，本就是"守后主导"的老尺度）。

### 2.1.1 交战地板 `ENGAGE_MIN_SCORE`（v2 新增，**没有它引力形同虚设**）

| 常量 | 值 | 说明 |
|---|---|---|
| `ENGAGE_MIN_SCORE` | 0.15 | 全部候选评完后，最佳者 score < 此值 → **本轮不交战**（留在 SQUAD_FOLLOW/PATROL，僚机自然守在长机/锚旁） |

**为什么必须有**：引力只压分，`try_engage` 选的是 argmax——BOSS 隐形/锥外时不进候选表（lock<30% 门直接 -1），僚机候选表里**只剩** 10km 外杂鱼（score≈0.06），没有地板它照样是第一名、僚机照样飞过去。地板才是"这仗不值得打→留在战场"的真正机制。
- survival（≥60）/ objective（≥40）恒过地板，天然豁免。
- 校准：距锚 5000px 的候选需 base ≥ 0.46 才值得打（正对+可锁的近身敌机轻松过）；R_FAR 外候选上限 = FLOOR 0.10 < 0.15 → **永不**顺手追击。无 objective 时（锚=操控机）4km 内 base 0.5 的杂鱼 mult≈0.55 → 0.275 过地板，日常清怪不受影响。
- reevaluate 侧对称：当前目标（非 survival/objective/commanded）score 连续 2 次评估 < 地板 → disengage 归队（治"已经在打远杂鱼的存量僚机"）。

### 2.1.2 leash 可行性门（v2 新增，根治 log① 的 45 次 engage↔rejoin 循环）

评分阶段直接拒掉"physically 追不到"的候选：本机在编队且非豁免时，
`dist(长机, 候选) > effective_squad_leash() × LEASH_FEAS_MARGIN(0.9)` → 该候选按 -1 处理（不参选）。

- 病根：候选离长机 3000px、leash 1800px → 咬上→飞出界→0.5s 拽回→3s 冷却→再咬同一个……log① 里 45 次 break-off 全是这个循环。**与其咬了再拽，不如评分时就不选**。leash 保留做兜底，但正常路径不应再触发它。
- 豁免：survival（leash 已放宽，§3.4）/ objective（leash 已重锚，§3.4）/ TS_COMMANDED（本就不过评分）/ 无编队者（PATROL 孤机没有 leash，靠 §2.1.1 地板 + 引力管）。

### 2.1.3 带感知粘性（v2 新增，防生存带内目标横跳）

| 常量 | 值 | 说明 |
|---|---|---|
| `STICKY_BONUS`（现有） | 0.10 | 当前目标在**顺手层**时的粘性（base 尺度，不变） |
| `SURVIVAL_STICKY` | 8.0 | 当前目标是 **survival 候选**时改用此粘性 |

**为什么**：两架追击者的 threat01 随距离连续变化（Δ300px ≈ 4 分），0.10/0.18 的 base 尺度粘性/切换阈值在 60~100 的带内形同虚设 → 防守僚机每秒在两个追击者间横跳、`_tactic_timer` 狂重置、BFM 决策瘫痪。SURVIVAL_STICKY=8.0 ≈ 600px 的距离滞回。
**objective 带刻意不加**：+40 是常数，同带两个 BOSS 成员的分差回落到 base 尺度 → 现有 0.18 阈值继续正常管用（这个不对称是设计，不是遗漏）。

### 2.2 引力衰减曲线（顺手层乘子）

`gravity_mult(d)`，d = **引力锚 → 候选**的像素距离（不是"锚→自己"）：

| 区间 | 值 | 像素 / 米 |
|---|---|---|
| `d ≤ R_CORE` | 1.0 | R_CORE = 2000px ≈ 4km |
| `R_CORE < d < R_FAR` | 线性 1.0 → `GRAVITY_FLOOR` | R_FAR = 6000px ≈ 12km |
| `d ≥ R_FAR` | `GRAVITY_FLOOR` = 0.10 | —— |

样例：CH-47 距锚 5000px（10km）→ `(5000-2000)/(6000-2000)=0.75` → `mult = 1.0 - 0.75×0.90 = 0.325`。一架对正+锁定的 CH-47 base≈0.6 → 0.6×0.325 ≈ 0.20，被任何 objective(+40) 碾压，且远不如锚附近的杂鱼。dist=17030m 那种 → 直接吃 FLOOR 0.10。

> 关键：**引力锚用 objective 成员的当前位置质心，即使 BOSS 隐形（不可锁）也照样可读**（boss-hunter-doctrine：BOSS 圈中心 = 存活成员质心）。所以隐形窗口里僚机被引力钉在 BOSS 门口打近处杂鱼，BOSS 一现身立刻凭 +40 回锁——不会飞去 17km 外。

### 2.3 生存威胁强度 threat01

**生存层只对空**（用户 2026-07-24 定档）。候选是"生存威胁"当且仅当：候选是**敌方飞机** 且 `当前操控机.engaging_me.has(候选.instance_id)`（候选把操控机设为了 `_current_target`，即正在咬你）**且** `dist(候选, 操控机) ≤ SURVIVAL_RANGE`。

> ⚠ **已核实的边界（非 bug，是刻意范围）**：`engaging_me` 反查索引**只有飞机的 AIController 会写**（`_current_target as Aircraft`）。地面单位（SAM/AAA/雷达站，GroundUnit）与航母/舰船（NavalUnit：SAM_SHORT/VLS/CIWS 都会打玩家）用各自的 `combat_target`，**永不进 `player.engaging_me`**。因此生存层对地面/航母威胁**恒不触发**（`.has()` 查不到 = false，不崩）。这些威胁的分工：
> - 地面 SAM/AAA → 现有 `scan_leader_threat_ground`（按靠近距离扫、导弹 standoff 拔除，squad-cohesion）。
> - 航母/舰船 → 多为 BOSS，直接吃**任务层 +40**（§2.4，naval 成员在 objective 集里）。

| 常量 | 值 | 说明 |
|---|---|---|
| `SURVIVAL_RANGE` | 3000px ≈ 6km | 超此距离的"咬你"不算急威胁（够不着） |
| threat01 基线 | 0.6 | 满足触发即给 0.6 地板（保证压过任务层） |
| threat01 近距加成 | +0.4 × prox_ctrl | `prox_ctrl = 1 - clamp(dist/SURVIVAL_RANGE,0,1)`，贴脸→1.0 |

threat01 = `0.6 + 0.4 × prox_ctrl` ∈ [0.6, 1.0]。（是否再叠"候选已锁定你/正开火"的额外权重留作 spec_version 2 的 playtest 调项，先不做——避免二阶机制。）

### 2.4 任务（objective）提供者与锚

任务层是**单槽**（用户定档：真 BOSS 登场时战区已清，二者不同时存在）。锚与成员集由"当前生效的 objective 提供者"给出，优先级 BOSS > 战区：

| 提供者 | 生效条件 | 成员集（objective_term=+40 的对象） | 引力锚位置 |
|---|---|---|---|
| BOSS | 存在 `active==true` 的 BossEncounter | 该 encounter 的 `get_display_members()` 存活成员（**实际成员表**，飞机 BOSS=Aircraft / 舰队 BOSS=NavalUnit/MountTarget 均在内） | 存活成员**质心** |
| 战区任务 | 无 active BOSS，且有 **triggered** 战区（多个并发时取**距操控机最近**的一个——`_spawned_zones` 是字典，同屏多战区真实存在，必须定选择规则） | 该战区已标记单位（meta `zone_mission` / `zone_garrison`；地面 TGT 单位若带 zone meta 一并计入，实现时核对） | 该战区 `center` |
| 无 | 上两者皆无 | ∅（无人吃 +40） | **当前操控机位置** |

> ⚠ **成员集判定禁用字符串匹配**：不得用 `category` meta 含 "boss"/"ace" 来判 objective —— 非 BOSS 的**王牌支援中队** `ace_support_squad` 的 `category=="ace_support"` 正好含 "ace"，会被误判成任务目标吃 +40（它明确"不打 boss"、不该抢 BOSS 的火力优先级）。**只认当前 active `BossEncounter.get_display_members()` 返回的实例**（O(1) 查 instance_id 集）。这也天然覆盖航母 BOSS 的 NavalUnit/MountTarget 成员。
>
> **质心 anchor 用存活成员**：`get_display_members()` 含已击毁成员（HUD 显示 DOWN），算锚/判 +40 时必须过滤 `is_destroyed`，否则 +40 加在尸体上、质心被拉偏。

无 objective 时，引力锚退化为操控机 → 顺手层把僚机收在你身边，不许游走（顺带压 ① 之外的散兵游勇）。

## 3. 行为与公式（How）

### 3.1 两个整合面（分工）

| 面 | 作用 | 治的病 | 绕开雷达锥？ |
|---|---|---|---|
| **A. 评分加分**（target-engageability-selection 的候选打分） | 决定"我 radar_targets 里的可锁目标，选谁" | ②（BOSS 战不跑去打远杂鱼） | 否（只作用于已可锁候选） |
| **B. 主动防御扫描**（scan_leader_rear 的泛化：锚到操控机、常开、走 all_units 距离扫描） | 把"咬你但没进任何僚机雷达锥"的追击者也捞出来指派 | ①（追你的没人管） | 是（复用 all_units，不受锥/锁门限制） |

面 A 是本 spec 的乘/加分公式（§2）。面 B 是把现有 `scan_leader_rear` 从"仅 GUARD_REAR 模式 + 锚长机 + 900px"泛化为"常开 + 锚当前操控机 + SURVIVAL_RANGE"，威胁排序直接复用 `rear_threat_score` 语义但改为"咬操控机"判据。二者共用同一套 §2.3 threat 判据，杜绝公式漂移。

### 3.2 面 A：候选打分（伪码）

```
func score_candidate(cand, self_ai):
    base = 0.45·align + 0.30·env + 0.15·lock + 0.10·prox      # 现有
    s = base × visibility × overkill × alt_pref               # 现有修饰

    is_survival = cand is Aircraft
                  and controlled.engaging_me.has(cand.id)
                  and dist(cand, controlled) <= SURVIVAL_RANGE
    is_objective = cand in objective_member_set               # §2.4

    if not is_survival and not is_objective:                  # 仅顺手层：
        if in_squad and dist(leader, cand) > effective_leash × 0.9:
            return -1                                         # §2.1.2 可行性门：追不到的不选
        s *= gravity_mult(dist(objective_anchor, cand))       # §2.2 引力

    if is_objective:
        s += OBJECTIVE_BONUS                                  # +40
    if is_survival:
        s += SURVIVAL_BONUS × threat01(cand)                  # +60~100
    return s

# 调用方（try_engage）：
#   best = argmax(score)；粘性 = SURVIVAL_STICKY(8.0) 若当前目标 is_survival，否则 STICKY_BONUS(0.10)
#   if best_score < ENGAGE_MIN_SCORE: return   # §2.1.1 地板：这仗不值得打，留在编队/巡逻
```

- objective / survival 候选**不吃**引力衰减也**不吃**可行性门（它们就是战场本身 / 保命本身；leash 对二者已分别放宽/重锚，§3.4）。
- 玩家命令铁律：`commanded_target` 路径完全不过本函数（走 TS_COMMANDED，AIController 既有仲裁），本公式只影响 TS_SCORED 自主选择。
- **生效门**：只对友方玩家小队的 AI 机（`is_player_squad()` 且非 manual_control）叠三带/地板/可行性门；敌方 AI 走原公式零变化——否则敌机远离锚时会"拒绝交战玩家僚机"，把引力错误地送给敌人。
- **同源覆盖 `scan_squad_nearby_enemy`**（SQUAD_FOLLOW 自由扫描）：该路径用 1/d 就近选，BOSS 在 1400px、杂鱼在 600px 时会选杂鱼。三带加分抽成共享 helper（`band_bonus(cand)`），评分路径与自由扫描两处同源叠加（自由扫描 range≤1500px，引力/可行性门在此几乎不触发，只需带加分）。

### 3.3 面 B：主动防御扫描（泛化 scan_leader_rear）

```
每 1s（沿用 _scan_timer）对每个存活僚机：
  protectee = 当前操控机   # 不再是 squad.leader；切控随之转移（用户定档）
  if 当前回防僚机数 >= MAX_DEFENDERS: break    # 不许全队回防（见下）
  best = argmax over hostile *Aircraft* in all_units:   # 只扫飞机，naval/ground 不进
             survival_score(protectee, unit)     # = threat01 语义，见 §2.3
  if best and best.threat01 >= THREAT_ENGAGE_MIN(0.6):
      指派该僚机 autonomous engage best（复用 _enter_autonomous_engage）
```

- **回防不许掏空火力**：`回防数 = min(MAX_DEFENDERS=2, 存活自主僚机数)`。仅此一条——v1 曾附加"至少留 1 架在任务上"，与"活命第一"矛盾（只剩 2 架且你被咬时，两架都该回防），v2 删除：MAX_DEFENDERS 上限已足以防"一架 MiG 咬你、4 架全放弃 BOSS"的火力涣散。回防计数 = 遍历小队成员数"当前目标 ∈ protectee.engaging_me"者（无新增状态字段）。多个追击者靠 `_is_target_already_squad_engaged` 分摊（不挤同一个）。
- **只扫敌方 Aircraft**：面 B 复用 `rear_threat_score`/`escort_target_bonus`（内部 cast Aircraft），扫描循环必须先过 `unit is Aircraft`（现有 scan_leader_rear 已如此）→ naval/ground 天然进不来，无 cast 崩溃风险。
- 常开（不再要求 `squad_engage_mode==GUARD_REAR`，也不要求"长机正在攻击"）。
- 与面 A 关系：面 B 负责"捞出锥外追击者并指派"，指派后该僚机进 ENGAGE，后续换目标走面 A 评分（survival 候选仍 +60~100，粘住不放）。面 B 用 TS_SCORED 指派，**不 override 玩家命令**（TS_COMMANDED 优先级更高，仲裁保证——被点名的僚机不会被拽去回防）。

### 3.4 与 leash 的关系（治①的包抄被拽回）

leash（squad-cohesion _apply_constraints 约束 2）保留做硬兜底，但需两处松绑，否则生存层刚指派就被拽回：
- **生存交战放宽 leash（v2 修正公式）**：僚机正在打 survival 目标（目标 ∈ protectee.engaging_me 且存活）时，leash 距离 = `SURVIVAL_RANGE + BRACKET_SLACK = 3000 + 1200 = 4200px`（**常数**）。v1 曾写"= anchor 到 protectee 距离 + slack"——错了：leash 量的是僚机↔长机距离，而 survival 战斗就发生在 protectee 身边，anchor 位置无关。有界性天然成立：追击者逃出 SURVIVAL_RANGE → 不再是 survival → 正常 leash 即刻恢复收回僚机，不存在"永不拽回"。
- **leash 重锚只在有 active objective 时生效**（缩小改动面，降 bug 风险）：有 BOSS/战区任务时，leash 锚从"长机"改"引力锚"（向战场中心收拢）；**无 objective 时保持现状**（锚长机/操控机，行为不变，不动巡逻场景）。已知 playtest 观察项：重锚后若玩家单独脱离 BOSS 战场（未被咬），僚机会留在 BOSS 处继续压——这是 RTS 语义的刻意选择，玩家用轮盘"紧急集合"显式召回；若体感不适再调。
- **可行性门（§2.1.2）把 leash 从"常态纠错"降级为"真兜底"**：正常路径评分时就不选追不到的目标，leash 只兜"目标交战中逃远"等动态漂移。验收上体现为 LEASH break-off 事件数量级下降（log① 基线：300s 内 45 次）。

> 注：面 A/B 是"往战场拉"的软引力，leash 是"别游走"的硬边界；本 spec 让二者共用同一个 objective_anchor，消除"顺着 leash 杀包抄、绕过 leash 放羊"的二义。

### 3.5 已知盲区与独立调查项（v2 复审发现，不在本 spec 修）

- **玩家僚机为何掉进 PATROL**：log② 中多架玩家 J-20 僚机以 `PATROL → ENGAGE` 交战（正常应在 SQUAD_FOLLOW）。PATROL 孤机**没有 leash**，引力只能过滤其目标选择（地板+引力），**不能物理拉它回来**——本 spec 对这类僚机只有半效。疑与切控/长机阵亡后的编队重建缺口有关（squad-control-switching "打完再归队"路径）。→ 独立调查，勿混入本 spec 改动面。
- **`DISENGAGE (was fighting None, engaged 52.1s)` 异常**：ENGAGE 态挂着 null 目标 52 秒才脱离（log② 两例）。疑为目标释放/仲裁的边角 bug，同样独立调查。

## 4. 结构与组成（Structure）

- **ObjectiveContext（新增，队级共享，每帧/低频刷新一次）**：数据类，提供 `has_objective`、`member_set`（判 is_objective，O(1) 查表）、`anchor: Vector2`（引力锚）。由生存模式在已知"当前 BOSS encounter / 当前 triggered 战区"处填充（数据驱动，不在共享层写模式分支）。BOSS 分支读 encounter 存活成员质心；战区分支读 zone center；皆无则 anchor=操控机。
- **面 A 注入点**：target-engageability-selection 的候选打分函数（叠 §3.2 三项）。
- **面 B 注入点**：squad-cohesion 的 rear-guard 扫描（泛化为 protectee=操控机、常开）。
- **protectee 来源**：当前操控机引用，必须经 `survivor_mode._set_player_aircraft()` chokepoint 重定向（SEAM-019；切控后 ObjectiveContext / 面 B 都要指向新机，否则护的是旧机）。注意 naval 单位本身也直接持 `AircraftRenderer.player_ref` 打玩家（既有 SEAM-019 持有者，非本 spec 引入）——本 spec 新增的 protectee/anchor 缓存并列登记即可。
- **候选类型安全**：面 A 的候选 `cand` 可能是 Aircraft / GroundUnit / NavalUnit / MountTarget（僚机能打地/船）。三带项**只用** `cand.get_instance_id()`（survival/objective 查表）与 `cand.global_position`（gravity 距离），**不得 cast Aircraft**。需要 Aircraft 语义的只有面 B（`rear_threat_score`），它已 Aircraft-only 过滤。
- **消费方**：仅友方玩家小队僚机的 TS_SCORED 路径。敌方小队、玩家命令（TS_COMMANDED）、BOSS 攻击手不受本 spec 影响（各有既有逻辑）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **①回防**：脚本 sim —— 操控机被一架敌机咬住（写入 `controlled.engaging_me`），近旁僚机在打远处杂鱼；1~2s 内至少 1 架僚机 acquire 该追击者（面 B 指派 + 面 A survival +60）。
- [ ] **②不跑远**：脚本 sim —— 场上有 active BOSS（成员 + 质心锚）+ 一架 10km 外可锁 CH-47；僚机评分 BOSS 成员 > CH-47；CH-47 gravity_mult ≤ 0.35。
- [ ] **②地板生效（v2 核心补测，主病征场景）**：候选表里**只有**远杂鱼（BOSS 隐形/锥外不进表）→ `try_engage` 因 `best < ENGAGE_MIN_SCORE` **不交战**，僚机留在 SQUAD_FOLLOW；无 objective 时 4km 内 base 0.5 杂鱼仍正常交战（日常清怪不受影响）。
- [ ] **可行性门杀循环（v2）**：候选距长机 3000px、leash 1800px → 评分即拒（-1），不产生 engage→LEASH break-off→rejoin 循环；playtest 对照 log① 基线（300s/45 次 break-off），新版应下降一个数量级。
- [ ] **生存带内不横跳（v2）**：两架追击者距离交替小幅变化（±300px）时，防守僚机 10s 内目标切换 ≤ 1 次（SURVIVAL_STICKY 滞回生效）。
- [ ] **隐形不破功**：BOSS 全体 `is_lock_immune()==true`（cloak）时，僚机不因锁不上而飞去远杂鱼——引力锚仍为 BOSS 质心，远杂鱼仍被压。
- [ ] **带间隔离**：单测断言 任一 survival 候选评分 > 任一 objective 候选 > 任一 near-anchor 顺手候选（base 拉满也不越界）。
- [ ] **命令铁律不受影响**：玩家点名远目标（TS_COMMANDED），僚机仍执行、不被引力/leash 拽回（既有 `_cmd_engage_active` 豁免 + 本 spec 不介入 TS_COMMANDED）。
- [ ] **切控转移**：切控到僚机后，新操控机成为 protectee/锚参照；对旧机的护航停止（无野指针，SEAM-019）。
- [ ] **非飞机威胁不误触发/不崩**（本轮审查专项）：
  - SAM/AAA/航母 SAM 锁并射击操控机时，生存层**不触发**（对空设计）、**不崩**；地面威胁仍由 `scan_leader_threat_ground` 覆盖。
  - 单测：以 GroundUnit / NavalUnit 作候选跑面 A 打分，无 Aircraft cast 异常；其 is_survival==false。
  - `ace_support` 中队（category=="ace_support"）**不**被判为 objective（不吃 +40）——用 BossEncounter 成员表而非字符串。
  - 航母 BOSS：NavalUnit/MountTarget 成员正确吃 +40，质心锚只算存活成员（击毁成员剔除）。
- [ ] **回防不掏空火力**：sim —— 单个追击者咬玩家时回防僚机数 ≤ `MAX_DEFENDERS`，且 active objective 下至少 1 架仍在任务目标上。
- [x] 单测断言并入 `--bench=target_sel`（G1~G11 共 28 断言：曲线/三带/地板/可行性门/隐形锚/非飞机/粘性/关闭基线/回防指派/上限/leash 三态；35/35 PASS）。物理步进 sim（detached Aircraft 逐帧验证指派后确实飞向追击者）**playtest 前补**。
- [x] 性能：`--bench=stress_40` 三轮对照（基线 20260724 vs 引力 live 两轮）——ai_tick 6.25→7.15→**6.09**µs/call、aircraft_phys 33.7→38.7→**32.6**µs/call；未触碰的 aircraft_phys 桶与 ai_tick 同幅波动 → ±15% 为场景随机噪声，引力开销在噪声地板内。相邻回归：fire_discipline 10/10、rejoin 指标与基线一致。
- [x] 已知 seam：SEAM-019——protectee 赋值就在 `_set_player_aircraft` chokepoint 内，`verify_player_ref_holders.py` ✓（26 接收方 / 漏登记 0）。
- [x] i18n：零新增玩家可见文本（回防 tactic 标签复用既有 TACTIC_GUARD_REAR key）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — ObjectiveContext + 面 A 评分（先落地，单独治②）✅ 2026-07-26
- [x] 新增 ObjectiveContext 数据类（has_objective / member_set / anchor）+ 生存模式低频填充（BOSS 质心 / 最近 triggered 战区 center / 操控机兜底；0.5s；新局 reset+enable / 退局 reset / protectee 走 chokepoint）
- [x] 常量：SURVIVAL_BONUS/OBJECTIVE_BONUS/GRAVITY_FLOOR/R_CORE/R_FAR/SURVIVAL_RANGE/BRACKET_SLACK/**ENGAGE_MIN_SCORE/LEASH_FEAS_MARGIN/SURVIVAL_STICKY**（全住 ObjectiveContext，模块自含）
- [x] 面 A：候选打分叠 gravity_mult（顺手层）+ objective_term + survival_term + **可行性门（§2.1.2）**；三带抽共享 helper `band_bonus(cand)`
- [x] **try_engage/reevaluate 接地板**（§2.1.1：best < ENGAGE_MIN_SCORE 不交战；当前顺手目标连续 2 评估 < 地板 → disengage）+ 带感知粘性（§2.1.3 `_sticky_for`）
- [x] `scan_squad_nearby_enemy` 叠 band_bonus（同源 helper）
- [x] 单测：带间隔离 + gravity_mult 曲线样例 + 隐形锚不破功 + **地板拒远杂鱼（含锚旁负向对照）+ 可行性门拒 leash 外候选（含 survival 豁免）+ 带感知粘性 + 非飞机安全 + enabled=false 逐位基线**——G1~G8 共 22 断言并入 `--bench=target_sel`，29/29 PASS（原 7 断言零回归）；相邻回归 `--bench=fire_discipline` 10/10 PASS；`verify_player_ref_holders.py` ✓（protectee 在 chokepoint 登记）

### 阶段 2 — 面 B 主动防御扫描（治①）✅ 主体 2026-07-26
- [x] 面 B 回防（`try_defend_protectee`，独立于 GUARD_REAR：protectee=操控机、SQUAD_FOLLOW 常开 1Hz、
      直读 engaging_me 绕雷达锥、MAX_DEFENDERS=2 + `_count_defenders` 反查无新状态、
      `_is_target_already_squad_engaged` 分摊、隐形铁律过滤；threat 判据统一走 ObjectiveContext §2.3）
- [x] leash 松绑（`leash_anchor_and_limit`：生存交战 4200px 常数锚操控机 / active objective 重锚引力锚 /
      无引力逐位旧行为；_apply_constraints 消费）
- [x] 单测 G9~G11（回防指派含锥外验证 / 上限+补位 / leash 三态）——target_sel 35/35 PASS
- [ ] sim 断言：被咬→僚机回防指派→确实物理飞向追击者（detached Aircraft 逐帧步进，播 playtest 前补）

### 阶段 3 — 收尾
- [ ] SEAM-019 chokepoint 补重定向 + verify_player_ref_holders.py 过
- [ ] （可选）②兜底：BOSS ENGAGED 后收敛杂兵刷新，减少诱惑源（survivor_spawner）
- [ ] playtest 调 SURVIVAL_RANGE / OBJECTIVE_BONUS / 引力曲线；填 §7 锚点 + §8；status→done

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| ObjectiveContext（三带判据 + 引力曲线 + 全部常量） | `scripts/ai/objective_context.gd` |
| 面 A 评分（`_score_candidate` 引力/三带/可行性门 + `_sticky_for` + try_engage 地板 + reevaluate 地板脱离） | `scripts/ai/target_selection.gd` |
| 自由扫描带加分（`scan_squad_nearby_enemy`） | `scripts/ai/squad_coordination.gd` |
| 地板脱离计数字段 `_gravity_low_evals` | `scripts/ai_controller.gd` |
| 战区 objective 查询（`get_nearest_triggered_objective`） | `scripts/survivor/zone_mission.gd` |
| 生存模式填充（`_update_objective_context`）/ protectee 重定向（`_set_player_aircraft`）/ 新局启用（`_ready`）/ 退局清理（`_exit_tree`） | `scripts/survivor/survivor_mode.gd`（SEAM-019 chokepoint） |
| 单测 G1~G8 | `scripts/tests/test_target_selection.gd`（并入 bench `target_sel`） |
| 面 B 扫描 / leash 松绑（阶段 2 待落地） | `scripts/ai/squad_coordination.gd` / `scripts/ai_controller.gd` |
| reference 索引行 | script-index.md 的 objective_context / target_selection 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-24 | 1 | 初稿。由 log 20260724_222238（①包抄被拽回）+ 20260724_222827（②BOSS 战打远杂鱼）驱动。三带模型 + 引力锚定档：生存层护当前操控机 / 任务层单槽 BOSS 优先 / 引力锚=当前任务目标位置。 |
| 2026-07-24 | 1 | 落地前边界审查（用户要求"多做检查、别造 bug"）。核实锁定链：`engaging_me` 仅飞机 AIController 写，地面/航母（NavalUnit SAM/VLS/CIWS 确会打玩家）走各自 combat_target 不进反查。定档**生存层保持对空**（地面→scan_leader_threat_ground，航母→任务层）。修真 bug：objective 判定改用 `BossEncounter.get_display_members()` 实例表（原"category 含 ace"会误伤 ace_support）。收窄：面 B 加 `MAX_DEFENDERS` 防全队回防、leash 重锚只在 active objective 时生效、候选类型安全（不 cast Aircraft）。补边界验收 4 项。 |
| 2026-07-26 | 2 | **验证收口 + 挂具排障**。误用未注册 bench 名 `formation_rejoin`（正名 `rejoin`）踩进通用场景路径并暴露挂具既有 bug：bench 玩家机阵亡 → `is_game_over` 早退冻结倒计时 → 进程永久挂死（已登记独立修复任务，不混本 spec）。正确回归全绿：target_sel 35/35 / fire_discipline 10/10 / rejoin 指标一致 / stress_40 三轮证引力开销在噪声地板内 / 双校验脚本 ✓。§5 除物理 sim 断言与 playtest 项外全部勾除。 |
| 2026-07-26 | 2 | **阶段 2 主体落地**（面 B 回防 + leash 松绑）。`squad_coordination.gd` 新增 `try_defend_protectee`/`_count_defenders`/`MAX_DEFENDERS`，process_squad_follow 挂 1Hz 常开扫描（独立 `_defense_scan_timer`，不抢 FREE 扫描节奏；优先于 GUARD_REAR/FREE/跟打长机全部分支）；`ai_controller.gd` 抽 `leash_anchor_and_limit()` 三态 helper（生存 4200px 锚操控机 / objective 重锚 / 旧行为），_apply_constraints 消费。tactic 标签复用 TACTIC_GUARD_REAR（零 i18n 新键）。单测 G9~G11，target_sel 35/35。剩余：物理步进 sim 断言 + playtest。 |
| 2026-07-26 | 2 | **落地即撞的坑（freed-instance `is` 判序）**：`--bench=formation_rejoin` 硬崩（exit 4 无 script error）——战区 units 表（_spawned_zones/_garrison_zones）不即时剔除阵亡单位，含 freed 引用；对 freed 实例求值 `x is CombatUnit` 直接抛错中断。修法=**`is_instance_valid` 必须在 `is` 之前**，三处统一（set_boss_objective / set_zone_objective / is_survival_threat——后者经 `_sticky_for` 吃 `ai._current_target`，同样可能 freed）。 |
| 2026-07-26 | 2 | **阶段 1 落地**（ObjectiveContext + 面 A + v2 三件套）。新文件 `objective_context.gd`（全静态，常量自含）；`_score_candidate` 接引力/三带/可行性门；try_engage 地板 + reevaluate ×2 评估地板脱离 + `_sticky_for` 带感知粘性；自由扫描叠 band_bonus；zone_mission 加 `get_nearest_triggered_objective`；survivor_mode 四处接线（_ready 启用/_exit_tree 清理/chokepoint protectee/_physics_process 0.5s 填充）。验证：target_sel 29/29（G1~G8 新 22 断言 + 原 7 零回归）、fire_discipline 10/10、player_ref_holders ✓。阶段 2（面 B 常开回防 + leash 松绑）与阶段 3 待做。 |
| 2026-07-24 | 2 | **Fable 复审——修致命洞 + 消振荡**。①致命：引力只压分但 try_engage 选 argmax，BOSS 隐形/锥外不进候选表时僚机照样飞去打唯一候选的远杂鱼 → 新增 `ENGAGE_MIN_SCORE=0.15` 交战地板（§2.1.1，survival/objective 恒过）+ reevaluate 侧连续 2 评估低于地板即脱离。②新增 leash 可行性门（§2.1.2）：评分时拒掉 `dist(长机,候选)>leash×0.9` 的追不到目标，根治 log① 45 次 engage↔rejoin 循环（leash 降级为真兜底）。③新增带感知粘性 `SURVIVAL_STICKY=8.0`（§2.1.3）：threat01 连续变化导致带内目标横跳，0.10/0.18 base 尺度粘性在 60~100 带内失效；objective 带刻意不加（+40 常数，带内回落 base 尺度）。④修 v1 自相矛盾：删"至少留 1 架在任务上"（与活命第一冲突），回防数=min(2,存活)。⑤修 v1 leash 放宽公式错误：改常数 `SURVIVAL_RANGE+BRACKET_SLACK=4200px`（anchor 距离无关，有界性由 survival 判定自然保证）。⑥`scan_squad_nearby_enemy` 同源叠 band_bonus（编队自由扫描 1/d 就近会在 BOSS 1400px/杂鱼 600px 时选错）。⑦多战区并发定规则：最近 triggered。⑧登记独立调查项：玩家僚机掉 PATROL（无 leash，引力半效）+ "fighting None 52s" 异常。补验收 3 项。 |
