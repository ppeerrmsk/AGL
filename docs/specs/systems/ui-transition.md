---
id: ui-transition
kind: system
status: in-progress
schema_version: 1
spec_version: 12
owner: noelu
depends_on: [command-wheel, survivor-loop, zone-reward-docking, radio-chatter, event-system]
reconstruction_complete: true
---

# 表演导演系统（转场 / 镜头 / 时间 / 演出）

> 界面不再"啪"地跳出来，BOSS 也不再默默飘进战场。升级时世界急刹、卡片错开弹入；
> Wraith 登场时舞台清空成一片空旷的天空，四架 F-47 列队飞入、台词逐句响起，
> 然后世界在他们周围重新组装 —— 玩家回到战场时，敌人已经在那儿了。

## 1. 设计意图（Why）

- **体验目标**：把"界面出入场 / 镜头 / 时间缩放 / 台词编排 / 演员走位"从各面板与各 BOSS 子类的
  私有逻辑里抽出来，收成一个**可编排、可调参、数据驱动**的表演层。
  两个落地实例：升级面板的**急刹车转场**（最小闭环）与 **Wraith 中队登场演出**（完整闭环）。
  之后加新演出只写 JSON，不写系统。

- **Litmus 自检**（引 DESIGN_PHILOSOPHY）：
  - **#3 信息察觉优先于数值** —— "如果一个改动玩家说不出'哪里不一样了'，那它就不该存在"。
    升级选**急刹车**而非通用淡入；BOSS 选**清空舞台**而非镜头随便晃两下。两者都是能被指认的事件。
  - **#2 操作反馈：笨重 + 延迟快感** —— 延迟只许加在**铺垫**侧。升级入场可以有仪式感，但玩家
    点下卡片后升级效果必须**当帧**生效。BOSS 演出是纯铺垫（战斗尚未开始），是合法的延迟位置。
  - **#7 战场氛围：要热闹** —— 演出层是"热闹"的主要载体，与无线电、击杀提示同族。
  - **#9 阶段时机** —— BOSS 登场是战区节奏的分界点，值得一段仪式。
  - **#11 性能红线：60 FPS** —— 导演空闲时 `set_process(false)`；全场扫描只在演出**起止各一次**，
    不进每帧。

- **反模式规避**：
  - **不新增玩家决策**：演出不引入新按键、新交互、新 HUD 中介。F8 热重载仅编辑器模式。
  - **不做非物理强扭**：演员走位**只下发航路点**，飞行由既有物理与转弯控制器飞出来。
    **禁止**逐帧写 `global_position` / 预烘焙曲线 —— 俯视全程可见，K 帧出来的轨迹与机身坡度、
    速度、盘旋半径对不上，跟旁边正常飞的飞机一比立刻穿帮。
  - **不造第二套 AI 所有权**：演员指令一律经既有 `AIDirective` + `GameEvent` 的 owner/cleanup 下发。
  - **不做模式污染**：导演是 autoload，但只被生存模式链路调用；共享层（aircraft / ai / weapons）不碰。
  - **演出必须短**：生存模式是无尽波次，同一段演出玩家会看几十遍。**不可跳过**是已定决策
    （见 §3.6），代价必须用时长来还 —— BOSS 演出硬上限 **7 秒**。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 系统级常量

| 字段 | 值 | 说明 |
|---|---|---|
| `DIM_LAYER` | `16`（**上限**，非固定值） | 压暗层 CanvasLayer 的默认高度。**实际取 `min(DIM_LAYER, panel.layer − 1)`** —— 压暗层必须永远低于被展示的面板，否则面板被自己的遮罩盖住。面板在 20（升级/进化/边界）→ 取 16，战区提示(18) / 无线电(19) 留在亮处；面板在 15（战术图）→ 取 14 |
| `FX_LAYER` | `25` | 特效层（闪白 / 渐黑 / 信箱框）。高于全部面板(20)，低于 debug(30/31) 与命令轮盘(100) |
| `PAUSE_SCALE` | `0.05` | 急刹终点的时间缩放。不取 0 —— `Engine.time_scale = 0` 下 `_process` 仍以 `delta = 0` 被调用，非 delta 逻辑照跑，不是真暂停 |
| `TIME_EPSILON` | `0.001` | 时间栈求解的浮点比较容差 |
| `SEQ_PATH` | `res://resources/presentation/sequences.json` | 序列定义唯一权威文件 |
| `CINE_MAX_SEC` | `7.0` | 演出硬超时。超时强制走收尾路径（见 §3.7），防演出卡死锁死一局 |
| `HOT_RELOAD_KEY` | `F8` | 重读 JSON + 重放当前序列。**仅 `OS.has_feature("editor")`**。F9/F10/F11/F12 已被日志导出 / RuntimeTuner / 编队调试占用 |

> **为什么压暗层拆成两层**：无线电条在 CanvasLayer 19。若压暗层放在它之上，BOSS 演出会把
> 自己的台词一起压暗 —— 而台词正是演出的主角。拆层后升级转场也顺带受益（现状是升级遮罩在
> 20，把无线电一起压暗了）。
>
> ⚠ **压暗层高度不能写死**（playtest 实测踩坑）：战术图自己在 CanvasLayer **15**，
> 固定 16 的压暗层会盖在它上面 —— 打开 Tab 地图整个变黑。故实际高度按被展示的面板动态求解，
> 规则见上表。无头断言 `dim.*` 逐面板守门。

### 2.2 时间栈（TimeAuthority）

| 字段 | 值 | 说明 |
|---|---|---|
| 求解规则 | **最小值获胜** | 所有活跃请求中最小的 `scale` 即当前 `Engine.time_scale` |
| 空栈默认 | `1.0` | 无请求时恢复正常速度 |
| 请求键 | `StringName` | 同 id 重复请求 = 覆盖，不叠加 |
| 混合时钟 | **unscaled** | 缩放过渡本身用原始 delta 还原，否则时间越慢过渡越慢，永远到不了终点 |
| `hard_pause` | `get_tree().paused` | 真暂停的**唯一**入口，与 scale 栈正交 |

请求 id 全集（阶段 2 收编后）：

| id | scale | 来源 |
|---|---|---|
| `&"upgrade"` | `0.05` | 升级面板急刹 |
| `&"wheel"` | `0.3` | 命令轮盘 |
| `&"settlement"` | `0.05` | 进化 / 结算站 |

BOSS 演出**不用时间栈**，走 `hard_pause` + 演员豁免（见 §3.4）。

### 2.3 升级转场序列 `upgrade_in`

总时长 **0.54s**（= 面板 step 的 `at 0.16` + 跨度 `0.38`）。

| # | at (s) | 通道 | 动作 | from → to | dur (s) | ease |
|---|---|---|---|---|---|---|
| 1 | 0.00 | `time` | 请求 `upgrade` 缩放 | 1.0 → 0.05 | 0.15 | `expo_out` |
| 2 | 0.06 | `camera` | `zoom_punch`（推近） | ×1.0 → ×1.12 | 0.30 | `back_out` |
| 3 | 0.10 | `overlay` | `dim` 遮罩透明度 | 0.0 → 0.60 | 0.18 | `cubic_out` |
| 4 | 0.15 | `time` | `hard_pause(true)` | — | 瞬时 | — |
| 5 | 0.16 | `panel` | `stagger_in` 元素错开弹入 | 见下 | **0.38**（跨度） | `back_out` |

`stagger_in`：`stagger = 0.06`，`elem_dur = 0.20`。
单元素 = `modulate.a: 0 → 1`（`cubic_out`）**并行** `scale: 0.92 → 1.0`（`back_out`）。
元素表见 §4.3（标题 + 3 张卡 = 4 个）。

> ⚠ **错开跨度不变式**：`dur ≥ elem_dur + stagger × (n−1)`。
> `dur` 是**整组跨度**（序列运行器据此计时），`elem_dur` 才是单元素时长。
> 4 个元素时：`0.20 + 0.06×3 = 0.38`。
> 违反则最后一个元素的进度跑不满 —— 它会**永久停在半透明**，看起来像"第三张卡没出来"。
> 本项目首次实现就踩了这个坑（把 `dur` 当成单元素时长），已加无头断言 `stagger.*跨度足够` 守门。

