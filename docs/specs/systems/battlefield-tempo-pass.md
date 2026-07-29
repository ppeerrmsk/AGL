---
id: battlefield-tempo-pass
kind: balance
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 1
owner: noelu（设计输入）/ Claude（细化 + 落地）
depends_on: [reinforcement-ingress, global-awareness-roe, 60km-density-pass, survivor-loop, map-expansion]
reconstruction_complete: true
---

# 战场节奏批 —— 拦截波（以玩家为目标的进场敌机）+ 新战区 F/G

> 玩家视角：旷野不再冷场——你在哪里，敌机就从你面前的地图边缘成队压过来；
> 地图上多了两块新战区，候选池更满、重复更少。战区里热闹、旷野上也有仗打。

## 1. 设计意图（Why）

### 1.1 用户反馈（2026-07-22，本批驱动源）

- 热度太低、经验值偏少、经常冷场；
- 某个战区会突然刷出很多敌人，但没有敌人从边缘进场来攻击玩家；
- 之前做过类似调整（磁吸航点/hunter），但现在很不直观——缺"慢慢进场袭击玩家、以玩家为目标"的敌机；
- 需要新战区，让地图热闹起来。

### 1.2 根因链（已实证）

1. [reinforcement-ingress](reinforcement-ingress.md) 改造后，**全部**旅途增援走"边缘 → 中央锚点
   ONSTATION 盘旋"，没有任何一类敌机以玩家为目标进场；
2. 主动压力唯一来源是 ROE 热度的 hunter 配额（[global-awareness-roe](global-awareness-roe.md)），
   但 hunter 只能**抽调场上已有的 PATROL 闲兵**——玩家附近抽调池空时，配额再高也造不出压力；
3. 玩家远离锚点盘/战区 → 附近无敌机 → 无击杀 → XP 停滞 → 高价值敌机不解锁 → 更冷。

拦截波打在 1、2 两个根因上：**hunter 配额有缺口时，下一波增援不再去中央锚点，
而是以拦截使命从玩家前方边缘入场、航点持续指向玩家**，由既有 hunter tick 自然收编。

### 1.3 Litmus 自检（DESIGN_PHILOSOPHY）

- **原则 7 战场热闹**：本批正是该原则的执行（多线交战、旷野有压力）。
- **信息察觉**：拦截队从玩家前方边缘进场（Tab 图一队红点直奔你），可预判、可拦截、可规避。
- **单杠杆**：拦截触发只有一个条件（hunter 配额缺口），无概率旋钮、无档位；缺口大 → 必来，
  hunter 满额 → 必不来，天然自平衡。
- **反模式规避**：不新增每帧逻辑（全部骑既有 spawn / 8 s / 5 s tick）；不做"传送"式修正，
  拦截队全程物理飞行。

### 1.4 与既有调参批的边界（保归因能力）

[60km-density-pass](60km-density-pass.md) 两轮热度旋钮（token 预算 / 间隔 / hunter 配额 /
实例上限）**尚未 playtest 确认**。本批**不叠加任何数值旋钮**：token 预算、XP 曲线、刷怪间隔、
战区任务规模全部不动。本批只做**结构性**增压（拦截波 + 新战区 + 姊妹 spec
[ace-support-squadron](../events/ace-support-squadron.md) 的时间延长），playtest 后若热度仍不足，
再回 density-pass 调旋钮。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 拦截波常量

| 常量 | 值 | 说明 |
|---|---|---|
| `INTERCEPT_QUOTA_GAP` | 2 | hunter 配额缺口 ≥ 此值时，本波旅途增援转为拦截波 |
| 入场扇区 | 玩家 heading ±90° | 拦截队只从玩家前半球方向的边缘进场（[[feedback_event_spawn_ahead]]：不从身后偷袭，玩家看得见来路） |
| 入场点距玩家 | ≥ 5000 px | 沿用 `INGRESS_MIN_PLAYER_DIST_PX`，不新增常量 |
| 航点刷新 | 8 s | 骑既有敌机航点 tick；拦截队 TRANSIT 航点 = 玩家当前位置 |
| hunter 收编 | ≤ 4000 px / 5 s | 沿用既有 hunter 资格与 tick，零改动 |

### 2.2 新战区 F / G

