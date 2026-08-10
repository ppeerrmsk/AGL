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

**2026-07-03 审计备注**：planner 主干（Situation/tactical/）已零旁路 ✅；但 **legacy
路径系统性直读 params.***（bfm_tactics set_engage_speed 全家 / ai_controller
`_process_simple` orbit 等 10+ 处）。当前未爆雷仅因敌机现有 buff（指挥光环）直改 params
字段。给敌机加任何"状态型"机动 buff（走 effective_* if 块）前，必须先修这条直读带，
否则 SEAM-001 原病灶在敌机侧完整复发。

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

**2026-08-08 补充**：`viewport_transform.scale` 还包含 `canvas_items` 的窗口 stretch。
它适合做屏幕像素尺寸补偿，却不能直接作为语义 LOD 阈值；否则最大化到 4K（stretch≈2）会把
相机 zoom 0.20 误判为 0.40。标签 LOD 必须先除以 `Viewport.get_stretch_transform().scale`，
统一走 `AircraftRenderer.label_lod_scale()`；飞机和地面单位不能各自直读最终 viewport scale。

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
[scripts/aircraft/aircraft_physics.gd:322 update_altitude](../../scripts/aircraft/aircraft_physics.gd:336)
× [scripts/aircraft/aircraft_physics.gd:314 gravity_effect](../../scripts/aircraft/aircraft_physics.gd:328)
两段都涉及 vs，缺一个出血点。

**踩到次数**：2（这次 + 用户记忆中至少一次同样症状）

**解法**（2026-05-12）：在 [aircraft_physics.gd:322](../../scripts/aircraft/aircraft_physics.gd:322)
和 [aircraft_physics.gd:1421 step_altitude](../../scripts/aircraft/aircraft_physics.gd:1318)
两处把 `max_climb` 改为 `base_climb * minf(alt_mult, 1.3)`。`gain` / `smooth_rate` 仍由
`alt_mult` 全幅放大（响应度保留），物理顶速最多 +30%（PE↔KE 损耗回到可承受档）。

**约束**：未来加任何新的 `altitude_authority_mult` 来源前，先确认这个 cap 仍合理；
不要在物理 tick 里散点乘 `altitude_authority_mult`（参考 SEAM-001 的 effective_*() 思路）。

---

## SEAM-010 · 小队横切行为分散在 AI 状态 / survivor `_process` 顺序里，易漏某一处

**症状**（2026-05 squad-cohesion 期间连环踩）：
- 给交战僚机加了"防游走 leash"（`_process_engage`），但**躲弹（EVADE）没 leash** → 僚机被地面 SAM
  反复打、一路 max+AB 躲到 7km 脱队，"守护后方"名存实亡。leash 只覆盖了一个状态。
- 长机被击坠**没接管、直接 GameOver**：`survivor_mode._process` 的死亡检查（→`_on_player_died`）
  排在 spawner 周期 squad cleanup（晋升新长机 + leader_changed 接管）**之前**且节流 → 当帧先 GameOver。
- 长机在 `survivor_mode` 本帧死亡检查之后被武器击毁时，僚机 `SQUAD_FOLLOW` 会先看到死长机并
  把自己的 `AIController.squad` 清成 null；下一帧虽然 `Squad.cleanup()` 晋升了新长机，却只修
  leader/index、不恢复全员反向引用 → 轮盘全队命令退化为只作用当前操控机，数字键仍能逐架切控。

**根因**：小队的**横切关注点**（containment/leash、长机阵亡接管、凝聚模式行为）天然要作用于
**多个 AI 状态**（PATROL / ENGAGE / EVADE_MISSILE / SQUAD_FOLLOW）和 **survivor `_process` 的多个阶段**，
但实现是按"单个状态 / 单个 _process 位置"散点加的 → 加在一处就以为齐了，漏掉另一状态/另一阶段时静默失效。

**踩到次数**：3（EVADE 漏 leash + GameOver 接管 race + AI.squad 解绑 race，同根）

**解法**（2026-05-31，临时）：
- leash 抽成 `AIController.effective_squad_leash()`，在 `_process_engage` **和** `MissileEvasion.process_evade`
  **两处**都查（覆盖 ENGAGE + EVADE）。守后模式用更紧的 `REAR_GUARD_LEASH_DIST`、打地面时放宽。
- 长机阵亡：`_process` 死亡检查改为**先 `_try_takeover_after_leader_down()`**（立即 `_squad.cleanup()`
  同步晋升 + leader_changed 接管），全队覆灭才 `_on_player_died()` —— 不依赖 spawner 周期 cleanup 的时序。
- 2026-08-03：`Squad.cleanup()` / `set_leader()` / `remove_member()` 统一经过
  `_sync_member_bindings()`；`Squad.members/leader` 是结构真源，继任时原子恢复所有幸存
  `AIController.squad`、连续重排 `squad_index`、刷新现有 formation leader 缓存。自动接管的新长机
  走完整 `clear_formation()`，不再残留僚机托管状态。

**根治**（2026-07-05，Phase 2 约束层）：leash / combat_zone 收口到
`AIController._apply_constraints()`——分发前每 tick 统一执行、对所有模态生效（EVADE 已是
modifier，天然被覆盖），两份 leash 拷贝退役。**AI 侧的"按状态散点加约束"模式就此结束**：
新 containment（如 anchor 区域保护）直接加进约束层即可。survivor `_process` 阶段顺序的
另一半（长机接管时序）除 survivor 早检查外，必须由 Squad 结构层原子修复成员反向引用。

**约束**（更新）：给小队加"无论僚机在干什么都该生效"的行为——AI 侧一律进
`_apply_constraints`；survivor `_process` 侧仍需列阶段顺序逐一确认。小队成员关系以
`Squad.members/leader` 为真源，AI 层不得假定自己的 `squad` 缓存不可恢复。

---

## SEAM-011 · 编队槽位"AI 分频写 / 物理 60Hz 读"双频率，写读必须解耦

**症状**：僚机编队跟随"慢一拍"——玩家频繁点地图、长机持续转弯时，僚机追的是上一个 AI tick
的旧槽位，阵型拖泥带水。把任何"随长机机体实时变化"的量缓存成 AI-tick 死点都会复现。

**根因**：槽位有**慢变**（用哪个阵型/第几槽，AI tick 决定就够）和**快变**（offset 旋进长机
当前机体系的世界坐标，必须 60Hz 跟）两部分。旧实现在 `squad_coordination.gd:process_squad_follow`
（AI 分频 ~10~20Hz）把两者**一起**算成冻结的 `ac.target_position`，而 60Hz 的
`aircraft_formation.gd:_build_context` 读这个死点 → 快变部分被钉在 AI tick 频率上。

**踩到次数**：1（2026-06-07 首次显式登记）

