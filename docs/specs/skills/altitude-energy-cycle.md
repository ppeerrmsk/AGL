---
id: altitude-energy-cycle
kind: skill
status: done
schema_version: 1
spec_version: 3
owner: noelu
depends_on: [systems/altitude-action-states, systems/afterburner-mode]
reconstruction_complete: true
---

# 高度能量循环

> 俯冲把势能换成超额机炮备弹，爬升则把动作过程转化为小队加力能量，让玩家围绕上下高度循环组织下一轮交战。

## 1. 设计意图（Why）

- **体验目标**：给俯冲和爬升各一个清晰资源收益，使高度动作不再只是速度变化；形成“爬升蓄加力 → 俯冲加速并备弹”的循环。
- **Litmus 自检**：资源数字会直接变化，玩家能从 GUN 弹量与 AFTERBURNER 条读取收益；使用统一 `CLIMB / DIVE` 状态，不增加隐藏触发条件。
- **反模式规避**：共享加力资源不得随僚机数量线性放大；失速下坠不能伪装成 DIVE 获取收益。

## 2. 数据定义（What —— 全部数值，权威源）

| 字段 | 值 | 说明 |
|---|---|---|
| 正式 id | `altitude_energy_cycle` | 稳定技能 id。 |
| 中文名 | `高度能量循环` | 正式名称。 |
| 最大层数 | 1 | 双向资源循环技能，不做叠层。 |
| 稀有度 | 实验 | 单层实验级技能。 |
| category / axis | `mobility` / 骑士 | 高度动作与能量管理。 |
| 俯冲收益 | `25 发/s` | 只在统一 `DIVE` 状态成立时回复本机机炮。 |
| 俯冲超储 | `2 × max_ammo` | 可突破基础弹仓，达到硬上限后停止。 |
| 爬升收益 | `+0.2 加力能量/s` | 只在统一 `CLIMB` 状态成立时回复共享加力池。 |
| 加力启用中 | 仍回复 | 先结算实际消耗再回复，基础净消耗由 `1.0/s` 降为 `0.8/s`。 |
| 共享加力贡献者 | 当前操控机，且不可叠加 | 不随玩家小队飞机数量放大。 |
| 机炮收益对象 | 每架持有技能的玩家小队飞机 | 各自按自身 `DIVE` 独立结算。 |
| 失速下坠 | 不触发 | 失速不属于 `DIVE`。 |
| 垂直越过 | 触发对应方向收益 | 它会发布统一 `CLIMB / DIVE` 状态。 |

## 3. 行为与公式（How）

```text
if aircraft.altitude_action == DIVE and aircraft has gun:
    aircraft.ammo = min(aircraft.ammo + 25 * delta,
                        aircraft.params.gun.max_ammo * 2)

if controlled_aircraft.altitude_action == CLIMB:
    squad_afterburner_charge += 0.2 * delta
    clamp to CHARGE_MAX
```

- 机炮回复必须保留小数累加器，再以整数发数写回，低帧率和不同 physics tick 下总量一致。
- 超储弹药在俯冲结束后保留，正常射击消耗；不因回到平飞、切换高度或切控而截回基础上限。
- 后续任何“补满”逻辑不得把已经高于 `max_ammo` 的超储弹药错误截断；只允许增加到对应来源的合法硬上限。
- 加力能量达到 `CHARGE_MAX` 后不继续隐藏累计；爬升收益不会突破加力池上限。
- 加力启用中先结算实际消耗，再结算爬升回复；Storm I 只统计实际消耗，爬升回复不倒扣或伪造其门槛。

## 4. 结构与组成（Structure）

- 技能数据进入正式升级表并由通用 F4 技能面板自动列出、可强制授予。
- 单机机炮回复放在现有武器更新与小数累加路径，读取统一 `DIVE`；不得新增 Aircraft 子节点或独立 `_process()`。
- 小队加力回复由现有 AfterburnerCharge 更新入口消费当前操控机的统一 `CLIMB`，只做 O(1) 状态读取。
- 技能账本、换机继承、切控和 Debug 清单遵循现有通用全队技能规则；共享加力只读取当前操控机，机炮则由各机独立结算。

## 5. 验收标准（Acceptance / Litmus）

- [x] F4 可直接授予本技能，不受机型、学说、装备和前置门控；正式卡池与 Debug 清单同源。
- [x] `DIVE` 时机炮按定稿速率回复并可越过基础 `max_ammo`，到达定稿硬上限后停止；`CLIMB/NONE/失速下坠` 不回复机炮。
- [x] 超储弹药在结束俯冲、切控和正常射击后保留并正确消耗；其它“补满”入口不把超储量截断。
- [x] `CLIMB` 时加力池按定稿速率回复；`DIVE/NONE` 不获得本技能加力回复；满池不隐藏累计。
- [x] 小队规模从 1 增加到 9 时，共享加力回复速率不被僚机数量放大。
- [x] 垂直越过向上/向下段分别触发爬升/俯冲收益，动作结束立即停止。
- [x] 与加力供弹、强化加力、暴风雨 I/II、MiG-41 和 Typhoon 同时持有时各自语义可解释，无重复帧或错误截断。
- [x] 玩家可从正式 GUN 弹量和 AFTERBURNER 条观察资源变化，不新增常驻 HUD 面板。
- [x] 性能：复用现有更新入口和 O(1) 状态读取，Sentinel + Lv5+ 压测不低于 60 FPS。
- [x] i18n：名称与描述三语齐全。
- [x] 文档：本 spec 已登记总表；定稿后 `reconstruction_complete` 与状态同步。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与授予
- [x] 加入技能数据、三语 i18n、卡池与 F4 自动审计。

### 阶段 2 — 消费点
- [x] 机炮更新读取 `DIVE`，复用小数累加并支持超储硬上限。
- [x] AfterburnerCharge 更新读取 `CLIMB`，按定稿作用域结算且不随小队人数叠加。
- [x] 审计所有会写 `ammo = max_ammo` 的入口，保护合法超储量。

### 阶段 3 — 回归
- [x] 补 CLIMB/DIVE/失速/垂直越过、超储、切控与 Storm 交互断言。
- [x] 运行技能审计、聚焦 bench、文档与玩家引用校验、压力测试。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 技能数据 | `scripts/survivor/survivor_data.gd` |
| 技能授予 | `scripts/survivor/survivor_player.gd` |
| 机炮回复 | `scripts/aircraft/aircraft_weapons.gd` |
| 加力池 | `scripts/survivor/afterburner_charge.gd` |
| 生存层接线 | `scripts/survivor/survivor_mode.gd` |
| i18n | `i18n/skills.csv` |
| 聚焦与全表审计 | `scripts/tests/test_skills_720.gd` / `scripts/tests/test_skill_audit.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-17 | 1 | 按用户方向建立双向资源循环草案；所有未指定数值、作用域和加力启用中语义保持待定。 |
| 2026-08-17 | 2 | 用户定稿：正式名“高度能量循环”，实验级单层，DIVE 25 发/s 至 2 倍弹仓，CLIMB +0.2/s，仅当前操控机贡献共享加力。 |
| 2026-08-17 | 3 | 实现完成：163 条技能表、F4 自动覆盖、DIVE 每机独立超储与 CLIMB 单贡献者加力接线落地；聚焦 267/267、技能审计 183/183、Visual 压力场与文档校验通过。 |
