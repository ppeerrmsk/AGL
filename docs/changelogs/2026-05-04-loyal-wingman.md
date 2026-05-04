# 2026-05-04 — 忠诚僚机无人机（Loyal Wingman）

## 同时立的设计原则：60 FPS 硬底线（[DESIGN_PHILOSOPHY §11](../DESIGN_PHILOSOPHY.md)）

> 任何时候帧数都不能低于 60 FPS。这是不接受的红线。

为本次 loyal wingman 实施服务，但作用范围远不止：从此以后所有新内容都要守这条线。
- DESIGN_PHILOSOPHY.md 加第 11 条原则 + Litmus 第 11 项 + 反模式条目
- performance-guidelines.md 顶部 + R7 措辞改成"60 不可掉"

## 新机制：忠诚僚机无人机

灵感原型：Skyborg / MQ-28 Ghost Bat / Kratos XQ-58 等"忠诚僚机"概念。AGL 抽象成一个规避模式触发释放的伴飞 drone。

### 玩家交互
- **激活**：进入规避模式（KEY_E）
- **触发**：CD 完毕（默认 8s）即从机尾释放 1 架 drone
- **同屏 cap**：2 架（与漂浮雷的 21 cap 同设计哲学：给"减 CD 升级"留天花板）
- **HUD**：WMN 段显示 `alive/max  状态`（绿=READY / 灰绿=CD / 蓝灰=MAX）

### Drone 行为
- 规避中持续绕玩家飞行（轨道间距 ~ ORBIT_INNERMOST，Sentinel UAV 同套机制）
- **玩家有 combat_target 时** → 跳出轨道主动追击该目标，类机炮"激光"点射
  - 单发 20 dmg / 60 RPM / 弹速 1800 m/s（视觉接近瞬时命中）
  - 追击中如有导弹瞄向玩家，立刻折返自爆（保命优先于火力）
- **玩家无 combat_target 时** → 留在轨道护驾，导弹来袭时主动飞入弹道自爆
  - 复用 shield_leader 的 kamikaze 逻辑（`MISSILE_INTERCEPT_DIST = 100px`）
  - 自爆 = drone 死 + 导弹消失 + AOE 视觉指示
- **追丢 / 目标死亡** → 回到玩家身边继续轨道
- **寿命 25s**（与现实 loyal wingman 油料相符），SceneTreeTimer 一次性 queue_free
- **被击毁** → 数组清理，下个 CD 可补充

## 关键设计：与漂浮雷互斥的同槽武器

`AircraftParams` 加 `loyal_wingman: LoyalWingmanParams` 字段，与 `torpedo` 字段**互斥**（设计约定只填一个）。同时填的话两个 update 都会跑（无 crash，但浪费资源）。靠 `.tres` 编辑约定保证互斥，未来可加 PlayableAircraft 层校验。

A-10 默认配置 `playable_a10_base.tres` 仍挂 torpedo（漂浮雷）；新增 `playable_a10_drone.tres` 替换为 loyal_wingman，作为实验装载（未来可通过 boss_debug_select 或玩家选择切换）。

## 实现要点

