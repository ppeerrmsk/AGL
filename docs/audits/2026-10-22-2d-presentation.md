# 2026-10-22 二维呈现审计与修复证据

## 全元素补查（2026-10-24，用户要求全部检查）

### 本轮新增修复

- 电磁炮充能跟踪线的方向使用显示目标、长度却使用物理距离；现改为同一显示端点。收拢至零角度时只画一条边，不再提交退化三角形和重复边。冻结命中解、发射射程与伤害保持原值。
- DEADAIR 暴露环抵消物理旋转、缓存期间又受镜头变化影响。现在由统一战术画布保持屏幕轴和尺寸，覆盖飞机、无人机以及 Ground/Naval 共用的 CombatUnit 路径；暴露归零、隐藏、死亡后撤销代理。
- 副武器锁定框与战斗连线在传感器接触刚丢失时仍显示缓存中的精确目标。现在在绘制端立即撤销；副锁定还排除已毁目标，保留原弹空/装填/冷却门。
- 命令轮盘的自动交战范围圈中心改用玩家显示位置，范围绘制统一变换到控件局部画布。
- 旧 UI Dev 夹具向 AfterburnerCharge 已删除的 `active` 属性赋值，引发退出码 86；改走正式 `activate`，五个通知/缩放/手动热诱弹画面场景均复跑。
- BOSS Debug 陆航母夹具使用固定 420 个渲染帧等待起飞，在高帧率时提前断言；改为等待真实起飞状态、并设 12 秒墙钟上限，仍要求正式起飞后停机坪剩余两机。

### 逐项画面矩阵

新增 `bench/run.cmd player_elements_visual 1 180 Shadow Visual`。98 个状态共 1824 个真实渲染帧，4 档缩放与旋转；物理步移动、动态端点像素、暴露环亮段方向、正式标签覆盖层轴向、正/负可见性断言全部通过。机器清单为 `tmp/map_visual_qa/player_elements/coverage.json`，每项同名 PNG；拼图 `tmp/2d-elements-sheet-*.png` 用于人工逐图核对。

| 类别 | 已覆盖状态 |
|---|---|
| 玩家附着 | 机体、滚转、俯仰、坠毁、云下阴影/云内、枪口、加力及俯仰加力、装填 FLR/GUN/MSL、战术弹字/过期、热诱弹 |
| 范围与锁定 | 雷达、副弹锥、悬停/急刹/敌威胁机炮锥、炮艇全向圈、干扰/减速/恐惧/ESM 范围、主锁进度/完成、TGT/匿名 TGT、副锁与弹空/装填/隐形/丢失接触/目标死亡 |
| 战斗线 | 普通/突击/接触丢失、航点预测/切控撤销、编队槽位/航向、电磁炮跟踪/机头/冻结/等待/扇面/实弹、激光/黑客/过热 |
| 独立战斗层 | Mother Goose 指定猎杀预警/激活/清除、干扰场三相/清除、Black Star AOE/冲刺刹车/爆点/清除、指挥机数据链、ORION 锁定/FANG 预警与激活/电磁炮/拦截/清除 |
| 弹丸与尾迹 | 炸弹、空爆弹、炸弹冲击圈/Flak、实弹/火箭/纯视觉弹、命中火星、漂浮雷、运动尾迹/隐藏清除 |
| 标签与 HUD | 完整/精简/最小/无人机/坠毁标签；轮盘目标/自动范围/蓄力、战区箭头/清除；雷达/隐形提示/切控/死亡、屏外威胁/锁定/入屏清除、玩家离屏 |
| 跨兵种环 | CombatUnit 暴露环的缩放/旋转与归零清除；生命周期专项追加无人机与地面真实伤害后撤销 |

最终逐项日志 `tmp/2d-final-player_elements_visual.log`：98/0、wrapper 0。`tmp/2d-final-tactical_canvas.log`：48 运动帧、46 插值帧、最大端点误差 0.00027px，暴露环及伤害/free 到末尾，wrapper 0。

开发夹具的失败记录保留：首轮漏算窗口 stretch 与固定 BOSS 快照出镜；第二轮 Callable.bind 传入未类型化空数组触发 86；随后修正类型、镜头和窗口坐标。没有放宽生产渲染门或跳过失败图元。逐项标签最终接入正式覆盖层，不能把缺少覆盖层的缓存绘制夹具当成正式标签旋转效果。

### 跨场景检查与性能结果

`tmp/2d-suite-*.log` 与 `tmp/2d-final-*.log` 保存本轮现有 Visual 场景回归。覆盖刹车提示、玩家/僚机仪表、跨兵种状态栏、支持圈、火箭、热诱弹、命中反馈、隐形、三语菜单、选图/选机/档案/商店/音频/HUD 设置/暂停/失败/胜利九页、升级卡、进化、BOSS 到场/选择、机型轮廓/滚转、Snowblind 和 UI Dev 五种状态。真实截图已查看；静态截图与连续运动断言分别记录，不能用截图宣称全程无抖动。

本轮 25 个功能/Visual 入口最终全部通过（包含新逐项矩阵、战术画布及 ORION 生命周期）。第一轮 `boss_debug_select_visual` 的 FINAL WAR 120 帧中 44 帧低于 60、最慢 30.185ms，wrapper 1；当时存在另一个任务的离线压缩负载，保留失败。暂停压缩后 FINAL WAR 达标，但暴露固定帧等待起飞的夹具错误。修复等待语义后的最终整项 `tmp/2d-boss-debug-final.log` wrapper 0：FINAL WAR 120 帧最慢 11.607ms、低于60为0；列车120帧最慢5.624ms、低于60为0；陆航母实际起飞、停机坪剩余2。`evolution_decision_visual` 和部分 UI 夹具有退出资源残留警告，不声明退出无泄漏。

代表性压力测试在离线压缩暂停、进程 CPU 增量为0的窗口内进行，保留正式机体、弹丸、画质和负载。两项均 wrapper 0、8/8 镜头巡检，但**严格60FPS门均未通过**：

| 场景 | 采样帧 | 平均FPS | 1% low | 最差FPS | 低于60帧数 | 证据 |
|---|---:|---:|---:|---:|---:|---|
| C1 36/36单位 | 5234 | 193.85 | 76.77 | 54.14 | 1 | `bench/results/battlefield_atmosphere_stress_36_20261024_023339.txt` |
| C2 48/48单位、24km | 5352 | 198.23 | 78.99 | 51.86 | 12 | `bench/results/battlefield_atmosphere_stress_48_24km_20261024_023419.txt` |

两项均1600×900、render_scale=1、正式机体体积、2×MSAA，记录 `volume satellite=disabled`，不能当作启用正式东京地图的性能结论，也不能用平均FPS替代慢帧门。

默认全量第一轮 `tmp/2d-all-complete-20261024.log`：105组同步测试失败1，地图 Operational 预热1632ms超过1600ms，wrapper 1；同步门失败后未进入异步生命周期。无 SCRIPT ERROR / RUNTIME ERROR；退出15 ObjectDB / 7 resources / PagedAllocator残留警告。此轮有恢复中的离线压缩，不删除该失败记录。

暂停离线压缩、确认进程 CPU 增量为0后，`tmp/2d-map-prewarm-quiet.log` focused 预热1207ms、wrapper 0。随后默认 `all 1 300 Shadow Headless` 最终日志 `tmp/2d-all-final-quiet-20261024.log`：**105组同步测试失败0，LifecycleGauntlet 90/0，wrapper 0，无 SCRIPT ERROR / RUNTIME ERROR**；地图预热1163ms。战术画布48运动帧全部处于插值相位、最大端点误差0.00027px，伤害/free/退出走到末尾、失败0。退出仍14 ObjectDB / 7 resources及PagedAllocator警告，不声明无泄漏。

静态检查：`verify_player_ref_holders.py` 漏登记0，`verify_doc_anchors.py`、`verify_docs.ps1`、`git diff --check`通过。最终结论是绘制入口静态审计、上述98状态与25场景及全量功能回归已完成；严格60FPS仍未通过，所有玩法组合与长局人工动态验收不在本次样本的证明范围。

## 跨场景补充验收（2026-10-24）

### 新修复与检查

- ORION 的 FANG 持续光剑、双炮预警仍使用物理起点，两个物理步之间与插值机体错位。本轮改为显示态位置和航向；未锁定的预警方向跟踪显示目标，锁定后的方向不变。伤害端点、已发射弹道和拦截爆点保持原快照。
- `orion_presentation_case` 在真实物理步中移动、旋转三机与目标，检查锁定框、光剑双端点和两个炮口；同时检查固定锁定方向、伤害端点与已发射快照没有被表现更新改写。Headless、GL Visual、默认 all 均为32/32插值帧，最大误差0px、失败0；正式伤害、拦截、阵营变更和死亡清理断言保持通过。
- 隐形 Visual 原夹具没有装配世界覆盖层，且目标在镜头外。现在接入正式 WorldUnitStatusOverlay、登记真实单位并要求目标在画面内，验可见→渐隐立即撤精确标记→隐藏任务目标保留匿名TGT→重新显形恢复。四张截图已查看，淡出中点alpha约0.500，幂等Tween、普通隐形目标无代理和重新显形均通过。
- 中/英/日菜单重建与玩家/僚机HUD的真实GL截图入口均运行。初次日文截图观察到机壳缺失，后续重跑未复现，未据此修改菜单生产代码；新增三语各8帧、每帧四点的实际机壳像素门，24帧均通过。此证据不等于所有菜单交互已验收。像素探针开发时误用Image API触发退出码86，已修正并复跑，失败日志保留。

### 当前回归结果与边界

- `tmp/2d-all-20261024.log`：105组同步测试失败0，LifecycleGauntlet 90/0，wrapper 0，无SCRIPT ERROR / RUNTIME ERROR。原预测线用例48帧中47帧处于插值相位，最大端点误差0.00025px。退出仍有14 ObjectDB / 7 resources及PagedAllocator警告，不声明无泄漏。
- `tmp/2d-orion-focused-20261024.log`、`tmp/2d-orion-motion-visual-20261024.log`：ORION聚焦Headless/GL均wrapper 0。
- `tmp/2d-sensor-final-20261024.log`、`tmp/2d-menu-pixels-final-20261024.log`、`tmp/2d-player_hud_visual-20261024.log`：上述GL专项wrapper 0。截图位于`bench/results/`的`sensor_stealth_*.png`、`main_menu_visual_*.png`、`player_hud_*.png`。
- 正式`orion_visual`样本`bench/results/orion_visual_20261024_015457.txt`：截图可见双FANG光剑与机体连接；但提前胜利，`orion_peak_missiles=0`，wrapper 1。未覆盖完整齐射，不能算S2完整武器负载通过。墙钟记录4帧低于60FPS、最大82.118ms，不作性能通过证据。
- C1 `bench/results/battlefield_atmosphere_stress_36_20261024_015832.txt`：Godot4.7.2、GL、1600×900、正式机体/原弹丸、36/36演员、8/8镜头巡检；5292采样帧，平均196.00FPS、1% low 80.28、最差58.20，低于60共1帧。wrapper 0只代表运行完成，**严格60FPS门未通过**。该入口记录`volume satellite=disabled`，不得与地图任务启用正式地图的样本混成同条件对照，也不据单次样本宣称性能提升。

生产改动的全量回归已通过；全部BOSS、切控、菜单组合与长局人工动态验收仍未完成。保留早期结果如下，不能用早期三次C1全帧60替代本次或正式地图的当前结果。

## 最新集成验收（2026-10-23）

保留本轮全部二维修改的最终集成回归已通过：105 组同步测试零失败，LifecycleGauntlet 90/0，wrapper 退出码 0，无 SCRIPT ERROR / RUNTIME ERROR。已直接核对共享日志 `tmp/map-flicker-20261022/final-all.log`。此前东京地图测试的陈旧覆盖夹具已由地图任务修正；下文失败轮次是保留的历史证据，不再代表最新回归状态。

退出仍报告 14 ObjectDB、7 resources 和 PagedAllocator 警告，因此不声明无泄漏。全部菜单、BOSS 与玩法组合的人工动态验收仍未完成；本轮全量通过不能替代该边界。


## 覆盖范围

静态枚举 scripts 内所有实际调用 Canvas 绘制 API 的生产脚本（排除 tests/experiments/diagnostics/tools），包括 _draw、信号绘制及静态委托。共 81 个文件。静态清单表示入口已纳入检查范围，不等于每个场景已完成人工动态验收。

## 根因与修复

- 插值机体与物理坐标连线混用；绘制命令缓存后被机体继续旋转，世界远端漂移。动态标记独立 Canvas，渲染帧统一取显示态，两端同相位。
- 预测首点是开工时机位；新显示按已飞过近端裁剪，首点锚定同帧机位。
- 预测到达截断造成点数变化，旧逻辑整线 snap。固定弧长重采样及指数平滑消除长度变化时的重置；末端只取非退化切线。
- 屏外箭头手算相机矩形，遗漏 rotation/offset/stretch。改用真实画布投影。
- _draw 中推进平滑使时序依赖是否发生 redraw。显示准备与绘制分离。

## 按域裁决

| 范围 | 本轮处理 | 仍需区分的边界 |
|---|---|---|
| 预测线/目标线/锁定/任务框/装填提示/战术弹字/来袭导弹 | 独立活跃画布，同帧双端点 | 不改变锁定判定或自动射击 |
| 激光/电磁炮/热诱弹/编队调试 | 显示变换与冻结世界坐标分离 | 已发射弹道仍保持实际命中位置 |
| 指挥数据链/母鹅场和指定线 | 读插值显示位置 | 源死亡后清理仍走原终态 |
| 标签/雷达/悬停/命令目标/屏外箭头 | 相机完成后定位、实际画布换算 | 普通内容读数频率与位置更新分离 |
| 支援圆/机体局部轮廓/雷达锥 | 保留局部几何缓存，随插值变换移动 | 不把静态几何升为逐帧重绘 |
| 子弹/爆炸/炮弹/尾迹批绘 | 核查世界几何与生命周期所有权；保持原批量提交 | 子弹批绘仍60Hz、尾迹采样20Hz；没有宣称所有粒子已逐渲染帧插值 |
| 固定战区/地表/建筑/地图网格 | 保留脏驱动重绘与原LOD | 东京3D切面露底由并行地图任务处理 |
| 菜单/图标/仪表/网格/预览/UGC | 核查屏幕局部坐标与更新入口 | 不把设计脉冲/扫描线等同于故障频闪；未逐页操作所有菜单 |
| ORION/BlackStar锁存攻击预告 | ORION 跟随锁定框改读显示态；冻结弹道/命中几何保留物理快照 | 跨阶段人工 Visual 未完成 |

## 额外边界检查

- `LockWarning.draw` 为未调用的旧绘制入口（跨文件引用搜索无调用）；当前来袭警告由 Missile 活跃画布承担，不能仅凭旧函数存在把它当作正式运行中的故障。
- Tab 战术地图按既有 10Hz 更新符号、静态底图独立缓存；显示的是全图态势，不与主画面机体叠放，本轮保留其采样语义。菜单 CRT 扫描与锁定告警的设计闪烁保留。
- 世界距离读数、射程判断、冻结电磁炮命中点继续读物理真值；只迁移跟随标记的位置来源，避免让显示平滑改变射击判定。
- 生产绘制清单外，额外检查了三维合成屏幕投影、动态标记委托、CanvasLayer 状态栏、纹理机体轮廓和相机处理顺序。清单中的每个入口不等同于每个玩法组合已进行动态验收。

## 全部生产绘制入口

