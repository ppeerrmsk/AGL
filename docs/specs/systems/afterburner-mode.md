---
id: afterburner-mode
kind: system
status: done  # 2026-07-29 用户确认工程落地可收口
schema_version: 1
spec_version: 3
owner: ppeerrmsk
depends_on: [wingman-escort-evasion]
reconstruction_complete: true
---

# 加力模式（规避模式资源化改造）

> 把语义模糊的"规避模式"改造成显眼的小队级**充能资源（充能制/电池模型）**"加力模式"：只要有能量就能一键启动，全队极速冲刺 + 机炮完全打不中 + 滚转躲导弹，激活中持续耗能、耗尽自动结束、玩家可随时再按 E 提前关闭（剩余能量保留）。代价是加力期间无法攻击 + 能量需时间/击杀回充。给玩家一个明确的"脱离-重整-再入"战术按钮。

## 1. 设计意图（Why）

- **体验目标**：
  - 现状痛点：规避模式（E 键开关）名字和作用都让人疑惑——"规避了什么？"收益不可见（+20% 机炮闪避是暗数值）、无成本无限开关导致没有使用决策，玩家几乎不用。
  - 改造后：**名字直白（加力）、收益直观（全队瞬间拉满速 + 敌人打不中）、成本清晰（一条看得见的能量条，激活中肉眼放空）**。被导弹雨围剿时按下去 = 全队脱离火网的"逃命键 / 重新进场键"。
  - 充能制（电池模型）：能量是一池连续资源，随开随关、按需短点或长烧，玩家自己权衡"烧多久 / 留多少"。击杀充能形成正循环：打得凶 → 充得快 → 更敢往火网里进场。
- **Litmus 自检**（引 [DESIGN_PHILOSOPHY.md](../../DESIGN_PHILOSOPHY.md)）：
  - **单杠杆**：一条能量资源、一个开关按钮。无档位、无滞回、无部分激活（仍是全队广播）。
  - **效果即反馈**：速度陡增（加力焰）+ 子弹全闪避触发滚转动画 + 导弹被甩偏飞——效果本身就是反馈，不加中介 HUD 数字。充能条是资源本身的可视化，不是解释性 UI。
  - **不破坏"一击毙命"张力**：不是无敌泡泡——导弹保留 10% 极限命中、能量有限（满格最多连烧 6 s 且期间不回攻）、期间全队丧失攻击能力（有真实代价）。
  - **输入语法**：E / 按钮 = 全队广播（符合"轮盘/模式键带动全体"的操作语法，不设计部分队员加力）。
- **反模式规避 / 底层复用铁律**（用户点名"底层代码什么都不要变"）：
  - `evasion_mode` 字段名、set/传播链（`escort_cover_active` 广播）、AI 自保 `enter_evade` 语义、§1.2 技能钩子、TORP/WMN 投放**全部保留原样**。（例外：无线电呼叫从"break"分离为专属"加力冲刺"——v3 充能制后加力已非躲导弹，见 §3.5。）
  - 改造 = 三层叠加：① 生存层**资源 gate**（E 键先过资源再调既有 `set_evasion_mode`）② 新窗口标志 `afterburner_window_active` 挂**强 buff**（100% 闪避 / 躲弹 / 禁攻击 / 满速地板）③ UI 重命名 + 充能条。
  - 模式隔离：资源 gate 只在生存层（survivor_mode / hud）；共享层只多读一个 bool 字段。沙盒直连 `set_evasion_mode` 行为不变。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 资源常量（挂 AfterburnerCharge 模块）

**充能制（电池模型）**：`charge` 是一池连续能量（秒），激活条件 = `charge > 0`（有能量即可，不必满）。激活中按 `DRAIN_RATE` 实时耗能，耗尽（≤0）自动关闭；玩家可随时再按 E 提前关闭，剩余能量保留。

