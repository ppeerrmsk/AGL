# 已实现功能清单

> 最后校订：2026-08-20。本文回答"**这个游戏现在有什么**"，是给人看的粗粒度盘点。
>
> - 想知道**数值/公式/为什么** → [docs/specs/](../specs/_INDEX.md)（权威源）
> - 想知道**代码在哪** → [script-index.md](script-index.md) / [code-index.md](code-index.md)
> - 想知道**某次改动当时做了什么** → `docs/changelogs/`
>
> ⚠ 本文只标"有没有"，不标数值。相当多的系统状态是"代码已落地、差 playtest 调参"，
> 精确状态看 [specs/_INDEX.md](../specs/_INDEX.md) 总表的 status 列。

---

## 操控与指挥

- **RTS 点选操控**：左键点空地 → 飞向该点；左键点敌机 → 设为战斗目标并自动交战；右键取消
- **玩家命令铁律**：玩家点名的 `commanded_target` AI 绝不覆盖，逐机持久、跨切控保留
- **切控**：数字键 1–9 接管小队对应号机（`squad_slot` 稳定），被接管机的 AI 休眠，原操控机交还 AI
- **换帅**：`set_leader` 切换长机
- **命令轮盘**（按住左键拖拽呼出 marking menu，带子弹时间）
  - 小队轮盘（按空地）：紧急集合 / 撤离此区 / 防守此区 + 三个开关（自动交战 / 高度偏好 / 自动发射）
  - 攻击轮盘（按敌机）：姿态（STANDOFF 打带跑 / ASSAULT 突击）× 火力分配（集火 / 分火）× 阵型纪律
  - **输入语法**：单点 = 只管自机 / 轮盘 = 永远全队广播
- **加力模式**（E 键）：小队级充能资源，激活期全队强 buff（机炮闪避 / 滚转甩导弹 / 满速地板），禁攻击
- 相机：滚轮缩放、中键拖拽平移、战术地图

权威源：[specs/systems/command-wheel](../specs/systems/command-wheel.md) ·
[specs/systems/rts-command](../specs/systems/rts-command.md) ·
[specs/systems/squad-control-switching](../specs/systems/squad-control-switching.md) ·
[specs/systems/afterburner-mode](../specs/systems/afterburner-mode.md)

---

## 飞行物理

不使用 Godot 物理引擎，全部在 `_physics_process` 手动演算。按 LOD 分三档调度。

- 标准协调转弯 `ω = g × tan(bank) / speed`；G 载荷 `G = 1/cos(bank)`
- 滚转速率限制、非对称加减速（减速板语义）、高 G 阻力
- 高度⇌速度能量耦合（俯冲加速 / 爬升减速）
- 失速 `V_stall = V_stall_base × √G`；**角点速度地板**保证不会"转弯转到失速"
- 空气密度比 `σ = e^(-alt/8500)` 影响高空最大速度
- 转弯控制器为**临界阻尼 PD**（2026 重写，见 SEAM-012）
- 机动性 buff 统一走 `effective_*()` accessor 层，AI 战术层自动感知（AGENTS.md / SEAM-001 强制约定）

权威源：[architecture.md](../architecture.md) · [specs/systems/flight-model-realism](../specs/systems/flight-model-realism.md)

---

## 武器系统

全部武器**自动开火**，不存在玩家手动扳机（设计原则 10）。

| 武器 | 状态 | 备注 |
|---|---|---|
| 机炮 | ✅ | 前置射击 / 距离伤害衰减 / 高度差检查 / **梭射节奏**（burst 制，非匀速滴弹）|
| 主导弹 | ✅ | PN 比例导引 / 智能目标选择 / 单目标不重复补射 / crank 保持照射 |
| 副武器槽 SP | ✅ | 独立锁定锥/距离/CD 的第二套武器子系统（首个样本 QMAAM）|
| 火箭弹 | ✅ | 扇形锥内自动一波速发（A-10 Hydra 70 等）|
| 电磁炮 | ✅ | 充能 + 预测狙击 + **承诺弹道**（指示线即发射线）；两相对准 |
| 激光 | ✅ | 拦截型（Aegis UAV 打导弹）|
| 热诱弹 | ✅ | 概率失误 `fail_chance`；对王牌中队而言**热诱弹即命数** |
| 忠诚僚机 / 漂浮雷 / 空射鱼雷 | ✅ | 特殊装备类 |
| 武器竞选 | ✅ | "什么距离用什么武器"的统一准则 + 机头指向路径提前点瞄准语义 |

