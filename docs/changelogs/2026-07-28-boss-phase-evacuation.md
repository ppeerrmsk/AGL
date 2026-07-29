# 2026-07-28 · BOSS 阶段闸门统一 + 全场撤离

> 问题（玩家报告）：BOSS 阶段敌机仍在不停刷新，城区直升机事件也照常触发。
> 期望：进 BOSS 阶段后所有飞机撤离战场；战区里的船保留。

规格：[survivor-loop §3.1](../specs/systems/survivor-loop.md)（新增段）+ §9 验收两条。

## 1. 根因

BOSS 阶段有**两套语义不同的闸门**，各子系统各自读其中一套：

| 判定 | 语义 | 何时为真 |
|---|---|---|
| `ZoneData.is_boss_phase()` | `selected_id == "BOSS"` | 玩家在战术地图上**点了 BOSS 圈**之后 |
| `survivor_mode._is_in_boss_phase()` | `boss_unlocked ∪ selected==BOSS ∪ 已 spawn` | BOSS **解锁**那一刻（600s 到点）|

刷怪总管 / ADBS 随机事件 / 战区任务全都读的是前者。而 600s 到点后
`_check_warzone_phase_timeout()` 会把 `selected_id` 清空（关掉所有战区），BOSS 圈只是变成
AVAILABLE —— 于是从"BOSS 解锁 + BossEncounterEvent 进 PRE_STAGE 接近"到"玩家自己点选 BOSS 圈"
之间的整段时间里，旅途刷怪、猎手指派、城区直升机事件**全部照常运转**。

## 2. 改动

**闸门收敛到唯一真源**：`survivor_mode.is_boss_phase()`（public，包 `_is_in_boss_phase()`）。

| 文件 | 改动 |
|---|---|
| `survivor_mode.gd` | 新增 public `is_boss_phase()`；出界补给禁用闸改用 `_is_in_boss_phase()`（原来只在玩家选中 BOSS 圈后才禁，PRE_STAGE 段可无限贴边回血——与 spec §6 的描述本就不符）|
| `survivor_spawner.gd` | `_is_boss_phase()` 改问 mode（缺方法回落旧判定）→ 刷怪 / 猎手 / Sentinel 看门狗 / 开局驻防在**解锁即**停摆 |
| `survivor/adbs_manager.gd` | 城区直升机等随机奖励事件的闸门同上 |
| `zone_mission.gd` | 闸门同上；BOSS 阶段不再自己 despawn 战区单位（旧行为会把**战区舰船**也一起偷偷 free）；删 `_despawn_zone_units_offscreen` / `_boss_despawn_timer` / `BOSS_DESPAWN_INTERVAL` |
| `events/awacs_support_event.gd` | BOSS 解锁 → 提前转撤离（与王牌支援中队 / 宿敌 Orion 同契约，那两个原本就已实现）|
| `survivor_spawner.gd` | `_update_boss_phase_purge` 从"只清画面外、画面内的留着"改为**全场撤离**（下详）|
| `scripts/tests/test_boss_phase.gd` | 新增无头单测 18 断言，bench key `boss_phase` |

### 全场撤离（`_update_boss_phase_purge`，1 Hz）

- 画面外 → 立即静默 free（标 `xp_granted`，不算击杀）
- 画面内 → `_begin_boss_evacuation()`：清 AI 目标（TS_BOSS）+ 回 PATROL + 航线改最近出界点 +
  开加力，**物理飞出去**。铁则不变：不在玩家画面里瞬消。被追打照样还手（不做无敌逃兵），
  撤离中豁免边界纪律（`boss_evac` meta），否则会被"往图心拽"的纪律逻辑拉回来
- 豁免：`boss*` 前缀（BOSS 本体 / Goose 蜂群 / CSG 舰载机）、`ace_support` / `ace_nemesis`
  （事件层自管撤离）、`parent_carrier`（甲板停机 = 保留舰船的一部分）
- **舰船 / 地面单位一概不动**：撤离只针对飞机，战区里的船、SAM、AA 原样留在场上

## 3. 验证

- `--bench=boss_phase` 18/18 绿（闸门 2 / 画面内撤离 6 / 画面外释放 2 / 豁免 6 / 舰船地面 2）
- `--bench=all` 回归门 **45 项全绿**
- 差 playtest：确认 PRE_STAGE 段场面确实清空、撤离机不会在玩家眼前打转

## 4. 未做（留给 playtest 后判断）

- 撤离机被玩家追杀时会回头应战 → 是否要给个"撤离中不还手/不给 XP"的更硬语义，
  暂按现有 withdraw 契约（还手）走
- adds（Tu-160/AH-64/CH-47 编队）与普通残余敌机同等对待，一起撤离
