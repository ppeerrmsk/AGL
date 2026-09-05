---
id: encounter-director
kind: system
status: in-progress
schema_version: 1
spec_version: 4
owner: user+codex
depends_on: [systems/global-awareness-roe, systems/survivor-loop, systems/battlefield-tempo-pass, systems/reinforcement-ingress, systems/zone-air-support-naval-safety, systems/zone-atmosphere-combat, systems/runtime-performance-budget, systems/bomber-escort-zone, systems/ace-squadron-tier, systems/squad-xp-threat-balance, systems/squad-cohesion, systems/formation-discipline]
reconstruction_complete: false
---

# Encounter Director 敌方遭遇导演系统

> 让生存模式始终有可读、可处理、会收束的战斗节奏：地图可以很热闹，但同一时刻真正压在玩家小队上的致命压力必须由一个导演统一分配。

## 1. 设计意图（Why）

### 1.1 要解决的问题

当前生存模式已经有旅途增援、战区任务、轰炸机护送、王牌事件、BOSS/Adds、三级全局威胁、战区气氛层与多类友军支援。各来源分别拥有生成和退场逻辑，虽然部分入口已有任务中停刷、BOSS 清场、Token、实例上限、离屏 LOD 与物理撤离，但缺少统一的“当前玩家实际承压”账本。

因此同一套存量可能出现两种相反体验：

- 多架单位在远处巡逻或与第三方交战，玩家却长时间没有明确目标；
- 旅途敌机、任务守军、王牌与特殊机制重叠，数量未必极端，但锁定、导弹、机炮攻击跑同时成立，瞬间超过可处理上限。

Director 不用敌人 HP、伤害或无限增员修节奏，而是统一回答四个问题：

1. 现在能否再创建真实单位；
2. 现在有多少有效敌压正在作用于玩家；
3. 哪个 Encounter 应优先占用敌压；
4. 哪些敌人此刻可以进入最终致命攻击动作。

### 1.2 体验目标

标准节奏为：

`接近 → 预告 → 接敌 → 压力建立 → 高潮 → 清理/撤离 → 8～12 秒恢复 → 下一次接敌`

- 玩家大多数时间都有明确目标，但不要求一直处于峰值压力。
- 高 Heat 主要改变敌方编成质量、主动接敌比例与致命攻击机会，不把数量曲线无限放大。
- 同样数量的敌机优先表现为数个可辨认、会重整的紧密编队；接敌不等于全员立刻解除阵型、各自追击到战场四角。
- 玩家以单机出击时，后续普通敌方响应继续偏向单机；玩家以直属编队出击时，后续响应继续偏向双机、3～4 机队及多 Element Package，但只做软相关，不逐架镜像。
- 任务、王牌和 BOSS 改变当前压力的组成，不在已经填满的旅途敌压上简单加怪。
- 清场快的玩家获得真实节奏收益；清场慢时不会积累 Spawn Debt，之后也不会补刷欠账。
- 战场气氛与第三方交战继续存在；Director 只控制对玩家有效的战斗压力，不把“地图上看见多少单位”误当成同一个值。

### 1.3 Litmus 自检

- **设计哲学 #2 笨重与延迟快感**：限制的是同拍致命攻击，不让敌人失去包抄、占位、拉开和重整；玩家仍需预判。
- **#3 信息察觉优先**：节奏变化通过成建制入场、无线电、敌方编成、真实撤离和恢复窗体现，不新增必须盯看的 Heat HUD。
- **#4 难度与节奏**：难度来自受控压力下的编成与攻击机会，不用 HP/DPS 膨胀代替。
- **#7 热闹战场**：不为过性能门删除正在发生的战斗；未关注战区仍保持战略层 0 实体，已激活战线保留真实演员。
- **#11 60 FPS 硬底线**：Director 为集中式低频账本，不给每架飞机新增 `_process`、子节点或全场扫描。

### 1.4 原草案审查裁决

| 原方向 | 裁决 | 修订 |
|---|---|---|
| Presence / Pressure / Attack Slot 分层 | 保留 | Presence 再拆为玩法人口与性能工作量；不能用单一 `32` 上限覆盖舰船挂点、气氛单位和友军 |
| 新建 Battle Heat | 否决 | 复用现有 `RoeDirector.heat`，保持 0～100、交战事件升温、静默衰减与小队地板；禁止第二套 Heat 真源 |
| 任务统一重写八阶段生命周期 | 延后 | 首版用 Encounter 适配现有 AVAILABLE/SELECTED/triggered/completed/failed，不先重写已经稳定的任务状态机 |
| Attack Slot 同时管锁定、机炮和导弹 | 收窄 | 首版只在最终致命攻击承诺点申请；跟踪、雷达锁定、包抄和占位不占 Slot |
| BOSS 本体不进普通 PR、Adds 走 Director | 保留 | 按 BOSS 逐个迁移；迁移前保留旧逻辑，禁止半迁移导致重复生成 |
| 任务结束恢复窗 | 保留 | 默认 10 秒，可被 BOSS 转场等 critical Encounter 显式覆盖 |
| 禁止 Spawn Debt | 保留 | 被抑制的生成机会直接作废；恢复后只看当前缺口，不补历史次数 |
| 一次迁移所有生成来源 | 否决 | 先观察、再 Global、再任务/事件、最后 Attack Slot 与 BOSS；每阶段可独立回滚 |

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 Director 固定频率与全局常量

| 字段 | 值 | 说明 |
|---|---:|---|
| `DIRECTOR_TICK_S` | `0.5 s` | 2 Hz 低频账本；出生、死亡、阵营转换、任务终态等事件可在当帧提前标脏并重算 |
| `TELEMETRY_INTERVAL_S` | `5.0 s` | 周期日志；Encounter/抑制原因/预算跨档时立即额外记录 |
| `RECOVERY_DEFAULT_S` | `10.0 s` | 普通任务成功、失败与王牌终态后的默认恢复窗 |
| `RECOVERY_MIN_S` | `8.0 s` | 普通内容声明的最短恢复窗 |
| `RECOVERY_MAX_S` | `12.0 s` | 普通内容声明的最长恢复窗 |
| `DISENGAGE_GRACE_S` | `4.0 s` | ACTIVE 失去玩家交战关系后保留半额压力的迟滞 |
| `SPAWN_DEFICIT_THRESHOLD` | `1.5 PR` | 当前压力低于目标至少此值才考虑新 Package |
| `GLOBAL_PACKAGE_COOLDOWN_S` | `10～18 s` | 每次成功 Global Package 后重新随机；生成失败也消耗本次机会，不欠账 |
| `MISSION_PACKAGE_COOLDOWN_MIN_S` | `8.0 s` | 任务可声明更长值，不得更短 |
| `SPIKE_MULT` | `1.30` | 高潮期总压力软上限 `PR_TARGET × 1.30` |
| `SPIKE_MAX_S` | `20.0 s` | 连续处于普通目标之上的最长时间，之后必须降回普通目标 |
| `RECENT_PACKAGE_COUNT` | `3` | 防连续重复窗口 |
| `PLAYER_TARGET_PROTECTION_S` | `8.0 s` | 玩家点名/锁定普通敌人后，Director 不得为让预算直接删除或休眠该机 |

