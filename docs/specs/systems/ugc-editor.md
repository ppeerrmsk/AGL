---
id: ugc-editor
kind: system
status: draft        # ⏳ 可行性 + 分阶段计划（2026-07-02 调查完毕）；未实装
schema_version: 1
spec_version: 1
owner: noelu
depends_on: [map-system, map-expansion, aircraft-evolution-tree]
reconstruction_complete: false
---

# 游戏内 UGC 编辑器 + 创意工坊 —— 可行性评估与分阶段计划

> 玩家视角：游戏里自带一个交互编辑器，能自己捏飞机、画关卡地图、摆编队，做完直接开一局试飞；做得好的传创意工坊给别人玩。开发者自己也用同一个编辑器造官方内容。

## 1. 可行性总评（2026-07-02 调查）

| 方向 | 可行性 | 依据 |
|---|---|---|
| **自制飞机** | 🟢 高 | AircraftParams 是纯数据 Resource（~35 个 @export 字段），spawner 已在运行时 `duplicate()`+逐字段改写（先例现成）；PlayableAircraft 也是纯数据包装。JSON→运行时构造零障碍 |
| **自制地图** | 🟢 高 | 地块=多边形数据（JSON 烘焙 + Polygon2D 手画双轨已在跑）；Tab 图/相机全参数化。缺的只是"游戏内交互画多边形"这层 UI |
| **自制编队** | 🟢 中高 | 阵型=小段数学公式（6 种硬编码），但 spacing/阵型选择已可配；新形状需把槽位表数据化（工作量小） |
| **自制敌人/关卡逻辑** | 🟡 中 | 敌机 params 是 .tres，但 per-type 微调（flare 失败率/装填时长）硬编码在 spawner 两个 match 块里，需外置成 JSON（1~2h 重构） |
| **创意工坊（Steam）** | 🟡 后置 | 需 GodotSteam（GDExtension）+ Steam 上架。**P4 前先走"本地 mod 文件夹 + 文件分享"**，不阻塞前面全部 |

**架构底子好**：全代码库已广泛使用 `JSON.parse_string` + `user://` 读写（地理/建筑/底图/存档全是这套），运行时加载用户内容是既有惯例而非新发明。

## 2. 安全红线（强制）

- **只加载 JSON（自定义 schema），绝不加载用户 .tres / .gd / .pck**——Godot 文本资源可内嵌脚本 = 任意代码执行。工坊内容全部走纯数据 schema + 加载时校验。
- **数值围栏**：飞机编辑器暴露的每个字段带 min/max clamp（对齐 DESIGN_PHILOSOPHY 的 600–2200 区间等），防"9999 速度"破坏体验；越界内容加载时钳制 + 提示。
- UGC 内容一律 `user://ugc/` 下，与官方资源隔离；坏文件加载失败要优雅降级（跳过 + 日志），不崩游戏。

## 3. 数据 schema（P0 交付物，草案）

```
user://ugc/
├── aircraft/<name>.json    # {schema_version, display_name, params:{~35 字段子集}, weapons:{gun/missile/...引用官方武器 id + 微调}, icon_color}
├── maps/<name>.json        # {schema_version, world_size_m, land_polygons:[[x,y]...], zones:[{center,radius,type}...], spawn_tables:{...}}
├── formations/<name>.json  # {schema_version, slots:[{x_mult,y_mult}...], base_spacing_m}
└── squads/<name>.json      # {schema_version, members:[aircraft_ref...], formation_ref}
```
官方内容逐步迁移到同一 schema（dogfood：官方=第一批 UGC）。

## 3.5 与进化系统的排序（✅ 用户定 2026-07-02）

**游戏性先行，编辑器 P0 后置**：进化/ACE 垂直切片先做（在 `feature/aircraft-evolution` 分支验证），
但切片实装**强制守三条护栏**，保证产出天生是编辑器能吃的形状（详见 [evolution-vertical-slice](../../planning/evolution-vertical-slice.md) §0）：
1. 进化树 = 数据文件（JSON），代码只读表；
2. 机型查找走单一 registry（AircraftDB），UgcLoader 将来只需注册；
3. 不往 match 块塞新 per-type 硬编码。

