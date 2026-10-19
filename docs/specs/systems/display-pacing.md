---
id: display-pacing
kind: system
status: done
schema_version: 1
spec_version: 1
owner: AGL
depends_on: [systems/combat-entity-volume-prototype]
reconstruction_complete: true
---

# 显示节拍：物理插值与帧上限

> 物理仍是固定 60Hz，画面上的飞机、导弹、镜头、标签和尾迹按渲染帧连续移动，高帧率下不再一顿一顿。

## 1. 设计意图（Why）

- **体验目标**：消除“帧率很高但画面一直不顺”。2026-10-17 诊断实测：物理 60Hz、未开插值、渲染不限帧
  （正式局 220–280 FPS，C2 约 100 FPS）时，42–77% 的渲染帧里玩家位置完全不变，位移以 13–20ms 不均匀
  间隔呈现；镜头在渲染帧里 lerp 追一个每 tick 才跳一次的目标，屏幕滚动速度逐帧忽快忽慢。
- **Litmus 自检**：纯表现层，不改任何玩法数值、物理、AI 或命中判定；游戏逻辑只读物理位置。
- **反模式规避**：不全局开启插值（大量 VFX/UI/Tween/镜头在 `_process` 改变换，会被引擎按 tick 错误插值）；
  不为插值把批量世界坐标绘制改成逐渲染帧重绘（性能守则 R1/R6）。

## 2. 数据定义（What）

| 项 | 值 | 说明 |
|---|---|---|
| `physics/common/physics_interpolation` | `true` | 项目开关；运行态可被 `AGL_PHYSICS_INTERP=0/1` 覆盖（A/B） |
| 根节点 `physics_interpolation_mode` | `OFF` | 启动时设置，白名单制 |
| 新入树的任意 `Viewport`（SubViewport / Window） | `OFF` | 实测 Godot 4.7 视口默认是独立插值根（子树回到开启），入树即强制关闭 |
| 白名单节点 | `Aircraft`、`Missile` | 只在 `_physics_process` 移动；`_ready` 设 `ON` 并延迟重置一次 |
| `physics_jitter_fix` | 插值开：`0.0`；插值关：项目值（默认 `0.5`） | 插值已吸收 tick/帧相位差 |
| `common/max_physics_steps_per_frame` | `2`（原 `3`） | 单帧超时只补 1 步；代价见 §3.5 |
| 帧上限 | 默认 `0`（不限，跟随 VSync） | `user://display.cfg [display] max_fps`；`AGL_MAX_FPS` 覆盖；非 0 时下限 `30` |
| 物理频率 | `60` tick/s | 不变 |

## 3. 行为与公式（How）

### 3.1 引擎插值语义

每个物理步开头，引擎把白名单 CanvasItem 的 `prev ← curr`；步内脚本写入新变换成为 `curr`；
渲染时显示 `prev.interpolate_with(curr, f)`，`f = Engine.get_physics_interpolation_fraction()`
（距上一步的时间 / 步长，0..1）。显示态比最近物理步滞后 `(1−f)` 个 tick。

### 3.1.1 视口边界（Godot 4.7 实测）

SubViewport / Window 入树后自身仍按“插值开启”解析，不继承根节点的 `OFF`：其下 Camera2D 会被引擎改为物理
回调并走插值路径（`force_update_scroll` 不再立即刷新画布变换，地图瓦片可见性与三维合成层取景随之错帧），
Node3D 被 3D FTI 插值。故安装时监听节点入树，凡 Viewport 一律设为 `OFF`；入树信号早于其子节点入树，
子树随之继承关闭。白名单单位即使位于子视口内也仍显式 `ON`。

### 3.2 显示态（供 `_process` / 绘制消费方读取）

白名单节点在 `_physics_process` 开头记录 `interp_prev_xform = transform`、`interp_prev_tick = 当前物理帧号`；
收到 `NOTIFICATION_RESET_PHYSICS_INTERPOLATION` 时 `interp_prev_xform = transform`。

```
is_interpolating(node) = 插值开启 且 node 已解析为插值 且 interp_prev_tick == 当前物理帧号
display_local(node)    = is_interpolating ? interp_prev_xform.interpolate_with(node.transform, f) : node.transform
display_global(node)   = 父 CanvasItem 全局变换 × display_local（父容器视为不插值）
display_origin(node)   = display_global(node).origin（不插值时 = global_position）
display_rotation_offset(node) = angle_difference(node.rotation, display_local.rotation)
display_time_lag       = 插值开 ? (1−f) × time_scale / 60 : 0
```

`interp_prev_tick` 不等于当前物理帧号（暂停、本步未跑物理）时显示态 = 物理态，与引擎 prev=curr 一致。

同一渲染帧内镜头、状态栏、尾迹、三维合成层会多次读同一单位：`display_global` 以（渲染帧号, 物理帧号）为键缓存在单位上，
重置插值时清缓存。物理帧号进键，保证物理步中途的读取不会复用上一帧结果。

