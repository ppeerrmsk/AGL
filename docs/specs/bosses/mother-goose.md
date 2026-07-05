---
id: mother-goose
kind: boss
status: done
schema_version: 1
spec_version: 1
owner: design
depends_on: [jam-status, vls-salvo, uav-swarm-roles]
reconstruction_complete: true
---

# Mother Goose（飞行翼无人母舰 BOSS）

> 一架巨型无人飞行翼"空中航母"：正面绝对免疫，玩家必须绕后逐个打掉 10 个挂点暴露核心；
> 全程被 UAV 蜂群、周期性 JAM 力场、指定猎杀、VLS 导弹齐射压制。定位：阵地攻坚 + 走位惩罚。

## 1. 设计意图（Why）

- **体验目标**：把"狗斗"切换成"攻坚"。玩家不能正面莽，必须读 boss 朝向、绕到尾后扇区、在
  JAM/指定窗口之间见缝插针拆挂点。节奏是"压制波 ↔ 输出窗口"的呼吸感。
- **Litmus 自检**（docs/DESIGN_PHILOSOPHY.md）：
  - 玩家有明确的"正确解法"（绕后 + 打挂点），且解法可被走位执行 → 通过"可读可解"测试。
  - 所有压制都有预警相（WARNING）和逃逸窗口（EXPANDING）→ 通过"惩罚先给预告"测试。
- **反模式规避**：不堆 HP 当难度（核心只有 800 HP，难度来自"够不够得到核心"而非数值海绵）；
  正面 0× 免伤不是隐形墙，而是有清晰几何规则（朝向扇区）可被玩家学习。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 本体基础属性（AircraftParams）

| 字段 | 值 | 字段 | 值 |
|---|---|---|---|
| is_unmanned | true | max_hp | 3000.0 |
| armor | 0.0 | max_speed | 280.0 km/h |
| cruise_speed | 200.0 km/h | stall_speed_base | 80.0 km/h |
| acceleration | 8.0 | deceleration | 12.0 |
| g_drag_factor | 0.5 | max_g | 1.5 |
| max_g_structural | 2.0 | roll_rate | 0.4 |
| pilot_stamina | 100.0 | stamina_drain_rate | 0.0 |
| stamina_recovery_rate | 100.0 | max_altitude | 8000.0 |
| climb_rate_max | 30.0 | thrust_to_weight | 0.20 |
| drag_coefficient | 0.04 | afterburner_thrust_mult | 1.0 |
| fuel_capacity | 99999.0 | fuel_rate_normal / ab | 0.0 / 0.0 |
| radar_range | 2500.0 px | radar_half_angle | 90.0° |
| lock_time | 99.0 s | icon_color | (0.92, 0.92, 0.95, 1) |
| wing_color | (0.78, 0.80, 0.85, 1) | | |

**身份/接线**：display_name `Mother Goose` · callsign 前缀 `GOOSE` · team 1 · 巡航高度 5500 px（MID 中段）·
silhouette meta `mother_goose`（按 9× 战斗翼图标渲染）· 初始 heading 90°（北）· 出生点 anchor 或地图中心。

**3000 HP 的来源（守恒校验）**：HP 不是一个独立海绵，而是子系统 HP 之和 ——
`8 × 200(螺旋桨) + 2 × 350(VLS) + 800(弱点) = 3000`。血条按剩余子系统 HP 实时同步。

### 2.2 子系统挂点（10 个，本体暴露弱点前不可锁定）

| # | 类型 | 本地偏移 px | HP | 显示符 |
|---|---|---|---|---|
| 0–7 | 螺旋桨 PROP | x=-63，y ∈ {-143,-103,-62,-21,+21,+62,+103,+143} | 200.0 | P |
| 8 | VLS | (-15, -27) | 350.0 | V |
| 9 | VLS | (-15, +27) | 350.0 | V |
| 弱点 | 核心 CORE | (0, 0) 中心 | 800.0 | — |

弱点参数：HP 800、命中半径 220 px。命中判定半径：距最近挂点 400 px 内才算击中挂点。

### 2.3 受击角度免伤（所有挂点共用）

| 攻击向量 vs boss 机头夹角 | 区 | 伤害倍率 |
|---|---|---|
| 0–60°（FRONT_CONE） | 正面锥 | **0.0×**（完全免疫） |
| 60–120°（SIDE_CONE） | 侧面 | **0.3×** |
| 120–180° | 尾后 | **1.0×**（满伤） |

夹角 = `acos(forward · normalize(hit - pos))`，clamp 到 [0,180°]。

### 2.4 JAM 力场（60s 周期状态机）

| 状态 | 时长 | 半径 | 效果 |
|---|---|---|---|
| COOLDOWN | 40.0 s | — | 无 |
| WARNING | 4.0 s | 固定 300 px（黄圈预警） | 无 gameplay 效果，纯视觉 |
| EXPANDING | 8.0 s | 300 → 1500 px lerp（橙） | 逃逸窗口，仍无效果 |
| SUSTAIN | 8.0 s | 1500 px（红） | 全效：见下 |

