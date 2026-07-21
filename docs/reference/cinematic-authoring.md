# 演出编排方法论（Cinematic Authoring）

> 给"下一段演出"的作者看的。本文是**方法论与陷阱清单**，数值权威在
> [specs/systems/ui-transition.md](../specs/systems/ui-transition.md)。
> 每一条都来自 Wraith 登场演出（2026-07-20~21）实际踩过的坑 —— 共 15+ 个，
> 其中约一半是无头测试全绿、进引擎才炸的。

## 0. 三权分立（先想清楚谁管什么）

| 权 | 归属 | 铁律 |
|---|---|---|
| 视觉（镜头/时间/遮罩/尾迹/透明度） | 表演导演 | 随便折腾，但 release 必须**全部复原** |
| 台词 | 演出编排内容与时机；**渲染仍走 RadioChatter 显示带** | 发射后不管，不得依赖出声准点 |
| AI/玩法状态 | **只经 GameEvent.set_directive 借用** | 导演不持有指令；演出结束重建事件自己的阶段契约 |

**核心教训（隐身事件）**：演出想要某个玩法机制的"样子"时，**只借它的视觉语言，
不要动它的状态机**。真隐身状态机在 PRE_STAGE 下休眠、计时器不倒数 → 一置位就是永久隐身。
演出效果的生命周期必须 ≤ 演出本身；凡是"演出结束后还生效"的状态，都要问一句：
**谁负责把它关掉？答不出来就不许开。**

## 1. 开工前四问（每问漏一个都出过事故）

1. **空间尺度从速度反推了吗？** `PIXELS_PER_METER = 0.5`：1600 km/h ≈ 222 px/s。
   所有距离 = 速度 × 可见秒数，先算再写。历史事故：5200px 进场段需 41 秒，演出结束时飞机还在画面外；
   交汇几何一度要求 6 马赫。
2. **暂停语义三查**：演出全程 `hard_pause`，逐个确认——
   - 每个要动的系统**谁在泵**？（镜头应用在 survivor_mode._process → 暂停即死，导演须代泵）
   - 每个要动的节点 `process_mode` 是什么？（RadioChatter 没设 ALWAYS → 台词全部积压到演出后）
   - 用哪个时钟？`_process` 的 delta 被 time_scale 缩放（需 unscaled 还原）；
     `_physics_process` 的 delta 是**固定步长**（缩的是 tick 频率，**不许**除 time_scale，
     否则事件计时比世界物理跑得快）。
3. **每个参数有消费方吗？** 往 `directive.params` 里塞值 ≠ 生效。交汇的逐机反解速度写进了
   JSON、写进了 spec、写了断言 —— 但 `_directive_follow_path_step` 根本不读它，
   断言只验了数据不验消费链。**新参数落地 = 写入方 + 消费方 + 一条穿透两端的验证。**
4. **命名契约核对了吗？** 派生名（如 `boss_id.to_lower() + "_arrival"`）对不上就**静默回落**，
   不报错 —— 症状是"只有无线电、镜头不动"。已有断言 `arrival.*` 双向校验，新演出照抄。

## 2. 引擎陷阱速查（都是本项目真踩过的）

| 陷阱 | 后果 | 对策 |
|---|---|---|
| CanvasLayer **没有 `modulate`** | 运行时报错中断循环，HUD 藏不掉 | `StageIsolator._set_alpha`：CanvasLayer 走 `visible` |
| Container 每帧覆写子节点 `position/size` | 位移动画被吃掉 | 只动 `scale` + `modulate`；先设 `pivot_offset` |
| `self_modulate` 不向子节点传播 | （反向好消息）机体隐身不会带走尾迹 | 机体淡出用 `self_modulate`，全灭用 `modulate` |
| 传送飞机后尾迹丝带连出巨线 | "出生点→演出起点"横贯地图 | 传送后 `clear_trail()` |
| heading 约定：0=北、方向 d 的 heading = `d.angle()+PI/2` | 方向差 180° 开场就地掉头 | 用**行进方向**（不是进场轴）算 heading |
| 无类型数组字面量转不成 `Array[Control]` | 运行时报错后**静默走兜底** | 显式构造 typed array |
| `visible = true` 早于压 alpha | 等布局那帧全不透明闪现 | 先压 alpha 0 → visible → 等帧 → pivot |
| 错开动画 `dur` 当单元素时长 | 最后一个元素永久停在半透明 | `dur ≥ elem_dur + stagger×(n−1)`，断言守门 |
| 压暗层高度写死 | 战术图（layer 15）被自己的遮罩盖黑 | `min(DIM_LAYER, panel.layer − 1)` |
| 状态记账早退（`if _paused == on: return`） | 外部直写 tree.paused 后解除变 no-op | 幂等写入，以引擎实际状态为准 |
| 离屏 LOD 把远端敌机 `visible=false`，而 LOD 扫描在演出暂停期不跑 | 演员 alpha 全对却**全场隐形**（尾迹可见、机体不见） | `_set_actor_awake`：唤醒即 `visible=true + lod_level=0` |
| 散开方向均布 → 必有一架朝玩家 | 贴脸误触 ENGAGED，engage 摆位当场瞬移 | 散开取**背向玩家的扇面**（`fan_deg`） |
| 高速 = 巨转弯半径（2400 km/h ≈ 2500px 半径） | "汇聚成一点"物理上切不进去 | 收紧编队 + 拉长窗口把反解速度压回巡航量级；交汇触发半径必须 **< 编队最小间距** |
| `crossfade_music` 无同曲早退 | 演出切过 BOSS 曲后，交战切歌点把同一首**重启** | 用 `AudioManager.current_music_id()` 幂等守卫再切 |

