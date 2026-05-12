# Known Seams · 项目架构耦合点

> 本文档登记 AGL 代码里**反复绊倒 bug 修复 / 容易让人踩同样坑**的架构耦合点。每次 fix
> 撞到地基，先来这里看是否已记录；新发现就写一条。这份表是下一轮 refactor 排期的输入，
> 也是新成员（包括下一个我）避免踩老坑的索引。
>
> **规则**：只记"反复出血"的 seam，不记一次性 bug。每条标"踩到次数 + 解法状态"。

---

## SEAM-001 · 机动性 buff 必须走 effective_*() accessor

**症状**：加任何"影响速度 / G 力 / 失速 / 转弯"的 buff 时，AI 战术层看不到 buff 抬升。
玩家升级名存实亡（规避加力 +40% / BLOODLUST +G / lock_panic +G / EXECUTIONER +Speed
都曾因 Situation 直读 `params.*` 而对 AI 失明）。

**根因**：[Situation.from_aircraft](../../scripts/ai/tactical/situation.gd) 直读
`ac.params.*` 字段，绕过运行时 buff 注入。AI 战术层基于 Situation 决策 → 不知 buff 存在。

**踩到次数**：5+

**解法**（已成文，2026-04 早期）：所有运行时 buff 通过 `aircraft_physics.gd` 的
`effective_*()` accessor 注入：
- `effective_max_g(ac)` — G 力相关
- `effective_max_speed_kmh(ac)` — 顶速相关
- `effective_cruise_speed_kmh(ac)` — 巡航速度相关
- `effective_stall_speed_kmh(ac)` — 失速基数相关
- `effective_corner_speed_kmh(ac)` — 自动随 effective_max_g 抬升

**约束**：禁止在 `update_speed` / `update_bank` / `update_heading` 等物理 tick 里
散点 if-else 乘 buff，禁止在 Situation 里直读 `ac.params.*`。详见 [CLAUDE.md](../../CLAUDE.md)
"加机动性 buff 的规范"段。

---

## SEAM-002 · CombatUnit.all_units 与 MountTarget 一致性

**症状**：把舰船 mount 摘出 `CombatUnit.all_units` 做"船一个雷达"优化时，玩家锁不上船。

**根因**：玩家锁船依赖 `radar_targets[mount]` 累积，摘掉后彻底锁不上。

**踩到次数**：1（已记 memory）

**解法**：MountTarget 必须留在 `all_units`。优化只能改 shooter 那一层，不能动锁定一致性。
详见 user memory `feedback_mount_target_in_all_units.md`。

---

## SEAM-003 · 脏驱动 redraw 跟踪必须涵盖所有视觉决定字段

**症状**：船体状态标签随相机缩放变形（标签随世界放大缩小，与飞机标签的"恒定屏幕大小"
行为不一致）。新刷出来的船一开始巨大，被攻击后才"突然变正常"。

**根因**：`naval_unit.gd:_should_redraw` 只跟踪 hp / lock / mounts / heading_int / speed_int /
weak_revealed 等字段，**没有跟踪 `viewport_transform.scale`**。`_draw_status_label` 把
`inv_zoom = 1 / viewport_scale.x` 烤进 canvas item，缩放变化时不重画就显示错。

"被攻击后变正常"是命中暴露 `weak_point.revealed` 触发每帧重画 → 副作用 rebake，**与伤害
本身无关**。

**踩到次数**：1（v1 修了但放错位置；v2 修对）

**解法**：把 zoom 量化检查放在 `_physics_process` 内 LOD 节流**之前**，每帧执行、独立
`queue_redraw()`，不依赖 `_should_redraw` 的早返回路径（远距船被节流 5/6 帧 + 早返回路径
会短路末尾 zoom 检查）。

**模式**：任何把 `viewport_transform` / `inv_zoom` / 屏幕空间值烤进 canvas item 的
`_draw` 逻辑，都需要在脏驱动 redraw 里跟踪 zoom 变化。这是脏驱动 redraw 优化的隐藏依赖。

