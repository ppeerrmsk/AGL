# 2026-05-03 — 空中漂浮雷 / Drift Mine（A-10 实验武器）

## 新机制：规避触发型降落伞挂雷

灵感原型：英国二战 Long Aerial Mine (LAM) — 把炸弹挂在降落伞下投放到敌机航线前方。AGL 抽象后做成"规避模式 → 飞机周围撒下若干降落伞雷 → 各自向不同方向缓慢漂移 + 缓降 → 敌人靠近自爆 AOE"。

### 玩家交互
- **激活**：进入规避模式（KEY_E）
- **触发**：CD 完毕（默认 5s）即在飞机周围撒下若干颗（默认 3 颗），各自往不同方向漂
- **退出**：取消规避模式 → 不再投放（CD 仍然倒数）
- **HUD**：TORP 状态条显示 READY / CD% / "(Evade)" 灰字提示需要先开规避

### 行为
- 投放点 = 飞机当前位置（**留在原地**，不往机尾发射）
- 漂移方向：在 0~2π 上均匀分布 + 抖动 ±14°，让"几个方向都有"
- 漂移速度：18-45 m/s 随机（缓慢飘）
- 缓降速率：8 m/s（降落伞下沉）
- **弱追踪**：1500m scan 半径内有敌人时，慢慢（20°/s）旋转漂移方向往敌人靠
- **追踪中暂停寿命**：捕获目标后 life 不再倒数；目标丢失 / 离开 scan 才继续 → 这样"咬住"敌方的雷不会半路淡出
- 引爆 → 130m AOE → 45 dmg 半径内统一伤害
- 寿命 14s（仅未追踪状态下倒数），超时不爆静默消失
- 不被 CIWS / Laser 拦截（与火箭弹同级独立武器）
- **同屏上限**：每个 source 最多 21 颗（`MAX_TORPEDOES_PER_SOURCE`），超出则 spawn 直接 return — 给未来"减 CD 升级"留好天花板

### 实现要点（运算成本极低）
- 不进入 Missile / PN 制导系统
- 数据结构：`BulletManager._torpedoes: Array[Dictionary]`，每帧只做：
  1. 重选目标（节流 0.5s/次，scan 范围线性扫 combat_unit_list）
  2. 旋转 drift_vel 朝目标（atan2 + signf + clamp）
  3. 漂移位移 + 高度递减
  4. 近炸扫描（与火箭弹同 helper）
- 21 × ~22 单位 / 0.5s = ~1k 距离比较/秒，纯 Vector2 算术，可忽略
- 引爆复用 `_explode_rocket()` 的 AOE 逻辑（构造一个 fake bullet dict 喂进去）

## 文件改动

### 新建
- `scripts/torpedo_params.gd` — `TorpedoParams extends Resource`
- `resources/a10_torpedo.tres` — A-10 鱼雷数据
- `docs/changelogs/2026-05-03-aerial-torpedo.md`（本文件）

### 修改
- `scripts/aircraft_params.gd` — 加 `@export var torpedo: TorpedoParams`
- `scripts/aircraft.gd` — 加 `_torpedo_cooldown: float`；在 LOD 0/1/2 三档物理路径都调 `AircraftWeapons.update_torpedo()`
- `scripts/aircraft/aircraft_weapons.gd` — 末尾加静态 `update_torpedo(ac, delta)`
- `scripts/bullet_manager.gd` — 加 `_torpedoes` 数组 / `spawn_torpedo()` / `_update_torpedoes()` / `_torpedo_pick_target()` / `_explode_torpedo()` + `_draw()` 末尾加青色弹体绘制
- `scripts/survivor/survivor_hud.gd` — RKT 段后加 TORP 状态显示
- `resources/playable_a10_base.tres` — 挂 `torpedo = a10_torpedo.tres`

## 数值快照（A-10 漂浮雷）

