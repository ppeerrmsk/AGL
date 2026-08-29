# 代码索引

按功能主题索引到 `文件:行号 符号`，直接读取对应行段即可获取上下文。不确定功能属于哪个代码域时先读
[Reference Index](_INDEX.md)；已知文件名时先用 [Script Index](script-index.md) 确认职责。

## 快速定位

本文件按“飞行与战斗 → AI / 编队 → 地面 / 海军 → 生存成长与内容 → 无线电 → 主场景 / 视觉 / UI → 资源 / 场景 → ROE / 演出 / 专项批次”排列。
先搜索二级标题，再搜索符号名；不要从头通读本文件。常用命令：

```powershell
rg -n "^## |^### " docs/reference/code-index.md
rg -n "目标功能名|ClassName|symbol_name" docs/reference/code-index.md
```

> ✅ **2026-08-21 全量校验通过**。当前文档与锚点数量以
> `python tools/verify_doc_anchors.py` 的实时输出为准；禁止在索引里冻结会迅速过期的总数。
> （2026-04-22 拆子模块重构遗留的 218 处失效锚点已批量修复。）
>
> **改代码后同步本文件，并跑校验器**：
> ```
> python tools/verify_doc_anchors.py                     # 全量
> python tools/verify_doc_anchors.py --section 无线电通讯  # 只查你动的那段
> ```
> 退出码 1 = 有锚点对不上。写锚点时**带上符号名**（`aircraft/aircraft_physics.gd:325 update_speed`），
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
> **概念保留** —— 计划在将来的拟真战役模式重新启用。`i18n/skills.csv` 的
> `UPGRADE_PILOT_STAMINA_*` 三语文本**刻意保留，不要当死键清掉**。

---

## 飞行物理

| 功能 | 位置 |
|------|------|
| 物理主循环 | `aircraft.gd:1151` _physics_process |
| 目标航向计算 | `aircraft/aircraft_physics.gd:76` update_target_heading |
| 实飞 / 预测共享目标航向状态 | `aircraft/aircraft_physics.gd` `_target_heading_state` |
| 滚转角更新（G 限制由 tactical_aggression 插值调节）| `aircraft/aircraft_physics.gd:206` update_bank |
| 实飞 / 预测共享滚转公式（方向锁、坡度帽、滚转权限、回正、EMA 积分） | `aircraft/aircraft_physics.gd` `_resolve_turn_lock_state` / `_bank_limit_rad` / `_bank_roll_rate_rad_s` / `_apply_bank_recovery` / `_integrate_bank_state` |
| 右键急刹拖拽转向（捕获鼠标 / 相对位移、12px 死区 / 110px 满舵、持续 G 坡度、失速禁用、实飞预测同源、机场面板接管释放、速度/射程摇杆、真实机炮射界） | `survivor/survivor_mode.gd` `_begin_hard_brake` / `_update_hard_brake_steer` / `_set_hard_brake` / `_open_evolution_offer` → `aircraft/aircraft_physics.gd` `brake_steer_input_from_dx` / `_brake_steer_target_bank` / `_speed_target_ms`；表现 `survivor/brake_steering_overlay.gd` → `survivor/survivor_hud.gd` `begin_brake_steering` / `set_brake_steering_stall_locked` / `set_brake_steering_flight_data`，飞机前方复用 `aircraft_renderer.gd` `should_show_friendly_gun_reference` / `draw_gun_cone`；右键 `SquadCommandController.cancel` 清旧 combat/commanded target，但机炮/炮艇自动扫描继续；spec `systems/brake-steering` |
| 航向更新 ω=g×tan(bank)/speed | `aircraft/aircraft_physics.gd:303` update_heading |
| 实飞 / 预测共享航向积分 | `aircraft/aircraft_physics.gd` `_integrate_heading_rad` |
| 速度更新（含高G阻力、高度耦合） | `aircraft/aircraft_physics.gd:325` update_speed |
| 实飞 / 预测共享速度公式（目标约束 + 积分） | `aircraft/aircraft_physics.gd` `_speed_target_ms` / `_integrate_speed_ms` |
| 高度更新 | `aircraft/aircraft_physics.gd:417` update_altitude |
| 实飞 / 预测共享高度积分 | `aircraft/aircraft_physics.gd` `_integrate_altitude_state` |
| AI 巡逻 / 作战偏好 / 近距匹配高度策略 | `ai/ai_altitude_policy.gd` `set_patrol` / `use_combat_preference` / `match_target` |
| 失速检查 | `aircraft/aircraft_physics.gd:490` update_stall |
| G力计算 | `aircraft/aircraft_physics.gd:512` update_g_load |
| 飞行员耐力 | **代码已移除**（保留概念：将来拟真战役模式再启用；`i18n` 的 `UPGRADE_PILOT_STAMINA_*` 三语文本刻意保留） |
| 位移应用 | `aircraft/aircraft_physics.gd:545` apply_movement |
| 最大 bank 角（物理瞬时上限） | `aircraft/aircraft_physics.gd:554` max_bank_angle |
| 有效最大G（**buff 注入点**，SEAM-001） | `aircraft/aircraft_physics.gd:599` effective_max_g；瞬时结构 G = `:610` effective_max_g_instant |
| 临时光环基线与加减速修改器（实飞/预测同源） | `aircraft/aircraft_physics.gd` `base_stall_kmh` / `base_roll_rate` / `base_accel` / `base_max_speed_kmh` / `base_cruise_kmh` / `effective_accel_mult` / `effective_decel_mult` |
| 角点速度 V=V_stall×1.2×√G | `aircraft/aircraft_physics.gd:691` corner_speed_kmh |
| 失速速度 V_stall×√G | `aircraft/aircraft_physics.gd:790` stall_speed |
| 高空最大速度衰减 | `aircraft/aircraft_physics.gd:799` max_speed_at_altitude |
| 空气密度比 σ=e^(-alt/8500) | `aircraft/aircraft_physics.gd:821` air_density_ratio |
| 旋翼机速度向量/机头解耦运动 | `aircraft/aircraft_physics.gd:1697 update_rotorcraft` |
| 高度档位切换（生存模式） | `aircraft.gd:1745` set_target_tier |

## 主动特殊机动（R 五选一）

| 功能 | 位置 |
|------|------|
| 共享状态/命中资格 | `aircraft.gd:2404 is_active_special_maneuver` / `aircraft.gd:2408 can_accept_new_hit` |
| 位移滚转激活与安全侧评分 | `aircraft.gd:2504 _try_start_displacement_roll` |
| 垂直越过激活与高度边界 | `aircraft.gd:2529 _try_start_vertical_break` |
| 动作推进与 10Hz AI 自动触发 | `aircraft.gd:2625 _update_active_special_maneuver` |
| 垂直越过俯仰投影（纵轴收缩/尾焰锚点） | `aircraft_renderer.gd:972 draw_muzzle_flash` / `aircraft_renderer.gd:983 draw_afterburner_glow` / `aircraft_renderer.gd:1154 draw_aircraft_icon` |
| 五向 R 固定优先级入口 | `aircraft.gd:2645 try_manual_maneuver` |
| 小队共享冷却账本 | `squad.gd:40 active_maneuver_cooldown_s` |
| 玩家 HUD 唯一技能/冷却只读状态 | `aircraft.gd:2423 equipped_r_maneuver_id` / `aircraft.gd:2437 r_maneuver_cooldown_total` / `aircraft.gd:2452 r_maneuver_cooldown_remaining` |
| 常规高度物理让位门 | `aircraft/aircraft_physics.gd:417 update_altitude` |
| 弹体/光束命中资格、source 清洗、归因与目标类型分派 | `weapon_hit_resolver.gd:11 can_accept_unit_hit` / `weapon_hit_resolver.gd:17 resolve_unit_hit`；调用方 `bullet_manager.gd` / `missile_manager.gd` / `equipment/laser_equipment.gd` / `equipment/railgun_equipment.gd` |
| 技能数据/五向互斥 | `survivor/survivor_data.gd:1737 displacement_roll` / `survivor/survivor_data.gd:1731 vertical_break` |
| 技能授予 | `survivor/survivor_skill_effects.gd:270 displacement_roll` / `survivor/survivor_skill_effects.gd:273 vertical_break` |
| 聚焦回归 | `tests/test_skills_720.gd:816 _test_t5_mechanisms`（轨迹、边界、命中、共享冷却、AI 自动） |

## 高度动作、爬升反制与能量循环

| 功能 | 位置 |
|------|------|
| CLIMB/DIVE 统一状态、Q 换档一次性闸门、进入沿与 4s 反制窗 | `aircraft.gd` `AltitudeAction` / `altitude_action_command` / `command_altitude_preference` / `_set_altitude_action` / `_tick_climb_counter_window` / `climb_counter_window_active`；`aircraft_physics.gd` `update_altitude`；玩家编队镜像见 `aircraft_formation.gd` `_update_altitude` |
| 普通高度物理与失速排除 | `aircraft/aircraft_physics.gd` `update_altitude`；目标方向 + 实际垂直速度 30m/s 门，失速保持 NONE |
| 编队僚机自身高度动作 | `aircraft/aircraft_formation.gd` `_update_altitude` |
| 严格 GUN_TAILED 火控解与旧射向打空 | `aircraft/aircraft_weapons.gd` `is_gun_tailed_by` / `_refresh_committed_gun_aim` → `aircraft.gd` `report_gun_tailed` |
| 迫近导弹 60m/s、3.5s 共用门与确定性失导 | `ai/missile_evasion.gd` `is_imminent_evasion_threat` → `aircraft.gd` `try_climb_counter_missile` → `missile.gd` `disrupt_by_climb_break` |
| DIVE 每机机炮回复与 2×超储 | `aircraft/aircraft_weapons.gd` `update_altitude_cycle_ammo`；编队早退由 `update_passive_gunship` 结算 |
| CLIMB 共享加力池 +0.2/s（只读当前操控机） | `survivor/survivor_mode.gd` → `survivor/afterburner_charge.gd` `update` |
| 详细 ALT 动作词与 GUN_TAILED 状态 | `aircraft_renderer.gd` `draw_data_label_minimal` / `draw_data_label` / `status_label_entries`；详细档固定英文 CLIMB/DIVE，战略档省略且无动作气流 |
| 聚焦回归 | `tests/test_skills_720.gd` `_test_altitude_actions_and_cycle`；全表/F4 审计 `tests/test_skill_audit.gd` |

## 能量管理

| 功能 | 位置 |
|------|------|
| 能量管理总入口 | `aircraft/aircraft_physics.gd:1018` update_energy_management |
| 加力燃烧器开关 | `aircraft/aircraft_physics.gd:984` set_afterburner |
| 燃油消耗 | `aircraft/aircraft_physics.gd:998` update_fuel |

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
| 设定战斗目标 | `aircraft.gd:2106` set_combat_target |
| 清除战斗目标 | `aircraft.gd:2125` clear_combat_target |
| CombatParams 获取 | `aircraft.gd:2180` _combat_params |
| 自动扫描机炮目标 | `aircraft/aircraft_weapons.gd` auto_gun_scan（普通机炮守交战纪律；玩家全队炮艇优先射程内 `commanded_target` / MountTarget，失格或超距时各自扫描最近 Aircraft/GroundUnit） |
| 编队 / LOD 提前返回路径的高度循环与炮艇 tick | `aircraft/aircraft_weapons.gd` update_passive_gunship + `aircraft.gd` LOD0/1/2 formation 分支 |

## 武器系统 — 机炮

| 功能 | 位置 |
|------|------|
| 机炮射击更新（梭射状态机，spec: gun-burst-fire） | `scripts/aircraft/aircraft_weapons.gd` update_gun |
| 单发出弹（散布/云雾/多管/音效/弹药） | `scripts/aircraft/aircraft_weapons.gd` _fire_gun_round |
| 梭射常量（DUTY/MIN_INTRA/帧补上限） | `scripts/aircraft/aircraft_weapons.gd` GUN_BURST_* |
| 梭计数与目标锁存状态 | `aircraft.gd` _gun_burst_rounds_left / _auto_gun_target_id / _gun_burst_target_id（_fire_cooldown 旁） |
| 梭目标逐 tick 提前点刷新 | `scripts/aircraft/aircraft_weapons.gd` _gun_target_from_id / _refresh_committed_gun_aim |
| GUN_TAILED 正式火控解 / CLIMB 旧射向冻结 | `scripts/aircraft/aircraft_weapons.gd` is_gun_tailed_by / _refresh_committed_gun_aim + `aircraft.gd` report_gun_tailed |
| 炮艇射向炮口 / CIWS 独立 5° 正面锥 | `scripts/aircraft/aircraft_weapons.gd` _fire_gun_round / AIRCRAFT_CIWS_CONE_HALF_ANGLE_DEG / update_ciws |
| 敌机一次机会一梭安全门（末发后停火 3s；全敌方 Aircraft） | `aircraft.gd` _ai_gun_burst_allowed / _ai_gun_pause_timer + `scripts/aircraft/aircraft_weapons.gd` update_gun |
| 每梭弹数参数 | `scripts/gun_params.gd` burst_count |
| [GUN_BURST] 梭起始诊断（射向/最近敌机距离快照，追"对空放枪"） | `scripts/aircraft/aircraft_weapons.gd` _log_burst_start |
| [GUN_SCAN] 被动扫描锁存上升沿诊断 | `scripts/aircraft/aircraft_weapons.gd` auto_gun_scan 尾部 |
| 机炮射程（像素） | `aircraft.gd:2209` _gun_range_px |
| 子弹生成 | `bullet_manager.gd:207` spawn_bullet |
| 子弹物理+命中检测 | `bullet_manager.gd` _physics_process |
| 曳光弹/火箭/炸弹/Flak/漂浮雷绘制 | `rendering/bullet_presenter.gd` `draw`；状态宿主 `bullet_manager.gd` `_draw` |
| 真命中火星（闪避不触发；每目标 110ms CD；12 组封顶；两次批量绘制） | `bullet_manager.gd` `_emit_hit_spark` `_update_hit_sparks` → `rendering/bullet_presenter.gd` `_draw_hit_sparks` |

## 武器系统 — 火箭弹（无制导副武器，例：F-86 FFAR）

| 功能 | 位置 |
|------|------|
| RocketParams 定义（齐射数/最终散布/冷却/射程 + 直飞/展开距离）| `scripts/rocket_params.gd` `straight_flight_distance` / `spread_transition_distance` |
| 火箭弹发射主逻辑（敌我共享扫描 + 左右逐发队列）| `scripts/aircraft/aircraft_weapons.gd` `update_rocket` / `rocket_burst_plan` |
| 单发火箭出膛（当帧机体航向 + 左右挂点 + 前向速度全量继承） | `scripts/aircraft/aircraft_weapons.gd` `_launch_rocket` |
| 火箭弹生成与 180m 直飞→320m smoothstep 展开 | `scripts/bullet_manager.gd` `spawn_rocket` / `rocket_spread_progress` / `apply_rocket_spread_step` |
| 火箭弹命中 / 伤害无衰减 / 更大判定半径 | `bullet_manager.gd` _physics_process 分支 `is_rocket` |
| 橙红尾迹 + 白色弹头绘制 | `rendering/bullet_presenter.gd` `_draw_bullet_streams` |
| 火箭弹字段（AircraftParams） | `aircraft_params.gd` `rocket: RocketParams` |
| F-86 火箭资源 | `resources/rocket_ffar.tres` |
| 敌方火箭弹 tier 资源表（V1~V8，等级成长唯一杠杆）| `survivor/survivor_data.gd:3710` ENEMY_ROCKET_TIERS → `resources/weapons/enemy_rocket_v1.tres` ~ `enemy_rocket_v8.tres` |
| └ tier 注入点（`_create_enemy` 内按等级 duplicate 挂载）| `survivor/survivor_spawner.gd:3979` ENEMY_ROCKET_TIERS |
| └ 齐射数实际取 `burst_count_max`（`burst_count_min` 目前未被读取）| `scripts/rocket_params.gd` burst_count_max / `aircraft/aircraft_weapons.gd:762` update_rocket |
| 延迟散开专项回归 / 真实渲染样张 | `scripts/tests/test_rocket_trajectory.gd`（bench `rocket_trajectory`）/ `scripts/tests/rocket_trajectory_visual_qa_runner.gd`（Visual bench `rocket_trajectory_visual`） |

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
| 武器模式切换（MISSILE/GUN） | `aircraft/aircraft_weapons.gd:896` update_weapon_mode |
| 战术偏好武器模式（带机炮回退） | `aircraft/aircraft_weapons.gd:949` _update_weapon_mode_tactical |
| 导弹打不中但机炮能打（有滞回） | `aircraft/aircraft_combat_tracking.gd:578` missile_cannot_hit_but_gun_can |
| 机炮冲锋：进入承诺判定 | `aircraft/aircraft_combat_tracking.gd:611` should_commit_gun_pass |
| 机炮冲锋：冲锋完成判定 | `aircraft/aircraft_combat_tracking.gd:619` is_gun_pass_finished |
| 航点/编队机会火控（不写 combat_target，20Hz） | `aircraft.gd` 三档 formation early-return → `aircraft/aircraft_weapons.gd` update_formation_passive_missile（spec waypoint-fire-control） |
| 导弹发射主逻辑 | `aircraft/aircraft_weapons.gd:1004` update_missile |
| 导弹阻断日志（被锁/RNG/能量等原因） | `aircraft.gd:2942` _log_msl_block |
| 齐射空手日志（auto_fire 实际值 + 各过滤踢除计数） | `aircraft.gd:2962` _log_salvo_skip |
| 单枚/齐射共享发射提交与一轮 cooldown/reload | `aircraft/aircraft_weapons.gd:1241 _emit_missile` / `aircraft/aircraft_weapons.gd:1271 _finish_main_missile_cycle`；包装入口 `aircraft/aircraft_weapons.gd:1232 _fire_missile_at` |
| 多目标齐射（有效锁数截断 + 正常冷却） | `aircraft/aircraft_weapons.gd:1282 _fire_multi_lock_salvo` · `aircraft/aircraft_weapons.gd` `_salvo_fire_count` |
| 飞机导弹发射纪律（档案 skill/jitter、稳定窗口、共享两轮前置点、预测包络） | `combat_params.gd` `missile_skill` / `missile_skill_jitter`；`aircraft/aircraft_weapons.gd` `_missile_skill` / `_has_stable_launch_window` / `_has_lead_intercept_solution` / `missile_lead_point`；`ai/tactical/bfm_intent.gd` `_missile_engage_pos`（未出弹 lead / 出弹后 crank）；`missile_manager.gd` `_compute_lead_launch_heading`；`aircraft/aircraft_combat_tracking.gd` `envelope_pass_at` |
| 最优目标选择（评分） | `aircraft.gd:3026` _select_best_missile_target |
| 射程包线检查 | `aircraft/aircraft_combat_tracking.gd:632` is_in_missile_envelope |
| 导弹阶段判定（接近/照射/保持） | `aircraft.gd:2243` _get_missile_phase |
| 是否应该用机炮 | `aircraft.gd:2270` _should_use_gun |
| Crank 状态查询 | `aircraft.gd:2281` is_cranking |
| 导弹射程（像素） | `aircraft.gd:2215` _missile_range_px |
| 有效导弹射程=min(导弹,雷达)像素 | `aircraft.gd:2225` _effective_missile_range_px |
| 有效射程（像素） | `aircraft.gd:2237` _effective_range_px |
| 导弹飞行物理+PN制导 | `missile.gd:264` _physics_process |
| 导弹低空制导衰减 | `missile.gd:870 _guidance_degradation` |
| 导弹生成 | `missile_manager.gd:123` spawn_missile |
| 飞机导弹前置出筒（相对机头 ±60°；地面/舰载/VLS 隔离） | `missile_manager.gd` `_compute_lead_launch_heading`；`MissileParams.launch_toward_target` 保留 HOBS 直指目标例外 |
| 导弹命中检测 + 连锁弹头直穿 | `missile_manager.gd:436` _physics_process |
| 连锁弹头逐弹去重 + 命中后直飞 | `missile.gd` continue_after_penetration / already_penetrated |
| 连锁弹头发射快照/去重回归 | `tests/test_weapon_behavior.gd` _test_chain_warhead_snapshot |
| 在飞导弹查询 | `missile_manager.gd:260` has_active_missile_at |
| 近炸引信 AOE 生成 | `missile_manager.gd:647` _spawn_aoe |
| AOE 区域更新+伤害 | `missile_manager.gd:672` _update_aoe_zones |
| AOE 红圈渲染 | `rendering/explosion_presenter.gd` `_draw_aoe_zones`；状态宿主 `missile_manager.gd` `_draw` |
| 仅大型飞机使用的四条结构解体路线与全场爆点面/棱合批真实渲染回归 | `missile_manager.gd` `spawn_airframe_wave` `_spawn_hit_flash` `_update_hit_flashes` → `rendering/explosion_presenter.gd` `hit_flash_draw_packet` `hit_flash_cube_packet` / `aircraft_destruction.gd` `destruction_size_class` `_large_breakup_route` `_emit_airframe_wave` / `tests/hit_flash_visual_qa_runner.gd`；Visual bench `hit_flash_visual` |
| 弹跳目标查找 | `missile_manager.gd:834 _find_bounce_target` |

## 热诱弹/反制

| 功能 | 位置 |
|------|------|
| 热诱弹系统更新（含失误判定） | `aircraft/aircraft_flares.gd:58` update |
| 释放热诱弹（target_missile 可选，针对性释放）| `aircraft/aircraft_flares.gd:245` release |
| 干扰成功率计算 | `aircraft/aircraft_flares.gd:520` calc_jam_chance |
| 粒子更新 | `aircraft/aircraft_flares.gd:553` _update_particles |
| 玩家/直属僚机/TEAM_ALLY 统一投焰门（完整来袭资格 + TTI≤1.0s / 200m；加力窗口暂缓；自卫/护卫复用） | `aircraft/aircraft_flares.gd` `player_flare_should_trigger` |
| 敌机小概率不投 + 1.25s 可命中 break + 有效 AI 80%→95% | `aircraft/aircraft_flares.gd` `enemy_release_fail_chance_for_configured` `enemy_flare_break_chance` / `missile.gd` `begin_enemy_flare_break` `update_enemy_flare_break` `enemy_flare_break_action` |
| 固定十枚 0.90s 六波双侧抛射 + 同帧计数 | `aircraft/aircraft_flares.gd` `_queue_visual_burst` `_spawn_wave` / `aircraft.gd` `flare_visual_burst_emitted` |
| 热诱弹聚焦、旧即时/前版/当前生存战力对照与正式 Visual 样张 | `tests/test_flare_timing.gd`（bench `flare`）/ `tests/test_flare_impact_ab.gd`（显式 bench `flare_impact_ab`，不进 `all`）/ `tests/flare_visual_qa_runner.gd`（bench `flare_visual`） |
| 失误概率 / 对头减免（FlareParams 字段） | `flare_params.gd:19-22` fail_chance / head_on_fail_reduction |
| 规避态（底层 evasion_mode：导弹来袭 S 型 + 降高度；AI 自保 + 加力模式共用的底座）| `aircraft.gd:2691` _update_evasion |
| 规避态开关（调用方：AI 自保 enter_evade / 玩家 E 键经 AfterburnerCharge.toggle） | `aircraft.gd:2303` set_evasion_mode |
| 加力模式唯一状态机（WeakRef 小队快照；有能量即开/耗尽自动关/再按关闭；世界飞行指令取消后立即充能且不写速度，spec afterburner-mode） | `survivor/afterburner_charge.gd` `Phase` / `activate` / `deactivate` / `cancel_for_manual_command` / `update`；`survivor/survivor_mode.gd` `_cancel_afterburner_for_manual_control` |
| 加力窗口唯一查询/生命周期边界（全队强 buff、肉鸽技能、TORP/WMN、签名技能、HUD 共用） | `aircraft.gd` `afterburner_window_active` / `is_afterburner_mode_active` / `set_afterburner_mode_active` |
| 加力肉鸽联动消费（超频/蓄势/弹仓/雾隐/供弹） | `aircraft/aircraft_physics.gd` `effective_max_speed_kmh` / `effective_cruise_speed_kmh` / `effective_accel_mult`；`aircraft.gd` `cd_rate` / `_update_evasion`；`aircraft/aircraft_weapons.gd` `update_gun` |
| 加力专属载荷统一门（TORP / WMN，普通规避与物理 AB 不触发） | `aircraft/aircraft_weapons.gd` `afterburner_payload_enabled` / `update_torpedo` / `update_loyal_wingman` |
| 加力机炮 100% 闪避（绕 dodge cap 短路） | `aircraft.gd:3248` effective_dodge |
| 加力滚转甩导弹（90% → is_flare_jammed） | `missile_manager.gd:548` AB_MISSILE_DODGE |
| 加力速度地板 + 加速 ×3 | `aircraft/aircraft_physics.gd:721` AB_WINDOW_ACCEL_MULT |
| 玩家 HUD HP/加力/装填统一绿黄红进度与 0.5s 闪烁；FLR 开始 CD 且加力可用时 E 键反色提示最多 5s | `survivor/player_instrument_panel.gd` `progress_color` / `_draw_progress_bar` / `_draw_afterburner` / `_draw_weapon_row` / `_sync_afterburner_flare_hint` / `afterburner_flare_hint_on` |
| 加力充能条 + 按钮三态刷新 | `survivor/survivor_hud.gd` _update_afterburner_ui |
| 眼镜蛇机动模块 | `cobra_maneuver.gd` CobraManeuver（挂载到 Aircraft 子节点） |
| 眼镜蛇机动激活 | `cobra_maneuver.gd` activate |
| 战术机动查询（通用） | `aircraft.gd` get_maneuver |
| AI 控制器查询 | `aircraft.gd` _get_ai_controller |
| R 统一机动入口（眼镜蛇/J-Turn/胆大妄为） | `aircraft.gd:2645` try_manual_maneuver；`survivor/survivor_mode.gd:3115` KEY_R |
| 当前操控机手动 / AI 僚机自动分流 | `aircraft.gd:1092` is_manual_maneuver_controlled；`:1873` _update_cobra_skill；`:1935` _update_evasion_herbst_skill；`:1962` _update_manual_dodge_skill |
| 三种 R 机动卡池互斥 | `survivor/survivor_data.gd` cobra_skill / evasion_herbst / manual_dodge 的 `excludes` |
| 手动大机动不压制自动 flare | `aircraft/aircraft_flares.gd:160` is_manual_maneuver_controlled 门 |
| 眼镜蛇后方判定（AI） | `ai_controller.gd` _is_missile_from_rear |
| 锁定免疫检查 | `aircraft.gd:3781` is_lock_immune |

## 伤害与击毁

