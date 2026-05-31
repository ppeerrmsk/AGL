---
id: flight-model-realism
kind: system
status: in-progress     # 代码已派生并通过 Godot 加载；待用户手感验收 + STRUCT_BLEED_FACTOR 调参
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [bloodlust]
reconstruction_complete: false
---

# 飞行模型拟真化 —— 双层 G（持续 vs 瞬时）+ 能量自限

> 玩家视角：飞机能"猛拉一下"打出极高的瞬时转弯率，但拉得越狠掉速越快，维持不住就被速度拽回稳态——真实空战那种"瞬时拉得动、能量维持不住、一硬转就掉到角点"的手感。这是 RTS 方向第一步：让单机操控更有重量、更拟真。

## 1. 设计意图（Why）

AGL 正在从"单机吸血鬼幸存者"向"RTS 小队空战"转向。第一步先把**基础飞行性能拟真化**，给后续小队战术一个有重量、可预期的物理底座。

**关键认知（推翻了一个常见误解）**：现实战斗机的"笨重"**不在滚转**。F-16 实际滚转率 240–324°/s ≈ 4.2–5.65 rad/s（游戏现值 4.8，已贴近真实）。真实的"沉"在**转弯能量**：F-16 持续转弯率仅 ~22.5°/s，但瞬时靠拉到 9G 能冲很高；角点速度 330–440 KCAS ≈ 610–815 km/h。所以拟真的正确旋钮是**持续 G vs 瞬时 G 的分离 + 拉 G 掉速的能量循环**，不是把滚转调慢。

**体验目标**：
- 玩家急转时能短暂吃到 `max_g_structural` 的瞬时高转弯率（"猛拉一下"有效），但速度会快速流失，几秒内被拽回 `max_g` 持续区——产生"能量管理"的紧张感。
- 不同机型的"持续 vs 瞬时"差距成为可感知的机型性格（F-16 持续好，截击机瞬时猛但掉速狠）。
- 全程不破坏现有导弹/机炮战术手感（零 buff、零硬转时行为与现状一致）。

**🚫 头号硬约束（不可违背）——转弯不得自陷失速**：
玩家**只能操控飞机"去哪儿"，无法精确控速/控杆**。因此**转弯导致的能量流失绝不允许把飞机拖进不可恢复的失速死亡螺旋**（硬转→掉速→失速→速度再也提不起来）。这是历史翻车点（用户明确反馈"很不爽"），也是现有代码的既存洞：`update_speed` 的 g_drag 掉速发生在速度地板钳制**之后**，能把速度拽到失速线以下。
本 spec 的能量自限**必须设地板**：拉 G 掉速最多把速度拽到**角点速度（corner speed）**就停住，绝不更低。角点速度按定义即"能拉满持续 G 的最低速度"，settle 在此 = 满持续 G 最优转弯 + 离失速线有安全余量。**瞬时拉得动 → 掉到角点 → 卡住 → 永不失速。** 本改动顺带修掉既存的 g_drag 越界洞（直线慢飞失速不受影响，只堵"转弯把自己转到失速"）。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 2（笨重 + 延迟快感）**：✅ 强化。能量自限让"硬转→掉速→需要重新积累能量"成为新的延迟来源，命中仍是瞬时爽点。
- **原则 3（信息察觉优先）**：✅ 改动必须**可感知**——硬转后明显掉速、转弯率明显先高后回落。禁止做成玩家说不出差别的暗调。验收按此卡。
- **原则 4（数值区间）**：✅ 不新增超区间数值；只改 G/掉速的**作用方式**与少量离群 .tres 值。
- **原则 6（敌机性能 = 现实 × 平衡中间值）**：✅ 机型数据只修"明显离谱"的离群值（如 A-10 max_g 9.5），不照抄、不全量重填。
- **原则 11（60 FPS）**：✅ 纯标量公式，无新节点/无新每帧扫描，零性能风险。

