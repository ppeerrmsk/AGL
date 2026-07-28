# 2026-07-28 平衡与事件批：三轴全队 / 刷怪池 / 事件裁撤 / 航母穿排

一次性收掉玩家反馈里的 11 项，按"纯数值 → 系统"分五批落地。全批通过 `--bench=all`
（回归门 **42/42**，新增 `spawn_pool` 套件），`verify_doc_anchors.py` 与
`verify_player_ref_holders.py` 均绿。

---

## A. 纯数值 / 视觉

| 项 | 旧 → 新 | 位置 |
|---|---|---|
| CIWS 真弹周期 | 每 3 发 1 发真弹 → **每 2 发 1 发**（拦截 DPS ×1.5） | `NavalWeapons.CIWS_REAL_BULLET_CYCLE` |
| 出界补给时间税 | 15s → **30s** | `SurvivorMode.SUPPLY_TIME_COST` |
| 玩家 QMAAM 格斗弹伤害 | 70 → **80**（与主导弹 MRM 齐平） | `resources/qmaam_missile.tres` |
| 云噪声频率 | 0.00055 → **0.00028**（特征尺度 ≈7km，出大块云系） | `WeatherSystem.cloud_frequency` |
| 敌方机炮意图锥 | 填充 alpha 0.22 → **0.12**，描边 0.4 → **0.24** | `AircraftRenderer.draw_gun_cone` |

**CIWS 澄清**：它一直是**真实弹道子弹碰撞拦截**，不是概率判定——"真子弹概率"其实是
确定性的出弹周期。散布 ±5°、命中半径 12px、距离衰减（≥800px 完全无伤）三重压制保持不变，
60HP 导弹仍需 6 发真弹命中，观感仍是"近了才拦得下"。

**火箭弹削弱**（`resources/weapons/enemy_rocket_v1~v8.tres`）：伤害全档约 −25%
（8/10/13/16/19/23/27/32 → 6/8/10/12/14/17/20/24），齐射数压缩
（3/4/5/6/7/8/9/10 → 2/3/3/4/4/5/5/6）。V8 满齐射伤害上限 320 → 144。
同时**移除** `_create_enemy` 里 F-86/A-7/Q-5 额外的 `×(1 + (level−1)×0.04)`——
火箭弹的等级成长现在完全由武器 tier 表承担，同一维度不留两根互相放大的杠杆。
（火箭弹不吃距离衰减、也不走玩家的机炮闪避通道，实际威胁比数字看起来更高。）

**机炮锥开火淡出**：新增 `Aircraft._gun_threat_fade`，`is_firing` 期间 0.35s 淡出、
停火后 1.5s 淡回（梭射间隙仍有预警）。锥的职责是"开火前的预告"，曳光弹一出来它就是纯干扰。
威胁条件整体中断时仍**立即归零**，保留原防抖语义。顺手修了注释漂移——
注释写"红色威胁锥"，实际一直是橙黄。

**签名技 sig_\***：新增 `SurvivorData.SIG_SKILL_WEIGHT_MULT = 2.5`，在轴内抽卡与三选一
两条路径的权重乘区生效（基础权重仍是 CLASSIFIED 0.08，等效抬到 0.20 ≈ ADVANCED 档）。
40 条 sig 全是 CLASSIFIED，加上驾驶门控保证池里最多 1 条自机专属，靠通用稀有度权重
基本抽不到，"每机一条看家本领"名存实亡。卡面新增**洋红专属边框**
（`SurvivorUpgradeUI.SIG_FRAME_COLOR`，边框加粗一档 + 0.16 alpha 底色），
刻意避开五档稀有度色与三轴色；稀有度徽章仍显示真稀有度。

---

## B. 三轴里程碑全队生效

**症状**：三轴（斗士/骑士/策士）里程碑的全部效果只写在 `SurvivorPlayer.aircraft`——
也就是当前操控机——的 params 上。僚机入队、换机重放、技能分流三条路径都只重放 UPGRADES，
零里程碑。更糟的是**换帅后彻底丢失**：`_set_player_aircraft` 不重挂，而玩家级记账
`applied_milestones` 又已记满，`apply_crossed_milestones` 因此永远补不上。

**改动**：里程碑加成改为**跟玩家不跟机体、且下发全队**，与技能的归属分流语义对齐。

- 记账从"玩家级单账本"改为**逐机记账**（存飞机 meta）；`applied_milestones` 退化为
  "当前操控机那本账"的属性视图（getter/setter），tactical_map 量表与既有单测读法不变。
- 新增 `SurvivorPlayer.milestone_targets_provider`（Callable），由 `survivor_mode` 注入
  `_squad_members_alive` —— `add_axis_point` / `add_milestone_bonus` 的**全部**调用点
  自动覆盖僚机，不必逐处补。未注入时退化为只有当前操控机（单测 / 沙盒路径行为不变）。
