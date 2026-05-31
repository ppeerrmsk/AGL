---
id: squad-ai-escort
kind: system
status: draft
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [squad-control-switching, survivor-loop]
reconstruction_complete: false
---

# 玩家小队僚机 AI 护卫强化 —— 护长机 / 反杀攻击者 / 守后半球

> 玩家视角：你的 AI 僚机不再各打各的，而是真正像"护卫机"——以你（当前操控的长机）的安危为中心：优先干掉正在咬你的敌人，并留人罩住你的六点钟后半球。配合操控切换，无论你上手哪一架，僚机都护着"现在的你"。

## 1. 设计意图（Why）

RTS 化要求僚机像"小队"而非"散兵"。本 spec 给玩家小队僚机注入**护卫意图**：无指定目标时，决策中心从"离我最近的敌机"转为"长机的安危"。

**体验目标**（用户三目标）：
1. **保护长机**：无指定目标时僚机以长机安危为中心决策。
2. **优先攻击正在攻击长机的敌人**：谁咬长机，僚机优先去杀谁。
3. **掩护长机后半球**：留一架占位守长机六点钟，拦截后方威胁，不脱队乱冲。

**护卫强度定调（用户决策：护卫优先但不死板）**：默认以护卫为主——优先反杀攻击长机者、留人守后半球；但身边的顺手敌机仍会打，不做"贴身保镖把战场打空"。保留战场热闹感（原则 7）。

**适用范围（用户决策：玩家队 + BOSS 精英队，不给杂兵）**：护卫逻辑对**玩家小队（team==0）与 BOSS 精英编队（F-47 王牌队 / Mother Goose 护航队等显式标记的精英 squad）生效**；普通杂兵敌机/敌方散兵编队**保持现有 BFM 不变**。

为什么这样切：
- **性能可控**：只有"玩家队 + 少数精英队"的 leader 需要维护 engaging_me 反查，反查规模 = 几个队的长机，不是全场 → 远离 O(N²)。
- **符合原则 8（BOSS AI 要聪明）**：精英 BOSS 编队懂得护卫旗舰/反杀威胁者，正是"真聪明"的体现；杂兵不配吃这套智能，也维持难度梯度。
- **接口通用**：评分/守后/反查写成不绑死 team 的形式，是否对某 squad 启用由 squad 上的 `escort_doctrine_enabled` 标记控制（玩家队默认 on，精英 BOSS 队建队时 on，杂兵 off）。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 3（信息察觉优先）**：✅ 僚机扑向"咬长机的敌人"、留人守后方，是玩家肉眼可见的行为差异，不是暗 buff。
- **原则 7（战场热闹 + AI 演戏）**：✅ 核心正命中——僚机"罩着你"是强演戏感；"护卫但不死板"避免战场变空。
- **原则 8（BOSS 真聪明）**：✅ 精英 BOSS 编队护卫旗舰/反杀威胁者 = "AI 聪明"维度；杂兵不吃此智能，维持 BOSS 与杂兵的差距。
- **原则 11（60 FPS）**：✅ 威胁反查走 O(1) engaging_me 反向索引（仅玩家队 + 少数精英队维护，非全场扫描）+ 既有 tick 节流，无新全场遍历。

**反模式规避**：
- ❌ 不做"僚机看不出差别的暗调"（原则 3）——护卫行为必须可感知。
- ❌ 不让护卫僚机贴身到把战场打空（违背原则 7 热闹）——"不死板"。
- ❌ 不引入 O(N²) 全场威胁扫描（违背性能守则）——定向 engaging_me。
- ❌ 不覆盖敌方编队 BFM（范围隔离）。

## 2. 数据定义（What —— 权威源）

### 2.1 核心概念：长机 = 当前操控机（动态）

| 概念 | 定义 |
|---|---|
| **护卫编队** | `escort_doctrine_enabled = true` 的 squad：玩家队（默认 on）+ 精英 BOSS 队（建队时 on）。杂兵队 off，本逻辑全程跳过 |
| **被护卫的长机** | 该 squad 的 leader。**玩家队**：= 玩家当前操控那架（随操控切换动态变，见 [squad-control-switching](squad-control-switching.md)）；**BOSS 队**：= 该编队旗舰/长机 |
| **护卫者（僚机）** | 同 squad、非长机、AI 自主（`manual_control=false`）的飞机 |

### 2.2 目标评分加权（在现有 try_engage / scan_squad_nearby_enemy 评分上叠加）

现有评分 = 距离 + 锁定度。新增两个加权项（仅护卫编队的僚机，即 escort_doctrine_enabled）：

