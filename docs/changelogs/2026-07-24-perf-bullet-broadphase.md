# 2026-07-24 性能修复 —— 航母战子弹碰撞广相 + 防死亡螺旋

> 承接 [2026-07-23 航母群掉帧修复](2026-07-23-perf-carrier-convoy-fix.md)：那批修好了 `_draw`（批量绘制），
> 但用户 playtest 反馈**航母战 + 友军航母对射时仍掉到个位数帧**。用修复后的真机日志二次定位 →
> 元凶是命中循环（`bullet_phys`），本批三项修复根治 + 兜底。

## 诊断（修复后真机日志实证）

对比 07-24 两份 F9 快照（**均在 07-23 批量绘制修复之后**）：

| 桶 | 00:42 健康（93 FPS / 65 机） | 00:37 卡死（**~8 FPS** / 146 机） |
|---|---|---|
| `bullet_phys`（子弹物理+碰撞） | 69 µs/帧 | **80,345 µs/帧 = 80 ms** |
| `bullet_draw`（07-23 已修） | 1 µs | 695 µs（无关紧要） |
| `aircraft_draw` | 1675 µs | 24,879 µs |
| `aircraft_phys` | 651 µs | 13,744 µs |

`bullet_phys` 一个桶吃掉 8FPS 帧预算（125ms）的 **64%**，其它全是配角。**批量绘制修的是绘制，没碰碰撞循环。**

### 根因（两个问题叠乘）

1. **命中循环是 O(真弹 × 单位数)**：`bullet_manager._physics_process` 里每颗真弹遍历整个
   `combat_unit_list` 做距离判定。航母战 = 舰队狂喷 CIWS/AA 真弹 + 大混战 100+ 机同场，
   两个因子同时爆炸。65→146 机（2.2×）配弹幕翻倍 → 碰撞开销涨 ~1160×（69µs→80ms）。
2. **物理补步死亡螺旋**：快照 `calls=64` 但仅 `8 帧` —— 物理仍跑满 60Hz，渲染掉到 8Hz。
   Godot 掉帧时用最多 8 个物理子步追时间，每步都重跑一遍 10ms 的碰撞循环 → 单渲染帧内 8×10ms=80ms
   → 渲染更慢 → 追更多步。越卡越卡冻成幻灯片。

## 修复（用户批准全三项）

### ① 防死亡螺旋 —— `project.godot` 物理补步封顶
`physics/common/max_physics_steps_per_frame` 默认 8 → **3**。掉帧时单渲染帧内最多补 3 个物理子步，
卡顿退化为"平滑掉几帧"而非彻底冻死。物理仍 60Hz，零逻辑改动，无风险。

### ② 装饰弹软上限 —— `bullet_manager.spawn_bullet`
`MAX_BULLETS=1200`。到上限后**只拒绝新的 `visual_only` 装饰弹**，真弹 / 火箭永远照常生成
（不影响平衡与命中）。装饰弹占 CIWS 出弹 2/3，封住它就封住弹幕洪峰；真弹本就受 1/3 射速 + 2s 寿命自然限量。
兑现 07-23"上限作兜底，等真机数据再决定"——这份日志就是数据。

### ③ 命中广相网格 —— `scripts/util/unit_grid.gd`（新模块）+ `bullet_manager`
把命中循环从"每弹扫全场"换成均匀网格空间哈希：每物理帧按单位位置重建网格，每颗真弹只查
**自己所在格的 3×3 邻域**（`GRID_CELL_SIZE=256px`）。大/小单位分治：
- 小单位（飞机 / 地面 / MountTarget，命中半径 ≤ 20px）→ 入格
- 大单位（`NavalUnit`，命中半径随 hull_length 扩到 ~140px）→ `large_units` 线性表，逐弹全扫
  （船数量少 ≤~13，线性无所谓；正好化解命中半径悬殊）

