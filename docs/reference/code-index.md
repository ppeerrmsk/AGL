# 代码索引

按功能主题索引到 `文件:行号`，直接 Read 对应行号即可获取上下文。

> ✅ **2026-07-20 全量校验通过**：`docs/reference/` + `docs/systems/` + `docs/architecture/` +
> `docs/specs/` + CLAUDE.md 共 75 份文档、328 个锚点已逐条对代码校验，无腐烂。
> （2026-04-22 拆子模块重构遗留的 218 处失效锚点已批量修复。）
>
> **改代码后同步本文件，并跑校验器**：
> ```
> python tools/verify_doc_anchors.py                     # 全量
> python tools/verify_doc_anchors.py --section 无线电通讯  # 只查你动的那段
> ```
> 退出码 1 = 有锚点对不上。写锚点时**带上符号名**（`aircraft/aircraft_physics.gd:222 update_speed`），
> 校验器才能做强校验；只写行号只能校验"没越界"—— 历史上正是这类弱锚点掩盖了指错文件的错误。
>
> **重构后代码去哪了**（2026-04-22 拆子模块，私有方法搬进模块时**去掉了前导下划线**）：
>
> - **物理**（bank/heading/speed/altitude/stall/fuel/energy）→ `scripts/aircraft/aircraft_physics.gd`
> - **武器**（gun/ciws/rocket/missile/weapon_mode）→ `scripts/aircraft/aircraft_weapons.gd`
> - **战斗追踪**（update_combat / 对地攻击 / 包线判定）→ `scripts/aircraft/aircraft_combat_tracking.gd`
> - **热诱弹**（`AircraftFlares.update` / `.release`）→ `scripts/aircraft/aircraft_flares.gd`
> - **编队** → `scripts/aircraft/aircraft_formation.gd`
> - **BFM 战术 / 目标选择 / 导弹规避 / 编队协同** → `scripts/ai/` 下 4 个子模块
> - **刷怪与建敌**（`_pick_enemy_type` / `_create_enemy` / `_update_spawner`）→ `scripts/survivor/survivor_spawner.gd`
> - **地形绘制**（`_init_noise` / `_draw_grid`）→ `scripts/terrain_renderer.gd`
>
> ⚠ **飞行员耐力（pilot stamina）当前无代码实现**（全仓库 0 处引用），但
> **概念保留** —— 计划在将来的拟真战役模式重新启用。`i18n/translations.csv` 的
> `UPGRADE_PILOT_STAMINA_*` 三语文本**刻意保留，不要当死键清掉**。

---

## 飞行物理

| 功能 | 位置 |
|------|------|
| 物理主循环 | `aircraft.gd:827` _physics_process |
| 目标航向计算 | `aircraft/aircraft_physics.gd:71` update_target_heading |
| 滚转角更新（G 限制由 tactical_aggression 插值调节）| `aircraft/aircraft_physics.gd:88` update_bank |
| 航向更新 ω=g×tan(bank)/speed | `aircraft/aircraft_physics.gd:203` update_heading |
| 速度更新（含高G阻力、高度耦合） | `aircraft/aircraft_physics.gd:222` update_speed |
| 高度更新 | `aircraft/aircraft_physics.gd:336` update_altitude |
| 失速检查 | `aircraft/aircraft_physics.gd:377` update_stall |
| G力计算 | `aircraft/aircraft_physics.gd:399` update_g_load |
| 飞行员耐力 | **代码已移除**（保留概念：将来拟真战役模式再启用；`i18n` 的 `UPGRADE_PILOT_STAMINA_*` 三语文本刻意保留） |
| 位移应用 | `aircraft/aircraft_physics.gd:432` apply_movement |
| 最大 bank 角（物理瞬时上限） | `aircraft/aircraft_physics.gd:441` max_bank_angle |
| 有效最大G（**buff 注入点**，SEAM-001） | `aircraft/aircraft_physics.gd:484` effective_max_g；瞬时结构 G = `:493` effective_max_g_instant |
| 角点速度 V=V_stall×1.2×√G | `aircraft/aircraft_physics.gd:506` corner_speed_kmh |
| 失速速度 V_stall×√G | `aircraft/aircraft_physics.gd:605` stall_speed |
| 高空最大速度衰减 | `aircraft/aircraft_physics.gd:614` max_speed_at_altitude |
| 空气密度比 σ=e^(-alt/8500) | `aircraft/aircraft_physics.gd:636` air_density_ratio |
| 高度档位切换（生存模式） | `aircraft.gd:1354` set_target_tier |

## 能量管理

| 功能 | 位置 |
|------|------|
| 能量管理总入口 | `aircraft/aircraft_physics.gd:833` update_energy_management |
| 加力燃烧器开关 | `aircraft/aircraft_physics.gd:799` set_afterburner |
| 燃油消耗 | `aircraft/aircraft_physics.gd:813` update_fuel |

## 战斗追踪（Aircraft 内置）

| 功能 | 位置 |
|------|------|
| 战斗追踪主逻辑（空对空） | `aircraft/aircraft_combat_tracking.gd:60` update_combat |
| 对地攻击（Apache 专用 `_strafe_state`，不经 planner） | `aircraft/aircraft_combat_tracking.gd:273` update_combat_ground_attack |
| 对面攻击 pass 循环（planner 路径：玩家指挥机+迁移 AI+舰船，SETUP/RUN/EGRESS + 姿态 STANDOFF/ASSAULT，spec surface-attack-pass） | `ai/tactical/bfm_intent.gd` ground_strafe + `_strafe_pass_phase`（Aircraft 状态位） |
| 慢速空目标（直升机）交战 pass（spec slow-air-target-pass；与地面 pass 同一台相位机，只换包络） | `ai/tactical/situation.gd` `tgt_is_slow_air` + `SLOW_AIR_SPEED_RATIO` / `ai/tactical/tactical_planner.gd` 优先级 4.5 分流 / `ai/tactical/bfm_intent.gd` `SLOW_AIR_*` 常量 |
| 碰撞航路拦截点（解交会时刻，SETUP 段引导；区别于按弹速算的机炮提前点） | `ai/tactical/bfm_intent.gd` `_intercept_point`（对照 `_gun_lead_point`） |
| 导弹相位坡度软化的适用门（锁定满但仍在发射锥外 → 不降转弯权限，破"锁上了转不动"死锁） | `aircraft.gd` `_get_missile_phase` + `_target_within_launch_cone` |
| planner 统一时钟源（无头 sim 可拨快；intent hysteresis / EXTEND 倒计时都读它） | `ai/tactical/situation.gd` `now` + `sim_time_override`（`aircraft.gd` 写 `_bfm_extend_until` 也走它） |
| 设定战斗目标 | `aircraft.gd:1701` set_combat_target |
| 清除战斗目标 | `aircraft.gd:1713` clear_combat_target |
| CombatParams 获取 | `aircraft.gd:1777` _combat_params |
| 自动扫描机炮目标 | `aircraft/aircraft_weapons.gd:107` auto_gun_scan |

## 武器系统 — 机炮

| 功能 | 位置 |
|------|------|
| 机炮射击更新（梭射状态机，spec: gun-burst-fire） | `scripts/aircraft/aircraft_weapons.gd` update_gun |
| 单发出弹（散布/云雾/多管/音效/弹药） | `scripts/aircraft/aircraft_weapons.gd` _fire_gun_round |
| 梭射常量（DUTY/MIN_INTRA/帧补上限） | `scripts/aircraft/aircraft_weapons.gd` GUN_BURST_* |
| 梭计数状态 | `aircraft.gd` _gun_burst_rounds_left（_fire_cooldown 旁） |
| 每梭弹数参数 | `scripts/gun_params.gd` burst_count |
| [GUN_BURST] 梭起始诊断（射向/最近敌机距离快照，追"对空放枪"） | `scripts/aircraft/aircraft_weapons.gd` _log_burst_start |
| [GUN_SCAN] 被动扫描锁存上升沿诊断 | `scripts/aircraft/aircraft_weapons.gd` auto_gun_scan 尾部 |
| 机炮射程（像素） | `aircraft.gd:1785` _gun_range_px |
| 子弹生成 | `bullet_manager.gd:119` spawn_bullet |
| 子弹物理+命中检测 | `bullet_manager.gd` _physics_process |
| 曳光弹绘制 | `bullet_manager.gd` _draw（区分 is_rocket）|

## 武器系统 — 火箭弹（无制导副武器，例：F-86 FFAR）

| 功能 | 位置 |
|------|------|
| RocketParams 定义（齐射数/散布/冷却/射程）| `scripts/rocket_params.gd` |
| 火箭弹发射主逻辑（齐射排队 + 距离/角度过滤）| `aircraft/aircraft_weapons.gd:498` update_rocket |
| 单发火箭出膛 | `aircraft/aircraft_weapons.gd:581` _launch_rocket |
| 火箭弹生成（BulletManager 共享） | `bullet_manager.gd:165` spawn_rocket |
| 火箭弹命中 / 伤害无衰减 / 更大判定半径 | `bullet_manager.gd` _physics_process 分支 `is_rocket` |
| 橙红尾迹 + 白色弹头绘制 | `bullet_manager.gd` _draw 分支 `is_rocket` |
| 火箭弹字段（AircraftParams） | `aircraft_params.gd` `rocket: RocketParams` |
| F-86 火箭资源 | `resources/rocket_ffar.tres` |
| 敌方火箭弹 tier 资源表（V1~V8，等级成长唯一杠杆）| `survivor/survivor_data.gd:2960` ENEMY_ROCKET_TIERS → `resources/weapons/enemy_rocket_v1.tres` ~ `enemy_rocket_v8.tres` |
| └ tier 注入点（`_create_enemy` 内按等级 duplicate 挂载）| `survivor/survivor_spawner.gd:2861` ENEMY_ROCKET_TIERS |
| └ 齐射数实际取 `burst_count_max`（`burst_count_min` 目前未被读取）| `scripts/rocket_params.gd` burst_count_max / `aircraft/aircraft_weapons.gd:498` update_rocket |

## AI 原型预设（CombatParams）

| 原型 | 文件 | 特征 |
|------|------|------|
| Gladiator（斗士） | `resources/gladiator_combat.tres` | intercept_range_mult=1.6 / 低 six_oclock_offset / 高 bank_aggression / 低 maneuver_speed |
| Lancer（骑士/打带跑） | `resources/lancer_combat.tres` | intercept_range_mult=3.5 / 高 approach_speed / 高 closing_rate_threshold（闭合不够就放弃）|
| F-86 参数 | `resources/enemy_f86.tres` | 亚音速 + 高G + Gladiator combat + FFAR + 6x.50cal |
| F-86 专用机炮 | `resources/f86_gun.tres` | 低伤害低射速（避免秒杀玩家）|
| F-86 生存模式 AI | `scripts/survivor/survivor_mode.gd` EnemyType.F86 分支 | 高 aggression / 低 self_preservation / 长 engage_duration |
| A-7 参数 | `resources/enemy_a7.tres` | 亚音速 + 低G + Lancer combat + Zuni + M61 火神炮（高弹量）|
| A-7 专用机炮 | `resources/a7_gun.tres` | M61A1 20mm（400发，中射速）|
| A-7 火箭弹 | `resources/a7_rocket.tres` | Zuni 5"（高伤害 14，低弹量 16）|
| Q-5 参数 | `resources/enemy_q5.tres` | 微超音速 + 中G + Lancer combat + 57mm + 23mm 双炮 |
| Q-5 专用机炮 | `resources/q5_gun.tres` | 23-2K 23mm x2（200发）|
| Q-5 火箭弹 | `resources/q5_rocket.tres` | 57mm 火箭弹（低伤害 8，高弹量 32，大散布）|

## 武器系统 — 导弹

