# 主角飞机制作工作流程（Playable Aircraft Workflow）

> 目标：把"加一个新的可玩主角"变成纯粹的 .tres 编辑工作 + 一行 PLAYABLE_LIST 追加。

## 一、系统概览

主角飞机由三层数据构成：

```
PlayableAircraft (.tres)             ← 档案：装载 base + 生存模式调味
  └─ base_params: AircraftParams (.tres)   ← 机体：物理 + 默认武器装填
        ├─ gun:  GunParams       (可空)
        ├─ rocket: RocketParams  (可空)
        ├─ missile: MissileParams (可空)
        ├─ secondary_missile: MissileParams (可空)
        ├─ flare: FlareParams    (可空)
        └─ combat: CombatParams  (可空)
  ├─ combat_override (可空)        ← 替换 base.combat
  ├─ flare_override  (可空)        ← 替换 base.flare
  └─ wingman_params (可空)         ← 起始僚机机型（可与主角不同）
```

加载流程（`survivor_mode.gd:_ready`）：

1. 从 `survivor_aircraft_resource` meta 读取 `PlayableAircraft` 路径
2. `_player_params_base = profile.base_params`
3. 实例化 `aircraft.tscn`，深拷贝 `base_params` 和所有子武器资源
4. `SurvivorPlayableSetup.apply(player_aircraft, profile)` 应用所有调味
5. 通用主角配置（HUD/扁平高度/战术面板）—— 与机型无关
6. 若 `wingman_count > 0`，调用 `_spawn_starting_wingmen(profile)`

## 二、武器系统是已经"灵活组装"的

**`aircraft.gd` 的所有武器代码都是 null-safe 的**——

| 字段 | 留空时的行为 | 关键检查行 |
|---|---|---|
| `gun` | 完全没有机炮，不会触发射击逻辑 | `aircraft.gd:1495` `1737` |
| `rocket` | 没有火箭弹，不进入火箭决策分支 | `aircraft.gd:1536` `1599` |
| `missile` | 没有主导弹，武器模式自动锁定 GUN | `aircraft.gd:1622` `1683` |
| `secondary_missile` | 没有副导弹，仅用主导弹 | `aircraft.gd:1963` |
| `flare` | 没有热诱弹，`AircraftFlares.release` 直接 return | `aircraft/aircraft_flares.gd:226` release |

**结论**：要给新机型不同的武器组合，**只需要调整 AircraftParams 上的字段是否为 null + 指向哪个 .tres**。无需改 aircraft.gd。

`AIController` 也只在一个地方读取武器（`ai_controller.gd:910` 取 `gun.max_range`）。所有 BFM 战术、规避、巡逻完全和武器无关。

### 武器组合示例

| 玩家概念 | gun | rocket | missile | secondary | flare |
|---|---|---|---|---|---|
| 现行 F-16 | M61A1 | — | AIM-7M | AGM | 30 枚 |
| 经典格斗机（F-86 风格） | M3 | FFAR | — | — | — |
| 纯机炮拦截机 | 加重型 | — | — | — | 大量 |
| 远程导弹卡车 | 弱机炮 | — | 远程 BVR | — | — |
| 多用途打地鸡 | — | — | AAM | AGM | 少量 |
| 无武器侦察机 | — | — | — | — | 大量 |

每一种都不需要改任何代码——加 .tres、设字段、塞进 PlayableAircraft.base_params 即可。

## 三、加一架新主角的完整步骤

### 步骤 1：准备机体物理参数 — `enemy_*.tres` 风格的 AircraftParams

```bash
resources/playable_<name>_base.tres   # AircraftParams
```

参考 `default_fighter.tres`。关键字段：
- `display_name` —— HUD 显示名（PlayableAircraft.codename 会附加副名）
- `max_hp` `armor` —— 生存性
- `max_speed` `cruise_speed` `acceleration` —— 速度系
- `max_g` `max_g_structural` `roll_rate` —— 机动系（用户列表里说的"结构 G 力 / 速度差异"就在这里）
- `radar_range` `radar_half_angle` `lock_time` —— 雷达
- `icon_color` —— 屏幕图标主色