| 加权项 | 权重 | 含义 |
|---|---|---|
| **正在攻击长机** | `ATTACKING_LEADER_BONUS = +60`（评分主导项） | 该敌机 `combat_target == 长机`（查长机 engaging_me，O(1)）→ 大幅提权，僚机优先去杀 |
| **威胁距长机近** | `LEADER_PROXIMITY_BONUS`，按距离插值 0~+25 | 敌机离长机越近威胁越大，叠加权重 |
| 顺手敌机（原距离/锁定分） | 现有 | 保留——"不死板"，身边敌机仍纳入候选 |

> 效果：候选里若有"咬长机的敌人"，几乎总会被僚机优先选中；没有时退化为现有就近交战（护卫但不死板）。

### 2.3 后半球掩护常量

| 常量 | 值 | 说明 |
|---|---|---|
| `REAR_CONE_HALF_ANGLE` | 90°（後半球，复用现有 scan_leader_rear 门槛 PI*0.5） | 长机航向背向 ±90° 内算"后半球" |
| `REAR_COVER_SCAN_RANGE` | 复用现有 `COVER_SCAN_RANGE`（~2500px / 5km） | 后半球威胁扫描半径 |
| `REAR_GUARD_SLOT_DIST_M` | 长机后方占位距离（建议 800~1200m，调参定） | 守护者飞到长机正后方此距离的拦截位 |
| `COVER_REASSIGN_HYSTERESIS` | 1.5 s | 守护者重指派的迟滞，防止逐 tick 抖动换人 |
| 威胁反查频率 | 复用僚机 AI tick（~0.5~1Hz，不每帧） | 见 §3.5 性能 |

### 2.4 engaging_me 定向扩展（关键，范围红利）

| 现状 | 改为 |
|---|---|
| 攻击者只对 `AircraftRenderer.player_ref`（玩家正控的那一架）登记 `engaging_me` | 攻击者对**所有护卫编队的成员**登记 `engaging_me`（全体玩家队 + 精英 BOSS 队成员） |
| 攻击者对杂兵/散兵 | **不登记**（无人读 → 不维护，省成本） |

> 写入方=攻击者（锁定到"护卫编队成员"时登记其 engaging_me），读取方=护卫僚机（查本队 leader 的 engaging_me，O(1)）。维护范围 = 玩家队 + 少数精英队的成员，**不是全场** → 远离 O(N²)。
>
> **集中开关**：维护范围由 `_maintains_engaging_me(target)` 判定（`return target.squad and target.squad.escort_doctrine_enabled`）。玩家队默认 enabled；F-47 / Mother Goose 等精英队建队时置 enabled；杂兵队 false → 攻击它们不写 engaging_me。要调整覆盖面只改建队处的标记。

## 3. 行为与公式（How）

### 3.1 僚机决策优先级（无玩家指定目标时）

护卫编队的僚机（escort_doctrine_enabled、非长机、自主）每个决策 tick：
```
1. 查长机威胁：leader_threats = 长机.engaging_me 中的存活敌机（O(1) 读 + 过滤）
2. 若本机被指派为后半球守护者（§3.3）→ 优先占位守后（除非自己正被近距咬）
3. 目标评分（§2.2）：候选敌机按 [距离 + 锁定 + 正在攻击长机×60 + 近长机×0~25] 排序
   → 选最高分（通常 = 咬长机的敌人）
4. 无任何候选 → 回编队跟随长机（SQUAD_FOLLOW，现有）
```
"护卫优先但不死板"由评分实现：威胁存在时护卫项主导，不存在时自然退回就近交战。

### 3.2 优先攻击攻击长机者（目标 2）

- 反查"谁在打长机" = 读 `长机.engaging_me`（定向扩展后可用），过滤存活 + 敌方 → 给这些敌机加 `ATTACKING_LEADER_BONUS`。
- 多架僚机不重复抢同一威胁：复用现有 `_is_target_already_squad_engaged()`，已咬该威胁的僚机够了，其余转向次威胁或顺手敌机。

### 3.3 后半球掩护：指派一机占位守后（目标 3，用户选"指派一机占位守后"）

