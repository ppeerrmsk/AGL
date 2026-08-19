---
id: radio-chatter
kind: system
status: done  # 2026-08-10 Notion 修订已实现并完成聚焦回归
schema_version: 1
spec_version: 11
owner: noelu
depends_on: [combat-feed, command-wheel, global-awareness-roe]
reconstruction_complete: true
---

# 无线电通讯系统（Radio Chatter）

> 战场上有人在说话。击坠、下令、BOSS 登场时，屏幕上方跳出一句带呼号的无线电台词 + 一声电台底噪，让空战从"打靶"变成"有人的战场"。

## 1. 设计意图（Why）

- **体验目标**：AGL 目前的战场是**哑的**——击杀只有左上角一行灰字，BOSS 登场只有一个红色 WARNING 横幅，僚机执行命令毫无回应。玩家操控的是一支小队，却听不见队友的声音。本系统补的是**临场感与人味**，参考《皇牌空战》：让"我不是一个人在飞"成为可感知的事实，让敌方在被打崩时发出哀嚎，把玩家的战绩**翻译成敌人的痛苦**。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - **"效果即反馈，不加 HUD 中介"** —— 本系统**不引入任何新的玩家决策**。台词是纯输出，不携带玩家必须读的信息，不设图标、不设计数器。漏看任何一条都不影响操作。
  - **"中队级粒度"** —— 说话人是**中队成员**，不是每架飞机的独立人格。RTS 下令只回一条 ack，不是全队 4 架各喊一句。
  - **"复用既有数值"** —— 阵营色直接引 `GameConstants` FactionPalette；说话人名直接用既有 `callsign`；触发点全部挂在**已存在**的信号/函数上，零新增轮询。
- **反模式规避**：
  - **不做对话树 / 不做剧情分支**。台词是氛围贴图，不是叙事系统。
  - **不打断**（用户硬需求）：绝不为"更重要的话"截断正在播的话。宁可丢弃，不可截断——被打断的语音是廉价感的头号来源。
  - **不刷屏**：每个触发类别独立冷却，队列有上限且会丢弃过期条目。战场再乱，说话频率也有硬上限。
  - **不新增 `_process` 扫描**：唯一的 `_process` 是本系统自己的一个计时器（O(1)），不做任何全场遍历。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 显示层

**版式参考《皇牌空战》**（用户 2026-07-20 提供截图）：呼号**单独一行在上**，正文另起一行并用 `<< >>` 包裹；呼号取纯阵营色、正文取同色向白靠拢的淡色，形成"谁在说 / 说了什么"的主次；背景是**左右淡出的柔和渐变带**，不是硬边矩形；长句自动换行且整块高度随行数增长。

| 字段 | 值 | 说明 |
|---|---|---|
| CanvasLayer layer | `19` | 夹在 ZoneHint(18) 与升级 UI(20) 之间 |
| 带宽比例 | `BAND_WIDTH_RATIO = 0.64` | 占屏幕宽度的 64%，水平居中 |
| 垂直位置 | `TOP_MARGIN = 118` | 让开时间(28)/击杀(54)/云(74)/BOSS面板(78)/ZoneHint(70~110) |
| 高度 | 自动 | `= 内容高 + 上下内边距 × 2`，随正文换行行数增长 |
| 背景色（中段） | `Color(0.02, 0.03, 0.05, 0.66)` | |
| 背景渐变 | 停靠点 `0.0 / 0.26 / 0.74 / 1.0` → `透明 / 实 / 实 / 透明` | 水平方向，两端淡出；用 `GradientTexture2D` 生成，无外部素材依赖 |
| 内边距 | `PAD_H = 28`, `PAD_V = 9` | |
| 呼号字号 | `13` | |
| 正文字号 | `15` | |
| 行距 | `2` | 呼号与正文之间 |
| 描边 | `outline_size = 4`, `Color(0,0,0,0.9)` | 两行都有，与 kill feed 一致 |
| 呼号颜色 | 纯阵营色（§2.5） | |
| 正文颜色 | `阵营色.lerp(白, 0.65)` | **必须向白靠拢**，不可变暗——深色背景上暗色读不出来 |
| 正文标记 | `"<< "` + 台词 + `" >>"` | 由代码拼，不进 i18n（译者不必关心） |
| 换行 | `AUTOWRAP_WORD_SMART` | |
| 淡入时长 | `0.12` s | |
| 淡出时长 | `0.35` s | 在条目剩余寿命的最后 0.35s 内线性降 alpha |

**高度重算时机**：容器要先解算出宽度，才知道正文换了几行。因此设置文本后**等 2 帧**再按 `VBoxContainer.get_combined_minimum_size().y` 定高。这 2 帧被 0.12s(≈7 帧) 的淡入盖住，看不出跳变。每条台词只算一次，不是每帧。

### 2.2 时序与队列

**全部数值住在 `resources/chatter/radio_chatter.json` 的 `global` 段**，本表是其权威副本。