**反模式规避**：
- ❌ 不引入耐力池（pilot_stamina）——当年因"响应不确定"被删（`a1c073e`，2026-04-28）。本 spec 用**能量自限**（拉 G 掉速）代替计时器/资源池，无持久状态。
- ❌ **不允许"转弯把自己转到失速、能量耗光提不起速"**（见上方头号硬约束）——能量自限必须以角点速度为地板。
- ❌ 不调慢 roll_rate（那会更不拟真）。
- ❌ 不在 update_speed/update_bank 物理 tick 里散点叠 buff——双层 G 走 effective_*() accessor（SEAM-001）。

## 2. 数据定义（What —— 权威源）

### 2.1 新增/复用常量

| 常量 | 值 | 说明 |
|---|---|---|
| `G_DRAG_GLOBAL_MULT` | 0.4 | 既有：基础拉 G 掉速全局系数（不动） |
| `STRUCT_BLEED_FACTOR` | 6.0 | **新增**：超过持续 max_g 的部分的额外掉速系数（m/s² per G·s）。越大→结构 G 越维持不住 |
| 基础掉速公式 | `(g_load−1)×g_drag_factor×0.4×(1−alt_f×0.30)` | 既有，不动（`g_drag_factor` 默认 3.0） |
| 额外结构掉速 | `max(g_load − sustained_max_g, 0)×STRUCT_BLEED_FACTOR×(1−alt_f×0.30)` | **新增**，叠加在基础掉速之上 |
| **角点速度地板** | `corner_speed_kmh(ac)` | **新增硬约束**：拉 G 掉速（base+struct 合计）绝不把速度拽到此值以下。堵死"转弯自陷失速"死亡螺旋 |

> `STRUCT_BLEED_FACTOR = 6.0` 是初始提案值，需在验收阶段实测调参：目标是"猛拉到结构 G 后约 1.5–2.5 秒内速度掉到角点速度附近，自然settle到持续 G"。调参记录写入 §8。

### 2.2 字段语义重定义（AircraftParams，字段本身已存在，不新增字段）

| 字段 | 旧语义 | 新语义 | F-16 值 |
|---|---|---|---|
| `max_g` | 唯一 G 上限（structural 未被代码使用） | **持续 G**：稳态转弯、AI 战术规划、corner speed、稳态 bank cap 的依据 | 9.0（×档案 +1.0 → 10.0） |
| `max_g_structural` | 死字段（耐力系统删除后无人读） | **瞬时 G**：物理 bank cap 的瞬时上限，硬转可短暂触达，靠能量自限拽回 | 12.0 |
| `roll_rate` | 滚转速率 | 不变（已贴近真实，仅清离群值） | 4.0（×档案 1.2 → 4.8） |

### 2.3 roll_rate 离群值清理（只动"明显不合理"的）

> 原则：战机 roll_rate 一律**不动**（已拟真）。仅复核非战机类是否合理。下表为**复核结论**，绝大多数维持现状。

| 机型 | 现值 | 处置 | 理由 |
|---|---|---|---|
| 所有有人战机（F-16/MiG/Su/F-14/A-7/F-4…） | 2.4–5.5 | **不动** | 真实滚转本就快 |
| 无人机（uav_railgun 7.0 / uav_mqx 6.0 / mqx…） | 5.0–7.0 | **不动** | 无飞行员 G 限制，高滚转是设计语言 |
| 轰炸机/大机体（Tu-160 0.8 / mother_goose 0.4） | <1.0 | **不动** | 大惯量低滚转，合理 |
| 直升机（CH-47 1.2 / AH-64 3.0） | 1.2–3.0 | **不动** | 旋翼机定位 |

→ **结论：roll_rate 本轮无需改动任何 .tres**（"只清离群值"复核后为空集；如实测发现个别异常再补）。

### 2.4 机型数据离群值修正（只修"明显离谱"的 max_g）