| 功能 | 位置 |
|------|------|
| 受伤（导弹） | `aircraft.gd:3168` take_damage |
| 受伤（机炮，含闪避；返回 bool 表示是否实际结算） | `aircraft.gd:3217` take_bullet_damage |
| 内部伤害应用 | `aircraft.gd:3316` _apply_damage |
| └ 敌方护卫反应（被护送对象挨打 → 护卫同拍脱队扑攻击者） | `aircraft.gd:3481` _alert_escort_guards（`TS_DIRECTIVE` + `clear_formation` + `enter_engage_state`）|
| └ 护卫名单字段 | `aircraft.gd:362` escort_guards（登记方 `survivor/survivor_spawner.gd:2240` _spawn_flee_escort）|
| 地面撞击检查 | `aircraft.gd:3514` _check_ground_crash |
| 击毁流程与受击分区 | `aircraft.gd` `take_damage_at` `take_bullet_damage` `_start_destroy` → `aircraft_destruction.gd` `record_hit` `hit_zone_for_local` `start` |
| 所有伤害统一保留模型并旋转下坠；失控阶段不透明，终点爆炸帧仍显示机体，之后继续运动 0.85s 并连续淡出才释放；部位与局部随机改变下坠/减速/偏航/侧翻；普通机/无人机终点仅一个方框，大型有人机才有结构波 | `aircraft_destruction.gd` `destruction_size_class` `_configure_crash_motion` `update` `crash_visual_progress` `_update_crash_visual_state` `_update_post_breakup_linger` `_emit_terminal_breakup` `_large_breakup_route` `_stop_trail`；`aircraft_renderer.gd` `draw_aircraft_icon_destroyed` `draw_aircraft_icon`；权威 spec `docs/specs/systems/aircraft-destruction-presentation.md` |
| 命中结算共享边界 | `weapon_hit_resolver.gd` `can_accept_unit_hit` / `resolve_unit_hit`；调用方 `bullet_manager.gd` `_apply_projectile_damage` `_physics_process` `_explode_airburst_shell`、`missile_manager.gd` `_physics_process` `_update_aoe_zones` `_apply_aoe_damage`、`equipment/railgun_equipment.gd` `_apply_hitscan_damage`、`equipment/laser_equipment.gd` `_apply_laser_effect` |
| 小型导弹被 CIWS/激光/电磁炮拦截的 HP 与终态 | `missile.gd:544 take_intercept_damage` / `missile.gd:555 destroy_from_intercept`；调用方 `bullet_manager.gd` / `equipment/laser_equipment.gd` / `equipment/railgun_equipment.gd` |
| 坠毁终态真实释放、体型/部位/随机与缩放/透明度回归 | `tests/lifecycle_gauntlet_runner.gd` `_test_all_damage_kinds_enter_aircraft_crash` `_test_unified_aircraft_breakup` `_test_hit_location_crash_response` `_test_large_aircraft_structural_breakup`；Visual 时间片 `tests/hit_flash_visual_qa_runner.gd` `_ready`；bench `lifecycle_gauntlet` / `hit_flash_visual` |
| 基类伤害 | `combat_unit.gd:287` take_damage |

## 雷达系统

| 功能 | 位置 |
|------|------|
| 雷达锥判定（飞机） | `aircraft.gd:3579` is_in_radar_cone |
| 雷达锥判定（地面单位） | `ground_unit.gd:301` is_in_radar_cone |
| 雷达锥判定（SAM，360°） | `sam_unit.gd:105` is_in_radar_cone |
| 全局锁定计算循环 | `main.gd:198` _update_radar_locks |
| Aircraft 主雷达 shooter 能力门（主 AAM/railgun/对空 laser；副槽独立） | `aircraft_params.gd` `has_lock_capable_weapon` → `main.gd` / `survivor/survivor_mode.gd` `_update_radar_locks`；hover 主锥在 `aircraft.gd` `_draw_impl` 共用 |
| 生存模式雷达 ROE 候选预分桶 | `survivor/survivor_mode.gd` `_rebuild_radar_target_buckets` → `_update_radar_locks`；HOSTILE 只遍历非 HOSTILE，PLAYER/ALLY 只遍历 HOSTILE，最终仍走 `is_hostile_to` 防御校验 |
| 敌机传感器隐形 / 反隐技能 | `aircraft_params.gd` `sensor_stealth_enabled` → `survivor/sensor_stealth_controller.gd` `observe` / `finish_radar_tick` / `_counter_stealth_extended_contact` / `_revealed_by_counter_stealth` / `_held_by_ghost_buster` / `release_player_sensor_refs_batch` / `_target_is_in_batch`（5s 失联、1000px 近距揭露、反隐 120% 扩距、被锁/交战现形、同 tick 合批；Variant 边界净化玩家 combat/commanded 与 AI current 的已释放引用）→ `aircraft.gd` `set_sensor_contact_hidden` / `set_counter_stealth_revealed` / `set_combat_target` / `sync_stealth_trail_emission`；同向渐变命令幂等，透明度走 CanvasItem 调制，完全隐形非任务目标停止常规 redraw，但 AI/物理/机动/武器及通用 LOD 频率不受隐身状态影响；光学 cloak 周期覆盖见 `ace_squad.gd` `_cloak_update`，击杀队级 +10 HP 见 `skill_hooks.gd` `dispatch_on_kill` / `sync_ghost_buster_team_hp_bonus`；其余观察者门、导演、导弹、Radar/TGT 与尾迹沿用原链；跨帧抗体见 `tests/lifecycle_gauntlet_runner.gd` `_test_sensor_release_with_freed_target_caches` |
| 低空锁定速率衰减 | `main.gd:300` _lock_rate_for_target（静态方法） |
| 玩家可见被锁状态过滤 | `combat_unit.gd` `tracks_player_lock_state` / `accumulate_player_lock_state` → `main.gd` / `survivor/survivor_mode.gd` `_update_radar_locks`；AI↔AI 的 `radar_targets` 保留，但不写锁框/玩家反应状态 |
| 雷达数据链共享 | `radar_station.gd:35` _update_datalink |

## AI 控制器

| 功能 | 位置 |
|------|------|
| AI 主循环 | `ai_controller.gd:532` _physics_process |
| └ 写入 aircraft.tactical_aggression（effective_skill×aggression）| `ai_controller.gd:200` |
| 有效技能（压力衰减） | `ai_controller.gd:1065` _effective_skill |
| 压力更新 | `pilot_personality.gd:131` update_stress |
| 漂移/判断失误 | `pilot_personality.gd:188` update_drift |
| Simple AI（UAV用） | `ai_controller.gd:1376` _process_simple |
| Simple / drone / kamikaze / 机炮共用追击点几何 | `ai/pursuit_geometry.gd` `closing_time_lead_point` / `projectile_lead_point`；消费方 `ai_controller.gd` `_process_simple` / `_process_drone_engage` 与 `ai/tactical/bfm_intent.gd` `_gun_lead_point` |
| └ 护驾长机失效检测（Sentinel 坠毁）| `ai_controller.gd:384-390` |
| └ 绕长机飞行分支（orbit_squad_leader）| `ai_controller.gd:397` |
| └ 护驾战斗脱离（tether check）| `ai_controller.gd:436-451` |
| Simple AI 交战 | `ai_controller.gd:1927` _try_engage_simple |
| └ 护驾过滤（目标必须在 tether 内）| `ai_controller.gd:530-536` |
| orbit_squad_leader 导出变量 | `ai_controller.gd:59` |
| 绕长机飞行常量 | `ai_controller.gd:66-69` ORBIT_RADIUS=400/ANGULAR_SPEED=0.22/SPEED_RATIO=0.85/TETHER=550 |
| 巡逻逻辑 | `ai_controller.gd:1983` _process_patrol |
| 编队跟随逻辑 | `ai/squad_coordination.gd:28` process_squad_follow |
| └ 协同攻击触发（反应延迟） | `ai_controller.gd:639` 块内 |
| 掩护扫描（队友后方） | `ai/squad_coordination.gd:330` scan_leader_rear |
| BVR 狙击模式（F-47 专用） | `ai_controller.gd` `bvr_only` 标志 → `_process_engage` 距离检查；机动与武器纪律由 TacticalPlanner 输出 |
| TacticalPlanner 滞回重置 | `aircraft.gd` `reset_tactical_plan_state`（字段所有者）；`ai_controller.gd` `reset_tactical_plan`（目标切换/特殊机动等调用入口） |
| 被追 → Herbst 触发 | `ai_controller.gd` `_process_engage` 内独立于 bvr_only 的后半球检测 + `get_herbst().activate()`；模块自身再检查次数/flare 门 |
| 协同齐射广播 | `ai_controller.gd` broadcast_salvo + process_salvo |
| 赫尔贝特轮机动 | `herbst_maneuver.gd` HerbstManeuver（DECEL→TURN 180°→ACCEL，15s 冷却；默认可重复，profile 可限次数与 flare 分层） |
| 光学隐形（F-47） | `aircraft.gd` is_cloaked / _cloak_alpha → _draw() 淡出 + is_lock_immune() + missile.gd 丢失制导 |
| └ 隐形索敌过滤（各通路） | `ai_controller.gd` _current_target 失效判定 / _try_engage_simple / _try_engage_in_tether_range / 神风扫描；`ai/squad_coordination.gd` scan_squad_nearby_enemy + scan_leader_rear；`ai/target_selection.gd` disengage BOSS 再交战；`aircraft/aircraft_weapons.gd` update_secondary_radar；`aa_gun_unit.gd` 扫描 |
| **交战速度治理**（绕圈死结） | `ai/tactical/engagement_speed_governor.gd` EngagementSpeedGovernor — `R = V²/(g√(n²−1))` 反解速度上限，地板=角点速度；接线在 `aircraft.gd` `TacticalPlanner.plan()` 之后一行；`Situation.max_g` 为其新增字段（经 `effective_max_g()` 注入） |
| **属性感知狗斗画像** | `ai/tactical/situation.gd` `_recompute`（双方转率/角点半径/滚转/减速 → BALANCED/ENERGY/TIGHT）→ `ai/tactical/tactical_planner.gd` `_apply_dogfight_energy_management` + 5b/5b.2/侧翼/僚机角色消费 → `ai/tactical/bfm_intent.gd` `_apply_squad_lateral_offset`（spec engagement-discipline §C） |
| **玩家高位自然高度带**（PREFER_CLIMB 8400m 中心、错相慢漂移、转弯掉高；敌机不变） | `ai/tactical/situation.gd` `is_player_squad` / `altitude_variation_phase` → `ai/tactical/bfm_intent.gd` `_apply_player_altitude_preference` / `player_high_hold_altitude_m`（spec command-wheel §2.5.2） |
| └ 治理回归测试 | `tests/test_speed_governor.gd`（`--bench=speed_governor`，14 断言：7 公式 + 7 裸物理步进 sim 对照） |
| └ 狗斗成长沙盒 | `tests/test_dogfight_growth.gd`（`--bench=dogfight_growth`：六档机动 build × 当前/属性感知候选 planner × 三种开局；机炮解算窗/尾位/能量/盘旋半径 A-B） |
| └ **减速迟滞**（王牌执行失误） | `ai/tactical/engagement_speed_governor.gd` `apply_with_lag()` — 每次新进入治理区掷一次骰，25% 概率延迟 0.6~1.2s 才压速 → 冲过头。状态 `_ace_decel_lag_latched` / `_ace_decel_lag_timer` 在 `aircraft.gd`（spec wraith-squadron §2.4） |
| **BOSS 登场→接战统一契约** | `events/boss_encounter_event.gd` — spawn 后从 `BossRegistry.banner_metadata_for()` 注入身份并播放 `<boss_id>_arrival`；先播系统入侵横幅，Wraith / CSG / Goose 退场后切主体，Black Star 因根机仍在 30km 隐藏而不切固定锚点特写；镜头回玩家后立即 ENGAGED；缺序列或被 UI 转场覆盖均 fail-open 接战并亮血条；ENGAGED 后猎手持续追玩家（spec ui-transition §2.0 / boss-hunter-doctrine） |
| **Black Star / Hyper-A 双根分裂 BOSS** | `survivor/hyper_a_boss.gd`：双根 `1→2→4→8` 节点账本、G1 首次隐藏下降 / 40–50s 循环再入 / 越过 15km 时解除主副目标、雷达锁存、旧追击点与雷达余辉 / 7–10s 高空等待（HUD 保留 30km 高度倒数）/ 活动序列暂停其它倒数并至少错峰 12s / AOE、四代独立饱和齐射标记与武器静默、G0 全向锁定 / 离轴齐射、G1 普通前向发射、共享物理减速对线后冲刺、终点 `900m / 110° / 45` 急刹扇形冲击波、火箭 / 6s SLOW 散热、分裂与胜利门；`aircraft/aircraft_weapons.gd` 消费 Hyper-A 独立齐射 / G0 全向豁免两层许可；`survivor/hyper_a_threat_overlay.gd` 同源画危险圆 / 由近到远生长的攻击线 / 线满后急刹预警扇区与扩散波 / 冲击；资源 `enemy_hyper_a_g0..g3.tres` + `hyper_a_missile.tres`；spec `bosses/hypersonic-splitter` |
| └ Black Star 正式接入 / 状态栏 / Debug | `survivor/boss_registry.gd` `BLACK_STAR` → `events/boss_encounter_event.gd` `_spawn_hyper_a/_on_hyper_a_root_descent_started/_set_arrival_player_visual_hidden` → `survivor/survivor_spawner.gd` `_spawn_boss`；双根真实下降信号分别驱动 `BLACK STAR-01/02` 无线电，第一根倒数以 `Aircraft.META_PRESENTATION_FORCE_HIDDEN_VISUAL` 隐藏玩家绘制；树 HUD 走 `boss_encounter.gd get_hud_entries` → `survivor_hud.gd _format_custom_boss_entries`；九场景在 `boss_debug_select.gd BOSS_LIST` |
| └ Black Star 回归与压力 | `tests/test_hyper_a_boss.gd`（bench `hyper_a`，107 项）；`survivor_mode.gd` bench `boss_hyper_a_arrival` / `boss_hyper_a` / `boss_hyper_a_dash` / `boss_hyper_a_brake_wave` / `boss_hyper_a_g0_weapons` / `boss_hyper_a_g1_entry` / `boss_hyper_a_g1_weapons` / `boss_hyper_a_lifecycle` / `boss_hyper_a_stress`；正式横幅→玩家附近下降 / 状态栏 / 无线电 Visual、G0 后向全向实弹、G1 侧向拒射 / 普通前向实弹、爬升消失时目标 / 锁存解除、高空状态栏 / 等待 / 俯冲分段与多分裂体排队错峰、冲锋对线、延迟扇区 / 急刹波实伤 Visual、16 G3 + Sentinel/5 终态由 Visual、日志与 `generation_counts` / `get_hud_entries` 输出 |
| **BOSS 通关强化分层** | `meta/career_archive.gd` `build_boss_history()` 输出完整 `defeat_counts` → `events/boss_encounter_event.gd` 在 spawn 前调用 `BossEncounter.configure_progression()`；当前只消费 0 / ≥1，≥2 保留原次数并沿用层 1（spec boss-clear-progression） |
| └ Wraith 首败后 YF-23 可选支援 | `survivor/f47_ace_squad.gd` `engage/_spawn_progression_support/support_spawn_positions/set_player_ref` + `resources/enemy_yf23.tres`；两架沿玩家→Wraith 轴在队形后方 1800px 潜伏（离玩家至少 5000px），启用传感器隐形但无永久免锁，接触建立后正常可锁定；保持 4–6km BVR，不进演出/血条/胜利判定 |
| └ LADON 护航编成 | `survivor/carrier_strike_group.gd` `escort_counts_for_progression/_build_escort_plan`；初见 0CG+2DDG+6FFG，首败后 2CG+2DDG+8FFG；`_pick_water_placement` 按本局实际 offsets 校验 |
| └ Mother Goose 型号门 | `survivor/mother_goose_boss.gd` spawn 注入 → `mother_goose_uav_swarm.gd` `variant_weights_for_progression/_roll_variant`；初见仅 MQ-109/110，首败后恢复 111/112 与 railgun 保底 |
| └ Mother Goose VLS 远距空爆 | `survivor/mother_goose_controller.gd` `vls_can_launch_at_distance/_enqueue_vls_salvo`（3000m 内停火）→ `resources/goose_vls_missile.tres`（8000m/800m/1.5s）→ `missile.gd` `distance_traveled_px` → `missile_manager.gd` `distance_airburst_ready/_detonate_distance_airburst/_spawn_aoe/_apply_aoe_damage` |
| └ MQ-111 累计反导 + 玩家同款过热 | `resources/uav_mg_laser.tres` 开启 `intercepts_missiles_directly` 并对齐 X-02 热量四参数，复用 `equipment/laser_equipment.gd` `update/_apply_laser_effect`：持续刷新减速并扣 `Missile.intercept_hp`，归零令弹体失效；回归 `tests/test_boss_progression.gd`（bench `boss_progression`） |
| └ MQ-X 绕圈根治 + 三路武器 + F-22 级隐形 | `survivor/mother_goose_boss.gd` `configure_mqx_ai`统一注入 joust 550/2600px 攻击跑 → `resources/enemy_uav_mqx.tres` 聚合 `mqx_pulse_cannon.tres` / `uav_mqx_missile.tres` / `mqx_intercept_laser.tres` 与 `sensor_stealth_enabled`；回归 `tests/test_joust.gd` `_test_mqx_attack_run_and_loadout`（bench `joust`） |
| └ 猎手指令 verb | `events/ai_directive.gd` `PURSUE_UNIT` + `pursue(target, refresh_interval)`；执行分支 `ai_controller.gd` `_directive_pursue_unit_step`（0.5s 重取、**无抵达态**、目标失效自动释放） |
| └ 玩家引用重定向契约 | `survivor/boss_encounter.gd` `set_player_ref()` 基类虚方法；三子类各自覆写（`ace_squad.gd` / `carrier_strike_group.gd` → 转发 Poltergeist / `mother_goose_boss.gd` → 转发 controller → `ai/swarm/swarm_director.gd`）。SEAM-019 同类，猎手模型下是急性病 |
| └ 母舰巡逻环跟随玩家 | `survivor/mother_goose_boss.gd` `_patrol_center()` / `_update_patrol_follow()` — 环心=玩家实时位置，2s 重算、位移 <800px 不重下航点 |
| └ CSG 舰载机目标指派 | `survivor/carrier_strike_group.gd` `_assign_player_target()` — F/A-18 弹射即挂玩家（`acquire_target(TS_BOSS)`），舰船不猎手（物理追不动） |
| └ CSG 舰队摆位地形校验（护卫舰不落陆地） | `survivor/carrier_strike_group.gd:443` _pick_water_placement（委托 NavalPlacement 挑圆心 + 盘旋半径降级；结果写 EventLogger，仍落地则 push_warning） |
| └ 候选枚举常量 | `survivor/carrier_strike_group.gd:434` PLACEMENT_NUDGE_RADII（1800/3200 八方向）/ `survivor/carrier_strike_group.gd:437` PLACEMENT_RING_CANDIDATES（750→400→0 驻泊） |
| └ CSG 旗舰环形巡航（反"整队原地旋转"） | `survivor/carrier_strike_group.gd:34` CV_PATROL_RING_RADIUS（750 px，出生点即圆周切点）→ 写 `NavalUnit.patrol_center/patrol_radius` |
| **舰队摆位水域校验（共用）** | `naval/naval_placement.gd` NavalPlacement —— CSG 与战区海上任务共用；核心洞察：刚体整队绕圆心转 → **每艘船走的是一个同心圆**，沿这些圆细采即可精确判定，不用猜转位 |
| └ 轨道半径 / 占地半径 | `naval/naval_placement.gd:45` ship_orbit_radii / `naval/naval_placement.gd:20` fleet_reach（= 盘旋半径 + 最外圈偏移） |
| └ 落地计分（ring=0 走静止分支） | `naval/naval_placement.gd:57 score`（沿每艘船的同心轨道按 40 px 步长细采） |
| └ 挑圆心 / 降级挑摆位 | `naval/naval_placement.gd:77 pick_center`（由近及远，全水解即返回）/ `naval/naval_placement.gd:98 pick_placement`（盘旋半径由大到小降级，最后 0 = 原地驻泊） |
| └ 水域/全舰 TGT 回归测试 | `tests/test_naval_zone_water.gd:22 run`（`--bench=naval_zone_water`，26 断言：战区 E 三档 40px 复核 + 4/5/6 编成 + 真实六舰实例化 + 旗舰速杀负例 + 缩编/fallback + CSG 锚点） |
| **战区海上任务舰队** | `survivor/zone_mission.gd:1666 _spawn_naval_formation`（4/5/6 艘；先规划后实例化；`land_hits != 0` 绝不创建）/ `survivor/zone_mission.gd:1765 build_naval_target_roster`（安全方案全舰 TGT）/ `survivor/zone_mission.gd:1778 safe_naval_plan`（缩圈→逐艘减护卫→单旗舰→零舰船退化为空战） |
| └ 编成/几何常量 | `survivor/zone_mission.gd:1609 NAVAL_FLEET_COMPOSITIONS` / `survivor/zone_mission.gd:1622 NAVAL_RING_RADIUS` / `survivor/zone_mission.gd:1624 NAVAL_RING_CANDIDATES` / `survivor/zone_mission.gd:1630 NAVAL_ESCORT_OFFSETS`（1★/2★/3★ 占地 2150/2228/2512） |
| **战区空军边缘入场** | `survivor/zone_mission.gd` `_zone_air_spawn_origin` / `_tag_zone_air_ingress` → `_spawn_air_squadron` / `_spawn_zone_defenders` / `_spawn_sentinel_garrison`；抵达清标 `survivor/survivor_spawner.gd` `_tick_zone_air_ingress`；离屏冻结豁免 `survivor/survivor_mode.gd` `_update_offscreen_lod` |
| └ 聚焦回归 | `tests/test_zone_air_support.gd` `_test_visible_spawn_deadlock_recovery` / `_test_hostile_zone_edge_ingress`（纯空战恢复带、静态目标可见门、边界外入口、朝向、LOD meta 生命周期、三条正式消费路径） |
| └ 猎手回归测试 | `tests/test_boss_hunter.gd`（`--bench=boss_hunter`，117 断言：PURSUE_UNIT 执行分支/无归巢/世界边缘软收容+40px 物理硬护栏+ace_support 撤离负例/KNIGHT-SNIPER 角色/死 meta 清除/热诱弹 4 命/瞄准误差开门/减速迟滞） |
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
| └ tier 回归测试 | `tests/test_ace_tier.gd`（`--bench=ace_tier`，80 断言：成员/缩放/HP cap/残血保证/打标/profile 表/固定两槽边界与倒拨锁存/呼号保留/留档/四曲随机 one-shot/自然曲终恢复/缺资源安全门/母版导出隔离/主菜单曲加载） |
| **王牌编成 profile 注册表 / TTK 预算** | `survivor/ace_squad_profiles.gd` AceSquadProfiles — 七队单点登记；六支非宿敌 210s 第一槽同池，`scheduled_wave_count` 给出 3:30 / BOSS 前 3:00 两个固定槽，`build_run_order` 新局洗牌；`defeat_units` / `estimated_ttk_s` 统一量化 60~90s；`reserve_callsigns`。**加新王牌中队 = 本表加一行** |
| └ 非 BOSS 王牌编成（profile 驱动） | `survivor/ace_support_squad.gd` AceSupportSquad — element 解析 + profile 专属机炮资源；`gun_lancer` 给 WhiteTea 配逐机 joust、4×5 受控短梭与单次 flare 后 J-turn |
| └ 骑士掠袭战术 | `survivor/lancer_squad_tactics.gd` LancerSquadTactics — CHARGE→VOLLEY→EXTEND 三态机 + `assign_targets` round-robin 分配；只管 `ace_tactics_owned` 成员 |
| └ 王牌事件（无线电/血条/留档/弹尽撤离/实测 TTK） | `events/ace_reinforcement_event.gd` — `battle_bar_info()` 支持 Debug 仅强制显示、不污染 `_battle_joined`/TTK；正式事件仍首次交火亮条并起计时 |
| └ 新局调度 | `survivor/survivor_mode.gd` `_prepare_ace_run_order` / `_update_ace_support_event` — 固定 3:30 / BOSS 前 3:00 两槽，无放回洗牌、连续两局首队防重复；同场占用时第二槽待触发且单向锁存，终态 +60s 倒拨不关槽、无冷却 |
| └ 宿敌 ORION | `events/orion_nemesis_event.gd` OrionNemesisEvent — 独立轨道调度（survivor_mode `_update_orion_event`）+ 成长档位表 `tier_for`/机号 `designation` + 生涯计数（CareerArchive `get_orion_kills`） |
| └ 王牌/宿敌回归测试 | `tests/test_lancer_squad.gd`（`--bench=lancer_squad`，52 断言：固定第一槽、静态注册表跨局清理/profile/分配/混编解析/ORION 档位/真物理掠袭 sim） |
| └ 眼镜蛇王牌分层门 | `cobra_maneuver.gd` `activate()` — `AceTier.is_ace && flares>0 → 拒绝`（flare 耗尽后解锁，tier §3.4） |
| └ 王牌线框徽章 | `meta/ace_emblem_icon.gd` AceEmblemIcon — 七队几何图形（含 WhiteTea 三茶叶 J 钩；血条代号旁 + 图鉴页）；静态绘制仅变更时重画 |
| **敌人图鉴**（spec career-archive §2.6） | `meta/enemy_codex.gd` EnemyCodex — 条目注册表 + 5 分组 + 计数分派 + 完成度；BOSS 段与 `BossRegistry.BOSS_DEFS` 对齐四项并含 Black Star；`is_unlocked` 统一呈现判定，`debug_set_unlock_all` 仅本次运行覆盖。**加新敌人在此加一行** |
| **游戏信息手册**（spec career-archive §2.7） | `meta/game_info_codex.gd` GameInfoCodex — 7 分组 47 条机制说明；`tip` 字段复用 `tactical_map._TIP_KEYS` 译文（单一数据源）。**加机制说明在此加一行** |
| └ 资料库页面（两分类页签） | `meta/archive_ui.gd` + `scenes/archive.tscn` — 共享 CRT 白色终端页；敌人图鉴走 `EnemyCodex.is_unlocked`（0 杀默认剪影，Debug 可覆盖），游戏信息全文开放 |
| └ 机型标识唯一源 | `survivor/survivor_spawner.gd` `type_tag_of()` / `all_type_tags()`（enemy_type meta / 档案键 / 无线电白名单 / 图鉴共用） |
| └ 逐型地面计数 | `meta/career_archive.gd` `record_ground_kill(tag)` / `get_ground_kills_by_type()`（sam/aa/radar） |
| └ tier 调用点 | `survivor/survivor_spawner.gd` 缩放块 + `_create_enemy` 末尾打标；`survivor/survivor_mode.gd` 离屏冻结 + 预算排队两处 LOD 豁免 |
| 王牌中队基类 | `survivor/ace_squad.gd` AceSquad — 通用飞机类 BOSS 框架（角色分配/隐形/force_engage）+ 世界边缘软收容 `_update_boundary_recovery`（2000px 触发→3000px 安全带，40px 触线前硬钳；不是锚点 leash） |
| F-47 王牌小队 | `survivor/f47_ace_squad.gd` F47AceSquad extends AceSquad — 具体战斗参数 + 齐射（Herbst 已转移到 F-14） |
| F-47 隐形系统 | `ace_squad.gd` `_should_enter_cloak` / `_cloak_enter` / `_cloak_update` / `_cloak_exit` / `_has_close_player_contact` — 首次及每次结束后严格 60s CD、可重复、无紧急提前触发 / 5.5s 隐形 / 1.0s 淡入淡出 / 当前玩家 1000px 内禁止或打断 |
| 交战主逻辑 | `ai_controller.gd:2037` _process_engage |
| └ 长机目标丢失宽限（防抖动） | `ai_controller.gd:748` |
| └ 长机目标超射程宽限 | `ai_controller.gd:764` |
| 导弹规避流程 | `ai/missile_evasion.gd:30` process_evade |
| 进入规避 | `ai/missile_evasion.gd:91` enter_evade |
| 退出规避 | `ai/missile_evasion.gd:134` exit_evade |
| 尝试进入交战（含引力交战地板） | `ai/target_selection.gd` try_engage |
| 自动目标超杀即时让路（机炮优先豁免；只禁补弹、不换目标） | `aircraft/aircraft_weapons.gd` TEAM_OVERKILL → `ai_controller.gd` request_overkill_retarget → `ai/target_selection.gd` reevaluate_target |
| 目标重评估（含引力地板脱离 ×2） | `ai/target_selection.gd` reevaluate_target |
| 脱离交战（重置小队交战标志与长机丢目标宽限） | `ai/target_selection.gd` disengage |
| 战场引力上下文（三带判据/引力曲线/交战地板/可行性门常量） | `ai/objective_context.gd` 全模块（`is_objective` / `is_survival_threat` 为 `Variant` 生命周期边界，先拒绝已释放引用；spec battlefield-gravity；生存模式填充在 `survivor/survivor_mode.gd` _update_objective_context；回归 `tests/test_target_selection.gd` G6b） |
| 来袭导弹检查 | `ai/missile_evasion.gd` check_incoming_missile / find_nearest_incoming_missile |
| 规避入口分层门（flare 优先不脱队） | `ai/missile_evasion.gd` should_enter_evade（B1，2026-07-03） |
| 控制意图仲裁（pursuit/speed/AB 写入权收口） | `aircraft/control_intent.gd` + `aircraft.gd` submit_intent/_resolve_intents（Phase 1，2026-07-04） |
| 小队雷达距脱离豁免（协同/自主交战继续由 squad leash 约束） | `ai_controller.gd` `is_range_disengage_exempt` / `_process_engage`；长机丢目标仍用 `LEADER_TARGET_LOST_GRACE` |

