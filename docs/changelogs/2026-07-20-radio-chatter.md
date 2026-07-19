# 2026-07-20 — 无线电通讯系统（阶段 1：管线 + BOSS 登场范例）

Spec：[docs/specs/systems/radio-chatter.md](../specs/systems/radio-chatter.md)（spec_version 1，status in-progress）

## 背景

战场是**哑的**：击杀只有左上角一行灰字，BOSS 登场只有一个红色 WARNING 横幅，僚机执行 RTS 命令毫无回应。
玩家操控的是一支小队，却听不见队友的声音。本批补的是临场感与人味，参考《皇牌空战》的无线电。

用户口径的"强化击杀表现"经确认**不是**独立的视觉/音效工作，而是无线电内容的一部分（击坠回报 / 弹射
呼叫 / 敌方减员哀嚎）。因此全部收敛成一个系统 + 一张触发表，而不是两套并行的反馈机制。

## 交付

### 新增

- `scripts/survivor/radio_chatter.gd` — `RadioChatter extends CanvasLayer`（layer 19）。队列 + 优先级 +
  冷却 + 状态机 + 显示 + 音效触发。
- `scripts/survivor/chatter_lines.gd` — `ChatterLines extends RefCounted`。台词 key 表 + BOSS 专属序列 +
  选词防相邻重复。
- `scripts/tests/test_radio_chatter.gd` — 无头回归，注册为 `--bench=chatter`。
- `docs/specs/systems/radio-chatter.md` — spec（SSOT）。
- `i18n/translations.csv` — 49 个 `RADIO_*` key，三语。

### 核心契约

1. **一次只显示一条，绝不打断**（用户硬需求）。优先级只决定排队顺序与满队淘汰，**不触发打断** ——
   被打断的语音是廉价感的头号来源。
2. **不新增全场扫描**。唯一的 `_process` 是 O(1) 计时器（性能守则第 2/4 条）。
3. **入队即把说话人快照成字符串 + Color**，绝不持有 Aircraft 引用 —— 说话人随后阵亡不会留下悬垂引用。
4. 阵营色一律引 `GameConstants` FactionPalette（玩家蓝 / ALLY 绿 / 敌常规橙 / 敌精英红），
   不散写颜色字面量。

### 触发表（8 类）

| 触发 | 挂载点 |
|---|---|
| BOSS 登场（**范例**，2~3 句队内对话） | `boss_encounter_event.gd` `_start`，与 WARNING 横幅并排 |
| BOSS 进入交战 | `survivor_mode.gd` `on_boss_engaged` |
| 击坠回报 / 弹射呼叫 / 敌方减员哀嚎 | `EventLogger.kill_recorded`（既有信号，第 3 个订阅方） |
| break 规避呼叫 | 新 signal `EventLogger.evasion_started`，`Aircraft.set_evasion_mode` 上升沿 |
| 僚机归队 | 新 signal `EventLogger.wingman_joined`，`SquadFactory.register_wingman` |
| RTS 五条指令回令（追击/包围/掩护/集合/撤离） | `squad_command_controller.gd` 各 command_* 末尾 |

RTS 回令是**中队级粒度**：一条命令只回一句，由随机一名存活僚机代表全队应答，绝不 4 架各喊一句；
队里只剩玩家时静默（玩家不会自己回自己的令）。

### 音频

`AudioManager` 的 **`Radio` 总线早在之前就建好了**（频带切割 + 轻失真的人声链，注释写着"Step 2 使用"），
但从未有任何播放器挂上去。本批接上：新增专用 `_radio_player` + `play_radio(id)` + `RADIO_FILES` 注册。

**素材未到位**（用户决定先留接口）：`res://audio/sfx/radio_beep.wav` 缺失时静默跳过，且**不 push_warning**
（每条台词都会调一次，warning 会刷屏）。视觉部分独立可验收。

## 版式（按用户提供的皇牌空战截图重做）

初版把呼号和台词拼成一行（`呼号 ▸ 台词`）放在硬边矩形里。对照参考图后重做：

- **呼号单独一行在上**，正文另起一行，用 `<< >>` 包裹（无线电通话标记，由代码拼，不进 i18n）。
- **呼号取纯阵营色，正文取同色向白靠拢 0.65 的淡色** —— 一眼分出"谁在说"和"说了什么"。
  淡化方向硬性向白：深色背景上变暗会读不出来，已写成断言。
