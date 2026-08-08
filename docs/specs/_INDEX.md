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

## 工作流（doc → task pipeline）

```
设计  ── 复制 _TEMPLATE.md → 填 §1~§5 → status: draft → review → approved
执行  ── 按 §6 实现计划逐条打勾，代码从 spec 派生（执行 cheap）
收尾  ── 跑 §5 验收 → 更新 §7 锚点 + 同步 reference 索引 → 写 §8 变更记录 → status: done
```

**重建测试**：每份 spec 的 `reconstruction_complete` 字段，标记它是否已能脱离代码重建。
目标是全表为 ✅。

## 状态图例

`draft` 起草中 · `approved` 设计定稿待实现 · `in-progress` 实现中 · `done` 已落地并验收 · `superseded` 被取代

---

## 总表

| Spec | kind | status | 重建完整 | 覆盖范围 |
|---|---|---|---|---|
| [systems/player-instrument-hud](systems/player-instrument-hud.md) | system | done | ✅ | **玩家与僚机仪表 HUD**：替换右侧旧 TACTICS/玩家信息/僚机富文本框；玩家内部逐行左上角锚定，HP 右侧仅 G，SPD 左侧为 ALT/高度偏好、右侧为速度/单位，Q 与 E/G/F/T 在外框左侧同列；唯一 R 技能取得后常驻 0%→100% 充能且不显示秒数；固定拉丁内容保留 Acumin，本地化中日韩文使用主题默认字体。 |
| [systems/presentation-foundation-rework](systems/presentation-foundation-rework.md) | system | draft | ✗ | **表现层底层逻辑改造确认稿**：持续汇总本轮讨论中由用户明确确认的主要改动；区分待讨论、已确认、已实现，记录旧/新行为、影响、风险、退化策略与验收标准，并以既有 `ui-transition` 为依赖。 |
| [skills/displacement-roll](skills/displacement-roll.md) | skill | done | ✅ | **位移滚转**：实验级 R 主动技能；1.15s 内确定性选择安全侧并横移 450px，15s 玩家小队共享冷却；动作本体不可命中、保留锁定与在飞武器；并入五向 R 互斥槽，当前操控机手动、AI 僚机自动。 |
| [skills/vertical-break](skills/vertical-break.md) | skill | done | ✅ | **垂直越过**：实验级 R 主动技能；LOW 拉升/MID·HIGH 俯冲 900m/1.30s，18s 玩家小队共享冷却；额外能量交换封顶 −18%/+15%，并入五向 R 互斥槽，当前操控机手动、AI 僚机自动。 |
| [systems/active-special-maneuvers](systems/active-special-maneuvers.md) | system | done | ✅ | **主动特殊机动共享契约**：五种 R 技能统一双向互斥且玩家只持有一个；当前操控机按 R、AI 僚机按威胁自动释放；共享冷却、最新命令队列、切控续播、统一不可命中查询；玩家仪表取得后常驻并只显示 0%→100% 可用度。 |
| [systems/status-build-completion](systems/status-build-completion.md) | balance | done | ✅ | **状态词条构筑聚焦与终端保底**：保留三轴各一卡，已选主词条相关卡按 `1+0.75×sqrt(min(A,4))` 加权、无关卡降至 ×0.85/×0.70/×0.65；终端首轮 ×2、次轮 ×4、第三次合格事件强制出示但不自动授予。同步六项新技能、词条闭合、稀有度调整与 BLOODLUST 基础机炮零耗弹。 |
| [skills/flee](skills/flee.md) | skill | done | ✅ | **逃离**：实验级全队唯一；新 FEAR 40% 令普通载人敌机真实撤退并正常结算一次 XP；无人机、ACE、BOSS 与 BOSS 生成物豁免。 |
| [skills/invasion-algorithm](skills/invasion-algorithm.md) | skill | done | ✅ | **入侵算法**：实验级全队唯一；玩家小队 JAM 使 MQ-109～112 立即坠毁并正常结算一次 XP。 |
| [skills/hunter](skills/hunter.md) | skill | done | ✅ | **猎手**：机密级全队技能；突击目标存活期间 +2G、加减速 ×1.2、G 能量损失 ×0.7、承伤 ×0.7，目标结束即关闭。 |
| [skills/heavy-gun](skills/heavy-gun.md) | skill | done | ✅ | **重型机炮**：次世代全队技能；机炮射程 +1000m，斗士 +1。 |
| [skills/gunship-mode](skills/gunship-mode.md) | skill | done | ✅ | **炮艇模式**：次世代全队技能；当前机与 AI 僚机各自以 360° 独立扫描最近敌机/地面单位并整梭跟踪，显示完整射程圈，最大速度 -40%，斗士 +1。 |
| [weapons/esm-pod](weapons/esm-pod.md) | weapon | done | ✅ | **ESM 吊舱**：3000m 数据链光环；锁定速率 ×1.5，机炮/导弹/热诱弹装填时间 ×0.7；2Hz 共享列表扫描；F4/F6 可直接测试。 |
| [systems/dynamic-faction-conversion](systems/dynamic-faction-conversion.md) | system | done | ✅ | **动态阵营转换**：统一原子清理 IFF/目标/锁定/旧小队/奖励/在飞武器；WhiteTea 仅余一机时投降转 ALLY、本人喊话后被动离场并按王牌击破结算；策士“黑客光束”与“激光致命输出”双向互斥，持续 2.5s 可黑入 MQ-109/110，转为绿色不可控 ALLY并跟随当前长机战斗至被击毁。 |
| [systems/flight-model-realism](systems/flight-model-realism.md) | system | in-progress | ✗ | **双层 G + 能量自限**：结构 G 提供短暂瞬时机动，额外能量流失把飞机拉回持续 G；角点速度作为硬地板，禁止转弯把自己拖入失速死循环。代码与加载验证已完成，待手感验收和结构耗能调参。 |
| [systems/bomber-strike-missions](systems/bomber-strike-missions.md) | system | in-progress | ✅ | **阵营对称轰炸任务**：友军 B-1B / 敌军 Tu-160 共用指定航路 `INGRESS→LINE_UP→RELEASE→EGRESS`；每机 5 枚、0.22s 间隔，3.2s 下落，160m/75 伤害；战略硬目标仅接受其 `bomber_bomb` 通道。已实现，待实机 QA。 |
| [systems/strategic-hardened-targets](systems/strategic-hardened-targets.md) | system | in-progress | ✅ | **战略硬目标**：地堡、仓库、导弹井不可被战斗机锁定或常规武器伤害；150 HP，仅接受敌对轰炸机炸弹伤害，为护航/截击任务提供专属目标。已实现，待实机 QA。 |
| [systems/rotorcraft-combat](systems/rotorcraft-combat.md) | system | in-progress | ✅ | **旋翼机独立飞行/战斗模型**：平面速度与机头解耦；AH-64 在 500m 环以 180km/h 切向平移，7–11s 环绕后刹停悬停 3.5–6s，再恢复环绕；M230 40 伤害短点射，只攻 GroundUnit，三道防火禁止对空。CH-47 共享平飞/悬停模型但无武装。已实现，待实机 QA。 |
| [weapons/airburst-aa-gun](weapons/airburst-aa-gun.md) | weapon | approved | ✅ | **远距空爆高炮**：450m/s 三连发、220m/75 AOE、组/单发偏角封顶 7°/1.5°；爆点为白橙火光 + 黑灰烟团。陆基战区限一门；DDG 右舷 CIWS 已原位替换为 Flak（2VLS+1CIWS+1Flak，舰载冷却 6s），专项 bench 22/22，待实机视觉 QA。 |
| [systems/battlefield-visual-scale](systems/battlefield-visual-scale.md) | system | in-progress | ✅ | **飞机/舰船统一视觉尺度**：普通飞机用 `7.9×m^0.55` 压缩幂律保可读，高度倍率从旧 0.55–1.70 收敛为 0.85–1.20；CV/CG/DDG/FFG/SS 回到 0.5px/m 世界比例并重算挂点，航母 420→166.4px。已实现，待舰队 bench 与视觉 QA。 |
| [systems/enemy-pool-expansion](systems/enemy-pool-expansion.md) | balance | in-progress | ✗ | **玩家科技树敌机化 + 常规敌机池扩充**：覆盖 T1–T3 共 27 架；每机互斥归为 Gladiator/Lancer/Schemer，五角色池 + 最近三队防重复。独立敌版参数、Token 四档审计、轮廓家族、图鉴/i18n/debug/无线电与专用多锁均已落地；F-22 可1–3机、每机四锁，本体取 Su-35 普通敌机基线。70/70 数据回归通过；9 友机 + 17 指定扩池敌机压力样本为 146 FPS，待人工逐机 playtest。 |
| [systems/squad-xp-threat-balance](systems/squad-xp-threat-balance.md) | balance | in-progress | ✗ | **编队经验稀释 + 敌方警戒响应**：共享 XP 乘区 `2/(N+1)`；热度地板 `min(100,min(75,5L)+6(N-1))`；每僚机 +3 Token 响应、减员即时降 6 热度、敌方目标分散到直属小队。敌方后续出击规模按玩家 N 软倾向：单机玩家约 60% 遇单机，九机玩家约 60% 遇 3–4机队，每批再乘 0.85–1.15 乱数，绝不确定性镜像。公共规则已接线，Tab 表现与规模 bench 待完成。 |
| [systems/classified-card-pity](systems/classified-card-pity.md) | balance | done | ✅ | **4 级金色技能递增概率**：自然三轴三卡连续未见 `CLASSIFIED` 时，下轮金卡候选倍率按 `1 + 2×未出次数` 递增；普通三卡见金即清零，机型专属第四槽与奖励升级隔离。静态池标定 LV18 六轮期望 2.05 次、LV21 七轮 2.43 次；`attr_gates` 121/121、`sig_skills` 64/64、压力样本 146 FPS。 |
| [systems/zone-air-support-naval-safety](systems/zone-air-support-naval-safety.md) | system | done | ✅ | **战区友军空中支援 + 对舰水域硬闸**：对空/对地支援契约不变；对舰已增压为 1★ 4 FFG、2★ 2 DDG+3 FFG、3★ 1 CG+2 DDG+3 FFG，安全方案实际保留的全舰均为 TGT，继续执行 40px 全水硬闸。水域回归 26/26；63 单位压力样本 146 FPS。 |
| [systems/boss-clear-progression](systems/boss-clear-progression.md) | system | done | ✅ | **按各 BOSS 历史击败次数切换编成/机制**：初见为教学层；首败后 Wraith 接战追加 2 架雷达静默 YF-23 可选狙击支援，LADON 航母由 0CG+2DDG+6FFG 强化到 2CG+2DDG+8FFG，Mother Goose 解锁 MQ-111/112；MQ-111 激光保留减速并累计消耗导弹拦截 HP。历史次数 ≥2 暂沿用强化层 1，等待后续设计。 |
| [systems/friendly-asset-aggro](systems/friendly-asset-aggro.md) | system | done | ✅ | **玩家触发的友方据点牵连交战**：已解放机场 2000px / 友军航母 2500px 内由当前操控机激活，退出圈 +500px 持续 8s 才解除；只从 6000px 内敌机按 `H<2→0 / 否则 min(3,max(1,floor(H/3)))` 限额分流，主 BOSS/队长/事件指令不拆，新增目标来源 `SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED`。机场打 SAM+AA，航母打 CIWS 挂点→弱点；友军航母专属 300 hull，敌方航母 BOSS 保持 1200。用户裁定四 CIWS 可全数压住 5/8 枚正向齐射，符合航母 BOSS 身份；真实弹道审计 14/14。 |
| [systems/doctrine-unlocks](systems/doctrine-unlocks.md) | system | done | ✗ | **战术学说解锁 + 槽位配件系统退役**（2026-07-27 用户拍板，07-28 落地）：整个"买配件加属性"的机库层下架——12 件数值件（机炮/导弹/雷达/电战 T1-T3）、`EquipmentPart` 资源类、槽位预算、随机货架、付费刷新、出击前机库场景（选机→直接出击）、`LoadoutLedger` autoload 全部删除；只留 **6 张 doctrine 词条解锁件**并搬进主菜单生涯商店（降级为 MetaShop 常量表，不再用 `.tres`；legacy loadout.cfg 一次性迁移，数值件按 D2 不退款丢弃）。局外成长收敛为单杠杆——**只买"这局能抽到什么牌"，不买"这局直接强多少"**。门控权威表：6 词覆盖当前技能表中的 **45 条**（stealth 11 / jam 9 / overload 8 / fear 7 / bloodlust 7 / chivalry 5，双词技 AND 语义；v3 playtest 修复：`headon_xp` 720 批漏标家族词 `chivalry` 无证进池，补标后骑士 700→800、全买 6500——**对头技双词惯例：head_on=触发词不门控，家族词才门控**）；渐进上架（嗜血+骑士买齐才放进阶 4 张）；定价 `100×门控技能数+300`（草案）。修复两处：①**战区奖励 NEXT_GEN 池补门控**（`evasion_stealth` / `fear_on_lock` 此前可无证获得）②**9 条 `sig_*` 签名技豁免二次门控**（保"每机一条专属"承诺）。**--bench=meta_shop 47 断言 + 回归门 40 项 PASS，差 playtest 定价校准** |
| [systems/career-shop](systems/career-shop.md) | system | in-progress | ✅ | **起手机解锁与生涯商店**（depends_on career-archive）：战场支援页新增第四项 3000 功勋永久授权 `support_airfield_sam`；购入后每局每座解放机场在基础 AA×2 后追加一次性 SAM×1。原 `airfield_sam_network` 局内技能删除；正式局查购买态，非正式局 fail-open；差 Godot 定向回归。 |
| [systems/career-archive](systems/career-archive.md) | system | done | ✅ | **玩家生涯档案**（2026-07-26 用户）：跨局持久记录（user://career.cfg）分机型击坠（enemy_type 键+玩家小队归因过滤）/ BOSS 接战·击败 / 通关·阵亡·撤退·停机计数，作全局成长系统数据地基。两个玩法输出：①**BOSS 档案轮换**——生涯首遇固定序 雷斯中队→航母→Mother Goose、击败必换下一个、未击败 50% 概率推进、环绕循环（**MOTHER_GOOSE 借此正式入池**，此前 done 却一直池外刷不到）；地形过滤（CSG 要水面）顺延候选、轮换指针跟随实际刷出；②**成就样板 uav_hunter**——UAV 族累计 30 击坠 → toast + 忠诚僚机进战区奖励武器子池（此前不 roll；A-10 自带等其它渠道不受门控，缺省 fail-open 保 bench）。入档铁律：bench/boss_debug 局零写入、不持 Node 引用、脏标记低频写盘、主菜单删档已登记。**728 敌人图鉴批（v3，用户"档案显示所有敌人含杂兵与 BOSS、打败过就有计数"）**：新增 §2.6 呈现层——原「王牌档案」页泛化为**敌人图鉴**（主菜单入口；34 条目 5 分组=19 空中/3 非战斗机群/3 地面/6 王牌/3 BOSS；统一"击败即解锁"语义：0 杀=剪影 ???、遭遇过附"它认识你了"；右侧 ×N 计数 + 收录进度；王牌额外解锁 lore/徽章/首破日期，ORION 预告下一架机号）；数据层补**逐型地面计数** ground_by_type（sam/aa/radar，旧档兼容）；收录边界裁定（王牌/BOSS 专属机型与舰船不单列）；防腐烂 13 断言（id 对齐真实 type_tag/AceSquadProfiles/BossRegistry、无漏收录、三语齐全）+ `type_tag_of()` 静态化收口机型标识。**728 游戏信息手册批（v4，用户"再写一个档案库写清所有机制，与图鉴分两类"）**：§2.7——资料库改**双分类页签**（敌人图鉴 / 游戏信息）；手册 7 分组 47 条（鼠标每个操作/键盘全键位含 E 加力充能数值/小队指挥语法/飞行/武器"除BOSS外一发即杀"/一局流程/情报）；**Tab 小技巧不复制文本，条目 `tip` 字段复用译文**（单一数据源+bench 对齐断言）；修 TACTICAL_TIP_WEAPON_SWAP 过期键位。**新增 CSV 列数断言**揪出并修复 36 行含逗号未加引号的译文错位（含 2 行历史遗留长期截断）。**--bench=career_archive 48 断言 + 回归门 42 项 PASS；§0 已获用户批准，差 playtest** |
| [systems/airfield-liberation-zones](systems/airfield-liberation-zones.md) | system | done | ✗ | **机场解放战区**：羽田/木更津/調布 三机场开局＝敌占战区（固定地标，独立于随机 A–G）。地面 1 SAM+2 AA＝TGT，打光即解放；升空迎战规模按**当前热度**定档（heat<34→1★/<67→2★/≥67→3★，读 `_roe.heat`）。解放奖励＝机场本身：圆心开**一次性**友军补给点（降落=回血/进化/僚机）+ 解放即刻**渐进**刷出 ALLY 防空伞（每 4s 一个，不 dock 门控）。**不碰 BOSS**（BOSS 早为纯时间闸 600s，ZoneData 旧"打够 3 次解锁"注释作废）。附带修 Tab 奖励块死路径（新奖励字典无 desc/category → 恒显"生存"死词，改按 kind 渲染）+ 去飞行员耐力废提示。**数据层单测 22/22 + 回归门 37/37 PASS，差 §5 playtest** |
| [systems/circle-cut-entry](systems/circle-cut-entry.md) | system | draft | ✗ | 圈外切入 CIRCLE_CUT（第三方支援射击几何，**敌我同享**）：队友被咬进转弯圈时，第三方不再汇入圆凑车轮战 —— 解目标转弯圆（复用 lag_pursuit 公式）→ 站位圆外 1.8R/领先相位 105° → **弧上前置解**横穿射击（局部修复"前置解无转弯率项"）；触发=目标的目标是我队友且 bank>40°×1.5s，滞回 40°/25° + 2s 再入冷却；友方僚机反咬与 Wraith PRESS 收网共用。**待 review** |
| [systems/boss-hunter-doctrine](systems/boss-hunter-doctrine.md) | system | done | ✅ | **BOSS 猎手准则 v5**：废除 `ANCHOR_HOLD`，ENGAGED 后持续追玩家；出生点位于玩家机头前方 12km，BOSS 圈跟存活成员质心。飞机类 BOSS 采用**双层世界边缘收容**：`AceSquad` 2000px 软返场 + `SurvivorSpawner` 40px 触线前物理硬护栏，绝不进入边界外黑区；仅守世界外框、不是锚点 leash。**2026-07-29 用户统一接战时机**：全部 BOSS 在 spawn 后立刻走表演导演 `<boss_id>_arrival`，镜头回玩家后立即 ENGAGED；旧进圈/贴近/被锁/受伤 T1~T4 退出主流程，缺序列 fail-open 直接接战。CSG 猎手性由最多 8 架舰载机承担；Mother Goose 巡逻环跟随玩家。附带 `BossEncounter.set_player_ref()` 活引用契约与 CSG 水面摆位/承伤规范。 |
| [bosses/wraith-squadron](bosses/wraith-squadron.md) | boss | done | ✗ | WRAITH 中队（F-47）战术规格，depends_on ace-squadron-tier。目标=**本作最强敌人之一，强度来自四机协同的两难而非数值**：KNIGHT×2 逼你转弯 / SNIPER×2 惩罚你转弯。**阶段 1~3 全落地（2026-07-22）**：①角色真实化 `AceRole{KNIGHT,SNIPER}`（取代 `combat_specialty` 只写不读 + `f47_role` 只读不写两个死 meta），KNIGHT 转身对抗 / SNIPER `bvr_only` 站位带 4~6km ②**队级战术状态机**（独立模块 `wraith_tactics.gd`，Wraith 专属窄井）PERCH 高位 → **BRACKET 诱敌包夹**（BAIT=二号机**不开火**、拉到玩家机头前 3000m 保持在雷达锥内；三翼经**复用命令轮盘的包围轴通道**从 ≥60° 离轴方位切入；咬住 4s 收网）→ PRESS（15s 完全放手 BFM）→ RESET（8s 脱离+爬升）四相闭环 + **退化检测**（平均机头偏角 >50° 持续 6s 强制重整，根治共速绕圈死锁）③执行精度失误（拆出 `gun_aim_error_enabled` 根治**全部敌机零瞄准误差**、王牌枪法 0.85 → ±1.2°、25% 减速迟滞 0.6~1.2s）。**冲突裁决**：SNIPER 原定 `aggression 0.75` 违反 tier 铁律，判 tier 赢——"不贪战"改由 BVR 站位（空间行为）表达。**--bench=boss_hunter 97 断言 + 回归门 34 项 PASS，差 §5 playtest** |
| [bosses/poltergeist-squadron](bosses/poltergeist-squadron.md) | boss | done | ✅ | POLTERGEIST 中队（CSG 二阶段 F-14）队级战术。由 playtest log 20260724_004256 驱动（母舰弹射的 F-14 陷入共速绕圈死锁：KNIGHT 全程 0 开火、绕圈 ~60s、机头钉 ±90°、飘出战场）。根因=`PoltergeistSquad` 有 `EngagementSpeedGovernor`（修速度几何）但**缺队级战术逃生层**。**Poltergeist 专属解法**（不抄 Wraith 全队 RESET，因性格相反=誓死不退）：**死锁单机换手（Relay Break）**——机头偏角 >55° 持续 4s、距玩家 ≤4000m → 只把**最咬不住的 1 架**拽去爬升 HIGH + 背离拉开 2200m 重整 3.5s、其余继续压；**同时换手上限=1**（灵魂：绝不两架一起变慢变傻）。独立模块 `poltergeist_tactics.gd`，走 AceSquad `_tactics_*` 钩子。**2026-08-01 出界回归**：继承 AceSquad 世界边缘收容，不恢复锚点归巢。**--bench=poltergeist_tactics 9 断言 PASS，差 §5 playtest** |
| [bosses/mother-goose](bosses/mother-goose.md) | boss | done | ✅ | Mother Goose 飞行翼母舰：10 挂点 + 弱点、JAM 力场、指定猎杀、UAV 蜂群、VLS 齐射、MQ-X 精英 |
| [enemies/snowblind](enemies/snowblind.md) | enemy | in-progress | ✗ | **SNOWBLIND「雪幕」纯支援 Schemer**：Sentinel 固定基线、无武器/flare/等级缩放；携 2 架当前响应等级动态护卫。4000m 单 mesh 实体风雪层在圆心显示不可交互本体轮廓，真实实体创建当帧即隐藏；直属机入圈整队显形、4500m/2s 复隐滞回与跨边界双向停火已落地；待 Tab 表现、坍塌演出与人工 playtest。 |
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
| [skills/close-range-lock](skills/close-range-lock.md) | skill | done | ✅ | **近距捕获**：稳定级斗士全队技能；主雷达锁定速率随距离线性加快，雷达边缘 ×1、半程 ×1.5、贴身最高 ×2；不改静态 lock_time，不影响副武器锁定。`skills720` 135/135，压力样本 134 FPS。 |
| [skills/bloodlust](skills/bloodlust.md) | skill | done | ✅ | BLOODLUST 嗜血家族：击杀/受伤触发 8s buff，基础回血 + 血怒护甲修饰卡（减伤/拉G/加速，经 SEAM-001 注入） |
| [systems/airfield-sam-network](systems/airfield-sam-network.md) | system | in-progress | ✅ | **机场防空网授权**：从局内技能池移除，改为生涯商店“战场支援”页 3000 功勋永久商品；购入后每局每座解放机场在基础 AA×2 后追加一次性 SAM×1，战损不重生；差 Godot 定向回归。 |
| [weapons/qmaam](weapons/qmaam.md) | weapon | done | ✅ | QMAAM 副武器槽近距格斗弹：宽锁定锥 70° + HOBS + 60G 发射后不管，自动补刀狗斗侧面目标；副槽机制完整 |
| [weapons/gun-burst-fire](weapons/gun-burst-fire.md) | weapon | done | ✅ | 飞机机炮改梭射：burst_count=10/梭，梭内 3.3× 密度；友方平均射速守恒；所有敌方 Aircraft 一次机会只打一梭、末发后停火 3.0s，堵连续多梭秒杀；--bench=gun_burst 20/20 |
| [systems/survivor-loop](systems/survivor-loop.md) | system | done | ✗ | 生存模式核心循环：10 分钟战区→BOSS 阶段、Token 经济、加权刷怪、XP/升级、出界时间税；★含扩展接入图。**v2（2026-07-28）等级通胀整治：XP 指数 1.15→1.3 + Adds 等级计价废除（Tu-160 80/AH-64 50/CH-47 40 普通公式）——平均局 LV18~22、顶级机不保底，差 playtest**。**v3（2026-07-28）出界补给时间税 15→30s + §4.4 敌人作战高度分档（18 型 LOW/MID/HIGH 权重 + 巡逻高度随档 1500~3000/4500~6500/8500~11000，未登记类型维持均匀随机）+ 修 F-47/F-14 Poltergeist 漏进常规刷怪** |
| [systems/first-run-tutorial](systems/first-run-tutorial.md) | system | in-progress | ✅ | 新存档基础教程补 **E 加力用途/禁攻代价** 与 **双击敌机突击**；首次拥有僚机时按实际固定号机提示数字键接管，只有成功切到另一架飞机才永久消失。代码与静态回归落地，差三语实机视觉验收。 |
| [aircraft/a-10](aircraft/a-10.md) | aircraft | done | ✅ | A-10 Warthog：T2 厚甲机炮平台，默认只有底线机炮/导弹/热诱弹，**不自带火箭**；Hydra 70 仅能从战区奖励取得。旧基础/实验变体与战区支援 A-10 同样零火箭。 |
| [systems/event-system](systems/event-system.md) | system | done | ✅ | 剧本系统：GameEvent + EventDirector + AIDirective（6 verb）；BOSS 事件三相；★含扩展接入图。**v2（2026-07-28）事件目录去腐**：在役子类补齐 BossEncounter / AwacsSupport / AceReinforcement / OrionNemesis（EscortConvoy 已删除），新增 §3.1 **ADBS 随机事件体系**（教程轰炸机 / 城区直升机 + 护卫反应 + 受击散开 + 全歼 3 架 → 作战时间 +20s） |
| [systems/map-system](systems/map-system.md) | map | done | ✗ | 地图系统：±7500px 边界 + 手画地理 + OSM 烘焙 + 底图三层；陆判 API；★含加新地图接入图 |
| [skills/buff_duration_rebalance](skills/buff_duration_rebalance.md) | balance | done | ✗ | 自身 buff 时长统一拉到 8s（INVUL/OVERLOAD/FRENZY）；回顾型记录，未达到完整重建级别。 |
| [systems/squad-control-switching](systems/squad-control-switching.md) | system | done | ✗ | 操控切换：数字键 1–9 接管稳定 `squad_slot` + set_leader 换帅 + manual_control 休眠 AI + 打完再归队 + 白底/击落接管。**代码全落地，差 §5 playtest** |
| [systems/squad-cohesion](systems/squad-cohesion.md) | system | in-progress | ✗ | 小队凝聚学说（友+敌）：焦点开火（地/船/BOSS 饱和、飞机留自由机互掩）+ 维持阵型 + 防游走 leash + GUARD_REAR 守后 + 敌方成建制/随机阵型。**阶段 1-4 主体落地，差联调/调参/§5** |
| [systems/squad-ai-escort](systems/squad-ai-escort.md) | system | draft | ✗ | 僚机护卫：反杀咬长机者（engaging_me 定向扩展）+ 近长机评分加权。**仅阶段 1-2；守后半球由 squad-cohesion GUARD_REAR 覆盖，escort 自身阶段 3-5 未做** |
| [systems/battlefield-gravity](systems/battlefield-gravity.md) | system | done | ✗ | **战场引力——友军目标优先级三带**：由 log 20260724_222238（①僚机放弃包抄回编队）+ 20260724_222827（②BOSS 战跑去打 10~17km 外低慢直升机）驱动。核心=目标评分补一个"以当前主战场为中心"的空间锚，统一两病根。三带（加在可命中性 base 上，严格隔离）：①生存 `+100×threat01`（候选正在咬**当前操控机**，只对空）②任务 `+40`（BossEncounter 成员表实例判定 / 最近 triggered 战区，单槽 BOSS 优先）③顺手 `base×gravity_mult`（离锚 2000→6000px 衰减到 0.1）。引力锚=BOSS 存活质心/战区 center/兜底操控机，**隐形也可读**故 cloak 窗不破功。v2 复审三件套：**`ENGAGE_MIN_SCORE=0.15` 交战地板**（无地板则 argmax 仍选唯一远杂鱼，引力形同虚设）+ **leash 可行性门**（评分即拒追不到的候选，根治 45 次 engage↔rejoin 循环）+ **SURVIVAL_STICKY=8** 带内防横跳。两整合面：A 评分治② + B 泛化 scan_leader_rear（锚操控机·常开·≤2 机回防）治①。**阶段 1+2 已落地**（ObjectiveContext+面A三件套 / 面B `try_defend_protectee` 常开回防≤2机 / `leash_anchor_and_limit` 三态松绑）：target_sel 35/35 + fire_discipline 10/10 + rejoin 指标一致 + stress_40 开销在噪声地板 + 双校验 ✓；**余：物理步进 sim 断言（playtest 前）+ 可选 BOSS 期杂兵刷新收敛 + playtest 调参** |
| [systems/rts-command](systems/rts-command.md) | system | done | ✅ | RTS 指挥（独立模块 SquadCommandController + 参数 Resource）：战术地图航点/战区边缘巡航 + 到点自动交战 + **玩家命令逐机持久铁律**（commanded_target 跨 1-4 切控、AI 不得覆盖；跟打僚机继承命令优先级，普通归队不得覆盖）+ 右侧开关；自由僚机切目标细则归 target-engageability-selection |
| [systems/waypoint-fire-control](systems/waypoint-fire-control.md) | system | in-progress | ✅ | 航点移动机会火控（2026-07-31 用户确认分阶段）：阶段 1 已让亲控机/玩家编队僚机在不写 `combat_target`、不改变航线时复用现有严格导弹齐射过滤；锁定/包络/坡度/滚转/离轴/超杀门全部不动，`waypoint_fire` 27/27 + 相关行为回归 + Lv15 编队压力样本已通过。阶段 2 放宽数值未批准；余 Sentinel 有渲染手动验收。 |
| [systems/target-engageability-selection](systems/target-engageability-selection.md) | system | done | ✗ | 目标选择改"可命中性"评分：对正度/包络/锁定(封顶)/邻近四因子 + 承诺火力超杀让路（**机炮优先豁免：不降权/不换目标**）+ 守后优先(rear_threat_score)；根除锁定 runaway。**代码落地 + 自动回归，差生存 playtest 调参** |
| [systems/wingman-escort-evasion](systems/wingman-escort-evasion.md) | system | done | ✅ | 僚机护卫规避：玩家按 E 时僚机不再无脑散开——被真威胁才逃，否则召回编队待命 + 投护卫 flare 替长机挡追它的导弹（escort_cover_active 与 evasion_mode 解耦；护卫 jam=0.70×近度，范围 800m）。**代码落地、flare bench 9/9，差 §5 playtest** |
| [systems/afterburner-mode](systems/afterburner-mode.md) | system | done | ✅ | 加力模式（规避模式资源化改造，**充能制/电池模型**）：小队能量池（上限 6s / 被动 0.2/s ≈30s 充满 / 击杀 +0.8s / 开局满格）——**有能量即一键启动**（不必满格）、激活中 1.0/s 实时耗能、耗尽自动结束、玩家再按 E 提前关闭保留余量。激活期全队强 buff：100% 机炮闪避 + 90% 滚转甩导弹 + 禁攻击 + 满速地板；**眼镜蛇/J-Turn/胆大妄为统一 R 且三向互斥**（当前操控机手动且不依赖加力，AI 僚机受威胁自动）。**代码全落地 + i18n 三语，差 §5 playtest** |
| [systems/weapon-employment-doctrine](systems/weapon-employment-doctrine.md) | system | done | ✅ | 武器使用准则：僚机多武器时"什么距离用什么武器"的竞选规则（距离带+滞回+命中率优先）、全武器统一"机头指向路径提前点"瞄准语义（锥角=纪律严格度，电磁炮 ±3° 最苛）、机动跟随主武器（railgun LINE_UP 直线充能 intent）+ 电磁炮承诺弹道（指示线=发射线）。验收：MRM 命中 44%→79%（log 175843） |
| [systems/joust-attack-run](systems/joust-attack-run.md) | system | done | ✅ | 攻击跑行为原语：RUN_IN 对准进入火力窗（两段速）→ BREAK 脱离拉开 → 折返循环；包络动态读装备 live params；修 MG 电磁炮 UAV"切向轨道 vs 机头对准"死锁（log 183044 全场 0 充能）+ 骑士型 Lancer（J-7/F-104/F-100/MiG-31）打带跑统一实现（取代 engage_duration 定时器）。bench 7/7 + playtest 手感确认（2026-07-05） |
| [systems/command-wheel](systems/command-wheel.md) | system | done | ✗ | 命令轮盘：按住左键拖拽呼出 marking menu（位置=参数/方向=动词，0.3x 子弹时间）。**操作语法：单点=只操控自机 / 轮盘=永远全队广播**。小队命令轮盘(按空地)=紧急集合+撤离此区(圈内径向散出 3km+20s 限时禁入圈、圈外不生效)+防守此区(**3km 区域清剿：全队自主搜敌/分头接战/击杀后接续，圈外不获取、越界停追、清空后继续守备**)+开关（自动交战/高度偏好三态循环/自动发射候选）；攻击轮盘(按敌机)=姿态（保持距离 STANDOFF 打带跑/突击 ASSAULT 锚定）×火力分配（集火=同目标+包围轴分离≥45° / 分火=锚点目标池内各自接敌+超杀让路）×阵型纪律开关，挂 commanded_target 铁律；**最新输入覆盖移动命令（单点→自机/轮盘→全队）**；移动指示线只画当前操控机（现状闪烁/僚机误显示 bug 列阶段 1 前置修复）；二级面板=开关显式选项（拉深选值）；左上红色取消槽（两轮盘统一）；悬停范围圈（撤离3km/防守3+1km等世界圈，仅空间语义命令）+ 轮盘下方教程说明条（WHEEL_TIP_* 三语）+ 激活压暗35% + 攻击轮盘目标高亮层；导弹/机炮优先搁置、高度"默认"三态评估后搁置；开关长期收束进轮盘。**代码全落地（阶段 1-4 + 收尾批）**：手势+执行端+二级面板+取消槽+范围圈+说明条+区域清剿+姿态分化[空中 joust 打带跑/面目标 surface pass]+火力分配[FOCUS 包围轴 ≥45°/SPREAD 池内各自接敌]+集合/撤离全力加速（command_sprint ×1.4 accessor）+撤离 20s 禁入区（决策过滤+圈框倒计时）+自动发射队级广播；--bench fire_alloc 15 / wheel_orders / surface_pass 20 断言，**回归门 20 项 PASS**。**只差 playtest** |
| [systems/formation-discipline](systems/formation-discipline.md) | system | in-progress | ✗ | 阵型纪律与齐射：队级开关 FREE 自由散开（=现状）/ TIGHT 紧密队形。**v1 已落地（2026-07-12 用户确认后实装）**：TIGHT 集火=长机独持命令目标、僚机全程编队跟随（整队进入/拉开由编队复现涌现）；**齐射触发器=长机开火**（玩家亲自扣扳机=全队齐射）→ 开窗 1.5s 临时授予僚机槽位内开火权（volley_fire_active 豁免编队防御清除）→ 到时回收=禁补射 → 停火 2s 再武装；ASSAULT 豁免（普通集火广播）。--bench=tight_volley 10 断言。剩：HUD 第 6 toggle（收束轮盘方向暂不做）/巡航收紧 leash/SPREAD+TIGHT/playtest |

