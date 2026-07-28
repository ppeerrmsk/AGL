---
id: boss-hunter-doctrine
kind: system
status: in-progress
schema_version: 1
spec_version: 2
owner: 用户（设计定档） / Claude（落地）
depends_on: [ace-squadron-tier, event-system, global-awareness-roe, wraith-squadron]
reconstruction_complete: true
---

# BOSS 猎手准则（取消"飞到圈里等玩家"）

> BOSS 不再是一个躺在地图某处、等你走过去踢一脚才醒的场景物件。
> 它知道你在哪，它朝你来，而且你打它第一枪的那一刻它就已经在还手了。

## 1. 设计意图（Why）

### 1.1 要解决的体验缺口

playtest log `20260722_005100` 完整暴露了旧模型的三重失败：

| 时刻 | 事件 |
|---|---|
| 612.5s | WRAITH 中队刷出，收到"飞到锚点 → 绕锚点巡逻"指令 |
| 651.7s | 玩家从 **10363m** 外发射第一枚中距弹 |
| 612.5~660.1s | BOSS **全程无反应**：不还手、不规避、不接近玩家，四机在锚点低速绕圈 **47.6 秒** |
| 660.1s | 玩家贴近到 2500px，事件层才切 ENGAGED，AI 苏醒 |
| 663.1s | 长机 WRAITH-01 阵亡（苏醒后仅存活 3.0s，起手速度 173m/s 无加力） |
| 668.4s | 二号机 WRAITH-02 阵亡 |

**一轮骑射打掉半数**，而且观感上"很迟缓"。三个根因：

1. **BOSS 不来找玩家** —— 它的剧本任务就是"飞到 BOSS 区、绕圈、等"。玩家不进圈，它永远不动。
2. **接战判定只认几何距离**，不认"我正在挨打"。玩家用射程 10km+ 的中距弹站在 5km 苏醒半径外白嫖，
   BOSS 连"我被锁定了"都不知道。
3. **苏醒即低能量**。巡逻速度 ~170m/s、无加力、无高度优势，被打了个措手不及。

### 1.2 North star

**BOSS 是猎手，不是场景物件。** 三条硬承诺：

- **它知道你在哪**（全知，设定 = 地面指挥所 / 数据链引导，与 [global-awareness-roe](global-awareness-roe.md) 的 HUNT 姿态同源）
- **它朝你来**（没有 leash、没有归巢、没有"玩家跑远了我就回去绕圈"）
- **你打它，它立刻算接战**（受威胁 = 接战触发器，与几何距离并列）

对应 [DESIGN_PHILOSOPHY](../../DESIGN_PHILOSOPHY.md) 原则 8「BOSS 战：真聪明 + 真硬」的第 3 项
"AI 聪明 —— 懂得撤退、看时机、配合僚机、不上头"。一个在圈里绕到你来踢它的 BOSS，
连"不上头"都谈不上，它根本没在参战。

### 1.3 Litmus 自检

| # | 测试 | 判定 |
|---|---|---|
| 1 | **信息察觉** | ✅ 玩家能直接感知：BOSS 从地平线压过来、你开第一枪它就变向咬你。这是**空间可见**的变化，不需要 HUD 提示 |
| 3 | **手感** | ✅ 不动飞机物理，不改武器灵敏度。只改"谁朝谁飞" |
| 6 | **AI 演戏** | ✅ 从"绕圈等待"变成"主动逼近"，增加演戏感而非换一种绕圈 |
| 7 | **BOSS 三维** | ✅ 直接补的就是"AI 聪明"这一维；机制独特 / 难度高由 [wraith-squadron](../bosses/wraith-squadron.md) 与 [ace-squadron-tier](ace-squadron-tier.md) 承担 |
| 9 | **阶段时机** | ✅ 由 playtest 暴露的现网缺陷驱动，不是提前造机制 |
| 11 | **60 FPS** | ✅ 无新增 `_process` / `_draw`；猎手导航复用既有 directive 通路，队级 tick 0.5s |

