---
id: squad-cohesion
kind: system
status: in-progress   # 阶段 1-3 + 阶段 4 主体已落地；剩联调/调参/§5 playtest → done
schema_version: 1
spec_version: 2
owner: noelu
depends_on: [squad-ai-escort, squad-control-switching, squad-tactics-design]
reconstruction_complete: false
---

# 小队凝聚学说 —— 共进退 / 焦点开火 / 阵型纪律 / 防游走 leash

> 玩家视角：你的小队（以及敌方编队）应该像一个小队，而不是一盘散沙。绝大多数时候它们维持阵型一起走；要打就一起打同一个目标；只有真有战术必要（互掩、包夹、守后）才分散。再也不会"飞着飞着一架不知道绕哪去了，查无此人"。

## 1. 设计意图（Why）

现状：僚机（友 + 敌）被设计成**独立自由的个体**——`EngageMode.FREE` + 每机 2000px 自由扫描各自咬最近的敌机，`_is_target_already_squad_engaged` 还**主动**把多机推到不同目标上（反焦点开火），且交战中**无 leash**，BFM（extension/yo-yo/lag）把僚机带到任意远处直到目标死。三股力合起来 = 整体散、无饱和火力、单机游走失踪。

本 spec 把小队从"散兵集合"改成"凝聚小队"。**用户三目标**：
1. **焦点开火**：共同攻击一个目标，靠饱和火力一起射击。
2. **维持阵型**：绝大多数时候保持阵型一起行动。
3. **必要才分散**：只有互掩 / 包夹 / 守后这类战术动作才散开。

**适用范围（用户决策：全部小队，友 + 敌）**：玩家队 + 所有敌方编队都吃凝聚逻辑。让整个战场都是"成建制的小队"对抗，而不是各打各的。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 3（信息察觉优先）**：✅ 焦点开火 / 阵型收拢 / leash 拉回都是玩家肉眼可见的行为差异。
- **原则 7（战场热闹 + AI 演戏）**：✅ "小队共进退"是强演戏感；保留 FREE 开关 + 必要时分散，避免变成呆板列队。
- **原则 8（BOSS / 敌方真聪明）**：✅ 敌方编队懂得焦点开火 + 留自由机掩护 = 真战术，比散兵更有压迫感。
- **原则 11（60 FPS）**：✅ leash = O(1) 距长机距离判定；焦点开火复用既有 FOLLOW_LEADER 路径；目标类型分流只读 target.meta，无新全场扫描。

**反模式规避**：
- ❌ 不做"看不出差别的暗调"——凝聚行为必须可感知（原则 3）。
- ❌ 不把小队焊死成永不分散的呆板列队（违背原则 7）——保留 FREE 开关 + 战术分散。
- ❌ 不引入新全场扫描（性能守则）——leash 走 O(1)。

## 2. 数据定义（What —— 权威源）

### 2.1 交战模式开关（三态，HUD 按钮循环）

