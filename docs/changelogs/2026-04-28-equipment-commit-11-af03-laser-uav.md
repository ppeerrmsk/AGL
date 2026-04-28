# 更新日志 — 2026-04-28（commit 11）

## 装备模块化 commit 11/13 — AF-03 电磁炮狙击 + Aegis 激光 UAV

最后两个新内容：用了新装备系统的两种敌人。

## AF-03（EnemyType.AF03 = 17）

**Schemer with combat**——具备战斗能力的策士型，配置：

- 仅装备电磁炮（敌人版）：`charge_duration=2.5s`、`lock_trajectory_at=AT_CHARGE_START`、
  `damage=60`、`range=5500m`、`cooldown=9s`
- 玩家看到 AF-03 朝自己充能（红色扇形从 30° 收缩到 0°）→ 立刻知道弹道已锁死 →
  2.5s 内任何机动都能躲掉（**唯独直线匀速飞行会被命中**）
- HP 60，无机炮 / 无导弹 / 无热诱弹 / 无火箭弹 → 玩家不靠近时无法反击 AF-03（除非用电磁炮）

**AI 配置**（survivor_spawner.gd `_create_enemy` AF03 case）：
- `evade_missiles=true`，`aggression=0.7`（不主动近身但持续 keep distance）
- `engage_duration=60s`（长时间盯人）
- `skill_level=0.85, composure=0.80, focus=0.92`
- **`self_preservation=0.85`** ← 关键：玩家近身立即脱离

Token=7，instance_cap=1（高威胁独特机制，多于 1 太挤压）。

## Aegis UAV（EnemyType.UAV_LASER = 18）

**拦截支援 Schemer**——跟随 Sentinel 出现的导弹拦截器：

- 仅装备 LaserEquipment 拦截特化版：`can_target_aircraft=false`、
  `can_target_missiles=true`、`can_target_ground=false`、`dps_max=80`、`range=1200m`
- 完全无攻击力——玩家飞过去撞它都不还手；纯专心拦截飞向 Sentinel 的导弹
- HP 40 脆皮

**AI 配置**：
- `simple_ai=true, enable_combat=false`（laser update 自己扫描 + 自动开火，AI 不参与）
- `orbit_squad_leader=true`（绕 Sentinel 飞）
- `self_preservation=0.95`

每只 Sentinel 出现时自动带 2 架（`_spawn_commander_squad` 末尾追加）。

**克制关系**（玩家应对策略）：
- 方案 A：先用机炮/激光近身打掉 2 架 Aegis UAV，再发导弹打 Sentinel
- 方案 B：发多发导弹饱和（齐射升级派上用场）
- **方案 C**：用电磁炮直接秒 Sentinel（电磁炮是动能弹，激光拦不下来 → 克制）

## 改动清单

### 新增 .tres
- `resources/enemy_railgun.tres`（敌方电磁炮：长充能 + 早锁定 + 中等伤害）
- `resources/enemy_laser_interceptor.tres`（导弹拦截激光：仅 missiles target_filter）
- `resources/enemy_af03.tres`（AircraftParams）
- `resources/enemy_uav_laser.tres`（AircraftParams）

### 修改 `scripts/survivor/survivor_spawner.gd`
- EnemyType 枚举末尾追加 `AF03, UAV_LASER`
- 新增 `_af03_params_base` / `_uav_laser_params_base` 字段 + `_ready` 加 preload
- `_create_enemy` 5 个 match 全部追加 case（base_params / scale / type_tag / AI 配置）
- `_spawn_commander_squad` 末尾追加 2 架 Aegis UAV 自动护卫

### 修改 `scripts/survivor/survivor_data.gd`
- TOKEN_COST 加 16/17/18（F14_Poltergeist=10, AF03=7, UAV_LASER=2）
- TOKEN_INSTANCE_CAP 加 16/17/18（4/1/2）

### 修改 `scripts/survivor/survivor_debug_spawn.gd`
ENEMY_TYPE_LABELS 末尾追加 AF03 + UAV_LASER 两条，可手动测试。

### 修改 CLAUDE.md
敌人索引表追加 2 行。

## 已知缺口（明天再说）

1. **未接入 `_pick_enemy_type`**：AF-03 / Aegis UAV 不会随机刷出，必须事件触发或调试面板。
   未来可加规则：Lv8+ 后小概率刷 AF-03 单机
2. **AI 没有针对电磁炮的"keep distance" 战术**：AF-03 用现有 `_process_engage` 路径，
   不知道电磁炮 prefer_range=5500m。`self_preservation=0.85` 让它不会冲脸但也不会主动维持
   理想距离。等 commit 12 TacticalPlanner 投票模型上线后才会自动执行 TAIL_CHASE@5km
3. **未与事件系统集成**：AF-03 应该走 `events/` 目录的 GameEvent 体系（类似 BossEncounter），
   commit 11 没做这步。当前只能 debug 触发
4. **僚机绕 Sentinel 飞**：Aegis UAV 设了 orbit_squad_leader=true 但没加入 `sq.add_member`
   （只设了 squad/squad_index）→ 可能会绕得不对。需要测试

## 累计进度

```
[完成] commit 1-10  全部装备 + 升级过滤 + X-02 主角
[完成] commit 11    AF-03 + Aegis UAV
        commit 12   TacticalPlanner 投票模型 + 老路径删除（视精力）
```

至此**所有用户在设计阶段提过的内容都已落地**：电磁炮 / 激光 / X-02 / AF-03 / 激光 UAV /
云层削弱 / 过热 / 穿透 / telegraph / 双锁定时机 / 升级过滤 / 装备模块化。

可以**收工**或**继续 commit 12**（投票模型）让 AI 对新装备更智能。
