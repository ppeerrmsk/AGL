---
id: gun-burst-fire
kind: weapon
status: done
schema_version: 1
spec_version: 4
owner: 用户（机制指令）+ Claude（数值细化）
depends_on: []
reconstruction_complete: true
---

# 机炮梭射节奏（Burst Fire）

> 敌我双方飞机机炮从"匀速滴弹"改为"一梭一梭地打"：扣扳机就是一串子弹出去，打完一梭停一拍，再打下一梭。

## 1. 设计意图（Why）

- **体验目标**：现实机炮开火是"哒哒哒哒——停——哒哒哒哒"的梭射节奏。旧实现是每发之间固定间隔 `60/fire_rate` 秒的匀速点射，低射速炮（600~1500 发/分）子弹一颗一颗地"滴"出来；火控窗口一闪而过时只漏出一发孤弹，观感极假。
- **两条铁律**（用户指令）：
  1. 射速（fire_rate）越高 → 两梭之间的 CD 越短；
  2. 射速越高 → 同一梭内的出弹频率越快。
- **武器层平衡不变式**：玩家小队与第三方友军持续扣扳机时，长时间平均射速严格等于 `fire_rate`（发/分）。敌方飞机另受 §3.3 的“一次机会一梭”安全门约束，实际平均射速会更低，避免尾追窗口内连续多梭秒杀玩家。
- **Litmus 自检**：纯视觉/手感真实性修复，不新增系统、不加数值膨胀（反模式"数值叠数值"不适用）。
- **反模式规避**：不给梭射加独立可升级维度；`gun_firerate` 升级仍只乘 `fire_rate`，梭内频率与梭间 CD 自动同步缩放（两条铁律天然满足）。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 GunParams 新增字段

| 字段 | 默认值 | 说明 |
|---|---|---|
| `burst_count` | 10 | 每梭弹数。1 = 退化为旧版匀速点射。所有现有 .tres 不覆写，统一吃默认值 |

### 2.2 全局常量（武器模块级，不随炮变）

| 常量 | 值 | 说明 |
|---|---|---|
| `GUN_BURST_DUTY` | 0.3 | 梭内间隔 = 平均间隔 × duty（即梭内射速 ≈ 3.3 × fire_rate） |
| `GUN_BURST_MIN_INTRA` | 1/60 s | 梭内间隔下限（一物理帧一发；防多弹同帧同点重叠成"霰弹团"） |
| 帧补上限 | 3 发/帧 | 累加器一帧最多补发数（防低帧率灾难性追帧） |

### 2.3 派生公式与样例值

```
base_interval = 60 / fire_rate                            # 平均每发间隔（秒）
intra         = max(base_interval × GUN_BURST_DUTY, 1/60) # 梭内间隔
gap           = max(burst_count × (base_interval − intra), 0)  # 梭间 CD
```

平均射速守恒推导：一个完整梭周期 ≈ `burst_count × intra + gap = burst_count × base_interval`，
故长期平均 = `fire_rate`。fire_rate 上升 → intra 与 gap 同时缩短（两条铁律）。

| 炮（fire_rate 发/分） | base | 梭内间隔 | 梭内等效射速 | 10 发梭打完 | 梭间 CD |
|---|---|---|---|---|---|
| UAV 机枪（600） | 0.100s | 0.030s | 2000/分 | ~0.27s | 0.70s |
| AH-64（625） | 0.096s | 0.029s | 2083/分 | ~0.26s | 0.67s |
| Q-5（1400） | 0.043s | 0.0167s（触底） | 3600/分 | ~0.15s | 0.26s |
| F-86（1800） | 0.033s | 0.0167s（触底） | 3600/分 | ~0.15s | 0.17s |
| M61 类（3000） | 0.020s | 0.0167s（触底） | 3600/分 | ~0.15s | 0.03s ≈ 连续弹链 |