**解法**（2026-06-07）：写读解耦——
- **慢变**：`process_squad_follow` 在 AI tick 写 `AIController._formation_offset_committed`（长机本地系偏移，
  未旋转）；`set_formation_target(leader, INF)` 不再写冻结世界槽位。
- **快变**：`_build_context` 每物理帧实时 `slot_pos = leader.pos + committed.rotated(leader.heading)` +
  回写 `target_position` 保一致。无 committed 守卫回退旧值（下游 INF 安全平飞）。

**约束**：以后任何"飞机相对长机/相对世界、且长机在动"的派生量（槽位 / 守后拦截位 / 相对锚点），
**别在 AI 分频 tick 缓存成世界坐标死点**；缓存"相对/本地系不变量"，世界坐标留到物理帧实时旋转。
详见 [squad-cohesion §3.6](../specs/systems/squad-cohesion.md) + changelogs/2026-06-07-formation-realtime-slot.md。

---

## SEAM-012 · 战斗转弯控制器欠阻尼 —— 激进机动时机身大坡反转颤抖

**症状**：飞机硬转 / 追击机动目标 / 躲弹归队时机身剧烈来回压坡（bank ±70°）。慢速机（F-86，cruise 700）
最明显。表现为 bank 在目标方位附近反复过冲反转。

**根因**：`aircraft_physics.gd` 的转弯控制（`update_bank` → `compute_target_bank` + `update_heading`）
本质是**欠阻尼**的位置式（P）控制：bank 追 heading_diff，但缺有效的速度阻尼（D）项，高 bank 时航向过冲
目标 → heading_diff 翻号 → target_bank 翻号 → 来回。多个放大器叠加：①`compute_target_bank` 硬台阶
②`combat_full_bank_diff` 太小（小误差就满坡度）③过冲补偿近似失真且被 cap 卡死。

**踩到次数**：1（2026-06-07 系统排查，分 ~7 层补丁）

**第一轮（治标，2026-06-07）**：台阶→连续斜坡；`combat_full_bank_diff` 放宽；过冲补偿改滚出航向精确积分
`(G/v)·t_roll·(-ln(cosB)/B)` + 临界阻尼式扣减。把"每帧猛翻 buzz"从 501 次/局压到个位数。

**第二轮（治本=根治，2026-06-07）**：把 `compute_target_bank` 整个重写成**临界阻尼 PD 控制**：
`target_turn_rate = kp·heading_diff − kd·current_turn_rate`，`bank = atan(target_turn_rate·v/g)`（协调转弯反推）。
位置式(P)缺失的速度阻尼(D)项接近目标航向时自动提前滚出，从根上消除"过冲→翻号→来回"。
删除所有治标补丁：bank-flip 守卫 / target_bank 翻转去抖 / 滚出精确积分过冲补偿全部移除。

**实现要点（踩坑记录，改这块前必看）**：
1. **命令转速再反推坡度**：(g/v) 与 (v/g) 抵消 → 闭环阻尼与速度无关，跨机型/速度稳健。这是用 turn_rate
   命令而非直接 heading→bank 映射的关键好处。
2. **D 项必须低通**（`TURN_RATE_FILT_ALPHA`）：协调转弯下 ω 几乎一帧跟上指令，直接反馈裸 ω 形成单帧
   代数环 `ω_n = kp·e − kd·ω_{n-1}` → `(−kd)^n` 每帧交替 Nyquist 抖。低通到 ~3 帧时间常数破环。
3. **kd 随 roll_rate 反比**（`kd = clamp(PD_KD_SCALE/roll_rate, …)`）：慢滚机阻尼更大维持临界阻尼。
4. **LOS 前馈试过但关掉**（`PD_LOS_FF=0`）：理论上尾追转弯目标(e≈0 仍需稳态转速)需要它，否则同向
   bank 幅度"呼吸"；但无头扫参实测在离散物理 + AI 分频跳变参考下前馈尖刺过冲恒为害。管线保留待将来抗跳变 LOS 估计。
5. **度量要分清"符号反转"vs"同向呼吸"**：用户抱怨的"大坡反转"是 bank 过零硬翻（左↔右），不是同向幅度脉动。
   harness 两个指标都报。PD 把**符号反转**全场景压到 ≤2（根治目标达成）；残留的是同向呼吸（追内圈出转目标时
   的结构性弛豫，非用户痛点）。盲优化"总反转"会被同向呼吸误导（本轮实测教训）。

调参旋钮全在 `aircraft_physics.gd` 顶部 `PD_*` static var（用 static 方便 harness 扫参）；逐机型经
`combat_bank_aggression`(→kp 缩放) 透传。验证：通过 `bench/run.cmd turn_physics`（Windows）或
`bench/run.sh turn_physics`（其它平台）运行
（看"符号反转"列，全场景 ≤2）；扫参 `--pd-sweep`；可视 `--bench=demo`。
详见 changelogs/2026-06-07-bank-twitch-rootfix-and-test-harness.md。

**约束**：以后改任何"飞机追目标/航点的转弯"逻辑，先用 harness 量化**符号反转**（≤2），别靠肉眼，也别用
同向呼吸总数误导自己。`update_bank`（实物理）与 `step_bank`（预测线）两份必须同步改，否则预测路径撕裂。

---

## SEAM-013 · 战术追踪点"子 intent 抖动" —— crank 侧选择无滞回致长机原地摇摆打转

**症状**：长机（含玩家方 planner 机）对**近似共线 / 对头**的机动目标交战时，机身在 ±60~84° 坡度间
反复硬翻，**航向几乎不动**（hdg 漂移 < 5°），看上去"不停滚转、原地打转"，却打不出有效转弯。
日志特征：`AC_TICK` 里 `bnk` 大幅左右翻（如 +82°→−71°→+84°），但 `tp_brg`（到追踪点方位）极小（±1~7°）。
（2026-06-13 日志 Warhound[Ultra] 24~30s / 106~114s 多段复现。）

**根因（与 SEAM-012 不同层）**：SEAM-012 已证明 bank **控制器**本身临界阻尼、平滑（turn_physics 全场景
符号反转 ≤2）。本 seam 是**喂给控制器的参考点在抖**：
1. `bfm_intent._missile_engage_pos` 的 crank 侧每帧按 `ccw_align > cw_align` 重选，**无滞回**。目标接近
   正前方 / crank 决策边界时两侧 align 几乎相等，单帧噪声就让 crank 侧翻号 → 追踪点在机身两侧
   ±5000px(=10000m) 之间瞬移 → 参考航向大幅摆 → 平滑控制器忠实追摆 → 大坡来回。
2. 顶层 `TacticalPlanner` 有 intent 滞回（`HYSTERESIS_MIN_HOLD=0.5s`），但只防"换 intent"，**管不住
   同一 intent 内追踪点的左右跳**——抖动是 sub-intent 的，滞回看不见。
