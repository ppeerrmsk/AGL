# 2026-07-23 — 对地攻击回令用"打击"语义（不再喊空战"咬住"）

spec: [docs/specs/systems/radio-chatter.md](../specs/systems/radio-chatter.md) §3.4

## 背景

用户截图：点名攻击 AAA（地面 AA 炮）时长机喊"咬住 AAA 了，开始交战"（`RADIO_ACK_PURSUE_2_FMT`）。"咬住/追击/包围"是空战咬尾词，对地面单位不通。

## 做了什么

RTS 攻击回令按目标类型分流：

- **新 trigger `ack_strike`**（radio_chatter.json，与 ack_* 共享冷却桶 8s/0.35）+ 两条台词 `RADIO_ACK_STRIKE_1/2_FMT`（三语）：
  - 收到，锁定 %s，发起打击。/ Roger. Locked on %s — commencing strike.
  - 进入攻击航路，打击 %s。/ Rolling in on %s.
- **空/地分流** `SquadCommandController._strike_or_pursue(target)`：`target is Aircraft` → 空战词（`ack_pursue`/`ack_surround`）；否则（地面单位/舰船等）→ `ack_strike`。
- 四个回令点全部改走分流：`command_attack`（单点）、`command_attack_all`（分火 SPREAD / 紧密 TIGHT / 包围 FOCUS）。包围分支对地面目标也一律退回 `ack_strike`（不喊"分散包抄/切断退路"）。

## 改动清单

| 文件 | 改动 |
|---|---|
| `scripts/rts/squad_command_controller.gd` | 新增 `_strike_or_pursue()`；4 处 ack 点改走分流（含 surround 分支的对地覆盖） |
| `resources/chatter/radio_chatter.json` | 新增 `ack_strike` trigger（2 台词） |
| `i18n/translations.csv` | `RADIO_ACK_STRIKE_1/2_FMT` 三语 |
| `scripts/tests/test_radio_chatter.gd` | `_FMT` %s 覆盖测试加 `ack_strike` |
| docs | radio-chatter §3.4 空/地分流表 + 触发/冷却表；code-index RTS 段 anchor 回填 |

## 验证

- `--bench=chatter`：87/0（53 台词 key 全译，`ack_strike` %s 占位符校验绿）。
- `--bench=all` 回归门：34/0。
- `verify_doc_anchors.py` 全量 451 锚点绿。
