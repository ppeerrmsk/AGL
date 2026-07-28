---
id: airfield-liberation-zones
kind: system
status: in-progress
schema_version: 1
spec_version: 3
owner: ppeerrmsk
depends_on: [zone-reward-docking, survivor-loop]
reconstruction_complete: false
---

# 机场解放战区（Airfield Liberation Zones）

> 三座机场（羽田 / 木更津 / 調布）开局是**敌占战区**，圆圈里驻着两三门地面防空、
> 靠近就有敌机升空迎战；把地面防空全清掉＝**解放机场**，机场就地变成一次性友军补给点
> （降落＝回血 / 进化 / 送僚机）。奖励就是这座机场本身。

## 1. 设计意图（Why）

- **体验目标**：把原本"开局白送的三个友军机场"改成**要打下来的目标**。地图上多三个
  固定地标级目标，玩家一眼看到"那有个机场被占了"，飞过去解放它 → 立刻得到一个能降落
  补给的据点。占领的爽点＝据点本身，不再堆抽象奖励。
- **与随机战区的分工**：A–G 是**随机轮换**的抽奖式战区（奖励池驱动）；机场是**固定地标**，
  每局同样的三座、同样的位置、目标恒为"解放"。两套并存互不干扰。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - *单杠杆 / 效果即反馈*：解放的反馈就是"机场亮了、能降落了"，不加 HUD 中介、不发抽象奖励卡。
  - *复用既有数值*：地面防空＝复刻原 ALLY 驻军编成（SAM×1 + AA×2）、升空迎战＝复用战区
    驻守机（garrison）刷怪链、降落补给＝复用 DockPoint。**零新机制，全是既有件重接线**。
  - *中队级粒度*：升空迎战按当前热度出一支符合难度的编队，不做逐机微操。
- **反模式规避**：不给机场战区塞军械库奖励（避免"目标即抽奖"）；不让机场解放去驱动 BOSS
  解锁（BOSS 早已改为**纯时间闸**，见 §3.5）——机场是独立目标层，不碰进度主线。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 三座机场战区（固定，开局全部可打）

| id | 名称 key | 补给点 key | 圆心（px） | 半径（px） | 方位 |
|---|---|---|---|---|---|
| `AF_HANEDA`   | `DOCK_HANEDA_NAME`（羽田机场） | `DOCK_HANEDA_NAME`   | `(1030, -6080)` | 2000 | 中部（HANEDA_AIRPORT 多边形质心，已烘焙为字面量） |
| `AF_KISARAZU` | `DOCK_KISARAZU_NAME`（木更津基地） | `DOCK_KISARAZU_NAME` | `(6844, 2381)`  | 2000 | 东南 |
| `AF_CHOFU`    | `DOCK_CHOFU_NAME`（調布机场） | `DOCK_CHOFU_NAME`    | `(-10434, -12864)` | 2000 | 西北 |

- **圆心来源**：与旧 `_spawn_airfield_docks` 的三处机场坐标完全一致（羽田＝
  `HANEDA_AIRPORT` 十顶点均值 = `(1030, -6080)`；后两者＝烘焙 aero 多边形质心）。
- **半径 2000**：留足地面防空散布（2000×0.85≈1700）与升空迎战盘旋（≥1800），且
  Chofu（y=-12864）− 2000 = -14864，仍在 ±15000 地图边界内（离边 ≥136，圆环贴边可接受）。
- **战区字段**：`mission_type = "airfield"`、`airfield = true`、`dock_name_key = <补给点 key>`、
  `label = "✈"`（战术地图圆心字符）。**无 `reward` 字典**（奖励＝机场本身，见 §2.4）。
- **初始状态**：三座全部 `AVAILABLE`（开局即在战术地图上可见、可前往）。
  **不 roll** 奖励 / 任务类型；难度不预 roll，改由首刷时按当前热度动态定档（§2.3）。

### 2.2 地面防空编成（TGT —— 打完＝解放）

固定小编队，**复刻原 ALLY 机场驻军的数量**（用户："数量大概和我们原本的版本一样，两三个"）：

| 单位 | 数量 | 资源 | 说明 |
|---|---|---|---|
| SAM（防空导弹） | 1 | `sam_launcher.tres`（敌版，team=1） | 复用现有 SAM 场景/参数 |
| AA（高炮） | 2 | `aa_gun.tres`（敌版，team=1） | 复用现有 AA 场景/参数 |

