# 资源配置目录

> 最后校订：2026-08-08。
>
> ⚠ **本文是选摘，不是全量**。飞机部分只覆盖**早期的几个基准 .tres**，
> 后来加的大量机型不在这里：
> - **玩家机（43 机）** → `resources/player/player_*.tres`；配平规范看
>   [specs/systems/player-aircraft-power-curve](../specs/systems/player-aircraft-power-curve.md)，
>   进化树看 [specs/systems/aircraft-evolution-tree](../specs/systems/aircraft-evolution-tree.md)
> - **敌机** → [enemy-index.md](enemy-index.md) 的 Enemy Index 表（当前 50+ 个 `EnemyType` 条目；含 `.tres` / Token / 上限 / 解锁等级）
> - **舰船** → `resources/naval/`
>
> 单一机型的准确数值请直接读对应 `.tres`。本文只保留仍有参考价值的**基准值 + 通用子资源**表。

---

## 飞机顶视轮廓

| 资源 | 用途 |
|---|---|
| `resources/aircraft_silhouettes/*.png` | 40 张 128×128 白色 alpha 顶视蒙版，逐架从已审查来源直接提取；原创/虚构/未验证概念机保留旧绘制 |
| `resources/aircraft_silhouettes/README.md` | 格式、直接提取流程、来源边界与禁止项 |
| `resources/aircraft_silhouettes/reference_manifest.json` | 逐机审查状态、来源、许可/署名、处理边界与 alpha 哈希 |

权威数值、复用映射与验收标准见 [aircraft-top-view-silhouettes](../specs/systems/aircraft-top-view-silhouettes.md)。

---

## 玩家仪表字体

| 资源 | 用途 |
|------|------|
| `resources/fonts/AcuminPro-Regular.otf` | 玩家仪表小型信息、字段名、单位、键帽与 PRIORITY |
| `resources/fonts/AcuminProExtraCond-Semibold.otf` | 玩家仪表大号数字与 AFTERBURNER/ENGAGE/FIRE/FLR/MSL/GUN |

两份字体均随项目打包；Acumin 缺少的中日文字形由 `ThemeDB.fallback_font` 补齐。

---

## 飞机参数总表（基准 .tres 选摘）

### `default_fighter`（早期 F-16 基准）

⚠ 这是**沙盒时代的通用基准**，不是当前玩家起手机。生存模式的玩家机走
`resources/player/` + PlayableAircraft 档案注入。保留它是因为多处默认值和文档
（尤其"雷达 5000px 是弱基准"这条设计语言）仍以它为锚。

| 参数 | F-16 (default_fighter) |
|------|------------------------|
| HP | 100 |
| 最大速度 | 2100 km/h |
| 巡航速度 | 900 km/h |
| 失速速度 | 220 km/h |
| 加速度/减速度 | 50 / 80 m/s² |
| G力阻力 | 3.0 |
| 持续G/结构G | 9.0 / 12.0 |
| 滚转速率 | 4.0 rad/s |
| 升限/爬升率 | 15000m / 250 m/s |
| AB倍率 | 1.5 |
| 燃油(容量/正常/AB) | 3000 / 1.5 / 8.0 kg |
| 雷达(范围/半角/锁定) | 5000px=10km / ±30° / 2.5s |
| 机炮 | M61A1 |
| 主导弹 | AIM-7M |
| 副武器槽 SP | AGM-65（字段名 `secondary_missile` 是历史遗留；现在是**通用特殊武器槽**，不是"空对地导弹"）|
| 热诱弹 | 30枚 |
| 颜色 | 蓝色 (0.15, 0.35, 0.85) |

### 敌方机型（本节只保留早期样例；完整现状见 [enemy-index.md](enemy-index.md)）

