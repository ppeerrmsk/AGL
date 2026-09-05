---
id: afterburner-mode
kind: system
status: in-progress
schema_version: 1
spec_version: 8
owner: user
depends_on: [wingman-escort-evasion]
reconstruction_complete: true
---

# 加力模式（规避模式资源化改造）

> 把语义模糊的"规避模式"改造成显眼的小队级**充能资源（充能制/电池模型）**"加力模式"：只要有能量就能一键启动，全队极速冲刺 + 机炮完全打不中 + 滚转躲导弹，激活中持续耗能、耗尽自动结束、玩家可随时再按 E 提前关闭（剩余能量保留）。激活期间飞机由模式接管，玩家世界点击会先立刻取消加力、转入充能，再执行原移动/攻击指令；退出不重置已经获得的速度。代价是加力期间无法攻击 + 能量需时间/击杀回充。给玩家一个明确的"脱离-重整-再入"战术按钮。

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
  - v5 重构：加力资源、激活会话、退出原因和对称清理只住在 `AfterburnerCharge`；成员从 `Squad.members` 做 O(S) 弱引用快照，不再扫描全场或跨帧强持有 Aircraft。
  - v6 联动统一：肉鸽加力技能、加力专属载荷与 HUD 只认 `Aircraft.is_afterburner_mode_active()`；`evasion_mode` 仅保留 AI/规避几何语义，`is_afterburner` 仅保留物理发动机语义，禁止再互相代判。

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
| 激活消耗 | 随时间耗能 | 激活中每秒 -`DRAIN_RATE`；不再"激活瞬间清零"。激活中击杀照样按 `KILL_CHARGE + bonus` 回充（边烧边攒）。 |
| 激活中被动充能 | 0 | ACTIVE 期间被动充能暂停，关闭后恢复。 |
| 关闭方式 | 耗尽自动 / 玩家再按 E / 世界飞行指令 | 全部共用 `deactivate(reason)`；提前关闭保留剩余能量。 |

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

### 2.3 i18n（三语，`i18n/interface.csv` / `i18n/skills.csv` / `i18n/radio.csv`）

改名（既有 key 改文案）：

| key | zh | en | ja |
|---|---|---|---|
| `TACTIC_EVADE_FMT` | `E 加力: %s` | `E Afterburner: %s` | `E アフターバーナー: %s` |
| `UPGRADE_EVASION_SPEED_BOOST_NAME` | 超频加力 | Overdrive Burner | オーバードライブAB |
| `UPGRADE_EVASION_SPEED_BOOST_DESC` | 加力模式顶速 +40% | Afterburner mode top speed +40% | ABモード最高速+40% |
| `UPGRADE_EVASION_WEAPON_CD_DESC` | 加力模式中武器冷却流逝 ×2（出加力即就绪） | Weapon cooldowns tick 2× during Afterburner | ABモード中武器CD進行2倍 |
| `UPGRADE_EVASION_STEALTH_DESC` | 加力模式中获得隐身效果 | Stealth while in Afterburner mode | ABモード中ステルス |
| `UPGRADE_EVASION_HERBST_DESC` | 当前操控机按 R 手动启动 J-Turn（无需加力）；AI 僚机受威胁时自动启动 | Press R to manually trigger a J-Turn in the controlled jet (no Afterburner required); AI wingmen auto-trigger when threatened | 操作中の機体はRでJターンを手動発動（AB不要）；AI僚機は被脅威時に自動発動 |
| `UPGRADE_EVASION_OVERSTOCK_DESC` | 加力模式中每 4s 装填 1 发导弹（突破上限至 2 倍） | Afterburner mode reloads +1 missile per 4s up to 2× cap | ABモード4秒毎ミサイル+1（上限2倍） |

新增（充能条 / 按钮三态）：

