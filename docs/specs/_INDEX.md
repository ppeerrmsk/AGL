# Specs Index —— 设计单一数据源（SSOT）总表

`docs/specs/` 是 AGL 的**设计权威源**。每个机制 / 敌人 / 武器 / 技能 / BOSS / 系统都有一份 spec，
完整写下**数值 + 行为 + 公式**，使得"代码全丢、只看 specs 也能一比一重建游戏"。

## 与其它文档的分工（硬约定）

| 层 | 回答 | 权威性 | 行号 |
|---|---|---|---|
| **`docs/specs/`**（本层） | 做什么 + 为什么 + **全部数值/公式/行为** | ✅ 权威源 | ❌ 禁止 |
| `docs/reference/`（enemy-index / script-index / code-index） | 代码**在哪** | 易腐烂的指针 | ✅ 这里放 |
| `docs/systems/` | 跨系统的架构叙述 / 流程 | 叙述，非数值权威 | 少量 |
| `docs/changelogs/` | 某次改动**当时**做了什么 | 历史快照 | 可有 |

迁移方向（进行中）：**把设计意图与数值从 enemy-index / systems 抽进 specs；索引退化为纯指针表。**
新内容一律 **spec 优先**（先写 spec → 定稿 → 按 §6 实现计划派生代码）。

**UI 继承约定**：所有主界面、HUD、游戏内面板及 UI 视觉/交互设计默认继承 [systems/ui-design-guidelines](systems/ui-design-guidelines.md) 的稳定通用规则。普通 UI 实现、视觉和排版调整默认不回写该规范，也不要求为差异另写 spec；仅当用户明确要求写入规范或确立通用规则时才更新。不得建立第二份并行 UI 通用规范。

## 工作流（doc → task pipeline）

```
设计  ── 复制 _TEMPLATE.md → 填 §1~§5 → status: draft → review → approved
执行  ── 按 §6 实现计划逐条打勾，代码从 spec 派生（执行 cheap）
收尾  ── 跑 §5 验收 → 更新 §7 锚点 + 同步 reference 索引 → 写 §8 变更记录 → status: done
```

**重建测试**：每份 spec 的 `reconstruction_complete` 字段，标记它是否已能脱离代码重建。
目标是全表为 ✅。

## 当前阶段：内容铺量

模板验证与核心垂直切片已经完成。当前生产顺序、WIP 上限、证据等级、地图七件套与发布完成线统一看
[content-production-workflow](../planning/content-production-workflow.md)。旧 roadmap 和 evolution vertical slice
只作历史记录，不再从那里派生任务。

铺量目标是至少约 20 小时持续出现新机体、技能、BOSS、功能和战场刺激；当前 43 机 / 167 技能 / 4 组
BOSS 都是生产基线，不是封顶。扩充必须回到时间曲线、地图身份或明确玩法空位，不能只追数量。音画、机体/地图细节、特效、
提示与 Build 变强反馈统一走 [音画生产工作流](../planning/audio-visual-production-workflow.md)。

状态只表达生命周期，不代替证据：`in-progress` 仅用于正在实现或缺 spec 明定的必需验收门；
“以后还可以调数值”不能让条目永久停在进行中。focused Shadow、集成 Shadow、Visual 与完整局证据
必须分别记录，不能互相冒充。

性能验收统一以 [performance-guidelines](../reference/performance-guidelines.md) 为当前权威。旧 spec 中尚未执行的
“Sentinel + Lv5 / 掉幅 <15”通用句式一律迁移解释为 C1 混合全可见战场 + 与成本形状匹配的专项剖面；
Sentinel 只在功能确实涉及其光环、护卫或 LOD 豁免时保留。历史已经执行的测量数字不反向改写。

## 状态图例

`draft` 起草中 · `approved` 设计定稿待实现 · `in-progress` 实现中 · `done` 已落地并验收 · `superseded` 被取代

---

## 总表

