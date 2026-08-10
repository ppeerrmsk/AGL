---
id: dynamic-faction-conversion
kind: system
status: done
schema_version: 1
spec_version: 8
owner: noelu（设计输入 2026-08-04）/ Codex（规格细化）
depends_on: [systems/global-awareness-roe, events/ace-whitetea-fck1, systems/early-game-uav-rework]
reconstruction_complete: true
---

# 动态阵营转换 —— 投降、黑客与战场倒戈

> 玩家视角：敌人不一定只能被击落。被打垮的王牌会投降脱离，被激光持续侵入的无人机会
> 立刻变成绿色友军并把武器转向旧阵营；转换发生的一刻，锁定、火控、颜色和胜负判定同时翻面。

## 1. 设计意图（Why）

- **用户需求（2026-08-04）**：建立单位可切换阵营的通用机制。首批两条消费路径：
  1. WhiteTea 中队被击落至仅剩一架时，最后一架转为 `ALLY` 并逃离战场；事件立即按玩家已
     击败该王牌中队结算；
  2. 新增“激光·黑客光束”技能；取得后玩家小队的激光可黑入 MQ-109 / MQ-110，持续照射
     完成后目标转为 `ALLY`。该技能与既有“激光·致命输出”双向互斥，取得任一后另一张
     永久退出本局卡池。
- **体验目标**：让“投降”和“黑客”成为可直接看见的战场事件，而不是只改一个隐藏整数。
  转换当帧必须停止旧敌对关系、换阵营色并进入新的明确行为。
- **架构目标**：所有调用方走一个原子转换事务；禁止各事件散写 `unit.team = 2` 后遗漏旧目标、
  小队、锁定、奖励或在飞武器。既有 `AllyForce` 降级为该事务的兼容包装层。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - 信息察觉：黑客进度弧、完成浮字、敌暖色→ALLY 绿与火力翻面均可见；WhiteTea 血条立即
    结算并播报最后一机脱离；
  - 延迟快感：黑客需要维持有效照射，而不是碰一下就收编；完成当帧立即翻面；
  - AI 演戏：WhiteTea 的最后一机不是木桩式消失，而是认输、脱离并物理飞出战场；
  - 武器自动化：激光仍自动工作，玩家通过走位、距离与目标偏好维持照射，不新增手动黑客键；
  - 性能：黑客判定骑既有激光 `update`，投降判定骑既有王牌事件 `update`；不新增全场每帧扫描、
    Aircraft 子节点或常驻 `_process`。
- **反模式规避**：不把 ALLY 偷换成 PLAYER；被黑单位不可控、不吃玩家技能、不产玩家收益；
  不凭空复制单位，数量只来自实际生成并成功黑入的 MQ；不以“改了 team 就算完成”留下半敌半友状态。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 阵营关系（沿用既有 IFF）

| 阵营 | team | 本机制中的含义 |
|---|---:|---|
| PLAYER | 0 | 玩家直属小队；可控、吃局内升级 |
| HOSTILE | 1 | 敌军；可被玩家与 ALLY 攻击 |
| ALLY | 2 | 非直属友军；不可控、不吃玩家升级、击杀不产玩家 XP/功勋 |

敌我关系仍只由 `CombatUnit.is_hostile_to()` / `teams_hostile()` 决定：HOSTILE 与 PLAYER、ALLY
互相敌对；PLAYER 与 ALLY 互相友好。本机制不新增第四套敌我矩阵。

### 2.2 原子转换请求

| 字段 | 类型/值 | 说明 |
|---|---|---|
| `unit` | `CombatUnit` | 必须有效、存活且尚未进入转换事务 |
| `to_team` | `0 / 1 / 2` | 首批调用只使用 `HOSTILE → ALLY`；API 不写死单向 |
| `reason_id` | String | 首批为 `whitetea_surrender` / `laser_hack_mq109` / `laser_hack_mq110` |
| `source` | `CombatUnit?` | 黑客时为激光宿主；投降时为空；只作归因/日志，不授予击杀 |
| `post_policy` | `PASSIVE_EGRESS / ALLY_ESCORT_COMBAT / HOLD` | 转换完成后的 AI 策略；本期消费前两种 |
| 返回值 | bool | 仅首次成功转换返回 `true`；无效、死亡、同阵营或重入均为 `false` |