| key | zh | en | ja |
|---|---|---|---|
| `AB_STATE_READY` | 就绪 | READY | 準備完了 |
| `AB_STATE_CHARGING_FMT` | 充能 %d%% | CHG %d%% | 充填 %d%% |
| `AB_STATE_ACTIVE_FMT` | %.1fs | %.1fs | %.1fs |

（tooltip 六键 `TOOLTIP_EVADE_ON/OFF_*` 全部改写为加力语义：ON=激活中效果说明，OFF=充能/激活方法+效果预览。）

（`UPGRADE_EVASION_*_NAME` 中"雾隐机动 / 危机赫尔贝特 / 弹仓过载 / 规避狂暴"不含"规避模式"字样的名字保留；`规避狂暴` 因语义反转改为 `蓄势狂暴`，en `Primed Frenzy`，ja `チャージフレンジー`。）

### 2.4 v5 状态与输入提示

| 反馈 | 契约 |
|---|---|
| 飞机旁状态栏 | 每个实际处于加力窗口的玩家小队成员增加固定英文 `AB` 状态行，使用亮青色；退出当帧移除。世界战术状态码遵循 UI 规范，不走本地化。 |
| E 键热诱弹提示 | 当前操控机的热诱弹冷却从 `0 → >0` 且加力可启动时，玩家 HUD 的 E 键以 `0.5s` 相位反色闪烁，最多 `5s`；热诱弹提前就绪、加力被启动或资源不可用时立即停止。 |
| 可用定义 | `phase == CHARGING && charge > 0`；正在 ACTIVE 不算“可用”，避免提示玩家重复启动。 |

## 3. 行为与公式（How）

### 3.1 资源状态机（小队级单实例，生存模式专属）

充能制只有两态：CHARGING（充能中）与 ACTIVE（耗能中）。没有"必须满格"的 READY 门（满格只是能量条颜色到顶，不是激活前提）。

| 状态 | 进入条件 | 期间行为 | 退出 |
|---|---|---|---|
| CHARGING | 初始 / 加力关闭后 | charge += CHARGE_RATE × dt；击杀 +KILL_CHARGE；clamp 到 CHARGE_MAX | 玩家按 E 且 charge > 0 → ACTIVE |
| ACTIVE | 玩家触发（charge > 0） | charge -= DRAIN_RATE × dt；被动充能暂停；击杀仍按当前 `KILL_CHARGE + bonus` 入账（边烧边攒）；再按 E → 立即关闭 | charge ≤ 0（自动）、玩家再按 E（提前）或玩家世界指令 → CHARGING |

- 升级 UI 暂停（get_tree().paused）期间模块不被驱动 → 充能与耗能计时自然冻结。
- CHARGING 时按 E：charge > 0 则启动；charge = 0 则无操作（按钮/条状态即反馈，不做弹窗）。
- ACTIVE 时按 E：立即关闭（剩余能量保留），是开关而非"激活中按键无效"。

### 3.2 激活流程（触发瞬间）

```
toggle(leader):                        # E 键 / HUD 按钮统一入口，开关语义
  if leader invalid: return false
  if is_active():                      # 激活中再按 → 提前关闭
    deactivate("toggle"); return false
  if charge <= 0: return false         # 无能量，启动失败静默
  phase = ACTIVE                       # 不再清零 charge！能量随时间耗
  window_members = Squad.members 中的存活非 drone 成员（WeakRef 快照，不追新）
  for m in window_members: m.afterburner_window_active = true
  leader.set_evasion_mode(true, suppress_radio=true)  # 既有链路原样：清指令、planner EVADE(max+AB)、
                                       # 传播 escort_cover_active 给僚机、evasion_modifiers cd 缩放、
                                       # 隐身/overstock 技能计时启动；但抑制 break，改喊加力冲刺 ↓
  emit EventLogger.afterburner_engaged(leader.callsign, leader.team)  # → RADIO_AFTERBURNER_*
  return true

update(delta) 里 ACTIVE 分支:
  charge -= (DRAIN_RATE / max(duration_mult,ε)) * delta
  if charge <= 0: charge = 0; deactivate("depleted")   # 耗尽自动关闭

deactivate(reason):                    # 耗尽 / 提前关闭 / 手动世界指令 / 场景清理共用
  phase = CHARGING
  for m in window_members(valid): m.afterburner_window_active = false
  leader.set_evasion_mode(false)       # CD rate 自动读当前状态
  window_members.clear()
```