| 字段 | JSON 键 | 值 | 说明 |
|---|---|---|---|
| 基础时长 | `line_duration_base_sec` | `2.6` s | |
| 逐字追加 | `line_duration_per_char_sec` | `0.035` s | 长句多留阅读时间 |
| 单条上限 | `line_duration_max_sec` | `5.0` s | |
| 条间静默 | `line_gap_sec` | `0.30` s | 电台换手感 |
| 队列上限 | `queue_max` | `3` | 不含正在播的那条 |
| 过期阈值 | `queue_stale_sec` | `6.0` s | 排队超时即丢弃 |

**时长公式**：`duration = clamp(base + per_char * len(text), base, max)`
样例：18 字 → `2.6 + 0.035*18 = 3.23` s。

**过期豁免**：`class: scripted` 的条目**永不过期**。BOSS 登场是一次性入队的多条剧本序列，按每条约 3.4 s 计，第 3 条要等到约 6.8 s 才轮到播出 —— 若一律按 `queue_stale_sec` 丢弃，**挑衅的收尾句会被静默砍掉**。过期机制的本意是"迟到的战况播报等于噪音"，对预先写好的桥段不成立。

### 2.3 无线电分类（用户订正 2026-07-20）

每个 trigger 必须声明 `class`，这是"要不要受节流管"的唯一开关：

| class | 含义 | 节流 | 典型 |
|---|---|---|---|
| `scripted` | **剧情关键节点** | **完全豁免**全局冷却 / 自身冷却 / 概率骰，**必定播出** | BOSS 登场对话、BOSS 交战、王牌中队登场（`ace_spawn`） |
| `ambient` | 普通战场无线电 | 受**三层节流**全部限制 | 击坠回报、弹射、回令、哀嚎、归队 |

未登记 class 的 trigger **保守按 `ambient` 处理** —— 新加的东西不会意外获得强插特权。

`scripted` 条目**不占用也不重置**任何冷却账本：BOSS 说完话，普通语音的冷却窗口不受影响。

### 2.4 权重（Weight）

多条同时排队时，**权重高的先播**。权重**只影响排队顺序与满队淘汰，永不打断**正在播的那条（用户硬需求）。

| trigger | 权重 |
|---|---|
| `boss_spawn` / `boss_engage` | `100` |
| `wraith_member_down` | `98` |
| `bomber_escort_complete` | `98` |
| `airfield_liberated` | `97` |
| `bomber_escort_intercept` | `97` |
| `bomber_escort_available` | `96` |
| `hound_one_contact` / `hound_two_follow` | `94` / `93` |
| `zone_ground_thanks` | `91` |
| `ace_spawn`（王牌中队登场） | `90` |
| `eject_friendly`（自家人阵亡） | `80` |
| `break` | `60` |
| `ack_*`（RTS 回令） | `50` |
| `splash`（击坠回报） | `40` |
| `eject`（敌方阵亡） | `30` |
| `csg_fa18_launch` | `25` |
| `attrition_*`（敌方哀嚎） | `20` |
| `zone_naval_contact` / `zone_air_support_request` | `15` |
| `wingman_join` | `10` |

同权重时取**最早入队者**。满队时新条目只有权重**严格大于**队内最低者才顶替，否则被丢弃。

### 2.5 阵营配色（引 `GameConstants` FactionPalette，禁止散写字面量）

| 说话人 | 颜色常量 | 值 |
|---|---|---|
| 玩家直属小队（team 0） | `COL_FRIEND_PLAYER` | `#4D99FF` 蓝 |
| 第三方 ALLY（team 2） | `COL_FRIEND_ALLY` | `#59D16B` 绿 |
| 敌方常规（team 1） | `COL_ENEMY_REGULAR` | `#FF8A3D` 橙 |
| 敌方精英 / BOSS | `COL_ENEMY_ELITE` | `#E8352E` 红 |

> 用户需求是"敌红 / 友绿或蓝"。敌方拆成橙/红两档是既有 FactionPalette 的**威胁分级**语义（常规→精英），两者都落在暖色域，读感仍是"敌人在说话"，且与雷达/尾迹/kill feed 全局一致。**精英判定**：说话人所属 encounter 非空，或单位 `enemy_type` meta 属于 BOSS 类。

### 2.6 敌方减员哀嚎（`enemy_attrition`）触发阈值

累计本局**敌方**损失数（空中 + 地面，两者合并计数）。每跨过一个 `12` 的整数倍触发一次，并受 2.4 的 30s 冷却压制。台词档位按累计总数选：

| 累计损失 | 档位 | 语气 |
|---|---|---|
| `12 ~ 35` | tier 1 | 报告接触/请求支援 |
| `36 ~ 71` | tier 2 | 承受重大损失 |
| `≥ 72` | tier 3 | 防线崩溃 / 请求撤退许可 |

### 2.7 音效

| 字段 | 值 |
|---|---|
| 播放总线 | `AudioManager.RADIO_BUS`（`"Radio"`，默认 -10 dB，已挂频带切割+轻失真效果链） |
| 音效 id | `radio_beep` |
| 期望文件 | `res://audio/sfx/radio_beep.wav` |
| 播放时机 | 每条台词**显示的同一帧** |
| 素材缺失行为 | **静默跳过，不 push_warning**（本轮素材未到位；视觉部分独立可验收） |

### 2.8 谁有资格说话（用户订正 2026-07-20）

> **无人机不该有无线电台词，只让一定等级的敌人有台词。**

两道门，**必须同时通过**：

