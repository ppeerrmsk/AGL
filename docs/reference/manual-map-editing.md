# 在 Godot 编辑器里手画地图

本文档教你用 Godot 编辑器直接"手搓"地图地块，叠加在 OSM 自动生成的地面之上。适合：修补 OSM 没覆盖的区域、手动画一些港口 / 地标 / 机场跑道、给地图加一些虚构元素。

> **Agent 制图审核规则**：不要每画一版就要求用户检查。必须先按
> [map-pipeline §0](map-pipeline.md) 完成固定机位基线、分层诊断和至少 3 轮内部迭代，
> 只提交过客观门的里程碑候选。普通色偏、道路宽度、海岸碎边、悬空线和预览清晰度由 agent
> 自行解决；用户只负责方向分叉与最终毕业确认。工作图一律放 `tmp/`，Notion 不堆每轮 scratch 图。

---

## 1. 基础：坐标系和色调

地图坐标系（与游戏世界完全一致）：

```
      Y-（北）
        ↑
  X- ←  · → X+（东）
        ↓
      Y+（南）
```

- **原点 (0, 0) = 地图中心**（东京湾湾心）
- **1 px = 2 m**
- **世界范围**：`±7500 px`（即 ±15 km，合计 30×30 km）
- 任何坐标超出这个范围会被边界外 vignette 遮盖，但不会报错

### 常用色（从 `map_geography.gd` 的颜色常量复制过来）

| 用途 | RGB (alpha=1.0) |
|---|---|
| 陆地 | `Color(0.32, 0.35, 0.27, 1)` |
| 城区 | `Color(0.42, 0.38, 0.28, 1)` |
| 港口 / 工业区 | `Color(0.25, 0.25, 0.23, 1)` |
| 沙滩 | `Color(0.68, 0.62, 0.48, 1)` |
| 森林 | `Color(0.22, 0.30, 0.20, 1)` |
| 机场跑道 | `Color(0.22, 0.22, 0.22, 1)` |
| 湖泊（深） | `Color(0.16, 0.24, 0.32, 1)`（同海） |
| 道路 | `Color(0.88, 0.80, 0.56, 1)` |

想要**半透明覆盖某区域时**（比如给某块陆地加一层"浅色沙漠"效果），可以降 alpha 到 0.4-0.6。但用户反馈里明确说**地面不要半透明**，所以画地皮时用 alpha=1.0。

---

## 2. 打开编辑场景

1. 启动 Godot 编辑器，打开 AGL 项目
2. 左侧 **FileSystem** 面板找到 `scenes/map_manual.tscn`，**双击打开**
3. 场景根节点叫 `Root`（类型 `Node2D`），下面有个 `Background` 子节点
4. `Background` 是一个 `@tool` 脚本，**在编辑器里实时画出 OSM 的陆地/城区/道路作为参考底图** —— 你能直接看到整张东京湾的形状
5. 世界边框（青色方框 ±7500px）+ 网格（每 1km 一条灰线，原点有红十字）也在 `Background` 里，帮你判断坐标

### Background 的可调参数

选中 `Background` 节点，Inspector 里：

| 参数 | 作用 |
|---|---|
| `show_land_mask` | OSM 陆地底（灰绿色半透，默认开） |
| `show_urban` | OSM 城区（暗褐色半透） |
| `show_roads` | OSM 道路（米黄线） |
| `show_world_border` | ±7500 px 世界边框 |
| `show_grid` | 坐标网格 |
| `grid_step` | 网格间距，默认 1000（2km） |

临时关某些层方便描特定元素 —— 比如要画港口时把 `show_roads` 关掉，看得更清楚。

### 为什么 Background 不是 Polygon2D？

`MapFeatureRenderer._collect_polygon2d` 只扫描**真正的 `Polygon2D` 节点**作为手画地块。`Background` 是 `Node2D` + `@tool` 脚本，游戏加载时被自动跳过 —— 它纯粹是编辑器视觉辅助，**不会出现在实际游戏画面里**。

如果不想看到背景（想纯黑屏画），选中 `Background` → Inspector → 把所有 `show_*` 关掉；或者直接把 `Background` 节点的 `Visible` 属性关掉。

---

## 3. 画第一个多边形（Polygon2D）

### 3.1 添加节点

