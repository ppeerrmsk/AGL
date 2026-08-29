---
id: radar-range-normalization
kind: system
status: approved
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [player-aircraft-power-curve, t0-low-t1-aircraft-expansion]
reconstruction_complete: true
---

# 雷达距离规范化——代际走廊、局部平滑与最终硬上限

## 1. 设计意图

- 雷达首先服从科技树位置，其次才表达电战、远程或制空身份；现实航电只提供性格参考。
- 高阶机应看得更远，但不能用一次进化翻倍、技能连乘或高空倍率覆盖整张战区。
- 雷达特色同时由距离、锥宽、锁定时间和共享感知组成，不把全部预算塞进距离。
- `radar_range` 的单位是像素；不要把字段误写成现实米数。

## 2. 玩家基础雷达曲线

| Tier | 基础走廊（px） | 设计语义 |
|---:|---:|---|
| T0 | 1900~2400 | 完整但低预算的起手感知 |
| T1 | 2200~2800 | 低位 T1 与标准 T1 共带，身份开始分化 |
| T2 | 2550~3200 | 第一段稳定航电成长 |
| T3 | 2850~3400 | 隐身 / 传感融合阶段 |
| T4 | 3200~3900 | 六代 / 试验机，但仍不进入地图级感知 |
| T5 | 3450~4400 | 原创超凡档；X-13 保留全谱航电王冠 |

### 2.1 当前 50 机基础值

| Tier | 机体与 `radar_range` |
|---:|---|
| T0 | MiG-21F-13 1900；F-104C 1950；J 35F 2200；EA-6B 2400 |
| T1 | A-6E 2200；Jaguar 2250；F-15 2300；MiG-23 2350；F-4E 2500；F-14 2500；Mirage III 2800 |
| T2 | Mirage 2000 2550；Harrier 2550；F-15C 2600；F-15E 2600；Su-27 2600；A-10 2600；Tornado 2600；Viggen 2600；Su-34 2650；Typhoon 2700；F/A-18E 2850；MiG-31 2950；F-16 3100；Gripen C 3100；EA-18G 3150；Rafale 3200 |
| T3 | F-15 S/MTD 2900；Su-35 2950；F-22 3000；Su-57 3000；A-12 3000；J-20 3300；F-35 3400；Gripen E 3400 |
| T4 | YF-23 3200；F-47 3250；F/A-XX 3300；GCAP 3600；MiG-41 3600；J-36 3650；FCAS 3900 |
| T5 | X-09 3450；X-77 3550；X-44 3600；X-02 4000；X-21 4000；X-90 4100；AX-00 4200；X-13 4400 |

注：表中 F-4E 2500 指玩家低位 T1；敌方 F-4E 使用独立档案 2600。

### 2.2 进化边约束

对 `evolution_tree.json` 中每条 `parent → child`：

```text
0.90 <= child.base_radar / parent.base_radar <= 1.35
```

35% 是跨身份进化的最大单步；同身份链应更收敛。换定位允许最多 10% 回撤，必须同时在锥宽、锁定或其他角色轴上得到回报。

## 3. 有效雷达公式

```text
category_mult = min(1 + 0.03 × 不同电子战类技能数, 1.30)
pre_altitude = base_radar × category_mult + ew_expert_flat_bonus
effective_radar = min(pre_altitude × altitude_mult, 9000 px)
```

高度连续锚点保持：

| 高度 | 倍率 |
|---:|---:|
| 0m | ×0.50 |
| 2000m | ×0.60 |
| 5500m | ×1.00 |
| 10000m | ×1.40 |
| 15000m 及以上 | ×1.50 |

- `9000 px` 是所有机体、类别联动、平加与高度叠加后的最终上限。
- 导弹有效交战距离继续取 `min(导弹物理射程, effective_radar)`。
- 锥宽、锁定时间、数据链和预警支援不绕过距离硬上限。

## 4. 敌机校准

| 对象 | 基础雷达 | 锁定 | 说明 |
|---|---:|---:|---|
| 敌 F-4E | 2600 | 3.4s | 前期有人机，不再以 4200 / 2.6s 抢高阶航电身份 |
| AF-03 | 4800 | 2.0s | 保留电磁炮狙击平台特色，但从 7000 收回 |

所有敌机同样经过 `effective_radar <= 9000 px`。敌人等级缩放只增加 HP；`missile_add = 0`、`gun_damage_mult = 1.0`，武器强度由机型档案与战区编成单一负责，避免双重成长。

## 5. 验收

- [x] 50 架玩家机全部落在对应 Tier 走廊。
- [x] 155 条真实进化边全部满足雷达单步 `0.90~1.35`。
- [x] 极端基础值、技能倍率、平加和 15000m 高度叠加后仍返回 9000 px。
- [x] 电子战类别联动为每技能 +3%，封顶 ×1.30。
- [x] 敌 F-4E / AF-03 使用 2600 / 4800；等级缩放不再加弹或增伤。
- [ ] 代表性完整局确认 T0 仍能及时发现接战目标，T5 航电机仍有清晰优势。

## 6. 实现计划

- [x] 重排 50 机 `.tres` 基础雷达。
- [x] 在 `Aircraft.effective_radar_range_px()` 加最终硬上限。
- [x] 收紧 `CATEGORY_BONUSES` 并取消敌武器双重成长。
- [x] `player_params` 增加全树边与极端叠加验收。

## 7. 索引锚点

| 关注点 | 文件 |
|---|---|
| 有效公式 / 高度表 / 最终上限 | `scripts/aircraft.gd` |
| 类别联动 / 敌等级缩放 | `scripts/survivor/survivor_data.gd` |
| 玩家基础值 | `resources/player/player_*.tres` |
| 敌方特例 | `resources/enemy_f4e.tres` / `resources/enemy_af03.tres` |
| 回归 | `scripts/tests/test_player_params.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-07-26 | 2 | 旧 43 机三带规范化。 |
| 2026-08-26 | 3 | 改为 T0~T5 代际走廊；50 机重排；加 9000 px 最终上限、类别倍率封顶与敌机双重成长修正。 |
