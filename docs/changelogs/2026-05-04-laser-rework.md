# 2026-05-04 — 激光武器重做：默认减速 / 致伤变升级

## 设计变更

旧定位：360° 全向 DPS 武器，扫到就开始 DoT。
**新定位**：**软压制 / 控制型武器**——扫到目标只施加 SLOW 状态，不直接造成伤害。导弹拦截不变（防御角色保留）。玩家通过 build 升级 `skill_laser_damage` 后才解锁伤害输出。

为什么改：
- 让激光在武器矩阵里有独特角色（控制 vs 输出），不再"另一种 DPS"
- SLOW 让被扫飞机 cap 350 km/h + 屏蔽 AB → 给玩家 / 队友导弹和机炮制造杀伤窗口
- 导弹拦截功能完整保留 → Aegis UAV / X-02 防御性使用不受影响
- 致伤作为"build 选择"而不是默认能力，符合 AGL 的"build-defining 升级"哲学

## 实现要点

### LaserEquipment 行为

| 目标类型 | 默认（无 skill） | 持有 SKILL_LASER_DAMAGE |
|---|---|---|
| **Aircraft** | 每帧刷 SLOW 状态（0.4s 续期，脱离光束 0.4s 后消失） | SLOW + 完整 DPS 伤害 |
| **Missile** | **强减速**（_laser_slow_timer，速度 cap 45% + 转弯 G cap 50%）→ 玩家有时间机动闪开 | 强减速 + intercept_hp（CIWS 拦截回归） |
| **GroundUnit** | 无效（"激光不熔化坦克"，机制定位） | 完整 DPS 伤害 |

### 导弹减速实现（与 SLOW 状态独立）

导弹不是 CombatUnit，没有 status_effects 系统。单独走 `Missile._laser_slow_timer`：
- LaserEquipment 每帧续期到 `LASER_MISSILE_SLOW_DURATION = 0.5s`
- Missile._physics_process 顶部统一倒数（VLS / 渐隐 / 主路径都覆盖，避免被旁路）
- timer > 0 时：`max_speed × 0.45` + `max_g × 0.5`（VLS 转向速率也按 0.5 倍）
- 减速比飞机版（`SLOW` 状态 cap 350 km/h）更猛，因为导弹无法做大角度规避，强减速才能让玩家闪开
- 不直接击落 — 导弹仍然飞但速度慢、转弯弱，玩家有时间侧滑机动 / 释放热诱弹

### SLOW 状态效果（status_effects.gd 已有定义）
- `target_speed_kmh` cap 至 **350 km/h**（`SLOW_SPEED_CAP_KMH`）
- 屏蔽 `is_afterburner`
- 滚转倍率 ×0.6（`SLOW_ROLL_MULT`）
- 飞机 HUD / 数据标签可见 SLOW 标记

### 持续刷新
- 每帧应用 `unit.apply_status(StatusEffects.SLOW, 0.4)`
- StatusEffects 内部用 max() 合并 → 保持 0.4s
- 玩家停止扫描 → 0.4s 后状态自然消失，目标恢复正常机动
- 不依赖具体激光 stack；同时被多个激光照射效果不叠（已是状态，不是 DPS）

## 新升级

| 字段 | 值 |
|---|---|
| id | `skill_laser_damage` |
| 名称 | 激光·致命输出 / Lethal Lasing |
| 描述 | 激光在减速基础上叠加完整 DPS 伤害（贴脸 dps_max → 满射程 dps_min 衰减） |
| stat | `skill_flag` |
| max_stacks | 1 |
| requires | `["laser"]` |
| rarity | ADVANCED |

## 文件改动

