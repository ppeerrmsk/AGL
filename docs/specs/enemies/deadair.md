---
id: deadair
kind: enemy
status: in-progress
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [enemy-pool-expansion, squad-xp-threat-balance, global-awareness-roe, enemies/snowblind]
reconstruction_complete: false
---

# DEADAIR「断讯」支援机（累积 JAM 光环 Schemer）

> 一架始终可见、可选、可攻击的无武装电子战支援机：它用移动干扰场保护附近敌军，
> 远射导弹通常会在接近核心前累计失导；玩家飞机则有一段明确的入圈窗口，可以压近后让机炮自动击毁核心。

`DEADAIR / 断讯` 是工作名；改名不改变本 spec 的机制与数值。

## 1. 设计意图（Why）

- **体验目标**：给“锁定后远距离发射导弹”加入一个可读的空间反制题。玩家先看见 3000m 干扰圈和核心位置，
  再选择绕开、从圈缘近射，或直接压进机炮窗口；正确近距切入应在自身 JAM 生效前获得一次自动机炮攻击机会。
- **角色定位**：`Schemer / ew`。本体没有武器、flare 或战斗 AI，威胁完全来自移动 JAM 场和两架动态护卫；
  一旦玩家穿过远程保护层，本体仍是 HP55、无额外命数的脆弱支援平台。
- **与 Snowblind 的差异**：Snowblind 改变“能否发现/锁定”；DEADAIR 不隐藏任何实体，只改变“导弹能否穿过场”和
  “飞机能在圈内停留多久”。Snowblind 的解法是破幕，DEADAIR 的解法是一次快速近距攻击跑。
- **自动开火契约**：玩家不新增机炮按键。玩家只负责让飞机在 8 秒窗口内进入既有机炮射程与射界，机炮仍按共享火控自动开火。
- **Litmus 自检**：
  - 信息察觉：敌对红紫外圈、向内扫过的干扰带、单位分段累积环和导弹逐渐变色的尾迹让危险与进度都可见。
  - 尺度：本体采用 Sentinel 纯支援基线，650km/h、HP55、Token4，均在既有区间内。
  - 一击毙命：任何有效普通导弹或机炮命中仍可当场击毁本体；JAM 场不是 HP、装甲或物理护盾。
  - 手感：3000m 圈缘到常规约 1700–2000m 机炮窗口，在 600km/h 直线闭合下约需 6.0–7.8s，刻意压在 8s 累积阈值内。
  - AI 演戏：本体在护卫后方维持支援位置，被贴近后只会慢速背离，不进入绕圈狗斗。
  - 性能：一个场只由 5Hz 中央控制器扫描；不在 Aircraft/Missile 下新增逐实体处理节点。
- **现实参考例外**：DEADAIR 与 Snowblind 一样是机制优先的虚构无人电子战平台，不声称对应现实机型；
  飞行、雷达和生存逐字段复用现有 Sentinel 支援基线，避免用虚构身份任意堆数值。
- **反模式规避**：不做导弹绝对免疫、不做进圈瞬时 JAM、不让核心隐形或不可选、不让光环造成伤害/减速，
  不让敌机在圈内获得额外属性，也不通过逐导弹 `_process` 或全屏 CPU 噪声实现。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 本体基础属性

> 速度单位 km/h；距离默认用 m，并同时给出落地 px 值；`PIXELS_PER_METER = 0.5`。

