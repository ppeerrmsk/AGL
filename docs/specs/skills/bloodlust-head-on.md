---
id: bloodlust-head-on
kind: skill
status: in-progress
schema_version: 1
spec_version: 4
owner: design
depends_on: [skills/bloodlust, skills/berserk-virus, systems/doctrine-unlocks]
reconstruction_complete: true
---

# 血色骑士（嗜血击杀视为对头）

> 嗜血期间，本机击杀敌方飞机均视为对头击杀。2026-09-15 用户确认执行实装与测试，按本规格实施。

## 1. 设计意图（Why）

- 将嗜血来源与对头击杀收益连接起来，形成先进入嗜血、再连续收割的跨流派构筑。
- Litmus：改变可用击杀角度与武器选择，收益通过现有经验、生命与恐惧反馈感知；沿用真实自动开火和嗜血持续时间；只在击杀事件增加判定。
- 风险：移除对头几何门槛会显著提高永久生命与群体恐惧触发率。应作为后续构筑桥接卡，而非开局基础能力。

## 2. 数据定义（What）

| 字段 | 值 |
|---|---|
| id | `bloodlust_head_on` |
| 中文 / 英文 / 日文名 | 血色骑士 / Blood Knight / 血染めの騎士 |
| stat / value / max_stacks | `skill_flag / 1 / 1` |
| category / axis | `survival / knight` |
| rarity | `ADVANCED`（先进，用户指定） |
| scope | 默认全队；每名队员按自己的实际嗜血状态判定 |
| keywords | `bloodlust, head_on, chivalry` |
| build_role / terminal_for | `bridge / [bloodlust]` |
| requires_skill（任一） | `skill_kill_bloodlust, skill_damaged_bloodlust, overload_to_bloodlust, qmaam_boost, squad_revenge, berserk_virus` |
| 装备 / 机型限制 | 无 |
| 获取 | 骑士轴普通卡池；嗜血与骑士学说均解锁后可抽取 |
| 额外里程碑奖励 | 无；沿用普通选卡的轴进度规则 |
| 触发概率 / 冷却 | 100% / 无额外冷却 |
| 新增状态或时长 | 无；消费真实 BLOODLUST 剩余时间 |
| 中文描述 | 嗜血期间，本机击杀敌方飞机均视为对头击杀。 |
| 英文描述 | While Bloodlust is active, all enemy aircraft kills by this aircraft count as head-on kills. |
| 日文描述 | 嗜血状態中、この機体による敵航空機の撃破をすべて正面撃破として扱う。 |

## 3. 行为与公式（How）

### 3.1 致死瞬间快照

```text
嗜血视同对头 = 有效击杀归因属于玩家直属小队飞机
              AND 被击杀目标为敌方飞机（Aircraft）
              AND 击杀者持有 bloodlust_head_on
              AND 致死结算开始时 BLOODLUST 剩余时间 > 0

某对头击杀收益可触发 = 该收益原有几何判定 OR 嗜血视同对头
```

- 在任何本次击杀引发的回血、嗜血授予或刷新之前保存布尔快照；延迟经验结算读取同一快照。
- 第一杀仅使本机进入嗜血时，该杀不会被本技能追溯转为对头；若该杀原本满足几何条件，仍正常算对头。
- 击杀前已处于嗜血时，无论机炮、导弹、火箭、激光、电磁炮或有正式归因的范围伤害，均可生效；不要求朝向、距离或高度。
- 任意真实嗜血来源均有效。F4 强制授予本技能只绕过获取条件，仍需真实 BLOODLUST。
- 队员独立判定：长机嗜血不能替未嗜血僚机获得转换；有效归因的僚机也不借用当前操控机状态。
- 快照只保存值，不缓存跨帧强 Object 引用；击杀者随后状态结束、切控或释放均不改变已成立的分类。

### 3.2 飞机击杀的边界

- 仅覆盖正式算作独立击杀的敌方飞机（Aircraft）；每架飞机的生命周期只能结算一次。
- 地面单位、海上单位及其武器挂点、装甲列车节段不参与转换。BOSS 部件仅在其自身属于 Aircraft 且原玩法认作独立飞机击杀时计入；单纯破件或伴随销毁不新增击杀。
- 无有效归因、自然坠毁、友军击杀、第三方 ALLY 击杀、退出清理不触发本技能。召唤物仅在正式归因已归属本机时继承。
- `no_kill_reward`、BOSS 阶段禁经验等收益限制继续有效；“视为对头”不绕过禁经验或禁永久成长规则。

### 3.3 收益合同

| 消费者 | 转换后的效果 |
|---|---|
| 基础对头奖励 | 当前操控机亲自击杀时，沿用基础 +5 max_hp / +5 hp；僚机不会把它转赠长机 |
| 骑士心脏 | 持有该卡的实际击杀者再获得 +5 max_hp / +5 hp |
| 骑士心脏·历练 | 持有该卡时，对该次原本可获得的击杀经验 ×1.5；沿用既有取整及其它乘区 |
| 寒颤号令 | 持有该卡时，以死者位置为中心，对 1000px（2km）内敌人施加 6s FEAR；沿用统一 FEAR 联动 |
| 正面回旋 / 对锋干扰 | 它们判断交战中的真实几何，继续按原条件执行 |

