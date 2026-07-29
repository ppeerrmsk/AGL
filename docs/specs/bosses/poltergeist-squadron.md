---
id: poltergeist-squadron
kind: boss
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 1
owner: 用户
depends_on: [wraith-squadron, boss-hunter-doctrine, ace-squadron-tier]
reconstruction_complete: true
---

# POLTERGEIST 中队（F-14 母舰死守小队）队级战术

> 母舰将沉，最后一搏弹射起飞的 4 架 F-14。它们像"骚灵"一样死缠玩家——**压迫永不落幕，绝不集体退场**。

## 1. 设计意图（Why）

Poltergeist 是 CarrierStrikeGroup BOSS 的第二阶段（CV 沉没 → 弹射 4 架 F-14，见
[boss-hunter-doctrine](../systems/boss-hunter-doctrine.md) 里 CSG 的猎手性描述）。它复用
[ace-squadron-tier](../systems/ace-squadron-tier.md) 的 tier 与 [wraith-squadron](wraith-squadron.md)
的 `AceSquad` 框架（PURSUIT + `EngagementSpeedGovernor`），但**性格与 Wraith 相反**，所以
**不能复用 Wraith 的队级战术**。

- **体验目标**：Poltergeist 攻击欲极强、自保极低（誓死护航）。玩家应感到"甩不掉、喘不过气"，
  而不是像 Wraith 那样被"耐心设局"。
- **它必须表现出 BOSS 级智商，而不是一味莽**：核心智商体现在**绝不同时变慢变傻**——
  任何一刻至少有人压在玩家脸上。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - 单杠杆：只加**一个**机制（死锁换手），不叠状态机。
  - 效果即反馈：玩家直接感到"总有一架在咬我"，无需 HUD 中介。
- **反模式规避**：
  - 不抄 Wraith 的 PERCH/BRACKET/PRESS/RESET 四态机——那是欺骗流，且 RESET"全队一起撤"
    违背 Poltergeist"誓死不退"的气质。
  - 不做诱饵机（不开火 = 消极，与本 BOSS 性格冲突）。
  - 不做归巢/锚点盘旋（[boss-hunter-doctrine](../systems/boss-hunter-doctrine.md) 已废除）。

### 1.1 它要修的具体病（playtest log 20260724_004256）

母舰弹射的 4 架 F-14 里，两架**机炮机(KNIGHT)全程 0 开火**，其中一架掉到低血后
**绕圈绕了约 60 秒**、速度掉到 ~180 m/s、机头方位角常年钉在 ±90°（一次没指向过目标）、
最后飘出主战场。根因：`PoltergeistSquad` 有 `EngagementSpeedGovernor`（修速度几何）但
**缺队级战术逃生层**——一旦被拖进"共速绕圈"死锁，没有任何机制把它拽出来，于是低能量
稳态无限延续。Wraith 靠全队 RESET 解这个死锁；Poltergeist 需要一套**符合自己性格的**解法。

## 2. 数据定义（What —— 全部数值，权威源）

本 spec 只新增**一个队级机制**：死锁单机换手（Relay Break）。其余战斗行为完全继承
`AceSquad` PURSUIT（各机跑自己的激进 BFM）与 F-14 弹射流程（见
[reference/script-index](../../reference/script-index.md) 的 `poltergeist_squad.gd` 行）。

### 2.1 死锁换手（Relay Break）参数

| 字段 | 值 | 说明 |
|---|---|---|
| 采样间隔 | 0.5 s | 每隔此时长评估一次全队死锁状态 |
| 死锁机头偏角阈值 | 55° | 单机对玩家的机头偏角超此，视为"这一刻咬不住" |
| 死锁持续判定 | 4.0 s | 连续超阈值达此时长 → 该机进入死锁，可被换手 |
| 死锁生效最大距离 | 4000 m | 仅在此距离内判死锁（远距高偏角是正常接近，不算） |
| 换手时垂直重整档 | HIGH | 换手机 `target_altitude_tier` 顶到 HIGH（爬升攒能量/高度） |
| 换手拉开距离 | 2200 m | 换手机飞向"背离玩家方向 2200 m"的点，重建间距 |
| 换手持续时长 | 3.5 s | 到时撤指令，交还 BFM 重新扑入 |
| 换手后冷却 | 3.0 s | 换手结束后此时长内不再对该机判死锁，防抖 |
| 同时换手上限 | 1 | **全队任一刻最多 1 架在换手**——这是本机制的灵魂 |

## 3. 行为与公式（How）

### 3.1 单机机头偏角（判定输入）

```
nose_off_deg(m, target_pos):
    to_t = target_pos - m.pos
    fwd  = (sin(m.heading), -cos(m.heading))   # 机头单位向量
    return |deg(angle_between(fwd, to_t))|
```

### 3.2 死锁换手主循环（在 tier 的 PURSUIT 之内，每帧跑）

