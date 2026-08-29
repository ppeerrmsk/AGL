---
id: mig-23
kind: aircraft
status: done
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [t0-low-t1-aircraft-expansion, radar-range-normalization]
reconstruction_complete: true
---

# MiG-23 Flogger

## 1. 定位

LV4 低位 T1 斗士。以极速、加速和可变后掠翼的纵向感取胜，不做超档雷达或持续盘旋王。

## 2. AircraftParams

| HP | 极速 / 巡航 / 失速 | 加 / 减速 | G / 结构 G | 滚转 | 雷达 / 锥 / 锁定 |
|---:|---|---|---|---:|---|
| 100 | 2200 / 1000 / 280 | 62 / 78 | 8.0 / 11.0 | 3.6 | 2350 / 30° / 2.7s |

武器：MRM 2；机炮 9.2、1000 px、7°、瞄准 0.60；热焰弹 2。

## 3. 取得与出口

只能进化取得；出口为 MiG-31、Su-27、F-15C、F-16、Mirage 2000。

## 4. 专属槽

名称占位“鞭挞者”；效果延期，槽不可取得或生效。

## 5. 验收

- [x] LV4、T1，能够直接进入 T2。
- [x] 专属槽只显示预留状态。

## 6. 实现计划

- [x] params/profile、注册、i18n、树节点、测试。

## 7. 索引锚点

`resources/player/player_mig23.tres` · `resources/player/playable_mig23.tres`

## 8. 变更记录

| 日期 | 版本 | 改动 |
|---|---:|---|
| 2026-08-26 | 1 | 批准实现；技能效果延期。 |
