# Player AI Changelog

玩家自动战斗 AI（`aircraft.gd` 里 `_update_combat` / `_choose_dogfight_pursuit_pos` / `_auto_gun_scan` 等分支）的所有调整记录，按时间倒序。

## 为什么要这个文件

玩家飞机不是纯 RTS 手动飞 —— 锁定敌机后（`combat_target != null`）有一层自动追踪/开火逻辑。这套逻辑调过很多轮，每次都牵扯到：
- 追尾、对头、侧翼等多种相对位置
- 机炮 vs 导弹两种武器模式
- 过顶脱离、闭合率、前置点、机会射击等独立子系统
- 不同机型（玩家 F-16 / F-14 等）的参数差异

**教训**：直接改公式/常量很容易把一个情景修好、另一个情景搞坏，过去修好的 bug 又复发。

## 工作约定

1. **默认偏好"加一层守卫判定"**（early-return / 条件分支 / override），保留老路径作为 fallback。适用于：原公式在大多数场景正确、只在特定边界失灵。优点是老 case 保留不动，新 case 单独处理。
2. **公式/常量本身错的时候直接改**。适用于：原公式对所有 case 都偏差、常量标定不对、加守卫会变层层叠叠补丁。改的时候在本文件记一条说明"为什么改公式比加守卫干净"。
3. **两种都不对的时候重构**。上一条的 LOD 2 / LOD 1 路径补丁太多时，最好坐下来把整个路径梳理一遍而不是再堆补丁。
4. 改动必须带注释说明：① 触发条件 ② 为什么需要 ③ 指向本文件某条记录
5. 每次改动在本文件顶部加一条，写清楚：
   - 日期
   - 症状（玩家反馈）
   - 根因（哪段代码在哪种场景下失灵）
   - 修复方式（加守卫 / 改公式 / 重构，在哪个文件的哪一行）
   - 回归测试要点（下次改附近代码要重点验证的场景）
6. 玩家 AI 改动前先读本文件，防止踩已修过的坑

## 血泪教训（2026-04-20 一整天修 F-47 BOSS 相关 bug 总结）

一天修了 11 轮，其中 8/11 是修之前几轮修坏的东西。关键教训如下：

### L1. 先诊断再修，不要瞎猜

**错误**：玩家报告"飞机绕错方向 / 对头不开火 / BOSS 不追玩家"时，没有运行时数据就开始猜根因、改公式。

**后果**：常常猜错，把一个 case 修好、另一个 case 搞坏；2~3 轮后 bug 依然存在，还多了新 bug。

**正确做法**：先加诊断事件（PURSUIT / AC_TICK / ENEMY_SQUAD 这类快照），用节流日志抓运行时状态。**user 原话："不能通过修改，而是添加判定的机制来改善"**。等 log 能证明根因在哪一行后再动手改。

日志的价值：2026-04-20 (3) 从"玩家绕圈"症状到定位 `B_rear_six_offset` 分支只用了 3 分钟，而前面几轮瞎改没触及这条路径。

### L2. 加守卫是默认偏好，但不是铁律

2026-04-20 (1) 用户说的是"我觉得不能通过修改，而是添加判定的机制来改善" —— 这是**当时那个具体 bug** 的建议（场景是改 target_position 计算公式会连带影响对头/追尾等多个已工作的 case，加守卫更安全）。

我后来过度推广成了"永远不能改公式"，这是误解。正确理解是：
- **默认偏好加守卫** —— 原公式在大多数 case 正确时，加判定处理边界 case，避免把好 case 搞坏
- **公式本身错就直接改** —— 例如常量标定不对、公式忽略了重要条件、加守卫会变补丁地狱
- **不要教条化** —— 工程判断每次情况都不同，关键是改完能 justify "这种改法比另一种干净"

### L3. 改完一处就停下来让 user 验证，不要连续堆叠

**错误**：我曾经一轮就改了 5 个地方（bank 翻转守卫 + Herbst TURN 跳过 + LOD 2 切换 + delta*3 + visuals 同步），每个改动都是"推测这个也需要改"。

**后果**：某个改动引入新 bug 后，用户很难分辨是哪个改动导致的；我自己也容易搞混因果。

**正确做法**：一次只改一个明确定位的 bug。改完 commit，等 user 下一份 log 验证。如果 user 说"变得更糟"，优先考虑**回滚刚才的改动**而不是叠加更多改动。2026-04-20 (9-11) 就是这种"连环修坏"的典型。

### L4. "Frozen" 不一定是真冻住，可能是"慢动作"

**错误**：user 说 "飞机离屏不动"，我一度认为物理完全停了。

**实际**：是 `set_physics_process(false)` 导致 Godot 跳过 `_physics_process` 调用，但 `delta` 在 Godot 里**永远是单帧 1/60s**（不会累加），跑 1/3 的帧 → 飞机按 1/3 实时速度运行。user 看到的是 3 倍慢动作，不是真 frozen。

**教训**：Godot 里只要 `_physics_process` 还在被调用，delta 始终单帧。任何"每 N 帧跑一次"的节流必须**手动把 delta 乘以 N**（AIController.`ai_tick_divisor` 就是正确范例，line 384-387）。否则就是 1/N 速度 bug。

### L5. LOD 状态切换必须双向对称

**错误**：给敌机 `_update_enemy_lod` 离屏分支加 `lod_level = 2`，屏幕内分支忘了加 `lod_level = 0`。敌机进了 LOD 2 就永远卡在那。

**后果**：label 不更新（queue_redraw 节流）、label 跟飞机转（inv_rot 过时）、物理过激（delta*3 在屏幕内还跑）。

**正确做法**：所有 LOD / 状态字段（lod_level / visible / formation_mode / ai_override_pursuit 等）的切换必须**每个状态分支都显式赋值**，不能依赖"离屏改、屏幕内不改"的不对称写法。参考友军侧正确写法 [_update_friendly_squad_lod:780](scripts/survivor/survivor_mode.gd:780)：每帧 if/elif/else 三个分支都显式设 lod_level。

### L6. 改 LOD 2 / LOD 1 路径前必须审计完整依赖

LOD 路径里每一步（`_update_combat / _update_bank / _update_visuals / queue_redraw / _apply_movement`）都可能被跳过。改 LOD 分支时要问自己：

- 这个路径少调了哪些 LOD 0 有的函数？（例如 LOD 2 漏 `_update_visuals` 导致 rotation 不同步）
- 用了 delta 的函数是否正确 × tick_divisor？（例如 LOD 2 用 `delta` 而不是 `delta*3` 导致物理 1/3 速度）
- `queue_redraw` 的触发条件是否够？（例如 LOD 2 只在 selected 时 queue，普通敌机 label 就不刷新）
- 状态变量（flag / timer / counter）在跳过的帧里会不会失去推进？

**教训**：2026-04-20 (8) 把敌机切到 LOD 2 的时候，上面四个问题都没审计，后面用 (10)/(11) 三轮才补齐。应该一开始就检查清楚再动。

### L7. 用户说"变得更糟"时，认真考虑回滚

**错误**：user 在 2026-04-20 (10) 反馈"你之前的所有修复似乎几乎没有任何实质效果，而且让问题变得更严重了"后，我还是在 LOD 2 路径上加补丁，没有考虑回滚到 pre-(8) 的 set_physics_process 方案（那方案有 1/3 速度 bug，但至少不会造成图标反转/label 挂着转这种严重视觉问题）。

**教训**：用户用"更严重"/"更糟"/"失控"这类词时，这是 stop-the-bleeding 信号。立即停手，评估是否回滚到最后一个已知稳定版本，而不是继续补丁。

### L8. 诊断事件的设计原则

这一天加的诊断事件（PURSUIT / AC_TICK / ENEMY_SQUAD / PURSUIT_LOCK / PURSUIT_UNLOCK 等）都很有用。好的诊断事件：

- **节流**：高频状态用 0.1~0.5s 节流，避免日志爆炸
- **触发条件**：只在感兴趣场景触发（例如 AC_TICK 仅当 bank>60° 或 Herbst/Cobra 激活），正常场景 0 污染
- **字段设计**：不是堆原始字段，而是**让异常模式一眼可见**的组合（例如 `tp_brg°` 正负号直接告诉你"目标在左还是右"，`dL` 距长机距离飙升就是跑路）
- **条件退出自重置**：像 AC_TICK 的 `_ac_tick_log_timer = 0.0`，条件失效就重置节流，下次进入立即采样第一帧
- **只给玩家/BOSS 打，不污染全场**：用 `use_tactical_preference` / `is_boss_attacker()` 这种身份标记过滤

---

## 2026-04-27 AI 战斗时不再无脑贴目标高度：导弹战保自身作战高度

### 症状 / 设计动机

用户观察：所有 AI 一进 ENGAGE 就调 `BFMTactics.match_target_altitude(ai)` 把自身高度同步到目标高度，导致：
- Lancer 类（MiG-31 / F-100）失去高空 BVR 优势 —— 玩家在 1000m 它就跟着掉到 1000m 打导弹
- 飞机的 `patrol_altitude`（出生时随机 4000~9000m 的"作战高度"）只在巡逻有用，进战斗瞬间被抹消
- `preferred_altitude_tier` 字段（`ai_controller.gd:113`）是预留的"作战偏好高度"位但根本没接通

### 根因

7 个战术执行器 + AIController 入口（`ai_controller.gd:1265`）一起强制 match_target_altitude：
- `bfm_tactics.gd:300/310/326/359/403/447/500` —— LEAD/LAG/LEAD_TURN/HIGH_YOYO recover/LOW_YOYO recover/BREAK phase1/SCISSORS
- `bfm_intent.gd` 在 6 个战斗 intent 里写死 `p.target_altitude_m = s.tgt_alt`（CLOSE_TAIL / TAIL_CHASE / LEAD_TURN / LAG_PURSUIT / LEAD_PURSUIT / MERGE_PASS）

附带的硬约束：`aircraft_combat_tracking.gd:659` 导弹包线高度差 > 3000m 直接禁火 —— 这是为什么之前不敢留高度差的物理原因。

### 修复方式

**改公式（不加守卫）**：原来的"无条件匹配"对所有 case 都偏差，加守卫会变补丁地狱。直接按"机炮战 vs 导弹战"分桶。

1. **新增 `BFMTactics.use_combat_altitude(ai)`** ([bfm_tactics.gd:524](scripts/ai/bfm_tactics.gd:524))：使用 `ai.patrol_altitude` 作偏好，clamp 到目标 ±2500m 内。扁平模式下选 patrol 对应档但限制目标 ±1 档。
2. **AIController 入口** ([ai_controller.gd:1266](scripts/ai_controller.gd:1266))：alt_diff > 500m 时调 use_combat_altitude（默认作战高度），不是 match_target_altitude。
3. **BFMTactics 战术分桶**：
   - LEAD_PURSUIT / LEAD_TURN — 距离 > gun_range×3 用 use_combat，否则 match
   - LAG_PURSUIT / SCISSORS / BREAK_TURN phase1 / YOYO recovery — 保持 match（机炮战或恢复几何）
4. **TacticalPlanner 路径**：
   - `Situation.combat_altitude_m` 新字段 ([situation.gd:58](scripts/ai/tactical/situation.gd:58))，从 AIController.patrol_altitude 注入；玩家用 my_alt
   - `BfmIntent._apply_target_altitude(s, p)` 新辅助 ([bfm_intent.gd:438](scripts/ai/tactical/bfm_intent.gd:438))：weapon_mode==MISSILE → combat altitude（clamp 目标 ±2500m），否则 tgt_alt
   - 6 个战斗 intent 的 `p.target_altitude_m = s.tgt_alt` 替换为 `_apply_target_altitude(s, p)`
5. **导弹包线高度差上限** ([aircraft_combat_tracking.gd:660](scripts/aircraft/aircraft_combat_tracking.gd:660))：3000m → 5000m。AI 用 use_combat_altitude 的 ±2500m clamp 留 2500m 余量给 yoyo / extension 等过渡瞬态。

### 设计取舍

为什么 clamp ±2500m 而不让 AI 真的保留 4000m+ 高度差：导弹包线 5000m 是物理合理的硬上限（AAM 垂直能量耗损），允许 AI 高出目标 2500m 已经能吃到"BVR 高位"优势 + 让 patrol_altitude 真正生效，又不会让 missile envelope 频繁拒火。如果之后觉得 Lancer 高度优势不够明显，可以加 `CombatParams.combat_altitude_m` 字段让 archetype 显式声明（Lancer=9000, Gladiator=5000）—— 现在用 patrol_altitude 复用是最小变更。

### 回归测试要点

- **MiG-31 / F-100 vs 低空玩家**：BVR Lancer 应该明显保留高度优势打 dive 导弹
- **F-86 / MiG-23 近距狗斗**：进入机炮射程后必须 match 高度，否则机炮 500m 高度差判定（[aircraft_weapons.gd:145](scripts/aircraft/aircraft_weapons.gd:145)）会让自动开火失效
- **导弹包线**：高度差 > 5000m 时不发射，但 use_combat_altitude clamp 到 ±2500m 应该极少触发
- **HIGH_YOYO / LOW_YOYO**：phase 1 仍 match 目标高度，maneuver 几何不破
- **F-47 BOSS**：仍走 BFMTactics 路径，受同样规则影响 —— 应当观察是否仍能维持 BVR 狙击节奏
- **僚机协同**：`SquadCoordination` 走 set_patrol_altitude 没动；编队归队应不变
- **玩家飞机**（use_tactical_planner）：MISSILE intent 下保 my_alt（而不是贴目标），切换 GUN 模式才下高度 —— 验证不会出现"按导弹键时玩家自动爬升"

---

## 2026-04-26 auto_gun_scan "保护"早返冻结 lead_heading：UAV 高 bank 时持续朝侧面喷子弹

### 症状

生存模式日志 `combat_log_20260426_004909.txt` + 玩家截图：UAV-04 在 bank +86°、15g 高速旋转时，机炮持续朝一个固定的世界方向喷射子弹（机头早转过去了，子弹还往原方向飞），形成长长的弧形 tracer 残影。

### 根因

`f3a99fa` 重构（屎山拆分）时在 `aircraft/aircraft_weapons.gd:auto_gun_scan` 顶部新加了一段：

```gdscript
# 保护：已在开火 → 保持当前 _gun_lead_heading，不让扫描覆盖。
if ac.is_firing:
    return
```

这段早返在 `_auto_gun_scan_timer` 节流（行 92-95）**之前**就 return —— 一旦 `is_firing` 锁存为 true，整个 scan 永远走不到节流以下的逻辑，`_gun_lead_heading` 冻结在初次开火那帧的世界方向，`is_firing` 也不会被新一轮 scan 清掉。

aircraft 在 86° bank 下旋转速率 ~60°/s，0.3s 转过 18°，但 lead 一动不动 → 子弹方向相对机头看就是"侧射"。

`is_firing` 只在 cobra/herbst 机动 + 弹药耗尽时清，正常交战中永不重评估。

### 修复

`aircraft/aircraft_weapons.gd:auto_gun_scan`：
- 删除 `if ac.is_firing: return` 三行
- 替换为反面注释，说明为什么不能在这里早返（防止下次又有人按"保护"思路加回来）
- 顶部 comment 也补一段 2026-04-26 修复说明

行为退回到旧版 `aircraft.gd:_auto_gun_scan`（重构前）：scan 每 0.3s 重新扫描目标 + 刷新 `is_firing` + 刷新 `_gun_lead_heading`，射速节流由 `_fire_cooldown` 单独管。

### 回归测试要点

- ✅ 高 bank（>60°）追击中机炮指向应跟随机头，不残留世界方向
- ✅ 目标飞出锥外应在 0.3s 内停火
- ✅ 射速不应改变（`_fire_cooldown = 60/fire_rate` 单独节流）
- ⚠ AI 走的是行 70-73 的 `combat_target` 早返分支，不直接走扫描，但日志显示 UAV 在 `combat_target` 为空（dogfight pursuit-only）时也会落入扫描分支 → 测试要覆盖 UAV/MiG 持续 360° 缠斗

### 教训

重构时往原本能跑的逻辑上加"保护守卫"，要先确认守卫不会绕过原有节流/状态重置机制。本来 `_auto_gun_scan_timer` 已经做了 0.3s 节流，scan 重新跑一遍代价极小，再加一层 `if is_firing: return` 是无效的优化但破坏了状态自愈。

---

## 2026-04-24 (5) Rejoin "扭曲"：combat→formation bank 瞬间反转（4 rad/s 硬拉）

### 症状

修了 bug #9 的 bank-flip 守卫后，bang-bang 抖动消失，玩家反馈仍有"扭曲"感。

### 根因（10Hz 数据确诊）

`combat_log_20260424_163239` Corsair @ 43.3-43.8:
```
bank=-53° → -33° → -13° → +7° → +22°  (0.5s 内, 平均 180°/s)
dbank=+29° 全程稳定（**无振荡**）
```

desired_bank 没振荡——是从 combat 残留的 -53° 直拉到 formation 的 +29°，按 params.roll_rate
（~4 rad/s = 229°/s）硬跑，**0.4 秒完成 82° 反转**。视觉上像"僚机突然把自己拧过去"。

