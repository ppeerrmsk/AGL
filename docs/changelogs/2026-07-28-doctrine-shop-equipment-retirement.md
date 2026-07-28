# 2026-07-28 — 槽位配件系统退役 + doctrine 学说搬进生涯商店

> spec：[docs/specs/systems/doctrine-unlocks.md](../specs/systems/doctrine-unlocks.md)（用户 2026-07-27 拍板，本批全落地，余 playtest 定价校准）

## 一句话

出击前的配件机库整层删除（选机 → 直接出击）；6 张 doctrine 词条解锁件降级为常量表
搬进主菜单生涯商店；局外功勋从此只买"这局能抽到什么牌"，不买"这局直接强多少"。

## 拆除

- `scenes/survivor_loadout.tscn` + `scripts/survivor/survivor_loadout.gd`（~560 行机库 UI）
- `scripts/meta/loadout_ledger.gd`（AutoLoad，已从 project.godot 摘除）+ `scripts/meta/equipment_part.gd`
- `resources/equipment/` 全 18 个 `.tres`（12 数值件 + 6 doctrine）
- `PlayableAircraft.slot_budget` 字段、`SurvivorPlayableSetup` 的 apply_to_aircraft 调用、
  `main_menu` 的 LoadoutLedger.debug_reset
- i18n 死 key 45 条（21 机库 LOADOUT_* + 24 数值件 EQUIPMENT_*_T*）+ CSV 3 行历史重复

## 新增 / 迁移（scripts/meta/meta_shop.gd）

- `DOCTRINES` 常量表（6 张：id/价格/i18n key/keyword/颜色）+ `GATED_KEYWORDS`
- `is_keyword_unlocked` / `is_upgrade_gated`（AND 语义；`sig_*` 豁免；boss debug fail-open）
- `doctrine_listed_ok` 渐进上架（嗜血+骑士买齐才放进阶 4 张）；`buy`/`get_price`/`is_listed` 泛化
- `migrate_legacy_loadout`：user://loadout.cfg 的 doctrine 拥有态一次性搬入，
  数值件按 D2 裁决**不退款**丢弃，legacy 文件删除（幂等）
- `MetaShopUI` 两分区：【战术学说】（徽章+词条声明+flavor）+【生涯商品】

## 消费点

- `survivor_mode` 升级三选一 / 三轴卡池：`LoadoutLedger.is_upgrade_gated` → `MetaShop.is_upgrade_gated`
- **修漏点**：`zone_data._nextgen_candidates` 补门控——此前战区奖励 NEXT_GEN 池不查 doctrine，
  `evasion_stealth`(stealth) / `fear_on_lock`(fear) 可无证获得；顺带删除零调用死代码 `_build_reward_pool`
- **修冲突**：9 条 `sig_*` 机体签名技（su27/rafale/x13/a6e/f22/yf23/mig41/x09/x77）豁免
  doctrine 二次门控，保住"每机一条专属技"（aircraft-signature-skills）承诺

## 验证

- `--bench=meta_shop` 21 → **47 断言全绿**（门控 AND / sig 豁免 / 渐进上架 / 定价表 / 迁移幂等）
- 回归门 `--bench=all` **40 项 PASS**
- `verify_player_ref_holders` ✓；`verify_doc_anchors` ✓（顺带回填 39 个腐烂锚点，含上批遗留）

## 待办

- playtest：6 张学说定价手感（chivalry 700 … stealth 1400，全买 6400；公式 `100×门控技能数+300`）
