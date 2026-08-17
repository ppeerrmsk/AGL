---
id: hypersonic-splitter
kind: boss
status: done
schema_version: 1
spec_version: 8
owner: 用户
depends_on: [systems/boss-hunter-doctrine, systems/ui-transition, systems/ui-design-guidelines, systems/multi-target-missile-locks]
reconstruction_complete: true
---

# Black Star / Hyper-A（高超音速分裂体）

> 代号 **Black Star**、机体型号 **Hyper-A**。两架根机先后从超高空俯冲轰炸入场；每架都以自身粉身碎骨为代价完成三次火箭分段式二分。它本质上仍是速度极快的战斗机，高超音速只用于有预警的登场、再入和冲刺。

> **v8 已实现。** 此前仍待定的数值在 v7 收敛为首版可调参数；v8 已按该基线接入正式 BOSS 轮换、演出、Debug 与验证链。它们是可玩的首版参数，不代表以后禁止平衡调整。

## 1. 设计意图（Why）

- 登场先给信息、后给伤害：身份横幅结束后，BOSS 状态栏先显示 `30,000m`，危险圆与高度同时倒数约 4 秒，随后才结算落点爆炸。
- 常态是遵守飞机物理包线的顶级高速战斗机；高超音速位移是稀有、清晰、有界的特殊行为。
- 单体威胁随代际下降，目标管理压力随 `1 → 2 → 4 → 8` 上升；每一代都改变武器和招式，不只是缩血量。
- G0–G2 每次冲刺后必须主动靠近当前操控机散热，以标准 `SLOW` 给玩家真实攻击窗口。
- 父体死亡必须表现为粉碎与分段；两个子体从父体碎裂点分离，不得像凭空召唤复制品。
- 最坏 16 个 G3 同场时仍以读线、走位、目标管理为核心，禁止全员同时冲刺或制造无界特效。
- 现实视觉只参考 NASA X-43A 的低矮升力体、黑色热防护主体与浅色边缘，不使用 X-43A、Hyper-X 或 NASA 作为游戏内名称 / 商标。

## 2. 数据定义（What）

### 2.1 身份、拓扑与奖励

| 字段 | 确定值 |
|---|---|
| Registry id | `BLACK_STAR` |
| BOSS 代号 / 机体型号 | `Black Star` / `Hyper-A` |
| 状态栏标题 | `BLACK STAR // HYPER-A` |
| 根机 | 两架；`Hyper-A1`、`Hyper-A2` |
| 分支命名 | 子体在父路径后追加 `.1` / `.2`，如 `Hyper-A1.1`、`Hyper-A1.1.2` |
| 每棵树 | `1 × G0 → 2 × G1 → 4 × G2 → 8 × G3` |
| 全场节点 | `2 × (1 + 2 + 4 + 8) = 30`；终末体 `16 × G3` |
| 节点 / 最终胜利 XP | 全部 `0` |
| 首版其它奖励 | 不新增 BOSS 专属奖励；沿用既有通关 / 功勋 / 档案结算 |

唯一胜利条件：两架根机均已完成登场，存活节点为 0，待生成子代为 0，待登场根机为 0，且两棵树均完整结算。第一棵树提前清空、父体粉碎等待子体、第二根机尚未入场时均不得提前胜利。

### 2.2 四代机体参数

| 参数 | G0 | G1 | G2 | G3 |
|---|---:|---:|---:|---:|
| HP | `800` | `300` | `100` | `70` |
| 长 × 宽视觉尺寸 | `96m × 60m` | `80m × 50m` | `36m × 22m` | `10m × 6m` |
| 常态最大 / 巡航速度 | `2200 / 1600 km/h` | `2000 / 1450 km/h` | `1800 / 1250 km/h` | `1400 / 950 km/h` |
| 失速速度 | `230 km/h` | `220 km/h` | `200 km/h` | `150 km/h` |
| 最大持续 / 结构 G | `10 / 13` | `9.5 / 12.5` | `9 / 12` | `8.5 / 11` |
| 滚转率 | `3.0 rad/s` | `3.4 rad/s` | `4.0 rad/s` | `5.2 rad/s` |
| 最大爬升率 | `250 m/s` | `250 m/s` | `230 m/s` | `180 m/s` |
| flare | `0` | `0` | `0` | `0` |
| 导弹锁容量 | `8` | `4` | `2` | `1` |
| 高超音速冲刺 | 有 | 有 | 有 | 无 |
| 冲刺双侧火箭 | 有 | 有 | 无 | 无 |
| 高空再入轰炸 | 仅首次根机登场 | 有 | 有 | 无 |
| 枪械 | 忠诚僚机式点射激光 | 无 | 无 | 常规机炮 |