| Spec | kind | status | 重建完整 | 覆盖范围 |
|---|---|---|---|---|
| [systems/offscreen-world-simulation](systems/offscreen-world-simulation.md) | system | done | ✅ | **未关注战区最简模拟 + P0**：普通 1★/2★ AVAILABLE 战区只保留战略数据，玩家选择或进入后才一次性生成真实单位并保持到终态；3★全局威胁继续公开即投射。攻克后幸存驻守敌机物理撤离，连续离屏 2 秒后分批释放。玩家 360 步预测线移出 `_draw`，限制单帧推进并以 4:1 抽样显示。 |
| [systems/flare-evasion-coupling](systems/flare-evasion-coupling.md) | system | done | ✅ | **热诱弹与敌机规避耦合**：敌我十枚视觉改为 0.90s 六波双侧抛射并延长粒子寿命；玩家自动投焰收紧到 TTI≤1.0s / 200m 兜底；敌机投焰后进入 1.25s 可命中 break 窗，只有真实转向/横移/增速/高度变化达门且通过 AI 等级概率才令导弹失导。玩家主动规避不变。 |
| [skills/counter-stealth](skills/counter-stealth.md) | skill | done | ✅ | **反隐身 / 捉鬼者**：稳定策士全队技能将隐形目标侦测距离扩到 120%，并让完整锁定任一队员的隐形敌机现形；先进斗士全队技能保持当前 `combat_target` 暴露，击杀隐形单位令全队永久最大生命 +10，晚入队与换机补齐。两者均可压过 Wraith 光学 cloak，条件解除后原周期恢复。 |
| [systems/runtime-validation-workflow](systems/runtime-validation-workflow.md) | system | done | ✅ | **自动运行时验证工作流**：所有 bench 统一静音 Master，并把 GDScript 红错与 freed-object 诊断改判为失败；`all` 在同步断言后自动进入真实 SceneTree 生命周期 gauntlet，覆盖击杀、任务完成/失败/取消、传感器目标缓存与释放后缓存 tick。错误门自检可把 Godot 退出 0 改判为 86，并保留完整 GDScript backtrace、输出 freed-object 生命周期归因。 |
| [systems/enemy-sensor-stealth](systems/enemy-sensor-stealth.md) | system | done | ✅ | **敌机传感器隐形**：F-22/F-35/Su-57/J-20/YF-23 与 F-47/Wraith 启用；玩家小队雷达需持续照射，处于全部玩家机 1000px 外失联 5.0s 后 0.5s 渐隐，近距立即揭露。隐身只影响玩家可见性/火控接触，绝不改变敌机 AI、物理、机动或武器频率。同向渐变命令幂等，完全隐形非任务目标停止无效 redraw；逐机 Canvas/AC_TICK 错峰，EventLogger O(1) 过期。专项 63/63、Visual idempotent=true；FINAL WAR、C1、C2 各三次 Visual 均 `<60=0`。 |
| [systems/aircraft-top-view-silhouettes](systems/aircraft-top-view-silhouettes.md) | system | done | ✅ | **飞机顶视轮廓资产 v8**：40 张 128×128 alpha PNG 逐架从可靠顶视/正投影或用户批准定型参考直接提取；同型号共享一图并运行时换色。滚转使用不增加纹理提交的“暗色壳层 + 顶面/机腹”体积投影，90° 正侧面不再归零；未批准原创/概念机保留旧绘制并复用不归零投影。 |
| [systems/map-2-3-preview](systems/map-2-3-preview.md) | map | in-progress | ✗ | **图 2 / 图 3 PNG 可飞行地图预览**：60×60 km 沙漠铁路与海洋群岛两份内置 MapDocument；共享 lossless WebP 候选已接入真实试飞，主图/Tab 精确映射各自 manifest，默认仍保留 8704² PNG 供 A/B 与回滚。空图仍只生成玩家和地图，关闭战区、任务、敌机、BOSS 与开局驻防。 |
| [systems/three-map-campaign-continuity](systems/three-map-campaign-continuity.md) | system | draft | ✗ | **三图战役串联与双队会师**：港湾→沙漠→海洋决战；A/B 两支不同初始队伍分别在前两图形成独立 build，第三图二选一主力、另一队按自身 build 支援。未遭遇 BOSS 逐图顺延，但 Mother Goose 固定第一图、Black Star 固定最终 BOSS；沙漠 BOSS/敌人/任务与海洋决战任务均显式待定，火车只作为关卡机制候选。本轮仅搭设计骨架，不实装。 |
| [systems/ui-design-guidelines](systems/ui-design-guidelines.md) | system | done | ✗ | **UI 设计规范**：所有主界面、HUD、游戏内面板及 UI 视觉/交互的稳定默认基线；统一军用终端网格、连续标题行、空框、分高度数字框、共享描边、字体、颜色、刷新与交互规则。世界单位状态栏共用屏幕空间矢量面板，不随单位/父节点/镜头转动或缩放；新增单位首行统一使用 locale-independent 英文战术名/型号，并按统一迟滞档位在近景显示详情。屏幕底部固定保留全宽 `3u` 常驻框板并容纳三轴与经验条；顶部紧急信息和底部临时提示使用独立滑入通知栏。具体玩家仪表布局仅作实现快照，普通 UI 修改不自动回写；F7 专用缩放默认 `0.9×`，其它 UI 保持 `1.0×`。 |
| [systems/presentation-foundation-rework](systems/presentation-foundation-rework.md) | system | draft | ✗ | **表现层底层逻辑改造确认稿**：持续汇总本轮讨论中由用户明确确认的主要改动；区分待讨论、已确认、已实现，记录旧/新行为、影响、风险、退化策略与验收标准，并以既有 `ui-transition` 为依赖。 |
| [skills/fire-control-saturation](skills/fire-control-saturation.md) | skill | done | ✅ | **火控饱和**：实验级骑士轴王牌技能；当前王牌同时满锁至少 5 个目标时获得基础 6s 超载，超载实际存续期间锁定目标数 +2；20s 内置 CD 且需先跌破五锁再重新跨线。 |
| [skills/displacement-roll](skills/displacement-roll.md) | skill | done | ✅ | **位移滚转**：实验级 R 主动技能；1.15s 内确定性选择安全侧并横移 450px，15s 玩家小队共享冷却；动作本体不可命中、保留锁定与在飞武器；并入五向 R 互斥槽，当前操控机手动、AI 僚机自动。 |
| [skills/vertical-break](skills/vertical-break.md) | skill | done | ✅ | **垂直越过**：实验级 R 主动技能；LOW 拉升/MID·HIGH 俯冲 900m/1.30s，18s 玩家小队共享冷却；额外能量交换封顶 −18%/+15%，并入五向 R 互斥槽，当前操控机手动、AI 僚机自动。 |
| [systems/altitude-action-states](systems/altitude-action-states.md) | system | done | ✅ | **高度动作状态与威胁响应**：统一 CLIMB/DIVE 与 GUN_TAILED 真源；进入 CLIMB 开启一次 4.0 秒反制窗口，旧解梭射真实打空、迫近导弹确定性失导，攻击者只按真实相对运动自然飞过。 |
| [skills/altitude-energy-cycle](skills/altitude-energy-cycle.md) | skill | done | ✅ | **高度能量循环**：实验级单层；DIVE 以 25 发/s 回复本机机炮至 2 倍弹仓，CLIMB 以 0.2/s 回复共享加力且只认当前操控机。 |
| [systems/active-special-maneuvers](systems/active-special-maneuvers.md) | system | done | ✅ | **主动特殊机动共享契约**：五种 R 技能统一双向互斥且玩家只持有一个；当前操控机按 R、AI 僚机按威胁自动释放；共享冷却、最新命令队列、切控续播、统一不可命中查询；玩家仪表取得后常驻并只显示 0%→100% 可用度。 |
| [systems/status-build-completion](systems/status-build-completion.md) | balance | done | ✅ | **状态词条构筑聚焦与终端保底**：保留三轴各一卡，已选主词条相关卡按 `1+0.75×sqrt(min(A,4))` 加权、无关卡降至 ×0.85/×0.70/×0.65；终端首轮 ×2、次轮 ×4、第三次合格事件强制出示但不自动授予。同步六项新技能、词条闭合、稀有度调整与 BLOODLUST 基础机炮零耗弹。 |
| [skills/flee](skills/flee.md) | skill | done | ✅ | **逃离**：实验级全队唯一；新 FEAR 40% 令普通载人敌机真实撤退并正常结算一次 XP；无人机、ACE、BOSS 与 BOSS 生成物豁免。 |
| [skills/invasion-algorithm](skills/invasion-algorithm.md) | skill | done | ✅ | **入侵算法**：实验级全队唯一；玩家小队 JAM 使 MQ-109～112 立即坠毁并正常结算一次 XP。 |
| [skills/hunter](skills/hunter.md) | skill | done | ✅ | **猎手**：机密级全队技能；突击目标存活期间 +2G、加减速 ×1.2、G 能量损失 ×0.7、承伤 ×0.7，目标结束即关闭。 |
| [skills/heavy-gun](skills/heavy-gun.md) | skill | done | ✅ | **重型机炮**：次世代全队技能；机炮射程 +1000m，斗士 +1。 |
| [skills/gunship-mode](skills/gunship-mode.md) | skill | done | ✅ | **炮艇模式**：次世代全队技能；射程内玩家点名（含挂点代理）优先，否则当前机与 AI 僚机各自以 360° 独立扫描最近敌机/地面单位并整梭跟踪；显示完整射程圈，最大速度 -40%，斗士 +1。 |
| [weapons/esm-pod](weapons/esm-pod.md) | weapon | done | ✅ | **ESM 吊舱**：3000m 数据链光环；锁定速率 ×1.5，机炮/导弹/热诱弹装填时间 ×0.7；2Hz 共享列表扫描；F4/F6 可直接测试。 |
| [systems/dynamic-faction-conversion](systems/dynamic-faction-conversion.md) | system | done | ✅ | **动态阵营转换**：统一原子清理 IFF/目标/锁定/旧小队/奖励/在飞武器；WhiteTea 仅余一机时投降转 ALLY、本人喊话后被动离场并按王牌击破结算；策士“黑客光束”与“激光致命输出”双向互斥，持续 2.5s 可黑入 MQ-109/110，转为绿色不可控 ALLY并跟随当前长机战斗至被击毁。 |
| [systems/flight-model-realism](systems/flight-model-realism.md) | system | in-progress | ✗ | **双层 G + 能量自限**：结构 G 提供短暂瞬时机动，额外能量流失把飞机拉回持续 G；角点速度作为硬地板，禁止转弯把自己拖入失速死循环。代码与加载验证已完成，待手感验收和结构耗能调参。 |
| [systems/bomber-strike-missions](systems/bomber-strike-missions.md) | system | in-progress | ✅ | **阵营对称轰炸任务**：友军 B-1B / 敌军 Tu-160 共用指定航路 `INGRESS→LINE_UP→RELEASE→EGRESS`；每机 5 枚、0.22s 间隔，3.2s 下落，160m/75 伤害；战略硬目标仅接受其 `bomber_bomb` 通道。已实现，待实机 QA。 |
| [systems/strategic-hardened-targets](systems/strategic-hardened-targets.md) | system | in-progress | ✅ | **战略硬目标**：地堡、仓库、导弹井不可被战斗机锁定或常规武器伤害；150 HP，仅接受敌对轰炸机炸弹伤害，为护航/截击任务提供专属目标。已实现，待实机 QA。 |
| [systems/rotorcraft-combat](systems/rotorcraft-combat.md) | system | in-progress | ✅ | **旋翼机独立飞行/战斗模型**：平面速度与机头解耦；AH-64 在 500m 环以 180km/h 切向平移，7–11s 环绕后刹停悬停 3.5–6s，再恢复环绕；M230 40 伤害短点射。正式地面气氛层已复用同一 AH-64 生成 `ALLY/HOSTILE` 双阵营非 TGT/Token 演员，只攻击 GroundUnit，弹丸再次拒绝 Aircraft；敌对实例保留现有 50 XP 玩家归因。 |
| [systems/battlefield-atmosphere-experiment](systems/battlefield-atmosphere-experiment.md) | system | in-progress | ✅ | **真实生存局海陆空气氛实验 + 当前性能核心负载**：F5 分为空战、炮战和海战；远距持续开火/保留弹道，玩家进入 3km 才恢复 10% AI 实伤。36 名/8 km 混合全可见场为 C1 通用 draw 门，48 名/24 km 为 C2 多战线/LOD 门；Sentinel 不再承担通用性能权威。 |
| [systems/runtime-performance-budget](systems/runtime-performance-budget.md) | system | draft | ✗ | **运行时性能预算重构**：以一次 typed 工作量快照替代重复场景树扫描与 30 FPS 动态减员；AI、雷达、LOD/尾迹按各自成本域预算，FPS 只诊断，不得停刷或削减真实战斗内容。Phase 0 已完成飞机缓存复用与 C1 A/B，待用户确认设计后实现快照和刷怪解耦。 |
| [systems/zone-atmosphere-combat](systems/zone-atmosphere-combat.md) | system | done | ✅ | **正式战区氛围战斗**：普通地图约 30%，决战地图全覆盖；陆战双阵营 SPG 加四种等权 AH-64 构图，海战只补友军。气氛直升机只与 GroundUnit 交战、不是 TGT/Token，玩家击毁敌对实例沿用 50 XP，对正式 TGT 非致死；SPG 近距可信直击/画外零伤害保持。 |
| [systems/tier-3-zone-global-threats](systems/tier-3-zone-global-threats.md) | system | approved | ✅ | **三级战区全局威胁与超级单位**：唯一 3★名额；AURORA LANCE 使用固定圆形基盘与独立旋转桁架炮架，危险带缩为 360m 全宽并改为 4.0s 渐宽 + 1.5s 满宽闪烁后发射；攻城坦克和远程 VLS 已落地。空战批准改为 150 HP / 1.50× 的 Sentinel X，固定 5 MQ-109 + 1 Aegis，并以 4s 首批、20s/批、6 猎手上限持续放出普通 MQ-109/110。来源被毁只解除威胁，仍须清空其它 TGT。UI 只稳定显示高威胁身份，不再弹出激活/解除横幅；空战替换与回归待实现。 |
| [systems/bomber-escort-zone](systems/bomber-escort-zone.md) | system | done | ✅ | **可选战区任务：轰炸机护送**：正式局 150s+Lv5 后先广播、6 秒后生成；整局保底 1 次、20% 第 2 次且最多 2。七线等时、场外 3×30 HP B-1B + 2×F-4E；敌方按局势混编，轰炸编队先飞完 6% 航程后才从实时航迹后方同向追击，32% 航程前只接近/锁定，40% 无人介入才补一次后方追击增援，最迟 58% 中止；无线电只作军事态势包装，成功只给特殊 XP，FAILED 无痕。 |
| [weapons/airburst-aa-gun](weapons/airburst-aa-gun.md) | weapon | approved | ✅ | **远距空爆高炮**：450m/s 三连发、220m/75 AOE、组/单发偏角封顶 7°/1.5°；爆点为白橙火光 + 黑灰烟团。陆基战区限一门；DDG 右舷 CIWS 已原位替换为 Flak（2VLS+1CIWS+1Flak，舰载冷却 6s），专项 bench 22/22，待实机视觉 QA。 |
| [systems/battlefield-visual-scale](systems/battlefield-visual-scale.md) | system | in-progress | ✅ | **飞机/舰船统一视觉尺度**：普通飞机用 `7.9×m^0.55` 压缩幂律保可读，高度倍率从旧 0.55–1.70 收敛为 0.85–1.20；CV/CG/DDG/FFG/SS 回到 0.5px/m 世界比例并重算挂点，航母 420→166.4px。已实现，待舰队 bench 与视觉 QA。 |
| [systems/aircraft-destruction-presentation](systems/aircraft-destruction-presentation.md) | system | done | ✅ | **飞机击毁、体型分级与受击部位演出**：普通飞机/无人机/导弹的命中与终点只用单方框，大型有人机才允许五点结构连续解体；所有爆炸都禁止与模型同帧消失绑定，终点爆炸后机体继续运动并保留 0.85s；最后命中点分为机头、尾段/发动机、左右翼与中心，并配合不污染玩法 RNG 的局部随机改变旋转、侧翻、减速与下坠。生命周期、全量、Visual 与 C1 严格 60 FPS 门通过。 |
| [systems/enemy-pool-expansion](systems/enemy-pool-expansion.md) | balance | in-progress | ✗ | **玩家科技树敌机化 + 常规敌机池扩充**：覆盖 T1–T3 共 27 架；每机互斥归为 Gladiator/Lancer/Schemer，五角色池 + 最近三队防重复。独立敌版参数、Token 四档审计、轮廓家族、图鉴/i18n/debug/无线电与专用多锁均已落地；F-22 可1–3机、每机四锁，本体取 Su-35 普通敌机基线。70/70 数据回归通过；9 友机 + 17 指定扩池敌机压力样本为 146 FPS，待人工逐机 playtest。 |
| [systems/squad-xp-threat-balance](systems/squad-xp-threat-balance.md) | balance | in-progress | ✗ | **编队经验稀释 + 敌方警戒响应**：共享 XP 乘区 `2/(N+1)`；热度地板 `min(100,min(75,5L)+6(N-1))`；每僚机 +3 Token 响应、减员即时降 6 热度、敌方目标分散到直属小队。敌方后续出击规模按玩家 N 软倾向：单机玩家约 60% 遇单机，九机玩家约 60% 遇 3–4机队，每批再乘 0.85–1.15 乱数，绝不确定性镜像。公共规则已接线，Tab 表现与规模 bench 待完成。 |
| [systems/classified-card-pity](systems/classified-card-pity.md) | balance | done | ✅ | **4 级金色技能递增概率**：自然三轴三卡连续未见 `CLASSIFIED` 时，下轮金卡候选倍率按 `1 + 3.5×未出次数` 递增；普通三卡见金即清零，机场专属技能与奖励升级完全不参与。静态池标定 LV18 六轮期望约 2.00 次、LV21 七轮约 2.37 次；`attr_gates` 覆盖倍率/累计/清零/渠道隔离。 |
| [systems/zone-air-support-naval-safety](systems/zone-air-support-naval-safety.md) | system | done | ✅ | **战区友军空中支援 + 对舰水域硬闸**：F-86/A-10 两项权益分别只响应每局首次合资格战区；绿色标签只移除 ALLY，机型名称后缀缩首字母、呼号完整保留；对舰为 1★ 4 FFG、2★ 2 DDG+3 FFG、3★ 1 CG+2 DDG+3 FFG，全舰 TGT 并继续执行 40px 全水硬闸。 |
| [systems/boss-clear-progression](systems/boss-clear-progression.md) | system | done | ✅ | **按各 BOSS 历史击败次数切换编成/机制**：初见为教学层；首败后 Wraith 接战在队形后方追加 2 架启用传感器隐形、接触建立后正常可锁定的 YF-23 可选狙击支援，LADON 航母由 0CG+2DDG+6FFG 强化到 2CG+2DDG+8FFG，Mother Goose 解锁 MQ-111/112；MQ-111 激光保留减速并累计消耗导弹拦截 HP，过热循环与玩家 X-02 完全一致。历史次数 ≥2 暂沿用强化层 1。 |
| [systems/friendly-asset-aggro](systems/friendly-asset-aggro.md) | system | done | ✅ | **玩家触发的友方据点牵连交战**：已解放机场 2000px / 友军航母 2500px 内由当前操控机激活，退出圈 +500px 持续 8s 才解除；只从 6000px 内敌机按 `H<2→0 / 否则 min(3,max(1,floor(H/3)))` 限额分流，主 BOSS/队长/事件指令不拆，新增目标来源 `SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED`。机场打 SAM+AA，航母打 CIWS 挂点→弱点；友军航母专属 300 hull，敌方航母 BOSS 保持 1200。用户裁定四 CIWS 可全数压住 5/8 枚正向齐射，符合航母 BOSS 身份；真实弹道审计 14/14。 |
| [systems/doctrine-unlocks](systems/doctrine-unlocks.md) | system | done | ✗ | **战术学说解锁 + 槽位配件系统退役**（2026-07-27 用户拍板，07-28 落地）：整个"买配件加属性"的机库层下架——12 件数值件（机炮/导弹/雷达/电战 T1-T3）、`EquipmentPart` 资源类、槽位预算、随机货架、付费刷新、出击前机库场景（选机→直接出击）、`LoadoutLedger` autoload 全部删除；只留 **6 张 doctrine 词条解锁件**并搬进主菜单生涯商店（降级为 MetaShop 常量表，不再用 `.tres`；legacy loadout.cfg 一次性迁移，数值件按 D2 不退款丢弃）。局外成长收敛为单杠杆——**只买"这局能抽到什么牌"，不买"这局直接强多少"**。门控权威表：6 词覆盖当前技能表中的 **45 条**（stealth 11 / jam 9 / overload 8 / fear 7 / bloodlust 7 / chivalry 5，双词技 AND 语义；v3 playtest 修复：`headon_xp` 720 批漏标家族词 `chivalry` 无证进池，补标后骑士 700→800、全买 6500——**对头技双词惯例：head_on=触发词不门控，家族词才门控**）；渐进上架（嗜血+骑士买齐才放进阶 4 张）；定价 `100×门控技能数+300`（草案）。修复两处：①**战区奖励 NEXT_GEN 池补门控**（`evasion_stealth` / `fear_on_lock` 此前可无证获得）②**9 条 `sig_*` 签名技豁免二次门控**（保"每机一条专属"承诺）。**--bench=meta_shop 47 断言 + 回归门 40 项 PASS，差 playtest 定价校准** |
| [systems/career-shop](systems/career-shop.md) | system | in-progress | ✅ | **八卡选机与生涯商店**：保留既有四卡及门控，新增四架各 1000 功勋采购 T0；F-86/A-10/F-15 空中支援、机场 SAM 与机体战术适配继续按独立永久授权运作。 |
| [systems/career-archive](systems/career-archive.md) | system | done | ✅ | **玩家生涯档案**：跨局持久记录分机型击坠、BOSS 接战 / 击败、通关 / 阵亡 / 撤退 / 停机；bench 与 boss_debug 零写入。**BOSS 档案轮换**按 Wraith→CSG→Mother Goose→Black Star 四项环绕，击败必换、未击败 50% 推进，CSG 水域过滤后顺延。**敌人图鉴**覆盖常规空中 / Adds / 地面 / 王牌 / 4 BOSS，统一“击败即解锁”，Black Star 已有三语名称 / 简介与计数入口；图鉴 id、真实注册表、五表译文双向审计。**游戏信息手册**复用 Tab 小技巧 SSOT。成就样板 `uav_hunter` 仍为 UAV 族累计 30 击坠解锁忠诚僚机奖励。`career_archive` 当前 `62/62` 通过。 |
| [systems/airfield-liberation-zones](systems/airfield-liberation-zones.md) | system | done | ✗ | **机场解放战区**：羽田/木更津/調布 三机场开局＝敌占战区（固定地标，独立于随机 A–G）。地面 1 SAM+2 AA＝TGT，打光即解放；升空迎战规模按**当前热度**定档（heat<34→1★/<67→2★/≥67→3★，读 `_roe.heat`）。解放奖励＝机场本身：圆心开**一次性**友军补给点（降落=回血/进化/僚机）+ 解放即刻**渐进**刷出 ALLY 防空伞（每 4s 一个，不 dock 门控）。**不碰 BOSS**（BOSS 早为纯时间闸 600s，ZoneData 旧"打够 3 次解锁"注释作废）。附带修 Tab 奖励块死路径（新奖励字典无 desc/category → 恒显"生存"死词，改按 kind 渲染）+ 去飞行员耐力废提示。**数据层单测 22/22 + 回归门 37/37 PASS，差 §5 playtest** |
| [systems/circle-cut-entry](systems/circle-cut-entry.md) | system | draft | ✗ | 圈外切入 CIRCLE_CUT（第三方支援射击几何，**敌我同享**）：队友被咬进转弯圈时，第三方不再汇入圆凑车轮战 —— 解目标转弯圆（复用 lag_pursuit 公式）→ 站位圆外 1.8R/领先相位 105° → **弧上前置解**横穿射击（局部修复"前置解无转弯率项"）；触发=目标的目标是我队友且 bank>40°×1.5s，滞回 40°/25° + 2s 再入冷却；友方僚机反咬与 Wraith PRESS 收网共用。**待 review** |
| [systems/boss-hunter-doctrine](systems/boss-hunter-doctrine.md) | system | done | ✅ | **BOSS 猎手准则 v6**：废除 `ANCHOR_HOLD`，ENGAGED 后持续追玩家；出生点位于玩家机头前方 12km，BOSS 圈跟存活成员质心。飞机类 BOSS 采用**双层世界边缘收容**：`AceSquad` 2000px 软返场 + `SurvivorSpawner` 40px 触线前物理硬护栏，绝不进入边界外黑区；仅守世界外框、不是锚点 leash。实际投焰后只允许最长 1.25s 的局部 break，不恢复常态自保规避。**2026-07-29 用户统一接战时机**：全部 BOSS 在 spawn 后立刻走表演导演 `<boss_id>_arrival`，镜头回玩家后立即 ENGAGED；旧进圈/贴近/被锁/受伤 T1~T4 退出主流程，缺序列 fail-open 直接接战。CSG 猎手性由最多 8 架舰载机承担；Mother Goose 巡逻环跟随玩家。附带 `BossEncounter.set_player_ref()` 活引用契约与 CSG 水面摆位/承伤规范。 |
| [bosses/wraith-squadron](bosses/wraith-squadron.md) | boss | done | ✗ | WRAITH 中队（F-47）战术规格，depends_on ace-squadron-tier。目标=**本作最强敌人之一，强度来自四机协同的两难而非数值**：KNIGHT×2 逼你转弯 / SNIPER×2 惩罚你转弯。光学 cloak 开战后首次与每次结束后均严格等待 60s，可重复且无紧急提前触发；渐变 1s，当前玩家 1000px 内禁止/打断。传感器隐形近距揭露、左下雷达匿名提示，隐身中拒绝 `combat_target` 重挂。`boss_hunter` 127/127；追加 Wraith 压力三次 worst 63.70/70.48/82.28、below60 全 0。 |
| [bosses/poltergeist-squadron](bosses/poltergeist-squadron.md) | boss | done | ✅ | POLTERGEIST 中队（CSG 二阶段 F-14）队级战术。由 playtest log 20260724_004256 驱动（母舰弹射的 F-14 陷入共速绕圈死锁：KNIGHT 全程 0 开火、绕圈 ~60s、机头钉 ±90°、飘出战场）。根因=`PoltergeistSquad` 有 `EngagementSpeedGovernor`（修速度几何）但**缺队级战术逃生层**。**Poltergeist 专属解法**（不抄 Wraith 全队 RESET，因性格相反=誓死不退）：**死锁单机换手（Relay Break）**——机头偏角 >55° 持续 4s、距玩家 ≤4000m → 只把**最咬不住的 1 架**拽去爬升 HIGH + 背离拉开 2200m 重整 3.5s、其余继续压；**同时换手上限=1**（灵魂：绝不两架一起变慢变傻）。独立模块 `poltergeist_tactics.gd`，走 AceSquad `_tactics_*` 钩子。**2026-08-01 出界回归**：继承 AceSquad 世界边缘收容，不恢复锚点归巢。**--bench=poltergeist_tactics 9 断言 PASS，差 §5 playtest** |
| [bosses/mother-goose](bosses/mother-goose.md) | boss | done | ✅ | Mother Goose 飞行翼母舰：10 挂点 + 弱点、JAM 力场、指定猎杀、UAV 蜂群；VLS 在 3000m 内停火、飞行 8000m 后形成 800m AOE；MQ-111 可真实反导；半血 MQ-X 精英对使用三发点射+强化导弹+过热反导激光+F-22 级传感器隐形，以 joust 攻击跑取代近距离绕圈；登场先播系统入侵身份横幅再切母机镜头 |
| [bosses/hypersonic-splitter](bosses/hypersonic-splitter.md) | boss | done | ✅ | **Black Star / Hyper-A 高超音速分裂体 BOSS**：两架根机先后以 4 秒 `30,000m→5,500m` 状态栏 / AOE 预警再入，各自三次二分 `1→2→4→8`，整场 30 节点、16 个 G3。G0/G1/G2/G3 为 `400/200/100/70 HP`、`8/4/2/1` 锁、全代 4 发导弹弹匣且 0 flare；每棵树总 HP `1760`。四代导弹齐射独立于主武器模式，G0 独有 360° 全向锁定与离轴齐射，G1 恢复普通前向规则。G0 分裂出的 G1 首次生成先隐藏下降、撞击后显形；后续 G1/G2 再入放缓至每 `40–50s`，爬升后独立等待 `7–10s` 才俯冲，高空序列期间其它分裂体暂停倒数并至少再错峰 `12s`。G0/G1 冲刺左右各 5 火箭，G2 冲刺无火箭，G3 机炮狗斗无冲刺。G0–G2 的急刹扇区只在线满后显示，终点以同源预警 / 判定释放 `900m / 110° / 45` 冲击波，随后靠近当前操控机并自施标准 `SLOW 6s`。树 HUD、统一身份演出、十个 Debug 直达与专项验证链已落地；`FINAL WAR // OCEAN` 额外提供双 T5 满配玩家队、常规友军 / 敌军与 2v2 舰队的真实可减员海洋决战沙盒；全部节点及最终胜利 0 XP。 |
| [enemies/snowblind](enemies/snowblind.md) | enemy | in-progress | ✗ | **SNOWBLIND「雪幕」纯支援 Schemer**：Sentinel 固定基线、无武器/flare/等级缩放；携 2 架当前响应等级动态护卫。4000m 单 mesh 实体风雪层在圆心显示不可交互本体轮廓；4500m/2s 复隐滞回与跨边界双向停火已落地。批准与 DEADAIR 同场独立运行，待移除互斥门、Tab 表现、坍塌演出与人工 playtest。 |
| [enemies/deadair](enemies/deadair.md) | enemy | in-progress | ✗ | **DEADAIR「断讯」累积 JAM 支援 Schemer**：3000m 移动场；友方单位 8s 累积后持续 JAM，制导导弹按 4× 在 2s 失导；HP55 无武装核心 + 2 动态护卫，鼓励玩家压入一次机炮攻击跑。批准与 Snowblind 同场独立运行并回归普通随机支援，待移除互斥门。总体特殊支援曝光频率另立任务校准。 |
| [enemies/sentinel-x](enemies/sentinel-x.md) | enemy | approved | ✅ | **Sentinel X 三星空战高威胁指挥机**：固定 150 HP、普通 Sentinel 1.50× 体型、5 MQ-109 + 1 Aegis 固有护卫；4s 首批、每 20s 最多补 1 MQ-109 + 1 MQ-110，持续猎手上限 6且为无收益非 TGT。来源毁灭立即停补并令猎手 EGRESS；只显示稳定高威胁战区身份，不弹横幅。 |
| [enemies/f-22](enemies/f-22.md) | enemy | in-progress | ✅ | F-22 四锁狙击 Schemer：1–3机，每机4锁，队级目标去重，12s EGRESS。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-15](enemies/f-15.md) | enemy | in-progress | ✗ | F-15 常规 Gladiator，2–3机持续能量缠斗。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-14](enemies/f-14.md) | enemy | in-progress | ✗ | F-14 常规 Lancer，固定双机迎头攻击后脱离。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/a-6e](enemies/a-6e.md) | enemy | in-progress | ✗ | A-6E 低空重载 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/mirage-iii](enemies/mirage-iii.md) | enemy | in-progress | ✗ | Mirage III 三角翼高速截击 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/mirage-2000](enemies/mirage-2000.md) | enemy | in-progress | ✗ | Mirage 2000 常规 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/fa-18e](enemies/fa-18e.md) | enemy | in-progress | ✗ | F/A-18E 高迎角 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-16](enemies/f-16.md) | enemy | in-progress | ✗ | F-16 轻型多机 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/a-10](enemies/a-10.md) | enemy | in-progress | ✗ | A-10 低空机炮 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-15c](enemies/f-15c.md) | enemy | in-progress | ✗ | F-15C 高能 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-15e](enemies/f-15e.md) | enemy | in-progress | ✗ | F-15E 重载 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/gripen-c](enemies/gripen-c.md) | enemy | in-progress | ✗ | Gripen C 队级三目标 Schemer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/rafale](enemies/rafale.md) | enemy | in-progress | ✗ | Rafale 单机双目标 Schemer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/tornado](enemies/tornado.md) | enemy | in-progress | ✗ | Tornado 低空突防 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/typhoon](enemies/typhoon.md) | enemy | in-progress | ✗ | Typhoon 高能 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/su-34](enemies/su-34.md) | enemy | in-progress | ✗ | Su-34 重击 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/viggen](enemies/viggen.md) | enemy | in-progress | ✗ | Viggen 低空截击 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/harrier](enemies/harrier.md) | enemy | in-progress | ✗ | Harrier 高鼻向 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-15smtd](enemies/f-15smtd.md) | enemy | in-progress | ✗ | F-15 S/MTD 后失速 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-35](enemies/f-35.md) | enemy | in-progress | ✗ | F-35 双目标 Schemer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/gripen-e](enemies/gripen-e.md) | enemy | in-progress | ✗ | Gripen E 队级三目标 Schemer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/su-57](enemies/su-57.md) | enemy | in-progress | ✗ | Su-57 后失速 Gladiator。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/j-20](enemies/j-20.md) | enemy | in-progress | ✗ | J-20 远距 Lancer。 参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/a-12](enemies/a-12.md) | enemy | in-progress | ✗ | A-12 窄锥单目标远距 Schemer。参数资源/池/审计已落地，待人工 playtest。 |
| [enemies/f-4e](enemies/f-4e.md) | enemy | done | ✅ | F-4E 前期导弹杂鱼（有人机，2026-07-26 用户）：Lv1 起单机 35%/2-3 机小队，只带导弹无机炮，HP 45 一发死；定位="第一种有人敌机"，与 MQ-109/MQ-110 无人机杂鱼混编（v2：不顶替任何生态位），与 Lv6 的 F-4 Phantom（导弹卡车）共存分档。**代码落地，差 playtest** |
| [enemies/af-03](enemies/af-03.md) | enemy | done | ✅ | AF-03 电磁炮狙击无人机（Schemer）：railgun AT_FIRE_TIME 预测狙击 + BVR 5-8km 打带跑。**v2（2026-07-28）出场率整治**：解锁 8→7 / 每级 0.05→0.06 / 上限 0.18→0.26 + **新进战区池**（权重 0.5，unlock 7/peak 10/不淘汰），实例上限仍 1；高度档改**偏高空**（取射界）；§3.2 补电磁炮对舰**按母舰归并、一发一舰只结算一次**。理由=旧配置实测整局遇不到一次 |
| [skills/close-range-lock](skills/close-range-lock.md) | skill | done | ✅ | **近距捕获**：先进级斗士全队技能；主雷达锁定速率随距离线性加快，雷达边缘 ×1、半程 ×1.5、贴身最高 ×2；合并“副武器”，机炮装填期发射导弹不耗弹。 |
| [skills/bloodlust](skills/bloodlust.md) | skill | done | ✅ | BLOODLUST 嗜血家族：击杀/受伤触发 8s buff，基础回血 + 血怒护甲修饰卡（减伤/拉G/加速，经 SEAM-001 注入） |
| [skills/berserk-virus](skills/berserk-virus.md) | skill | done | ✅ | **狂化病毒**：实验级斗士普通池全队技能；僚机不可主动接管并锁定 FREE，仍服从其它命令；常驻机动与 weapon/flare CD 强化，击杀进入标准 BLOODLUST。 |
| [systems/airfield-sam-network](systems/airfield-sam-network.md) | system | in-progress | ✅ | **机场防空网授权**：从局内技能池移除，改为生涯商店“战场支援”页 3000 功勋永久商品；购入后每局每座解放机场在基础 AA×2 后追加一次性 SAM×1，战损不重生；差 Godot 定向回归。 |
| [weapons/qmaam](weapons/qmaam.md) | weapon | done | ✅ | QMAAM 副武器槽近距格斗弹：宽锁定锥 70° + HOBS + 60G 发射后不管，自动补刀狗斗侧面目标；副槽机制完整 |
| [weapons/gun-burst-fire](weapons/gun-burst-fire.md) | weapon | done | ✅ | 飞机机炮改梭射：burst_count=10/梭，梭内 3.3× 密度；友方平均射速守恒；所有敌方 Aircraft 一次机会只打一梭、末发后停火 3.0s，堵连续多梭秒杀；--bench=gun_burst 20/20 |
| [weapons/rocket-ripple-trajectory](weapons/rocket-ripple-trajectory.md) | weapon | done | ✅ | 敌我飞机火箭改为左右挂点逐发交替：每枚出膛地速=资源初速+发射机当帧前向速度；先平行直飞 180m，再于 320m 内 smoothstep 展开到原散布半角。伤害、引信、射程与最终扇面不变。 |
| [systems/survivor-loop](systems/survivor-loop.md) | system | done | ✗ | 生存模式核心循环：10 分钟战区→BOSS 阶段、Token 经济、加权刷怪、XP/升级、出界时间税；★含扩展接入图。v7 将净时间轴、阶段关闭事务、王牌固定槽/无放回与 ORION 门收口到 BattlefieldFlow，并统一新局/退局 static reset；玩法数值不变。 |
| [systems/first-run-tutorial](systems/first-run-tutorial.md) | system | in-progress | ✅ | 新存档基础教程补 **E 加力用途/禁攻代价** 与 **双击敌机突击**；首次拥有僚机时按实际固定号机提示数字键接管，只有成功切到另一架飞机才永久消失。代码与静态回归落地，差三语实机视觉验收。 |
| [aircraft/a-10](aircraft/a-10.md) | aircraft | done | ✅ | A-10 Warthog：T2 厚甲机炮平台，默认只有底线机炮/导弹/热诱弹，**不自带火箭**；Hydra 70 仅能从战区奖励取得。旧基础/实验变体与战区支援 A-10 同样零火箭。 |
| [aircraft/mig-21f-13](aircraft/mig-21f-13.md) | aircraft | done | ✅ | T0 斗士起手；低雷达、高机炮基线；专属槽仅占位。 |
| [aircraft/f-104c](aircraft/f-104c.md) | aircraft | done | ✅ | T0 骑士高速起手；2200 km/h 极端直线速度、72 HP 低耐久；专属槽仅占位。 |
| [aircraft/j-35f](aircraft/j-35f.md) | aircraft | done | ✅ | T0 宽锥截击起手；三角翼机动；专属槽仅占位。 |
| [aircraft/ea-6b](aircraft/ea-6b.md) | aircraft | done | ✅ | T0 策士支援起手；速度对齐 A-6E、雷达带内最高；专属槽仅占位。 |
| [aircraft/mig-23](aircraft/mig-23.md) | aircraft | done | ✅ | LV4 低位 T1 斗士；可变后掠翼中间层；专属槽仅占位。 |
| [aircraft/f-4e](aircraft/f-4e.md) | aircraft | done | ✅ | LV4 低位 T1 骑士；机炮/导弹通用平台；专属槽仅占位。 |
| [aircraft/jaguar-gr1a](aircraft/jaguar-gr1a.md) | aircraft | done | ✅ | LV4 低位 T1 策士攻击机；低空、机炮与低失速；专属槽仅占位。 |
| [systems/event-system](systems/event-system.md) | system | done | ✅ | 剧本系统：GameEvent + EventDirector + AIDirective（6 verb）；BOSS 事件三相；★含扩展接入图。**v4（2026-08-20）ADBS 城区直升机**：每窗 25% 概率、整局最多 2 次且禁止并存；从距玩家 ≥12km、距边界 ≥8km 的全图城区生成，玩家从战术地图主动寻找；护卫反应 / 受击散开 / 全歼 3 架 → 作战时间 +20s 保持不变。 |
| [systems/map-system](systems/map-system.md) | map | done | ✗ | 地图系统：边界 + 手画地理 + OSM 烘焙 + 底图三层；含港池水面排除与 50px 连续陆地净空的正式地面部署 API；★含加新地图接入图 |
| [systems/raster-basemap-streaming](systems/raster-basemap-streaming.md) | map | done | ✅ | **三地图正式分级栅格底图**：东京湾/沙漠/海洋按 `tile_map_key` 直接消费 Strategic + Operational + Detail lossless WebP；主图 12 张 LRU、Tab 复用 Strategic、0.40s LOD 淡变与 `0.014` 世界颗粒保持。用户已确认瓦片版，五张旧/正式地图 PNG、`Shift+F8` A/B 和切换对拍 Debug 页已退役；正式资源缺失走父层/矢量 fallback，外部 UGC 自带 PNG 兼容保留。当前性能毕业仍按 C1 + S3 代表性负载复核。 |
| [skills/buff_duration_rebalance](skills/buff_duration_rebalance.md) | balance | done | ✗ | 自身 buff 时长统一拉到 8s（INVUL/OVERLOAD/FRENZY）；回顾型记录，未达到完整重建级别。 |
| [systems/squad-control-switching](systems/squad-control-switching.md) | system | done | ✗ | 操控切换：数字键 1–9 接管稳定 `squad_slot` + set_leader 换帅 + manual_control 休眠 AI + 打完再归队 + 白底/击落接管。**代码全落地，差 §5 playtest** |
| [systems/squad-cohesion](systems/squad-cohesion.md) | system | in-progress | ✗ | 小队凝聚学说（友+敌）：焦点开火（地/船/BOSS 饱和、飞机留自由机互掩）+ 维持阵型 + 防游走 leash + GUARD_REAR 守后 + 敌方成建制/随机阵型。**阶段 1-4 主体落地，差联调/调参/§5** |
| [systems/squad-ai-escort](systems/squad-ai-escort.md) | system | draft | ✗ | 僚机护卫：反杀咬长机者（engaging_me 定向扩展）+ 近长机评分加权。**仅阶段 1-2；守后半球由 squad-cohesion GUARD_REAR 覆盖，escort 自身阶段 3-5 未做** |
| [systems/battlefield-gravity](systems/battlefield-gravity.md) | system | done | ✗ | **战场引力——友军目标优先级三带**：由 log 20260724_222238（①僚机放弃包抄回编队）+ 20260724_222827（②BOSS 战跑去打 10~17km 外低慢直升机）驱动。核心=目标评分补一个"以当前主战场为中心"的空间锚，统一两病根。三带（加在可命中性 base 上，严格隔离）：①生存 `+100×threat01`（候选正在咬**当前操控机**，只对空）②任务 `+40`（BossEncounter 成员表实例判定 / 最近 triggered 战区，单槽 BOSS 优先）③顺手 `base×gravity_mult`（离锚 2000→6000px 衰减到 0.1）。引力锚=BOSS 存活质心/战区 center/兜底操控机，**隐形也可读**故 cloak 窗不破功。v2 复审三件套：**`ENGAGE_MIN_SCORE=0.15` 交战地板**（无地板则 argmax 仍选唯一远杂鱼，引力形同虚设）+ **leash 可行性门**（评分即拒追不到的候选，根治 45 次 engage↔rejoin 循环）+ **SURVIVAL_STICKY=8** 带内防横跳。两整合面：A 评分治② + B 泛化 scan_leader_rear（锚操控机·常开·≤2 机回防）治①。**阶段 1+2 已落地**（ObjectiveContext+面A三件套 / 面B `try_defend_protectee` 常开回防≤2机 / `leash_anchor_and_limit` 三态松绑）：target_sel 35/35 + fire_discipline 10/10 + rejoin 指标一致 + stress_40 开销在噪声地板 + 双校验 ✓；**余：物理步进 sim 断言（playtest 前）+ 可选 BOSS 期杂兵刷新收敛 + playtest 调参** |
| [systems/rts-command](systems/rts-command.md) | system | done | ✅ | RTS 指挥（独立模块 SquadCommandController + 参数 Resource）：战术地图航点/战区边缘巡航 + 到点自动交战 + **玩家命令逐机持久铁律**（commanded_target 跨 1–9 切控、AI 不得覆盖；跟打僚机继承命令优先级，普通归队不得覆盖）+ 右侧开关；自由僚机切目标细则归 target-engageability-selection |
| [systems/brake-steering](systems/brake-steering.md) | system | in-progress | ✅ | **急刹拖拽转向**：战场内按住右键继续急刹，以按下点为中位左右拖拽；轻拖微调机头、保持侧向持续盘旋。屏幕虚拟摇杆同步显示减速、真实左右舵量、即时速度、明确标名的机炮剩余/最大弹药、有效射程及失速转向锁定；当前操控机前同步绘制真实机炮扇形或炮艇射程环。转向复用持续 G、滚转率、减速率、失速软地板与协调转弯公式；普通机炮、机炮吊舱与炮艇独立自动火控在拖拽期间继续工作，机场面板接管前强制恢复鼠标。 |
| [systems/waypoint-fire-control](systems/waypoint-fire-control.md) | system | in-progress | ✅ | 航点移动机会火控（2026-07-31 用户确认分阶段）：阶段 1 已让亲控机/玩家编队僚机在不写 `combat_target`、不改变航线时复用现有严格导弹齐射过滤；锁定/包络/坡度/滚转/离轴/超杀门全部不动，`waypoint_fire` 27/27 + 相关行为回归 + Lv15 编队压力样本已通过。阶段 2 放宽数值未批准；余 Sentinel 有渲染手动验收。 |
| [systems/target-engageability-selection](systems/target-engageability-selection.md) | system | done | ✗ | 目标选择改"可命中性"评分：对正度/包络/锁定(封顶)/邻近四因子 + 承诺火力超杀让路（**机炮优先豁免：不降权/不换目标**）+ 守后优先(rear_threat_score)；根除锁定 runaway。**代码落地 + 自动回归，差生存 playtest 调参** |
| [systems/wingman-escort-evasion](systems/wingman-escort-evasion.md) | system | done | ✅ | 僚机护卫规避：玩家按 E 时僚机不再无脑散开——被真威胁才逃，否则召回编队待命 + 投护卫 flare 替长机挡追它的导弹（escort_cover_active 与 evasion_mode 解耦；护卫 jam=0.70×近度，范围 800m）。玩家、直属僚机与 TEAM_ALLY 友军自卫/护卫统一排除失导、错目标、同阵营、飞离/追不上的导弹；加力窗口内暂缓自动投放。**代码落地，差 §5 playtest** |
| [systems/afterburner-mode](systems/afterburner-mode.md) | system | in-progress | ✅ | 加力模式（规避模式资源化改造，**充能制/电池模型**）：小队能量池（上限 6s / 被动 0.2/s ≈30s 充满 / 击杀 +0.8s / 开局满格），`CHARGING/ACTIVE` 为唯一状态机，WeakRef 固定激活快照。有能量即可 E 启动；激活期全队 100% 机炮闪避 + 90% 滚转甩导弹 + 禁攻击 + 满速地板，并在世界状态栏显示 `AFTERBURNER`。世界飞行指令立即取消、开始充能且不瞬降当前速度；热诱弹进入 CD 且加力可用时 E 键闪烁最多 5s。窗口内玩家与僚机暂缓自卫/护卫自动热诱弹，把库存留给退出后的真实威胁。肉鸽技能、专属载荷、签名技能与 HUD 统一只认窗口 accessor。**模块化重构、focused/Visual 回归已落地，差 §5 playtest** |
| [systems/weapon-employment-doctrine](systems/weapon-employment-doctrine.md) | system | done | ✅ | 武器使用准则：僚机多武器时"什么距离用什么武器"的竞选规则（距离带+滞回+命中率优先）、全武器统一"机头指向路径提前点"瞄准语义（锥角=纪律严格度，电磁炮 ±3° 最苛）、机动跟随主武器（railgun LINE_UP 直线充能 intent）+ 电磁炮承诺弹道（指示线=发射线）。验收：MRM 命中 44%→79%（log 175843） |
| [systems/joust-attack-run](systems/joust-attack-run.md) | system | done | ✅ | 攻击跑行为原语：RUN_IN 对准进入火力窗（两段速）→ BREAK 脱离拉开 → 折返循环；包络动态读装备 live params；修 MG 电磁炮 UAV"切向轨道 vs 机头对准"死锁（log 183044 全场 0 充能）+ 骑士型 Lancer（J-7/F-104/F-100/MiG-31）打带跑统一实现（取代 engage_duration 定时器）。bench 7/7 + playtest 手感确认（2026-07-05） |
| [systems/command-wheel](systems/command-wheel.md) | system | done | ✗ | 命令轮盘：按住左键呼出 marking menu（位置=参数/方向=动词，0.3x 子弹时间）。**操作语法：单点=只操控自机 / 轮盘=永远全队广播**。小队命令轮盘(按空地)=紧急集合+撤离此区(圈内径向散出 3km+20s 限时禁入圈、圈外不生效)+防守此区(**3km 区域清剿：全队自主搜敌/分头接战/击杀后接续，圈外不获取、越界停追、清空后继续守备**)+开关（自动交战/高度偏好两态/自动发射）；玩家“爬升”偏好不再锁死 10000m，改为中心 8400m、7600–9000m 边界、个体错相漂移与转弯掉高的自然高度带，敌机不变。攻击轮盘(按敌机)=姿态（保持距离 STANDOFF 打带跑/突击 ASSAULT 锚定）×火力分配（集火=同目标+包围轴分离≥45° / 分火=锚点目标池内各自接敌+超杀让路）×阵型纪律开关；高度“默认”第三态仍搁置。**代码主体全落地，差 playtest**。 |
| [systems/formation-discipline](systems/formation-discipline.md) | system | in-progress | ✗ | 阵型纪律与齐射：队级开关 FREE 自由散开（=现状）/ TIGHT 紧密队形。**v1 已落地（2026-07-12 用户确认后实装）**：TIGHT 集火=长机独持命令目标、僚机全程编队跟随（整队进入/拉开由编队复现涌现）；**齐射触发器=长机开火**（玩家亲自扣扳机=全队齐射）→ 开窗 1.5s 临时授予僚机槽位内开火权（volley_fire_active 豁免编队防御清除）→ 到时回收=禁补射 → 停火 2s 再武装；ASSAULT 豁免（普通集火广播）。--bench=tight_volley 10 断言。剩：HUD 第 6 toggle（收束轮盘方向暂不做）/巡航收紧 leash/SPREAD+TIGHT/playtest |

