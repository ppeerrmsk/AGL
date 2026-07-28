# 2026-07-27 Tab 战术面板：已激活技能清单修复 + 移到画面右缘

## 症状

Tab 战术面板本应在左栏显示玩家当前装备的技能（升级清单，hover 行显示详情），
但实际打开后清单恒空——玩家没有任何地方能查看已装备技能的详细信息。

## 根因

2026-07-19 `cf4ea2a`（三轴属性阶段7）把新函数 `_refresh_axis_panel` **插进了
`_refresh_upgrades_list` 函数体中间**，导致原本属于 `_refresh_upgrades_list` 的
建清单代码（按轴分桶 + `_make_upgrade_row`）被"劈"到 `_refresh_axis_panel` 尾部。
调用顺序变成：

1. `_refresh_upgrades_list` → `_refresh_axis_panel()`（此时清单被建出来）
2. 返回后执行清空循环 `queue_free()` → **刚建好的技能行全部被删**

结果：每次开面板清单必空。数据源（`survivor_mode.upgrade_stacks`）本身完好。

## 修复

- 建清单代码搬回 `_refresh_upgrades_list`（清空之后重建，顺序修正）；
  `_refresh_axis_panel` 回归纯三轴面板职责
- 按用户令把"已激活技能"面板从左栏移到**画面右缘**（`_build_skills_panel`：
  anchor 右缘 -240..-20，上缘对齐缩略图 top、下缘避开右下操作指南框），
  含标题 + 滚动清单 + hover 详情框；左栏（`_build_axis_column`）保留三轴量表/
  里程碑明细 + 当前加成/机体数据状态块，并顺手修正左栏容器 anchor_bottom
  漏设（原 0 → 0.5，消除纵向 rect 塌缩）

## 验证

- `test_map_expansion` parse 冒烟（完整 AutoLoad 环境编译 tactical_map.gd）全绿
- 差 playtest：进生存模式拿若干升级后开 Tab，确认右缘清单按轴分组显示、
  hover 行出详情、左栏三轴/状态块不变