| 概念 | 定义 |
|---|---|
| `Squad.engage_mode` / `AIController.squad_engage_mode` | **FREE(0)**=僚机各自就近自由交战 + 协同长机目标；**FOLLOW_LEADER(1)**=僚机只攻击长机当前目标（焦点开火 + 凝聚）；**GUARD_REAR(2)**=僚机**不打长机的进攻目标**，只盯长机六点钟后半球、攻击其中威胁，无威胁则守在长机身后保持编队。**实际生效的是 per-AI `squad_engage_mode`**（squad_coordination 读它）。 |
| 玩家队切换 | HUD「交战模式」按钮 `_btn_squad_engage`（survivor_hud `_on_squad_engage_pressed`）——**三态循环** FREE→FOLLOW_LEADER→GUARD_REAR；切换时强制僚机脱离当前交战立即回编队。 |
| GUARD_REAR 行为 | `_guard_rear_tick`：① 后半球空中真威胁（`scan_leader_rear`，REAR_GUARD_RANGE=900px、engaging_me 或 approaching dot>0.3，忽略远处闲敌）→ 拦截；② 否则威胁长机的**地面 AA**（`scan_leader_threat_ground`：SAM/AAA，SQUAD_LEASH_DIST 内）→ 默认 PREFER_MISSILE + GROUND_STRAFE 导弹模式**远射拔掉**，不贴脸 strafe 吃 AA 火力；③ 都没有→保持编队守后。anti-pile-on 分摊。 |
| GUARD_REAR leash | 守后专属紧 leash `REAR_GUARD_LEASH_DIST=1200px(贴身)`（`effective_squad_leash()`，区别于 FREE/FOLLOW 的 1800）；但**打地面 AA 时放宽回 1800** 让导弹 standoff 够得着。空中守护/闲置用紧 leash。 |
| FREE 范围 | 自由交战只接管**靠近**的敌机：`SQUAD_FREE_SCAN_RANGE=1500px(=3km)`（2026-05-31：2000→800→1500），不再一点就散开去够 4km 外目标，且 < leash 1800px。 |
| **★ 战术=阵型（绑定，本轮）** | **玩家手动切阵型已废弃**（删 HUD「阵型」按钮 + KEY_5）。交战模式直接决定阵型：自由→COMBAT_SPREAD / 跟随长机→FINGER_FOUR / 守后→WEDGE（`Squad.formation_for_engage_mode`）。切交战模式时同步设 `sq.formation`。 |
| **★ 敌方随机阵型（本轮）** | 普通杂鱼 `survivor_spawner._spawn_squad` 登场时 `sq.formation = Squad.random_formation()`（除 Trail 外随机），**只换站位、行为仍走凝聚默认**（用户决策）。精英/Boss 不走此路径（各自建队显式固定阵型）。Trail 现无人使用（玩家不绑、AI 不随机）。 |
| **默认值（用户已确认）** | 玩家队 + 敌方队默认 = **FOLLOW_LEADER（凝聚）**。FREE 退化为玩家主动选的"放养"模式。落地方式：`AIController.squad_engage_mode` @export 默认改 FOLLOW_LEADER + HUD `_squad_engage_mode` 初值同步。 |
| **焦点开火自动成立** | FOLLOW_LEADER 下僚机直接打 `leader.combat_target`（玩家左键点敌机 → 控制机/长机 combat_target → 全队跟打），**不走 FREE scan**，故 anti-pile-on（仅在 scan 路径）自动失效 = 天然饱和。玩家不点目标时全队维持阵型。 |

### 2.2 防游走 leash（新增，所有队）

| 常量 | 建议值 | 说明 |
|---|---|---|
| `SQUAD_LEASH_DIST` | 1800px（≈3600m，调参定） | 交战僚机距**长机**超过此距离 → 强制 break off 回编队 |
| `SQUAD_LEASH_HYSTERESIS` | 0.5 s | 越界持续此时长才触发（防边界抖动），瞬态每 tick 评估 |

- leash 作用于**有 squad、非长机、处于 ENGAGE 或 EVADE_MISSILE 的僚机**。长机是锚点不受 leash。
  ⚠ **EVADE 也必须 leash**（2026-05-31 补）：否则僚机被地面 SAM 反复打 → 一路躲到天边（实测 7km），守后/编队名存实亡。躲弹中超 leash → 停躲归队，近处仍有真威胁会重新进躲。
- 触发 = 走既有 disengage → SQUAD_FOLLOW 回编队路径（不新写归队物理）。
- 与 escort 守后、FREE/FOLLOW 模式正交：无论哪种模式，僚机都不许游走出 leash。

### 2.3 目标类型决定交战学说（新增）

小队交战一个目标时，按**目标类型**分流（用户决策）：