### 1.4 反模式规避

- ❌ **不做"扩大苏醒半径"的治标修法**。锁定与齐射能在任何固定圈外完成 —— 把 4500 改成 9000 只是把
  白嫖窗口推远，不是关掉它。触发器必须从"几何"扩到"威胁"。
- ❌ **不做无敌 / 免疫 / 减伤补丁**。BOSS 挨打就该死，问题是它当时**不该在挨打时装睡**。
- ❌ **不给 BOSS 开专属物理**（超机动 / 瞬移 / 无限加力）。猎手性来自**目标获取与导航**，不来自包线。
- ❌ **不做脚本化演出战斗**（"第 N 秒必定从东侧压来"）。接近路线由玩家实时位置决定。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 相位模型（取代旧的三相）

BOSS 战剧本仍是三相，但 **PRE_STAGE 的语义从"预驻等待"改为"接近"**：

| 相 | 旧语义 | 新语义 | 成员武器 | HUD 血条 | BGM |
|---|---|---|---|---|---|
| **INBOUND**（原 PRE_STAGE） | 飞到锚点 → 绕锚点巡逻，等玩家进圈 | **持续朝玩家实时位置飞** | 冷（不主动开火） | 隐藏 | 未切 |
| **ENGAGED** | 玩家进圈 / 贴近成员 | 同左 **＋ 受威胁即触发** | 热 | 显示 | BOSS 曲 |
| **VICTORY** | encounter.active true→false | 不变 | — | — | — |

**INBOUND 不是"和平期"**，它只是"BOSS 还没正式开火"。它随时可以被玩家的第一次锁定终止。

### 2.2 接战触发器（ENGAGED 的进入条件）

四条，**任一满足即立刻切 ENGAGED**（or 关系）：

| # | 触发器 | 阈值 | 说明 |
|---|---|---|---|
| T1 | 玩家进入 BOSS 圈 | `boss_zone.radius`（默认 2200 px） | 旧有，保留 |
| T2 | 玩家贴近任一存活成员 | `BOSS_ENGAGE_DISTANCE_PX = 2500` px | 旧有，保留 |
| T3 | **任一成员被玩家方锁定** | `is_locked == true` | **新增** |
| T4 | **任一成员受伤** | 当前 HP < 该成员的接战前 HP | **新增** |

T3/T4 复刻 [global-awareness-roe](global-awareness-roe.md) §2 的"事件察觉"语义
（任一成员被打 / 被锁 → 整队瞬间察觉），保持全项目一套察觉词汇。

**为什么 T3 用"被锁定"而不是"被击中"**：锁定发生在导弹发射**之前**，给 BOSS 留出反应时间 ——
这正是旧模型缺的那 8.4 秒（651.7s 开火 → 660.1s 苏醒）。T4 是 T3 漏网时的兜底
（机炮 / 火箭弹 / 不需锁定的武器）。

**舰队 BOSS（CSG 航母）的 T3/T4 语义**：船体**锁定免疫**（玩家锁的是挂点 / 暴露弱点的
`MountTarget` 代理，不是船中心），且伤害走 `hull_hp` + 部件血、**不碰** `CombatUnit.hp`。
因此 T3 不能直读船体 `is_locked`、T4 不能直读船体 `hp` —— 否则对舰队 BOSS **完全失明**，
玩家 10km 外锁舰齐射却要贴脸（T1/T2 几何触发）才苏醒，直接违背 §5"打第一枪即接战"验收。
修法：T3 聚合"任一锁定代理被锁"，T4 聚合"总血量池 = hull_hp + 存活挂点 HP + 暴露弱点 HP"，
均由船只自身以 `is_engaged_by_lock()` / `boss_hp_pool()` 暴露，事件层 duck-type 调用（普通飞机
无这两个方法，回落直读 `is_locked` / `hp`）。**不采用"扩大 T2 苏醒半径"的治标修法**（§1.4 反模式）。