1. 选中 `Root` 节点
2. 按节点面板顶部的 "**+**" 按钮（或 `Ctrl+A`）
3. 搜索 **`Polygon2D`** → 选中 → 点 "Create"
4. 新建的 `Polygon2D` 默认是一个小白色方块在 (0, 0) 附近

### 3.2 设置颜色

1. 选中你刚加的 Polygon2D
2. 右侧 **Inspector** 面板找 **`Color`** 字段
3. 点色块打开颜色选择器
4. 可以用 RGB 数值填，或者直接拖滑块
5. **重要**：alpha 保持 1.0

### 3.3 画顶点（核心技能）

**进入点编辑模式**有两种方式：

- **方法 A**：选中 Polygon2D 后，视口顶部工具栏会出现一个**"Edit Points"**图标（小的圆圈+点图标）→ 点它
- **方法 B**：选中 Polygon2D 后，按快捷键 **`E`**

进入编辑模式后视口会显示现有顶点（小白点）+ 边线。

**操作**：

| 操作 | 键盘/鼠标 |
|---|---|
| **添加顶点** | 左键点击视口空白处 |
| **在边上插入顶点** | 左键点击现有边线 |
| **移动顶点** | 拖拽现有的白点 |
| **删除顶点** | 右键点击顶点 |
| **退出编辑模式** | 再按一次 `E` 或 `Esc` |

**画一个矩形港口举例**：
1. 加 Polygon2D，颜色设为 `Color(0.25, 0.25, 0.23, 1)`（暗港口色）
2. `E` 进入编辑模式
3. 依次在视口点 4 个角（例如以羽田机场位置为参考）：
   - 左键点 (-500, -5800)
   - 左键点 (500, -5800)
   - 左键点 (500, -5500)
   - 左键点 (-500, -5500)
4. 在 Inspector 的 **`Polygon`** 字段里能看到 PackedVector2Array 被填好

---

## 4. 如何精确定位坐标

画顶点时你点哪，顶点就在哪 —— 但视口里看不出具体坐标。有三招：

### 4.1 看 Inspector 里的顶点坐标

选中 Polygon2D，下拉 Inspector 里的 `Polygon` 字段，每个顶点的 `Vector2(x, y)` 都列出来。可以**手动输入精确坐标**而不是用鼠标画。

### 4.2 视口内的坐标显示

视口左下角（或右下角，取决于 Godot 版本）会显示鼠标当前所在的世界坐标。移鼠标到目标位置记下来就行。

### 4.3 打开网格对齐（推荐）

为了不画成歪歪扭扭的：

1. 视口顶部工具栏 → 找 **"Use Snap"** 磁铁图标（或 `Ctrl+Shift+G`）
2. 开启后，点击视口会吸附到网格
3. 网格间距在：**Editor Menu → Configure Snap** → **Grid Step** 设成 `(100, 100)` 或 `(250, 250)`
4. 这样画顶点会自动对齐到 100 的整数倍

---

## 5. 组织多个地块（重要）

一个 Polygon2D = 一个填充色块。如果要画很多地块，建议分组管理：

```
Root (Node2D)
├── Lands (Node2D)              # 陆地类
│   ├── Kawasaki (Polygon2D)
│   ├── Yokohama (Polygon2D)
│   └── BosoPeninsula (Polygon2D)
├── Ports (Node2D)               # 港口类
│   ├── KawasakiPort (Polygon2D)
│   └── YokohamaPort (Polygon2D)
└── Airports (Node2D)            # 机场类
    └── HanedaRunways (Polygon2D)
```

分组好处：
- 方便命名
- 以后想批量显示/隐藏某类，直接选 Node2D 切换 Visible
- 渲染顺序 = **场景树顺序**（后出现的画在上面），所以把港口 Group 放在 Lands 之后，港口就会盖在陆地上

### 怎么加分组 Node2D
1. 选中 Root，点 "+" → 搜索 `Node2D` → 取名 `Lands`
2. 拖动 Polygon2D 节点到 `Lands` 下面作为子节点（或右键 Polygon2D → **Reparent** → 选 Lands）

---

## 6. 图层顺序 / z_index

同一级节点按场景树顺序渲染：**靠后的 = 画在上面**。

如果要细粒度控制某个 Polygon2D 浮到最上或沉到最下，用 **`z_index`**（Inspector 里）：
- `z_index = 0`：默认
- `z_index = 1`：在同层之上
- `z_index = -1`：在同层之下

