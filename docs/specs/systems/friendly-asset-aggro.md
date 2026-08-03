---
id: friendly-asset-aggro
kind: system
status: done
schema_version: 1
spec_version: 4
owner: user + Codex
depends_on: [global-awareness-roe, target-engageability-selection, surface-attack-pass, airfield-liberation-zones, zone-reward-docking, aa-fire-awareness]
reconstruction_complete: true
---

# 玩家触发的友方据点牵连交战

> 玩家把空战带到已解放机场或友军航母附近时，敌军会在继续压迫玩家的同时，分出少量兵力拆除当地防空与航母；玩家飞远后，据点不会凭空吸引全图敌军。

## 1. 设计意图（Why）

- **体验目标**：堵住“躲在友军防空/航母旁边，让不会反击据点的 BOSS 或王牌被白白磨死”的安全解；据点仍然是有价值的战术地形，但玩家把敌人引过去会让据点承担可见代价。
- **不把友军援助改成陷阱**：敌军只在玩家主动把战斗带进据点区域时分流，而且分流有上限；主力仍继续攻击玩家。
- **Litmus 1 信息察觉**：导弹、机炮攻击跑、挂点爆炸与防空单位被逐个摧毁就是反馈，不增加不可见的纯数值 buff。
- **Litmus 6 AI 演戏**：敌军表现为“压玩家 + 拆支援节点”的多目标战术，而不是所有人无脑追尾或突然全员转头打建筑。
- **Litmus 7 BOSS 三维**：BOSS/王牌保留队长与核心角色对玩家的战术承诺，只允许僚机、舰载机、无人机或普通成员承担据点攻击。
- **Litmus 11 性能**：一份生存模式级 1 Hz 调度器复用战斗单位缓存；不加逐机子节点、不加每帧全场扫描。
- **反模式规避**：不做全图仇恨、不让机场/航母常驻吸怪、不以大幅加血掩盖选靶问题、不在共享层写生存模式分支。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 可牵连据点

| 据点种类 | 锚点 | 可被攻击的实体 | 进入半径 | 退出半径 | 退出宽限 |
|---|---|---|---:|---:|---:|
| 已解放机场 | 机场 DockPoint / 战区圆心 | 该机场生成的 SAM ×1、AA ×2 | **2000 px（4000 m）** | **2500 px（5000 m）** | **8.0 s** |
| 友军奖励航母 | 航母实时世界位置 | 当前存活 CIWS 挂点代理；弱点暴露后含弱点代理 | **2500 px（5000 m）** | **3000 px（6000 m）** | **8.0 s** |

- 只用**当前操控机**判进入/退出；僚机单独飞近不能远程开启据点仇恨。
- 机场补给点用尽后，ALLY 防空仍留场，因此该机场仍可再次进入 ACTIVE。
- 航母开始南撤后立即退出本机制，不再因玩家贴近而重新吸引攻击。
- 据点与其目标实体拥有稳定 `asset_group_id`；航母挂点代理通过母舰归组，不复制一份独立归属真相。

### 2.2 状态与节奏

| 字段 | 值 | 说明 |
|---|---:|---|
| 调度频率 | **1.0 Hz** | 每秒最多一次激活、配额、目标存活与释放检查 |
| ACTIVE 进入 | 玩家距锚点 `<= enter_radius` | 当次 tick 生效 |
| ACTIVE 保持 | 玩家距锚点 `< exit_radius` | 清零离场计时 |
| ACTIVE 退出 | 玩家连续 **8.0 s** 位于 `>= exit_radius` | 释放本机制持有的目标 |
| 敌机参与半径 | **6000 px（12000 m）** | 只从据点附近的敌机分流，不拉全图单位 |
| 分流最短保持 | 目标存活且据点 ACTIVE 时持续 | 不按 tick 换目标；目标死后下一次 tick 重分配 |

### 2.3 分流配额

令 `H` 为参与半径内、存活、有 AI、未撤离、可被本机制接管的敌方飞机数。

```text
H < 2: Q = 0
H >= 2: Q = min(3, max(1, floor(H / 3)))
```

| 附近敌机 H | 强制分流 Q | 至少留给玩家/原任务的数量 |
|---:|---:|---:|
| 0–1 | 0 | H |
| 2–5 | 1 | 1–4 |
| 6–8 | 2 | 4–6 |
| 9+ | 3 | H−3 |

