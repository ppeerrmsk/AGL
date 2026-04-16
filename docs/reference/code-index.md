# 代码索引

按功能主题索引到 `文件:行号`，直接 Read 对应行号即可获取上下文。

---

## 飞行物理

| 功能 | 位置 |
|------|------|
| 物理主循环 | `aircraft.gd:194` _physics_process |
| 目标航向计算 | `aircraft.gd:399` _update_target_heading |
| 滚转角更新（G 限制由 tactical_aggression 插值调节）| `aircraft.gd:419` _update_bank |
| 航向更新 ω=g×tan(bank)/speed | `aircraft.gd:580` _update_heading |
| 速度更新（含高G阻力、高度耦合） | `aircraft.gd:598` _update_speed |
| 高度更新 | `aircraft.gd:635` _update_altitude |
| 失速检查 | `aircraft.gd:649` _update_stall |
| G力计算 | `aircraft.gd:670` _update_g_load |
| 飞行员耐力 | `aircraft.gd:679` _update_pilot_stamina |
| 位移应用 | `aircraft.gd:692` _apply_movement |
| 最大 bank 角（受耐力影响） | `aircraft.gd:700` _max_bank_angle |
| 有效最大G（耐力插值） | `aircraft.gd:720` _effective_max_g |
| 角点速度 V=V_stall×1.2×√G | `aircraft.gd:731` _corner_speed_kmh |
| 失速速度 V_stall×√G | `aircraft.gd:737` _stall_speed |
| 高空最大速度衰减 | `aircraft.gd:742` _max_speed_at_altitude |
| 空气密度比 σ=e^(-alt/8500) | `aircraft.gd:748` _air_density_ratio |
| 高度档位切换（生存模式） | `aircraft.gd:759` set_target_tier |

## 能量管理

| 功能 | 位置 |
|------|------|
| 能量管理总入口 | `aircraft.gd:803` _update_energy_management |
| 加力燃烧器开关 | `aircraft.gd:774` _set_afterburner |
| 燃油消耗 | `aircraft.gd:784` _update_fuel |

## 战斗追踪（Aircraft 内置）

| 功能 | 位置 |
|------|------|
| 战斗追踪主逻辑（空对空） | `aircraft.gd:1107` _update_combat |
| 对地攻击（跑道进入式） | `aircraft.gd:1274` _update_combat_ground_attack |
| 设定战斗目标 | `aircraft.gd:1093` set_combat_target |
| 清除战斗目标 | `aircraft.gd:1099` clear_combat_target |
| CombatParams 获取 | `aircraft.gd:1347` _combat_params |
| 自动扫描机炮目标 | `aircraft.gd:1362` _auto_gun_scan |

## 武器系统 — 机炮

| 功能 | 位置 |
|------|------|
| 机炮射击更新 | `aircraft.gd:1422` _update_gun |
| 机炮射程（像素） | `aircraft.gd:1355` _gun_range_px |
| 子弹生成 | `bullet_manager.gd:23` spawn_bullet |
| 子弹物理+命中检测 | `bullet_manager.gd` _physics_process |
| 曳光弹绘制 | `bullet_manager.gd` _draw（区分 is_rocket）|

## 武器系统 — 火箭弹（无制导副武器，例：F-86 FFAR）

