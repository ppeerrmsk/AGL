---
id: weather-clouds-and-sandstorm
kind: system
status: done
schema_version: 1
spec_version: 6
owner: user
depends_on: [systems/map-editor, systems/map-expansion]
reconstruction_complete: true
---

# 新地图云层与沙尘暴

> 图 2/3 拥有与东京湾同等存在感的大片云系；沙漠铁路在局中出现一场只影响低空的黄色沙尘暴。

## 1. 设计意图（Why）

- **体验目标**：提高新地图的天气密度与地图辨识度；海岛云层均匀覆盖各片海域，同时保留可绕飞的大片连续区域；沙漠中场形成一条从地图边缘推进的动态战术带。
- **Litmus 自检**：天气的视觉颜色、移动方向和战斗后果均可直接察觉；导弹失灵和锁定延长沿用既有云层语义，不另造玩家难以理解的新规则。
- **反模式规避**：不每帧生成贴图、不扫描全场单位、不把云切成大量碎片、不让沙尘暴错误影响中高空。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 普通云

| 地图 | seed | coverage 阈值 | frequency | secondary_mix | 风向 | 风速 |
|---|---:|---:|---:|---:|---:|---:|
| 沙漠铁路 | 271828 | 0.26 | 0.00024 | 0.25 | 70° | 12 m/s |
| 海洋群岛 | 314159 | 0.20 | 0.00024 | 0.70 | 125° | 22 m/s |

`coverage` 是噪声阈值而非面积百分比，越低云越多。`frequency=0.00024` 形成约 8 km 特征尺度的大块云系。`secondary_mix` 取第二个同尺度噪声场，与主场按 `max(primary, secondary × mix)` 合成；沙漠使用 0.26/0.25 减少普通云但不打碎尺度，海岛使用 0.20/0.70 填补局部空洞并保留主场的大块形状。

### 2.2 沙尘暴

| 字段 | 值 | 说明 |
|---|---:|---|
| enabled | true | 仅沙漠铁路启用 |
| seed | 161803 | 密度纹理确定性种子 |
| start_ratio | 0.45 | 战区阶段进行到 45% 时开始 |
| speed_kmh | 180 | 50 m/s；由用户在现实尺度版本上要求速度翻倍 |
| sweep_duration | 1400 s | 70 km 总行程 ÷ 180 km/h，约 23 分 20 秒，由运行时计算 |
| band_width_px | 5000 | 10 km 宽的连续风暴带，减少同时受影响的战区面积 |
| direction | west_to_east | 从西侧卷向东侧 |
| tint | (0.95, 0.70, 0.18, 1.0) | 黄褐色气象信息层；中心累计 alpha 0.060 |
| combat altitude | `<3500 m` | 只在 LOW 生效；MID/HIGH 无沙尘遮蔽 |

## 3. 行为与公式（How）

### 3.1 时间与移动

```text
start_time = warzone_phase_duration × 0.45
travel = world_width + band_width = 70km
sweep_duration = travel / 180km/h = 1400s
active = start_time <= game_time < start_time + sweep_duration
progress = (game_time - start_time) / sweep_duration
band_center = west_outside + travel × progress
```

开始帧风暴前缘刚进入西边界。标准 600 秒战区阶段中于 270 秒触发，到阶段结束共推进 16.5 km；不会横穿全图，也不会让整张地图同时处于沙尘遮蔽。完整 70 km 扫图在连续运行时需要 1400 秒。F6“跳到半局”仍推进正式时间到 300 秒，但额外使用仅限 Debug 的 0.5 progress override，把沙带定位到地图中心供视觉与 LOW 游戏性验收；正式局绝不使用该 override。

### 3.2 密度与表现

沙尘密度为宽带边缘羽化与三 octave 低频噪声的乘积，内部最低密度 0.58。视觉禁止复用普通云贴图或模拟写实尘雾体积，改用现实气象观测图与项目军事 UI 接近的抽象信息层：

- 0.060 中心累计 alpha 的黄褐色宽带底色；前后缘由 6 层同形曲边多边形在 720 px 内渐变羽化；
- 210 px 行距、120 px 采样步长的成组平行弯曲流线，每四条一条 5 px 主线，其余为 3 px 次线；
- 620 px 稳定世界网格上的十字观测点、小菱形与短风羽，允许确定性重复拼贴；
- 前后缘叠加两级低频曲率（最大约 244 px）；推进侧以 3.6 px、0.52 alpha 的断续曲线和每 340 px 一组的三角锋面符号标记移动方向；
- 纹样只在当前相机与沙带的交集内构造；短符号合并为 `draw_multiline`，不按整张地图生成节点或纹理。

### 3.3 统一战斗遮蔽

```text
obscurant_density(position, altitude) = max(
  normal_cloud_density(position)  if altitude >= 7500m else 0,
  sandstorm_density(position)     if altitude < 3500m else 0
)
```

密度大于 0 时沿用普通云效果：

