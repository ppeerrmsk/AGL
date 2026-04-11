# 更新日志 — 2026-04-11

本次提交累计自 `c783634` (2026-04-10) 以来的所有改动。约 17 个文件，+2200 / -480 行。

## 1. 新敌人机型家族（4 款载人战机 + AI 原型体系）

参照空战文献的"原型 (archetype)"分类，将敌人按行为风格分组：

- **F-86**（Gladiator 入门）— 火箭弹 + 机炮缠斗
- **MiG-23**（Gladiator 综合）— 导弹 + 机炮编队
- **F-100**（Lancer 编队）— 雷达弹打带跑
- **MiG-31**（Lancer 顶级）— 单机超高速 BVR 截击
- **J-7** 截击机改挂 `lancer_combat.tres`，由"早期单机出场"改为"`LATE_GAME_LEVEL(10)` 后变 2-3 架编队"

每个新机型独立配置 AI 参数（aggression / engage_cooldown / engage_duration / skill / composure / focus / self_preservation / situational_awareness），体现「斗士」vs「骑士」vs「顶级 Lancer」的差异。

`CLAUDE.md` 新增 **AI 原型概念**（Gladiator / Lancer / Schemer / Adds / 主力威胁）与**敌人索引表 + 12 步新增清单**，供后续加新敌人时直接走索引而非通读 1450 行 `survivor_mode.gd`。

## 2. Token 烈度预算系统（生存模式刷怪重构）

引入精细烈度控制：

- `TOKEN_COST` / `TOKEN_INSTANCE_CAP` / `TOKEN_BUDGET_BASE/PER_LEVEL/MAX` 控制同屏战斗烈度
- 烈度成本：UAV=1 / F-86=3 / MiG-29=MiG-23=4 / J-7=F-100=5 / Sentinel=6 / MiG-31=8
- 实例硬上限：Sentinel 1 台 / MiG-31 2 台 / F-100 3 台，保证稀有感
- `_pick_enemy_type` 按优先级插入所有新类型判定分支
- UAV/UCAV 改为 1 级起等权重杂鱼（删除 UCAV 解锁曲线）
- 新增 `_recalc_token_usage` / `_can_spawn_type` / `_get_token_budget`
- **远距清理**：超出 `FAR_CLEANUP_DISTANCE=7000px` 的敌机静默移除并释放 Token
- `LATE_GAME_LEVEL=10` 后杂鱼/低级机强制编队生成，不再有"落单 1 架"的尾巴

## 3. 机炮整匣装填系统

替换原有的"持续回弹"为"耗尽 → CD → 整匣补满"模式：

- `Aircraft` 删除 `gun_regen_rate` / `_gun_regen_accum`，新增 `_gun_reload_active` / `_gun_reload_timer` / `gun_reload_duration: float = 25.0`（比导弹的 20s 略久）/ `gun_reload_progress`
- `_update_gun` 重写：装填激活时累计计时器、到时一次性补满，期间 `is_firing = false`
- 升级技能 `gun_regen / 自动装弹机` → `gun_reload / 快速装弹机`，描述改为"机炮装填时间 -15%"，3 层
- HUD GUN 行装填中显示 `GUN  RELOAD %d%%`

## 4. 无制导火箭弹武器系统（F-86 副武器）

- 新增 `RocketParams` Resource 类型，`AircraftParams` 增加 `rocket` 字段
- `Aircraft` 新增 `rockets_remaining` / `_rocket_queue` / `_rocket_burst_cooldown` + 完整 `_update_rocket` / `_launch_rocket` 发射流水
  - 齐射按间隔出膛、机头锥过滤、距离/高度门槛
- `BulletManager.spawn_rocket` 分支：
  - 命中半径 18px（vs 普通子弹 12px）
  - 无伤害衰减
  - 橙红色长尾迹
  - 独立 `ROCKET` 事件标签
  - 不进入 `bullet_dodge_chance` 闪避系统

## 5. 战术激进度系统 + 战斗物理同步重写（v9）

新增 `tactical_aggression: float [0..1]` 作为战斗物理与能量管理的核心参数：

- AI 每帧根据 `effective_skill × aggression` 写入
- `_update_bank` 大角度 G 限制由其插值（1.0 = 解除限制拉结构 G，0.0 = 原 70% 持续 G）
- 新增 `_corner_speed_kmh()`：`V_stall × 1.2 × √G`（最小转弯半径速度点）

**导弹模式能量管理统一到 v9 方案**（玩家与 AI 同源）：

- 未对准 → 角点速度（最小转弯半径）
- 对准且在雷达内 → match speed（保持发射条件）
- 超出雷达 → 巡航
- 距离 > 1.3× 有效射程且 `aggression > 0.6` → 才开加力冲刺