比如：想让港口永远盖在陆地上 → 港口 Polygon2D 的 `z_index` 设 `1`。

---

## 7. 保存 + 测试

1. **Ctrl + S** 保存场景
2. 回到 Godot 编辑器，**F5** 运行游戏（或直接 PowerShell `./Godot project.godot` 运行）
3. 进入生存模式，地图上应该能看到你画的形状
4. **调试日志**：游戏启动时控制台会打印：
   ```
   [MapFeatureRenderer] manual overlay polygons loaded: N
   ```
   `N` 就是你画了几个 Polygon2D。**不出现这行** = 场景路径不对或场景里没 Polygon2D。

---

## 8. 常见工作流：改港口 / 加机场跑道

### 加羽田机场 4 条跑道

羽田机场在世界坐标约 `(800, -6000)` 附近（真实经度 139.78°E、纬度 35.55°N 投影过来）。跑道大概几个平行长条。

做法：
1. Root 下新建 Node2D 命名 `HanedaRunways`
2. 加 4 个 Polygon2D，每个是长条矩形
3. 设颜色 `Color(0.22, 0.22, 0.22, 1)`（跑道深灰）
4. 依次画 4 条，每条大概 2000×200 px 长条
5. 保存测试

### 画东京湾 Aqua-Line（跨湾桥隧道）
其实游戏里已经有 `AQUALINE_PATH` 自动画虚线了。如果你觉得虚线位置不准，可以画自己的粗线多边形覆盖掉。

### 修正 OSM 漏掉的某岛屿

OSM 数据里小岛可能被过滤掉了。你可以画一个小 Polygon2D 填上：
1. 在地图上观察缺漏的小岛位置（估个坐标）
2. 加 Polygon2D，颜色陆地色
3. 画出粗略轮廓（6-10 个顶点够了）

---

## 9. 进阶技巧

### 9.1 贴底图参考

如果想按真实卫星图"描边"：
1. 把一张东京湾的卫星图 / 地图截图保存为 `.png` 放进 `resources/` 或任意目录
2. 回 `map_manual.tscn`
3. Root 下加 `Sprite2D` 节点
4. Inspector 里设 `Texture` 为那张图
5. 调整 `Position` 让它贴合世界坐标原点
6. 调整 `Scale` 让图片大小匹配游戏世界（试错到各地标位置对齐）
7. 把 `Modulate` 的 alpha 调低（比如 0.3）作为半透明底图
8. **在 Sprite 上面画 Polygon2D**，描出陆地轮廓
9. **完成后记得删掉 Sprite2D**（或把它 Visible 关掉），它只是参考，不应该被游戏加载
10. 或者在 `_collect_polygon2d` 的扫描里会自动跳过非 Polygon2D 节点，所以 Sprite2D 留着也不会被加载

### 9.2 一个 Polygon2D 最多多少顶点？

Godot 没硬限制。但 **50 顶点以下视觉上够好，30 顶点最常见**。太多顶点加载慢、编辑卡。

### 9.3 复杂形状：用 CSG 拼接？

Polygon2D 支持凹多边形但不支持"洞"（例如湖中岛）。要表达"洞"：画两个 Polygon2D 叠在一起 —— 外层大的陆地色 + 内层小的海色。

### 9.4 看不见画的东西？

- Polygon2D 的 `Visible` 属性没关吧？
- `Color` 的 alpha 是不是 0？
- 场景树里它是不是在 `Root` 下？（脚本只扫描 Root 的子孙）
- 坐标是不是在 ±7500px 外？

---

## 10. 快速参考卡

| 动作 | 快捷键 |
|---|---|
| 进入 Polygon 点编辑 | `E` |
| 退出编辑 | `Esc` |
| 添加节点 | `Ctrl+A` |
| 保存场景 | `Ctrl+S` |
| 运行游戏 | `F5` |
| 视口网格对齐 | `Ctrl+Shift+G` |
| 框选节点 | 左键拖 |
| 平移视口 | 中键拖 / 空格+拖 |
| 缩放视口 | 滚轮 |

---

## 11. 加载机制 / 脚本对接

手画层的读取逻辑在 `scripts/survivor/map_feature_renderer.gd`：

```gdscript
const MANUAL_MAP_PATH := "res://scenes/map_manual.tscn"

func _ensure_manual_loaded() -> void:
    # 加载 PackedScene，实例化，递归收集所有 Polygon2D 子节点
    # 读取每个 Polygon2D 的 polygon + color + global_position
    # 实例 free 掉（只读数据，不保留节点）
```

