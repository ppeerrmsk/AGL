# 武器使用准则（Weapon Employment Doctrine）

> status: **approved（2026-07-04 用户定稿）** · spec_version: 2 · 日期：2026-07-04
> 上游：重构计划 [physics-ai-control-refactor.md](../../planning/physics-ai-control-refactor.md)
> （用户提出："武器使用的 AI 比较乱，需要规范僚机装备各种武器后，什么时候发射什么武器、
> 怎么瞄准、怎么机动"）。姊妹 spec：[wingman-escort-evasion](wingman-escort-evasion.md)。

## 1. 设计意图（Why）

**现状病灶**（2026-07-04 摸底）：
- planner 的武器决策（`_apply_combat_weapon`）只认识**机炮/导弹二元**，且优先序硬编码
  "导弹包络内必导弹"。电磁炮、激光、火箭弹、副导弹槽**完全不在决策树里**——各自跑
  自己的 update 状态机自行开火，互相不知道对方存在。
- 后果实证：机炮侧射（已修，log 230431）；电磁炮机（AF-03）被迫用
  `prefer_nose_aligned_weapon` 旗留在 legacy 路径；装备越多行为越不可预测。
- 装备层其实**已有投票骨架**（`EquipmentParams.desired_engagement()` →
  `EngagementPreference{preferred_range_m, preferred_intent, priority}`），但从未被消费
  ——本 spec 就是它的激活令。

**North star**：僚机带什么武器，就打出什么风格——远距电磁炮狙击、中距导弹 crank、
近距机炮咬尾，切换自然、每发都有道理。玩家看一眼僚机的行为就能猜到它在用什么武器。

**两条用户定下的原则**：
1. **距离决定武器**：每种武器有自己的有效距离带，远距优先远程武器（电磁炮）。
2. **瞄准逻辑统一**：所有指向性武器共用同一个"机头指向敌机路径提前点"的瞄准语义，
   区别只在**纪律严格度**（允许偏差锥角）——电磁炮直线命中判定最苛刻 → 锥最窄 →
   机动上要求最平直的对准航线；机炮次之；导弹最宽松（允许 crank 维持锁定即可）。

## 2. 数据定义（What —— 权威源）

### 2.1 武器包络与瞄准纪律表

每件装备申报五件事：**距离带（动态来源）/ 命中率优先级 / 瞄准纪律 / 前置条件 /
机动含义**。⚠ 距离带一律**每次竞选实时读装备 live params**（用户定稿 1a/1b：技能升级/
武器强化即时生效），下表"来源"列即权威读取点，禁止烘焙常量：

| 武器 | 距离带来源（动态，m） | 命中率优先级 | 瞄准纪律（提前点偏机头锥角） | 前置条件 | 机动含义（intent 倾向） |
|---|---|---|---|---|---|
| 电磁炮 railgun | `min_engage_range_m` ~ 本机 `radar_range`（已是动态设计） | **100（必中，最高）** | **±3°**（直线 hitscan 最苛刻）；充能全程维持 + 持续追踪航点 | 冷却就绪 | LINE_UP：平直对准提前点，bank ≤ ~30°，甩头中断充能 |
| 主导弹 missile | `missile.min_range` ~ `missile.max_range`（锁定距离升级即时反映） | 70（可被 flare/机动躲） | 宽松：雷达锁即可，crank ≤ crank_deg | 雷达锁定完成 + 弹药 | LEAD_PURSUIT/crank 几何（现行为不变） |
| 机炮 gun | 60 ~ `gun.max_range` | 50 | ±`fire_cone_half_angle`（已实装锥门） | 弹药 | CLOSE_TAIL 咬尾（现行为不变）；近带唯一候选 = "近距固定机炮"（1e） |
| 火箭弹 rocket | `rocket.min_fire_range` ~ `rocket.max_fire_range` | 40（无制导最低） | ±8°（需对准路径点） | 弹药 + 冷却 | TAIL_CHASE 直线逼近段顺势齐射 |
| 副导弹槽 secondary | 副槽自己的包络 | —（被动，不竞选） | 同主导弹（独立雷达/锁定） | 副槽锁定 + 弹药 | 不驱动机动（机会武器） |
| 激光 laser | 0 ~ 激光射程 | —（被动，不竞选） | 无（360° 照射） | 热量未过热 | 不驱动机动（纯被动 DoT） |

### 2.2 选择准则（"什么时候发射什么武器"——2026-07-04 用户定稿版）

1. **主武器唯一制**：任一时刻只有一件"主武器"驱动机动与开火意图；**被动/机会武器**
   （激光、副导弹、机会机炮）不参与竞选、不驱动机动，条件满足即自动开火（现行为保留）。
2. **距离带是动态数值**（用户定稿 1a/1b）：每次竞选**实时读装备当前参数**（导弹锁定
   距离升级、武器强化 buff 等即时生效）——禁止把距离带烘焙成常量（SEAM-001 同款纪律：
   数值来源是装备的 live params/effective 值）。
