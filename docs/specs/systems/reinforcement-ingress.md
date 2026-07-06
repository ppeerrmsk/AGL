---
id: reinforcement-ingress
kind: system
status: in-progress  # 阶段 1~3 代码落地 + 无头回归绿（test_map_expansion 入场段）；差 §5 playtest/性能验收
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [survivor-loop, map-system, map-expansion]
reconstruction_complete: false
---

# 增援入场 —— 地图边缘中队涌入 + 中央锚点巡逻

> 玩家视角：增援敌机不再"凭空出现在面前"，而是以完整中队从地图边缘飞入，向地图中部集结巡逻；
> 镜头拉到任何地方，看到的敌机都有可信的来路。战场有"前线不断有敌人涌入"的持续感。

## 1. 设计意图（Why）

### 1.1 要根治的问题（实证根因）

现行旅途刷怪（survivor-loop §4.2）把增援刷在**玩家周围 3200 px、前方 ±70° 扇形**，
"不在屏幕内"只是软约束。RTS 自由镜头下这套机制有两个实锤破绽：

1. **镜头挪开再挪回 = 一片敌机凭空出现**。刷怪锚定的是玩家坐标而非镜头；玩家把镜头
   拉去看别处的几十秒里，自己身边 3200 px 处照常刷怪。镜头挪回来，一堆"没有来路"的
   敌机已经站在原本确认过是空的空域里。
2. **拉满镜头时软约束必然失败**。`SPAWN_DISTANCE=3200` 按旧 `ZOOM_MIN=0.4`（可视对角
   半径 ≈2750 px）标定；`ZOOM_MIN` 放宽到 0.2 后可视对角半径 ≈5500 px > 3200 px——
   第一遍"屏幕外"采样 8 次必然全失败，第二遍直接放弃该约束，敌机**当着玩家的面刷出来**。

另外，闲置敌机的巡逻航点每 8 s 重锚到**玩家当前位置**周围 800~1500 px 的圆环——
本质是"磁铁式"跟踪，同样没有可信的空间轨迹（玩家飞多远，闲置敌机都"漂移"跟过来）。

### 1.2 体验目标

- **出现即有来路**：每一架增援敌机的首次出现位置都在地图边界之外，向内飞入。
  观察者无论何时把镜头对准任何一块内陆空域，都不会看到敌机 materialize。
- **前线感**：增援以中队建制涌入 → 向地图中部集结 → 驻空盘旋，Tab 战术图上能看到
  敌人"占据中央空域"的持续存在，而不是一团跟着玩家漂的雾。
- **压力守恒**：主动威胁继续由猎手系统（hunter）供给，不因巡逻锚点离开玩家而变成挂机局。

### 1.3 Litmus 自检（DESIGN_PHILOSOPHY）

- **难度可读**：涌入可被观察、可被预判（看见边缘进入的中队 → 决定拦截还是规避）。
- **安全玩法有成本**：躲在角落不清中央巡逻群 → 敌人存量持续累积（token 不回收），
  压力自然上涨；hunter 照常点名追击。
- **反模式规避**：不引入每帧全场扫描（全部逻辑骑既有 tick）；不做任何"传送/挪坐标"
  式的位置修正（入场、巡逻、退场全程物理飞行，符合 [[feedback_formation_physical_elegance]]）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 新增常量