```
每威胁评估 tick（带 COVER_REASSIGN_HYSTERESIS 迟滞）：
  rear_threats = scan_leader_rear(长机)  # 复用现有后半球扫描
  若 rear_threats 非空：
    指派"最适合的一架僚机"为后半球守护者：
      - 优先选当前离长机后方占位点最近、且未深陷自己缠斗的僚机
      - 该僚机目标点 = 长机正后方 REAR_GUARD_SLOT_DIST_M 处的拦截位（朝威胁微偏）
      - 它在此拦截后方来敌，不脱队冲向远处
  若 rear_threats 为空 → 解除守护指派，僚机回常规护卫/编队
```
- **只指派一架**（不是全队回防），其余僚机照常按 §3.1 评分作战 → 保持"不死板"。
- 守护者占位用现有编队托管路径加一个"rear_guard"目标点，不新写阵型物理。

### 3.4 ★ 与操控切换的交互（回答用户 Q2，硬约定）

**守护者角色是瞬态的、键于"当前长机引用"、每评估 tick 重算**，而非钉在某架飞机上。因此操控切换天然自愈：

| 切换场景 | 行为 |
|---|---|
| 玩家从 A 切到 B（B 成新长机） | 监听 `leader_changed` → 护卫/守后全部以 **B** 为中心重算；原守 A 后方的僚机改守 B 后方 |
| 玩家恰好切去操控"当前后半球守护者" | 该机 `manual_control=true`（AI 休眠，§squad-control-switching）→ 守护职责当帧失效 → 下个 tick 自动另指派一架补位 |
| 长机自己 | 护卫逻辑**跳过 `manual_control` 的机**（玩家正控的那架）→ 长机永不"守护自己" |
| 长机被击落自动接管下一号机 | 新长机确立后，护卫目标随 `leader_changed` 切到新长机 |

**实现红线**：护卫/守后指派**禁止**写成飞机的持久属性；必须每评估 tick 依据"当前长机"重新求值（带迟滞防抖）。这样切换无需任何特殊善后代码。

### 3.5 性能（守则强制）

- **威胁反查 O(1)**：读 `长机.engaging_me` 字典，不遍历 all_units。engaging_me 的写入由敌机锁定时差量维护（仅 team0 方向）。
- **后半球扫描**复用现有 `scan_leader_rear`（已节流），不新增全场扫描。
- **频率**：护卫评估走僚机现有 AI tick（~0.5~1Hz），不每帧；守护者重指派带 1.5s 迟滞。
- 验收必跑 Sentinel + Lv5+ 满编队压测。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `Squad.escort_doctrine_enabled` | 该队是否吃护卫逻辑（玩家队默认 on / 精英 BOSS 队 on / 杂兵 off） | **新增字段**（squad.gd） |
| engaging_me 登记范围 | 攻击者对护卫编队成员登记（_maintains_engaging_me 判定） | 改（ai_controller 维护 engaging_me 的条件） |
| 目标评分加权 | ATTACKING_LEADER_BONUS + 近长机加权 | 改（target_selection / squad_coordination 评分函数，仅护卫编队僚机分支） |
| `scan_leader_rear` | 后半球威胁扫描 | 复用（已有） |
| 后半球守护者指派 | 选一机 + 占位拦截位 + 迟滞 | **新增**（squad_coordination，瞬态键于当前长机） |
| `leader_changed` 监听 | 切换时护卫重算 | 接信号（squad_coordination / ai_controller） |
| 跳过 manual_control 机 | 长机不护卫自己 | 改（护卫逻辑入口判定） |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **目标 2 反杀**：敌机咬长机时，护卫僚机优先扑向该敌机（即使另有更近的别的敌机）；威胁解除后退回就近交战。
- [ ] **目标 3 守后**：长机后半球出现威胁时，**恰一架**僚机飞到长机正后方占位拦截，不脱队远冲；威胁消失后归常态。其余僚机不全员回防（不死板）。
- [ ] **目标 1 护卫优先但不死板**：无威胁时护卫僚机仍会打身边顺手敌机，战场不变空。
- [ ] **范围**：玩家队 + F-47/Mother Goose 等精英队吃护卫逻辑；普通杂兵敌机/散兵编队行为与改动前一致（攻击杂兵不写 engaging_me）。
- [ ] **★ 切换自愈（Q2）**：玩家从 1 切到 3 → 护卫/守后立即以 3 号为中心；若切去的正是当前守护者，下个 tick 另一架自动补位；长机从不守护自己。反复切换无残留"守旧长机"的僚机。
- [ ] **engaging_me 定向**：攻击护卫编队成员（玩家队/精英队任意一员）都登记其 engaging_me；攻击杂兵不登记。
- [ ] 性能：威胁反查 O(1)、无新全场遍历；Sentinel + Lv5+ 满编队 FPS 掉幅 < 15。
- [ ] 已知 seam：与 squad-control-switching 的 leader/manual_control 状态机无竞态（切换瞬间不出现双守护者或零守护者卡死）。
- [ ] i18n：若加"covering / 守护中"无线电提示文本走 tr() 三语；纯行为无文本则免。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 威胁反查地基 ✅（2026-05-31）
- [x] `Squad.escort_doctrine_enabled` 字段；玩家队建队 on、F-47/Mother Goose 建队 on、杂兵队默认 off。
- [x] engaging_me 登记范围：`_maintains_engaging_me(target)`（team0 **OR** 护卫编队成员）；杂兵不维护。**加性扩展**保留 team0 既有技能反向索引。
- [x] 工具函数：`SquadCoordination.escort_target_bonus` 读 leader.engaging_me（O(1) has 命中）+ 近长机插值。