| 常量 | 值 | 说明 |
|---|---|---|
| `CHARGE_MAX` | 6.0 s | 能量池容量上限 = 满能量下最多**连烧 6 s** 加力（对齐旧固定窗口时长，避免变成准无限）。 |
| `CHARGE_RATE` | 0.2 /s | 被动充能速率（空 → 满 ≈ 30 秒 = 6 ÷ 0.2，沿用旧"30s 攒一次"节奏）。 |
| `DRAIN_RATE` | 1.0 /s | 激活时耗能速率，能量按秒 1:1 消耗（可被 `duration_mult` 减慢）。 |
| `KILL_CHARGE` | 0.8 s | 小队任一成员击杀 1 个敌人（空中或地面）→ +0.8 s（占满池 13%，满池仍需 ~7.5 杀，与旧 4/30 同比例）。 |
| 激活条件 | `charge > 0` | 有能量即可一键启动；能量为 0 时按键失败静默（条状态即反馈）。 |
| 初始 charge | `CHARGE_MAX`（满） | 开局即可用，保证新机制第一时间被发现。可调。 |
| 激活消耗 | 随时间耗能 | 激活中每秒 -`DRAIN_RATE`；不再"激活瞬间清零"。激活中击杀照样 +4（边烧边攒）。 |
| 激活中被动充能 | 0 | ACTIVE 期间被动充能暂停，关闭后恢复。 |
| 关闭方式 | 耗尽自动 / 玩家再按 E | 二者共用 `_deactivate()`；提前关闭保留剩余能量。 |

### 2.2 窗口内强 buff（挂 `Aircraft.afterburner_window_active`，全队生效）

| 项 | 值 | 说明 |
|---|---|---|
| 机炮闪避 | **100%**（无条件闪避，绕过全局 dodge cap 0.85） | 每次闪避照旧触发滚转动画（沿用既有节流）。理由：能量限量 + 期间无法攻击的资源代价，换取 cap 的 15% 命中窗口豁免。 |
| 导弹躲避 | 命中判定瞬间 roll，`MISSILE_JAM_CHANCE = 0.90` | 成功 → 弹置 `is_flare_jammed`（走既有"jammed 弹永不命中"偏飞契约）+ 本机触发滚转动画；失败（10% = "非常极限的情况"）→ 正常命中。**每弹天然只 roll 一次**（jam 后不再参与命中检测；失败当帧即爆）。与热诱弹无关——这是无 flare 时也成立的兜底层。 |
| 禁攻击 | 机炮 / 主导弹 / 副槽导弹 / 火箭全静默 | 复用既有 evasion 静默语义并扩展到全队。`commanded_target` **不清除**（玩家命令铁律）——仅暂停开火，窗口结束自动恢复交战。 |
| 禁攻击例外 | 空射鱼雷（TORP）、忠诚僚机（WMN）照旧投放 | 二者本就设计为"仅规避模式投放"的专属装备，与加力"脱离中反击"语义契合；砍掉则装备彻底作废。 |
| 速度 | 目标速度**地板 = 有效顶速**（`effective_max_speed_kmh`） | 无论有无移动命令，窗口内目标速度不低于顶速（点哪都全速飞）。满足"速度直接提升到当前飞机的速度上限"。有 `evasion_speed_boost` 技能时顶速 ×1.4（超频，见 §3.5）。 |
| 加速度 | `ACCEL_MULT = 3.0` | 加力期间加速度 ×3。没有它，典型加速度从巡航加到顶速需 ≈7 s，短点加力根本"快不起来"。失速地板照旧（不破坏"转弯不得自陷失速"）。 |
| 适用对象 | **仅玩家小队**（长机 + squad.leader == 长机的僚机） | 敌机 / 友军 NPC 番队永不置此标志。敌机 AI 规避维持旧 +20% 闪避，不然玩家机炮打不中规避中的敌机。 |

### 2.3 i18n（三语，`i18n/translations.csv`）

改名（既有 key 改文案）：

