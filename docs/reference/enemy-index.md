# Enemy Index — 生存模式敌人完整索引

> 本节内容原在 CLAUDE.md，2026-05-05 移出。

## AI 原型（Archetype）预设

参照经典空战文献的敌方行为分类，通过 `CombatParams` + `AIController` 参数组合实现：

| 原型 | 行为特征 | 预设文件 | 适用机型 |
|------|---------|----------|----------|
| **Gladiator（斗士）** | 积极近身狗斗，拉近距离，高转弯激进度，低自保 | `gladiator_combat.tres` / 注册表通用配置 | F-86、MiG-23、Su-27/Su-35、F-15C、Typhoon、Su-57 等 |
| **Lancer（骑士/打带跑）** | 高速一次性突击，闭合率不足即脱离，不缠斗 | `lancer_combat.tres` / 注册表通用配置 | J-7、F-104、MiG-31、F-14、Tornado、J-20 等 |
| **Schemer（策士）** | 特殊机制或远距循环；执行后换位，玩家靠近即脱离 | 注册表通用配置 + 专用控制器 | Sentinel、Snowblind、F-22、Gripen/Rafale/F-35、A-12 |
| **Adds（任务单位）** | 不占 Token 的事件族群；轰炸机执行航路任务，旋翼机使用独立运动模型 | — | Tu-160、AH-64、CH-47。MQ-109/MQ-110/F-4E 仍受刷怪系统管理，不归入此类 |
| **主力威胁** | 全能 BFM 战术 + 导弹缠斗 | `default_combat.tres` | MiG-29 |

⚠ 这些原型名称是**纯内部设计词汇**，不要写进玩家可见 UI / debug 面板 / `display_name`。仅可出现在源码注释、`.tres` 注释、设计文档里。

## Enemy Index

所有生存模式敌人的完整索引。**新增敌人必须在此表新增一行**，以便下次直接走索引而不通读代码。

`EnemyType` enum 在 `scripts/survivor/survivor_spawner.gd`；常规池选型、解锁、Token、编成与原型由
`scripts/survivor/enemy_pool_registry.gd` 集中登记。旧敌人仍保留专用生成分支，新扩池敌人共用注册表路径。

