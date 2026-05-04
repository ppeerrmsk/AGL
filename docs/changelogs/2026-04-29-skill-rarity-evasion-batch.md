# 2026-04-29 — 稀有度全量分配 + Evasion 通电 + 12 张技能批量

承接同日上午的 [foundations](2026-04-29-skill-system-foundations.md)。
本次让框架"通电"——稀有度抽卡真的能选出非 STABLE 牌、evasion 模式真的能让玩家飞更快。

## A. 老 UPGRADES 稀有度 + 关键词全量分配

之前所有老技能默认 `Rarity.STABLE` 且无 keywords，导致 HIGH 槽永远空、pity 一直累积。

**分布（约 30 张）**：
- **STABLE**：14 张（hp_up / speed_up / maneuver_up / armor_up / 各种 gun 数值 / radar_range / lock_time / xp_mult …）
- **ADVANCED**：13 张（flare_cooldown / kill_heal / missile_count / missile_tracking / missile_reload / dogfight / gun_kill_fear / railgun_charge / …）
- **EXPERIMENTAL**：8 张（multi_lock / cobra_skill / fear_squad_spread / fear_chills / flare_shield / ecm_pod / shock_absorb / …）
- **CLASSIFIED**：6 张（proximity_fuze / missile_bounce / gun_multishot / gun_ciws / fire_and_forget / executioner / vapor_dodge）
- **NEXT_GEN**：1 张（data_link，F-14 exclusive）

每张额外加 `keywords: [...]` —— "fear" / "missile" / "swarm" / "evasion_mode" / "cloud" / "head_on" / ... 用于 §7 流派 steering 推荐。

**fear_chills** 的 `requires_skill` 顺手补全：现在可以接 `gun_kill_fear` / `fear_squad_spread` / `skill_gun_kill_fear` / `skill_head_on_aoe_fear` 任一。

## B. evasion_modifiers 通电

### 物理消费
[scripts/aircraft/aircraft_physics.gd:update_speed](scripts/aircraft/aircraft_physics.gd) 在 SLOW cap 之后 / max_speed cap 之前应用：
```gdscript
if ac.evasion_mode:
    var cruise_mult: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
    if cruise_mult != 1.0:
        t_kmh *= cruise_mult
```
仍受 `max_speed_at_altitude` 钳制，不会无限加速。

### 升级写入
[scripts/survivor/survivor_player.gd](scripts/survivor/survivor_player.gd) 加 4 个 stat case：
- `evasion_speed_boost` → `cruise_speed_mult`
- `evasion_weapon_cd` → `weapon_cd_mult`
- `evasion_flare_cd` → `flare_cd_mult`
- `evasion_missile_reload` → `missile_reload_mult`

通过新 helper `_set_evasion_modifier(ac, key, mult)`，关键是**升级时若玩家正处于 evasion，先 toggle off 再 toggle on** —— 让 `set_evasion_mode` 重新按新倍率缩放当前 cd，避免跨升级出现 cd 错配。

### 新增技能（2 张）
| id | 稀有度 | 效果 |
|---|---|---|
| `evasion_speed_boost` | EXPERIMENTAL | evasion 模式 cruise ×1.4 |
| `evasion_weapon_cd` | CLASSIFIED | evasion 模式所有武器 cd ×0.5 |

## C. 钩子激活技能（5 张） + 数值技能（5 张）

### 钩子激活：把 SkillHooks 已有的钩子接入 UPGRADES
| id | 稀有度 | SkillHooks 钩子 |
|---|---|---|
| `skill_kill_status_heal` | ADV | 击杀异常状态者 +30 HP |
| `skill_flare_aoe_jam` | ADV | 发射 flare 周围 JAM |
| `skill_gun_kill_flare_drop` | EXP | 机炮击杀生成 JAM 区 |
| `skill_missile_hit_aoe_jam` | EXP | 被导弹命中周围 JAM |
| `skill_evade_missile_overload` | CLA | 成功回避导弹 → 自身 OVERLOAD |

接入点：
- `aircraft_flares.release` 末调 `AOEBroadcast.apply_status_in_radius` 触发 SKILL_FLARE_AOE_JAM
- `aircraft_flares.release` jam 成功后调 `SkillHooks.on_evade_missile(ac)` 触发 SKILL_EVADE_MISSILE_OVERLOAD
- 其余 3 张钩子原本已 wired 在 `dispatch_on_kill` / `dispatch_on_hit`