## 编队系统

| 功能 | 位置 |
|------|------|
| 阵型偏移计算 | `squad.gd:146` get_formation_offset |
| 僚机世界坐标 | `squad.gd:209` get_wingman_target |
| 阵型循环 | `squad.gd:241` cycle_formation |
| 长机继任原子修复（全员 AI.squad / index / formation leader 缓存） | `squad.gd:81` cleanup / `squad.gd:115` _sync_member_bindings；接管回调 `survivor/survivor_mode.gd` _on_squad_leader_changed |
| 生成友方编队 | `main.gd:324` _spawn_friendly_squad |
| 生成敌方编队 | `main.gd:371` _spawn_enemies |
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
| 自由交战搜索范围 | `ai_controller.gd` SQUAD_FREE_SCAN_RANGE=1500px（自由交战只接管约 3km 内靠近敌机） |
| 小队防游走 leash | `ai_controller.gd` `_apply_constraints` 僚机越界 break-off（SQUAD_LEASH_DIST=1800/HYSTERESIS=0.5）；`_cmd_engage_active` 让跟打长机玩家点名目标高于普通归队（squad-cohesion §3.2 / rts-command §3.2） |
| 狂化病毒（僚机动态门 / FREE 锁定 / 禁主动切控 / 机动-CD / 击杀嗜血） | `aircraft.gd` `is_berserk_virus_wingman` / `enforce_berserk_virus_free_mode` / `cd_rate`；`aircraft/aircraft_physics.gd` `_g_buff_mult` / `base_roll_rate` / `effective_accel_mult` / `effective_decel_mult`；`ai_controller.gd` `_physics_process_impl`；`survivor/survivor_mode.gd` `_switch_control_to_slot`；`survivor/survivor_hud.gd` `_on_squad_engage_pressed`；`survivor/skill_hooks.gd` `dispatch_on_kill` |

## 地面单位

| 功能 | 位置 |
|------|------|
| 地面单位移动 | `ground_unit.gd:84` _update_movement |
| 地面自动目标选择 | `ground_unit.gd:141` _update_target_selection |
| 地面机炮战斗 | `ground_unit.gd:176` _update_combat |
| 地面机炮射击 | `ground_unit.gd:211` _update_gun |
| SAM 只对空选敌 / 导弹发射 | `sam_unit.gd:28` _update_target_selection / `sam_unit.gd:51` _update_sam_missile |
| AA 炮塔转向 | `aa_gun_unit.gd:74` _update_turret |
| AA 目标选择（最近敌机；拒绝地面单位） | `aa_gun_unit.gd:31` _update_aa_target_selection |
| 雷达站数据链 | `radar_station.gd:35` _update_datalink |
| 战略硬目标（不可锁定；仅 bomber_bomb；护送目标预刷常驻 TGT/轰炸权限提示） | `strategic_target.gd` `set_bomber_escort_objective` / `take_bomber_damage` / `_draw_bomber_escort_hint`；场景 `scenes/strategic_target.tscn` |
| 远距空爆高炮（陆基/舰载共用冻结解与偏角采样 + 火光/烟团 VFX） | `airburst_aa_unit.gd:99 sample_burst_solution` / `airburst_aa_unit.gd:119 sample_shell_solution` / `bullet_manager.gd:277 spawn_airburst_shell` / `bullet_manager.gd:703 _explode_airburst_shell` / 战区替换 `survivor/zone_mission.gd:864 _spawn_ground_garrison` |
| 车队管理 | `ground_convoy.gd:12` add_member |

## 海上单位 / 船伤害路由

| 功能 | 位置 |
|------|------|
| NavalUnit 物理主循环（含状态 tick） | `scripts/naval/naval_unit.gd:177` _physics_process |
| 移动（环形巡航 / waypoints / 编队三分支）| `scripts/naval/naval_unit.gd:303` _update_movement |
| 僚舰刚体跟随（复制 leader heading + 自注册到 `_followers`）| `scripts/naval/naval_unit.gd:354` _update_formation_follow |
| **旗舰转速上限**（治"整支舰队原地旋转"）| `scripts/naval/naval_unit.gd:376` _effective_turn_rate —— 有僚舰时 ω ≤ FORMATION_TANGENTIAL_CAP_PXS / r_max；无僚舰原样透传 |
| 位置感知伤害入口（双池：部件 + hull）| `scripts/naval/naval_unit.gd:518` take_damage_at |
| 状态过滤（船只接受 JAM）| `scripts/naval/naval_unit.gd:578` apply_status |
| 弱点暴露判定 | `scripts/naval/naval_unit.gd:588` _check_weak_point_reveal |
| 编队运动回归测试 | `tests/test_naval_formation.gd`（`--bench=naval_formation`，10 断言：环形巡航转位 ≤0.35°/s、僚舰对地 ≤12 px/s、无掉头、U-turn 兜底、单船不变） |
| 武器派发（JAM 早返）| `scripts/naval/naval_weapons.gd:56` update |
| DDG 舰载 Flak（2Hz 搜敌、三连发、6s 冷却、不拦导弹）| `scripts/naval/naval_weapons.gd:365 _update_naval_flak` / `scripts/naval/naval_weapons.gd:386 _find_aircraft_for_flak` / `resources/naval/mount_ddg_flak_s.tres` / `resources/naval/destroyer_ddg.tres` |
| 舰载 Flak hover 包线 / 挂点符号 | `scripts/naval/naval_unit.gd:822 _draw_flak_envelopes` / `scripts/naval/naval_unit.gd:925 _draw_alive_mount` |
| 子弹命中船（机炮 hull 0.15× / 弱点可磨）| `scripts/bullet_manager.gd:738` _physics_process 的 NavalUnit 分支 |
| 火箭弹命中船（hull 0.5× / 可磨弱点）| `scripts/bullet_manager.gd:738` _physics_process 的 is_rocket 分支 |
| 火箭弹 AOE 命中船 | `bullet_manager.gd:593` _explode_rocket |
| 导弹近炸 AOE 命中船（含 alt_ok 例外）| `missile_manager.gd:672` _update_aoe_zones |
| 电磁炮命中船按母舰归并（船体 + MountTarget 代理同挂 all_units → 一发多次结算）| `equipment/railgun_equipment.gd:445` _apply_hitscan_damage |
| └ 伤害归属母舰（代理 → 母舰） | `equipment/railgun_equipment.gd:510` _naval_damage_sink |
| └ 沿弹道取最靠前命中点（一发一舰只结算一次） | `equipment/railgun_equipment.gd:520` _segment_param |

## 状态效果（StatusEffects）

| 功能 | 位置 |
|------|------|
| 状态常量（INVINCIBLE/STEALTH/BLOODLUST/OVERLOAD/JAM/SLOW/FEAR）| `scripts/status_effects.gd:11-22` |
| 通用 tick（倒计时 + 写 status_jam_active）| `scripts/status_effects.gd:119` tick |
| Aircraft 专用 update（所有派生标记 + 副作用）| `scripts/status_effects.gd:140` update |
| 词条一句话说明（升级卡脚注文案 i18n key）| `scripts/status_effects.gd:107` note_i18n_key（表 `status_effects.gd:97` NOTE_I18N_KEY）|
| 技能 → 状态词条映射（keywords + EXTRA + OVERRIDE）| `survivor/survivor_data.gd:2524` status_notes_of |
| Aircraft.apply_status 覆写（UAV 滤 FEAR / OVERLOAD 钩子）| `aircraft.gd:3077` apply_status |
| NavalUnit.apply_status 覆写（只接受 JAM）| `scripts/naval/naval_unit.gd:578` apply_status |
| AOE 状态广播（fear_applies_slow 联动）| `scripts/survivor/aoe_broadcast.gd` apply_status_in_radius |
| 四词条亲和、软聚焦与终端债务纯函数 | `scripts/survivor/survivor_data.gd` compute_status_build_affinity / status_focus_multiplier / select_terminal_service_tag / pick_terminal_for_tag |
| 三轴事件接入终端 ×2/×4/第三次强制 | `scripts/survivor/survivor_mode.gd` _roll_axis_cards |
| 嗜血免机炮弹药 + Ratatat 有效机炮参数 | `scripts/aircraft.gd` bloodlust_gun_ammo_free / effective_gun_range_m / effective_gun_cone_half_angle_deg / effective_gun_fire_interval |
| StormⅠ/Ⅱ实际耗能与免费充放 | `scripts/survivor/afterburner_charge.gd` update |
| 精神错乱 / Hush / Stasis 低频事件 | `scripts/survivor/skill_hooks.gd` on_player_fear_landed / on_player_jam_landed / dispatch_on_hit |
| 火控饱和（五锁上升沿 / 单局 CD / OVERLOAD 期间 +2 锁） | `scripts/survivor/skill_hooks.gd` try_fire_control_saturation → `scripts/survivor/survivor_mode.gd` _update_radar_locks；`scripts/aircraft.gd` effective_max_locks |
| Hush 热诱弹闸门与新弹失导 | `scripts/aircraft/aircraft_flares.gd` update / release；`scripts/missile_manager.gd` spawn_missile |
| CD 速率栈（不改写运行中倒计时） | `aircraft.gd` `cd_rate` → `aircraft/aircraft_weapons.gd` / `aircraft/aircraft_flares.gd` tick 消费 |
| 云中 OVERLOAD 单一 timed 状态入口 | `aircraft.gd` `_update_cloud_state` / `apply_status`；`status_effects.gd` `CLOUD_OVERLOAD_BASE_DURATION` |
| 运行时修改器黑盒差分 | `modifier_trace.gd` `explain` / `print_report`；生存模式 Shift+F12 |

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
| 相机跟随插值 | `survivor/survivor_mode.gd:3571` _process |
| 物理主循环（总入口） | `survivor/survivor_mode.gd:3626` _physics_process |
| 选中列表清理 | `survivor/survivor_mode.gd:3909` _cleanup_references |
| 飞机列表同步 | `survivor/survivor_mode.gd:3916` _update_aircraft_list |

#### 雷达锁定
| 功能 | 位置 |
|------|------|
| 全局锁定计算 | `survivor/survivor_mode.gd:3987` _update_radar_locks |
| 近距捕获（距离归一化倍率） | `survivor/survivor_data.gd` `close_range_lock_mult` → `survivor/survivor_mode.gd` `_update_radar_locks` |
| 火控饱和五锁触发 | `survivor/skill_hooks.gd` `try_fire_control_saturation`，由 `_update_radar_locks` 在数据链合并后调用 |

#### 动态性能 / LOD / 清理
| 功能 | 位置 |
|------|------|
| 当前通用性能门（Sentinel 非权威） | `survivor/survivor_mode.gd` `_bench_force_battlefield_atmosphere_stress` / `_bench_enable_camera_patrol` / `_bench_update_camera_patrol` / `_bench_camera_patrol_summary` + `bench/bench_camera_patrol.gd` `sample`：C1 `battlefield_atmosphere_stress_36` 为 8 km 混合 draw 门；C2 `battlefield_atmosphere_stress_48_24km` 为多战线/LOD 门；3 秒预热后 18 秒确定性巡检 8/8 段，覆盖平移、缩放与旋转。海洋专项 `final_war_ocean_baseline/stress` 复用轨迹并按战线中心/横纵尺度变换；统一按 `reference/performance-guidelines.md` 运行 `Shadow Visual` |
| 帧统计与负载摘要 | `survivor/survivor_mode.gd` `_process` / bench 收尾：3s 预热后记录 avg/p1/worst/<60；`battlefield_atmosphere_experiment.gd` `stress_summary` 记录目标/存活成员/跨度/炮弹 |
| 性能热点与人口/弹丸快照 | `util/perf_buckets.gd` `format_hud_lines` / `format_full_dump`；飞机/尾迹/舰船/子弹/导弹/雷达/AI 各自 `PerfBuckets.tick/set_value/count` |
| F3 运行时详细面板 | `survivor/survivor_hud.gd` `set_performance_panel_visible` / `_update_debug_panel` → `util/perf_buckets.gd` `configure_runtime_panel` / `format_detailed_hud_lines`；最近 120 帧 avg/p95/worst/<60、引擎 Canvas/2D physics、海陆空/弹丸/HUD/系统细桶、生存主循环 cache/LOD/spawner、BOSS 阶段、技能事件、人口/调用/内存与前十 CPU 热点；只在面板可见时启用细分计时，`performance_hud_visual` 复用 C1 做真实截图 |
| Visual bench 慢帧事件关联 | `util/perf_buckets.gd` `configure_frame_trace` / `begin_render_frame` / `_update_trace_context` / `_trace_frame_percentiles` / `_trace_spike_class` / `mark_frame_event` / `format_frame_trace_dump`；上一帧 delta 与同帧工作量正确配对，最多 8 个尖峰保留前 120 / 后 30 帧，输出 p95/p99/max、保守根因及预热后全程根桶均值/活跃帧/known share；默认每 4 帧采细桶，`AGL_BENCH_FRAME_TRACE_MODE=full/off` 做 observer-tax A/B；`survivor_mode.gd` 3s 预热后启用并关联 `survivor_cache/lod/spawner`、雷达、气氛、日志、音效、无线电、技能与海陆空/弹丸负载；契约 bench `perf_trace` |
| triangle-array 共享组包/提交 | `rendering/canvas_triangle_packet.gd` `append_triangle` `append_indexed` `submit_arrays`；地图静态 packet、尾迹、爆点共用，领域缓存/LOD 各自保留 |
| 尾迹缓存与战略几何 LOD | `trail_ribbon.gd` `_process` / `geometry_point_step_for` / `_desired_geometry_point_step` / `_rebuild_cached_geometry`：父机移动只更新 identity 变换，retained Canvas 命令只在 20Hz 新采样、淡入/剔除或样式变化时重建；0.26 以下普通演员隔点构网格但不缩短路径，玩家/BOSS/Sentinel/玩家导弹豁免 |
| 战略视距 Canvas 提交 LOD | `aircraft_renderer.gd` `target_marker_detail_visible_at_scale` / `draw_target_line`（普通友军保留主线）；`missile.gd` `data_label_visible_at_scale` / `body_detail_visible_at_scale`（来袭与玩家弹豁免）；`naval/naval_unit.gd` `mount_detail_visible_at_scale` / `_draw_mounts_placeholder`（位置与损毁态仍可读） |
| 导弹尾迹八相集中批绘 | `missile_manager.gd` `register_missile_trail` 建 internal 批次子树 → `missile_trail_batch.gd` `_draw` → `trail_ribbon.gd` `append_to_missile_batch`；0.26 以下普通导弹四点构网格，玩家弹/真实来袭弹逐点豁免 |
| 绘制 RNG 隔离 | `aircraft_renderer.gd` `visual_noise01_for` / `visual_noise01`；机炮闪光、加力火焰、导弹尾焰、电磁炮抖动只读时间+实例 ID，不消费战斗全局 RNG |
| 高频飞机组件缓存 | `aircraft.gd` `_refresh_maneuver_cache` / `get_maneuver` / `get_herbst`；子节点顺序变化后失效重建；契约 bench `component_cache` |
| 导弹命中 broad-phase | `missile_manager.gd` `_rebuild_target_grid` / `_ordered_target_candidates`：每 tick 一次 UnitGrid，邻格小单位 + 全部舰船，按旧 target_list 顺序命中；契约 bench `missile_grid` |
| 纯视觉普通弹 SoA | `bullet_manager.gd` `spawn_bullet` / `_update_visual_bullets` / `total_bullet_count`：PackedArray 位置/速度/寿命，swap-remove；真实弹/火箭/CIWS 拦截不降级；大型舰船候选按射手阵营预分；契约 bench `visual_bullet_soa` / `bullet_grid` |
| 性能桶无分配 rollover | `util/perf_buckets.gd` `_process`：窗口/快照 Dictionary 双缓冲交换，避免每秒三次 duplicate |
| 玩家预测轨迹分帧预算 | `aircraft/aircraft_physics.gd` `PredictionWork` / `begin_player_path_prediction` / `advance_player_path_prediction` / `player_path_prediction_result` / `predict_player_path` → `survivor/survivor_mode.gd` `_process` → `aircraft_renderer.gd` `update_predicted_path_cache` / `prediction_display_result` / `draw_predicted_path`；360 步按 24 步/渲染帧推进，完成缓存至少间隔 200ms，显示按 4:1 抽样且 `_draw` 不推进预测；等价性 bench `predicted_path` |
| BOSS 最坏态性能门 | `survivor/survivor_mode.gd` `_bench_force_spawn_boss_wraith_stress` / `_bench_force_spawn_boss_csg_stress`：Wraith+YF-23 与强化 CSG→Poltergeist 二阶段均加 12 友军并用真实 0.20 镜头；`boss_wraith_stress` / `boss_csg_stress` 必须 `Shadow Visual` |
| FPS 采样与动态上限调整 | `survivor/survivor_spawner.gd:362` update_fps_sampling |
| 平均 FPS 查询 | `survivor/survivor_spawner.gd:383` _get_avg_fps |
| 屏幕外 AI/物理降频 | `survivor/survivor_mode.gd:4347` _update_offscreen_lod |
| 未关注普通战区 0 实体层 | `survivor/zone_mission.gd` `zone_simulation_should_activate` / `_ensure_spawned_for_active_zones`；普通 1★/2★ AVAILABLE 只保留 ZoneData，SELECTED/进入圆内/3★才生成；回归 `tests/test_offscreen_world_simulation.gd`（bench `offscreen_world`） |
| 攻克后敌机撤离与离屏释放 | `survivor/zone_mission.gd` `_begin_conquered_garrison_egress` / `_command_conquered_enemy_exit` / `_schedule_despawn` / `_flush_pending_despawn`；可见物理撤离，连续离屏 2 秒后按 5Hz/每 tick 4 架预算静默释放；回归 `tests/test_zone_air_support.gd` + `tests/lifecycle_gauntlet_runner.gd` |
| 已坠毁敌机清理 | 统一由 `aircraft_destruction.gd update/_update_post_breakup_linger` 持有释放权威；`survivor_mode` 不得按 `_destroy_timer` 旁路释放，否则大型机随机坠毁时长会触发同帧消失 |
| 远距清理（释放 Token） | `survivor/survivor_spawner.gd:3337` _update_far_cleanup |

#### 猎手系统
| 功能 | 位置 |
|------|------|
| 猎手指派主循环 | `survivor/survivor_spawner.gd:3439` _update_hunters |
| BOSS 世界边界物理硬护栏（不接管战术/火控） | `survivor/survivor_spawner.gd:3550` enforce_boss_world_boundary |
| 空闲敌机航点围绕玩家 | `survivor/survivor_spawner.gd:3644` _update_enemy_waypoints |
| 获取 AI 控制器 | `survivor/survivor_mode.gd:4491` _get_ai |
| 导弹上限查询（飞向玩家数）| `survivor/survivor_mode.gd:4663` _count_missiles_targeting_player |
| 筛选未发射敌机 | `survivor/survivor_mode.gd:4672` _get_enemies_without_active_missile_at_player |
| 敌人数统计 | `survivor/survivor_spawner.gd:3952` _count_enemies |

#### 刷怪 & Token 烈度控制
| 功能 | 位置 |
|------|------|
| 刷怪主逻辑（每波间隔/FPS闸/Token 预算）| `survivor/survivor_spawner.gd:669` _update_spawner |
| 当前 Token 预算（随等级增长）| `survivor/survivor_spawner.gd:412` _get_token_budget |
| 重算场景 Token 占用 & 每类数量 | `survivor/survivor_spawner.gd:426` _recalc_token_usage |
| 指定类型是否可生成（预算+实例上限）| `survivor/survivor_spawner.gd:438` _can_spawn_type |
| 按等级选敌机类型（概率 + Token 约束）| `survivor/survivor_spawner.gd:464` _pick_enemy_type |
| └ BOSS/事件专属机型排除（后期随机桶，F-47 / F-14 Poltergeist）| `survivor/survivor_spawner.gd:633` BOSS_ONLY_TYPES（表在 `survivor/survivor_data.gd:3515` BOSS_ONLY_TYPES）|
| 敌人作战高度分档（按机型查权重表，替代均匀 1/3 随机）| `survivor/survivor_spawner.gd:2762` pick_altitude_tier → `survivor/survivor_data.gd:3521` ENEMY_ALTITUDE_WEIGHTS + `survivor/survivor_data.gd:3567` pick_altitude_tier |
| └ 巡逻高度跟随抽到的档（经 Situation.combat_altitude_m 影响战术层交战高度）| `survivor/survivor_spawner.gd:2773` patrol_altitude_for_tier → `survivor/survivor_data.gd:3556` TIER_PATROL_ALTITUDE + `survivor/survivor_data.gd:3562` patrol_altitude_for_tier |
| AF-03 解锁/概率常量（旅途随机池入口） | `survivor/survivor_data.gd:3312` AF03_UNLOCK_LEVEL |
| AF-03 战区池入口（type 17 行） | `survivor/survivor_data.gd:3739` ZONE_ENEMY_TABLE |
| **常规敌机注册表 SSOT**（解锁/退役/Token/上限/编成/角色/冷却/阶段上限） | `survivor/enemy_pool_registry.gd` `ROWS` |
| └ 五角色权重 + 最近三队防重复选型 | `survivor/enemy_pool_registry.gd` `role_weights` / `eligible_rows` / `pick_row` |
| └ ADBS 护卫零 Token 候选池（服从解锁/退役，排除专用编成） | `survivor/enemy_pool_registry.gd` `escort_rows` → `survivor_spawner.gd` `_pick_flee_escort_type` |
| └ 敌版参数审计（无玩家资源依赖；Token 分档 HP/雷达/锁定/flare） | `survivor/enemy_pool_registry.gd` `audit_enemy_params`；bench `spawn_pool` |
| └ 57 型敌机产出路径审计（43 常规池资源/工厂 + 14 专用入口） | `tests/test_spawn_pool.gd` `_test_enemy_type_route_coverage` |
| └ 常规池数学可达性 + 响应 1/4/7/10/13 防重复蒙特卡洛产出率 | `tests/test_spawn_pool.gd` `_test_regular_pool_reachability_and_rates` |
| 玩家编队规模 → 敌方单机/双机/3–4机软倾向 | `survivor/survivor_data.gd` `pick_enemy_formation_class` / `pick_flight_size`；消费点 `survivor/survivor_spawner.gd` `_update_spawner` |
| Snowblind 特殊包（本体 + 两个动态合格护卫） | `survivor/survivor_spawner.gd` `_pick_snowblind_escort_rows` / `_spawn_snowblind_squad` |
| Snowblind 创建当帧注册 + 5Hz 显隐/滞回/跨边界停火 | `survivor/snowblind_controller.gd` `register` / `refresh_now` / `tick` / `next_reveal_state` / `_apply_concealment` / `_release_cross_boundary_targets` |
| Snowblind 单 CanvasItem GPU 连续风雪圈 + 圆心不可交互本体轮廓 + 固定飞机下层世界 Z + 0.80s 破幕/复隐过渡 | `survivor/snowblind_shroud_visual.gd` `attach` / `set_concealed`（无 `_process/_physics_process/_draw/queue_redraw`） |
| Snowblind 生成顺序层级 + 0.80s 双向渐变 Visual QA | `tests/snowblind_layer_visual_qa_runner.gd`；运行 `bench/run.cmd snowblind_layer_visual 1 180 Shadow Visual` |
| DEADAIR 特殊包（HP55 无武装本体 + 两个动态护卫；普通池与 Snowblind 互斥；3★ 来源具有单场优先权） | `survivor/survivor_spawner.gd` `_support_field_blocked` / `_spawn_deadair_squad` / `register_tier3_deadair_squad` / `retire_deadair_source`；`survivor/snowblind_controller.gd` `retire_for_priority_field` |
| DEADAIR 5Hz 累积 JAM（单位 8s；导弹 4×=2s；离圈宽限/衰减/清弹；来源退役同拍移除其自有 JAM，已永久失导弹体不倒带） | `survivor/deadair_controller.gd` `META_DEADAIR_JAM_OWNED` / `replace_with_priority` / `retire` / `tick` / `next_unit_exposure` / `next_missile_exposure` / `_tick_units` / `_tick_missiles` / `_clear_all_exposure` |
| DEADAIR 单 mesh 扫描场 + 世界八段暴露环 + 导弹尾迹插值 + Tab 场快照 | `survivor/deadair_field_visual.gd` `attach`；`aircraft_renderer.gd` `draw_deadair_exposure`；`missile.gd` `set_deadair_exposure_ratio`；`survivor/tactical_map.gd` `_draw_deadair_field` |
| DEADAIR 定向回归（阈值/阵营/地面海军/导弹/互斥/敌版/bench 静音） | `tests/test_deadair.gd` `run`；运行 `bench/run.cmd deadair 5 180 Shadow` |
| DEADAIR 主循环压力场（9 直属友机在圈 + 特殊包 + 16 额外敌机/在途弹） | `survivor/survivor_mode.gd` `_bench_force_deadair_stress`；运行 `bench/run.cmd deadair_stress 15 180 Shadow` |
| F-22 队级不同目标四锁 + 0.15s 齐射 + 12s 脱离 | `survivor/f22_multilock.gd` `register` / `allocate_unique_targets` / `tick` |
| Gripen C/E 队级三目标；Rafale/F-35 单机双目标 | `survivor/schemer_multilock.gd` `register` / `tick` / `_plan_team_three` / `_plan_per_aircraft` |
| 常规扩池原型 AI（Gladiator 持续近战 / Lancer 攻击通场 / Schemer 远距换位） | `survivor/survivor_spawner.gd` `_configure_registry_archetype` |
| 新敌机轮廓家族 / 未登记 UGC 兜底 | `survivor/survivor_spawner.gd` `_regular_silhouette_family` → `aircraft_silhouette_catalog.gd` `key_for` → `aircraft_renderer.gd` `draw_aircraft_icon` |
| 扩池专项性能场（直属9机 vs 17架 Snowblind/F-22/多锁/近远原型） | `survivor/survivor_mode.gd` `_bench_force_enemy_pool_stress`；运行 `bench/run.cmd enemy_pool_stress 20 180` |
| 狂化病毒同负载压力场（直属9机 vs 扩池17敌 + Sentinel/5护卫） | `survivor/survivor_mode.gd` `_bench_force_berserk_virus_stress` / `_bench_verify_berserk_virus_lod`；运行 `bench/run.cmd berserk_virus_baseline 15 180 Shadow` 与 `berserk_virus_stress` |
| 无头异常暂停看门狗 + 阵亡接管终局 | `survivor/survivor_mode.gd` `_bench_wall_watchdog` / `_bench_setup_survivor_death` / `_bench_update_survivor_death`；运行 `bench/run.cmd survivor_death 10 60 Shadow` |
| 单机生成（J-7 / MiG-31 / F-4E 35%）| `survivor/survivor_spawner.gd:1321` _spawn_single |
| 编队生成（MiG-29 / F-86 / MiG-23 / F-100 / A-7 / Q-5 / MQ-109 / MQ-110 / F-4E）| `survivor/survivor_spawner.gd:1362` _spawn_squad |
| 指挥 UAV 小队生成（Sentinel + MQ-109 僚机）| `survivor/survivor_spawner.gd:1546` _spawn_commander_squad |
| └ 初始漏编兜底 + 原生护卫 1Hz 脱队召回 | `survivor/survivor_spawner.gd` `_ensure_sentinels_escorted` / `_recall_detached_sentinel_escort` |
| └ 凝聚策略回归（原生护卫召回 / hunter 豁免） | `tests/test_spawn_pool.gd` `_test_sentinel_escort_cohesion` |
| F-47 BOSS 小队生成（菱形 4 架 + 登场通场） | `survivor_mode.gd` _spawn_f47_squad |
| F-47 BOSS 狙击循环更新（站位/撤退/全灭检测）| `survivor_mode.gd` _update_f47_squad |
| 创建敌机实体（参数/AI/缩放/Token meta）| `survivor/survivor_spawner.gd:2468` _create_enemy |
| └ base_params match（**新增敌人改这里**） | `:1041` |
| └ enemy_scale 适用判定 | `:1075` |
| └ no_stamina 排除 | `:1103` |
| └ type_tag 映射 | `:1108` |
| └ AI 分支（**F86:1183 / MIG31:1195 / MIG23:1208 / F100:1220 / Sentinel:1233**） | `:1157-1244` |
| 无效分队清理 | `survivor/survivor_spawner.gd:3983` _cleanup_squads |