> ⚠ **不用 `position` 做滑入**。卡片是 `HBoxContainer` 的子节点，Container 每帧
> `fit_child_in_rect` 覆写子节点 `position`/`size`，位移会被吃掉。`scale` 与 `modulate`
> 不受 Container 管辖。`scale` 生效前须设 `pivot_offset = size * 0.5`，否则从左上角缩放。

> ⚠ **元素必须先压到 alpha 0，再 `visible = true`**。反过来的话，等 Container 算 size
> 的那一帧面板会以全不透明闪现一下 —— 正是本系统要消灭的"突兀"本身。

### 2.4 升级退场序列 `upgrade_out`

总时长 **0.30s**。**第 0 帧完成所有状态恢复**，动画只是尾巴。

| # | at (s) | 通道 | 动作 | from → to | dur (s) | ease |
|---|---|---|---|---|---|---|
| 1 | 0.00 | `time` | `hard_pause(false)` | — | 瞬时 | — |
| 2 | 0.00 | `panel` | `stagger_out`（`stagger = 0`，齐退） | a 1→0 / scale 1→0.96 | 0.12 | `cubic_in` |
| 3 | 0.00 | `time` | 释放 `upgrade` | 0.05 → 1.0 | 0.20 | `expo_out` |
| 4 | 0.02 | `overlay` | `dim` | 0.60 → 0.0 | 0.16 | `cubic_in` |
| 5 | 0.02 | `camera` | `zoom_punch` 归位 | ×1.12 → ×1.0 | 0.28 | `cubic_out` |

### 2.5 缓动函数（EaseLib）

`t ∈ [0,1] → [0,1]`，端点恒为 `f(0)=0, f(1)=1`。

| 名 | 公式 |
|---|---|
| `linear` | `t` |
| `cubic_out` | `1 - (1-t)³` |
| `cubic_in` | `t³` |
| `cubic_in_out` | `t<0.5 ? 4t³ : 1-(-2t+2)³/2` |
| `expo_out` | `t>=1 ? 1 : 1 - 2^(-10t)` |
| `back_out` | `1 + c₃(t-1)³ + c₁(t-1)²`，`c₁ = 1.70158`，`c₃ = 2.70158` |

`back_out` 过冲到约 **1.10** 再回落 —— 这是"弹入"手感的来源，故 scale 终点必须是 1.0。

### 2.6 镜头电影层（CameraController 扩展）

| 字段 | 默认 | 范围 | 说明 |
|---|---|---|---|
| `cine_zoom_mult` | `1.0` | `[0.3, 3.0]` | 乘到基础 zoom。Camera2D **zoom 越大越推近** |
| `cine_offset` | `Vector2.ZERO` | — | 写入 `camera.offset`，**不写 `global_position`** —— 后者会被 `_clamp_camera_position` 钳制并污染跟随 |
| `cine_target` | `null` | — | 演出期间的临时跟随目标；非空时接管 `_update_follow`，演出结束还原 |
| `shake_trauma` | `0.0` | `[0, 1]` | 抖动强度 |
| `SHAKE_DECAY` | `1.8` /秒 | — | `trauma -= SHAKE_DECAY * delta` |
| `SHAKE_MAX_PX` | `14.0` | — | 位移 = `SHAKE_MAX_PX * trauma²`（平方使尾部收干净） |

> ⚠ **zoom 反馈环**：现有 `update_zoom` 回读 `camera.zoom.x` 作 lerp 起点。直接把
> `cine_zoom_mult` 乘进 `camera.zoom` 会自乘发散。必须引入内部 `_base_zoom`：
> `_base_zoom = lerp(_base_zoom, target_zoom, delta*10)`，再 `camera.zoom = _base_zoom * cine_zoom_mult`。
> `_base_zoom` 在 `setup()` 初始化为 `START_ZOOM`。`_clamp_camera_position` 继续读
> `camera.zoom.x`（含系数）—— 这是正确的，钳制应基于实际视野。

### 2.7 空舞台（Stage Isolation）

BOSS 演出期间把世界"清空"成一片空旷天空的参数。**不新建场景、不新建 Viewport** ——
靠淡出实现视觉隔离。

| 字段 | 值 | 说明 |
|---|---|---|
| `STAGE_CLEAR_SEC` | `0.50` | 非演员单位 `modulate.a → 0` 的时长 |
| `STAGE_RESTORE_SEC` | `0.80` | 世界淡回的时长（比清空慢，"重新组装"要有重量） |
| `STAGE_MAP_ALPHA` | `0.25` | 演出期间地图/地理层的 `modulate.a` |
| `STAGE_HUD_ALPHA` | `0.0` | 演出期间 HUD 全隐 |
| 演员豁免 | `process_mode = ALWAYS` | 演员飞机 + 其 AIController 在 `hard_pause` 下继续跑 |
| 非演员 | 保持 `PROCESS_MODE_INHERIT` | 被 `hard_pause` 冻住，**零 CPU、零风险** |

> **为什么这样就够**：`hard_pause(true)` 冻住整个世界（玩家绝对安全、敌人不动、导弹不飞），
> 只有演员的 `process_mode = ALWAYS` 让他们继续飞。视觉上其它单位淡到 0、地图压到 25%，
> 观感就是"另一个空间"。这是**最省的实现**：没有第二个 Viewport，没有坐标系映射，
> 没有重父级（重父级会打断 `all_units` 注册与雷达累积，见 known-seams 的 MountTarget 教训）。

### 2.8 Wraith 登场演出序列 `wraith_arrival`（分镜定稿）

总时长 **6.70s**（硬上限 7.0s；末步为 5.90 起的镜头归位 0.80）。演员 = 4 架 F-47（`WRAITH-01..04`）。
**三幕结构**（用户分镜，2026-07-20）：

```
第一幕 平飞          第二幕 交汇·隐身（v2）        第三幕 尾迹余韵
  ✈ ✈ ✈ ✈           \  |  /                     \  |  /
  梯队斜列            长机居中、僚机向它收拢         ＼ ｜ ／
  两句对话            【贴上长机的瞬间各自隐身】      × 交汇点
                     未贴上者窗口末强制淡出兜底     ／ ｜ ＼
                     「找点乐子」                 飞机没了，线还在
```

| # | at (s) | 通道 | 动作 | 参数 | dur | ease |
|---|---|---|---|---|---|---|
| 1 | 0.00 | `time` | `hard_pause(true)` | — | 瞬时 | — |
| 2 | 0.00 | `stage` | `clear` 清空舞台 | 见 §2.7 | 0.50 | `cubic_out` |
| 3 | 0.00 | `camera` | `cut_to` 切到长机并**持续跟随** | `follow=true, actor=0`，`zoom = 0.85`；手感 = 空格跟随（lerp 7.0/s） | 瞬时 | — |
| 4 | 0.00 | `actor` | `trail_boost` 尾迹增强 | 见 §2.11 | 瞬时 | — |
| 5 | 0.30 | `actor` | `echelon_ingress` 梯队平飞进场 | 见 §2.9 | — | — |
| 6 | 0.60 | `radio` | 第 1 句「目标发现，准备交战」 | `RADIO_BOSS_WRAITH_SPAWN_1` / `WRAITH-01`，`dur = 1.8` | — | — |
| 7 | 2.50 | `radio` | 第 2 句「收到」 | `RADIO_BOSS_WRAITH_SPAWN_2` / `WRAITH-02`，`dur = 0.9` | — | — |
| 8 | 3.50 | `radio` | 第 3 句「让我们来找点乐子吧」 | `RADIO_BOSS_WRAITH_SPAWN_3` / `WRAITH-01`，`dur = 1.8` | — | — |
| 9 | 3.60 | `actor` | `converge` 四线收拢至交汇点 | 见 §2.10 | 1.80 | — |
| 10 | 4.20 | `camera` | `zoom` 推近交汇点 | ×1.0 → ×1.30 | 1.40 | `cubic_in_out` |
| 11 | 5.40 | `actor` | `cloak_vanish` 集体隐身淡出 | `CLOAK_FADE = 0.5`，**仅淡机体不淡尾迹** | 0.50 | `cubic_in` |
| 12 | 5.90 | `actor` | `scatter` 散开（**已隐身，不可见**） | 见 §2.10 | — | — |
| 13 | 5.90 | `actor` | `trail_fade` 尾迹淡出 | a → 0 | 0.70 | `cubic_in` |
| 14 | 5.90 | `stage` | `restore` 世界淡回 | 见 §2.7 | 0.80 | `cubic_in_out` |
| 15 | 5.90 | `camera` | `return_to_player` | 复位 `cine_target`/zoom | 0.80 | `cubic_in_out` |
| 16 | 6.60 | `time` | `hard_pause(false)` | — | 瞬时 | — |
| 17 | 6.60 | `actor` | `release` + `trail_restore` | — | 瞬时 | — |