### 步骤 2：准备武器 .tres（如有定制需求）

复用现有的 `default_gun.tres` / `default_missile.tres` / `rocket_ffar.tres` / `default_flare.tres` 通常就够了。

要新武器才创建：
```bash
resources/<name>_gun.tres       # GunParams
resources/<name>_missile.tres   # MissileParams
resources/<name>_rocket.tres    # RocketParams
resources/<name>_flare.tres     # FlareParams
```

把这些资源 ExtResource 进步骤 1 的 AircraftParams 的对应字段。**留空字段就代表"该机型没有这件武器"**。

### 步骤 3：（可选）准备战斗风格 / 热诱弹覆盖

如果你想让生存模式下的这架主角有特殊的 AI 战斗倾向（比 base 更激进/更保守），不要改 `base_params.combat`——而是新建一个 CombatParams .tres 作为 `combat_override`。这样 base 还能被沙盒模式或敌方 AI 复用。

```bash
resources/playable_<name>_combat.tres   # CombatParams（参考 playable_f16_combat.tres）
resources/playable_<name>_flare.tres    # FlareParams（参考 playable_f16_flare.tres）
```

### 步骤 4：创建 PlayableAircraft 档案

```bash
resources/playable_<name>.tres
```

最小骨架（参考 `playable_f16.tres`）：

```ini
[gd_resource type="Resource" script_class="PlayableAircraft" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/playable_aircraft.gd" id="1"]
[ext_resource type="Resource" path="res://resources/playable_<name>_base.tres" id="2"]

[resource]
script = ExtResource("1")
id = &"<name>"
display_name = "<显示名>"
codename = "<副名，可空>"
card_tags = PackedStringArray("特性1", "特性2", "特性3")
card_desc = "卡片描述..."
base_params = ExtResource("2")
# 默认所有 mult/bonus 为 0/1，不写就用默认值
# 想要生存模式特殊化时再加：
# max_speed_mult = 1.15
# max_g_bonus = 1.0
# missile_count_override = 4
# combat_override = ExtResource("3")
# flare_override  = ExtResource("4")
# wingman_count = 3
# wingman_params = ExtResource("5")
```

### 步骤 5：注册到选择界面

`scripts/survivor/survivor_select.gd` 顶部的 `PLAYABLE_LIST`：

```gdscript
const PLAYABLE_LIST: Array[Dictionary] = [
    { "resource": "res://resources/playable_f16.tres", "locked": false },
    { "resource": "res://resources/playable_<name>.tres", "locked": false },  # ← 解锁这一格
    { "resource": "", "locked": true, "slot_name": "??? / TBA", "slot_desc": "..." },
    { "resource": "", "locked": true, "slot_name": "??? / TBA", "slot_desc": "..." },
]
```

把第 N 个占位符的 dictionary 替换成新档案。卡片显示用的所有信息都从 `PlayableAircraft` 字段读取——不需要重复填写 name/tags/desc。

### 步骤 6：测试

1. F5 启动游戏 → 主菜单 → 生存模式 → 地图选择 → 机型选择
2. 检查卡片：名称、副名、标签、描述、属性栏是否正确
3. 点击出击 → 进入战场
4. 检查 HUD 标题栏（替换显示主角呼号 + display_name）
5. 检查武器：开火逻辑、装填、热诱弹（如有）
6. 若有起始僚机：检查阵型是否在玩家两侧/后方就位、是否跟随长机攻击

## 四、AI 行为如何随武器变化

> "因为初始武器不同，使用武器战斗时的 AI 表现会有所不同，但基本的转弯等操作是一致的"

这条**已经原生支持**，不需要任何额外代码：

