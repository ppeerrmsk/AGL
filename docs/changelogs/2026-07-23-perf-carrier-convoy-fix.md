# 2026-07-23 性能修复 —— 航母群 + 友军护送同场掉到个位数帧

> playtest 实测：航母战斗群 BOSS 登场时恰逢友军护送车队（CH-47）靠近，帧数掉到几帧。
> 诊断（日志实证 + 代码分析）→ 三项修复。**绘制优化须真机 playtest 复核**（无头 `_draw` 不跑）。

## 诊断

### 触发链（log 20260723_004555 实证）

| 时刻 | 事件 |
|---|---|
| 594.3 | 友军护送车队出发（3× CH-47，team 2 ALLY） |
| 666.7 | 航母战斗群登场：CV + 10 护卫舰 = **12 naval + 38 挂点**（18 CIWS / 8 VLS / 6 舰炮 / 6 短 SAM，与日志 `mt=38` 完全吻合） |
| 666~699 | 护卫舰对车队直升机 **58 次命中**（FFG-927×24 / FFG-975×22 / FFG-156×12） |

**三阵营 IFF 是正确行为，不是 bug**：`CombatUnit.is_hostile_to()` = `(team==1) != (other.team==1)`，team 2（绿友军）对敌方完全敌对。CH-47 又慢又近 → 舰队合法优先目标。（另：日志里友军显示成 `Enemy/CH-47` 是 `_log_name()` 的 `team==0?Friend:Enemy` 二元判断未适配三阵营——**纯显示 bug，IFF 没坏**，另记。）

### 根因（都在 profiler 盲区）

78 FPS 快照里所有 PerfBuckets 桶加起来仅 ~3ms/帧，而帧时间 12.8ms —— **76% 在埋点盲区**，而 `BulletManager`/`MissileManager`/`NavalWeapons` 恰好零埋点。

车队进 CIWS 包线（1000px）瞬间，**38 挂点从静默一次性切满功率**：18 CIWS×33Hz + 6 舰炮×15Hz ≈ 690 发/秒，子弹寿命 2s → 常驻 ~1400 颗。而 `BulletManager`：
- **绘制**：`_draw` 逐颗 `draw_line(抗锯齿)` = ~1400 draw call/帧（违反性能守则 R3）——**最大头**
- **无上限**：`spawn_bullet` 无条件 append（对比 `_torpedoes` 有 `MAX_TORPEDOES_PER_SOURCE=21`）
- 碰撞 O(真弹×单位)：装饰弹已跳过（`visual_only`），真弹 ~400×105

放大器：CIWS 空闲扫描节流反转（`naval_weapons.gd`）——空闲挂点每帧全场扫两次 `all_units`，38 挂点空转在开火前就已在烧。

## 修复（用户批准前三项）

### 1. 子弹批量绘制（`bullet_manager.gd` `_draw`）
曳光弹收集成线段对，一次 `draw_multiline`（单色）提交，替代逐颗 `draw_line`。~1400 draw
call → 1。火箭数量少 + 带圆头 → 保留逐颗。与 `naval_unit` 边缘线"48 段一调用"同款 API。

> ⚠ **regression 修正（2026-07-23，同日）**：初版用 `draw_multiline_colors`（想保留逐颗
> 末段淡出）——但该方法 `colors` 数组长度语义（逐点 vs 逐段）在不同 Godot 版本不一致，
> 长度不匹配时**静默不画**（无报错），导致游戏里**曳光弹/机炮子弹全部消失**（火箭走
> `draw_line` 不受影响，正好是"机炮子弹没了"的现象）。改用**已在生产验证的单色
> `draw_multiline`**（`naval_unit.gd:685`），代价是曳光弹放弃逐颗末段淡出（改瞬间消失，
> 密集弹幕里几乎不可见）。**教训：`_draw` 改动无头测不到（`--draw` 不执行），必须真机验证。**

### 2. CIWS 空闲节流反转（`naval_weapons.gd` `_update_ciws`）
节流路径在缓存目标失效时**主动清零 `acquire_cooldown` 再落完整扫描** → 空闲 CIWS 每帧全扫。
改为 `return` 尊重 cooldown：重新捕获延迟 ≤ `CIWS_ACQUIRE_INTERVAL(0.15s)`，对 CIWS 无感，
空转扫描频率降 ~9×。

### 3. 补性能埋点（消除盲区）
新增 4 桶：`bullet_phys`（物理+命中循环）、`bullet_draw`（绘制）、`missile_phys`（命中+AOE+
闪光+快照）、`naval_weapons`（12 舰火控累加）+ `bullet_count` 瞬时值。下次 F9 快照直接看出
是哪块爆。

**修复期抓到并修正的自身 bug**：`missile_phys` 的 tick 初版误埋进 `_update_aoe_zones`（`_t0`
不在该函数作用域）→ `--import` parse error 抓到 → 移到 `_physics_process` 真正末尾
（`_update_aoe_zones` 本就在其内部第 429 行被调，覆盖完整）。

## 验证

| 项 | 结果 |
|---|---|
| `--import` 全项目重编译 | ✅ 零脚本错误（`update_scripts_classes` DONE） |
| `test_map_expansion.gd` | ✅ 全绿（未连带破坏） |
| **真机压测** | ⏳ **待 playtest**：无头 `_draw` 不执行，绘制优化测不出 |

### 真机验证方法
1. Debug 面板刷 `CSG_BOSS`（航母战斗群）+ 触发护送任务，让车队进舰队 CIWS 包线
2. **卡顿正在发生时按 F9**（不要等恢复——快照只存最后 1s）
3. 看 PERF SNAPSHOT 首行 `(last 1.00s, N frames)` 的 N = 真实帧率；对比新桶
   `bullet_draw` / `bullet_phys` / `naval_weapons` 应显著低于修复前

## 未做（留后续 / 用户裁定）

- **子弹数上限**：碰撞已跳过装饰弹，批量绘制应单独够用 → 上限作兜底，**等真机压测数据**再决定
  （"playtest 证明必要再补"）
- **绿友军（team 2）纳入 LOD**：放大器之一——`survivor_mode.gd` 的 `if ac.team != TEAM_HOSTILE:
  continue` 把蓝队友（team 0）和绿友军（team 2）一起豁免了 LOD。**用户明确：蓝队友豁免是对的，
  不动**；绿友军（护送/AWACS 等第三方）是否纳入离屏降频待裁定。**改只能动 team 2，绝不碰 team 0**
- **EventLogger 缓冲区 300s**（注释写 60s，差 5×，无关闭开关）：`pop_front` O(N) 每帧内存搬移，
  另记
- `_log_name()` 三阵营显示适配（友军显示成 Enemy/）
