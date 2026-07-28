# 飞机参数说明（AircraftParams）

> 最后校订：2026-07-26（对照 `scripts/aircraft_params.gd`）。
>
> 本文只解释**字段是什么、怎么影响行为**。各机型的**具体数值**不在这里
> —— 看 `resources/` 下的 `.tres`、[reference/resources-catalog.md](../reference/resources-catalog.md)，
> 玩家机的战斗力配平规范看
> [specs/systems/player-aircraft-power-curve](../specs/systems/player-aircraft-power-curve.md)。

`AircraftParams` 继承 `Resource`，通过 `.tres` 定义机型。全部字段是 `@export`，可在 Godot 编辑器里改。

⚠ 生成飞机时必须 `duplicate(true)`，否则升级/缩放会污染共享的 `.tres`。

---

## 字段一览（按 `@export_group` 分组）

### 基本信息
| 字段 | 类型 | 说明 |
|---|---|---|
| `display_name` | String | 显示名。**例外**：不走 `tr()`，HUD / 日志直接拼接 |
| `is_unmanned` | bool | 无人驾驶标识（可被 Sentinel 招募；无人机在无线电系统里一律沉默）|

### 生存性
| 字段 | 类型 | 说明 |
|---|---|---|
| `max_hp` | float | 血量。⚠ 敌机会被 `ENEMY_HP_MISSILE_CAP` 夹取以保证"导弹一发死" |
| `armor` | float | 装甲减伤 |

### 速度
| 字段 | 单位 | 说明 |
|---|---|---|
| `max_speed` | km/h | 海平面最大速度（高空按 `√σ` 衰减）|
| `cruise_speed` | km/h | 巡航速度，也是初始速度 |
| `stall_speed_base` | km/h | 1G 海平面失速速度；实际 `V_stall = base × √G` |
| `acceleration` | m/s² | 加速能力 |
| `deceleration` | m/s² | 减速能力（含减速板，**通常高于 acceleration**，非对称是设计意图）|
| `g_drag_factor` | m/s² | 每 G 额外阻力减速（拉 G 掉速）|

### 机动性
| 字段 | 说明 |
|---|---|
| `max_g` | 飞行员持续耐受 G（可长期维持）；最大 bank = `acos(1/max_g)` |
| `max_g_structural` | 机体结构极限 G（短时可超越 `max_g`）|
| `roll_rate` | rad/s 滚转速率 → 影响从直飞进入满 bank 转弯要多久（"笨重感"的主要来源）|

### 高度
| 字段 | 说明 |
|---|---|
| `max_altitude` | 米，实用升限 |
| `climb_rate_max` | m/s 最大爬升率 |

### 引擎
| 字段 | 说明 |
|---|---|
| `thrust_to_weight` | 推重比（预留）|
| `drag_coefficient` | 阻力系数（预留）|
| `afterburner_thrust_mult` | 加力时加速度倍率 |

### 燃油
`fuel_capacity`（kg 内油）/ `fuel_rate_normal`（kg/s 巡航油耗）/ `fuel_rate_afterburner`（kg/s 加力油耗）。

⚠ 生存模式通过参数注入设为**无限燃油**，燃油只在沙盒 / 拟真场景有意义。

### 雷达
| 字段 | 说明 |
|---|---|
| `radar_range` | 探测距离（**像素**，1px = 2m）|
| `radar_half_angle` | 扇形半角（度）|
| `lock_time` | 锁定所需持续照射时间（秒）|

⚠ **F-16 的 `radar_range` 是"比较弱"的基准**，新机型低于它必须有理由。见
[DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md) 原则 4(d)。

