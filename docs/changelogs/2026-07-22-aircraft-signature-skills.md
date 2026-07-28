# 2026-07-22 — 722 机体签名技能批（41 机每机一条专属技能）

> spec：[aircraft-signature-skills](../specs/systems/aircraft-signature-skills.md)（权威源，数值/歧义裁定/锚点全在那边）
> 来源：用户 722 表《722机体原创技能》。本文只记"这次动了什么"。

## 概要

进化树 41 机每机新增一条**签名技能**：

- **获取**：只有驾驶该机型时升级才可能刷出（`exclusive_to` 现成门控，按当前 ACE 机型判）；稀有度一律 **CLASSIFIED（机密/金）**，×1 层。
- **继承**：获得后进玩家层账本，换机/进化重放**不查门控** → 永久跟玩家、不断往下带（用户定案；底座零成本复用 720/attr-gates 机制）。
- **Meta 预留**：将来上锁进局外 Meta Progression 时只需在池过滤加一层"局外解锁表"，数据结构不动。

## 数据与文案

- `survivor_data.gd` UPGRADES 表尾追加 **40 条 `sig_*`**（F-14 围猎=既有 `f14_squad_lock_slow` 改名"围猎"+ 改档 CLASSIFIED，不重复建条）。
- `milestone_plus` 字段**数组化**（AX-00 双子星 骑士+策士 双轴 +1）：`milestone_plus_list_of()` 新增、发放点循环、cap=2 语义不变；`dump_skill_table.py` 同步兼容数组。
- i18n 三语 **80 新键 + 围猎改名**；技能全表重生成 → **144 条**。

## 系统层新底座（多技能共用）

| 底座 | 服务技能 |
|---|---|
| 锁定管线集中注入（`_update_radar_locks` 722 段） | 无败之鹰 / 制空清扫 / 对地特化 / 盲飞入侵 / 近太空冲刺（高空）/ 唯一的锁定（出锥 grace 冻结窗） |
| 致死拦截（`aircraft._try_sig_death_save`，判序：钛浴缸先、复活兜底） | 钛浴缸（A-10）/ 不被期待的计划（A-12） |
| 特殊机动完成事件（cobra/herbst phase→NONE → `SkillHooks.on_special_maneuver_done`） | 急停机动（Su-27）/ 落叶飘（Su-35） |
| 起飞事件（停靠结算关闭分支） | 甲板周转（F/A-18E，过量装填 ×2 + 永久 HP 走 meta 跨换机）/ 落选者（YF-23，20s 隐身） |
| STEALTH 上升沿（apply_status 覆写快照；常驻派生隐身刻意不触发） | 先敌开火（F-22：全装填 + 隐身多锁齐射 `effective_max_locks`） |
| 作战云中继（`cloud_relaying` 守卫：广播落地直通 super，防 OVERLOAD 乘区双乘/防递归） | 作战云（FCAS） |
| 独立发射通道（不经 `_fire_missile_at` 的窗口禁火硬断） | 超速截击（MiG-31：加力窗口自动发射、弹速 ×1.3） |
| 越肩发射（锥门+锁定门豁免、包线/窗口质量照查） | 传感器融合（F-35） |
| 导弹 spawn 打标 + `missile_evasion` 单点过滤（覆盖规避与投焰两判定） | 夜枭（X-09 静默弹 40%） |
| 被偏转重索敌（2s 直飞 → 导引头 FOV 内 TEAM_HOSTILE 最近） | 超越地平（X-21） |
| 签名 drone 不进 `_alive_drones` 离屏 despawn 体系 → 天然永久 | 忠诚僚机编队（F-47）/ 鲸群（X-90 周期生成 + 血量均摊光环） |
| `_spawn_reward_wingman` 抽取复用（无 XP 副作用） | 双子星（AX-00 克隆 3 架 + build 补挂） |

## 顺手修复的既有问题

1. **`_apply_build_to_new_member` 零调用**（720 T1 "新僚机入队补挂"缺口②实际漏了接线）：现挂 `_spawn_reward_wingman` 尾部——+1 僚机奖励与双子星克隆都会吃全队 build。
2. **`aim_assist` cap 倒退**：高速炮艇置锥角 90° 后再拿瞄准辅助会被 `min(…, 45°)` 缩回——cap 改为不低于当前值。

## 落地偏差（詳见 spec §2.3 / §8-v2）

- 地形跟随"低空无速度惩罚"：游戏无此惩罚机制，上翻为低空 +8% 增速。
- 超巡爬升的"+30% 闪避"走全局 85% dodge cap 兜底（与全部 dodge 技能一致），不单设 70%。
- 卡面"签名"专属角标缓做（归属角标机制已有，样式随 playtest 反馈定）。

## 验收

- `--bench=sig_skills` 47 断言全绿（表约定 / 门控 / milestone 数组 / apply / 致死判序 / 免疫 / x13 流速 / f22 / accessor）。
- `--bench=all` 回归门 **34 项 PASS**（skills720 等既有批未破坏）。
- `verify_player_ref_holders`（AircraftWeapons 显式裁定入 NON_HOLDERS）与 `verify_doc_anchors`（重定位 35 处行号漂移）双绿。

## 余项

- playtest（用户实机）：CLASSIFIED 出现率手感、各条数值调档、Sentinel+Lv5 压测。
- 卡面签名角标样式；夜枭对 ace 命数体系的强度观察（BOSS 不豁免为预期设计）。