- 窗口成员为**激活瞬间快照**：中途换帅（1–9 切控）、新僚机入场都不改变本次加力的 buff 归属；成员遍历带 `is_instance_valid` 守卫。
- 模块只持 `WeakRef` 长机与成员快照；释放后的成员自动解析为空，规避 SEAM-019 换帅/阵亡悬挂引用问题。

### 3.3 窗口内交互规则（与既有系统的叠加）

| 场景 | 行为 |
|---|---|
| 玩家加力中下移动/攻击命令 | 指针按下沿先调用 `cancel_for_manual_command()`：全队窗口 flag 与长机 `evasion_mode` 对称清理、状态立刻转 `CHARGING`；随后原移动/攻击命令正常执行。命令不会在 ACTIVE 状态内生效，因此加力期间没有可叠加的手动操控。 |
| 取消时速度连续性 | 取消入口禁止写 `speed`、`target_speed_kmh`、`is_afterburner` 或物理积分状态；取消当帧已经获得的速度完整保留，下一物理帧才按普通加减速公式追随新命令，不瞬间回落到巡航速度。 |
| 世界输入覆盖 | 左键移动/点名攻击在按下沿立即取消；右键取消/急刹、战术地图航点、轮盘的 regroup/evac/guard/standoff/assault 也走同一入口。轮盘纯开关（自动接敌/自动开火/阵型等）不属于飞行操控，不误取消。 |
| 僚机 | 照旧收 `escort_cover_active`（护卫姿态：被真威胁才自保规避、替长机投护卫焰），叠加窗口强 buff。跟随长机满速飞行依赖既有编队追赶逻辑（长机满速 → 僚机 max+AB 追）。 |
| AI 自保规避（含玩家托管机被咬、无 flare 时 `enter_evade`） | 照旧置 `evasion_mode`，享受**旧弱 buff**（+20% 闪避、planner max+AB、武器静默）。**不**触发窗口、不吃强 buff、不消耗资源。 |
| 敌机 EVADE | 同上，完全不变。 |
| 沙盒模式 | E 键直连 `set_evasion_mode`，无资源系统，行为不变（沙盒已废弃）。 |
| 窗口内长机被击落 | 窗口计时照走到期清理（成员数组有 valid 守卫）；资源随局销毁。 |
| 玩家阵营自动热诱弹 | 加力窗口已经承担导弹防御时，本机自卫焰与僚机替本机释放的护卫焰均暂缓；窗口结束后若导弹仍具真实来袭资格且进入末段门，恢复正常投放。热诱弹库存/CD 的 `flare_ready` 语义不变，避免僚机因“无兜底”误判而额外脱队规避。 |

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
| `evasion_weapon_cd`（CD 时间倍率 ×0.5） | **语义反转** | 规避开启时 `cd_rate("weapon")=2`，窗口内虽禁攻击但既有冷却双倍流逝；切换模式不改写倒计时，仍实现“出加力瞬间更接近就绪”。文案见 §2.3。 |
| `evasion_overstock`（每 4s +1 弹） | 成立 | 加力持续越久装填越多（充能制下不再固定 6s，按实际烧的时长算）。文案不变（速率仍准确）。 |
| `evasion_stealth`（进入 2s 后隐身） | 成立 | 加力持续 > 2s 即进入隐身段，直到关闭。 |
| `evasion_herbst` / `cobra_skill`（panic_save） | **与加力解耦** | 当前操控机只认 R 手动触发，不要求/不读取加力窗口；AI 僚机保留来袭导弹/后方追尾威胁自动触发。加力自身的 90% 躲弹判定不变。 |
| TORP / WMN（仅 evasion 期投放） | 保留例外 | 见 §2.2 禁攻击例外。HUD 灰显文案 "(Evade)" 改 "(AB)"。 |
| `command_sprint`（紧急集合 ×1.4） | 正交 | 速度取各来源最大值语义，无叠乘异常。 |
| BLOODLUST / OVERLOAD / lock_panic（G/加速 buff） | 正交 | 走 effective_* accessor 与 OVERLOAD accel 既有注入点，与窗口 accel ×3 相乘可接受（都是短窗口）。 |
| 玩家命令铁律（commanded_target） | 兼容 | 加力静默不清除点名目标，仅在加力期间暂停开火（玩家自己按的全队防御指令，优先级成立）。 |
| 敌机 AI `evasion_mode` | 隔离 | 强 buff 只认窗口标志；敌机永不置窗口标志。 |
| 无线电呼叫 / kill feed | **分离** | 加力已不是躲导弹：`toggle` 启动时 `set_evasion_mode(true, suppress_radio=true)` 抑制 break，改 emit `afterburner_engaged` → 长机喊"全队加力冲刺"（`RADIO_AFTERBURNER_*`，radio-chatter 新 trigger）。真·躲导弹（AI `enter_evade`）仍走 `evasion_started` → break，语义各归各。 |
| `skill_evade_missile_overload`（死里逃生：躲弹→超载 8s） | 不联动 | 该钩子只挂 flare jam 成功路径；窗口 90% 躲弹是模式豁免，不算技能语义的"躲弹"，避免窗口内连躲 N 弹刷新超载。 |
| 忠诚僚机 drone / ACE 友军番队 | 不适用 | drone 不进窗口成员集（沿用 `_propagate` 的 is_drone 排除）；友军番队 leader 非玩家，天然排除。 |