> **敌人类型与 archetype 映射**（EnemyType enum + 适用 archetype）：
> - `UAV(0)` MQ-109（机炮）/ `UCAV(1)` MQ-110（导弹）— 无人机杂鱼，1 级一起开局，等权重 50/50
> - `F4E(23)` F-4E — 前期导弹杂鱼（有人机，无机炮），Lv1~6 单机/小队（spec enemies/f-4e）
> - `MIG(2)` MiG-29 — 主力威胁，全能 BFM
> - `INTERCEPTOR(3)` J-7 — Lancer 入门款（轻量、单机）
> - `UAV_COMMANDER(4)` Sentinel — Schemer 指挥支援；常规 Schemer 扩展见 `enemy_pool_registry.gd`
> - `F86(5)` F-86 — Gladiator 入门款（机炮+火箭弹编队）
> - `MIG31(6)` MiG-31 — Lancer 顶级（极速 3200 / 雷达弹 / 单机精英）
> - `MIG23(7)` MiG-23 — Gladiator 综合款（导弹+机炮编队）
> - `F100(8)` F-100 — Lancer 中量编队（雷达弹打带跑）
> - `SU27(9)` Su-27 — Gladiator+眼镜蛇（单机精英）
> - `A7(10)` A-7 — Lancer 亚音速攻击机（M61火神炮+祖尼火箭弹编队）
> - `Q5(11)` Q-5 — Lancer 超音速攻击机（23mm双炮+57mm火箭弹编队）
> - `F47(15)` F-47 — BOSS 王牌狙击小队（BVR 协同齐射 / bvr_only + salvo_leader）
> - `YF23(29)` YF-23 — Wraith 首败后专属可选支援（Wraith 后方潜伏、传感器隐形、无永久免锁、接触建立后正常可锁定、BVR 4–6km、固定 2 架，不进随机池）

> Token 常量表：`survivor_data.gd::TOKEN_COST` / `TOKEN_INSTANCE_CAP` / `TOKEN_BUDGET_BASE/PER_LEVEL/MAX` / `FAR_CLEANUP_DISTANCE` / `FAR_CLEANUP_INTERVAL`。设计要点：
> - 每种敌人有 Token 成本（弱 1~3，顶级可到 10）与可选实例上限；新常规池以 `EnemyPoolRegistry.ROWS` 为权威源。
> - 全局 Token 预算随等级线性增长；用来精细控制同屏战斗烈度。
> - `_update_spawner` 每 tick 重算 `_token_used`，基于场景真实状态。
> - `_update_far_cleanup` 定期静默移除离玩家 > FAR_CLEANUP_DISTANCE 的敌机，不给经验（防止养肥刷怪），自然释放 Token。

#### 击杀/经验/升级
| 功能 | 位置 |
|------|------|
| 击杀检测 & 经验奖励 & 回血（×xp_mult×sig×机体 xp_gain_mult）| `survivor/survivor_spawner.gd:3742` _detect_kills |
| 小队共享经验倍率 `2/(N+1)`（单机1.0、3机0.5、9机0.2；击杀者不独占） | `survivor/survivor_data.gd` `squad_xp_multiplier` → `survivor/survivor_spawner.gd` `_apply_squad_xp_share` |
| 每名僚机 +3 Token、抬热度地板；真实等级与热度共同决定响应等级 | `survivor/survivor_data.gd` `squad_token_bonus` / `response_level`；`survivor/roe_director.gd` `heat_floor_for_level` |
| 猎手在直属小队内按当前承压最少、再按最近分配目标 | `survivor/survivor_data.gd` `least_pressure_target_index` → `survivor/survivor_spawner.gd` `_update_hunters` |
| 玩家升级回调（基础斗士/骑士/策士三张；已购机体适配时 15% 普通第四卡）| `survivor/survivor_mode.gd` `_on_player_leveled_up` → `_roll_axis_cards`；普通候选唯一过滤/轴分组 `survivor/survivor_skill_catalog.gd` `normal_candidates` / `candidates_by_axis`；适配权益仍由 `SurvivorData` / `MetaShop` 决定 |
| 升级选中与生效（技能入账 + 普通 +1 轴点）| `survivor/survivor_mode.gd` `_apply_upgrade_choice` / `_on_upgrade_selected` → `survivor/survivor_skill_catalog.gd` 单机/重放投影 → `survivor/survivor_player.gd` `apply_upgrade_to` → `survivor/survivor_skill_effects.gd` `apply`；队级自动状态 `survivor/survivor_skill_runtime.gd` `sync_team_state` |
| 机场留机装备专属技能 / 进化互斥终态 | `survivor/survivor_mode.gd` `_open_evolution_offer` / `_on_settlement_signature` / `_on_settlement_evolution` |
| 玩家死亡 | `survivor/survivor_mode.gd:5350` _on_player_died |

#### 4 级金卡软 pity

| 功能 | 位置 |
|------|------|
| 倍率 `1+3.5m` / 本轮 3～4 张普通卡后清零或累加 / 奖励与机场专属渠道隔离 | `survivor/survivor_data.gd` `CLASSIFIED_PITY_WEIGHT_PER_MISS` / `classified_pity_weight_multiplier` / `classified_pity_next_misses` / `pick_card_for_axis`；`survivor/survivor_mode.gd` `_classified_pity_misses` / `_roll_axis_cards` |

#### 生涯档案（spec career-archive，2026-07-26）
| 功能 | 位置 |
|------|------|
| 档案 AutoLoad（schema/记录 API/成就/写盘） | `meta/career_archive.gd` 全文件 |
| 入档守卫（bench/boss_debug 排除） | `survivor/survivor_mode.gd:6571` archive_enabled |
| 空中击坠入档（归因过滤+enemy_type 键） | `survivor/survivor_spawner.gd:3742` _detect_kills（空中/地面两分支各一处 record 调用） |
| 停机计数 | `survivor/survivor_mode.gd:6439` _on_dock_docked 头部 |
| BOSS 接战/击败入档 | `survivor/survivor_mode.gd:6683` on_boss_engaged / `:6754` on_boss_victory |
| BOSS 轮换 + 通关次数 history 注入 | `survivor/survivor_mode.gd:6660` _update_boss_phase → `events/boss_encounter_event.gd` `_start`（spawn 前注入 `defeat_counts`） |
| 轮换算法（纯函数） | `survivor/boss_registry.gd` `pick_for_map` / `pick_by_rotation` / `rotation_candidates` |
| BOSS 显示名与登场横幅元数据 | `survivor/boss_registry.gd` `name_key_for` / `banner_metadata_for` → `events/boss_encounter_event.gd` `_try_play_arrival_cinematic` |
| 结算面板 BOSS 名（"XX 已被击毁"） | `survivor/boss_registry.gd` `name_key_for` → `survivor/survivor_hud.gd:2176` show_victory（boss_id 空 → 通用文案） |
| 忠诚僚机奖池门控（构造时注入；缺键 fail-closed） | `survivor/zone_data.gd:829 _assign_reward`（武器子池过滤）+ `survivor/survivor_mode.gd:6557 _build_reward_roll_context`；回归 `tests/test_zone_rewards.gd:189 _test_achievement_reward_gate` |
| 成就 toast | `survivor/survivor_mode.gd:6576 _on_achievement_unlocked` |
| 删存档登记 | `main_menu.gd:366` _on_reset_save_pressed 内 CareerArchive.debug_reset |

#### 生涯商店、专属许可与起手解锁（spec career-shop + aircraft-signature-progression + airfield-sam-network）
| 功能 | 位置 |
|------|------|
| 商店账本（学说/基础商品/AWACS/四项战斗支援/41 专属许可） | `meta/meta_shop.gd:345 is_awacs_entitled`；`meta/meta_shop.gd:349 is_zone_air_support_entitled`；`meta/meta_shop.gd:352 is_zone_ground_support_entitled`；`meta/meta_shop.gd:356 is_ace_f15_support_entitled`；`meta/meta_shop.gd:360 is_airfield_sam_entitled` |
| 商店四分页 + 专属已知/??? 双密度界面 | `meta/meta_shop_ui.gd:77` _add_page / `:130` _build_signature_page；共享 CRT 白色终端页，场景 `scenes/meta_shop.tscn` |
| AWACS 正式局权益消费点 | `survivor/survivor_mode.gd:6038 _update_ally_events` |
| 起手机门控 | `survivor/survivor_select.gd` `_effective_list` / `_unlock_hint_for`（正常八卡：既有四架沿用原门控，新增四架读取局外采购；Boss Debug 改读 T4 参考节点） |
| 停靠送僚机门控 + 首停上新 toast | `survivor/survivor_mode.gd:6439` _on_dock_docked 内 |
| 战区时长 +30s 注入 | `survivor/survivor_mode.gd` _ready 内（WARZONE_PHASE_DURATION 已 const→var） |

#### 噪声/绘制
| 功能 | 位置 |
|------|------|
| 地形噪声初始化 | `terrain_renderer.gd:61` _init_noise |
| 主 _draw 入口 | `terrain_renderer.gd:76` _draw |
| 地形类型判定 | `terrain_renderer.gd:83` _get_terrain_type |
| 地形单元绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 网格绘制 | `terrain_renderer.gd:162` _draw_grid |

### survivor_tutorial.gd — 首次存档与僚机操作教程

| 功能 | 位置 |
|------|------|
| 新存档基础教程（E 加力 / 双击突击 / 三架教学轰炸机结算） | `survivor/survivor_tutorial.gd`；输入接线 `survivor/survivor_mode.gd` `_unhandled_input` / `_execute_left_click` |
| 首次僚机数字键教程（固定号机提示 / 成功切控后永久消失） | `survivor/survivor_wingman_tutorial.gd`；触发与完成 `survivor/survivor_mode.gd` `_maybe_start_wingman_switch_tutorial` / `_first_switchable_wingman_slot` / `_switch_control_to_slot` |

### pause_menu.gd — 暂停菜单（spec pause-menu，2026-07-28）

| 功能 | 位置 |
|------|------|
| ESC 分流（开面板 / 结算态直退 / 选卡中不响应） | `survivor/survivor_mode.gd:3048` _unhandled_input |
| 创建 + 接线（bench 跳过） | `survivor/survivor_mode.gd:496` |
| 确认退出回调（不结算功勋） | `survivor/survivor_mode.gd:5367` _on_pause_quit_to_menu |
| 退出序列（clear_all + stop_music + 切场景） | `survivor/survivor_mode.gd:5374` _quit_to_main_menu |
| 打开（hard_pause 走 panel_in） | `survivor/pause_menu.gd:54` open |
| 关闭＝继续作战（解暂停走 panel_out） | `survivor/pause_menu.gd:56` close |
| 面板构建 | `survivor/pause_menu.gd:75` _build_ui |
| 按钮回调 | `survivor/pause_menu.gd:153` _on_resume_pressed / `:157` _on_quit_pressed |

### survivor_player.gd — 玩家状态（127 行）

| 功能 | 位置 |
|------|------|
| 信号 leveled_up | `survivor_player.gd:7` |
| 经验累加/升级触发 | `survivor/survivor_player.gd:43` add_xp |
| 应用升级公开入口 | `survivor/survivor_player.gd` `apply_upgrade` / `apply_upgrade_to`（显式目标、当前操控机引用稳定） |
| 静态技能效果（机体属性 / 武器资源 / 运行时字段 / 玩家倍率） | `survivor/survivor_skill_effects.gd` `apply` |
| 随机池 / 归属有效层数 / 晚入队与换型重放计划 | `survivor/survivor_skill_catalog.gd` 全模块 |
| 队级自动技能状态同步与新局清零 | `survivor/survivor_skill_runtime.gd` `sync_team_state` / `reset_team_state` |
| HP 查询 | `survivor/survivor_player.gd:441 get_hp` |

### survivor_data.gd — 参数表（322 行）

| 功能 | 位置 |
|------|------|
| 升级定义表 UPGRADES（常量）| `survivor_data.gd:12` |
| 刷怪基础常量（BASE/MIN/SPAWN_DISTANCE，旅途位置已弃用）| `survivor_data.gd` 刷怪参数段 |
| 增援入场常量（INGRESS_*/ANCHOR_*/PATROL_RING_*/EGRESS_*/OPENING_GARRISON，spec reinforcement-ingress）| `survivor_data.gd` SPAWN_DISTANCE 之后 |
| 增援入场逻辑（边缘生成/锚点驻空/EGRESS/开局驻防 + 冻结豁免）| `survivor_spawner.gd` INGRESS 段 + `survivor_mode.gd` LOD 冻结块 reinforcement 分支 |
| 地图扩展无头回归（几何/陆地占比/BOSS 锚点/入场纯函数）| `scripts/tests/test_map_expansion.gd` |
| 三图外缘空域 SSOT（60km 核心入口 / 64km 真边界 / 2.5s 倒计时 / 32px 相机内容内收 / AI 300px 转弯带） | `scripts/survivor/map_boundary.gd` `CORE_HALF_PX` `WORLD_HALF_PX` `EXIT_COUNTDOWN_S` `CAMERA_CONTENT_INSET_PX` `AI_EDGE_TURN_MARGIN_PX` / `_process`；UI 消费 `scripts/survivor/boundary_ui.gd` `on_countdown` `on_crossed` |
| └ 普通敌机与飞机 BOSS 边界纪律 | `scripts/survivor/survivor_spawner.gd` `_update_boundary_discipline` `enforce_boss_world_boundary`；`scripts/survivor/ace_squad.gd` `_update_boundary_recovery`；fear/joust 消费同一真边界与 AI 余量 |
| └ 三图覆盖 / AI / 倒计时回归与最远缩放角落 Visual | `scripts/tests/test_map_boundary.gd`（`--bench=map_boundary`，20 项）+ `bench/bench_runner.gd` `PREVIEW_BENCH_MAPS` + `survivor/survivor_mode.gd` `MAP_PREVIEW_BENCH_SCENARIOS`；Visual keys `map_boundary_crop_tokyo/desert/ocean` |
| 官方底图失败可见报错（控制台 error + 底部红色临时通知 + 旧矢量兜底）| `scripts/survivor/map_feature_renderer.gd` `_report_basemap_error` → `scripts/survivor/survivor_mode.gd` `_on_basemap_load_failed` → `scripts/survivor/zone_hint.gd` `show_error_temp`；契约回归在 `scripts/tests/test_map_expansion.gd` |
| 60km 密度调优旋钮（战区规模/token/间隔/上限/hunter 配额，spec 60km-density-pass）| `survivor_data.gd`（ground_tgt_scale 含 radar_count / ZONE_DEFENDER_* / TOKEN_BUDGET_*）+ `survivor_spawner.gd` _update_hunters + `zone_data.gd` 半径 |
| 战区雷达站 TGT + 空战中队长机高一档 + 盘旋环随半径缩放 | `zone_mission.gd`（_RADAR_SCENE / _spawn_ground_garrison 尾段 / _spawn_air_squadron leader_etype·orbit_r / _spawn_zone_defenders garrison_r） |
| 战区任务 6 秒生成 + 可见性死锁恢复（沿用画外优先/玩家抵达后放行；其中所有空中敌机独立从地图边缘入场） | `survivor/zone_mission.gd:261 _ensure_spawned_for_active_zones` / `survivor/zone_mission.gd:45 VISIBLE_SPAWN_RECOVERY_APPROACH_PX`；回归 `tests/test_zone_air_support.gd:71 _test_visible_spawn_deadlock_recovery` |
| 战区临时支援（已购授权后：每局首次 `air/squadron` 派 2/3/4 架 F-86、首次 `ground` 派 2 架 A-10；两项额度分账；ALLY、短标签、战区 leash、统一物理撤离） | `survivor/zone_mission.gd:1913 _start_air_support_if_needed` / `survivor/zone_mission.gd:2009 _try_spawn_air_support` / `survivor/zone_mission.gd:2082 _create_a10_support` / `survivor/zone_mission.gd:2134 _begin_air_support_egress` / `ai_controller.gd:962 acquire_target` 的 `air_targets_only` + `ground_targets_only` 门；测试 `tests/test_zone_air_support.gd:53 run` |
| 王牌截击支援（已购授权后：每局首次非 BOSS 王牌轮换派 Hound-1/2 两架 F-15；友军实例雷达 3000m、固定双句无线电，只对空并优先本事件王牌；事件终态物理撤离） | `events/ace_reinforcement_event.gd:190 _spawn_ally_support` / `events/ace_reinforcement_event.gd:308 _maintain_ally_support_targets` / `events/ace_reinforcement_event.gd:345 _begin_ally_support_egress` / `events/ace_reinforcement_event.gd:381 _tick_ally_support_egress`；测试 `tests/test_zone_air_support.gd:53 run` |
| └ 第三方 ALLY 击杀收益隔离（任务销毁照常；不给玩家 XP/击杀数/回血/连击/教程进度） | `survivor/survivor_spawner.gd:3742 _detect_kills` 的 `third_party_kill` |
| └ 双支援最坏压力样本 | `survivor/survivor_mode.gd` `_bench_force_zone_support`（`--bench=zone_support_stress`：Lv15 + 31 敌 + Sentinel 完整机群 + F-86×4 + A-10×2） |
| └ 对舰最坏压力样本 | `survivor/survivor_mode.gd:1979 _bench_force_naval_zone`（`--bench=naval_zone_stress`：39 架飞机 + 3★ 六舰 + 18 挂点代理，持续覆盖 VLS/CIWS/Flak） |
| └ 王牌截击压力样本 | `survivor/survivor_mode.gd:6860 _bench_force_ace_support`（`--bench=ace_support_stress`：Lv15 + 31 敌 + Sentinel 完整机群 + MARATHON×5 + F-15×2） |
| **战场流程聚合根**（净时间轴、战区关闭事务、王牌固定槽/无放回、ORION 门） | `survivor/battlefield_flow.gd` `BattlefieldFlow`：`advance_time` / `apply_time_cost` / `grant_time_extension` / `close_warzone_if_due` / `claim_next_ace_profile` / `claim_orion_if_due`；场景执行仍由 `survivor/survivor_mode.gd` |
| **BOSS 阶段闸门真源**（flow phase ∪ boss_unlocked ∪ selected==BOSS ∪ 已 spawn；子系统一律问 Mode，别直读 ZoneData）| `survivor/battlefield_flow.gd` `is_boss_phase` → `survivor/survivor_mode.gd` `is_boss_phase` / `_is_in_boss_phase` |
| └ 消费点（停摆刷怪/猎手/驻防 · 停随机奖励事件 · 停战区任务 · AWACS 提前撤离）| `survivor_spawner.gd` _is_boss_phase · `survivor/adbs_manager.gd` _physics_process 闸 · `zone_mission.gd` _is_boss_phase · `events/awacs_support_event.gd` _update 顶部 |
| └ BOSS 阶段全场撤离（画面外 free / 画面内清目标+出界航线+AB；舰船地面单位一概不动）| `survivor_spawner.gd` _update_boss_phase_purge / _begin_boss_evacuation（豁免 boss* / ace_support / ace_nemesis / parent_carrier）+ _update_boundary_discipline 的 boss_evac 豁免 |
| └ 无头回归 | `scripts/tests/test_battlefield_flow.gd`（bench `battlefield_flow`，31 断言）+ `scripts/tests/test_boss_phase.gd`（bench `boss_phase`，33 断言）|
| **BOSS 阶段 XP 总闸**（`is_boss_phase()` 从解锁/PRE_STAGE 起生效；空中+地面击杀 XP=0，仍保留击杀数/回血/连击）| `survivor_spawner.gd` `_detect_kills` 的 `boss_phase_no_xp` |
| **击杀不计价开关** `no_kill_reward` meta（全阶段无 XP / 不入生涯档案 / 不给对头永久 +max_hp；仍计击杀数与击杀回血）| 消费点 `survivor_spawner.gd` _detect_kills；打标处 `mother_goose_uav_swarm.gd` _spawn_uav + `mother_goose_boss.gd` _make_mqx + `carrier_strike_group.gd` _launch_fa18 |
| └ CSG 机库累计上限（整场 8 架，击落不退还名额）| `survivor/carrier_strike_group.gd` FA18_TOTAL_CAP / _fa18_launched_total（守卫点在 _launch_fa18 开头 + _update_fa18_periodic_launch）|
| 教程轰炸机锚点（出生点前方派生，扩图安全）| `survivor/adbs_manager.gd` TUTORIAL_BOMBER_ANCHOR |
| 城区直升机调度与探索生成（每窗 25%、整局 ≤2、活跃组互斥；距玩家 ≥12km、距边界 ≥8km 的全图城区）| `survivor/adbs_manager.gd` `city_heli_schedule_allows` / `city_heli_spawn_candidate_allowed` / `_pick_city_center`；测试 `tests/test_bomber_rotor_airburst.gd` `_test_city_heli_schedule` |
| 城区直升机全歼奖励（作战时间延长，与王牌中队全灭同一注入点 `grant_time_extension`）| `survivor/adbs_manager.gd:267` _award_city_heli_bonus |
| └ 战果轮询（与 _detect_kills 同模式；逃出地图被回收不算不阻塞）| `survivor/adbs_manager.gd:247` _track_city_heli_kills |
| └ 编队/击落计数状态 | `survivor/adbs_manager.gd:55` _city_heli_group / `survivor/adbs_manager.gd:56` _city_heli_killed |
| └ 奖励时长常量 | `survivor/adbs_manager.gd:44` CITY_HELI_TIME_BONUS_S |
| CH-47 受击散开（scatter_on_damage meta + flock_members 串联）| `survivor/survivor_spawner.gd:2304` spawn_heli_flee |
| 停靠结算（spec zone-reward-docking：DockPoint 组件/攻克全队满血+奖励入库/领奖分发）| `survivor/dock_point.gd` + `survivor_mode.gd`（_on_dock_docked / _claim_*）|
| 机场解放战区（spec airfield-liberation-zones + airfield-sam-network：3 机场敌占→解放→一次性补给点；友军基础 AA×2，已购 `support_airfield_sam` 永久授权追加一次性 SAM×1；难度=热度；F6 可立即访问进化树）| `survivor/zone_data.gd`（AIRFIELD_IDS / is_airfield / liberate_airfield / set_airfield_difficulty）+ `zone_mission.gd`（_spawn_airfield_ground / _airfield_difficulty_from_heat）+ `survivor_mode.gd`（airfield_ally_plan / _try_deploy_airfield_sam / _deploy_airfield_ally_gradual / _liberate_airfield / debug_visit_airfield）+ `meta/meta_shop.gd`（is_airfield_sam_entitled）+ `survivor_debug_zone.gd`（_on_visit_airfield）|
| 战区四类奖励 roll（航母/僚机/武器/次世代技能；A/B 每局保底各一武器一技能；航母 pity）| `survivor/zone_data.gd` RUN_GUARANTEED_REWARD_KINDS / REWARD_KIND_WEIGHTS / _assign_reward |
| F6 全战区奖励直发（15 项；绕过 roll/正式门控，技能仍守 max_stacks） | `survivor/survivor_debug_zone.gd` `DEBUG_REWARD_OPTIONS` / `_on_grant_reward` → `survivor_mode.gd` `debug_grant_zone_reward`；`skill_audit` 自动与正式数据源对拍 |
| 新地图云层 / 沙漠沙尘暴（spec weather-clouds-and-sandstorm） | `weather_system.gd` `setup(camera, deterministic_seed)` / `sandstorm_speed_kmh` / `sandstorm_progress` / `sandstorm_center_world` / `set_debug_midgame` / `sample_density` / `sample_sandstorm_density` / `sample_obscurant_density` / `_draw_sandstorm` / `_sandstorm_edge_wave` / `_draw_sandstorm_fill` / `_draw_sandstorm_streamlines` / `_draw_sandstorm_observations` / `_draw_sandstorm_front`（正式随机天气；地图 Visual bench 固定云形；官方沙漠 180km/h、10km 宽；气象图式矢量纹样、曲边 Alpha 羽化，不复用云贴图）；`ugc/map_document.gd` cloud schema；`resources/maps/*_preview.aglmap`；`aircraft.gd` `_update_cloud_state`（focused bench 注入同一 WeatherSystem 验真实对象状态）；`survivor_mode.gd` `_cached_is_in_cloud` / `debug_skip_to_midgame`；`missile.gd` 云中累计失导；`missile_manager.gd` `get_in_cloud` / 命中 miss；`survivor_debug_zone.gd` `_on_skip_midgame`；bench `weather` / `map_raster_tokyo` / `map_raster_desert` / `map_raster_ocean` |
| 战区奖励说明文案（Tab 面板奖励名下方一行；技能类=技能介绍）| `survivor/zone_data.gd` REWARD_WEAPON_DESC_KEYS / reward_desc_key + `tactical_map.gd` _refresh_info（reward_desc）+ i18n `REWARD_*_DESC` |
| 友军航母（南入北上/甲板 DockPoint/限 2 次/友军专属 300 hull/击沉清零；敌方 CV 资源仍 1200）| `survivor_mode.gd:6135 _summon_reward_carrier` / `survivor_mode.gd:6209 _depart_friendly_carrier` |
| 玩家触发的友军设施区域仇恨（机场 2000px/航母 2500px 激活；1 Hz；H→Q 限额；8s 退出；`SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED`）| `survivor/friendly_asset_aggro.gd:76 tick` + `ai_controller.gd:989 TargetSource` / `ai_controller.gd:955 get_target_source` / `ai_controller.gd:962 acquire_target` + `combat_unit.gd:74 META_FRIENDLY_ASSET_GROUP` + `naval/mount_target.gd:38 _ready`；测试 `test_friendly_asset_aggro.gd:10 run` |
| 逃跑组护卫编队（adds 语义、普通 XP；独立零 Token 选型；运输机作移动长机、WEDGE 220m、首机阵亡换锚）| `survivor/survivor_spawner.gd` `_pick_flee_escort_type` / `_new_flee_escort_squad` / `_spawn_flee_escort` |
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