```
每 0.5s 采样：
  resetting = 当前正在换手的架数
  for 每架存活、有 combat_target、非无敌、非起飞保护期的成员 m:
      if 距玩家 ≤ 4000m 且 nose_off(m) > 55°:  deadlock_timer[m] += 0.5
      else:                                      deadlock_timer[m] = 0

  # 派发换手（受"同时最多 1 架"约束）
  slots = 1 - resetting
  if slots > 0:
      候选 = { m | deadlock_timer[m] ≥ 4.0 且 m 不在换手/冷却 }
      取候选里 nose_off 最大的一架 → 开始换手（占用 slot）

每帧推进换手计时：
  换手机：target_tier = HIGH；下 fly_to(玩家背离方向 2200m, HOLD) 指令（combat_disabled=false，
          路上有解还是打）；计时 3.5s
  到时：撤指令、清 deadlock_timer、进 3.0s 冷却、交还 AceSquad PURSUIT（自动重新 ENGAGE 扑入）
```

**与 Wraith RESET 的本质区别**：Wraith 死锁 → **全队**一起 EXTEND+爬升回 PERCH（压迫短暂消失）。
Poltergeist 死锁 → **只有最咬不住的那一架**换手，其余继续压（压迫从不消失）。同时换手上限=1
直接保证了"绝不两架一起变慢变傻"。

### 3.3 与既有层的分工（不越界）

- **不每帧覆盖 AI 字段**：只在"进入换手/退出换手"两个时点各下一次指令（与 Wraith 同契约）。
- **走位靠真实转弯**：换手用 `AIDirective.fly_to` + `set_target_tier`，绝不直接挪坐标。
- **`EngagementSpeedGovernor` 不变**：治理层继续管速度几何；本层只管"咬不住时把人拽出来"。
- **起飞保护期优先**：保护期内的成员（`combat_target==null`）天然被排除，不会被换手打断爬升。

## 4. 结构与组成（Structure）

- `PoltergeistTactics`（RefCounted，独立模块，仿 `WraithTactics` 但只有死锁换手一件事）——
  持有 `_squad` 引用与三张按 `instance_id` 索引的小状态表（deadlock/reset/cooldown 计时）。
- `PoltergeistSquad` 实现 `AceSquad` 的三个战术钩子 `_tactics_enter/_update/_exit`，
  转发到 `PoltergeistTactics`（与 `F47AceSquad` 转发 `WraithTactics` 同构）。
- 纯函数 `PoltergeistTactics.nose_off_deg()` 可无头单测。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 裸物理 sim 断言：构造"两架共速绕圈"场景，跑 tactics.update →
      **恰好 1 架**被派去换手（另一架继续），且换手机 target_tier 抬到 HIGH。
- [ ] 纯函数单测：`nose_off_deg` 对正前 / 正侧 / 正后目标返回 ~0° / ~90° / ~180°。
- [ ] playtest（log 复现场景）：母舰弹射 4 架 F-14，观察不再出现"某架绕圈 >10s 且 0 开火"；
      KNIGHT 能拿到机炮开火机会。
- [ ] 性能：本层每 0.5s 采样一次、O(4)，不新增 `_process`/`_draw`；跑 Sentinel FPS 掉幅 < 15。
- [ ] 已知 seam 未触碰：只读 `members`/`_player`，不缓存玩家机引用（SEAM-019）。
- [ ] i18n：本层仅出 EventLogger 调试日志（非玩家可见 UI），无需 tr()。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 战术层
- [x] 新建 `scripts/survivor/poltergeist_tactics.gd`（死锁采样 + 单机换手 + 同时上限 1）
- [x] `PoltergeistSquad` 覆写 `_tactics_enter/_update/_exit` 转发
- [x] 修 `poltergeist_squad.gd` 头注释里"anchor 盘旋模式"的过期描述

### 阶段 2 — 验证与留痕
- [x] `scripts/tests/test_poltergeist_tactics.gd`：nose_off 纯函数 + 单机换手断言，注册进 bench_runner（`--bench=poltergeist_tactics` 9/0 PASS；`--bench=boss_hunter` 97/0 无回归）
- [x] 同步 script-index / code-index / specs/_INDEX
- [x] 写 changelog（2026-07-24-poltergeist-relay-break.md）+ 本 spec §7/§8
- [ ] §5 playtest（复现 log 场景确认体感）后 status → done

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 战术层主逻辑 | `scripts/survivor/poltergeist_tactics.gd` |
| 钩子转发 | `scripts/survivor/poltergeist_squad.gd` |
| tier 框架/钩子契约 | `scripts/survivor/ace_squad.gd`（`_tactics_*`） |
| 速度几何治理（互补层） | `scripts/ai/tactical/engagement_speed_governor.gd` |
| 单测 | `scripts/tests/test_poltergeist_tactics.gd` |
| reference 索引行 | script-index.md `poltergeist_squad.gd` / `poltergeist_tactics.gd` 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-24 | 1 | 初稿。由 playtest log 20260724_004256（F-14 死锁绕圈、KNIGHT 0 开火）驱动。定义 Poltergeist 专属「死锁单机换手」机制，区别于 Wraith 全队 RESET。 |