| [systems/combat-effectiveness-metrics](systems/combat-effectiveness-metrics.md) | system | draft | ✗ | 战斗效能评估：交战记录 4 层指标（转化 FSR/执行 hit_rate/结果 TTK/对手规避+CapIndex 差距）+ 两轴 Offense/Defense 评级 + bench 对位矩阵；核心解决"快机打不中慢直升机≠直升机强"。**仅 §1~§6 草稿，待 review** |
| [systems/aircraft-evolution](systems/aircraft-evolution.md) | system | superseded | ✗ | **历史高层骨架，禁止继续派生实现。** 当前权威已拆分到 zone-reward-docking、aircraft-evolution-tree、evolution-attribute-gates 与 inrun-weapon-inventory。 |
| [systems/aircraft-evolution-tree](systems/aircraft-evolution-tree.md) | system | done | ✅ | **v9**：T0~T5 共 50 节点 / 155 边；新增四架 T0 起手与三架 LV4 低位 T1；永久不可达边=0。 |
| [systems/t0-low-t1-aircraft-expansion](systems/t0-low-t1-aircraft-expansion.md) | system | done | ✅ | 保留既有四张选机卡，追加四架局外采购 T0、三架低位 T1、50 机进化树与七个不可授予专属槽占位。 |
| [systems/aircraft-mastery-progression](systems/aircraft-mastery-progression.md) | system | draft | ✗ | **单机熟练度 + 科技树迷雾 + 研发许可草案**：43 机各五段微调，M5 目标约 +15% 综合效能；直属小队击杀计入当前操控机型；累计功勋做无战力军衔；9 架横向/秘密机由 8 项功勋项目取得局内进化资格，免费纵向骨架不锁。 |
| [systems/evolution-attribute-gates](systems/evolution-attribute-gates.md) | system | done | ✅ | **v22 已落地**：全部节点使用具体逐轴门槛，F/A-18E `any` 保留；电子对抗套件不再增加热诱弹数量，策士 3 点里程碑仍独立 `+1`。主 HUD 常驻三轴里程碑进度；Boss Debug 动态列出全部 T4，每项生成至少四机同型 Squad，按节点等级从正式三星池配 2~3 件 ACE 特殊武器，再按 gates 配置正式节奏技能 build；Tab 可核对武器、技能与里程碑。 |
| [systems/evolution-growth-benchmark](systems/evolution-growth-benchmark.md) | balance | done | ✅ | 50 机参数验收；常规机炮 T2–T5 按 1.175/1.25/1.35/1.45 与 1050/1150/1250/1350 平滑抬升，机炮核心保留强化档；真实进化边单步≤35%。 |
| [systems/multi-target-missile-locks](systems/multi-target-missile-locks.md) | system | done | ✅ | 多锁多射从 on/off 改为可叠加锁数：基础 1；稳定级骑士普通卡每层 +1（最多 3，全队）；F-22 隐身 +2；导弹蜂群全队 +3；骑士 8 点 +1。齐射覆盖数=`min(有效锁数,合法目标,弹量)`，每轮正常冷却。斗士装甲里程碑现位于 4 点；策士 3 点 XP +10% 不变。 |
| [systems/missile-launch-discipline](systems/missile-launch-discipline.md) | system | done | ✅ | 飞机共用导弹发射纪律：档案技能/抖动、稳定瞄准包线、两次前置预测与 ±60° 初始弹道；地面/舰载/BOSS 发射路径不变。 |
| [systems/aircraft-icon-rendering](systems/aircraft-icon-rendering.md) | system | done | ✅ | 当前逐机型顶视 PNG 目录取代历史通用 fighter Sprite；保留专用轮廓与安全回退，排除旧 O(N²)/MultiMesh 性能试验。 |
| [systems/localization-catalog](systems/localization-catalog.md) | system | in-progress | ✅ | 本地化拆为五张权威表与 15 个资源；1390 个唯一 key、主菜单三语言视觉通过，尚欠英/日 HUD 实机视觉验收。 |
| [systems/inrun-weapon-inventory](systems/inrun-weapon-inventory.md) | system | in-progress | ✅ | **v3 局内武器库**：特殊武器（火箭/电磁炮/激光/忠诚僚机/QMAAM/漂浮雷/ESM）属于当前 ACE 的局内玩家库存，到手即永久、换机/进化全继承（含强化）；所有 `player_*.tres` 只保留机炮/基础导弹/flare 底线。Boss Debug 已从正式三星池按参考等级随机搭配 2~3 件，先装武器再筛技能并在 Tab 显示；四机以上编队不复制 ACE 武器。核心快照/补挂/技能重放与 Debug 回归已落地，普通局仍差结算清单分段和 Tab 武器库图标行。 |
| [systems/aircraft-signature-skills](systems/aircraft-signature-skills.md) | system | approved | ✅ | v9 共 43 条机体专属技能；全部从随机抽选与奖励池移除，机场以“保留当前机并装备专属技能 / 进化”二选一取得；43/43 映射与详情陈列受自动审计保护。 |
| [systems/aircraft-signature-progression](systems/aircraft-signature-progression.md) | system | approved | ✅ | 43 条机体专属许可；Tier 数量 4/16/8/7/8、全购价 30000；许可已购时机场留机装备与进化严格互斥，专属技能不进入基础三卡或机体适配普通第四卡。 |
| [systems/airframe-affinity-fourth-card](systems/airframe-affinity-fourth-card.md) | system | done | ✅ | **机体战术适配全局升级**：机体与后勤页 3000 功勋恒上架；购买后自然升级有 15% 概率追加一张当前机体身份轴的普通第四卡，多轴等概率选轴，完整继承普通稀有度、门控、构筑引导、终端债务与金卡 pity。 |
| [systems/skills-720-rework](systems/skills-720-rework.md) | system | done | ✅ | 720 技能整改批（用户逐条改表）：**"+1 轴进度"系统**（选卡奖励里程碑进度非技能点，13 条；预留档通道；cap 2 待二选一）+ 归属词汇 v6（王牌层为 AoE 控场强技收敛回归/A10 限定=exclusive_to/需要词条=requires_skill/队级单实例 1→8）+ 新增 27（含 R 键手动闪避/僚机阵亡触发×3/技能计数缩放×4/轮盘联动×2）/ 改动 ~35 / 移除 railgun_damage；实现对照四档（纯数据/复用钩子[加力充能·击杀归因·轮盘状态·recompute]/追加功能/新机制）；排查双项（数据链生效+僚机锁可射、寒蝉友军 JAM bug）；任务拆分 T0~T6。**待 review** |
| [systems/squad-upgrade-ownership](systems/squad-upgrade-ownership.md) | system | superseded | ✗ | **历史绑机型 build 草案，禁止继续派生。** 当前技能作用域与王牌迁移以 skills-720-rework 为权威，里程碑全队语义归 evolution-attribute-gates，特殊武器归 inrun-weapon-inventory，1–9 切控归 squad-control-switching。 |