> **为什么"散开→合并成阵型"不占演出时长**：第 11 步之后四机已完全隐身不可见，
> 散开与重组阵型**没有观众**。故这两拍放在解暂停之后，由既有编队 AI 在隐身状态下自然完成 ——
> 玩家解除暂停时面对的是"四架看不见的敌机正在散开包抄"，正是分镜想要的压迫感，且**零时长成本**。
> 这是把 7 秒预算守住的关键。

> **隐身是演出专属视觉**（用户裁定 2026-07-20，推翻 v3~v9 的"真隐身接续战斗"方案）：
> `cloak_vanish` 只写 `_cloak_alpha`，**绝不碰** AceSquad 的隐身状态机 ——
> `_cloak_enter()` 会置 `_cloak_in_state`，而 PRE_STAGE 下状态机休眠、`_cloak_remaining`
> 永不倒数，实测四机**永久隐身**、玩家满地图找不到 BOSS。
> `release` 时三字段一起复位（`_cloak_alpha` / `is_cloaked` / `suppress_flares`），
> 剧情结束即解除；真隐身仍由战斗中的 110s±jitter 循环自行触发。

**导演不等无线电**（§3.5）—— 这些是入队时刻，不是保证出声时刻。

### 2.8.1 台词（用户定稿，2026-07-20）

**权威文本**。覆写既有 `RADIO_BOSS_WRAITH_SPAWN_1/2/3` 的内容（原文本随演出上线一并作废，
不留孤儿 key）。`RADIO_BOSS_WRAITH_ENGAGE_1` 不动。

| key | 说话人 | 中文 | English | 日本語 |
|---|---|---|---|---|
| `RADIO_BOSS_WRAITH_SPAWN_1` | `WRAITH-01` | 目标发现，准备交战 | Target sighted. Prepare to engage. | 目標発見。交戦準備。 |
| `RADIO_BOSS_WRAITH_SPAWN_2` | `WRAITH-02` | 收到 | Roger. | 了解。 |
| `RADIO_BOSS_WRAITH_SPAWN_3` | `WRAITH-01` | 让我们来找点乐子吧 | Let's have some fun. | 楽しませてもらおうか。 |

呼号轮转 `01 → 02 → 01`：第 1 句长机发现目标、第 2 句僚机应答（分镜第一格的双行对话）、
第 3 句长机收尾并卡在收拢起始点。

### 2.8.2 演出台词的时长覆写（必需，非优化）

`RadioChatter.line_duration(text) = clamp(2.6 + 0.035 × 字数, 2.6, 5.0)`
—— **基础时长 2.6s 封底**。按此公式本演出三句为 2.92 / 2.67 / 2.92s，
连播加间隔约 **8.5s**，比整段演出还长；「收到」两个字也要占 2.6s。

该公式是为**战斗中的 ambient 喊话**设计的（玩家分心时需要足够阅读时间），
而演出台词的时长是**编排出来的**，不该由字数反推。

故 `radio` 步骤支持 `dur` 覆写：

| 字段 | 行为 |
|---|---|
| `dur` 缺省 | 走 `line_duration(text)`，ambient 行为不变 |
| `dur` 给定 | 直接作为显示时长，绕开公式与封底 |

本演出取 `1.8 / 0.9 / 1.8`，三句含间隔约 5.0s，容纳于 6.6s 演出内且第 3 句正好覆盖收拢过程。

> ⚠ **覆写只允许演出用**。ambient 喊话不得传 `dur` —— 2.6s 封底是可读性下限，
> 战斗中缩短会让玩家根本来不及看。

### 2.9 第一幕：梯队平飞进场（`echelon_ingress`）

> ⚠⚠ **空间尺度必须从"速度 × 可见时长"反推，不能凭感觉给大数。**
> `PIXELS_PER_METER = 0.5`，故 1600 km/h ≈ **222 px/s**。初版 spec 写了 5200px 进场段 ——
> 那需要 **41 秒**才飞得完，演出结束时飞机还在画面外。所有距离都要先算再写。

| 字段 | 值 | 说明 |
|---|---|---|
| `ingress_dist` | **730 px** | 起点 = `anchor + inbound × 730 + offset`。= 1600 km/h × 3.3s 的可达距离（733px） |
| 可见时长 | `3.3 s` | 从 `at 0.30`（进场）到 `at 3.60`（收拢）之间 |
| `inbound` | 玩家→锚点的单位向量 | **从玩家机头前方飞来**，守"事件刷在沿途"约定 |
| 编队 | **右梯队（echelon）** | 偏移 `[(0,0), (-90,110), (-180,220), (-270,330)]`，沿 `inbound` 旋转。分镜第一格的斜列 |
| 逐机淡入间隔 | `0.35 s` | 复用 Poltergeist 的 `FADING` 模式 |
| 淡入时长 | `0.60 s` | 与 Poltergeist `FADE_IN_DURATION` 一致 |
| 平飞速度 | **1600 km/h** | = F-47 `cruise_speed`。730px / 3.3s 反解得 1593，取整 1600 |
| 高度分层 | 每机差 `120 m` | 交汇时四机不同高度 → 图标缩放不同，既避免糊成一团，也让交汇物理上说得通 |
| 镜头 zoom | **0.85** | 视野半宽 = 1920/2/0.85 ≈ 1129px，容得下 730px 进场段 + 编队展开 |

### 2.10 第二幕：交汇与散开（`converge` / `scatter`）

**交汇点** `CP = anchor + inbound × 250px`（锚点前方一点，让四条线在镜头中央交叉）。
250px 不是随手取的：它与 `CONVERGE_SEC = 1.8` 一起，决定了四机所需速度落在 **1000 ~ 2463 km/h**，全部在 F-47 的 `max_speed = 2800` 包线内。

| 字段 | 值 | 说明 |
|---|---|---|
| `CONVERGE_SEC` | `1.80` | 从梯队收拢到抵达 CP 的时长 |
| 目标点 | 四机**同一个** `CP` | 靠 §2.9 的高度分层避免同高度重叠 |
| 到点半径 | **`80px`**（覆写现状 `300px`） | 交汇必须"准"，300px 下四条线交不成一个点 |
| 抵达同步 | 各机速度按 `dist_i / CONVERGE_SEC` 反解 | 梯队里靠后的机要飞得快，保证**同时**抵达 —— 这是"四线同时汇于一点"的关键 |
| **速度包线** | 全部机位所需速度 ≤ 机体 `max_speed` | 超出会被钳速 → 同时抵达失效 → 交汇退化成"依次穿过"。这是**设计错误**而非运行时容错，代码里留 warning，无头断言逐机位守门 |
| `SCATTER_SEC` | 不限（解暂停后交由 AI） | 散开航向 = `CP` 出发的四向，间隔 `90°`，起始方位随机化避免每次一样 |
| 散开距离 | `2600px` | 到点后指令释放，编队 AI 接管重组 |

> ⚠ **到点半径必须可配**。现状 `_directive_follow_path_step` 把 `300.0` 硬编码在
> 到点判定里。交汇镜头要求 `80px`，这是阶段 2 的必改项，不是优化项。

