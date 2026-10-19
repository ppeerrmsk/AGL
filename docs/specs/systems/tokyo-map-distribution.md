---
id: tokyo-map-distribution
kind: system
status: in-progress
schema_version: 1
spec_version: 1
owner: AGL
depends_on: [systems/tokyo-bay-volume-map, systems/tokyo-prepared-streaming]
reconstruction_complete: false
---

# 东京地图安装包的发行打包（独立 PCK）

> 玩家从安装目录双击、桌面快捷方式或任意启动器打开发行版，都能进入东京湾三维地图；
> 地图包是随游戏分发的独立文件，不进主包，也不依赖启动时的工作目录。

## 1. 设计意图（Why）

- **体验目标**：发行版的东京湾地图可用性与开发机一致；不因"从哪里启动"而退回无地图的回退画面。
- **工程目标**：主包导出保持分钟级；M20（10 万级文件）有一条可重复、可校验、与编辑器导出器无关的打包路径。
- **背景**：按旧导出预设把 M20 打进主 PCK，Godot 4.7.2 编辑器在写完全部文件后的收尾阶段单核空转超过 60 分钟不完成（§3.5）。
  2026-10-19 的 release 测量改用"M20 不进 PCK、在程序目录放同路径目录"的做法：导出包里主 PCK 没有的 `res://` 文件
  会回落到"当前工作目录 + 相对路径"，所以只在工作目录恰好是程序目录时成立，不能发行。
- **不变量**：地图内容、包内 `res://` 路径、`package.json` 摘要与流送/校验代码全部不变；本规格只改"文件怎么到达 `res://`"。
- **Litmus 自检**：本规格不涉及玩法数值、战斗规则与美术；不以减少地图内容、降低精度或隐藏地图换取打包可行性。
- **反模式规避**：不在流送、`tokyo_installed_map` 或任何共享层写"导出版 / 编辑器版"分支；路径差异只在启动最早的挂载点消化。

## 2. 数据定义（What）

### 2.1 发行目录布局

| 文件（相对发行目录） | 内容 |
|---|---|
| `AGL.exe` + `AGL.pck` | 主包，由编辑器导出预设 `Windows Desktop` 生成，**不含** `resources/maps/tokyo_playable/` 与 `resources/maps/tokyo_volume_preview/` 下任何文件 |
| `maps/tokyo_playable_m20.pck` | M20 地图包 = 安装器认定的"M20 运行时"：`res://resources/maps/tokyo_playable/m20/` 下全部文件，加上三维启用门 `res://resources/maps/tokyo_volume_preview/downtown_lod.res`；包内路径与开发机散文件路径逐字相同 |

三维启用门：东京三维层只在 `downtown_lod.res` 存在时启用，缺它时正常路径整体退回二维底图（即使 M20 在）。它和 M20 一样不入库、随地图安装包下发，所以随地图包走，保证"有地图包 = 有三维地图"。

地图包格式：Godot 引擎自带 `PCKPacker` 写出的标准 PCK（与运行它的引擎同版本的包格式与版本号），不加密，
文件按包内路径字典序写入，每个文件起点按 32 字节对齐。读取端要求引擎 major.minor 不低于打包端。

### 2.2 项目设置

| 设置 | 值 | 说明 |
|---|---|---|
| `rendering/tokyo_map/installed_package` | `res://resources/maps/tokyo_playable/m20/package.json` | 不变；正常游戏入口读这份包 |
| `rendering/tokyo_map/installed_packs` | `PackedStringArray("maps/tokyo_playable_m20.pck")` | 启动时依序挂载的地图包，路径**相对可执行文件所在目录** |

### 2.3 主包导出过滤

| 字段 | 值 |
|---|---|
| `include_filter` | `*.json,resources/aircraft_silhouettes/*_detail.png,resources/maps/tokyo_full/*.bin` |
| `exclude_filter` | `audio_intake/*,audio_intake/**/*,resources/maps/tokyo_playable/*,resources/maps/tokyo_volume_preview/*` |

Godot 过滤器的 `*` 跨目录匹配，`resources/maps/tokyo_playable/*` 排除该目录下全部层级；`tokyo_volume_preview/` 在仓库里没有入库文件，排除它保证三维启用门只来自地图包；排除在包含之后执行，
所以 `*.json` 不会把包内 JSON 带回主包。

### 2.4 M20 规模（2026-10-19 实测）

