---
id: squad-cohesion
kind: system
status: in-progress   # 阶段 1-4 旧凝聚主体已落地；v3 阶段 5 阵型攻击/多 Element 待实现与验收
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [squad-ai-escort, squad-control-switching, squad-tactics-design]
reconstruction_complete: false
---

# 小队凝聚学说 —— 共进退 / 焦点开火 / 阵型纪律 / 防游走 leash

> 玩家视角：你的小队（以及敌方编队）应该像一个小队，而不是一盘散沙。绝大多数时候它们维持阵型一起走、以阵型形成攻击几何并从阵位开火；只有真有战术必要（规避、互掩、包夹、守后）才短时分散，然后先重整再进入下一轮攻击。再也不会“接敌同拍全员解队，随后各打各的”。

## 1. 设计意图（Why）

历史根因：僚机（友 + 敌）曾被设计成**独立自由的个体**——`EngageMode.FREE` + 每机自由扫描各自咬最近目标，且交战中无 leash。阶段 1～4 已补默认 FOLLOW、焦点目标与 leash，但当前 `process_squad_follow` 在长机取得目标后仍让多数僚机 `clear_formation()` 并进入独立 ENGAGE/BFM；所以出生和巡航时像编队，开战后仍会迅速散成多个单机。

本 spec 把小队从"散兵集合"改成"凝聚小队"。**用户三目标**：
1. **焦点开火**：共同攻击一个目标，靠饱和火力一起射击。
2. **维持阵型**：绝大多数时候保持阵型一起行动。
3. **必要才分散**：只有互掩 / 包夹 / 守后这类战术动作才散开。
4. **阵型攻击优先**：获得目标本身不再是解散阵型的理由；普通攻击先由长机形成几何，僚机从槽位机会开火。

**适用范围（用户决策：全部小队，友 + 敌）**：玩家队 + 所有敌方编队都吃凝聚逻辑。让整个战场都是"成建制的小队"对抗，而不是各打各的。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 3（信息察觉优先）**：✅ 焦点开火 / 阵型收拢 / leash 拉回都是玩家肉眼可见的行为差异。
- **原则 7（战场热闹 + AI 演戏）**：✅ "小队共进退"是强演戏感；保留 FREE 开关 + 必要时分散，避免变成呆板列队。
- **原则 8（BOSS / 敌方真聪明）**：✅ 敌方编队懂得焦点开火、Element 互掩与重整，比散兵式独立追击更有压迫感。
- **原则 11（60 FPS）**：✅ leash = O(1) 距长机距离判定；焦点开火复用既有 FOLLOW_LEADER 路径；目标类型分流只读 target.meta，无新全场扫描。

**反模式规避**：
- ❌ 不做"看不出差别的暗调"——凝聚行为必须可感知（原则 3）。
- ❌ 不把小队焊死成永不分散的呆板列队（违背原则 7）——保留 FREE 开关 + 战术分散。
- ❌ 不引入新全场扫描（性能守则）——leash 走 O(1)。

## 2. 数据定义（What —— 权威源）

### 2.1 交战模式开关（三态，HUD 按钮循环）