低射速炮获得清晰的"一串一停"节奏；高射速加特林天然退化为近连续弹链（现实中 M61 本来就是连续弹雨）。若 `fire_rate × 升级乘数 > 3600`，梭间 CD 钳到 0，等效封顶 3600 发/分——与旧版"一帧一发"物理帧上限行为一致，非新削弱。

## 3. 行为与公式（How）

### 3.1 状态机（每架飞机一个 `_gun_burst_rounds_left` 计数器）

| 状态 | 判定 | 行为 |
|---|---|---|
| 空闲 | `rounds_left == 0` 且 `is_firing == false` | 不出弹；`_fire_cooldown` 钳 0 递减 |
| 梭间 CD | `rounds_left == 0` 且 `is_firing == true` 且 `_fire_cooldown > 0` | 等 CD 走完 |
| 梭起始 | `rounds_left == 0` 且 `is_firing == true` 且 CD 到 0 | 装填 `rounds_left = burst_count`；玩家侧摇一次梭级瞄准误差（±5°~±0.5° 按 pilot_aim_skill） |
| 梭内 | `rounds_left > 0` | **梭承诺**：无视 `is_firing`，按 intra 连续出弹直到打完；`_fire_cooldown` 允许负值累加器携带、一帧最多补 3 发 |
| 梭收尾 | 最后一发出膛 | `_fire_cooldown = gap`，回梭间 CD / 空闲 |

### 3.2 梭承诺（burst commitment）与中止条件

**承诺**：第一发出膛后整梭必须打完，即使火控窗口下一帧就关（目标掠出锥外 / 扫描重评估）。
这直接根治"敌人进窗口一瞬间只射一发孤弹"。弹道方向持续跟随 `_gun_lead_heading`（扫描仍 ~3Hz 刷新）。

**硬中止**（立即清梭，`rounds_left = 0`）：

| 条件 | 原因 |
|---|---|
| JAM 干扰生效 | 所有武器封锁（既有语义） |
| 弹药耗尽 | 无弹可出，触发整匣装填 |
| 整匣装填开始 | 装填期禁射（既有语义） |
| 进入 evasion_mode | 沿用"规避盲射根治"（2026-06-15）：规避中机头大角度机动，绝不允许朝旧 lead 方向喷完剩余整梭 |
| 当前目标被毁/失效 | 承诺对象已消失，禁止把剩余弹沿旧提前方向喷入空域 |
| 飞机摧毁 | 上游不再 tick |

### 3.3 敌方与剧本 FFA 飞机“一次机会一梭”安全门

- **适用范围**：所有 `team == HOSTILE` 或 `team >= TEAM_FREE_FOR_ALL_BASE` 且挂载机炮的 `Aircraft`，不区分普通敌机、王牌、无人机、旋翼机或 AI 原型。The Crucible 的自由混战队不能因为使用剧本 team 而绕过安全门；CIWS / 地面炮仍不在本 spec 范围。
- **开火机会**：敌方飞机在无强制停火且火控请求开火时，只能启动 **1 个完整 `burst_count` 梭**。梭承诺保证第一发出膛后打完整梭，但同一次机会绝不能衔接第二梭。
- **强制停火**：该梭结束（或被 JAM / 弹尽 / 装填 / 规避 / 目标被毁硬中止）后，进入 **3.0s** 强制停火；计时从梭结束/中止后的武器 tick 开始。计时结束且火控条件仍满足，才能启动下一梭。
- **统一执行层兜底**：安全门由 `update_gun` 执行，不依赖某一种 AI 调用路径；即使战术规划、旧 combat tracking、自动扫描或旋翼机路径持续把 `is_firing` 置真，也不能绕过停火期。
- **友方不受限**：玩家小队（PLAYER）与第三方友军（ALLY）不吃该敌方安全门，继续按 §2.3 的武器层平均射速循环梭射。
- **枪口闪光**：只在 `_fire_gun_round` 确实生成弹丸时刷新 0.06 s；`is_firing` 只是持续火控意图，梭间等待或 FFA AI 持续瞄准时不得让闪光常亮。