- 自然对头与嗜血转换是 OR：同一消费者只触发一次。基础奖励与技能奖励原有的独立叠加保留。
- 不凭空授予任何下游技能；本卡本身不修改嗜血的基础回血或其它终端。
- 现状注意：钩子几何是双向 dot >0.7 且距离 ≤1500px；经验及基础成长是双向 dot ≥0.6。本次追加转换分支，零技能时保留各消费者现有规则。

### 3.4 强度评估

- 当前操控机在嗜血期间取得 20 次原本非对头的可奖励敌机击杀，本卡可经基础规则额外提供 +100 最大生命；再持骑士心脏时，共 +200。
- 配寒颤号令时每次敌机击杀都可能刷新范围恐惧；与其它嗜血永久生命终端叠加还会进一步放大成长。
- 按用户指定采用先进档，完整保留 100% 转换效果与嗜血来源前置；实际强度未验证，需记录真实完整局增长与恐惧覆盖。

## 4. 结构与组成（Structure）

- 数据表与现有技能投影负责授予、晚入队、换机和 F4 清单。
- 致死归因层产生嗜血转换快照；击杀钩子、基础成长与经验消费者共享该值。
- 复用现有只接收 Aircraft 的 `StatusEffects.on_kill` 与 `SkillHooks.dispatch_on_kill`，并将同一转换快照接入飞机经验与基础对头奖励消费者。
- 恐惧复用 `AOEBroadcast.apply_status_in_radius`，遵守 SEAM-004；新增共享入口接收可能跨帧的对象时先做 Variant / TYPE_OBJECT / 有效性检查。

## 5. 验收标准（Acceptance / Litmus）

- [x] 无技能、有技能无嗜血、已嗜血、嗜血过期、第一杀触发嗜血、自然对头与转换同时成立六组边界通过。
- [x] 前述武器类别对敌机的击杀、远距尾追击杀都走真实致死入口，并且每项收益只发生一次。
- [x] 嗜血期间击毁地面或海上单位不产生本技能的对头转换及其收益。
- [x] 骑士心脏、历练、寒颤号令与基础奖励分别验证；未持有的卡不产生收益。
- [x] 长机与僚机状态互不借用；晚入队、换机、切控后效果跟随正确归属。
- [x] 击杀者释放或切控后至少推进一个 SceneTree 帧，并跨过延迟经验消费；无重复结算、悬空引用或信号遗漏。
- [x] no_kill_reward、BOSS 禁经验、第三方击杀与伴随破件不能制造成长收益。
- [x] F4 清单覆盖并可强制授予、仍尊重单层上限；技能与三语审计通过。
- [x] focused Shadow → `bench/run.cmd all 1 300 Shadow Headless`，运行时错误门通过；新增终态案例纳入 lifecycle_gauntlet。
- [x] 性能：生产转换判定为击杀事件 O(1)，无新增 tick/draw；寒颤高频联动已跑真实混合战场 Shadow Visual，三组有效对照均 frames_below_60=0，数据见下表。
- [ ] 完整局记录额外永久生命、恢复量、转换次数与恐惧覆盖，验证先进档的实际构筑强度。
- [x] 文档登记、技能表、三语构建、索引锚点与玩家引用持有者静态校验通过。

### 5.1 证据记录

| 等级 | 证据 | 结论 |
|---|---|---|
| E0 | 技能表生成；i18n_build；verify_docs / verify_doc_anchors / verify_player_ref_holders；diff --check | 通过；正式表 159 条，F4 动态覆盖新条目，三份 skills.translation 已回填 |
| E1 | `bench/run.cmd bloodlust_head_on 1 180 Shadow Headless`；`tmp/bloodlust-head-on-focused.log` | 24 个真实终态案例、202 断言、0 失败；使用正式 take_damage 致死并跨帧结算，未宣称完整武器飞行实射 |
| E2 | `bench/run.cmd all 1 300 Shadow Headless`；`tmp/bloodlust-head-on-all.log` | 101 项同步测试与 lifecycle_gauntlet 通过；本案例再次 202/0，gauntlet 自身 90/0；wrapper 退出 0，运行时错误门通过 |
| E3 | `bloodlust_head_on_c1_baseline` / `bloodlust_head_on_c1`，各 30s ×3，180s 超时，Shadow Visual | 有效对照六次均守住 60 FPS，8/8 镜头巡检、36 名混合演员；启用时每次 55/55 转换，恐惧确实落地 |
| E4 | 未执行 | 完整局永久成长与控场平衡仍待实玩，保留 in-progress；不将短时压力样本称为整局验证 |