3. 叠加诱因：`merge_pass`/`lead_pursuit` 的"目标急转 bank>60° 则替代 MERGE_PASS"覆写，会随**目标自己**
   摇摆的 bank 跨 60° 阈值而 toggle，进一步给追踪点换边。

**踩到次数**：1（2026-06-13 武器有效性排查时顺带定位）

**解法状态：已根治（2026-06-13）**。`_missile_engage_pos` 的离散选侧（`ccw if ccw_align>cw_align else cw`）
换成**连续 clamp**：`aim_hdg = los_hdg + clamp(nose_off, ±crank_deg)`，瞄准点 = 该航向 5000px 处。
- nose_off=0（正对目标）→ aim=LOS，无 crank；
- |nose_off|<crank_deg → aim=机头当前方向（顺势直飞）；
- |nose_off|>crank_deg → crank 封顶在 LOS 偏 crank_deg（朝机头侧，维持锁不过冲）。
nose_off 过零时 aim 连续穿过 LOS，**没有"侧"可翻** → 从根上消除瞬移。语义不变（仍朝机头侧 crank、
封顶 crank_deg、维持雷达锁），只是把"满 crank 离散二选一"改成"0~crank_deg 连续偏置"。纯函数、无状态。

**验证**：`scripts/tests/test_weapon_behavior.gd` 加测试 D（经 `--bench=weapon`）：让 nose_off 从 +20°
扫到 −20°，量化相邻步进的 aim 航向跳变。修复后 **翻号=0、最大相邻步进 1.0°**（修复前过零处会 ~30° 跳）。
论证闭合：连续参考（本修复）+ 临界阻尼控制器（SEAM-012 已证 turn_physics 符号反转 ≤2）= 无摇摆。

**约束（再动这块时）**：改 `_missile_engage_pos` 不要触碰 SEAM-012 的 `update_bank`/`step_bank`；
继续用 `--bench=weapon` 的测试 D 守"无翻号"，别靠肉眼。`merge_pass` 的"目标 bank>60° 替代"覆写仍是
潜在二级诱因（目标摇摆传导成本机换 intent），如再现摇摆可给该阈值加滞回带。

---

## SEAM-014 · 命令铁律与 EVADE 争同一根 `_state` 轴，仲裁顺序即行为

**症状**：带玩家命令（commanded_target）的飞机躲弹时 ENGAGE↔EVADE 按 tick 抖动；
`evasion_mode` 卡 true → planner 持续输出 EVADE intent（max+AB、武器静默）直到玩家重新下令。

**根因**：`_enforce_commanded_target`（铁律）排在 `match _state` **之前**且无条件把状态拉回
ENGAGE —— 注释宣称"求生规避优先于命令"，代码顺序与之相反。规避（正交模态）与命令（目标
所有权）都挤在 `_state` 一根轴上，谁先执行谁赢。是重构计划 R2（正交模态混轴）的典型实例。

**踩到次数**：1（2026-07-02 架构体检定位；此前长期存在未被诊断）

**解法**（已实施 2026-07-03，B1）：
- `_enforce_commanded_target` 顶部对 `EVADE_MISSILE` 让位（返回 false，**不清** commanded_target）；
- 有界性：全部 `enter_evade` 入口统一走 `MissileEvasion.should_enter_evade` 分层门
  （真威胁 + flare 不可用才进；被锁/打不到的导弹不算威胁），EVADE 维持由 process_evade
  每 tick 带滞回重新确认，威胁消失立即 exit → `_current_target`(=命令目标) 无缝恢复。
- 验收：`--bench=cmd_evade`（23 断言：分层门 8 + 仲裁 4 + 闭环无抖动 11）。

**约束**：以后任何"正交模态 vs 命令"的优先级问题（新增机动/剧本/状态），先看重构计划
Phase 2 的 modifier 栈方案；在那之前，修改 `_enforce_commanded_target` 入口顺序必须
跑 `--bench=cmd_evade` 守护。

---

## SEAM-015 · 机动模块（Cobra/Herbst）守卫矩阵不对称，靠"同帧双写自卫"

**症状**：Herbst J-Turn 期间 `update_speed`/`update_g_load` 照常跑（守卫只查 Cobra），
Herbst 被迫每帧"先被物理写一次、再自己钳回"的同帧双写自卫（herbst_maneuver.gd 旧注释
自认），正确性依赖 Godot 父先子后树序——改 process_priority / reparent 即碎。

**根因**：每加一个机动模块要在 N 个 `update_*` 里散点补 if 守卫，漏一处就是同帧双写。
重构计划 R1（守卫矩阵不完备）的实证。

**踩到次数**：1（2026-07-02 体检发现；Herbst 上线以来一直靠双写硬顶）

**解法**（已实施 2026-07-03，B2）：守卫收口成 `AircraftPhysics.maneuver_overrides_speed(ac)` /
`maneuver_overrides_g(ac)` 两个谓词。注意 **Herbst ACCEL 阶段刻意不接管速度**（开 AB 交还
update_speed 自然拉回巡航）——谓词按阶段区分，不是一刀切。

**约束**：新增任何机动模块（新 EvasionModule 子类等），接管判定**只改这两个谓词**，
禁止再往 update_* 里散点加 if。Phase 1 意图仲裁器落地后此层整体退役。

---

## SEAM-016 · lod_level 七写者每帧拔河，收敛依赖引擎树序（未修，Phase 4 排期）

**症状**：`lod_level` 有 ~12 处写入 / 7 个写者：survivor_mode 每帧强制（敌机屏内=0/离屏=2、
友方一律=0）与 AI 侧按事件写（set_formation_target=1 / exit_evade=1 / disengage 等）
互相覆盖，"最后写者赢"。历史已产生需在 aircraft.gd LOD0 编队分支打补丁的 bug；
生存模式里 LOD1 非编队分支实为死代码；`_update_friendly_squad_lod` docstring 与实现
曾自相矛盾（2026-07-03 已修注释，B5）。

**根因**：LOD 无单一 owner。survivor_mode（相机视角）与 AI（行为语义）都认为自己有权决定。

**踩到次数**：1 次显性 bug + 多次注释级困惑

**解法状态**：**未修**。归属方案（mode 唯一决策者 vs Aircraft 自决）在重构计划
Phase 4 定夺，见 [docs/planning/physics-ai-control-refactor.md](../planning/physics-ai-control-refactor.md) §5。

**约束（过渡期）**：不要再新增 lod_level 写入者；需要改 LOD 语义先读
`_update_friendly_squad_lod` / `_update_offscreen_lod` 的每帧覆盖行为，明白你的写会被
下一帧盖掉。

---

## SEAM-017 · update_* / step_* 预测线镜像契约仅存在于注释，已实证漂移