| 常量 | 值 | 说明 |
|---|---|---|
| `INGRESS_SPAWN_OUTSET_PX` | 400 | 生成点在世界边界线**外**的推出量（相机余量 2500 px 内，跨线飞入可被看见） |
| `INGRESS_EDGE_CANDIDATES` | 16 | 每次入场在边界周长上均匀取的候选点数 |
| `INGRESS_MIN_PLAYER_DIST_PX` | 5000 | 候选边缘点距玩家的硬下限（贴边飞行的玩家身边不会"背后出兵"） |
| `ANCHOR_DISC_RADIUS_FRAC` | 0.35 | 巡逻锚点盘半径 = 0.35 × `WORLD_HALF_PX`（30 km 图 ≈2625 px；已拍板的 60 km 图 ≈5250 px，自动随扩图缩放） |
| `ANCHOR_ZONE_CLEARANCE_PX` | 800 | 锚点距任何 AVAILABLE/SELECTED 战区圆边的最小距离（不污染战区任务空间） |
| `ANCHOR_MIN_SEPARATION_PX` | 2500 | 新锚点与现存活跃锚点的最小间距（巡逻群摊开，不叠罗汉） |
| `ANCHOR_ARRIVE_DIST_PX` | 900 | 长机距锚点小于此值 → TRANSIT 转 ONSTATION |
| `PATROL_RING_RADIUS_PX` | 1400 ± 400 | 驻空盘旋环半径（每中队随机一次，4 航点环） |
| `EGRESS_STALE_SEC` | 45 | 中队连续无交战达此时长才有退场资格 |
| `EGRESS_FREE_OUTSET_PX` | 800 | 全员飞出边界线外此距离才释放（绝不在画面内消失） |
| `EGRESS_MAX_CONCURRENT` | 1 | 同时处于退场状态的中队数上限（避免"集体大撤退"观感） |
| `OPENING_GARRISON_SQUADS` | 2 | 开局 t≈0 直接以 ONSTATION 状态预置在锚点上的中队数 |

### 2.2 退役 / 语义变更的旧常量

| 常量 | 处置 |
|---|---|
| `SPAWN_DISTANCE`（3200） | **退役**。生成位置改由边缘候选点算法决定，不再锚定玩家 |
| `TRAVEL_SPAWN_FAN_HALF`（±70°） | **退役**（旅途增援不再有"玩家前方扇形"概念；奖励任务/事件/Adds 的机头沿途原则**不变**，见 §3.6） |
| `FAR_CLEANUP_DISTANCE`（7000） | **保留**，但只对**非** reinforcement 类别生效（F5 调试刷怪、无类别遗留单位）；增援的回收改走 EGRESS（§3.5） |

### 2.3 明确不变项

| 项 | 保持 |
|---|---|
| Token 预算公式 / `TOKEN_COST` / 实例上限 / FPS 动态降载 | 不变（survivor-loop §4） |
| 刷怪间隔 45→25 s 按等级插值、任务中停摆 | 不变 |
| `_pick_enemy_type` 加权选型、"杂鱼一律 ≥2 建制、精英孤狼单机" | 不变（孤狼也走边缘入场，单机 TRANSIT） |
| Hunter 制度（最少 2 + level/3，每 5 s 指派） | 不变，仅加资格过滤（§3.4） |
| Adds 族群（Tu-160/AH-64/CH-47）固定航线穿场 | 不变（它们本来就是"飞过战场"的观感，已带 `skip_far_cleanup`） |
| 战区任务敌人（zone_air / ground / naval）、BOSS 事件 | 不变（战区目标由 zone_mission 独立管理，不属于本 spec 范围） |
| 玩家可见文本 | 无新增（无 i18n 工作） |

## 3. 行为与公式（How）

### 3.1 增援生命周期状态机

| 阶段 | 进入条件 | 行为 | 退出 |
|---|---|---|---|
| **TRANSIT** | 刷怪 tick 选型完成，中队在边缘生成 | 长机 PATROL 状态沿 `[入场点 → 中途点 → 锚点]` 航线飞，僚机 SQUAD_FOLLOW；雷达照常扫描（路过玩家附近会自然接敌） | 长机距锚点 < `ANCHOR_ARRIVE_DIST_PX` |
| **ONSTATION** | 到站 | 绕锚点 4 航点环盘旋（半径 `PATROL_RING_RADIUS_PX`，起始航点按当前方位角选最顺的，与 zone_mission 空战中队同法）；可被 hunter 点名、可被雷达接敌 | 被指派/接敌 → ENGAGE（既有 AI 路由）；交战结束 disengage 回 ONSTATION（下个 8 s tick 重发锚点环）；或满足退场条件 → EGRESS |
| **ENGAGE** | 既有 AI 交战路由 | 不属于本 spec，完全复用 | — |
| **EGRESS** | §3.5 条件全满足 | 航线 = 最近边界点 + 向外 `EGRESS_FREE_OUTSET_PX`，全速离场；**途中被伤害或获得目标 → 立即取消退场回 ONSTATION（可被玩家追杀，被打就应战，不做无敌逃兵）** | 全员出界 + 800 px → 静默释放（置 `xp_granted` 防击杀误判），token 由既有场景重算自动回收 |