- 共 **3 个地面 TGT**，HP 不随难度缩放（直接用基础 params，与原 ALLY 驻军对称）。
- 落点：走 `_find_valid_spawn_pos` 严格陆地判定 + 间距 + 距路（三门都落在机场那块陆地上）。
- **完成判定**：这 3 个 TGT 全部被击毁 → 机场解放（触发 §3.1 解放流程）。
- 触发（激活任务）沿用双通道：玩家进入圆 / 圈外击中任一 TGT（复用 `_should_trigger`）。

### 2.3 升空迎战（Air Defenders —— 非 TGT，难度＝当前热度）

靠近机场时升空迎战的敌机，走**既有战区驻守机（garrison）刷怪链**，规模按"当前热度"定档：

**热度 → 难度档（首刷该机场时计算一次并写入该区难度）**

| 当前 heat | 机场难度档 |
|---|---|
| `heat < 34`      | 1★ |
| `34 ≤ heat < 67` | 2★ |
| `heat ≥ 67`      | 3★ |

- `heat` 读 `SurvivorSpawner._roe.heat`（0–100，ROE 热度账本；静默地板＝`level×5` 封顶 75，
  见 spec global-awareness-roe §2.4）。热度天然随局势升温 → "当前难度/热度"直达。
- 定档后调 `ZoneData.set_airfield_difficulty(id, star)`（写 `_difficulties[id]`），使
  **战术地图显示的星级、升空迎战规模、机型选型**三者一致。
- 升空迎战规模 / 机型：完全走既有 `_spawn_zone_defenders(zone_id, zone, "airfield")`
  —— Token 预算 `zone_defender_budget(star, level)`、等级加权池、成建制中队盘旋。
  即"机场按当前热度对应难度，刷出一支符合难度的编队升空迎战"。
- **无海上 / 精英 / 雷达站附加**：机场恒为陆基防空 + 空中迎战，不 roll 其它任务类型。

### 2.4 奖励 —— 机场本身（一次性补给点）

解放后**不发军械库奖励**（用户拍板："只给机场"）。奖励＝在该机场圆心创建一个
**一次性友军补给点**（DockPoint）：

| 字段 | 值 | 说明 |
|---|---|---|
| `dock_kind` | `"airfield"` | 复用现有机场停靠外观 / 判定 |
| `radius` | 600 | DockPoint 默认 |
| 一次性 | 是（`_spent` after 1 landing） | 用户："一次性"；降落一次即关闭、标记消失 |
| 着陆功能 | 全队回血 + 进化结算 + 送 1 架僚机 | 复用 `_on_dock_docked` 既有全套 |
| 友军防空伞 | 解放**即刻**逐个刷出 SAM×1 + AA×2（ALLY） | 复用 `_spawn_airfield_garrison` 编成；**渐进刷出**，不 dock 门控 |

- **友军防空伞（用户 2026-07-24 订正）**：一旦机场被打下来（解放），就在该机场**逐渐刷出**
  友军防空单位（SAM×1 + AA×2，ALLY），**不要求玩家降落 / 停靠**才出现。
  - "渐进刷出"＝逐个入场而非一次性全出：解放起每 `AIRFIELD_ALLY_SPAWN_INTERVAL = 4.0s`
    刷出一个（顺序 SAM → AA → AA，共 ~8s 布防完成），营造"友军接管、防空陆续到位"的观感。
  - 与降落解耦：即使玩家打完就飞走、从不降落，防空伞照样刷齐并原地驻守。
  - 落点：机场圆心附近的原 ALLY 驻军偏移（`(240,0)` / `(-170,±150)`，复刻原编成）。
  - 敌占期间机场只有敌方地面防空；解放后才有友军防空伞。

### 2.5 几何约束裁决 —— 机场豁免 map-expansion §2.4（权威裁定，2026-07-26）

**冲突**：map-expansion §2.4 要求任意两战区缘距 ≥2000 px、离边 ≥1500 px——那是给
**可自由布点的随机战区**（A–G + BOSS 锚点）定的验收几何。机场战区圆心是现实机场
烘焙质心（§2.1，**不可挪**），从未满足过该约束（2026-07-26 确认为既有腐烂，非当日引入）：

| 违反项 | 实测值 | §2.4 要求 |
|---|---|---|
| B↔AF_HANEDA 缘距 | 1651 | ≥2000 |
| D↔AF_KISARAZU 缘距 | 1670 | ≥2000 |
| F↔AF_HANEDA 缘距 | 1332 | ≥2000 |
| G↔AF_KISARAZU 缘距 | 1256 | ≥2000 |
| AF_CHOFU 离边 | 136 | ≥1500 |