- `Q` 是**所有重叠 ACTIVE 据点共享的总上限**，不会因机场与航母圈重叠而叠加抽干敌军。
- 选攻击者顺序：已经持有有效据点目标者 → 非队长/非主 BOSS 成员 → 距据点最近 → `squad_index` 较大者。
- 永不强制分流：当前操控机、友军、地面/舰船敌人、撤离/转场单位、主 BOSS 实体、敌方中队长，以及被更高优先级事件指令持有的飞机。
- 若排除后没有合格僚机/无人机，少分流或零分流，不牺牲 BOSS 演出与事件脚本正确性来凑配额。

### 2.4 目标分配

| 规则 | 数值/顺序 |
|---|---|
| 目标池 | ACTIVE 据点内所有存活目标实体 |
| 均摊 | 先选当前 `asset_attacker_count` 最少的目标 |
| 次级排序 | 攻击者距离较近者优先；再按稳定组内顺序 |
| 目标死亡 | 下一次 1 Hz tick 改派到同组下一目标；同组全灭则释放 |
| 玩家离场 | 退出宽限到期后释放；已发射导弹不凭空删除，继续自然飞行 |

机场按 SAM / AA 实体直接受击。航母船体保持锁定免疫，敌机与玩家一样攻击 CIWS 挂点代理；打掉足够挂点后再攻击暴露弱点，完整复用舰船位置伤害链。

### 2.5 目标来源优先级

AI 目标来源顺序调整为：

```text
SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED
```

| 来源 | 含义 |
|---|---|
| `ASSET` | 本机制的局部据点分流；可以临时盖过“持续追玩家”的 BOSS/猎手软指派 |
| `DIRECTIVE` | 明确剧本任务；高于据点分流，满足“除非特别说明”的例外 |
| `COMMANDED` | 玩家显式命令；保持全系统最高，不改语义 |

共享 AI 层只识别通用元数据和 `ASSET` 来源，不知道“生存模式、机场、航母”等概念。ACTIVE 状态、分流配额与归组全部由生存模式填入。

### 2.6 友军航母生存性基线（友军专属 300 HP）

友军航母生成时必须只对复制后的参数做友军专属覆写，避免污染敌方航母 BOSS 的共享基线。友军航母是可被饱和火力摧毁的临时支援点，不应成为玩家长期借用的无风险防空堡垒：

| 池/部件 | 数值 |
|---|---:|
| 友军航母船体总血量 | **300** |
| 敌方航母 BOSS 船体总血量（不变） | **1200** |
| CIWS 挂点 | **4 × 50 HP** |
| 弱点暴露阈值 | **2 个挂点被毁** |
| 弱点 HP | **280** |

船体与命中部件同时扣血。友军船体降到 `300 HP` 后，最短击沉路径改为直接耗尽船体，而不是“拆 2 个 CIWS → 打 280 HP 弱点”。忽略 CIWS 拦截并假设每发均穿透时：

| 敌弹档 | 单发伤害 | 最少穿透弹数 |
|---|---:|---:|
| V1 | 35 | 9 |
| V2 | 45 | 7 |
| V3 | 55 | 6 |
| V4 | 65 | 5 |
| V5 | 75 | 4 |
| V6 | 85 | 4 |
| V7 | 95 | 4 |
| V8 | 105 | 3 |

`300 HP` 仍可承受零星漏弹，但高等级导弹只需 3–4 发穿透即可击沉。CIWS 负责压制孤立来弹，密集齐射则会自然饱和；这个组合防止玩家把航母当成长期承伤单位。

这是 BOSS/装甲单位的显式例外：高血量由巨大舰体、可见挂点与弱点阶段表达，不违反普通飞机一击毙命规则。

### 2.7 航母 CIWS 拦截能力审计

| 字段 | 值 |
|---|---:|
| CIWS 数量 | **4** |
| 获取半径 | **1400 px（2800 m）**，以挂点计 |
| 重扫间隔 | **0.15 s** |
| 视觉射击间隔 | **0.030 s**（名义约 33 Hz；60 Hz 物理帧量化后约 30 Hz） |
| 真弹比例 | **每 2 发 1 发** |
| 有效真弹射速 | 名义 **16.7 Hz**；60 Hz 物理帧下约 **15 Hz / 座** |
| 真弹基础拦截伤害 | **10 / 发** |
| 散布 | **±5°** |
| 导弹命中半径 | **12 px** |
| 距离伤害 | 导弹距船心 `>=800 px` 为 0；`250–800 px` 线性增至满额；`<=250 px` 满额 |
| 单弹拦截 HP | V1–V8 = **40 / 45 / 55 / 60 / 65 / 75 / 82 / 90** |
| 并发纪律 | 一座 CIWS 同时拦一枚；同船其它 CIWS 不重复咬同一枚 |
| 再接敌冷却 | **0.6 s** |

