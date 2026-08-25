---
id: counter-stealth
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: noelu（设计）/ Codex（实现）
depends_on: [enemy-sensor-stealth, skills-720-rework]
reconstruction_complete: true
---

# 反隐身与捉鬼者

## 1. 设计意图（Why）

给玩家小队两级反隐 build：稳定级技能提供可靠的搜索与被锁反制，先进级技能把已经进入交战的隐形目标固定为持续接触，并把猎杀隐形单位转化为全队成长。

## 2. 数据定义（What）

| 技能 | id | 稀有度 | 轴 | 范围 | 数值 |
|---|---|---|---|---|---|
| 反隐身 | `counter_stealth` | STABLE | 策士 | 通用全队 | 对数据标记的隐形单位侦测距离 ×1.20 |
| 捉鬼者 | `ghost_buster` | ADVANCED | 斗士 | 通用全队 | 每击杀 1 架隐形单位，全队永久最大生命值 +10 |

两项均为单层 `skill_flag`，通过每架玩家小队飞机的有效技能子集生效。

## 3. 行为与公式（How）

### 3.1 反隐身

- 只对 `AircraftParams.sensor_stealth_enabled` 的敌机扩展侦测距离；角度、JAM、Snowblind 幕边界、武器可锁能力与 ECM 缩距继续沿用现有雷达契约。
- 扩距只用于发现隐形目标，不扩大普通目标的雷达锁定/武器射程。
- 隐形敌机对任一持有技能的玩家小队成员形成完整主雷达锁定时，该敌机保持现形；锁定解除后重新服从既有 5 秒失联宽限。
- 现形同时压过该机当前的光学 cloak：模型、尾迹、选择、锁定与实体命中恢复；不停止或重置 Wraith 的 cloak 周期，现形条件解除后按原周期恢复。

### 3.2 捉鬼者

- 任一持有技能的玩家小队成员把隐形敌机保持为 `combat_target` 时，该目标不能进入传感器失联隐藏，并压过当前光学 cloak。
- 解除交战、目标死亡或技能不再生效后，目标恢复标准失联/显隐流程。
- 击杀归因沿用 `SkillHooks.dispatch_on_kill`；只有 `sensor_stealth_enabled` 的敌机计为隐形单位，目标死亡时是否正处于隐藏态不影响奖励。
- 每次有效击杀令队级永久生命账本 +10；所有当前存活成员立刻增加 10 最大生命并回复同量生命。晚入队成员与换机重放按账本补齐，不重复叠加。
- 账本只在当前战局内永久，新局显式清零。

## 4. 结构分层（Structure）

- `SurvivorData.UPGRADES`：技能数据、稀有度、轴与 i18n key。
- `SensorStealthController`：扩距发现、被锁现形、交战目标保持与标准失联恢复。
- `Aircraft` / `AceSquad`：现形覆盖光学 cloak，但保留 cloak 生命周期所有权。
- `SkillHooks`：隐形目标击杀归因、队级永久生命账本与成员补齐。
- `SurvivorMode`：新局清零、有效技能子集刷新、换机重放。

## 5. 验收标准（Acceptance / Litmus）

- [x] 反隐身只扩展隐形目标侦测距离到 120%，不改变普通目标包线。
- [x] 隐形敌机完整锁定任一队员后全队可见，解除后恢复标准宽限。
- [x] `combat_target` 中的隐形敌机不会被跟丢；解除交战后可再次隐藏。
- [x] 两种现形来源都能压过 Wraith 光学 cloak，条件解除后 cloak 周期继续。
- [x] 隐形单位击杀给当前全队、晚入队成员和换机后机体一致的永久 +10 最大生命。
- [x] 普通目标击杀不触发，且新局账本清零。
- [x] 技能卡三语文本、正式抽卡池、Debug 技能面板与自动技能表同源。

## 6. 实施计划（Task Pipeline）

- [x] 增加技能数据和三语文本。
- [x] 接入既有 5Hz 雷达/隐形控制器，不新增全场扫描。
- [x] 接入光学 cloak 覆盖与击杀/永久生命账本。
- [x] 增加聚焦回归、技能审计与文档索引。

## 7. 代码锚点（Where）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| 发现/现形/保持 | `scripts/survivor/sensor_stealth_controller.gd` |
| 光学 cloak 覆盖 | `scripts/aircraft.gd`、`scripts/survivor/ace_squad.gd` |
| 击杀与队级 HP | `scripts/survivor/skill_hooks.gd`、`scripts/survivor/survivor_mode.gd` |
| 自动回归 | `scripts/tests/test_sensor_stealth.gd` |
| 玩家可见文本 | `i18n/skills.csv` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-23 | 1 | 按 Notion「agl反隐技能」落地反隐身与捉鬼者，并与现行传感器隐形/Wraith cloak 契约合并。 |
