---
id: runtime-validation-workflow
kind: system
status: done
schema_version: 1
spec_version: 5
owner: AGL
depends_on: [systems/survivor-loop, systems/event-system]
reconstruction_complete: true
---

# 自动运行时验证工作流

> 让击杀、任务完成、失败、取消、切阶段和对象释放成为每次回归都会主动经过的路径；任何 Godot 运行时红错都不能再以“进程退出 0”冒充通过。

## 1. 设计意图（Why）

- **体验目标**：玩家不再承担发现稳定可复现闪退的职责；Agent 在交付前通过自动化主动制造终态并自行修复。
- **Litmus 自检**：支撑“一击毙命”的即时反馈与 12–20 分钟完整局稳定性；测试不能只证明生成、数值或短时稳态，还必须证明结果发生后的清理链。
- **反模式规避**：不靠延长随机压力测试碰运气，不把 focused/Shadow 误写成完整局，不因 Godot 返回 0 就忽略 stderr 红错，不用宽泛白名单吞掉真实错误。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 回归层级

| 层 | 内容 | 默认入口 | 通过条件 |
|---|---|---|---|
| L0 | 纯函数、数据表、局部行为断言 | 单项 bench | 断言失败数为 0，且运行时错误门为 0 |
| L1 | 真实 SceneTree 生命周期终态 | `lifecycle_gauntlet` | 全部案例越过释放后续帧与缓存 tick，失败数为 0 |
| L2 | 全量默认回归 | `all` | L0 全部通过后自动执行 L1；任一层失败即非 0 |
| L3 | 功能专项 Shadow / Visual / 压力 | 对应场景 | 场景合同通过，且运行时错误门为 0 |
| L4 | 完整局 / 长时 churn | 正式 Survivor | 覆盖真实节奏与组合；不能替代 L0–L3 |

### 2.2 固定边界

| 字段 | 值 | 说明 |
|---|---:|---|
| 生命周期释放等待 | 至少 1 个 SceneTree 帧 | `queue_free()` 后再消费缓存；案例可按子系统追加 physics frame |
| 缓存采样推进 | 至少跨过该缓存的完整 tick | 例如 10 Hz 缓存至少推进 0.1 秒 |
| wrapper 运行时错误退出码 | 86 | Godot 自身退出 0，但发现致命脚本诊断时使用 |
| 断言失败退出码 | 1 | 保留 BenchRunner 既有语义 |
| launcher 失败 / 锁 / 超时 | 2 / 3 / 124 | 与运行时错误分离，便于 Agent 自动归因 |
| bench 音频输出 | `Master.mute = true` | 所有 `--bench` 场景静音全部现有/未来子总线；不保存用户设置，不跳过播放逻辑 |

### 2.3 运行时致命诊断

以下任一出现即失败，不受 Godot 进程退出码影响：

- `SCRIPT ERROR`；
- 对 freed / previously freed 实例的转换、赋值、类型判断、参数检查或调用；
- `Invalid call`、`Invalid access`、函数参数 `Invalid type`；
- null value 调用、TypedArray 非法 erase、stack overflow；
- 错误门自检探针的专用标记，以及测试代码主动发出的精确 `ERROR: [Bench]` 前缀。

普通 `WARNING` 不自动失败。若引擎存在稳定、已证实无害的退出噪音，只能用精确文本白名单排除；禁止按 `ERROR` 大类整体放行。

错误门输出必须保留同一诊断块的完整 GDScript backtrace，直到空行或下一条 Godot 诊断为止；不得用固定四行
截断而丢失生产调用者。命中 freed-object 族错误时，wrapper 额外输出 `FREED_OBJECT_LIFECYCLE` 归因，明确提示
从最深 GDScript 调用者检查跨帧缓存和带类型边界，但最终修复仍以真实调用链为准。

## 3. 行为与公式（How）

### 3.1 默认执行链

```text
bench wrapper 取得独占锁并创建 Shadow
→ Godot 执行单项 / all
→ BenchRunner mute 当前进程的 Master 总线
→ all 先跑同步断言注册表
→ 断言全绿后切入 lifecycle_gauntlet 场景
→ 场景真实 queue_free 并越过后续帧/缓存 tick
→ wrapper 汇总 stdout + stderr
→ 扫描运行时致命诊断
→ 断言、进程、超时、运行时诊断任一失败即非 0
```

