---
id: desert-theater
kind: map
status: in-progress
schema_version: 1
spec_version: 8
owner: user
depends_on: [map-2-3-preview, survivor-loop, airfield-liberation-zones, zone-atmosphere-combat, rotorcraft-combat, bosses/armored-train, events/the-crucible]
reconstruction_complete: true
---

# 赤土铁路正式战区

> 在纯陆地沙漠上延续 AGL 的空战小队核心，以据点占领、地面推进、炮战和直升机打击群形成可见的 RTS 战线；玩家不承担地面单位微操。

## 1. 设计意图（Why）

- **体验目标**：玩家飞越战区时能看见友军与敌军沿铁路工业走廊推进、互射和争夺据点；帮助友军解除包围、占领设施后，后续地面增援会真实从该设施驶向中央战线。
- **地图职责**：沙漠图是攻击机与对地构筑的优势场。没有海战；空战仍存在，但主要服务于保护或摧毁地面战线。
- **总体结构继承**：沙漠沿用海岸线的 600 秒战区主流程、支线结算、三座敌占机场与一次性机场补给点；地图差异只来自陆战内容、沙尘暴与 BOSS，不另改倒计时规则。
- **Litmus 自检**：遵守设计哲学 3「可见反馈」、7「热闹战场」、8「独特 BOSS」、10「全武器自动开火」与 11「60 FPS」。占领、生产和推进必须由真实单位与弹道表达，不只改隐藏倍率。
- **反模式规避**：不增加 RTS 选兵、编队或建造微操；不在未关注战区提前实例化整批演员；不复制海岸线的海战身份；不把海岛图内容提前混入本图。

## 2. 数据定义（What）

### 2.1 关卡基线

| 字段 | 值 | 说明 |
|---|---:|---|
| 地图 id | `desert_railway_preview` | 保留已发布的资源稳定 id；玩家可见文案移除“预览” |
| 战区阶段 | 600 s | 与海岸线当前标准一致；生涯商店既有延时仍可叠加 |
| 地图模式 | 正式 | 构造 ZoneData、ZoneMission、Spawner、王牌与 BOSS |
| 海战任务 | 0 | 沙漠全图为陆地；不得生成舰船任务 |
| 机场战区 | 3 | 只在内部沿用 `AF_HANEDA`、`AF_KISARAZU`、`AF_CHOFU` 三个稳定 id 兼容存档/统计；玩家可见名称、坐标与跑道全部由沙漠 MapDocument 覆盖，不得显示日本地名或沿用海岸线坐标 |
| 地面气氛覆盖 | 100% 已激活地面战区 | 未选择/未进入的普通战区仍保持 0 实体 |
| 初始中央战线 | 友军 3 辆 SPG vs 敌军 3 辆 SPG | 开局即在中央工业走廊形成一条可见战线 |
| 地面单位全局上限 | 每方 9 辆 | 包含初始与设施生产单位；阵亡后可补 |
| 地面速度 | 12 m/s | 沿设施到中央战线的预设路线移动 |
| 地面单位 HP | 60 | 可信火炮直击一发摧毁；玩家可正常攻击敌方 |

### 2.2 Pilbara 机场布局

底图权威范围为西澳 Pilbara 的 Mount Whaleback / Newman West，中心 `(-23.34718, 119.64044)`。真实地理锚点采用 Airservices Australia 公布的 Newman Airport：ARP 约 `(-23.41778, 119.80278)`，跑道 `05/23`、长 `2072 m`；按底图元数据投影后，为了给超级武器列车保留明确安全间隔，将玩法圆心向东南偏移约 `1.1 km` 至 `(8672,4318)`。Mount Whaleback 位于 Newman 以西约 6 km，地图铁路表达矿区重载走廊。

| 内部稳定 id | 玩家可见名称 key | 性质 | 圆心（px） | 跑道方向/长度 | 选址理由 |
|---|---|---|---:|---:|---|
| `AF_HANEDA` | `DOCK_NEWMAN_NAME` | 真实机场锚点 | `(8672,4318)` | `05/23`，约 `1036 px / 2072 m` | 以真实 Newman Airport 为锚点，向东南作约 1.1 km 玩法避让；远离超级武器列车路线 |
| `AF_KISARAZU` | `DOCK_WESTERN_RIDGE_NAME` | 虚构矿区作业机场 | `(-8500,-1500)` | `110/290`，约 `900 px / 1800 m` | 西部山脊外的开阔地，不压矿区建筑、山体或铁路安全走廊 |
| `AF_CHOFU` | `DOCK_OPHTHALMIA_NAME` | 虚构战时前线机场 | `(-3000,12000)` | `020/200`，约 `900 px / 1800 m` | Ophthalmia 南部开阔地，避开河道、建筑群与列车主线 |