| 概念 | 定义 |
|---|---|
| `Squad.engage_mode` / `AIController.squad_engage_mode` | **FREE(0)**=玩家显式放养，僚机可就近独立交战；**FOLLOW_LEADER(1)**=默认阵型攻击：长机决定主目标和攻击轴，僚机保持槽位并从阵位机会开火，只有 §3.7 break 条件才短时脱队；**GUARD_REAR(2)**=僚机不打长机的进攻目标，只盯后半球真威胁，无威胁则守在长机身后。实际生效的是 per-AI `squad_engage_mode`。 |
| 玩家队切换 | HUD「交战模式」按钮 `_btn_squad_engage`（survivor_hud `_on_squad_engage_pressed`）——**三态循环** FREE→FOLLOW_LEADER→GUARD_REAR；切换时强制僚机脱离当前交战立即回编队。 |
| GUARD_REAR 行为 | `_guard_rear_tick`：① 后半球空中真威胁（`scan_leader_rear`，REAR_GUARD_RANGE=900px、engaging_me 或 approaching dot>0.3，忽略远处闲敌）→ 拦截；② 否则威胁长机的**地面 AA**（`scan_leader_threat_ground`：SAM/AAA，SQUAD_LEASH_DIST 内）→ 默认 PREFER_MISSILE + GROUND_STRAFE 导弹模式**远射拔掉**，不贴脸 strafe 吃 AA 火力；③ 都没有→保持编队守后。anti-pile-on 分摊。 |
| GUARD_REAR leash | 守后专属紧 leash `REAR_GUARD_LEASH_DIST=1200px(贴身)`（`effective_squad_leash()`，区别于 FREE/FOLLOW 的 1800）；但**打地面 AA 时放宽回 1800** 让导弹 standoff 够得着。空中守护/闲置用紧 leash。 |
| FREE 范围 | 自由交战只接管**靠近**的敌机：`SQUAD_FREE_SCAN_RANGE=1500px(=3km)`（2026-05-31：2000→800→1500），不再一点就散开去够 4km 外目标，且 < leash 1800px。 |
| **★ 战术=阵型（绑定，本轮）** | **玩家手动切阵型已废弃**（删 HUD「阵型」按钮 + KEY_5）。交战模式直接决定阵型：自由→COMBAT_SPREAD / 跟随长机→FINGER_FOUR / 守后→WEDGE（`Squad.formation_for_engage_mode`）。切交战模式时同步设 `sq.formation`。 |
| **★ 敌方随机阵型（本轮）** | 普通杂鱼 `survivor_spawner._spawn_squad` 登场时 `sq.formation = Squad.random_formation()`（除 Trail 外随机），**只换站位、行为仍走凝聚默认**（用户决策）。精英/Boss 不走此路径（各自建队显式固定阵型）。Trail 现无人使用（玩家不绑、AI 不随机）。 |
| **默认值（用户已确认）** | 玩家队 + 敌方队默认 = **FOLLOW_LEADER（凝聚）**。FREE 退化为玩家主动选的"放养"模式。落地方式：`AIController.squad_engage_mode` @export 默认改 FOLLOW_LEADER + HUD `_squad_engage_mode` 初值同步。 |
| **焦点开火 + 阵型攻击** | FOLLOW_LEADER 下全队共享 `leader.combat_target`，但僚机的 movement authority 继续属于编队槽位；武器走既有编队机会火控。目标共享不再等于全员 `clear_formation()`。玩家不点目标时全队维持阵型。 |
| **当前实现差距** | 现代码在多数僚机跟打长机目标时仍清阵型并进入独立 ENGAGE；这是 v3 阶段 5 的迁移对象，不得把“默认 FOLLOW 已落地”误报成“编队攻击已完成”。 |

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
| **飞机**（机动威胁） | 编队攻击 + Element 互掩 | 单个 Squad 默认不拆成数架独立 BFM：长机形成攻击几何，僚机守槽位机会开火。需要互掩/侧击时，优先由 Encounter Package 的另一个 Element 承担；只有一个 Element 时才按 §3.7 临时派出守后机。 |
| **地面 / 船 / BOSS**（低机动 / 高 HP） | 编队饱和 | 全员保持阵型压同一目标，从阵位开火；关闭 anti-pile-on，最大化可读的编队齐射与攻击航线。 |

判定：`target.is_ground()` / 船类 meta / `category == "boss"` 等 → 编队饱和；否则（Aircraft 且非 boss）→ 编队攻击，并由 Package 是否存在第二 Element 决定互掩层级。具体规则见 §3.3。

## 3. 行为与公式（How）

### 3.1 凝聚模式下的僚机决策（FOLLOW_LEADER）

```
每决策 tick（僚机，有 squad、非长机、自主）：
1. leash 检查：dist(self, leader) > SQUAD_LEASH_DIST 持续 > HYSTERESIS → break off → SQUAD_FOLLOW，跳过以下
2. 长机有目标 T：
   - 保持 formation movement authority，目标与攻击轴读长机
   - 从阵位运行既有机会火控；不因获得 T 进入独立 BFM
   - 若满足 §3.7 break 条件，记录 reason 后短时脱队
3. 长机无目标 → 维持阵型（SQUAD_FOLLOW，现有）
4. break 原因结束 → 先 REFORM；重新进入阵位前不扫描新自由目标
```

FREE 模式：维持现状（自由扫描就近交战），但**仍受 §2.2 leash 约束**（这是 FREE 模式下"绕一大圈失踪"的根治）。

### 3.2 防游走 leash（目标：共进退，根治"查无此人"）

