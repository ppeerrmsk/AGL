# 2026-04-29 — base 系统 × 技能叠加 bugfix

承接同日上午的 [buff-stack-bugfix](2026-04-29-buff-stack-bugfix.md)。
用户继续追问 base 系统（规避模式 / 高度 / 云）与技能的叠加是否会出问题。系统排查发现 2 个新 bug。

## 🔴 Bug 3: 机炮闪避线性叠加无 cap → 永久闪避

**场景**：所有机炮闪避来源都是**线性加和**：
| 来源 | 量 |
|---|---|
| `bullet_dodge_chance` 基础（PlayableAircraft 0.10–0.20） | |
| `hp_up` 升级（cap 0.40） | 取代基础值 |
| `evasion_mode` | +0.20 |
| `AltitudeTier.HIGH` | +0.20 |
| `head_on_gun_dodge_bonus` | +0.60（对头几何）|

**最坏情况（已选 hp_up 满级）**：
- 装备 build：0.40 + 0.20 + 0.20 = **0.80（80%）** —— 单凭 base 系统就已经接近上限
- 加对头：**1.40（140%）** —— `randf() < 1.40` 永远 true，机炮永远打不到玩家

**且无任何提示**：原代码直接 `randf() < effective_dodge`，不会报错也不会吃 cap。

**修复**：
```gdscript
const MAX_BULLET_DODGE_CAP: float = 0.85
effective_dodge = clampf(effective_dodge, 0.0, MAX_BULLET_DODGE_CAP)
```
85% 留 15% 命中窗口，玩家仍能感到"危险"，但满 build 也算合理收益。

**为什么用 cap 而不是乘法递减**：
- 乘法（1 − Π(1 − d_i)）数学更"优雅"但玩家心算困难（"我大概多少闪避？"）
- 线性 + cap 简单可读，玩家选每张牌都能感受到收益
- 未来若加"低空 50% 机炮闪避"等便利贴，cap 自然兜底，无需再调

## 🔴 Bug 4: SLOW debuff 被 evasion cruise mult 绕过

**场景**：SLOW 状态硬 cap target_speed 为 350 km/h，但旧顺序：
```
1. 应用 SLOW cap → 350
2. 应用 evasion cruise_mult ×1.4 → 350 × 1.4 = 490 ←← debuff 失效
3. 应用 max_speed_at_altitude cap
```
玩家持有 evasion_speed_boost + 进入 SLOW → 期望被减速到 350，实际还能 490 km/h。

**修复**：buff/debuff 顺序反转。**所有 buff 在 SLOW cap 之前，debuff 永远是 final cap**：
```
1. evasion cruise_mult（buff 先）
2. SLOW cap 350（debuff 后）  ← 不会被绕过
3. max_speed cap
```

## 全表系统性扫描其它叠加场景

### ✅ 锁定速率 lock_rate（乘法叠加，安全）
- stealth_pod ÷ lock_resistance_mult（3 层 ÷2.46）
- HIGH 云中 ×0.5
- vapor_dodge 任意档云中 ×0.1
- alt_change_stealth ×(1 − alt_v×factor)
- high_alt_lock_speed_bonus 反向 ×(1 + bonus)

**保护**：`MAX_EFFECTIVE_LOCK_TIME_S = 12s` 硬下限 + `lock_time` 升级 cap 0.5s 上限 ✓

### ✅ effective_max_g（乘法叠加，天然限制）
- params.max_g + maneuver_up（base +1G/层 × 3 层 = +3G）
- 云中 ×0.9（debuff）
- lock_panic_g_mult ×1.20/层 cap 2 层（最高 ×1.44）

最大：F-16 max_g=9 + maneuver +3G = 12 × 1.44 = **17.28 G**。在飞行包线内，maneuver_up 只 3 层 + lock_panic 只 2 层天然限制。`max_g_structural` 是另一层保护。✓

### ✅ max_speed（乘法 + cap 自然兜底）
- speed_up ×1.18/层 cap 4 层（最高 ×1.94）
- evasion cruise_mult ×1.4

最终被 `max_speed_at_altitude` 钳制 ✓

### ✅ 受击/击杀回血（全部 cap 到 max_hp）
- BLOODLUST kill heal +15 → minf(hp+15, max_hp)
- skill_kill_status_heal +30 → minf cap
- kill_heal_amount +N → minf cap
- shock_absorb_pending → room = max_hp - hp

### ✅ INVINCIBLE × 闪避 × DR 链路
1. INVINCIBLE: invul return（最优先，跳过其它）
2. 机炮闪避: cap 0.85（剩 15% 命中窗口）
3. armor 减免（DOTA 式 dr = a/(a+100)）
4. gun_fire_dr 时间窗 ×0.5
5. hp -= amount

每层独立可叠加，每层都有合理上限。✓

### ✅ FEAR/JAM/SLOW 施加给敌人
敌人不持有玩家 upgrade_stacks，钩子层早退，不存在反向叠加问题。
UAV FEAR 在 `Aircraft.apply_status` 静默丢弃（已修 Bug 0）。

## 设计准则总结

为预防同类 bug，规则化：

1. **同一可叠加属性必须有 cap**——线性加和的 buff 几乎必然溢出
2. **debuff 永远是 final 应用层**——放在 buff 之后 cap，避免被绕过
3. **常驻状态不进 status_effects 字典**——用独立 bool + 派生 OR（见 [bugfix-1](2026-04-29-buff-stack-bugfix.md) Bug 2）
4. **击杀奖励用 `max` 模式，受击防滥用用 `no_refresh`**——语义不同不要共用
5. **回血都 minf cap 到 max_hp**——已全部检查 ✓
6. **乘法叠加比线性安全**——但玩家心算困难，特殊场景才用

## 文件清单

**改动**：
- `scripts/aircraft.gd` — `MAX_BULLET_DODGE_CAP = 0.85` 常量 + `take_bullet_damage` clampf；注释扩展叠加来源
- `scripts/aircraft/aircraft_physics.gd` — `update_speed` 顺序调整（evasion mult 在 SLOW cap 之前）