v6 的统一判定补充：

- `超频加力 / 蓄势狂暴 / 弹仓过载 / 雾隐机动 / 加力供弹` 均按每架成员自己的 `is_afterburner_mode_active()` 生效；既然升级范围是通用全队，激活快照中的长机与僚机必须同拍获得、同拍清除。
- `TORP / WMN / 超速截击 / 鸭嘴兽厨房` 同样只认窗口 accessor；普通 AI 规避或物理发动机自动开 AB 都不得触发。
- 窗口 setter 负责隐身与弹仓过载计时的进入/退出清理；`AfterburnerCharge` 不直接写字段，避免新消费点绕过生命周期。

### 3.6 R 键统一机动入口（2026-08-01 用户定档）

- **当前操控机**：眼镜蛇、危机赫尔贝特（J-Turn）、胆大妄为统一由 `R` 主动释放；眼镜蛇/J-Turn 不再由加力模式或威胁检测自动启动，且按 R 时无需先开加力。
- **AI 僚机**：同一技能仍按来袭导弹/后方追尾威胁自动启动，用作自保；切控后身份立即反转——新受控机改听 R，旧受控机交还 AI 后恢复自动。
- **三技能互斥**：眼镜蛇、J-Turn、胆大妄为属于同一互斥组；拿到任意一张后，其余两张不再出现在卡池。代码仍保留“大机动优先、不可用时回退胆大妄为”的防御顺序，只处理旧档/debug 异常共存，不是正常 build 组合。
- **自动热诱弹**：当前操控机持眼镜蛇/J-Turn 时，未按 R 不得因“大机动已就绪”而压住正常自动热诱弹；胆大妄为原有“禁自动热诱弹”代价保持不变。
- **输入边界**：R 是飞行动作，不是武器扳机，因此不违反全武器自动开火原则。

### 3.7 充能事件源

