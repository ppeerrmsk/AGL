---
id: boss-clear-progression
kind: system
status: done
schema_version: 1
spec_version: 3
owner: 用户（设计） / Codex（落地）
depends_on: [career-archive, wraith-squadron, mother-goose]
reconstruction_complete: true
---

# BOSS 通关强化分层

> 同一个 BOSS 会记住玩家此前击败它的次数；再会时不只加数值，而是换编成或解锁新机制。

## 1. 设计意图（Why）

- **体验目标**：让重复遇到同一 BOSS 时出现可直接观察的战术变化，同时保留首次遭遇的教学版本。
- **成长轴**：读取该 `boss_id` 在生涯档案中的历史击败次数；只读既有档案，不另建第二份存档。
- **Litmus 自检**：遵守设计哲学 3「信息察觉优先于数值」与 8「BOSS 真机制」——强化优先增加编成、站位和反导能力，不给本体简单堆血。
- **反模式规避**：不做全局难度缩放；每个 BOSS 独立计数；未定义的第二强化层不擅自补机制。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 通用分层

| 历史击败次数 | 当前层 | 行为 |
|---:|---|---|
| 0 | 初见层 | 使用下表的首次编成/机制 |
| 1 | 强化层 1 | 使用下表的第一次通关后编成/机制 |
| ≥2 | 强化层 1（暂存原始次数） | 第二强化层待设计；在定稿前不再追加改动 |

判定时点为本局 BOSS 实例生成前；本局胜利写档发生在战斗结束后，因此本局不会中途跳层。
正式局读取 `CareerArchive.boss.defeats[boss_id]`；bench / boss debug 未注入档案时按 0 次处理。

### 2.2 WRAITH 中队

| 历史击败次数 | 编成变化 |
|---:|---|
| 0 | 原四架 F-47，无额外单位 |
| ≥1 | 接战瞬间追加 **2 架 YF-23 远距狙击支援机**；不参加登场演出 |

YF-23 支援机规则：

| 项目 | 值 |
|---|---|
| 数量 | 2 |
| 出生 | 以 Wraith 存活四机的队形中心为基准，沿“玩家 → Wraith”轴在 Wraith 后方再退 1800 px；总体离玩家不少于 5000 px，左右各偏 700 px；地图边界内缩 800 px |
| 角色 | SNIPER；低于 2000 px（4000 m）开始脱离，拉到 3000 px（6000 m）重新站位 |
| 锁定 | 不设 `lock_immune_override`：玩家及僚机按普通飞机规则发现、积累锁定并可使用导弹攻击；“后方潜伏”是生成几何，不等于永久免锁 |
| BOSS 结算 | 不加入 Wraith `members/all_members`；不进 BOSS 血条；不阻塞胜利 |
| 击杀计价 | `no_kill_reward=true`，BOSS 阶段不额外产出 |
| 机体 | HP 75；装甲 0；最大速度 2200 km/h；巡航 1100；失速 220；加速度 72；减速度 90；持续/结构 G 10.0/13.0；滚转 4.5；最大高度 18000 m；爬升 380 m/s |
| 雷达 | 5000 px；半角 35°；锁定 1.8 s |
| 武器 | 无机炮；AIM-260：4 发、射程 20000 m、伤害 90、冷却 1.5 s（复用现有资源） |
| 防御 | 普通敌机规则：1 枚热诱弹；可被机炮击毁，不获得 BOSS 抗性 |

### 2.3 LADON 航母战斗群

旗舰 CV、Phase 2、F/A-18 弹射节奏均不变，只调整 Phase 1 护航编成：

| 历史击败次数 | CG | DDG | FFG | 护航合计 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 2 | 6 | 8 |
| ≥1 | 2 | 2 | 8 | 12 |

强化层 1 把旧默认的两架 CG 加回，并在舰队后翼增加两架 FFG。新增 FFG 本地编队偏移为
`(-1200, -900)` 与 `(-1200, 900)` px；水域摆位校验必须按本局真实编成的偏移集合计算。

### 2.4 Mother Goose

| 历史击败次数 | UAV 型号池 |
|---:|---|
| 0 | 只允许 MQ-109 机炮与 MQ-110 导弹；权重 45:25 归一化抽取 |
| ≥1 | 解锁 MQ-111 激光与 MQ-112 电磁炮；恢复完整权重 45:25:15:15、MQ-111 上限 2、MQ-112 维持 2–3 |

MQ-111 的激光继续对导弹施加 0.5 s 减速（速度上限 45%、转弯 G 上限 50%），并同时按距离/云层衰减后的
激光 DPS 累计扣除导弹 `intercept_hp`。`intercept_hp ≤ 0` 时销毁导弹；即“先压慢，持续照射到阈值后拦截击毁”。
MQ-111 专属激光：射程 2500 m、DPS 80→18、单目标；热量规则与玩家 X-02 完全一致——上限 100、
输出 +35/s、过热强制停火并以 25/s 散热，降到 30% 才恢复拦截。

## 3. 行为与公式（How）

### 3.1 数据流

