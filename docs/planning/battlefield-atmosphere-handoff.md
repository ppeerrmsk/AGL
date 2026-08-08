# 战场气氛实验跨电脑交接

> 更新时间：2026-08-08
> 当前规格：[`battlefield-atmosphere-experiment.md`](../specs/systems/battlefield-atmosphere-experiment.md) v4
> 实现状态：Debug 实验可用，自动验证通过；尚需在 Godot 编辑器内由人眼完成最终画面验收。
> 设计调查：[`battlefield-atmosphere-combined-arms.md`](battlefield-atmosphere-combined-arms.md) 仅作历史背景，不再作为数值依据。

## 1. 当前结论

本轮已经在真实 `survivor_mode` 中做出三个彼此独立的 F5 气氛样本，而不是复活废弃的旧沙盒：

- **空战**：ALLY F-86 ×3 对 HOSTILE MiG-23 ×3；双方各有一架轰炸机和两架 AH-64。AH-64 完全复用现有 `apache` 轮廓、旋翼物理和 M230，不创建新模型；实验副本禁用火箭。
- **炮战**：双方各 3 门自行榴弹炮，沿解析式椭圆轨道以 3 m/s 运动并低频互射。轨迹不存在 waypoint 过冲、端点急转或长期累计漂移。
- **海战**：双方各一艘 DDG + FFG，沿平行航路运动；以原有 3.0–3.8 秒频度发射 1.8 伤害舰炮。舰炮锁定同场敌舰后必然命中，不再用故意打偏模拟低烈度；无鱼雷系统。飞行弹体是沿航向的细长短曳光，不绘制圆球。

AI 对 AI 的常规武器使用独立参数副本并缩放为正式值的 10%；玩家参数完全不改，所以玩家介入仍能明显改变战局。实验演员不提供 XP、击杀档案或 Token。

## 2. 如何肉眼验收

1. 用 Godot 4.7+ 打开项目并进入一局生存模式。
2. 按 `F5` 打开 Debug 刷怪面板；面板打开时游戏不会暂停。
3. 在“战场气氛实验”区域分别点击 `空战`、`炮战`、`海战`。
4. 每次启动都会先清除上一种样本；点击 `清除` 可只移除本次实验演员。
5. 重点观察：Apache 是否显示为直升机、火炮转弯是否连续、海战是否每发都产生可信命中、舰炮弹是否是细长高速曳光而非光球。

如果某个入口报告附近没有连续陆地或水域，先移动玩家到合适地形再启动；代码会拒绝把陆军刷进水里或把舰队刷到陆地上。

## 3. 当前权威数值

| 域 | 编成与移动 | 武器节奏 | 生存性约束 |
|---|---|---|---|
| 空战 | 3v3 固定翼；双方 2 架 AH-64；B-1B/Tu-160 各一架 | 实验机常规武器伤害 ×0.10；AH-64 仅 M230、无火箭；轰炸专用炸弹保持 75 | 战略硬目标 900 HP，只接受敌对 `bomber_bomb` |
| 炮战 | 3v3；700×90 px 椭圆轨道；3 m/s | 4.5–5.5 s；飞行 2.2 s；伤害 6；半径 55 px | 每门 120 HP，目标只来自本次实验敌方炮兵 |
| 海战 | 1 DDG + 1 FFG 对同编成；2400 px 平行航路 | 3.0–3.8 s；飞行 1.6 s；伤害 1.8；锁定后必然命中 | 正式防空系统设为永久 `PASSIVE`；无鱼雷、制导或近炸扫描 |

共同作用域：集中控制器以 2 Hz 做失效清理和目标改派；只允许相同 `ambient_engagement_id` 的敌对实验演员互相交战。正式 TGT、BOSS、玩家、正式僚机和战区支援都不进入自动选敌池。

## 4. 实现文件

### 本功能新文件

| 文件 | 作用 |
|---|---|
| `scripts/survivor/battlefield_atmosphere_experiment.gd` | 三种样本的生成、2 Hz 火控、弹道绘制、目标隔离与清理 |
| `scripts/survivor/atmosphere_artillery_unit.gd` | 火炮外观和解析式椭圆移动 |
| `docs/specs/systems/battlefield-atmosphere-experiment.md` | 当前数值与行为的 SSOT |
| `docs/planning/battlefield-atmosphere-combined-arms.md` | 早期设计调查；其中旧鱼雷/低命中建议已经过时 |
| `docs/planning/battlefield-atmosphere-handoff.md` | 本交接文档 |

Godot 已为两个新 GDScript 生成对应 `.gd.uid`；跨电脑传输时也应一并带走。

### 接入过的现有文件

| 文件 | 接入内容 |
|---|---|
| `scripts/survivor/survivor_debug_spawn.gd` | F5 的空战、炮战、海战、清除按钮和状态显示 |
| `scripts/survivor/survivor_mode.gd` | 三个专项 bench 场景入口 |
| `scripts/survivor/survivor_spawner.gd` | `no_kill_reward` 的正式收益隔离 |
| `scripts/aircraft_renderer.gd` | 实验使用既有 `apache` 绘制分支；不要另造 helicopter 模型 |
| `scripts/tests/test_bomber_rotor_airburst.gd` | 火炮轨道 10 分钟/36000 帧确定性回归 |
| `scripts/tests/test_boss_phase.gd` | 实验收益隔离相关回归 |
| `docs/specs/_INDEX.md` | spec 登记和当前摘要 |
| `docs/reference/script-index.md` | 脚本职责索引 |
| `docs/reference/code-index.md` | 功能入口索引 |