| 字段 | 值 | 说明 |
|---|---:|---|
| EnemyType / type_tag | `DEADAIR` / `deadair` | 枚举值实现时只在末尾追加，不固定整数 |
| display_name | `DEADAIR` | 工作显示名；Archetype 不进入玩家可见文本 |
| is_unmanned / no_pilot | `true / true` | 无线电沉默且免疫 FEAR；JAM 仍可正常作用于本体 |
| archetype / role | `Schemer / ew` | 专属支援循环；无 Gladiator/Lancer 兜底 |
| max_hp / armor | `55 / 0` | 与 Sentinel 相同；普通有效命中一击击毁 |
| max_speed / cruise_speed | `650 / 400` | 与 Sentinel 相同的慢速支援平台 |
| stall_speed_base | `150` | 与 Sentinel 相同 |
| acceleration / deceleration | `20 / 30` | 与 Sentinel 相同 |
| g_drag_factor | `2.0` | 与 Sentinel 相同 |
| max_g / max_g_structural | `3.0 / 4.0` | 与 Sentinel 相同；没有战斗机动能力 |
| roll_rate | `1.2` | 与 Sentinel 相同 |
| max_altitude / climb_rate_max | `8000m / 80` | 与 Sentinel 相同 |
| thrust_to_weight / drag_coefficient | `0.45 / 0.035` | 与 Sentinel 相同 |
| afterburner_thrust_mult | `1.0` | 无加力逃生能力 |
| fuel_capacity / normal / ab | `800 / 0.8 / 0.8` | 与 Sentinel 相同 |
| radar_range | `1200px = 2400m` | 只供支援导航，不用于攻击；低于 F-16 的理由是纯支援平台 |
| radar_half_angle / lock_time | `20° / 99.0s` | 不进入有效锁定流程 |
| gun / missile / rocket / equipment | **无** | 任何等级均不注入武器 |
| flare | **无** | 玩家突破干扰场后没有额外命数 |
| combat flags | `enable_combat=false`、`attack_air_targets=false` | 不选敌、不锁定、不攻击、不进入 BFM |
| icon_color / wing_color | `#A94F48 / #5C343C` | 暖红敌方色，不把绿/青友军色用于本体 |
| silhouette | `deadair` | 扁菱形机身 + 四个短电子战阵列；与 Snowblind 长菱形区分 |

### 2.2 累积 JAM 场

| 字段 | 值 | 说明 |
|---|---:|---|
| `FIELD_RADIUS_M` | **3000m** | 世界半径 `1500px`；与玩家既有 JAM 光环同尺度 |
| `FIELD_TICK_S` | **0.20s** | 5Hz 单控制器扫描 |
| `EXPOSURE_THRESHOLD` | **8.0 等效秒** | 达到前不施加 gameplay JAM；只显示累积进度 |
| CombatUnit 累积率 | **1.0 / s** | 连续在圈内 8.0s 达阈值 |
| guided Missile 累积率 | **4.0 / s** | 连续在圈内 2.0s 达阈值；体现导弹航电更易被压制 |
| 圈外宽限 | **1.0s** | CombatUnit 离圈后先保留进度 1.0s，避免边界采样闪烁 |
| CombatUnit 圈外衰减 | **2.0 / s** | 宽限后每秒减 2 等效秒；满进度 4s 清空 |
| Missile 圈外处理 | **立即清除该场累积** | 高速弹体不保留跨次进入的历史；同时避免长期字典残留 |
| `JAM_REFRESH_DURATION` | **0.50s** | CombatUnit 达阈值且仍在圈内时，每 0.20s 刷新标准 JAM |
| `COLLAPSE_S` | **0.60s** | 核心击毁/撤离清理后的场视觉消散时间 |
| 作用 CombatUnit | 与本体敌对的全部存活单位 | 包含 `TEAM_PLAYER` 直属小队与 `TEAM_ALLY` 飞机、地面单位、舰船；不含 HOSTILE |
| 作用 Missile | 与本体敌对、`is_active && has_guidance && !is_flare_jammed` 的导弹 | 包含玩家、ALLY 飞机/SAM/舰船发射的制导弹 |
| 不作用对象 | 子弹、火箭、炸弹、无制导弹体、敌方导弹 | 机炮是主要反制；不把 JAM 偷换成物理护盾 |
| 重叠 | DEADAIR 同场最多 1；且与 Snowblind 互斥 | 两种移动支援场不能同时存在；不设计场叠加或优先级 |

### 2.3 刷怪经济