| 机型 | 字段 | 现值 | 提案值 | 真实参考 / 理由 |
|---|---|---|---|---|
| A-10（playable_a10_base / _drone） | `max_g` | 9.5 | **7.0** | 真实 A-10 ~6.5G；攻击机不该有战机级持续 G。structural 12.0→**9.0** |
| loyal_wingman_drone | `max_g` | 18.0 | **不动** | 已有注释说明是 chase 追随需要的折中，非离谱 |
| 其余战机 | — | — | **不动** | 落在原则 6 "现实×平衡"区间内，非离谱 |

> 本轮**只列已确认离谱的 A-10**。其余机型逐个核对属于"全量真实化"，超出本步范围（用户决策：只修明显离谱的）。后续若铺开，另起 spec。

## 3. 行为与公式（How）

### 3.1 双层 G 注入点（accessor 层，SEAM-001）

新增一个 accessor，与 `effective_max_g` 并列：

```
effective_max_g(ac)            # = 持续 G（不变）：max_g × (cloud/lock_panic/bloodlust 修饰)
                               #   消费者：corner_speed、AI Situation、稳态 bank cap、update_bank 的 sustained 段
effective_max_g_instant(ac)    # 新增 = 瞬时 G：max_g_structural × (与上面相同的修饰乘数)
                               #   消费者：仅 max_bank_angle 的 g_limited_bank（物理瞬时上限）
```

**关键约定**：`effective_max_g_instant` 复用 `effective_max_g` 的**同一套 buff 乘数**（cloud ×0.9 / lock_panic / bloodlust ×1.2），只是基数换成 `max_g_structural`。保证 buff 对持续/瞬时一视同仁，不产生第二处散点注入。

### 3.2 物理 bank cap 改动

`max_bank_angle` 的 G 限制段：
```
旧: g_limited_bank = acos(1 / effective_max_g(ac))          # 持续 G 当瞬时上限
新: g_limited_bank = acos(1 / effective_max_g_instant(ac))  # 瞬时 G 当瞬时上限
```
速度限制段（speed_limited_bank）**不变**——它本来就是防失速的物理钳制，与能量自限协同：拉到结构 G → 掉速 → speed_limited_bank 收紧 → bank 被迫降回持续区。

`update_bank` 内既有的"combat sustained 段"（in_combat 时把 turn_g 在 0.7×max_g..max_g 间按 heading_diff 插值，再由 tactical_aggression 拉到 effective_max_g）**保留不变**：它定义的是 AI 战斗中"愿意持续吃多少 G"，依然以**持续 max_g** 为天花板。只有当 aggression→1（拼死硬转）时才逼近 effective_max_g（持续）。瞬时结构 G 不进入 AI 的稳态规划，只在物理 cap 层对所有单位开放。

### 3.3 能量自限（核心，替代耐力池）

`update_speed` 的掉速段，在既有基础掉速之后**追加**一道结构超 G 掉速：

```
# 既有（不动）：
alt_f      = clamp(altitude / 15000, 0, 1)
g_drag     = g_drag_factor × 0.4 × (1 − alt_f×0.30)
base_loss  = max(g_load − 1, 0) × g_drag

# 新增：超过持续 max_g 的部分，额外狠掉速
sustained  = effective_max_g(ac)                       # 持续 G
over_g     = max(g_load − sustained, 0)
struct_loss = over_g × STRUCT_BLEED_FACTOR × (1 − alt_f×0.30)

# 🚫 头号硬约束：拉 G 掉速最多拽到角点速度地板，绝不更低（转弯不得自陷失速）
g_loss_total   = base_loss + struct_loss
no_stall_floor = corner_speed_kmh(ac) / 3.6           # m/s，角点速度地板
allowed_loss   = max(speed − no_stall_floor, 0.0)     # 已在地板以下时 = 0，不再 g-bleed
speed -= min(g_loss_total × delta, allowed_loss)
```

