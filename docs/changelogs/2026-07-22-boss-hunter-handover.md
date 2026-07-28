# 交接工作日志 · 2026-07-22 · BOSS 猎手化 + Wraith 三阶段

> 本文回答"**进行到哪里了 / 下一个人从哪接手**"。
> "改了什么、为什么这么改"在同批 changelog：[2026-07-22-boss-hunter-doctrine.md](2026-07-22-boss-hunter-doctrine.md)。
> 数值与行为的**权威源**在三份 spec，不在本文。

---

## 一句话状态

**代码全部落地并通过全量回归门；三份 spec 的 §5 验收一条都没做（需要实机 playtest）。**
可以直接接着 playtest，也可以直接提交 —— 没有半成品状态挂在树上。

---

## 起因

playtest log `logs/combat_log_20260722_005100.txt`，用户报告两点：

1. "Boss 像开进了场没有来找玩家，他没有把玩家队当目标"
2. "他在一轮骑射中就被歼灭了半数，完全没有要躲的意思，看上去行动很迟缓"

诊断出**三条独立根因**（不是一个 bug）：BOSS 设计上就是"飞到圈里等" / 接战判定只认几何距离不认挨打 /
热诱弹命数从未实装（承诺 4 条命，实际 1 条）。用户随后定档"**取消'去圈里等'的概念，
所有 BOSS 的王牌飞机都主动来追玩家**"，并要求推进 Wraith spec 落地。

---

## 完成度

### spec（三份，全部 `status: in-progress`）

| spec | 阶段完成度 | 剩余 |
|---|---|---|
| [systems/boss-hunter-doctrine](../specs/systems/boss-hunter-doctrine.md)（**本轮新建**） | 阶段 1~4 全打勾 | §5 playtest |
| [bosses/wraith-squadron](../specs/bosses/wraith-squadron.md) | 阶段 1 / 2 / 3 全打勾 | §5 playtest + 命中率实测 |
| [systems/ace-squadron-tier](../specs/systems/ace-squadron-tier.md) | 阶段 3 打勾 | 阶段 4（`ace_gun.tres` 火力对齐）+ §5 |

> ⚠ 三份 spec 都**没有**升到 `done` —— 按仓库工作流，`done` 要求 §5 验收跑完。

### 代码

**新增文件**

| 文件 | 作用 |
|---|---|
| `scripts/survivor/wraith_tactics.gd` | WRAITH 队级战术状态机（PERCH/BRACKET/PRESS/RESET + 退化检测），**Wraith 专属窄井** |
| `scripts/tests/test_boss_hunter.gd` | 97 断言，bench key `boss_hunter` |
| `resources/ace_flare.tres` | 王牌专属热诱弹（4 命 × 每次 1 枚） |
| `docs/specs/systems/boss-hunter-doctrine.md` | 新 spec |

**修改文件**（按关注点，不按行数 —— 见下方"⚠ 并行会话"）

| 文件 | 我改了什么 |
|---|---|
| `scripts/events/ai_directive.gd` | 新增第 7 个 verb `PURSUE_UNIT` + `pursue()` 工厂 |
| `scripts/ai_controller.gd` | `_directive_pursue_unit_step` 执行分支；`is_boss_attacker()` 兜底改读真角色 meta；`_process_directive` 签名加 delta |
| `scripts/events/boss_encounter_event.gd` | INBOUND 相猎手指令、四条接战触发器、猎手出生点、BOSS 圈质心同步、玩家引用保鲜 |
| `scripts/survivor/boss_encounter.gd` | 新增 `set_player_ref()` 基类契约 |
| `scripts/survivor/ace_squad.gd` | 删 `ANCHOR_HOLD` 整个状态 + 两个 leash 常量；`AceRole` 角色体系；`_apply_role`；三个 `_tactics_*` 空钩子；远端进场机头改朝玩家 |
| `scripts/survivor/f47_ace_squad.gd` | 持有 `WraithTactics` 并转发三个钩子 |
| `scripts/survivor/carrier_strike_group.gd` | F/A-18 弹射即挂玩家目标；`set_player_ref`；删私有 BOSS 圈同步（上提到事件层） |
| `scripts/survivor/mother_goose_boss.gd` | 巡逻环圆心改跟随玩家（2s 重算）；`set_player_ref` |
| `scripts/survivor/mother_goose_controller.gd`、`scripts/ai/swarm/swarm_director.gd` | 玩家引用重定向链下游 |
| `scripts/ai/tactical/situation.gd` | 包围轴读取门给 `tier == ace` 开窄口 |
| `scripts/ai/tactical/engagement_speed_governor.gd` | `apply_with_lag()` 减速迟滞 |
| `scripts/aircraft.gd` | 新字段 `gun_aim_error_enabled` / `_ace_decel_lag_*`；治理接线改 `apply_with_lag` |
| `scripts/aircraft/aircraft_weapons.gd` | 两处瞄准误差门 `use_tactical_preference` → `gun_aim_error_enabled` |
| `scripts/aircraft/aircraft_flares.gd` | 王牌 `jam_chance = 1.00` 分支 |
| `scripts/survivor/ace_tier.gd` | `mark()` 顺带开误差通路 + 写 `pilot_aim_skill = 0.85` |
| `scripts/survivor/survivor_spawner.gd` | 王牌 `fail_chance` / `head_on_fail_reduction` 归零 |
| `scripts/survivor/survivor_hud.gd` | 角色标签改读真 meta（仍只显示行为 CLOSE/STRIKE，不暴露 KNIGHT/SNIPER 代号） |
| `scripts/survivor/survivor_mode.gd` | 玩家侧补 `gun_aim_error_enabled = true`（1 行） |
| `scripts/bench/bench_runner.gd` | 注册 `boss_hunter` |
| `resources/enemy_f47.tres`、`resources/enemy_f14_poltergeist.tres` | flare 资源改指向 `ace_flare.tres` |

