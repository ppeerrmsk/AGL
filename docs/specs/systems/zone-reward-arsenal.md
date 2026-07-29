---
id: zone-reward-arsenal
kind: balance
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 1
owner: noelu（设计输入）/ Claude（细化 + 落地）
depends_on: [zone-reward-docking, inrun-weapon-inventory, skills-720-rework]
reconstruction_complete: true
---

# 战区奖励军械库 —— 武器进池 + 次世代技能只走战区奖励

> 玩家视角：战区奖励值得抢了——除了航母/僚机/副武器，现在还能开出**电磁炮、激光、火箭弹**
> 这样的真家伙；而升级卡池里最顶的"次世代"技能不再靠运气刷卡，**只**在战区奖励里出现——
> 想要蜂群导弹？去把那个战区打下来。

## 1. 设计意图（Why）

- **用户需求（2026-07-22）**：(a) 所有战区的奖励池加入武器（电磁炮、火箭弹等）；
  (b) 5 级（"次世代"）技能不再出现在升级卡池，仅作为战区奖励发放。
- **设计边界修订**：[zone-reward-docking](zone-reward-docking.md) §0 曾把武器奖励限定为
  "副系统类"（主武器=机型自带）。该边界已被
  [inrun-weapon-inventory](inrun-weapon-inventory.md)（2026-07-19 用户定向）实质取代——
  特殊武器（电磁炮/激光/忠诚僚机/QMAAM/漂浮雷）= 局内外部装备，**获取 = 签名机型首驾入库
  + 战区奖励**，到手永久、换机/进化全继承。本 spec 即"战区奖励"半边的落地。
  落地时在 zone-reward-docking §0/§2.6 加修订指针。
- **顺带归还欠账**：`missile_swarm` / `evasion_stealth` 已移出卡池但奖励链从未接通，
  是 720 批 changelog 记录的**孤儿技能**（当前无任何获取途径）。本 spec 一并修复。
- **Litmus 自检**：
  - 局内成长爽点（原则 9）：次世代技能从"第 N 次三选一碰运气"变成"打下战区必得"，
    build 决策前置到战区选择（Tab 奖励预告已有）；
  - 信息察觉（原则 3）：武器奖励领取即挂载即开火，无隐形数值；
  - 一击毙命（原则 1）：电磁炮 60 dmg / 火箭弹既有伤害均在 30-100 区间，无数值膨胀。
- **反模式规避**：不复活 ZoneRewardRegistry 死表（"一区一奖"覆盖制太死板且会发出
  build 不可用的技能）——次世代技能走实体奖励 roll 的新类别，天然带可用性过滤与跨区去重。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 奖励类别权重（REWARD_KIND_WEIGHTS 扩到四类）

| kind | ★ | ★★ | ★★★ | 说明 |
|---|---|---|---|---|
| carrier 航母 | 0 | 20 | 45 | 不变；余量用尽移出 |
| wingman +1 僚机 | 40 | 45 | 40 | 不变 |
| weapon 追加武器 | 60 | 35 | 15 | 不变（子池扩容见 §2.2） |
| **nextgen 次世代技术** | **15** | **30** | **40** | 新增；候选为空时降级为 weapon（§3.2） |

### 2.2 武器子池扩容（REWARD_WEAPON_WEIGHTS，按难度）

| 武器 | 资产 | ★ | ★★ | ★★★ | 挂载语义 |
|---|---|---|---|---|---|
| 漂浮雷 tail_mine | 既有 | 45 | 25 | 15 | 现状不变 |
| 忠诚僚机 loyal_wingman | 既有 | 30 | 30 | 25 | 现状不变 |
| QMAAM qmaam | 既有 | 25 | 25 | 20 | 现状不变（重复=补弹） |
| **火箭弹 rocket** | A-10 Hydra 泛化（rocket equipment） | **20** | **20** | **15** | 扇形自动速射，全机型可挂 |
| **电磁炮 railgun** | X-02 电磁炮泛化（railgun equipment） | **0** | **15** | **20** | 充能预测狙击，全机型可挂 |
| **激光 laser** | X-02 激光泛化（laser equipment） | **0** | **10** | **15** | 持续光束，全机型可挂 |

- 三件新武器全部**已实现**（equipment 层资产现成），本 spec 只开放获取渠道；
  电磁炮/激光属高价值件 → ★ 区不出（次日拿神器太便宜）。
