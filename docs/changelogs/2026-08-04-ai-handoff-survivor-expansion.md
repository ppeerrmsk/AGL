# 2026-08-04 AI 接手日志：生存模式扩池、战场系统与无头压测

> 用途：这是给后续 Codex / Claude 等代码代理恢复上下文的工程日志，不是玩家公告。
> 对应提交主题：`feat: expand survivor combat systems and headless coverage`。
> 本批规模：302 个文件，约 +18.7k / -1.7k 行；同时包含已完成机制、在制机制、SSOT 补档、测试和 bench 基建，**不能把整批等同于全部验收完成**。

## 0. 新会话阅读顺序

1. 先读根目录 `AGENTS.md`，尤其 Godot 4.7、spec-first、性能规则和 bench 并发隔离。
2. 改玩法前读 `docs/DESIGN_PHILOSOPHY.md`。
3. 用 `docs/specs/_INDEX.md` 判断目标 spec 的 status；数值与行为以 spec 为 SSOT。
4. 用 `docs/reference/script-index.md` / `code-index.md` 找入口，不要先通读大文件。
5. 涉及目标仲裁、玩家机引用、BOSS/事件生命周期时先查 `docs/architecture/known-seams.md`。
6. 本日志只解释本批的连接关系与验证状态；与 spec 冲突时以对应 spec 为准。

## 1. 本批建立或扩大的系统边界

### 1.1 常规敌机池数据化

- 权威设计：`docs/specs/systems/enemy-pool-expansion.md`，当前仍为 `in-progress`。
- 注册入口：`scripts/survivor/enemy_pool_registry.gd`，`EnemyPoolRegistry.ROWS` 维护机型、Tier、角色与原型。
- 三类互斥原型为 `Gladiator` / `Lancer` / `Schemer`；角色桶为 `dogfight` / `intercept` / `strike` / `ew` / `legacy_fodder`。
- `survivor_spawner.gd` 负责从注册表抽取、生成与 Token 计账；特殊事件资源和常规敌版资源必须继续隔离，禁止为了省资源直接复用玩家 `.tres` 后原地改参数。
- 新增了约 25 份敌机 spec 与对应敌版资源，包括 F-14/F-15 系、F-22/F-35、Gripen、Rafale、Su-34/Su-57、J-20、Harrier、Tornado、Typhoon、Viggen、Snowblind 等。
- 这些敌机 spec 目前均为 `in-progress`。代码/资源已落地不代表逐机 §5 验收、§7 锚点和 §8 变更记录已经全部收口。

### 1.2 目标仲裁与友方资产牵连

- 权威设计：`docs/specs/systems/friendly-asset-aggro.md`，状态 `done`。
- 核心对象：`scripts/survivor/friendly_asset_aggro.gd` 的 `FriendlyAssetAggro`。
- 友方机场/航母/保护目标通过 group id 和 `CombatUnit.META_FRIENDLY_ASSET_*` 元数据登记；入口是 `register_airfield`、`register_carrier`、`register_target`。
- 玩家进入资产半径后，系统按固定 tick 把部分敌军目标来源切到友方资产；离开后有 grace period，再归还常规目标仲裁。
- 后续新增资产必须走登记入口，不能直接给敌机写 `combat_target`；BOSS、王牌和强制事件目标的优先级保护必须保留。
- 相关耦合文件：`ai/objective_context.gd`、`ai/target_selection.gd`、`ai_controller.gd`、`survivor_mode.gd`、`zone_mission.gd`、海军单位与挂点。

### 1.3 多目标导弹、特殊敌机与王牌

- `scripts/survivor/f22_multilock.gd`：F-22 独立多锁控制器，0.20 秒逻辑 tick、0.15 秒发射间隔、单机最多 4 锁，执行后进入脱离阶段。
- `scripts/survivor/schemer_multilock.gd`：Schemer 原型的多目标队列与脱离控制。
- `scripts/survivor/snowblind_controller.gd` + `snowblind_shroud_visual.gd`：Snowblind 电子遮蔽/揭示与视觉；进入半径、退出滞后和最短揭示时间由控制器常量统一维护。
- `scripts/events/ace_reinforcement_event.gd`、`ace_squad*.gd`、`ace_support_squad.gd`、`f47_ace_squad.gd` 扩展王牌轮换、第二波和友军支援。
- 新增 WhiteTea/F-CK-1、Snowblind 等 spec；其中 `multi-target-missile-locks.md` 为 `done`，敌机和王牌个体 spec 多数仍为 `in-progress`。