`_formation_blend` (b) 原本应该是 rejoin 的平滑过渡因子（0→1 over 2s），但在
`aircraft_formation.gd` 中只用在了高度和速度上，**bank/heading rate-limit 始终用原始全速率**
——所以 rejoin 瞬间 bank 以全速反转。

### 修复

`aircraft_formation.gd:update_follow` 加 rejoin 速率缩放：
```gdscript
const REJOIN_RATE_FLOOR := 0.35
var rejoin_rate_scale = lerpf(REJOIN_RATE_FLOOR, 1.0, b)
var eff_roll_rate = roll_rate_limit * rejoin_rate_scale
var eff_turn_rate = FORMATION_MAX_TURN_RATE * rejoin_rate_scale
```

b=0（rejoin 起点）→ 35% 速率 → 82° 反转需 ~1.1s（原 0.4s）
b=1（稳态）→ 100% 速率 → 旧行为完全不变

### 为什么 `0.35` 而不是更低

测过 0.2：82° 反转需 ~2s，僚机看起来"呆滞"，像飞行员犹豫。0.35 是"明显更柔和"与
"仍然反应迅速"的折中。如果后续反馈仍偏快，调到 0.25；偏慢则 0.5。

### 回归测试要点

1. **僚机击毙敌机**：bank 反转过程应比之前柔和，但仍能在 ~1s 内完成（不会拖几秒）
2. **稳态编队**（b=1）：所有速率回到 params.roll_rate / FORMATION_MAX_TURN_RATE，
   手感跟老代码一样
3. **rejoin 期间长机转向**：僚机 bank 跟随长机的速度降低，延迟感明显但不影响队形

---

## 2026-04-24 (4) Rejoin 抖动真正根因：MID 分支 bias_angle 硬钳翻转

### 症状

玩家反馈："僚机击毙了敌机以后回到阵型这个过程中会抖，在很多敌机身上包括 BOSS 都有复现。"
长期存在的 bug，多轮修复未解决。

### 先前的误诊（已撤销）

最初怀疑是 `aircraft_physics.gd:update_bank` 的 target_bank 死区阶跃不连续（hdiff=half_diff
时 0 → 0.4·max_bank 的跳变）。改了 3 处死区为二次平滑曲线。**玩家明确指出根因错了**，
已撤销所有 BFM 改动。教训：不要在没看日志的情况下先猜公式 bug。

### 真正的根因

查 `combat_log_20260424_160912.txt` Fractal 在 33.9s DISENGAGE 后的 FORM_DBG：

```
[34.1] slot_d=786 b=0.08 hdg=4→44    Δ=+41.2°  dbank=+63°  bank=+29°
[73.9] slot_d=620 b=0.09 hdg=-118→0  Δ=+120.6° dbank=+62°  bank=+7°
[75.7] slot_d=623 b=0.08 hdg=-24→0   Δ=+25.4°  dbank=+62°  bank=+62°
[76.7] slot_d=518 b=0.58 hdg=0→0     Δ=+0.3°   dbank=+1°   bank=+1°   ← 骤然归零
[82.3] slot_d=443 b=0.43 hdg=-71→-106 Δ=-36.2° dbank=-62°  bank=-62°  ← 又反向
```

rejoin 期间 target_heading 巨幅跳变（40-120°），desired_bank 贴 ±62° 上限，然后
骤然翻转。

根源在 `aircraft_formation.gd` MID 分支：
```gdscript
bias_angle = atan2(slot_local.x, LEAD_BIAS_DIST=250)
bias_angle = clampf(bias_angle, -MAX_BIAS, MAX_BIAS)  # ±60° 硬钳
target_heading = ldr.heading + jitter_heading + bias_angle
```

rejoin 时 wingman 离阵型很远，slot_local.x 绝对值大，bias_angle 经常贴到 ±60° 硬钳。
**长机转向让 slot_local.x 翻符号时，bias 从 +60° 跳到 -60°**（target_heading 瞬移 120°）
→ desired_bank 翻正负 → rate-limit 拉过去又被拉回来 → bank bang-bang 抖动。

稳态编队（b=1）没事是因为 wingman 已经贴近阵型（slot_local.x 小），bias_angle 远离
±60° 钳位，翻符号时变化平滑。

### 修复

给 `aircraft_formation.gd` 加**编队专属 bank 翻转抗振守卫**（和 `aircraft_physics.gd:260-264`
同构）：

```gdscript
const FORM_BANK_ESTABLISHED_RAD := deg_to_rad(30.0)
const FORM_BANK_COMMIT_RAD := deg_to_rad(15.0)
if absf(ac.bank_angle) > FORM_BANK_ESTABLISHED_RAD \
        and signf(desired_bank) != 0.0 \
        and signf(desired_bank) != signf(ac.bank_angle) \
        and absf(hdiff_after) < FORM_BANK_COMMIT_RAD:
    desired_bank = 0.0  # 先归零再考虑反向
```

当前 bank 已建立（|bank|>30°）且 desired_bank 要反向而 hdiff 又不够大（<15°）时，先
强制 target=0 让机翼回正，过了中立位才允许反向。给 bias 翻转加一层迟滞。

### 配套诊断改动

`FORM_DBG` 节流：rejoin 期间（b<0.95）升到 10Hz，其他时段保持 1Hz。旧的 1Hz 采样看
不见 60Hz 抖动，下次排查需要高频包络。

### 为什么这次看错了方向

BFM 目标 bank 死区阶跃确实是个 bug，但：
1. BFM 阶跃是 0 → 34° 的 step，rate-limited 后实际 bank 平滑跟进，视觉影响小
2. rejoin 的 bias 翻转是 +60° → -60° 的 120° 跳跃，差两个数量级
3. 抖动复现条件是 rejoin（即 b<1.0 + lod=1 + formation_mode=true），不是全场 BFM

今后排查前先让用户说清触发条件（"什么时候抖"），再读日志定位具体 FORM_DBG / AC_TICK
片段，不要先猜公式。

### 回归测试要点

1. **僚机击毙敌机后归队**（主要场景）：之前整段 rejoin 看得见机身左右晃，修复后应平滑
2. **长机连续硬转期间僚机归队**：bias 翻转触发 bank-flip 守卫，期间 bank 应先到 0 再翻
3. **稳态编队**（b=1）：守卫不应触发，编队手感不变
4. **导出日志**：下次出现抖动，找 FORM_DBG 条目（rejoin 期间 10Hz），看 dbank 是否频繁
   翻转符号。如果仍翻转但带 `dbank=0`（守卫介入）的过渡，说明守卫生效但仍需调阈值

---

## 2026-04-24 (3) auto_fire=OFF 锁定后自动开火（去掉"一点一发"）

### 症状

玩家反馈："导弹自动开火关闭时，每点击一次只发射一次。难道不应该锁定成功就自动发射吗？"

### 根因

2026-04-22 加的 `_missile_manual_shot_spent` 一次性额度标志把 auto_fire=OFF 做成了"半自动扳机"——每次 `set_combat_target` 重置、发射成功后置 true、下次阻塞。当初担心 2s 冷却过后 `_update_missile` 每帧跑会自动补射。

但其实已经有两层天然节流：① `_missile_cooldown = msl.cooldown`（武器内部冷却），② `count_active_missiles_at(ac, target) >= 1`（auto_fire=OFF 下 `max_inflight=1`，前一枚没打完就拦住）。把它们放在一起结果就是"发一枚 → 等命中/脱靶 → 再发"的合理节奏，不需要额外守卫。

tooltip 承诺的是"只在玩家点击敌机指定攻击时开火"——意思是**只打 combat_target，不多锁齐射**，从来没有承诺过"每次点击一发"。之前的实现误把这条读成了"每点击一次只放一发"。

### 修复（直接删代码）

移除 `aircraft.gd` 的 `_missile_manual_shot_spent` 字段 + `set_combat_target` 里的重置 + `aircraft_weapons.gd:update_missile` 里的守卫与置位。保留 auto_fire ON/OFF 的核心语义区别：

- **ON**：走 `_fire_multi_lock_salvo`，多锁齐射所有雷达锁定目标
- **OFF**：只对 `combat_target` 开火，锁定 + 冷却 + 在飞限制共同节流

### 回归测试要点

- **auto_fire=OFF 锁定远距离敌机**：到锁定时间就自动发射第一枚，命中/脱靶后自动补射，**不需要重新点目标**
- **auto_fire=OFF 同一目标连射间隔**：应该是 `max(missile.cooldown, 导弹在飞时间)` —— 测测是不是合理的节奏（不要 0.2s 一枚的连珠泡）
- **auto_fire=ON 不变**：多锁齐射路径优先级不变
- **切目标**：点别的敌机立刻切 combat_target，冷却继承（不重置），避免切目标刷冷却 exploit
- **机炮/火箭不受影响**：本次只动导弹路径

### 症状

玩家反馈："移动和攻击的积极性不一致。点地图目标点时，距离远飞机会加速，距离近就不加速，显得很奇怪。玩家点了地图就应该积极冲过去，即便可能飞过头也该保持加速。"

### 根因

`aircraft_physics.gd:update_energy_management` 巡航分支的玩家点击移动路径（原 863 行 `elif dist_to_tgt > 800.0:`）按距离分档：`> 800px` 才开 AB 冲 approach，≤ 800px 直接掉回 cruise 关 AB。

800px 阈值当初估计是想"到点就缓下来准备悬停"，但：
1. 玩家飞机 RTS 操控本来就没有悬停概念，飞过头是常态
2. 和刚修好的对空/对地导弹"未进射程也开 AB 冲"形成反差 —— 同一个玩家操作，换个触发源就变被动

### 修复（改公式）

删掉距离分档，点击移动分两档：
- 大角度转弯：corner speed + AB（帮助快速拉到 corner，而不是旧版关 AB 让速度自然掉）
- 对准后：不论距离一律 `approach_speed + AB`（`my_kmh < approach - 0` 门控防震荡）

加力门控保留旧版的 `my_kmh_cr < approach_spd` 判定，速度够高就自动关 AB 不浪费油。

### 回归测试要点

- **点 500m 近处**：应该开 AB 冲过去，不再温吞吞
- **点 10km 远处**：和原版一致 —— AB 推到 approach_speed
- **斜侧点击（大角度）**：corner speed + AB（新增 AB），应该转弯更快
- **燃油耗尽**：AB 门控有 `ac.fuel > 0.0`，耗油后自动关 AB
- **编队僚机**：`ac.formation_mode` 早已 early-return，此分支不影响编队
- **不触发对头危险**：玩家点击路径不关心 combat_target，此处无对空顾虑

---

## 2026-04-24 对地导弹模式：远距主动减速 + 关加力 bug

### 症状

玩家反馈："导弹模式准备攻击地面单位，距离还很远、目标不在雷达照射范围里，为什么要减速？难道不应该加速尽快凑到能照射的距离吗？"

日志实测（`combat_log_20260424_113528.txt`）：F-16 在 7.2km 外锁定 SAM，立刻关加力（`ab=y → ab=n`），速度从 460 m/s 一路掉到 201 m/s，同时还在 84° 压杆 11G 转弯（诱导阻力雪上加霜），之后一直贴着战斗最低速（~combat_min_kmh）缓慢推进，体感严重错乱。

### 根因

`aircraft_physics.gd:update_energy_management` 地面目标分支在 2026-04-21 (2) 分流后，导弹路径写死：

```gdscript
if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
    ac.target_speed_kmh = cruise * 0.7
    set_afterburner(ac, false)
```

无条件 `cruise × 0.7 + 关 AB`，不看距离、不看航向对准度。注释初衷是"维持照射稳定"—— 但只有 **已进入雷达有效距离** 的照射阶段才需要减速；距离外这么做就是主动自残。

对空导弹分支（同函数 v9，668 行起）已经做对了：corner speed 未对准 / cruise 超射程 / match 进射程三段式，对地分支漏了。

### 修复（改公式而不是加守卫）

对齐对空导弹的三段式结构，在 `aircraft/aircraft_physics.gd:576` 地面 MISSILE 分支内：

1. **未对准（`|hdg_diff| > 35°`）**：corner speed 获得最小转弯半径，必要时 AB 辅助快速进入最优转弯态
2. **对准但超射程（`dist > _effective_missile_range_px`）**：cruise 推进，`my_kmh < cruise − 50` 时开 AB 快速闭合
3. **对准且进射程**：恢复旧行为 `cruise × 0.7 + 关 AB`，稳定照射

为什么改公式而不是加守卫：原公式在所有距离都返回同一组速度命令，本质是公式缺了距离带判定 —— 这和对空导弹分支早就解决的问题一模一样，加守卫只会让地面分支变成"旧路径 + 新路径"更难维护，直接抄对空分支的三段式更干净。

### 回归测试要点

- **打 7km+ 远的 SAM（导弹模式）**：应该保持 `ab=y`、速度维持 cruise 附近、快速凑距离；不要像旧版一路掉到 201 m/s
- **进入雷达射程后**：应该降到 cruise × 0.7、关 AB、稳定累积锁定时间
- **大角度开火（玩家点击斜侧 SAM）**：未对准阶段应该走 corner speed（比 cruise 慢但转弯最快），不要被新分支里 `cruise` 分支覆盖
- **机炮对地不受影响**：地面 `else` 分支（机炮/火箭）逻辑未改，strafe 通场应保持 `approach_speed + AB`
- **空对地 vs 空对空**：空对空走原 668 行分支，本次改动只触 576 行地面分支

---

## 2026-04-21 (12) J-Turn 颤抖最终方案：TURN 阶段 1.0s → 1.8s（降低旋转速率到感知阈值内）

### 症状

(11) 把视觉压缩改成各向同性后用户再测：J-Turn 仍然抖，而且发现**连 "J-TURN" popup 也一起抖**。popup 用 `draw_set_transform(popup_pos, inv_rot, 1)` + `popup_pos.rotated(inv_rot)` 做双重旋转抵消，数学上 `R(ac.rotation) * R(-ac.rotation) = I`，世界坐标完美稳定 —— 但视觉上还是抖。

### 根因：Godot CanvasItem 在极快旋转下的光栅化亚像素伪影

数学抵消 = transform 层面稳定，但**光栅化到屏幕像素**是另一回事：
- 180°/秒 偏航 = 60fps 下每帧 3° 递增
- 每帧飞机 CanvasItem 的 `rotation` 变 3° → 所有 `_draw()` 内的多边形 / Rect / 文字都重新光栅化
- 多边形边的亚像素对齐、文字光栅缓存、抗锯齿羽化在每帧 3° 递增下全部**子像素跳动**
- 人眼 60Hz 感知子像素级别的像素位置跳动 = "剧烈抖动"

**这不是数学 bug，是渲染管线的物理极限**。任何 2D 游戏让物体以 3°/帧旋转都会有类似问题 —— 真实飞机不会这样偏航，游戏里也不应该。

(10)、(11) 的修复都是针对具体现象打补丁：
- (10) 标签框宽度：真 bug，已修
- (11) 图标各向异性压缩：真 bug，已修

但根本的"180°/秒超过 Godot 光栅化平滑阈值"问题，只能靠**降低旋转速率**或**改用非方向性图标**解决。

### 修复（方案 A）：TURN_DURATION 1.0s → 1.8s

[herbst_maneuver.gd:23](scripts/herbst_maneuver.gd:23)：

| 参数 | 旧 | 新 |
|---|---|---|
| TURN_DURATION | 1.0s | **1.8s** |
| 旋转速率 | 180°/秒 | **100°/秒** |
| 每帧递增 | 3° | **1.67°** |
| TOTAL_DURATION | 2.1s | **2.9s** |

1.67°/帧在 Godot CanvasItem 光栅化容限内，视觉平滑无抖。

### 为什么这个数值

2026-04-21 (8) 曾把 TURN_DURATION 从 1.6s 拉到 1.0s，原因是"太慢被玩家白嫖"。本轮 1.8s 相比当时的 1.6s 只多 0.2s —— 配合 (7) 加的**机炮 / 导弹 J-Turn 全程免疫**（bullet_manager + missile_manager 都守卫 `get_herbst().is_active`），即使偏航慢一点也不会被打死。免疫时长 `TOTAL_DURATION + POST_IMMUNITY` 自动跟随 2.9 + 0.3 = 3.2s 免疫期。

### 为什么不用方案 B（换非方向性图标）

方案 B（Herbst TURN 期间把飞机画成对称圆圈）能绕开光栅化问题，但：
- 视觉突兀（飞机突然变形成圆）
- label / popup 在飞机 CanvasItem 里仍会抖（除非也同时隐藏）
- 需要写新的 symmetric icon 渲染代码

方案 A 改一个数字解决全部问题，优先选择。

### 回归测试要点

- F-47 J-Turn：TURN 阶段 1.8s，图标平滑旋转 180°，label 和 popup 稳定
- 打 F-47 的机炮 / 导弹：在 Herbst 期间全程穿透（(7) 的免疫守卫已经保证）
- 玩家在 J-Turn 期间是否能反杀：理论上慢了 0.8s 多一些反应时间，但由于免疫机制，应该仍然打不死 —— 观察实际效果，如果用户反馈"变成活靶子"，下一步可能要重新审视免疫机制，或考虑方案 B
- Herbst 结束后的 counterattack 窗口：仍然 5s，不变

