---
id: fire-control-saturation
kind: skill
status: done
schema_version: 1
spec_version: 1
owner: 用户
depends_on: [status-build-completion, skills-720-rework]
reconstruction_complete: true
---

# 火控饱和（Fire-Control Saturation）

> 当前王牌同时完成五个目标的主雷达锁定时进入短时超载，并在整个超载窗口内再扩展两个
> 锁定席位；奖励玩家把多目标锁定构筑推到实际峰值，而不是只堆静态锁数。

## 1. 设计意图（Why）

- **体验目标**：把“同时五锁”变成一个清楚的爆发沿。玩家先通过骑士轴构筑取得足够锁定席位，
  再靠站位把五个目标同时锁满；触发时既出现既有 `OVRLD` 状态条，也能立即多覆盖两个目标。
- **Litmus 自检**：触发条件直接来自玩家可见的锁定框；`+2` 是可感知整数门槛；检测复用既有
  低频雷达循环，不新增全场扫描、节点或高频计时器。
- **6 秒例外**：设计哲学通常要求玩家 buff 覆盖一次真实交战周期。本技能由“已经处于五目标
  满锁射击窗”触发，收益从触发当刻即可使用；用户明确指定基础时长 6 秒，因此不擅自改为
  通用 8 秒。既有超载延时终端仍可延长它。
- **反模式规避**：内置冷却与五锁上升沿双闸并存；保持在五锁以上不会在冷却结束时自动续杯，
  必须先跌回五锁以下，再重新完成五锁。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 升级条目

| 字段 | 值 | 说明 |
|---|---|---|
| id | `fire_control_saturation` | 唯一技能 id |
| 显示名 | 火控饱和 / Fire-Control Saturation / 火器管制飽和 | 三语玩家名称 |
| stat | `skill_flag` | 低频事件钩子读取当前王牌生效子集 |
| value / max_stacks | 1 / 1 | 单层开关 |
| category / axis | missile / knight | 骑士轴导弹构筑 |
| rarity | EXPERIMENTAL | 实验级 |
| scope | `ace` | 只对当前操控王牌生效；切控迁移 |
| classes | 无 | 不限制当前机体的斗士／骑士／策士品类身份 |
| keywords | missile / lock / overload | OVERLOAD 状态来源，受对应学说与构筑聚焦影响 |
| requires | missile | 无主导弹时不进入正式卡池 |
| build_role | source | 可解锁 OVERLOAD 终端 |

### 2.2 触发与收益常量

| 常量 | 值 | 含义 |
|---|---:|---|
| 同时满锁阈值 | 5 个目标 | “五个以上”按包含 5 解释 |
| 基础 OVERLOAD 时长 | 6.0 s | 经统一 `apply_status` 入口施加 |
| 内置冷却 | 20.0 s | 单局共享；切换当前王牌不清零 |
| OVERLOAD 期间锁定席位加成 | +2 | 持有本技能且 OVERLOAD 实际存在时生效 |

## 3. 行为与公式（How）

### 3.1 满锁计数

每次既有主雷达锁定循环完成数据链照射合并后，只检查当前操控王牌：

```text
eligible_capacity = effective_max_locks()
fully_locked = count(
  target 有效、未摧毁、与王牌敌对
  且 radar_targets[target] >= 当前王牌 params.lock_time
)

只有 eligible_capacity >= 5 且 fully_locked >= 5 才进入触发沿判定。
```

副导弹槽的独立锁定字典不计入；主雷达数据链共享后的合法满锁计入。

### 3.2 上升沿与内置冷却

| 状态 | 条件 | 转移与结果 |
|---|---|---|
| 未锁存 | 满锁或有效席位少于 5 | 保持未锁存，不触发 |
| 未锁存 | 满锁与有效席位均至少 5，且 CD=0 | 锁存；施加 OVERLOAD 6s；CD 置 20s |
| 未锁存 | 满锁与有效席位均至少 5，但 CD>0 | 锁存；不触发 |
| 已锁存 | 仍至少 5 锁 | 保持锁存；即使 CD 归零也不触发 |
| 已锁存 | 跌到 5 锁以下或有效席位少于 5 | 解除锁存，等待下一次跨线 |

CD 按游戏内雷达 tick 的 `delta` 递减，暂停不流逝；状态保存在单局主控而不是飞机实例上，
因此 1–9 切控不能重置 CD 或伪造新的五锁上升沿。

