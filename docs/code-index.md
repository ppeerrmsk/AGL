# 代码索引

按功能主题索引到 `文件:行号`，直接 Read 对应行号即可获取上下文。

---

## 飞行物理

| 功能 | 位置 |
|------|------|
| 物理主循环 | `aircraft.gd:154` _physics_process |
| 目标航向计算 | `aircraft.gd:339` _update_target_heading |
| 滚转角更新（含导弹阶段限制） | `aircraft.gd:359` _update_bank |
| 航向更新 ω=g×tan(bank)/speed | `aircraft.gd:479` _update_heading |
| 速度更新（含高G阻力、高度耦合） | `aircraft.gd:497` _update_speed |
| 高度更新 | `aircraft.gd:534` _update_altitude |
| 失速检查 | `aircraft.gd:548` _update_stall |
| G力计算 | `aircraft.gd:569` _update_g_load |
| 飞行员耐力 | `aircraft.gd:578` _update_pilot_stamina |
| 位移应用 | `aircraft.gd:591` _apply_movement |
| 最大 bank 角（受耐力影响） | `aircraft.gd:599` _max_bank_angle |
| 有效最大G（耐力插值） | `aircraft.gd:619` _effective_max_g |
| 失速速度 V_stall×√G | `aircraft.gd:627` _stall_speed |
| 高空最大速度衰减 | `aircraft.gd:632` _max_speed_at_altitude |
| 空气密度比 σ=e^(-alt/8500) | `aircraft.gd:638` _air_density_ratio |
| 高度档位切换（生存模式） | `aircraft.gd:646` set_target_tier |

## 能量管理

| 功能 | 位置 |
|------|------|
| 能量管理总入口 | `aircraft.gd:690` _update_energy_management |
| 加力燃烧器开关 | `aircraft.gd:661` _set_afterburner |
| 燃油消耗 | `aircraft.gd:671` _update_fuel |

## 战斗追踪（Aircraft 内置）

| 功能 | 位置 |
|------|------|
| 战斗追踪主逻辑（空对空） | `aircraft.gd:930` _update_combat |
| 对地攻击（跑道进入式） | `aircraft.gd:1081` _update_combat_ground_attack |
| 设定战斗目标 | `aircraft.gd:918` set_combat_target |
| 清除战斗目标 | `aircraft.gd:923` clear_combat_target |
| CombatParams 获取 | `aircraft.gd:1154` _combat_params |
| 自动扫描机炮目标 | `aircraft.gd:1169` _auto_gun_scan |

## 武器系统 — 机炮

| 功能 | 位置 |
|------|------|
| 机炮射击更新 | `aircraft.gd:1229` _update_gun |
| 机炮射程（像素） | `aircraft.gd:1162` _gun_range_px |
| 子弹生成 | `bullet_manager.gd:21` spawn_bullet |
| 子弹物理+命中检测 | `bullet_manager.gd:34` _physics_process |
| 曳光弹绘制 | `bullet_manager.gd:102` _draw |

## 武器系统 — 导弹

| 功能 | 位置 |
|------|------|
| 武器模式切换（MISSILE/GUN） | `aircraft.gd:1313` _update_weapon_mode |
| 战术偏好武器模式 | `aircraft.gd:1342` _update_weapon_mode_tactical |
| 导弹发射主逻辑 | `aircraft.gd:1402` _update_missile |
| 单枚发射 | `aircraft.gd:1474` _fire_missile_at |
| 多目标齐射 | `aircraft.gd:1496` _fire_multi_lock_salvo |
| 最优目标选择（评分） | `aircraft.gd:1542` _select_best_missile_target |
| 射程包线检查 | `aircraft.gd:1591` _is_in_missile_envelope |
| 导弹阶段判定（接近/照射/保持） | `aircraft.gd:1285` _get_missile_phase |
| 是否应该用机炮 | `aircraft.gd:1302` _should_use_gun |
| Crank 状态查询 | `aircraft.gd:1353` is_cranking |
| 导弹射程（像素） | `aircraft.gd:1272` _missile_range_px |
| 有效射程（像素） | `aircraft.gd:1279` _effective_range_px |
| 导弹飞行物理+PN制导 | `missile.gd:37` _physics_process |
| 导弹低空制导衰减 | `missile.gd:238` _guidance_degradation |
| 导弹生成 | `missile_manager.gd:11` spawn_missile |
| 导弹命中检测+连锁弹头 | `missile_manager.gd:46` _physics_process |
| 在飞导弹查询 | `missile_manager.gd:38` has_active_missile_at |
| 弹跳目标查找 | `missile_manager.gd:101` _find_bounce_target |

## 热诱弹/反制

| 功能 | 位置 |
|------|------|
| 热诱弹系统更新 | `aircraft.gd:2276` _update_flares |
| 释放热诱弹 | `aircraft.gd:2337` _release_flares |
| 干扰成功率计算 | `aircraft.gd:2397` _calc_jam_chance |
| 粒子更新 | `aircraft.gd:2431` _update_flare_particles |
| 规避模式（生存模式S型） | `aircraft.gd:1357` _update_evasion |
| 锁定免疫检查 | `aircraft.gd:2273` is_lock_immune |

## 伤害与击毁

