# 2026-07-23 — 加力模式改充能制（电池模型）

spec: [docs/specs/systems/afterburner-mode.md](../specs/systems/afterburner-mode.md) spec_version 3（用户点名：能量随时开关 / 耗完自动结束 / 有能量即可启动 / 充能制）

## 做了什么

把加力模式从"**满格才能激活 + 固定 6s 窗口不可提前退出**"改造成"**充能制（电池模型）**"：能量是一池连续资源，随开随关、按需短点或长烧。

- **激活条件**：`charge > 0` 即可（不必满格）。E 键 / HUD 按钮统一走 `toggle(leader)` 开关语义——未激活且有能量 → 启动；激活中再按 → 立即关闭（剩余能量保留）；能量为 0 → 无操作。
- **耗能**：激活中 `update(delta)` 按 `DRAIN_RATE = 1.0/s` 实时扣能（能量按秒 1:1 消耗），耗尽（≤0）→ `_deactivate()` 自动关闭。不再"激活瞬间清零"。
- **续航上限**：满能量下最多连烧 `CHARGE_MAX = 6s` 加力——**对齐旧固定窗口时长**，避免变成准无限（初版误设 30 已修正）。
- **充能按旧节奏重标定**：被动 `CHARGE_RATE = 0.2/s`（6 ÷ 0.2 = ~30s 充满，沿用旧"30s 攒一次"）+ 小队击杀 `KILL_CHARGE = 0.8s`（占满池 13%，满池仍需 ~7.5 杀，与旧 4/30 同比例）；激活中被动充能暂停、击杀仍入账（边烧边攒）。

## 无线电台词分离（加力不再喊 "break"）

加力已是玩家主动的脱离/占位动作，不再是躲导弹，沿用规避的 "break break break" 语义不符：

- **新 trigger `afterburner`**（radio_chatter.json）+ 三条台词 `RADIO_AFTERBURNER_1/2/3`（三语，如"全队加力，冲！"/"推满油门，脱离重整！"），weight 55 / cooldown 8s / chance 0.85。
- **信号分离**：`toggle` 启动时调 `set_evasion_mode(true, suppress_radio=true)` 抑制 `evasion_started`(break)，改 emit 新信号 `EventLogger.afterburner_engaged` → survivor_mode `_on_radio_afterburner_engaged` → 长机喊加力台词。
- **真·躲导弹不变**：AI `enter_evade`（僚机被咬）仍走 `evasion_started` → "break"。两条频道语义各归各。
- `set_evasion_mode` 新增可选参 `suppress_radio := false`（默认 false，所有旧调用行为不变）。

## 底层复用（未变）

启动/关闭链路、全队强 buff（机炮 100% 闪避 / 90% 滚转甩导弹 / 禁攻击 / 满速地板 + accel ×3）、`afterburner_window_active` 标志、`set_evasion_mode` 既有副作用、TORP/WMN 例外、导弹 roll、武器静默硬断——**全部原样保留**。只把"6s 倒计时窗口"换成"按能量续航的激活期"，并把无线电从 break 分离。

## 改动清单

| 文件 | 改动 |
|---|---|
| `scripts/survivor/afterburner_charge.gd` | 重写：`window_left`→`active` bool；`try_activate`→`toggle`（开关）；新增 `DRAIN_RATE`、`_effective_drain()`、`remaining_seconds()`、`_deactivate()`；删 `WINDOW_DURATION`/`_window_total`/`window_ratio`；查询器 `is_ready`→`is_full`、`is_window_active`→`is_active`；`window_duration_mult`→`duration_mult`（改为耗能减慢的除数） |
| `scripts/survivor/survivor_mode.gd` | E 键 `toggle`；账本同步字段名 `duration_mult`；接 `afterburner_engaged` → `_on_radio_afterburner_engaged` 播加力台词 |
| `scripts/event_logger.gd` | 新增 `signal afterburner_engaged(callsign, team)` |
| `scripts/aircraft.gd` | `set_evasion_mode` 加可选参 `suppress_radio`（加力路径抑制 break emit） |
| `resources/chatter/radio_chatter.json` | 新增 `afterburner` trigger（3 台词，55/8s/0.85） |
| `scripts/survivor/survivor_hud.gd` | 按钮 `toggle`；tooltip ON 判据 `is_active`；`_update_afterburner_ui` 三态改为恒显 `ratio()`（激活=剩余秒数 + 亮青放空 / 满=READY / 部分=充能%） |
| `scripts/tests/test_skills_720.gd` | 强化加力断言改"满能量续航 6→9s"；新增"激活中再按 → 关闭"断言 |
| `i18n/translations.csv` | `UPGRADE_AB_DURATION_DESC`（耗能减慢续航 +50%/层）+ 四条 `TOOLTIP_EVADE_*`（去掉"6s"/"需满充能"，改充能制口径）+ 三条 `RADIO_AFTERBURNER_*` 三语 |

## 技能语义映射

- **强化加力（ab_duration）**：`duration_mult` 作 drain 除数（续航 +50%/层）。因 `CHARGE_MAX=6`，满能量续航精确回到原来的 **6→9→12s**。i18n/skill-table/skills-720-rework 同步。
- **检讨（ab_kill_charge）+ 适应（adapt_energy）充能奖励随池缩放 ÷5**：检讨 `+3s→+0.6s/层`（survivor_mode 系数 3.0→0.6）、适应 `ADAPT_ENERGY_CHARGE 3.0→0.6`——保持"占满池 13%/次"的旧比例。i18n/skill-table/skills-720/survivor_data 注释同步；test_skills_720 断言随之更新。
- **超频加力 / 弹仓过载 / 雾隐 / 检讨 / 适应 / su34 厨房 / mig31 超速截击**：全部键于 `afterburner_window_active`，随激活期存续，行为不变（不再固定 6s，按实际烧的时长算）。

## 验证

- `--bench=chatter`：87/87 通过（`RADIO_AFTERBURNER_*` 三语落地，i18n 覆盖 51 台词 key 全绿）。
- `--bench=skills720`：64/64 通过（含两条新 AB 断言）。
- `--bench=all` 回归门：**34 项测试 / 0 失败**（`set_evasion_mode` 加参不破坏任何 evasion/状态机测试）。
- `verify_doc_anchors.py`（全量 450 锚点）+ `verify_player_ref_holders.py`：绿。
- 剩 §5 playtest（能量随开随关手感 / 短点 vs 长烧节奏 / 强化加力续航体感）留用户实机跑。
