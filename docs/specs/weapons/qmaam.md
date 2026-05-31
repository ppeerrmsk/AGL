---
id: qmaam
kind: weapon
status: done
schema_version: 1
spec_version: 1
owner: design
depends_on: [secondary-weapon-slot, missile-system]
reconstruction_complete: true
---

# QMAAM（副武器槽近距格斗弹 · SP 首把样本）

> 玩家专属副武器槽（SP/副槽）的第一把样本弹：宽锁定锥（70°）+ HOBS 高离轴发射 + 60G 机动 +
> 发射后不管，专挑"正在和你狗斗的侧面目标"自动补刀。定位：近距格斗中的**自动救场弹**，
> 与主弹槽完全独立的第二条火力线。

## 1. 设计意图（Why）

- **体验目标**：给玩家一条**独立于主弹的近距火力线**。主弹忙着打远处/被冷却卡住时，QMAAM
  在缠斗圈里自动咬住"正贴着你打的那个"补刀，缓解"被狗斗咬死又腾不出手"的窘境。
- **Litmus 自检**（docs/DESIGN_PHILOSOPHY.md）：
  - 宽锁定锥 + HOBS + 发射后不管 = 低操作负担的"救场"工具，不抢主弹的远程精算戏份 → 职责清晰。
  - 单发 + 8s 重装 = 有节奏、非刷屏；不破坏"导弹是稀缺资源"的张力 → 过反模式（武器不刷屏）。
- **反模式规避**：**敌方副槽默认不激活**——避免一加副槽就全场难度抬升；副槽框定为玩家专属救场位。
  目标选择刻意**避开主弹已在打的目标**，不做"双弹砸一个"的浪费。

## 2. 副武器槽（SP）机制

副槽是与主弹槽**完全并行**的第二套：独立雷达累积、独立锁定锥、独立弹药/冷却/重装。

| 维度 | 行为 |
|---|---|
| 启用 | 默认 `secondary_missile_enabled=false`；`SurvivorPlayableSetup.apply()` 对玩家机置 true 并按 `max_count` 装填 |
| 触发 | 自动：`update_secondary_missile()` 满足条件即选靶开火（玩家无需额外操作） |
| 开火门槛 | 启用 ∧ 余弹>0 ∧ 冷却≤0 ∧ 非重装中 ∧ **非 JAM** ∧ 目标通过有效性 gate |
| 雷达累积 | `update_secondary_radar()` 每 0.5s tick（`SECONDARY_RADAR_TICK`，省每帧全表扫描）；`secondary_radar_targets: {CombatUnit→进度秒}` |
| 锁定阈值 | 用飞机 `params.lock_time`（默认 4.0s），**JAM 时冻结**累积 |
| 与主槽隔离 | 主弹冷却/重装字段不被副槽写；任一空了/重装中，另一条线照常开火 |
| 有效性 gate | 锁定满 ∧ 主弹**没有**正飞向该目标（避免双砸）∧ 目标有效未摧毁 |
| 目标选择 | 由 `target_priority` 分派；QMAAM 用 `TARGET_PRIO_DOGFIGHT_SIDE`（见 §4.2） |
| 视觉 | 橙色 70° 锁定锥（hover 时才画，省视觉噪声）；锁定满目标橙色括号；HUD 副槽行 `[SP名] 余/满` |

## 3. 数据定义（What —— 全部数值，权威源）

### 3.1 弹体参数（`qmaam_missile.tres`，MissileParams）

> 单位：速度 m/s、加速度 m/s²、射程 m、角度 度、`*_px` 为像素（1 px = 2 m，`PIXELS_PER_METER=0.5`）。

