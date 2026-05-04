# 2026-05-04 — Squad 系统重构（Step 1/2/3/4/5）

## 背景

编队代码经多次增量演化已成屎山。审计发现 7 个核心痛点：状态镜像 / SquadCoordination 直写 Aircraft 私字段 / 9 套生成路径 / orbit_squad_leader 与 SQUAD_FOLLOW 双轨 / 反应延迟常量散落 / 自校正守卫 / Squad 反向调用 AI。

用户决定全套重构 + Squad 升 Resource + 沙盒/生存两个模式都要保留。计划见 `~/.claude/plans/squad-context-starry-llama.md`。

## 已完成

### Step 1 — Squad 升 Resource
- `scripts/squad.gd`: `extends RefCounted` → `extends Resource`
- 新增 `signal leader_changed(new_leader)` —— 长机阵亡晋升时发射
- 新增 `enum EngageMode { FREE = 0, FOLLOW_LEADER = 1 }` + `var engage_mode` 字段（整队共享，原来散在每架 AIController.squad_engage_mode）
- 新增 `const FORMATION_SWITCH_THRESH/REACT_BASE/JITTER_AMP/JITTER_ADD/WINGMAN_ENGAGE_DELAY_MIN/MAX`（从 AIController 迁过来）
- `_sync_leader_squad_index` 暂留（Step 2 起由 SquadFactory 监听 leader_changed 接管，目前仍内部调用）
- `formation` / `base_spacing_m` / `engage_mode` 标 `@export`（以后可 .tres 化阵型预设）

### Step 2 — SquadFactory 统一生成入口
- 新建 `scripts/squad_factory.gd`，3 个核心原语 + 1 个一行版：
  - `create(formation, engage_mode, base_spacing_m)`
  - `register_leader(sq, leader)` —— 写 squad.leader + add_member + AI.squad/squad_index=0
  - `register_wingman(sq, ac, set_state=true)` —— 加入 + AI.squad/squad_index/(可选 _state=SQUAD_FOLLOW)
  - `form_up(leader, wingmen, ...)` —— 已实例化好的成员一次到位
- 9 处 `Squad.new()` 生成路径全部改用 SquadFactory：
  - `main.gd`: `_spawn_friendly_squad` / `_spawn_enemies`
  - `survivor/survivor_spawner.gd`: `_spawn_squad` / `_spawn_commander_squad` / `_spawn_sentinel_escort_uavs`（watchdog 兜底）
  - `survivor/survivor_mode.gd`: `_spawn_starting_wingmen`
  - `survivor/zone_mission.gd`: 3 处（pre-spawn / garrison / elite Sentinel）
  - `aircraft/aircraft_weapons.gd`: 玩家 drone squad
- AceSquad（BOSS 飞机小队）保留原 `Squad.new()`，按计划列为 out-of-scope

### Step 3 — Aircraft 编队接口 + 删状态镜像
- `scripts/aircraft.gd` 删字段 `_formation_blend` / `_formation_jitter_phase`（每帧手动同步的镜像 → 单源）
- 新增 `var _ai_ref: AIController = null`，由 `AIController._ready` 写入
- 新增方法 `set_formation_target(leader, slot_pos, keep_arrival=true)` —— 一次写 `formation_mode/_formation_leader/target_position/keep_target_on_arrival/lod_level=1`
- 新增方法 `clear_formation()` —— 一次写 `formation_mode=false/_formation_leader=null/keep_target_on_arrival=false/ai_override_pursuit=false/lod_level=0`
- 收口的字段写入块（共 ~6 处）：
  - `ai/squad_coordination.gd:process_squad_follow` 进入跟随分支 / 回退到巡逻 / 进 ENGAGE 自由扫描 / 进 ENGAGE 跟随长机交战
  - `ai/missile_evasion.gd:enter_evade`
  - `ai/target_selection.gd:disengage`
  - `ai_controller.gd:1500` kamikaze 拦截
  - `survivor/survivor_hud.gd:1140` 强制回编队命令
  - `survivor/survivor_mode.gd:521` 起始僚机预置编队态
  - `aircraft/aircraft_weapons.gd:1054` drone 预置编队态