| 参数 | 值 | 备注 |
|---|---|---|
| 投放冷却 | 5 s | 规避模式下持续倒数；未来技能可减 |
| 单次投放数 | 3 颗 | 朝周围均匀分布的方向飘 |
| 寿命 | 14 s | 仅未追踪时倒数；超时静默消失 |
| 同屏上限 | **21 颗 / source** | 给"减 CD 升级"留天花板 |
| 漂移速度 | 18-45 m/s | 随机 |
| 缓降速率 | 8 m/s | 降落伞下沉 |
| 追踪 scan | 1500 m | 内有敌方才追 |
| 追踪转向 | 20 °/s | 9 秒转 180°，"被微弱吸引"感 |
| 重选目标间隔 | 0.5 s | 节流 |
| 近炸距离 | 90 m | 触发引爆 |
| AOE 半径 | 130 m | 引爆中心 |
| AOE 伤害 | 45 | 半径内统一（kind="rocket"，不被导弹 cap 卡）|

## 设计契合度

| 原则 | 契合方式 |
|---|---|
| 1) 一击毙命 | AOE 45 dmg ≤ ENEMY_HP_MISSILE_CAP 75，命中即接近一发死 |
| 2) 笨重 + 延迟快感 | CD 5s + 飞行 + 追踪 + 引爆四阶段，命中瞬时反馈 |
| 3) 信息察觉优先 | 青色弹体 + 蓝色尾迹明显区别于火箭弹 / 子弹；HUD TORP 段 |
| 5) 武器抽象优先 | 不模拟空气动力、惯性、推进器；只有"航向 + 速度 + 转向限速" |
| 10) 全自动开火 | 进入规避 + CD 好 → 自动抛出，无任何手动键 |

## 同日二次平衡（按用户反馈）

### 设计哲学新增：F-16 雷达 = 弱基准
[DESIGN_PHILOSOPHY.md §4(d)](../DESIGN_PHILOSOPHY.md) — "飞机初始雷达距离以 F-16 (5000m) 为'比较弱'的标准。比 F-16 强才是真的强。"
- A-10 雷达 3500 → **5000**（与 F-16 baseline 对齐）

### 火箭弹伤害 = 以导弹（80）为参照 + 距离衰减
- 新字段 `RocketParams.min_damage_mult: float = 1.0`（默认无衰减，保持敌方 AI 火箭兼容）
- A-10 火箭弹：
  - `rocket_damage` 25 → **100**（直击）
  - `aoe_damage` 30 → **90**（近炸）
  - `min_damage_mult` = **0.7**（飞到 max_range 时倍率）
- 衰减曲线（线性 lerp）：
  | 飞行进度 | 直击伤害 | AOE 伤害 |
  |---|---|---|
  | 0%（贴脸）| 100 | 90 |
  | 50% | 85 | 76.5 |
  | 80%（典型交战末端）| 76 | 68.4 |
  | 100%（max_range）| 70 | 63 |
- 0-65% 进度直击始终 > 导弹 80；AOE 0-30% 进度 > 导弹 80。整体"绝大多数情况比导弹高"达成。
- 实现：`BulletManager._rocket_falloff_mult(b)` 静态辅助 + `spawn_rocket_with_falloff` 包装器；直击 + AOE 共用同一个倍率
- ⚠ 数值越界：`rocket_damage = 100` 触及 30-100 dmg 区间上限，allowed exception（"贴脸炸弹巢"机制使然，平均交战距离衰减后实际命中通常 80-90）

### 漂浮雷伤害 = 导弹标准（80）
- A-10 漂浮雷 `aoe_damage` 45 → **80**（与导弹平齐，因为是慢速等待型武器）

## 后续可扩展

- 给其他主角（F-14 / X-02）配独立的 .tres，参数差异化
- 鱼雷自带"规避偏好"buff：投放时短暂提升玩家本机的规避属性，强化"规避一体化"主题
- 升级条目（exclusive_to=["a10"]）："鱼雷连发" / "AOE 加大" / "鱼雷数量 +1"

## 测试

1. F5 → 第 4 槽 A-10 → 出击
2. HUD 应显示 "TORP (Evade)" 灰字
3. 按 KEY_E 进入规避 → 5 秒后第一发鱼雷从机尾抛出（青色光点）
4. 鱼雷飞向最近敌方编队，靠近后引爆出蓝色爆炸 + 半径内多杀
5. 退出规避 → 不再投放，但 HUD CD 仍在倒数
6. 沙盒模式不受影响（PlayableAircraft 路径不进沙盒）
7. 性能：观察 22 架敌机 + 5 颗在飞鱼雷场景，FPS 应无明显下降（鱼雷热路径只有 5 单位 × N 敌机的距离扫描）