所有时间使用受 `Presentation` 控制的游戏/物理 `delta`。暂停时不推进；命令轮盘慢动作按实际游戏时间推进，不读取墙钟时间。

### 2.2 四类账本

| 账本 | 回答的问题 | 是否改变既有 Token |
|---|---|---|
| `Spawn Budget` | 这批单位是否有资源与内容资格生成 | 否；Token、实例上限、冷却、解锁/退役继续是硬门 |
| `Presence` | 世界里有哪些真实演员仍占人口/生命周期 | 否；撤离单位仍占 Presence，直到真正出界释放 |
| `Pressure (PR)` | 当前多少有效敌对战斗力正在作用于玩家小队 | 新增；与 Token 分账 |
| `Lethal Slot (LS)` | 同时有多少敌人可进入最终导弹/机炮/特殊攻击承诺 | 新增；不限制普通机动、跟踪与锁定 |

性能工作量不是第五种游戏难度。它读取 [runtime-performance-budget](runtime-performance-budget.md) 的分域快照，决定非关键单位的更新频率和 LOD，不反向增加敌压或奖励。

### 2.3 Presence 分类

| 字段 | 定义 | 首版上限/阈值 |
|---|---|---:|
| `hostile_aircraft_count` | 有效、未摧毁的 HOSTILE Aircraft | 正式内容软上限 `36` |
| `hostile_aircraft_hard_cap` | 仅显式高压内容/bench 可用 | `48` |
| `all_aircraft_count` | PLAYER、HOSTILE、ALLY 全部有效 Aircraft | 无单一玩法硬上限；用于 AI/LOD 工作量 |
| `combat_unit_count` | 含地面、舰船与挂点代理的全部 CombatUnit | 无单一玩法硬上限；只作分域性能与雷达诊断 |
| `temporary_ally_count` | 战区 F-86/A-10、王牌 F-15、AWACS、气氛友军及转换友军 | 不抬高 PR 目标；占 Presence 与性能成本 |
| `retreating_count` | 已进入 RETREATING/EGRESS、尚未出界的单位 | PR 为 0，Presence 保留 |

舰船 `MountTarget` 不算独立飞机 Presence，也不单独计算 PR；它只进入雷达/命中与性能工作量。不得为了让友军支援入场而取消玩家已购买的支援：先抑制低优先级 Global 生成、命令闲置 Global 敌机撤离，并对非关键单位降 LOD；支援只在找不到合法入场点时延后重试。

### 2.4 Pressure State 与倍率

| 状态 | 条件 | PR 倍率 |
|---|---|---:|
| `DORMANT` | 远距巡逻、只与气氛/第三方交战、尚未进入玩家 Encounter | `0.0` |
| `APPROACHING` | 已被 Encounter 接纳，正在向玩家/任务接触区入场 | `0.5` |
| `ACTIVE_PLAYER` | 正在追踪、拦截、守护玩家攻击的目标，或正在对玩家小队执行攻击 | `1.0` |
| `ACTIVE_ALLY_ONLY` | 只与临时 ALLY 交战，玩家小队不在当前交战链 | `0.25` |
| `DISENGAGING` | 刚停止主动接敌，仍在危险空间内；最多 4 秒 | `0.5` |
| `RETREATING` | 明确飞向出界点/已关闭主动攻击 | `0.0` |

判为 `ACTIVE_PLAYER` 的任一充分条件：

- 当前 AI 目标属于玩家小队；
- 正在锁定或已有在途武器指向玩家小队；
- 持有 Lethal Slot；
- 属于玩家当前主动攻击的任务目标护卫，且位于任务交战半径内；
- Encounter 的脚本攻击已明确指定玩家小队。

阵营转换为 PLAYER/ALLY、投降、黑客成功、来源退役或进入 EGRESS 时，当帧释放敌方 PR 与 LS；Presence 到实体真正释放时才减少。

### 2.5 单位 Pressure Cost

阶段 0 只记录、不用于生成许可。普通注册表单位在未声明显式 `pressure_cost` 时使用迁移公式：

`pressure_cost = clamp(0.75 + 0.25 × token_cost, 1.0, 3.0)`

| 类型 | 显式规则 |
|---|---|
| 普通常规 Aircraft | 使用迁移公式；以后逐行显式化后不再读 Token 推导 |
| `support_body=true` 的 Snowblind/DEADAIR 本体 | `1.5`；护卫各自另算 |
| Sentinel 指挥机 | 本体按显式值 `2.25`；固有护卫各自另算；后续补充单位同样另算 |
| 非 BOSS 王牌成员 | `2.5 / 架`；特殊队长可显式 `3.0` |
| BOSS 本体 | 不进入普通 PR；由独立 Boss Threat 表达 |
| BOSS Adds | 必须显式声明，未迁移的 BOSS 暂由旧逻辑拥有且不可同时由 Director 生成 |
| 无武装战略目标 | `0.0` |
| 地面/舰船正式任务目标 | 阶段 0 只观测；在逐任务迁移时按其真实对玩家火力显式登记，不把挂点逐个相加 |

该公式只解决迁移可观测性，不代表最终平衡值已经批准。进入阶段 2 前必须用完整局 TTK、在途导弹、玩家受击与单位存活遥测确认显式成本表；因此本 spec 当前 `reconstruction_complete=false`。

### 2.6 Pressure Target

当前 Global Package 生成权威公式：

```text
base_pr = 4.0 + 0.75 × (player_squad_size - 1)
heat_mult = 0.80 + 0.006 × RoeDirector.heat
encounter_mult =
    travel/global: 1.00
    1-star zone:   1.00
    2-star zone:   1.10
    3-star zone:   1.20
pr_target_raw = base_pr × heat_mult × encounter_mult
PR_TARGET = clamp(pr_target_raw, 3.0, 12.0)
SPIKE_CAP = PR_TARGET × 1.30
```