| 门 | 规则 | 落点 |
|---|---|---|
| ① 硬规则 | `no_pilot` 的机体**永不说话** —— 无人机没有飞行员，就没有人声。**不可被 ② 覆盖** | `Aircraft.can_speak_on_radio()` |
| ② 等级门 | 机型必须登记在白名单里，**opt-in，默认沉默** | JSON 的 `voiced_enemy_types.types`，经 `ChatterLines.type_has_voice()` 查询 |

`no_pilot` 是既有字段（原用于让无人机免疫 FEAR 心理状态），本系统复用它而非另造概念。

**opt-in 而非 opt-out 是刻意的**：以后新增敌人默认不会突然开口，杜绝"加了个无人机结果它开始喊话"这类回归。

**当前登记为有无线电的机型**（`resources/chatter/radio_chatter.json` 的 `voiced_enemy_types.types`，就是"哪一级敌人配无线电"的唯一调参处）：

| 类别 | 机型 |
|---|---|
| 常规有人战斗机 | MiG-29 / J-7 / F-86 / MiG-31 / MiG-23 / F-100 / Su-27 / A-7 / Q-5 / F-4 / **F-4E** / F-104 / Su-35 / F/A-18 |
| BOSS 王牌 | F-47（WRAITH）/ F-14（POLTERGEIST） |

**沉默**：MQ-109(uav) / MQ-110(ucav) / Sentinel(uav_commander) / Aegis(uav_laser) / AF-03（均为无人机）、Tu-160 / AH-64 / CH-47（被动杂兵，无交战能力）、Mother Goose 蜂群 UAV 与 MQ-X。

**各触发的具体表现**：

| 触发 | 无人机时的行为 |
|---|---|
| `eject`（弹射呼叫） | **不播** —— 没有飞行员可弹射 |
| `break`（规避呼叫） | **不 emit**（在 `set_evasion_mode` 处就掐掉） |
| `wingman_join`（归队） | **不 emit** |
| RTS 回令 | 无人僚机**不入选**应答人 |
| `enemy_attrition`（减员哀嚎） | **照常计数** —— 说话的是敌方指挥部（有人），它一样会为损失无人机而哀嚎 |
| `splash`（击坠回报） | **照常** —— 说话的是玩家方僚机，与被击坠者是不是无人机无关 |

**信号扩展**：`EventLogger.kill_recorded` 增加末位参数 `victim_voiced: bool`（在 `Aircraft._record_kill_attribution` 由 `can_speak_on_radio()` 求值）。该信号只带呼号字符串、不带单位引用，订阅端无从判断机种，因此必须由发出端携带。kill feed / ROE 两个既有订阅方不消费此字段。

### 2.9 数据源与文本编辑流程（用户订正 2026-07-20）

> **不要把文本写在代码里**，方便后续本地化/剧情人员编辑。

| 内容 | 住在哪 | 谁编辑 |
|---|---|---|
| **结构**：有哪些 trigger、各自的 class / weight / cooldown / chance、台词 key 列表、BOSS 对话序列、说话资格白名单 | `resources/chatter/radio_chatter.json` | 设计 / 策划 |
| **文本**：每个 key 的中/英/日三语 | `i18n/radio.csv` | 本地化 |
| **代码** | `chatter_lines.gd`（纯加载器，**零数值**）+ `radio_chatter.gd`（队列与显示） | 程序 |

**加一条新台词**（不碰代码）：
1. 在 JSON 对应 trigger 的 `lines` 数组加一个 key，例如 `"RADIO_SPLASH_5"`；
2. 在 `i18n/radio.csv` 加一行 `RADIO_SPLASH_5,中文,English,日本語`。

**加一个新 trigger**：在 JSON `triggers` 里加一项，然后在代码的事件点调 `RadioChatter.say("<trigger_id>", ...)`。

同一 trigger 可以混放 `_FMT` 与普通 key。`RadioChatter.say()` **只对 key 名以 `_FMT` 结尾的条目执行 `%` 格式化**；调用方即使统一传入 `fmt_args`，抽到普通 key 也必须原样播出，不能出现格式化错误或把该句静默丢掉。

**JSON 字段**：

| 字段 | 说明 |
|---|---|
| `class` | `scripted` / `ambient`，见 §2.3 |
| `weight` | 见 §2.4 |
| `cooldown_group` | 共享冷却的桶名，省略则用 trigger 自己的 id。例：所有 `ack_*` 共享 `"ack"` 桶 |
| `cooldown_sec` | 同桶内两次播出的最小间隔 |
| `chance` | 通过冷却后仍要过的概率骰（0~1）。**"偶尔出现一下"的主要旋钮** |
| `lines` | i18n key 数组 |
| `lines_ref` | 复用另一个 trigger 的 `lines`，避免重复粘贴（例：`eject` 复用 `eject_friendly`） |

**容错**：JSON 缺失或解析失败 → 报 error 后整个无线电系统**降级为静默**，不崩游戏（台词是氛围，不值得为它中断一局）。加载结果静态缓存，全进程解析一次。

**导出注意**：`.json` 在 Godot 里不是导入资源（无 `.import` 附属文件），因此 `export_presets.cfg` 的 `include_filter` 必须包含 `*.json`，否则导出包会丢掉本表（以及 `resources/maps/` 和 `resources/evolution/` 的同类数据）。

