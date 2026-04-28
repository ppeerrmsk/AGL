# 更新日志 — 2026-04-28（commit 10）

## 装备模块化 commit 10/13 — X-02 Wraith 主角飞机首次落地

第一架使用新装备系统的可玩飞机。**无传统机炮 / 导弹 / 热诱弹**——纯电磁炮 + 激光双武器配置。

## 资源

| 文件 | 说明 |
|---|---|
| `resources/x02_railgun.tres` | RailgunEquipment 玩家版（charge_duration=1.2s, lock_trajectory_at=AT_FIRE_TIME=1, damage=150, range=5000m, cooldown=6s）|
| `resources/x02_laser.tres` | LaserEquipment 全开版（target_filter 三档全 true, dps_max=150, range=1500m, heat_max=100）|
| `resources/playable_x02_base.tres` | AircraftParams（acceleration 65 = +30%, cruise 1000, radar_range 420 加大, lock_time 2.5 加快, equipment 数组装两件武器）|
| `resources/playable_x02.tres` | PlayableAircraft 档案（id=x02, codename=Wraith, 三标签 RAILGUN/LASER_360/NO_FLARE）|

## 飞机定位

- **站桩狙击型**：高加速（+30%）+ 长雷达 + 短锁定 → 适合远距 keep distance + 拖锁开火
- **近战兜底**：360° 激光 1500m 范围，DPS_max=150 贴脸最强 → 被冲到面前也不慌
- **特殊机制**：
  - 电磁炮充能 1.2s + AT_FIRE_TIME 锁定 → 玩家几乎不会射失
  - 激光 360° 全向 → 不需要瞄准，但有过热（约 2.85s 满热 → 强制冷却到 30%）
  - **没有热诱弹** → 玩家被锁定时只能靠机动 + 拦截（用激光打导弹）
  - **云中激光大幅衰减**，电磁炮不受影响 → 战略选择

## 集成改动

### `scripts/survivor/survivor_select.gd`

PLAYABLE_LIST 第 3 槽（原 SLOT_TBA）改为 `playable_x02.tres`，从锁定改为可选。
现在选择菜单：F-16 / F-14 / **X-02** / TBA。

### `scripts/survivor/survivor_playable_setup.gd`

`deep_dup_weapons` 追加 equipment 数组深拷贝逻辑：

```gdscript
var dup_arr: Array[EquipmentParams] = []
for eq in p.equipment:
    if eq != null:
        dup_arr.append(eq.duplicate())
    else:
        dup_arr.append(null)
p.equipment = dup_arr
```

防止生存模式运行时（升级修改 equipment 字段）污染共享 .tres。

### `scripts/survivor/survivor_data.gd` UPGRADES 表追加 6 条 X-02 专属升级

| ID | 效果 | requires |
|---|---|---|
| railgun_charge | 充能时间 -20%（每层）| railgun |
| railgun_range | 最大射程 +500m | railgun |
| railgun_damage | 伤害 +25% | railgun |
| laser_cooldown | 散热效率 +25% | laser |
| laser_range | 最大射程 +20% | laser |
| laser_heat | 过热阈值 +30% | laser |

每条都标了 `requires`，**只在装了对应装备时出现**。F-16 / F-14 选择时升级池不会出现这 6 条。
反之 X-02 选择时**不会出现** missile/gun/flare 升级（因为它没装这些）—— commit 7 升级过滤已实装。

### `scripts/survivor/survivor_player.gd`

apply_upgrade 加 6 个 stat 分支，调用 `params.get_equipment_of_kind("railgun")` /
`get_equipment_of_kind("laser")` 拿到装备实例后修改字段。

### `i18n/translations.csv`

追加 18 行三语翻译（display name / card desc / 3 tags / 6 升级 × 2 keys）。

## 验证

跑生存模式：
1. **地图选择 → 机型选择**：第 3 卡显示 X-02 Wraith
2. **进入战斗**：玩家飞机有蓝灰色机身（icon_color=Color(0.85,0.9,1.0)）+ 深色机翼
3. **升级抽取**：抽到的不应有 missile/gun/flare/rocket 升级；可能抽到 6 条 X-02 专属升级 + 通用 HP/速度/机动等
4. **战斗机制**：
   - 右键敌机 → 看到电磁炮扇形从 30° 收缩到 0°（1.2s）→ 闪电光束 + 命中
   - 敌机靠近 1500m 内 → 激光黄绿线条自动照射（360° 多目标）
   - 持续激光 → 激光线条逐渐变红 → 周围红色光环（过热）→ 几秒不能再开
5. **云交互**：钻进云团时观察激光线条是否变细变淡

## 累计进度

```
[完成] commit 1-9  装备类 + 升级过滤 + 电磁炮 + 激光
[完成] commit 10   X-02 主角飞机
        commit 11  AF-03 + 激光 UAV
        commit 12  TacticalPlanner 投票（视精力）
```

## 已知缺口

- **AI 未优化**：X-02 有 AI 模板 sense（ai_controller 跑老路径），但还没有"电磁炮射手"
  专属战术。AI 玩家僚机用 X-02 时不会主动 keep distance。这等 commit 12 投票模型上线后才会
  自动行为正确。当前玩家手动操控不受影响
- **AGM/secondary_missile 处理**：X-02 没有副导弹，`survivor_playable_setup.gd:58-61`
  的 "AGM 继承 AAM 属性" 路径不触发（因为 p.missile = null），无需修改
- **僚机配置**：X-02 默认 wingman_count=0（单机）。未来可加 X-02 编队，但需要 AI
  专门为新装备做决策才好玩