临时 TEAM_ALLY 数量、AWACS buff、气氛友军与被黑单位一律不进入 `base_pr`。它们是玩家获得的战场收益，不得暗中换算成更多敌人。

临时增压调参不得改写该公式来追逐单次 Package 抽样结果。Lv12 / N=4 / Heat≈78 的固定重复样本中，
把直属僚机步长提高到 `1.40` 只令三次 ACTIVE 中位从 `2.33` 到 `2.40`，且热样本因抽到四机 Flight
达到 `P90=7`；因此撤回该全局放宽，改由 §2.9.1 的开局完整 Element 稳定前移一名攻击者。

玩家直属僚机变化：

- 减员导致目标下降时，在 `3.0 s` 内线性降到新目标；立即禁止基于旧目标补怪。
- 局中增员导致目标上升时，最高每 `10 s` 增加 `1.0 PR` 的可填充目标；不得立即刷出对应差额。
- 临时友军到场/阵亡不改变目标，也不触发增减员平滑器。

### 2.7 Lethal Slot

```text
LS_CAPACITY = clamp(
    2.5
    + 0.35 × (player_squad_size - 1)
    + heat_slot_bonus,
    2.5,
    6.5)

heat_slot_bonus =
    Heat < 30: 0.0
    Heat < 60: 0.5
    Heat < 80: 1.0
    else:      1.5
```

| 动作 | Slot cost | 持有期 |
|---|---:|---|
| 普通跟踪、包抄、争高度、雷达锁定 | `0.0` | 不申请 |
| 导弹最终发射承诺 | `1.0` | 从批准发射到离架；现有“同时飞向玩家导弹上限 3”继续作为独立硬门 |
| 机炮攻击 Run / 已承诺梭射 | `1.0` | 从进入最终火力窗到梭射结束或放弃 |
| 多弹高威胁特殊攻击 | `1.5` | 由技能/BOSS 适配器明确释放 |
| 普通 BOSS 专属攻击 | 独立 Boss Threat | 不占普通 LS，仍须遵守自身错峰契约 |

Slot 公平性：普通持有者释放后 `3.0 s` 内同机优先级降低；等待时间越长优先级越高。已经满足发射几何的攻击者优先于尚未形成几何者，但 scripted critical、王牌显式攻击拥有更高优先级。Slot 不允许取消已经离架的武器或中途截断已发射的机炮弹。

### 2.8 Encounter 数据契约与优先级

每个 Encounter 必须声明：

```text
id, type, priority, owner,
pressure_reservation, presence_reservation,
spawn_policy, retreat_policy, cleanup_policy,
can_overlap, recovery_s, phase
```

| 类型 | 优先级 | 默认叠加规则 |
|---|---:|---|
| `BOSS` | `100` | 禁止 Global/Mission/ACE 新生成；只接纳 BOSS 本体、已批准 Adds 与 critical story |
| `STORY_CRITICAL` | `90` | 可覆盖 Recovery，但仍守 Presence hard cap 与合法出生点 |
| `ACE` | `80` | Global 让位；任务正处于 CONTACT/CLIMAX 时排队，除非总量不越 Spike Cap |
| `MISSION` | `60` | 占用当前 PR；Global 降到余量，不额外叠完整预算 |
| `ZONE` | `50` | 战区驻守/三级威胁；同一区任务共用一份预算 |
| `GLOBAL` | `10` | 永远先让位；只填其它 Encounter 未使用的缺口 |

友军支援继承所属 Encounter 的生命周期，但不申请敌方 PR：战区 F-86/A-10 属于对应 MISSION；王牌 F-15 属于 ACE；AWACS 属于独立 SUPPORT Presence；气氛友军属于 ZONE Presence。

### 2.9 Encounter Package

Global 随机生成从逐机 roll 迁移为“战术意图 × 编成等级”共同解析 Package；具体机型继续由当前响应等级、解锁/退役、实例上限和角色池筛选。

三层概念必须分开：

```text
Encounter Package    一次共同入场、共同目标域和共同生命周期的遭遇包
└─ Element            一个可独立机动/重整的战术分队
   └─ Squad / Solo    一个长机和兼容僚机，或一架明确的独行机
```

- 一个 Package 可以包含多个 Element；多个 Element 共享 Encounter id、入场方向、接触区与目标集合，但各有长机、阵型和重整状态。
- 普通常规 Squad 上限为 4 架。需要更大画面时增加 Element，不把 6～8 架焊成一个迟钝的大 Squad。
- 同一 Element 的成员必须具有兼容的航速、机动与战术职责；角色差异过大的单位拆成不同 Element。
- Snowblind/DEADAIR 本体是 Package 支援核心，不再充当普通战斗机 Squad 长机；两架护卫组成自己的 `ESCORT_SCREEN` Element。
- Sentinel 是显式例外：其机制要求 Sentinel 成为 Command Squad 长机，`5 MQ-109 + 1 Aegis` 走 `ORBIT_GUARD`，且初始固定槽位必须完整校验。
- Package 必须按 `Resolve → Validate → Reserve → Instantiate → Wire → Verify → Commit` 原子提交；任一 required slot 缺失则整包回滚，禁止半包进入战场。

#### 2.9.1 玩家编队规模软响应（保留既有系统）

编成等级继续以 [squad-xp-threat-balance](squad-xp-threat-balance.md) §2.6 为唯一数值权威。Director 不新建第二张权重表，也不把它改成硬镜像：

| 玩家直属机数 N | 单机 Package | 双机 Element | Flight Package（总计 3～4 机） |
|---:|---:|---:|---:|
| 1 | 60% | 30% | 10% |
| 2～3 | 40% | 35% | 25% |
| 4～6 | 25% | 35% | 40% |
| 7～9 | 15% | 25% | 60% |

