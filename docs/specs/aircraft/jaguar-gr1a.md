---
id: jaguar-gr1a
kind: aircraft
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [t0-low-t1-aircraft-expansion, radar-range-normalization]
reconstruction_complete: true
---

# Jaguar GR.1A

## 1. 定位

LV4 低位 T1 策士攻击机。低空包线、低失速和机炮可靠，雷达与极速不是主要预算。

## 2. AircraftParams

| HP | 极速 / 巡航 / 失速 | 加 / 减速 | G / 结构 G | 滚转 | 雷达 / 锥 / 锁定 |
|---:|---|---|---|---:|---|
| 115 | 1500 / 820 / 190 | 48 / 90 | 7.5 / 10.5 | 4.1 | 2250 / 28° / 3.0s |

武器：MRM 2；机炮 10.0、1100 px、8°、瞄准 0.60；热焰弹 2。

## 3. 取得与出口

只能进化取得；出口为 A-10、Harrier、Viggen、Tornado、Su-34。

## 4. 专属槽

名称占位“贴地猎手”；效果延期，槽不可取得或生效。

## 5. 验收

- [x] LV4、T1；低失速与机炮强项在详情卡可见。
- [x] 专属槽只显示预留状态。

## 6. 实现计划

- [x] params/profile、注册、i18n、树节点、测试。

## 7. 索引锚点

`resources/player/player_jaguar.tres` · `resources/player/playable_jaguar.tres`

## 8. 变更记录

| 日期 | 版本 | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 批准实现；技能效果延期。 |
