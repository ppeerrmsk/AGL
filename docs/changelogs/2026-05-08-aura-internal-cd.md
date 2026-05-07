# 2026-05-08 — 累积光环 4s 内置 CD + hover 范围预览（含凝视压迫雷达锥）

## 背景

玩家累积式光环（rear_aura_slow / jam_aura）的 8s 累积窗口内会被反复触发：每达阈值施 debuff 4s，但累积器不停清零重算 → 在 debuff 期间内部继续累积新一轮 → debuff 结束当帧又触发一次 → VFX 脉冲叠加 + status duration 反复 max() 刷新成"近似永久"，与设计原则"累积式光环是间歇性威胁"不符。

同时之前没有 hover 自己飞机时显示光环 / 凝视压迫范围的可视化，玩家不知道这些被动技能的有效范围（设计文档"知道你能做什么 vs 知道你做了什么"原则缺一）。

## 改动

### A. 累积光环加 AURA_INTERNAL_CD = 4.0（与 debuff 时长对齐）

`scripts/aircraft.gd`：

- 新增常量 `AURA_INTERNAL_CD: float = 4.0` + 两个字段 `_rear_aura_cd_remaining` / `_jam_aura_cd_remaining`
- `_update_evasion` 内 §C 累积光环 tick 改为：
  ```
  if cd_remaining > 0.0:
      cd_remaining -= delta   # CD 期内只扣计时不扫描
  else:
      _tick_aura_accumulator(... out_fired)
      if out_fired[0]:
          cd_remaining = AURA_INTERNAL_CD   # 触发即整段锁
  ```
- `_tick_aura_accumulator` 加 `out_fired: Array = []` 出参（不能改 return type 因为函数体内混入了 evade-roll 逻辑不能 early-return）
- 累积光环不再发范围 VFX 脉冲（`AOEPulseVFX.spawn(...)` 删除）—— 累积式异步达阈值不应当作 AOE 圈，状态图标已足够提示。范围 VFX 只留给"瞬时全部生效"的真 AOE。

### B. hover 玩家时显示光环范围预览（draw_aura_ranges）

`scripts/aircraft_renderer.gd:draw_aura_ranges`（新函数，仅在 `team == 0 && is_hovered` 时画）：

- **jam_aura**：全圆绿色环（半径 = `jam_aura_radius_px`）
- **rear_aura_slow**：后半球弧（半角 acos(0.3) ≈ 72.54°，绕 +Y 即 local back）
- **凝视压迫**（`fear_on_lock_threshold > 0`）：紫色雷达锥（外弧 + 两条边缘线，与 `effective_radar_range_px()` × `params.radar_half_angle` 同形状）

`aircraft.gd:_draw_impl` 在 hover 分支调 `AircraftRenderer.draw_aura_ranges(self)`。

#### 关于"凝视压迫范围"的设计澄清

凝视压迫（fear_on_lock_threshold）触发条件 = 玩家持续锁定某敌 N 秒 → 在那个敌人位置施 50px AOE FEAR。技能本身没有"独立 AOE 范围" —— 真正的"视线范围" = 玩家雷达锁定锥本身。所以 hover 预览画的是雷达锥的紫色高亮叠加层，与下方 `draw_radar_cone` 的淡色填充并存。50px 的命中扩散圈太小没必要画。

## 工作流复盘

- 这是首条档 2 任务跑全套封套：plan 文件 + 分支 + commit + 自审 DoD + `--no-ff` 合 main + 本 changelog。
- 桶 C 来源是 plan §盘点结果 拍出 `aircraft.gd` / `aircraft_renderer.gd` 整文件，然后用 Edit 工具反向把不属于 C 的 hunks（bucket A Mother Goose icon / fire_along_nose / damage_router / lock_immune_override / _log_unit_name 扩展，以及 bucket H data_label 权威标志兜底）还原成 main 版本。这是"按 hunk 拆"的实战路径——`git add -p` 在 Bash tool 里跑不动，纯 Edit 也能完成且更精确。
- 顺手做了 plan §桶 C carry-over 的凝视压迫雷达锥预览。这是用户在桶 E 验证完后提的需求，当时只把它写进 plan 等到桶 C 时再做。两次会话之间靠 plan 文件传递，没漏。