### 2.3 猎手导航数值（INBOUND 相）

| 参数 | 值 | 说明 |
|---|---|---|
| 目标点 | **玩家机实时位置**（每次刷新时重取） | 不是锚点、不是快照坐标 |
| 目标点刷新间隔 | `0.5 s` | 与 `PURSUIT_MAINTAIN_INTERVAL` 同频；60Hz 逐帧刷新对一个数公里外的目标毫无意义 |
| 抵达半径 | 不适用（猎手指令**没有抵达态**） | 追到贴脸时 T2 早已触发切 ENGAGED |
| 巡航速度 | 机体 `cruise_speed` | INBOUND 不开加力 —— 留能量给接战瞬间 |
| 加力门限 | 距玩家 > `force_pursuit_distance`（F-47 = 2500 px）且燃油 > 0 | 仅 ENGAGED 后的 PURSUIT 软维护适用，INBOUND 不用 |

### 2.4 出生点

| 参数 | 值 | 说明 |
|---|---|---|
| 出生距离 | 距玩家 **6000 px（12 km）** | 取代旧的"离玩家最远的地图角落"（60km 图上可达 40km+，纯粹的空转时间） |
| 出生方位 | 玩家 **机头前方 ±30° 扇面**内随机 | 守"事件刷在玩家沿途"约定，不从背后冒出、不逼玩家掉头 |
| 出生高度 | 沿用 `AltitudeTier.HIGH` | 王牌中队常驻高位（能量优势，见 wraith-squadron §3.3 PERCH） |
| 边界守卫 | 若出生点越界（`MapBoundary.is_safe_inside(pos, 1500)` 为假），方位改为**指向地图中心** | 复用既有防越界逻辑 |

**为什么是 12 km**：在 F-47 巡航 1600 km/h（≈444 m/s ≈ 222 px/s）下，12 km = 6000 px 需约 **27 秒**闭合。
这段时间够玩家看见警告横幅、看见它们压过来、做一次高度/位置准备，又不至于像旧模型那样空转 47 秒。

### 2.5 锚点的降级

`anchor`（BOSS 区中心，由 `ZoneData` 的南/北两个固定点经"吸附到水面"求得）**保留，但用途收缩**：

| 用途 | 保留 | 说明 |
|---|---|---|
| BOSS 出生位置的基准 | ✅ | 尤其 CSG —— 舰队必须落在水面上，land/water 过滤依赖它（**锚点在水 ≠ 舰队在水**，见 §2.5.1） |
| 登场演出（cinematic）的舞台坐标 | ✅ | `<boss_id>_arrival` 序列的编队飞入几何 |
| CSG 航母的巡逻线中心 | ✅ | 舰船不猎手，仍沿 `anchor ± 前向 × 1500px` 往返 |
| 接战触发 T1 的几何圆心 | ✅ | 玩家主动冲进 BOSS 区仍算接战 |
| ~~AceSquad 的巡逻中心~~ | ❌ 删除 | 没有王牌机再绕它飞 |
| ~~AceSquad 的归巢 leash~~ | ❌ 删除 | `ANCHOR_ENGAGEMENT_RADIUS` / `ANCHOR_ORBIT_RADIUS` 两个常量废除 |

### 2.5.1 CSG 舰队摆位的地形校验（2026-07-28 新增）

> ⚠ **暂记于此**：Ladon 战斗群（CSG）目前**没有独立 spec**（见 [_INDEX 待补清单](../_INDEX.md)）。
> 以下两条 CSG 专属规则先落在本 spec，将来 `bosses/carrier-strike-group` 建档时整段迁走。

**(a) 摆位地形校验**——锚点吸附水面**只保证圆心在水上**，而舰队的包围盒约 1950 × 2200 px、
航母还要沿航向来回巡逻 ±1500 px：锚点靠岸时护卫舰会**直接刷在陆地上**（此前零校验）。

