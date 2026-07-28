# 2026-07-28 等级通胀整治 + 进化树视觉（color code / pip 徽记）

> 用户裁决："等级需求形同虚设、和实际升级频率不符；应该做到**不保证每局都能强化到顶级飞机**；
> 三轴需求过于温和、没在读玩家路线。" + "改进科技树 UI 做 color code：当前机 / 路线 / 需求点数更直观。"
> spec：[evolution-attribute-gates v9](../specs/systems/evolution-attribute-gates.md) ·
> [survivor-loop v2](../specs/systems/survivor-loop.md)

## 诊断（三处通胀源）

1. **每级击杀数恒定**：升级需求 `15·L^1.15` 与击杀 XP `+level×8` 近同速增长 →
   全程 2~3 杀/级，等级=击杀计数器，LV21（T5 开门）中局即到。
2. **Adds 核弹经验**：`adds_xp_per_kill` 单只=当前等级全额（divisor 1），一组 Tu-160×4 = +4 级；
   等级计价对 XP 曲线免疫，曲线改多陡都白调。
3. **无等级上限 + 点数无封顶**：`floor(LV/3)` 不封顶 → LV30=10 点起 spec §2.5 排他性数学失效
   （骑5+策5 双专精可行），三轴门槛全面失去路线判别力。

## 改动

### 数值（spec-first，survivor-loop §5 / attribute-gates §2.2）

- `xp_for_level` 指数 **1.15 → 1.3**（温和档，用户拍板）：每级击杀数随等级爬升
  （LV10≈2.8 → LV25≈4.1，未计乘区），平均局收 LV18~22，LV26+ 只属于高节奏局。
- **Adds 等级计价废除**（用户拍板"整组设计去掉，全部按单独敌人经验排"）：
  `adds_xp_per_kill`/`ADDS_XP_DIVISOR` 删除，新增 `XP_PER_KILL_TU160=80 / AH64=50 / CH47=40`，
  走普通公式 `base + level×8`。整组 ≈ 1~1.5 级，仍是最肥经验事件。
- **三轴点数收入封顶 8**：`axis_points_earnable = min(floor(LV/3), AXIS_POINT_CAP=8)`；
  `add_axis_point` 合计 8 后闸掉（一切加点来源共用）；触顶后卡面不再显示"+1"、
  家系池空时不再合成"专注"纯加点卡。门槛表与 41 机 gates **一个数没动**——排他性由封顶背书恢复。

### 进化树视觉（attribute-gates §3.3 v9，evolution_tree_view.gd）

- **路线 color code**：卡左缘轴色竖条（攻击=琥珀/远程=青绿/电战=紫/制空·桥接·母舰=双段/
  隐身=骑+策/omni·传说=三色），CAT_AXES 数据驱动，颜色复用 AXIS_COLORS。
- **门槛 pip 徽记**：每 1 点一枚圆点，实心=已满足/空心=缺口；合计门"各≥N"=纯色点、
  自由余量=双/三色分瓣点；或门=一枚分瓣。全部已揭示节点可见（远处调暗），扫一眼知道差几点。
- **当前机高亮**：金框加粗 + 外圈光环 + 底色提亮；顶部三轴图例（复用 ATTR_* key，零新 i18n）。
- 迷雾剪影节点不画条/pip；静态绘制不加每帧重绘（性能守则 1）。

## 文件

- `scripts/survivor/survivor_data.gd` — XP 指数 / Adds 常量 / AXIS_POINT_CAP
- `scripts/survivor/survivor_spawner.gd` — Adds 并入普通 XP 分支
- `scripts/survivor/survivor_player.gd` — add_axis_point 封顶闸
- `scripts/survivor/survivor_mode.gd` — `_axis_points_capped()` + 专注卡停发 + populate 传参
- `scripts/survivor/survivor_upgrade_ui.gd` — populate(choices, points_capped) 徽章去"+1"
- `scripts/survivor/evolution_tree_view.gd` — v9 视觉整版（路线条/pip/高亮/图例）
- `scripts/tests/test_attribute_gates.gd` — §A 封顶刻度 + §E 第 9 点闸断言（87 绿）
- `scripts/tests/test_evolution_detail.gd` — §F pip 槽位断言（28 绿）

## 验证

- `--bench=all` 回归门 **41 项全绿**（attr_gates 87 / evo_detail 28 含新断言）。
- `--bench=stress_swarm` 生存场景冒烟：无脚本错误。
- ⏳ playtest：平均局终等级落 LV18~22、T5 不保底、pip/色条手感（用户实机）。