### 3.4 保留语义（重排不改动）

| 既有机制 | 处理 |
|---|---|
| 玩家梭级瞄准误差（原 `is_firing` 边沿检测摇一次） | 改在**梭起始**摇，语义一致且更精确 |
| 云中/自身入云散布放大、bank 机动惩罚 | 逐发计算，不变 |
| 多管齐射（gun_extra_barrels ≥ 2 时 ±15° 扇形 +2 发） | 逐发跟随，不变 |
| 机炮音效 0.5s 节流 | 不变 |
| AB 回弹 / 机炮发射减伤窗口 / 整匣装填 | 不变 |
| evasion `weapon_cd_mult` 对 `_fire_cooldown` 的进出缩放 | 不变（作用于梭间 CD） |
| CIWS / 地面炮（ground_unit、AA） | **不在本 spec 范围**，维持匀速射流 |

### 3.5 命中火星反馈

- 机炮弹真正结算伤害后，在接触点产生 3 道短促小火星；被机炮闪避、无敌拦截的弹不触发，也不计入 `gun_hits`。
- 同一目标的火星独立 CD 为 **110ms**，一梭密集弹流不会逐发重复播放；不同目标互不压制。
- 火星寿命 **0.16s**，同屏最多 **12 组**。全部状态住 `BulletManager` 的轻量数组，亮芯/橙边分别合并成一次线段批量提交；禁止为每次命中创建 Node/粒子节点。

## 4. 结构与组成（Structure）

- 参数：`GunParams.burst_count`（Resource 字段，全炮默认 10）
- 状态：`Aircraft._gun_burst_rounds_left`（每机一个 int，状态住 Aircraft、逻辑住武器模块，沿用现有分工）
- 逻辑：武器模块 `update_gun`（节奏状态机）+ 抽出的单发出弹函数（散布/伤害/音效/弹药）

## 5. 验收标准（Acceptance / Litmus）

- [x] 梭射节奏成立（`--bench=gun_burst`）：600/分 首梭 10 发跨时 0.28s（旧匀速点射 0.90s）+ 梭间 CD 0.70s
- [x] 敌机火控窗口短暂打开时，射出的是完整一梭而非 1~2 发孤弹（梭承诺，`--bench=gun_burst`：窗口开 1 帧仍出 10 发）
- [x] 规避模式进入瞬间梭立即掐断，无残梭盲射（`--bench=gun_burst`）
- [x] 弹尽立即掐断（`--bench=gun_burst`）；JAM / 装填掐断同一代码路径（同 pattern 置零）
- [x] fire_rate 上升 → 梭内更密 + 梭间 CD 更短（`--bench=gun_burst`：1800/分 vs 600/分，0.15s/0.18s vs 0.28s/0.70s）
- [x] 平均射速守恒（`--bench=gun_burst`：3s 内 600/分 出 32 发、1800/分 出 90 发）
- [x] 敌方飞机持续满足火控时，每次机会只打 1 个完整 `burst_count` 梭；首梭与次梭之间从上一梭末发起至少间隔 3.0s（`--bench=gun_burst`：3.03s）
- [x] 敌方安全门在同帧被多个 AI 火控入口重复查询时不消耗/覆盖许可；武器执行层仍只能启动一梭（`--bench=gun_burst`）
- [x] PLAYER / ALLY 不受敌方安全门影响，继续按武器层节奏循环梭射（`--bench=gun_burst`）
- [x] 剧本 FFA 飞机与 HOSTILE 共用一次机会一梭安全门；枪口闪光只由真实出弹刷新，持续 `is_firing` 不会留下常亮机头特效（`--bench=gun_burst`）
- [ ] 目视确认：低射速炮（UAV/AH-64）观感为"一串一停"，高射速炮近似连续弹链（需进引擎）
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（无新增每帧扫描；仅重排出弹时刻）
- [x] 真命中才出火星：机炮闪避返回未结算，既不触发火星也不累计 `gun_hits`
- [x] 火星节流与上限：同目标 110ms CD、0.16s 寿命、同屏 12 组上限、固定两次批量线段提交
- [x] 已知 seam 未触碰（不动 Situation / 战术决策；机动性 accessor 无涉）
- [ ] i18n：无玩家可见新文本，不适用

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 参数与状态
- [x] `GunParams` 加 `burst_count`（默认 10）
- [x] `Aircraft` 加 `_gun_burst_rounds_left` 状态

