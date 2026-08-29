# BOSS 系统重构计划

> 状态：approved（2026-08-28 用户要求纳入总重构流程）
> 范围：既有行为等价重构；覆盖 BOSS 战流程、BOSS 行为、隐形/可见性和 BOSS 公共生命周期。
> 不做：不调整 BOSS 数值、招式、通关强化、登场演出、轮换概率、奖励或胜负条件。

## 目标

把当前 BOSS 系统拆成四条明确边界：

1. **遭遇流程**：选择 → spawn → PRE_STAGE → arrival → ENGAGED → VICTORY → cleanup；
2. **行为控制**：每个 BOSS 自己的战术、代际、阶段、技能和挂点规则；
3. **隐形与可见性**：传感器失联、光学 cloak、演出隐藏三种不同语义分别有唯一所有者；
4. **公共 BOSS 契约**：身份、演员、HUD、音乐、玩家引用、终态和 Debug 入口。

重构后的日常目标是：增加或修理一个 BOSS 时，只修改该 BOSS 的行为模块和注册数据，不再给事件流程、HUD、雷达、演出和 spawner 同时增加按 boss id/type 分支。

## 当前权威与保留项

- `BossRegistry` 已是身份、构造器、地图池、轮换和横幅元数据真源；保留数据驱动结构，UI 禁止按 boss id 分支。
- `BossEncounter` 已提供 `spawn/update/engage/is_defeated/set_player_ref/get_display_members/get_hud_entries` 公共接口；以它为兼容壳演进，不另建平行基类。
- `BattlefieldFlow.is_boss_phase()` 已是战场规则总闸；BOSS 重构不得复制第二套阶段时钟。
- `SensorStealthController` 已是低频传感器失联真源；普通隐身、反隐和玩家观察者批清理继续集中在此。
- `Presentation` / `CinematicCast` 继续拥有镜头、舞台、演员演出冻结与演出隐藏；不把演出状态写成战斗 cloak。
- Wraith、Poltergeist、Mother Goose、Black Star 的独特机制与设计身份全部保留。

## 当前结构问题

### R1 · 事件流程仍按具体 BOSS 类型分派

`BossEncounterEvent` 同时负责注册表选择、通关次数注入、四类 spawn 分支、PRE_STAGE directive、arrival、音乐、HUD、玩家引用保鲜、BOSS 圈同步和胜利。Black Star 的根机下降、无线电与玩家演出隐藏又直接进入通用事件。

后果：新增 BOSS 即使已经实现 `BossEncounter`，仍必须修改事件脚本；通用流程和单体例外互相影响。

### R2 · 公共生命周期主要靠轮询字段

事件通过 `encounter.active true→false` 检测胜利，演员/HUD 更新依赖 `get_display_members()` 每次重查。`active/hud_visible` 是公共字段，但 spawn、engage、defeat、cleanup 的合法迁移没有统一入口和幂等合同。

后果：复合 BOSS 的延迟子体、第二阶段、提前胜利保护和场景退出清理需要各自防御。

### R3 · 光学 cloak、传感器隐形、演出隐藏语义相邻但所有权不够醒目

- `sensor_hidden`：战斗传感器失联，由 `SensorStealthController` 结算；
- Wraith `CLOAK`：队级光学/战术状态，当前混在 773 行 `AceSquad`；
- `META_PRESENTATION_FORCE_HIDDEN_VISUAL`：只隐藏 CanvasItem，不改变锁定/伤害。

三者必须保持分离，但调用方容易通过 `visible/is_cloaked/sensor_hidden` 任一字段猜整体状态。跨帧批清理又处在 freed-object 高风险路径。

### R4 · 个别 BOSS 类仍承担过多职责

- `AceSquad`：spawn、角色、边界、战术、cloak、成员账本和终态；
- `HyperABoss`：双根拓扑、代际生命期、再入、冲刺、火箭、AOE、武器许可、HUD 和 overlay 快照；
- `MotherGooseBoss` 与 `MotherGooseController` 通过反向引用共同拥有挂点、伤害路由、蜂群、JAM、VLS 和指定猎杀。

这些都不是要改机制，而是需要把“账本 / 决策 / 执行 / 表现快照”拆开。

## 目标模块边界

### `BossEncounterEvent`：只编排遭遇

- 选择并配置 encounter；
- 驱动 `PRE_STAGE → ENGAGED → VICTORY`；
- 把 arrival、HUD、BGM、mode 回调接到公共 encounter 信号/接口；
- 不判断 `CarrierStrikeGroup/AceSquad/MotherGoose/HyperA` 具体类型；
- 不持有某个 BOSS 的根机、代际或 cloak 状态。

### `BossEncounter`：稳定公共协议

逐步补齐幂等语义入口，而不是扩大字段直写：

- `configure_progression()`；
- `spawn()`；
- `prepare_pre_stage(owner)`；
- `engage()`；
- `shutdown(reason)`；
- `get_display_members()` / `get_hud_entries()`；
- `set_player_ref()`；
- 公共信号：演员变化、HUD 变化、defeated、特殊 arrival cue。