- **基本转弯/能量管理**：`aircraft.gd:_physics_process` 物理层只看 `max_g` `roll_rate` `cruise_speed`——和武器无关
- **战术决策（BFM）**：`ai_controller.gd:_choose_tactic` 基于几何/能量/角度，不读武器类型
- **武器射程**：`gun_range_px` 在 `ai_controller.gd:910` 直接从 `gun.max_range` 读，没有 gun 时为 0
- **导弹发射时机**：`aircraft.gd:_update_missile`（行 1811 起）读 `missile.max_range_rear` 和 `min_range`，导弹换型只需替换 .tres
- **武器模式切换**：`aircraft.gd:_update_weapon_mode` 自动根据 missile 是否存在/弹量决定 GUN ↔ MISSILE，无 missile 时永远 GUN
- **机会射击宽容度**：通过 `combat.opportunity_cone_mult` `opportunity_range_mult` 调，不在代码里

要专属定制 AI 倾向，**改 `combat_override`** 而不是改代码。例如要做"放风筝型"：

```ini
combat_override.intercept_range_mult = 4.0   # 长射程死守拦截位
combat_override.combat_bank_aggression = 0.7 # 不极限机动
combat_override.approach_speed_mult = 1.2    # 慢速接敌
```

## 五、热诱弹/规避行为差异

> "躲避导弹和使用热诱弹的功能也可能不同，有的飞机初始可能没有配备热诱弹"

这条也是原生支持的：

- **没有热诱弹**：`PlayableAircraft.base_params.flare = null` 即可。`aircraft.gd:_release_flares` 早 return，AI 仍会进入 EVADE_MISSILE 状态做急转规避，但不会撒诱饵
- **不同释放性格**：FlareParams 的 `nervousness` `panic_distance` `calm_distance` 控制
- **不同干扰率**：`base_jam_chance` `aspect_bonus` `maneuvering_bonus` `close_range_penalty`
- **不同弹量/连发**：`max_flares` `burst_count` `cooldown`
- **生存模式 100% 干扰**：`flares_guaranteed = true` 即可（PlayableAircraft 字段）
- **耗尽自动装填**：`enable_flare_reload = true`

## 六、起始僚机（小队主控型主角）

`PlayableAircraft.wingman_count > 0` 时，`survivor_mode._spawn_starting_wingmen` 会：

1. 创建 `Squad`，玩家为长机（`squad_index = 0`）
2. 实例化 N 架僚机，使用 `wingman_params`（缺省 = `base_params`）
3. **对每架僚机调用 `SurvivorPlayableSetup.apply(ac, profile, true)`**（is_wingman=true），起始属性与长机完全一致——同样的雷达倍率、武器覆盖、热诱弹、伤害上限、闪避率等
4. 按 `Squad.get_formation_offset(i)` 在玩家周围摆位（默认 FINGER_FOUR 阵型）
5. 给每架僚机挂 `AIController`，状态为 `SQUAD_FOLLOW`
6. AI 倾向参数从 `wingman_aggression_min/max` 和 `wingman_skill_min/max` 随机

### 6.1 僚机与长机的差异

| 维度 | 长机（玩家） | 僚机 |
|---|---|---|
| 起始属性（雷达/速度/G/武器/伤害上限/闪避） | apply(profile) | apply(profile, true) — 与长机完全一致 |
| display_name | "F-14 TopGun"（带 codename） | "F-14"（无 codename） |
| 升级（leveled_up） | 全部生效 | 完全不受影响（仅作用于 `survivor_player.aircraft = leader`） |
| 玩家点击命令 | 直接接收 | 不接收，靠 SQUAD_FOLLOW 跟随 |
| HUD 标签 | 简化版（5 行） | 完整版（10+ 行） |
| 战术偏好按钮（1/2/3/4/E/F） | 生效 | 不生效 |

**核心思路**：起始时是 N+1 架完全相同的飞机；玩家通过升级让长机逐渐拉开差距。

**僚机 NOT 加入 `selected_aircraft`**——玩家点击只命令长机，僚机靠 SQUAD_FOLLOW 自主交战。这是"小队主控"的标准语义。如果要做"一键全队进攻"的群控，可以在 `_screen_to_world_click` 里把僚机也算上。