⚠ **不做**现实武器分类（红外/半主动/主动）的差异化逻辑——武器只是一组性能参数。

权威源：[specs/systems/weapon-employment-doctrine](../specs/systems/weapon-employment-doctrine.md) ·
[specs/weapons/](../specs/_INDEX.md) · [systems/missile-system.md](../systems/missile-system.md)

---

## 雷达与锁定

- 锥形探测（航向为轴的扇形），参数化半径 + 半角
- 锁定累积 `lock_time`；被锁警告；照射共享
- JAM 状态清空照射并禁止累积；云层内锁定衰减
- 隐形（STEALTH）机制 + **隐形一致性铁律**（所有索敌通路都要过 `is_lock_immune`）

权威源：[systems/radar-system.md](../systems/radar-system.md)

---

## AI

- 状态机 `AIState { PATROL, ENGAGE, SQUAD_FOLLOW }` + 导弹规避子行为
- **TacticalPlanner**：玩家 / 僚机 / 全部敌机走统一决策路径，输出 intent
- BFM 战术族：lead/lag pursuit、lead turn、high/low yoyo、破 S、boom-zoom、overshoot 处理
- 行为原语：攻击跑（joust）/ 对面攻击 pass / 慢速空中目标 pass / 圈外切入
- AI 原型预设（内部词汇，**不对玩家暴露**）：Gladiator / Lancer / Schemer / Adds
- 飞行员心理：`stress` / SA（FEAR 状态的底层）
- 交战纪律：无 combat_target 即停火；能量触发的脱出重建
- 全图察觉与 ROE：中队级感知圈 + 任务姿态五型 + **热度即难度**（内部量，不上 HUD）
- 目标选择：可命中性评分（对正度/包络/锁定/邻近）+ **战场引力**三带

权威源：[systems/ai-system.md](../systems/ai-system.md) ·
[specs/systems/global-awareness-roe](../specs/systems/global-awareness-roe.md) ·
[specs/systems/target-engageability-selection](../specs/systems/target-engageability-selection.md)

---

## 编队与小队

- Squad 结构 + 阵型槽位；三段式托管航向控制（LOD 1）
- 阵型纪律开关：FREE 自由散开 / TIGHT 紧密队形 + 齐射（长机开火 = 全队开窗）
- 小队凝聚学说：焦点开火、维持阵型、防游走 leash、GUARD_REAR 守后
- 僚机护卫：反杀咬长机者 + 投护卫 flare 替长机挡导弹
- 敌方同享编队学说（成建制 / 随机阵型）
- 调试：F11 编队覆盖层、F12 编队快照

权威源：[systems/squad-tactics-design.md](../systems/squad-tactics-design.md) ·
[specs/systems/squad-cohesion](../specs/systems/squad-cohesion.md) ·
[specs/systems/formation-discipline](../specs/systems/formation-discipline.md)

---

## 生存模式（主玩法）

- **战区推进 → BOSS 战 → 击败 BOSS 即过关**（不是无尽波次）
- 战区任务：地面 TGT 打光 / 空中中队歼灭 / 机场解放；攻克后开新战区
- **停靠结算**：飞到停靠点减速着陆 → 领奖励 / 换机进化 / 全队满血
- **进化树**：43 节点宝可梦式机型进化（T1 起手四卡，按生涯逐步解锁 → T5 原创超凡），带 LV + 三轴属性双门槛
- **三轴卡片制**：每升 3 级三选一（斗士 / 骑士 / 策士各一张），选卡 = 技能 + 该轴 1 点
- **技能系统**：当前自动生成表共 165 条，含 43 条机型签名技；签名技经生涯揭示/购买后进入每机每局一次的第四槽机会，到手跟玩家走
- **局内武器库**：特殊武器到手即永久，换机 / 进化全继承
- **局外功勋**（MeritLedger）：局内 XP 按系数折算，节制原则（局内 90% / 局外 10%）
- 敌人谱已有 50+ 个 `EnemyType` 条目（含常规机、直升机、轰炸机、无人机、舰载机与王牌专属单位）
- Token 预算刷怪 + 热度驱动的增援入场（边缘中队涌入 → 驻空 → 物理飞离）
- 王牌中队分层（AceTier）：不吃 LOD / 无等级缩放 / 热诱弹即命数
- BOSS 注册表四项：WRAITH F-47 中队 / LADON 航母战斗群（POLTERGEIST 二阶段）/
  Mother Goose 飞行翼母舰 / Black Star（Hyper-A 双根分裂）