| 目标类型 | 学说 | 行为 |
|---|---|---|
| **飞机**（机动威胁） | 双重攻击（互掩为主） | 指派部分僚机为交战机压目标，**留 ≥1 架自由机**不进攻、守交战机后半球 / 盯第二威胁。保留 spread（不全压）。 |
| **地面 / 船 / BOSS**（低机动 / 高 HP） | 饱和火力 | **全员**压同一目标，关闭 anti-pile-on，最大化 DPS 速杀。 |

判定：`target.is_ground()` / 船类 meta / `category == "boss"` 等 → 饱和；否则（Aircraft 且非 boss）→ 双重攻击。具体判定键见 §3.3。

## 3. 行为与公式（How）

### 3.1 凝聚模式下的僚机决策（FOLLOW_LEADER）

```
每决策 tick（僚机，有 squad、非长机、自主）：
1. leash 检查：dist(self, leader) > SQUAD_LEASH_DIST 持续 > HYSTERESIS → break off → SQUAD_FOLLOW，跳过以下
2. 长机有目标 T：
   - T 是飞机 → 进双重攻击分流（§3.3）：自己是交战机则压 T，是自由机则守后/盯二号威胁
   - T 是地/船/BOSS → 饱和：直接压 T（关 anti-pile-on）
3. 长机无目标 → 维持阵型（SQUAD_FOLLOW，现有）
```

FREE 模式：维持现状（自由扫描就近交战），但**仍受 §2.2 leash 约束**（这是 FREE 模式下"绕一大圈失踪"的根治）。

### 3.2 防游走 leash（目标：共进退，根治"查无此人"）

- 在 `_process_engage`（或僚机 ENGAGE tick 入口）加 O(1) 判定：`dist_to_leader > SQUAD_LEASH_DIST` 累计 > `SQUAD_LEASH_HYSTERESIS` → 调用既有 disengage → 回 SQUAD_FOLLOW。
- 长机 / 无 squad / 已在 SQUAD_FOLLOW 的不判。
- BOSS UAV 已有自己的 RECALL_LEASH（mother_goose_controller），不重复套用——本 leash 只管常规 squad 僚机。
- **玩家点名例外**：僚机正在跟打长机当前的 `commanded_target` 时，命令优先级高于普通归队 leash；长机取消、改点或目标失效后例外立即结束。导弹规避仍按求生优先处理。

### 3.3 目标类型分流 + 自由机指派（目标：焦点开火 / 必要才分散）

- **饱和（地/船/BOSS）**：小队全员目标 = 同一个 T。关闭 `_is_target_already_squad_engaged` 的"避免多机咬一个"限制（仅对该目标）。
- **双重攻击（飞机）**：按 squad_index 指派——一架（建议最高 index 或最远的一架）为**自由机**（不进攻、守交战机后半球、盯第二威胁），其余为交战机压 T。自由机角色瞬态、每 tick 按当前小队成员重算（与 escort 守护者同思路，禁持久属性 → 切换 / 减员自愈）。
- 复用 escort 的 `scan_leader_rear` / 守后位（与 squad-ai-escort 阶段 3 共用一套自由机/守护者基础设施）。

### 3.4 与既有系统的交互

| 系统 | 交互 |
|---|---|
| **squad-ai-escort** | escort（护卫评分=反杀咬长机者）与 cohesion（焦点+leash+纪律）正交叠加：凝聚护卫小队焦点打长机目标、被 leash、escort 评分仍在 FREE 分支提权咬长机者。自由机/守护者基础设施共用。 |
| **squad-control-switching** | leash / 自由机指派键于"当前长机"，操控切换经 leader_changed 自愈（同 escort §3.4 红线：禁持久属性）。长机不被 leash / 不当自由机。 |
| **敌方编队** | 敌方队默认 FOLLOW_LEADER：长机 try_engage 选目标，僚机焦点跟打 + leash。敌方旗舰打玩家时整队压玩家 = 更强压迫感。 |

