---
id: modifier-pipeline
kind: system
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [afterburner-mode, cloud-skill-consistency]
reconstruction_complete: true
---

# 运行时修改器一致性管线

## 1. 设计意图

运行时 buff 不能改写永久 `params`，也不能靠进入/退出模式对倒计时做乘除。前者会在升级、
多光环与成员转会时把新值回滚；后者无法处理模式内新生成的 CD，并在边界产生漂移。

## 2. 数据定义

### 2.1 CD 速率

倒计时写入基础时长，tick 消耗 `delta × cd_rate(channel)`，其中
`rate = 1 / max(所有生效的时间倍率乘积, 0.01)`。

- `weapon`：规避 weapon 倍率 × 云中 weapon 倍率；覆盖机炮、主弹、火箭、副槽。
- `flare`：规避 flare 倍率 × 低血装填倍率；ESM rate 在调用侧继续相乘。
- `missile_reload`：规避装填倍率；ESM rate 在调用侧继续相乘。

### 2.2 指挥光环字段

`aura_max_g_add=0`、`aura_g_structural_add=0`、其余 roll/speed/accel/stall 倍率默认 1；
`aura_buff_owner=null`。光环不得写 `AircraftParams`。

### 2.3 加减速 accessor

`base_*` 汇入永久 params 与光环字段；`effective_accel_mult` / `effective_decel_mult` 汇入现有
OVERLOAD、BLOODLUST、加力窗口、AB、签名与 hunter 状态。实飞与预测 `step_*` 必须共用。

## 3. 行为

- 指挥光环每 0.5 秒全量重算“当前小队成员且在半径内”的集合；离队/越界/转会均撤除。
- 单一 owner 仲裁；其它有效指挥机持有时不抢占，失效 owner 可被接管。
- 规避滚转和走位每帧只执行一次，生命周期与后半球/JAM 光环是否装备完全无关。
- `ModifierTrace.explain` 只在显式调试时做黑盒差分，禁止进入热路径；Shift+F12 输出报告。

## 4. 边界与不变量

- 永久升级继续直接修改 duplicate 后的 params。
- `update_*` 与 `step_*` 的速度、失速、滚转、G 与加减速公式保持同源。
- Sentinel 坠落动画期间保留光环，节点退出时统一撤除。
- 雷达、状态和 CD 热路径不分配通用 Modifier 对象。

## 5. 验收

- 模式内新开的 CD 立即受当前倍率影响；零倒计时进出模式不漂移。
- 光环生效/撤除不改变 params；永久升级在光环撤除后仍保留。
- 成员离队后一个扫描周期内清除光环字段；两个光环不会互相撤除。
- 无光环技能时规避滚转/走位仍推进；两种光环同时启用也只推进一次。
- 实飞和预测对相同状态得到相同加减速倍率。

## 6. 实现计划

以现有 accessor 为核心收口 CD、Sentinel 光环、加减速镜像和调试追踪，并补无头契约测试。

## 7. 实现锚点

- `scripts/aircraft/aircraft_physics.gd` `base_*` / `effective_accel_mult` / `effective_decel_mult`
- `scripts/survivor/commander_aura.gd` `_scan_and_buff` / `_apply_buff` / `_remove_buff`
- `scripts/aircraft.gd` `_update_evasion_motion`
- `scripts/modifier_trace.gd` `explain` / `print_report`
- `scripts/tests/test_local_fix_integration.gd` `run`；`hard_brake` 5/5、`speed_governor` 14/14、`turn_physics` 四机型通过；`stress_40` 与 `zone_support_stress` 完成 15 秒压力验证

## 8. 变更记录

| 日期 | 版本 | 内容 |
|---|---:|---|
| 2026-08-15 | 1 | 移植旧修改器分支已完成阶段，并适配当前签名技能、加力窗口和 ESM。 |