| key | zh | en | ja |
|---|---|---|---|
| `TACTIC_EVADE_FMT` | `E 加力: %s` | `E Afterburner: %s` | `E アフターバーナー: %s` |
| `UPGRADE_EVASION_SPEED_BOOST_NAME` | 超频加力 | Overdrive Burner | オーバードライブAB |
| `UPGRADE_EVASION_SPEED_BOOST_DESC` | 加力模式顶速 +40% | Afterburner mode top speed +40% | ABモード最高速+40% |
| `UPGRADE_EVASION_WEAPON_CD_DESC` | 加力模式中武器冷却流逝 ×2（出加力即就绪） | Weapon cooldowns tick 2× during Afterburner | ABモード中武器CD進行2倍 |
| `UPGRADE_EVASION_STEALTH_DESC` | 加力模式中获得隐身效果 | Stealth while in Afterburner mode | ABモード中ステルス |
| `UPGRADE_EVASION_HERBST_DESC` | 加力模式下来袭导弹/后方机炮追尾时自动启动赫尔贝特轮（J-Turn） | Afterburner mode auto-triggers J-Turn vs incoming missile / rear gun chase | ABモードで来襲ミサイル/後方追尾時にJターン自動発動 |
| `UPGRADE_EVASION_OVERSTOCK_DESC` | 加力模式中每 4s 装填 1 发导弹（突破上限至 2 倍） | Afterburner mode reloads +1 missile per 4s up to 2× cap | ABモード4秒毎ミサイル+1（上限2倍） |

新增（充能条 / 按钮三态）：

| key | zh | en | ja |
|---|---|---|---|
| `AB_STATE_READY` | 就绪 | READY | 準備完了 |
| `AB_STATE_CHARGING_FMT` | 充能 %d%% | CHG %d%% | 充填 %d%% |
| `AB_STATE_ACTIVE_FMT` | %.1fs | %.1fs | %.1fs |

（tooltip 六键 `TOOLTIP_EVADE_ON/OFF_*` 全部改写为加力语义：ON=激活中效果说明，OFF=充能/激活方法+效果预览。）

（`UPGRADE_EVASION_*_NAME` 中"雾隐机动 / 危机赫尔贝特 / 弹仓过载 / 规避狂暴"不含"规避模式"字样的名字保留；`规避狂暴` 因语义反转改为 `蓄势狂暴`，en `Primed Frenzy`，ja `チャージフレンジー`。）

## 3. 行为与公式（How）

### 3.1 资源状态机（小队级单实例，生存模式专属）

充能制只有两态：IDLE（充能中）与 ACTIVE（耗能中）。没有"必须满格"的 READY 门（满格只是能量条颜色到顶，不是激活前提）。

| 状态 | 进入条件 | 期间行为 | 退出 |
|---|---|---|---|
| IDLE | 初始 / 加力关闭后 | charge += CHARGE_RATE × dt；击杀 +KILL_CHARGE；clamp 到 CHARGE_MAX | 玩家按 E 且 charge > 0 → ACTIVE |
| ACTIVE | 玩家触发（charge > 0） | charge -= DRAIN_RATE × dt；被动充能暂停；击杀仍 +4（边烧边攒）；再按 E → 立即关闭 | charge ≤ 0（自动）或玩家再按 E（提前）→ IDLE |

- 升级 UI 暂停（get_tree().paused）期间模块不被驱动 → 充能与耗能计时自然冻结。
- IDLE 时按 E：charge > 0 则启动；charge = 0 则无操作（按钮/条状态即反馈，不做弹窗）。
- ACTIVE 时按 E：立即关闭（剩余能量保留），是开关而非"激活中按键无效"。

### 3.2 激活流程（触发瞬间）

```
toggle(leader):                        # E 键 / HUD 按钮统一入口，开关语义
  if leader invalid: return false
  if active:                           # 激活中再按 → 提前关闭
    _deactivate(); return false
  if charge <= 0: return false         # 无能量，启动失败静默
  active = true                        # 不再清零 charge！能量随时间耗
  window_members = [leader] + 所有 squad.leader == leader 的存活僚机（快照，不追新）
  for m in window_members: m.afterburner_window_active = true
  leader.set_evasion_mode(true, suppress_radio=true)  # 既有链路原样：清指令、planner EVADE(max+AB)、
                                       # 传播 escort_cover_active 给僚机、evasion_modifiers cd 缩放、
                                       # 隐身/overstock 技能计时启动；但抑制 break，改喊加力冲刺 ↓
  emit EventLogger.afterburner_engaged(leader.callsign, leader.team)  # → RADIO_AFTERBURNER_*
  return true

update(delta) 里 ACTIVE 分支:
  charge -= (DRAIN_RATE / max(duration_mult,ε)) * delta
  if charge <= 0: charge = 0; _deactivate()   # 耗尽自动关闭

_deactivate():                         # 耗尽 / 提前关闭 / 长机销毁共用
  active = false
  for m in window_members(valid): m.afterburner_window_active = false
  leader.set_evasion_mode(false)       # 若玩家中途下令已退出则为 no-op（边界差量对称）
  window_members.clear()
```

