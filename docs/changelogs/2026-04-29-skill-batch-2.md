# 2026-04-29 — 第二批便利贴（5 张）+ AOE 视觉

承接同日的 [foundations](2026-04-29-skill-system-foundations.md) 和 [rarity-evasion-batch](2026-04-29-skill-rarity-evasion-batch.md)。

## 表现层：AOE 视觉脉冲

新文件 `scripts/survivor/aoe_pulse_vfx.gd`：
- 紫色圆环勾勒生效范围 + 命中目标小爆裂
- 1.2s 淡出，圆环略外扩
- 颜色按状态自动选（FEAR=紫 / JAM=绿 / INVUL=金）；可显式覆盖
- 即使 hit_count=0 也画范围圈（让玩家知道"我触发了"）
- AOEBroadcast.apply_status_in_radius 自动 spawn

## 第二批 5 张技能

| id | 稀有度 | 关键词 | 效果 |
|---|---|---|---|
| `head_on_gun_dodge` | EXP | gun, head_on, chivalry | 对头交锋时机炮闪避 +60% |
| `gun_fire_dr` | CLA | gun, panic_save | 机炮发射后 0.4s 内受到伤害 -50% |
| `fear_on_lock` | EXP | fear, radar, lock | 持续锁定敌人 4s → 给其施 FEAR |
| `cloud_overload` | CLA | cloud, overload | 在云中获得超载状态（进/出云事件 toggle）|
| `cloud_weapon_cd` | CLA | cloud, gun, missile | 云中所有武器 cd ×0.5 |

## 实现细节

### 对头机炮闪避
`Aircraft.take_bullet_damage(amount, attacker)` 增加 attacker 参数，在 effective_dodge 累加上检查双向 dot：
```
my_fwd · to_attacker > 0.7 AND attacker_fwd · -to_attacker > 0.7
```
（双方机头都对着对方 ≲ 53° 内才算对头，避免侧射误判）

`bullet_manager.gd` 同步把 `b["source"]` 传进去；`take_bullet_damage` 内部把 attacker 写到 `_pending_attacker` meta，保证致死时归因正确。

### 机炮发射减伤窗口
- `aircraft_weapons.update_gun` 开火后刷新 `_gun_fire_recently_until = now + window`
- `aircraft._apply_damage` 顶层查时间戳；在窗口内 `amount *= (1 - dr_amount)`
- 时间戳用 `EventLogger.get_game_time()` 全局 tick，不会被暂停影响

### 锁定累积恐惧
- `Aircraft._locked_target_seconds: Dictionary[instance_id → float]`
- `survivor_mode._update_radar_locks` 在玩家锁敌方时累加；离开锥外清零
- 达到 `fear_on_lock_threshold` 即 AOEBroadcast.apply_status_in_radius（半径 50px = 单点）施 FEAR 4s + 累积归零（让玩家可重复触发）
- 自动获得 AOE 紫色圆环 VFX

### 云边界事件
- `Aircraft._on_cloud_boundary(entering: bool)` 由 `_update_cloud_state` 在 `cloud_state >= 1` 状态变化时调用
- 仅玩家（team==0）走这条路径
- **云中超载**：进入 apply OVERLOAD 9999s（用 owner 跟踪 `_cloud_owns_overload` 避免与其它来源打架）+ 出云 remove
- **云中武器 cd**：进入按倍率 scale 当前 cd（同 §1.2 evasion_modifiers 模式），出云反向 unscale
- 进/出云事件触发频率受 `_update_cloud_state` 0.2s 节流保护，避免边缘抖动

## 文件清单

**新增**：
- `scripts/survivor/aoe_pulse_vfx.gd`

**改动**：
- `scripts/survivor/aoe_broadcast.gd` — apply_status_in_radius 自动 spawn VFX；新增 _color_for_status / _resolve_scene_root
- `scripts/aircraft.gd` — 7 个新字段（head_on_gun_dodge_bonus / gun_fire_dr_window / gun_fire_dr_amount / _gun_fire_recently_until / fear_on_lock_threshold / _locked_target_seconds / cloud_overload_active / cloud_weapon_cd_mult / _was_in_cloud_last_frame）；take_bullet_damage 加 attacker 参数 + 对头几何检查；_apply_damage 加机炮减伤窗口；_update_cloud_state 末追加 _on_cloud_boundary 检测；新增 _on_cloud_boundary 函数
- `scripts/aircraft/aircraft_weapons.gd` — update_gun 开火后刷 _gun_fire_recently_until
- `scripts/bullet_manager.gd` — take_bullet_damage 调用传 attacker
- `scripts/survivor/survivor_mode.gd` — _update_radar_locks 维护玩家 _locked_target_seconds + 触发 FEAR
- `scripts/survivor/survivor_data.gd` — 5 张新 UPGRADES
- `scripts/survivor/survivor_player.gd` — 5 个 stat case
- `i18n/translations.csv` — 10 条翻译 key

## UPGRADES 总数

约 60 张技能，覆盖白板便利贴的 70%+。

剩余难度较高的便利贴（需要新基础设施）：
- 缠斗累计恐惧 / 后半球减速光环 → engaging_me 反向索引
- evasion 模式眼镜蛇 / J-Turn 触发 → 改 _apply_damage 钩子
- evasion 模式隐身 / 4s 装填突破上限 → set_evasion_mode 触发 + 装填 timer
- F-14 全僚机锁同一目标 → 僚机管理层 0.5s 检查
- 持久 flare 实体 → PersistentFlare 节点 + 导弹目标重定向（已决定跳过）
