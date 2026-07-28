# Repository Layout

> 最后校订：2026-07-26（对照实际目录重建）。
>
> 本文只回答"**东西大致在哪个目录**"。单个文件的职责 + 关键入口看
> [script-index.md](script-index.md)；按功能主题找代码看 [code-index.md](code-index.md)。
> 这里**刻意不写行号也不写行数**——那种注解一定会腐烂。

```
AGL/
├── project.godot              # 项目配置 + AutoLoad 注册（入口场景 = scenes/main_menu.tscn）
├── CLAUDE.md / AGENTS.md      # AI 协作导航 + 硬约定
├── export_presets.cfg
│
├── scenes/
│   ├── main_menu.tscn             # 主菜单（入口场景）
│   ├── survivor_mode.tscn         # 生存模式主场景（BulletManager + MissileManager + Camera2D）
│   ├── survivor_map_select.tscn   # 地图选择（生存流程第一步；B → boss_debug_select）
│   ├── survivor_select.tscn       # 机型选择
│   ├── boss_debug_select.tscn     # BOSS 测试场（全机型 × 技能组合）
│   ├── map_editor.tscn            # 地图编辑器（UGC）
│   ├── map_manual.tscn            # 手画地块编辑参考场景
│   ├── building_preloader.tscn
│   ├── aircraft.tscn              # 飞机模板（通用）
│   ├── missile.tscn               # 导弹模板
│   ├── sam_unit.tscn / aa_gun_unit.tscn / radar_station.tscn
│   └── main.tscn                  # ⚠ 沙盒主场景，**已废弃**（只作调试留存，不打包）
│
├── scripts/
│   ├── ── 共享实体层 ──
│   │   combat_unit.gd             # 战斗单位基类（team/hp/altitude/雷达/锁定）
│   │   aircraft.gd                # Aircraft 实体：LOD 路由 + 损伤 + 状态所有者（细节全部委托 aircraft/）
│   │   aircraft_renderer.gd       # 飞机绘制系统
│   │   aircraft_destruction.gd    # 坠毁动画（fighter / bomber / heli 三种风格）
│   │   ai_controller.gd           # AI 状态机路由（战术/规避/目标选择/编队委托 ai/）
│   │   pilot_personality.gd       # 飞行员心理（压力 / SA / 判断误差）
│   │   missile.gd / missile_manager.gd
│   │   bullet_manager.gd
│   │   ground_unit.gd / sam_unit.gd / aa_gun_unit.gd / radar_station.gd / ground_convoy.gd
│   │   squad.gd / squad_factory.gd    # 编队数据结构 + 阵型计算
│   │   status_effects.gd          # FEAR/JAM/SLOW/STEALTH/INVINCIBLE/OVERLOAD/BLOODLUST
│   │   cobra_maneuver.gd / herbst_maneuver.gd
│   │   trail_ribbon.gd / explosion_vfx.gd / weather_system.gd
│   │   terrain_renderer.gd / camera_controller.gd
│   │   lock_warning.gd
│   │   game_constants.gd / theme_colors.gd
│   │
│   ├── ── Resource 定义 ──
│   │   aircraft_params.gd / gun_params.gd / missile_params.gd / rocket_params.gd
│   │   torpedo_params.gd / flare_params.gd / combat_params.gd / loyal_wingman_params.gd
│   │   playable_aircraft.gd       # 主角档案（UI + 生存调味注入）
│   │
│   ├── ── AutoLoad ──
│   │   callsign_db.gd / event_logger.gd / locale_manager.gd
│   │   audio/audio_manager.gd / meta/merit_ledger.gd
│   │
│   ├── aircraft/              # Aircraft 子系统（RefCounted 静态模块，首参 ac: Aircraft）
│   │   ├── aircraft_physics.gd         # bank/heading/speed/altitude/stall/g + effective_*() accessor 层
│   │   ├── aircraft_weapons.gd         # gun/rocket/missile/副槽/齐射/weapon_mode
│   │   ├── aircraft_combat_tracking.gd # 战斗追踪 + 狗斗追击点 + 对地攻击
│   │   ├── aircraft_formation.gd       # LOD 1 编队托管三段式（顶部有"常见 bug 回溯地图"）
│   │   ├── aircraft_flares.gd          # 热诱弹释放 / jam 概率 / 多波 reload
│   │   ├── control_intent.gd / flight_state.gd
│   │
│   ├── ai/                    # AI 子系统（RefCounted 静态模块，首参 ai: AIController）
│   │   ├── bfm_tactics.gd              # BFM 战术执行器 + choose_tactic + assess_situation
│   │   ├── target_selection.gd         # 交战 / 重评估 / 脱战
│   │   ├── missile_evasion.gd          # 规避 + 来袭检测 + Herbst 触发
│   │   ├── squad_coordination.gd       # 编队协同 + 后半球扫描 + cover + salvo 广播
│   │   ├── escort_behavior.gd / joust_controller.gd / objective_context.gd
│   │   ├── swarm/                      # 蜂群指挥（SwarmDirector + 参数）
│   │   └── tactical/                   # 统一决策路径：决策 / 执行分离
│   │       ├── situation.gd            # 态势快照（输入）
│   │       ├── tactical_plan.gd        # 决策输出（值类型）
│   │       ├── bfm_intent.gd           # intent 纯函数
│   │       ├── tactical_planner.gd     # 顶层决策树 + hysteresis 防抖
│   │       ├── weapon_selector.gd      # 武器竞选
│   │       └── engagement_speed_governor.gd
│   │
│   ├── equipment/             # 模块化装备系统（新机型走这里，老机型走 AircraftParams 旧字段）
│   │   equipment_params.gd（基类）/ engagement_preference.gd（装备投票）
│   │   gun_ / rocket_ / missile_ / flare_ / railgun_ / laser_equipment.gd
│   │   evasion_module.gd + cobra_evasion.gd / herbst_evasion.gd
│   │
│   ├── survivor/              # 生存模式专属（最大的目录，~65 个文件）
│   │   survivor_mode.gd           # 主控（帧循环 / 阶段闸 / 玩家机登记 chokepoint / 胜负）
│   │   survivor_spawner.gd        # 刷怪：Token / 猎手 / 增援入场 / FPS 降载
│   │   survivor_data.gd           # 静态数据：技能表 / Token 成本 / 缩放常量 / XP 曲线
│   │   survivor_player.gd / skill_hooks.gd        # 等级与升级应用 / 事件型技能钩子
│   │   survivor_hud.gd / tactical_map.gd / boundary_ui.gd / xp_gain_vfx.gd
│   │   survivor_select.gd / survivor_map_select.gd
│   │   survivor_playable_setup.gd                  # PlayableAircraft → Aircraft 应用器
│   │   zone_data.gd / zone_mission.gd / zone_arrow.gd / zone_hint.gd / dock_point.gd
│   │   evolution_system.gd / evolution_ui.gd / evolution_tree_view.gd
│   │       / evolution_detail_panel.gd / axis_bars_panel.gd
│   │   aircraft_db.gd / aircraft_codex.gd
│   │   ace_tier.gd / ace_squad.gd / ace_support_squad.gd / f47_ace_squad.gd
│   │   wraith_tactics.gd / poltergeist_squad.gd / poltergeist_tactics.gd
│   │   boss_registry.gd / boss_encounter.gd / mother_goose_*.gd
│   │   carrier_strike_group.gd
│   │   roe_director.gd / adbs_manager.gd / afterburner_charge.gd
│   │   aoe_broadcast.gd / aoe_pulse_vfx.gd
│   │   radio_chatter.gd / chatter_lines.gd
│   │   commander_aura.gd / commander_overlay.gd
│   │   map_geography.gd / map_geography_data.gd / map_feature_renderer.gd
│   │       / map_boundary.gd / map_manual_background.gd
│   │   building_renderer.gd / building_preloader.gd
│   │   survivor_tutorial*.gd
│   │   survivor_debug_skills.gd / survivor_debug_spawn.gd / survivor_debug_zone.gd
│   │       / boss_debug_select.gd / boss_debug_builds.gd
│   │
│   ├── rts/                   # RTS 指挥（独立模块，**不塞 survivor_mode**）
│   │   squad_command_controller.gd / command_wheel.gd
│   │   rts_command_params.gd / command_wheel_params.gd
│   │
│   ├── events/                # 剧本系统：GameEvent + AIDirective + EventDirector
│   │   game_event.gd / event_director.gd / ai_directive.gd
│   │   boss_encounter_event.gd / ace_reinforcement_event.gd
│   │   awacs_support_event.gd / ally_force.gd
│   │
│   ├── presentation/          # 表演导演：转场 / 镜头 / 时间 / 演出
│   │   time_authority.gd（时间请求栈，Engine.time_scale 唯一写入点）
│   │   sequence_player.gd / presentation_director.gd
│   │   stage_isolator.gd / cinematic_cast.gd / ease_lib.gd
│   │
│   ├── naval/                 # 海上单位 + 挂点 / 弱点伤害路由
│   │   naval_unit.gd / naval_weapons.gd / naval_params.gd / naval_destruction.gd
│   │   carrier_ / cruiser_ / destroyer_ / frigate_ / submarine_ship.gd
│   │   weapon_mount.gd / weapon_mount_params.gd / mount_target.gd / weak_point.gd
│   │   naval_ship_names.gd
│   │
│   ├── zones/                 # 战区
│   │   zone.gd / naval_zone.gd / zone_manager.gd / zone_types.gd
│   │
│   ├── meta/                  # 局外层
│   │   merit_ledger.gd（AutoLoad）/ merit_coin_icon.gd
│   │
│   ├── ugc/                   # 地图编辑器 + UGC
│   │   map_document.gd / map_editor_scene.gd / map_editor_canvas.gd
│   │   contour_baker.gd / official_map_converter.gd / ugc_loader.gd
│   │
│   ├── audio/                 # audio_manager.gd（AutoLoad）/ audio_settings_panel.gd
│   ├── util/                  # unit_grid.gd（空间网格）/ perf_buckets.gd
│   ├── tests/                 # 无头断言测试（~44 个 test_*.gd）
│   ├── bench/                 # bench_runner.gd —— `--bench=<name>` 的注册与调度
│   ├── tools/                 # 地图烘焙 Python（bake_tokyo_bay / bake_buildings / download_basemap）
│   │
│   └── ── 沙盒（已废弃，仅调试留存）──
│       main.gd / hud.gd / debug_panel.gd
│
├── resources/                 # .tres 参数资源
│   ├── player/                    # 玩家机档案（41 机）
│   ├── evolution/                 # 进化树相关
│   ├── weapons/ / equipment/      # 武器与装备
│   ├── naval/                     # 舰船
│   ├── chatter/                   # radio_chatter.json（无线电台词，数据全外置）
│   ├── presentation/              # sequences.json（演出时间线，F8 热重载）
│   ├── maps/                      # 地图数据（JSON / PNG 底图）
│   ├── shaders/                   # 地图 shader
│   └── *.tres                     # 敌机 / 通用武器 / 战斗风格
│
├── i18n/                      # translations.csv + 三语 .translation（中 / 英 / 日）
├── audio/                     # music/ · sfx/ · ui/ · radio/
├── tools/                     # 校验与生成脚本（Python / PowerShell）
│   verify_doc_anchors.py          # 索引锚点校验（commit 前跑）
│   verify_player_ref_holders.py   # SEAM-019 玩家机引用持有者校验（commit 前跑）
│   dump_skill_table.py            # 重刷 docs/reference/skill-table.md
│   seam-report.ps1
├── bench/                     # bench 输出
├── logs/                      # 编辑器模式的战斗日志（.gitignore 排除）
├── addons/
└── docs/                      # 见 docs/project-overview.md
```