> ⚠ **同步抵达要反解速度，不能给同一个速度**。梯队最后一架距 CP 比长机远约 1000px，
> 同速会导致四条线先后到达、交汇变成"依次穿过"，分镜效果全失。

### 2.11 尾迹的演出覆写（`trail_boost`）

分镜第三格「飞机没了、四条线还交汇在那儿」是整段演出的题眼，**全靠尾迹撑**。
现状尾迹撑不起来，演出期间需临时覆写（**仅 4 架演员**，退出时还原）：

| 字段 | 常规值 | 演出值 | 理由 |
|---|---|---|---|
| `max_points` | `80` | `240` | 80 点 @ 20Hz 采样 = **仅 4 秒尾迹**；900km/h 下约 500px，在 0.50 广角下只占屏宽 ~14%，画不出长线交汇。240 点 = 12 秒 ≈ 1500px ≈ 屏宽 43% |
| `ribbon_width` | `8.0` | `14.0` | 0.50 广角下 8px 只剩 4 屏幕像素，太细 |
| `ribbon_color` | 阵营色（敌=橙红） | 不变 | 分镜的红线即敌方阵营色，复用 `FactionPalette` |

> ✅ **尾迹天然免疫机体隐身淡出**（实现时验证，初版 spec 判断有误）。
> 机体的隐身淡出走 `self_modulate`，而 Godot 的 `self_modulate` **只影响节点自身、不向子节点传播**
> （向下传播的是 `modulate`）。`TrailRibbon` 作为飞机子节点因此不受影响 —— 分镜第三格
> "飞机没了、线还在"无需额外处理即成立。
>
> 反过来要注意：**空舞台压暗非演员用的是 `modulate`**，会连同它们的尾迹一起淡掉 —— 这正是想要的。

> **性能**：`max_points 80` 是当初从 300 砍下来的性能优化，**针对的是 22+ 架同屏**。
> 演出期间只有 4 架演员且世界已暂停（其余单位零开销），240 点完全安全。
> 但必须在 `release` 时还原，绝不能把 240 泄漏给常规战斗。

### 2.12 序列 JSON 结构

```json
{
  "upgrade_in": {
    "steps": [
      {"at": 0.00, "ch": "time",    "op": "request", "id": "upgrade", "to": 0.05, "dur": 0.15, "ease": "expo_out"},
      {"at": 0.06, "ch": "camera",  "op": "zoom",    "to": 1.12, "dur": 0.30, "ease": "back_out"},
      {"at": 0.10, "ch": "overlay", "op": "dim",     "from": 0.0, "to": 0.60, "dur": 0.18, "ease": "cubic_out"},
      {"at": 0.15, "ch": "time",    "op": "pause",   "to": 1},
      {"at": 0.16, "ch": "panel",   "op": "stagger_in", "stagger": 0.07, "dur": 0.22, "ease": "back_out"}
    ]
  },
  "wraith_arrival": {
    "max_sec": 7.0,
    "steps": [
      {"at": 0.00, "ch": "time",   "op": "pause", "to": 1},
      {"at": 0.00, "ch": "stage",  "op": "clear", "dur": 0.50, "ease": "cubic_out"},
      {"at": 0.00, "ch": "camera", "op": "cut_to", "anchor": "cine_anchor", "zoom": 0.50},
      {"at": 0.00, "ch": "actor",  "op": "trail_boost", "max_points": 240, "width": 14.0},
      {"at": 0.30, "ch": "actor",  "op": "echelon_ingress", "stagger": 0.35, "fade": 0.60,
       "speed": 900, "offsets": [[0,0],[-220,260],[-440,520],[-660,780]], "alt_step": 120},
      {"at": 0.60, "ch": "radio",  "op": "line", "key": "RADIO_BOSS_WRAITH_SPAWN_1", "actor": 0, "dur": 1.8},
      {"at": 2.50, "ch": "radio",  "op": "line", "key": "RADIO_BOSS_WRAITH_SPAWN_2", "actor": 1, "dur": 0.9},
      {"at": 3.50, "ch": "radio",  "op": "line", "key": "RADIO_BOSS_WRAITH_SPAWN_3", "actor": 0, "dur": 1.8},
      {"at": 3.60, "ch": "actor",  "op": "converge", "point": "cp", "dur": 1.80, "arrive_radius": 80},
      {"at": 4.20, "ch": "camera", "op": "zoom", "to": 1.30, "dur": 1.40, "ease": "cubic_in_out"},
      {"at": 5.40, "ch": "actor",  "op": "cloak_vanish", "dur": 0.50, "ease": "cubic_in"},
      {"at": 5.90, "ch": "actor",  "op": "scatter", "spread_deg": 90, "dist": 2600},
      {"at": 5.90, "ch": "actor",  "op": "trail_fade", "dur": 0.70, "ease": "cubic_in"},
      {"at": 5.90, "ch": "stage",  "op": "restore", "dur": 0.80, "ease": "cubic_in_out"},
      {"at": 5.90, "ch": "camera", "op": "return_to_player", "dur": 0.80, "ease": "cubic_in_out"},
      {"at": 6.60, "ch": "time",   "op": "pause", "to": 0},
      {"at": 6.60, "ch": "actor",  "op": "release"}
    ]
  }
}
```

字段：`at` 起始秒 / `ch` 通道 / `op` 动作 / `dur` 缺省=瞬时 / `ease` 缺省 `linear` /
`from` 缺省=通道当前值。未知 `ch` 或 `op` → 跳过并 `push_warning`，**不中断整条序列**
（热重载改坏 JSON 不能把游戏卡死）。

## 3. 行为与公式（How）

### 3.1 转场状态机

| 状态 | 时长/触发 | 效果 |
|---|---|---|
| `IDLE` | 默认 | `set_process(false)`，零开销 |
| `PLAYING` | `present()` / `dismiss()` / `play_cinematic()` | 每帧推进 `_elapsed`（**unscaled**），激活到期 step，插值活跃 step |
| `SETTLED` | 序列跑完且面板仍显示 | `set_process(false)`，通道保持终值 |

`PLAYING → PLAYING`：新序列打断旧序列。旧序列的**时间请求不自动释放**（由新序列显式接管），
插值 step 全部丢弃，通道停在当前值再从该值起插 —— 避免跳变。
跑完发 `sequence_finished(name)`。

### 3.2 unscaled delta 还原

导演 `_process(delta)` 收到的是被 `Engine.time_scale` 缩放过的 delta。演出时序必须与游戏
时间无关，否则时间缩到 0.05 后转场会慢 20 倍：

```
unscaled_delta = delta / max(Engine.time_scale, 0.001)
```

`process_mode = PROCESS_MODE_ALWAYS` 保证 `hard_pause` 期间仍收到 `_process`。

> ⚠ **本规则【不】适用于事件系统**（v9 审计修正，作废 v2~v8 的旧论述）：
> `_physics_process` 的 delta 是固定步长（1/60，**不随 time_scale 缩放** —— time_scale
> 缩的是 tick 频率），累加它天然跟踪游戏时间，与飞机物理同一时钟。若改成 unscaled，
> 命令轮盘 0.3× 期间事件计时会比世界快 3.3 倍 —— 护航拦截波次相对航线位置提前触发。
> hard_pause 期间物理根本不 tick，无漂移可言。**事件计时保持裸 delta。**
> unscaled 还原只适用于 `_process`（帧时间，确实被 time_scale 缩放）——即导演自身。

### 3.3 演员指令的所有权（关键安全约束）

导演**不自己持有** `AIDirective`。`actor` 通道的 step 一律**委托给发起本段演出的 `GameEvent`**
去下发：

```
play_cinematic(name, ctx):
    require ctx.owner is GameEvent      # 无 owner 则拒绝 actor 步骤
    actor step → ctx.owner.set_directive(unit, directive)
```

理由：`GameEvent.set_directive` 已经把 `owner_event` 设成弱引用，且事件结束时
`clear_all_directives()` 兜底。若导演另造一套所有权，一旦某条路径漏了清理，
**四架飞机会永远停在免战脚本模式**——屏幕上看着在飞但不打仗，不报错、不崩溃、极难查。
这比时间缩放泄漏更危险。一套所有权模型，不造第二套。

