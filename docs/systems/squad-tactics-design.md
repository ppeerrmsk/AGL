# 小队战术系统设计文档

> 参考：Robert L. Shaw《Fighter Combat: Tactics and Maneuvering》第5-8章
> 适用模式：**生存模式**（沙盒模式已废弃）
> 状态：早期设计文档（2026-05）——**编队学说的思想来源**，不是当前实装规格
>
> ⚠ 本文写于沙盒时代，当时的设想是"玩家指挥一个编队"。这个方向后来成为项目主线
> （RTS 化转向），但**实装规格已迁移到 specs**：
> [squad-cohesion](../specs/systems/squad-cohesion.md)（小队凝聚学说）·
> [formation-discipline](../specs/systems/formation-discipline.md)（阵型纪律与齐射）·
> [squad-control-switching](../specs/systems/squad-control-switching.md)（切控）·
> [rts-command](../specs/systems/rts-command.md) + [command-wheel](../specs/systems/command-wheel.md)（指挥）·
> [wingman-escort-evasion](../specs/systems/wingman-escort-evasion.md)（僚机护卫）。
>
> 读本文是为了理解**为什么这么设计**（Shaw 的互相支援 / 交战机-自由机分工等原则）；
> 要数值和当前行为请去上面的 spec。

---

## 一、设计目标

引入 **2-4 机小队协同作战**，使玩家可以指挥一个编队执行空战任务，AI 僚机根据战术学说自主配合。系统应体现以下核心空战原则：

1. **互相支援**（Mutual Support）——编队存在的根本目的
2. **角色分工**（Engaged / Free Fighter）——交战机与自由机的动态切换
3. **战术阵型**（Formation）——不同阵型适应不同战场态势
4. **任务超载管理**——AI 在高压下会犯错，技能等级影响表现

---

## 二、编队结构

### 2.1 基本单元：双机编队（Section / Element）

空战的最小有效协同单元。由 **长机（Leader）** 和 **僚机（Wingman）** 组成。

```
  L ---- W        Combat Spread（战斗展开，并排）
  间距：1000-2000m（约500-1000像素）

  L
   \               Echelon（梯形，僚机在后侧60°）
    W
  间距：600-1200m
```

### 2.2 四机编队（Division / Flight）

两个双机编队组成。

```
  L1 ---- W1       Finger Four（指尖四点）
      L2 ---- W2
  编组间距：1500-3000m

  L1 -- W1 -- L2 -- W2    Wall（线列，四机并排）
  机间距：800-1500m
```

### 2.3 数据结构

```gdscript
class_name Squad
extends RefCounted

enum Formation { COMBAT_SPREAD, ECHELON, WALL, FINGER_FOUR, TRAIL }
enum Doctrine { FIGHTING_WING, DOUBLE_ATTACK, LOOSE_DEUCE }

var leader: Aircraft                      # 编队长机
var members: Array[Aircraft] = []         # 所有成员（含长机）
var formation: Formation = Formation.COMBAT_SPREAD
var doctrine: Doctrine = Doctrine.DOUBLE_ATTACK
var base_spacing: float = 1500.0          # 基础间距（米）

# 动态角色
var engaged_fighter: Aircraft = null      # 当前交战机
var free_fighter: Aircraft = null         # 当前自由机
```

```gdscript
class_name SquadManager
extends Node

var squads: Array[Squad] = []

func create_squad(aircraft_list: Array[Aircraft]) -> Squad
func dissolve_squad(squad: Squad) -> void
func assign_formation(squad: Squad, formation: Squad.Formation) -> void
func assign_doctrine(squad: Squad, doctrine: Squad.Doctrine) -> void
```

---

## 三、战术学说（Doctrine）

参考 Shaw 的三大双机战术原则，对应三种 AI 行为模式。

### 3.1 僚翼战术（Fighting Wing）

> 适用：僚机技能低、训练不足、或需要最简单协同时

| 角色 | 行为 |
|------|------|
| 长机 | 导航、搜索、决定交战、执行所有攻击 |
| 僚机 | 保持阵型（后侧60°），监视后半球，**不主动攻击** |

