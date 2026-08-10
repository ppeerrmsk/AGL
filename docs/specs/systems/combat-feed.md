---
id: combat-feed
kind: system
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [survivor-loop]
reconstruction_complete: true
---

# 战况栏 / Kill Feed —— 左上角实时击坠提示（最新 5 条淡出）

> 玩家视角：战斗中左上角实时滚出"谁用什么武器击坠了谁"的提示，像射击游戏的击杀栏。
> 友方击坠敌机=绿，友机被击坠=红；只留最新 5 条，旧的几秒后自动淡出消失。

## 1. 设计意图（Why）

RTS 化后玩家同时指挥多机、镜头常拉远俯瞰全场（见 [camera 缩放上限放宽](#7-相关)），
靠 HUD 数字（击杀总数）无法感知"我的哪架僚机正在赢/输"。战况栏把**逐次交战结果**可视化，
让玩家一眼掌握战局走势与每架僚机的表现，强化"指挥官"体感（DESIGN_PHILOSOPHY 原则 3 信息察觉）。

**反模式规避**：低频事件驱动（每次击坠一次），非每帧扫描；复用既有击杀归因数据，零新增战斗逻辑。

## 2. 数据定义（What —— 权威源）

| 参数 | 值 | 说明 |
|---|---|---|
| 位置 | 左上角 `(16, 92)` | 居中顶部计时/击杀块之下，避让 BOSS 面板 |
| 最大条数 | `KILL_FEED_MAX = 5` | 超出立即移除最旧 |
| 保持时长 | `KILL_FEED_HOLD = 5.0s` | 完全不透明 |
| 淡出时长 | `KILL_FEED_FADE = 1.5s` | 之后线性 alpha→0，归零移除 |
| 字号 | 13，黑描边 `outline_size=4` | 战场上叠图也清晰可读 |
| 颜色 | 友机击坠敌=绿(`HP_OK`) / 友机阵亡=红(`HP_LOW`) / 中立=灰(`TEXT_MUTED`) | 按双方 team 判定，玩家方 team=0 |
| 行格式 | `"{击杀者}  →{武器}→  {被击坠者}"` | 武器为空（如坠地无凶手）退化为 `"{a}  →  {b}"` |

**武器种类**（来自 `Aircraft._last_damage_kind`）：`gun/missile/rocket/aoe/ground_crash` →
i18n key `WEAPON_GUN/MISSILE/ROCKET/AOE/CRASH`（`interface.csv`），未导入时回退中文。

## 3. 行为与公式（How）

```
致死瞬间（Aircraft._record_kill_attribution，已有击杀归因）:
    EventLogger.kill_recorded.emit(击杀者呼号, 被击坠呼号, 武器kind, 击杀者team, 被击坠team)

survivor_hud._on_kill_recorded(...):    # 订阅信号，事件级
    按 team 选色 → 建 Label（描边）→ 插到 VBox 顶部（move_child 0）
    entries.push_front({label, age:0}); 超 MAX 移除最旧 queue_free

survivor_hud._update_kill_feed(delta):  # 每帧
    每条 age += delta
    age > HOLD+FADE → queue_free + 移除
    age > HOLD      → modulate.a = 1 - (age-HOLD)/FADE
```

信号解耦：击坠发生在 `aircraft.gd`，显示在 `survivor_hud.gd`，经 `EventLogger` 信号桥接，
不互相持有引用（CLAUDE.md 信号解耦约定）。敌我对称——僚机击坠敌机与敌机击坠僚机同源触发。

## 4. 结构与组成

| 组成 | 角色 | 新增/改动 |
|---|---|---|
| `EventLogger.kill_recorded` 信号 | 击坠事件桥 | **新增**（event_logger.gd） |
| `Aircraft._record_kill_attribution` emit | 致死瞬间广播 | 改（aircraft.gd，复用已有 attacker/kind） |
| `survivor_hud` 战况栏（VBox + 条目 + 淡出） | 显示 | **新增**（survivor_hud.gd） |
| `WEAPON_*` i18n key | 武器三语 | **新增**（interface.csv，需重建翻译资源） |

## 5. 验收标准

- [x] 击坠时左上角出现一条"击杀者→武器→被击坠者"。
- [x] 友机击坠敌机=绿，友机阵亡=红。
- [x] 同时最多 5 条，第 6 条进来移除最旧。
- [x] 每条 HOLD 5s 后 1.5s 淡出消失。
- [x] `--bench=stress_mixed` 18s 实战：编译干净、信号/淡出无报错。
- [ ] i18n：Godot 重导入 CSV 后武器名走三语（未导入时中文回退，不崩）。

## 6. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 击坠信号 | `scripts/event_logger.gd`（signal kill_recorded） |
| 信号 emit | `scripts/aircraft.gd`（_record_kill_attribution） |
| 战况栏 UI + 淡出 | `scripts/survivor/survivor_hud.gd`（_on_kill_recorded / _update_kill_feed / _feed_weapon_label） |
| 颜色常量 | `scripts/theme_colors.gd`（HP_OK / HP_LOW / TEXT_MUTED） |
| 武器 i18n | `i18n/interface.csv`（WEAPON_*） |

## 7. 相关

- **镜头缩放上限放宽**（同批 RTS 改动）：`camera_controller.gd` `ZOOM_MIN 0.4→0.2`（可俯瞰大半张图），
  新增 `START_ZOOM=0.35` 开局镜头与上限解耦（开局不至于太小，玩家可滚轮拉到 0.2 看全场）。

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-06-28 | 1 | 初版落地：EventLogger.kill_recorded 信号 + survivor_hud 左上角战况栏（最新 5 条、HOLD 5s+淡出 1.5s、敌我配色、武器 i18n 回退）。同批放宽镜头缩放上限。bench 18s 验证干净。 |
