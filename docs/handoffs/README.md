# Handoffs

- [2026-10-14地图问题研究与接手索引](2026-10-14-map-upload-guide.md)：问题到代码的导航、原始证据、来源范围、重建缺口与验收入口。
- [2026-10-14东京湾工程接手需求](2026-10-14-tokyo-map-engineering-requirements.md)：目标、约束和验收矩阵。

返回 [文档入口](../README.md)；要把交接稿里的代码发现固化为长期导航，更新
[Reference Index](../reference/_INDEX.md) 及对应专项索引。

阶段性交接稿统一放在这里，命名为 `YYYY-MM-DD-<topic>.md`。

交接稿只保存“下一位维护者继续工作所需的临时上下文”，不承载设计权威。设计决策与数值必须回写
`docs/specs/`；代码位置必须回写 `docs/reference/`。任务结束后在稿头标记 `status: closed`，并链接最终
spec 或 changelog。

`docs/` 根目录现存的 `HANDOFF-2026-07-22*.md` 是迁移前历史文件，保留原位以避免破坏旧链接；新文件
不要继续放根目录。
