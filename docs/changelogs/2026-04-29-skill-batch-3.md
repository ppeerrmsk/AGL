# 2026-04-29 — 第三批便利贴（3 张）evasion 隐身 / J-Turn / 击杀小队恐惧

承接 [batch-2](2026-04-29-skill-batch-2.md)。本次实装 evasion 系列两张关键技能 + 击杀小队恐惧。

## 3 张新技能

| id | 稀有度 | 关键词 | 效果 |
|---|---|---|---|
| `evasion_stealth` | NEXT_GEN | evasion_mode, stealth | 规避模式中获得隐身 |
| `evasion_herbst` | CLA | evasion_mode, panic_save | 规避模式被攻击自动 J-Turn |
| `skill_kill_squad_fear` | ADV | fear, kill | 击杀敌人后其小队成员 6s FEAR |

## 实现要点

### Evasion 隐身（NEXT_GEN）
**独立 bool 派生模式**（同 cloud OVERLOAD 的设计）：
- `Aircraft.evasion_stealth_active`（解锁标记）
- `Aircraft._in_evasion_stealth`（运行时，由 `set_evasion_mode` 切换）
- `StatusEffects.update`：`status_stealth_active = status_effects.has(STEALTH) or _in_evasion_stealth`
- 不进 status_effects，避免与未来其它 STEALTH 限时来源冲突
- 复用 `StatusEffects.update` 中已有的 owner-tracked `is_cloaked` 切换链

### Evasion J-Turn（CLA）
**钩子触发模式**：
- 在 `SkillHooks.dispatch_on_hit` 加新分支
- 条件：evasion_mode ON + evasion_herbst_active + HerbstManeuver.can_activate
- 转向方向 = `sign(my_right · to_attacker)`（朝攻击者方向 J-Turn 反咬）
- `apply_upgrade("evasion_herbst")` 自动挂载 HerbstManeuver 子节点

**Cobra × J-Turn 互斥**：两机动都改姿态，同时跑视觉混乱
- J-Turn 触发前查 `cobra.is_active` → 跳过
- Cobra 触发前查 `herbst.is_active` → 跳过
- Cobra 优先级更高（更短暂，先到先 lock）

### 击杀小队恐惧（ADV）
- `SkillHooks._apply_squad_fear(victim)`：经 `victim.AIController.squad.members` 列表逐个 `apply_status(FEAR, 6s)`
- 名单制不是范围制（不调 AOE）
- UAV/无驾驶员单位 `Aircraft.apply_status` 自动静默丢弃（之前 bugfix 已修），无需预筛
- 不会施加给 victim 自己（已死）

## 文件清单

**改动**：
- `scripts/aircraft.gd` — `evasion_stealth_active` / `_in_evasion_stealth` / `evasion_herbst_active`；`set_evasion_mode` 同步 `_in_evasion_stealth`；`_update_cobra_skill` 加 herbst 互斥检查
- `scripts/status_effects.gd` — `status_stealth_active` 派生 OR `_in_evasion_stealth`
- `scripts/survivor/skill_hooks.gd` — 新常量 `SKILL_KILL_SQUAD_FEAR` / `SKILL_EVASION_HERBST` / `KILL_SQUAD_FEAR_DURATION`；`dispatch_on_kill` 加 `_apply_squad_fear` 分支；`dispatch_on_hit` 加 evasion_herbst 分支（互斥 cobra）；`_apply_squad_fear` helper
- `scripts/survivor/survivor_data.gd` — 3 张新 UPGRADES
- `scripts/survivor/survivor_player.gd` — 2 个新 stat case（evasion_stealth / evasion_herbst）；evasion_herbst 自动挂 HerbstManeuver 子节点
- `i18n/translations.csv` — 6 条翻译

## UPGRADES 总数

约 **63 张**。剩余便利贴需要更复杂基础设施：
- 缠斗累计恐惧 / 后半球减速光环 → engaging_me 反向索引（AI 切目标时增量写）
- 4s 装填导弹突破上限 → evasion 期间专用 timer
- F-14 全僚机锁同一目标 → 僚机管理层 0.5s 检查
- 持久 flare 实体（已决定跳过）
