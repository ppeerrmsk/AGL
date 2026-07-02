# 进化系统垂直切片 —— 思考记录 + 实施计划

> 分支：`feature/aircraft-evolution`（退路 = main @ e93e1d5）。
> 目的：**验证设计好不好玩**，不是做完整版。设计权威见 specs：ace-system / aircraft-evolution(+tree) / meta-progression。

## 0. 排序决策（思考记录，2026-07-02 与用户定）

**问题**：先做游戏性大改（进化/ACE）还是先搭编辑器底层（UGC P0 数据化）？用户担心编辑器动底层导致游戏性白做。

**结论**：**游戏性先行**。依据：
- 进化/ACE 的大头（ACE 逻辑/继任/结算 UI/归属栈）与编辑器**正交**，不会白做。
- 机型档案是纯 @export Resource，.tres→JSON 将来可脚本机械迁移，不算重做。
- 反向风险更大：UGC schema 里该有什么**取决于还没验证的游戏性设计**（签名武器槽/档位/affinity），现在定 schema = 对着流动设计定协议。
- 唯一真共享底层很小 → 用三条护栏顺手做对（约 1 天成本，替代整周的编辑器 P0 先行）。

**三条护栏（切片实装强制）**：
1. **进化树 = 数据文件**（JSON），代码只读表——绝不写成硬编码 match/dict。
2. **机型查找走单一 registry**（`AircraftDB.get_profile(id)`），不散落 preload。将来 UgcLoader 只需向 registry 注册。
3. **不往 match 块塞新 per-type 硬编码**（spawner flare/装填两个 match 块是反面教材）；新内容参数进 Resource 字段或数据表。

## 1. 切片范围（验证什么 / 砍什么）

**要验证的核心循环**：
战斗涨团队等级 → 清战区结算 → **ACE 手动三选**进化 + **僚机自动跟随** → 整机蜕变（可感知变强）→ 继续打 → 感受"养王牌"的张力。

**Phase 1（本批实装，2026-07-02 完成 ✅ 除手测）**：
- [x] 排序决策/护栏文档（本文件）
- [x] 进化树 JSON（`resources/evolution/evolution_tree.json`，12 节点 3 档）+ AircraftDB registry（护栏 1/2）
- [x] 切片树内容：**起手 f15/f14/a10**（F-15 承接原 F-16 起手调校；F-16 降为 T2 电战形态，spec §2.6 用户纠正 2026-07-02）→ T2 f22/**f16**/mig31/su34 → T3 x09/x13/x21/x44/x02；变体 .tres 共享 base + 倍率递增（f35.tres 留档未挂树）
- [x] `EvolutionSystem.evolve()`：与出生注入同路（params 深拷贝 + SurvivorPlayableSetup.apply）；保 HP 比例；武器载弹重置为新机满额
- [x] 战区结算钩子 → 进化面板（置旗延到首个未暂停帧，避免与升级 UI 暂停打架）；僚机跟随=直接同款（切片简化）
- [x] 团队等级门槛 = survivor_player.level（切片 T2=LV3 / T3=LV6）
- [x] i18n key（EVOLUTION_* + 8 机型名三语）+ EventLogger EVOLVE + kill_tally 记账（继任 Phase 2 用）
- [x] 冒烟测试 `test_evolution_tree.gd`（12 节点全过：档案加载/出口/≥3 选/i18n）+ bench stress_mixed 无报错
- [ ] **用户 F5 手测**（验收 §3 的主观题）——切片真正的出口

**Phase 1 已知简化/债**（手测时留意）：
- 进化丢当前局内升级（`upgrade_stacks` 效果随 params 换掉失效）= **绑机型设计使然**，但 HUD 右下技能列表仍显示旧条目（视觉不一致，Phase 2 清）
- 自然成长曲线（growth_curve）进化后未重放（切片略过）
- ACE=player_aircraft（长机），继任仅埋了 kill_tally 记账、未接管逻辑

**Phase 2（验证通过后）**：
- ACE 继任记账（击坠最高者，接现有击落接管）+ ACE HUD 标记
- 航母第二结算入口 / 僚机逐架手动 override UI / 相邻环严格校验
- 旧"三选一升级"退役方案（见 §2 风险）

**明确砍掉（切片不做）**：局外 meta / ACE 专属深度（设计未定）/ 完整 5 档树与虚构机 / 阵型编辑 / F-15 正式数值（用 f16 base 换皮占位）。

## 2. 风险与决定

| 风险 | 决定 |
|---|---|
| **运行时换档案是 SEAM**（AI/编队/HUD 持引用；params 换掉可能断） | 实例不销毁只换 params/视觉；探子先查 survivor_playable_setup 注入路径能否复用；换完跑 bench + 手测切控/编队 |
| **旧三选一升级还在跑** | 切片**并存不拆**：旧升级照常、进化叠在上面。拆除等新循环验证过（免得验证失败还得装回去） |
| 结算 UI 工作量 | 复用 survivor_upgrade_ui 的暂停/面板模式，切片版只做按钮列表不做科技树可视化 |
| 树内容单薄 | 验证机制用 8~9 节点足够；内容量产等编辑器/正式树 |

## 3. 验收（切片过关标准）

- [ ] 清一个战区 → 弹进化面板；ACE 有 ≥3 个出口可选（含"暂不"）。
- [ ] 选定 → ACE 原地整机蜕变（名字/涂装/数值变，位置速度连续）；僚机同帧跟随换成同款（不可达则升自己最强可达）。
- [ ] 换机后：切控 1-4 正常、编队跟随正常、武器是新机型的、HP 比例延续。
- [ ] 等级不足的出口灰显门槛。
- [ ] EventLogger 有 EVOLVE 记录；bench 无报错；FPS 掉幅 <15。
- [ ] **主观题（用户 F5）**：这个循环"想继续玩下去"吗？——切片的真正产出。
