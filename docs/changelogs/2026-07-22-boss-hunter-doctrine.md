# 2026-07-22 · BOSS 猎手化 + Wraith 角色/执行失误 + 热诱弹命数

> 📋 **接手请先看** [2026-07-22-boss-hunter-handover.md](2026-07-22-boss-hunter-handover.md)
> —— 进行到哪里、下一步做什么、四个坑、两个需复核的judgment call。
> 本文只记"改了什么、为什么"。

> 触发：playtest log `combat_log_20260722_005100.txt`。用户报告两个现象 ——
> ①"Boss 像开进了场没有来找玩家，他没有把玩家队当目标"
> ②"他在一轮骑射中就被歼灭了半数，完全没有要躲的意思，看上去行动很迟缓"

## 诊断（日志实证）

| 时刻 | 事件 |
|---|---|
| 612.5s | WRAITH 中队刷出，收到"飞到锚点 → 绕锚点巡逻"指令 |
| 651.7s | 玩家从 **10363m** 外发射第一枚中距弹 |
| 612.5~660.1s | BOSS **全程无反应**，在锚点低速绕圈 **47.6 秒** |
| 660.1s | 玩家贴近到 2500px，事件层才切 ENGAGED |
| 663.1s | 长机 WRAITH-01 阵亡（苏醒后仅存活 3.0s，起手 173m/s 无加力） |
| 668.4s | 二号机 WRAITH-02 阵亡 |

三条独立根因，不是一个 bug：

1. **BOSS 不来找玩家** —— 设计如此。PRE_STAGE 的剧本任务就是"飞到 BOSS 区绕圈等"。
2. **接战判定只认几何距离**，不认"我正在挨打"。玩家用射程 10km+ 的弹站在 5km 苏醒半径外白嫖，
   BOSS 连"我被锁定了"都不知道 —— 白挨 8.4 秒。
3. **热诱弹命数从未实装**。`ace-squadron-tier` spec 承诺"4 枚 = 4 条命"，实际资源是
   `max_flares=2 / burst_count=3` → `mini(3,2)=2`，**第一次投放就打光弹匣 = 只有 1 条命**。

> 顺带澄清一个**看起来像 bug、其实是设计**的点：`is_boss_attacker()` 是一个总的自保关闭
> 开关，它按设计屏蔽了王牌的**全部规避机动入口**。tier spec 已定档"王牌不靠机动躲、靠热诱弹
> 当命数（不解锁规避机动）"。所以"完全没有要躲的意思"的正确修法是**补上 4 条命**，
> 不是把规避接上。本批未推翻该设计。

## 用户裁定

> "取消了'要去圈里等'这个概念。它会直接作为猎手型来找玩家，和玩家主动交战。
> 包括所有的 Boss 都是这样，所有 Boss 的王牌飞机都会知道玩家的位置，然后主动来追玩家。"

新建 spec [systems/boss-hunter-doctrine](../specs/systems/boss-hunter-doctrine.md)。

## 落地

### 一、猎手化（新 spec，阶段 1~4 全落地）

- **新 directive verb `PURSUE_UNIT`**（AIDirective 第 7 个 verb）：持续飞向一个**会动的单位**，
  0.5s 重取一次位置，**无抵达态**（"追到了"由上层接战触发器裁定），目标失效自动释放。
  不是"每 0.5s 重下一条 `FLY_TO_POINT`"的语法糖 —— 重下会清 `_directive_state`，
  且 `FLY_TO_POINT` 的抵达判定会在贴近时误触发 `on_arrival` 分派。
- **接战触发器 2 条 → 4 条**：新增 **T3 任一成员被锁定** / **T4 任一成员受伤**。
  T3 取"被锁定"而非"被击中"，因为锁定发生在发射**之前** —— 这正是旧模型缺的那 8.4 秒。
- **废除 `ANCHOR_HOLD` 归巢**：`SquadState` 从 4 态收缩到 3 态，PURSUIT 成为唯一战斗常态。
  两个 leash 常量一并删除，防止下次有人照着再写一遍。
- **出生点**：从"离玩家最远的地图角落"（60km 图上可达 40km+，纯空转）改为
  **玩家机头前方 ±30° 扇面 12km**（守"事件刷在沿途"约定），约 27s 闭合。
  远端进场的机头朝向也从"朝锚点"改成"朝玩家"。
- **逐 BOSS**：WRAITH / Poltergeist 走基类改动；**Mother Goose** 巡逻环圆心从地图中心
  改为跟随玩家（2s 重算，位移 <800px 不重下航点）；**CSG 舰船不猎手**（30 节 vs 400m/s，
  物理上追不动，观感只会是"船在原地扭动"），其猎手性由弹射的 F/A-18 承担 —— 起飞即
  `acquire_target(TS_BOSS)` 挂玩家（旧版靠"AI 雷达扫描自然获取"，玩家绕开 5km 就永不被发现）。