### 教训

(9-撤销) / (9) / (10) / (11) 都是在修"具体症状"，每次都以为找到了根因。真正的根因是**根本就不应该让物体以这个速度旋转** —— 这是设计问题（2026-04-21 (8) 为了对抗白嫖的调整副作用）而不是 bug。

用户的一句 **"连 popup 也抖"** 是决定性证据 —— popup 有完整的旋转数学抵消，它还抖，那就不是任何单点的 bug，而是渲染管线本身在这个速度下不稳定。

---

## 2026-04-21 (11) J-Turn 颤抖真根因：机动视觉压缩只压本地 Y 轴，heading 快速旋转时长宽比剧变

### 症状

经过 2026-04-21 (10) 的标签框宽度修复后，用户反馈 J-Turn 仍然抖，且明确指出："**问题几乎可以肯定发生在 J-Turn 行为自身上，机动本身的动作导致**"。

### 根因（通过排除法 + 用户关键观察锁定）

日志连续几份都确认 J-Turn 期间物理状态 100% 平滑（heading/position/bank 全部单调变化）。但**用户还有一条观察**：
> "当玩家导弹飞过 F-47 时，导弹也会跟着一起晃。"

导弹不是 F-47 的子节点，不共享 transform。两者唯一的视觉共同点是：**都是在快速旋转的渲染对象**。

回去再看 [aircraft_renderer.gd:draw_aircraft_icon](scripts/aircraft_renderer.gd:324) 的图标缩放逻辑：

```gdscript
var bank_compress := cos(ac.bank_angle + ac._evade_roll_phase)
var sx := base_scale * bank_compress
var sy := base_scale
# 战术机动视觉效果：俯视视角下 Y 轴压缩（模拟机头大仰角）
var _hm := ac.get_herbst()
if _hm and _hm.visual_offset > 0.0:
    sy *= lerpf(1.0, 0.4, _hm.visual_offset)   # ← 只压 sy，不压 sx
```

`sy` 是飞机**本地坐标系**的 Y 轴 = 机体纵轴（鼻尾方向）。设计意图：Herbst 期间模拟"机头大仰角"，俯视看应该沿机体纵轴被压扁。这在**静态**或慢转的情况下是物理上正确的效果。

但 J-Turn TURN 阶段 heading 以 **180°/秒** 旋转（3°/帧）。因为 sy 压缩是在 LOCAL 坐标系，**压缩方向随 heading 旋转**：
- 偏航 0°：sy 压缩方向 = 屏幕竖直 → 图标"短而宽"
- 偏航 45°：sy 压缩方向 = 屏幕 45° → 图标斜扁
- 偏航 90°：sy 压缩方向 = 屏幕水平 → 图标"高而窄"
- 每帧 3° → 图标在屏幕上的长宽比每帧剧变

人眼在 60Hz 下感知这种"形变 + 旋转"为"剧烈抖动、抽搐"。并且紧贴图标的状态框被人眼归因到"一起在抖"。

### 为什么导弹也抖

导弹图标也是有朝向的矩形（子弹+尾翼形状），`rotation = heading`。PN 制导在近距（<200m 纯追踪分支）转弯加剧，missile heading 也在高频变化。虽然 missile 没有 visual_offset 压缩，但 body 本身就是长条形（body = 10px × 2.4px），旋转时长轴方向变化 → 屏幕上的 bounding box 长宽比剧变 → 和 F-47 同样机制的"旋转中形状剧变"视觉效果。

**F-47 和导弹没有直接耦合**，只是同时处在"高速旋转非对称形状"状态，一起抖。

### 为什么只有 J-Turn 飞机抖

普通转弯 ~30°/秒 = 0.5°/帧，人眼追得上，看起来是连续平滑的旋转，bbox 长宽比变化足够慢。J-Turn 的 180°/秒（6x 正常转速）才让视觉形变超出"平滑旋转"的感官容限，显露为"抖动"。

### 修复

[aircraft_renderer.gd:331-341](scripts/aircraft_renderer.gd:331) 把 Herbst / Cobra 的 `visual_offset` 压缩改成**各向同性**（sx、sy 同时乘因子），保留"图标变小"的极端机动视觉线索，但消除长宽比变化：

```gdscript
var _hm := ac.get_herbst()
if _hm and _hm.visual_offset > 0.0:
    var f: float = lerpf(1.0, 0.4, _hm.visual_offset)
    sx *= f
    sy *= f
```

现在 Herbst 期间图标均匀缩小到 40%（顶峰时），不再变形。旋转时整个图标等比旋转，屏幕上的长宽比始终稳定。

### 代价

失去了"俯视视角下机头大仰角"的物理隐喻。但这个隐喻在 180°/秒偏航下已经失效——真实 post-stall J-Turn 没这么快。换成"图标变小 = 极端机动"的视觉语言更符合感官容限，也更通用（对 Cobra 机动同样适用）。

`afterburner_glow` 里的 `sy_compress` 保持原状（单纯用作尺度因子，没有各向异性问题）。

### 回归测试要点

- F-47 J-Turn：图标均匀缩小到 40%，平滑旋转 180°，不抖、不抽搐
- Cobra 机动（玩家）：图标均匀缩小到 35%，同样平滑，不抖
- 静态 / 慢速旋转下：视觉效果变化不大（只是图标稍小一点，但整体机动识别度保持）
- 状态框：图标稳定 → 框稳定（配合 (10) 的 `_digit_stable` 宽度修复，完整消除抖动）
- 导弹飞过：导弹自己仍会快速旋转，但 F-47 不再抖，不再给人"一起抖"的感知

### 教训

走了 4 轮才定位：
1. (9-撤) boss 搜僚机 — 误诊
2. (9) anticipated_change 软钳位 — 修了另一个真 bug（bank 4Hz 振荡），但不是 J-Turn 颤抖元凶
3. (10) 标签框宽度 `_digit_stable` — 修了另一个渲染抖动（label 宽度）但不是元凶
4. **(11) 视觉压缩各向异性 — 真元凶**

用户最后一句 **"机动本身的动作导致"** 直接逼我去看 Herbst 的**渲染层交互**，跳过了一直聚焦的"物理层抢写"和"标签层"。教训：**"渲染"不只是 label，图标的 transform 本身也会出 bug**，尤其在高速旋转 + 非对称缩放同时存在时。

---

## 2026-04-21 (10) J-Turn "抖动" 真元凶：标签框宽度每帧按文字重算

### 症状

用户反复报告 F-47 J-Turn 期间"**机身和状态框一起左右摇晃、抽搐**"，修过 Herbst 相关守卫好几轮都没消掉。本轮关键线索：**"玩家射出去的导弹飞过 F-47 时，导弹也会跟着一起晃"**。导弹不是 F-47 的子节点，也不共享 transform —— 两者唯一的视觉共同点是**都有数据标签**。

### 诊断过程

加了 Herbst 期间每帧全速采样（AC_TICK 从 10Hz → 60Hz），附加 `rot/dx/dy/cth/tp_x/tp_y/erp/erR/hv_off/cloak/alt` 共 12 个字段。抓到一个 J-Turn 完整过程（2.1s 共 126 条 tick）：**所有物理字段完全平滑** —— `hdg`/`rot` 同步 +24°→-155° 每帧 3° 单调、`dx`/`dy` 单调无一次 sign 翻转、`bnk` 单调到 0、`erp=0° erR=0` 全程、`hv_off` 平滑 0→1→0。物理层没有任何抖动 → 抖动必在渲染层。

用户进一步确认：**只有 J-Turn 那架飞机**抖，其它敌机不抖，摄像头不抖。导弹只有**经过 F-47 附近时**抖。

### 根因

[aircraft_renderer.gd:draw_data_label](scripts/aircraft_renderer.gd:727) + [missile.gd:_draw_data_label](scripts/missile.gd:223) 的标签背景框宽度计算：

```gdscript
var max_w := 0.0
for line in lines:
    var w := ac._font.get_string_size(line, ...).x
    max_w = maxf(max_w, w)
var box_w := max_w + 10.0
```

每帧按当前 `lines[]` 文字内容重新测量宽度。J-Turn TURN 阶段 `hdg` 以 **3°/帧**（180°/秒）变化，`"HDG %03d"` 每帧数字组合都不同。Godot fallback 字体是 **proportional**（不是 tabular digits），0~9 各自像素宽度略有差异 → 不同数字组合的 `max_w` 每帧波动 ±1~2 px → `box_w` 抖动 → **标签背景框每帧宽窄跳动** = "抽搐" 视觉。

**为什么只有 J-Turn 飞机抖**：普通转弯 ~30°/秒 = 0.5°/帧，连续多帧 hdg 整数值相同，文字稳定，宽度稳定。只有 J-Turn 的 3°/帧才每帧必换数字。

**为什么导弹经过 F-47 时也抖**：导弹标签同样有 `HDG %03d` + `M%.2f` + `RNG %dm/%.1fkm` 这类高频变化字段。PN 制导在接近目标时 heading 变化加剧，加上 RNG 跨 1000m 阈值切换格式 —— 标签框宽度一样跳。和 F-47 自身是否同一时刻抖无关，**只是同时都在抖**，近距离看起来像"跟着抖"。

**为什么感觉飞机图标本身也在抖**：标签紧贴图标（offset `(24, -12)` px 或 `(14, -8)` px），标签框在图标边每帧抽 1~2 px，人眼把整个组合认作同一个物体的抖动。飞机图标多边形 transform 不变（xform 只依赖平滑的 bank/hv_off），图标本身其实完全稳定。

### 修复

测量宽度前把字符串里所有数字替换成 `"0"`，保证无论当前数字是什么，测量结果一致：

[aircraft_renderer.gd:19-29](scripts/aircraft_renderer.gd:19) 新增 `_digit_stable()` helper。`draw_data_label` + `draw_data_label_minimal` 都改用 `_font.get_string_size(_digit_stable(line), ...)` 测宽度。

[missile.gd:283](scripts/missile.gd:283) 同款内联替换（missile 没 import aircraft_renderer，本地写一遍）。

**绘制的文字本身不变**，只改**测量时**的字符串。标签框宽度变成只依赖"每行字符结构 + 字母/空格部分"，不再跟数字内容联动。

### 教训：视觉抖 ≠ 物理抖

之前 2026-04-21 (5)(6)(7) 围绕"Herbst is_active 期间 AI/Combat/BankTarget 抢写 heading/position"加了 4 层守卫，修掉的是**真实物理振荡**（bang-bang bank 翻跳）。但 2026-04-21 起的新一轮"颤抖"投诉，物理层已经干净，残余视觉抖动其实是**标签渲染层的独立 bug**。

走了 3 轮猜错根因（boss 搜僚机 / anticipated_change / _evade_roll_phase）才定位。教训：**"抖"字不要自动联想到"物理抖"**，先加全字段诊断再动手。这次是用户一句"导弹飞过也抖"才戳破——不共享 transform 的两个对象同时抖，共同点只能是渲染管线里的相同代码。

### 回归测试要点

- F-47 J-Turn：标签框宽度稳定，不抽搐。图标本身（物理层一直是稳的）视觉也稳（因为标签稳）
- 玩家 F-16 / 普通敌机正常交战：heading 慢变，文字原本就稳，本改动无影响
- 导弹飞过敌机：导弹标签框不再抖
- 所有标签文字内容**显示无变化**（只是测量时用替换版本，绘制时仍用原 `line`）

### 诊断代码清理

本轮为抓 bug 加的 Herbst 全速采样 + 附加字段已撤回 `_log_ac_tick`。AC_TICK 恢复 10Hz 基础格式。未来再有"抖动"报告先用 diff 重新加回这段。

### 上轮 (9) 软钳位修复仍保留

2026-04-21 (9) 的 `anticipated_change` 软钳位修掉了另一个独立 bug：F-47 CLOSE_FIGHTER 近距咬尾时 bank 在 -79°/-85° 两档 4Hz 振荡（日志 22.7~23.6 直接可见）。那个不是 J-Turn 颤抖的元凶但也是真实 bug，保留不撤。

---

## 2026-04-21 (9) F-47 玩家阵亡后转弯颤抖（_disengage boss 搜索抓到僚机）【已撤销 — 误诊】

⚠ **此修复已撤销**。用户实测"完全没有修好，它还是在晃动、颤抖"。

撤销原因：按 `use_tactical_preference` 精确识别玩家的确切断了 _disengage 抓到僚机的路径，但并非颤抖根因 —— 撤销后行为不变，证明这条路径不是元凶。_try_engage 的 cooldown=15s 也不可能每帧刷。根因在别处（仍在诊断中），为了不把无效守卫留在 `_disengage` 里误导未来读代码，先撤回。

下一步计划：加诊断事件（每帧打 `bank_angle / _cached_target_heading / target_position / combat_target / _state`），对 F-47 Herbst 过程 + 玩家死亡后 5 秒内高频采样，看哪个字段每帧跳变，再针对真元凶修。

---

## 2026-04-21 (9) F-47 近距咬尾 bank 两档振荡（anticipated_change 硬归零）

### 症状

用户："F-47 使用 J-Turn 回转会颤抖修过好几轮了，现在又发现玩家被击坠以后它转弯也会产生剧烈的晃动。整个机身连状态栏一起左右摇晃、抽搐。"

之前修 J-Turn 颤抖围绕 Herbst is_active 期间加了 4 层守卫（AIController / _update_combat / _update_target_heading / AceSquad._maintain_role / _update_bank），但 **Herbst 并不是唯一触发点**。

### 日志证据

从 `combat_log_20260421_171637.txt` 22.7~23.6s WRAITH-02（F-47 CLOSE_FIGHTER，近距咬尾玩家）：

| 时间 | bnk | g | tp_brg | tp_d |
|---|---|---|---|---|
| 22.7 | -81° | 6.7 | -5° | 1059m |
| 22.8 | -80° | 6.3 | -4° | 1061m |
| 22.9 | -85° | 13.3 | -3° | 1059m |
| 23.0 | -84° | 11.2 | -2° | 1053m |
| 23.2 | -79° | 5.3 | -3° | 1037m |
| 23.3 | -83° | 9.3 | -3° | 1020m |
| 23.4 | -79° | 5.3 | -3° | 1003m |
| 23.5 | -83° | 9.3 | -3° | 987m |
| 23.6 | -79° | 5.3 | -3° | 971m |

bank 在 -79°/-85° 以 ~4Hz 两档切换，G 在 5.3/13.3 之间摆 —— **不是 Herbst 期间，是普通近距交战**。

同一段 log 里玩家 F-16 bank 稳定在 ±84°，毫无抖动 —— 因为走的是另一条分支（`use_tactical_preference` 阈值宽）。

### 根因：anticipated_change 反馈环 bang-bang 振荡

[aircraft.gd:867-881](scripts/aircraft.gd:867) "预测式过冲补偿"：

```gdscript
var current_turn_rate := GRAVITY * tan(bank_angle) / maxf(speed, 50.0)
var t_roll := absf(bank_angle) / maxf(rr_val, 0.5)
var anticipated_change := current_turn_rate * t_roll * 0.5
if signf(anticipated_change) == signf(heading_diff):
    if absf(anticipated_change) >= absf(heading_diff):
        heading_diff = 0.0                       # ← 罪魁：硬归零
    else:
        heading_diff -= anticipated_change
```

WRAITH-02 近距咬尾瞬态代入（bank=-85°, speed=342m/s, heading_diff ≈ -0.052 rad）：

- `current_turn_rate = 9.81 * tan(-85°) / 342 = -0.328 rad/s`
- `t_roll = 1.48 / 4.0 = 0.37s`
- `anticipated_change = -0.328 * 0.37 * 0.5 = -0.061 rad`
- `|anticipated| (0.061) > |heading_diff| (0.052)` → **heading_diff = 0**

步骤：
1. Tick N：bank=-85°，heading_diff=0 → `target_bank=0` → bank 向 0 滚，下一 tick 变 -81°
2. Tick N+1：bank=-81°，`anticipated = 9.81 * tan(-81°) / 342 * (1.41/4) * 0.5 = -0.032 rad`；`|anticipated|(0.032) < |heading_diff|(0.052)` → heading_diff 减到 -0.020 rad（保留）→ `target_bank = -max_bank * 0.475` → bank 回滚到 -85°
3. Tick N+2：回到步骤 1

**振荡频率 ≈ roll_rate 能在一个 tick 内改变 bank 多少 / 两档阈值间距**，日志里看到的 ~4Hz。

F-47 `_configure_close_fighter_combat` 把 `combat_full_bank_diff/aggression = 0.033 rad (1.9°)`，target_bank 在阈值附近近似阶跃函数，放大了振荡幅度（±6°）。玩家 F-16 走 `use_tactical_preference` 分支（阈值 0.02/0.15 rad 宽得多）+ `tactical_aggression≥0.999` 跳过 G-cap，不进振荡带。

### 为什么 J-Turn 后 + 玩家阵亡后更明显