**文档**：`_INDEX.md` 加 1 行改 1 行、`script-index.md` / `code-index.md` / `enemy-index.md` 同步、
`event-system.md` verb 表 6→7、`known-seams.md` SEAM-009 锚点、changelog 一份。

---

## 验证状态（全部为本轮实跑结果）

| 检查 | 结果 |
|---|---|
| `--bench=boss_hunter` | **97 通过 / 0 失败** |
| `--bench=all`（回归门） | **34 项 PASS / 0 失败** |
| `python tools/verify_doc_anchors.py` | **全部锚点与代码一致 ✓** |
| `python tools/verify_player_ref_holders.py` | **全部已登记 ✓** |
| Sentinel + Lv5+ 压测 | ❌ **未跑** |
| 三份 spec §5 验收 | ❌ **一条未做** |

跑法：
```
"<Godot4.6>" --headless --path . -- --bench=boss_hunter
"<Godot4.6>" --headless --path . -- --bench=all
python tools/verify_doc_anchors.py && python tools/verify_player_ref_holders.py
```
Godot 在 `~/Downloads/Godot_v4.6.2-stable_mono_win64/.../Godot_v4.6.2-stable_mono_win64_console.exe`。

---

## 下一步（按建议顺序）

### 1. playtest —— 唯一的硬阻塞

**猎手侧**（boss-hunter-doctrine §5）：

- [ ] 刷出后不给任何输入，BOSS 与玩家距离**单调下降**至接战；日志中不存在 `→ ANCHOR_HOLD`
- [ ] 12km 闭合时间落在 **25~35 s**
- [ ] 10km 外锁定 BOSS → `ENGAGED` 时间戳与首次 `is_locked` 间隔 **< 0.5 s**（旧版是 8.4 s）
- [ ] 接战后全速向地图另一端飞 30 s，BOSS 仍在追（不回巢不脱战）
- [ ] 追击途中按 1-4 切控 / 触发换帅 → BOSS 目标跟着换，无崩溃
- [ ] Mother Goose 环心跟随；CSG 舰载机 4 s 后挂上玩家、航母**不**追

**Wraith 侧**（wraith-squadron §5）：

- [ ] 角色可辨：观察 60 s，KNIGHT 平均交战距离 < 2000 m、SNIPER > 3500 m，两组不混
- [ ] 包夹成立：BRACKET 时两翼与"玩家→BAIT"轴夹角 ≥60°；玩家咬住 BAIT 后 4 s 内两翼进攻
- [ ] 诱饵全程不开火
- [ ] 整场平均机头偏角 < 35°；连续 6 s >50° 时日志出现强制 RESET
- [ ] 机炮命中率明显低于 100%，能看到过头（overshoot）后被玩家反咬的窗口
- [ ] 60 s 内至少经历 2 个不同队级战术相位（日志里 `[WRAITH] 战术相位 X → Y`）

**tier 侧**（ace-squadron-tier §5）：

- [ ] 前 4 发导弹**必定**被骗飞（含迎头、含 150 m 内），第 5 发命中且不死（残血），第 6 发击坠

> 日志抓法：F9 导出，搜 `[WRAITH]`（战术相位/收网/退化）、`[BOSS]`（相位与触发器 T3/T4）、
> `[ACE]`（减速迟滞）、`engage trigger T3/T4`。

### 2. 压测

新增的每帧开销只有战术层 0.5 s 采样 + 相位切换时的一次性配置，理论上可忽略，
但按性能守则**必须实跑** Sentinel + Lv5+，FPS 掉幅 < 15。