1. `CareerArchive.build_boss_history()` 同时输出旧轮换布尔表与完整 `defeat_counts`。
2. `BossEncounterEvent` 选出 BOSS 后、调用 `spawn()` 前，把该 id 的次数注入 encounter。
3. encounter 只按 `prior_defeats >= 1` 打开强化层 1；原始次数仍保留，供未来第二层直接扩展。
4. 胜利后既有 `record_boss_defeat()` 加一；下一次生成才读取新值。

### 3.2 Wraith 可选支援生命周期

- YF-23 在 `engage()` 才生成，因此不会进入 `<boss_id>_arrival` 演员列表。
- 两机组成独立 Squad，从 Wraith 队形后方进场，目标来源使用 BOSS 优先级，玩家切控时必须随 encounter 的 `set_player_ref()` 重定向。
- Wraith 四机全灭仍立即胜利；YF-23 存活与否不参与判定。

### 3.3 Mother Goose 型号门

- 初见层在抽签前把 MQ-111/MQ-112 权重置 0，并禁止“MQ-112 至少 2 架”的保底分支。
- 强化层 1 完整复用现有四型号配额、角色与补充节拍。

## 4. 结构与组成（Structure）

- 持久化来源：`CareerArchive` 既有 BOSS 击败字典。
- 注入层：`BossEncounterEvent` → `BossEncounter.configure_progression()`。
- 实例消费：`F47AceSquad`、`CarrierStrikeGroup`、`MotherGooseBoss/MotherGooseUAVSwarm`。
- 新敌机资源：事件专属 `enemy_yf23.tres`；登记 EnemyType 但不进入普通随机池。
- 激光累计拦截：复用 `LaserEquipment.intercepts_missiles_directly` 与导弹 `intercept_hp`，不新增每帧扫描。

## 5. 验收标准（Acceptance / Litmus）

- [x] 新档/0 次击败：Wraith 仍为四机；CSG 无 CG 且为 2 DDG+6 FFG；Goose 不生成 MQ-111/112。
- [x] 各自击败 1 次后：Wraith 接战新增 2 YF-23；CSG 为 2 CG+2 DDG+8 FFG；Goose 恢复四型号。
- [x] Wraith YF-23 不进演出、不进 BOSS 血条、不阻塞胜利；在 Wraith 队形后方且离玩家至少 5000 px 处成对生成；被追近后回到 4–6 km 距离带；可被正常锁定。
- [x] 玩家切控后，两架 YF-23 改追当前操控机，不保留旧玩家引用。
- [x] MQ-111 光束命中导弹时同时减速与累计扣 `intercept_hp`，累计达到阈值后导弹被删除。
- [x] MQ-111 连续照射会过热停火，强制散热到 30% 后才恢复；四项热量参数与玩家 X-02 一致。
- [x] 历史击败次数 ≥2 时不崩溃，当前仍使用强化层 1，完整次数保留给未来层。
- [ ] 性能：只增加既有实体与既有装备扫描，无新增 `_process/_physics_process/_draw`；跑生存模式 Sentinel + Lv5+ 压测，FPS 掉幅 < 15。
- [x] 玩家引用持有者校验通过。
- [ ] 全量索引锚点校验通过（共享工作区其它在途改动仍有历史外的新漂移；本功能引入的 CSG 锚点已修正）。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 档案注入
- [x] history 输出完整击败次数；事件在 spawn 前注入 encounter。

### 阶段 2 — 三 BOSS 分层
- [x] Wraith 接战生成两架可选 YF-23 狙击支援。
- [x] CSG 按层构建 8/12 艘护航舰计划。
- [x] Mother Goose 按层过滤 UAV 型号池。

### 阶段 3 — 激光与验证
- [x] MQ-111 开启直接累计拦截。
- [x] 增加无头断言、同步索引并运行校验。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 档案与事件注入 | `scripts/meta/career_archive.gd` · `scripts/events/boss_encounter_event.gd` · `scripts/survivor/boss_encounter.gd` |
| Wraith / YF-23 | `scripts/survivor/f47_ace_squad.gd` · `scripts/survivor/survivor_spawner.gd` · `resources/enemy_yf23.tres` |
| 航母编成 | `scripts/survivor/carrier_strike_group.gd` |
| Goose 型号门 / 激光 | `scripts/survivor/mother_goose_boss.gd` · `scripts/survivor/mother_goose_uav_swarm.gd` · `resources/uav_mg_laser.tres` |
| 回归测试 | `scripts/tests/test_boss_progression.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-18 | 3 | 按实战反馈修正 Wraith 强化支援：YF-23 取消永久 `lock_immune_override`，改为普通可锁定目标；出生基准从“玩家机头前方”改为“Wraith 队形后方 1800 px，且离玩家至少 5000 px”，避免贴近玩家突然闪现。 |
| 2026-08-01 | 1 | 用户定稿并完成首轮分层：Wraith 双 YF-23、CSG 护航编成、Goose 高级 UAV 门控；`boss_progression` 22/22 及受影响回归通过。第二次通关后的新机制暂缓。 |
| 2026-08-16 | 2 | MQ-111 仍走共享 LaserEquipment 累计反导，并把热量上限、输出升温、强制散热和 30% 恢复门完全对齐玩家 X-02；回归扩到真实过热循环。 |
