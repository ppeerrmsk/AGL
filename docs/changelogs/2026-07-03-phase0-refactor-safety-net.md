# 2026-07-03 · 操控权限重构 Phase 0：安全网 + 活 bug 修复（B1~B6）

> 上游：[docs/planning/physics-ai-control-refactor.md](../planning/physics-ai-control-refactor.md)
> （2026-07-02 三路架构体检 + 用户拍板 B1 分层规避策略）。
> 验收：`godot --headless --path . -- --bench=all` **8 项全绿**（退出码 0）。

## B1 · 分层规避策略 + 命令铁律×EVADE 仲裁（[ref:SEAM-014]）

用户定稿的三层策略（planning doc §3"B1 定稿策略"+ memory `feedback_evasion_tiered_policy`）：

- 新增 `MissileEvasion.should_enter_evade(ai)` 分层入口门，**全部 4 处 enter_evade 入口**
  （engage / patrol / squad-follow / escort_cover 广播）统一走它：
  ①仅被锁定/打不到的导弹（closing/TTI 门，已有）→ 不躲；②真威胁 + flare 就绪 → 只扔
  flare 不脱队；③flare 弹尽/CD/被弃管 → 才运动学规避。敌方不受 flare 门（维持难度）。
- `_enforce_commanded_target` 顶部对 `EVADE_MISSILE` 让位（不清 commanded_target），
  修复"躲弹被铁律每 tick 拉回 ENGAGE → ENGAGE↔EVADE 抖 + evasion_mode 卡 true"的死锁。
  有界性由 process_evade 每 tick 带滞回的威胁重确认保证。
- `AircraftFlares._escort_flare_ready` 改名公开 `flare_ready`（护卫/自卫/规避门三方共用）。

## B2 · 机动守卫矩阵统一（[ref:SEAM-015]）

- 新增 `AircraftPhysics.maneuver_overrides_speed(ac)` / `maneuver_overrides_g(ac)`；
  `update_speed`/`update_g_load` 守卫从"只查 Cobra"改为统一谓词。
- Herbst DECEL/TURN 期间物理让位；**ACCEL 阶段刻意保留交还 update_speed**（开 AB 自然
  拉回巡航）。删除 herbst 的"同帧双写自卫"注释语义（target_speed_kmh 同步写保留，
  降级为意图字段一致性）。

## B3 · evasion_mode 裸写收口

- missile_evasion 4 处裸写全部改走 `set_evasion_mode()` 入口（保 evasion_modifiers
  边界差量缩放对称；AI 无 use_tactical_preference 不触发僚机广播）。

## B4 · 编队死代码删除

- 删 aircraft_formation.gd 旧 `_update_heading` / `_update_bank` /
  `_compute_leader_bank_blend` / `_should_suppress_bank_flip`（2026-06-07 PD 重写后
  即死）+ 孤儿常量（FORMATION_LERP_K / FORM_BANK_* / BANK_BLEND_*）+ AIController
  孤儿字段 `_form_bank_ema`。净 -90 行左右。

## B5 · LOD docstring 对齐现实

- `_update_friendly_squad_lod` 注释改为如实描述"全钉 LOD 0 + 每帧覆盖压过 AI 写"
  （lod_level 所有权 → SEAM-016，Phase 4 排期）。

## B6 · bench_runner 回归门

- 6 个复制粘贴测试块改注册表驱动（`UNIT_TESTS`）；新增 `--bench=all`（任一失败退出码 1）
  和 `--bench=bfm_intent`（88 case 首次接入无头，原只能 F10 手测）。
- 接入即抓到一个存量过期断言：`waypoint_big_turn.ab=false` 是 2026-05-07 AB 平滑化
  设计变更前的旧期望 → 测试修正为双断言（慢速开 AB / 已到角点速度不开）。

## 新增验收测试