### 阶段 2 — 护卫目标评分 ✅（2026-05-31）
- [x] 护卫编队僚机分支（`is_escort_wingman`）：try_engage / reevaluate_target / scan_squad_nearby_enemy 叠加 ATTACKING_LEADER_BONUS + 近长机加权（§2.2）。
- [x] 复用 _is_target_already_squad_engaged 防多机抢同一威胁（scan_squad_nearby_enemy 内既有）。

### 阶段 3 — 后半球守护者
- [ ] scan_leader_rear 结果 → 指派一机为守护者 + 后方拦截位目标点（§3.3）。
- [ ] COVER_REASSIGN_HYSTERESIS 迟滞防抖。

### 阶段 4 — 切换交互 + 自愈
- [ ] 护卫/守后指派全部键于"当前长机"、每 tick 重算（禁持久属性）。
- [ ] 监听 leader_changed 重算；护卫逻辑跳过 manual_control 机。
- [ ] 与 squad-control-switching 联调切换边界（守护者被接管/长机切换/击落接管）。

### 阶段 5 — 验收调优
- [ ] 跑 §5 全部验收 + 切换交互 + 性能压测。
- [ ] 调 REAR_GUARD_SLOT_DIST_M / 各加权值至护卫体感自然。
- [ ] 更新 §7 锚点 + reference 索引 + known-seams 登记护卫×切换接缝。
- [ ] status → done，reconstruction_complete → true。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| engaging_me 维护范围 | `scripts/ai_controller.gd`（`_maintains_engaging_me` + _physics_process_impl 差量同步） |
| 反向索引字段 | `scripts/aircraft.gd`（engaging_me） |
| 护卫学说开关字段 | `scripts/squad.gd`（escort_doctrine_enabled）；建队处打开：`survivor_mode.gd:_spawn_starting_wingmen` / `ace_squad.gd` / `mother_goose_boss.gd` |
| 护卫目标评分 | `scripts/ai/squad_coordination.gd`（`is_escort_wingman` / `escort_target_bonus` / scan_squad_nearby_enemy）+ `scripts/ai/target_selection.gd`（try_engage / reevaluate_target） |
| 评分常量 | `scripts/ai_controller.gd`（ATTACKING_LEADER_BONUS / LEADER_PROXIMITY_BONUS_MAX） |
| 后半球指派 / 扫描（阶段 3 待做） | `scripts/ai/squad_coordination.gd`（scan_leader_rear 已定义未接线） |
| 切换交互 | 与 `scripts/survivor/survivor_mode.gd`（leader_changed）+ squad.gd |
| reference 索引行 | script-index.md / code-index.md AI 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 初稿（draft）：僚机护卫三目标（护长机/反杀攻击者/守后半球）。决策定型：护卫优先但不死板 / 指派一机占位守后 / **先只玩家队、架构留口**（接口不绑 team，开敌方仅需打开反查维护开关）。固化切换自愈（守护者瞬态键于当前长机 + leader_changed 重算 + 跳过 manual_control）与 engaging_me 定向扩展（本轮仅 team0 写入避免 O(N²)，留集中开关）。待 review → approved。 |
| 2026-05-31 | 1 | **派生代码 §6 阶段 1-2**（目标 1+2 + 切换自愈）：`Squad.escort_doctrine_enabled` 字段 + 玩家队/F-47/Mother Goose 建队打开；engaging_me 维护由 `team==0` **加性扩展**到 `_maintains_engaging_me`（team0 OR 护卫编队，保留 team0 技能反向索引）；`is_escort_wingman` + `escort_target_bonus` 接入 scan_squad_nearby_enemy / try_engage / reevaluate_target。**阶段 3-5 未做**（守后半球未接线、待 playtest 调参 ATTACKING_LEADER_BONUS=60/PROXIMITY=25）。详见 changelogs/2026-05-31-squad-ai-escort-1-2.md。 |
