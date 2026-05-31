---
id: squad-upgrade-ownership
kind: system
status: wip-design     # ⏳ 前提失效 + 用户仍在细化进化系统，待 aircraft-evolution 定稿后重构本 spec
# ⚠ 前提变更（2026-05-30）：用户决定废除"经验满→三选一"roguelike 升级机制，改为
#   "经验=货币积累 + 局内飞机进化/改造"。本 spec 的"三选一升级"前提已失效，
#   待"进化/改造"系统方向定稿后重构。仍成立的结论：①独特武器跟机（当前操控机）
#   ②数值跟队 vs 跟机的归属问题依然需要回答。详见 §0。
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [squad-control-switching, survivor-loop, survivor-skills]
reconstruction_complete: false
---

# 小队升级归属 —— 数值跟队共享 + 独特武器跟机唯一

## 0. ⚠ 重大前提变更待重构（2026-05-30）

用户决定**废除生存模式"经验满→升级三选一"的 roguelike 机制**，改为：
- 经验值 = 一种**货币**积累，升级只提示"已升级"，不打断节奏；
- 技能提升通过**局内飞机直接进化/改造**实现（形态待定稿）。

这推翻了本 spec 写作时的"三选一升级"前提，也动到 DESIGN_PHILOSOPHY 的"build-focused roguelike"定调与 survivor-skills 整份图鉴（属北极星级调整，需另行处理）。

**本 spec 中仍然成立、将被新系统继承的结论**：
1. **独特武器跟机**：玩家拿到电磁炮/激光等独特武器 = **当前操控的那架飞机**获得（用户确认）。AI 托管该机仍能自动用（equipment update 无 player-only 分支）。
2. **数值跟队 vs 跟机的归属问题依然存在**：无论升级是"三选一"还是"自动/改造"，都要回答"某项数值加成作用于全队还是单机"。

下面 §1~§8 为旧前提下的草稿，**进化/改造系统定稿后整体重构**，暂存以保留归属模型推理。

---


> 玩家视角：你这局 roll 到的**数值升级（HP/速度/雷达/导弹数…）整个小队共享**，所以无论你操控哪一架、AI 托管哪一架，全队都是升级后的强度，切谁都不肉。而**电磁炮、激光这类"独特武器"全队只此一门，装在具体某架飞机上**——切到那架就能亲手用它，切走后 AI 托管那架也照常用。换飞机 = 换一套武器手感，但底子一样硬。

## 1. 设计意图（Why）

操控切换（[squad-control-switching](squad-control-switching.md)）要成立，必须先回答："玩家积累的 build 跟谁走？"现状是**升级绑死飞机实例**（`apply_upgrade` 直接改当前操控机的 params，僚机是基线副本）。若不改，切到僚机 = 操控一架没堆 build 的弱鸡，切换功能形同虚设。

本 spec 定义**分层归属模型**，让切换既有意义又无惩罚：

| 升级类别 | 归属 | 理由 |
|---|---|---|
| **数值升级**（stat：HP / max_speed / max_g / radar / 导弹数 / 加速 / buff 能力解锁等） | **跟队共享**（全队每架都有） | 切谁都不肉；体现"这局小队 build" |
| **独特/进化武器**（signature：电磁炮 railgun / 激光 laser 等 equipment 槽位武器） | **跟机唯一**（全队只一门，绑具体实例） | 保稀缺感 + AI 托管能自动用 + 切换体验不同武器 |

**体验目标**：
- 切到任意友机都是"升级后的强度"——数值跟队。
- 不同飞机可以挂不同独特武器——切换 = 体验不同武器手感（这架电磁炮、那架激光）。
- AI 托管任意一架都能正常发挥（数值已在 params、独特武器自动开火）。

**Litmus 自检**（DESIGN_PHILOSOPHY）：
- **原则 1（一击毙命，HP 不堆海）**：✅ 不改升级本身设计，仅扩作用范围到全队；独特武器仍 60dmg 级一击毙命。
- **原则 3（信息察觉优先）**：✅ "切到带电磁炮那架，手感不同"是强可感知差异；数值共享让玩家明确"全队都变强了"。
- **原则 9（局外节制 / 局内 build）**：✅ 强化"这局 roll 到什么 build"的局内爽点（survivor-skills 哲学）；归属是局内机制，不碰局外。
- **原则 10（全武器自动开火）**：✅ 独特武器本就全自动（equipment update 对所有机统一驱动），AI 托管天然能用。
- **原则 11（60 FPS）**：✅ 升级 apply 是事件级（非每帧）；全队遍历几架机成本可忽略；独特武器 update 现状已对所有机跑，无新增。

**反模式规避**：
- ❌ 不让"切到僚机=变弱鸡"（破坏切换功能）——数值跟队。
- ❌ 不做"每架都一门电磁炮"的数值膨胀（4 门电磁炮破平衡 / 失稀缺）——独特武器唯一。
- ❌ 不引入 player-only 武器触发分支（独特武器走统一 equipment update）。

