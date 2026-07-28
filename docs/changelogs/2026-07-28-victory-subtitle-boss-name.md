# 2026-07-28 通关结算副标题：按实际击败的 BOSS 变名

## 症状

打赢任意 BOSS，结算面板副标题永远是「Wraith 中队已被击毁」。
`HUD_VICTORY_SUBTITLE` 的三语文案里直接写死了 Wraith，而 `show_victory()` 的签名里
根本没有 BOSS 参数 —— 打 Ladon 战斗群 / 鹅妈妈过关也照抄雷斯中队。

（BOSS 轮换 2026-07-26 随生涯档案上线后这条才真正暴露：在那之前多数局都是雷斯。）

## 改动

- `BossRegistry.BOSS_DEFS` 每条加 `name_key` 字段 + `name_key_for(boss_id)` 静态取值器。
  **复用敌人图鉴的条目名** `CODEX_<ID>_NAME`，不新造一套 BOSS 名 key。
  与 `display_name` 分工：后者是 EventLogger / 调试用原值（不 tr），前者才是玩家可见名
- `survivor_mode.on_boss_victory` 从 `ev.encounter.boss_id` 取一次 id，同时喂给
  档案入档与 `_on_victory(boss_id)` → `hud.show_victory(..., boss_id)`
- `show_victory` 的 `boss_id` 是**带默认值的尾参**（空串 → 通用文案），沙盒与老调用方不受影响；
  未注册 id 同样退回通用文案，不会把 key 原样显示给玩家

## i18n

- `HUD_VICTORY_SUBTITLE` → `HUD_VICTORY_SUBTITLE_FMT`（`%s 已被击毁` / `%s eliminated` /
  `%s 撃破`）
- 新增 `HUD_VICTORY_SUBTITLE_GENERIC`（`敌方主力已被击毁`）作兜底

## 验证

- `--bench=all` 回归门 42 项全绿
- `--bench=career_archive` 55 通过 / 0 失败（新增 7 条断言：每个注册 BOSS 都有 name_key、
  三语有译文、未知/空 id 退空串、FMT 有译文且保留 `%s`、GENERIC 有译文）
- 三语 `tr()` 实取验证（zh/en/ja 三个 locale 下 FMT/GENERIC + 三个 BOSS 名都命中译文）
- `verify_doc_anchors.py` 全绿（顺手回填了 code-index 里 `on_boss_victory` 的历史腐烂行号）
- 待 playtest：三个 BOSS 各打一次，确认副标题跟着变