### 阶段 2 — 节奏状态机
- [x] 武器模块 `update_gun` 重写为梭射状态机（§3.1），单发出弹逻辑原样抽为独立函数
- [x] 梭承诺 + 全部硬中止条件（§3.2）
- [x] 玩家梭级瞄准误差改挂梭起始

### 阶段 3 — 验证
- [x] `--bench=gun_burst` 无头回归测试（25 断言：梭结构 / 守恒 / 铁律缩放 / 承诺 / 硬中止 / FFA 敌机门 / 真实出弹闪光 / 悬停威胁圈 / 真命中返回值 / 火星节流回收），入 `--bench=all` 回归门
- [x] `--bench=all` 全量回归门 91 项 0 失败（weapon / gun_aim / weapon_doctrine 等均未受影响）
- [x] 同步 reference 索引（code-index 机炮段 + script-index aircraft_weapons 行）+ §7 锚点
- [ ] 进引擎目视 + Sentinel Lv5+ 压测后 status: done

### 阶段 4 — 敌机致死连射收紧
- [x] 删除敌机“2.5s 内可连续多梭”的宏观窗口，改为一次火控机会只启动一梭
- [x] 3.0s 停火计时统一放在武器执行层，覆盖全部敌方 Aircraft 开火路径
- [x] 增加敌我阵营分流与同帧多入口回归断言
- [x] `--bench=gun_burst` 20/20

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 节奏状态机 + 单发出弹 | `scripts/aircraft/aircraft_weapons.gd`（update_gun / _fire_gun_round） |
| 参数字段 | `scripts/gun_params.gd` |
| 梭计数状态 | `scripts/aircraft.gd`（_gun_burst_rounds_left，_fire_cooldown 旁） |
| 参数资源 | `resources/*gun*.tres`（均不覆写，吃默认 burst_count=10） |
| 无头回归测试 | `scripts/tests/test_gun_burst.gd`（--bench=gun_burst，注册于 scripts/bench/bench_runner.gd） |
| 机炮命中火星 | `scripts/bullet_manager.gd`（_emit_hit_spark / _update_hit_sparks / _draw） |
| 敌方一梭安全门 | `scripts/aircraft.gd`（_ai_gun_burst_allowed / _ai_gun_pause_timer）+ `scripts/aircraft/aircraft_weapons.gd`（update_gun） |
| reference 索引行 | code-index.md「武器系统 — 机炮」段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-05 | 1 | 初稿 + 实现（用户指令：机炮改梭射，射速同时缩短梭间 CD 与加快梭内频率） |
| 2026-08-01 | 2 | 强化真命中反馈：闪避不计命中；火星按目标 110ms 节流、0.16s 短寿命、12 组封顶并批量绘制 |
| 2026-08-02 | 3 | 敌方飞机全局改为“一次机会只打一梭，梭后强制停火 3.0s”；安全门下沉武器执行层，堵住不同 AI 路径连续多梭秒杀玩家 |
| 2026-09-05 | 4 | The Crucible 的 team≥3 FFA 飞机纳入同一敌机梭射安全门；枪口闪光从持续火控意图解耦，只在真实出弹后短暂显示，修复 IDO MQ-X 点射结束后机头特效残留。 |
