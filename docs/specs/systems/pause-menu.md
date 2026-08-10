---
id: pause-menu
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [ui-transition]
reconstruction_complete: true
---

# 暂停菜单

> 战局中按 ESC 冻结全场并弹出确认页：要么继续作战，要么确认返回主菜单。误触 ESC 不再直接丢掉整局。

## 1. 设计意图（Why）

- **体验目标**：ESC 是一个高频误触键（玩家想关个提示、想取消选中都会下意识按它）。当前 ESC = 无确认地立即销毁战局回主菜单，一次手滑就损失整局进度与未结算功勋。暂停菜单把"退出"从**单键不可逆动作**改成**暂停 → 确认**的两步动作，同时顺带补上游戏本来就缺的"我要去开门/接电话"的暂停能力。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - *单杠杆*：只加一个面板、两个按钮，不引入"暂停时长惩罚""暂停次数上限"等二阶机制。
  - *效果即反馈*：暂停就是全场冻结 + 压暗 + 面板，无需额外 HUD 中介。
  - *复用既有数值/结构*：暂停与出入场完全复用表演导演的 `panel_in` / `panel_out` 序列（与战术地图、越界菜单同一套），不自建时间控制。
- **反模式规避**：
  - 不做"自动存档/续关"——生存模式是一局定生死，暂停只是暂停，不改变结算语义。
  - 不在暂停菜单里塞设置/音量/图鉴等第二功能；它只回答一个问题："继续还是退出"。
  - 不改动"中途退出不结算功勋"的既有规则，只是把这个后果**写在确认页上**告诉玩家。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 面板属性

| 字段 | 值 | 说明 |
|---|---|---|
| CanvasLayer layer | 21 | 高于越界菜单（20）与战术地图（15）；压暗层由导演自动落到 16 |
| process_mode | `PROCESS_MODE_ALWAYS` | 硬暂停期间仍需响应 ESC 与按钮点击 |
| 面板宽 | 460 px（±230） | 与越界菜单同宽，保持模态对话观感一致 |
| 面板高 | 300 px（±150） | 标题 + 说明 + 两按钮 |
| 按钮尺寸 | 360 × 40 px | 与越界菜单一致 |
| 音乐 | 打开时 `set_music_muffled(true)`，关闭时 `false` | 与战术地图一致 |

### 2.2 配色（与越界菜单同一套模态语言）

| Token | RGBA | 用途 |
|---|---|---|
| PANEL_BG | (0.04, 0.05, 0.06, 0.92) | 面板底 |
| PANEL_BORDER | (0.35, 0.75, 1.0, 0.9) | 面板边框（蓝＝中性/系统，区别于越界菜单的红＝警告） |
| TEXT_TITLE | (0.6, 0.9, 1.0, 1.0) | 标题 |
| TEXT_BODY | (0.75, 0.8, 0.8, 1.0) | 正文/按钮字 |
| TEXT_WARN | (0.95, 0.65, 0.35, 1.0) | "退出不结算功勋"警示行 |
| BTN_BG / BTN_BORDER / BTN_HOVER_BG | (0.08,0.1,0.11,1) / (0.35,0.5,0.5,0.8) / (0.15,0.2,0.22,1) | 按钮三态 |

### 2.3 文本（i18n key）

| key | zh | en | ja |
|---|---|---|---|
| `PAUSE_MENU_TITLE` | `[ 已暂停 ]` | `[ PAUSED ]` | `[ 一時停止 ]` |
| `PAUSE_MENU_BODY` | 战局已冻结。按 ESC 或点击「继续作战」回到战斗。 | Combat frozen. Press ESC or click Resume to return. | 戦闘は停止中。ESC または「戦闘再開」で復帰。 |
| `PAUSE_MENU_WARN` | 返回主菜单将放弃本局，本局功勋不结算。 | Leaving abandons this run — no merit will be settled. | メインメニューへ戻ると今回の出撃は放棄され、功勲は清算されません。 |
| `PAUSE_BTN_RESUME` | 继续作战 | RESUME | 戦闘再開 |
| `PAUSE_BTN_QUIT` | 返回主菜单 | QUIT TO MAIN MENU | メインメニューへ |

## 3. 行为与公式（How）

### 3.1 ESC 语义表（生存模式）

按优先级从上往下判定，命中即停：

| 当前态 | ESC 行为 | 理由 |
|---|---|---|
| 战术地图打开（自身 ALWAYS） | 关闭战术地图 | 既有行为，不变 |
| 越界撤退菜单打开 | 无（面板只认按钮） | 既有行为，不变 |
| 升级选卡暂停中 | 无 | 选卡是必答题，不许用 ESC 绕过 |
| **暂停菜单已打开** | 关闭暂停菜单 = 继续作战 | ESC 可开可关，对称 |
| 战局已结束（`is_game_over` / 胜利结算面板） | 直接返回主菜单 | 局已结束，无进度可丢；与结算面板提示"按 ESC 返回主菜单"一致 |
| 其余（正常作战中） | **打开暂停菜单** | 本 spec 新增 |

> 关键机制：硬暂停期间 `get_tree().paused = true`，`survivor_mode` 是 `PROCESS_MODE_INHERIT` 因此**收不到输入**。所以"ESC 开"由 `survivor_mode` 负责、"ESC 关"必须由暂停菜单自己（`ALWAYS`）负责。这与战术地图的既有分工完全一致。