满额距离内的名义有效 DPS 为 **150–167 / s / 座**；四座可并行处理最多四枚不同来袭弹，但不能把四座火力叠到同一枚上。它对孤立、正向来袭弹非常有效，对超过四枚的齐射、贴脸敌机优先级抢占、挂点被毁、JAM 与远端零伤区明显变弱。

代码常量离散模型的审计探针（非 Godot 场景验收）在“单座未受干扰、正向直飞、0–0.15 s 随机发现延迟、60 Hz”前提下，V1–V6 拦截约 100%，V7 约 99.9%，V8 约 98.7%。它证明 CIWS 不是装饰，但不能替代 §5 的真实场景齐射测试。

## 3. 行为与公式（How）

### 3.1 据点状态机

| 状态 | 触发 | 行为 |
|---|---|---|
| `DORMANT` | 默认 / 玩家远离 | 据点目标不参加敌方自主选靶；明确 `DIRECTIVE` 仍可攻击 |
| `ACTIVE` | 当前操控机进入半径 | 据点目标开放给自主选靶；1 Hz 调度器按 `Q` 分流敌机 |
| `EXIT_GRACE` | 玩家越过退出半径 | 维持原分流与开火；回圈立即恢复 ACTIVE |
| `DORMANT` | 连续离场 8 s | 释放所有 `ASSET` 目标；敌机恢复原 BOSS/评分/巡逻逻辑 |
| `EXHAUSTED` | 目标全毁 / 航母撤离 | 永久移出本局调度；不再分流 |

### 3.2 每秒调度伪代码

```text
for each registered asset_group:
    update DORMANT / ACTIVE / EXIT_GRACE from current_controlled_aircraft distance

active_targets = valid targets from all ACTIVE groups
eligible_attackers = hostile aircraft within 6000 px of any ACTIVE group
eligible_attackers -= leaders, primary bosses, transit/egress, higher-source holders
Q = quota(eligible_attackers.count)

keep valid existing ASSET assignments first
while assignments < Q and attackers/targets remain:
    attacker = nearest eligible nonleader, tie by larger squad_index
    target = least-assigned valid target, tie by distance then stable group order
    acquire_target(target, ASSET)

for old ASSET assignment not covered by ACTIVE groups:
    release_target(ASSET)
```

### 3.3 自主选靶硬门

```text
if target belongs to a registered friendly asset group:
    if group is DORMANT or EXHAUSTED:
        reject SCORED / BOSS / ASSET acquisition
        allow explicit DIRECTIVE / COMMANDED acquisition
    else:
        use the existing lock, envelope, visibility, overkill and surface-pass rules
```

不新增第二套攻击几何。目标一旦获得，飞机继续走既有地/水面 `SETUP → RUN → EGRESS` 攻击 pass、自动导弹/机炮开火和 AA/CIWS 中弹脱离规则。

### 3.4 BOSS / 王牌保护

- 分流只盖过 `BOSS` 级“追玩家”软指派，不盖过 `DIRECTIVE` 剧本动作。
- 主 BOSS 实体和中队长永不被强制分流；优先从僚机、舰载机、无人机、adds 中选。
- WRAITH / POLTERGEIST / 王牌支援中队至少保留队长与其余成员继续对玩家执行核心战术；若没有安全可分流成员，允许 `Q` 不满。
- 据点退出后，原事件脚本下一次维护 tick 可重新取得玩家目标；调度器不缓存玩家 Node 引用。

### 3.5 可观察与诊断

- 不增加 HUD 文本；玩家从敌机转入俯冲跑、锁定线/弹迹改向、SAM/AA/CIWS 爆炸直接读懂机制。
- EventLogger 记录：组进入/退出、`H/Q`、攻击者与目标、释放原因、据点各实体摧毁、航母 CIWS 拦截。
- 同一攻击者/目标状态未变化时不重复刷日志。

## 4. 结构与组成（Structure）

- 一份生存模式持有的 `FriendlyAssetAggro` 状态对象：注册机场/航母组、1 Hz tick、配额与分配账本；自身不挂 `_process`。
- 机场解放接线：生成 ALLY SAM/AA 时把三者与机场锚登记为同组。
- 友军航母接线：生成时登记母舰；航母挂点/弱点代理由归组 helper 动态解析。
- AI 目标仲裁：新增 `ASSET` 来源及优先级；通用元数据硬门保证非 ACTIVE 时不自主攻击。
- 目标选择与武器：复用现有雷达锁、可命中性评分、surface attack pass、导弹与机炮伤害；不复制算法。
- 清理：机场单位全灭、航母撤离/沉没、场景退出时注销；静态/跨局状态必须 reset。