两种场景 F-47 都处于"高 bank + 小 heading_diff"状态：
- **J-Turn 刚结束**：Herbst 释放时 bank=0（守卫强制），counterattack 窗口 AI 立刻切 LEAD_PURSUIT 朝玩家拉 bank → 快速爬到 max bank，heading_diff 小 → 进入振荡带
- **玩家阵亡后**：AI 抓到僚机（team 0 搜索）重新 ENGAGE，CLOSE_FIGHTER role 维持，近距锁敌时同样进振荡带
- **常规近距咬尾**：其实一直在抖，只是玩家在混战中没那么容易注意到单架敌机的 4Hz 小抖

### 修复

[aircraft.gd:867-881](scripts/aircraft.gd:867)：把硬归零改成软钳位，最多吃 `|heading_diff|` 的 80%：

```gdscript
if signf(anticipated_change) == signf(heading_diff):
    var cap: float = absf(heading_diff) * 0.8
    var sub: float = minf(absf(anticipated_change), cap) * signf(heading_diff)
    heading_diff -= sub
```

Tick N 同样瞬态代入：
- `cap = 0.052 * 0.8 = 0.042`
- `sub = min(0.061, 0.042) = 0.042`
- `heading_diff -= 0.042 → -0.052 + 0.042 = -0.010 rad`（保留 20% 原值）

→ 落在 `half_diff(0.0067) ~ full_diff(0.033)` 之间 → `target_bank ≈ -max * 0.5 = -43°` → bank 温和向 -43° 滚（不跳到 0）。下一 tick 在新 bank/heading_diff 下平滑迭代，不跨阈值。

### 为什么不动阈值 / 不动 anticipated_change 公式本身

- 阈值紧是 F-47 要"高激进度、最紧贴目标"的设计意图；改宽就丢了战斗力
- anticipated_change 的 critical-damping 思路是对的，2026-04-20 用它解决过"追尾 sinusoidal 摆动"问题；只是硬归零太极端。软钳位保留了补偿效果（仍然减去大部分），只是留一小段残余信号
- 改动**不影响**玩家 F-16（走不同分支）、不影响其他不进振荡带的 AI（`|anticipated| < |heading_diff|` 时两条路径行为完全一致 —— 软钳位只在"过补偿"瞬间生效）

### 回归测试要点

- F-47 近距咬尾：bank 稳在 -85° 附近单调变化，G 不再 5↔13 抖；日志 AC_TICK 连续 10 帧 bnk 差值 < 2°
- J-Turn 结束后 counterattack 5s 内：bank 从 0 单调拉回咬尾位，不抽搐
- 玩家阵亡后 F-47 转弯：同上
- 玩家自己的追尾（上轮修的 MiG-29 绕圈问题）：`use_tactical_preference` 走另一条分支，本改动不触及
- 普通 AI（MiG-29/F-86 等）BFM 机动：`|anticipated| < |heading_diff|` 场景两路径等价，无变化

### 后续诊断钩子

**已加**（2026-04-21 本轮）：Herbst 激活期间 AC_TICK 由 10Hz 升到每帧全速采样，额外输出 `rot` / `dx` / `dy` / `cth` / `tp_x` / `tp_y` ——
- `rot` vs `hdg`：若 rotation 和 heading 相差大，说明有两处在抢写 rotation
- `dx/dy`：若每帧 sign 翻转（例如 +5/-5/+5），说明 position 本身在抽
- `cth`：若 `_cached_target_heading` 抖，说明 Herbst 守卫没堵住 `_update_target_heading`
- `tp_x/tp_y`：若 target_position 每帧跳两个点，说明多系统抢写 target_position

用户重现 J-Turn 后按 F9，就能一眼看到哪个字段在抖。

**用户确认（2026-04-21）**：本轮 anticipated_change 软钳位修复**不是** J-Turn 颤抖的元凶 —— 修完后 J-Turn 依然抖。软钳位仍然是对的（日志 22.7~23.6s 的 bank 两档振荡是真实存在的 bug），但不影响 J-Turn（Herbst 激活时 `_update_bank` 整段走 `is_active` 守卫分支，根本走不到软钳位那段代码）。J-Turn 颤抖的根因尚未找到，待下一份 F9 日志（带 Herbst 期间逐帧采样）。

---

## 2026-04-21 (8) J-Turn 加速执行

用户："J-Turn 现在太慢了，根本就是活靶子。开始那段要更快结束。"

机动节奏上轮（2026-04-21 (6)）从 1.6s 拉到 3.4s 时为了"视觉清晰"步长设大了，配合 J-Turn 免疫 buff 后虽然不会被打死但观感拖沓。缩回：

| 阶段 | 上轮 | 本轮 |
|---|---|---|
| DECEL_DURATION | 1.0s | **0.5s** |
| TURN_DURATION | 1.6s | **1.0s** |
| ACCEL_DURATION | 0.8s | **0.6s** |
| TOTAL | 3.4s | **2.1s** |
| DECEL_RATE | 600 m/s² | **1400 m/s²**（DECEL 缩到 0.5s 需要更猛刹车才能到 turn_target）|

TURN_SPEED_FACTOR / ACCEL_SPEED_FACTOR 保持不变。整个 J-Turn 从"减速 → 偏航 → 加力"三段依然清晰可辨，但节奏紧凑，BOSS 快速消失-反咬。

---

## 2026-04-21 (7) F-47 J-Turn 颤抖三次修（AceSquad 漏守卫） + 机动 Buff + 隐形削弱

### 症状 + 需求

用户：
1. "J-Turn 还是会剧烈地晃动。"
2. "J-Turn 期间给它一个 buff，让它没有物理碰撞，导弹和机炮都会打空（像眼镜蛇机动）。"
3. 隐形削弱：① 延长 CD；② 不要只在被导弹瞄准时用；③ CD 到了就有可能用（全队），不依赖导弹。

### 颤抖根因（上轮 2026-04-21 (6) 漏的第四条链路）

AIController._physics_process 和 Aircraft._update_combat / _update_target_heading 都加了 Herbst 守卫，但漏了 **AceSquad._maintain_role**（[ace_squad.gd:315](scripts/survivor/ace_squad.gd:315)）—— 基类的 CLOSE_FIGHTER / RANGED_STRIKER 两个 role 分支**没有**Herbst 守卫（只有 EVADER 有）。

后果：J-Turn 执行者虽然是 EVADER（bvr_only 路径触发），但如果玩家的 `combat_target` 切到别的成员（或 EVADER 位置变化让它失去 "chased" 资格），AceSquad 会把 EVADER 重分类为 CLOSE_FIGHTER，触发：

- `_force_engage(member, ai)` — 写 `ai._state = ENGAGE` / `ai._current_target = player` / `member.combat_target = player`
- `ai.waypoints = PackedVector2Array([pp])` 每帧覆写
- `ai._apply_new_tactic(LEAD_PURSUIT)` 每帧触发（每帧 `show_tactic_popup`）
- `member.is_afterburner = true` 每帧强写

其中关键抖动源：**`ai._apply_new_tactic(LEAD_PURSUIT)` 每帧判断 `_tactic != LEAD_PURSUIT` 时才触发，但中间有其它模块写 _tactic 就会反复切换** —— 加上 AceSquad 在 Herbst 期间改 `combat_target` / `boss_attacker`，这些都影响渲染和诊断路径，视觉上表现为机身颤抖。

### 修复 A：AceSquad 全局 Herbst 守卫

[ace_squad.gd:315-322](scripts/survivor/ace_squad.gd:315) `_maintain_role` 开头加全局守卫：

```gdscript
var hm_global: HerbstManeuver = member.get_herbst()
if hm_global and hm_global.is_active:
    return
```

Herbst 激活期间任何 role 都不干预，模块独占控制权。

### 修复 B：J-Turn 物理碰撞免疫（对称 Cobra 机动）

导弹已经走 `missile_phase_timer`（Herbst activate 时设为 `TOTAL_DURATION + POST_IMMUNITY = 3.7s`），[missile_manager.gd:111](scripts/missile_manager.gd:111) 已自动覆盖。

机炮/火箭弹补：[bullet_manager.gd:102-105](scripts/bullet_manager.gd:102)：

```gdscript
var _hm_b = ac.get_herbst()
if _hm_b and _hm_b.is_active:
    continue
```

J-Turn 全程子弹穿过。机动结束 POST_IMMUNITY (0.3s) 后恢复正常碰撞。

### 修复 C：隐形系统重做

[ace_squad.gd:_update_cloak](scripts/survivor/ace_squad.gd:384)：

触发条件改为 OR：
- ① **CD 到了直接触发**（主节奏）—— 老逻辑只靠导弹紧急触发，BOSS 变成"挨打才隐形"的被动反制，威慑力弱。
- ② **导弹紧急触发**（保留）—— CD 还没转完但已经过 `CLOAK_EMERGENCY_MIN_ELAPSED`（10s）最短间隔 + 有导弹锁向任一成员时，提前触发。作为"还没到下轮 CD 但被逼急了"的应急保险。

每轮 CD = 基础周期 + 随机 jitter（`cloak_timer = cycle + randf_range(0, cycle_jitter)`），玩家无法按表躲。

[survivor_data.gd:577-580](scripts/survivor/survivor_data.gd:577)：

| 参数 | 旧 | 新 |
|---|---|---|
| F47_CLOAK_CYCLE | 95s | **110s** |
| F47_CLOAK_CYCLE_JITTER | —（新增） | **25s** |

实际周期 = 110~135s 随机，比老的 95s 固定略长，但没有拉到极端值。

### 回归测试要点

- F-47 J-Turn：三段节奏清晰（减速 1s → 低速偏航 1.6s → 加力 0.8s），机身**完全不抖**
- J-Turn 期间打它：子弹直接穿过，导弹飞过去不触发近炸引信
- J-Turn 结束 0.3s POST_IMMUNITY 后恢复正常碰撞
- 隐形触发时机：开场后 160~205s 随机首次触发，之后每轮相同分布
- 隐形和 J-Turn 独立：J-Turn 不会意外触发隐形
- 普通 AI（MiG-29 / F-86 等）没有 HerbstManeuver 组件，所有守卫 `get_herbst()` 返回 null，路径不变

---

## 2026-04-21 (6) F-47 J-Turn 颤抖二次修（AI/Combat 抢写 + 机动节奏重做）

### 症状

用户："上一轮修复没效果，还是剧烈晃动。而且能不能让 J-Turn 减速后慢慢转，不要全速维持。"

### 根因（上轮 2026-04-21 (5) 只堵了 bank，没堵 target/combat）

上轮把 `_update_bank` Herbst 守卫扩到 `is_active` —— 只压住了 bank 不翻跳。但 Herbst 激活 1.6s 内，**其它三条链路还在跟 Herbst 抢写状态**：

1. **AIController**：`_process_engage` 每 tick 跑 bvr_only 分支（[ai_controller.gd:1196](scripts/ai_controller.gd:1196)）。`hm.can_activate=false` 于是 fall through 到 `target_position = flee_dir × 3000` + `_disengage()` + boss re-engage + `_apply_new_tactic(LEAD_PURSUIT)`。每 tick `combat_target` 和 `target_position` 在「离玩家」和「对玩家」之间被覆写 2~3 次。
2. **Aircraft._update_combat**：不管 `ai_override_pursuit`，OVERSHOOT 分支（[aircraft.gd:1697](scripts/aircraft.gd:1697)）只要 `dist < 80px` 就写 `target_position = my_pos + my_fwd × 2000` 并 `is_firing = false`；机炮 lead 分支写 `_gun_lead_heading` / `is_firing`。heading 在 TURN 期间每帧硬转 3.75° → `my_fwd` 跟着转 → `target_position` 绕圈。
3. **Aircraft._update_target_heading**：每帧把 `_cached_target_heading` 按上面 1/2 写的 `target_position` 重算。

heading 被 Herbst 硬转 + `target_position` 被多处绕圈刷新，下游 `_apply_movement` 用的 heading 本身稳定，但 **`_update_visuals` 的 `rotation = heading` 和 Herbst 的 `rotation = heading` 同帧顺序打架时间窗**，再加上 position 随 heading 转圈导致 icon 绕小圈飘 —— 视觉就是"整个机身不停晃动"。

### 修复（让 Herbst 整段完全独占控制权）

**A. AI 在 Herbst 激活期间完全停摆** —— [ai_controller.gd:381-390](scripts/ai_controller.gd:381) `_physics_process` 开头：

```gdscript
var _hm_ai := aircraft.get_herbst()
if _hm_ai and _hm_ai.is_active:
    return
```

Herbst 自带 1.6s 时长 + 5s counterattack 窗口，期间不需要任何 AI 决策。机动结束立刻恢复。

**B. Aircraft._update_combat 整段跳过** —— [aircraft.gd:1639](scripts/aircraft.gd:1639)：

```gdscript
var _hm_uc := get_herbst()
if _hm_uc and _hm_uc.is_active:
    is_firing = false
    return
```

OVERSHOOT / lead / 机炮 firing 全部停，不再写 `target_position` / `_gun_lead_heading` / `is_firing`。

**C. Aircraft._update_target_heading 冻结** —— [aircraft.gd:770](scripts/aircraft.gd:770)：

```gdscript
var _hm_th := get_herbst()
if _hm_th and _hm_th.is_active:
    return
```

不再根据旧 target_position 刷新 `_cached_target_heading`。

**D. Herbst 自己写稳定的 target_position** —— 各阶段都把 `target_position = global_position + fwd × 2000`，并同步 `target_speed_kmh`，防止 Aircraft `_update_speed` 反向抬升。

### 机动节奏重做（用户要求的"减速后慢慢转"）

[herbst_maneuver.gd:12-22](scripts/herbst_maneuver.gd:12)：

| 参数 | 旧值 | 新值 | 说明 |
|---|---|---|---|
| DECEL_DURATION | 0.3s | **1.0s** | 玩家能看到减速 |
| TURN_DURATION | 0.8s | **1.6s** | 低速偏航，像失速机动而不是急转 |
| ACCEL_DURATION | 0.5s | **0.8s** | 从近失速平缓拉回巡航 |
| TOTAL | 1.6s | **3.4s** | |
| DECEL_RATE | 300 m/s² | **600 m/s²** | DECEL 1s 内真的要能刹到近失速 |
| TURN 目标速度 | `corner × 0.8` | **`stall_base × 1.15`**（TURN_SPEED_FACTOR）| 近失速，观感像推力矢量低速偏航 |

- DECEL / TURN 阶段 `is_afterburner=false` + `target_speed_kmh=turn_target × 3.6`，彻底压住 `_update_speed` 反向加速。
- TURN 阶段 `speed = turn_target_ms` 双向钳制（不是 `maxf`），速度严格稳定在近失速值。
- ACCEL 阶段 `is_afterburner=true` + `target_speed_kmh = cruise_speed`，让 `_update_speed` 自然拉回。起始 tick `minf(speed, stall_base × 1.4)` 防止一帧从 stall×1.15 暴涨。

F-47 实际效果（`stall_base=180 km/h`）：
- DECEL 1.0s：从 2000 km/h → 约 207 km/h
- TURN 1.6s：定速 207 km/h 偏航 180°
- ACCEL 0.8s：加力从 207 → 巡航 1600 km/h

### 为什么不直接在 heading 上加守卫？

`_update_heading` 早在 04-20 就已经用 `is_active` 跳过了；`_update_bank` 在 04-21 (5) 用 `is_active` 压到 0。剩下的抖动源是**别处在写 heading 的输入信号（target_position）和下游状态（combat_target / is_firing）**。必须从源头切断：让 Herbst 激活期间没有任何别的逻辑能写这些字段。

### 回归测试要点

- F-47 BOSS J-Turn：视觉三段清晰 —— 减速（1s，speed 曲线明显下降）→ 低速偏航 180°（1.6s，icon 绕自身缓慢旋转）→ 加力冲出（0.8s，speed 拉回巡航）
- 机身不再颤抖（bank=0 全程 + target/combat 不抢写）
- Herbst 结束立即进入 5s counterattack 窗口，AI 恢复，BOSS 开始反咬玩家
- 普通 AI 机动不受影响（`is_active=false` 时所有守卫都不触发）
- 玩家飞机不涉及 Herbst，路径不变

---

## 2026-04-21 (5) F-47 J-Turn 颤抖回潮（04-20 (9) 覆盖不全）

### 症状

用户："Boss F47 在使用 J-turn 的时候，飞机会剧烈颤抖。之前似乎修过一次。整个机身会不停地晃动，肯定有什么逻辑在打架。"

### 根因

04-20 (9) 的 `_update_bank` Herbst 守卫**只 match `Phase.TURN`**，DECEL（0.3s）和 ACCEL（0.5s）两段没覆盖。

闭环：
1. Herbst 整个 1.6s 内 `is_active=true` → `_update_heading` 被跳过，heading 在 DECEL/ACCEL 期间冻结（TURN 期间由 herbst 自己硬转）。
2. 与此同时 AI `_process_engage` 每 tick 继续跑 bvr_only 分支（[ai_controller.gd:1196-1220](scripts/ai_controller.gd:1196)）。herbst 已激活 → `hm.can_activate=false` → fall through 到 `target_position = flee_dir × 3000` + `_disengage()`。`_disengage()` 对 boss 立即 re-engage + `_apply_new_tactic(LEAD_PURSUIT)`（[ai_controller.gd:2164-2184](scripts/ai_controller.gd:2164)）。
3. 结果 `target_position` 每 tick 在「背离玩家的 flee 点」和「对准玩家的 pursuit 点」之间反复跳 → target_heading 跳 ±180°。
4. DECEL/ACCEL 期间 `_update_bank` 正常跑但 heading 冻结，反馈环失效：heading_diff 始终是 ±180° 级，target_bank 在 `±max_bank` 翻跳。bank_flip 守卫（2026-04-20 (7)）只在 `|bank|>30°` 生效，小 bank 时直接放行翻转。
5. 渲染层 [aircraft_renderer.gd:296](scripts/aircraft_renderer.gd:296) `bank_compress = cos(bank_angle)` → bank 抖 → icon X 轴宽度被反复压扁 → **视觉机身颤抖**。

