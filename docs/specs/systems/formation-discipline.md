---
id: formation-discipline
kind: system
status: in-progress
schema_version: 1
spec_version: 5
owner: 设计/用户
depends_on: [command-wheel, squad-cohesion, weapon-employment-doctrine]
reconstruction_complete: false
---

# 阵型纪律与齐射（允许阵型分散开关）

> 队级开关：**自由散开**（各自机动、多角度包围输出）vs **紧密队形**（整队保持阵型一起进入、一起齐射、一起拉开）。给"四机齐射一波再整队脱离"的编队美学一个真实可玩的载体。

## 1. 设计意图（Why）

- **体验目标**：俯视视角下编队全程可见，"整队压上→四机齐射→整队冷转拉开"是这个游戏最有观赏性的画面之一；同时给玩家一个真实的战术选择——爆发齐射 vs 持续包围。
- **战术取舍（两个模式都必须有存在理由）**：
  - **紧密队形**：一波齐射饱和目标的 flare/拦截等防御（爆发穿透）；互相掩护（护卫 flare 半径内）；玩家只需一次机动决策。代价：包围角度归零、目标转冷对全队同时生效、可被拖着走、范围威胁一锅端。
  - **自由散开**：多角度持续输出，目标往哪转都有人有射击解；抗打击（不会一波团灭）。代价：个体暴露、难以整队脱离、火力时间上摊平。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - "物理优雅"——僚机靠既有编队跟随（真实 bank/盘旋归位）保持槽位，齐射是**开火时机门控**，不伪造位置/曲线（[[feedback_formation_physical_elegance]]）。
  - "转弯不得自陷失速"——整队 EGRESS 冷转沿用角点速度地板。
- **反模式规避**：不新增编队系统——紧密模式 = 既有编队跟随 + 抑制个体脱队交战 + 齐射门控三件事，零新阵型代码；FREE 模式 = 现状零改动。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 开关

| 字段 | 值 | 说明 |
|---|---|---|
| `formation_discipline` | `enum { FREE, TIGHT }`，默认 `FREE`（=现状） | 队级状态。FREE=允许分散（各自交战/包围）；TIGHT=紧密队形（整队机动+齐射） |
| 入口 | **攻击轮盘右槽**（[[command-wheel]]）+ HUD 战术栏第 6 个 toggle | 双入口同源镜像；从小队命令轮盘移入攻击轮盘——它决定"怎么打"，归攻击语境 |

### 2.2 齐射参数（并入 `CommandWheelParams` 或独立 `FormationDisciplineParams`，.tres 可调）

| 字段 | 默认值 | 说明 |
|---|---|---|
| `volley_window_s` | 1.5 s | 齐射窗口时长：长机满足开火条件后开窗，窗口内有解僚机各自释放 |
| `volley_lock_lead_mult` | 1.3 | 锁定提前量：整队进入 `齐射距离 × 1.3` 时全员开始锁定目标，保证到位时锁是热的 |
| 齐射距离 | 长机当选武器最佳包络带（走 [[weapon-employment-doctrine]] 竞选，不写死） | 混装 loadout：僚机在该距离用自己最好的有效武器；无有效武器则本轮不发 |
| `egress_dist_mult` | 1.5（沿用 STANDOFF 循环） | 齐射后整队拉开至包络带外沿 × 1.5 再回转 |
| 补射 | **禁止** | 窗口关闭时未完成锁定/无解的僚机不追射，跟队 EGRESS——纪律优先于个体输出，防止齐射拖出散兵尾巴 |

### 2.3 作用域

| 状态 | TIGHT 生效？ | 行为 |
|---|---|---|
| 巡航 / 待命 / 紧急集合途中 | ✅ | 收紧编队跟随（防游走 leash 归零，见 [[squad-cohesion]]） |
| STANDOFF 集火（攻击轮盘·保持距离） | ✅ | 整队齐射循环（§3.1，核心场景） |
| 防守此区拦截 | ✅ | 整队出击拦截进圈目标，同齐射循环 |
| 自动交战 | ✅ | 同上 |
| ASSAULT 突击 / 被迫 merge 缠斗 | ❌ **临时豁免**（用户已确认） | 缠斗物理上不可能保持紧密阵型：突击期间临时按 FREE 执行，脱离缠斗后自动收拢回 TIGHT |
| 求生规避 | ❌ 层级更高 | 不变：flare 优先不脱队（与 TIGHT 天然契合）；真威胁才有界脱离，结束后归位 |

