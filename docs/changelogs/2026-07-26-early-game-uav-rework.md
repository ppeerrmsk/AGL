# 2026-07-26 — 前期敌情与 UAV 更名改造（MQ-109 / MQ-110 / F-4E / Sentinel 降级）

> 用户四件套指令。设计权威源：
> [specs/systems/early-game-uav-rework](../specs/systems/early-game-uav-rework.md) ·
> [specs/enemies/f-4e](../specs/enemies/f-4e.md)。本文只记"当时做了什么"。

## 1. UAV → MQ-109 更名（显示层）

- `enemy_uav.tres` display_name `UAV` → `MQ-109`；呼号 `UAV-XX` → `MQ109-XX`，
  顺手把 Sentinel 呼号 `UAV_COMMANDER-XX` → `SENTINEL-XX`（`_create_enemy` 呼号分支）。
- i18n `TACTICAL_TIP_SENTINEL` 三语把"UAV"改"MQ-109"。
- **内部标识全部不动**：EnemyType.UAV/UCAV / type_tag `"uav"`/`"ucav"` / 文件名
  （避免 meta 比对与存档回归）。
- 约定：用户此后说"机炮 UAV"即指 MQ-109；导弹版 = MQ-110（见 §2）。

## 2. ~~UCAV 退役~~ → 同日 v2 订正：UCAV 更名 MQ-110，不退役

- 用户订正："UCAV 没必要退役，它就是导弹版的 MQ-109，跟 F-4E 不冲突"。
- 显示名 `UCAV` → **MQ-110**（enemy_uav_missile.tres），呼号 `UCAV-XX` → `MQ110-XX`。
- 刷新行为**全部恢复改造前**：`_pick_enemy_type` 前期兜底层 MQ-109/MQ-110 50/50、
  `ZONE_ENEMY_TABLE` MQ-110 行恢复（unlock 1/peak 2/retire 6/weight 1.4，F-4E 行另加并存）、
  bench 压测编组 MQ-110 与 F-4E 条目并存、debug 标签"MQ-110 导弹无人机"。
- 生态位划分：MQ-110 = 无人机导弹杂鱼 / F-4E = **有人机**导弹杂鱼（第一种有人敌机）。

## 3. elite 战区任务移除 + Sentinel 降级

- `zone_data.gd`：MISSION_TYPE_BASE_WEIGHTS ★/★★ 删 elite 项；E 战区
  `restricted_mission_types` `["naval","elite"]` → `["naval","squadron"]`。
- `zone_mission.gd`：删 `_spawn_elite_target` 与 elite 分支；新增
  `_spawn_sentinel_garrison`（25% 概率 / Sentinel + 6-10 MQ-109 / **驻守非 TGT** /
  绕驻守环盘旋 / 出现时驻守预算 ×0.5 / 场上唯一性检查）。
- UI/文案：survivor_mode 任务开始横幅、tactical_map 悬停描述、F6 面板选项均删 elite；
  i18n 删 `ZONE_MISSION_ELITE` / `ZONE_MISSION_STARTED_ELITE_FMT` 两键
  （⚠ `.translation` 编译文件待下次 Godot 编辑器 import 时自动刷新）。
- 随机刷新概率补偿：`COMMANDER_CHANCE_BASE` 0.04→0.06 / `COMMANDER_CHANCE_MAX` 0.08→0.12。

## 4. 新增 F-4E（EnemyType 23）

按 enemy-index 13 步清单落地：`enemy_f4e.tres`（HP 45 / 1700 km/h / 雷达 4200m /
**无机炮、无热诱弹**只导弹——同日 v3 订正：初始敌机不设对抗，玩家导弹必中）、
F4E_* 常量（unlock 1 / retire 6 / chance 0.40 / single 0.35）、Token 2 / cap ∞ /
tier offset −1、XP 32、`_create_enemy` 全 match、AI 低技袍分支、
radio 白名单 `f4e`（有人机开口）、debug 面板标签。
单机 35% 是"杂鱼一律成建制"的显式例外（用户指令）。

## 5. 回归

- `--bench=all` 回归门 **38 项全 PASS**。
- `test_map_expansion`：本批相关项全绿（parse 冒烟 13 项 / 战区几何 / 奖励去重）。
  ⚠ **既有腐烂（非本批引入）**：5 项机场战区几何 FAIL（B/D/F/G↔✈ 缘距 <2000、
  AF_CHOFU 离边 136px）——机场解放战区批次加入固定机场坐标后从未过这套约束，待单独处理。
- `verify_doc_anchors.py` / `verify_player_ref_holders.py`（见 commit 前检查）。

## 6. 待办（playtest）

- F-4E 出现率/导弹威胁/单机比例手感。
- SENTINEL_GARRISON_CHANCE=0.25 与 COMMANDER 概率上调的手感。
- E 战区 naval/squadron 轮换观感。
