# AGL 文档入口

> 最后校订：2026-08-19。这里是 `docs/` 的导航与维护约定；游戏设计本身以
> [specs/_INDEX.md](specs/_INDEX.md) 为权威源。

## 先判断你要写哪一种文档

| 目的 | 放置位置 | 生命周期 | 能否作为设计权威 |
|---|---|---|---|
| 定义机制、数值、公式、行为和验收 | `specs/<kind>/<name>.md` | 随实现持续维护 | **是** |
| 告诉维护者代码或资源在哪里 | `reference/` | 易腐烂，随代码同步 | 否 |
| 解释跨文件架构和运行流程 | `systems/`、`architecture.md` | 随架构同步 | 否；数值回链 spec |
| 安排尚未完成的实施批次 | `planning/` | 完成后冻结或标历史 | 否 |
| 记录一次审计及其证据 | `audits/YYYY-MM-DD-*.md` | 只增补结论，不改写历史 | 否 |
| 记录一次已经发生的改动 | `changelogs/YYYY-MM-DD-*.md` | 历史快照 | 否 |
| 保存阶段性交接上下文 | `handoffs/YYYY-MM-DD-*.md` | 短期；完成后标已关闭 | 否 |
| 保存外部教材与研究材料 | `design reference/` | 原始资料 | 否 |

不要为了“顺手记一下”在 `docs/` 根目录新增散落文件。根目录只保留长期入口和项目级说明；
新审计、计划、交接和历史记录进入上表对应目录。

## 常用入口

| 我想…… | 从这里开始 |
|---|---|
| 快速理解项目 | [project-overview.md](project-overview.md) |
| 设计或实现一个新内容 | [reference/playbook.md](reference/playbook.md) → [specs/_TEMPLATE.md](specs/_TEMPLATE.md) |
| 查设计红线 | [DESIGN_PHILOSOPHY.md](DESIGN_PHILOSOPHY.md) |
| 查某个设计的当前状态 | [specs/_INDEX.md](specs/_INDEX.md) |
| 按文件找代码 | [reference/script-index.md](reference/script-index.md) |
| 按功能找代码 | [reference/code-index.md](reference/code-index.md) |
| 看仓库目录 | [reference/repo-layout.md](reference/repo-layout.md) |
| 查已知耦合点 | [architecture/known-seams.md](architecture/known-seams.md) |
| 查现有功能快照 | [reference/features.md](reference/features.md) |

## 项目结构速览

| 路径 | 当前职责 |
|---|---|
| `scenes/` | 可运行场景；`scenes/tests/` 保存 Visual QA 与开发面板场景 |
| `scripts/` | 游戏逻辑与全局服务；按 `aircraft/`、`ai/`、`survivor/`、`rts/`、`events/`、`ui/` 等子系统分层 |
| `scripts/tests/` / `scripts/tools/` | 无头断言回归 / 地图、图像与数据生成审计工具 |
| `resources/` | `.tres` 参数、玩家机、武器、舰船、地图、字体、飞机剪影和 shader 等运行时资源 |
| `i18n/` / `audio/` | 五个领域的三语本地化资源 / 音乐与音效 |
| `bench/` / `tools/` / `tmp/` | Godot 隔离启动与结果 / 仓库级校验生成脚本 / 被 Godot 隔离的临时产物 |
| `docs/` | 设计 SSOT、代码指针、架构、计划、审计与历史记录 |

完整目录树与 AutoLoad 落点见 [reference/repo-layout.md](reference/repo-layout.md)；这里不复制易腐烂的
单文件清单。

## 新建文件的落点

### 设计文档

先复制 [specs/_TEMPLATE.md](specs/_TEMPLATE.md)，再按内容放入：

- `specs/enemies/`：可生成的敌方机型或独立敌人；
- `specs/bosses/`：BOSS 本体、编成与阶段机制；
- `specs/weapons/`：武器或武器机制；
- `specs/skills/`：单项技能或一组不可拆分的技能改造；
- `specs/aircraft/`：玩家可驾驶机体；
- `specs/events/`：单个事件或王牌事件；
- `specs/systems/`：跨实体机制、平衡批次、地图及其它系统。

`kind` 是语义分类，目录是存放位置；例如 `kind: balance`、`kind: map` 仍放在
`specs/systems/`。spec 的稳定身份是相对路径（如 `aircraft/a-10`），因此不同目录可有同名文件。
建档后必须在 [specs/_INDEX.md](specs/_INDEX.md) 登记。

### 代码与资源

| 内容 | 默认位置 |
|---|---|
| 生存模式专属逻辑 | `scripts/survivor/` |
| RTS 指挥 | `scripts/rts/` |
| AI 子系统 | `scripts/ai/`；纯战术决策放 `scripts/ai/tactical/` |
| 飞机实体子模块 | `scripts/aircraft/` |
| 事件 | `scripts/events/` |
| 表演与镜头 | `scripts/presentation/` |
| 主界面、HUD 与通用 UI 表现 | `scripts/ui/`；生存模式专属 HUD 逻辑仍放 `scripts/survivor/` |
| 舰船 | `scripts/naval/` |
| 战区 / UGC / 音频 / 局外层 | `scripts/zones/` / `scripts/ugc/` / `scripts/audio/` / `scripts/meta/` |
| Visual QA 场景 | `scenes/tests/` |
| 通用数据类 | `scripts/` 根或已有同类子目录 |
| `.tres` 参数 | `resources/` 的对应分类；玩家机放 `resources/player/` |
| 地图、字体、剪影与 shader | `resources/maps/` / `resources/fonts/` / `resources/aircraft_silhouettes/` / `resources/shaders/` |
| 临时探针和生成产物 | `tmp/`，禁止放进 Godot 可扫描目录 |

更细的接入点和清单以 [reference/playbook.md](reference/playbook.md) 为准。不要为了一个新文件新建
只有单个成员的目录；先沿用现有子系统边界，确有三个以上稳定成员或独立所有权时再拆目录。

## 维护规则

1. 先改 spec，再改代码；代码落地后同步 reference 指针，不能反向把代码当设计真源。
2. 当前指导文档不得链接 `.claude/plans/`、临时 worktree 或个人绝对路径。
3. `changelogs/`、旧 `handoffs/` 是历史证据；路径失效可以注明，不要批量改写成“今天的事实”。
4. 不在 spec 正文写行号。行号只允许出现在 `reference/` 指针层；spec §7 只列文件和符号。
5. 容易变化的数量（技能数、敌机数、脚本行数）尽量链接自动生成表或索引，不在多个入口重复硬编码。
6. 修改代码函数或大幅移位后，按 AGENTS/CLAUDE 的索引维护清单同步并运行校验。

提交前至少检查：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_docs.ps1
python tools/verify_doc_anchors.py
python tools/verify_player_ref_holders.py
```

若当前环境没有 Python，必须记录未运行原因；不能把“未运行”写成“通过”。涉及运行时行为的改动还要通过
`bench/run.cmd` 或 `bench/run.sh` 运行相应 bench，禁止直接启动 Godot CLI。
