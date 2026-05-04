# 2026-04-29 — 同状态多源叠加 bugfix（INVINCIBLE / OVERLOAD）

用户排查后发现两个静默失效的边界 bug，都是"同一状态多个 apply 源"引起。

## 🔴 Bug 1: INVINCIBLE 双源 no_refresh 互锁

**复现**：
- t=0 玩家被导弹命中 → `apply_status(INVINCIBLE, 4s, "no_refresh")` → status_effects[INV]=4
- t=2 玩家低空击杀触发奖励 → `apply_status(INVINCIBLE, 4s, "no_refresh")` → 看到 prev=2.0 仍在 → **静默跳过**
- 击杀奖励的 2s 完全失效，玩家无感

**根因**：两个 SkillHooks 都用 no_refresh 模式（受击防滥用 + 击杀奖励），互相挡住。
但语义上"被打不刷新"和"击杀延长无敌"是两类设计，不该共用一个模式。

**修复**：
- `SKILL_MISSILE_HIT_INVUL` 保留 `no_refresh`（防滥用，符合用户 Q2）
- `SKILL_LOWEST_ALT_KILL_INVUL` 改 `max`（默认）—— 击杀是奖励，应能延长已有 INVINCIBLE

```gdscript
// SkillHooks._hook_lowest_alt_kill_invul
killer.apply_status(StatusEffects.INVINCIBLE, LOWEST_ALT_KILL_INVUL_DURATION)  // 去掉 "no_refresh"
```

## 🔴 Bug 2: cloud OVERLOAD owner 跟踪误删 evade 6s

**复现**：
- t=0 玩家在云外 evade 一发导弹 → `apply_status(OVERLOAD, 6s)` → status_effects[OVER]=6
- t=2 玩家飞进云 → `_on_cloud_boundary(true)`：
  - `apply_status(OVERLOAD, 9999, "no_refresh")` 看到 prev=6 → 跳过（status 不变）
  - 但 `_cloud_owns_overload = true` 仍被无条件置 true ←← bug
- t=10 玩家出云（OVERLOAD 还有 4s 是 evade 给的）→ `_on_cloud_boundary(false)`：
  - 看到 flag=true → **`remove_status(OVERLOAD)` 把 evade 的 4s 一起清了** ←← 静默失效

**根因**：把"在云中=OVERLOAD"塞进 status_effects 必然跟其它来源冲突。
9999s + owner 跟踪是不稳的 hack。

**修复**：云中 OVERLOAD 不走 status_effects，独立 bool + 派生标记 OR：

```gdscript
// Aircraft 新字段
var cloud_overload_active: bool = false   # 解锁标记（apply_upgrade 写）
var _in_cloud_overload: bool = false      # 运行时（_on_cloud_boundary toggle）

// _on_cloud_boundary
if cloud_overload_active:
    _in_cloud_overload = entering   # 单纯 toggle，不动 status_effects

// StatusEffects.update — 派生标记 OR 两源
ac.status_overload_active = ac.status_effects.has(OVERLOAD) or ac._in_cloud_overload
```

两源完全独立：云内常驻 + status_effects 限时（evade / 未来其它源）互不干扰。
出云只关 `_in_cloud_overload`，不动 status_effects 中的 evade 6s。

## 全表扫一遍其它叠加场景（检查无 bug）

| 场景 | 行为 | 状态 |
|---|---|---|
| BLOODLUST：kill 7s + damaged 7s | max() 取较大；持续 apply 刷新到 7s | ✅ 符合用户 Q8 |
| BLOODLUST 击杀回血 +15 | minf(hp+15, max_hp) cap 正确 | ✅ |
| skill_kill_status_heal +30 | minf cap 到 max_hp | ✅ |
| kill_heal_amount +N | minf cap 到 max_hp | ✅ |
| shock_absorb_pending 慢回血 | room = max_hp - hp 钳制 | ✅ |
| 对头 +5 max_hp 多次叠加 | 设计预期；hp 同步 +5 不超新 max | ✅ Q6 |
| INVINCIBLE 期间被命中 | invulnerable=true 直接 return，DR/钩子都不跑 | ✅ |
| gun_fire_dr 与 take_bullet_damage 闪避 | 闪避在 _apply_damage 前 return，DR 不冲突 | ✅ |
| FEAR/JAM/SLOW 施加给敌人 | 敌人不持有玩家技能 stacks，不会反向叠加 | ✅ |
| no_pilot UAV 的 FEAR | Aircraft.apply_status 静默丢弃 | ✅ Bug 已修 |

## 一个 minor edge case（不修）

`apply_status(id, duration)` 在 `prev == duration` 时（极小概率）不更新 baseline，
进度条不重置。实际每帧 tick 让 prev 一直在递减，几乎不可能恰好相等，忽略。

## 文件清单

**改动**：
- `scripts/survivor/skill_hooks.gd` — `_hook_lowest_alt_kill_invul` 去掉 "no_refresh"
- `scripts/aircraft.gd` — 新增 `_in_cloud_overload: bool`；改 `_on_cloud_boundary` 用 bool toggle 取代 status_effects 9999s + owner 跟踪
- `scripts/status_effects.gd` — `status_overload_active` 派生 OR `_in_cloud_overload`
