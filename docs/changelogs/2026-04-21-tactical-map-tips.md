# 2026-04-21 战术地图：随机战场简报 + 操作指南 + CSV 修复

## 范围

战术面板（Tab）的两个常驻信息模块：

1. 底部红框"战场简报"：每次打开/关闭面板随机换一条游戏机制提示
2. 右下蓝框"操作指南"：常驻列出玩家可用按键

以及修复 i18n CSV 因半角逗号导致日文字段被挤丢的问题。

---

## 1. 红框"战场简报"（`tactical_map.gd`）

**目的**：用 loading-screen 式的随机提示把玩家平时不容易发现的机制教给他们。

**位置**：主缩略图下方居中横幅，红边（`#d94040`）+ 半透明深色底。

**实现**：

- `_build_tip_banner()`：`Control` holder + `PanelContainer`(StyleBoxFlat) + `RichTextLabel`
- `_roll_random_tip()`：从 `_TIP_KEYS` 随机抽一条，`_last_tip_idx` 避免立即重复
- 前缀 `// 战场简报` 用小字红色染色，正文白色

**时机**：`open()` 和 `close()` 都调用一次，玩家每次切换面板都看到新提示。

**提示池**（15 条，i18n 齐全）：

| key | 主题 |
|---|---|
| TACTICAL_TIP_BOUNDARY | 战区边界补给 + 时间加速 |
| TACTICAL_TIP_DIFFICULTY | 敌人随时间增强 |
| TACTICAL_TIP_WEAPON_SWAP | 1/2 切换 + 导弹耗尽自动切炮 |
| TACTICAL_TIP_FLARE | 自动释放热诱弹规避 |
| TACTICAL_TIP_ALT_HIGH | 高空雷达更远 |
| TACTICAL_TIP_ALT_LOW | 低空难被锁 |
| TACTICAL_TIP_ALT_CLOUDS | 云层规避雷达 + 对头风险 |
| TACTICAL_TIP_SENTINEL | Sentinel 范围内 UAV 增强 + 自爆 |
| TACTICAL_TIP_STAMINA | 高 G 消耗耐力 |
| TACTICAL_TIP_TURN_RADIUS | 转弯半径 = 速度² / G |
| TACTICAL_TIP_CORNER_SPEED | 每机都有最佳角速度 |
| TACTICAL_TIP_MISSILE_RANGE | 高空迎头最远，低空尾追最短 |
| TACTICAL_TIP_MISSILE_SWEET_SPOT | 最大射程 ≠ 最佳射程 |
| TACTICAL_TIP_CRANK | 照射减速的原因 |
| TACTICAL_TIP_RELOAD | 弹药耗尽自动装填 |

---

## 2. 蓝框"操作指南"（`tactical_map.gd`）

**目的**：面板打开时常驻显示玩家可用按键，作为新手引导的兜底。只列常规操作，Debug 按键不放进去。

**位置**：右下角固定（bottom-right anchored），蓝边（`#59bfff`）+ 半透明深色底。

**实现**：

- `_build_controls_panel()`：`PanelContainer` + `VBoxContainer` + 每条一个 `RichTextLabel`
- 使用 BBCode 让键名部分染成暖黄色（`#ffe08a`）并用 `[ ]` 包裹，和白色的动作描述在视觉上分层
- 每条用独立翻译 key，翻译值直接包含 BBCode，减少运行时拼接

**按键清单**：

- `[左键]` 指定目标
- `[右键]` 解除任务
- `[中键拖动]` 平移相机
- `[滚轮]` 缩放
- `[空格]` 回到主视角
- `[Tab]` 战术地图
- `[ESC]` 退出当前界面

---

## 3. CSV 半角逗号逃逸修复

**问题**：日文语境下 3 条提示显示英文，原因是 CSV 字段里的半角 `,` 被解析器当分隔符，日文列被挤丢。

**涉及条目**：

- `TACTICAL_TIP_ALT_CLOUDS`（英文 `... inside them, they can be fatal.`）
- `TACTICAL_TIP_STAMINA`（英文 `Once exhausted, max G drops sharply ...`）
- `TACTICAL_TIP_RELOAD`（英文 `Missiles, guns, and flares ...`）

**修法**：这 3 个英文字段用双引号包裹 `"..."`，其他字段不动。

**教训**：以后加 CSV 多语文案，英文里有 `,` 就得加引号。中文/日文默认用全角 `，` 、 不踩这个坑。

---

## 4. 红框高度扩到支持 2 行

**问题**：中文一行放得下的句子，翻译成英文/日文经常超出，框里被截断。

**修法**：`_build_tip_banner()` 里红框 holder 的垂直范围从 40px（`offset_top=355 bottom=395`）扩到 70px（`offset_top=350 bottom=420`）。RichTextLabel 自带 `AUTOWRAP_WORD_SMART`，容器高了自然会换行显示完整。

---

## 相关文件

- `scripts/survivor/tactical_map.gd`：新增 `_TIP_KEYS` / `_roll_random_tip` / `_build_tip_banner` / `_build_controls_panel`，`open` / `close` 改为会 roll tip
- `i18n/translations.csv`：新增 15 条 `TACTICAL_TIP_*` + 7 条 `TACTICAL_CONTROLS_*` + 1 条 `TACTICAL_TIP_PREFIX`，修复 3 条英文字段的引号逃逸
- `i18n/translations.*.translation`：由 Godot 编辑器重新烘焙（二进制）
