# 2026-04-29 — 技能系统基础设施 + 抽卡稀有度 + 战区奖励降级

## 概述

为生存模式技能扩展（白板 ~40 张便利贴）铺好基础。本次落地的是**框架层**——
具体技能由后续按需逐张接入即可，每张技能 = 配置 +（可能的）一两行钩子。

## 共享基础设施

### §1.1 damage_kind 参数化
所有伤害入口加可选 `kind` 参数：
```
CombatUnit.take_damage(amount, attacker=null, kind="")
CombatUnit.take_damage_from(amount, attacker, kind="")
```
- 枚举字符串："gun" / "missile" / "aoe" / "rocket" / "laser" / "railgun" / "ground_crash" / "collision"
- `Aircraft._apply_damage` 末尾经由 `_last_damage_kind` meta 传给钩子链
- 改造点：bullet_manager / missile_manager（直接命中 + AOE）/ laser_equipment / railgun_equipment / ai_controller（盾机 + Kamikaze）/ aircraft._check_ground_crash
- `take_bullet_damage` 内部自动写 kind="gun"，老调用点无需改

### §1.2 evasion_modifiers 容器（边界差量）
解决"进入 evasion / 退出 evasion / 进入云 / 退出云"反复抖动 cd 的问题。
```
Aircraft.evasion_modifiers: Dictionary = {
    "weapon_cd_mult": 1.0,
    "flare_cd_mult": 1.0,
    "missile_reload_mult": 1.0,
    "cruise_speed_mult": 1.0,
}
```
`set_evasion_mode(true/false)` 切换瞬间一次性按倍率 scale/unscale 现有倒计时——
进行中的 cd 不会"倒回去"，只按比例缩放。

### §1.3 AOE 状态广播 — `scripts/survivor/aoe_broadcast.gd`
单次扫 `CombatUnit.all_units` + 距离平方 + apply_status max() 合并语义。
3km × 25 单位 < 10μs / 触发。事件驱动（击杀 / 释放 flare / 导弹爆炸时）。

### §1.4 击杀 / 受击钩子链 — `scripts/survivor/skill_hooks.gd`
- `dispatch_on_kill(killer, victim)`：从 `StatusEffects.on_kill` 末尾调用
- `dispatch_on_hit(victim, attacker, kind, amount)`：从 `Aircraft._apply_damage` 调用
- `on_evade_missile(evader)`：flare 成功 jam 后由 aircraft_flares 调用（待接入）
- 钩子按 `killer.upgrade_stacks` 的 flag 早退；不命中开销 = 1 dict.has

### §3 FEAR → AI panic
`ai/bfm_tactics.gd:choose_tactic` 顶层判断 `aircraft.status_fear_active` → 强制 EXTENSION。
不动 _current_target，只换战术 → 玩家有视觉反馈"敌人转身就跑"。

## 战区奖励降级（§4）

- 删除所有 `evolved: true` 字段——原战区奖励技能（vapor_dodge / ecm_pod /
  fire_and_forget / shock_absorb / executioner）现在进入随机升级池
- 新增 `scripts/survivor/zone_reward_registry.gd`：模块化映射，默认空 →
  战区只回血。后续设计师按战区填表：
  ```
  ZoneRewardRegistry.register_reward(&"BOSS_F47", "fire_and_forget")
  ```
- `survivor_mode._on_zone_mission_completed` 优先查 registry，未注册回退到 `_zone_data.get_reward`

## 抽卡稀有度（§5 / §7）

### Rarity 枚举（`SurvivorData.Rarity`）
| 档 | 设计语义 |
|---|---|
| STABLE | 纯数值轻微提升 |
| ADVANCED | 数值显著 + 简单触发 |
| EXPERIMENTAL | 解锁新战术维度 |
| CLASSIFIED | 跨系统强联动 |
| NEXT_GEN | 改变战斗节奏 |

### 抽卡 — `SurvivorData.pick_3_upgrades(pool, owned_stacks, pity_counter, level)`
1. 按 rarity 分桶
2. Pity：超阈值（EXP=5/CLA=8/NEXT=12）的最高档强制保底 1 张
3. 默认 2 槽 LOW（Stable+Advanced）+ 1 槽 HIGH（EXP+）
4. 每槽内 `RARITY_BASE_WEIGHT × keyword_steering` 加权随机
5. 不重复抽同 id

### 流派引导 — `compute_keyword_steering_weights`
玩家每持有 1 stack 同 keyword 技能 → 该 keyword 的同类技能权重 +20%（封顶 +100%）。
等级 < 5 时 steering 折半防早期 funnel。

### 前置链（§6 复用现有 `requires_skill`）
原 `is_upgrade_available_for` 已支持 `requires_skill: [id...]`，至少持有列表中一个即解锁。

## Debug 工具

### F4 实时状态划区（§7.5）
`survivor_debug_skills.gd` 顶部加 `RichTextLabel`，每 0.25s 刷新：
- 当前状态效果（FEAR / INVINCIBLE / ... 剩余秒数）
- HP / max_hp / 高度档 / evasion 开关
- evasion_modifiers 当前倍率
- 已选技能数
- pity 计数 / keyword steering 倍率

