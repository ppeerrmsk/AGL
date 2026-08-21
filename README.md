# AGL

AGL 是一个使用 Godot 4.7 开发的俯视 2D 战斗机生存沙盒。正式玩法入口是
`scenes/main_menu.tscn` → `scenes/survivor_mode.tscn`；`scenes/main.tscn` 只保留为已废弃的沙盒调试场景。

## 从哪里开始

| 目的 | 第一入口 |
|---|---|
| AI / 维护者第一次进入仓库 | [AGENTS.md](AGENTS.md) → [Reference Index](docs/reference/_INDEX.md) |
| 快速理解项目与运行时边界 | [项目概述](docs/project-overview.md) |
| 查看文档层级与文件落点 | [文档入口](docs/README.md) |
| 查询设计、数值与当前实现状态 | [Specs Index](docs/specs/_INDEX.md) |
| 按目录、文件或功能定位代码 | [Reference Index](docs/reference/_INDEX.md) |
| 新增敌人、技能、武器、BOSS 或系统 | [Playbook](docs/reference/playbook.md) |

代码导航采用三层结构：

1. [repo-layout.md](docs/reference/repo-layout.md) 回答“目录和运行时边界在哪里”；
2. [script-index.md](docs/reference/script-index.md) 回答“哪个文件负责、关键入口是什么”；
3. [code-index.md](docs/reference/code-index.md) 回答“某个功能具体落在哪个符号和行段”。

不要从头通读大型 GDScript。先走索引，再只读取目标符号附近的行段；只有索引未覆盖或需要验证跨文件引用时才全文搜索。

## 运行与验证

- 使用 Godot 4.7+ 打开 `project.godot`，F5 从主菜单启动。
- 自动化 bench 只通过 `bench/run.cmd` / `bench/run.sh` 启动，禁止直接调用 Godot CLI。
- 文档改动至少运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_docs.ps1
python tools/verify_doc_anchors.py
```

更完整的运行、性能与提交前约定以 [AGENTS.md](AGENTS.md) 为准。