`actor.release` step 调 `ctx.owner.clear_all_directives()`，与 `BossEncounterEvent`
进入 ENGAGED 阶段的既有释放路径合并。

### 3.4 空舞台的进出

```
stage.clear:
    _stage_actors = ctx.actors                       # 演员集合
    对 CombatUnit.all_units 中的非演员: tween modulate.a → 0.0    # 一次性扫描
    地图层 modulate.a → STAGE_MAP_ALPHA
    HUD modulate.a → STAGE_HUD_ALPHA
    对每个演员及其 AIController: process_mode = ALWAYS

stage.restore:
    反向 tween（STAGE_RESTORE_SEC）
    对每个演员及其 AIController: process_mode = INHERIT
    _stage_actors.clear()
```

**全场扫描只在 clear / restore 各一次**，不进每帧（守性能守则第 2 条）。
淡出用 tween 驱动，非逐帧遍历。

**注册在案的失败模式**：演出中途有单位被 `queue_free`（例如恰好死亡的敌机），
`restore` 时其引用已失效 → 遍历必须 `is_instance_valid()` 守卫。
更稳的做法是 `restore` 不依赖 clear 时的快照，而是重新扫 `all_units` 把
**所有**非演员的 alpha 拉回 1.0（幂等，且自动覆盖演出期间新生成的单位）。本 spec 取后者。

### 3.5 无线电：编排权归演出，渲染权归无线电

**演出持有台词的内容 / 顺序 / 时机**（写在序列里），但台词**推进 `RadioChatter` 的显示队列**，
不另画字幕。

理由：无线电条是屏幕上唯一一个物理 UI 元素（CanvasLayer 19）。若演出绕过它直接写屏，
演出台词与 ambient 喊话会同屏叠字，且"绝不打断"契约会被从外部破掉。

| 规则 | 说明 |
|---|---|
| 入队方式 | `radio.say_text(trigger, speaker, color, text)`，`trigger` 标为 `scripted` |
| **导演不等无线电** | `radio` step 是**发射后不管**。若入队时正在念上一句，实际出声会推迟 —— 演出时序**不得**依赖无线电准点 |
| ambient 压制 | 演出开始时清空 / 暂缓 ambient 队列，scripted 优先。**需给 `RadioChatter` 加真正的压制 API**（现只有 test-only 的 `debug_clear_throttle`） |
| 演出结束 | 解除压制，ambient 恢复 |

若不加压制 API，最坏情况是队列里压着 3 句 ambient，BOSS 台词滞后到演出结束后才出声 ——
所以压制 API 是阶段 2 的必做项，不是可选项。

### 3.6 不可跳过

**已定决策：演出不可跳过。** 演出期间吞掉全部输入（`hard_pause` 已天然阻断玩法输入，
导演额外吞掉 ESC / Tab 以防中途开面板）。

代价与对冲：生存模式是无尽波次，同一段演出会被看几十遍。因此 `CINE_MAX_SEC = 7.0` 是
**设计约束而非技术约束** —— 任何超过 7 秒的演出方案应先砍内容，而不是放宽上限。

### 3.7 演出超时与异常收尾

演出是**唯一会长时间接管玩法状态**的机制，必须有兜底。

| 触发 | 处置 |
|---|---|
| `_elapsed > max_sec` | 强制执行收尾：`stage.restore` 瞬时完成、`hard_pause(false)`、`actor.release`、镜头复位 |
| 演员全部失效（`is_instance_valid` 全 false） | 同上，立即收尾 |
| 场景切换 / run reset / `_exit_tree` | `clear_all()`：时间栈清空、舞台复原、镜头复位、演员指令释放 |

**泄漏防护是本系统最高危的失败面**。三类泄漏各有后果：
时间栈泄漏 → 玩家卡在 0.05 倍速；舞台泄漏 → 世界永远隐形；演员指令泄漏 → BOSS 永不参战。
三者都必须有无头断言覆盖（见 §5）。

### 3.8 时间栈求解

```
func _solve() -> float:
    var m := 1.0
    for scale in _requests.values():
        m = min(m, scale)
    return m
```

每次 `request` / `release` 后重算目标，向其**混合**（非瞬跳），时长由调用方给。栈空 → 1.0。

### 3.9 present / dismiss 契约

```
present(panel, seq_name):
    panel.visible = true
    await get_tree().process_frame          # 等 Container 算出 size（见下）
    _bind_panel_elements(panel)
    对每个元素: modulate.a = 0, scale = 0.92, pivot_offset = size * 0.5
    play(seq_name)

dismiss(panel, seq_name):
    play(seq_name)
    await sequence_finished → panel.visible = false
```

**硬约束**：`dismiss` 的调用方必须在**调用之前**完成所有游戏状态恢复（升级效果生效、
`is_paused_for_upgrade = false`、鼠标状态重置）。导演只负责视觉。

**尺寸时序陷阱**：`pivot_offset = size * 0.5` 要求 `size` 已由 Container 布局算出，
而面板刚 `visible = true` 那帧 `size` 仍是 `Vector2.ZERO`。故必须等一帧。
这一帧（16ms）不计入序列时长。

## 4. 结构与组成（Structure）

### 4.1 部件

| 部件 | 类型 | 职责 |
|---|---|---|
| `PresentationDirector` | autoload `Presentation` | 序列运行器、通道分发、双 overlay 持有、F8 热重载 |
| `TimeAuthority` | RefCounted | 时间请求栈 + `Engine.time_scale` / `get_tree().paused` 唯一写入点 |
| `SequencePlayer` | RefCounted | 单条序列的 step 推进与插值 |
| `StageIsolator` | RefCounted | 空舞台的 clear / restore + 演员 `process_mode` 切换 |
| `EaseLib` | 静态类 | §2.5 缓动函数表 |
| `sequences.json` | 资源 | 全部时长 / 曲线 / 幅度 / 台词时刻 |
| dim `CanvasLayer` | 导演子节点 | layer 16，全屏 `ColorRect` |
| fx `CanvasLayer` | 导演子节点 | layer 25，全屏 `ColorRect`（闪白 / 渐黑） |

### 4.2 通道（ch）→ 目标解析

| ch | 目标 | 绑定时机 | 能写玩法状态？ |
|---|---|---|---|
| `time` | `TimeAuthority` | 常驻 | 是（暂停 / 缩放） |
| `camera` | `CameraController` | `bind_camera()` | 否 |
| `overlay` | dim / fx ColorRect | 常驻 | 否 |
| `panel` | 当前 `present` 的面板元素 | 每次 `present` | 否 |
| `radio` | `RadioChatter` | `bind_radio()` | 否 |
| `stage` | `StageIsolator` | 常驻 | 是（`process_mode`） |
| `actor` | **委托 `ctx.owner`（GameEvent）** | 每次 `play_cinematic` | **是（AI 指令）** |

后两条是能写玩法状态的通道，是全系统的风险集中区，对应 §3.3 / §3.4 / §3.7 的约束。

### 4.3 面板接入协议

```gdscript
func get_transition_elements() -> Array[Control]
```

返回**按错开顺序排列**的 Control 数组。未实现的面板 → 退化为整体淡入。

升级面板元素顺序：`[_title, _buttons[0], _buttons[1], _buttons[2]]`。
（`_overlay` **不**进数组 —— 遮罩由 `overlay` 通道统一管；升级面板自持的 `_overlay` 接入后移除。）

### 4.4 与事件系统的边界

`GameEvent` 现在**没有任何 signal**，生命周期 `_start / _update / _finish` 全靠
`EventDirector._physics_process` 轮询；`scripts/events/` 下 `await` / `Tween` / `time_scale`
**零使用**。所以本系统是事件系统的**第一条表演通道**。

