# 2026-09-07 本地化文本盘点

本次以 `main@ed944a0` 的已上传内容和当前工作区文本为起点，只修订本地化源表及其生成资源。
GitHub `origin/main` 已实时核实为 `ed944a0046c44579085b3c22e79d95a44ffa9c1a`；检查开始时五份 CSV 没有未提交改动。
旧 `translations.csv` 已在 2026-08-10 拆分并删除，历史页面不是当前文本入口。

## 文本清单

| 源表 | 本次修订后 key 数 | 内容 |
|---|---:|---|
| [interface.csv](../../i18n/interface.csv) | 287 | 菜单、HUD、控件与界面 |
| [gameplay.csv](../../i18n/gameplay.csv) | 454 | 玩法、地图、奖励、王牌背景与 BOSS 横幅 |
| [skills.csv](../../i18n/skills.csv) | 439 | 技能、装备、状态与属性 |
| [meta.csv](../../i18n/meta.csv) | 269 | 资料库、图鉴、手册与局外成长 |
| [radio.csv](../../i18n/radio.csv) | 107 | 无线电说话人与台词 |

合计 1,556 个唯一 key，每项有中文、英文、日文三列。数字只记录本次审计，不作为永久数量门槛。

## BOSS 与决战内容

| 内容 | 名称和登场横幅 | 敌情图鉴 | 无线电 |
|---|---|---|---|
| Wraith Squadron | 已有 | 名称、介绍及入口已有 | 专属序列已有 |
| Ladon Strike Group | 已有 | 名称、介绍及入口已有 | 专属序列已有 |
| Mother Goose | 已有 | 名称、介绍及入口已有 | 专属序列已有 |
| Black Star / Hyper-A | 已有 | 名称、介绍及入口已有 | 两条专属登场台词已有 |
| Iron Serpent 装甲列车 | 已有；本次修订调试介绍 | 只有名称，未登记独立图鉴入口或介绍 | 未登记专属序列，使用通用回退 |
| BEHEMOTH 陆地航母 | 已有 | 只有名称，未登记独立图鉴入口或介绍 | 未登记专属序列，使用通用回退 |
| The Crucible | 已有；本次修订调试介绍 | 只有决战名称，未登记独立图鉴入口或介绍 | 明确关闭统一登场喊话；主题不是角色 |

注册与文本消费以 [BossRegistry](../../scripts/survivor/boss_registry.gd)、
[EnemyCodex](../../scripts/meta/enemy_codex.gd)、
[无线电序列](../../resources/chatter/radio_chatter.json) 和
[TheCrucibleEncounter](../../scripts/survivor/the_crucible_boss.gd) 为证。
“缺独立图鉴入口”属于内容接入现状，不是已引用翻译 key 丢失；本次不把未接线的新文本当作已完成的图鉴或对白。

## 本次修订

- The Crucible 的旧介绍为六队 27 架；按现有实现同步为 17 支 Ace 队加 Hound 双机，共 18 队 73 架，同时最多三队，灭队后 3 秒补队。三语同步。
- 装甲列车旧介绍写十五节；同步为十四节，并说明从尾向前击破、断节加速与侧舷电磁炮。三语同步。
- 日文 `HUD_WEAPON_COOLDOWN_FMT`、`HUD_WEAPON_RELOAD_FMT`、`HUD_WEAPON_OVERHEAT_FMT` 的 `%.1秒` 修为 `%.1f秒`，与实际数值格式化调用一致。
- `CODEX_THE_CRUCIBLE_NAME` 从 gameplay 移至 meta，key 和三语内容不变，消除分类错位。
- 本地化目录说明补充旧总表停用时间及当前五表入口。

## 验证范围

静态检查覆盖五表结构、空译文、重复 key、`_FMT` 三语占位符、脚本/资源中的完整字面量引用、已登记图鉴的动态名称/介绍 key、BOSS 注册表的 28 个名称与横幅 key、无线电 JSON 的 95 个唯一文本引用。
字符串扫描中的日志事件名、内部 ID 与动态前缀须人工排除；不把它们视为缺失译文。

验证结果：

- 静态审计：1,556 个唯一 key；四列结构、空译文、重复 key、三语格式符及上述实际引用均无错误。
- `bench/run.cmd i18n_build 5 120 Shadow Headless`：15 份资源生成成功，wrapper 退出码 0；仅复制内容发生变化的 10 份生成资源。radio 源文案没有新增，生成资源统一重建。
- `bench/run.cmd career_archive 5 120 Shadow Headless`：62 通过、0 失败，wrapper 退出码 0；覆盖三语 BOSS 名、已登记敌情条目、手册与翻译资源注册。
- `verify_player_ref_holders.py`：漏登记 0；`verify_docs.ps1`：文档链接、spec 登记与元数据通过；本次文本 diff 无空白错误。
- 索引检查：当前共享工作区有 5 处东京地图测试函数的行号漂移，全部位于本次未修改、未上传的 `docs/reference/code-index.md`。另从已提交 HEAD 导出隔离快照验证，232 份文档、606 个锚点全部通过；此次新增报告没有行号锚点。
- 两次 Godot 运行仍输出系统根证书读取失败，以及退出时 4 个 ObjectDB / 2 个资源未释放的告警；没有触发 wrapper 运行时错误门，不将此结果表述为无告警或无泄漏证明。

此次是文本与资源修订，不声明全部技能数值文案已逐项重新平衡，也不替代三语实机视觉验收。