### 2.10 三层节流（用户订正 2026-07-20）

> **语音播放频度太高**（每次点 combat target 僚机基本必然说话），要"偶尔出现一下就可以，不要太抢戏"。

`ambient` 类语音必须**依次通过三道门**，任一不过即静默丢弃；`scripted` 类**三道全免**。

| 层 | 机制 | 默认值 | 作用 |
|---|---|---|---|
| ① 全局冷却 | 任何一条 ambient 语音入队后，**全场 ambient 静默** | `12.0` s | 控制"整体多久才有人说一次话"的总闸 |
| ② 冷却桶 | 同 `cooldown_group` 的最小间隔 | 见下表 | 防止同一类事件连播 |
| ③ 概率骰 | 过了冷却仍要掷骰 | 见下表 | 制造"不是每次都有人应答"的自然感 |

**判定顺序**：全局冷却 → 桶冷却 → 概率骰 → 入队。

**冷却在成功入队瞬间起算**（不是播出时），防止一秒内 10 次击杀塞满队列。
**掷骰失败不起冷却** —— 否则一次运气不好就闷掉整个冷却窗口。

| trigger | 冷却桶 | `cooldown_sec` | `chance` | 说明 |
|---|---|---|---|---|
| `eject_friendly` | 自身 | `8.0` | `0.90` | 自己人阵亡是重要事件 |
| `eject` | 自身 | `9.0` | `0.45` | 敌方阵亡，氛围性质 |
| `break` | 自身 | `12.0` | `0.60` | |
| `splash` | 自身 | `10.0` | `0.40` | 击杀是最高频事件，压得最狠 |
| `ack_pursue` / `ack_strike` / `ack_surround` / `ack_cover` / `ack_regroup` / `ack_evac` | **共享 `ack`** | `8.0` | `0.35` | **用户反馈的重灾区**：连点下令不会每次都有人应答 |
| `attrition_t1/t2/t3` | **共享 `enemy_attrition`** | `30.0` | `1.00` | 本身已由里程碑门控 |
| `wingman_join` | 自身 | `0.0` | `1.00` | 事件本身稀有 |
| `csg_fa18_launch` | 自身 | `0.0` | `0.50` | 只在 Phase 1 定期补充机成功弹射后尝试；成功入队后本战一次性闭锁 |
| `zone_naval_contact` | 自身 | `0.0` | `0.45` | 战区首次进入，敌舰低优先级喊话 |
| `zone_air_support_request` | 自身 | `0.0` | `0.45` | 战区首次进入；必须找到真实存活友机作为说话人 |

## 3. 行为与公式（How）

### 3.1 队列状态机

| 状态 | 转移条件 | 动作 |
|---|---|---|
| `IDLE` | 队列非空 | 弹出优先级最高（同优先级取先入队者）→ `SPEAKING` |
| `SPEAKING` | 计时到 `duration` | → `GAP` |
| `GAP` | 计时到 `LINE_GAP` | → `IDLE` |

**入队 `say(entry)` 判定顺序**（任一步失败即静默丢弃，返回 false）：

1. 类别冷却未到 → 丢弃。
2. 队列已满（`size >= QUEUE_MAX`）：
   - 新条目优先级 **>** 队列中最低者 → 踢掉最低者，新条目入队；
   - 否则 → 丢弃新条目。
3. 入队，记录 `enqueued_at`。
4. **冷却在成功入队瞬间起算**（不是播出瞬间）。理由是防洪：一秒内 10 次击杀若都能入队，队列会被同类台词占满，冷却形同虚设。代价是被淘汰的条目也占了冷却 —— 这条路径罕见，且后果只是少说一句话，可以接受。

**出队时过期检查**：弹出条目若不属于 `NEVER_STALE` 且 `now - enqueued_at > QUEUE_STALE_SEC` → 丢弃并立刻尝试下一条（`while` 循环，非递归）。

### 3.2 说话人解析

给定一个 `CombatUnit speaker`：

```
name  = speaker.callsign（空 → 回退 "UNKNOWN"）
color = team 0 → COL_FRIEND_PLAYER
        team 2 → COL_FRIEND_ALLY
        team 1 且 elite → COL_ENEMY_ELITE
        team 1 → COL_ENEMY_REGULAR
```

BOSS 序列的说话人由 `encounter` 提供：`"<callsign_prefix>-%02d" % (slot + 1)`，颜色恒为 `COL_ENEMY_ELITE`。这样即使 BOSS 机体尚未 `_ready()` 分配呼号，登场台词也能立即说出正确的名字。

### 3.3 触发表（Phase 1 实装范围）

