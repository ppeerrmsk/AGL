# 2026-07-29 升级卡状态词条脚注

## 起因

超载 / 嗜血 / 无敌 / 隐身 / 恐惧 / 干扰 / 减速 这七个状态词条，**在游戏里从来没说明过效果**。
卡面只写"击杀进入嗜血状态 9s"，玩家不知道嗜血本身干什么，只能选完一局靠猜。
用户要求：在技能选取卡片下面写清楚（仅限带词条效果的技能）。

## 改了什么

### 1. 词条说明文案（`status_effects.gd`）

新增 `NOTE_I18N_KEY` 表 + `note_i18n_key(id)`，7 个状态各一句话。
文案里的数值与本文件常量段同源，改常量必须同步改文案。

| 词条 | 文案 |
|---|---|
| 超载 | 装填 / 锁定 ×0.4 · 加速与顶速 ×1.6 |
| 嗜血 | 每次击杀回复 20 HP |
| 无敌 | 免疫全部伤害 |
| 隐身 | 无法被锁定 · 敌方丢失目标 |
| 恐惧 | 敌机压力拉满 · 被迫脱离交战 |
| 干扰 | 目标全武器封锁 · 雷达冻结 |
| 减速 | 限速 350 km/h · 禁用加力 · 滚转 ×0.6 |

i18n key `STATUS_NOTE_*`（中/英/日三语，`translations.csv`）。

### 2. 技能 → 词条映射（`survivor_data.status_notes_of`）

三层，优先级 OVERRIDE > (keywords ∪ EXTRA)：

- **主路径 = `keywords` ∩ 状态 id**。keywords 本来就是 doctrine 家族分类的权威源，
  新技能按惯例写上 `overload/bloodlust/stealth/fear/jam/slow` 就自动带脚注，零维护。
- **`STATUS_NOTE_EXTRA`** 补"施加了状态但关键词里没写"的漏网。
  INVINCIBLE 根本没有对应关键词，7 条全走这里：squad_revenge / assassin_revenge(+stealth) /
  skill_missile_hit_invul / skill_lowest_alt_kill_invul / manual_dodge / sig_su35 / sig_harrier。
- **`STATUS_NOTE_OVERRIDE`** 修关键词与实际状态不符的个例：
  `sig_mig41` 关键词写的是 altitude/stealth，实际给的是 OVERLOAD。

排序按 `StatusEffects.DISPLAY_ORDER`（buff 在前），一张卡最多 2 行（`STATUS_NOTE_MAX`）。

### 3. 卡片布局（`survivor_upgrade_ui.gd`）

每张卡从"一个 Button"变成"一列 VBox = [Button][脚注 Label]"。
脚注放在按钮**外面**而不是塞进 `Button.text`：按钮内部四角已经被稀有度徽章（右上）、
轴色 chip（左上）、归属角标（左下）占满，正文再加行会顶到左下角标签上。
脚注 11px、`NOTE_COLOR` 暗一档、`AUTOWRAP_WORD_SMART` + 与按钮同宽的最小宽度
（长句往下折行，不把整排卡撑宽），并跟着自己那张卡一起进出场元素表。

## 验收

`scripts/tests/test_status_notes.gd`（`--bench=status_notes`，25 断言）：

- A 映射 15 条：keywords 主路径 / DISPLAY_ORDER 排序 / EXTRA 合并 / OVERRIDE 覆盖 /
  纯数值技能不挂 / 空字典安全 / 全表行数 ≤ 2 / EXTRA·OVERRIDE 无幽灵 id
- B 文案 4 条：7 个词条都有 note key，且 key 都在 translations.csv 里
- C UI 6 条：有状态显示 / 无状态隐藏 / 双状态两行 / 进出场元素表 / 空位隐藏 /
  换卡后旧脚注不残留（复用同一控件的清理路径）

回归门 `--bench=all` 46 项全绿；`verify_doc_anchors.py` / `verify_player_ref_holders.py` 均绿。

## 顺手记下的一个疑点（未改）

`OVERLOAD_ACCEL_MULT` 名字与注释都写"加/减速 ×1.6"，但它乘进的
`aircraft._executioner_speed_mult()` 同时被 `aircraft_physics.effective_max_speed_kmh` 用于顶速，
所以超载实际还附带**顶速 +60%**。脚注文案按现状如实写了"加速与顶速 ×1.6"。
若这不是设计意图，要改的是常量的消费点而不是文案。

## 后续

- playtest 看三张卡带脚注时整排的高度观感（脚注是变高的唯一来源）
- 加新的"会施加状态"技能时按 skill-implementation-index §4 的提示登记 EXTRA/OVERRIDE