- 领取 = 资产 `duplicate(true)` 挂载 + 进 `weapon_inventory` 记账（inrun-weapon-inventory
  既有机制）→ **换机/进化全继承**；重复获得同件：有弹药语义的补弹，否则按既有互斥降级
  （沿用 zone-reward-docking §6.1 规则）。
- 签名机型重复项：X-02 自带电磁炮/激光、A-10 自带火箭 → roll 时过滤"当前已持有同类
  equipment"的件，避免发废奖（过滤后子池空 → 回退既有三件）。

### 2.3 次世代技能池（nextgen 类别候选，全仓恰好 4 条）

| id | 中文名 | 归属 | 效果（权威在技能表，此处摘要） | 现状 → 本批 |
|---|---|---|---|---|
| missile_swarm | 导弹蜂群 | 骑士限定 + 王牌 | 挂载 +4 且对所有锁定目标自动齐射 | 已出卡池（孤儿）→ 接入 nextgen roll |
| evasion_stealth | 雾隐机动 | 通用全队 | 加力模式中获得隐身 | 已出卡池（孤儿）→ 接入 nextgen roll |
| fear_on_lock | 凝视压迫 | 王牌 | 持续锁定 8 s 施加恐惧 | **补 `evolved:true` 出卡池** → 接入 |
| data_link | 数据链 | 队级单实例 | 队友锁定共享 + 僚机雷达 +20% | **补 `evolved:true` 出卡池** → 接入 |

- `evolved: true` 是"移出三选一卡池"的唯一开关（升级卡 roll 侧过滤），语义不变。
- 发放走停靠领取 → 既有升级分发链（与卡池同一 apply 语义：stacks 记账 + 里程碑进度），
  效果与从卡池抽到逐字节一致。
- ZoneRewardRegistry（zone→upgrade 死表）**维持退役不接线**。

## 3. 行为与公式（How）

### 3.1 战区奖励 roll（战区开放时，一次定档）

```
kind = 按 §2.1 难度权重 roll（carrier 余量 0 → 移出；nextgen 候选空 → 移出，见 §3.2）
kind == weapon  → 按 §2.2 难度权重 roll 一件（过滤"已持有同类"；空 → 回退既有三件）
kind == nextgen → 候选 = 4 条中满足全部条件者：
                    ① 对当前机型/队伍可用（既有可用性过滤：exclusive_to / classes / requires）
                    ② stacks 未满
                    ③ 不与其它活跃战区的已 roll 奖励重复（沿用跨区去重）
                  随机取 1 → 该区奖励
Tab 展示照旧：战区圈下亮出具体奖励名 + 质量星
```

### 3.2 降级链

`nextgen 候选空`（全拿满/全不可用）→ 该区改 roll weapon；`carrier` 余量尽 → 权重摊给其余类。
保证任何战区在任何 build 下都有有效奖励。

### 3.3 领取（停靠结算，机制不变）

武器 → 挂载 + weapon_inventory 记账；次世代技能 → 升级分发链。均在停靠结算 UI 中呈现，
不新增 UI 形态。

## 4. 结构与组成（Structure）

- 无新节点/新类。改动全在：奖励 roll 数据表（kind/weapon 权重 + nextgen 候选过滤）、
  武器领取分发的三个新分支、两条技能的 `evolved` 标记、i18n。
- 升级卡池侧**零改动**（`evolved` 过滤早已存在，本批只是给两条技能补标记）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **卡池纯净**：任意机型连续 roll 三选一升级 200 次，不出现 4 条次世代技能中的任何一条
- [ ] **战区可得**：战区奖励能 roll 出 nextgen 类；停靠领取后效果生效且 stacks/里程碑记账
      与卡池获取完全一致
- [ ] **可用性过滤**：非骑士系 build 下不 roll 出 missile_swarm；data_link 已持有（队级单实例）
      后不再 roll 出
- [ ] **武器三件**：电磁炮/激光/火箭弹可被 roll 出（★ 区无电磁炮/激光）、领取后自动开火可用、
      换机型后仍在（weapon_inventory 继承）；X-02 在驾时不 roll 出电磁炮/激光
