# 三维显示 / 二维模拟：可行性实验

日期：2026-09-05。设计权威：[战斗实体立体质感原型](../specs/systems/combat-entity-volume-prototype.md)。本文件记录实验与未通过的边界，不建立第二份行为规范。

本页保留初版可行性及手动入口追加时的结果。用户随后已认可效果并批准并行制作，**当前首批飞机/地图资产及最新回归结果见 [批次 A 报告](volume-batch-a-results.md)**；本页的旧网格预算和旧 bench 结果不覆盖新批次。

## 结论边界

技术接线已跑通：共享正交 Camera3D、真实低模机体与 Mother Goose、真实阴影、建筑/道路/铁路几何；仍由原二维世界执行 AI、飞行、武器、伤害与 UI。正式游戏默认没有切换。

**性能裁决：未通过长时 60 FPS 门，不批准推广。** C1/C2 与 Mother Goose 的三轮 30 秒样本没有低于 60 的帧；延长到 120 秒后，同一三维地图上的新、旧机体均出现尖峰。不能用短测或平均约 119 FPS 覆盖这个失败，也不能据此断言三维飞机是根因。

这不是完整三维游戏、最终美术、全机型/BOSS 完成或低配性能承诺。三维地图只有样区内容；不能用这张简单地图与完整 PNG/瓦片地图的不同负载宣称“3D 更省”。完整地图地理/碰撞未迁移，天空高度、特殊姿态、多装备、旋翼/海陆单位和三维残骸仍待适配。

## 查看与复现

**亲自战斗**：在 Godot 编辑器打开 `scenes/tests/volume_3d_combat.tscn`，按 F6（运行当前场景，不是 F5）。默认 F-47 小队挑战 Mother Goose，登场演出结束后即可操作。左键点击下令/选择攻击目标，武器自动开火；滚轮缩放、空格跟随玩家、Tab 构筑、Esc 暂停、游戏内 F8 重开。沿用真实 Boss Debug 战斗，不计入生涯，不强制测试相机，也不会按 bench 时长自动退出。

**模型观察**：打开 `scenes/tests/volume_3d_lab.tscn`，按 F6。`1` 正俯视，`2` 斜视检查，`3` 阴影开关，`4` 地图样区，`B` 进入上述手动战斗。若观察场已在旧进程运行，先停止再运行新版。这个 lab 是模型观察，不是混战性能证据。

Agent / 自动验证只能通过 wrapper：

```powershell
bench\run.cmd volume_world 1 180 Shadow Headless
bench\run.cmd volume_3d_lab 1 180 Shadow Visual
bench\run.cmd volume_3d_combat 1 90 Shadow Visual
bench\run.cmd volume_2d_c1 30 180 Shadow Visual
bench\run.cmd volume_3d_c1 30 180 Shadow Visual
bench\run.cmd volume_2d_c2 30 180 Shadow Visual
bench\run.cmd volume_3d_c2 30 180 Shadow Visual
bench\run.cmd volume_2d_mother_goose 30 180 Shadow Visual
bench\run.cmd volume_3d_mother_goose 30 180 Shadow Visual
bench\run.cmd volume_2d_mother_goose 120 240 Shadow Visual
bench\run.cmd volume_3d_mother_goose 120 240 Shadow Visual
bench\run.cmd all 1 300 Shadow Headless
```

两组机体候选使用相同三维地图、相机、材质/光源配置和原有负载 fixture。C1/C2 保留标准 8 段巡航；Mother Goose 成对镜头共同跟随母机，缩放 1.2，避免本体在屏外却算通过。独立 lab 的观察光照不用于性能比较。

生成物在 `bench/results/`：`volume_3d_lab_top.png`、`volume_3d_lab_tilted.png`、`volume_3d_lab_map.png`；`volume_3d_mother_goose_view_0.png` 是真实 Survivor 战斗终帧。`mother_goose_technical_proxy.glb` 是可导入 Blender 的真实网格，不是 PNG，也不是已完成的 `.blend` 制作工程。GLB 原点归零，部件具名；单位遵循项目显示像素，不解释成现实米制。

性能窗口结束并写完结果后才采集战斗截图。首个开发试跑 `volume_3d_mother_goose_20260905_111202.txt` 曾在采样中额外读回/编码 PNG，记录 6 个低于 60 的帧，最慢 15.49 FPS；该旧试跑保留，不与后续正式成对采样混合，也不能将这些尖峰全部归咎于模型。其后的测量没有额外窗口内截图。

## 测试环境与覆盖

