# 2026-07-29 · BOSS 阶段不产出（随行无人机不计价 + CSG 机库上限）

> 问题（用户）：mother goose 阶段的 UAV 不该给经验；F/A-18 刷 8 架就是上限、也不给经验。
> **总意图：阻止"BOSS 阶段无限刷周围小怪继续运营"的玩法。**

规格：[survivor-loop §3.2](../specs/systems/survivor-loop.md)「BOSS 阶段不产出」（全局裁决）
+ [bosses/mother-goose §2.7](../specs/bosses/mother-goose.md)（"击杀计价"行 + 理由段）+ 两处 §5 验收。

## 1. 病因

蜂群 UAV 打的是 `enemy_type="uav"` → `_detect_kills` 按普通 MQ-109 计价：
`25 + level×8`，Lv20 一架 **185 XP**（再乘 xp_mult / sig / 机体乘区）。
而母舰**每 12s 补 2 架、上限 30、只有母舰死才停** —— BOSS 战等于一台经验永动机。
同一条结算路径上还挂着两个"按击杀发的进度奖励"：生涯档案空中击坠（图鉴 + `uav_hunter`
成就）与对头击杀的**永久 +max_hp**，同样被无限刷。

## 2. 改动

新增通用开关 `no_kill_reward` meta —— **"无限补充/BOSS 自带单位不计价"**：

| 项 | 打了 `no_kill_reward` 后 |
|---|---|
| 击杀 XP | 0（连带不弹 +N 经验飘字）|
| 生涯档案 `record_air_kill`（图鉴 + 成就）| 不入档 |
| 对头击杀永久 +max_hp | 不给 |
| `kill_count`（HUD 击杀数）| **照常 +1** |
| 击杀回血 / 侩子手连击 | **照常触发** |

分界线：**进度/成长奖励**跟着"这单位是不是有限的"走；**局内战斗资源**是玩家用 build
换来的，蜂群本来就该是它的燃料，不动。

打标处：`mother_goose_uav_swarm._spawn_uav`（蜂群）+ `mother_goose_boss._make_mqx`（MQ-X 精英对）
+ `carrier_strike_group._launch_fa18`（CSG 舰载机）。消费点只有 `survivor_spawner._detect_kills` 一处。
Wraith 中队 / Poltergeist **不打标** —— 它们是有限的 BOSS 本体编成，就是通关奖励本身。

## 3. CSG 机库上限（同批）

`carrier_strike_group.gd`：新增 `FA18_TOTAL_CAP = 8` + `_fa18_launched_total` 累计计数。

- **累计**而非同场上限：击落**不退还**名额，弹完机库就空了（"打一架补一架"正是运营路子）
- 开局 `engage()` 的 2 架也走同一计数（守卫点唯一：`_launch_fa18` 开头）
- 定期弹射 tick 到上限后静默停摆；EventLogger 输出改成 `%d/%d launched`

## 4. 验证

- `--bench=boss_phase` 26/26 绿：F 组 5 断言（蜂群 XP=0 / 无永久 +max_hp / 仍计击杀数
  + **对照组**普通 MQ-109 照常 185 XP、照常 +max_hp）、G 组 3 断言（cap=8 / 上限后不产机 /
  定期 tick 静默停摆）
- `--bench=all` 回归门 45 项全绿
- 差 playtest：确认 BOSS 战不再"边打小怪边升级"

## 5. 结算：BOSS 阶段还剩哪些 XP 来源

配合 0728 的闸门修复（解锁即停刷 + 全场撤离），现在 BOSS 阶段的产出只剩：

| 来源 | 是否有限 |
|---|---|
| BOSS 本体编成（Wraith 4 架 / Poltergeist 4 架 / Goose 本体）| 有限，就是通关奖励 |
| 战区残留的地面单位 / 舰船 | 有限（战区任务已停摆，不再补刷）|
| 撤离途中被玩家追杀的残余敌机 | 有限，且正在离场 |

**已无任何无限产出源**。若 playtest 仍嫌"打残留地面刷等级"碍事，下一步可以考虑
BOSS 阶段直接冻结升级选卡（不是冻结 XP）——那是更大的设计动作，待裁决。

## 6. 未做

- 击杀回血 / 侩子手连击仍吃 BOSS 随行单位（见 §2 分界线）。若 playtest 发现靠蜂群
  无限回血站桩，再把这两项并进同一个开关