**修复**：

- 新增 `_effective_missile_range_px()` = min(导弹射程, 雷达范围)，修复单位混淆 bug
- 新增"预测式过冲补偿（critical damping）"：按当前转弯率 + 滚回时间估算未来航向扣减，消除反馈环路过冲
- `_angle_diff` 改用 `wrapf` 修复 `fmod` 在负值情况下返回 `|diff| > π` 的角度比较 bug
- 玩家巡航点击移动也走加力冲刺 + 角点速度转弯

## 6. 机炮狗斗 overshoot / dynamic lag 修复

- 新增 `_overshoot_timer` + `OVERSHOOT_DIST_PX=80` + `OVERSHOOT_EXTEND_TIME=1.2`：距离过近时强制沿机头直飞脱离，避免追击/机炮前置点退化为零向量导致的重叠刷伤
- `MIN_GUN_FIRE_DIST_PX=60` 守门，禁止子弹出膛即命中
- 新增 `_choose_dogfight_pursuit_pos`：战术偏好机炮模式的动态六点钟偏移（距离越近 offset 越大，连续插值无粘滞）

## 7. 武器模式切换重写 + 机炮攻击提交

- 新增 `_missile_cannot_hit_but_gun_can()`：统一的回退规则（距离 < 导弹 `min_range + 150m` 滞回，且机炮能打 → 切机炮），AI 与玩家同源
- 新增 `_gun_pass_committed` + `_should_commit_gun_pass` + `_is_gun_pass_finished`：机炮攻击一旦提交就完成整套攻击（飞过目标 `dot < -0.2` 且超出机炮射程）才允许切回导弹，防止装填好的瞬间中途切换断攻击

## 8. 导弹发射 / 齐射大改

- 新增 `missile_auto_fire` 开关（默认开，HUD 战术按钮）
- 玩家战术偏好模式：跳过 `LOCK_STABLE_BUFFER` 1 秒稳定缓冲，只要 `lock_time` 到就开火
- `_fire_multi_lock_salvo` 重写：
  - 返回 bool
  - 允许对同一目标连发（AI 仍 1 枚/目标）
  - 多锁定升级下跳过冷却并对所有锁定目标同时发射
  - 手点 `combat_target` 提到列表最前
  - 锁定框 = 整个雷达锥
- **修复** 齐射 fall-through 到单发路径造成同目标连发浪费的 bug
- `multi_lock` 升级改为一次性（`max_stacks=1`），描述"自动对所有锁定目标同时发射"
- 机炮正在打 `combat_target` 时不再重复发导弹
- 新增 `MSL_BLOCK` / `THREAT` 诊断日志（阻塞原因节流记录 + 威胁态势快照）

## 9. 热诱弹 / 导弹穿透窗口改写

- 单次 flare 释放只诱骗触发它的那一枚导弹（`_release_flares(target_missile)`），解决连射多发全部被同一次 flare 废掉的 bug
- 新增 `missile_phase_timer` + `MISSILE_PHASE_DURATION = 1.0s` 导弹穿透窗口：玩家释放 flare 后 1 秒所有导弹跳过近炸判定，解决"已 jam 的导弹靠惯性直飞穿过慢速玩家"问题（`MissileManager` 侧实现）
- 玩家 flare 正面阈值从 `dot ≤ 0.3` 放宽到 `dot ≤ 0.6`（±53° 外全 100%）
- 生存模式玩家 flare 参数大幅 buff：
  - `base_jam_chance` 55% → 90%
  - `aspect_bonus` 0.2 → 0.3
  - `maneuvering_bonus` 0.15 → 0.25
  - `close_range_penalty` 0.35 → 0.15
- 敌机 flare 全体削弱：整个生命周期只允许释放 1 枚（`max_flares = burst_count = 1`）

## 10. 规避模式重做

- 新增 `set_evasion_mode(enabled)`：开启时自动 `clear_combat_target` + 清空 `target_position`（等同右键"解除任务"）
- 新增桶滚动画：`_evade_roll_phase` / `_EVADE_ROLL_DURATION = 0.45s` / `_EVADE_ROLL_COOLDOWN = 1.2s`，来袭导弹进入 700px 触发一圈滚转，按导弹 instance_id 去重
- 废除 `_evasion_override` 逻辑，改为点击攻击/移动时直接 `evasion_mode = false`
- 机炮闪避率累加规则：基础 + 规避模式 +20% + HIGH 高度 +20%
- **修复** Jinx bug：`AIController._enter_evade` 强制退出编队托管（清 `formation_mode` / `_formation_leader` / `_formation_blend`，`lod_level = 0`），修复 LOD 1 编队托管旁路导致 360°/s 瞬间扭转

