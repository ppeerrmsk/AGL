# 武器发射与命中结算重构

> 状态：第一阶段完成（2026-08-27）
>
> 性质：既有行为等价重构；不新增武器、机制或数值，不替代 `docs/specs/` 的设计权威。

## 目标

把“选武器 → 发射 → 弹体飞行 → 建立命中 → 伤害/归因 → 弹体终态”拆成职责清楚的边界，避免每种武器重复实现攻击者清洗、目标类型分派、舰船倍率和导弹回收。

## 权威边界

- `AircraftWeapons`：飞机武器许可、单发/齐射提交、弹药、冷却与 reload。
- `BulletManager` / `MissileManager`：弹体生成、轨迹、碰撞、距离/天气规则、爆炸与命中特效。
- `WeaponHitResolver`：无状态命中资格、跨帧 source 清洗、击杀归因、Aircraft/Ground/Naval/通用目标伤害入口分派。
- `Missile`：`intercept_hp` 与被 CIWS/激光/电磁炮拦截后的生命周期。
- 各目标类：护甲、闪避、软目标一击必杀、舰船部件/弱点、BOSS damage router 等目标自身规则。

## 已完成

- 机炮、火箭、空爆、导弹直击、导弹 AOE、电磁炮与激光伤害共用 `WeaponHitResolver`。
- 保留火箭对舰 `0.5×`、机炮对舰 `0.15×`、地面软目标战斗部一击必杀、气氛 TGT 非致死与 Aircraft 机炮闪避语义。
- 单枚主弹、副弹与多锁齐射共用 `_emit_missile`；一轮 cooldown/crank/reload 由 `_finish_main_missile_cycle` 统一提交。
- CIWS、激光、电磁炮不再直接拼装导弹回收状态，改走 `Missile.take_intercept_damage` / `destroy_from_intercept`。
- 新增 `weapon_hit` focused bench，锁住命中拒绝、已释放 source、归因、地面/舰船/飞机分派。

## 扩展约束

- 新武器不得在调用点复制 `if target is Aircraft/GroundUnit/NavalUnit` 伤害树；先给 resolver 增加明确且可测试的策略参数。
- 碰撞前的武器特有 miss roll、轨迹、距离衰减和 VFX 不进入 resolver。
- 新的导弹拦截方式不得直接写 `intercept_hp/is_active/queue_free`。
- resolver 保持无状态，不在逐弹热路径构造请求对象或扫描全场。

## 回归门

- focused：`weapon_hit`、`weapon`、`weapon_doctrine`、`bullet_grid`、`missile_grid`、`rocket_trajectory`、`ciws_intercept`、`zone_atmosphere`、`boss_progression`。
- 终态：`bench\\run.cmd all 1 300 Shadow Headless`（包含 `lifecycle_gauntlet`）。
- 静态：`verify_player_ref_holders.py`、`verify_doc_anchors.py`、`verify_docs.ps1`、`git diff --check`。
