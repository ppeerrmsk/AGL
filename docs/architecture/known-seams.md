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

## SEAM-010 · 小队横切行为分散在 AI 状态 / survivor `_process` 顺序里，易漏某一处

**症状**（2026-05 squad-cohesion 期间连环踩）：
- 给交战僚机加了"防游走 leash"（`_process_engage`），但**躲弹（EVADE）没 leash** → 僚机被地面 SAM
  反复打、一路 max+AB 躲到 7km 脱队，"守护后方"名存实亡。leash 只覆盖了一个状态。
- 长机被击坠**没接管、直接 GameOver**：`survivor_mode._process` 的死亡检查（→`_on_player_died`）
  排在 spawner 周期 squad cleanup（晋升新长机 + leader_changed 接管）**之前**且节流 → 当帧先 GameOver。

**根因**：小队的**横切关注点**（containment/leash、长机阵亡接管、凝聚模式行为）天然要作用于
**多个 AI 状态**（PATROL / ENGAGE / EVADE_MISSILE / SQUAD_FOLLOW）和 **survivor `_process` 的多个阶段**，
但实现是按"单个状态 / 单个 _process 位置"散点加的 → 加在一处就以为齐了，漏掉另一状态/另一阶段时静默失效。

**踩到次数**：2（EVADE 漏 leash + 接管 race，同根）

**解法**（2026-05-31）：
- leash 抽成 `AIController.effective_squad_leash()`，在 `_process_engage` **和** `MissileEvasion.process_evade`
  **两处**都查（覆盖 ENGAGE + EVADE）。守后模式用更紧的 `REAR_GUARD_LEASH_DIST`、打地面时放宽。
- 长机阵亡：`_process` 死亡检查改为**先 `_try_takeover_after_leader_down()`**（立即 `_squad.cleanup()`
  同步晋升 + leader_changed 接管），全队覆灭才 `_on_player_died()` —— 不依赖 spawner 周期 cleanup 的时序。

**约束**：以后给小队加任何"无论僚机在干什么都该生效"的行为（新 containment / 新接管 / 新模式），
先列出它要覆盖的**所有 AI 状态**和 survivor `_process` 里相关阶段的**顺序**，逐一接上，别只加在 ENGAGE。

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
`combat_bank_aggression`(→kp 缩放) 透传。验证：`godot --headless --path . -- --bench=turn_physics`
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
