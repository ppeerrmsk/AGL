---
id: aircraft-top-view-silhouettes
kind: system
status: done
schema_version: 1
spec_version: 11
owner: AGL
depends_on: [systems/battlefield-visual-scale]
reconstruction_complete: true
---

# 飞机顶视轮廓资产

> 现实机逐架使用可靠顶视资料的真实外轮廓；原创/虚构机默认保留旧绘制，用户明确提供并批准的定型参考可作为白名单例外。同型号只保留一张白色蒙版，运行时换色。

## 1. 设计意图（Why）

- 玩家不读名称也能凭翼型、机身比例、尾翼和发动机布局区分现实机型。
- 保留 AGL 的抽象纯色风格，不引入照片质感、涂装或内部线稿。
- 真实性来自来源图本身，不由生成式模型或参数化模板“近似重画”。
- 找不到许可、视角和闭合度都合格的来源时，宁可继续旧绘制，也不制造错误轮廓。

## 2. 数据定义（What）

### 2.1 PNG 契约

| 字段 | 值 |
|---|---|
| 画布 | 128 × 128 RGBA PNG |
| 朝向 | 机头朝上 |
| 安全边距 | 7 px |
| 可见 RGB | 255, 255, 255 |
| 背景 | alpha = 0 |
| 内容 | 仅机体顶视外轮廓；来源明确标注的外挂或辅助线可剔除 |
| 运行时颜色 | `icon_color`；若 `wing_color.a > 0.01` 则使用 `wing_color` |

`icon_color/wing_color` 是机体涂装唯一权威源，与阵营、当前操控权及战术 UI 配色解耦。
出生、进化、僚机复制、切控和阵营切换均不得为了标识阵营而改写这两个字段；阵营必须由尾迹、状态栏、雷达与指令线各自的语义色表达。

允许的加工只有：裁切、剔除明确标注的武器/辅助线、旋转、等比缩放、居中和抗锯齿。禁止补画或改造飞机几何。

### 2.2 来源与审查状态

`resources/aircraft_silhouettes/reference_manifest.json` 是逐机来源、许可、署名、处理边界和 alpha 哈希的权威清单。

- `reviewed`：来源和最终轮廓已逐架核对，可加入运行时 PNG 目录。
- `fallback_source_not_clean`：现实机，但没有找到足够干净且可复用的顶视来源，继续旧绘制。
- `fallback_unverified_concept`：原创、未定型或仅有概念外形，不制作正式轮廓。

当前正式接入 **44** 张 reviewed PNG。A-12、F-47、F/A-XX、FCAS、GCAP、J-36、MiG-41 不以猜测外形制作正式 PNG。

原创/虚构显示名中 **24** 个继续保留旧 polygon/special renderer，包括 X 系列、AX-00、AF-03、Cre、DEADAIR、Snowblind、Sentinel、MQ-112、Aegis UAV、DRONE、Probe、Mother Goose 与 Hyper-A G0–G3。MQ-109 / MQ-110 / MQ-111 按用户提供并批准的定型顶视参考，共用 `mq109_family` 白色蒙版；三者只以武器、颜色和行为区分，并用 `DRAW_SCALE=0.53` 保持旧无人机约 55% 战斗机视觉尺寸。

### 2.3 同型号复用

- F-4 / F-4E → `f4`
- F-14 / F-14 Tomcat → `f14`
- F-15 / F-15C / F-15E → `f15`
- F-16 两个显示名 → `f16`
- F/A-18E / EA-18G → `fa18e`
- Gripen C / E → `gripen`
- Su-27 / Su-35 → `su27`
- MiG-31 两个显示名 → `mig31`
- F-104 / F-104C → `f104`
- F-4 / F-4E Phantom II → `f4`
- MiG-23 / MiG-23 Flogger → `mig23`

MiG-21F-13、J 35F Draken、EA-6B Prowler 与 Jaguar GR.1A 各用独立 reviewed key，不以 J-7、A-6E 或其他近似机型代替。

### 2.4 滚转体积投影

飞机图标继续使用二维顶视蒙版，不引入 3D 节点、逐机型侧视资产或额外逐帧资源生成。渲染器把现有两次纹理提交解释为“暗色机体壳层 + 当前可见表面”：

