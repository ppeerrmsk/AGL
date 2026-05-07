# 2026-05-08 — Mother Goose 空中航母 BOSS（桶 A · 6 子分支串联）

## 背景

最后一桶。Mother Goose 是受 Arsenal Bird "Liberty" 灵感的 BOSS 设计——3000HP 巨型空中航母 + 12-30 UAV 蜂群 + 周期性干扰场。原本和其它一堆改动一锅塞在 main 上，按新工作流必须先拆 6 个子分支串联做。

## 6 子分支拓扑

```
* feat/boss-mother-goose-wire   (Sub 6: 接入层)
| * feat/boss-mother-goose-render (Sub 5: 9x 飞翼图标 + railgun fire_along_nose telegraph)
| | * feat/boss-mother-goose-core (Sub 4: 五件套 + BOSS .tres)
| | | * feat/boss-fear-immunity   (Sub 3: combat_unit fear_immune + ai_controller no_kamikaze)
| | | | * feat/boss-mount-target-aircraft (Sub 2: parent_ship 放宽 + damage_router meta hook)
| | | | | * feat/boss-uav-resources (Sub 1: 4 UAV 资源 + railgun charge_persistent/fire_along_nose)
| | | | | | * main
```

每条子分支独立合 main、独立可 revert。下面按 sub 顺序写。

## Sub 1: UAV 资源 + railgun 字段（最封闭）

5 个独立资源 + railgun_equipment.gd 两个新字段：
- `resources/{enemy_uav_mg_laser, enemy_uav_railgun, uav_mg_laser, uav_railgun}.tres`
- `railgun_equipment.gd` 加 `charge_persistent`（充能后失锁不取消）+ `fire_along_nose`（弹道沿机头不偏移）。配套 `_fire` miss 处理重写：旧版改 aim_pos 与 fire_along_nose 不兼容 → 新版在 dir 基底确定后加横向角度扰动。
- 顺手加 "慢速目标命中加成"：< 300km/h 时 miss_chance 线性砍 60%（凝视压迫/fear_chills 联动的设计承诺）。

## Sub 2: 基础设施层（纯重构）

为 Mother Goose（Aircraft 子类带挂点）打通基础设施。**行为不变**，所有新 if 块都是 dormant。
- `mount_target.gd` `parent_ship: NavalUnit → CombatUnit` 类型放宽
- `aircraft.gd` `_log_unit_name` 扩展（log 看到 callsign / full_name 而非 `@Node2D@xxx`）
- `aircraft.gd` 新 `take_damage_at(amount, hit_pos)` 函数 + `take_damage` / `take_bullet_damage` 加 `damage_router` meta 短路
- `aircraft.gd` `is_lock_immune` 加 `lock_immune_override` meta 优先
- `aircraft_combat_tracking.gd` surface 目标含 NavalUnit/MountTarget（让飞机用机炮舔船挂点也走低空掠过）
- `aircraft_physics.gd` 注释（Mother Goose 干扰场减速走标准 SLOW 通道）

## Sub 3: fear_immune + no_kamikaze meta 锚点

- `combat_unit.gd:apply_status` 加 `fear_immune` meta 检查（无飞行员单位拒绝 FEAR）
- `status_effects.gd` 注释呼应
- `ai_controller.gd` 自爆指派加 `no_kamikaze` meta 例外（专职近距护卫永不出列）

也是 dormant，等 sub 4 spawn UAV 时设 meta 才激活。

## Sub 4: 五件套核心实现

5 个新 .gd（共 1126 行）+ 1 个新 .tres：
- `mother_goose_boss.gd` (358) — BossEncounter 子类，3000HP + 蜂群 + 干扰场骨架，patrol ring 飞行
- `mother_goose_controller.gd` (325) — 战斗逻辑控制器（每帧 tick + jam field + draw shield）
- `mother_goose_jam_shield.gd` (122) — 状态机：COOLDOWN 40s → WARNING 4s → EXPANDING 8s → SUSTAIN 8s
- `mother_goose_shield_overlay.gd` (40) — 视觉层
- `mother_goose_uav_swarm.gd` (281) — 蜂群管理（起 12 / 上限 30 / 每 12s 补 2）
- `enemy_mother_goose.tres` — BOSS AircraftParams（silhouette=mother_goose）