## 3. 镜头方法论

- **跟主体，不看地点。** `cut_to` 定点看锚点 = 盯着空气；正确做法是 `follow=true` 咬住长机
  （`cine_target` + 暂停期 `cine_follow_tick` 代泵），手感对齐空格跟随。
- 步骤顺序：**先传送演员、再切镜**（同 `at` 靠数组序执行，切镜要读演员定位）。
- 归位（`return_to_player`）一开始就清 `cine_target` —— 别追着隐身/散开的目标跑。
- zoom 全走 `cine_zoom_mult`（乘法叠加层），绝不直改 `camera.zoom`（回读反馈环会自乘发散）。

## 4. 收尾契约（泄漏是最高危故障面）

release / 超时 / clear_all 三条路径都必须复原全部四类状态，且**幂等**：

1. 时间（栈清空 + 解除暂停）→ 泄漏 = 卡 0.05 倍速
2. 舞台（全场 alpha 拉回，**重扫而非快照**——中途有单位生灭）→ 泄漏 = 世界隐形
3. 演员（指令经 owner 清 + 尾迹参数还原 + 演出视觉状态复位）→ 泄漏 = BOSS 永不参战 / 永久隐身
4. 事件阶段契约（PRE_STAGE 需重下巡逻指令 + 补持久提示）→ 漏掉 = 状态机停摆、AI 乱飞

## 5. 验证阶梯（各层能抓什么、抓不了什么）

| 层 | 能抓 | 抓不了 |
|---|---|---|
| 无头断言（`--bench=presentation`） | 数值/时序/配平/命名契约/几何包线 | 一切引擎交互 |
| SceneTree 探针（临时脚本真跑 present/dismiss） | 暂停语义、typed array、首帧闪现、泄漏 | 视觉观感、多系统合流 |
| 引擎内肉眼（F6 → 跳 BOSS，F8 热重载调参） | 层叠遮挡、镜头手感、节奏、"到底好不好看" | —— |

**规律：本次 15+ 个 bug 里，凡是"暂停下谁在跑"“属性存不存在”“方向对不对"这类引擎事实，
无头层全部漏过。** 所以新演出**必须**走完第三层才算完成，前两层绿≠能玩。

## 6. 新增一段登场演出的最短路径

1. 序列名 = `<boss_id 小写>_arrival`（命名契约，断言会查）
2. 在 `sequences.json` 里编排（照抄 `wraith_squadron_arrival` 骨架：
   pause → stage.clear → 演员定位 → cut_to(follow) → **audio.boss_bgm（演出即配乐，
   别让大阵仗配巡航曲）** → 台词(带 `dur`) → 动作 → restore →
   return_to_player → unpause → release）
3. 空间尺度按 §1-1 反推；台词时长用编排值（ambient 的 2.6s 封底不适用于演出）
4. 需要新演员动作 → 加进 `cinematic_cast.gd`（只下航路点，真物理，禁 K 帧）
5. 过一遍 §1 四问 + §2 陷阱表 + §4 收尾四类
6. `--bench=presentation` 绿 → **引擎内看一遍**（F6 跳 BOSS + F8 热重载调参）
7. spec §8 记变更

## 7. 锚点

| 关注点 | 文件 |
|---|---|
| 序列数据 | `resources/presentation/sequences.json` |
| 导演/通道 | `scripts/presentation/presentation_director.gd` |
| 演员动作 | `scripts/presentation/cinematic_cast.gd` |
| 空舞台 | `scripts/presentation/stage_isolator.gd` |
| 接入样板 | `scripts/events/boss_encounter_event.gd`（`_try_play_arrival_cinematic`） |
| 回归门 | `scripts/tests/test_presentation.gd`（`--bench=presentation`） |