- 每档仍独立乘 `0.85～1.15` 扰动；机型 `spawn_min/max`、Token、实例上限、冷却、PR、Presence 与合法出生点拥有最终否决权。
- 抽到 Flight 后总数仍按既有 `3 机 65% / 4 机 35%` 解析。3 机默认一个三机 Element；4 机可以是一个四机 Element，也可以按主题拆成两个双机 Element。
- 当 `N >= 4`、`Heat >= 60` 且 Package 允许多 Element 时，4 机 Flight 首轮候选按 `60%` 解析为 `2+2`、`40%` 解析为单个四机 Element；条件不满足时保持单个四机 Element。该比例在阶段 0 遥测与 Visual playtest 后才能转 approved 数值。
- Resolve 阶段在候选定案前读取当下 `SPIKE_CAP - current_pr`：若 Flight 意图放不下，可解析为同机型的最大完整 Element，但不得低于该机型 `spawn_min`。这是候选解析，不是 DENY 后拆包或补债；一旦进入 Validate，整包只能全成或全败。
- `N` 只在生成请求解析时读取；已出场 Package 不因玩家增员/减员被拆分、补员或删除。临时 TEAM_ALLY、AWACS、战区支援和阵营转换友军不计入 `N`。
- 开局 `OPENING_GARRISON` 仍只提交一个完整 Element：`N < 4` 保留既有随机 `2～3` 架，`N >= 4`
  固定为 3 架。它只把第三名攻击者前移，不改变后续 PR target、Package 冷却或 Spike Cap。

#### 2.9.2 Element 凝聚策略

| 策略 | 默认对象 | 战斗合同 |
|---|---|---|
| `FORMATION_ASSAULT` | 普通敌方/友方战斗机 Element | 长机拥有导航与主攻击几何；僚机优先保持槽位并从阵位机会开火；只在明确 break 条件下短时脱队 |
| `ESCORT_SCREEN` | Snowblind/DEADAIR 护卫 | 护卫自己组成 Squad，以支援核心为 protectee；核心不成为战斗机编队长机 |
| `ORBIT_GUARD` | Sentinel 固有护卫 | 维持专属环绕、屏障和召回逻辑；Command Squad 固定编成原子生成 |
| `LOOSE_SOLO` | 精英独行机、主题独立截击手 | 共享 Package 目标域与生命周期，但不占用其它 Element 的阵型槽位 |

| Package | Heat | 编成 | 角色约束 |
|---|---:|---|---|
| `PATROL_LIGHT` | `0～100` | 1 个 2 机 Element | legacy/regular，至少一架非 special；`FORMATION_ASSAULT` |
| `DOGFIGHT_ELEMENT` | `20～100` | 1 个 2～4 机 Element | `role=dogfight`；规模服从编成等级 |
| `INTERCEPT_ELEMENT` | `30～100` | 1 个 2 机 Element | `role=intercept`；`FORMATION_ASSAULT` |
| `ELITE_SINGLE` | `45～100` | 1 个 Solo Element | Token ≥7，遵守实例上限与独立冷却；`LOOSE_SOLO` |
| `EW_ESCORT` | `50～100` | 1 支援核心 + 1 个 2 机护卫 Element | 复用 Snowblind/DEADAIR 完整包契约；`ESCORT_SCREEN`；不得缺护卫生成 |
| `MIXED_FLIGHT` | `60～100` | dogfight 双机 Element + intercept 双机 Element | 两个紧密编队共同入场，分别保持战术身份；总 PR 必须放得下 |

每个 Package 的真实 PR 是成员显式成本之和，不另收编成税。`current_pr` 低于目标至少 `1.5 PR` 才可尝试生成；通过该缺口门后，完整 Package 只允许进入 `SPIKE_CAP = PR_TARGET × 1.30` 以内，`1.5 PR` 不是整包越过目标的上限。Resolve 后仍放不下、实例上限不足、特殊单位冷却中或出生点非法时，本轮机会作废；不得换成贴脸 spawn，也不得形成债务。最近 3 个 Package 内，同包第二次权重乘 `0.25`，连续第三次权重为 `0`。scripted Encounter 可豁免防重复，但必须显式声明。

## 3. 行为与公式（How）

### 3.1 Director 主循环

```text
每 0.5 秒或关键事件标脏时：
1. 读取 SurvivorMode 已有 typed aircraft/combat-unit cache；不扫描场景树。
2. 净化对象：Variant → TYPE_OBJECT → is_instance_valid → 类型/字段。
3. 更新 Encounter phase、Recovery 与 reservation。
4. 为每个敌对单位派生 Pressure State 与成本；为友军/撤离单位记 Presence。
5. 按优先级分配 PR reservation；高优先级先拿，Global 只得余量。
6. 计算 PR deficit、Presence/Token/实例上限、Package 冷却与出生合法性。
7. 只向已迁移来源返回 ADMIT / DEFER / DENY；未迁移来源保持旧 authority。
8. 更新 LS lease 与确定性 LOD 分类。
9. 仅在状态变化或 5 秒周期输出 telemetry。
```

Director 不创建单位，不直接 `queue_free()`，也不写单机战术状态。它给各来源返回许可、reservation 与撤离建议；生成仍由现有 spawner/mission/event/BOSS 工厂完成，撤离仍走各自真实物理离场入口。

### 3.2 标准 Encounter 生命周期

| Phase | 入口 | Director 行为 | 出口 |
|---|---|---|---|
| `AVAILABLE` | 内容可被选择/触发 | 0 PR、0 实体；普通未关注战区保持战略层 | 玩家选择/进入/被三级威胁影响 |
| `APPROACH` | 现有 6 秒预告或事件入场演出 | 预留 PR，Global 开始让位；不贴脸生成 | 预告结束且出生合法 |
| `CONTACT` | 第一组身份编成入场 | 接纳任务初始 Package；展示任务差异 | 首批真实接敌 |
| `SUSTAIN` | 正常任务交战 | 只有本 Encounter PR 低于目标至少 1.5 才考虑增援 | 任务高潮或终态 |
| `CLIMAX` | 每 Encounter 最多一次 | 使用 Spike Reserve，最长 20 秒 | 回落或终态 |
| `RESOLVED` | 成功/失败/取消已确定 | 当帧禁止新 spawn/增援，释放未用 reservation | 清理命令已下达 |
| `CLEANUP` | 现有单位撤离/保留/转换 | 撤离者 PR=0、Presence 保留；可见单位不消失 | 非持久单位已清理 |
| `COMPLETE` | 清理合同满足 | 进入 Recovery；删除 Encounter 跨帧引用 | 恢复窗结束 |

首版不要求改写 `ZoneMission` 的内部状态；适配器把现有事件映射到以上 phase。任何来源只有在迁移完成后才由此状态机拥有生成许可。

### 3.3 Pressure Reservation 与让位

任务不是在旅途压力之上再加完整预算。例：当前 `PR_TARGET=8`、Global 已占 8，任务申请 5，则目标构成为 `Mission=5, Global≤3`。

Global 让位顺序：

