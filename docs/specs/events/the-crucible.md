---
id: the-crucible
kind: event
status: done
schema_version: 1
spec_version: 14
owner: user
depends_on: [systems/desert-theater, systems/ace-squadron-tier, systems/radio-chatter, systems/boss-hunter-doctrine]
reconstruction_complete: true
---

# The Crucible 王牌大混战

> 沙漠决战空域成为一座熔炉：17 支王牌中队与背叛的 Hound 雇佣兵双机从不同方向分批压入，场上始终保持最多 3 支活跃队伍；玩家击破一队后再补一队，直到活到最后并歼灭全部敌机。

## 1. 设计意图（Why）

- **身份铁律**：`The Crucible` 只是一场战斗及其主题名，不是角色、单位、中队或 BOSS；不存在名为 The Crucible 的说话者，也不存在 `CRUCIBLE-01` 一类呼号。
- **体验目标**：参考 B7R 式大规模王牌空战的味道，但不复刻其角色、台词或关卡；核心是多支具名 Ace 队伍同时交错、导弹与尾迹把沙漠天空填满。
- **独特机制**：本场决战由全部 17 支已实装 Ace 中队与 Hound-1/2 组成淘汰接力战；开场 3 队先进行 8 秒只在 Ace 队之间互选目标的真实混战，再把玩家纳入仇恨池。每次一队全灭后延迟 3 秒补入下一队。开局混战结束后每支活跃队只保留 1 名玩家猎手，其余成员维持队际混战；Hound 双机中由 Hound-2 优先担任猎手。个人当前击坠越多越能抢走常规 Ace 仇恨。
- **玩家目标**：没有护送、占点或逃脱副目标；玩家小队至少一机存活，并消灭全部 18 队共 73 架敌机即胜利。
- **Litmus 自检**：满足设计哲学 3「变化可见」、7「热闹战场」、8「机制独特 + 难度高 + AI 聪明」与 11「60 FPS」；不通过堆单体 HP 伪装成 Boss。
- **反模式规避**：不生成新的同质 Ace 机型；不让所有敌机只追玩家而失去混战；不以降低参战数量、停火或删除弹道换取性能通过。

## 2. 数据定义（What）

### 2.1 身份与地图

| 字段 | 值 | 说明 |
|---|---:|---|
| 内部 encounter id | `THE_CRUCIBLE` | 复用决战阶段注册与胜利结算的稳定技术 id，不表示存在同名 BOSS |
| 战斗标题 | `THE CRUCIBLE` | 三语均保留英文主题名 |
| 地图决战池 | `desert_railway_preview` | 与超级武器列车等权随机 |
| 决战音乐 | `Round Table` | 规范化资源 id `boss_round_table`；文件缺失时回退既有 `boss` |
| 总队数 | 18 | 17 支已实装正式 Ace 队 + Crucible 专属 Hound 雇佣兵双机 |
| 总机数 | 73 | 既有 71 架 + Hound-1/2 |
| XP | 0 | Boss 阶段统一不产出 XP；成员额外标记 no-kill-reward |

### 2.2 固定接力序列

| 批次 | 入场条件 | Profile | 中队 | 数量 | 入场方位 |
|---:|---|---|---|---:|---:|
| 开场 | `ENGAGED` 立即 | `2ndwave` / `gimmick` / `goofighters` | 2NDWAVE / GIMMICK / GOOFIGHTERS | 11 | 相对玩家机头左侧 110° / 正前 / 右侧 110° |
| 4 | 任一活跃中队全灭后 3 s | `whitetea` | WhiteTea | 3 | 当前镜头外可用环带槽 |
| 5 | 再次出现空位后 3 s | `vulture` | VULTURE | 8 | 当前镜头外可用环带槽 |
| 6 | 再次出现空位后 3 s | `marathon` | MARATHON | 5 | 当前镜头外可用环带槽；从首发延后到前中段 |
| 7–17 | 同一接力规则 | 扩编批次 | MOIRAI → FUNERAL | 44 | 排除六点钟禁区后均匀环绕入场 |
| 18（终局） | 前 17 支均已生成，任一活跃队全灭形成空位后 3 s | `hound`（Crucible-only） | HOUND | 2 | 同一可用环带；Hound-1/2 作为背叛玩家的雇佣兵最终入场 |