转换成功后单位发出一次 `faction_changed(old_team, new_team, reason_id)`；重复调用幂等，不重复
播报、不重复计数、不重复挂接长机。

### 2.3 转换事务的共同结果

| 类别 | 必须完成的结果 |
|---|---|
| IFF | `team` 原子切换；旧阵营目标不得再在转换后命中帧造成友伤 |
| 自身火控 | 清空 `combat_target`、`commanded_target`、`secondary_combat_target`、AI 当前目标、锁定累积与事件指令 |
| 他方火控 | 清除所有已变成友方的单位对本机的目标/锁定；仍敌对的单位可保留或重新获取 |
| 小队 | 从旧 `Squad.members` 移除，解除 formation / leader / shield / escort 绑定；不得继续接收旧中队命令 |
| 在飞武器 | 转换单位已发射、且仍会伤害新友方的持续弹药改为新 team 或安全失效；原友方正在追踪该单位的导弹解除制导，禁止绕着绿机空转 |
| 收益 | 从 HOSTILE 转出时 `token_cost=0`，标记已中和；转换默认不给收益，但具体 `reason_id` 可显式定义一次性中和奖励 |
| 目标身份 | 清除 `is_mission_target`；任务/事件把“敌对目标已被转换”视为已中和，不得因绿机仍存活卡住完成条件 |
| 视觉 | PLAYER=蓝、ALLY=绿、HOSTILE=暖色；飞机参数资源必须为实例私有，换色不得污染同型尚未转换的单位 |
| 日志 | 记录单位呼号、old/new team、reason、source；同一转换只记一次 |

转换清理允许在**转换当帧一次性**遍历 `CombatUnit.all_units` 与当前在飞导弹；它是低频事件，
不是每帧路径。遍历必须先过 `is_instance_valid()`，并遵守已释放引用净化契约。

### 2.4 WhiteTea 最后一机投降

| 字段 | 值 | 说明 |
|---|---:|---|
| 适用事件 | `profile_id == "whitetea"` | 其它王牌中队保持全灭契约 |
| 触发数量 | 存活敌对成员恰为 **1** | 由 3→2 不触发；同一帧 3→0 则按正常全灭 |
| 触发阶段 | 正式交战中，且未因 BOSS 解锁/弹尽进入撤离 | 外部撤离不能伪装成投降胜利 |
| 转换目标 | 最后一架存活 F-CK-1 | 不要求固定是 Tea；谁活着谁投降 |
| 新阵营 | ALLY | 绿色、不可控、与玩家互不伤害 |
| 新策略 | `PASSIVE_EGRESS` | 禁用战斗，不因受击回头；以最大速度/加力飞向最近边界外 |
| 静默回收线 | 飞出世界边界 **800 px** | 与既有王牌撤离/友军撤离一致；回收前清引用 |
| 事件结算 | 转换成功当帧视为 WhiteTea 已被击败 | 立即关闭分段血条、+60 s、写王牌击破档案 |
| 逃离无线电 | 转换成功当帧入队一次 `whitetea_surrender` | 由投降的 WhiteTea 幸存者本人喊话“两个废物…！我先撤了！”，让玩家知道它不是漏杀或消失 |
| 投降经验 | **按正常击落第三架 WhiteTea 的完整经验公式发放一次** | 基础 100 XP，再走当前等级加值、玩家 XP 倍率、里程碑倍率与编队经验稀释 |
| 非经验击杀收益 | **不触发** | 投降不是击落：不增加击杀数，不触发击杀回血、连击、对头奖励、图鉴击坠或空战击坠档案 |
| 终态日志 | `surrendered` | 与 `eliminated` / `withdrawn` 分开，避免污染 TTK 诊断 |