错误门应用于每一个 `bench/run` 调用，而不只应用于 `all`。因此 focused bench 一旦执行到未知红错，也必须立即阻断交付。

### 3.2 生命周期案例合同

每个终态案例必须包含四段：

| 阶段 | 要求 |
|---|---|
| Arrange | 使用生产类与真实 SceneTree 节点；只允许 Debug/测试入口建立确定性初态 |
| Act | 通过正式伤害、正式 signal、正式完成/失败/取消入口触发终态，不直接伪造最终缓存 |
| Settle | `queue_free()` 后继续推进帧，并跨过消费者的下一次缓存/调度 tick |
| Assert | 同时检查信号、权威状态、缓存清空和测试函数确实走到末尾；wrapper 另查运行时红错 |

Focused gauntlet 必须显式隔离不属于本案例的下游 owner。例如终态案例直接调用生产 `_physics_process`
时，应为其它战区预登记空生成快照，避免同帧顺带启动需要完整 `SurvivorMode` 的刷怪链；不得用 null owner
承接生产生成，也不得把由 fixture 缺依赖造成的红错加入白名单。

### 3.3 强制覆盖矩阵

当前 gauntlet 的基础矩阵必须覆盖：

- 战区目标释放后仍能完成结算；
- 特殊任务控制器或目标任一先释放；
- 成功 / 失败 / 取消共用退役链面对已释放成员；
- 缓存状态快照在失效引用下安全降级；
- 玩家 `combat_target`、`commanded_target` 与 AI `_current_target` 同时残留已释放目标时，另一目标进入传感器隐形批处理仍能净化三类缓存；
- 一体化巨炮经正式伤害入口销毁后，底座、炮管、在途效果和来源缓存同拍退役，跨过 `queue_free()` 后不残留独立 TGT；
- 既有全量注册表中的攻击者死亡、玩家切控/死亡、BOSS 清场、阵营转换、舞台演员释放与 TypedArray 边界回归继续纳入 `all`。

新增敌人、任务、事件、BOSS 或特殊条件时，只要引入新的 `success / failure / cancel / cleanup` 分支，就必须增加或复用对应终态案例；只测生成和稳态不算接入完成。

### 3.4 跨帧 Object 边界

可能比对象活得更久的数组、字典、meta、信号绑定或强类型缓存，读取顺序统一为：

```text
Variant → typeof == TYPE_OBJECT → 非 null → is_instance_valid → is / as / 字段访问
```

带 Object 类型形参的函数无法在函数体内保护已释放实参；必须在调用前净化，或把生命周期边界形参改为 `Variant`。

## 4. 结构与组成（Structure）

| 部件 | 责任 |
|---|---|
| BenchRunner | 静音当前 bench 进程的 Master；注册同步断言、Headless 集成场景和 Visual 场景；`all` 串联断言与生命周期门 |
| Shadow wrapper | 锁、版本、隔离、超时、进程树回收、stdout/stderr 捕获和运行时错误改判 |
| Lifecycle Gauntlet | 真实 SceneTree 终态与释放后续帧测试 |
| Runtime Error Probe | 证明 Godot 退出 0 时 wrapper 仍能返回 86；不进入 `all` |
| Reference workflow | 为 Agent 选择 focused / all / Visual / soak，记录命令与证据口径 |

## 5. 验收标准（Acceptance / Litmus）