| EnemyType(int) | 显示名 | Archetype | `.tres` 参数 | Token | 实例上限 | 解锁等级 | 生成形式 | `_create_enemy` match 行 | AI 配置行 |
|---|---|---|---|---|---|---|---|---|---|
| `UAV(0)` | MQ-109 | Gladiator（前期杂鱼） | `enemy_uav.tres` | 1 | ∞ | 1 | 常规池仅响应等级 1–4；Sentinel 固定护卫不受退役线影响；ADBS 护卫独立按响应等级抽取；呼号 MQ109-XX | `_create_enemy` UAV case | simple_ai |
| `UCAV(1)` | MQ-110 | Adds | `enemy_uav_missile.tres` | 2 | ∞ | 1 | 编队(后期)；呼号 MQ110-XX | `:1046` | `:1240`(default) |
| `MIG(2)` | MiG-29 | 主力威胁 | `enemy_fighter.tres` | 4 | ∞ | 7 | 编队 | `:1042` | `:1158` |
| `INTERCEPTOR(3)` | J-7 | Lancer 入门 | `enemy_interceptor.tres` | 5 | ∞ | 5 | 单机→后期编队 | `:1044` | `:1167` |
| `UAV_COMMANDER(4)` | Sentinel | Schemer | `enemy_uav_commander.tres` | 6 | **1** | 4 | 自带 5 MQ-109 + 1 Aegis（随机刷新）；另 25% 概率作战区驻守障碍（`zone_mission._spawn_sentinel_garrison`，非 TGT）。elite 战区任务已移除 | `:1048` | `:1233` |
| `F86(5)` | F-86 | Gladiator 入门 | `enemy_f86.tres` + `f86_gun.tres` + `rocket_ffar.tres` | 3 | ∞ | 2 | 编队 | `:1050` | `:1183` |
| `MIG31(6)` | MiG-31 | Lancer 顶级 | `enemy_mig31.tres` | 8 | **2** | 9 | 单机 | `:1052` | `:1195` |
| `MIG23(7)` | MiG-23 | Gladiator 综合 | `enemy_mig23.tres` | 4 | ∞ | 4 | 编队 | `:1054` | `:1208` |
| `F100(8)` | F-100 | Lancer 编队 | `enemy_f100.tres` | 5 | **3** | 6 | 编队 | `:1056` | `:1220` |
| `SU27(9)` | Su-27 | Gladiator+眼镜蛇 | `enemy_su27.tres` | 7 | **2** | 8 | 单机 | `:1263` | `:1443` |
| `A7(10)` | A-7 | Lancer 亚音速攻击 | `enemy_a7.tres` + `a7_gun.tres` + `a7_rocket.tres` | 3 | ∞ | 3 | 编队 | `:1294` | `:1525` |
| `Q5(11)` | Q-5 | Lancer 超音速攻击 | `enemy_q5.tres` + `q5_gun.tres` + `q5_rocket.tres` | 4 | ∞ | 5 | 编队 | `:1296` | `:1538` |
| `TU160(12)` | Tu-160 "白天鹅" | **Adds 轰炸任务** | `enemy_tu160.tres`（任务炸弹由 BulletManager 管理） | **0** | ∞ | 事件触发 | 横列 4 架 | `spawn_bomber_mission` | 指定航路→5 弹弹带→直线离场 |
| `AH64(13)` | AH-64 Apache | **Adds 直升机（对地）** | `enemy_ah64.tres` + `ah64_gun.tres`（M230 30mm）+ `ah64_rocket.tres`（Hydra 70）+ 1 枚热诱弹 | **0** | ∞ | 事件触发 | **菱形 Flock** 4 架（队长前 + 左右两翼 + 殿后） | `_create_enemy` AH64 case | simple_ai + `ground_combat_only=true` + `attack_air_targets=false` |
| `CH47(14)` | CH-47 Chinook | **Adds 运输直升机** | `enemy_ch47.tres`（1 枚热诱弹，50% 失误概率） | **0** | ∞ | 事件触发 | **纵阵 Flock** 3 架 | `_create_enemy` CH47 case | AI 简化(simple_ai, 与 Tu-160 同) |
| `F47(15)` | F-47 | **BOSS 王牌狙击小队** | `enemy_f47.tres` + `default_gun.tres` + `f47_missile.tres`（AIM-260）+ `ace_flare.tres`（**热诱弹即命数：max_flares=4 / burst=1 → 整场 4 条命，干扰恒 100%、fail_chance=0、不补充**，见下方细节）+ `ace_combat.tres` | **10** | **4** | 事件触发 | **菱形编队** 4 架（队长+两翼+殿后）| `_create_enemy` F47 case + `_spawn_f47_squad` | BVR 狙击模式(bvr_only) + 协同齐射(salvo_leader) + 距离切换由 `aircraft_weapons.update_weapon_mode` GUN/MISSILE 枚举管 |
| `AF03(17)` | AF-03 | **Schemer 电磁炮狙击** | `enemy_af03.tres` + `enemy_railgun.tres`（充能 2.0s + 锁定 0.5s, AT_FIRE_TIME 预测命中, dmg 60, range 14000m, base+cloud+lowalt miss 加成）| **7** | **1** | **7**（旅途随机池 + 战区池）| 单机 | `_create_enemy` AF03 case + `_pick_enemy_type` 优先级 ≈ Su-27（常量 `survivor_data.gd` `AF03_UNLOCK_LEVEL/_CHANCE_PER_LEVEL/_CHANCE_MAX`）+ `ZONE_ENEMY_TABLE` type 17 行（战区池）| bvr_only @ 5-8km + prefer_nose_aligned_weapon (SNIPER_HOLD) + Lancer 节奏（10s/7s）+ 等级缩放 |
| `UAV_LASER(18)` | Aegis UAV | **拦截支援 Schemer** | `enemy_uav_laser.tres` + `enemy_laser_interceptor.tres`（target_filter 仅 missiles, dps_max=80, range 1200m）| **2** | 2 | 跟随 Sentinel 自动出现 | Sentinel 编队的一部分 | `_create_enemy` UAV_LASER case + `_spawn_commander_squad` 末尾追加 2 架 | simple_ai + `enable_combat=false`（laser 自己扫描，AI 不开火）+ `attack_air_targets=false` |
| `F4(19)` | F-4 Phantom | Gladiator 中段（导弹卡车） | `enemy_f4.tres` + `default_gun.tres` + `default_missile.tres` + `agm_missile.tres`（双弹种 sparrow+sidewinder 总弹量大）| **5** | ∞ | **6** | 编队 2-3 架 | `_create_enemy` F4 case | gladiator_combat + 中等 aggression / engage_cooldown 2.5s（重而不灵活但导弹齐射强） |
| `F104(20)` | F-104 Starfighter | Lancer 纯速度截击 | `enemy_f104.tres` + `default_gun.tres` + `default_missile.tres` | **4** | ∞ | **5** | 编队 2-3 架 | `_create_enemy` F104 case | lancer_combat + 高 aggression / engage_cooldown 7s / engage_duration 5.5s（极速通过+一次发射后脱离，HP 32 纸糊） |
| `SU35(21)` | Su-35 Super Flanker | Gladiator 顶级（Su-27 强化版+TVC） | `enemy_su35.tres` + `default_gun.tres` + `default_missile.tres` + `agm_missile.tres` + `default_flare.tres`（fail 10%）| **8** | **3** | **9** | 编队 2-3 架 | `_create_enemy` SU35 case | gladiator_combat + 极高 aggression / engage_cooldown 1.2s + 沿用 Su-27 的 CobraManeuver（spawner 内挂载）；雷达 4600px/±30°（强于 Su-27 4200px；敌机分带见 [specs/systems/radar-range-normalization](../specs/systems/radar-range-normalization.md)） |
| `FA18(22)` | F/A-18 Hornet | Gladiator 均衡舰载机（CSG 弹射） | `enemy_fa18.tres` + `default_gun.tres` + `default_missile.tres` + `default_flare.tres`（敌机统一限 1 枚） | **0**（CSG 事件弹射，不占 Token） | ∞ | CSG 接战触发 | CSG 引擎瞬刷 2 架（左右分开），之后每 120s 补 1 架，CV 沉则停 | `_create_enemy` FA18 case + `CarrierStrikeGroup.engage()` / `_launch_fa18` | gladiator_combat + aggression 0.85-1.0 / cooldown 1.5s / duration 35s（海军舰载机精锐：技能 0.55-0.78，超 MiG-23 略低于 Su-27）；callsign HRNT-XX |
| `F4E(23)` | F-4E | 前期导弹杂鱼（有人机） | `enemy_f4e.tres` + `default_missile.tres`（占位，V-tier 注入 offset −1）；**无机炮、无热诱弹**（初始敌机零对抗，spec v3） | **2** | ∞ | **1**（retire 6，F4E_CHANCE 0.40 平坦） | 单机 35% / 小队 2-3 架（"杂鱼成建制"规则的显式例外，spec [enemies/f-4e](../specs/enemies/f-4e.md)） | `_create_enemy` F4E case | default_combat + aggression 0.5-0.7 / cooldown 4.0s / 低技袍（skill 0.25-0.45）；不 joust 不规避；XP 32 |
| `F15(24)` | F-15 | **王牌专属**（2NDWAVE 学员骑士 element） | `enemy_f15.tres`（lancer_combat） | 0（事件供给，不进随机池/无缩放） | — | 事件 | AceSquadProfiles elements 生成；装备覆写=无机炮/载弹 6 硬预算 | `_create_enemy` F15 case | AI 由 ace 层配置（ai_level 0.92）；spec [events/ace-2ndwave](../specs/events/ace-2ndwave.md) |
| `F16(25)` | F-16 | **王牌专属**（GIMMICK 狙击 element） | `enemy_f16.tres`（default_combat） | 0（同上） | — | 事件 | elements 生成；AceRole.SNIPER 站位带 4~6km + ace_gun + 载弹 6 | `_create_enemy` F16 case | spec [events/ace-gimmick](../specs/events/ace-gimmick.md) |
| `MIRAGE2000(26)` | Mirage 2000 | **王牌专属**（GIMMICK 斗士 element） | `enemy_mirage2000.tres`（gladiator_combat） | 0（同上） | — | 事件 | elements 生成；KNIGHT 近战 + ace_gun | `_create_enemy` MIRAGE2000 case | spec 同上 |
| `SU47(27)` | Su-47 | **王牌专属**（GOOFIGHTERS 眼镜蛇斗士） | `enemy_su47.tres`（gladiator_combat；**无中距弹**、QMAAM 副槽 + spawner 挂 CobraManeuver） | 0（同上） | — | 事件 | profile 生成 ×2；cobra 王牌分层门=flare 耗尽后解锁（CobraManeuver 内 AceTier 判定） | `_create_enemy` SU47 case（AI 分支挂 cobra） | spec [events/ace-goofighters](../specs/events/ace-goofighters.md) |
| `CRE(28)` | Cre（宿敌 ORION） | **宿敌专属**（跨局成长单机） | `enemy_cre.tres`（default_combat；初始敌机级基线，档位表运行时覆写） | 0（独立轨道事件） | **1** | 事件（game_time ≥300s 每局一次） | OrionNemesisEvent 生成；机号即呼号 Cre-XX；`no_pilot`（无人原型机，静默+FEAR 免疫） | `_create_enemy` CRE case | spec [events/ace-orion](../specs/events/ace-orion.md) |
| `YF23(29)` | YF-23 Black Widow II | **Wraith 通关强化专属支援** | `enemy_yf23.tres` + `f47_missile.tres`（AIM-260）+ `default_flare.tres`；无机炮 | 0（事件供给，不进随机池/无缩放） | **2** | Wraith 历史击败 ≥1 | `F47AceSquad.engage()` 生成左右各一架；`boss_support`、雷达静默、可选击毁、不进 BOSS 血条/胜利判定 | `_create_enemy` YF23 case | `bvr_only` 4–6km + 高空 + TS_BOSS 追当前玩家；spec [systems/boss-clear-progression](../specs/systems/boss-clear-progression.md) |
| `F22(30)` | F-22 Raptor | Schemer 四锁远距 | `enemy_f22.tres` + `enemy_f22_flare.tres` | 10 | **3** | 13 | 1–3 架；阶段累计 6；冷却 150s | 注册表 `_create_enemy` | `f22_multilock.gd`：队级目标去重、每机≤4、0.15s 齐射、12s 脱离 |
| `SNOWBLIND(31)` | SNOWBLIND | Schemer 纯支援 | `enemy_snowblind.tres` | 4 + 两护卫各自 Token | **1** | 8 | 本体 + 2 架当前响应等级可用战斗机；最低完整编成 10 Token；阶段累计 2；冷却 180s | `_spawn_snowblind_squad` | `snowblind_controller.gd`：4000m 雪幕、5Hz 显隐与双向交战边界；圆心只显示不可交互本体轮廓，真实本体无武器/flare且仍隐藏 |
| `F15_REGULAR(32)` | F-15 Eagle | Gladiator | `enemy_regular_f15.tres` | 6 | ∞ | 7 | 2–3 架 | 注册表 `_create_enemy` | `_configure_registry_archetype` 持续近战 |
| `F14(33)` | F-14 Tomcat | Lancer | `enemy_f14.tres` | 6 | **3** | 7 | 2 架 | 注册表 `_create_enemy` | `_configure_registry_archetype` 远程攻击通场 |
| `A6E(34)` | A-6E Intruder | Lancer | `enemy_a6e.tres` | 3 | ∞ | 3 | 2–3 架 | 注册表 `_create_enemy` | 低空攻击通场 |
| `MIRAGE3(35)` | Mirage III | Lancer | `enemy_mirage3.tres` | 3 | ∞ | 2 | 2–3 架 | 注册表 `_create_enemy` | 高速截击通场 |
| `MIRAGE2000_REGULAR(36)` | Mirage 2000 | Gladiator | `enemy_regular_mirage2000.tres` | 5 | ∞ | 6 | 2–3 架 | 注册表 `_create_enemy` | 持续近战 |
| `FA18E(37)` | F/A-18E | Gladiator | `enemy_fa18e.tres` | 6 | ∞ | 7 | 2–3 架 | 注册表 `_create_enemy` | 持续近战 |
| `F16_REGULAR(38)` | F-16 | Gladiator | `enemy_regular_f16.tres` | 4 | ∞ | 5 | 2–4 架 | 注册表 `_create_enemy` | 轻型持续近战 |
| `A10(39)` | A-10 | Gladiator | `enemy_a10.tres` | 4 | ∞ | 4 | 2–3 架 | 注册表 `_create_enemy` | 低速强攻近战 |
| `F15C(40)` | F-15C | Gladiator | `enemy_f15c.tres` | 7 | **3** | 9 | 2 架 | 注册表 `_create_enemy` | 高能持续近战 |
| `F15E(41)` | F-15E | Lancer | `enemy_f15e.tres` | 6 | **3** | 8 | 2 架 | 注册表 `_create_enemy` | 重载攻击通场 |
| `GRIPEN_C(42)` | JAS 39C | Schemer 协同导弹 | `enemy_gripen_c.tres` | 5 | **4** | 6 | 3 架 | 注册表 `_create_enemy` | `schemer_multilock.gd` 队级 3 目标、每机 1 发 |
| `RAFALE(43)` | Rafale | Schemer 双锁 | `enemy_rafale.tres` | 7 | **3** | 9 | 2 架 | 注册表 `_create_enemy` | `schemer_multilock.gd` 每机 2 目标 |
| `TORNADO(44)` | Tornado | Lancer | `enemy_tornado.tres` | 5 | ∞ | 6 | 2–3 架 | 注册表 `_create_enemy` | 高速重载攻击通场 |
| `TYPHOON(45)` | Eurofighter Typhoon | Gladiator | `enemy_typhoon.tres` | 7 | **3** | 9 | 2 架 | 注册表 `_create_enemy` | 高能持续近战 |
| `SU34(46)` | Su-34 | Lancer | `enemy_su34.tres` | 6 | **3** | 8 | 2 架 | 注册表 `_create_enemy` | 重载攻击通场 |
| `VIGGEN(47)` | Saab 37 Viggen | Lancer | `enemy_viggen.tres` | 4 | ∞ | 5 | 2–3 架 | 注册表 `_create_enemy` | 高速截击通场 |
| `HARRIER(48)` | Harrier | Gladiator | `enemy_harrier.tres` | 4 | ∞ | 5 | 2–3 架 | 注册表 `_create_enemy` | 高鼻向近战 |
| `F15SMTD(49)` | F-15 S/MTD | Gladiator 后失速 | `enemy_f15smtd.tres` | 8 | **2** | 11 | 1–2 架 | 注册表 `_create_enemy` | 持续近战 + `CobraManeuver` |
| `F35(50)` | F-35 | Schemer 双锁 | `enemy_f35.tres` | 8 | **2** | 11 | 1–2 架 | 注册表 `_create_enemy` | `schemer_multilock.gd` 每机 2 目标 |
| `GRIPEN_E(51)` | JAS 39E | Schemer 协同导弹 | `enemy_gripen_e.tres` | 7 | **3** | 10 | 2–3 架 | 注册表 `_create_enemy` | `schemer_multilock.gd` 队级 3 目标、每机 1 发 |
| `SU57(52)` | Su-57 | Gladiator 后失速 | `enemy_su57.tres` | 9 | **2** | 12 | 1–2 架 | 注册表 `_create_enemy` | 持续近战 + `CobraManeuver` |
| `J20(53)` | J-20 | Lancer | `enemy_j20.tres` | 9 | **2** | 12 | 1–2 架 | 注册表 `_create_enemy` | 远程高速攻击通场 |
| `A12(54)` | A-12 Avenger II | Schemer 远距 | `enemy_a12.tres` | 8 | **2** | 13 | 1–2 架 | 注册表 `_create_enemy` | 单目标远距重击后换位 |
| `FCK1(55)` | F-CK-1 | **王牌专属**（WhiteTea 机炮骑士） | `enemy_fck1.tres` + `whitetea_gun.tres`（4×5 受控短梭；纯机炮无导弹） | 0（事件供给，不进随机池/无缩放） | **3** | 事件（240s 统一王牌池） | WhiteTea profile 生成 ×3；逐机 joust 打带逃，1 flare 耗尽后解锁一次性 J-turn；2→1 时幸存者投降转 ALLY、本人喊话后被动离场 | `_create_enemy` FCK1 case | AceSupportSquad `gun_lancer`；`AceReinforcementEvent._try_whitetea_surrender`；spec [events/ace-whitetea-fck1](../specs/events/ace-whitetea-fck1.md) / [systems/dynamic-faction-conversion](../specs/systems/dynamic-faction-conversion.md) |