| [systems/combat-effectiveness-metrics](systems/combat-effectiveness-metrics.md) | system | draft | ✗ | 战斗效能评估：交战记录 4 层指标（转化 FSR/执行 hit_rate/结果 TTK/对手规避+CapIndex 差距）+ 两轴 Offense/Defense 评级 + bench 对位矩阵；核心解决"快机打不中慢直升机≠直升机强"。**仅 §1~§6 草稿，待 review** |
| [systems/aircraft-evolution](systems/aircraft-evolution.md) | system | superseded | ✗ | **历史高层骨架，禁止继续派生实现。** 当前权威已拆分到 zone-reward-docking、aircraft-evolution-tree、evolution-attribute-gates 与 inrun-weapon-inventory。 |
| [systems/aircraft-evolution-tree](systems/aircraft-evolution-tree.md) | system | done | ✅ | **v8 已落地**：43 节点 / 124 边，EA-18G（T2 电战）与 F/A-XX（T4 斗士型攻击）已接入；Tier 数量 4/16/8/7/8，永久不可达边=0。 |
| [systems/evolution-attribute-gates](systems/evolution-attribute-gates.md) | system | done | ✅ | **v16 已落地**：全部节点使用具体逐轴门槛，F/A-18E `any` 保留；8 点内全分配枚举覆盖 124 条边，永久不可达边=0。主 HUD 经验条上方以固定 400×18 三格计数器常驻显示斗士/骑士/策士里程碑进度。 |
| [systems/evolution-growth-benchmark](systems/evolution-growth-benchmark.md) | balance | done | ✅ | 用户取消 320 局实战并改为参数验收；斗士 T2–T5 已按炮伤倍率 1.30/1.40/1.50/1.60、射程 1200/1300/1400/1500m、开火半角 8/9/10/11°、瞄准 0.65/0.70/0.75/0.80 逐档增强，43 机静态审计“通过”、违规项 0，任务完成。 |
| [systems/multi-target-missile-locks](systems/multi-target-missile-locks.md) | system | done | ✅ | 多锁多射从 on/off 改为可叠加锁数：基础 1；稳定级骑士普通卡每层 +1（最多 3，全队）；F-22 隐身 +2；导弹蜂群全队 +3；骑士 8 点 +1。齐射覆盖数=`min(有效锁数,合法目标,弹量)`，每轮正常冷却。斗士装甲里程碑现位于 4 点；策士 3 点 XP +10% 不变。 |
| [systems/inrun-weapon-inventory](systems/inrun-weapon-inventory.md) | system | draft | ✅ | 局内武器库（2026-07-19 用户重点调整）：特殊武器（电磁炮/激光/忠诚僚机/QMAAM/漂浮雷）=**局内玩家外部装备，到手即永久、换机/进化全继承（含强化）**；获取=签名机型首驾入库+战区奖励；底线武器（机炮/导弹/flare）仍随机体；**作废**"武器绑机型不继承"（06-28）与 meta-progression"局外多武器 loadout"；重放与属性门槛玩家层同机制。开放点：火箭归类/挂载上限/重复补偿。**核心落地（进化前快照/换型补挂/升级卡重放防双叠）+ 断言并入 attr_gates，差 结算清单分段/Tab 图标行/debug 勾选** |
| [systems/aircraft-signature-skills](systems/aircraft-signature-skills.md) | system | approved | ✅ | v8 扩为 43 条：新增 EA-18G「伴随压制」（僚机共锁持续 JAM）与 F/A-XX「穿透打击」（本机机炮击杀 5s 隐身、20s CD）；其余 41 条语义不变。 |
| [systems/aircraft-signature-progression](systems/aircraft-signature-progression.md) | system | approved | ✅ | 扩为 43 条机体专属许可；Tier 数量 4/16/8/7/8，全购价 30000；第四槽 30% / 每机每局一次规则不变。 |
| [systems/skills-720-rework](systems/skills-720-rework.md) | system | done | ✅ | 720 技能整改批（用户逐条改表）：**"+1 轴进度"系统**（选卡奖励里程碑进度非技能点，13 条；预留档通道；cap 2 待二选一）+ 归属词汇 v6（王牌层为 AoE 控场强技收敛回归/A10 限定=exclusive_to/需要词条=requires_skill/队级单实例 1→8）+ 新增 27（含 R 键手动闪避/僚机阵亡触发×3/技能计数缩放×4/轮盘联动×2）/ 改动 ~35 / 移除 railgun_damage；实现对照四档（纯数据/复用钩子[加力充能·击杀归因·轮盘状态·recompute]/追加功能/新机制）；排查双项（数据链生效+僚机锁可射、寒蝉友军 JAM bug）；任务拆分 T0~T6。**待 review** |
| [systems/squad-upgrade-ownership](systems/squad-upgrade-ownership.md) | system | draft | ✗ | 升级归属**绑机型**：三归类字段(ownership/affinity/flavor/inheritable) + 全 41 技能归类总表(GLOBAL/GUN-A10/EW-F16/MISSILE/UNIVERSAL/HARDWARE) + 同型共享/战损不丢 build + 僚机生产+build 重放 + 编队上限 9/1-9 接管 + Session 内 Roguelike。**待 review；待拍板硬件继承 A/B** |