**症状**：玩家预测弧线与实机航迹系统性不符。2026-07-03 物理审计实证 2 处漂移：
①基础 max_bank 的 G 口径撕裂——实飞用结构 G（`effective_max_g_instant`，默认 12G），
预测线用持续 G（9G）→ 预测弧恒偏宽 ~30%，实机总"转得比线快"（`max_bank_angle` 改用
instant G 时忘改预测侧）；②`step_speed` 只守卫 Cobra 不守卫 Herbst——B2（2026-07-03 上午）
的新守卫又只改了单侧，玩家危机赫尔贝特期间实机速度被钳近失速、预测线自由加减速。

**根因**：aircraft_physics.gd 顶部"两份实现必须人肉同步"的契约没有任何测试/断言强制
（与导弹"jammed 视为不会命中"契约失效同构）。每次改 update_* 都是一次漂移机会。

**踩到次数**：2（本次审计一次抓到两处；SEAM-012 约束段早有预警）

**解法**（2026-07-03 两处已修：`_eff_max_g_instant_st` + `cached_max_g_instant` /
`step_speed` 改用 `maneuver_overrides_speed` + 预测 g_load 加 `maneuver_overrides_g`）。
**根治**在重构计划 Phase 3：逐对提取共享纯函数（`compute_target_bank` 已是样板），
两侧变薄壳后契约自动成立。过渡期约束：**改任何 update_* 前 grep 对应 step_* 并同步**，
改完跑 `--bench=all`。

---

## SEAM-018 · "锁定进度"同时驱动发射门与转弯权限，两者阈值不一致会自锁

**耦合点**：`Aircraft._get_missile_phase()` 用 `radar_targets[target] >= lock_time` 判"已锁定"→
返回 phase 2 → `AircraftPhysics.compute_target_bank` 把坡度上限压到 **35%**（为 crank 保稳设计）。
但**能不能发射**由另一套判据决定：`AircraftWeapons._has_stable_launch_window` 要求离轴
≤ `radar_half × 0.55`（F-14 = 19.25°）。

**为什么绊倒 fix**：两个阈值分属不同模块、语义看起来无关，但共享同一个前提——
"锁定完成 ⇒ 机头已经在目标上"。该前提在慢速/横切目标上不成立。一旦锁定满而机头仍在
19.25° 门外，就形成闭环：**锁上了 → 坡度被压到 35% → 转不进发射锥 → 打不出去 →
机头继续飘 → 出锥丢锁 → 重来**。表现为玩家侧的"锁定上了却不发射导弹"，
但改发射门那一侧永远修不好，因为病根在转弯权限那一侧。

**实证**：`--bench=slow_air_pass` C 段——满锁 3.30s/3.00s 时 nose 27°，坡度仅 27.6°/1.1G
（可用 7.5G），随后离轴 27°→31°→43° 越飘越远，45s 一枪未发。

**现状（2026-07-20 已修）**：`_get_missile_phase` 增加 `_target_within_launch_cone()` 门——
锁定满但仍在发射锥外时返回 0（满转弯权限），语义 = "还在对准段"；
`is_cranking()`（发射后支援照射）不受影响，维持柔坡。

**约束**：今后若再引入"按锁定/交战阶段调机动权限"的旋钮，**必须与发射门同源判据**，
或显式验证"权限降低时飞机已经能开火"。否则同一类自锁会换个形式复现。

**踩到次数**：1（表现为长期"AI 打直升机锁上了不发射"，spec slow-air-target-pass §0 第 4 层）

## SEAM-019 · "谁是玩家机" 有 9 个缓存持有者，chokepoint 曾只覆盖 5 个

**耦合点**：`survivor_mode._ready()` 里至少 9 个子系统在 setup 时**缓存**了初始
`player_aircraft` 引用：`_spawner.player_aircraft` / `zone_manager.player_ref` /
`_map_boundary.player` / `_tactical_map._player` / `_zone_arrow._player` /
`_zone_mission._player` / `_adbs._player` / `_event_director.player`，外加
`AircraftRenderer.player_ref` / `survivor_player.aircraft` / `_camera_ctrl` 跟随目标。

`_set_player_aircraft()` 自称"操控真源单一 chokepoint"，但只重定向了后面那 3 个 + 自身 +
`selected_aircraft`。前面 8 个 setup-time 缓存**全部漏掉**。

**为什么绊倒 fix**：漏掉的引用在切控（1-4 切槽）/ 换帅（长机被击落自动接管）/ 进化换机
之后仍指向旧机。旧机后续被击落 → `queue_free()` → 持有者拿到的是**已释放实例**。
GDScript 读已 free 对象的字段常常"看起来能跑"（返回 null / 假值），所以问题会潜伏很久，
直到某处把它**当强类型参数传出去**才炸。

**实证（2026-07-20 玩家闪退）**：
`Invalid type in function 'spawn' in base 'RefCounted (CarrierStrikeGroup)'.
The Object-derived class of argument 4 (previously freed) is not a subclass of the expected argument class.`
—— arg 4 = `player: Aircraft`，来自 `survivor_spawner._spawn_boss` 传的
`player_aircraft`。切控后旧机阵亡，spawner 缓存变野指针，下一个 BOSS 生成即硬崩。

**现状（2026-07-20 已修 + 已上抗体）**：
1. `_set_player_aircraft` 补齐全部 8 个缓存持有者的重定向；
2. `_spawn_boss` 加 `is_instance_valid` 防御守卫（宁可跳过生成也不硬崩）；
3. 新增 `tools/verify_player_ref_holders.py` —— 静态扫 `survivor_mode.gd`，
   把"把 `player_aircraft` 交出去的接收方"与 chokepoint 函数体比对，漏登记即退出码 1。
   已挂进 CLAUDE.md 的 commit 前流程。

**校验器顺手抓到的第二个洞**：`AudioManager._engine_host` 同样是 setup-time 缓存且未重定向。
它有 `is_instance_valid` 守卫所以不崩，但切控后引擎声会**静默消失**——
典型的"缓存腐烂不一定表现为崩溃"，也说明人工 review 靠不住、必须上自动化。

**约束**：今后任何在 `_ready` 里 `setup(..., player_aircraft, ...)` 的新子系统，**必须**同步
在 `_set_player_aircraft` 里加一行重定向（校验器会拦）。理想解是改成子系统按需回读
`mode.player_aircraft`（像 `zone_manager._process` 已有的自愈逻辑），
彻底消灭缓存 → 排进 Phase 4 refactor；在那之前校验器是防线。

**校验器的已知边界**（别误以为它覆盖了全部）：
- 只扫 `survivor_mode.gd`。若将来别的文件也分发 `player_aircraft`，需扩 `SOURCE`。
- 局部/循环变量（`ac` / `ai` / `leader_ai`）会被识别但不判定——它们生命周期在函数内，
  chokepoint 无从登记。**若某个局部变量把引用存进了长寿对象，脚本抓不到**。
  已人工确认现存 3 处安全：`ac.set_formation_target(player_aircraft, ...)` 会被
  `ai_controller` 每 tick 从 `squad.leader` 重设覆盖，属自愈。
