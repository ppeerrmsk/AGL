# 2026-04-29 — hp_up 拆分 + multi_lock 改为 missile_swarm

按用户要求重构两张技能。

## hp_up 拆分

**之前**：`hp_up` 一张牌同时给 +30 HP 和 +8% 闪避（cap 0.40）。
**现在**：拆成两张独立 STABLE 技能。

| id | 改动 |
|---|---|
| `hp_up` | 移除 `dodge_per_stack` / `dodge_cap` 字段，纯 +30 HP 每层（max_stacks 5 不变）|
| `bullet_dodge`（新）| +0.20 闪避/层，max_stacks 2，cap 由全局 `MAX_BULLET_DODGE_CAP=0.85` 兜底 |

`survivor_player.gd` 的 `"max_hp"` case 删除闪避加成代码；新增 `"bullet_dodge_flat"` case 直接 += 到 `bullet_dodge_chance`。

## multi_lock → missile_swarm

**之前**：`multi_lock`（EXP）— 单纯把 `max_simultaneous_locks += 1`，让齐射逻辑触发；不增加导弹数。

**现在**：`missile_swarm`（NEXT_GEN）— 一张牌干三件事：
1. `max_count += 4`（主导弹 + 副导弹同步）
2. `max_simultaneous_locks` 提到至少 8（让齐射真的"全打"）
3. **追踪能力轻微下降**：`max_g ×= 0.85`（玩家用弹群压火力，不靠单发精度）

单目标场景仍然只射 1 发（`_fire_multi_lock_salvo` 行为，符合用户 Q5）。

## 文件清单

**改动**：
- `scripts/survivor/survivor_data.gd` — `hp_up` 删 dodge 字段；新增 `bullet_dodge`；`multi_lock` 改名 `missile_swarm` + 升 NEXT_GEN + 加 `tracking_penalty`
- `scripts/survivor/survivor_player.gd` — `max_hp` case 删闪避；新增 `bullet_dodge_flat` case；`multi_lock` case 改名 `missile_swarm` + 实装 +4/penalty
- `i18n/translations.csv` — `UPGRADE_HP_UP_DESC` 改纯 HP；新增 `UPGRADE_BULLET_DODGE_*`；新增 `UPGRADE_MISSILE_SWARM_*`

## 现状

- UPGRADES 总数仍 ~67 张（拆 hp_up 出 +1，multi_lock 改名不变）
- STABLE 池 +1（bullet_dodge）
- NEXT_GEN 池 +1（missile_swarm 从 EXP 升上去），共 3 张：data_link、evasion_stealth、missile_swarm

## 测试要点

1. **hp_up 不再带闪避**：选 hp_up 5 层不应有任何 `bullet_dodge_chance` 变化
2. **bullet_dodge 独立累加**：选 2 层 = +40% 闪避
3. **missile_swarm 单目标行为**：只锁一个敌人时，发射只用 1 发（不浪费）
4. **missile_swarm 多目标齐射**：锁 3 个敌人 + 持有 ≥3 发导弹 → 同时全打
5. **missile_swarm 追踪减劣**：发射后导弹机动性应略低（max_g ×0.85）；玩家应该感到"导弹更容易被甩开"