| [systems/ui-transition](systems/ui-transition.md) | system | in-progress | ✅ | 表演导演系统（转场/镜头/时间/演出）：TimeAuthority + SequencePlayer + time/camera/overlay/panel/radio/stage/actor/audio 通道。升级急刹 0.44s；所有注册 BOSS 生成后立即使用统一 arrival 系统。Wraith 保留 6.7s 四机交汇专属分镜；CSG 为旗舰镜头+3 句无线电+回玩家（6.7s）；Mother Goose 为母机镜头+2 句无线电+回玩家（5.1s）。演出收尾立即 ENGAGED；缺序列或被 UI 转场覆盖时 fail-open 接战并亮血条，统一受 7s 硬上限与时间/舞台/演员三类泄漏兜底约束。 |
| [systems/pause-menu](systems/pause-menu.md) | system | done | ✅ | 暂停菜单：ESC 从"无确认直接销毁战局回主菜单"改为**冻结全场 + 确认页**（继续作战 / 返回主菜单），顺带补上游戏本来缺的暂停能力。时间控制全部复用表演导演 `panel_in`/`panel_out`（不直写 `get_tree().paused`）；面板 `PROCESS_MODE_ALWAYS` 自理"ESC 关闭"（硬暂停期间 survivor_mode 收不到输入，与战术地图同一分工）。ESC 优先级表：战术地图 > 选卡（不响应）> 暂停菜单开关 > 结算态直退 > 打开暂停菜单。**不改结算语义**——中途退出仍不结算功勋，只在确认页明写后果 |
| [systems/combat-feed](systems/combat-feed.md) | system | done | ✅ | 战况栏 / kill feed：左上角实时"谁用什么武器击坠谁"，最新 5 条、HOLD 5s+淡出 1.5s、友绿敌红配色；EventLogger.kill_recorded 信号桥接、复用既有击杀归因。同批放宽镜头缩放上限 ZOOM_MIN 0.4→0.2 |
| [systems/meta-progression](systems/meta-progression.md) | system | draft | ✗ | 局内/局外彻底分层，轴=**槽位装备 vs 玩法深度**：~~局外（功勋持久）解锁机型武器/装备 loadout~~（**2026-07-19 局外多武器作废**，武器改纯局内继承 → [inrun-weapon-inventory](systems/inrun-weapon-inventory.md)；局外层新用途待本 spec 自身修订）；局内（roguelike 清零）= 玩法深度 + 进化 + 三轴属性/武器库。**方向 stub 待重写** |