> 注意：地板**只钳制 G 引致的掉速**（转弯能量流失），不影响直线飞行时按 target_speed 正常减速到巡航/失速——直线慢飞行为不变，只堵"转弯把自己转到失速"。

**自限闭环**（无计时器、无资源池、有失速地板）：
1. 玩家/AI 猛拉 → bank 冲向 structural-G 对应角 → `g_load > sustained`
2. `struct_loss` 触发，速度快速流失 **直到角点速度地板**
3. 掉到角点速度 → `allowed_loss` 归零，G 掉速停止；此速度恰好能拉满持续 G
4. bank/speed_limited 自然 settle 到持续 G 稳态最优转弯
5. 全程速度 ≥ 角点速度 > 失速线 → **永不因转弯失速**

样例（F-16，海平面，sustained=10、structural=12）：角点速度 = 220×1.2×√10 ≈ 835 km/h（失速线 1G 仅 220、10G 时 ~553）。
瞬间 g_load=12 时 `struct_loss=(12−10)×6.0×1.0=12 m/s²` + base_loss≈(12−1)×3.0×0.4=13.2 → 合计 ~25 m/s²（每秒掉 ~90 km/h）。从顶速 2205 硬转，约 1.5–2s 掉向 835 后**被地板卡住**，settle 在满持续 10G 最优转弯。能量代价巨大（2205→835）但绝不触失速。

### 3.4 零改动保证（回归基线）

- 不硬转时 `g_load ≤ sustained` → `struct_loss = 0` → 速度行为与现状逐位一致。
- AI 走 `effective_max_g`（持续）与 `corner_speed`/Situation 不变 → 现有导弹/机炮战术手感不变。
- roll_rate / 失速公式 pow(G,0.4) / corner_speed 公式 **全部不动**。

### 3.5 高度 ↔ 能量耦合（现状，已实现；本节为补写存档，不改行为）

> 这套位能/动能互换 + 高度机动加成**早已实现**，是与 §3.3 能量自限同一个能量系统。补写进 spec 使模型完整可重建，并明确它与新失速地板的关系。第 2 点（爬升对 G）保持**现有的间接耦合**，本轮不新增专门机制。

**(A) 位能 ↔ 动能互换（PE↔KE）**——俯冲加速 / 爬升耗速：
```
spd           = max(speed, 10)
gravity_effect = GRAVITY × vertical_speed / spd × PE_KE_BOOST   # PE_KE_BOOST = 2.5
speed        -= gravity_effect × delta
```
- 俯冲（`vertical_speed < 0`）→ gravity_effect<0 → **加速**（高处俯冲换速度）。
- 爬升（`vertical_speed > 0`）→ **掉速**（拿速度换高度）。
- **施加顺序在 §3.3 g-loss 地板之后** → 俯冲冲速**不受地板限制、完整保留**（俯冲甚至可短暂顶破 q-limit）。

**(B) 爬升的目标速度惩罚**（在 update_speed 设 target 时）：
```
vs_norm  = clamp(vertical_speed / climb_rate_max, −1, 1)
target_ms ×= 1.0 − vs_norm × 0.10        # 满爬升率时目标速度 −10%
```

**(C) 爬升 → 高度**（update_altitude）：
- `vertical_speed → altitude`；爬升率 = `clamp(alt_diff×gain, −max_climb, +max_climb)`，`max_climb = climb_rate_max × min(alt_mult,1.3)`。
- **能量门控（防爬升失速）**：爬升且 `speed − stall_at_g < 50 m/s` 时，`climb_authority = (speed−stall_at_g)/50`，`target_vs ×= climb_authority` → 速度不够时爬不动，**爬升也不会自陷失速**（与 §3.3 转弯地板共同构成"任何操作都不死亡螺旋"）。

