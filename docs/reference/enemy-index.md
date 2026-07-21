# Enemy Index — 生存模式敌人完整索引

> 本节内容原在 CLAUDE.md，2026-05-05 移出。

## AI 原型（Archetype）预设

参照经典空战文献的敌方行为分类，通过 `CombatParams` + `AIController` 参数组合实现：

| 原型 | 行为特征 | 预设文件 | 适用机型 |
|------|---------|----------|----------|
| **Gladiator（斗士）** | 积极近身狗斗，拉近距离，高转弯激进度，低自保 | `gladiator_combat.tres` | F-86, MiG-23, F-4（导弹卡车）, Su-27/Su-35（带眼镜蛇） |
| **Lancer（骑士/打带跑）** | 高速一次性突击，闭合率不足即脱离，不缠斗 | `lancer_combat.tres` | J-7（轻量）, F-104（纯速度截击）, F-100（中量编队）, MiG-31（顶级单机） |
| **Schemer（策士）** | 特殊机制（光环 buff/远距狙击/隐身），玩家靠近即脱离 | — | Sentinel 指挥 UAV |
| **Adds（杂兵）** | 无反击能力，直线飞过战场，纯经验奖励；族群波次（非编队） | — | Tu-160（战略轰炸机）。UAV/UCAV 虽然 Token 很便宜但仍会反击 + 受刷怪系统管理，设计上**不归类为 Adds** |
| **主力威胁** | 全能 BFM 战术 + 导弹缠斗 | `default_combat.tres` | MiG-29 |

⚠ 这些原型名称是**纯内部设计词汇**，不要写进玩家可见 UI / debug 面板 / `display_name`。仅可出现在源码注释、`.tres` 注释、设计文档里。

## Enemy Index

所有生存模式敌人的完整索引。**新增敌人必须在此表新增一行**，以便下次直接走索引而不通读代码。

`EnemyType` enum 在 `survivor_mode.gd:843`。每个敌人由 7 个位置共同定义：