- G1 的长度按一般 `20m` 级战斗机约四倍确定；G0 再大一档，G3 回到小型无人机量级。
- 普通转弯、加减速、失速、G 限制和导弹 / 枪械交战均走共享飞机物理与 AI，不因 BOSS 身份暗加瞬转。
- 四代均无 flare，不通过规避弹药抵消分裂阶段的目标管理压力。

### 2.3 导弹与枪械

| 参数 | 值 |
|---|---:|
| 四代导弹弹匣 / 装填 | `4` 发 / `20s` 自动装填 |
| 单轮冷却 / 伤害 | `1.5s` / `90` |
| 最大速度 / 过载 | `1600 m/s` / `40G` |
| 射程 / 最小射程 | 后向 `20,000m`、前向倍率 `4.5` / `400m` |
| 全场在途总上限 | 不另设 BOSS 专属硬上限；仍遵守一机对同一目标的共享有效弹约束 |

实际齐射数为 `min(代际锁容量, 合法不同目标数, 当前弹匣余量)`。因此 G0 能维护 8 个不同目标锁，但满弹匣一轮最多实际发 4 枚。Hyper-A 标记为饱和攻击者，不受队友预计伤害的全局“够杀了”抑制，但不会在同一轮向同一目标重复分配。

- G0 点射激光复用忠诚僚机脉冲炮：`20` 伤害、`60 rpm`、`1800 m/s`、`1400m` 射程。
- G3 机炮：`13.5` 伤害、`3000 rpm`、`1200 m/s`、`1350m` 射程、`520` 发弹匣，`20s` 装填。

### 2.4 双根登场与高空再入

| 参数 | 根机登场 | G1 再入 | G2 再入 |
|---|---:|---:|---:|
| 状态栏 / AOE 预警 | `4.0s` | `4.0s` | `4.0s` |
| 高度读数 | `30,000m → 5,500m` | `30,000m → 5,500m` | `30,000m → 5,500m` |
| AOE 半径 | `1200m` | `900m` | `700m` |
| AOE 伤害 | `60` | `50` | `40` |
| 爆炸落点 | 招式开始时锁存当前操控机位置 | 同左 | 同左 |

- 第一根机在身份演出完成后立即进入 4 秒倒数；第二根机在第一根机落地后 `18s` 独立开始倒数，不依赖第一棵树 HP / 代际 / 存活。
- 第二根机的战中登场不暂停、不慢放、不强切镜头；危险圆、状态栏高度和音效承担理解成本。
- 根机倒数与 G1 / G2 隐藏再入阶段均不可锁定、不可受伤；模型不可见。
- G1 / G2 每次落地后 `26s` 才可再次尝试高空轰炸；全场同时最多 `1` 个再入倒数。
- G1 / G2 的爬升阶段为 `2.5s`：达到 `15,000m` 前仍可见、可锁定、可受伤，达到后才隐藏并免伤，然后进入 4 秒落点倒数。
- AOE 圆、倒计时、状态栏高度与伤害半径共用同一份运行时快照。

### 2.5 高超音速冲刺、火箭与散热