### 3.5 性能（守则强制）
- leash = 每僚机 O(1) 距长机距离；无全场遍历。
- 焦点开火复用 FOLLOW_LEADER 既有路径；目标类型只读 target 类型 / meta。
- 自由机指派复用 escort 守后基础设施（已节流）。
- 验收必跑 Sentinel + Lv5+ 满编队压测。

### 3.6 阵型槽位双频率架构（实时跟随，消除"慢一拍"）★

**问题**：玩家频繁点地图下移动指令时，僚机跟随滞后、阵型拖泥带水。根因是槽位更新有两条脱节频率：
- 旧实现在 **AI 分频 tick（~10~20Hz）** 算槽位 `leader.pos + offset.rotated(leader.heading)`，写成一个**冻结的世界坐标死点**；
- 60Hz 的编队跟随逻辑读的就是这个死点。长机转弯/平移时，正确槽位应随长机机体系实时旋转，僚机却要等下一个 AI tick 才更新 → 50~100ms 内追"过去的槽位"。

**架构**：把槽位拆成两部分，分别在各自合适的频率更新：

| 部分 | 内容 | 频率 | 位置 |
|---|---|---|---|
| **慢变（committed 偏移）** | 用哪个阵型、第几槽（长机本地系偏移，未旋转） | AI tick（~10~20Hz） | squad_coordination 写 `_formation_offset_committed`；换阵型时经 react 延迟错落采纳 |
| **快变（世界槽位）** | committed 偏移旋进**长机当前机体系**得世界坐标 | **每物理帧 60Hz** | AircraftFormation 跟随逻辑每帧实时算，长机一动全队同帧跟动 |

**优雅性**（俯视下玩家全程可见，要真实编队的优雅，不靠强扭轨迹）：实时槽位本身让僚机靠既有 bank/盘旋自然到位，因此：
- 旧"延迟+突跳伪造曲线"机制自动失效（曲线由实时槽位 + 物理 bank 自然产生）。
- 旧"直接挪坐标"的归位修正降级为**稳态亚像素吸附**（仅"几乎到位 + 稳态巡航"时清残差，肉眼不可见）；动态归位全交给真实转弯。

**范围**：改在共享编队跟随层（无 team 分叉），**友机与敌机编队同时生效**。

**性能**：每帧每僚机仅新增 1 次向量旋转 + 回写，无分配、无全场扫描。

**不破坏历史编队 bug 修复**：leader-frame 槽位（防方位角摆动）、bank 翻转守卫、leader-bank 混合、roll/turn rate-limit、速度 clamp 全部不动；实时槽位让槽位距离更连续（不再每 AI tick 阶跃），分支边界穿越反而减少。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `squad_engage_mode` 默认值 | 玩家 + 敌方队默认凝聚 | 改（建队处默认 + HUD 初值） |
| `SQUAD_LEASH_DIST` / `SQUAD_LEASH_HYSTERESIS` | leash 常量 + 计时 | **新增**（ai_controller） |
| leash 判定 | ENGAGE 僚机越界 break off | **新增**（ai_controller `_process_engage` 或 squad_coordination） |
| 目标类型分流 | 饱和 vs 双重攻击 | **新增**（squad_coordination：交战目标分类 + anti-pile-on 条件化 + 自由机指派） |
| anti-pile-on 条件化 | 饱和模式关闭 | 改（`_is_target_already_squad_engaged` 调用处加目标类型分支） |
| 自由机指派 | 飞机目标留一机掩护 | **新增**（复用 escort 守护者基础设施） |
| HUD 按钮 | 凝聚/自由开关 | 复用（已有）；默认初值改 |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **目标 1 焦点开火**：凝聚模式下打地面/船/BOSS 时全员压同一目标（饱和）；打飞机时多数压目标 + 留一架自由机掩护。
- [ ] **目标 2 维持阵型**：无敌情 / 长机无目标时小队严守阵型一起走，不再单机乱跑。
- [ ] **目标 3 必要才分散**：仅交战飞机目标时分出交战机/自由机；脱战后收拢归队。
- [ ] **防游走 leash**：无玩家点名目标时，交战僚机距长机超 leash 即 break off 回编队——不再"绕一大圈查无此人"；跟打长机玩家点名目标时不被普通归队覆盖。
- [ ] **开关**：玩家 HUD「交战模式」按钮在 凝聚(FOLLOW_LEADER) ↔ 自由(FREE) 间切换，立即生效。
- [ ] **范围**：友方 + 敌方编队都凝聚；敌方旗舰交战时整队焦点压目标。
- [ ] **切换自愈**：操控切换 / 减员后 leash / 自由机指派立即以新长机 / 新成员重算，无残留。
- [ ] 性能：leash O(1)、无新全场遍历；Sentinel + Lv5+ 满编队 FPS 掉幅 < 15。
- [ ] i18n：HUD 模式文本 / 新增无线电提示走 tr() 三语。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 防游走 leash（最高优先，根治"查无此人"）✅（2026-05-31）
- [x] `SQUAD_LEASH_DIST=1800` / `SQUAD_LEASH_HYSTERESIS=0.5` 常量 + per-AI `_squad_leash_timer`。
- [x] `_process_engage` 僚机 leash 判定 → 越界 break off（TargetSelection.disengage）回 SQUAD_FOLLOW（所有队）。drone/bvr_only/boss/hunter 跳过。
- [ ] 验证 FREE / FOLLOW 两模式下都不再游走失踪（playtest）。