到站判定与锚点环重发都骑**既有 8 s 航点 tick**；退场资格判定骑**既有 4 s 清理 tick**。无新增每帧逻辑。

### 3.2 边缘入场点选取

```
在世界矩形周长上均匀取 INGRESS_EDGE_CANDIDATES(16) 个候选点
过滤：
  1. 距玩家 ≥ INGRESS_MIN_PLAYER_DIST_PX(5000)
  2. 不在当前镜头可视范围内（is_world_pos_visible == false）
存活候选里 → 选距"本中队目标锚点"最近的一个（+少量抖动，入场走廊自然朝集结方向）
全部候选都可见（理论上只有镜头能看全图时发生）→ 取距镜头中心最远的候选
生成位置 = 候选点沿边法线向外推 INGRESS_SPAWN_OUTSET_PX(400)
中队朝向 = 指向锚点；僚机按阵型偏移绕长机展开（既有 _spawn_squad 逻辑）
```

镜头可视性从"软约束、失败就放弃"升格为**结构保证**：生成点永远在边界外，
可视性过滤只决定"从哪条边进"，最坏情况也是"从镜头最远的边进"，绝无当面刷新。

### 3.3 巡逻锚点选取（"地图中间巡逻"）

```
候选 = 原点为中心、半径 ANCHOR_DISC_RADIUS_FRAC × WORLD_HALF_PX 的圆盘内随机极坐标点
约束（最多 roll 12 次，全失败取末次候选软接受）：
  1. 距任何 AVAILABLE/SELECTED 战区圆边 ≥ ANCHOR_ZONE_CLEARANCE_PX(800)
  2. 距现存活跃中队锚点 ≥ ANCHOR_MIN_SEPARATION_PX(2500)
锚点记在中队每个成员的 meta 上（长机阵亡后继任长机继承，环不散）
```

锚点**静态**（v1 不做"锚点向玩家方向漂移"；如 playtest 发现中央巡逻感太"死"，
把漂移列为调参项再开）。

### 3.4 闲置航点 tick 与 hunter 的适配

- `_update_enemy_waypoints`（8 s tick）：对 `category=="reinforcement"` 的单位**不再**
  发"绕玩家 800~1500 px"的环，改发/维护锚点环（含 TRANSIT→ONSTATION 的到站翻转）。
  无类别单位（F5 调试刷怪等）保留旧行为。
- `_update_hunters`（5 s tick）闲置池资格过滤：
  `非 reinforcement 类别` **或** `阶段 == ONSTATION` **或** `距玩家 ≤ 4000 px`（TRANSIT
  路过玩家身边可被就近点名，但不会把横穿半张图的运输队硬拽过来）；EGRESS 不入池。
- 边界纪律 `_update_boundary_discipline`：`reinforcement` 在 TRANSIT / EGRESS 阶段**豁免**
  （跨线飞行是设计内行为，不得被 hard clamp / 强制转向打断）；ONSTATION / ENGAGE 阶段
  照常受纪律约束（锚点盘在地图中央，正常打不到边）。

### 3.5 退场（token 轮换的"物理化"替代）

旧机制"距玩家 >7000 px 直接删除"对增援停用，替代条件（4 s tick 检查，全部满足才触发）：

1. token 已占满（`token_used ≥ budget`，刷怪被饿着）——没饿着就不轮换，存量留着当前线
2. 该中队处于 ONSTATION 且连续无交战 ≥ `EGRESS_STALE_SEC(45)`
3. 全员不在镜头内 且 距玩家 > 7000 px
4. 当前退场中的中队数 < `EGRESS_MAX_CONCURRENT(1)`

满足 → 转 EGRESS 飞出去。效果等价旧远距清理（回收 token 让位给新增援），但整个过程
可观察、可拦截、绝不瞬消。