| [systems/ui-transition](systems/ui-transition.md) | system | in-progress | ✅ | 表演导演系统（转场/镜头/时间/演出）：TimeAuthority + SequencePlayer + time/camera/overlay/panel/banner/radio/stage/actor/audio 通道。所有注册 BOSS 生成后先让 5 个系统警告窗逐个完成压入，再展开身份横幅并进入统一 arrival 镜头；Wraith 左上为 `NOTHING BUT THIEVES` 并使用蓝黑/电蓝变体，其余维持终端绿。身份文字设安全内边距并在动画全过程硬裁切。Wraith 四机交汇 6.68s；CSG 旗舰镜头 6.73s；Mother Goose 母机镜头 6.33s。演出收尾立即 ENGAGED；缺序列或被 UI 转场覆盖时 fail-open 接战并亮血条，统一受 7s 硬上限与时间/舞台/演员/横幅四类泄漏兜底约束。 |
| [systems/pause-menu](systems/pause-menu.md) | system | done | ✅ | 暂停菜单：ESC 从"无确认直接销毁战局回主菜单"改为**冻结全场 + 确认页**（继续作战 / 返回主菜单），顺带补上游戏本来缺的暂停能力。时间控制全部复用表演导演 `panel_in`/`panel_out`（不直写 `get_tree().paused`）；面板 `PROCESS_MODE_ALWAYS` 自理"ESC 关闭"（硬暂停期间 survivor_mode 收不到输入，与战术地图同一分工）。ESC 优先级表：战术地图 > 选卡（不响应）> 暂停菜单开关 > 结算态直退 > 打开暂停菜单。**不改结算语义**——中途退出仍不结算功勋，只在确认页明写后果 |
| [systems/combat-feed](systems/combat-feed.md) | system | done | ✅ | 战况栏 / kill feed：左上角实时"谁用什么武器击坠谁"，最新 5 条、HOLD 5s+淡出 1.5s、友绿敌红配色；EventLogger.kill_recorded 信号桥接、复用既有击杀归因。同批放宽镜头缩放上限 ZOOM_MIN 0.4→0.2 |
| [systems/meta-progression](systems/meta-progression.md) | system | superseded | ✗ | **历史“局外武器 loadout”草案，禁止继续派生。** 当前局外层由 career-archive、career-shop、doctrine-unlocks 与 aircraft-signature-progression 承担；特殊武器明确属于 inrun-weapon-inventory。 |