### 阶段 2 — 凝聚默认 + 焦点开火（地/船/BOSS 饱和）✅核心（2026-05-31）
- [x] 玩家 + 敌方队默认 squad_engage_mode = FOLLOW_LEADER（@export 默认 + HUD 初值）。
- [x] 焦点开火 + 饱和：FOLLOW_LEADER 下全员打 leader.combat_target，不走 scan → anti-pile-on 自动失效 = 天然饱和（所有目标类型）。
- 注：目标类型分类目前只用于阶段 3 的"飞机目标留自由机"；阶段 2 下飞机目标也全压（待阶段 3 细分）。
- ⚠ 敌方队仅对走 SQUAD_FOLLOW 路径的编队生效；独立 try_engage 的敌方散兵需阶段 4 排查 spawn 路径。

### 阶段 3 — 双重攻击（飞机目标留自由机掩护）✅（2026-05-31）
- [x] 飞机目标分流：FOLLOW_LEADER 焦点打飞机(非 BOSS) + 本队 ≥2 架自主僚机时，指定 squad_index 最大的一架为**自由机**（不进攻、守长机后半球）；其余压目标。地面/船/BOSS → 不留自由机(饱和)。`_should_be_free_fighter` + `_guard_rear_tick`（复用 GUARD_REAR 守后行为）。
- [x] 自由机瞬态键于当前存活成员（每 tick 重算 max squad_index），切换/减员自愈，禁持久属性。
- 注：escort 阶段3"长机后半球自动守护者"用同一套 `scan_leader_rear`/`_enter_autonomous_engage`；本阶段已落地其僚机侧逻辑。