- 前三队在 PRE_STAGE 已从各自方向生成但禁火，供开场分镜依次切到 2NDWAVE、GIMMICK、GOOFIGHTERS 三位真实长机，表达多支中队正在同时汇入空域；MARATHON 延后到第 6 批再进场。镜头不得虚构 The Crucible 演员或说话者。
- 演出结束进入 ENGAGED 后，前三队同时开火，但前 8 秒只允许不同 Ace 队互相选敌；玩家仍可主动攻击且会承受误入弹道的正常后果。8 秒结束时立即把玩家小队加入仇恨候选，再恢复玩家猎手加权。场上活跃中队上限为 3；未出现全灭空位时不得按绝对时间继续堆人。一队全灭后等待 3 秒，只补一支下一队；同时空出多个槽位时也以 3 秒节拍逐队补入。
- 每波沿用原 profile 的机型、装备、flare、枪法、固定呼号与队内编成；不另加 HP。
- Hound 是唯一例外：正常友军支援实例保持 3000 m 雷达与原参数；Crucible 生成敌对 duplicate，固定呼号 `Hound-1/2`，每机 100 HP、3 flare、10 枚导弹、Ace 机炮、AI 四维 1.0，完整频率执行战术/武器更新且不吃拥挤降频。100 HP 直接复用 AceTier 的 Boss 级两发击破合同，不另造 HP 档。
- Hound 双机使用专属 `hound_betrayal` 队级主题：Hound-1 负责远距监视与火力覆盖，Hound-2 近身追杀；Hound-2 优先承担该队唯一玩家猎手，阵亡后由 Hound-1 接替；任一机被击毁后，幸存者切入 `VENGEANCE` 强攻。
- 每波出生中心取生成时的玩家当前位置与航向快照，最小入场半径为 3600 px（7.2 km）。导演先保持 profile 的设计方位，再以 400 px 步进把半径外推到最多 6000 px；若受地图边界阻挡，才以 15° 步进搜索相邻方位。最终必须按 profile 的真实编队偏移逐架计算：整队每架飞机都离地图真边界至少 1200 px，且全部位于当前相机视野之外，不得只判长机或出生中心。
- 首发三队的首选方位仍为相对机头 `-110° / 0° / +110°`；后续 15 队首选槽仍均匀铺在 `-135°..+135°`。相对玩家正后方 `135°..225°` 是出生禁区，搜索也不得越入六点钟禁区；所有方位都相对生成瞬间的玩家航向，不解释为世界固定北向。

### 2.3 LOD 与性能合同

| 字段 | 值 | 说明 |
|---|---:|---|
| 参战机视觉 LOD | 0 | 全部 Crucible 成员保持完整机体、标签、尾迹与反馈；AceTier 继续豁免远距冻结 |
| 同时活跃上限 | 3 支中队 | 数量由接力节拍约束，不用隐藏、冻结或静默删除伪装降载 |
| 开局纯混战窗 | 8.0 s | 从 `ENGAGED` 起计时；期间玩家不进入 Ace 目标候选，结束沿立即恢复正常仇恨 |
| 入场环 / 后方禁区 | 3600–6000 px / 相对机头后方 ±45° | 首发三槽保留设计方位，按当前镜头与地图边界外推/侧搜，出生中心必须在镜头外 |
| 主战场返场外圈 | 3600 px（7.2 km） | 成员离玩家超过此外圈时，同一 1 Hz 目标导演下发一次独占返场指令；世界硬边界仍作最后物理护栏 |
| 返场落点 / 抵达半径 | 玩家周围 900–1200 px 环槽 / 600 px | 每机按稳定名册槽分散落点；抵达后自动释放指令并恢复 FFA，避免 73 架挤向同一点 |
| 仇恨重算 | 1.0 s | Boss 控制器集中执行，不给每架飞机增加新 process |
| 雷达扫描 | 5 Hz；高密度发起方 16 相 | 复用同一次雷达 tick，把 FFA 发起方摊开并按实际 stride 补偿锁定进度 |
| 决策所有者 | `TheCrucibleEncounter` | 集中维护波次、仇恨和终态；内部仍接入 `BossEncounter` 生命周期只是结算适配 |