| 功能 | 位置 |
|------|------|
| RocketParams 定义（齐射数/散布/冷却/射程）| `scripts/rocket_params.gd` |
| 火箭弹发射主逻辑（齐射排队 + 距离/角度过滤）| `aircraft.gd:1468` _update_rocket |
| 单发火箭出膛 | `aircraft.gd:1531` _launch_rocket |
| 火箭弹生成（BulletManager 共享） | `bullet_manager.gd:38` spawn_rocket |
| 火箭弹命中 / 伤害无衰减 / 更大判定半径 | `bullet_manager.gd` _physics_process 分支 `is_rocket` |
| 橙红尾迹 + 白色弹头绘制 | `bullet_manager.gd` _draw 分支 `is_rocket` |
| 火箭弹字段（AircraftParams） | `aircraft_params.gd` `rocket: RocketParams` |
| F-86 火箭资源 | `resources/rocket_ffar.tres` |

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
| 武器模式切换（MISSILE/GUN） | `aircraft.gd:1599` _update_weapon_mode |
| 战术偏好武器模式（带机炮回退） | `aircraft.gd:1630` _update_weapon_mode_tactical |
| 导弹打不中但机炮能打（有滞回） | `aircraft.gd:1667` _missile_cannot_hit_but_gun_can |
| 机炮冲锋：进入承诺判定 | `aircraft.gd:1688` _should_commit_gun_pass |
| 机炮冲锋：冲锋完成判定 | `aircraft.gd:1696` _is_gun_pass_finished |
| 导弹发射主逻辑 | `aircraft.gd:1811` _update_missile |
| 导弹阻断日志（被锁/RNG/能量等原因） | `aircraft.gd:1796` _log_msl_block |
| 单枚发射 | `aircraft.gd:1909` _fire_missile_at |
| 多目标齐射 | `aircraft.gd:1931` _fire_multi_lock_salvo |
| 最优目标选择（评分） | `aircraft.gd:1977` _select_best_missile_target |
| 射程包线检查 | `aircraft.gd:2026` _is_in_missile_envelope |
| 导弹阶段判定（接近/照射/保持） | `aircraft.gd:1571` _get_missile_phase |
| 是否应该用机炮 | `aircraft.gd:1588` _should_use_gun |
| Crank 状态查询 | `aircraft.gd:1709` is_cranking |
| 导弹射程（像素） | `aircraft.gd:1544` _missile_range_px |
| 有效导弹射程=min(导弹,雷达)像素 | `aircraft.gd:1554` _effective_missile_range_px |
| 有效射程（像素） | `aircraft.gd:1565` _effective_range_px |
| 导弹飞行物理+PN制导 | `missile.gd:37` _physics_process |
| 导弹低空制导衰减 | `missile.gd:238` _guidance_degradation |
| 导弹生成 | `missile_manager.gd:20` spawn_missile |
| 导弹命中检测+连锁弹头 | `missile_manager.gd:56` _physics_process |
| 在飞导弹查询 | `missile_manager.gd:48` has_active_missile_at |
| 近炸引信 AOE 生成 | `missile_manager.gd:109` _spawn_aoe |
| AOE 区域更新+伤害 | `missile_manager.gd:126` _update_aoe_zones |
| AOE 红圈渲染 | `missile_manager.gd:157` _draw |
| 弹跳目标查找 | `missile_manager.gd:166` _find_bounce_target |

## 热诱弹/反制

| 功能 | 位置 |
|------|------|
| 热诱弹系统更新（含失误判定） | `aircraft.gd:3147` _update_flares |
| 释放热诱弹（target_missile 可选，针对性释放）| `aircraft.gd:3245` _release_flares |
| 干扰成功率计算 | `aircraft.gd:3307` _calc_jam_chance |
| 粒子更新 | `aircraft.gd:3341` _update_flare_particles |
| 失误概率 / 对头减免（FlareParams 字段） | `flare_params.gd:19-22` fail_chance / head_on_fail_reduction |
| 规避模式（导弹来袭 S 型 + 降高度）| `aircraft.gd:1724` _update_evasion |
| 规避模式开关（AI → Aircraft） | `aircraft.gd:1714` set_evasion_mode |
| 眼镜蛇机动模块 | `cobra_maneuver.gd` CobraManeuver（挂载到 Aircraft 子节点） |
| 眼镜蛇机动激活 | `cobra_maneuver.gd` activate |
| 战术机动查询（通用） | `aircraft.gd` get_maneuver |
| AI 控制器查询 | `aircraft.gd` _get_ai_controller |
| 眼镜蛇后方判定（AI） | `ai_controller.gd` _is_missile_from_rear |
| 锁定免疫检查 | `aircraft.gd:2721` is_lock_immune |

## 伤害与击毁

| 功能 | 位置 |
|------|------|
| 受伤（导弹） | `aircraft.gd:2065` take_damage |
| 受伤（机炮，含闪避） | `aircraft.gd:2077` take_bullet_damage |
| 内部伤害应用 | `aircraft.gd:2091` _apply_damage |
| 地面撞击检查 | `aircraft.gd:2100` _check_ground_crash |
| 击毁流程 | `aircraft.gd:2106` _start_destroy |
| 坠落动画 | `aircraft.gd:2117` _update_destroy |
| 基类伤害 | `combat_unit.gd:81` take_damage |