| 文件 | 首个绘制调用 | 静态调用数 |
|---|---:|---:|
| `scripts/aa_gun_unit.gd` | 207 | 12 |
| `scripts/airburst_aa_unit.gd` | 170 | 2 |
| `scripts/aircraft_renderer.gd` | 392 | 144 |
| `scripts/ground_unit.gd` | 365 | 8 |
| `scripts/lock_warning.gd` | 101 | 4 |
| `scripts/meta/ace_emblem_icon.gd` | 38 | 54 |
| `scripts/meta/archive_ui.gd` | 213 | 6 |
| `scripts/meta/merit_coin_icon.gd` | 29 | 6 |
| `scripts/missile.gd` | 813 | 7 |
| `scripts/naval/carrier_ship.gd` | 124 | 6 |
| `scripts/naval/cruiser_ship.gd` | 43 | 10 |
| `scripts/naval/destroyer_ship.gd` | 40 | 7 |
| `scripts/naval/frigate_ship.gd` | 41 | 5 |
| `scripts/naval/naval_destruction.gd` | 118 | 2 |
| `scripts/naval/naval_unit.gd` | 775 | 17 |
| `scripts/naval/submarine_ship.gd` | 52 | 7 |
| `scripts/radar_station.gd` | 125 | 5 |
| `scripts/rendering/bullet_presenter.gd` | 28 | 19 |
| `scripts/rendering/canvas_triangle_packet.gd` | 0 | 0 |
| `scripts/rendering/explosion_presenter.gd` | 23 | 3 |
| `scripts/rts/command_wheel.gd` | 404 | 27 |
| `scripts/rts/squad_command_controller.gd` | 381 | 3 |
| `scripts/rts/war_command_panel.gd` | 176 | 3 |
| `scripts/rts/war_sector_overlay.gd` | 21 | 3 |
| `scripts/sam_unit.gd` | 182 | 4 |
| `scripts/strategic_target.gd` | 62 | 17 |
| `scripts/survivor/aircraft_hologram_preview.gd` | 31 | 11 |
| `scripts/survivor/aoe_pulse_vfx.gd` | 83 | 4 |
| `scripts/survivor/armored_train_segment.gd` | 169 | 42 |
| `scripts/survivor/armored_train_unit.gd` | 743 | 11 |
| `scripts/survivor/atmosphere_artillery_unit.gd` | 76 | 7 |
| `scripts/survivor/axis_bars_panel.gd` | 57 | 11 |
| `scripts/survivor/battlefield_atmosphere_experiment.gd` | 1183 | 4 |
| `scripts/survivor/boss_debug_select.gd` | 119 | 10 |
| `scripts/survivor/bottom_experience_panel.gd` | 113 | 6 |
| `scripts/survivor/brake_steering_overlay.gd` | 134 | 15 |
| `scripts/survivor/building_renderer.gd` | 534 | 1 |
| `scripts/survivor/commander_overlay.gd` | 44 | 3 |
| `scripts/survivor/damage_vignette.gd` | 133 | 1 |
| `scripts/survivor/dock_point.gd` | 113 | 8 |
| `scripts/survivor/evolution_tree_view.gd` | 248 | 18 |
| `scripts/survivor/hyper_a_threat_overlay.gd` | 45 | 18 |
| `scripts/survivor/land_carrier_unit.gd` | 216 | 25 |
| `scripts/survivor/map_boundary.gd` | 182 | 11 |
| `scripts/survivor/map_feature_renderer.gd` | 491 | 21 |
| `scripts/survivor/map_manual_background.gd` | 57 | 12 |
| `scripts/survivor/milestone_axis_counter.gd` | 68 | 3 |
| `scripts/survivor/mother_goose_designation_overlay.gd` | 60 | 3 |
| `scripts/survivor/mother_goose_jam_shield.gd` | 117 | 3 |
| `scripts/survivor/notification_terminal_bar.gd` | 52 | 2 |
| `scripts/survivor/orion_weapon_overlay.gd` | 24 | 8 |
| `scripts/survivor/player_instrument_panel.gd` | 711 | 19 |
| `scripts/survivor/support_range_overlay.gd` | 32 | 2 |
| `scripts/survivor/survivor_debug_spawn.gd` | 767 | 11 |
| `scripts/survivor/survivor_hud.gd` | 2296 | 26 |
| `scripts/survivor/survivor_tutorial_frame.gd` | 37 | 10 |
| `scripts/survivor/tactical_map.gd` | 354 | 63 |
| `scripts/survivor/tier3_siege_ciws.gd` | 120 | 2 |
| `scripts/survivor/tier3_siege_flak.gd` | 40 | 3 |
| `scripts/survivor/tier3_siege_sam.gd` | 40 | 3 |
| `scripts/survivor/tier3_siege_tank.gd` | 184 | 12 |
| `scripts/survivor/tier3_super_cannon_part.gd` | 269 | 27 |
| `scripts/survivor/upgrade_media_surface.gd` | 49 | 33 |
| `scripts/survivor/warzone_time_panel.gd` | 63 | 2 |
| `scripts/survivor/wingman_instrument_panel.gd` | 168 | 5 |
| `scripts/survivor/xp_gain_vfx.gd` | 103 | 2 |
| `scripts/survivor/zone_arrow.gd` | 72 | 3 |
| `scripts/survivor/zone_atmosphere_combat.gd` | 1016 | 5 |
| `scripts/terrain_renderer.gd` | 150 | 4 |
| `scripts/ugc/map_editor_canvas.gd` | 39 | 9 |
| `scripts/ugc/map_editor_scene.gd` | 345 | 4 |
| `scripts/ui/fear_readout_mask.gd` | 6 | 5 |
| `scripts/ui/main_menu_crt_shell.gd` | 30 | 22 |
| `scripts/ui/main_menu_scope_display.gd` | 34 | 6 |
| `scripts/ui/terminal_grid_overlay.gd` | 68 | 2 |
| `scripts/ui/terminal_map_preview.gd` | 22 | 16 |
| `scripts/ui/terminal_text.gd` | 127 | 1 |
| `scripts/ui/ui_dev_outline_overlay.gd` | 53 | 3 |
| `scripts/ui/world_unit_status_overlay.gd` | 143 | 4 |
| `scripts/weather_system.gd` | 456 | 5 |
| `scripts/zones/zone.gd` | 198 | 4 |

## 资料

- [Godot 2D自定义绘制](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)：缓存命令与Canvas局部坐标。
- [Godot物理插值](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html)：二维插值在渲染服务器实现；不能把读取global_position当成显示态。

## 本轮验证

- `predicted_path`：22 项通过。保留原 360 步积分等价性，增加过期首点、长度变化、重采样、退化末端与平滑状态独立性。
- `tactical_canvas 1 180 Shadow Visual`：4 档 zoom（0.2/0.55/1/3）与旋转通过；48 帧真实物理步移动，其中 45 帧出现显示态/物理态分离，源/目标端点最大误差 0.00024 px；真实伤害后跨帧清理、free 和退出通过，wrapper 0。
- 同一场景在 Headless 也通过；截图位于 `tmp/map_visual_qa/tactical_canvas/`。截帧只证明静态画面，运动断言证明上述采样窗口的端点一致，不代表所有场景人工验收完成。
- 第一轮 `all`：105 组中 1 组失败（career_archive 缺两条 ORION 译文）。两个 key 已在 meta.csv，根因是生成资源过期；从当前源表运行 i18n_build，仅回写 meta 三语资源。没有新编译文或跳过断言。
- 隔离副本仍保留已不存在的 agl_native 扩展登记，确认源码无该扩展后只清理副本的生成登记；源码/编辑器缓存未改。

- 第二轮 `all`：同步断言 105/0；二维动态用例 48/48 插值帧、最大端点误差 0.00025 px、真实伤害/free 通过；ORION lifecycle 0 失败。总 lifecycle 90/1，地图候选 `_commit_ready_target` 的缺失 parent 与空 get_ref 触发运行时错误门，wrapper 返回 1；该轮不得标记全量通过。

- 最终补充：装填提示、战术弹字和匿名 TGT 提示也迁入同一画布；保持隐形/坠毁提示原来的可见性例外。专项再次通过，48 帧中 45 插值帧、最大误差 0.00024 px；伤害后提示保留，计时结束清理，再 free，均到达末尾。

### 真实画面性能

Godot 4.7.2 Steam / RTX 3080 / 1600×900，正式三维机体、原弹丸、2× MSAA 配置保留。下表 C1 全部达到 36 名混合演员与 8/8 镜头巡检；统计跳过前三秒预热。

| 场景/轮次 | 平均 FPS | 1% low | 最差帧 FPS | frames_below_60 |
|---|---:|---:|---:|---:|
| 改动前单次 C1 | 118.67 | 60.08 | 58.64 | 24 |
| 改动后 C1-1 | 259.36 | 115.22 | 72.58 | 0 |
| 改动后 C1-2 | 251.97 | 116.95 | 90.38 | 0 |
| 改动后 C1-3 | 253.24 | 112.07 | 71.31 | 0 |

C1 三次平均 FPS 中位数 253.24，最差单帧约 14.02ms。本轮只确认三个样本达到 60 FPS 底线；改动前只有单次样本，且期间有并行工作与环境负载变化，**不能将平均 FPS 差值归因为本修复性能收益**。

结果：`bench/results/battlefield_atmosphere_stress_36_20261022_141113.txt`（前）；`..._145029.txt`、`..._145122.txt`、`..._145201.txt`（后三轮）。完整文件名共同前缀为 `battlefield_atmosphere_stress_36_20261022`。

C2 `battlefield_atmosphere_stress_48_24km_20261022_145255.txt`：48/48 演员、24km、8/8 巡检，平均 231.70 FPS、1% low 104.05、最差 87.28 FPS（约 11.46ms）、frames_below_60=0。C1 三轮和 C2 均 wrapper 0，未出现 SCRIPT ERROR 或退出泄漏报告。它们证明本轮代表性负载，不能替代所有地图/BOSS/菜单组合的人工长局验收。

### 稳定主线地图下的阶段性全量（2026-10-23）

`tmp/2d-all-stable.log`：地图运行时/测试文件已由地图任务确认恢复 main，双方暂停写入后执行默认 `all 1 300 Shadow Headless`。105 组同步断言通过；TacticalCanvas 与 ORION lifecycle 通过；总 LifecycleGauntlet 为 90/1，失败来自 Tokyo cells lifecycle（354/1，projection_error 0.017639px），已交给地图任务核对。**全量仍未通过，不能以二维 focused 成功代替。**

该轮还暴露其他过期翻译产物：FULL WAR 的 WAR_* key 已在 interface.csv，但旧 translation 缺失，格式化报错。随后逐字节确认五张 CSV 与本轮 i18n_build 输入一致，补同步 interface/gameplay/skills 三语资源（meta 此前已同步，radio 一致），没有修改源文案。该轮退出仍报告 14 ObjectDB / 7 resources，不能声明全量退出无泄漏。

静态收尾：verify_player_ref_holders（漏登记0）、verify_doc_anchors（254份文档、1695锚点）、verify_docs、git diff --check 通过。地图任务后续独立修改可能使它负责的锚点再次移动，这些数值仅代表本轮检查时刻。

翻译同步后 `full_war 1 120 Shadow Headless` 专项：32/0、峰值22单位/10导弹、wrapper 0，无格式化 ERROR / SCRIPT ERROR / 退出泄漏报告（`tmp/2d-full-war-final.log`）。最终全量未再次冒充通过：地图任务已将上述 Tokyo cells 失败缩小到 `commit_ready_checks()`，继续独立调查；二维任务不改地图门限或跳过该失败。


## 剩余掉帧与退出回收（2026-10-24）

### 根因与实现