| 功能 | 位置 |
|------|------|
| 武器模式切换（MISSILE/GUN） | `aircraft/aircraft_weapons.gd:617` update_weapon_mode |
| 战术偏好武器模式（带机炮回退） | `aircraft/aircraft_weapons.gd:670` _update_weapon_mode_tactical |
| 导弹打不中但机炮能打（有滞回） | `aircraft/aircraft_combat_tracking.gd:578` missile_cannot_hit_but_gun_can |
| 机炮冲锋：进入承诺判定 | `aircraft/aircraft_combat_tracking.gd:611` should_commit_gun_pass |
| 机炮冲锋：冲锋完成判定 | `aircraft/aircraft_combat_tracking.gd:619` is_gun_pass_finished |
| 导弹发射主逻辑 | `aircraft/aircraft_weapons.gd:711` update_missile |
| 导弹阻断日志（被锁/RNG/能量等原因） | `aircraft.gd:2241` _log_msl_block |
| 齐射空手日志（auto_fire 实际值 + 各过滤踢除计数） | `aircraft.gd:2259` _log_salvo_skip |
| 单枚发射 | `aircraft/aircraft_weapons.gd:885` _fire_missile_at |
| 多目标齐射 | `aircraft/aircraft_weapons.gd:946` _fire_multi_lock_salvo |
| 最优目标选择（评分） | `aircraft.gd:2319` _select_best_missile_target |
| 射程包线检查 | `aircraft/aircraft_combat_tracking.gd:632` is_in_missile_envelope |
| 导弹阶段判定（接近/照射/保持） | `aircraft.gd:1819` _get_missile_phase |
| 是否应该用机炮 | `aircraft.gd:1846` _should_use_gun |
| Crank 状态查询 | `aircraft.gd:1857` is_cranking |
| 导弹射程（像素） | `aircraft.gd:1791` _missile_range_px |
| 有效导弹射程=min(导弹,雷达)像素 | `aircraft.gd:1801` _effective_missile_range_px |
| 有效射程（像素） | `aircraft.gd:1813` _effective_range_px |
| 导弹飞行物理+PN制导 | `missile.gd:105` _physics_process |
| 导弹低空制导衰减 | `missile.gd:566` _guidance_degradation |
| 导弹生成 | `missile_manager.gd:41` spawn_missile |
| 导弹命中检测+连锁弹头 | `missile_manager.gd:283` _physics_process |
| 在飞导弹查询 | `missile_manager.gd:157` has_active_missile_at |
| 近炸引信 AOE 生成 | `missile_manager.gd:436` _spawn_aoe |
| AOE 区域更新+伤害 | `missile_manager.gd:458` _update_aoe_zones |
| AOE 红圈渲染 | `missile_manager.gd:518` _draw |
| 弹跳目标查找 | `missile_manager.gd:663` _find_bounce_target |

## 热诱弹/反制

| 功能 | 位置 |
|------|------|
| 热诱弹系统更新（含失误判定） | `aircraft/aircraft_flares.gd:52` update |
| 释放热诱弹（target_missile 可选，针对性释放）| `aircraft/aircraft_flares.gd:230` release |
| 干扰成功率计算 | `aircraft/aircraft_flares.gd:476` calc_jam_chance |
| 粒子更新 | `aircraft/aircraft_flares.gd:509` _update_particles |
| 失误概率 / 对头减免（FlareParams 字段） | `flare_params.gd:19-22` fail_chance / head_on_fail_reduction |
| 规避态（底层 evasion_mode：导弹来袭 S 型 + 降高度；AI 自保 + 加力模式共用的底座）| `aircraft.gd:1992` _update_evasion |
| 规避态开关（调用方：AI 自保 enter_evade / 玩家 E 键经 AfterburnerCharge.toggle） | `aircraft.gd:1881` set_evasion_mode |
| 加力模式充能资源（充能制：有能量即开/耗尽自动关/再按关闭，spec afterburner-mode） | `survivor/afterburner_charge.gd:54` toggle |
| 加力标志（全队强 buff，生存层写入） | `aircraft.gd:571` afterburner_window_active |
| 加力机炮 100% 闪避（绕 dodge cap 短路） | `aircraft.gd:2516` effective_dodge |
| 加力滚转甩导弹（90% → is_flare_jammed） | `missile_manager.gd:365` AB_MISSILE_DODGE |
| 加力速度地板 + 加速 ×3 | `aircraft/aircraft_physics.gd:536` AB_WINDOW_ACCEL_MULT |
| 加力充能条 + 按钮三态刷新 | `survivor/survivor_hud.gd:1009` _update_afterburner_ui |
| 眼镜蛇机动模块 | `cobra_maneuver.gd` CobraManeuver（挂载到 Aircraft 子节点） |
| 眼镜蛇机动激活 | `cobra_maneuver.gd` activate |
| 战术机动查询（通用） | `aircraft.gd` get_maneuver |
| AI 控制器查询 | `aircraft.gd` _get_ai_controller |
| 眼镜蛇后方判定（AI） | `ai_controller.gd` _is_missile_from_rear |
| 锁定免疫检查 | `aircraft.gd:2983` is_lock_immune |

## 伤害与击毁

| 功能 | 位置 |
|------|------|
| 受伤（导弹） | `aircraft.gd:2437` take_damage |
| 受伤（机炮，含闪避） | `aircraft.gd:2489` take_bullet_damage |
| 内部伤害应用 | `aircraft.gd:2581` _apply_damage |
| └ 敌方护卫反应（被护送对象挨打 → 护卫扑攻击者） | `aircraft.gd:2730` _alert_escort_guards（`acquire_target(attacker, TS_DIRECTIVE, "escort_alert")`）|
| └ 护卫名单字段 | `aircraft.gd:273` escort_guards（登记方 `survivor/survivor_spawner.gd:1517` _spawn_flee_escort）|
| 地面撞击检查 | `aircraft.gd:2760` _check_ground_crash |
| 击毁流程 | `aircraft.gd:2770` _start_destroy |
| 坠落动画 | `aircraft.gd:2777` _update_destroy |
| 基类伤害 | `combat_unit.gd:221` take_damage |

## 雷达系统

| 功能 | 位置 |
|------|------|
| 雷达锥判定（飞机） | `aircraft.gd:2816` is_in_radar_cone |
| 雷达锥判定（地面单位） | `ground_unit.gd:247` is_in_radar_cone |
| 雷达锥判定（SAM，360°） | `sam_unit.gd:80` is_in_radar_cone |
| 全局锁定计算循环 | `main.gd:198` _update_radar_locks |
| 低空锁定速率衰减 | `main.gd:296` _lock_rate_for_target（静态方法） |
| 雷达数据链共享 | `radar_station.gd:35` _update_datalink |

## AI 控制器

