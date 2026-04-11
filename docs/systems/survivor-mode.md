# 生存模式参考

## 概述

生存模式是类吸血鬼幸存者的无尽战斗模式。玩家操控一架 F-16 面对不断增强的敌机波次，击杀获取经验升级，选择升级强化飞机。

---

## 文件结构

| 文件 | 说明 |
|------|------|
| `scripts/survivor/survivor_mode.gd` | 主控制器（操控/波次/刷怪/雷达/地形） |
| `scripts/survivor/survivor_player.gd` | 经验/等级/升级应用 |
| `scripts/survivor/survivor_data.gd` | 静态数据（升级定义/波次参数/经验曲线） |
| `scripts/survivor/survivor_hud.gd` | HUD 界面（HP/经验条/导弹/弹药/计时等） |
| `scripts/survivor/survivor_upgrade_ui.gd` | 升级选择 UI |
| `scripts/survivor/survivor_select.gd` | 模式选择界面 |
| `scripts/survivor/commander_aura.gd` | 指挥 UAV 光环效果 |
| `scripts/survivor/commander_overlay.gd` | 指挥 UAV 覆盖层 |
| `scripts/survivor/survivor_debug_skills.gd` | 调试用技能面板 |
| `scenes/survivor_mode.tscn` | 场景（BulletManager + MissileManager + Camera2D） |
| `scenes/survivor_select.tscn` | 选择界面场景 |

---

## 与沙盒模式的差异

| 方面 | 沙盒模式 (main.gd) | 生存模式 (survivor_mode.gd) |
|------|-------|-------|
| 高度系统 | 连续高度（米） | 扁平三/四档位（flat_altitude） |
| 弹药 | 有限 | 自动装填（gun/missile/flare） |
| 燃油 | 有限 | 无限（infinite_fuel） |
| 敌机 | 固定放置 | 按等级波次自动生成 |
| 升级 | 无 | 经验→等级→选择升级 |
| 机炮 | 标准命中半径 | 扩大命中半径 |
| 目标限制 | 无 | 同时飞向玩家的导弹上限 3 |
| 伤害上限 | 无 | 可设置导弹/机炮伤害上限 |

---

## 经验与等级系统 (SurvivorPlayer)

### 经验曲线

```gdscript
static func xp_for_level(level: int) -> int:
    return int(20.0 * pow(level, 1.15))
```

### 经验来源

| 来源 | 经验值 |
|------|--------|
| 击杀 MiG | 40 |
| 击杀 UAV | 25 |
| 击杀指挥 UAV | 50 |

### 升级流程

```
击杀敌机 → add_xp()
├── xp >= xp_to_next → level up
│   ├── leveled_up 信号
│   ├── 暂停游戏 (is_paused_for_upgrade)
│   ├── 显示 3 个随机升级选项
│   └── 玩家选择 → apply_upgrade() → 恢复游戏
```

---

## 升级系统 (SurvivorData.UPGRADES)

### 生存轴

| ID | 名称 | 效果 | 最大层数 | 进化 |
|----|------|------|----------|------|
| hp_up | 装甲强化 | HP+30, 机炮闪避+8% | 5 | - |
| speed_up | 引擎强化 | 速度/巡航+18% | 4 | - |
| maneuver_up | 飞控升级 | 滚转+25%, G+1 | 3 | - |
| flare_cooldown | 红外对抗优化 | 热诱弹冷却-20% | 3 | → flare_shield |
| flare_shield | ★电子对抗套件 | 释放热诱弹解锁+免疫锁定3s | 1 | (进化技能) |
| pilot_stamina | 体能强化 | 耐力上限×2, 恢复×2 | 3 | - |
| kill_heal | 战场急救 | 击杀回复10HP | 3 | - |

### 战斗轴

