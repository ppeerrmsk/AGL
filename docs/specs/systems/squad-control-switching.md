---
id: squad-control-switching
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 8
owner: noelu
depends_on: [survivor-loop, squad-upgrade-ownership]
reconstruction_complete: false
---

# 玩家小队操控切换 —— 数字键接管 + 长机/僚机移交

> 玩家视角：你的队伍最多有 9 架飞机。默认操控 1 号长机，**按数字键 1–9 把操控权切到对应号机**，相机直接切过去；被切中的机立刻成为长机受你操控，原长机降为僚机继续自主作战。RTS 化第一块交互：你不再被绑死在一架飞机上，而是"指挥并随时上手"任意一架。

## 1. 设计意图（Why）

AGL 正在 RTS 化。本功能让"小队"成为可操控单位池：玩家随时切换"亲自驾驶哪一架"，其余交给 AI 僚机自主打。这是"满地图都在交战、既混乱又有秩序"氛围的第一步玩家侧抓手。

**体验目标**：
- 操控权切换**即时**：按 1-4 直接上手对应号机；相机直接切（不插值）。
- **行为延续**：接管后飞机延续它当前的航向/攻击目标，不突变。
- **平滑降级**：原长机变僚机后，**先完成当前动作**（带延迟）再融入编队，不瞬间甩头归队。
- **视觉锚点**：当前操控机状态栏底色**白色**，其余友机**蓝色**，敌机**红色**——一眼看出"我现在是谁"。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 2（笨重 + 延迟快感）**：✅ 不破坏。任一时刻仍只精控一架笨重飞机；切换只是换"哪一架"，单机操控手感不变。
- **原则 3（信息察觉优先）**：✅ 白/蓝/红底色 + 相机切换是强可感知反馈。
- **原则 7（战场要热闹 + AI 演戏）**：✅ 强化。僚机全程自主演戏，玩家上手任意一架，多线交战感增强。
- **原则 10（全武器自动开火）**：✅ 一致。接管后武器仍自动触发；数字键只切操控对象、点击只下达"去哪/打谁"，都不是手动扳机。
- **原则 11（60 FPS）**：✅ 切换是输入事件级（非每帧）；底色复用既有 draw_data_label；无新节点/扫描。

**反模式规避**：
- ❌ 不引入"同时手操多架"（破坏单机笨重操控核心）——一次只亲控一架，其余 AI。
- ❌ 不让接管瞬间清空目标/甩头（破坏延续感）——combat_target / target_position 保留 + 降级 grace。
- ❌ 不丢敌我识别（敌机保持红色）。

> ⚠️ 北极星提示：这是 RTS 化方向的交互改动，但仍落在"任一时刻精控单架"的框架内，**未推翻** DESIGN_PHILOSOPHY 原则 2。若后续要做"同时指挥多架/框选下令"，那才需要回头改哲学文档。

## 2. 数据定义（What —— 权威源）

### 2.1 两套编号（关键，不可混淆）

| 编号 | 字段 | 稳定性 | 用途 |
|---|---|---|---|
| **号机号 squad_slot（1-4）** | `Aircraft.squad_slot: int`（新增） | **出生即定，永不变**（即使该机被接管成长机或降为僚机） | 数字键绑定（键 N → squad_slot==N）+ 状态栏显示"1/2/3/4" |
| **编队角色 squad_index（0=长机）** | 既有 `squad_index` | **随接管变动**（当前操控机 = 长机 = index 0） | 编队阵型槽位计算 |

> 例：你按 3 切到 3 号机，3 号机 squad_slot 仍是 3（身份不变），但它现在 squad_index=0（成为长机）；原 1 号机 squad_slot 仍是 1，squad_index 变为非 0（降为僚机）。**数字键永远对应同一架物理飞机。**

### 2.2 状态栏底色（每架飞机浮动标签 draw_data_label 的背景）

