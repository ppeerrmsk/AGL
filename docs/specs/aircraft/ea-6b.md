---
id: ea-6b
kind: aircraft
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [t0-low-t1-aircraft-expansion, radar-range-normalization]
reconstruction_complete: true
---

# EA-6B Prowler

## 1. 定位

T0 策士支援起点。极速与巡航直接对齐当前 A-6E；稍慢加速、较低 G 和滚转表达吊舱与机体负担。AGL 战斗化外置炮舱与自卫弹是游戏改装，不冒充史实。

## 2. AircraftParams

| HP | 极速 / 巡航 / 失速 | 加 / 减速 | G / 结构 G | 滚转 | 雷达 / 锥 / 锁定 |
|---:|---|---|---|---:|---|
| 130 | 1150 / 780 / 220 | 50 / 80 | 5.8 / 8.8 | 3.2 | 2400 / 40° / 3.1s |

武器：MRM 2；AGL 炮舱 8.5、900 px、8°、瞄准 0.55；热焰弹 2。

## 3. 取得与出口

生涯商店以 1000 功勋采购后，作为 LV1 追加起手机；出口为 Jaguar、F-4E、A-6E、Mirage III。

## 4. 专属槽

名称占位“电磁徘徊”；效果延期，槽不可取得或生效。

## 5. 验收

- [x] 极速 1150、巡航 780，与 A-6E 同基准；加速低于 A-6E。
- [x] T0 基础雷达最高，但不占用标准 T1 策士预算。
- [x] 专属槽只显示预留状态。

## 6. 实现计划

- [x] params/profile、注册、i18n、树节点、测试。

## 7. 索引锚点

`resources/player/player_ea6b.tres` · `resources/player/playable_ea6b.tres`

## 8. 变更记录

| 日期 | 版本 | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 速度改按现行 A-6E；技能效果延期。 |