| 功能 | 位置 |
|------|------|
| 受伤（导弹） | `aircraft.gd:1630` take_damage |
| 受伤（机炮，含闪避） | `aircraft.gd:1638` take_bullet_damage |
| 内部伤害应用 | `aircraft.gd:1647` _apply_damage |
| 地面撞击检查 | `aircraft.gd:1656` _check_ground_crash |
| 击毁流程 | `aircraft.gd:1662` _start_destroy |
| 坠落动画 | `aircraft.gd:1673` _update_destroy |
| 基类伤害 | `combat_unit.gd:81` take_damage |

## 雷达系统

| 功能 | 位置 |
|------|------|
| 雷达锥判定（飞机） | `aircraft.gd:1690` is_in_radar_cone |
| 雷达锥判定（地面单位） | `ground_unit.gd:211` is_in_radar_cone |
| 雷达锥判定（SAM，360°） | `sam_unit.gd:54` is_in_radar_cone |
| 全局锁定计算循环 | `main.gd:226` _update_radar_locks |
| 低空锁定速率衰减 | `main.gd:300` _lock_rate_for_tier（静态方法） |
| 雷达数据链共享 | `radar_station.gd:35` _update_datalink |

## AI 控制器

| 功能 | 位置 |
|------|------|
| AI 主循环 | `ai_controller.gd:161` _physics_process |
| Simple AI（UAV用） | `ai_controller.gd:362` _process_simple |
| Simple AI 交战 | `ai_controller.gd:447` _try_engage_simple |
| 巡逻逻辑 | `ai_controller.gd:472` _process_patrol |
| 编队跟随逻辑 | `ai_controller.gd:502` _process_squad_follow |
| 交战主逻辑 | `ai_controller.gd:616` _process_engage |
| 态势分析数据 | `ai_controller.gd:735` _assess_situation |
| Lufberry 检测 | `ai_controller.gd:789` _update_lufberry_detection |
| 战术选择决策树 | `ai_controller.gd:818` _choose_tactic |
| 应用新战术 | `ai_controller.gd:899` _apply_new_tactic |
| 判断失误（低技术） | `ai_controller.gd:943` _make_mistake |
| 前置追踪执行 | `ai_controller.gd:975` _execute_lead_pursuit |
| 滞后追踪执行 | `ai_controller.gd:987` _execute_lag_pursuit |
| 提前转弯执行 | `ai_controller.gd:999` _execute_lead_turn |
| 高悠悠执行 | `ai_controller.gd:1011` _execute_high_yoyo |
| 低悠悠执行 | `ai_controller.gd:1052` _execute_low_yoyo |
| 急转防御执行 | `ai_controller.gd:1095` _execute_break_turn |
| 加速脱离执行 | `ai_controller.gd:1127` _execute_extension |
| 剪刀机动执行 | `ai_controller.gd:1148` _execute_scissors |
| 导弹规避流程 | `ai_controller.gd:1207` _process_evade |
| 进入规避 | `ai_controller.gd:1238` _enter_evade |
| 退出规避 | `ai_controller.gd:1247` _exit_evade |
| 尝试进入交战 | `ai_controller.gd:1273` _try_engage |
| 目标重评估 | `ai_controller.gd:1344` _reevaluate_target |
| 脱离交战 | `ai_controller.gd:1392` _disengage |
| 来袭导弹检查 | `ai_controller.gd:1418` _check_incoming_missile |
| 掩护扫描（队友后方） | `ai_controller.gd:571` _scan_leader_rear |
| 态势感知更新 | `ai_controller.gd:215` _update_situational_awareness |
| 压力更新 | `ai_controller.gd:273` _update_stress |
| 漂移/判断失误 | `ai_controller.gd:320` _update_drift |

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

| 功能 | 位置 |
|------|------|
| 生存模式初始化 | `survivor_mode.gd:90` _ready |
| 物理循环（波次/猎手） | `survivor_mode.gd:340` _physics_process |
| 刷怪逻辑 | `survivor_mode.gd:665` _update_spawner |
| 敌机类型选择 | `survivor_mode.gd:726` _pick_enemy_type |
| 单体敌机生成 | `survivor_mode.gd:759` _spawn_single |
| 编队敌机生成 | `survivor_mode.gd:767` _spawn_squad |
| 指挥 UAV 编队生成 | `survivor_mode.gd:807` _spawn_commander_squad |
| 创建敌机实体 | `survivor_mode.gd:865` _create_enemy |
| 猎手指派 | `survivor_mode.gd:553` _update_hunters |
| 航点更新（追踪玩家） | `survivor_mode.gd:604` _update_enemy_waypoints |
| 击杀检测 | `survivor_mode.gd:1012` _detect_kills |
| 升级选择回调 | `survivor_mode.gd:1062` _on_upgrade_selected |
| 玩家死亡 | `survivor_mode.gd:1093` _on_player_died |
| FPS 采样/动态上限 | `survivor_mode.gd:482` _update_fps_sampling |
| 导弹上限查询 | `survivor_mode.gd:634` _count_missiles_targeting_player |
| 经验/升级/等级 | `survivor_player.gd:20` add_xp |
| 升级应用（修改params） | `survivor_player.gd:30` apply_upgrade |
| 升级定义表 | `survivor_data.gd:12` UPGRADES 常量 |
| 经验曲线 | `survivor_data.gd:205` xp_for_level |
| 刷怪常量 | `survivor_data.gd:210` BASE_SPAWN_INTERVAL 等 |
| 敌人属性缩放 | `survivor_data.gd:240` enemy_scale_for_level |
| 指挥 UAV 光环 | `commander_aura.gd:25` _physics_process |
| 指挥 UAV 招募 | `commander_aura.gd:168` _try_recruit |

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