| 单位状态 | 底色 | 备注 |
|---|---|---|
| **当前操控机** | **白色** `Color(0.92, 0.92, 0.96, 0.90)`，文字深色 | 全场至多一架 |
| **友方其余机**（team==0 非操控） | **蓝色** `Color(0.10, 0.15, 0.35, 0.85)` | 复用现有 team0 底色 |
| **敌机**（team==1） | **红色** `Color(0.35, 0.08, 0.08, 0.85)` | 复用现有 team1 底色，**不变** |
| 中立/其它 | 现有规则 | 不变 |

> 现状 team0 本就蓝底、team1 红底；本功能**只新增"当前操控机=白底"分支**。判定 key = `ac == 当前操控机引用`（非 team）。

### 2.3 键位与切换/过渡常量

| 项 | 值 | 说明 |
|---|---|---|
| 切换操控 | `KEY_1` .. `KEY_9` | 键 N → 选中 squad_slot==N 的存活友机；无对应/已死/即当前机 → no-op。上限 9 = 编队上限（zone-reward-docking §2.5，奖励僚机可堆满） |
| 高度偏好切换 | `KEY_Q`（原 KEY_3/4 → KEY_Z → Q） | 爬升↔低空 toggle；HUD 标签 + 悬浮提示同步 |
| 武器偏好切换 | `KEY_T`（原 KEY_1/2 → KEY_Q → T，Q 腾给高度） | 导弹↔机炮 toggle；HUD 标签 + 悬浮提示同步 |
| 小队交战模式 | `KEY_C`（原 KEY_6，被 1..9 切控拦截成死键后迁移） | 三态循环：自由交战 → 跟随长机 → 守护后方 |
| 小队武器偏好 | `KEY_V`（原 KEY_7，同上） | 小队导弹↔机炮 toggle |
| `TAKEOVER_TRANSITION_GRACE` | 6.0 s（**兜底上限**，非固定延迟） | 降级过渡**事件驱动**为主："打完再归队"——原长机保持当前 combat_target/target_position 直到**目标消失或到达**才融入编队；此常量只是防呆兜底（万一目标长期不消失，最多 6s 后归队），正常情况由事件触发，不是定时 |
| 相机切换 | 即时（snap） | 接管后相机位置直接置到新机，不做 follow 渐入插值 |
| 可选切换键上限 | 9 | 编队上限 9（zone-reward-docking §2.5）；1-9 全留给切控，战术/小队命令键一律走字母键 |

### 2.4 AI 模型字段（"全机常挂 AI，操控机休眠"）

| 字段 | 载体 | 语义 |
|---|---|---|
| `manual_control: bool` | AIController（新增） | true = 该机被玩家亲控，AI **休眠**：不发 target_position、不选战术、不设速度/高度目标；但**仍维护内部状态**（_current_target 等）以便恢复延续。auto-missile-evasion 反射保留（§3.5） |
| 当前操控机引用 | survivor_mode `player_aircraft` + `AircraftRenderer.player_ref` | 唯一真源；切换走单一 chokepoint `set_player_aircraft()` 原子更新所有消费者 |
| `use_tactical_preference: bool` | Aircraft | 当前操控角色的物理/战术权限；全队恰好一架为 true。换机必须同一事务中设 `old=false` / `new=true`，否则新操控机会误吃导弹 phase-2 的 35% 坡度上限，旧机则永久保留玩家豁免 |

## 3. 行为与公式（How）

### 3.1 数字键切换触发

`_unhandled_input` 监听 KEY_1..KEY_9：
```
按下键 N：
  target = squad.members 中 squad_slot == N 且存活的那架
  若 target 不存在 / 已死 / == 当前操控机 → 忽略（no-op）
  否则 → switch_player_to(target)   (§3.2)
```
- 鼠标左键语义**不变**：点敌机=当前操控机攻击、点空地=当前操控机移动指令。右键清目标不变。
- 武器/高度/小队命令键位见 §2.3 键位表（数字键已全部让位给切控，战术键走字母键）。

### 3.2 接管流程（switch_player_to(new_ac)）