- [ ] **降级链**：全部次世代拿满后，nextgen 区位改发武器，无空奖励
- [ ] **孤儿修复**：missile_swarm / evasion_stealth 存在获取途径（战区奖励）
- [ ] i18n：REWARD_WEAPON_{ROCKET,RAILGUN,LASER}_NAME 三语；次世代技能沿用既有 UPGRADE_* key
- [ ] 性能：roll 仅在战区开放/攻克时刻执行，无每帧成本

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 次世代出池 + 接入
- [x] fear_on_lock / data_link 补 `evolved: true`
- [x] 奖励 roll 加 nextgen 类别（§2.1 权重 + §3.1 候选过滤 + §3.2 降级；玩家上下文经
      `nextgen_context` Callable 注入——开局 A/B 首 roll 早于注入走无上下文保守路径，
      领取侧可用性兜底补位）
- [x] 停靠领取 → 升级分发链接通（`upgrade_by_id` 取全条目 → 分发/记账/里程碑与选卡一致；
      roll 后换机不可用 → 转发 tail_mine 兜底）

### 阶段 2 — 武器子池扩容
- [x] REWARD_WEAPON_WEIGHTS / NAME_KEYS 加 rocket / railgun / laser 三行（§2.2 权重）
- [x] 武器领取分发三个新分支（railgun/laser=equipment 挂载 + publish；rocket=legacy 字段
      直挂 + `inrun_reward` meta 标记 + 弹药初始化；均 record 进 weapon_inventory）
- [x] "已持有同类"roll 过滤（`_ctx_owns_weapon`）
- [x] 奖励火箭换机继承：record/remount 加 rocket 分支。⚠ **2026-07-24 修订**：原"只收带
      `inrun_reward` 标的火箭"的门已**移除**——机型自带火箭全部剥离（inrun-weapon-inventory §2.2），
      此门反而导致换机把火箭摘掉（log 20260724_222103 Su-34→J-20）→ 改为**所有火箭一律入库继承**。

### 阶段 3 — 收尾
- [x] i18n 三语（REWARD_WEAPON_{ROCKET,RAILGUN,LASER}_NAME）
- [x] zone-reward-docking §0/§2.6 加修订指针（本 spec 取代其武器边界与 §2.3 强卡悬案）
- [ ] §5 验收 playtest 项（领取生效 / 换机继承 / 降级链）→ status: done

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 奖励 kind/武器权重、roll、去重 | `scripts/survivor/zone_data.gd` |
| 武器领取分发 / 次世代分发 | `scripts/survivor/survivor_mode.gd` |
| 技能表（evolved 标记、4 条次世代） | `scripts/survivor/survivor_data.gd` |
| 武器继承记账 | `scripts/survivor/survivor_player.gd`（weapon_inventory） |
| 武器资产 | `resources/`（x02_railgun / x02_laser / a10_rocket 系） |
| i18n | `i18n/translations.csv` REWARD_WEAPON_* 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-22 | 1 | 初稿并定稿：用户需求（武器进池 + 次世代仅战区奖励）；确认修订 zone-reward-docking §0 武器边界（依据 inrun-weapon-inventory 既定方向）；修复 missile_swarm/evasion_stealth 孤儿；数值细化项见 §9 |
| 2026-07-22 | 2 | **同日代码落地**（阶段 1~3 无头项全勾）：nextgen 第四类 + 三件武器进池 + 火箭继承（inrun_reward meta 方案）；200 局奖励 roll 去重回归绿；status → in-progress 差 playtest |
| 2026-07-24 | 2 | **去重语义收紧（用户拍板）**：§3.1 的"跨活跃区去重"升级为**整局去重**——武器/技能/航母每种整局唯一（`_used_reward_ids`，roll 即登记）。修复 `_ctx_owns_weapon` 只过滤 rocket/railgun/laser、漏过 tail_mine/loyal_wingman/qmaam 导致的重复武器奖励。僚机豁免=可重复保底（兜底奖励）。航母加 pity 整局保证。数值权威仍在本 spec，落地细节见 zone-reward-docking §2.3/§8 v8。新增 bench `zone_rewards`|

## 9. 自拍板项（playtest 重点复核）

1. nextgen 类权重 15/30/40（若太稀有 → 抬 ★★★ 到 50；太泛滥 → ★ 归 0）
2. 激光纳入池（用户点名"电磁炮和火箭弹**等**"，激光按 inrun-weapon-inventory 特殊武器
   清单顺带纳入；不要可整行删除）
3. 电磁炮/激光 ★ 区权重 0（高价值件不进最低档战区）
4. 重复获得新武器的补偿细则（火箭补弹 / 电磁炮·激光无弹药语义 → 触发既有互斥降级）