| [systems/ace-system](systems/ace-system.md) | system | superseded | ✗ | **历史“长机角色 = ACE”草案，禁止继续派生。** 当前技能中的王牌作用域随玩家当前操控机迁移；切控/换帅归 squad-control-switching，进化与三轴归 aircraft-evolution-tree / evolution-attribute-gates。 |
| [systems/ace-rotation-balance](systems/ace-rotation-balance.md) | balance | in-progress | ✅ | **王牌新局随机轮换 + 60~90 秒标准击破预算**：固定两槽——开局 3:30 第一波、BOSS 前最后 3:00 第二波；单局无放回且最多两支，同场占用时第二槽待触发、终态后不追加冷却。固定时序与 DU/TTK 日志已落地并通过专项及全量回归；仍差每队 5 局实测与专项压测。 |
| [systems/ace-squadron-tier](systems/ace-squadron-tier.md) | system | in-progress | ✗ | **敌方**王牌中队分层标准；六支非宿敌按固定 3:30 / BOSS 前 3:00 两槽洗牌轮换，默认 flare=1，VULTURE 为量化后的 0 flare；WhiteTea 登记首个 `gun_lancer` 纯机炮骑士与一次性 J-turn。非 BOSS 王牌中队血条浮现时从四首专属曲随机抽一首 one-shot，曲终或中队终止后恢复普通歌单，Boss 优先。其余 tier 契约（LOD 豁免、无缩放、极强攻击欲、BOSS 子集、包装/血条/档案）不变。 |