| [systems/ace-system](systems/ace-system.md) | system | draft | ✗ | 王牌系统：长机当前机=ACE（开局默认）；进化分王牌/僚机两类对象（王牌线=进化树深度 / 编队线=数量+品质+loadout 轻成长）；ACE 阵亡由击坠最高者继任、旧加成不继承。调和"单机英雄进化 vs RTS 编队"。**核心已定，资源分配/继任边界待推敲** |
| [systems/ace-rotation-balance](systems/ace-rotation-balance.md) | balance | in-progress | ✅ | **王牌新局随机轮换 + 60~90 秒标准击破预算**：六支非宿敌队统一 240s 入池，新局 Fisher–Yates 无放回洗牌，连续两局首队防重复；建立 DU 量纲（机体/必躲 flare/确定性防御动作各 1 DU，1 DU=5s）+ access_s，六队预计 70~80s；WhiteTea 为 9 DU/70s。事件日志记录预计与实际 combat TTK。静态回归已接，差每队 5 局实测与压测。 |
| [systems/ace-squadron-tier](systems/ace-squadron-tier.md) | system | in-progress | ✗ | **敌方**王牌中队分层标准；六支非宿敌统一 240s 洗牌轮换，默认 flare=1，VULTURE 为量化后的 0 flare；WhiteTea 登记首个 `gun_lancer` 纯机炮骑士与一次性 J-turn。其余 tier 契约（LOD 豁免、无缩放、极强攻击欲、BOSS 子集、包装/血条/档案）不变。 |