SUSTAIN 全效（仅作用 team 0 玩家，boss/UAV 免疫）：
- 每帧施加 `JAM`（武器锁定/开火失效）+ `SLOW`，刷新时长 0.5 s
- 玩家速度上限 ×0.6（且硬 cap 350 km/h）
- 场内伤害 5.0 DPS

### 2.5 指定猎杀 Designation（180s 周期状态机）

| 状态 | 时长 | 效果 |
|---|---|---|
| COOLDOWN | 180.0 s | 无 |
| WARNING | 3.0 s | boss→玩家红色牵引线预警 |
| ACTIVE | 15.0 s | 全体敌机强制锁玩家；GUARD UAV 临时转 HUNTER；30% hunter 前出 2400 px 设伏 |

ACTIVE 细节：所有 team 1 强制 `current_target = player`；GUARD→HUNTER 时
`aggression=1.0, self_preservation=0.05, combat_zone_radius=99999`；**例外** MQ-111 激光机保持 guard 做对空；
拦截分队 = 30% 活跃 hunter，置于玩家前方 2400 px。

### 2.6 VLS 齐射

| 参数 | 值 |
|---|---|
| 齐射间隔 | 20.0 s |
| 每 VLS 弹数 | 4 |
| 单发间隔 | 0.25 s |
| 目标 | 当前玩家 |
| 散布 | ±25°（is_vls_salvo） |
| 弹种 | `cg_vls_missile.tres`（naval） |

每次齐射 = 存活 VLS 数 × 4 发。两个 VLS 都活时 = 8 发/轮。

### 2.7 UAV 蜂群

| 参数 | 值 |
|---|---|
| 初始数 | 12 |
| 上限 | 30 |
| 补充批量 | 2 / 间隔 |
| 补充间隔 | 12.0 s |
| 出生半径（绕 boss） | 250 px |
| Hunter 牵引半径 | 4500 px（超出回收） |
| 远距剔除距离 | 距玩家 3500 px 且离屏（+400 px 余量），每 5 s 检查 |
| 迷途召回 | 距 boss 5000 px 且无目标 → 每 4 s 强制返航 |

四变体（加权随机）：

| 变体 | 武器 | 资源 | 权重 | 存活上限 | standoff |
|---|---|---|---|---|---|
| MQ-109 | 机炮 | `enemy_uav.tres` | 45% | — | 近战 |
| MQ-110 | 导弹 | `enemy_uav_missile.tres` | 25% | — | 1500 px |
| MQ-111 | 激光 | `enemy_uav_mg_laser.tres` | 15% | **2** | 0（贴身对空） |
| MQ-112 | 电磁炮 | `enemy_uav_railgun.tres` | 15% | — | 2000 px |

角色分配：MQ-110/112 恒 HUNTER；MQ-111 恒 GUARD（对空，`no_kamikaze`）；
MQ-109 按 50% 概率 GUARD / 50% HUNTER。
- **GUARD**：orbit boss + 拦截来袭导弹（shield_leader）；engage_cd 1.5s / duration 30s；aggression 0.7–0.95
- **HUNTER**：追玩家；engage_cd 0.5s / duration 60s；aggression 0.95；evade_missiles=true

### 2.8 MQ-X 精英对（一次性，boss HP ≤ 50% 触发）

| 参数 | 值 |
|---|---|
| 触发 | boss 总 HP < 50%（一次性，`_mqx_spawned` 标记） |
| 数量 | 2（队长 + 僚机，共享 Squad） |
| 资源 | `enemy_uav_mqx.tres` |
| 出生位 | boss 左右翼 ±500 px |
| 牵引半径 | 7000 px |
| 侧翼偏移 | ±600 px |
| AI | engage_cd 0.3s / duration 120s；aggression 1.0；skill 0.90；composure 0.85；focus 0.95；纯狗斗 standoff=0 |

## 3. 行为与公式（How）

### 3.1 攻坚流程（玩家解法 = 设计意图的几何实现）

1. boss 八点环形巡逻（半径 `max(4000, 地图半宽-1500)`，高度 5500，`enable_combat=false`——本体不主动开火，靠 UAV+力场+VLS 施压）。
2. 本体 `lock_immune_override=true`，玩家**锁不上本体**，只能打 10 个挂点（绕到 120–180° 尾扇区才满伤）。
3. 全部 10 挂点摧毁 → `weak_point.revealed=true` + 清除锁定免疫 → 暴露 800 HP 核心。
4. 核心 HP ≤ 0 → boss 死亡，`active=false`，encounter 完成。

### 3.2 三条压制时间线并行（互不同步，各自独立周期）

- JAM 力场：60s 周期（40 cd → 4 warn → 8 expand → 8 sustain）
- 指定猎杀：180s 周期（180 cd → 3 warn → 15 active）
- VLS 齐射：每 20s 一轮
- UAV 补充：每 12s 补 2，封顶 30

### 3.3 伤害路由

挂点不是独立 CombatUnit，伤害经 `MotherGooseController.route_damage`：命中点 → 找 400px 内最近挂点 →
按 §2.3 角度倍率结算 → 扣该挂点 HP → 同步 boss 血条。本体直接受击在弱点暴露前被 lock_immune 挡掉。