- 窗口成员为**激活瞬间快照**：中途换帅（1-4 切控）、新僚机入场都不改变本次加力的 buff 归属；成员遍历带 `is_instance_valid` 守卫。
- 模块**不缓存长机引用**（`toggle` 传参即用），规避 SEAM-019 换帅悬挂引用问题。

### 3.3 窗口内交互规则（与既有系统的叠加）

| 场景 | 行为 |
|---|---|
| 玩家加力中下移动/攻击命令 | 照现状：命令下达会退出长机 `evasion_mode`（S 型自动机动、TORP 投放等技能钩子停止）。但 `afterburner_window_active` 独立于 evasion，随能量维持——强 buff（闪避/躲弹/静默/满速地板/加速）**持续到耗尽或玩家再按 E**。点哪就全速飞哪。 |
| 攻击命令在窗口内下达 | `commanded_target` 正常记录（铁律），开火被静默压住，窗口结束立即恢复开打。 |
| 僚机 | 照旧收 `escort_cover_active`（护卫姿态：被真威胁才自保规避、替长机投护卫焰），叠加窗口强 buff。跟随长机满速飞行依赖既有编队追赶逻辑（长机满速 → 僚机 max+AB 追）。 |
| AI 自保规避（含玩家托管机被咬、无 flare 时 `enter_evade`） | 照旧置 `evasion_mode`，享受**旧弱 buff**（+20% 闪避、planner max+AB、武器静默）。**不**触发窗口、不吃强 buff、不消耗资源。 |
| 敌机 EVADE | 同上，完全不变。 |
| 沙盒模式 | E 键直连 `set_evasion_mode`，无资源系统，行为不变（沙盒已废弃）。 |
| 窗口内长机被击落 | 窗口计时照走到期清理（成员数组有 valid 守卫）；资源随局销毁。 |

### 3.4 机炮闪避 / 导弹躲避判定（伪代码）

```
take_bullet_damage(...):                     # 既有闪避栈之后
  effective_dodge = clamp(既有线性加和, 0, 0.85)
  if afterburner_window_active:
      effective_dodge = 1.0                  # 绕 cap，无条件闪避
  roll → 闪避成功照旧触发滚转动画、伤害归零

missile_manager 命中检测（fuse 距离 + 高度容差成立瞬间，云 miss roll 之后）:
  if target is Aircraft and target.afterburner_window_active:
      if randf() < 0.90:
          missile.is_flare_jammed = true     # 走既有偏飞契约：不再参与命中/CIWS/补射计伤
          target._trigger_evasion_roll()     # 贴脸滚转甩掉导弹的视觉
          log AB_MISSILE_DODGE
          continue
      # else：10% 极限命中，正常爆炸
```

### 3.5 与既有技能/机制的冲突裁定（用户点名排查项）