投降后的 F-CK-1 仍是战场中的真实 ALLY：HOSTILE 可以攻击它，它也可能在离场前被击毁；但
WhiteTea 的胜利、时间奖励与生涯击破不会回滚。投降经验只在转换成功时发放一次；投降机之后
死亡不再产生第二份经验或其它玩家收益。

#### 2.4.1 WhiteTea 逃离无线电

| 字段 | 值 | 说明 |
|---|---|---|
| trigger | `whitetea_surrender` | 只在最后一机成功执行 `HOSTILE → ALLY + PASSIVE_EGRESS` 后触发一次 |
| class | `scripted` | 豁免全局冷却、自身冷却、概率骰与过期丢弃，剧情结果必须传达 |
| weight | `95` | 高于普通王牌登场 `90`，低于 BOSS 剧本 `100`；只影响排队，不打断正在播放的台词 |
| speaker | 投降的 WhiteTea 幸存者真实 `callsign` | 谁活着谁说，不固定 Tea / Milk / Sugar |
| line key | `RADIO_WHITETEA_SURRENDER_1` | 中：两个废物…！我先撤了！ |
| English | `Those two idiots...! I'm getting out of here!` | 三语必须同批进入 `radio.csv` |
| 日本語 | `あの役立たず二人め…！俺は撤退する！` | 不让管制、无人机或无关友机代说 |
| 呼号颜色 | 敌王牌暖色 | 在转换成功后显式使用敌王牌色，不随投降机新 ALLY 绿改变 |

顺序契约：投降转换与胜利/经验结算成功后再调用无线电；转换失败、同帧 2→0 全灭、BOSS 解锁撤离、
弹尽撤离均不播。若当前已有台词，`whitetea_surrender` 在队列中等待并保持不失效，绝不打断；
若无线电系统缺席或降级静默，独立投降提示仍必须显示，不能让无线电成为胜负反馈的唯一通道。

### 2.5 激光构筑分支与卡池互斥

基础激光保持既有定位：**只有 SLOW，没有伤害，也没有黑客**。取得以下任一技能后选定一条
不可回头的本局分支：

| 字段 | 激光·致命输出 | 激光·黑客光束 |
|---|---|---|
| upgrade id | `skill_laser_damage` | `skill_laser_hack` |
| name key | `UPGRADE_SKILL_LASER_DAMAGE_NAME` | `UPGRADE_SKILL_LASER_HACK_NAME` |
| desc key | `UPGRADE_SKILL_LASER_DAMAGE_DESC` | `UPGRADE_SKILL_LASER_HACK_DESC` |
| stat / value | `skill_flag / 1` | `skill_flag / 1` |
| max_stacks | 1 | 1 |
| category | `secondary` | `secondary` |
| axis | 由 `secondary` 默认映射为 `gladiator` | **`schemer`（策士位）** |
| rarity | `ADVANCED` | `ADVANCED` |
| keywords | `[laser, damage]` | `[laser, hack]` |
| requires | `[laser]` | `[laser]` |
| excludes | `[skill_laser_hack]` | `[skill_laser_damage]` |
| 效果 | 激光保留 SLOW，并恢复距离衰减 DPS | 激光保留 SLOW；对合法无人机焦点推进黑客，不造成 DPS |

双向 `excludes` 是卡池权威：取得任一技能后，另一技能在普通三轴卡、任何重抽与可用性过滤中
都必须消失。若 debug/旧档/损坏数据异常地同时持有两者，采用兼容兜底：
`skill_laser_damage` 优先、禁用黑客并记录 warning；正常游戏流程不得产生该组合。

### 2.6 激光黑客参数

