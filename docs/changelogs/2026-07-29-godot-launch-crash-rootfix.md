# Godot 启动崩溃根治（2026-07-29）

## 症状

Codex 修改或运行验证期间反复弹出 Godot 4.6.2 原生“内存不能为 read”错误窗口；后台命令被模态弹窗卡住，无法自行结束。

## 根因

1. 项目级 `.codex/config.toml` 自动加载 `godot-mcp`，并把 `GODOT_PATH` 指向 GUI 版 Godot 4.6.2 Mono；现场发现 9 个重复 MCP 进程。
2. 遗留的 `--bench=fire_discipline` 进程树使用 4.6.2，在原生访问冲突后长期卡死。
3. `project.godot` 已声明 Godot 4.7 feature，旧的 bench 启动器和部分交接文档仍硬编码 4.6.2。

## 修复

- 删除项目级 godot-mcp 自动加载配置，禁止 Codex/MCP 自动拉起 GUI Godot。
- 终止重复 MCP 与卡死的 4.6.2 进程树。
- `bench/run.cmd`、`bench/run.sh` 默认发现 D 盘 Steam Godot 4.7.1，并在启动前强校验版本必须以 `4.7` 开头。
- `AGENTS.md` 登记唯一已验证路径，要求 CLI 使用 `--headless`、有限超时，禁止照抄历史 4.6.2 命令。
- 修正活跃交接/规划文档中的旧版入口；历史 changelog 保持原始记录，不作为运行指令。

## 验证

- `Godot 4.7.1 stable Steam`：`--headless --version` 正常。
- 编辑器 headless 加载项目 5 帧后正常退出。
- 主场景 headless 运行 5 帧后退出码 0，无脚本错误、无访问冲突、无残留进程。
- `bench/run.cmd __launch_smoke__ 1` 从默认 D 盘路径成功调用 4.7.1 并退出码 0；启动器不再 `pause`，避免 agent 命令挂起。
- 清理后复查：Godot 4.6.2 与 godot-mcp 匹配进程均为 0。

补充：全量 `verify_doc_anchors.py` 仍报告 `docs/reference/code-index.md` 中 41 个既存漂移锚点，与本次启动链修改无关，需单独执行“更新 index”任务处理。