## 3. 行为与公式（How）

### 3.1 自由混战阵营

现有 `0=PLAYER / 1=HOSTILE / 2=ALLY` 语义保持不变。The Crucible 为 18 队分配运行时专用 team `3..20`：

```text
hostile(a, b):
  if a == b: false
  if a >= 3 or b >= 3: true
  else: exactly one side is HOSTILE(1)
```

- 同一 Ace 中队共享一个 team，队内绝不互伤；不同 Ace 队、玩家小队、第三方友军和残留敌军都与它敌对。
- 雷达、AI 目标选择、导弹、机炮、火箭和 AOE 一律消费同一个敌我 API；禁止只做视觉假打。
- 这些专用 team 只在本 Boss 生成的成员上使用；未打标内容的 0/1/2 行为逐字不变。

### 3.2 开局混战与击坠仇恨

每 1.0 秒由控制器为每个存活 Ace 重算一个合法目标。开局前 8 秒候选只有其它 Ace 队存活成员；时间窗结束后，每支活跃中队只指定 1 名玩家猎手，其余成员的候选仍只有其它 Ace 队。同队、已毁、锁定免疫目标排除。

```text
distance01 = clamp(1 - distance_px / 9000, 0, 1)
kill_bonus = candidate.kill_tally * 2.0
score = 1.0 + distance01 + kill_bonus
```

混战位选择非玩家目标时，额外加入战场可见性项：

```text
center01 = clamp(1 - distance(candidate, player) / 3600, 0, 1)
score += center01 * 3.0
```

- `kill_tally` 是飞机真实致死归因累计；击落玩家、友军或其它 Ace 都计入。
- 每支活跃中队只保留 1 名稳定玩家猎手：首次由离玩家最近的存活成员承担，猎手阵亡、失效或正在独占返场时才换人；Hound 优先指定 Hound-2。猎手直接以当前玩家机为 Boss 级目标，不参与普通仇恨竞价；只要存在可交战的活跃中队，就必须至少有人持续给玩家压力。
- 非猎手永远排除玩家小队目标，继续在不同 Ace 队之间自由混战；不得因为玩家距离近、击坠数高或目标失效而把全队重新吸到玩家身上。
- 每个射手在最高分候选并列时用实例 id 的稳定轮转分散目标，避免同批单位同拍锁死一机。
- 预生成但尚未激活的中队带 `crucible_active=false`，既不能成为射手也不能成为目标；激活时才进入仇恨候选。
- 分配使用 Boss 级目标来源，但只在 1 Hz 重算；目标失效时下一次更新前由既有 AI 安全脱离。
- 高击坠 Ace 的仇恨显著高于距离项，但不是隐藏增伤或强制处决；玩家可利用混战窗口。
- 可见性项只改变目标选择，不传送、冻结或伪造伤害；它让真实队际交火优先发生在玩家附近，玩家仍可凭机动把战团拉开。

当非猎手位于“正在以玩家小队为当前目标”的敌方 Ace 后半球时，允许触发机会主义背刺：

```text
rear_alignment = -forward(candidate) · normalize(shooter - candidate)
eligible = distance <= 2600 px and rear_alignment >= cos(60°)
range01 = 1 - distance / 2600
angle01 = inverse_lerp(cos(60°), 1, rear_alignment)
backstab_bonus = 8.0 * (0.65 + 0.20 * range01 + 0.15 * angle01)
```

- 该加权只在目标确实正在缠斗玩家且射手已经进入其后方 ±60° 时生效；正面、侧面、超距或目标未盯玩家时为 0。
- 每轮 1 Hz 重算中，同一名缠斗目标最多被 1 名机会主义者认领，避免所有混战位再次汇聚成单点集火；其它成员继续按距离、击坠仇恨和玩家附近可见性选择不同敌队。
- 背刺只改变正式 AI 的目标，不伪造伤害、命中率、位置或机头方向；射手仍须靠自己的飞行与武器包线完成攻击，因此只会在战场几何自然成立时偶发出现。

### 3.2.1 独占返场