| 字段 | 值 | 说明 |
|---|---:|---|
| 合法来源 | PLAYER 阵营飞机上的 `LaserEquipment`，且该机持有 `skill_laser_hack` | HOSTILE / ALLY 激光或无技能的基础激光不触发收编 |
| 合法目标 | HOSTILE 且 `enemy_type` 为 `uav` 或 `ucav` | 即 MQ-109 / MQ-110；Sentinel、MQ-111/112、Aegis 激光机与其它无人机不在本期 |
| 有效距离 | 激光装备自己的 `max_range_m` | 当前玩家激光为 1500 m；不另造黑客射程 |
| 黑客阈值 | **2.5 s** 有效照射 | 小于激光单次约 2.85 s 过热窗，完整维持一次射击窗即可完成 |
| 断线宽限 | **0.30 s** | 容忍 tick/LOD/目标排序的短抖动 |
| 宽限后衰减 | **1.0 s 进度 / 1.0 s** | 重新照射时按时间戳惰性结算；不建全场衰减 tick |
| 同源并行 | 每个激光宿主同时只推进 **1** 个黑客目标 | 黑客分支的其它光束照常施加 SLOW，但不推进黑客，禁止一轮收编八架 |
| 焦点优先级 | 有效 `combat_target` → 有效 `commanded_target` → 最近合法目标 | 保留自动武器契约，同时允许玩家靠目标偏好表达意图 |
| 多源叠加 | 不叠加 | 同一物理帧同一目标最多按 1 倍时间推进，防多激光瞬间完成 |
| 黑客目标伤害 | 黑客焦点只吃 SLOW + 黑客进度，不吃激光 DPS | 伤害与黑客技能已在卡池互斥，正常构筑不存在两种效果竞争 |
| 完成策略 | `ALLY_ESCORT_COMBAT` | 清旧目标后绑定当前玩家长机；跟随长机机动并攻击 HOSTILE，不响应玩家指挥 |
| 存活时长 | **战斗直到被击毁** | 无倒计时、无数量替换、无主动撤离、无离屏回收；仅被击毁或本局场景结束时释放 |
| 同场上限 | **不设机制硬上限** | 已成功黑入的无人机不能因后来又黑入新机而被逐出；实际数量只受本局 MQ-109/110 生成与存活数限制 |

黑客焦点的 2.5 s 进度按目标保存。照射中显示青色进度弧；完成当帧显示本地化 `HACKED` 浮字、
机体转 ALLY 绿并把火控转向 HOSTILE。MQ-109/110 无驾驶员，不播放人格化无线电。

### 2.7 黑客后 ALLY 契约

| 项 | 行为 |
|---|---|
| 玩家控制 | 不可选中、不可加入 1~9 号机、不可接收战术轮盘命令 |
| 成长 | 不吃玩家技能、里程碑、datalink 或换机重放 |
| 作战 | 使用自身原始机炮/导弹与 AI 参数，只把合法目标改为 HOSTILE |
| 收益 | 它击落 HOSTILE 时沿第三方 ALLY 契约：任务可推进、敌 token 正常回收，玩家 XP/击杀/回血/连击/功勋为 0 |
| 长机 | 始终以当前 `player_aircraft` 为跟随锚点；玩家切控、换机或长机继任时，经统一 `_set_player_aircraft()` 接缝同帧重定向到新长机 |
| 跟随作战 | 不重新加入 Sentinel、原敌军 Squad 或玩家可控 Squad；复用护驾/伴随语义：长机附近无目标时伴飞，长机交战时优先协同攻击其合法 HOSTILE，追击过远则脱离目标并归队 |
| 长机暂失 | 换机/阵亡交接的短窗口内保持 ALLY、清空失效长机引用并在当前位置自主防卫；新 `player_aircraft` 有效后重新挂接，绝不因此撤离或回敌军 |
| 生命周期 | 已黑无人机只在自身被击毁或本局场景结束时释放；离屏、BOSS 解锁、战区清场或后来黑入更多无人机都不得回收它 |

## 3. 行为与公式（How）

### 3.1 原子转换顺序