| [systems/early-game-uav-rework](systems/early-game-uav-rework.md) | system | done | ✅ | 前期敌情与 UAV 更名改造（2026-07-26 用户四件套，v2）：①无人机更名——机炮 UAV=**MQ-109**、导弹 UCAV=**MQ-110**（显示名/呼号/i18n，内部标识不动；v2 订正 MQ-110 **不退役**，与 F-4E 并存）②**elite 战区任务移除**（Sentinel 作为战区目标太弱；E 区限制改 naval/squadron）③Sentinel+MQ-109 小队=普通地图刷新敌人（COMMANDER 概率 0.06/0.12 上调）+ **战区驻守障碍**（25% 概率带 6-10 MQ-109 驻守、非 TGT、驻守预算减半、全场唯一）④新增 [f-4e](enemies/f-4e.md) 有人导弹杂鱼填前期空间。**代码落地，差 playtest** |
| [systems/battlefield-tempo-pass](systems/battlefield-tempo-pass.md) | balance | done | ✅ | 战场节奏批（2026-07-22 用户三联反馈：冷场/XP 少/缺进场敌机）：**拦截波**——hunter 配额缺口 ≥2 时本波旅途增援改为"玩家前方 ±90° 扇区边缘入场 + 航点持续指向玩家、永不 ONSTATION"，由既有 ROE 感知/hunter tick 自然收编（单杠杆自平衡，冷场必来/热闹必不来）；**新战区 F 荒川北岸 ground r2200 / G 千叶中部 air r2500**（几何自检过 1500/2000 约束，候选池 4→6）；刻意不动任何热度旋钮保 density-pass 归因。**已落地 + test_map_expansion 全绿，差 playtest** |
| [systems/zone-reward-arsenal](systems/zone-reward-arsenal.md) | balance | done | ✅ | 首批 A/B 奖励目标延迟到 60s+Lv3，先广播、6 秒后生成；保留武器/次世代双保底。次世代池现为 6 项（重型机炮保留、狂化病毒移入实验级普通池），七件武器与航母第 4 次保底不变。 |
| [events/ace-whitetea-fck1](events/ace-whitetea-fck1.md) | event | in-progress | ✅ | **WhiteTea**：F-CK-1×3 中期纯机炮骑士；进入固定 3:30 / BOSS 前 3:00 王牌轮换；逐机 joust 打带逃，每机 1 flare 后解锁一次性 J-turn；独立 4×5 受控短梭，三机同步首梭不秒满血玩家；呼号 Tea/Cola/Bottle；Debug 复用正式事件并立即显示分段血条。 |
| [events/ace-orion](events/ace-orion.md) | event | done | ✗ | **宿敌 ORION / 猎户座（2026-07-27 用户）**：原创机体 Cre ×1 单机——tier §3.8 宿敌条款唯一实例（六项豁免：单机/静默登场无任何提示/伪装普通敌橙/跨局成长/机号即呼号 Cre-XX/无时间奖励）；只死咬玩家**当前操控机**；被击坠全局计数 +1（CareerArchive），机号 Cre-01→99 进位；成长档位表 5 档（初始敌机级别→顶格 AI 1.0+闪避 0.50+满武装，性能 ×1.0→1.4，武器 机炮→导弹→ace_gun→QMAAM）；中期 ~300s 独立轨道每局一次、不占轮换名额；**728 核心落地**：enemy_cre+OrionNemesisEvent（独立轨道 300s/静默/死咬操控机/BOSS 闸撤离/击坠生涯+1）+档位表纯函数 bench 断言；落地修订=XP 统一 100/档IV QMAAM 暂以导弹数替代/血条待拍板。**差 playtest** |
| [events/ace-gimmick](events/ace-gimmick.md) | event | done | ✗ | **GIMMICK / 把戏**：F-16×2 狙击（BVR 4~6km）+ Mirage 2000×2 斗士的远近夹击；固定 3:30 / BOSS 前 3:00 洗牌轮换；8 DU+30s access=预计 TTK 70s；洋红涂装/双箭头徽章/BLUFF~SWITCH 固定呼号。**差 playtest** |
| [events/ace-goofighters](events/ace-goofighters.md) | event | done | ✗ | **GOOFIGHTERS / 怪火**：Su-47×2、格斗弹+一次性眼镜蛇；每机 1 flare 后解锁 Cobra，合计 6 DU+40s access=预计 TTK 70s；固定 3:30 / BOSS 前 3:00 洗牌轮换；深紫罗兰涂装/WISP+ORB。**差 playtest** |
| [events/ace-2ndwave](events/ace-2ndwave.md) | event | done | ✗ | **2NDWAVE / 第二波**：Teacher F-4E 斗士 + F-15×4 学员骑士混编；Teacher 顶格 AI/0.50 机炮闪避，2026-08-01 改为 1 flare 且不再叠持续 evade；全队 10 DU+20s access=预计 TTK 70s；固定 3:30 / BOSS 前 3:00 洗牌轮换。**差 playtest** |
| [events/ace-lancer-mig31](events/ace-lancer-mig31.md) | event | done | ✗ | **VULTURE / 秃鹫**：MiG-31×8 横列高速掠袭，纯导弹无机炮；2026-08-01 全员 flare 1→0，以 8 DU+40s 追击 access=预计 TTK 80s（旧 16 DU/120s）；固定 3:30 / BOSS 前 3:00 洗牌轮换；6 波弹尽撤离。**差 playtest** |
| [events/ace-support-squadron](events/ace-support-squadron.md) | event | in-progress | ✅ | **MARATHON / 马拉松**：Su-35×5 斗士，1 flare/架、猩红涂装、PACER 长机；10 DU+25s access=预计 TTK 75s；固定 3:30 / BOSS 前 3:00 洗牌轮换；全灭 +60s 作战时间。已购 `support_ace_f15` 时仅本局首次事件派 Hound-1/2 两架 3000m 雷达 F-15，并播固定双句，终态物理撤离。**差 playtest** |
| [systems/zone-reward-docking](systems/zone-reward-docking.md) | system | done | ✗ | 战区奖励攻克即领；停靠仅全队回血与进化。航母限 2 次登舰且第 4 次奖励 roll 保底；僚机奖励同型最多 2 架、不增加战斗等级；四类奖励与七件武器的数值由 zone-reward-arsenal 统一负责。 |
| [systems/60km-density-pass](systems/60km-density-pass.md) | balance | done | ✅ | 60km 密度调优（playtest 反馈"敌人少"）：战区半径 A/C/D 3500·B 3000·E 2500 + 盘旋环随半径撑开；任务规模（地面 TGT 3+3/4+4/6+6、中队 4/5/6、驻守预算 12/22/42×1.10^L、精英护卫 6-10）；丰富化（★★+ 雷达站 TGT 削预警层次、中队长机高一档）；热度（token 8+1.8L cap55、间隔 32→18、上限 36/48、驻防 3 队、hunter max(3,2+L/2)）；附带修教程轰炸机锚点（扩图后 10.9km 远→出生点前 3km 派生）。**回归绿，差 playtest+压测** |
| [systems/reinforcement-ingress](systems/reinforcement-ingress.md) | system | done | ✗ | 增援与战区空军入场：旅途增援、空战 TGT、普通驻守与 Sentinel 驻守均从地图边缘飞入；保留战区任务既有可见性死锁恢复与静态目标语义，只消除空中敌机贴脸生成；旅途敌机到中央锚点驻空并在 token 饿时物理 EGRESS，战区空军到自身巡逻环后恢复普通 LOD。**代码与聚焦回归落地，差正式 Visual/playtest** |
| [systems/aa-fire-awareness](systems/aa-fire-awareness.md) | system | done | ✅ | 僚机对地面机炮火力警觉：①被 AA/CIWS 机炮命中 → 打断 SETUP/RUN 强转 EGRESS + 机头转出 45° 后 AB 全速脱离（EGRESS 加速为敌我通用改进）；编队/巡航被打不脱队只 AB 直线冲刺 2.5s；②STANDOFF inner 环抬到目标对空火力半径 ×1.25（CIWS 舰 2200→2500m）+ F-Pole：弹在飞/TEAM_OVERKILL 时不压入、环外 crank 等命中。单杠杆=只对"被命中"反应，不做火力圈预判扫描。**代码全落地 + --bench=surface_pass §E 8 断言（28/28 绿），差生存 playtest/压测**。**v3（2026-07-28）CIWS 真弹周期 3→2**（有效伤害射速 ~11→~16.7 Hz、拦截 DPS ×1.5；仍是真实弹道拦截非概率判定，散布/命中半径/距离衰减不变，60HP 导弹仍需 6 发真弹）——本 spec 常量一个未动，但舰船火力圈停留成本上升 |
| [systems/surface-attack-pass](systems/surface-attack-pass.md) | system | done | ✗ | 对面攻击 pass 循环：地面/舰船静止目标做俯冲攻击跑（SETUP→RUN→EGRESS + 最小转弯半径守卫，根治"机炮打 SAM 原地绕圈"死锁）；姿态 STANDOFF（导弹远距 standoff 环脱离不进 AA）/ ASSAULT（机炮贴地俯冲穿越）分流，默认由武器竞选推导（有弹保持距离/无弹机炮），预留 command-wheel 姿态覆盖钩子。相位状态位走 `_apply_tactical_plan` 回写、planner 保持纯函数。**全量落地 + 无头行为 sim `--bench=surface_pass` 9/9 + bfm_intent 102/102 + all 18 项绿，差生存 playtest** |
| [systems/slow-air-target-pass](systems/slow-air-target-pass.md) | system | done | ✅ | 慢速空中目标（直升机）交战 pass：与 surface-attack-pass 共用同一台相位机，只换包络常量与终端瞄准点。根治用户报的"绕好多圈打不中 / 锁定上了却不发射"——四层叠加根因（几何极限环 / LOW 档 4.3s 锁定被出锥 0.3s 清零 / 满锁被 off-axis 发射门拒发 / **锁定即压坡到 35% 导致再也转不进发射锥的通用死锁**）。分流置于优先级 4.5（必须早于 overshoot/boom-zoom 等只对快机成立的能量学规则）。**`--bench=slow_air_pass` 14/14 + all 全绿，差生存 playtest** |
| [systems/map-expansion](systems/map-expansion.md) | system | done | ✗ | 地图扩展 + 战区重排：60×60km 核心与战区布局保留，三图共同 overscan 再提供四边各 2km 外缘空域（真边界 64×64km）；进入外缘连续 2.5s 后才触发补给/调头/撤退，相机严格裁切，AI 认新边界。无头回归覆盖几何、倒计时与 AI 边界。**仍差 ≥3 战区/局节奏 playtest** |
| [systems/weather-clouds-and-sandstorm](systems/weather-clouds-and-sandstorm.md) | system | done | ✅ | 图2/3 普通云改为 0.00024 大片低频云系，海岛以第二噪声 0.70 填补分布空洞；沙漠局时 45% 起从西向东卷过 60s 黄色沙尘暴，只在 LOW 复用普通云的导弹失误/制导衰减/锁定延长；F6 可跳半局直看风暴中段。**自动回归已建，差性能与人工视觉验收**。 |
| [systems/ugc-editor](systems/ugc-editor.md) | system | draft | ✗ | 游戏内 UGC 编辑器 + 创意工坊：飞机/地图/编队可行性高（params 纯数据、JSON+user:// 惯例现成）；安全红线只收 JSON+数值围栏；P0 数据化→P1 地图编辑器（兼扩图工具）→P2 飞机→P3 编队→P4 本地分享→工坊（GodotSteam/mod.io） |
| [systems/map-editor](systems/map-editor.md) | system | approved | ✗ | 地图编辑器（UGC P1 细化）：格子笔刷前端 + 矢量多边形后端；调色板 + 官方 gameplay 图层直通转换；UGC 试飞保持 vector-only。**正式东京湾主地图与 Tab 保留 PNG + shader**，转换器不得删除或覆盖；v19 同步自主视觉 QA、真实道路/机场/港区与静态性能门。**已定稿，待按 §6 五阶段实装** |
| [systems/pure-vector-map-preview](systems/pure-vector-map-preview.md) | system | superseded | ✅ | **V45 决策归档**：V1–V44 debug `Shift+F10` 全东京湾候选完成结构、覆盖与性能研究，但用户最终整图视觉验收未通过。正式东京湾主地图与 Tab 保留 8704×8704 PNG + shader；候选 renderer/数据/QA 仅冻结作 debug 研究材料，不再作为当前生产迁移或 PNG 退役路径。未来重启须另立 approved spec。 |