### 武器与对抗（子 Resource）
| 字段 | 类型 | 说明 |
|---|---|---|
| `gun` | GunParams | 机炮 |
| `rocket` | RocketParams | 无制导火箭弹（低命中率副武器，可选）|
| `torpedo` | TorpedoParams | 加力模式下从机尾抛出的追踪雷（可选）|
| `loyal_wingman` | LoyalWingmanParams | 加力模式下释放的自主无人机。**与 `torpedo` 互斥**（约定只填一个）|
| `missile` | MissileParams | 主导弹 |
| `secondary_missile` | MissileParams | **副武器槽（玩家面叫 SP / Special Weapon）**|
| `flare` | FlareParams | 热诱弹 |
| `combat` | CombatParams | 战斗风格 / 飞行员性格 |

⚠ `secondary_missile` 的字段名是历史遗留（早期 AAM/AGM 双轨制的"空对地"槽）。
**现在它是通用特殊武器槽位**，不是 missile 子类——锁定 / 发射 / UI / 升级路径与主 MSL 完全平行。
详见 [aircraft-system.md 副导弹槽位段](aircraft-system.md)。

### 视觉
| 字段 | 说明 |
|---|---|
| `icon_color` | 图标线框颜色。⚠ 受阵营色板约束（蓝=玩家直属 / 绿=中立第三方 / 橙红=敌）|
| `wing_color` | 机翼配色（alpha 非零时替换机翼色，例如黑机身 + 红翼）；默认全透明 = 跟随 `icon_color` |

### 装备（模块化系统）
| 字段 | 说明 |
|---|---|
| `equipment` | `Array[EquipmentParams]`。**新机型走这里**；空数组时回退读上面的旧字段 |

查询接口：`has_equipment(type)` / 取第一件的 getter —— 同时检查新 `equipment` 数组和旧字段（兼容迁移期）。
生存模式的升级过滤（`requires` 装备门控）和 AI 决策都走这个入口。

装备实现在 `scripts/equipment/`：机炮 / 导弹 / 火箭 / 电磁炮 / 激光 / 热诱弹 / 眼镜蛇 / 赫尔贝特 等。

---

## 参数如何影响飞行行为

- **`max_g` / `max_g_structural`** → 最大 bank 角 = `acos(1/G)`，进而决定转弯率与半径
- **`roll_rate`** → bank 角变化速度 → 决定"从直飞到满 bank 要多久"
- **`max_speed` / `cruise_speed`** → 速度越快，同 bank 角下转弯半径越大（`R = v²/(g·tanφ)`）
- **`stall_speed_base`** → 高 G 转弯时失速速度升高（`× √G`），限制低速急转
  - ⚠ 但**角点速度有地板**，绝不允许"转弯转到失速再也提不起速"的死亡螺旋（feedback 铁律）
- **`acceleration` / `deceleration` / `g_drag_factor`** → 加减速响应与能量损耗
- **`max_altitude` / `climb_rate_max`** → 高度⇌速度能量转换的上限

⚠ **不要直接读 `params.*` 做 AI 战术判断**。速度 / G / 失速 / 角点速度必须经
`AircraftPhysics.effective_*()` accessor，否则运行时 buff（加力模式 / BLOODLUST / 被锁恐慌等）
对 AI 战术层失明。见 [CLAUDE.md 加机动性 buff 的规范](../../CLAUDE.md)（SEAM-001）。

---

## 添加新机型

**主角机**走完整流程：[reference/playable-aircraft-workflow.md](../reference/playable-aircraft-workflow.md)。

**敌机**走 13 步清单：[reference/enemy-index.md](../reference/enemy-index.md)。

两者都要**先建 spec**（[playbook.md](../reference/playbook.md)）。
数值取值遵循 DESIGN_PHILOSOPHY 原则 6：查现实参考 → 按定位取"现实 × 游戏平衡"的中间值。

---

## 已移除的字段（勿再文档化）

| 字段 | 状态 |
|---|---|
| `pilot_stamina` / `stamina_drain_rate` / `stamina_recovery_rate` | **已从代码移除**。飞行员耐力系统被撤下，有效最大 G 不再随耐力浮动。i18n 里的 `UPGRADE_PILOT_STAMINA_*` 键**刻意保留**（留给将来的拟真战役模式），做死键清理时跳过它们 |