| 字段 | 值 | 说明 |
|---|---:|---|
| 解锁 | `response_level >= 9` | Snowblind 后一档出现；先学会破幕，再学习近距穿场 |
| role 桶 | `ew` | 进入敌机扩池电子战桶 |
| 池内基础权重 | `0.40` | 略低于 Snowblind 的 0.45 |
| Token 成本 | `4` | 仅本体；纯支援机不按高端战斗机定价 |
| 同场实例上限 | `1` | 场内只能有一个 DEADAIR |
| 战区阶段累计上限 | `2` | 击毁不返还累计名额 |
| 同型生成冷却 | `180s` | 死亡、撤离或清理后都开始计时 |
| 初始生成形式 | `1` 本体 + `2` 动态护卫 | 与 Snowblind 相同的特殊支援包 |
| 护卫候选 | 当前响应等级允许的任何常规战斗机 | 两槽独立抽取，可同型或混编 |
| 硬排除 | Snowblind、DEADAIR、BOSS、王牌、Adds、事件专属、非战斗支援单位 | 只使用常规热度战斗机池 |
| 预算门槛 | `4 + escort_1_token + escort_2_token` 全额可支付 | 当前最低完整编成预算为 10；不足时整包跳过，不刷无护卫核心 |
| 作战高度权重 | LOW/MID/HIGH = `0.10 / 0.65 / 0.25` | 以中空支援为主；本体与初始护卫同档 |
| 击杀 XP | `80` | 走统一小队共享/稀释管线；护卫各自正常计 XP |
| 等级缩放 | 本体全部固定 | 难度来自 JAM 场与动态护卫，不缩放 HP/场半径/累积率 |

### 2.4 视觉规格

| 元素 | 规格 | 目的 |
|---|---|---|
| 场边界 | 3000m 红紫外环，宽 `6px`，稳定常亮；每 1.6s 有一条低对比扫描带向内收缩 | 明确敌对范围与核心位置 |
| 场内部 | 单 mesh shader；透明度 `0.06–0.10`，稀疏断续干扰纹，不遮挡地图/单位 | 场可读但不复制 Snowblind 实体遮蔽 |
| 本体 | 暖红机体，始终显示标签、目标框、雷达点和尾迹 | 明确它可选、可锁、可攻击 |
| CombatUnit 累积 | 目标外圈 8 段短弧，按 `exposure / 8` 逐段点亮；未满不显示 JAM 状态条 | 把“还剩多久能开火”变成可读倒计时 |
| Missile 累积 | 复用既有尾迹材质，仅把颜色按进度从原色 lerp 到黄绿；达阈值时一次短促静电脉冲 | 不新增逐导弹子节点或独立 `_draw` |
| 生效 JAM | 继续使用现有 JAM 状态条/派生标记/武器门，不新造第二种干扰状态 | 保持全游戏词义一致 |
| 坍塌 | 0.60s 内外环断成 8 段向外淡出，内部干扰纹停止 | 核心击毁后即时、明确地解除机制 |

- 外圈必须使用敌对红紫作为身份色；黄绿只出现在“电子干扰累积/生效”的局部纹理与被影响目标上，
  不把整架敌机或整个边界染成友军绿。
- 世界视图与 Tab 战术图都显示相同 3000m 边界；Tab 只画稳定圆和中心敌机图标，不播放扫描噪声。
- 动画完全由单 mesh shader 时间推进；状态变化只更新 uniform，不高频 `queue_redraw()` 或 CPU 重建几何。

## 3. 行为与公式（How）

### 3.1 累积与 JAM 结算

```text
每 0.20s，对本场独立维护 exposure[id]：
  对每个与核心敌对的存活 CombatUnit：
    若 distance_to(core) <= 1500px：
      exposure += 0.20 * 1.0
      outside_time = 0
      若 exposure >= 8.0：
        exposure = 8.0
        apply_status(JAM, 0.50s, mode=max)
    否则：
      outside_time += 0.20
      若 outside_time > 1.0：exposure = max(0, exposure - 0.20 * 2.0)
      若 exposure == 0：删除条目

  对每枚与核心敌对的 active + guided + unjammed Missile：
    若 distance_to(core) <= 1500px：
      missile_exposure += 0.20 * 4.0
      若 missile_exposure >= 8.0：
        is_flare_jammed = true
        has_guidance = false
        删除该场的 missile_exposure 条目
    否则：
      立即删除该场的 missile_exposure 条目
```