| 决定 | 内容 |
|---|---|
| **不造通用 beat API** | 现有事件子类只有 3 个，其中 AWACS 刻意无表演面、护航只有 3 句 `show_temp`，真实样本只有 BOSS 一个。从 1 个样本泛化通用 API 是过度设计。等第 2、3 个演出出现再抽 |
| 访问方式 | `Presentation` 挂成 `EventDirector` 的字段，事件经已有的 `director` 引用够到。**不新增第四套访问 idiom**（现已有 `.get("_zone_hint")` / `._zone_hint` / 全局单例三套） |
| 首个迁移目标 | BOSS "engaged" 节拍现**撕在两个文件**：横幅+无线电在 `survivor_mode.on_boss_engaged`，BGM+HUD 标志在 `BossEncounterEvent._enter_engaged`。合并进演出序列 |
| 既有仲裁不得打架 | `ZoneHint` 的"temp 覆盖 persistent 再恢复"优先级规则；`RadioChatter` 的"绝不打断"队列 |

### 4.5 复用清单（不重写）

| 能力 | 既有实现 |
|---|---|
| 逐架淡入 | `PoltergeistSquad` 的 `FROZEN → FADING` 模式（`FADE_IN_DURATION = 0.6`、`modulate.a` lerp） |
| 物理航路飞行 | `AIDirective.follow_path` —— **已造好、已接线、全项目零使用**，现成钩子 |
| 免战 | `AIDirective.combat_disabled`（默认 true，每帧 `clear_combat_target()`） |
| 台词队列 | `RadioChatter.say_text` + `scripted` 豁免节流与淘汰 |
| BOSS 台词内容 | `RADIO_BOSS_WRAITH_SPAWN_1/2/3` 三语已在 `translations.csv`；序列在 `radio_chatter.json` |
| 脚本化进场 | `BossEncounterEvent` PRE_STAGE 的 `fly_to(..., combat_disabled=true)` |
| 镜头 lerp | `CameraController.target_zoom` / `_update_follow` |
| 音乐切层 | `AudioManager.play_layered_music` / `crossfade_music` / `set_music_muffled` |

> **本质上 `PoltergeistSquad` 已经是一段手写的演出**（逐架淡入 0.6s、间隔 1.4s 依次弹射、
> 弹射期锁高度清目标、起飞 4s 宽限期无敌免锁）。本系统的价值就是把这个模式从 BOSS 子类里
> 抽成数据。阶段 3 可考虑把 Poltergeist 反向迁移到序列驱动。

## 5. 验收标准（Acceptance / Litmus）

**无头**（`--bench=presentation`）：
- [ ] 时间栈：多请求取最小值；同 id 覆盖不叠加；release 回 1.0；`clear_all` 清空
- [ ] **时间泄漏**：任意 present/dismiss 配对后 `Engine.time_scale == 1.0`；中途 `clear_all` 亦然
- [ ] **舞台泄漏**：`clear` → `restore` 后全部非演员 `modulate.a == 1.0`；演出中途单位失效不阻断 restore
- [ ] **演员泄漏**：演出结束后全部演员 `_directive == null`；超时路径同样释放
- [ ] 超时：`_elapsed > max_sec` 触发强制收尾，三类状态全复原
- [ ] 序列：`upgrade_in` 总时长 0.44s、`wraith_arrival` 6.40s；每 step 在 `at` 激活、`at+dur` 到终值
- [ ] 缓动：6 个函数 `f(0)=0` / `f(1)=1`；`back_out` 在 `t≈0.7` 处 > 1.0（确有过冲）
- [ ] unscaled：`Engine.time_scale = 0.05` 下序列推进速度与 1.0 时一致（误差 < 1 帧）
- [ ] 坏 JSON：未知 ch/op 被跳过且序列仍跑完
- [ ] `actor` 步骤在无 `ctx.owner` 时被拒绝（不静默下发）
- [ ] `--bench=all` 无回归

**引擎内**（生存模式 F5）：
- [ ] 升级：世界急刹 ~0.15s → 镜头微推 → 标题+3 卡错开弹入，总时长约 0.44s
- [ ] 选卡后升级效果**当帧**生效（EventLogger 确认），面板齐退，时间弹回 1.0
- [ ] **鼠标回归**：选卡后立刻按住拖拽，无卡死的 `is_dragging`（原代码专门修过：暂停吞 release）
- [ ] Wraith 三幕：梯队平飞+两句对话 → 四线收拢交汇+「交战自由」→ 交汇瞬间集体隐身淡出 → 尾迹余韵 → 世界淡回
- [ ] **交汇成点**：四条尾迹在 CP 汇于一点（非依次穿过）—— 验证速度反解生效、到点半径 80px 生效
- [ ] **题眼镜头**：机体消失后尾迹仍在，四线交叉于一点后才淡出（验证尾迹未继承机体 alpha）
- [ ] 尾迹够长：0.50 广角下单条尾迹约占屏宽 40%+（验证 `max_points 240` 覆写生效）
- [ ] `release` 后尾迹参数还原为 `80 / 8.0`（**不得泄漏给常规战斗**，这是性能红线）
- [ ] 隐身接续：解暂停后四机仍隐身约 5s，随后正常进入 110s+jitter 循环；玩家开局面对看不见的敌人
- [ ] 演出期间玩家绝对安全（世界冻结），演出结束后玩家机与敌人状态与演出前一致
- [ ] 演出中飞行是**真物理**：四机有真实坡度、转弯半径、速度，与常规飞行无视觉差异
- [ ] 无线电条在演出期间**不被压暗**（DIM_LAYER=16 生效）
- [ ] 台词三句按序出现，不与 ambient 喊话叠字
- [ ] 命令轮盘 0.3× 与升级急刹叠加后，退出时 `Engine.time_scale` 干净回 1.0
- [ ] F8 热重载：改 JSON 存盘后按 F8 立即生效；导出包中 F8 无效
- [ ] 性能：Sentinel + Lv5+ 压测，转场/演出期间 FPS 掉幅 < 15；`IDLE` 时 `_process` 已关闭
- [ ] 已知 seam：新增耦合点补进 `architecture/known-seams.md`
- [ ] 台词按 §2.8.1 逐字上屏，呼号轮转 `01 → 02 → 01`
- [ ] 台词时长为编排值 `1.8 / 0.9 / 1.8`（非公式反推），三句在演出内播完
- [ ] i18n：`RADIO_BOSS_WRAITH_SPAWN_1/2/3` 三语已按 §2.8.1 覆写

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 地基 + 升级急刹（最小闭环）—— **代码已落地 2026-07-20，差引擎内 playtest**
- [x] `scripts/presentation/ease_lib.gd` —— §2.5 六个缓动函数
- [x] `scripts/presentation/time_authority.gd` —— 请求栈 / 混合 / `clear_all` / pause 入口
- [x] `scripts/presentation/sequence_player.gd` —— step 推进 + 插值 + 容错跳过
- [x] `scripts/presentation/presentation_director.gd` —— 通道分发 / 双 overlay(16/25) / present / dismiss
- [x] `resources/presentation/sequences.json` —— `upgrade_in` + `upgrade_out`
- [x] F8 热重载（`OS.has_feature("editor")` 门控）+ `debug_replay(name)`
- [x] `project.godot` 注册 autoload `Presentation`（置于 `AudioManager` 之后）
- [x] `camera_controller.gd` —— `_base_zoom` 拆分 + `cine_zoom_mult` / `cine_offset` / `cine_shake` / `cine_reset`
      （`cine_target` 未做：它只服务 BOSS 演出的镜头切换，随阶段 2 的 `cut_to` / `return_to_player` 一起落）
- [x] `survivor_mode.gd` —— `bind_camera` / 场景退出与 run reset 时 `clear_all`
- [x] `survivor_upgrade_ui.gd` —— `show_choices` 拆为 `populate()` + `get_transition_elements()`；移除自持 `_overlay`
- [x] `survivor_mode.gd` 升级触发点走 `present`；选卡点走 `dismiss`，**状态恢复前置**
- [x] `scripts/tests/test_presentation.gd`（52 断言）+ 注册 `bench_runner.gd` 的 `UNIT_TESTS["presentation"]`
- [x] `--bench=presentation` 52/52 + `--bench=all` 25 套件全绿
- [ ] **引擎内 playtest** —— §5「引擎内」条目全部待验

