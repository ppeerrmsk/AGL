# 2026-07-29 舰船不许开上陆地 + 母舰 VLS 改报自己的名字

承接 [2026-07-28 修"整支航母舰队都在旋转"](2026-07-28-naval-formation-spin-fix.md)。

**玩家报告**：BOSS 阶段"有船跟着 Mother Goose 的无人机一起移动，甚至移动到了陆地上"。

顺着这条线查出**两件独立的事**，都改了：

---

## 一、战区海上舰队会开上陆地（实测确认）

CSG（BOSS 舰队）2026-07-28 已经有摆位地形校验，但**战区海上任务从来没查过水**：
旗舰沿 `center.x ± radius×0.7~0.85` 走东西直线、端点掉头，僚舰刚体跟随、偏移最大 2600 px。

无头实测（`--bench=naval_zone_water`，战区 E = 浦贺水道，radius 2500）：

| 档位 | 舰队扫过半径 | 采样点落地率 | 最远落地点 |
|---|---|---|---|
| 1★ | 3331 px | **9.7%** | (4106, 6717) |
| 2★ | 3897 px | **15.7%** | (4497, 6151) |
| 3★ | 4725 px | **16.0%** | (5329, 6010) |

而该战区能容下的**最大全水圆只有 2750 px 半径** —— 舰队根本塞不进去，挪位置也解决不了。

### 改动

- **编队缩到装得进水域**：僚舰偏移整体缩到原来的 0.62~0.75，占地半径
  1★ 2086 / 2★ 2228 / 3★ 2512 px（均 ≤ 2750）。
- **旗舰改恒定盘旋**（半径 900，与 CSG 同机制）：不再有 U-turn，整队不会原地旋转。
- **摆位走水域校验**：`NavalPlacement.pick_placement` 由近及远挑圆心，找不到全水解就把
  盘旋半径降级 900 → 450 → **0（原地驻泊）**。宁可舰队不动，也不许开上岸。

结果：三档全部 **0 落地**（40 px 步长复核）。

## 二、CSG 摆位校验重做（并共用给战区）

新增 [`scripts/naval/naval_placement.gd`](../../scripts/naval/naval_placement.gd)（`NavalPlacement`，全静态）。

核心洞察：**刚体整队绕圆心转 → 每艘船到圆心的距离恒定 → 它一辈子走的就是一个同心圆**。
所以落地判定不用"猜转位"，沿这几个同心圆按 150 px 步长细采就是精确解。
（旧的 6 转位采样漏过"只在某个中间朝向蹭岸"的摆位——加密复核一眼就抓到了。）

顺带查出一件老账：**北 BOSS 锚点（湾北桥下）的可用全水圆只有 1750 px**，
装不下"编队 1421 + 盘旋 750"。现在自动降级为**原地驻泊 + 西移 1800 px**，零落地。
南锚点（浦贺水道）可用 2750 px，舰队占地 2171 px → 原位正常盘旋。

北湾放不下一支"会动的"航母战斗群，这是水域形状的硬约束，不是参数没调好。

## 三、Mother Goose 的 VLS 弹改报自己的名字

母舰的 VLS 齐射一直**直接借用巡洋舰的 `cg_vls_missile.tres`**，而导弹 HUD 标签画的是
`display_name` —— 于是 BOSS 战里一串标着 **"CG-VLS"**（CG = 巡洋舰舷号前缀）的红框
跟着无人机蜂群飞过陆地。玩家读成"有船跟着无人机移动、还开到岸上去了"完全合理。

新增 [`resources/goose_vls_missile.tres`](../../resources/goose_vls_missile.tres)（数值 = 原件克隆，
只改 `display_name = "GOOSE-VLS"`），`mother_goose_controller.VLS_MISSILE_PATH` 指向它。

> ⚠ 这一条是**推测性修复**：它与玩家描述完全吻合，但没有当场日志佐证。
> 若下次仍看到"船"跟着无人机跑，请 F9 导一份日志——现在 `ZONE/NavalPlacement`
> 与 `BOSS/placement` 都会把圆心、盘旋半径、落地数写进日志，好对账。

## 测试

- 新增 `--bench=naval_zone_water`（11 断言）：战区 E 三档 + CSG 南北锚点，
  复核步长 40 px（比实现密 4 倍），并打印每个战区的"可用水域最大全水半径"预算。
- `--bench=all` **45 项全绿**。

## 文档同步

- [specs/systems/boss-hunter-doctrine.md](../specs/systems/boss-hunter-doctrine.md) §2.5.1(a) 重写
  （同心圆采样 + 盘旋半径降级 + 南北锚点实测），(c) 补降级说明。
- [reference/code-index.md](../reference/code-index.md)：NavalPlacement 5 行 + 战区舰队 2 行 + CSG 摆位 3 行改写。
- [reference/script-index.md](../reference/script-index.md)：新增 `naval/naval_placement.gd` + `tests/test_naval_zone_water.gd`。

## 待办

- [ ] playtest：战区 E 海上任务（三档各一次）看船是否还蹭岸；BOSS 北锚点看驻泊态观感。
- [ ] 北锚点长期解：要么把 BOSS 北锚点挪到更宽的水域（会丢"从桥下驶出"的画面），
      要么给窄水域单独准备一支缩编舰队。当前是"驻泊 + 西移"的保守解。
