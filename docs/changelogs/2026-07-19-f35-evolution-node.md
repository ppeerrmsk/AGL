# 2026-07-19 — F-35 挂进进化树（切片 T2 电战第二节点）

## 背景

`playable_f35.tres` 自切片实装起「留档未挂树」（AircraftDB 已注册但不在
`evolution_tree.json`，玩家局内不可达）。用户 2026-07-19 点名做出来。

## 设计（切片投影自 spec player-aircraft-power-curve §2 的 F-35 = T3 电战·传感器融合）

与同层 F-16 做**同环不同味**：

| | F-16 SmartFalcon（火力电战） | F-35 Lightning（传感器电战） |
|---|---|---|
| 雷达 | 2500 | **4600**（×0.92） |
| 锁定 | 1.375s | **1.25s**（×0.5） |
| 导弹 | **×3** | ×3 |
| 机炮 | 10 dmg / 800 / 8°宽锥 | 8 dmg / 1000 / 5°（原味，无覆盖） |
| 速度/G/滚转 | 2310 / 10G / 4.8 | 2310 / 9.5G / 4.6 |

- 热诱弹：挂 `playable_f16_flare` 覆盖（2 发 · cd1.5 · reload12 · 保底 100%）——
  **堵住「进化档案不写 flare 字段 → 吃 default_flare 30 发」的默认值漏洞**
  （F-22 / X-09 / X-13 同款漏洞仍在，属机型平衡表红旗 #1，待用户平衡表定稿一并处理）
- combat / aim 0.6 / 三防御地板 / 装填 flags 与 F-15/F-16 玩家线对齐

## 树结构（evolution_tree.json）

- 新节点：`{ id: f35, tier: 2, category: ew, exits: [x13, x09, x02] }`
- 入口：`f15.exits += f35`（spec F-15E→F-35 投影）、`a10.exits += f35`（spec A-10C→F-35 投影）
- 电战本线成型：F-16 / F-35（平行双入口）→ X-13

## 验证

- `test_evolution_tree.gd` headless：PASS，13 节点全过（profile 加载 / 出口引用 / ≥3 选 / i18n）
- i18n：`AIRCRAFT_F35_DISPLAY` 三语已在 translations.csv（切片时已加）

## 涉及文件

- `resources/evolution/playable_f35.tres`（补全档案）
- `resources/evolution/evolution_tree.json`（挂节点 + 双入口）
- `docs/planning/evolution-vertical-slice.md`（勾掉留档备注）
