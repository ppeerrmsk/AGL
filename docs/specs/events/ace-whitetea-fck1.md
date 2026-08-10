---
id: ace-whitetea-fck1
kind: event
status: in-progress
schema_version: 1
spec_version: 5
owner: noelu（设计输入 2026-08-02）/ Codex（规格细化）
depends_on: [ace-squadron-tier, ace-rotation-balance]
reconstruction_complete: true
---

# 王牌中队 WhiteTea（F-CK-1 ×3）—— J-turn 机炮骑士三机

> 玩家视角：三架轻型战斗机排成攻击线，高速切入，用机炮扫过后绝不回头缠圈；你追着其中
> 一架进入脱离腿，它却在近失速状态下猛然反转。每架机只会这样反咬一次，但三架不会同时
> 交牌——整场遭遇是连续的扫射、脱离与攻守翻面。

## 1. 设计意图（Why）

- **用户需求（2026-08-02）**：新增一支进入刷新池的中期王牌中队；中队名 **WhiteTea**；
  编成 F-CK-1 ×3；驾驶员呼号 **Tea / Cola / Bottle**；骑士型，使用机炮打带逃；会使用
  J-turn；Debug 页面必须可以强制刷新整支中队。
- **体验目标**：补第一支“纯机炮骑士”王牌队。VULTURE 的骑士节奏是导弹齐射，WhiteTea
  则高速对准切入、机炮扫射、穿越脱离、折返再攻。J-turn 是脱离失败后的反咬保险：玩家
  不能把一次成功追尾当成稳定优势，必须为单次反转保留速度、间距或僚机交叉火力。
- **现实锚点**：F-CK-1 是轻型、双发、超音速、多用途战斗机；公开资料给出最大速度
  Mach 1.6、实用升限 51,500 ft，并描述其机动性与防空拦截职责。本作据此取“轻型灵活、
  中等极速、标准雷达”的游戏中间值。**J-turn 是用户指定的王牌招牌技，不宣称为现实
  F-CK-1 的制式能力**。
- **Litmus 自检**：
  - 信息察觉：2.9 s 的减速→180°偏航→加速，以及 `J-TURN` 浮字，玩家无需读隐藏数值；
  - 尺度：游戏最大速度 2100 km/h，处于 600~2200 km/h 设计区间；
  - AI 演戏：RUN_IN→机炮扫射→BREAK→折返是清晰攻击跑；被咬尾时再主动翻转攻守关系；
  - 机制复用：复用既有 `JoustController` 与 `HerbstManeuver`，只补 profile 接线、一次使用与 flare 门；
  - 性能：只新增 3 个既有机动子节点，不新增扫描、绘制或每机战术状态机。
- **反模式规避**：不加 HP、护甲、隐形减伤或等级缩放；不做 BOSS 演出；不让 J-turn
  15 s 一次无限循环拖长战斗；不把骑士做成另一种贴身绕圈斗士；不照抄现实极速。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 编成与王牌 tier

| 字段 | 值 | 说明 |
|---|---:|---|
| 编成 | **F-CK-1 ×3** | 长机 + 两僚机，三机横列入场 |
| 战术风格 | 全员 `gun_lancer` | 机炮 joust：高速切入→扫射→穿越脱离→折返 |
| tier | 全员 `AceTier.mark()` | LOD 豁免、无缩放、远距不清理、armor 0、token 0 |
| AI 四维 | `skill_level / composure / focus / situational_awareness = 0.94` | 高于王牌门槛 0.90，低于 Teacher 1.00 |
| `aggression` | 0.95 | 主动贴身，不自动撤出 |
| `engage_duration` | 999.0 s | 遭遇不按计时器自动脱战；攻击跑内部自行循环 |
| `engage_cooldown` | 0.5 s | 沿 tier 契约 |
| `self_preservation` | 0.20 | 沿 tier 契约 |
| 生存 | 一发死 + **1 枚必躲 flare/机** | 非 BOSS 默认档 |
| 机炮闪避 | 0.20 | 王牌基线；难点放在 J-turn，不再叠高档闪避 |
| 击杀 XP | 100/架 | 全灭 300 XP |
| 全灭奖励 | `game_time -= 60 s` | 等价作战时间 +60 s，沿非宿敌王牌契约 |

