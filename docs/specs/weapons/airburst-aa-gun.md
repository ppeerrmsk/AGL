---
id: airburst-aa-gun
kind: weapon
status: approved
schema_version: 1
spec_version: 4
owner: 用户 + Codex
depends_on: [aa-fire-awareness, battlefield-visual-scale]
reconstruction_complete: true
---

# 空爆高射炮（Airburst Flak AA）

> 一种“打出炮弹、等引信走完、在预计空域炸成一次 AOE”的高炮：它不追踪炮弹、也不保证贴脸爆炸，而是用一簇簇可见黑云把空域变成危险区。

## 1. 设计意图（Why）

- **体验目标**：玩家先看见曳光弹飞来，再看见远近不一的空爆团；威胁来自“下一片空域可能被覆盖”，而不是必中锁头。
- **牵制而非精准狙杀**：每组三发共享一次较大的测距误差，整组可能落空；命中 AOE 则遵循一击有意义，普通飞机承受 75 伤害。
- **与现有 ZU-23 区分**：ZU-23 是近距高射速直射弹幕；空爆炮是远距低频区域拒止。两者都自动开火。
- **Litmus 自检**：单次伤害 75；误差有可见空间结果；没有持续 DPS 云；不引入现实引信分类树；爆炸查询走空间网格。
- **反模式规避**：炮弹发射后不重新追踪目标；不每帧校正引信；不把 AOE 做成长期驻留伤害区；不让每发都保证在目标旁爆。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 单位参数

| 字段 | 值 | 说明 |
|---|---:|---|
| 单位 HP | 60 | 与现有 AAGunUnit 同级 |
| 雷达/感知半径 | 3000 px（6000m） | 360°，只用于选目标 |
| 目标重选间隔 | 0.5s | 最近敌对 Aircraft |
| 最小射程 | 800m | 近处交给 ZU-23/其它火力 |
| 最大射程 | 5000m | 形成远距火力区 |
| 炮塔转速 | 1.2 rad/s | 重型炮塔比 ZU-23 慢 |
| 开火对准门 | 18° | 象征性火力，不要求精确锁定 |
| 弹药 | 90 发 | 30 组三连发 |

### 2.2 炮弹与空爆参数

| 字段 | 值 | 说明 |
|---|---:|---|
| 炮口速度 | 450 m/s | 明显可见的飞行时间 |
| 每组炮弹 | 3 | 空爆簇 |
| 组内间隔 | 0.25s | 三发有连续节奏 |
| 组间冷却 | 4.0s | 低频威胁，不铺满全场 |
| AOE 半径 | 220m | 110px |
| AOE 伤害 | 75 | 半径内不衰减，只结算一次 |
| 可伤目标 | 敌对 Aircraft | 不伤地面、舰船、挂点、导弹 |
| 炮弹寿命上限 | 12s | 引信/出界兜底 |
| 爆炸云可见时间 | 1.2s | 纯视觉，无二次伤害 |

### 2.3 不完美引信/瞄准误差

每组三发先采样一次**共享误差**，再为每发叠加小误差：

| 误差 | 公式/值 | 作用 |
|---|---|---|
| 共享横向误差 | `uniform(-1,1) × min(500m, 220m + distance_m × 0.05, tan(7°) × predicted_distance_m)` | 整组偏到目标左右，但绝不呈现为随机朝远离预瞄空域开炮 |
| 共享引信误差 | `uniform(-0.35s, +0.35s)` | 整组沿弹道提前/延后爆 |
| 单发横向抖动 | `±min(60m, tan(1.5°) × solution_distance_m)` | 三朵云不完全重叠；与组级误差合计随机偏角 ≤8.5° |
| 单发引信抖动 | ±0.08s | 形成短纵深 |

样例：目标距 3000m → 共享横向误差上限 370m，大于 220m AOE 半径；因此不少炮组会完整落空，这正是“范围牵制而非完美贴炸”。

### 2.4 DDG 舰载型

| 字段 | 值 | 说明 |
|---|---:|---|
| 装载舰种 | DDG | 只接入驱逐舰，不扩散到 CV / CG / FFG / SS |
| 挂点替换 | 右舷 CIWS → 1 门 Flak | DDG 总挂点仍为 4：2×VLS + 1×CIWS + 1×Flak |
| 挂点 HP | 30 | 与被替换 CIWS 相同，不改变弱点预算 |
| 最小 / 最大射程 | 800m / 5000m | 与陆基型相同 |
| 目标捕获间隔 | 0.5s | 仅在无炮组且组冷却结束时扫描最近敌对 Aircraft |
| 炮组 | 3 发，间隔 0.25s | 与陆基型共用同一冻结火控解 |
| 组间冷却 | 6.0s | 舰载型专属；低于陆基型频率，避免两艘 DDG 铺满空域 |
| 炮弹 / AOE / 误差 | 完全复用 §2.2–§2.3 | 450m/s、220m/75、7°/1.5° 偏角上限 |
| 弹药 | 不耗尽 | 舰船其它挂点同样不做局内弹药库存 |
| 导弹拦截 | 无 | 被替换 CIWS 的拦截能力真实消失，不允许 Flak 误伤 Missile |

