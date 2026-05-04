# 2026-04-29 — Buff/Debuff 显示改为状态栏文本

## 动机

飞机正上方那一摞彩色进度条（"恐惧" / "超载" / …）与游戏整体的极简线框 + 数据标签风格不搭，破坏战术感。改成在数据标签里以英文简称 + 百分比的形式按颜色逐行列出。

## 改动

- **`scripts/status_effects.gd`** — 新增 `english_label(id)`：`INVUL / STLTH / BLOOD / OVRLD / FEAR / JAM / SLOW`。`short_label`（中文）保留供 debug 面板使用。
- **`scripts/aircraft_renderer.gd`**
  - `draw_data_label_minimal`（玩家用）：在拼装 lines 末尾追加状态行 `"<LABEL> <pct>%"`，记录 `status_line_indices: idx → Color`。
  - `draw_data_label`（友/敌机）：同样追加。
  - 两处文本绘制循环改为 `default → alt_line → status_line` 三段优先级选色。
- **`scripts/aircraft.gd:_draw`** — 删去 `AircraftRenderer.draw_status_icons(self)`。函数本体保留供地面单位继续使用。

## 范围

- **生效**：所有 Aircraft（玩家 / 僚机 / 敌机 / BOSS / Adds）。
- **不变**：地面单位 `aa_gun_unit.gd` / `sam_unit.gd` / `ground_unit.gd` 仍走 bar（它们没有数据标签）。

## 验证

1. 生存模式触发 FEAR / OVERLOAD / SLOW / BLOODLUST 等，飞机正上方不再有彩条；数据标签内出现彩色 `FEAR 87%` 行，倒计为 0 后整行消失。
2. 多状态叠加：进云层（OVERLOAD）+ 击杀（BLOODLUST）→ 标签出现两行，分别为橙 / 血红。
3. 地面 SAM 被 JAM → 仍显示原绿色 bar。
