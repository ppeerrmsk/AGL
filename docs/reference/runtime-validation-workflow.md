# 自动运行时验证工作流

本页只说明“怎么跑、结果怎么看、改哪里”。行为与强制覆盖的设计权威见
[runtime-validation-workflow spec](../specs/systems/runtime-validation-workflow.md)。

## 默认命令

需要追查退出孤立节点时可显式设置 `AGL_BENCH_VERBOSE=1`；wrapper 只向同一隔离 Godot 追加 `--verbose`，不改变锁、超时、静音或错误门。正式菜单海洋测试比较进入前后的 orphan ID，新增孤立节点会判失败；不能只看主场景弱引用已释放。FINAL WAR 海洋基线/压力测试同时记录引擎帧率与独立墙钟，任一出现低于 60 FPS 的帧即返回失败；GPU/阶段采样仅用 `AGL_MAP_GPU_TRACE=1` 显式开启，诊断轮不能替代无探针性能轮。

```powershell
# 改动所属的最窄专项，先快速定位
bench\run.cmd <focused-key> 1 180 Shadow Headless

# 交付前默认回归：同步断言全表 + 真实 SceneTree 生命周期终态
bench\run.cmd all 1 300 Shadow Headless
```

只能通过 `bench/run.cmd` 或 `bench/run.sh` 启动 Godot。wrapper 对每个场景统一执行版本检查、Shadow
隔离、原子锁、有限超时、进程树回收和运行时错误扫描；不再接受“Godot exit 0，但输出里有红错”。

任何 `--bench` 场景启动后都会在当前测试进程 mute `Master` 总线，因此 Music、SFX、UI、Radio
以及未来新增的子总线均不会从系统扬声器出声。这里只切断最终输出，不跳过 `play_*` 调用、播放器状态、
signal 或总线路由断言，也不写入 `user://audio.cfg`；正常 F5 游戏和用户音频设置不受影响。

用户要求实际操作验收时，可在 `Shadow Visual` 前显式设置 `AGL_BENCH_INTERACTIVE=1`，把本次窗口显示在屏幕内。默认仍是屏外窗口；锁、超时、错误门和自动测试静音不变。交互截图与操作会扰动帧时，不能把该会话当标准性能样本；结束后清除此进程环境开关，再跑标准C1/C2。

对比 release 包时同样只经 wrapper：`AGL_BENCH_EXPORT_RELEASE=<项目外绝对路径\X.exe>` 在 Shadow 副本里用当前编辑器导出（预设名可用 `AGL_BENCH_EXPORT_PRESET` 改），`AGL_BENCH_EXPORTED_EXE=<X.exe>` 用导出包（同名 `.pck`）跑同一场景；导出包把结果写到 `user://bench/results/`，wrapper 结束后搬回 `bench/results/`。两者互斥，锁、超时、作业对象与错误门不变。`AGL_BENCH_EXPORTED_CWD=<项目外已存在目录>` 让导出包从该目录启动，验证与工作目录无关。M20 东京地图包不进主 PCK，改打独立地图包（构建任务 `tokyo_map_pack`），放在导出目录 `maps/` 下由 `MapPacks` 挂载，见[发行打包规格](../specs/systems/tokyo-map-distribution.md)。

## 结果口径


| 退出码 | 含义 | Agent 下一步 |
|---:|---|---|
| 0 | 断言、场景和运行时错误门均通过 | 继续所需 Visual / 性能 / 文档门 |
| 1 | 测试断言或场景失败 | 按首个失败标签修复并复跑 |
| 2 | launcher / 参数 / 环境错误 | 修环境，不归因到玩法代码 |
| 3 | InPlace 检测到 Godot 进程或锁冲突 | 使用 Shadow 或等待 owner 退出 |
| 86 | Godot 可能退出 0，但 stdout/stderr 含致命运行时诊断 | 从首个 `RUNTIME ERROR` 块追真实调用链并修复 |
| 124 | 超时，进程树已回收 | 区分死循环、原生崩溃弹窗被抑制后的挂起和时限不足 |