原子顺序：
1. `old_ac = 当前操控机`；若 `new_ac == old_ac` 或 new_ac 无效（死/不在 squad）→ return。
2. **新机上手**：`new_ac.ai.manual_control = true`（AI 休眠）；保留 `combat_target` / `target_position`（延续当前动作）。
3. **编队换长机**：`squad.set_leader(new_ac)`（§3.3）→ 触发 `leader_changed`（只动 squad_index，**不动 squad_slot**）。
4. **旧机降级**：`old_ac.ai.manual_control = false`（AI 唤醒）→ §3.4 平滑降级（带 grace）。
5. **重定向操控真源**（单一 chokepoint `set_player_aircraft(new_ac)`）：
   - `old_ac.use_tactical_preference = false`，`new_ac.use_tactical_preference = true`
   - `survivor_mode.player_aircraft = new_ac`
   - `AircraftRenderer.player_ref = new_ac`
   - `_camera_ctrl.set_follow_target(new_ac)` + 相机位置即时 snap
   - HUD 右下状态面板刷新到 new_ac
6. 底色下一帧自动更新（draw_data_label 读新操控机引用）。

### 3.3 Squad.set_leader(new_leader)（新增 API）

对标现有 `remove_member` 的降级逻辑做显式换帅：
```
func set_leader(new_leader):
    if new_leader == leader or new_leader not in members: return
    leader = new_leader
    重新分配各成员 squad_index（0 = new_leader，其余按原序补位）  # 注意：不触碰 squad_slot
    leader_changed.emit(new_leader)
```
僚机 `_formation_leader` 经 `leader_changed` 自动指向新长机；阵型槽位下一帧由 get_formation_offset 重算（既有机制）。

### 3.4 平滑降级（原长机 → 僚机，第 3 点 —— "打完再归队"事件驱动）

旧机 `manual_control` 关闭后 AI 唤醒，**先把手头动作做完再归队**，归队时机由**事件**触发，不是定时：
```
降级时记录 _takeover_transition_timer = TAKEOVER_TRANSITION_GRACE (6.0s 兜底上限)
过渡期内：保持当前 combat_target（继续打原目标）+ target_position（继续飞向原点），不读编队 offset、不执行归位转向
归队触发（任一先到）：
  - combat_target 消失（被击落 / 脱锁 / 失效）  ← 主驱动："这一仗打完"
  - 到达 target_position（这段飞完）
  - 6.0s 兜底上限到（防呆，防止目标长期不消失卡住）
归队后：正常进入 SQUAD_FOLLOW，融入新长机阵型
```
效果：飞机"把手头这下打完/这段飞完"再归队，不被接管瞬间甩头。复用现有 grace 范式（参照 LEADER_TARGET_LOST_GRACE）。

### 3.5 换帅的最小扰动原则（不惊动各自为战的僚机）★

**核心约定**：切换操控对象**只改"谁听玩家点击"**，绝不打断其它僚机正在进行的独立战斗。

`set_leader` / `leader_changed` 只做两件事：**更新 leader 引用 + 重排 squad_index 记账**。它**不主动把任何僚机踢出当前 AI 状态**。每架僚机是否归位、归位到谁，由它自己的 AI 状态机决定：

| 僚机当前状态 | 换帅后 | 是否受影响 |
|---|---|---|
| `engage_mode = FREE`（各自为战，正在打自己的目标） | 继续打自己的，**完全不读新长机、不归位** | ❌ 不受影响 |
| `SQUAD_FOLLOW`（正归位跟随长机） | 下一帧起跟随**新**长机的阵型槽位 | ✅ 仅换跟随对象，平滑 |
| 被接管成为新长机 | manual_control=true，听玩家 | 成为操控机 |
| 旧长机（刚被卸下操控） | §3.4 打完再归队 | 延迟过渡 |

举例（用户场景）：1 号、4 号机在 FREE 各自交战，玩家在 2、3 号机间反复切换。因为 1/4 号机处于 FREE engage、根本不读编队阵型，**无论玩家在 2/3 间切多久、切多少次，1/4 号机的战斗都不受任何影响**。只有处于"归位跟随"状态的僚机才会把跟随目标从旧长机切到新长机。

> 实现注意：`set_leader` **禁止**遍历 members 强制设 `formation_mode=true` 或强制状态转 SQUAD_FOLLOW。leader 引用更新后，FREE 僚机的决策路径压根不碰 leader，天然隔离。