| 参数 | G0 | G1 | G2 |
|---|---:|---:|---:|
| 首次可用延迟 / 循环冷却 | `9s / 12s` | `8s / 10s` | `7s / 9s` |
| 攻击线预警 / 冲刺时间 | `1.6s / 1.2s` | `1.6s / 1.2s` | `1.6s / 1.2s` |
| 冲刺长度 / 危险带全宽 | `3200px`（`6400m`）/ `140m` | 同左 | 同左 |
| 冲撞伤害 | `55`；同一冲刺对同一单位最多一次 | 同左 | 同左 |
| 冲刺后延迟 | `1.2s` | `1.2s` | `1.2s` |
| 散热接近距离 / 最长接近 | `700px / 5s` | 同左 | 同左 |
| 自我 `SLOW` / 散热 | `5s` | `5s` | `5s` |

- 全场同时最多 `2` 条攻击线、`2` 架冲刺；第二根机登场 / 任意高空再入倒数优先，期间不再发起新冲刺。
- 选线以当前操控机或存活僚机位置为机会点，并把完整起终点、危险带和扫掠判定锁存为同一快照；预警完成后不追踪修正。
- 冲刺期间仍可锁定、受伤；只有超高空隐藏阶段免伤。
- G0 / G1 每次冲刺在约三分之一进度发射左右各 `5` 枚火箭。每侧优先选择冲刺航向对应侧的玩家 / 僚机位置；该侧无人时，在最近友方附近偏向该侧生成逼位落点。
- 火箭复用共享弹体：`24` 伤害、`420 m/s`、`2400m` 射程、无额外 AOE；10 发只生成一批，有界且不重复补射。
- 冲刺后主动靠近当前操控机到 `700px` 或最多追 `5s`，随后直接写入标准 `SLOW` 状态账本 `5s`，绕过未来外部减速免疫。
- 标准 `SLOW` 权威效果保持：目标速度上限 `350 km/h`、滚转 ×`0.6`、关闭加力。散热期正常锁定、正常受伤，不额外减伤。

### 2.6 分裂

- G0–G2 归零后等待 `0.65s` 分段演出，再在父体最后位置左右 `160px` 生成两个下一代子体。
- 子体继承父体根树与完整路径，朝向在父航向两侧各偏 `18°`；出生后 `0.8s` 免伤，防同一爆炸连锁清空。
- 待生成账本在父体死亡当帧增加，在两个子体均成功创建后原子核销。
- G3 死亡永久结算叶节点，不再生成。

## 3. 行为与公式（How）

### 3.1 Encounter 与单体状态机

```text
ROOT_PENDING → DESCENT_WARNING → IMPACT → ACTIVE_G0

on G0/G1/G2 defeated:
    live.erase(parent)
    pending_split += 1
    0.65s 后 spawn(path.1, path.2)
    pending_split -= 1

victory = roots_arrived == 2
       && pending_roots == 0
       && pending_split == 0
       && live_nodes == 0
       && terminal_g3_defeated == 16
```

```text
G0–G2:
FIGHTER_COMBAT → TELEGRAPH(1.6s) → HYPER_DASH(1.2s)
  → POST_DASH_DELAY(1.2s) → COOLDOWN_POSITIONING(≤5s)
  → COOLDOWN(SLOW 5s) → FIGHTER_COMBAT

G1/G2 另可由 FIGHTER_COMBAT：
CLIMB(2.5s；15km 前可攻击) → HIDDEN_DESCENT(4s；不可攻击)
  → IMPACT → FIGHTER_COMBAT

G3：GUN_DOGFIGHT；无冲刺、无火箭、无高空再入、无散热循环。
```

所有 Hyper-A 节点由单个 encounter 编排器更新；不为每架新增 `_process` / `_draw`。AI 的正常 BFM 与武器循环仍由共享 `AIController` / `Aircraft` 执行，特殊状态只在进入 / 退出时切换 AI 战斗许可。

### 3.2 状态栏