| 功能 | 位置 |
|------|------|
| AI 主循环 | `ai_controller.gd:649` _physics_process |
| └ 写入 aircraft.tactical_aggression（effective_skill×aggression）| `ai_controller.gd:200` |
| 有效技能（压力衰减） | `ai_controller.gd:1103` _effective_skill |
| 压力更新 | `pilot_personality.gd:131` update_stress |
| 漂移/判断失误 | `pilot_personality.gd:188` update_drift |
| Simple AI（UAV用） | `ai_controller.gd:1285` _process_simple |
| └ 护驾长机失效检测（Sentinel 坠毁）| `ai_controller.gd:384-390` |
| └ 绕长机飞行分支（orbit_squad_leader）| `ai_controller.gd:397` |
| └ 护驾战斗脱离（tether check）| `ai_controller.gd:436-451` |
| Simple AI 交战 | `ai_controller.gd:1829` _try_engage_simple |
| └ 护驾过滤（目标必须在 tether 内）| `ai_controller.gd:530-536` |
| orbit_squad_leader 导出变量 | `ai_controller.gd:59` |
| 绕长机飞行常量 | `ai_controller.gd:66-69` ORBIT_RADIUS=400/ANGULAR_SPEED=0.22/SPEED_RATIO=0.85/TETHER=550 |
| 巡逻逻辑 | `ai_controller.gd:1885` _process_patrol |
| 编队跟随逻辑 | `ai/squad_coordination.gd:28` process_squad_follow |
| └ 协同攻击触发（反应延迟） | `ai_controller.gd:639` 块内 |
| 掩护扫描（队友后方） | `ai/squad_coordination.gd:330` scan_leader_rear |
| BVR 狙击模式（F-47 专用） | `ai_controller.gd` bvr_only 标志 → _process_engage 距离检查 + _choose_tactic 过滤 |
| BVR 被追 → Herbst 触发 | `ai_controller.gd` _process_engage 内 bvr_only 分支：后半球检测 + get_herbst().activate() |
| 协同齐射广播 | `ai_controller.gd` broadcast_salvo + process_salvo |
| 赫尔贝特轮机动 | `herbst_maneuver.gd` HerbstManeuver（DECEL→TURN 180°→ACCEL，15s 冷却，可重复） |
| 光学隐形（F-47） | `aircraft.gd` is_cloaked / _cloak_alpha → _draw() 淡出 + is_lock_immune() + missile.gd 丢失制导 |
| └ 隐形索敌过滤（各通路） | `ai_controller.gd` _current_target 失效判定 / _try_engage_simple / _try_engage_in_tether_range / 神风扫描；`ai/squad_coordination.gd` scan_squad_nearby_enemy + scan_leader_rear；`ai/target_selection.gd` disengage BOSS 再交战；`aircraft/aircraft_weapons.gd` update_secondary_radar；`aa_gun_unit.gd` 扫描 |
| **交战速度治理**（绕圈死结） | `ai/tactical/engagement_speed_governor.gd` EngagementSpeedGovernor — `R = V²/(g√(n²−1))` 反解速度上限，地板=角点速度；接线在 `aircraft.gd` `TacticalPlanner.plan()` 之后一行；`Situation.max_g` 为其新增字段（经 `effective_max_g()` 注入） |
| └ 治理回归测试 | `tests/test_speed_governor.gd`（`--bench=speed_governor`，14 断言：7 公式 + 7 裸物理步进 sim 对照） |
| └ **减速迟滞**（王牌执行失误） | `ai/tactical/engagement_speed_governor.gd` `apply_with_lag()` — 每次新进入治理区掷一次骰，25% 概率延迟 0.6~1.2s 才压速 → 冲过头。状态 `_ace_decel_lag_latched` / `_ace_decel_lag_timer` 在 `aircraft.gd`（spec wraith-squadron §2.4） |
| **BOSS 猎手准则** | `events/boss_encounter_event.gd` — INBOUND 相下 `PURSUE_UNIT(player)` 追玩家实时位置；接战触发器四条（T1 进圈 / T2 贴近 / **T3 被锁定** / **T4 受伤**）；出生点 = 玩家机头前方 ±30° 扇面 12km；BOSS 圈中心同步存活成员质心（spec boss-hunter-doctrine） |
| └ 猎手指令 verb | `events/ai_directive.gd` `PURSUE_UNIT` + `pursue(target, refresh_interval)`；执行分支 `ai_controller.gd` `_directive_pursue_unit_step`（0.5s 重取、**无抵达态**、目标失效自动释放） |
| └ 玩家引用重定向契约 | `survivor/boss_encounter.gd` `set_player_ref()` 基类虚方法；三子类各自覆写（`ace_squad.gd` / `carrier_strike_group.gd` → 转发 Poltergeist / `mother_goose_boss.gd` → 转发 controller → `ai/swarm/swarm_director.gd`）。SEAM-019 同类，猎手模型下是急性病 |
| └ 母舰巡逻环跟随玩家 | `survivor/mother_goose_boss.gd` `_patrol_center()` / `_update_patrol_follow()` — 环心=玩家实时位置，2s 重算、位移 <800px 不重下航点 |
| └ CSG 舰载机目标指派 | `survivor/carrier_strike_group.gd` `_assign_player_target()` — F/A-18 弹射即挂玩家（`acquire_target(TS_BOSS)`），舰船不猎手（物理追不动） |
| └ CSG 舰队摆位地形校验（护卫舰不落陆地） | `survivor/carrier_strike_group.gd:397` _pick_water_placement（候选朝向 × 锚点偏移取落地最少解，结果写 EventLogger，仍落地则 push_warning） |
| └ 落地点计分（CV 巡逻两端 + 10 个护卫位） | `survivor/carrier_strike_group.gd:382` _score_placement |
| └ 候选枚举常量 | `survivor/carrier_strike_group.gd:374` PLACEMENT_HEADING_STEP_DEG / `survivor/carrier_strike_group.gd:376` PLACEMENT_ANCHOR_NUDGES |
| └ 猎手回归测试 | `tests/test_boss_hunter.gd`（`--bench=boss_hunter`，60 断言：PURSUE_UNIT 执行分支/无归巢/KNIGHT-SNIPER 角色/死 meta 清除/热诱弹 4 命/瞄准误差开门/减速迟滞） |
| **WRAITH 队级战术状态机** | `survivor/wraith_tactics.gd` WraithTactics — PERCH（爬到玩家+2000m 档 / 1500m 差或 12s）→ BRACKET（BAIT 不开火拉到玩家机头前 3000m，三翼 ≥60° 离轴切入，咬住 4s 收网或 20s）→ PRESS（15s 完全放手 BFM）→ RESET（8s 脱离 3000m+爬升）→ 回 PERCH；退化检测 0.5s 采样、均值 >50° 持续 6s 强制 RESET。**Wraith 专属窄井**（spec wraith-squadron §2.3/§3.1~3.4） |
| └ 战术层钩子 | `survivor/ace_squad.gd` `_tactics_enter/_tactics_update/_tactics_exit` 三个空虚方法（基类不含 Wraith 逻辑）；`survivor/f47_ace_squad.gd` 持有 `tactics` 并转发 |
| └ 包夹的执行端 | 复用命令轮盘的包围轴：`ai/tactical/tactical_planner.gd` `_apply_surround_axis`（>1500m 飞自己扇区的进入门点、近了解除偏置收敛，**真实转弯不挪坐标**）；`ai/tactical/situation.gd` 读取门为 tier=ace 开窄口（敌机没有 commanded_target） |
| └ 战术层纯函数（可单测） | `wraith_tactics.gd` `pick_bait()` / `wing_bearings()` / `axis_heading()`（**heading 约定 0=北**，与 surround_bearing 消费端同源）/ `is_biting()` / `average_nose_off_deg()` / `perch_tier_for()` |
| **POLTERGEIST 队级战术**（死锁换手） | `survivor/poltergeist_tactics.gd` PoltergeistTactics — 共速绕圈死锁（机头偏角 >55° 持续 4s、距玩家 ≤4000m）→ 只派**最咬不住的 1 架**爬升 HIGH + 背离拉开 2200m 重整 3.5s、其余继续压（**同时换手上限=1**=灵魂）。与 `EngagementSpeedGovernor` 互补（治理修速度几何、本层修"谁也咬不住"死锁）。接线在 `poltergeist_squad.gd` `_tactics_*` 钩子。**Poltergeist 专属**，区别于 Wraith 全队 RESET（spec bosses/poltergeist-squadron） |
| └ 死锁换手回归测试 | `tests/test_poltergeist_tactics.gd`（`--bench=poltergeist_tactics`，9 断言：4 纯几何 + 5 换手/上限/排除 sim） |
| └ 战术层纯函数（可单测） | `poltergeist_tactics.gd` `nose_off_deg()`（单机对某点机头偏角，heading 0=北） |
| **王牌角色** KNIGHT / SNIPER | `survivor/ace_squad.gd` `AceRole{NONE,KNIGHT,SNIPER}` + `ROLE_META` + `role_of()` + `_apply_role()` — 前 2 架 KNIGHT（机炮 / `bvr_only=false` 转身对抗），后 2 架 SNIPER（导弹 / `bvr_only=true` 站位带 4~6km）。取代 `combat_specialty`（只写不读）与 `f47_role`（只读不写）两个死 meta |
| └ 角色消费点 | `ai_controller.gd` `is_boss_attacker()` 兜底改读角色 meta；`survivor/survivor_hud.gd` 状态标签 CLOSE/STRIKE（**只显示行为，不暴露角色代号**） |
| **机炮瞄准误差开关** | `aircraft.gd` `gun_aim_error_enabled`（从 `use_tactical_preference` 拆出——那是操控模式标志，兼任导致**全部 AI 敌机零瞄准误差**）；两处门在 `aircraft/aircraft_weapons.gd`；王牌由 `survivor/ace_tier.gd` `mark()` 开启 + 写 `pilot_aim_skill=0.85`（→ ±1.2°） |
| **王牌中队 tier 语义** | `survivor/ace_tier.gd` AceTier — 成员判定 is_ace_type / 打标 mark / 查询 is_ace / 缩放豁免 no_scale / HP cap 豁免 exempt_from_hp_cap / 血量 apply_hp |
| └ tier 回归测试 | `tests/test_ace_tier.gd`（`--bench=ace_tier`，42 断言：成员/缩放/HP cap/残血保证/打标/profile 表/呼号保留/留档） |
| **王牌编成 profile 注册表** | `survivor/ace_squad_profiles.gd` AceSquadProfiles — 六队单点登记（编成/elements 混编/装备/战术/阵型/包装五件套/时段档）+ `pool_at` 调度池 + `reserve_callsigns`。**加新王牌中队 = 本表加一行** |
| └ 非 BOSS 王牌编成（profile 驱动） | `survivor/ace_support_squad.gd` AceSupportSquad — element 解析 `_element_of/_member_type/_member_role` + 装备覆写 + `ace_tactics_owned`/`ace_evader` meta 打标 + `is_ammo_dry` |
| └ 骑士掠袭战术 | `survivor/lancer_squad_tactics.gd` LancerSquadTactics — CHARGE→VOLLEY→EXTEND 三态机 + `assign_targets` round-robin 分配；只管 `ace_tactics_owned` 成员 |
| └ 王牌事件（横幅退役→无线电/血条/留档/弹尽撤离） | `events/ace_reinforcement_event.gd` — `battle_bar_info()` HUD 数据源 / `active_codename` / `_detect_battle_joined` |
| └ 宿敌 ORION | `events/orion_nemesis_event.gd` OrionNemesisEvent — 独立轨道调度（survivor_mode `_update_orion_event`）+ 成长档位表 `tier_for`/机号 `designation` + 生涯计数（CareerArchive `get_orion_kills`） |
| └ 王牌/宿敌回归测试 | `tests/test_lancer_squad.gd`（`--bench=lancer_squad`，39 断言：profile/分配/混编解析/ORION 档位/真物理掠袭 sim） |
| └ 眼镜蛇王牌分层门 | `cobra_maneuver.gd` `activate()` — `AceTier.is_ace && flares>0 → 拒绝`（flare 耗尽后解锁，tier §3.4） |
| └ 王牌线框徽章 | `meta/ace_emblem_icon.gd` AceEmblemIcon — 六队几何图形（血条代号旁 + 图鉴页）；静态绘制仅变更时重画 |
| **敌人图鉴**（spec career-archive §2.6） | `meta/enemy_codex.gd` EnemyCodex — 34 条目注册表 + 5 分组 + 计数分派 + 完成度。**加新敌人在此加一行** |
| **游戏信息手册**（spec career-archive §2.7） | `meta/game_info_codex.gd` GameInfoCodex — 7 分组 47 条机制说明；`tip` 字段复用 `tactical_map._TIP_KEYS` 译文（单一数据源）。**加机制说明在此加一行** |
| └ 资料库页面（两分类页签） | `meta/archive_ui.gd` + `scenes/archive.tscn` — 主菜单入口；敌人图鉴走击败解锁制（0 杀 = 剪影 "???"），游戏信息全文开放 |
| └ 机型标识唯一源 | `survivor/survivor_spawner.gd` `type_tag_of()` / `all_type_tags()`（enemy_type meta / 档案键 / 无线电白名单 / 图鉴共用） |
| └ 逐型地面计数 | `meta/career_archive.gd` `record_ground_kill(tag)` / `get_ground_kills_by_type()`（sam/aa/radar） |
| └ tier 调用点 | `survivor/survivor_spawner.gd` 缩放块 + `_create_enemy` 末尾打标；`survivor/survivor_mode.gd` 离屏冻结 + 预算排队两处 LOD 豁免 |
| 王牌中队基类 | `survivor/ace_squad.gd` AceSquad — 通用飞机类 BOSS 框架（角色分配/隐形/force_engage） |
| F-47 王牌小队 | `survivor/f47_ace_squad.gd` F47AceSquad extends AceSquad — 具体战斗参数 + 齐射（Herbst 已转移到 F-14） |
| F-47 隐形系统 | `ace_squad.gd` _cloak_enter / _cloak_update / _cloak_exit — 110s 基础 CD + 0~25s 抖动 / 5.5s 隐形 / 0.5s 淡入淡出 |
| 交战主逻辑 | `ai_controller.gd:1939` _process_engage |
| └ 长机目标丢失宽限（防抖动） | `ai_controller.gd:748` |
| └ 长机目标超射程宽限 | `ai_controller.gd:764` |
| 态势分析数据 | `ai/bfm_tactics.gd:24` assess_situation |
| Lufberry 检测 | `ai/bfm_tactics.gd:78` update_lufberry_detection |
| 战术选择决策树 | `ai/bfm_tactics.gd:107` choose_tactic |
| 应用新战术 | `ai/bfm_tactics.gd:252` apply_new_tactic |
| 判断失误（低技术） | `ai/bfm_tactics.gd:296` make_mistake |
| 前置追踪执行 | `ai/bfm_tactics.gd:328` execute_lead_pursuit |
| 滞后追踪执行 | `ai/bfm_tactics.gd:346` execute_lag_pursuit |
| 提前转弯执行 | `ai/bfm_tactics.gd:359` execute_lead_turn |
| 高悠悠执行 | `ai/bfm_tactics.gd:377` execute_high_yoyo |
| 低悠悠执行 | `ai/bfm_tactics.gd:421` execute_low_yoyo |
| 急转防御执行 | `ai/bfm_tactics.gd:466` execute_break_turn |
| 加速脱离执行 | `ai/bfm_tactics.gd:508` execute_extension |
| 剪刀机动执行 | `ai/bfm_tactics.gd:551` execute_scissors |
| 导弹规避流程 | `ai/missile_evasion.gd:30` process_evade |
| 进入规避 | `ai/missile_evasion.gd:91` enter_evade |
| 退出规避 | `ai/missile_evasion.gd:134` exit_evade |
| 尝试进入交战（含引力交战地板） | `ai/target_selection.gd` try_engage |
| 目标重评估（含引力地板脱离 ×2） | `ai/target_selection.gd` reevaluate_target |
| 脱离交战（重置宽限计时器） | `ai/target_selection.gd` disengage |
| 战场引力上下文（三带判据/引力曲线/交战地板/可行性门常量） | `ai/objective_context.gd` 全模块（spec battlefield-gravity；生存模式填充在 `survivor/survivor_mode.gd` _update_objective_context） |
| 来袭导弹检查 | `ai/missile_evasion.gd` check_incoming_missile / find_nearest_incoming_missile |
| 规避入口分层门（flare 优先不脱队） | `ai/missile_evasion.gd` should_enter_evade（B1，2026-07-03） |
| 控制意图仲裁（pursuit/speed/AB 写入权收口） | `aircraft/control_intent.gd` + `aircraft.gd` submit_intent/_resolve_intents（Phase 1，2026-07-04） |
| 编队宽限常量 | `ai_controller.gd:72-75` LEADER_TARGET_LOST_GRACE / SQUAD_RANGE_GRACE |

## 编队系统

| 功能 | 位置 |
|------|------|
| 阵型偏移计算 | `squad.gd:122` get_formation_offset |
| 僚机世界坐标 | `squad.gd:185` get_wingman_target |
| 阵型循环 | `squad.gd:217` cycle_formation |
| 生成友方编队 | `main.gd:320` _spawn_friendly_squad |
| 生成敌方编队 | `main.gd:364` _spawn_enemies |
| 护卫学说开关字段 | `squad.gd` escort_doctrine_enabled（玩家队/F-47/Mother Goose 建队 on，杂兵 off） |
| 护卫僚机判定 / 目标加权 | `ai/squad_coordination.gd` is_escort_wingman / escort_target_bonus（咬长机+近长机加权，squad-ai-escort） |
| engaging_me 维护范围（反向索引） | `ai_controller.gd` _maintains_engaging_me（team0 OR 护卫编队）+ _physics_process_impl 差量同步 |
| 护卫评分常量 | `ai_controller.gd` ATTACKING_LEADER_BONUS / LEADER_PROXIMITY_BONUS_MAX |
| 交战模式（三态 FREE/FOLLOW_LEADER/GUARD_REAR） | `ai_controller.gd` squad_engage_mode（默认 FOLLOW_LEADER）+ `survivor_hud.gd` 交战模式按钮三态循环 + `_squad_engage_mode_label`（squad-cohesion） |
| 守护后方模式 / 自主交战入口 | `ai/squad_coordination.gd` process_squad_follow GUARD_REAR 分支 + `_enter_autonomous_engage` + `_guard_rear_tick`（空中 scan_leader_rear → 否则地面 scan_leader_threat_ground）（squad-cohesion §2.1） |
| 守护者打地面 AA / 守后紧 leash | `ai/squad_coordination.gd` `scan_leader_threat_ground`（SAM/AAA 导弹远射）；`ai_controller.gd` `effective_squad_leash()`（REAR_GUARD_LEASH_DIST=1200 守后紧、打地面放宽 1800）+ REAR_GUARD_RANGE=900 |
| 战场引力 leash 松绑（生存 4200px 锚操控机 / objective 重锚 / 旧行为三态） | `ai_controller.gd` `leash_anchor_and_limit()`（_apply_constraints 消费，spec battlefield-gravity §3.4） |
| 生存层主动回防（操控机被咬 → 僚机反咬，≤2 机） | `ai/squad_coordination.gd` `try_defend_protectee` + `_count_defenders`（SQUAD_FOLLOW 常开 1Hz，spec battlefield-gravity §3.3） |
| 自由机互掩（双重攻击学说） | `ai/squad_coordination.gd` `_should_be_free_fighter`（FOLLOW_LEADER 打飞机非 BOSS+≥2僚机→最高号机守后）+ `_is_boss_target`（squad-cohesion 阶段3） |
| 战术=阵型绑定 / 阵型映射 | `squad.gd` formation_for_engage_mode（自由→Spread/跟随→FingerFour/守后→Wedge）；切模式时 `survivor_hud._on_squad_engage_pressed` 设 sq.formation（玩家手动切阵型已废弃：删按钮 + KEY_5） |
| 敌方随机阵型 | `squad.gd` random_formation（除 Trail）；`survivor_spawner._spawn_squad` 杂鱼登场随机；精英/Boss 建队显式固定 |
| 自由交战搜索范围 | `ai_controller.gd` SQUAD_FREE_SCAN_RANGE=800px（自由交战只接管靠近敌机） |
| 小队防游走 leash | `ai_controller.gd` _process_engage 僚机越界 break-off（SQUAD_LEASH_DIST=1800/HYSTERESIS=0.5，squad-cohesion §3.2） |

