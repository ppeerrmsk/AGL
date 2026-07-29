# 2026-07-29 共振反馈前置修正（无 JAM 手段却刷出 JAM 派生技）

## 现象

生存局内玩家 build 为 焰诱共振 / 弹后潜匿 / 座舱护甲 / 武器大师 / 二段推进 —— 全局**没有任何能施加 JAM
的技能**，升级三选一却把 **共振反馈**（`jam_self_overload`：JAM 命中 ≥1 敌 → 自身 OVERLOAD 8s）刷了出来。
拿了也永远不会触发，等于一张空卡。

## 根因

`survivor_data.gd` 的 `jam_self_overload` 条目里，前置写反了因果：

```
"requires_skill": ["cloud_overload", "skill_evade_missile_overload", "skill_flare_overload"]
```

这三条是**超载来源**。但本技能自己就是超载来源，它需要的是"能把 JAM 打出去"的手段。
条目上方那行注释（"必须先有能施加 JAM 的来源"）说的是对的，代码却是 720 批改坏的
（spec skills-720-rework §2.3 当时把它记成"需要词条：超载入门技"，§8 的 2026-07-22 行也留了
"共振反馈前置组合观察"作为已知余项）。玩家只要拿到焰诱共振（相当常见的 flare 系入门技）就解锁了这张卡。

顺带查出第二个缺口：SPECTRA（`sig_rafale`，Rafale 专属——热诱弹偏转导弹后对发射者施加 5s JAM）
是唯一一个打出 JAM 却**没调** `SkillHooks.on_player_jam_landed` 的来源，所以即使它作为前置放行，
拿了共振反馈也照样不触发。

## 改动

| 文件 | 改动 |
|---|---|
| `scripts/survivor/survivor_data.gd` | `jam_self_overload.requires_skill` 改为全部 JAM 来源：`skill_flare_aoe_jam` / `skill_gun_kill_flare_drop` / `skill_missile_hit_aoe_jam` / `skill_torpedo_aoe_jam` / `head_on_jam` / `jam_aura` / `sig_rafale` |
| `scripts/aircraft/aircraft_flares.gd` | SPECTRA 施加 JAM 后补调 `SkillHooks.on_player_jam_landed(ac, 1)` |
| `scripts/survivor/skill_hooks.gd` | `on_player_jam_landed` 头部注释补全来源名单，并写明"这份名单同时是 `jam_self_overload` 的 requires_skill，新增 JAM 来源两处必须一起改" |
| `scripts/tests/test_skills_720.gd` | 新增 §I 前置链自洽段（下） |
| `docs/specs/systems/skills-720-rework.md` | §2.3 该行改为"JAM 来源技"；§8 加 v9 记录；spec_version 8→9；bench 断言数 66→110 |

`classes: ["knight"]` 保留不动 —— 卡池品类门控是队伍身份并集判定，斗士/策士系的 JAM 来源（全向干扰场 /
机炮撒焰 / 扰乱投弹 / 雷阵警讯）与骑士系（对锋干扰）以及通用的寒蝉效应都能作为前置，不会互锁成死条目。

## 验证

- `--bench=skills720`：110 断言全绿（新增 §I：全表 `requires_skill` 的 id 有效性逐条校验 +
  共振反馈正反例——"只有焰诱共振 → 不进池" / "持有寒蝉效应 → 进池"）
- `--bench=all` 回归门：47 项测试全绿，失败 0

## 余项

- 数值/手感层面未动（OVERLOAD 8s 不变），playtest 时再看 JAM build 的实际 uptime。