## 11. Sentinel 指挥 UAV 护驾系统重写

- `CommanderAura` buff 由"技能 / 冷静"改为"机动 / 速度 / 攻击欲"：
  - aggression +0.35
  - max_g +4 / 结构 G +5
  - roll_rate ×1.8
  - max_speed / cruise ×1.25
  - acceleration ×2.0
  - stall ×0.7
- 只增益小队成员（不再扫全场）；仅招募 UAV / UCAV，上限 `MAX_WINGMEN = 8`；从旧松散 UAV 编队抢人
- 僚机保持 `simple_ai` + 新增 `orbit_squad_leader` 模式：围绕长机 `ORBIT_RADIUS = 400px` 半径公转（按 `squad_index` 错开相位），`ORBIT_TETHER_RADIUS = 550px` 护驾圈内才交战，超出放弃目标
- Sentinel 自身不再扫描 / 指派目标，僚机独立 `enable_combat = true`
- 长机被击坠时僚机 `orbit_squad_leader` 回退为独立 simple AI
- Commander overlay 随 `_destroy_timer` 淡出（不再硬切消失）

## 12. Squad 系统崩溃修复

- `Squad._sync_leader_squad_index`：原长机阵亡僚机晋升时把新长机 `AIController.squad_index` 同步到 0，**修复"追自己尾巴原地自转"死循环**
- 僚机晋升时 `target speed` 限幅到 `_max_speed_at_altitude`，**修复"1.15× 超速在晋升链里累加成 Mach 8+"暴走**
- `AIController._process_squad_follow` 加入 `leader == self` 安全网，强制退出编队托管
- `AIController._disengage`：孤雁长机回 PATROL 并清编队状态
- 长机目标丢失加 1.5s 宽限 + 协同攻击目标超射程加 2.0s 宽限（防单帧抖动触发脱离）
- `BulletManager` 命中判定改用 `source_team` 快照字典，**修复射手被释放时访问 `source.team` 崩溃**

## 13. HUD / UI / Debug 面板

- 状态面板新增 G 力 / 结构极限实时显示
- 机炮行显示 `GUN %d / %d` 或 `GUN RELOAD %d%%`
- 战术按钮栏新增"F 自动发射: 开/关"按钮 + tooltip
- 生存模式接入 `SurvivorDebugSpawn`（F5 刷怪调试面板）
- F9 导出日志时消费事件并自动解除暂停，防止编辑器调试器捕获

## 14. 文档 / 索引重构

- `CLAUDE.md` 从极简入口彻底重写为完整代码地图：
  - **Script Index** 表
  - **敌人索引表**
  - **新增敌人 12 步清单**
  - 架构段落
  - LOD / 编队 / AI 状态机说明
  - 触发短语
- `docs/code-index.md` 大幅扩充 (+454 行) 配合 CLAUDE.md 的细粒度主题索引
- `export_presets.cfg` 导出路径改到 `../export/0411/AGL0411.exe`

---

## 涉及文件总结

**修改主要脚本：**
- `scripts/aircraft.gd`（+923 -～：v9 物理 / 战术激进度 / 火箭弹 / 武器模式切换 / 桶滚 / 机炮装填 / 齐射重写）
- `scripts/ai_controller.gd`（+151 -：编队脱出 / 协同宽限 / Jinx 修复）
- `scripts/bullet_manager.gd`（+103 -：火箭弹 / source_team 快照）
- `scripts/missile_manager.gd`（穿透窗口）
- `scripts/squad.gd`（晋升 squad_index 同步）
- `scripts/aircraft_params.gd`（rocket 字段）
- `scripts/survivor/survivor_mode.gd`（+352 -：Token 预算 / 远距清理 / 新敌人 / 规避接线）
- `scripts/survivor/survivor_data.gd`（+85 -：Token 表 / 新敌人常量 / gun_reload / multi_lock 改一次性）
- `scripts/survivor/survivor_hud.gd`（+49 -：机炮装填 / 自动发射按钮 / G 显示）
- `scripts/survivor/survivor_player.gd`（+4 -：gun_reload 分支）
- `scripts/survivor/commander_aura.gd`（+190 -：护驾 buff / 招募逻辑重写）
- `scripts/survivor/commander_overlay.gd`（淡出动画）

**修改资源：**
- `resources/enemy_interceptor.tres`（J-7 改挂 lancer_combat）

**文档：**
- `CLAUDE.md`（+326 -）
- `docs/code-index.md`（+454 -）
- `docs/survivor-mode.md`（gun_reload 行）

**配置：**
- `export_presets.cfg`（导出路径）