> 2026-07-26 更名批：UAV 显示名改 **MQ-109**、UCAV 改 **MQ-110**（同族导弹版，正常在役）；
> 另新增有人导弹杂鱼 **F-4E**（`enemy_f4e.tres`，无机炮，HP 45 / 1700 km/h / 雷达 4200m），
> 全量数值见 [specs/enemies/f-4e](../specs/enemies/f-4e.md)。
> Mother Goose 蜂群的机炮型使用专属 `enemy_uav_mg_gun.tres`：1100/650 km/h、加速 55、
> 持续 G 5.5、滚转 2.7；普通 `enemy_uav.tres` 不受其 BOSS 平衡调整影响。
> 激光型 `enemy_uav_mg_laser.tres` 挂 `uav_mg_laser.tres`：真实累计消耗导弹 `intercept_hp`，
> 热量 100、输出 +35/s、过热散热 25/s、30% 恢复门与玩家 X-02 一致。Mother Goose 专属
> `goose_vls_missile.tres` 在 3000m 内停火，累计飞行 8000m 后生成 800m/1.5s 定距 AOE。
> 半血精英对 `enemy_uav_mqx.tres` 使用三发 `mqx_pulse_cannon.tres` + 强化
> `uav_mqx_missile.tres` + 只打导弹的 `mqx_intercept_laser.tres`，并启用 F-22 级传感器隐形。
> WhiteTea 使用王牌专属 `enemy_fck1.tres` + `whitetea_gun.tres`：F-CK-1 ×3，2100/1050 km/h、
> 持续 G 9、4×5 受控短梭、无导弹；完整战术与命数预算见 [ace-whitetea-fck1](../specs/events/ace-whitetea-fck1.md)。
> Black Star / Hyper-A 使用 `enemy_hyper_a_g0.tres` 至 `enemy_hyper_a_g3.tres` +
> `hyper_a_missile.tres`：HP 400/200/100/70、视觉长度 96/80/36/10m、全代 0 flare、
> 4 发导弹弹匣；G0 使用 `1.2s` 锁定、`180°` 雷达半锥与全向离轴齐射许可，G1 恢复普通 `45°` 前向规则；分代特殊行为见
> [hypersonic-splitter](../specs/bosses/hypersonic-splitter.md)。

| 参数 | MiG-29 | J-7 截击机 | MQ-109 | MQ-110 | Sentinel指挥 |
|------|--------|-----------|-----|------|-------------|
| .tres | enemy_fighter | enemy_interceptor | enemy_uav | enemy_uav_missile | enemy_uav_commander |
| HP | 50 | 35 | 40 | 35 | 55 |
| 最大速度 | 2000 | 2400 | 800 | 700 | 650 km/h |
| 巡航速度 | 850 | 1100 | 500 | 450 | 400 km/h |
| 失速速度 | 200 | 240 | 160 | 150 | 150 km/h |
| 加速/减速 | 45/75 | 55/60 | 25/40 | 20/35 | 20/30 |
| 持续G/结构G | 6/9 | 9/12 | 4/5 | 3.5/4.5 | 3/4 |
| 滚转 | 3.0 | 4.5 | 1.8 | 1.5 | 1.2 |
| 雷达范围 | 3600px | 2500px | 800px | 3600px | 1200px |
| 锁定时间 | 3.5s | 4.0s | 5.0s | 4.0s | 99s(不锁) |
| 武器 | M61+AIM7+AGM | M61 | UAV MG | UAV-SAM | 无 |
| 特殊 | - | 快+脆弱 | 低速低G | 导弹型 | 编队指挥 |

### 侦察型

| 参数 | Probe (drone_probe) |
|------|---------------------|
| HP | 30 |
| 最大速度 | 600 km/h |
| 武器 | 无 |
| 雷达 | 无 (range=0) |
| 特殊 | 无武装侦察机 |

---

## 机炮参数总表（选摘）

> 另有多种专用机炮：`ace_gun`（王牌中队）/ `a10_gun` / `a7_gun` / `f86_gun` / `ah64_gun` 等。
> ⚠ 机炮现在是**梭射节奏**（burst 制，非匀速滴弹），见
> [specs/weapons/gun-burst-fire](../specs/weapons/gun-burst-fire.md)。

