# 全部重构域智能测试报告（2026-08-28）

## 范围

本报告覆盖本轮已经完成的四个重构域，而非仅表现层：

1. 飞机物理与 AI 操控权限、状态机、战术执行器和共享预测公式；
2. 武器选择、发射、弹体飞行、命中资格、伤害分派、归因、拦截和终态；
3. 战区、王牌中队、净时间轴、BOSS 阶段、跨场景重置和支援生命周期；
4. 弹丸、爆点、尾迹、导弹和地图绘制。

2026-08-28 后续追加的第 5 域为 BOSS 系统，已建立独立的
`boss-system-refactor.md`，覆盖遭遇流程、行为、隐形/可见性、身份与公共生命周期。
当前完成的是重构前审计和 Phase 0 基线，尚未把 BOSS 代码重构标为完成。

所有运行时测试均通过 `bench/run.cmd` 在 Godot 4.7.2 Shadow 隔离环境执行。性能数据使用 Visual；纯规则和生命周期使用 Headless。

## 1. 飞机物理与 AI

通过的重点门：

- `turn_physics`：四类机型的 J-turn、急转、追圆、S 转、AI 分频和近目标转弯均满足平滑门，总净 buzz=33。
- `predicted_path`：13/13；速度、航向、高度、失速、超巡爬升和滚转的实飞/预测薄壳逐步同值。
- `state_machine`：22/22；状态进入、软重连、规避 modifier、约束和高度策略正常。
- `bfm_intent`：125/125；统一 TacticalPlanner 的全部 intent 与共享 `PursuitGeometry` 正常。
- `intent` 14/14、`target_arb` 25/25、`cmd_evade` 26/26：控制权优先级、目标所有权、真实导弹威胁、flare 优先和脱险后命令恢复正常。
- `hard_brake` 5/5、`target_sel` 42/42、`slow_air_pass` 14/14、`surface_pass` 32/32、`joust` 16/16。
- `rejoin` 的真实物理归队样本全部收敛；`dogfight_growth` 六套 build、两种 planner、三种开局均无 NaN/零速，并产生真实机炮窗。

结论：没有发现 update/step 公式分叉、操控权抢写、EVADE 卡死、目标仲裁回退或统一 planner 行为断裂。

## 2. 武器发射与命中结算

通过的重点门：

- `weapon_hit`：6/6；通用目标、主动机动拒绝、已释放 source、软地面目标、舰船倍率和 Aircraft 机炮入口均正确。
- `weapon`：33/33；发射、弹药、冷却、目标释放和瞄准连续性正常。
- `weapon_doctrine`：34/34；武器竞选、发射窗、电磁炮锁定解和导弹准则正常。
- `gun_aim` 6/6、`gun_burst` 21/21、`missile_env` 4/4。
- `bullet_grid` 8/8、`missile_grid` 6/6；broad-phase 与旧目标顺序合同一致。
- `rocket_trajectory` 46/46；直飞段、smoothstep 散开、追踪修正、左右涟发和敌我共用出膛入口正常。
- `ciws_intercept` 14/14；5/8 枚齐射拦截率门通过，导弹统一拦截终态正常。
- `zone_atmosphere`、`boss_progression` 44/44、`fire_alloc` 15/15、`fire_discipline` 10/10 通过。
- Visual：`rocket_trajectory_visual` 与 `hit_flash_visual` 退出码 0；人工检查火箭轨迹、五命中区、四类大型机结构解体和坠毁末段均完整。

结论：没有发现重复扣血、错误阵营命中、归因丢失、已释放 source 访问、舰船倍率变化或导弹拦截回收异常。

## 3. 战场任务与游戏规则

通过的重点门：

- `battlefield_flow`：31/31；净时间推进、暂停/预热门、补给时间税、奖励倒拨、战区到点事务和 BOSS 阶段切换正常。
- 王牌第一槽 3:30、第二槽 BOSS 前 3:00、第二槽倒拨锁存、同局无放回、最多两支及 ORION 一次性门均通过。
- 新局/退局共用 reset：技能队级开关、天气/账本和目标上下文正确清理。
- `ace_tier`：80/80；王牌成员、HP、缩放、呼号、档案和音乐生命周期正常。
- `zone_air_support`：75/75；战略态到 LIVE、可见性生成门、空/地/王牌支援、撤离和收益隔离正常。
- `boss_phase`：33/33；BOSS 解锁总闸、画面内物理撤离、画面外释放、豁免演员和空地 XP 总闸正常。
- `zone_rewards` 47/47、`lancer_squad` 52/52、`boss_progression` 44/44、`hyper_a` 108/108、`faction_conversion` 26/26。

