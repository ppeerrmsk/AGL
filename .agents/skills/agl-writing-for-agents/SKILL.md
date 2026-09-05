---
name: agl-writing-for-agents
description: "创建或修改 AGL 的 AGENTS/CLAUDE 导航、Codex skill 或供代理读取的操作文档，同时保持现有文档分层、触发指针和验证入口。仅在用户显式要求代理文档工作或调用本 skill 时使用。"
metadata:
  upstream-repository: "https://github.com/mattpocock/skills"
  upstream-revision: "3cca18b368ae95cdbdebbff572ccafa662551015"
  upstream-skill: "writing-for-agents"
  license: "MIT"
---

# 为 AGL 代理编写文档

目标不是增加文档数量，而是让代理在正确条件下读取正确权威源，并能判断工作何时完成。

当前用户要求和根目录 `AGENTS.md` 优先于本 skill。若规则冲突，保留项目权威，并指出需要修订的 skill 条款，不能静默折中。

## 先判定文档层

- `AGENTS.md`：始终加载的导航、灾难性硬约定和条件指针。
- `docs/specs/`：玩法意图、行为、全部数值/公式、验收和状态的设计 SSOT；禁止代码行号。
- `docs/reference/`：易腐烂的代码/资源位置指针；锚点写成 `path:line symbol`。
- `docs/systems/` / `docs/architecture/`：跨文件流程、架构取舍与 known seams。
- `docs/planning/`：生产顺序和未来工作，不冒充已实现契约。
- changelog、audit、handoff：历史证据，不冒充当前 SSOT。

不要创建并行的 `CONTEXT.md`、`docs/adr/`、`docs/agents/` 或第二套通用 UI 规范。若现有分层无法承载内容，先说明缺口和建议落点，再由用户决定是否扩展结构。

## 写作规则

1. 每个指针同时写清“什么情况下读取”和“去哪里读取”；仅列文件名而没有触发条件的指针不完整。
2. 让步骤带有可核验完成条件。把只在某个分支需要的长参考放进目标文档，不塞进始终加载的 `AGENTS.md`。
3. 灾难性或高频翻车守则应保留在始终加载层，不能仅为了缩短文本而下沉。环境容易查到的事实通常不重复，除非它是昂贵查询、已知陷阱或安全门。
4. 一个含义只保留一个权威位置；其他文档使用指针。不要把一次 UI/实现选择自动升级为通用规范，除非用户明确要求。
5. 面向代理的说明使用紧凑、可搜索的中文和真实符号名。先描述 owner、入口和完成线，再补原因；避免读完整大型脚本的指令。
6. 修改 `AGENTS.md` 或 `CLAUDE.md` 时只编辑用户指定的消费者。若规则显然需要跨代理同步，先报告两者差异和建议，不静默复制或覆盖。
7. 保留无关脏改动；文档任务不授权整理附近内容、重写历史或提交。

## Skill 文档

创建或修改 skill 时，名称和 description 必须精确区分触发范围；高风险动作在执行点获取授权，不能靠含糊描述扩大权限。把条件流程放入引用文件，只在该分支需要时读取。项目级 skill 优先使用 `agl-` 命名空间，防止影响其他仓库。

## 验证

按改动范围运行：skill frontmatter 验证、`tools/verify_docs.ps1`、定点 `verify_doc_anchors.py` 和 `git diff --check`。文档-only 或 skill-only 修改不运行 Godot；若同时改了运行时代码，仍遵守 focused → `all` 的项目终态门。

完成时说明修改了哪一层、哪些指针会触发它、验证结果和任何未解决的权威冲突。