| 来源 | 判定 | 挂点语义 |
|---|---|---|
| 空中击杀 | `EventLogger.kill_recorded` 信号，`killer_team == TEAM_PLAYER && victim_team == TEAM_HOSTILE` | 与 kill feed / roe 热度同源（生存模式已订阅处顺路调用）。 |
| 地面/舰船击杀 | spawner 击杀检测中"玩家方击杀地面单位"的既有热度挂点 | 与 roe `add_heat` 地面分支同点位。 |
| 被动 | 生存主循环驱动 `update(delta)` | 升级 UI 暂停时自然冻结。 |

## 4. 结构与组成（Structure）

- **状态机模块** `scripts/survivor/afterburner_charge.gd`（`AfterburnerCharge extends RefCounted`）：`Phase {CHARGING, ACTIVE}` 为唯一权威；持 charge、弱引用 leader/member 会话；`activate/toggle/deactivate/cancel_for_manual_command` 共用对称边界，`update` 只处理资源与窗口成员效果，查询统一走 `is_active/is_available/is_full/ratio/remaining_seconds`。
- **小队复用**：`Aircraft.squad_ref()` 统一返回 AI 缓存指向的 Squad 结构真源；加力快照和 `escort_cover_active` 广播都只遍历 `Squad.members`，不再各自扫描 `CombatUnit.all_units` / 子节点。
- **Aircraft 新字段** `afterburner_window_active: bool`（共享层运行时标志，仅生存层写入；沙盒恒 false）。
- **判定点（共享层，各 ≤5 行）**：`take_bullet_damage` 闪避短路；missile_manager 命中 roll；`aircraft_weapons` 三处静默（机炮扫描 / 残梭 / 副槽）扩展 `or afterburner_window_active`；`aircraft_physics.update_speed`（+ 预测镜像）速度地板与 accel ×3。
- **接线（生存层）**：survivor_mode 建实例、`_process` 驱动、E 键与 HUD 按钮走 `toggle`、击杀 handler 调 `on_kill_charge`；所有世界飞行指令在执行前走 `_cancel_afterburner_for_manual_control`。
- **R 机动入口**：`survivor_mode` 只把 R 交给当前 `player_aircraft`；Aircraft 统一入口按“大机动 → 胆大妄为”优先级尝试，自动路径依据 AI `manual_control` 身份让位。
- **HUD / 状态栏**：玩家 HUD 保持统一加力进度模块；`PlayerInstrumentPanel` 只做 O(1) 的 flare CD 上升沿观察并复用键帽反色函数；世界单位状态栏由 `AircraftRenderer.status_label_entries` 读取 `afterburner_window_active`，不新增节点或全场扫描。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 开局能量满；按 E 全队进入加力：速度明显陡增至顶速（加力焰亮）、能量条肉眼放空、耗尽自动退出后开始重充，~30 秒充满。
- [ ] **充能制核心**：能量未满时按 E 也能启动（只要 charge > 0）；激活中再按 E 立即关闭且剩余能量保留；能量为 0 时按 E 无反应。
- [ ] 加力激活时每个窗口成员的飞机旁状态栏显示亮青 `AB`，退出当帧消失。
- [ ] 加力期间点击移动/敌人：按下沿立即退出并进入充能，随后原命令生效；取消前后的 `speed` 与 `target_speed_kmh` 不被退出入口重写，无瞬时掉速。
- [ ] 右键急刹、战术地图航点和轮盘飞行命令走同一取消入口；纯战术开关不误取消。
- [ ] 热诱弹 CD 从 0 开始且加力可用时，E 键按 0.5s 相位反色提示，最多 5s；加力不可用/已启动或 flare 就绪时不闪。
- [ ] 加力期间敌机机炮对全队 0 伤害（每次闪避有滚转动画）；EventLogger 无玩家队 GUN 受伤条目。
- [ ] 加力期间无 flare 被导弹追：约 9/10 弹在命中瞬间被甩偏（AB_MISSILE_DODGE 日志 + 偏飞），偶发命中存在。
- [ ] 加力期间全队机炮/导弹/火箭静默（含被点名 commanded_target 的僚机）；关闭后点名目标自动恢复开打。TORP/WMN 照旧投放。
- [ ] 加力期间下移动/攻击命令：加力立即取消并开始充能，随后原命令生效；速度不瞬降。
- [ ] 击杀充能：非加力时击杀敌机 charge 可见 +0.8s 跳增；地面击杀同样；检讨每层额外 +0.6s。
- [ ] 强化加力（ab_duration）：满能量续航从 6s 拉长到 9s/12s（耗能减慢），HUD 剩余秒数随之变长。
- [ ] AI 自保规避（玩家托管被咬 / 敌机 EVADE）不触发加力强 buff、不消耗能量；敌机规避时玩家机炮命中率与改造前一致（+20% 闪避不变）。
- [ ] 当前操控机持眼镜蛇/J-Turn：不开加力也能按 R 释放；只开加力或遭受威胁不会自动释放。旧档/debug 若异常同时持有胆大妄为，大机动不可用时 R 才回退为手动滚转。
- [ ] 切控后：新受控机的大机动只听 R；旧受控机恢复 AI 威胁自动释放。当前受控机未按 R 时，眼镜蛇/J-Turn 就绪不得抑制正常自动热诱弹。
- [ ] 加力窗口内，玩家与僚机不对窗口已可处理的导弹释放自卫焰，也不替加力中的长机释放护卫焰；窗口结束后真实末段威胁恢复正常投放。
- [ ] 沙盒 E 键行为不变。
- [ ] 性能：跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15（充能条为控件属性更新，无每帧自绘全场扫描）。
- [ ] 已知 seam：SEAM-019（模块只持长机/成员 WeakRef，`verify_player_ref_holders.py` 通过）；SEAM-011 不适用（无长机相对量缓存）。
- [ ] i18n：§2.3 全部 key 三语落 csv；HUD 状态面板硬编码 "(Evade)" → "(AB)"。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 资源模块 + 生存层接线
- [x] `afterburner_charge.gd`：常量 + 状态机 + `toggle/update/on_kill_charge/查询器`（v3 充能制：`toggle` 开关、ACTIVE 耗能 + 耗尽统一 `deactivate`）。
- [x] survivor_mode：建实例（字段初始化）、`_physics_process` 驱动（早退后 → 升级暂停冻结）、E 键改 `toggle`、空中/地面击杀走统一回充、关闭走 `deactivate` 对称清理。