- 在 `_process_engage`（或僚机 ENGAGE tick 入口）加 O(1) 判定：`dist_to_leader > SQUAD_LEASH_DIST` 累计 > `SQUAD_LEASH_HYSTERESIS` → 调用既有 disengage → 回 SQUAD_FOLLOW。
- 长机 / 无 squad / 已在 SQUAD_FOLLOW 的不判。
- BOSS UAV 已有自己的 RECALL_LEASH（mother_goose_controller），不重复套用——本 leash 只管常规 squad 僚机。
- **玩家点名例外**：僚机正在跟打长机当前的 `commanded_target` 时，命令优先级高于普通归队 leash；长机取消、改点或目标失效后例外立即结束。导弹规避仍按求生优先处理。

### 3.3 目标类型分流 + Element 互掩（目标：焦点开火 / 必要才分散）

- **饱和（地/船/BOSS）**：Squad 全员目标 = 同一个 T，movement 仍由阵型拥有。关闭 `_is_target_already_squad_engaged` 的避免同目标限制。
- **空战（一个 Element）**：整队先完成一次阵型攻击航线；若确有后半球威胁，最高 index 僚机可临时守后，但无威胁时仍在槽位，不提前变成独立游猎机。
- **空战（多个 Element）**：Package 层优先把“正面攻击 / 侧击 / 守后”分给不同 Element；每个 Element 内保持自己的长机与阵型。用数个小编队协同，替代一个 Squad 内全员散开。
- 自由/守后角色瞬态键于当前 Squad/Package，切换与减员自愈；不得用持久 Aircraft 标记把新长机或幸存者锁死在旧角色。

### 3.4 与既有系统的交互

| 系统 | 交互 |
|---|---|
| **squad-ai-escort** | escort（反杀咬长机者）与 cohesion（焦点+leash+纪律）正交叠加：护卫反击是 §3.7 显式 break 原因，结束后先重整；守护者基础设施继续复用。 |
| **squad-control-switching** | leash / 临时守护角色键于“当前长机”，操控切换经 leader_changed 自愈（禁持久属性）。长机不被 leash，也不继承旧守护角色。 |
| **敌方编队** | 敌方队默认 FOLLOW_LEADER：长机 try_engage 选目标，僚机焦点跟打 + leash。敌方旗舰打玩家时整队压玩家 = 更强压迫感。 |
| **Encounter Package** | Package 负责多 Element 的目标域、接触轴和角色分配；Squad 只负责单个紧密编队。玩家直属机规模影响未来 Package 的 Solo/Pair/Flight 倾向，数值权威见 squad-xp-threat-balance。 |

### 3.5 性能（守则强制）
- leash = 每僚机 O(1) 距长机距离；无全场遍历。
- 焦点开火复用 FOLLOW_LEADER 既有路径；目标类型只读 target 类型 / meta。
- 临时守护角色复用 escort 守后基础设施（已节流）；多 Element 角色分配在 Package 低频 tick 完成。
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

### 3.7 阵型优先级与允许脱队条件（v3 用户定调）

默认优先级：

`生存/边界安全 > 玩家或脚本强制命令 > Element 战术动作 > 保持/重整编队 > 个体自由追击`

FOLLOW_LEADER 下只有以下原因可以暂时把僚机 movement authority 从 formation 交给独立 ENGAGE：

1. 本机真实导弹规避，且现有 flare/编队内防御不能处理；
2. 世界边界、地形/碰撞或任务安全合同要求立即脱离；
3. Package/任务显式指派包夹、守后、护卫反击或截击角色；
4. 当前保护对象遭到直接攻击，且守护者名额允许；
5. 玩家点名本机目标或脚本 critical 指令。

