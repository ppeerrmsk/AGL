---
id: ace-rotation-balance
kind: balance
status: in-progress
schema_version: 1
spec_version: 2
owner: noelu（设计输入 2026-08-01）/ Codex（量纲化与落地）
depends_on: [ace-squadron-tier, ace-support-squadron, ace-lancer-mig31]
reconstruction_complete: true
---

# 王牌中队随机轮换与标准击破时间预算

> 每局第一支王牌都可能不同，但不靠暗改血量拉平难度；六支队都以首次交火后 60~90 秒内可击破为平衡窗，战力不足的玩家仍可能被反杀。

## 1. 设计意图（Why）

- **体验目标**：新开一局不能再固定先遇到 2NDWAVE；王牌身份来自战术差异，而不是固定剧本顺序。
- **可比较目标**：把“难打”拆成可数的击破单位（DU）与无法稳定输出的接近时间，所有队共用同一公式。
- **允许失败**：60~90 秒是标准四机玩家小队的可击破预算，不是胜利保证；build、减员、操控与遭遇时的战场压力不足时，玩家可以被王牌击败。
- **Litmus 自检**：遵守一击毙命与信息察觉原则；只调整 flare 这一既有生存杠杆，不加 HP、护甲或伤害减免；MiG-31 的长追击成本显式进入时间预算。
- **反模式规避**：禁止为了凑时长加隐形血量、随机免伤或更厚 HP；实际值偏离时优先调接近窗口、编成、flare 数与可读战术，不做无感知百分比 buff。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 标准量纲

基准玩家为 **4 架存活飞机的标准小队**，计时从中队任一成员首次开火或首次受伤开始。

| 字段 | 值 | 说明 |
|---|---:|---|
| 目标击破时间下限 | 60 s | 低于此值说明中队没有形成完整战术读感 |
| 目标击破时间上限 | 90 s | 高于此值说明追击/防御预算过量 |
| 1 DU | 5 s | 标准四机小队制造一次有效击杀解的平均预算 |
| 机体成本 | 1 DU / 架 | 非 BOSS 一发命中即死 |
| 必定成功 flare | 1 DU / 枚 | 该次有效导弹解被确定取消 |
| 确定性防御动作 | 1 DU / 次 | 如 GOOFIGHTERS 每机一次 Cobra |
| `access_s` | 每队单列 | 追击、回转、重获射击窗口等不能稳定输出的总时间预算；不含边缘入场飞行 |

### 2.2 六队预算表

公式：

`DU = 存活机体数 + 必定成功 flare 总数 + 确定性防御动作总数`

`预计击破时间 = access_s + DU × 5 s`

| 中队 | 机体 DU | flare DU | 动作 DU | access_s | 预计击破时间 |
|---|---:|---:|---:|---:|---:|
| MARATHON（Su-35×5） | 5 | 5 | 0 | 25 s | **75 s** |
| 2NDWAVE（Teacher + F-15×4） | 5 | 5 | 0 | 20 s | **70 s** |
| GIMMICK（F-16×2 + Mirage×2） | 4 | 4 | 0 | 30 s | **70 s** |
| GOOFIGHTERS（Su-47×2） | 2 | 2 | 2 | 40 s | **70 s** |
| VULTURE（MiG-31×8） | 8 | **0** | 0 | 40 s | **80 s** |
| WhiteTea（F-CK-1×3） | 3 | 3 | 3 | 25 s | **70 s** |

数值裁决：

- **VULTURE 全员 0 flare**。高速掠袭、拉远与回转已收取 40 秒接近成本，再给 8 枚必躲会成为 16 DU、预计 120 秒，明显越过上限。
- **Teacher 改为 1 枚 flare**，与四名学员一致；不再同时启用持续导弹机动规避。Teacher 保留 0.50 机炮闪避与 AI 1.0，角色仍然成立。
- GOOFIGHTERS 的两次 Cobra 是可数的一次性动作，因此各记 1 DU；不把机动速度、G 力等隐性折算成额外血量。
- WhiteTea 每机一枚 flare，耗尽后才解锁且整场只可执行一次 J-turn；三次 J-turn 各记 1 DU。

### 2.3 轮换参数

| 字段 | 值 |
|---|---:|
| 六支非宿敌中队进池时间 | `game_time ≥ 240 s` |
| 抽取 | 每局开局 Fisher–Yates 洗牌 |
| 局内重复 | 禁止，无放回 |
| 连续两局首队 | session 内禁止相同；若洗牌首项相同，与后续随机项交换 |
| 同场上限 | 1 支 |
| 前队结束后的冷却 | 150 s |
| 新刷截止 | 540 s |
| ORION | 仍走宿敌独立轨道，不进入本轮换 |

