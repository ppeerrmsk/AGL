# 脚本 API 参考

> 最后校订：2026-07-26。
>
> ⚠ **本文是选摘，不是全量 API**。它覆盖的是**核心实体层**（CombatUnit / Aircraft / Missile /
> 管理器 / Squad / Resource 基础类）的关键变量与方法。后来加的大量子系统
> （rts / presentation / naval / zones / equipment / survivor 的绝大部分）**不在这里**。
>
> 找文件与入口 → [script-index.md](script-index.md)（全量、按文件）
> 找某个功能的实现 → [code-index.md](code-index.md)（按功能主题）
> 找数值与设计意图 → [docs/specs/](../specs/_INDEX.md)

---

## 类继承结构

```
Node2D
├── CombatUnit                     # 战斗单位基类
│   ├── Aircraft                   # 飞机（玩家/AI通用）
│   └── GroundUnit                 # 地面单位基类
│       ├── SAMUnit                # 防空导弹车
│       ├── AAGunUnit              # 高射炮
│       └── RadarStation           # 雷达站
│   └── NavalUnit                  # 舰船基类
│       ├── CarrierShip / CruiserShip / DestroyerShip / FrigateShip / SubmarineShip
│       └── （挂点 WeaponMount / MountTarget / WeakPoint 承担伤害路由）
├── Missile                        # 导弹飞行实体
├── BulletManager                  # 机炮子弹管理器
├── MissileManager                 # 导弹管理器
└── TrailRibbon                    # 烟迹/尾迹渲染

Node
├── AIController                   # AI 状态机（附加到飞机子节点）
├── SurvivorPlayer                 # 生存模式经验/等级系统
└── EventDirector                  # 剧本调度器（survivor_mode 子节点）

RefCounted
├── Squad                          # 编队数据与阵型计算
├── SurvivorData                   # 生存模式静态数据（技能表 / Token 刷怪配置 / XP 曲线）
├── CallsignDB                     # 呼号分配器
├── GameEvent                      # 剧本基类
└── AIDirective                    # 声明式 AI 覆盖指令

Resource
├── AircraftParams                 # 飞机性能参数
├── GunParams / MissileParams / RocketParams / TorpedoParams / FlareParams
├── LoyalWingmanParams / NavalParams / WeaponMountParams
├── EquipmentParams                # 模块化装备基类（gun/rocket/missile/flare/railgun/laser/evasion）
├── CombatParams                   # 战斗 AI 行为参数
└── PlayableAircraft               # 主角机档案
```

> 静态工具模块（`aircraft/` · `ai/` · `ai/tactical/` 下的 RefCounted 静态类）不在此树中，
> 它们不是实体类型，只是 Aircraft / AIController 的实现拆分。

---

## CombatUnit（战斗单位基类）

**文件**: `scripts/combat_unit.gd`

所有可战斗实体（飞机、地面单位）的基类，提供共享接口。

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `GRAVITY` | 9.81 | 重力加速度 |
| `PIXELS_PER_METER` | 0.5 | 1米=0.5像素 |

### 高度档位系统

```gdscript
enum AltitudeTier { GROUND = -1, LOW = 0, MID = 1, HIGH = 2 }
# 档位判定边界（get_altitude_tier）: LOW: <3500m, MID: 3500-7500m, HIGH: >=7500m
const TIER_ALTITUDE  # 切档目标高度（set_target_tier）: GROUND 0 / LOW 2000 / MID 5500 / HIGH 10000
```

⚠ **判定边界 ≠ 切档目标**：切到 HIGH 后飞机以 10000m 为目标爬升，但 7500m 起 UI 就显示
HIGH——tier 门控效果（+20% 机炮闪避、AA 散布 ×3 等）在 7500m 已全部生效，7500→10000m
段的收益是连续量（雷达距离 ×1.22→×1.40、图标放大、高空 G 阻力折减）。降 LOW 同理
（3500m 翻档、2000m 到位，俯冲段是加速所以体感无碍）。