- 新僚机入队 `_apply_build_to_new_member` 增加全量补挂；换型（进化）第③步改为对
  `_squad_members_alive()` 逐机重放 —— **每机恰好一次**，reapply 会先清账再全量重挂，
  重复调用等于叠两遍。
- 效果应用走 `_apply_milestone_effect_to(target, m)`：借用 `self.aircraft` 指针后还原，
  与 `apply_upgrade_to` 同一手法，保证单机路径与全队路径语义逐字节一致。
- 换帅 bug 由构造消解：账本跟着飞机走，新操控机带着自己那本。

**新增无头断言** `test_attribute_gates._test_milestone_squad_wide()`（E2 节 9 条：
僚机同吃 / 逐机幂等 / 晚入队补挂 / 换帅不丢）。attr_gates 套件 87 → 96 通过。

---

## C. 刷怪池

**AF-03（电磁炮试验机）可见性**：解锁等级 8→**7**、每级概率 0.05→**0.06**、
上限 0.18→**0.26**，并**新进战区池**（`ZONE_ENEMY_TABLE`，权重 0.5 / unlock 7 / peak 10）。
原配置下它只在旅途随机池、8 级解锁、上限 18%、实例上限 1，且战区任务完全刷不出——
玩家整局遇不到一次，"电磁炮试验机"形同不存在。实例上限仍为 1，保住稀有精英身份。
顺手修了 `TOKEN_COST` 的注释漂移（原写"事件触发"，实际是随机池）。

**敌人作战高度分档**：此前**所有**机型共用一句均匀 1/3 随机 LOW/MID/HIGH——
高空高速截击机和贴地攻击机掷同一颗骰子，战场纵向毫无层次。新增
`SurvivorData.ENEMY_ALTITUDE_WEIGHTS`（18 型登记）+ `pick_altitude_tier()`：

- 攻击机 A-7 / Q-5 偏低空；截击机 MiG-31 / F-104 / J-7 偏高空；AF-03 偏高空（取射界）
- 多用途机（MiG-29 / Su-27 / Su-35 / F-4 / MiG-23 / F-86 / F-100 / F-4E）偏中空
- MQ-109 低空、MQ-110 低中空；Sentinel / Aegis UAV 中高空

同时新增 `TIER_PATROL_ALTITUDE` + `patrol_altitude_for_tier()`（LOW 1500~3000 /
MID 4500~6500 / HIGH 8500~11000），让 `AIController.patrol_altitude` 跟随抽到的档位——
它经 `Situation.combat_altitude_m` 决定战术层的交战高度，不同步的话档位分化只影响巡逻段，
一进交战全被拉回中空。**未登记类型**（BOSS / adds / 事件单位，档位由各自 spawn 代码
事后覆写）维持原行为，避免和被覆写的档位对不上。

**修 BOSS 机型漏进常规刷怪**：`_pick_enemy_type` 的后期随机桶遍历整张 `TOKEN_COST`
取 cost ≥ 3，F-47 与 F-14 Poltergeist 靠 cost 10 混了进来，作为普通旅途敌机刷出
（与 enemy-index 记载不符）。新增 `SurvivorData.BOSS_ONLY_TYPES` 显式黑名单，
不再靠 cost 数值偶然挡住。

---

## D. 事件系统

### 裁撤：友军直升机护送事件

删除 `EscortConvoyEvent`（脚本 + 调度 + `_escort_timer` / `_escorts_launched` 字段 +
i18n `EVENT_ESCORT_*` 三键）。奖励是纯局外功勋（40/架，满额 120）、Tab 图不画护送队、
无无线电、抵达即静默消失——玩家既找不到它，也没有局内理由去打，属于纯噪音事件。

### 敌军直升机（ADBS 城区 CH-47）

- **护卫反应**：新增 `Aircraft.escort_guards` + `_alert_escort_guards()`。被护送对象
  在 `_apply_damage` 里挨打 → 护卫机经 `acquire_target(attacker, TS_DIRECTIVE)` 扑向攻击者。
  此前敌方护卫对"被护送对象被打"**完全无反应**：护卫学说只对玩家队开、
  `try_defend_protectee` 是玩家专属、adds 类还被 ROE 察觉体系整体排除——
  这条数组是敌方护卫唯一的反应通道。
- **直升机受击散开**：CH-47 现在挂 `scatter_on_damage` 并串上 `flock_members`
  （此前只有 AH-64 编队有），被点名时整列急停侧跨 jink。
- **全歼奖励**：三架全部击落 → `grant_time_extension(20.0)`（与王牌中队全灭 +60s
  同一注入点）+ 横幅。给局内时间而不是功勋——玩家要有**当场**去打它的理由。
  实现走轮询（与 `_detect_kills` 同模式），逃出地图被回收的不算战果也不阻塞结算。

### AWACS 支援事件改造

