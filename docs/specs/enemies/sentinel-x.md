---
id: sentinel-x
kind: enemy
status: approved
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [systems/tier-3-zone-global-threats, systems/early-game-uav-rework, bosses/mother-goose]
reconstruction_complete: true
---

# Sentinel X 三星空战高威胁指挥机

> 只在 3★空战任务出现的强化 Sentinel：以更大的指挥机本体和可持续补充的 MQ-109/MQ-110 猎手，把 Mother Goose 的无人机压迫感缩成可被普通战区承载的一件高威胁目标。

## 1. 设计意图（Why）

- **体验目标**：取代“3★空战只是再出现一架 DEADAIR”的旧方案。玩家即使暂时不处理该战区，也会不断看见从真实来源起飞、朝当前操控机赶来的猎手；优先击毁 Sentinel X 会立刻停止后续补充。
- **角色定位**：Mother Goose 的弱化/杂鱼版本，而不是新 BOSS。身份来自“更大的 Sentinel + 固有护卫 + 有上限的持续猎手”，不复制 BOSS 相位、30 机蜂群、MQ-111/112、指定猎杀波或专属胜利结算。
- **Litmus 自检**：符合设计哲学 1、3、7、8、11。150 HP 是明确的装甲例外并由更大体型与高威胁 TGT 身份解释；难度主要来自可见增援机制，不把普通敌机统一加血。
- **信息表达**：玩家从战术地图的 3★高威胁身份、真实 Sentinel X 本体和从其位置出发的猎手理解危险。禁止再叠加“全局威胁出现/解除”弹窗、顶部 warning banner 或临时 toast。
- **反模式规避**：不在 Sentinel X 死后凭空刷兵；不把可无限补充的猎手设为任务 TGT；不让猎手产出无限 XP；不瞬移到玩家身边；不为它复制 Mother Goose 控制器或高级无人机池。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 本体基础属性

| 字段 | 值 | 说明 |
|---|---:|---|
| type tag / display name | `sentinel_x` / `Sentinel X` | 与普通 `uav_commander / Sentinel` 区分；玩家可见名称固定为 Sentinel X |
| mission identity | 3★空战高威胁来源、正式 TGT | 不进入普通随机敌机池 |
| is_unmanned / no_pilot | `true / true` | 无线电沉默并免疫 FEAR |
| max_hp / armor | `150 / 0` | 固定值，不随玩家等级、热度或武器 tier 缩放 |
| max_speed / cruise_speed | `650 / 400 km/h` | 沿用普通 Sentinel 慢速支援平台基线 |
| stall_speed_base | `150 km/h` | 沿用普通 Sentinel |
| acceleration / deceleration | `20 / 30` | 沿用普通 Sentinel |
| g_drag_factor | `2.0` | 沿用普通 Sentinel |
| max_g / max_g_structural | `3.0 / 4.0` | 本体不进行战斗机动 |
| roll_rate | `1.2` | 沿用普通 Sentinel |
| pilot_stamina / drain / recovery | `100 / 50 / 10` | 无人机仍复用共享飞行字段 |
| max_altitude / climb_rate_max | `8000m / 80` | 沿用普通 Sentinel |
| thrust_to_weight / drag_coefficient | `0.45 / 0.035` | 沿用普通 Sentinel |
| afterburner_thrust_mult | `1.0` | 无加力逃生能力 |
| fuel_capacity / normal / ab rate | `800 / 0.8 / 0.8` | 正式局使用无限燃油，资源字段仍保持基线 |
| radar_range / half_angle / lock_time | `1200px / 20° / 99s` | 只供导航与共享显示，不进入有效攻击锁定 |
| gun / missile / rocket / flare | 无 | 本体不直接攻击，也没有额外命数 |
| combat flags | `enable_combat=false`、`attack_air_targets=false` | 本体只导航、维持指挥与补充机制 |
| callsign | `SENTINEL-X-<zone_id>` | 同一战区生命周期稳定 |
| icon color | 与普通 Sentinel 相同的敌对橙红色 | 不用颜色制造另一套阵营语义 |
| visual scale | 普通 Sentinel 的 **1.50×** | 只改变机体绘制、选择圈和标签避让；不放大雷达、武器或碰撞判定 |