- CombatUnit 的 JAM 完全复用 `StatusEffects.JAM`：雷达锁定冻结、飞机/地面/海军武器封锁等既有消费者全部生效；
  本 spec 不新增 SLOW、伤害或命中率惩罚。
- 标准负面状态免疫继续有效；控制器仍可显示累积到满，但 `apply_status` 不得绕过既有免疫门。
- 导弹达阈值后走既有 `is_flare_jammed` 无害失导契约：不再命中、不计入来袭伤害、CIWS 不浪费拦截火力。
- 若既有技能让已 JAM 导弹稍后恢复制导，它在场内重新从 0 累积；不会继承旧进度，也不会获得场免疫。
- 核心击毁时立即清除所有未完成 exposure 和累积表现；已经作用于 CombatUnit 的 JAM 最迟 0.50s 自然消退，
  不强删其它来源的 JAM；已经失导的导弹不会因核心死亡恢复制导。

### 3.2 近距机炮窗口

```text
进入场边界时 exposure = 0
普通飞机可用时间 = 8.0s
导弹可用时间 = 8.0 / 4.0 = 2.0s

直线闭合到机炮窗所需时间 = (3000m - 当前机炮有效射程) / ground_speed
```

- 以 600km/h（166.7m/s）和 2000m 机炮窗为例，闭合耗时 `1000 / 166.7 ≈ 6.0s`，剩约 2s 对准/开火。
- 以 600km/h 和 1700m 短机炮窗为例，闭合耗时约 `7.8s`，是最紧的基线；更快飞机获得更宽窗口。
- 玩家若在圈内盘旋、转错方向或被护卫拖住超过 8s，会进入持续 JAM，机炮也会被标准武器门封锁；
  正确恢复方式是离圈，经过 1s 宽限后让进度以 2/s 衰减，再组织下一次攻击跑。
- 场不是导弹硬免疫：从圈内近距离发射、目标靠近边缘、或飞行时间短于 2s 的导弹仍可能先命中。
  这是允许的空间技巧；设计目标是明显压低远射可靠性并鼓励机炮，不是强制唯一解。

### 3.3 支援状态机

| 状态 | 进入条件 | 行为 | 离开条件 |
|---|---|---|---|
| `INGRESS` | 特殊支援包生成 | 与两架动态护卫从边缘飞入；JAM 场创建当帧生效 | 到达战区/巡逻锚附近 |
| `COVER` | 正常在站 | 位于护卫质心相对最近敌对单位的后方 `1200–1800m`；巡航，不锁定不开火 | 敌对 CombatUnit 距本体 ≤1200m → PRESSURED；连续10s无可保护敌机 → EGRESS |
| `PRESSURED` | 玩家/ALLY 贴近 1200m | 以普通最高速度朝最近威胁反方向直飞；不加力、不投 flare、不规避、不进入 BFM | 最近威胁 >1800m 连续3s → COVER；本体死亡 → COLLAPSE |
| `EGRESS` | 连续10s无本体外可保护敌机，或 BOSS 阶段开始 | 以普通最高速度飞向最近世界边界外；场继续生效 | 飞出/超时清理 → COLLAPSE |
| `COLLAPSE` | 击毁、撤离完成或模式清理 | 停止扫描，清未完成累积，0.60s 消散 | 结束后释放视觉/控制器 |

- 动态护卫保持各自原型 AI、Token、武器、flare、XP 和实例上限；进入场不会获得数值强化。
- DEADAIR 与 Snowblind 共用“移动支援场在场互斥”门：任一仍在场时，另一种特殊包本轮直接跳过；
  只禁止同时在场，不合并两者各自的阶段累计次数或同型冷却。
- F5/debug 创建必须同帧注册核心与两架护卫、同帧启用场，不依赖下一轮 Token 统计。

## 4. 结构与组成（Structure）