## Sub 5: 渲染层

`aircraft_renderer.gd`：
- silhouette == "mother_goose" 分支调 `draw_mother_goose_icon`（~110 行）
- 9x 战斗机大小的飞翼 + 6 发动机舱 + 中部船桥 + 8 螺旋桨槽位 + 2 VLS 标记 + 翼面参考线
- prop_xs / ry=0.42 与 `mother_goose_boss.gd:PROP_OFFSETS_PX` 严格对齐（v2 接 MountTarget 后可锁定）
- `draw_railgun_telegraph` 加 fire_along_nose 分支（弹道沿机头延长线显示）

## Sub 6: 接入层

最后一段把 sub 4 的资源接入游戏 spawn 流程：
- `boss_registry.gd` 注册 MOTHER_GOOSE id
- `boss_encounter_event.gd` MotherGooseBoss 分支
- `boss_debug_select.gd` 加 BOSS_DEBUG_GOOSE 调试条目
- `survivor_spawner.gd:_spawn_boss` 加 MotherGooseBoss 分支
- i18n CSV + 三语 .translation 同步
- `script-index.md` 4 行 mother_goose_* 索引

## 工作流复盘

- 桶 A 是这次"工作流重构"任务里最大的一桶，6 子分支按依赖严格串联做下来，每一步都可独立合 main 不破坏游戏：
  - Sub 1 / 3 是 dormant 资源 + meta 锚点
  - Sub 2 是行为不变的纯重构
  - Sub 4 是新文件不影响现有 spawn 流程
  - Sub 5 silhouette 分支只对 mother_goose 生效
  - Sub 6 才真正让 BOSS 在调试菜单可选
- 拆得这么细的好处：每条 commit 都能在 30 秒内看懂在做什么；任意一段炸了用 `git revert -m 1 <merge-sha>` 干净回滚；不需要等所有 6 段都通过才合 main。
- 实操中用了"从 stash 拍单文件 + Edit 工具反向把不属于该 sub 的 hunks 还原"的笨办法 —— `git add -p` 在自动化里跑不动，纯 Edit 反而精确。这是 plan 里提到的"按 hunk 拆"实战路径，跑下来证明 OK。
- Sub 5 一度遇到"stash 版本是早于桶 C 凝视压迫 carry-over"的时间问题，必须手工把凝视压迫 cone 加回来才能 commit 干净 diff。**当 carry-over 已合 main 时，从 stash 拍同一个文件需要先把 carry-over 的部分手工回填到 working tree**。这个坑写进 docs/changelogs/2026-05-08-feat-batch-fhb.md 的复盘段，桶 A 也踩过两次。

## 此次工作流总账

从 2026-05-08 开始按 `~/.claude/plans/clever-spinning-hummingbird.md` 工作流重构计划，把 main 上散修的 23 modified + 10 untracked 文件拆成 14 个独立分支（3 fix + 6 桶 + 桶 A 6 子分支），全部 `--no-ff` 合 main，写了 5 份 changelog（bug fix 批次 / aura CD / 桶 F-H-B 批次 / Mother Goose / 本份）。stash 完整保留作存档。

工作流跑通了。

## TODO 后续

- `docs/architecture/known-seams.md` 还没建。攒了 4 个 SEAM：
  - SEAM-NAVAL-LABEL-ZOOM（脏驱动 redraw 漏点）
  - SEAM-FEAR-MULTI-INLET（FEAR 入口分散到 4 处）
  - SEAM-AURA-VFX-NO-CD（累积式光环 VFX 脉冲叠加）
  - SEAM-EFFECTIVE-ACCESSOR（机动性 buff 必须走 effective_*() accessor）
- stash@{0} 可以 drop 了，但留作存档无害
- plan 文件 `~/.claude/plans/*.md` 一堆，可以归档到 `~/.claude/plans/archived/` 或保留