## 地面单位

| 功能 | 位置 |
|------|------|
| 地面单位移动 | `ground_unit.gd:67` _update_movement |
| 地面自动目标选择 | `ground_unit.gd:109` _update_target_selection |
| 地面机炮战斗 | `ground_unit.gd:135` _update_combat |
| 地面机炮射击 | `ground_unit.gd:168` _update_gun |
| SAM 导弹发射 | `sam_unit.gd:26` _update_sam_missile |
| AA 炮塔转向 | `aa_gun_unit.gd:74` _update_turret |
| AA 目标选择（最近） | `aa_gun_unit.gd:30` _update_aa_target_selection |
| 雷达站数据链 | `radar_station.gd:35` _update_datalink |
| 车队管理 | `ground_convoy.gd:12` add_member |

## 海上单位 / 船伤害路由

| 功能 | 位置 |
|------|------|
| NavalUnit 物理主循环（含状态 tick） | `scripts/naval/naval_unit.gd:159` _physics_process |
| 位置感知伤害入口（双池：部件 + hull）| `scripts/naval/naval_unit.gd:464` take_damage_at |
| 状态过滤（船只接受 JAM）| `scripts/naval/naval_unit.gd:516` apply_status |
| 弱点暴露判定 | `scripts/naval/naval_unit.gd:522` _check_weak_point_reveal |
| 武器派发（JAM 早返）| `scripts/naval/naval_weapons.gd:51` update |
| 子弹命中船（机炮 hull 0.15× / 弱点可磨）| `scripts/bullet_manager.gd:648` 命中循环 NavalUnit 分支 |
| 火箭弹命中船（hull 0.5× / 可磨弱点）| `scripts/bullet_manager.gd:636` 同上 is_rocket 分支 |
| 火箭弹 AOE 命中船 | `bullet_manager.gd:408` _explode_rocket |
| 导弹近炸 AOE 命中船（含 alt_ok 例外）| `missile_manager.gd:458` _update_aoe_zones |
| 电磁炮命中船按母舰归并（船体 + MountTarget 代理同挂 all_units → 一发多次结算）| `equipment/railgun_equipment.gd:438` _apply_hitscan_damage |
| └ 伤害归属母舰（代理 → 母舰） | `equipment/railgun_equipment.gd:490` _naval_damage_sink |
| └ 沿弹道取最靠前命中点（一发一舰只结算一次） | `equipment/railgun_equipment.gd:500` _segment_param |

## 状态效果（StatusEffects）

| 功能 | 位置 |
|------|------|
| 状态常量（INVINCIBLE/STEALTH/BLOODLUST/OVERLOAD/JAM/SLOW/FEAR）| `scripts/status_effects.gd:11-22` |
| 通用 tick（倒计时 + 写 status_jam_active）| `scripts/status_effects.gd:103` tick |
| Aircraft 专用 update（所有派生标记 + 副作用）| `scripts/status_effects.gd:124` update |
| Aircraft.apply_status 覆写（UAV 滤 FEAR / OVERLOAD 钩子）| `aircraft.gd:2370` apply_status |
| NavalUnit.apply_status 覆写（只接受 JAM）| `scripts/naval/naval_unit.gd:516` apply_status |
| AOE 状态广播（fear_applies_slow 联动）| `scripts/survivor/aoe_broadcast.gd` apply_status_in_radius |

## 生存模式

### survivor_mode.gd — 主控制器（~1450 行）

#### 初始化 & 常量
| 功能 | 位置 |
|------|------|
| 敌机类型枚举 EnemyType | `survivor_mode.gd:843` |
| 敌机参数基 preload | `survivor_mode.gd:104-112` |

#### 主循环
| 功能 | 位置 |
|------|------|
| 相机跟随插值 | `survivor/survivor_mode.gd:1801` _process |
| 物理主循环（总入口） | `survivor/survivor_mode.gd:1816` _physics_process |
| 选中列表清理 | `survivor/survivor_mode.gd:1925` _cleanup_references |
| 飞机列表同步 | `survivor/survivor_mode.gd:1932` _update_aircraft_list |

#### 雷达锁定
| 功能 | 位置 |
|------|------|
| 全局锁定计算 | `survivor/survivor_mode.gd:1987` _update_radar_locks |

#### 动态性能 / LOD / 清理
| 功能 | 位置 |
|------|------|
| FPS 采样与动态上限调整 | `survivor/survivor_spawner.gd:238` update_fps_sampling |
| 平均 FPS 查询 | `survivor/survivor_spawner.gd:245` _get_avg_fps |
| 屏幕外 AI/物理降频 | `survivor/survivor_mode.gd:2301` _update_offscreen_lod |
| 已坠毁敌机清理 | `survivor/survivor_mode.gd:2437` _cleanup_destroyed_enemies |
| 远距清理（释放 Token） | `survivor/survivor_spawner.gd:2384` _update_far_cleanup |

#### 猎手系统
| 功能 | 位置 |
|------|------|
| 猎手指派主循环 | `survivor/survivor_spawner.gd:2466` _update_hunters |
| 空闲敌机航点围绕玩家 | `survivor/survivor_spawner.gd:2611` _update_enemy_waypoints |
| 获取 AI 控制器 | `survivor/survivor_mode.gd:2444` _get_ai |
| 导弹上限查询（飞向玩家数）| `survivor/survivor_mode.gd:2591` _count_missiles_targeting_player |
| 筛选未发射敌机 | `survivor/survivor_mode.gd:2600` _get_enemies_without_active_missile_at_player |
| 敌人数统计 | `survivor/survivor_spawner.gd:2834` _count_enemies |

#### 刷怪 & Token 烈度控制
| 功能 | 位置 |
|------|------|
| 刷怪主逻辑（每波间隔/FPS闸/Token 预算）| `survivor/survivor_spawner.gd:452` _update_spawner |
| 当前 Token 预算（随等级增长）| `survivor/survivor_spawner.gd:275` _get_token_budget |
| 重算场景 Token 占用 & 每类数量 | `survivor/survivor_spawner.gd:286` _recalc_token_usage |
| 指定类型是否可生成（预算+实例上限）| `survivor/survivor_spawner.gd:298` _can_spawn_type |
| 按等级选敌机类型（概率 + Token 约束）| `survivor/survivor_spawner.gd:309` _pick_enemy_type |
| └ BOSS/事件专属机型排除（后期随机桶，F-47 / F-14 Poltergeist）| `survivor/survivor_spawner.gd:423` BOSS_ONLY_TYPES（表在 `survivor/survivor_data.gd:2779` BOSS_ONLY_TYPES）|
| 敌人作战高度分档（按机型查权重表，替代均匀 1/3 随机）| `survivor/survivor_spawner.gd:1985` pick_altitude_tier → `survivor/survivor_data.gd:2785` ENEMY_ALTITUDE_WEIGHTS + `survivor/survivor_data.gd:2820` pick_altitude_tier |
| └ 巡逻高度跟随抽到的档（经 Situation.combat_altitude_m 影响战术层交战高度）| `survivor/survivor_spawner.gd:1996` patrol_altitude_for_tier → `survivor/survivor_data.gd:2809` TIER_PATROL_ALTITUDE + `survivor/survivor_data.gd:2815` patrol_altitude_for_tier |
| AF-03 解锁/概率常量（旅途随机池入口） | `survivor/survivor_data.gd:2657` AF03_UNLOCK_LEVEL |
| AF-03 战区池入口（type 17 行） | `survivor/survivor_data.gd:2989` ZONE_ENEMY_TABLE |
| 单机生成（J-7 / MiG-31 / F-4E 35%）| `survivor/survivor_spawner.gd:1038` _spawn_single |
| 编队生成（MiG-29 / F-86 / MiG-23 / F-100 / A-7 / Q-5 / MQ-109 / MQ-110 / F-4E）| `survivor/survivor_spawner.gd:1057` _spawn_squad |
| 指挥 UAV 小队生成（Sentinel + MQ-109 僚机）| `survivor/survivor_spawner.gd:1117` _spawn_commander_squad |
| F-47 BOSS 小队生成（菱形 4 架 + 登场通场） | `survivor_mode.gd` _spawn_f47_squad |
| F-47 BOSS 狙击循环更新（站位/撤退/全灭检测）| `survivor_mode.gd` _update_f47_squad |
| 创建敌机实体（参数/AI/缩放/Token meta）| `survivor/survivor_spawner.gd:1721` _create_enemy |
| └ base_params match（**新增敌人改这里**） | `:1041` |
| └ enemy_scale 适用判定 | `:1075` |
| └ no_stamina 排除 | `:1103` |
| └ type_tag 映射 | `:1108` |
| └ AI 分支（**F86:1183 / MIG31:1195 / MIG23:1208 / F100:1220 / Sentinel:1233**） | `:1157-1244` |
| 无效分队清理 | `survivor/survivor_spawner.gd:2865` _cleanup_squads |

> **敌人类型与 archetype 映射**（EnemyType enum + 适用 archetype）：
> - `UAV(0)` MQ-109（机炮）/ `UCAV(1)` MQ-110（导弹）— 无人机杂鱼，1 级一起开局，等权重 50/50
> - `F4E(23)` F-4E — 前期导弹杂鱼（有人机，无机炮），Lv1~6 单机/小队（spec enemies/f-4e）
> - `MIG(2)` MiG-29 — 主力威胁，全能 BFM
> - `INTERCEPTOR(3)` J-7 — Lancer 入门款（轻量、单机）
> - `UAV_COMMANDER(4)` Sentinel — Schemer 唯一单位
> - `F86(5)` F-86 — Gladiator 入门款（机炮+火箭弹编队）
> - `MIG31(6)` MiG-31 — Lancer 顶级（极速 3200 / 雷达弹 / 单机精英）
> - `MIG23(7)` MiG-23 — Gladiator 综合款（导弹+机炮编队）
> - `F100(8)` F-100 — Lancer 中量编队（雷达弹打带跑）
> - `SU27(9)` Su-27 — Gladiator+眼镜蛇（单机精英）
> - `A7(10)` A-7 — Lancer 亚音速攻击机（M61火神炮+祖尼火箭弹编队）
> - `Q5(11)` Q-5 — Lancer 超音速攻击机（23mm双炮+57mm火箭弹编队）
> - `F47(15)` F-47 — BOSS 王牌狙击小队（BVR 协同齐射 / bvr_only + salvo_leader）

> Token 常量表：`survivor_data.gd::TOKEN_COST` / `TOKEN_INSTANCE_CAP` / `TOKEN_BUDGET_BASE/PER_LEVEL/MAX` / `FAR_CLEANUP_DISTANCE` / `FAR_CLEANUP_INTERVAL`。设计要点：
> - 每种敌人有 Token 成本（弱 1~2，精英 4~6）与可选实例上限（Sentinel=1，J-7=2）。
> - 全局 Token 预算随等级线性增长；用来精细控制同屏战斗烈度。
> - `_update_spawner` 每 tick 重算 `_token_used`，基于场景真实状态。
> - `_update_far_cleanup` 定期静默移除离玩家 > FAR_CLEANUP_DISTANCE 的敌机，不给经验（防止养肥刷怪），自然释放 Token。