- `scripts/tests/test_commanded_evade.gd`（`--bench=cmd_evade`，23 断言）：
  A 分层门 8 断言 / B 铁律让位 4 断言 / C 闭环序列 + 30-tick 零弹回抖动守护 11 断言。
  离树构造 Aircraft + AIController + MissileManager + Missile，无需场景。

## 文档同步

- known-seams：新增 SEAM-014 / 015（已修）/ 016（待 Phase 4）。
- spec wingman-escort-evasion v3：§3.1 触发条件更新为分层门 + §8 变更记录。
- script-index / code-index：missile_evasion / aircraft_physics / aircraft_formation /
  aircraft_flares 行更新。
- memory：`feedback_evasion_tiered_policy`（用户规避设计原则）。

## 回归结果

| 测试 | 结果 |
|---|---|
| turn_physics | 全场景符号反转 ≤2（B2 未破坏 SEAM-012 根治） |
| flare | 9/9 |
| rejoin | 指标正常 |
| weapon | 7/7 |
| escort | 24/24（flare_ready 改名无回归） |
| target_sel | 7/7 |
| **cmd_evade（新）** | **23/23** |
| bfm_intent（新接入） | 89/89（修正 1 个存量过期断言后） |

---

# 追加（同日晚）：'投了 flare 仍被命中'诊断 + 三修复

## 诊断（日志实证）
用户报告僚机提前投 flare 仍被同一发导弹命中。翻当日三份战斗日志定位到两类病例：

1. **干扰成功仍命中（真 bug，主因）**：`184619 [120.3]` Watch 投焰 → `flare jammed
   (jam_chance=100%)` → `[121.8]` **同一发 Missile V1 命中 Watch**。根因：命中判定循环
   （missile_manager）不检查 `is_flare_jammed`——被干扰的导弹只失去制导（直线飞行），
   近炸引信照常起爆；尾追弹被干扰时正对目标航迹，目标又因"威胁列表已滤掉 jammed"不再
   规避 → 直线弹撞直线机。与 `team_inbound_damage` / CIWS 拦截过滤的"jammed 视为不会
   命中"契约不一致（CIWS 不拦它，它却还能杀人）。
2. **干扰失败静默（观测盲区，次因）**：`190108 [262.6]` Phoenix 投焰后无任何日志行——
   jam roll 失败只有成功才记日志，"投了焰为什么还追我"无法归因。
3. **顺带发现**：Phoenix 失手后 flare 进 CD → 进躲 → `[262.8]/[263.3]/[263.9]` 三连
   "LEASH 拽回 ↔ 立即重进躲"0.5s 振荡（leash 与威胁两条规则打架，无仲裁）。

## 修复
- missile_manager 命中循环顶部跳过 `is_flare_jammed` 弹（语义统一：jammed=无害）。
- `release` / `release_cover` 补 jam 失败日志（`flare FAILED to jam ...`）。
- 新增 `_evade_reenter_cd`（2.0s，`LEASH_REENTER_SUPPRESS_S`）：leash 拽回后压制
  `should_enter_evade` 一小段，让飞机真的归队（回程即变向 + 回到护卫焰覆盖圈），
  防 EVADE↔SQUAD_FOLLOW 振荡。

## 验证
`--bench=all` 8 项全绿；cmd_evade 新增 2 断言（再入冷却压制/归零恢复）→ 25/25。

---

# 追加（同日）：飞机物理"契约一致性"专项审计 + 5 修复（[ref:SEAM-017]）

按 flare bug 的模式（契约写在注释、实现不强制）对物理层做 7 项专项审计。结论：
**3 确认 bug + 4 隐患**，其中两个确认 bug 正是"update_*/step_* 必须人肉同步"契约的实证漂移
（登记为 SEAM-017）。

## 已修（5 处，--bench=all 8 项全绿）

1. **预测线 G 口径撕裂（确认 bug）**：实飞 max_bank 用结构 G(12G)、预测线用持续 G(9G)
   → 预测弧恒偏宽 ~30%。修：FlightState 加 `cached_max_g_instant`，step_bank 基础
   max_bank 改走 `_eff_max_g_instant_st`（sustained cap 的 aggression lerp 仍用持续 G，
   与实飞逐项对齐）。