详见 [docs/changelogs/2026-05-08-bug-fixes-batch.md](../changelogs/2026-05-08-bug-fixes-batch.md)
section A。

---

## SEAM-004 · FEAR 状态有 4 个入口分散在 3 个文件

**症状**：加任何"FEAR 联动 buff"（fear_chills 让 FEAR 同时附带 SLOW 等）必须 4 处都改，
否则会出现"某些路径触发 FEAR 时联动失灵"。fear_chills 一开始只在单体路径生效，
gun_kill / head_on / 凝视压迫三条 AOE 路径全漏。

**根因**：FEAR 触发器分散：
1. `survivor_spawner._apply_player_fear`（单体，`fear_squad_spread` 用）
2. `skill_hooks.dispatch_on_kill` `gun_kill` AOE
3. `skill_hooks.dispatch_on_kill` `head_on` AOE
4. `survivor_mode` 凝视压迫 `fear_on_lock_threshold` AOE

每条路径独立调 `apply_status(FEAR)` 或 `AOEBroadcast.apply_status_in_radius(FEAR)`，
缺乏"联动钩子"集中点。

**踩到次数**：2（fear_chills v1 漏一处；v2 漏两处）

**解法**（已实施）：联动检查塞进 `AOEBroadcast.apply_status_in_radius` 内部 —— 三条 AOE
都过这个 helper，集中处理 fear_applies_slow。单体路径继续走 `_apply_player_fear`
helper（已存在）。未来加新 FEAR 联动 buff 只改这两处。

**约束**：所有"AOE FEAR 触发"必须用 `AOEBroadcast.apply_status_in_radius`，不要直接
循环调 `apply_status`。所有"单体 FEAR by 玩家"必须用 `_apply_player_fear` helper，不要
直接调 `target.apply_status(FEAR)`。

详见 [docs/changelogs/2026-05-08-bug-fixes-batch.md](../changelogs/2026-05-08-bug-fixes-batch.md)
section B。

---

## SEAM-005 · 累积式光环触发后必须有内置 CD

**症状**：玩家累积光环（rear_aura_slow / jam_aura）触发 debuff 后 8s 累积窗口内被反复
触发：每达阈值施 debuff 4s，但累积器不停清零重算 → 在 debuff 期间内部继续累积新一轮 →
debuff 结束当帧又触发一次 → VFX 脉冲叠加 + status duration 反复 max() 刷新成"近似永久"。

**根因**：累积式光环（异步达阈值）与瞬时 AOE（同步全员生效）的语义混淆。早期把累积式
也当 AOE 处理，发范围 VFX 脉冲；触发后没有 CD 锁，下一帧就能再次累积 → 累积本身没问题，
但触发频次失控。

**踩到次数**：1（这次修）

**解法**（已实施）：每个累积光环加内置 CD 字段（`_rear_aura_cd_remaining` /
`_jam_aura_cd_remaining`），触发后整段锁 4s（= debuff 时长，正好同步释放无空窗）。
撤掉累积式光环的范围 VFX 脉冲——异步达阈值不应当作 AOE 圈，状态图标已足够提示。

**模式**：**累积式（异步）≠ AOE（同步）**。
- AOE：所有目标本帧同时检查 + 同时生效，发范围脉冲合理。
- 累积式：每个目标独立在自己达阈值时生效，发范围脉冲会被多次触发误用。需要 CD 锁。

详见 [docs/changelogs/2026-05-08-aura-internal-cd.md](../changelogs/2026-05-08-aura-internal-cd.md)。

---

## SEAM-006 · 中队 spawner 不必显式设 `_state`（自校正守卫已存在）

**症状**：早期加有编队的敌人 spawner 误以为必须 `aircraft._state = ...` 才能进入战术
状态机，结果状态被覆盖、僚机行为异常。

**踩到次数**：1（已记 memory）

**解法**：AIController 有 spawn 自校正守卫，加敌人只需设 `squad + squad_index`，
**不要写 `_state`**。详见 user memory `feedback_squad_spawner_auto_state.md`。

---