| 参数 | M61A1 (default_gun) | ZU-23 (aa_gun) | UAV MG (uav_gun) |
|------|------|-------|--------|
| 射速 | 3000 发/min | 1200 | 600 |
| 单发伤害 | 8.0 | 4.0 | 2.0 |
| 初速 | 1050 m/s | 700 | 600 |
| 射程 | 1000m | 600m | 400m |
| 散布 | 1.5° | 6.0° | 6.0° |
| 火控角 | 5.0° | 15.0° | 3.0° |
| 弹药 | 200 | 2000 | 200 |

---

## 导弹参数总表（选摘）

> 另有 `f47_missile`(AIM-260) / `qmaam_missile`（副槽近距格斗弹）/ 舰船 VLS 等，见
> `resources/weapons/` 与各自 spec。

| 参数 | AIM-7M | AGM-65 | HQ-7 (SAM) | UAV-SAM |
|------|--------|--------|------------|---------|
| .tres | default_missile | agm_missile | sam_missile | uav_missile |
| 最大速度 | 1400 m/s | 1000 | 550 | 800 |
| 燃烧时间 | 6.0s | 5.0s | 3.5s | 3.0s |
| 加速度 | 200 m/s² | 180 | 150 | 120 |
| 减速率 | 35 m/s² | 25 | 25 | 40 |
| 最大过载 | 35G | 20G | 15G | 15G |
| PN常数 | 4.0 | 4.0 | 3.5 | 3.0 |
| 后半球射程 | 15km | 10km | 6km | 5km |
| 前/后比 | 4.0 | 3.0 | 1.5 | 2.0 |
| 伤害 | 80 | 90 | 60 | 30 |
| 近炸半径 | 20m | 30m | 20m | 15m |
| 发射后不管 | 否 | 是 | 否 | 否 |
| 挂载数 | 2 | 2 | 4 | 2 |
| 冷却 | 3.0s | 4.0s | 6.0s | 8.0s |
| 存活时间 | 30s | 35s | 20s | 15s |

---

## 战区特殊装备（2026-08-04）

| 资源 | 类型 | 关键参数 | 权威 spec |
|---|---|---|---|
| `resources/esm_pod.tres` | `EsmPodEquipment` | 3000m 光环；锁定速率 ×1.5；机炮/导弹/热诱弹 reload 时间 ×0.7；0.5s 扫描 | [esm-pod](../specs/weapons/esm-pod.md) |
| `resources/x02_railgun.tres` | `RailgunEquipment` | 最大射程 7000m；自动充能/预测射击 | [zone-reward-arsenal](../specs/systems/zone-reward-arsenal.md) |
| `resources/x02_laser.tres` | `LaserEquipment` | 仅对空；飞机压向动态失速 90%；导弹每秒损失 35% 最大速度 | [zone-reward-arsenal](../specs/systems/zone-reward-arsenal.md) |
| `resources/a10_torpedo.tres` | 漂浮雷 | 加力窗口投 3；扫描 1500m；130m/60 伤害 | [zone-reward-arsenal](../specs/systems/zone-reward-arsenal.md) |
| `resources/a10_loyal_wingman.tres` | 忠诚僚机 | 独立 20s；存活上限 2；60m/30 伤害 | [zone-reward-arsenal](../specs/systems/zone-reward-arsenal.md) |

---

## 玩家主导弹默认挂载分档（2026-08-08，spec player-aircraft-power-curve §2.5）

| Tier | 默认 `max_count` | 允许例外 |
|---|---:|---|
| T1 | 2 | 无 |
| T2 | 2 | 无 |
| T3 | 3 | 无 |
| T4 | 3 | 无 |
| T5 | 4 | 仅 `category=range` 的远程导弹专精机可为 5；当前仅 X-21 |