- Windows / Godot 4.7.2 Steam / OpenGL 3.3 GL Compatibility / RTX 3080，实际渲染结果为 `headless: false`。采样使用现有显示配置，不据接近 120 FPS 的平均值推算 GPU 余量。
- C1：36 名气氛编成、8 km，场内 25 架 Aircraft，加地面/舰船/挂点；C2：48 名、24 km，场内 33 架 Aircraft。标准 fixture 自身的基线无敌/气氛非致死规则未修改；因此另跑真实可伤害的 Mother Goose 样本，不拿气氛场代表完整自由混战验收。
- 三维源网格 5 族合计 1200 三角形，静态地图 17620 三角形，一个共享视图，5 个 MultiMesh 批次。不是一实体一视口。
- C1 新机体峰值 15 个，C2 峰值 17 个；其它单位/不可见状态保持旧显示，未为了通过减少战斗实体、火力或反馈。该覆盖**不支持“36/48 个单位全部三维化已通过”**。
- 实时中心投影误差在这些短采样中小于 0.001 像素；focused 比较铁路点与 `ArmoredTrainBoss.train_route()` 同源。它们证明显示坐标接线，不证明正式建筑碰撞或 PNG 铁路错位已修好。
- GPU 专项耗时、显存峰值、目标最低配置、冷启动/首次出现资源、全地图与完整局尚无完整证据；不填假零。

## C1 / C2：每种配置三轮，每轮 30 秒

每一行三轮均 `frames_below_60=0`，且 `camera_patrol=on segments=8/8`。平均和 P1 取三轮中位；最慢帧取三轮最差，不被中位数掩盖。

| 配置 | 平均 FPS 中位 | P1 FPS 中位 | 最慢帧 FPS | 低于 60 帧总数 |
|---|---:|---:|---:|---:|
| C1 同地图 + 旧机体 | 119.74 | 110.00 | 71.05 | 0 |
| C1 同地图 + 新机体 | 119.74 | 110.00 | 61.56 | 0 |
| C2 同地图 + 旧机体 | 119.81 | 111.29 | 68.24 | 0 |
| C2 同地图 + 新机体 | 119.78 | 110.00 | 73.43 | 0 |

C1 平均/P1 中位基本持平；C2 平均约下降 0.03%，P1 约下降 1.16%，在原 5% / 10% 相对回退预算内。但 C1 最慢帧接近底线，不能拿平均 120 FPS 承诺继续堆细节没有成本。

结果文件时间戳（均为 20260905；完整名为 `volume_<2d/3d>_<c1/c2>_20260905_<时间>.txt`）：

| 配置 | 三轮文件时间 |
|---|---|
| 2d_c1 | 111831 / 112104 / 112338 |
| 3d_c1 | 111909 / 112142 / 112416 |
| 2d_c2 | 111947 / 112221 / 112455 |
| 3d_c2 | 112025 / 112300 / 112533 |

## Mother Goose：近景真实战斗，三轮 × 30 秒

保留正式 20 友军 fixture、实际 UAV、导弹、伤害与部件。新路径每轮 Mother Goose 在视图中超过 3500 帧（含预热）；不是只在屏外上传模型。终帧真实剩余挂点为 9 / 7 / 10，真实血量为 82.8% / 64.9% / 88.2%。部件损毁没有为美术伪造。

| 配置 | 平均 FPS 中位 | P1 FPS 中位 | 最慢帧 FPS | 低于 60 帧总数 |
|---|---:|---:|---:|---:|
| 同地图 + 旧 Mother Goose | 119.70 | 110.00 | 60.95 | 0 |
| 同地图 + 新 Mother Goose | 119.80 | 110.00 | 60.86 | 0 |

文件：2d 为 `112758 / 112915 / 113032`；3d 为 `112837 / 112954 / 113111`。双方有自然伤亡、弹丸和终帧血量差异，**不能把这组均值差解释成三维后端更快**；这里只确认这几个真实样本没有破 60。短测没有覆盖完整 JAM/MQ-X/胜利周期，不代表 BOSS 最坏阶段与完整局性能通过。

## Mother Goose：120 秒延长测试，未通过

每配置一轮，仍在同一三维地图、光照、近景跟随条件下运行，不在测量窗口采集额外截图；没有减单位、停火或绕过真实伤害。

| 配置 | 平均 FPS | P1 FPS | 最慢帧 FPS | 低于 60 帧数 | wrapper |
|---|---:|---:|---:|---:|---|
| 同地图 + 旧机体 | 118.88 | 100.00 | 33.73 | 16 | 退出 1，性能门失败 |
| 同地图 + 新机体 | 119.07 | 110.00 | 30.02 | 12 | 退出 1，性能门失败 |