3. **竞选规则**：候选 = "当前距离在其优先区间内 + 前置条件满足"的指向性武器；
   胜者 = **命中率优先级最高者**（用户定稿 1c/1d）：
   `电磁炮(必中) > 导弹(可被 flare/机动规避) > 机炮 > 火箭弹`。
   同级平手取距离带上界大者。电磁炮设**最近射程**（1e）：近距自然出局，近带只剩
   机炮候选 → "近距固定机炮"由竞选自然涌现，无需特判。
4. **滞回**：主武器切换需 1.5s 保持（防距离带边界抖动来回换武器换机动）。
5. **兜底**（用户定稿 4，阶段 2 实现时细化）：**"就绪但距离未进带"≠失格**——
   有弹药/冷却就绪、只是还没飞到距离带的武器，按其中命中率最高者的**纪律逼近收距离**
   （纯机炮机 1500m 外保持机炮几何压向 gun 带——CLOSE_TAIL 逼近语义不破坏）。
   **真·全失格**（无任何就绪武器：全 CD/弹尽）→ 维持追击 + 按导弹纪律 crank 等待
   （保持雷达锁，CD 转好即刻能打；不再"机炮硬兜底"，也不是呆飞）。
6. **玩家覆盖**：weapon_lock（强制机炮/导弹）与 charge_intent 压过竞选（现行为保留）。

### 2.2b 阵营分级（用户定稿 3）

**瞄准纪律（提前点公式 + 锥角）两阵营同一套**；难度差异全部放在**执行层**，且沿用/
扩展现有机制，不在纪律层开叉：
- 玩家方：尽可能准确不失误——无人为误差注入，burst 不节流（team==0 现状）。
- 敌方：`_ai_gun_burst_allowed` 射击节奏节流（现状）+ PilotPersonality 误差注入
  （legacy 路径现有；planner 路径的对等接入点在重构计划 Phase 3 补）+ 未来可加
  开火频率系数。平衡调参只动这一层。

### 2.3 瞄准统一规范

- **单一提前点公式**：全武器共用"双迭代弹道提前点"纯函数（2026-07-04 机炮修复引入的
  公式抽为共享 helper；弹速参数按武器：机炮=muzzle_velocity、火箭=rocket 弹速、
  电磁炮=∞→提前点退化为目标当前位置 + 微小外推、导弹=不需要）。
- **开火门 = 提前点偏机头 ≤ 该武器锥角**（表 2.1 列 3）。机炮已实装此门；
  电磁炮/火箭弹按同款模式接入。
- **机动跟随武器**：胜出主武器的"机动含义"（表 2.1 列 5）作为 planner 的 intent
  倾向注入——electromagnetic LINE_UP 是新增 intent（第 14 个）：直线对准提前点、
  限 bank、恒速，充能完成/失格即退出。

## 3. 行为与公式（How）

### 3.1 决策管线（骑在 Phase 1 架构上）

```
装备表（EquipmentParams.desired_engagement 投票，含距离带/锥角/前置）
   ↓ 每 AI tick
武器竞选（§2.2）→ 主武器 kind + 该武器的机动含义
   ↓
TacticalPlanner：主武器含义作为 intent 决策输入（Situation 加 primary_weapon 字段）
   ↓
TacticalPlan{weapon_mode, allow_*_fire} → _apply_tactical_plan（统一提前点 + 锥门）
   ↓
各武器 update_*：只负责"已被允许时的发射执行"，不再自带目标选择/时机决策
```

### 3.2 电磁炮 LINE_UP intent（新增；2026-07-04 用户定稿 2）

- 进入：主武器竞选出 railgun 且冷却就绪。
- 行为：pursuit_pos = **目标提前点（持续追踪，每 tick 更新）**——充能期间不是冻结
  航向，而是持续小幅修正机头跟住敌机的航点；target_speed = 巡航（稳定射击平台）；
  bank 上限收紧（≤ ~30°）；heading 变化率超阈值 → 中断充能（防"充能中甩头白费冷却"
  ——小幅跟踪修正在阈值内，不触发中断）。
- **射空可接受**（用户定稿 2b）：不因目标临近出带而抑制发射——按当前提前点打，
  脱靶认了（有 MISSILE 脱靶同款日志归因即可）。
- 退出：发射完成 / 目标出带 / 被迫规避（EVADE 优先级高于一切武器纪律——保命第一，
  与 B1 分层规避一致）。

## 4. 结构与组成（Structure）

- 竞选器：新纯函数模块（`scripts/ai/tactical/weapon_selector.gd`，输入装备投票数组 +
  Situation，输出主武器 kind + 机动含义——可单测）。
- 装备投票补全：railgun/laser/rocket 的 `desired_engagement()` 从占位实装为表 2.1。
- Situation 加 `primary_weapon` / `primary_weapon_cone_deg` 字段；TacticalPlan 的
  weapon_mode 扩展为 kind 枚举（兼容期保留 GUN/MISSILE 映射）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 无头测试 `--bench=weapon_doctrine`：距离 6000/2500/900/300m 四档 × 满装备机，
  断言竞选结果 = railgun/railgun 或 missile/missile/gun；滞回防抖（边界往返不换武器）。
