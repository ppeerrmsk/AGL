# 2026-06-16 僚机护卫规避：被打才逃 / 待命护焰（spec wingman-escort-evasion）

用户反馈：玩家按 E 进规避，僚机**没被攻击也无脑加速散开飞离阵型**（实测脱队飞数 km），很不自然。
期望：僚机只有自己真被导弹咬住才加速逃命；否则守在长机身边，并主动投热诱弹替长机挡追它的导弹。

spec：[docs/specs/systems/wingman-escort-evasion.md](../specs/systems/wingman-escort-evasion.md)（in-progress，差 §5 playtest）。

## 根因

`_propagate_evasion_to_squad` 把 `evasion_mode=true` 广播给僚机 → `ai_controller` 规避守卫**无条件** `enter_evade` → 哪怕僚机毫发无损、根本没被瞄，也走 `_process_scatter_evade` 朝散开扇形 max+AB 飞离。`evasion_mode=true` 还会让 planner 的 `Situation.evasion_intent` 出 `EVADE_MISSILE` intent（max+AB），即使留在 SQUAD_FOLLOW 也会散开。

## 改动

### 阶段 1 — 解耦广播标志
- `Aircraft` 新增 `escort_cover_active`（护卫姿态，**与 `evasion_mode` 解耦**：待命期间僚机 `evasion_mode` 保持 false，planner 不再让它散开）+ `_escort_flare_tried`（护卫单弹单次记录）。
- `_propagate_evasion_to_squad`：广播置僚机 `escort_cover_active`（不再 `set_evasion_mode`）；长机自身按 E 仍 `evasion_mode=true`，自卫机制零变动。
- `ai_controller` 规避守卫三分支：① 自己被真威胁(`check_incoming_missile`)→ `enter_evade` 逃命；② 没威胁 + 无玩家命令 → 召回 `SQUAD_FOLLOW` 待命护卫；③ 没威胁 + 有命令 → 落「命令铁律」继续交战。
- `MissileEvasion.process_evade` 无导弹分支：**废除 scatter-on-broadcast**，自身威胁一解除即清 `evasion_mode` + `exit_evade` 归队。删除死代码 `_process_scatter_evade` + 4 个 `SCATTER_*` 常量 + `_scatter_evade_timer`/`_scatter_no_missile_secs` 字段与重置。

### 阶段 2 — 护卫 flare（所有僚机基础能力）
- `AircraftFlares.try_cover_flare(ac, leader)`：前置门（玩家方僚机 + flare 就绪 + 距长机 ≤ `ESCORT_FLARE_LEADER_RANGE_M=800m`）→ 选「追长机 + 即将命中长机(`player_flare_should_trigger(leader,m)`) + 本机未尝试过」的最近一枚导弹 → 投焰。
- `AircraftFlares.release_cover(...)`：粒子/弹量/CD 复用 `release`；jam 概率 `escort_jam_chance = ESCORT_BASE_JAM(0.70) × clamp(1 − d_leader/800, 0, 1)`（贴脸 0.70、800m 处趋 0）；成功 `is_flare_jammed=true` + `ESCORT_FLARE` / `MISSILE escort flare jammed` 日志。**不**触发玩家自卫技能钩子（护卫是僚机行为）。
- `SquadCoordination.process_squad_follow`：`escort_cover_active` 时调 `try_cover_flare`（自保 evade 之后、正常编队之前）。
- **一次只有一架（全队裁决）**：`_is_best_escort_for` —— 同一枚追长机的导弹，仅「同队就绪僚机里离长机最近」的那架出手（平局 instance_id 决断，多架同帧 tick 恰好一架通过）；最近那架 jam 失败（进 CD + `_escort_flare_tried` 标记）后，下一帧次近的接手 → 任一时刻只一架喷焰，优先 jam 概率最高的去做，失败有顺序兜底。
- CD：护卫焰与自卫焰**共用** `_flare_cooldown`（F-16 1.5s / F-14 4.0s 等），投一次即进 CD。
- 防滥用四重：一次一架 + 单弹单次/架 + 近度衰减 + 消耗自身 flare 弹量/CD → 不会变长机无敌护盾，不破坏「一击毙命」。

## 验证

- `--bench=escort`（新增 `scripts/tests/test_escort_evasion.gd`）：**24/24 通过** —— jam 概率公式（贴脸 0.70 / 半程 0.35 / 边缘 0 / 超界 clamp）、flare 就绪门（敌方/无弹/CD 拒）、目标合格判定（追长机+即将命中+未试过）、「一次一架」全队裁决（最近者出手 / 较远让位 / 最近进 CD 次近接手 / 更近者超界让位 / 平局恰好一架）、**端到端**（真实 missile_manager 扫描→裁决→投焰→消耗 flare→进 CD→单弹单次）、**jam 应用率**（贴脸 3000 发实测 ≈ 0.69，容差 ±0.05）。
- `--bench=flare`：9/9 通过（既有智能放焰 + 规避威胁门未回归，复用同套 `player_flare_should_trigger` / `_is_evasion_threat`）。
- 全项目 headless 编译干净，无 SCRIPT/Parse/Compile Error。
- **待 playtest**：按 E 后未被瞄僚机留编队（log 无 scatter / 无 `EVADE_MISSILE` PLAN）；被瞄僚机仍规避；长机被追时近距僚机出 `ESCORT_FLARE` 且导弹被 jam；Sentinel + Lv5+ 压测 60 FPS。

## 设计哲学

命中原则 7（AI 演戏 / 僚机 covering 护长机）+ 原则 3（护卫焰有可见反馈：粒子 + 导弹偏飞 + 日志）。护卫概率/范围首版取 0.70 / 800m，实测再调。