### 3.3 必须读显示态的消费方

| 消费方 | 读取 | 原因 |
|---|---|---|
| 镜头跟随（含演出 cine_target） | `display_origin(target)` 作 lerp 目标 | 追阶梯目标会让滚动与机体相对抖动 |
| 世界单位状态栏、恐惧锥与暴露条 | `display_origin` / 显示航向 | 标签不得在 tick 间相对机体抖动 |
| 正式局三维机体合成层（含母鹅挂点） | `display_origin` + `heading + display_rotation_offset` | 三维机体不经二维插值，必须喂显示态 |
| 尾迹 `TrailRibbon` | 本地变换 = `display_global(父机)⁻¹`；20Hz 采样点 = `display_origin(父机)` | 父机插值后，`global_transform=IDENTITY` 会让整条丝带随相位抖动；采显示态避免丝带头冒出机头 |
| bench 巡检镜头 | 巡检时刻 = `_bench_elapsed − 3 − display_time_lag` | 原按物理步累加时间采样，镜头自身阶梯跳 |
| FrameProbe | 玩家显示态位置；物理位置、`f`、开关另列 | 度量真实呈现 |

尾迹节点自身 `OFF`；导弹批次尾迹的自身 Canvas 不出图，跳过逐帧抵消。

### 3.4 保持 60Hz 的绘制（已评估）

- `BulletManager` 子弹/火箭/空爆弹：每物理步重绘一次的世界坐标批绘，保持模拟真值位置。逐渲染帧重绘成本随
  弹丸数与帧率线性放大，违背 R1/R6。
- 飞机 `_draw` 内的目标线、锁定框、预测航迹：在机体本地坐标绘制，随插值机体刚性移动；远端相对误差
  ≤ (1−f) × 一 tick 的相对位移/旋转。

### 3.5 传送与出生

- 出生：白名单节点 `_ready` 设 `ON` 后 `reset_physics_interpolation.call_deferred()`，出生点在 `add_child` 后写入也不会从旧位置插值过来。
- 传送：`Aircraft.clear_trail()` 是现有传送收口（越界钳回、编队/演出落位、BOSS 冲刺等均调用），在其中 `reset_physics_interpolation()`。

### 3.6 补步上限 2 的代价

一帧墙钟超过 2 个 tick（>33.3ms）时，多出的模拟时间被丢弃，游戏时间短暂慢于墙钟（时间膨胀）；
换取不再出现“超时→补 3 步→继续超时”的秒级补步螺旋。物理步会话实测 C2：>16.7ms 帧 2.13% → 0.88%，
>33ms 帧 52 → 14（见 performance-guidelines 历史教训）。

## 4. 结构与组成（Structure）

- 静态服务 `DisplayPacing`（无 class_name，消费方 preload）：安装、开关、显示态函数、帧上限读写。
- 启动接线：表演导演 AutoLoad 的 `_ready` 调用安装（早于任何战斗场景）。
- 白名单单位：`Aircraft`、`Missile` 各持 `interp_prev_xform` / `interp_prev_tick`。
- 诊断：FrameProbe 显示态采样列 `ply_wx/wy/sx/sy`（显示态）+ 行尾 `ply_px,ply_py,interp_f,interp_on`；
  自动驾驶可选 `AGL_FRAME_PROBE_SHOTS=<n>` 截帧；`tools/frame_probe_motion.py` 计算顿挫指标。

## 5. 验收标准（Acceptance）

- [x] 正式局自动驾驶与 C2 交错 A/B（`AGL_PHYSICS_INTERP=0/1`，各 ≥2 轮）：插值开时无位移帧比例为 0，
      逐帧世界速度变异系数、玩家屏幕二阶抖动显著下降；正式局帧时无可测差异，C2 平均帧时 +0.4～0.6ms（见 5.1）
- [x] 截帧检查：近/中/远镜头（2.5/1.2/0.5）下尾迹、预测航迹、目标箭头、来袭锁定框、敌机连线与状态栏均贴合机体
- [x] 视口子树：SubViewport 内 Camera2D/Node3D 不插值，`force_update_scroll` 立即刷新画布（`display_pacing` 专项断言；
      `volume_world` 210/3 与插值关闭时逐条相同）
- [x] focused：`display_pacing` 29/0、`presentation` 402/0、`trail_ribbon_lod` 7/0、`predicted_path` 13/0、
      `missile_visual_lod` 8/0、`target_marker_lod` 7/0、`bench_camera_patrol` 12/0；`volume_world` 仅余与插值无关的缺失资源项
- [x] `bench\run.cmd all 1 300 Shadow Headless` 不新增失败：104 项失败 14，错误行与同工作树基线逐条相同（均为缺失预烘焙地图资源）；
      较 2026-10-18 早先 102 项基线只多一行退出时 VariantPools 页未释放（既有泄漏对象带 Transform2D 成员所致，泄漏对象/资源数 45/11 不变）；lifecycle 单跑 90/1 同基线
