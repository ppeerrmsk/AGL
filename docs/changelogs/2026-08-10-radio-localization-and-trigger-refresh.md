# 2026-08-10 本地化分表与无线电触发更新

## 范围

- 将原本臃肿的单一 `i18n/translations.csv` 按领域拆为 `interface`、`gameplay`、`skills`、`meta`、`radio` 五份源表，并统一运行时、文档与测试指向。
- 无线电文本固定由 `i18n/radio.csv` 管理，三语资源分别生成为 `radio.zh/en/ja.translation`。
- 按用户更新的 Notion 原页同步 v8 台词与触发条件；字体、版式和音效素材不在本轮修改。

## 无线电运行时变化

- WRAITH：首次真实成员减员只播一次专属台词。
- CSG：120 秒定期 F/A-18 补充在首次成功入队后闭锁；航母沉没进入 Phase 2 时播两句序列。
- Mother Goose：只有 MQ-X 至少一架实际生成后才播 Phase 2 序列。
- 轰炸护送：使用实际任务目标坐标量化八方向，由指挥中心固定播双句。
- 战区：海战由真实存活敌军报告接触；空战/中队战仅由真实有人僚机请求支援；地面战只有气氛友军存活时感谢；机场解放三选一并代入真实长机呼号。
- `RadioChatter.say()` 只格式化 `_FMT` key，允许格式句与普通句安全共池。

## 验证

- `bench/run.cmd chatter 5 120 Shadow`：101/101。
- `bench/run.cmd boss_phase 5 120 Shadow`：33/33。
- `bench/run.cmd boss_hunter 5 120 Shadow`：119/119。
- `bench/run.cmd boss_progression 5 120 Shadow`：22/22。
- `bench/run.cmd zone_atmosphere 5 120 Shadow`：29/29。
- `bench/run.cmd i18n_build 5 120 Shadow`：五份源表三语资源成功生成；`radio` 每种语言 103 条。
- `bench/run.cmd career_archive 5 120 Shadow`：61/61；五表共 1360 个 key、跨表唯一，15 份翻译资源全部注册。

## 验证边界

完整 `SurvivorMode` Shadow 加载仍会遇到源工作区 `.godot/imported` 中字体导入缓存缺失；按本轮约定不修改字体，也不把聚焦逻辑回归写成完整实机视觉/听感验收。后续使用 Godot 4.7+ 补做 BOSS 与战区时序、队列密度、换行和音量检查。