## 5. 验收标准（Acceptance / Litmus）

- [x] 玩家远离已解放机场与友军航母时，普通敌机、猎手、BOSS/王牌不会主动改道攻击这些据点；明确事件指令仍可绕过。
- [x] 玩家进入机场 2000 px 圈后，附近 5 架敌机中稳定有 1 架攻击 SAM/AA，其余继续攻击玩家或执行原任务；不会全员转头。
- [x] 玩家进入航母 2500 px 圈后，WRAITH 四机或王牌五机中最多分出 1 名非队长成员攻击 CIWS 挂点；队长与核心战术仍正常运行。
- [x] 6–8 架附近敌机时分流 2 架，9+ 时最多 3 架；两个 ACTIVE 据点重叠也不超过总配额。
- [x] 玩家离开退出半径并持续 8 s 后，所有 `ASSET` 目标释放，敌机恢复玩家/BOSS/巡逻目标；边界来回穿越不按秒抖动。
- [x] 航母目标按 CIWS 挂点 → 暴露弱点推进，船体中心仍不可锁；挂点销毁后无 freed instance / 残留 combat_target。
- [x] 友军航母使用专属 300 船体；敌方航母 BOSS 仍为 1200，共享资源原值不被友军覆写污染。
- [x] 单枚任意 V1–V8 导弹不能击沉满血友军航母；V8 理论至少需要 3 发穿透。
- [x] CIWS 实景 bench：V1/V4/V8 各做 100 次孤立正向来袭，记录拦截率；再做 2/4/5/8 枚同批齐射，证明“孤弹有效、超过四枚可饱和”，不得只用概率替身。
- [x] 持续攻击 playtest：孤立单机的串行来弹主要由 CIWS 处理；多机同时攻击、密集齐射或 CIWS 被分散时，友军航母存在快速沉没风险。
- [x] BOSS/王牌回归：WRAITH、POLTERGEIST、Mother Goose、CSG 舰载机、MARATHON 各验证一次；主 BOSS/队长不被分流，离场后战术恢复。
- [x] 目标来源回归：`SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED` 全部抢占/拒绝/释放组合有断言。
- [x] 性能：调度器 1 Hz、每 tick 至多一次 `CombatUnit.all_units` 线性扫描；Sentinel + Lv5+ FPS 不低于 60，Lv8+ 拥挤场景无尖峰。
- [x] `verify_player_ref_holders.py` 通过；调度器只在 tick 时读当前操控机，不成为漏登记的持有者。
- [x] `verify_doc_anchors.py` 通过；新增/修改函数同步 script-index 与 code-index。
- [x] i18n：本机制无新增玩家文本；若实现期增加提示，必须走 `tr()` 并补三语。

### 2026-08-01 验收结果

| Bench | 结果 | 关键结论 |
|---|---:|---|
| `friendly_asset_aggro` | **27 / 27** | DORMANT/ACTIVE、H→Q、6000 px 参与圈、重叠组、8 s 退出、300/1200 HP 隔离通过 |
| `target_arb` | **25 / 25** | 五级来源抢占、DORMANT 硬门、DIRECTIVE 例外通过 |
| `ciws_intercept` | **14 / 14** | V1/V4 孤弹 100%，V8 孤弹 88%；V4 八枚齐射穿透 41/160（25.6%） |
| `target_sel` / `surface_pass` | **35 / 35**、**32 / 32** | 自主选靶与对地/对舰攻击链无回归 |
| BOSS / 王牌 / 舰队相关五组 | **193 / 193** | POLTERGEIST、Lancer/Marathon、Wraith/CSG、BOSS 阶段与舰队运动通过 |
| `ace_tier` | **55 通过 / 1 个外部失败** | 王牌战斗、轮换、TTK 全绿；仅生涯落盘重读失败 |
| `stress_40`（10 s） | **通过** | 32 单位；最后 1.01 s 为 146 帧（约 145 fps），AI tick 76 µs/帧，Aircraft physics 428 µs/帧 |