| EnemyType(int) | 显示名 | Archetype | `.tres` 参数 | Token | 实例上限 | 解锁等级 | 生成形式 | `_create_enemy` match 行 | AI 配置行 |
|---|---|---|---|---|---|---|---|---|---|
| `UAV(0)` | UAV | Adds | `enemy_uav.tres` | 1 | ∞ | 1 | 编队(后期) | `:1059` | `:1240`(default) |
| `UCAV(1)` | UCAV | Adds | `enemy_uav_missile.tres` | 2 | ∞ | 1 | 编队(后期) | `:1046` | `:1240`(default) |
| `MIG(2)` | MiG-29 | 主力威胁 | `enemy_fighter.tres` | 4 | ∞ | 7 | 编队 | `:1042` | `:1158` |
| `INTERCEPTOR(3)` | J-7 | Lancer 入门 | `enemy_interceptor.tres` | 5 | ∞ | 5 | 单机→后期编队 | `:1044` | `:1167` |
| `UAV_COMMANDER(4)` | Sentinel | Schemer | `enemy_uav_commander.tres` | 6 | **1** | 4 | 自带 2-3 僚机 | `:1048` | `:1233` |
| `F86(5)` | F-86 | Gladiator 入门 | `enemy_f86.tres` + `f86_gun.tres` + `rocket_ffar.tres` | 3 | ∞ | 2 | 编队 | `:1050` | `:1183` |
| `MIG31(6)` | MiG-31 | Lancer 顶级 | `enemy_mig31.tres` | 8 | **2** | 9 | 单机 | `:1052` | `:1195` |
| `MIG23(7)` | MiG-23 | Gladiator 综合 | `enemy_mig23.tres` | 4 | ∞ | 4 | 编队 | `:1054` | `:1208` |
| `F100(8)` | F-100 | Lancer 编队 | `enemy_f100.tres` | 5 | **3** | 6 | 编队 | `:1056` | `:1220` |
| `SU27(9)` | Su-27 | Gladiator+眼镜蛇 | `enemy_su27.tres` | 7 | **2** | 8 | 单机 | `:1263` | `:1443` |
| `A7(10)` | A-7 | Lancer 亚音速攻击 | `enemy_a7.tres` + `a7_gun.tres` + `a7_rocket.tres` | 3 | ∞ | 3 | 编队 | `:1294` | `:1525` |
| `Q5(11)` | Q-5 | Lancer 超音速攻击 | `enemy_q5.tres` + `q5_gun.tres` + `q5_rocket.tres` | 4 | ∞ | 5 | 编队 | `:1296` | `:1538` |
| `TU160(12)` | Tu-160 "白天鹅" | **Adds 杂兵** | `enemy_tu160.tres`（无武器） | **0** | ∞ | 事件触发 | **族群 Flock**（横列 4 架） | `_create_enemy` Tu160 case | AI 简化(simple_ai) |
| `AH64(13)` | AH-64 Apache | **Adds 直升机（对地）** | `enemy_ah64.tres` + `ah64_gun.tres`（M230 30mm）+ `ah64_rocket.tres`（Hydra 70）+ 1 枚热诱弹 | **0** | ∞ | 事件触发 | **菱形 Flock** 4 架（队长前 + 左右两翼 + 殿后） | `_create_enemy` AH64 case | simple_ai + `ground_combat_only=true` + `attack_air_targets=false` |
| `CH47(14)` | CH-47 Chinook | **Adds 运输直升机** | `enemy_ch47.tres`（1 枚热诱弹，50% 失误概率） | **0** | ∞ | 事件触发 | **纵阵 Flock** 3 架 | `_create_enemy` CH47 case | AI 简化(simple_ai, 与 Tu-160 同) |
| `F47(15)` | F-47 | **BOSS 王牌狙击小队** | `enemy_f47.tres` + `default_gun.tres` + `f47_missile.tres`（AIM-260）+ `f47_flare.tres`（**实际 max_flares=2 / burst=3 → 整场只够投一次**，见下方细节）+ `ace_combat.tres` | **10** | **4** | 事件触发 | **菱形编队** 4 架（队长+两翼+殿后）| `_create_enemy` F47 case + `_spawn_f47_squad` | BVR 狙击模式(bvr_only) + 协同齐射(salvo_leader) + 距离切换由 `aircraft_weapons.update_weapon_mode` GUN/MISSILE 枚举管 |
| `AF03(17)` | AF-03 | **Schemer 电磁炮狙击** | `enemy_af03.tres` + `enemy_railgun.tres`（充能 2.0s + 锁定 0.5s, AT_FIRE_TIME 预测命中, dmg 60, range 14000m, base+cloud+lowalt miss 加成）| **7** | **1** | **8**（随机刷新 + 事件触发）| 单机 | `_create_enemy` AF03 case + `_pick_enemy_type` 优先级 ≈ Su-27 | bvr_only @ 5-8km + prefer_nose_aligned_weapon (SNIPER_HOLD) + Lancer 节奏（10s/7s）+ 等级缩放 |
| `UAV_LASER(18)` | Aegis UAV | **拦截支援 Schemer** | `enemy_uav_laser.tres` + `enemy_laser_interceptor.tres`（target_filter 仅 missiles, dps_max=80, range 1200m）| **2** | 2 | 跟随 Sentinel 自动出现 | Sentinel 编队的一部分 | `_create_enemy` UAV_LASER case + `_spawn_commander_squad` 末尾追加 2 架 | simple_ai + `enable_combat=false`（laser 自己扫描，AI 不开火）+ `attack_air_targets=false` |
| `F4(19)` | F-4 Phantom | Gladiator 中段（导弹卡车） | `enemy_f4.tres` + `default_gun.tres` + `default_missile.tres` + `agm_missile.tres`（双弹种 sparrow+sidewinder 总弹量大）| **5** | ∞ | **6** | 编队 2-3 架 | `_create_enemy` F4 case | gladiator_combat + 中等 aggression / engage_cooldown 2.5s（重而不灵活但导弹齐射强） |
| `F104(20)` | F-104 Starfighter | Lancer 纯速度截击 | `enemy_f104.tres` + `default_gun.tres` + `default_missile.tres` | **4** | ∞ | **5** | 编队 2-3 架 | `_create_enemy` F104 case | lancer_combat + 高 aggression / engage_cooldown 7s / engage_duration 5.5s（极速通过+一次发射后脱离，HP 32 纸糊） |
| `SU35(21)` | Su-35 Super Flanker | Gladiator 顶级（Su-27 强化版+TVC） | `enemy_su35.tres` + `default_gun.tres` + `default_missile.tres` + `agm_missile.tres` + `default_flare.tres`（fail 10%）| **8** | **3** | **9** | 编队 2-3 架 | `_create_enemy` SU35 case | gladiator_combat + 极高 aggression / engage_cooldown 1.2s + 沿用 Su-27 的 CobraManeuver（spawner 内挂载）；雷达 3000m/22°（强于 Su-27） |
| `FA18(22)` | F/A-18 Hornet | Gladiator 均衡舰载机（CSG 弹射） | `enemy_fa18.tres` + `default_gun.tres` + `default_missile.tres` + `default_flare.tres`（敌机统一限 1 枚） | **0**（CSG 事件弹射，不占 Token） | ∞ | CSG 接战触发 | CSG 引擎瞬刷 2 架（左右分开），之后每 120s 补 1 架，CV 沉则停 | `_create_enemy` FA18 case + `CarrierStrikeGroup.engage()` / `_launch_fa18` | gladiator_combat + aggression 0.85-1.0 / cooldown 1.5s / duration 35s（海军舰载机精锐：技能 0.55-0.78，超 MiG-23 略低于 Su-27）；callsign HRNT-XX |