**AI 实现要点：**
- 僚机 `target_position` = 长机位置 + 编队偏移（相对长机航向旋转）
- 僚机仅在长机明确指令或被直接攻击时才独立交战
- 僚机探测到后方威胁时通过信号通知长机（`signal squad_threat_detected`）

### 3.2 双重攻击（Double Attack）

> 适用：中等技能编队、高威胁环境、2v2 对称交战

交战后转换为 **交战机 / 自由机** 角色：

| 角色 | 职责 |
|------|------|
| 交战机（Engaged） | 与目标一对一缠斗，全力攻击 |
| 自由机（Free） | **不参与进攻**，监视第二个威胁，掩护交战机后半球 |

**角色切换条件：**
1. 交战机能量耗尽（速度 < 巡航速度 × 0.7）→ 请求换位
2. 交战机被第二架敌机威胁 → 自由机介入解围后换位
3. 交战机击毁目标 → 自由机如有目标则升任交战机

**自由机 AI 行为：**
- 在交战平面的 **垂直方向** 绕圈（Shaw: 交战机水平盘旋时，自由机做垂直面拉升/俯冲）
- 在游戏中简化为：自由机在交战区域外围 **高位盘旋**，保持 1500-2500m 距离
- 监视自由敌机方向；若敌机攻击交战机，立即俯冲干扰（短暂交火后脱离，不深追）

### 3.3 松散双机（Loose Deuce）

> 适用：高技能编队、需要最大攻击效率、1v2 / 2v1 场景

与双重攻击的关键区别：**自由机主动寻找射击位置**（射手/射手 模式）。

| 角色 | 职责 |
|------|------|
| 交战机 | 维持对敌压力（滞后追踪），迫使敌机做可预测转弯，**不冒险冲刺** |
| 自由机 | 主动预判敌机航线，争取最快进入射击窗口 |

**交战机 AI：**
- 使用 `LAG_PURSUIT` 战术，保持在敌机后半球但不过度逼近
- 目标：让敌机持续转弯 ~360°，给自由机创造时间窗口
- 压力控制：距离保持在 800-1500m，不进入 500m 以内

**自由机 AI：**
- 计算敌机当前转弯圆的切入点
- 选择进攻路径：
  - **顺流攻击**（In-flow）：与敌机同向绕行，从侧后切入——精度高、容错高
  - **逆流攻击**（Counter-flow）：与敌机反向，正面截击——速度快但时间窗极窄
- 到达射击位置后开火，击杀或冲过后角色互换

**角色自主切换：**
- 自由机到位后呼叫接管（不需等交战机召唤）
- 交战机感知将被冲过时主动呼叫换位

---

## 四、编队阵型与机动

### 4.1 阵型偏移计算

```gdscript
# 根据阵型和编号计算僚机相对长机的偏移
func get_formation_offset(formation: Formation, index: int, spacing: float) -> Vector2:
    match formation:
        Formation.COMBAT_SPREAD:
            # 并排展开，奇数左偶数右
            var side = -1.0 if index % 2 == 1 else 1.0
            var rank = ceili(index / 2.0)
            return Vector2(side * spacing * rank, 0)

        Formation.ECHELON:
            # 后侧60°梯形
            var side = -1.0 if index % 2 == 1 else 1.0
            return Vector2(side * spacing * 0.5 * index, -spacing * 0.866 * index)

        Formation.TRAIL:
            # 纵列
            return Vector2(0, -spacing * index)

        Formation.FINGER_FOUR:
            # 指尖四点（两对 Combat Spread 前后错开）
            var pair = index / 2
            var side = -1.0 if index % 2 == 0 else 1.0
            return Vector2(side * spacing * 0.5, -spacing * 0.6 * pair)

        Formation.WALL:
            # 四机并排
            var center_offset = (members.size() - 1) / 2.0
            return Vector2((index - center_offset) * spacing, 0)
```

偏移向量需 **按长机航向旋转** 后加到长机位置上：

```gdscript
func get_wingman_target(leader: Aircraft, offset: Vector2) -> Vector2:
    var rotated = offset.rotated(leader.heading)
    return leader.position + rotated
```

### 4.2 编队转向