**(D) 高度 → 机动加成**（`alt_factor = clamp(altitude/15000, 0, 1)`，注意是**高度值**不是爬升动作）：
- `roll_rate ×= 1 + alt_factor × 0.30`（高空滚转 +30%）
- `g_drag ×= 1 − alt_factor × 0.30`（高空拉 G 掉速 −30%，能量更耐用）
- 抽象表达"高空机动余量大"（2D 顶视无法渲染垂直机动，用此代偿）。

**(E) 爬升 → G（第 2 点）**：**无专门机制，间接耦合**——爬升经 (A)(B) 耗速 → 速度降 → `speed_limited_bank` 收紧 → 可用 G 自然下降。本轮维持现状。

> ⚠️ 实现注记：draw_predicted_path 有一份 (A)(C)(D) 的**并行镜像**（step_altitude / step_speed），任何改动须两处同步，否则预测线与实际轨迹撕裂（见 known-seams）。本轮 §3 不改 (A)~(E) 行为，仅 §3.3 新增地板——地板逻辑也须在预测镜像里同步。

## 4. 结构与组成（Structure）

| 组成 | 角色 |
|---|---|
| `effective_max_g`（持续，既有） | AI 战术规划 + 稳态 bank + corner speed 的依据 |
| `effective_max_g_instant`（瞬时，新增 accessor） | 仅 max_bank_angle 物理瞬时上限消费 |
| `STRUCT_BLEED_FACTOR`（新增常量） | 结构超 G 的能量惩罚强度，唯一调参旋钮 |
| update_speed 掉速段（既有 + 追加一段） | 能量自限闭环的执行处 |
| AircraftParams.max_g_structural（既有字段，复活语义） | 每机型瞬时 G 上限数据源 |
| A-10 .tres max_g 修正（数据） | 唯一确认的离群值修正 |

注入类别（按 CLAUDE.md「加机动性 buff 规范」）：本改动属**模型层**而非 buff，但新 accessor `effective_max_g_instant` 必须遵守同款 SEAM-001 约定——任何未来 G 类 buff 同时透传持续与瞬时。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **🚫 头号硬约束：转弯绝不自陷失速**。从顶速对地图连续点反向大角度做最硬的转弯（玩家最暴力的操作），速度只会掉到角点速度附近并卡住，**永不触发 is_stalled**，转完能正常重新加速。反复横跳硬转也不进死亡螺旋。这是 must-pass，不过则回退。
- [ ] **可感知（原则 3）**：玩家手动急转（大角度点击）时，EventLogger 可见 g_load 短暂冲到接近 max_g_structural，随后速度明显下滑、g_load 回落到 max_g 附近、速度在角点速度处止跌。肉眼能说出"硬转会掉速但不会失速"。
- [ ] **瞬时转弯率提升可见**：同一硬转，改动后入弯瞬间转弯率高于改动前（structural > sustained 的体现），但圈打不满（掉速拽回）。
- [ ] **稳态不变**：温和转弯（g_load ≤ max_g）下速度/转弯/失速与改动前逐位一致（回归基线）。
- [ ] **AI 不失明（SEAM-001）**：升满 BLOODLUST/lock_panic，EventLogger 看 AI 的 target G 与瞬时 bank cap 同步抬升（持续/瞬时同被 buff 乘）。
- [ ] **调参收敛**：STRUCT_BLEED_FACTOR 调到"硬转后 1.5–2.5s settle 回角点速度"，记录最终值入 §8。
- [ ] **A-10 数据**：A-10 持续 G 体感明显弱于战机（不再能像战机一样硬转）。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（纯标量，预期 0 影响）。
- [ ] 已知 seam：vapor_dodge × HIGH 档 target_altitude 翻车点（known-seams）未被掉速改动二次触发。
- [ ] i18n：本改动无新玩家可见文本（纯物理）。若后续给 HUD 加"过载/能量"提示，再补 tr()。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 双层 G accessor
- [ ] 在 aircraft_physics.gd 新增 `effective_max_g_instant(ac)`：基数 `max_g_structural`，复用 effective_max_g 的 cloud/lock_panic/bloodlust 乘数（抽出共享乘数 helper 或内联复制，注释标 SEAM-001）。
- [ ] `max_bank_angle` 的 g_limited_bank 改用 `effective_max_g_instant`。
- [ ] 确认 update_bank 的 combat sustained 段仍引用 `effective_max_g`（持续），不误改。