#### 击杀/经验/升级
| 功能 | 位置 |
|------|------|
| 击杀检测 & 经验奖励 & 回血（×xp_mult×sig×机体 xp_gain_mult）| `survivor/survivor_spawner.gd:2660` _detect_kills |
| 玩家升级回调（暂停+弹选项）| `survivor/survivor_mode.gd:2704` _on_player_leveled_up |
| 升级选中回调（应用+进化判定）| `survivor/survivor_mode.gd:3106` _on_upgrade_selected |
| 玩家死亡 | `survivor/survivor_mode.gd:3175` _on_player_died |

#### 生涯档案（spec career-archive，2026-07-26）
| 功能 | 位置 |
|------|------|
| 档案 AutoLoad（schema/记录 API/成就/写盘） | `meta/career_archive.gd` 全文件 |
| 入档守卫（bench/boss_debug 排除） | `survivor/survivor_mode.gd:3960` archive_enabled |
| 空中击坠入档（归因过滤+enemy_type 键） | `survivor/survivor_spawner.gd:2660` _detect_kills（空中/地面两分支各一处 record 调用） |
| 停机计数 | `survivor/survivor_mode.gd:3880` _on_dock_docked 头部 |
| BOSS 接战/击败入档 | `survivor/survivor_mode.gd:4066` on_boss_engaged / `:4137` on_boss_victory |
| BOSS 轮换 history 注入 | `survivor/survivor_mode.gd:4041` _update_boss_phase → `events/boss_encounter_event.gd:74` _start |
| 轮换算法（纯函数） | `survivor/boss_registry.gd:65` pick_for_map / `:95` pick_by_rotation / `:107` rotation_candidates |
| 结算面板 BOSS 名（"XX 已被击毁"） | `survivor/boss_registry.gd:43` name_key_for → `survivor/survivor_hud.gd:1597` show_victory（boss_id 空 → 通用文案） |
| 忠诚僚机奖池门控 | `survivor/zone_data.gd:604` _assign_reward（门控在武器子池过滤段）+ `survivor/survivor_mode.gd:3947` _build_reward_roll_context |
| 成就 toast | `survivor/survivor_mode.gd:3965` _on_achievement_unlocked |
| 删存档登记 | `main_menu.gd:365` _on_reset_save_pressed 内 CareerArchive.debug_reset |

#### 生涯商店与起手解锁（spec career-shop，2026-07-26）
| 功能 | 位置 |
|------|------|
| 商店账本（目录/判定/购买） | `meta/meta_shop.gd` 全文件 |
| 商店界面 | `meta/meta_shop_ui.gd` + `scenes/meta_shop.tscn`；主菜单入口 `main_menu.gd` _build_ui 模式按钮区 |
| 起手机门控 | `survivor/survivor_select.gd` _effective_list / _unlock_hint_for（boss debug 放行） |
| 停靠送僚机门控 + 首停上新 toast | `survivor/survivor_mode.gd:3880` _on_dock_docked 内 |
| 战区时长 +30s 注入 | `survivor/survivor_mode.gd` _ready 内（WARZONE_PHASE_DURATION 已 const→var） |

#### 噪声/绘制
| 功能 | 位置 |
|------|------|
| 地形噪声初始化 | `terrain_renderer.gd:61` _init_noise |
| 主 _draw 入口 | `terrain_renderer.gd:76` _draw |
| 地形类型判定 | `terrain_renderer.gd:83` _get_terrain_type |
| 地形单元绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 网格绘制 | `terrain_renderer.gd:162` _draw_grid |

### pause_menu.gd — 暂停菜单（spec pause-menu，2026-07-28）

| 功能 | 位置 |
|------|------|
| ESC 分流（开面板 / 结算态直退 / 选卡中不响应） | `survivor/survivor_mode.gd:1429` _unhandled_input |
| 创建 + 接线（bench 跳过） | `survivor/survivor_mode.gd:496` |
| 确认退出回调（不结算功勋） | `survivor/survivor_mode.gd:3191` _on_pause_quit_to_menu |
| 退出序列（clear_all + stop_music + 切场景） | `survivor/survivor_mode.gd:3194` _quit_to_main_menu |
| 打开（hard_pause 走 panel_in） | `survivor/pause_menu.gd:54` open |
| 关闭＝继续作战（解暂停走 panel_out） | `survivor/pause_menu.gd:63` close |
| 面板构建 | `survivor/pause_menu.gd:82` _build_ui |
| 按钮回调 | `survivor/pause_menu.gd:176` _on_resume_pressed / `:180` _on_quit_pressed |

### survivor_player.gd — 玩家状态（127 行）

| 功能 | 位置 |
|------|------|
| 信号 leveled_up | `survivor_player.gd:7` |
| 经验累加/升级触发 | `survivor/survivor_player.gd:37` add_xp |
| 应用升级（修改 aircraft.params）| `survivor/survivor_player.gd:426` apply_upgrade |
| └ max_hp / missile_count / tracking | `survivor_player.gd:37-50` |
| └ gun_damage / multishot / ammo / regen / firerate | `survivor_player.gd:58-72` |
| └ radar_range / lock_time / speed / maneuver | `survivor_player.gd:73-85` |
| └ flare / kill_heal / dogfight | `survivor_player.gd:86-112`（⚠ `pilot_stamina` 分支已随耐力系统一并移除）|
| HP 查询 | `survivor/survivor_player.gd:892` get_hp |

### survivor_data.gd — 参数表（322 行）

| 功能 | 位置 |
|------|------|
| 升级定义表 UPGRADES（常量）| `survivor_data.gd:12` |
| 刷怪基础常量（BASE/MIN/SPAWN_DISTANCE，旅途位置已弃用）| `survivor_data.gd` 刷怪参数段 |
| 增援入场常量（INGRESS_*/ANCHOR_*/PATROL_RING_*/EGRESS_*/OPENING_GARRISON，spec reinforcement-ingress）| `survivor_data.gd` SPAWN_DISTANCE 之后 |
| 增援入场逻辑（边缘生成/锚点驻空/EGRESS/开局驻防 + 冻结豁免）| `survivor_spawner.gd` INGRESS 段 + `survivor_mode.gd` LOD 冻结块 reinforcement 分支 |
| 地图扩展无头回归（几何/陆地占比/BOSS 锚点/入场纯函数）| `scripts/tests/test_map_expansion.gd` |
| 60km 密度调优旋钮（战区规模/token/间隔/上限/hunter 配额，spec 60km-density-pass）| `survivor_data.gd`（ground_tgt_scale 含 radar_count / ZONE_DEFENDER_* / TOKEN_BUDGET_*）+ `survivor_spawner.gd` _update_hunters + `zone_data.gd` 半径 |
| 战区雷达站 TGT + 空战中队长机高一档 + 盘旋环随半径缩放 | `zone_mission.gd`（_RADAR_SCENE / _spawn_ground_garrison 尾段 / _spawn_air_squadron leader_etype·orbit_r / _spawn_zone_defenders garrison_r） |
| 教程轰炸机锚点（出生点前方派生，扩图安全）| `survivor/adbs_manager.gd` TUTORIAL_BOMBER_ANCHOR |
| 城区直升机全歼奖励（作战时间延长，与王牌中队全灭同一注入点 `grant_time_extension`）| `survivor/adbs_manager.gd:227` _award_city_heli_bonus |
| └ 战果轮询（与 _detect_kills 同模式；逃出地图被回收不算不阻塞）| `survivor/adbs_manager.gd:207` _track_city_heli_kills |
| └ 编队/击落计数状态 | `survivor/adbs_manager.gd:52` _city_heli_group / `survivor/adbs_manager.gd:53` _city_heli_killed |
| └ 奖励时长常量 | `survivor/adbs_manager.gd:41` CITY_HELI_TIME_BONUS_S |
| CH-47 受击散开（scatter_on_damage meta + flock_members 串联）| `survivor/survivor_spawner.gd:1589` spawn_heli_flee |
| 停靠结算（spec zone-reward-docking：DockPoint 组件/攻克全队满血+奖励入库/领奖分发）| `survivor/dock_point.gd` + `survivor_mode.gd`（_on_dock_docked / _claim_*）|
| 机场解放战区（spec airfield-liberation-zones：3 机场敌占→解放→一次性补给点+渐进 ALLY 防空；难度=热度）| `survivor/zone_data.gd`（AIRFIELD_IDS / is_airfield / liberate_airfield / set_airfield_difficulty）+ `zone_mission.gd`（_spawn_airfield_ground / _airfield_difficulty_from_heat）+ `survivor_mode.gd`（_liberate_airfield / _deploy_airfield_ally_gradual）|
| 战区三类奖励 roll（航母/僚机/武器 + carrier_uses_left）| `survivor/zone_data.gd` REWARD_KIND_WEIGHTS / _assign_reward |
| 战区奖励说明文案（Tab 面板奖励名下方一行；技能类=技能介绍）| `survivor/zone_data.gd` REWARD_WEAPON_DESC_KEYS / reward_desc_key + `tactical_map.gd` _refresh_info（reward_desc）+ i18n `REWARD_*_DESC` |
| 友军航母（南入北上/甲板 DockPoint/限 2 次/击沉清零）| `survivor_mode.gd` _summon_reward_carrier / _depart_friendly_carrier |
| 逃跑组护卫编队（adds 语义、普通 XP）| `survivor/survivor_spawner.gd` _spawn_flee_escort |
| Tab 停靠/奖励标记 | `survivor/tactical_map.gd` _draw_dock_markers + _draw_one_zone 奖励行 |
| 敌机上限常量（HARD/DEFAULT/MIN/TARGET_FPS）| `survivor_data.gd:215-218` |
| MiG 解锁/概率常量 | `survivor_data.gd:220-222` |
| 截击机 J-7 解锁/概率常量 | `survivor_data.gd:223-225` |
| F-86 解锁/概率常量 | `survivor_data.gd:226-228` |
| MiG-23 解锁/概率常量 | `survivor_data.gd:229-231` |
| F-100 解锁/概率常量 | `survivor_data.gd:232-234` |
| MiG-31 解锁/概率常量 | `survivor_data.gd:235-237` |
| Su-27 解锁/概率常量 | `survivor_data.gd:238-240` |
| A-7 解锁/概率常量 | `survivor_data.gd:241-243` |
| Q-5 解锁/概率常量 | `survivor_data.gd:244-246` |
| 指挥 UAV 解锁/概率/小队规模 | `survivor_data.gd:247-254` |
| **Token 预算常量** (BASE/PER_LEVEL/MAX) | `survivor_data.gd:254-256` |
| **Token 消耗表 TOKEN_COST** | `survivor_data.gd:261` |
| **Token 实例上限表 TOKEN_INSTANCE_CAP** | `survivor_data.gd:276` |
| **远距清理常量** (DISTANCE/INTERVAL) | `survivor_data.gd:289-290` |
| **后期分水岭 LATE_GAME_LEVEL** | `survivor_data.gd:296` |
| MiG/截击机缩放 enemy_scale_for_level | `survivor_data.gd` enemy_scale_for_level |
| UAV 缩放 uav_scale_for_level | `survivor_data.gd` uav_scale_for_level |
| 指挥机缩放 commander_scale_for_level | `survivor_data.gd` commander_scale_for_level |

### commander_aura.gd — 指挥 UAV 光环（230 行）

**设计要点**：
- 招募范围内的 UAV 加入小队（上限 MAX_WINGMEN=8 僚机）
- 可从**其它普通 UAV 编队中"挖人"**（检查 `ai.orbit_squad_leader` 排除其它指挥小队）
- 小队成员保持 `simple_ai=true`，通过 `orbit_squad_leader` 围绕 Sentinel 飞行
- **不再指派目标**（无 _designate_target）；僚机通过 `_try_engage_simple` 自主扫描并攻击靠近的敌方
- buff 聚焦机动/速度/攻击欲望（不加技能/冷静，simple_ai 用不上）
- buff 强度：+4G、+80% 滚转、+25% 速度、+100% 加速、-30% 失速（效果明显）