### 关键属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `team` | int | 阵营 (0=友方, 1=敌方)，@export |
| `callsign` | String | 唯一呼号标识 |
| `altitude` | float | 高度（米） |
| `heading` | float | 航向（弧度, 0=北） |
| `speed` | float | 速度 (m/s) |
| `hp` | float | 血量 |
| `is_destroyed` | bool | 是否被击毁 |
| `flat_altitude` | bool | 扁平高度模式（生存模式用三/四档） |
| `radar_targets` | Dictionary | `{CombatUnit: float}` 雷达锥内目标的累计照射时间 |
| `is_locked` | bool | 被至少一个敌方锁定 |
| `locked_by` | Array[CombatUnit] | 锁定自己的单位列表 |
| `is_hovered` | bool | 鼠标悬停中 |

### 关键方法

| 方法 | 说明 |
|------|------|
| `take_damage(amount)` | 扣血，HP≤0 触发 `_on_destroyed()` |
| `is_in_radar_cone(pos) → bool` | 子类覆写实现雷达锥判定 |
| `is_lock_immune() → bool` | 子类覆写实现锁定免疫 |
| `get_altitude_tier() → int` | 从 altitude 推算高度档位 |
| `effective_distance_px(...)` | 静态方法，含高度差的 3D 距离（像素） |

### ID 分配器

静态方法 `_allocate_id()` / `_recycle_id()` / `reset_id_allocator()` 管理全局唯一 ID。

---

## Aircraft（飞机）

**文件**: `scripts/aircraft.gd`  
**继承**: CombatUnit

核心实体，包含飞行物理、战斗 AI、武器系统、热诱弹、视觉绘制。

### 导出属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `params` | AircraftParams | 飞机性能资源 |
| `initial_heading_deg` | float | 初始航向（度） |

### 飞行状态

| 属性 | 说明 |
|------|------|
| `bank_angle` | 滚转角（弧度） |
| `g_load` | 当前 G 力 |
| `is_stalled` | 失速状态 |
| `target_position` | 目标航路点（Vector2，INF=无目标） |
| `target_altitude` | 目标高度（米） |
| `target_speed_kmh` | 目标速度 (km/h) |
| `fuel` | 剩余燃油 (kg) |
| `is_afterburner` | 加力状态 |

### 战斗状态

| 属性 | 说明 |
|------|------|
| `combat_target` | 锁定的战斗目标 (CombatUnit) |
| `weapon_mode` | WeaponMode 枚举: MISSILE / GUN |
| `missiles_remaining` | 剩余导弹数 |
| `secondary_missiles_remaining` | 副导弹剩余数 |
| `is_firing` | 正在开火 |
| `ammo` | 剩余弹药 |
| `_crank_timer` | 导弹发射后照射保持计时（>0 时稳定飞行） |
| `_in_rear_hemisphere` | 是否在敌机后半球 |

### 生存模式专属属性

| 属性 | 说明 |
|------|------|
| `enable_missile_reload` | 自动装填导弹 |
| `missile_reload_duration` | 装填总时间（可通过升级缩短） |
| `max_simultaneous_locks` | 多目标同时锁定数 |
| `bullet_dodge_chance` | 机炮闪避概率（机体基线 + 座舱护甲等技能） |
| `flare_lock_immunity` | 热诱弹释放后锁定免疫秒数 |
| `gun_extra_barrels` | 多管齐射额外管数 |
| `missile_bounce_count` | 连锁弹头弹跳次数 |
| `infinite_fuel` | 无限燃油 |
| ~~`no_stamina`~~ | **已移除**（耐力系统撤下后无意义）|
| `lod_level` | LOD 等级 (0=完整, 1=简化, 2=屏幕外) |

### 物理演算流程 (_physics_process)

