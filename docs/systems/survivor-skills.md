# 生存模式技能系统

完整技能图鉴 + 设计哲学 + 待实现技能规划。
所有技能定义见 [scripts/survivor/survivor_data.gd](../../scripts/survivor/survivor_data.gd) `UPGRADES` 表，运行时应用见 [scripts/survivor/survivor_player.gd](../../scripts/survivor/survivor_player.gd) `apply_upgrade()`。

## 索引

- [设计哲学](#设计哲学)
- [系统机制](#系统机制)
- [技能图鉴](#技能图鉴)（生存 / 机动 / 电子战 / 导弹 / 副武器）
- [战区奖励池](#战区奖励池)
- [骑士精神系列](#骑士精神系列chivalry)
- [恐惧 / 心理战系列](#恐惧--心理战系列fearpsywar)
- [EMP / 电子瘫痪系列](#emp--电子瘫痪系列emp)
- [环境 / 天气系列](#环境--天气系列environment)
- [扩展约束](#扩展约束)

---

## 设计哲学

**两种增益曲线并存**：
- **线性堆叠**（`max_stacks > 1`）— 玩家可重复 roll 同一技能堆数值；常规升级池主体
- **战区奖励**（`evolved: true` 不参与随机池）— 通关战区任务才发，避免被升级 RNG 稀释

> ⚠ **进化系统已弃用**：早期设计有 `evolves_to` 链（基础满级 → 进化形态），现已取消。当前代码里残存的 `evolves_to` 字段后续会清理。新技能不再引入进化链，要么走常规堆叠，要么直接走战区奖励池。

**轴线**：
- 常规：`survival` 生存 / `mobility` 机动 / `electronic_warfare` 电子战 / `missile` 导弹 / `secondary` 副武器（机炮）
- 设计中的子主题（不一定是独立轴，可挂在战区奖励池）：
  - `chivalry` 骑士精神 — 鼓励对头 / 低空 / 高速等反偷袭打法
  - `fear` 心理战 — 利用 pilot_personality 的 stress / SA 系统压迫敌人判断
  - `emp` 电子瘫痪 — 短时让敌方雷达 / 锁定 / 武器失效

**几何门槛优先于状态机**：
新技能尽量用"当帧几何条件"触发（heading dot、距离、高度、速度），不引入额外计时器或外部状态。这样玩家从视觉就能预判会不会触发，没有"我做了对的事但系统没认"的挫败。

**僚机扩展性**：
击杀归因层（`_pending_attacker` meta + `_record_kill_attribution`）已经能识别任意 attacker，不只玩家。后续做僚机版技能时把判定从 `attacker_id == player_id` 放宽到 `attacker.team == 0` 即可。

---

## 系统机制

### 经验曲线

```gdscript
static func xp_for_level(level: int) -> int:
    return int(20.0 * pow(level, 1.15))
```

每次升级暂停游戏，弹出 3 个随机升级，玩家选 1 个。详见 [survivor_player.gd](../../scripts/survivor/survivor_player.gd)。

### 升级筛选规则

`SurvivorData.is_upgrade_available_for(upgrade, aircraft_id, params)` 在抽卡前过滤：

| 字段 | 作用 |
|---|---|
| `requires: ["gun"/"missile"/"flare"/"rocket"]` | 主角必须装备对应硬件，否则不出现 |
| `exclusive_to: ["f14", ...]` | 仅指定 PlayableAircraft.id 能 roll 到（专属技能） |
| `evolved: true` | 完全不进随机池，靠战区奖励发放 |
| `max_stacks` | 已达上限的技能不再 roll |

### 击杀归因（Kill Attribution）

骑士系列 / 心理战系列 / 未来僚机技能共享的统一基础设施。

- 攻击者 → 被害者：[bullet_manager.gd](../../scripts/bullet_manager.gd) / [missile_manager.gd](../../scripts/missile_manager.gd) 在调 `take_damage` 前 `set_meta("_pending_attacker", source)`
- 致死帧快照：[aircraft.gd](../../scripts/aircraft.gd) `_record_kill_attribution()` 写入 4 个 meta：
  - `kill_attacker_id` — instance_id（精确匹配）
  - `kill_attacker_team` — 0=友方
  - `kill_head_on_dot` — `−victim_fwd · to_victim`，1=对头
  - `kill_attacker_aim` — `attacker_fwd · to_victim`，1=攻击者瞄准
- 奖励发放：[survivor_spawner.gd](../../scripts/survivor/survivor_spawner.gd) `_detect_kills` → `_check_head_on_kill_bonus()`
- 不触发：地面坠机（绕过 `_apply_damage`）/ SAM/AAA/船击杀（`attacker is Aircraft` 过滤）

### 飞行员心理（pilot_personality）— 心理战钩子

[pilot_personality.gd](../../scripts/pilot_personality.gd) 已有 `stress` / `situational_awareness` / `composure` 状态，影响 AI 判断误差。
任何"恐惧"/"压制"类技能都应通过给敌方 AI 注入 `stress` 实现，而不是直接改 AI 状态机。

---

## 技能图鉴

🟡 = 战区奖励池（不参与随机升级抽卡）
✅ = 已实现 / ⏳ = 规划中

### 生存轴（survival）

| id | 效果 | 层数 | 注 |
|---|---|---|---|
| `hp_up` | +30 max_hp，每层 +8% 机炮闪避（cap 40%） | 5 | 双轴（HP + 闪避） |
| `armor_up` | +40 armor（DR 软上限，导弹穿甲 50%） | 4 | 1 层 ≈ 29%/机炮·17%/导弹 |
| `kill_heal` | 击杀回血 +10 HP | 3 | |
| `xp_mult` | XP 倍率累加 +20%（硬顶 ×1.4） | 2 | |
| `shock_absorb` 🟡 | 受 ≥2 dmg 排队回 floor(dmg×0.4) HP；一击致死无效 | 1 | |

### 机动轴（mobility）

| id | 效果 | 层数 | 注 |
|---|---|---|---|
| `speed_up` | +18% max_speed，加速跟着涨一半 | 4 | |
| `maneuver_up` | +25% 转弯能力，每层 +1 G、+0.5 结构 G | 3 | |
| `dogfight` | -12% 失速速度 + +30% 减速 + +20% G 阻力 + 大角度减速更多 | 3 | 综合格斗 buff |
| `cobra_skill` 🟡 | 规避模式下被来袭/追尾自动眼镜蛇 | 1 | |
| `executioner` 🟡 | 不受伤连杀堆层（max 5），每层 +5% 速度 / +10% 减速 / 武器加成；受任意伤害清零 | 1 | |

### 电子战轴（electronic_warfare）

| id | 效果 | 层数 | 注 |
|---|---|---|---|
| `flare_cooldown` | -20% 热诱弹冷却 | 3 | |
| `flare_shield` 🟡 | 自动护盾 + 赠送 2 枚热诱弹 | 1 | |
| `stealth_pod` | 敌人锁定速率 ÷1.35 / ÷1.82 / ÷2.46 | 3 | |
| `radar_range` | +20% 雷达距离 | 3 | |
| `radar_angle` | +15% 雷达锥角度（cap 90°） | 3 | |
| `lock_time` | -0.5s 锁定时间（地板 0.5s） | 3 | |
| `vapor_dodge` 🟡 | 切高度速度 ×2 + 云中 lock_rate ×0.1 | 1 | |
| `ecm_pod` 🟡 | 敌方雷达对我有效距离 ×0.75 | 1 | |

### 导弹轴（missile）

需要 `requires: ["missile"]`，无导弹的主角不会 roll 到。

| id | 效果 | 层数 | 注 |
|---|---|---|---|
| `missile_count` | +1 载弹 | 4 | |
| `missile_tracking` | +30% 跟踪 | 4 | |
| `missile_reload` | -15% 装填 | 3 | |
| `missile_boost` | -15% cooldown / +15% 燃烧时间 / +10% 加速 | 3 | |
| `seeker_fov` | +20% 导引头 FOV（cap 120°） | 3 | |
| `multi_lock` | 多锁定齐射 | 1 | |
| `proximity_fuze` 🟡 | 近炸引信 AOE | 1 | |
| `missile_bounce` 🟡 | 连锁弹头（命中后弹跳至另一敌机） | 1 | |
| `fire_and_forget` 🟡 | 发射后无需照射，可立刻转向 | 1 | |

### 副武器轴（secondary，机炮系）

需要 `requires: ["gun"]`。

| id | 效果 | 层数 | 注 |
|---|---|---|---|
| `gun_damage` | +20% 机炮伤害 | 5 | |
| `gun_ammo` | +100 备弹 | 5 | |
| `gun_reload` | -15% 装填 | 3 | |
| `gun_firerate` | +25% 射速 | 4 | |
| `gun_range` | +20% 射程 | 4 | |
| `gun_accuracy` | -20% 散布（地板 0.1°）+ 飞行员 aim_skill +0.18/层 | 4 | |
| `aim_assist` | +25% 开火扇区（cap 45°） | 3 | |
| `gun_kill_fear` ✅ | 机炮击杀 AOE 注入恐惧 stress（每层 +800px 半径，满级 2400px） | 3 | 心理战已实装的代表作 |
| `gun_multishot` 🟡 | 一次发射 +2 弹 | 1 | |
| `gun_ciws` 🟡 | 自动 CIWS 拦截来袭导弹 | 1 | |

---

## 战区奖励池

打通战区任务发放，**不**进入常规升级池。当前清单：

`shock_absorb` / `executioner` / `vapor_dodge` / `ecm_pod` / `fire_and_forget` / `flare_shield` / `proximity_fuze` / `missile_bounce` / `gun_multishot` / `gun_ciws`

新技能要进战区池：`evolved: true` + 在战区奖励发放代码里挂上挑选权重。

---

## 骑士精神系列（Chivalry）

鼓励**反偷袭**的正面交锋打法：对头、近距、低空、高速。
反向激励的是 BVR 偷袭 / 后半球追尾这种保守玩法 —— 不禁止，但不奖励。
定位上倾向战区奖励池或专属升级槽，不污染常规 RNG。

### ✅ 对头猎手（Head-On Hunter）

玩家用机炮 / 火箭 / 导弹直接命中击落对头来袭的敌机 → **永久 +5 max_hp**。

**几何判据**（双方当帧 heading 几何）：
- `head_on_dot = -victim_fwd · to_victim > 0.6`（受害者机头朝攻击者，夹角 ≲ 53°）
- `attacker_aim = attacker_fwd · to_victim > 0.6`（攻击者机头朝受害者，夹角 ≲ 53°）

**实现**：
- 归因层：[aircraft.gd](../../scripts/aircraft.gd) `_record_kill_attribution()`
- 攻击者标注：[bullet_manager.gd](../../scripts/bullet_manager.gd) / [missile_manager.gd](../../scripts/missile_manager.gd)
- 奖励发放：[survivor_spawner.gd](../../scripts/survivor/survivor_spawner.gd) `_check_head_on_kill_bonus()`
- 常量：`HEAD_ON_KILL_HP_BONUS = 5.0` / `HEAD_ON_DOT_THRESHOLD = 0.6`
- EventLogger tag：`HEAD_ON_KILL`

**未来扩展**：
- 把判定阈值放宽到 friendly team → 僚机版骑士技能
- streak 机制（连续 3 次对头击杀 → 额外效果）
- 机炮对头 vs 导弹对头给不同奖励（机炮更高，鼓励近距）

### ⏳ 冲锋盾（Charge Shield）

低空 + 高速时机头前方出现一个吸收伤害的能量护盾。

**触发条件**（每帧检查）：
- `altitude_tier == LOW`
- `speed_kmh > params.cruise_speed * 1.15`（明显高于巡航）
- 机头方向 ±30° 扇区内有敌方单位 / 子弹 / 导弹（确保是冲向某物而不是后撤）

**护盾参数**：
- 形状：机头前方半径 ~250px 半圆 / 三角形 wedge
- 吸收：上限 50 HP，缓充 10 dmg/秒，被打掉后 3s 冷却重生
- 视觉：半透明蓝色光晕 + 受击时白色闪光
- 受击范围：所有 incoming projectile 进入 wedge 几何范围时先扣护盾值，护盾未破时不传给飞机

**实现思路**：
- 加 `Aircraft.charge_shield_active: bool` + `charge_shield_hp: float`
- aircraft_physics.gd 每帧维护 active 状态
- bullet_manager / missile_manager 命中前先做 wedge 几何判定，命中护盾就吃护盾值，飞机不受伤
- 与 `armor` / `shock_absorb` 的优先级：护盾在最外层（先吃），armor 在最内层（最后过 DR）
- aircraft_renderer.gd 加 `draw_charge_shield(ac)`

### ⏳ 想法占位

| 名称 | 触发 | 效果 |
|---|---|---|
| **正面对决（Joust Bonus）** | 对头击杀（复用归因） | 本次 XP +50% |
| **直面 BVR（Stare Down）** | 被锁定时机头朝向锁定者 ±20° | 敌方锁定速率 ×0.5 |
| **冲撞免疫（Last Stand）** | HP < 20% 时对头击杀 | 回 +20 HP（每条命一次） |
| **决斗者（Duelist）** | 5 秒内只面对单个敌人 1v1 | 命中伤害 +25%；任何第三方介入打破 |
| **近距加成（Knife Fight）** | 机炮命中距离 < 400px | 暴击 ×1.5 |
| **低空王（Treetop King）** | LOW 高度持续 ≥10s | max_g +1，锁定时间 -20% |

---

## 恐惧 / 心理战系列（Fear/PsyWar）

利用 [pilot_personality.gd](../../scripts/pilot_personality.gd) 的 `stress` / `situational_awareness` 系统压迫敌方 AI 判断。
**关键约束**：恐惧效果对 simple_ai（Adds 杂兵 Tu-160/AH-64/CH-47）无效，因为它们没有 personality；对 BOSS 用 `FEAR_BOSS_STRESS_FACTOR=0.4` 削减。
现有基础设施：[survivor_spawner.gd](../../scripts/survivor/survivor_spawner.gd) `_trigger_gun_kill_fear()`。

### ✅ 机炮震慑（Gun Kill Fear）— `gun_kill_fear`

已实装。机炮击杀 → 周围半径内敌机 stress 注入 1.0（BOSS 0.4），decay 由升级层数决定。
3 层满级覆盖 2400px 半径。

### ⏳ 死神光环（Reaper Aura）

玩家附近持续辐射压力。
- 半径：800px（满级 1500px）
- 注入：每秒 +0.1 stress（线性累积，不上限直接堆到 1.0）
- 排除：BOSS / Adds / 玩家僚机
- 视觉：玩家周围一圈淡红色光晕，敌人进入时图标短暂抖动
- 实现：复用 `_trigger_gun_kill_fear` 的扫描逻辑改为周期 tick（建议 0.5s 一次，不要每帧）

### ⏳ 斩首吓阻（Decapitation Strike）

击杀敌方编队**长机**时，整个 squad 立刻 stress = 1.0 + 持续 5 秒内 SA 减半。
- 长机判定：`Aircraft.squad != null && squad_index == 0`
- 触发点：`_check_head_on_kill_bonus` 同处加扩展，读 victim 的 squad 引用，遍历 squad 成员注入
- 设计意图：奖励"先掐头"的战术选择，让一发导弹的价值放大

### ⏳ 对头威慑（Head-On Dread）

玩家机头持续指向某敌机 ≥ 1.5 秒（`atk_aim > 0.7`）→ 该敌机 stress 上升 0.05/秒。
- 目的：让"对头瞪眼"本身成为施压工具，配合骑士系列形成"瞪 → 打 → 杀"的连环奖励
- 实现：玩家每帧扫一次锁定锥内最高 atk_aim 的敌机，累加 timer

### ⏳ 战吼（War Cry）

规避模式开关切换瞬间释放一次脉冲，玩家半径 1200px 内敌机 stress = 0.6。
- 冷却 15s（防滥用）
- 设计意图：给规避模式额外一层主动控制价值，鼓励玩家在被群殴时主动切档反压

---

## EMP / 电子瘫痪系列（EMP）

短时间让敌方雷达 / 锁定 / 武器失效。本质是给敌方 Aircraft 加临时 meta 让 ai_controller / aircraft_weapons 检查后跳过。

**统一约束**：
- BOSS 抗性：EMP 时长 ×0.4（沿用恐惧系列的 `FEAR_BOSS_STRESS_FACTOR` 思路）
- Adds 免疫：`category=="adds"` meta 跳过
- 不能瘫痪僚机（team==0 跳过）
- 视觉：敌机被瘫痪期间图标外发蓝白电弧 + 雷达锥消失

**统一接入点（待实现）**：
```gdscript
# aircraft.gd
var emp_disabled_until: float = 0.0  # 全局时间戳
func is_emp_disabled() -> bool:
    return Time.get_ticks_msec() / 1000.0 < emp_disabled_until
```
- ai_controller.gd: `is_emp_disabled()` → 跳过雷达扫描 + 锁定累积
- aircraft_weapons.gd: `is_emp_disabled()` → 不开火（机炮 + 导弹）
- main.gd / survivor_mode.gd 雷达循环: 跳过该飞机的 lock 累积

### ⏳ EMP 弹头（EMP Warhead）

一颗专用导弹（不是常规弹的修饰），命中后**不**造成伤害，而是触发 AOE EMP：
- 半径：500px（爆炸点周围所有敌机）
- 时长：4s
- 玩家手动选择目标 + 发射；占用导弹挂架（需要专门的弹种参数）
- 设计意图：对付 BOSS / 高威胁单位（如 MiG-31 BVR 狙击）的反压牌

**实现思路**：新建 `MissileParams` 加 `is_emp: bool` + `emp_duration: float`，命中分支特殊处理。

### ⏳ EMP 脉冲（EMP Pulse）

主动技能。被锁定时按热诱弹键的"长按"释放：
- 立刻清除当前所有针对自己的导弹锁定（in-flight 导弹失去制导）
- 半径 1500px 内敌机 EMP 2 秒
- 冷却 30s，每场战斗有限次数（开局 2 次）
- 视觉：玩家机身爆出环形蓝白冲击波

**实现思路**：
- aircraft.gd 加 `emp_pulse_charges: int` + `emp_pulse_cooldown: float`
- input 层：长按 flare 键 0.5s 触发（避免误触）
- missile.gd: 检查发射者是否 emp_pulse 触发后丢失锁定 → `has_guidance = false`

### ⏳ EMP 区域（EMP Field）

击杀敌机的位置散播一个静态 EMP 云：
- 持续 8s，半径 400px
- 飞过的敌机被 EMP 2s
- 不影响友方
- 渲染：参考现有 `proximity_fuze` 的 AOE 区域绘制

**实现思路**：复用 missile_manager 的 `_aoe_zones` 列表，加 `is_emp` 标记，更新时不扣血只设 emp_disabled。

### ⏳ 想法占位

| 名称 | 触发 | 效果 |
|---|---|---|
| **过载射手（Overload Trigger）** | 玩家发射导弹时 5% 概率 | 该弹自带 EMP 副效果，命中后 1.5s 区域 EMP |
| **链式瘫痪（Chain EMP）** | EMP 中的敌机被击杀 | 半径 600px 再次释放 1.5s 短 EMP |
| **静默潜行（Silent Run）** | 玩家手动开"无线电静默" | 自身雷达关闭，但所有敌机对自己的锁定时间 ×2 |

---

## 环境 / 天气系列（Environment）

直接操纵已有的 [WeatherSystem](../../scripts/weather_system.gd) 全局云层，或在特定位置临时生成云团，用环境本身做战术资源。

### 现状回顾（已实现的环境互动）

| 升级 / 机制 | 效果 | 位置 |
|---|---|---|
| `cloud_lock_stealth`（`vapor_dodge` 战区奖励内含） | 玩家在云中被锁定速率 ×0.1 | [main.gd:243](../../scripts/main.gd:243) |
| 导弹云中丢制导 | 导弹进入云区域 → `has_guidance = false` | [missile.gd:83](../../scripts/missile.gd:83) |
| AOE 云中衰减 | 近炸引信 AOE 在云内伤害衰减 | [missile_manager.gd:192](../../scripts/missile_manager.gd:192) |

所有现有 hook 都通过 `WeatherSystem.sample_density(pos)` / `is_in_cloud(pos)` 查询。**任何"云"系扩展只要密度走这套接口，战斗逻辑零改动**。

### 性能基线（v2026.4.27 评估）

云系统**不在性能预算 top 20**，可放心扩展：
- 渲染：`REDRAW_INTERVAL = 0.12s` 即 8Hz，每次扫视口网格 60-100 个单元格、每格 ≤1 次 `draw_texture_rect`，约 800 draws/s
- 战斗查询：`is_in_cloud` 按单位缓存 0.3s（[combat_unit.gd:76](../../scripts/combat_unit.gd:76)），30 架飞机 ≈ 100 次噪声采样/s
- 启动烘焙：4 张 256² 贴图 ~200ms，一次性

### ⏳ 局部云团基础设施（Local Cloud Puffs）

**核心想法**：WeatherSystem 维护一个**局部云团数组**（独立于全局 noise），任何系统都可以调 API 在指定位置临时生成一片云。所有现有"云中效果" hook 自动复用。

**数据结构**：
```gdscript
# weather_system.gd
var _local_puffs: Array[Dictionary] = []
# 每个: { pos, radius_px, peak_density, age, lifetime, fade_in, fade_out, drift_vel, type }

func spawn_puff(pos: Vector2, radius: float = 600.0, lifetime: float = 8.0,
                peak_density: float = 1.0, fade_in: float = 0.4, fade_out: float = 2.0,
                type: String = "smoke") -> void
```

**接入点**：把现有 `sample_density(pos)` 改成全局 noise 与 puff 列表 max 合并：
```gdscript
func sample_density(world_pos: Vector2) -> float:
    var d := _global_density(world_pos)
    for p in _local_puffs:
        var r := p.pos.distance_to(world_pos)
        if r > p.radius_px: continue
        var falloff := 1.0 - r / p.radius_px
        var time_curve := _puff_envelope(p)  # fade_in → 平台 → fade_out
        d = maxf(d, p.peak_density * falloff * time_curve)
    return d
```

**渲染**：`_draw()` 在原网格扫描后再扫 `_local_puffs`，每个 puff 用同一 sprite atlas 撒 ~6 张贴图。30 puff 增量 ~1500 draws/s（仍在预算内）。

**风带漂移**：puff 创建时缓存 `wind_direction * wind_speed * PIXELS_PER_METER` 作为 drift_vel，每帧 `pos += drift_vel * delta`，符合"云被风吹走"的直觉。

**Puff 上限**：建议 20-30，超出按最旧 fade_out。

### ⏳ 触发场景（用上面的 spawn_puff）

| 场景 | 触发 | 参数 |
|---|---|---|
| **被命中烟幕脱身** | 玩家被导弹/火箭命中（dmg ≥ 8）| 玩家身后 400px，radius 700，lifetime 6s |
| **战场积烟** | 任意飞机爆炸 | 爆炸点，radius 400，lifetime 4s（短，不堆积过多）|
| **玩家烟雾弹技能** | 主动按键 | 玩家位置，radius 800，lifetime 12s，冷却 25s |
| **EMP 区域**（呼应 EMP 系列）| 击杀敌机 / 主动技能 | type="emp"，puff 内对穿过敌机注入 emp_disabled |
| **BOSS 入场云散** | F-47 BOSS 出现 | 反向应用 — 在 BOSS 周围 spawn 一个 negative puff（peak_density=-1.0）抵消全局云 |

### ⏳ "被命中→生成云"细节

[scripts/aircraft.gd](../../scripts/aircraft.gd) `_apply_damage` 玩家分支加：
```gdscript
const MISSILE_HIT_PUFF_THRESHOLD: float = 8.0  # 阈值，小擦伤不刷
if hp > 0.0 and is_player_aircraft() and amount >= MISSILE_HIT_PUFF_THRESHOLD:
    var weather := get_tree().get_first_node_in_group("weather")
    if weather and weather.has_method("spawn_puff"):
        var behind := -Vector2(sin(heading), -cos(heading)) * 400.0
        weather.spawn_puff(global_position + behind, 700.0, 6.0)
```

**设计意图**：被打中的玩家身后立刻有云，敌方导弹冲进去丢制导 → 鼓励"挨打 → 急转回头反咬"的攻防节奏。变成一种**被动型骑士技能**（不奖励对头本身，但奖励"被打了不跑反而回头"）。

### ⏳ 全局云调控（API 草案）

```gdscript
# weather_system.gd
func set_coverage(target: float, fade_seconds: float = 0.0)  # 阴/晴过渡
func set_wind(dir: Vector2, speed: float, fade_seconds: float = 0.0)
func set_tint(color: Color, fade_seconds: float = 0.0)       # 颜色（白/灰/夕阳/血红）
func reroll_clouds()                                          # 换 seed 洗牌云形态
```

**可玩出的效果**：
- 战区色彩：东京湾默认白云、火山区域偏暗红、北方雪区偏冷蓝（按 map_id 设 tint）
- BOSS 入场：F-47 出现时 5s 内 cloud_coverage 从当前值降到 0.15（云散开露出 BOSS）
- 长战压力：每场战斗 90 秒后 tint 渐变到夕阳橙

**唯一注意**：现在 `CLOUD_TINT` 是 const，要支持动态 tint 必须把它从烘焙挪到绘制层（`_draw_sprite_at` 里 `var c := tint * dynamic_tint`），否则每次变色要 rebake ~200ms 卡半秒。

### 推进决策

本段是**设计记录**，未实施。考虑推进时需要先决定：
1. 是只做"被命中生成云"这一个用例（最小切片），还是直接铺 `spawn_puff` 完整基础设施
2. 全局云调控（tint / coverage 动态化）和局部 puff 哪个优先 —— 前者影响地图叙事，后者影响战斗交互
3. EMP / 烟雾弹等技能是否准备同步落地（决定 `type` 字段是否要从 day 1 设计）

---

## 扩展约束

### 加新常规技能

1. 在 `SurvivorData.UPGRADES` 加条目（`id` / `name` / `desc` / `stat` / `value` / `max_stacks` / `category`）
2. 在 [survivor_player.gd](../../scripts/survivor/survivor_player.gd) `apply_upgrade()` 里加对应 `match` 分支处理 stat
3. 在 `i18n/translations.csv` 加 `UPGRADE_<ID>_NAME` / `UPGRADE_<ID>_DESC` 三语 key
4. 如果有硬件依赖填 `requires`，专属填 `exclusive_to`

### 加战区奖励技能

技能本身就是 `evolved: true`（这个字段名沿用历史，含义现在是"不进随机池"）。在战区任务奖励发放代码里挂权重。

### 不要再加进化技能

`evolves_to` 字段已弃用。后续清理代码时会移除。新技能不要走"基础满级 → 进化"的链式设计。

### 性能守则

- 每帧扫场景禁止 —— 复用 `BulletManager.combat_unit_list` 缓存
- 心理战 / EMP 类周期 tick 默认 0.5s 一次，不要每帧
- `_process` / `_physics_process` 默认 20Hz 起步（`tick_divisor ≥ 3`）
- 详见 [docs/reference/performance-guidelines.md](../reference/performance-guidelines.md)

### i18n 强制

所有玩家可见文本（升级名/描述/弹窗）必须走 `tr("KEY")`，硬编码中文会被翻译流程漏掉。

### 不污染规则

- 骑士 / 恐惧 / EMP 系列默认 `evolved: true`（不进随机池）
- 飞机专属技能用 `exclusive_to: ["<id>"]`，不要在 `apply_upgrade` 里写 `if aircraft_id == ...`
- 沙盒模式不应感知到任何升级 stat，所有逻辑挂在生存模式入口