- [x] 性能：消费方每帧每单位一次插值求值（按渲染帧缓存），尾迹每帧一次变换求逆；不新增逐实体全场扫描
- [x] 文档：本 spec 已登记 _INDEX；script-index / code-index / known-seams（SEAM-053）/ performance-guidelines 已同步

### 5.1 证据记录

测量口径：`tools/frame_probe_motion.py`（玩家呈现位置取插值显示态）。正式局 = `probe_play` 自动驾驶 240s；
C2 = `tokyo_volume_c2` 36s；均为 Shadow Visual、1600×900 窗口、300Hz VSync、物理补步上限 2，交错运行。

| 指标 | 正式局 插值关（2 轮） | 正式局 插值开（2 轮） | C2 插值关 | C2 插值开 |
|---|---|---|---|---|
| 无位移帧比例 | 78.9% / 78.3% | 0% / 0% | 80.8–82.9% | 0% |
| 位移平均间隔 | 16.9ms | 3.5–3.7ms（=帧间隔） | 约 68ms | =帧间隔 |
| 逐帧世界速度变异系数 | 1.99 / 1.95 | 0.29 / 0.19 | 2.32–2.50 | 0.28–0.29 |
| 玩家屏幕二阶抖动 p95 | 0.843 / 0.835 px | 0.004 / 0.004 px | 0.79–0.92 px | 0.025–0.038 px |
| 玩家逐帧屏幕位移 p95 | 1.17 / 1.17 px | 0.012 / 0.016 px | 1.07–1.26 px | 1.37–1.70 px（巡检镜头自转） |
| 全程屏幕滚动速度变异系数 | 0.30 / 0.27 | 0.29 / 0.19 | 10.6–10.9 | 2.3–2.6 |
| 平均帧时 | 3.53 / 3.63ms | 3.46 / 3.70ms | 7.79–7.93ms | 8.42–8.60ms |
| >16.7ms 帧 | 0.05% / 0.01% | 0.00% / 0.01% | 0.56–1.69% | 1.31–2.01% |

C2 成本拆分（同代码、交错）：有物理步的帧持平；无物理步的帧插值开 +0.5ms，其中巡检镜头逐帧移动约 0.2ms
（插值开但巡检镜头仍按 tick 采样的变体恢复这部分），其余约 0.3ms 为显示态消费方与引擎插值开销。

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | `verify_doc_anchors` / `verify_player_ref_holders` / `verify_docs` | 锚点与持有者全过；`verify_docs` 仅余 17 条既有审计文档 PNG 链接缺失 |
| E1 聚焦 Shadow | 见上方 focused 清单；`all` 104/14、lifecycle 90/1 | 全过；失败集合与基线相同 |
| E2 集成 / 压力 Shadow | C2 交错 A/B（6 对含 tick 变体） | 顿挫指标大幅下降；平均帧时 +0.4～0.6ms，FPS 降幅 <15 |
| E3 Visual | 自动驾驶截帧（插值开/关各 18 帧） | 尾迹/连线/状态栏无脱节 |
| E4 完整局 | 正式局自动驾驶 240s × 4 | 顿挫消除，帧时无可测差异；人工长局手感未做 |

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 插值白名单与显示态
- [x] 项目开关 + 根 OFF + Aircraft/Missile ON + 显示态记录
- [x] 镜头 / 状态栏 / 三维合成层 / 尾迹 / bench 巡检镜头改读显示态
- [x] 传送收口重置；补步上限 3→2
- [x] 帧上限配置；FrameProbe 显示态列与截帧；分析脚本

### 阶段 2 — 验收
- [x] A/B 测量与截帧检查
- [x] 显示态按渲染帧缓存、单次求值（C2 插值开 102–112 → 117–119 FPS）
- [x] focused + all 回归

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 主逻辑 | `scripts/util/display_pacing.gd` |
| 白名单单位 | `scripts/aircraft.gd`、`scripts/missile.gd` |
| 消费方 | `scripts/camera_controller.gd`、`scripts/ui/world_unit_status_overlay.gd`、`scripts/experiments/volume_world_probe.gd`、`scripts/trail_ribbon.gd`、`scripts/survivor/survivor_mode.gd`（bench 巡检镜头） |
| 启动接线 | `scripts/presentation/presentation_director.gd` |
| 诊断 | `scripts/diagnostics/frame_probe.gd`、`scripts/diagnostics/frame_probe_autoplay.gd`、`tools/frame_probe_motion.py` |
| 测试 | `scripts/tests/test_display_pacing.gd`（bench `display_pacing`） |
| reference 索引 | script-index.md / code-index.md 的对应条目 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-10-18 | 1 | 物理插值白名单、视口降级、显示态消费方与按帧缓存、补步上限 2、帧上限；A/B 与回归验收完成 |