## 雷达系统

| 功能 | 位置 |
|------|------|
| 雷达锥判定（飞机） | `aircraft.gd:2134` is_in_radar_cone |
| 雷达锥判定（地面单位） | `ground_unit.gd:211` is_in_radar_cone |
| 雷达锥判定（SAM，360°） | `sam_unit.gd:54` is_in_radar_cone |
| 全局锁定计算循环 | `main.gd:226` _update_radar_locks |
| 低空锁定速率衰减 | `main.gd:300` _lock_rate_for_tier（静态方法） |
| 雷达数据链共享 | `radar_station.gd:35` _update_datalink |

## AI 控制器

| 功能 | 位置 |
|------|------|
| AI 主循环 | `ai_controller.gd:179` _physics_process |
| └ 写入 aircraft.tactical_aggression（effective_skill×aggression）| `ai_controller.gd:200` |
| 有效技能（压力衰减） | `ai_controller.gd:217` _effective_skill |
| 压力更新 | `ai_controller.gd:298` _update_stress |
| 漂移/判断失误 | `ai_controller.gd:327` _update_drift |
| Simple AI（UAV用） | `ai_controller.gd:380` _process_simple |
| └ 护驾长机失效检测（Sentinel 坠毁）| `ai_controller.gd:384-390` |
| └ 绕长机飞行分支（orbit_squad_leader）| `ai_controller.gd:397` |
| └ 护驾战斗脱离（tether check）| `ai_controller.gd:436-451` |
| Simple AI 交战 | `ai_controller.gd:512` _try_engage_simple |
| └ 护驾过滤（目标必须在 tether 内）| `ai_controller.gd:530-536` |
| orbit_squad_leader 导出变量 | `ai_controller.gd:59` |
| 绕长机飞行常量 | `ai_controller.gd:66-69` ORBIT_RADIUS=400/ANGULAR_SPEED=0.22/SPEED_RATIO=0.85/TETHER=550 |
| 巡逻逻辑 | `ai_controller.gd:546` _process_patrol |
| 编队跟随逻辑 | `ai_controller.gd:576` _process_squad_follow |
| └ 协同攻击触发（反应延迟） | `ai_controller.gd:639` 块内 |
| 掩护扫描（队友后方） | `ai_controller.gd:670` _scan_leader_rear |
| BVR 狙击模式（F-47 专用） | `ai_controller.gd` bvr_only 标志 → _process_engage 距离检查 + _choose_tactic 过滤 |
| BVR 被追 → Herbst 触发 | `ai_controller.gd` _process_engage 内 bvr_only 分支：后半球检测 + get_herbst().activate() |
| 协同齐射广播 | `ai_controller.gd` broadcast_salvo + process_salvo |
| 赫尔贝特轮机动 | `herbst_maneuver.gd` HerbstManeuver（DECEL→TURN 180°→ACCEL，15s 冷却，可重复） |
| 光学隐形（F-47） | `aircraft.gd` is_cloaked / _cloak_alpha → _draw() 淡出 + is_lock_immune() + missile.gd 丢失制导 |
| F-47 战术状态机 | `survivor_mode.gd` F47Tactic enum（INTRO/ORBIT/ATTACK_RUN/SCATTER/REGROUP） |
| F-47 隐形计时器 | `survivor_mode.gd` _update_f47_cloak — 60s 周期 / 5.5s 隐形 / 0.5s 淡入淡出 |
| 交战主逻辑 | `ai_controller.gd:715` _process_engage |
| └ 长机目标丢失宽限（防抖动） | `ai_controller.gd:748` |
| └ 长机目标超射程宽限 | `ai_controller.gd:764` |
| 态势分析数据 | `ai_controller.gd:848` _assess_situation |
| Lufberry 检测 | `ai_controller.gd:902` _update_lufberry_detection |
| 战术选择决策树 | `ai_controller.gd:931` _choose_tactic |
| 应用新战术 | `ai_controller.gd:1012` _apply_new_tactic |
| 判断失误（低技术） | `ai_controller.gd:1056` _make_mistake |
| 前置追踪执行 | `ai_controller.gd:1088` _execute_lead_pursuit |
| 滞后追踪执行 | `ai_controller.gd:1100` _execute_lag_pursuit |
| 提前转弯执行 | `ai_controller.gd:1112` _execute_lead_turn |
| 高悠悠执行 | `ai_controller.gd:1124` _execute_high_yoyo |
| 低悠悠执行 | `ai_controller.gd:1165` _execute_low_yoyo |
| 急转防御执行 | `ai_controller.gd:1208` _execute_break_turn |
| 加速脱离执行 | `ai_controller.gd:1240` _execute_extension |
| 剪刀机动执行 | `ai_controller.gd:1261` _execute_scissors |
| 导弹规避流程 | `ai_controller.gd:1320` _process_evade |
| 进入规避 | `ai_controller.gd:1351` _enter_evade |
| 退出规避 | `ai_controller.gd:1361` _exit_evade |
| 尝试进入交战 | `ai_controller.gd:1387` _try_engage |
| 目标重评估 | `ai_controller.gd:1459` _reevaluate_target |
| 脱离交战（重置宽限计时器） | `ai_controller.gd:1507` _disengage |
| 来袭导弹检查 | `ai_controller.gd:1536` _check_incoming_missile |
| 编队宽限常量 | `ai_controller.gd:72-75` LEADER_TARGET_LOST_GRACE / SQUAD_RANGE_GRACE |

