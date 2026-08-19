---
status: open
owner: 文案接手人
created: 2026-08-19
baseline: main@989765c
scope: 资料库与关联本地化文案修正
---

# 资料库与本地化文案修正交接

这份交接用于继续修订玩家可见文本，重点是主菜单“资料库”入口、资料库外壳、48 条作战手册、
62 条敌情档案，以及被资料库复用的战术提示和王牌中队文案。它是阶段性交接，不是设计权威；
玩法事实若与文案冲突，以当前代码和 `docs/specs/` 为准。

## 1. 开始前先看这四条

1. **只改 CSV 源文件，不直接改 `.translation`。** 构建完成后再用生成物覆盖 `i18n/` 下的二进制翻译资源。
2. **同一行必须同时维护 `zh`、`en`、`ja`。** 五张 CSV 的表头都是 `keys,zh,en,ja`。
3. **Notion 是措辞需求源，不是当前数量或文件结构的权威。** 原文档仍写旧基线、单表
   `translations.csv`、61 个敌情和 3 个 BOSS；当前实现是五张分表、62 个敌情和 4 个 BOSS，
   已包含 Black Star。
4. **先确认 key 的全部消费点再改。** 尤其是 `TACTICAL_TIP_*` 和 `ACE_SQUAD_*_LORE`，它们不只出现在资料库。

需求来源：