```text
validate(unit, alive, old_team != new_team, not transition_in_progress)
→ 标记 transition_in_progress
→ 从旧 Squad 与 formation 解绑
→ 清单位自身的目标、锁定、directive、雷达累积
→ 清全场中“转换后已不再敌对”的目标/锁定引用
→ 处理双方在飞追踪武器与持续弹药的 IFF
→ 写 team / category / token / neutralized / reason / faction color
→ 发 faction_changed(old_team, new_team, reason)
→ 应用 post_policy
→ 清 transition_in_progress，返回 true
```

必须先完成战斗引用清理再允许新 AI 获取目标。事务任一步遇到已释放对象都跳过该对象，不得因
一条僵尸引用中断整个转换。

### 3.2 WhiteTea 状态转移

| 状态 | 条件 | 结果 |
|---|---|---|
| COMBAT_3 | 三机存活 | 沿既有 joust/J-turn 行为 |
| COMBAT_2 | 一机被击落 | 无新增效果，继续作战 |
| SURRENDER | 第二机被击落后仅余一架，且非外部撤离 | 对最后一机执行 ALLY + PASSIVE_EGRESS；王牌事件立即进入击败终态 |
| ELIMINATED | 同一更新步没有存活成员 | 沿既有全灭终态，不生成投降机 |
| WITHDRAWING | BOSS 解锁或弹尽 | 沿既有撤离；不触发投降、不算击败 |

事件终态与投降机离场生命周期分离：胜利奖励在 SURRENDER 当帧结算；事件继续轻量监护绿机
直到其出界/被击毁，再释放引用结束，不让事件结束时把投降机误回收或恢复旧 AI。

### 3.3 黑客进度公式

对本帧选出的唯一黑客焦点 `u`：

```text
gap = now - u.hack_last_touch_time
if gap > 0.30:
    progress = max(0, progress - (gap - 0.30) * 1.0)
if u.hack_last_progress_frame != physics_frame:
    progress += delta
u.hack_last_touch_time = now
u.hack_last_progress_frame = physics_frame
ratio = clamp(progress / 2.5, 0, 1)
if ratio >= 1:
    convert(u, ALLY, laser_hack_<type>, source, ALLY_ESCORT_COMBAT)
```

离开光束后不跑额外全场 tick；下次进入光束或绘制进度时用时间戳计算当前有效进度。转换、死亡、
出界回收时清除黑客进度元数据。

### 3.4 目标与任务仲裁

- 基础激光无 `skill_laser_hack` 时不创建/刷新任何黑客进度；只有黑客分支进入本节流程。
- 正常黑客分支没有激光 DPS；达到阈值的帧直接转换，不产生一帧额外伤害。
- debug/旧档异常同时持有伤害与黑客技能时，伤害分支优先且完全禁用黑客。
- 其它武器同帧已先造成致死伤害时，目标死亡优先，转换失败并按正常击杀结算。
- 被黑的 `is_mission_target` 当帧按“已中和”移出目标集合；不要求先击毁。
- 被黑单位不得被当前玩家/僚机的自动火控重新选中；转换当帧已有玩家导弹解除制导。
- 被黑单位可立刻被其它 HOSTILE 选中，符合“倒戈后成为敌军目标”的战场语义。

## 4. 结构与组成（Structure）

- 新增共享的阵营转换事务服务；接收 `CombatUnit` 与转换请求，通用部分只依赖基类 IFF/目标 API。
- 既有 `AllyForce.convert_aircraft/convert_ground` 保留签名，内部改调事务服务，保证机场防空、AWACS、
  F-15 支援行为不回归。
- `CombatUnit` 提供实例级 `faction_changed` 信号；任务/事件只订阅需要的单位，不建全局总线轮询。
- Aircraft 专用适配负责旧 Squad、formation、AI target/directive、参数实例色与 post policy；
  Ground/Naval 适配复用通用 IFF/目标清理，首批无新消费方但须保持既有 ALLY 转换可用。
- 激光黑客骑 `LaserEquipment.update` 已有 picks：只在最多 8 个已选目标中选 1 个焦点，零新增全场扫描。
- 黑客进度通过既有激光 beam 数据交给 AircraftRenderer；只增加单个进度弧/颜色参数，不新增节点、
  `_process`、`queue_redraw` 或逐目标文本 Label。
