# AGL — 俯视战斗机模拟沙盒

Godot 4.6 / GDScript / GL Compatibility。

俯视 RTS 式操控战斗机，较真实航空物理演算，极简线框美术。

## 文档索引

### 快速检索（先读这个）

- [docs/code-index.md](docs/code-index.md) — **代码索引**：按功能主题索引到 `文件:行号`，直接定位任何功能实现

### 核心参考（需要理解设计时读）

- [docs/scripts-reference.md](docs/scripts-reference.md) — **脚本 API 参考**：类继承、所有变量/方法、物理演算流程、Resource 参数定义
- [docs/ai-system.md](docs/ai-system.md) — **AI 系统**：状态机、BFM战术决策树、飞行员能力/压力/态势感知、编队跟随
- [docs/survivor-mode.md](docs/survivor-mode.md) — **生存模式**：波次/刷怪/经验/升级系统、与沙盒差异、进化技能
- [docs/ground-units.md](docs/ground-units.md) — **地面单位**：SAM/AAA/雷达站、数据链、车队系统
- [docs/resources-catalog.md](docs/resources-catalog.md) — **资源参数总表**：所有 .tres 的具体数值汇总

### 设计文档

- [docs/project-overview.md](docs/project-overview.md) — 项目概述、目录结构、场景树
- [docs/features.md](docs/features.md) — 已实现功能清单与待实现清单
- [docs/architecture.md](docs/architecture.md) — 架构设计、物理公式、编队扩展规划
- [docs/aircraft-params.md](docs/aircraft-params.md) — AircraftParams 参数说明与新机型添加方法
- [docs/radar-system.md](docs/radar-system.md) — 雷达系统：锥体判定、锁定计算
- [docs/missile-system.md](docs/missile-system.md) — 导弹系统：SARH制导、武器模式、三阶段机动