## 3. 行为与公式（How）

### 3.1 新局顺序

1. 从所有 `implemented=true`、`nemesis!=true` 的 profile 构造候选。
2. Fisher–Yates 洗牌得到本局顺序。
3. 若首项等于 session 内上一局首项且候选多于 1，随机选择后续一项与首项交换。
4. 每次触发从顺序表中取第一个“已到进池时间且本局未出现”的 id。
5. profile 热更新导致顺序表无合法项时，退化为当前候选首项，事件不得卡死。

### 3.2 实测闭环

- 事件生成时记录 profile、DU、预计击破时间和目标窗。
- 首次开火/受击时把 `combat_elapsed_s` 归零；这也是分段血条亮起的同一时刻。
- 全灭、撤离、玩家先败或场景中止都记录 `result`、实际交战秒数、生成后总在场秒数与预计值。
- F9 导出的 EventLogger 中，策划按中队聚合实际交战秒数。每队至少 5 个正常战斗样本后再调数；死亡、主动撤退、BOSS 闸强制撤离样本单列，不混入“玩家击破”均值。

## 4. 结构与组成（Structure）

- profile 是轮换、flare 与 TTK 参数的唯一数据源。
- 支援中队生成器只消费 profile；`flares=0` 时移除 flare 资源，正数时复制统一支援 flare 并写入数量。
- 生存模式仅持有本局洗牌顺序和本局已使用集合；上一局首队只在当前应用 session 内保留。
- 事件类负责实际计时与日志，不新增每帧全场扫描。

## 5. 验收标准（Acceptance / Litmus）

- [x] 六支中队在 240 秒池中都有被抽为第一支的资格；局内无重复；连续两局首队不同。
- [x] 静态公式算出的六队 TTK 全部位于 60~90 秒。
- [x] VULTURE profile 为 8 架、全员 0 flare，DU=8、预计 80 秒。
- [x] Teacher 为 1 flare 且不再叠持续导弹规避，2NDWAVE 预计 70 秒。
- [x] WhiteTea profile 为 3 架、每机 1 flare + 1 次 J-turn，DU=9、预计 70 秒。
- [x] EventLogger 输出预计 TTK、实际 combat TTK、总 encounter 时长与结果（含 player_defeated）。
- [ ] 每队至少 5 个正常战斗实测样本，P50 位于 60~90 秒；超窗队按 §2.2 单杠杆回调。
- [ ] 性能：Sentinel + Lv5+ 与 8 架 VULTURE 同场，FPS 掉幅 < 15。
- [x] 已知 seam：未新增玩家引用持有者，未改变 BOSS/ORION 轨道。
- [x] i18n：无新增玩家可见文本。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与轮换

- [x] profile 统一 240 秒进池，加入 flare 与 balance 字段。
- [x] 新局洗牌、局内无放回、连续两局首项防重复。

### 阶段 2 — 生存预算与测量

- [x] VULTURE flare 归零，Teacher 改 1 枚并撤下 evade 叠层。
- [x] 实现 DU 与预计 TTK 纯函数。
- [x] 接入实际交战计时和 EventLogger。

### 阶段 3 — 验证

- [x] 回归测试覆盖轮换唯一性、六队时间窗、flare 裁决与 WhiteTea 单次 J-turn 预算。
- [ ] 收集每队实战样本并按 P50 校准 `access_s` 或显式生存杠杆。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| profile / DU / TTK / 洗牌纯函数 | `scripts/survivor/ace_squad_profiles.gd` |
| flare 注入 | `scripts/survivor/ace_support_squad.gd` |
| 新局顺序与调度 | `scripts/survivor/survivor_mode.gd` |
| 实际计时与日志 | `scripts/events/ace_reinforcement_event.gd` |
| 回归 | `scripts/tests/test_ace_tier.gd`、`scripts/tests/test_lancer_squad.gd` |
| reference | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-02 | 2 | WhiteTea 加入 240 秒统一池；三机 + 三 flare + 三次单次 J-turn = 9 DU，access 25 秒，预计击破 70 秒。 |
| 2026-08-01 | 1 | 用户要求强化新局轮换并把各队击破时间量化为 60~90 秒；建立 DU 公式、五队预算、随机无放回轮换、实际计时；VULTURE 0 flare、Teacher 1 flare。 |