## 编队系统

| 功能 | 位置 |
|------|------|
| 阵型偏移计算 | `squad.gd:51` get_formation_offset |
| 僚机世界坐标 | `squad.gd:114` get_wingman_target |
| 阵型循环 | `squad.gd:128` cycle_formation |
| 生成友方编队 | `main.gd:313` _spawn_friendly_squad |
| 生成敌方编队 | `main.gd:364` _spawn_enemies |

## 地面单位

| 功能 | 位置 |
|------|------|
| 地面单位移动 | `ground_unit.gd:63` _update_movement |
| 地面自动目标选择 | `ground_unit.gd:105` _update_target_selection |
| 地面机炮战斗 | `ground_unit.gd:131` _update_combat |
| 地面机炮射击 | `ground_unit.gd:164` _update_gun |
| SAM 导弹发射 | `sam_unit.gd:26` _update_sam_missile |
| AA 炮塔转向 | `aa_gun_unit.gd:69` _update_turret |
| AA 目标选择（最近） | `aa_gun_unit.gd:30` _update_aa_target_selection |
| 雷达站数据链 | `radar_station.gd:35` _update_datalink |
| 车队管理 | `ground_convoy.gd:12` add_member |

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
| 相机跟随插值 | `survivor_mode.gd:359` _process |
| 物理主循环（总入口） | `survivor_mode.gd:370` _physics_process |
| 选中列表清理 | `survivor_mode.gd:410` _cleanup_references |
| 飞机列表同步 | `survivor_mode.gd:417` _update_aircraft_list |

#### 雷达锁定
| 功能 | 位置 |
|------|------|
| 全局锁定计算 | `survivor_mode.gd:429` _update_radar_locks |

#### 动态性能 / LOD / 清理
| 功能 | 位置 |
|------|------|
| FPS 采样与动态上限调整 | `survivor_mode.gd:514` _update_fps_sampling |
| 平均 FPS 查询 | `survivor_mode.gd:535` _get_avg_fps |
| 屏幕外 AI/物理降频 | `survivor_mode.gd:543` _update_offscreen_lod |
| 已坠毁敌机清理 | `survivor_mode.gd:578` _cleanup_destroyed_enemies |
| 远距清理（释放 Token） | `survivor_mode.gd:586` _update_far_cleanup |

#### 猎手系统
| 功能 | 位置 |
|------|------|
| 猎手指派主循环 | `survivor_mode.gd:610` _update_hunters |
| 空闲敌机航点围绕玩家 | `survivor_mode.gd:661` _update_enemy_waypoints |
| 获取 AI 控制器 | `survivor_mode.gd:685` _get_ai |
| 导弹上限查询（飞向玩家数）| `survivor_mode.gd:691` _count_missiles_targeting_player |
| 筛选未发射敌机 | `survivor_mode.gd:700` _get_enemies_without_active_missile_at_player |
| 敌人数统计 | `survivor_mode.gd:715` _count_enemies |