- WhiteTea 投降与离场由既有 `AceReinforcementEvent` 监护；不把通用服务写死 `profile_id`。
- WhiteTea 逃离播报复用既有 `RadioChatter` 队列；事件只提交一次 scripted trigger，不新增 UI、音频节点或并行计时器。
- 玩家黑入单位注册表由生存模式持有，事件驱动增删并在单位销毁时差量移除；长机重定向只走
  `_set_player_aircraft()` 接缝，不每帧全场扫描。注册表无机制硬上限，但只包含本局实际存活的被黑 MQ。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 原子性：任一 HOSTILE 飞机转 ALLY 的同一物理帧内，颜色、IFF、AI 目标、旧 Squad、锁定与
      任务目标全部翻面；不存在仍朝玩家开火或被玩家继续伤害的一帧半转换状态。
- [ ] 幂等：对同一单位重复提交相同转换，只触发一次信号、日志、视觉和长机挂接。
- [ ] 在飞武器：玩家已发射导弹不会继续追/伤转换后的绿机；转换机旧弹药不会在转换后误伤新友方。
- [ ] 既有 ALLY：机场 AA/SAM、AWACS 与王牌 F-15 支援转换后的 team、颜色、0 XP 和事件行为逐字节等价。
- [ ] WhiteTea 3→2 时继续作战；2→1 时最后一机变绿并被动飞向边界，血条立即关闭、+60 s、
      生涯记 `whitetea` 击破；前两架正常击杀结算，投降机额外发放一次等同正常第三架的完整 XP。
- [ ] 投降 XP 走与普通王牌击落一致的等级/倍率/编队稀释公式，但不增加击杀数，不触发回血、
      连击、对头奖励、图鉴击坠或空战击坠档案；投降机之后死亡不得重复发 XP。
- [ ] WhiteTea 同帧 2→0 时正常全灭；BOSS 解锁/弹尽撤离时即使只余一机也不投降、不记击破。
- [ ] 投降机出界 800 px 后静默回收；离场前被 HOSTILE 击毁不回滚胜利、不产生玩家收益。
- [ ] 投降无线电：2→1 转换成功当帧由幸存者本人用真实呼号入队一次“两个废物…！我先撤了！”；
      使用 scripted/weight 95、三语齐全，不受冷却/概率/过期影响，也不打断当前台词。
- [ ] 投降无线电不在 3→2、同帧 2→0、BOSS 解锁撤离、弹尽撤离或重复转换时播放；无线电缺席时
      独立投降提示和胜利结算仍正常工作。
- [ ] 基础激光：未取得两种分支技能时只施加 SLOW，不造成 DPS，也不积累黑客进度。
- [ ] 卡池互斥：取得 `skill_laser_damage` 后 `skill_laser_hack` 在本局所有后续候选中不可出现；
      反向取得黑客技能后伤害技能同样不可出现；两条 upgrade 数据必须双向写 `excludes`。
- [ ] 伤害分支：取得 `skill_laser_damage` 后保持既有 SLOW + 距离衰减 DPS，MQ-109/110 不积累黑客。
- [ ] 黑客分支：取得 `skill_laser_hack` 后，PLAYER 激光连续有效照射 MQ-109/110 2.49 s 不转换，
      达到 2.50 s 当帧转 ALLY；
      Sentinel/MQ-111/112/Aegis/有人机均不积累黑客进度。
- [ ] 策士位：`skill_laser_hack` 显式 `axis = schemer`，只出现在策士卡槽；取得时策士轴进度 +1，
      不得因 `category = secondary` 被默认分进斗士位。
- [ ] 黑客断线 0.30 s 内不衰减，之后按 1.0 s/s 衰减；同帧多束不叠加。
- [ ] 异常共存兜底：debug/旧档同时持有两技能时伤害分支优先、黑客禁用并记录 warning；正常抽卡
      与重抽流程不得产生共存。
