class_name LoyalWingmanParams
extends Resource

## 忠诚僚机无人机参数（A-10 实验武器）
##
## 现实灵感：Skyborg / MQ-28 Ghost Bat / Kratos XQ-58 等"忠诚僚机"概念——
## 自主无人机伴飞主机，按需出击攻击或防御。
##
## 设计语义：
##   - 与漂浮雷（params.torpedo）共享同一武器槽位（设计上互斥，只填一个）
##   - 规避模式（evasion_mode=true）下持续倒数 cooldown，归零自动从机尾释放
##   - 释放出的 drone 是真正的 Aircraft 实例 + AIController（不是子弹 / 不是导弹）
##   - drone 在玩家身边轨道飞行（orbit_squad_leader）
##   - 玩家有 combat_target 时，drone 突进追击 + 类机炮"激光"点射
##   - 玩家无 combat_target 时，drone 拦截瞄向玩家的来袭导弹（kamikaze 自爆）
##   - 同源同屏上限 2 架（cap）；释放 cap 阻断防止"减 CD 升级"导致数量爆炸
##
## 性能设计：drone 用 simple_ai + ai_tick_divisor=3（20Hz AI），
## 不走 BFM / TacticalPlanner / SQUAD_FOLLOW 重路径。详见
## docs/changelogs/2026-05-04-loyal-wingman.md 的性能分析段。

@export_group("基本")
@export var display_name: String = "Loyal Wingman"

@export_group("投放")
## 释放冷却（秒，规避模式下持续倒数）
@export var cooldown: float = 8.0
## 离屏后多久消失（秒）— **不是固定寿命**：drone 在玩家视野内**永久存在**，
## 只有连续离屏超过此值才静默 queue_free。设 0 = 永不离屏消失（只靠击坠/自爆死亡）
@export var offscreen_despawn_seconds: float = 8.0
## 同源同屏上限（玩家方激进 build 也不应超过此值，cap 在 spawn 入口阻断）
@export var max_simultaneous: int = 2

@export_group("无人机机体")
## drone 的 AircraftParams（机体物理 + 武器配置）
## 实施时 spawn 路径会 duplicate(true)，运行时改不污染原 .tres
@export var drone_aircraft_params: AircraftParams

@export_group("自爆拦截")
## kamikaze 触发距离（米，drone 与来袭导弹距离 ≤ 此值即同归于尽）
@export var kamikaze_range_m: float = 80.0
## 自爆 AOE 半径（米，给临近敌机/导弹"沾点光"，主要语义还是撞导弹保命）
@export var kamikaze_aoe_radius_m: float = 60.0
## 自爆 AOE 伤害
@export var kamikaze_aoe_damage: float = 30.0