- **BOSS 圈跟着 BOSS 走**：事件层每帧把 `boss_zone["center"]` 同步为存活成员质心。
  战术地图的洋红圈与 HUD `ZoneArrow` 都读这个字段，故两处**零改动**自动跟随。
  CSG 二阶段原有的私有同款同步已删，改由事件层单一所有。
- **玩家引用活化**（SEAM-019 同类）：新增 `BossEncounter.set_player_ref()` 基类契约。
  各 encounter 的 `_player` 是 spawn 时缓存，而 `_set_player_aircraft()` chokepoint 扫不到它们
  （校验脚本只扫 `survivor_mode.gd`）。旧模型下是慢性病，**猎手模型下是急性病** ——
  BOSS 全程追 `_player`，玩家一按 1-4 切控就会去追一架不再是玩家的飞机。
  Mother Goose 一条链三处（boss → controller → SwarmDirector）全部重定向。

### 二、Wraith spec 阶段 1（角色真实化）

- `AceRole { NONE, KNIGHT, SNIPER }` + `ROLE_META` + `role_of()`，取代两个死代码：
  `combat_specialty`（**只写不读**）与 `f47_role`（**只读不写** —— `is_boss_attacker()`
  的整条兜底分支因此恒为假）。
- 三个消费点：KNIGHT = 机炮优先 + `bvr_only=false`（被咬转身对抗）；
  SNIPER = 导弹优先 + `bvr_only=true` + 站位带 **4000~6000 m**（被压近即拉开）。
- **spec 冲突裁决**：wraith §2.2 原给 SNIPER 的 `aggression 0.75` / `self_preservation 0.35`
  违反 tier §2.1 铁律（≥0.90 / ≤0.25），而 wraith §2.5 又声明"不覆盖 tier"。**判 tier 赢** ——
  "SNIPER 不贪战"本就不该由交战欲实现（那会让它在该开火时也消极，正是 tier 想禁止的）；
  真正要的是空间行为"被压近了就拉开"，由 BVR 站位表达，与交战欲正交。裁决已写回 spec。

### 三、Wraith spec 阶段 3（执行精度失误）

- **机炮瞄准误差通路开门**：拆出 `Aircraft.gun_aim_error_enabled`。此前这条通路被
  `use_tactical_preference` 门死 —— 那是个"玩家有战术偏好面板"的**操控模式**标志，
  与枪法毫无关系，兼任的后果是**全部 AI 敌机（含 BOSS）永远打一个完美居中的散布锥**。
  玩家侧行为逐字节不变。
- 王牌枪法 `pilot_aim_skill = 0.85` → 梭起手误差 `lerp(5.0°, 0.5°, 0.85) = ±1.175°`。
  连同开关一起写在 `AceTier.mark()`（tier 语义的单一归属地），加第三个王牌中队时不用再想起。
- **减速迟滞**：`EngagementSpeedGovernor.apply_with_lag()` —— 每次**新进入**治理区掷一次骰，
  25% 概率延迟 0.6~1.2s 才开始减速 → 冲过头，给玩家一个可利用的反咬窗口。
  失误只在**执行层**（手慢半拍），决策层不掷骰。

### 四、热诱弹即命数（ace-squadron-tier 阶段 3）

- 新建 `resources/ace_flare.tres`：`max_flares=4` / `burst_count=1` / `nervousness=0.5`。
  F-47 与 F-14 Poltergeist 的**敌方** params 改挂它 —— 刻意不动 `f14_flare.tres`，
  那份被玩家可驾驶的 F-14 共用。
- 干扰判定加 tier 分支：王牌 `jam_chance = 1.00` 恒定。
- `fail_chance` / `head_on_fail_reduction` 一并归零（F-47 原为 0.05 / F-14 为 0.15）。
  同一条理由：那是"对来袭导弹完全不反应"的骰子，会让一条命随机蒸发，
  与 §3.3 判定 jam 恒为 1.00 的动机完全一致（玩家要能从"骗掉几发"推断剩余命数）。

## 验证

- 新增 `--bench=boss_hunter`，**60 断言全绿**（PURSUE_UNIT 执行分支含节流/无抵达态/
  目标失效释放；无归巢；KNIGHT-SNIPER 距离带分离；两个死 meta 已清；热诱弹 4 命；
  瞄准误差开门；减速迟滞锁存与解除）。
- **回归门 `--bench=all` 33 项 PASS / 0 失败。**
- `verify_doc_anchors.py` 全绿、`verify_player_ref_holders.py` 全绿。

> **断言抓到一个真 bug**：`_directive_pursue_unit_step` 里 `as Node2D` 写在
> `is_instance_valid` **之前** —— 对已释放对象求值直接抛错（SEAM-020 的教科书形态）。
> 猎手全程持有玩家机引用，玩家阵亡/切控时这条路径是常态而非边缘情况。已修，守卫前置。