2. **LOD1 every3 节流漏 ×3 补偿（确认 bug）**：非编队 LOD1 机爬升/燃油/flare CD 全部
   1/3 速率演化（与当年"BOSS 离屏转弯慢 3 倍"同型错误）。修：every3 块传 `delta*3.0`
   （含 AircraftFlares.update）。
3. **step_speed 缺 Herbst 守卫 + 预测 g_load 缺机动守卫（确认漂移）**：B2 新守卫单侧
   生效。修：step_speed 改用 `maneuver_overrides_speed`；预测循环 g_load 反推包
   `maneuver_overrides_g`。
4. **零燃油白嫖 AB（隐患，条件性）**：ace_squad 远距强制 AB / Herbst ACCEL 无燃油检查，
   裸写发生在 update_fuel 之后 → 没油也有 AB 推力（现被 infinite_fuel 掩盖）。修：补
   `fuel > 0` 守卫。
5. **directive 期间 orbit_speed_cap 残留（隐患）**：带轨道限速的 UAV 收到事件 directive
   后整段被钳 ~280km/h。修：`set_event_directive` 非空入口清 cap。

## 审计确认"已守住"的（良性备案）

高度档位同步契约（bfm_tactics 13 处直写全有 flat 分流）/ stall→altitude 顺序（三条 LOD
路径全守序）/ orbit cap 主循环对称清除 / SLOW 压 AB 物理必胜（仅视觉尾焰可能常亮）/
step_* 的 evasion 倍率、SLOW cap、失速地板、hard_brake、orbit cap 镜像全部一致。

## 遗留（待用户决定 / 后续排期）

- **hard_brake 无失速保护（隐患中）**：长按右键 2-3s 跌破失速 → 强制下压，LOW 档持续
  按住 ~10-20s 可坠地，多选时僚机陪葬（survivor_mode 注释承认是故意跳过失速余量）。
  候选修法：目标速度给 stall×0.9 软地板 / is_stalled 时自动解除 hard_brake。**待拍板**。
- legacy AI 直读 params.* 带（SEAM-001 备注）：给敌机加状态型 buff 前必须先修。
- set_target_tier 无法表达 GROUND（poltergeist 被迫裸写双字段）→ 建议 `set_target_ground()`。
- update/step 镜像契约的根治 = Phase 3 共享纯函数化（SEAM-017）。

---

# 追加（同日）：急刹重设计（用户定稿，结清"hard_brake 无失速保护"待拍板项）

用户反馈：①减速手感不真实（"轻按一秒速度就到底"），低级机减速效率应该更差；
②反复权衡后决定：**急刹仍作用全队**（selected 全体），但去掉"自杀"设定——任何高度
都不能因减速导致失速坠机。

## 实现
- `update_speed` 急刹分支：目标速度从 0 改为**失速软地板**（stall_at_g × 1.05，
  最小可控速度）——刹不进失速，`update_stall` 强制下压永远不会因刹车触发。
- 急刹减速率 = 本机 `params.deceleration`（机型差异化）× **随速度衰减的阻力因子**
  （v/cruise，下限 0.35）：巡航段全额减速、逼近地板时效率降到 35%，减速过程渐进。
- `step_speed` 预测线镜像同步（SEAM-017 纪律）。
- 切控时清旧机 hard_brake 残留旗（防 AI 接管后永久钳在地板速度）。
- survivor_mode `_set_hard_brake` 保持作用全体 selected（用户最终决定，中途试过
  仅长机版已回退）。

## 验收
新增 `--bench=hard_brake`（5 断言）：巡航开刹 1s 剩 181m/s 未到底 / 30s 收敛到地板
64.2m/s 不失速 / 高速段单帧减速 2.8× 于低速段 / decel=40 机比 decel=120 机 1s 后快
59m/s（机型差异化成立）。`--bench=all` 回归门 9 项全绿。
