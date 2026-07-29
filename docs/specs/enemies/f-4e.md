---
id: f-4e
kind: enemy
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 3
owner: user + Claude
depends_on: [early-game-uav-rework]
reconstruction_complete: true
---

# F-4E —— 前期导弹杂鱼（有人机）

> 比 MQ-109 强一点点的最初期敌机：会打导弹、没有机炮，本质仍是杂鱼。
> 单机或 2-3 机小队出现，作用是填补前期地图空间——让开局不是满屏无人机。

## 1. 设计意图（Why）

- **体验目标**：游戏最初期（Lv1 起）如果满屏都是 MQ-109/MQ-110 无人机会显得很不自然。
  F-4E 提供"第一种有人敌机"：有无线电、有呼号、给玩家看到导弹来袭线，
  但威胁刻意压低——它就是杂鱼，一发死，导弹是它唯一的牌。
- **与 MQ-110 的关系（v2 订正）**：MQ-110（导弹无人机）**保留并存**，两者不冲突——
  MQ-110 是无人机导弹杂鱼、F-4E 是有人机导弹杂鱼，前期空域由三者混编构成。
- **与既有 F-4 Phantom 的关系**：EnemyType.F4（"F-4 Phantom"，Lv6 解锁的 Gladiator
  导弹卡车）**保留不动**。F-4E 是另一个独立敌人：老旧出口型定位，前期杂鱼。
  两者共存不冲突——前期见 F-4E（弱），中期见 F-4 Phantom（强），玩家读得出梯度。
- **Litmus 自检**：
  - 一击毙命：HP 45 < ENEMY_HP_MISSILE_CAP(75)，任何导弹/电磁炮一发解决 ✅
  - 信息察觉：与 MQ-109 的区别肉眼可见——战机轮廓 + 导弹尾迹 + 有无线电台词 ✅
  - 数值区间：速度 1700 km/h ∈ [600, 2200]；无伤害数值（导弹走 V-tier 表）✅
  - 敌机参考：真实 F-4E ~2370 km/h → 取中间值 1700（前期杂鱼定位压低，
    保留"平飞快、盘旋笨"的 Phantom 灵魂）✅
  - AI 演戏：低技袍杂鱼——凑近、放弹、笨拙再进入；不做新战术 ✅
- **反模式规避**：不做 HP 海（45）；不做暗 buff；机炮明确不挂（用户指令），
  不是"删了机炮参数但行为像有机炮"。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 基础属性（enemy_f4e.tres / AircraftParams）

| 字段 | 值 | 说明 |
|---|---|---|
| display_name | `F-4E` | |
| is_unmanned | false（默认） | **有人机**：吃 FEAR、配无线电、呼号走 CallsignDB |
| max_hp | 45.0 | 比 MQ-109(40) 略高；一发死 |
| max_speed | 1700.0 | 平飞快（Phantom 灵魂），前期杂鱼压低取值 |
| cruise_speed | 850.0 | |
| stall_speed_base | 230.0 | 重机身 |
| acceleration / deceleration | 35.0 / 55.0 | 加速迟钝 |
| g_drag_factor | 3.2 | |
| max_g / max_g_structural | 6.0 / 8.0 | 盘旋差（比 F-4 Phantom 的 6.5 再低半档） |
| roll_rate | 2.2 | |
| pilot_stamina / drain / recovery | 80 / 28 / 8 | 与 F-4 Phantom 同 |
| max_altitude / climb_rate_max | 15000 / 180 | |
| thrust_to_weight | 0.85 | |
| drag_coefficient | 0.030 | |
| afterburner_thrust_mult | 1.5 | |
| fuel_capacity / normal / ab | 2800 / 2.1 / 11.0 | 敌机 infinite_fuel，摆设 |
| radar_range | 4200.0 | 弱于 F-16 基准 5000（前期杂鱼，设计上"雷达弱"）|
| radar_half_angle | 30.0 | |
| lock_time | 2.6 | 比无人机（MQ-110 lock 1.0）迟钝，玩家有反应窗口 |
| gun | **无** | 用户硬性指令：F-4E 没有机炮 |
| missile | default_missile.tres（占位） | 运行时被敌方武器 V-tier 注入覆盖，见 §3.2 |
| flare | **无** | 用户订正（v3）：初始敌机不带热诱弹——玩家导弹必中，见 §3.3 |
| combat | default_combat.tres | |
| icon_color | Color(0.85, 0.55, 0.25, 1) | 暖橙（阵营色板：威胁=暖色域） |

### 2.2 刷怪经济（survivor_data / survivor_spawner）

| 项 | 值 | 说明 |
|---|---|---|
| EnemyType | `F4E`（枚举末尾追加，int=23） | |
| TOKEN_COST | 2 | 与 MQ-110 同价位并存 |
| TOKEN_INSTANCE_CAP | -1 | 无上限 |
| F4E_UNLOCK_LEVEL | 1 | 最初期即出 |
| F4E_RETIRE_LEVEL | 6 | 比 MQ-109（UAV_RETIRE_LEVEL=4）晚两级退场，衔接 F-86/A-7 |
| F4E_CHANCE | 0.40 | 前期兜底层平坦概率（不随级爬升——杂鱼不该越来越多） |
| F4E_SINGLE_CHANCE | 0.35 | 单机出现概率；其余走 2-3 机小队 |
| ENEMY_TIER_OFFSET | -1 | 与 MQ-110 同档：武器永远比同级 MiG 弱一截 |
| 击杀 XP | XP_PER_KILL_F4E = 32（+level×8） | MQ-109(25) 与普通机(40) 之间 |
| 等级缩放 | enemy_scale_for_level（载人战机组） | HP 受 75 上限压制 |
| 战区敌人池 | {unlock 1, peak 2, retire 7, base_weight 1.4} | 与 MQ-110 行并存 |
| 无线电 | voiced_enemy_types 加 `f4e` | 有人机开口（spec radio-chatter §2.8 opt-in） |

