# 2026-05-12 · MQ-X 精英无人机（Mother Goose 半血触发）

## 设计

Mother Goose 血量降到总 HP 50% 以下时，**一次性** spawn 两架精英 UAV `MQ-X`，左右翼编队站在 boss 两侧 350px 外。这是无人机系列里数值最强的型号 —— HP 是普通 MQ 的 6~9 倍、双武器（导弹 + 点射攻击激光）、首次给敌方 UAV 装 flare。两架 HP 独立显示在 HUD boss 面板顶部。

## 数值（最强 UAV 档）

| 字段 | MQ-X | MQ-112 (railgun) | MQ-110 (missile) |
|---|---|---|---|
| max_hp | **300** | 50 | 35 |
| max_speed | 1500 | 1400 | 1100 |
| max_g | 8.5 | 6.0 | 5.5 |
| radar_range | 5500m | 5000m | 4000m |
| 武器 | 导弹 ×4 + 点射机炮 | 电磁炮 | 导弹 ×3 |
| flare | 1 charge | 0 | 0 |
| AI 标签 | hunter standoff 1700px | hunter standoff 2000px | hunter standoff 1500px |

### 点射激光机炮（loyal_wingman 系，加强版）

[resources/mqx_pulse_cannon.tres](resources/mqx_pulse_cannon.tres) —
**这是 GunParams（点射机炮），不是 LaserEquipment**。视觉上靠高初速 + 低射速 + 紧散布
看起来像激光弹。参数比 loyal_wingman_laser 全面强化：

| 字段 | loyal_wingman_laser | MQ-X | 含义 |
|---|---|---|---|
| max_range | 1400m | **1800m** | 射程更远 |
| spread_angle | 0.3° | **0.15°** | 散布减半 = 更精准 |
| bullet_damage | 20 | **25** | 单发更狠 |
| muzzle_velocity | 1800 m/s | **2200 m/s** | 弹更快，提前量小 |
| fire_rate | 60 rpm | 50 rpm | 节奏 1.2s 一发，点射感 |
| fire_cone_half_angle | 6° | 5° | 开火角度收紧

### 导弹（强化版 UAV-SAM）

[resources/uav_mqx_missile.tres](resources/uav_mqx_missile.tres) —
damage=45 / max_speed=1000 / nav_constant=3.5 / cooldown=4.0s / max_count=4。
单发杀伤比 UAV-SAM(30) 高 50%，并发火力两架并发约 30 dmg/s 持续输出。

### Flare

[resources/uav_mqx_flare.tres](resources/uav_mqx_flare.tres) —
`max_flares=1` + `reload_time=999`（精英只有"救命一发"）+ `fail_chance=0.10` +
`nervousness=0.3`（冷静老练，关键时刻才放）。

## 实现

- [scripts/survivor/mother_goose_boss.gd](scripts/survivor/mother_goose_boss.gd):
  - 新常量 `MQX_*`（路径 / HP 比例 / 偏移 / 牵引半径 / 站位距离）
  - 新字段 `_mqx_units` / `_mqx_spawned` / `_initial_total_hp`（spawn 时记录 hp_sum 分母）
  - `update()` 半血触发 `_spawn_mqx_pair()`（一次性，记 `_mqx_spawned=true`）
  - 每帧清理 `_mqx_units` 中 freed/destroyed 引用
  - `_make_mqx()` 内联 spawn 单架：duplicate params → 加 meta（fear_immune/saturation_attacker/skip_far_cleanup）→ 接 bullet/missile_manager → 入 boss_squad（吃 CommanderAura buff）→ 配 AIController（simple_ai hunter + leash + standoff + 精英 self_preservation=0.35）
  - `get_display_members()` 扩展为返回 `[boss_unit] + 存活 MQ-X`，触发 HUD 顶部 3 张卡片

- 新 .tres 4 个：`enemy_uav_mqx.tres` / `mqx_pulse_cannon.tres` / `uav_mqx_missile.tres` / `uav_mqx_flare.tres`

## HUD 显示

[scripts/survivor/survivor_hud.gd:_update_boss_panel](scripts/survivor/survivor_hud.gd:942)
已支持遍历 `get_display_members()` → 写到 5 个卡片槽位。MQ-X spawn 后顶部 boss 面板自动从 1 张
（MOTHER GOOSE）变为 3 张（MOTHER GOOSE + MQ-X-01 + MQ-X-02），各自独立 HP 条。
MQ-X 死亡后 `_mqx_units` 清出，HUD 卡片自动消失（不会留 DOWN 状态）。

## 验证

1. 生存模式打 Mother Goose，把 boss 打到 50% HP。
2. 观察 EventLogger 出现 `MQ-X elite pair deployed at 50% HP (hp/each=300)`。
3. 顶部 boss 面板从 1 张卡片变 3 张，能看到两架 MQ-X 各自 300 HP 在掉。
4. 玩家被点射机炮（高速弹丸 + 1.2s 一发）打中应明显掉血（单发 25dmg）。
5. 被 MQ-X 导弹锁定时（lock_time=1.0s），4 秒一发 AAM 飞过来。
6. 给 MQ-X 发导弹时它会 flare（1 发）—— 后续就不再有 flare 防御。
7. 杀死两架 MQ-X 后 HUD 卡片消失，boss 战回归常态。