- `aircraft_formation.gd` 通过 `ac._ai_ref._formation_blend` / `ac._ai_ref._formation_jitter_phase` 直接读 AI 端权威值（带 null 守护）

### Step 5 — 常量收编 + CLAUDE.md
- 5 个反应延迟常量从 `AIController` 移到 `Squad`（值保持原样：30.0 / 0.3 / 0.5 / 1.0 / 0.3 / 1.5）
- `squad_coordination.gd` 改读 `Squad.FORMATION_*` / `Squad.WINGMAN_ENGAGE_DELAY_*`
- `CLAUDE.md` Script Index：`squad.gd` 改 Resource + 新增 `squad_factory.gd` 行 + Aircraft 加 set_formation_target/clear_formation/_ai_ref 注

### Step 4 — EscortBehavior 谓词收口 + spawn 路径显式 set_state=true
- 新建 `scripts/ai/escort_behavior.gd`：
  - `is_active(ai)` 谓词：把散布 5 处的 `orbit_squad_leader and squad and squad.leader and is_instance_valid(squad.leader) and not squad.leader.is_destroyed` 5 条件 AND 检查收口到一处
  - `cleanup_after_leader_lost(ai)`：长机阵亡时清 orbit 标志 + 还原 buff + 解 squad 引用（原本散在 ai_controller.gd:699-720 ~22 行）
- ai_controller.gd 5 处替换：lifecycle 检测 / shield 系统入口 / orbit 主循环入口 / engage tether 检测 / 护驾交战过滤
- spawn 路径改 `set_state=true`：survivor_spawner._spawn_squad / zone_mission 2 处。原本依赖自校正守卫初始化，现在显式直接进 SQUAD_FOLLOW
- 自校正守卫保留（移到运行时兜底用）—— 注释更新说明：所有 spawn 已显式，守卫现在只服务运行时招募 / PATROL 残留兜底；Sentinel UAV 走 simple_ai 路径不会触发守卫
- **未做**：orbit/shield/kamikaze 执行体的迁移（仍住 ai_controller.gd._process_simple ~250 行）。原因：与 simple_ai 的 PATROL/ENGAGE 分支高度耦合（_current_target 共享 / _scan_timer 复用 / 撤退条件判断），完整搬运要重写整个 _process_simple，风险高。EscortBehavior 类已建好，为未来执行体迁移留好接口位

## 收益

- **状态镜像消失**：Aircraft 不再持有 `_formation_blend` / `_formation_jitter_phase`；AircraftFormation 通过 `_ai_ref` 单源读
- **9 处生成路径收口**：所有调用都走 `SquadFactory.create()` + `register_leader/register_wingman`，新增"主角小队 / BOSS 护航"只调一个工厂
- **Aircraft 编队接口**：set_formation_target / clear_formation 替代了散布在 7 处的 4-5 行字段写入块
- **常量集中**：编队反应延迟 6 个常量从 AIController 收编到 Squad，整队级配置归一处
- **Squad 升 Resource**：未来阵型预设可 .tres 化（`finger_four_aggressive.tres` / `wedge_loose.tres`）
- **leader_changed 信号**：长机阵亡晋升解除了 `_sync_leader_squad_index` 反向调用 AIController 的隐性副作用（暂保留实现，未来 listener 接管）

## 验证

按计划 5 个场景测试：
1. 沙盒 F2/F3/F4 + Tab 切换阵型
2. 生存模式 F-16/F-14 起始僚机 + 协同攻击 + 自由扫描
3. 生存模式敌方编队（Lv 5+ MIG/F86/MIG23）
4. Sentinel + UAV 护航（Lv 4+，orbit 路径未动应保持原样）
5. F-47 BOSS（AceSquad，未动应保持原样）

每个场景 F9 导出 log 看有没有 squad/formation 相关 push_warning / null deref。