**僚机不会因为玩家死亡自动消失**，目前会进入 PATROL 状态游离。需要的话可以扩展死亡处理。

### 6.2 为什么 apply() 对僚机也调用？

因为 `PlayableAircraft.base_params` 是"裸"参数（沙盒模式 / 敌机也可以复用），生存模式特有的调味（雷达 1/3 cut、伤害上限、闪避率等）写在 `PlayableAircraft` 的 mult/override/flag 字段里。如果僚机只 duplicate base_params 而不 apply()，它们就会拿到沙盒级别的属性（比如完整 radar_range = 3500），与生存模式的玩家不对齐。`apply(ac, profile, true)` 是把"生存模式调味"统一刷到长机和僚机上的入口。

## 七、调试技巧

- 卡片数据看不到：检查 PlayableAircraft 的 `script_class` 和 ExtResource 路径是否正确
- 进游戏后 display_name 没变：`SurvivorPlayableSetup.apply` 用 `display_name.split(" ")[0]` + `codename` 组合；如果你的 display_name 含中文空格，splitter 可能不符合预期，简化为 `aircraft.params.display_name = profile.display_name + " " + profile.codename`
- 武器没生效：在 godot 编辑器里打开 `playable_<name>_base.tres`，手动确认每个武器槽都连接到了 .tres
- 起始僚机没出现：确认 `wingman_count > 0`，且 `_spawn_starting_wingmen` 在 `add_child(player_aircraft)` 之后被调用
- 升级会破坏数据：survivor 模式下所有外部子资源都被 `SurvivorPlayableSetup.deep_dup_weapons` 深拷贝，升级修改不会反污染原 .tres

## 八、升级分类与筛选

生存模式的升级表（`SurvivorData.UPGRADES`）支持三层分类，让不同主角获得不同升级池：

### 8.1 三种字段

每条 UPGRADES 条目可加两个可选字段：

| 字段 | 类型 | 含义 | 示例 |
|---|---|---|---|
| `requires` | 字符串数组 | 必须的硬件标签，缺一即不可用 | `["gun"]` `["missile","flare"]` |
| `exclusive_to` | 字符串数组 | 仅指定 PlayableAircraft.id 可获得 | `["f14"]` `["f16","f14"]` |

`requires` 支持的硬件标签：
- `"gun"` —— 飞机必须 `params.gun != null`
- `"missile"` —— 飞机必须 `params.missile != null`
- `"flare"` —— 飞机必须 `params.flare != null`
- `"rocket"` —— 飞机必须 `params.rocket != null`

字段缺失时的语义：
- `requires` 缺失/空 → 无硬件要求（任何机型都可获得）
- `exclusive_to` 缺失/空 → 通用升级（所有机型可获得）

### 8.2 三类升级

| 类别 | requires | exclusive_to | 例子 |
|---|---|---|---|
| **通用基础** | 缺 | 缺 | `hp_up`（装甲）`speed_up`（引擎）`maneuver_up`（飞控）`pilot_stamina`（体能）`kill_heal`（战场急救）`radar_range`（雷达升级）`lock_time`（火控）`dogfight`（格斗大师）|
| **硬件依赖** | 有 | 缺 | `gun_*` 系列（要求 gun）`missile_*` 系列（要求 missile）`flare_cooldown` `flare_shield`（要求 flare）|
| **机型专属** | 任意 | 有 | （F-14 的专属升级待用户后续定义；模板见下） |

### 8.3 筛选入口

唯一的判定函数：

```gdscript
SurvivorData.is_upgrade_available_for(upgrade, aircraft_id, params) -> bool
```

调用点：
- `survivor_mode.gd::_on_player_leveled_up` —— 升级抽卡时筛选
- `survivor_debug_skills.gd::_refresh` —— F4 调试面板的"添加技能"下拉