| [systems/radar-range-normalization](systems/radar-range-normalization.md) | system | approved | ✅ | v3：50 机按 T0~T5 六带 1900~4400 铺开；真实进化边 0.90~1.35；电子战类别每技 +3% 且 ×1.30 封顶；最终有效雷达 9000 px 硬上限；敌 F-4E/AF-03 与双重武器成长修正。 |
| [systems/player-aircraft-power-curve](systems/player-aircraft-power-curve.md) | balance | approved | ✗ | v23：当前 50 机 / T0~T5 曲线契约；机炮弹量按定位分 180/200/240/280/320 五档且以 180 为硬下限；七新机与雷达分别由扩谱/规范化 spec 负责。 |
| [systems/engagement-discipline](systems/engagement-discipline.md) | system | done | ✅ | 交战纪律 v2：无目标 AI 停火；基础机能量劣势会脱出；新增**属性感知狗斗画像**，按双方转率/半径/滚转/减速分 balanced/energy/tight。强 G 机保能量赢转率，强刹低失速机切内圈并减少无效脱离，僚机更早转入直接 BFM；不放宽机炮扳机。 |
| [systems/squad-engagement-persistence](systems/squad-engagement-persistence.md) | system | done | ✅ | 小队交战不再因目标短暂越过雷达距离每 2 秒弃战；空间边界继续由距长机 leash 与长机丢目标宽限控制。 |
| [systems/radar-lock-capability-gate](systems/radar-lock-capability-gate.md) | system | done | ✅ | 只有主 AAM、railgun 或对空 laser 飞机参与主雷达 shooter 扫描并绘制主雷达锥；副槽与 victim 集合不受影响。 |
| [systems/cloud-skill-consistency](systems/cloud-skill-consistency.md) | system | done | ✅ | 云中超载统一走 timed status 联动链；云中武器 CD 改为 rate 模型，消除拾取/进出云边界错配。 |
| [systems/modifier-pipeline](systems/modifier-pipeline.md) | system | done | ✅ | 运行时修改器收口：CD rate、Sentinel 光环字段化与全量重算、实飞/预测加减速 accessor、Shift+F12 黑盒追踪。 |
| [systems/global-awareness-roe](systems/global-awareness-roe.md) | system | done | ✅ | 全图察觉与交战规则（ROE，v2 按 review 简化）：**中队级感知**（感知圈=长机雷达距离全向 + 被打即察觉 + 战区 datalink，15s 记忆；中队三字段 posture/aware/squad_target，不逐机算）+ 任务姿态五型（守区 leash=区+1500m 出圈停追 / 巡逻 leash 6km 含 30% 线路巡逻 / 狩猎全知 / 转场 / 撤离）+ **热度即难度**（heat 0-100 纯内部量不上 HUD，唯一输出 hunter 配额 round(2+10h/100)，静默基线复刻既有曲线、等级地板 min(75,5L) 载难度爬升）+ **第三方事件化三类**（护送直升机 A→B +40 功勋/架 / 机场防空 SAM+AA×3 停靠机场 / AWACS 南带往返 8km buff 区锁定×3·导弹×1.25；ALLY(2) 不可控 0 XP，航母存量收编）+ 阵营色板统一（FactionPalette **蓝=玩家直属/绿=中立·第三方**/橙红=敌；机体无 PNG，敌机 icon_color 审计 ×15 换暖色）+ IFF 收口（is_hostile_to 单 API，四类硬编码迁移清单）。**阶段 1~5 代码全落地**（roe 单测 33/33 + 回归门 21 项 + 30s 冒烟绿；落地修订 §8-v3：posture 派生制/事件察觉 2s 粒度/守区战区聚合/AWACS 无 flare/航母收编暂缓），**差 playtest + 压测**。**v5（2026-07-28）第三方事件回炉**：①**护送事件整体删除**（含 EVENT_ESCORT_* 三键）——奖励纯局外功勋 / Tab 图不画 / 无无线电 / 抵达即静默消失，玩家既找不到也没有局内理由去打（§2.6a 转为废弃记载 + 事件设计三占其二教训）；②**AWACS 轨道改绕当前战区**（选中战区 > 最近 AVAILABLE > 南带兜底；南退 2200px < 光环 4000px 是硬耦合）+ **在站 180s 定时撤离**（超时 90s 兜底，光环留到飞出）+ **进离场 scripted 无线电各 3 条** + Tab 光环改淡填充/粗描边/圆心点；**buff 数值不变** |
| [systems/radio-chatter](systems/radio-chatter.md) | system | done | ✅ | 无线电通讯（皇牌空战式）：一次一条、绝不打断；JSON + `radio.csv` 驱动可读三语文字。声音不做逐句配音，而使用跨语言共享、像人在通信但完全不可辨词句的无语义人声纹理。奖励目标与护送任务均有 scripted 通报。**差音效素材 + playtest 调频度** |

