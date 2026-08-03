---
id: battlefield-visual-scale
kind: system
status: in-progress
schema_version: 1
spec_version: 1
owner: 用户 + Codex
depends_on: [map-expansion]
reconstruction_complete: true
---

# 战场载具视觉尺度（Battlefield Visual Scale）

> 统一飞机、轰炸机、直升机与舰船的屏幕尺寸规则：世界仍是 1px=2m，但小型飞机用压缩幂律放大保证可读，大型载具接近真实地图比例；高度只做温和强调，不再把 HIGH 飞机放大到破坏空间感。

## 1. 设计意图（Why）

- **体验目标**：在 60km 东京湾地图上，战斗机是可读的战术符号，轰炸机明显更大，航母又显著大于飞机，但不再像 840m 长的浮岛；缩到 0.2 仍能辨认类别。
- **当前病灶**：
  - 飞机基础图标用固定 `size=16`，大多数机型无真实尺寸身份；
  - 高度倍率从 0m 的 0.55 拉到 15km 的 1.70，HIGH 比 LOW 大约 2.4 倍，压过机型差异；
  - 航母 `hull_length=420px` 在 0.5px/m 下相当于 840m，约为 Nimitz 真实 333m 的 2.5 倍；CG/DDG/FFG/SS 也各用不同放大率。
- **取舍**：不做摄影透视（俯视 2D + 虚拟高度仍需要高度可视化），也不让 10m 战斗机严格只画 5px；采用“飞机压缩幂律 + 舰船真实世界比例 + 温和高度倍率”。
- **Litmus 自检**：变化在第一眼可见；只改视觉/命中几何一致性，不改航速、武器射程或地图坐标；静态轮廓不新增逐帧扫描。

### 1.1 现实尺寸锚点

| 类别 | 参考长度/宽度 | 来源用途 |
|---|---:|---|
| Nimitz CVN | 332.85m / 飞行甲板宽 76.8m | 航母基准 |
| Ticonderoga CG | 172.8m / 16.8m | 巡洋舰基准 |
| Arleigh Burke DDG | 155.3m / 18m | 驱逐舰基准 |
| Constellation FFG | 151.2m / 19.7m | 护卫舰基准 |
| Virginia SSN | 114.8m / 10.36m | 潜艇基准 |
| AH-64E | 14.7m / 旋翼 14.6m | 攻击直升机基准 |
| CH-47F | 工作旋翼总长 30.1m / 旋翼 18.3m | 运输直升机基准 |
| B-1B | 长 44.5m / 战斗后掠翼展 24.1m | 友军轰炸机基准 |
| Tu-160 | 长 54.1m / 后掠翼展 35.6m | 敌军轰炸机基准 |

舰船/直升机/B-1B 数据取自美国海军、Boeing 与美国空军官方资料；Tu-160 取美国陆军航空识别资料。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 普通飞机视觉公式

AircraftParams 增加：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `visual_length_m` | 18m | 未单独登记的普通固定翼基准 |
| `visual_span_m` | 12m | 未单独登记的普通固定翼基准 |
| `visual_scale_exempt` | false | Mother Goose 等机制型巨物为 true，沿用专属绘制 |

在 MID 高度，单个物理尺寸 `d_m` 映射为：

```text
visual_dimension_px(d_m) = 7.9 × pow(max(d_m, 1.0), 0.55)
```

关键样例（四舍五入）：

| 对象/尺寸 | MID 绘制尺寸 |
|---|---:|
| 12m 普通翼展 | 31px |
| 18m 普通机长 | 39px |
| AH-64 14.6m 旋翼 | 34px |
| CH-47 30.1m 工作总长 | 51px |
| B-1B 44.5m 机长 | 64px |
| Tu-160 54.1m 机长 | 71px |

该幂律保留“大就是大”的顺序，但把真实 5倍尺寸差压成约 2.5倍，避免大机遮住战场。

### 2.2 高度倍率

替换现有高度视觉锚点：

| 高度 | 现值 | 新值 |
|---:|---:|---:|
| 0m | 0.55 | 0.85 |
| 2000m（LOW） | 0.70 | 0.90 |
| 5500m（MID） | 1.05 | 1.00 |
| 10000m（HIGH） | 1.55 | 1.15 |
| 15000m | 1.70 | 1.20 |

高度仍可读，但 HIGH/LOW 尺寸比从约 2.21 收敛为 1.28。尾焰、枪口闪光、旋翼盘、选中环和锁定框必须消费同一个倍率。

### 2.3 舰船绘制几何

舰船采用世界物理比例：`px = meters × PIXELS_PER_METER`；只有宽度设 10px 可读下限。

| 舰种 | 新 `hull_length` | 新 `hull_width` | 当前长度 | 变化 |
|---|---:|---:|---:|---:|
| CV | 166.4px | 38.4px | 420px | ×0.396 |
| CG | 86.4px | 10.0px | 240px | ×0.360 |
| DDG | 77.6px | 10.0px | 180px | ×0.431 |
| FFG | 75.6px | 10.0px | 130px | ×0.582 |
| SS | 57.4px | 10.0px | 300px | ×0.191 |

挂点沿船长/船宽归一化比例重算，不保留旧绝对像素：

| 舰种 | 前后主挂点（沿船长） | 左右挂点（沿船宽） |
|---|---:|---:|
| CV | ±71px | ±14px |
| CG | VLS ±27px；CIWS ±16px | 0 |
| DDG | VLS ±26px | CIWS ±4px |
| FFG | ±19px | 0 |
| SS | 中心 | 0 |

`weak_point_radius` 是交互/瞄准辅助，不是绘制尺寸，本批不改；bullet/naval hit radius 必须与新船体几何一致，不能继续读旧尺寸缓存。