### 修复

[aircraft.gd:799-802](scripts/aircraft.gd:799) 守卫从 `phase == Phase.TURN` 扩到 `is_active`：

```gdscript
var _hm_bank := get_herbst()
if _hm_bank and _hm_bank.is_active:
    var roll_rate_herbst: float = params.roll_rate if params else 4.0
    bank_angle = move_toward(bank_angle, 0.0, roll_rate_herbst * delta)
    return
```

Herbst 全程放平机翼。符合真实 post-stall J-Turn 的动作（全程 wings-level，只绕 yaw 轴）。视觉转身感由 `HerbstManeuver.visual_offset` 的俯视 Y 轴压缩负责。

### 为什么不直接修 AI bvr_only 闭环

AI 侧是设计意图（持续刷新 target_position 保证 boss 始终追玩家）。真正的责任边界是：**Herbst 激活时 bank 不该由 target_position 驱动**。在 `_update_bank` 源头守卫一次，所有上游波动都不会再影响视觉。

### 回归测试要点

- F-47 BOSS 多次 J-Turn：DECEL / TURN / ACCEL 三段 `bnk` AC_TICK 值应平滑降到 0，不再翻跳
- J-Turn 结束进入 counterattack 5s 窗口后 bank 恢复正常 P 控制（不影响）
- 非 Herbst 的普通高 G 机动不受影响（`is_active=false` 时守卫不触发）

---

## 2026-04-21 (4) 导弹对地一击必杀 + 补 AGM 升级遗漏

### 症状

用户："AGM 打在地面单位上，地面单位没死。所有的导弹，无论类型，打到地面单位就应该死。"

### 根因

1. **HP 缩放吃光弹头威力**：`survivor_data.gd:ground_tgt_scale` 给 SAM/AAA 加 `hp_mult = 1 + 0.1×(level-1) + 0.2×(diff-1)`（cap ×3）。5 级 + 2 星 → SAM HP = 80 × 1.6 = 128。AGM 80 damage 打不穿，需要 2 发。
2. **AGM 升级覆盖审计发现一处遗漏**：`seeker_fov`（广角导引头）升级只改 `p.missile`，不改 `p.secondary_missile`。AGM 是 AAM 的 `duplicate()` 克隆，设计上所有升级都该同步覆盖，其它升级（`missile_count` / `missile_tracking` / `missile_reload` / `proximity_fuze` / `missile_bounce` / `multi_lock`）都已正确同步，唯独 seeker_fov 漏了。

日志证据（`logs/combat_log_20260421_132219.txt`）：
- `[102.9] AGM-65: hit @Node2D@385 (dmg=80)` —— 伤害打进去
- `[103.9] PURSUIT_ACQUIRE tgt=@Node2D@385` —— 1 秒后 SAM 还活着被重新锁定
- `[109.7] THREAT ... @Node2D@385 LOCKED=23.5/3.5s @541m` —— 7 秒后仍可被锁定（combat_target 有效 = 未 destroyed）
- GroundUnit.take_damage 没有 EventLogger 记录，所以看不到 DAMAGE 事件（现象上"静默"）

### 修复

**1. 新增 `GroundUnit.take_missile_damage(amount)`**（[ground_unit.gd](scripts/ground_unit.gd)）：
```gdscript
func take_missile_damage(_amount: float) -> void:
    if is_destroyed:
        return
    hp = 0.0
    _start_destroy()
```
伤害值被忽略 —— 任何战斗部命中 = 秒杀，无视 HP 缩放。

**2. missile_manager 对 GroundUnit 走新路径**（[missile_manager.gd](scripts/missile_manager.gd)）：
- 直接命中分支（:139）：`if unit is GroundUnit: take_missile_damage() else: take_damage()`
- 近炸 AOE 分支（:225）：同样分流

**3. seeker_fov 升级补齐 AGM**（[survivor_player.gd:170](scripts/survivor/survivor_player.gd:170)）：同时对 `p.missile` 和 `p.secondary_missile` 放大 seeker_fov。

### 设计原则

- **地面单位 vs 导弹**：软目标，任何战斗部一击必杀。难度压力来自 garrison 的数量（`sam_count` 2/3/5）和编组，不是 HP 耗损。
- **地面单位 vs 机炮**：保留原 HP 系统（`take_damage`），机炮扫射仍要持续射击才能打死。
- **地面单位 vs 地面单位（比如友方卡车被敌方 AA 打）**：保留原 HP 系统，走 `take_damage`（非制导，不算战斗部）。
- **AGM = AAM 包装**：survival 模式 `secondary_missile = missile.duplicate()`，所有导弹升级都该覆盖两份。

### 回归测试要点

- **任意等级打 SAM/AAA/雷达站**：AGM 一发击毁，不需要连发
- **AIM-7M 打空中目标**：不走 GroundUnit 路径，HP 系统正常（一发可能打残不打死，设计如此）
- **近炸引信 AOE 扫过地面单位**：SAM/AAA 被 AOE 命中也应该秒杀
- **广角导引头升级**：AGM 的 seeker_fov 也应该变宽（对地大离轴发射应该更容易锁定）
- **机炮扫射 SAM**：仍然需要多发（原逻辑不变）

---

## 2026-04-21 (3) AGM 对地发射 bug：武器模式切换用了错误的导弹 min_range

### 症状

用户："导弹模式下锁定地面单位，慢慢锁定以后没发射导弹；靠近以后使用了机炮，明明有 AGM 可以发射。"

### 根因

`aircraft.gd:_missile_cannot_hit_but_gun_can()` 判断"距离是否进入导弹 min_range"时**固定读 `params.missile.min_range`（AAM = 500m）**，但对地目标实际要发射的是 `params.secondary_missile`（AGM-65，min_range = 300m）。

触发链：
1. 玩家靠近 SAM 到 ~400m —— AGM 可打（>300m）、AAM 不能打（<500m）
2. `_missile_cannot_hit_but_gun_can` 用 AAM 500m 判 → 500>400 → 返回 true
3. `_update_weapon_mode_tactical` 把 `weapon_mode` 切到 GUN
4. 滞回 +150m（`WEAPON_MODE_HYSTERESIS_M`）→ 除非拉到 650m 外才切回，strafe 通场中不会发生
5. `_update_missile` 首行 `if weapon_mode != MISSILE: return` 直接出 → **AGM 从没获得发射机会**

日志证据（`logs/combat_log_20260421_131248.txt`）：
- `[84.3] PURSUIT_ACQUIRE tgt=SAMUnit wpn=GUN` —— 锁定 SAM 的瞬间 weapon_mode 已被切到 GUN
- 84.3→94.3s 的 10 秒 SAM 交战期间**零 MSL_BLOCK 事件**（`WEAPON_MODE` 节流间隔 2s，最少应该出 5 条）—— 说明根本没走到带 log 的发射分支
- 相比之下对 UCAV-06 正常发射了 AGM（:3069）—— 那次走的是另一个对空路径

### 修复

`_missile_cannot_hit_but_gun_can()` 按目标类型选择 `effective_missile`，与 `_update_missile` 的导弹选择逻辑保持一致：
- 地面目标 → `secondary_missile` 优先（AGM）
- 空中目标 → `missile`（AAM）
- 无可用弹 → fallback 到另一个或 return true（机炮兜底）

然后用 `effective_missile.min_range` 替代硬编码的 `params.missile.min_range` 做距离判据。

### 关联文件（同步检查）

以下位置也区分了"对空/对地用哪个导弹"，已确认与新 `effective_missile` 选择逻辑一致：
- `_update_missile` [aircraft.gd:2819-2832](scripts/aircraft.gd:2819)：msl 选择（ground → secondary）
- `_update_weapon_mode` AI 分支 [aircraft.gd:2503-2509](scripts/aircraft.gd:2503)：usable_missiles 计数（ground = AAM+AGM）

### 回归测试要点

- **导弹模式接近 SAM/AAA/雷达站**：应该在 ~300m 内才切 GUN（而不是 500m），AGM 能正常发射
- **对空 UCAV 近战**：仍然用 AAM 500m 判据切 GUN（不应被误改）
- **AGM 打完**：`secondary_missiles_remaining == 0` 时 `effective_missile` fallback 到 AAM，恢复旧行为
- **MSL_BLOCK 日志**：发射失败时应该看到明确 reason（`ENVELOPE` / `LOCK` / `OFF_CONE`），而不是静默消失
- **玩家切机炮优先 (PREFER_GUN)**：早期 return 优先生效，本修复不影响

---

## 2026-04-21 (2) 机炮对地攻击：加力低空掠袭（不再减速照射）

### 症状

用户："机炮模式攻击地面单位时，不应该像发射导弹那样慢慢减速，而是应该加力快速飞过地面单位进行一波攻击。飞行高度应尽可能往低，匹配目标高度。"

### 根因

`aircraft.gd:_update_energy_management` 的地面攻击分支一刀切：
```gdscript
if combat_target is GroundUnit:
    target_speed_kmh = cruise * 0.7
    _set_afterburner(false)
    return
```
不管机炮还是导弹都 cruise×0.7 + 关加力。这对导弹模式合理（维持照射），但机炮 strafe 通场时等于主动降速把自己挂在 AAA/SAM 火控里。

另外 `STRAFE_ATTACK_ALT_M = 1500m` 对掠袭来说太高，远离"贴地攻击"的直观感受。

### 修复

**1. 按武器模式分流**（`aircraft.gd:_update_energy_management` 地面分支）：
- 机炮/火箭：`target_speed_kmh = cruise × approach_speed_mult`（默认 1.4×）+ 加力（my_kmh 不足时）
- 导弹：保持 cruise×0.7 关加力（照射稳定）

**2. 降低 strafe 攻击高度**：
- `STRAFE_ATTACK_ALT_M`: 1500m → **500m**（脱离高度 3000m 不变）

### 覆盖范围

- `_update_combat_ground_attack` 只在 `weapon_mode != MISSILE` 时调用（`aircraft.gd:1569`），
  所以 strafe 状态机天然是机炮/火箭路径。新加的武器模式分流只影响 `_update_energy_management` 的对地速度命令。
- 火箭模式与机炮同路径处理（都是近距直射）。

### 回归测试要点

- **打 SAM/AAA**：玩家应该加力冲向目标、低空掠过、脱离时爬升到 3000m
- **打 SAM（带导弹且玩家选择导弹模式）**：应该保持 cruise×0.7、不开加力、维持照射
- **空对空不受影响**：`combat_target is GroundUnit` 门控，空中目标走原路径
- **低空危险**：500m 对俯冲/失速有风险，注意 AC_TICK 日志看 `spd` 是否掉到失速附近；如果频繁坠地可以把地板抬到 700m

---

## 2026-04-21 机炮慢目标分两态：咬尾匹配速度 / 剪式压到角点

### 症状

用户："玩家攻击 UAV 的时候经常会飞过。在和敌人进行剪式飞行的时候，它会加速而不是减速；等敌人飞向它的前面时，它一直在加速飞过敌人，表现出一种找不到角度的样子。"

### 根因

`aircraft.gd` 的机炮模式能量管理分支里，`is_slow_target` 一刀切命令 `maneuver_speed = cruise × 1.0 ≈ 900 km/h`，不管玩家是咬在 UAV 屁股后还是对头剪式，都强制 cruise。

- 2f93ee4 当时的注释解释："不再进一步降速到 tgt×1.3 —— 太慢会导致 G-lim 过低，转弯半径极大，反而被动等待目标经过"
- 问题是对**所有慢目标场景**都这么处理，对头/剪式时根本不该维持高速 —— 该情形要压速换小半径拉反转咬尾

UAV 150 km/h vs 玩家 900 km/h，相对速度 750，穿过目标瞬间完成，玩家根本没机会开火也没机会打剪式反转。

### 修复

`aircraft.gd` 机炮分支按 BFM 分两态：

```gdscript
if is_slow_target:
    var tail_aligned := _in_rear_hemisphere and heading_diff_deg < 30.0
    if tail_aligned:
        # A. 已咬尾：目标速度 × 1.2，保持射程稳定射击
        target_speed_kmh = maxf(combat_min_kmh, tgt_speed_kmh * 1.2)
    else:
        # B. 对头/横切/剪式：角点速度，最小转弯半径拉 180° 反咬
        target_speed_kmh = _corner_speed_kmh()
    _set_afterburner(false)
```

### 设计约束：全派生，不硬编码

公式里所有速度/距离都从当前 params 派生，**玩家升级自动生效**：
- `combat_min_kmh = stall × 1.8` ← 失速降低升级
- `_corner_speed_kmh() = stall × 1.2 × √G_limit` ← 结构 G 升级
- `gun_range` ← 机炮射程升级
- `tgt_speed × 1.2`、`30°` 是 BFM 几何常量，与机型/升级无关

### 回归测试要点

- **UAV/直升机近战**：玩家应该能咬住 UAV 并持续命中（原症状修复）
- **剪式/对头 UAV**：玩家应该减速而不是加速，穿过后立刻反转咬尾
- **快目标（MiG/F-100 等）**：`is_slow_target=false`，走原 `_in_rear_hemisphere` / `needs_big_turn` 分支，不应有任何变化
- **升级后**：`.tres` 调低 stall 或调高 G，追慢目标时速度档位应该相应下移（对头更激进的小圈）
- **观察** AC_TICK 诊断：剪式场景下 `spd` 应该明显低于之前（接近 corner_speed，如 F-16 约 780 km/h 而不是 cruise 900）

---

## 2026-04-20 (11) 修 LOD 2 → LOD 0 回切遗漏（label 不更新 + 跟飞机转）

### 症状

用户："状态栏都不更新，而且只是挂在那里，跟着飞机一起旋转。"

截图里多架敌机（MiG-31、F-47 BOSS 全队、MiG-23、A-7 等）的 status label 都呈 45° 倾斜状态，且数据停留在离屏瞬间的值（HDG / spd / RNG / FLR 不变化）。

### 根因

[survivor_mode.gd:_update_enemy_lod:738](scripts/survivor/survivor_mode.gd:738) 里：

```gdscript
if offscreen:
    ac.lod_level = 2          # ← 离屏设 2
    ...
    continue

# 屏幕内
ac.visible = true
# BOSS 之类关键目标强制全速，不参与预算排队
var is_critical: bool = ac.has_meta("category") and ac.get_meta("category") == "boss"
if is_critical or not (ai_node and ai_node.simple_ai):
    ac.set_physics_process(true)
    ...
    continue
# ← 从头到尾没有 ac.lod_level = 0！
```

当敌机从离屏回屏幕内时 `lod_level` **永远卡在 2**。Aircraft 进了 LOD 2 分支后：

1. [`queue_redraw()`](scripts/aircraft.gd:411) 只在 `selected and combat_target != null` 时调用 —— 普通敌机几乎不触发 → `_draw` 很少跑 → **label 数据停留在上次绘制时的瞬间**
2. label 用 `inv_rot = -ac.rotation` 反补偿使其看起来正向。`_update_visuals()` 里 `rotation = heading` 是 LOD 2 tick 帧才更新（2026-04-20 (10) 修的是这个）。但 label 只有在 `_draw` 被调用时才重新计算 inv_rot —— 由于 _draw 极少被调用，inv_rot 也停留在过时值，导致 label 倾斜
3. LOD 2 内部 `delta * 3` 用于补偿跳过的 2 帧 —— 但屏幕内已经每帧都跑，继续用 3× delta 意味着物理以 3 倍速度跑，转向等行为过激

### 修复（[survivor_mode.gd:755-767](scripts/survivor/survivor_mode.gd:755)）

屏幕内分支开头加 `ac.lod_level = 0`，不管是 BOSS、全功能 AI 还是 simple_ai 都统一走完整 LOD 0 路径。

```gdscript
ac.visible = true
ac.lod_level = 0              # ← 新增：从离屏回屏幕内时必须重置
var is_critical: bool = ...
if is_critical or not (ai_node and ai_node.simple_ai):
    ac.set_physics_process(true)
    ...
    continue
simple_enemies.append({...})  # simple_ai 仍然走预算节流池
```

### 为什么友军 LOD 切换没这个 bug

[survivor_mode.gd:_update_friendly_squad_lod:774](scripts/survivor/survivor_mode.gd:774) 写得对，每次都**无条件重算** lod_level：

```gdscript
if offscreen:
    ac.lod_level = 2
elif ac.combat_target != null:
    ac.lod_level = 0
else:
    ac.lod_level = 1
```

