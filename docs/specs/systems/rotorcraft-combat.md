---
id: rotorcraft-combat
kind: system
status: in-progress
schema_version: 1
spec_version: 5
owner: 用户 + Codex
depends_on: [slow-air-target-pass, surface-attack-pass, global-awareness-roe, battlefield-visual-scale]
reconstruction_complete: true
---

# 旋翼机平移 / 环绕 / 悬停战斗（Rotorcraft Combat）

> AH-64 不再伪装成一架极慢固定翼：机头可以持续朝向地面目标，机体沿目标切向平移、在环绕和悬停之间切换并用机炮压制；CH-47 共享旋翼飞行模型但保持无武装运输身份。

## 1. 设计意图（Why）

- **体验目标**：玩家能直接看见“机头盯住目标、机体侧向绕圈、突然刹停悬停、再横移”的直升机语言，而不是看它用固定翼 bank 做大半径慢转。
- **战术身份**：攻击直升机靠持续视线和位置控制打地面；固定翼靠 pass。两者不共用对面攻击相位机。
- **绝对边界**：普通任务 AH-64 只选 `GroundUnit`；气氛变体还可选择属于地面实体的正式锁定点。机炮和火箭的兜底扫描始终排除 Aircraft；它可以被战斗机攻击，但永远不反打战斗机或玩家。
- **物理抽象**：不是 1:1 旋翼空气动力学；只实现平面速度向量与机头朝向解耦、加减速、偏航、环绕和悬停这五个玩家能感知的事实。
- **Litmus 自检**：行为差异强可见；自动开火；没有瞬移；决策 20Hz 错相、运动 60Hz；不新增每机每帧全场扫描。
- **显式速度例外**：设计哲学的 600–2200 km/h 区间针对固定翼敌机。AH-64/CH-47 保留 279/302 km/h 级真实身份，否则“直升机”会变成喷气机皮肤。

### 1.1 现实参考

| 机型 | 现实尺寸/性能参考 | AGL 取舍 |
|---|---|---|
| AH-64E | 长 14.7m、旋翼直径 14.6m、最大平飞 279+ km/h、M230 600–650 rpm | 最大 290、巡航 230；可平移/悬停；M230 自动对地 |
| CH-47F | 工作旋翼总长 30.1m、单旋翼直径 18.3m、最大 302 km/h、巡航 291 km/h | 最大 310、巡航 250；运输航路可停靠/悬停，无攻击状态 |

参考来源：Boeing AH-64E 与 CH-47F Block II 官方规格页。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 飞行模型字段

| 字段 | AH-64 | CH-47 | 说明 |
|---|---:|---:|---|
| `flight_model` | `ROTORCRAFT` | `ROTORCRAFT` | 普通飞机为 `FIXED_WING` |
| `rotorcraft_role` | `ATTACK` | `TRANSPORT` | 决定是否有战斗状态 |
| 最大平移速度 | 290 km/h | 310 km/h | 任何方向 |
| 巡航平移速度 | 230 km/h | 250 km/h | TRANSIT |
| 环绕速度 | 180 km/h | — | 切向速度 |
| 平移加速度 | 32 m/s² | 20 m/s² | 速度向量趋近 |
| 平移刹车 | 48 m/s² | 30 m/s² | 进入 HOVER 时更快 |
| 最大偏航率 | 75°/s | 45°/s | 机头方向独立于平移方向 |
| 视觉最大 bank | 18° | 12° | 只表达横向加速度，不决定转弯半径 |
| 悬停速度门 | ≤15 km/h | ≤15 km/h | 达到即视为悬停 |
| 作战高度 | 1200m | 1200m | LOW 内部，出生即到位 |

旋翼机不走固定翼失速、角点速度、G 转弯半径、加力和 afterburner；仍走燃油、状态、受伤、坠毁、热诱弹和武器公共逻辑。

### 2.2 AH-64 目标与环绕参数