- **背景改为左右淡出的柔和渐变带**（`GradientTexture2D` 生成，无外部素材依赖），不是硬边矩形。
- **长句自动换行，整块高度随行数增长**。高度需等容器解算出宽度后才算得出，因此设文本后等 2 帧再定高；
  这 2 帧被 0.12s(≈7 帧) 的淡入盖住，看不出跳变，且每条台词只算一次而非每帧。

## 频度节流 + 分类 + 数据外置（用户订正第三批）

反馈是"每次点 combat target 僚机基本必然说话"，要"偶尔出现一下就可以，不要太抢戏"。

### 三层节流

普通语音（`ambient`）必须依次通过三道门，任一不过即静默丢弃：

| 层 | 机制 | 默认 |
|---|---|---|
| ① 全局冷却 | 任何一条普通语音入队后，**全场普通语音**静默 | 12s |
| ② 冷却桶 | 同 `cooldown_group` 的最小间隔 | 8~30s |
| ③ 概率骰 | 过了冷却仍要掷骰 | 0.35~1.0 |

**概率骰是"偶尔出现一下"的主旋钮**。用户点名的重灾区（RTS 回令）：五条 `ack_*` 现在**共享一个冷却桶**
且 `chance = 0.35` —— 连点下令不会每次都有人应答。

两个刻意的细节：**冷却在成功入队时起算**（不是播出时），防止一秒内 10 次击杀塞满队列；
**掷骰失败不起冷却**，否则一次运气不好就闷掉整个冷却窗口。

### 分类：scripted / ambient

每个 trigger 声明 `class`。`scripted`（BOSS 登场/交战）**完全豁免三层节流，必定播出**，
且**不占用也不重置**任何冷却账本 —— BOSS 说完话，普通语音的冷却窗口不受影响。
未登记 class 的 trigger **保守按 ambient 处理**，新加的东西不会意外获得强插特权。

原先的 `PRIORITY` 常量改名为 `weight` 并移入数据表，语义不变（只管排队与满队淘汰，永不打断）。

### 数据全部外置

`chatter_lines.gd` 从"装满常量的表"退化为**纯加载器，零数值**。所有台词 key、权重、冷却、概率、
BOSS 对话序列、说话资格白名单都住进 **`resources/chatter/radio_chatter.json`**（跟着仓库既有的
`resources/evolution/evolution_tree.json` 惯例走）。文件头写了完整的编辑说明。

分工：**结构**在 JSON（策划改），**文本三语**在 `i18n/translations.csv`（本地化改），代码只剩队列与显示。
加一条台词 = JSON 加个 key + CSV 加一行，不碰代码。

容错：JSON 缺失/损坏 → 报 error 后系统降级为静默，不崩游戏。静态缓存，全进程解析一次。

**API 变更**：`say_group(cat, speaker, color, group, args)` → `say(trigger, speaker, color, args)`；
`say_unit(cat, unit, group, args)` → `say_unit(trigger, unit, args)`。category 与 group 两个概念合一为 trigger。

### 导出隐患（顺带修）

`.json` 在 Godot 里不是导入资源（没有 `.import` 附属文件），而 `export_presets.cfg` 原本是
`export_filter="all_resources"` + **空的 `include_filter`**。已把 `include_filter` 设为 `*.json`。
这不只保护本表 —— `resources/maps/*.json` 和 `resources/evolution/evolution_tree.json`
（地图与进化树，都是核心数据）此前在同一条船上。**建议下次出包时验证一下这两处仍正常。**

## 说话资格门（用户订正：无人机不该有台词）

无人机没有飞行员，不该有人声。两道门必须同时通过：

1. **硬规则**：`no_pilot` 的机体永不说话，**不可被第 2 条覆盖**。
   复用既有的 `no_pilot` 字段（原用于让无人机免疫 FEAR），不另造概念。
2. **等级门**：机型必须登记在 `ChatterLines.VOICED_ENEMY_TYPES`，**opt-in、默认沉默**。
   opt-in 是刻意的 —— 以后新增敌人默认不会突然开口。

**这张表就是"哪一级敌人配无线电"的唯一调参处。** 当前有台词：13 种有人战斗机
（MiG-29/J-7/F-86/MiG-31/MiG-23/F-100/Su-27/A-7/Q-5/F-4/F-104/Su-35/F/A-18）+ 2 个 BOSS 王牌。
沉默：全部无人机族 + Tu-160/AH-64/CH-47 被动杂兵。