| 触发 id | 挂载点（信号/函数） | 说话人 | 台词 key |
|---|---|---|---|
| `boss_spawn` | BOSS 遭遇事件开场（与 WARNING 横幅同处） | BOSS 队 slot 0/1 | 按 boss id 取专属序列 |
| `boss_engage` | BOSS 进入交战阶段 | BOSS 队 slot 0 | 按 boss id |
| `wraith_member_down` | WRAITH 本战第一架有效成员被击毁 | 被击毁成员（真实呼号） | `RADIO_BOSS_WRAITH_DOWN_*`，本战仅一次，scripted |
| `csg_fa18_launch` | CSG Phase 1 **定期** F/A-18 成功弹射（不含 engage 初始两架） | 新弹射 F/A-18 | `RADIO_BOSS_CSG_FA18_LAUNCH_*`；每次补充按 `0.50` 尝试，首次成功入队后闭锁 |
| `ace_spawn` | 非 BOSS 王牌中队入场（`AceReinforcementEvent._start`；红色警告横幅已收回 BOSS 专属，此台词即王牌入场**主信号**） | 王牌长机（`say_unit`） | `RADIO_ACE_SPAWN_*` 单条池（**台词内容权威在 [ace-squadron-tier](ace-squadron-tier.md) §2.6**；单条即可——多句对话序列是 BOSS 专属） |
| `hound_one_contact` | 本局首次 F-15 王牌截击支援实际生成 | `Hound-1`（ALLY 绿） | `RADIO_HOUND_ONE_CONTACT`：“发现猎物了，准备交战” |
| `hound_two_follow` | 与 Hound-1 同一双机实际生成 | `Hound-2`（ALLY 绿） | `RADIO_HOUND_TWO_FOLLOW`：“收到，我跟在你后面” |
| `splash` | `EventLogger.kill_recorded`，killer_team==0 且 killer 非玩家本机 | killer | `RADIO_SPLASH_*` |
| `eject` | `EventLogger.kill_recorded` | victim | `RADIO_EJECT_*` |
| `break` | `Aircraft.set_evasion_mode(true)` 的 **false→true 沿**（`suppress_radio=false`，即真·躲导弹），且单位属玩家小队 | 该机 | `RADIO_BREAK_*` |
| `afterburner` | `AfterburnerCharge.toggle` 成功启动加力（充能制，玩家主动脱离/占位；此路径的 evasion break emit 被 `suppress_radio` 抑制） | 长机 | `RADIO_AFTERBURNER_*` |
| `ack`（含 `ack_pursue` / `ack_strike` / `ack_surround` / …） | `SquadCommandController.command_attack / command_attack_all / command_guard / command_regroup / command_evacuate` | 队内随机一名非玩家僚机 | 见 3.4 |
| `enemy_attrition` | 同 `kill_recorded`，victim_team==1，累计计数 | 敌方泛指呼号 | `RADIO_ATTRITION_T{1,2,3}_*` |
| `wingman_join` | 僚机加入玩家小队 | 新成员 | `RADIO_JOIN_*` |
| `reward_target_available` | 首批奖励战区达到 60 秒 + Lv3 门槛；目标实体生成前 6 秒 | HQ | `RADIO_REWARD_TARGET_AVAILABLE` |
| `bomber_escort_available` | 可选护送任务达到 150 秒 + Lv5 门槛；目标实体生成前 6 秒 | 指挥中心 | 固定双句：先按真实目标坐标计算八方向并通报打击方位，再播护航请求 |
| `bomber_escort_intercept` | 玩家选择可选护送任务，轰炸编队开始入场且敌方后方追击计划建立 | 指挥中心 | mandatory：只报告敌方追击编队正从轰炸队后方接近，并请求近空掩护；不暴露玩家介入判定、航程阈值或强制失败机制 |
| `bomber_escort_complete` | 战略目标被 `bomber_bomb` 实际摧毁，专属 XP 已加入共享经验池 | 指挥中心 | mandatory：只确认目标摧毁、任务完成与轰炸编队撤离；不播报 XP 数值 |
| `zone_naval_contact` | `ZoneMission.mission_triggered`，任务类型为 `naval` | 本战区真实存活敌舰 | `RADIO_ZONE_NAVAL_CONTACT`；低优先级、随机 |
| `zone_air_support_request` | `ZoneMission.mission_triggered`，任务类型为 `air` / `squadron` | 玩家编队中真实存活的非玩家友机；单机时静默 | `RADIO_ZONE_AIR_SUPPORT_REQUEST_FMT`，地区名取战区 `name_key`；低优先级、随机 |
| `zone_ground_thanks` | `ZoneMission.mission_completed`，任务类型为 `ground`，且战区气氛层至少一辆友军单位存活 | 该真实存活友军单位 | `RADIO_ZONE_GROUND_THANKS`；条件成立即播 |
| `airfield_liberated` | `_liberate_airfield` 完成状态切换与机场部署 | 临时塔台 | `RADIO_AIRFIELD_LIBERATED_*_FMT` 三选一；代入当前长机真实呼号，mandatory |

**BOSS 登场序列**为**多条**台词（2~3 条，不同 slot 交替），依次入队，构成一段小队内部对话。这是本系统的展示样例。

**BOSS 相位补充**：

- CSG `phase2` 固定先由 slot 1 报告舰体向右舷严重倾斜，再由 slot 0 下达现有弹射命令；两句均走 `boss_engage` scripted 队列。
- Mother Goose 在半血 MQ-X 双机成功释放后播 `phase2`：`engagement.phase++;reserve_units.commit();`。若 MQ-X 因资源/生成前置失败而未实际生成，则不播。
- WRAITH 减员台词只属于 `WRAITH_SQUADRON`，不泛化到 Poltergeist 或普通王牌中队。

