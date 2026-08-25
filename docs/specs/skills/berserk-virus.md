---
id: berserk-virus
kind: skill
status: done
schema_version: 1
spec_version: 3
owner: design
depends_on: [skills/bloodlust, systems/squad-control-switching, systems/squad-cohesion]
reconstruction_complete: true
---

# 狂化病毒

> 放弃对僚机的直接接管与交战模式切换，换取一支持续自由猎杀、机动和武器循环显著强化的斗士编队。

## 1. 设计意图（Why）

- **体验目标**：让僚机从“玩家可随时接管的备用机”变成会自己寻找近处战斗、击杀后继续滚雪球的危险伙伴；玩家仍能通过攻击、移动、防守、集合、撤离和火力姿态命令控制战局。
- **Litmus 自检**：
  - 符合“信息察觉优先于数值”：FREE 行为、无法切控、持续更紧凑的武器循环和击杀后的 BLOODLUST 都有可观察结果。
  - 符合“玩家 Buff 必须跨真实交战周期”：机动与 CD 是僚机身份模式的常驻效果；BLOODLUST 沿用 9 秒标准窗口。
  - 符合 60 FPS 红线：只复用现有 FREE 的 1 Hz 局部扫描，不新增全图目标搜索或每实体场景树扫描。
- **反模式规避**：不做全图扫荡，不取消其它小队命令，不提高顶速，不把模式 buff 永久写入机体 params，也不阻断长机阵亡后的自动继任。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 技能条目

| 字段 | 值 | 说明 |
|---|---|---|
| id | `berserk_virus` | 唯一账本 id |
| stat | `berserk_virus` | M2 字段置位；高频消费读 Aircraft 布尔字段 |
| value / max_stacks | `1 / 1` | 不叠加 |
| category / axis | `survival / gladiator` | 显式归斗士轴 |
| rarity | `EXPERIMENTAL` | 实验级；强度不足以占用战区次世代奖励位 |
| 获取渠道 | 斗士普通三轴卡池 | 不设置 `evolved`；仍因 `bloodlust` 关键词受嗜血学说门控 |
| scope | 默认全队 | 当前与后来入队的玩家小队飞机都取得能力旗标；是否生效由当前操控身份动态判定 |
| keywords | `squad, bloodlust, mobility, weapon` | BLOODLUST 是真实状态语义并接受对应学说门控 |
| milestone_plus | `gladiator` | 获得时斗士里程碑进度 +1 |

### 2.2 狂化僚机常驻倍率

| 效果 | 值 | 边界 |
|---|---|---|
| 持续 / 瞬时结构最大 G | ×1.25 | 经统一 `effective_*` G 乘区，AI 战术与物理同源感知 |
| 滚转率 | ×1.25 | 经滚转率 accessor 同时进入实飞与预测 |
| 加速 / 减速能力 | ×1.25 | 不提高巡航速度或最大速度 |
| 普通武器 CD 恢复速率 | ×1.40 | 只作用于共享 `weapon` CD 通道：机炮射击间隔、火箭 burst、主导弹和副导弹发射 CD；不改装填、激光热量、电磁炮、鱼雷、CIWS 与忠诚僚机等独立装备节奏 |
| 热诱弹 CD 恢复速率 | ×1.50 | 同时加快短释放 CD 与弹药耗尽后的共享装填计时 |
| 击杀后状态 | 标准 BLOODLUST 9.0 秒 | 复用现有 max 刷新规则、基础回血与普通机炮/CIWS 零耗弹语义 |

## 3. 行为与公式（How）

### 3.1 动态身份门

```text
berserk_wingman =
  aircraft.berserk_virus_active
  AND aircraft 属于玩家直属小队
  AND aircraft 不是当前玩家操控引用
  AND aircraft 有有效 AIController
  AND AIController.manual_control == false
```

- 当前操控机即使持有全队旗标也不吃任何狂化倍率，不强制 FREE，且本身可正常接受玩家操控。
- 长机阵亡时允许既有自动继任；新长机进入 `manual_control=true` 后立即退出狂化效果。
- 若旧操控机重新成为 AI 僚机，则按同一动态门自动获得狂化效果，不写死某个 `squad_slot`。

### 3.2 自由交战锁定

- 获得技能后，直属小队交战模式立即设为 `FREE`，绑定阵型设为 `COMBAT_SPREAD`。
- 僚机 AI 每次决策前兜底校正为 `FREE`，外部路径不得把狂化僚机长期留在 `FOLLOW_LEADER` 或 `GUARD_REAR`。
- FREE 沿用现有语义：待命时维持宽松展开；约每 1 秒扫描 1500 px（约 3 km）内的附近空中敌人；交战仍受距当前长机 1800 px（约 3.6 km）的小队 leash 与 0.5 秒滞回约束。
- **不是全图扫荡**：看不到局部敌人时不跨地图寻敌，也不改变敌方 LOD、远距冻结或清理锚点。

### 3.3 命令与切控

- 数字键主动接管其它存活号机时：请求被拒绝，当前操控机不变，并显示一次本地化临时提示。
- 当前操控机阵亡后的自动继任不走上述拒绝门。
- C 键或旧小队面板尝试切换交战模式时：保持 FREE，不脱离当前目标、不改阵型，并显示一次本地化临时提示。
- 其它既有命令全部照常：点名攻击、移动、集合、守卫、撤离、分散/集中、火力姿态与武器偏好可临时覆盖自主行为；命令完成或取消后回到 FREE 局部扫描。