### commander_aura.gd — 指挥 UAV 光环

**设计要点**：
- 招募范围内的 UAV 加入小队（上限 MAX_WINGMEN=5 僚机）
- 可从**其它普通 UAV 编队中"挖人"**（检查 `ai.orbit_squad_leader` 排除其它指挥小队）
- 小队成员保持 `simple_ai=true`，通过 `orbit_squad_leader` 围绕 Sentinel 飞行
- **不再指派目标**（无 _designate_target）；僚机通过 `_try_engage_simple` 自主扫描并攻击靠近的敌方
- buff 聚焦机动/速度/攻击欲望（不加技能/冷静，simple_ai 用不上）
- buff 强度：+6G、结构 +7G、滚转 ×2.5、速度 ×1.5、加速 ×3、失速 ×0.5；只写 Aircraft 运行时字段，不改 params
- 每 0.5s 全量重算“当前小队成员 ∧ 半径内”，单 owner 仲裁；离队、越界和节点退出均撤除

| 功能 | 位置 |
|------|------|
| 主循环（扫描+招募+buff） | `survivor/commander_aura.gd:44` _physics_process |
| 增益扫描（全量重算小队∧半径） | `survivor/commander_aura.gd` _scan_and_buff |
| 应用 buff（运行时 G/结构/滚转/速度/加速/失速字段）| `survivor/commander_aura.gd` _apply_buff |
| 移除单个 / 全部 buff | `survivor/commander_aura.gd` _remove_buff / _remove_all_buffs |
| 招募新成员（允许从普通编队挖人）| `survivor/commander_aura.gd` _try_recruit |
| 析构时清理 | `survivor/commander_aura.gd` _exit_tree |
| 查找 AI 控制器 | `survivor/commander_aura.gd` _find_ai |

### commander_overlay.gd — 指挥机视觉覆盖（~80 行）

| 功能 | 位置 |
|------|------|
| 颜色常量 | `commander_overlay.gd:10-13` |
| 坠落淡出时长常量 | `commander_overlay.gd:15` DESTROY_FADE_DURATION |
| 绘制（坠落时按 _destroy_timer 淡出） | `commander_overlay.gd:27` _draw |

### survivor_hud.gd — HUD

| 功能 | 位置 |
|------|------|
| UI 构建 | `survivor/survivor_hud.gd` `_build_ui` |
| 主循环与分层刷新 | `survivor/survivor_hud.gd` `_process` / `HUD_DATA_REFRESH_INTERVAL` / `_update_hud_data_layer` |
| 玩家 HUD 框板本局首次两闪 | `ui/hud_first_reveal_sequencer.gd` `register_panel` / `register_callback_panel` / `set_panel_available` / `set_panel_sort_position` / `update`；`ui/hud_board_visibility.gd` + `resources/shaders/hud_board_visibility.gdshader` 直接切换复合控件源框板；`survivor/survivor_hud.gd` `_setup_hud_first_reveal` / `_sync_hud_first_reveal_targets` |
| UI 自适应布局（viewport 未变时不重复写静态底栏/顶部几何） | `survivor/survivor_hud.gd` `_static_layout_viewport` / `_layout_ui` |
| 右键急刹虚拟摇杆（按下减速 / 实际左右舵量 / 即时速度 / 明确标名的剩余与最大机炮弹药或 `∞` / 有效射程 / 失速锁定 / 边缘夹紧） | `survivor/brake_steering_overlay.gd` `begin` / `update_steer` / `set_stall_locked` / `set_flight_data` / `_draw` → `survivor/survivor_hud.gd` `begin_brake_steering` / `update_brake_steering` / `set_brake_steering_stall_locked` / `set_brake_steering_flight_data` / `end_brake_steering`；focused `brake_steering_ui`，Visual `brake_steering_overlay_visual` |
| 顶部粗体 `1u` 当前时间与框版战区剩余时间 | `survivor/survivor_hud.gd` `top_time_rect` / `warzone_time_rect` / `formatted_elapsed_time` / `_layout_ui`；`survivor/warzone_time_panel.gd` `formatted_remaining_time` / `grid_regions` / `_draw` |
| 全屏底部 `3u` 常驻框板与等宽侧板、三方向、剩余经验与进化就绪内部布局 | `survivor/survivor_hud.gd` `BOTTOM_BAR_HEIGHT` / `bottom_bar_rect` / `bottom_progress_rect` / `bottom_axis_rect` / `bottom_xp_rect` / `_layout_ui` / `_update_display` |
| 顶部常驻紧急通知 + 底部临时提示双滑入通道 | `survivor/zone_hint.gd` `TOP_RESERVED_HEIGHT` / `show_persistent` / `hide_persistent` / `show_temp` / `show_error_temp` / `_slide_top` / `_slide_bottom`；精英入场路由在 `events/ace_reinforcement_event.gd` |
| HP/XP/等级、状态行与三方向计数更新 | `survivor/survivor_hud.gd` `_update_display` / `_update_player_instrument` |
| 玩家 HUD 安全引用与刷新 | `survivor/survivor_hud.gd` `_safe_player_aircraft` / `_update_player_instrument` |
| 玩家模块化仪表（右锚；高度针独立重绘层；HP 上方等宽云层/击杀状态，HP/SPD 各带 0.5u 装饰行，武器装填百分比/秒数/底条） | `survivor/player_instrument_panel.gd` `AltimeterNeedleLayer` / `_draw_altimeter_needle` / `_configure_layout` / `update_status` / `cloud_status_rect` / `kill_status_rect` / `hp_decorative_rect` / `spd_decorative_rect` / `weapon_reload_percent_rect` / `weapon_reload_remaining_rect` / `weapon_reload_progress_rect` / `weapon_reload_remaining_seconds` / `weapon_name_rect` / `_draw` |
| 僚机动态行仪表 | `survivor/wingman_instrument_panel.gd` `update_display` / `_draw_row` |
| 底部三个等宽 `2u` 三方向板、`当前/8` 数字与常显 `0.5q` 点击格 | `survivor/milestone_axis_counter.gd` `update_display` / `axis_title_rect` / `axis_value_rect` / `point_rect` / `grid_regions` / `_draw` |
| 底部等级、距下一级 XP 与真实进化就绪格；升级逐板反色 | `survivor/bottom_experience_panel.gd` `update_display` / `xp_remaining` / `evolution_ready_rect` / `flash_level_up` / `flash_index_at` / `grid_regions` / `_draw`；资格入口 `survivor/survivor_mode.gd` `has_ready_aircraft_evolution`；刷新入口 `survivor/survivor_hud.gd` `_update_display` / `show_level_up` |
| 统一共享 1 物理像素网格描边（相等 setter 早退；重合边去重并合为 multiline；HUD 缩放使用 scale-invariant hairline；物理视口边缘半像素内收防裁切） | `ui/terminal_grid_overlay.gd` `TerminalGridOverlay` / `SCALE_INVARIANT_LINE_WIDTH` / `regions` / `override_regions` / `edge_insets` / `outline_segments_for` / `edge_safe_region` / `_draw` |
| 终端文字精确排版、高度优先步进扩宽与轮廓缓存 | `ui/terminal_text.gd` `TerminalText` / `FontFace` / `SizeRule` / `MAX_INK_BOUNDS_CACHE_ENTRIES` / `resolve_font_layout` / `font_size_for_ink_height` / `expanded_width_for_fixed_text` / `measure_ink_bounds`；重复 glyph contour 命中 2048 项有界缓存，bench `terminal_text` 覆盖缓存契约 |
| F7 实际 HUD 几何定位覆盖层与手动 FLR 插键测试 | `survivor/survivor_hud.gd` `toggle_ui_dev_overlay` / `_collect_ui_dev_regions` / `_on_ui_dev_add_manual_flare_pressed`；`ui/ui_dev_outline_overlay.gd` `UiDevOutlineOverlay` / `build_entries`；截图场景 `scenes/tests/ui_dev_panel.tscn` |
| E/G/F/Q/T 键、高度两态与缺失武器跳过 | `survivor/survivor_mode.gd` `_unhandled_input` / `_cycle_player_altitude_preference` / `_cycle_player_weapon_preference` |
| 战术按钮创建、tooltip 与状态刷新 | `survivor/survivor_hud.gd` `_create_tac_button` / `_on_tac_hover` / `_update_tactical_buttons` |
| 王牌中队交战血条（分段命条） | `survivor/survivor_hud.gd` `_build_ace_panel` |
| F3 详细性能面板开关与 4 Hz 文字更新 | `survivor/survivor_hud.gd` `set_performance_panel_visible` / `_update_debug_panel`；统计源见动态性能节 |
| Game Over / 通关结算画面 | `survivor/survivor_hud.gd` `show_game_over` / `show_victory`；固定尺寸白色终端板、高层压暗遮罩，失败仅保留红色危险标题 |

### 小队信息行与键盘指挥（启动条件 = 有僚机入队，与机型无关）

| 关注点 | 位置 |
|------|------|
| 旧按钮节点构建（兼容保留、固定隐藏） | `survivor/survivor_hud.gd` _build_squad_panel |
| 僚机值快照 + 信息行显隐刷新（僚机非空才显示） | `survivor/survivor_hud.gd` _update_squad_panel |
| 独立行绘制、固定号机排序与 20Hz 刷新 | `survivor/wingman_instrument_panel.gd` update_display / _draw_row |
| C/V 键盘指挥入口 | `survivor/survivor_mode.gd` _unhandled_input → `survivor/survivor_hud.gd` _on_squad_engage_pressed / _on_squad_weapon_pressed |
| 玩家队反查（扫 `_spawner.get_squads()` 找 leader==玩家）| `survivor/survivor_hud.gd` `_get_player_squad` |
| 存活僚机列表 | `survivor/survivor_hud.gd` `_get_wingmen` |
| **玩家队装配 + 登记进 spawner 队表**（唯一入口，幂等）| `survivor/survivor_mode.gd` `_ensure_player_squad` |
| 起手僚机（`wingman_count>0`，仅 F-14 走）| `survivor/survivor_mode.gd` `_spawn_starting_wingmen` |
| T0 起手机机场等价礼包（MiG-21 机炮吊舱 / F-104C FFAR / J 35F QAAM / EA-6B ESM） | `playable_aircraft.gd` `starting_benefit_id` → 选机说明 `survivor/survivor_select.gd` `STARTING_BENEFIT_NAME_KEYS` / `_build_aircraft_card` → 授予 `survivor/survivor_mode.gd` `_grant_starting_benefit` / `_claim_weapon_reward` → 继承 `survivor/survivor_player.gd` `record_special_weapons` / `remount_weapons`；回归 `tests/test_player_params.gd` / `tests/test_zone_rewards.gd` / `tests/ui_iteration_visual_qa_runner.gd` |
| 懒建队消费方：+1 僚机奖励 / 停靠送僚机 / 双子星克隆 | `survivor/survivor_mode.gd` `_claim_wingman_reward` |
| 固定数字键查询与操控角色权限转移（`squad_slot` 不随换帅变化；`use_tactical_preference` 随当前操控机转移） | `survivor/survivor_mode.gd` _aircraft_for_squad_slot / _switch_control_to_slot / `_set_player_aircraft` |
| 回归测试（bench squad_cmd_ui，28 断言：登记/幂等/HUD 反查/固定号机/长机阵亡解绑竞态/操控角色权限）| `tests/test_squad_command_ui.gd` run |

### survivor_upgrade_ui.gd — 升级选择界面（最多四卡）

| 功能 | 位置 |
|------|------|
| 信号 upgrade_selected | `survivor/survivor_upgrade_ui.gd` `upgrade_selected` |
| UI 构建（4 列预建；3/4 卡统一 `240×300`）| `survivor/survivor_upgrade_ui.gd` `_build_ui` |
| 填充介质标签（技能/稀有度/三轴/限定；浅色软盘稀有度章为 11px 亮字 + 实体深底；高档光盘与 shader 强度）| `survivor/survivor_upgrade_ui.gd` `populate` |
| 低档软盘 / 高档光盘实体几何（只按状态重绘；软盘底部无圆形轴孔）| `survivor/upgrade_media_surface.gd` `configure` `_draw_floppy_media` `_draw_optical_media` |
| 明确代价句危险红 + hover/focus 词条独立旁注（卡组右侧、空间不足切左，不覆盖卡面） | `survivor/survivor_upgrade_ui.gd` `_description_bbcode` `_set_note_revealed` `_note_popup_position` |
| 出入场元素表（标题 + 可见卡列）| `survivor/survivor_upgrade_ui.gd` `get_transition_elements` |
| 全卡读写扫描 / CLASSIFIED 闪边 / `0.80s` 入场输入保护 / 卡带保持不透明并垂直压缩写入 `0.055s` → 卡列退场 `0.04s`（无连线、脉冲、横移与透明拖尾） | `survivor/survivor_upgrade_ui.gd` `_schedule_input_unlock` `_unlock_choice_input` `schedule_entry_flashes` `_play_media_boot` `_play_border_flash` `_on_choice_pressed`；`resources/presentation/sequences.json` `upgrade_out` |
| └ UI 回归与真实画面 | `tests/test_status_notes.gd`（bench `status_notes`，50 断言）/ `tests/upgrade_media_visual_qa_runner.gd`（Visual bench `upgrade_media_visual`，正式经验/三轴条 + 基础三卡/机体适配第四卡来源条/浅色稀有度章/无重叠旁注/扫描/输入锁） |

### 技能归属分流（spec skills-720-rework T1）

| 功能 | 位置 |
|------|------|
| 归属字段文档（scope/classes/milestone_plus） | `survivor/survivor_data.gd:79` 附近 UPGRADES 头注释 |
| scope 查询 | `survivor/survivor_data.gd:2485` upgrade_scope |
| 品类数组查询 | `survivor/survivor_data.gd:2550` upgrade_classes |
| "+1 轴进度"目标轴查询 | `survivor/survivor_data.gd:2557` milestone_plus_of |
| 王牌字段型 stat 白名单 | `survivor/survivor_data.gd:2579` ACE_FIELD_STATS |
| 归属生效纯谓词 | `survivor/survivor_data.gd:2593` upgrade_applies_to_machine |
| 品类身份映射表 | `survivor/evolution_system.gd:81` CLASS_IDENTITY_BY_CATEGORY |
| 档案 → 品类身份 | `survivor/evolution_system.gd:95` class_identity_of_profile |
| 定向应用（借指针走同 match） | `survivor/survivor_player.gd:387` apply_upgrade_to |
| 王牌剥离（切控迁移逆操作） | `survivor/survivor_player.gd:394` strip_upgrade_from |
| "+1 轴进度"加成（cap=2） | `survivor/survivor_player.gd:148` add_milestone_bonus |
| 里程碑进度=点+加成 | `survivor/survivor_player.gd:162` get_milestone_progress |
| 队存活成员枚举 | `survivor/survivor_mode.gd:4962` _squad_members_alive |
| 单机品类身份（meta profile_id） | `survivor/survivor_mode.gd:4884` _class_identity_of |
| 队品类并集（卡池门控） | `survivor/survivor_mode.gd:4984` _squad_present_classes |
| 升级归属分流入口 | `survivor/survivor_mode.gd:4994` _distribute_upgrade |
| 普通技能一次性动作（忠诚僚机立即部署） | `survivor/survivor_mode.gd` _dispatch_regular_oneshot |
| "+1 轴进度"发放点 | `survivor/survivor_mode.gd:5101` _grant_milestone_plus |
| 生效子集 meta 重建 | `survivor/survivor_mode.gd:5112` _refresh_squad_effective_stacks |
| 王牌字段技切控迁移 | `survivor/survivor_mode.gd:5125` _migrate_ace_field_upgrades |
| 新僚机入队补挂 build | `survivor/survivor_mode.gd:5141` _apply_build_to_new_member |
| 验收测试（bench skills720） | `tests/test_skills_720.gd:21 run`；`tests/test_skills_720.gd:584 _test_today_full_build_loadout`（今日 13 张/19 层在非 A-10 同机满层共存） |
| 全量生效/文案/收益/Debug 可达性审计（bench skill_audit） | `tests/test_skill_audit.gd` run / `_test_debug_surface_coverage` |

> **技能系统总入口 → [skill-implementation-index.md](skill-implementation-index.md)**（配置字段 × 实装八模式 ×
> 全 stat 消费点速查）。下面按批次的段落只是历史行号锚点，"某技能代码在哪"优先查那份索引。

### 720 批 T3 钩子（僚机阵亡/弹尽/AB 充能/轮盘联动/停靠）

| 功能 | 位置 |
|------|------|
| 备用弹仓（弹尽概率回满） | `survivor/skill_hooks.gd:412` try_gun_reserve_mag |
| 近距捕获（合并副武器后的装填期免耗弹窗口） | `survivor/skill_hooks.gd:429` in_free_missile_window |
| QAAM 强化合并嗜血 / 适应回能（击杀钩子内） | `survivor/skill_hooks.gd:210` 附近 dispatch_on_kill 720 批段 |
| AB 充能静态引用注入 | `survivor/skill_hooks.gd:266` afterburner |
| 僚机阵亡 watcher（0.5s 沿检测） | `survivor/survivor_mode.gd:5162` _tick_squad_watch |
| 复仇之战/刺客复仇/黑匣子分发 | `survivor/survivor_mode.gd:5215` _on_squad_member_down |
| 奖励升级队列/呈现 | `survivor/survivor_mode.gd:5232` _queue_bonus_upgrade |
| 防守此区区域清剿（逐机领目标/击杀接续/越界回防） | `rts/squad_command_controller.gd` `_tick_guard` / `_end_guard`；验收 `tests/test_wheel_orders.gd` D 段 |
| 保卫阵地圈内 buff 维护 | `rts/squad_command_controller.gd:726` _update_guard_zone_buff |
| 阵地转移/保卫阵地/座舱护甲减伤 | `aircraft.gd:3316` _apply_damage 720 批段 |
| 撤离/防守物理注入 | `aircraft/aircraft_physics.gd:578` _g_buff_mult 与 EVAC_SHIFT_SPRINT_BONUS |
| QAAM 击杀归因（kind="qmaam"） | `missile_manager.gd:123` spawn_missile is_secondary |
| 对头击杀经验 ×1.5（历练） | `survivor/survivor_spawner.gd:2514` 附近 headon_xp 段 |

### 720 批 T5 新机制（胆大妄为/机炮吊舱/电磁炮双发/导弹二段）

| 功能 | 位置 |
|------|------|
| R 统一机动（眼镜蛇/J-Turn/胆大妄为） | `aircraft.gd:2645` try_manual_maneuver |
| 胆大妄为动作（i-frame + 滚转 + 投焰） | `aircraft.gd:2676` do_manual_dodge |
| R 键输入入口 | `survivor/survivor_mode.gd:3115` KEY_R 分支 |
| 禁自动 flare 门 | `aircraft/aircraft_flares.gd:125` manual_dodge_active 早退 |
| 机炮吊舱两道翼挂 | `aircraft/aircraft_weapons.gd:392` 附近 gun_extra_barrels 分支 |
| 电磁炮双发补射 | `equipment/railgun_equipment.gd:134` followup_pending 分支 |
| 导弹二段推进（续推+渐强） | `missile.gd:101` _second_stage_g_mult 与动力阶段 elif |

### 722 批机体签名技能 + 50 机专属槽

| 功能 | 位置 |
|------|------|
| 数据表 42 条 sig_* + F-14 围猎特例 | `survivor/survivor_data.gd:1747` sig_f15 起 |
| milestone_plus 数组化 | `survivor/survivor_data.gd:2559` milestone_plus_list_of |
| apply 专用分支（722 段） | `survivor/survivor_skill_effects.gd:414 sig_relaxed_stability` 起 |
| 技能杂项 tick（CD/VIFFing/近太空/三发推力/超速截击） | `aircraft.gd:1774` _update_sig_skills |
| 超速截击选目标（机头前半球 + 当前雷达锥双硬门） | `aircraft.gd:1835` _sig_mig31_pick_target |
| STEALTH 上升沿装填（先敌开火） | `aircraft.gd:3112` _sig_f22_reload_all |
| 隐身多锁齐射消费点 | `aircraft.gd:3135` effective_max_locks |
| 致死拦截（钛浴缸/复活判序） | `aircraft.gd:3397` _try_sig_death_save |
| 负面状态免疫早退（电战预算） | `combat_unit.gd:166` apply_status（头部 sig_status_immune 早退） |
| 全频段压制流速（被锁敌负面 ×0.6） | `status_effects.gd:113` sig_x13_active + tick 内 x13_suppress |
| 锁定管线集中注入（6 技 + viggen 出锥 grace） | `survivor/survivor_mode.gd:3987` _update_radar_locks（722 段在 in_cone/出锥两分支） |
| 一次性特判（f47/x02/ax00） | `survivor/survivor_mode.gd:5039` _dispatch_sig_oneshot |
| 签名 drone 生成（f47/x90，不进离屏 despawn 体系） | `survivor/survivor_mode.gd:5081` _sig_spawn_loyal_drone |
| 联合突击差量重算 | `survivor/survivor_mode.gd:5191` _update_sig_gcap |
| 奖励僚机生成体（双子星复用；尾部 build 补挂） | `survivor/survivor_mode.gd:6309` _spawn_reward_wingman |
| 鲸群血量均摊 | `survivor/skill_hooks.gd:73` whale_pod_share |
| 作战云广播（中继直通防双乘） | `survivor/skill_hooks.gd:96` broadcast_combat_cloud |
| 三发推力触发（突击命令两入口） | `survivor/skill_hooks.gd:116` try_trigger_j36_assault |
| 特殊机动完成事件（急停/落叶飘） | `survivor/skill_hooks.gd:173` on_special_maneuver_done |
| EA-18G 伴随压制（复用全体存活僚机共锁交集，持续 JAM） | `survivor/survivor_mode.gd` `_update_radar_locks` 内 F-14 / EA-18G 共锁段 |
| F/A-XX 穿透打击（仅当前 ACE 本机机炮击杀，5s STEALTH / 20s CD） | `survivor/skill_hooks.gd` `dispatch_on_kill`；`aircraft.gd` `_sig_faxx_cd` |
| f35 越肩发射豁免 | `aircraft/aircraft_weapons.gd:1218` _sig_f35_relay_ok |
| 夜枭静默弹过滤（规避+投焰单点覆盖） | `ai/missile_evasion.gd:262` sig_silent 过滤 |
| 超越地平重索敌 | `missile.gd:571` _sig_find_retarget |
| 验收 bench（43 已实装 + 7 空占位与机场渠道隔离） | `tests/test_sig_skills.gd` `_test_offer_rules` / `_test_new_signatures`；--bench=sig_skills |
| **50 机专属槽 + F-14 特例 + 7 占位** | `survivor/survivor_data.gd` `SIGNATURE_PLACEHOLDERS` / `signature_upgrade_id_for_aircraft` / `signature_upgrade_for_aircraft` / `is_signature_placeholder` / `is_signature_upgrade` |
| **占位不可购买 / 装备 / 阻断出击** | `meta/meta_shop.gd` `signature_item_known` / `signature_nodes`；`survivor/evolution_ui.gd` `show_offer` / `_build_signature_card` |
| **普通升级与奖励池统一排除签名技** | `survivor/survivor_data.gd` `is_normal_random_candidate`：默认排除签名技与 NEXT_GEN，金色 CLASSIFIED 封顶；`zone_data.gd` `_nextgen_candidates` 只显式放行 NEXT_GEN；普通消费点 `survivor_mode.gd` `_roll_upgrade_choices` / `_roll_axis_cards` |
| **机场留机 / 进化二选一调度** | `survivor/survivor_mode.gd` `_current_evolution_node_id` / `_open_evolution_offer` / `_on_settlement_signature` / `_on_settlement_evolution` |
| **机场专属技能视觉与逐机陈列** | `survivor/evolution_ui.gd` `_build_signature_card` / `_build_evolution_card`；`survivor/evolution_detail_panel.gd` `_build_signature` |
| **基础三卡 + 机体适配普通第四卡介质** | `survivor/survivor_upgrade_ui.gd` `populate` / `get_transition_elements` / `schedule_entry_flashes` |

