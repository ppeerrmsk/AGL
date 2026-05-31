# 2026-05-31 — 小队凝聚（squad-cohesion）阶段 1 + 阶段 2 核心

spec: [docs/specs/systems/squad-cohesion.md](../specs/systems/squad-cohesion.md)（draft；§6 阶段 1 + 阶段 2 核心已派生，阶段 3-4 待续）

## 起因
用户反馈：小队（友 + 敌）整体对阵型非常不在意——飞着飞着一架绕一大圈"查无此人"、各打各的、没有焦点火力。
期望：共进退（焦点开火一个目标 / 绝大多数时候维持阵型 / 只在必要时分散互掩）。

## 诊断
现状把僚机设计成独立自由个体：`EngageMode.FREE` + 每机 2000px 自由扫描各咬最近敌机 +
`_is_target_already_squad_engaged` 主动分散到不同目标（反焦点开火）+ 交战中**无 leash**（BFM 把僚机带到任意远处）。

## 改动（阶段 1：leash + 阶段 2：凝聚默认）

### `scripts/ai_controller.gd`
- 新增常量 `SQUAD_LEASH_DIST=1800`（≈3600m）/ `SQUAD_LEASH_HYSTERESIS=0.5s` + per-AI `_squad_leash_timer`。
- `_process_engage` 顶部（drone 早 return 之后）新增 **leash 判定**：常规 squad 僚机距长机 > LEASH 持续 0.5s
  → `TargetSelection.disengage` 强制脱战回编队。**根治"绕一大圈查无此人"**。
  - 跳过：drone（上方已 return）/ `bvr_only`（F-47 远距逃跑手）/ `is_boss_attacker()` / hunter（`combat_zone_anchor != null`）——各有自己的远距语义。
- `squad_engage_mode` @export 默认 **FREE → FOLLOW_LEADER**：小队默认凝聚，僚机只打长机目标。

### `scripts/survivor/survivor_hud.gd`
- `_squad_engage_mode` 初值 0(FREE) → 1(FOLLOW_LEADER)，与 @export 默认同步（否则 HUD 按钮标签 / 首次切换方向错）。

## 行为结果
- **焦点开火**：玩家左键点敌机 → 控制机(=长机) `combat_target` → FOLLOW_LEADER 僚机全队跟打同一目标（天然饱和，
  anti-pile-on 仅在 FREE scan 路径故自动失效）。
- **维持阵型**：玩家不点目标时全队保持阵型（FOLLOW_LEADER 不做自由扫描）。
- **不游走**：任何模式下交战僚机超 leash 即被拉回——共进退。
- **开关保留**：HUD「交战模式」按钮仍可切回 FREE 放养。

## ⚠ 待续 / 风险
- **阶段 3（飞机目标留自由机互掩）未做**：目前飞机目标也全压（无自由机）。用户要求"打飞机以自由掩护为主、
  打地/船/BOSS 饱和"——自由机分流待与 squad-ai-escort 阶段 3（守后守护者）共用基础设施一起做。
- **敌方凝聚仅覆盖走 SQUAD_FOLLOW 路径的编队**：@export 默认翻转对"独立 try_engage 的敌方散兵"无效（它们不读
  squad_engage_mode）。leash 仍对所有 ENGAGE 僚机生效。完整敌方凝聚需阶段 4 排查各 enemy spawn 路径。
- **凝聚默认的体感**：FOLLOW_LEADER 下僚机只在玩家点目标时交战，不再自动咬附近威胁。这是用户明确要的凝聚，
  但 survivor 被围殴时可能觉得"僚机不主动帮忙"——可随时按 HUD 切 FREE。需 playtest 确认手感。

## 验证（待 playtest）
- [ ] 僚机不再绕远失踪（leash 生效，看 EventLogger "LEASH break-off"）。
- [ ] 点一个敌机 → 全队焦点压上同一目标。
- [ ] 不点目标 → 全队维持阵型一起走。
- [ ] HUD「交战模式」切 FREE → 恢复自主交战（但仍被 leash 约束）。
- [ ] Sentinel + Lv5+ 满编队 FPS 掉幅 < 15。

---

## 追加（同日）— 阶段 4 部分：敌方"成建制"

