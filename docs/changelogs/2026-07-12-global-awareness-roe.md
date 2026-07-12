# 2026-07-12 · 全图察觉与交战规则（ROE）阶段 1~5 落地

Spec：[docs/specs/systems/global-awareness-roe.md](../specs/systems/global-awareness-roe.md)（v3，status: in-progress，差 playtest）

## 一句话

敌人从"全知磁铁"变成"守区的守区、巡逻的巡逻、只有猎杀队冲你来"；热度（纯内部量）
驱动 hunter 配额承载难度；第三方友军以三类事件登场（机场防空 / AWACS buff 区 / 护送任务）；
全部敌机机体色收进暖色域，友好单位统一蓝绿。

## 落地内容

1. **IFF 收口（阶段 1）**：`CombatUnit.is_hostile_to()/teams_hostile()/is_player_squad()`
   单一 API；A 类敌我直比 / B 类玩家特权 / C 类上帝 director / D 类配色二分 约 90 处迁移。
   team 语义：0=PLAYER 1=HOSTILE 2=ALLY。
2. **中队感知 + 姿态（阶段 2）**：`RoeDirector`（2s tick）——感知圈=长机雷达全向、
   hp 差分/被锁事件察觉、战区聚合警报、雷达站 datalink、15s 记忆；感知门挂
   `acquire_target` TS_SCORED 分支；GARRISON（区+1500m）/PATROL（6km）leash；
   线路巡逻 30%（2 点 reinf_ring 往返）；hunter 整队抽调/归还；磁吸航点退役。
3. **热度单杠杆（阶段 3）**：heat 0~100（击杀+5/地面+8/攻克+15/被命中+2，6s 后 -2/s，
   地板 min(75,5L)）→ 唯一输出 hunter 配额 round(2+10h/100)；静默基线对拍旧曲线
   （单测逐点验证）；不上 HUD。
4. **FactionPalette（阶段 4）**：GameConstants Token + 全部强调色函数三分支
   （玩家亮青 #3EE0C8 / ALLY 海绿 #3FA98E / 敌暖红）；机体 icon_color 审计修正 ×15
   （5 蓝 + 2 冷紫 + 3 冷白 + 复核追加 A-7/Q-5/AH-64/FA-18）；kill feed / 小地图 /
   雷达锥 / 地面标签 / Tab 图接入。
5. **第三方三事件（阶段 5）**：`AllyForce` 转换器（0 token / 0 XP / 不可点名）；
   机场防空 SAM+AA×3 机场常驻；AWACS 南带往返 + 8km buff（锁定×3 / 导弹 G ×1.25 快照）
   + Tab 圈 + 180s 冷却；护送 CH-47×3（40 功勋/架，`MeritLedger.award`）+ 2 波拦截 +
   横幅三语（EVENT_ESCORT_*）。

## 验证

- 单测 `--bench=roe` 33/33（热度纯函数 / 配额旧曲线对拍 / 姿态派生 / 感知门 / 守区 leash）
- 回归门 `--bench=all` **21 项全 PASS**（含既有 20 项零回归）
- 30s 生存无头冒烟（stress_40）无脚本错误

## 待办（用户）

- §5 playtest：察觉手感（绕后/守区不追出/巡逻 leash）、热度节奏（静默降压/攻坚围剿）、
  三事件观感；Sentinel + Lv5+ 压测 FPS 掉幅 < 15
- 拍板遗留：奖励航母收编 ALLY（暂缓项 §8-⑨）；舰船击杀热度挂钩；AWACS 无热诱弹简化是否接受