### 728 批 三轴里程碑全队下发（spec evolution-attribute-gates）

| 功能 | 位置 |
|------|------|
| 策士 3 点 XP 玩家级乘区（不按飞机数重复） | `survivor/survivor_player.gd:129` milestone_xp_multiplier |
| 2/3/4/6/8/10 基准里程碑表 | `survivor/survivor_data.gd:3069` MILESTONE_TABLE（斗士 6 点 `max_g +2.0`） |
| Tab 里程碑数值格式（闪避百分比 / G 一位小数） | `survivor/tactical_map.gd:1607` _fmt_milestone_value |

> 语义：里程碑加成**跟玩家不跟机体，且下发全队**（与 UPGRADES 归属分流一致）。
> 记账从玩家级单账本改为**逐机记账**，换帅/换型/晚入队都由构造保证不丢不叠。

| 功能 | 位置 |
|------|------|
| 逐机记账 meta 键 | `survivor/survivor_player.gd:242` MILESTONE_RECORD_META |
| 记账读 / 写（无飞机时落孤儿本） | `survivor/survivor_player.gd:245` _milestone_record / `survivor/survivor_player.gd:252` _set_milestone_record |
| "当前操控机那本账"属性视图（tactical_map 量表读法不变） | `survivor/survivor_player.gd:93` applied_milestones |
| 下发目标提供器（未注入 = 只有当前操控机） | `survivor/survivor_player.gd:101` milestone_targets_provider |
| └ 目标解析 | `survivor/survivor_player.gd:259` _milestone_targets |
| └ 注入点（注 `_squad_members_alive`） | `survivor/survivor_mode.gd:596` milestone_targets_provider |
| 跨档下发（加点后，逐机幂等） | `survivor/survivor_player.gd:273` apply_crossed_milestones_to |
| 全量补挂（新僚机入队 / 僚机换型） | `survivor/survivor_player.gd:289` apply_all_milestones_to |
| └ 新僚机入队调用点 | `survivor/survivor_mode.gd:5155` apply_all_milestones_to |
| 清账重挂（换型；**每机恰好一次**，重复调用会叠两遍） | `survivor/survivor_player.gd:303` reapply_all_milestones_to |
| └ 进化换型调用点（对 `_squad_members_alive()` 逐机） | `survivor/survivor_mode.gd:5869` reapply_all_milestones_to |
| 定向生效（借 self.aircraft 指针走同一 match，同 apply_upgrade_to 手法） | `survivor/survivor_player.gd:309` _apply_milestone_effect_to |
| 无头断言（E2 节：僚机同吃 / 逐机幂等 / 晚入队补挂 / 换帅不丢） | `tests/test_attribute_gates.gd:264` _test_milestone_squad_wide |

### 50 机 T0~T5 进化树与成长审计

| 功能 | 位置 |
|------|------|
| 50 节点 / 155 边 / 具体三轴门派生树 | `resources/evolution/evolution_tree.json`；设计 SSOT `specs/systems/t0-low-t1-aircraft-expansion.md` / `aircraft-evolution-tree.md` |
| 运行时门判定（仅具体三轴 + F/A-18E any）与至少一个可用出口 | `survivor/evolution_system.gd` `gates_passed` `gates_missing` `has_available_exit` |
| Boss Debug T4 参考名单、至少四机同型 Squad、等级、正式三星池 ACE 武器、gates 轴规划与技能 build；Black Star FINAL WAR 自动推进 T5 / Lv26 / 8 点并生成独立 SUPPORT 满配队与海空双方编成 | `survivor/boss_debug_builds.gd` `reference_nodes` `target_axis_points` `roll_weapon_loadout` `roll_reference_build` → `survivor/survivor_select.gd` `_boss_debug_reference_list` → `survivor/survivor_mode.gd` `BOSS_DEBUG_MIN_SQUAD_SIZE` / `_spawn_starting_wingmen` / `_setup_boss_debug_scenario` / `_final_war_promote_primary_squad` / `_setup_final_war_battlefield` / `_setup_final_war_bench_overlay` / `_bench_final_war_summary` / `_final_war_spawn_player_squad` / `_final_war_apply_support_build` / `_claim_weapon_reward` → `survivor/tactical_map.gd` `_refresh_weapon_loadout`；断言 `tests/test_attribute_gates.gd` `_test_boss_debug_reference_builds` + Visual `squad>=4` / 武器实际挂载 / Tab 同屏读数 / FINAL WAR 编成与水域；诊断 A/B 为 `final_war_ocean_baseline/stress` |
| 8 点内全分配枚举、永久不可达边=0 | `tests/test_attribute_gates.gd` `_test_evolution_gates`；bench `attr_gates` |
| 50 节点详情、pip 与 155 条正交树边 | `tests/test_evolution_detail.gd` `_test_gate_pips` `_test_tree_routes_and_current_marker`；bench `evo_detail` |
| 全树雷达 / 机炮 / 导弹局部平滑、9000 px 雷达上限与敌武器成长审计 | `tests/test_player_params.gd` `_test_evolution_edge_smoothing` / `_test_effective_radar_cap` / `_test_enemy_weapon_scaling`；bench `player_params` |
| 玩家机炮弹量五档（180/200/240/280/320）与进化装满 | `playable_aircraft.gd` `gun_ammo_override` → `survivor/survivor_playable_setup.gd` `apply` → `survivor/evolution_system.gd` `evolve`；断言 `tests/test_player_params.gd` `_test_gun_ammo_profiles` |
| 14 分钟成长单局记录器 | `tests/test_evolution_growth_benchmark.gd` `configure_from_environment` `handle_level_up` `tick` `finish`；bench `evolution_growth` |
| 320 局可恢复 Shadow 串行与无效样本补跑 | `bench/run_evolution_growth.ps1`；固定步长入口 `bench/invoke_godot.ps1` `AGL_BENCH_FIXED_FPS` |
| 成长分位数、曲线数据与经验补偿结论 | `scripts/tools/aggregate_evolution_growth.py` `group_row` `build_conclusions` `render_markdown` |

### survivor_debug_skills.gd — F4 技能与装备面板

| 功能 | 位置 |
|------|------|
| F4 开关（打开时暂停）| `survivor/survivor_debug_skills.gd:38` _unhandled_input |
| UI 构建 | `survivor/survivor_debug_skills.gd:84` _build_ui |
| 按钮样式 | `survivor/survivor_debug_skills.gd:320` _apply_btn_style |
| 三轴分组刷新（读取 axis_of_upgrade / AXIS_COLORS） | `survivor/survivor_debug_skills.gd` _refresh / _axis_title / _axis_color |
| 设置等级 | `survivor/survivor_debug_skills.gd:476` _on_set_level |
| 触发升级（+1） | `survivor/survivor_debug_skills.gd:485` _on_levelup |
| 按 ID 强制添加技能（绕过正式门控；保留 max_stacks、正式分流、milestone_plus、对应三轴 +1） | `survivor/survivor_debug_skills.gd` _on_add_skill_by_id |
| 添加选中技能 | `survivor/survivor_debug_skills.gd:513` _on_add_skill |
| 移除技能 | `survivor/survivor_debug_skills.gd:543` _on_remove_skill |
| 装备直挂（含 ESM）与审计入口 | `survivor/survivor_debug_skills.gd` `_LOADOUT_SLOTS` / `_on_loadout_changed` / `debug_skill_ids` / `debug_can_force_upgrade` / `debug_has_loadout_kind` |

### survivor_debug_spawn.gd — F5 刷怪与海陆空气氛实验面板

| 功能 | 位置 |
|------|------|
| 编队类型枚举 FormationType | `survivor/survivor_debug_spawn.gd` FormationType（含全部王牌事件项） |
| 敌机类型标签表 | `survivor/survivor_debug_spawn.gd` ENEMY_TYPE_LABELS |
| F5 开关（不暂停）| `survivor/survivor_debug_spawn.gd` _unhandled_input |
| UI 构建（下拉/规模/空战/炮战/海战/清除按钮）| `survivor/survivor_debug_spawn.gd` _build_ui |
| 类型与编队切换 | `survivor/survivor_debug_spawn.gd` _on_type_changed / _on_formation_changed |
| 刷怪按钮（普通敌机玩家附近即时生成；BOSS/王牌/Adds 保留正式事件航路）| `survivor/survivor_debug_spawn.gd` `_on_spawn_pressed`；`survivor/survivor_spawner.gd` `_debug_spawn_point` / `_set_debug_patrol`；王牌 `_start_ace_event` |
| 气氛实验模式启动与状态 | `survivor/survivor_debug_spawn.gd` _on_atmosphere_pressed / `_on_atmosphere_ground_pressed` / `_on_atmosphere_naval_pressed` / `_on_atmosphere_status_changed` |
| 清空敌人 / 导出日志 | `survivor/survivor_debug_spawn.gd` _on_clear_pressed / _on_dump_pressed |

### battlefield_atmosphere_experiment.gd — 真实局海陆空气氛实验

| 功能 | 位置 |
|------|------|
| 三类样本生成与一键清理 | `survivor/battlefield_atmosphere_experiment.gd` launch_air_battle / `launch_ground_battle` / `launch_naval_battle` / `clear_experiment` |
| 3v3 对向楔形固定翼 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_fighter_wedge |
| 2v2 现有 AH-64 + 专属地面锚 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_heli_pair / `_spawn_ground_anchor`；轮廓强制走现有 `apache`，实验参数副本移除火箭 |
| 双阵营一次性轰炸航线 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_bomber_pair |
| 3v3 火炮解析式椭圆轨道/错峰弹道 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_artillery_line / `_update_artillery_fire_control` / `_update_ballistic_shells`；轨道与外观 `survivor/atmosphere_artillery_unit.gd` |
| DDG+FFG 斜列小巡航圈与低伤害必然命中舰炮 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_naval_group / `_find_water_battle_setup` / `_update_naval_fire_control` / `_resolve_ballistic_impact`；240/120/0 px 降级，`NavalPlacement.score` 每 40px 校验完整同心轨迹；无实验鱼雷数组或逐帧制导 |
| 演员独立武器参数 ×0.10 | `survivor/battlefield_atmosphere_experiment.gd` _duplicate_and_scale_weapons |
| 画外连续开火 / 近距实伤 LOD | `survivor/battlefield_atmosphere_experiment.gd` `_prime_damage_lod` / `_update_damage_lod` / `_set_air_damage_enabled`；1500px 进入、1800px 退出，轰炸炸弹豁免 |
| 零伤害弹丸视觉快路径 | `bullet_manager.gd` `spawn_bullet` / `spawn_rocket` / `spawn_airburst_shell`：仍生成、移动、绘制，普通弹跳过近炸/建筑/单位命中，空爆弹跳过空间网格伤害查询；`missile_manager.gd` `_update_visual_only_ambient_missile`：导弹只检查既定目标并保留爆炸，不扫全体单位、不生成 AOE |
| 2Hz 实验内固定翼/旋翼机重指派 | `survivor/battlefield_atmosphere_experiment.gd:994` _refresh_assignments |
| 8–48km、24–96 名混合容量 bench | `survivor/battlefield_atmosphere_experiment.gd` launch_stress_battle / `stress_summary`；场景路由在 `survivor/survivor_mode.gd` _bench_force_battlefield_atmosphere_stress |
| Headless/Visual 真实场景样本 | `survivor/survivor_mode.gd` _bench_force_battlefield_atmosphere；bench key `battlefield_atmosphere` / `battlefield_atmosphere_ground` / `battlefield_atmosphere_naval` |

### tier-3-zone-global-threats — 3★ 战区特殊任务

| 功能 | 位置 |
|------|------|
| 全局唯一 3★ 名额（正式抽取、机场与 F6 同一闸；F6 可转移但不增加槽） | `survivor/zone_data.gd` `MAX_CONCURRENT_TIER3_ZONES` / `active_tier3_zone_ids` / `has_active_tier3` / `_tier3_allowed_for` / `debug_set_difficulty` / `debug_claim_tier3_slot` |
| 四 profile 分流、来源生命周期与“来源先灭≠任务完成” | `survivor/zone_mission.gd` `_spawn_tier3_profile` / `_register_tier3_sources` / `_update_tier3_source_states` / `_retire_tier3_unit`；信号 `tier3_threat_changed`；正式完成仍走全 TGT 判定 |
| AURORA LANCE 英文状态栏、单体 TGT、固定圆形基盘与独立旋转桁架炮架、4.0s 渐宽 + 1.5s 满宽闪烁、360m 全宽同拍 AOE、随机长机/僚机、5–88km 末端淡出预警与高速长条弹迹 | `survivor/zone_mission.gd` `_spawn_tier3_super_cannon`；`survivor/tier3_super_cannon_part.gd` `DISPLAY_NAME` / `WARNING_FILL_S` / `WARNING_FLASH_S` / `AOE_RADIUS_PX` / `_set_body_heading` / `warning_fill_ratio` / `warning_width_px` / `warning_is_flashing` / `_eligible_aim_targets` / `_choose_aim_target` / `_begin_warning` / `_fire_snapshot` / `_draw_stationary_base` / `_draw_rotating_turret` / `_update_projectile` / `cease_tier3_threat` |
| 攻城坦克 2×CIWS + 远程 SAM + 空爆挂点 | `survivor/tier3_siege_tank.gd` `arm_mounts` / `_spawn_ciws` / `_spawn_sam` / `_spawn_flak`；各挂点实现于 `tier3_siege_ciws.gd` / `tier3_siege_sam.gd` / `tier3_siege_flak.gd` |
| 攻城坦克主炮只打一同区友军气氛地面单位，一次可信直击摧毁 | `survivor/tier3_siege_tank.gd` `_nearest_atmosphere_ground_ally` / `_begin_shell` / `_update_shell` |
| 远程 VLS 只深拷贝 3★ 本舰参数，不污染普通舰队；DEADAIR 替换普通支援场并随来源同拍撤销场、累积与自有 JAM | `survivor/zone_mission.gd` `_tier3_naval_params` / `_spawn_tier3_deadair`；`survivor/survivor_spawner.gd` `register_tier3_deadair_squad` / `retire_deadair_source`；`survivor/deadair_controller.gd` `META_DEADAIR_JAM_OWNED` / `replace_with_priority` / `retire` / `_clear_all_exposure` |
| 持续 HUD 威胁、按内容分流的 Tab/开始提示与 F6 原子 profile/真伤害验收 | `survivor/zone_mission.gd` `resolve_tier3_profile` / `mission_desc_key_for` / `mission_started_fmt_key_for`；`survivor/survivor_mode.gd` `zone_mission_desc_key_for` / `zone_mission_started_fmt_key_for` / `_on_tier3_threat_changed`；`survivor/tactical_map.gd` `_refresh_info`；`survivor/survivor_debug_zone.gd` `normalize_zone_change_request` / `_apply_zone_change` / `_on_neutralize_tier3` |
| 专项契约与正式场景 bench | `tests/test_tier3_zone_threats.gd` `run`（bench `tier3_zone`）；`survivor/survivor_mode.gd` `_bench_force_tier3_zone`（`tier3_super_cannon` / `tier3_super_cannon_d` / `tier3_siege_tank` / `tier3_deadair` / `tier3_long_range_vls`，巨炮覆盖 A/D） |

### zone_atmosphere_combat.gd — 正式战区氛围战斗

| 功能 | 位置 |
|------|------|
| 普通地图每区一次性 30% 抽取并缓存、海洋群岛决战地图全覆盖；生成后登记 / 完成失败重刷取消时注销 | `survivor/zone_atmosphere_combat.gd` `ORDINARY_ZONE_CHANCE` / `DECISIVE_MAP_IDS` / `enabled_for_roll` / `cached_enabled` / `is_decisive_map`；`survivor/zone_mission.gd` `_zone_atmosphere_enabled_for_zone` / `_register_zone_atmosphere` / `_retire_zone_atmosphere` / `_retire_all_zone_atmosphere` |
| 空战零增员复用正式敌军；陆战双方固定阵营专用 SPG，并等概率覆盖无直升机/仅友军/仅敌军/双方都有四种组合；海战只补友军 | `survivor/zone_atmosphere_combat.gd` `register_zone` / `helicopter_sides_for_roll` / `_spawn_atmosphere_helicopter` / `_spawn_artillery_group` / `_find_land_artillery_plan` / `_mark_actor` / `_spawn_allied_naval`；`survivor/survivor_spawner.gd` `spawn_atmosphere_ah64` |
| 火炮港池水面排除 + 50px 连续陆地椭圆与舰队 240/120/0 全水降级 | `survivor/zone_atmosphere_combat.gd` `_find_land_artillery_plan` / `_land_ellipse_valid` / `_spawn_allied_naval`；`survivor/map_geography.gd` `is_ground_spawn_safe` / `find_ground_spawn_near`；`survivor/atmosphere_artillery_unit.gd` `configure_ellipse`（正式随机轨道）/ `configure_rail`（实验兼容） |
| 2Hz、1500/1800px 伤害迟滞、发射快照与轰炸豁免；60 HP SPG 的近距炮弹为 80px 散布、24px 直击窗、60 点致死伤害，近失/画外零伤害 | `survivor/zone_atmosphere_combat.gd` `update` / `_apply_damage_state` / `_update_artillery_source` / `_resolve_shell`；`combat_unit.gd` `ambient_damage_multiplier` |
| 玩家近距优先且只释放本系统持有的目标权 | `survivor/zone_atmosphere_combat.gd` `_update_player_priority` / `_clear_player_priority`；`ground_unit.gd` `_update_target_selection`；`naval/naval_weapons.gd` `_find_aircraft_in_range` |
| 气氛炮火不能终结正式 TGT | `combat_unit.gd` `take_atmosphere_damage`；`naval/naval_unit.gd` `take_atmosphere_damage_at` |
| 武装直升机永不攻击/命中 Aircraft，只打地面；正式地面 TGT 非致死、气氛地面可击毁；敌军直升机保留经验身份、友军无奖励 | `combat_unit.gd` `META_PROJECTILES_GROUND_ONLY` / `META_AMBIENT_TGT_NONLETHAL`；`bullet_manager.gd` `projectile_allows_target`；`survivor/survivor_spawner.gd` `spawn_atmosphere_ah64` |
| 专项契约 / 真实正式样本 | `tests/test_zone_atmosphere_combat.gd` `run`（bench `zone_atmosphere`）；`survivor/survivor_mode.gd` `_bench_force_zone_atmosphere`（bench `zone_atmosphere_formal`） |

### Optional Zone Mission — 可选战区任务（bomber_escort）

| 功能 | 入口 |
|---|---|
| A/B 在 60s+Lv3 开放；首个 optional 在 150s+Lv5 开放；整局保底 1、20% 第二次、最多 2 | `survivor/zone_data.gd` `initial_reward_unlock_ready` / `optional_mission_unlock_ready` / `release_initial_reward_zones` / `release_first_optional_mission` / `_try_open_followup_optional_mission`；`survivor/survivor_mode.gd` `_update_delayed_zone_unlocks` |
| FAILED 状态、无收益刷新、固定目标/专用航线/任务状态/动态编队缓存、150×星级专属 XP | `survivor/zone_data.gd` `mark_failed` / `bomber_escort_xp_reward` / `get_objective_center` / `get_mission_route` / `get_mission_status` / `get_zone_center` / `set_dynamic_center` |
| 广播后 6 秒生成；独立航线目录、安全陆地目标、七线统一 12500px 航程、场外直线入口、75 HP 单弹目标、3×30 HP B-1B + 2×F-4E；按局势组建截击+扫荡混编计划，轰炸编队先飞完 6% 航程才从实时航迹后方追入，32% 航程前只接近/锁定，40% 无玩家介入才按存活态补一次后方追击增援，58% 仍无玩家介入则中止 | `survivor/zone_mission.gd` `MISSION_SPAWN_RADIO_LEAD_S` / `_ensure_spawned_for_active_zones` / `BOMBER_ESCORT_ROUTE_CATALOG` / `build_bomber_escort_route` / `_prepare_bomber_escort` / `_start_bomber_escort` / `bomber_interceptor_plan` / `bomber_reserve_plan` / `bomber_route_progress` / `bomber_response_should_launch` / `_spawn_bomber_initial_response_if_ready` / `bomber_response_weapons_should_arm` / `_update_bomber_response_fire` / `should_abort_bomber_escort` / `_spawn_bomber_reserve_if_needed` / `_retarget_bomber_interceptors`；`survivor/survivor_mode.gd` `_on_zone_mission_spawn_announced` |
| 150s、每机一弹、成功优先、全灭/离场失败、在途炸弹窗口、无人护送 `abort` 转 EGRESS 与地图/截击层只读成员状态 | `survivor/bomber_mission.gd` `setup` / `abort` / `_force_egress` / `_update_outcome` / `_resolve_failure` / `get_live_center` / `get_live_heading` / `get_bombers` / `get_alive_bomber_count` / `get_alive_escort_count` / `get_phase_key` |
| 纵队槽位、自带护航与按 `{type,count,assignment}` 计划执行的初始/一次性增援后方追击编队；任务实例跳过通用边界 PATROL 接管 | `survivor/survivor_spawner.gd` `spawn_bomber_mission` / `bomber_formation_offset` / `_spawn_bomber_escort_fighters` / `spawn_bomber_interceptors` / `bomber_pursuit_spawn_positions` / `assign_bomber_intercept_target` / `_update_boundary_discipline` |
| 地图失败无痕 / OPTIONAL 类别 + 航线 + 高对比固定 TGT/HP 条/右栏轰炸机、护航机、截击机状态 + 可钳边移动纵队标记 / 准确 XP 预告 | `survivor/tactical_map.gd` `_should_hide_zone` / `_zone_primary_center` / `_draw_bomber_route_and_target` / `_draw_bomber_escort_marker` / `_refresh_info` / `_zone_id_at` |
| 成功绕过普通奖励只发专属 XP；7 秒成功通知显示 XP，无线电只报告截击/目标摧毁/编队撤离等军事态势；失败不发收益且不解释内部介入阈值 | `survivor/survivor_mode.gd` `_on_zone_mission_completed` / `_grant_bomber_escort_xp` / `_say_bomber_escort_intercept` / `_say_bomber_escort_completed` / `_on_zone_mission_failed` |
| F6 强制验收 / 真实 bench | `survivor/survivor_debug_zone.gd` `MISSION_TYPES`；`survivor/survivor_mode.gd` `_bench_force_bomber_escort_zone`；bench key `bomber_escort_zone` |

### survivor_select.gd — 正常八卡起手机 / Boss Debug T4 参考编队选择

| 功能 | 位置 |
|------|------|
| 正常局八张起手机卡（既有四架 + 四架局外采购） | `survivor/survivor_select.gd` `PLAYABLE_LIST` |
| 模式分流 / T4 动态名单 | `survivor/survivor_select.gd` `_effective_list` / `_boss_debug_reference_list` |
| UI / 机型卡片构建（固定全息窗 + 三列卡片） | `survivor/survivor_select.gd` `_build_ui` / `_build_aircraft_card` |
| 悬停 / 键盘焦点预览与卡片高亮；锁定卡不加载档案 | `survivor/survivor_select.gd` `_show_initial_preview` / `_show_aircraft_preview` / `_refresh_card_highlights` |
| 全息投影绘制、正式轮廓复用与加密占位 | `survivor/aircraft_hologram_preview.gd` `show_profile` / `show_locked` / `_draw` → `aircraft_silhouette_catalog.gd` `texture_for_display_name` |
| 选中回调（写资源 + T4 node/level meta） | `survivor/survivor_select.gd` `_on_aircraft_selected` |

## 无线电通讯（spec radio-chatter）

设计权威源：[docs/specs/systems/radio-chatter.md](../specs/systems/radio-chatter.md)。
本节按**"我要改什么 → 去哪"**组织，不按文件罗列。

### ⚡ 最常见的改动（多数不用碰代码）

| 我想…… | 去哪 |
|---|---|
| **加一条台词** | ① `resources/chatter/radio_chatter.json` 对应 trigger 的 `lines` 加 key ② `i18n/radio.csv` 加一行三语。**不碰代码** |
| **改台词文案** | `i18n/radio.csv` 的 `RADIO_*` 行（改完需 Godot 重新导入） |
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
| 阵营色解析（引 FactionPalette） | `radio_chatter.gd:307` color_of / `:313` color_for_team |
| 队列状态机 IDLE/SPEAKING/GAP | `radio_chatter.gd:353` _process |
| 冷却递减（含全局） | `radio_chatter.gd:379` _tick_cooldowns |
| 出队 + 过期丢弃（scripted 豁免） | `radio_chatter.gd:374` _pump |
| 权重排序 | `radio_chatter.gd:406` _best_index |
| 开播（写 Label + 触发音效） | `radio_chatter.gd:399` _begin |
| 显示时长公式 | `radio_chatter.gd:420` line_duration |
| 淡入淡出 | `radio_chatter.gd:443` _apply_alpha |
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
| **硬规则**：no_pilot 永不说话 | `aircraft.gd:430` can_speak_on_radio |
| 等级门字段 | `aircraft.gd:431` has_radio_voice |
| 常规敌机赋值（与 no_pilot 同处） | `survivor/survivor_spawner.gd:1796` |
| Mother Goose 蜂群 UAV | `survivor/mother_goose_uav_swarm.gd:250` |
| Mother Goose MQ-X | `survivor/mother_goose_boss.gd:443` |
| 白名单数据 | JSON `voiced_enemy_types.types` |

### 触发接线（每处 ≤4 行，全部挂在既有信号/函数上）