| 功能 | 位置 |
|------|------|
| 主循环（扫描+招募+buff） | `survivor/commander_aura.gd:44` _physics_process |
| 增益扫描（仅小队成员） | `commander_aura.gd:55` _scan_and_buff |
| 清理已毁 buff 单位 | `survivor/commander_aura.gd:88` _cleanup_buffed |
| 应用 buff（G/结构/滚转/速度/加速/失速）| `survivor/commander_aura.gd:102` _apply_buff |
| 移除单个 buff | `survivor/commander_aura.gd:133` _remove_buff |
| 移除全部 buff | `survivor/commander_aura.gd:154` _remove_all_buffs |
| 招募新成员（允许从普通编队挖人）| `survivor/commander_aura.gd:165` _try_recruit |
| 析构时清理 | `survivor/commander_aura.gd:251` _exit_tree |
| 查找 AI 控制器 | `survivor/commander_aura.gd:258` _find_ai |

### commander_overlay.gd — 指挥机视觉覆盖（~80 行）

| 功能 | 位置 |
|------|------|
| 颜色常量 | `commander_overlay.gd:10-13` |
| 坠落淡出时长常量 | `commander_overlay.gd:15` DESTROY_FADE_DURATION |
| 绘制（坠落时按 _destroy_timer 淡出） | `commander_overlay.gd:27` _draw |

### survivor_hud.gd — HUD（881 行）

| 功能 | 位置 |
|------|------|
| 布局常量 | `survivor_hud.gd:47-49` |
| UI 构建 | `survivor/survivor_hud.gd:91` _build_ui |
| 输入（暂无实际用途） | `survivor/survivor_hud.gd:338` _unhandled_input |
| 主循环（更新显示） | `survivor/survivor_hud.gd:343` _process |
| UI 自适应布局 | `survivor/survivor_hud.gd:360` _layout_ui |
| HP/XP/等级 显示更新 | `survivor/survivor_hud.gd:465` _update_display |
| 状态面板（飞机属性）| `survivor/survivor_hud.gd:563` _update_status_panel |
| 战术按钮创建 | `survivor/survivor_hud.gd:823` _create_tac_button |
| 武器/高度/规避按键回调 | `survivor_hud.gd:448-478` |
| 战术 tooltip | `survivor/survivor_hud.gd:926` _on_tac_hover |
| 战术按钮状态刷新 | `survivor/survivor_hud.gd:1000` _update_tactical_buttons |
| 王牌中队交战血条（分段命条） | `survivor/survivor_hud.gd:1162` _build_ace_panel |
| Debug 面板文字更新 | `survivor/survivor_hud.gd:1534` _update_debug_panel |
| 游戏结束画面 | `survivor/survivor_hud.gd:1583` show_game_over |

### survivor_upgrade_ui.gd — 升级选择界面（124 行）

| 功能 | 位置 |
|------|------|
| 信号 upgrade_selected | `survivor_upgrade_ui.gd:6` |
| UI 构建 | `survivor_upgrade_ui.gd:30` _build_ui |
| 显示三选一 | `survivor_upgrade_ui.gd:162` show_choices |
| 选择回调 | `survivor/survivor_upgrade_ui.gd:303` _on_choice_pressed |

### 技能归属分流（spec skills-720-rework T1 / squad-upgrade-ownership §2.8）

| 功能 | 位置 |
|------|------|
| 归属字段文档（scope/classes/milestone_plus） | `survivor/survivor_data.gd:79` 附近 UPGRADES 头注释 |
| scope 查询 | `survivor/survivor_data.gd:2168` upgrade_scope |
| 品类数组查询 | `survivor/survivor_data.gd:2173` upgrade_classes |
| "+1 轴进度"目标轴查询 | `survivor/survivor_data.gd:2180` milestone_plus_of |
| 王牌字段型 stat 白名单 | `survivor/survivor_data.gd:2202` ACE_FIELD_STATS |
| 归属生效纯谓词 | `survivor/survivor_data.gd:2217` upgrade_applies_to_machine |
| 品类身份映射表 | `survivor/evolution_system.gd:73` CLASS_IDENTITY_BY_CATEGORY |
| 档案 → 品类身份 | `survivor/evolution_system.gd:87` class_identity_of_profile |
| 定向应用（借指针走同 match） | `survivor/survivor_player.gd:374` apply_upgrade_to |
| 王牌剥离（切控迁移逆操作） | `survivor/survivor_player.gd:387` strip_upgrade_from |
| "+1 轴进度"加成（cap=2） | `survivor/survivor_player.gd:139` add_milestone_bonus |
| 里程碑进度=点+加成 | `survivor/survivor_player.gd:153` get_milestone_progress |
| 队存活成员枚举 | `survivor/survivor_mode.gd:2802` _squad_members_alive |
| 单机品类身份（meta profile_id） | `survivor/survivor_mode.gd:2815` _class_identity_of |
| 队品类并集（卡池门控） | `survivor/survivor_mode.gd:2824` _squad_present_classes |
| 升级归属分流入口 | `survivor/survivor_mode.gd:2834` _distribute_upgrade |
| "+1 轴进度"发放点 | `survivor/survivor_mode.gd:2909` _grant_milestone_plus |
| 生效子集 meta 重建 | `survivor/survivor_mode.gd:2920` _refresh_squad_effective_stacks |
| 王牌字段技切控迁移 | `survivor/survivor_mode.gd:2946` _migrate_ace_field_upgrades |
| 新僚机入队补挂 build | `survivor/survivor_mode.gd:2962` _apply_build_to_new_member |
| 验收测试（bench skills720） | `tests/test_skills_720.gd:15` run |

> **技能系统总入口 → [skill-implementation-index.md](skill-implementation-index.md)**（配置字段 × 实装八模式 ×
> 全 stat 消费点速查）。下面按批次的段落只是历史行号锚点，"某技能代码在哪"优先查那份索引。

### 720 批 T3 钩子（僚机阵亡/弹尽/AB 充能/轮盘联动/停靠）

| 功能 | 位置 |
|------|------|
| 备用弹仓（弹尽概率回满） | `survivor/skill_hooks.gd:306` try_gun_reserve_mag |
| 副武器（装填期免耗弹窗口） | `survivor/skill_hooks.gd:323` in_free_missile_window |
| QAAM 嗜血 / 适应回能（击杀钩子内） | `survivor/skill_hooks.gd:210` 附近 dispatch_on_kill 720 批段 |
| AB 充能静态引用注入 | `survivor/skill_hooks.gd:185` afterburner |
| 僚机阵亡 watcher（0.5s 沿检测） | `survivor/survivor_mode.gd:2986` _tick_squad_watch |
| 复仇之战/刺客复仇/黑匣子分发 | `survivor/survivor_mode.gd:3039` _on_squad_member_down |
| 奖励升级队列/呈现 | `survivor/survivor_mode.gd:3056` _queue_bonus_upgrade |
| 保卫阵地圈内 buff 维护 | `rts/squad_command_controller.gd:650` _update_guard_zone_buff |
| 阵地转移/保卫阵地/座舱护甲减伤 | `aircraft.gd:2581` _apply_damage 720 批段 |
| 撤离/防守物理注入 | `aircraft/aircraft_physics.gd:465` _g_buff_mult 与 EVAC_SHIFT_SPRINT_BONUS |
| QAAM 击杀归因（kind="qmaam"） | `missile_manager.gd:41` spawn_missile is_secondary |
| 对头击杀经验 ×1.5（历练） | `survivor/survivor_spawner.gd:2514` 附近 headon_xp 段 |

### 720 批 T5 新机制（胆大妄为/机炮吊舱/电磁炮双发/导弹二段）

| 功能 | 位置 |
|------|------|
| R 手动闪避（i-frame + 滚转 + 投焰） | `aircraft.gd:1980` do_manual_dodge |
| R 键输入入口 | `survivor/survivor_mode.gd:1380` 附近 KEY_R 分支 |
| 禁自动 flare 门 | `aircraft/aircraft_flares.gd:119` manual_dodge_active 早退 |
| 机炮吊舱两道翼挂 | `aircraft/aircraft_weapons.gd:392` 附近 gun_extra_barrels 分支 |
| 电磁炮双发补射 | `equipment/railgun_equipment.gd:134` followup_pending 分支 |
| 导弹二段推进（续推+渐强） | `missile.gd:73` _second_stage_g_mult 与动力阶段 elif |

### 722 批 机体签名技能（41 机每机一条；spec aircraft-signature-skills）

| 功能 | 位置 |
|------|------|
| 数据表 40 条（sig_* 段） | `survivor/survivor_data.gd:1459` sig_f15 起 |
| milestone_plus 数组化 | `survivor/survivor_data.gd:2180` milestone_plus_list_of |
| apply 专用分支（722 段） | `survivor/survivor_player.gd:812` sig_relaxed_stability 起 |
| 技能杂项 tick（CD/VIFFing/近太空/三发推力/超速截击） | `aircraft.gd:1383` _update_sig_skills |
| 超速截击选目标 | `aircraft.gd:1437` _sig_mig31_pick_target |
| STEALTH 上升沿装填（先敌开火） | `aircraft.gd:2400` _sig_f22_reload_all |
| 隐身多锁齐射消费点 | `aircraft.gd:2429` effective_max_locks |
| 致死拦截（钛浴缸/复活判序） | `aircraft.gd:2646` _try_sig_death_save |
| 负面状态免疫早退（电战预算） | `combat_unit.gd:113` apply_status（头部 sig_status_immune 早退） |
| 全频段压制流速（被锁敌负面 ×0.6） | `status_effects.gd:97` sig_x13_active + tick 内 x13_suppress |
| 锁定管线集中注入（6 技 + viggen 出锥 grace） | `survivor/survivor_mode.gd:1987` _update_radar_locks（722 段在 in_cone/出锥两分支） |
| 一次性特判（f47/x02/ax00） | `survivor/survivor_mode.gd:2850` _dispatch_sig_oneshot |
| 签名 drone 生成（f47/x90，不进离屏 despawn 体系） | `survivor/survivor_mode.gd:2889` _sig_spawn_loyal_drone |
| 联合突击差量重算 | `survivor/survivor_mode.gd:3015` _update_sig_gcap |
| 奖励僚机生成体（双子星复用；尾部 build 补挂） | `survivor/survivor_mode.gd:3765` _spawn_reward_wingman |
| 鲸群血量均摊 | `survivor/skill_hooks.gd:56` whale_pod_share |
| 作战云广播（中继直通防双乘） | `survivor/skill_hooks.gd:79` broadcast_combat_cloud |
| 三发推力触发（突击命令两入口） | `survivor/skill_hooks.gd:97` try_trigger_j36_assault |
| 特殊机动完成事件（急停/落叶飘） | `survivor/skill_hooks.gd:112` on_special_maneuver_done |
| f35 越肩发射豁免 | `aircraft/aircraft_weapons.gd:898` _sig_f35_relay_ok |
| 夜枭静默弹过滤（规避+投焰单点覆盖） | `ai/missile_evasion.gd:253` sig_silent 过滤 |
| 超越地平重索敌 | `missile.gd:340` _sig_find_retarget |
| 验收 bench（47 断言） | `tests/test_sig_skills.gd` --bench=sig_skills |
| **sig 判别式**（抽卡加权与卡框共用；`id.begins_with("sig_")`） | `survivor/survivor_data.gd:2275` is_signature_upgrade |
| **sig 抽卡权重乘区**（常量 + 乘区函数） | `survivor/survivor_data.gd:52` SIG_SKILL_WEIGHT_MULT / `survivor/survivor_data.gd:2280` _sig_weight_mult |
| └ 消费点 1（轴卡三选一） | `survivor/survivor_data.gd:2537` pick_card_for_axis |
| └ 消费点 2（通用加权抽卡） | `survivor/survivor_data.gd:2385` _weighted_pick |
| **sig 卡框色**（洋红边框 + 底色叠加；稀有度徽章仍用真稀有度色） | `survivor/survivor_upgrade_ui.gd:11` SIG_FRAME_COLOR（用点 `survivor/survivor_upgrade_ui.gd:217` frame_color）|

### 728 批 三轴里程碑全队下发（spec evolution-attribute-gates）

> 语义：里程碑加成**跟玩家不跟机体，且下发全队**（与 UPGRADES 归属分流一致）。
> 记账从玩家级单账本改为**逐机记账**，换帅/换型/晚入队都由构造保证不丢不叠。

