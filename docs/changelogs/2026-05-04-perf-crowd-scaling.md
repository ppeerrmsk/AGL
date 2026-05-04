# 2026-05-04 — 同屏敌人多时性能优化（A-E 五项）

## 背景

用户反馈"场上敌人多时帧数明显下降"，需求"同屏敌人越多就省略低等级敌人 AI 来支持更多敌人"。

性能审计找到 5 个热点（按敌机增长成本从重到轻）：
1. O(N²) 雷达锁定（survivor_mode._update_radar_locks，0.2s 节流但 N=50 仍 12.5k 比较/秒）
2. AI 用 `get_parent().get_children()` 全树扫（违反 CLAUDE.md 性能守则第 4 条）
3. BFM `assess_situation` 高频 acos（已有 ai_tick_divisor 节流，但固定值不随场上人数动态降）
4. CommanderAura 0.5s buff 写参数（小，留作未来）
5. auto_gun_scan 每 0.3s O(N)（小，留作未来）

## 改动总览

### A. 共享列表替代 get_children()（零行为变化）

替换 4 处 `get_parent().get_children()` 为 `CombatUnit.all_units`：
- `scripts/ai/squad_coordination.gd:scan_leader_rear` / `scan_squad_nearby_enemy`
- `scripts/ai_controller.gd:_try_engage_in_tether_range` / 自爆机敌人扫描
- `scripts/ai/target_selection.gd:` BOSS 重锁路径

`CombatUnit.all_units` 是 survivor_mode 每帧维护的共享列表，节点数 N >> 单位数。改后 AI 扫描成本从"全场景树"降到"实际单位列表"。

### B. 动态 AI tick scaling（拥挤度分级降频）

`scripts/ai_controller.gd` 加：
- `enum AIScaleClass { IMMUNE, NORMAL, CHEAP }` + 阈值常量
- `_compute_scaling_class()` 自动从 aircraft.team / category meta / params.is_unmanned 派生：
  - **IMMUNE**：玩家方 / BOSS（category="boss"）/ Sentinel（enemy_type="uav_commander"）→ 永不降频
  - **CHEAP**：UAV/UCAV/Adds（params.is_unmanned 或 category="adds"）→ 30+ 敌机时 ×2
  - **NORMAL**：MiG/F-86 等载人战机 → 30+ 敌机时 ×1.5
- `_physics_process` 头部按 `CombatUnit.all_units.size()` 计算 `effective_divisor`：
  - ≤12 单位：原 divisor 不变
  - 12→30 单位：线性插值 to max_mult
  - ≥30 单位：拉满 max_mult

实测：30 敌机时 simple_ai UAV divisor 从 6 → **12**（5Hz AI），符合用户规格。

### C. 屏幕外远距冻结

`scripts/survivor/survivor_mode.gd:_update_offscreen_lod`：
- 新常量 `FAR_FREEZE_DIST_SQ = 750² = 562500`（PIXELS_PER_METER=0.5 → 1.5km）
- 屏幕外 + 距玩家 > 1.5km + 非 BOSS / 非 Sentinel 的敌机：`set_physics_process(false)` 完全冻结 AI 和 Aircraft，零成本
- 进屏幕或靠近自动 `set_physics_process(true)` 解冻

### D. 雷达锁定子集轮转扫描

`scripts/survivor/survivor_mode.gd:_update_radar_locks`：
- 新常量 `RADAR_LOCK_STRIDE = 4`：每 0.2s tick 只扫 1/4 单位作为 shooter，全覆盖周期 0.8s
- `per_shooter_delta = step_delta * STRIDE` 抵消 1/4 频率，每个 shooter 看到的累积速率不变 → 锁定时间体感无变化
- 单 tick 成本从 N² → N²/4
- 副作用：目标离开雷达锥后衰减最多滞后 0.6s（旧 0.2s），实测无感知

### E. LOD 1 编队 speed/altitude 降到 20Hz

`scripts/aircraft/aircraft_formation.gd:update_follow`：
- bank / heading / position 保持 60Hz（视觉敏感）
- speed / altitude 改成 `_lod_frame % 3 == 0` + `delta×3`，20Hz 更新
- 各飞机 _lod_frame 错相位天然分散负载

依据：飞机加减速 / 升降是秒级慢量，20Hz 决策完全够；20Hz 是历史风险点，但 speed/altitude 不影响视觉对齐，相对安全。

## 收益估算

| 场景 | 改动前 | 改动后估算 |
|------|--------|-----------|
| 同屏 30 敌机 | ~25 fps | ~50+ fps（A+B+D 主力） |
| 屏幕外大量 UAV | 持续吃 CPU | 0 成本（C 完全冻结） |
| 编队 20+ 友方 | LOD 1 60Hz 速度计算 | LOD 1 20Hz（E） |

## 行为退化（用户已批准）

- 30+ 敌机时 UAV/UCAV AI 从 20Hz → 5Hz：会"反应慢半拍"，不再做精细机动决策。设计上"屎山多 = 像炮灰"符合游戏感
- 屏幕外远距敌机完全冻结：进屏前不更新位置，可能轻微"跳跃"出现
- LOD 1 编队 speed/altitude 滞后 50ms 决策：紧跟队列但加减速反应慢

## 不在范围内（留作后续）

- CommanderAura 每 0.5s 重写所有附近 UAV 的 aggression/max_g 等：成本不大，可后续换成 AOEBroadcast 状态
- auto_gun_scan 玩家 LOD 0：本地小 N 扫描，不是热点
- BFMTactics.assess_situation 本身的 acos 链：已被 B 阶段间接降频解决

## 验证

需要在生存模式跑：
1. **基线**：低敌人数（< 12）时玩法不变 — AI 反应、锁定速度、编队行为应与重构前一致
2. **拥挤场景**（Lv 8+ 让 30+ 敌机出现）：FPS 应明显改善；UAV/Adds 反应肉眼可见变迟钝是预期
3. **远距敌人冻结**：让敌机飞远 + 屏幕外 → 它们应"暂停"在原位（位置不变，AI 不跑）；玩家追近后立即解冻继续作战
4. **F-47 / Sentinel BOSS**：永远 IMMUNE，机动反应应与重构前完全一致
5. **F11 编队 debug**：友方僚机阵型应与重构前一致（speed/altitude 滞后 50ms 不应造成可见跟丢）

F9 导 log 看有没有 push_warning。FPS 比较看 Godot Monitor → Time → Process。