## SEAM-007 · BOSS 挂点系统的 parent_ship 类型耦合（Mother Goose 暴露）

**症状**：早期 `MountTarget.parent_ship: NavalUnit` 硬绑死，让"挂点 + 弱点"系统只能给船用。
Mother Goose（Aircraft 子类带挂点）出来时，MountTarget 无法挂在 Aircraft 上。

**根因**：`parent_ship` 类型过窄，`_log_unit_name` / damage 路由 / 锁定代理等都假设
`parent_ship is NavalUnit` 直读 `full_name` 等 NavalUnit-only 字段。

**踩到次数**：1（这次桶 A · Sub 2 修）

**解法**（已实施）：`parent_ship: NavalUnit → CombatUnit` 类型放宽。所有
NavalUnit-only 字段访问改为显式 `parent_ship is NavalUnit` 类型守卫 + cast，或走
CombatUnit 通用 API（`heading` / `global_position` / `team` / `is_destroyed` /
`take_damage_at(amount, hit_pos)`）。Aircraft 也提供 `take_damage_at` forwarder。

**模式**：BOSS 设计早期就要考虑"挂点系统是否要给非船单位用"。如果可能，挂点 / 弱点 /
锁定代理的 parent 类型从一开始就用 CombatUnit。

详见 [docs/changelogs/2026-05-08-mother-goose-boss.md](../changelogs/2026-05-08-mother-goose-boss.md)
Sub 2 段。

---

## SEAM-008 · CombatUnit 基类契约与子类实现脱节

**症状**：`combat_unit.gd:82-87` 注释 + `status_effects.gd:96-98` 写明"地面单位 / 船 / 巨型
BOSS 只识别 JAM，其它状态仅对 Aircraft 生效"。但 NavalUnit 实现完全没遵守：
- 不调 `StatusEffects.tick(self, delta)` → `status_jam_active` 永不被写，JAM 形同虚设
- `NavalWeapons.update` 没有 `if status_jam_active: return` 早返 → 即使 JAM 写进字典，船依然开火
- 没覆写 `apply_status` 过滤 → SLOW/FEAR 等被静默写入永不衰减的死条目

外部代码（玩家技能 / AOE 广播）按契约调 `naval.apply_status(JAM, 5.0)`，期望船停火 5 秒 ——
但实际什么也不发生。类似地 `bullet_manager.gd:656` 给 NavalUnit 传 `can_hit_weak_point=false`
做硬隔离，绕过 NavalUnit 自己已经设计好的 hull_dmg_mult 双池机制，制造"机炮打不死船"的
体验 bug。这些都是**基类提供的契约（注释 / 默认行为）和子类实现不一致**导致的同一类问题。

**根因**：
1. 基类契约只在注释里，没有 lint / 测试强制。
2. 子类（NavalUnit）只重写了"必须重写才能跑"的方法（_physics_process / take_damage_at），
   "应该重写但不重写也能编译"的方法（apply_status / 状态 tick 调用）会被遗漏。
3. 调用方（bullet_manager）在外部用参数硬编码绕过子类逻辑，是另一个变体。

**踩到次数**：3+（本次同次发现 3 个：JAM 不工作、SLOW/FEAR 永驻、机炮弱点屏蔽）

**解法**（已实施 part）：
- 三处补齐：tick / JAM 早返 / apply_status 覆写
- can_hit_weak_point 子类外部硬编码改回 true，由 NavalUnit 自己用 hull_dmg_mult 决定平衡

**模式**：
- **任何 CombatUnit 新子类**（未来船 / 巨型 BOSS / 地面新单位）都必须自检：
  - [ ] `_physics_process` 里有没有 `StatusEffects.tick(self, delta)`？
  - [ ] 武器 / 行动逻辑入口有没有 `if status_jam_active: return`？
  - [ ] 是否需要覆写 `apply_status` 过滤掉对该单位类型没有作用通路的状态？
  - [ ] 是否需要覆写 `take_damage_at`（带位置感知）+ `take_damage`（兜底）？