| 字段 | F | G |
|---|---|---|
| id | `F` | `G` |
| 名称 | 荒川北岸（都心北内陆） | 千叶中部 |
| center | (-1500, -11000) | (10800, -1800) |
| radius | 2200 px | 2500 px |
| mission_type | ground | air |
| 初始 state | LOCKED（进再激活候选池） | LOCKED |

几何自检（约束：离边界 ≥1500 px、任两区缘距 ≥2000 px，世界半宽 15000 px）：

| 检查 | 值 | 判定 |
|---|---|---|
| F 离边界 | 15000 − 11000 − 2200 = 1800 | ✓ |
| F ↔ A(-6400,-5000,r3500) 缘距 | ≈ 2047 | ✓（压线，实现后必跑 test_map_expansion 复核） |
| F ↔ B(6000,-10500,r3000) 缘距 | ≈ 2317 | ✓ |
| G 离边界 | 15000 − 10800 − 2500 = 1700 | ✓ |
| G ↔ B 缘距 | ≈ 4436 | ✓ |
| G ↔ D(9600,9000,r3500) 缘距 | ≈ 4866 | ✓ |
| G ↔ E(800,7000,r2500) 缘距 | ≈ 8320 | ✓ |

备用方案：F 为 ground 区，需陆地占比 ≥ 0.12（都心北内陆预期全陆）。若烘焙陆判不达标 →
优先把 F 东移/北收再测；仍不行则改 mission_type: air（air 区不查陆地）。

### 2.3 明确不动项

| 项 | 保持 |
|---|---|
| Token 预算 / 刷怪间隔 / 实例上限 / hunter 配额公式 | 不变（density-pass 待 playtest，见 §1.4） |
| XP 曲线 / 击杀 XP | 不变（XP 提升靠拦截波送上门 + ace-support +60 s 成长窗口） |
| 战区任务规模 / 驻守预算 / 再激活规则（攻克 1 开 2，CLEARED 1.5×） | 不变（候选池 4→6 自然摊开） |
| E 区特殊解锁（A+B 清后 0.60 概率） | 不变，F/G 走普通 LOCKED 候选 |
| 锚点巡逻 / EGRESS / 开局驻防 | 不变（非拦截波照旧全套 ingress 生命周期） |

## 3. 行为与公式（How）

### 3.1 拦截波判定（骑既有旅途刷怪 tick）

```
每次旅途增援 spawn 时：
  gap = hunter_quota(热度) − 当前在册 hunter 数
  gap ≥ INTERCEPT_QUOTA_GAP(2) → 本波为拦截波（intercept = true）
  否则                         → 普通增援（边缘 → 中央锚点，行为照旧）
```

选型不变：拦截波刷**什么**完全走既有 `_pick_enemy_type` 加权（当级正常强度、杂鱼 ≥2 建制），
只改**去哪**。

### 3.2 拦截队生命周期

| 阶段 | 行为 |
|---|---|
| 入场 | 入场点 = 玩家 heading ±90° 扇区内、距玩家 ≥5000 px 的合法边缘点（复用边缘候选点算法，仅加扇区过滤；扇区内无合法候选 → 全周长回退）；生成于边界外、机头指向玩家 |
| TRANSIT（拦截） | 打 `reinf_intercept` 标记；航点 = 玩家当前位置，每 8 s tick 刷新；**永不转 ONSTATION**（无到站判定） |
| 接敌 | 双保险：① ROE 中队感知圈（长机雷达距离全向）飞近自然察觉交战；② hunter tick 对距玩家 ≤4000 px 者照常收编（TS_BOSS 强制指派）。收编后计入 hunter 在册数 |
| 交战后 | 与普通敌机完全一致（BFM / 压力 / 脱离全走既有 AI） |
| 退场 | 拦截队永不 ONSTATION → 天然不满足 EGRESS 资格（使命即咬住）；远距清理豁免沿用 reinforcement 类别 |

### 3.3 与既有系统的守恒关系

- 拦截波**消耗的就是本该发生的那次旅途增援**（同 token、同间隔、同选型）——总刷怪量不变，
  只是冷场时把增量投放到玩家面前，热闹时投放到中央战场。
- hunter 配额语义不变：拦截队被收编后占配额名额，配额满 → 不再触发拦截波 → 闭环收敛。

## 4. 结构与组成（Structure）

- 无新节点/子控制器。拦截判定住在旅途刷怪入口；扇区选边是边缘候选点算法的一个参数化分支；
  拦截航点是 reinforcement 航点 tick 的一个 if 分支。
