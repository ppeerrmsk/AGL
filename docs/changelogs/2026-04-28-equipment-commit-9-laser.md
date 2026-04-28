# 更新日志 — 2026-04-28（commit 9）

## 装备模块化 commit 9/13 — LaserEquipment（360° 激光，第二个全新机制）

第二种全新武器：360° DoT 激光。与电磁炮（hitscan 单发高伤）形成对比——
**贴脸最强 + 全向覆盖 + 持续输出**。装在 X-02 + 激光 UAV 上。

## 核心机制

### 全向 DoT（区别于机炮的前向锥）

每帧扫描射程内所有目标（按 target_filter 过滤），按距离取最近 N 个，每个施加
`dps × delta` 伤害。**无机头朝向限制**——飞机绕飞或盘旋时也能持续照射。

### 距离衰减

```
t = 1 - dist / max_range  ∈ [0, 1]
falloff = t ^ falloff_exp
dps = dps_min + (dps_max - dps_min) × falloff
```

`falloff_exp = 1.5`：贴脸 dps_max=150，半射程 dps≈70，满射程 dps_min=20。

### 多目标限制（性能 + 平衡）

`max_simultaneous_targets = 8`。防 N² 爆炸（22 单位 × 360° 扫描），同时让玩家
"激光人海打 boss" 不至于过强。

### Target filter（解锁 X-02 vs 激光 UAV 差异）

```
@export var can_target_aircraft: bool = true
@export var can_target_missiles: bool = true
@export var can_target_ground: bool = true
```

- **X-02 玩家版**：全 true，全能武器
- **激光 UAV（拦截特化）**：`can_target_aircraft=false, can_target_ground=false,
  can_target_missiles=true`。Sentinel 带的 2 架激光 UAV 只拦导弹，不打玩家本身

### 过热（防躺赢）

- `heat += heat_per_second × delta` 输出时（默认 35/s → 满 2.85s）
- `heat -= heat_cooldown_per_second × delta` 静止时（默认 25/s → 满冷却 4.0s）
- 不开火时按 50% 速率散热（鼓励玩家适时停火，但完全停火更快冷却）
- 满 → `overheating=true` → 强制冷却到 `heat_max × 0.3` 才能再开

### 云层削弱（核心机制）

调 `WeatherSystem.sample_density(target.global_position)` 拿目标处云密度（0-1）：

```
damage_multiplier = lerp(1.0, cloud_damage_factor_min[0.30], cloud_density)
beam_thickness = base × lerp(1.0, cloud_beam_thickness_factor_min[0.40], cloud_density)
```

满云 → 30% 伤害 + 40% 厚度。视觉立刻可读（光束变细变淡），战略后果：玩家被迫等敌
飞出云、或改用电磁炮（动能弹不受云影响 → 克制关系）。

### 导弹拦截

走 `Missile.intercept_hp` 路径，与现有 BulletManager CIWS 一致。激光照射 → 累计扣
intercept_hp → 归零时 queue_free。激光 UAV 群（每个 dps_max=80）配合可形成"导弹屏障"。

## 视觉

`AircraftRenderer.draw_laser_beams(ac)`：
- 每个被照射目标画一条 ac → unit 的细线
- 主光束（黄绿）+ 高亮中心（白）双层
- alpha 随距离衰减
- heat > 70% → 染红警告
- overheating → 周围画红色光环（仅玩家）

## 颜色编码

- 电磁炮（commit 8）：蓝白 `(0.7, 0.95, 1.0)`，敌方红 `(1.0, 0.5, 0.4)`
- 激光（本 commit）：黄绿 `(0.9, 1.0, 0.7)`
- 双装备 X-02 时玩家立刻能区分两种武器在屏幕上的视觉

## 没有 .tres / 没有飞机使用

同 commit 8，本 commit 只提供机制。X-02（commit 10）和激光 UAV（commit 11）才创建
对应 .tres 并装上。

## 累计进度

```
[完成] commit 1-7  装备包装 + 升级过滤
[完成] commit 8    RailgunEquipment（电磁炮）
[完成] commit 9    LaserEquipment（360° 激光）
        commit 10  X-02 主角
        commit 11  AF-03 + 激光 UAV
        commit 12  TacticalPlanner 投票（视精力）
```
