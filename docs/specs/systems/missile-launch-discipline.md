---
id: missile-launch-discipline
kind: system
status: done
schema_version: 1
spec_version: 4
owner: user
depends_on: [systems/weapon-employment-doctrine, systems/multi-target-missile-locks]
reconstruction_complete: true
---

# 导弹发射纪律

> 飞机不再把导弹浪费在明显追不上或机头尚未对准前置点的窗口；不同作战档案仍保留从冒进到精准的可见差异。

## 1. 设计意图（Why）

- **体验目标**：玩家通过走位把飞机带入有效发射窗口后，导弹直接朝预测命中位置出筒；边缘射程、高侧速和高 G 横切不再频繁制造“刚发射就烧光能量”的废弹。
- **Litmus 自检**：符合设计哲学“信息察觉优先于数值”“AI 要演戏”和“全武器自动开火”；能力差异表现为真实的发射选择与初始弹道，不新增手动扳机。
- **反模式规避**：不按现实导引头分类另造状态机；只在飞机共用导弹路径增加几何门。地面 SAM、舰载武器与 BOSS VLS 继续使用自身路径。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 作战档案参数

| 档案 | `missile_skill` | `missile_skill_jitter` | 定位 |
|---|---:|---:|---|
| 玩家 F-14 / F-16 | `0.85` | `0.10` | 玩家主角机 |
| ACE | `0.85` | `0.10` | BOSS / 王牌级 |
| Lancer | `0.65` | `0.15` | 打带跑型 |
| Default | `0.55` | `0.20` | 通用敌战斗机 |
| Gladiator | `0.45` | `0.20` | 近距缠斗型 |
| 未显式配置的兜底 | `0.40` | `0.15` | 新档案的中低纪律默认值 |

- 两个字段的合法范围分别为 `[0,1]` 与 `[0,0.4]`。
- 每次发射判定得到 `skill = clamp(base + random(-jitter,+jitter), 0, 1)`；无导弹或无 CombatParams 时返回 `0`。

### 2.2 稳定窗口端点

所有阈值按 `lerp(loose, tight, skill)` 计算。

| 条件 | Loose | Tight | 适用 |
|---|---:|---:|---|
| 雷达半角倍率 | `0.95` | `0.50` | 非 fire-and-forget |
| 雷达半角倍率 | `1.00` | `0.85` | fire-and-forget |
| 最大 bank | `75°` | `35°` | 非 fire-and-forget |
| 最大 bank | `90°` | `60°` | fire-and-forget |
| 最大滚转率 | `120°/s` | `30°/s` | 仅非 fire-and-forget |

### 2.3 前置解端点

| 字段 | 值 |
|---|---:|
| 估算导弹平均速度 | `max(发射机速度, 导弹最大速度 × 0.85)` |
| 平均速度下限 | `100 m/s` |
| TTI 迭代次数 | `2` |
| 前置偏角倍率 Loose | `1.00` |
| 前置偏角倍率 Tight，非 fire-and-forget | `0.30` |
| 前置偏角倍率 Tight，fire-and-forget | `0.55` |
| 导弹出筒方向上限 | 相对发射机机头 `±60°` |

## 3. 行为与公式（How）

### 3.1 发射门

单锁自动发射与多锁齐射的每个候选目标都依次通过：

1. 现有锁定、弹量、CD、目标合法性与导弹包络；
2. 稳定窗口：按 §2.2 检查 bank、机头到当前目标的偏角；非 fire-and-forget 额外检查滚转率；
3. 两轮前置解：以目标当前速度和 heading 预测命中点；
4. 用预测点而非目标当前位置重新执行同一导弹包络几何。失败始终拒绝，与 skill 无关；
5. `机头到预测点偏角 ≤ seeker_fov × 0.5 × lerp(1, tight_ratio, skill)`；
6. 全部通过后按现有自动开火路径发射。