## 3. 行为与公式（How）

### 3.1 TIGHT 整队齐射循环（队级状态机，长机为基准）

| 阶段 | 进入条件 | 行为 | 退出 |
|---|---|---|---|
| FORM_INGRESS | 接到集火/拦截命令 | 长机飞向目标至齐射距离；僚机保持编队槽位（不各自 BFM）；进入 `齐射距离 × volley_lock_lead_mult` 全员开始锁定 | 长机进带且完成锁定 → VOLLEY |
| VOLLEY | 长机满足开火条件 | 开窗 `volley_window_s`：窗口内有锁有解的成员朝**各自命令目标**释放——FOCUS 集火=同一目标饱和 / SPREAD 分火=各自所选目标"一波清一片"（火力分配见 [[command-wheel]] §3.6）；电磁炮 LINE_UP 直线充能与编队直线同构；无解者持械 | 窗口关闭 / 全员打完 → FORM_EGRESS |
| FORM_EGRESS | 齐射完毕 | 整队冷转，拉开至带外沿 × `egress_dist_mult`；转弯遵守角点速度地板 | 到位 → FORM_INGRESS（循环） |
| FORM_DRAG（防碰瓷） | 目标压进带内沿以内 | 整队先拉开再回头（同 STANDOFF DRAG，队级执行） | 脱出 → FORM_INGRESS |

- 目标阵亡：循环终止，按命令来源回归（集火→回编队待命；防守→回 ORBIT）。
- 与单机 STANDOFF 循环（command-wheel §3.5）的关系：同一循环的**队级聚合执行**——FREE 下每架机各自跑，TIGHT 下只有长机跑、僚机跟槽位 + 齐射门控。

### 3.2 FREE 模式（=现状，零改动基线）

自由僚机按可命中性评分各自选位/交战（[[target-engageability-selection]]），包围是多机独立 BFM 几何的自然涌现，不做显式包围算法。

### 3.3 开关切换时机

- FREE → TIGHT：交战中切换不打断当前攻击，各机完成当前一轮后收拢归队进入队级循环。
- TIGHT → FREE：立即放飞（僚机下一 tick 起自由交战）。

## 4. 结构与组成（Structure）

- **开关状态**：队级字段（挂 Squad 或玩家机，与其它战术 toggle 同层），轮盘/HUD 双入口镜像。
- **齐射门控**：`SquadCoordination` 扩展（volley gate 广播 + 锁定提前），不新建系统。
- **队级循环**：AIController 战术层，复用 STANDOFF 循环骨架 + 既有编队跟随；抑制个体 engage 脱队的注入点走 squad-cohesion 既有"维持阵型"通路。
- **性能**：门控判定挂在既有 AI 分频 tick（≥3 分频），无新 per-frame 开销。

## 5. 验收标准（Acceptance / Litmus）

- [ ] FREE 模式回归：开关默认 FREE 时全部行为与改动前一致。
- [ ] TIGHT + 攻击轮盘保持距离：四机保持编队进入 → 一波齐射（EventLogger 可见开火时间戳聚在 volley_window 内）→ 整队拉开 → 再进入循环。
- [ ] 齐射纪律：窗口关闭时未就绪的僚机不追射、不脱队。
- [ ] 混装：电磁炮+导弹混编齐射，各用各的武器，无解者持械跟队。
- [ ] TIGHT + 突击：临时散开缠斗，战斗结束自动收拢归队。
- [ ] 规避豁免：齐射循环中被导弹锁定，flare 照撒不脱队；真威胁有界脱离后归位。
- [ ] 切换时机：交战中 FREE↔TIGHT 切换无瞬移/无诡异急转（物理优雅）。
- [ ] 编队响应无分频死点（SEAM-011：长机相对量不得缓存成 AI 低频快照）。
- [ ] 性能：Sentinel + Lv5+ 压测 FPS 掉幅 < 15。
- [ ] i18n：开关文本走 tr()，三语已补。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 开关 + 收紧编队
- [x] `formation_tight` 队级字段（SquadCommandController）+ 攻击轮盘右槽切换 + 轮盘状态显示
- [ ] HUD 第 6 toggle 镜像——**暂未做**：用户方向已定"开关长期收束进轮盘"，轮盘为唯一入口；若 playtest 想要面板镜像再补
- [ ] TIGHT 巡航/待命收紧编队（防游走 leash 归零）——v1 未做（攻击时僚机"不发目标"已保证不脱队；巡航收紧待 playtest 观感决定）