**轰炸方位算法**：取 `ZoneMission.build_bomber_escort_route()` 返回的真实 `target` 世界坐标，以地图原点为中心按 `atan2(y, x)` 量化为北 / 东北 / 东 / 东南 / 南 / 西南 / 西 / 西北八档。台词只说大致方位，不暴露精确坐标，也不使用任务槽位 A–G 伪装地理。

### 3.4 RTS 指令回令映射

| 指令 | 台词语义 | key |
|---|---|---|
| `command_attack`（单点点名，**空中目标**） | "正在追击 <目标>" | `RADIO_ACK_PURSUE_*_FMT` |
| `command_attack` / `command_attack_all`（**地面/水面目标**） | "锁定 <目标>，发起打击" | `RADIO_ACK_STRIKE_*_FMT` |
| `command_attack_all`（轮盘集火，带包围轴，**空中目标**） | "正在包围 <目标>" | `RADIO_ACK_SURROUND_*_FMT` |
| `command_guard` | "正在掩护你" | `RADIO_ACK_COVER_*` |
| `command_regroup` | "正在向集合点靠拢" | `RADIO_ACK_REGROUP_*` |
| `command_evacuate` | "脱离中" | `RADIO_ACK_EVAC_*` |

`<目标>` 取被指目标的 `callsign`（空则退回其 `display_name`，再空则 `"目标"` 的 i18n key）。

**空/地分流**（`SquadCommandController._strike_or_pursue`）：目标 `is Aircraft` → 走空战词（追击/包围）；否则（地面单位/舰船等）→ 走 `ack_strike`（打击语义），**不喊空战的"咬住/追击/包围/切断退路"**。集火包围分支对地面目标同样一律退回 `ack_strike`。

**说话人选取**：从玩家小队成员里挑一名**非玩家操控机**且存活者（随机）。全队只剩玩家本人 → **不发**回令（玩家不会自己回自己的令）。

### 3.5 选词与防重复

每个 key 组是一个字符串数组。选取时随机取一条，但**不得等于该组上一次选中的 key**（组内条数 ≥2 时）。实现为每组记一个 `_last_pick` 索引，命中重复则取 `(idx + 1) % size`。

### 3.6 生命周期

- `RadioChatter` 由生存模式在建 `ZoneHint` 之后创建并 `add_child`。
- 局内重开 / 回主菜单：节点随场景销毁，无全局静态残留状态。
- 冷却计时与队列均为实例字段，不跨局泄漏。

## 4. 结构与组成（Structure）

| 部件 | 职责 |
|---|---|
| `RadioChatter`（CanvasLayer） | 队列 + 状态机 + 显示 + 触发音效。唯一的公开入口 `say()` / `say_unit()` / `say_sequence()` |
| `ChatterLines`（纯数据 RefCounted） | 台词表：触发 id → i18n key 数组；BOSS 专属序列表；选词防重复 |
| `AudioManager.play_radio(id)` | 新增。挂在既有但闲置的 `Radio` 总线上的专用 `AudioStreamPlayer`；素材缺失静默 |
| 触发接线 | 分散在既有调用点，每处 ≤ 4 行，全部走 `is_instance_valid` 守卫 |

**依赖方向**：触发点 → `RadioChatter`（单向）。`RadioChatter` 不反向读任何游戏状态，不持有 Aircraft 引用过夜（入队时即把呼号/颜色**快照成字符串与 Color**，说话人随后阵亡不影响显示）。这条是刻意的解耦——避免 kill feed 早期踩过的悬垂引用。

## 5. 验收标准（Acceptance / Litmus）

**无头基线已验证**（`--bench=chatter`：v8 为 101 项断言全绿）：

- [x] 时长公式（基础 / 逐字 / 封顶）与 §2.2 一致。
- [x] 阵营色全部取自 `GameConstants` FactionPalette，敌我不同色。
- [x] **绝不打断**：最高优先级条目插入时，正在播的低优先级条目不受影响，插入者排队等待。
- [x] 队列上限 3；同优先级第 4 条被丢弃；更高优先级顶掉最低者且队列不膨胀。
- [x] 类别冷却：入队即起算，冷却内同类别被拒，不影响其它类别，到期恢复。
- [x] 过期丢弃对反应式战况生效；BOSS 序列的收尾句**豁免**、必定播出。
- [x] BOSS 登场三句顺序与说话人正确（`WRAITH-01 → WRAITH-02 → WRAITH-01`），色为精英红。
- [x] 未登记 BOSS 回退默认挑衅序列，不静默。
- [x] 敌方减员里程碑：11 次不触发，第 12 次触发；冷却内不重复；三档阈值正确。
- [x] 选词防重复：连抽 60 次无相邻重复。
- [x] i18n：91 个台词 key 全部有三语译文（`tr()` 不返回 key 本身）；`_FMT` 台词均含 `%s`；`radio.csv` 另含八方向与说话人辅助 key，共 103 行。
- [x] 呈现层：呼号单独成行、正文带 `<< >>`、呼号取纯阵营色、正文更淡且淡化方向为**向白**。
- [x] 说话资格门：无人机族 + 被动杂兵全部沉默；有人战斗机 + BOSS 有台词；未登记机型默认沉默；
      `no_pilot` 硬规则压过 `has_radio_voice`（漏设也不会开口）。