- 判定的是"有没有登记"，不是"登记得对不对"——写错字段名它看不出来。

**踩到次数**：1

## SEAM-020 · 已释放引用传进"带类型的 Object 形参"即硬崩，守卫写在函数体里是无效的

**耦合点**：Godot 对实参做**类型检查发生在进入函数之前**。把一个已 `queue_free()` 的对象
传进 `func take_damage(amount, attacker: Node, ...)` 这类形参，引擎直接报：

    Invalid type in function 'take_damage' in base 'Node2D (Aircraft)'.
    The Object-derived class of argument 2 (previously freed) is not a subclass of ...

**为什么绊倒 fix**：直觉是"在 `take_damage` 里加 `if is_instance_valid(attacker)`"——
**完全无效**，函数体根本没机会执行。若 API 的语义只接受活对象，必须在**调用点**净化；若 API
本来就是生命周期边界谓词、职责是把失效引用判成 `false`，则形参必须收 `Variant`，进入函数后先做
`typeof(x) == TYPE_OBJECT and is_instance_valid(x)`，再做 `is` / 字段读取。

第二个陷阱是**守卫矩阵不对称**（同 SEAM-015）：这些调用点大多**已经**写了
`is_instance_valid`，但只护住了紧邻的 `set_meta(...)` 归因行，**漏掉了下一行的
`take_damage(..., source, ...)`**。看起来"已经防过了"，实际防的是不会崩的那半边
（`set_meta` 收 Variant，不做类型检查，存野指针也不报错）。

**根因场景**：弹丸/AOE 的生命周期**长于发射者**。
子弹与导弹在飞行途中射手被击落、AOE 区域在导弹爆炸后还要存活 `AOE_DURATION` 秒——
BOSS 混战里这是常态而非边缘情况。`_pending_attacker` meta 同理：它一直留到
`_record_kill_attribution` 才清，期间攻击者随时可能阵亡。

**实证（2026-07-20 玩家 BOSS 战闪退）**：CSG + Poltergeist 中队混战，多艘舰船已沉。

**现状（2026-07-20 已修）**：新增 `CombatUnit.safe_attacker()` / `safe_unit()` 静态净化入口
（名字可 grep，注释写明"为什么不能在函数体里判"），并修掉 8 个裸传点：
`missile_manager` 直接命中 + AOE 区域、`bullet_manager` 火箭 AOE / 火箭直击 / 机炮 ×2、
`aircraft` 的 `dispatch_on_hit`、`laser_equipment`、`mother_goose_controller`、
`ai_controller._apply_position_error`。

**约束**：新增任何"武器命中 → 结算"路径时，凡是把**跨帧存下来的**单位引用
（弹丸字典的 `source`、`missile.source`、meta 里的 `_pending_attacker`、AI 的 `_current_target`）
传给带 Object 类型形参的函数，一律经 `CombatUnit.safe_attacker()` / `safe_unit()`。
归因丢失（attacker=null）只是"这次不记凶手"，远好过整局闪退。

**排查手段**：见本条 commit 里的一次性扫描脚本思路——
收集全仓 `func` 的 Object 类型形参 → 找出用长寿引用调用它们且同行无 `is_instance_valid` 的点。
**没有做成常驻校验器**：静态判断"这个引用是否可能已释放"需要跨帧生命周期分析，
误报率会高到没人看。这条靠的是 code review 时的模式识别，不是自动化。

**2026-08-03 第二次实证**：`ObjectiveContext.is_survival_threat(cand: Object)` 虽在函数体第一段写了
`is_instance_valid(cand)`，但 `_sticky_for` 把已释放的 `ai._current_target` 传入时，仍在形参类型检查阶段
报 `argument 1 (previously freed)`。`is_survival_threat` / `is_objective` 改为 `Variant` 生命周期边界，
并用 `target_sel` 的已释放 Aircraft 回归覆盖。

**2026-08-03 第三次实证**：BOSS 通关释放本体后，hunter UAV 的
`AIController.combat_zone_anchor` 仍持有已释放引用。`_apply_constraints` 先做
`combat_zone_anchor is CombatUnit` 导致 `Left operand of 'is' is a previously freed instance`。
对跨帧 Object 引用的约束同样适用于**类型判断**：必须先用 `is_instance_valid`
净化，再做 `is` / `as` / 字段读取。

**2026-08-08 第四次实证**：`SurvivorPlayer.aircraft` / `AircraftRenderer.player_ref`
在玩家终局边界可短暂保留已释放飞机；HUD 和敌方锁定线先赋给 `var ac: Aircraft`、再判有效，
于是每帧重复报 `Trying to assign invalid previously freed instance`。统一修为
`safe_aircraft_ref(value: Variant)` 边界净化，所有 `player_ref` 运行时读取走 `safe_player_ref()`，
Game Over 同步断开两个缓存；`presentation` 用真实 `free()` 后的强类型缓存覆盖回归。

**2026-08-10 第五次实证**：近炸导弹的生命周期长于发射者，命中时把已释放的
`missile.source` 传给 `_spawn_aoe(..., source: Node)`，在第 6 个实参类型检查阶段硬崩。
调用点先经 `CombatUnit.safe_attacker()` 净化，AOE 创建入口同时改收 `Variant` 并只缓存净化结果；
`weapon` bench 用真实 `free()` 的发射者直接覆盖该边界。

**踩到次数**：5

## SEAM-021 · "玩家显式命令"在移动层是铁律，在武器发射层却没有代表权

**耦合点**：`commanded_target`（玩家点名的攻击命令）被 AI **移动/交战路由**当铁律死咬
（`ai_controller._enforce_commanded_target` 绕过评分强制 ENGAGE），但**导弹发射选择**
（`aircraft_weapons._fire_multi_lock_salvo`）**完全不读它**——salvo 扫全部 `radar_targets`
自主选目标，命令目标只在最后按距离排序时"提到队首"，且必须先过 6 道过滤（LOCK / OFF_CONE /
ENVELOPE / TEAM_OVERKILL / GUN_ACTIVE / UNSTABLE_WIN）才有资格进名单。

**为什么绊倒 fix**：直觉认为"命令铁律已经保证了打命令目标"——只在移动层成立。武器层是**另一套
独立的目标选择**，两套各写各的。加任何"纪律/防浪费"过滤门（如 2026-07 的 UNSTABLE_WIN
发射窗口质量门、TEAM_OVERKILL 超杀记账）都是**全局无差别**生效，没有给"玩家显式意图"留豁免，
于是命令目标被这些门踢出候选后，salvo 转头把弹发给幸存名单里的其他目标。