- 常规 BOSS 沿用原有 5 卡布局；Black Star 通过 `BossEncounter.get_hud_entries()` 提供紧凑树条目，HUD 自动切换到专用网格文本，不按 boss id 写 UI 分支。
- 每个活节点显示完整 `Hyper-A…` 路径、代际、HP；处于 `DESCENT / CLIMB / DASH / SLOW` 时追加状态和高度 / 秒数。
- 每次分裂在父卡片消失、两个子路径出现的同一次数据刷新中原子更新；最多 16 个条目，4 列排布。
- 连续高度倒数由 encounter 快照直读，不提高普通 HUD 全局刷新频率。

### 3.3 演出

- 初次登场走统一 `black_star_arrival`：系统入侵横幅 `0–1.5s`，其后才切空域 / 演员镜头；总长小于 `7s`。
- 序列结束前依次恢复舞台、回玩家镜头、解除暂停并释放演员；`sequence_finished` 后才进入 ENGAGED。
- ENGAGED 后亮状态栏并启动根机 4 秒真实高度倒数。身份演出不伪造落点倒计时。
- 第二根机与 G1 / G2 再入不重复全局身份横幅、不暂停战局；使用危险圆、下落高度、冲击环和有界爆炸闪光。
- 分裂使用一次碎裂冲击环与两股短分离迹，不为 30 个历史节点保留常驻粒子。

### 3.4 Debug 与验证入口

Boss Debug 的 Black Star 卡提供 `FULL ENCOUNTER`、`G0 FIGHTER`、`G1 REENTRY`、`G2 DASH`、`G3 DOGFIGHT`、`SECOND ROOT`、`COOLDOWN WINDOW`。场景选择通过 `boss_debug_scenario` meta 传给 encounter；F8 重开 / 重 roll 保留它。Debug 只改变起始状态，不伪造伤害、锁定、SLOW 或分裂的运行时语义。

## 4. 结构与组成（Structure）

- `HyperABoss extends BossEncounter`：双根时间闸、节点账本、分裂、特殊行为、胜利。
- 四份 `AircraftParams` + 一份 Hyper-A 导弹资源：物理、武器与视觉尺寸的 SSOT。
- `HyperAThreatOverlay`：只消费 encounter 锁存的 AOE / 攻击线 / 冲击快照；不拥有伤害。
- `BossEncounterEvent` / `SurvivorSpawner`：类型派发、统一身份演出与 BGM。
- `BossEncounter.get_hud_entries()` / `SurvivorHUD`：通用自定义 BOSS 树 HUD 协议。
- `BossDebugSelect` / `SurvivorMode`：Debug 场景选择与传递。
- `BossRegistry` / `sequences.json` / i18n：正式轮换、横幅、无线电和三语文本。

## 5. 验收标准（Acceptance）

- [x] 两架根机各严格三次二分，完整战斗固定 30 节点、16 个 G3；待登场 / 待分裂期间不提前胜利。
- [x] 四代 HP、体型、速度、G 限、flare、锁数、枪械与特殊行为严格匹配 §2。
- [x] 四代均使用 4 发导弹弹匣；G0 / G1 / G2 / G3 锁容量为 `8 / 4 / 2 / 1`，同轮只分配不同目标。
- [x] G0 点射激光；G0 / G1 冲刺左右各 5 发火箭；G2 冲刺无火箭；G3 机炮狗斗且无冲刺。
- [x] 第一 / 第二根机均有约 4 秒、`30,000m → 5,500m` 的状态栏倒数和同源 AOE 危险圆。
- [x] G1 / G2 爬升初段可攻击，超过 `15,000m` 后模型消失且不可锁定 / 受伤，再以 4 秒预警轰炸返回。
- [x] 一次冲刺对同一单位最多伤害一次；视觉线、实际路径和危险带同源。
- [x] G0–G2 每次冲刺后都靠近当前操控机并自施真实 `SLOW 5s`；玩家切控后目标刷新。
- [x] Black Star 树 HUD 每次分裂后原子更新完整层级名，16 个 G3 时不遮满屏幕。
- [x] 初次身份演出遵守统一横幅 / 镜头 / 时间令牌顺序；第二根机不夺走战中控制权。
- [x] 所有节点和最终胜利均为 `0 XP`；Debug 局不入档。
- [x] 七个 Black Star Debug 场景可直达，专项 Shadow bench 与 Visual 验收通过。
- [x] 16 个 G3 + Sentinel + Lv5+ 压测维持 60 FPS 红线；攻击线、火箭和分裂特效有硬上限。
- [x] 三语、spec 索引、enemy / script / code / resource 索引与文档校验全部通过。