### 2.2 F-CK-1 敌机参数

| 字段 | 值 | 说明 |
|---|---:|---|
| `display_name` | `F-CK-1` | 玩家可见机型名 |
| `max_hp` | 55.0 | 低于敌机导弹一击必杀 cap 75 |
| `armor` | 0.0 | tier 铁律 |
| `max_speed` | 2100.0 km/h | 现实 Mach 1.6 的游戏化中间值；不越 2200 上限 |
| `cruise_speed` | 1050.0 km/h | 轻型斗士中速巡航 |
| `stall_speed_base` | 180.0 km/h | 支撑低速反转读感，不低于同档 Mirage 2000 |
| `acceleration` | 58.0 | F-16 55 与 Su-47 62 之间 |
| `deceleration` | 90.0 | 近战收速略强；J-turn 主动段仍由机动模块接管 |
| `g_drag_factor` | 2.7 | 斗士档 |
| `max_g` | 9.0 | 现实 9G 公开试飞锚点；游戏持续 G |
| `max_g_structural` | 11.5 | 瞬时结构余量 |
| `roll_rate` | 4.7 rad/s | 高于 F-16 4.5，低于 Su-47 4.8 |
| `pilot_stamina` | 96.0 | 王牌斗士档 |
| `stamina_drain_rate` | 23.0 | 王牌斗士档 |
| `stamina_recovery_rate` | 11.0 | 王牌斗士档 |
| `max_altitude` | 15700.0 m | 51,500 ft 四舍五入 |
| `climb_rate_max` | 275.0 | F-16/Mirage 游戏档之间 |
| `thrust_to_weight` | 1.05 | 游戏化近战底子，不照抄满载现实值 |
| `drag_coefficient` | 0.022 | 轻型战斗机档 |
| `afterburner_thrust_mult` | 1.6 | 同代战斗机统一值 |
| `fuel_capacity` | 3000.0 | 事件遭遇中不形成限制 |
| `fuel_rate_normal` | 2.0 | 同档统一值 |
| `fuel_rate_afterburner` | 10.0 | 同档统一值 |
| `radar_range` | 5000.0 m | F-16 标准基准；不是雷达弱机 |
| `radar_half_angle` | 30.0° | 标准战斗机锥 |
| `lock_time` | 2.5 s | F-16 2.4 与 Mirage 2.6 之间 |
| `combat` | `lancer_combat` | 骑士闭合与打带逃底子 |

### 2.3 武器、机炮攻击跑与 J-turn