### 3. 可选：ace-squadron-tier 阶段 4

`ace_gun.tres` 火力对齐（spec §2.4 数值表已定稿，未实装）。
这是"BOSS 机炮不如后期杂兵"的修复，与本轮独立。

---

## ⚠ 接手前必读的四个坑

### 1. 有另一个会话在并行改同一个仓库

本轮进行中，`scripts/skill_hooks.gd` / `herbst_maneuver.gd` / `cobra_maneuver.gd` /
`aircraft.gd` / `survivor_mode.gd` / `survivor_spawner.gd` / `tactical_map.gd` 等被**外部修改**，
还新增了 `AceSupportSquad`（非 BOSS 的王牌支援中队）+ `sig_skills` 测试 +
`docs/specs/events/ace-support-squadron.md`。

**后果**：
- 上表里 `aircraft.gd` / `survivor_mode.gd` / `survivor_spawner.gd` 的 diff 是**两方混合**的，
  别把整个 diff 当成本轮改动。
- 有一次 `--bench=all` 撞上写盘中途，报了 24 项**假失败**；文件稳定后重跑即 34/34 全绿。
  **看到大面积失败先确认没有并行写入**，再怀疑代码。

### 2. `AceTier.mark()` 现在有副作用

它不再只是打 meta，还会开 `gun_aim_error_enabled` + 写 `pilot_aim_skill = 0.85`。
并行会话新加的 `AceSupportSquad` 走**实例打标**（`_configure_spawn` 里调 `AceTier.mark`），
所以支援中队也会自动吃到这两项 —— 这符合 tier 语义，但**是本轮引入的新行为**，
如果支援中队的 playtest 手感变化，先想到这里。

### 3. 包围轴用 heading 约定（0=北），不是 `.angle()`

`surround_bearing` 的消费端是 `Vector2(sin(brg), -cos(brg))`。
写轴线时必须用 `WraithTactics.axis_heading()`（`atan2(d.x, -d.y)`），
用标准 `.angle()` 会让整个包夹**歪 90°**。这个坑我踩过一次，已加断言锁死（北=0°/东=90°）。

### 4. 王牌不做规避机动 —— 这是设计不是 bug

`is_boss_attacker()` 是一个**总的自保关闭开关**，屏蔽了全部规避机动入口。
[ace-squadron-tier §3.4](../specs/systems/ace-squadron-tier.md) 明确定档："王牌不靠机动躲，
靠热诱弹当命数，耗尽后**不解锁**规避"。所以再看到"BOSS 不躲"的反馈，
**先查热诱弹命数是否正常（4 命）**，不要去把规避接上 —— 那会推翻已定稿的 tier 设计。

---

## 本轮做过的两个"越权"判断（需要你复核）

### A. spec 冲突裁决：SNIPER 的交战欲

wraith-squadron §2.2 原写 SNIPER `aggression 0.75` / `self_preservation 0.35`，
与 ace-squadron-tier §2.1 的 tier 铁律（≥0.90 / ≤0.25）**直接冲突**，
而 wraith §2.5 又声明"不覆盖 tier"。

**我判 tier 赢**，并把"SNIPER 不贪战"改由 BVR 站位（空间行为，被压进 4 km 就拉开）表达。
理由写在 wraith spec §2.2 的"与 tier 的冲突裁决"段。**如果你认为应该反过来（wraith 覆盖 tier），
改 `_apply_role` 里两个数字即可，断言会红，同步改断言。**

### B. 把王牌的 `fail_chance` 归零

spec 只写了"干扰成功率 1.00"，没提 `fail_chance`（那是"对来袭导弹完全不反应"的另一个骰子，
F-47 原为 0.05 / F-14 为 0.15）。我按 §3.3 的**同一条理由**（命数必须可数、不能随机蒸发）
把它一并归零，并把这两行补进了 spec §2.2 的数值表。
**如果你希望保留一点"王牌偶尔也会漏一发"的随机性，改 spawner 里那个 match 分支 + spec 表。**

---

## 未清理项

- 临时脚本 `fix_anchors.py`（锚点批量回填）留在 scratchpad，**未进仓库**。
  它是一次性工具；如果觉得有价值可以搬进 `tools/`，但注意它只在符号有**唯一**定义时才动手，
  其余情况列出来人工处理。
- 本轮顺带回填了 **148 处腐烂的文档锚点**，其中绝大多数来自本轮之前的未提交改动
  （`survivor_data.gd` 有的偏了 575 行）。HEAD 上是 0 腐烂 —— 说明全部产生于工作区。
  这些回填混在本轮 diff 里，提交时如果想分开，可以单独 `git add docs/reference/`。