| 字段 | 值 | 单位 | 说明 |
|---|---|---|---|
| display_name | "QMAAM" | — | HUD/日志拼接用，免 tr()（同 AircraftParams.display_name 例外） |
| max_speed | 1400.0 | m/s | ≈ Mach 4.1（燃尽后巡航峰值） |
| motor_burn_time | 2.5 | s | 发动机燃烧时长 |
| motor_acceleration | 320.0 | m/s² | 燃烧阶段加速度（高，配近距快交战） |
| drag_deceleration | 35.0 | m/s² | 燃尽后阻力减速 |
| max_g | 60.0 | G | 最大过载（高机动 PN 制导） |
| nav_constant | 5.0 | — | 比例导引 N |
| max_range_rear | 800.0 | m | 后半球最大射程 |
| front_rear_ratio | 2.0 | — | 前半球 = 2× 后半球 = **1600 m** |
| min_range | 100.0 | m | 引信武装距离 |
| max_lifetime | 8.0 | s | 绝对存活时间（硬 kill 计时） |
| damage | 70.0 | — | 命中伤害 |
| proximity_fuse_radius | 25.0 | m | 近炸引信半径 |
| proximity_fuse_alt | 200.0 | m | 近炸高度容差 |
| intercept_hp | 40.0 | — | 抗 CIWS：被子弹累积此 HP 才算拦截（短程弹档位） |
| seeker_fov | 120.0 | ° | 导引头总视场（±60°） |
| guidance_delay | 0.1 | s | 制导启动延迟（极短，配快交战） |
| fire_and_forget | true | — | 发射后不管：不需持续照射、不受热诱弹干扰 |
| max_count | 1 | 发 | 弹仓容量：单发 |
| cooldown | 8.0 | s | 发射间隔 |
| target_filter | 1 | 位域 | 仅 AIR（`TARGET_AIR=1`） |
| lock_cone_half_angle_deg | 70.0 | ° | 副雷达锁定锥半角（宽，覆盖侧面） |
| lock_max_range_px | 800.0 | px | = 1600 m 近距锁定（覆盖飞机默认雷达距离） |
| target_priority | 1 | enum | `TARGET_PRIO_DOGFIGHT_SIDE` |
| launch_toward_target | true | — | HOBS：发射即指向目标 LOS（非机头），PN 立刻有效 |

> ⚠ **源码注释陈旧**：`missile_params.gd` 对 `lock_max_range_px` 的示例注释写 "QMAAM: 1500px ≈ 3km"，
> 但实际 `.tres` 值为 **800 px（1600 m）**。以 .tres 为准。

### 3.2 重装节奏

```
开火 → 余弹 1→0 → _secondary_reload_active=true
重装时长 = cooldown × max(max_count,1) = 8.0 × 1 = 8.0 s
重装满 → 余弹=1，reload_active=false → 冷却 8s 后可再自动开火
```

## 4. 行为与公式（How）

### 4.1 开火流程

```
update_secondary_missile():
  若 启用 ∧ 余弹>0 ∧ 冷却≤0 ∧ 非重装 ∧ 非 JAM:
    tgt = _pick_secondary_target()        # §4.2
    若 tgt 通过 _is_valid_secondary_candidate（锁定满 ∧ 主弹没在打它 ∧ 有效）:
      发射（单发；HOBS 起始朝向 = 目标 LOS；fire_and_forget 自导）
      余弹-1 → 触发重装 + 冷却
```

副槽**不**参与主弹的多锁齐射（`_fire_multi_lock_salvo` 仅主槽）。

### 4.2 目标选择 `TARGET_PRIO_DOGFIGHT_SIDE`

挑"离得近、在侧面、且正在和玩家狗斗"的空中目标，打分（高者优先）：

```
closeness     = 1.0 - dist / max_range                      # 距离主权重
side_bonus    = (off_axis / max_off_axis) × 0.30            # 最高 +0.30，70° 处峰值
dogfight_bonus= 0.40  若 敌.combat_target==玩家
                       或 敌.secondary_radar_targets[玩家] > lock_time×0.5
score = closeness + side_bonus + dogfight_bonus
```

只取 AIR（`target_filter=1`）；地面/海军天然被类型位过滤掉。

## 5. 结构与组成（Structure）

- 弹体：`qmaam_missile.tres`（MissileParams），挂在 `AircraftParams.secondary_missile`。无独立 Equipment 子类，
  走通用副槽逻辑。
- 副槽运行态（`aircraft.gd` 字段）：`secondary_missiles_remaining` / `secondary_missile_enabled` /
  `secondary_radar_targets{}` / `secondary_combat_target` / `_secondary_cooldown` / `_secondary_reload_active` /
  `_secondary_reload_timer` / `_secondary_radar_tick_acc`。