| 项 | 规则 |
|---|---|
| 评分 | 对一组（锚点, 朝向）数出**落在陆地上的点数** = 航母巡逻线两端 + 10 个护卫位 |
| 候选朝向 | **45° 步长**（一圈 8 个朝向） |
| 候选锚点 | 原锚点 + **5 个锚点偏移**（含原位） |
| 取舍 | 遍历候选组合，取**落地点最少**的一组；**一旦找到全水面解立即采用**（不再穷举） |
| 留痕 | 结果写事件日志；穷举完仍有落地点时**告警**（地图/锚点该修了，不静默） |

**(b) 承伤：电磁炮对同一艘舰的重复结算已修**——船体与它的挂点 / 弱点代理同时在战斗单位表里，
代理受伤会把伤害原样转发母舰，一条有半径的 hitscan 能同时扫到船体 + 多个 CIWS 代理，
**一发打出最高 5 × 150 = 750**，这才是"航母被一炮秒"的真正来源。
现按母舰归并、只保留沿弹道最靠前的那个命中点，**一发一舰只结算一次**
（规则全文见 [enemies/af-03 §3.2](../enemies/af-03.md)）。

> **航母 HP 保持 1200 不变**（用户拍板）：这是**修穿排，不是改血量**——
> 航母原本就该扛得住一发电磁炮，问题在结算次数，不在它有多厚。

### 2.6 BOSS 圈必须跟着 BOSS 走

猎手模型下，"战术地图上一个钉死在锚点的洋红圈 + 指向该圈的 HUD 箭头"是**假信息** ——
BOSS 已经不在那里了。

**规则**：事件层每帧把 `boss_zone["center"]` 同步为 encounter 的**存活成员质心**；
无存活成员时保持上一次的值不变（不写入）。

| 参数 | 值 |
|---|---|
| 同步源 | `encounter.get_display_members()` 中存活成员的位置平均 |
| 同步频率 | 每帧（写一个 Dictionary 字段，开销可忽略） |
| 圈半径 | **不变**（`BOSS_RADIUS = 2200 px`）—— 玩家仍看到完整的 BOSS 圈范围 |
| 无存活成员时 | 不写入，保留上次值 |

这样战术地图的圈与 HUD 的 `ZoneArrow` **零改动**自动跟随 —— 它们本来就读
`boss_zone["center"]`。CSG 二阶段已有一份私有的同款同步（同步到 F-14 质心），
本规则将其**上提为通用规则、由事件层单一所有**，删除 CSG 的私有副本。

### 2.7 不在本 spec 范围内的两件事（避免误判）

playtest 同时暴露了两个**看起来像猎手问题、实际不是**的现象，在此明确划界：

| 现象 | 真实归属 | 结论 |
|---|---|---|
| "BOSS 完全没有要躲的意思" | `is_boss_attacker()` 是一个**总的自保关闭开关**，它按设计屏蔽了王牌的全部规避机动入口 | **不改**。[ace-squadron-tier](ace-squadron-tier.md) 已定档"王牌不靠机动躲，靠热诱弹当命数（4 命，不解锁规避机动）"。本 spec 不推翻它 |
| "一轮骑射掉半数" | 热诱弹命数契约**从未实装**：spec 要 `max_flares=4 / burst_count=1`（4 条命），实际资源是 `max_flares=2 / burst_count=3` → 一次投放打光全部弹量 = **1 条命** | 归 ace-squadron-tier 阶段 3，与本 spec 并行修复 |

猎手化解决的是"BOSS 不来 + 挨打不算接战"；上面两条解决的是"BOSS 太脆"。三者叠加才是完整修复。

### 2.8 逐 BOSS 猎手化对照表