### 3.3 锁定席位与 OVERLOAD 交互

```text
if 持有 fire_control_saturation and status_effects 包含 OVERLOAD:
  effective_max_locks += 2
```

- `+2` 跟随 **OVERLOAD 的实际存续时间**，不是独立 6 秒计时器；状态消失当刻自动收回。
- 任意来源的 OVERLOAD 都能开启本技能的 `+2`，包括其它超载来源。
- 本技能触发仍走统一 OVERLOAD 时长链：已有倍率与固定延时终端可以延长最终状态时长，
  `+2` 自动跟随延长后的状态。
- 与 F-22 的 STEALTH `+2` 同时存在时，两项加成相加；各自状态结束时只收回自己的部分。
- 席位回落不会删除已有雷达进度；导弹齐射在每次开火时重新按当前有效席位截断目标数。

### 3.4 OVERLOAD 构筑闭合

本技能是新的 OVERLOAD 来源。`overload_duration_4x`、`overload_extended_ammo`、
`overload_to_bloodlust` 与 `storm_ii` 的 OR 前置列表必须承认本技能。

## 4. 结构与组成（Structure）

- 数据与 i18n：正式升级表 + 三语技能表。
- 低频触发：`SkillHooks` 统计当前王牌已有主雷达锁定字典。
- 单局状态：生存模式主控持有 `{cooldown, latched}`，切控不重置。
- 动态锁数：飞机的统一有效锁数查询叠加本技能与 F-22 状态加成。
- Debug：F4 面板动态读取正式技能表，可绕过门控直接授予，仍尊重单层上限。

## 5. 验收标准（Acceptance / Litmus）

- [x] 数据：实验级、骑士轴、`scope=ace`、单层，不附加 `classes` 品类限制。
- [x] 四锁不触发；五个合法主雷达满锁且有效席位至少 5 时触发基础 6s OVERLOAD。
- [x] OVERLOAD 存续期间有效锁数 +2；状态结束立即回落，延时终端能同步延长加成。
- [x] 同一段五锁不反复触发；CD 内重新跨线不触发；CD 结束且再次跌破／跨线后可触发。
- [x] 切控不清内置 CD；效果只由当前王牌的生效子集触发。
- [x] 四个既有 OVERLOAD 终端均承认本技能为合法来源。
- [x] F4 Debug 动态覆盖、三语玩家文本与 OVERLOAD 状态脚注齐全。
- [x] 运行时：`skills720`、`skill_audit`、`status_notes`、`i18n_build` 专项 bench 全绿。
- [x] 性能：Sentinel + Lv5+ 压力样本保持 60 FPS 以上，雷达 tick 无新增全场扫描。
- [x] 文档：spec 登记、生成技能表、reference 索引、锚点与当前文档校验全绿。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与状态语义
- [x] 正式升级条目、骑士／王牌归属、OVERLOAD 来源元数据与三语。
- [x] 四个 OVERLOAD 终端补入新来源。

### 阶段 2 — 运行时
- [x] 在数据链合并后的低频雷达 tick 统计五个合法满锁。
- [x] 单局 CD／锁存状态与统一 OVERLOAD 入口。
- [x] 有效锁数查询在 OVERLOAD 实际存续期间追加 +2。

### 阶段 3 — 回归与索引
- [x] 补数据、五锁、CD、重新跨线、状态结束回落与终端闭合断言。
- [x] 运行专项 bench、压力样本、文档与差异检查。

## 7. 索引锚点（Where —— 指针，会腐烂，非权威）

| 关注点 | 文件 |
|---|---|
| 升级条目／终端前置 | `scripts/survivor/survivor_data.gd`（UPGRADES） |
| 触发常量与五锁沿 | `scripts/survivor/skill_hooks.gd`（try_fire_control_saturation） |
| 单局 CD 接线 | `scripts/survivor/survivor_mode.gd`（_update_radar_locks） |
| OVERLOAD 期间锁数 | `scripts/aircraft.gd`（effective_max_locks） |
| 回归 | `scripts/tests/test_skills_720.gd`（_test_overload_axis_and_terminals） |
| 三语 | `i18n/skills.csv`（UPGRADE_FIRE_CONTROL_SATURATION_*） |
| reference | `docs/reference/skill-implementation-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-17 | 1 | 用户定稿基础效果；内置 CD 按同类强触发档位落为 20s，并明确五锁上升沿、切控保持与 OVERLOAD 实际时长跟随。 |