- 新队从镜头外生成后带 `initial_ingress` 状态，先由正式目标/AI 自然飞入战区；距离玩家进入 3000 px 后清除。该状态期间不得因为出生距离超过 3600 px 而被“脱战返场”反向接管，禁止刚出生就掉头去飞慢速返场环。
- 成员越过 3600 px 外圈后，不再把“锁定玩家并继续空战”误当作返场；控制器只下发一次优先级 50 的 `DIRECTIVE/FLY_TO_POINT`，期间关闭战斗与旧目标、临时解除编队跟随，保持真实飞行返回主战场。
- 返场落点按成员在固定 73 机名册中的槽位，用黄金角分布在玩家快照位置周围 900 / 1050 / 1200 px 三层环带；到点容差固定 600 px。最坏抵达位置仍在 1800 px 内，和 3600 px 外圈形成明确滞回。
- 指令建立时快照玩家位置，后续 1 Hz 仇恨重算不得刷新指令或重置转弯；返场机关闭加力，并同时把目标速度与硬速度上限设为自身有效角点速度，避免高速大半径盘旋。抵达后恢复进入返场前的加力状态并回到普通 FFA 选敌。
- 父 `Aircraft` 的物理帧早于子 `AIController`：独占指令必须在父层 planner 与物理消费前镜像到 `DIRECTIVE` 控制意图槽，并撤销旧 `TACTIC` 槽；普通 directive 未声明速度字段时保持既有行为。
- `dense_battle_sim_divisor` 的成员相位门只能执行一次：命中相位后使用一次补偿 delta 完整更新，未命中时仅做 60 Hz 位移；禁止在 LOD 分支再按 `_lod_frame % divisor` 二次门控，否则非零相位成员会永久失去完整物理更新。
- 指令 owner 绑定本 encounter；胜利、取消、成员失效或 encounter 清理时必须释放，禁止跨终态持有飞机或 AI。
- 返场仍禁止传送、冻结、删除单位或关闭正式战斗负载来伪造通过；20 秒回场门必须由真实飞机运动满足。

### 3.3 状态机与终态

| 状态 | 进入 | 行为 | 退出 |
|---|---|---|---|
| `PRE_STAGE` | 决战事件生成 | 生成前三队但全部禁火；主题横幅后依次切三位真实中队长机，无开场无线电 | 演出收尾 → `ENGAGED` |
| `ENGAGED` | 通用决战事件接战 | 前三队先进行 8s 纯队际混战，随后每支活跃队只启用 1 名玩家猎手；其余成员继续 FFA，并可抢攻正在缠斗玩家且向其暴露后半球的敌方 Ace；每出现一个全灭空位，3 s 后补一队；1 Hz 仇恨与返场重算；Hound 双机作为最终接力入场 | 18 队已生成且全部 73 架击毁 → `VICTORY` |
| `VICTORY` | 最后一架 Ace 坠毁 | 清理目标引用，内部 encounter `active=false` | 通用胜利结算 |

- 玩家全队阵亡沿用既有 Game Over；Boss 不提供额外失败分支。
- WhiteTea 在本 Boss 中禁用投降；VULTURE 弹尽不撤离，所有队伍战至全灭。
- Boss 圈中心跟随全部存活成员质心。

### 3.4 无线电

- 当前版本禁用 The Crucible 的全部专属无线电：开场、正式接战、每队入场和高击坠威胁都不播放台词，不占用屏幕上方的无线电 UI 通道。
- The Crucible 仍只是战斗主题，没有人格、呼号或规则宣告者。开场分镜只用画面建立多队汇入。
- 旧的 Crucible 专属台词与 i18n key 已移除；后续只能在用户统一撰写、监修并明确要求重新开启后恢复。

## 4. 结构与组成（Structure）

- `TheCrucibleEncounter extends BossEncounter`：集中拥有 18 个 `AceSupportSquad`、接力计时、专用 team、仇恨与终态。继承仅复用现有决战阶段生命周期，不赋予 The Crucible BOSS 身份。
- `AceSupportSquad` / `AceSquadProfiles`：复用既有编成、装备、固定呼号和 AceTier 标记；本 Boss 不复制 profile 数据。
- `CombatUnit`：扩展运行时自由混战 team 的唯一敌我判定公式；弹丸继续只快照整数 team。
- `SurvivorMode` 雷达桶：0/1/2 沿用二分桶；team ≥3 的射手使用同一帧单位缓存并由唯一敌我 API 过滤。
- `BossEncounterEvent`：沿用 custom spawn、身份横幅、接战、胜利与玩家引用保鲜。
- HUD：必须直接复用海岸线与其它地图的常规王牌中队条构建与更新代码，不得保留 Crucible 专用卡片视觉。最多 3 条常规王牌条在顶部横向排列；仅已激活且尚有存活成员的中队显示，单机击毁即从分段中移除，中队全灭即整条移除，未入场队伍不占位。

