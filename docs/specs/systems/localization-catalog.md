---
id: localization-catalog
kind: system
status: approved
schema_version: 1
spec_version: 1
owner: user
depends_on: [systems/radio-chatter, systems/ui-design-guidelines]
reconstruction_complete: true
---

# 本地化目录拆分

> 在不改动运行时 key 的前提下，把单一翻译表拆成职责清楚、可独立审计的五张权威表；无线电触发条件与无线电文本继续分离。

## 1. 设计意图（Why）

- 降低多人修改翻译表时的冲突面，让界面、玩法、技能、局外和无线电文本分别维护。
- 保留所有既有运行时 key，拆表不是玩家可见文案改版，也不得引入重复 key。
- 无线电触发 JSON 继续回答“何时说哪一句”；`radio.csv` 只回答“这句话在各语言中怎么写”。

## 2. 数据定义（What）

### 2.1 五张唯一源表

| 源表 | 职责 |
|---|---|
| `i18n/interface.csv` | 主菜单、HUD、面板、按钮和通用界面文本 |
| `i18n/gameplay.csv` | 战斗、事件、地图、提示和玩法状态文本 |
| `i18n/skills.csv` | 技能、升级、进化和武器相关文本 |
| `i18n/meta.csv` | 生涯、功勋、商店和局外成长文本 |
| `i18n/radio.csv` | 无线电台词文本 |

每张表固定四列：`keys,en,zh_CN,ja`。构建产物为五张表乘三种语言，共 `15` 个 `.translation` 资源。旧的单表 `translations.csv` 与未登记的旧聚合产物不得继续作为权威源。

### 2.2 完整性约束

- 五表合并后 key 全局唯一；重复 key 数必须为 `0`。
- 本次迁移基线为 `1360` 个唯一 key，其中 `radio.csv` 为 `103` 行文本；后续增删以审计结果为准，不把基线写成永久数量门槛。
- `project.godot` 只登记当前 `15` 个翻译资源。
- `I18nCatalog` 提供表清单、分类查询和静态完整性审计；游戏运行时仍通过 `tr("KEY")` 消费，不改 key 名。

### 2.3 无线电权威边界

- `data/radio_chatter.json`：触发条件、事件映射、发言者和 key 的权威源。
- `i18n/radio.csv`：key 对应各语言文本的权威源。
- `RadioChatter.say()` 仅对以 `_FMT` 结尾的 key 执行参数格式化；普通 key 即使文本含 `%` 也按原文显示。

## 3. 行为流程（How）

1. 编辑者根据职责把新 key 加入唯一一张源表。
2. Godot 导入器分别生成三种语言资源，`project.godot` 加载全部十五个资源。
3. 静态审计合并五表，检查表头、空 key、重复 key、触发 JSON 引用缺失和资源登记漂移。
4. 运行时继续用原 key 查找翻译；无线电先由 JSON 选 key，再由本地化系统取文本。

## 4. 边界情况与异常处理

- key 无法明确归类时按实际玩家消费界面归类，不复制到多表。
- 旧聚合文件存在但未登记也视为迁移未完成，避免后来维护者误改错误权威源。
- 无线电 JSON 引用缺失 key 时审计失败，不用运行时静默兜底掩盖。
- 非 `_FMT` key 不做 `%` 插值，避免普通台词中的百分号触发格式异常。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 五张 CSV 均为四列且合并后重复 key 为 `0`。
- [ ] 迁移前后全部运行时 key 可解析，基线审计得到 `1360` 个唯一 key、`103` 行无线电文本。
- [ ] `project.godot` 仅登记五表对应的 `15` 个翻译资源。
- [ ] 无线电触发 JSON 的全部 key 均存在于 `radio.csv`，普通 key 不被格式化，`_FMT` key 正常格式化。
- [ ] 英文、简中、日文至少各启动一次主菜单与 HUD 聚焦验证，无缺字或 key 泄漏。

## 6. 实现计划

- [ ] 移植五表、导入资源和 `I18nCatalog`。
- [ ] 更新 `project.godot`、构建脚本与静态审计。
- [ ] 移植 `RadioChatter.say()` 的 `_FMT` 边界并补回归 bench。
- [ ] 删除旧单表与未登记聚合产物，更新 i18n reference。

## 7. 代码锚点

- 待实现后填写。

## 8. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1 | 2026-08-16 | 从历史 HUD 分支提炼五表本地化权威边界；排除生成验证文件和旧聚合资源。 |
