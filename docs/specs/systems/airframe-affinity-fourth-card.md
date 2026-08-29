---
id: airframe-affinity-fourth-card
kind: system
status: done
schema_version: 1
spec_version: 2
owner: player-progression
depends_on: [evolution-attribute-gates, classified-card-pity, career-shop, aircraft-signature-progression]
reconstruction_complete: true
---

# 机体战术适配：稀有第四技能卡

> 在生涯商店永久解锁后，当前机体偶尔会把一张符合自身战术轴的普通技能送入第四槽，但基础三轴选择与机场专属技能路径保持不变。

## 1. 设计意图（Why）

- **体验目标**：让玩家选择并长期驾驶某类机体时，偶尔获得一次与机体身份呼应的额外构筑机会；它是稀有惊喜，不是每轮稳定扩容。
- **Litmus 自检**：奖励依赖当前机体身份并继续受既有池规则约束，能形成“继续驾驶这架飞机会遇到什么构筑机会”的可预测关系；第四卡仍需与原三卡竞争玩家的一次选择，不直接增加每轮技能收入。
- **反模式规避**：不把机体专属技能重新塞回随机池；不复制前三张的稀有度；不绕过学说、装备、前置、互斥或堆叠上限；空池时不造一张无意义的纯加点卡。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 生涯商品

| 字段 | 值 | 说明 |
|---|---:|---|
| 商品 id | `global_airframe_affinity` | MetaShop 持久购买键 |
| 名称 | 机体战术适配 | 三语本地化 |
| 分类 | 机体与后勤 | 与起手机、停靠补给、行动时长同页 |
| 价格 | 3000 功勋 | 一次性永久购买 |
| 上架条件 | 恒上架 | 新档案即可看见 |
| 正式局权限 | 必须已购买 | 未购买不掷第四槽概率 |
| 非正式局权限 | fail-open | bench / boss debug 可直接验收 |

### 2.2 触发与轴选择

| 字段 | 值 | 说明 |
|---|---:|---|
| 合资格事件 | 自然等级升级（LV 3/6/9/…） | 奖励升级、机场结算与 debug 强制授予不触发 |
| 基础卡数 | 3 | 斗士、骑士、策士各一张，行为不变 |
| 第四槽触发率 | 15% / 合资格事件 | 独立掷一次；`roll < 0.15` 命中 |
| 第四槽上限 | 1 张 | 每轮最多四张可选卡，仍只能选择其中一张 |
| 单轴机 | 100% 选择该轴 | 触发后不再随机轴 |
| 双轴机 | 两轴各 50% | 先去重，再按三轴稳定顺序抽取 |
| 三轴机 | 三轴各 1/3 | 先去重，再按三轴稳定顺序抽取 |
| 未知/无轴机 | 不生成第四卡 | 不回退到随机轴 |

## 3. 行为与公式（How）

### 3.1 自然升级流程

```text
先生成基础三轴三张卡
if 已有机体战术适配权益 and randf() < 0.15:
    identity = 当前玩家机型的战术身份轴集合
    axis = 从 identity 中按等概率选择一个合法轴
    pool = 该轴的普通随机候选池
    pool -= 本轮前三张已经出现的技能 id
    pool = 应用与前三张相同的正式资格过滤
    if 本轮前三张已有当前服务流派的终端技能:
        pool -= 同一服务流派的其它终端技能
    fourth = 用同一轴抽卡器独立抽取(pool)
    if fourth 存在:
        标记 airframe_bonus_offer = true
        标记 airframe_bonus_axis = axis
        追加为第四张
在完整 3~4 张卡上统一结算终端债务与 CLASSIFIED pity
```

### 3.2 普通肉鸽规则继承

第四张必须复用普通轴卡的候选池与加权抽取：

- 排除 `evolved` 奖励技能和全部机体专属技能；
- 遵守当前机型、硬件、学说、`classes`、`requires`、`excludes` 与 `max_stacks`；
- 稀有度权重、等级解锁、构筑关键词引导、状态流派亲和、终端债务倍率和 CLASSIFIED 软 pity 与前三张相同；
- 第四张使用一次新的随机抽取，因此稀有度不从前三张复制；
- 同轮不允许重复技能 id，并继续保证同一轮至多出现一张当前服务流派终端技能；
- 第四张若为 CLASSIFIED，视为本轮“见金”并清零软 pity；若被选中，获得该技能并给该卡所属轴 +1，和普通卡完全一致；
- 候选池为空时不显示第四槽，不生成“专注”纯加点卡，也不重掷其它轴。

### 3.3 UI