| 项 | 值 | 说明 |
|---|---:|---|
| 机炮 | `whitetea_gun` | 三机集火专用受控短梭：5 dmg、1400 m、360 rpm、1.2°散布、4 发/梭、360 发 |
| 单机单梭总伤 | 20 | 4×5；单机或三机同一首梭都不能秒杀满血玩家 |
| 梭内节奏 | 约 0.15 s 打完 4 发 | 既有 `GUN_BURST_DUTY=0.3` 公式；能看见连续弹道而非同帧伤害峰值 |
| 梭间隔 | 约 0.47 s | 既有平均射速守恒公式；给玩家明确的规避/反打呼吸窗 |
| 导弹 | **无** | 纯机炮骑士；所有伤害窗口来自切入扫射 |
| `joust_enabled` | `true` | 复用既有空对空攻击跑原语 |
| RUN_IN 外带速度 | effective max = 2100 km/h | 全速闭合 |
| RUN_IN 机炮带速度 | `max_speed ×0.90 = 1890 km/h` | 高速穿越，不降到巡航缠斗 |
| 机炮包络 outer | `1400m ×0.5 = 700 px` | 实时读取 `ace_gun.max_range` |
| BREAK inner | 200 px（400 m） | 机炮 pass 自动地板；进入即沿远离目标方向脱离 |
| BREAK 速度 | effective max = 2100 km/h | 加力拉开 |
| reentry | `outer ×1.3 = 910 px`（1820 m） | 拉开后折返再攻 |
| 闭合放弃阈值 | 60 m/s 持续 2.0 s | 追不上就先 BREAK 换角度，不抱尾绕圈 |
| RUN_IN 火力窗超时 | 15.0 s | 只计进入 outer 后的时间 |
| BREAK 超时 | 12.0 s | 被玩家追住拉不开时强制折返；J-turn 判定优先于 joust |
| flare | 1/机、必定成功、不可补充 | 第一层确定性防御 |
| J-turn 使用次数 | **1/机/遭遇** | 第二层确定性动作；用后永久耗尽 |
| J-turn 解锁 | `flares_remaining == 0` | 不与 flare 同层叠防御；先骗弹，后反咬 |
| 触发后半球阈值 | 前向点积 `< -0.3` | 复用既有被追判定 |
| 触发距离 | `< 1500 px`（3000 m） | 复用既有近距判定 |
| 最低触发高度 | 1500 m | 避免近失速后无法恢复 |
| 减速段 | 0.5 s | 速度压至失速速度 ×1.15 |
| 反转段 | 1.8 s | 偏航 180°，100°/s |
| 加速段 | 0.6 s | 开加力恢复；总机动 2.9 s |
| 导弹/锁定免疫 | 机动 2.9 s + 结束后 0.3 s | 既有 J-turn 视觉与防御契约 |
| 反击窗 | 5.0 s | 完成后继续普通 BFM，优先咬回原目标 |
| `J-TURN` 浮字 | 开始时显示 | 玩家直接识别招牌动作 |

### 2.4 调度与击破预算

| 字段 | 值 | 说明 |
|---|---:|---|
| 轮换池 | 当前非宿敌王牌池的**第 6 支** | 与既有五队一同洗牌，无放回 |
| 进池时间 | `game_time >= 240 s` | “中期出现”的统一精确定义 |
| 同场上限 | 1 支王牌中队 | 沿轮换契约 |
| 前队结束冷却 | 150 s | 沿轮换契约 |
| 新刷截止 | 540 s | BOSS 前不再新刷 |
| 机体 DU | 3 | 1/架 |
| flare DU | 3 | 1/枚必躲 flare |
| 动作 DU | 3 | 1/次确定性 J-turn |
| `access_s` | 25 s | 三次反转后重建射击窗口预算 |
| 预计击破时间 | `25 + (3+3+3)×5 = 70 s` | 落在 60~90 s 标准窗 |

### 2.5 包装（用户定名）

| 项 | 值 |
|---|---|
| 中队代号 | **WhiteTea**（专有名词，三语均保持此拼写；内部 id `whitetea`） |
| 留档 id | `whitetea` |
| 主色 | 覆盆子红 `#C73567`（`Color(0.780, 0.208, 0.404)`） |
| 徽章 | 三片茶叶围绕同一轴心回转，叶尖形成三枚 J 形回钩 |
| 血条 | 3 段命条；长机 Tea 段带三角标记 |
| 入场 | `ace_spawn` 单条无线电 + 常规次级提示条 + Tab 标记；禁止 BOSS 红色 WARNING 横幅 |

**成员固定呼号**（逐槽位绑定，开局永久 reserve）：

| 槽位 | 呼号 | 含义 |
|---|---|---|
| 长机 | **Tea** | 用户指定 |
| 2 号机 | Cola | 用户指定 |
| 3 号机 | Bottle | 用户指定 |

**Lore（i18n 三语草案；名称与呼号不翻译）**：

- zh：情报员最初以为 WhiteTea 是通讯误录：Tea、Cola、Bottle，怎么听都不像同一支中队。
  直到三架 F-CK-1 用完全相同的方式穿过交战区——一轮机炮、一次脱离；谁追上去，谁就会
  看见那架飞机在眼前把航向翻转一百八十度。名字很随意，动作从不随意。
