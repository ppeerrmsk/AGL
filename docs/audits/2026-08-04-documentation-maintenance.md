# 2026-08-04 文档体系维护审计

## 范围

本轮检查当前指导层、spec 工作流、目录导航、相对链接、spec 登记与元数据一致性，并用
`project.godot`、自动生成技能表和现有索引核对易变事实。历史 changelog 只作为证据，不批量改写。

## 已处理

- 新增 `docs/README.md`，明确文档分层、生命周期、目录落点和新文件放置规则；
- 新增 `docs/handoffs/` 约定，停止继续在 `docs/` 根目录堆交接稿；
- 合并 AGENTS/CLAUDE 的分叉事实，统一 Godot 4.7、bench 启动规则、AutoLoad 和当前索引入口；
- 修正 playbook 中后半段绕过 spec-first 的路径，并补系统类改动与目录落点说明；
- 修复当前文档的失效相对链接，历史 changelog 中的旧路径保持历史原样；
- 补登遗漏的 `flight-model-realism` spec，补齐早期 spec 元数据，并同步总表状态；
- 将已被多个细化 spec 取代的 `aircraft-evolution` 总纲标为 `superseded`；
- 校正入口文档中的 AutoLoad、技能数量、敌人规模、1–9 切控和模块化装备语义；
- 更新 spec 模板，明确目录映射、相对路径身份、登记与收尾检查；
- 刷新了 235 个腐烂行号锚点（首轮 223，补获同行简写后再修 12），当前 149 份文档的 702 个锚点全部通过；
- 扩展 `verify_doc_anchors.py --fix`，并新增 `verify_docs.ps1` 校验当前链接、spec 登记、元数据和总表漂移。

## 仍属长期债务

- `docs/specs/_INDEX.md` 仍是人工维护的大表，适合后续增加生成器或结构化校验；
- 大量早期 spec 的 `reconstruction_complete: false` 是内容缺口，不应仅为“变绿”修改字段；
- `docs/reference/` 的行号指针会持续腐烂，必须依靠 `verify_doc_anchors.py` 守门；
- 历史 changelog 中存在已失效的旧路径，保留它们是有意的历史策略，不代表当前入口断链。

## 权威边界

这份审计只记录维护动作，不是设计权威。设计状态看 `docs/specs/_INDEX.md`，代码位置看
`docs/reference/`，本轮实际差异以版本控制为准。