顺带补了两个 `no_pilot` 的既有漏网：**Mother Goose 蜂群 UAV 与 MQ-X 此前没设 `no_pilot`**，
意味着它们不仅会说话，还会吃 FEAR 心理状态 —— 已一并补上。

**AF-03 仍未设 `no_pilot`**（enemy-index 里写明是无人机）。本批只经等级门让它闭嘴，
没动它的 FEAR 行为 —— 那属于状态系统的既有问题，改动会影响平衡，留给你定夺。

### 信号扩展

`EventLogger.kill_recorded` 增加末位参数 `victim_voiced: bool`。该信号只带呼号字符串、不带单位引用，
订阅端无从判断机种，只能由发出端携带。两个既有订阅方（`survivor_hud` kill feed / `roe_director`）
签名同步更新，不消费该字段。

各触发的表现：弹射呼叫**不播**（无人可弹射）；break / 归队**不 emit**；无人僚机不入选 RTS 应答人；
但**减员哀嚎照常计数** —— 说话的是敌方指挥部（有人），它一样会为损失无人机而哀嚎；
**击坠回报照常** —— 说话的是玩家方僚机，与被击坠者是不是无人机无关。

## 实装期的两处设计修正

写测试时暴露的，都已回写 spec §8：

1. **过期丢弃会砍掉 BOSS 挑衅的收尾句。** BOSS 登场是一次性入队的 3 条序列，按每条约 3.4s 计，第 3 条要
   等到约 6.8s 才轮到播出，超过 `QUEUE_STALE_SEC = 6.0` 会被当噪音丢掉 —— 而那正是最狠的一句。
   过期机制的本意是"迟到的战况播报等于噪音"，对预先写好的桥段不成立。
   → 新增 `NEVER_STALE`，`boss_spawn` / `boss_engage` 豁免。
2. **冷却起算时机。** 原设计写的是"播出瞬间起算"，但那样一秒内 10 次击杀会全部入队、把队列占满，冷却
   形同虚设。→ 改为**成功入队瞬间**起算。代价是被淘汰的条目也占冷却，该路径罕见且后果仅是少说一句。

## 顺带改动

- `BossEncounter` 新增 `boss_id` 字段，由 `BossRegistry.instantiate` 印上（此前 registry 只印
  display_name / callsign_prefix / bgm，拿不到 id）。台词序列按 id 查表需要它，对以后按 BOSS 分支的
  系统也通用。
- `RadioChatter` 刻意建在 survivor_mode 的战区 `if` **之外** —— `_zone_hint` 在 boss_debug / bench 模式
  是不建的，而 **boss_debug 正是用来看 BOSS 登场台词的路径**，跟着跳过就看不到范例了。

## 验证

- `--bench=chatter`：**50 项断言全绿**。覆盖时长公式 / 阵营色 / 不打断契约 / 队列上限与淘汰 / 冷却 /
  过期丢弃与 BOSS 豁免 / BOSS 序列顺序与说话人 / 减员里程碑 / 选词防重复 / **i18n 全 49 key 有译文**。
  测试脱离场景树手工驱动 `_process`，时序完全确定，不依赖引擎主循环或视口。
- `--bench=all`：**25 项测试 0 失败**，无回归。
- `--bench=stress_40 --duration=15`：无新增报错。退出时的 `1 CanvasItem RID leaked` 经 git stash 对照
  确认为**改动前既有**，与本批无关。

## 待办

- **音效素材**（用户之后放 `audio/sfx/radio_beep.wav`）。
- **playtest**：台词条位置是否与顶部其他 HUD 元素打架、淡入淡出观感、实战密度体感（会不会聒噪/太沉默）。
- 阶段 2 候选（spec §6）：语音配音、更多触发（低油量/导弹告警/战区攻克/僚机阵亡后的复仇台词）、
  按敌人性格分组扩写台词。

## 注意

新增了 `class_name`（`RadioChatter` / `ChatterLines`）与 i18n key，**必须让 Godot 编辑器导入一次**
（或 `godot --headless --path . --import`）才能刷新全局类缓存和 `.translation`，否则无头跑会报
"Identifier not declared" 且 `tr()` 原样返回 key。本批已跑过导入，`.translation` 三份已入库。