- 两座虚构机场明确使用当地矿区/山地地名语感，不冒充现实民航机场。
- 三座机场圆心距 `iron_serpent_main` 铁路折线均须 `≥2500 px / 5 km`，距任意手工建筑轮廓须 `≥1200 px / 2.4 km`，且圆心不得落入山体多边形。
- 三座跑道多边形质心必须与对应机场战区圆心重合；机场解放、一次性补给点与友军防空伞都读取该地图覆盖后的圆心。

### 2.3 据点生产

| 字段 | 值 | 说明 |
|---|---:|---|
| 生产点来源 | 玩家攻克的非机场普通战区 | 机场继续走既有解放/补给语义 |
| 首批生产 | 攻克后立即 2 辆友军 SPG | 从战区圆心附近生成并驶向中央战线 |
| 后续周期 | 60 s | 每个已占领生产点独立计时 |
| 每周期产量 | 1 辆友军 SPG | 达到友军 9 辆上限时暂停，不累积欠单 |
| 敌军补充周期 | 75 s | 从东侧集结区补 1 辆，达到敌军 9 辆上限时暂停 |
| 中央战线 | `(1200,-1800) px` | 友军停在其西侧，敌军停在其东侧 |
| 火炮射程 | 2600 px | 5.2 km；集中控制器 2 Hz 选取最近合法地面目标 |
| 火炮射击间隔 | 4.5 s | 每车初始相位错开 |
| 炮弹飞行 | 2.2 s | 80 px 散布、24 px 直击窗口、60 伤害 |

### 2.4 直升机攻击群

| 字段 | 值 | 说明 |
|---|---:|---|
| 首批时间 | 90 s | 战区阶段内开始 |
| 后续间隔 | 150 s | BOSS 阶段停止新增 |
| 每批数量 | 4 架 AH-64 | 落在用户要求的 4–5 架组内 |
| 同时存活上限 | 5 架 | 防止连续批次堆叠 |
| 阵营 | HOSTILE | 只攻击 GroundUnit；不得攻击玩家或其它 Aircraft |
| 身份 | 气氛演员 | 非 TGT、Token=0；玩家击毁沿用 AH-64 既有经验规则 |

### 2.5 支线与时间轴

| 支线结果 | 时间效果 | 说明 |
|---|---:|---|
| `bomber_escort` 成功 | 0 s | 沿用海岸线：发放既有固定星级 XP，不提前进入 BOSS |
| `squadron` 成功 | 0 s | 沿用海岸线：正常攻克与奖励，不延长战区阶段 |
| 其它任务 | 0 s | 所有支线都不得改写沙漠倒计时；唯一时间变化继续来自海岸线共有的系统规则 |

## 3. 行为与公式（How）

### 3.1 正式入口

选择赤土铁路后加载既有 MapDocument，但 `preview_only=false`。ZoneData、ZoneMission、Spawner、王牌固定槽、倒计时、沙尘暴和 BOSS 事件全部启用。沙漠地图 BOSS 池在超级武器列车与 `THE CRUCIBLE` 间等权随机；陆地航母仍是另一个可停机/放飞舰载机的独立可指定 BOSS，不进入正式沙漠池。

### 3.2 地面战线

```text
capture(zone):
  register facility(zone.center)
  spawn 2 allied SPG toward allied front slot

every 60s per facility:
  if live allied SPG < 9: spawn 1

every 75s:
  if live hostile SPG < 9: spawn 1 from east staging

every 0.5s:
  each live SPG selects nearest hostile GroundUnit within 2600px
  if cooldown ready: snapshot one ballistic shell
```

炮弹命中只按发射时快照的目标实例、阵营和落点结算；目标释放、已毁或阵营不再敌对时只播落点，不访问旧对象。所有跨帧引用先做 Variant/实例有效性检查。

### 3.3 未关注战区与玩家职责

- 初始中央战线属于地图身份，固定 3v3；其它据点内容仍遵守选择/进入后才实例化。
- 玩家不直接指挥地面单位。玩家通过摧毁敌方地面目标、拦截 AH-64、攻克战区和保护生产点影响战线。
- 地面第三方火力不得替玩家完成正式 TGT；正式战区目标继续走既有非致死气氛伤害边界。

