---
id: t0-low-t1-aircraft-expansion
kind: system
status: done
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [aircraft-evolution-tree, player-aircraft-power-curve, radar-range-normalization, aircraft-signature-progression]
reconstruction_complete: true
---

# T0 初始层与低位 T1 扩谱

## 1. 设计意图

- 以低预算而非年代定义 T0，让第一局四选一已经具有完整的机炮、导弹和规避循环。
- T0 在 LV1 起步并作为局外采购后的追加起手机；低位 T1 在 LV4 取得。
- 原 F-15 / F-14 / A-6E / Mirage III 四张选机卡完整保留，同时仍作为 LV5 标准 T1 进化节点。
- 同一 Tier 的低位 / 标准差异只存在于节点高度和等级门，不新增 T0.5 或 P0。
- 现实资料只用于保留机型性格，最终速度、雷达、武器和生存性服从 AGL 全谱曲线。

## 2. 节点与身份

| 层 | 节点 | 等级 | 取得 | 主轴 |
|---|---|---:|---|---|
| T0 | MiG-21F-13 / F-104C / J 35F / EA-6B | 1 | 生涯商店各 1000 功勋解锁后可作为起手机 | 斗 / 骑 / 斗 / 策 |
| 低位 T1 | MiG-23 / F-4E / Jaguar GR.1A | 4 | 只能进化 | 斗 / 骑 / 策 |
| 标准 T1 | F-15 / F-14 / A-6E / Mirage III | 5 | 保留原选机页取得方式，也可由 T0 进化 | 保留现有身份 |

层数为 `T0/T1/T2/T3/T4/T5 = 4/7/16/8/7/8`，总数 50。

## 3. 进化边

| T0 | 低位 T1 | 标准 T1 |
|---|---|---|
| MiG-21F-13 | MiG-23 / Jaguar / F-4E | F-15 |
| F-104C | F-4E / MiG-23 | F-14 / F-15 |
| J 35F | MiG-23 / Jaguar | Mirage III / F-14 |
| EA-6B | Jaguar / F-4E | A-6E / Mirage III |

- MiG-23 → MiG-31 / Su-27 / F-15C / F-16 / Mirage 2000。
- F-4E → F-15C / F-15E / F/A-18E / MiG-31 / Tornado。
- Jaguar → A-10 / Harrier / Viggen / Tornado / Su-34。
- 所有 T0 有 4 个出口；所有低位 T1 有 5 个出口；T2 以后沿用现行树。

## 4. 专属技能占位

- 七架新机只建立详情页可见的预留槽，名称可先使用调查报告占位名。
- 占位不是 `SurvivorData.UPGRADES` 条目，不计入技能总数。
- 不进入普通抽卡、战区奖励、功勋商店、机场装备、F4 Debug 或技能重放。
- 机场当前机为占位机时，保留选项显示“效果待设计”，按钮禁用；玩家仍可继续或进化。
- 后续只有用户给出效果后，才建立独立技能 spec、UPGRADES 条目、i18n、Debug 和验收。

### 4.1 T0 开局机场等价礼包（不是专属技能）

四架 T0 比标准 T1 起手机多经历一次进化，作为补偿，**只有在本局作为起手机时**各获得一项完整的机场等价收益：

| T0 起手机 | 开局收益 | 正式资源 / 账本语义 |
|---|---|---|
| MiG-21F-13 | 机炮吊舱 | 直接授予现有 `gun_multishot` 1 层，不增加三轴点 |
| F-104C | FFAR 火箭弹吊舱 | `rocket_ffar.tres` 入局内武器库 |
| J 35F Draken | QAAM 格斗弹 | `qmaam_missile.tres` 入局内武器库 |
| EA-6B | ESM 电子战吊舱 | `esm_pod.tres` 入局内武器库 |