| BOSS | 类 | 猎手载体 | 改动 |
|---|---|---|---|
| **WRAITH SQUADRON** | `F47AceSquad` ← `AceSquad` | 四架 F-47 全部 | INBOUND 追玩家；废除 `ANCHOR_HOLD` |
| **POLTERGEIST**（CSG 二阶段） | `PoltergeistSquad` ← `AceSquad` | 四架 F-14 | 同上（继承基类改动，零额外代码） |
| **CARRIER STRIKE GROUP** | `CarrierStrikeGroup` | **舰载机**（F/A-18 × N、二阶段 F-14） | 舰船**不猎手**（物理上追不动，见下）；弹射出的 F/A-18 起飞即挂玩家为目标 |
| **MOTHER GOOSE** | `MotherGooseBoss` | 母舰本体 + MQ-X 精英 | 环绕**地图中心**的巡逻环 → 环绕**玩家**的巡逻环（见 §3.4） |

**为什么舰船不猎手**：CSG 的航母 30 节 ≈ 15 m/s，玩家机 400+ m/s。让舰队"追击"玩家在物理上是
一场笑话，观感只会是"船在原地扭动"。CSG 的猎手性由**它放出的飞机**承担 —— 这既符合真实航母战斗群的
交战方式，也符合用户"**所有 Boss 的王牌飞机**都会知道玩家的位置"的原话。

## 3. 行为与公式（How）

### 3.1 新增 directive verb：`PURSUE_UNIT`

[event-system](event-system.md) §5 明列"新指令 verb"为受支持的扩展位。本 spec 新增第 7 个 verb：

| verb | 参数 | 行为 |
|---|---|---|
| `PURSUE_UNIT` | `params.target`（一个 `CombatUnit`） | 每 tick 把 `aircraft.target_position` 设为 `target.global_position`；**没有抵达态**，永不自行结束；目标失效（`is_instance_valid` 为假 / 已击毁）时指令自动释放，AI 回归常规路由 |

字段默认与其它 verb 一致：`combat_disabled = true`（INBOUND 相武器冷）。

**为什么要新 verb 而不是"每 0.5s 重下一条 `FLY_TO_POINT`"**：
后者每次重下都会重置 `_directive_state`（`PATROL_RING` 的相位、`FOLLOW_PATH` 的航点游标），
且 `FLY_TO_POINT` 自带的抵达判定会在贴近时触发 `on_arrival` 分派 —— 语义上"追一个会动的单位"
根本不是"飞到一个点"。一个诚实的 verb 比一串定时器 hack 更容易重建，也更容易被下一个 BOSS 复用。

### 3.2 相位状态机（事件层）

```
        刷出
         │
         ▼
   ┌──────────────┐   T1 玩家进 BOSS 圈
   │  INBOUND     │   T2 玩家贴近成员 <2500px
   │  追玩家实时  │──  T3 任一成员被锁定      ──▶ ┌──────────┐
   │  位置，武器冷│   T4 任一成员受伤             │ ENGAGED  │
   └──────────────┘   （任一满足）                │ 正常战斗 │
                                                  └────┬─────┘
                                                       │ encounter.active
                                                       │ true → false
                                                       ▼
                                                  ┌──────────┐
                                                  │ VICTORY  │
                                                  └──────────┘
```

**没有反向边**。一旦 ENGAGED，不因玩家跑远而回退 —— 这是废除 `ANCHOR_HOLD` 的直接推论。

### 3.3 AceSquad 队级状态机的收缩

| 状态 | 旧 | 新 |
|---|---|---|
| `INTRO` | 经典通场进场 | 保留（沙盒 / 非事件路径） |
| `PURSUIT` | 默认战斗 | 保留，**成为唯一的战斗常态** |
| `CLOAK` | 隐形 5.5s | 保留 |
| ~~`ANCHOR_HOLD`~~ | 玩家远离锚点 → 绕锚点巡逻 | **删除**（枚举值、转移条件、enter/exit 全部移除） |