## 3. 行为与公式（How）

### 3.1 开火解

```text
time_nominal = distance_to_target / muzzle_speed
predicted_pos = target_pos + target_velocity × time_nominal
shared_error_cap = tan(7°) × distance(gun_pos, predicted_pos)
burst_aim_pos = predicted_pos + lateral_axis × clamp(shared_lateral_error, ±shared_error_cap)
fuse_time = clamp(time_nominal + shared_fuse_error + shell_fuse_jitter, 1.0, 12.0)
shell_jitter_cap = tan(1.5°) × distance(gun_pos, burst_aim_pos)
shell_heading = bearing(gun_pos, burst_aim_pos + clamp(per_shell_lateral_jitter, ±shell_jitter_cap))
```

发射瞬间冻结 `shell_heading` 和 `fuse_time`。之后即使目标转弯、加速、悬停或被击落，炮弹都不再修正。

### 3.2 状态机

| 状态 | 行为 | 转移 |
|---|---|---|
| `SEARCH` | 0.5s 选一次 800–5000m 内最近敌对 Aircraft | 有目标 → `TRACK` |
| `TRACK` | 炮塔朝预测点转动 | 对准 ≤18° 且冷却完 → `BURST` |
| `BURST` | 用同一共享误差依次发 3 枚 | 第三枚后 → `COOLDOWN` |
| `COOLDOWN` | 4.0s，不开火但继续转炮塔 | 到时 → `SEARCH` |

### 3.3 炮弹与爆炸

- 炮弹在 BulletManager 的独立 `_airburst_shells` 数组中做 O(1) 直线更新；不进入普通 bullet 命中热路径。
- 引信到时无条件在当前位置爆炸；不是近炸触发，也不会因掠过目标提前爆。
- 爆炸只在当帧查询 220m 邻域，按阵营过滤 Aircraft；一个单位同一爆炸最多结算一次。
- AOE 命中时写 `kind="airburst"`，触发爆炸 VFX、音效、EventLogger 和正常击杀归因。
- 视觉不是向外扩散的蓝色同心圆：爆炸当刻显示白橙爆心与放射碎线，随后留下不规则黑灰烟团；220m AOE 只用 0.22s 断续橙色危险圈提示一次。
- 炮弹飞出世界安全边界 500px 后静默回收，不在地图外生成爆炸云。

### 3.4 DDG 舰载状态机

```text
READY ──每 0.5s 捕获最近 800–5000m 敌机──> BURST
BURST ──冻结一份 §3.1 解，立即发首弹，再以 0.25s 发余下两弹──> COOLDOWN
COOLDOWN ──6.0s 从炮组开始时计时──> READY
```

- 舰载挂点没有独立追踪节点；全向炮座在捕获时直接冻结预瞄解，舰体后续转向不改变已出膛炮弹。
- `JAM`、演出期 `combat_disabled`、挂点击毁均阻断开火；已经出膛的炮弹继续按原引信结算。
- 同一 DDG 的剩余 CIWS 继续负责导弹拦截与近距扫射；Flak 不参与 CIWS 的导弹独占目标分配。

## 4. 结构与组成（Structure）

- `AirburstAAUnit extends AAGunUnit`：独立炮塔、选目标、三连发状态机，并保有空爆参数常量。
- `GunParams`：承载 UI/公共防空射程和弹药库字段；空爆专属误差、引信和 AOE 数值由单位脚本常量承载。
- `BulletManager`：独立空爆炮弹数组、集中更新、空间网格 AOE 查询、批量绘制。
- `NavalWeapons` + `WeaponMount`：舰载 Flak 复用同一火控采样函数与 BulletManager 管线；挂点只保存炮组剩余数、组内计时、冻结解和 burst id。
- 场景与资源：空爆炮拥有与 ZU-23 可区分的大口径长炮管/四脚底座轮廓。
- 生成接入：作为地面驻防池中的独立类型和 debug 入口；是否进入各战区数量表由本 spec 批准后在实现阶段按现有驻防预算接线，不替换所有 ZU-23。

### 4.1 默认布置预算