**裁定：豁免机场（方案①），不缩半径（方案②否决）**。理由：

- 缩半径救不了 AF_CHOFU——离边 1500 达标需要半径 ≤636；F↔AF_HANEDA 达标需要羽田
  半径 ≤1332。两者都击穿 §2.1 的半径预算（2000 = 地面防空散布 ~1700 + 升空盘旋 ≥1800）。
- §2.4 的 2000/1500 本意是防随机战区互相咬合 + 留增援走廊；机场是**固定地标**，
  位置本身就是设计（现实机场），与随机战区 1.2~1.7 km 的间隙已足够避免目标混淆。

**豁免不等于裸跳过**——机场战区仍须满足弱化下限（回归测试强校验，防未来改半径/挪
随机战区时真出事）：

| 约束（凡机场参与的组合） | 下限 | 现值最紧 |
|---|---|---|
| 与任意战区缘距 | ≥ **1000 px**（不重叠 + 最小走廊） | G↔AF_KISARAZU 1256 |
| 圆边距地图边界 | ≥ **0 px**（圆整体在图内） | AF_CHOFU 136 |

随机战区之间（无机场参与）仍按 §2.4 原值 2000/1500 强校验。落地：
`test_map_expansion.gd::_check_zone_geometry` 按 `airfield` 字段分派双阈值。
map-expansion §2.4 已同步标注适用范围与本裁决指针。

## 3. 行为与公式（How）

### 3.1 机场生命周期状态机

| 状态 | 触发 | 表现 |
|---|---|---|
| **敌占（AVAILABLE）** | 开局 | 战术地图红圈 + ✈ + "解放机场" 目标；玩家靠近（off-screen 时）刷 3 门地面防空 + 升空迎战 |
| **交战（SELECTED / triggered）** | 玩家进圆 或 击中任一地面 TGT | 地面 TGT 打 TGT 标记；升空迎战编队接战 |
| **解放（CLEARED）** | 3 门地面 TGT 全灭 | 红圈消失；圆心生成一次性友军补给点；**即刻起逐个刷出 ALLY 防空伞**（每 4s 一个，不 dock 门控）；升空迎战残余撤离（视线外 free）；`+HEAT_ZONE_CAPTURED` |
| **补给点用尽（spent）** | 玩家降落一次 | 补给点标记消失、不再判定（ALLY 防空伞原地保留） |

- 解放**不触发** `_refresh_availability_after_clear` 的战区重开逻辑（机场一次性，不进重开池）。
- 解放**不参与** A/B→E 解锁、`_last_cleared`、奖励池去重（走独立 `liberate_airfield()` 路径）。
- BOSS 阶段（时间闸到点）：机场战区与 A–G 一样被 `lock_all_open_zones_except` 关闭、战术地图隐藏。

### 3.2 难度定档伪代码（首刷时）

```
on 首次 _spawn_zone_units(airfield_zone):
    star = 1 if heat < 34 else (2 if heat < 67 else 3)   # heat = _spawner._roe.heat
    zones.set_airfield_difficulty(id, star)
    spawn_airfield_ground(id)          # 固定 1 SAM + 2 AA（TGT）
    _spawn_zone_defenders(id, zone, "airfield")   # 升空迎战，规模按 star + level
```

### 3.3 战术地图（Tab）绘制规则

- 机场战区 `AVAILABLE/SELECTED` → 画红圈 + ✈ + 难度星（星＝§2.3 定档，未定档前按 1★ 占位显示）。
- 机场战区 `CLEARED` → **隐藏圆圈**（`_should_hide_zone` 对 airfield+CLEARED 返回 true），
  改由 `_draw_dock_markers` 画激活后的机场补给点图标（青绿跑道框 + 名称）。
- 敌占期间机场补给点**不画**（补给点在解放时才创建）。

### 3.4 战术地图（Tab）信息面板过时项修正（用户："很多信息过时"）

现状腐烂点（`tactical_map._refresh_info` 奖励块）：读 `reward.get("desc")` / `reward.get("category")`
——但新奖励字典（`ZoneData._assign_reward`）只有 `kind/quality/id/name/weapon`，导致轴标题恒显
"▸ 生存"、描述恒空。**修正**：奖励块改按 `kind` 渲染，删除 survival 轴/desc 死路径：