| 项 | 值 |
|---|---|
| M20 文件数 | 106,810（106,789 个 `.res`、12 个 `.bin`、9 个 `.json`） |
| `assets/` 单目录文件数 | 106,788，文件名 = 内容 SHA-256 十六进制 + `.res` |
| 总字节 | 7,717,693,434（7.72 GB / 7.19 GiB），只有 `assets/` 与 `native/` 两个子目录 |
| 三维启用门 `downtown_lod.res` | 6,486,517 字节 |
| `package.json` SHA-256 | `424e4aa1db195308389ffcce30ff672bc5b23851810801847199b4d9d572d858` |

## 3. 行为与公式（How）

### 3.1 运行时挂载（AutoLoad `MapPacks`）

`MapPacks` 是 `project.godot` 里**第一个** AutoLoad，在脚本实例化（`_init`）时完成挂载：

| 条件 | 行为 |
|---|---|
| 进程带引擎特性 `editor`（编辑器、工具版跑项目、bench 工具版） | 不挂载；`res://` 直接读项目里的散文件，开发机安装方式不变 |
| 导出版，`installed_packs` 某项对应文件不存在 | 打印 `[MapPacks] missing <绝对路径>`，跳过；地图入口按原有"包缺失"规则回退 |
| 导出版，文件存在 | `ProjectSettings.load_resource_pack(<可执行文件目录>/<相对路径>, replace_files=false)`；成功打印 `[MapPacks] mounted <路径> in <毫秒> ms`，失败 `push_error` |

- **路径基准**：`OS.get_executable_path()` 的目录。不读工作目录，所以快捷方式、启动器或命令行从任意目录启动结果相同。
- **不覆盖主包**：`replace_files=false`，主包已有的同路径文件优先，地图包只能新增路径。
- **线程安全**：挂载会修改引擎的包内文件表；放在第一个 AutoLoad 的 `_init`，此时没有任何脚本或后台加载在读 `res://`。
  不得改成在 Loading 或首次取地图时懒挂载（那时可能已有后台线程在读文件）。
- 挂载后，`tokyo_installed_map` 的前缀门（`res://resources/maps/tokyo_playable/` 开头且文件存在）、`package.json`
  摘要、目录/覆盖/资产的逐项 SHA 校验与线程化流送全部按原路径工作，无需任何改动。
- 若工作目录里仍残留旧的同路径散目录，包内文件优先命中（包表先于工作目录回落）。

### 3.2 打包工序（bench 构建任务 `tokyo_map_pack`）

输入（环境变量）：

| 变量 | 含义 |
|---|---|
| `AGL_TOKYO_PACK_SOURCE` | 已安装地图的 `resources/maps` 目录绝对路径（其下有 `tokyo_playable/` 与 `tokyo_volume_preview/`） |
| `AGL_TOKYO_PACK_OUTPUT` | 输出 `.pck` 的绝对路径，必须在项目目录之外，且目标文件不存在 |

步骤：

1. 打包文件 = `installed_package` 所在版本目录（M20 为 `tokyo_playable/m20/`）的全部文件 + 三维启用门；源路径 = `SOURCE` + 相对 `res://resources/maps/` 的路径。
2. 拒绝条件：输出已存在；项目里存在版本目录或启用门的同路径散文件（否则回读会命中散文件而不是包）；启用门在源里缺失；源目录里出现隐藏文件
   （安装器复制期间放的 `.gdignore` 守卫，说明安装未完成）、`.import` 或 `.remap`。
3. 递归列出全部文件并按相对路径排序；逐个读一次字节 → 计算 SHA-256 →
   `assets/<64 位十六进制>.res` 要求摘要等于文件名 → `add_file_from_buffer` 写入 `<输出>.partial`。
4. 解析源 `package.json`，其中每个 `{path, sha256}` 绑定若指向本包目录，必须存在于包内且摘要一致；
   指向其它版本目录的绑定（增量包复用旧资产）只计数。至少要有 1 个包内绑定。
5. `flush` 后把 `.partial` 改名为输出路径。
6. 在同一进程挂载输出包，逐文件用 `res://` 路径回读 SHA-256，必须与第 3 步一致。
7. 收据写入 `bench/results/tokyo_map_pack_<UTC>.json`：包名、包字节、包路径与摘要、文件数、文件总字节、
   排序后"路径\t摘要"清单的 SHA-256、引擎版本、打包秒数、挂载毫秒、总秒数。

任何一步失败：退出码 1，不改名、不写收据。工序不经编辑器导出器，不触发编辑器文件系统扫描。

### 3.3 发行流程