- **调用方（bullet_manager / missile_manager / 技能）不应该用参数硬编码绕过子类伤害模型**。
  应该让子类自己用 `hull_dmg_mult` / 路由优先级 / 内部 routing 做平衡。

**约束（新加）**：加新 CombatUnit 子类前先按上面 4 个 checkbox 自检；改伤害平衡时
**优先调子类自己的字段**（NavalParams.hull_hp_max / mount hp / weak_point_hp），不要在
调用方传 `can_hit_*=false` 类的硬开关。

详见 [docs/changelogs/2026-05-12-naval-damage-and-jam-fixes.md](../changelogs/2026-05-12-naval-damage-and-jam-fixes.md)。

---

## SEAM-009 · altitude_authority_mult 与 PE↔KE 反抽公式的耦合

**症状**：玩家拿到 vapor_dodge（云雾机动）后开局速度异常低（spd 卡在 138~200kt），
无任何 debuff，加力推力顶不住，疯狂爬升（vs ≈ 900 m/s）一路把横速吃光。

**根因**：`altitude_authority_mult`（设计意图："操纵响应度"）被同时乘进 `update_altitude`
三处：`max_climb` / `gain` / `smooth_rate`。其中 `max_climb` 被放大到 500+ m/s 后，PE↔KE
公式 `gravity_effect = GRAVITY · vs / spd · PE_KE_BOOST(2.5)` 反向抽 spd，每秒 ≈ 110 m/s
速度损失，加力推力（≈ 17 m/s²）完全顶不住。
[scripts/aircraft/aircraft_physics.gd:267 update_altitude](../../scripts/aircraft/aircraft_physics.gd:267)
× [scripts/aircraft/aircraft_physics.gd:255 PE↔KE](../../scripts/aircraft/aircraft_physics.gd:255)
两段都涉及 vs，缺一个出血点。

**踩到次数**：2（这次 + 用户记忆中至少一次同样症状）

**解法**（2026-05-12）：在 [aircraft_physics.gd:273](../../scripts/aircraft/aircraft_physics.gd:273)
和 [aircraft_physics.gd:1207 step_altitude](../../scripts/aircraft/aircraft_physics.gd:1207)
两处把 `max_climb` 改为 `base_climb * minf(alt_mult, 1.3)`。`gain` / `smooth_rate` 仍由
`alt_mult` 全幅放大（响应度保留），物理顶速最多 +30%（PE↔KE 损耗回到可承受档）。

**约束**：未来加任何新的 `altitude_authority_mult` 来源前，先确认这个 cap 仍合理；
不要在物理 tick 里散点乘 `altitude_authority_mult`（参考 SEAM-001 的 effective_*() 思路）。

---

## 维护约定

- 修 bug 时撞到地基 → 先来这里看是否已记。已记 → 票数 +1，可能升级到 refactor 优先级。
  未记 → 加新条目（症状 / 根因 / 踩到次数 / 解法状态）。
- "踩到次数 ≥ 2 + 30 天内" 的 seam 在 plan 工作流里会被升级到 `refactor/<seam>` 分支
  做档 3 集中修。
- 解法已实施的 seam 不删，留作历史 + 模式参考。新成员看到能避免重复发明。
- 这份文档 + [CLAUDE.md](../../CLAUDE.md) "加机动性 buff 的规范" + [docs/DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md)
  共同构成 AGL 的"防撞抗体"。

### Git log 自动计票约定

修 bug 撞到本表里某 seam 时，commit message 里加 `[ref:SEAM-XXX]` 标记（可放任何位置，
正文或脚注都行）。然后用 `tools/seam-report.ps1` 扫 git log 统计票数：

```powershell
.\tools\seam-report.ps1                # 全历史
.\tools\seam-report.ps1 -Since 30      # 最近 30 天（refactor 阈值判断窗口）
.\tools\seam-report.ps1 -Verbose       # 同时打印每条 commit 的 hash + 标题
```

git log 的票数 = 实测踩坑频次（验证文档里"踩到次数"基线是否仍然准确）。
两个数都 ≥ 2 + 都在 30 天内 → 该 seam 已成熟到值得做档 3 refactor。