```
1. _update_weapon_mode()        武器模式判定（MISSILE/GUN）
2. _update_combat(delta)        追踪/交战逻辑
3. _update_energy_management()  速度/高度/加力管理
4. _update_target_heading()     目标航向计算
5. _update_bank(delta)          滚转角更新（受导弹阶段影响）
6. _update_heading(delta)       航向更新 ω = g × tan(bank) / speed
7. _update_speed(delta)         速度趋近（含高G阻力）
8. _update_altitude(delta)      高度趋近
9. _update_fuel(delta)          燃油消耗
10. _update_stall()             失速检查
11. _update_g_load()            G 力计算
12. ~~_update_pilot_stamina(delta)~~ —— **已移除**（耐力系统撤下）
13. _apply_movement(delta)      位移应用
14. _update_gun(delta)          机炮射击
15. _update_missile(delta)      导弹发射
16. _update_flare(delta)        热诱弹
17. _update_lock_immunity(delta) 锁定免疫
18. _update_visuals()           视觉更新
```

### 关键公开方法

| 方法 | 说明 |
|------|------|
| `set_combat_target(target)` | 设定战斗目标 |
| `clear_combat_target()` | 清除战斗目标 |
| `take_damage(amount)` | 受伤（导弹） |
| `take_bullet_damage(amount)` | 受伤（机炮，受闪避影响） |
| `deploy_flares()` | 释放热诱弹 |
| `set_target_tier(tier)` | 设置目标高度档位（生存模式） |

### 武器模式切换逻辑

```
无导弹 → GUN
Crank 阶段 → 强制 MISSILE
当前 GUN + 有导弹 → 距离 > 机炮射程×2 才切 MISSILE（滞后）
当前 MISSILE → 距离 < 机炮射程×0.8 才切 GUN
```

### 导弹交战三阶段

| 阶段 | 条件 | 机动 | 速度 |
|------|------|------|------|
| 0 接近 | 目标不在雷达锥内 | 积极 | 可加力 |
| 1 照射 | 目标在锥内，累积锁定中 | 适度稳定 | 巡航 |
| 2 保持 | 已锁定/crank | 极稳定 | 巡航×0.95 |

---

## Missile（导弹实体）

**文件**: `scripts/missile.gd`

### 关键属性

| 属性 | 说明 |
|------|------|
| `params` | MissileParams 资源 |
| `source` | 发射单位 (CombatUnit) |
| `target` | 目标单位 (CombatUnit) |
| `has_guidance` | 当前是否有制导 |
| `is_flare_jammed` | 被热诱弹干扰（永久失去制导） |
| `bounces_remaining` | 剩余弹跳次数（连锁弹头） |
| `age` | 存活时间 |
| `is_active` | 是否活跃 |

### 飞行物理 (_physics_process)

1. 超时/能量耗尽 → 失活
2. 动力阶段（< motor_burn_time）→ 加速；否则减速
3. 制导判定：
   - `fire_and_forget` → 只要目标存活就有制导
   - SARH → 查询 `source.radar_targets[target]` 是否满足锁定
4. 比例导引 (PN): `A_cmd = N × V_closure × ω_LOS`
5. 近距 <200m 切纯追踪
6. 低空目标导引头性能衰减（`_guidance_degradation()`）

---

## BulletManager（子弹管理器）

**文件**: `scripts/bullet_manager.gd`

每帧更新所有弹丸位移 + 命中检测。

### 关键配置

| 属性 | 说明 |
|------|------|
| `combat_unit_list` | 由 main.gd 每帧更新的所有战斗单位列表 |
| `friendly_hit_radius` | 友方命中半径（生存模式可扩大） |
| `flat_altitude_mode` | 扁平高度模式（跳过高度容差检查） |

### 弹丸数据结构

```gdscript
{ pos: Vector2, vel: Vector2, source: CombatUnit, damage: float, life: float, max_life: float, altitude: float }
```

### 伤害衰减

- 前 30% 飞行距离满伤害
- 之后线性衰减到 20%

---

## MissileManager（导弹管理器）

**文件**: `scripts/missile_manager.gd`

### 关键方法

| 方法 | 说明 |
|------|------|
| `spawn_missile(source, target, params)` | 生成导弹（初速=发射单位速度+50） |
| `has_active_missile_at(source, target) → bool` | 检查目标是否已有在飞导弹 |

### 命中检测

