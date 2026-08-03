---
id: strategic-hardened-targets
kind: system
status: in-progress
schema_version: 1
spec_version: 1
owner: 用户 + Codex
depends_on: [bomber-strike-missions, global-awareness-roe]
reconstruction_complete: true
---

# 战略硬目标（Strategic Hardened Targets）

> 地堡、仓库、导弹发射井是轰炸任务的专属目标：它们不能被战斗机锁定，也不接受任何常规武器伤害；玩家通过护航轰炸机、压制防空和保障投弹航路来摧毁它们。

## 1. 设计意图（Why）

- 把轰炸机从“另一种输出飞机”变成任务解法，建立护航、截击和防空压制目标。
- 战斗机不能直接绕过任务结构；不可锁定必须是目标层权限，不依赖某一枚导弹的特殊过滤。
- 硬目标自身不反击，不增加弹幕密度；威胁来自其周边既有 SAM/AAA 配置。
- 三种外观共享同一行为与数值，差异只用于地图叙事。

## 2. 数据定义（What）

### 2.1 类型与参数

| 字段 | 地堡 | 仓库 | 导弹井 |
|---|---:|---:|---:|
| `target_kind` | `BUNKER` | `WAREHOUSE` | `MISSILE_SILO` |
| `max_hp` | 150 | 150 | 150 |
| 碰撞半径 | 32 px | 40 px | 28 px |
| 武器 / 雷达 / 移动速度 | 无 | 无 | 无 |
| 高度 | `GROUND` / 0m | `GROUND` / 0m | `GROUND` / 0m |
| 接受伤害 | `kind == "bomber_bomb"` 且攻击者阵营敌对 | 同左 | 同左 |

一次 75 伤害的炸弹需要两次有效覆盖；五枚弹带允许航路误差，但不能让单枚擦边直接抹掉全部目标。

### 2.2 锁定与伤害权限

- `is_lock_immune()` 永久返回 `true`，因此不会进入玩家、AI、SAM、舰船或副雷达的锁定候选。
- 覆写 `take_damage(amount, attacker, kind)`：仅接受 `kind == "bomber_bomb"`，且 `attacker` 提供的阵营与本单位敌对；其余调用无伤害、无受击闪烁、无击杀收益。
- 炸弹发射者死亡后仍能结算：炸弹保存释放瞬间的 `source_team`；`attacker` 可为空，战略目标以显式 `source_team` 参数校验阵营。
- 为避免扩大全局 `take_damage` 签名，炸弹管理器调用 `StrategicTarget.take_bomber_damage(amount, source_team, attacker)`；普通 `GroundUnit` 仍走现有 `take_damage(..., "bomber_bomb")`。
- 玩家点击/RTS 命令、自动机炮扫描、导弹候选和激光扫描均因 `is_lock_immune()` 被过滤；爆炸等无锁定常规伤害仍由伤害通道门挡住。

## 3. 行为与公式（How）

```text
for unit in bomb_aoe_neighbors:
    if not teams_hostile(source_team, unit.team): continue
    if unit is StrategicTarget:
        unit.take_bomber_damage(75, source_team, safe_attacker)
    elif unit is GroundUnit:
        unit.take_damage(75, safe_attacker, "bomber_bomb")
```

- AOE 半径内为均匀伤害；建筑不按中心距离衰减。
- HP 归零时播放一次向外扩张的双环爆炸和碎片线，随后按普通 `CombatUnit.destroyed` 生命周期回收。
- 单位静止，仅在状态变化时 `queue_redraw()`；不新增 `_process`。
- 场景/事件通过 `spawn_strategic_target(kind, team, position)` 创建，可混合放置三种外观。

## 4. 结构与组成（Structure）

- `StrategicTarget extends GroundUnit`：伤害门、静态绘制、三种外观。
- 类型与碰撞半径由节点导出字段承载，基础战斗数值复用一份 `.tres`。
- `SurvivorSpawner` 提供生成入口，任务或 debug 决定阵营、类型与位置。
- `BulletManager` 仅在炸弹 AOE 分支识别 `StrategicTarget`，不把专属权限扩散到普通武器。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 三种外观均可由同一 API 创建为任意阵营，固定在地面且无武器。
- [ ] 玩家机炮、火箭、导弹、激光、普通爆炸均无法锁定或扣除其 HP。
- [ ] 友军 B-1B 炸弹只伤敌方硬目标；敌军 Tu-160 炸弹只伤友方硬目标。
- [ ] 两枚命中的 75 伤害炸弹摧毁 150 HP 目标；一枚命中后保留 75 HP。
- [ ] 轰炸机释放后被击落，已投炸弹仍按保存阵营正常伤害硬目标。
- [ ] 无每帧全场扫描；AOE 使用共享空间网格的邻域候选。
- [ ] 销毁、空引用、重复爆炸与同阵营过滤均无报错。

## 6. 实现计划（Task Pipeline）

- [x] 新增 `StrategicTarget` 脚本、场景、参数与三种线框外观。
- [x] 新增 spawner/任务公共入口，接入轰炸炸弹专属伤害分支。
- [x] 增加锁定、伤害门、阵营与释放者失效测试。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 硬目标行为 | `scripts/strategic_target.gd` |
| 场景 | `scenes/strategic_target.tscn` |
| 参数 | `resources/strategic_target_params.tres` |
| 生成入口 | `scripts/survivor/survivor_spawner.gd` |
| 炸弹伤害 | `scripts/bullet_manager.gd` |
| 回归 | `scripts/tests/test_bomber_rotor_airburst.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-01 | 1 | 用户确认：新增地堡、仓库、导弹井；不可被战斗机锁定或常规武器伤害，只接受轰炸机炸弹伤害。 |
| 2026-08-01 | 2 | 实现三种线框外观、永久锁定免疫、`bomber_bomb` 双重伤害门和释放者失效后的阵营快照结算；专项 bench 已通过。 |