结论：没有发现时间双写、王牌重复刷/倒拨重开、战区重复结算、BOSS 阶段漏停、退局状态污染或撤离对象跨帧崩溃。

## 4. 表现层

表现层专项、Visual 与地图性能结果详见同日的 `presentation-rendering-validation-2026-08-28.md`。共享 packet 16/16、视觉弹 SoA 7/7、尾迹 LOD 7/7、导弹 LOD 8/8，地图 packet/LOD/预热合同均通过。

## 5. 性能与旧版对比

### 三轮同条件中位数

| 代表场景 | 旧版 | 当前 | 判断 |
| --- | ---: | ---: | --- |
| C1 36 单位 / 8 km，平均 FPS | 353.97 | 363.31 | +2.6%，无回退 |
| C1 P1 FPS | 221.52 | 270.00 | +21.9% |
| C2 48 单位 / 24 km，平均 FPS | 378.35 | 381.71 | +0.9%，无回退 |
| C2 P1 FPS | 220.00 | 239.37 | +8.8% |
| 海战弹幕，当前平均/P1 FPS | - | 592.00 / 420.00 | 三轮低于 60 帧中位数 0 |
| 地图转场，当前平均/P1 FPS | - | 466.30 / 274.73 | 三轮低于 60 帧中位数 0 |

C1/C2 使用 2026-08-24 同镜头巡航、同负载、同 30 秒 Visual 三轮基线。C1 的 `bullet_draw` 维持 5 us/f，`trail_draw` 从 81 降至 68 us/f；C2 的导弹和尾迹桶基本持平。

### 战场流程真实支援场

| 场景 | 历史单样本 | 当前三轮中位数 | 当前 P1 | 低于 60 帧 |
| --- | ---: | ---: | ---: | ---: |
| 45 机战区双支援 | 281.17 FPS | 640.41 FPS | 540.00 | 0 |
| 46 机王牌截击支援 | 371.26 FPS | 662.89 FPS | 600.00 | 0 |

两组历史记录均为相同 Godot 4.7.2、15 秒 Visual 和相同实体数，但各只有一个旧样本。它们是明显正向信号，不足以把 +127.8% / +78.6% 的幅度完全归因于本轮某一个重构。

测试过程中曾观察到外部 120 FPS 上限间歇启用；所有被限速样本均排除出性能 A/B，只保留作 60 FPS 门槛证据。

## 6. 生命周期、闪退与残留警告

- `lifecycle_gauntlet`：82/82。武器致死、战区 success/failure/cancel、任务目标释放、驻军撤离、阵营转换、BOSS 终态和飞机坠毁均跨过消费者下一缓存帧。
- 全量 `all`：退出码 0，自动运行时错误门未发现 `SCRIPT ERROR`、freed-object、非法 call/access/type 或原生崩溃。
- 所有本轮 focused、Visual 和压力进程均退出 0；无超时、退出码 86、`signal 11` 或 crash。
- 仍有 Godot 退出期 `ObjectDB` / Resource still in use 警告；地图 Visual 另有 1 个 `CanvasItem` RID 警告。它们没有转化为跨帧非法访问或闪退，按项目约定与断言结果分开记录，后续可单独清理。
- Wacom、shader cache 和系统根证书错误属于 Shadow 本机环境噪声。

## 代表性性能证据

- `bench/results/battlefield_atmosphere_stress_36_20260828_000938.txt`、`001018.txt`、`001059.txt`
- `bench/results/battlefield_atmosphere_stress_48_24km_20260828_001151.txt`、`001235.txt`、`001316.txt`
- `bench/results/naval_zone_stress_20260828_001356.txt`、`001437.txt`、`001517.txt`
- `bench/results/zone_support_stress_20260828_003919.txt`、`003946.txt`、`004012.txt`
- `bench/results/ace_support_stress_20260828_004038.txt`、`004103.txt`、`004130.txt`