### 反馈
凝聚手感 OK，但"在敌人身上没通用"（战区里的敌人）。

### 诊断
- 敌方*编队*（`_spawn_squad`，2-4 架）其实已继承凝聚：`_create_enemy` 用 `AIController.new()` → 吃翻转后的
  `squad_engage_mode=FOLLOW_LEADER` 默认；register_wingman(set_state=true) → SQUAD_FOLLOW。leash 也已覆盖所有 ENGAGE 僚机。
- 真正缺口：**早期（lv < LATE_GAME_LEVEL=10）`min_squad_size=1`**，非精英敌机大量以**单机**刷出（`squad_size==1 → _spawn_single`）。
  单机无 leader/无阵型 → 凝聚学说无对象作用 → 玩家看到的"敌人不成小队"。

### 改动
`scripts/survivor/survivor_spawner.gd` `_spawn_wave`：非精英分支 `min_squad_size` 由 `2 if is_late_game else 1` → **恒 2**。
杂鱼始终 ≥2 架成编队走 SQUAD_FOLLOW；单机精英（MiG-31/Su-27/AF-03/早期 J-7）走 spawn_as_single 分支不受影响，保持孤狼设计。

### ⚠ 副作用 / 待观察
- 预算碎片时（凑不齐 2 架）该 spawn 轮 `break`，等下个 tick 重试 → 早期可能少量"成对才来"的节奏变化、敌机数略降。
  late-game 早就是这逻辑（已验证），现扩到全程。若早期觉得敌人变少/变难，回调为分级 min。
- flock（Tu-160/AH-64/CH-47）/ zone_mission 敌队未动（特殊编成，按需再说）。

### 验证（待 playtest）
- [ ] 战区敌机成对/成队出现并一起行动（焦点同一目标 + 不游走）。
- [ ] 单机精英（MiG-31 等）仍单独出现。
- [ ] 早期敌机数量 / 难度无明显异常。

---

## 追加（同日）— 第三交战模式 GUARD_REAR（守护后方）

### 需求
新增一个战术：长机攻击目标，僚机不打长机的进攻目标，只守长机后半球、攻击其中有威胁的敌机。
选项放进「交战模式」HUD 按钮（与 自由交战 / 跟随长机 同一循环）。

### 改动
- `ai_controller.gd` / `squad.gd`：`SquadEngageMode` / `EngageMode` 加 `GUARD_REAR = 2`。
- `squad_coordination.gd`：
  - `process_squad_follow` 新增 GUARD_REAR 分支——扫 `scan_leader_rear`（长机后半球 2500px 内最近敌机），
    有威胁 → `_enter_autonomous_engage` 拦截；无威胁 → 只保持编队守在长机身后，**绝不打长机前方目标**。
  - 新增 `_enter_autonomous_engage(ai, tgt, tactic_name)` 共用入口（FREE 就近 / GUARD_REAR 后方 共用 ENGAGE 过渡）。
  - `scan_leader_rear` 加 `_is_target_already_squad_engaged` 跳过 → 多守护者分摊不同后方威胁，不挤一个。
- `survivor_hud.gd`：交战模式按钮二态→**三态循环** `(mode+1)%3`；新增 `_squad_engage_mode_label()`（三语标签）。
- `i18n/translations.csv`：`SQUAD_ENGAGE_GUARD`（守护后方/Guard Rear/後方警戒）+ `TACTIC_GUARD_REAR`。

### 与 escort/cohesion 阶段3 的关系
阶段3 是"自动指派单机守后"；GUARD_REAR 是**玩家主动选的整队守后学说**（全体僚机守后）。两者可并存。

### 验证（待 playtest）
- [ ] HUD 按钮循环出现"守护后方"；选中后僚机不再追长机的进攻目标。
- [ ] 后方出现敌机 → 僚机去拦截；前方敌机（长机在打的）僚机不管。
- [ ] 无后方威胁 → 僚机保持编队守在长机身后。
- [ ] 多架僚机分摊不同后方威胁，不挤同一个。
- [ ] 切到其它模式立即生效（强制脱离当前交战）。

---

## 追加（同日）— 战术=阵型 + 阵型系统重构 + 自由交战范围收紧

