<!--
================================================================================
AGL Spec 模板 —— 设计单一数据源（SSOT）

复制本文件到下方约定目录，删掉所有模板说明注释后填写。

目录映射（目录与 kind 不是一回事）：
  enemies/  -> kind: enemy        bosses/   -> kind: boss
  weapons/  -> kind: weapon       skills/   -> kind: skill
  aircraft/ -> kind: aircraft     events/   -> kind: event
  systems/  -> kind: system | balance | map，以及跨域批次

稳定身份使用相对路径（如 aircraft/a-10、enemies/a-10）；不同目录允许同名。

核心契约（必读，违背就失去"靠文档重建"的能力）：
  1. specs/ 回答 "做什么 + 为什么 + 全部数值"。这是权威源。
  2. reference/（enemy-index / script-index / code-index）只回答 "在哪"（行号指针）。
  3. 本文件【禁止出现行号】。行号易腐烂；要查"代码在哪"去 reference/。
  4. 重建测试：假设所有 .gd / .tres 全部删除，只有本文件 —— 能不能一字不差地
     重做出同一个东西？凡是只在代码里、本文件没写下的数值/公式/行为，都是重建漏洞。
  5. 数值表里写【真实数值】，不是"见 .tres"。.tres 是落地副本，spec 是权威。
     若数值由公式生成，写公式 + 一个样例值。
  6. 涉及主界面 / HUD / 游戏内面板 / UI 视觉与交互时，默认继承
     systems/ui-design-guidelines 的稳定通用规则。普通 UI 实现、视觉和排版调整默认不回写
     该规范，也不要求另写差异 spec；只有用户明确要求写入规范或确立通用规则时才更新。
     不得另建并行 UI 通用规范。

工作流（doc → task pipeline）：
  设计阶段 — 填 §1~§5，status: draft → 你 review 后改 approved
  执行阶段 — 按 §6 实现计划 逐条打勾，代码从 spec 派生（执行很 cheap）
  收尾阶段 — 跑 §5 验收，更新 §7 锚点，写 §8 变更记录，status: done
  全阶段   — 建档当天登记 _INDEX.md；状态或 reconstruction_complete 改变时同步总表
================================================================================
-->
---
id: <kebab-case-id>                 # 与文件名一致
kind: boss                          # boss | enemy | weapon | skill | aircraft | system | balance | map | event
status: draft                       # draft | approved | in-progress | done | superseded
schema_version: 1
spec_version: 1                     # 本 spec 的迭代版本，每次实质改动 +1
owner: <谁负责设计>
depends_on: []                      # 其它 spec 的相对键；同名跨目录时写 aircraft/a-10 这类完整键
reconstruction_complete: false      # 数值/行为是否已全部写下、足以脱离代码重建
---

# <中文标题>

> 一句话定位（玩家视角：这是什么、给玩家什么体验）。

## 1. 设计意图（Why）

<!-- North star。为什么要有这个东西，解决什么体验缺口。
     必过 docs/DESIGN_PHILOSOPHY.md 的 Litmus 测试，列出相关的几条。
     这是后面所有数值的"宪法"——数值争议时回到这里裁决。 -->

- **体验目标**：
- **Litmus 自检**（引 DESIGN_PHILOSOPHY 对应条目）：
- **反模式规避**：

## 2. 数据定义（What —— 全部数值，权威源）

<!-- 重建的核心。把每一个字段、每一个数值写成表。
     这一节写完整，代码全丢也能照抄回来。不要写"见 xxx.tres"。 -->

### 2.1 基础属性

| 字段 | 值 | 说明 |
|---|---|---|
|  |  |  |

### 2.2 <子系统/分类数值表，按需增删>

| | | |
|---|---|---|

## 3. 行为与公式（How）

<!-- 状态机、公式、判定逻辑，用伪代码/状态表表达，不引行号。
     "受击角度免伤 = 0~60°→0×, 60~120°→0.3×, 120~180°→1.0×" 这种。
     有状态机就画状态表：状态 | 时长 | 触发转移 | 效果。 -->

### 3.1 <状态机/主循环>

| 状态 | 时长/触发 | 效果 |
|---|---|---|
|  |  |  |

### 3.2 <公式/判定>

## 4. 结构与组成（Structure）

<!-- 由哪些部件/子节点/子系统组成，它们如何关联（声明式，不写挂载行号）。
     例如 boss 的 mounts 列表、子控制器、overlay；技能的注入点类别。 -->

## 5. 验收标准（Acceptance / Litmus）

<!-- 可观察的通过条件，做完后逐条勾。包含性能守则与已知 seam 检查。 -->

- [ ] <可观察行为 1>
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（见 performance-guidelines）
- [ ] 已知 seam 未触碰 / 已妥善处理（见 architecture/known-seams.md）
- [ ] i18n：玩家可见文本走 tr()，三语已补（见 reference/i18n.md）
- [ ] 文档：本 spec 已登记 _INDEX；状态/重建标记一致；当前文档无失效相对链接

## 6. 实现计划（Task Pipeline —— 工作令）

<!-- 这一节就是工单。设计定稿后，按阶段逐条实现并打勾。
     每条尽量是一个可独立验证的小步。执行是 cheap 的下游动作。 -->

### 阶段 1 — <名>
- [ ] 任务
- [ ] 任务

### 阶段 2 — <名>
- [ ] 任务

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

<!-- 实现落地后，把"代码在哪"的指针放这里，并同步到 reference/ 索引。
     本节内容【会腐烂】，不是权威；§1~§4 才是。只列文件与符号，禁止精确行号。 -->

| 关注点 | 文件 |
|---|---|
| 主逻辑 | `scripts/...` |
| 参数资源 | `resources/....tres` |
| 注册/接线 | `scripts/...` |
| reference 索引 | enemy-index.md / script-index.md 的对应条目 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| YYYY-MM-DD | 1 | 初稿 |