已锁定且进入中距发射带时，发射前 planner 必须直接追踪与第 3–5 步同一个两轮 TTI 前置点；锁定本身不得提前触发 crank。只有导弹已出筒、需要短时支援时才进入既有 crank 几何。当前目标 LOS、发射门前置解与 planner 追踪点不得各自重算或分叉。

### 3.1a 玩家追击的发射姿态闭环

玩家偏好控制路径保留完整转弯能力，但不能在已有发射解时持续高坡度跟转而永远被自身火控拒绝。

- 只对玩家偏好路径的 `CLOSE_TAIL / TAIL_CHASE / LEAD_TURN / LEAD_PURSUIT / LAG_PURSUIT` 生效；AI 既有物理降坡不重复叠加。
- 当前空中目标已满锁，主弹有余弹、非装填、冷却归零，且不在 JAM、规避、加力窗口、外部导弹控制或发射后支援期。
- 距离处于既有预发射追踪带：`min_range × 1.5 < distance ≤ max_range_rear × 0.7`；当前点及两轮前置点均通过原物理包络。
- 以 `clamp(missile_skill + missile_skill_jitter, 0, 1)` 的最严格端验证当前偏角与前置偏角，不为飞行指令抽取随机熟练度。
- 以上成立且 plan 允许导弹时，使用已有 `bank_limit_deg` 接口，将目标坡度限制为同源稳定窗口上限减 `2°`。余量用于让连续滚转控制确实越过发射门槛，不改变实际发射的任一阈值。
- 航点、手动意图、机炮优先、双击冲锋、规避、脱离、慢空中/面目标攻击跑、电磁炮直线充能与尚未收敛的包围门不被接管。失锁、出角度门、出弹或进入冷却后自然解除此建议。
- 不新增常驻 tick、全场扫描或 Object 缓存；Situation 只携带数值建议，planner 仍是纯数据决策。

### 3.2 初始朝向

飞机发射的导弹复用 §2.3 的两轮前置点，把初始 heading 指向预测命中点，再相对发射机 heading 限制到 `±60°`；初始位置沿最终 heading 前移 `15 px`。发射门、发射前 planner 与离架航向共用 `AircraftWeapons.missile_lead_point`，使 `guidance_delay` 内也直接朝同一前置点飞。

VLS 继续使用 LOS 加每发 `±25°` 散布；地面与舰载 SAM 继续使用 source-to-target LOS；两者不进入飞机发射纪律。

### 3.3 诊断

- 稳定窗口失败记录 `UNSTABLE_WIN` 与实际 skill。
- 前置包络或偏角失败记录 `LEAD_GEOM`、TTI 与偏角/距离。
- 诊断只在既有 EventLogger/武器日志节奏发生，不新增逐帧打印。

## 4. 结构与组成（Structure）

- CombatParams 保存基础 skill 与 jitter；各 `.tres` 只复制本 spec 数值。
- AircraftWeapons 计算有效 skill、稳定窗口与前置解，并同时服务单锁和多锁路径。
- BfmIntent 在未出弹的发射带追踪 AircraftWeapons 同源前置点；出弹后才恢复 crank 支援。
- AircraftCombatTracking 暴露“任意预测点走现有导弹包络”的纯几何入口。
- MissileManager 只负责飞机导弹的前置出筒 heading；地面、舰船与 VLS 分支保持隔离。

## 5. 验收标准（Acceptance / Litmus）

- [x] 横切目标在预测点越出包络时被拒绝，尾追稳定窗口仍可正常发射。
- [x] skill 高档比低档更少在高 bank、大滚转率和大前置偏角下发射。
- [x] 单锁与多锁齐射使用同一门槛；齐射不会绕过前置包络。
- [x] 飞机导弹出筒即朝预测命中点；VLS、SAM 与舰载发射朝向不变。
- [x] 高速横穿目标已锁定时，发射前 planner 收敛到真实发射门的前置点；不再持续 `LEAD_GEOM` 拒发。
- [x] crank 仅在出弹后支援期生效，既有连续无翻号几何不变。
- [x] 玩家仍只通过走位和武器偏好影响自动开火，不新增手动发射键。
- [x] 性能：无全场新扫描；Sentinel 与 `stress_40` 的 Lv8/32 机压力样本末秒均为 145 帧。
- [x] i18n：无新增玩家可见文本。
- [x] 文档：本 spec 已登记 _INDEX；reference 索引同步。