### 2.4 镜头与屏幕可读性

| 镜头 zoom | 规则 |
|---|---|
| `0.2` 最远 | 普通 31px 翼展约 6.2 屏幕 px，达到最低可读目标；不再额外放大 |
| `0.35` 开局 | 普通翼展约 10.9 屏幕 px；轰炸机约 22–25px；航母约 58px |
| `1.0+` | 使用真实 world 绘制尺寸，不做反向屏幕钳制 |

数据标签、目标框、雷达锥线宽继续走各自的 inverse-zoom 可读策略，不计入载具尺寸。

## 3. 行为与公式（How）

### 3.1 单一视觉尺寸入口

- 所有飞机轮廓先从 `visual_length_m / visual_span_m` 求 MID 尺寸，再乘 `altitude_visual_scale` 与 bank 压缩。
- 特殊轮廓只定义归一化形状，不再各自私设 `size×1.15`、`size×1.1` 等不可追踪倍率。
- 附件（旋翼、尾焰、枪口、选中环、锁定框）读取同一组 `AircraftRenderer` 视觉尺度结果。
- Mother Goose 和明确 `visual_scale_exempt=true` 的演出巨物保持专属比例，不套幂律。

### 3.2 舰船几何一致性

以下消费者必须从同一份新几何读取：

1. 船体绘制；
2. 挂点位置与 MountTarget 世界位置；
3. 子弹/火箭/电磁炮命中半径；
4. 目标括号大小；
5. 航母甲板 DockPoint 偏移与着舰区；
6. 舰载机停放/弹射视觉锚点。

武器射程圈、舰队编队间距、雷达范围与战区水域安全圆使用世界战术距离，**不随船体缩小**。

## 4. 结构与组成（Structure）

- `AircraftRenderer.visual_model_scale/altitude_base_scale`：共享纯函数，负责飞机幂律与高度倍率；无 Node、无 `_process`。
- `AircraftParams`：增加真实/参考长度与翼展字段；普通资源可用默认值，B-1B/Tu-160/AH-64/CH-47 必须显式填写。
- `AircraftRenderer`：所有轮廓、枪口与尾焰共用幂律尺度输出。
- `NavalParams`：继续存最终 px 几何，但资源值改为本 spec 表；挂点资源同步重算。
- 测试截图仅放 `tmp/`，在 zoom 0.2/0.35/1.0 各截一张同场对比，不把临时图放进 Godot 扫描目录。

## 5. 验收标准（Acceptance / Litmus）

- [ ] 同场普通战斗机、AH-64、CH-47、B-1B、Tu-160 的尺寸顺序与 §2.1 样例一致；Tu-160 不再只比战斗机大一点。
- [ ] LOW→HIGH 的同机尺寸比约 1.28，不再约 2.21；高度变化仍能肉眼察觉。
- [ ] zoom 0.2 时普通战斗机最窄主尺度 ≥6 屏幕 px；zoom 0.35 时不遮挡相邻 100px 编队槽位。
- [ ] CV/CG/DDG/FFG/SS 长度与 §2.3 一致；挂点全部落在船体内或紧贴甲板，没有悬空旧坐标。
- [ ] 舰船缩小后，子弹命中、锁定框、弱点点击、DockPoint、舰载机弹射位置与图形对齐。
- [ ] 武器射程、舰队编队间距、航速与水域摆位不因视觉尺寸调整而改变。
- [ ] 无头测试覆盖公式锚点、资源值、挂点归一化和命中半径；naval formation / water / CIWS 回归全绿。
- [ ] 性能：纯函数 O(1)，不新增 `_process`/扫描/每帧分配；Sentinel + Lv5+ 不低于 60 FPS。
- [ ] 视觉 QA：tmp 中三档 zoom 对比图人工检查通过后才把 status 标为 done。

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 单一尺度入口
- [x] 新增 AircraftRenderer 尺度纯函数与 AircraftParams 尺寸字段。
- [x] AircraftRenderer 普通/轰炸机/旋翼机/枪口/尾焰统一改读该入口。

### 阶段 2 — 舰船资源迁移
- [x] 更新五类 NavalParams 几何与所有挂点坐标。
- [x] 确认命中半径、目标框与舰体绘制均消费同一 `hull_length`；挂点与甲板坐标同步校正。

### 阶段 3 — 回归与视觉 QA
- [x] 新增 visual scale 公式/资源断言。
- [ ] Godot 4.7 三档 zoom 截图 + Sentinel/Lv5+ 压测。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 视觉尺度纯函数 | `scripts/aircraft_renderer.gd` |
| 飞机参数/绘制 | `scripts/aircraft_params.gd` · `scripts/aircraft_renderer.gd` |
| 舰船几何 | `scripts/naval/naval_params.gd` · `resources/naval/` |
| 舰船命中/交互 | `scripts/naval/naval_unit.gd` · `scripts/bullet_manager.gd` |
| 回归 | `scripts/tests/test_bomber_rotor_airburst.gd` · `scripts/tests/test_naval_formation.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-01 | 1 | 初稿：普通飞机尺寸用 `7.9×m^0.55` 压缩幂律，高度倍率收敛到 0.85–1.20；五类舰船回到 0.5px/m 世界比例并重算挂点。 |
| 2026-08-01 | 2 | 实现统一飞机幂律/高度倍率，校正 B-1B、Tu-160、AH-64、CH-47 真实尺寸参考，并将 CV/CG/DDG/FFG/SS 舰体与挂点收敛回世界比例；专项公式 bench 已通过，待编辑器关闭后补舰队 bench 与三档 zoom 视觉 QA。 |