- 顶面/机腹横向倍率：`face = abs(cos(roll))`
- 壳层横向倍率：`shell = face + thickness × abs(sin(roll))`
- 可见表面横向偏移：`offset = thickness × 0.42 × sin(roll)`
- `roll` 同时包含常规坡度、规避滚转相位与主动位移滚转视觉相位。

默认 `thickness = 0.22`；低矮飞翼/升力体为 `0.14`，轰炸机为 `0.17`，直升机为 `0.30`，小型无人机为 `0.18`。这些值只控制图标投影，不进入物理、碰撞、雷达或目标判定。

`abs(cos(roll)) < 0.18` 时顶面/机腹透明度平滑衰减，让 90° 正侧面只保留壳层，避免表面从一侧跳到另一侧。`cos(roll) < 0` 时使用同一蒙版的较暗机腹色，不把顶视图以负横向倍率翻转冒充机腹。未经审查的 legacy/UGC 轮廓复用同一壳层倍率，但不新增伪造的逐机型侧面细节。

## 3. 行为与结构（How）

1. `AircraftParams.display_name` 经目录映射到规范 key。
   生存模式玩家机若已拼接档案代号，则优先用 `SurvivorPlayableSetup` 保存的纯机型 `airframe_label` 映射；呼号与运行时全名不参与轮廓识别。
2. 目录首次命中时从原始 PNG 解码并缓存 `ImageTexture`。
3. 渲染器用同一 alpha 蒙版先画深色偏移边，再画运行时纯色填充。
4. 滚转时，深色偏移边扩展为壳层，纯色填充保持顶面/机腹投影；正侧面仍有厚度而不会归零。
5. 未审查、原创、虚构或未知 UGC 名称返回未命中，继续调用原有绘制路径，并至少应用不归零的壳层倍率。
6. 原始 PNG 由导出预设显式包含，不依赖开发机的 `.ctex` 缓存。

本功能不新增节点、不做场景树扫描、不增加逐帧资源解码；缓存粒度为每个规范机型首次一次。PNG 图标每次重绘最多保持原有两次纹理提交，正侧面隐藏表面层时降为一次；滚转体积不得新增第三次逐机绘制提交。

## 4. 验收标准

- [x] 44 张正式 PNG 均为 128 × 128 RGBA、白色 alpha 蒙版、透明四角、机头朝上。
- [x] 每个正式 key 都有来源、许可/署名（适用时）、处理边界和 alpha 哈希。
- [x] 运行时目录只包含 `reviewed` key；fallback key 不会加载占位 PNG。
- [x] 同型号玩家/敌人/子型号共享一张 PNG，仅通过颜色区分。
- [x] 非默认玩家机涂装（基准：紫色 EA-18G）经运行时档案应用与阵营刷新后保值，且不改变玩家小队统一蓝的 combat target 线或状态栏语义色。
- [x] 玩家机运行时名称拼接档案代号后仍命中同一机型 PNG；F-14 `Tomcat Warhound` 不回退旧绘制。
- [x] 24 个未获批准定型参考的原创/虚构显示名和未知 UGC 保留旧绘制；MQ-109/110/111 共用用户参考轮廓。
- [x] 静态审计覆盖当前全部 AircraftParams 显示名；七架 T0 / 低位 T1 新机零 unmapped。
- [x] Godot 4.7 Shadow 视觉 QA 通过，逐架拼图没有方向、裁切、加载或颜色错误。
- [x] 0° / 30° / 60° / 80° / 90° / 120° / 180° 滚转样张覆盖现实 PNG、轰炸机、无人机与 legacy 轮廓；90° 壳层宽度大于零。
- [x] PNG 图标滚转前后都不超过原有两次纹理提交；不新增 Aircraft 子节点、process、场景树扫描或纹理解码。
- [x] `stress_40` 改前/改后同场压力测试记录 `aircraft_draw`，60 FPS 红线保持。
- [x] 文档与锚点校验通过。