### 3.6 开局驻防 & 与"机头沿途"原则的边界

- **开局驻防**：t≈0 用正常选型/预算生成 `OPENING_GARRISON_SQUADS(2)` 个中队，直接置
  ONSTATION 在锚点上（免 TRANSIT）。合法性：玩家出生贴南边，锚点盘距出生点 ≥6000 px，
  开局镜头（START_ZOOM 0.35，可视对角半径 ≈3150 px）看不到；开局前无任何观察历史，
  不构成 pop-in。作用：抹掉"第一波增援要飞 60~90 s，前两分钟地图全空"的冷场。
- **机头沿途原则的适用边界**（[[feedback_event_spawn_ahead]]）：奖励任务/随机事件/Adds
  波次照旧刷在玩家 heading 前方扇形——那是"给玩家送目标"，要顺路；本 spec 管的增援是
  "给战场供压力"，走边缘集结，两者语义不同、并存不冲突。

### 3.7 实现期修订（2026-07-05，落地时发现/收紧的点）

1. **第 4 个适配点：离屏远距冻结豁免**（实施期发现，spec 起草时未知）——survivor_mode 的
   LOD 冻结把"离屏 + 距玩家 >750 px"的敌机**完全停物理**（这也是旧机制"刷出来的敌机原地
   杵着等你看见"的另一半根因）。豁免策略：TRANSIT/EGRESS 全豁免（位移任务，同 adds 理由）；
   ONSTATION 仅 PATROL 态可冻（省性能），被 hunter 点名/进屏后下一帧自动解冻恢复绕环。
2. **锚点避区收紧**：从"仅避 AVAILABLE/SELECTED 战区"改为**避开全部战区圆**——防止锚点
   在战区随后开放时恰好坐在圈里（战区开放是运行时随机的）。
3. **开局驻防选型降级**：roll 到单机精英/Sentinel 时降级为当级杂鱼小队（UAV / F-86），
   精英登场留给正常旅途节奏。
4. **TRANSIT 航线简化**：单点 `[锚点]`（PATROL 对单航点即直线飞去 + 到点自然盘旋），
   等效取代原设计的三点式 `[入场点→中途点→锚点]`。
5. 常量拆分：`PATROL_RING_RADIUS_PX 1400±400` 落地为 `_BASE_PX 1400` + `_JITTER_PX 400`。

## 4. 结构与组成（Structure）

- **不新增节点/子控制器**。全部逻辑住在 SurvivorSpawner 既有 tick 里。
- 单位标记（meta）：
  - `category = "reinforcement"`（与既有 `adds` / `boss` / `zone_air` 同一套查询语义）
  - `reinf_phase ∈ {transit, onstation, egress}`（ENGAGE 由 AI 状态本身表达，不重复记）
  - `reinf_anchor: Vector2`（全员冗余存，长机继任时锚点不丢）
- 中队仍走 `SquadFactory.create` + 随机阵型 + 长机/僚机注册的既有管线，生成入口只换
  "位置与朝向的来源"。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **镜头挪走再挪回**（间隔 ≥2 个刷怪周期）：原空域内不多出任何"无来路"敌机；
      期间新增的增援全部位于边缘入场航线上或中央锚点区
- [ ] **ZOOM_MIN 拉满悬停内陆任意空域** ≥2 个刷怪周期：无一架敌机在画面内 materialize
- [ ] 增援以完整中队建制（2~4 机阵型）跨越边界线飞入，Tab 战术图可观察到"边缘 → 中央"的移动
- [ ] 中央空域驻留 ≥1 个巡逻中队时，Tab 图可见其绕锚点盘旋（非跟随玩家漂移）
- [ ] 压力守恒：Lv≥3 时击杀当前追击者后 ≤60 s 内有新 hunter 接敌（hunter 制度未被削弱）
- [ ] 退场中队全程可见可追，被攻击立即回头应战；释放时刻全员在镜头外且在边界外
- [ ] 战区任务敌人 / Adds / BOSS 行为与本改动前完全一致（类别过滤未误伤）
- [ ] 性能：无新增每帧全场扫描（全部骑既有 5 s/8 s/4 s tick）；Sentinel + Lv5+ 压测 FPS 掉幅 < 15
- [ ] survivor-loop spec §4.2 刷怪位置段落已加 superseded 指针 → 本 spec
- [ ] i18n：无新增玩家可见文本（无需三语）

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 边缘生成
- [x] 新增边缘候选点选取函数（§3.2），替换 `_pick_safe_spawn_angle` 在旅途刷怪三个入口
      （`_spawn_single` / `_spawn_squad` / `_spawn_commander_squad`）中的调用
