---
id: missile-launch-discipline
kind: system
status: done
schema_version: 1
spec_version: 2
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

### 3.2 初始朝向

飞机发射的导弹复用 §2.3 的两轮前置点，把初始 heading 指向预测命中点，再相对发射机 heading 限制到 `±60°`；初始位置沿最终 heading 前移 `15 px`。这样 `guidance_delay` 内也直接朝前置点飞。

VLS 继续使用 LOS 加每发 `±25°` 散布；地面与舰载 SAM 继续使用 source-to-target LOS；两者不进入飞机发射纪律。

### 3.3 诊断

- 稳定窗口失败记录 `UNSTABLE_WIN` 与实际 skill。
- 前置包络或偏角失败记录 `LEAD_GEOM`、TTI 与偏角/距离。
- 诊断只在既有 EventLogger/武器日志节奏发生，不新增逐帧打印。

## 4. 结构与组成（Structure）

- CombatParams 保存基础 skill 与 jitter；各 `.tres` 只复制本 spec 数值。
- AircraftWeapons 计算有效 skill、稳定窗口与前置解，并同时服务单锁和多锁路径。
- AircraftCombatTracking 暴露“任意预测点走现有导弹包络”的纯几何入口。
- MissileManager 只负责飞机导弹的前置出筒 heading；地面、舰船与 VLS 分支保持隔离。

## 5. 验收标准（Acceptance / Litmus）

- [x] 横切目标在预测点越出包络时被拒绝，尾追稳定窗口仍可正常发射。
- [x] skill 高档比低档更少在高 bank、大滚转率和大前置偏角下发射。
- [x] 单锁与多锁齐射使用同一门槛；齐射不会绕过前置包络。
- [x] 飞机导弹出筒即朝预测命中点；VLS、SAM 与舰载发射朝向不变。
- [x] 玩家仍只通过走位和武器偏好影响自动开火，不新增手动发射键。
- [x] 性能：无全场新扫描；Sentinel 与 `stress_40` 的 Lv8/32 机压力样本末秒均为 145 帧。
- [x] i18n：无新增玩家可见文本。
- [x] 文档：本 spec 已登记 _INDEX；reference 索引同步。

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

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 参数 | `scripts/combat_params.gd`、`resources/*_combat.tres` |
| 发射门 | `scripts/aircraft/aircraft_weapons.gd` |
| 包络几何 | `scripts/aircraft/aircraft_combat_tracking.gd` |
| 初始朝向 | `scripts/missile_manager.gd` |
| 聚焦测试 | `scripts/tests/test_waypoint_fire_control.gd`、`scripts/tests/test_weapon_behavior.gd` |
| reference 索引 | `docs/reference/script-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-16 | 1 | 将历史 missile-skill-gate 按当前主线架构重建为权威规格；保留前置几何与技能档位，明确排除地面/舰载/VLS。 |
| 2026-08-16 | 2 | 当前主线语义移植完成；weapon 29/29、waypoint 30/30、surface pass 32/32、TIGHT 齐射 10/10、fire allocation 15/15、BOSS 33/33，两个压力场末秒均为 145 帧。 |
