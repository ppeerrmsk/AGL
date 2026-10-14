# 飞机三维模型资产

`reference_manifest.json` 是三维飞机生产覆盖、来源边界、制作状态和四视角 QA 的机器可读清单。现实机的来源与许可继承 `resources/aircraft_silhouettes/reference_manifest.json`；原创/概念/特种机只引用项目现有轮廓、参数和批准 spec。

当前几何由 `scripts/experiments/volume_aircraft_catalog.gd` 确定性生成，并在预热后以共享只读 `ArrayMesh` 使用。可编辑源不是单张 PNG 等厚挤出；每个规范 key 必须提供自己的轮廓、剖面和结构定义，或在清单中明确声明同型共享。预热只创建 71 个机体与 12 个挂载类型的网格路由；`MultiMeshInstance3D` 节点在对应类型第一次有真实演员提交时才创建，空类型不常驻 3D 剔除。

完成状态不能手工凭印象填写：运行 `scripts/tools/audit_aircraft_volume_models.py` 检查当前 `AircraftParams`、别名、规范 key、来源、模型目录、真实装备到共享挂件目录的覆盖与 QA 状态。正式资源允许未完成时回退 PNG，但回退项不能计入全量完成。

`volume_aircraft_catalog.gd` 的 `build()` 是含完整静态结构的四视图/导出源；AH-64 与 CH-47 的真实演员另走 `build_runtime()` 无桨叶机身，并由 `volume_aircraft_mount_catalog.gd` 的共享 rotor 批次旋转。普通飞机的挂件同样只读正式配置、库存、装填、释放 CD、充能与过热状态，不拥有第二套武器逻辑。

正式 Survivor 通过 `scripts/rendering/aircraft_volume_overlay.gd` 的单一透明 SubViewport 合成飞机，不替换地图、Camera2D、碰撞、AI、武器、HUD 或世界反馈。当前候选以主视口 0.45 内部尺寸按 60 Hz 同步权威 transform，再以最近邻放大；机身保留逐顶点受光。`volume_aircraft_livery.gdshader` 在同一 surface/material/MultiMesh 内消费机翼顶点掩码与每实例副色/主色比值，恢复正式 `icon_color` / `wing_color` 而不增加批次；小挂载/旋翼使用无光照顶点色。高刷新显示器上只将到期的三维提交从 physics 同帧顺延到紧邻显示帧；密集挂载且持续低帧时，共享视口用带迟滞的 `UPDATE_ALWAYS` 规避 Windows GL 的半刷新率调度，不降低玩家/BOSS/玩法 tick。

普通飞机的机体始终保持三维；只有独立装备按实际输出投影跨度做 `22 px` 进入、`18 px` 退出的迟滞 LOD。玩家、BOSS、Sentinel 及其原生护卫/猎手、AH-64/CH-47 动态旋翼均豁免；压力工作量仍计入被 LOD 隐藏的潜在挂载，不能靠少画装备伪造性能通过。Shift+F11 可在同一批实体上切回 PNG；自动成对性能基线使用 `AGL_AIRCRAFT_VOLUME=off`，该路径不创建空 SubViewport。清单只有在 focused、生命周期、BOSS、默认 `all` 与性能门完成后才能从 `formal_default_pending_validation` 提升为 `formal_default`。
