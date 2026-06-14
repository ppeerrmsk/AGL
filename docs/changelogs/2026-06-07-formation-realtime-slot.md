# 2026-06-07 — 阵型槽位实时跟随（消除"慢一拍" + 去非物理强扭）

spec: [docs/specs/systems/squad-cohesion.md](../specs/systems/squad-cohesion.md) §3.6（in-progress；首轮核心修复已派生，"协调盘旋"增强延后调参阶段）

## 起因
用户反馈（俯视视角，玩家全程看得到僚机动作）：
1. **慢一拍**：玩家频繁点地图下移动指令时，僚机跟随滞后、阵型拖泥带水、失去意义。
2. **不优雅**：部分到位靠"非物理强扭"轨迹（直接挪坐标 / 延迟+突跳伪造曲线），而非真实盘旋/坡度。

期望：真实飞行编队那种优雅、动态的跟随感，僚机靠真实 bank/盘旋自然保持与重建阵型；友机敌机同时受益。

## 诊断（根因 = 双频率脱节）
- `scripts/ai/squad_coordination.gd:process_squad_follow` 在 **AI 分频 tick（~10~20Hz）** 算槽位
  `leader.pos + offset.rotated(leader.heading)`，写成一个**冻结的世界坐标死点** `ac.target_position`。
- `scripts/aircraft/aircraft_formation.gd:update_follow` 是 **60Hz** 跑的，但 `_build_context` 读的就是那个冻结死点。
- 长机转弯/平移时，正确槽位应随长机机体系实时旋转，僚机却要等下一个 AI tick 才更新 →
  50~100ms 内一直追"过去的槽位" → 阵型慢一拍。
- react 延迟（`_formation_react_timer`，仅长机本地偏移变化 > 30px 才触发）**不是元凶**——它只在"换阵型类型"时触发，
  长机单纯移动/转向不触发。

## 改动（首轮 = 核心修复）

### `scripts/ai_controller.gd`
- 新增字段 `_formation_offset_committed: Vector2 = Vector2.INF` —— 已采纳的阵型偏移（长机本地系，未旋转）。

### `scripts/ai/squad_coordination.gd`（process_squad_follow）
- 槽位计算拆为**慢变 / 快变**：本函数只算并采纳"慢变部分" `new_offset_local = get_formation_offset(squad_index)`，
  存入 `ai._formation_offset_committed`。
- react 延迟只用于"换阵型类型"时错落采纳新偏移（首次进编队当帧强制初始化 committed），**不再影响日常跟随**。
- `set_formation_target(leader, Vector2.INF)`：不再写冻结世界槽位。
- 订正注释：删除"延迟+突跳伪造曲线"措辞（该机制随实时槽位自动失效）。

### `scripts/aircraft/aircraft_formation.gd`
- **`_build_context`（快变部分，核心）**：槽位来源从冻结 `ac.target_position` 改为每物理帧实时算
  `slot_pos = ldr.global_position + ai._formation_offset_committed.rotated(ldr.heading)`，并回写 `ac.target_position`
  保持 micro-drift / 调试 / LOD 切换 / 其它读者一致。无 committed 时守卫回退用旧值（下游 INF 走安全平飞分支）。
- **`_update_position`（去非物理强扭 ①）**：直接挪坐标的归位修正降级为**稳态亚像素吸附**——
  新常量 `FORM_SETTLE_DIST=25`（原 CLOSE_DIST=50，收紧一半）/ `FORM_SETTLE_STRENGTH=0.15`（原 0.4），
  且仅 `b > 0.9` 稳态时启用。动态归位全交给真实 bank/盘旋。

## 行为结果
- **慢一拍消除**：长机一动（转弯/平移），全队同帧重算槽位跟动，阵型紧凑。
- **优雅**：僚机靠真实 bank/盘旋自然到位；曲线由实时槽位 + 物理 bank 自然产生，不再有非物理位移突变。
- **友 + 敌统一**：改在共享 AircraftFormation 层，无 team 分叉，敌方编队（默认 FOLLOW_LEADER + 随机阵型）同时受益。
- **换阵型仍自然**：react 错落延迟保留（仅 Finger Four→Wedge 等阵型类型切换时触发）。

## 历史 10 bug 防回归（首轮零触碰核心结构）
- bank 公式 / 翻转守卫（`_should_suppress_bank_flip`）/ leader-bank 混合（`_compute_leader_bank_blend`）/
  roll·turn rate-limit / 速度 clamp（`_update_speed`）/ rejoin rate_scale 全部**不动**。
- `slot_local` 仍用 leader-frame（防 bug#1 方位角摆动）。
- 实时槽位让 slot_dist 更连续（不再每 AI tick 阶跃）→ CLOSE/MID 边界穿越反而减少（利好 bug#8/#9）。

## 性能
每帧每僚机新增：1× `Vector2.rotated` + 1× 向量加 + 1× INF 比较 + 1× 回写。无分配、无全场扫描、无 get_children。
22 架×60Hz 纳秒级，符合性能守则。

## 验证（待 playtest，未代跑）
- F11 编队覆盖层：阵型槽位标记是否**同帧**跟长机转弯（不再滞后）；痛点场景=连续快速点地图 + 长机急转，看 slot_d 不再周期性跳大。
- F12 抓帧 + FORM_DBG 日志：hdiff(Δ) 平滑无 AI tick 周期阶跃；dbank 无 ±50° bang-bang（bug#9）；spd 不超 max（bug#3）。
- 换阵型（切交战模式 Finger Four→Wedge）确认 react 错落延迟仍自然。
- 友 + 敌同时观察；Sentinel + Lv5+ 满编队压测 FPS 掉幅 < 15。

## 回归修复（同日，第二轮）
**症状**：首版改完后僚机在彼此间保持编队、但整体追长机的**旧位置**飞、不跟当前长机（截图：队友困在左下旧位置，长机已飞到右上）。
**根因**：首版把 `process_squad_follow` 的 `set_formation_target` 改为传 `Vector2.INF`（不写世界槽位），完全依赖 `_build_context` 的 committed 路径。但存在 spawn 守卫 / 接管 grace / drone / 规避恢复等路径会在 committed 暂为 INF 或时序错位时让 `formation_mode=true`，此时 `_build_context` 回退读**陈旧的 `target_position`**（指向长机旧位置）→ 僚机追旧位置。
**修法（双保险，槽位永远 = 长机当前位置 + 实时 offset）**：
1. `squad_coordination.gd:process_squad_follow`：恢复每 AI tick 写**新鲜世界槽位**作基线（committed 此处已保证非 INF），不再传 INF。
2. `aircraft_formation.gd:_build_context`：committed 为 INF 时直接从 `squad.get_formation_offset(squad_index)` 实时算，**绝不回退到陈旧 target_position**。

## 后续（延后到调优雅阶段，按需）
"协调盘旋"增强：转弯内外侧速度差（外圈加速追）/ MID bias 调参 / leader-bank 镜像增强（整队压坡）。
每项独立提交 + 专项 bug#9（F11 dbank 包络）验证——仅在核心效果看完觉得"还不够优雅"时做。