- [x] 三层节流：全局冷却挡住【其它 trigger、其它冷却桶】的普通语音；冷却记在**桶**名下（同桶不同
      trigger 互相挡住）；概率骰 2000 次采样命中率与配置值一致（±0.08）。
- [x] 分类：`boss_*` 为 scripted 且**无视全局冷却必定入队**、且**不重置**全局冷却；未登记 trigger
      保守按 ambient。
- [x] 数据外置：台词/权重/冷却/概率全部从 JSON 读；JSON 里每个普通 trigger 都有台词（防打字错导致
      该事件永远静默）。
- [x] 全量回归门 `--bench=all` 25 项测试 0 失败，无回归。
- [x] v8 三语与结构：全部新 key 三语齐全；只有 `_FMT` key 强制含 `%s`；`ack_pursue` 抽到普通句并带 `fmt_args` 时原样播出。
- [x] v8 Boss 数据与闭锁：WRAITH 减员仅一次；CSG 定期 F/A-18 首次成功喊话后闭锁；CSG phase2 两句顺序正确；Goose 仅在 MQ-X 实际释放后调用 phase2。
- [x] v8 战区静态/聚焦验证：轰炸通报方位取实际目标坐标；海/空首次进入选真实单位；地面感谢要求友军存活；机场解放代入真实长机呼号。
- [ ] v8 BOSS 与战区完整实战时序、队列听感仍需 4.7+ 引擎内 playtest；本轮不把聚焦测试等同于实机验收。

**待引擎内验收**（需人眼/人耳）：

- [ ] BOSS 登场时台词条位置不与时间/击杀/云层/BOSS 面板/ZoneHint 重叠，读得清。
- [ ] 长台词换行后背景带高度正确、无跳变；渐变两端淡出观感接近参考图。
- [ ] 淡入淡出观感自然，间隔不显得拖沓或急促。
- [ ] 玩家小队僚机击坠敌机 → 蓝色回报；ALLY 说话 → 绿色；敌方 → 橙/红。
- [ ] RTS 下达攻击/包围/掩护令 → 出现对应回令，且**只出一条**（非全队 4 条）。
- [ ] 实战密度体感：混战中台词不显得聒噪，也不至于长时间沉默。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（本系统仅 1 个 O(1) `_process`）。
- [ ] 音效素材到位后，底噪音量与 BGM/SFX 的相对关系合适。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 管线与范例（本批）
- [x] `ChatterLines` 数据表 + 选词防重复
- [x] `RadioChatter` CanvasLayer：队列 / 优先级 / 冷却 / 淡入淡出 / 状态机
- [x] `AudioManager.play_radio()` + `RADIO_FILES` 注册 + 缺失素材静默
- [x] 生存模式接线（实例化）
- [x] BOSS 登场 / 交战序列（**范例**，三个 BOSS 各一套）
- [x] `splash` / `eject` / `enemy_attrition` 接 `kill_recorded`
- [x] `break` 接 `set_evasion_mode` 上升沿
- [x] RTS 五条指令回令
- [x] 僚机加入
- [x] i18n 三语
- [x] 无头测试 `test_radio_chatter.gd` + 注册 `--bench=chatter`

### 阶段 2 — 2026-08-10 Notion 修订
- [ ] 扩写既有台词池并同步中/英/日三语
- [ ] WRAITH 减员、CSG 舰载机补充与 Phase 2、Mother Goose MQ-X Phase 2 接线
- [ ] 轰炸护航真实八方向双句通报
- [ ] 海 / 空 / 地战区与机场解放无线电接线
- [ ] 扩展 `--bench=chatter` 与相关 Boss / 战区无头回归
- [ ] 将实装状态回写原 Notion 页面，不覆盖用户原文

### 阶段 3 — 待 playtest 后决定
- [ ] 真实无线电音效素材接入（当前留接口）
- [ ] 语音台词（TTS / 配音）—— 需先确认文本定稿
- [ ] 更多触发：低油量、其它导弹告警、僚机阵亡后的复仇台词
- [ ] 台词按 BOSS/敌人**性格**分组扩写（当前仅 BOSS 有专属组）

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

> 本节只列文件，**不写行号**（spec 硬约定，`tools/verify_doc_anchors.py` 会把 spec 里的行号
> 当分层违规报出来）。带行号、按"我要改什么 → 去哪"组织的导航在
> [code-index.md「无线电通讯」段](../../reference/code-index.md)。