### 3.6 休眠 AI 的反射保留

`manual_control = true` 时 AI 不做战术导航，但**自动反射保留**（与原则 10 自动开火同理，玩家无法微操）：
- **自动闪避来袭导弹**（flare / break 反射）仍触发。
- **武器自动开火**仍按状态触发。
- 仅"去哪 / 打谁的主动决策"被玩家接管。

### 3.7 击落自动接管（边界）

当前操控机（= 长机）被击落时：
- Squad 既有：长机阵亡 → `leader = members[0]`，`leader_changed`。
- 追加：若死的是当前操控机 → `set_player_aircraft(新 leader)`（相机 snap，新机 `manual_control = true`）。新机 squad_slot 不变（仍按其原号机号显示）。
- squad 已无存活成员 → 走既有"全队覆灭 → Game Over"流程（用户决策：全队阵亡才算局结），不变。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `Aircraft.squad_slot` | 稳定号机号（1-4），键绑定 + 显示 | **新增字段**，spawn 时赋值 |
| `set_player_aircraft(ac)` chokepoint | 原子重定向 player_aircraft / player_ref / 相机 / HUD | **新增**（survivor_mode） |
| `Aircraft.use_tactical_preference` | 玩家操控角色的全坡度战术权限 | 由同一 chokepoint 原子从旧机转给新机 |
| KEY_1..4 切换监听 | §3.1 | 改 _unhandled_input（survivor_mode） |
| 武器偏好键迁移 KEY_1/2 → KEY_Q | 腾出数字键 | 改（survivor_mode + 键位帮助文本 + i18n） |
| `Squad.set_leader(new_leader)` | 显式换帅，只动 squad_index | **新增**（squad.gd） |
| `AIController.manual_control` | 操控机 AI 休眠 + 反射保留 | **新增字段 + 分支** |
| `_takeover_transition_timer` | 降级 grace | **新增**（AIController） |
| draw_data_label 底色 + 号机号显示 | 当前操控机白底 + 1/2/3/4 标号 | 改（aircraft_renderer + game_constants 颜色） |
| HUD 右下状态面板 | 反映当前操控机 | 改（survivor_hud） |
| 击落自动接管 | 监听 leader_changed / 死亡 | 改（survivor_mode 接 squad 信号） |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **数字键即时切换**：按 1-9 → 相机即时切到对应号机、该机变白底、原机变蓝底。键对应同一架物理飞机（接管后再按同键回切到原机）。
- [ ] **号机号稳定**：接管使某机成长机后，它的 squad_slot（号机号）不变；数字键映射不漂移。
- [ ] **行为延续**：切到一架正在追打某敌机的僚机，接管后它继续朝该敌机机动（combat_target/target_position 未清）。
- [ ] **打完再归队**：原长机变僚机后不瞬间甩头归队，**先打完当前目标 / 飞完当前航路**（事件驱动）再融入编队；目标消失即归队，不是死等定时。肉眼可见过渡。
- [ ] **★最小扰动**：1、4 号机在 FREE 各自交战时，玩家在 2、3 号机间反复/长时间切换，**1、4 号机的战斗轨迹与目标完全不受影响**（不归位、不甩头、不换目标）。只有处于归位跟随的僚机才把跟随对象切到新长机。
- [ ] **底色三态**：全场至多一架白底；友方其余蓝底；敌机始终红底（敌我识别不丢）。
- [ ] **战术键位真相化**：T 切导弹/机炮、Q 切爬升/低空、C/V 切小队交战/小队武器均正常；数字键 1-9 只切控不再碰战术；HUD 标签与悬浮提示显示的键与实际一致。
- [ ] **休眠反射**：亲控时来袭导弹仍自动闪避、武器仍自动开火；仅主动战术导航交玩家。
- [x] **操控权限单例**：任意主动切控/长机阵亡接管后，新操控机 `use_tactical_preference=true`、旧机=false；新机不会因导弹 phase 2 在 35%/100% 坡度权限间反复切换。
- [ ] **击落接管**：操控机被击落 → 自动接管下一存活号机、相机 snap；全队覆灭才 Game Over。
- [ ] **边界**：按当前机的键=no-op；按对应已死/不存在号机的键=忽略；单机无僚机时无异常。
- [ ] 性能：切换为输入事件级；生存模式 Sentinel + Lv5+ 满编队压测 FPS 掉幅 < 15。
- [ ] 已知 seam：player_ref 所有消费者（相机/HUD/renderer/雷达"是否玩家"判定）经单一 chokepoint 原子更新，无半切状态（新增 seam 条目登记）。
- [ ] i18n：武器偏好键位文本 + 可能的"号机号/操控中"提示走 tr()，三语补。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 基础设施 ✅（早前会话，commit 04a7a44）
- [x] `Aircraft.squad_slot` 字段 + spawn 时按生成序赋 1..N（长机=1，僚机 2..N）。
- [x] `Squad.set_leader(new_leader)`：换帅 + squad_index 重排（不动 squad_slot）+ 发 leader_changed（§3.3）。
- [x] `AIController.manual_control` 字段 + 主循环开头分支：true 时跳过战术/导航、仅保留反射（§3.5）+ 维护内部状态。
- [x] `AIController._takeover_transition_timer` + SQUAD_FOLLOW 前置 grace（§3.4）。

