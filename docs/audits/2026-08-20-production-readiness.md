# 2026-08-20 文档与铺量准备审计

## 范围与证据

本轮检查当前指导层、spec 状态、reference 指针、systems 架构叙述与 planning 生命周期；以
`project.godot`、`evolution_tree.json`、自动生成技能表、BossRegistry 和当前代码索引核对易变事实。
历史 changelog、已关闭 handoff 与旧 roadmap 原文保留为当时证据，不把它们批量改写成今天的事实。

审计开始时：152 份已登记 spec；85 done、47 in-progress、12 draft、6 approved、2 superseded；
83 份使用纯值 `reconstruction_complete: true`，另 1 份带行内注释但仍被元数据校验器识别。机械验证在修订前已经通过：当前 Markdown 链接、spec
登记/元数据一致，191 份受检文档的 674 个代码锚点全部有效。

本轮归档 3 份冲突草案、把已有工程主体但仍有明确尾项的局内武器库转为 in-progress 后，当前分布为：
85 done、48 in-progress、8 draft、6 approved、5 superseded；84 份为 `reconstruction_complete: true`。
数量只用于本次审计基线，今后以 `_INDEX` 和验证脚本的实时结果为准。

## 发现的概念腐烂

- 当前入口混用 41/43 机、41/43 签名技能与 146/152/165 技能数量；数据真源现为 43 机、43 条
  签名技能、165 条自动生成技能。
- `evolution-vertical-slice` 仍以未完成计划口吻存在，但其 12 节点切片已被正式 43 机树、三轴门槛、
  局内武器库和当前切控语义取代。
- 早期 `ace-system`、`squad-upgrade-ownership`、`meta-progression` 仍标 draft，内容却与当前“当前操控机
  为王牌生效对象、技能归属 v6、特殊武器纯局内、生涯商店节制解锁”直接冲突。
- survivor-loop 同时保留“3200px 前方扇形已退役”和“验收前方 3200px”的互斥陈述；当前真相是普通
  增援从地图边缘集结，hunter 缺口时的拦截波才从前方边缘来，任务/追击按各自遭遇几何派生。
- DESIGN_PHILOSOPHY 仍挂着 2026-07 的两个待校准项：20–30 分钟旧时长，以及“Build 还是机型”二选一。
- spec status 被当成长期愿望池：不少 `in-progress` 已完成主体，只因模糊 playtest 债长期不关闭。

## 本轮裁决

- 当前单张地图出击目标收口为 12–20 分钟；未来三图战役另算总墙钟。
- 生存模式定为“机型路线 × Build 双主轴的 squad roguelike”，两者都必须产生玩家决策。
- 旧 ACE / 绑机型升级 / 局外武器 loadout 三份草案归档为 superseded；当前权威回链正式 specs。
- 铺量生产单位改为“地图内容包”，并建立 P0 底座收口 → 东京湾母版 → 沙漠独立成局 → 海洋独立成局
  → 三图串联的顺序。
- 状态、证据与完成定义拆开：focused Shadow 不是 Visual，Visual 不是完整局，单项 done 也不是地图发布就绪。

## 仍需后续执行的债

- 47 个原 `in-progress` 需要专门的状态关闭批；本轮不在没有对应运行时证据的情况下批量改成 done。
- CSG 缺独立总 spec；基础武器族、早期敌人和绝大多数玩家机仍有重建缺口。
- raster basemap 两套路径仍差最终同位 Visual 裁决；map 2/3 尚未形成完整内容包。
- 三图战役的双队快照、失败/退出、BOSS 顺延与沙漠主 BOSS 仍是明确 draft，不由实现侧擅自补值。
- 性能旧门已由 C1 混合全可见战场取代；首次三次 Visual 基线均出现低于 60 的帧，铺量前必须按
  [性能基线审计](2026-08-20-performance-validation-baseline.md) 完成尖峰归因与收口。

## 制作人补充裁决（同日）

- 43 机、165 技能与当前 4 组 BOSS 都是基线，不是封顶；后续扩充必须服务约 20 小时持续新体验、
  地图身份或明确玩法空位。新 BOSS 仍是明确内容需求，不得把现有四组误写成最终阵容。
- 功勋与所有解锁系统需要围绕至少约 20 小时持续内容重新量化；核心循环首局成立，进阶功能循序开放，
  不能用重复 grind 伪造时长。
- 60 FPS 继续死守，但性能修复必须保护大规模战斗群 fantasy；AI 战斗群/小队级共同攻击与脱离是下一步
  优化方向，精确行为仍待独立 spec。
- 音效、音乐、机体与地图细节、战斗特效、提示语言、击杀/状态变化和 Build 变强可视化进入正式生产线，
  不再作为发布前尾项。执行入口见 [音画生产工作流](../planning/audio-visual-production-workflow.md)。

## 权威边界

今后的阶段顺序与完成线看 [content-production-workflow](../planning/content-production-workflow.md)；
设计数值看 [specs/_INDEX](../specs/_INDEX.md)；代码位置看 `docs/reference/`。本审计只记录本轮判断与证据，
不替代上述权威源。
