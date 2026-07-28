# 2026-07-23 — 剥离机体自带的特殊武器（全部改战区获取）

> spec：[inrun-weapon-inventory §2.2](../specs/systems/inrun-weapon-inventory.md)（权威修订源）
> + [player-aircraft-power-curve §1.7](../specs/systems/player-aircraft-power-curve.md)
> 起因：用户进化到 Su-34（鸭嘴兽）时被**自动塞了火箭弹**，指出"所有飞机都不要自带特殊武器，要从战区获取"。

## 诊断

排查 41 份 `player_*.tres`，**自带特殊武器的共 8 架**：

| 武器 | 机型 |
|---|---|
| 火箭弹（`rocket`） | A-6E / A-10 / F-15E / Su-34 / Tornado / Viggen / X-44（攻击线 7 架） |
| 电磁炮 + 激光（`equipment`） | X-02 |

其余特殊武器（忠诚僚机 / 漂浮雷 / QMAAM）本就没烤进任何机体，已符合要求。
这批自带武器是"机型固有入手/首驾入库"设计（inrun-weapon-inventory §2.1.4 旧版）的产物 ——
该 spec 当初**专门否掉**了"全谱只留机炮导弹"的剥离方案，本次用户令**反转**了这个决定。

## 改动

- **剥离** 7 攻击线机的 `rocket` 引用 + X-02 的 `equipment`（railgun+laser）——删赋值行、删对应 `ext_resource` 声明、修正 `load_steps`。
- **底线武器不动**：机炮 / 导弹 / 热诱弹仍随机体（power-curve §1.7）。剥离后 A-10/Su-34 等仍有机炮+导弹，不至于变废。
- **获取来源收敛为两条，均非自带**：
  1. **战区奖励**（zone-reward-arsenal）：rocket / railgun / laser 早已在奖励池（`zone_data` 按星级 roll，权重 20/20/15 等），领取即入库、换机继承。
  2. **签名技能**：sig_x02（突击翼龙）给电磁炮、sig_f47/sig_x90 给忠诚僚机 —— 玩家**选卡换来**，不算自带。
     sig_x02 的分支已处理"无烤入电磁炮"的情况（`get_equipment_of_kind` 为 null → 自动 claim），剥离后照常生效。

## 用户拍板

范围经确认为**全剥、含起手机 A-6E**（另一选项是只剥"进化进去"的机、保留菜单主动选的起手机身份，用户选了全剥）。
攻击线起手 A-6E 现在开局只有机炮+导弹+热诱弹，火箭需战区 roll ——攻击线开局身份变淡是已知代价，符合 build-focused 立意。

## 验收

- bench `player_params` 新增断言："**41 机无一自带特殊武器**（火箭/电磁炮/激光/僚机/雷/QMAAM）" + "底线武器仍在"。
- 41 份 `.tres` 全部正确加载（`load_steps` 校正无误）。
- `--bench=all` 回归门 **37 项 PASS**。

## 文档

- inrun-weapon-inventory：§1.4 / §2.1 / §2.2 / §4 开放点 / §5 验收 全部改写，spec_version 1→2，作废"首驾入库"。
- power-curve §1.7：特殊武器改"一律不自带"。
- a-10.md：加现状偏离横幅（原始概念是无导弹+火箭身份；roster 版有导弹、火箭改战区）。
- resources-catalog：机型武器表同步。

## 追加修复（2026-07-24）：进化把火箭摘掉

用户实测（log `combat_log_20260724_222103`）：Su-34 用火箭弹一路打到 503s，进化 → J-20 后火箭没了。

**根因**：`record_special_weapons()` 有一道 `inrun_reward` meta 门——**只**把"战区领来的火箭"收进武器库，
"机体自带的火箭"跳过。这道门是旧设计（A-10 自带火箭=底线武器随机体、不入库）的遗留。
本批把机体自带火箭全剥了之后，这道门就只剩害处：玩家在 Su-34（旧存档/未重载的自带火箭，或过渡期）上的火箭
进化时不被记录 → 换到 J-20 直接丢失。电磁炮走 equipment 通道没有这道门，所以正常继承了（日志里 railgun 补挂成功）。

**修复**：移除 `record_special_weapons` 的 `inrun_reward` 门——**所有火箭一律入库、随人走**（与"火箭=外部装备"
的定位一致）。`_claim_weapon_reward` 仍打 `inrun_reward` 标记，但仅作溯源，不再影响继承。

**回归守卫**：`--bench=attr_gates` §G 武器库测试加"火箭入库（无 meta 门）"+"换机补挂火箭弹量=24"两断言。

> 提示：若你在旧运行实例里仍看到 Su-34 自带火箭，是因为 `.tres` 剥离要**重启一次生存模式**才生效
> （`.tres` 直接 load，无需 reimport，但已实例化的资源要新局才重建）。重启后 Su-34 无自带火箭，
> 火箭从战区领，领到后进化继承正常。

## 余项

- playtest：攻击线开局手感（尤其 A-6E 起手无火箭）；战区火箭 roll 频率是否够攻击线成型。
- 挂载上限（inrun §4 开放点 2）：仍不设上限，若"武器全家桶"过强再谈。