- en: Intelligence first dismissed WhiteTea as a transcription error: Tea, Cola, Bottle hardly
  sounded like one squadron. Then three F-CK-1s crossed the fight the same way—one gun pass,
  one extension. Whoever followed saw the aircraft reverse its heading in front of them.
  The names are casual. The flying never is.
- ja: 情報部は当初、WhiteTea を通信記録の誤りだと思った。Tea、Cola、Bottle——同じ中隊の
  呼号には聞こえない。だが三機の F-CK-1 は同じやり方で戦場を横切った。一度の機銃掃射、
  一度の離脱。追った者だけが、目の前で百八十度反転する機体を見る。名前は気軽でも、
  飛び方に気の緩みはない。

## 3. 行为与公式（How）

### 3.1 遭遇循环

| 状态 | 触发/时长 | 行为 |
|---|---|---|
| INGRESS | 事件生成至进入战区 | 横列三机从边缘入场；广播非 BOSS 王牌提示 |
| RUN_IN | 默认攻击段 | 全员 `gun_lancer`，优先玩家当前操控机；全速闭合，进入机炮带后以 1890 km/h 对准扫射 |
| BREAK | 距离≤200 px / 火力窗15 s / 闭合不足2 s | 沿远离目标方向加力脱离；拉开到910 px后折返 |
| FLARE_LAYER | 每机 flare 尚存 | 来弹先由 1 枚必躲 flare 处理；该机 J-turn 不可触发 |
| J_TURN | flare=0、未使用、满足后半球/距离/高度 | 2.9 s 既有三段机动；本机使用次数置 1，后续不可再次触发 |
| COUNTERATTACK | J-turn 完成后 5 s | 保持原交战目标；J-turn 完成后重新进入 RUN_IN，不转成贴身斗士 |
| JOUST_EXHAUSTED | J-turn 已用尽 | 继续纯机炮 RUN_IN/BREAK；无第二阶段、无狂暴、无补充防御 |
| WITHDRAW | BOSS 解锁或事件被闸断 | 物理撤离；不发全灭奖励 |

### 3.2 J-turn 仲裁

逐机在既有 AI 交战 tick 中判定，不新增全场扫描：

```text
若 herbst 存在
且 herbst.uses_remaining > 0
且 flares_remaining == 0
且当前目标有效
且 forward dot direction_to_target < -0.3
且 distance_to_target < 1500 px
且 altitude >= 1500 m
则 activate(cross(forward, direction_to_target))
```

- 三机**各自跑 joust / 各自判定 J-turn**，不强制齐转；自然错峰形成连续扫射与反咬。
- 触发方向由目标相对横向叉积决定，不随机向错误一侧转。
- J-turn 期间沿既有机动守卫接管速度与 G；ACCEL 段交还正常加速。
- 玩家在 1500 m 以下把它咬住时，J-turn 被明确封锁，这是可利用的地形/高度答案。

### 3.3 玩家反制答案

1. **先拆 flare**：第一枚有效导弹一定换掉一层防御，不会被随机浪费；
2. **别无脑追脱离腿**：flare 耗尽后若追进 3000 m 内后半球，就会送出 J-turn 触发条件；
3. **诱出单次反转**：一架每局只转一次，动作结束后的低速恢复段可由僚机交叉射击惩罚；
4. **压低高度**：把交战带带到 1500 m 以下可封锁招牌动作，但玩家也承担低空机动风险；
5. **分配目标**：三架会自然错峰，若全队追同一架，另外两架能在反转窗内咬入。

## 4. 结构与组成（Structure）

- 新增一条王牌 profile：单一 element，F-CK-1 ×3，`gun_lancer`、`ace_gun`、无导弹、1 flare、
  J-turn 一次、WhiteTea 包装、70 s TTK 预算。
- 新增专属敌机参数资源；该机型**只经王牌 profile 生成，不进入普通 token 刷怪池**。
- 在敌机类型注册与创建分支登记 F-CK-1；生成后挂既有 `HerbstManeuver`。
- `gun_lancer` 只负责逐机注入 `joust_*` 参数，**不挂**导弹骑士的队级 `LancerSquadTactics`；
  因而成员保持 ENGAGE，既有 J-turn 在 joust 钩子之前可正常抢占。