### 阶段 2 — 操控真源 chokepoint ✅（早前会话，commit 04a7a44）
- [x] 操控真源切换（chokepoint 内联在 `_switch_control_to_slot`）：原子更新 player_aircraft / player_ref / 相机 snap / HUD（§3.2 步骤 5）。命名与 spec 的 `set_player_aircraft` 不同（内联实现），功能等价。
- [x] `_set_player_aircraft` 同时转移 `use_tactical_preference`；旧机清除、新机授予，覆盖手动切控与阵亡接管。
- [x] 全队初始化：所有友机挂 AIController；初始 1 号机 `manual_control = true`。

### 阶段 3 — 键位与切换交互 ✅（早前会话，commit 04a7a44）
- [x] 武器偏好 KEY_1/2 → KEY_Q 迁移（survivor_mode + 帮助文本 + i18n）；KEY_3/4 高度偏好同迁。
- [x] _unhandled_input 加 KEY_1..4 → 查 squad_slot → `_switch_control_to_slot`（§3.1，命名替代 spec 的 switch_player_to）。
- [x] `_switch_control_to_slot(slot)` 协调全流程（§3.2）。

### 阶段 4 — 视觉 + 击落接管 ✅（早前会话，commit 04a7a44）
- [x] draw_data_label：当前操控机白底分支（§2.2）+ 号机号显示。
- [x] survivor_mode 接 squad `leader_changed` / 死亡 → 击落自动接管（§3.6）；全队覆灭才 Game Over。