**根因场景**：对地攻击的动作（压坡度 + 冲近 + 大 off-axis）恰好触满这几道门 →
命令的地面目标被踢出；而屏幕外迎头飞来的敌机（正前方 ±5°、平飞、锁满、超 min_range、高 hp）
反成唯一合法候选。"按距离排序打近的"排的是**幸存者**里最近的，玩家面前的目标根本没进名单。

**实证（2026-07-23，log combat_log_20260723_004212）**：玩家命令打地面 RADAR/SAM 期间，
`[Ultra]` 522–528s 四发 MRM 全打 11–12.6km 外的 AAA/F-104/F-4；同期 `[SALVO_SKIP]`
显示近敌 `LOCK×11` / `LOCK×15` / `UNSTABLE_WIN×6` 被过滤门筛光。用户观感=
"命令打面前目标却熟视无睹，自动发弹打屏幕外敌机"。

**现状（2026-07-23 已修，最小侵入）**：`_fire_multi_lock_salvo` 顶部加"命令收窄门"——
`commanded_target` 存活时候选池只保留它一个，打不到就这一帧不发（留弹），绝不散射。
命令目标自己被过滤门挡下 → salvo 空手，（单锁机型）落到单发路径同样只打 `combat_target`
(==commanded) 同样被挡 → 净结果=不发不散。语义边界：只作用于**显式命令**，无命令时的
RTS auto-fire 散射不变（SPREAD 分火/巡航/集合都置 `commanded_target=null`，本门天然不触发）。

**未修的同类隐患**（本条只堵了 salvo 散射，过滤门本身对命令目标仍是硬门）：
- 命令目标被 `UNSTABLE_WIN` / `TEAM_OVERKILL`(按满血 hp 记账) 挡下 → 仍是"这一帧不发"，
  近距对地攻击可能长时间发不出弹（现状=让位机炮，但玩家可能预期导弹）。
- `GROUND_STRAFE` 相位机武器竞选选 gun 时 `weapon_mode=GUN`，导弹通道整段关闭（log 里
  378–393s 连续 8 次 `WEAPON_MODE mode=1` 静默）。
- 放宽这些门对命令目标的判定 = 动 [weapon-employment-doctrine] / [rts-command] 定稿，
  按 spec-first 需先补 spec，未做。

**约束**：新增任何"武器发射选择 / 防浪费过滤"逻辑时，先问"玩家显式命令（commanded_target）
是否应豁免这道门"。武器层与移动层是两套独立的目标选择，别假设移动层的铁律会自动传导到发射层。

**踩到次数**：1

## SEAM-022 · railgun-bank-cap：`weapon_mode=MISSILE` 把电磁炮 LINE_UP 坡度砍到 35%，靠一个无关的玩家标志才绕过

**耦合点**：`bfm_intent._apply_combat_weapon` 里 railgun 竞选胜出时置 `p.weapon_mode = MISSILE`
（阶段 2 遗留的 crank 保锁写法）。`compute_target_bank` 见 `weapon_mode==MISSILE` 且非"激进档"
就把坡度上限乘 `cap_frac=0.35`（SEAM-018 同一个乘数）。于是 LINE_UP 猛拧相声明的 65° 坡度
实际只剩 **23°** → 转向率 ~1.3°/s → 机头永远够不进 ±5° 火控锥 → 充能每帧静默失败。

**为什么绊倒 fix**：改 `line_up` 的 bank_limit_deg（30→65）在 plan 快照层看完全生效，纯几何
单测也全绿——但 `cap_frac` 在 `compute_target_bank` 内部二次砍坡，plan 层完全看不到。
只有**裸物理步进闭环 sim**（驱动 planner→物理→railgun 状态机）才暴露"bank 卡 23°、tr 1.3°/s、
9.7s 打不出"。**教训**：坡度/转弯权限类改动**必须**配闭环 sim 断言，plan 字段快照会骗人
（fable 评审 2026-07-24 独立指出"3 条断言只验字段没碰闭环"）。

**唯一绕过路径**：`use_tactical_preference`（玩家机）→ `aggressive_ok=true` → `cap_frac=1.0`。
∴ **玩家电磁炮能对准纯属"恰好玩家有 preference 标志"**——而该标志语义是"玩家有战术偏好面板 +
机炮瞄准误差"，与电磁炮转弯权限毫无关系。非 preference 的电磁炮机（敌 AF-03 / 玩家僚机带
电磁炮）仍卡 35% 慢转档。

**实证（2026-07-24，闭环 sim `test_weapon_doctrine` 端到端）**：preference=false → bank 卡 23°、
15° 偏轴 8s 打不出；preference=true → bank 65°、3.2s 起充开火。

**现状（2026-07-24 未修，仅文档 + 依赖绕过）**：玩家路径已验证可用（走 preference 绕过），
故只加注释 + 本条 seam，未动 `weapon_mode=MISSILE`（改 GUN 会连带敌 AF-03 变准 + 触动
auto-fire/HUD 通道，超出"修玩家电磁炮"范围）。**根治**（若日后僚机带电磁炮成常态 / 想去掉对
preference 的隐性依赖）：railgun LINE_UP 不该复用导弹 crank 的 weapon_mode，应有独立"直射对准"
语义让 cap_frac=1.0 对所有阵营生效——属 [weapon-employment-doctrine] 定稿改动，spec-first 先补。

**约束**：新增"按武器模式/交战阶段调机动权限"的旋钮时，先查它会不会被 `cap_frac` 二次砍；
且**必须**配闭环 sim 验证，别只信 plan 快照。与 SEAM-018 同族（cap_frac 前提"该模式下机头已对准"
在慢转/横切目标上不成立）。

**踩到次数**：1（与 SEAM-018 同一乘数的第 2 种触发形式）

## SEAM-023 · planner 追踪几何与武器发射门数值耦合但互不知情 → "无声拒发"反复复发

**症状**：飞机看起来在正常执行攻击战术（锁定、绕target、保持包络），但导弹/机炮一发不出，
无任何 UI 反馈，只有 EventLogger `MSL_BLOCK` 能看出被门拒。同一类病已独立复发 **3 次**：
1. 慢速空目标（直升机）：交会点引导常驻前置偏置 → 锁攒满但机头卡在发射门外（slow-air spec 修）；
2. 慢速空目标机炮跑：交会点 vs 机炮解 10° 稳态偏差 → 机炮锥永不开门（slow-air spec 修）；
3. **地面/舰船 STANDOFF（2026-07-26，log 20260726_165536）**：crank 稳态离轴
   `radar_half×0.5` 恰在发射窗质量门（`×0.5(SARH)/0.55(f&f)`）外沿 → UNSTABLE_WIN 永拒；
   同批还撞出包络"高度差>5000m"门被 STANDOFF MID 学说高度恒触（面目标已豁免）。