### 5.2 Visual 负载与结果（2026-09-15）

- Godot 4.7.2 Steam，GL Compatibility，1600×900，正式机体三维显示，seed=42。
- 两组均沿用 C1 的 36 名海陆空混合演员、8km 范围与 8 段相机巡检；开局预设构筑相同，再授予击杀嗜血、骑士心脏、寒颤号令、历练，仅启用组额外授予血色骑士。
- 测量时固定构筑：继续记录击杀经验，停止经验条排空触发的随机选卡。每 0.5s 追加一个敌机真实致死事件，敌机朝外保证不是自然对头；原演员、AI、武器、伤害、尾迹、爆炸与标签继续运行。
- 这是持续触发压力，额外死亡由测试主动调用正式伤害入口；不能将 55 杀/30s 当成真实玩家击杀速率。

| 组别/序号 | avg FPS | p1 FPS | 最差帧 FPS | frames_below_60 | 转换/注入击杀 | 恐惧采样累计 | 最大生命增加 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 基线 1 | 118.82 | 105.00 | 60.55 | 0 | 0/55 | 0 | 0 |
| 启用 1 | 118.73 | 110.00 | 66.07 | 0 | 55/55 | 116 | 550 |
| 基线 2 | 118.88 | 100.00 | 69.47 | 0 | 0/55 | 0 | 0 |
| 启用 2 | 119.26 | 110.00 | 60.00 | 0 | 55/55 | 117 | 550 |
| 基线 3 | 118.27 | 98.62 | 71.11 | 0 | 0/55 | 0 | 0 |
| 启用 3 | 119.02 | 110.00 | 74.72 | 0 | 55/55 | 116 | 550 |

三次 avg FPS 中位：基线 118.82、启用 119.02；p1 中位：基线 100、启用 110。满足无超过 5% / 10% 回退的门，未据此声称技能优化了渲染。

原始文件位于 `bench/results/`：基线时间戳 `20260915_005041` / `005249` / `005407`，启用时间戳 `20260915_005143` / `005328` / `005446`；统一汇总 `tmp/bloodlust-head-on-metrics.json`。
截图 `bench/results/bloodlust_head_on_enabled.png` 已检查，保留真实混合战场、炮火、烟迹和 HP 成长显示。

首次 `004926` 基线因自动选卡意外取得血色骑士而转换 38/55，wrapper 正确判失败；保留原结果，明确作为无效对照排除。修正固定构筑后重跑上述三组。
引擎退出仍有 ObjectDB/resource 计数警告，本次不作无泄漏结论。

## 6. 实现计划（Task Pipeline）

- [x] 用户审阅并要求执行实装与测试，规格获批后进入 in-progress。
- [x] 注册条目、三语、来源前置与 F4/技能审计。
- [x] 接入飞机致死快照与击杀收益消费，保留原有几何分支；验证目标类型、奖励禁用与幂等。
- [x] focused、生命周期、全量回归及 Visual 验证。
- [ ] 完整局实际构筑平衡验证。
- [x] 刷新技能表、实装索引、Script/Code Index，记录自动测试证据；因 E4 未过保留 in-progress。

## 7. 索引锚点（Where）

| 关注点 | 实装入口 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd`：UPGRADES |
| 空中归因与钩子 | `scripts/aircraft.gd`：_record_kill_attribution；`scripts/status_effects.gd`：on_kill；`scripts/survivor/skill_hooks.gd`：dispatch_on_kill |
| 经验与基础成长 | `scripts/survivor/survivor_spawner.gd`：_check_head_on_kill_bonus 与死亡结算 |
| 转换资格 | `scripts/survivor/skill_hooks.gd`：bloodlust_counts_as_head_on / BLOODLUST_HEAD_ON_META |
| 聚焦与生命周期案例 | `scripts/tests/bloodlust_head_on_case.gd` / `bloodlust_head_on_runner.gd`；`scripts/tests/lifecycle_gauntlet_runner.gd` |
| C1 持续触发压力 | `scripts/tests/bloodlust_head_on_performance.gd`；`scripts/bench/bench_runner.gd`：_swap_to_bloodlust_c1 |
| 导航 | [技能实装索引](../../reference/skill-implementation-index.md) |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-09-15 | 1 | 按用户“嗜血状态下任何击杀视为对头”的想法建立可行性与技能草案，等待定稿。 |
| 2026-09-15 | 2 | 用户指定稀有度为先进（ADVANCED），同步获取定位与强度验收表述。 |
| 2026-09-15 | 3 | 用户限定仅敌方飞机击杀可转换；同步三语描述、判定、结构、验收与实现计划，移除地面和海上目标接入要求。 |
| 2026-09-15 | 4 | 用户批准实装测试；数据、三语、致死快照、对头消费者与 no_kill_reward 永久成长守卫落地；focused 202/0、全量回归和三组 C1 对照通过；整局平衡待实玩。 |
