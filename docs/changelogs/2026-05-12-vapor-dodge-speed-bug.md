# 2026-05-12 · vapor_dodge 导致开局速度死锁修复 [SEAM-009]

## 症状

玩家在生存模式开局拿到 `vapor_dodge`（云雾机动）后，速度被卡在 138~200kt 提不上来，
加力（`ab=y`）全程开着也没用。无任何 debuff，没有 stall。在
`logs/combat_log_20260512_163945.txt` 里复现。

## 根因

`altitude_authority_mult ×2.0` 被同时乘进 `update_altitude` 的三处：
- `max_climb`：250 → 500+ m/s（**问题源**）
- `gain`：0.4 → 0.8（响应度，无害）
- `smooth_rate`：8 → 16（响应度，无害）

AI 把 target_altitude 推到 HIGH（≈8500m），alt_diff +3000m 让 target_vs 顶到 500+ m/s，
log 实测 `vs=898ms`。然后 [aircraft_physics.gd:255 PE↔KE](../../scripts/aircraft/aircraft_physics.gd:255)
`gravity_effect = g · vs / spd · 2.5` 反抽：vs=898, spd=200 时**每秒 ≈ 110 m/s 速度损失**，
加力推力（≈17 m/s²）完全顶不住，飞机被钉在失速带边缘。

详见 [SEAM-009](../architecture/known-seams.md#seam-009--altitude_authority_mult-与-pekek-反抽公式的耦合)。

## 改动

[scripts/aircraft/aircraft_physics.gd:273](../../scripts/aircraft/aircraft_physics.gd:273)
`update_altitude` + [aircraft_physics.gd:1207](../../scripts/aircraft/aircraft_physics.gd:1207)
`step_altitude`（预测器，两边必须同步）：

```gdscript
var base_climb: float = ac.params.climb_rate_max if ac.params else 250.0
var max_climb := base_climb * minf(alt_mult, 1.3)   # 物理顶速最多 +30%
var gain := 0.4 * alt_mult                          # 响应度仍由 alt_mult 全幅放大
var smooth_rate := 8.0 * alt_mult
```

同步更新 [aircraft.gd:243](../../scripts/aircraft.gd:243) `altitude_authority_mult` 字段
注释 + [survivor_data.gd vapor_dodge 注释](../../scripts/survivor/survivor_data.gd) 反映新 cap。

## 行为差异

| 场景 | 改前 | 改后 |
|---|---|---|
| baseline（无 vapor_dodge）| vs ≤ 250 m/s | vs ≤ 250 m/s（不变）|
| 拿 vapor_dodge | vs 顶到 900 m/s，spd 死锁 138kt | vs 顶到 325 m/s，spd 能回到 600kt+ |
| 切档时间（LOW↔HIGH）| ~20s（但代价是横速失控）| ~22-25s（横速可保）|

`alt_change_stealth` 的 `_alt_velocity`（peak vs 决定）会从 ~900 降到 ~325，
即 lock_rate stealth 在快速切档时略弱。可接受 —— 原行为本就建立在自残物理上。

## 验证

1. 拿 vapor_dodge 跑一局，F9 抓 log，搜 PRED_DIAG 应无 `vs=` 接近 900 的值。
2. 不拿 vapor_dodge 跑一局，确认 `vs ≤ 250` baseline 不变。
3. 搜 `PRED_JUMP` 频率不增多（两处改动同步）。