#### 刷怪 & Token 烈度控制
| 功能 | 位置 |
|------|------|
| 刷怪主逻辑（每波间隔/FPS闸/Token 预算）| `survivor_mode.gd:722` _update_spawner |
| 当前 Token 预算（随等级增长）| `survivor_mode.gd:846` _get_token_budget |
| 重算场景 Token 占用 & 每类数量 | `survivor_mode.gd:851` _recalc_token_usage |
| 指定类型是否可生成（预算+实例上限）| `survivor_mode.gd:863` _can_spawn_type |
| 按等级选敌机类型（概率 + Token 约束）| `survivor_mode.gd:874` _pick_enemy_type |
| 单机生成（J-7 / MiG-31）| `survivor_mode.gd:934` _spawn_single |
| 编队生成（MiG-29 / F-86 / MiG-23 / F-100 / A-7 / Q-5 / UAV / UCAV）| `survivor_mode.gd:942` _spawn_squad |
| 指挥 UAV 小队生成（Sentinel + UAV 僚机）| `survivor_mode.gd:982` _spawn_commander_squad |
| F-47 BOSS 小队生成（菱形 4 架 + 登场通场） | `survivor_mode.gd` _spawn_f47_squad |
| F-47 BOSS 狙击循环更新（站位/撤退/全灭检测）| `survivor_mode.gd` _update_f47_squad |
| 创建敌机实体（参数/AI/缩放/Token meta）| `survivor_mode.gd:1038` _create_enemy |
| └ base_params match（**新增敌人改这里**） | `:1041` |
| └ enemy_scale 适用判定 | `:1075` |
| └ no_stamina 排除 | `:1103` |
| └ type_tag 映射 | `:1108` |
| └ AI 分支（**F86:1183 / MIG31:1195 / MIG23:1208 / F100:1220 / Sentinel:1233**） | `:1157-1244` |
| 无效分队清理 | `survivor_mode.gd:1249` _cleanup_squads |

> **敌人类型与 archetype 映射**（EnemyType enum + 适用 archetype）：
> - `UAV(0)` `UCAV(1)` — Adds 杂鱼，1 级一起开局，等权重 50/50
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
| 击杀检测 & 经验奖励 & 回血 | `survivor_mode.gd:1261` _detect_kills |
| 玩家升级回调（暂停+弹选项）| `survivor_mode.gd:1286` _on_player_leveled_up |
| 升级选中回调（应用+进化判定）| `survivor_mode.gd:1311` _on_upgrade_selected |
| 玩家死亡 | `survivor_mode.gd:1342` _on_player_died |

#### 噪声/绘制
| 功能 | 位置 |
|------|------|
| 地形噪声初始化 | `survivor_mode.gd:1350` _init_noise |
| 主 _draw 入口 | `survivor_mode.gd:1365` _draw |
| 地形类型判定 | `survivor_mode.gd:1369` _get_terrain_type |
| 地形单元绘制 | `survivor_mode.gd:1387` _draw_terrain |
| 网格绘制 | `survivor_mode.gd:1430` _draw_grid |

### survivor_player.gd — 玩家状态（127 行）

| 功能 | 位置 |
|------|------|
| 信号 leveled_up | `survivor_player.gd:7` |
| 经验累加/升级触发 | `survivor_player.gd:20` add_xp |
| 应用升级（修改 aircraft.params）| `survivor_player.gd:30` apply_upgrade |
| └ max_hp / missile_count / tracking | `survivor_player.gd:37-50` |
| └ gun_damage / multishot / ammo / regen / firerate | `survivor_player.gd:58-72` |
| └ radar_range / lock_time / speed / maneuver | `survivor_player.gd:73-85` |
| └ flare / pilot_stamina / kill_heal / dogfight | `survivor_player.gd:86-112` |
| HP 查询 | `survivor_player.gd:114` get_hp |

### survivor_data.gd — 参数表（322 行）