| ID | 名称 | 效果 | 最大层数 | 进化 |
|----|------|------|----------|------|
| missile_count | 导弹挂架扩展 | 导弹+1 | 4 | - |
| missile_tracking | 制导升级 | 过载+30%, 导引常数+0.5 | 4 | → missile_bounce |
| missile_bounce | ★连锁弹头 | 导弹命中后弹跳至另一敌机 | 1 | (进化技能) |
| missile_reload | 快速挂载 | 装填时间-15% | 3 | - |
| multi_lock | 多目标追踪 | 同时锁定+1 | 2 | - |
| gun_damage | 穿甲弹药 | 机炮伤害+20% | 5 | → gun_multishot |
| gun_multishot | ★多管齐射 | 同时射出三道机炮 | 1 | (进化技能) |
| gun_ammo | 弹药扩容 | 弹药+100 | 5 | - |
| gun_reload | 快速装弹机 | 机炮装填时间-15% | 3 | - |
| gun_firerate | 射速强化 | 射速+25% | 4 | - |
| radar_range | 雷达升级 | 探测距离+20% | 3 | - |
| lock_time | 火控优化 | 锁定时间-0.5s | 3 | - |
| dogfight | 格斗大师 | 失速-12%, 减速+30% | 3 | - |

### 进化机制

基础技能满级时 `evolves_to` 字段指向进化技能 ID。进化技能标记 `evolved: true`，不出现在随机池中，仅通过基础技能满级自动触发。

---

## 敌机波次系统

### 刷怪参数

| 常量 | 值 | 说明 |
|------|-----|------|
| BASE_SPAWN_INTERVAL | 8.0s | 初始刷怪间隔 |
| MIN_SPAWN_INTERVAL | 3.0s | 最小间隔 |
| ENEMIES_PER_WAVE_BASE | 1 | 每波基础敌人数 |
| ENEMIES_PER_WAVE_GROWTH | 0.3 | 每级增长 |
| SPAWN_DISTANCE | 3000px | 距玩家刷怪距离 |
| MAX_ENEMIES_HARD | 40 | 绝对上限 |
| MAX_ENEMIES_DEFAULT | 30 | 默认上限 |

### 敌机类型解锁

| 类型 | 解锁等级 | 出现概率增长 | 最大概率 |
|------|----------|-------------|----------|
| UAV（基础） | 1 | 始终出现 | - |
| UCAV（导弹无人机） | 3 | +10%/级 | 40% |
| 指挥 UAV（Sentinel） | 4 | +6%/级（基础12%） | 25% |
| J-7 截击机 | 5 | +12%/级 | 35% |
| MiG-29 | 7 | +8%/级 | 50% |

### 敌人属性缩放

随玩家等级提升：

**MiG**: HP ×(1 + (level-1)×0.15), 每4级+1导弹, 机炮伤害 ×(1 + (level-1)×0.08)

**UAV**: HP ×(1 + (level-1)×0.08), 机炮伤害 ×(1 + (level-1)×0.05)

**指挥UAV**: HP ×(1 + (level-1)×0.10), 无武装

### 指挥 UAV 机制

- 自带 2-3 架僚机编队
- 最多可招募 6 架（含自己）
- 击杀给 50 经验
- 无武装但 HP 较高

---

## 动态性能控制

- 每 0.5s 采样 FPS，保留最近 6 次
- 平均 FPS < TARGET_FPS (30) → 降低敌机上限
- FPS 恢复 → 逐渐恢复上限
- 下限 MIN_ENEMIES_CAP = 8

---

## 猎手指派系统

每 5 秒检查一次（HUNTER_INTERVAL），从空闲敌机中指派猎手追踪玩家，确保持续有压力。

每 8 秒更新一次敌机巡逻航点（WAYPOINT_UPDATE_INTERVAL），让巡逻敌机向玩家方向移动。

---

## 导弹限制

`MAX_MISSILES_TARGETING_PLAYER = 3`：同时飞向玩家的导弹不超过 3 枚，防止玩家被瞬间秒杀。