### 阶段 2 — Wraith 登场演出（完整闭环）—— **代码已落地 2026-07-20，差引擎内 playtest**
- [x] `scripts/presentation/stage_isolator.gd` —— clear / restore + 演员 `process_mode` 切换 + 幂等复原
- [x] `actor` 通道 —— 委托 `ctx.owner.set_directive`，无 owner 则拒绝（§3.3）
- [x] `radio` 通道 + `RadioChatter` 的 **ambient 压制 API**（`suppress_ambient(bool)`，非 debug 接口）
- [x] `RadioChatter` 支持**演出台词时长覆写**（`dur` 参数绕开 2.6s 封底，仅演出可用，§2.8.2）
- [x] `translations.csv` 覆写 `RADIO_BOSS_WRAITH_SPAWN_1/2/3` 三语（§2.8.1 权威文本）
- [x] `camera` 通道扩展 —— `cut_to` / `return_to_player` / `cine_target`
- [x] **`FOLLOW_PATH` 到点半径改为可配**（现 `300.0` 硬编码，交汇需 `80`）
- [x] `echelon_ingress` op —— 梯队偏移 + 高度分层 + 逐机 stagger 淡入 + `follow_path` 下发
- [x] `converge` op —— 四机同点 + **按距离反解各机速度保证同时抵达**（同速会毁掉交汇效果）
- [x] `cloak_vanish` op —— 接 `AceSquad` 隐身状态机（真隐身非特效，接续进战斗）
- [x] `scatter` op —— 四向 90° 散开，起始方位随机化
- [x] `trail_boost` / `trail_fade` / `trail_restore` op —— `max_points 80→240`、`width 8→14`，**退出必还原**
- [x] **`TrailRibbon` 脱离父级 alpha 继承**（改 `self_modulate` 或只淡机体精灵）—— 不做则题眼镜头不成立
- [x] `sequences.json` 加 `wraith_arrival`
- [x] `BossEncounterEvent` —— PRE_STAGE 改走 `play_cinematic`；合并 `on_boss_engaged` 那半边节拍
- [x] `EventDirector` —— 持 `Presentation` 字段；**事件计时改 unscaled delta**（§3.2）
- [x] 超时与异常收尾（§3.7）+ 三类泄漏断言
- [x] 命令轮盘 `Engine.time_scale` 收编进时间栈
- [ ] **引擎内 playtest** —— 交汇是否真汇成一点 / 尾迹余韵观感 / 隐身接续战斗