这些现有文件在当前工作树中可能同时包含别的任务改动，不能用整文件覆盖或回退。续作时应按函数和 diff 合并。

## 5. 已解决的具体问题

- **Apache 画成飞机**：实验曾写入不存在的 `helicopter` silhouette，渲染器回退成固定翼三角。现改为既有 `apache`，运行日志中的四架均为 `silhouette=apache`。
- **火箭占用**：只在实验的 AH-64 参数副本中将 `rocket=null`、弹量清零；共享 `resources/enemy_ah64.tres` 不变。
- **鱼雷无意义运算**：实验鱼雷数组、逐帧制导、近炸与绘制均已删除。
- **海战假赛感**：v3 的 30% 命中率已经废弃；v4 锁定后必然命中，低烈度只靠 1.8 伤害和 3.0–3.8 秒冷却实现。
- **炮弹像球**：飞行中的炮弹已改为顺飞行方向的 10–16 px 细长弹体、阴影和短亮芯，不再调用 `draw_circle` 绘制弹丸。
- **火炮轨道破绽**：弃用 waypoint 往返，位置直接由椭圆相位求值，车体朝向取轨道切线。

## 6. 当前验证证据

| 验证 | 结果 |
|---|---|
| `battlefield_atmosphere_naval`，30 秒，Godot 4.7.1，Shadow | 4 艘舰全部存活；34 发射，结束前落地 32 发，`NavalGunHit=32`、`NavalGunMiss=0`、`Torpedo=0`；0 击杀 |
| `bomber_rotor_airburst` | 27/27 通过；包含 10 分钟火炮椭圆轨道、连续位移、有限相位和切线朝向 |
| 空战专项样本 | 四条 `RotorConfig` 均为 `silhouette=apache rocket=false`；15 秒内 AH-64 只有 GUN 事件、无 ROCKET 事件 |
| 炮战专项样本 | 3v3 全部生成并出现 `ArtilleryImpact`；低伤害下未快速清场 |
| `boss_phase` | 31/31 通过（本轮此前运行） |
| 文档校验 | `verify_docs.ps1` 通过；`script-index.md` 的 68 个锚点通过 |

本机 headless 启动仍会输出 Windows 根证书读取失败，以及退出时 1 个 `CanvasItem` / 1 个 `ObjectDB` 的既有基线警告；本轮海战命中改动没有新增运行错误。最终弹体形状只能靠编辑器中的 Visual/F5 人眼验收，headless 日志无法证明美术可读性。

完整 `code-index.md` 锚点校验当前仍会被同一脏工作树中大量其它任务造成的旧行号阻断；本功能所在段的 `_refresh_assignments` 锚点已更新。不要把全表报错误记为本功能已全绿，也不要为本交接顺手重写其它任务的索引。

## 7. 新电脑上的复现命令

先确认使用 Godot 4.7+，并让本机 `bench/run.cmd` 能找到正确的 Godot；禁止换回 4.6.2。只通过 bench 包装器启动，默认使用 `Shadow` 隔离副本：

```powershell
bench\run.cmd battlefield_atmosphere 15 180 Shadow
bench\run.cmd battlefield_atmosphere_ground 12 180 Shadow
bench\run.cmd battlefield_atmosphere_naval 30 180 Shadow
bench\run.cmd bomber_rotor_airburst 5 180 Shadow
bench\run.cmd boss_phase 5 180 Shadow
powershell -ExecutionPolicy Bypass -File tools\verify_docs.ps1
& 'C:\Users\noelu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\verify_doc_anchors.py --doc docs/reference/script-index.md
```

Python 路径是当前电脑的备用运行时。新电脑若该文件不存在，先在终端确认可用的 `python`，再运行同一脚本。

全新 checkout、完全没有 `.godot` class-name 缓存时，本机用当前基线版 `bench/run.cmd` 连续两次启动都会在 180 秒后被包装器回收，并报告 `Aircraft`、`CombatUnit`、`Presentation` 等全项目基础类型未注册；没有进入气氛实验代码。新电脑应先用 Godot 4.7+ 编辑器打开项目并等待首次导入完成，再运行 headless bench。不要把这组全局基础类型错误误判为气氛控制器的解析错误。

关键日志词：`ATMOSPHERE RotorConfig`、`GroundLaunch`、`ArtilleryImpact`、`NavalLaunch`、`NavalGunHit`。v4 正常运行中不应出现 `NavalGunMiss` 或 `Torpedo`。

## 8. 交接风险与下一步

本功能文件由专用分支 `codex/battlefield-atmosphere-research` 追踪，可在新电脑上直接 fetch/checkout。原工作区仍有大量地图、DEADAIR、玩家资源等其它未提交修改，它们不属于本分支提交；不要为了整理本功能而整批回退或覆盖这些文件。

下一位开发者的建议顺序：

1. 先读 v4 spec 和本文，不按历史调查里的鱼雷/低命中方案回退。
2. 检查上述功能文件是否全部存在，再跑 5 秒行为回归和三个专项样本。
3. 在编辑器里逐项做 F5 人眼验收，尤其观察舰炮曳光是否太长/太亮、火炮轨道是否在镜头尺度下自然。
4. 只有视觉验收需要时，先改 spec 数值再同步代码；不要改共享 AH-64 资源来满足 Debug 实验。
5. 当前只批准 Debug 实验。是否接入正式战区随机事件，仍是后续独立决策，不能从本实验自动扩 scope。
