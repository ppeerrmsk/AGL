# 2026-05-09 — 导弹发射纪律 missile_skill 参数

## 起因

玩家在 dogfight 中常感到自己导弹"乱射、追不上"——射击窗口检查只看 bank/roll/off-axis 是否稳定，**不看目标的预测前置点是否仍在导弹包络内**。结果在边缘 max_range + 高侧速 / 高 G 对头场景下，导弹一出筒就要做大幅 PN 修正，烧光能量丢锁。

用户进一步要求把这套"发射纪律"做成**可调参数**，不同等级敌人可配不同纪律：杂兵乱射、王牌精准。

## 改动

### 1) 新增 `CombatParams.missile_skill` (0..1) + `missile_skill_jitter`

[scripts/combat_params.gd](../../scripts/combat_params.gd) — 影响三道发射门槛：
- 发射窗口稳定（bank / roll-rate / off-axis）阈值按 skill 双线性插值（LOOSE↔TIGHT）
- 前置点偏角（off-axis-to-lead）按 skill 收紧
- **前置点包络检查始终生效**——这是物理上的废弹判定，与 skill 无关

每次发射判定时摇一次 `randf_range(-jitter, +jitter)`，避免行为机械。

### 2) `aircraft_weapons.gd` 接线

- 删 `_should_apply_launch_quality(ac) -> bool`（玩家/AI 二分硬开关）
- 新 `_missile_skill(ac) -> float`（无 missile loadout / 无 combat 资源 → 返回 0）
- `_has_stable_launch_window` 阈值参数化，签名加 `skill: float`
- 新 `_has_lead_intercept_solution(ac, target, msl, skill) -> [pass, tti, detail]`
- 单发路径 `update_missile` + 齐射路径 `_fire_multi_lock_salvo` 都加双门槛

### 3) `aircraft_combat_tracking.gd` 抽出 `envelope_pass_at(ac, point, tgt_heading, tgt_alt, msl)`

原 `is_in_missile_envelope(ac, target, msl)` 改为薄壳，行为完全等价。lead 检查复用同一套包络几何（max_range × alt_factor / TAA / min_range / 高度差）。

### 4) 各类 CombatParams 的数值

| .tres | missile_skill | jitter | 适用 |
|---|---|---|---|
| `playable_f16_combat.tres` / `playable_f14_combat.tres` | 0.85 | 0.10 | 玩家主角机 |
| `ace_combat.tres` | 0.85 | 0.10 | F-47 王牌中队等 BOSS 级 |
| `lancer_combat.tres` | 0.65 | 0.15 | 打带跑骑士型 |
| `default_combat.tres` | 0.55 | 0.20 | 通用敌战斗机 / Mother Goose |
| `gladiator_combat.tres` | 0.45 | 0.20 | 缠斗近战型（F-86 等） |

CombatParams 脚本默认 `missile_skill = 0.4` / `jitter = 0.15`——给未来新加 .tres 一个不极端的兜底。

## 不参与本系统的对象

- 没有 `params.missile` 的飞机（纯机炮/UAV 撞击/纯激光等）—— 根本走不进 `update_missile`
- 地面 SAM (`sam_unit.gd`) / Mother Goose VLS (`mother_goose_controller.gd`) / 舰艇 (`naval_weapons.gd`) —— 走自有发射路径，不进 `aircraft_weapons.update_missile`

## 验证

- 玩家 F-16 默认 build：边缘 max_range + 横切目标会出 `LEAD_GEOM` 阻断；尾追稳定追击行为不变
- F5 刷 F-86（skill=0.45）vs F-47（skill=0.85），导弹命中率应有可观差异
- F9 dump combat log 搜 `LEAD_GEOM` / `UNSTABLE_WIN`，skill 值在日志可读
- 回归对照：mother_goose / F-47 战中玩家齐射不应被卡死；BOSS VLS 仍按其自有路径发射

## 2026-05-09 补丁：lead 门槛收紧 + 导弹初始朝向指向前置点

第一版上线后用户反馈"导弹打的还像中间，没看到前置量"。日志确认 `_missile_skill` 与 `_has_lead_intercept_solution` 都在跑，但：

1. **门槛过松**：SARH 在 skill=0.85 时实际允许 17° off-axis-to-lead，玩家肉眼看不出"在拉前置"。
   - 改 `LEAD_OFFAX_RATIO_SARH_TIGHT` 0.50 → **0.30**（≈9° 内才发）
   - 改 `LEAD_OFFAX_RATIO_FAF_TIGHT` 0.70 → **0.55**（≈16.5° 内才发）

2. **导弹出筒朝向是发射器机头**，前 0.5s `guidance_delay` 内笔直飞 → 视觉上"奔着当前目标去"再拐弯。
   - [missile_manager.gd] `spawn_missile` 飞机分支改为调用新 `_compute_lead_launch_heading(source, target, msl)`：两轮迭代算前置点 → 把 `initial_heading` 设为指向前置点（clamp 到机头 ±60° 防爆角）。
   - 与新门槛配合：上层只在玩家机头基本对准前置点时才允许发射，导弹再以前置朝向出筒，全程几何对称——视觉上导弹直接朝命中位置飞。


- skill 接入升级表（"导弹发射"系熟练度技能）
- skill 受 PilotPersonality 压力 / SA 削弱
- 同套路做 `gun_skill`
