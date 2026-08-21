# 飞机顶视轮廓资产

项目级代码入口见 [Reference Index](../../docs/reference/_INDEX.md)；设计与验收契约见
[aircraft-top-view-silhouettes spec](../../docs/specs/systems/aircraft-top-view-silhouettes.md)。

本目录只保存已经逐架核对过来源的现实飞机顶视轮廓。当前正式目录由
`reference_manifest.json` 中 `status = reviewed` 的条目决定；只有这些条目可以出现在
`AircraftSilhouetteCatalog.TEXTURE_PATHS` 中。

## 美术与数据契约

- 128 × 128 RGBA PNG，机头朝上，四角透明。
- 可见像素的 RGB 恒为白色；游戏运行时用 `icon_color` / `wing_color` 着色，所以玩家、敌人、王牌和阵营变体共享同一张图。
- 轮廓必须直接来自可复用的顶视图、正投影三视图或作者发布的顶视剪影。只允许裁切、剔除来源中明确标注的武器/辅助线、旋转、等比缩放、居中和抗锯齿。
- 禁止凭印象补画机翼、尖角、进气道、尾翼或其他几何；禁止使用生成式模型重建正式轮廓。
- 原创/虚构机、尚未定型的概念机，以及没有干净可靠顶视来源的现实机继续走旧 polygon/special renderer。
- 禁止加入涂装、国籍标志、文字、摄影纹理、渐变、阴影或内部线条。

## 维护流程

1. 在 `tmp/aircraft_refs/` 保存下载的工作副本，不把参考原图提交进生产资源目录。
2. 用 `scripts/tools/trace_orthographic_outline.py` 从闭合线稿或已有实色层提取外轮廓；用 `scripts/tools/normalize_aircraft_reference.py` 统一尺寸与边距。
3. 人工逐架叠图检查；在 `reference_manifest.json` 登记来源、许可、署名、处理边界与 alpha 哈希。
4. 只有通过审查的 key 才加入 `scripts/aircraft_silhouette_catalog.gd`。
5. 运行：

```powershell
C:\Users\noelu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe scripts/tools/audit_aircraft_silhouettes.py
```

审计会验证清单与运行时映射一致、PNG 契约、当前 AircraftParams 覆盖，以及生产 alpha 与已审参考哈希一致。
