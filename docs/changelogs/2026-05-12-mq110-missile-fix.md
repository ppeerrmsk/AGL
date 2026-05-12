# 2026-05-12 · MQ-110 永不发射导弹修复

## 症状

Mother Goose 蜂群中的 MQ-110（导弹 UAV）锁定玩家后从不发射导弹。多局观察都没见过它打出过任何导弹。

## 根因

MQ-110 是"近视眼带 BVR 导弹"的设计错配：

| 参数 | MQ-110 改前 | 武器 (UAV-SAM) | 失配 |
|---|---|---|---|
| `radar_range` | 1500m (750px) | `max_range_rear` 5000m + `front_rear_ratio` 2.0 | 雷达只能看到导弹射程 1/3 |
| `max_speed` | 1100 km/h (305 m/s) | — | 玩家 2000+km/h 时 MQ-110 永远 tail chase 拿不到 |
| `preferred_standoff_range_px` | 无 | — | hunter LEAD chase 一路冲到玩家面前 |
| `lock_time` | 1.0s | `radar_half_angle` 35° | 高速擦肩根本攒不齐 1.0s 锁定窗口 |

[scripts/aircraft/aircraft_weapons.gd:707 update_missile](../../scripts/aircraft/aircraft_weapons.gd:707) 要求 `is_in_radar_cone` + `lock_progress >= lock_time` —— 上述四点联手让 MQ-110 永远卡在 LOCK / OFF_CONE / ENVELOPE 阻塞，从未发出过一发。

对比 MQ-112（电磁炮）：radar 5000m + standoff 2000px + speed 1400，工程参数自洽。

## 改动

1. [resources/enemy_uav_missile.tres](../../resources/enemy_uav_missile.tres) — `radar_range: 1500 → 4000`（与 UAV-SAM 后半球射程 5000m 大致匹配，留 20% 余量避免边缘抖动）。
2. [scripts/survivor/mother_goose_uav_swarm.gd:308-314](../../scripts/survivor/mother_goose_uav_swarm.gd:308) — `match variant` 增加 `MQ_110_MISSILE: standoff = 1500px` 分支。1500px = 3000m，落在新雷达(4000m=2000px)内 + 远离 missile min_range (300m=150px) 死区 + 留余量给玩家机动。

`lock_time` / `radar_half_angle` / `max_speed` 不动 —— 35° 锥与 1.0s 锁定时间在 standoff 模式下完全够用，速度差通过 standoff 不打狗斗规避。

## 行为差异

| 场景 | 改前 | 改后 |
|---|---|---|
| MQ-110 接近玩家 | 一路冲到 < 750px，甩出锥死循环 | 1500px 处掉头维持站位，机头稳定指向玩家 |
| 雷达锁定累积 | < 750px 才开始，常被甩 | 在 2000px (4000m radar) 即开始，标称 1.0s 内可锁定 |
| 导弹发射频率 | 0 | 每 5s 冷却 + infinite_ammo → 持续输出 |
| 伤害模型 | 设计上 6 架 ×30dmg = 180 inbound，实际为 0 | 设计值终于能实现 |

## 验证

1. 生存模式打 Mother Goose（boss=MOTHER_GOOSE），F9 抓 log。
2. 搜 `_log_msl_block` 阻塞原因：应能看到 `LOCK` / `COOLDOWN` 等正常状态，**不再**长期卡在 `OFF_CONE` 或 `ENVELOPE too_close`。
3. 搜 `[MISSILE FIRE]` 或观察 missile_manager 应有 UAV-SAM 出现。
4. 玩家 inbound damage / flare 触发频率应明显上升。