### 敌人作战高度分档（2026-07-28）

敌机的初始高度档**不再是 spawn 代码里的均匀 1/3 随机**，改为按机型查表：

- 权重表 `SurvivorData.ENEMY_ALTITUDE_WEIGHTS`（EnemyType → [LOW, MID, HIGH] 权重）+ 抽档函数 `SurvivorData.pick_altitude_tier(etype)`
- 抽到的档同时决定 `AIController.patrol_altitude`：`SurvivorData.TIER_PATROL_ALTITUDE` + `SurvivorData.patrol_altitude_for_tier(tier_idx)`
  （patrol_altitude 经 `Situation.combat_altitude_m` 影响战术层交战高度，不同步的话档位分化只影响巡逻段）
- 消费点在 `survivor_spawner._create_enemy`；**未登记的类型**（BOSS / adds / 事件单位，档位由各自 spawn 代码事后覆写）维持原行为
- 逐符号行号见 [code-index.md](code-index.md) 的「刷怪 & Token 烈度控制」表

## Adds 杂兵分类细节

目前有 Tu-160 轰炸波次 + AH-64/CH-47 旋翼机波次；SAM/AA 是地面任务单位，不属于飞机 Adds：

- **任务化行为**：Tu-160 由 `BomberMission` 10Hz 集中控制投弹；AH-64 只对地环绕/悬停开火；CH-47 沿航线平移。
- **独立刷新系统**：`_update_tu160_flock`（survivor_mode.gd）自己的 timer，不走 `_update_spawner`
- **不占 Token**（`TOKEN_COST[12]=0`），实例计入 `_count_enemies()` 但不消耗预算
- **不被远距清理**（`skip_far_cleanup` meta → `_update_far_cleanup` 跳过）
- **族群 Flock 而非编队**：共享任务与航路偏移，**不使用 `Squad` 类**。
- **一击致命**：HP 60，被 `ENEMY_HP_MISSILE_CAP=75` 保证任何导弹都能一发命中
- **特殊坠落动画**：`crash_style="bomber"` meta → `_update_destroy` 走侧翻慢坠分支（5 秒，持续 `bank_angle` 累加模拟侧翻）
- **轰炸机外观**：`silhouette="bomber"` meta → `_draw_bomber_icon()` 大翼展 + 长机身
- **XP 奖励**：Adds 类（Tu-160/AH-64/CH-47）与普通敌机同一公式 `base + level×8`（2026-07-28 等级计价废除，spec survivor-loop §5）：`XP_PER_KILL_TU160=80` / `XP_PER_KILL_AH64=50` / `XP_PER_KILL_CH47=40`（常量在 survivor_data.gd Adds 段）。整组击杀 ≈ 1~1.5 级，仍是最肥经验事件但不再一波 3-4 级
- **轰炸权限**：B-1B/Tu-160 炸弹只伤敌对 GroundUnit；战略硬目标永久不可锁定且只接受 `bomber_bomb`。
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
- **AH-64 对地武器 + 空中免疫**：M230 40 伤害、6 发短梭 + Hydra；`_process_rotorcraft` 只选可锁定 GroundUnit，`attack_air_targets=false` 同时封住机炮自动扫与火箭 Aircraft 候选。运动走 500m 环绕→刹停→3.5–6s 悬停，不进入固定翼 strafing/BFM。
- **AH-64 受击散队（jink 机动）**：`scatter_on_damage` meta + `Aircraft.flock_members` 共享引用。任一队员 `_apply_damage` 触发 `_trigger_flock_scatter()` 给所有队友设 `flock_scatter_timer = FLOCK_SCATTER_DURATION (3.5s)` + 随机侧向单位向量。AIController waypoint 分支用时间曲线复合偏移：`sin(progress×π)` 包络 × `sin(progress×τ×1.2)` weave × 侧向 650px ＋ 机头方向 × 200px 前冲 —— 形成明显的 S 型 jink 而非原地压杆。scatter 期间自动清空 `_current_target` 中断地面交战。
- **AH-64 菱形编队**：4 架偏移在 `_spawn_ah64_flock` 写死：[0] 队长 (0, 0)、[1/2] 两翼 (-fwd, ±lat)、[3] 殿后 (-2×fwd, 0)，全部沿 `flight_dir`/`lateral_axis` 变换到世界坐标。

