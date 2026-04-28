# 更新日志 — 2026-04-28（commit 6）

## 装备模块化 commit 6/13 — CobraEvasion / HerbstEvasion 标记装备

最后两件 EvasionModule 子类。眼镜蛇和赫尔贝特轮**没有 params 资源**——
它们是挂载到 Aircraft 的 Node 子节点。装备类只是"声明 + 自动挂载"的桥。

## 本 commit 内容

### 新增 `scripts/equipment/cobra_evasion.gd` + `herbst_evasion.gd`

```gdscript
class_name CobraEvasion extends EvasionModule
func _init(): equipment_kind = "cobra"

class_name HerbstEvasion extends EvasionModule
func _init(): equipment_kind = "herbst"
```

`should_trigger` / `execute_evasion` 暂留 base no-op，commit 7 投票模型上线后实装。

### 修改 `scripts/aircraft.gd`

`_publish_equipment_to_legacy` 追加 Node 自动挂载：

```gdscript
if params.has_equipment_of_kind("cobra") and get_maneuver() == null:
    add_child(CobraManeuver.new())
if params.has_equipment_of_kind("herbst") and get_herbst() == null:
    add_child(HerbstManeuver.new())
```

**幂等性**：检测已存在子节点则跳过。现存手动挂载路径不动：
- `survivor_player.gd:232`（玩家升级 cobra）
- `survivor_spawner.gd:1398`（部分敌人升级 cobra）
- `poltergeist_squad.gd:234`（F-14 BOSS 拿 herbst）

这些代码先 `add_child(CobraManeuver.new())`，publish 后续检测 `get_maneuver() != null` → 跳过，不重复挂载。

### 兼容覆盖

无破坏性变化：
- 老飞机（equipment 空）→ has_equipment_of_kind("cobra") false → publish 不挂载 → 走老路径
- 新飞机（equipment 含 CobraEvasion）→ publish 自动挂载 → 与手动挂载等效
- 现存手动挂载点不动 → 玩家升级 / spawner / BOSS 路径全保留

## 验证

跑生存模式：
- 玩家升 cobra 技能 → 测眼镜蛇激活（按键触发或 AI 自动判定）
- 遇到带 cobra 升级的高级敌人（survivor_spawner.gd:1398 那批）→ 测它们的眼镜蛇规避
- F-14 Poltergeist BOSS 对战 → 测 J-Turn 反杀

## 累计进度

```
[完成] commit 1-6 装备类全部到位（Gun/Rocket/Missile/Flare/Cobra/Herbst）
        commit 7  TacticalPlanner 投票模型 ★ 关键步骤
        commit 8  老路径删除
        commit 8' 升级过滤
        commit 9  RailgunEquipment ★ 第一个新机制
        commit 9' LaserEquipment
        commit 10' X-02 主角 ★
        commit 10'' 敌人版 + AF-03 + 激光 UAV ★
        commit 11  阶段清理
```

## 节点

至此**所有现存武器/规避装备都已包装完毕**。下一步 commit 7 是真正的硬骨头——
TacticalPlanner 改投票模型，把 13 种 intent 决策从硬编码改成"装备投票"驱动。
那一步上线后，本 commit 1-6 写的 `desired_engagement` 才真正参与决策。

可以选择：
1. **直接进 commit 7**（投票模型）—— 风险较高，需细心做新旧路径并存的 USE_EQUIPMENT_VOTING 主开关
2. **先跳到 commit 9（RailgunEquipment）**—— 跳过 7/8，先做新装备类型，做完再回头改 planner。这样能更快看到 X-02 雏形，但有些功能（武器锁定后 AI 选战术）不会自动用上电磁炮的"远距 TAIL_CHASE"偏好
3. **先做 commit 8'（升级过滤）**—— 这个最简单，纯生存模式 UPGRADES 表加 requires_equipment_kind 字段，效果立竿见影：玩家选 X-02 之后升级池里不再出 missile/gun/flare 升级