### 5.1 验证证据

| 证据 | 结果 |
|---|---|
| `hyper_a` | `52/52`：Registry、四代资源、锁数 / 弹匣、Debug 七入口、fallback 无线电、拓扑与 arrival 契约 |
| `boss_hyper_a_lifecycle` | 真实节点按 `G0×1 → G1×2 → G2×4 → G3×8` 结算；终态 `active=NO`、`pending_splits=0`、`terminal_g3=8` |
| `boss_hyper_a` 30s | 双根完整时间线；终态 `generation_counts=[2,0,0,0]`，确认第二根按独立计时加入 |
| `boss_hyper_a_stress` 15s | `16 G3 + Sentinel/5`，23 个 Aircraft；采样 `93 FPS`、`hud_entries=16` |
| `presentation` / `boss_phase` / `boss_progression` | `230/230`、`33/33`、`38/38` |
| Visual | Black Star 横幅、Debug 四卡、4 秒再入高度 / AOE、16 G3 树 HUD 均完成 1920×1080 截图验收 |

## 6. 实现计划（Task Pipeline）

- [x] 阶段 0：v7 收敛设计与首版参数，状态改为 `approved`。
- [x] 阶段 1：资源、Registry、Encounter 双根 / 分裂 / 胜利骨架。
- [x] 阶段 2：高空登场、G1 / G2 再入、AOE 与状态栏。
- [x] 阶段 3：共享物理常态战斗、导弹、激光 / 机炮、冲刺 / 火箭 / 散热。
- [x] 阶段 4：统一登场 sequence、分裂 / 冲击表现、树 HUD、Debug 直达。
- [x] 阶段 5：专项 bench、Visual、索引与 Notion 回写；状态改为 `done`。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 主逻辑 | `scripts/survivor/hyper_a_boss.gd` |
| 危险区表现 | `scripts/survivor/hyper_a_threat_overlay.gd` |
| 参数资源 | `resources/enemy_hyper_a_g0.tres` 至 `enemy_hyper_a_g3.tres`、`resources/hyper_a_missile.tres` |
| 注册 / 事件 | `scripts/survivor/boss_registry.gd`、`scripts/events/boss_encounter_event.gd`、`scripts/survivor/survivor_spawner.gd` |
| HUD / Debug | `scripts/survivor/survivor_hud.gd`、`scripts/survivor/boss_debug_select.gd`、`scripts/survivor/survivor_mode.gd` |
| 演出 | `resources/presentation/sequences.json` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-10 | 1–2 | 建立高超音速冲刺与分裂概念；早期单根 31 节点方案。 |
| 2026-08-16 | 3–5 | 定名 Black Star / Hyper-A；改为双根各三次二分；确认 HP、代际冲刺 / 火箭 / 机炮与 0 XP。 |
| 2026-08-17 | 6 | 确认 G0 / G1 的 8 / 4 锁与冲刺后自我标准 `SLOW`。 |
| 2026-08-17 | 7 | 吸收 Notion 最新补充：G0 点射激光，G1 / G2 爬升消失后再入轰炸，四代导弹 4 发装填且不设 BOSS 专属在途总上限，G1 为普通战斗机约四倍，G1–G3 无 flare，分裂树 HUD 层级名与 X-43A 视觉语汇。用户要求开始执行，因而收敛全部首版参数并改为 `approved` / 可重建。 |
| 2026-08-17 | 8 | 完成正式实现：双根 / 分裂 / 胜利账本、四代共享飞机、再入 / AOE / 冲刺 / 火箭 / 散热、层级 HUD、统一 arrival、七个 Debug 入口；专项、生命周期、压力与 Visual 证据通过，状态改为 `done`。 |
