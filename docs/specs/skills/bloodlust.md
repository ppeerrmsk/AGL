---
id: bloodlust
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: design
depends_on: [overload, status-effects, seam-001-effective-accessor]
reconstruction_complete: true
---

# BLOODLUST 嗜血（击杀/受伤触发 buff 家族）

> 一组围绕"BLOODLUST 状态"的升级。基础款触发即回血；进阶"血怒护甲"把 BLOODLUST 期间变成
> 减伤 + 高机动窗口。设计定位：奖励**主动交战/挨打**，把"打得越凶越强"做成正反馈循环。

## 1. 设计意图（Why）

- **体验目标**：让玩家在击杀/被打的瞬间获得短时强化，形成"咬住战斗就滚雪球"的节奏。
  基础款先给**续航**（回血），进阶款再换成**攻坚窗口**（减伤+拉 G+加速），层层加码。
- **Litmus 自检**（docs/DESIGN_PHILOSOPHY.md）：
  - buff 有明确来源（击杀/受伤）和清晰时长条（8s）→ 玩家能预期、能规划连招 → 过"可读"测试。
  - 机动 buff 经 `effective_*()` 注入，**AI 战术层能感知**（设的目标速度/角点速度会抬升）→
    过"buff 名副其实"测试（见反模式：升级名存实亡）。
- **反模式规避**：基础 BLOODLUST 只回血、不直接给机动——避免单卡就过强；机动/减伤拆到
  `bloodlust_armor_mobility` 进阶卡，形成"基础→进阶→共振"的构筑深度，而非一张卡全包。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 升级条目（`survivor_data.gd:UPGRADES`）

| id | 触发/作用 | 类别 | 稀有度 | 上限 | 前置（任一） |
|---|---|---|---|---|---|
| `skill_kill_bloodlust` | 击杀 → BLOODLUST 8s | survival | ADVANCED | 1 | — |
| `skill_damaged_bloodlust` | 受伤 → BLOODLUST 8s（被打刷新） | survival | ADVANCED | 1 | — |
| `bloodlust_armor_mobility` | **修饰**：BLOODLUST 期间减伤+拉G+加速 | survival | ADVANCED | 1 | `skill_kill_bloodlust` / `skill_damaged_bloodlust` / `overload_to_bloodlust` |
| `overload_to_bloodlust` | OVERLOAD 时同时获得 BLOODLUST，击杀刷新两者 | electronic_warfare | EXPERIMENTAL | 1 | `cloud_overload` / `skill_evade_missile_overload` / `skill_flare_overload` |
| `full_hp_kill_perma_hp` | 满血+BLOODLUST 击杀 → 永久 +max_hp | survival | CLASSIFIED | 1 | 任一 BLOODLUST 基础卡 |

所有条目 `stat = "skill_flag"`、`value = 1`（布尔旗标，不是数值堆叠）。

### 2.2 核心常量（`skill_hooks.gd`）

| 常量 | 值 | 含义 |
|---|---|---|
| `KILL_BLOODLUST_DURATION` | 8.0 s | 击杀触发时长 |
| `DAMAGED_BLOODLUST_DURATION` | 8.0 s | 受伤触发时长 |
| `BLOODLUST_ARMOR_DR` | 0.30 | 减伤 30%（受伤 ×0.70），仅 `bloodlust_armor_mobility` 生效 |
| `BLOODLUST_G_MULT` | 1.20 | max_g ×1.2，仅修饰卡生效 |
| `BLOODLUST_ACCEL_MULT` | 1.30 | 加速/减速 ×1.3，仅修饰卡生效（与 OVERLOAD 的 1.6 区别开） |
| `FULL_HP_KILL_HP_BONUS` | **8.0** | 满血 BLOODLUST 击杀的永久 +max_hp/+hp ⚠ 见 §8 desync |
| `BLOODLUST_HEAL_PER_KILL`（`status_effects.gd`） | 20.0 | BLOODLUST 期间击杀回血 +20 |

### 2.3 状态显示（`status_effects.gd`）