- 第三方与可选任务：机场防空 / AWACS / 战区制空与对地支援 / 王牌截击支援 / B-1B 轰炸机护送
- 动态性能控制：FPS 采样 → 自动收敛敌机上限

权威源：[systems/survivor-mode.md](../systems/survivor-mode.md) ·
[specs/systems/survivor-loop](../specs/systems/survivor-loop.md) ·
[enemy-index.md](enemy-index.md) · [skill-implementation-index.md](skill-implementation-index.md)

---

## 地面 / 海上单位

- 地面：SAMUnit（防空导弹车）/ AAGunUnit（高射炮）/ RadarStation（雷达站）/ 地面车队
- 海上：航母 / 巡洋舰 / 驱逐舰 / 护卫舰 / 潜艇；**挂点 + 弱点**伤害路由（`MountTarget`）
- Ladon 战斗群（CSG）：接战即弹射舰载机

权威源：[systems/ground-units.md](../systems/ground-units.md)

---

## 地图

- 60×60km 战场（2026-07 扩图），矢量地理 + OSM 烘焙 + 底图三层
- 手画东京湾地理，`is_on_land` 陆判 API
- 战区分布 A–G，含机场解放战区（羽田 / 木更津 / 調布）
- 天气系统：云层影响锁定与导弹制导
- **地图编辑器核心**（UGC P1）：已有格子笔刷、矢量后端与官方图转换代码；完整产品化状态以 map-editor spec 为准
- 沙漠铁路与海洋群岛已有可飞行预览和天气/底图候选，但尚未达到独立完整局；当前铺量顺序见
  [content-production-workflow](../planning/content-production-workflow.md)

权威源：[specs/systems/map-system](../specs/systems/map-system.md) ·
[specs/systems/map-expansion](../specs/systems/map-expansion.md) ·
[specs/systems/map-editor](../specs/systems/map-editor.md) · [map-pipeline.md](map-pipeline.md)

---

## 表现层

- 极简线框飞机图标（代码 `_draw()`），阵营色板统一（蓝=玩家 / 绿=中立第三方 / 橙红=敌）
- 滚转变形、高度缩放、尾迹、加力火焰、机头闪光、爆炸分级、解体动画
- **无线电通讯**：屏幕上方"呼号 ▸ << 台词 >>"，一次一条绝不打断，三层节流，数据全外置 JSON
- **战况栏 / kill feed**：左上角"谁用什么武器击坠谁"
- **表演导演系统**：TimeAuthority 时间栈 + SequencePlayer 时间线 + 空舞台隔离（升级急刹车 / BOSS 登场演出）
- 音频：总线 + BGM + SFX + UI + 播放列表
- **i18n 三语**：中 / 英 / 日，玩家可见文本一律 `tr("KEY")`

权威源：[specs/systems/radio-chatter](../specs/systems/radio-chatter.md) ·
[specs/systems/ui-transition](../specs/systems/ui-transition.md) ·
[systems/audio.md](../systems/audio.md) · [i18n.md](i18n.md)

---

## 开发基础设施

- **EventLogger**：60 秒环形缓冲，F9 导出战斗日志
- **无头 bench**：`--bench=<name>` 跑断言（转弯物理 / 战术几何 / 技能 / 回归门等），`--bench=all` 全跑
- **文档校验**：`tools/verify_docs.ps1`（断链 + spec 结构）+ `tools/verify_doc_anchors.py`（代码锚点）+ `tools/verify_player_ref_holders.py`（SEAM-019）
- **技能表生成**：`tools/dump_skill_table.py` 重刷 [skill-table.md](skill-table.md)
- Debug：F4 动态覆盖全技能表并可强制授予、可直挂全部门控装备（含 ESM）；F6 可逐项直发完整战区奖励并管理战区；主菜单 B → BOSS 测试场；F11/F12 编队调试

---

## 明确不做的方向

见 [DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md) 反模式段。摘要：

- ❌ RPG 式 HP 海 / 数值膨胀（除 BOSS 外空中敌人一发死）
- ❌ 玩家察觉不到的 +5% 暗 buff
- ❌ 需要玩家手动按键开火的武器
- ❌ 长期局外解锁的进度墙
- ❌ 让帧数掉到 60 以下的新内容
- ❌ 引入现实武器分类作为机制约束