| 触发 | 位置 |
|------|------|
| 系统实例化（**刻意在战区 if 之外**，boss_debug 也要有） | `survivor/survivor_mode.gd:423` |
| 字段声明 | `survivor/survivor_mode.gd:177` _radio |
| BOSS 登场挑衅 | `events/boss_encounter_event.gd` `_try_play_arrival_cinematic`（正式序列）/ `_start`（缺序列时通用 WARNING + 无线电回退）；Black Star 例外由 `_on_hyper_a_root_descent_started` 在两架根机各自真实下降开始时分别播 `BLACK STAR-01/02`，不在身份横幅一次性提前播完 |
| BOSS 交战 | `survivor/survivor_mode.gd:6683` on_boss_engaged |
| 击坠回报 / 弹射 / 减员计数 | `survivor/survivor_mode.gd:6704` _on_radio_kill_recorded |
| break 规避呼叫（真·躲导弹） | `survivor/survivor_mode.gd:6729` _on_radio_evasion_started |
| 加力冲刺呼叫（玩家主动加力，非躲导弹） | `survivor/survivor_mode.gd:6737` _on_radio_afterburner_engaged |
| 僚机归队 | `survivor/survivor_mode.gd:6746` _on_radio_wingman_joined |
| RTS 回令派发 | `rts/squad_command_controller.gd:810` _ack |
| RTS 应答人选取（跳过无人机） | `rts/squad_command_controller.gd:797` _ack_speaker |
| RTS 攻击回令空/地分流（空=追击/包围·地=打击） | `rts/squad_command_controller.gd:825` _strike_or_pursue |
| RTS 目标名解析 | `rts/squad_command_controller.gd:829` _target_label |

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
| 播放入口 | `audio/audio_manager.gd:716` play_radio |
| 音效 id → 路径 | `audio/audio_manager.gd:69` RADIO_FILES |
| **素材待补** | `res://audio/sfx/radio_beep.wav`（缺失时静默跳过，不 push_warning） |

### 音乐生命周期

| 关注点 | 位置 |
|------|------|
| 非 BOSS 王牌中队血条浮现 / 终态所有权 | `events/ace_reinforcement_event.gd` `_begin_ace_battle_music` / `_end_ace_battle_music` |
| 四曲随机 one-shot、曲终、Boss/Game Over 守卫、地图歌单断点恢复 | `survivor/survivor_mode.gd` `begin_ace_battle_music` / `_on_music_track_finished` / `end_ace_battle_music` / `_play_default_battle_music` |
| one-shot 完成信号 / 缺资源安全门 / 临时插入曲断点冻结与恢复 | `audio/audio_manager.gd` `music_track_finished` / `has_music` / `crossfade_music_interrupt` / `resume_interrupted_music` / `discard_interrupted_music` |
| 音频母版包体隔离 | `audio_intake/.gdignore` + `export_presets.cfg` `exclude_filter` / `patch_delta_exclude_filters`；只排除收件区，不全局排除正式 SFX WAV |
| 主菜单循环曲与战局交接 | `main_menu.gd` `_ready` 幂等 `crossfade_music("main_menu")`；`survivor/survivor_mode.gd` `_play_default_battle_music` → `crossfade_music_playlist` |

### 测试与导出

| 关注点 | 位置 |
|------|------|
| 自动测试音频隔离 | `bench/bench_runner.gd:185` `_ready`：识别 `--bench` 后 mute Master；`tests/test_deadair.gd` `_test_automation_audio_gate` 运行时断言 |
| 无头回归（89 断言） | `scripts/tests/test_radio_chatter.gd`，`--bench=chatter` |
| 航点移动机会火控回归 | `scripts/tests/test_waypoint_fire_control.gd`，`--bench=waypoint_fire` |
| 注册表 | `scripts/bench/bench_runner.gd` UNIT_TESTS |
| **导出必需** | `export_presets.cfg` 的 `include_filter` 必须含 `*.json`，否则数据表不进包 |

## 自动运行时验证

| 关注点 | 位置 |
|------|------|
| 设计权威与覆盖矩阵 | `docs/specs/systems/runtime-validation-workflow.md` |
| Agent 命令、退出码与新增终态清单 | `docs/reference/runtime-validation-workflow.md` |
| 所有 bench 的 stderr 红错改判与自动归因 | `bench/invoke_godot.ps1` `Get-BenchRuntimeErrorBlocks`；Godot 退出 0 但命中致命诊断时退出 86；保留完整 GDScript backtrace，freed-object 族追加 `FREED_OBJECT_LIFECYCLE` 提示 |
| `all` 串联同步断言与终态场 | `scripts/bench/bench_runner.gd` `HEADLESS_TEST_SCENES` / `_ready` / `_swap_to_test_scene` |
| 真实释放终态门 | `scripts/tests/lifecycle_gauntlet_runner.gd` + `scenes/tests/lifecycle_gauntlet.tscn`；含传感器三目标缓存的 A 释放 / B 隐形批清理顺序；bench `lifecycle_gauntlet` |
| 错误门自检 | `scripts/tests/runtime_error_probe.gd` + `scenes/tests/runtime_error_probe.tscn`；同时注入普通红错与 freed-object 类型边界，验证完整栈和自动归因；bench `runtime_error_probe` 预期退出 86 |
| bomber 跨帧字典净化 | `scripts/survivor/zone_mission.gd` `_live_bomber_target` / `_live_bomber_controller` → `_start_bomber_escort` / `_update_bomber_escort_caches` / `_retire_bomber_run` |

## 主场景/操控

| 功能 | 位置 |
|------|------|
| 鼠标输入 | `main.gd:66` _unhandled_input |
| 左键点击（锁定/移动） | `main.gd:119` _on_left_click |
| 右键取消 | `main.gd:136` _on_right_click |
| 悬停检测 | `camera_controller.gd:250` update_hover（main.gd 调用） |
| LOD 管理 | `main.gd:454` _update_lod |
| 地形绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 命令轮盘手势层（生存，spec command-wheel） | `scripts/rts/command_wheel.gd`（CommandWheel；参数 `command_wheel_params.gd` + `resources/command_wheel.tres`） |
| 轮盘接线：左键按下/松开仲裁 + 单击回放 | `survivor_mode.gd` `_on_left_press` / `_on_left_release` / `_execute_left_click` / `_on_wheel_command`（阶段 1 stub 打 EventLogger） |
| Mother Goose 本体点击→最近可攻击挂点 | `survivor_mode.gd` `_find_enemy_near` / `_is_inside_mother_goose_hull` / `_find_nearest_mount_target_on` |

## 视觉绘制

| 功能 | 位置 |
|------|------|
| 飞机绘制入口 | `aircraft.gd:3599` _draw |
| 已审顶视 PNG、同型号复用与运行时换色；MQ-109/110/111 共用用户批准的 `mq109_family`，其余原创/虚构/无合格来源机保留旧绘制 | `aircraft_silhouette_catalog.gd` `TEXTURE_PATHS` / `DISPLAY_KEYS` / `LEGACY_DISPLAY_NAMES` / `_texture_for` / `draw_icon` → `aircraft_renderer.gd` `draw_aircraft_icon`；原始 PNG 导出包含 `export_presets.cfg`；资产/来源清单 `resources/aircraft_silhouettes/`；直接提取 `tools/trace_orthographic_outline.py` / `tools/normalize_aircraft_reference.py`；审计 `tools/audit_aircraft_silhouettes.py` |
| 滚转体积投影（暗色壳层 + 顶面/机腹；PNG 最多两次纹理提交；legacy 不归零） | `aircraft_renderer.gd:98 bank_volume_projection_for` / `:84 bank_volume_face_alpha_for` / `:916 draw_aircraft_icon` → `aircraft_silhouette_catalog.gd:126 volume_thickness_for` / `:164 draw_icon`；回归 `test_aircraft_bank_volume.gd`；Visual/Perf `aircraft_bank_volume_visual` |
| 统一机型尺寸幂律 + 高度倍率 | `aircraft_renderer.gd:412 altitude_base_scale` / `:224 visual_model_scale`；真实尺寸字段 `aircraft_params.gd` |
| 指挥型图标 | `aircraft_renderer.gd:1405` draw_commander_icon |
| 雷达锥绘制 | `aircraft_renderer.gd:645` draw_radar_cone |
| 跨帧玩家机引用净化（HUD / 锁定线 / 绘制消费者） | `aircraft_renderer.gd` `safe_aircraft_ref` / `safe_player_ref`；`survivor/survivor_hud.gd` `_safe_player_aircraft`；终局断引用 `survivor/survivor_mode.gd` `_on_player_died` |
| 锁定框闪烁 + 屏幕空间恒定尺寸 | `aircraft_renderer.gd` `screen_space_inverse_scale` / `draw_lock_indicator` / `draw_lock_box` / `draw_secondary_lock_indicators`；地面/舰船/挂点调用同一补偿规则 |
| 真实在途导弹警告（一弹一线一三角；雷达共用判定） | `missile.gd` `incoming_warning_rule` / `is_incoming_warning_for` / `_draw_incoming_warning`；`survivor/survivor_hud.gd` `RadarDisplay` |
| 战斗单位统一矢量状态栏（飞机/无人机/地面/SAM/雷达/战略目标/舰船/导弹；共享英文 HDG/SPD/ALT/RNG/HP 数据契约；不随单位、父节点或镜头转动/缩放；玩家/僚机受伤整块蓝白反相；加力激活飞机显示 `AFTERBURNER`） | `aircraft_renderer.gd` `unit_status_screen_offset_for` / `screen_space_panel_transform_for` / `screen_space_panel_transform` / `draw_unit_status_panel` / `status_label_entries` / `status_heading_text` / `status_speed_knots_text` / `status_ground_speed_text` / `status_altitude_text` / `status_range_text` / `status_hp_text` / `english_status_identity`；地面/SAM/雷达内容 `_status_label_lines`，舰船 `_draw_status_label`，导弹 `missile.gd` `_draw_data_label`；格式与受伤断言 `tests/test_presentation.gd`，跨兵种 Visual `unit_status_label_visual` |
| 数据标签（完整） | `aircraft_renderer.gd` draw_data_label |
| 数据标签（生存模式简化） | `aircraft_renderer.gd` draw_data_label_minimal |
| 数据标签（剥离窗口 stretch 后按真实相机 0.35/0.40 简略档 + Alt 临时完整；玩家小队每架都显示纯机型编号 + 完整呼号，长机名后缀缩首字母） | `aircraft_renderer.gd` `label_lod_scale_for` / `label_lod_scale` / `next_compact_label_state` / `should_draw_compact_label` / `draw_data_label_compact` / `aircraft_model_designation` / `compact_aircraft_name` / `controlled_identity_label`；地面 `ground_unit.gd` `_should_draw_compact_data_label`，舰船 `naval/naval_unit.gd` `_draw_status_label` |
| 飞机旁数据标签近景避让与高速像素稳定 | `aircraft_renderer.gd` `unit_status_screen_offset_for` / `data_label_screen_offset_for` / `data_label_screen_offset`；5x 真实相机画面 `aircraft_label_visual`，跨兵种组合变换画面 `unit_status_label_visual` |
| 机头闪光 | `aircraft_renderer.gd:972` draw_muzzle_flash |
| 加力火焰 | `aircraft_renderer.gd:983` draw_afterburner_glow |
| 热诱弹粒子 | `aircraft_renderer.gd:1018` draw_flare_particles |
| 目标连线（普通=当前操控机 icon_color；双击突击=独立黄线；单层中细线） | `aircraft_renderer.gd:2222` draw_target_line |
| 蓝色玩家小队简略档左上角全部装填武器矩形反相闪烁；完整档显示百分比 | `aircraft_renderer.gd` `draw_reload_indicators` / `reload_indicator_team_visible` / `reload_indicator_style` / `reload_indicator_tokens` / `secondary_reload_progress` |
| 飞机旁状态栏：FLR 弹尽装填行红/琥珀双色闪烁 | `aircraft_renderer.gd:460` _wpn_color（FLR_RELOAD） |
| 玩家 HUD：热诱弹十星投放/短冷却/长装填同步 | `survivor/player_instrument_panel.gd` flare_lit_star_count / _draw_flare_stars |
| 雷达小地图：来袭导弹常亮脉冲标记 + 警示牌/外圈；光学或传感器隐形敌机保留低亮度匿名位置环但不恢复火控；30+ 单位时 20 Hz、其它 30 Hz 重绘，扫线尾迹与 TGT 括号合批 | `survivor/survivor_hud.gd` `RadarDisplay` / `redraw_interval_for_unit_count` / `stealth_hint_contact_for` |
| 预测轨迹（360 步分为 15 × 24 步，显示 4:1 抽样，旧缓存持续显示） | `survivor/survivor_mode.gd` `_process` → `aircraft_renderer.gd` `update_predicted_path_cache` / `prediction_display_result` / `draw_predicted_path` → `aircraft/aircraft_physics.gd` `begin_player_path_prediction` / `advance_player_path_prediction` / `player_path_prediction_result`；回归 `tests/test_predicted_path_incremental.gd`（bench `predicted_path`） |
| 战术提示弹窗 | `aircraft_renderer.gd:2202` draw_tactic_popup |
| 机炮意图锥（敌方威胁锥 / 友方 hover 参考锥 / 当前操控机急刹真实射界；炮艇为 360° 环；仅 Mother Goose 蜂群隐藏） | `aircraft_renderer.gd` `should_show_enemy_gun_threat` / `should_show_friendly_gun_reference` / `draw_gun_cone` |
| └ 威胁锥淡出系数（开火淡出 / 停火淡回） | `aircraft.gd:615` _gun_threat_fade |
| └ 淡出淡回时长常量 | `aircraft.gd:616` GUN_THREAT_FADE_OUT_TIME / `aircraft.gd:617` GUN_THREAT_FADE_IN_TIME |
| └ 每帧推进（威胁条件成立时按 is_firing 增减） | `aircraft.gd:3811` _update_gun_threat_indicator |
| └ 威胁条件中断复位（保留"立即归零防抖"语义） | `aircraft.gd:3819` _reset_gun_threat |

## HUD / UI

| 功能 | 位置 |
|------|------|
| 沙盒 HUD（**沙盒已废弃**，仅调试留存）| `hud.gd:7` _process |
| 生存模式 HUD 构建/更新与 F7 玩家 HUD 六档独立缩放（默认 `0.9×`，其它 UI `1.0×`） | `survivor/survivor_hud.gd` `_build_ui` / `_ensure_ui_root` / `set_player_hud_scale` / `snap_player_hud_scale` / `right_anchored_player_rect` / `_update_display` / `_update_player_instrument` |
| HUD 首次显现（空间顺序、`0.02s` 错峰、逐框 `0.50s` 两闪、动态取消） | `ui/hud_first_reveal_sequencer.gd`；`ui/hud_board_visibility.gd`；`survivor/survivor_hud.gd` `_setup_hud_first_reveal` / `_sync_hud_first_reveal_targets` |
| 屏幕外圈受伤/异常/治疗反馈（红 > 黄 > 绿；低于 ThreatOverlay；释放安全） | `survivor/damage_vignette.gd`；`aircraft.gd` `_apply_damage` 写受伤时刻；`survivor/survivor_hud.gd` `_build_ui` / `_process`；`tests/test_damage_vignette.gd`（bench `damage_vignette`） |
| 玩家/僚机受伤反馈（飞机旁状态栏整块与数字蓝白反相；右下角 HUD 不整体变色、仅对应 HP 红闪；导弹单发完整周期、机炮连续命中续窗不重置相位） | `aircraft.gd` `_apply_damage` 写 `status_bar_damage_started_at` / `status_bar_last_damage_at` → `aircraft_renderer.gd` `status_damage_flash_phase` / `status_damage_flash_phase_for` / `status_damage_panel_colors` / `draw_unit_status_panel`；玩家 HUD `survivor/player_instrument_panel.gd` `register_damage_event` / `damage_hp_color` / `hp_damage_regions`；僚机 HUD `survivor/survivor_hud.gd` `_update_squad_panel` → `survivor/wingman_instrument_panel.gd` `_sync_damage_rows` |
| 玩家模块化仪表（生产 HUD 与 F7 预览共用；401px 根宽、HP 上方云层/击杀状态、2u/3u 数字模板、ALT 反相档位与独立连续指针层、武器装填双读数） | `survivor/player_instrument_panel.gd` `AltimeterNeedleLayer` / `_configure_layout` / `update_status` / `altimeter_target_degrees` / `_draw_altimeter_gauge` / `_draw_altimeter_needle` / `decorative_aligned_width` / `weapon_reload_remaining_seconds` / `active_control_empty_rect` / `update_display` / `_draw` |
| 玩家 HUD 字号与动态扩格 | `ui/terminal_text.gd` `TerminalText`；小字 `resources/fonts/Silkscreen-Regular.ttf`，主要数字 `resources/fonts/ChakraPetch-Bold.ttf` |
| 唯一互斥 R 技能常驻百分比充能行 | `aircraft.gd` `equipped_r_maneuver_id` / `r_maneuver_cooldown_total` / `r_maneuver_cooldown_remaining`；`survivor/player_instrument_panel.gd` `_draw_maneuver_charge` |
| 独立 `1q` 操作键与手动 FLR 运行时插列 | `survivor/player_instrument_panel.gd` `grid_regions` / `debug_grant_manual_flare_skill` |
| 僚机动态行仪表（每行 `1q+7u × 3u`） | `survivor/wingman_instrument_panel.gd` `update_display` / `grid_regions` / `_apply_row_count` / `_draw_row` |
| 底部三方向点击格、`当前/8` 数字、等级/剩余经验与进化就绪侧板 | `survivor/milestone_axis_counter.gd` `update_display` / `axis_value_rect` / `point_rect` / `_draw`；`survivor/bottom_experience_panel.gd` `update_display` / `xp_remaining` / `evolution_ready_rect` / `flash_level_up` / `_draw` |
| UI 设计规范（主界面 + 玩家/僚机 HUD + 战斗单位状态栏 SSOT） | `docs/specs/systems/ui-design-guidelines.md` |
| 终端共享网格物理 1px 描边、重合边去重 multiline 与精确文字 | `ui/terminal_grid_overlay.gd` `SCALE_INVARIANT_LINE_WIDTH` / `outline_segments_for` / `ui/terminal_text.gd` |
| HUD 速度单位与线框色持久化 | `ui/hud_preferences.gd` `speed_unit` / `hud_color` / `set_hud_color` |
| 主菜单速度单位、音频与 HUD 色盘 | `main_menu.gd` `_refresh_hud_settings_buttons` / `_on_speed_unit_pressed` / `_on_audio_settings_pressed` / `_on_hud_color_pressed`；`audio/audio_settings_panel.gd` / `ui/hud_color_settings_panel.gd` 均走白色终端弹层 |
| 主菜单 Y2K 军用 CRT 与双栏终端布局 | `main_menu.gd` `_build_terminal_header` / `_build_system_panel` / `_add_mode_button` / `_refresh_terminal_palette`；`ui/main_menu_crt_shell.gd`；`ui/main_menu_crt_effect.gd` + `resources/shaders/main_menu_crt.gdshader`；`ui/main_menu_scope_display.gd`；`tests/main_menu_visual_qa_runner.gd`（bench `main_menu_visual`） |
| 规范后旧 UI 翻修共享管线 | `ui/terminal_page_shell.gd`（CRT/23u×30u）+ `ui/terminal_ui_style.gd`（白色线框/字体/反色控件）+ `ui/terminal_map_preview.gd`（静态线稿）；资料库、商店、选图、选机共用整页壳，音频/色盘/暂停/结算共用小板样式；`tests/ui_iteration_visual_qa_runner.gd`（bench `ui_iteration_visual ... Shadow Visual`） |
| HUD 字体 | `resources/fonts/Silkscreen-Regular.ttf`（1u/1q 拉丁信息）/ `ChakraPetch-Bold.ttf`（主要数字）；缺失字符走当前主题默认字体回退 |
| BOSS 系统入侵身份横幅 | `ui/boss_arrival_banner.gd` `show_identity/_apply_palette/set_reveal_progress/warning_reveal_progress/set_dismiss_progress`（5 窗严格逐个压入、主身份最后展开；默认终端绿 / Wraith 蓝黑电蓝 / Black Star 银黑橙；CSG 包装 `AN AWESOME WAVE`，Black Star 包装 `Blame it on the falling sky`）；身份/motto/palette 数据 `survivor/boss_registry.gd` `banner_metadata_for`；时序 `resources/presentation/sequences.json` 的 `banner` 通道 |
| 玩家 HUD 回归/可视验收 | `tests/test_player_instrument_hud.gd` `run`（bench `player_hud`）；`tests/player_hud_visual_qa_runner.gd`（bench `player_hud_visual`） |
| 五表本地化源、唯一性审计与 15 份资源构建 | `i18n/README.md`；`i18n/interface.csv` / `gameplay.csv` / `skills.csv` / `meta.csv` / `radio.csv`；`scripts/i18n_catalog.gd`；`scripts/tests/build_translations.gd`（bench `i18n_build`） |
| BOSS 横幅 / Debug 回归与可视验收 | `tests/test_presentation.gd` `_test_boss_banner_contract`（bench `presentation`）；`tests/boss_arrival_banner_visual_qa_runner.gd`（bench `boss_arrival_banner_visual`，含 Black Star）；`tests/boss_debug_select_visual_qa_runner.gd`（bench `boss_debug_select_visual`，Boss 选择 → 7 个 T4 四机以上参考编队 → 实战 Tab build → 海洋 FINAL WAR 四段） |
| 终端文字、轮廓缓存与共享网格回归 | `tests/test_terminal_text.gd` `run` / `_check_ink_bounds_cache`；bench `terminal_text` |
| UI Dev 定位框与玩家 HUD 缩放回归/可视验收 | `tests/test_ui_dev_outline.gd` `run`（bench `ui_dev_outline`，含正式 `_physics_process` 时间注入位置、战区时钟整数秒/BOSS 状态重绘门、六档吸附、默认 `0.9×`、零右边距轴心、其它 UI `1.0×` 隔离）；`tests/ui_dev_panel_runner.gd`（bench `ui_dev_panel_visual` / `ui_dev_panel_clean_visual` / `ui_dev_panel_manual_flare_visual` / `ui_dev_panel_scale_visual`，最后一项验证玩家 HUD 贴右 `0.5×` 物理 1px 描边且其它 UI 不缩放） |
| 升级 UI 选项展示 | `survivor_upgrade_ui.gd:323` show_choices |
| 进化树层间直角布线（布局期缓存） | `survivor/evolution_tree_view.gd:158` _build_edge_routes / `:196` _orthogonal_path |
| 进化树四状态线批绘 | `survivor/evolution_tree_view.gd:206` _draw / `:315` _draw_edge_batch |
| 进化树隐藏当前机永久不可达旁支 | `survivor/evolution_tree_view.gd:69` `_relevant_nodes`；`tests/test_evolution_detail.gd` `_test_tree_hides_unreachable_routes` |
| 进化选择前的当前机框/候选详情；成功后结束本次停靠 | `survivor/evolution_tree_view.gd:103` set_current + `survivor/evolution_ui.gd` `_on_tree_node_selected` + `survivor/survivor_mode.gd` `_on_settlement_evolution` |
| 调试面板构建 | `debug_panel.gd:41` _build_ui |
| 调试面板内容更新 | `debug_panel.gd:183` _update_content |
| 战斗策略文本 | `debug_panel.gd:336` _get_combat_strategy |
| 飞行员信息 | `debug_panel.gd:373` _get_pilot_info |
| 地面单位生成按钮 | `debug_panel.gd:703` _spawn_ground_unit |
| Game Over 显示 | `survivor/survivor_hud.gd:2158` show_game_over |

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
| 空爆高炮 | `resources/airburst_aa_params.tres` + `resources/airburst_aa_gun.tres` |
| 战略硬目标 | `resources/strategic_target_params.tres` |
| 友军 B-1B | `resources/friendly_b1b.tres` |

## 场景文件

| 场景 | 文件 | 节点树 |
|------|------|--------|
| 生存模式（**主玩法**） | `scenes/survivor_mode.tscn` | SurvivorMode + BulletManager + MissileManager + Camera2D |
| 沙盒主场景（**已废弃**，仅调试留存） | `scenes/main.tscn` | Main + BulletManager + MissileManager + Camera2D + PlayerAircraft + DebugPanel |
| 飞机模板 | `scenes/aircraft.tscn` | Aircraft (Node2D + aircraft.gd) |
| 导弹模板 | `scenes/missile.tscn` | Missile (Node2D + missile.gd) |
| SAM 单位 | `scenes/sam_unit.tscn` | SAMUnit + sam_params |
| AA 单位 | `scenes/aa_gun_unit.tscn` | AAGunUnit + aa_gun_params |
| 空爆 AA 单位 | `scenes/airburst_aa_unit.tscn` | AirburstAAUnit + airburst_aa_params |
| 战略硬目标 | `scenes/strategic_target.tscn` | StrategicTarget + strategic_target_params |
| 雷达站 | `scenes/radar_station.tscn` | RadarStation + radar_station_params |
| 主菜单（**入口场景**） | `scenes/main_menu.tscn` | MainMenu |
| 机型选择 | `scenes/survivor_select.tscn` | SurvivorSelect |
| 地图选择 | `scenes/survivor_map_select.tscn` | 生存流程第一步；共享 CRT 白色终端五卡 + 静态地图线稿；B → boss_debug_select |
| BOSS 测试场 | `scenes/boss_debug_select.tscn` | Boss/场景选择 → 7 个 T4 四机以上同型编队 → 节点等级匹配的正式随机 ACE 武器 + gates 技能 build；战斗中 Tab 核对武器、技能与里程碑 |
| 地图编辑器 | `scenes/map_editor.tscn` | UGC |
| 手画地块参考 | `scenes/map_manual.tscn` | @tool 编辑器预览 |

## ROE / 阵营 / 第三方（2026-07-12，spec global-awareness-roe）

- **敌我判定唯一 API**：combat_unit.gd `is_hostile_to()` / `teams_hostile()` / `is_player_squad()`（team 0=PLAYER 1=HOSTILE 2=ALLY；散写 team 直比已收口禁止回潮）
- **动态阵营原子事务**：events/faction_transition.gd `convert()`（统一清 IFF/目标/锁定/旧小队/在飞弹药/任务身份并发 `faction_changed`）；events/ally_force.gd 是兼容包装。
- **WhiteTea 投降**：events/ace_reinforcement_event.gd `should_whitetea_surrender()` / `_try_whitetea_surrender()` / `_tick_surrender_egress()`；2→1 当帧按击破结算，幸存者本人播 `whitetea_surrender`。
- **激光黑客**：equipment/laser_equipment.gd `_select_hack_focus()` / `_advance_hack()`；survivor/hacked_ally_force.gd 负责被黑 MQ 跟随当前长机与切控重绑；技能配置 `survivor/survivor_data.gd` `skill_laser_hack`。
- **阵营转换运行时回归**：tests/test_faction_conversion.gd `_test_laser_hack_runtime_conversion()` / `_test_squad_cleanup_skips_freed_successor()`；必须真实越过 2.5s 黑客完成门，并覆盖 `Array[Aircraft]` 缓存清理与已释放继任引用。
- **感知门**：ai_controller.gd `_roe_allows_scored_engage()`（TS_SCORED 专用；读 roe_posture / roe_aware_until / roe_zone_* meta）
- **察觉/姿态/热度**：survivor/roe_director.gd（写 meta 的唯一方；2s 感知 tick + 1s 热度 tick）
- **hunter 配额**：survivor_spawner.gd `_update_hunters`（配额 = `_roe.hunter_quota()`，整队抽调）
- **第三方事件**：events/ally_force.gd + awacs_support_event.gd（护送直升机事件 `escort_convoy_event.gd` 已于 2026-07-28 删除）；机场解放后 ALLY 基础 AA×2 + MetaShop 永久授权 SAM 渐进部署 survivor_mode `airfield_ally_plan` / `_try_deploy_airfield_sam` / `_deploy_airfield_ally_gradual`（spec airfield-liberation-zones + airfield-sam-network）；调度 `_update_ally_events`
- **AWACS 支援事件**（2026-07-28 改造：绕战区轨道 + 定时撤离 + 进离场无线电）：