### 3.2 打开 / 关闭流程

```
open():
    _is_open = true
    _root.visible = true
    AudioManager.set_music_muffled(true)
    Presentation.present(self, "panel_in")     # 第 0 帧 hard_pause(true) + 压暗 + 元素淡入

close():                                       # = 继续作战
    _is_open = false
    AudioManager.set_music_muffled(false)
    Presentation.dismiss(self, "panel_out")    # 第 0 帧 hard_pause(false) + 元素淡出

quit():                                        # = 确认返回主菜单
    _is_open = false
    AudioManager.set_music_muffled(false)
    → 发 quit_to_menu 信号，由 survivor_mode 执行既有退出序列：
        Presentation.clear_all()               # 必须：否则时间缩放/遮罩/镜头系数带进主菜单
        AudioManager.stop_music(1.0)
        change_scene_to_file("res://scenes/main_menu.tscn")
```

退出分支**不走 `dismiss`**：场景即将销毁，视觉尾巴无意义，且 `clear_all()` 已负责解除硬暂停。

### 3.3 结算语义

暂停 / 继续不改变任何结算。确认退出＝既有"中途 ESC 退出"路径，**不调用 `MeritLedger.settle_run`**（功勋只在 KIA / 撤退 / 胜利三个出口结算）。本 spec 不改这条规则，只在确认页用 `PAUSE_MENU_WARN` 明写后果。

### 3.4 不做的事

- 暂停期间不允许任何游戏内操作（切控/下令/闪避）——硬暂停天然覆盖，无需额外守卫。
- 不在暂停菜单里做音频设置、技能查看、重开。想看局内信息用 Tab 战术地图（它同样是暂停的）。
- bench / headless 模式不创建暂停菜单（无人按 ESC，省一个 CanvasLayer）。

## 4. 结构与组成（Structure）

- `PauseMenu extends CanvasLayer`（独立模块，遵循"能独立就独立"）
  - `_root: Control`（PRESET_FULL_RECT，`MOUSE_FILTER_STOP`，ALWAYS）
    - 半透明遮罩 `ColorRect`
    - `PanelContainer`（StyleBoxFlat：边框 2 / 圆角 6 / 内边距 24）
      - 标题 `Label` → `PAUSE_MENU_TITLE`
      - 正文 `Label` → `PAUSE_MENU_BODY`
      - 警示 `Label` → `PAUSE_MENU_WARN`
      - 按钮 `继续作战`（上，安全项优先）
      - 按钮 `返回主菜单`（下，破坏性项放远）
  - 信号：`resumed` / `quit_to_menu`
  - 实现 `get_transition_elements()` 协议（返回 `[_root]`），供表演导演做错开出入场
- `survivor_mode` 侧：持有 `_pause_menu`，在建 `BoundaryUI` 处一并创建（bench 模式跳过），`_unhandled_input` 的 ESC 分支改为按 §3.1 表分流。

## 5. 验收标准（Acceptance / Litmus）

- [x] 作战中按 ESC → 全场冻结（飞机/导弹/计时全停）+ 压暗 + 面板淡入
- [x] 面板打开时再按 ESC → 恢复作战，时间正常流动（不残留 `time_scale`）
- [x] 点"继续作战" → 同上
- [x] 点"返回主菜单" → 回主菜单，且主菜单不处于暂停/压暗/时间缩放残留态
- [x] 战术地图打开时按 ESC 仍是关地图（不弹暂停菜单）
- [x] 升级选卡暂停中按 ESC 无反应（不能绕过选卡）
- [x] 战局结束（阵亡/胜利结算面板）按 ESC 仍直接回主菜单
- [x] 性能：面板按需创建，无 `_process`/`_draw` 常驻开销（见 performance-guidelines）
- [x] 已知 seam：不新增"谁是玩家机"缓存持有者，`verify_player_ref_holders.py` 不受影响
- [x] i18n：5 条 key 三语齐全，全部走 `tr()`

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 面板
- [x] 新建 `scripts/survivor/pause_menu.gd`（`PauseMenu extends CanvasLayer`），按 §2/§4 建 UI
- [x] 自身 `_unhandled_input` 处理 ESC 关闭；实现 `get_transition_elements()`

### 阶段 2 — 接线
- [x] `survivor_mode` 创建 `_pause_menu` 并接 `resumed` / `quit_to_menu`
- [x] `_unhandled_input` ESC 分支改为 §3.1 分流（game_over 直退 / 否则开面板）

### 阶段 3 — 收尾
- [x] i18n 补 5 条 key × 3 语
- [x] 同步 `script-index.md` / `code-index.md` / `specs/_INDEX.md`

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 面板主逻辑 | `scripts/survivor/pause_menu.gd` |
| 创建/接线/ESC 分流 | `scripts/survivor/survivor_mode.gd` |
| 出入场序列 | `resources/presentation/sequences.json`（`panel_in` / `panel_out`） |
| 文案 | `i18n/interface.csv`（`PAUSE_*`） |
| reference 索引行 | `script-index.md` 生存模式段 / `code-index.md` UI 段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-28 | 1 | 初稿 + 实装（ESC 改为暂停确认页） |