### 2.2 固有护卫

| 项 | 值 | 说明 |
|---|---:|---|
| 初始编成 | `5× MQ-109 + 1× Aegis UAV` | 与普通 Sentinel 的完整固定编成一致 |
| 身份 | 驻守、非 TGT | 不参与战区完成判定 |
| Sentinel 光环 | 正常生效 | 固有护卫加入 Sentinel X 指挥小队并消费既有 CommanderAura |
| 战损补充 | **不补** | 持续补充只属于 §2.3 猎手池，不能把固有护卫也变成无限 XP 来源 |
| 击杀收益 | 沿用各自普通敌版 | 固有数量固定，因此不存在无限刷取 |

### 2.3 持续猎手

| 字段 | 值 | 说明 |
|---|---:|---|
| 首批延迟 | `4.0s` | 从 Sentinel X 正式生成开始计时 |
| 补充间隔 | `20.0s` | 固定可预测节拍；不随镜头、距离或击杀瞬间重置 |
| 每批组成 | `1× MQ-109 + 1× MQ-110` | 不随机偏科，玩家每批都能读到近战与导弹两种压力 |
| 同时存活上限 | `6` | 只统计该 Sentinel X 生成且仍存活的猎手 |
| 缺口补充 | 每个节拍最多补 `2` 架至上限 | 若只缺 1 架则只补 1；满员时跳过，不累计欠兵、不在未来瞬间补发 |
| 出生位置 | 以本体为圆心、半径 `250px` 的安全环 | 从真实来源出发；不得贴脸生成或传送到玩家附近 |
| 高度 | 与 Sentinel X 当前高度相同 | 生成后按各型号正常飞行能力追猎 |
| 型号参数 | 普通敌版 MQ-109 / MQ-110 | 不使用 Mother Goose 专属强化资源，不开放 MQ-111/112 |
| AI | simple hunter；MQ-110 继续使用其既有攻击跑 | 不绕 Sentinel X；生成时向当刻当前操控机下达初始追猎指令，之后按正常目标有效性重选 |
| 光环 | 不加入 Sentinel X 固有护卫小队 | 猎手离源出击，不额外叠加 CommanderAura 数值强化 |
| 身份 | 非 TGT、`no_kill_reward=true` | 不阻塞任务，也不给 XP、生涯击坠或其它击杀触发收益 |
| 远距清理 | 高威胁来源存活时视为来源拥有的关键猎手 | 不因普通画外冻结/清理在抵达前无声消失；仍服从全局性能 LOD |

### 2.4 战区与 UI 身份

- Sentinel X 本体是 3★空战任务新增的一个正式高威胁 TGT；普通空战 TGT 继续存在，必须全部清空才结算。
- 固有护卫和持续猎手都是非 TGT。玩家击毁 Sentinel X 后不必追杀无限补充链留下的单位才能完成任务。
- 战术地图与战区详情只稳定显示“3★ / 高威胁”身份、任务说明和真实目标；来源生成与解除均不弹出额外 UI。
- 禁止使用顶部红色 warning banner、全屏横幅、模态弹窗或“全局威胁已解除”临时 toast。普通战区被选择/触发时的既有任务开始提示可以保留，但不得再重复播一条“全局威胁”。

### 2.5 与普通支援机和内容曝光的边界

- DEADAIR 回到普通随机特殊支援包，不再担任 3★空战高威胁 profile；Snowblind 也保持自己的普通随机入口。
- DEADAIR 与 Snowblind **不互斥**：两者各自遵守同型实例上限、Token、冷却和阶段累计，抽中且预算合法时可以同场存在；范围效果各自独立结算，不做场合并或优先替换。
- 本 spec 不调整 DEADAIR、Snowblind 或其它特殊支援单位的全局权重、冷却与曝光排期。后续独立刷怪任务必须整体审计这些机制为何单局难遇，而不是在此局部拍一个概率。
- 后续曝光设计必须服从 20 小时 roadmap：特殊支援机制应在长线中持续提供首次刺激，不能长期稀有到玩家几乎遇不到；同时任何单局都不保证、也不应穷举全部特殊机制。需要以 `first_seen_run/hour`、单局重复数和连续空窗证据校准，而不是把所有权重一起抬高。