`PURSUIT` 的软维护（每 0.5s）逻辑不变：掉出 ENGAGE 就补回、远距开加力、Herbst 期间不打扰。
删掉 `ANCHOR_HOLD` 后，`_decide_next_state` 在 `PURSUIT` 分支只剩隐形判定。

### 3.4 Mother Goose 的猎手化

母舰是一架巨型飞行翼，不是战斗机 —— 它不做 BFM，它**压过来**。

| 参数 | 旧 | 新 |
|---|---|---|
| 巡逻环圆心 | 地图中心 `Vector2.ZERO` | **玩家实时位置** |
| 巡逻环半径 | `PATROL_RADIUS_PX = 4000`（并 clamp 到 `world_half - 1500`） | 不变 |
| 航点数 | 8 | 不变 |
| 圆心刷新间隔 | —（静态，只在 spawn 时算一次） | `2.0 s` |

效果：母舰始终在玩家外围 4000px 的环上盘旋，玩家往哪跑它跟到哪 —— "**你甩不掉这个东西**"。
半径不变意味着它不会贴脸（那会毁掉挂点/弱点的攻击窗口设计），但也绝不会被甩到地图另一头。

刷新间隔取 2.0s 而非 0.5s：8 航点的环重算是几十次三角函数，且母舰速度慢、玩家 2 秒内位移
远小于 4000px 半径 —— 0.5s 刷新是纯浪费。

### 3.5 CSG 舰载机的目标指派

F/A-18 弹射后当前**完全不被指向玩家**（依赖普通雷达扫描自然获取）。改为：
起飞宽限期（`FA18_TAKEOFF_GRACE = 4.0 s`）结束后，按 `AceSquad._pursuit_enter` 同款配方指派 ——
`acquire_target(player, TS_BOSS)` + `enter_engage_state()` + `boss_attacker = true`。

`TS_BOSS` 优先级天然绕过 ROE 感知门（= GCI 全知引导），与既有猎手系统同一条通路。

### 3.6 玩家引用必须是活引用（SEAM-019 同类）

`AceSquad._player` 是 **spawn 时缓存的玩家机引用**，而 `survivor_mode._set_player_aircraft()`
这个 chokepoint **没有登记它**（校验脚本只扫 `survivor_mode.gd`，扫不到经 spawner 传参的缓存）。

旧模型下这是慢性病（BOSS 只在 ENGAGED 后用一次）；**猎手模型下它是急性病** ——
BOSS 全程追 `_player`，玩家一按 1-4 切控或长机阵亡换帅，BOSS 就会去追一架**不再是玩家**的飞机，
甚至一架已释放的实例（硬崩，见 SEAM-020）。

**硬约定**：猎手目标必须**每次取用时**经一个活引用源解析，不得读 spawn 时快照：

| 层 | 活引用源 |
|---|---|
| 事件层（`BossEncounterEvent`） | `director.player` —— 已在 chokepoint 登记（`_event_director.player = ac`） |
| encounter 层（`AceSquad` 等） | 由事件层每 tick 注入，或经 `director.player` 取 |

取用前一律 `is_instance_valid()` + `is_destroyed` 双检。

## 4. 结构与组成（Structure）

| 部件 | 角色 |
|---|---|
| `AIDirective.PURSUE_UNIT` | 新 verb：追一个会动的单位，无抵达态 |
| `BossEncounterEvent` | 相位机；INBOUND 下发猎手指令、跑四触发器、切 ENGAGED |
| `AceSquad` | 队级状态机（删 `ANCHOR_HOLD`）；`PURSUIT` 承担全部战斗常态 |
| `CarrierStrikeGroup` | 舰船不变；F/A-18 弹射后加目标指派 |
| `MotherGooseBoss` | 巡逻环圆心改玩家实时位置 |
| `RoeDirector` | **不改** —— BOSS 的 `roe_posture` 恒为 `""`（豁免），已与 `"hunt"` 享受同等的感知门豁免与免 leash |