全量 `all` 回归门已执行；本机制与直接依赖全部通过。共享工作树总门仍有 27 个
**非本机制**失败：`ace_tier` 的生涯落盘 1、`career_archive` 21、`meta_shop` 4、
`spawn_pool` 1。它们不经过设施归组、ASSET 仲裁、航母 HP 或 CIWS 路径，作为仓库级
提交阻塞单独保留，未在本任务中越界修改。

提交前静态门：`verify_player_ref_holders.py`、本 spec、Script Index 与本功能
Code Index 锚点均通过，`git diff --check` 通过。全仓 Code Index 仍有 63 个来自
其它并行改动的旧锚点；本功能两行均不在腐烂清单，未跨任务批量改写。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 状态对象与注册

- [x] 新建 `FriendlyAssetAggro`，实现组注册、进入/退出迟滞、1 Hz tick、清理与日志。
- [x] 机场 ALLY 防空生成后登记同组；友军航母生成/撤离/沉没时登记与注销。
- [x] 用 helper 把航母 `MountTarget` 解析回母舰组，覆盖动态弱点代理。

### 阶段 2 — 目标仲裁与硬门

- [x] 新增 `ASSET` 目标来源并更新优先级、名字表与仲裁测试。
- [x] 共享层加入通用 asset-group ACTIVE 硬门；`DIRECTIVE/COMMANDED` 绕过。
- [x] normal/BOSS/ace 分流过滤与总配额落地，保持现有有效 assignment 不抖动。

### 阶段 3 — 武器与攻击跑回归

- [x] GroundUnit、MountTarget、弱点代理继续走既有 surface attack pass；本机制不新增攻击几何。
- [x] 导弹、机炮、超杀记账、目标释放和挂点销毁链不增加武器特判。
- [x] 修正航母脚本内与资源不一致的旧注释，数值权威保持本 spec。

### 阶段 4 — Bench 与实景验收

- [x] 新增资产仇恨无头测试：激活、迟滞、配额、优先级、重叠组、销毁重派。
- [x] 新增 CIWS 真实弹道 bench：孤弹与 2/4/5/8 齐射，输出型号/拦截/命中/穿透统计。
- [x] 跑目标选择、surface pass、BOSS/王牌与全量回归门。
- [x] 跑生存 playtest 与 Sentinel/Lv5+、Lv8+ 压测，再填 §7 与状态 `done`。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 资产牵连调度 | `scripts/survivor/friendly_asset_aggro.gd` · `tick` |
| 生存模式注册 | `scripts/survivor/survivor_mode.gd` · `_deploy_airfield_ally_gradual`、`_summon_reward_carrier` |
| AI 目标仲裁 | `scripts/ai_controller.gd` · `TargetSource`、`acquire_target`、`get_target_source` |
| 自主目标选择 | `scripts/ai/target_selection.gd` |
| 通用设施 meta | `scripts/combat_unit.gd` · `META_FRIENDLY_ASSET_GROUP` |
| 航母挂点代理 | `scripts/naval/mount_target.gd` · `_ready` |
| 航母与 CIWS 参数 | `resources/naval/carrier_cv.tres`、`scripts/naval/naval_weapons.gd` · `CIWS_ACQUIRE_INTERVAL` |
| 测试 | `scripts/tests/test_friendly_asset_aggro.gd` · `run`、`scripts/tests/test_ciws_intercept.gd` · `run` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-01 | 4 | Godot 原生启动问题修复后完成验收：核心三组 66/66，目标/对面/BOSS/舰队相关回归通过，`stress_40` 约 145 headless fps；CIWS 实测孤弹有效、八枚齐射明显饱和。功能状态转 `done`；仓库全量门的 27 个无关存档/商店/刷怪池失败另行保留。 |
| 2026-07-31 | 3 | 修复运行时错误：设施调度器调用了遗漏实现的公开 `get_target_source()`；AIController 现通过只读 getter 返回当前有效目标来源。 |
| 2026-07-31 | 3 | 用户批准后落地调度、ASSET 仲裁、ACTIVE 硬门、机场/航母注册、友军 300 HP 覆写及两组 bench。工作区 idle 后仅经 `bench/run.cmd` 启动验证，但 Steam Godot 4.7.1 在 GDScript bench 前原生 `signal 11`；遵守协调要求未重试，保持 `in-progress`。 |
| 2026-07-30 | 2 | 友军航母船体改为专属 300 HP；敌方航母 BOSS 保持 1200；重算 V1–V8 理论最低穿透数。 |
| 2026-07-30 | 1 | 初稿：局部激活、限额分流、BOSS/王牌保护、友军航母生存性与 CIWS 审计。 |