## Adds 杂兵分类细节

目前有 Tu-160 横列波次 + AH-64/CH-47 纵阵波次 + SAM/AA 地面单位五种：

- **无反击、无规避、无雷达**：`enable_combat = false` + `radar_range = 0` + `simple_ai`
- **独立刷新系统**：`_update_tu160_flock`（survivor_mode.gd）自己的 timer，不走 `_update_spawner`
- **不占 Token**（`TOKEN_COST[12]=0`），实例计入 `_count_enemies()` 但不消耗预算
- **不被远距清理**（`skip_far_cleanup` meta → `_update_far_cleanup` 跳过）
- **族群 Flock 而非编队**：4 架直线横向交错排开，各自独立飞向终点，**不使用 `Squad` 类**
- **一击致命**：HP 60，被 `ENEMY_HP_MISSILE_CAP=75` 保证任何导弹都能一发命中
- **特殊坠落动画**：`crash_style="bomber"` meta → `_update_destroy` 走侧翻慢坠分支（5 秒，持续 `bank_angle` 累加模拟侧翻）
- **轰炸机外观**：`silhouette="bomber"` meta → `_draw_bomber_icon()` 大翼展 + 长机身
- **XP 奖励**：Adds 类（Tu-160/AH-64/CH-47）走 `SurvivorData.adds_xp_per_kill(level)`，每 kill = `ceil(xp_for_level(level) / 3)`（即当前等级所需经验的 1/3）。整组（≥3 只）击杀保证升 1 级；若玩家快满级时打一只也可能触发升级，体验更自然
- **完全被动**：不转弯（单点 waypoint 直线飞）、不规避、**被击中无任何反应**（与 UAV 等普通敌机区别开 — adds 是纯靶子）
- **跳过 3 个全局敌机系统**（`category=="adds"` meta 检测）：
  - `_update_hunters` — 不会被指派为玩家追击者
  - `_update_enemy_waypoints` — 每 8s 的"绕玩家圆周航点"不会覆盖其固定航线
  - `_update_far_cleanup` — `skip_far_cleanup` meta 使之不受距离清理
  - 新增 adds 类敌人必须同步排除这些系统，否则会被强制改向追玩家
- **生命期上限**：`despawn_after` meta 标记 120~150 秒后静默消失（防止 skip_far_cleanup 下无限堆积）
- **不走随机刷新**：Adds 类敌人**永不**由 `_update_spawner` / 任何 timer 自动出现 —— 由未来的事件系统（紧急事件 / 大地图 A→B 任务）手动调用 `_spawn_tu160_flock()` / `_spawn_ah64_flock()` / `_spawn_ch47_flock()` 触发。Debug 面板也能手动触发用于测试。
- **新增 Adds 步骤**：创建 tres → 加 EnemyType 枚举 → `survivor_data.gd` 加 `TOKEN_COST/INSTANCE_CAP/XP/FLOCK_SIZE/FLIGHT_DISTANCE/spacing 等几何参数`（不要加 UNLOCK_LEVEL/WAVE_INTERVAL）→ `_create_enemy` 加 base_params/type_tag/AI 分支 → 新增 `_spawn_xxx_flock()` 函数 → `_configure_adds_unit()` 已自动设置 despawn_after 清理 meta → Debug 面板加条目供手动测试

### 直升机专属细节（AH-64/CH-47）