## 5. 验收标准（Acceptance / Litmus）

- [x] 沙漠决战池在 `ARMORED_TRAIN` 与 `THE_CRUCIBLE` 间等权随机；Debug 可直达 The Crucible 战斗。
- [x] 开场 3 队同时接战；任一队全灭后延迟 3 s 只补一队，始终最多 3 支活跃中队；最终覆盖 18 队 73 架。
- [x] 首发三队在 `ENGAGED` 后先进行 8 秒真实队际混战，期间没有任何 Ace 把玩家选为目标；结束沿立即恢复玩家猎手权重。
- [x] 首发三队首选方位仍为相对玩家航向左侧 110°、正前、右侧 110°；全部 18 个槽均排除正后方 ±45°。实际出生半径在 3600–6000px 内按当前镜头外推/侧搜，出生中心不在当前镜头及缓冲区内。
- [x] Hound-1/2 只在 The Crucible 作为最终敌对双机出现；正常友军支援参数不变。双机为 100 HP / 3 flare / 10 missile / 满 AI / 完整频率，并在损失僚机后保持复仇强攻。
- [x] 不同 Ace 队之间真实雷达锁定、真实开火并真实造成伤害；同队绝不互伤；玩家可攻击全部 18 队。
- [x] Ace 个人 `kill_tally` 每增加 1，候选仇恨分固定 +2；2 杀 Ace 比零杀等距目标更优先。
- [x] WhiteTea 不投降、VULTURE 不撤离；全部 18 队生成且 73 架全灭才触发胜利。
- [x] 顶部最多 3 条且全部复用正常王牌中队 UI；单机击毁即移除其段、中队全灭即移除整条、未入场不占位，不显示专用 BOSS/Crucible 卡片。
- [x] 玩家主雷达可对 team 3–19 的熔炉成员正常累积锁定；传统 0/1/2 阵营候选关系不变。
- [x] 高密度四相位移时，飞机与世界状态标签同步刷新；标签保持屏幕水平、恒定字号，不随机体旋转。
- [x] 新队至少在玩家 7.2 km 外且镜头外汇入；初次入场进入 6.0 km 后才交还脱战导演，之后成员超过玩家 7.2 km 必须回扑，不得出现存活血条对应的飞机长时间消失于战场外。
- [x] Round Table 驱动本 Boss；Midnight March 驱动装甲列车；Ace 只加入沙漠非 Boss Ace 随机池。缺失素材 fail-safe 回退，不中断当前音乐所有权。
- [x] 整场 The Crucible 不播放开场、接战、入场或高威胁无线电；通用 BOSS 默认序列也不得回退播出。
- [x] focused 测试覆盖阵营公式、接力表、Hound 专属实例、仇恨公式、注册表/音乐配置与胜利终态；生命周期终态后至少继续一帧并跨缓存 tick。
- [x] 性能：当前正式同屏上限三队；Hound 入场时完整频率、LOD0 与真实武器开启，The Crucible 专项 `Shadow Visual` 为 `frames_below_60=0`、p1/worst ≥60，不隐藏、不停火。
- [x] i18n：Boss、Debug 与身份横幅三语齐全；已禁用的 Crucible 台词 key 不留存。
- [x] 文档：本 spec 登记 `_INDEX`，沙漠 spec 与 reference 指针同步。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | spec、注册表、i18n、JSON、diff 审计 | 通过；三份 intake WAV 已保留并派生为正式 48 kHz stereo OGG，注册表命中真实资源 |
| E1 聚焦 Shadow | `the_crucible` + `desert_theater`；静态覆盖固定接力顺序、猎手配额、后半球 / 距离 / 单目标认领门与 18 槽相对航向几何；真实 SceneTree 逐机确认首发整队离开当前镜头且不越地图安全边界、第一帧/7.9s 纯 Ace 目标、8.0s 三队三名玩家猎手切换、其余成员零玩家目标、真实背刺目标写入及猎手阵亡后的同队接班，并继续接力推进至 73 机终态 | v14 为 32/32 + 62/62 通过；MARATHON 位于第 6 批，正式三队阶段始终为 3 名玩家猎手 |
| E2 集成 / 压力 Shadow | `all` + `lifecycle_gauntlet` | v14 全量 91/91，`lifecycle_gauntlet` 86/86，runtime error gate 退出 0。 |
| E3 Visual | `the_crucible_stress 30s Shadow Visual`；经正式接力推进到终局三队/9 Ace，含 Hound×2 完整频率、LOD0、真实武器与 HUD | v14 最终复核为 3240 帧，avg/p1 120.00、worst 117.92 FPS，`frames_below_60=0`。中间两份样本各出现 1 个无游戏桶归因的 24.4/24.9ms 桌面尖峰，且前后均有零低帧样本；红样本保留，不放宽 60 FPS 硬门。 |
| E3 Visual | `battlefield_atmosphere_stress_36 30s Shadow Visual`；36 名混合海陆空演员、8/8 镜头巡检 | `frames_below_60=0`；avg 119.89、p1 119.80、worst 61.35 FPS |
| E3 Visual | `battlefield_atmosphere_stress_48_24km 30s Shadow Visual`；24km 多战线、48 名初始演员、8/8 镜头巡检 | `frames_below_60=0`；avg 119.63、p1 117.61、worst 67.03 FPS；结束时 47 名存活是实战减员 |
| E2 极限诊断 | `the_crucible_full_roster_stress 40s Shadow Headless`；绕过正式三队上限并固定观察者，同时激活 18 队 73 架、真实武器、成员锁血 | 73/73 全程存活、0 静默退场、0 失效目标；峰值 55 missile / 253 bullet，返场峰值 12 架、最长 12s、0 次超时、最远 8.2km、0 架越过世界硬边界。Headless `frames_below_60=0` 只作自动诊断，不替代 Visual。 |
| E2 真实减员 | `the_crucible_full_roster_attrition 60s Shadow Headless`；同上但保留真实互伤与死亡 | 19 架存活、1 架有效击毁、53 架 destroyed 退场，0 非 destroyed 退场、0 失效目标；峰值 55 missile / 461 bullet，返场峰值 5 架、最长 11s、0 次超时、最远 8.0km。极限弹幕瞬间有 16 帧低于 60 FPS，属于诊断压力红项，不冒充正式三队 Visual 通过。 |
| E4 完整局 | 沙漠 12–20 分钟完整局 | 待用户验收 |