### 阶段 2 — 队级齐射循环（2026-07-12 v1 落地，设计变体见 §8 v5）
- [x] **齐射触发器 = 长机开火**（v1 设计变体）：TIGHT 集火时只有长机接命令目标（含玩家亲自带队——你扣扳机的瞬间全队齐射，指挥官仪式感）；僚机全程编队跟随，"整队进入/拉开"由编队复现长机轨迹自然涌现，未做显式 FORM_* 队级状态机
- [x] 齐射门控：开窗 `volley_window_s=1.5s` → 僚机临时授予 combat_target（`volley_fire_active` 豁免 SquadCoordination 编队防御清除，**在槽位里开火不脱队**）→ 到时回收 = 禁补射（构造保证）→ 长机停火 ≥`volley_rearm_quiet_s=2s` 才允许下轮开窗（防连环开窗）；锁定提前由编队机头几何在进入段自然积累（未做显式 1.3× 参数）
- [x] ASSAULT 豁免（发令级：TIGHT+突击 = 普通集火广播）；战后收拢 = 目标亡自动清理回编队
- [ ] SPREAD+TIGHT 齐射（分火暂忽略阵型纪律）/ 防守·自动交战接 TIGHT——后续按 playtest 需求

### 阶段 3 — 收尾
- [x] `--bench=tight_volley` 10 断言（长机独持/僚机不脱队/开火开窗/到时禁补射/安静期再武装/目标亡清理/ASSAULT 豁免）
- [ ] 生存 playtest（TIGHT 集火观感：整队进入-齐射-拉开）
- [x] 参数落 CommandWheelParams（volley_window_s / volley_rearm_quiet_s）+ §7 锚点 + reference 索引

## 7. 索引锚点（Where —— 实现后填）

| 关注点 | 文件 |
|---|---|
| 开关字段/镜像 | 待实现 |
| 齐射门控 | `scripts/ai/squad_coordination.gd` 扩展（计划） |
| 队级循环 | AIController 战术层（计划） |
| reference 索引行 | 实现后补 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-05 | 1 | 初稿：FREE/TIGHT 开关、整队齐射循环（锁定提前 1.3× + 窗口 1.5s + 禁补射）、齐射距离走武器准则包络带、ASSAULT 临时豁免（待确认）、规避层级不变、FREE=现状零改动 |
| 2026-07-05 | 2 | 用户确认：ASSAULT 临时豁免定稿；HUD 双入口都做（长期收束进轮盘、战术栏后撤）。VOLLEY 阶段接火力分配（command-wheel §3.6）：FOCUS 饱和同一目标 / SPREAD 各机朝各自分配目标齐射，超杀问题由分火开关解决、不做 AI 自动干预 |
| 2026-07-05 | 3 | 同步火力分配语义定稿：分火=目标池内各自接敌（自主选择，无中心分配器）；集火在 FREE 阵型下带包围轴分离、TIGHT 下阵型优先于包围（详见 command-wheel §3.6） |
| 2026-07-05 | 4 | 入口改为**攻击轮盘右槽**（用户：阵型纪律决定"怎么打"，归攻击语境；小队命令轮盘左下让位给撤离此区） |
| 2026-07-12 | 5 | **用户确认 → v1 实装（status: in-progress）**，设计变体：①齐射触发器 = **长机开火**（原设计"长机进包络+锁定"改为可观察的开火事件——玩家亲自带队扣扳机即全队齐射，指挥官仪式感；AI 长机 pass 循环同样适用）；②未做显式 FORM_* 队级状态机——TIGHT 集火时长机独持命令目标飞攻击几何，僚机全程编队跟随，"整队进入/拉开"由编队复现长机轨迹自然涌现（零新编队代码）；③齐射窗口 = 临时授予僚机 combat_target + `Aircraft.volley_fire_active` 豁免 SquadCoordination 编队防御清除（僚机在槽位里开火不脱队），到时回收=禁补射（构造保证），停火 ≥2s 再武装防连环开窗；④锁定提前由编队机头几何自然积累（未做显式 1.3× 参数）；⑤参数 volley_window_s=1.5/volley_rearm_quiet_s=2.0 落 CommandWheelParams；⑥HUD 第 6 toggle 暂不做（用户"开关长期收束进轮盘"）。`--bench=tight_volley` 10/10。剩巡航收紧/SPREAD+TIGHT/playtest |