新代码涉及升级随机/列表时务必走这个 helper，**不要直接遍历 UPGRADES 然后只看 max_stacks**。

### 8.4 加机型专属升级模板

```gdscript
# 在 SurvivorData.UPGRADES 末尾追加：
{
    "id": "f14_phoenix_volley",
    "name": "★ AIM-54 齐射",
    "desc": "F-14 专属！发射 AIM-54 时同时射出 2 发",
    "stat": "f14_phoenix_volley",
    "value": 1,
    "max_stacks": 1,
    "category": "combat",
    "exclusive_to": ["f14"],
    "requires": ["missile"],
},
```

然后在 `survivor_player.gd::apply_upgrade` 的 `match stat:` 里加对应分支处理副作用。专属升级与通用升级共用同一个 `apply_upgrade` 方法，stat 字符串区分即可。

### 8.5 排除规则的两个例子

**例 A：F-14 没有副导弹挂架**

将来如果某机型 `params.secondary_missile = null`，需要为 secondary_missile 类升级（如果加的话）打 `requires: ["secondary_missile"]`。需要先把 `is_upgrade_available_for` 的 match 里加上 `"secondary_missile"` 分支。

**例 B：F-86 没有制导导弹**

如果加一架 F-86 主角（只有机炮+火箭弹，无导弹无热诱弹）：
- `params.missile = null`、`params.flare = null`
- 升级池自动剔除所有 `requires: ["missile"]` 和 `requires: ["flare"]` 的条目
- F-86 主角只会 roll 到通用升级 + 机炮升级 + 火箭弹升级（如果加的话）
- 无需修改任何 UPGRADES 条目

## 九、加新主角的"触发短语"清单

为防止改文件时漏掉关键步骤，"加一个主角"应同步：

1. `resources/playable_<name>_base.tres` (AircraftParams)
2. （如有）`resources/<name>_gun.tres` / `<name>_missile.tres` / `<name>_rocket.tres` / `<name>_flare.tres`
3. （如有）`resources/playable_<name>_combat.tres` (CombatParams override)
4. （如有）`resources/playable_<name>_flare.tres` (FlareParams override)
5. `resources/playable_<name>.tres` (PlayableAircraft) ← 主档案，**记得设 `id = &"<name>"`**
6. `scripts/survivor/survivor_select.gd::PLAYABLE_LIST` 追加/替换条目
7. （如有专属技能）在 `SurvivorData.UPGRADES` 末尾追加专属条目，`exclusive_to = ["<name>"]`
8. （如有专属技能）在 `survivor_player.gd::apply_upgrade` 的 `match stat:` 中加对应分支
9. （如新文件较多）更新 `docs/playable-aircraft-workflow.md` 的"现有主角清单"
10. （重大变更）更新 `CLAUDE.md` Script Index

**完全不需要改的**：
- `aircraft.gd`（武器是 null-safe 的）
- `ai_controller.gd`（战术与武器解耦）
- `survivor_mode.gd`（loader 已经数据驱动；筛选走 `is_upgrade_available_for`）
- `bullet_manager.gd` / `missile_manager.gd`

## 十、现有主角清单

| ID | 显示名 | 档案 | 武器 | 起始僚机 | 备注 |
|---|---|---|---|---|---|
| `f16` | F-16C Block 50 / SmartFalcon | `playable_f16.tres` | M61A1 / AIM-7M ×2 / 热诱弹 ×2 | 0 | 入门均衡，全属性强化 |
| `f14` | F-14A Tomcat / TopGun | `playable_f14.tres` | M61A1（半弹） / AIM-54 ×1 / 热诱弹 ×1 | 3 | 小队主控，单机弱依赖编队 |
| `a10` | A-10 Warthog | `playable_a10.tres` | GAU-A 加强机炮 / Hydra 70 火箭弹（无限弹/手动 KEY_R 平行齐射 6 发）| 0 | 实验机型：玩家手动 RKT 入口，无导弹/无热诱弹/重装甲 |