所以友军从离屏到屏幕内会正确降回 0 / 1。而敌军的 `_update_enemy_lod` 是"不同分支做不同的事"的结构，离屏分支把 `lod_level=2` 塞进去，屏幕内分支却只改 `visible`/`set_physics_process` 没管 `lod_level`，是遗漏。

### 回归测试

镜头从战斗区拖出，看到一架敌机从屏幕边缘进入屏幕：
- label 数据（HDG/spd/RNG/FLR）应该实时更新，不再冻结
- label 保持正向显示，不随飞机转
- 飞机物理动作正常，不会因为 LOD 2 的 delta*3 在屏幕内继续跑造成转向过激

### 本轮总结

| 轮次 | 改动 | 结果 |
|------|------|------|
| 2026-04-20 (8) | 把敌机从 set_physics_process(1/3) 切到 lod_level=2 机制 | 引入 LOD 2 多个盲区 bug |
| 2026-04-20 (10) | 加 `rotation=heading` 每帧 + full-update 用 `delta*3` | 修了一部分但 LOD 2 在屏幕内还继续跑 |
| 2026-04-20 (11) | 屏幕内分支强制 `lod_level = 0` | 修好 LOD 切换链路最后一环 |

---

## 2026-04-20 (10) 修正 2026-04-20 (8) LOD 2 的两个致命遗漏

### 症状（我上一轮 LOD 2 修复仍有问题）

用户："你之前的所有修复似乎几乎没有任何实质效果，而且让问题变得更严重了。"
1a. 几乎所有飞机使用 J-Turn 时，状态图标和状态栏**完全反转**
1b. 视角切回后飞机**倒着飞、斜着飞，各种不自然姿态**
1c. 用户自己猜测："可能是画面外渲染被停止，切回来不同步"
2. **4 架 BOSS 全部飞得离玩家非常远**，基本不回头

### 根因 1（visuals 不同步 → 1a + 1b）

上一轮 LOD 2 修复把离屏敌机切到 `lod_level=2` 让 Aircraft 的 LOD 2 内部分支（[aircraft.gd:404-433](scripts/aircraft.gd:404)）处理节流。但 LOD 2 分支**从头到尾没调用 `_update_visuals()`**。

`_update_visuals()` 的唯一职责就是 `rotation = heading`。这是节点视觉旋转，决定：
- 图标朝向
- label 用 `inv_rot = -rotation` 反补偿让自己正向显示

结果：
- LOD 2 下 `heading` 每 3 帧更新一次（full-update），但 `rotation` **永远冻结**在刚离屏时的值
- Herbst J-Turn 期间 heading 被 Herbst 每帧 +3°/frame 硬转，rotation 完全跟不上 → **图标和状态栏完全反转**
- 镜头切回来时，看到飞机图标指向一个过时的朝向，和 HDG 读数不符 → **斜着飞、倒着飞**

### 根因 2（attitude 1/3 速率 → Bug 2）

LOD 2 full-update 分支用 `delta = 1/60`（单帧 delta）调用 `_update_heading / _update_bank / _update_speed` 等。但实际已经过去了 3 帧 —— attitude 只更新了 1 帧份的物理。

结果：
- 位置每帧都跑 `_apply_movement(delta)` → 移动 100% 正常速度 ✓
- 但 **转弯、加速、bank 响应只有 1/3 真实速率**
- BOSS 在 LEAD_PURSUIT 但转弯慢 3 倍 → 跟不上玩家机动 → 越飞越远
- 从 log 看 ACE-01 在 ~t=40s 从 d=837m 被我方推远到 d=18725m（19km！），100 秒后才 d=523m 回到近距

### 修复（两处，[aircraft.gd:404-438](scripts/aircraft.gd:404)）

**Fix 1：`rotation = heading` 每帧同步**

```gdscript
if _lod_frame % 3 != 0:
    _apply_movement(delta)
    rotation = heading   # ← 新增
    ...
    return
```

LOD 2 非 tick 帧也同步 rotation，成本是 1 次赋值，可忽略。保证镜头切回来看到的图标朝向与 HDG 读数一致。

**Fix 2：full-update 用 `delta * 3`**

```gdscript
var lod_delta: float = delta * 3.0
_update_combat(lod_delta)
_update_bank(lod_delta)
_update_heading(lod_delta)
_update_speed(lod_delta)
_update_altitude(lod_delta)
_update_fuel(lod_delta)
...
_apply_movement(delta)   # 位置保持单帧，前 2 帧已各 apply 一次
```

Attitude 类函数用 `lod_delta = delta * 3` 补偿跳过的 2 帧，aircraft 转弯/加速/bank 响应以真实速率跑。`_apply_movement` 保持 `delta` 因为它每帧都跑（累计 3 × delta 不变）。与 [AIController 的 `ai_tick_divisor` delta 放大](scripts/ai_controller.gd:384) 思路一致。

### 为什么 `delta * 3` 不导致精度问题

- 典型 delta = 1/60 ≈ 0.0167s，× 3 = 0.05s
- `_update_bank` 里 `bank_angle += clamp(bank_diff, -rate*delta, rate*delta)` — 最大滚转量 3 倍，等同连续 3 帧滚转，总量一致
- `_update_heading` 里 `heading += turn_rate * delta` — 等同 3 帧累加转向
- `_update_speed` 里 `speed += accel * delta` — 有少许精度差（非线性 drag），但 50ms 级积分误差可忽略
- 不是连续积分敏感的系统，离散 50ms 步长和 16.7ms 步长结果差别 <1%

### 回归测试要点

镜头拖出战斗核心区后再拖回来：
- **图标朝向**：应与 `HDG` 标签读数一致（以前是冻结在离屏瞬间的朝向）
- **status label**：文字正向显示，不反转
- **Herbst J-Turn**：DECEL/TURN/ACCEL 全程图标跟随 HDG 变化平滑旋转
- **BOSS 闭合**：离屏 BOSS 追击玩家时 d 应该稳定下降，不再出现 d 从 800m → 19km 的失控拉远
- **zigzag 尾迹**：screenshot 2 的锯齿尾迹现象应消失（trail 刷新频率不变但 heading 响应恢复）

### 为什么之前 LOD 2 从来没出过这些问题

因为**之前根本没有敌机进 LOD 2**。LOD 2 是为友军僚机设计的（[survivor_mode.gd:_update_friendly_squad_lod](scripts/survivor/survivor_mode.gd:774) 对 team==0 生效）。敌机走的是 [_update_enemy_lod](scripts/survivor/survivor_mode.gd:_update_enemy_lod) 的 `set_physics_process(frames % 3 == 0)` 路径 —— 那个有 1/3 速度 bug 但没触发 LOD 2 的视觉/delta 问题。

上一轮把敌机切到 LOD 2 路径才触发了这两个**早就存在但从未被测到的 bug**。

### 这一轮做的事情总结

| 轮次 | 目标 | 结果 |
|------|------|------|
| 2026-04-20 (8) Fix A | 修离屏 1/3 速度 | 引入 visuals 不同步（1a/1b）+ attitude 1/3 速率（2）|
| 2026-04-20 (10) Fix 1 | 修 visuals 不同步 | 已修，rotation 每帧同步 |
| 2026-04-20 (10) Fix 2 | 修 attitude 1/3 速率 | 已修，full-update 用 delta*3 |

---

## 2026-04-20 (9) 修正 2026-04-20 (8) 的 Herbst 冻结 bank 副作用

### 症状（我上一轮的修法引入的新 bug）

用户："你修出了更严重的 bug。飞机 J-Turn 以后，图标会跟着一起转；飞机斜着飞，图标 bug。"

### 根因（2026-04-20 (8) 的 Herbst TURN 守卫策略错误）

上一轮为了消除 Herbst TURN 期间 bank 翻转振荡，直接 `return` 让 `_update_bank` 跳过 —— 但这等于**冻结 bank**：

- 进 TURN 时 bank 可能 ±70°~±85°（刚从 DECEL 出来，DECEL 只有 0.3s 来不及把大 bank 滚回 0）
- TURN 阶段 0.8s 冻结 ±85°
- ACCEL 阶段 0.5s 虽然 `_update_bank` 恢复但 bank_flip 守卫（2026-04-20 (7)）在 bank=±85° 时要求 |heading_diff|>5° 才放行反向，heading_diff ≈ 0 时把 target_bank 设 0 → bank 滚回 0 但 0.5s × 4 rad/s = 115°，勉强够但不稳
- 退出 Herbst 后若 AI 立刻设新 target_position 导致 heading_diff 再次非零，bank 可能在高位持续

**视觉 bug 机制**：[aircraft_renderer.gd:296](scripts/aircraft_renderer.gd:296) `bank_compress = cos(bank_angle + _evade_roll_phase)` 把 icon X 轴按 `cos(bank)` 压缩：
- bank=0°: sx = 1.0（正常圆滑俯视图）
- bank=85°: sx = 0.087（X 轴压到 8.7%，icon 看起来是细长斜线）
- rotation=heading 照常应用，压扁后的 icon 再转到 heading 方向 → 看起来就是"斜着画的 F-47"

### 正确修复

TURN 阶段不应该冻结 bank，而是**强制 bank 衰减到 0**。真实 F-18 post-stall yaw J-Turn 就是**放平机翼**（roll=0）纯绕 yaw 轴旋转，视觉上的"转身"感由 [HerbstManeuver.visual_offset](scripts/herbst_maneuver.gd:99) 的俯视扁平化处理。

[aircraft.gd:752-767](scripts/aircraft.gd:752) 改为：

```gdscript
var _hm_bank := get_herbst()
if _hm_bank and _hm_bank.phase == HerbstManeuver.Phase.TURN:
    var roll_rate_herbst: float = params.roll_rate if params else 4.0
    bank_angle = move_toward(bank_angle, 0.0, roll_rate_herbst * delta)
    return
```

- 进 TURN 时 bank 是 ±85° → 一帧滚 `4 rad/s × 1/60 = 0.067 rad = 3.8°` → 22 帧 ≈ 0.37s 归零
- TURN 阶段剩下的 0.4+s 维持 bank=0 稳定
- ACCEL 进入时 bank=0，bank_flip 守卫不触发（当前 bank < 30°），target_bank 自然跟 heading_diff 走
- 不再有 icon 压扁伪装问题

### 为什么"衰减到 0" 而不是"瞬间置 0"

瞬间置 0 会产生可见的"机翼啪一下放平"的突变（ACCEL/DECEL 前后对比突兀）。用 `move_toward` 按 `roll_rate` 平滑过渡 —— 和正常 bank 控制相同的物理上限，视觉自然。

### 回归测试要点

- F-47 BOSS 多次 Herbst J-Turn：TURN 阶段 AC_TICK 中 `bnk` 应从入场值快速（~0.4s）滚到 0 然后维持
- 非 Herbst 的普通机动：不受此路径影响（普通 _update_bank 照常跑）
- DECEL 和 ACCEL：两端仍然走正常 `_update_bank`，只有 TURN 特殊处理

---

## 2026-04-20 (8) 修两个关键 bug：离屏 1/3 速度 + Herbst TURN 阶段颤抖

### 症状

用户：
1. "我不拖动镜头去观察飞机，飞机就不会动。它在画面外好像被冷冻、卡死了一样，时间仿佛是停止的。"
2. "飞机在做 J-turn 的时候还是没有修复好，依然会剧烈颤动。不过现在这种情况仅限于做 J-turn 的时候。"

### Bug A：离屏敌机按 1/3 速度运行（解释之前几轮"卡死"的根本原因）

**根因**：[survivor_mode.gd:738-744（修前）](scripts/survivor/survivor_mode.gd:738) 想给离屏敌机做性能节流：

```gdscript
if offscreen:
    ac.set_physics_process(Engine.get_physics_frames() % 3 == 0)  # ← 错
    if ai_node:
        ai_node.set_physics_process(Engine.get_physics_frames() % 3 == 0)
    ac.visible = false
    continue
```

问题：`set_physics_process(bool)` 是 Godot 节点级开关。每帧被父节点这样调用时，会按 `frames % 3 == 0` 打开/关闭。Aircraft 的 `_physics_process` 2/3 的帧完全不执行。

但 **Godot 传给 `_physics_process` 的 delta 永远是 1/60s**（真实单帧），不会因为这 2 帧没跑而累加。结果：
- 离屏敌机 60Hz → 20Hz 触发
- 每次 delta = 0.0167s（正常）
- **飞机经历的模拟时间 = 20Hz × 0.0167 = 0.333s/真实秒 = 1/3 速度**

用户拖动镜头观察时：飞机立刻被算回屏内 → `set_physics_process(true)` 每帧跑 → 回到 60Hz 正常速度。看起来像"观察才运动"。

这同时**解释了之前几轮 ACE-03/ACE-01 的"stuck hdg"**：那些截图是在它们离屏时采样的 ENEMY_SQUAD 快照，hdg 变化缓慢是因为它们真的在 1/3 速度慢动作运行，看起来像冻住。

**修复**：改用 Aircraft 自己的 LOD 2 机制处理节流：

```gdscript
if offscreen:
    ac.lod_level = 2            # 让 Aircraft 进 LOD 2 分支
    ac.set_physics_process(true) # 保持每帧跑
    if ai_node:
        ai_node.set_physics_process(true)
    ac.visible = false
    continue
```

Aircraft 的 LOD 2 处理（[aircraft.gd:392-410](scripts/aircraft.gd:392)）：
- 每帧都跑 `_apply_movement(delta)` → **位置每帧正常推进**
- 每 3 帧跑一次完整物理（bank/heading/speed 等），其余帧跳过
- 延迟感知：重 AI 决策 20Hz，但位置移动 60Hz

AIController 的节流已经在 `ai_tick_divisor` 里正确实现（[ai_controller.gd:384-387](scripts/ai_controller.gd:384)），**该路径正确乘了 delta**，所以 AI 时间不会走慢。

**为什么旧代码不 work 而 LOD 2 机制 work**：前者是节点级"不调用"，delta 丢失；后者是函数内"条件返回"，delta 守恒。这是 Godot 节流正确姿势。

### Bug B：Herbst J-Turn 仍颤抖（上一轮 bank 守卫未覆盖）

2026-04-20 (7) 的 bank 翻转守卫修好了普通机动的颤抖，但 J-Turn 仍颤。抓到的 AC_TICK 数据（t=57.1-58.3，ACE-01 Herbst TURN 阶段）：

```
t=57.7  bnk=+85°  hdg=+130°  ph=HB_TURN
t=57.8  bnk=+85°  hdg=+104°
t=57.9  bnk=+51°  hdg=+78°   ← 掉到 +51
t=58.0  bnk=+66°  hdg=+51°   ← 回到 +66
t=58.2  bnk=+85°  hdg=+25°   ← 又到 +85
```

**根因**：Herbst TURN 阶段 [herbst_maneuver.gd:106](scripts/herbst_maneuver.gd:106) 直接写 `_aircraft.heading += turn_this_frame`（约 3.75°/frame）。

- [aircraft.gd:_update_heading:925-927](scripts/aircraft.gd:925) 已经正确跳过 Herbst 激活阶段
- 但 [`_update_bank`](scripts/aircraft.gd:752) **没有跳过**
- 每帧 heading 被硬转 3~4°，`heading_diff = _cached_target_heading - heading` 也剧变 3~4°
- target_bank 根据 heading_diff 符号和大小翻转 → bank 跟着瞎翻
- 上一轮的 bank-flip 守卫在 heading_diff 大幅度跨 0 时不触发（`|heading_diff| > 5°` 不满足守卫条件）

**修复**：[aircraft.gd:752-760](scripts/aircraft.gd:752) 加守卫，Herbst TURN 阶段直接 early-return，bank 维持入场姿态：

```gdscript
var _hm_bank := get_herbst()
if _hm_bank and _hm_bank.phase == HerbstManeuver.Phase.TURN:
    return
```

为什么只跳 TURN 不跳 DECEL/ACCEL：
- DECEL：Herbst 只改 speed，不改 heading，bank 正常控制无冲突
- TURN：Herbst 硬转 heading，冲突来源，跳过
- ACCEL：Herbst 设 target_position 到正前方 2000m，heading_diff 自然接近 0，target_bank=0，bank 平滑归零，正常路径即可

### 为什么 1/3 速度 bug 过去一直没被定位

- 离屏敌机只通过 ENEMY_SQUAD 快照间接观察（0.5s 一条）
- 每条快照的 `spd=` 显示是 Aircraft 内部 speed 变量 —— **这个值是正确的**（每次 _physics_process 运行时，加速度积分没错）
- 但 **spd 的积累效果被 1/3 调用频率稀释**：表面上 spd=1535 km/h 正常，实际每秒只推进 1/3 距离
- `d=` 距离字段每 0.5s 采样一次，增长速度看起来像"慢半拍"但不显眼
- 需要想到"delta 守恒"问题 + 对照 `set_physics_process` 语义才能定位

### 回归测试要点

**Bug A（离屏 LOD）**：
- 离屏敌机（hidden behind camera viewport）应该以正常速度接近玩家而不是 1/3 速度
- 一架敌机从 5km 外飞向玩家 500m/s = 10 秒应该到达；修前要 30 秒
- 性能：离屏敌机从 20Hz 升到 60Hz 物理（但只做位置推进 + 20Hz AI），单帧开销增加约 3x`_apply_movement`；若有 20+ 敌机全离屏需监控 FPS
- **简单性能兜底**：如果确认性能问题，可以在 AIController 里加 `offscreen_divisor` 提高到 6 或 9（那会再次降低 AI 决策频率但 delta 仍守恒）