| 功能 | 位置 |
|------|------|
| 升级定义表 UPGRADES（常量）| `survivor_data.gd:12` |
| 刷怪基础常量（BASE/MIN/SPAWN_DISTANCE）| `survivor_data.gd:210-214` |
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
| 主循环（扫描+招募+buff） | `commander_aura.gd:36` _physics_process |
| 增益扫描（仅小队成员） | `commander_aura.gd:55` _scan_and_buff |
| 清理已毁 buff 单位 | `commander_aura.gd:79` _cleanup_buffed |
| 应用 buff（G/结构/滚转/速度/加速/失速）| `commander_aura.gd:93` _apply_buff |
| 移除单个 buff | `commander_aura.gd:124` _remove_buff |
| 移除全部 buff | `commander_aura.gd:145` _remove_all_buffs |
| 招募新成员（允许从普通编队挖人）| `commander_aura.gd:155` _try_recruit |
| 析构时清理 | `commander_aura.gd:222` _exit_tree |
| 查找 AI 控制器 | `commander_aura.gd:229` _find_ai |

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
| UI 构建 | `survivor_hud.gd:55` _build_ui |
| 输入（暂无实际用途） | `survivor_hud.gd:230` _unhandled_input |
| 主循环（更新显示） | `survivor_hud.gd:235` _process |
| UI 自适应布局 | `survivor_hud.gd:245` _layout_ui |
| HP/XP/等级 显示更新 | `survivor_hud.gd:289` _update_display |
| 状态面板（飞机属性）| `survivor_hud.gd:309` _update_status_panel |
| 战术按钮创建 | `survivor_hud.gd:403` _create_tac_button |
| 武器/高度/规避按键回调 | `survivor_hud.gd:448-478` |
| 战术 tooltip | `survivor_hud.gd:481` _on_tac_hover |
| 战术按钮状态刷新 | `survivor_hud.gd:541` _update_tactical_buttons |
| Debug 面板文字更新 | `survivor_hud.gd:555` _update_debug_panel |
| 游戏结束画面 | `survivor_hud.gd:587` show_game_over |

### survivor_upgrade_ui.gd — 升级选择界面（124 行）

| 功能 | 位置 |
|------|------|
| 信号 upgrade_selected | `survivor_upgrade_ui.gd:6` |
| UI 构建 | `survivor_upgrade_ui.gd:20` _build_ui |
| 显示三选一 | `survivor_upgrade_ui.gd:94` show_choices |
| 选择回调 | `survivor_upgrade_ui.gd:121` _on_choice_pressed |

### survivor_debug_skills.gd — F4 技能面板（299 行）

| 功能 | 位置 |
|------|------|
| F4 开关（打开时暂停）| `survivor_debug_skills.gd:23` _unhandled_input |
| UI 构建 | `survivor_debug_skills.gd:32` _build_ui |
| 按钮样式 | `survivor_debug_skills.gd:149` _apply_btn_style |
| 列表刷新 | `survivor_debug_skills.gd:163` _refresh |
| 设置等级 | `survivor_debug_skills.gd:242` _on_set_level |
| 触发升级（+1） | `survivor_debug_skills.gd:251` _on_levelup |
| 按 ID 添加技能 | `survivor_debug_skills.gd:261` _on_add_skill_by_id |
| 添加选中技能 | `survivor_debug_skills.gd:271` _on_add_skill |
| 移除技能 | `survivor_debug_skills.gd:287` _on_remove_skill |

### survivor_debug_spawn.gd — F5 刷怪面板（274 行）

| 功能 | 位置 |
|------|------|
| 编队类型枚举 FormationType | `survivor_debug_spawn.gd:19` |
| 敌机类型标签表 | `survivor_debug_spawn.gd:28` ENEMY_TYPE_LABELS |
| F5 开关（不暂停）| `survivor_debug_spawn.gd:42` _unhandled_input |
| UI 构建（下拉/规模/按钮）| `survivor_debug_spawn.gd:55` _build_ui |
| 类型切换联动编队 | `survivor_debug_spawn.gd:221` _on_type_changed |
| 编队模式切换 | `survivor_debug_spawn.gd:228` _on_formation_changed |
| 刷怪按钮（调 _spawn_*）| `survivor_debug_spawn.gd:231` _on_spawn_pressed |
| 清空敌人按钮 | `survivor_debug_spawn.gd:259` _on_clear_pressed |
| 导出日志按钮（替代 F9）| `survivor_debug_spawn.gd:271` _on_dump_pressed |

### survivor_select.gd — 机型选择界面（263 行）

| 功能 | 位置 |
|------|------|
| 可选机型列表 AIRCRAFT_LIST | `survivor_select.gd:19` |
| UI 构建 | `survivor_select.gd:75` _build_ui |
| 机型卡片构建 | `survivor_select.gd:140` _build_aircraft_card |
| 选中回调（写 meta 进下一场景）| `survivor_select.gd:259` _on_aircraft_selected |
| 背景绘制 | `survivor_select.gd:42` _draw |