| [systems/early-game-uav-rework](systems/early-game-uav-rework.md) | system | done | ✅ | 前期敌情与 UAV 更名改造（2026-07-26 用户四件套，v2）：①无人机更名——机炮 UAV=**MQ-109**、导弹 UCAV=**MQ-110**（显示名/呼号/i18n，内部标识不动；v2 订正 MQ-110 **不退役**，与 F-4E 并存）②**elite 战区任务移除**（Sentinel 作为战区目标太弱；E 区限制改 naval/squadron）③Sentinel+MQ-109 小队=普通地图刷新敌人（COMMANDER 概率 0.06/0.12 上调）+ **战区驻守障碍**（25% 概率带 6-10 MQ-109 驻守、非 TGT、驻守预算减半、全场唯一）④新增 [f-4e](enemies/f-4e.md) 有人导弹杂鱼填前期空间。**代码落地，差 playtest** |
| [systems/battlefield-tempo-pass](systems/battlefield-tempo-pass.md) | balance | done | ✅ | 战场节奏批（2026-07-22 用户三联反馈：冷场/XP 少/缺进场敌机）：**拦截波**——hunter 配额缺口 ≥2 时本波旅途增援改为"玩家前方 ±90° 扇区边缘入场 + 航点持续指向玩家、永不 ONSTATION"，由既有 ROE 感知/hunter tick 自然收编（单杠杆自平衡，冷场必来/热闹必不来）；**新战区 F 荒川北岸 ground r2200 / G 千叶中部 air r2500**（几何自检过 1500/2000 约束，候选池 4→6）；刻意不动任何热度旋钮保 density-pass 归因。**已落地 + test_map_expansion 全绿，差 playtest** |
| [systems/zone-reward-arsenal](systems/zone-reward-arsenal.md) | balance | done | ✅ | 战区奖励四类重定档；七件武器含 ESM，四起手机型各对一件武器 ×2；六项次世代含连锁弹头且不存在独立穿透弹头；航母第 4 次保底，僚机最多 2 架且不增加战斗等级；F6 可逐项直发。 |
| [events/ace-whitetea-fck1](events/ace-whitetea-fck1.md) | event | in-progress | ✅ | **WhiteTea**：F-CK-1×3 中期纯机炮骑士；240s 入统一王牌轮换；逐机 joust 打带逃，每机 1 flare 后解锁一次性 J-turn；独立 4×5 受控短梭，三机同步首梭不秒满血玩家；呼号 Tea/Cola/Bottle；Debug 复用正式事件并立即显示分段血条。 |
| [events/ace-orion](events/ace-orion.md) | event | done | ✗ | **宿敌 ORION / 猎户座（2026-07-27 用户）**：原创机体 Cre ×1 单机——tier §3.8 宿敌条款唯一实例（六项豁免：单机/静默登场无任何提示/伪装普通敌橙/跨局成长/机号即呼号 Cre-XX/无时间奖励）；只死咬玩家**当前操控机**；被击坠全局计数 +1（CareerArchive），机号 Cre-01→99 进位；成长档位表 5 档（初始敌机级别→顶格 AI 1.0+闪避 0.50+满武装，性能 ×1.0→1.4，武器 机炮→导弹→ace_gun→QMAAM）；中期 ~300s 独立轨道每局一次、不占轮换名额；**728 核心落地**：enemy_cre+OrionNemesisEvent（独立轨道 300s/静默/死咬操控机/BOSS 闸撤离/击坠生涯+1）+档位表纯函数 bench 断言；落地修订=XP 统一 100/档IV QMAAM 暂以导弹数替代/血条待拍板。**差 playtest** |
| [events/ace-gimmick](events/ace-gimmick.md) | event | done | ✗ | **GIMMICK / 把戏**：F-16×2 狙击（BVR 4~6km）+ Mirage 2000×2 斗士的远近夹击；统一 240s 洗牌轮换；8 DU+30s access=预计 TTK 70s；洋红涂装/双箭头徽章/BLUFF~SWITCH 固定呼号。**差 playtest** |
| [events/ace-goofighters](events/ace-goofighters.md) | event | done | ✗ | **GOOFIGHTERS / 怪火**：Su-47×2、格斗弹+一次性眼镜蛇；每机 1 flare 后解锁 Cobra，合计 6 DU+40s access=预计 TTK 70s；统一 240s 洗牌轮换；深紫罗兰涂装/WISP+ORB。**差 playtest** |
| [events/ace-2ndwave](events/ace-2ndwave.md) | event | done | ✗ | **2NDWAVE / 第二波**：Teacher F-4E 斗士 + F-15×4 学员骑士混编；Teacher 顶格 AI/0.50 机炮闪避，2026-08-01 改为 1 flare 且不再叠持续 evade；全队 10 DU+20s access=预计 TTK 70s；统一 240s 洗牌轮换。**差 playtest** |
| [events/ace-lancer-mig31](events/ace-lancer-mig31.md) | event | done | ✗ | **VULTURE / 秃鹫**：MiG-31×8 横列高速掠袭，纯导弹无机炮；2026-08-01 全员 flare 1→0，以 8 DU+40s 追击 access=预计 TTK 80s（旧 16 DU/120s）；统一 240s 洗牌轮换；6 波弹尽撤离。**差 playtest** |
| [events/ace-support-squadron](events/ace-support-squadron.md) | event | in-progress | ✅ | **MARATHON / 马拉松**：Su-35×5 斗士，1 flare/架、猩红涂装、PACER 长机；10 DU+25s access=预计 TTK 75s；统一 240s 洗牌轮换；全灭 +60s 作战时间。已购 `support_ace_f15` 时事件入场同步派 2 架只对空 ALLY F-15，王牌事件终态后物理撤离。**差 playtest** |
| [systems/zone-reward-docking](systems/zone-reward-docking.md) | system | done | ✗ | 战区奖励攻克即领；停靠仅全队回血与进化。航母限 2 次登舰且第 4 次奖励 roll 保底；僚机奖励同型最多 2 架、不增加战斗等级；四类奖励与七件武器的数值由 zone-reward-arsenal 统一负责。 |
| [systems/60km-density-pass](systems/60km-density-pass.md) | balance | done | ✅ | 60km 密度调优（playtest 反馈"敌人少"）：战区半径 A/C/D 3500·B 3000·E 2500 + 盘旋环随半径撑开；任务规模（地面 TGT 3+3/4+4/6+6、中队 4/5/6、驻守预算 12/22/42×1.10^L、精英护卫 6-10）；丰富化（★★+ 雷达站 TGT 削预警层次、中队长机高一档）；热度（token 8+1.8L cap55、间隔 32→18、上限 36/48、驻防 3 队、hunter max(3,2+L/2)）；附带修教程轰炸机锚点（扩图后 10.9km 远→出生点前 3km 派生）。**回归绿，差 playtest+压测** |
| [systems/reinforcement-ingress](systems/reinforcement-ingress.md) | system | done | ✗ | 增援入场：旅途增援改"边缘中队涌入 → 中央锚点驻空绕环 → token 饿着时 EGRESS 物理飞离（被打回头应战）+ 开局驻防 2 队"，根治双根因（离屏刷怪无来路 + FAR_FREEZE 750px 刷出即冻结原地杵）；hunter/token/选型不变；含离屏冻结豁免策略（transit/egress 豁免、onstation 闲置可冻）。**阶段 1~4 代码落地 + 无头回归绿，差 playtest/性能验收** |
| [systems/aa-fire-awareness](systems/aa-fire-awareness.md) | system | done | ✅ | 僚机对地面机炮火力警觉：①被 AA/CIWS 机炮命中 → 打断 SETUP/RUN 强转 EGRESS + 机头转出 45° 后 AB 全速脱离（EGRESS 加速为敌我通用改进）；编队/巡航被打不脱队只 AB 直线冲刺 2.5s；②STANDOFF inner 环抬到目标对空火力半径 ×1.25（CIWS 舰 2200→2500m）+ F-Pole：弹在飞/TEAM_OVERKILL 时不压入、环外 crank 等命中。单杠杆=只对"被命中"反应，不做火力圈预判扫描。**代码全落地 + --bench=surface_pass §E 8 断言（28/28 绿），差生存 playtest/压测**。**v3（2026-07-28）CIWS 真弹周期 3→2**（有效伤害射速 ~11→~16.7 Hz、拦截 DPS ×1.5；仍是真实弹道拦截非概率判定，散布/命中半径/距离衰减不变，60HP 导弹仍需 6 发真弹）——本 spec 常量一个未动，但舰船火力圈停留成本上升 |
| [systems/surface-attack-pass](systems/surface-attack-pass.md) | system | done | ✗ | 对面攻击 pass 循环：地面/舰船静止目标做俯冲攻击跑（SETUP→RUN→EGRESS + 最小转弯半径守卫，根治"机炮打 SAM 原地绕圈"死锁）；姿态 STANDOFF（导弹远距 standoff 环脱离不进 AA）/ ASSAULT（机炮贴地俯冲穿越）分流，默认由武器竞选推导（有弹保持距离/无弹机炮），预留 command-wheel 姿态覆盖钩子。相位状态位走 `_apply_tactical_plan` 回写、planner 保持纯函数。**全量落地 + 无头行为 sim `--bench=surface_pass` 9/9 + bfm_intent 102/102 + all 18 项绿，差生存 playtest** |
| [systems/slow-air-target-pass](systems/slow-air-target-pass.md) | system | done | ✅ | 慢速空中目标（直升机）交战 pass：与 surface-attack-pass 共用同一台相位机，只换包络常量与终端瞄准点。根治用户报的"绕好多圈打不中 / 锁定上了却不发射"——四层叠加根因（几何极限环 / LOW 档 4.3s 锁定被出锥 0.3s 清零 / 满锁被 off-axis 发射门拒发 / **锁定即压坡到 35% 导致再也转不进发射锥的通用死锁**）。分流置于优先级 4.5（必须早于 overshoot/boom-zoom 等只对快机成立的能量学规则）。**`--bench=slow_air_pass` 14/14 + all 全绿，差生存 playtest** |
| [systems/map-expansion](systems/map-expansion.md) | system | done | ✗ | 地图扩展 + 战区重排（**60×60km ×2 已手改落地**，用户二次复审决定保留）：主开关/出生点/60km 重烘焙（矢量+过渡底图）/战区 ×2 重排（B 落湾里经 land_mask 网格扫描修正 (6000,-11000)）；无头回归 `tests/test_map_expansion.gd` 全绿（几何 15/15 + 陆地占比 + BOSS 锚点）。**差 playtest（≥3 战区/局节奏）；编辑器整合退为后续 converter 吃现状，PNG=过渡资产** |
| [systems/ugc-editor](systems/ugc-editor.md) | system | draft | ✗ | 游戏内 UGC 编辑器 + 创意工坊：飞机/地图/编队可行性高（params 纯数据、JSON+user:// 惯例现成）；安全红线只收 JSON+数值围栏；P0 数据化→P1 地图编辑器（兼扩图工具）→P2 飞机→P3 编队→P4 本地分享→工坊（GodotSteam/mod.io） |
| [systems/map-editor](systems/map-editor.md) | system | approved | ✗ | 地图编辑器（UGC P1 细化）：格子笔刷前端 + 矢量多边形后端（marching squares+Chaikin+layer_dirty 懒烘焙保 1:1）；三区 UI（素材库左上/画布中间/工具栏笔刷橡皮线条）；9 图层含地形覆盖/建筑伪3D/云 mask；调色板全渲染色可编辑；官方图一键转换（数据本就是 JSON 直通）；**底图 PNG 退役**改纯矢量（性能预算 §3.5，官方图待编辑器重制）。**已定稿，待按 §6 五阶段实装** |