**刻意不做的**：不给 `Squad` 类加 `posture` / `aware` 字段。ROE 把中队状态存在单位 meta 上，
BOSS 又整体豁免于 ROE —— 为 BOSS 单独引一套姿态字段是纯粹的二阶机制，不做。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **BOSS 主动来找**：刷出后不给任何玩家输入，BOSS 与玩家的距离**单调下降**至接战；
      日志中不存在 `→ ANCHOR_HOLD`
- [ ] **12km 闭合时间**：从刷出到 ENGAGED，无玩家配合时应在 **25~35 秒**内完成
- [ ] **打第一枪即接战**：玩家在 10km 外锁定 BOSS → 日志中 `ENGAGED` 时间戳与首次 `is_locked`
      的间隔 **< 0.5s**（不再是 8.4 秒）
- [ ] **甩不掉**：玩家接战后全速向地图另一端飞 30 秒，BOSS 仍在追击（不回巢、不脱战）
- [ ] **玩家切控安全**：BOSS 追击途中按 1-4 切控 / 触发换帅，BOSS 目标随之切到新玩家机，无崩溃
- [ ] **Mother Goose 跟随**：母舰巡逻环圆心跟随玩家，玩家横穿地图后母舰仍在其 ~4000px 外围
- [ ] **CSG 舰载机**：F/A-18 弹射 4s 后日志出现对玩家的目标指派；航母**不**追击（保持原航线）
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（见 performance-guidelines）
- [ ] 已知 seam 未触碰 / 已妥善处理（SEAM-019 活引用、SEAM-020 已释放引用传参）
- [ ] i18n：玩家可见文本走 tr()，三语已补（见 reference/i18n.md）

## 6. 实现计划（Task Pipeline）

### 阶段 1 — directive 地基
- [x] `AIDirective.Type` 加 `PURSUE_UNIT` + `pursue()` 工厂
- [x] `AIController._process_directive` 加执行分支（目标失效自动释放）
- [x] 同步 event-system spec 的 verb 表（6 → 7）

### 阶段 2 — 事件层猎手化
- [x] `_apply_pre_stage_directives_ace` 改下 `PURSUE_UNIT(player)`
- [x] `_check_engagement_trigger` 加 T3（被锁定）/ T4（受伤）
- [x] 出生点改"玩家机头前方 ±30° 扇面 6000px"，废除 `_far_map_edge_from`
- [x] 玩家引用全部经 `director.player` 解析（SEAM-019）——
      新增 `BossEncounter.set_player_ref()` 基类契约，三个子类各自重定向自己的全部缓存
      （含 MotherGoose → controller → SwarmDirector 整条链）
- [x] BOSS 圈中心跟随存活成员质心（§2.6），CSG 的私有同款同步已删

### 阶段 3 — encounter 层
- [x] `AceSquad` 删 `ANCHOR_HOLD`（枚举 / 转移 / enter / exit / 两个常量）
- [x] `MotherGooseBoss` 巡逻环圆心改玩家实时位置 + 2s 刷新（位移 < 800px 不重下航点）
- [x] `CarrierStrikeGroup` F/A-18 弹射即指派玩家目标（`acquire_target(TS_BOSS)`）