**耦合点**：追踪点几何住 `bfm_intent`（crank/交会点/机炮解），发射门住
`aircraft_weapons._has_stable_launch_window`（离轴 `radar_half×0.5/0.55`）+
`aircraft_combat_tracking.is_in_missile_envelope`（距离/TAA/高度差）。两层各自演化、
无共享常量：planner 让机头停在哪里，与武器层"机头必须在哪里才肯开火"没有任何编译期/测试期约束。
**行为验收若只断言运动几何（保距/相位/收敛），武器层门永远不在环内 → bug 全绿穿过验收**。

**踩到次数**：3

**解法状态**（模式已成文，2026-07-26）：
- 引导点原则：**终端段（意图开火的相位）必须让机头稳态收敛进发射门**——静止/慢速目标直接
  纯追踪瞄目标本体（LOS 零/低旋转，离轴→0）；crank/F-Pole 这类"故意离轴"几何只允许在
  **发射后**（fpole_hold）或**明确不打算开火**的相位使用。
- 验收原则：任何攻击类战术的行为 sim **必须带"真出弹"断言**（复刻发射门序列：
  包络→锥→锁→发射窗质量+冷却），范本 `test_surface_pass.gd _launch_gate_open`。
- 未根治的残留：`_missile_engage_pos` 的空对空 crank 上限仍 = SARH 发射门（`radar_half×0.5`
  两者相等），空战靠目标机动让 LOS 摆过零点才有发射窗——对空若再出"锁着不发射"，先查这里。

**约束**：新增/修改任何"武器就绪期的追踪点"几何时，先对照发射门数值算稳态离轴；
配套 sim 必须含出弹断言，别只信运动几何全绿。

## SEAM-024 · RefCounted 事件被静态 UI 注册表强持有，场景退出不等于事件终态

**症状**：上一局已亮起的王牌中队分段血条，在新开一局后仍显示；Tab 的王牌标记也可能读到
上一局代号。正常全灭/撤离路径没有问题，只有玩家在事件进行中结束一局或直接换场景时复现。

**根因**：`GameEvent extends RefCounted`，`EventDirector` 虽是场景节点，但
`AceReinforcementEvent._active_ref` 是静态强引用。场景退出销毁 EventDirector 后，事件仍被静态字段
续命，因而不会经 EventDirector 的正常回收循环调用 `_finish()`；依赖 `_finish()` 清静态注册表的设计
在换场景路径上失效。HUD 又直接消费这张注册表，于是跨局残留。

**解法状态（2026-08-01 已修）**：事件提供 `reset_runtime_state()`，SurvivorMode 在 `_ready` 与
`_exit_tree` 两端显式清理；前者保证新局入口不信任旧状态，后者及时断开强引用。`lancer_squad`
bench 加回归断言，先构造已交战血条，再验证 reset 后数据源为空。

**约束**：任何 static 字段若强持有 `RefCounted` 的局内对象，不能把“场景节点销毁”当成其终态；
必须提供显式 reset，并在模式开局/退局两端接线。若 UI 读取该字段，测试至少覆盖一次跨局清理。

**踩到次数**：1

## SEAM-025 · 零 Token 事件复用常规选型器，空池兜底穿透退役门

**症状**：高响应等级、常规 Token 接近耗尽时，城区 CH-47 的事件护卫仍成批生成已退役
MQ-109；同一绝对兜底也可能让普通波次用 1~2 个残余 Token 填入退役杂鱼。

**根因**：ADBS 护卫虽是 `token_cost=0` 的 Adds，却直接调用读取常规剩余 Token 的
`_pick_enemy_type()`；候选为空后该函数又无条件返回 `EnemyType.UAV`，绕过注册表的
unlock/retire 门。事件计费语义与常规预算语义被一个 picker 隐式耦合。

**解法状态（2026-08-03 已修）**：注册表新增 `escort_rows(response_level)`，以无限预算只应用
解锁/退役和专用编成排除；ADBS 走 `_pick_flee_escort_type()`。常规 picker 空池返回 `-1`，调用方
跳过本轮。`spawn_pool` 同时覆盖“常规零预算不刷”与“ADBS 零预算仍选当级非 MQ-109 护卫”。

**约束**：新增 Token 豁免事件时不得复用读取 `_token_used` 的常规 picker；先明确事件自己的
计费域，再从注册表构造对应候选池。任何空池 fail-soft 都必须继续服从 unlock/retire，不能写死
某个低价敌人。

**踩到次数**：1

## SEAM-026 · `acquire_target` 只持有目标，不负责 AI 模态切换

**症状**：事件护卫收到“护航对象被攻击”的 `TS_DIRECTIVE` 后，目标字段和 HUD 交战线已经建立，
飞机却仍留在 PATROL / SQUAD_FOLLOW；下一次编队 tick 还可能清掉 Aircraft 侧目标，体感就是护卫
看见了但迟迟不转向。

**根因**：`AIController.acquire_target()` 是目标所有权唯一入口，刻意只同步 `_current_target`、
`_target_source` 与 `Aircraft.combat_target`，不替调用者决定 PATROL / ENGAGE / SQUAD_FOLLOW 模态。
正常评分、玩家命令与事件 directive 都在各自路由里补状态迁移；`Aircraft._alert_escort_guards()`
从伤害回调直接调用它时漏掉了后半段。

**解法状态（2026-08-04 已修）**：护卫受警在 `acquire_target(TS_DIRECTIVE)` 成功后同拍执行
`clear_formation()`、开启追击覆盖并 `enter_engage_state()`；ADBS Squad 另用 `leader_successors`
保证运输机换锚不会被已有战果的护卫抢位。`spawn_pool` 直接断言目标所有权、编队退出、ENGAGE
与高战果护卫下的确定性换锚。

**约束**：任何从常规 AI 路由外注入目标的调用点，都必须明确回答“只预装目标，还是立即接战”。
若是立即接战，验收不能只查 `combat_target`，必须同时断言 `_state == ENGAGE` 与编队托管已退出；
不要把模态切换塞进 `acquire_target()`，否则预装目标、编队齐射和命令恢复等调用方会被隐式改态。

**踩到次数**：1

## SEAM-027 · BOSS 软返场与世界物理边界分属不同更新链，单一所有者会失守

**症状**：飞机类 BOSS 已有 2000 px 提前返场和“越线后钳回 40 px”，实战中 WRAITH 仍整队进入
边界外黑区。普通敌机不会这样，因为全局边界纪律会硬钳；`category="boss"` 为保护专属战术而被
全局逻辑整段跳过。

**根因**：`AceSquad` 同时承担战术编排和物理不可越界两个不同强度的职责。它的返场依赖 encounter
持续 tick、有效玩家引用和 directive 所有权，且钳制发生在“已经越线”之后；任一环节暂停或晚于
Aircraft 物理移动，渲染帧就可能出界。世界外框是不变量，不能只由可暂停、可被抢写的战术链守护。