- 礼包只在 Survivor 开局读取所选 `PlayableAircraft` 时结算一次；沿进化树后来取得同型机不触发。
- 特殊武器不得烤进 `player_*.tres`。它们复用正式战区武器授予和 `SurvivorPlayer.weapon_inventory`，因此换机 / 进化后自动继承。
- `gun_multishot` 复用正式技能账本、归属分发和重放链，但不发普通升级卡附带的轴点；它与七架机的签名技能占位互不替代。
- J 35F 不再同时获得短促格挡或眼镜蛇；QAAM 就是该机唯一开局补偿。F-104C 的补偿只使用 FFAR，不改主导弹与机炮底线。

### 4.2 独立顶视模型交付

- 七架新增现实机必须完成 `aircraft-top-view-silhouettes` 的可靠参考、外轮廓提取、manifest 登记、运行时映射、静态审计与 Godot Visual QA。
- F-104C / F-4E / MiG-23 可复用已经按对应真实型号审查过的现有蒙版；MiG-21F-13 / J 35F / EA-6B / Jaguar 必须新增逐机参考蒙版。
- 在独立模型验收完成前，本扩谱批次不得视为交付完成；旧 polygon 回退只适用于找不到可靠资料的虚构 / 未定型机，不得成为现实机新增流程的默认结果。

## 5. 验收

- [x] AircraftDB 可加载 50/50 档案；选机页保留原四卡并追加四张 T0 采购卡，共八卡。
- [x] 50 节点全部有入边；非终端节点出口满足表中要求。
- [x] 标准 T1 原四卡仍在选机页；T0 四卡各自购买后可选，未购时不泄露档案数据。
- [x] 七个占位在详情可见但不能购买、装备、授予或生效。
- [x] 四架 T0 作为起手机时各获得一项机场等价礼包；作为进化结果时不重复获得，特殊武器随换型继承。
- [x] 七架新增现实机全部命中独立 reviewed 顶视轮廓，不再回退通用旧模型。
- [x] `player_params`、`evo_detail`、`attr_gates`、`meta_shop`、`sig_skills` 与全量回归通过。

## 6. 实现计划

- [x] 七份 AircraftParams 与 PlayableAircraft。
- [x] AircraftDB、正式起手、i18n 与进化树。
- [x] 生涯商店四项 1000 功勋采购与八卡滚动选机页。
- [x] 占位映射、机场禁用态与商店隔离。
- [x] 全谱雷达 / 武器平滑化和敌机成长修正。
- [x] T0 开局礼包走正式技能 / 武器库存入口，并覆盖开局与进化继承回归。
- [x] 七架新机顶视模型补齐，来源、alpha 哈希、静态审计和 Visual 样张齐全。
- [x] focused、全量与 Visual 验收。

## 7. 索引锚点

| 关注点 | 文件 |
|---|---|
| 机体档案 | `resources/player/player_*.tres` / `playable_*.tres` |
| 注册与起手 | `scripts/survivor/aircraft_db.gd` / `survivor_select.gd` |
| 进化树 | `resources/evolution/evolution_tree.json` |
| 占位 | `scripts/survivor/survivor_data.gd` / `evolution_ui.gd` / `meta_shop.gd` |
| T0 开局礼包 | `scripts/playable_aircraft.gd` / `survivor_mode.gd` / `survivor_player.gd` |
| 顶视模型 | `resources/aircraft_silhouettes/` / `scripts/aircraft_silhouette_catalog.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 用户批准开始实现；七个专属技能只留不可生效占位。 |
| 2026-08-27 | 2 | 保留既有四张选机卡；新四架改为生涯商店采购后的追加起手机。 |
| 2026-08-27 | 2 | 实装收口：八卡选机页、四项采购、50 机进化树、七占位与平滑化回归全部通过。 |
| 2026-08-28 | 3 | 四架 T0 增加仅开局结算的机场等价礼包：MiG-21 机炮吊舱、F-104C FFAR、J 35F QAAM、EA-6B ESM；特殊武器经局内库存继承。补齐七架现实机独立顶视模型，并把模型生产列为本批交付硬门。 |