### 1.4 战区、地面/海上和轰炸任务

- `scripts/survivor/bomber_mission.gd`：阵营对称轰炸任务状态机；管理航路、投弹窗口、5 发序列、落点和撤离。spec `bomber-strike-missions.md` 仍为 `in-progress`。
- `scripts/strategic_target.gd` + `scenes/strategic_target.tscn`：战略硬目标骨架。spec `strategic-hardened-targets.md` 仍为 `in-progress`。
- `scripts/airburst_aa_unit.gd` + 对应场景/资源：空爆高射炮，独立索敌、炮塔对准、三连发与空爆弹。spec `airburst-aa-gun.md` 仍为 `in-progress`。
- `zone_mission.gd` 扩展友军空中支援和海上摆位硬闸；`zone-air-support-naval-safety.md` 为 `done`，后续不得绕过水域合法性检查直接生成舰队。
- AH-64/CH-47 的平移、环绕、悬停与武器行为已扩展，但 `rotorcraft-combat.md` 仍为 `in-progress`。
- 机场 SAM 网络、战场视觉尺度、首局教程等 spec 已创建但仍在制。

### 1.5 成长、签名技能与局外系统

- `aircraft-signature-progression.md` 为 `done`：机体专属技能进入升级第四槽；每机每局一次；需功勋商店购买对应许可；商店按战术学说/机体专属/战场支援/机体与后勤分类。
- `classified-card-pity.md`、`boss-clear-progression.md`、`close-range-lock.md` 为 `done`。
- 主要代码入口：`survivor_data.gd`、`survivor_player.gd`、`survivor_mode.gd`、`survivor_upgrade_ui.gd`、`evolution_*`、`meta_shop*.gd`、`career_archive.gd`。
- 新增/修改玩家可见文本已经同步 `i18n/translations.csv` 及中英日 `.translation`；继续新增 UI 文本必须走 `tr(KEY)`。
- 机动性类升级仍必须遵循根 `AGENTS.md` 的 accessor 注入约束，不要在物理 tick 或 `Situation.from_aircraft` 重复散点乘数。

## 2. 本批已完成与仍在制的 spec

### 2.1 新增且已标记 `done`

- `docs/specs/skills/close-range-lock.md`
- `docs/specs/systems/aircraft-signature-progression.md`
- `docs/specs/systems/boss-clear-progression.md`
- `docs/specs/systems/classified-card-pity.md`
- `docs/specs/systems/friendly-asset-aggro.md`
- `docs/specs/systems/multi-target-missile-locks.md`
- `docs/specs/systems/zone-air-support-naval-safety.md`

### 2.2 新增但仍为 `in-progress`

- 全部本批新增敌机个体 spec，包括 Snowblind。
- `ace-whitetea-fck1`、`ace-rotation-balance`。
- `airfield-sam-network`、`battlefield-visual-scale`、`bomber-strike-missions`、`enemy-pool-expansion`、`first-run-tutorial`、`rotorcraft-combat`、`squad-xp-threat-balance`、`strategic-hardened-targets`、`waypoint-fire-control`、`airburst-aa-gun`。
- 后续代理不要批量把这些改成 `done`；必须逐份跑 §5 验收、补 §7 锚点和 §8 记录。

## 3. 无头测试基建：以后必须这样跑