1. 最远且未接敌的 DORMANT/ONSTATION 巡逻队；
2. 没有 LS、没有任务身份、未被玩家点名的 DISENGAGING 单位；
3. 没有 LS、未被玩家点名的 ACTIVE Global 单位；只下达脱离，不删除；
4. 玩家点名目标最后让位，并必须真实撤离。

Director 不撤出任务 TGT、scripted persistent、BOSS、王牌成员或玩家当前点名目标来给低优先级内容腾位。

### 3.4 Recovery 与无 Spawn Debt

- 任务/王牌进入 COMPLETE 时创建 10 秒 Recovery。
- Global 敌对 Presence 从非零变为零时创建 10 秒 Recovery；暂时失锁、从玩家切换去打 TEAM_ALLY、或全部进入 APPROACHING/DORMANT 不算终态，不能误触发恢复窗。
- Recovery 内 Global、随机 ACE 与普通增援均 `DEFER`；已有敌人、在途武器、玩家主动追击与 scripted critical 继续。
- 玩家在 Recovery 内触发新普通任务：APPROACH/无线电可以开始，CONTACT 的新敌压等 Recovery 结束；若任务实体已因正式规则存在，只禁止其新增增援，不删除。
- BOSS 转场可覆盖 Recovery，但旧任务必须先 RESOLVED 并停止增援。
- 被 DEFER/DENY 的 timer 机会直接丢弃。Recovery 结束后重新随机 10～18 秒 Global cooldown，仅根据当下 PR 缺口判断。

### 3.5 友军支援到场

#### 战区 F-86 / A-10

- 仍只在任务真实触发后按现有授权、每局 fighter/attack 各一次、2～4 架编成生成。
- 支援生成前向父 MISSION 登记 Presence；不增加 PR target，不增加 Heat，不恢复被压低的 Global 配额。
- 支援在途中只与父 Encounter 的目标交战；不得跨 Encounter 把远处敌军拉进当前战斗。
- 任务完成/失败/reset/BOSS 锁区时当帧结束支援的战斗贡献，沿现有 EGRESS 真实飞出；受击后的 4 秒自卫窗口保留。

#### 王牌 F-15

- 属于 ACE Encounter 的友军 Presence；只攻击本次王牌成员。
- 到场不允许 ACE 或 Global 因“我方多两机”提高 PR/LS；终态后与王牌事件共同撤离。

#### AWACS

- 只记 1 个临时 ALLY Presence 与性能成本；buff 不换算成更多敌人。
- BOSS 解锁、到站时长结束或被击落时走现有撤离/终态，不产生补刷债务。

#### 气氛友军与阵营转换

- 气氛 SPG/AH-64/舰船只占 Presence/性能，不进入玩家小队规模，也不抬 PR target。
- WhiteTea 投降、黑客转换等在当帧释放敌 PR/LS，之后作为临时 ALLY Presence；不得用转换导致的 PR 缺口立即补怪，至少等当前 Package cooldown。

### 3.6 友军到场与性能冲突

支援是已购买/已触发的内容，Director 不能以“性能不足”为理由静默取消。处理顺序：

1. 停止/延后 Global 非关键生成；
2. 让闲置 Global 巡逻队进入 PRESSURE_RELEASE/EGRESS；
3. 对 §3.7 中较低优先级飞机使用更低 LOD；
4. 支援仍按合法镜头外点整队入场；若没有合法点，0.5 秒后重试，不消耗权益；
5. 仍不允许越过 hostile 36/48 内容 cap 或在玩家画面内凭空生成。

### 3.7 Director LOD 分类

Director 只输出分类；最终 `lod_level/visible/physics_process` 写入继续服从 [runtime-performance-budget](runtime-performance-budget.md) 与既有 LOD authority，避免新增并行写者。

| LOD 类 | 对象 | 允许降级 |
|---|---|---|
| `IMMUNE` | 玩家小队、BOSS、王牌、Sentinel、当前 LS 持有者、屏内任务核心 | 不降 AI 决策；保持现有豁免 |
| `CORE` | 屏内或玩家 1500m 内的当前 Encounter 单位 | 位置/heading/bank 保持 60Hz；慢决策沿已有 crowd divisor |
| `SUPPORT_TRANSIT` | 镜头外的战区 F-86/A-10、王牌 F-15、AWACS 入场/撤离 | 可用 LOD2 与更低慢决策频率，但必须持续物理位移，禁止冻结在航线上 |
| `GLOBAL_PATROL` | 未接敌的旅途驻空/巡逻队 | 屏外远距可走现有 LOD2/冻结；被观察或进入 Encounter 当帧恢复 |
| `RETREATING` | 已释放 PR、真实出界中的非关键飞机 | 优先 LOD2；保留位移、边界和受击自卫所需最小更新 |
| `ATMOSPHERE_FAR` | 不直接影响玩家的远距气氛演员 | 使用其既有 2Hz/伤害 LOD，不新建逐机逻辑 |

降级顺序固定为 `RETREATING → GLOBAL_PATROL → SUPPORT_TRANSIT → 非核心 APPROACHING`。不得降低玩家、BOSS、王牌、Sentinel、屏内当前任务核心或 LS 持有者的 LOD 来过性能门。

### 3.8 Attack Slot 接入边界

- AI 目标选择、BFM 计划、包抄、雷达锁定继续运行；只在导弹最终发射许可与机炮承诺梭射入口查询 Slot。
- 没有 Slot 时 AI 保持几何或转入重整，不清空目标，不停物理。
- 当前已在途导弹继续由既有 `MAX_MISSILES_TARGETING_PLAYER=3` 管理；Slot 不替代该门。
- 特殊多锁、ACE 和 BOSS 必须逐来源审计，未迁移时使用旧 authority；禁止一半武器走 Slot、一半绕过却宣称全局上限已生效。

### 3.9 多 Encounter 与 edge cases