## 主场景/操控

| 功能 | 位置 |
|------|------|
| 鼠标输入 | `main.gd:84` _unhandled_input |
| 左键点击（锁定/移动） | `main.gd:138` _on_left_click |
| 右键取消 | `main.gd:155` _on_right_click |
| 悬停检测 | `main.gd:208` _update_hover |
| LOD 管理 | `main.gd:455` _update_lod |
| 地形绘制 | `main.gd:515` _draw_terrain |

## 视觉绘制

| 功能 | 位置 |
|------|------|
| 飞机绘制入口 | `aircraft.gd:1710` _draw |
| 飞机线框图标 | `aircraft.gd:1850` _draw_aircraft_icon |
| 指挥型图标 | `aircraft.gd:1945` _draw_commander_icon |
| 雷达锥绘制 | `aircraft.gd:1732` _draw_radar_cone |
| 锁定警告闪烁 | `aircraft.gd:1768` _draw_lock_indicator |
| 数据标签（完整） | `aircraft.gd:2044` _draw_data_label |
| 数据标签（简化） | `aircraft.gd:2003` _draw_data_label_minimal |
| 机头闪光 | `aircraft.gd:1787` _draw_muzzle_flash |
| 加力火焰 | `aircraft.gd:1796` _draw_afterburner_glow |
| 热诱弹粒子 | `aircraft.gd:1818` _draw_flare_particles |
| 目标连线 | `aircraft.gd:2138` _draw_target_line |
| 预测轨迹 | `aircraft.gd:2176` _draw_predicted_path |
| 战术提示弹窗 | `aircraft.gd:2118` _draw_tactic_popup |

## HUD / UI

| 功能 | 位置 |
|------|------|
| 沙盒 HUD | `hud.gd:7` _process |
| 生存模式 HUD 构建 | `survivor_hud.gd:55` _build_ui |
| 生存模式 HUD 更新 | `survivor_hud.gd:289` _update_display |
| 状态面板更新 | `survivor_hud.gd:309` _update_status_panel |
| 战术按钮 | `survivor_hud.gd:403` _create_tac_button |
| 升级 UI 选项展示 | `survivor_upgrade_ui.gd:94` show_choices |
| 调试面板构建 | `debug_panel.gd:41` _build_ui |
| 调试面板内容更新 | `debug_panel.gd:183` _update_content |
| 战斗策略文本 | `debug_panel.gd:299` _get_combat_strategy |
| 飞行员信息 | `debug_panel.gd:318` _get_pilot_info |
| 地面单位生成按钮 | `debug_panel.gd:648` _spawn_ground_unit |
| Game Over 显示 | `survivor_hud.gd:587` show_game_over |

## 资源参数文件

| 资源 | 文件 |
|------|------|
| F-16（友方） | `resources/default_fighter.tres` |
| MiG-29（敌方） | `resources/enemy_fighter.tres` |
| J-7 截击机 | `resources/enemy_interceptor.tres` |
| UAV | `resources/enemy_uav.tres` |
| UCAV（导弹型） | `resources/enemy_uav_missile.tres` |
| Sentinel 指挥UAV | `resources/enemy_uav_commander.tres` |
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
| 沙盒主场景 | `scenes/main.tscn` | Main + BulletManager + MissileManager + Camera2D + PlayerAircraft + DebugPanel |
| 生存模式 | `scenes/survivor_mode.tscn` | SurvivorMode + BulletManager + MissileManager + Camera2D |
| 飞机模板 | `scenes/aircraft.tscn` | Aircraft (Node2D + aircraft.gd) |
| 导弹模板 | `scenes/missile.tscn` | Missile (Node2D + missile.gd) |
| SAM 单位 | `scenes/sam_unit.tscn` | SAMUnit + sam_params |
| AA 单位 | `scenes/aa_gun_unit.tscn` | AAGunUnit + aa_gun_params |
| 雷达站 | `scenes/radar_station.tscn` | RadarStation + radar_station_params |
| 主菜单 | `scenes/main_menu.tscn` | MainMenu |
| 模式选择 | `scenes/survivor_select.tscn` | SurvivorSelect |