- [x] 生成时打 `category="reinforcement"` + `reinf_phase="transit"` + `reinf_anchor` meta
- [x] EventLogger 加 `INGRESS Spawn/Arrive/EgressStart/EgressAbort/EgressFree` 事件（F9 可回放验证）

### 阶段 2 — 生命周期与巡逻锚点
- [x] 锚点选取（§3.3）+ 到站翻转 + 锚点环发放（改 `_update_enemy_waypoints`，8 s tick）
- [x] `_update_hunters` 资格过滤（§3.4）
- [x] `_update_boundary_discipline` / `_update_far_cleanup` 类别豁免
- [x] survivor_mode 离屏冻结豁免（§3.7-1，实施期新增适配点）

### 阶段 3 — 退场与开局驻防
- [x] EGRESS 条件判定（骑独立 4 s timer）+ 出界释放 + 被打回头守卫
- [x] 开局驻防 2 中队直接 ONSTATION 预置（`_spawn_squad(…, garrison=true)`）

### 阶段 4 — 收尾
- [x] 旧常量语义标注：`SPAWN_DISTANCE` 仍被 ace_squad/adds/沙盒引用故**保留**并注明旅途已弃用；
      `TRAVEL_SPAWN_FAN_HALF` 注明留作事件"机头沿途"备用（未删，避免误伤事件路径）
- [x] survivor-loop §4.2 加 superseded 指针；同步 script-index / code-index
- [x] 无头回归：`tests/test_map_expansion.gd` 入场段（周长参数点/外法线/退场点/锚点避区 4/4）
- [ ] §5 验收 playtest 项（镜头挪回/ZOOM_MIN 悬停/压力守恒/退场观察）+ Sentinel+Lv5 性能压测 → status: done

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 刷怪总管 / 三个生成入口 / INGRESS 辅助函数组（`_ingress_spawn_point` / `_pick_reinf_anchor` / `_tick_reinforcement_waypoints` / `_update_reinf_egress` / `_spawn_opening_garrison` 等） | `scripts/survivor/survivor_spawner.gd` |
| 常量（INGRESS_* / ANCHOR_* / PATROL_RING_* / EGRESS_* / OPENING_GARRISON_SQUADS） | `scripts/survivor/survivor_data.gd` |
| 离屏冻结豁免（reinforcement 分支） | `scripts/survivor/survivor_mode.gd`（LOD 冻结块） |
| 边界 API（distance_to_edge / clamp_inside / world_half_px） | `scripts/survivor/map_boundary.gd` |
| PATROL 航点消费 | `scripts/ai_controller.gd` |
| 无头回归（入场纯函数段） | `scripts/tests/test_map_expansion.gd` |
| 被取代的旧设计记录 | `docs/specs/systems/survivor-loop.md` §4.2 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-05 | 1 | 初稿：边缘中队入场 + 中央锚点巡逻 + EGRESS 物理化轮换 + 开局驻防；实证两条 pop-in 根因（镜头挪回 / ZOOM_MIN 0.2 下软约束必然失败）。同日 **定稿 approved**（锚点盘样例值按拍板的 60 km 图更新） |
| 2026-07-05 | 2 | **阶段 1~4 代码落地**（60km 图上，与 map-expansion 同批）：§3.7 实现期修订 ×5（离屏冻结第 4 适配点 = pop-in 另一半根因"刷出即冻结原地杵着"/锚点避全区/驻防降级/单点航线/常量拆分）；无头回归入场段 4/4 绿；status → in-progress，差 playtest/性能验收 |
