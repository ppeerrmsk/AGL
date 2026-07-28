# 2026-07-28 暂停菜单：ESC 改为「冻结 + 确认页」

## 症状

生存模式作战中按 ESC = **无确认地立即销毁战局回主菜单**。ESC 是高频误触键
（想关提示、想取消选中都会下意识按），一次手滑就损失整局进度与未结算功勋。
同时游戏根本没有"暂停"能力——中途要离开只能挂着或者直接放弃整局。

## 改动

新增 **暂停菜单**（spec [`systems/pause-menu`](../specs/systems/pause-menu.md)）：
ESC → 冻结全场 + 压暗 + 确认页「继续作战 / 返回主菜单」。

- 新模块 `scripts/survivor/pause_menu.gd`（`PauseMenu extends CanvasLayer`，layer 21）
  - 时间控制**完全复用表演导演**：`Presentation.present(self, "panel_in")` 的第 0 帧
    `hard_pause(true)`，`dismiss(self, "panel_out")` 的第 0 帧 `hard_pause(false)`。
    本模块不直写 `get_tree().paused`（守 ui-transition 的"时间唯一写入点"）
  - `process_mode = ALWAYS`：硬暂停期间 `survivor_mode`（INHERIT）收不到输入，
    所以"ESC 打开"归 survivor_mode、"ESC 关闭"必须由面板自理——与战术地图同一分工
  - 退出分支**不走 dismiss**：场景马上销毁，视觉尾巴无意义，解暂停由
    `Presentation.clear_all()` 负责
  - 按钮顺序：继续（安全项）在上，返回主菜单（破坏性）在下
- `survivor_mode` ESC 分流（spec §3.1，按优先级）：
  战术地图打开 → 关地图 ／ 选卡暂停中 → 不响应（不许绕过必答题）／
  `is_game_over`（阵亡·胜利结算面板）→ 直接回主菜单（与结算面板"按 ESC 返回主菜单"
  提示一致）／ 其余 → 打开暂停菜单
- 原地退出序列抽成 `_quit_to_main_menu()`（`clear_all` + `stop_music` + 切场景），
  ESC 结算态分支与暂停菜单确认分支共用
- bench / headless 不创建面板（无人按 ESC，省一个 CanvasLayer）

**不改结算语义**：中途退出仍不结算功勋（功勋只在 KIA / 撤退 / 胜利三个出口结算），
但确认页用 `PAUSE_MENU_WARN` 把这个后果明写给玩家。

## i18n

新增 5 条 key × 三语：`PAUSE_MENU_TITLE` / `PAUSE_MENU_BODY` / `PAUSE_MENU_WARN` /
`PAUSE_BTN_RESUME` / `PAUSE_BTN_QUIT`。

## 验证

- `--bench=all` 无脚本编译/解析错误（回归门另有 2 项 `test_attribute_gates` 热诱弹
  断言失败，属本次改动之前工作区里既有的失败，与本批无关）
- `verify_player_ref_holders.py` ✓（未新增"谁是玩家机"缓存持有者）
- `verify_doc_anchors.py` 本批新增锚点全绿
- 待 playtest：ESC 开关对称性 / 退出后主菜单无时间缩放·压暗残留 / 战术地图与
  选卡两条优先级分支