### 数值技能（5 张）
| id | 稀有度 | 效果 | 消费点 |
|---|---|---|---|
| `lock_panic_g` | STABLE | 被锁时 max G ×1.20（每层）| `aircraft_physics.effective_max_g` |
| `low_hp_flare_reload` | ADV | HP < 50% 时 flare reload 倍率 ×0.5（更快）| `aircraft_flares.update` |
| `high_alt_lock_speed` | ADV | HIGH 档锁定速率 +30% | `survivor_mode._update_radar_locks` |
| `ab_gun_regen` | EXP | AB 时机炮弹药 +25 发/秒 | `aircraft_weapons.update_gun` |
| `alt_change_stealth` | EXP | 高度变化时更难被锁（受 EMA 平滑 `_alt_velocity` 驱动）| `survivor_mode._update_radar_locks` + `aircraft_physics.update_altitude` 维护 _alt_velocity |

新 Aircraft 字段：
```
lock_panic_g_mult: float = 1.0
low_hp_flare_reload_mult: float = 1.0
high_alt_lock_speed_bonus: float = 0.0
ab_gun_regen_per_sec: float = 0.0
alt_change_stealth_factor: float = 0.0
_alt_velocity: float = 0.0          # EMA 平滑值
_alt_velocity_prev: float = 0.0
```

## 验证

1. **抽卡稀有度**：升级 5 次，看 F4 实时面板 pity 计数是否 EXP/CLA/NEXT 都涨；选 1 张 EXPERIMENTAL → pity[EXP] 清零。三选一卡牌应有边框颜色差异（紫色 EXP / 金色 CLA / 红色 NEXT）。
2. **流派 steering**：连选 3 张带 `gun` keyword（如 gun_damage / gun_firerate / gun_ammo），下次升级 F4 面板应显示 `Steering gun×1.6`，gun 系列下张抽卡几率上升。
3. **evasion 加速**：手动选 `evasion_speed_boost`，进 evasion 模式看速度上升（应能突破 cruise）。
4. **evasion cd**：选 `evasion_weapon_cd`，开火后立刻进 evasion → 看 cd 立即缩短一半。再退出 → cd 恢复正常时间轴。
5. **lock_panic_g**：让 SAM 锁你 → 看转弯半径变小（G 加成）。
6. **low_hp_flare_reload**：刷到 HP < 50% → flare reload 进度条 2 倍速。
7. **high_alt_lock_speed**：HIGH 档锁敌时间应短 30%。
8. **ab_gun_regen**：开 AB 飞机炮弹药数应缓慢回升。
9. **alt_change_stealth**：快速爬升/俯冲时被锁定累积应可见变慢。

## 文件清单

**改动**：
- `scripts/survivor/survivor_data.gd` — 全部老 UPGRADES 加 rarity + keywords；fear_chills.requires_skill 扩展；新增 12 张技能（2 evasion + 5 钩子激活 + 5 数值）
- `scripts/survivor/survivor_player.gd` — 4 个 evasion_modifier stat case + 5 个数值 stat case + `_set_evasion_modifier` helper
- `scripts/aircraft.gd` — 7 个新字段（lock_panic_g_mult / low_hp_flare_reload_mult / high_alt_lock_speed_bonus / ab_gun_regen_per_sec / alt_change_stealth_factor / _alt_velocity / _alt_velocity_prev）
- `scripts/aircraft/aircraft_physics.gd` — update_speed 应用 evasion cruise mult；effective_max_g 应用 lock_panic_g_mult；update_altitude 维护 _alt_velocity
- `scripts/aircraft/aircraft_flares.gd` — release 末追加 AOE JAM + on_evade_missile 钩子；update reload 倍率应用 low_hp_flare_reload_mult
- `scripts/aircraft/aircraft_weapons.gd` — update_gun 顶 AB 时回机炮弹
- `scripts/survivor/survivor_mode.gd` — _update_radar_locks 应用 alt_change_stealth_factor + high_alt_lock_speed_bonus
- `i18n/translations.csv` — 16 条新 i18n key

## 现状统计

UPGRADES 表（不含 evolved 链残留 / 弃用字段）：
- STABLE: 16
- ADVANCED: 16
- EXPERIMENTAL: 13
- CLASSIFIED: 8
- NEXT_GEN: 1

约 54 张技能，覆盖白板 ~40 张便利贴的 60%。剩余便利贴（云中超载 / 对头机炮闪避 / 后半球减速光环 / 缠斗累计恐惧 / Cobra evasion 触发 / J-Turn 触发 / 隐身 / 4s 装填突破上限 / F-14 全员 SLOW / 等）需要新机制（云事件钩子 / engaging_me 反向索引 / cobra/herbst 触发器接入），后续按需实装。
