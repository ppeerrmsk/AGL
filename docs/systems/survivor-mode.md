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

## 阶段制（2026-05-09 起）

| 阶段 | 时长 | 行为 |
|------|------|------|
| 战区阶段 | 0–8 分钟（`WARZONE_PHASE_DURATION = 480.0`） | 战区可循环刷新；攻克 1 个 → 立即开 2 个新战区 |
| BOSS 阶段 | 8 分钟到点之后 | `game_time` 冻结；其他战区关闭，BOSS 可用 |

**触发流程（即时切换）**：
1. 8 分钟到点（`survivor_mode._check_warzone_phase_timeout`）：
   - `zone_mission.cancel_all_zone_missions()` → 清所有 TGT 标记 / `_spawned_zones` / `_triggered_zones` / `_completed_zones`，敌人留场（继续给经验，但不再给奖励）
   - 关所有 AVAILABLE/SELECTED 战区为 LOCKED
   - `boss_unlocked = true`
2. 下一帧 `_update_boss_phase` 启动 `BossEncounterEvent`

**已攻克战区再激活**：`_refresh_availability_after_clear` 用加权抽取（CLEARED 1.5×，LOCKED 1.0×）从候选池开 2 个新战区 → 已攻克战区有显著概率被重新激活并刷新敌人。

**出界回血时间税**：玩家点 SUPPLY 满血但 `game_time += 15.0`（`SUPPLY_TIME_COST`），把 BOSS 拉近。BOSS 阶段 SUPPLY 已被 `_on_supply_confirmed` L1978 早 return 屏蔽。

**HUD 显示**：[survivor_hud.gd](../../scripts/survivor/survivor_hud.gd) `set_warzone_remaining(seconds, in_boss_phase)`：顶部最上方常驻 Label，PROCESS_MODE_ALWAYS 保证升级面板暂停时也显示；升级面板打开前 survivor_mode 同步刷新一次。

**已废弃**：旧的 `cleared_count >= 3` 触发 BOSS 路径已删除（`zone_data.gd:_refresh_availability_after_clear`），改由 `survivor_mode._check_warzone_phase_timeout` 时间驱动。

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

## 升级系统

完整技能图鉴 / 设计哲学 / 战区奖励池 / 骑士精神系列规划见 **[survivor-skills.md](survivor-skills.md)**。
本文档只描述升级**机制**：
- 升级池由 `SurvivorData.UPGRADES` 定义；筛选走 `is_upgrade_available_for(upgrade, aircraft_id, params)`（处理 `requires` 硬件依赖、`exclusive_to` 主角专属、`max_stacks` 上限）
- 进化机制：基础技能满级时 `evolves_to` 字段触发自动进化为指定技能；进化技能 `evolved: true` 不出现在常规随机池，仅通过进化或战区奖励发放
- 应用入口：[survivor_player.gd](../../scripts/survivor/survivor_player.gd) `apply_upgrade()` 把 stat 写到 Aircraft / AircraftParams（已 `duplicate(true)`）

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