| 机制 | 关系 | 裁定 |
|---|---|---|
| 全局机炮闪避 cap 0.85 | **结构冲突** | 加力期间短路为 1.0（唯一绕 cap 通道，能量限量资源代价换取）。 |
| `hp_up` 闪避（cap 40%）/ `low_alt_gun_dodge` +50% / 对头闪避 +60% / HIGH 档 +20% / evasion +20% | 被覆盖 | 窗口内 100% 覆盖一切；窗口外照旧生效。无叠加 bug（短路发生在 clamp 之后）。 |
| `evasion_speed_boost`（巡航 ×1.4 并抬顶速 cap） | 增强 | 窗口基线=顶速，此技能让顶速本身 ×1.4 → 窗口内超频 140%。技能价值保留，文案改"顶速 +40%"。 |
| `evasion_weapon_cd`（进入时 cd ×0.5 缩放） | **语义反转** | 机制零改动：窗口内禁攻击，但 cd 缩放让冷却在窗口内双倍流逝 → "出加力瞬间武器就绪"。文案随之改写（§2.3）。 |
| `evasion_overstock`（每 4s +1 弹） | 成立 | 加力持续越久装填越多（充能制下不再固定 6s，按实际烧的时长算）。文案不变（速率仍准确）。 |
| `evasion_stealth`（进入 2s 后隐身） | 成立 | 加力持续 > 2s 即进入隐身段，直到关闭。 |
| `evasion_herbst` / `cobra_skill`（panic_save） | 成立 | 防御机动在窗口内照常触发，与 90% 躲弹并行不悖（机动是表演层，jam roll 是判定层）。 |
| TORP / WMN（仅 evasion 期投放） | 保留例外 | 见 §2.2 禁攻击例外。HUD 灰显文案 "(Evade)" 改 "(AB)"。 |
| `command_sprint`（紧急集合 ×1.4） | 正交 | 速度取各来源最大值语义，无叠乘异常。 |
| BLOODLUST / OVERLOAD / lock_panic（G/加速 buff） | 正交 | 走 effective_* accessor 与 OVERLOAD accel 既有注入点，与窗口 accel ×3 相乘可接受（都是短窗口）。 |
| 玩家命令铁律（commanded_target） | 兼容 | 加力静默不清除点名目标，仅在加力期间暂停开火（玩家自己按的全队防御指令，优先级成立）。 |
| 敌机 AI `evasion_mode` | 隔离 | 强 buff 只认窗口标志；敌机永不置窗口标志。 |
| 无线电呼叫 / kill feed | **分离** | 加力已不是躲导弹：`toggle` 启动时 `set_evasion_mode(true, suppress_radio=true)` 抑制 break，改 emit `afterburner_engaged` → 长机喊"全队加力冲刺"（`RADIO_AFTERBURNER_*`，radio-chatter 新 trigger）。真·躲导弹（AI `enter_evade`）仍走 `evasion_started` → break，语义各归各。 |
| `skill_evade_missile_overload`（死里逃生：躲弹→超载 8s） | 不联动 | 该钩子只挂 flare jam 成功路径；窗口 90% 躲弹是模式豁免，不算技能语义的"躲弹"，避免窗口内连躲 N 弹刷新超载。 |
| 忠诚僚机 drone / ACE 友军番队 | 不适用 | drone 不进窗口成员集（沿用 `_propagate` 的 is_drone 排除）；友军番队 leader 非玩家，天然排除。 |

### 3.6 充能事件源

| 来源 | 判定 | 挂点语义 |
|---|---|---|
| 空中击杀 | `EventLogger.kill_recorded` 信号，`killer_team == TEAM_PLAYER && victim_team == TEAM_HOSTILE` | 与 kill feed / roe 热度同源（生存模式已订阅处顺路调用）。 |
| 地面/舰船击杀 | spawner 击杀检测中"玩家方击杀地面单位"的既有热度挂点 | 与 roe `add_heat` 地面分支同点位。 |
| 被动 | 生存主循环驱动 `update(delta)` | 升级 UI 暂停时自然冻结。 |

## 4. 结构与组成（Structure）

