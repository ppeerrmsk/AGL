# Repository Layout

> 本节内容原在 CLAUDE.md，2026-05-05 移出。

```
AGL/
├── project.godot              # Godot 项目配置（含 AutoLoad: EventLogger, CallsignDB）
├── scenes/
│   ├── main.tscn              # 沙盒主场景（Main + BulletManager + MissileManager + Camera2D）
│   ├── main_menu.tscn         # 主菜单（入口场景）
│   ├── survivor_mode.tscn     # 生存模式
│   ├── survivor_map_select.tscn # 生存模式地图选择（先于机型选择）
│   ├── survivor_select.tscn   # 生存模式机型选择界面
│   ├── aircraft.tscn          # 飞机模板（通用）
│   ├── missile.tscn           # 导弹模板
│   ├── sam_unit.tscn          # 防空导弹车
│   ├── aa_gun_unit.tscn       # 高射炮
│   └── radar_station.tscn     # 雷达站
├── scripts/
│   ├── main.gd                # 沙盒主场景：输入/雷达锁定/编队生成（地形/相机委托共享模块）
│   ├── terrain_renderer.gd    # TerrainRenderer：地形/网格/云层绘制（沙盒+生存共享）
│   ├── camera_controller.gd   # CameraController：缩放/平移/hover/坐标转换（沙盒+生存共享）
│   ├── main_menu.gd           # 主菜单
│   ├── aircraft.gd            # Aircraft 实体（~1254 行，LOD 路由 + 损伤 + 状态所有者；物理/武器/战斗/编队/热诱弹全部委托 aircraft/）
│   ├── aircraft_params.gd     # AircraftParams Resource
│   ├── ai_controller.gd       # AI 状态机（~1235 行，状态机路由 + 状态所有者 + BVR/BOSS + 简单 AI；战术/规避/目标选择/编队委托 ai/）
│   ├── combat_unit.gd         # 战斗单位基类（Aircraft/GroundUnit 共享接口）
│   ├── missile.gd             # 导弹实体（PN 制导）
│   ├── missile_manager.gd     # 导弹管理器（命中检测/在飞查询/近炸AOE）
│   ├── missile_params.gd      # MissileParams Resource
│   ├── bullet_manager.gd      # 机炮子弹管理（物理+命中）
│   ├── gun_params.gd          # GunParams Resource
│   ├── rocket_params.gd       # RocketParams Resource（无制导火箭弹）
│   ├── combat_params.gd       # CombatParams Resource（AI 行为风格）
│   ├── flare_params.gd        # FlareParams Resource（含 fail_chance 失误概率 + head_on_fail_reduction 对头减免）
│   ├── playable_aircraft.gd   # PlayableAircraft Resource（主角档案，UI+生存调味）
│   ├── squad.gd               # 编队数据结构 + 6 种阵型计算
│   ├── ground_unit.gd         # 地面单位基类
│   ├── sam_unit.gd            # SAM（防空导弹车，360° 雷达）
│   ├── aa_gun_unit.gd         # AAA（高射炮，独立炮塔）
│   ├── radar_station.gd      # 雷达站（数据链共享）
│   ├── ground_convoy.gd       # 地面车队
│   ├── event_logger.gd        # 全局事件日志（AutoLoad）
│   ├── callsign_db.gd         # 呼号分配器（AutoLoad）
│   ├── trail_ribbon.gd        # 烟迹/尾迹渲染
│   ├── bullet_manager.gd      # 子弹管理器
│   ├── hud.gd                 # 沙盒 HUD
│   ├── debug_panel.gd         # 调试面板（策略显示/生成按钮）
│   ├── game_constants.gd      # 全局物理/队伍颜色常量（GameConstants）
│   ├── theme_colors.gd        # 生存 UI 统一调色板（ThemeColors）
│   ├── terrain_renderer.gd    # 地形/网格/云层绘制（沙盒+生存共享）
│   ├── camera_controller.gd   # 缩放/平移/hover/坐标转换（沙盒+生存共享）
│   ├── aircraft_renderer.gd   # 飞机绘制系统（从 aircraft.gd 提取的 18 个 _draw_*）
│   ├── aircraft_destruction.gd # 坠毁动画（fighter/bomber/heli 三种风格）
│   ├── pilot_personality.gd   # 飞行员心理（压力/SA/判断误差）
│   ├── aircraft/              # Aircraft 子系统（RefCounted 静态模块，首参 ac: Aircraft）
│   │   ├── aircraft_flares.gd          # 热诱弹：释放/jam 概率/粒子/多波 reload（274 行）
│   │   ├── aircraft_weapons.gd         # 武器：gun/ciws/rocket/missile/multi_lock_salvo/weapon_mode（694 行）
│   │   ├── aircraft_physics.gd         # 物理：bank/heading/speed/altitude/stall/fuel/g/energy_mgmt（873 行）
│   │   ├── aircraft_combat_tracking.gd # 战斗追踪：_update_combat + _choose_dogfight_pursuit_pos + 对地攻击（654 行）
│   │   └── aircraft_formation.gd       # LOD 1 编队托管三段式 FAR/MID/CLOSE + 常见 bug 回溯地图（246 行）
│   ├── ai/                    # AI 子系统（RefCounted 静态模块，首参 ai: AIController）
│   │   ├── bfm_tactics.gd              # BFM 战术：8 个执行器 + choose_tactic + assess_situation（574 行）
│   │   ├── target_selection.gd         # 目标选择：try_engage + reevaluate_target + disengage（203 行）
│   │   ├── missile_evasion.gd          # 导弹规避：process_evade + 来袭检测 + Herbst 触发（165 行）
│   │   ├── squad_coordination.gd       # 编队协同：squad_follow + 后半球扫描 + cover + salvo 广播（287 行）
│   │   └── tactical/                   # P4 重构：玩家 + 僚机 + 9 种敌机的统一决策路径
│   │       ├── situation.gd            # 态势快照（输入）：几何/锁定/小队/AI 性格
│   │       ├── tactical_plan.gd        # 决策输出（值类型）：13 种 intent + 速度/武器/AB
│   │       ├── bfm_intent.gd           # 13 个 intent 纯函数：CRUISE/WAYPOINT/PASSIVE_FIRE/TAIL_CHASE/CLOSE_TAIL/LEAD_TURN/LEAD_PURSUIT/LAG_PURSUIT/MERGE_PASS/EXTEND_RECOVER/BOOM_ZOOM_OUT/WIDE_TURN/GROUND_STRAFE/EVADE_MISSILE
│   │       └── tactical_planner.gd     # 顶层决策树（9 优先级）+ hysteresis 防抖 + 武器锁定后置覆盖
│   ├── equipment/             # 装备模块化系统（重构中，逐 commit 迁移老武器字段）
│   │   ├── equipment_params.gd         # 装备基类（武器/反制/规避统一抽象，equipment_kind 标识）
│   │   ├── engagement_preference.gd    # 装备投票值类型（preferred_range/intent/priority）
│   │   ├── evasion_module.gd           # 规避模块基类（extends EquipmentParams + should_trigger）
│   │   ├── gun_equipment.gd            # 机炮装备包装器（commit 2/13；持 GunParams + CLOSE_TAIL 投票）
│   │   ├── rocket_equipment.gd         # 火箭弹装备包装器（commit 3/13；持 RocketParams + TAIL_CHASE 投票）
│   │   ├── missile_equipment.gd        # 导弹装备包装器（commit 4/13；主/副双槽 is_secondary + LEAD_PURSUIT 投票）
│   │   ├── flare_equipment.gd          # 热诱弹装备包装器（commit 5/13；EvasionModule 子类，等 commit 7 接入投票）
│   │   ├── cobra_evasion.gd            # 眼镜蛇 EvasionModule 标记（commit 6/13；publish 时自动 add_child 子节点）
│   │   ├── herbst_evasion.gd           # 赫尔贝特轮 EvasionModule 标记（commit 6/13；自动挂 HerbstManeuver）
│   │   ├── railgun_equipment.gd        # 电磁炮（commit 8/13）：telegraph + hitscan + 闪电视觉 + 穿透
│   │   └── laser_equipment.gd          # 360° 激光（commit 9/13）：DoT + 过热 + 云削弱 + target_filter
│   └── survivor/
│       ├── survivor_mode.gd       # 生存模式主控制器（场景/操控/升级/HUD）
│       ├── survivor_spawner.gd    # 刷怪系统（Token/生成/击杀/清理/猎手）
│       ├── survivor_player.gd     # 经验/等级/升级应用
│       ├── survivor_data.gd       # 升级定义 + 波次参数 + 经验曲线（静态）
│       ├── survivor_hud.gd        # HUD（HP/经验/战术按钮）
│       ├── survivor_upgrade_ui.gd # 升级选择界面
│       ├── survivor_map_select.gd # 地图选择（生存流程第一步）
│       ├── survivor_select.gd     # 机型选择（PlayableAircraft 卡片，4 槽）
│       ├── survivor_playable_setup.gd # PlayableAircraft → Aircraft 实例的应用器
│       ├── survivor_debug_skills.gd # 调试技能面板
│       ├── commander_aura.gd      # Sentinel 指挥 UAV 光环 buff + 招募
│       ├── commander_overlay.gd   # 指挥机可视化覆盖层
│       ├── map_geography.gd       # 地图 API (is_on_land 等)
│       ├── map_geography_data.gd  # JSON 加载器（OSM 烘焙数据）
│       ├── map_feature_renderer.gd # 主地图 (Sprite 底图 + shader)
│       ├── map_manual_background.gd # @tool 编辑器参考预览
│       └── tactical_map.gd        # 战术缩略图 (CRT 风)
│   ├── events/                  # 事件系统：剧本驱动单位 AI（BOSS / 未来剧情演出）
│   │   ├── ai_directive.gd          # AI 指令（FLY_TO_POINT/PATROL_RING/FOLLOW_PATH/HOLD/ENGAGE/PASSIVE）
│   │   ├── game_event.gd            # 事件基类（lifecycle + managed_units + set_directive）
│   │   ├── event_director.gd        # 调度器（survivor_mode 子节点；每帧 tick 所有 active 事件）
│   │   └── boss_encounter_event.gd  # BOSS 战剧本：PRE_STAGE → ENGAGED → VICTORY
│   └── audio/
│       ├── audio_manager.gd       # AutoLoad：BGM + SFX + UI + 播放列表 + 玩家引擎音 + 菜单模糊
│       └── audio_settings_panel.gd # 主菜单"音频设置"叠加面板（4 条 Bus 滑条 + 静音 + 保存）
├── audio/
│   ├── music/                 # BGM .ogg（Vorbis Q5, 44.1kHz stereo）
│   ├── sfx/                   # 世界音效 .wav（PCM mono, 44.1kHz, ≤ 2s）
│   ├── ui/                    # 界面音效 .wav
│   └── radio/                 # 无线电语音（Step 2 预留）
├── scripts/tools/             # 开发工具（不进打包）
│   ├── bake_tokyo_bay.py       # OSM GeoJSON → tokyo_bay.json
│   └── download_basemap.py     # CartoDB 瓦片 → 底图 PNG
├── resources/                 # .tres 参数资源（飞机/武器/导弹/战斗风格）
├── resources/maps/            # 地图数据（JSON / PNG）
├── resources/shaders/         # 地图 shader（basemap_tacview.gdshader）
├── docs/                      # 设计文档 + 代码索引 + 更新日志
└── export_presets.cfg         # Godot 导出配置
```