| 功能 | 位置 |
|------|------|
| 逐机记账 meta 键 | `survivor/survivor_player.gd:233` MILESTONE_RECORD_META |
| 记账读 / 写（无飞机时落孤儿本） | `survivor/survivor_player.gd:236` _milestone_record / `survivor/survivor_player.gd:243` _set_milestone_record |
| "当前操控机那本账"属性视图（tactical_map 量表读法不变） | `survivor/survivor_player.gd:93` applied_milestones |
| 下发目标提供器（未注入 = 只有当前操控机） | `survivor/survivor_player.gd:101` milestone_targets_provider |
| └ 目标解析 | `survivor/survivor_player.gd:250` _milestone_targets |
| └ 注入点（注 `_squad_members_alive`） | `survivor/survivor_mode.gd:424` milestone_targets_provider |
| 跨档下发（加点后，逐机幂等） | `survivor/survivor_player.gd:264` apply_crossed_milestones_to |
| 全量补挂（新僚机入队 / 僚机换型） | `survivor/survivor_player.gd:280` apply_all_milestones_to |
| └ 新僚机入队调用点 | `survivor/survivor_mode.gd:2981` apply_all_milestones_to |
| 清账重挂（换型；**每机恰好一次**，重复调用会叠两遍） | `survivor/survivor_player.gd:294` reapply_all_milestones_to |
| └ 进化换型调用点（对 `_squad_members_alive()` 逐机） | `survivor/survivor_mode.gd:3437` reapply_all_milestones_to |
| 定向生效（借 self.aircraft 指针走同一 match，同 apply_upgrade_to 手法） | `survivor/survivor_player.gd:300` _apply_milestone_effect_to |
| 无头断言（E2 节：僚机同吃 / 逐机幂等 / 晚入队补挂 / 换帅不丢） | `tests/test_attribute_gates.gd:176` _test_milestone_squad_wide |

### survivor_debug_skills.gd — F4 技能面板（299 行）

| 功能 | 位置 |
|------|------|
| F4 开关（打开时暂停）| `survivor/survivor_debug_skills.gd:38` _unhandled_input |
| UI 构建 | `survivor/survivor_debug_skills.gd:84` _build_ui |
| 按钮样式 | `survivor/survivor_debug_skills.gd:320` _apply_btn_style |
| 列表刷新 | `survivor/survivor_debug_skills.gd:351` _refresh |
| 设置等级 | `survivor/survivor_debug_skills.gd:480` _on_set_level |
| 触发升级（+1） | `survivor/survivor_debug_skills.gd:489` _on_levelup |
| 按 ID 添加技能 | `survivor/survivor_debug_skills.gd:499` _on_add_skill_by_id |
| 添加选中技能 | `survivor/survivor_debug_skills.gd:510` _on_add_skill |
| 移除技能 | `survivor/survivor_debug_skills.gd:538` _on_remove_skill |

### survivor_debug_spawn.gd — F5 刷怪面板（274 行）

| 功能 | 位置 |
|------|------|
| 编队类型枚举 FormationType | `survivor_debug_spawn.gd:19` |
| 敌机类型标签表 | `survivor/survivor_debug_spawn.gd:48` ENEMY_TYPE_LABELS |
| F5 开关（不暂停）| `survivor/survivor_debug_spawn.gd:81` _unhandled_input |
| UI 构建（下拉/规模/按钮）| `survivor/survivor_debug_spawn.gd:99` _build_ui |
| 类型切换联动编队 | `survivor/survivor_debug_spawn.gd:341` _on_type_changed |
| 编队模式切换 | `survivor/survivor_debug_spawn.gd:354` _on_formation_changed |
| 刷怪按钮（调 _spawn_*）| `survivor/survivor_debug_spawn.gd:369` _on_spawn_pressed |
| 清空敌人按钮 | `survivor/survivor_debug_spawn.gd:509` _on_clear_pressed |
| 导出日志按钮（替代 F9）| `survivor/survivor_debug_spawn.gd:534` _on_dump_pressed |

### survivor_select.gd — 机型选择界面（263 行）

| 功能 | 位置 |
|------|------|
| 可选机型列表 AIRCRAFT_LIST | `survivor_select.gd:19` |
| UI 构建 | `survivor/survivor_select.gd:130` _build_ui |
| 机型卡片构建 | `survivor_select.gd:196` _build_aircraft_card |
| 选中回调（写 meta 进下一场景）| `survivor/survivor_select.gd:412` _on_aircraft_selected |
| 背景绘制 | `survivor/survivor_select.gd:97` _draw |

## 无线电通讯（spec radio-chatter）

设计权威源：[docs/specs/systems/radio-chatter.md](../specs/systems/radio-chatter.md)。
本节按**"我要改什么 → 去哪"**组织，不按文件罗列。

### ⚡ 最常见的改动（多数不用碰代码）

| 我想…… | 去哪 |
|---|---|
| **加一条台词** | ① `resources/chatter/radio_chatter.json` 对应 trigger 的 `lines` 加 key ② `i18n/translations.csv` 加一行三语。**不碰代码** |
| **改台词文案** | `i18n/translations.csv` 的 `RADIO_*` 行（改完需 Godot 重新导入） |
| **嫌太吵 / 太安静** | JSON `global.ambient_cooldown_sec`（总闸）+ 各 trigger 的 `chance`（主旋钮） |
| **某类语音太频繁** | JSON 该 trigger 的 `chance` 调低 / `cooldown_sec` 调高 |
| **让某类语音必定播出** | JSON 该 trigger 改 `"class": "scripted"`（同时豁免三层节流） |
| **改谁先播** | JSON 该 trigger 的 `weight` |
| **让某机型能/不能说话** | JSON `voiced_enemy_types.types` 增删机型 tag |
| **改 BOSS 登场对话** | JSON `boss_sequences.<BOSS_ID>.spawn`（`slot` = 队内序号，决定谁说） |
| **加新 BOSS 的专属对话** | JSON `boss_sequences` 加一项，key 用 `BossRegistry.BOSS_DEFS` 的 id；不加则走 `_default` |
| **加全新触发场景** | JSON `triggers` 加一项 → 事件点调 `RadioChatter.say("<id>", ...)` |
| **改版式/配色/位置** | `radio_chatter.gd:25-58` 常量区 |

### 数据表结构（`resources/chatter/radio_chatter.json`）

| 段 | 内容 |
|---|---|
| `global` | 全局节流 + 时长 + 队列参数 |
| `triggers.<id>` | `class` / `weight` / `cooldown_group` / `cooldown_sec` / `chance` / `lines` / `lines_ref` |
| `boss_sequences.<BOSS_ID>.{spawn,engage}` | `[{slot, key}]` 多句队内对话；`_default` 为未登记 BOSS 兜底 |
| `voiced_enemy_types.types` | 配无线电的机型 tag 白名单（opt-in，未列 = 沉默） |

### 核心逻辑（`scripts/survivor/radio_chatter.gd`，CanvasLayer layer=19）

| 功能 | 位置 |
|------|------|
| 版式/配色/位置常量 | `radio_chatter.gd:25-58` |
| **三层节流判定**（全局冷却→冷却桶→概率骰） | `radio_chatter.gd:170` say_text 开头 |
| 入队 + 满队按 weight 淘汰 | `radio_chatter.gd:170` say_text |
| 按 trigger 选词 + `%` 格式化 | `radio_chatter.gd:233` say |
| 说话人从单位解析 | `radio_chatter.gd:243` say_unit |
| BOSS 多句序列入队 | `radio_chatter.gd:274` say_boss_sequence |
| 敌方减员里程碑（每 12 架跨档） | `radio_chatter.gd:287` notify_enemy_loss |
| 呼号解析 | `radio_chatter.gd:300` speaker_name_of |
| 阵营色解析（引 FactionPalette） | `radio_chatter.gd:307` color_of / `:276` color_for_team |
| 队列状态机 IDLE/SPEAKING/GAP | `radio_chatter.gd:335` _process |
| 冷却递减（含全局） | `radio_chatter.gd:361` _tick_cooldowns |
| 出队 + 过期丢弃（scripted 豁免） | `radio_chatter.gd:374` _pump |
| 权重排序 | `radio_chatter.gd:388` _best_index |
| 开播（写 Label + 触发音效） | `radio_chatter.gd:399` _begin |
| 显示时长公式 | `radio_chatter.gd:420` line_duration |
| 淡入淡出 | `radio_chatter.gd:425` _apply_alpha |
| 节点构建（PanelContainer + 两 Label） | `radio_chatter.gd:92` _build |
| 渐变底（GradientTexture2D） | `radio_chatter.gd:136` _make_gradient_style |
| 换行后重算高度 | `radio_chatter.gd:158` _relayout |

### 数据加载器（`scripts/survivor/chatter_lines.gd`，**零数值，纯查表**）

| 功能 | 位置 |
|------|------|
| JSON 路径常量 | `chatter_lines.gd:13` DATA_PATH |
| 分类枚举 SCRIPTED/AMBIENT | `chatter_lines.gd:16` Kind |
| 加载 + 静态缓存 + 失败降级静默 | `chatter_lines.gd:28` _ensure_loaded |
| BOSS 序列查询（未登记退 `_default`） | `chatter_lines.gd:129` boss_sequence |
| 说话资格等级门 | `chatter_lines.gd:139` type_has_voice |
| 减员档位映射 | `chatter_lines.gd:148` attrition_trigger |
| 选词防相邻重复 | `chatter_lines.gd:163` pick |
| 校验用全量导出 | `chatter_lines.gd:180` all_line_keys / `:204` all_trigger_ids |

### 说话资格门（无人机不得有台词，spec §2.8）

| 关注点 | 位置 |
|------|------|
| **硬规则**：no_pilot 永不说话 | `aircraft.gd:345` can_speak_on_radio |
| 等级门字段 | `aircraft.gd:341` has_radio_voice |
| 常规敌机赋值（与 no_pilot 同处） | `survivor/survivor_spawner.gd:1796` |
| Mother Goose 蜂群 UAV | `survivor/mother_goose_uav_swarm.gd:250` |
| Mother Goose MQ-X | `survivor/mother_goose_boss.gd:443` |
| 白名单数据 | JSON `voiced_enemy_types.types` |

### 触发接线（每处 ≤4 行，全部挂在既有信号/函数上）

| 触发 | 位置 |
|------|------|
| 系统实例化（**刻意在战区 if 之外**，boss_debug 也要有） | `survivor/survivor_mode.gd:423` |
| 字段声明 | `survivor/survivor_mode.gd:140` _radio |
| BOSS 登场挑衅 | `events/boss_encounter_event.gd:112`（`_start` 内，紧邻 WARNING 横幅） |
| BOSS 交战 | `survivor/survivor_mode.gd:4064` on_boss_engaged |
| 击坠回报 / 弹射 / 减员计数 | `survivor/survivor_mode.gd:4085` _on_radio_kill_recorded |
| break 规避呼叫（真·躲导弹） | `survivor/survivor_mode.gd:4110` _on_radio_evasion_started |
| 加力冲刺呼叫（玩家主动加力，非躲导弹） | `survivor/survivor_mode.gd:4118` _on_radio_afterburner_engaged |
| 僚机归队 | `survivor/survivor_mode.gd:4127` _on_radio_wingman_joined |
| RTS 回令派发 | `rts/squad_command_controller.gd:734` _ack |
| RTS 应答人选取（跳过无人机） | `rts/squad_command_controller.gd:721` _ack_speaker |
| RTS 攻击回令空/地分流（空=追击/包围·地=打击） | `rts/squad_command_controller.gd:749` _strike_or_pursue |
| RTS 目标名解析 | `rts/squad_command_controller.gd:753` _target_label |

### 信号（EventLogger 全局总线）

| 信号 | 声明 |
|------|------|
| `kill_recorded(..., victim_voiced)` | `event_logger.gd:12` kill_recorded |
| `evasion_started(callsign, team)` | `event_logger.gd:16` evasion_started |
| `afterburner_engaged(callsign, team)` | `event_logger.gd:21` afterburner_engaged |
| `wingman_joined(callsign, team)` | `event_logger.gd:25` wingman_joined |

> `kill_recorded` 另有两个订阅方（`survivor_hud` kill feed / `roe_director`），**改签名要同步三处**。

### 音频（Radio 总线）

| 关注点 | 位置 |
|------|------|
| 播放入口 | `audio/audio_manager.gd:586` play_radio |
| 音效 id → 路径 | `audio/audio_manager.gd:62` RADIO_FILES |
| **素材待补** | `res://audio/sfx/radio_beep.wav`（缺失时静默跳过，不 push_warning） |

### 测试与导出