- [x] 同向盘旋日志几何经真实 planner、物理滚转及武器提交后及时出弹；旧决策对照保持拒射。
- [x] 无锁、未对准、无弹、冷却、装填、JAM、规避、机炮优先、支援期、AI 与航点负例不误收坡。

- [x] 本轮 `weapon` 50/50、`waypoint_fire` 30/30、标准 `all` 105 项及 93 项生命周期全通过，运行时错误门通过。
- [x] 性能 E0：只在既有玩家 planner 快照中计算当前目标的常数次几何，不新增 tick、draw、实体、弹丸额度、全场扫描或跨帧缓存。按性能守则 R7 采用静态审计及聚焦回归豁免新增 Visual 压测；本轮不声明新的 FPS 或整局平衡结论。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 参数与几何
- [x] 为 CombatParams 与五类资源增加 skill/jitter。
- [x] 抽取任意预测点的导弹包络判定。

### 阶段 2 — 发射与弹道
- [x] 单锁和多锁路径接稳定窗口与前置解。
- [x] 飞机导弹改为前置朝向出筒，保留其它发射器路径。

### 阶段 3 — 验证
- [x] 增加确定性聚焦测试与日志契约。
- [x] 跑武器、BOSS、齐射分配和 Sentinel 回归。

### 阶段 4 — 发射前几何闭环
- [x] 抽取单一 `missile_lead_point`，发射门、planner、离架航向共用。
- [x] 区分未出弹的拦截收敛与已出弹的 crank 支援。
- [x] 聚焦回归复制高速横穿的真实发射门序列。

### 阶段 5 — 玩家发射姿态闭环
- [x] 武器层提供同源稳定坡度建议，Situation 数值透传，planner 在追击与保持分支消费。
- [x] 真实 60Hz 追击/滚转/离架对照与禁入边界通过，普通 F5 默认生效。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 参数 | `scripts/combat_params.gd`、`resources/*_combat.tres` |
| 发射门 | `scripts/aircraft/aircraft_weapons.gd` |
| 发射前战术追踪与姿态 | `scripts/ai/tactical/bfm_intent.gd`、`scripts/ai/tactical/situation.gd`、`scripts/ai/tactical/tactical_planner.gd` |
| 包络几何 | `scripts/aircraft/aircraft_combat_tracking.gd` |
| 初始朝向 | `scripts/missile_manager.gd` |
| 聚焦测试 | `scripts/tests/test_waypoint_fire_control.gd`、`scripts/tests/test_weapon_behavior.gd` |
| reference 索引 | `docs/reference/script-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-16 | 1 | 将历史 missile-skill-gate 按当前主线架构重建为权威规格；保留前置几何与技能档位，明确排除地面/舰载/VLS。 |
| 2026-08-16 | 2 | 当前主线语义移植完成；weapon 29/29、waypoint 30/30、surface pass 32/32、TIGHT 齐射 10/10、fire allocation 15/15、BOSS 33/33，两个压力场末秒均为 145 帧。 |
| 2026-08-18 | 3 | 修复高速横穿时 planner 的预发射 crank/LOS 与武器层前置门不一致：三个消费者共用两轮 TTI 前置点，crank 限已出弹支援期；`weapon` 33/33。 |
| 2026-11-01 | 4 | 根据 combat_log_20261031_224050 补齐玩家追击的发射姿态闭环；保持全部火控门槛，使用同源坡度建议创造窗口。`weapon` 50/50、`waypoint_fire` 30/30、`all` 105 项及生命周期 93 项全部通过；复核见 [狗斗发射窗口记录](../../audits/2026-11-01-dogfight-launch-window.md)。 |