### 阶段 2 — 窗口强 buff（共享层判定点）
- [x] `Aircraft.afterburner_window_active` 字段。
- [x] `take_bullet_damage` 闪避短路 100%（全局 cap 之后）。
- [x] missile_manager 命中 roll 0.90 → `is_flare_jammed` + 滚转动画 + `AB_MISSILE_DODGE` 日志。
- [x] `aircraft_weapons` 三处静默条件扩展（机炮扫描 / 残梭 / 副槽）+ 发射硬断四处（`_fire_gun_round` / `_fire_missile_at` / `_fire_multi_lock_salvo` / `_launch_rocket`；CIWS 不受影响）。
- [x] `aircraft_physics.update_speed` + 预测镜像：速度地板 = effective_max、cap 放开、accel ×3（`AB_WINDOW_ACCEL_MULT`）。

### 阶段 3 — HUD + i18n
- [x] 充能条控件（ProgressBar 线框三色）+ 按钮三态文案；每帧 `_update_afterburner_ui` 挂 `_update_display`。
- [x] i18n 分表：§2.3 改名 + 新增 key + tooltip 六键重写（三语）；HUD "(Evade)"→"(AB)"。
- [x] v4：R 统一机动入口；玩家手动/AI 僚机自动分流；眼镜蛇/J-Turn 与加力触发彻底解耦。