每帧遍历 missiles × target_list：
- 2D距离 < `proximity_fuse_radius × PIXELS_PER_METER`
- 高度差 < `proximity_fuse_alt`（地面单位跳过高度检查）
- 引信武装：`age > guidance_delay`

### 连锁弹头

命中后若 `bounces_remaining > 0`，寻找最近的其他敌方单位作为新目标。

---

## main.gd（沙盒模式主场景 —— **已废弃**）

**文件**: `scripts/main.gd`

> ⚠ **沙盒模式已废弃**，只作物理 / AI 调试留存，不打包、不加新内容。
> 生存模式的对应职责在 `scripts/survivor/survivor_mode.gd`（主控）+
> `scripts/camera_controller.gd`（相机）+ `scripts/rts/`（指挥）。
> 本段仅供调试时参考。

### 职责

- 相机控制（缩放/平移）
- 鼠标输入处理（左键选中/锁定、右键取消）
- 雷达锁定计算循环（每帧 `_update_radar_locks`）
- 编队管理（F1-F4 生成编队，F5 切换阵型）
- LOD 管理
- 地形绘制（FastNoiseLite 噪声地形 + 网格）
- 单位列表同步到 BulletManager/MissileManager

### 快捷键

| 按键 | 功能 |
|------|------|
| F1 | 生成 4 机友方编队 |
| F2 | 生成 2 机友方编队 |
| F3 | 生成 2 机敌方编队 |
| F4 | 生成 4 机敌方编队 |
| F5 | 切换阵型 |
| F9 | 导出战斗日志 |
| ESC | 返回主菜单 |

### 雷达锁定计算

- 在锥内 → 按 `_lock_rate_for_tier()` 速率累加照射时间（低空/地面目标锁定更慢）
- 不在锥内 → 1.5秒衰减窗口（防边缘震荡）
- 累计时间 ≥ lock_time → 判定锁定

---

## Squad（编队系统）

**文件**: `scripts/squad.gd`

### 阵型枚举

```
COMBAT_SPREAD  战斗展开（并排大间距）
WEDGE          楔形编队（后方45°）
ECHELON        梯形编队（右侧阶梯）
TRAIL          纵列编队（正后方）
FINGER_FOUR    指尖四点（不对称）
FLUID_FOUR     流体四机（两对战斗翼）
```

### 关键方法

| 方法 | 说明 |
|------|------|
| `get_formation_offset(index) → Vector2` | 计算成员在编队中的像素偏移 |
| `get_wingman_target(index) → Vector2` | 计算僚机世界坐标目标点 |
| `cycle_formation()` | 切换到下一个阵型 |
| `cleanup()` | 清理无效成员 |

---

## EventLogger（事件日志）

**文件**: `scripts/event_logger.gd`  
**类型**: 自动加载单例 (Autoload)

O(1) 环形事件队列，保留最近 300 秒事件；逐条过期不搬移剩余缓冲。F9 导出：编辑器模式写 `<project>/logs/combat_log_*.txt`，导出包写 `user://combat_log_*.txt`（路径策略见 `dump_to_file` 注释）。

```gdscript
EventLogger.log_event("MISSILE", "Player", "hit Enemy#3 (dmg=80)")
```

---

## CallsignDB（呼号分配器）

**文件**: `scripts/callsign_db.gd`

静态类，每架飞机 `_ready()` 时调用 `CallsignDB.allocate()` 获取唯一呼号。

---

## TrailRibbon（烟迹/尾迹）

**文件**: `scripts/trail_ribbon.gd`

通用 ribbon trail 渲染器，用于导弹烟迹和飞机尾迹。

### 配置

| 属性 | 说明 |
|------|------|
| `ribbon_width` | 宽度 |
| `max_points` | 最大采样点数 |
| `sample_interval` | 采样间隔（秒） |
| `ribbon_color` | 颜色 |

---

## Resource 资源类

### AircraftParams (`scripts/aircraft_params.gd`)

飞机全部性能参数，通过 .tres 文件配置。