- [ ] 被黑无人机不可控、不入玩家可控 Squad、不吃升级；跟随当前长机作战，可攻击 HOSTILE，
      其击杀推进任务但玩家收益为 0。
- [ ] 被黑无人机不会因离屏、BOSS 解锁、战区清场或后来黑入新机而撤离/回收；每架都持续作战，
      直到自身被击毁或本局场景结束。玩家切控/换机后全部无人机改跟新长机，无旧引用残留。
- [ ] 表现：照射中有青色进度弧，完成有本地化 HACKED 浮字并立即换绿；WhiteTea 投降有独立提示，
      不冒用“全机击落”文案；三语齐全。
- [ ] 性能：不新增常驻 process/全场扫描；跑 Sentinel + Lv5+ + 12 架被黑无人机 + WhiteTea 压测，
      FPS 不低于 60，掉幅 <15；再跑 Lv8+ 验证拥挤度降频正常。
- [ ] 生命周期：转换/出界/场景退出后无 freed-instance、残留 target、残留静态注册表或 token 泄漏。
- [ ] 文档：依赖 spec、_INDEX 与 reference 索引同步；玩家引用与文档锚点校验通过。

## 6. 实现计划（Task Pipeline —— 用户批准后执行）

### 阶段 1 — 原子阵营转换地基

- [ ] 新增转换请求/事务服务与 `faction_changed` 信号；实现 IFF、目标、锁定、小队、在飞武器、
      奖励/任务身份与颜色的一次性清理。
- [ ] 让 `AllyForce` 走新事务，补机场防空/AWACS/F-15 兼容回归。
- [ ] 增加纯函数/替身单测：幂等、目标引用、Squad 解绑、任务中和、弹药 IFF、参数色不串实例。

### 阶段 2 — WhiteTea 投降

- [ ] 在王牌事件中加入 WhiteTea 专属 2→1 仲裁、独立 `surrendered` 终态与 PASSIVE_EGRESS 监护。
- [ ] 加投降提示/i18n；注册 scripted `whitetea_surrender`（weight 95），由幸存者真实呼号播出；修血条、
      +60 s、生涯击破和 TTK 日志；补 3→2、2→1、2→0、外部撤离与无线电去重回归。

### 阶段 3 — 激光黑客

- [ ] 注册 `skill_laser_hack` 与三语文本，显式写 `axis = schemer`；给它和 `skill_laser_damage` 写
      对称 `excludes`，补三轴槽位、里程碑、普通池、重抽、异常共存与自动生成 skill-table 回归。
- [ ] 在激光 picks 中增加技能门与单焦点仲裁；实现进度/宽限/惰性衰减/同帧不叠加。
- [ ] 完成 MQ-109/110 eligibility、`ALLY_ESCORT_COMBAT`、当前长机重定向、任务中和与直到被击毁的生命周期。
- [ ] 用既有 beam/renderer 增加进度弧、青色黑客束与 HACKED 完成反馈；不加子节点。

### 阶段 4 — 验证与文档