### 阶段 4 — 收尾
- [x] `verify_player_ref_holders.py`（`afterburner_charge` 入 NON_HOLDERS 显式裁定）+ `verify_doc_anchors.py` 通过（顺手回填 82 处漂移锚点）。
- [x] script-index / code-index / _INDEX / survivor-skills.md 同步；changelog `2026-07-20-afterburner-mode.md`。
- [x] `--bench=all` 回归门 31 项 PASS / 0 失败（零 buff 路径不变）。
- [ ] §5 验收 playtest 项（速度体感 / 躲弹观感 / 充能节奏 / Sentinel 压测）——留给用户实机跑，通过后 status → done。

### 阶段 5 — v5 模块化重构与交互修订
- [x] `AfterburnerCharge` 重写为显式两态状态机；成员改用 Squad O(S) 弱引用快照；所有退出原因走同一对称清理。
- [x] 玩家世界指令按下沿统一取消加力；退出不写速度/目标速度/积分状态，命令在 CHARGING 状态继续执行。
- [x] 世界状态栏增加 `AB` 行；热诱弹进入 CD 且加力可用时 E 键复用键帽反色动画提示。
- [x] focused / all / Visual 回归通过；文档与锚点校验纳入交付终态门。

### 阶段 6 — v6 肉鸽技能联动统一
- [x] Aircraft 提供唯一窗口 accessor + lifecycle setter，状态机不再直接写字段。
- [x] 全队加力技能、TORP/WMN、签名技能和 HUD 全部迁移到窗口 accessor。
- [x] 保留非现役肉鸽的 `flare_cd_mult / missile_reload_mult` 为普通 AI 规避语义，避免迁移过界。
- [x] 真实两机 Squad 回归覆盖长机/僚机同拍生效、退出清理、普通规避与物理 AB 负例；`afterburner 17/17`。
- [x] 两机小队、物理 AB 假阳性与窗外载荷拒绝已纳入 focused；HUD 仪表状态按当前机 accessor 每次重算，切控不沿用旧机状态。

