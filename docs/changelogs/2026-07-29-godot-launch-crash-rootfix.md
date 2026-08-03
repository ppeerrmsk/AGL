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

## 2026-07-30：Godot 4.7.1 signal 11 初步隔离

`wheel_orders` 曾在启动时非确定性 signal 11；稳定工作区重跑为 12/12、退出码 0，排除轮盘参数/GDScript 的确定性崩溃。现场同时有多个 Codex task 共用工作树，其中宠物生成任务持续向项目内 `tmp/` 写 PNG/WebP；Godot 在崩溃时刻也把这些临时素材批量导入到 `.godot/imported`，另有 task 同时改写 GDScript。当时先消除这些并发干扰，最终原生崩溃根因见下方 2026-08-01 完整 dump 结论。

根治：跟踪 `tmp/.gdignore`，让引擎永不扫描临时目录；`.gitignore` 忽略其余 `tmp/` 内容；`AGENTS.md` 新增强制并发隔离规则。bench 只能在无其他 task 写项目文件时运行。

## 2026-07-31：常驻 editor 崩溃与机器锁

再次出现 4.7.1 `0x58 memory read` 弹窗。现场进程取证确认弹窗所属 PID 44356 的命令行是 `--editor`，从 2026-07-30 23:20:59 起常驻；当时正逢临时素材批量导入，之后又持续监视多个 agent 的外部脚本/资源改写。弹窗不是当次 headless bench 进程，而是遗留 editor 在测试期间崩溃。

处理：终止崩溃 editor，并把 606 文件 / 54,932,573 bytes 的 `.godot` 缓存移动到 `tmp/godot-cache-crashed-editor-20260731` 留证、让引擎重建。`bench/run.cmd` / `run.sh` 新增两层硬门：检测到 Godot editor/其他 Godot 进程直接退出码 3；用原子目录 `tmp/godot-bench.lock` 阻止两个 agent 同时启动 bench。文档约定升级为可执行门禁。

## 2026-07-31：封死外层超时后的孤儿进程与弹窗

再次复盘发现旧启动器虽要求调用方设置有限超时，内部仍直接同步执行 Godot。Codex 命令在 60 秒被取消时，调用壳可能先退出，GUI 版 Steam Godot 子进程却继续存活；后续原生异常便会脱离原任务反复弹窗。这也是“任务已停止但稍后仍弹错”的启动链缺口。

新增 `bench/invoke_godot.ps1` 作为 Windows 唯一实际启动点，`run.cmd` / `run.sh` 只做参数转发。启动器现在同时提供：带 owner PID 的可恢复原子锁、启动前后双重 Godot 进程检查、默认 `max(120s, duration+90s)` 的内部 watchdog、独立 `watch_godot.ps1` 在超时或 owner 消失时显式 `taskkill /T /F`、Windows Job Object `KILL_ON_JOB_CLOSE` 二次兜底、超时退出码 124，以及只对子进程继承的 `SEM_NOGPFAULTERRORBOX` / `SEM_FAILCRITICALERRORS`。不能只依赖 Job Object：Codex/PowerShell 自身可能已处在宿主 Job 中，嵌套环境下关闭本地 Job 句柄并不总能及时终止 Godot。现在 bench 原生崩溃会静默退出，调用任务被取消后也由外部 watcher 收尸，不再卡住无人可点击的错误框；诊断时可用 `AGL_PROCDUMP` 指向 ProcDump，由同一启动器从进程创建阶段捕获 dump。

## 2026-08-01：完整 dump 定位到 Godot 4.7.1 RotatedFileLogger

通过微软 ProcDump 从进程创建阶段捕获到 253,021,078 bytes 完整转储：主线程异常为 `C0000005 ACCESS_VIOLATION`，故障地址位于 Godot 主程序 RVA `0x3E160D4`，指令为 `cmp qword ptr [rcx+0x58], 0`，当时 `RCX=0`，与弹窗“读取 0x58”完全一致。x64 unwind 栈为 `RotatedFileLogger::RotatedFileLogger` → `Main::Setup`；GNU RTTI 也从现场对象解出类型 `17RotatedFileLogger`。与 4.7.1 官方源码逐行核对后，故障行是 `strip_ansi_regex->detach_from_objectdb()`：前一行 `strip_ansi_regex.instantiate()` 在本机无头启动路径返回空引用，官方实现未判空。

Steam tools exe 与同版本官方 console 包 A/B 均在相同初始化阶段崩溃，排除 Steam 分发差异；崩溃发生在项目 GDScript、渲染与音频驱动加载前，排除 `friendly_asset_aggro` 脚本为原生崩溃根因。Godot 4.7.1 `main.cpp` 表明 PC 运行时默认启用 `debug/file_logging/enable_file_logging.pc` 并构造该日志器。AGL 已有 EventLogger、stdout 与 bench 结果文件，因此在 `project.godot` 显式设置 `file_logging/enable_file_logging.pc=false`，精准绕开有缺陷的原生日志器；F9 战斗日志不受影响。

修复后验证：`friendly_asset_aggro` 27/27、`target_arb` 25/25、`wheel_orders` 12/12 均退出 0；另以 `stress_40 30 10` 注入强制超时，启动器按约定退出 124，Godot 残留进程为 0、锁目录不存在。再次正常运行 `friendly_asset_aggro` 仍为 27/27，证明 watcher 不会误杀正常 bench。

## 2026-08-03：编辑器常驻时改用隔离 Shadow bench

为恢复“编辑器开着也能跑无头测试”的工作流，`bench/run.cmd` / `run.sh` 默认改为 `Shadow` 模式：启动前只镜像 Godot 运行所需目录与根配置到系统临时目录的稳定项目副本，并复制（不共享）源 `.godot` 的 `class_name` / UID 缓存与 imported 产物作为私有缓存种子；随后 headless 只写副本自己的 `.godot`。测试结束把 `bench/results` 与 EventLogger 日志回收到原项目。原工作区的 editor 与 headless 不再共享导入缓存；编辑器内未保存到磁盘的改动按定义不进入快照。原工作区锁仍串行化所有 bench，防止多个 agent 同时同步或运行。

需要对原目录做精确复现时可显式传第四参数 `InPlace`；该模式保留旧硬门，发现任何 Godot 进程即返回 3。Shadow 副本不包含 `.git/.godot/tmp/logs/docs/.claude/.codex`，首次启动会导入运行时资源，后续复用缓存。

## 2026-08-03：生存压力场异常暂停与终局覆盖

`stress_40` 原先在约 26 秒后表现为进程存活但不再推进。线程状态与 ALWAYS 看门狗确认并非原生死锁：玩家沿默认南边界出生，AI 转向中心航点前惯性越界，`BoundaryUI` 的 `panel_in` 合法触发 `Presentation.time.hard_pause(true)`，无头环境无人选择撤退菜单，因而永久停在交互态。

修复为所有生存压力场在地图中心开始，并让 bench 主控在暂停期间继续运行墙钟看门狗；非升级场景出现 `SceneTree.paused` 会立即写出诊断并失败。新增 `survivor_death`：三机小队先击落长机验证僚机接管，再全队覆灭验证 Game Over。验证包括 `stress_40` 60 秒、`stress_swarm` 60 秒（78 个战斗对象，末秒 127 fps）、扩池 60 秒、战区支援 45 秒（49 机）、王牌支援 45 秒（46 机）、Mother Goose 90 秒（18 杀，Boss 余 74.2%），均无崩溃或非预期暂停。