## 2. 数据定义（What —— 权威源）

### 2.1 升级分类（决定归属的唯一依据）

每条升级在升级表里标注 `ownership` 字段（或由其作用对象推断）：

| ownership | 含义 | 例 |
|---|---|---|
| `SQUAD`（数值跟队） | apply 到全队所有 team0 飞机 + 记入 SquadBuild 栈（供新机重放） | max_hp+ / max_speed+ / radar_range× / 导弹数+ / 加速+ / DOGFIGHT_STALL_MULT / BLOODLUST 能力解锁 |
| `SIGNATURE`（独特武器跟机） | apply 到"持有该武器的那一架"实例（全队唯一一门） | 电磁炮 railgun / 激光 laser 的获取与强化 |

> 判定来源：升级若改 equipment 数组里的"槽位独特武器"（railgun/laser 等显式标记为 signature 的 kind）→ SIGNATURE；其余 → SQUAD。普通武器参数（机炮/主导弹的数值）属 SQUAD（全队共享强化）。

### 2.2 SquadBuild（新增：全队共享升级的权威记录）

| 字段 | 类型 | 说明 |
|---|---|---|
| `stat_upgrade_stacks` | Dictionary{upgrade_id → stack_count} | 全队共享的数值升级累积栈。新飞机加入小队时按此**重放**，保证后加入的机也满 build |
| `signature_loadout` | Dictionary{aircraft_instance → Array[signature_kind]} | 哪架飞机持有哪些独特武器（全队每 kind 唯一） |

> SquadBuild 是"全队 build"的单一真源。各机 `params` 是它的落地副本（数值类）；独特武器额外在 signature_loadout 记账归属。

### 2.3 独特武器唯一性约束

| 约束 | 值/规则 |
|---|---|
| 每种独特武器全队上限 | **1 门**（roll 到已拥有的同 kind → 转为"强化"而非"再装一门"） |
| 首次获取装到哪架 | **当前操控机**（玩家正驾驶的那架 → 玩家可立即上手体验） |
| 后续强化定位 | 定位到 signature_loadout 中持有该 kind 的那架实例（不管当前操控谁） |
| 持有机被击落 | 该独特武器**随之永久丢失**（roguelike 代价；不自动转移）。§3.4 给可选转移变体，默认丢失 |

## 3. 行为与公式（How）

### 3.1 apply_upgrade 分流

```
apply_upgrade(upgrade):
    if upgrade.ownership == SQUAD:
        stat_upgrade_stacks[upgrade.id] += 1
        for ac in 全队存活 team0 飞机:
            _apply_stat_to(ac, upgrade)        # 改 ac.params / ac 实例字段
    elif upgrade.ownership == SIGNATURE:
        kind = upgrade.signature_kind
        holder = signature_loadout 中持有 kind 的机
        if holder == null:                     # 首次获取
            holder = 当前操控机
            给 holder.params.equipment 加该独特武器（深拷贝）
            signature_loadout[holder].append(kind)
        else:                                  # 已有 → 强化
            _apply_signature_upgrade_to(holder, upgrade)   # 改 holder 的 railgun.charge_duration 等
```

### 3.2 新飞机加入小队 → 重放数值栈

任何新加入 team0 小队的飞机（开局僚机 spawn / 未来增援 / 复活）在初始化后：
```
for upgrade_id, stacks in stat_upgrade_stacks:
    重复 apply stats × stacks 到该新机.params
```
→ 后加入的机也立即达到当前全队数值水平。独特武器**不重放**（唯一性，不自动复制给新机）。

### 3.3 AI 托管 / 操控切换的自动正确性

- **数值**：已写进全队每架 params → AI 托管任意一架自动是满数值；操控切到任意一架也是满数值。**零额外代码**。
- **独特武器**：绑实例 + equipment update 对所有机统一驱动（现状已是）→ 持有机被 AI 托管时，电磁炮按 combat_target 自动充能开火（见调查：无 player-only 分支）；玩家切到持有机则亲手用。**零额外代码**。
- **buff 能力解锁（如 BLOODLUST）**：解锁属 SQUAD（全队都能触发血怒）；但运行时**触发的状态实例各自独立**（这架击杀进血怒、那架没有），状态字段本就在 Aircraft 实例上，天然随机走。

### 3.4 独特武器持有机阵亡（边界）

- **默认（roguelike 代价）**：持有机被击落 → signature_loadout 移除该条 → 该独特武器本局永久丢失。强化它的升级算"沉没成本"。
- **可选变体（待玩测决定，先不实现）**：阵亡时把独特武器+其强化转移给"当前操控机"或最近僚机，避免一次失误丢整套电磁炮 build。spec 标记此为 §8 待评估项，默认走"丢失"。

### 3.5 与操控切换 / 护卫的衔接

- 切换操控（squad-control-switching）后，新操控机若**不**持有独特武器 → 玩家这架只有机炮/导弹（数值满），独特武器仍在原机由 AI 用。这是预期的"换武器手感"。
- 护卫 AI（squad-ai-escort）不关心归属——它只看 combat_target / 威胁；持电磁炮的护卫机会自动用电磁炮反杀攻击长机者。