## 3. 行为与公式（How）

### 3.1 生命周期

| 状态 | 进入条件 | 行为 | 离开条件 |
|---|---|---|---|
| `DEPLOYING` | 3★空战 profile 创建 | 本体、5 MQ-109、1 Aegis 从战区边缘真实入场；4s 首批计时启动 | 创建完成同拍 → `PROJECTING` |
| `PROJECTING` | Sentinel X 存活且战区未终止 | 固有光环正常工作；按 4s 首批、之后 20s 节拍向当前玩家放出猎手 | 本体毁灭 → `NEUTRALIZED`；失败/取消/BOSS 清理 → `ENDED` |
| `NEUTRALIZED` | 本体毁灭 | 立即停止计时并清空待发批次；已放出的猎手解除来源强制追猎并向最近世界边缘 EGRESS；固有护卫走既有长机失效处理 | 全部正式 TGT 清空或战区终止 → `ENDED` |
| `ENDED` | 战区正常完成、失败、取消、reset 或 BOSS 转场 | 幂等停止生成；清掉控制器、来源引用、待发队列与残留强制指令 | 终态 |

### 3.2 补充规则

```text
每次补充节拍：
  alive = 该来源仍存活的持续猎手数
  slots = max(0, 6 - alive)
  spawn_count = min(2, slots)
  若 spawn_count == 0：跳过本节拍，不累计欠兵
  若 spawn_count == 1：补当前缺失较多的型号；数量相同则 MQ-109 / MQ-110 交替
  若 spawn_count == 2：固定生成 1 MQ-109 + 1 MQ-110
```

- 猎手被击落不会触发同拍补兵；最早只会在下一个固定节拍补充。
- 新一批读取当刻当前操控机作为初始指令目标；已经起飞的猎手不因玩家切控而瞬间转向或传送。
- Sentinel X 被击毁后绝不继续生成。已起飞猎手是可见实体，进入 EGRESS 而不是当场消失。

### 3.3 调度与性能

- 生成计时、存活清理与来源终止由战区已有低频生命周期调度维护，目标频率 `4Hz`；不为每个猎手增加补员扫描节点。
- 存活检查只遍历本来源最多 6 个猎手引用，并按 `Variant → TYPE_OBJECT → is_instance_valid` 清理跨帧对象。
- 每个节拍最多实例化 2 架，禁止一次补齐多轮欠兵；新增飞机继续消费既有 AI 拥挤度降频与画外 LOD。

## 4. 结构与组成（Structure）

- `Aircraft` Sentinel X 本体：固定参数、1.50× Sentinel 飞翼绘制、正式高威胁 TGT。
- `CommanderAura / CommanderOverlay`：只服务固定护卫小队；不复制第二套 aura。
- 战区低频猎手调度：拥有 4s/20s 计时、最多 6 个猎手引用、生成批次与终止/EGRESS 入口。
- 普通 MQ-109/MQ-110 资源和 AI：持续猎手直接复用，不建立 Sentinel X 专属武器参数。
- `ZoneMission`：持有 profile、来源和正式 TGT 生命周期；稳定高威胁标识由战区数据/UI读取，不发横幅。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 3★空战首次裁决为 Sentinel X，实际实体、Tab 任务说明和 F6/bench 读取同一个 profile；DEADAIR 不再被当作三级来源。
- [ ] Sentinel X 固定 150 HP、无武装、无 flare、1.50× 普通 Sentinel 可见尺寸，选择圈和标签不会切入机体。
- [ ] 初始编成严格为 Sentinel X + 5 MQ-109 + 1 Aegis；固有护卫战损后不补。
- [ ] 4s 后首批固定放出 MQ-109/MQ-110 各一架，之后每 20s 最多补 2，持续猎手存活数永不超过 6且不累计欠兵。
- [ ] 持续猎手从本体附近真实起飞并朝当前操控机进场；不贴脸生成，不使用 MQ-111/112 或 Mother Goose 专属强化资源。
- [ ] 持续猎手非 TGT且无击杀收益；反复击落不会刷 XP、生涯击坠、技能触发收益或阻塞任务完成。
- [ ] Sentinel X 被真实伤害击毁后同拍停止生成并清空队列；已出动猎手解除强制追猎后 EGRESS，本体死亡后的下一个补充节拍仍为零生成。
- [ ] 全部普通 TGT + Sentinel X 清空才完成任务；只杀本体不会提前结算，只剩非 TGT 无人机时也不会死锁。
- [ ] 3★来源生成和解除均不出现 warning banner、横幅、模态弹窗或临时 toast；战术地图/战区详情持续显示稳定高威胁身份即可。
- [ ] DEADAIR 与 Snowblind 可按各自普通随机入口同场生成，互不退休、替换或阻断；各自场效果与清理所有权独立。
- [ ] 生命周期覆盖成功、失败、取消、reset、BOSS 转场、场景退出、`queue_free()` 及后续至少一个 SceneTree 帧；无已释放本体/猎手引用。
- [ ] 性能负载：3★普通空战 TGT + Sentinel X 完整固有护卫 + 6 个持续猎手全部存活并实际交战；跑 C1 `Shadow Visual` 与 Sentinel X 专项，`frames_below_60 == 0`，记录成员/弹丸和同条件 baseline。
- [ ] i18n：Sentinel X 名称、战区任务说明与稳定高威胁标签三语完整；不再保留只服务已删除横幅的激活/解除文案。
- [ ] 文档：本 spec、三级总 spec、DEADAIR/Snowblind spec 与 `_INDEX` 对同场、UI 和任务完成语义一致。

