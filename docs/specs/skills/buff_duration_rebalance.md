---
id: buff_duration_rebalance
status: done
schema_version: 1
kind: balance
completed_date: 2026-05-09
---

# Buff 类技能时长统一调整

## 设计意图

自身 buff 类触发型技能（INVUL / OVERLOAD / FRENZY）固定时长在 3~7s，
玩家在窗口内来不及调整战术（4s 无敌还没追上敌人就结束、3s 超载手感像闪现）。
统一拉到 ≥ 8s，让玩家感知到"我现在很强"并真正打出连招。

AOE debuff（FEAR / JAM 给敌人）保持现状，给敌人的负面状态时长是节奏控制器，本次不动。

## 实际改动（已落盘）

### 1. [scripts/survivor/skill_hooks.gd](../../../scripts/survivor/skill_hooks.gd) 行 53-65

| 常量 | 旧 | 新 |
|---|---|---|
| `LOWEST_ALT_KILL_INVUL_DURATION` | 4.0 | 8.0 |
| `MISSILE_HIT_INVUL_DURATION` | 4.0 | 8.0 |
| `KILL_BLOODLUST_DURATION` | 7.0 | 8.0 |
| `DAMAGED_BLOODLUST_DURATION` | 7.0 | 8.0 |
| `EVADE_MISSILE_OVERLOAD_DURATION` | 6.0 | 8.0 |
| `FLARE_OVERLOAD_DURATION` | 5.0 | 8.0 |
| `JAM_SELF_OVERLOAD_DURATION` | 3.0 | 8.0 |
| `OVERLOAD_DURATION_MULT` | 4.0 | 2.0 |

### 2. [i18n/translations.csv](../../../i18n/translations.csv) 8 行

行 339/341/347/349/370/398/402/414 三语描述同步更新。

### 3. [docs/systems/survivor-skills.md](../../systems/survivor-skills.md) 全技能总表

- 8 条 self-buff 行 duration 更新为 8s
- `overload_duration_4x` 描述改为 ×2
- 顺手补全：之前总表完全缺失约 15 条 skill_flag 类技能行，agent 已补入

## 设计上限校验

`evade_missile_overload` 8s × `overload_duration_4x` ×2 = 16s
再叠 `overload_extended_ammo` +6s = **22s OVERLOAD**（最高叠加）

对比改动前 30s（6s × 4 + 6s）有所收紧；纯基础 8s 仍有 2.75 倍升级空间。

## 校验记录

- ✅ skill_hooks.gd grep 旧值 3.0/4.0/5.0/6.0/7.0 不再出现于 INVUL/BLOODLUST/OVERLOAD 路径
- ✅ i18n csv 8 行三语全部同步
- ✅ survivor-skills.md 总表 duration 与 csv 一致
- ✅ SEAM-001 未触碰：仅改常量，无物理 tick / Situation 改动
- ✅ AOE debuff 时长全部保持原值

## 顺手清理的预存 desync（已修）

发现并修正两条 i18n 与代码长期不一致：

| key | csv 旧文案 | 代码实际 | csv 新文案 |
|---|---|---|---|
| `UPGRADE_OVERLOAD_EXTENDED_AMMO_DESC` | +4s | `OVERLOAD_DURATION_FLAT_BONUS = 6.0` | +6s |
| `UPGRADE_BLOODLUST_ARMOR_MOBILITY_DESC` | 减伤 20% | `BLOODLUST_ARMOR_DR = 0.30` | 减伤 30% |

## 相关文件

- 代码：[scripts/survivor/skill_hooks.gd](../../../scripts/survivor/skill_hooks.gd)
- 文案：[i18n/translations.csv](../../../i18n/translations.csv)
- 总表：[docs/systems/survivor-skills.md](../../systems/survivor-skills.md)
- 变更记录：[docs/changelogs/2026-05-09-buff-duration-rebalance.md](../../changelogs/2026-05-09-buff-duration-rebalance.md)