| 项 | 值 |
|---|---|
| status key | `BLOODLUST = "bloodlust"` |
| HUD 英文标签 | `FRENZY` |
| HUD 中文短标 | `嗜血` |
| 图标色 | Color(1.00, 0.30, 0.30) 血红 |
| 刷新模式 | **max**（取 max(剩余, 新时长)，进度条按 `status_initial_durations` 渲染） |

## 3. 行为与公式（How）

### 3.1 触发 → 施加

```
击杀任意敌机（gun/missile/rocket/AOE 皆可）:
  若持有 skill_kill_bloodlust → apply_status(BLOODLUST, 8.0)
  若持有 BLOODLUST 状态（任意来源）→ 回血 +20（BLOODLUST_HEAL_PER_KILL）
  若持有 overload_to_bloodlust 且 OVERLOAD/BLOODLUST 仍在 → 刷新两者到 initial 时长
  若持有 full_hp_kill_perma_hp 且 当前 status_bloodlust_active 且 满血(容差0.5)
     → params.max_hp += 8.0；hp = min(hp+8.0, max_hp)   ## 永久成长

受伤（任意来源）:
  若持有 skill_damaged_bloodlust → apply_status(BLOODLUST, 8.0)（max 刷新）

进入 OVERLOAD（任意来源）且持有 overload_to_bloodlust:
  → 同时 apply_status(BLOODLUST, OVERLOAD 同款最终时长)
     （OVERLOAD 时长链：base 8 ×2 if overload_duration_4x +6 if overload_extended_ammo，最高 22s）
```

### 3.2 BLOODLUST 期间的效果（注意分层）

**基础 BLOODLUST（无 `bloodlust_armor_mobility`）**：**只有击杀回血 +20**，无机动/减伤。

**+ `bloodlust_armor_mobility` 修饰卡**（且 `team==0`），追加四项，全部经 SEAM-001 注入点：

| 效果 | 值 | 注入位置（accessor） |
|---|---|---|
| 减伤 | 受伤 ×(1-0.30)=×0.70 | `aircraft.gd._apply_damage`（独立于护甲 DR 的乘法层） |
| max_g | ×1.20 | `aircraft_physics.gd:effective_max_g` |
| 加速/减速 | ×1.30 | `aircraft_physics.gd:update_speed` + `update_altitude`（accel_rate & decel_rate 同乘） |
| 失速安全余量 | 1.2 → **1.0** | `aircraft_physics.gd:_dynamic_safe_margin` |

> **失速余量降到 1.0 的连带效果**：角点速度 `effective_corner_speed_kmh` 自动随 `effective_max_g`
> 上升 + 允许更低速拉满 G。所以这张卡不只是"+20% G 数字"，而是把整条转弯包络抬高。
> 预测线 `cached_max_g / cached_safe_margin` 会冻结这些值（同一帧内一致，防止预测路径撕裂）。

> ⚠ **SEAM-001**：机动 buff **只能**经 `effective_*()` accessor 注入，AI 战术层（Situation /
> TacticalPlanner）才能感知；BLOODLUST 正是范例。禁止在物理 tick 散点 if-else 乘 buff。

### 3.3 叠加 / 交互

- 单一 BLOODLUST 实例；多来源（击杀/受伤/OVERLOAD）只**刷新**同一个，不叠加。
- 与 OVERLOAD / INVINCIBLE / STEALTH 等其它状态各自独立共存。
- 修饰卡效果对 BLOODLUST 的"任意来源"都生效（不限于击杀触发）。

## 4. 结构与组成（Structure）

- 触发逻辑：`skill_hooks.gd` 的 `dispatch_on_kill`（经 `StatusEffects.on_kill` 调用）/ `dispatch_on_hit`。
- 状态存储：`CombatUnit.status_effects["bloodlust"]`（剩余时长）+ `status_initial_durations`（进度条基线）；
  派生旗标 `aircraft.status_bloodlust_active`（每帧由 `StatusEffects.update` 维护）。
- 修饰卡 gate：所有 accessor 内 `team==0 && status_bloodlust_active && upgrade_stacks[bloodlust_armor_mobility]>0`。
- 升级旗标存于 `aircraft` 的 `upgrade_stacks` meta（`SurvivorPlayer.apply_upgrade` 写入；skill_flag 类不改 params）。

## 5. 验收标准（Acceptance / Litmus）