- **模块** `scripts/survivor/afterburner_charge.gd`（`AfterburnerCharge extends RefCounted`，模块化约定）：持 charge / active / window_members；方法 `update(delta)`（ACTIVE 耗能 + 自动关闭）、`toggle(leader)`（开关）、`on_kill_charge()`、`_deactivate()`、查询器 `ratio()` / `is_active()` / `is_full()` / `remaining_seconds()`。不持长机引用。
- **Aircraft 新字段** `afterburner_window_active: bool`（共享层运行时标志，仅生存层写入；沙盒恒 false）。
- **判定点（共享层，各 ≤5 行）**：`take_bullet_damage` 闪避短路；missile_manager 命中 roll；`aircraft_weapons` 三处静默（机炮扫描 / 残梭 / 副槽）扩展 `or afterburner_window_active`；`aircraft_physics.update_speed`（+ 预测镜像）速度地板与 accel ×3。
- **接线（生存层）**：survivor_mode 建实例、`_process` 驱动、E 键与 HUD 按钮走 `toggle`（开关）、击杀 handler 调 `on_kill_charge`。
- **HUD**：战术按钮区 `_btn_evasion` 上方加能量条（StyleBoxFlat 线框，宽同按钮，高 ~10px）：条恒为 `ratio()`（charge/CHARGE_MAX）；满=亮橙 READY，部分=暗橙充能%，ACTIVE=亮青随耗能实时放空 + 按钮显剩余续航秒数；按钮文案三态（§2.3 key）。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 开局能量满；按 E 全队进入加力：速度明显陡增至顶速（加力焰亮）、能量条肉眼放空、耗尽自动退出后开始重充，~30 秒充满。
- [ ] **充能制核心**：能量未满时按 E 也能启动（只要 charge > 0）；激活中再按 E 立即关闭且剩余能量保留；能量为 0 时按 E 无反应。
- [ ] 加力期间敌机机炮对全队 0 伤害（每次闪避有滚转动画）；EventLogger 无玩家队 GUN 受伤条目。
- [ ] 加力期间无 flare 被导弹追：约 9/10 弹在命中瞬间被甩偏（AB_MISSILE_DODGE 日志 + 偏飞），偶发命中存在。
- [ ] 加力期间全队机炮/导弹/火箭静默（含被点名 commanded_target 的僚机）；关闭后点名目标自动恢复开打。TORP/WMN 照旧投放。
- [ ] 加力期间下移动命令：飞机满速飞向目标点，强 buff 不掉。
- [ ] 击杀充能：非加力时击杀敌机 charge 可见 +4s 跳增；地面击杀同样。
- [ ] 强化加力（ab_duration）：满能量续航从 6s 拉长到 9s/12s（耗能减慢），HUD 剩余秒数随之变长。
- [ ] AI 自保规避（玩家托管被咬 / 敌机 EVADE）不触发加力强 buff、不消耗能量；敌机规避时玩家机炮命中率与改造前一致（+20% 闪避不变）。
- [ ] 沙盒 E 键行为不变。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（充能条为控件属性更新，无每帧自绘全场扫描）。
- [ ] 已知 seam：SEAM-019（模块不持长机引用，`verify_player_ref_holders.py` 通过）；SEAM-011 不适用（无长机相对量缓存）。
- [ ] i18n：§2.3 全部 key 三语落 csv；HUD 状态面板硬编码 "(Evade)" → "(AB)"。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 资源模块 + 生存层接线
- [x] `afterburner_charge.gd`：常量 + 状态机 + `toggle/update/on_kill_charge/查询器`（v3 充能制：`toggle` 开关、ACTIVE 耗能 + 耗尽自动 `_deactivate`）。
- [x] survivor_mode：建实例（字段初始化）、`_physics_process` 驱动（早退后 → 升级暂停冻结）、E 键改 `toggle`、`_on_radio_kill_recorded` 处 +4s、spawner 地面击杀挂点 +4s、关闭 `_deactivate` 对称清理。

### 阶段 2 — 窗口强 buff（共享层判定点）
- [x] `Aircraft.afterburner_window_active` 字段。
- [x] `take_bullet_damage` 闪避短路 100%（全局 cap 之后）。
- [x] missile_manager 命中 roll 0.90 → `is_flare_jammed` + 滚转动画 + `AB_MISSILE_DODGE` 日志。
- [x] `aircraft_weapons` 三处静默条件扩展（机炮扫描 / 残梭 / 副槽）+ 发射硬断四处（`_fire_gun_round` / `_fire_missile_at` / `_fire_multi_lock_salvo` / `_launch_rocket`；CIWS 不受影响）。
- [x] `aircraft_physics.update_speed` + 预测镜像：速度地板 = effective_max、cap 放开、accel ×3（`AB_WINDOW_ACCEL_MULT`）。