| [systems/radar-range-normalization](systems/radar-range-normalization.md) | balance | done | ✗ | 雷达距离规范化：诊断"卸配件仍远"（非残留 bug=基线+高度倍率×1.5+配件曾叠 ×1.725）+ 玩家三带（**电战>骑士>斗士**，T1~T5 带锚点 2200~5000，F-14 3600→2600 主诉求，X-13 全谱王冠不动）+ 41 机新雷达列 + 敌机六带迁移（常规封顶 4600，超者=拦截/王牌/BOSS/传感器特批）。拍板：高度倍率不动；功勋留、改装件退役（商品用户另批）。**数值全落地（玩家 40+僚机+敌 9）、三带走廊测试 38/38、回归门 39 项 PASS，差 playtest（波次进攻性+电磁炮体感）** |
| [systems/player-aircraft-power-curve](systems/player-aircraft-power-curve.md) | balance | approved | ✗ | v16 五档 43 机参数已落地；斗士 T2–T5 已补齐炮伤、射程、开火半角与瞄准的逐档下限，纯参数审计结论“通过”，射速与弹量维持共同基线。 |
| [systems/engagement-discipline](systems/engagement-discipline.md) | system | done | ✅ | 交战纪律 v2：无目标 AI 停火；基础机能量劣势会脱出；新增**属性感知狗斗画像**，按双方转率/半径/滚转/减速分 balanced/energy/tight。强 G 机保能量赢转率，强刹低失速机切内圈并减少无效脱离，僚机更早转入直接 BFM；不放宽机炮扳机。 |
| [systems/global-awareness-roe](systems/global-awareness-roe.md) | system | done | ✅ | 全图察觉与交战规则（ROE，v2 按 review 简化）：**中队级感知**（感知圈=长机雷达距离全向 + 被打即察觉 + 战区 datalink，15s 记忆；中队三字段 posture/aware/squad_target，不逐机算）+ 任务姿态五型（守区 leash=区+1500m 出圈停追 / 巡逻 leash 6km 含 30% 线路巡逻 / 狩猎全知 / 转场 / 撤离）+ **热度即难度**（heat 0-100 纯内部量不上 HUD，唯一输出 hunter 配额 round(2+10h/100)，静默基线复刻既有曲线、等级地板 min(75,5L) 载难度爬升）+ **第三方事件化三类**（护送直升机 A→B +40 功勋/架 / 机场防空 SAM+AA×3 停靠机场 / AWACS 南带往返 8km buff 区锁定×3·导弹×1.25；ALLY(2) 不可控 0 XP，航母存量收编）+ 阵营色板统一（FactionPalette **蓝=玩家直属/绿=中立·第三方**/橙红=敌；机体无 PNG，敌机 icon_color 审计 ×15 换暖色）+ IFF 收口（is_hostile_to 单 API，四类硬编码迁移清单）。**阶段 1~5 代码全落地**（roe 单测 33/33 + 回归门 21 项 + 30s 冒烟绿；落地修订 §8-v3：posture 派生制/事件察觉 2s 粒度/守区战区聚合/AWACS 无 flare/航母收编暂缓），**差 playtest + 压测**。**v5（2026-07-28）第三方事件回炉**：①**护送事件整体删除**（含 EVENT_ESCORT_* 三键）——奖励纯局外功勋 / Tab 图不画 / 无无线电 / 抵达即静默消失，玩家既找不到也没有局内理由去打（§2.6a 转为废弃记载 + 事件设计三占其二教训）；②**AWACS 轨道改绕当前战区**（选中战区 > 最近 AVAILABLE > 南带兜底；南退 2200px < 光环 4000px 是硬耦合）+ **在站 180s 定时撤离**（超时 90s 兜底，光环留到飞出）+ **进离场 scripted 无线电各 3 条** + Tab 光环改淡填充/粗描边/圆心点；**buff 数值不变** |
| [systems/radio-chatter](systems/radio-chatter.md) | system | done | ✅ | 无线电通讯（皇牌空战式）：屏幕上方"呼号 ▸ << 台词 >>" 两行版式 + 左右淡出渐变底 + Radio 总线电台底噪（该总线早已建好、此前从未被使用）。**核心契约=一次一条、绝不打断**（权重只管排队与满队淘汰）。**三层节流**：全局冷却(12s，跨 trigger) → 冷却桶(五条 RTS 回令共享) → 概率骰(ack 0.35，"偶尔出现"的主旋钮)。**两类无线电**：`scripted`(BOSS 登场对话)豁免全部节流必定播出且不占冷却账本 / `ambient` 受三层限制，未登记保守按 ambient。**说话资格门**：`no_pilot` 硬规则 + opt-in 机型白名单，无人机一律沉默。**数据全外置** `resources/chatter/radio_chatter.json`（台词 key/权重/冷却/概率/BOSS 序列/白名单），`chatter_lines.gd` 退化为零数值加载器，文本三语在 translations.csv —— 加台词不碰代码。8 类触发：BOSS 登场多句队内对话(**范例**，三 BOSS 各一套)/BOSS 交战/击坠回报/弹射/break/RTS 五令回应/敌方累计减员三档哀嚎/僚机归队。入队即快照呼号+颜色，不持有 Aircraft 引用。--bench=chatter 87 断言 + 回归门 25 项 PASS。**差音效素材 + playtest 调频度** |