**参数分组**: 基本信息 / 生存性 / 速度 / 机动性 / 飞行员 / 高度 / 引擎 / 燃油 / 雷达 / 机炮 / 导弹 / 热诱弹 / 战斗风格 / 视觉

关键子资源引用:
- `gun: GunParams` — 机炮
- `missile: MissileParams` — 主导弹
- `secondary_missile: MissileParams` — 副导弹
- `flare: FlareParams` — 热诱弹
- `combat: CombatParams` — 战斗风格

### GunParams (`scripts/gun_params.gd`)

| 参数 | 说明 |
|------|------|
| `fire_rate` | 发/分钟 |
| `bullet_damage` | 单发伤害 |
| `muzzle_velocity` | 弹丸初速 (m/s) |
| `max_range` | 最大射程 (m) |
| `spread_angle` | 散布半角（度） |
| `fire_cone_half_angle` | 允许开火的机头偏角（度） |
| `max_ammo` | 弹药量 |

### RocketParams (`scripts/rocket_params.gd`)

| 参数 | 说明 |
|------|------|
| `burst_count_max` | 单次涟发火箭数；实际发射受剩余弹药钳制 |
| `burst_interval` | 左右挂点逐发交替时的单发间隔（秒） |
| `muzzle_velocity` | 火箭初速 (m/s) |
| `max_range` | 最大射程 (m) |
| `spread_angle` | 远段最终散布半角（度） |
| `straight_flight_distance` | 出膛后保持平行直飞的距离；默认 180m |
| `spread_transition_distance` | 从直飞平滑展开到最终散布角的距离；默认 320m |
| `fire_cone_half_angle` | 自动开火允许的机头偏角（度） |
| `min_range` / `max_fire_range` | 自动开火距离带 (m) |
| `max_ammo` / `infinite_ammo` | 总弹量与无限弹药开关 |

### MissileParams (`scripts/missile_params.gd`)

| 参数 | 说明 |
|------|------|
| `max_speed` | 最大速度 (m/s) |
| `motor_burn_time` | 发动机燃烧时间 (s) |
| `motor_acceleration` | 加速度 (m/s²) |
| `drag_deceleration` | 燃尽减速率 (m/s²) |
| `max_g` | 最大过载 |
| `nav_constant` | PN 导引常数 |
| `max_range_rear` | 后半球最大射程 (m) |
| `front_rear_ratio` | 前/后半球射程比 |
| `damage` | 命中伤害 |
| `proximity_fuse_radius` | 近炸引信半径 (m) |
| `fire_and_forget` | 发射后不管模式 |
| `distance_airburst_distance_m` | 定距空爆累计路径 (m)，0=关闭 |
| `distance_airburst_min_launch_range_m` | 定距空爆武器的近身停火距离 (m) |
| `distance_airburst_radius_m` / `distance_airburst_duration_s` | 定距空爆 AOE 半径 (m) / 持续时间 (s) |
| `max_count` | 挂载数量 |
| `cooldown` | 发射间隔 (s) |

### CombatParams (`scripts/combat_params.gd`)

战斗 AI 行为风格配置，分组:

- **追踪策略**: 拦截距离/预判/闭合率/六点钟偏移
- **开火纪律**: 机会射击角度放宽/射程缩减
- **机动激进度**: bank 激进度/满坡度阈值
- **转向减速**: 减速角度/速度倍率
- **速度管理**: 接近/格斗/咬尾速度倍率/防冲过参数
- **能量管理**: 俯冲/爬升触发条件/深度/高度限制

### FlareParams (`scripts/flare_params.gd`)

| 参数 | 说明 |
|------|------|
| `max_flares` | 携带总量 |
| `burst_count` | 每次释放枚数 |
| `cooldown` | 释放间隔 (s) |
| `base_jam_chance` | 基础干扰成功率 |
| `aspect_bonus` | 侧/后方追来额外成功率 |
| `maneuvering_bonus` | 大幅机动（G>4）额外成功率 |
| `close_range_penalty` | 极近距离（<150m）惩罚 |
| `nervousness` | 飞行员焦虑度 (0=冷静, 1=慌张) |
