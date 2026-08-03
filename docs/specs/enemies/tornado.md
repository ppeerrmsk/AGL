---
id: tornado
kind: enemy
status: in-progress
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [enemy-pool-expansion]
reconstruction_complete: false
---

# Tornado IDS 常规敌版

## 1. 设计意图

- 互斥原型：Lancer；池角色：strike。身份必须由主循环而非小数值差表达。
- 主循环：低空高速直线突防，攻击通场后长距离重整。

## 2. 数据定义

| 项目 | 权威值 |
|---|---|
| 解锁 / Token / 上限 / 编成 | 6 / 5 / ∞ / 2–3 |
| 机体关键值 | 58；2100/900/225；6G；roll 2.9；accel 44 |
| 雷达 | 3600px/25°/3.5s |
| 武器与防御 | 机炮+敌方 V-tier 导弹；flare 1/fail 0.50；普通敌机 HP 运行时封顶 75 |
| 飞行/生存/雷达基准 | F-100/A-7；不读取 resources/player/ |

## 3. 行为

- Lancer 状态机契约与池选型以 enemy-pool-expansion 为准。
- 敌方武器按真实玩家等级注入 V-tier；response_level 只控制出现资格。

## 4. 验收

- [x] 独立敌方参数资源、注册表、debug spawn 与参数审计已接入。
- [x] archetype 仅一个，且与注册表一致。
- [ ] 生存模式录像确认轮廓/主循环可辨，并完成 Lv5/Lv15 性能压测。

## 5. 实现计划

- [x] 资源与池接入。
- [x] 通用原型 AI 接入。
- [ ] 人工 playtest 后升为 done。

## 6. 索引锚点

| 关注点 | 文件 |
|---|---|
| 池数据 | scripts/survivor/enemy_pool_registry.gd |
| 敌版资源 | resources/enemy_tornado.tres |

## 7. 变更记录

| 日期 | 版本 | 改动 |
|---|---:|---|
| 2026-08-01 | 1 | 首次落地常规敌版、互斥原型与参数审计。 |
