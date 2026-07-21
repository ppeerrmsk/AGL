# 2026-07-20 — 加力模式（规避模式资源化改造）

spec: [docs/specs/systems/afterburner-mode.md](../specs/systems/afterburner-mode.md)（用户当日逐条给定数值，初稿即定稿）

## 做了什么

把语义模糊的"规避模式"（E 开关、无成本、收益不可见）改造成小队级充能资源"**加力模式**"：

- **资源**：`scripts/survivor/afterburner_charge.gd`（新模块，RefCounted）——30s 被动充满 / 小队击杀 +4s（空中走 `kill_recorded`、地面走 spawner roe 热度同点位）/ 开局满格 / 满格才能激活 / 6s 固定窗口不可提前退出。
- **激活链路**：E 键与 HUD 按钮改走 `try_activate(leader)`——全队快照置新标志 `Aircraft.afterburner_window_active` + 长机照旧 `set_evasion_mode(true)`（planner max+AB、escort_cover_active 广播、radio break、§1.2 技能钩子、TORP/WMN 投放**全保留**）。窗口到期对称清理。
- **窗口强 buff（全队）**：
  - 机炮 100% 闪避：`take_bullet_damage` 在全局 cap(0.85) 后短路 `effective_dodge = 1.0`（唯一绕 cap 通道）。
  - 90% 滚转甩导弹：missile_manager 命中瞬间 roll → `is_flare_jammed`（走既有偏飞契约：不参与命中/CIWS/补射计伤）+ 滚转动画 + `AB_MISSILE_DODGE` 日志；10% 极限命中。每弹天然只 roll 一次。
  - 禁攻击：既有 evasion 静默三处扩展 `or afterburner_window_active`（机炮扫描/残梭/副弹）+ 发射硬断四处（`_fire_gun_round` / `_fire_missile_at` / `_fire_multi_lock_salvo` / `_launch_rocket`）。CIWS 拦截、TORP、WMN 例外保留。`commanded_target` 不清除，窗口结束恢复开火。
  - 速度：update_speed（实物理 + 预测镜像双侧）目标速度地板 = `effective_max_speed_kmh` + 物理 cap 放开 + 加速度 ×3（`AB_WINDOW_ACCEL_MULT`）。
- **HUD**：战术面板加力按钮上方加充能条（充能暗橙 % / READY 亮橙满格 / 激活亮青倒计时收缩），按钮三态文案；每帧 `_update_afterburner_ui` 走 `_update_display`。
- **i18n**：`TACTIC_EVADE_FMT` 改"E 加力"、新增 `AB_STATE_READY/CHARGING_FMT/ACTIVE_FMT`、tooltip 六键重写为加力语义、§1.2 五个技能文案随语义更新（`规避加力→超频加力`、`规避狂暴→蓄势狂暴` 等），三语齐。

## 关键裁定（详见 spec §3.5，共 16 项）

- AI 自保 `enter_evade`（含玩家托管被咬）照旧置 `evasion_mode` 享受旧弱 buff（+20% 闪避 / max+AB / 静默），**不触发窗口、不耗资源**；敌机行为完全不变（强 buff 只认窗口标志）。
- 窗口内玩家下令照现状退出 `evasion_mode`，但窗口标志独立倒计时满 6s——强 buff 与满速地板不因指挥中断。
- `evasion_weapon_cd` 语义反转为"窗口内冷却双倍流逝、出加力即就绪"（机制零改动只改文案）；`evasion_speed_boost` 变成窗口顶速 ×1.4 超频。
- `skill_evade_missile_overload`（死里逃生）不联动窗口躲弹（钩子只挂 flare jam 路径）。
- 沙盒 E 键直连 `set_evasion_mode` 行为不变。

## 验证

- `--bench=all` 回归门 **31 项 PASS / 0 失败**（零 buff 路径不变：窗口标志缺省 false 全分支短路）。
- `verify_doc_anchors.py` 全绿（顺手回填了 82 处行号漂移锚点，含本次插入代码造成的偏移与前批遗留）。
- `verify_player_ref_holders.py` 全绿（`afterburner_charge` 登记 NON_HOLDERS：传参即用 + 6s 快照带 valid 守卫，刻意不追换帅）。
- 剩 spec §5 playtest 项（速度体感 / 躲弹观感 / 充能节奏）留待用户实机确认后 spec 转 done。