| 字段 | 值 | 说明 |
|---|---:|---|
| 目标类型 | 敌对 `GroundUnit` | 明确排除 Aircraft/NavalUnit/MountTarget |
| 搜索半径 | 1800 m | 900 px |
| 重选间隔 | 0.5 s | 每机错相，避免同帧峰值 |
| 环绕半径 | 500 m | 250 px |
| 环绕半径迟滞 | ±80 m | 防状态抖动 |
| 重新定位外环 | 850 m | 太远先直线靠近 |
| 环绕方向 | 出生时 ±1 均匀采样 | 持有到目标失效，不每帧翻转 |
| 环绕持续 | 7–11 s | 到时尝试 HOVER |
| 悬停距离带 | 450–850 m | 太近/太远都不悬停 |
| 悬停持续 | 3.5–6.0 s | 随机一次采样 |
| 悬停结束 | 切回同方向 ORBIT | 不原地无限炮台化 |
| 目标失效 | 返回原任务航路 TRANSIT | 不追击空中单位 |

### 2.3 M230 与现有 Hydra

| 字段 | 值 | 说明 |
|---|---:|---|
| M230 射速 | 625 rpm | 保留现实身份 |
| 单发伤害 | 40 | 修正旧 12，进入 30–100 平衡区间 |
| 初速 | 805 m/s | 保留 |
| 最大射程 | 1500 m | 保留 |
| 机头开火半角 | 8° | 旋翼机持续指向目标，仍禁止侧射 |
| 散布 | 1.8° | 保留 |
| 弹药 | 300 | 保留当前事件规模 |
| AI 短点射 | 开 0.45–0.8s / 停 0.8–1.4s | 避免 625rpm 持续 DPS 墙 |
| Hydra | 保留当前 38 枚与现有参数 | 作为次武器；本 spec 验收不依赖它 |

### 2.4 CH-47 行为参数

- `TRANSIT`：按指定航路平飞，机头逐渐对齐速度方向。
- `HOVER`：事件/任务调用方可在航点标记 `hold_seconds`；默认 0，城区逃离事件仍不停留。
- 无 `ORBIT_ATTACK`、无目标搜索、无武器；受击散开改为 2.5s 侧向加速脉冲，不再用固定翼 S 形 waypoint 修正。

### 2.5 地面气氛组武装直升机变体

- [正式战区氛围战斗](zone-atmosphere-combat.md) 可以用同一套 AH-64 参数/运动/武器创建 `ALLY` 或 `HOSTILE` 气氛直升机；任务 Adds 与气氛变体是两种生成身份，不复制资源或物理状态机。
- 气氛变体的目标池是敌对 `GroundUnit`，以及父级属于地面任务实体的可攻击锁定点；因此可以攻击 SPG、普通坦克、沙漠攻城坦克，以及一体化巨炮单体。Aircraft、NavalUnit 与非地面挂点始终非法。
- 友敌气氛直升机可以同时存在，但双方互不攻击；它们只与地面目标交战。地面 AA/SAM/CIWS 可以按既有规则反击直升机，超级巨炮因无防空能力不能反击。
- 气氛变体不是正式 TGT，不占 Token、不阻塞任务，也不加入玩家小队。玩家或正式小队击毁 `HOSTILE` 气氛 AH-64 时沿用当前 `XP_PER_KILL_AH64 = 50`；第三方击毁或 `ALLY` 损失不产生玩家收益。
- 对气氛 GroundUnit 的伤害可正常致死；对正式 TGT/挂点必须走非致死入口、最低保留 1 HP。气氛变体发射的机炮/火箭继续读取 3/3.6km 气氛伤害 LOD。
- 纯地面、只追加友军直升机、只追加敌军直升机、双方直升机同时存在等组合由气氛系统选择；本 spec 只拥有单机飞行/火控与目标边界。

## 3. 行为与公式（How）

### 3.1 AH-64 状态机

| 状态 | 行为 | 转移 |
|---|---|---|
| `TRANSIT` | 沿航路平移，机头跟速度方向 | 搜到 GroundUnit → `REPOSITION` |
| `REPOSITION` | 朝目标环上最近点平移；机头同时朝目标偏航 | 进入 500±80m → `ORBIT` |
| `ORBIT` | 切向速度 + 径向误差修正；机头持续朝目标；自动点射 | 7–11s 且在悬停距离带 → `BRAKE_TO_HOVER` |
| `BRAKE_TO_HOVER` | 以 48m/s² 把平面速度降至 0；机头保持目标 | ≤15km/h → `HOVER`；目标失效 → `TRANSIT` |
| `HOVER` | 位置保持，机头跟随目标，自动点射 | 3.5–6s → `ORBIT` |
| `EGRESS` | 沿任务离场航路，不搜新目标 | 出界回收 |