绘制在 `_draw_manual_overlays()` 里，夹在 `_draw_land_mask`（OSM 底）和 `_draw_urban_districts`（OSM 城区）之间。

**渲染层级（从底到顶）**：
1. 海
2. OSM 陆地 mask
3. **你的手画 Polygon2D**
4. OSM 城区
5. OSM 道路
6. AquaLine / TacView 装饰
7. 边界 vignette

如果想让手画的地块盖在 OSM 城区和道路之上（比如一个要突出显示的军事基地），要改 `_draw` 函数里的调用顺序：把 `_draw_manual_overlays()` 挪到 `_draw_highways()` 之后。

---

## 12. 示例：从零画一个"新岛"

假设你要在 `(2000, 2000)` 附近画一个虚构的"哨戒岛"。

1. 打开 `scenes/map_manual.tscn`
2. Root → "+" → Node2D → 命名 `SentinelIsland`
3. `SentinelIsland` → "+" → Polygon2D → 命名 `Land`
4. Inspector：
   - Color: `Color(0.32, 0.35, 0.27, 1)` 陆地色
5. `E` 进入点编辑
6. 视口里依次点：
   - (1800, 1800)
   - (2300, 1700)
   - (2500, 2000)
   - (2400, 2400)
   - (2000, 2500)
   - (1700, 2200)
7. `Esc` 退出编辑
8. `SentinelIsland` → "+" → Polygon2D → 命名 `Port`
9. Color: `Color(0.25, 0.25, 0.23, 1)` 港口色
10. `E` 进入编辑，画一个小矩形港口在 `(2300, 2200)` 附近
11. `Ctrl+S` 保存
12. `F5` 运行 → 生存模式看地图，应该能看到你画的新岛

---

## 13. 故障排查

| 症状 | 原因 | 修复 |
|---|---|---|
| 游戏启动控制台没"manual overlay polygons loaded" | 场景文件路径不对 / 场景为空 | 检查 `res://scenes/map_manual.tscn` 存在，且 Root 下有 Polygon2D |
| 看到形状但位置不对 | Polygon2D 的 `position` 非零，被额外加了偏移 | 选 Polygon2D，Inspector 里 Transform → Position 清零 |
| 形状颜色透明 | alpha < 1 或 modulate 异常 | Color 里 A 拉到 1.0 |
| 颜色奇怪偏色 | Polygon2D 的 `Modulate` 被改了 | 确保 Modulate = Color(1, 1, 1, 1) |
| 复杂凹多边形部分区域没填色 | Godot 2D 三角剖分对凹多边形有 bug | 拆成多个凸多边形分别画 |

---

## 14. 下一步：如果 Polygon2D 不够用

如果你觉得画地块太慢，可以考虑：

- **导入 SVG**：用 Inkscape / Illustrator 画矢量 → Godot 可以导入 SVG 为 Texture
- **使用 TileMap**：适合网格化的城市块，但不适合自由海岸线
- **Path2D + Line2D**：画线条（比如铁路、跑道中线）比 Polygon 更合适
- **写一个小的 Godot 插件**：右键菜单"复制成陆地色" / "批量改 alpha" 等便利操作（需要 GDScript 写 EditorPlugin）

这些都是以后的事了。先用 Polygon2D 练起来。

---

## 附：色卡速查（复制即用）

```gdscript
# 地面
Color(0.32, 0.35, 0.27, 1)  # 陆地（暗橄榄绿）
Color(0.22, 0.30, 0.20, 1)  # 森林
Color(0.42, 0.38, 0.28, 1)  # 城区
Color(0.52, 0.46, 0.32, 1)  # 郊区 / 农田
Color(0.68, 0.62, 0.48, 1)  # 沙滩

# 人工
Color(0.25, 0.25, 0.23, 1)  # 港口 / 工业区
Color(0.22, 0.22, 0.22, 1)  # 机场跑道
Color(0.88, 0.80, 0.56, 1)  # 道路米黄
Color(0.35, 0.28, 0.22, 1)  # 铁路褐

# 水
Color(0.16, 0.24, 0.32, 1)  # 深海
Color(0.22, 0.32, 0.42, 1)  # 浅海
Color(0.40, 0.55, 0.65, 1)  # 河流
```