### 3.4 BOSS 转场

标准 600 秒倒计时结束后，普通刷怪与任务停摆并从沙漠池选择一个决战：

- `ARMORED_TRAIN` 从地图西侧场外进入，十四节严格沿金色双线主铁路驶向 Newman；玩家从车尾逐节打断，最后击毁车头胜利，当前车尾完整驶出则 Game Over。
- `THE_CRUCIBLE` 使用全部 17 支 Ace 队与背叛的 Hound-1/2，共 18 队 73 架的固定接力名册：开场三队、同屏最多三队，任一队全灭 3 秒后只补一队；玩家必须活到最后并歼灭所有敌机。

## 4. 结构与组成（Structure）

- 既有 MapDocument、瓦片、建筑、沙尘暴、Tab 与边界不分叉。
- `DesertFrontController` 集中拥有生产点、地面战线、火炮快照和直升机波次；不把新决策 tick 挂到每辆车。
- 地面演员复用 `AtmosphereArtilleryUnit` 与现有 GroundUnit 伤害/状态栏。
- 直升机复用 `SurvivorSpawner.spawn_atmosphere_ah64` 与既有旋翼机 GroundUnit-only 三道门。
- 超级武器列车 BOSS 由独立 boss spec 定义，接 BossRegistry/BossEncounterEvent。
- The Crucible 由独立决战事件 spec 定义；它是战斗主题而非同名 BOSS，复用 AceSquadProfiles 与 AceSupportSquad，不复制 18 队数据。
- 陆地航母由独立 boss spec 定义；连续履带舰体、停机甲板与舰载机起飞是其专属职责。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 地图选择赤土铁路后进入完整正式局，不再是空图预览；海岛图仍保持预览。
- [ ] 600 秒倒计时、普通刷怪、王牌固定槽、战区选择、奖励和沙尘暴均正常工作。
- [ ] 600 秒后列车与 The Crucible 等权可达；Debug 可分别直达，任一胜利均走同一沙漠结算。
- [ ] 初始中央 3v3 地面战线可见；炮弹与击毁真实发生。
- [ ] 攻克普通战区后立即驶出 2 辆友军 SPG，之后每 60 秒生产 1 辆，友军不超过 9。
- [ ] 至少一批 4 架敌方 AH-64 攻击 GroundUnit，且不攻击玩家或 Aircraft。
- [ ] `bomber_escort`、`squadron` 与其它支线均不改写沙漠倒计时，流程保持海岸线标准 600 秒。
- [ ] 三座机场分别显示 Newman Airport / Western Ridge Operations Strip / Ophthalmia Forward Airfield，不出现羽田、木更津、調布或其译名。
- [ ] 三座机场中心均位于陆地、避开山体，距铁路 ≥2500 px、距建筑 ≥1200 px；地图与战术地图的三座独立跑道分别对齐战区；三座可彼此独立解放并分别生成一个一次性机场补给点。
- [ ] 攻击机路线可凭既有对地武器明显更快清理地面目标；未引入攻击机专属隐藏伤害倍率。
- [ ] 成本合同：最坏 18 辆地面单位、5 架气氛 AH-64、现有空战人口、火炮快照与沙尘暴同时激活；集中火控 2 Hz，单位移动沿用 GroundUnit；跑 C1、C2、沙漠 S3 与沙漠专项 S2，稳态 `frames_below_60=0`、p1/worst ≥60。
- [ ] L1 完整局覆盖 Tab、至少一个地面战区、至少一座机场解放与补给、AH-64 波次、沙尘暴、火车 BOSS 成败之一与结算。
- [ ] 已知 seam：终态后继续至少一帧，控制器、火车与 BossEncounterEvent 不读取已释放对象。
- [ ] i18n：地图、Boss、失败原因和 Debug 文案三语齐全。
- [ ] 文档：本 spec 与火车 spec 已登记 `_INDEX`，reference 指针同步。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 文档、索引、玩家引用持有者与 diff 审计 | 通过 |
| E1 聚焦 Shadow | `armored_train` 32/32；`desert_theater` 29/29（含本地名称隔离、真实/拟真坐标、铁路/建筑/山体净空、独立解放与三个补给点） | 通过 |
| E2 集成 / 压力 Shadow | `lifecycle_gauntlet` 86/86；`all` 两次在约 66 秒被外部以 `-1` 终止，未产生断言失败或运行时错误块 | 本范围通过；整库 `all` 终态与 C1/C2/S3/S2 待补 |
| E3 Visual | `map_raster_desert` 与 Boss Debug 超级武器列车沙漠铁路中段 | 自动 Visual 启动通过；三机场全图构图与完整局仍待人工验收 |
| E4 完整局 | 12–20 分钟人工实玩 | 待用户验收 |

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 正式入口与时间轴
- [x] 沙漠地图从预览切为正式入口，保留海岛预览边界。
- [x] 固定沙漠 Boss 池；支线与 600 秒时间轴保持海岸线结构。

