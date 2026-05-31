# 2026-05-31 — 僚机护卫 AI（squad-ai-escort）阶段 1-2

spec: [docs/specs/systems/squad-ai-escort.md](../specs/systems/squad-ai-escort.md)（status 仍 draft；本轮只派生 §6 阶段 1-2，阶段 3-5 待续）

## 目标

让护卫编队（玩家队 + F-47/Mother Goose 精英队）的 AI 僚机以"当前长机安危"为目标中心：
优先扑向**正在攻击长机**的敌机，并对紧贴长机的威胁提权。本轮落地目标 1（护卫优先但不死板）
与目标 2（反杀攻击者）+ 切换自愈（评分键于当前长机引用，无持久属性）。

目标 3（指派一机守后半球）= 阶段 3，本轮**未做**（scan_leader_rear 仍未接线，留作下一步）。

## 改动

### 阶段 1 — 威胁反查地基
- **`scripts/squad.gd`**：新增 `@export var escort_doctrine_enabled: bool = false` 字段。
  off 时全部护卫逻辑跳过，行为与改动前完全一致。
- **`scripts/ai_controller.gd`**：
  - 新增常量 `ATTACKING_LEADER_BONUS = 60.0` / `LEADER_PROXIMITY_BONUS_MAX = 25.0`（体感调参项）。
  - 新增静态 `_maintains_engaging_me(target)`：team0 玩家系（**原状保留**，技能反向索引依赖）
    **OR** 护卫学说编队成员 → 维护 engaging_me；杂兵不维护。
  - engaging_me 差量同步条件由 `team == 0` 换成 `_maintains_engaging_me(_current_target)`
    （**加性扩展**：team0 行为不变 + 新增精英敌方编队成员）。
- **建队处打开护卫学说**：
  - `survivor_mode.gd:_spawn_starting_wingmen` 玩家队 → on
  - `ace_squad.gd`（F-47 精英基类）→ on
  - `mother_goose_boss.gd` boss_squad + mqx_squad → on

### 阶段 2 — 护卫目标评分
- **`scripts/ai/squad_coordination.gd`**：新增
  - `is_escort_wingman(ai)`：编队开护卫学说 + 长机有效 + 自己非长机。
  - `escort_target_bonus(leader, candidate)`：咬长机 → +ATTACKING_LEADER_BONUS（查 leader.engaging_me，O(1)）；
    近长机 → 按距长机插值 0~LEADER_PROXIMITY_BONUS_MAX（COVER_SCAN_RANGE 内）。
  - `scan_squad_nearby_enemy` 改为评分选目标（就近分 `1/d*1000` + 护卫加权）。
    **非护卫编队 escort_leader=null → 纯就近**，与原 best_dist 纯距离选择**等价**（max(1/d) ⟺ min d）。
- **`scripts/ai/target_selection.gd`**：`try_engage` / `reevaluate_target` 候选评分叠加
  `escort_target_bonus`（仅护卫编队僚机，target 须 Aircraft）。

## 设计 / 安全要点

- **加性守卫**：engaging_me 维护从 team0 **扩**到 team0+护卫编队，绝不收窄——否则 solo 玩家会丢
  缠斗恐惧 / 后半球减速光环等依赖 team0 反向索引的技能。
- **切换自愈**：护卫评分读 `ai.squad.leader`（操控切换经 set_leader 动态更新），无任何持久护卫属性，
  切换天然自愈（§3.4）。长机不护卫自己（is_escort_wingman 排除 leader == self）。
- **性能**：engaging_me 反查 O(1)；维护范围 = 玩家队 + 少数精英队成员（非全场）；scan 仍走既有
  `CombatUnit.all_units` + 1Hz tick，无新全场遍历。

## ⚠ 待调参（阶段 5）/ 已知关注点

- ATTACKING_LEADER_BONUS=60 / PROXIMITY=25 相对自然评分（~0~12）偏大 → 护卫考量会**强主导**。
  这是"护卫优先"的有意取向，但需 playtest 确认"不死板"未被破坏（无威胁时 bonus≈0，应退回就近）。
- 阶段 3（守后半球）未做：scan_leader_rear + COVER_SCAN_INTERVAL/_cover_scan_timer 等脚手架已在
  但未接线。下一步实装一机占位守后 + COVER_REASSIGN_HYSTERESIS 迟滞。

## 验证（待用户 playtest）

- [ ] 敌机咬长机时僚机优先扑向该敌（即使另有更近敌机）；威胁解除退回就近。
- [ ] 无威胁时僚机仍打身边顺手敌机（战场不空）。
- [ ] 攻击玩家队/精英队成员登记 engaging_me；攻击杂兵不登记。
- [ ] 反复切换操控无残留"守旧长机"的僚机。
- [ ] Sentinel + Lv5+ 满编队 FPS 掉幅 < 15。