> 43 份玩家机 profile/params 按此表验收。攻击机与其它非远程分类不得使用 5 发默认挂载；直接跨 Tier 进化边不得倒退。

---

## 热诱弹参数 —— 敌我两族（2026-07-23 解耦，spec player-aircraft-power-curve §2.6）

**敌用 `default_flare`**（玩家机不得引用；多数敌机还会被 spawner 强制压到 `max_flares=1`）

| 参数 | 值 |
|------|-----|
| 携带量 | 30 |
| 每次释放 | 2 枚 |
| 冷却 | 1.5s |
| 基础干扰率 | 55% |
| 侧/后方追来加成 | +20% |
| 大机动加成 | +15% |
| 极近距惩罚 | -35% |
| 低能量导弹加成 | +20% |
| 飞行员焦虑度 | 0.5 |

**玩家族 `resources/player/flare_t1~t5.tres`**（43 机按进化树 tier 引用）

| 参数 | 值 |
|------|-----|
| 携带量 | **T1=2 / T2=3 / T3=4 / T4=5 / T5=6**（分档唯一变量） |
| 每次释放 | 1 枚（"1 枚 = 1 次机会"记账） |
| 冷却 / 装填 | 1.5s / 12.0s（装填是否启用看 `PlayableAircraft.enable_flare_reload`） |
| 基础干扰率 | 90% |
| 侧/后方追来加成 | +30% |
| 大机动加成 | +25% |
| 极近距惩罚 | -15% |
| 低能量导弹加成 | +20% |
| 飞行员焦虑度 | 0.0（冷静型：等逼近才投） |

> 数量加成（策士 3 点里程碑 +1、预留档 +1 / `manual_dodge` +6）叠在**新机档位基数**之上；`flare_shield` 只提供清锁与锁定免疫，不增加载弹量。
> 换机后 `max_flares` 与 `flares_remaining` 同步 = 基数 + Σ加成。验收 bench `player_params`。
> 其它专用变体：`ace_flare`(4，命数语义) / `ace_support_flare`(2) / `f47_flare`(2) / `uav_mqx_flare`(1)。

---

## 战斗风格参数 (default_combat)

> 另有 AI 原型预设 `gladiator_combat` / `lancer_combat` / `ace_combat`，见
> [enemy-index.md](enemy-index.md) 的 AI 原型段。⚠ 原型名是**内部词汇**，不进玩家可见 UI。


| 分组 | 参数 | 值 |
|------|------|-----|
| 追踪 | intercept_range_mult | 2.5 |
| | intercept_lead_max | 8.0s |
| | closing_rate_threshold | 0.15 |
| | six_oclock_offset_ratio | 0.3 |
| 开火 | opportunity_cone_mult | 2.5 |
| | opportunity_range_mult | 0.4 |
| 机动 | combat_bank_aggression | 1.0 |
| | combat_full_bank_diff | 0.1 rad |
| 速度 | approach_speed_mult | 1.4 |
| | maneuver_speed_mult | 1.0 |
| | overshoot_speed_margin | 1.12 |
| 能量 | dive_speed_ratio | 0.85 |
| | climb_brake_overspeed | 1.15 |

---

## 地面单位参数总表

| 参数 | SAM | AAA | FLAK 空爆 | RADAR | 战略硬目标 |
|------|------|------|------|------|------|
| HP | 80 | 60 | 60 | 40 | 150 |
| 感知/武器范围 | 3000px | 2000px | 2500px（5km） | 10000px | 无 |
| 武器 | HQ-7×4 | ZU-23 | 450m/s 三连发定时空爆 | 无 | 无 |
| 特殊 | 圆形雷达 | 独立炮塔 | 220m/75 AOE + 组级误差 | 数据链共享 | 不可锁定，仅 bomber_bomb |
| 颜色 | 红 | 橙 | 蓝白 | 青 | 土黄 |