### F9 EventLogger 技能快照（§7.6）
日志末尾追加 `=== SKILLS SNAPSHOT @ t=... ===`：
- Active upgrades（含 rarity 标签 + keywords）
- Active status effects
- evasion_modifiers / pity / steering 全部

## 样例技能（7 张）

接入 SkillHooks 钩子链验证整个机制：
- `skill_kill_bloodlust` (ADVANCED) — 击杀进嗜血
- `skill_damaged_bloodlust` (ADVANCED) — 受伤进嗜血（被打刷新）
- `skill_head_on_perma_hp` (CLASSIFIED) — 对头击杀 +5 max_hp + hp（局内永久）
- `skill_head_on_aoe_fear` (CLASSIFIED) — 对头击杀 3km 内 4s FEAR
- `skill_missile_hit_invul` (EXPERIMENTAL) — 被导弹命中 2s 无敌（无敌期间不刷新）
- `skill_lowest_alt_kill_invul` (EXPERIMENTAL) — 低空击杀 2s 无敌
- `skill_gun_kill_fear` (EXPERIMENTAL) — 机炮击杀周围 3s FEAR

## 用户 Q&A 落实

| 问题 | 决策 |
|---|---|
| Q1 进入加 / 退出减 | evasion_modifiers 边界差量；不每帧重算 |
| Q2 多源 status 合并 | 同 id 取 max 持续时间；INVINCIBLE 走 `apply_status(..., "no_refresh")` |
| Q3 局内持久；僚机算你的 | upgrade_stacks 一局生效；SkillHooks 默认 team==0 触发 |
| Q4 damage_kind | 枚举字符串 + meta 路由 |
| Q5 单目标只射 1 发 | （后续接入导弹齐射技能时 cap n=min(locks, missiles)）|
| Q6 +5 HP 行为 | max_hp + hp 同步 +5 |
| Q7 持久 flare | 跳过（性能/复杂度风险） |
| Q8 链式触发 | 已有；嗜血 max() 自然刷新 |
| Q9 3km AOE 性能 | < 10μs/触发，事件驱动不每帧 |
| Q10 FEAR 强度 | 加 panic 强制 EXTENSION |

## 性能验证清单（守则要求）

- 边界差量（cloud / evasion）：进出事件触发，每帧 1 个 bool 比对
- 击杀 / 受击钩子：低频，AOE 单次 < 10μs
- pick_3_upgrades / steering：升级时点一次（极低频）
- StatusEffects.update：O(状态数 ≤ 7)，已有
- 没有引入任何"全场每帧扫描"

## 后续工作（不在本次）

1. 把 ~30 张便利贴技能逐张接入：每张 = UPGRADES 一条 + 对应钩子（多数走 SkillHooks 已有，部分要新机制）
2. evasion_modifiers 的具体技能（cobra/jturn/隐身 等需要再加触发器）
3. 战区→技能绑定表：用户后续在 ZoneRewardRegistry 填
4. 稀有度 base_weight / pity 阈值 / steering 倍率按手感 balance
5. 升级 UI 染色 / 稀有度标签（survivor_upgrade_ui.gd）

## 文件清单

**新增**：
- `scripts/survivor/aoe_broadcast.gd`
- `scripts/survivor/skill_hooks.gd`
- `scripts/survivor/zone_reward_registry.gd`

**改动**：
- `scripts/combat_unit.gd` — take_damage 加 attacker/kind；apply_status 加 mode
- `scripts/aircraft.gd` — evasion_modifiers + _apply_evasion_modifiers + take_damage 改签 + dispatch_on_hit + ground_crash kind
- `scripts/aircraft.gd:_check_ground_crash` — 加 kind=ground_crash
- `scripts/ground_unit.gd` / `naval_unit.gd` / `naval/mount_target.gd` — take_damage 签名扩展
- `scripts/bullet_manager.gd` / `missile_manager.gd` — 全部 take_damage 调用加 kind
- `scripts/equipment/laser_equipment.gd` / `railgun_equipment.gd` — 加 kind
- `scripts/ai_controller.gd` — 盾机 + kamikaze 加 kind
- `scripts/status_effects.gd` — on_kill 调 SkillHooks.dispatch_on_kill
- `scripts/ai/bfm_tactics.gd` — choose_tactic 顶 FEAR → EXTENSION
- `scripts/event_logger.gd` — _dump_skill_snapshot 末追加技能快照段
- `scripts/survivor/survivor_data.gd` — Rarity 枚举 / pick_3_upgrades / steering / 7 个样例技能；删 evolved
- `scripts/survivor/survivor_mode.gd` — _pity_counter；pick_3_upgrades 调用；ZoneRewardRegistry 查询；upgrade_stacks meta 暴露
- `scripts/survivor/survivor_debug_skills.gd` — _live_label 实时状态划区 + _process 0.25s 刷新
- `i18n/translations.csv` — 新增 7 + 5 = 12 条翻译 key