## 6. 实现计划（Task Pipeline）

### 阶段 1 — SSOT 与接线
- [x] 建立规格、登记沙漠双 Boss 池与音乐所有权。
- [x] 加 BossRegistry、Boss Debug、身份横幅和 i18n。

### 阶段 2 — 真实混战
- [x] 实现 18 队顺序生成、自由混战阵营、Hound 最终接力、玩家主仇恨、1 Hz 击坠仇恨与 18 队终态。
- [x] 接入队级 HUD 与玩家引用保鲜；Crucible 无线电保持禁用。

### 阶段 3 — 验证
- [x] 加 focused / lifecycle / performance 场景并跑默认全量回归；三组 Visual 已过 60 FPS 硬门。
- [x] 完成自动 Visual 验收；完整局手感与难度留给用户实机监修。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 主逻辑 | `scripts/survivor/the_crucible_boss.gd` |
| 敌我判定 | `scripts/combat_unit.gd` |
| 雷达候选 | `scripts/survivor/survivor_mode.gd` |
| 注册/音乐 | `scripts/survivor/boss_registry.gd` · `scripts/audio/audio_manager.gd` |
| 无线电禁用/演出 | `scripts/survivor/boss_encounter.gd` · `scripts/events/boss_encounter_event.gd` · `scripts/survivor/survivor_mode.gd` · `resources/presentation/sequences.json` |
| focused 测试 | `scripts/tests/test_the_crucible.gd` |
| reference 索引 | `docs/reference/script-index.md` · `docs/reference/code-index.md` · `docs/reference/enemy-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-09-02 | 9 | 新增长驻全员 Headless 诊断：18 队 73 架同时激活的 stable/attrition 双样本，逐秒审计成员、退场、目标、弹丸和空间范围；确认 CPU/生命周期无溢出或静默消失，同时记录极限同屏下返场约束失败，留作后续空间导演修复输入。 |
| 2026-09-03 | 10 | 修复空间导演语义：越过 7.2km 后下发一次独占 `FLY_TO_POINT`，按固定名册槽分散到玩家快照周围三层返场环；到点自动恢复 FFA，禁止每秒重建指令或用传送伪造回场。 |
| 2026-09-04 | 10 | 完成返场实现校正：独占 DIRECTIVE 在父层物理前抢占旧战术意图，返场暂离编队并以有效角点速度作为目标与硬上限；修复 dense 相位在 LOD 分支被二次门控、导致非零相位成员永不完整更新的根因。73 机 stable/attrition 均为 0 返场超时与 0 异常退场。 |
| 2026-09-04 | 11 | 按玩家反馈重做开局节奏与出生几何：首发三队先进行 8 秒纯 Ace 队际混战，再开始围猎玩家；出生槽改为相对玩家航向的 2400px 包围环，所有批次排除六点钟后方 ±45° 禁区。 |
| 2026-09-04 | 12 | 调整接力顺序：MARATHON 从首发移到第 6 批；开场改为 2NDWAVE / GIMMICK / GOOFIGHTERS，WhiteTea 与 VULTURE 分别成为第 4、5 批。 |
| 2026-09-04 | 13 | 把接战后的玩家压力收敛为每支活跃中队 1 名稳定猎手，其余成员永久排除玩家目标并继续 FFA；加入后半球机会主义背刺，优先抢攻正在缠斗玩家的敌方 Ace，且每轮每个目标最多 1 名认领者。 |
| 2026-09-05 | 14 | 入场最小距离由 2400px 提高到 3600px，并按当前镜头与地图边界外推到最多 6000px、必要时侧搜；按真实编队偏移逐架验证离屏与边界，禁止任何僚机仍在镜头内凭空生成；新增 3000px 初次入场滞回，避免远端出生立即误触 3600px 脱战返场。 |
| 2026-09-02 | 8 | Hound-1/2 作为背叛玩家的雇佣兵加入最终接力；仅 Crucible 敌对 duplicate 获得 Boss 级 100 HP、3 flare、10 missile、满 AI、完整频率与远近协同/幸存复仇，正常友军支援不变。 |
| 2026-09-02 | 7 | 按完整局反馈改为三队上限的全灭接力制；增加 7.2 km 回扑与世界硬边界护栏；删除 Crucible 专用 HUD 视觉，强制复用常规王牌中队条。 |
| 2026-09-02 | 6 | 按玩家监修禁用并移除本战所有新增无线电；入场、接战、波次和高威胁均静默，直到玩家统一重写后再开启。 |
| 2026-09-02 | 5 | 按实机反馈修订：自由混战阵营必须进入玩家雷达候选；入场改为跟随玩家的 4.8 km 外缘并增加近景交战权重；HUD 改为仅显示已入场存活成员的多 Ace 中队条，逐机显示击坠数；高密度位移不得让世界标签旋转。 |
| 2026-09-02 | 4 | 17 队 71 架完成高密度四相模拟与 16 相雷达摊分；C1、C2、The Crucible Visual 均零帧低于 60 FPS。 |
| 2026-09-01 | 3 | 加入扩编 11 队，总计 17 队 71 架；每四架固定三架主攻玩家、一架维持混战，高击坠敌王牌仍可抢走仇恨；未激活预生成队不得提前参战。 |
| 2026-09-01 | 2 | 用户纠正身份：The Crucible 是战斗主题而非中队、角色或 BOSS，不得拥有无线电或 CRUCIBLE 呼号；开场改为前三支真实中队依次切镜。内部仅借用 BossEncounter 生命周期完成决战结算。 |
| 2026-08-31 | 1 | 用户批准沙漠 The Crucible：全部已实装 Ace 队依次进场真实互打，高击坠 Ace 获得更高仇恨，目标为存活并全歼；指定 Round Table / Midnight March / Ace 三首音乐职责。 |