### 阶段 2 — 能量自限 + 失速地板
- [ ] update_speed 掉速段追加 struct_loss（公式见 §3.3），常量 STRUCT_BLEED_FACTOR=6.0。
- [ ] **加角点速度地板**：把 G 引致掉速（base_loss+struct_loss 合计）钳到不低于 corner_speed（公式见 §3.3）。这同时修掉既存的 g_drag 越界洞。
- [ ] 验证零硬转时 struct_loss=0、且地板不影响直线减速（回归基线）。
- [ ] **专项验证头号硬约束**：顶速连续反向硬转，确认 is_stalled 始终不触发、速度在角点止跌。

### 阶段 3 — 数据修正
- [ ] playable_a10_base.tres / playable_a10_drone.tres：max_g 9.5→7.0，max_g_structural 12.0→9.0。
- [ ] roll_rate：本轮不动（§2.3 复核为空集），如实测异常再补。

### 阶段 4 — 调参与验收
- [ ] 运行调 STRUCT_BLEED_FACTOR 至 §5 收敛目标，记录入 §8。
- [ ] 跑 §5 全部验收项，性能压测。
- [ ] 更新 §7 锚点 + reference 索引（script-index / code-index 的 effective_max_g_instant 行）。
- [ ] status → done，reconstruction_complete → true。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 双层 G accessor（_g_buff_mult / effective_max_g / effective_max_g_instant）| `scripts/aircraft/aircraft_physics.gd` |
| bank cap（max_bank_angle 用 instant）| `scripts/aircraft/aircraft_physics.gd` |
| 能量自限 + 失速地板（update_speed）| `scripts/aircraft/aircraft_physics.gd` |
| 预测镜像同步（_predict_inline_planner）| `scripts/aircraft/aircraft_physics.gd` |
| max_g / max_g_structural 字段 | `scripts/aircraft_params.gd`（AircraftParams） |
| A-10 数据 | `resources/playable_a10_base.tres` / `resources/playable_a10_drone.tres` |
| reference 索引行 | script-index.md / code-index.md 的 effective_*() 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 初稿（draft）：双层 G + 能量自限设计定型；roll_rate 复核为不动；A-10 max_g 离群修正。待用户 review → approved。 |
| 2026-05-30 | 1 | 草稿修订：加入**头号硬约束「转弯不得自陷失速」**（用户反馈历史翻车）——能量自限以角点速度为地板，瞬时掉速最多拽到角点止跌、永不失速；顺带修既存 g_drag 越界洞。 |
| 2026-05-30 | 1 | 代码派生完成：_g_buff_mult 共享乘数 + effective_max_g(持续)/effective_max_g_instant(瞬时结构) 双层 accessor；max_bank_angle 改用瞬时 G；update_speed 追加 struct_loss 能量自限 + 角点速度失速地板；预测镜像同步；A-10 max_g 9.5→7/structural 12→9 + 清 stamina 死字段。Godot 加载通过。待用户手感验收 + STRUCT_BLEED_FACTOR 调参。 |
| 2026-05-30 | 1 | 补写 §3.5 高度↔能量耦合（PE↔KE 俯冲加速/爬升耗速、爬升目标速度惩罚、爬升→高度、高度→机动加成、爬升→G 的间接耦合）——均为现状存档，不改行为；明确俯冲加速不受地板限制、爬升被 climb_authority 门控同样不失速。 |