参考 Shaw 的战术转弯（Tac Turn），编队换向时：

1. **原地转弯**：所有人同时转，简单但内侧机短暂失去视野覆盖
2. **交叉转弯**：内侧机飞越外侧机上方，转完后左右互换（本项目简化：编队偏移 index 互换）
3. **战术转弯**：分两段各 90°，保持腹侧视野——推荐作为默认转向方式

游戏中简化实现：长机转向后，僚机根据新航向重新计算偏移目标点，通过正常转弯物理飞向新位置。编队转向时允许 **阵型临时散开**，到位后自动收拢。

### 4.3 编队间距动态调节

| 态势 | 间距倍率 | 说明 |
|------|----------|------|
| 巡航 | 1.0× | 标准间距 |
| 接敌 | 1.5× | 展开以增加搜索覆盖和包夹空间 |
| 交战中 | 自由 | 交战机/自由机独立机动，不维持阵型 |
| 脱离 | 0.6× | 收紧阵型便于快速重组 |

---

## 五、交战流程状态机

```
                    ┌──────────────┐
                    │   CRUISING   │  编队巡航/巡逻
                    │  保持阵型     │
                    └──────┬───────┘
                           │ 发现敌机
                    ┌──────▼───────┐
                    │  PRE_ENGAGE  │  展开阵型，分配角色
                    │  间距增大     │  选择学说/战术
                    └──────┬───────┘
                           │ 进入交战距离
              ┌────────────▼────────────┐
              │        ENGAGED          │
              │  交战机 vs 自由机角色    │
              │  按学说执行战术          │
              │  动态角色切换            │
              └────────────┬────────────┘
                           │ 目标歼灭/脱离/弹药耗尽
                    ┌──────▼───────┐
                    │   REJOIN     │  重组编队
                    │  收拢阵型     │  恢复巡航间距
                    └──────┬───────┘
                           │ 阵型恢复
                    ┌──────▼───────┐
                    │   CRUISING   │
                    └──────────────┘
```

### 5.1 SquadAI 状态机

```gdscript
class_name SquadAI
extends Node

enum SquadState { CRUISING, PRE_ENGAGE, ENGAGED, REJOIN }

var squad: Squad
var state: SquadState = SquadState.CRUISING
var threat_list: Array[Aircraft] = []     # 探测到的威胁列表

func _physics_process(delta: float) -> void:
    _update_threat_list()
    match state:
        SquadState.CRUISING:
            _maintain_formation(delta)
            if threat_list.size() > 0:
                _transition_to_pre_engage()
        SquadState.PRE_ENGAGE:
            _widen_formation()
            _assign_roles()
            if _in_engagement_range():
                _transition_to_engaged()
        SquadState.ENGAGED:
            _execute_doctrine(delta)
            _check_role_switch()
            if _engagement_complete():
                _transition_to_rejoin()
        SquadState.REJOIN:
            _tighten_formation()
            if _formation_restored():
                state = SquadState.CRUISING
```

---

## 六、威胁评估与目标分配

### 6.1 威胁评分

每架探测到的敌机根据以下因素打分（复用并扩展现有 `_score_target()` 逻辑）：

```gdscript
func _score_threat(enemy: Aircraft, from: Aircraft) -> float:
    var score := 0.0
    var dist = from.position.distance_to(enemy.position)
    var angle_off = _aspect_angle(from, enemy)  # 0°=正后方 180°=正前方

    # 距离越近威胁越大
    score += (1.0 - clampf(dist / 20000.0, 0, 1)) * 40.0

    # 在我后半球的敌机威胁更大
    if angle_off > 90.0:
        score += (angle_off - 90.0) / 90.0 * 30.0

    # 正在攻击编队成员的敌机优先
    if enemy.combat_target in squad.members:
        score += 25.0

    # 闭合率（正在逼近的更危险）
    var closure = _closure_rate(from, enemy)
    if closure > 0:
        score += clampf(closure / 300.0, 0, 1) * 15.0

    # 有导弹在飞向编队成员
    if _has_missile_targeting_squad(enemy):
        score += 20.0

    return score
```

### 6.2 目标分配规则

