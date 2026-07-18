# 2026-07-19 局内成长底层系统批 —— 三轴属性 / 卡片回归 / 武器库 / 进化双门

分支 `feature/inrun-progression`，7 个阶段小步提交，每步 import 零错误 + 全量回归门绿（22→23 项）。
spec：[evolution-attribute-gates](../specs/systems/evolution-attribute-gates.md) v5 /
[inrun-weapon-inventory](../specs/systems/inrun-weapon-inventory.md) v1 /
[player-aircraft-power-curve](../specs/systems/player-aircraft-power-curve.md) v9。

## 落地内容（按提交序）

| 阶段 | commit | 内容 |
|---|---|---|
| 设计批 | 0992531 | 5档41机矩阵 + 三轴门槛 + 里程碑 + 武器库 四 spec 定稿入库 |
| 1 数据层 | 0397d72 | 三轴点数（SurvivorPlayer.axis_points）+ 收入 `floor(LV/3)` + 里程碑基准表数据化 + 起手机覆写槽 |
| 2 应用器 | 8643063 | 13 种 stat 里程碑应用器（apply_upgrade 同语义；speed 不动巡航防转弯地板）+ 增量/幂等/无机补挂 + evolve 后换型重放 |
| 3 卡片回归 | ff9c4a0 | 每 3 级暂停三选一：三卡=三轴各一张（affinity→轴映射 + 7 条覆写 + 专注兜底卡）；选卡=技能+1点；结算站强化栏让位 |
| 4 成长退役 | eebf463 | 自然成长全链摘除（等级纯门槛；L1=L26 同机型同数值）；boss debug 跳级不再补 HP/弹 |
| 5 武器库 | 3d9af81 | 特殊武器跟玩家：进化前快照（资源引用=强化载体）→ 换型补挂（互斥/不重复守卫）；升级卡重放（weapon 类跳过防双叠 + 两个实例乘法字段序言重置） |
| 6 进化双门 | c6d5134 | 树 JSON gates 字段（13 机临时缩放值）+ gates_passed/missing + 树视图三处双门与缺口徽记"斗士 1/2" + settlement 兜底 + debug 点数补发（主题 build 轴分布 5 点） |
| 7 Tab 面板 | cf4ea2a | 战术图左栏三轴常驻面板（点数/●○进度/下一档预览/路线倾向）+ 13 个 stat 短名 i18n |

## 验证

- `--bench=attr_gates` 75 断言（收入公式/表结构/覆写合并/计数/里程碑应用与重放/卡片映射/武器库/门槛判定/JSON 完备性/可行性 cost≤income）
- `--bench=all` 回归门 23 项全绿贯穿每一步；进化树冒烟 13 节点 PASS
- i18n 新增 24 key 三语（ATTR_*/CARD_AXIS_FOCUS_*/13 stat 短名）

## 差项（登记）

- playtest：卡片节奏手感 / 里程碑数值 / 门槛松紧（gates §6 阶段 7）
- 武器库 UI 润色：结算武器清单分段、Tab 武器库图标行、debug 武器勾选
- 卡角里程碑预告、排他性 bench 断言（41 机重排批一并）
- 41 机矩阵 + 树 §4 出口重连 + debug 全谱选机（power-curve §6 阶段 1~6，下一大批）

## 顺带

- 权限白名单 `.claude/settings.json`（Godot 无头跑/MCP 调试/PS 只读）
- 发现并补上先前会话遗留的 f35 树节点门槛