迁移期保留 `active/hud_visible` 兼容读，最终只允许上述入口修改。

### `BossRegistry`：身份与能力声明

在现有 `BOSS_DEFS` 上增加可静态审计的能力元数据，例如 arrival id、是否复合体、是否提供定制 arrival cue；元数据只描述能力，不存运行时状态，不把行为重新塞回 Dictionary。

### 行为模块：每个 BOSS 自己组合

- Wraith：`AceSquad` 只管成员/状态路由；`WraithTactics` 管战术；新增 cloak 状态组件管进入、退出、CD、近距打断与成员可见性提交。
- CSG：战斗群账本与 Phase 2 生成从事件完全隔离，舰船/Poltergeist 仍由 encounter 管。
- Mother Goose：frame/mount/weak-point 账本、JAM、蜂群、VLS、designation 分别维持独立模块；删除 controller 对 encounter 具体字段的随意访问，改为窄接口。
- Black Star：拆为代际树账本、单体状态执行器、武器/伤害策略和表现快照；`HyperABoss` 保留 orchestration 壳，不给 30 个节点各挂 process。

### 隐形边界

三条状态禁止合并成一个万能 `is_hidden` 写入口：

1. `SensorStealthController`：是否可被传感器持续交战；
2. BOSS cloak component：是否处在特定 BOSS 招式、成员 alpha/尾迹如何过渡；
3. `Presentation/CinematicCast`：是否仅因演出隐藏视觉。

允许新增无状态查询 `BossVisibilityPolicy` 汇总“某消费者该看什么”，但它只能读状态，不能成为第四个状态所有者。物理命中仍与传感器可见性分离。

## 分阶段实施

### Phase 0 · 重构前安全网与可观察性

- 固化 `boss_phase`、`boss_progression`、`boss_hunter`、`sensor_stealth`、`cmd_cloak`、`hyper_a`、`presentation`。
- Visual：`sensor_stealth_visual`、`boss_arrival_banner_visual`、Black Star 专项画面。
- 性能：Wraith、CSG、Mother Goose、Black Star 各自最坏态；不得用 C1 替代专属成本形状。
- 生命周期：真实 defeat、复合体延迟子代、玩家切控、目标先释放、arrival 被覆盖和场景退出。

### Phase 1 · 遭遇流程去类型分支

- 给 `BossEncounter` 增加最小 `prepare_pre_stage()` 和 arrival cue 协议。
- 四类 `_spawn_*` 合并为通用 spawn 路由；猎手入场几何由 Ace encounter 自己声明/消费。
- Black Star 根机 cue 通过公共信号上送，事件不再 `is HyperABoss`。
- `BossEncounterEvent` 只保留通用 phase 与导演桥接。

验收：四 BOSS arrival → ENGAGED → VICTORY；缺序列/覆盖序列 fail-open；`boss_phase`、`presentation`、`lifecycle_gauntlet`。

### Phase 2 · 公共生命周期收口

- 增加幂等 `mark_defeated/shutdown` 或等价内部过渡；统一 signal。
- `active/hud_visible` 从外部可写字段收成兼容只读状态。
- 玩家引用一律通过 live provider/chokepoint 更新；跨帧缓存遵守 `Variant → TYPE_OBJECT → is_instance_valid`。
- 复合 BOSS 的“仍有 pending child/phase”成为公共 defeat contract，不由事件猜。

验收：玩家切控、长机死亡换帅、目标先释放、success/cleanup 后跨下一缓存 tick。

### Phase 3 · cloak 与隐形边界收口

- 从 `AceSquad` 提取 cloak 状态组件；Wraith 数值和触发条件保持不变。
- 所有锁定清理继续通过 `SensorStealthController` / AI 目标 API，不直写私有缓存。
- 演出隐藏只走 Presentation meta，禁止污染 `sensor_hidden/is_cloaked`。
- 增加状态组合矩阵：sensor stealth × optical cloak × presentation hidden × counter-stealth × commanded target。

验收：`sensor_stealth`、`cmd_cloak`、`boss_hunter`、Visual、freed-object 生命周期场。

### Phase 4 · 单体行为拆分

按风险从低到高逐个完成，不并行大改：

1. Wraith/Ace cloak；
2. Mother Goose 窄伤害/挂点接口；
3. CSG 阶段账本；
4. Black Star 代际树与单体执行器。

每个切片都要求行为等价、净减少跨模块字段写入，并保留独特机制。禁止抽出一个全知 `BossController` 上帝类。

### Phase 5 · 身份、Debug 与文档收口

- Registry、Boss Debug、HUD、横幅和 Chatter 只认公共身份协议；
- 新增 BOSS 的 playbook 变成“spec → registry → encounter → behavior modules → presentation → tests”；
- 更新 script/code/enemy index 与 known seams。

## 回归矩阵

### 所有阶段必跑