### 3.2 环绕速度解

```text
r = aircraft_pos - target_pos
radial_dir = normalize(r)
tangent_dir = perpendicular(radial_dir) × orbit_sign
radial_error_m = (|r| / PIXELS_PER_METER) - orbit_radius_m
desired_velocity = tangent_dir × orbit_speed_mps
                 - radial_dir × clamp(radial_error_m × 0.35, -35, 35)
velocity = move_toward(velocity, desired_velocity, translation_accel × dt)
heading = move_toward_angle(heading, bearing_to_target, yaw_rate × dt)
```

这使机头与移动方向解耦：绕圈时机头指向圆心、速度沿切线，玩家能直接看到“平移施火”。

### 3.3 悬停与位置保持

HOVER 不把位置硬钉死。保存进入悬停时的 `hover_anchor`，用比例速度纠偏：

```text
desired_velocity = clamp_length((hover_anchor - pos) × 1.2, 12 m/s)
```

因此受爆炸/状态推动后会缓慢归位，不瞬移。机头仍以最大偏航率朝目标。

### 3.4 武器与空中免疫

必须同时保留三道门：

1. 普通 AH-64 只接受敌对 `GroundUnit`；气氛变体只额外接受属于地面任务实体的锁定点；
2. `attack_air_targets=false`，公共自动机炮扫描不能命中 Aircraft；
3. 发射瞬间再次验证目标仍是合法地面目标且敌对，并按气氛演员/正式 TGT 选择致死或非致死入口。

任一门失效时测试必须报红；不能只信 AI 的 `combat_target`。

## 4. 结构与组成（Structure）

- `AircraftParams.flight_model` 与 `rotorcraft_role`：参数驱动，不写生存/沙盒分支。
- `AircraftPhysics.update_rotorcraft`：只负责平面速度向量、偏航、视觉 bank、位置和高度保持。
- `AIController._process_rotorcraft`：20Hz simple-AI 分频下的状态决策与 GroundUnit 目标选择；60Hz 运动只消费缓存的状态/向量。
- `Aircraft`：按 `flight_model` 分发固定翼或旋翼运动，但共享伤害、状态、武器、绘制和销毁。
- `AircraftRenderer`：旋翼盘按统一视觉尺度绘制；动画只随时间变化，不做场景扫描。
- 现有 `slow-air-target-pass` 保持不变：它描述“固定翼如何攻击直升机”，本 spec 描述“直升机自己如何飞”。

## 5. 验收标准（Acceptance / Litmus）

- [ ] AH-64 从直线航路发现敌方 AA 后进入 500m 环，机头持续朝 AA，速度沿切线，至少完成可见的 90° 圆弧而不做固定翼 bank 大回环。
- [ ] ORBIT 7–11s 后能真实减速到 ≤15km/h，悬停 3.5–6s，随后恢复同方向环绕。
- [ ] ORBIT/HOVER 均能以 M230 自动点射 GroundUnit；无目标时不朝空地乱射。
- [ ] 玩家飞机从 AH-64 机头 100m 内穿过，AH-64 不选中、不瞄准、不伤害它。
- [x] `ALLY/HOSTILE` 气氛 AH-64 可分别攻击敌对 SPG、坦克、攻城坦克和一体化巨炮 GroundUnit；双方同场互不攻击，玩家/飞机不是目标且弹丸拒绝 Aircraft。
- [x] 气氛 AH-64 不是 TGT/Token；敌对实例保留现有 50 XP 玩家归因，友军关闭收益；其火力可击毁气氛地面演员但不能清掉正式 TGT。
- [ ] AH-64 目标被毁后 0.5s 内回到原任务航路，不在尸体旁永远盘旋。
- [ ] CH-47 按航路平移，指定 hold 航点能悬停后继续；城区逃离事件默认不停留。
- [ ] 受击散开对旋翼机表现为侧向平移脉冲，结束后能回到航路；不触发固定翼失速/G 逻辑。
- [ ] 无头闭环测试覆盖速度向量/机头解耦、环半径收敛、悬停、三道对空防火门；加入 `--bench=all`。
- [ ] 性能：目标决策 20Hz 并错相；运动 60Hz O(1)；无每机每帧全场扫描；Sentinel + Lv5+ 不低于 60 FPS。
- [ ] i18n：无新增玩家可见硬编码文本；如加 debug 标签，按既有 debug 例外处理。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 参数与旋翼运动
- [x] AircraftParams 加 flight_model/rotorcraft_role；实现旋翼运动分支。
- [x] AH-64/CH-47 迁移到旋翼模型，固定翼零行为差异。