<!-- 新增 spec 后在此追加一行。保持按 kind 分组、最新在各组顶部。 -->

---

## 待补 specs（重建缺口清单）

> ✅ **模板验证阶段已完成（2026-05-30）**：当前 9 种 kind（boss/enemy/skill/weapon/system/aircraft/event/map/balance）
> 各有 ≥1 个 reconstruction-grade 样板，模板与工作流已跑通。下一阶段是**内容铺量 + 触达即补档**；
> 批次顺序与完成线见 [content-production-workflow](../planning/content-production-workflow.md)。
>
> 以下内容目前**只在代码里**，是"靠文档重建"的漏洞。按优先级补 spec。

- [ ] **enemies/** —— 当前敌机 spec 已覆盖扩池常规机、af-03、f-4e、snowblind、deadair 与 sentinel-x；
      早期基础池、Adds 与部分 BOSS 专属单位仍只有 [enemy-index](../reference/enemy-index.md) + `.tres`，需继续补档。
- [x] **systems/survivor-loop** —— 时间制战区循环：10 分钟阶段、加权抽取、出界回血时间税（含扩展接入图）✅
- [x] **systems/event-system** —— GameEvent + EventDirective 剧本系统（含扩展接入图）✅
- [x] **systems/map-system** —— 地图边界 + 地理 + 三条流水线（含加新地图接入图）✅
- [ ] **skills/** —— 当前技能总量看自动生成的 [skill-table](../reference/skill-table.md)；已有少量单项 spec 与批量改造 spec，
      其余效果仍散在 `survivor_data.gd` / `skill_hooks.gd` / 常量与 i18n，需继续补档。
- [ ] **weapons/** —— 各武器 GunParams/MissileParams/RocketParams（现在 .tres）。已完成：qmaam（副槽）、gun-burst-fire（机炮梭射节奏）
- [ ] **aircraft/** —— 各主角机型档案（现走 PlayableAircraft 注入）。已完成：a-10 与本批七架 T0/低位 T1；其余继续补档。
- [x] **bosses/wraith-squadron** —— F-47 王牌狙击小队已由 [wraith-squadron](bosses/wraith-squadron.md) 覆盖。
- [ ] **bosses/carrier-strike-group** —— Ladon 战斗群 BOSS（编成/HP 1200/CIWS/弹射/二阶段衔接）。
      现状散在三处：CIWS 数值在 [aa-fire-awareness §2.1](systems/aa-fire-awareness.md)、
      舰队摆位地形校验与电磁炮对舰结算在 [boss-hunter-doctrine §2.5.1](systems/boss-hunter-doctrine.md)（暂寄）、
      二阶段 F-14 在 [bosses/poltergeist-squadron](bosses/poltergeist-squadron.md)、
      **F/A-18 弹射数值（开局 2 + 每 120s 补 1，整场累计上限 8，击杀不计价）在
      [survivor-loop §3.2](systems/survivor-loop.md)（2026-07-29 暂寄）**。建档时把这几处整段迁走