- focused：当前切片 + `boss_phase` + `boss_progression` + `presentation`；
- 隐形切片追加：`sensor_stealth` + `cmd_cloak` + `boss_hunter`；
- Black Star 切片追加：`hyper_a` 与相应真实场景；
- 终态：`lifecycle_gauntlet`，随后 `all`；
- 静态：player-ref holders、doc anchors、docs、diff check。

### 性能与 Visual

- Wraith：`boss_wraith_stress 15 180 Shadow Visual`；
- CSG：`boss_csg_stress 15 180 Shadow Visual`；
- Mother Goose：正式 `boss_mother_goose` 场景与蜂群/JAM/VLS 实况；
- Black Star：`boss_hyper_a_stress 15 180 Shadow Visual`，必要时追加 FINAL WAR ocean；
- 隐形：`sensor_stealth_visual`；
- 登场：`boss_arrival_banner_visual` 与真实 arrival 场。

验收必须同时检查平均/P1/worst/<60、实际 BOSS 编成、技能/阶段是否触发、camera/渲染覆盖以及 wrapper 错误门；空画面或未进入目标阶段的绿色退出无效。

## 完成线

- `BossEncounterEvent` 不再按四种具体 BOSS 类型分派；
- 新 BOSS 不需要修改通用流程、HUD、雷达或演出控制器；
- sensor stealth、optical cloak、presentation hidden 各只有一个写入所有者；
- 四个现有 BOSS 的机制、数值、演出、胜负和通关强化行为不变；
- focused、四类专属压力、Visual、lifecycle 与 `all` 全部通过；
- 索引与 known seams 对齐实际代码。

## Phase 0 基线快照（2026-08-28）

Focused：`boss_phase` 33/33、`boss_progression` 44/44、`boss_hunter` 127/127、
`sensor_stealth` 63/63、`cmd_cloak` 18/18、`hyper_a` 108/108、`presentation` 通过。

Visual：`sensor_stealth_visual` 验证中段 alpha=0.5、完全隐藏、反向恢复与幂等；
`boss_arrival_banner_visual` 完成通用、Wraith、CSG 和 Black Star 全部截图，人工检查通过。

15 秒 Shadow Visual 单样本：

| 场景 | 实际负载 | 平均 FPS | P1 FPS | worst FPS | <60 帧 |
| --- | --- | ---: | ---: | ---: | ---: |
| Wraith stress | 19 Aircraft / 7 missiles | 338.84 | 240.00 | 49.83 | 1 |
| CSG stress | 19 Aircraft / 12 Naval / 32 mounts / 455 bullets / 41 missiles | 124.09 | 72.00 | 58.62 | 1 |
| Mother Goose | 27 Aircraft / 9 mounts / 7 missiles | 159.40 | 85.80 | 54.24 | 1 |
| Black Star stress | 23 Aircraft / 6 missiles | 284.26 | 160.27 | 49.69 | 1 |

四场均正常结束、无运行时错误或闪退，但都各有一个未知归因的 17–20ms 尖峰。
按 60 FPS 硬红线，Phase 0 尚不能标为性能全绿；实施 Phase 1 前先用三轮同条件样本确认复现率，
若尖峰稳定存在则从 CSG 开始补更细 bucket/事件窗口并清除。

## Phase 0 性能修复与复测（2026-08-28）

CSG 的真实弹幕热路径已做行为等价优化：火箭近炸和弹体命中改用距离平方比较；
射手阵营、弹种、弹高、贯穿账本和射手类型等每弹不变量移出候选单位内循环。
`bullet_grid` 8/8、`weapon_hit` 6/6、`rocket_trajectory` 46/46、
`lifecycle_gauntlet` 82/82 与全量 `all` 86/86 均通过。

CSG 15 秒 Visual 三轮 A/B 中位数：

| 指标 | 修复前 | 修复后 | 变化 |
| --- | ---: | ---: | ---: |
| worst FPS | 72.09 | 81.11 | +12.5% |
| P1 FPS | 108.21 | 118.59 | +9.6% |
| `bullet_phys` | 697 us/f | 674 us/f | -3.3% |
| `<60` 帧（三轮） | 1 / 0 / 0 | 0 / 0 / 0 | 硬门全绿 |

代表性 36 单位混合战场复测三轮也全部为 0 个 `<60` 帧，worst FPS 为
60.69 / 83.70 / 60.74，8/8 镜头巡检完整。

其余 BOSS 的残余单帧红点必须和游戏侧预算分开解释：Wraith 与 Black Star 的慢帧
已知脚本工作仅约 4–5 ms，但屏外 Shadow Visual 窗口出现 11–15 ms 不可归因停顿；
Mother Goose 的同类停顿会触发 Godot 连跑两个固定物理 tick，形成 30 ms 追帧放大。
实体数、事件、canvas 压力均未在停顿前突增。不得通过放宽 60 FPS 阈值、删除 BOSS
表现或降低 BOSS 更新频率把这类环境调度异常伪装成通过；后续若要把专属门变为稳定
硬绿，应先让性能 Visual 使用可见、未被桌面合成器降频的正式渲染窗口再复测。