### 阶段 3 — 待 playtest 后决定（本批不做）
- [ ] 编队特技（分裂 / 交叉 / 拉起）—— 需先给 `FOLLOW_PATH` 加编队相对路径 + 可配到点半径 + 速度时序
- [ ] `PoltergeistSquad` 反向迁移到序列驱动
- [ ] 其余 BOSS 登场演出（Mother Goose / Carrier Strike Group）
- [ ] 场景切换淡出淡入（主菜单 ↔ 生存模式）
- [ ] `tactical_map` / `boundary_ui` / `evolution_ui` 接入转场
- [ ] 击杀特写 / `shake` 接入受击反馈

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 导演主逻辑 | `scripts/presentation/presentation_director.gd` |
| 时间栈 | `scripts/presentation/time_authority.gd` |
| 序列运行器 | `scripts/presentation/sequence_player.gd` |
| 空舞台 | `scripts/presentation/stage_isolator.gd` |
| 缓动函数 | `scripts/presentation/ease_lib.gd` |
| 序列数值 | `resources/presentation/sequences.json` |
| 镜头电影层 | `scripts/camera_controller.gd` |
| 升级面板接入 | `scripts/survivor/survivor_upgrade_ui.gd` |
| 升级触发/解除 | `scripts/survivor/survivor_mode.gd` |
| BOSS 演出接入 | `scripts/events/boss_encounter_event.gd`、`scripts/events/event_director.gd` |
| Wraith 中队 | `scripts/survivor/f47_ace_squad.gd`、`scripts/survivor/ace_squad.gd` |
| 演员指令 | `scripts/events/ai_directive.gd`、`scripts/events/game_event.gd` |
| 无线电压制 | `scripts/survivor/radio_chatter.gd` |
| autoload 注册 | `project.godot` |
| 无头测试 | `scripts/tests/test_presentation.gd`，注册于 `scripts/bench/bench_runner.gd` |
| reference 索引行 | `script-index.md` / `code-index.md` 的 presentation 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-20 | 1 | 初稿。三块结构（时间栈 / 序列运行器 / 通道）+ 升级急刹转场定稿 |
| 2026-07-21 | 12 | **演出配乐**（playtest 反馈：debug 跳 BOSS 后没有 BOSS 曲）。查证：音乐切换本来只在 ENGAGED（玩家进圈 2200px / 贴近成员 2500px），PRE_STAGE 刻意不切 —— 非 bug；但登场演出出现后该设计成了气氛断档（6.7s 大阵仗配巡航曲）。新增 **audio 通道**（op `boss_bgm`，ctx 快照 `bgm_layers/bgm_track`，导演不认识 encounter），wraith 序列 0.2s 即切 BOSS 曲；`_enter_engaged` 原切歌点保留（服务无演出 BOSS）但加幂等守卫 —— `crossfade_music` **没有同曲早退**，不守卫会把在播的 BOSS 曲重启。AudioManager 新增 `current_music_id()`（crossfade/layered 均记录）作为幂等依据 |
| 2026-07-21 | 11 | **playtest 三轮（探针驱动）**。①全程隐形根因终于实锤：演员被离屏 LOD 藏着（`visible=false + lod_level=2`），该扫描在演出 hard_pause 期间不跑 —— alpha 全对但 visible 永远 false。`_set_actor_awake` 唤醒时强制 `visible=true + lod_level=0`，演出后 LOD 自行接管；②收尾瞬移根因：scatter 四向均布必有一架朝玩家甩 → 贴脸误触 ENGAGED → engage 摆位瞬移。散开改**背向玩家 135° 扇面**（fan_deg），兼收'往战区深处包抄'；③隐身触发改**交汇驱动**（用户分镜 v2）：新 op `cloak_on_meet`（radius=100 / fade=0.35 / 窗口 3.4~5.9）—— 每架僚机贴上长机即各自淡出、长机随首次交汇淡出、未触发者窗口末强制兜底，替换定时 `cloak_vanish`；④物理教训：交汇反解 2400 km/h 时转弯半径 ~2500px、僚机切不进 CP —— 编队间距减半 + 交汇窗口 1.8→2.0s 把速度压回巡航量级；**触发半径必须 < 编队最小间距**（160>110 时收拢刚开始就误触发）。探针复核：visible 全程 true、镜头咬住长机 11~50px、无瞬移、PRE_STAGE 不误触、四机淡出集中在 5.5±0.3s |
| 2026-07-21 | 10 | **playtest 二轮修正（两项均为用户裁定）**：①镜头改**跟随长机**（`cut_to` 加 `follow/actor` 参数 + `cine_follow_tick` 暂停期代泵；原定点看锚点 = 盯着战区正中央的空气，飞机在画面外进场）。进场 step 必须排在 cut_to 之前（同 at 靠数组序执行，切镜要读演员传送后的定位），断言守门；②**隐身回退为演出专属视觉**：v9 接真隐身状态机是错的 —— PRE_STAGE 下状态机休眠、`_cloak_remaining` 永不倒数 → 永久隐身。现 `cloak_vanish` 纯视觉、`release` 三字段复位解除。另修：演员传送后未清尾迹 —— 丝带把"远端出生点→演出起点"连成横贯地图的巨线，`echelon_ingress` 传送后 `clear_trail()` |
| 2026-07-20 | 9 | **全面审计（模型切换后复查），修 7 个实现错误**：①`RadioChatter` 无 `PROCESS_MODE_ALWAYS` —— hard_pause 期间台词泵冻结，Wraith 三句对话全部积压到演出结束后连播（演出对话全灭）；②镜头应用循环在 survivor_mode._process、暂停期不跑 —— 演出中段推近与升级 zoom punch 只改系数从不落到镜头；导演在 `paused 或 time_scale<0.999` 时代泵 `update_zoom`；③`echelon_ingress` 机头方向 180° 反了（`+basis` 应为 `-basis`）—— 四机背对目标出生、开场就地掉头；④`StageIsolator` 对 CanvasLayer（hud/zone_arrow）写 `modulate` —— **CanvasLayer 没有该属性**，运行时报错中断循环、HUD 藏不掉（spec 自己写过的教训又踩了一遍）；改 `_set_alpha` 助手、CanvasLayer 走 visible；⑤converge 逐机反解速度是死参数（无消费方）—— 同时抵达失效、交汇退化依次穿过；`_directive_follow_path_step` 消费 `target_speed` + 超巡航自动点加力，scatter 归还巡航速防加力泄漏；⑥`cloak_vanish` 只写 `_cloak_alpha` 纯视觉 —— 解暂停后状态机把 alpha 拍回 1.0 当场显形且无锁定免疫；改为置位 `_cloak_enter()` 真隐身状态机 + 终态 `is_cloaked/suppress_flares`；⑦事件计时 unscaled 化是**错误修复**（§3.2 论述有误：physics delta 是固定步长，除以 time_scale 反而让事件比世界快）—— 已回退并修正 spec。另修：演出 release 后事件仍 PRE_STAGE 但指令全清、状态机停摆 —— `sequence_finished` 一次性钩子重下巡逻指令（隐身下飞回锚点绕环 = 分镜'散开→合并阵型'的涌现实现）+ 补持久提示；`TimeAuthority.hard_pause` 去掉 `_paused==on` 早退（debug 面板直写 tree.paused 时会让解除变 no-op → ESC 后主菜单卡死）；`StageIsolator.restore` 加 `_active` 闸防 force_restore 后回暗闪烁。回归门 31 项全绿；**引擎内观感仍全部待验** |
| 2026-07-20 | 8 | **playtest 回归修复**：战术地图打开后整个变黑。根因 —— 压暗层写死在 CanvasLayer 16，而战术图自己在 **15**，遮罩盖在了它上面。压暗层高度改为按被展示面板动态求解 `min(DIM_LAYER, panel.layer − 1)`：面板在 20 → 16（无线电 19 / 战区提示 18 仍在亮处），面板在 15 → 14。`clear_all` 复位回默认值。新增 `dim.*` 逐面板无头断言守门 |
| 2026-07-20 | 7 | **阶段 2 收尾补漏**。上一版用批量替换给阶段 2 打勾，虚标了两项：①**Wraith 三句台词从未落到 CSV**（spec §2.8.1 写了、代码里还是旧文案）—— 已按用户定稿覆写三语并 import 验证；②**tactical_map / boundary_ui / evolution_ui 未接入导演** —— 已补：新增通用 `panel_in`/`panel_out` 序列（比升级急刹轻，玩家主动打开的面板不需要"游戏为我停了一下"的仪式感），三者的 `get_tree().paused` 全部收编进时间栈。`dismiss()` 增加 `hide_node` 参数，供"CanvasLayer 还有别的东西要继续画"的面板（boundary_ui 的越界警告）指定只隐藏子节点。另修一处三处同款 bug：`return [_root] if _root else []` 的**无类型数组字面量无法转成 `Array[Control]`**，运行时报错后静默退化到导演兜底路径（单元素面板下恰好等价，故功能没露馅但日志持续刷错）—— 改为显式构造 typed array。全局仅剩 0 处直写 `get_tree().paused`（F9 那条保险也改走时间栈：直写会让 TimeAuthority 仍以为处于暂停态，下次 `hard_pause(true)` 因状态相同被跳过）|
| 2026-07-20 | 6 | **阶段 2 代码落地**（空舞台 StageIsolator / 演员 CinematicCast / stage·actor·radio 三通道 / 无线电 dur 覆写 + ambient 压制 / FOLLOW_PATH 到点半径可配 / 镜头 cut_to·return_to_player·cine_target / 命令轮盘收编时间栈 / 事件计时改 unscaled）。`--bench=presentation` 75 断言 + 回归门 31 项全绿。实现中修正 spec 两处**会误导重建**的错误：①**空间尺度算错**（§2.9）—— 初版写 5200px 进场段，但 `PIXELS_PER_METER=0.5` 下 1600km/h 仅 222px/s，5200px 要飞 **41 秒**；同理交汇几何要求 **7600 km/h**（6 马赫），远超 F-47 `max_speed=2800`，会被钳速导致四机无法同时抵达、交汇退化成"依次穿过"。全部重算：进场 730px / CP 前移至 250px / 编队偏移缩至 (-270,330) / zoom 0.50→0.85，四机所需速度落在 1000~2463 km/h。新增逐机位包线断言守门。②**尾迹继承判断有误**（§2.11）—— 机体隐身走 `self_modulate`，Godot 中它只影响自身不传子节点，尾迹天然免疫，无需额外处理；原 ⚠ 已改为 ✅ 并说明反向注意点（空舞台压暗用 `modulate`，会连尾迹一起淡，这是想要的） |
| 2026-07-20 | 5 | **阶段 1 代码落地**（导演/时间栈/序列运行器/缓动/双 overlay/镜头电影层/升级面板接入），`--bench=presentation` 52 断言 + `--bench=all` 25 套件全绿。实现中修正 §2.3 三处数值/约束：①**错开跨度不变式** `dur ≥ elem_dur + stagger×(n−1)` —— 首版把 `dur` 当单元素时长，导致第 3 张卡进度只跑到 4.5%、永久停在全透明；拆出 `elem_dur` 并加断言守门，总时长 0.44→**0.54s**。②**元素须先压 alpha 0 再 visible** —— 否则等 Container 算 size 的那一帧面板会全不透明闪现，正是本系统要消灭的突兀本身。③`upgrade_out` 总时长 0.20→**0.30s**（原值漏算 camera 归位 0.02+0.28）。`cine_target` 推迟到阶段 2 与 `cut_to`/`return_to_player` 一起落 |
| 2026-07-20 | 4 | 台词改用户定稿三句（§2.8.1，覆写既有 `SPAWN_1/2/3` 三语）：「目标发现，准备交战」/「收到」/「让我们来找点乐子吧」。发现时长冲突 —— `line_duration` 有 **2.6s 封底**（「收到」两字也占 2.6s），三句连播约 8.5s 超过整段演出，故新增**演出台词时长覆写**（§2.8.2，`dur` 绕开公式，仅演出可用；ambient 保留封底作为可读性下限）。取 1.8/0.9/1.8，第 3 句正好覆盖收拢过程 |
| 2026-07-20 | 3 | Wraith 演出按用户分镜定稿三幕（§2.8~§2.11）：梯队平飞两句对话 → 四线收拢交汇成点 + 交汇瞬间集体隐身淡出 → 尾迹余韵。既有三句台词逐拍对上分镜（第 2 句「我们是隐形的」预告隐身、第 3 句「交战自由」卡散开），无需新增 i18n。关键实现约束三条：**尾迹须脱离父级 alpha 继承**（否则题眼镜头不成立）、**尾迹演出期覆写 max_points 80→240**（现状仅 4s 尾迹画不出长线交汇，退出必还原）、**交汇须按距离反解各机速度**（同速会变成依次穿过）。散开/重组移到解暂停后隐身状态下完成，零时长成本，守住 7s 上限；登场隐身是真隐身并接续进战斗，使演出本身成为 BOSS 机制教学 |
| 2026-07-20 | 2 | 扩为完整演出系统。新增：空舞台隔离（§2.7/§3.4，用户"假空间"方案）、Wraith 登场序列（§2.8/§2.9）、`radio`/`stage`/`actor` 三条通道、演员指令所有权委托（§3.3）、演出超时收尾（§3.7）、与事件系统的边界（§4.4）、双 overlay 层拆分（16/25，避免压暗无线电）、事件计时改 unscaled。决策：不可跳过 + 7s 硬上限、不造通用 beat API、特技推迟到阶段 3 |