- 面板预建四个同尺寸物理槽位；普通轮次只显示前三个，命中时显示第四个。
- 第四卡继续使用自身稀有度决定介质、边框、辉光与闪边，不使用机体专属技能的品红样式。
- 第四卡顶部在轴徽记上方增加高对比轴色来源条“◆ 机体适配增援”，让玩家明确它来自商店全局升级；不覆盖技能 scope、品类限制或里程碑信息。
- 标题与所有可见卡都进入同一错开转场；四卡布局必须在 1920×1080 下完整可读。

## 4. 结构与组成（Structure）

| 组成 | 职责 |
|---|---|
| MetaShop 商品与权益查询 | 保存永久购买态；正式局门控、非正式局 fail-open |
| SurvivorData 纯函数 | 15% 边界判定；合法身份轴去重与等概率映射 |
| SurvivorMode 抽卡编排 | 在基础三张后尝试第四张，并把最终卡组交给 pity / 终端债务结算 |
| SurvivorUpgradeUI | 四个物理槽、条件显隐与“机体适配增援”来源标记 |
| i18n | 商品名、说明与第四卡来源标记三语文本 |

第四卡的两个 `airframe_bonus_*` 字段只存在于当轮候选字典副本，不写入技能定义、玩家技能账本或存档。

## 5. 验收标准（Acceptance / Litmus）

- [x] 未购买时正式局自然升级始终只有基础三张；购买后才进行 15% 掷骰。
- [x] `0.149999` 命中、`0.15` 不命中；单/双/三轴的纯函数边界与等概率分段有确定性断言。
- [x] 命中后第四张属于当前机体的某个身份轴，并且不与前三张重复。
- [x] 第四张遵守普通候选资格、独立稀有度、终端唯一性与 CLASSIFIED pity；专属技能仍不可能进入任何普通卡槽。
- [x] 选第四张与选前三张相同：只取得一张技能并给对应轴 +1。
- [x] UI 在三卡时隐藏第四槽；四卡时保留正常稀有度视觉并显示“机体适配增援”。
- [x] 性能：仅自然升级时 O(技能数) 扫描一次，不增加常驻 tick / draw / 实体；豁免 C1 压力专项，使用升级 Visual 验证真实渲染。
- [x] 已知 seam 未触碰：不新增跨帧 Object 缓存，不改变机场留机/进化生命周期。
- [x] i18n：玩家可见文本走 `tr()`，三语已补。
- [x] 文档：本 spec 已登记 `_INDEX`；相关抽卡、商店、专属技能文档无“永远固定三张”的冲突表述。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 50 机体身份轴与专属技能审计；i18n / 文档 / 玩家引用审计 | 50 个身份均合法；43 个专属技能已实现，7 个按已批准机体扩展 spec 保持不可取得占位；专属技能继续排除于普通池 |
| E1 聚焦 Shadow | `attr_gates`、`meta_shop`、`status_notes`、`presentation`、`career_archive` | 161/161、93/93、50/50、244/244、62/62 通过 |
| E2 集成 Shadow | `bench\run.cmd all 1 300 Shadow Headless` | 83 项同步测试 0 失败；LifecycleGauntlet 82/82 通过 |
| E3 Visual | `upgrade_media_visual`、`ui_iteration_visual` | 四卡截图通过；UI 迭代 9 captures / 0 failures |
| E4 完整局 | 未执行 | 非本次自动交付门 |

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与商店
- [x] 增加全局商品、上架规则、定价、购买态与 fail-open 权益查询。
- [x] 增加概率边界与机体身份轴等概率选择纯函数。

### 阶段 2 — 抽卡编排
- [x] 基础三张完成后，仅自然升级按权益和 15% 概率尝试第四张。
- [x] 复用普通池过滤与加权抽卡，补齐重复、终端与 pity 约束。

### 阶段 3 — UI 与验收
- [x] 扩展为条件四槽，增加来源标记与三语文案。
- [x] 补 focused、Visual、文档审计与全量回归。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 商店目录与权益 | `scripts/meta/meta_shop.gd` |
| 概率/身份轴纯函数 | `scripts/survivor/survivor_data.gd` |
| 自然升级编排 | `scripts/survivor/survivor_mode.gd` |
| 四槽 UI | `scripts/survivor/survivor_upgrade_ui.gd` |
| 验收 | `scripts/tests/test_attribute_gates.gd`、`scripts/tests/test_meta_shop.gd`、`scripts/tests/test_status_notes.gd` |
| Visual | `scripts/tests/upgrade_media_visual_qa_runner.gd` |
| reference 索引 | `docs/reference/script-index.md`、`docs/reference/code-index.md`、`docs/reference/skill-implementation-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 用户裁定：第四槽改为商店永久升级；15% 概率追加当前机体身份轴的普通技能卡，稀有度与全部肉鸽规则独立继承。 |
| 2026-08-26 | 2 | 完成商店、抽卡、四槽 UI、三语与机体/专属技能审计；聚焦、Visual、全量与生命周期门均通过。 |