- 逻辑：`aircraft_weapons.gd` 的 `update_secondary_radar` / `update_secondary_missile` / `_pick_secondary_target` /
  `_is_valid_secondary_candidate`。
- 视觉：`aircraft_renderer.gd` 锁定锥 + 括号；`survivor_hud.gd` SP 行。
- `deep_dup_weapons()` 对 `secondary_missile` 做 `duplicate(true)`，避免运行时改动污染 .tres。

## 6. 装载与 AI

- **玩家**：副槽默认空（各 PlayableAircraft `secondary_missile=null`）；通过 F4 调试面板可换上 QMAAM/AGM。
  正式进度中尚未做成解锁项（属调试/样本阶段）。
- **敌人**：`secondary_missile_enabled=false` 硬关闭——敌方副槽**永不开火**（设计：避免基线难度漂移）。

## 7. 验收标准（Acceptance / Litmus）

- [x] 零回归：`secondary_missile=null` 时无 SP HUD、无锁定锥、主弹行为不变
- [x] 独立性：主弹空/重装时 QMAAM 照常开火；QMAAM 空/重装时主弹照常开火
- [x] 目标选择：锥内三种空靶（对头/冷侧/热侧狗斗）→ 选热侧（分最高）
- [x] 不抢靶：主弹已飞向某靶 → QMAAM 跳过另选
- [x] JAM 阻断：BOSS JAM 场内副雷达冻结、QMAAM 不发，主雷达同样冻结（对称）
- [x] 升级隔离：missile_count/seeker_fov/boost/tracking/swarm 只影响主弹，QMAAM 不变；lock_time 升级两槽都快
- [x] 单位正确：max_speed m/s、射程 m、lock_max_range_px=800px=1600m（以 .tres 为准，非注释 1500px）
- [x] 性能：副雷达 0.5s tick；Lv5+ sentinel 压测 FPS 掉 < 2
- [x] display_name 走 HUD 拼接例外（免 tr()）

## 8. 实现计划（Task Pipeline）

> 已落地（status: done，commit 0551516）。保留作"从零重建"工单参考。

### 阶段 1 — 副槽地基
- [x] `missile_params.gd` 加副槽字段：target_filter / lock_cone_half_angle_deg / lock_max_range_px / target_priority / launch_toward_target（HOBS）
- [x] `aircraft.gd` 加 8 个副槽运行态字段
- [x] `aircraft_weapons.gd` 副雷达 + 副弹更新 + 目标选择 + 有效性 gate（+ JAM 冻结对称）

### 阶段 2 — QMAAM 样本
- [x] `qmaam_missile.tres`（§3.1 全部数值）
- [x] `_pick_secondary_target` 的 `TARGET_PRIO_DOGFIGHT_SIDE` 打分分支

### 阶段 3 — 表现 + 接入
- [x] `aircraft_renderer.gd` 橙色 70° 锁定锥（hover）+ 锁定括号
- [x] `survivor_hud.gd` SP 行（余/满，配色）
- [x] `survivor_playable_setup.gd` 启用副槽 + 装填
- [x] F4 调试面板副弹切换项

## 9. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 弹体参数 | `resources/qmaam_missile.tres` |
| MissileParams 字段/枚举 | `scripts/missile_params.gd`（TARGET_PRIO_*、副槽字段组） |
| 副槽逻辑 | `scripts/aircraft/aircraft_weapons.gd`（update_secondary_radar/missile, _pick_secondary_target, _is_valid_secondary_candidate） |
| 副槽运行态字段 | `scripts/aircraft.gd` |
| 锁定锥/括号 | `scripts/aircraft_renderer.gd` |
| SP HUD 行 | `scripts/survivor/survivor_hud.gd` |
| 启用/装填 | `scripts/survivor/survivor_playable_setup.gd` |
| HOBS 发射 | `scripts/missile_manager.gd`（launch_toward_target） |
| 设计来源 | `docs/changelogs/2026-05-10-secondary-slot-revival.md` |
| reference 索引 | playbook.md §3 加武器装备 |

## 10. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-12 | — | 副武器槽复活 + QMAAM 首把样本落地（commit 0551516） |
| 2026-05-30 | 1 | 逆向回填为 reconstruction-grade spec；核对单位（m/s / m / px=2m）+ 记录 lock_max_range_px 注释陈旧（实 800px） |