| 关注点 | 文件 |
|---|---|
| **★ 唯一数据源**（台词 key / 权重 / 冷却 / 概率 / BOSS 对话 / 说话白名单） | `resources/chatter/radio_chatter.json` |
| 台词文本三语 | `i18n/radio.csv`（`RADIO_*` 前缀，独立分表） |
| 显示 + 队列 + 三层节流 | `scripts/survivor/radio_chatter.gd` |
| 数据加载器（零数值） | `scripts/survivor/chatter_lines.gd` |
| 说话资格硬规则 | `scripts/aircraft.gd`（`can_speak_on_radio` / `has_radio_voice`） |
| 资格赋值 | `scripts/survivor/survivor_spawner.gd`、`mother_goose_uav_swarm.gd`、`mother_goose_boss.gd` |
| 触发接线 | `scripts/survivor/survivor_mode.gd`、`scripts/survivor/ace_squad.gd`、`scripts/survivor/f47_ace_squad.gd`、`scripts/survivor/carrier_strike_group.gd`、`scripts/survivor/mother_goose_boss.gd`、`scripts/survivor/zone_mission.gd`、`scripts/survivor/zone_atmosphere_combat.gd`、`scripts/events/boss_encounter_event.gd`、`scripts/rts/squad_command_controller.gd` |
| 信号声明 | `scripts/event_logger.gd`（`kill_recorded` / `evasion_started` / `afterburner_engaged` / `wingman_joined`） |
| 信号发出 | `scripts/aircraft.gd`、`scripts/squad_factory.gd` |
| 音频 | `scripts/audio/audio_manager.gd`（`play_radio` / `RADIO_FILES` / Radio 总线） |
| 无头测试 | `scripts/tests/test_radio_chatter.gd`（`--bench=chatter`），注册于 `scripts/bench/bench_runner.gd` |
| 导出配置 | `export_presets.cfg`（`include_filter` 须含 `*.json`） |
| reference 索引 | code-index.md「无线电通讯」段 / script-index.md 三行 / playbook.md §10 / enemy-index.md 13 步清单第 10 步 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-08-19 | 11 | 护送响应改为轰炸队后方追击后，无线电同步报告敌追击编队从后方接近并请求近空掩护；保持纯军事态势包装，不暴露玩家介入、航程阈值、强制失败或 XP 数值。 |
| 2026-08-19 | 10 | 护送开始通报从固定 J-7 截击包改为动态敌方响应编队，并明确告知航程中段前必须建立玩家护航，否则轰炸编队会中止任务。 |
| 2026-08-18 | 9 | 轰炸护送任务增加两条 mandatory scripted 通报：截击包实际生成时明确提示护航压力；目标摧毁并发放经验后确认任务完成与实际 XP 数值。 |
| 2026-08-10 | 8 | 按用户更新的 Notion 原页扩写三语台词并完成运行时触发：WRAITH 首次减员、CSG 定期 F/A-18 / 双句 Phase 2、Mother Goose MQ-X Phase 2；轰炸护送按真实目标坐标通报八方向；海/空/地战区与机场解放无线电；`ack_pursue` 允许格式化句与普通句共池。Shadow 聚焦回归：chatter 101/101、boss_phase 33/33、boss_hunter 119/119、boss_progression 22/22、zone_atmosphere 29/29，三语 radio 资源各 103 条。字体与完整实机试听留后续。 |
| 2026-08-10 | 7 | 本地化拆分后将全部 `RADIO_*` 文本迁入独立 `i18n/radio.csv`，运行时 key 与 `radio_chatter.json` 结构保持不变；新增跨分表唯一性/资源注册审计，Shadow `chatter` 91/91。 |
| 2026-08-09 | 6 | 新增奖励目标与轰炸护送两个 scripted 通报；两者均在目标实体生成前 6 秒入队，不受 ambient 节流影响。Shadow `chatter` 91/91。 |
| 2026-08-08 | 5 | 新增每局一次的 Hound-1/Hound-2 王牌截击支援固定双句；两条均为 scripted，权重 94/93，使用 ALLY 绿色与固定呼号。Shadow `chatter` 89/89。 |
| 2026-07-26 | 4 | 新增 `ace_spawn` trigger（scripted / 权重 90）：非 BOSS 王牌中队入场主信号（红横幅收回 BOSS 专属后的替代演出，ace-squadron-tier §2.6 规范化批）。台词池 5 条三语、说话人=王牌长机、单条不成序列（多句对话序列维持 BOSS 专属） |
| 2026-07-20 | 3 | 用户订正三项：① **全局冷却**（普通语音总闸 12s）+ **概率骰**（"偶尔出现一下"的主旋钮），解决"每次点 combat target 僚机必然说话"；② **分类 scripted / ambient** —— 剧情关键节点豁免全部节流、必定播出，普通语音受三层限制；③ **文本与数值全部外置到 `resources/chatter/radio_chatter.json`**，`chatter_lines.gd` 退化为纯加载器，加台词/调手感不用碰代码（新增 §2.9 / §2.10，§2.2~§2.4 重写） |
| 2026-07-20 | 2 | 用户订正：**无人机不得有台词，只有一定等级的敌人配无线电**（新增 §2.8 双门规则 + `VOICED_ENEMY_TYPES` 表 + `kill_recorded` 增 `victim_voiced` 参数）。同批按用户提供的皇牌空战截图重做版式（§2.1：呼号独立成行 / `<< >>` 标记 / 正文向白淡化 / 渐变淡出底 / 自动换行增高） |
| 2026-07-20 | 1 | 初稿 + 阶段 1 实装（管线 + BOSS 登场范例 + 8 类触发）。实装期两处修正：① 冷却改为**入队时**起算（防洪，原设计的播出时起算会让队列被同类台词占满）；② 新增 `NEVER_STALE`，BOSS 剧本序列豁免过期丢弃（否则登场挑衅的收尾句会被砍） |