| 编队规模 | 敌机数 | 分配策略 |
|----------|--------|----------|
| 2v1 | 1 | 交战机攻击，自由机掩护 |
| 2v2 | 2 | 各分配一个目标；按学说决定谁先交战 |
| 4v2+ | 多 | 第一编组交战最高威胁，第二编组自由掩护 |
| 2v多 | 多 | 打击-重组-再打击（Strike-Rejoin-Strike）循环 |

**钳形攻击（Bracket）**：2v1 时双机向目标两侧展开，迫使敌机只能应对一侧：

```gdscript
func _execute_bracket(target: Aircraft) -> void:
    var to_target = (target.position - squad.leader.position).normalized()
    var perp = to_target.rotated(PI / 2)

    # 交战机从左侧接近
    engaged_fighter.set_target_position(target.position + perp * 800)
    # 自由机从右侧接近
    free_fighter.set_target_position(target.position - perp * 800)
```

---

## 七、通信系统（信号与消息）

编队内通信通过 Godot Signal 实现，模拟无线电呼叫：

```gdscript
# Squad 信号
signal role_switch_requested(requester: Aircraft)
signal threat_detected(detector: Aircraft, threat: Aircraft)
signal engaging(fighter: Aircraft, target: Aircraft)
signal winchester(fighter: Aircraft)        # 弹药耗尽
signal defensive(fighter: Aircraft)         # 进入防御态势
signal rejoin_called(caller: Aircraft)      # 请求重组
```

### 通信延迟与干扰

为增加真实感，可选添加通信延迟：

- 信号发出后延迟 0.5-1.5 秒才被接收（模拟反应时间）
- `skill_level` 低的飞行员延迟更长
- 高压力（`_stress > 0.8`）时可能遗漏信号

---

## 八、玩家操控接口

### 8.1 编队选择与指挥

| 操作 | 效果 |
|------|------|
| 左键点击友机 | 选中单机 |
| 框选 / Shift+点击 | 多选飞机 |
| Ctrl+1-4 | 编组快捷键（绑定编队） |
| 1-4 | 选中已绑定编队 |
| 左键点地面 | 编队飞向该点（保持阵型） |
| 左键点敌机 | 编队交战该目标 |
| F 键 | 切换阵型（循环：展开→梯形→纵列→线列） |
| T 键 | 切换战术学说（僚翼→双重攻击→松散双机） |
| Tab 键 | 在编队成员间切换主视角 |

### 8.2 快捷战术指令

| 按键 | 指令 | 效果 |
|------|------|------|
| Q | Bracket（钳形） | 双机向目标两侧展开夹击 |
| E | Split（分离） | 双机向反方向分开（防御） |
| R | Rejoin（重组） | 所有僚机回到阵型位置 |
| G | Engage Free（自由交战） | 僚机自主选择目标攻击 |

---

## 九、与现有系统的集成

### 9.1 对 `aircraft.gd` 的改动

- 新增属性 `squad: Squad`（所属编队引用）
- 新增属性 `squad_role: StringName`（"leader" / "wingman" / "engaged" / "free"）
- `target_position` 来源扩展：玩家指令 → 编队阵型计算 → AI 自主战术
- 现有战斗 AI（三阶段追踪、能量管理等）完全保留，编队系统在其上层协调

### 9.2 对 `ai_controller.gd` 的改动

- 新增状态 `AIState.SQUAD_FOLLOW`（编队跟随）
- 编队僚机在 `SQUAD_FOLLOW` 时，`target_position` 由 `SquadAI` 计算
- 收到 `role_switch` 信号时切换到 `ENGAGE` 状态，行为与现有交战 AI 一致
- 自由机状态：在交战区域高位盘旋，使用现有巡逻逻辑的变体

### 9.3 对 `main.gd` 的改动

- `selected_aircraft` 扩展为真正的多选
- 新增 `SquadManager` 子节点管理所有编队
- 输入处理增加编队快捷键
- 框选逻辑（按住左键拖拽画框）

### 9.4 新增文件

| 文件 | 职责 |
|------|------|
| `scripts/squad.gd` | Squad 数据结构与阵型计算 |
| `scripts/squad_ai.gd` | SquadAI 状态机与战术执行 |
| `scripts/squad_manager.gd` | 编队创建/销毁/全局管理 |