### 阶段 4 — 收尾
- [x] 无头断言 `--bench=boss_hunter`（60 项，含 PURSUE_UNIT 执行分支：节流 / 无抵达态 / 目标失效自动释放）
- [x] 跑 `--bench=all` 回归门（33 项 PASS）
- [x] 更新 §7 锚点 + 同步 reference 索引 + `_INDEX.md`
- [x] 跑 `python tools/verify_doc_anchors.py` 与 `verify_player_ref_holders.py`
- [ ] **§5 验收逐条 playtest**（唯一剩余项）

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 新 verb 定义 + `pursue()` 工厂 | `scripts/events/ai_directive.gd` |
| verb 执行分支 `_directive_pursue_unit_step` | `scripts/ai_controller.gd` |
| 相位机 / 四条接战触发器 / 猎手出生点 / BOSS 圈同步 | `scripts/events/boss_encounter_event.gd` |
| 玩家引用重定向基类契约 `set_player_ref` | `scripts/survivor/boss_encounter.gd` |
| 队级状态机（无归巢态）+ 角色 | `scripts/survivor/ace_squad.gd` |
| 母舰巡逻环跟随玩家 | `scripts/survivor/mother_goose_boss.gd` |
| 母舰玩家引用链下游 | `scripts/survivor/mother_goose_controller.gd`、`scripts/ai/swarm/swarm_director.gd` |
| CSG 舰载机目标指派 + 舰队摆位地形校验（§2.5.1a） | `scripts/survivor/carrier_strike_group.gd` |
| 电磁炮对舰按母舰归并结算（§2.5.1b） | `scripts/equipment/railgun_equipment.gd` |
| 舰队 BOSS 的 T3/T4 聚合 `is_engaged_by_lock` / `boss_hp_pool` | `scripts/naval/naval_unit.gd` |
| 无头断言（`--bench=boss_hunter`） | `scripts/tests/test_boss_hunter.gd` |
| reference 索引行 | script-index.md（`ace_squad.gd` / `boss_encounter_event.gd` 两行）、enemy-index.md（F-47 状态机段） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-22 | 1 | 初稿并定档。用户裁定：取消"BOSS 飞到圈里等玩家"的概念，全 BOSS 王牌机改猎手型（知道玩家位置 + 主动追击）。由 playtest log 20260722_005100 驱动（BOSS 锚点空转 47.6s、玩家 10km 外白嫖、苏醒 3s 内长机阵亡）。核心四条：INBOUND 相追玩家实时位置 / 接战触发器扩到四条（+被锁定 +受伤）/ 废除 ANCHOR_HOLD 归巢 / 出生点从"最远地图角"改"机头前方 12km"。舰船不猎手（物理不可行），CSG 猎手性由舰载机承担 |
| 2026-07-28 | 2 | **CSG 摆位与承伤（§2.5.1，暂寄本 spec —— CSG 尚无独立 spec）**：①**舰队摆位地形校验**——锚点吸水只保证圆心在水上，而舰队 bbox ≈1950×2200 px、航母还沿航向巡逻 ±1500 px，靠岸锚点会把护卫舰刷到陆地上（此前零校验）；现按"候选朝向 45° 步长 × 5 个锚点偏移"打分（数航母巡逻两端 + 10 个护卫位有几个在陆地），取落地点最少的一组、找到全水面解立即采用，结果写日志、仍有落地点则告警。②**电磁炮对同一艘舰重复结算已修**——船体与挂点/弱点代理同时在单位表且代理转发伤害，一发能打出最高 5×150=750（"航母被一炮秒"的真正来源）；现按母舰归并只取沿弹道最前的命中点，一发一舰只结算一次。**航母 HP 保持 1200 不变**（用户拍板：修穿排不改血量）。③附：CIWS 真弹周期 3→2（拦截 DPS ×1.5）记在 [aa-fire-awareness §2.1](aa-fire-awareness.md) |
| 2026-07-24 | 1 | 修 T3/T4 对舰队 BOSS 失明的实现漏洞（§2.2 补语义）。玩家从远距离锁定并导弹命中 CSG 航母却要贴脸才 ENGAGED —— 根因：船体锁定免疫（锁的是 MountTarget 代理）+ 伤害走 hull_hp/部件不碰 `CombatUnit.hp`，而 T3/T4 直读船体 `is_locked`/`hp`。修法：`NavalUnit` 暴露 `is_engaged_by_lock()`（聚合代理锁定态）/ `boss_hp_pool()`（hull+挂点+弱点总血），`boss_encounter_event` 的 T3/`_members_hp_total` duck-type 调用。不动 T2 几何半径（§1.4 反模式）。`--bench=boss_hunter` +6 断言 |
