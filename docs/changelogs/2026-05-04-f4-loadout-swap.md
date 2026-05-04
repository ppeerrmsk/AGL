# 2026-05-04 — F4 装备装载切换面板

在 F4 调试模式下，**屏幕左侧独立面板**显示装备装载切换（与中央技能面板同步显隐）。可即时切换玩家飞机的次要武器槽位，方便测试不同 build 组合。

> 设计变更：原本想加在中央 F4 面板末尾，但中央面板高度已 680px，再加 6 个 OptionButton 会被裁掉看不到。改为屏幕左侧独立 PanelContainer（380×360），与 F4 面板同时切换可见性。

## 槽位清单

| 槽位 | 类型 | 可选 | 备注 |
|---|---|---|---|
| **机炮 (gun)** | — | 锁定 | 用户指定固定不可换 |
| **主导弹 (missile)** | — | 锁定 | 用户指定固定不可换 |
| 规避槽（互斥）| evasion_mutex | 无 / 漂浮雷 / 忠诚僚机 | torpedo 与 loyal_wingman 二选一，自动清对方 |
| 火箭弹 (params.rocket) | field | 无 / FFAR / Hydra 70 / A-7 / Q-5 / AH-64 | |
| 副导弹 (params.secondary_missile) | field | 无 / AGM | |
| 热诱弹 (params.flare) | field | 无 / 默认 / F-14 / F-16 / F-47 | |
| 电磁炮 (equipment.railgun) | equipment | 无 / X-02 / 敌方(AF-03) | 走 params.equipment 数组 |
| 激光 (equipment.laser) | equipment | 无 / X-02 / Aegis 拦截 | 走 params.equipment 数组 |

## 实现要点

### 切换语义
- **field 类**：直接 `params.set(field_name, dup_resource)`；切换后清相关 runtime 状态（rocket → 重置弹量 + cooldown；flare → 重置弹量；secondary_missile → 重置弹量）
- **equipment 类**：先从 `params.equipment` 数组移除所有该 `equipment_kind` 的条目；清 `aircraft.equipment_state[kind]`；再 append 新装备的 duplicate；调 `_publish_equipment_to_legacy()` 同步老字段
- **evasion_mutex**：清 torpedo + loyal_wingman 双槽，再按选项设其中一个；活着的 drone / 漂浮雷不强制清场（让其自然走完寿命）

### 资源 duplicate + 来源路径 stash
- 切换时一律 `res.duplicate(true)`，避免运行时改污染原 .tres
- `duplicate(true)` 会**清空** `resource_path`，所以同时 `dup.set_meta("_loadout_origin_path", path)` 把来源路径存到 meta 上
- 下次刷新 OptionButton 状态时 `_resolve_current_index` 优先读 meta，回退 resource_path

### UI 入口
- `_build_loadout_rows()` 在 `_build_ui` 末尾构建（在状态测试段之后、底部提示之前）
- 每行：Label(220px) + OptionButton(expand) → `item_selected.bind(slot_key)` → `_on_loadout_changed`
- F4 打开 / `_refresh()` 调用时同步 OptionButton 选中项 → 与当前 params 状态对齐

## 文件改动

| 文件 | 改动 |
|---|---|
| [scripts/survivor/survivor_debug_skills.gd](../../scripts/survivor/survivor_debug_skills.gd) | 加 `_loadout_section` / `_loadout_options` 字段 + `_LOADOUT_SLOTS` const + `_build_loadout_rows` / `_refresh_loadout` / `_resolve_current_index` / `_on_loadout_changed` / `_reset_runtime_state_for_field` 5 个方法 + UI 接入 + `_refresh()` 调用 `_refresh_loadout` |

## 测试

1. F4 打开调试面板 → 滚到底部"装备装载"段
2. 规避槽：选"忠诚僚机" → 进规避（KEY_E）应释放 drone（不再投漂浮雷）
3. 规避槽：选"漂浮雷" → 进规避应投漂浮雷（drone 不再释放，已活的 drone 走完 25s 寿命自然消失）
4. 火箭弹：选不同 .tres，齐射数 / 散布 / AOE 应跟着变化
5. 电磁炮：选 X-02 Railgun → 玩家飞机获得电磁炮装备（HUD 显示对应段）
6. 激光：选 X-02 Laser → 玩家获得 360° 激光（默认减速；持有 skill_laser_damage 升级时致伤）
## 不变的部分

- 机炮 / 主导弹槽位**固定不动**（用户指定）
- 任何切换都不会污染原 .tres（全部 duplicate(true)）
- 关闭 F4 / 重启游戏后切换不持久（debug 工具语义；持久化走 PlayableAircraft 配置）