### 用户决策
1. 废弃手动切阵型（不再用按键/菜单切）；战术直接等同于阵型。
2. 敌方杂鱼登场随机阵型（除 Trail 外），只换站位、行为不变（凝聚默认）。精英/Boss 显式固定阵型不进随机。
3. 自由交战不该一点就散开去够远敌——收到较近范围。

### 改动
- `squad.gd`：新增 `formation_for_engage_mode(mode)`（自由→COMBAT_SPREAD / 跟随→FINGER_FOUR / 守后→WEDGE）
  + `random_formation()`（除 Trail 外随机）。`cycle_formation` 保留（沙盒/debug 仍用）。
- `survivor_hud.gd`：**删除「阵型」按钮**（创建 / `_btn_squad_formation` 字段 / 文本更新 / `_on_squad_formation_pressed` 全删）；
  `_on_squad_engage_pressed` 切模式时 `sq.formation = Squad.formation_for_engage_mode(mode)`。
- `survivor_mode.gd`：删 **KEY_5**（阵型切换键）；`_spawn_starting_wingmen` 玩家队初始阵型显式设为 FOLLOW_LEADER 绑定的 Finger Four。
- `survivor_spawner.gd`：`_spawn_squad`（杂鱼路径）`sq.formation = Squad.random_formation()`。精英(ace_squad/mother_goose/commander)各自建队不走此路径 → 固定。
- `ai_controller.gd`：`SQUAD_FREE_SCAN_RANGE` 2000→800px。

### 阵型↔战术映射（玩家）
| 交战模式 | 阵型 | 作用 |
|---|---|---|
| 自由交战 | Combat Spread | 铺开搜索 + 互看六点 |
| 跟随长机 | Finger Four | 标准凝聚 |
| 守护后方 | Wedge | 僚机后方锥内罩六点 |

Trail（纵列）现无人使用（玩家不绑、AI 随机排除）——留着不动。

### 验证（待 playtest）
- [ ] HUD 不再有「阵型」按钮；KEY_5 无效；KEY_6/按钮三态循环切战术同时换阵型。
- [ ] 切到自由→并排展开；跟随→指尖四点；守后→楔形。
- [ ] 自由交战时僚机只接管 ~1.6km 内靠近的敌机，不再立刻散开跑远。
- [ ] 敌方杂鱼每队登场阵型不一（随机），但行为仍焦点凝聚。
- [ ] 精英/Boss 阵型固定（不随机）。

---

## 追加（同日）— 阶段3 自由机互掩 + 阶段4 zone_mission

### 自由机互掩（双重攻击学说）
- `squad_coordination.gd`：
  - 抽出 `_guard_rear_tick(ai, delta)`（GUARD_REAR 模式 + 自由机 共用守后行为：扫 scan_leader_rear，有威胁拦截、无则保持编队）。GUARD_REAR 分支改调它。
  - 新增 `_should_be_free_fighter(ai, target)`：仅 FOLLOW_LEADER + 目标是飞机(非 BOSS) + 本队 ≥2 架存活自主僚机 → squad_index 最大的一架是自由机。地面/船/BOSS → false（全员饱和）。瞬态、每 tick 按存活成员重算（_ai_ref.squad_index）→ 切换/减员自愈。
  - 新增 `_is_boss_target`（category meta 含 "boss"）。
  - 焦点开火入口（follow leader target）：是自由机 → `_guard_rear_tick` 守后并 return，不打长机目标。
- 效果：玩家点一架敌机 → 长机 + N-1 僚机压上，**留 1 架（最高号机）守长机六点**；点地面/船/BOSS → 全员饱和压上。

### zone_mission（阶段4 用户只要 zone）
- zone 的 air squadron / `_spawn_zone_defenders` 早已 register_wingman(set_state=true)→SQUAD_FOLLOW + AIController.new() 吃 FOLLOW_LEADER 默认 → **凝聚已自动继承**，无需额外改。
- 仅补 `sq.formation = Squad.random_formation()`（两处）→ 阵型随机化，与战区杂鱼一致。
- 随机奖励目标无 AI → 跳过；flock(Tu-160/AH-64/CH-47) 用户决定暂不动。