- `HerbstManeuver` 新增可配置字段：`max_uses`（默认 `-1`=无限，保持 F-14 Poltergeist 不变）
  与 `requires_flares_empty`（默认 `false`）；F-CK-1 注入 `1 / true`。
- 王牌轮换、事件、HUD 血条、Tab、留档、固定呼号、i18n 全部消费 profile，不新建中队子类。
- Debug 刷新页新增 `WhiteTea（F-CK-1×3）` 编队项，调用正式事件入口
  `_start_ace_event("whitetea")`；继续遵守“同场≤1支王牌”与正式事件配置，禁止另写简化生成器。
- Debug 入口给正式事件写 `debug_force_battle_bar=true`：仅绕过“首次交火后亮血条”的呈现门，
  不修改 `_battle_joined`，因此不提前启动 TTK 计时、不改变正式轮换事件的演出语义。
- 测试扩充既有 ace tier / lancer squad bench；不新增常驻 `_process`、绘制节点或全场扫描。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **三机与中期池**：`game_time < 240 s` 永不入池；达到 240 s 后 WhiteTea 有资格成为
      本局第一支，局内只出现一次，编成严格为 3 架 F-CK-1。
- [ ] **机炮打带逃**：入场后全员以玩家当前操控机为优先目标；至少完成一次
      RUN_IN→机炮开火窗→BREAK→拉开910 px→折返闭环；不得抱尾绕圈。
- [x] **机炮短梭安全线**：WhiteTea 使用独立 4 发短梭；单机每梭 20 伤、三机理论同步首梭
      60 伤，均低于玩家 100 HP；梭间隔约 0.47 s，不再继承 `ace_gun` 的 150 伤一梭。
- [ ] **分层防御**：每机 flare 尚存时 J-turn 必不触发；第一枚有效导弹必消耗 flare；
      flare=0 后才可反转。
- [ ] **J-turn 条件**：后半球、<1500 px、≥1500 m 三条件齐全才触发；任一不满足均沉默。
- [ ] **一次性**：每机最多成功 J-turn 1 次；冷却结束后也不能再次触发；F-14 Poltergeist
      默认无限次行为逐字节不变。
- [ ] **反击成立**：BREAK 脱离腿被玩家咬尾时可触发 J-turn；完成后 5 s 内保持原目标并重新
      形成机炮 RUN_IN；EventLogger 有触发与耗尽记录。
- [ ] **纯机炮**：三机导弹资源与弹量均为空；全遭遇无 WhiteTea 导弹发射事件。
- [x] **击破预算（静态）**：`DU=9`、预计 TTK=70 s。
- [ ] **击破预算（实测）**：至少 5 次标准四机实测 P50 在 60~90 s。
- [ ] **一击毙命**：flare/J-turn 防御均耗尽后，任一玩家导弹命中即可击坠；无 HP/护甲豁免。
- [ ] **包装**：3 段血条、Tea 长机标记、覆盆子红涂装、Tea/Cola/Bottle 固定呼号、
      WhiteTea 提示条、Tab 标记、全灭写入 `whitetea` 生涯档案；无 BOSS WARNING 横幅。
- [x] **Debug 刷新（静态）**：Debug 编队下拉可选择 WhiteTea；点击生成严格得到正式 profile 的三机、
      装备、呼号、J-turn 与事件 HUD；已有王牌在场时沿正式约束拒绝重复生成。
- [x] **现实/游戏边界**：资料库描述 F-CK-1 的现实定位，但不把 J-turn 写成现实制式能力。
- [ ] **回归 seam**：机动接管只走 `maneuver_overrides_speed/g` 既有收口；同步验证预测侧；
      不新增 `lod_level` 写入者或玩家机引用持有者。
- [ ] **性能**：生存模式 Sentinel + Lv5+ + WhiteTea 同场压测，FPS 掉幅 <15 且不低于 60。
- [x] **i18n**：代号名、lore、提示条与图鉴文本三语齐全，玩家可见文本全部走 `tr()`。