## 4. 结构与组成（Structure）

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `SquadBuild`（stat_upgrade_stacks + signature_loadout） | 全队 build 单一真源 | **新增**（survivor 层） |
| 升级表 `ownership` / `signature_kind` 标注 | 分类依据 | 改（升级数据定义） |
| `apply_upgrade` 分流 | SQUAD 广播 / SIGNATURE 定位 | 改（survivor_player.gd apply_upgrade） |
| 新机重放数值栈 | spawn 僚机/增援后同步 build | 改（survivor 僚机生成处） |
| 独特武器唯一性 + 首装当前操控机 | signature_loadout 记账 | **新增逻辑** |
| equipment update（独特武器自动开火） | AI 托管能用 | 复用（现状已统一） |

## 5. 验收标准（Acceptance / Litmus）

- [ ] **数值跟队**：roll 一个 +HP / +速度，全队每架（含 AI 僚机）数值同步提升；切到任意一架操控都是满数值，不肉。
- [ ] **新机满 build**：开局后陆续生成/增援的僚机，自动达到当前全队数值水平（重放栈生效）。
- [ ] **独特武器唯一**：roll 到电磁炮 → 装当前操控机；再 roll 同类 → 变成强化（不出现第二门）；全队任意时刻每 kind ≤ 1 门。
- [ ] **切换换手感**：切到持电磁炮那架 → 玩家亲手用电磁炮；切走 → 该机被 AI 托管仍自动用电磁炮（充能开火可见）。
- [ ] **AI 托管满发挥**：把持电磁炮的机交 AI，它对锁定目标自动充能开火（无 player-only 阻断）。
- [ ] **持有机阵亡**：持电磁炮机被击落 → 该武器本局消失（默认代价），其余数值升级全队仍在。
- [ ] **buff 解锁跟队**：BLOODLUST 类解锁后全队都能触发；运行时血怒状态各机独立。
- [ ] 性能：apply 为事件级；全队遍历 + 新机重放无每帧开销；Sentinel + Lv5+ 压测 FPS 掉幅 < 15。
- [ ] 已知 seam：升级 apply 不再假定"只有一架玩家机"（player_ref 单机假设）；与 squad-control-switching 的 leader 切换、squad-ai-escort 无竞态（登记 known-seams）。
- [ ] i18n：独特武器/升级文本走 tr() 三语（若新增"独特武器已装备/转移"提示）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — SquadBuild 地基
- [ ] 新增 SquadBuild（stat_upgrade_stacks + signature_loadout），挂在 survivor 局内单例。
- [ ] 升级表给每条标 ownership（SQUAD / SIGNATURE）+ signature 项标 signature_kind。

### 阶段 2 — apply_upgrade 分流
- [ ] SQUAD：记栈 + 广播到全队存活 team0 机（§3.1）。
- [ ] SIGNATURE：唯一性定位（首装当前操控机 / 已有则强化 holder）（§3.1）。

### 阶段 3 — 新机重放 + 衔接
- [ ] 僚机 spawn / 增援后重放 stat_upgrade_stacks（§3.2）。
- [ ] 持有机阵亡 → signature_loadout 清理（默认丢失，§3.4）。

### 阶段 4 — 验收调优
- [ ] 跑 §5 全部验收 + 切换/托管/阵亡边界 + 性能压测。
- [ ] 玩测决定是否启用独特武器阵亡转移变体（§3.4）。
- [ ] 更新 §7 锚点 + reference 索引 + known-seams（升级多机化）。
- [ ] status → done，reconstruction_complete → true。

## 7. 索引锚点（Where —— 实现后回填）

| 关注点 | 文件 |
|---|---|
| 升级 apply 分流 | `scripts/survivor/survivor_player.gd`（apply_upgrade） |
| SquadBuild 真源 | `scripts/survivor/...`（新增） |
| 独特武器（equipment） | `scripts/equipment/railgun_equipment.gd` / `laser_equipment.gd` / `equipment_params.gd` |
| equipment 自动 update | `scripts/aircraft.gd`（_update_equipment） |
| 僚机生成/重放 | `scripts/survivor/survivor_playable_setup.gd` / survivor_mode 僚机 spawn |
| reference 索引行 | script-index.md / code-index.md 升级与装备段 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-05-30 | 1 | 初稿（draft）：分层归属——**数值升级跟队共享**（SquadBuild 栈 + 新机重放）、**独特武器跟机唯一**（首装当前操控机、AI 托管自动用、阵亡默认丢失）。回应用户顾虑：电磁炮非 player-only、全自动开火、AI 托管能用。 |
| 2026-05-30 | 1 | ⚠ 加 §0：用户废除"三选一"改"经验货币+进化/改造"，本 spec 前提失效待重构；保留两条仍成立结论（独特武器跟机 / 归属问题仍在）。 |