## 顺带

- 回填 **127 处腐烂的文档锚点**（`verify_doc_anchors.py` 报 113 → 0）。绝大多数来自本轮之前
  的未提交改动（`survivor_data.gd` 有的偏了 575 行、`survivor_mode.gd` 偏 170 行）；
  HEAD 上是 0 腐烂，说明全部产生于工作区。
- 同步 `script-index` / `code-index` / `enemy-index` / `specs/_INDEX.md`。

### 五、Wraith spec 阶段 2（队级战术状态机）—— 同批补齐

新建独立模块 `scripts/survivor/wraith_tactics.gd`（**Wraith 专属窄井**，不下沉为通用模块）。
`AceSquad` 只加三个空钩子 `_tactics_enter/update/exit`，其它王牌中队不覆写即零影响。

```
PERCH 建立高位 → BRACKET 诱敌包夹 → PRESS 压制 → RESET 重整 → 回 PERCH（四相闭环，无终止态）
                                        ↑                │
                                        └── 退化检测 ────┘
```

- **PERCH**：爬到"玩家高度 +2000 m"对应的高度档，绕到玩家侧后方 2500 m 处爬（不贴脸）。
  高度差 ≥1500 m 或 12 s 超时即完成。
- **BRACKET（签名战术）**：BAIT 默认二号机（KNIGHT），阵亡顺位取存活 KNIGHT 再取 SNIPER。
  BAIT 拉到**玩家机头正前方 3000 m** —— 正前方而不是随便一个远点，因为诱饵必须**留在玩家
  雷达锥内**、看起来是能吃下的猎物，否则玩家根本不会去追。BAIT 全程 `combat_disabled=true`
  **不开火**。其余三机分到与"玩家→BAIT"轴线夹角 **≥60°** 的方位（左右交替、同侧再错开 30°）。
  玩家咬住 BAIT 满 4 s 收网转 PRESS（松口时衰减速度是累积的 2 倍），或 20 s 超时。
- **PRESS**：撤掉一切 directive 与包围偏置，**完全放手**给 BFM 决策树。15 s。
- **RESET**：全队沿背离玩家方向散开拉到 3000 m 并爬升。`combat_disabled=false` ——
  脱离是**几何行为不是缴械**，路上有解还是要打。8 s 后回 PERCH。
- **退化检测**：每 0.5 s 采样全队对玩家的机头偏角均值，连续 6 s >50° → 强制 RESET。
  这是对"共速绕圈、谁也咬不住谁"（log 20260720_172222）的结构性防御，与
  `EngagementSpeedGovernor` 互补：治理层保证他们**能**咬住（修几何），RESET 保证他们
  **咬不住时不会傻转**（修死锁）。

**包夹复用既有通道**：`surround_bearing` 原为命令轮盘 FOCUS 集火（相邻 ≥45°）而建，
与包夹是同一个几何概念，故复用而非另造 —— 它已经实现了"距目标远时先飞到自己扇区的
进入门点、近于 1500 m 解除偏置收敛"，**全程真实转弯不挪坐标**。`Situation` 侧原以
`commanded_target != null` 为读取门（玩家点名专用，敌机没有），为 `tier == ace` 开了一个
窄口子，仍以 `INF` 作未分配哨兵，对友军侧零影响。

> **顺带修一个隐性 bug**：`_pursuit_enter` 无条件写 `ai.bvr_only = false`，
> 而 `bvr_only` 是**角色属性**（SNIPER=true）由 spawn 期 `_apply_role` 写死 ——
> 每次进 PURSUIT 都会把 SNIPER 的 4~6 km 站位带当场抹掉，角色分化名存实亡。已移除该行。

> **另一个差点埋雷的点**：`surround_bearing` 的消费端用 `Vector2(sin, -cos)` 还原方向
> （**heading 约定，0=北**），而轴线若用标准 `.angle()` 计算会整体偏 90°，包夹会歪到
> 完全错误的方位。已统一为 `axis_heading()` 并加断言锁死（北=0° / 东=90°）。

## 未做（明确留口）

- 三份 spec 的 §5 验收均需 **playtest** 逐条确认。猎手侧尤其："12km 闭合应在 25~35s"、
  "打第一枪到 ENGAGED 间隔 <0.5s"、"甩不掉"、"切控时目标跟着换"；
  Wraith 侧尤其："角色可辨（KNIGHT 平均交战距离 <2000m、SNIPER >3500m）"、
  "包夹成立且玩家咬住 BAIT 后 4s 内两翼进入攻击"、"整场平均机头偏角 <35°"。
- Wraith §5 的"命中率显著低于无误差基线"需实测数据，不能靠断言假设。
- 性能：本批新增的每帧开销只有战术层的 0.5s 采样与相位切换时的一次性配置，
  未跑 Sentinel + Lv5+ 压测，需补。