**无漏判保证**：`cell_size(256) >= 最大小单位命中半径(20)` → 3×3 邻域候选集 ⊇ 任何真正会命中的单位。
候选集缩小、判定逻辑逐字节不变 → 命中结果与旧的全扫**等价**（见验证）。候选集是本帧快照，
命中循环内仍保留 per-candidate `is_instance_valid + is_destroyed` 守卫（同帧可能已被别的弹击毁）。

> ⚠ 仅**主命中循环**改走网格。火箭近炸引信扫描（prox fuse）+ AOE 引爆扫描仍走全 `combat_unit_list`
> ——火箭数量远少于 CIWS 真弹（洪峰不在火箭），且其半径可能大于网格格，保守起见不动。

## 验证

| 项 | 结果 |
|---|---|
| `--import` 全项目重编译 | ✅ 零脚本错误 |
| **`--bench=bullet_grid`（新增等价性单测）** | ✅ 8/0：邻域超集 / hit_r=20 命中集等价 / 大单位恒扫 / 已毁排除 / 空网格 |
| `--bench=all` 回归门 | ✅ 35 项测试 0 失败（未连带破坏） |
| **真机压测** | ⏳ **待 playtest**：无头不渲染、也不触发物理补步 → FPS 收益测不出，须真机复核 |

### 真机验证方法（沿用 07-23）
1. Debug 面板刷 `CSG_BOSS`（航母战斗群）+ 触发护送任务，让车队进舰队 CIWS 包线；最好再叠大混战把飞机数堆到 100+
2. **卡顿正在发生时按 F9**（快照只存最后 1s）
3. 看 PERF SNAPSHOT：`bullet_phys` 应从 ~80ms 级跌到亚毫秒/毫秒级；首行 `(last 1.00s, N frames)` 的 N 应显著回升

## 承接 07-23"未做"清单

- ✅ **子弹数上限** → 本批 ②（软上限，只丢装饰弹）
- ✅ **命中循环 O(N×M)** → 本批 ③（广相网格），这是 80ms 的真正根治
- ⏳ **绿友军（team 2）纳入 LOD**：仍待裁定（网格已大幅削平命中成本，可能不再必要——看真机数据）。**改只能动 team 2，绝不碰 team 0**
- ⏳ EventLogger 缓冲区 300s（`pop_front` O(N)）：另记
- ⏳ `_log_name()` 三阵营显示适配：另记

## 顺带修复：`GunParams.lifetime` 崩溃（720 批既存 bug，非本批引入）

playtest 时刷出 199 条 `Invalid access to property 'lifetime' on GunParams`。根因是 720 技能批
"枪械精度·子弹寿命 +20%/层"半成品：`survivor_player.apply_upgrade` 写了 `p.gun.lifetime *= …`，
但 `GunParams` 从未加过该字段、`bullet_manager` 也硬编码 `2.0s` 从不读它（power-curve spec §7 早有记录）。
玩家一选这条技能就崩，会直接毁掉性能验证 playtest。用户拍板**修法A（让技能生效）**：

- `GunParams` 加 `@export var lifetime := 2.0`（默认 = 旧硬编码值）
- `bullet_manager.spawn_bullet` 加可选 `life_seconds` 参数据此定 `life`/`max_life`
- `aircraft_weapons` 主机炮三处调用传 `gun.lifetime`（机载 CIWS 点防 line 478 保留 2.0——非本技能路径）
- 测试替身 `BulletStub.spawn_bullet` 签名对齐（补 is_ciws/visual_only/life_seconds 可选参）

效果：技能现按设计生效（子弹寿命 +20%/层，弹道延伸）——**一次平衡改动，数值待 playtest 调**；
不选该技能时行为与旧版一致（默认 2.0）。`--bench=all` 36 项全绿。

## 后续可选（若真机仍不够）
- `missile_manager` 的目标扫描同样是 O(N×M)，可复用 `UnitGrid`（本模块刻意做成通用 RefCounted 便于复用）
- 网格格大小 / 是否把 MountTarget 也归大单位，按真机 profiler 微调