- [ ] 新增 `faction_conversion` bench 并滚入 all；跑相关定向 bench、文档、玩家引用校验。
- [ ] 只经 `bench/run.cmd` 跑 Sentinel/Lv5+ 与 Lv8+ 压测；完成实机视觉/手感 QA。
- [ ] 同步 WhiteTea、UAV、激光相关 spec/reference；回填锚点与变更记录后转 done。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 通用阵营转换事务 | `scripts/events/` 下的新事务服务；`scripts/events/ally_force.gd` 兼容包装 |
| IFF / faction_changed | `scripts/combat_unit.gd` |
| Aircraft 目标/编队适配 | `scripts/aircraft.gd`、`scripts/ai_controller.gd`、`scripts/squad.gd` |
| 在飞武器 IFF 清理 | `scripts/missile.gd`、`scripts/missile_manager.gd`、`scripts/bullet_manager.gd` |
| WhiteTea 投降/离场 | `scripts/events/ace_reinforcement_event.gd` |
| WhiteTea 逃离无线电 | `resources/chatter/radio_chatter.json`、`scripts/survivor/radio_chatter.gd`、`i18n/radio.csv` |
| 激光黑客 | `scripts/equipment/laser_equipment.gd` |
| 黑客表现 | `scripts/aircraft/aircraft_renderer.gd`、`i18n/gameplay.csv` |
| 回归 | `scripts/tests/` 下阵营转换专项 + 既有 ROE/王牌/激光相关 bench |
| reference | `docs/reference/script-index.md`、`docs/reference/code-index.md`、`docs/reference/enemy-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-04 | 8 | 修复阵营转换把 `CombatUnit` 直接传给 `Array[Aircraft].erase()` 导致的 4.7 TypedArray 错误风暴；修复 Squad 继任链读取已释放强类型引用；专项 bench 新增真实激光黑客完成路径、强类型护卫/群组缓存和 freed successor 回归。 |
| 2026-08-04 | 7 | 实装完成：原子阵营事务、WhiteTea 2→1 投降/本人无线电/完整中和 XP、策士黑客光束、双向卡池互斥、MQ 当前长机重绑定、青色进度表现与定向 bench。 |
| 2026-08-04 | 6 | 用户定档：WhiteTea 投降无线电不由战术管制播报，而由最后幸存者本人使用真实呼号说“两个废物…！我先撤了！”；呼号保持敌王牌暖色。 |
| 2026-08-04 | 5 | 用户裁决：WhiteTea 最后一机投降成功后必播战术管制无线电，明确提示“最后一架逃了，正在脱离战场”；scripted、权重 95、不打断当前台词、三语齐全。 |
| 2026-08-04 | 4 | 用户裁决：被黑 MQ 跟随当前玩家长机持续作战直到自身被击毁；取消 4 架上限、最老撤离与离屏/BOSS 清场回收。黑客光束显式归 `schemer` 策士位。 |
| 2026-08-04 | 3 | 用户裁决：黑客光束改为独立 `skill_laser_hack` 构筑分支，与既有 `skill_laser_damage` 双向互斥；取得任一后另一张不再刷出。基础激光仍只减速。 |
| 2026-08-04 | 2 | 用户裁决：WhiteTea 投降机也给经验；按正常第三架的完整 XP 公式发放一次，但不伪造成击杀、不触发击杀派生收益。 |
| 2026-08-04 | 1 | 初稿：原子阵营转换事务；WhiteTea 最后一机投降并按击破结算；PLAYER 激光 2.5 s 黑入 MQ-109/110；被黑 ALLY 最多 4 架。 |

## 9. 待用户批准的裁决

1. WhiteTea 最后一机投降当帧即按击败结算，并提供等同正常第三架的完整 XP；投降不计作击杀，
   不触发击杀回血、连击、对头奖励或击坠档案。
2. `skill_laser_damage` 与新 `skill_laser_hack` 是双向互斥的激光构筑分支；取得任一后另一张
   不再刷出。基础激光在两者皆无时只减速。
3. 黑客阈值为 2.5 s；只允许 MQ-109/MQ-110；黑客分支没有激光 DPS。
4. 被黑单位是绿色、不可控的 ALLY，而非蓝色玩家僚机；其击杀不给玩家收益。
5. 被黑单位跟随当前玩家长机战斗，玩家切控/换机时改跟新长机；不设同场硬上限，也不会被后来
   黑入的新机替换或被动撤离，每架都持续作战直到自身被击毁或本局场景结束。
6. `skill_laser_hack` 显式归 `schemer` 策士位；`category = secondary` 仅保留旧分类语义，不参与轴位兜底。
7. WhiteTea 最后一机投降成功当帧播放一次 scripted 无线电，由幸存者本人以真实呼号说
   “两个废物…！我先撤了！”；不打断当前台词，且不在全灭或普通撤离路径误播。