---

## 十、分阶段实现计划

### Phase 1：基础编队移动（最小可用）

- [ ] `Squad` 数据结构 + `Formation` 阵型偏移计算
- [ ] `SquadManager` 编队创建/销毁
- [ ] 僚机跟随长机保持阵型（`COMBAT_SPREAD` 和 `ECHELON`）
- [ ] 玩家框选多架友机 → 自动创建编队
- [ ] 左键点击地面 → 编队整体移动
- [ ] F 键切换阵型

### Phase 2：战术学说与角色系统

- [ ] 交战机/自由机角色分配
- [ ] Fighting Wing（僚翼）学说实现
- [ ] Double Attack（双重攻击）学说实现
- [ ] 角色切换逻辑（能量耗尽、受威胁、击毁目标）
- [ ] 编队通信信号
- [ ] T 键切换学说

### Phase 3：高级战术

- [ ] Loose Deuce（松散双机）学说实现
- [ ] 钳形攻击（Bracket）
- [ ] 防御分离（Defensive Split）
- [ ] Strike-Rejoin-Strike 循环
- [ ] 威胁评估与目标自动分配
- [ ] Q/E/R/G 快捷指令

### Phase 4：四机编队与多机战术

- [ ] 四机编队支持（Finger Four、Wall）
- [ ] 双编组协同（交战编组 + 自由编组）
- [ ] Fluid Four 战术
- [ ] 多机混战外围截击逻辑

### Phase 5：润色

- [ ] 编队 HUD 信息（角色状态、阵型图标）
- [ ] 通信延迟与飞行员压力影响
- [ ] 编队快捷键绑定（Ctrl+数字）
- [ ] 异种机型混编支持

---

## 十一、关键参数参考（来自 Shaw）

| 参数 | 真实值 | 游戏值（建议） | 说明 |
|------|--------|----------------|------|
| Combat Spread 间距 | 1-2 英里 (1.6-3.2km) | 1500m (750px) | 双机并排基础间距 |
| Echelon 角度 | 后侧 60° | 60° | 僚机相对长机位置角 |
| Finger Four 机间距 | ~600ft (180m) | 600m (300px) | 游戏放大便于操控 |
| 交战机-自由机距离 | 可变 | 1500-2500m | 自由机盘旋半径 |
| 自由机高度差 | 1000-3000ft | 1000-2000m | 自由机比交战机高 |
| 角色切换触发速度 | 低于巡航 30% | speed < cruise×0.7 | 能量耗尽阈值 |
| 钳形攻击展开距离 | 可变 | 800m 横向偏移 | 目标两侧 |
| 防御分离角度 | 180° 对向 | 各偏 90° | 向反方向分开 |

---

## 十二、设计理念总结

Shaw 的核心教训：**80-90% 的空战损失来自毫无察觉的攻击**。编队系统的首要价值不是增加火力，而是 **扩大态势感知、消除盲区**。

本设计遵循以下原则：

1. **简单优先**：默认双重攻击学说，适合大多数场景，AI 复杂度可控
2. **渐进复杂**：玩家可通过切换学说解锁更高级战术
3. **复用现有 AI**：编队系统在现有 `AIController` 之上协调，不重写底层战斗逻辑
4. **物理一致**：僚机遵循相同的飞行物理，阵型保持通过目标点设定实现，不是瞬移
5. **玩家可控**：所有战术选择（阵型、学说、指令）由玩家决定，AI 在框架内自主执行细节

---

## 编队托管三段式（CLAUDE.md 摘出，2026-05-05）

实现位置：`scripts/aircraft/aircraft_formation.gd`。

| 距槽位距离 | 行为 |
|-----------|------|
| `>800px` 或过渡初期 | 纯追击归队（航向直指槽位 + 激进 bank） |
| `50~800px` | 航向混合长机与槽位 + 自然 bank 转弯（走真实物理） |
| `<50px` | 航向同步长机 + 极弱漂移修正（0.15×speed） |

这样消除了僚机振荡和平移感。阵型变换有 0.3~1.3 秒个体化反应延迟。
