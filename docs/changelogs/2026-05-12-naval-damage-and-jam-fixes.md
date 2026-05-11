# 2026-05-12 — NavalUnit 伤害路由 / JAM 契约修复（3 处）

## 背景

玩家用机炮打 CG-132 Vanguard 时，子弹像撞到空气墙：截图里船上的 ✕ 是 [naval_unit.gd:811 `_draw_dead_mount`](../../scripts/naval/naval_unit.gd) 的"已摧毁挂点"标记。挂点全部打掉、弱点暴露后，机炮对船完全失效。

用户澄清：**这不是设计意图**。弱点有 HP，应当能被任何带 HP 数值的武器扣血。当前代码错误地把"机炮 ↔ 弱点"做了硬隔离。

排查同类"对船伤害/状态被错误屏蔽"问题，找到 3 处需要修。

## 改动

### A. 机炮对暴露的弱点完全无效

**位置**：[`bullet_manager.gd:656`](../../scripts/bullet_manager.gd)

**根因**：子弹命中 NavalUnit 时调 `take_damage_at(..., 0.15, false)` —— `can_hit_weak_point=false` 让机炮路由直接跳过弱点路径。弱点暴露后玩家被卡死：弱点免疫机炮 + 全挂点已死无可路由 + hull 只吃 15% 倍率 → 玩家弹药耗尽都打不沉。

**修法**：参数改成 `true`。`hull_dmg_mult=0.15` 独立保留，已经防住"一梭子秒船"；不再需要靠 `can_hit_weak_point` 做二次屏蔽。
同步改 [`naval_unit.gd:430`](../../scripts/naval/naval_unit.gd) 函数注释 + bullet_manager 命中循环里的旧注释。

### B. 导弹近炸 AOE 永远扫不到船

**位置**：[`missile_manager.gd:425 _update_aoe_zones`](../../scripts/missile_manager.gd)

**根因**：
```gdscript
var alt_ok := alt_diff < AOE_ALT_TOLERANCE or unit is GroundUnit
```
船 altitude=0，AOE 中心在空中（导弹爆炸点）→ `alt_diff` 必然超容差 → `unit is GroundUnit` 的兜底没把 NavalUnit/MountTarget 加进去 → 船永远拿不到 AOE 伤害。

**修法**：把例外列表补全为 `or unit is GroundUnit or unit is NavalUnit or unit is MountTarget`，与导弹直接命中检查 [`missile_manager.gd:301`](../../scripts/missile_manager.gd) 的写法对齐。同时把 NavalUnit 的 AOE 路由从 `take_damage_from(zdmg, zsrc, "aoe")`（伤害落在船中心、走 1.0 默认倍率）改成 `take_damage_at(zdmg, zpos)`（AOE 中心位置 → mount/弱点 routing 更准）。

### C. 船无法被 JAM（契约和实现脱节）

**契约**（[`combat_unit.gd:82-87`](../../scripts/combat_unit.gd) 注释 + [`status_effects.gd:96-98`](../../scripts/status_effects.gd) 注释）：
> 除 JAM 外的状态（INVINCIBLE / STEALTH / BLOODLUST / OVERLOAD / FEAR / SLOW）仅对 Aircraft 生效。地面单位 / 船 / 巨型 BOSS 只识别 JAM。

但 NavalUnit 实现里：

1. **不 tick 状态**：[`naval_unit.gd:159 _physics_process`](../../scripts/naval/naval_unit.gd) 没有调 `StatusEffects.tick(self, delta)`。对比 [ground_unit.gd:58](../../scripts/ground_unit.gd) / [sam_unit.gd:20](../../scripts/sam_unit.gd) / [aa_gun_unit.gd:22](../../scripts/aa_gun_unit.gd) 都有。结果：船的 `status_effects` 字典永不衰减、`status_jam_active` 永不被写。
2. **武器不读 JAM**：[`naval_weapons.gd:51 update`](../../scripts/naval/naval_weapons.gd) 没有 `if status_jam_active: return` 早返路径，对比 [aa_gun_unit.gd:121](../../scripts/aa_gun_unit.gd) 已有。结果：即使 JAM 被写进字典，船依然开火。
3. **apply_status 不过滤**：NavalUnit 没覆写 `apply_status` → 调用方传 SLOW/FEAR/BLOODLUST 都被写入字典且永驻不衰减，违反契约。

**修法**：
- [`naval_unit.gd:165`](../../scripts/naval/naval_unit.gd) `_physics_process` 顶部加 `StatusEffects.tick(self, delta)`（is_destroyed 早返之后、`_update_movement` 之前）
- [`naval_weapons.gd:54`](../../scripts/naval/naval_weapons.gd) `update(nu, delta)` 入口加 `if nu.status_jam_active: return`
- [`naval_unit.gd:486`](../../scripts/naval/naval_unit.gd) 覆写 `apply_status`：仅 `id == StatusEffects.JAM` 时调 super，其它静默丢弃。参考 [aircraft.gd:1931](../../scripts/aircraft.gd) 同模式。

## 顺手核对（无需改）

- 火箭弹直击 ([`bullet_manager.gd:641`](../../scripts/bullet_manager.gd)) → 0.5 / true，OK
- 火箭弹 AOE ([`bullet_manager.gd:433`](../../scripts/bullet_manager.gd)) → 0.5 / true，OK
- 导弹直击 ([`missile_manager.gd:338`](../../scripts/missile_manager.gd)) → 默认 1.0 / true，OK
- 电磁炮 ([`railgun_equipment.gd:350`](../../scripts/equipment/railgun_equipment.gd)) → 走 `take_damage_from` → NavalUnit.take_damage → take_damage_at(default)，OK
- 玩家激光按设计只施加 SLOW，对地/船不应反应 → 不改

## DoD 验证

- [ ] 生存模式刷 CG（survivor_debug_spawn）
- [ ] 用机炮：打 2 挂点 → 弱点暴露 → 继续射 → 弱点 HP 应下降 → 沉船
- [ ] 火箭弹/导弹/电磁炮回归：原本能打的依然能打
- [ ] 导弹近炸 AOE 在飞机附近爆炸 + 圈内有船 → 船吃 AOE 伤
- [ ] JAM：玩家技能或 AOE 给船施 JAM → SAM/CIWS/VLS 全部停火，几秒后恢复
- [ ] SLOW/FEAR 施加给船 → `status_effects` 里不出现条目（覆写过滤），无任何行为变化
- [ ] F9 dump → EventLogger 走的是预期 kind（gun / aoe / missile）

## 关联

- 新增 SEAM-008（"基类契约与子类实现脱节"），详见 [`known-seams.md`](../architecture/known-seams.md)。
- 代码索引补"海上单位 / 船伤害路由" + "状态效果" 两节，详见 [`code-index.md`](../reference/code-index.md)。