- [AGL｜游戏内资料库文案现状与修改清单（2026-08-19）](https://app.notion.com/p/3c1cb899efcd8196a427c4e5a34e24d2)
- [AGL｜资料库同步与当前事实盘点（2026-08-19）](https://app.notion.com/p/3c1cb899efcd81709a6cc7846a12dcb5)
- 当前本地化规则：[本地化参考](../reference/i18n.md) / [i18n 分表说明](../../i18n/README.md)

## 2. 文本从哪里来、显示到哪里

| 玩家看到的位置 | key / 数据来源 | 修改文件 | 额外影响 |
|---|---|---|---|
| 主菜单“资料库”入口 | `MENU_ARCHIVE_NAME`、`MENU_ARCHIVE_DESC` | [`i18n/interface.csv`](../../i18n/interface.csv) | 只影响主菜单入口 |
| 资料库标题、页签、栏目、状态与统计 | `ARCHIVE_*`、`INFO_*`、`CODEX_*` | [`i18n/meta.csv`](../../i18n/meta.csv) | 资料库外壳与档案列表 |
| 作战手册普通条目 | `INFO_<ID>_TITLE`、`INFO_<ID>_BODY` | [`i18n/meta.csv`](../../i18n/meta.csv) | 只影响作战手册 |
| 作战手册“情报”条目 | `INFO_<ID>_TITLE` + `TACTICAL_TIP_*` | 标题在 [`i18n/meta.csv`](../../i18n/meta.csv)，正文在 [`i18n/gameplay.csv`](../../i18n/gameplay.csv) | 同一正文也会在生存模式 Tab 战术地图底部轮播 |
| 常规敌机、支援单位、地面单位、BOSS | `CODEX_<ID>_NAME`、`CODEX_<ID>_DESC` | [`i18n/meta.csv`](../../i18n/meta.csv) | 资料库敌情档案 |
| 王牌中队名称与背景 | `ACE_SQUAD_<ID>_NAME`、`ACE_SQUAD_<ID>_LORE` | [`i18n/gameplay.csv`](../../i18n/gameplay.csv) | 资料库会复用实际王牌档案；也可能出现在王牌相关界面或事件中 |
| 无线电台词 | `RADIO_*` | [`i18n/radio.csv`](../../i18n/radio.csv) | 触发条件不在 CSV，而在 `resources/chatter/radio_chatter.json` 和运行时代码 |

当前注册表是实际条目权威：

- 作战手册：[`scripts/meta/game_info_codex.gd`](../../scripts/meta/game_info_codex.gd)
- 敌情档案：[`scripts/meta/enemy_codex.gd`](../../scripts/meta/enemy_codex.gd)
- 资料库呈现：[`scripts/meta/archive_ui.gd`](../../scripts/meta/archive_ui.gd)
- 王牌档案：[`scripts/survivor/ace_squad_profiles.gd`](../../scripts/survivor/ace_squad_profiles.gd)
- Tab 战术提示：[`scripts/survivor/tactical_map.gd`](../../scripts/survivor/tactical_map.gd)

## 3. 资料库外壳与统计文本

这些 key 全部在 `i18n/meta.csv`，由 `archive_ui.gd` 消费。

| key | 使用位置 | 修改注意 |
|---|---|---|
| `ARCHIVE_TITLE` | 资料库顶栏标题 | 保留终端式括号属于视觉语气，不是格式占位符 |
| `ARCHIVE_TAB_INFO` | “作战手册”页签 | 短标签，避免过长 |
| `ARCHIVE_TAB_ENEMY` | “敌情档案”页签 | 短标签，避免过长 |
| `INFO_SUBTITLE` | 作战手册顶部说明 | 一行说明 |
| `INFO_BADGE_TIP` | 复用战术提示的“情报”徽标 | 极短标签 |
| `INFO_SECTION_MOUSE` | 鼠标操作分组标题 | 保留分隔线风格 |
| `INFO_SECTION_KEYS` | 键盘操作分组标题 | 保留分隔线风格 |
| `INFO_SECTION_SQUAD` | 编队指挥分组标题 | 保留分隔线风格 |
| `INFO_SECTION_FLIGHT` | 飞行与机动分组标题 | 保留分隔线风格 |
| `INFO_SECTION_WEAPON` | 武器与交战分组标题 | 保留分隔线风格 |
| `INFO_SECTION_RUN` | 作战流程分组标题 | 保留分隔线风格 |
| `INFO_SECTION_INTEL` | 战场情报分组标题 | 保留分隔线风格 |
| `CODEX_SUBTITLE` | 敌情档案顶部说明 | 一行说明 |
| `CODEX_PROGRESS_FMT` | 收录进度 | 必须保留两个 `%d`，顺序不变 |
| `CODEX_LOCKED` | 未解锁条目正文 | 击败目标后才显示真实描述 |
| `CODEX_NEVER_MET` | 尚无接触记录 | 状态短句 |
| `CODEX_MET_FMT` | 已接触但未击破 | 必须保留一个 `%d` |
| `CODEX_SHOTDOWN_FMT` | AIR / ADDS 击坠数 | 必须保留一个 `%d` |
| `CODEX_DESTROYED_FMT` | GROUND 摧毁数 | 必须保留一个 `%d` |
| `CODEX_DEFEATED_FMT` | ACE / BOSS 击破数 | 必须保留一个 `%d` |
| `CODEX_ENCOUNTERS_FMT` | ACE / BOSS 接触数 | 必须保留一个 `%d` |
| `CODEX_FIRST_FMT` | 首次击破时间 | 必须保留一个 `%s` |
| `CODEX_ORION_UNIT_FMT` | Orion 下一架原型机编号 | 必须保留一个 `%s` |
| `CODEX_SECTION_AIR` | 空中作战单位分组 | 保留分隔线风格 |
| `CODEX_SECTION_ADDS` | 支援与特种航空单位分组 | 保留分隔线风格 |
| `CODEX_SECTION_GROUND` | 地面防空单位分组 | 保留分隔线风格 |
| `CODEX_SECTION_ACE` | 王牌中队分组 | 保留分隔线风格 |
| `CODEX_SECTION_BOSS` | BOSS 目标分组 | 保留分隔线风格 |

## 4. 作战手册：48 条正文使用表

标题始终来自 `i18n/meta.csv` 的 `INFO_<ID>_TITLE`。下表“正文 key”若为 `INFO_*_BODY`，正文也只在
作战手册显示；若为 `TACTICAL_TIP_*`，正文来自 `i18n/gameplay.csv`，会同时在 Tab 战术地图轮播。

### 4.1 鼠标操作（7 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `lmb_move` | `INFO_LMB_MOVE_TITLE` | `INFO_LMB_MOVE_BODY` | 作战手册 |
| `lmb_target` | `INFO_LMB_TARGET_TITLE` | `INFO_LMB_TARGET_BODY` | 作战手册 |
| `lmb_double` | `INFO_LMB_DOUBLE_TITLE` | `INFO_LMB_DOUBLE_BODY` | 作战手册 |
| `lmb_wheel` | `INFO_LMB_WHEEL_TITLE` | `INFO_LMB_WHEEL_BODY` | 作战手册 |
| `rmb_cancel` | `INFO_RMB_CANCEL_TITLE` | `INFO_RMB_CANCEL_BODY` | 作战手册 |
| `rmb_brake` | `INFO_RMB_BRAKE_TITLE` | `INFO_RMB_BRAKE_BODY` | 作战手册 |
| `camera` | `INFO_CAMERA_TITLE` | `INFO_CAMERA_BODY` | 作战手册 |

### 4.2 键盘操作（11 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `key_num` | `INFO_KEY_NUM_TITLE` | `INFO_KEY_NUM_BODY` | 作战手册 |
| `key_e` | `INFO_KEY_E_TITLE` | `INFO_KEY_E_BODY` | 作战手册 |
| `key_r` | `INFO_KEY_R_TITLE` | `INFO_KEY_R_BODY` | 作战手册 |
| `key_f` | `INFO_KEY_F_TITLE` | `INFO_KEY_F_BODY` | 作战手册 |
| `key_q` | `INFO_KEY_Q_TITLE` | `INFO_KEY_Q_BODY` | 作战手册 |
| `key_t` | `INFO_KEY_T_TITLE` | `INFO_KEY_T_BODY` | 作战手册 |
| `key_c` | `INFO_KEY_C_TITLE` | `INFO_KEY_C_BODY` | 作战手册 |
| `key_v` | `INFO_KEY_V_TITLE` | `INFO_KEY_V_BODY` | 作战手册 |
| `key_tab` | `INFO_KEY_TAB_TITLE` | `INFO_KEY_TAB_BODY` | 作战手册 |
| `key_space` | `INFO_KEY_SPACE_TITLE` | `INFO_KEY_SPACE_BODY` | 作战手册 |
| `key_esc` | `INFO_KEY_ESC_TITLE` | `INFO_KEY_ESC_BODY` | 作战手册 |

### 4.3 编队指挥（5 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `squad_grammar` | `INFO_SQUAD_GRAMMAR_TITLE` | `INFO_SQUAD_GRAMMAR_BODY` | 作战手册 |
| `squad_wheel` | `INFO_SQUAD_WHEEL_TITLE` | `INFO_SQUAD_WHEEL_BODY` | 作战手册 |
| `squad_attack` | `INFO_SQUAD_ATTACK_TITLE` | `INFO_SQUAD_ATTACK_BODY` | 作战手册 |
| `squad_iron` | `INFO_SQUAD_IRON_TITLE` | `INFO_SQUAD_IRON_BODY` | 作战手册 |
| `squad_switch` | `INFO_SQUAD_SWITCH_TITLE` | `INFO_SQUAD_SWITCH_BODY` | 作战手册 |

### 4.4 飞行与机动（7 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `flight_corner` | `INFO_FLIGHT_CORNER_TITLE` | `TACTICAL_TIP_CORNER_SPEED` | 作战手册 + Tab 战术地图 |
| `flight_turn` | `INFO_FLIGHT_TURN_TITLE` | `TACTICAL_TIP_TURN_RADIUS` | 作战手册 + Tab 战术地图 |
| `flight_tier` | `INFO_FLIGHT_TIER_TITLE` | `INFO_FLIGHT_TIER_BODY` | 作战手册 |
| `flight_alt_high` | `INFO_FLIGHT_ALT_HIGH_TITLE` | `TACTICAL_TIP_ALT_HIGH` | 作战手册 + Tab 战术地图 |
| `flight_alt_low` | `INFO_FLIGHT_ALT_LOW_TITLE` | `TACTICAL_TIP_ALT_LOW` | 作战手册 + Tab 战术地图 |
| `flight_cloud` | `INFO_FLIGHT_CLOUD_TITLE` | `TACTICAL_TIP_ALT_CLOUDS` | 作战手册 + Tab 战术地图 |
| `flight_stall` | `INFO_FLIGHT_STALL_TITLE` | `INFO_FLIGHT_STALL_BODY` | 作战手册 |

### 4.5 武器与交战（9 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `weapon_oneshot` | `INFO_WEAPON_ONESHOT_TITLE` | `INFO_WEAPON_ONESHOT_BODY` | 作战手册 |
| `weapon_lock` | `INFO_WEAPON_LOCK_TITLE` | `INFO_WEAPON_LOCK_BODY` | 作战手册 |
| `weapon_range` | `INFO_WEAPON_RANGE_TITLE` | `TACTICAL_TIP_MISSILE_RANGE` | 作战手册 + Tab 战术地图 |
| `weapon_sweet` | `INFO_WEAPON_SWEET_TITLE` | `TACTICAL_TIP_MISSILE_SWEET_SPOT` | 作战手册 + Tab 战术地图 |
| `weapon_crank` | `INFO_WEAPON_CRANK_TITLE` | `TACTICAL_TIP_CRANK` | 作战手册 + Tab 战术地图 |
| `weapon_flare` | `INFO_WEAPON_FLARE_TITLE` | `TACTICAL_TIP_FLARE` | 作战手册 + Tab 战术地图 |
| `weapon_gun` | `INFO_WEAPON_GUN_TITLE` | `INFO_WEAPON_GUN_BODY` | 作战手册 |
| `weapon_reload` | `INFO_WEAPON_RELOAD_TITLE` | `TACTICAL_TIP_RELOAD` | 作战手册 + Tab 战术地图 |
| `weapon_swap` | `INFO_WEAPON_SWAP_TITLE` | `TACTICAL_TIP_WEAPON_SWAP` | 作战手册 + Tab 战术地图 |

### 4.6 作战流程（6 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `run_loop` | `INFO_RUN_LOOP_TITLE` | `INFO_RUN_LOOP_BODY` | 作战手册 |
| `run_boundary` | `INFO_RUN_BOUNDARY_TITLE` | `TACTICAL_TIP_BOUNDARY` | 作战手册 + Tab 战术地图 |
| `run_time` | `INFO_RUN_TIME_TITLE` | `TACTICAL_TIP_DIFFICULTY` | 作战手册 + Tab 战术地图 |
| `run_dock` | `INFO_RUN_DOCK_TITLE` | `INFO_RUN_DOCK_BODY` | 作战手册 |
| `run_upgrade` | `INFO_RUN_UPGRADE_TITLE` | `INFO_RUN_UPGRADE_BODY` | 作战手册 |
| `run_evolve` | `INFO_RUN_EVOLVE_TITLE` | `INFO_RUN_EVOLVE_BODY` | 作战手册 |

### 4.7 战场情报（3 条）

| ID | 标题 key | 正文 key | 使用位置 |
|---|---|---|---|
| `intel_ace` | `INFO_INTEL_ACE_TITLE` | `INFO_INTEL_ACE_BODY` | 作战手册 |
| `intel_boss` | `INFO_INTEL_BOSS_TITLE` | `INFO_INTEL_BOSS_BODY` | 作战手册 |
| `intel_sentinel` | `INFO_INTEL_SENTINEL_TITLE` | `TACTICAL_TIP_SENTINEL` | 作战手册 + Tab 战术地图 |

### 4.8 战术提示的特殊注意事项

- `TACTICAL_TIP_PREFIX` 是 Tab 战术地图里提示正文前的前缀，不是作战手册条目正文。
- 当前 Tab 轮播和作战手册共用上表 14 个 `TACTICAL_TIP_*`。
- `TACTICAL_TIP_STAMINA` 仍留在 `i18n/gameplay.csv`，但飞行员耐力机制已移除，当前没有运行时消费点；
  不要把它当成仍在显示的文案，也不要仅为了改稿把它重新接回界面。

## 5. 敌情档案：62 个条目

除王牌中队外，名称和描述都在 `i18n/meta.csv`：

```text
CODEX_<大写 ID>_NAME
CODEX_<大写 ID>_DESC
```

例如 `uav_commander` 对应 `CODEX_UAV_COMMANDER_NAME` / `CODEX_UAV_COMMANDER_DESC`。
未击破条目只显示 `CODEX_LOCKED`，所以校对描述时需要 Debug 全解锁或已有生涯记录。

### 5.1 空中作战单位（45 个）

这些条目都只在敌情档案使用 `CODEX_<ID>_NAME/DESC`：

```text
uav, ucav, f4e, f86, a7, mig23, interceptor, q5, f100, f4,
mig, f104, su27, su35, mig31, fa18, uav_commander, af03, uav_laser,
mirage3, a6e, a10, f16, viggen, harrier, mirage2000, gripen_c, tornado,
f15, f14, fa18e, f15e, su34, snowblind, deadair, f15c, rafale, typhoon,
gripen_e, f15smtd, f35, su57, j20, f22, a12
```

### 5.2 支援与特种航空单位（3 个）

| ID | 名称 key | 描述 key | 使用位置 |
|---|---|---|---|
| `tu160` | `CODEX_TU160_NAME` | `CODEX_TU160_DESC` | 敌情档案 |
| `ah64` | `CODEX_AH64_NAME` | `CODEX_AH64_DESC` | 敌情档案 |
| `ch47` | `CODEX_CH47_NAME` | `CODEX_CH47_DESC` | 敌情档案 |

### 5.3 地面防空单位（3 个）

| ID | 名称 key | 描述 key | 使用位置 |
|---|---|---|---|
| `sam` | `CODEX_SAM_NAME` | `CODEX_SAM_DESC` | 敌情档案 |
| `aa` | `CODEX_AA_NAME` | `CODEX_AA_DESC` | 敌情档案 |
| `radar` | `CODEX_RADAR_NAME` | `CODEX_RADAR_DESC` | 敌情档案 |

### 5.4 王牌中队（7 个，特殊数据链）

王牌不使用 `CODEX_*_NAME/DESC`。资料库直接复用 `AceSquadProfiles` 的名称和背景 key，文本在
`i18n/gameplay.csv`。因此这些改动可能同时影响资料库以外的王牌相关呈现。

| ID | 名称 key | 背景 key | 使用位置 |
|---|---|---|---|
| `2ndwave` | `ACE_SQUAD_2NDWAVE_NAME` | `ACE_SQUAD_2NDWAVE_LORE` | 敌情档案 + 王牌档案消费者 |
| `marathon` | `ACE_SQUAD_MARATHON_NAME` | `ACE_SQUAD_MARATHON_LORE` | 敌情档案 + 王牌档案消费者 |
| `gimmick` | `ACE_SQUAD_GIMMICK_NAME` | `ACE_SQUAD_GIMMICK_LORE` | 敌情档案 + 王牌档案消费者 |
| `goofighters` | `ACE_SQUAD_GOOFIGHTERS_NAME` | `ACE_SQUAD_GOOFIGHTERS_LORE` | 敌情档案 + 王牌档案消费者 |
| `whitetea` | `ACE_SQUAD_WHITETEA_NAME` | `ACE_SQUAD_WHITETEA_LORE` | 敌情档案 + 王牌档案消费者 |
| `orion` | `ACE_SQUAD_ORION_NAME` | `ACE_SQUAD_ORION_LORE` | 敌情档案 + 王牌档案消费者 |
| `vulture` | `ACE_SQUAD_VULTURE_NAME` | `ACE_SQUAD_VULTURE_LORE` | 敌情档案 + 王牌档案消费者 |

### 5.5 BOSS 目标（4 个）

| ID | 名称 key | 描述 key | 使用位置 |
|---|---|---|---|
| `WRAITH_SQUADRON` | `CODEX_WRAITH_SQUADRON_NAME` | `CODEX_WRAITH_SQUADRON_DESC` | 敌情档案 |
| `CARRIER_STRIKE_GROUP` | `CODEX_CARRIER_STRIKE_GROUP_NAME` | `CODEX_CARRIER_STRIKE_GROUP_DESC` | 敌情档案 |
| `MOTHER_GOOSE` | `CODEX_MOTHER_GOOSE_NAME` | `CODEX_MOTHER_GOOSE_DESC` | 敌情档案 |
| `BLACK_STAR` | `CODEX_BLACK_STAR_NAME` | `CODEX_BLACK_STAR_DESC` | 敌情档案 |

Black Star 已是当前正式条目。不要沿用旧 Notion 清单中“尚未实现 / 只有 3 个 BOSS”的判断。

## 6. 五张本地化表的边界

如果后续修订超出资料库范围，按领域选择文件，不要把文本重新集中回单表。

| 文件 | 负责文本 | 常见 key |
|---|---|---|
| [`i18n/interface.csv`](../../i18n/interface.csv) | 主菜单、HUD、战术 UI、小队面板、游戏内弹窗 | `MENU_*`、`HUD_*`、`TACTIC_*`、`SQUAD_*`、`POPUP_*` |
| [`i18n/gameplay.csv`](../../i18n/gameplay.csv) | 地图、战区、飞机、进化、BOSS、奖励、事件、战术提示、王牌档案 | `MAP_*`、`ZONE_*`、`AIRCRAFT_*`、`TACTICAL_TIP_*`、`ACE_SQUAD_*` |
| [`i18n/skills.csv`](../../i18n/skills.csv) | 升级、技能轴、装备、状态效果 | 技能 / 装备 / 状态相关 key |
| [`i18n/meta.csv`](../../i18n/meta.csv) | 资料库、图鉴、作战手册、成就、生涯商店 | `ARCHIVE_*`、`INFO_*`、`CODEX_*` |
| [`i18n/radio.csv`](../../i18n/radio.csv) | 所有无线电显示文本 | `RADIO_*` |

无线电特别注意：`radio.csv` 只负责说什么；什么时候说、权重、冷却、概率与序列由
[`resources/chatter/radio_chatter.json`](../../resources/chatter/radio_chatter.json) 和运行时代码负责。
判断台词是否“用得到”时不能只看 CSV。

## 7. 编辑硬约束

- CSV 一行固定四列：`key,zh,en,ja`。包含半角逗号的字段必须用英文双引号包住；字段内的英文双引号写成 `""`。
- 多行文本在 CSV 中写 `\n`，不要直接把一条记录拆成多行。需要多行解析的消费端应使用 `LocaleManager.trm()`。
- `_FMT` key 中 `%d`、`%s` 等占位符的数量和顺序必须在三种语言中一致，否则运行时格式化会报错。
- 不要改 key 名来做纯文案润色。改 key 会牵涉代码、资源和审计；只改 `zh/en/ja` 单元格即可。
- 术语、机型名、数字、按键名和玩法效果必须以当前实现为准。发现事实冲突时先记录，不要用文案自行改玩法语义。
- 不做本地化的内容包括：`AircraftParams.display_name`、`PlayableAircraft.codename`、EventLogger 和 Debug 文本。
- 技能逻辑按稳定 `id` 判断，绝不能按会随语言变化的显示名称判断。

## 8. 推荐交接流程

1. 从 Notion 清单选一组文案，先在本文件第 4、5 节确定实际 key 和影响范围。
2. 用 `rg` 确认 key 的所有消费点：

   ```powershell
   rg -n '目标_KEY' scripts resources i18n docs/specs
   ```

3. 只编辑对应 CSV 的 `zh/en/ja` 三列。若只是中文定稿，也要确保英日列没有占位符或列错位。
4. 生成翻译资源：

   ```powershell
   bench\run.cmd i18n_build 5 120 Shadow
   ```

5. 将 `bench/results/` 中本次生成的 `.translation` 覆盖回 `i18n/`，不要漏掉改过的分表和语言。
6. 跑资料库与本地化审计：

   ```powershell
   bench\run.cmd career_archive 5 120 Shadow
   ```

7. 在 1920×1080 下用主菜单底部“中 / EN / 日”切换三种语言，至少检查：

   - 主菜单资料库入口是否换行或溢出；
   - 作战手册普通正文和“情报”正文是否一致、可读；
   - Tab 战术地图的 14 条共享提示是否仍适合短时阅读；
   - 敌情档案的常规单位、王牌中队和 Black Star；
   - `%d` / `%s` 统计文本是否能正常格式化。

8. 提交前跑：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/verify_docs.ps1
   python tools/verify_doc_anchors.py
   git diff --check
   ```

## 9. 接手人的完成标准

- [ ] Notion 中选定的条目都能对应到本交接中的实际 key。
- [ ] 没有把旧 `translations.csv` 当作当前源文件。
- [ ] `zh/en/ja` 三列完整，CSV 没有多列、少列或错位。
- [ ] 共享 `TACTICAL_TIP_*` 同时适合作战手册和 Tab 战术地图。
- [ ] 王牌文案确认过资料库外的复用影响。
- [ ] 当前 62 个敌情条目都保留，包含 4 个 BOSS 与 Black Star。
- [ ] 翻译资源已重建，`career_archive` 审计通过。
- [ ] 三种语言完成 1920×1080 人工排版检查。

完成本轮修订后，把本文件头部 `status` 改为 `closed`，并在这里补上最终 commit 或 changelog 链接。