## 4. 结构与组成（Structure）

boss 节点挂载：`AIController`（巡逻+雷达）、`MotherGooseController`（状态机/JAM/VLS/UAV 管理/伤害路由）、
`CommanderAura` + `CommanderOverlay`（对 UAV 的 buff 光环 ~1500px）。

scene_root 下独立子节点：`MotherGooseShieldOverlay`（JAM 圈）、`MotherGooseDesignationOverlay`（牵引线）、
12–30 架 UAV `Aircraft`、0–2 架 MQ-X、10 个 `MountTarget`（挂点+弱点的锁定代理，deferred 生成）。

> ⚠ MountTarget 必须留在 `all_units`（见 known-seams：玩家锁挂点依赖 radar_targets 累积，摘出会彻底锁不上）。

关键 meta：`enemy_type=mother_goose` · `category=boss` · `skip_far_cleanup=true` · `lock_immune_override`（弱点暴露后转 false）·
`fear_immune=true`（无人机无飞行员）· `damage_router`（指向 Controller）· `mg_mounts`（挂点列表，供渲染跳过）。

BGM：循环歌单 `["boss_mothergoose_1", "boss_mothergoose_2"]`（优先于 bgm_track）。

## 5. 验收标准（Acceptance / Litmus）

- [x] 正面攻击 boss 任意挂点 0 伤害；尾后满伤；侧面 0.3×
- [x] 10 挂点全毁前本体锁不上；全毁后核心可锁可击杀
- [x] JAM SUSTAIN 内玩家被 JAM+SLOW、限速、吃 5 DPS；WARNING/EXPANDING 有逃逸窗口
- [x] 指定 ACTIVE 内全体敌机锁玩家、GUARD 转 HUNTER、前方设伏
- [x] HP 跌破 50% 恰好一次性刷 2 架 MQ-X
- [x] 性能：UAV 30 上限 + 远距剔除 + 迷途召回生效，Lv5+ 压测 FPS 掉幅 < 15（bench/results/boss_mother_goose_*.txt）
- [x] MountTarget 保留在 all_units（SEAM 未触碰）
- [x] i18n：display_name 走 HUD 拼接例外；无其它玩家可见硬编码文本

## 6. 实现计划（Task Pipeline）

> 本 BOSS 已落地（status: done）。保留实现计划作为"从零重建"的工单参考。

### 阶段 1 — 本体 + 攻坚骨架
- [x] enemy_mother_goose.tres（§2.1 数值）
- [x] 10 挂点 + 弱点 + MountTarget 代理 + 血条按子系统 HP 求和
- [x] 伤害路由 + 角度免伤（§2.3 / §3.3）
- [x] lock_immune → 全毁暴露核心

### 阶段 2 — 压制系统
- [x] JAM 力场状态机 + overlay（§2.4）
- [x] VLS 齐射（§2.6）
- [x] UAV 蜂群 + 四变体 + GUARD/HUNTER 角色 + 剔除/召回（§2.7）

### 阶段 3 — 高压相
- [x] 指定猎杀状态机 + 牵引线 overlay + 设伏（§2.5）
- [x] MQ-X 精英对 50% 触发（§2.8）
- [x] boss_registry 注册 + BGM 歌单

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 本体/挂点/弱点/MQ-X | `scripts/survivor/mother_goose_boss.gd` |
| 状态机/JAM/VLS/UAV 管理/伤害路由 | `scripts/survivor/mother_goose_controller.gd` |
| JAM 力场 | `scripts/survivor/mother_goose_jam_shield.gd` |
| 指定猎杀 | `scripts/survivor/mother_goose_designation.gd` |
| UAV 蜂群 | `scripts/survivor/mother_goose_uav_swarm.gd` |
| overlay（视觉） | `mother_goose_shield_overlay.gd` / `mother_goose_designation_overlay.gd` |
| 注册/接线 | `scripts/survivor/boss_registry.gd` · `scripts/survivor/boss_encounter.gd` |
| 参数资源 | `resources/enemy_mother_goose.tres` · `resources/enemy_uav_mqx.tres` · `resources/naval/cg_vls_missile.tres` |
| reference 索引 | enemy-index.md（F-47 同段 BOSS 区） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-08 | — | BOSS 初版落地（见 changelogs/2026-05-08-mother-goose-boss.md） |
| 2026-05-12 | — | MQ-X 精英 + 收尾（见 changelogs/2026-05-12-mqx-elite-uav.md） |
| 2026-05-30 | 1 | 回填为 reconstruction-grade spec（本文件，从源码逆向提取全部数值） |
| 2026-07-05 | 2 | MQ-110/112 hunter 走位改 joust 攻击跑（spec joust-attack-run）：退役 standoff 切向轨道（其 1.5×standoff=6000m 触发圈盖住整个 5000m 电磁炮包络 → 机头永远侧身 → 全场 0 充能死锁，log 183044）。preferred_standoff_range_px 不再设置，包络由 joust 动态读装备。 |