- [ ] 电磁炮机充能期间 bank ≤ 30°、heading 甩头中断充能（无"边急转边充能"）。
- [ ] GUN_AIM 日志开火时 aim_vs_tgt ≈ 0 恒成立（全武器）。
- [ ] 生存模式 playtest：满装备僚机行为可读——远距先电磁炮、进带切导弹、贴脸机炮。
- [ ] 现有 12 项回归门全绿（尤其 bfm_intent 89 case 与 weapon 7 case）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 竞选器 + 装备投票补全（纯函数层，无行为变化）
weapon_selector + 三件装备投票实装 + 单测。planner 暂不消费。

### 阶段 2 — planner 接入（行为切换点）✅ 2026-07-04 落地
Situation 注入竞选输入（railgun 带/就绪 live 读取 + 滞回状态经 Aircraft 回写）；
`_apply_combat_weapon` 从"机炮/导弹二元硬编码"重写为消费 WeaponSelector 竞选；
`plan.primary_weapon` 新字段。**实现备注**：①火箭弹暂不参与竞选（保持机会射击，
阶段 3 评估）；②railgun 胜出时阶段 2 过渡按导弹纪律 crank 保锁（LINE_UP 在阶段 3）；
③"逼近≠失格"语义（§2.2-5 细化）由回归门抓出——纯机炮机带外逼近必须保持机炮几何；
④统一提前点 helper 上移并入阶段 3（与 LINE_UP 一起动 _apply_tactical_plan）。
验收：--bench=weapon_doctrine 18 断言 + 回归门 13 项全绿（bfm_intent 89 无回归）。

### 阶段 3 — LINE_UP intent + 电磁炮迁入 planner ✅ 2026-07-05 落地
- **LINE_UP intent**（第 15 个）：竞选出 railgun → 平直对准提前点远点直线航线（每 tick
  重算 = 持续追踪航点）、恒巡航速禁 AB、`plan.bank_limit_deg=30`（新字段 →
  `_plan_bank_limit_rad` → update_bank/step_bank 双侧镜像钳制，SEAM-017 纪律）。
  决策树插在 boom-zoom **之前**（远距狙击 aspect 常年 >80°，否则被误判脱离）；
  参与 hysteresis 集合；竞选单点化为 `BfmIntent.run_weapon_election`（planner 与
  _apply_combat_weapon 共用，同 tick 同结果）。
- **电磁炮时机上收**：`_try_start_charging` 加 planner 门（planner 机仅当竞选胜者 =
  railgun 才充能；非 planner legacy 保留自主）；`_tick_charging` 加甩头中断
  （|turn_rate_filt| > 25°/s → 取消回 IDLE 不进冷却——LINE_UP 小幅跟踪修正在阈值内）。
  发射执行/hitscan/视觉仍留 equipment。
- **AF-03 迁入 planner**：摘 `prefer_nose_aligned_weapon`（SNIPER_HOLD legacy 路径退役），
  `use_tactical_planner=true`；bvr_only 远距站位（走位学说）保留。
- **统一提前点上移**：`AircraftWeapons.lead_heading(ac, tgt, bullet_speed_mps)`
  （双迭代，INF/非机目标退化直瞄），机炮瞄准改调之（§2.3 落地）。
验收：weapon_doctrine 26 断言（LINE_UP 竞选驱动/坡度钳 30°/CD 降级/提前点外推方向）
+ 回归门 13 项全绿。

### 阶段 4 — 验收 + 文档
bench + playtest + §7 锚点回填 + survivor-skills/enemy-index 相关行同步。

## 7. 索引锚点（Where）

（实现后回填）

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-04 | 1 | 初稿（draft）：现状摸底 + 包络/纪律表 + 竞选规则 + LINE_UP intent 设计。待用户定稿。 |
| 2026-07-04 | 2 | **用户定稿（approved）**：①距离带改为动态数值（实时读装备 live params，升级即时生效）；②重叠区竞选从"射程上界优先"改为**命中率优先**（电磁炮必中 > 导弹 > 机炮 > 火箭），电磁炮最近射程使近距自然归机炮；③充能期间持续追踪敌机航点（非冻结），射空可接受；④阵营分级：瞄准纪律同一套，难度差异全放执行层（敌机节流/误差）；⑤兜底改"维持追击 + 按导弹纪律 crank 等待 CD"。 |
| 2026-07-05 | 4 | 阶段 3 落地：LINE_UP intent（竞选驱动、bank_limit_deg 双侧镜像钳制、boom-zoom 之前插枝）+ 电磁炮充能 planner 门 + 甩头中断（25°/s，取消不进 CD）+ AF-03 摘旗迁 planner + 统一提前点 lead_heading 上移。weapon_doctrine 26 断言 + 回归门 13 项全绿。剩阶段 4 playtest。 |
| 2026-07-04 | 3 | 阶段 2 落地：planner 消费竞选（Situation 竞选输入 + plan.primary_weapon + _apply_combat_weapon 重写）。实现中细化 §2.2-5 "逼近≠失格"语义（回归门抓出：纯机炮机带外须保持机炮几何逼近）。--bench=weapon_doctrine 18 断言 + 回归门 13 项全绿。 |
