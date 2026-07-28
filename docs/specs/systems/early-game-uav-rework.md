---
id: early-game-uav-rework
kind: system
status: in-progress   # 代码落地完成；差 playtest（Sentinel 驻守出现率 / F-4E 密度手感）
schema_version: 1
spec_version: 2
owner: user + Claude
depends_on: [f-4e, survivor-loop]
reconstruction_complete: true
---

# 前期敌情与 UAV 更名改造（2026-07-26 批）

> 用户指令四件套：① 普通生存模式的机炮 UAV 更名 **MQ-109**、导弹 UCAV 更名 **MQ-110**
> （同族兄弟机，v2 订正：MQ-110 不退役）；② Sentinel 从战区目标降级——elite 战区任务移除；
> ③ Sentinel + MQ-109 小队改为普通地图刷新敌人，且偶尔作为战区驻守"障碍"出现；
> ④ 新增 F-4E 前期导弹杂鱼（有人机，与无人机不冲突，另见 [f-4e](../enemies/f-4e.md)）。

## 1. 设计意图（Why）

- **命名自然度**："UAV" 是类别词不是型号，出现在 HUD/击杀条里很出戏。改为型号名
  **MQ-109**（约定：用户此后说"机炮 UAV"即指 MQ-109）。
- **Sentinel 作为战区目标太弱**：elite 任务 = 打一只无武装指挥机 + 一群一发死
  无人机，作为"战区攻克目标"的分量不足（对比 squadron 的精英中队 / naval 的舰队）。
  它更适合当**地图上的移动障碍**——玩家路过撞见、可绕可打，而不是任务终点。
- **前期敌情多样性**（v2 订正）：MQ-110（原 UCAV）**保留**——它是 MQ-109 的导弹版
  兄弟机，与 F-4E 不冲突：MQ-110 = 无人机导弹杂鱼、F-4E = **有人机**导弹杂鱼，
  各占一个生态位。F-4E 的作用是让开局不全是无人机——开局画面 =
  MQ-109/MQ-110 无人机群 + F-4E 有人散兵。

## 2. 数据定义（What）

### 2.1 更名（显示层，内部标识不动）

| 位置 | 旧 | 新 |
|---|---|---|
| enemy_uav.tres display_name | `UAV` | `MQ-109` |
| enemy_uav_missile.tres display_name | `UCAV` | `MQ-110` |
| UAV 呼号格式 | `UAV-XX` | `MQ109-XX` |
| UCAV 呼号格式 | `UCAV-XX` | `MQ110-XX` |
| Sentinel 呼号格式 | `UAV_COMMANDER-XX` | `SENTINEL-XX` |
| i18n TACTICAL_TIP_SENTINEL | "…范围内的 UAV…" | "…范围内的 MQ-109…"（三语） |
| debug 面板标签 | `UAV 机炮无人机` / `UCAV 导弹无人机` | `MQ-109 机炮无人机` / `MQ-110 导弹无人机` |

**不改**：EnemyType.UAV/UCAV 枚举名 / type_tag `"uav"`/`"ucav"` / 文件名 enemy_uav*.tres /
uav_gun.tres —— 内部标识改动波及 meta 字符串比对与存档兼容，收益为零。
Aegis UAV / Mother Goose 蜂群 UAV / MQ-X 不在本批范围（各有自己的名字）。

### 2.2 MQ-110（原 UCAV）——保留，仅更名（v2 订正）

v1 曾把 UCAV 退役、由 F-4E 顶替；用户订正：**没必要退役**——它就是导弹版的 MQ-109，
与 F-4E（有人机）不冲突。刷新行为**完全回到改造前**：

| 位置 | 现状 |
|---|---|
| `_pick_enemy_type` 前期兜底层 | MQ-109/MQ-110 等权重 50/50（Lv ≤ UAV_RETIRE_LEVEL=4） |
| ZONE_ENEMY_TABLE | MQ-110 行保留（unlock 1 / peak 2 / retire 6 / weight 1.4），F-4E 行**另加**并存 |
| bench/debug 测试编组 | MQ-110 与 F-4E 条目并存 |

### 2.3 elite 战区任务移除

| 位置 | 处理 |
|---|---|
| zone_data MISSION_TYPE_BASE_WEIGHTS | ★ {ground 45, squadron 30}；★★ {ground 35, squadron 35}（elite 项删除；★★★ 本就无） |
| E 战区 restricted_mission_types | `["naval", "elite"]` → `["naval", "squadron"]`（维持两选一的多样性；squadron 可在水上刷） |
| zone_mission | `_spawn_elite_target` 删除；elite 驻守预算减半分支删除（语义移入 §2.4） |
| survivor_mode / tactical_map / debug 面板 | elite 文案分支与选项删除 |
| i18n | `ZONE_MISSION_ELITE` / `ZONE_MISSION_STARTED_ELITE_FMT` 两键删除 |

### 2.4 Sentinel 新出场方式

**A. 普通地图刷新（既有路径，提高频率）**：`_pick_enemy_type` 的 Sentinel 判定保留
（必带 5 架 MQ-109 + 1 架 Aegis UAV，绝不单飞）。elite 移除后它是 Sentinel 的主要
出场通道，出现概率补偿上调：