1. **导出主包**：`AGL_BENCH_EXPORT_RELEASE=<发行目录>\AGL.exe`，`bench\run.cmd export_release 1 <超时> Shadow Headless`。
   过滤器已排除 M20，导出不再为它付 O(N²) 收尾；但若工程里有散装 M20，编辑器启动时仍要扫描它（冷缓存约 26 分钟），
   所以推荐在不含 M20 的工作树里导出。
2. **打地图包**：在不含散装 M20 的工作树里跑 `tokyo_map_pack`，输出到 `<发行目录>\maps\tokyo_playable_m20.pck`。
3. **验收**：按 §5 用导出包、非程序目录的工作目录跑一次 `tokyo_volume_c2`。
本节取代 [tokyo-bay-volume-map](tokyo-bay-volume-map.md) 里"导出必须包含 native/*.bin"与"组件清单及 11 份 coverage 的 bin 须进导出过滤器"两处主包导出要求：这些文件改随地图包分发，开发机散文件布局不变。

4. **后续地图更新**：新版本（如增量包 `m21/`，复用 `m20/` 资产）打成**另一个**包追加到 `installed_packs`，
   不重写已发行的 M20 包；避免大文件内偏移整体移动导致的整包重新下载。

### 3.4 候选方案比较

| 方案 | 路径改动 | 依赖工作目录 | 导出/打包代价 | 结论 |
|---|---|---|---|---|
| A. 独立 PCK + 启动最早挂载（本规格） | 无 | 否（相对可执行文件） | 线性；不经编辑器导出器 | **采用** |
| B. 程序目录外独立目录 + 基于可执行文件路径的绝对路径 | 包内 `package.json`、7 份 HLOD 目录、原生目录 `catalog.res`、`components.bin` 与 11 份覆盖表全部内嵌 `res://…/m20/` 路径；`tokyo_installed_map` 有 `res://` 前缀门。要么整包迁址重写（摘要全变、且绝对路径随安装位置变化），要么在所有读取点加路径映射 | 否 | 散文件；需迁址工序 | 否决：改动面最大，破坏"包身份 = 摘要"的不变量 |
| C. 用编辑器导出器拆成多个较小 PCK | 无 | 否 | 收尾代价取决于**单目录**文件数而不是每个 PCK 的文件数（§3.5），拆包不降总代价 | 否决 |
| C'. 把 `assets/` 拆成多级子目录再走编辑器导出 | 全包迁址 | 否 | 单目录规模降为 1/分片数 | 否决：与 B 同样要重写全部路径与摘要 |
| D. 主 PCK 外放同路径目录（2026-10-19 测量用法） | 无 | **是**：导出版 `res://` 回落到工作目录 | 无 | 仅限测量 |
| E. 旧预设整包进主 PCK | 无 | 否 | 收尾 O(N²) 空转 >60 分钟 | 否决 |

`load_resource_pack` 不能直接挂载磁盘目录：4.7.2 的目录型包源只接受 `res://` 本身（引擎内部用途），
所以"目录外放 + 挂载"必须是 PCK（或 ZIP）形式。

### 3.5 Godot 4.7.2 导出 10 万级文件时收尾空转的原因

源码定位（4.7.2-stable）：

1. 编辑器导出 `export_project_files` 写完全部文件与 `.remap` 后，调用 `_get_filtered_cache(paths)` 生成导出包的
   UID 缓存、全局类表与扩展表；它对**每一个导出路径**调用一次 `EditorFileSystem::get_file_uid(path)`。
2. `get_file_uid` → `find_file` → `_find_file`：按目录逐级找到所在目录后，在该目录的文件数组里**线性**比较文件名
   （源码注释 `todo make faster`）。
3. Windows 的 NTFS 不区分大小写，编辑器文件系统走不区分大小写分支：每次比较都对数组里的文件名调用一次
   `to_lower()`，即"分配新字符串 + 逐字符查大小写表"。
4. M20 的 106,788 个资产都在 `assets/` 一个目录里。每个路径平均比较约 N/2 次，总计约
   N²/2 ≈ 5.7×10⁹ 次 `to_lower()`，单核、零 IO——与观测到的"最后一个 `.remap` 写完后单核空转"一致。

规避方式与效果：

| 做法 | 收尾代价 |
|---|---|
| 导出过滤器排除 M20 | 不对 M20 路径查 UID，消失（本规格采用） |
| 拆成多个 PCK 仍用编辑器导出 | 每次导出仍在同一个大目录里线性查找，总量不变 |
| 把单目录拆成 k 个子目录 | 约降为 1/k，但需全包迁址 |
| 用 `PCKPacker` 直接打包 | 不经编辑器文件系统，线性（本规格采用） |

