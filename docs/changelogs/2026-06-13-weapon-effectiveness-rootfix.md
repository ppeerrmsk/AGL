# 2026-06-13 武器使用有效性根因修复（队友连续射空 / 全队不开火 / 对空喷子弹）

诊断来源：`logs/combat_log_20260613_135005.txt`（用户反馈：①队友 AI 对平飞/弱机动目标
连续射空两发；②有时面前没敌机也零碎喷子弹）。

## 诊断

### 1. 全队被"幽灵导弹"自封锁（主因）
日志 A-7[Dispatch]（50hp）时间线：
- `205.2` Solar 发 MRM#1 → `team_inbound=80 ≥ 50` → Dolphin/Ultra 触发 `TEAM_OVERKILL` 被封锁。
- Solar 这枚 **射空**，目标存活。
- `205.2 → 222`（约 17s）全队每帧 `TEAM_OVERKILL`（80→160 ≥ 50）**一弹不发**，
  `220.5` Solar 又补一枚 MRM#2 仍射空。两枚 160 伤害进账，目标却毫发无损。

根因：`MissileManager.team_inbound_damage()` 把任何 `is_active` 的导弹按满伤计入"在飞伤害"，
**不管它是否还持有制导**。一枚丢锁/出 FOV/被干扰、注定射空的导弹会把整支小队的补射
封锁到它寿命耗尽（最长 30s）。这正是"队友攻击零碎且无效 + 目标不死"的体感来源。

### 2. 僚机 MRM 在滚转反向中盲发 → 射空
`spawn_missile` 对飞机源用 `source.heading` 作初始朝向。`205.1` Solar `roll=155°/s bank=80°`
处于滚转反向中，下一帧（bank 瞬时跌进 60° 门限）发射 → 导弹继承"正在甩"的机头方向，
在 `guidance_delay=0.5s`（~700m）盲飞段冲向错误方向，等制导接管时硬转的 A-7 已被甩出
导引头 FOV(±30°) → 永久丢锁射空。f&f 路径豁免滚转率门限（见 aircraft_weapons），
所以这枚在反向中放了出去。

### 3. 机炮对"机头前方空域的前置点"放空
`bfm_intent._apply_combat_weapon` 的 `gun_in_cone` 只判断**前置点**是否在 5° 火控锥内。
横切高速目标时，前置预测点会落进机头正前方而**目标本体在侧后** → 对着空域零碎喷子弹。

## 修复（全部纯代码，不动共享 `default_missile.tres`——它被玩家+僚机+多款敌机共用，
改资源会连带 buff 敌人）

1. **`missile_manager.gd: team_inbound_damage`** — 增加 `not m.has_guidance` 过滤：
   丢锁/干扰中的导弹不再计入"已发足够伤害"。导弹一旦射空，封锁立即解除，队友马上补射。
   （刚发射的 f&f 弹 `has_guidance` 立即为 true，不会出现 1 帧空窗导致双发。）

2. **`missile_manager.gd: spawn_missile`** — 急转/大坡度发射修正：飞机源 + 有目标时，
   若 `|roll_rate|>60°/s` 或 `|bank|>45°`，初始朝向改用 source→target 的 LOS 而非机头，
   消除"继承滚转机头"的初始误差。零坡度平飞发射行为不变。对称作用于全体飞机（含敌机），
   无单边平衡漂移。

3. **`ai/tactical/bfm_intent.gd: _apply_combat_weapon`** — `gun_in_cone` 增加
   `s.aim_align >= GUN_TARGET_AHEAD_MIN(0.7≈cos45.6°)`：前置点在锥内 **且** 目标本体大致
   在机头前方才开火，杜绝目标 >45° 离轴时的对空放空。尾追（aim_align≈1）不受影响。

## 验证

### 自动化回归测试（新增 `scripts/tests/test_weapon_behavior.gd`，经 BenchRunner）
运行：`godot --headless --path . -- --bench=weapon`（无头、确定性、裸构造对象直接断言）。
结果 **6/6 通过**：

```
── A. team_inbound 丢锁过滤 ──
  ✓ 两枚在飞(1 制导/1 丢锁) → 只计制导那枚   inbound=80 期望=80(单枚)
  ✓ 两枚都制导 → 全计入                      inbound=160 期望=160
── B. 急转发射朝 LOS ──
  ✓ 急转中发射 → heading 指向目标(LOS≈+90°)  heading=90° 误差=0.0°
  ✓ 平飞发射 → heading 维持机头(0°)           heading=0.0°
── C. 机炮目标本体守卫 ──
  ✓ 目标 60° 离轴(前置点却在锥内) → 不开火     allow_gun_fire=false
  ✓ 目标 10° 离轴(基本对准) → 开火             allow_gun_fire=true
──────── 结果：6 通过 / 0 失败 ────────
```

- A 同时验证了"丢锁才排除、正常在飞仍计入"两个方向（修复未误伤正常补射判定）。
- B 同时验证了对照（平飞发射行为不变），确认修复只在急转/大坡度时介入。
- 全量加载（`--headless`）无 SCRIPT/Parse/Compile Error。

### 仍需运行时观察
射空后队友应立刻接力补射；`TEAM_OVERKILL` 不应再长时间连刷同一目标；僚机不再对侧后目标空喷机炮。

---

## Ultra 长机原地摇摆打转（SEAM-013，已根治）

同一份日志里长机 `Warhound[Ultra]` 出现"不停滚转、原地打转"。先**排除** bank 控制器
（SEAM-012 已根治，turn_physics 全场景符号反转 ≤2），定位为**战术追踪点 sub-intent 抖动**：
`bfm_intent._missile_engage_pos` 的 crank 侧每帧按"哪侧更对齐机头"离散重选，目标近共线时两侧
align 几乎相等，单帧噪声让追踪点在机身两侧 ±5000px(=10000m) 瞬移，平滑控制器忠实追摆 →
±80° 大坡来回、航向几乎不动。

**修复**：离散选侧换成**连续 clamp** —— `aim_hdg = los_hdg + clamp(nose_off, ±crank_deg)`。
nose_off 过零时 aim 连续穿过 LOS，没有"侧"可翻。纯函数、语义不变（仍朝机头侧 crank、封顶 crank_deg）。
详见 [SEAM-013](../architecture/known-seams.md)。

**测试**：`test_weapon_behavior.gd` 新增测试 D（`--bench=weapon`），nose_off 从 +20°→−20° 扫过 0，
量化 aim 航向相邻步进：**翻号=0、最大步进 1.0°**（修复前过零处 ~30° 跳变）。

### 最终自动化测试结果（`--bench=weapon`）：7/7 通过
```
A. team_inbound 丢锁过滤        ✓✓   (80 / 160)
B. 急转发射朝 LOS              ✓✓   (90° / 0°)
C. 机炮目标本体守卫            ✓✓   (false / true)
D. crank 追踪点无翻号(SEAM-013) ✓    (翻号=0, 最大步进 1.0°)
──────── 7 通过 / 0 失败 ────────
```