### 3.4 CD 公式

```text
final_cd_rate(channel) = existing_cd_rate(channel)
if berserk_wingman and channel == "weapon": final_cd_rate *= 1.40
if berserk_wingman and channel == "flare":  final_cd_rate *= 1.50
```

倒计时继续写基础时长，只在 tick 消耗侧乘恢复速率，保证 LOD 的 delta 补偿路径保持真实时间一致。

## 4. 结构与组成（Structure）

- `SurvivorData.UPGRADES`：实验级斗士普通卡池条目；不进入战区次世代奖励池。
- `SurvivorPlayer.apply_upgrade`：给全队飞机置 `berserk_virus_active`，并立即校正小队 FREE 状态。
- `Aircraft`：持有布尔旗标、动态僚机身份查询与 weapon/flare CD 乘区。
- `AircraftPhysics`：G、滚转、加速与减速的唯一模式 buff 注入层。
- `AIController`：决策前 O(1) 兜底 FREE 锁定；不新增扫描。
- `SkillHooks`：击杀时给狂化僚机施加标准 BLOODLUST。
- `SurvivorMode / SurvivorHUD`：只拦主动切控与交战模式切换；自动继任和其它命令路径不变。

## 5. 验收标准（Acceptance / Litmus）

- [x] 获得技能后所有现有及后来入队的直属僚机进入 FREE；C 键不能切走，且不会因尝试切换而丢失当前战斗目标。
- [x] 数字键不能主动接管其它号机并给出提示；当前操控机阵亡后仍会自动接管下一架存活僚机。
- [x] 点名攻击、移动、集合、守卫、撤离、分散/集中、火力姿态和武器偏好仍能执行；完成后恢复 FREE。
- [x] 狂化僚机 G/滚转/加减速倍率均为 ×1.25，AI 战术读取到有效值；当前操控机与未持有技能的基线不变。
- [x] weapon CD rate 为基线 ×1.40，flare CD rate 为基线 ×1.50；特殊装备和普通装填不被误改。
- [x] 狂化僚机击杀后获得 9 秒 BLOODLUST；玩家亲控机仅凭本技能击杀不触发。
- [x] 性能：Lv15、直属 9 机、扩池 17 敌 + Sentinel/5 护卫同负载 Shadow A/B 为 139→134 FPS（-5）；8 架狂化僚机均由既有友军 LOD 所有者钉在 LOD 0。
- [x] i18n：技能名、描述和两类拒绝提示三语齐全；普通 UI 规则继续继承 `systems/ui-design-guidelines`。
- [x] Debug：F4 从正式技能表自动列出并可绕过门控强制授予，仍尊重 `max_stacks=1`。
- [x] 获取：稀有度为 `EXPERIMENTAL`、无 `evolved`，可进入普通三轴卡池；因 `bloodlust` 关键词仍需嗜血学说。
- [x] 文档：本 spec 已登记 `_INDEX`，技能表与实现索引同步，当前文档校验通过。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与角色门
- [x] 登记升级条目、三语文本和 Aircraft 高频旗标。
- [x] 接入全队/后来入队重放与动态操控身份判定。

### 阶段 2 — 行为与数值
- [x] 锁定 FREE，拦主动切控与 C 切换，保留自动继任和其它命令。
- [x] 经 accessor 接入机动倍率，经 CD rate 接入 weapon/flare 倍率。
- [x] 击杀钩子复用标准 BLOODLUST。

### 阶段 3 — 验收与索引
- [x] 补技能数据、动态门、CD、机动、BLOODLUST 和命令边界断言。
- [x] 重生成技能表和 translation，更新 reference 索引。
- [x] 跑定向 bench、全表审计、文档校验与压力测试。

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 技能条目 | `scripts/survivor/survivor_data.gd` |
| 置位 / 重放 | `scripts/survivor/survivor_player.gd` |
| 动态身份与 CD | `scripts/aircraft.gd` |
| 机动 accessor | `scripts/aircraft/aircraft_physics.gd` |
| FREE 兜底 | `scripts/ai_controller.gd` |
| 击杀 BLOODLUST | `scripts/survivor/skill_hooks.gd` |
| 切控与交战模式拦截 | `scripts/survivor/survivor_mode.gd` / `scripts/survivor/survivor_hud.gd` |
| i18n | `i18n/skills.csv` / `i18n/interface.csv` |
| 自动回归 | `scripts/tests/test_skills_720.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-24 | 3 | 用户裁定强度不配作为战区奖励：稀有度由 `NEXT_GEN` 改为 `EXPERIMENTAL`，移除 `evolved` 并进入斗士普通卡池；效果、单层上限、代价警告和嗜血学说门控均不变。 |
| 2026-08-17 | 2 | 完成实现与回归：290 项定向技能断言、185 项全表审计、44 项战区奖励通过；同负载压力场 139→134 FPS，确认 8 架僚机保持 LOD 0。 |
| 2026-08-17 | 1 | 用户将名称定为“狂化病毒”并要求开始实现；按已确认的锁定 FREE、禁止主动切控、其它命令保留和击杀嗜血语义固化首版数值。 |