- `Aircraft` 本体：独立敌版参数、轮廓与无武装支援 AI；不读取玩家飞机资源。
- `DeadairController`：每个在场本体唯一的 5Hz 范围控制器；持有 CombatUnit/Missile 两张累积字典、状态机和清理入口。
- `DeadairFieldVisual`：一个世界空间 mesh + shader；只消费核心位置、半径、状态与 collapse 进度。
- CombatUnit 累积表现：控制器只写一个 `0..1` 的显示值；共享渲染器在既有绘制路径中画 8 段短弧，不创建子节点。
- Missile 累积表现：控制器写一个 `0..1` 显示值；既有尾迹读取它做颜色插值，不新增逐弹 `_process/_draw`。
- 活跃导弹集合必须由导弹生命周期维护的共享注册表提供；控制器不得在 5Hz tick 中调用 `get_children()` 或扫描场景树。
- 刷怪层使用“特殊支援包”入口创建本体与两架动态护卫，并维护 DEADAIR/Snowblind 在场互斥、Token、冷却与阶段累计。
- 生命周期只有控制器拥有本场累积状态；死亡、撤离、BOSS 转阶段、换场与 debug 清理统一走幂等 `collapse()`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] DEADAIR 生成当帧显示 3000m 红紫干扰圈；真实本体始终可见、可选、可锁、可被自动攻击。
- [x] 敌对 CombatUnit 在圈内 7.8s 不受 JAM，累计达到 8.0s 后 0.20s 内进入标准 JAM；持续留圈时不断档。
- [ ] CombatUnit 离圈 0.5s 内 JAM 消退；1.0s 内累积不衰减，之后以 2.0/s 衰减，满进度再过 4.0s 清零。
- [x] 玩家直属单位与 `TEAM_ALLY` 飞机、SAM/AA/舰船都遵守同一敌对口径；HOSTILE 单位完全不受本场影响。
- [x] 敌对制导导弹在圈内 1.8s 不失导，达到 2.0s 后 0.20s 内置 `is_flare_jammed` 并永久无害；离圈立即清累积。
- [x] 子弹、火箭、炸弹、无制导弹体可以正常穿过干扰场并命中；场不提供碰撞、装甲、减伤或伤害。
- [ ] 从场外对准核心发射的普通远射导弹通常在命中前失导；从足够近的位置发射、飞行时间 <2s 的导弹仍可击毁核心。
- [ ] 600km/h 飞机从圈缘直线压向 2000m 机炮窗时，在首次 JAM 前获得约 2s 射击余量；一次有效机炮命中当场击毁 HP55 本体。
- [ ] 玩家在圈内拖延超过 8s 后机炮确实被标准 JAM 门封锁；离圈恢复后可以再次组织攻击跑。
- [ ] 标准 JAM 免疫不被绕过；已有 JAM 导弹恢复制导后若仍在圈内，会从 0 再次累积。
- [ ] 本体击毁后 0.60s 内场视觉坍塌、所有未完成累积表现消失、CombatUnit JAM 最迟 0.50s 自然消退；其它来源 JAM 不被误删。
- [x] 初始编成固定为 1 本体 + 2 动态护卫；预算不足、同场已有 DEADAIR/Snowblind、同型冷却中或阶段累计已满时不生成。
- [x] 动态护卫使用各自独立普通敌版参数并正常计 Token/上限/XP；场不会强化护卫，也不作用于敌方导弹。
- [x] F5/debug 可直接刷 DEADAIR 特殊包，创建当帧场与护卫完整生效；不等待正式刷怪计数刷新。
- [ ] 世界视图与 Tab 图均能读出边界/核心；8段累积环和导弹尾迹变色与真实进度一致，无友军色身份误判。
- [ ] 生命周期：本体死亡、撤离、BOSS 转阶段、返回主菜单、debug 清场均不残留累积字典、视觉或已释放引用。
- [ ] 自动回归覆盖阈值、衰减、阵营、导弹失导、近距存活窗口、互斥生成、清理与标准免疫。
- [ ] 性能：控制器严格 5Hz、同场最多1、无逐实体处理节点、无 tick 内场景树扫描；Sentinel + Lv5/Lv15 压测 FPS 不低于60且相对掉幅 <15。
- [x] i18n：图鉴名/描述/debug 标签三语齐全；Archetype 不进入玩家可见文本。
- [x] 文档：本 spec 已登记 `_INDEX.md`；实现后同步 enemy/script/code index，并通过当前文档校验。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 纯函数规则与集中累积控制器
- [x] 建 DEADAIR 参数资源、5Hz 控制器与纯函数测试：8s阈值、4×导弹、1s宽限、2/s衰减、圈外清弹。
- [x] 为 CombatUnit/Missile 增加只用于显示的 exposure ratio，并建立幂等清理；不新造第二种 JAM 状态。
- [x] 建活跃导弹共享注册表，覆盖 spawn、命中、失活、queue_free 与换场清理；所有读取前验证实例有效。

