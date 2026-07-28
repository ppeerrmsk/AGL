# 2026-07-26 起手机解锁与生涯商店（spec career-shop）

用户六条规则（同日紧接 career-archive 批）：起手只有 F-15；首败航母解锁 F-14；30 地面击杀解锁 A-6；
幻影花钱购买；首次机场停靠上架"停靠送僚机"商品（现机制改购入后生效）；首次撤离上架"行动时间+30s"。

权威设计见 [specs/systems/career-shop.md](../specs/systems/career-shop.md)。
探索结论：A-6E 已完整实装且本就是 T1 起手四选一之一（F-15/F-14/A-6E/幻影 III）——本批为纯门控，无新机体。

## 本批改动

- **新增** `scripts/meta/meta_shop.gd` — MetaShop AutoLoad（user://meta_shop.cfg 只存已购集合；
  解锁/上架条件**实时读 CareerArchive 不落盘**）：3 件商品（幻影 2000 / 停靠僚机 3000 / +30s 2500，
  价格草案）+ 纯静态判定 `aircraft_unlock_ok` / `item_listed_ok` + `buy()`（MeritLedger.spend）。
  project.godot 注册；main_menu 删存档补 `MetaShop.debug_reset()`。
- **选机门控**（survivor_select.gd）：PLAYABLE_LIST 补 `id` 字段；新增 `_effective_list()` 按解锁态
  翻锁定标志，按钮文本 = 解锁条件句（A-6E 带 %d/30 进度）；**boss debug 链路放行**（debug 全谱选机铁律）。
  2026-07-27 用户裁定改版（spec v2）：从 dev_locked 全信息形态改 **locked 占位形态**——未解锁机型
  不加载档案、名字 ???、无武器/数值/描述，只留解锁条件句。
- **消费点**：
  - `_on_dock_docked` 送僚机段加门控：正式局需持有 `dock_wingman`；非正式局视为已拥有（保 bench）。
    首次机场停靠且未购时弹 `METASHOP_LISTED_TOAST` 上新提示。
  - `WARZONE_PHASE_DURATION` **const → var**：正式局购入 `op_time_30s` 后 `_ready` +30s；
    HUD 倒计时/超时判定/补给 clamp/F6 全走同一变量自洽。顺手修好 survivor_debug_zone 经
    `get()` 读常量取 null 的隐性 bug（var 后可读）。
- **商店 UI**：新增 `scenes/meta_shop.tscn` + `scripts/meta/meta_shop_ui.gd`（主菜单新按钮进入）：
  商品三态按钮复用 LOADOUT_BTN_*，未上架灰条显示上架条件，功勋徽章实时刷新。
- **i18n**：MENU_META_SHOP_* / METASHOP_* / UNLOCK_HINT_* 共 16 key 三语，已重导入。
- **测试**：`scripts/tests/test_meta_shop.gd`（bench key `meta_shop`，21 断言：解锁判定/上架判定/
  购买早退/roundtrip；真功勋零变动）。`--bench=all` 回归门 40 项 PASS；verify 双工具绿。

## 遗留

- 价格三件为草案（单局功勋收入 ≈2,500~7,500，现有机库件 80~400 明显低估——留经济平衡批统一处理）
- spec §0 落地解释待用户确认（"+30s"一次性买断不可叠加、"机场停靠"才上架、非正式局放行等）
- §5 playtest 未跑；起手收紧后攻击/电战线解锁节奏需实测体感
- playable-aircraft-workflow.md 的 PLAYABLE_LIST 示例与"现有主角清单"早已过期（另行清理）