| 关注点 | 位置 |
|------|------|
| 无头回归（87 断言） | `scripts/tests/test_radio_chatter.gd`，`--bench=chatter` |
| 注册表 | `scripts/bench/bench_runner.gd` UNIT_TESTS |
| **导出必需** | `export_presets.cfg` 的 `include_filter` 必须含 `*.json`，否则数据表不进包 |

## 主场景/操控

| 功能 | 位置 |
|------|------|
| 鼠标输入 | `main.gd:66` _unhandled_input |
| 左键点击（锁定/移动） | `main.gd:119` _on_left_click |
| 右键取消 | `main.gd:136` _on_right_click |
| 悬停检测 | `camera_controller.gd:250` update_hover（main.gd 调用） |
| LOD 管理 | `main.gd:450` _update_lod |
| 地形绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 命令轮盘手势层（生存，spec command-wheel） | `scripts/rts/command_wheel.gd`（CommandWheel；参数 `command_wheel_params.gd` + `resources/command_wheel.tres`） |
| 轮盘接线：左键按下/松开仲裁 + 单击回放 | `survivor_mode.gd` `_on_left_press` / `_on_left_release` / `_execute_left_click` / `_on_wheel_command`（阶段 1 stub 打 EventLogger） |

## 视觉绘制

| 功能 | 位置 |
|------|------|
| 飞机绘制入口 | `aircraft.gd:2836` _draw |
| 飞机线框图标 | `aircraft_renderer.gd:658` draw_aircraft_icon |
| 指挥型图标 | `aircraft_renderer.gd:807` draw_commander_icon |
| 雷达锥绘制 | `aircraft_renderer.gd:204` draw_radar_cone |
| 锁定警告闪烁 | `aircraft_renderer.gd:406` draw_lock_indicator |
| 数据标签（完整） | `aircraft_renderer.gd:1418` draw_data_label |
| 数据标签（简化） | `aircraft_renderer.gd:1291` draw_data_label_minimal |
| 机头闪光 | `aircraft_renderer.gd:520` draw_muzzle_flash |
| 加力火焰 | `aircraft_renderer.gd:530` draw_afterburner_glow |
| 热诱弹粒子 | `aircraft_renderer.gd:563` draw_flare_particles |
| 目标连线 | `aircraft_renderer.gd:1604` draw_target_line |
| 预测轨迹 | `aircraft_renderer.gd:1717` draw_predicted_path |
| 战术提示弹窗 | `aircraft_renderer.gd:1584` draw_tactic_popup |
| 机炮意图锥（敌方威胁锥 / 友方 hover 参考锥；读淡出系数） | `aircraft_renderer.gd:363` draw_gun_cone |
| └ 威胁锥淡出系数（开火淡出 / 停火淡回） | `aircraft.gd:504` _gun_threat_fade |
| └ 淡出淡回时长常量 | `aircraft.gd:505` GUN_THREAT_FADE_OUT_TIME / `aircraft.gd:506` GUN_THREAT_FADE_IN_TIME |
| └ 每帧推进（威胁条件成立时按 is_firing 增减） | `aircraft.gd:3002` _update_gun_threat_indicator |
| └ 威胁条件中断复位（保留"立即归零防抖"语义） | `aircraft.gd:3028` _reset_gun_threat |

## HUD / UI

| 功能 | 位置 |
|------|------|
| 沙盒 HUD（**沙盒已废弃**，仅调试留存）| `hud.gd:7` _process |
| 生存模式 HUD 构建 | `survivor/survivor_hud.gd:91` _build_ui |
| 生存模式 HUD 更新 | `survivor/survivor_hud.gd:465` _update_display |
| 状态面板更新 | `survivor/survivor_hud.gd:563` _update_status_panel |
| 战术按钮 | `survivor/survivor_hud.gd:823` _create_tac_button |
| 升级 UI 选项展示 | `survivor_upgrade_ui.gd:162` show_choices |
| 调试面板构建 | `debug_panel.gd:41` _build_ui |
| 调试面板内容更新 | `debug_panel.gd:183` _update_content |
| 战斗策略文本 | `debug_panel.gd:336` _get_combat_strategy |
| 飞行员信息 | `debug_panel.gd:373` _get_pilot_info |
| 地面单位生成按钮 | `debug_panel.gd:703` _spawn_ground_unit |
| Game Over 显示 | `survivor/survivor_hud.gd:1583` show_game_over |

## 资源参数文件

> ⚠ **下表是早期基准资源的选摘，远非全量**。现在还有：
> `resources/player/`（41 架玩家机 + 分档热诱弹）· `resources/evolution/`（进化树）·
> `resources/weapons/` · `resources/naval/`（舰船）·
> `resources/chatter/radio_chatter.json`（无线电台词）·
> `resources/presentation/sequences.json`（演出时间线）· 以及 20 多个 `enemy_*.tres`。
>
> 敌机资源的准确对应看 [enemy-index.md](enemy-index.md)；
> 参数数值看 [resources-catalog.md](resources-catalog.md)。

| 资源 | 文件 |
|------|------|
| F-16 早期基准（**非当前玩家起手机**） | `resources/default_fighter.tres` |
| MiG-29（敌方） | `resources/enemy_fighter.tres` |
| J-7 截击机 | `resources/enemy_interceptor.tres` |
| MQ-109（机炮无人机） | `resources/enemy_uav.tres` |
| MQ-110（导弹无人机） | `resources/enemy_uav_missile.tres` |
| F-4E（前期导弹杂鱼） | `resources/enemy_f4e.tres` |
| Sentinel 指挥机 | `resources/enemy_uav_commander.tres` |
| A-7 攻击机 | `resources/enemy_a7.tres` |
| A-7 机炮 | `resources/a7_gun.tres` |
| A-7 火箭弹 | `resources/a7_rocket.tres` |
| Q-5 攻击机 | `resources/enemy_q5.tres` |
| Q-5 机炮 | `resources/q5_gun.tres` |
| Q-5 火箭弹 | `resources/q5_rocket.tres` |
| Probe 侦察机 | `resources/drone_probe.tres` |
| M61A1 机炮 | `resources/default_gun.tres` |
| ZU-23 高炮 | `resources/aa_gun.tres` |
| UAV 机枪 | `resources/uav_gun.tres` |
| AIM-7M 导弹 | `resources/default_missile.tres` |
| AGM-65 对地导弹 | `resources/agm_missile.tres` |
| HQ-7 防空导弹 | `resources/sam_missile.tres` |
| UAV-SAM 导弹 | `resources/uav_missile.tres` |
| 战斗风格 | `resources/default_combat.tres` |
| 热诱弹 | `resources/default_flare.tres` |
| SAM 单位 | `resources/sam_params.tres` |
| AAA 单位 | `resources/aa_gun_params.tres` |
| 雷达站 | `resources/radar_station_params.tres` |

## 场景文件

| 场景 | 文件 | 节点树 |
|------|------|--------|
| 生存模式（**主玩法**） | `scenes/survivor_mode.tscn` | SurvivorMode + BulletManager + MissileManager + Camera2D |
| 沙盒主场景（**已废弃**，仅调试留存） | `scenes/main.tscn` | Main + BulletManager + MissileManager + Camera2D + PlayerAircraft + DebugPanel |
| 飞机模板 | `scenes/aircraft.tscn` | Aircraft (Node2D + aircraft.gd) |
| 导弹模板 | `scenes/missile.tscn` | Missile (Node2D + missile.gd) |
| SAM 单位 | `scenes/sam_unit.tscn` | SAMUnit + sam_params |
| AA 单位 | `scenes/aa_gun_unit.tscn` | AAGunUnit + aa_gun_params |
| 雷达站 | `scenes/radar_station.tscn` | RadarStation + radar_station_params |
| 主菜单（**入口场景**） | `scenes/main_menu.tscn` | MainMenu |
| 机型选择 | `scenes/survivor_select.tscn` | SurvivorSelect |
| 地图选择 | `scenes/survivor_map_select.tscn` | 生存流程第一步；B → boss_debug_select |
| BOSS 测试场 | `scenes/boss_debug_select.tscn` | 全机型 × 技能组合 |
| 地图编辑器 | `scenes/map_editor.tscn` | UGC |
| 手画地块参考 | `scenes/map_manual.tscn` | @tool 编辑器预览 |

## ROE / 阵营 / 第三方（2026-07-12，spec global-awareness-roe）

- **敌我判定唯一 API**：combat_unit.gd `is_hostile_to()` / `teams_hostile()` / `is_player_squad()`（team 0=PLAYER 1=HOSTILE 2=ALLY；散写 team 直比已收口禁止回潮）
- **感知门**：ai_controller.gd `_roe_allows_scored_engage()`（TS_SCORED 专用；读 roe_posture / roe_aware_until / roe_zone_* meta）
- **察觉/姿态/热度**：survivor/roe_director.gd（写 meta 的唯一方；2s 感知 tick + 1s 热度 tick）
- **hunter 配额**：survivor_spawner.gd `_update_hunters`（配额 = `_roe.hunter_quota()`，整队抽调）
- **第三方事件**：events/ally_force.gd + awacs_support_event.gd（护送直升机事件 `escort_convoy_event.gd` 已于 2026-07-28 删除）；机场解放后 ALLY 防空渐进部署 survivor_mode `_deploy_airfield_ally_gradual`（spec airfield-liberation-zones）；调度 `_update_ally_events`
- **AWACS 支援事件**（2026-07-28 改造：绕战区轨道 + 定时撤离 + 进离场无线电）：

| 功能 | 位置 |
|------|------|
| 轨道中心选取（选中战区 → 最近 AVAILABLE 战区 → 兜底南带） | `events/awacs_support_event.gd:159` _pick_orbit_center |
| 到点转撤离（航点改到南界外，飞出/超时即 end） | `events/awacs_support_event.gd:145` _begin_egress |
| 进离场无线电（trigger `awacs_onstation` / `awacs_egress`） | `events/awacs_support_event.gd:191` _say |
| 在站时长 / 撤离兜底 | `events/awacs_support_event.gd:21` ON_STATION_S / `events/awacs_support_event.gd:23` EGRESS_TIMEOUT_S |
| 轨道几何常量（退避 / 半程 / 边界余量，退避须 < BUFF_RADIUS_PX） | `events/awacs_support_event.gd:26` ORBIT_STANDOFF_PX / `events/awacs_support_event.gd:28` ORBIT_HALF_SPAN_PX / `events/awacs_support_event.gd:30` ORBIT_MARGIN_PX |
| buff 半径（锁定×3 / 导弹 G ×1.25 的作用域） | `events/awacs_support_event.gd:14` BUFF_RADIUS_PX |
| Tab 图光环圈绘制 | `survivor/tactical_map.gd` _draw_dock_markers AWACS 分支 |
- **阵营色板**：game_constants.gd FactionPalette（COL_FRIEND_PLAYER/ALLY、COL_ENEMY_REGULAR/ELITE + 全部 team_* 函数三分支）

## 表演/演出（转场·镜头·时间·剧情演出）

- **总入口**：编排手册 [cinematic-authoring.md](cinematic-authoring.md)（通道/op 全参考 + ctx 契约 + 陷阱表）；设计权威 spec [systems/ui-transition.md](../specs/systems/ui-transition.md)
- 导演/通道分发/遮罩/热重载 → `scripts/presentation/presentation_director.gd`
- 时间缩放与暂停（唯一写入口，含命令轮盘收编）→ `scripts/presentation/time_authority.gd`；轮盘接线 `scripts/rts/command_wheel.gd _activate/_reset/_exit_tree`
- 演员走位/尾迹/演出隐身 → `scripts/presentation/cinematic_cast.gd`；指令消费端 `scripts/ai_controller.gd _directive_follow_path_step`（`target_speed`/`arrive_radius` 参数）
- 空舞台隔离 → `scripts/presentation/stage_isolator.gd`
- 镜头电影层（`_base_zoom` 拆分/cine_target 跟随/暂停期代泵）→ `scripts/camera_controller.gd`
- BOSS 登场接入样板 + 收尾钩子 → `scripts/events/boss_encounter_event.gd _try_play_arrival_cinematic / _on_arrival_cinematic_done`
- 升级急刹接入 → `scripts/survivor/survivor_mode.gd _on_player_leveled_up / _on_upgrade_selected`；面板协议 `survivor_upgrade_ui.gd get_transition_elements`
- 演出台词时长覆写/ambient 压制 → `scripts/survivor/radio_chatter.gd set_duration_override / suppress_ambient`
- 演出配乐幂等 → `scripts/audio/audio_manager.gd current_music_id`