附近出现普通候选、长机刚获得目标、当前目标暂时离开射界，都不是解队理由。break 结束后先通过现有真实飞行物理回到槽位；归队过程中不抢新目标。不得瞬移、同步转向或伪造弹道。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `squad_engage_mode` 默认值 | 玩家 + 敌方队默认凝聚 | 改（建队处默认 + HUD 初值） |
| `SQUAD_LEASH_DIST` / `SQUAD_LEASH_HYSTERESIS` | leash 常量 + 计时 | **新增**（ai_controller） |
| leash 判定 | ENGAGE 僚机越界 break off | **新增**（ai_controller `_process_engage` 或 squad_coordination） |
| 目标类型分流 | 编队饱和 vs 编队空战 / Element 互掩 | **改**（squad_coordination + Encounter Package 角色分配） |
| anti-pile-on 条件化 | 饱和模式关闭 | 改（`_is_target_already_squad_engaged` 调用处加目标类型分支） |
| 临时 break / 守护角色 | 仅真威胁或显式战术时脱队，结束后重整 | **改**（复用 escort 守护者基础设施） |
| HUD 按钮 | 凝聚/自由开关 | 复用（已有）；默认初值改 |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **目标 1 焦点开火**：凝聚模式下同一 Squad 共享主目标；打地面/船/BOSS 时编队饱和，打飞机时从阵位攻击，互掩优先由第二 Element 承担。
- [ ] **目标 2 维持阵型**：无敌情 / 长机无目标时小队严守阵型一起走，不再单机乱跑。
- [ ] **目标 3 必要才分散**：只有 §3.7 的真实规避、安全或显式战术理由才短时脱队；原因结束后先收拢归队，再开始下一轮攻击。
- [ ] **目标 4 阵型攻击**：FOLLOW_LEADER 获得空中目标后，普通僚机不会同拍 `clear_formation()`；整队沿长机攻击轴行动，并能从阵位真实开火。
- [ ] **多编队画面**：四机主题包可表现为两个双机 Squad；两队可承担不同攻击轴/玩家目标，但队内仍紧密，不退化成四架独立 BFM。
- [ ] **防游走 leash**：无玩家点名目标时，交战僚机距长机超 leash 即 break off 回编队——不再"绕一大圈查无此人"；跟打长机玩家点名目标时不被普通归队覆盖。
- [ ] **开关**：玩家 HUD「交战模式」按钮在 凝聚(FOLLOW_LEADER) ↔ 自由(FREE) 间切换，立即生效。
- [ ] **范围**：友方 + 敌方编队都凝聚；敌方旗舰交战时整队焦点压目标。
- [ ] **切换自愈**：操控切换 / 减员后 leash、临时 break 与 Package 角色立即以新长机 / 新成员重算，无残留。
- [ ] 性能：leash 与 break 判定 O(1)，目标/攻击轴提升到 Squad/Element 低频决策；无新逐机全场遍历。按性能守则跑 C1，涉及多战线/LOD 时追加 C2，均守 60 FPS 与相对回退门。
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
- [ ] 调 SQUAD_LEASH_DIST / 临时 break 名额与归队体感至自然。
- [ ] 跑 §5 全部验收 + 性能压测。
- [ ] 更新 §7 锚点 + reference 索引 + known-seams。status → done。

### 阶段 5 — 阵型攻击与多 Element（v3，待实现）
- [ ] 修改 FOLLOW_LEADER 跟打路径：共享目标但保留 formation movement authority，复用 `update_formation_passive_missile`/编队武器链；不再默认 `clear_formation()` 进入独立 BFM。
- [ ] 为 break reason 与 REFORM 增加最小状态合同；导弹规避、边界、玩家/脚本指令与守护反击走显式例外，原因结束后先归队。
- [ ] Encounter Package 提供多 Element 角色分配；同一 Package 的不同 Squad 可分配不同玩家直属目标，但每个 Squad 内目标一致。
- [ ] 建 focused 回归：接敌不解队、阵位开火、真实规避后归队、换帅后整队重整、两个双机 Element 不串 leader/squad_index。
- [ ] 跑 C1/C2 三轮 Visual A/B 与完整局 playtest；记录编队态时长、最大散布、归队耗时、击杀/受击和弹丸数量。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 凝聚/自由开关字段 | `scripts/squad.gd`（engage_mode）/ `scripts/ai_controller.gd`（squad_engage_mode）/ `scripts/survivor/survivor_hud.gd`（HUD 按钮） |
| leash 常量 / 判定 | `scripts/ai_controller.gd` |
| 焦点开火 / 目标类型分流 / 临时 break | `scripts/ai/squad_coordination.gd` |
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
| 2026-08-30 | 3 | 用户提高编队优先级：明确默认 FOLLOW_LEADER 应以阵型形成攻击几何并从阵位开火，获得目标不再自动全员解队；多方向战术优先由 Encounter Package 的多个 Element 承担，单机 break 限于规避/安全/显式角色/保护/强制命令，结束后先重整。现有独立 ENGAGE 路径登记为阶段 5 实现差距。 |