### 阶段 5 — 验收调优 ⏳（待 playtest）
- [x] 更新 §7 锚点 + reference 索引（本次文档对齐）。
- [ ] **跑 §5 全部验收 + 边界 + 性能压测（需在 Godot playtest，未代跑）**。
- [ ] 调 TAKEOVER_TRANSITION_GRACE 至降级过渡自然。
- [ ] known-seams 登记 player_ref chokepoint（如尚未登记）。
- [ ] §5 验收通过后：status → done，reconstruction_complete → true。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 键切换入口 / 操控 chokepoint（内联）/ 击落接管 | `scripts/survivor/survivor_mode.gd`（`_unhandled_input` KEY_1..9 → `_switch_control_to_slot`；战术键 Q/T/C/V 同函数；player_aircraft/player_ref 原子重定向） |
| squad_slot 号机号字段 | `scripts/aircraft.gd`（`squad_slot`）；spawn 赋值在 `survivor_mode.gd`（长机=1、僚机 `ac.squad_slot = i+1`） |
| 换帅 API / 继任反向引用修复 | `scripts/squad.gd`（`set_leader` / `cleanup` / `_sync_member_bindings`） |
| manual_control / 降级 grace | `scripts/ai_controller.gd`（`manual_control` 字段 + 休眠分支 + `_takeover_transition_timer`） |
| 状态栏白底 + 号机号 | `scripts/aircraft_renderer.gd`（draw_data_label 当前操控机白底分支）+ `scripts/game_constants.gd`（颜色） |
| HUD 状态面板 / 武器偏好键 | `scripts/survivor/survivor_hud.gd` |
| reference 索引行 | script-index.md / code-index.md 对应段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 初稿（draft）：长机/僚机移交。决策：敌机保持红底 / 击落自动接管 / 全机常挂 AI 操控机休眠。 |
| 2026-05-30 | 2 | 切换机制定为**数字键 1-4**（非点选）；引入稳定 `squad_slot` 号机号与编队 squad_index 解耦（键永远对应同一物理机）；武器偏好键 KEY_1/2 迁移到 KEY_Q 腾位。 |
| 2026-05-30 | 3 | 降级过渡改为**"打完再归队"事件驱动**（目标消失/到达即归队，grace 6s 仅兜底）；新增 §3.5 **换帅最小扰动原则**——set_leader 只换引用不强制归位，FREE 各自为战的僚机切换时完全不受影响（用户场景：在 2/3 间切换不扰动 1/4）。待用户 review → approved。 |
| 2026-06-07 | 3 | **文档对齐代码**（status draft→in-progress）：核对确认 §6 阶段 1-4 **早前会话已全部派生**（commit 04a7a44）——`Aircraft.squad_slot`、`Squad.set_leader`、`AIController.manual_control` + `_takeover_transition_timer`、KEY_1..4 切换 + `_switch_control_to_slot`、KEY_Q 武器偏好迁移、白底 + 击落接管。实现命名与 spec 略有出入（chokepoint 内联在 `_switch_control_to_slot` 而非独立 `set_player_aircraft`/`switch_player_to`，功能等价）。回填 §6 勾 + §7 真实文件锚点。**唯一未尽**：§5 验收为 playtest 项（需 Godot 内目测 + Lv5+ 压测），未代跑 → 故 status 暂停在 in-progress，验收通过后转 done。 |
| 2026-07-27 | 4 | **键位真相化批**（文档对齐代码 + 换绑）：切控键实际早已扩至 **1-9**（zone-reward-docking §2.5 编队上限 9），导致原 KEY_6/7 小队命令分支被切控拦截成**死键**，且 HUD 标签仍显示 1/3/6/7 与实际按键不符。换绑：高度偏好 KEY_Z→**Q**（用户指定）、武器偏好 KEY_Q→**T**、小队交战 KEY_6→**C**、小队武器 KEY_7→**V**；E 加力 / F 自动发射 / R 手动机动 / WASD 相机不变。i18n 三语标签（TACTIC_*/SQUAD_*）+ 悬浮提示（TOOLTIP_*_HINT）同步。§2.3 键位表重写为唯一真源。 |
| 2026-07-29 | 5 | **固定号机号重新收口**：撤销后续曾引入的“按存活列表动态压缩”实现，数字键恢复严格匹配稳定 `squad_slot`。小队面板显示当前操控机与全部僚机的固定数字；阵亡号位留空，新入队飞机回填最小空号。 |
| 2026-08-03 | 6 | **修长机阵亡后全队指挥失联**：武器在 survivor 死亡检查后击毁长机时，僚机 AI 会先把 `AI.squad` 清空；下一帧仅晋升 leader 未恢复反向引用，轮盘遂退化为单机命令。`Squad.members/leader` 定为结构真源，cleanup/换帅时原子恢复全员 `AI.squad`、连续重排 `squad_index`、刷新编队缓存；自动接管新长机完整 `clear_formation()`。`squad_cmd_ui` 新增真实时序回归，26/26。 |
| 2026-08-04 | 7 | 文档维护：把摘要中遗留的 1–4 改为已在 v4 落地的 1–9；机制与代码不变。 |
| 2026-08-18 | 8 | 修复换机只转移 player_ref、未转移 `use_tactical_preference`的角色半切状态：新操控机曾被当作普通 AI，在导弹发射锥边界反复切换 35%/100% 坡度上限，导致滚转与 G 值抽动。现由唯一 chokepoint 原子转移，`squad_cmd_ui` 28/28 直接对比两种坡度 cap。 |