### 阶段 2 — 支援 AI、场视觉与机炮竞速窗口
- [ ] 接 COVER/PRESSURED/EGRESS/COLLAPSE；本体无战斗 AI、无 flare、无武器。
- [x] 建单 mesh shader、Tab 稳定圆、8段 CombatUnit 累积环与尾迹颜色插值；不新增逐实体节点。
- [ ] 做真实运动/自动火控闭环 bench，断言 600km/h 基线从圈缘进入机炮窗后能在 8s 前实际出膛并击毁核心。

### 阶段 3 — 刷怪、debug、图鉴与回归
- [x] 按 enemy-index 13 步清单接 EnemyType、注册表、Token、2护卫特殊包、DEADAIR/Snowblind互斥、F5 与图鉴/i18n。
- [ ] 新增定向 bench，覆盖玩家/ALLY/地面/海军/导弹、免疫、恢复制导再累积、死亡/BOSS/换场清理。
- [ ] 跑 spawn_pool、文档校验、Sentinel + Lv5/Lv15 压测与人工机炮攻击跑；用日志校准 8s/4×，不靠加 HP 调难度。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 本体参数 | `resources/enemy_deadair.tres` |
| JAM 场控制器 | `scripts/survivor/deadair_controller.gd` |
| 场视觉 | `scripts/survivor/deadair_field_visual.gd` |
| 导弹累积与失导 | `scripts/missile.gd`、`scripts/missile_manager.gd` |
| 共享状态/表现 | `scripts/combat_unit.gd`、`scripts/aircraft_renderer.gd`、`scripts/trail_ribbon.gd` |
| 刷怪/特殊支援包 | `scripts/survivor/enemy_pool_registry.gd`、`scripts/survivor/survivor_spawner.gd`、`scripts/survivor/survivor_data.gd` |
| debug / 图鉴 / i18n | `scripts/survivor/survivor_debug_spawn.gd`、`scripts/meta/career_archive_ui.gd`、`i18n/translations.csv` |
| reference 索引 | `docs/reference/enemy-index.md`、`docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-08 | 1 | 初稿：3000m 移动 JAM 场；CombatUnit 8s、导弹 4×=2s 累积；标准 JAM 0.5s 刷新；圈外 1s 宽限后 2/s 衰减；HP55 无武装核心 + 2动态护卫；与 Snowblind 在场互斥；明确近距机炮攻击跑为主要解法。 |
| 2026-08-08 | 2 | 核心实现：5Hz 集中控制器、CombatUnit/Missile 真实 JAM 路径、活动导弹注册表、单 mesh 场/八段环/尾迹与 Tab 表现、特殊包与正式/debug 互斥、图鉴/i18n；新增 `deadair` 定向回归和 `deadair_stress` 主循环压力场。保留人工视觉与真实机炮攻击跑验收后再转 done。 |
| 2026-08-08 | 3 | 修正 F5 可达性：普通单机、小队、Sentinel 与经这些入口生成的 Snowblind/DEADAIR 特殊包不再复用地图边缘 ingress，改为玩家周围约 2200m 外六方位轮换即时生成；正式增援与事件航路不变。 |