- [x] 仅持基础卡：击杀回血 +20，**无**机动/减伤变化（零回归：accessor if 块未触发 = baseline）
- [x] 加修饰卡：BLOODLUST 期间受伤 ×0.70、max_g ×1.2、accel/decel ×1.3、safe_margin→1.0
- [x] AI 可感知：升满 buff 后 EventLogger 看 AI 设的 `target_speed_kmh` / 角点速度抬升（SEAM-001 通路）
- [x] 触发为 max 刷新（已激活时再触发取 max，不缩短）
- [x] OVERLOAD 共振：overload_to_bloodlust 下 OVERLOAD/BLOODLUST 同时在、击杀同时刷新
- [x] i18n：5 个条目三语齐全，desc 数值与代码常量一致（full_hp_kill +5→+8 desync 已修，见 §8）

## 6. 实现计划（Task Pipeline）

> 已落地（status: done）。保留作"从零重建"工单参考。

### 阶段 1 — 状态与基础触发
- [x] `StatusEffects.BLOODLUST` + HUD 标签/色/DISPLAY_ORDER + `BLOODLUST_HEAL_PER_KILL=20`
- [x] `skill_kill_bloodlust` / `skill_damaged_bloodlust` 条目 + on_kill/on_hit 钩子（8s，max 刷新）

### 阶段 2 — 修饰卡（机动/减伤）
- [x] `bloodlust_armor_mobility` 条目（前置任一 BLOODLUST 基础卡）
- [x] 四注入点：effective_max_g ×1.2 / update_speed+update_altitude accel ×1.3 / _apply_damage ×0.70 / _dynamic_safe_margin→1.0
- [x] 预测线缓存 cached_max_g / cached_safe_margin 一致性

### 阶段 3 — 进阶联动
- [x] `overload_to_bloodlust`（OVERLOAD 同步授予 + 击杀双刷新）
- [x] `full_hp_kill_perma_hp`（满血 BLOODLUST 击杀永久 +max_hp）

### 阶段 4 — 收尾
- [x] i18n 5 条目三语
- [x] survivor-skills.md 图鉴登记
- [x] 修正 full_hp_kill 文案/常量 desync（§8，以代码 +8 为准）

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 触发钩子 + 常量 | `scripts/survivor/skill_hooks.gd` |
| accessor 注入（G/accel/safe_margin） | `scripts/aircraft/aircraft_physics.gd`（effective_max_g / update_speed / update_altitude / _dynamic_safe_margin） |
| 减伤层 | `scripts/aircraft.gd`（_apply_damage） |
| 状态定义/HUD/回血 | `scripts/status_effects.gd` |
| 升级条目 | `scripts/survivor/survivor_data.gd`（UPGRADES） |
| 旗标写入 | `scripts/survivor/survivor_player.gd`（apply_upgrade，skill_flag 类） |
| i18n | `i18n/translations.csv`（UPGRADE_*_BLOODLUST_* 等） |
| 图鉴 | `docs/systems/survivor-skills.md` |

## 8. desync 修复记录（已解决）

`full_hp_kill_perma_hp`：代码 `FULL_HP_KILL_HP_BONUS = 8.0`（每次 +8 max_hp），但旧版
i18n `UPGRADE_FULL_HP_KILL_PERMA_HP_DESC` 三语文案与 `skill_hooks.gd` 注释写成 "+5"。
**2026-05-30 裁决：以系统数值为准（+8）**，已改：
- i18n CSV 三语文案 +5 → **+8**（`translations.csv` UPGRADE_FULL_HP_KILL_PERMA_HP_DESC）
- `skill_hooks.gd` 注释 +5 → +8
- survivor-skills.md 图鉴本就是 +8（无需改）
- ⚠ 需在 Godot 编辑器打开 csv 重新生成 `.translation` 二进制（或跑 import）才会在游戏内生效

## 9. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-09 | — | buff 时长统一 8s（见 specs/skills/buff_duration_rebalance.md + changelog 2026-05-09） |
| 2026-05-30 | 1 | 逆向回填为 reconstruction-grade spec；澄清"基础款仅回血、机动/减伤在修饰卡"；记录 full_hp_kill +5/+8 desync |