### 阶段 3 — HUD + i18n
- [x] 充能条控件（ProgressBar 线框三色）+ 按钮三态文案；每帧 `_update_afterburner_ui` 挂 `_update_display`。
- [x] translations.csv：§2.3 改名 + 新增 key + tooltip 六键重写（三语）；HUD "(Evade)"→"(AB)"。

### 阶段 4 — 收尾
- [x] `verify_player_ref_holders.py`（`afterburner_charge` 入 NON_HOLDERS 显式裁定）+ `verify_doc_anchors.py` 通过（顺手回填 82 处漂移锚点）。
- [x] script-index / code-index / _INDEX / survivor-skills.md 同步；changelog `2026-07-20-afterburner-mode.md`。
- [x] `--bench=all` 回归门 31 项 PASS / 0 失败（零 buff 路径不变）。
- [ ] §5 验收 playtest 项（速度体感 / 躲弹观感 / 充能节奏 / Sentinel 压测）——留给用户实机跑，通过后 status → done。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 资源模块 | `scripts/survivor/afterburner_charge.gd` |
| 生存层接线（E 键 / 击杀充能 / 驱动） | `scripts/survivor/survivor_mode.gd` |
| 窗口标志 / 机炮闪避短路 | `scripts/aircraft.gd` |
| 导弹躲避 roll | `scripts/missile_manager.gd` |
| 武器静默扩展 | `scripts/aircraft/aircraft_weapons.gd` |
| 速度地板 / accel | `scripts/aircraft/aircraft_physics.gd` |
| 充能条 + 按钮 | `scripts/survivor/survivor_hud.gd` |
| 无线电"加力冲刺"信号 / 抑制 break | `scripts/event_logger.gd`（`afterburner_engaged`）/ `scripts/aircraft.gd`（`set_evasion_mode` suppress_radio）/ `scripts/survivor/survivor_mode.gd`（`_on_radio_afterburner_engaged`） |
| 无线电台词表 | `resources/chatter/radio_chatter.json`（`afterburner` trigger）→ 详见 [radio-chatter](radio-chatter.md) |
| i18n | `i18n/translations.csv`（含 `RADIO_AFTERBURNER_*`） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-20 | 1 | 初稿即定稿（用户逐条给定数值：6s 窗口 / 30s 充能 / 击杀 +4s / 100% 机炮闪避 / 可躲导弹 / 禁攻击 / 速度拉满 / 底层复用 evasion_mode）。冲突排查 §3.5 共 16 项。 |
| 2026-07-20 | 2 | 阶段 1~4 代码全落地 + i18n 三语；`--bench=all` 31 项回归门 PASS、双校验脚本绿。status → in-progress，剩 §5 playtest 转 done。 |
| 2026-07-23 | 3 | **改充能制（电池模型）**（用户点名）：删掉"满格才能激活 + 固定 6s 窗口不可提前退"，改为"有能量即启动（charge > 0）+ 激活中按 DRAIN_RATE 实时耗能 + 耗尽自动结束 + 玩家再按 E 提前关闭保留余量"。`try_activate`→`toggle`、`window_left/is_window_active/is_ready/window_ratio`→`active/is_active/is_full/remaining_seconds`、`window_duration_mult`→`duration_mult`（改为耗能减慢，续航 +50%/层）。**常量按旧节奏重标定**：`CHARGE_MAX 30→6`（满能量最多连烧 6s，对齐旧窗口，避免准无限）、`CHARGE_RATE 1.0→0.2`（仍 ~30s 充满）、`KILL_CHARGE 4→0.8`（满池仍 ~7.5 杀）；duration_mult 精确回到 6→9→12s。同步 survivor_mode/hud/test_skills_720 + i18n tooltip/AB_DURATION 三语。 |
| 2026-07-23 | 3 | **无线电台词从 break 分离**（用户点名"现在不是为了躲导弹了"）：新 radio trigger `afterburner` + `RADIO_AFTERBURNER_*` 三语；新信号 `EventLogger.afterburner_engaged`；`set_evasion_mode` 加 `suppress_radio` 参在加力路径抑制 break emit。真·躲导弹（AI enter_evade）仍走 break。`--bench=chatter` 87 PASS（51 台词 key 全覆盖）。 |