### 验证（待 playtest）
- [ ] 跟随长机模式点一架敌机：留一架僚机不扑、守在长机后方（看 EventLogger 它走 GUARD REAR / 保持编队）。
- [ ] 点地面/船/BOSS：全员压上，不留自由机。
- [ ] 僚机只剩 1 架时不留自由机（它去打）。
- [ ] 自由机阵亡/切换长机 → 另一架自动补位当自由机。
- [ ] zone 任务敌队焦点凝聚 + 阵型随机。

---

## 追加（同日）— 守护后方"真威胁"判定（修守护者去打远处闲敌）

### 反馈
GUARD_REAR 模式下守护者没在守后方，反而飞去打距离很远、暂无威胁的目标。

### 诊断
`scan_leader_rear` 抓"后半球 + COVER_SCAN_RANGE(2500px≈5km) 内最近敌机"，**无威胁判定** → 身后 4-5km 闲晃的 UAV 也被当目标去打；且 5km > leash(1800px) 还会和 leash 拉扯。

### 修复（squad_coordination.gd scan_leader_rear）
- 范围收到 **REAR_GUARD_RANGE=1200px(≈2.4km)** < leash，守护者贴着长机守不飞远（ai_controller.gd 新常量）。
- 加**真威胁判定**：只拦 ① 正在咬长机（`leader.engaging_me`）或 ② 正朝长机飞来（`enemy_fwd · (leader-enemy) > 0.3`）的敌机；远处闲晃的忽略。
- COVER_SCAN_RANGE 保留给 escort 评分（近长机加权），不动。

### 验证（待 playtest）
- [ ] 守护者贴在长机后方守，不再飞 4-5km 去打闲敌。
- [ ] 真有敌机咬长机 / 从后方扑来 → 守护者上前拦截。
- [ ] 身后远处不构成威胁的敌机 → 守护者不理，保持守位。

---

## 追加（同日）— 守后专属紧 leash + 守护者打威胁长机的地面 AA（导弹远射）

### #1 守后专属紧 leash
- `ai_controller.gd`：`REAR_GUARD_LEASH_DIST=1200px`（守后贴身，区别于 FREE/FOLLOW 的 SQUAD_LEASH_DIST=1800）；
  `effective_squad_leash()` 按 squad_engage_mode 选；ENGAGE/EVADE 两处 leash 检查都改用它。
- `REAR_GUARD_RANGE` 1200→900（< leash，留拦截+追的余量）。

### #2 守护者打威胁长机的地面 AA（用户：地面单位威胁玩家时僚机也打，AA 优先导弹避免受伤）
- `squad_coordination.gd` 新增 `scan_leader_threat_ground`：长机 SQUAD_LEASH_DIST 内的 SAM/AAGun（真防空威胁）→ 守护者拦截。
- `_guard_rear_tick`：空中后方威胁优先；没有则打地面 AA。
- **导弹远射**：靠默认 `weapon_preference=PREFER_MISSILE` + `BfmIntent.ground_strafe` 的导弹模式（"导弹包络稳定推进"，no AB、不贴脸 strafe）→ 守护者从导弹包络外远射 AA，不冲进 AA 火力。
- `effective_squad_leash()`：守后打地面目标时放宽到 1800px（导弹 standoff 够得着，不被紧 leash 拽回）。
- 类型放宽：`_enter_autonomous_engage(tgt: CombatUnit)` / `_is_target_already_squad_engaged(target: CombatUnit)`（原 Aircraft）。

### ⚠ 待观察
- 非 tactical_preference_user 的僚机在 GROUND_STRAFE 导弹模式仍会下降到目标高度（bfm_intent.ground_strafe 行 347）→ 可能仍靠近 AA。若实测吃伤害多，再让守护者打地面时维持高度（高空 AGM）。
- 坦克/船等非 AA 不算威胁（不engage）；naval 暂不纳入。

### 验证（待 playtest）
- [ ] 守护者贴长机更近（紧 leash 1200）；闲置守在后方不远游。
- [ ] 场上有 SAM/AAA 威胁时，守护者用导弹远射拔掉它，不贴脸 strafe。
- [ ] 打地面 AA 时允许飞到 standoff 距离（不被紧 leash 立刻拽回）。
