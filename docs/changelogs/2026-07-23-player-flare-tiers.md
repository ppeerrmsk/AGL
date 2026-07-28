# 2026-07-23 — 玩家热诱弹分档 + 敌我解耦

> spec：[player-aircraft-power-curve §2.6](../specs/systems/player-aircraft-power-curve.md)（数值权威源）
> 起因：用户实机发现"有的玩家机体甚至有 32 发热诱弹"。

## 诊断

不是个别机型的问题 —— **41 架玩家机里 38 架都是 30 发**，而且拿的是**敌机口味的热诱弹**。

41 份 `resources/player/player_*.tres` **无一例外**引用共享的 `default_flare.tres`：

| 字段 | default_flare（敌用） | 玩家已调优的版本（仅 3 机在用） |
|---|---|---|
| max_flares | **30**（= `FlareParams` 引擎默认值，从没人改过） | 2 |
| burst_count | 2 | 1 |
| base_jam_chance | 0.55 | 0.90 |
| nervousness | 0.5（慌张型，一被锁就投） | 0.0（冷静型） |

只有 F-15 / F-16 / F-35 三架靠 `flare_override` 指到 `playable_f16_flare.tres`（2 发）。
**32 = 30 基数 + 2**，来自 `flare_shield`（战区奖励 `bonus_flares: 2`）或策士里程碑 2 点档（`flare_count +2`）；
再叠胆大妄为（+6）可到 38。且 32 份档案 `enable_flare_reload = true`（12s 装填），30 发实际近乎无限。

**佐证这是遗漏而非设计**：① F-15 有 2 发、F-14 有 30 发，两架都是 T1 起手机；② F-14 长机 30 发、
其僚机（`playable_f14_wingman.tres` → `f14_flare.tres`）2 发，同一架飞机内部差 15 倍；③ 全局 flare 经济在
1~4 量级（王牌中队 4="1 枚 1 条命"、支援中队 2、F-47 BOSS 2、UAV 1、普通敌机被 spawner 压到 1），只有玩家是 30。

**根因**：扩谱到 41 机时，`player_*.tres` 按 power-curve 矩阵批量生成，矩阵管 HP/速度/G/雷达，
不管武器资源引用 → flare 槽全填了共享库默认值，而共享库的默认值是按敌机调的。
spec §3.4 原本允许"武器资源作共享只读库引用"，正是这条口子。

## 落地

1. **新建玩家专属族** `resources/player/flare_t1.tres` ~ `flare_t5.tres`：
   `max_flares` 按 tier = **2 / 3 / 4 / 5 / 6**（分档唯一变量），
   全族统一玩家侧特性 `burst_count=1` / `jam=0.90` / `nervousness=0.0` / `reload=12s`。
2. **41 份基参按进化树 tier 重指向**（T1×4 / T2×15 / T3×8 / T4×6 / T5×8）。
3. **摘除 3 处 `flare_override`**（F-15/F-16/F-35）——否则会盖掉分档（F-35 是 T3，本该 4 发却被覆写成 2）。
   同时删掉失效的 `ext_resource` 声明并修正 `load_steps`。
4. **`default_flare.tres` 一字未动**，从此只服务敌机；玩家机不得再引用（bench 断言守着）。

## 换机继承（用户明确要求）

技能加成必须叠在**新机自身基数**之上。查实三处加成源（`flare_shield +2` / 里程碑 `flare_count +2`（10 点预留档再 +1）/
`manual_dodge +6`）本就 `max_flares` 与 `flares_remaining` **同步递增**，换机链路
（`evolve()` 重置为新机基数 → `_replay_player_upgrades` 重挂 → `reapply_all_milestones`）结果正确。
分档前 41 机同为 30 发时这条不可观测，分档后成为可见契约 → **加断言锁死**，防后人改动打破。

## 验收