### 不写新 kamikaze 逻辑（复用 shield_leader）
关键发现：[ai_controller.gd:751-781](../../scripts/ai_controller.gd#L751) `shield_leader` 路径**已经包含**导弹自爆拦截（`MISSILE_INTERCEPT_DIST = 100px`）。drone 设 `shield_leader = true` 即免费获得拦截能力，无需新加 `kamikaze_intercept` flag。

### 唯一新 AI flag：chase_leader_target
现有 `shield_leader` 让 UAV 留在轨道防御，**不**主动追击 leader 锁定的目标。新加 `chase_leader_target: bool` 在 `_process_simple` 顶部抢占 `_current_target = squad.leader.combat_target`，让 drone 跳出轨道追击；shield_leader 的导弹自爆扫描仍优先于 chase（保命第一）。

默认 false，**Sentinel UAV / Aegis UAV 现有行为完全不变**。

### Drone 是真正的 Aircraft 实例（不是子弹/导弹）
- 实例化 `aircraft.tscn` → `params = drone_aircraft_params.duplicate(true)` → 挂 AIController（simple_ai + orbit + shield + chase）
- 复用 `survivor_spawner.gd:_spawn_commander_squad` 模板
- 创建透明 `_drone_squad: Squad`（leader = 玩家），drone 通过 `squad.leader` 反向引用玩家；不污染玩家自身的 `wingman_count > 0` 编队

### 性能优化（按 60 FPS 硬底线核对）

| 优化点 | 实现 |
|---|---|
| 单源 cap = 2 | spawn 入口 `_alive_drones.size() >= max_simultaneous` 早退 |
| simple_ai + ai_tick_divisor=3 | AI 20Hz，跳过 BFM/TacticalPlanner/PilotPersonality 重路径 |
| TrailRibbon max_points 360→60 | 避免重蹈"40 万 draw_polygon/秒" 覆辙（R6 历史教训）|
| 不走 SQUAD_FOLLOW BFM | drone 用 orbit_squad_leader 路径，不算编队三段式 |
| shield_leader 复用帧级缓存 | 来袭导弹扫描走现有 `_frame_enemy_missiles_by_team` |
| 不挂额外子节点 | 无 CommanderOverlay / 雷达圈 / 专属音效播放器 |
| 静态 HUD 不 queue_redraw | WMN 走主 HUD 文字段，无 overlay |
| lifetime 25s → SceneTreeTimer | 一次性触发 queue_free，无每帧 tick 成本 |
| kamikaze 复用 _explode_rocket | drone 死亡走标准 `take_damage` 路径，无新爆炸系统 |
| 沙盒 / 非生存模式 0 成本 | `params.loyal_wingman = null` → update 顶部一次 null 检查 |

### 单 drone 每帧成本（worst case）

| 子系统 | 频率 | 成本 |
|---|---|---|
| Aircraft._physics_process（LOD 0）| 60 Hz | ≈一架战斗机的全部物理 |
| AIController._physics_process（simple_ai）| 20 Hz | scan + orbit + shield 扫描 |
| auto_gun_scan | 3.3 Hz | cone scan |
| update_gun（开火）| 60 Hz 检测 / 1 Hz 出弹 | bullet spawn |
| TrailRibbon 重绘 | 60 Hz | 60 顶点（不是 360）|

**结论**：2 架 drone 总开销 ≈ +1 架普通战斗机。远低于 5 架 Sentinel 招募 UAV 的现有压测基准。

## 文件改动

| 文件 | 改动 |
|---|---|
| [DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md) | 加第 11 条原则（60 FPS 硬底线）+ Litmus 第 11 项 + 反模式条目 |
| [performance-guidelines.md](../reference/performance-guidelines.md) | 顶部 + R7 措辞改为"60 FPS 不可掉" |
| [scripts/loyal_wingman_params.gd](../../scripts/loyal_wingman_params.gd)（新建）| `LoyalWingmanParams extends Resource` |
| [scripts/aircraft_params.gd](../../scripts/aircraft_params.gd) | 加 `loyal_wingman` 字段；`has_equipment_of_kind` 加 "loyal_wingman" 分支 |
| [scripts/aircraft.gd](../../scripts/aircraft.gd) | 加 `_loyal_wingman_cooldown` / `_drone_squad` / `_alive_drones`；3 个 LOD 路径调 `update_loyal_wingman` |
| [scripts/ai_controller.gd](../../scripts/ai_controller.gd) | 加 `chase_leader_target` flag + 在 `_process_simple` 顶部抢占 `_current_target` |
| [scripts/aircraft/aircraft_weapons.gd](../../scripts/aircraft/aircraft_weapons.gd) | 末尾加 `update_loyal_wingman` + `_spawn_loyal_wingman_drone` |
| [scripts/survivor/survivor_hud.gd](../../scripts/survivor/survivor_hud.gd) | TORP 段后加 WMN 段 |
| [resources/loyal_wingman_laser.tres](../../resources/loyal_wingman_laser.tres)（新建）| GunParams：单发 20 / 60 RPM / 弹速 1800 m/s |
| [resources/loyal_wingman_drone.tres](../../resources/loyal_wingman_drone.tres)（新建）| AircraftParams：HP 40 / max_g 28 / 1800 km/h |
| [resources/a10_loyal_wingman.tres](../../resources/a10_loyal_wingman.tres)（新建）| LoyalWingmanParams：CD 8s / 寿命 25s / cap 2 |
| [resources/playable_a10_drone.tres](../../resources/playable_a10_drone.tres)（新建）| A-10 实验装载（torpedo 替换为 loyal_wingman）|

## 数值快照（A-10 loyal wingman）

| 维度 | 值 | 备注 |
|---|---|---|
| 释放 CD | 8s | 规避模式下倒数 |
| 寿命 | 25s | SceneTreeTimer 一次性 queue_free |
| 同屏上限 | 2 架 | 用户指定 |
| Drone max_speed | 1800 km/h | 接近超音速 |
| Drone max_g | 28 G | 接近导弹 |
| Drone HP | 40 | 一发导弹直接秒 |
| Drone 激光单发伤害 | 20 | 用户指定 |
| Drone 激光射速 | 60 RPM | 慢节奏点射 |
| Drone 激光弹速 | 1800 m/s | 视觉接近瞬时 |
| 自爆触发距离 | 100px (50m) | 复用 shield_leader 现有 const |
| AOE 半径 / 伤害 | 60m / 30 | 复用 shield_leader VFX |

## 不变的部分（关键不变量）

- **Sentinel UAV / Aegis UAV 行为完全不变** — chase_leader_target 默认 false
- **shield_leader 自爆逻辑不动** — 沿用 ai_controller.gd:751-781
- **drone 不污染玩家 squad** — `_drone_squad` 与 `player.squad` 是不同对象
- **drone 不进 LoadoutLedger / 升级系统** — drone.params 是 duplicate 副本，运行时改不污染原 .tres；玩家技能（gun_damage / radar_range 等）不影响 drone
- **沙盒模式 0 成本** — params.loyal_wingman = null → update 顶部一次 null 检查

## 验证

1. F5 → 选 A-10 (用 playable_a10_drone.tres 装载) → 出击
2. HUD 显示 `WMN  0/2  (Evade)` 灰字
3. 进规避（KEY_E）→ 8s 后第一架 drone 从机尾甩出，绕玩家飞
4. 玩家右键锁敌 → drone 突进 + 类机炮点射 20 dmg/发
5. 击杀目标后 drone 回轨道
6. 敌方导弹瞄向玩家 → drone 飞入弹道、100px 内自爆 + 导弹消失
7. 再 8s 第 2 架 drone 释放，cap 到 2
8. cap 满时 spawn 阻断，HUD 显示 `WMN 2/2 MAX`
9. drone 25s 寿命到期 → 静默消失（EventLogger 记 "drone lifetime expired"）
10. 玩家死亡 → drones 失去 squad.leader，shield/orbit 自动关闭，退化为独立 simple_ai
11. **回归测试**：Sentinel + Aegis UAV 现有行为不变（chase_leader_target 未启用）
12. **性能基准（R7）**：lv 5+ + Sentinel 小队 + 2 drone 释放 → **FPS 必须保持 60**

## 同日反馈微调（2026-05-04 第二轮）

按用户实测反馈调整：

### 1. 去掉预测线 / 数据标签 / 锁定指示
drone 是无人机不需要那些 HUD 元素。新增 `Aircraft.is_drone: bool = false` 标记，gate 以下 draw 调用：
- `draw_target_line`（含 `draw_predicted_path` 的弧线 + 航点标记）
- `draw_lock_indicator` / `draw_target_bracket`
- `draw_data_label` / `draw_data_label_minimal`（飞机旁的文字标签）

保留：`draw_aircraft_icon` / `draw_radar_cone` / `draw_gun_cone` / `draw_muzzle_flash` / `draw_tactic_popup`（关键事件 popup 如"自爆"）。

### 2. 修 twitching（左右反复抽搐）
原因：drone 之前 `max_g = 28`（接近导弹机动）+ orbit 代码让 drone 直接追踪轨道点本身（不是切线方向）→ drone 高速冲到点上后过冲，AI 下一 tick 重新对准 → 反复矫正 → 视觉左右抽搐。

调低机动参数：
- `max_g` 28 → **10**（中等 G，不影响 chase 模式仍然快）
- `max_g_structural` 35 → **15**
- `roll_rate` 6.0 → **4.5**
- `cruise_speed` 1300 → **900**（与玩家 cruise 一致，orbit 不需要更快）
- `acceleration` 80 → **55**

`max_speed = 1800` 保留（chase 模式仍能高速突进）。

### 3. 出生朝向与玩家一致
- 之前 `initial_heading_deg = rad_to_deg(ac.heading + PI)` → drone 出生朝后甩，需要先掉头
- 现在 `initial_heading_deg = rad_to_deg(ac.heading)` → 出生**与玩家同向**，AI 顺势进入轨道，无掉头过渡

位置仍然在玩家机尾后 30px（视觉上"被释放"），但朝向同向。

### 4. 精简到 2D
- `is_drone = true` flag 跳过所有需要 3D 高度信息的 HUD 元素
- 飞机内部 `altitude` 字段仍维持（用于伤害计算 / 武器射程判定），但不**显示**给玩家
- callsign 仍自动分配（CallsignDB.allocate 无法绕过），但不显示在屏幕上

### 改动文件（第二轮）
- `scripts/aircraft.gd` — 加 `is_drone: bool` 字段；`_draw` 末段加 4 个 `if not is_drone` 守卫
- `scripts/aircraft/aircraft_weapons.gd::_spawn_loyal_wingman_drone` — 改 spawn 朝向；设 `drone.is_drone = true`
- `resources/loyal_wingman_drone.tres` — 调机动参数（max_g/cruise/roll/accel）

### 第三轮调整（2026-05-04 第三反馈）

**3a. 加回极简标签**
之前完全去掉标签，玩家反馈"标签栏没了"。新加 `AircraftRenderer.draw_data_label_drone(ac)`：
- 一行小字 `DRONE  482 kt`（kind 名 + 速度）
- 半透明绿底，不显示 callsign / altitude / HDG / G / RNG
- aircraft.gd `_draw` 中 is_drone 分支调用此函数

**3b. 提高机动跟得上玩家**
之前 max_g=10 太低，玩家剧烈转向时 drone 跟不上。折中提到 18：
- `max_g` 10 → **18**（player A-10 是 9.5；drone ≈ 1.9× 玩家，能跟急转）
- `max_g_structural` 15 → **25**
- `roll_rate` 4.5 → **5.5**
- `cruise_speed` 900 → **1100**（orbit 默认速度匹配高速玩家）
- `acceleration` 55 → **75**

仍然不到导弹级（35G），保留"高速但稳"的飞行感。

## 第四轮调整（2026-05-04 第四反馈）

**反馈**：drone 反应迟钝，玩家转向后跟不上。

**根本原因**：drone 之前用 `simple_ai + orbit_squad_leader + shield_leader`，AI 跑在 simple_ai 路径（20Hz），轨道点是直追式（每 tick 算一次几何点），玩家剧烈转向时 drone 总是滞后一拍 + 矫正过冲。

**修复**：彻底切换到与玩家僚机一致的 **formation_mode + SQUAD_FOLLOW** 架构。

### 实现路径

| 之前 | 现在 |
|---|---|
| `simple_ai = true` | `simple_ai = false`（默认）|
| `orbit_squad_leader = true` | 不用 |
| `shield_leader = true`（含 kamikaze）| 不用，由新 hook 替代 |
| `chase_leader_target = true` | 不用，SQUAD_FOLLOW 已自动跟随 leader 交战 |
| `Squad.formation = FINGER_FOUR` | `Squad.formation = TRAIL`（drone 跟在玩家正后方）|
| AI 状态：默认 PATROL | `_state = AIController.AIState.SQUAD_FOLLOW` |
| 物理路径：LOD 0 全模拟 | 预置 `lod_level=1` + `formation_mode=true` → 走 LOD 1 三段式编队跟随 |

**SQUAD_FOLLOW 的好处**（[scripts/aircraft/aircraft_formation.gd](../../scripts/aircraft/aircraft_formation.gd)）：
- 9 阶段流水线：context / target heading / heading / bank / speed / debug / altitude / position / visuals
- 三段式跟随：远距激进追、中距混合、近距漂移修正
- 玩家转向时 drone 立刻 lead/lag 预测跟上，不会落 1-2 秒

### kamikaze 拦截 Hook（保留 drone 标志性能力）

不用 `shield_leader` 后，原本的"主动撞导弹"行为丢失。新加 `AIController.kamikaze_intercept: bool` flag + `_try_kamikaze_intercept(delta)` 方法：
- 在 `_physics_process` 顶部（state dispatch 之前）调用
- 扫 `missile_manager` 找瞄向 squad.leader 的导弹
- 选距 drone 最近的一枚
- 距离 ≤ `KAMIKAZE_INTERCEPT_RANGE_PX (1200m)` → break formation 全速冲过去
- 距离 ≤ `KAMIKAZE_DETONATE_DIST_PX (60m)` → ExplosionVFX + 双双消失
- 不影响 Sentinel UAV（kamikaze_intercept 默认 false）

### 改动文件（第四轮）
- `scripts/ai_controller.gd` — 移除 `chase_leader_target` flag，加 `kamikaze_intercept` flag + `_try_kamikaze_intercept` 方法 + `_physics_process` 顶部 hook
- `scripts/aircraft/aircraft_weapons.gd::_spawn_loyal_wingman_drone` — 改为 SQUAD_FOLLOW + formation_mode + TRAIL formation 配置
- `resources/loyal_wingman_drone.tres` — 不变（max_g 18 / cruise 1100 等）

## 第五轮调整（存在时间改成离屏计时）

**反馈**：drone 不应该有固定 25s 寿命。在画面里应该一直存在直到被击坠 / 自爆；只有飞出画面外才慢慢消失。

**实现**：
- `LoyalWingmanParams.lifetime` → **`offscreen_despawn_seconds`**（语义彻底变）
  - 默认 8s（连续离屏 8s 才静默 queue_free）
  - 设 0 = 永不离屏消失（仅靠击坠/自爆）
- 移除 `SceneTreeTimer` 一次性触发 free 的旧机制
- 每个 drone 有 meta `_drone_offscreen_timer: float`（初始化为 0）
- `update_loyal_wingman` 每帧迭代 `_alive_drones`：
  - 在屏幕内（含 200px 外扩缓冲）→ 重置计时器为 0
  - 离屏 → 累加 delta；超过阈值 → queue_free + EventLogger
- 屏幕检测 `_is_drone_on_screen()` 复用 missile_manager 的 camera 视口判定

### 战术含义
- 玩家看着 drone 飞 → drone 永远不会"凭空消失"，可信赖度高
- drone 飞远脱屏（被打散队 / 被甩开 / 玩家高速远离）→ 8 秒后静默清理，避免"无主无人机"在地图边缘游荡
- 玩家可以靠规避模式持续维持 2 架 drone 编队 → 真正的"忠诚伴飞"体验

### 改动文件（第五轮）
- `scripts/loyal_wingman_params.gd` — `lifetime` → `offscreen_despawn_seconds`，注释改写
- `scripts/aircraft/aircraft_weapons.gd` — 移除 SceneTreeTimer，加 `_is_drone_on_screen` helper + `update_loyal_wingman` 离屏计时逻辑
- `resources/a10_loyal_wingman.tres` — 字段名同步

## 第六轮调整（drone 叛逃 bug 修复）

**反馈**：drone 跟着玩家飞一段，就掉头去别的方向。

**根本原因**：`AIController.squad_engage_mode` 默认值是 **`FREE`**，意思是僚机会自主扫描附近敌机（[squad_coordination.gd:116-147](../../scripts/ai/squad_coordination.gd#L116)），扫到一个就破阵 + 进入 ENGAGE 状态飞过去打。drone 上这个默认会让它看起来像"飞着飞着突然掉头"。

**修复**：spawner 中显式设置 `ai.squad_engage_mode = SquadEngageMode.FOLLOW_LEADER`：
- 跳过自主扫描分支
- drone 只在玩家锁定 combat_target 时跟着上（line 151-181 的"跟随长机交战"分支仍保留，与 squad_engage_mode 无关）
- 玩家无目标时 drone 严格保持编队 + 等待

### 改动文件（第六轮）
- `scripts/aircraft/aircraft_weapons.gd::_spawn_loyal_wingman_drone` — 加 `ai.squad_engage_mode = AIController.SquadEngageMode.FOLLOW_LEADER`

## AI / 编队系统说明（针对用户问"AI 怎么写的"）

**SQUAD_FOLLOW 状态**有两种 engage 模式：
1. **FREE**（默认）：僚机自主扫描 800m 内敌机，扫到就破阵去打。设计初衷是让僚机感觉"有自主感"，不是傻跟。
2. **FOLLOW_LEADER**：僚机只在长机锁敌时跟着上，平时严格保持编队槽位。

普通玩家僚机用 FREE（你按 KEY_6 可以切换），但 drone 我们想要"绝对忠诚跟随"，所以强制 FOLLOW_LEADER。

**为什么编队/小队系统经常出问题**：squad 状态机里有很多分支（formation_mode true/false / engage / cover / kamikaze / herbst / 反应延迟 / 归队混合等），任何一个分支没正确设置都会导致 drone 行为异常。建议每次发现问题先 F12 dump 当前 AI 状态（survivor_mode 已有快照功能），再回到代码定位。

## 第七轮调整（drone 外观参考真实 loyal wingman）

**反馈**：drone 比玩家飞机还大，看起来不像无人机。需要参考现实造型缩小。

**实现**：新增 silhouette = "drone" 类型，在 [aircraft_renderer.gd](../../scripts/aircraft_renderer.gd) 加 `draw_drone_icon` 函数，灵感来自现实 XQ-58 Valkyrie / MQ-28 Ghost Bat：
- **尺寸缩小**：`s = size × 0.55`（比战斗机小约 45%）
- **尖锐机头**：比战斗机更尖（无座舱泡——无人机标识）
- **极后掠三角翼**：翼尖向后伸 0.95s（vs 战斗机 1.1s 但更靠后）
- **V 形尾翼**：两片向后斜伸的尾翼（替代战斗机的水平稳定翼）
- **流线机身脊线**：accent 色淡线给"科技感"
- 绘制顺序：尾翼 → 主翼 → 机身（机身覆盖在最上）

**接入**：`_spawn_loyal_wingman_drone` 设 `drone.set_meta("silhouette", "drone")`，draw_aircraft_icon 的 silhouette dispatch 自动走新分支。

### 改动文件（第七轮）
- `scripts/aircraft_renderer.gd` — 新增 `draw_drone_icon`（~80 行）+ silhouette dispatch
- `scripts/aircraft/aircraft_weapons.gd::_spawn_loyal_wingman_drone` — 设 silhouette meta

## 第八轮调整（drone 不打 combat_target bug 修复 + 编队系统问题归档）

**反馈**：玩家锁定 Tu-160，drone 跟在阵型不动，不去攻击。

**根本原因**：玩家进规避模式（drone 释放的前提）→ `_propagate_evasion_to_squad` 把 evasion_mode 广播到所有 squad.leader=自己的飞机，包括 drone。然后 [ai_controller.gd:535-538](../../scripts/ai_controller.gd#L535) 有硬守卫"僚机收到长机 evasion → 强制 EVADE_MISSILE 状态 + return"。drone 因此永远卡在 EVADE，根本走不到 SQUAD_FOLLOW 的"跟随长机锁定目标"分支。

**修复**：`_propagate_evasion_to_squad` 跳过 `is_drone = true` 的飞机：
- drone 有自己的 kamikaze 拦截路径（在 _physics_process 顶部 hook），不需要走 EVADE_MISSILE 状态机
- drone 的"防御性能"由 kamikaze_intercept 实现，与 evasion 模式解耦

### 改动文件（第八轮）
- `scripts/aircraft.gd::_propagate_evasion_to_squad` — 加 `if ac.is_drone: continue` 守卫

## 编队系统重构 backlog（用户提议 — 待立项）

用户反馈："这个逻辑明显是各种地方互相矛盾的，导致了很多 bug。编队系统我觉得要重构一下。"

确实存在系统性问题。当前编队 / 小队相关有 ~10 个互相影响的字段 / flag：
- `Aircraft.formation_mode` / `_formation_leader` / `_formation_blend`
- `Aircraft.evasion_mode`（被 set_evasion_mode 广播到 squad.members）
- `AIController._state`（PATROL / ENGAGE / EVADE_MISSILE / SQUAD_FOLLOW 4 态）
- `AIController.squad_engage_mode`（FREE / FOLLOW_LEADER）
- `AIController.simple_ai`（有 / 无：完全不同的 _process 路径）
- `AIController.orbit_squad_leader` + `shield_leader`（simple_ai 专用）
- `AIController.kamikaze_intercept`（drone 专用 hook）
- `AIController._squad_attacking_leader_target` / `_squad_free_engaging` / `_cover_target`

每个 flag 都有"在某些组合下有效，在另一些组合下被旁路"的边角情况。新加单位类型时容易踩到：
- Sentinel 招募 UAV：simple_ai + orbit + shield
- 普通玩家僚机：full AI + SQUAD_FOLLOW
- 忠诚僚机 drone：full AI + SQUAD_FOLLOW + kamikaze hook
- BOSS 攻击手：bvr_only + 多个独立守卫

**重构思路（草稿）**：
1. 提炼"小队成员行为"为单一接口 `SquadMemberPolicy`：
   - `should_orbit_leader() -> bool`
   - `should_engage_target(target) -> bool`
   - `should_intercept_missile(missile) -> bool`
   - `should_follow_evasion(leader_evasion) -> bool`（drone 返回 false 即可解此 bug）
2. 每种单位类型实现一个 policy 子类：StandardWingmanPolicy / SentinelEscortPolicy / LoyalWingmanDronePolicy / BossSquadPolicy
3. AIController 持有 `policy: SquadMemberPolicy`，根据 policy 决定 state machine 路径
4. 移除散落的 flag（simple_ai / orbit_squad_leader / shield_leader / chase_leader_target / kamikaze_intercept），统一到 policy

**预估工作量**：3-5 天（涉及 ai_controller.gd / squad_coordination.gd / 6+ 个 spawner / 完整回归测试）。

**优先级**：建议作为下一个大版本的核心重构项目；当前先用打补丁方式修单点 bug。

## 后续可加（未实现）

- 升级技能（CD -25% / cap +1 / drone HP +40 / drone 激光伤害 ×1.5），exclusive_to=["a10"] 或 requires=["loyal_wingman"]
- drone silhouette 美化（专属"无人机"图标，区别于战斗机轮廓）
- 玩家死亡时强制 queue_free 所有 drones（避免无主无人机继续飞）
- drone 子弹的视觉特效（专属黄绿"激光弹"绘制路径）
- PlayableAircraft 层正式 loadout 互斥校验（torpedo / loyal_wingman 二选一）