2026-08-17 Godot 4.7.1 Shadow 验证：角度矩阵以 5 类机体 × 7 角度、每格旧/新并排生成 `aircraft_bank_volume_visual.png`；3150 次强制重绘微基准中，单图标 CPU 构建由 8.861 µs 增至 10.196 µs（+1.335 µs），两组调用数相同。32 架 Headless `stress_40` 的 `aircraft_draw` 由 133 µs/帧变为 138 µs/帧（+0.005 ms/帧），采样帧率同为 146 FPS；改后 Shadow Visual 同场为 523 FPS。

## 5. 实现锚点

- `scripts/aircraft_silhouette_catalog.gd`
- `scripts/aircraft_renderer.gd`
- `scripts/tests/test_aircraft_bank_volume.gd`
- `scripts/tests/aircraft_bank_volume_visual_qa_runner.gd`
- `scripts/tools/trace_orthographic_outline.py`
- `scripts/tools/normalize_aircraft_reference.py`
- `scripts/tools/audit_aircraft_silhouettes.py`
- `resources/aircraft_silhouettes/reference_manifest.json`

## 6. 变更记录

- **2026-08-08 / v1**：建立现实机顶视 PNG、同型号复用和运行时换色路径。
- **2026-08-08 / v2**：按用户要求，原创/虚构机统一恢复旧绘制。
- **2026-08-09 / v3**：撤销参数化模板和生成式近似图；38 架正式资源改为从逐架核实的顶视/正投影来源直接提取。无法可靠提取的机型明确回退，不再猜测补画。
- **2026-08-09 / v4**：补齐现实机型 F-CK-1；直接提取 FAS DOD 101 归档三视图的闭合顶视外轮廓，并纳入运行时视觉 QA。
- **2026-08-09 / v5**：轮廓目录接入玩家机的纯机型 `airframe_label`，修复 F-14 拼接 `Warhound` 后玩家机回退旧多边形、僚机却正常的问题；视觉 QA 改为实际应用 playable profile。
- **2026-08-09 / v6**：修正 F-104 误截取顶视图后半段的问题；从同一授权三视图重新提取完整机鼻、主翼、机身与尾翼，并统一机头朝上。
- **2026-08-09 / v7**：用户提供并批准 MQ-109 系定型参考；从原图严格提取无尾三角翼、双垂尾和尖长机身外轮廓，MQ-109 / MQ-110 / MQ-111 共用一张运行时换色 PNG，并以 0.53 目录缩放保持旧无人机尺寸；MQ-112 保持旧绘制。
- **2026-08-17 / v8**：滚转由纯 `cos` 纸片压缩改为“壳层 + 顶面/机腹”二维体积投影；不提高原有纹理提交上限，并新增角度矩阵 Visual QA、纯函数回归和 `stress_40` 改前/改后负担记录。
- **2026-08-28 / v9**：为 T0 / 低位 T1 扩谱补齐七架现实机运行时模型：F-104C、F-4E、MiG-23 复用已审同型号 key；MiG-21F-13、J 35F、EA-6B、Jaguar 从公共领域三视图新增独立蒙版。并把逐机参考、manifest、静态审计与 Godot Visual 写入主角飞机新增 / 更新流程硬门。
- **2026-09-05 / v10**：确立机体涂装与战术 UI 的硬边界：`icon_color/wing_color` 在出生、进化、切控与阵营切换中保值，不再污染 combat target 线或状态栏。
- **2026-09-05 / v11**：按用户纠正确认普通玩家 combat target 线统一使用玩家蓝，不再用当前操控权区分白/蓝；机体涂装和突击黄保持独立。

## 7. 代表性来源

- [F-14 公版三视图](https://commons.wikimedia.org/wiki/File:Grumman_F-14_Tomcat.png)
- [Eurofighter Typhoon 公版正投影线稿](https://commons.wikimedia.org/wiki/File:Eurofighter_Typhoon_line_drawing.svg)
- [YF-23 / YF-22 顶视轮廓对比（CC BY-SA 4.0）](https://commons.wikimedia.org/wiki/File:YF-22_et_YF-23.svg)
- [Rafale 顶视剪影](https://commons.wikimedia.org/wiki/File:Dassault_Rafale_silhouette-top.svg)
- [F-CK-1 三视图归档](https://man.fas.org/dod-101/sys/ac/row/idf.htm)

完整来源以 manifest 为准。