### 5.1 证据记录

| 等级 | 场景 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 待实现 | 未执行 |
| E1 聚焦 Shadow | 待实现 | 未执行 |
| E2 集成 / 压力 Shadow | 待实现 | 未执行 |
| E3 Visual | 待实现 | 未执行 |
| E4 完整局 | 待实现；同时记录特殊支援首次曝光与单局重复 | 未执行 |

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — profile、本体与固定编成

- [ ] 把 3★空战 profile 从 DEADAIR 改为 Sentinel X，并让 UI/生成/F6/bench 共用缓存结果。
- [ ] 建固定 150 HP 参数与 1.50× Sentinel 绘制身份；接正式 TGT、CommanderAura 和固定 5+1 护卫。

### 阶段 2 — 低频猎手补充与终态

- [ ] 接 4s/20s、2 架/批、6 架上限、无欠兵的集中调度，复用普通 MQ-109/110。
- [ ] 接死亡、失败、取消、reset、BOSS、场景退出与猎手 EGRESS；补生命周期 gauntlet。

### 阶段 3 — UI、普通支援共存与验收

- [ ] 删除三级来源激活/解除的额外 banner/toast，只保留稳定高威胁战区身份与正常任务信息。
- [ ] 移除 DEADAIR/Snowblind 在场互斥门并补双场所有权、清理和压力回归；不在本任务调整总体刷新权重。
- [ ] 补 F6、focused、全量、Visual、C1/专项与完整局证据，同步 reference 索引。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 三级 profile / 来源生命周期 | `scripts/survivor/zone_mission.gd` |
| 生成与普通无人机复用 | `scripts/survivor/survivor_spawner.gd` |
| 本体参数 | `resources/enemy_sentinel_x.tres` |
| Sentinel 视觉与光环 | `scripts/aircraft_renderer.gd`、`scripts/survivor/commander_aura.gd`、`scripts/survivor/commander_overlay.gd` |
| 战区高威胁 UI | `scripts/survivor/survivor_mode.gd`、`scripts/survivor/tactical_map.gd` |
| 回归 | `scripts/tests/test_tier3_zone_threats.gd`、生命周期 gauntlet、Sentinel X Visual/压力 bench |
| reference 索引 | `docs/reference/enemy-index.md`、`docs/reference/script-index.md`、`docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-22 | 1 | 用户批准以 150 HP、1.50× 体型、普通 Sentinel 5 MQ-109 + 1 Aegis 固有编成和 4s 首批/20s 补充/6 猎手上限的 Sentinel X 取代三级空战 DEADAIR；猎手为无收益非 TGT。三级高威胁只做稳定战区身份，不弹出激活/解除横幅；DEADAIR 回普通随机且不再与 Snowblind 互斥。总体特殊支援刷新频率留给后续独立任务，并服从 20 小时新鲜度路线。 |
