# 2026-07-24 — POLTERGEIST 死锁单机换手（Relay Break）

## 缘起

playtest log `combat_log_20260724_004256.txt`：CSG 二阶段母舰弹射的 4 架 F-14 里，
两架机炮机（KNIGHT）**全程 0 开火**，其中 PLTGST-02 掉到 30 血后**绕圈约 60 秒**、
速度掉到 ~180 m/s、机头方位角常年钉在 ±90°（一次没指向过目标）、最后飘出主战场；
PLTGST-01 也 0 开火、864s 后飞出交战圈。导弹机（SNIPER，03/04）能离轴发射，照常反击、
照常很快被打死。

用户反馈：**"boss 出的 f14 为什么变得这么傻，不反击飞的很慢，而且有一架根本不知道跑去哪里了"**。

## 根因

`PoltergeistSquad extends AceSquad`，拿到了 `EngagementSpeedGovernor`（修速度几何）但
**没有队级战术逃生层**。一旦被拖进"共速绕圈"死锁（转弯半径 ≈ 交战距离 → 机头几何上
指不到目标），没有任何机制把飞机拽出来：机炮机头永远咬不上 → 0 开火；持续满转 → 能量
被放光越飞越慢；低能量稳态无限延续 → 飘出战场。

Wraith（F-47）靠 `wraith_tactics.gd` 的 **RESET 相 + 退化检测**解这个死锁，但那是"全队一起
EXTEND 拉开回 PERCH"，与 Poltergeist"誓死护航、绝不退场"的性格冲突，**不能直接复用**。

## 改动

**新增 Poltergeist 专属队级战术：死锁单机换手（Relay Break）** —— 只做一个机制，不叠状态机。

- **`scripts/survivor/poltergeist_tactics.gd`**（新）：`PoltergeistTactics extends RefCounted`。
  每 0.5s 采样全队机头偏角；某机偏角 >55° 持续 4s 且距玩家 ≤4000m → 判死锁。派发时**只把
  最咬不住的 1 架**拽去换手：`target_tier` 顶到 HIGH（爬升攒能量）+ `AIDirective.fly_to`
  背离玩家方向 2200m（重建间距），持续 3.5s 后撤指令交还 BFM，进 3.0s 冷却防抖。
  **同时换手上限 = 1** —— 这是灵魂：绝不两架一起变慢变傻，压迫从不集体消失。
- **`scripts/survivor/poltergeist_squad.gd`**：覆写 `AceSquad` 的 `_tactics_enter/_update/_exit`
  钩子转发到 `PoltergeistTactics`（与 `F47AceSquad` 转发 `WraithTactics` 同构）。顺手修了头
  注释里"anchor_position 盘旋模式"的过期描述（2026-07-22 已随 boss-hunter-doctrine 删除归巢）。

**与 Wraith 的本质区别**：Wraith 死锁 → 全队 RESET（压迫短暂消失）；Poltergeist 死锁 →
单机换手、其余继续压（压迫从不消失）。用垂直重整（爬升）而非平面 EXTEND，天然区别于 Wraith。

## 验证

- `--bench=poltergeist_tactics`（新增，注册进 `bench_runner.gd`）：**9 断言 PASS**
  （4 纯几何 `nose_off_deg` + 5 换手/同时上限/排除项 sim）。
- `--bench=boss_hunter`：**97/0 无回归**；项目整体解析无错误。
- 差 §5 playtest（复现 log 场景，确认不再出现"某架绕圈 >10s 且 0 开火"）。

## 留痕

- spec：`docs/specs/bosses/poltergeist-squadron.md`（SSOT，新建）
- 索引：`docs/specs/_INDEX.md` / `docs/reference/script-index.md` / `docs/reference/code-index.md` 已同步
- 复用既有 plumbing（`AIDirective.fly_to` / `set_event_directive` / `set_target_tier` / `_tactics_*` 钩子），
  未造新机制、未写死散点魔法数（数值集中为具名常量，权威在 spec）。