- 普通地面战区：至多 1 门空爆炮；与 1 个现有 AA 槽互斥替换，不额外增加总 TGT 数。
- 机场解放前敌军驻防：三星机场的 2 门 AA 中，最多 1 门替换为空爆炮；一、二星不出现。
- 友军解放后防空：默认仍用 ZU-23，不免费获得空爆炮。
- DDG：右舷 CIWS 原位替换为 Flak；不新增第五挂点。该配置对使用同一 `destroyer_ddg` 参数的敌方 DDG 生效。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 炮弹从炮口可见飞行，1–12s 后才在当前位置转为空爆；不是发射当帧直接画圆。
- [x] 3000m 匀速横穿目标的统计射击中，必须同时出现“整组落空”和“至少一发覆盖目标”，不能全部贴身爆；所有炮弹相对冻结预瞄方位的随机偏角 ≤8.6°。
- [ ] 目标在发射后急转/悬停，炮弹继续沿旧解飞行并在旧引信时刻爆炸。
- [ ] AOE 只伤敌对 Aircraft；同阵营飞机、GroundUnit、NavalUnit、Missile 均不受伤。
- [ ] 半径内普通 75HP 飞机一次爆炸即死；半径外 1px 不受伤，无持续云伤害。
- [ ] 普通战区最多一门且替换现有 AA 槽，总 TGT/Token 压力不膨胀。
- [x] DDG 资源固定为 2×VLS + 1×CIWS + 1×Flak；总挂点仍为 4，Flak HP=30。
- [x] 舰载 Flak 首弹立即、后两弹间隔 0.25s，炮组起始后 6.0s 内不得开始下一组。
- [x] 舰载 Flak 只伤敌对 Aircraft、不拦导弹；剩余单座 CIWS 仍可独立拦截来袭导弹。
- [ ] 无头测试覆盖误差共享、引信冻结、阵营/类型过滤、边界回收；加入 `--bench=all`。
- [ ] 性能：目标选择 2Hz；炮弹 O(shells)；爆炸用 UnitGrid；Sentinel + Lv5+ 不低于 60 FPS。
- [ ] i18n：单位名/任务文本三语齐全；EventLogger 可用英文内部标签。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 参数与炮弹
- [x] 新增单位专属空爆参数；BulletManager 独立空爆数组、引信和 AOE。
- [x] 集中绘制炮弹/空爆火光、断续危险圈和烟团，接入音效与安全归因。

### 阶段 2 — 地面单位
- [x] 新增 AirburstAAUnit 状态机、场景、资源和图标。
- [x] 接入普通战区和三星机场的地面驻防预算替换。

### 阶段 3 — 回归与压测
- [x] 新增 airburst AA 专项 bench，覆盖引信数据契约、AOE 尺寸与组射 ID。
- [ ] Godot 4.7 实机观察 10 组散布与压力帧率。

### 阶段 4 — DDG 舰载化
- [x] 新增 `NAVAL_FLAK` 挂点类型和舰载炮组状态，复用地面版火控采样与空爆管线。
- [x] 右舷 CIWS 资源原位替换为 Flak，补舰体符号与 hover 射程圈。
- [x] 扩展专项 bench，覆盖 DDG 挂点构成、首组实弹、6s 冷却与不拦导弹契约。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 单位逻辑/空爆参数 | `scripts/airburst_aa_unit.gd` |
| 公共火炮参数 | `resources/airburst_aa_gun.tres` |
| 炮弹与 AOE | `scripts/bullet_manager.gd` |
| 场景/单位参数 | `scenes/airburst_aa_unit.tscn` · `resources/airburst_aa_params.tres` |
| DDG 舰载挂点 | `scripts/naval/naval_weapons.gd` · `scripts/naval/weapon_mount.gd` · `resources/naval/destroyer_ddg.tres` |
| 回归 | `scripts/tests/test_bomber_rotor_airburst.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-01 | 1 | 初稿：5000m 远距三连发空爆炮；450m/s、220m/75 AOE、组级横向/引信误差，强调范围牵制而非必中。 |
| 2026-08-01 | 2 | 实现冻结预测解、共享误差三连发、定时空爆和只伤敌对 Aircraft 的单次 AOE；普通战区/三星机场按预算替换现有 AA 槽；专项 bench 已通过。 |
| 2026-08-03 | 3 | 按实机反馈修正表现：共享/单发随机偏角分别封顶 7°/1.5°，保证炮弹明显朝冻结预瞄空域飞；蓝色同心水波改为白橙放射爆心、短暂断续危险圈与黑灰烟团；专项 bench 增加 240 组实际弹道命中率审计。 |
| 2026-08-04 | 4 | 用户批准并完成 DDG 舰载化：右舷 CIWS 原位替换为一门 Flak，总挂点保持 4；弹道/AOE/误差复用陆基型，舰载组间冷却 6s，且明确失去该 CIWS 的导弹拦截能力；专项 bench 22/22。 |
