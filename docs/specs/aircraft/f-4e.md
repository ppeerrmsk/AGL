---
id: f-4e
kind: aircraft
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [t0-low-t1-aircraft-expansion, radar-range-normalization]
reconstruction_complete: true
---

# F-4E Phantom II

## 1. 定位

LV4 低位 T1 骑士。双发高耐久、内置炮和完整综合武器，代价是高失速与不灵活的近距转弯。

## 2. AircraftParams

| HP | 极速 / 巡航 / 失速 | 加 / 减速 | G / 结构 G | 滚转 | 雷达 / 锥 / 锁定 |
|---:|---|---|---|---:|---|
| 120 | 2100 / 920 / 275 | 52 / 82 | 7.5 / 10.5 | 3.4 | 2500 / 34° / 2.6s |

武器：MRM 2；机炮 9.4、1050 px、7°、瞄准 0.60；热焰弹 2。

## 3. 取得与出口

只能进化取得；出口为 F-15C、F-15E、F/A-18E、MiG-31、Tornado。

## 4. 专属槽

名称占位“鬼怪武库”；效果延期，槽不可取得或生效。

## 5. 验收

- [x] LV4、T1，基础火力与耐久高于 T0 但低于标准后续节点总预算。
- [x] 专属槽只显示预留状态。

## 6. 实现计划

- [x] params/profile、注册、i18n、树节点、测试。

## 7. 索引锚点

`resources/player/player_f4e.tres` · `resources/player/playable_f4e.tres`

## 8. 变更记录

| 日期 | 版本 | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 批准实现；技能效果延期。 |