`--bench=player_params` 27 断言（新增 9 条）：tier 分档表 41 机全覆盖 / 全族特性统一 / 敌我解耦
（玩家机不引用 default_flare + default_flare 未被改动）/ 换机继承四条（T1+2=4 → 换 T3 → 4+2=6，max 与 remaining 同步）。
`--bench=all` 回归门 **34 项 PASS**。

## 追加：共享武器资源污染（同日修复，spec §2.7）

上面提到"机炮同病"后，用户追问"**改玩家机炮的技能也会对敌人生效吗？这是不能允许的**"。
实测结论：**会 —— 而且是真 bug，已修**。

**机制**：`default_gun.tres` 被 41 玩家机与 12 敌机同时引用。玩家机炮升级（`gun_damage` 等）直改
`params.gun` 字段；只要该 params 的 `gun` 仍指向磁盘资源实例，升级就写进了共享 `.tres`。

**引擎事实（实测，本版本）**：`Resource.duplicate(true)` **不深拷子资源**——
`base_params.duplicate(true)` 之后 `params.gun` 仍是共享实例。项目里靠显式
`SurvivorPlayableSetup.deep_dup_weapons()` 隔离，但它只在 3 条出生路径被调用，
**`EvolutionSystem.evolve()` 漏了** → 玩家一旦换机，之后的机炮升级全部污染共享资源。
实测 `default_gun.bullet_damage` 被一次 `gun_damage` 升级从 **8.00 改成 10.40**，
且 `load()` 缓存不重置 → **污染跨局残留**（下一局敌机开局就带着上局玩家的机炮加成）。

**修复**：`evolve()` 在 `duplicate(true)` 后补 `deep_dup_weapons(ac.params)`，与出生路径同契约。
敌机侧本就有等价手工深拷（spawner 逐字段 duplicate），不受影响。

**回归守卫**（bench `player_params` 新增 7 断言）：两条路径的隔离断言 + 端到端污染断言
（应用 `gun_damage` 后共享 `default_gun.bullet_damage` 必须不变）+ 源码断言（防有人把 evolve 里
那行深拷当"冗余"删掉）+ 一条"前提"断言（记录 `duplicate(true)` 单独不够用这一引擎事实）。

**剩余的（设计期耦合，未处理）**：33 架玩家机的机炮**基数**仍等于敌机默认值 —— 为调敌机而编辑
`default_gun.tres` 仍会改到玩家。这不是运行时污染，处理方式同 §2.6（开 `player/gun_t<1-5>.tres`），
但机炮基数直接冲击手感，应先 playtest 立基线，已记 spec §7 Backlog。

## 另一处顺带炸出的 bug（未处理，待拍板）

隔离测试跑 `gun_accuracy` 时抛 `Invalid access to property 'lifetime' on GunParams`：
720 批"枪械精度"的第二段效果（spec skills-720-rework §3.3 明列的"子弹寿命字段"）写了
`p.gun.lifetime *= (1.0 + lifetime_bonus)`，**但 `GunParams` 从未加过 `lifetime` 字段** —— 
该效果从未生效，且每次拿这条技能都抛错。子弹寿命现在硬编码在 `bullet_manager`（2.0s）。
修法二选一：给 `GunParams` 加 `lifetime`（默认 2.0）+ bullet_manager 读它（技能按设计生效，是一次平衡改动），
或删掉那两行并同步 i18n 文案。已记 spec §7，待用户拍板。

另注：`resources/playable_x02_base.tres` / `playable_f14_base.tres` 是扩谱后的孤儿文件（无任何引用），
仍指着 `default_flare`，不影响运行，清理时可一并删除。

## 余项

- playtest：2~6 发 + 12s 装填的手感（T1 的 2 发是既有调优锚点，其余档位是按 tier 线性外推的初值）
- 是否给电战线（策士）机型再 +1 基数 —— **刻意没做**（单杠杆；电战机已通过策士里程碑与签名技拿到 flare 向收益）