| 情形 | 规定 |
|---|---|
| 玩家把旧敌人拉进新战区 | 旧敌保留原 Encounter id；总 PR 共享，不因跨区复制预算 |
| 两个战区同时 triggered | 当前选中/玩家所在战区先分配；另一战区保留实体与 Presence，但新增敌压延后 |
| Mission + ACE | Mission 在 CONTACT/CLIMAX 时 ACE 排队；否则 ACE 可在 Spike Cap 内接入并令 Global 让位 |
| Mission + BOSS 解锁 | Mission 立即 RESOLVED，停止增援并清理；BOSS Engage 等清理命令发出后开始，不要求所有实体瞬间消失 |
| ACE + Global | ACE 优先，Global 只占余量；不得 `Global full + ACE full` |
| BOSS Adds 无限生成 bug | Boss Add reservation、Presence hard cap 与来源实例上限三重拒绝；被拒绝的请求不欠账 |
| 玩家 30 秒不杀敌 | PR/Presence 满后不再增长；Heat 可按现有规则衰减 |
| 玩家 10 秒击杀 8 架 | 只在 cooldown 与 deficit 同时满足时补一个 Package，不按击杀数逐架补齐 |
| 玩家追击撤离敌人 | 敌人仍可被击杀，Presence 保留、PR=0；玩家点名保护禁止直接删除 |
| 所有出生点非法 | 本轮作废；不贴脸、不越界、不积债 |
| 暂停 / 慢动作 | 只按游戏 delta 推进；暂停零变化，慢动作不会因墙钟时间多刷 |
| 边界补给 | 沿现有 Token bonus/游戏规则生效；不得造成 Spawn Burst |
| 玩家直属僚机瞬间全灭 | 3 秒平滑下调 PR，立即停止按旧目标补怪；已在途武器不删除 |
| 玩家突然获得 4 架直属僚机 | PR 可填目标每 10 秒最多 +1；不立即刷出等额敌机 |
| 临时友军突然全灭 | PR target 不变；不触发“补偿性”敌人刷新 |
| 阵营转换 / 投降 | 当帧释放敌 PR/LS；对象有效性按 Variant 链检查；不重复回收 Token |
| 任务终态后对象同帧释放 | 下一 SceneTree 帧与下一次 2Hz Director tick 均不得访问 freed object |
| 场景退出/新局 | 清空所有 Encounter、lease、WeakRef/实例 id、cooldown 与 telemetry 状态；不跨局保留 |

### 3.10 编队优先战斗流程

普通 `FORMATION_ASSAULT` Element 的优先级为：

`生存/边界安全 > 玩家或脚本强制命令 > Element 战术动作 > 保持/重整编队 > 个体自由追击`

1. **FORM_UP / INGRESS**：长机独占入场航线；僚机保持真实物理阵位，不逐机重复寻路。
2. **FORMATION_ATTACK**：Element 只选一个主目标/攻击轴。长机形成攻击几何，僚机保持 `SQUAD_FOLLOW`，从阵位使用既有机会火控；不能因为长机获得 `combat_target` 就全员同拍 `clear_formation()`。
3. **TACTICAL_BREAK**：仅允许下列原因脱队：本机真实导弹规避、边界/碰撞安全、Package 明确分配的包夹/守后角色、保护目标遭直接攻击、玩家/脚本强制点名。普通“附近还有一架敌机”不足以解除阵型。
4. **REFORM**：break 原因结束后，成员先走既有物理归队；归队前不得重新扫描另一个自由目标。Element 达到既有阵位容差后，才开始下一轮编队攻击。
5. **LEADER LOSS**：沿现有 `Squad.cleanup/_sync_member_bindings` 选继任长机；幸存者进入 REFORM，不在换帅帧各自转巡逻。

多个 Element 的协同发生在 Package 层：Package 可以让 A Element 正面接触、B Element 侧向截击或守后，但每个 Element 内部仍保持自己的阵型。不同 Element 可被分配到不同玩家直属机，避免所有敌人只压当前操控机；同一 Element 内保持共同主目标。

Lethal Slot 仍按单次真实武器承诺记账；Package/Element 攻击窗只决定“谁正在形成攻击几何”，不凭空合并弹道，也不让全队瞬移或同步转向。

## 4. 结构与组成（Structure）

### 4.1 Authority 边界

- `EncounterDirector`：`RefCounted` 集中账本；由 `SurvivorMode` 持有并以 2Hz tick，不新增 Node `_process`。
- `SurvivorMode`：继续生产同帧 typed aircraft/combat-unit cache、持有相机/LOD authority，并转发任务/BOSS/阵营事件。
- `SurvivorSpawner`：继续拥有 Token、敌池、Package 实例化和物理入场；迁移后每次 Global 生成先请求 Director。
- `ZoneMission`：继续拥有任务目标、友军支援与任务终态；只把 Encounter phase/成员/增援请求登记给 Director。
- `EventDirector` / ACE / BOSS：逐事件适配；未迁移前不受 Director 生成 authority，避免双写。
- `RoeDirector`：继续是 Heat 单一真源；Director 只读 `heat`，不复制增长/衰减逻辑。
- `PerformanceWorkloadSnapshot`：按成本域提供计数；Director 不读取瞬时 FPS 决定敌人数量。

### 4.2 数据对象

```text
EncounterSnapshot
  encounter_id, type, phase, priority
  pressure_reserved, pressure_current
  presence_current, ally_presence
  spawn_suppression_reason, recovery_remaining

DirectorSnapshot
  heat, pr_target, pr_current, spike_cap
  hostile_aircraft, all_aircraft, temporary_allies, retreating
  ls_capacity, ls_used
  active_encounters[]
  lod_class_counts{}
```

跨帧成员只保存实例 id 或 WeakRef；读取时执行 `Variant → TYPE_OBJECT → is_instance_valid → 类型`。Director 不保存 typed Object 形参等待下一帧调用。

### 4.3 Telemetry

EventLogger 每 5 秒或跨状态时记录：

```text
heat, pr=current/target/spike,
presence=hostile_aircraft/all_aircraft/allies/retreating,
slots=used/capacity,
encounters=id:type:phase:reserved,
spawn=admit|defer|deny + reason,
lod=immune/core/support/global/retreating
```

Telemetry 不上玩家 HUD，不逐单位逐秒写日志；同批单位日志按 Encounter 合并，避免长局尖峰。

## 5. 验收标准（Acceptance / Litmus）

### 5.1 功能与生命周期