**Bug B（Herbst 颤抖）**：
- F-47 BOSS Herbst J-Turn 触发时 AC_TICK 的 bnk 应该在 TURN 阶段保持入场时姿态不抖
- DECEL 和 ACCEL 阶段 bank 仍正常更新
- J-Turn 完成后 bank 应能正确归零

### 已知遗留

- Herbst TURN 期间 bank 冻结不更新 —— 如果飞机入场时 bank 不是 0，视觉上 TURN 过程中飞机以固定 bank 旋转。看起来应该还行（J-Turn 本身就是绕 yaw 轴，roll 保持是合理的）
- 离屏敌机性能优化（如果需要）建议走 AIController 的 `ai_tick_divisor` 而不是 `set_physics_process` 开关

---

## 2026-04-20 (7) Bank 翻转抗振守卫 + AC_TICK 加 tp_d 字段

### 症状（颤抖 bug 的 root cause）

用户报告："飞机激烈机动时剧烈颤抖 / 机头左右晃 / 速度剧烈变化 / 扔下的 flare 堆在原地不动 / 直线平飞没问题"。

### AC_TICK 直接证据（log `combat_log_20260420_015322.txt` t=74-81 的 ACE-04）

上一轮加的 AC_TICK 诊断事件（2026-04-20 (6)）**命中**：

```
t=76.3  bnk=+67°  tp_brg=-17°  spd=309m/s  hdg=-54°
t=76.8  bnk=-61°  tp_brg=-15°  spd=253m/s  hdg=-54°  ← bank 瞬间翻转 +67→-61！
t=76.9  bnk=-86°  tp_brg=-10°  g=14.7     ← 一路滚到 -86°
t=77.0  bnk=-81°  tp_brg=-4°
t=77.5  bnk=+60°  tp_brg=+11°             ← 又翻回 +60°
t=77.6  bnk=+86°  tp_brg=+13°             ← 满右 bank
```

周期 ~1.3s 的 **bang-bang 振荡**。

### 根因机制

[aircraft.gd:_update_bank](scripts/aircraft.gd:752) 的战斗分支（line 826-872）里：

```gdscript
target_bank = sign(heading_diff) * max_bank  # 超过 full_diff 就全力反向
```

- `full_diff = combat_full_bank_diff / combat_bank_aggression`
- F-47 close_fighter：`0.05/1.5 = 0.033 rad ≈ 1.9°` → **死区只有不到 2°**
- 任何微小 heading_diff 符号翻转（tp_brg 穿越 0°）就全力反向 bank
- Bank 滚转率 4 rad/s，从 +86° → -86° 需 **0.75s**
- 期间 target_position 因目标横向移动继续摆动，heading_diff 再次翻转
- Bank 滚到一半又要翻回 → 永远到不了稳定位置

视觉上：bank 反复 +86° ↔ -86°（机头左右疯甩），飞机原地打转（前进有效分量近零），flares 堆在一处。

虽然已有 [`anticipated_change` 过冲补偿（792-806）](scripts/aircraft.gd:792)，但只在 `signf(anticipated) == signf(heading_diff)`（同向）时生效，对翻转瞬间（符号相反）完全不管。

### 修复（附加守卫，原公式不动）

[aircraft.gd:_update_bank](scripts/aircraft.gd:902) 在 target_bank 计算完毕后、stall 强制回正之前插入：

```gdscript
if absf(bank_angle) > BANK_FLIP_ESTABLISHED_RAD \      # 当前 bank > 30°
        and signf(target_bank) != 0.0 \
        and signf(target_bank) != signf(bank_angle) \   # 候选 target_bank 要反向
        and absf(heading_diff) < BANK_FLIP_COMMIT_RAD:  # 但 heading_diff < 5°
    target_bank = 0.0   # 先 roll 到中立
```

常量（aircraft.gd 顶部）：
- `BANK_FLIP_ESTABLISHED_RAD = 0.524`（30°）
- `BANK_FLIP_COMMIT_RAD = 0.087`（5°）

**语义**："当前已经建立一个方向的 bank（>30°），候选目标想翻到对面 —— 但 heading_diff 还不够大（<5°）说明目标只是刚穿过中心，别急着翻，先滚回中立再看情况。"

### 为什么这个守卫不会误伤敏捷性

- **小 bank（<30°）**：守卫不触发，小角度快速翻转仍可行，不影响精细调整
- **大 heading_diff（>5°）**：守卫也不触发，目标确实在对侧要翻就翻
- **只 kill 病态场景**：大 bank + 对侧目标 + 微小 heading_diff 三者同时 → 先过中立再说
- 滚回中立（0.375s @ 4rad/s 从 ±30° 起）后 heading_diff 如果超过 5°，下一帧立刻全力翻 —— 等价于加了 0.3~0.5 秒的迟滞

### AC_TICK 增强：加 tp_d 字段

同时给 AC_TICK 加 `tp_d=<米>`（到 target_position 的距离），用来诊断 Bug 2（ACE-01/ACE-03 脱离战场不回头）。

新格式：
```
bnk=+86° spd=427m/s hdg=-42° tp_brg=+125° tp_d=2340m g=13.9 ab=y ph=HI_BANK
```

下次 Bug 2 复现时，观察 runaway 飞机的 `tp_d`：
- `tp_d=10000m+` 且与玩家距离吻合 → AI 的 target_position 指向玩家附近，bug 在 bank/heading 控制没响应
- `tp_d` 远远小于玩家距离（<500m 在原地附近）→ AI 的 target_position 被什么东西改到了飞机自己附近，aircraft 就地飞
- `tp_d` 背离玩家方向 → AI 选 EXTENSION / SCISSORS 等远离战术或 target_position 计算错

### 回归测试要点

- 普通 AI 近距高 G 转弯不抖（MiG-29 / F-86 / Su-27 都要测）
- F-47 BOSS 近距追击玩家时不再原地打转
- 玩家自己（F-16 survivor 模式点击机动）大 bank 仍能快速反向转弯（因为 `use_tactical_preference` 模式的 deadzone 是 0.02 rad ≈ 1.1°，小角度下守卫不触发，不影响玩家操控手感）
- Herbst J-Turn 期间 bank 直接由模块写（bypass 此路径），不受守卫影响
- 编队 formation_mode 的小角度调整（< 5°）在 bank > 30° 时也被守卫阻止反向 —— 正常阵型飞行 bank 远小于 30°，不冲突

### Bug 2（ACE-01/ACE-03 脱离战场不回头）状态

本次 AC_TICK 没抓到 runaway 瞬间的关键数据（采样触发条件 bank>60° 时它们 bank 多半 <60° 了）。新增的 `tp_d` 字段下次复现能直接告诉我们 target_position 是在玩家附近还是在原地。先 ship Bug 1 修复 + tp_d 诊断，Bug 2 等下一次 log。

---

## 2026-04-20 (6) 追加 AC_TICK 物理采样事件（颤抖 bug 诊断）

### 动机

用户报告："飞机激烈机动时剧烈颤抖 —— 机头上下左右晃、速度剧烈变化、扔下的 flare 都挤在同一个位置跟着晃，直线平飞没问题"。

观察到的间接证据：
- Herbst J-Turn 期间（0.6s 内）速度 1384→1581→757→855 反复暴涨暴跌，每 0.6s 变化 ±200 km/h
- 屏幕截图里 9 枚 flare 挤在同一个点，意味着飞机高速报告但位置推进很少 → 前进速度被频繁反转
- 颤抖频率肯定是亚 0.5s 级（用户描述"飞快颤动"），当前 ENEMY_SQUAD 快照 0.5s 一条看不到

### 本次改动（纯观测，零行为变化）

在 `aircraft.gd` `_physics_process` 末尾加 `_log_ac_tick()`（含节流器）。触发条件 **OR**：
- `HerbstManeuver.is_active`（Herbst J-Turn 中）
- `CobraManeuver.is_active`（眼镜蛇机动中）
- `|bank_angle| > 60°`（高坡度机动）
- `_overshoot_timer > 0`（近距过顶 extension 中）

满足时以 10Hz 节流（0.1s 一条）打 `AC_TICK` 事件：

```
[AC_TICK] Enemy/F-47[ACE-01]: bnk=+72° spd=307m/s hdg=-45° tp_brg=+12° g=7.0 ab=y ph=HB_TURN
```

**字段**：
- `bnk` — bank_angle（度，±=左右）
- `spd` — speed（m/s，精细粒度，不转 km/h）
- `hdg` — heading 归一化到 ±180°
- `tp_brg` — target_position 相对机头方位角（±=左右）
- `g` — g_load
- `ab` — 加力状态 y/n
- `ph` — 阶段标签：`HB_DECEL` / `HB_TURN` / `HB_ACCEL`（Herbst）/ `COBRA` / `OVERSHOOT` / `HI_BANK`

### 条件退出自动重置节流

条件失效时（飞机从高 G 机动退出回巡航）立即 `_ac_tick_log_timer = 0.0`，下次进入高 G 机动时**第一帧就采样**，不会漏掉进入瞬间的快照。

### 性能影响

- 正常巡航（bank<60° 且无 Herbst/Cobra/Overshoot）**立即 return**，每帧 3 个 bool 查询 + 1 次 absf + 1 次 rad_to_deg，可忽略
- 激烈机动时 10Hz 一条事件 + 字符串拼接。F-47 BOSS 4 架同时激烈机动 = 40Hz log，持续 3s = 120 条记录，buffer 里 ~5% 容量
- 无额外 draw / node / 场扫描 — 符合性能守则 7 条硬规则

### 怎么用这些数据诊断颤抖

复现颤抖后按 F9 导出 log，grep `AC_TICK`，看相邻 0.1s 两条之间的跳变：

| 现象 | 对应 bug 来源 |
|------|---------------|
| `bnk` 在 ±20° 内来回翻转（+70° → -50° → +60° → ...） | bank 控制反馈环震荡 —— 查 `_update_bank` / `_committed_turn_sign` / bank 目标计算 |
| `spd` 每条振荡 ±50 m/s（300 → 250 → 320 → 260）| Aircraft 物理推力 + Herbst/AceSquad 强写入 speed 冲突 —— 查 herbst_maneuver.gd:96/112/122 |
| `tp_brg` 从 +30° 跳到 -30° 再跳回 | target_position 被两个系统轮流写入 —— AceSquad.`_maintain_role` vs AIController.`_process_engage` |
| `g` 一直 8.0 恒定 | Herbst 强制 G，但之后某路径没清 |
| `ph=HB_TURN` 但 `bnk` 不动 | Herbst 直接改 heading 绕过了 Aircraft 的 bank 逻辑，视觉上 bank 静止但 hdg 猛转（这是 Herbst 设计行为，不是 bug）|
| 单条 `hdg` 跨越 ±180° 边界 | 航向归一化问题（wrapf 工作正确的话不该出现）|

### 回归测试

观测代码只读，不改行为。需确认：
- 玩家 F-16 激烈机动（G 力 > 4 或 bank > 60°）也会触发 —— 这是**设计内**：玩家也会颤抖的话需要同样数据
- 普通 MiG-29 等敌方战斗机激烈机动同样触发
- 直线巡航场景（沙盒空飞）不产生任何 AC_TICK 事件

---

## 2026-04-20 (5) 僚机编队状态自校正守卫（通用 bug 根因）

### 症状

用户报告："F-47 BOSS 中队 4 架飞机，其中 1 架在和玩家战斗，另外 3 架却掉头跑向地图边缘。" 进一步发现：**所有中队都有这个问题，不止 F-47**。玩家跟其中 1 架战斗时，其他僚机对玩家爱理不睬，各干各的。

曾一度以为是 F-47 cloak 特有 bug（见 2026-04-20 (3/4) ENEMY_SQUAD 诊断），实际是全局性的编队协同失效。

### 根因（追到行号）

`AIController._state` 默认值 [`AIState.PATROL`](scripts/ai_controller.gd:296)。扫了全文 `_state = AIState.SQUAD_FOLLOW` 的赋值：

| 位置 | 触发条件 |
|------|---------|
| [ai_controller.gd:1989](scripts/ai_controller.gd:1989) | `_exit_evade()` 末尾（规避导弹结束）|
| [ai_controller.gd:2175](scripts/ai_controller.gd:2175) | 交战后 disengage |

**没有任何从 PATROL 初始化进入 SQUAD_FOLLOW 的路径**。

所有 spawner 都只碰 `squad` 和 `squad_index`，不动 `_state`：
- [survivor_spawner.gd:551](scripts/survivor/survivor_spawner.gd:551)（普通编队）
- [survivor_spawner.gd:598](scripts/survivor/survivor_spawner.gd:598)（指挥 UAV 僚机）
- [survivor_spawner.gd:658](scripts/survivor/survivor_spawner.gd:658)（其他）
- [ace_squad.gd:142](scripts/survivor/ace_squad.gd:142)（F-47 BOSS）

结果：**僚机永远停在 PATROL**，跑 [`_try_engage`（雷达锥扫描）](scripts/ai_controller.gd:908)。作者自己在 [ai_controller.gd:996-999](scripts/ai_controller.gd:996) 写了这个问题："玩家平飞飞过一架敌机时，该敌机会在僚机的雷达锥外或只短暂进入，永远达不到锁定门槛"。

同文件的解决方案（距离扫描 [`_scan_squad_nearby_enemy`](scripts/ai_controller.gd:1007) + 跟随长机 combat_target 协同 [ai_controller.gd:1035-1060](scripts/ai_controller.gd:1035)）全在 `_process_squad_follow` 里，**僚机从不进这个函数，解决方案永远不生效**。

日志证据（`combat_log_20260420_011628.txt` t=67.4 ENEMY_SQUAD）：ACE-02/ACE-03 锁玩家时 `tgt=Friend/F-16` 但全部缺 `[tm]` 标记（`_squad_attacking_leader_target`）→ 证明它们走的是独立 `_try_engage` 路径，不是协同路径。

### 修复（方案 B：集中式自校正守卫）

为什么选方案 B 而不是方案 A（spawner 初始化）：
- 未来还会加更多有编队的敌人 → spawner 数量会增长，方案 A 每个都要记得设 `_state`，一个漏了就复发
- 编队状态会随游戏动态变化（长机阵亡晋升、中队重组、招募） → 方案 B 每帧自校正，任何时刻出现"合法僚机身份但 state=PATROL"都能自动纠正
- 单一事实来源，修一处覆盖所有 spawner

[ai_controller.gd:411](scripts/ai_controller.gd:411) `_physics_process` 的 `match _state` 前加入守卫：

```gdscript
if _state == AIState.PATROL and not bvr_only \
        and squad and is_instance_valid(squad.leader) and not squad.leader.is_destroyed \
        and squad.leader != aircraft:
    _state = AIState.SQUAD_FOLLOW
    _rejoining = true
    _formation_blend = 0.0
    aircraft.lod_level = 1
    EventLogger.log_event("AI_STATE", _log_name(),
        "auto-enter SQUAD_FOLLOW (spawn init guard, leader=%s)" % squad.leader.callsign)
```

**条件与现有 disengage 路径（ai_controller.gd:2173-2174）完全对齐**：
- `not bvr_only`：F-47 ranged striker 之类的 BVR 狙击手仍走 PATROL 执行逃跑航点（保留）
- `squad.leader != aircraft`：自己是长机不进 SQUAD_FOLLOW（长机在 PATROL 走航点巡逻是合法状态）
- `squad.leader` 有效：残队清理时 `squad = null` 自动绕过

### 为什么不会死循环 / 不会误触发

扫了所有 `_state = AIState.PATROL` 赋值点，每一处都天然使本守卫条件失败：
| 位置 | 为什么不会被守卫拉回 |
|------|-------------------|
| [917](scripts/ai_controller.gd:917) 无效 squad | 同时 `squad = null` |
| [934](scripts/ai_controller.gd:934) 自任长机 | `squad.leader == aircraft` |
| [1998](scripts/ai_controller.gd:1998) exit_evade 无 squad | squad 为 null |
| [2186](scripts/ai_controller.gd:2186) 孤雁长机 | `squad.leader == aircraft` 或 squad 清理 |

切 SQUAD_FOLLOW 后条件 `_state == PATROL` 立即失败 → 守卫自终止，不产生 per-frame 抖动。

### 动态场景自愈（关键优点）

本守卫每帧跑 → 以下场景全自动校正：
- **spawn**：僚机 spawn 时 `_state=PATROL` 但 squad 已设好 → 下一物理帧切入 SQUAD_FOLLOW
- **长机阵亡晋升**：新长机自动转 squad_index=0，旧 squad 里的其他僚机检测到新长机 != 自己仍是僚机 → 自动回 SQUAD_FOLLOW
- **中队重组 / 招募**：任何时刻僚机 squad 指针切到新 squad，只要 leader != self，自动跟随
- **BOSS cloak 干扰残留**：之前 2026-04-20 (3) 里发现 cloak 后 ACE-01 冻结的问题，如果解除时进 PATROL，本守卫也会自动拉回 SQUAD_FOLLOW