原始证据分别为 `volume_2d_mother_goose_20260905_113619.txt` 与 `volume_3d_mother_goose_20260905_113403.txt`。新路径母机累计可见 14263 帧（含预热），结束时血量 49.6%，剩余真实挂点 7 个；此时 BOSS 还没有被击败，因此不是完整局/胜利终态的证据。

帧尖峰记录保留在结果文件中：新路径最大 33.314 ms，旧机体最大 29.651 ms。分类含物理追帧、Canvas 压力和未归因部分，**分类只是诊断线索，不是根因证明**；未覆盖的 CPU/GPU/呈现时间仍需拆分。旧机体这一组也使用新三维地图，不能称为“纯二维正式版本的既有性能债”。当前只能得出尖峰不专属于新机体显示，不能宣称 3D 更省或仅换回纸片就解决。

后续性能调查应固定同一战斗负载，分离三维地图、阴影和机体三个开关并补纯正式路径对照，再做 GPU/呈现时间分析；不靠删单位或关掉战斗反馈通过。本轮可行性实验到此保留失败结果，正式默认仍关闭。

## 手动战斗入口追加验证

2026-09-05 追加入口，不改变上述长时性能失败裁决：

- `volume_3d_combat` Shadow Visual：25/25，退出 0。走真实登场演出、点击坐标转换、滚轮、空格、Tab、Esc、F8 重载与回主菜单；重开后仍是实验战斗，旧场景释放且新机体重新绑定。测试等待演出自己结束，没有强制解除暂停。Mother Goose 在登场期间已有三维显示；手动入口的显示适配器在演出暂停期间继续同步，隐藏/渐隐单位仍回退原显示。
- 自动验收由 wrapper 显式启用，F6 手动运行不会启动自动输入或计时退出。`bench/results/volume_3d_combat_manual.png` 为真实玩家相机战斗截图，不是 BOSS 近景艺术验收或完整局通关证据。
- 单次 C1 回归 `volume_3d_c1_20260905_115856.txt`：30 秒、8/8 巡航、平均 119.17、P1 110.00、最慢 71.37 FPS、低于 60 帧数 0；新机体峰值 15。仅用于本次入口/渐隐守卫回归，不替代三轮 A/B 或修复此前 120 秒失败。

## 行为回归与待办

- focused：最新 `volume_world` 53/53，涵盖非零几何厚度、法线/顺时针正面、相机旋转与缩放投影、铁路 SSOT、显示回退和真实挂点伤害，以及手动场景/脚本编译和观察场跳转。
- 跨帧：默认 `lifecycle_gauntlet` 已接入新增案例，新增 5/5；原案例 86/86。真实伤害后跨帧撤去部件，飞机死亡接回残骸、已释放对象缓存继续执行、实验层退出后恢复存活机体。
- 初版默认 `all` 曾通过 92 项及后续生命周期。**手动入口追加后的最新 `bench\run.cmd all 1 300 Shadow Headless` 退出 1**：92 项中 1 项失败，为 `map_vector_preview` 首次 Operational 预热 1792 ms 超过原有 1600 ms 门槛；没有放宽门槛，也不将全量标绿。由于同步门失败未自动进入生命周期，另跑 `lifecycle_gauntlet 1 180 Shadow Headless`，原案例 86/86、新增案例 5/5，退出 0。
- 静态门：`verify_docs.ps1`、玩家引用持有者审计（漏登记 0）、`code-index.md` 视觉绘制定向锚点（43 项）及 `git diff --check` 通过。`script-index.md` 全文件审计仍有 9 个既有 `aircraft.gd` 符号锚点漂移；本轮没有修改该脚本，不将这个范围外问题掩盖或归为新模型回归。
- 运行日志另有系统证书读取、Visual 环境 Wacom/缓存目录诊断和退出时资源/ObjectDB 警告；旧/新运行均见相关诊断，尚无完整泄漏归因。默认 all 退出 0 不等于“日志无告警”或“无泄漏已证明”。
- 后续 BOSS 覆盖矩阵、航空挂载/CD 回弹与推广顺序，以设计 spec §6 为准；用户确认效果后再安排生产，当前默认入口不切换。

实现采用 [Godot 正交 Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)、[MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html) 与 [标准三维材质](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)。这些文档解释能力，性能结论只依据上述本地实测。