`WARNING` 不等于运行时错误。若确有稳定的引擎退出噪音，需要精确匹配单条文本后才能加入白名单；
测试代码主动发出的精确 `ERROR: [Bench]` 也属于致命诊断；禁止跳过全部 `ERROR` 或关闭错误门。

`SHADER ERROR:` 与 `ERROR: Shader compilation failed` 同样属于致命诊断，即使Godot退出0也改判86。`tools/test_bench_shader_gate.ps1`提取实际wrapper函数，覆盖stdout/stderr、回溯分块、非致命warning负对照及已有真实shader失败日志回放；失败shader的截图和像素摘要不能作为渲染通过证据。

wrong/uninitialized/already-initialized RID、free uninitialized/invalid RID及renderer scene cull的unimplemented base属于原生致命诊断，同样改判86；不能与普通退出RID计数警告混淆。`tools/test_bench_rid_gate.ps1`只读提取实际错误门函数验证5类模式及噪音/回溯保留，不启动引擎。

东京Stream在headless后端使用主线程延后领取原生资源，规避本机Godot 4.7.2 Dummy网格分配器的线程安全缺陷；窗口GL仍后台加载。无头生命周期不能据此宣称后台I/O或GPU性能已验收；线程路径用Shadow Visual核验。根因与边界见[SEAM-043](../architecture/known-seams.md#seam-043--dummy网格rid分配器与后台资源构造竞争)。

`RUNTIME ERROR` 块会保留完整 GDScript backtrace，不再固定截成四行。命中 `previously freed` / freed instance
时，wrapper 会追加 `FREED_OBJECT_LIFECYCLE` 诊断：优先检查最深 GDScript 调用者持有的跨帧 Object 缓存，
并确认边界是否在类型检查之前完成 `Variant → TYPE_OBJECT → is_instance_valid` 净化。该提示负责缩小范围，
不能替代生产调用链和确定性回归。

## `all` 实际包含什么

1. `BenchRunner.UNIT_TESTS` 全部同步断言；
2. 既有 freed-object / TypedArray 抗体：攻击者释放、玩家切控与死亡、BOSS 清场、阵营转换、舞台演员释放等；
3. `lifecycle_gauntlet`：真实节点进入树，`queue_free()` 后继续推进帧并跨缓存 tick；
4. wrapper 对完整输出执行运行时错误门。

`lifecycle_gauntlet` 可单跑：

```powershell
bench\run.cmd lifecycle_gauntlet 1 180 Shadow Headless
```

错误门自身用故意红错、Godot 主动退出 0 的探针验证。**这个命令预期退出 86，不是失败测试**：

```powershell
bench\run.cmd runtime_error_probe 1 180 Shadow Headless
```

## 修改终态机制时的强制清单

以下任一变化都属于生命周期改动：敌人/来源死亡、任务成功/失败、奖励结算、战区刷新、BOSS 解锁或
胜利、事件完成/取消、阵营转换、切控/换帅、场景退出，以及任何跨帧 Object 缓存。

- [ ] 用 index 找到权威 owner、缓存持有者和正式终态入口；
- [ ] 缓存读取遵守 `Variant → TYPE_OBJECT → is_instance_valid → is/as/字段`；
- [ ] focused 测试使用真实伤害或正式 signal/终态入口，不直接伪造最终状态；
- [ ] 终态发生后至少继续一个 SceneTree 帧，并跨过消费者的下一缓存 tick；
- [ ] 同时断言 signal、权威状态、缓存清空和函数确实执行到末尾；
- [ ] 新的 success/failure/cancel/cleanup 分支加入 gauntlet 或已有等价案例；
- [ ] 跑 focused，再跑 `all`；有 UI/画面合同时另跑 Visual，不能互相替代；
- [ ] wrapper 返回 86 时先修首个 runtime error，再处理后续连锁噪音。

长时随机压力仍有价值，但只负责发现未知组合；它不能代替确定性终态测试。需要 soak 时使用固定 seed，
主动注入击杀/完成/取消事件并记录 seed，失败后把该顺序收敛为新的确定性 gauntlet 案例。