### 阶段 2 — 战斗状态机
- [x] 实现 AIController 的 TRANSIT/REPOSITION/ORBIT/BRAKE/HOVER/EGRESS 状态集。
- [x] 接入 20Hz 错相 GroundUnit 目标选择和任务航路恢复。

### 阶段 3 — 武器与表现
- [x] M230 修为 40 伤害 + 点射节奏；保持 Hydra 和三道对空防火门。
- [x] 校准旋翼图标、bank 与悬停视觉；CH-47 使用速度向量的平移响应。

### 阶段 4 — 回归与压测
- [x] 新增 rotorcraft 专项 bench；通过速度向量、机头解耦、悬停与尺寸断言。
- [ ] Godot 4.7 生存实机观察环绕、悬停和压力帧率。
- [x] 气氛系统接入双阵营同场、GroundUnit/巨炮锁定点、玩家/飞机负例、非致死 TGT 与 50 XP 身份回归。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 旋翼运动 | `scripts/aircraft/aircraft_physics.gd` |
| 旋翼行为 | `scripts/ai_controller.gd` |
| 分发与公共武器 | `scripts/aircraft.gd` · `scripts/aircraft/aircraft_weapons.gd` |
| 参数 | `scripts/aircraft_params.gd` · `resources/enemy_ah64.tres` · `resources/enemy_ch47.tres` |
| 绘制 | `scripts/aircraft_renderer.gd` |
| 回归 | `scripts/tests/test_bomber_rotor_airburst.gd` |
| 气氛生成与弹丸边界 | `scripts/survivor/zone_atmosphere_combat.gd` · `scripts/survivor/survivor_spawner.gd` · `scripts/bullet_manager.gd` |
| 气氛回归 | `scripts/tests/test_zone_atmosphere_combat.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-22 | 5 | 跟随三级巨炮一体化裁决更新目标池：AH-64 只把整座巨炮视为一个 GroundUnit/TGT，不再看到四底座与炮身五个独立锁定点；正式 TGT 非致死边界不变。 |
| 2026-08-21 | 4 | 地面气氛变体正式接入：ALLY/HOSTILE AH-64 复用现有旋翼状态机，只扫描 GroundUnit；新发机炮/火箭快照地面专用与正式 TGT 非致死标记；四种组合、Aircraft 负例、气氛致死/正式非致死及奖励身份由 zone_atmosphere bench 覆盖。 |
| 2026-08-21 | 3 | 用户批准把 AH-64 作为地面气氛组双阵营演员：可与 SPG、坦克、攻城坦克、超级巨炮地面锁定点组合交战；不是 TGT/Token，绝不攻击玩家或任何 Aircraft；敌对实例由玩家/正式小队击毁时给现有 50 XP。对气氛地面单位可致死，对正式 TGT 始终非致死。当前尚未接入气氛生成。 |
| 2026-08-01 | 2 | 实现速度向量/机头解耦、AH-64 环绕—刹停—悬停循环、对地短点射与三道对空禁火；CH-47 迁移至同一旋翼运动模型；专项 bench 已通过。 |
| 2026-08-01 | 1 | 初稿：参数驱动旋翼飞行模型；AH-64 500m 环绕、7–11s 环绕/3.5–6s 悬停循环、M230 只对地；CH-47 支持平飞与任务悬停。 |