| 常量 | 旧 | 新 |
|---|---|---|
| COMMANDER_CHANCE_BASE | 0.04 | **0.06** |
| COMMANDER_CHANCE_MAX | 0.08 | **0.12** |

（COMMANDER_UNLOCK_LEVEL=4 / TOKEN_COST=6 / INSTANCE_CAP=1 不变。）

**B. 战区驻守障碍（新）**：非 naval / 非 airfield 战区刷驻守时 roll：

| 常量 | 值 | 说明 |
|---|---|---|
| SENTINEL_GARRISON_CHANCE | 0.25 | 每个战区首刷时 roll 一次 |
| 护卫数 | randi(6, 10) 架 MQ-109 | 沿用旧 elite 护卫密度（06-07-06 调优值） |
| 唯一性 | 场上已有 Sentinel（含随机刷的）→ 不出 | INSTANCE_CAP=1 同语义 |
| 预算联动 | 出现时该战区驻守 Token 预算 × 0.5 | 沿用旧 elite 减半规则，防双倍叠加 |
| 身份 | **驻守（garrison），非 TGT** | 不挂 is_mission_target；攻克战区后随驻守撤离；绕区盘旋 |

## 3. 行为与公式（How）

### 3.1 Sentinel 战区驻守小队

- 位置：战区中心；长机绕驻守环盘旋（半径 = max(1800, zone.radius × 0.72)，与普通驻守同）。
- 编成：Sentinel（CommanderAura + CommanderOverlay 照挂，光环照常招募/增幅）
  + 6-10 架 MQ-109 僚机（orbit_squad_leader + shield_leader，evade_missiles=false，
  aggression randf(0.7, 0.95)——与随机刷新路径 `_spawn_commander_squad` 完全一致）。
- meta：`zone_garrison` + `category="zone_air"` + `skip_far_cleanup`。
- 完成判定不看它（驻守非 TGT）；玩家可以全程无视绕开——这就是"障碍"的含义。

### 3.2 移除 elite 后的任务类型分布

★/★★ 战区在 {ground, squadron} 二选一（历史滑窗反重复照旧）；水域战区仍强制 air；
E 战区 {naval, squadron} 二选一；airfield 三座不 roll（不变）。

## 4. 结构与组成（Structure）

无新节点类型。Sentinel 驻守小队复用：CommanderAura / CommanderOverlay /
SquadFactory / zone_mission 驻守撤离队列。

## 5. 验收标准（Acceptance / Litmus）

- [ ] HUD/击杀条/日志内不再出现裸 "UAV"/"UCAV" 显示名；呼号为 `MQ109-XX` / `MQ110-XX`
- [ ] Lv1~4 随机刷新能同时观察到 MQ-109 与 MQ-110（50/50 兜底层）与 F-4E
- [ ] 战术地图任何战区不再出现"精英（Sentinel）"任务；E 战区在 naval/squadron 间轮换
- [ ] 多局观察：约 1/4 的陆基/中队战区带 Sentinel + MQ-109 驻守小队；打掉 TGT 后
      即使 Sentinel 小队仍在也判攻克，小队随驻守撤离
- [ ] 场上任意时刻 Sentinel ≤ 1（随机刷新与战区驻守互斥）
- [ ] 性能：Sentinel + Lv5+ 压测 FPS 掉幅 < 15（全部复用既有路径，无新每帧逻辑）
- [ ] i18n：TACTICAL_TIP_SENTINEL 三语已改；elite 两键已删
- [ ] playtest：SENTINEL_GARRISON_CHANCE=0.25 与 COMMANDER 概率上调的手感校准

## 6. 实现计划（Task Pipeline）

- [x] 更名批：tres display_name（MQ-109/MQ-110）/ 呼号 / i18n tip / debug 标签
- [x] ~~UCAV 退役批~~ v2 回滚：MQ-110 恢复随机/战区刷新，与 F-4E 并存
- [x] elite 移除批：zone_data 权重表 + E 限制 / zone_mission 分支 / UI 文案 / i18n 键
- [x] Sentinel 驻守批：_spawn_sentinel_garrison + 概率常量 + 预算减半
- [x] 索引同步：enemy-index / survivor-loop / event-system / radio-chatter 受影响段落
- [ ] playtest 校准（§5 最后两项）

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 任务类型权重/E 限制 | `scripts/survivor/zone_data.gd` |
| 驻守 Sentinel | `scripts/survivor/zone_mission.gd`（_spawn_sentinel_garrison） |
| 刷怪选型/呼号 | `scripts/survivor/survivor_spawner.gd` |
| 概率常量 | `scripts/survivor/survivor_data.gd`（COMMANDER_* / UAV_RETIRE_LEVEL） |
| 更名资源 | `resources/enemy_uav.tres` / `resources/enemy_uav_missile.tres` |
| i18n | `i18n/translations.csv`（TACTICAL_TIP_SENTINEL；elite 两键已删） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-26 | 1 | 初稿 + 落地（用户四件套指令；出现率数值待 playtest） |
| 2026-07-26 | 2 | 用户订正：UCAV **不退役**，更名 **MQ-110**（导弹版 MQ-109）恢复全部刷新，与 F-4E（有人机）并存 |
