# Buff Duration Rebalance — 2026-05-09

## 改动摘要

spec: `buff_duration_rebalance`（status: done）

### 代码修改

**`scripts/survivor/skill_hooks.gd`**（行 53-65）：

| 常量 | 旧值 | 新值 |
|---|---|---|
| `LOWEST_ALT_KILL_INVUL_DURATION` | 4.0 | **8.0** |
| `MISSILE_HIT_INVUL_DURATION` | 4.0 | **8.0** |
| `KILL_BLOODLUST_DURATION` | 7.0 | **8.0** |
| `DAMAGED_BLOODLUST_DURATION` | 7.0 | **8.0** |
| `EVADE_MISSILE_OVERLOAD_DURATION` | 6.0 | **8.0** |
| `FLARE_OVERLOAD_DURATION` | 5.0 | **8.0** |
| `OVERLOAD_DURATION_MULT` | 4.0 | **2.0** |
| `JAM_SELF_OVERLOAD_DURATION` | 3.0 | **8.0** |

### i18n 修改

**`i18n/translations.csv`**（对应行）：

- 行 339 `UPGRADE_SKILL_KILL_BLOODLUST_DESC`：7s → 8s（三语）
- 行 341 `UPGRADE_SKILL_DAMAGED_BLOODLUST_DESC`：7s → 8s（三语）
- 行 347 `UPGRADE_SKILL_MISSILE_HIT_INVUL_DESC`：4s → 8s（三语）
- 行 349 `UPGRADE_SKILL_LOWEST_ALT_KILL_INVUL_DESC`：4s → 8s（三语）
- 行 370 `UPGRADE_SKILL_EVADE_MISSILE_OVERLOAD_DESC`：6s → 8s（三语）
- 行 398 `UPGRADE_OVERLOAD_DURATION_4X_DESC`：×4 → ×2（三语）
- 行 402 `UPGRADE_SKILL_FLARE_OVERLOAD_DESC`：4s → 8s（三语，同时修正预存 desync：原代码是 5s 但文案写 4s）
- 行 414 `UPGRADE_JAM_SELF_OVERLOAD_DESC`：3s → 8s（三语）
- 行 404 `UPGRADE_OVERLOAD_EXTENDED_AMMO_DESC`：+4s → +6s（三语，预存 desync 修正：代码 `OVERLOAD_DURATION_FLAT_BONUS = 6.0`）
- 行 408 `UPGRADE_BLOODLUST_ARMOR_MOBILITY_DESC`：减伤 20% → 减伤 30%（三语，预存 desync 修正：代码 `BLOODLUST_ARMOR_DR = 0.30`）

### 文档同步

**`docs/systems/survivor-skills.md`** 全技能总表：

- 补充 15 条缺失的 self-buff / status 类技能行（kill_bloodlust / damaged_bloodlust / missile_hit_invul 等）
- `overload_duration_4x` 描述更新为 ×2
- 记录 desync 发现：总表之前完全缺失 skill_flag 类技能（约 15 条）

## 旧值确认（grep 校验）

改后 skill_hooks.gd 中已无旧 self-buff 值（3.0/4.0/5.0/6.0/7.0）被引用于 INVUL/BLOODLUST/OVERLOAD 路径。

## 设计上限验证

`evade_missile_overload`（8s）+ `overload_duration_4x`（×2）= **16s OVERLOAD**
再叠 `overload_extended_ammo`（+6s）= **22s 上限**

原始上限（6s × 4 + 6s = 30s）现收紧至 22s；`overload_duration_4x` 上调为 ×2。

## SEAM-001 合规

本次改动仅修改常量值，未触及物理 tick（update_speed / update_bank / update_heading），未接触 Situation.from_aircraft。SEAM-001 红线：未触碰。