- **轨道绕当前战区**：新增 `_pick_orbit_center()`——优先玩家选中的战区，其次离玩家
  最近的 AVAILABLE 战区，都没有则退回原南带位置。轨道中心 = 战区中心 + 南向退避 2200px，
  跑道形东西向半程 2500px。退避距离刻意 < 光环半径 4000px，否则光环盖不到战区，
  "预警机支援"就只是个装饰。（原实现是南带两个写死的点，离战场十万八千里。）
- **定时撤离**：在站 180s 后转向撤离，飞出地图（或 90s 兜底超时）即结束，光环保留到
  真正飞出去为止。原实现是"呆到被击落为止"，支援变成永久挂件，
  "抓住支援窗口打一波"的节奏完全不存在。
- **进离场无线电**：新增 chatter trigger `awacs_onstation` / `awacs_egress`
  （均 `scripted` 必播），各 3 条台词。光环来没来是战术信息，不能只靠玩家自己开 Tab 图发现。
- **Tab 图光环圈**：从 1.5px 细弧改为「0.07 alpha 淡填充 + 2.5px 描边」——
  玩家要能一眼判断"我在不在锁定加速圈里"。
- buff 数值不变：半径 4000px（8000m）/ 锁定速率 ×3 / 区内发射导弹追踪 G ×1.25。

---

## E. 航母 BOSS

**修电磁炮对同一艘舰的重复结算**（"一炮秒航母"的真正来源）：船体与它的挂点/弱点代理
（MountTarget）同时挂在 `CombatUnit.all_units` 里，而代理的 `take_damage` 会把伤害
**原样转发**母舰——一条 25px 半径的射线能同时扫到船体 + 4 个 CIWS 代理，
一发打出 5×150 = **750**，配合 `railgun_double` 补射基本两发入魂。
现按母舰归并，只保留**沿弹道最靠前**的那个命中点，一发一舰只结算一次。
**航母 HP 保持 1200 不变**——问题在穿排不在血量。飞机 / 地面单位的命中路径不受影响。

**舰队摆位地形校验**：`zone_data._snap_to_water` 只保证 BOSS 圈**圆心**在水面，
但舰队 bbox ≈1950×2200px、CV 还要沿航向来回跑 ±1500px——锚点靠岸时护卫舰会直接
刷在陆地上（此前**零校验**）。新增 `_pick_water_placement()`：候选朝向 45° 步长 ×
5 个锚点偏移，数 CV 巡逻两端 + 10 个护卫位有几个在陆地，取落地点最少的一组，
找到全水面解立即采用；结果写 EventLogger，仍有落地点时 `push_warning`。

---

## i18n

- 新增：`ADBS_CITY_HELIS_CLEARED_FMT`、`RADIO_AWACS_ONSTATION_1~3`、`RADIO_AWACS_EGRESS_1~3`（三语）
- 改写：`BOUNDARY_BTN_SUPPLY`（写明「战区时间 −30 秒」）、`ADBS_CITY_HELIS_FMT`（写明全歼可延长作战时间）
- 删除：`EVENT_ESCORT_TITLE` / `EVENT_ESCORT_SUCCESS` / `EVENT_ESCORT_FAIL`

## 验证

- `--bench=all` 回归门 **42/42 通过**
- 新增无头套件 `--bench=spawn_pool`（`scripts/tests/test_spawn_pool.gd`，35 条断言）：
  高度分档表结构与定位偏好（截击机永不落低空 / 攻击机永不落高空 / 多用途中空最多）、
  `patrol_altitude` 三档区间互不重叠、BOSS 机型隔离（含"光靠 cost 挡不住、黑名单不可删"
  这条钉死断言）、AF-03 出场参数与战区池在册、sig 权重乘区（同稀有度对拉命中率实测 0.710
  vs 理论 0.714）
- `test_attribute_gates` 新增 E2 三轴全队 9 条断言（套件 87 → 96）
- `verify_player_ref_holders.py` ✓ / `verify_doc_anchors.py` ✓
- 待 playtest：火箭弹削弱后的前中期压力 / AF-03 出场频率体感 / 高度分档的走位价值 /
  AWACS 180s 窗口节奏 / 城区直升机 +20s 是否值得绕路 / sig 卡 ×2.5 出率 /
  云块尺度 / 机炮锥淡化后的可读性 / 航母修穿排后所需击杀弹量

## 本批刻意不做

- **友军航母**：位置与生存性都不动（用户拍板）
- **航母 BOSS 血量**：保持 1200，只修穿排
- **不新增"不会反击"的 adds 内容**：Tu-160 高空轰炸波 / AH-64 攻击直升机编队
  没有接进刷怪池或事件（`_spawn_ah64_flock` 仍只有 F5 调试面板调用）
- **云的战术档位**：只调分布参数，"云中"仍只在 HIGH 档成立