| kind | 图标 | 显示 |
|---|---|---|
| `carrier` | ⚓ | `tr(name)`（增援航母） |
| `wingman` | ✚ | `tr(name)`（忠诚僚机） |
| `weapon` | ⌁ | `tr(name)`（对应武器件） |
| `nextgen` | ◆ | `tr(name)`（次世代技术） |

- 机场战区（`airfield=true`）信息面板：目标行显示 `tr("ZONE_MISSION_AIRFIELD")`，
  奖励行显示 `tr("ZONE_REWARD_AIRFIELD")`（"解放后机场开放补给"），不显示星级抽奖式奖励。
- 顺带：从战场简报轮播 `_TIP_KEYS` 移除 `TACTICAL_TIP_STAMINA`（飞行员耐力已移除，
  i18n 键按 [[project_pilot_stamina_reserved]] 保留但不再轮播）。

### 3.5 与 BOSS / 战区阶段的关系（澄清：文档曾过时）

- 现状 BOSS **纯时间闸**：`game_time` 跨 `WARZONE_PHASE_DURATION`(600s) → `_check_warzone_phase_timeout`
  解锁 BOSS。`ZoneData` 里"攻克 3 次解锁 BOSS / cleared_count 驱动"注释**已作废**（本 spec 一并标注，
  不复活该耦合）。
- 机场解放**不改** `cleared_count`、不 `finalize_boss_placement`、不设 `boss_unlocked`——完全独立。

## 4. 结构与组成（Structure）

- **`ZoneData.ZONES`**：追加 3 条 airfield 战区（含 `airfield/dock_name_key/label` 字段）；
  `_init` 置三者 AVAILABLE，跳过 reward/difficulty/mission_type 的 roll。
  新增：`is_airfield(id)`、`set_airfield_difficulty(id, star)`、`liberate_airfield(id)`。
  守卫：`_refresh_availability_after_clear` 的重开池 `if is_airfield(zid): continue`。
- **`ZoneMission`**：`_spawn_zone_units` 增 `"airfield"` 分支 → 定档 + `_spawn_airfield_ground`
  （1 SAM + 2 AA，TGT）+ `_spawn_zone_defenders`。完成判定 / 触发复用现链。
- **`survivor_mode`**：
  - 删除开局 `_spawn_airfield_docks` 造 3 个 active dock + 全场 `_spawn_airfield_garrison`；
  - 改为 `_liberate_airfield(zone_id)`：造该机场 DockPoint（active，一次性）+ 部署该机场 ALLY 防空伞 +
    `_tactical_map.set_docks` 刷新；
  - `_on_zone_mission_completed` 分流：`is_airfield` → `liberate_airfield()` + `_liberate_airfield()`；否则原奖励流。
- **`TacticalMap`**：`_should_hide_zone`（airfield+CLEARED→隐藏）、`_draw_one_zone`（airfield 目标/奖励文案）、
  `_refresh_info`（§3.4 kind 化 + airfield 文案）、`_TIP_KEYS`（去 stamina）。
- **`DockPoint`**：无需改（一次性 `_spent` 语义已具备）。
- **i18n**：`ZONE_MISSION_AIRFIELD`、`ZONE_REWARD_AIRFIELD`（三语）。机场/战区名复用 `DOCK_*_NAME`。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 开局战术地图上三座机场显示为红色战区圆（✈ + "解放机场" 目标），无补给点图标。
- [ ] 靠近某机场：刷出 1 SAM + 2 AA（地面 TGT）+ 一支符合当前热度难度的升空迎战编队。
- [ ] 低热度靠近＝1★ 小编队；高热度靠近＝3★ 编队（EventLogger `PreSpawnAirfield` 可见 star）。
- [ ] 打光 3 门地面防空 → 红圈消失、圆心出现友军机场补给点。
- [ ] 解放后即使**不降落**，ALLY 防空伞（SAM×1+AA×2）也逐个刷出（~每 4s 一个，~8s 布防齐）。
- [ ] 降落该机场一次 → 全队回血 + 进化结算 + 送僚机；补给点随即标记消失（一次性）。
- [ ] 三座机场互相独立；解放一座不影响另两座；均**不**改变 BOSS 解锁时机（仍 600s 时间闸）。
- [ ] Tab 悬停任意战区：奖励块正确显示 kind（航母/僚机/武器/次世代），**不再出现"生存"死词**。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（机场刷怪走既有链，无新每帧扫描）。
- [ ] 已知 seam：新 DockPoint 走 `mode` 每帧解析玩家机（不缓存 player_ref）；`verify_player_ref_holders.py` 通过。
- [ ] i18n：`ZONE_MISSION_AIRFIELD` / `ZONE_REWARD_AIRFIELD` 三语补齐；无硬编码中文玩家文本。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据层（ZoneData）
- [x] `ZONES` 追加 3 条 airfield 战区（字段见 §2.1）
- [x] `_init` 置三者 AVAILABLE，跳过 reward/difficulty/mission_type roll
- [x] 新增 `is_airfield(id)` / `set_airfield_difficulty(id, star)` / `liberate_airfield(id)` + `AIRFIELD_IDS`
- [x] `_refresh_availability_after_clear` 重开池排除 airfield

