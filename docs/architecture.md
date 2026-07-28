# 架构设计与核心取舍

> 最后校订：2026-07-26。本文写**长期不变的架构决策与物理公式**。
> 具体代码位置看 [reference/code-index.md](reference/code-index.md)，
> 数值与行为看 [specs/](specs/_INDEX.md)。

## 核心设计决策

1. **不使用 Godot 物理引擎**：飞机运动完全由自定义公式驱动，在 `_physics_process` 中手动更新
   `position`。物理行为完全可控，也让无头 bench 能逐帧步进复现。

2. **2D 场景 + 虚拟高度**：使用 Godot 的 2D 系统，`altitude` 作为纯数值变量存在，
   仅通过图标缩放可视化。高度档位 `AltitudeTier { GROUND, LOW, MID, HIGH }` 承担战术语义。

3. **单位系统**：内部使用 SI 单位（米、m/s），显示时转换为 km/h。
   地图 1 像素 = 2 米（`PIXELS_PER_METER = 0.5`）。

4. **输入模型**：玩家点击 → 设定 `target_position`，飞机自主执行转弯物理（G 力极限转弯）。
   不是瞬间转向——"笨重 + 延迟快感"是核心手感（DESIGN_PHILOSOPHY 原则 2）。

5. **飞机通用模板**：`aircraft.tscn` + `AircraftParams` Resource，通过不同 `.tres` 定义机型。
   生成时必须 `duplicate(true)`，否则升级/缩放会污染共享资源。

6. **AI 组合模式**：`AIController` 作为子节点附加到飞机上，飞机本身不区分玩家/AI，
   只是**目标来源**不同。这让"切控 1-4"变成拔插 AI，而不是换实体。

7. **决策 / 执行分离**：`ai/tactical/` 的 planner 是**纯函数**——吃 `Situation` 快照，
   吐 `TacticalPlan`（intent + 目标速度 + 武器模式）。执行侧
   （`aircraft/aircraft_physics.gd` 等）只负责把 plan 变成物理。
   新战术行为加在 planner 里，不散点改物理 tick。

8. **buff 单一注入点**：任何影响速度 / G / 失速 / 转弯的 buff 只能进两个地方——
   永久升级改 `params.*`，运行时状态改 `AircraftPhysics.effective_*()` accessor。
   **禁止**在物理 tick 里散点 if-else，也禁止 `Situation` 直读 `params.*`
   （否则 AI 战术层对 buff 失明）。见 CLAUDE.md（SEAM-001）。

9. **剧本 / 演出与所有权**：单位的非常规行为走 `GameEvent` + `AIDirective`
   （声明式覆盖，事件结束自动撤销），而不是在 spawner 里堆特殊状态机。
   演出层（`presentation/`）下发演员指令时**委托 GameEvent**，不另造所有权体系。

10. **模式隔离靠数据不靠分支**：共享层禁止 `if in_survivor_mode` / `if in_sandbox`，
    模式差异一律走参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入。

---

## 物理演算流程（每帧）

`aircraft.gd:_physics_process` 按 **LOD 三档**路由，各档调度
`AircraftPhysics` / `AircraftWeapons` / `AircraftCombatTracking` / `AircraftFormation` /
`AircraftFlares` 这几个静态模块：

| LOD | 适用 | 行为 |
|---|---|---|
| 0（完整） | 玩家 + 交战中飞机 | 全部步骤每帧跑 |
| 1（简化） | 编队僚机巡航 | 多数步骤降频；编队托管走专用三段式航向控制 |
| 2（屏幕外） | 离屏飞机 | 降频完整更新，其余帧仅位移 |

单帧内的大致顺序（细节以代码为准，见 [systems/aircraft-system.md](systems/aircraft-system.md)）：

```
（可选）TacticalPlanner：Situation 快照 → plan → 写入 target_* / weapon_mode / is_firing
  ├── 武器模式判定
  ├── 战斗追踪（按武器模式分导弹/机炮策略）
  ├── 能量管理（速度/高度/加力）
  ├── 目标航向 → bank → heading → speed → altitude
  ├── 燃油 / 失速 / G 载荷
  ├── 位移（heading + speed → position）
  ├── 机炮 / 导弹 / 火箭 / 热诱弹
  └── 视觉（rotation = heading）
```

⚠ 各步骤的**函数名与所在文件会变**（历史上已经历一次子模块拆分）。
要准确入口请查 [reference/script-index.md](reference/script-index.md)，不要依赖本文的步骤名。

---

## 关键物理公式

| 物理量 | 公式 | 说明 |
|--------|------|------|
| 转弯率 | `ω = g × tan(bank_angle) / speed` | 标准协调转弯 |
| 转弯半径 | `R = speed² / (g × tan(bank_angle))` | |
| G-force | `G = 1 / cos(bank_angle)` | 水平面转弯过载 |
| 失速速度 | `V_stall = V_stall_base × G^0.4` | 过载越大失速速度越高（曾用 √G，太严改缓） |
| 低空动压顶速（q-limit） | 超音速机 `V_max × lerp(0.7, 1.0, alt/5000)` | 海平面只拿 70% 顶速，5000m 以上拿满——**高空更快**，亚音速机（<1300km/h）不受限 |
| 高度⇌速度耦合 | `dV/dt = -g × (vs/speed) × 2.5` | 俯冲加速 / 爬升减速；**刻意 ×2.5 放大**（PE_KE_BOOST），爬升掉速远比真实剧烈 |
| 爬升门控 | 速度距失速线 < 50 m/s 时爬升率线性衰减到 0 | 保证爬升不会把自己爬进失速，但会把速度钉在失速线附近直到爬完 |
| 高 G 阻力 | `-(G-1) × g_drag_factor × 0.4 × (1 - alt/15000 × 0.3)` | 拉 G 掉速；高空阻力折减（10000m 时 −20%）；超持续 max_g 部分另有结构掉速项，整体钳制在角点速度地板之上 |

注：`air_density_ratio`（`σ = e^(-altitude/8500)`）目前是**死代码**——定义在
aircraft_physics.gd 但无任何调用点；旧版"高空最大速度 `V_max × √σ` 下降"的模型已被
q-limit（高空更快）取代。

**转弯控制器是临界阻尼 PD**（不是简单比例）——见 SEAM-012 与
[planning/physics-ai-control-refactor.md](planning/physics-ai-control-refactor.md)。
改转弯 / bank / 编队 / 规避物理时必须跑 `--bench=turn_physics`（量化符号反转与同向呼吸两指标），
别靠进引擎手感判断。

⚠ **角点速度有地板**：任何拉 G 掉速 / 能量机制都不允许出现"转弯转到失速、
速度再也提不起来"的死亡螺旋——玩家只控走位不能精确控速（feedback 铁律）。

---

## 编队（已实装，非"预留"）

早期版本这里写过"编队扩展预留"。编队早已是核心系统：

- `Squad` 数据结构 + 阵型槽位计算（`squad.gd` / `squad_factory.gd`）
- LOD 1 编队托管的三段式航向控制（`aircraft/aircraft_formation.gd`）
- 编队学说（凝聚 / 纪律 / 齐射 / 护卫）见
  [specs/systems/squad-cohesion](specs/systems/squad-cohesion.md) 等
- 指挥层独立在 `scripts/rts/`

**编队 / 跟随必须物理优雅**：俯视全程可见，归位靠真实 bank / 盘旋自然到位，
禁止直接挪坐标或伪造曲线等非物理强扭。
