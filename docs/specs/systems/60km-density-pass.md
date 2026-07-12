---
id: 60km-density-pass
kind: balance
status: in-progress   # 代码落地 + 无头回归绿；差 playtest 手感确认 + Sentinel+Lv5 压测
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [map-expansion, reinforcement-ingress, survivor-loop]
reconstruction_complete: true
---

# 60km 密度调优 —— 战区范围 / 任务规模 / 目标丰富化 / 整体热度

> 玩家视角：地图变大后敌人不再显得稀疏——战区更大更满、任务目标更有层次、
> 增援与追击的压力全面上调。2026-07-06 playtest 反馈驱动（"地图变大了但敌人有点少"）。

## 1. 设计意图（Why）

- 60km 扩图后面积 ×4，而所有密度旋钮还是 30km 时代的标定 → 单位面积热度掉到 1/4 观感。
- 本 pass 不改任何机制，只调旋钮 + 两处小的组合丰富化；机制层（入场/战区循环）不动。
- Litmus：难度可读（各旋钮线性、可回退）；性能有 FPS 动态降载兜底 + 压测门。

## 2. 旋钮总表（What —— 全部数值，旧 → 新）

### 2.1 战区范围（zone_data）

| 战区 | 半径 旧→新 | 备注 |
|---|---|---|
| A / C / D | 2500 → **3500** | 60km 空间充裕 |
| B | 2500 → **3000**，center y -11000 → **-10500** | 陆带贴北界，内收保住离边 ≥1500 |
| E | 1800 → **2500** | naval/elite 区 |

复验（tests/test_map_expansion.gd 全绿）：最小缘距 C↔E 3020 px、离边最小 B 1500 px；
陆地占比 A 1.00 / B 0.53 / D 0.98。

### 2.2 战区任务规模（survivor_data + zone_mission）

| 旋钮 | 旧 | 新 |
|---|---|---|
| 地面 TGT（SAM+AA） | ★2+2 / ★★3+3 / ★★★5+5 | **★3+3 / ★★4+4 / ★★★6+6** |
| 空战中队规模 | ★3 / ★★4 / ★★★5 | **★4 / ★★5 / ★★★6** |
| 驻守预算基数 | ★8 / ★★15 / ★★★30 | **★12 / ★★22 / ★★★42** |
| 驻守预算每级增幅 | +8% | **+10%**（Lv10 ≈ ×1.90） |
| 精英 Sentinel 护卫 | 5~8 | **6~10** |
| 空战/驻守盘旋环 | 固定 1200 / 1800 | **max(地板, zone.radius × 0.48 / 0.72)**（r3500 时 ≈1680 / 2520，占满扩大后的圈） |

### 2.3 任务目标丰富化（zone_mission）

1. **雷达站 TGT**：★★+ 地面战区附带雷达站（★★1 座 / ★★★2 座，`radar_count` 进
   `ground_tgt_scale`），刷在 scatter×0.6 内圈受 SAM 环保护；datalink 给全区共享 20km
   感知——**先打雷达可削弱战区预警**，给地面任务加"打法顺序"层次。计入 TGT 清除条件。
2. **空战中队队长机**：长机机型按 `tgt_lvl + 2` 选型（僚机维持 tgt_lvl），
   混编"队长机"质感；池子仍走 squad-friendly 过滤（不会抽到强制单机的 MiG-31）。

### 2.4 整体热度（survivor_data + spawner）

| 旋钮 | 旧 | 新 |
|---|---|---|
| Token 预算 | 5 + int(level×1.5)，cap 45 | **8 + int(level×1.8)，cap 55**（Lv1=9 · Lv10=26 · Lv20=44 · Lv27+=55） |
| 旅途刷怪间隔 | 45 → 25 s（按等级插值） | **32 → 18 s**（边缘入场有 60~120s 运输延迟，节奏前移补偿） |
| 实例上限 | 30 默认 / 40 硬 | **36 / 48**（FPS 动态降载兜底；须过 Sentinel+Lv5 压测） |
| 开局驻防中队 | 2 | **3** |
| hunter 追击配额 | max(2, 1 + level/3) | **max(3, 2 + level/2)**（大图 + 锚点巡逻后主动压力全靠 hunter） |

### 2.5 附带修复

- **教程轰炸机锚点**（adbs_manager）：旧值写死 `(0, 3000)`（30km 时代绝对坐标，扩图后距
  出生点 10.9km）→ 改为 `PLAYER_START_OFFSET_PX + (0, -TUTORIAL_LEAD_DIST_PX)` 派生
  （出生点正前方 3000 px，再挪出生点不会坏）。

### 2.6 热度第二轮（2026-07-06 同日追加，用户："总体热度再变高，更早的敌机以小队方式出现"）

| 旋钮 | 旧 | 新 |
|---|---|---|
| 刷怪选型有效等级 | level | **level + SPAWN_HEAT_LEVEL_SHIFT(2)**——全部解锁门/概率公式统一前移 2 级：战斗机小队更早登场、UAV 杂鱼更早退场；只影响选型，不影响间隔/预算/HP 缩放 |
| 每波数量增长 | 0.3/级 | **0.4/级** |

连带（非本 spec 但同批）：进化树 tier 门槛 4/8 → **10/18（3 阶暂定）**，evolution_tree.json 已改，
详见 aircraft-evolution §8 v3。

## 3. 明确不动项

- naval 舰队编成（1/2/3 星）——舰队平衡独立，另行调。
- 增援入场机制（锚点盘/EGRESS/冻结豁免）与战区循环机制——只调数值不动结构。
- 敌人 HP/伤害缩放曲线、XP 曲线。

## 4. 验收（Acceptance）

- [x] tests/test_map_expansion.gd 全绿（新半径几何 + 陆地占比 + parse 冒烟含 zone_mission/adbs_manager）
- [ ] playtest：教程轰炸机在出生点正前方 ~3km 可见
- [ ] playtest：战区观感"更大更满"（TGT+雷达站层次 / 守军铺满圈 / 中队 4~6 机）
- [ ] playtest：旅途压力上行（增援更频繁、hunter 更缠人、开局 3 驻防队）
- [ ] 性能：Sentinel + Lv5+ 压测 FPS 掉幅 < 15（实例上限 36/48 是本 pass 最大性能变量）
- [ ] i18n：无新增玩家可见文本（雷达站复用既有单位名）

## 5. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 战区半径/坐标 | `scripts/survivor/zone_data.gd` |
| 任务规模/预算/热度常量 | `scripts/survivor/survivor_data.gd`（ground_tgt_scale / air_squadron_count / ZONE_DEFENDER_* / TOKEN_BUDGET_* / TRAVEL_* / MAX_ENEMIES_* / OPENING_GARRISON） |
| 雷达站 TGT / 队长机 / 盘旋环缩放 | `scripts/survivor/zone_mission.gd` |
| hunter 配额 | `scripts/survivor/survivor_spawner.gd`（_update_hunters） |
| 教程轰炸机锚点 | `scripts/survivor/adbs_manager.gd` |
| 回归 | `scripts/tests/test_map_expansion.gd` |

## 6. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-06 | 1 | 初版落地：playtest 反馈驱动的整批旋钮（范围/规模/丰富化/热度）+ 教程轰炸机锚点修复；无头回归绿 |
| 2026-07-06 | 2 | 热度第二轮（§2.6）：选型等级 +2 前移 + 波次增长 0.4；同批进化门槛后移记录 |