### 阶段 2 — 刷怪层（ZoneMission）
- [x] `_spawn_zone_units` 增 `"airfield"` 分支：热度定档 + `_spawn_airfield_ground`（1 SAM + 2 AA）+ `_spawn_zone_defenders`
- [x] `PreSpawnAirfield` EventLogger 记录（star / heat / defenders）

### 阶段 3 — 解放 + 补给点（survivor_mode）
- [x] 删开局 `_spawn_airfield_docks` 造 active dock + 全场 ALLY 驻军
- [x] `_liberate_airfield(zone_id)`：造一次性 DockPoint + set_docks 刷新 + 启动**渐进** ALLY 防空伞刷出（每 4s 一个，与 dock 解耦）
- [x] `_on_zone_mission_completed` 分流 airfield → 解放路径（不发奖励、不 mark_cleared churn）
- [x] `_zone_label` 机场 toast 显示机场名（非 ✈ 圆心字符）

### 阶段 4 — 战术地图 UI（TacticalMap）
- [x] `_should_hide_zone`：airfield + CLEARED → 隐藏圆
- [x] `_draw_one_zone`：airfield 目标/奖励文案（✈ + 解放）
- [x] `_refresh_info`：奖励块 kind 化（删 survival/desc 死路径）+ airfield 专属文案
- [x] `_TIP_KEYS` 去 `TACTICAL_TIP_STAMINA`

### 阶段 5 — i18n + 收尾
- [x] `ZONE_MISSION_AIRFIELD` / `ZONE_REWARD_AIRFIELD` / `ZONE_AIRFIELD_LIBERATED_FMT` 三语（csv + 三份 .translation 重导）
- [x] 数据层单测进 `test_zone_rewards.gd`（22/22 PASS）；`--bench=all` 回归门 37/37 PASS
- [x] `verify_player_ref_holders.py` 通过；`verify_doc_anchors.py` 修掉本次改动引入的 6 处 survivor_mode 锚点位移
- [x] 回填 §7 锚点 + 同步 reference 索引（code-index / script-index）
- [ ] §5 §5 playtest（进引擎实飞验证：靠近刷怪 / 解放开补给 / 渐进 ALLY / Tab 文案）

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 战区数据 / 状态 | `scripts/survivor/zone_data.gd` |
| 刷怪（地面 TGT + 升空迎战） | `scripts/survivor/zone_mission.gd` |
| 解放 + 补给点 + ALLY 防空伞 | `scripts/survivor/survivor_mode.gd` |
| 战术地图绘制 / 信息面板 | `scripts/survivor/tactical_map.gd` |
| 补给点组件 | `scripts/survivor/dock_point.gd` |
| 数据层单测 | `scripts/tests/test_zone_rewards.gd`（`_test_airfield_zones`，bench key `zone_rewards`） |
| i18n | `i18n/translations.csv` + `.en/.ja/.zh.translation` |
| reference 索引行 | code-index.md「机场解放战区」行 / script-index.md ROE 行 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-24 | 1 | 初稿（三机场解放战区：敌占→解放→一次性补给点；难度＝热度；Tab 奖励块去"生存"死词；BOSS 纯时间闸澄清） |
| 2026-07-24 | 2 | 用户订正：友军防空伞在**解放即刻渐进刷出**（每 4s 一个，不 dock 门控）；status → approved |
| 2026-07-26 | 3 | 新增 §2.5：裁决机场豁免 map-expansion §2.4 几何约束（缩半径方案否决，因击穿 §2.1 半径预算）；弱化下限 缘距 ≥1000 / 离边 ≥0 进 test_map_expansion 强校验 |