- `silhouette="apache"` / `silhouette="chinook"` → `aircraft.gd` 里 `_draw_apache_icon` / `_draw_chinook_icon` 画出旋翼盘 + 旋转叶片
- `crash_style="heli"` → 坠落时尾桨失效自旋（大 yaw 旋转 + 中速下坠）
- **高度层**：AH-64/CH-47 固定 `AltitudeTier.LOW`（低空突防），Tu-160 固定 `AltitudeTier.HIGH`（战略轰炸）。`_spawn_*_flock` 直接指定单一 tier，不随机
- **1 枚热诱弹 + fail_chance**：Aircraft 的 `_update_flares` 里已有现成逻辑（FlareParams.fail_chance）—— 来袭导弹近到 release 距离时 roll 概率，命中失误则这枚导弹永远不会再触发 flare。恰好匹配"只用一次 + 概率触发"的设计。`enable_flare_reload=false`（默认）保证 1 枚用完就没了。
- **AH-64 对地武器 + 空中免疫**：挂 M230 30mm 机炮 + Hydra 70 火箭弹。**两处独立防火**：①`AIController.ground_combat_only=true` 保证 `_try_engage_simple` 只选 `GroundUnit` 作为 `_current_target`。②`Aircraft.attack_air_targets=false` 保证 `_auto_gun_scan` 在 `combat_target` 为空时也不会自动扫射路过的空中敌人（否则 Apache 会对穿过机头的玩家开火）。遇到地面敌方时走 `_update_combat_ground_attack` strafing 状态机。
- **AH-64 受击散队（jink 机动）**：`scatter_on_damage` meta + `Aircraft.flock_members` 共享引用。任一队员 `_apply_damage` 触发 `_trigger_flock_scatter()` 给所有队友设 `flock_scatter_timer = FLOCK_SCATTER_DURATION (3.5s)` + 随机侧向单位向量。AIController waypoint 分支用时间曲线复合偏移：`sin(progress×π)` 包络 × `sin(progress×τ×1.2)` weave × 侧向 650px ＋ 机头方向 × 200px 前冲 —— 形成明显的 S 型 jink 而非原地压杆。scatter 期间自动清空 `_current_target` 中断地面交战。
- **AH-64 菱形编队**：4 架偏移在 `_spawn_ah64_flock` 写死：[0] 队长 (0, 0)、[1/2] 两翼 (-fwd, ±lat)、[3] 殿后 (-2×fwd, 0)，全部沿 `flight_dir`/`lateral_axis` 变换到世界坐标。

## F-47 BOSS 王牌狙击小队

BVR 远距协同齐射 BOSS，事件触发：

> 设计权威源：[docs/specs/systems/ace-squadron-tier.md](../specs/systems/ace-squadron-tier.md)（王牌中队分层标准）。
> 本节只记"代码在哪 + 当前实际值"；数值该是多少以 spec 为准。

- **核心状态机**（`ace_squad.gd` `SquadState`）：INTRO（通场 4s）→ PURSUIT（各自跑 BFM，不干预战术树）；PURSUIT 可切 CLOAK（隐形 5.5s）或 ANCHOR_HOLD（玩家飞离锚点 4500px → 下 PATROL_RING 绕锚点）
- **赫尔贝特轮**（`herbst_maneuver.gd`）：被玩家近距追逐时触发 180° J-Turn 急转反杀。BOSS 专属可重复使用（15s 冷却），由 `ai_controller.gd` bvr_only 分支自动触发。**注**：F-47 现已不挂 Herbst（转移到 F-14 Poltergeist），见 `f47_ace_squad.gd` 注释
- **协同齐射**：`salvo_leader` 队长发射后广播齐射信号给僚机，0.1-0.4s 内 4 枚导弹齐射
- **光学隐形**：基础 CD **110s** + 随机抖动 **0~25s**（`SurvivorData.F47_CLOAK_CYCLE` / `F47_CLOAK_CYCLE_JITTER`），持续 5.5s，淡入淡出各 0.5s。效果：淡出消失 + 雷达锁定清除 + 导弹丢失制导 + 无法选中 + 子弹穿透。由 `ace_squad.gd` 的 `_cloak_enter/_cloak_update/_cloak_exit` 管理，全队共享计时器
- **热诱弹豁免**：不受敌机 `burst_count=1 / max_flares=1` 限制（BOSS 特权）。⚠ **但 `f47_flare.tres` 实际只有 `max_flares = 2` / `burst_count = 3`**，且敌机永不设 `enable_flare_reload` —— 净效果是**整场只能投放一次（2 枚）后永久耗尽**。豁免分支保护的值比它要防的限制还小，等同空转。修正方案见 spec §2.2
- **不走随机刷新**：不在 `_pick_enemy_type` 中，不被 `_update_spawner` 管理；由 `_spawn_f47_squad()` 专用函数触发（Debug 面板 / 未来事件系统）
- **独立航点**：`category="boss"` meta 使之跳过 `_update_hunters` 和 `_update_enemy_waypoints`
- **不受远距清理**：`skip_far_cleanup` meta

## 全局常量集中位置