## 6. 实现计划（Task Pipeline —— 用户批准后执行）

### 阶段 1 — 数据与注册

- [x] 新建 F-CK-1 参数资源并登记敌机枚举/资源注册/类型标签；保持普通刷新池不可选。
- [x] profile 加 `whitetea` 一行，登记编成、包装、纯机炮 joust、flare、J-turn 配置与 TTK 预算。

### 阶段 2 — 可配置 J-turn

- [x] 给既有 J-turn 模块加默认不改行为的 `max_uses` / `requires_flares_empty` 配置。
- [x] WhiteTea profile 生成后挂模块并注入一次性分层配置；EventLogger 记录本次/上限。

### 阶段 3 — 包装与留档

- [x] 接入固定呼号、涂装、3 段血条、Tab、提示条、徽章、图鉴与生涯留档。
- [x] 补 i18n 三语；Debug 编队页新增 WhiteTea 项并复用正式 `_start_ace_event` 入口。

### 阶段 4 — 验证与索引

- [x] 扩充既有 bench：profile、轮换、DU、机型/呼号/纯机炮与 J-turn 配置回归。
- [ ] 通过 `bench/run.cmd` 跑相关 bench 与全量回归；运行玩家引用、文档锚点校验。
- [ ] 完成生存 playtest / Sentinel + Lv5+ 压测；同步 reference 索引与本 spec §7/§8，转 done。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 王牌 profile / TTK | `scripts/survivor/ace_squad_profiles.gd` |
| F-CK-1 参数 | `resources/enemy_fck1.tres` |
| WhiteTea 受控短梭机炮 | `resources/whitetea_gun.tres` |
| 敌机注册与创建 | `scripts/survivor/survivor_spawner.gd` |
| J-turn 模块 | `scripts/herbst_maneuver.gd` |
| AI 触发 | `scripts/ai_controller.gd` |
| 事件生成与配置 | `scripts/survivor/ace_support_squad.gd` |
| 徽章 / 图鉴 / i18n / 无线电资格 | `scripts/meta/ace_emblem_icon.gd`、`scripts/meta/enemy_codex.gd`、`i18n/meta.csv`、`i18n/radio.csv`、`resources/chatter/radio_chatter.json` |
| Debug 正式事件入口 | `scripts/survivor/survivor_debug_spawn.gd` |
| 回归 | `scripts/tests/test_ace_tier.gd`、`scripts/tests/test_lancer_squad.gd`、`scripts/tests/test_career_archive.gd` |
| reference | `docs/reference/enemy-index.md`、`script-index.md`、`code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-02 | 5 | 修复首轮 playtest：Debug 事件仅强制显示王牌血条、不污染交战计时；WhiteTea 从通用 150 伤 `ace_gun` 改为 4×5=20 伤受控短梭，梭间隔约 0.47s，三机同步首梭也不秒满血玩家。 |
| 2026-08-02 | 4 | 代码接线完成：F-CK-1 资源/枚举、profile、机炮 joust、可配置单次 J-turn、包装图鉴三语、Debug 正式事件入口与静态回归；待 bench、实战计时和压力测试。 |
| 2026-08-02 | 3 | 用户批准并开始实现。 |
| 2026-08-02 | 2 | 用户定名 WhiteTea，呼号 Tea/Cola/Bottle；战术改为纯机炮骑士 joust 打带逃，J-turn 作为脱离腿被追时的一次性反咬；Debug 页须能走正式事件入口强制刷新。 |
| 2026-08-02 | 1 | 初稿：F-CK-1 ×3、中期 240 s 轮换、纯斗士、每机 1 flare 后解锁 1 次 J-turn；9 DU +25 s access=预计 70 s；提出 SHRIKE / 伯劳包装。 |

## 9. 已批准裁决

1. J-turn 为**每机仅一次，且 flare 耗尽后解锁**。
2. 主色使用覆盆子红 `#C73567`，保持王牌紫/红系规范。