合成工程实测（2026-10-19，Godot 4.7.2 工具版无头导出，每个文件是约 10 字节的 JSON，文件名为 64 位十六进制 + `.json`；
"收尾"取写字节停止增长到导出结束的零写入段，CPU 时间与墙钟几乎相等，即单核满载）：

| 组 | 扫描（到 PCK 开始） | 写入 | 零写入收尾 | 总计 |
|---|---:|---:|---:|---:|
| 单目录 5,000 | 35 s | 4.5 s | 13.1 s | 56 s |
| 单目录 10,000 | 64 s | 12.8 s | 45.0 s | 126 s |
| 单目录 20,000 | 158 s | 88.6 s | **181.7 s** | 434 s |
| 20,000 分到 256 个子目录 | 174 s | 97.0 s | **6.7 s** | 284 s |
| 单目录 20,000，导出过滤排除（另有 10 个保底文件） | 138 s | — | **2.4 s** | 144 s |

- 收尾随单目录文件数按平方增长：10k→20k 为 ×4.04。按 20k 点推算每次比较约 0.9 µs，
  M20 单目录 106,788 个文件只收尾一段就约 1.4 小时，与观测"60 分钟以上不完成"一致。
- 分目录把收尾降到 1/27；导出过滤排除则完全没有收尾。
- 扫描段与目录布局无关，排除也省不掉（文件仍在工程里）：这就是"含散装 M20 的工程冷启动扫描约 26 分钟"的来源，
  因此 §3.3 推荐在不含 M20 的工作树里导出主包。

## 4. 结构与组成（Structure）

| 部件 | 职责 |
|---|---|
| AutoLoad `MapPacks` | 启动最早按 `installed_packs` 挂载地图包；记录本进程实际挂上的包 |
| bench 构建任务 `tokyo_map_pack` | §3.2 打包、核验与收据；只显式调用，不进 `all` |
| 单测 `map_packs`（进 `all`） | 守卫：`MapPacks` 是第一个 AutoLoad；`installed_packs` 均为相对路径 `.pck` 且含 `maps/tokyo_playable_<installed_package 版本目录>.pck`；每个导出预设的 `exclude_filter` 含 `resources/maps/tokyo_playable/*` 与 `resources/maps/tokyo_volume_preview/*`，`include_filter` 不含这两个目录名 |
| 导出预设 `Windows Desktop` | §2.3 过滤 |
| bench 启动器开关 `AGL_BENCH_EXPORTED_CWD` | 让导出包从项目外任意已存在目录启动，验证与工作目录无关 |
| 既有 `tokyo_installed_map` / HLOD 流送 | 不改 |

## 5. 验收标准（Acceptance / Litmus）