理由：ACE/继任/结算 UI 与编辑器正交；.tres→JSON 可机械迁移；反之 schema 依赖未验证的游戏性设计，先定必 churn。
**P0 数据化在进化切片验证通过、设计稳定后启动。**

## 4. 分阶段计划

### P0 — 数据化地基（先做，其余全部踩在它上面）
- [ ] 定 3 个 JSON schema（aircraft / map / formation）+ 版本字段。
- [ ] `UgcLoader`：扫 `user://ugc/`、校验、钳制、构造运行时对象（AircraftParams.new()+赋值 / 地理多边形注入 / 阵型槽位表）。
- [ ] 外置 spawner 两个 match 块的 per-type 微调 → `enemy_type_stats.json`。
- [ ] 阵型槽位表数据化（保留现有 6 种为内置表）。
- [ ] 战区布局 JSON 化（与 [map-expansion](map-expansion.md) §2.4 同一件事，一次做完两边受益）。

### P1 — 地图编辑器（最先见效，且是扩图的工具）

**已细化为独立 spec：[map-editor](map-editor.md)（2026-07-04，draft）**。要点：格子笔刷交互 +
矢量多边形存储（marching squares + Chaikin 与官方地图同保真）；可编辑图层扩为 8 类
（陆地/城区/机场/道路/建筑/云 mask/战区/出生点）；三区 UI（素材库左上 + 中间画布 +
工具栏笔刷/橡皮/线条）。原要点保留：
- [ ] 存/读 `user://ugc/maps/`；"试飞"按钮直接开一局加载该图。
- [ ] 用它铺 [map-expansion](map-expansion.md) 的官方大图（工具先行）。

### P2 — 飞机编辑器
- [ ] 参数面板（滑条 + 数值围栏）+ 武器挑选（官方武器 id 池）+ 线框预览/涂色。
- [ ] 试飞按钮（沙盒式单机试驾）。
- [ ] 与进化树挂接：自制机可声明"挂在哪条线哪一档"（走 aircraft-evolution-tree 的档位规则）。

### P3 — 编队编辑器
- [ ] 槽位拖摆（相对长机偏移）+ spacing 调节 + 阵型存档；小队预设（机型组合）。

### P4 — 分享 / 创意工坊
- [ ] 先：导入/导出单文件包（zip/JSON），社区手动分享即可用。
- [ ] 后：Steam Workshop（GodotSteam GDExtension，需 Steam AppID）或 mod.io（有 Godot 插件、不绑 Steam）。二选一待发行计划定。

## 5. 风险与依赖

- **P4 绑发行**：Workshop 依赖上 Steam；mod.io 是无 Steam 备选。P0~P3 完全不受影响。
- **编辑器 UI 工作量**是大头（P1~P3 各是一个小工具场景）；数据层反而便宜（调查结论：多数"0 min ready"）。
- **平衡性**：UGC 飞机进多人/榜单类玩法前需要"官方校验标"机制——现阶段单机沙盒可先不管。
- 性能：编辑器为独立场景不进战斗帧循环；加载 UGC JSON ≈ 现有地理 JSON 加载（~30ms 级）。

## 6. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-07-02 | 1 | 可行性调查 + 分阶段计划初稿：飞机/地图/编队三编辑器可行性高（数据层多数 ready）；安全红线=只收 JSON+数值围栏；P0 数据化→P1 地图编辑器（兼做扩图工具）→P2 飞机→P3 编队→P4 本地分享后接工坊（GodotSteam/mod.io 待发行计划）。 |

## 7. 索引锚点（调查依据）

| 关注点 | 位置 |
|---|---|
| AircraftParams 纯数据 + 运行时改写先例 | `scripts/aircraft_params.gd` / `scripts/survivor/survivor_spawner.gd`（_create_enemy duplicate+字段写） |
| PlayableAircraft 纯数据包装 | `resources/playable_*.tres` / `scripts/playable_aircraft.gd` |
| 敌人 per-type 硬编码（待外置） | `survivor_spawner.gd`（flare 失败率 / 装填时长两个 match 块） |
| 阵型公式 | `scripts/squad.gd`（get_formation_offset，6 种） |
| JSON 运行时加载先例 | `map_geography_data.gd` / `building_renderer.gd` / `tactical_map.gd`（JSON.parse_string） |
| 地图流水线 | docs/reference/map-pipeline.md / manual-map-editing.md |
