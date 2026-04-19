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