**所有 Token / 上限 / 解锁常量** 都在 `survivor_data.gd` 里集中定义：

- `TOKEN_COST`（`:338`）/ `TOKEN_INSTANCE_CAP`（`:356`）/ `TOKEN_BUDGET_BASE/PER_LEVEL/MAX`（`:331`）
- `FAR_CLEANUP_DISTANCE`（`:372`）/ `FAR_CLEANUP_INTERVAL`（`:373`）/ `LATE_GAME_LEVEL`（`:379`）
- `LATE_GAME_MIN_TOKEN`（`:383`）/ `ENEMY_HP_MISSILE_CAP`（`:386`）
- 每个敌人的 `*_UNLOCK_LEVEL` / `*_CHANCE_PER_LEVEL` / `*_CHANCE_MAX`（`:288-314`）

## 创建新敌人的完整清单（"加一个敌人"触发短语）

**为避免通读数千行代码**，以下列出新增一个敌人必须同步修改的所有位置。按顺序操作：

> ⚠ **2026-07-20 订正**：刷怪逻辑早已从 `survivor_mode.gd` 搬到 **`survivor_spawner.gd`**，
> 本清单此前 7 步指向的文件都是错的。下列行号已用 `tools/verify_doc_anchors.py` 校验。

1. **创建 `.tres` 参数资源**（`resources/` 下）：
   - `enemy_<name>.tres` (AircraftParams)
   - 必要时同建对应的 `<name>_gun.tres` / `<name>_missile.tres` / `<name>_rocket.tres`
   - 可复用 `gladiator_combat.tres` / `lancer_combat.tres` / `default_combat.tres` 作为 `combat` 字段
   - ⚠ **`icon_color` / `wing_color` 必须选自暖色域**（橙→红表威胁层级；冷色蓝/青/绿只属于
     友好单位，spec global-awareness-roe §2.7 阵营色板规范）
2. **`survivor_spawner.gd:16` 的 `EnemyType` 枚举追加新值**（末尾，保持已有值不动）
3. **`survivor_spawner.gd:42` 起声明 `_<name>_params_base: AircraftParams` 成员**
4. **`survivor_spawner.gd:119` 起 `preload(...)` 加载资源**
5. **`survivor_data.gd:1554` 起加解锁/概率常量**（`<NAME>_UNLOCK_LEVEL` / `_CHANCE_PER_LEVEL` / `_CHANCE_MAX`）
6. **`survivor_data.gd:2100` `TOKEN_COST` 和 `:1685` `TOKEN_INSTANCE_CAP` 表补新枚举值**
7. **`survivor_spawner.gd:295` `_pick_enemy_type` 按威胁等级插入概率判定分支**
8. **`survivor_spawner.gd:1579` `_create_enemy` 的各 match 全部补新 case**：
   - `match etype` 选基础参数（`:1577`）
   - `enemy_scale_for_level` 适用判定（`:1646` 起）
   - 热诱弹失误概率 match（`:1689`）—— 越低级失误率越高
   - `type_tag` 映射（`:1759`）—— 第 10 步的无线电白名单要用这个 tag
   - AI 配置分支（`:1840` 起 — 仿照 F-86/MiG-23 写 `aggression`/`engage_cooldown` 等）
9. **`survivor_spawner.gd:432` `_update_spawner` 的编队/单机判定里追加**（精英单机 vs 成建制编队）
10. **决定它配不配无线电**（spec radio-chatter §2.8）：
    - 有人驾驶且够格说话 → 在 `resources/chatter/radio_chatter.json` 的 `voiced_enemy_types.types`
      加上第 8 步的 `type_tag`
    - **无人机** → 除了不加白名单，还要在 `_create_enemy` 里设 `enemy.no_pilot = true`
      （硬规则，同时让它免疫 FEAR 心理状态）
    - ⚠ 白名单是 **opt-in**：什么都不做 = 该敌人永远沉默。这是安全默认，但**别忘了给有人机开**
11. **更新 `survivor_debug_spawn.gd:42` 的 `ENEMY_TYPE_LABELS`**（让 F5 调试面板能手动刷）
12. **更新本文件（enemy-index.md）的 Enemy Index 表追加一行**
13. **更新 `docs/reference/code-index.md` 对应段落**，然后跑
    `python tools/verify_doc_anchors.py` 确认没写错行号

操作时用 Read 的 offset/limit 精确定位，不要通读整个 survivor_mode.gd（1450 行）。每一步改完就 commit 或至少 git diff 看一眼，防止漏 case 导致 NullRef 崩溃。