- 只允许 `bench/run.cmd` / `bench/run.sh`；禁止直接执行 Godot。
- 默认第四参数为 `Shadow`：把已保存的运行时项目镜像到系统临时目录，复制但不共享 `.godot` 缓存，允许原工作区 Godot editor 保持打开。
- 编辑器未保存的改动不会进入 Shadow；需要精确原地复现时用第四参数 `InPlace`，但检测到任何 Godot 进程会拒绝运行。
- 启动器入口：`bench/invoke_godot.ps1`。它负责项目锁、owner PID、墙钟超时、进程树回收、Job Object 和结果回收。
- 生存压力场统一把玩家放在地图中心。原因：旧出生点靠南边界，惯性越界会打开 `BoundaryUI` 并合法硬暂停，无头环境无人点击，看起来像引擎卡死。
- `survivor_mode.gd` 的 `_bench_wall_watchdog` 在 bench 中保持 `PROCESS_MODE_ALWAYS`；非预期 `SceneTree.paused`、升级暂停卡死或提前 Game Over 都会写状态并非零退出。
- `survivor_death` 场景依次验证长机阵亡、僚机接管、全队覆灭和 Game Over。

常用命令：

```bat
bench\run.cmd stress_swarm 60 180 Shadow
bench\run.cmd enemy_pool_stress 60 160 Shadow
bench\run.cmd zone_support_stress 45 150 Shadow
bench\run.cmd ace_support_stress 45 150 Shadow
bench\run.cmd boss_mother_goose 90 220 Shadow
bench\run.cmd survivor_death 10 60 Shadow
```

## 4. 2026-08-03 实际验证证据

- `stress_40` 60 秒：32 架存活，末秒 145 engine frames，无崩溃。
- `stress_swarm` 60 秒：78 个战斗对象、33 架飞机、2 杀，末秒 127 frames，无崩溃。
- `enemy_pool_stress` 60 秒：26 架、覆盖 7 类扩池敌机及多种技能组合，无崩溃。
- `zone_support_stress` 45 秒：49 架、10 架支援机，末秒 145 frames。
- `ace_support_stress` 45 秒：46 架，末秒 145 frames。
- `boss_mother_goose` 90 秒：18 杀，Boss 余 74.2%，末秒 137 frames。
- `survivor_death`：接管与 Game Over 终局通过。
- 未观察到 `signal 11` 或 Godot 原生闪退。
- 压力热点：Mother Goose 场 `trail_draw` 约 2.94 ms/frame；混战 `bullet_phys` 约 1.39 ms/frame。新增高实体视觉/子节点前仍须先读性能守则。
- `tools/verify_player_ref_holders.py` 通过：识别 27 个接收方，漏登记 0。
- `git diff --check` 通过。

bench 结果文件在 `bench/results/`，由 gitignore 排除，因此不在提交中；上述数字是本日志保留的历史证据。

## 5. 已知未收口项：后续 AI 不得误报全绿

1. `bench/run.cmd all 1 600 Shadow` 当时运行了 55 组，出现 29 个断言失败。多数来自当前 shell SID 与仓库拥有者不同导致的 `user://` 生涯/商店/档案隔离；`boss_phase` 的“XP 封锁不吞击杀内战斗语义”可能是真回归，需要单独复现。运行时压力场通过不等于单测全绿。
2. `tools/verify_doc_anchors.py` 全量报告 223 个腐烂锚点，主要来自本批/同期大重构造成的行号漂移。不要一边做无关功能一边顺手批量改；应开专门索引修复任务，用符号名重新锚定后全量复跑。
3. Godot 立即退出时偶见少量 `CanvasItem` / `ObjectDB` / Resource 泄漏警告。当前未造成压力场崩溃，但生命周期清理仍需追踪。
4. 多份新 spec 为 `in-progress`，尤其敌机扩池、旋翼机、轰炸、空爆炮、战略目标和教程。实现存在不代表 SSOT 闭环。
5. 性能结果来自 headless Steam Godot 4.7.1；不能直接当成导出包玩家机器 FPS，但可用于同机回归比较。

## 6. 提交前后的仓库状态说明

- 本批包含代码、资源、场景、spec、索引、i18n、测试与 bench 启动器，提交主题为 `feat: expand survivor combat systems and headless coverage`。
- 根目录曾出现 `aemeath-validation-v1.json`，它是 AGL 无关的宠物 spritesheet 失败校验输出，已明确排除在提交之外；后续不要把它当项目资产加入。
- 推送目标预期为 GitHub `origin/main`，但在本日志写入时仍仅为本地提交，需用户明确授权大载荷推送后执行。
