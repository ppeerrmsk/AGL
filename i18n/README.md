# 本地化源表

本文件只说明 `i18n/` 目录的数据契约；完整新增 key、构建、审计与代码入口见
[本地化工作流](../docs/reference/i18n.md)，项目级导航见 [Reference Index](../docs/reference/_INDEX.md)。

所有 CSV 使用同一表头 `keys,zh,en,ja`，key 在全部分表之间必须唯一。

| 文件 | 内容 | 路由规则 |
|---|---|---|
| `interface.csv` | 菜单、HUD、战术控件、暂停、编辑器与通用界面文本 | `MENU_*`、`HUD_*`、`TACTIC_*`、`TOOLTIP_*` 等界面前缀 |
| `gameplay.csv` | 地图、战区、机体、进化、BOSS、奖励与事件文本 | 不属于其它四类的玩法域 key |
| `skills.csv` | 技能、属性轴、装备、状态、稀有度与配装文本 | `UPGRADE_*`、`ATTR_*`、`EQUIPMENT_*`、`STATUS_*` 等 |
| `meta.csv` | 资料库、图鉴、信息手册、成就与局外商店文本 | `ARCHIVE_*`、`CODEX_*`、`INFO_*`、`METASHOP_*` 等 |
| `radio.csv` | 全部无线电说话人和台词文本 | `RADIO_*`，不得放入其它分表 |

构建与审计的分表清单以 `scripts/i18n_catalog.gd` 为准。新增文本时先按前缀选择分表；
新增分表时还必须同步该清单与 `project.godot` 的翻译资源注册。