### 阶段 2 — RTS 地面战线
- [x] 实现集中地面战线、据点生产、敌军补充和火炮互射。
- [x] 接入 4 架 AH-64 攻击群与上限。

### 阶段 3 — 超级武器列车 BOSS
- [x] 接入十四节超长真实目标、底图铁路中心线 SSOT、双转向架贴轨与活动车钩、尾段递进破坏/断节加速、电磁炮 AOE、击毁胜利和当前车尾逃脱失败。
- [x] 加 Boss Debug 直达入口。

### 阶段 3b — The Crucible 王牌大混战
- [x] 17 支已实现非 BOSS Ace 队以最多三队的全灭接力序列入场，以独立 FFA 阵营真实互打；仇恨随候选 Ace 当前击坠数提高。
- [x] 接入 Boss Debug、复用常规王牌中队条的三队 HUD、禁用全部 Crucible 无线电并使用 Round Table 音乐槽位。

### 阶段 4 — 回归与收尾
- [ ] 补 focused / lifecycle / performance / Visual 与文档校验。
- [ ] 人工完整局验收后根据数据调参。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 地图入口 | `scripts/survivor/survivor_map_select.gd` |
| 地面战线 | `scripts/survivor/desert_front_controller.gd` |
| 时间效果与失败结算 | `scripts/survivor/survivor_mode.gd` |
| 超级武器列车 BOSS | `scripts/survivor/armored_train_boss.gd` · `scripts/survivor/armored_train_unit.gd` |
| The Crucible 王牌大混战 | `scripts/survivor/the_crucible_boss.gd` · `scripts/survivor/ace_support_squad.gd` |
| BOSS 接线 | `scripts/survivor/boss_registry.gd` · `scripts/events/boss_encounter_event.gd` |
| 地图数据 | `resources/maps/desert_railway_preview.aglmap` |
| reference 索引 | `docs/reference/script-index.md` · `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-09-02 | 8 | The Crucible 终局加入敌对 Hound-1/2 雇佣兵双机；只强化该敌对 duplicate，正常友军支援参数不变。 |
| 2026-09-02 | 7 | The Crucible 改为开场三队、同屏最多三队、灭队 3 秒补一队；加入 7.2 km 返场护栏并精确复用常规王牌中队条。 |
| 2026-08-30 | 1 | 用户批准沙漠图正式制作方向：火车 Boss、RTS 地面推进/包围/设施生产、4–5 架直升机攻击群、倒计时支线、沿用王牌与 600 秒海岸线基线、纯陆战偏攻击机。 |
| 2026-08-30 | 2 | 用户取消未经确认的护送跳时/中队延时设计：全部支线维持海岸线时间结构，固定 600 秒后进入 BOSS；同时把三座敌占机场、三组与战区中心对齐的可见跑道及其独立解放/补给点列为沙漠硬合同。 |
| 2026-08-30 | 3 | 纠正海岸线地理泄漏：日本机场名与坐标只留在海岸线；沙漠改为真实 Newman Airport + 两座 Pilbara 语境虚构机场，并以铁路、建筑和山体净空约束重新选址。 |
| 2026-08-31 | 4 | 配合十四节列车正式铁路终点，将 Newman 机场玩法圆心和跑道向东南偏移约 1.1 km，仍保持 05/23 朝向与真实尺度；当前净距铁路 2743 px、建筑 4753 px。 |
| 2026-09-01 | 6 | 明确 The Crucible 是战斗主题而非 BOSS/中队/角色；开场由前三支真实中队依次切镜且主题本身无无线电。内部仍复用决战阶段注册与结算。 |
| 2026-08-31 | 5 | 沙漠决战池扩为超级武器列车与 The Crucible 等权随机；新增六支 Ace 队依次进场、真实 FFA 混战、击坠数仇恨、中队无线电与专属音乐配置。 |
