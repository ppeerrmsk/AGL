---
name: agl-code-review
description: "只读审查 AGL 的分支、提交、PR 或未提交改动，分别检查项目规范、设计 spec 和验证证据，并覆盖脏工作树中 staged、unstaged 与 untracked 的实际范围。仅在用户显式调用本 skill 时使用。"
metadata:
  upstream-repository: "https://github.com/mattpocock/skills"
  upstream-revision: "3cca18b368ae95cdbdebbff572ccafa662551015"
  upstream-skill: "code-review"
  license: "MIT"
---

# AGL 三轴代码审查

审查是只读工作：不修改文件、不暂存、不提交、不推送，也不把无关脏改动纳入结论。

当前用户要求和根目录 `AGENTS.md` 优先于本 skill。若出现冲突，按前两者确定审查范围，并明确记录没有采用的 skill 条款。

## 1. 固定审查范围

先读取 `git status --short --branch`，记录当前分支、固定点与脏工作树。用户指定 commit、branch、tag 或 merge-base 时使用该值；若用户只说“当前改动”，默认以 `HEAD` 为基线并覆盖 staged、unstaged 和相关 untracked 文件。只有基线会实质改变审查结果且无法可靠推断时，才询问一个简短问题。

分开收集并标注：

- 固定点到 `HEAD` 的已提交差异。
- staged 差异。
- unstaged 差异。
- 与请求范围有关的 untracked 文件。

不要只使用 `<base>...HEAD` 声称审过 WIP；该视图不会覆盖全部工作树状态。先列范围，再读 diff 和相关上下文。

## 2. 三个独立审查轴

### Standards

检查根目录 `AGENTS.md` 和任务相关规范，包括索引读取、性能守则、i18n、生命周期、UI 例外、Debug 可达性、Godot 启动约束及脏工作树保护。区分硬违规与代码气味；项目明确规则优先于通用启发式。

### Spec

从用户请求和 `docs/specs/` 的权威 spec 核对行为、全部数值/公式、失败路径、范围与 §5 验收。检查未实现/只实现一半、实现错误和未请求的范围扩张；同时检查 §7 锚点、`docs/specs/_INDEX.md` 与相关 reference 索引是否同步。

### Evidence

核实已有证据实际证明了什么：focused bench、runtime-error gate、`all`、`lifecycle_gauntlet`、性能负载、Visual fixture 和真实游玩各自独立。不要把测试名称、旧日志或 headless 绿灯当作玩家流程验收；把缺失证据列为 proof gap，而不是自动等同于代码缺陷。

对非平凡审查，在协作工具可用且独立上下文能提高质量时，为三个轴分别使用只读子代理，再由主代理去重和核验证据。子代理不得修改共享工作树。

## 3. 输出

先给 findings，按 P0–P3 排序。每条必须包含：轴、文件和紧凑行号、具体影响、触发条件或证据、最小修复方向。不要提交只有偏好、已由工具自动保证或无法形成行动的信息。

随后给出：

- 实际审查范围及未覆盖内容。
- 三轴各自的通过/问题数摘要。
- 已存在的验证证据和仍需运行的检查。

若没有发现，明确写“没有可执行 finding”，同时保留尚未验证的风险或测试缺口。