- LANCER：中队持有战术、战术再强持有中队，形成 RefCounted 环；独立 `lancer_squad` 复现全量的14对象/7脚本资源残留。反向改为 WeakRef，宿主释放后迟到 enter/update/exit 安全返回。扩查并同样修复 WRAITH、POLTERGEIST 与主题控制器；战术频率、几何、战斗数值不变。
- 音频：进化 UI 重复测试的第三轮复现4个播放/OGG对象、2个资源残留（`tmp/2d-evolution-exit-repeat-3.log`），与中队问题独立。AudioManager 现在统一处理窗口关闭和程序退出，停止/解绑全树音源、禁止晚到播放和预载、取消 Tween，跨真实帧等待播放 WeakRef 归还和已发出的加载领取，再退出。等待上限2秒，超时失败，后到成功退出请求不能覆盖已有失败码。没有把静音等同于释放，也没有关闭日志。
- 音频诊断参考 [Godot 官方问题 #76745](https://github.com/godotengine/godot/issues/76745)：stop 后服务器异步保留播放引用。本项目结论以本机复现及 WeakRef 门为准。
- 慢帧记录器：原先捕获尖峰会深拷贝前120帧的全部字典；扩展诊断出现 `diagnostic.perf_begin_render_frame=2796us`。改为共享不可变帧/嵌套字典、只复制上下文索引，下一帧另建容器。完整桶、事件、负载、窗口及采样频率保留；65项 trace 断言通过，包括历史覆盖、重启和只读隔离。不能据此宣称实际帧率已经达标。

### 回归证据

- LANCER 修复后52/0，无退出残留：`tmp/2d-lancer-fixed-verbose.log`；POLTERGEIST 行为9/0：`tmp/2d-poltergeist-ownership-regression.log`。
- 三类真实中队死亡反例修复前均出现 owner/controller 保活；修复后 terminal/owner_released/detached/controller_released 全为 true：`tmp/2d-squad-ownership-baseline.log`、`tmp/2d-squad-ownership-fixed.log`。
- 中队修复后默认全量105项失败0、LifecycleGauntlet 93/0、wrapper0，无 ObjectDB/resources/PagedAllocator 残留：`tmp/2d-cleanup-all-fixed-20261024.log`。随后加入音频退出门，必须另跑最终全量。
- `audio_shutdown` 正式播放、交叉淡化、2D音源、预载、跨帧归还、晚到请求、幂等与窗口关闭通过：`tmp/2d-audio-shutdown-focused.log`。`audio_shutdown_failure` 刻意先请求7再请求0/窗口关闭，Godot保持退出7：`tmp/2d-audio-shutdown-exitcode.log`，这是预期反例。
- 进化UI修复后三轮均 clean=true，playback_remaining=0，pending_loads=0，无退出警告：`tmp/2d-evolution-exit-fixed-1.log` 至 `-3.log`。实际等待4/5/12帧，不用固定帧数假定音频已经释放。
- 开发失败保留：首次全量新增 WeakRef 测试类型推断触发严格编译门，导致生命周期入口未执行而超时；显式类型修正后才通过，不能把该失败归咎于机器负载。

### 保持外部负载的性能样本

用户明确选择保留 Godot 编辑器和 Battle Brothers 进程，记录受干扰结果。此前读数为编辑器2秒内CPU增加约3.55秒，另一个游戏占用3D GPU；这些证明存在竞争，不能证明所有慢帧均由外部程序造成。没有关闭用户程序或提高测试优先级。

Godot 4.7.2 Steam / RTX3080，1600×900、正式机体体积、render_scale=1、2×MSAA、既有AI/物理/弹丸/爆炸/尾迹全部保留；C1 36/36、C2 48/48且24km，六轮均8/8镜头巡检、wrapper0、音频干净退出。`volume satellite=disabled`，不能代替正式东京地图性能结论。以下是稳态原始结果，不能用退出0或平均值判严格60通过，也不能跨外部负载条件声称收益：

| 场景 | 采样帧 | 平均FPS | 1% low | 最差FPS | 低于60帧 | 结果文件（bench/results/） |
|---|---:|---:|---:|---:|---:|---|
| C1 | 3055 | 113.15 | 60.09 | 54.60 | 26 | `battlefield_atmosphere_stress_36_20261024_055520.txt` |
| C1 | 2927 | 108.41 | 60.22 | 53.66 | 26 | `battlefield_atmosphere_stress_36_20261024_055643.txt` |
| C1 | 2750 | 101.85 | 54.66 | 23.01 | 64 | `battlefield_atmosphere_stress_36_20261024_055807.txt` |
| C2 | 2966 | 109.82 | 59.00 | 25.85 | 53 | `battlefield_atmosphere_stress_48_24km_20261024_055601.txt` |
| C2 | 2950 | 109.26 | 59.80 | 23.79 | 36 | `battlefield_atmosphere_stress_48_24km_20261024_055724.txt` |
| C2 | 2890 | 107.03 | 57.22 | 30.04 | 62 | `battlefield_atmosphere_stress_48_24km_20261024_055851.txt` |

本轮严格60门仍未通过。深拷贝放大已移除，但保留外部负载的六轮样本不足以分离剩余绘制/调度/外部GPU竞争成本；不继续以无证据的降级或削减战斗负载换分。性能问题仍待进一步归因。


### 最终全量与静态收尾

`bench/run.cmd all 1 300 Shadow Headless` 最终日志 `tmp/2d-exit-all-final-20261024.log`：105项同步测试失败0，LifecycleGauntlet 93/0，三类 SquadOwnership 全通过，AudioShutdownCase played/released/late_safe/repeated/ok 均 true；10帧后 playback_remaining=0、pending_loads=0、clean=true，wrapper0。无 SCRIPT ERROR、RUNTIME ERROR、ObjectDB/resources/PagedAllocator 残留。沙漠预载超时警告来自既有超时回退负例，断言正常通过。

`verify_player_ref_holders.py` 漏登记0；`verify_doc_anchors.py` 254份文档/1934锚点通过；`verify_docs.ps1` 与 `git diff --check` 通过。最终源码仅 AudioManager._finish_quit 保留直接 SceneTree.quit，避免临时 SceneTree 变量绕过统一清理。

结论：已修复并验证本次复现的中队循环引用与音频退出残留；保留所有画质和战斗负载。记录器的尖峰放大已移除，但当前严格60性能验收仍失败，不声明掉帧已全部修好，也不以这些短样本代替长局/所有地图组合验收。


## 剩余慢帧分段与云格缓存（2026-10-24）

- 阶段探针 `AGL_FRAME_PROBE` + 扩展桶：最初 C2 2951帧、47慢帧、最差21.64ms。天气重绘出现在约1.7–1.9ms的尖峰中；它反复对不随时间变化的云空间格点采样噪声。修复将固定32格列段的可见坐标/密度存为双精度值，最多512段逐项淘汰；风偏移仍实时计算，战斗查询仍走原任意位置密度函数。没有改变云数量、纹理、阈值、x→y混合顺序、0.12秒刷新间隔或战斗负载。
- `weather` focused：正负坐标冷/热命中、窗口边界和原绘制顺序逐值一致；配置/直接coverage/mask变更失效、长期容量门通过。首次开发运行因 PackedByteArray 没有 hash 方法被 wrapper 判86，改为精确副本比较后两轮通过，保留失败日志，不把失败归咎于外部负载。
- 严格对照：仅临时在bench中固定天气RNG输入2657，交替control/candidate三轮，其他源码冻结；脚本finally校验恢复SHA256 `977433224d21028a0a0f69ea214acb08db17e51b17c115c0207e9826e4a11882`。正式随机天气不变。复现/完整结果在 `tmp/remaining-cloud-cache/run_matched.py`、`matched-manifest.json`、`matched-summary.json`。

| 同输入C2 | 平均FPS | 1% low | 最差FPS | 慢帧 | 天气每次重绘ms（约） | 结果UTC后缀 |
|---|---:|---:|---:|---:|---:|---|
| control 1 |117.13|59.88|56.72|46|0.794|073042|
| candidate 1 |117.16|60.01|58.83|31|0.207|073122|
| control 2 |116.96|60.00|59.00|32|0.793|073202|
| candidate 2 |116.62|59.86|56.37|66|0.205|073241|
| control 3 |113.07|59.66|20.94|45|0.838|073321|
| candidate 3 |112.04|60.09|51.71|27|0.225|073401|

结果均为 `bench/results/battlefield_atmosphere_stress_48_24km_20261024_<后缀>.txt`；Godot4.7.2/RTX3080、1600×900、原生机体合成、2×MSAA、48/48、24km、8/8巡检。六轮wrapper0，音频clean，无运行时错误/退出残留。编辑器/F5/Battle Brothers依用户要求继续运行；`satellite=disabled`，不能冒充东京地图验收。天气每次重绘中位约0.794→0.207ms（减少74%）；慢帧中位45→31，但第二轮candidate为66，最差FPS中位56.72→56.37，不能声称所有慢帧已修复。诊断轮不替代最终无探针C1/C2。

另有脚本较轻、render段约10ms的帧。Godot的frame_post_draw在rasterizer.end_frame之后发出，Windows GL交换缓冲走SwapBuffers，因此阶段墙钟包含呈现等待；异步GPU读数不作为同帧因果证据。参考：[Godot渲染服务实现](https://github.com/godotengine/godot/blob/master/servers/rendering/rendering_server_default.cpp)、[Windows GL交换缓冲](https://github.com/godotengine/godot/blob/master/platform/windows/gl_manager_windows_native.cpp)。WPR CPU/GPU启动被Windows权限策略拒绝（0xc5585011），随后确认未在记录；`wpr-start.txt`保留原错误。尚未取得系统级线程抢占/驱动等待归因，不将余下慢帧一概推给外部程序。

最终无探针性能与all将与并行状态栏/地图任务在统一冻结后验证，当前不宣称严格60或整项任务完成。

### 墙钟纠偏

上述表格全部为引擎delta口径，不能单独衡量真实停顿。独立FrameProbe在control3的bench_t=18.4167记录285.953ms（post帧间间隙273.082ms），另在4.7333记录218.010ms；均处于稳态，排除了退出写盘。引擎最差仅约47.8ms，漏计完整长停顿。相同3–30秒窗口的墙钟慢帧control为60/44/51、candidate为62/65/26；中位51→62，不能从引擎慢帧45→31声称整场改善。边界采样相差1–2帧；完整分布在`tmp/remaining-cloud-cache/matched-wall.json`。

标准Survivor性能场景现复用已有单调时钟，保留引擎摘要并输出`render_wall_clock`及`render_strict_60_passed`。严格门仍是每帧不超过1000/60ms，两套时钟均须通过；wrapper运行时成功与性能门独立。新增285.953ms长停顿和预热/暂停不拼接反例。尚未把帧间长停顿归因到特定线程或驱动，需系统调度证据。


## 2026-10-25 继续排查

新增两项实现：
- TrailRibbon 保留原20Hz、80点、顶点/颜色与LOD规则，仅在可见顶点数改变时重建三角形索引。满80点的每次稳定重绘省去474次重复索引赋值；没有据此预先宣称整帧性能收益。
- BenchRunner 仅在 AGL_FRAME_PROBE=1 时创建探针；过去只查环境变量存在，会把显式0误认为开启。0路径不再出现armed，1路径保留armed和CSV。

focused证据：trail-focused-fixed.log 14/0；probe-on-focused.log 67/0，退出clean。首次尾迹断言把最后一项误认为右端顶点，实际末三角的最后一项是左端、倒数第二项才是右端；纠正断言后通过，未放松拓扑要求。初次11/3日志保留，wrapper0不冒充断言通过。

系统采样：用户已授权管理员CPU/GPU采样。独立命名helper第一次遇到Start-Process退出码为空，未启动bench；管理员cleanup确认cancel0/status未记录。修复辅助程序后，第二次UAC等待150秒超时，未启动bench/未得到ETL，生产FrameProbe字节未改变。遗留consent提示需用户取消后才能进行正常桌面性能验收；不把提权桌面等待计作游戏掉帧，也不声称已归因到驱动。

当前时间条件与昨天不同：environment-before.json只记录到旧consent进程，未发现Godot编辑器/Battle Brothers。没有由本任务终止这些程序；不得拿之后数据与昨日额外F5/编辑器/启动器负载作直接收益比较。

本轮默认 all：`tmp/remaining-perf-20261025/all.log`，105项同步测试失败0，LifecycleGauntlet 93/0；AudioShutdown 15帧后 playback_remaining=0、pending_loads=0、clean=true，wrapper0，无运行时错误与退出资源残留。01:19其他进化UI聊天修改了共享源码，因此这里只证明启动时Shadow副本；不冒充整个当前树终态验收。尾迹、天气、对应测试、BenchRunner、AudioManager与测试副本逐字节对比记录在 `all-owned-source-check.json`。

01:30时的未完成项（后续结果见下一节）：管理员系统跟踪未取得ETL；无探针C1/C2各三轮与尾迹配对性能试验尚未运行。旧UAC提示仍存在，进化UI聊天仍在修改/验收，已请求协调授权；暂不宣称严格60通过。地图和状态栏聊天已确认冻结，未关闭用户程序。


## 2026-10-25 三方冻结后的系统采样与性能复验

用户明确授权协调地图、状态栏和机场进化三个聊天；三方均确认暂停源码写入和bench。11:49检查无旧Godot/UAC/WPR进程；保持所有用户应用，没有结束编辑器、游戏或浏览器。本次外部负载不同于昨日，不用跨时段FPS直接计算收益。

### 尾迹交替对照

`tmp/remaining-perf-20261025/trail-matched-manifest.json` / `trail-matched-summary.json`：固定同一天气输入2657，C1 control/candidate交替三组，36/36演员、8/8巡检、原1600×900、render_scale=1、2×MSAA，均wrapper0。使用屏幕外Visual+FrameProbe，属于诊断，不作为最终性能门。脚本finally确认尾迹和天气恢复正式字节。

- 墙钟慢帧：control 28/53/33，candidate 18/33/28；中位33→28。
- 墙钟最大间隔中位21.985→20.556ms。
- 末1秒快照中，每次尾迹重建成本中位72.43→67.27µs；只代表该快照，不能当全程函数平均或保证每轮均改善。
- 可保留无损索引复用，但这些数据仍不满足严格60。

### Windows系统证据

两次独立命名WPR会话均启动0、停止0、无丢失事件/缓冲；保存后已退出。首轮xperf在70.58秒、WPR自身进程28808的收尾事件报告一个Invalid Event；游戏已于49.45秒退出，该事件不在35.3秒的分析窗口，原始导出警告保留。临时FrameProbe/MapFrameClock插入均逐字节恢复，manifest记录SHA256。采样会有观察开销，不把采样轮作为最终FPS成绩。

1. `etw-114956/capture.etl`：CPU+GPU、屏幕外C2、FrameProbe。第1467帧37.215ms，其中render 27.598ms；主线程31084在ETL 35301797–35325416µs等待23.619ms，恢复时ready等待1µs。邻近DxgKrnl Present与调用栈落在Godot→gdi32full→opengl32→nvoglv64→Windows图形内核；`finding.json`与`main-worst.json`记录定位。仅证明本帧呈现等待，不证明昨日285.953ms的post停顿属于同一原因。
2. `cpu-120316/capture.etl`：只采CPU、可见窗口C2、不加载FrameProbe/扩展CPU桶，墙钟仅保留慢帧。50个慢帧，最大28.217ms；第146帧主线程55968在14791049–14808107µs等待17.058ms，ready等待1µs，内核栈为nvlddmkm/dxgkrnl；此前连续用户栈为gdi32full!SwapBuffers→opengl32!wglSwapBuffers→nvoglv64。其他两处21ms级帧也有约8.2ms的同链等待。导出在`slow-window.csv`、`main-slow.json`与`wait-intervals.json`。

通过本机DLL导出地址核对：gdi32full!SwapBuffers=0x7ffae9d7e580，采样栈地址0x7ffae9d7e5d7（+0x57）；opengl32!wglSwapBuffers=0x7ffa2b787f80，采样地址0x7ffa2b78817e（+0x1fe）。这定位到交换缓冲调用，不把“驱动链内等待”直接等同于“驱动bug”或外部程序抢占。GPU排队、桌面合成和驱动同步策略的占比还未完全分离；没有改VSync、驱动配置、优先级或战斗负载来掩盖等待。

### 无额外探针、屏幕内窗口的最终六轮

`final-manifest.json`记录全部运行时代码/场景/资源SHA256；每轮前后源码相同。窗口1600×900位于80,80；原VSync/FPS设置，AGL_FRAME_PROBE及扩展桶关闭。C1 36/36、C2 48/48与24km，全部8/8巡检、render_scale=1、2×MSAA。volume satellite=disabled，不能替代东京地图性能门。墙钟为_process入口间隔，和引擎delta分别保留，不声称它是显示器硬件扫描时间。

|场景|引擎慢帧|墙钟慢帧|墙钟最差ms|严格60|
|---|---:|---:|---:|---|
|final-c1-1|15|18|23.273|未通过|
|final-c2-1|34|27|22.833|未通过|
|final-c1-2|22|35|36.817|未通过|
|final-c2-2|27|36|37.144|未通过|
|final-c1-3|7|21|20.812|未通过|
|final-c2-3|44|25|23.418|未通过|

六轮wrapper0、没有可选FrameProbe启动记录，原始文件路径见`final-summary.json`。不以平均112–117FPS或测试退出0替代严格60，也不以屏幕内复测否认仍存在的呈现等待。额外CPU采样后恢复正式源码，再执行默认all；最终结果另补。


### 全量时限与失败计数门补修

`all-final.log`：同步105组无失败，但在full_war第二次建场时达到300秒总上限，wrapper124；这是未通过，不能用先前通过结果覆盖。随后 `full-war-focused.log` 32/0、AudioShutdown5帧clean；原命令不加预算重跑 `all-retry.log` 为105/0、LifecycleGauntlet93/0、full_war32/0、AudioShutdown6帧clean、wrapper0。因此未复现场景重进死锁，但全量运行时限稳定性仍需关注。

追查此前“尾迹11/3而wrapper0”发现独立的断言结果汇总缺陷：BenchRunner只读 `_fail`，忽略五类使用 `_failed`/返回字典的已注册测试。现读取 `run()`返回的failed、_fail、_failed并取最大值；BFM专用布尔入口保留。增加每组同步用例耗时输出，避免下次全量超时只能看到末尾阶段。

`verify_unit_gate.py`临时故障注入逐项校验恢复原字节：字典返回失败、_failed失败且字典0、旧_fail失败三轮实际wrapper均为1；正式trail/weather恢复后均0，详见`unit-gate-results.json`。三次退出1是预期负对照，不是生产回归失败，也不是关闭运行时86门。尾迹14/0与weather原断言均保留。

这项测试调度器修复发生在六轮Visual之后；仅 `_run_unit_test` 变化，Visual路径未变，源文件差异记录于`post-perf-test-gate-delta.json`。修复后默认all记录于`all-gate-final.log`，12:26结束：105项同步测试失败0，LifecycleGauntlet 93/0，AudioShutdown 7帧后 playback_remaining=0、pending_loads=0、clean=true，wrapper0。不能把先前一次300秒超时从历史中抹掉，也不以本次功能回归通过替代性能验收。

最终all中104个普通同步入口计时合计176.005秒（BFM专用入口不在该计时中），其中tokyo_cells 103.572秒、dogfight_growth 21.981秒；这是测试套件耗时，不是战斗单帧成本，也不能倒推上一轮超时的唯一原因。收尾校验：文档锚点254份/2000个通过，玩家缓存持有者漏登记0，文档链接/spec登记与元数据一致，修改范围diff空白校验通过。

12:29已将源码与bench窗口明确交回地图聊天，并通知状态栏、机场进化聊天先与地图聊天交接再恢复写入/测试。本聊天不再启动bench或修改运行时代码。两次管理员采样已正常停止，诊断临时代码已恢复；14轮Visual/诊断记录均退出clean，未报告运行时错误或退出泄漏。当前剩余问题是严格60仍未通过、已定位的交换缓冲等待尚未消除，以及历史285.953ms停顿未能复现归因。此次没有调整画质、地图覆盖、战斗数量、VSync、帧率预算、进程优先级或驱动配置。

## 2026-10-25 地图交回后的等待来源复核

地图聊天明确交回窗口后，状态栏与机场进化聊天均确认冻结；本轮没有修改生产代码。源码快照为 `tmp/perf-resume-20261025/frozen-source.json`，两轮结束后1377份代码/场景/tres/project文件哈希无漂移。Godot编辑器仍由用户保持运行，没有关闭外部应用。

### 图形服务线程与游戏等待的关联

继续分析先前已保存的两份ETL，而非重新触发管理员录制：

- CPU+GPU跟踪中，游戏线程31084等待至35325416µs；35325410µs的ReadyThread事件明确由 `NVDisplay.Container.exe (3620)` 的线程5668唤醒它。该游戏context最后几项提交55159/55160在35301725/35301729µs已完成，早于长等待结束。这不能证明所有GPU工作均已完成，但不支持把这段等待直接归为这些队列包尚未渲染。
- 独立CPU跟踪中，游戏线程55968的17.058ms等待在14808107µs结束；14808102µs同样由PID3620/TID5668唤醒。两处ReadyThread不带InDPC标记，唤醒栈经过nvlddmkm、dxgkrnl；附近该线程用户栈含 `nvapi64_impl.dll` 和 `_nvtopps.dll`。
- 原始事件和栈保存在 `tmp/perf-resume-20261025/nvdisplay-ready-evidence.json`。可确认具体唤醒者与驱动调用链；没有私有符号，不能声称已解析锁持有对象、具体NVIDIA函数或所有慢帧的根因。
- 只读服务检查把PID3620对应到 `NVDisplay.ContainerLocalSystem`（NVIDIA Display Container LS），当前Running/Auto、可停止、无依赖服务。显卡为RTX3080，系统报告驱动32.0.16.1088。没有修改服务、启动类型或驱动配置。

### 当前源码60秒C2复测

两轮均官方Shadow Visual、屏幕内1600×900、原VSync、48/48演员、24km战线、8/8巡检、render_scale=1和2×MSAA；报告见 `tmp/perf-resume-20261025/summary.json`。

|样本|额外探针|脚本帧首慢间隔|最差脚本帧首ms|退出|
|---|---|---:|---:|---|
|c2-diagnostic|FrameProbe/扩展CPU/慢帧记录|44|20.823|wrapper0、AudioShutdown4帧clean|
|c2-no-probe|关闭|46|20.240|wrapper0、AudioShutdown clean|

这些是当前环境证据，不与上午不同外部负载样本直接计算收益。额外探针内 `3 <= bench_t < 60` 的完整迭代最差16.960ms；由start+total-post重建的post_draw间隔最差16.754ms，60个间隔超过16.667ms，仍未通过严格60。post_draw也不是显示器硬件扫描时间。第7120帧92.874ms发生在bench_t=60.0167的报告序列化收尾，不当作战斗窗口中的尖峰；历史285.953ms停顿仍未复现。脚本帧首、引擎delta、完整迭代和post_draw边界不同，不能相互替代。

已准备但未执行 `container_trial_guard.ps1` / `run_container_trial.py`：同负载原状态→临时停止上述容器服务→恢复后对照；helper最多等待120秒并在finally尝试恢复及核验，外层必须显式授权标志。只通过静态语法检查，尚未证明服务恢复路径实跑通过。由于用户此前只授权管理员采样并要求保留外部负载，临时停止服务另行请求明确许可；未收到许可不得运行，也不将此诊断当作游戏代码修复。

地图三轮报告另有983–1704ms镜头响应等待（零HLOD缺图不代表响应通过）。只读复核首轮frame412–563存在约1705ms镜头完全静止且pending_pan>1的区间。地图聊天仍继续调查栅格Detail可见瓦片缺失/淡入，本轮没有改其调度或预算。当前C2复测结束后归还地图测试窗口，剩余掉帧与地图响应均不标为已解决。


## 2026-10-25 晚间交回后的回归失败复核

用户已明确选择“保持所有服务运行，只做代码和采样排查”。上节服务临停方案未执行，现已拒绝；不得运行 container_trial_guard.ps1 / run_container_trial.py，不再请求同一许可。管理员只读采样授权仍有效。

地图交回后，三方协调保留全部未提交改动。`tmp/perf-handoff-20261025/source-before.json` 冻结1079份源码/场景与配置；本段代码只修改 `scripts/tests/test_tokyo_hlod_stream.gd` 的高度纹理夹具：Shadow不复制tmp，夹具应创建该目录、使用PID/时间唯一文件名，并在流送close与跨帧释放后删除和确认不存在。没有改地图运行时代码、画质或战斗负载。

复核地图的 focused-lifecycle.log：Desert preload timeout来自测试主动把deadline置零的取消用例，该测试实际22/0通过，不应列为额外回归失败。LifecycleGauntlet93/2由prepared catalog fail1与高度纹理保存失败汇总，不能把警告数量当失败数。

官方Shadow Headless复测使用稳定系统临时副本：tokyo_map_planning 1 180 的目录/规划/worker/admission全部0失败、wrapper0、AudioShutdown7帧clean；诊断仅通过源码overlay为目录测试加失败行打印，没有改正式目录代码。旧sandbox副本中的目录失败未复现，原因仍未确认，不能称已修复。高度夹具修改后，AGL_TOKYO_HLOD_STREAM_TEST=1 的 tokyo_cells_lifecycle 1 180 为wrapper0、packed height及流送检查0失败、AudioShutdown12帧clean。日志在上述tmp目录。

只读复核地图current-3d-final-r1/r2/r3：五段565–710ms镜头位置和zoom完全不动且目标zoom尚未到达，全部reason=retained、pending峰值0、texture_pending峰值0；分别见summary.json的camera_stalls。它们证明当时并非等待已登记的网格/纹理任务，后续需追规划结果、资格与提交条件；不据此直接判定唯一根因。原显示完整性通过仍独立于相机响应和严格60。

地图聊天还需要F5现场确认，本段focused结束后立即交回窗口。默认all、代表性Visual与严格60仍待后续最终源码复验；本段只修测试夹具，不冒充战斗掉帧已解决。

## 2026-10-26 凌晨交回后的退出与目录失败定位

地图明确交回、三方冻结后，本轮只保留 `tokyo_map_admission_case.gd:presentation_guard_checks` 的测试生命周期修复：CameraController继承Node，原夹具new后未入树且未free，verbose明确报CameraController脚本资源及Node共3个ObjectDB、1个resource残留。现add_child、queue_free并跨帧用WeakRef确认释放；稳定系统Shadow的planning-fixed-typed.log与planning-final.log均focused wrapper0、AudioShutdown clean、无ObjectDB/resource残留。初次新增弱引用推断触发86的planning-fixed.log已修为显式WeakRef，保留失败证据。索引机械刷新3处，玩家引用、文档锚点、文档链接与diff检查通过。

证据 `tmp/perf-return-20261026/`。原受限环境planning-restricted.log复现prepared catalog失败：生产write原114行FileAccess.open临时文件返回error=12，夹具原83行写入断言返回false；绝对路径是宿主AppData/Roaming/Godot/app_userdata/AGL/tokyo_prepared_catalog。稳定系统Shadow同源目录测试通过。不能把这个结果认作地图选择算法失败。

尝试把夹具路径迁到res://tmp并保留正式CACHE_ROOT合同，稳定系统通过，但planning-restricted-fixed.log仍prepared catalog fail1（其他planner/context/worker/admission均0，无泄漏），所以该路径候选未完成验证，已保存catalog-path-candidate.gd并仅撤回本轮这项未证明有效的改动。正式prepared catalog生产代码与测试路径均保持交回时状态。全量all按focused失败门未启动，不能宣称全量通过。

地图要求优先补真实drag=sweep三轮和F5。第二轮诊断在资源同步阶段主动取消，确认没有游戏测试启动；仅终止本聊天已核实的进程树33280及其wrapper19768/robocopy，随后验证owner19768已退出后移除本聊天锁。用户编辑器52484与全部服务保留。catalog-overlay2/diagnostic2为未执行完成草稿（日志缩进需重生成），不可直接复用或作为结果。现在再次交回地图源码与测试窗口。

地图上一轮自然入场三次显示完整性通过，城市诊断首次可见后hidden0但首显前14帧hidden且冷轮wait896ms失败；此前drag=1的input_pixels/camera_distance均0，不能算实际拖动验证。战斗严格60、历史285.953ms和pending=0/retained长停顿仍待继续，本轮不宣称生产慢帧已解决。

## 2026-10-27 地图 final-v24 交回后的目录归因与新性能基线

地图明确交回源码/bench窗口后，只读确认状态栏继续冻结、机场无新增工作，核对final-v24的1094个运行时来源摘要零漂移、无测试锁及Godot进程。本轮没有改生产源码或正式测试路径；仅重新生成tmp内诊断overlay并用于Shadow副本。地图/相机交接生产文件保留给待人工F5复核的候选，候选默认仍关闭。证据集中于 `tmp/perf-resume-20261027/summary.json`。

目录失败分为两个位置：`catalog-restricted.log`的原user路径在临时文件FileAccess.open返回12；res://tmp路径则mkdir成功、写入及回读等值成功，DirAccess.rename_absolute返回1，首次写入仍失败。相同新诊断在稳定宿主Shadow的`catalog-host.log`中两条路径均通过，重建、损坏缓存拒绝与清理均通过，wrapper0。由此定位为受限执行环境中的文件操作差异，不需要以更改生产缓存算法或放宽断言掩盖；底层Windows拒绝原因未继续追至具体系统调用。旧res://tmp迁移候选仍不采用，未声称它已修复受限测试。

撤除overlay后执行默认 `all 1 300 Shadow Headless`，`all-host.log`为wrapper0、prepared catalog与map planning均fail0、LifecycleGauntlet93/0、AudioShutdown11帧clean；verbose未发现ObjectDB/resource残留。因此此前本聊天未完成的all现已在当前源码补齐，但该结果不代表Visual或严格60通过。

随后同源运行两次60秒东京C2 Shadow Visual，显式加载final-v24地图候选及DISPLAY_COMPACTION=1，仅限测试进程；48演员目标、24km范围、初始33飞机/12地面/6海军、无模拟分频、8/8巡检、原渲染设置保持。探针轮墙钟9918样本、7慢帧、max20.369ms；无探针轮9970样本、4慢帧、max17.922ms，二者strict60均失败且wrapper1。显示检查分别9919/9971帧，hidden/uncovered/unqualified/budget全部0；AudioShutdown分别6/3帧clean，无运行时错误或退出残留。自然损失造成结束演员48/47，不是降低初始或目标负载。

FrameProbe完整迭代在3<=bench_t<60有9919样本，其中两帧超过16.667ms：frame3735为18.527ms（physics脚本4.189、process脚本6.669、render3.717ms），frame3736为17.946ms（physics脚本5.609、process脚本4.978、render3.783ms）。同期桶包含飞机物理2.655/3.216ms、状态栏1.974/0.599ms、地图stream1.927/1.542ms；stream纹理子桶不能重复相加。完整迭代与墙钟帧边界不同，2与7不能混为同一计数。下一步追查这些脚本工作重叠并补同源无探针对照；本轮未复现43.053ms或历史285.953ms，不沿用旧NVDisplay.Container关联作为当前原因。全部1094来源在测试后仍零漂移，自有测试结束、锁已释放；人工F5、扩大覆盖及严格60仍未完成。

后续只在Shadow overlay给状态栏添加tactical/content/positions三个分段计时，未改生产文件或行为。`status-phase-summary.json`记录同负载60秒：墙钟10240样本、2慢帧、max18.581ms，严格60仍失败；完整迭代10242样本max16.475ms、0慢帧，不能用其代替墙钟门。显示10241帧零异常，AudioShutdown9帧clean，wrapper1，无运行时错误或资源残留，1094来源零漂移。最后1秒快照状态栏总405µs/帧，位置239µs、战术99µs、内容64µs；这不是慢帧或全程统计，尚不足以认定内容刷新是主因。下一步应同时开启既有AGL_TOKYO_WALL_TRACE与FrameProbe，先按墙钟真实慢帧对齐工作，再选代码候选；没有因完整迭代0慢帧宣布修复。


墙钟对齐补查（`wall-phase-summary.json`）：在同一60秒C2同时启用WALL_TRACE、FrameProbe及状态栏分段overlay，墙钟9954样本3慢帧、max16.797ms，显示9955帧零异常，AudioShutdown2帧clean、wrapper1。时间线三个慢间隔为16.787/16.685/16.683ms；逐一用“前一完整迭代 + 当前物理/信号前段 - 前一物理/信号前段”还原，误差分别0/0/1µs，确认之前计数差来自采样边界，不是可以放宽门限的理由。三个慢间隔均包含单次纹理上传2027/2004/1074µs，最后一个还叠加规划提交1266µs，中间一个状态栏内容896µs；没有证据把状态栏单独定为根因。现上传策略单次无论大小必须推进，第二次仅允许首个小于1ms且两张均<=1MiB；本轮每慢间隔只有一次上传，因此简单把每帧最大2张改成1张不针对该样本。下一步应测试保持可见内容与响应的工作调度候选，地图/相机生产修改仍先协调，不能混入待人工F5候选。1094来源仍零漂移，未改生产，测试结束无锁。


上传与规划错峰隔离试验（`tmp/perf-resume-20261027/schedule-summary.json`、`schedule-input-comparison.json`）：仅Shadow覆盖层把“本帧已有纹理上传”纳入非紧急规划争用，沿用原两帧让出上限；镜头有待处理输入、画面安全依赖推进时照常执行，已就绪提交不新增让出。新增夹具覆盖饥饿上限、紧急推进、镜头等待及提交豁免。首轮因候选bool推断失败被wrapper86拒绝，明确类型后聚焦0；候选默认all通过、LifecycleGauntlet93/0，无ObjectDB/resource残留。没有改正式源文件或F5候选。

同源同负载60秒C2对照：控制9335样本/4慢帧/max18.575ms；候选10122样本/3慢帧/max17.164ms。候选新增错峰99个间隔，纹理上传与超过100µs规划提交共现间隔79→32；这只证明调度实际触发，单轮不足以确立性能收益。两轮严格60均失败、wrapper1；显示9336/10123帧hidden/uncovered/unqualified/budget全部0，AudioShutdown4/2帧clean。原48演员目标、24km、初始33飞机12地面6海军、无模拟分频、8/8巡检保持。

补当前输入对照而未沿用旧三轮：候选sweep/return为3845/3617帧，控制4219/3770帧；全部显示与镜头/合成坐标异常0、正式审计fail0、资源释放完成。两边sweep各21个缩放阶段到位、return各11个SPACE案例通过。最大等待候选337/302ms、控制351/238ms；候选SPACE首响应9–25ms、到位344–866ms，控制5–25ms、232–879ms。各轮仍有超过250ms目标的等待，虽然均在500ms硬门内；这些输入审计不是严格帧率样本。不能因C2慢帧数少一次便宣称响应没有退化，亦不能凭一次return差异确认因果。因此本候选不采纳、不写入生产，不扩大为整体通过。后续先检查规划请求与单次上传的实际成本，避免继续靠延后工作碰运气。

收尾正常Shadow同步已撤去全部三份候选/计时覆盖，文件摘要与生产一致；恢复后tokyo_map_planning wrapper0、AudioShutdown3帧clean。1094来源零漂移，本轮Godot进程全部结束、无锁；人工F5、严格60及扩大覆盖仍未完成。


规划提交成本分段（`tmp/perf-resume-20261027/submit-profile-summary.json`）：仍仅Shadow计时，原调度和负载不变。882次提交的pure/encode/copy/dispatch中位数分别397/67/52/8µs，pure累计374325µs，占这四个子阶段总和约76%，不包含外层构造请求成本；父子桶不重复相加。该轮墙钟9781样本6慢帧max20.230ms，显示9782帧零异常。另捕获单次ImageTexture创建API耗时9599µs，对应2012×2012、mip_bytes=2701792的纹理；这不是GPU执行时间或驱动归因，旧285.953ms仍未复现。

纯值检查候选差分（`pure-profile-comparison.json`、`pure-candidate-status.json`）：先试Array[int]逐值预算加match类型分支，实测中位数493µs、p95 885µs，比原397/724µs更慢，已拒绝（pure-candidate-overlay.json/pure-only-overlay.json不得误当推荐候选）。随后把同层子值一次记账，仅嵌套容器递归，保留原MAX_DEPTH、MAX_REQUEST_VALUES、对象/Callable/Signal/RID拒绝及序列化字节门、独占深复制、完成/退出语义。125组值/嵌套/危险值与12档预算及循环边界对照原算法一致；固定同一输入每200次原65.49–72.22ms、候选29.74–31.04ms。宽度队列版本只做过聚焦，被深度有界递归版本替代。推荐候选的focused与默认all均wrapper0，LifecycleGauntlet93/0，无ObjectDB/resource残留。

容器递归候选同负载C2计时：879次提交pure中位201µs、p95 348µs、max410µs（原397/724/869µs），encode/copy/dispatch中位68/50/8µs。局部校验成本约减半，但该轮墙钟9726样本3慢帧max18.294ms，显示9727帧零异常，严格60仍失败。去掉FrameProbe、WALL_TRACE、STREAM_AUDIT及状态栏计时后重跑当前同源控制/候选：控制9953样本4慢帧max19.953ms，候选10420样本5慢帧max17.712ms，均wrapper1、严格60失败；显示9954/10421帧异常全0，AudioShutdown2/9帧clean。两轮保留48演员目标、24km、初始33飞机12地面6海军、原渲染、无模拟分频与8/8巡检，不能以最大帧时间下降代替严格门通过，也未证明整体慢帧率改善。

干净候选及差分仅保留于tmp的pure-container-clean-overlay.json与pure-container-candidate.patch，未写正式源码、未混入待人工F5基线。尚需本候选的输入到位/等待和扩大覆盖验收、正式地图文件协调；上一轮调度候选的输入结果不能替代它。恢复正常Shadow同步后，四份覆盖目标逐一摘要与生产一致，恢复focused wrapper0、AudioShutdown14帧clean；1094来源零漂移，测试Godot均结束、无锁。后续在保护当前F5候选前提下补验证，并继续检查剩余单次上传、首次资源存在性检查及脚本重叠，仍不把外部服务相关性当作根因。

## 2026-10-27 纯值候选的当前输入门未通过

只读协调仍是地图明确交回、状态栏冻结、机场无新增任务。补查发现1094份运行时摘要中的地图资源只有package.json；本轮增加独立资源核验，沿package及其JSON目录中的res://路径与SHA256引用核对4188份文件、998129112字节，测试前后均全部匹配。二进制原生表本身已核摘要，表内嵌依赖仍由运行时验证，不能称此静态检查覆盖了所有二进制引用。证据为 `tmp/perf-resume-20261027/map-resource-closure.json`、`map-resource-closure-after.json`；各轮前后1094源码摘要及4188资源大小/修改时间无漂移。

仍只给Shadow应用pure-container-clean-overlay.json。聚焦wrapper0后，计划的三轮输入验证在第一轮sweep失败即停止，未运行扩大覆盖：3645帧显示、覆盖、预算、镜头/合成坐标异常全0，但21个缩放阶段有2个未到位，审计fail2、wrapper1。17秒与41秒终点目标均0.2，实测0.204003319与0.204084545，原2%误差门保持不变；最大等待277ms，超过250ms目标但未超500ms硬门。两终点均retained且显示合格/覆盖完整，最后样本网格pending均0，纹理pending分别3/0；不能把pending=0当作镜头已到位。

同源同输入控制sweep为4290帧、21阶段全部到位、最大等待229ms、fail0/wrapper0。补同轮SPACE对照：候选3902帧/控制3871帧，各11案例通过，首响应5–21/5–22ms、到位342–876/334–871ms；最大等待275/250ms。四轮均保留36单位战斗输入夹具、1920×1080、32格滚轮和原45秒输入脚本，显示异常0且资源释放；AudioShutdown依次5/11/37/39帧clean，无ObjectDB/resource残留或运行时错误。输入审计不是严格帧率样本，不能替代此前C2两边均失败的严格60结论。单次控制通过、候选失败不足以确认算法退化因果，但已足以阻止该候选晋级；局部校验减半的证据不能盖过输入门失败。当前候选只留tmp，不采纳到生产，不以重复跑出一次绿色覆盖失败记录。详见 `pure-input-current-summary.json`、`pure-candidate-status.json`。

只读复查既有同源分段数据：资源exists桶在原算法轮455个非零样本中位2µs、p95 605µs、最大1358µs；容器候选轮480个非零样本中位2µs、p95 642µs、最大1475µs。候选frame908的18.253ms慢间隔含1366µs exists（当帧8次请求）与物理/规划工作叠加。这是多次检查的累计CPU桶，不是一次调用耗时；不据此改请求配额、去掉存在性/摘要验证或定因驱动。后续应先核查候选输入失败的复现条件与资源就绪/接纳时序，再考虑独立的成本削减实验。

临时批处理首次因PowerShell把正常静音stderr提示提升为终止异常，在focused已成功退出后停止；仅修正tmp驱动的外层异常处理，正式wrapper运行时错误门未动。收尾普通Shadow同步撤去候选，两份候选及历史计时目标共四文件逐一摘要与生产一致；恢复tokyo_map_planning wrapper0、AudioShutdown8帧clean。全部本聊天测试结束、无Godot进程、无锁。生产源码、正式测试路径、默认开关和待人工F5候选均未修改；扩大覆盖、本候选三轮输入、人工F5及严格60仍未完成。

输入失败复查（`pure-input-orderb-summary.json`）：预先固定只追加一组“控制先、候选后”的同条件sweep，不运行到通过为止。控制3903帧出现5秒终点未到位：目标0.2、实际0.220571786，fail1/wrapper1，最大可操控输入等待343ms；候选4335帧21阶段全部到位、fail0/wrapper0，最大等待296ms。两边显示、预算、镜头/合成异常0，资源释放，AudioShutdown40/59帧clean。连同上一组，目前原算法和容器候选各一次通过、一次失败；因此未建立“纯值优化导致输入退化”的因果，也没有建立候选可接受。原失败全部保留，候选继续只在tmp，不能用本次绿色覆盖其此前fail2。控制的wall_wait_max=1332ms另查为212个连续input_open=false样本、input_ms固定9324，发生在正式veteran_hp升级模态期间，非1.3秒可操控输入停滞；5秒缩放失败仍独立成立。

`pure-input-alignment.json`通过每个正等待样本的`camera_wait_started + camera_wait_elapsed_ms - ms`恢复绝对时钟起点。四次sweep分别491/382/661/437样本得到唯一常量33179/33961/34073/33208ms。输入samples.frame是局部样本编号，selection_trace.frame是Engine进程帧，不能直接按同号拼接。原候选17秒失败的最后样本前5ms，目标资源仍未就绪、纹理pending3；最后样本后21ms才记录同一目标资源就绪。41秒失败在最后样本前6ms已记录next_ready=true，但`prepared_result`追踪调用位于`_admit_prepared_plan`之前，这个字段只证明资源可用，不证明最新机位资格/覆盖已被接受。原算法新增5秒失败也在compact_displayed_scale就绪后转入handoff暂存，末样本前7ms仍有4网格/4纹理请求。已有日志能定位资源就绪与输入阶段边界重叠，尚缺最新camera_demand和接纳后的状态，不能宣称只需多等一帧或放宽2%门。

本轮未增加生产或候选算法修改。下一步若加诊断，应只在Shadow的现有追踪条目补最新待提交机位及接纳前后计数/目标状态，保持原条目上限与输入规则，避免直接倍增追踪条目而截断后半段；再依据实际拒绝理由设计候选。正常Shadow同步已恢复全部四个目标文件与生产一致，恢复focused0、AudioShutdown14帧clean；1094源码与4188资源大小/mtime无漂移，无Godot进程或锁。严格60、扩大覆盖、人工F5与候选完整输入验收均未完成。

接纳前后诊断（`admission-trace-overlay.json`、`admission-trace-summary.json`、`admission-trace-status.json`）仅覆盖Shadow中的tokyo_hlod_overlay，使用原纯值算法，未启用容器优化候选。每个原prepared_result条目补camera_demand及接纳前后计数/目标状态，不新增事件、不改2048上限。首次把SELECTION_TRACE全局开到focused时，既有简化StreamProbe缺handoff_increment，诊断与撤覆盖后的原算法均wrapper86，失败日志分别留档；未关闭错误门或修改正式夹具。改为标准focused/all配置、仅真实输入场景开启追踪后，focused0、all0、LifecycleGauntlet93/0，AudioShutdown5/15帧clean，无退出残留。临时PowerShell驱动的中文注释需UTF-8 BOM，首个编码解析失败未启动Godot，修正仅在tmp。

原算法追踪sweep3572帧，显示/覆盖/预算/镜头合成异常0、资源释放，但5秒缩放目标0.2、实际0.218657613未到位，fail1/wrapper1，最大输入等待299ms，AudioShutdown28帧clean。这是诊断复现，不是无探针性能或候选验收。1053条追踪全部具有前后状态且未饱和；applied计数增加908次、rejected145次，其中133次为revision不匹配，目标键/目录改变191次。不能把applied计数或目标键未变当作最终机位被接受或工作必然冗余，元数据、覆盖和预测仍可能变化。

5秒末样本的绝对时间由452个正等待样本一致恢复。末样本前229ms，compact_displayed_scale目标被实际接纳暂存；前125ms该压缩显示已提交，revision由68变69，旧revision68结果被正确丢弃；前97ms新handoff目标被接纳暂存，目标76143280字节、物理联合100661200字节，仍在96MiB=100663296上限内。末样本前7ms尚有1网格/1纹理请求，后16ms资源才全部就绪；期间没有同revision连续拒绝导致卡死的证据。当前定位为显示压缩腾池后再载入前向交接的两阶段资源等待与输入终点重叠，尚未证明可以省掉哪一步，不能去掉预算/覆盖门或以延长输入阶段掩盖。

下一步先核这一两阶段过程的实际共享资源费用与发起/完成顺序，区分预算要求的腾挪和可避免的重复工作，再构造只在tmp/Shadow的成本削减候选。收尾普通Shadow同步撤去诊断，包含新地图追踪文件在内共五个历史覆盖目标摘要均与生产一致；恢复focused0、AudioShutdown8帧clean，1094源码/4188资源大小与mtime零漂移，无Godot进程或锁。日志核对本轮及之前all-host、无探针对照、输入对照均为Godot v4.7.2.stable.steam.ed1daf0bf，不能沿用导航中的历史4.7.1标签报告实际版本。正式源码、正式路径、F5默认与所有用户服务未改，严格60及完整输入验收仍未完成。


## 2026-10-27 两阶段交接的物理费用复核

本轮只分析已有 admission-trace-sweep，不运行 Godot、不改生产源码。`tmp/perf-resume-20261027/analyze_handoff_resources.py` 从实际七份 JSON 目录恢复交织目录（来源顺序4/5/6/3/2/1/0），按网格路径、纹理路径去重和每页288字节地表费用重算；三个切面费用及两段联合费用与运行时逐字节一致，结果在 `handoff-resource-summary.json`。

旧显示63830224字节、紧凑显示44361608字节、前向目标76143280字节。旧显示与紧凑显示联合95840856，紧凑显示与前向目标联合100661200（距96MiB上限仅2096字节）；直接旧显示与该前向目标联合133798016，超上限33134720字节。三者同时保留需152140448字节。故不能直接跳过腾池或提前全量加载同一前向目标。对九个同空间页分别保留旧档或切换已观测紧凑档，完整穷举512种组合，仅九页全部切换能同时满足前后两段联合预算；此结论只覆盖这些页版本，不排除不同空间切面存在更佳路径。

紧凑阶段新增12个物理资源、32008040字节，释放旧集12个资源、51476656字节；前向阶段相对紧凑集新增12个资源、56296712字节。紧凑阶段有7个资源、18339840字节不在旧集或最终前向集，但它们承担预算内显示桥接，不能称为可直接删掉的浪费或重复I/O。追踪聚合计数显示38680ms紧凑显示已提交，仍有2个纹理退役；38708ms前向接纳时网格pending3，38737ms纹理请求数由38变42、仍有1个退役；38821ms目标资源全就绪。旧追踪没有开启路径审计，无法把这些聚合增量分配到具体资源，也不能确定它们是目标、预取还是重复请求。

下一步若补运行诊断，应预先固定一轮原算法输入，在现有prepared_result条目中仅加入本窗口资源的请求/缓存/校验/纹理状态和统一时钟，保持2048条上限、原输入与全部验收门。原STREAM_AUDIT只有累计路径次数及纹理最后上传帧，单独开启仍不足以恢复每个资源的完成顺序；不得将其当成完整I/O时间线。先定位必要读取、摘要、上传、退役与投机请求的具体重叠，再决定是否存在保持内容和响应的成本候选。pure容器候选继续冻结；本轮没有新增性能/输入/退出通过结论。1094源码摘要和4188资源大小/mtime均无漂移。


## 2026-10-27 固定资源身份诊断

仅Shadow应用 `resource-trace-overlay.json`，在既有prepared_result中为上一轮三切面的42个固定资源记录整数状态：网格缓存/请求/摘要线程、图片线程完成/缓存/退役、wanted/pinned/visible及路径累计次数。仍限2048条，不新增追踪事件、不持有Resource、不启用pure候选。首次聚焦遇到StreamProbe没有_pending字段，wrapper86，保留 `resource-trace-focused-fixture-failed.log`；将新增内部状态读取限定在真实输入场景的AGL_PERF_RESOURCE_TRACE开关后，标准focused/all均0、LifecycleGauntlet93/0，AudioShutdown4/4帧clean。正式夹具与错误门未改。

预先固定的一轮原算法sweep已完成，不追加追绿：3513帧，1050条完整追踪，显示/覆盖/预算/镜头合成异常0且资源释放。5秒终点本次zoom0.200457871、通过2%门；41秒终点目标0.2、实际0.212569639未到位，fail1/wrapper1，最大输入等待466ms，AudioShutdown50帧clean。这不是无探针帧率或候选验收，不能用本次5秒通过抹掉此前失败，也不能把466ms差异直接归因算法或探针。证据 `resource-trace-summary.json`、`resource-trace-end41000-summary.json`、`resource-trace-paths.json`。

5秒窗口已捕获具体资源重复请求：例如网格4d852ccc858c先被非visible请求并缓存，38827ms已淘汰，38947ms作为visible目标重新请求；纹理1f576e2ffe3c和b8a99022b32e在38766ms已上传、38827ms已因预算退役，随后作为visible目标重读并再次上传。纹理127039f88940先出现已完成图片worker但未上传，38827ms已不在缓存/任务，38970ms第二次请求，39023ms上传。上述是可定位的重复工作证据，但还没证明在当时预算和完整显示下可以保留，不能直接增加缓存、关闭摘要或用时间宽限强留。状态只在原规划结果边界采样，5秒窗口最大间隔110ms，事件时间只能由相邻观测夹定，不能当作精确I/O时长。

41秒失败发生在hlod_actual→hlod_guard，目标联合99966716字节；最后样本前5ms仍未就绪，后25ms才next_ready。其30个目标物理资源仅4个属于预先固定的42路径，因此本轮不能归因最后3网格/2纹理具体身份。该窗口最大快照间隔54ms；不用扩大追踪或再跑一轮填满结论。下一步先离线重建5秒重复资源被淘汰时的当前/目标/预测物理费用与排队顺序，判断预算要求的淘汰和可避免投机重读；若存在预算内替代才设计候选，41秒问题保留独立未决。

正常Shadow同步已撤去诊断，五个覆盖目标摘要全部与生产一致；恢复focused0、AudioShutdown8帧clean。`resource-trace-status.json`记录无Godot进程、无锁，1094来源与4188资源stat零漂移。本轮生产/F5默认/服务未改，pure候选仍冻结，严格60及完整输入、扩大覆盖、人工F5仍未完成。


## 2026-10-27 重读资源保留费用的离线边界

本轮继续只读核协调、源码与锁，随后只生成tmp分析和本审计，没有运行Godot或修改生产。`analyze_reloads_budget.py` / `reload-budget-summary.json` 按真实目录物理路径重建5秒窗口的当前显示+目标，所有23个快照的联合费用逐字节匹配target_union。窗口内7个重复请求资源共29575080字节；38827ms当前/目标联合47477976，加入这7个身份仅77053056，表面在96MiB内，但当时实际池占用81331112，加回已缺失7资源会到110906192。38865ms同样会到114179336；不能只看当前/目标下界而强行保留全部重读资源，未追踪的在途/投机/退役占用并非不存在。

单独核已经缓存后被淘汰的网格4d852ccc858c和两张小纹理1f576e2ffe3c/b8a99022b32e，共6657416字节。在38827–39053ms所有既有快照上，给实际池加回其中尚缺失的身份均未超上限；例如38827ms为87988528，38970ms为100074160。它只把可调查范围缩到这三个资源，不能证明可行调度：淘汰发生在两个快照之间，prepare_target_space还会按完整wanted缺口调用_prune，未发起的预约未在实际total内，当前追踪也没有完整投机队列。不能以此启用强保留、LRU或宽限时间，更不能换预算。

代码读到的关键分支为HLOD prepare_target_space累计未缓存/未pending的网格及未持有的图片费用后调用_prune(missing)；HLOD _prune先执行父类网格淘汰，再计划两帧后归还纹理租约，实际分配仍核真实池余额。现有快照不能判断三资源是被这次完整缺口规划淘汰、实际单份分配淘汰，还是中途旧wanted/pins切换导致。下一次如补诊断，应在tmp/Shadow把采样收窄到这三个身份发生淘汰的_prune入口/出口：有界记录required、实际各费用、完整缺口与目标/预测身份，最多64次，不延长资源持有或改回收/分配分支；先获得准确触发条件，再决定是否有不阻碍真实请求的成本削减。原41秒失败独立保留。本轮没有新的运行时通过或修复结论。

## 2026-10-27 三身份淘汰触发诊断

`prepare_prune_trace.py` / `prune-trace-overlay.json`仅在Shadow为原算法增加有界诊断，未启用pure容器候选。只检查此前三个已缓存后重读的身份，原_prune分支无条件执行；最多64次合格入口快照，只保存实际淘汰事件。各状态列表上限128，记录完整缺口、缓存/在途/退役、wanted/pins/visible、统一时钟及调用栈，退出打印纯值结果。另沿用既有prepared_result接纳前后追踪，不增加该条目上限。

标准focused及all均wrapper0，LifecycleGauntlet93/0，AudioShutdown5/3帧clean，无ObjectDB/resource残留。预先固定的一轮原算法sweep为4074帧，21缩放阶段全部通过，显示/覆盖/预算/镜头合成异常0且资源释放，wrapper0、AudioShutdown16帧clean；最大输入等待345ms仍超过250ms目标。这是带诊断的输入样本，不是无探针性能或整体验收，不能抹掉历史5秒/17秒/41秒失败，也没有严格60新通过证据。

`analyze_prune_trace.py` / `prune-trace-summary.json`恢复64次尝试中的13个实际淘汰事件；尝试上限已饱和，后半段缺事件不代表没有淘汰，已保存事件的各列表未截断。13次调用栈全部来自prepare_target_space，经request_textures进入，未捕获实际单份分配触发这三个身份淘汰。重算唯一网格/图片缺口逐字节等于required，图片wanted没有重复条目；本轮decoded缓存关闭且为0，不能把重复队列计费当成原因。

其中8次全部缺口都不属于visible，也不属于pins；4次全部是visible，1次混合。首次在输入相对4473.37ms：实际池84979048字节，完整排队缺口31368824字节，使预留总量达到116347872并触发网格4d852ccc858c淘汰；当时visible及pins缺口均为0。这里已经定位到为非visible排队资源批量腾空间的触发条件，而不只是两个快照之间的猜测。但它尚不能证明资源一直保留到未来仍可行，实际预取分配以后也可能必须淘汰。

下一步可以构造tmp/Shadow对照：当显式visible集合有效时，批量prepare_target_space只预留当前目标及固定/保护资源的缺口，保留全部wanted/预测队列及顺序，保留实际每份分配的_prune(amount)、真实余额、摘要和生命周期检查；没有显式visible集合时维持原行为。先验证固定资源与pins的完整分类，测试批量投机缺口不提前淘汰、真实分配仍可按预算淘汰、可见缺口仍能腾空间等反例，再做focused/all和固定输入/原负载C2对照。该候选尚未实现或证明有效，不能启用LRU、保留宽限或降低预测内容来冒充成本削减。

正常Shadow同步已撤去诊断，六个历史覆盖目标（新增tokyo_hlod_stream）逐一SHA与生产一致；恢复focused0、AudioShutdown9帧clean。`prune-trace-status.json`记录无Godot进程、无锁，1094源码及4188资源stat无漂移。正式源码、测试路径、F5默认和所有服务未改。pure候选继续冻结，严格60、完整输入、扩大覆盖、实际人工F5仍未完成。

## 2026-10-27 可见目标批量预留候选对照

只在tmp/Shadow生成 `visible-reserve-overlay.json` / `visible-reserve-candidate.patch`，未修改生产。`prepare_target_space`在显式visible集合非空时，仅为visible及pins中的未持有资源批量腾池；没有显式分类时保留原完整缺口算法。固定逻辑页经request_partitioned展开并纳入物理pins；固定图片进入texture_pins，目标地表图属于visible_images，地表租约仍由原auxiliary账本计费。全部wanted与预测队列、顺序、每份实际分配回收、真实余额、摘要、上传及退出路径保持，未启用pure容器候选或额外LRU/宽限。

临时断言覆盖真实缓存与租约：只有投机批量缺口时旧件不提前淘汰，但随后真实分配仍可回收旧件且不超池；visible缺口和无分类回退仍按原路径腾空间；固定逻辑组件展开、地表图片、固定图片累计64字节缺口；缓存/在途/退役/已解码身份不重复预留，队列顺序不变。focused及默认all均wrapper0，新断言fail0、LifecycleGauntlet93/0，AudioShutdown13/14帧clean，无ObjectDB/resource残留。生产测试文件未改，仅在Shadow覆盖原测试入口并保留其全部已有断言。

预先固定候选先、控制后的单组45秒sweep：候选3715帧、控制4047帧，各21缩放阶段全部到位、fail0/wrapper0；显示/覆盖/预算/镜头合成异常全0、资源释放，原36演员夹具与输入门保持。最长输入等待分别270/313ms，仍均超过250ms目标而未超过500ms硬门，AudioShutdown58/60帧clean。单组通过不代表三轮完整输入验收，未沿用其他候选SPACE或旧轮次结果；此前所有5秒/17秒/41秒失败仍有效。

随后同源60秒C2无FrameProbe/WALL_TRACE/STREAM_AUDIT/状态栏计时：候选9959个墙钟样本、6慢帧、max18.826ms；控制9966样本、4慢帧、max18.060ms，均strict60=false、wrapper1。显示9960/9967帧hidden/uncovered/unqualified/budget全0，AudioShutdown10/5帧clean。两边均48演员目标、24km、初始33飞机/12地面/6海军、8/8巡检、模拟divisor1且assigned0，正式体积机身与原渲染参数一致。不能用输入等待单轮较低认定收益；本组帧率也没有显示改善，不能据此单独断言候选导致退化。

证据由 `analyze_visible_reserve.py` 汇总到 `visible-reserve-summary.json`，记录每轮wrapper、真实结果文件、负载、显示和退出。结果文件必须匹配日志的`[Bench] wrote`行：wrapper末尾列举历史结果文件，不能取最后一个文件名；本次分析器首次误选历史文件而缺字段，已修正，未影响任何测试或门限。现有输入追踪末态镜头及切面不同，因此即使累计请求数不同，也不能当作相同资源轨迹的成本削减证据。

该候选保留为未采用实验，未写生产、未晋级。下一步先利用已有输入追踪对齐相同目标/切换阶段，检查是否减少先淘汰后重读、是否把成本移至真实分配等待；若现有计数不足，先明确一组有界对照要回答的问题再补诊断，不能重复跑到绿色。仍需独立验证SPACE、完整三轮、扩大覆盖和严格60；当前无证据支持直接合入或放宽输入/预算门。

正常Shadow同步已撤去覆盖，六个历史目标SHA与生产一致；恢复focused0、AudioShutdown3帧clean。`visible-reserve-status.json`记录无Godot进程、无锁；各轮1094源码摘要及4188资源stat零漂移。F5默认关闭、所有用户程序和服务保持。人工F5仍待用户，未产生新的生产修复。

## 2026-10-27 可见预留候选的已有轨迹对齐

本轮不启动Godot、不改生产，仅运行 `analyze_reserve_alignment.py`，结果 `visible-reserve-alignment.json`。候选443个正等待样本一致恢复绝对起点34093ms；控制427个样本一致恢复34112ms。1077/1128条selection_trace中有1076/1127条落在实际输入采样范围，前一采样距追踪最大29/23ms。按原burst_interval还原缩放阶段，只保留相邻输入样本都在同一阶段、可操控且采样距离不超过50ms的记录；不拼接局部samples.frame与引擎frame。

候选与控制共有112个“同输入阶段+当前目录/键集/阶段+目标目录/键集/阶段”签名，但没有一个同时具有完全相同center与scale的观测。更关键的是两边所有追踪均path_audit_enabled=false、path_requests/path_evictions为空且没有texture_audit，因而不能从现有聚合计数证实三个身份是否少重读，也不能证实批量预留成本是否转移到实际分配。共有切面不能替代相同缓存历史、请求顺序或精确资源事件。此结论不否认候选作用，只明确当前证据不能回答其运行时收益。

下一组有界问题已固定在 `visible-reserve-reload-question.json`，尚未运行：原算法和候选各一次原45秒sweep，仅对既定一个网格及两张纹理记录请求/上传→预算淘汰→再次成为visible并请求的链，区分批量预留与真实分配触发。每臂最多64条纯值事件与固定总数/丢弃计数，不开全路径审计；两臂同诊断，原prepared_result只补事件序号、不增加2048上限。先独立判断各臂是否存在这些链，跨臂仅作共享阶段的描述性对照，不能将不同资源历史的总量相减称为因果收益。饱和后不自动扩大重跑。标准focused/all和正式错误门、原输入/负载/预算均保持。

本轮1094来源摘要及4188资源stat无漂移、无bench锁；没有新增运行时通过、性能改善或生产修复。候选继续未采用，严格60、SPACE、三轮输入、扩大覆盖及人工F5仍未完成。

## 2026-10-27 三身份重读链固定双臂诊断

按预先限定问题执行原算法先、visible-reserve候选后，各一次原45秒sweep。`prepare_reload_trace.py`只在Shadow对既定三身份记录纯值请求/上传/预算淘汰/实际退役事件，最多64条；原prepared_result只补事件序号，不增加2048上限。原回收、分配、摘要、预算与上传分支保持。标准focused/all不启内部追踪开关，两臂均wrapper0、LifecycleGauntlet93/0，无ObjectDB/resource残留；控制AudioShutdown13/11帧、候选14/12帧clean。

控制3626帧，5秒/29秒目标0.2实际0.216692477/0.210284010未到位，fail2/wrapper1，wait358ms；候选3943帧21阶段全部到位，fail0/wrapper0，wait247ms。两臂显示/覆盖/预算/镜头合成异常0且资源释放，AudioShutdown32/30帧clean。新的29秒失败完整保留；不能用候选此次通过抹掉旧失败，或把带诊断的输入差异当成严格帧率收益。

`analyze_reload_trace.py` / `reload-trace-summary.json`恢复控制62条、候选49条事件，均未饱和、丢弃0；1071/1096条prepared_result均含事件序号。控制发现15条“请求→淘汰→再请求”链，其中14条由批量prepare_target_space触发、1条由实际分配触发，9条再请求时为visible。候选仍有12条，其中2条由批量预留、10条由实际分配触发，5条再请求为visible；实际分配调用栈已核为reserve_auxiliary或_process_stream。它证明候选没有消除重读，许多回收转移到了真正申请容量时；不同机位/缓存历史使15对12不能直接称为节省三次重读或整体收益。

例如候选网格4d852ccc858c在输入4332.631ms成功请求，4426.562ms因图片实际预约8109472字节而淘汰，4700.062ms又作为visible请求。原算法同身份4366.125ms请求、4442.635ms批量淘汰、4637.520ms非visible再请求。两张纹理及网格的累计次数也非一致下降：网格请求控制6/候选7；纹理1f576请求均3、上传3/2；b8a请求11/8、上传9/6。请求后可能因需求变化取消，分析器仅把下一次请求之前的upload归到对应请求，不把稍后另一任务上传误算为本次完成。所有链中资源释放均有实际退役或缓存移除证据，事件的账本值是各记录点状态，并非统一分配前快照。

当前结果支持“提前批量回收确有作用点，但真实池压力仍会迫使重读”，不足以支持强保留、删预测、增预算或直接采用visible-reserve。上一轮无探针C2候选6慢帧max18.826ms、控制4慢帧max18.060ms的失败仍是当前帧率结论。候选仍未采用；本轮不再追加追绿或扩容审计。下一步先只读复核现有慢帧中的单次图片创建和首次exists路径成本及已做的缓存语义，寻找独立的成本削减，不继续只换回收时机；任何新候选仍保留存在性/摘要/响应/负载/覆盖与预算。

正常Shadow恢复focused0、AudioShutdown3帧clean，`reload-trace-status.json`核六历史覆盖目标与生产SHA一致、1094来源和4188资源stat零漂移，无Godot进程/锁。正式源码、正式测试路径、F5默认及全部用户程序服务未改。SPACE、完整三轮、扩大覆盖、严格60和实际人工F5仍未完成。

## 2026-10-27 既有上传与存在性成本离线复核

本轮没有运行Godot或改变生产算法。`analyze_upload_exists_cost.py` / `upload-exists-cost-summary.json`只重读三份既有C2分段结果，记录原文件SHA，按纹理审计实际使用的 `PerfBuckets._trace_frame_index` 关联墙钟时间线的 `frame`，没有把它直接当 `engine_frame`。三轮引擎帧偏移分别498/476/465；路径最大值不在采样窗口内的8/11/12项保持未关联，不移入正式采样统计。

原算法submit-profile的9599us单次ImageTexture创建已明确落在trace762/engine1260、bench_t=8.233秒，属于20.229ms慢间隔，且当间隔上传次数1、上传桶9599us逐值相等；对应2012×2012、mip_bytes2701792的09307bc26bfb资源。它并非只发生在初始加载期。但同轮4012×4012资源的5134us创建落在14.564ms非慢间隔，容器候选同规格6437us创建落在15.264ms非慢间隔，说明不能仅按纹理大小或单次API长短判定慢帧，也不能把API墙钟当GPU执行时间或驱动归因。

三份时间线上传间隔分别482/472/491个，其中单次上传346/341/355个；上传桶中位944.5/929.5/954us、p95为2264/2161/2221us。这里是每间隔聚合桶，双上传间隔不能解释成单次调用分布。原算法六个慢间隔中，上传桶9599/886/2949/0/2541/3548us；exists桶0/1207/1/5/2/0us，不能只归于上传，也不将父子桶叠加或减去某桶后假设帧率已通过。三个算法的不同轨迹分别保留，不把累计成本差当因果收益。

源码复核确认CellStream已有跨流实例的纯字符串正缓存 `_known_resources`，命中后短路不再调用ResourceLoader.exists；首次成功后登记缓存。旧exists桶包含该缓存查询与首次API调用，而且每间隔可有多次，成功请求事件数也不是缓存未命中数。三轮>=500us的exists间隔34/40/39个，现有数据不能给出每个昂贵首次调用的身份或将其归为磁盘I/O。重复加一个同义缓存不是新修复。图片worker仍执行存在性、加载前后SHA、尺寸/格式/mip/字节数核验；实际上传保持原预算，不能通过去掉其中检查来省成本。

辅助查阅了[Godot上游ResourceLoader实现](https://github.com/godotengine/godot/blob/master/core/io/resource_loader.cpp)：存在性判断涉及缓存、路径重映射和格式加载器，并非可普遍替换为原路径FileAccess存在检查；type_hint也不等于跳过路径重映射。该master文本不是本机4.7.2 Steam提交的二进制实现证明，不用它归因本次调用内部的耗时。

下一次若需运行，问题限定在 `exists-cost-question.json`：原算法一次原负载60秒C2，只给实际发生的首次exists调用记录有界纯值身份/起止时钟，64条>=250us事件与固定命中/未命中/丢弃计数，不预扫、增请求、换API或改变失败语义。先标准focused/all，内部诊断只在真实C2开；不重跑追绿。只有在保持缺失、重映射、摘要和加载错误语义的前提下，才能据此提出独立成本削减候选。本轮仍无可采用生产修复，旧严格60与输入失败、人工F5待验均保持。

## 2026-10-27 首次存在性检查固定单轮诊断

上述问题已按限定完成，不再重复原计划。`prepare_exists_cost.py` / `exists-cost-overlay.json`只覆盖Shadow的CellStream及C2结果出口；不使用pure或visible-reserve候选。正式算法的正缓存短路、首次ResourceLoader.exists调用和随后原登记/失败/加载路径全部保留。采样仅在bench_t达到3秒后开启，结果收尾关闭；每个实际首次API调用单独记起止ticks，慢于等于250us才保存纯值路径/帧，最多64条。没有预扫目录、额外查询、Resource持有或队列/回收/上传改动。标准focused/all未开启内部采样旗，均wrapper0，LifecycleGauntlet93/0；AudioShutdown均11帧clean，无ObjectDB/resource残留。

固定一次原60秒C2结果 `tokyo_volume_c2_20261026_212857.txt`：墙钟9599样本10慢帧，max18.884ms，strict60失败、wrapper1；显示9600帧hidden/uncovered/unqualified/budget全0，AudioShutdown8帧clean。原48演员目标、24km、初始33飞机/12地面/6海军、8/8巡检、模拟divisor1/assigned0及原正式渲染保持。该轮是带诊断的成本观测，不作为无探针帧率或输入到位验收，不与前轮慢帧数量直接归因比较。

`analyze_exists_cost.py` / `exists-cost-summary.json`：正缓存命中783次、实际首次API调用118次，总首次API墙钟45801us、最大846us，平均388.14us；100次达到250us记录阈值，保存前64次、丢弃36次，按预定上限饱和后没有扩大重跑。64个记录是64条不同的m20/assets原生.res路径，结果均true，覆盖bench_t5.683–12.900秒。保存的慢调用中位388us仅属于这个有界前缀，不能充当全部118次分布。所有64次均按起止ticks完整包含于原墙钟区间；trace编号差0，记录时的engine_frame比对应墙钟区间结束帧小1，不能按相同引擎帧硬拼。

例如trace427的18.279ms慢间隔包含3次已保存首次API调用、合计1029us，原exists聚合桶1063us；trace1208的17.904ms包含4次合计1408us、桶1447us，另叠加855us纹理上传。桶与保存调用差额还可能包括低于阈值调用、缓存查询与诊断记账，不能全部称为探针开销。也有多个慢间隔exists桶为0，因而该API只是部分重叠成本，不足以单独解释全部慢帧。API墙钟仍不能分解为磁盘I/O、锁等待或CPU执行，未据此归因驱动/服务或替换检查。

本次已经证实昂贵部分确实包含首次调用，现有正缓存发挥作用；没有得到可等价采用的独立代码削减。后续优先只读核对现有系统采样工具及时间桥，限定是否能用已有授权的CPU/文件I/O采样区分这些短调用内的执行与等待，再决定一次有界联合诊断；不继续扩大此事件列表，也不把检查搬到加载期、改为FileAccess存在即放行或去掉摘要。旧CPU/GPU采样脚本使用历史checkout、地图及预算参数，只能参考记录所有权/清理方法，不能直接执行其旧负载。

正常Shadow同步已撤去覆盖，恢复focused0、AudioShutdown9帧clean。`exists-cost-status.json`核七个历史覆盖目标（新增tokyo_cell_stream）与生产SHA全部相同，1094源码及4188资源stat零漂移，无Godot进程或锁。生产源码、正式测试路径、F5默认及全部用户程序服务未改。当前候选SPACE、三轮输入、扩大覆盖、严格60和人工F5均仍未完成。

## 2026-10-27 CPU/文件事件工具与时钟自检准备

本轮先只读确认三方协调未变，1094源码/4188资源stat无漂移、无bench锁。Windows自带WPR为10.0.26100，CPU、FileIO及独立instancename可用，默认记录状态为空。xperf可用；受限会话的wpaexporter帮助因注册表权限失败，未据此修改注册表或关闭系统限制，后续可用xperf读取事件。

`cpu-fileio-builtins.wprp`是只导出的本机CPU+FileIO模板，系统/事件缓冲配置为3126/332MiB，没有启动这个大模板。根据本机已识别的关键词生成 `exists-cpu-fileio.wprp`，单系统收集器256KiB×512=128MiB，保留CPU采样、上下文切换、ReadyThread和文件事件/文件初始化，不含GPU。`wpr -profiledetails`成功确认配置；这不等于实际记录已经成功。

`smoke_exists_trace.ps1`只做三次独有临时marker的QPC前后夹逼，验证FileCreate能否用于细粒度时间关联；不启动Godot。所有start/status/stop/cancel均带随机独立实例名，不停止其他记录或用户程序服务。普通执行令牌尝试启动失败，错误0xc5585011（无法启用系统性能采样策略），`exists-etw-smoke/result.json`记录ETL字节0、最终自身状态未记录，未取得CPU/文件事件证据。工具层的执行提升不等于Windows管理员令牌。

依据用户已有管理员采样授权，随后发起一次标准RunAs提升，助手增加RunAsAdministrator前置并使用新输出目录，保留第一次失败证据。截至本节落盘，启动会话45586仍未返回，已识别本聊天启动器PID6856，观察到consent进程47744，尚无 `exists-etw-smoke-admin/result.json`；没有发起第二个提升请求。`exists-etw-preflight-status.json`记录待处理状态。此时需要处理Windows系统管理员确认，属于实际操作系统授权界面，不能用已有聊天授权代替管理员令牌；不要重复询问聊天授权，也不要自动再次弹出RunAs。

下轮先检查现有助手结果/启动器是否完成；提升界面未处理前不启动Godot或性能测试。成功后先核命名会话已停止、事件丢失与三个marker时间夹逼精度，再决定是否可用于250–846us调用的联合归因；不足以对齐就保留“不确定”，不直接归因驱动、文件系统或服务。本轮没有游戏运行、生产修改或新的帧率/退出验收，源码及资源收尾核验仍零漂移。

### 2026-10-27 管理员启动等待状态纠正

用户反馈未见管理员窗口后复核：原启动会话 45586 已返回 exit 0 / helper_pid=18764，PID 文件于 08:41:01 写入。原 launcher 6856、曾观察的 consent 47744 及采样助手 18764 当前均未检出。不能再沿用“仍待管理员确认”的状态，也不能从此前会话未返回推定确认窗口一直存在；此前阻塞位置未取得调用栈，未证明具体原因。

`tmp/perf-resume-20261027/exists-etw-smoke-admin/result.json` 表明 start/active/stop/final_status 均 0、error=null，三枚 marker 已写入，ETL 73924608 字节。自有实例 AGLExists360fd8bb2da9417089e4f3fa87f2b433 的最终日志为 WPR is not recording。xperf tracestats 显示 PerfCounter 时钟、当地 08:41:02.4130587 起约 1.9999472 秒，Lost Buffers/Events 均 0。该结果只验证采样自检完成，尚未验证 marker 时间夹逼精度，不是游戏性能证据。

本次未重发 RunAs、未启动 Godot、未终止任何用户程序或服务；更新跟进状态，下一步分析现有 ETL 的 marker 对齐，禁止继续等待已结束的启动会话。

### 2026-10-27 既有 ETL 三枚 marker 的离线时钟夹逼

只读协调核对无新占用，1094 源码 SHA 与 4188 资源 stat 零漂移，无 bench 锁或 Godot 进程。本轮只导出并分析既有 smoke.etl，没有新采样、RunAs 或游戏运行。`analyze_smoke_clock.py` / `smoke-clock-summary.json` 保存可复算结果。

xperf 导出的三条 FileIoCreate 均匹配助手 PID18764/TID45452 和独有路径，ETL 相对时间为 205250/520639/833190us。QPC 构造调用夹逼宽度分别 176.3/228.6/249.2us；为整数 CSV 时间各留正负 1us 后，共同 offset 区间为 [4255530233931,4255530235714] 个 QPC tick（10MHz），宽 178.3us。三条事件支持固定偏移的一致性，但不能把该区间中点称为精确锚点，也没有测量长时间漂移。

现有夹逼对于 250–846us 调用的执行/等待精确划分仍不充分，且这里只桥接 PowerShell 助手 QPC，尚未桥接 Godot Time.get_ticks_usec。下一步先离线读取现有 ETL 原始时间戳/头部，核 QPC 映射，再设计游戏时钟桥；不因已有 UTC 起点或三 marker 匹配就直接启动联合诊断。

xperf 返回 0，但有三条 Invalid Event 解码警告（其中两条进入 CSV InvalidEvent，另条在导出器报告）；Lost Buffers/Events 为零不能扩大为所有事件解码完好。三 marker 本身完整。分析首次按 UTF-8、随后本机码页读大 CSV 均失败，改用 Latin-1 无损映射字节且只比较 ASCII 事件/路径/数字，未改 ETL 或放宽匹配条件。生产、正式测试路径、F5 默认与用户程序服务均未改，本轮不是游戏性能/退出验收。

### 2026-10-27 ETL 原始 QPC 离线核验

`read_smoke_qpc.cpp` 仅使用 OpenTrace/ProcessTrace/CloseTrace 读取现有 ETL，以 PROCESS_TRACE_MODE_RAW_TIMESTAMP 保留原时钟。语义依据 [Microsoft EVENT_TRACE_LOGFILEW](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/ns-evntrace-event_trace_logfilew)，结构由本机 SDK10.0.26100 编译。初次编译缺 UTF-8 选项导致中文注释解析失败，未执行程序；补 /utf-8 后编译通过，无生产改动。

ETL 头为 QPC clock_type1、frequency10000000，丢事件/缓冲均0。离线消费519546事件，ProcessTrace/CloseTrace均0；限定 FileIo provider、opcode64、PID18764/TID45452、marker文件名得到恰好3条。`analyze_smoke_raw_qpc.py` / `smoke-raw-qpc-summary.json`核原始值4255532287195、4255535441082、4255538566594均在原QPC夹逼内；分别距调用开始75.4/113.8/121.1us，距调用结束100.9/114.8/128.1us。减去xperf相对整数us后偏移仅差3tick=0.3us，符合整数导出量化。后续可直接读原始QPC，不必把178.3us区间中点当精确时钟。

这只解决ETL与助手QPC的映射，Godot的ticks起点仍未测得。既有xperf三条解码警告保留，原生回调成功不等于所有载荷解码正确；回调数与xperf合成行数也不直接比较。

`exists-joint-clock-design.json`预先列出下一步有界时钟桥方案：测量窗前后各3枚独有文件marker，以游戏ticks夹同步open，并用原始Create/成功OpEnd生命周期约束offset；需先核实际事件结构及IRP配对，预定最大50us区间，不合格则报告不确定，不追跑取窄。执行/就绪/阻塞仅报告含时间不确定性的区间，不把缺CPU采样当零执行。该方案尚未实现或启动，未新建采样/RunAs/Godot，未改帧率/输入/资源门或负载。三方协调无新占用，1094源码/4188资源stat无漂移，无锁；当前严格60和人工验收仍独立未完成。

### 2026-10-27 Create/OpEnd 配对与隔离游戏时钟标记校验

`read_smoke_operations-tdh.cpp`最初用TDH读取本机经典事件元数据，GetEventInformation/GetProperty返回1168，退出4；失败输出保留在 `exists-etw-smoke-admin/tdh-failed-*`，没有改注册表或重采样。随后 `read_smoke_operations.cpp` 按 [Microsoft PerfView 的 FileIOCreate/OpEnd 实现](https://raw.githubusercontent.com/microsoft/perfview/main/src/TraceEvent/Parsers/KernelTraceEventParser.cs)使用限定 x64/经典provider/版本/长度的显式布局；这不是TDH元数据通过。IRP串接意义依据 [Microsoft FileIo_OpEnd](https://learn.microsoft.com/en-us/windows/win32/etw/fileio-opend)。

三次Create→OpEnd均按活动IRP生命周期配对后立即移除，start/end各3、无剩余、状态0/ExtraInfo2，主线程身份均一致，全部内含于助手同步调用QPC夹逼。`analyze_smoke_operations.py`逐项核xperf既有CSV的IRP、选项、共享标志、完成状态及时间；原始持续65.4/74.8/88.7us，对应xperf整数65/75/89us。它们是文件操作墙钟，不是磁盘时间。把Create与OpEnd共同用于助手时钟约束仍得110.9us范围，不达预定50us门；不得放宽门或据此声称Godot桥已合格。

`prepare_joint_clock.py`生成的三个覆盖文件仅存tmp：在原exists-cost诊断副本中增加固定时钟marker helper，C2 _ready开头3枚、结束摘要采样后3枚；原exists首次调用、64条/250us门、队列/摘要/上传/负载不变。仅AGL_PERF_JOINT_CLOCK=1启用真实C2标记，时钟文件限本次tmp子目录、拒绝已有文件及非法位置、同步open后立即取ticks并close，无跨帧文件持有。临时focused断言验证3枚、单调ticks、PID、空文件回读、重复与非法位置拒绝，正式测试文件未改。

官方wrapper稳定宿主Shadow focused0、默认all0，JointClockChecks各fail0/markers3，LifecycleGauntlet93/0，AudioShutdown13/2帧clean，无ObjectDB/resource残留。随后正常Shadow撤覆盖恢复focused0、Audio14帧clean；`joint-clock-checks-summary.json`核7个历史覆盖目标SHA与生产一致，1094源码/4188资源stat零漂移，宿主只读核无Godot进程、无锁。

本轮只在普通测试中验证标记代码，没有同步ETW或代表性Visual C2，50us游戏时钟门仍未测。退出证据仅属于这次focused/all/恢复；慢帧、严格60、显示完整性和输入验收没有新增结论。没有新RunAs、没有生产/F5默认修改，也未停止用户程序服务。下一步先准备并审查一次有界联合采样的控制器与通用解码，禁止照旧启动已结束会话或重复自检。

### 2026-10-27 联合采样控制器静态审查，尚未启动

恢复时三方协调无新占用，1094源码摘要与4188资源大小/mtime仍零漂移。本轮发现原128MiB Memory配置为循环记录，不能仅凭lost=0保证保存测量窗前marker及完整60秒；[Microsoft WPR说明](https://devblogs.microsoft.com/performance-diagnostics/wpr-start-and-stop-commands/)区分内存循环与文件记录。因此仅在tmp新增 `exists-cpu-fileio-file.wprp`，保持同一256KiB×512缓冲与事件/栈集合，改File模式；WPR profiledetails退出0，未start。文件记录额外写盘会影响采样负载，只能用于诊断，不能与无探针慢帧数量比较。128MiB是配置缓冲，不是完整进程内存上限。

`joint_exists_sampler.ps1`与`joint_exists_controller.ps1`目前只是未执行草稿：采样助手仅操纵唯一命名实例；普通令牌控制器负责官方wrapper，拒绝管理员令牌运行Godot。双方用PID/启动时刻校验、30秒有界握手、无覆盖原子JSON发布及一次性C2尝试标记，脚本中没有RunAs或提权启动器。助手循环预定180秒、500ms检查4GiB软触发、起始12GiB/剩余8GiB磁盘余量；停止合并可能越过软触发值，不能称硬文件上限。异常只回收自有WPR子进程/实例，不操作用户程序服务。缺失或提前结束的采样结果不能算采集通过；C2退出后安排普通Shadow恢复与漂移/锁核验。两份UTF-8 BOM脚本仅语法解析通过，尚未实际验证异常退出链，不能据此宣布控制器验收完成。

`prepare_joint_decoder.py`生成参数化 `read_joint_file_operations.cpp`，本地SDK编译退出0，未运行。它只解码六枚marker的Create/OpEnd：使用该轮实际PID/TID及唯一目录，限定经典x64版本3与长度，按活动IRP生命周期配对，拒绝重复、失败、未完成及丢失记录。它不是CPU/就绪/阻塞或全部文件操作的通用分析器；相关版本结构与区间算法仍待实现和核验。50us游戏时钟门仍未测，不重跑旧smoke或标记checks以追精度。

`joint-controller-review.json`明确ready_for_capture=false，状态 `joint_controller_static_reviewed_semantic_decoder_pending_no_capture`。下一步先完成调度事件离线解码及控制器异常收尾审查、七覆盖目标恢复核验；当前没有可执行的提权启动编排，不得再次RunAs或复活45586。本轮未启动Godot/系统采样，未产生新慢帧、严格60、显示完整性或退出验收。宿主只读进程检查无Godot/wpr/xperf/consent，无bench锁或联合C2尝试文件；生产、正式路径、F5默认与用户服务均未改。

### 2026-10-27 调度事件离线核验与不确定区间算法

本轮三方只读协调未变，1094源码/4188资源stat零漂移，无bench锁。`read_thread_schedule.cpp`仅消费既有smoke.etl，不采样、不重跑旧marker配对。SDK编译0，OpenTrace/ProcessTrace/CloseTrace正常，写出助手TID45452相关194条原始记录，截断/畸形/丢失0。实际全局CSwitch为版本5/28字节/flags848，共50361条；ReadyThread为版本2/8字节/flags848，共27387条。不能直接把较旧MOF的版本2/24字节当成本机完整结构。

依据 [Microsoft CSwitch说明](https://learn.microsoft.com/en-us/windows/win32/etw/cswitch)与[PerfView调度字段定义](https://raw.githubusercontent.com/microsoft/perfview/main/src/TraceEvent/Parsers/KernelTraceEventParser.cs)，`analyze_thread_schedule.py`逐条对照既有xperf CSV：该助手130条CSwitch的新旧TID、优先级、旧状态/等待原因、CPU以及63条ReadyThread的被唤醒TID、调整信息、CPU/InDPC均相符，时刻落已核QPC/CSV整数舍入界；没有重新估计marker时钟桥。版本5打包的wait-mode字节及附加尾部没有解码，不声称全结构已验证。原始调度头PID/TID可为0xffffffff，不能拿它当目标身份；被唤醒线程必须取载荷TID，不能混同唤醒者。当前线程归属另与CSV的18764核对，未来游戏仍需独立生命周期核验。

`thread-schedule-summary.json`的助手观测区间由192段构成，无状态矛盾：scheduled263981、ready3938、waiting10701239个10MHz tick，总和等于两端差。这里只验证调度时间线，不是游戏或exists成本。删除唤醒、删除切出及未知版本三个反例均被拒绝。调度驻留包含中断/DPC占用的可能性，现有profile没有专用DPC/ISR事件，因此不能命名为净CPU执行时间或用它归因驱动；[Microsoft CPU分析说明](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/cpu-analysis)也分别分析调度、采样与DPC/ISR。

`schedule_interval_bounds.py`以预先有界的常量时钟偏移及端点量化误差，求各状态重叠时长的保守上下界；724组整数偏移/端点组合穷举符合界限，时间线缺口、越界、未知状态三个反例拒绝。各状态边际上界不能相加当实际总耗时。该算法仍假设已验证的同源单调时钟/漂移条件，不能替代尚未实测的50us Godot桥。

控制器草稿补入七历史覆盖目标的恢复SHA核验与失败退出，语法解析0，仍未执行，异常收尾未获运行验证。状态更新为 `offline_schedule_crosschecked_capture_gates_pending`，ready_for_capture=false：下一步补资源文件操作身份/生命周期与联合分析门，再完成异常控制器与可用启动编排；禁止再次RunAs、旧会话轮询或重复已完成自检。本轮宿主无Godot/wpr/xperf/consent，生产、F5默认、用户程序服务未改。没有新的慢帧/严格60/显示完整性/退出验收，无用户操作。

### 2026-10-27 自有助手等待边界与文件操作字段核验

本轮只读协调三方未变，1094源码/4188资源stat零漂移，无锁。审查新采样草稿发现：即使自有WPR子进程已经退出，其后代若继承stdout/stderr，ReadToEndAsync.Result仍可能无界等待。`joint_exists_sampler.ps1`现对子进程超时后的退出及输出排空分别设5秒边界，并在finally关闭读取端及释放进程对象。只针对本脚本新建的进程；这个发现没有旧45586调用栈支持，不是其历史阻塞原因证明。

`check_owned_process.ps1`从实际草稿AST只提取Own-Wpr函数，将可执行文件指向完全不调用WPR/Godot/服务的 `fake_owned_process.exe`。成功、退出17、挂起、父进程退出而测试子进程持有管道四案均按预期返回/报错，用时197/27/1024/5044ms；自有假程序最终全部退出。`owned-process-checks.json`记录四案通过。没有执行采样脚本主体或移除管理员门，没有start ETW、RunAs或Godot。这验证子调用等待，不代表整套采样/控制器异常恢复已验收。

`read_file_events.cpp`只读旧smoke.etl；初稿未筛名称rundown，100000条上限饱和、丢63674、退出4，`file-events.jsonl`与 `read_file_events_unfiltered.cpp`保留，不能用于完整配对。随后仅导出操作opcode>=64，仍用相同100000上限，得到92940条、丢0、退出0；这是修正离线导出范围，没有重新录制或扩大cap。名称rundown被省略后，旧句柄路径必须保持未知。

依据[Microsoft PerfView FileIO字段实现](https://raw.githubusercontent.com/microsoft/perfview/main/src/TraceEvent/Parsers/KernelTraceEventParser.cs)，`analyze_file_operations.py`对已知版本3/x64载荷解码并用活动IRP配对，FileObject每次Create增加代次、Close失效。独立对xperf CSV核助手184次操作开始及184次结束：Create28、Cleanup28、Close19、Read55、Write7、QueryInfo39、FSCTL8；IRP、FileObject、CPU、时刻、选项/共享、读写范围/flags、查询类别、完成状态与持续逐值一致。首次把CSV枚举文本当数字导致ValueError，修正为[官方FILE_INFORMATION_CLASS枚举](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ne-wdm-_file_information_class)和本机SDK winioctl.h的控制码映射，保留相同断言而非跳过字段。

`file-operation-summary.json`保留175次状态0、7次0xc0000011、2次0xc0000010；失败状态没有当成功存在性查询。助手184对无缺结束或已知IRP冲突，但46次路径未解析，未支持opcode与全局3266次无已知开始的结束均明确保留。不能把零截断说成全部文件身份/生命周期已完整，也不能把文件操作持续当磁盘时间。设备路径规范化和线程生命周期仍待补足；这些仍是助手自检数据，不是Godot或ResourceLoader成本证据。

状态 `offline_file_fields_and_owned_waits_checked_capture_pending`，ready_for_capture=false。已完成的调度/marker/本轮等待检查不重复；下一步仅补必要路径与身份门及整体控制器中止/恢复编排。50us游戏桥、原负载单轮联合C2仍未启动，原全部性能/输入验收结论保持。生产、正式测试路径、F5默认及所有用户程序服务未改。


### 2026-10-27 路径身份门与控制器中止收尾反例

本轮三方只读协调未变，1094源码SHA/4188资源stat零漂移，无bench锁或联合尝试文件。只处理tmp工具与既有导出；未启动Godot、WPR、提权助手或任何服务操作。

`check_joint_identity.py`从既有xperf CSV提取录制时的五个本地盘VolumeMapping，按最长完整设备目录前缀转换，正确处理CSV双反斜杠文本转义。28条助手Create原始NT路径与独立CSV路径逐条一致。只接受当前所需ASCII本地盘路径；未知卷、冲突映射、父目录段拒绝。不查询当前盘符替代历史映射，不把UNC、重解析点或Unicode名称推定为同一文件；此前46条未解析路径仍未知。

线程原始记录仅有PID18764/TID45452的opcode4 DCEnd。按[Microsoft线程生命周期说明](https://learn.microsoft.com/en-us/windows/win32/etw/thread-v2-typegroup1)，DCEnd是记录结束时仍运行线程的枚举，不是线程退出。新的生命周期门明确拒绝这份助手记录作为完整Start到测量窗的身份依据；保留既有字段/调度自检，不提升为游戏成本。未来游戏必须有独立解码的ThreadStart在测量窗前、End或DCEnd在窗后，且无TID复用冲突。三个生命周期反例（窗内结束、TID复用、缺收尾）及三个路径反例均拒绝；这些门控反例使用已解码合成记录，未观测的原始Start载荷版本不算验证通过。证据 `joint-identity-checks.json`。

控制器草稿原finally中的一个异常可能跳过后续恢复和结果落盘。`joint_exists_controller.ps1`新增独立阶段异常隔离，依次尝试stop请求、sampler结果、官方恢复、漂移、七目标摘要、锁检查、最终发布；异常逐阶段保留并拒绝验收，落盘失败另向stderr输出完整结果。sampler结果等待由75秒改为180秒上限，以容纳既有有界stop/cancel/status链；超时仍拒绝，不调用全局WPR停止。该时间不是游戏响应或性能门限。

`check_joint_cleanup.ps1`仅AST提取真实编排函数，以内存动作验证正常/七阶段各自抛错/全部抛错共9案，全部按顺序执行后续步骤。`check_joint_finally.ps1`提取实际finally与最终拒绝谓词，仅将wrapper、freeze和hash边界替换为惰性假函数；正常、未启动、sampler身份错、stop文件冲突、恢复抛错/86、漂移检查抛错、摘要读取失败/不等、锁存在、最终结果文件冲突共11案全部通过。核实际七目标循环，已有冲突文件保持原内容；没有执行控制器启动主体、采样或引擎。证据 `joint-cleanup-checks.json`、`joint-finally-checks.json`。首次测试脚本无BOM导致函数未识别，修正为UTF8 BOM；首次hash替身未正确截住调用而10案失败，`joint-finally-checks-mock-failed.json/.log`保留，随后改为两个明确hash边界替换，断言未削弱。一次临时修改命令Python引号错误未更改源码，后续用补丁修复。所有失败属于工具测试构造，不是游戏失败。

这证明收尾编排在假依赖故障下继续尝试及拒绝错误结果；不证明真实WPR停止/merge、180秒等待上限或实际Shadow恢复已联合执行。生产/正式路径/F5默认/用户程序服务均未改。状态 `path_identity_and_cleanup_faults_checked_joint_analysis_pending`，ready_for_capture=false。下一步将现有解码/时钟/身份/区间组件整合为单一离线分析入口，完成必要握手和启动边界审查；不再重复已完成自检，不RunAs、不复活45586、不盲跑一次C2。50us游戏桥及所有当前游戏验收仍未新增证据，无用户操作。


### 2026-10-27 单一离线联合分析入口与条件性时钟边界

本轮先只读核三方最新turn仍未新增占用、1094源码/4188资源stat零漂移和锁不存在。新增 `analyze_joint_evidence.py` 仅在tmp读取游戏摘要、原始FileIo/线程JSONL、录制时卷映射及实际Shadow根路径；不启动解码器、采样或Godot。入口复用已核的文件载荷解码、活动IRP/FileObject代次、调度载荷/区间、路径及生命周期门；从一般文件台账按六个完整marker路径匹配Create/OpEnd，因此不依赖把旧助手PID或独立marker序号强套到游戏。

入口检查原始导出头尾/计数/时序/丢失、6枚成功同步创建/主线程身份、原64条及250us门、首尾兼容原点区间<=50us、生命周期、调度歧义、原墙钟frame包含关系。每个调用保留原始路径/时刻，输出调度驻留、ready、waiting的条件性上下界及可能重叠文件操作；只在所有允许原点和端点误差下都包含时标 guaranteed_contained，失败NTSTATUS和未知路径不删。文件路径相同与操作重叠不等因果，scheduled不等净CPU，文件持续不等物理磁盘时间；边际上界不可求和。

明确补上认识边界：首尾六个marker的原点区间相交，只证明与恒定原点模型相容，不能单独证明整个测量窗没有非线性漂移。因此即使入口各门通过，状态仍为conditional_joint_intervals_only且attribution_qualified=false；实际Steam Godot时钟实现依据、ThreadStart实际载荷和同一ETL导出来源绑定仍待完成，未添加绕过开关。输入文件SHA留作追溯，不能代替其原始ETL来源证明。没有使用UTC或原点中点假精确。

`check_joint_analysis.py`用合成原始字节贯通六marker/文件IRP/调度/生命周期/墙钟和记录饱和前缀，验证失败状态0xc0000034仍保留、旧句柄路径仍未知，且结果不能提升为归因。十个反例（事件丢失、导出截断、改cap、缺marker、marker失败、缺ThreadStart、未知调度布局、错wall frame、原点宽于50us、首尾不相容）均拒绝。首次宽区间反例提前撞到marker排序门，`joint-analysis-checks-wide-premature-rejection.json`保留；修正合成夹逼宽度并断言确实到达50us门后通过，未改任何实际门限。CLI对 `joint-analysis-synthetic-v2/manifest.json` 退出0并输出conditional状态、attribution_qualified=false，`joint-analysis-checks.json`记录结果。这里是新入口的整合测试，不重跑旧smoke或游戏，也不称原始ThreadStart已验证。

状态 `joint_offline_entry_checked_conditional_clock_model_no_capture`，ready_for_capture=false。后续只补同一ETL来源绑定、实际目标进程有界导出（现有全系统100000上限只验证2秒smoke，不能假定覆盖60秒）、实际游戏时钟依据与ThreadStart布局，以及必要启动握手；不重复完成的自检，不再次RunAs、旧会话轮询或盲跑C2。收尾宿主无Godot/wpr/xperf/consent/fake，锁与联合尝试文件不存在；生产/F5默认/正式测试路径/所有用户程序服务未改，没有新慢帧/严格60/显示完整性/退出或输入验收，无用户操作。


### 2026-10-27 目标进程离线导出与同源ETL收据门

本轮只读核三方未新增占用、1094源码/4188资源stat零漂移和无锁。`read_process_file_events.cpp`由原只读导出器派生，只缩小离线输出，不改ETW录制事件或采样预算：保存目标PID的操作开始，以及活动IRP的对应结束；完成者PID可不同，不能按结束头PID简单过滤。若外部新开始复用目标活动IRP，保留冲突并拒绝。Read/Write的IRP偏移8与其他开始偏移0分别处理。输出与活动表仍100000上限，不扩大cap，未知目标操作保留，不补猜其语义。

SDK编译0。`check_process_file_selection.cpp`只调用实际选择函数，五案验证目标开始、异进程完成、无开始结束/无关开始、外部复用冲突和Read偏移；没有OpenTrace/WPR/Godot。随后仅对已有smoke.etl做一次新选择器离线导出，得到192开始/192结束、384条、drop/malformed/collision/active_at_end均0。与此前完整92940条操作导出逐事件比较，无改写/新增事件；目标开始全部保留，省略9条没有所选开始的完成，不推定它们必然属于记录前操作或游戏。目标线程45452/40696/63292开始分别188/2/2；包含此前未解码的84/86，不能把新导出完整消费说成全部语义已解码。`process-export-checks.json`留档，仅证明新过滤器在2秒旧ETL上的行为，不能保证未来60秒目标输出不饱和。

`export_joint_raw.py`只允许已有ETL与两种固定只读解码器，子调用120秒有界、隐藏窗口、输出目录拒绝覆盖，记录ETL前后stat/SHA、实际工具SHA、输出SHA/退出码/错误。`process-export-smoke/receipt.json`确认本次原ETL仍73924608字节，SHA652746f6e4c1e251ca4d11c717339d2eb0204b00e46054829e305d09fbe93623，前后相同，解码退出0。没有重新录制，也未重导已完成的调度数据。

`joint_export_provenance.py`接入联合CLI：文件与调度导出必须分别具备正确类型、成功状态、相同原ETL绝对路径/SHA、当前原ETL/输出/解码器摘要匹配，最终选择PID/TID须与实际marker一致；缺收据不会继续给出联合区间。八个惰性合成反例验证缺收据、导出途中源改变、输出摘要错、类型错、目标错、工具摘要错、导出失败和不同ETL路径（即使同字节）均拒绝，见 `joint-export-provenance-checks.json`。测试仅使用无执行能力的合成字节；不是两个真实导出的同源证明。此前无收据的联合合成manifest现由CLI退出4并输出inconclusive_rejected，旧conditional结果保留。新门不改变50us或玩法/帧率门限。

同源收据当前只覆盖原始文件/调度导出，录制时卷映射还需自己的来源链；只有一个真实进程导出收据存在，未宣称真实联合绑定。状态 `process_export_and_etl_binding_checked_clock_basis_pending`，ready_for_capture=false。下一步优先核实际Steam Godot4.7.2时钟依据及真实ThreadStart布局，不重复已完成自检/导出；再收束必要卷映射来源与启动握手。禁止再次RunAs、旧45586轮询或盲跑C2。收尾无Godot/wpr/xperf/consent/自有导出或假程序，无锁/联合尝试文件，生产/F5/正式路径/用户程序服务未改；没有新游戏验收，无需用户操作。


### 2026-10-27 已安装引擎时钟与原生ThreadStart只读核验

本轮三方无新占用，1094源码SHA及4188资源stat零漂移，无bench锁。只读已安装Steam可执行文件：180860936字节，SHA256 `12310c74bdda7dcd43f28e971f33047dcecadd436b68169d61ce41009006df38`，ProductVersion 4.7.2.stable.steam；文件内完整提交 `ed1daf0bf001b61586d9930840f2f1394092c079` 位于偏移122072184。没有运行Godot。

`inspect_godot_clock_pe.py`使用PE导入表与异常表定位QPC调用，并只反汇编相关有界函数。初次dumpbin范围参数缺0x导致退出失败；保留空的godot-clock-pe目录，修正参数后v2输出成功。RVA0x15b0读取QPC、减对象0x130起点，以0x138频率进行商/余数整数微秒换算；RVA0xc810初始化序列向相同两成员分别写入QueryPerformanceFrequency/Counter结果。实际指令与[对应提交Windows实现](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/platform/windows/os_windows.cpp)一致；[对应提交Time绑定](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/core/os/time.cpp)直接委托OS时钟。10MHz下公式为usec=floor((QPC-origin)/10)，余数0..9tick，因此既有端点±1us界保守；无需凭首尾marker相交来假设独立时钟漂移。这里函数名由指令和精确提交源码匹配推断，无PDB或可复现构建证明，也未穷举绑定/vtable；实际游戏起点与六marker<=50us仍未测。`godot-clock-basis.json`记录文件/反汇编摘要和边界，未修改联合入口资格门。

`read_thread_lifecycle.cpp`仅对已有smoke.etl做一次新的生命周期类别离线导出，100000原上限不变，SDK编译0，ProcessTrace/CloseTrace0，12747条、丢失/截断/畸形0，原ETL SHA前后相同。`check_native_thread_start.py`将其中234条真实Start的版本3/74字节/flags832、PID偏移0/TID偏移4及原始QPC逐条与既有xperfCSV核对，234条全部一致，未重算marker桥。`native-thread-start-checks.json`仅证明实际Start身份前缀，不声称其余字段已解码或Godot生命周期已验收。未来真实Godot仍须观测Start、窗后End/DCEnd及无TID复用；DCEnd仍是录制末枚举，不是退出。

状态 `installed_clock_and_native_start_inspected_volume_handshake_pending`，ready_for_capture=false。下一步收束录制时卷映射来源和必要启动握手，不重复已完成离线组件/导出，不新增无关门。实际WPR停止/merge和官方Shadow恢复尚未联合执行，无已可执行提权编排；禁止再次RunAs、旧45586轮询或盲跑C2。64条/250us/50us及固定一次原负载联合采样保持。收尾宿主无Godot/wpr/xperf/consent/自有助手，无锁或联合尝试文件；生产/F5/正式路径/所有用户程序服务未改，无新游戏验收或用户操作。


### 2026-10-27 录制时卷映射来源与握手过期竞态

三方只读核对无新占用，1094源码/4188资源stat前后无漂移、无锁。`read_volume_events.cpp`仅离线读取已有smoke.etl的SysConfig opcode35；布局依据[Microsoft PerfView](https://raw.githubusercontent.com/microsoft/perfview/main/src/TraceEvent/Parsers/KernelTraceEventParser.cs)的两段终止UTF16字符串。SDK编译0，经原有120秒有界导出器的新volume_mapping分支一次导出15条，版本0/flags832、全部QPC4255530234693，ProcessTrace/CloseTrace0、丢失/截断/畸形0。`volume-export-smoke/receipt.json`绑定原73924608字节ETL，SHA652746f6e4c1e251ca4d11c717339d2eb0204b00e46054829e305d09fbe93623前后不变；无新录制。

`joint_volume_mapping.py`严格核版本/载荷长度和恰好两个终止串，同源收据核ETL/输出/解码器身份及摘要；拒绝冲突或不同时刻的映射，拒绝映射快照晚于文件事件，不使用当前系统盘符回填。15个原始映射与既有xperfCSV逐值相等，其中只使用5个ASCII本地盘映射，其余10条保留而不用于路径推断。首次比较错误地把相邻反斜杠统一当转义折叠，导致8个非本地/前缀项不等；修正比较器为CSV原值后全等，`volume-csv-initial-failure.json`保留失败。此前5个本地映射没有相邻反斜杠，结果未受影响；这不是扩大UNC或重解析支持。8个反例覆盖未知版本、截断串、冲突、时变、丢失、截断计数、错ETL及快照过晚，均拒绝，见`volume-binding-checks.json`。

联合CLI现要求volume_events及对应同一ETL导出收据，并直接从原始卷事件派生映射，不接受独立手填映射表。旧合成manifest缺新证据时输出inconclusive_rejected，旧条件性结果保留。完整三类实际同源数据仍未形成，不能称真实联合分析已通过。

握手草稿新增实际守卫：sampler在初始、start前及发布ready前检查控制器仍存活、arm年龄0..30秒且没有stop；controller验证ready的完整实例名、owner PID与启动时刻、helper启动时刻和未结束；stop请求同时核owner PID。修补的是检查后WPR准备阶段可能过期/已撤销的窗口，不能绝对消除所有检查后竞态；唯一命名实例及死亡/超时收尾仍保留。`check_joint_handshake.ps1`只提取实际AST守卫函数，13案通过，两个脚本解析0；没有运行采样/控制器主体、没有移除管理员门、没有WPR/Godot/服务操作。此前finally七阶段未修改，不重复已通过检查。

状态`volume_provenance_and_handshake_guards_checked_no_capture`，ready_for_capture=false。下一步只完成必要的惰性启动/中止编排边界审查并明确可用启动路径；没有新的提权启动器，不得再次RunAs或轮询45586，不盲跑C2。固定一次原负载联合采样和64条/250us/50us门不变。收尾宿主无Godot/wpr/xperf/consent/自有助手，无bench锁或联合尝试文件；生产/F5/正式测试路径与用户程序服务均未改，无新游戏验收和用户操作。


### 2026-10-27 启动/中止编排检查与当前执行权限边界

三方无新占用，1094源码及4188资源stat前后零漂移。`check_sampler_orchestration.ps1`提取实际sampler try/catch/finally，外部Own-Wpr、控制器存活和ready后stop注入为惰性边界；不执行采样脚本主体，不移除管理员前置。12案覆盖正常、已占用、start前过期、start失败、active失败、ready前stop、ready文件冲突、错stop owner、owner退出、stop失败、cancel失败和final状态失败。所有案按预期拒绝或完成，失败路径仍尝试自有实例终态，冲突文件保留。只是编排逻辑验证，不是实际WPR停止/merge证据。

测试先因UTF8无BOM在Windows PS5误读中文注释而产生无效ScriptBlock，修正为BOM后，正常案实际发现草稿的UTC/本地时间错误：DateTime.Parse(UTC的o格式)返回本地时间，直接从UtcNow相减不自动按Kind换算，在JST形成负年龄，上一轮新增的未来日期守卫会错误拒绝有效arm。实际sampler已加ToUniversalTime再相减，0..30秒门不变。失败目录及`sampler-startup-initial-failures.json`保留，修复后12案通过；这与旧45586原因无关。

`check_controller_startup.ps1`提取实际controller启动块，仅把原官方wrapper调用替换成惰性函数，8案核wrapper1仍保留、错误实例/owner时刻/helper复用/采样已结束不启动、单次尝试文件冲突不覆盖、wrapper86和无当前结果路径拒绝。仅测试子进程中的临时环境，假日志/一次标记均在独有fixture目录；无真实Godot、WPR、ETL或生产标记。既有finally七阶段未改，不重复旧检查。两脚本当前摘要已更新到审查状态文件。

必要离线准备现已收束；状态`startup_abort_reviewed_waiting_existing_admin_terminal`，ready_for_capture=false。只读宿主令牌确认IsAdministrator=false（检查进程23232）；采样授权仍有效，但当前执行通道不具备管理员令牌，且仍遵守不再RunAs。`joint-launch-handoff.json`列明具体草稿/摘要、同RunId普通controller与管理员sampler顺序、30秒握手及尚未执行的实际验证。需用户提供一个已打开且保持打开的管理员PowerShell窗口后再安排，不独自启动controller或消耗一次C2标记。不新增临时服务、计划任务或其他提权绕行。

本轮无新采样/游戏验收，严格60与人工F5等原状态未变；生产/F5/正式路径/用户程序服务保持。宿主无Godot/wpr/xperf/consent/自有助手，无锁/联合尝试文件。仅本次通知必要窗口操作，后续无变化心跳保持安静，不重复自检、申请授权或提醒。