**解法状态（2026-08-04 已修）**：保留 `AceSquad` 的 2000→3500 px 软导航返场；同时把
`SurvivorSpawner._update_boundary_discipline()` 设为第二所有者，对 `category="boss"` 在距边缘
≤40 px、尚未越线时就执行物理钳制并朝内转向。硬护栏不依赖玩家引用，也不改 directive、目标或火控。

**约束**：软导航负责“飞得自然”，模式级物理护栏负责“绝不出界”。任何需要绝对成立的世界不变量
（边界、禁区、地形合法性）不得只挂在 AI/事件状态机上；全局兜底必须只修物理事实，不能顺手接管战术。

**踩到次数**：2（2026-08-01 Poltergeist；2026-08-04 Wraith）

## SEAM-028 · 单槽 Presentation 允许序列覆盖，但事件完成回调曾假定原序列必会结束

**症状**：玩家在出界补给时用 30 秒时间税跨过 BOSS 闸门，BOSS 实体与登场表现已经出现，
但事件永久停在 PRE_STAGE，既不正式接战也不显示血条。

**根因**：Presentation 的状态机明确允许 `PLAYING → PLAYING`，新 UI/演出序列会直接覆盖旧序列，
且只为最终替代者发一次 `sequence_finished(name)`。`BossEncounterEvent` 收到非 arrival 名称后却重新
挂一次性回调，等待已经被丢弃、永远不会再完成的 arrival；玩法状态因此依赖了表现序列必达。

**解法状态（2026-08-04 已修）**：导演仍按既有契约先清舞台、镜头与暂停；BOSS 回调若收到非预期
序列名，记录 warning 后 fail-open 立即进入 ENGAGED，并开启 `hud_visible`。presentation bench 新增
“UI 序列打断 arrival 后仍接战、仍亮血条”两条断言。

**约束**：任何玩法终态都不得靠“原表现序列最终一定发完成信号”成立。消费单槽导演完成信号时，
必须处理名称不匹配：能安全退化的玩法立即 fail-open；不能退化的流程须显式建队列/所有权仲裁，
不得重挂等待一个已被覆盖的序列。

**踩到次数**：1

## SEAM-029 · 基类静态类型与子类 TypedArray 交界会在运行时拒绝 erase/赋值

**症状**：激光黑客或 WhiteTea 投降触发阵营转换时，`faction_transition.gd` 每扫描一架飞机就连续
刷出 `Attempted to erase an object into a TypedArray`；同局小队清理又可能报
`Trying to assign invalid previously freed instance`。错误数量随全场飞机数和转换次数放大，最终可能闪退。

**根因**：`FactionTransition` 的参数静态类型是 `CombatUnit`，却直接传给
`Array[Aircraft].erase()`；运行时对象即使确实是 Aircraft，Godot 4.7 仍按调用点静态类型校验。
另一侧，`Array[Aircraft]` 会保留已释放对象的槽位，把 `pop_front()` 结果直接赋给
`var candidate: Aircraft` 会在 `is_instance_valid()` 有机会执行前先抛错。

**解法状态（2026-08-04 已修）**：阵营事务先验证并收窄成 `Aircraft` 再清强类型缓存；小队继任链
先用 Variant 接住、验证有效后才 cast。`faction_conversion` bench 真实调用激光 `_advance_hack()`，
并显式构造护卫/群组缓存和已释放 successor，保证两条路径先红后绿。

**约束**：跨继承层操作 TypedArray 时，先收窄到数组元素类型；从可能残留 freed object 的强类型
容器取值时，不得直接赋给强类型局部变量，必须先用 Variant + `is_instance_valid()`。技能审计的
注册/字段/消费点全绿不能替代真实 runtime consumer 测试；带转换、销毁、换阵营或编队重绑的技能，
专项 bench 必须至少执行一次完整状态跃迁。

**踩到次数**：1

## SEAM-030 · 3Hz 自动火控与 60Hz 战术回写共享射击方向，梭射会在采样间隔内回正

**症状**：炮艇模式已经在日志中选中侧后方 `+49° / +76° / 159°` 目标，但同一梭的大量子弹仍从正前方射出；侧后射击也固定从机鼻位置吐弹，看起来像在追踪其它对象。修完射向后，220856 日志又出现玩家全队 4 机、18 个 GroundUnit、炮艇/重炮均已生效，却没有任何对地 `GUN_SCAN/GUN_BURST`。

**根因**：`auto_gun_scan()` 只在 3Hz 扫描帧写 `_gun_lead_heading`，而 `_apply_tactical_plan()` 每个物理 tick 都会在无显式 `combat_target` 时把它重置为机头。`update_gun()` 的“整梭承诺”只锁存剩余弹数，没有锁存承诺对象，因此剩余弹忠实地沿被覆盖后的机头方向继续出膛。与此同时 `_fire_gun_round()` 的炮口出生点和双管横轴也始终取机体 heading。CIWS 又复用了普通机炮的可变射界，和炮艇模式组合时会从正面反导静默膨胀为 360° 反导。更上游还有三道旧纪律门：非 `use_tactical_preference` 的 AI 僚机无条件退出自动扫描；有 `combat_target` 时 planner 把扫描池锁死为该目标；编队 LOD0/1/2 又在武器主循环前提前返回，只保留编队导弹。它们对普通固定机炮合理，却让“全队独立炮塔”名存实亡。

**解法状态（2026-08-04 已修）**：自动扫描与梭射分别保存目标实例 ID；梭起始锁存承诺对象，之后每个武器 tick 重新求同一目标提前点，目标释放或失格即掐断残梭。炮艇炮口与双管基线按实际射向旋转。航空 CIWS 改用独立 5° 正面锥，并新增节流后的 `CIWS_FIRE` 日志，和普通 `GUN_BURST` 明确分流。炮艇另有显式纪律例外：所有 PLAYER 持有者（含 AI 僚机）都运行独立扫描，不锁 planner 当前目标池、不受 MISSILE 主武器模式静默，并按最近合法目标选取；编队和屏外 LOD 提前返回路径通过专用入口继续 tick 炮塔；普通机炮路径保持原纪律。

**约束**：凡是“慢频率选择 + 快频率消费”的火控状态，不得只共享一个会被其它系统覆盖的瞬时方向量；慢频率层保存对象身份，快频率层从对象事实重算派生方向。新增全向/扩锥技能时，逐项审计普通攻击、CIWS、防御火力等消费者，不得让同一个可变 GunParams 角度隐式扩散到不同武器通道。

**踩到次数**：3（2026-04-26 自动扫描 lead 冻结；2026-08-04 planner 回正与炮艇/CIWS 串线；2026-08-04 AI 僚机/战术目标纪律门吞掉全队对地炮塔）

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