## F-47 BOSS 王牌狙击小队

BVR 远距协同齐射 BOSS，事件触发：

> 设计权威源：[docs/specs/systems/ace-squadron-tier.md](../specs/systems/ace-squadron-tier.md)（王牌中队分层标准）。
> 本节只记"代码在哪 + 当前实际值"；数值该是多少以 spec 为准。

- **核心状态机**（`ace_squad.gd` `SquadState`）：INTRO（通场 4s）→ PURSUIT（各自跑 BFM，不干预战术树）；PURSUIT 只会被 CLOAK（隐形 5.5s）打断，之后必回 PURSUIT。**无归巢态** —— 2026-07-22 按 spec boss-hunter-doctrine 删除 ANCHOR_HOLD：王牌中队是猎手，玩家跑多远都追
- **角色**（`ace_squad.gd` `AceRole`）：前 2 架 KNIGHT（机炮近战 / `bvr_only=false` 被咬转身对抗），后 2 架 SNIPER（导弹 / `bvr_only=true` 站位带 4~6km，被压近即拉开）。取代此前两个死 meta `combat_specialty`（只写不读）与 `f47_role`（只读不写）
- **赫尔贝特轮**（`herbst_maneuver.gd`）：被玩家近距追逐时触发 180° J-Turn 急转反杀。默认可重复使用（15s 冷却）；profile 可限制次数与要求 flare 耗尽。F-14 Poltergeist 保留默认行为，WhiteTea 每机一次并采用 flare 分层门。
- **协同齐射**：`salvo_leader` 队长发射后广播齐射信号给僚机，0.1-0.4s 内 4 枚导弹齐射
- **光学隐形**：基础 CD **110s** + 随机抖动 **0~25s**（`SurvivorData.F47_CLOAK_CYCLE` / `F47_CLOAK_CYCLE_JITTER`），持续 5.5s，淡入淡出各 0.5s。效果：淡出消失 + 雷达锁定清除 + 导弹丢失制导 + 无法选中 + 子弹穿透。由 `ace_squad.gd` 的 `_cloak_enter/_cloak_update/_cloak_exit` 管理，全队共享计时器
- **热诱弹豁免**：不受敌机 `burst_count=1 / max_flares=1` 限制（BOSS 特权）。⚠ **但 `f47_flare.tres` 实际只有 `max_flares = 2` / `burst_count = 3`**，且敌机永不设 `enable_flare_reload` —— 净效果是**整场只能投放一次（2 枚）后永久耗尽**。豁免分支保护的值比它要防的限制还小，等同空转。修正方案见 spec §2.2
- **不走随机刷新**：不被 `_update_spawner` 管理；由 `_spawn_f47_squad()` 专用函数触发（Debug 面板 / 事件系统）。
  `_pick_enemy_type` 的后期随机桶此前遍历整张 `TOKEN_COST` 取 cost ≥ `LATE_GAME_MIN_TOKEN`，F-47(15) 与 F-14 Poltergeist(16) 靠高 Token 从这里漏出过；
  现由 `survivor_data.gd` 的 `BOSS_ONLY_TYPES` 名单在该桶里显式排除（消费点 `survivor_spawner._pick_enemy_type`）。加新 BOSS 专属机型必须同步进这张名单
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
6. **`survivor_data.gd:3044` `TOKEN_COST` 和 `survivor_data.gd:3149` `TOKEN_INSTANCE_CAP` 表补新枚举值**
7. **`survivor_spawner.gd:402` `_pick_enemy_type` 按威胁等级插入概率判定分支**
8. **`survivor_spawner.gd:2098` `_create_enemy` 的各 match 全部补新 case**：
   - `match etype` 选基础参数（`:1577`）
   - `enemy_scale_for_level` 适用判定（`:1646` 起）
   - 热诱弹失误概率 match（`:1689`）—— 越低级失误率越高
   - `type_tag` 映射（`:1759`）—— 第 10 步的无线电白名单要用这个 tag
   - AI 配置分支（`:1840` 起 — 仿照 F-86/MiG-23 写 `aggression`/`engage_cooldown` 等）
9. **`survivor_spawner.gd:606` `_update_spawner` 的编队/单机判定里追加**（精英单机 vs 成建制编队）
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