- [x] 当前 bomber escort freed-object 路径使用 Variant 生命周期边界并有真实释放回归。
- [x] 任意 bench 出现 `SCRIPT ERROR`、freed-object 或精确前缀 `ERROR: [Bench]` 诊断时，即使 Godot 返回 0，wrapper 也返回 86；不宽泛吞并环境 `ERROR`。
- [x] 错误门保留完整 GDScript 调用栈，并对 freed-object 边界输出可执行的自动归因提示。
- [x] `runtime_error_probe` 同时注入专用探针、通用 `ERROR: [Bench]` 红错与 freed-object 类型边界，稳定证明错误门会改判、保留栈并输出自动归因。
- [x] `lifecycle_gauntlet` 覆盖完成、失败、退役和两类缓存对象释放顺序。
- [x] `lifecycle_gauntlet` 覆盖一体化巨炮销毁、跨帧释放、来源缓存清除和无底座残留。
- [x] `lifecycle_gauntlet` 覆盖传感器批处理面对三个玩家目标缓存的跨帧失效引用。
- [x] `all` 自动串行执行同步断言与生命周期 gauntlet，用户无需另记第二条命令。
- [x] 任意 `--bench` 场景统一静音 Master，且播放逻辑、状态断言与用户持久化设置不被绕过或改写。
- [x] 所有新增终态机制的 onboarding 清单已写入 Agent 工作约定。
- [x] 性能：测试基础设施不进入正式局常驻 tick；仅 bench 场景执行，豁免 C1。
- [x] 已知 seam 已同步，尤其是已释放 Object 与 TypedArray 边界。
- [x] 文档：本 spec 已登记 _INDEX；reference 指针和当前文档链接通过。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | PowerShell 语法、文档/metadata、667 锚点、玩家引用与 diff 检查 | 通过 |
| E1 聚焦 Shadow | deadair 20/20（运行时断言 Master mute）；gauntlet 20/20；probe 将 Godot 0 改判 86 | 通过 |
| E2 集成 Shadow | `all` 80 个注册测试全绿后自动执行 gauntlet 20/20；Master mute；运行时错误门 0 命中 | 通过 |
| E3 Visual | 本系统无视觉输出 | 豁免 |
| E4 完整局 | 后续真实完整局继续提供未知组合证据 | 不作为基础设施落地阻塞 |

2026-08-26 增量证据：`sensor_stealth` 63/63；`lifecycle_gauntlet` 82/82；修复前新增案例稳定触发
`_target_is_in_batch argument 1 (previously freed)` 并由 wrapper 改判 86，增强后完整保留生产调用帧并输出
`FREED_OBJECT_LIFECYCLE`；修复后三类缓存均为真实 `TYPE_NIL`。错误门双探针同时覆盖普通红错与
freed-object 类型边界，Godot 主动退出 0 时 wrapper 仍改判 86。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 错误传播
- [x] 修复 bomber escort 缓存的已释放引用转型顺序。
- [x] wrapper 捕获运行时致命诊断并提供独立退出码。
- [x] 增加退出 0 的错误门自检探针。

### 阶段 2 — 生命周期门
- [x] 增加 Headless lifecycle gauntlet 场景。
- [x] `all` 在同步断言后自动执行 gauntlet。
- [x] 跑聚焦与全量验证并修复新门揭示的问题。

### 阶段 3 — 固化工作流
- [x] 更新 Agent 强制约定、reference 工作流与索引。
- [x] 完成文档/锚点/玩家引用/diff 校验并回填证据。

### 阶段 4 — 传感器缓存抗体与诊断上下文
- [x] 把目标批判定边界改为 `Variant`，并净化玩家与 AI 的三个失效目标缓存。
- [x] gauntlet 复现“目标 A 释放后由目标 B 隐形触发批清理”的真实跨帧顺序。
- [x] wrapper 从固定四行升级为完整 GDScript backtrace，并输出 freed-object 自动归因。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 错误门与 Shadow launcher | `bench/invoke_godot.ps1` |
| 注册与 `all` 串联 | `scripts/bench/bench_runner.gd` |
| 生命周期终态场景 | `scripts/tests/lifecycle_gauntlet_runner.gd`、`scenes/tests/lifecycle_gauntlet.tscn` |
| 错误门自检 | `scripts/tests/runtime_error_probe.gd`、`scenes/tests/runtime_error_probe.tscn` |
| 当前 bomber 生命周期边界 | `scripts/survivor/zone_mission.gd` |
| Agent 工作流 | `AGENTS.md`、`docs/reference/runtime-validation-workflow.md` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-09-03 | 5 | 把测试代码主动发出的 `ERROR: [Bench]` 纳入精确致命模式，避免压力场只写红错但进程退出 0 的假绿灯；环境级普通 `ERROR` 仍保持非致命并单独审计。 |
| 2026-08-26 | 4 | 修复传感器批清理的三个已释放目标缓存；gauntlet 固化跨帧抗体；错误门保留完整调用栈并输出 freed-object 生命周期归因。 |
| 2026-08-22 | 3 | gauntlet 增加一体化巨炮的正式伤害、跨帧释放、来源缓存清除与无底座残留案例；同步当前 20/20 与全量 80 项证据。 |
| 2026-08-22 | 2 | bench 从仅静音 Music 收口为进程级 Master 静音，覆盖 SFX/UI/Radio 与未来子总线，并增加运行时断言。 |
| 2026-08-22 | 1 | 建立 stderr 运行时错误硬门、真实释放 gauntlet 与默认 all 串联契约。 |