- 雷达对该目标的锁定累积速率 ×0.5，因此锁定时间变为 2 倍；“雾隐机动”仍覆盖为 ×0.1。
- 导弹穿越遮蔽时沿既有速率永久损失制导能力。
- 导弹近炸命中按 `35% × density` 概率失误并继续飞行。
- 飞机进入沙尘暴时使用既有“云中”战斗状态与技能边界事件；普通云下方仍保持原有视觉阴影状态。

## 4. 结构与组成（Structure）

- 地图 `.aglmap` 的 `cloud` 字段保存普通云参数，可选 `secondary_mix` 与 `sandstorm` 字典。
- `MapDocument` 负责读取、钳制并保存配置。
- `WeatherSystem` 是普通云、沙尘暴、渲染与按高度战斗遮蔽的唯一权威。
- 生存模式只向天气系统同步 `game_time` 与阶段总时长。
- 飞机状态、雷达锁定、导弹飞行和导弹命中均消费统一遮蔽查询。
- F6 战区 Debug 面板提供“跳到半局（天气验收）”。

## 5. 验收标准（Acceptance / Litmus）

- [x] 两张新地图使用 0.00024 低频大片云，海岛第二噪声混合为 0.70。
- [x] 沙漠普通云使用 0.26 coverage / 0.25 secondary mix；24×24 固定采样由旧配置 236 降至 173/576，仍保留大片云团。
- [x] 海岛 24×24 固定采样中总云格不少于 120/576，最少象限不少于最多象限的 30%。
- [x] 沙漠沙尘暴于标准局 270 秒触发，以 180 km/h 推进；一分钟移动 3 km，战区结束前移动 16.5 km。
- [x] 沙尘暴视觉为黄色气象观测图式宽带，以流线、观测点、短风羽和锋面三角从西向东扫过地图；不复用云贴图。
- [x] LOW 受导弹失误、制导衰减和锁定延长；MID/HIGH 不受沙尘暴影响。
- [x] F6 可将 `game_time` 直接推进到 50%，不触发 BOSS 解锁，并以 Debug override 将慢速沙带定位到地图中心。
- [x] 性能：气象图式版本在 Shadow + Visual 沙漠风暴中段 15 秒实测平均/1% low/最低均为 120 FPS、低于 60 FPS 为 0 帧；45 架飞机压力场景正常完成，未观察到 >15 FPS 的天气新增掉幅。
- [x] 人工视觉：已检查沙漠与海岛中段截图；海岛保留大片连续云区与开阔区，沙尘暴为连续气象线图覆盖，地图与单位仍可辨认。
- [x] i18n：新增内容仅为 Debug 文本，无正式玩家可见新文案。
- [x] 文档：本 spec 已登记 `_INDEX`，reference 指针已同步。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 数据与天气权威
- [x] 调整图 2/3 云参数并扩展 MapDocument。
- [x] 在 WeatherSystem 实现第二噪声与沙尘暴状态/渲染/高度采样。

### 阶段 2 — 战斗消费与 Debug
- [x] 将飞机、锁定、导弹飞行与导弹命中接到统一遮蔽入口。
- [x] 增加 F6 半局跳时和沙漠预览中场探针。

### 阶段 3 — 验证
- [x] 增加 `weather` focused bench。
- [x] 完成运行时性能与人工视觉验收。

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 天气与沙尘暴权威 | `scripts/weather_system.gd` |
| 地图配置读取 | `scripts/ugc/map_document.gd` |
| 地图数据 | `resources/maps/desert_railway_preview.aglmap` / `resources/maps/ocean_islands_preview.aglmap` |
| 飞机云状态 | `scripts/aircraft.gd` |
| 雷达锁定与时间同步 | `scripts/survivor/survivor_mode.gd` |
| 导弹消费 | `scripts/missile.gd` / `scripts/missile_manager.gd` |
| Debug 入口 | `scripts/survivor/survivor_debug_zone.gd` |
| 聚焦回归 | `scripts/tests/test_weather_system.gd` |
| reference 索引 | `docs/reference/script-index.md` / `docs/reference/code-index.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-09 | 1 | 两张新地图云量/大片分布、海岛均匀化、沙漠低空沙尘暴、统一战斗遮蔽、F6 半局跳时。 |
| 2026-08-09 | 2 | 沙尘暴移除写实云贴图，改为可拼贴的流线、观测点、风羽与锋面三角气象图式矢量纹样。 |
| 2026-08-09 | 3 | 小幅减少沙漠普通云：coverage 0.20→0.26，secondary mix 0.35→0.25；云团尺度与沙尘暴不变。 |
| 2026-08-10 | 4 | 沙带前后缘改为低频曲边 + 720 px 六层 Alpha 羽化；锋面线改为较细断续线；登记一分钟扫图对应 4560 km/h 的现实比例缺口。 |
| 2026-08-10 | 5 | 采用 90 km/h 现实推进速度；沙带由 16 km 缩至 10 km；完整扫图改为运行时计算的 2800 秒，F6 使用 Debug-only 中心定位保证验收可达。 |
| 2026-08-10 | 6 | 沙带速度翻倍至 180 km/h，完整扫图 1400 秒；focused bench 增加真实 Aircraft 云状态与 MissileManager 高度查询对象级回归。 |