- [x] Heat 只有 `RoeDirector.heat` 一个真源；Director 不自行增长/衰减 Heat。
- [ ] 阶段 0 观察模式的启用/关闭不改变随机序列、Token、生成数量、AI 目标、武器许可或任务终态。
- [ ] 活跃任务/ACE/BOSS 开始时 Global 让位，总 PR 不按来源完整相加。
- [x] 被抑制的生成机会不累计；Recovery 后不会成批补刷。
- [ ] 任务成功/失败/取消当帧禁止新任务增援；非持久单位按现有可见性和物理撤离规则收束。
- [ ] 玩家点名/锁定的撤离敌机不会被直接删除，仍可追击和击杀。
- [ ] 直属小队增减员平滑符合 §2.6；临时 ALLY 到场/阵亡不改变 PR target。
- [x] 固定种子编成抽样继续复刻 `N=1: 60/30/10` 与 `N=9: 15/25/60` 的单机/双机/Flight 趋势；Director 不建立第二套相互漂移的权重。
- [ ] 普通敌方 Element 接敌后不会全员同拍解除阵型；非规避/非显式战术时间中，至少 `70%` 的 CONTACT 时长处于 `FORMATION_ATTACK` 或 `REFORM`，该候选门由阶段 0 遥测与 Visual playtest 校准后批准。
- [ ] 4 机多 Element 样本真实存在两个 Squad/两个长机；两支双机队共享 Encounter 目标域但分别保持阵型、可被分配到不同玩家直属机。
- [x] Snowblind/DEADAIR 的支援核心不再成为普通护卫 Squad 长机；Sentinel 初始包精确验证 `1 Sentinel + 5 MQ-109 + 1 Aegis`，缺任一 required slot 整包不提交。
- [ ] 战区 F-86/A-10、王牌 F-15、AWACS 与气氛友军全部进入 Presence/性能账本，且不抬敌压、不积 Heat。
- [ ] WhiteTea/黑客/阵营转换当帧释放敌 PR/LS，Token 只由既有权威回收一次。
- [x] Attack Slot 不妨碍跟踪/包抄/雷达锁定，只限制最终致命攻击承诺；已有在途武器不被取消。
- [ ] BOSS 解锁时旧任务停止增援并发出清理命令；每个 BOSS Adds 只有一个生成 authority。
- [ ] 暂停、慢动作、边界补给、非法出生点、场景退出和 freed-object edge cases 符合 §3.9。
- [ ] 新的 success/failure/cancel/cleanup 分支进入 `lifecycle_gauntlet`，终态后至少继续一帧并跨过下一次 Director tick。

### 5.2 性能合同

- [x] Director 为单个 2Hz O(N) 缓存遍历；不新增逐机 Node/process，不调用 `get_children()`，不在 `_draw` 工作。
- [x] 工作量统计复用 `CombatUnit.all_units` 权威缓存；与 [runtime-performance-budget](runtime-performance-budget.md) 的快照阶段不建立第二份场景树扫描。
- [ ] 非关键飞机按 §3.7 可降低 LOD；玩家、BOSS、王牌、Sentinel、当前 LS 持有者和屏内任务核心保持豁免。
- [ ] 友军支援入场/撤离在 LOD2 下仍持续真实位移，不会冻结在地图外或破坏编队。
- [x] C1 `battlefield_atmosphere_stress_36 30 300 Shadow Visual` 改前/改后各 3 次取中位：`frames_below_60=0`、`p1_fps>=60`、`worst_frame_fps>=60`，镜头巡检、真实 AI/伤害/生成/标签/尾迹/爆炸合同完整。
- [x] 涉及全局扫描/LOD 时追加 C2 `battlefield_atmosphere_stress_48_24km 30 300 Shadow Visual` 改前/改后各 3 次，门槛同上，并记录 all_aircraft/combat_unit/友军/弹丸数量。
- [ ] 定向 `zone_air_support`、ACE 支援、AWACS 和混合战区样本覆盖支援到场、在站、撤离三阶段；Headless 只证明状态/CPU/泄漏，不冒充 draw 性能。
- [x] 运行 `all 1 300 Shadow Headless`、LifecycleGauntlet 与自动运行时错误门；退出码 86 视为失败。

### 5.3 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 2026-08-30 现状审计：Spawner / ROE Heat / ZoneMission 支援 / ACE F-15 / AWACS / LOD | 原方向成立；发现已有 Heat 真源、友军支援不计 Token 但需要 Presence/性能记账、原草案迁移面过大 |
| E1 focused | `roe` 63/63；`weapon` 34/34；`waypoint_fire` 30/30；`spawn_pool` 102/102；`rejoin` 基线不变 | PR/Spike、N 软响应、N≥4 开局三机完整 Element、编队机会火力、Global 真清空 Recovery、Snowblind 与 Sentinel 原子包均通过；反向归队 2000px/850kmh 仍是已知 >30s 极端样本 |
| E2 集成 | `all 1 300 Shadow Headless`；LifecycleGauntlet；seed 42 / Lv12 / N=4 / 120s `encounter_difficulty` | `all` 90 组失败 0；lifecycle 82/82。首轮重构把旧机制 avg ACTIVE `4.24→2.33`；v4 最终三次为 `2.87 / 3.15 / 3.19`，中位 `3.15`，P90 中位 `5`、峰值中位 `5`、首次接敌均 `5.27s`、unique/avg alive 中位 `5/4.33`、敌方导弹发射中位 `10`、编队保持中位 `100%`。相对旧机制平均攻击者仍低约 `26%`；自动长机未下攻击命令，`kills=0` 不作为真人 TTK 结论 |
| E3 Visual | C1/C2 各 30s×3 基线 + v4 各 1 次回归，RTX 3080 / Godot 4.7.2 / Shadow Visual | 原三次 C1 中位 `avg 343.02 / p1 220 / worst 60.73 / <60=0`，C2 中位 `avg 357.44 / p1 220 / worst 60.68 / <60=0`。v4 回归受当前 120 FPS 上限钳制，不做平均值 A/B：C1 `avg/p1/worst=120/120/116.84`，C2 `119.97/120/77.97`，两者 `<60=0`、8/8 镜头段与正式负载合同完整；无需额外降低飞机 LOD |
| E4 完整局 | 12～20 分钟实玩：冷场、峰值、支援到场、任务→ACE→BOSS | 待补 |

### 5.4 文档与 seam

- [ ] 已知 seam：LOD 写者、玩家引用 chokepoint、任务终态缓存、BOSS Adds authority 均已审计并登记必要变更。
- [x] `verify_player_ref_holders.py`、`verify_doc_anchors.py`、`verify_docs.ps1`、`git diff --check` 通过。
- [x] 本 spec 已登记 `_INDEX`；状态/重建标记一致；当前文档无失效相对链接。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 0 — 只读观测层与性能基线

- [x] 新建 `EncounterDirector` RefCounted，读取现有缓存、Roe Heat、Token 与任务/事件状态，产出压力快照。
- [ ] 所有生成与武器路径保持旧行为；加纯函数测试证明 observe on/off 行为一致。
- [ ] 登记战区 F-86/A-10、ACE F-15、AWACS、气氛友军与阵营转换 Presence。
- [x] 输出 5 秒节流 telemetry；覆盖对象释放与新局清空生命周期。
- [ ] 先跑 focused，再跑 C1/C2 三轮 A/B 与 `all`；若观测层越过性能回退门，先优化/回滚，不进入阶段 1。