## 3. 行为与公式（How）

### 3.1 AI 配置（_create_enemy F4E 分支）

低技袍杂鱼：贴近 → 放导弹 → 笨重再进入。不 joust、不规避导弹。

| 参数 | 值 |
|---|---|
| evade_missiles | false（杂鱼，一发死是设计约定） |
| aggression | randf(0.5, 0.7) |
| engage_cooldown / engage_duration | 4.0 / 25.0 |
| skill_level | clamp(randf(0.25, 0.45) + lvl/20 ≤0.2, …, 0.65) |
| composure | clamp(randf(0.2, 0.4) + 同上, …, 0.6) |
| focus | clamp(randf(0.35, 0.55) + 同上×0.5, …, 0.7) |
| self_preservation | randf(0.3, 0.5) |
| situational_awareness | randf(0.3, 0.5) |

### 3.2 武器

- **导弹**：.tres 里挂 default_missile 仅作占位标记"这机有导弹槽"；
  `_inject_weapon_tier` 按 `玩家等级基线 + 偏移(-1)` 换成 `enemy_missile_vN`。
  Lv1-2 玩家 → V1 弹（基线1，偏移-1 后 clamp 到 1）。
- **机炮**：无。gun 槽为空 → tier 注入自动跳过。
- 弹药走敌机统一规则：有限弹匣 + missile_reload_duration 20s（默认档）。

### 3.3 热诱弹

**无**（v3 用户订正）。F-4E 是初始敌机：玩家的第一发导弹就该命中，不设任何对抗。
与 MQ-109/MQ-110 一致（三种前期杂鱼均无 flare）；热诱弹从 F-86（Lv2，fail 0.65）
起才进入敌机梯度——"学会应对 flare"是第二级课程，不放在第一课。

### 3.4 生成形式

- `_pick_enemy_type`：F-4E 判定块放在 F-86 之后、MQ-109 兜底之前
  （lvl ∈ [1, 6] 且预算够 → roll 0.40）。
- 单机 or 小队：roll `F4E_SINGLE_CHANCE(0.35)` 走 `_spawn_single`，否则 2-3 机
  `_spawn_squad`。**单机是 squad-cohesion "杂鱼一律成建制" 规则的显式例外**
  （用户指令："既可以单架出现，也可以以小队方式出现"——填空间的孤机）。
- 战区驻守/中队池：走 ZONE_ENEMY_TABLE 正常抽取（cost 2 → 4 机杂鱼群档）。

## 4. 结构与组成（Structure）

- 普通 Aircraft + AIController（TacticalPlanner 路径），无专属子控制器/overlay。
- 轮廓：默认战机图标（不设 silhouette meta）。
- 呼号：CallsignDB 正常分配（非 UAV 序号制）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] Lv1 开局能遇到 F-4E（单机与小队两种形式都能观察到）
- [ ] F-4E 全程不开机炮（无 gun 槽）、不投热诱弹（无 flare 槽），会发导弹；被玩家导弹命中一发死且无对抗
- [ ] Lv7+ 后 F-4E 不再随机出现（retire 生效）
- [ ] 击杀 XP 32+8×lvl 入账；有无线电台词（交战/被锁触发）
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（复用既有刷怪链，无新每帧逻辑）
- [ ] i18n：无新玩家可见 UI 文本（display_name 豁免；debug 面板中文标签例外惯例）

## 6. 实现计划（Task Pipeline）

- [x] 建 enemy_f4e.tres（§2.1 全表）
- [x] EnemyType 枚举 + `_f4e_params_base` + preload
- [x] survivor_data：F4E_* 常量 + TOKEN_COST/CAP + ENEMY_TIER_OFFSET + ZONE_ENEMY_TABLE 行
- [x] `_pick_enemy_type` 判定块 + `_update_spawner` 单机/小队分流
- [x] `_create_enemy`：base_params / 缩放组 / type_tag / AI 分支（v3：flare fail 分支已随热诱弹一并移除）
- [x] radio_chatter.json voiced 白名单 + debug 面板标签
- [x] enemy-index / code-index / resources-catalog 同步
- [ ] playtest：出现率手感 / 导弹威胁强度 / 单机比例

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 参数资源 | `resources/enemy_f4e.tres` |
| 枚举/刷怪/工厂 | `scripts/survivor/survivor_spawner.gd`（EnemyType / _pick_enemy_type / _create_enemy） |
| 常量 | `scripts/survivor/survivor_data.gd`（F4E_* / TOKEN_COST / ZONE_ENEMY_TABLE） |
| 无线电白名单 | `resources/chatter/radio_chatter.json` voiced_enemy_types |
| 调试面板 | `scripts/survivor/survivor_debug_spawn.gd` ENEMY_TYPE_LABELS |
| reference 索引行 | enemy-index.md Enemy Index 表 F4E(23) 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-26 | 1 | 初稿 + 落地（用户指令：前期导弹杂鱼/无机炮/单机+小队；数值待 playtest） |
| 2026-07-26 | 2 | 用户订正：MQ-110（原 UCAV）不退役、与 F-4E 并存——F-4E 不再"顶替"任何生态位，定位收敛为"第一种有人敌机" |
| 2026-07-26 | 3 | 用户订正：**去掉热诱弹**——初始敌机不设对抗，玩家导弹必中（与 MQ-109/MQ-110 一致；flare 梯度从 F-86 起步） |