- 单位标记：沿用 `category="reinforcement"`，新增 `reinf_intercept: bool` meta
  （与 `reinf_phase` 正交：phase 表生命周期，intercept 表使命）。
- 新战区只是 `ZONES` 表 +2 行 + 初始 state 登记 + 区名 i18n。

## 5. 验收标准（Acceptance / Litmus）

- [ ] **冷场自愈**：飞到远离锚点盘与全部战区的空域悬停，≤1 个刷怪周期内有拦截队从玩家
      前方边缘入场并直奔而来（Tab 图可见"边缘 → 玩家"的移动轨迹）
- [ ] **热闹不加塞**：hunter 满额的激烈交战中，新增援照旧飞中央锚点，无拦截波
- [ ] **不从身后出兵**：连续观察 10 波拦截，入场点全部在玩家 heading ±90° 扇区（无合法候选的
      回退情形除外）
- [ ] 新战区 F/G：出现在再激活候选池、可被开放、任务可触发可完成、奖励照常 roll
- [ ] `tests/test_map_expansion.gd` 全绿（7 区几何 + F 陆地占比 + ingress 段 + 奖励去重）
- [ ] 性能：无新增每帧逻辑；Sentinel + Lv5+ 压测 FPS 掉幅 < 15
- [ ] i18n：F/G 区名三语（zh/en/ja）
- [ ] 已知 seam 未触碰（known-seams.md）

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 拦截波
- [x] 常量 `INTERCEPT_QUOTA_GAP` + hunter 在册计数复用函数（`_count_hunter_pressure`：交战中 + 在途拦截队）
- [x] 旅途 spawn 入口加拦截判定（§3.1），拦截波打 `reinf_intercept` meta
- [x] 边缘候选点算法加"玩家前方扇区"参数化分支（±90°，无候选回退全周长）
- [x] reinforcement 航点 tick 加 intercept 分支（航点=玩家位置、不转 ONSTATION）
- [x] EventLogger 打点 `INGRESS Intercept`（F9 可回放验证）

### 阶段 2 — 新战区
- [x] `ZONES` 追加 F/G 两行 + 初始 state LOCKED
- [x] i18n 区名三语（ZONE_F_NAME / ZONE_G_NAME）
- [x] 跑 `tests/test_map_expansion.gd` —— 全绿（F 陆地占比 1.00、F↔A 缘距 2047、7 区几何全过）

### 阶段 3 — 收尾
- [x] §5 验收无头项 + 同步 reference 索引 + §7 锚点 + _INDEX 总表
- [ ] playtest 项交用户（冷场自愈 / 前方入场观感 / 新区节奏）→ status: done

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 拦截判定 / 扇区选边 / 拦截航点 | `scripts/survivor/survivor_spawner.gd` |
| 常量 | `scripts/survivor/survivor_data.gd` |
| hunter 配额 | `scripts/survivor/roe_director.gd` |
| 新战区表 | `scripts/survivor/zone_data.gd` |
| 回归 | `scripts/tests/test_map_expansion.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-22 | 1 | 初稿并定稿：用户三联反馈（冷场/XP 少/缺进场敌机）→ 拦截波（hunter 缺口驱动、前方扇区边缘入场、航点指向玩家）+ 新战区 F/G；数值细化项见 §9 |
| 2026-07-22 | 2 | **同日代码落地**（阶段 1~3 无头项全勾）：拦截波三件套（判定/扇区选边/磁吸航点）+ F/G 入 ZONES；test_map_expansion 全绿（F 陆地 1.00）；status → in-progress 差 playtest |

## 9. 自拍板项（playtest 重点复核）

用户指示未覆盖、由 Claude 细化的数值，playtest 时优先质询：

1. `INTERCEPT_QUOTA_GAP = 2`（=1 会几乎每波都拦截，=3 冷场自愈变慢）
2. 入场扇区 ±90°（收窄到 ±70° 会更"正面"，但候选点变少）
3. F/G 坐标、半径、类型（F 压 A 区缘距下限 2047，若观感太挤可缩 F 半径至 2000）
4. 本批刻意不动任何热度旋钮（§1.4）——若 playtest 后仍冷，第一杠杆是 density-pass 的
   `TRAVEL_SPAWN_INTERVAL`，不是给拦截波加倍率