### 阶段 4 — 敌方"成建制" + 联调 + 调参
- [x] **敌方杂鱼成建制**（2026-05-31）：`survivor_spawner._spawn_wave` 非精英敌机 `min_squad_size` 恒 2。单机精英走 spawn_as_single 保持孤狼。
- [x] **zone_mission 敌队**（2026-05-31）：凝聚已由 FOLLOW_LEADER @export 默认自动继承（zone 的 air squadron / `_spawn_zone_defenders` 都 register_wingman(set_state=true)→SQUAD_FOLLOW）；补 `sq.formation = Squad.random_formation()` 随机阵型。**随机奖励目标无 AI → 跳过**。flock(Tu-160/AH-64/CH-47) 暂不动（用户决策）。
- [ ] 与 squad-ai-escort / squad-control-switching 联调（leash × leader_changed × escort 守后无竞态）。
- [ ] 调 SQUAD_LEASH_DIST / 自由机数量至体感自然。
- [ ] 跑 §5 全部验收 + 性能压测。
- [ ] 更新 §7 锚点 + reference 索引 + known-seams。status → done。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 凝聚/自由开关字段 | `scripts/squad.gd`（engage_mode）/ `scripts/ai_controller.gd`（squad_engage_mode）/ `scripts/survivor/survivor_hud.gd`（HUD 按钮） |
| leash 常量 / 判定 | `scripts/ai_controller.gd` |
| 焦点开火 / 目标类型分流 / 自由机指派 | `scripts/ai/squad_coordination.gd` |
| anti-pile-on 条件化 | `scripts/ai/squad_coordination.gd`（_is_target_already_squad_engaged 调用处） |
| 建队默认模式 | `squad_factory.gd` / `survivor_mode.gd` / 敌方建队处 |
| 敌方成建制（杂鱼 ≥2 编队） | `scripts/survivor/survivor_spawner.gd`（_spawn_wave min_squad_size 恒 2；单机精英走 spawn_as_single） |
| 阵型槽位双频率（实时跟随，§3.6） | 慢变写：`scripts/ai/squad_coordination.gd`（process_squad_follow → `_formation_offset_committed`）+ `scripts/ai_controller.gd`（字段）；快变读：`scripts/aircraft/aircraft_formation.gd`（`_build_context` 实时旋转 + `_update_position` 稳态吸附）；槽位源 `scripts/squad.gd`（get_formation_offset） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-31 | 1 | 初稿（draft）：小队凝聚三目标（焦点开火 / 维持阵型 / 必要才分散）。决策定型：**全部小队（友+敌）** / 复用既有 FREE↔FOLLOW_LEADER 开关 / **目标类型分流**（地/船/BOSS 饱和、飞机留自由机互掩）/ **新增防游走 leash**（根治单机游走失踪）。与 squad-ai-escort 共用自由机/守护者基础设施、切换自愈红线（禁持久属性）。 |
| 2026-05-31 | 1 | **派生代码阶段 1 + 阶段 2 核心**（用户已确认默认凝聚 friend+enemy）：新增 leash（`_process_engage` 僚机越界 break-off，drone/bvr/boss/hunter 跳过）；`squad_engage_mode` 默认 FREE→FOLLOW_LEADER + HUD 初值同步 → 焦点开火 + 维持阵型天然成立。**阶段 3（飞机目标留自由机）+ 阶段 4（敌方散兵 spawn 路径排查）待续**。详见 changelogs/2026-05-31-squad-cohesion-1-2.md。 |
| 2026-05-31 | 1 | **阶段 4 部分**：用户反馈凝聚"在敌人身上没通用"。诊断=敌方杂鱼早期（lv<10）多以单机刷出（min_squad_size=1），无 leader/阵型故无小队感；敌方*编队*其实已继承 FOLLOW_LEADER+leash。修：`survivor_spawner` 非精英 min_squad_size 恒 2 → 杂鱼始终成建制编队。单机精英保持孤狼。 |
| 2026-05-31 | 1 | **新增第三交战模式 GUARD_REAR（守护后方）**（用户需求）：长机进攻、僚机专职守长机后半球、只打后半球威胁。HUD「交战模式」按钮由二态改**三态循环**。复用 scan_leader_rear（加 anti-pile-on 分摊）+ 新 `_enter_autonomous_engage` 共用入口。i18n: SQUAD_ENGAGE_GUARD / TACTIC_GUARD_REAR 三语。这是 escort/cohesion 阶段3"守后"的**玩家可选整队学说**版本（区别于自动指派单机守后）。 |
| 2026-05-31 | 1 | **战术=阵型 + 阵型系统重构**（用户决策）：①废弃玩家手动切阵型（删 HUD 阵型按钮 + KEY_5）；交战模式直接绑定阵型（自由→Combat Spread / 跟随→Finger Four / 守后→Wedge，`Squad.formation_for_engage_mode`）。②敌方杂鱼 `_spawn_squad` 登场随机阵型（除 Trail 外，`Squad.random_formation`），**只换站位行为不变**；精英/Boss 显式固定不进随机。③FREE 搜索范围 2000→800px（后又调 3km=1500px）。Trail 现无人使用。 |
| 2026-05-31 | 1 | **阶段 3 自由机互掩**（用户：更有战术感）：FOLLOW_LEADER 焦点打飞机(非 BOSS)且 ≥2 僚机时，squad_index 最大的一架转"自由机"守长机后半球（`_should_be_free_fighter` + `_guard_rear_tick` 复用 GUARD_REAR）；地/船/BOSS 饱和不留。瞬态自愈。**阶段 4 zone_mission**：凝聚已由默认继承，补随机阵型；随机奖励目标无 AI 跳过、flock 暂不动。 |
| 2026-06-07 | 1 | **状态对齐**（status draft→in-progress）：核对确认阶段 1-3 + 阶段 4 主体（敌方杂鱼成建制 / zone_mission 随机阵型）均已落地（commit 04a7a44）。**阶段 4 未尽项**：与 squad-ai-escort / squad-control-switching 三方联调（leash × leader_changed × 守后无竞态）、SQUAD_LEASH_DIST / 自由机数量调参、跑 §5 全部验收 + 性能压测——均为 playtest 项，未代跑。验收通过后转 done。 |
| 2026-06-07 | 1 | **机身颤抖多层根治 + 无头测试 harness**：编队 bank 改"转向速率驱动协调转弯"(替代 leader-bank 镜像，消除原地打滚)；分支迟滞 + bias 死区 + target_heading/bank EMA(消除小幅 flutter)；LOD0 补 formation 分支(屏内僚机终于走 update_follow)；战斗侧 compute_target_bank 台阶→连续斜坡 + 过冲补偿改滚出精确积分临界阻尼 + combat_full_bank_diff 放宽；clear_formation 清 target_position；规避承诺 break 方向；leash 拽回设冷却；formation 分支补 flare 更新。新增 `test_turn_physics.gd`(无头量化 bank 反转) + `--bench=demo`(自动战斗可视)。残留：慢速机激进缠斗欠阻尼大坡反转(SEAM-012，待 PD 重设计)。详见 changelogs/2026-06-07-bank-twitch-rootfix-and-test-harness.md。 |
| 2026-06-07 | 1 | **新增 §3.6 阵型槽位双频率架构（实时跟随，消除慢一拍）**（用户反馈：玩家频繁点地图时僚机慢一拍、阵型拖泥带水；要真实编队的优雅，不靠强扭轨迹）。改 `aircraft_formation.gd:_build_context` 槽位来源：冻结 `target_position` → 每帧 `_formation_offset_committed.rotated(leader.heading)` 实时算（squad_coordination 在 AI tick 写 committed 偏移 + 回写 target_position 保一致）。优雅性：去两处非物理强扭——"突跳伪造曲线"自动失效（订正注释）、`_update_position` 直接挪坐标降级为稳态亚像素吸附（FORM_SETTLE_DIST=25 / STRENGTH=0.15）。共享层 → 友/敌同时生效。历史 10 bug 修复结构零触碰。**首轮（核心修复）；"协调盘旋"增强延后调参阶段**。待 §5 playtest 验收。详见 changelogs/2026-06-07-formation-realtime-slot.md。 |
| 2026-08-03 | 2 | 玩家点名目标高于普通归队：跟打长机 `commanded_target` 的僚机豁免 leash；取消/改点后恢复正常凝聚，导弹规避仍优先。 |