| 功能 | 位置 |
|------|------|
| 轨道中心选取（选中战区 → 最近 AVAILABLE 战区 → 兜底南带） | `events/awacs_support_event.gd:172` _pick_orbit_center |
| 到点转撤离（航点改到南界外，飞出/超时即 end） | `events/awacs_support_event.gd:158` _begin_egress |
| 进离场无线电（trigger `awacs_onstation` / `awacs_egress`） | `events/awacs_support_event.gd:204` _say |
| 在站时长 / 撤离兜底 | `events/awacs_support_event.gd:23` ON_STATION_S / `events/awacs_support_event.gd:25` EGRESS_TIMEOUT_S |
| 轨道几何常量（退避 / 半程 / 边界余量，退避须 < BUFF_RADIUS_PX） | `events/awacs_support_event.gd:28` ORBIT_STANDOFF_PX / `events/awacs_support_event.gd:30` ORBIT_HALF_SPAN_PX / `events/awacs_support_event.gd:32` ORBIT_MARGIN_PX |
| buff 半径（锁定×3 / 导弹 G ×1.25 的作用域） | `events/awacs_support_event.gd:16` BUFF_RADIUS_PX |
| 主战场海绿范围层（静态画布随父机移动；结束当帧隐藏） | `survivor/support_range_overlay.gd` `setup` / `_draw`；`events/awacs_support_event.gd` `_start` / `_finish` |
| Tab 图光环圈绘制 | `survivor/tactical_map.gd` _draw_dock_markers AWACS 分支 |
- **阵营色板**：game_constants.gd FactionPalette（COL_FRIEND_PLAYER/ALLY、COL_ENEMY_REGULAR/ELITE + 全部 team_* 函数三分支）

## 表演/演出（转场·镜头·时间·剧情演出）

- **总入口**：编排手册 [cinematic-authoring.md](cinematic-authoring.md)（BOSS 横幅→镜头→接战量产流水线 + 通道/op 全参考 + ctx 契约 + 陷阱表）；设计权威 spec [systems/ui-transition.md](../specs/systems/ui-transition.md)
- 导演/通道分发/遮罩/热重载 → `scripts/presentation/presentation_director.gd`
- BOSS 身份横幅（5 层警告窗/名称/角色/呼号/motto/palette）→ `scripts/ui/boss_arrival_banner.gd`；元数据 `scripts/survivor/boss_registry.gd banner_metadata_for`
- 时间缩放与暂停（唯一写入口，含命令轮盘收编）→ `scripts/presentation/time_authority.gd`；轮盘接线 `scripts/rts/command_wheel.gd _activate/_reset/_exit_tree`
- 演员走位/尾迹/演出隐身/虚拟环境所有权 → `scripts/presentation/cinematic_cast.gd`；bind/release 期间真实战斗传感器隐形冻结并绕过；指令消费端 `scripts/ai_controller.gd _directive_follow_path_step`（`target_speed`/`arrive_radius` 参数）
- 空舞台隔离 → `scripts/presentation/stage_isolator.gd`
- 镜头电影层（`_base_zoom` 拆分/cine_target 跟随/暂停期代泵）→ `scripts/camera_controller.gd`
- BOSS 登场接入样板 + 收尾钩子 → `scripts/events/boss_encounter_event.gd _try_play_arrival_cinematic / _on_arrival_cinematic_done`
- 升级急刹接入 → `scripts/survivor/survivor_mode.gd _on_player_leveled_up / _on_upgrade_selected`；面板协议 `survivor_upgrade_ui.gd get_transition_elements`
- 演出台词时长覆写/ambient 压制 → `scripts/survivor/radio_chatter.gd set_duration_override / suppress_ambient`
- 演出配乐幂等 → `scripts/audio/audio_manager.gd current_music_id`

## 2026-08-04 战区奖励与新技能

| 功能 | 位置 |
|---|---|
| 奖励类别/武器权重、航母第 4 次 pity、起始机型 ×2 偏置 | `survivor/zone_data.gd` `REWARD_KIND_WEIGHTS` `REWARD_WEAPON_WEIGHTS` `_assign_reward` |
| ESM 3000m 光环扫描 | `equipment/esm_pod_equipment.gd` `update`；`aircraft.gd` `esm_*_multiplier` |
| ESM 主战场蓝色范围层（淡填充 + 描边） | `aircraft_renderer.gd` `support_range_fill_color` / `support_range_ring_color` / `draw_esm_aura` |
| ESM 锁定 / reload 消费 | `survivor/survivor_mode.gd` 锁定循环；`aircraft/aircraft_weapons.gd`；`aircraft/aircraft_flares.gd` |
| 连锁弹头直穿与逐目标去重 | `missile_manager.gd` `_physics_process`；`missile.gd` `continue_after_penetration` `already_penetrated` |
| 炮艇模式 / 重型机炮 | `survivor/survivor_player.gd` `apply_upgrade`；`aircraft/aircraft_weapons.gd` `auto_gun_scan`（全队独立；射程内玩家点名 / MountTarget 优先，否则最近 Aircraft/GroundUnit）、`update_gun`（整梭目标锁存）、`_fire_gun_round`（炮口随射向）、`update_ciws`（独立正面锥）；`aircraft_renderer.gd` `draw_gun_cone` |
| Hunter 突击触发与生命周期 | `survivor/skill_hooks.gd` `try_trigger_j36_assault`；`aircraft/aircraft_physics.gd` effective accessors；`aircraft.gd` 伤害管线 |
| 入侵算法 / 逃离 | `survivor/skill_hooks.gd` `on_player_jam_landed` `on_player_fear_landed`；`survivor/survivor_spawner.gd` `grant_flee_neutralization_xp` |
| X-44 机炮贯穿 | `bullet_manager.gd` `spawn_bullet` `_physics_process`；`aircraft.gd` `gun_bullet_penetration_active` |

## 2026-08-08 图2/图3空地图试飞

| 功能 | 位置 |
|---|---|
| 内置地图数据 | `resources/maps/desert_railway_preview.aglmap` / `ocean_islands_preview.aglmap`：64×64 km MapDocument（旧 60km 核心布局不变），zones 为空；沙漠仅右侧 Newman 城区 15 体块炼油厂（中心约 `(4800,400) px`），海洋仅西北孤岛 16 体块火箭基地与 1 条配套跑道，另定义地理、云、出生点、palette、`tile_map_key` 与 bbox metadata |
| 正式栅格底图 | `resources/maps/basemap_tiles/{desert,ocean}/manifest.json` + lossless WebP 三档；原始/增强 PNG 已在瓦片毕业后从仓库删除，manifest 保留源文件名与 SHA-256 provenance |
| 选图与空场守卫 | `survivor/survivor_map_select.gd` `MAP_LIST` / `_on_map_selected` → `survivor/survivor_mode.gd` `_ready` / `_physics_process` / `archive_enabled`；预览图不构造 ZoneData/ZoneMission，不推进 Spawner/BOSS/阶段计时 |
| 主图与 Tab 同源色板 | `survivor/map_feature_renderer.gd` `ugc_palette` `_ugc_color`；`survivor/tactical_map.gd` `ugc_palette` `_map_color`，UGC 模式禁用东京湾专属 Aqua-Line |
| 正式底图失败反馈 | `survivor/map_feature_renderer.gd` `basemap_load_failed` / `_report_basemap_error` → `survivor/survivor_mode.gd` `_on_basemap_load_failed` / `_show_basemap_error`；正式图 fail-open 到矢量层并显示本地化红色 toast，UGC 纯矢量不误报 |
| 栅格上方机场覆盖 | `survivor/map_feature_renderer.gd` `_draw_ugc_airports` / `survivor/tactical_map.gd` `_draw_ugc_airports`：仅 UGC/内置预览图把 MapDocument 跑道静态绘制在底图上方；Tab 几何按面板尺寸缓存，东京湾不重复描画 |
| 港湾羽田跑道覆盖 | `survivor/map_geography.gd` `HANEDA_RUNWAYS` 存冻结 OSM 四跑道中线/宽度；`survivor/map_feature_renderer.gd` `_draw_haneda_airport` 静态叠在正式瓦片上方；`survivor/tactical_map.gd` `_rebuild_haneda_runway_cache` / `_draw_haneda_airport` 以独立八端点缓存绘制 Tab，不作用于图2/图3或任务判定 |
| 预览建筑透视守卫 | `survivor/survivor_mode.gd` `_ready`：MapDocument 预览将 `BuildingRenderer.perspective_k` 设为 `0.015`，防止低缩放时远处侧墙拉成长方块；东京湾保持默认值 |
| 载入与空场探针 | `bench/bench_runner.gd` `PREVIEW_BENCH_MAPS` + 东京默认图分支；`map_raster_tokyo/desert/ocean` 抓中央完整 viewport；`map_boundary_crop_tokyo/desert/ocean` 把相机置于右下内容极限并使用 `ZOOM_MIN=0.2`，逐图证明缩放时不采到底图外黑边 |

## 2026-08-22 三图 lossless WebP 正式底图

| 功能 | 位置 |
|---|---|
| 权威 spec | `docs/specs/systems/raster-basemap-streaming.md`：东京湾/沙漠/海洋统一按 `tile_map_key` 消费正式瓦片；旧 PNG 与 A/B Debug 页已获授权删除 |
| 三档离线数据 | `scripts/tools/build_lossless_basemap_pyramid.py` → `resources/maps/basemap_tiles/{tokyo,desert,ocean}/manifest.json`：Strategic 1520²、Operational 7680² 8×8、Detail 8704² 9×9；1024px 瓦片内容 + 16px gutter，lossless WebP 复解码像素 mismatch=0；工具默认只写 `tmp/`，支持 `--operational-only` / `--strategic-only` 复制基线并只重建一档，1520 为七档消融后仍满足 68 MiB 的最高质量点；`build_shared_blue_noise.py` 另生成不含地图内容的 64² L8 共享颗粒纹理 |
| 静态颗粒 profile | `raster_basemap_renderer.gd.make_material` 从每图 `style_profile` 一次性写入 `noise_strength=0.014` 与 `grain_repeat=64`；共享蓝噪声只采样一次、无 `TIME`。V33 的 `48/32` 真机消融因三图低频误差与结构 F1 单调恶化被否决 |
| 主地图静态 streaming | `survivor/raster_basemap_renderer.gd` `setup` `set_active` `debug_state` `make_material` + `shaders/basemap_streamed.gdshader`：Strategic `0.08…0.10`、Detail `0.20…0.24` 迟滞，使主要战斗 `0.26` 使用原尺寸层，Operational `0.18` 仍独立验收；manifest 静态采样/低频补偿、0.40s 目标层置顶覆盖淡入与 CanvasItem `COLOR/modulate` 生效；全部可见格优先、跨大档 Strategic 桥接、request 4/tick、bind 2/tick、12 格 LRU/16 格硬门；不在 `_draw` 扫描或持续 redraw |
| 正式 shader 同源风格 | `resources/shaders/basemap_streamed.gdshader`：复用正式 saturation/brightness/contrast/tint/Sobel 参数；Strategic/Detail `edge_gain=1.15/1.20`，Operational 按图使用东京/沙漠 `1.17`、海洋 `1.15`；grain 以世界 `map_uv×64` 采样共享蓝噪声 mip，不使用 `TIME`/fragment hash，不预烘进地图像素 |
| 主图/Tab 正式接线 | `map_feature_renderer.gd` `_prepare_raster_basemap`；`tactical_map.gd` `_ensure_raster_basemap`：官方三图直接按 key 读取 manifest，Tab 复用 Strategic + 固定乘色，无第二份 SubViewport/shader；`Shift+F8` A/B 已删除 |
| 内置三图接线与 UGC 边界 | `survivor_mode.gd` / `map_feature_renderer.gd`：东京湾、沙漠铁路、海洋群岛识别各自 manifest；外部 UGC 可 vector-only 或自带 PNG，禁止误加载官方 raster 内容 |
| 正式 Visual/载入 QA | `map_raster_{tokyo,desert,ocean}` Visual bench 使用同一天气种子抓取三张真实 Survivor viewport，覆盖玩家、HUD、天气、玩法建筑、机场与正式瓦片共同合成 |
| S3 地图性能门 | `survivor_mode.gd` 的 `map_raster_operational_stress`、`map_raster_stress`、`map_raster_detail_stress` 分别固定 `0.18/0.26/0.80`，峰值约 52 架/45 敌；`map_raster_transition_stress` 每 `0.8s` 在 `0.06/0.18/0.26` 三档循环。当前裁定须按 performance-guidelines 与 C1 组合复核，冷启动另记；稳态纹理约 `59.87 MiB`，16 格硬上限约 `76.89 MiB` |

## 2026-08-05 纯矢量地图游戏内预览（V45 冻结研究档案）

| 功能 | 位置 |
|---|---|
| V20 中远景自包含矢量数据 | `scripts/tools/build_vector_preview_data.py` → `resources/maps/tokyo_bay_vector_preview.json`；Operational 密度/建筑为 `tokyo_bay_operational_density.agod.gz` / AGOB v2 `tokyo_bay_operational_buildings.agob.gz`（51,121 大型 + 85,403 中型 + 176,738 小型面积守恒方向体块）；`bake_tokyo_bay_operational_roads.py` 从本地 PBF 生成 15,431 条分区限额街区骨架 `tokyo_bay_operational_roads.agor.gz`，运行时合入既有 packet |
| V21 近景实际高度地标 | `scripts/tools/bake_tokyo_bay_landmark_walls.py` 从本地 PBF 的 `height` / `building:levels` 生成 `resources/maps/detail_landmark_walls/*.aglw.gz` 与 `tokyo_bay_landmark_walls.json`；`MapDetailVectorRenderer._merge_landmark_wall_packet` 在 loading/安全暂停合入既有 large wall packet，缺包回退 8px 低浮雕，不增加 draw call |
| V23 Detail 统一色阶 | `survivor/map_detail_tile_cache.gd` `DETAIL_COLOR_LIFT = Color(1.25, 1.25, 1.24)`；只乘缓存 Sprite RGB，1.40 倍因接缝峰值超门已否决 |
| V25 单层真实街巷 | `tools/bake_tokyo_bay_operational_roads.py` 以 45/75/3/4 分区配额输出 18,874 条、52,633 线段；`map_vector_preview_renderer.gd` neighborhood 仅合入 `road_core`，不复制 casing，Operational 23 draw calls / 1,512,402 三角 |
| V26 中景建筑层次 | `map_vector_preview_renderer.gd` `_add_operational_buildings` / `_add_operational_building_casings`：small 柔和填充，medium/large 外扩 2.1 world px 合批冷暗 casing 后覆盖浅屋顶；Operational 24 draw calls / 1,785,450 三角 |
| V27/V28 远中景概括与性能门 | `map_vector_preview_renderer.gd`：Strategic/Tab 省略全部 AGOB；Operational 只提交 51,121 个 large 屋顶及 casing，中小建筑由 density mass/街区骨架与近景 AGDT 接管，24 draw calls / 1,090,362 三角；`map_visual_qa_runner.gd` 从真实 1024² `LOD_TAB` SubViewport 采集快照 |
| V29 全图视觉覆盖门 | `tests/map_detail_atlas_qa_runner.gd` + `scenes/tests/map_detail_atlas_qa.tscn`：逐格走生产超采样缓存并叠加世界对齐 Operational base，审计 203/203 格与 30 条边界；`bench_runner.gd` 注册显式 Visual 场景，不滚入 `all` |
| V30 静态高层层级 | `bake_tokyo_bay_landmark_walls.py`：普通楼投影仍封顶 52px，仅真实高度 `>=80m` 的少量地标按分段曲线放宽到 122px；投影 bbox 参与跨瓦片分配。6,371 栋 / 186,698 三角 / 1,560,988 bytes，合入既有 wall packet、无新增 draw call |
| V31 高层顶面 | 同一离线工具只为 669 栋真实 `>=80m` 高层耳切 7,291 个偏移顶面三角；米灰顶面 + 实体墙避免悬浮碎片。AGLW 总计 193,989 三角 / 1,603,641 bytes，仍合入既有 packet、无新增 draw call |
| V32 高层屋顶 casing | 同一耳切顶面先画全尺寸冷暗 casing、再画约 1.6px 内缩米灰屋顶；669 栋共 14,582 顶面三角，AGLW 总计 201,280 三角 / 1,657,080 bytes，仍无新增 packet/draw call |
| V40 跨尺度渐进门 | `map_vector_preview_renderer.gd` `_update_operational_feature_opacity`：主地图保持单一不透明 Operational 根；既有 mass/roof/depth packet 分别在 0.18–0.58 / 0.24–0.58 / 0.34–0.74 渐变，完整 Detail 0.50–0.98 感知淡入；不增加几何、draw call 或战斗期 bake |
| V34 整图风格预算门 | `tests/map_detail_atlas_qa_runner.gd` `_atlas_style_metrics`：203 格真实 GL atlas 同时阻断非空格亮度超出 90–146 或单格超过 1,400,000 三角，并报告最暗/最亮/最重格；不逐格调色、不抹平城乡差异 |
| V35 整图色偏门 | `tests/map_detail_atlas_qa_runner.gd` `_thumbnail_stats` / `_atlas_style_metrics`：记录每格 mean RGB，并要求 `G-R=3–12`、`B-G=-10–-1`，阻断发红、发蓝或通道错误；只运行于 Visual QA |
| V36 战区抵达走廊 | `survivor_mode.gd` `_zone_cruise_edge` / `_detail_corridor_region` + `map_detail_tile_cache.gd` `region_plan`：预热与巡航复用同一近侧抵达点；12 格截断先保留可用的抵达点/圆心瓦片，再按中点距离填充；出生区和全部正式战区四向入口由 `map_gold_slice` 回归 |
| V40 无断层视口预热 | `survivor_mode.gd` `_detail_path_view_regions` → `map_feature_renderer.gd` `prewarm_detail_regions` → `map_detail_tile_cache.gd` `bake_regions` / `_refresh_viewport_coverage`：入口/中点/圆心真实视口并集整批装入，超 12 格完整回退；纯海域 0 格成功保持 Operational；当前视口缺格时 Detail 整层渐退 |
| V40 Operational 伪立体楼 | `map_vector_preview_renderer.gd` `_add_operational_building_walls`：51,121 个 large 方向体块统一东南偏移，合入 1 个静态 wall packet；侧墙/casing 与屋顶分阶段、限透明度渐入，避免作战档实心大色块 |
| V41 共享游戏地标与功能色 | `survivor_mode.gd` `_sync_shared_map_gameplay_layers`：PNG/候选两侧始终显示同一 189 组横滨 `BuildingRenderer` 假 3D 地标，视觉与阻挡一致；`map_vector_preview_renderer.gd` `_add_operational_density` / `_build_packet_definitions`：城区、植被、工业使用低饱和分色，工业/停机坪并入既有 mass packet，Operational 24 draw calls / 1,192,604 三角 |
| V43 常驻高层与纸模色块 | `bake_tokyo_bay_operational_landmarks.py` → `tokyo_bay_operational_landmarks.aglw.gz`：669 栋真实 `>=80m` 高层、29,688 三角、227,154 bytes gzip；`MapVectorPreviewRenderer._add_operational_landmarks` 合为 alpha 1 的静态 `landmark` packet。`bake_tokyo_bay_context_relief.py` 离线生成 360 块不规则 6–8 边、非同心三层台地（灰绿 139 / 冷灰 57 / 灰褐 164），按视觉 water 边界精确拒绝相交；Operational 最终 26 draw calls / 1,240,237 三角，水面命中 0 |
| V44 暖灰纸板总平面 | `map_vector_preview_renderer.gd` 的 density/context/relief 锚点统一满足暖纸色序，以明度替代蓝/绿/橙功能分色；`bake_tokyo_bay_context_relief.py` 将台地改为 220 块、1.1k world px 宏观采样与 320–700px 半径，保留呼吸区。`test_map_vector_preview.gd` 守住色族与 `0.02..0.08` 类别距离；Operational 26 draw calls / 1,236,202 三角，`terrain_context` 14,496 三角、水面命中 0 |
| V39 三档调色与边缘阴影 | `map_vector_preview_renderer.gd` `_sea_color` / `_land_color` / `_urban_color` 与 `map_detail_vector_renderer.gd` 既有 coast/building packet：只调 LOD palette/alpha、描边宽度和统一阴影偏移，不新增地图内容、draw call 或三角；制作顺序见 `vector-map-production-playbook.md` §3.1 |
| V38/V41 完整网格与真实建筑对照 | `test_map_gold_slice.gd` 审计完整 16×16 网格并精确锁定 `detail_10_06` / `detail_14_04` 两个海岸边缘空格；`map_detail_atlas_qa_runner.gd` 报告 256 格分类；`map_visual_qa_runner.gd` 在 PNG 与候选两侧加载同一正式 `BuildingRenderer` 189 街区，并对拍两个显式空格 |
| 冻结研究制作规则 | `docs/reference/vector-map-production-playbook.md`：保留金样优先、三档信息预算、建筑层级、全格分类、静态预热、自主多轮迭代与成对性能门；当前不授权东京湾 PNG 退休 |
| 四档静态 triangle-array renderer | `survivor/map_vector_preview_renderer.gd` `setup` `prewarm_lod` `update_lod` `_build_packet_definitions`；组包/提交复用 `rendering/canvas_triangle_packet.gd`，v7 主图固定 Operational 单根，Tab 强制 LOD_TAB；自交主水环回退 `_triangulate_polygon` → `Geometry2D.offset_polygon` 拆环 |
| 已否决的整图淡入/规则道路格 | `docs/specs/systems/pure-vector-map-preview.md` v7；运行时代码已移除，禁止用 alpha 双根或规则网格冒充连续 zoom / 城市肌理 |
| loading 主图+Tab 预热 | `survivor/building_preloader.gd` `_process` → `MapVectorPreviewRenderer.prewarm_lod`；正式场景缓存命中后绑定约 0–1ms |
| 主地图 PNG/矢量 A/B | `survivor/map_feature_renderer.gd` `_prepare_vector_preview` `set_vector_preview_enabled` |
| Tab 1024² 一次性矢量快照 | `survivor/tactical_map.gd` `set_vector_preview_enabled` `_draw_minimap_vector_preview` |
| debug 同步开关与失败回滚 | `survivor/survivor_mode.gd` `_toggle_map_vector_preview` `_sync_shared_map_gameplay_layers`；`Shift+F10`，底图切换不隐藏共享假 3D 游戏地标 |
| 数据/cache/LOD/packet 预算回归 | `tests/test_map_vector_preview.gd`；`bench/run.cmd map_vector_preview 5 120 Shadow` |
| 真实 GL Compatibility 对拍 | `tests/map_visual_qa_runner.gd`、`tools/map_visual_qa.py`；`bench/run.cmd map_visual_qa 1 900 Shadow Visual`；V44 固定机位、六档、滚轮落点和 0.02 扫频均通过，PNG 与候选使用同一共享游戏大楼层；`contact_sheet.png` / `progression_sheet.png` 产物仅在 `tmp/map_visual_qa/analysis/`，PNG 继续承担色板与近景层次并排对照 |
| 横滨 4×4 km style 金样 | `tools/bake_yokohama_gold_slice.py` → `resources/maps/yokohama_gold_slice_preview.json`；15,601 栋 OSM 建筑 + landuse/rail/waterway/port；profile `yokohama_gold_v5_locked` |
| 全图 detail 生产与打包 | `tools/bake_tokyo_bay_full_detail.py` 在 `.gdignore` 的 `tmp/full_map_detail/detail_tiles_source/` 生成约 995 MB 构建 JSON；`tools/pack_tokyo_bay_detail_tiles.py` → `tokyo_bay_detail_tiles_full.json` + 199 个非空 `detail_tiles_packed/*.agdt.gz`（约 154.9 MB）。raw JSON 禁止进入 `resources/` |
| detail 一次性瓦片缓存 | `survivor/map_detail_tile_cache.gd`：3072²→1536² GPU 两级线性降采样、4 px 仅过滤外挤、12 格 LRU ≤110 MiB；zoom 0.50–0.98 的 1.75 次幂曲线直接求值，覆盖完整度单独用 `_coverage_alpha` 平滑，最终相乘以消除滚轮亮度滞后；战斗中禁止烘焙/readback，未驻留区保持 Operational |
| 跨战区 detail 安全预热 | `survivor/survivor_mode.gd` `_on_zone_selected` `_prewarm_zone_detail` → `map_feature_renderer.gd` `prewarm_detail_region` → `map_detail_tile_cache.gd` `bake_region`；`tactical_map.gd` `set_detail_prepare_in_progress` 在真暂停中锁住点击/关闭，恢复战斗后 streaming 仍为 false |
| 任意 Tab 航点 detail 安全预热 | `survivor/survivor_mode.gd` `_on_nav_point_selected` 先 await `_prewarm_nav_detail`，以航点为中心预热 4.4 km 方区，成功或回退后再 `command_move`；复用 TacticalMap 同一真暂停事务，战斗主画布不触发 |
| 瓦片/矢量同负载性能门 | `survivor/survivor_mode.gd` `MAP_BENCH_SCENARIOS`；`bench/run.cmd map_raster_stress 120 300 Shadow Visual` / `map_vector_stress`；两侧包含共享 `BuildingRenderer` |
| V46 最终生产裁决 | `docs/specs/systems/pure-vector-map-preview.md`：用户整图视觉验收未通过；正式主地图与 Tab 使用 lossless WebP 瓦片，V44 代码/数据/QA 仅作冻结 debug 研究，未来重启须另立 approved spec |
| 金样 packet 预算回归 | `tests/test_map_gold_slice.gd`；`bench/run.cmd map_gold_slice 1 120 Shadow` |