<!-- 新增 spec 后在此追加一行。保持按 kind 分组、最新在各组顶部。 -->

---

## 待补 specs（重建缺口清单）

> ✅ **模板验证阶段已完成（2026-05-30）**：当前 9 种 kind（boss/enemy/skill/weapon/system/aircraft/event/map/balance）
> 各有 ≥1 个 reconstruction-grade 样板，模板与工作流已跑通。下一阶段是**批量铺开**（逐个把现有内容转 spec）。
>
> 以下内容目前**只在代码里**，是"靠文档重建"的漏洞。按优先级补 spec。

- [ ] **enemies/** —— 当前已有 27 份敌机 spec（含扩池常规机、af-03、f-4e 与 snowblind）；
      早期基础池、Adds 与部分 BOSS 专属单位仍只有 [enemy-index](../reference/enemy-index.md) + `.tres`，需继续补档。
- [x] **systems/survivor-loop** —— 时间制战区循环：10 分钟阶段、加权抽取、出界回血时间税（含扩展接入图）✅
- [x] **systems/event-system** —— GameEvent + EventDirective 剧本系统（含扩展接入图）✅
- [x] **systems/map-system** —— 地图边界 + 地理 + 三条流水线（含加新地图接入图）✅
- [ ] **skills/** —— 当前技能总量看自动生成的 [skill-table](../reference/skill-table.md)；已有少量单项 spec 与批量改造 spec，
      其余效果仍散在 `survivor_data.gd` / `skill_hooks.gd` / 常量与 i18n，需继续补档。
- [ ] **weapons/** —— 各武器 GunParams/MissileParams/RocketParams（现在 .tres）。已完成：qmaam（副槽）、gun-burst-fire（机炮梭射节奏）
- [ ] **aircraft/** —— 各主角机型档案（现走 PlayableAircraft 注入）。已完成：a-10（待补 f-16/f-14/x-02）
- [x] **bosses/wraith-squadron** —— F-47 王牌狙击小队已由 [wraith-squadron](bosses/wraith-squadron.md) 覆盖。
- [ ] **bosses/carrier-strike-group** —— Ladon 战斗群 BOSS（编成/HP 1200/CIWS/弹射/二阶段衔接）。
      现状散在三处：CIWS 数值在 [aa-fire-awareness §2.1](systems/aa-fire-awareness.md)、
      舰队摆位地形校验与电磁炮对舰结算在 [boss-hunter-doctrine §2.5.1](systems/boss-hunter-doctrine.md)（暂寄）、
      二阶段 F-14 在 [bosses/poltergeist-squadron](bosses/poltergeist-squadron.md)、
      **F/A-18 弹射数值（开局 2 + 每 120s 补 1，整场累计上限 8，击杀不计价）在
      [survivor-loop §3.2](systems/survivor-loop.md)（2026-07-29 暂寄）**。建档时把这几处整段迁走