- [x] 打包：106,810 个 M20 文件 + 启用门逐个回读 SHA-256 一致；`package.json` 包内绑定全部一致；收据入 `bench/results/`
- [x] 主包导出：不含 `resources/maps/tokyo_playable/` 与 `tokyo_volume_preview/` 任何文件，导出用时为分钟级
- [x] 导出包以项目外、非程序目录的工作目录运行 `tokyo_volume_c2`：日志有 `[MapPacks] mounted`，地图 `hlod=true active=true`
- [x] 同条件下 HLOD 统计与工具版一致：隐藏 / 超预算 / 未覆盖帧为 0，待交接帧与切换次数落在工具版轮间范围内
- [x] 缺地图包：导出包不崩溃，打印 `missing` 并走原回退
- [x] 挂载耗时记录在案（启动期一次性）
- [x] 性能：仅启动期一次性挂载，无新增 `_process` / `_physics_process` / `_draw`（纯事件级 O(1) 豁免帧时门）
- [x] 已知 seam 未触碰
- [x] i18n：无玩家可见文本
- [x] 文档：本 spec 已登记 _INDEX；AutoLoad 列表、script-index、code-index 同步
- [ ] 正式完整局（导出包从快捷方式进入东京湾、打满一局）未做

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | 4.7.2-stable 源码：导出收尾、编辑器文件系统查找、PCK 读写与 `load_resource_pack` | 根因见 §3.5；目录型包源不可用于外部目录 |
| E0 合成导出 | 合成工程 5 组导出（§3.5 表） | 收尾零写入段随单目录文件数平方增长；分目录 1/27；过滤排除消失 |
| E1 聚焦 Shadow | `bench\run.cmd tokyo_map_pack 1 3600 Shadow Headless`，源为主检出 `resources\maps` | 106,811 个文件（M20 106,810 + 启用门）共 7,724,179,951 字节；打包 74 s，挂载 551 ms（工具版，含项目目录扫描），逐文件回读 SHA-256 全部一致，`package.json` 包内绑定 21 个一致；包 7,741,337,718 字节。独立 Python 审计（解析 PCK v4 目录）：路径有序唯一、与源逐项对上无缺无多、大小一致，抽样 3,000 个内容逐字节相同 |
| E1 聚焦 Shadow | `export_release`（不含 M20 的工作树） | 53 s，`AGL.pck` 185.7 MB、3,819 项，无任何 `tokyo_playable` / `tokyo_volume_preview` 地图数据 |
| E1 聚焦 Shadow | 单测 `map_packs` | 8/8 |
| E2 集成 Shadow | `all 1 1500 Shadow Headless`（不含 M20） | 105 项失败 14、运行时错误块 43；与 cdc1846 基线（104 项失败 14、43 块）逐段失败计数相同，新增 `map_packs` 段 0 失败。`test_tokyo_component_page` 的导出过滤检查改为断言主包排除地图二进制 |
| E3 Visual | `tokyo_volume_c2 36 420 Shadow Visual`，VSync 关，T R R T T R 交错；导出包 `AGL_BENCH_EXPORTED_CWD` 指向项目外空目录 | 导出包 3 轮：挂载 338–352 ms，`hlod=true`，隐藏/超预算/未覆盖/过期帧全 0，待交接 366/361/369 帧、切换 264/266/273 次，平均 135–137 FPS。工具版 3 轮：待交接 357/369/358、切换 261/262/264，超预算/未覆盖/过期 0，隐藏帧 6/0/0（首轮 6 帧是已知快速平移间歇竞态，工具版本就读散文件，与挂载无关），平均 117–122 FPS。导出包每轮约 8,600 条剪影 PNG 告警是 PR #8 修复的既有缺陷 |
| E3 Visual | 同上，临时移走 `maps/` | 打印 `[MapPacks] missing …`，地图 `2d baseline`，无崩溃（退出码 1 来自 C2 HLOD 门） |
| E4 完整局 | 未做 | |

## 6. 实现计划（Task Pipeline —— 工作令）

### 阶段 1 — 方案与工具
- [x] 源码定位导出收尾空转原因（§3.5）
- [x] 候选方案比较（§3.4）
- [x] `MapPacks` AutoLoad、`installed_packs` 设置、导出过滤
- [x] `tokyo_map_pack` 构建任务
- [x] 启动器 `AGL_BENCH_EXPORTED_CWD`
- [x] 静态守卫单测 `map_packs`

### 阶段 2 — 验证
- [x] 合成工程导出：平铺 / 分目录 / 排除三组对照，确认 O(N²)
- [x] 打 M20 包并逐文件回读
- [x] 导出主包，从项目外工作目录跑 C2，与工具版对照
- [x] 缺包回退
- [x] `test_tokyo_component_page` 的导出过滤检查从"主包 include 地图二进制"改为"主包 exclude 地图二进制"

### 阶段 3 — 发行前（不在本批）
- [ ] 导出包从快捷方式进入东京湾的正式完整局
- [ ] 安装器 / 商店仓库布局按 §2.1 放置 `maps/`
- [ ] macOS 等平台的包目录（应用包内 `Resources`）另行定义

## 7. 索引锚点（Where —— 唯一允许放指针的地方）

| 关注点 | 文件 |
|---|---|
| 运行时挂载 | `scripts/map_packs.gd`（AutoLoad `MapPacks`） |
| 打包工序 | `scripts/tests/build_tokyo_map_pack.gd`（`BenchRunner.BUILD_TASKS["tokyo_map_pack"]`） |
| 静态守卫 | `scripts/tests/test_map_packs.gd`（`BenchRunner.UNIT_TESTS["map_packs"]`） |
| 项目设置 | `project.godot` 的 `rendering/tokyo_map/installed_packs` |
| 导出过滤 | `export_presets.cfg` |
| 启动器开关 | `bench/invoke_godot.ps1` 的 `AGL_BENCH_EXPORTED_CWD` |
| reference 索引 | script-index.md / code-index.md 的对应条目 |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---|---|
| 2026-10-19 | 1 | 初稿：独立 PCK（M20 + 三维启用门）+ 启动最早挂载；4.7.2 导出收尾 O(N²) 根因与合成实测；E1–E3 验收 |