| 文件 | 改动 |
|---|---|
| [equipment/laser_equipment.gd](../../scripts/equipment/laser_equipment.gd) | 头部注释重写；`update()` 改为 `_apply_laser_effect`；新 `_has_damage_skill` 守卫；`_apply_laser_damage` → `_apply_laser_effect` 重命名 + 分发逻辑（导弹走 _laser_slow_timer，Aircraft 走 apply_status SLOW） |
| [missile.gd](../../scripts/missile.gd) | 加 `_laser_slow_timer` 字段；`_physics_process` 顶部统一倒数（VLS / fade / 主路径都覆盖）；speed cap + max_g cap 在主路径与 VLS 非末端都接入 |
| [survivor/skill_hooks.gd](../../scripts/survivor/skill_hooks.gd) | 加 `SKILL_LASER_DAMAGE` 常量 + `LASER_SLOW_REFRESH_DURATION = 0.4` + `LASER_MISSILE_SLOW_DURATION = 0.5` + `LASER_MISSILE_SPEED_MULT = 0.45` + `LASER_MISSILE_G_MULT = 0.5` |
| [survivor/survivor_data.gd](../../scripts/survivor/survivor_data.gd) | UPGRADES 加 `skill_laser_damage` 条目（requires:["laser"]） |
| [i18n/translations.csv](../../i18n/translations.csv) | 加 NAME + DESC（zh/en/ja） |

## 不变的部分
- LaserEquipment 的过热机制 / 多目标限制 / 云层削弱 / 视觉绘制全部保留
- 距离衰减曲线（`dps_max → dps_min`）只影响伤害——SLOW 不衰减（扫到就 cap 速度，距离无关）
- AI 对激光武器的目标偏好（CLOSE_TAIL / 0.4× 射程）不变
- `_pick_targets` 的 target_filter（aircraft/missiles/ground 三档）不变
- Aegis UAV 仍按 missiles=true 配置照常拦截敌方导弹

## 设计契合度

| 原则 | 契合方式 |
|---|---|
| 1) 一击毙命 | 激光不再压一击毙命的爽感 — SLOW 的目标仍然是被你的导弹 / 火箭 / 队友火力一发解决 |
| 3) 信息察觉 | SLOW 状态有专属图标（冰蓝）+ 飞机数据标签可见 + 速度直接 cap → 玩家清晰看到"我打慢了它" |
| 5) 武器抽象 | 不引入"红外 vs 雷达激光"等现实分类，纯参数化（dps + slow flag） |
| 7) AI 演戏 | 被 SLOW 的敌机不能 AB 撤退 → 强制陷入劣势机动 → 玩家可见"敌人变笨了" |
| 10) 全自动开火 | 激光仍是"飞进射程自动扫"，无任何手动键 |

## 同时新增升级：分束扩容（laser_extra_beams）

| 字段 | 值 |
|---|---|
| id | `laser_extra_beams` |
| 名称 | 激光·分束扩容 / Laser Splitter |
| 描述 | 激光可同时照射的目标数 +2（每层叠加，最多 +4）|
| stat | `laser_extra_beams` |
| max_stacks | 2 |
| value | 2 |
| requires | `["laser"]` |
| rarity | STABLE |

**实现**：`apply_upgrade` 取 `params.get_equipment_of_kind("laser")` 强转 `LaserEquipment` → `max_simultaneous_targets += 2`。装备数组已由 `SurvivorPlayableSetup.deep_dup_weapons` 深拷贝，直接改不会污染原 .tres。

**联动效果**：拿到分束扩容 + 激光致伤 + 大量敌机刷出 → 一束扫一只大幅放大压制力，是"激光控场流"的核心 build。

## 后续可加（未实现）

- `skill_laser_slow_extend` — SLOW 持续时间从 0.4s → 1.5s（脱离光束后还慢一会儿）
- `skill_laser_slow_radius` — SLOW 同时溅射给目标周围 600m 内的友机（编队压制）
- `skill_laser_jam` — 激光附加 JAM 状态（武器 / 雷达全锁死）

待玩家在主流（控制 vs 输出）选定后再决定加哪个分支。