### 阶段 1 — Global 抑制、Recovery 与无债务

- [x] Global spawner 每轮先请求 Director；把现有“任务中停刷/BOSS 停刷”映射为统一抑制原因。
- [x] 接入任务/ACE 终态 10 秒 Recovery，生成失败/抑制机会直接作废。
- [ ] Global 压力让位只复用既有 EGRESS/物理撤离，不直接删除可见单位。
- [ ] 定向验证任务结束 1 秒进新区、Mission+ACE、ACE+Global、BOSS 解锁四条链。

### 阶段 2 — Global Pressure 与 Package

- [ ] 用阶段 0 完整局遥测校准并批准显式 `pressure_cost`；不得直接把迁移公式当最终平衡。
- [x] 接入普通 Solo/Element/Mixed Flight 与 EW/Sentinel 主题 Package；保留 Token/实例/冷却硬门与原子提交。
- [x] 复用 `SurvivorData.pick_enemy_formation_class/pick_enemy_flight_size` 作为玩家 N 软响应真源；把结果解析为 Solo / 单 Element / 多 Element，不复制概率常量。
- [x] 接入 `FORMATION_ASSAULT`：目标选择和攻击轴提升到 Element，普通僚机从阵位机会开火；break/reform 复用现有 Squad/Formation 物理与生命周期。
- [x] 把 Snowblind/DEADAIR 改为“支援核心 + 护卫 Squad”，把 Sentinel 固定槽位改为原子验证/回滚；覆盖缺护卫后的单次修复与不重复补员。
- [x] 只让 Global 使用 PR admission；任务/事件仍旧 authority，避免一次迁移过宽。
- [ ] 验证 30 秒无击杀、10 秒 8 击杀、非法出生点、直属小队增减员与无 Spawn Debt。

### 阶段 3 — Lethal Slot

- [ ] 建 LS lease 纯函数与公平性/冷却测试。
- [x] 先接普通敌机导弹最终发射许可与机炮承诺梭射；保留在途导弹上限 3。
- [ ] 分别审计多锁 Schemer、特殊攻击、ACE 和 BOSS；未迁移来源明确 bypass，不宣称全局完成。
- [ ] 真实战场检查“整队仍在机动、但致命攻击错峰”，不得出现无 Slot 全员发呆。

### 阶段 4 — 任务、友军、ACE 与 BOSS 逐项迁移

- [ ] 先迁普通空战/地面/机场/海战 reservation，再迁 bomber escort。
- [ ] 战区支援到场优先级与 LOD 接入；临时友军绝不抬 PR target。
- [ ] 迁移非 BOSS 王牌与 F-15 支援；覆盖撤离/投降/阵营转换。
- [ ] 按 Wraith → CSG → Mother Goose → Black Star 顺序迁移 Adds/特殊攻击，每个 BOSS 独立 focused + Visual。
- [ ] 每迁一个来源即删除对应旧生成 authority；禁止长期双写。

### 阶段 5 — 完整局校准与收尾

- [ ] 12～20 分钟完整局记录 FSR、TTK、玩家受击、在途导弹、PR/LS/Recovery 占比与支援存活。
- [ ] 只根据完整局证据调整 PR cost、target、Package 权重和 Recovery；不顺手改 HP/DPS。
- [x] 跑 C1/C2、`all`、LifecycleGauntlet 与文档校验；任务/ACE/BOSS 专项仍随阶段 4 补齐。
- [ ] 更新 §7、reference 索引和证据；人工 playtest 通过后转 `done`。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| Director 主逻辑 / 快照 | `scripts/survivor/encounter_director.gd` |
| Heat 真源 | `scripts/survivor/roe_director.gd` |
| Global Token / 敌池 / Package 实例化 | `scripts/survivor/survivor_spawner.gd`、`scripts/survivor/enemy_pool_registry.gd` |
| 任务 / 战区支援生命周期 | `scripts/survivor/zone_mission.gd` |
| ACE / F-15 支援 | `scripts/events/ace_reinforcement_event.gd` |
| AWACS | `scripts/events/awacs_support_event.gd` |
| typed cache / LOD authority / 接线 | `scripts/survivor/survivor_mode.gd` |
| 武器最终许可 | `scripts/aircraft/aircraft_weapons.gd` |
| focused / lifecycle / Visual | `scripts/tests/`、`scripts/bench/`、`bench/` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-30 | 1 | 审查原 Encounter Director 草案并重写为分阶段方案：复用现有 Roe Heat；Presence 分离玩法人口与性能工作量；友军支援只占 Presence/性能、不抬敌压；Attack Slot 收窄到最终致命承诺；加入 LOD 降级顺序、迁移闸门、生命周期 edge cases 与 C1/C2 三轮 Visual 性能合同 |
| 2026-08-30 | 2 | 用户定调编队优先：保留既有玩家 N→敌方单机/双机/Flight 软响应；明确 Package→Element→Squad 三层，把 4 机 Flight 可解析为两个双机 Element；普通 Element 默认 FORMATION_ASSAULT，禁止接敌即全员散开；Snowblind/DEADAIR 拆支援核心与护卫 Squad，Sentinel 固定槽位原子校验。 |
| 2026-08-30 | 3 | 完成 Global PR admission、Recovery/无债务、普通与主题 Package、编队机会火力、普通敌机 Lethal Slot 及自动证据。难度基准显示峰值收敛、编队保持提高但无人指挥样本偏松；C1/C2 均守住 60 FPS 硬门，未启用额外飞机 LOD 降级。任务 reservation、阵营转换即时释放、逐 BOSS Adds 与完整局实玩仍保留为阶段 4～5。 |
| 2026-08-30 | 4 | 按用户要求小幅回调平均攻击者。两轮全局增压候选被自动对拍否决：直属僚机 PR 步长 `1.05` 只令 ACTIVE `2.33→2.40`；`1.40` 的三次中位仍为 `2.40`，热样本却因四机 Flight 达到 `P90=7`。最终保留原 `0.75` PR 步长与 `10～18s` 冷却，只让 `N>=4` 的唯一开局驻防固定为三机完整 Element；单机玩家、Heat、Lethal Slot、Spike Cap、Recovery 与编队优先级不变。 |
