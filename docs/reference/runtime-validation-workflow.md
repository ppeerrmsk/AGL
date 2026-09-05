# 自动运行时验证工作流

本页只说明“怎么跑、结果怎么看、改哪里”。行为与强制覆盖的设计权威见
[runtime-validation-workflow spec](../specs/systems/runtime-validation-workflow.md)。

## 默认命令

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