### 阶段 7 — v7 热诱弹资源协同
- [x] 玩家阵营自卫焰与护卫焰统一读取 `is_afterburner_mode_active()`，窗口内由加力独占防导弹职责。
- [x] 失导、错目标、同阵营、飞离与追不上的导弹统一排除，不新增扫描或每帧节点。
- [x] focused（flare 40/40、escort 29/29）与 `all`（88 项 + lifecycle 82/82）回归通过。
- [ ] 实机观感验收。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 状态机资源模块 | `scripts/survivor/afterburner_charge.gd` |
| 生存层接线（E 键 / 世界指令取消 / 击杀充能 / 驱动） | `scripts/survivor/survivor_mode.gd` |
| R 统一机动入口 / 玩家自动触发让位 | `scripts/survivor/survivor_mode.gd` / `scripts/aircraft.gd` / `scripts/aircraft/aircraft_flares.gd` |
| 窗口标志 / 机炮闪避短路 | `scripts/aircraft.gd` |
| 导弹躲避 roll | `scripts/missile_manager.gd` |
| 武器静默扩展 | `scripts/aircraft/aircraft_weapons.gd` |
| 速度地板 / accel | `scripts/aircraft/aircraft_physics.gd` |
| 充能条 + E 键 flare CD 提示 | `scripts/survivor/player_instrument_panel.gd` / `scripts/survivor/survivor_hud.gd` |
| 世界状态栏加力提示 | `scripts/aircraft_renderer.gd` |
| focused 回归 | `scripts/tests/test_afterburner_mode.gd` / `scripts/tests/test_player_instrument_hud.gd` |
| 无线电"加力冲刺"信号 / 抑制 break | `scripts/event_logger.gd`（`afterburner_engaged`）/ `scripts/aircraft.gd`（`set_evasion_mode` suppress_radio）/ `scripts/survivor/survivor_mode.gd`（`_on_radio_afterburner_engaged`） |
| 无线电台词表 | `resources/chatter/radio_chatter.json`（`afterburner` trigger）→ 详见 [radio-chatter](radio-chatter.md) |
| i18n | `i18n/interface.csv`、`i18n/skills.csv`、`i18n/radio.csv`（`RADIO_AFTERBURNER_*`） |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-20 | 1 | 初稿即定稿（用户逐条给定数值：6s 窗口 / 30s 充能 / 击杀 +4s / 100% 机炮闪避 / 可躲导弹 / 禁攻击 / 速度拉满 / 底层复用 evasion_mode）。冲突排查 §3.5 共 16 项。 |
| 2026-07-20 | 2 | 阶段 1~4 代码全落地 + i18n 三语；`--bench=all` 31 项回归门 PASS、双校验脚本绿。status → in-progress，剩 §5 playtest 转 done。 |
| 2026-07-23 | 3 | **改充能制（电池模型）**（用户点名）：删掉"满格才能激活 + 固定 6s 窗口不可提前退"，改为"有能量即启动（charge > 0）+ 激活中按 DRAIN_RATE 实时耗能 + 耗尽自动结束 + 玩家再按 E 提前关闭保留余量"。`try_activate`→`toggle`、`window_left/is_window_active/is_ready/window_ratio`→`active/is_active/is_full/remaining_seconds`、`window_duration_mult`→`duration_mult`（改为耗能减慢，续航 +50%/层）。**常量按旧节奏重标定**：`CHARGE_MAX 30→6`（满能量最多连烧 6s，对齐旧窗口，避免准无限）、`CHARGE_RATE 1.0→0.2`（仍 ~30s 充满）、`KILL_CHARGE 4→0.8`（满池仍 ~7.5 杀）；duration_mult 精确回到 6→9→12s。同步 survivor_mode/hud/test_skills_720 + i18n tooltip/AB_DURATION 三语。 |
| 2026-07-23 | 3 | **无线电台词从 break 分离**（用户点名"现在不是为了躲导弹了"）：新 radio trigger `afterburner` + `RADIO_AFTERBURNER_*` 三语；新信号 `EventLogger.afterburner_engaged`；`set_evasion_mode` 加 `suppress_radio` 参在加力路径抑制 break emit。真·躲导弹（AI enter_evade）仍走 break。`--bench=chatter` 87 PASS（51 台词 key 全覆盖）。 |
| 2026-08-01 | 4 | 用户将眼镜蛇/J-Turn/胆大妄为类机动统一到 R：当前操控机只手动释放且不依赖加力；AI 僚机保留威胁自动释放。三技能组成互斥组，任取其一后另两张不再出现；代码优先级只作旧档/debug 异常共存兜底。自动热诱弹不被手动大机动就绪压制。 |
| 2026-08-29 | 5 | 用户要求完整重构与三项交互修订：状态机改为 CHARGING/ACTIVE 唯一权威，Squad 弱引用快照替代全场扫描；ACTIVE 内不接受飞行指令，世界点击先立即取消并进入充能再执行原命令，退出不改写当前速度/目标速度/积分状态；飞机旁状态栏显示 `AFTERBURNER`；flare CD 上升沿且加力可用时 E 键反色闪烁提示。 |
| 2026-08-29 | 6 | 用户要求统一肉鸽技能联动：新增 Aircraft 唯一窗口 accessor/lifecycle setter；所有加力技能、特殊载荷、签名技能与 HUD 禁止再用 `evasion_mode` 或物理 `is_afterburner` 代判，并以真实两机小队覆盖全队效果。 |
| 2026-08-30 | 7 | 玩家与僚机热诱弹接入统一来袭资格；加力窗口内暂缓自卫与护卫自动投放，把有限热诱弹留给窗口结束后的真实威胁。 |
| 2026-08-30 | 8 | 加力激活期间，飞机旁世界状态栏沿用既有 buff 行样式，并将固定战术状态码收短为亮青色 `AB`；右侧 HUD 加力模块标题不变。 |