### 新增日志事件

`[AI_STATE] <Enemy>: auto-enter SQUAD_FOLLOW (spawn init guard, leader=<callsign>)`

复现中队协同失效时可以 grep `auto-enter SQUAD_FOLLOW` 看：
- spawn 后多久才进 SQUAD_FOLLOW（理论上下一个物理帧，应该在 spawn 后 1~17ms 内）
- 是否有中途再触发（表示 state 出现意外的 PATROL 回退）

### 回归测试要点

- 普通中队遭遇：ENEMY_SQUAD 应该能看到所有僚机 `tac=TACTIC_FOLLOW_FORMATION / TACTIC_REJOIN` 跟随长机；长机交战后僚机 `tac=TACTIC_TEAM_ATTACK` 带 `[tm]` 标记
- F-47 BOSS：守卫不影响 AceSquad 内部 update loop（它走 ai_override_pursuit 直接设 target_position）。BOSS ranged striker 若设了 bvr_only 则不受守卫影响
- 指挥 UAV 僚机：`orbit_squad_leader=true + simple_ai=true`，在 `_physics_process` 早期 simple_ai 分支 return（[ai_controller.gd:389-398](scripts/ai_controller.gd:389)），根本跑不到守卫这里 → 行为不变
- 护驾系统 shield_leader：同样 simple_ai，不受影响
- 残队清理：长机阵亡 → squad.remove_member → squad.leader 换人；若剩下 1 架则 leader==self，守卫不触发，走 PATROL

### 工作约定更新

**以后加新的中队敌人 spawner 不需要再手动设 `_state = AIState.SQUAD_FOLLOW`**。只需设好 `ai.squad + ai.squad_index`（这是 Squad 数据契约的一部分），`_physics_process` 守卫会下一帧自动纠正。

---

## 2026-04-20 (4) 追加 ENEMY_SQUAD 诊断事件（含跑路成员）

### 动机

用户反馈："F-47 BOSS 中队 4 架飞机，其中 1 架在和玩家战斗，另外 3 架却掉头跑向地图边缘。"

更一般的问题：敌方中队里的飞机对队友"爱理不睬"，协同失效。当前日志没有任何编队协同字段。

### 关键设计：列整个中队而不只是交战者

第一版曾把过滤做成"只列出正在以玩家为目标的敌机"。用户指出这刚好漏掉了 bug 场景 —— 跑路的那 3 架 `_current_target != player`，会被过滤掉看不到。

**正确逻辑（本版）**：两遍扫描
1. Pass 1：找出所有"至少有一个成员在交战玩家"的中队 + 无中队的单机交战者
2. Pass 2：对每个参战中队，**列出中队全部存活成员**（不管他本人是否在打玩家）+ 单机交战者

这样 1 个在打 + 3 个跑路的 F-47 中队，4 条全都进日志，跑路的 3 架的 `tgt=` / `hdg=` / `spd=` / `dL=` 能直接看出异常。

### 本次改动（纯观测，零行为变化）

`_log_pursuit_snapshot` 每次打 `PURSUIT` 同周期附带打 `ENEMY_SQUAD`（`aircraft.gd:_log_enemy_squads_engaging_player` + `_format_enemy_entry`）。

**每条记录字段**：
- `<callsign>[<type>]` — 敌机身份
- `sq=<leader_callsign>#<squad_index>` — 所属中队（长机呼号 + 序号 0=长机）。`sq=solo` 无中队
- `st=<P/E/V/F>` — AIState：P=PATROL、E=ENGAGE、V=EVADE_MISSILE、F=SQUAD_FOLLOW
- `tac=<current_tactic_name>` — AI 当前战术
- `[tm]/[fr]/[sl]` — `_squad_attacking_leader_target` / `_squad_free_engaging` / `salvo_leader`
- `tgt=<他当前目标>` — AI 实际锁定的目标（`-`=无目标）
- `d=<米>` — 距玩家距离
- `dL=<米>` — 距本队长机距离（长机本人不输出此字段）
- `spd=<km/h> hdg=<°>` — 速度 + 航向 → 看 "跑向地图边缘" 用

**节流**：与 PURSUIT 同频率 0.5s，只在玩家 `use_tactical_preference=true` 且有 combat_target 时触发。

### 怎么用日志诊断"跑路"/"爱理不睬"bug

F-47 场景预期异常模式（照下面对号入座）：

1. **3 架跑路**：看 `dL=` 持续飙升（>2000m 且增长），`tgt=-`，`hdg=` 远离玩家方向，`tac=` 一直是 `TACTIC_RETURN_FORMATION` / `TACTIC_REJOIN` 或空。则是 AceSquad 的"分散→归队"分支把僚机送到地图外
2. **目标错乱**：同 sq 的僚机 `tgt=Enemy/xxx` 指向己方别的敌机 → 阵营 / target 选择器 bug
3. **状态卡死**：`st=F`（SQUAD_FOLLOW）但 leader `st=E`（ENGAGE）→ 僚机没跟着切 ENGAGE
4. **tac 混乱**：同 sq 的 4 架 `tac=` 全不一样 → 协同状态机抖动
5. **`[tm]` 缺失**：僚机 `tgt=玩家` 但没 `[tm]` 标记 → 自认独立 free_engage
6. **st=P tgt=玩家**：状态和目标解耦（bug）

### 回归测试

观测代码只读，不改行为。需确认：
- F-47 BOSS 场景 FPS 不掉（单条 ENEMY_SQUAD 遍历 all_units 1 次 + 每个参战中队遍历 members 1 次，0.5s 一次 → 微小）
- 日志可读性：4~8 个敌机时单行 500~800 字符，可 grep `ENEMY_SQUAD` 过滤

### 已知限制

- 只有玩家有 `combat_target` 时才触发。若玩家没锁目标但中队正在跑路，看不到 log（通常这种情况玩家很快就会锁一个）
- 多个中队同时交战时全塞一行，长但完整
- 无中队单机（如游荡的 J-7）走 `solo_engagers` 分支，只在他本人交战玩家时上榜（无中队可扩展）

---

## 2026-04-20 (3) B_rear_six_offset 绕大圈根因与守卫

### 症状

玩家机炮攻击 MiG-29（及其他高机动敌机）时，近距离（<300m）遇到对方急转就会 180° 大 U 形倒飞 3km，再转回头重新冲入，循环往复，永远打不中。

### 根因（从 log `combat_log_20260420_005003.txt` 逐帧追）

完整 engagement 周期：

| 时刻 | 分支 | dist | aim | tp_brg° | 行为 |
|------|------|------|-----|---------|------|
| 324~328s | `A_rear_aligned` | 1308→362m | 1.00→0.96 | +2~+16° | 正常追尾逼近 |
| **328.7s** | `B_rear_six_offset` | **278m** | 0.82 | **-118°** | aim 掉破 0.87 切 B，**target_position 瞬间跳到身后** |
| 330.1s | — | — | — | — | `PURSUIT_LOCK` turn_sign=-1 |
| 330~336s | B | 565→2946m | -0.61→0.11 | -150~-87° | 被迫 180° 左转大回环倒飞出去 |
| 336.5s | — | — | — | — | `PURSUIT_UNLOCK`（turn_sign 自然清除）|
| 339~347s | A | 2909→346m | 0.89→0.95 | -26→+17° | 再次冲回来追尾 |
| 347.8s | B | 230m | 0.64 | **-127°** | 再次触发同样 bug |

B 分支公式：`pursuit_pos = tgt_pos - tgt_fwd * six_offset`，其中 `six_offset` 近距被 lerp 到 `gun_range × 1.0`（F-16 M61 约 1500m）。

**几何陷阱**：当玩家 `dist < six_offset` 时，"目标六点钟 `six_offset` 处"这个点落在玩家自己身后 → 飞机执行"飞到那个点"就是 180° 倒退。B 分支原本是"导入六点钟切入位"的逻辑，但它没考虑玩家已经在六点钟切入位**内侧**的情况。

用户一针见血："主角飞机不懂得什么叫做剪式飞行"。正确的人类飞行员行为是 scissors weave 或 lag pursuit，绝不是倒飞 3km 重置。

### 修复（附加守卫，不动原公式）

[aircraft.gd:1786](scripts/aircraft.gd:1786) `_choose_dogfight_pursuit_pos` 情况 B，在 `return six_pos` 之前加几何守卫：

```gdscript
var six_pos := tgt_pos - tgt_fwd * six_offset
var to_six_dir := (six_pos - my_pos).normalized()
if to_six_dir.dot(my_fwd) < 0.0:
    # six_pos 在玩家身后 → 避免 U 形倒飞，回落到 tgt_pos 直瞄目标
    if use_tactical_preference:
        _pursuit_branch = "B_guard_six_behind_me"
    return tgt_pos
```

触发条件纯几何：候选追击点与机头方向的 dot 为负（即要求玩家倒飞）。原公式所有 lerp / clamp / 常量完全不变，只在病态几何下 early-return 到目标本身。

回落到 `tgt_pos` 的效果：飞机继续朝目标延伸，穿过目标后 `in_rear` 翻转到 false，自然走 C 分支的前置拦截。这是 A 分支早已验证的"穿过目标"行为，不是新路径。

### 回归测试要点

- 远距（>1500m）后半球未对准切入：应正常走老 B 分支，tp_brg 在机头前方，不触发守卫
- 近距（<300m）目标急转 aim 掉破 0.87：应走 `B_guard_six_behind_me`，穿过目标后切 C
- 对头接近：`in_rear=false`，根本不进 B，守卫无效，行为不变
- AI 敌机（`use_tactical_preference=false`）：守卫照常生效（这是通用几何问题）—— 可能改善 AI 近距咬尾行为，观察是否有意外变化
- 慢目标（直升机/轰炸机）：已被 OVERSHOOT_SLOW 分支保护，不进 `_choose_dogfight_pursuit_pos`，无影响

### 新增观测分支

`_pursuit_branch = "B_guard_six_behind_me"` —— 下次若玩家仍绕圈，看这个标签触发频率和后续 branch 是否正确切到 C。

---

## 2026-04-20 (2) 追击诊断断点（PURSUIT 系列事件）

### 动机

用户报告："玩家永远无法用机炮成功攻击 MiG-29，总是绕一大圈往反方向。敌机在右边，他明明右转一点就能到位，非要从左边绕一大圈。"

截图显示：玩家 F-16 hdg 051°、MiG-29 hdg 012°、range 465m，玩家的飞行轨迹（蓝线）明显往左大弧线绕，而 MiG-29 在玩家前方偏右。

**当前日志一片空白** —— 没有任何 PLAYER / PURSUIT 类事件，出 bug 只能靠截图和语言描述猜根因。之前几轮修改都是在没有运行时数据的情况下硬改公式，导致一个情景修好、另一个情景坏掉。

### 本次改动（纯观测，零行为变化）

在 `aircraft.gd` 追加了一组诊断事件，**只对 `use_tactical_preference=true` 的玩家飞机触发**，不影响 AI 敌机、不改变任何判定逻辑：

| 事件 | 触发时机 | 信息 |
|---|---|---|
| `PURSUIT_ACQUIRE` | `set_combat_target(non-null)` | 获得目标（target 名 + 武器模式） |
| `PURSUIT_CLEAR` | `clear_combat_target()` | 失去目标（前 target 名） |
| `PURSUIT_LOCK` | `_committed_turn_sign` 从 0 被锁定（heading_diff > 143°） | turn_sign / hdg_diff / target / branch |
| `PURSUIT_UNLOCK` | `_committed_turn_sign` 从 ±1 解锁（hdg_diff < 86°） | hdg_diff / target |
| `PURSUIT` | 节流 0.5s 一次快照 | branch / tgt / dist_m / aim / rear / asp° / **tp_brg°** / hdg_diff° / turn_sign / firing / wpn / ammo |

**最关键的字段**：
- `branch` —— 哪个分支选的 target_position（A_rear_aligned / B_rear_six_offset / C_lead_intercept / C_head_on_guard / OVERSHOOT_EXT / BIG_TURN_>90）
- `tp_brg°` —— target_position 相对玩家机头的方位角，**+右 / -左**。用来和截图对照"该往哪边转"
- `turn_sign` —— `_committed_turn_sign`（0/±1）。如果 bug 发生时 turn_sign 和 tp_brg 方向相反，锁定分支就是元凶

### 可疑根因（待日志证实）

`_committed_turn_sign`（[aircraft.gd:10](scripts/aircraft.gd:10)）在 `|heading_diff| > 143°` 时锁转弯方向，直到 `< 86°` 才解锁。高机动 MiG-29 紧咬时 heading_diff 长期卡在 86~143°，一旦最初锁错方向就一直绕大圈，直到目标完全跑到机头前方 86° 内才解锁。

但这只是假设，**在用户按 F9 抓到新 log、看到 PURSUIT_LOCK + PURSUIT 快照前不动手改**。

### 使用方法

玩家下次复现"绕圈方向错"bug 后立刻按 F9 导出 log。重点看：
1. `PURSUIT_LOCK` 事件的 hdg_diff 符号 vs 当时目标实际方位 —— 如果符号一致，说明锁定本身没错，问题在 target_position 的分支选择
2. 连续几条 `PURSUIT` 快照里 `tp_brg°` 符号是否稳定，以及 `branch` 是否频繁切换 —— 切换频繁则分支震荡，稳定不变但方向错则分支本身计算错
3. `turn_sign` 持续为非 0 的时长，对比 `hdg_diff°` 是否进入 ±86° 解锁带但未解锁（说明 _cached_target_heading 没更新到位）

### 回归测试

断点本身不改行为，但要确认：
- 20+ 架飞机场景 FPS 不掉（节流 0.5s + 只打玩家 → 单机每秒 2 条 PURSUIT + 偶发 LOCK/UNLOCK，可忽略）
- AI 敌机日志干净（字符串 `PURSUIT` 只该配上 `Friend/F-16` 等玩家机名）

---

## 2026-04-20 追尾/对头机炮行为修复

### 症状
1. 追尾敌机时明明在射击位，玩家飞机非要飞过敌机，导致被敌机机炮反咬
2. 和敌机对头时，玩家飞机不开火而是扭头避战

### 根因

**问题1（追尾飞过）** — `aircraft.gd` 中 `_update_combat` 的 overshoot extension 分支（当前约 1466 行）：
- 原逻辑：距离 < `OVERSHOOT_DIST_PX` (80px ≈ 160m) 时强制沿机头直飞 `OVERSHOOT_EXTEND_DIST_PX` (2000px) 并停火 1.2s
- 只对"慢目标"（cruise×40% 以下，如直升机/轰炸机）禁用
- 追尾同速战斗机时，160m 是完美射击距离但 extension 照样触发，把六点钟位置让出去

**问题2（对头扭头）** — `_choose_dogfight_pursuit_pos` 情况 C（前半球/侧翼，当前约 1729 行）：
- 原公式 `closing_rate = max(my_speed - tgt_speed, MIN_CLOSING_RATE_PX)`
- 对头时两机速度相近 → 差值 ≈ 0 → 钳到 `MIN_CLOSING_RATE_PX` (30 px/s)
- `predict_time = dist / 30` 被 `PREDICT_TIME_MAX` (3.0s) 拉满
- 前置点 = `tgt_pos + tgt_fwd × tgt_speed × 3s`
- 对头时 `tgt_fwd` 指向玩家身后 → 前置点落在玩家背后 → `target_position` 在后方 → 飞机转向离开

### 修复

**均为附加判定，不改原闭合率公式 / 不改原 extension 常量**。

1. `aircraft.gd` overshoot 触发前增加 `aligned_tail_chase` 守卫：`in_rear_hemisphere && my_fwd.dot(to_target) > 0.87`（后半球 + 机头±30°）时跳过 extension。穿过目标后 `in_rear_hemisphere` 自然翻转，下一帧走原有 `heading_diff > 90°` 掉头分支。
2. `_choose_dogfight_pursuit_pos` 情况 C 原 `closing_rate` / `predict_time` 保留不变。末尾新增对头守卫：`head_on_dot > 0.7 && aim_align > 0.7` 时单独算真实闭合率 `aim_align × my_speed + head_on_dot × tgt_speed`，用这个重算的 `predict_time` return 一个新前置点；不满足对头条件则 fallthrough 到原公式。

### 回归测试要点

改动附近代码或调参时必须重测：
- 追尾快速敌机（MiG-29 / Su-27）：接近到 150~200m 时应持续开火并穿过，不再大回环
- 追尾慢目标（CH-47 / Tu-160）：原 slow target 分支依旧禁用 overshoot，持续扫射
- 对头中等速度敌机（J-7 / A-7）：应在进入机炮射程后持续开火，不掉头
- 对头超高速敌机（MiG-31）：新守卫的 `head_on_predict` 仍被 `PREDICT_TIME_MAX` 约束，不会射击点飞出合理范围
- 侧翼 90° 切入：`head_on_dot < 0.7`，应走原公式，不触发新守卫
- AI 敌机的 `_choose_dogfight_pursuit_pos` 调用路径（`use_tactical_preference=false` 分支）也复用同一函数 —— 确认 AI 对头进攻行为不变差
