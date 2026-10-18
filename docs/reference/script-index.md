# Script Index — 关键文件职责

局部完整楼体实景：`tests/tokyo_native_joint_preview.gd` / `run`显式native_joint_patch接同源地表、保留楼、候选顶/墙，24相机位姿首帧/稳定帧及空白负对照；不代表全图/FPS。`tests/tokyo_vector_roof_compare.gd` / `run`只按显式键分派，默认不变。

组合屋顶样件：`tests/tokyo_local_roof_gpu.gd` / `build`支持独立绑定encoded_indices，控制保留原始拓扑，候选只使用已审计简化索引，避免同索引对照掩盖轮廓变化。

局部整数屋顶GPU样件：`tests/tokyo_local_roof_gpu.gd` / `build`，Vector2代理顶点、二分街区表与恒定色法线；`tests/tokyo_vector_roof_compare.gd` / `run`显式local_roof_gpu同位对照及真实通道账，不作全图资格。

单样块屋顶GL对照：`tests/tokyo_vector_roof_compare.gd` / `run`，默认正式单面材质，双面仅显式诊断；原始索引屋顶与保存候选同位近中远、空白负对照、资源释放；截图差异不自动授美术或全图资格。

候选分层实际采样：`tests/tokyo_layered_sampler.gd` / `sampler_code` / `build` / `apply_updates`，127流式逐层更新；可选相机回调在旧合法域内移动，对比同姿态更新前后。`tests/tokyo_boundary_commit_preview.gd` / `run`显式moving_layer_updates，节奏绑定更新，不证明任意速度截止/峰值/FPS。

浮点层GPU直采样：`tests/tokyo_texture_update_probe.gd` / `sample_layered`将texelFetch整数值编码RGBA8，区分get_layer_data回读与GPU值；只用于失败定位。

实际补丁分层更新：`tests/tokyo_texture_update_probe.gd` / `run_layered`，127真实补丁行在Texture2DArray同RID更新一层并回读另一层不变；不是全层容量、地图连续显示或FPS。

纹理更新接口诊断：`tests/tokyo_texture_update_probe.gd` / `run`显式枚举本机更新接口并测试三种格式同RID更新回读；非整包峰值或FPS。入口`tests/tokyo_partition_stream_probe.gd` / `run`。

局部连续坐标选择：`tests/tokyo_boundary_commit_preview.gd` / `local_state` / `run`，显式route_x_offset平移候选中心，索引容量由绑定三层计算；两中心各±64、缩放0.4至0.625内选四态。六域外请求拒绝，96姿态首帧/稳定帧对照不替代独立来源覆盖。

局部四状态就绪替换：`tests/tokyo_boundary_commit_preview.gd` / `run`显式four_ready，10495440字节最终索引替换差分与双输出；12有向跳转无等待三层/相机提交，对比114就绪像素，非域外覆盖或预算资格。

准备窗口画面对照：`tests/tokyo_boundary_commit_preview.gd` / `prepare_upload` / `run`显式audit_pending，突发目标姿态后逐等待帧与目标就绪帧对照，差异计pending_mismatches而非由提交后相等掩盖；回读扰动计时，记录实际VSync。

直接上传准备：`tests/tokyo_boundary_commit_preview.gd` / `prepare_upload` / `run`，仅显式upload_ready逐层读取离线完整还原且绑定SHA的定长上传文件，三层全就绪才提交，取消清空；不把磁盘展开量算常驻，不证明冷读上界。

时间片准备实景：`tests/tokyo_boundary_commit_preview.gd` / `prepare` / `run`显式prepare_budget_us最多2000us，每段4096索引末检查，另记段越界、收尾及真实请求就绪墙钟；取消不提交半成品，未就绪移动帧仍单列失败范围。

局部可见检查：`tests/tokyo_boundary_commit_preview.gd` / `interactive` / `run`显式interactive_preview，有限窗口内左右平移、上下缩放；只用已准备双状态，不作为全图或用户已验收。

跨细节阈值实景：`tests/tokyo_boundary_commit_preview.gd` / `run`显式cross_zoom重用同中心简化/恢复双状态，连续平移缩放穿越来源阈值，对拍立即/稳定帧；仅已准备状态，不认证按需准备截止时间。

单层修复保存：`tests/tokyo_selectable_geometry_save.gd` / `run`显式single_layer_repair允许一层保存回读，默认仍要求三层；用于复用未修改网格与纹理。

边界包实际三层预览：`tests/tokyo_boundary_commit_preview.gd` / `pose` / `prepare` / `run`，共享编码纹理、保存网格与分段差分同帧提交；准备期间镜头移动单列未认证帧，四状态与稳定帧对照不冒充连续覆盖或正式资格。

整包诊断：`tests/tokyo_staged_resource_probe.gd` / `run`支持显式fixed_cpu_files与有界workspace，绑定已保存差分及双更新缓冲；不回读GPU，不授预算或实景资格。

稀疏槽读取保护：`tests/tokyo_sparse_mip_sampler.gd` / `sampler_code`生成的read_tile在mip读取前拒绝负ID、空槽与越界mip区间；缺槽返回诊断色，非连续显示资格。

差分跨帧发布诊断：`tests/tokyo_index_recipe_probe.gd` / `run_segmented_frames`由`tests/tokyo_partition_stream_probe.gd`显式入口调度；真实SceneTree帧取消/保留旧CPU值/完整后发布，非GPU交接。

差分分段准备：`tests/tokyo_delta_preparation.gd` / `begin` / `step` / `ready` / `take` / `cancel`，显式诊断4096索引步长、错误/取消不公开半成品；`tests/tokyo_index_recipe_probe.gd` / `run_segmented`核真实流，非正式调度。

有界差分索引探针：`tests/tokyo_index_recipe_probe.gd` / `decode_delta` / `run_delta`，显式delta_indices核实际保存流和错误拒绝；一次定长输出，非正式热路径或内存认证。

扩域配方GL验证：`tests/tokyo_nine_domain_preview.gd` / `choose` / `run` 显式recipe_indices绑定扩大实物、完整mip和54索引配方；同帧提交三层，限定0.4至0.625，不认证全图/FPS/峰值。

共享索引配方探针：`tests/tokyo_index_recipe_probe.gd` / `digest` / `load_bytes` / `assemble` / `run`，一次定长分配、32位填入绑定片段，避免append容量增长与slice副本；记录诊断时间/采样内存，仅partition显式index_recipe_probe入口，非实景性能认证。

侧墙恢复限定验证：`tests/tokyo_nine_domain_preview.gd` / `choose` / `run`只对显式wall_restore_threshold合同消费压缩索引，检查阈值两侧、稳定重放和完整索引对照；同步解压不授予性能资格。

九域连续提交候选：`tests/tokyo_nine_domain_preview.gd` / `digest` / `choose` / `run`校验绑定资源与域外拒绝，三层索引和相机同帧提交，对比移动帧与稳定帧；不授予全图、缩放范围或性能资格。

分阶段资源对象取证：`tests/tokyo_staged_resource_probe.gd` / `counters` / `run`只加载保存网格、八纹理及共同索引工作区，记录GL资源计数和对象释放；不画地图，不以弱引用或同步调用认证驱动暂存释放。

九域候选真实网格保存：`tests/tokyo_selectable_geometry_save.gd` / `unpack` / `build` / `run`从摘要绑定gzip属性/索引/mask制作三份ArrayMesh，保存回读打包通道并报告真实容量；只经partition显式请求，不授予GPU峰值、原子交接或正式资格。

位编码完整mip对拍：`tests/tokyo_bitpacked_mip_compare.gd` / `run`以同源全部mip比较旧/新编码的RGB与alpha、跨块过滤和非整数LOD，不作性能证据。`tools/tokyo_sparse_mip_payload.py` / `encode_block` / `decode_block` / `build`显式bitpacked/deduplicate，默认不变；`tests/tokyo_sparse_mip_sampler.gd` / `sampler_code`识别5/6/8位编码及9/10逐行游程模式，只有显式共享调色板清单才启用17/18/21/22/24/26，缺块/未知新模式返回诊断色而非旧图。

位编码GL像素门：`tests/tokyo_bitpacked_pixel_probe.gd` / `run`仅显式bench请求，校验保存载荷/Shader/逐块期望摘要，七模式逐像素回读与CPU Image/纹理弱引用释放；不证明驱动暂存峰值、连续地图或FPS。入口`tests/tokyo_partition_stream_probe.gd` / `run`。

住宅连续路径：`tests/tokyo_residential_continuous.gd` / `prepare` / `route` / `rejection_checks` / `digest` / `run`绑定同包覆盖合同，复用cell选择器运行连续四域缩放，独立重放像素摘要；由已存加载器`preview`显式调用，不接F5、不作FPS证据。

住宅已存资源加载：`tests/tokyo_residential_saved_load.gd` / `load_saved` / `live_count` / `run`绑定三网格并持有四索引/两材质，不展开顶点，报告已知费用与弱引用退出；`preview`显式GL四域三尺度首帧/稳态比较；`residential_saved_load`分派，不授予全图显示资格。

住宅区间资源回读：`tests/tokyo_residential_packet_audit.gd` / `bytes` / `valid_contract` / `run`校验文件与同包覆盖/纹理合同、固定索引实际容量上限及8类拒绝，复用稀疏平面构建及网格保存回读，输出已知资源费用；经`tests/tokyo_partition_stream_probe.gd` / `run`显式调用，不改正式地图。

规格302住宅原生成本：`tests/tokyo_residential_native_costs.gd` / `run`从摘要绑定来源与块面选择复用正式detail/建筑工厂，导出七档逐源属性范围；由`tests/tokyo_partition_stream_probe.gd` / `run`显式制作入口调用。不修改正式包，工厂重放尚须安装成员身份核对。

音频退出诊断：`tests/tokyo_audio_exit_probe.gd` / `run` / `_capture_playbacks`经显式audio_exit_probe入口验证主菜单音乐真实播放、停止/解绑流后跨帧WeakRef释放；同步捕获隔离临时强引用。仅诊断，不更改AudioManager正式退出行为。

连续相机域索引候选：`experiments/tokyo_cell_index_selector.gd` / `select`严格核ready/来源/索引身份和位置/缩放/旋转/俯角/分辨率，无合法域返回空。`tests/test_tokyo_cell_index_selector.gd` / `run`验证实际包边界、中心及拒绝条件；显式cell_index_contract进入bench，未接正式F5。

邻域首帧诊断：`tests/tokyo_envelope_visual_review.gd` / `_route`预载同身份索引、同提交段更新相机/索引并比较首帧与稳定帧；无certificate_leaf时记-1，不自动授予连续域或帧率资格。

分块mip测试shader：`tests/tokyo_sparse_mip_sampler.gd` / `build` / `build_map` / `sampler_code`绑定RGBA8载荷、块/mip/纹理表，四编码解码后过滤；build_map合并真实高度/UV/纹理身份平面并显式重绑参数。`tokyo_isolated_sampler_review.gd`显式sparse_mips和probe_lods接入，未接正式地图。

分块无损mip制作：`tools/tokyo_sparse_mip_payload.py` / `sha` / `encode_block` / `decode_block` / `build`保存纯色/局部R8/RG8/原RGBA字节流及精确float索引表，真实补齐GPU纹理行，保存后逐mip全量还原；`test_tokyo_sparse_mip_payload.py`验证四种编码及非法模式。GPU/运行时资格另验。

共享几何实物计费：`tests/tokyo_envelope_resource_audit.gd` / `run`复用逐角保存回读，可选atlas核真实平面及去重混合纹理，区分单索引与全部位置CPU索引持有费；不授予连续覆盖/联合预算资格。

混合索引图集实物：`tools/tokyo_mixed_palette_atlas.py` / `pack_rectangles` / `save_array` / `build`复用独立mip货架布局，按实际颜色数选择R8/RG8，保存索引页/颜色/偏移/metadata并从文件逐mip还原；`test_tokyo_mixed_palette_atlas.py`验证矩形不重叠及两种格式精确回放/实际字节计费。不等于GPU采样或全图资格。

闭合候选原生余量批次：`tools/tokyo_prepare_native_remainders.py` / `removal_ids` / `build`将最终水平面集合减去全局原生保留集，按原面成本有界分批，复用`tests/tokyo_selective_native_cost.gd`保存/回读逐角守恒；高楼不参与，未改页保持原资源。`test_tokyo_prepare_native_remainders.py`核来源分区与非法ID拒绝。

重烘后继闭合：`tools/tokyo_advance_layer_closure.py` / `face_contract` / `verify_replacement` / `build`核完整批次、逐面逐高度守恒、原生保留与纹理互斥，合并清单后复用全图闭合器；`test_tokyo_advance_layer_closure.py`含实际小资源端到端后继闭合，零重烘任务也不自动授权运行时。

全局保留面局部重烘：`tools/tokyo_rebake_layer_fallback.py` / `split_members` / `build`分离已保留原面，仅重烘受影响高度组，复用其余纹理；全保留组不留旧四边形，新回退另报而不自动授予删除资格。`test_tokyo_rebake_layer_fallback.py`含原面身份分割、局部重烘和全保留清空三项回归。

跨块回退闭合：`tools/tokyo_layer_fallback_closure.py` / `mark_group` / `build`要求全任务唯一完整、原面来源合法、纹理摘要有效；冲突/无收益面全局回退并列出重烘任务，不直接授予删除资格。`test_tokyo_layer_fallback_closure.py`覆盖共享面冲突传播和非法来源拒绝。

全图分层纹理批次：`tools/tokyo_bake_full_layer_batch.py` / `raster` / `build`共同收集相交页、按真高度及认可色板烘焙，保存回读像素；记录同高异色/无收益/无内核样本原生状态，跨块删除资格须另闭合。`tools/test_tokyo_bake_full_layer_batch.py`覆盖跨来源异色冲突与同色重叠/透明边。

全图分层烘焙索引：`tools/tokyo_full_layer_plan.py` / `sha` / `eligible` / `tile_sources` / `build`逐页核属性摘要，严格提取同高同色不透明正面，保留其余原生；共享世界块含2单位保护边。`tools/test_tokyo_full_layer_plan.py`覆盖斜面/渐变/透明/反面拒绝及跨界收集。

正式全图烘焙输入：`tests/tokyo_export_joined_layers.gd` / `run`核目录及组件身份，默认低楼/地表；export_layers/export_keys支持显式高楼局部成本导出，拒绝非法/重复层及缺键，full_catalog_scope区分子集，高楼原生资源不改。

正式三层格网目录：`tests/tokyo_joined_layers_catalog.gd` / `run`合并建筑与地表、逐源核三层面数、核全部页SHA及物理身份去重费用；不授予显示预算资格。`build_tokyo_joined_grid.run`显式all_groups支持有界全图归并。

全图地表无损分区：`tests/build_tokyo_current_grid_batch.gd` / `run`以显式ground_only仅处理层2，默认仍为建筑0/1；逐面守恒与保存回读相同，不改变运行时。

正式格网依赖：`tests/build_tokyo_grid_dependencies.gd` / `run`逐来源层验证归并片完整性；空ground覆盖表保持原生地表，非法表类型拒绝，不授予隐藏资格。

全图归并复用：`tests/build_tokyo_joined_grid.gd` / `read_reuse`与`run`按有序组件/面数/图格/正式来源比较旧归并页，匹配者只重绑origins并核输出SHA，不匹配者实际重建并逐角回读。

正式来源重绑定：`tests/tokyo_rebind_grid_batches.gd` / `run`将身份相同的旧行与正式补建行合成全叶batch，保留原批次追溯，核来源/层面数/owners/输出SHA及保存回读；不复制Mesh。

格网产物复用：`tests/tokyo_grid_reuse_inventory.gd` / `run`核正式组件身份、层面数与旧批次/输出SHA，给出实际可复用叶和补建索引；地表及视觉资格单列。

正式来源复用清单：`tests/export_tokyo_current_sources.gd` / `inventory`比较摘要绑定快照的组件描述身份，导出全叶边界、三层面数与来源；不把相同组件等同候选整体可安装。

无损颜色表图集：`tests/tokyo_independent_mip_batch.gd` / `build`按显式colors/offsets绑定混合R8/RG8索引与RGBA颜色，解码后过滤；texture_index支持平面复用，原RGBA分支不变，仅测试入口。

共享索引回放：`tests/tokyo_shared_index_audit.gd` / `run`，加载共享源和六叶区间，有界片段重建并校验SHA；局部解码时间不是FPS。

包络第一帧路线：`tests/tokyo_envelope_visual_review.gd` / `_route`，连续候选序列先取首帧与稳定帧，再单独参考遍历；不用于FPS验收。

无重叠采样诊断：`tests/tokyo_isolated_sampler_review.gd` / `run`，可选probe_tiles、重绑颜色表参数，单纹理RGBA分解与整数/半整数LOD对照，排除深度和光照混杂。

Shader错误门回归：`tools/test_bench_shader_gate.ps1`提取`bench/invoke_godot.ps1`的`Get-BenchRuntimeErrorBlocks`，验证shader编译失败不会漏判成功。

独立mip合批候选：`tests/tokyo_independent_mip_batch.gd` / `build`，四页无硬件mip图集、逐级夹紧和统一平面网格，仅显式GPU对照使用。

实际mip导出：`tests/tokyo_texture_mip_export.gd` / `run`，将引擎RGBA8各级像素与offset绑定源摘要导出，不替代GPU采样验收。

包络GPU对照：`tests/tokyo_envelope_visual_review.gd` / `run`，三个同位姿态原资源/统一索引候选/空白读回及费用，不授予连续显示资格。

包络实物费用回读：`tests/tokyo_envelope_resource_audit.gd` / `run`，显式测试入口，统一索引网格保存回读与纹理mip费用；不授予视觉/性能资格。

完整视野固定索引对照：`tests/tokyo_index_hybrid_review.gd` / `run`，显式index_hybrid_review入口，原资源/属性重建/24万固定容量候选/空白四相GPU读回及mesh/纹理费用，不授予全图或性能资格。

本机索引更新实景能力：`tests/tokyo_index_update_probe.gd` / `run`，显式index_update_probe入口，检查RenderingServer接口并以左右三角/空白像素负对照核GPU更新，记录索引数不变，不是地图性能门。

选择后原生几何实物计费：`tests/tokyo_selective_native_cost.gd` / `run`，由partition_stream_probe的selective_native_cost入口调用；按源面索引删除、原打包通道保留、repack与保存回读核验，未安装纹理或授予覆盖资格。

完整失败视野实物导出：`tests/tokyo_triangle_visibility_audit.gd` / `count`的可选export_directory由spatial_group_audit的单姿态triangle_export调用，验证三层当前组件SHA/身份/槽/面数再输出逐角属性，不是新资源接入或资格授予。

屋顶候选背面分组对照：`tests/tokyo_layered_roof_review.gd` / `wall_bins`按实际绕序法线保守判整个16方向组，显式wall_bins输入启用，仅固定对照姿态；未接运行时相机、预算选择或coverage合同。

当前真实高度屋顶GPU对照：`tests/tokyo_layered_roof_review.gd` / `run` / `mesh_from_bytes` / `difference`，绑定源属性与纹理，复用正式材质和投影，保存两缩放原生/候选/空白负对照；仅`tokyo_partition_stream_probe.run`显式入口，不授予正式覆盖或性能。

单组件指定槽导出：`tests/tokyo_grid_native_case.gd` / `run`的component_attribute_export支持显式component_slot范围检查；不带槽仍要求单网格，供当前地表实物核验。

当前块面实物导出：`tests/tokyo_block_source_match.gd` / `run`的export_current输出相交组件完整属性流及SHA，供已有完整楼匹配器核对；不改当前资源。

当前来源定位：`tests/tokyo_grid_native_case.gd` / `run`的source_trace_rect沿已认证snapshot的lod5完整树筛相交低层叶并导出真实页/组件映射，不重建几何或修改配置。

块面来源对应门：`tests/tokyo_block_source_match.gd` / `keys` / `run`核当前相交低楼组件SHA/身份、循环有向三角属性多重集；positions_only仅排查位置失配，不授予替换资格。`tokyo_grid_native_case.run`显式离线调用。

低楼块面实物对照：`tests/tokyo_grid_native_case.gd` / `run`的block_source_candidate复用roof样件保存回读流程，两变体均Factory detail1，来源普通楼与同高块面分别计费；显式离线，不授予正式来源等价、游戏楼保护或视觉资格。

来源屋顶中档样件：`tests/tokyo_grid_native_case.gd` / `run`的roof_detail_candidate，摘要绑定来源并生成detail0/1两实物、保存回读角摘要及费用；component_attribute_export导出单组件原属性。均显式离线，不接正式配置或授予视觉资格。

逐三角包络裁决：`tests/tokyo_triangle_visibility_audit.gd` / `count`沿实物SHA、身份、地表槽映射及面数核对，比较整片/逐三角投影包络面数；spatial_group_audit的triangle_visibility显式启用，不是像素遮挡或性能证据。

共享空间块：`tests/tokyo_shared_lod_cells.gd` / `run` / `position` / `save_cell`，双档重心分桶、真实顶点包围盒、逐档回读角属性核验与边界重复费用；默认九格，all_cells显式全源根守恒，仍不授予全图覆盖。`tokyo_spatial_group_audit.run`的shared_low_cells核实物摘要并联合高楼/地表下界，超门可拒绝，低于门不授予完整覆盖。

原生双档共享顶点样件：`tests/build_tokyo_shared_lod.gd` / `run` / `pack_indices`，逐字节角属性合并，两套索引存入ArrayMesh，保存回读并逐档角摘要核验；额外LOD索引计费，不接正式加载/自动LOD资格。

中近景实物共享核验：`tests/tokyo_shared_mesh_audit.gd` / `run` / `register` / `mesh_sha`，分批绑定完整清单，核源摘要、实际数组、层语义及无内置材质条件；部分批次不授予全图收益，默认不改运行时资源。

单一细片基底可行性：`rendering/tokyo_grid_native.gd` / `select` / `refine_entries`的私有_resident_fine_basis仅由`tests/tokyo_grid_native_case.gd` / `run`的resident_basis离线分支启用；固定根/叶地表及细片建筑，对保存姿态验证原面/页/覆盖门，正式读取器不启用。

固定空间组合原型：`tests/tokyo_spatial_group_audit.gd` / `run`，单叶地表与细片楼栋引用守恒，报告真实面数及未合并网格槽数；仅元数据，不证明绘制减少或运行时覆盖。

保存缺口驻留费用审计：`tests/tokyo_residency_gap_audit.gd` / `run`读取绑定的实景缺口，复用正式物理身份账本，分开报告固定集、缺件并集和全原生候选费用；`tests/tokyo_grid_native_case.gd` / `run`的residency_gap_audit离线入口。不是全图驻留可行性或性能证明。

有损候选拒绝与原子性回归：`tests/build_tokyo_simplified_ground.gd` / `rejection_checks`验证合同摘要、原组件摘要、原地表槽错配三类拒绝及目录/双树不变，再合法接入；`tests/tokyo_grid_native_case.gd` / `run`的simplified_ground_checks可接续保存姿态成本回归。

有损候选加载合同：`rendering/tokyo_simplified_ground.gd` / `read_json` / `attribute_sha` / `attach`绑定离线误差/连接及生产链并核实际原/新网格，成功后原子登记；`rendering/tokyo_grid_native.gd` / `read`的simplified_ground_candidate显式入口与ground_partition互斥。`tests/tokyo_grid_native_case.gd` / `run`的simplified_ground_binding经真实读取器，不是诊断树替换；正式包未启用。

最终联合连接核验：`tools/verify_tokyo_ground_connections.py` / `verify_sources`比较原/候选paths、roads、rails完整字段、端点、共享顶点和中心线关系，输出来源摘要；不改候选，不将源连接通过等同于最终视觉验收。

生成误差局部回退：`tools/locate_tokyo_ground_error.py` / `locate`将最终三角集合超距关联已修改源线，只恢复关联行，输出未关联面积；`tests/build_tokyo_path_replay.gd` / `run`支持reuse_original摘要/索引核对，复用未变原始回放，后续assemble仍核原始角多重集。

最终网格独立质量门：`tools/verify_tokyo_simplified_ground.py` / `digest` / `read_mesh` / `masks` / `corners` / `appearances` / `verify` / `main`校验非目标层逐角保留、目标属性与实际三角并集0.2双向误差；失败不出证书。`tools/test_verify_tokyo_simplified_ground.py` / `GeneratedGroundTests`覆盖正反例，不能用源折线通过代替最终网格通过。

格网自动档预算回退：`rendering/tokyo_grid_native.gd` / `select` 自动首选超预算时尝试合格lod5，仅无resident查询适用；显式档不变，未放宽显示/交接合同。

简化地表成本重放：`tests/build_tokyo_simplified_ground.gd` / `install_cost_candidate`只在测试内验证新分区资源/树守恒并替换成本与结构覆盖树，明确不授予有损质量资格；`tests/tokyo_grid_native_case.gd` / `run`支持摘要绑定的audit_poses_binding，simplified_ground_cost仅允许feasibility_only。正式读取器不支持此入口。

简化候选空间制作：`tests/build_tokyo_simplified_ground.gd` / `partition` 绑定物化报告与原始属性，复用两层二分/分页保存器；守恒仅相对新候选，不替代旧正式源的质量证明，未自动接入目录。

有损候选物化：`tests/build_tokyo_simplified_ground.gd` / `run` 校验已审查属性摘要并构建原生单槽组件，保存回读属性逐字节一致；`tests/tokyo_partition_stream_probe.gd` / `run` 的 materialize_ground 显式离线入口，不授予正式地图资格。

次级道路候选：`tools/build_tokyo_minor_road_candidate.py` / `build` 绑定原city与合格paths，保护宽度/主干/连接，复用可变宽度ribbon审查；`tests/build_tokyo_path_replay.gd` / `run`的minor_roads复用正式_path_ribbon及生产分区；`tools/review_tokyo_path_candidate.py` / `assemble`的minor/base校验原属性同向逐角一致后联合替换。仅离线候选。

生产切分重放与整地表候选：`tests/build_tokyo_path_replay.gd` / `run`的cell_index绑定使用旧索引16分区和split_fixed；`tools/review_tokyo_path_candidate.py` / `assemble`核同向逐角多重集后仅替换paths属性，输出全地表候选，不修改资源注册或覆盖门。

路径线带与连接审查：`tools/review_tokyo_path_candidate.py` / `ribbon` / `within_ribbon_error` / `review` 逐段矩形轮廓双向距离门、原新包络STRtree、中心线DE9IM关系固定点回退；`tools/test_tokyo_path_review.py` / `RibbonReviewTests` 为正反例。`tests/build_tokyo_path_replay.gd` / `run` 经partition_stream_probe复用工厂与外边界裁切，保存双属性供完整生产切分对照；不是正式网格等价证明。

目标路径简化制作：`tools/build_tokyo_path_candidate.py` / `digest` / `build` 复用既有simplify、生产登记摘要与原道路源，锁定记录连接点，只改变paths；`tools/test_tokyo_path_candidate.py` / `PathCandidateTests` 验来源漂移、禁止覆盖、连接点与非路径层保持。隐式相交/线带偏差/原网格回放仍是独立门。

地表候选实物网格：`tools/pack_tokyo_layered_ground.py` / `quad_vertices` 计算源所有权与裁空交集、世界坐标/图集UV和朝上绕序；`pack` 生成按真实层高分组的XYZ/UV二进制并回读。不包含Godot导入、mip资格或运行时接入。

分层地表裁空与同高图集：`tools/pack_tokyo_layered_ground.py` / `crop_pixels` / `pack` 保留全部基级RGBA、层高和源几何边界，输出拟合批surface与纹理费用；`tools/test_tokyo_layered_ground.py` / `LayeredGroundTests` 含空图拒绝、边缘与裁空回读。深层mip/实际合批未验，不授予运行时资格。

分层高清地表制作：`tools/build_tokyo_layered_ground.py` / `sha` / `layer_pixels` / `build`，真实高度分层、世界网格共享边缘和预算前置拒绝；`tools/test_tokyo_layered_ground.py` / `LayeredGroundTests` 验证颜色、孔洞、同位采样及异色冲突。不含运行时资格或F5接入。

联合地表预算模型：`tests/tokyo_grid_native_case.gd` / `run`的ground_cost_model仅枚举现有地表非支配成本前沿，与选定建筑的页/面/字节联合计费；不产生FPS或全局最优声明。

在途闲置完成件交接：`rendering/tokyo_cell_stream.gd` / `_collect_completed`仅已启用retain_unused且真实后台已完成时按原预算接管，Dummy取消和关闭不补载；`summary`记录retained_completions；`tests/test_tokyo_hlod_stream.gd` / `idle_completion_checks`覆盖六种完成/取消/预算/无效/关闭状态及再次请求不重载，不作连续显示证明。

显式地表分区真实接入：`rendering/tokyo_ground_partition.gd` / `attach` / `conserved` / `find_entry`在载入期核源摘要/身份、原地表包络与逐层树守恒，原子更新候选物理目录、选择树和覆盖树；`rendering/tokyo_grid_native.gd` / `read`仅ground_partition绑定启用，正式默认不变。

地表分区邻域覆盖门：`tests/tokyo_ground_split_review.gd` / `run`复用保存分区、规范身份并同步测试选择/覆盖树，50姿态预算/缺地表反例，1.25边界单列合法常驻接替；不加载同池、不授予实景通过。

单地表空间替代候选：`tests/tokyo_ground_split_candidate.gd` / `run` / `replace`复用既有两层二分、逐角守恒及分区保存回读；在独立内存地表树重放16页成本，不登记流送身份、不授予覆盖证明或正式接入。

地表精确重复面离线候选：`tests/tokyo_ground_duplicate_candidate.gd` / `run`经`tests/tokyo_grid_native_case.gd`分派，核真实源身份、全不透明/全属性同序角点，另存资源并回读逐角摘要；不改变正式目录，不把17面微小收益当预算修复。

正式页限交接可行性诊断：`tests/tokyo_prefetch_replay_case.gd` / `run`的handoff_feasibility分支独立报告保存姿态的原生切面预算与合法常驻层；逐页分层费用按实际piece_indices读取并核对求和，不能用父triangles计细分子集。实际页限随结果记录，不能把单姿态within_budget当连续显示或正式F5通过。

保存姿态预测器重放：`tests/tokyo_prefetch_replay_case.gd` / `run` / `vector`读取摘要绑定的旧报告，调用真实同步预测入口，计算一至两层后代费用及50–200ms四个裸视野切面的物理依赖并集；`tests/tokyo_grid_native_case.gd` / `run`的prefetch_replay分支接入。不恢复当时驻留状态，不构成Visual验收。

短时需求软保留候选：`rendering/tokyo_hlod_stream.gd` / `_prune_lru`仅AGL_TOKYO_RECENT_MESH_GRACE启用500ms淘汰排序，预算不足仍回收、默认关闭；`tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`核到期/压力退让。`tests/tokyo_wasd_audit.gd` / `run`显式诊断上限1024计划/512路径变化，不作正式性能采样。

来源令牌预编译：`experiments/tokyo_source_mask_index.gd` / `configure`将令牌条件去重、保留叶片重叠冲突，`covered`消费已认证层掩码；`experiments/tokyo_grid_coverage_index.gd` / `_refined_masks` / `compile_sources` / `covered_sources`避免提交时重建全来源身份表；`tests/test_tokyo_grid_coverage.gd` / `mask_checks`穷举共享令牌/重叠来源，`checks`核实际资产最终隐藏来源差分。

提交覆盖索引：`experiments/tokyo_grid_coverage_index.gd` / `configure`冻结认证依赖，`_build` / `_visible`沿三维包络树保守裁剪，`refined_layers`验证实际提交身份并恢复旧来源层。`rendering/tokyo_grid_native.gd` / `read`加载期编译、`covered`消费；`tests/test_tokyo_grid_coverage.gd` / `index_checks` / `refinement_checks` / `checks`以旧算法作差分真值。`tokyo_hlod_overlay.gd` / `_bind_target`独立计来源覆盖子桶；`tests/tokyo_wasd_audit.gd` / `run`仅显式追踪时在路线末导出CPU明细，不作性能验收。

近景原生地表显式候选：`rendering/tokyo_grid_native.gd` / `read` / `select`的grid_native_ground_only只切换已有地表表示，不改默认包；`tests/tokyo_grid_native_case.gd` / `run`的ground_frontier区分逻辑页瓶颈与几何成本，额外页只能作为实验，不能算正式验收。

候选地表目录接入：`rendering/tokyo_ground_catalog.gd` / `attach` / `rewrite`核原mapping与源摘要，只在初始化构造独立地表目录/两棵地表树费用；`rendering/tokyo_grid_native.gd` / `read`仅ground_components绑定启用。`tests/tokyo_grid_native_case.gd` / `run`核真实提交及旧地表整包不在物理缓存，正式默认不变。

独立地表装配：`rendering/tokyo_ground_page.gd` / `assemble`与`View.stream_identity`仅允许地表mask、单认证组件、明确父来源，楼栋槽为null；`rendering/tokyo_component_page.gd` / `assemble`显式格式分派；`tests/tokyo_ground_stream_case.gd` / `run`核同池真实加载、物理目录数量、费用、缺件/越层/错误费用与面数拒绝及退出释放。尚未授予地图选择器/F5资格。

地表独立组件制作：`tests/build_tokyo_ground_components.gd` / `run`沿认证诊断的mapping[2]提取现有地表槽，源SHA与身份、保存回读、逐角digest/AABB检查；`tests/tokyo_partition_stream_probe.gd` / `run`的build_ground_components显式入口，输出仅tmp，未自动接入。

现成地表分区组合：`tests/tokyo_grid_native_case.gd` / `run`的ground_mix/ground_mix_depth只展开已有来源树并枚举至多6个可见分区的原生/烘焙组合，每样本恢复目录，不改正式资源；通过预算才算可行。

地表/建筑费用定位：`tests/tokyo_grid_native_case.gd` / `run`的cost_breakdown记录实际切面逐页费用；use_native_ground仅在诊断对象选择既有原生地表分支，不修改正式地图。

有限显示可行性检查：`tests/tokyo_grid_native_case.gd` / `run`的feasibility_only按实际输出尺寸调用基础层与原生各档选择/覆盖/资格，记录面数/物理字节；不请求资源，不等于连续显示验收。

当前包驻留清单核算：`tests/tokyo_grid_native_case.gd` / `run`的inventory_only按物理路径去重基础层、原生叶、原生地表与新格建筑；package_override必须有精确摘要及相同grid_candidate绑定，报告区分来源快照包与实测包；只证明清单费用，不证明显示、RAM/VRAM或帧时间。

可选无损256子块：`tests/build_tokyo_grid_detail.gd` / `run`按认证原组件制作/保存回读，逐角点守恒；`rendering/tokyo_grid_detail.gd` / `expand`沿父身份扩展fine与来源依赖，拒绝未知父、重复子片与面数不守恒。`rendering/tokyo_grid_native.gd` / `read`仅显式grid_detail绑定启用；`tests/tokyo_grid_native_case.gd` / `run`验真实装配与全粗/全细覆盖一致、父子同交/错身份拒绝。

定点几何浪费审计：`tests/tokyo_grid_selection_case.gd` / `run`可输出来源/层成本、同输出原生LOD对照、逐三角屏幕包围盒，以及既有无损256分桶的逐角点守恒和正式包络计费；仅诊断，不授予运行时覆盖或性能验收。

有界原片子集：`rendering/tokyo_grid_native.gd` / `subset_entries` / `retire_subsets`与`rendering/tokyo_component_stream.gd` / `register_grid_subset` / `retire_grid_subsets`；固定物理目录配置后按内容身份登记实际切面子集，上限128，保留请求/pins/显示保护，退役同步清理逻辑视图与路径缓存。`tests/tokyo_grid_stream_case.gd` / `subset_registry_checks`核身份冲突、去重、保护、上限及回收；实际接合经`tests/tokyo_grid_native_case.gd` / `run`。

新格近景与空切面回归：`rendering/tokyo_grid_native.gd` / `select`超烘焙上限接原生地表，保留地表清晰度门；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_select_native` / `_predict_prefetch`接受空结果并按原预算重试/拒绝；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖空预测及窄预算空→全预算成功。

新格显式候选完整接合：`rendering/tokyo_grid_native.gd` / `read` / `read_bound` / `ground_only` / `select` / `refine_entries` / `covers_visible_layers` / `covered`，载入时建立固定粗细格层组合，超面数预算才按收益/新增绘制选择边缘细分；逐原片覆盖与实际提交资格校验。`tests/tokyo_grid_native_case.gd` / `run`支持真实尺寸、多姿态、逐页/逐片缺失拒绝、稳定身份及粗细物理联合计费，走同池正式_bind_target；非Visual/F5验收。旧异步预测器不理解新格，候选暂不启用该捷径。

新格/原地表联合切面：`tests/tokyo_grid_selection_case.gd` / `run` / `ground_tree` / `compare_queries`，完整格元数据分层投影并按空间格合并计页，原地表树保留真实资源费用/祖先覆盖，在余下16页预算选地表并联合24万面/192MiB检查；64姿态比较索引与原全扫描。支持多姿态/真实逻辑尺寸、原生地表回退、实际候选拒绝原因、原片边缘细分绘制成本估算；显式诊断，不替换正式地图。

新格空间候选：`experiments/tokyo_grid_query.gd` / `build` / `query`，真实层包络跨格入索引、全局高度和屋顶/阴影逆投影扩大查询；候选去重保持原顺序，最终仍使用原可见性判断，不改变隐藏资格。

新格同池三槽视图：`rendering/tokyo_grid_page.gd` / `assemble` / `assemble_group` / `assemble_segmented`沿ComponentPage分派，schema2同格双层、schema3逐层原片集合，身份/费用/重复片校验；`tests/tokyo_grid_stream_case.gd` / `run` / `inspect` / `inspect_group` / `inspect_binding`验证加载、错误装配、正式绑定入口及退出释放。`rendering/tokyo_hlod_overlay.gd` / `_bind_native_entry`支持SegmentedView逐片材质绑定，不替代整切面提交资格；非Visual/正式安装。

新格实际提交覆盖适配：`experiments/tokyo_grid_coverage.gd` / `source_layers` / `covered_sources`逐来源层核依赖身份与实际显示层；`refinement_data`双向核原片/认证面区间，`refined_layers`核粗细实际提交与屏外豁免；`tests/test_tokyo_grid_coverage.gd` / `checks` / `refinement_checks`覆盖缺片/错身份/重复粗细/重叠区间/相机移入及完整来源差分。非正式启用，不新增tick。

新格来源依赖表：`tests/build_tokyo_grid_dependencies.gd` / `run` / `read`，逐origin绑定原batch row/part、连续面区间及完整原叶分层面数，记录地表原生/纹理叶；不自动授予隐藏资格。

完整来源格网归并：`tests/build_tokyo_joined_grid.gd` / `run` / `run_series`，校验全批次来源/叶覆盖，最多8批顺序制作；复用packed join与独立逐通道校验，每格保存回读；origins记录原批次row/part与连续面区间，未授予运行时/地表覆盖资格。

完整来源格网批次：`tests/build_tokyo_current_grid_batch.gd` / `run` / `run_series`按完整来源快照叶序分批；最多8批串行复用packed分桶、逐角守恒、Component保存回读，保留逐面owners和正式来源，不按视口删面，地表接合独立待做。

当前完整来源导出：`tests/export_tokyo_current_sources.gd:6 run`保存当前lod4/lod5完整替换树、所有节点组件描述、正式来源覆盖及地表合同，Variant保存回读；不加载全图网格、不授予几何内容或安装资格。

多来源地表消费：`rendering/tokyo_native_ground.gd:7 surfaces`统一新内部数组与旧单面；native.decorate/cached_cut.native_tree/overlay._predict_prefetch逐面处理就绪与费用，`rendering/tokyo_hlod_overlay.gd` / `_bind_ground_surface`保留原UV/高度绘制。未开放目录适配，不启用正式包。

固定格离线资源制作：`tests/build_tokyo_grid_resources.gd:9 run`沿既有网格导入及正式地表plane保存/回读；`tests/tokyo_partition_stream_probe.gd`的grid_resources显式入口调用，不启用正式地图或覆盖资格。

实际切面第0层导出：`tests/tokyo_native_massing_cost.gd` / `run` / `_export_layer`支持与wall_export/ground_export互斥的layer0_export，按指定层原始面数核属性字节，供无损固定网格联合成本审计；不改变地图运行时。

大组合分批筛选：`experiments/tokyo_spatial_cut.gd` / `_combine_sweep` / `_pareto_costs`，每131072新增候选与完整旧前沿精确合并，不因超过批量回退二次扫描；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`跨批稳定身份差分。`tests/tokyo_handoff_selection_probe.gd` / `run`接受样本size以回放实际保护带；`tests/tokyo_wasd_audit.gd` / `run`沿已有LOADED_PHASE_TRACE开关记录实际慢查询。

父子前沿线性合并：`experiments/tokyo_spatial_cut.gd` / `_merge_parent`只消费已非支配的孩子集合，对照`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`原_insert稳定合并；不重新比较孩子之间的支配关系。

组合数值排序：`experiments/tokyo_spatial_cut.gd` / `_ordered_costs`用有溢出保护的64位编码进行原生排序；同面数/页数保留最小字节和原始首个身份；超界回精确比较。`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖超界回退及完整前沿差分。

选页组合排序扫描：`experiments/tokyo_spatial_cut.gd` / `_combine` / `_combine_sweep`按面数排序，以页数Fenwick前缀最小字节精确筛支配，恢复原顺序；临时候选有界，小组合保留原路径。`test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`与`test_tokyo_hlod_stream.gd` / `commit_ready_checks`核完整有序结果、重复费用、零费用、32页及64位字节。

固定失败姿态CPU计时：`tests/tokyo_handoff_selection_probe.gd` / `run`显式profile_selection清查询缓存并记录实际入口墙钟、solver构建次数及既有PerfBuckets差值，恢复追踪开关；裸查询不再暗跑扩区。纯元数据，不证明渲染性能。

缩远预取地表选档：`rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch`使用`tokyo_hlod_native.gd` / `ground_configuration`，避免实际LOD4而预取LOD5；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`通过真实预测入口覆盖缩远、缩近及无合格地表。

原生页数隔离候选：`rendering/tokyo_hlod_manifest.gd` / `resolve_native_page_limit` / `native_page_limit`，仅bench精确32开关生效，F5保持16；`tokyo_hlod_native.gd` / `select`缓存身份包含上限，`tokyo_hlod_handoff.gd` / `retain_display`显式上限，`tokyo_native_predictor.gd` / `request`将纯数据上限传到`tokyo_cut_worker.gd` / `submit`及`tokyo_cut_job.gd` / `run`。`test_tokyo_hlod_stream.gd` / `commit_ready_checks`核门控/保留边界，`tokyo_handoff_selection_probe.gd` / `capacity_audit`核当前运行选择与对应前沿一致。

未替换边缘叶细分诊断：`tests/tokyo_handoff_selection_probe.gd:110 edge_refinement_audit`，复用refinable与逐层守恒分割，在当前完整树保留既有地表绑定，比较深度0至4的16页切面；恢复原树并清空查询缓存。`_optimistic_new_ground`将新孩子或全部节点地表至多2面、全树字节归零后用正式切面求解器完整重选，另查48/96/192像素保护带；只作当前树的乐观面数下界，不生成纹理、不接入正式渲染。

离线驻留混合表示：`tests/tokyo_handoff_selection_probe.gd` / `mixed_audit` / `_mixed_frontier`，在每个原生节点比较原几何、合格纹理地表与完整孩子组合；原生/纹理单一模式的完整frontier逐值与生产选择器对齐，原树hash不变。仅resident_mixed_audit显式输入，不接入地图运行时。

建筑缺层精确现场：`tests/tokyo_wasd_audit.gd` / `layer_gaps` / `_collect_layer_gaps` / `layer_gap_snapshot`仅在失败快照记录精确画布、已提交mask和最多8个缺失叶节点，复用正式覆盖原语；`run`另存失败时物理网格/纹理缓存身份及精确查询，用`tokyo_handoff_selection_probe.gd` / `run`的resident_components输入离线重放，不复制Resource或修改失败门。

完成解码归还I/O槽候选：`rendering/tokyo_hlod_stream.gd` / `_decoded_capacity` / `_detach_speculative`复用既有同池CPU暂存；`tests/test_tokyo_hlod_stream.gd` / `decoded_slot_checks`及`PipelineFixture.ready_visible_mesh`核旧结果仍计费且当前读取不再被阻塞。

当前网格可发起时让路候选：`rendering/tokyo_hlod_stream.gd` / `visible_dispatch_ready`按队列首项、空槽及真实预算判定；`tests/test_tokyo_hlod_stream.gd` / `visible_dispatch_checks`核图片上传顺序、压力与退出。默认关闭，独立计数。

撤销预测的CPU解码暂存候选：`rendering/tokyo_hlod_stream.gd` / `_keep_decoded` / `_release_decoded`，同池有界且默认关闭；`tests/test_tokyo_hlod_stream.gd` / `cancelled_decode_checks`覆盖禁用、复用、过期、压力、关闭开关及退出。

原生缩远过渡预取：`rendering/tokyo_hlod_handoff.gd` / `native_exit_checkpoint`；`rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch`在终点已常驻时先预测原生边界近侧并同步调整位置提前量；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证跨界、未跨界和异常输入。

整树地表核查及显式导出：`tests/tokyo_native_massing_cost.gd` / `run` / `_export_layer`；partition_ground_inventory列两档完整树，ground_page_keys最多64个唯一存在页，沿用完整SHA/原始面数字节校验，不改变运行时选择。

清晰度过期立即重选：`rendering/tokyo_hlod_overlay.gd` / `_selection_due`使过期显示绕过常规50ms选页节流，提交清晰度/覆盖/预算门不变；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证地表上限、纯几何与原触发。

容量逐页归因：`tests/tokyo_handoff_selection_probe.gd` / `capacity_audit`同时输出每页身份、mask及三层面数，不加载/重切网格，不修改页数门。

当前树容量反事实：`tests/tokyo_handoff_selection_probe.gd` / `capacity_audit`只在显式capacity_audit输入比较16/24/32页，包含当前分区及地面替代；16页费用、键和mask必须与正式选择器完全相同。较多页不修改正式上限，单列formal_page_gate，不授予运行/覆盖/性能通过。

只读固定基底增量核算：`rendering/tokyo_hlod_stream.gd` / `handoff_increment`复用私有固定账本，仅集合变化时刷新；`tokyo_hlod_handoff.gd` / `append_streaming_bundle`可选fixed基底不复制/修改，校验共享组件和图片费用。`tokyo_hlod_overlay.gd` / `_handoff_bytes`消费；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`完整联合差分及拒绝原子性覆盖。

预载后同帧诊断：`tests/tokyo_hlod_route_probe.gd` / `play_session`仅显式LOADED_PHASE_TRACE接入`tokyo_render_trace.gd`，在process_frame恢复时结算前帧、结束时断开并恢复追踪开关；诊断结果不替代无追踪性能样本。

真实加载后战斗墙钟：`tests/tokyo_hlod_route_probe.gd` / `play_session`断言接管常驻集ready，记录测量起点纹理数和逐帧微秒墙钟；截图在窗口外，严格慢帧判失败，明确不替代完整局/全边缘验收。

固定资源交接增量计费：`rendering/tokyo_hlod_overlay.gd` / `_handoff_bytes`复用`tokyo_hlod_stream.gd` / `residency_request_ledger`计算物理联合减固定集，地表租约独立计费，未常驻时保持原路径；`tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`覆盖物理别名、重复图片、超限、冲突及空固定集。

绘制尖峰触发采样：`tests/tokyo_render_trace.gd` / `setup` / `_capture_draw_spike`仅显式DRAW_CAPTURE下建立ready、等待外部armed、保存一次已完成绘制慢帧及CPU桶；标记后续帧受文件I/O污染，不作性能验收。`tests/test_perf_frame_trace.gd` / `_test_draw_capture`覆盖未武装、阈值、一次性及拒绝覆盖。

真实地图层覆盖审计：`tests/tokyo_cut_worker_replay.gd` / `_layer_audit`沿已安装目录检查十个中心、四档尺度和九个屏幕位移；原视野必须三层完整，记录地面通过但全层拒绝的实际反例，与既有worker回放一并输出，不授予Visual或性能通过。

原生三层覆盖门：`rendering/tokyo_hlod_native.gd` / `covers_visible_layers` / `_covers_layers` / `_layer_complete`，替代原`_ground_complete`私有递归；`covers_ground`仍仅验证地面。`tokyo_hlod_overlay.gd` / `_cut_covers_current_view`复用和提交改走全层门。`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证平移后建筑mask失效与缺少同包络子页。

混合地表增量安装：`tests/stage_tokyo_incremental_package.gd` / `asset` / `partition` / `ground` / `build`汇总物理路径与新分区页身份，迁移地表/高度图后沿正式读取器和逐树验证；`tests/verify_tokyo_incremental_package.gd` / `run`逐摘要、实际ResourceLoader加载及运行时依赖项目内检查；由`tests/tokyo_partition_stream_probe.gd` / `run`的verify_incremental_package入口调用。`tools/install_tokyo_incremental.ps1`允许tmp和既有项目地图作为只读来源，保留新目录/锁/逐摘要及1GiB容量余量门。

组合临时字典消除：`experiments/tokyo_spatial_cut.gd` / `_combine`先以标量筛支配，只为存活候选分配完整Dictionary和页列表；`_insert`保持差分基准，`tests/test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`与`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证完整结果、稳定顺序和输入不变。

显式异步预取：`rendering/tokyo_native_predictor.gd` / `prepare` / `request` / `dispatch` / `usable` / `rejection` / `smooth_pan` / `close`维护来源、下一查询预测与拒绝原因；`rendering/tokyo_cut_worker.gd` / `configure_sources`加载时复制多来源；`rendering/tokyo_hlod_native.gd` / `decorate`统一结果费用和资源描述；`rendering/tokyo_hlod_overlay.gd` / `_async_full_prefetch_allowed`核联合预算，`_predict_prefetch`同步兜底后才dispatch。默认关闭，当前显示提交门不变。

后台切面基础件（现已接入显式预取候选）：`rendering/tokyo_cut_worker.gd` / `configure` / `submit` / `ready` / `take` / `close` / `_pure`管理纯来源快照和单个线程池任务；`rendering/tokyo_cut_job.gd` / `run`只做投影及完整求解，`experiments/tokyo_spatial_cut.gd` / `solve`显式trace_enabled=false避免后台访问PerfBuckets。`tests/test_tokyo_cut_worker.gd` / `run` / `Owner._exit_tree`验证差分/输入隔离/过期/退出，沿HLOD专项和全量生命周期；`tests/tokyo_cut_worker_replay.gd` / `run`由lifecycle runner的CUT_WORKER_REPLAY_OUT入口核真实候选目录与原生选择器一致。

原生查询归因：`tokyo_hlod_overlay.gd` / `_select_native`分记保护带扩展/半幅/四分幅/裸视野，`_step_geometry`记录预测父桶；`experiments/tokyo_spatial_cut.gd` / `solve` / `_frontier`分别累计可见性和组合子桶，并对初始零切面直接沿用首个完整分支。追踪关闭不计时，离线旧上下文兼容。

画外零分支组合省略：`experiments/tokyo_spatial_cut.gd` / `solve` / `_frontier`在可见性证明后跳过组合单位元；`tests/test_tokyo_hierarchical_pages.gd` / `_test_solver`验证根层与子层完整候选等价，保留原选择与预算。

武器音冷路径：`audio/audio_manager.gd` / `WEAPON_SFX` / `_get_sfx`提前持有六种既有机炮/导弹音，`tests/test_missile_grid.gd` / `run`验证路径与共享身份；基础切面必失败提前退出 → `rendering/tokyo_hlod_foundation.gd` / `select`，`tests/test_tokyo_hlod_stream.gd` / `foundation_checks`覆盖16/17页及面数门。追踪桶`tokyo_map_hlod_foundation_probe`与`tokyo_map_hlod_catalog_lookup`仅观测时启用。

网格领取优先对照：`rendering/tokyo_hlod_stream.gd` / `ready_visible_mesh` / `defer_speculative_upload` / `_step_textures`，仅在当前目标网格已读完/校验结束时延后投机图片上传；overlay `_request_target`登记当前目标，`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`核策略真值表。

原生驻留树：`rendering/tokyo_hlod_cached_cut.gd` / `native_tree`保留缺资源节点的几何，以费用哨兵排除；`rendering/tokyo_hlod_native.gd` / `select`可选resident参数跳过普通候选缓存、沿原完整求解/地表费用输出；`tests/test_tokyo_hlod_stream.gd` / `native_resident_tree_checks`覆盖完整父子替换和缺图拒绝。

原生屏内缓存桥接候选：`rendering/tokyo_hlod_overlay.gd` / `_native_screen_bridge`由原完整选择器求同档裸视野切面，沿资源/覆盖/联合预算门保留原目标预取；`tests/test_tokyo_hlod_stream.gd` / `native_screen_bridge_checks`覆盖拒绝反例。默认关闭。

交接选择只读对照：`tests/tokyo_handoff_selection_probe.gd` / `run`调用原_select_native，对比当前/未来保护视野与裸视野、48/192MiB选择的实际组件命中和地表图片；不流送，不代表提交或帧时间。入口`tests/tokyo_partition_stream_probe.gd` / `run`。

北侧固定坏点视图：`tests/tokyo_hlod_route_probe.gd` / `run`显式NORTH_FIXED_REVIEW追加两处原输出尺度及正常最大近景，按viewport输出比换算camera.zoom；不替换原八视图、不扩大玩家缩放上限。

无损叶面积切线：`tests/build_tokyo_lossless_leaf_partitions.gd` / `valid_leaf_plan` / `run`核清单SHA、原树、深度与全节点路径；`tests/tokyo_native_refinement_probe.gd` / `_refine`试算消费同一逐来源计划，生产再次复用；`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`覆盖非法身份/节点/轴反例。

共享槽公平候选：`rendering/tokyo_hlod_stream.gd` / `image_slot_reserve`在显式FAIR_IMAGE_SLOT下防当前图片被满额网格重复占槽；`rendering/tokyo_hlod_overlay.gd` / `_request_target`提供当前图片集合；`tests/test_tokyo_hlod_stream.gd`覆盖关闭候选、已有任务、缓存和单槽反例。

交接对应诊断：`tests/tokyo_wasd_audit.gd` / `run`显式HANDOFF_TRACE最多记录256次实际目标/预测身份变化、逻辑页到物理组件对应及既有wanted/pending顺序，不增加求解调用、不改变正式队列，不能作为帧时间样本。

离线面积切线计划：`tests/tokyo_native_refinement_probe.gd` / `planned_cut` / `_split`验证节点轴/阈值并沿既有无损分桶执行；`tests/build_tokyo_source_massing.gd` / `run`绑定候选/原树/深度/SHA与全部节点，未指定仍用中位分割；反例在`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`。`tests/tokyo_hlod_route_probe.gd` / `run`的WEST_REVIEW追加西侧两失败姿态和5.0近景，不替换原8图。

小额地表租约压力：`rendering/tokyo_hlod_stream.gd` / `reserve_auxiliary` / `_prune_lru`在真实容量不足时只即时回收非保护网格，不借用退役图片未来额度；`tests/test_tokyo_hlod_stream.gd` / `ground_lease_pressure_checks`覆盖712字节余量、保护资源、大额请求及计费守恒。

完整来源低楼接合：`tests/build_tokyo_source_massing.gd` / `split_depth` / `run`校验离线深度1–4，核当前树、完整来源三层、实际保留通道与两层不变后复用PageWriter/repack，每层逐角守恒，保留旧证明并重读联合包；`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`覆盖默认及非法深度。仅显式离线候选，不切换默认地图。

完整安装来源导出：`tests/export_tokyo_native_source.gd` / `common_source` / `unchanged_sources` / `run`按实际页定位最小共同子树，保留已有替换、仅导出完整未替换分支，核两档各自身份及正式楼保护；`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`覆盖共同祖先、单叶、未知、重复输入及部分子树已替换。仅离线制作，不授予覆盖或Visual通过。

增量无损细分前置资格：`tests/build_tokyo_lossless_leaf_partitions.gd` / `refinable` / `run`按当前覆盖树排除已有替换与正式楼；`tests/tokyo_native_refinement_probe.gd` / `select` / `_refine`的显式current_roots/eligible_leaf使拒绝页原样计费；`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks` / `RefinementSource`核当前树、拒绝页与正式楼反例。`tests/tokyo_native_massing_cost.gd` / `run`新增与ground_export互斥的wall_export（layer_1实际含标高楼屋顶），分字段保存，不改运行时。

可选地表高度流送：`rendering/tokyo_ground_height.gd` / `valid_texture` / `descriptor` / `shader_code`；`rendering/tokyo_native_ground.gd` / `read`核高度资源与层表；`rendering/tokyo_hlod_native.gd` / `select`计入ground_images；`rendering/tokyo_hlod_stream.gd` / `configure_hlod` / `load_image`核无mip数据纹理；`rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch` / `_bind_target`接原队列/材质。`tests/build_tokyo_ground_height.gd` / `run`保存回读；`tests/test_tokyo_hlod_stream.gd` / `height_texture_checks`实测异步/计费/退出。仅显式资源候选，默认包不变。

地表高度诊断：`tests/tokyo_native_ground_review.gd` / `run`仅显式height_depth_preview恢复片元深度，核高度纹理SHA/尺寸及16项层表，分别计颜色/高度三份费用；支持普通R8和双nibble索引，不修改正式材质或授予验收。

地面独立GPU对照：`tests/tokyo_native_ground_review.gd` / `run`支持最多16个显式位置/尺度/整数档位，与默认五处对照共用来源SHA、清晰度和原生/烘焙截图流程；退出0只证明制作完成，不授予视觉或性能通过。

合格已提交切面保留：`rendering/tokyo_hlod_handoff.gd` / `retain_display`核资格、覆盖和原显示预算；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`在新切面无解时应用，`_select_native`及`_predict_prefetch`继承当前显示档。`tests/test_tokyo_hlod_stream.gd` / `NativeSelectionProbe.select` / `commit_ready_checks`核预算传递、窄预算重试与缺边/过期/超限拒绝。

完整基础层候选：`rendering/tokyo_hlod_cache_policy.gd` / `complete_pool_bytes`；`rendering/tokyo_hlod_foundation.gd` / `plan`要求四层齐全；`tests/tokyo_foundation_audit.gd` / `sample` / `run`扩展实际包跨层去重和选择资格审计。

固定组请求：`rendering/tokyo_component_stream.gd` / `request_partitioned` / `_path_set`复用固定纯字符串集合，实际cache全齐后只保留pins；`rendering/tokyo_hlod_stream.gd` / `request_residency_only`用于暂无合格切面；`tests/test_tokyo_hlod_stream.gd` / `partitioned_request_checks`对拍顺序/保护/缺失重入队。`tests/tokyo_wasd_audit.gd` / `run`核固定叶实际切面与显示预算，不能沿用旧动态cut。

请求展开复用：`rendering/tokyo_component_stream.gd` / `request`按wanted/pins分别保存逻辑值快照与物理串表；`configure` / `close`失效。`tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`验证顺序、共享组件、原地修改和重配置。分发CPU子桶分别为views/paths/queue/textures。

固定集合账本缓存：`rendering/tokyo_hlod_stream.gd` / `residency_request_ledger`按固定数组值快照重建纯描述符账本，每次复制键表，保持共享物理身份去重；`tokyo_hlod_overlay.gd` / `_request_target`只增量加入实际目标、旧显示与预测资源。`tokyo_component_stream.gd` / `configure` / `_paths`一次展开只读目录，`close`清空字符串缓存。`tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`核共享费用、调用者键表修改、固定集合变化、空集与关闭；`tests/tokyo_hlod_route_probe.gd` / `patrol`显式ROUTE_TRACE输出CPU分项，不授予完整性能通过。

大常驻集成员查找：`rendering/tokyo_component_stream.gd` / `request`、`rendering/tokyo_hlod_stream.gd` / `_prune_lru`在单次操作建立保护集合，保留原请求顺序与LRU排序，不缓存跨帧Object引用。`tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`将5000项清理结果与旧规则逐值对拍，另核输入修改、清空请求和原计费/退役反例；微测不是游戏帧率。

固定叶容量纯值门：`rendering/tokyo_hlod_cache_policy.gd` / `static_pool_bytes`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖未开启、未知/不足显存、RAM边界和192MiB显示预算独立。正式路由探针`tests/tokyo_hlod_route_probe.gd` / `run`容量不足立即输出拒绝报告，加载每5秒保存一次状态，避免把回退旧图当候选预览。

固定最细叶显式候选：`rendering/tokyo_static_hlod_overlay.gd` / `_setup_geometry` / `_build_static` / `_step_geometry` / `_visible_static_cost` / `_sync_legacy` / `debug_state`，继承原合成/投影与同池生命周期，加载界面建立固定实例；`tokyo_hlod_cache_policy.gd` / `candidate_limit`与`tokyo_volume_preload.gd` / `script_path` / `state_ready`执行显式容量、路由与装配就绪门。独立真实GPU资源探针`tests/tokyo_static_leaf_probe.gd` / `run`从`tests/tokyo_partition_stream_probe.gd` / `run`分派，输出源边界夹取、逐像素alpha与非战斗计时，不授予完整验收。

原生全树/固定叶常驻审计：`tests/tokyo_native_massing_cost.gd` / `run`按物理组件去重输出全树、逐档根/叶内存，显式leaf_audit_only允许最多1024个纯数值视野；`_leaf_cut`沿正式投影遍历完整最细叶，不裁内容，记录三层面数、表面数与原预算违例。`tests/tokyo_wasd_audit.gd` / `run`失败快照记录当前目标/预测在途归属、加载/摘要线程状态及原生地面缺图阶段，不能把累计selection_usec当单帧。

原生地面完整切面：`rendering/tokyo_hlod_native.gd` / `covers_ground` / `_layer_complete`沿实际选择树验证全部可见后代，包络只用于排除不可见节点；`tokyo_hlod_overlay.gd` / `_cut_covers_current_view`保留投影与保护带，`_select_current_ground`仅在默认切面无解时求当前合格混合地面；`tests/test_tokyo_hlod_stream.gd` / `NativeSelectionProbe.ground_configuration` / `commit_ready_checks`覆盖重叠包络、祖先、缺页、资格与费用反例。`tests/tokyo_native_massing_cost.gd` / `run`支持有界poses，并在重复导出时核原始地面面数；`tokyo_wasd_audit.gd`记录display_tree_covered及native代码摘要。

常驻基础层＋邻区预载：`rendering/tokyo_hlod_stream.gd` / `configure_residency`支持同池、保留原固定集的载入前扩展；`tokyo_hlod_overlay.gd` / `_setup_geometry` / `prepare_loading_neighborhood` / `release_loading_neighborhood`在首次同步process前准备真实相邻细档，接管仅释放额外邻区保护；`tokyo_volume_preload.gd` / `_begin`传入预载开关。`tests/test_tokyo_hlod_stream.gd` / `LoadingOverlay._select_native` / `foundation_checks`验证固定集保留和额外资源释放。

预测选页尖峰：`rendering/tokyo_hlod_handoff.gd` / `native_preference_qualified` / `pan_lead`分离地面到期前偏好与当前资格，并限制投机前探；`tokyo_hlod_overlay.gd` / `_select_native`按实际保护带决定复用，`tokyo_hlod_native.gd` / `select`仅在追踪时记录solver_peak。`tests/test_tokyo_hlod_stream.gd` / `NativeSelectionProbe.select` / `commit_ready_checks`包含配置到期、速度与复用反例。无损制作`tests/build_tokyo_lossless_leaf_partitions.gd` / `run`兼容已迁址包不带制作机位，仍验证新输入与全部来源守恒。

混合地面接缝与选页分配：`rendering/tokyo_native_ground.gd` / `read` / `tree`核验平面高度等于原生最低地表；`tokyo_hlod_overlay.gd` / `_bind_target`应用高度与裁切footprint。`experiments/tokyo_spatial_cut.gd` / `_combine` / `_insert`先筛费用再拼接存活候选的页列表；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证32组确定性组合与原算法完全等价。`tests/tokyo_volume_combat_runner.gd`与`tokyo_wasd_audit.gd`统计native_ground_frames，独立预览`tokyo_native_ground_review.gd`遵守同一footprint/高度。

混合地面显式接入：`rendering/tokyo_native_ground.gd` / `read` / `tree`核源组件与地面范围、归一化JSON整数费用，复制选择树替换地面成本；`tokyo_hlod_native.gd` / `ground_configuration` / `select`按清晰度选择并附纹理清单/地表租约；`tokyo_hlod_overlay.gd`各交接入口统一等候、计费、保护与提交，实际quad裁到原生footprint，UV采样留边纹理。`tests/build_tokyo_native_ground_pack.gd` / `run`复用FlatBC3压缩、保存回读与透明覆盖哨兵。仅native.ground_override显式包启用，不改默认包。

原生地面烘焙候选：`tests/tokyo_native_massing_cost.gd` / `run`显式ground_export导出合格档的实际地面组件并核摘要/逐角计数；`scripts/tools/build_tokyo_native_ground_candidate.py` / `binding` / `bake`复用最高面栅格、预乘alpha和原生色板，拒绝非平面，不填洞；`tests/tokyo_native_ground_review.gd` / `run`五视野GPU前后图与独立成本统计，经partition_stream_probe分派。均为候选，不授予正式覆盖、美术或性能资格。

命中冷路径细分：`missile_manager.gd` / `_record_hit_cost`记录五个命中阶段首次/峰值/累计耗时，仅追踪时调用；`tests/tokyo_volume_combat_runner.gd` / `_bench_finish_now`输出全程命中摘要。`audio/audio_manager.gd` / `IMPACT_SFX` / `_get_sfx`提前持有四种既有命中音效，播放器池轮换不丢资源；`tests/test_missile_grid.gd` / `run`验证首次样本、峰值与音效路径/身份。

HLOD纯色几何诊断：`rendering/tokyo_hlod_surface.gd` / `textured_code`仅显式wall_solid_color与ordinary_building同时开启时使用旧色板屋顶/墙色，地表采样与alpha门不变；`tokyo_hlod_overlay.gd` / `_setup_geometry` / `_bind_target`接材质。`tests/tokyo_hlod_route_probe.gd` / `run`的WALL_REVIEW输出六同几何前后图及原生不变对照；诊断暴露方格代理过粗，不签美术通过。`tests/tokyo_native_massing_cost.gd` / `run`读取实际原生切面的三层成本与现有清晰度资格，经`tokyo_partition_stream_probe`显式输入分派，不放宽资格或安装混合表示。

地图二进制导出包含门：`tests/test_tokyo_component_page.gd` / `export_filter_checks`核实际export_presets的旧根目录、M20与版本化分区路径，以引擎String.matchn规则匹配，防止编辑器可读而导出漏文件。

候选资源安全复制：`tools/install_tokyo_incremental.ps1`校验inventory摘要、tmp来源与全新版本目标，共用owner PID测试锁，隔离编辑器扫描后逐文件复制/回读；拒绝覆盖或抢锁，只解除自己创建的临时隔离标记，不改默认包。

二分候选增量迁址：`tests/stage_tokyo_incremental_package.gd` / `record` / `asset` / `json` / `partition` / `build` / `run` 保留M20底座、逐摘要列出新增同页包、可逆重写分区物理路径、重绑HLOD/来源证明，输出tmp拷贝清单而不改默认。旧 `tests/package_tokyo_installed.gd` / `run` 明确拒绝含partition_override的包，防止静默遗失。

正式叶无损细分实物：`tests/build_tokyo_lossless_leaf_partitions.gd` / `run` / `save_json`，按失败视野选择正式叶，完整三层二分与打包回读、独立来源证明、合并旧替换后重验全图切面；经 `tests/tokyo_partition_stream_probe.gd` / `run` 的lossless_leaf_package入口。不改默认安装包。

地表租约原子交接：`rendering/tokyo_hlod_overlay.gd` / `_commit_ready_target`先取得独立新租约，再清旧画面并转移token；失败保持旧节点/可见性/租约。`tests/test_tokyo_hlod_stream.gd` / `CommitStream.reserve_auxiliary` / `commit_ready_checks`复现资源ready但预约失败，验证成功只余新租约及清理归零。

三层同页打包：`rendering/tokyo_partition_bundle.gd` / `valid` / `stream_identity` / `descriptor`保存独立三槽资源并验证逐层包络/面数/费用；`rendering/tokyo_partition_catalog.gd` / `normalize` / `node`只对schema3接入，`rendering/tokyo_partition_page.gd` / `assemble`零复制装配。`tests/repack_tokyo_partition.gd` / `run`重打包schema2并逐层回读守恒；`tests/tokyo_partition_stream_probe.gd` / `run`显式repack_partition入口。`tests/test_tokyo_component_page.gd` / `partition_checks`含错槽/缺件/费用/版本漂移；`tests/tokyo_partition_render_probe.gd` / `compare`兼容两种独立参考资源。

预测预取优先级：`rendering/tokyo_hlod_handoff.gd` / `prefetch_requests`保持真实目标由调用者先排队，投机部分先预测视野、后扩大保护带；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证原生和跨目录同名页的顺序与身份，预算账本不变。

正式源二分替换：`rendering/tokyo_partition_override.gd` / `json_binding` / `find` / `identity_matches` / `empty_game` / `read` 校验已审计正式来源与无游戏楼栋子树，`rendering/tokyo_partition_catalog.gd` / `replace`复制替换选择树；`rendering/tokyo_hlod_native.gd` / `read` / `select` / `covered`接原stream，不改变默认包。`tests/tokyo_partition_attach_probe.gd` / `find_entry` / `no_game_sources` / `run` / `cuts`检查正式原网格、未改层及完整地图切面；`tests/tokyo_tagged_low_cut_review.gd` / `mesh` / `preserve_known`绑定原生网格及逐面掩码，保留未修改面的原生压缩通道。

二分目录规范化与像素对照：`rendering/tokyo_partition_catalog.gd` / `normalize` / `node`验证完整二分树、组件身份/费用/包络/父子面数，转独立全路径键，不授予覆盖；`tests/test_tokyo_component_page.gd` / `partition_checks`含缺页/非法子数/面数漂移。`tests/tokyo_partition_render_probe.gd` / `compare` / `add_mesh`将公共stream实际页与完整根网格同位GPU读回，并用空画面负对照排除空图互比；`tests/tokyo_partition_stream_probe.gd` / `run`显式render_compare，非零像素差异或失效负对照拒绝。

二分逻辑页装配：`rendering/tokyo_partition_page.gd` / `assemble` / `View.stream_identity` 独立身份、三单槽组件零拷贝装配，拒绝缺件/重复映射/身份及字节漂移；`rendering/tokyo_component_page.gd` / `assemble` 仅显式format分派。`tests/test_tokyo_component_page.gd` / `partition_checks`进入既有focused/all；`tests/tokyo_partition_stream_probe.gd` / `run`显式logical_pages验证实际ComponentStream逻辑缓存及交接，不授予覆盖资格。

跨候选LOD流送对照：`tests/tokyo_partition_stream_probe.gd` / `read_partition` / `run` 支持两份独立摘要绑定的分区按pose.partition交替加载，沿同一96MiB池验证旧pins、新ready、排空与节点释放；不等价于正式渲染交接。

独立分页真实流送：`tests/tokyo_partition_stream_probe.gd` / `run`，入口 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 的PARTITION_STREAM。用现有HlodStream逐切面加载、旧资源pins直到新资源ready、关闭排空；报告明确不认证画面覆盖和性能。`tests/tokyo_partition_page_writer.gd` / `emit`现写schema2分区及MeshComponent实物，旧schema1原始网格候选不混用。

完整来源片指定档导出：`tests/tokyo_tagged_low_cut_review.gd` / `run` 的显式export_index分支复用 `tests/tokyo_residential_preview.gd` / `export_index`，核摘要、来源数、真实level/middle与保存回读。不从固定视野外推覆盖。

二分候选分页实物：`tests/tokyo_partition_page_writer.gd` / `emit` / `finish` / `verify_tree`，经 `tests/tokyo_native_refinement_probe.gd` / `_split` 的可选离线page_sink保存三层、逐角通道回读、树节点与资源成本一致性；`tests/tokyo_tagged_low_cut_review.gd` / `run` 显式save_pages调用。不沿用正式覆盖凭据。

普通标高低楼实际切面复核：`tests/tokyo_tagged_low_cut_review.gd` / `mesh` / `run` / `capture`，由 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 的显式TAGGED_LOW_REVIEW入口读取摘要绑定的三层属性，调用正式Cut选择器并生成同位前后画面；不是正式目录或全图覆盖验收。

东京湾北侧离线成本反例：`tests/tokyo_native_refinement_probe.gd` / `export_cut` / `select` / `_refine` / `_split`。从实际组件导出完整顶点通道，验证再分桶三角形守恒；由 `tests/tokyo_hlod_manifest_audit.gd` / `run` 的显式参数调用。24页仅是离线失败对照，不改变正式16页门，也不授予覆盖或实装资格。

四边四角连续输入：`tests/tokyo_wasd_audit.gd` / `anchor_for_route` / `run`显式八条边缘路线，未知拼写拒绝、不默默回城区；`tests/test_tokyo_hlod_stream.gd` / `foundation_checks`覆盖路由唯一性与非法输入。GPU读回仅作覆盖证据。

中景投机I/O短缓存：`rendering/tokyo_hlod_prefetch_cache.gd` / `reusable` / `checks`只复用150ms内同身份/方向且覆盖未来视野的非显示计划；`rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch` / `_step_geometry`保留合格基础显示，实际提交与ready证明不读该缓存。`audio/audio_manager.gd` / `play_sfx_2d`细分资源获取与播放启动耗时，不改变音效行为。

中景概括独立制作：`tests/build_tokyo_middle_massing.gd` / `write_json` / `aligned` / `component` / `checks` / `run`回读336页实际组件、UV、纹理与正式楼全通道，组合概括网格和清晰纹理，独立recipe/coverage/5202组固定切面报告；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式`AGL_TOKYO_MIDDLE_MASSING_OUT`入口。`rendering/tokyo_hlod_manifest.gd` / `normalize`传递独立制作身份；`rendering/tokyo_hlod_foundation.gd` / `plan`只在192MiB配置常驻新中景；`tests/test_tokyo_hlod_stream.gd` / `foundation_checks`覆盖旧目录禁止、无效身份和96MiB拒绝。未授予正式安装资格。

远景固定基础层候选：`rendering/tokyo_hlod_foundation.gd` `plan` / `select`；`rendering/tokyo_hlod_overlay.gd`在显式 `AGL_TOKYO_RESIDENT_FOUNDATION=1` 下预载常驻，不随邻区pins释放。`rendering/tokyo_volume_preload.gd`核对候选身份。`tests/tokyo_foundation_audit.gd` `leaves` / `sample` / `run` 核算真实包固定分区；`tests/test_tokyo_hlod_stream.gd` `foundation_checks`验证清晰度/内存/面数/缺口反例。尚未通过Visual验收，不作为正式默认。

## 东京湾高速输入局部覆盖诊断

流送增量物理账本：`rendering/tokyo_hlod_handoff.gd` `append_streaming_bundle` 先验证完整bundle再提交；`rendering/tokyo_hlod_overlay.gd` `_request_target` 单次核算常驻＋目标＋保护集，候选预取仅追加差额，不跨帧缓存。`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks` 用1620组与原 `streaming_bytes` 的差分及拒绝原子性检查。

缓存桥接按实际ready跳过：`rendering/tokyo_hlod_overlay.gd` `_resources_ready` 同时供提交与桥接门使用；目标完整已加载时不再求缓存替代树，固定常驻切面先走轻量选择。`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks` 覆盖空目标/未知目录/缺纹理/缺页拒绝。

常驻预取消重：`rendering/tokyo_hlod_overlay.gd` `_predict_prefetch` 对完整合格的固定未来切面跳过整树预取求解，资源仍由固定请求集负责；`tests/test_tokyo_hlod_stream.gd` `foundation_checks` 验证真实调用与计数。

常驻层边界选择：`rendering/tokyo_hlod_foundation.gd` `catalog_at` 只在请求目录也为常驻层时使用真实尺度基础层，非驻留细档的提前交接不得被覆盖；192MiB显式高档可预载0.25目录中层，低档只使用0.1944根页。

高显存显示工作集候选：`rendering/tokyo_hlod_cache_policy.gd` `display_bytes` / `display_limit`；`rendering/tokyo_hlod_overlay.gd` `_select_hlod`保留48/96MiB首选，仅无解时尝试192MiB；`rendering/tokyo_volume_preload.gd` `take` / `_begin`核对显示配置。`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证96/192边界；`tests/tokyo_wasd_audit.gd` `run`可在首个缺口后诊断全部目录缓存是否可用。

提前细档失败回退顺序：`rendering/tokyo_hlod_handoff.gd` `actual_fallback` / `rendering/tokyo_hlod_overlay.gd` `_step_geometry`；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`检查真实档、已合格细档、原生与异常尺度豁免。原生/HLOD求解计时复用各自`select`既有solver_usec。



投影裁剪固定循环消除：`rendering/tokyo_cells_overlay.gd` `projected_layer_bounds` / `intersects_view`；1024组逐值差分`tests/test_tokyo_hlod_stream.gd` `projection_equivalence_checks`。

跨目录合格缓存：`rendering/tokyo_hlod_cached_cut.gd` `candidate_catalogs` / `select`，由`rendering/tokyo_hlod_overlay.gd` `_step_geometry`按有界三档使用；`tests/tokyo_hlod_route_probe.gd` `run`验证同stream；`tests/tokyo_wasd_audit.gd` `run`记录完整指纹。

当前边缘清单防覆盖：`rendering/tokyo_hlod_handoff.gd` `prefetch_requests` / `prefetch_changed`；`rendering/tokyo_hlod_overlay.gd` `_select_hlod` / `_select_native` / `_request_target`；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证跨目录身份与空预测。

大池逐出顺序：`rendering/tokyo_hlod_stream.gd` `_prune_lru` / `touch_display_resources` / `_prune`；确定性计费/保留/旧行为反例`tests/test_tokyo_hlod_stream.gd` `cache_pruning_checks`。

显存分档加载候选：`rendering/tokyo_hlod_cache_policy.gd` `pool_bytes` / `candidate_limit` / `append_bundle`；`rendering/tokyo_hlod_overlay.gd` `prepare_loading_neighborhood` / `release_loading_neighborhood`；`rendering/tokyo_volume_preload.gd` `_begin` / `_claim`交接同一资源池。默认未启用，实测容量由验收入口提供；边界/去重/拒绝不变测试在`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

缩放预测反向：`rendering/tokyo_hlod_handoff.gd` `prediction_zoom_rate`由`rendering/tokyo_hlod_overlay.gd` `_step_geometry`消费；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`固定旧平滑方向错误及双向、微抖、瞬切反例；debug_state记录预测速度及反转次数。

远景交错查询复用：`rendering/tokyo_hlod_manifest.gd` `select` / `FRAME_SOLUTIONS`，`rendering/tokyo_hlod_native.gd` `select` / `read`，同帧有界多项纯值缓存；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`覆盖A→B→A、不同预算、容量、跨帧与read失效。无可见性跨帧复用。

失败切面空值合同：`rendering/tokyo_hlod_overlay.gd` `_select_hlod` / `_select_native`先保留空结果，再加诊断；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`覆盖超尺度失败不得变成伪切面。

显式跨资源请求优先级：`rendering/tokyo_hlod_stream.gd` `can_start_image` / `_step_textures`；`rendering/tokyo_hlod_overlay.gd` `_request_target`在预测追加前登记实际物理网格/图片；反例位于`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

显式最小网格进度：`rendering/tokyo_hlod_stream.gd` `_process_stream` / `summary`，开关`AGL_TOKYO_MESH_PROGRESS`；`tests/test_tokyo_hlod_stream.gd` `PipelineFixture` / `pipeline_checks`模拟重纹理帧并检查单项推进及宽度恢复。

显式缓存切面候选：`rendering/tokyo_hlod_cached_cut.gd` `select` / `_resident_tree`（缺资源哨兵、可见树、已有资源完整切面）；`rendering/tokyo_hlod_overlay.gd` `_step_geometry`在`AGL_TOKYO_CACHED_CUT=1`时接入，默认关闭。

交接空间门：`rendering/tokyo_hlod_overlay.gd` `_cut_covers_current_view` / `_target_covers_current_view` / `_commit_ready_target`；旧切面完整才可凭更高LOD上限拒绝仍合格的新切面。`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`提供旧边缘缺口反例。

当前纹理优先：`rendering/tokyo_hlod_stream.gd` `ordered_texture_jobs` / `_step_textures`（沿目标顺序上传，失效任务清理不占上传额度）；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`覆盖优先顺序与去重。

预取身份与缺口形状：`rendering/tokyo_hlod_handoff.gd` `prefetch_changed` / `uncovered_view`（归一化数组身份；保留真实缺口矩形以区分共边浮点误差）。

预测资源身份：`rendering/tokyo_hlod_overlay.gd:905 _predict_prefetch`（仅未绑定缓存候选，不放宽显示资格）。

| 文件 | 职责与入口 |
|---|---|
| `tests/tokyo_wasd_audit.gd:65 run` | 正式入口的真实 WASD/滚轮回放、逐绘制帧 alpha/几何覆盖、相机时序与预取命中诊断；读回样本不是性能验收 |
| `rendering/tokyo_hlod_handoff.gd:224 native_covers_view` | 第三层固定地表覆盖证明，不以低楼包络替代 |
| `rendering/tokyo_hlod_overlay.gd:657 _select_hlod` / `rendering/tokyo_hlod_overlay.gd:821 _select_native` | 移动提前范围与在途切面复用 |
| `rendering/tokyo_hlod_overlay.gd:1022 _target_covers_current_view` / `rendering/tokyo_hlod_overlay.gd:1138 _request_target` | 提交前重新证明空间覆盖；未绑定预取与显示切面分开计费 |

## 小队恐惧锥与受害者控制

| 文件 | 职责 | 入口 |
|---|---|---|
| `aircraft/fear_response.gd` | 来源安全采样、免疫先行裁决、远离来源、控制权、强制加力、读数策略 | `aircraft` `controlled` `eligible` `apply` `update` `enforce` `escape_point` `clear` `obscure` `seconds` |
| `survivor/squad_fear_cone_config.gd` | 小队可装配配置资源 | `valid` |
| `survivor/wraith_progression_loadout.gd` | 独立 Wraith 强化装配策略，输出本场专属恐惧配置；通用能力无生涯依赖 | `fear_cone_for_progression`；`survivor/f47_ace_squad.gd` `configure_progression` |
| `survivor/squad_fear_cone_controller.gd` | 弱宿主、选施放者、阶段、连续暴露、卸载清理与绘制登记 | `setup` `start` `update` `stop` `dispose` `emitter` `contains` `debug_cast` `live_controllers` `_notification` `_release_emitter` `_cooldown` `_visible_candidate` `_select` `_sample` |
| `survivor/ace_squad.gd` | 通用小队宿主适配；F47 配置首发 | `fear_enabled` `fear_members` `fear_targets` `engage` `update` |
| `ui/fear_readout_mask.gd` | 共用紫色占位遮蔽 | `draw` |
| `ui/world_unit_status_overlay.gd` | 批绘同判定参数的紫锥与暴露条 | `_draw` |
| `survivor/survivor_debug_skills.gd` | F4 目标/真实来源选择、施加/清除、一次正常紫锥 | `_build_fear_controls` `_refresh_fear_choices` `_debug_fear_action` |
| `tests/fear_cone_case.gd` / `tests/fear_cone_runner.gd` | 真实 SceneTree、物理、免疫与生命周期；fear_cone 及 all 入口 | `run` `_flight_and_edges` `_visual` `_aircraft` `_check` / `_ready` `_run` |
| `tests/fear_cone_performance.gd` | 同正式 C1/Wraith 负载，仅切换能力的 A/B；额外定时覆盖多人恐惧；不参与发布场景 | `start` `fear_members` `fear_targets` `fear_enabled` `_live` `_process` `summary` `capture` `_exit_tree`；`bench/bench_runner.gd` `_swap_to_fear_probe` |

东京湾系统记录对齐（R7）：`tests/tokyo_render_trace.gd` / `setup` 一次记录PID、UTC及单调时钟夹逼区间；`begin_frame` 慢帧保留原始阶段时间戳，`summary`输出锚点；不把异步GPU读回声称为同帧证据。`tests/test_perf_frame_trace.gd` / `_test_backend_peaks`覆盖锚点基本约束。

东京湾静态资格树复用（R7）：`rendering/tokyo_hlod_manifest.gd` / `qualified_roots` 只缓存同资源身份、左开右闭尺度区间内的纯值资格树；可见性仍每帧求解。`tests/test_tokyo_hlod_manifest.gd` / `checks` 覆盖阈值反向、身份失效、输入不变及不同相机/预算与旧算法逐项等价。

玩家HUD布局缓存：`survivor/player_instrument_panel.gd` / `_cached_text_layout` 保存不变字号基准，`_configure_layout` 清空256项有界缓存；`_draw_font_text_in_rect` 可选记录布局、实际基线及文字绘制子桶。`tests/test_player_instrument_hud.gd` / `_test_display_is_mouse_transparent` 覆盖等价、重建失效、尺寸与基准变化及容量。

FINAL WAR 双时钟验收：`tests/final_war_frame_probe.gd` / `_ready` / `_process` / `_bench_finish_now` / `_exit_tree`，继承真实 Survivor 场景，保留原编成；墙钟或引擎慢帧均返回失败。F5 坐标轴 owner 释放：`survivor/survivor_debug_spawn.gd` / `_exit_tree`；三条真实终态反例：`tests/debug_spawn_lifecycle_case.gd` / `run`，接入 `lifecycle_gauntlet_runner.gd`。

海洋事件驱动成员同步：`rendering/ocean_volume_ground.gd` / `sync` / `source_scans`只在owner版本变化时枚举；`tests/ocean_volume_lifecycle_case.gd` / `run`覆盖120稳定帧零快照、透明度与排序无需成员扫描、同帧退役重入一次扫描。默认禁用试验的热路径退出位于`rendering/ocean_volume_overlay.gd` / `_step_geometry`。

海洋覆盖抑制诊断（默认关闭）：`rendering/ocean_volume_overlay.gd` / `_set_raster_covered` / `_exit_tree`；真实菜单原生RGBA/MSAA对照：`tests/ocean_volume_visual.gd` / `_capture_msaa_pair`；可选GPU分桶：`tests/ocean_volume_combat.gd` / `_exit_tree`。正式路径保持4×MSAA，不以候选单轮通过宣称达标。

两图M20同标补验：`tests/map_lod_acceptance_probe.gd` / `run` / `_place` / `_sample`在正式菜单局检查40边缘视图、实际滚轮和逐帧桥接；`tests/map_frame_clock.gd` / `observe` / `report`提供独立墙钟门与有界慢帧记录；`tests/ocean_volume_lifecycle_runner.gd` / `_ready`复用终态反例（bench `ocean_volume_lifecycle`）。`survivor/raster_basemap_renderer.gd`的`presentation_revision` / `presentation_tile_retiring`驱动`rendering/ocean_volume_ground.gd` / `_on_tile_retiring` / `clear` / `_exit_tree`，保持同步退役与目标层排序；`tests/ocean_volume_combat.gd`追加`ocean_volume_c2` 48成员24km及`_process`墙钟采样，`tests/volume_map_performance.gd` / `_process`同口径记录沙漠。

M20无I/O旧页收缩：`rendering/tokyo_hlod_manifest.gd` / `visible_subset`只裁投影离屏旧页；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`下一帧继续预取；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`核原资源子集与楼体投影保留。

M20有界图片流水线：`rendering/tokyo_hlod_stream.gd` / `can_upload_texture` / `_step_textures`区分小图双份与大图单份；`tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks`验数量/尺寸/耗时门与四路I/O。

M20有界交接：`rendering/tokyo_hlod_handoff.gd` / `display_grace`纯值时间/空间/倍率门；`rendering/tokyo_hlod_overlay.gd` / `_update_display_grace` / `_record_display_grace`只保留已显示HLOD并独立计数，不放宽新档提交。

M20缩放抖动过滤：`rendering/tokyo_hlod_handoff.gd` / `zoom_direction`；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`保留最后有效方向，仅真实反向绕过选档节拍。

M20交接排序：`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`在联合预算不足时，先试具备当前空间覆盖证明的新档到期尺度预取，再试旧档缩块；提交资格、同池预算与M18空间门保持不变。实际回归用north快速输入48秒/20Hz/36演员与六区域路线，不用静止图替代。

M20 LOD策略保真：`tools/verify_tokyo_lod_policy.py` / `policy` / `verify`在补资源时独立比较所有非实物绑定字段，并拒绝选择区间重叠/缺口及非法近景偏好。资源支持范围不得替代包选择范围。`tests/tokyo_hlod_route_probe.gd` / `patrol`显式HANDOFF_TRACE记录最多60个交接快照，默认无诊断记录。

M20安装验收隔离：`tests/tokyo_cells_preload_case.gd` / `run`及`tests/tokyo_preload_lifecycle_case.gd` / `run`隔离并恢复HLOD覆盖环境，旧cells夹具不能误取HLOD节点。`tests/tokyo_hlod_route_probe.gd` / `play_session`增加真实北边、东边、东北角输入锚点并记录区域身份，保留36演员、正常相机输入与隐藏帧硬门。

M20内部子树复用：`tests/build_tokyo_boundary_tree.gd` / `assemble` 只重建边缘及祖先的71/123节点，未变节点沿用正式组件与逻辑身份；`collect`收集277个节点；`audit_tokyo_boundary_coverage.gd` / `verify` 仍遍历4432身份并重验496边缘叶，只在变更接合处加载未改子树。`tests/package_tokyo_installed.gd` / `run`支持显式安装版本；`tools/install_tokyo_playable.py` / `source_path`解析受限res来源，`--version`安装到独立子目录，不自动启用。

M20统一范围与增量凭据：`rendering/tokyo_boundary_extent.gd` / `bounds` / `page_bounds` / `full_grid` / `checks`限定已核来源版本，内部切线不变；`tokyo_full_grid_contract.gd` / `metadata_valid`保留旧包兼容，`tokyo_canonical_catalog.gd` / `presentation_archive`取已验证范围。`tokyo_hlod_manifest.gd` / `row_valid` / `normalize`与`tokyo_hlod_overlay.gd` / `_load_archive`拒绝近远混范围。`tests/build_tokyo_hlod_native_pages.gd` / `run`允许摘要完全一致的283内部页复用，53边界页重新保存。`tests/build_tokyo_boundary_catalog.gd` / `paths` / `read_value` / `run`汇总77增量根；`tests/audit_tokyo_boundary_coverage.gd` / `verify` / `token` / `run`独立重载内部叶逐角、边界无正式楼、祖先三层守恒，再迁移凭据并验189源完整切面。

M20真实边界制作：`tests/export_tokyo_boundary_layers.gd` / `run`绑定31片家族/来源/原生摘要并复用三层导出；`tests/build_tokyo_boundary_blocks.gd` / `run`绑定独立块面审计后复用七档保存器；`tests/export_tokyo_full_grid_layout.gd` / `run`支持显式BOUNDARY_LAYOUT，只改北排/东列外界。`tests/build_tokyo_boundary_tree.gd` / `collect` / `meshes` / `run`保留正式内部组件，边界必须不触碰正式楼，复用277节点组件树保存。显式制作入口在`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`；空入口拒绝由`tests/test_rail_obstacle_export.gd` / `checks`接入focused/all。不代表已安装或Visual通过。

M18预取空间门：`rendering/tokyo_hlod_handoff.gd` / `anticipation_scale` 将未来窄视野预取绑定到旧页实际覆盖；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`调用。`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖半屏、离屏、完整覆盖的预取尺度反例。`tests/tokyo_hlod_edge_audit.gd` / `run`追加目标资格/计费/缺资源快照；`tests/tokyo_volume_combat_runner.gd` / `_bench_finish_now`将实际HLOD默认入口也纳入隐藏帧报告。激进暂留释放试验已撤回，不保留can_stage函数。

M17全边缘验收：`tests/tokyo_hlod_edge_audit.gd` / `alpha_coverage` / `run`，通过显式EDGE_AUDIT沿正式Loading入口检查四边、四角、四缩放及三长宽比的完整RGBA与实际相机范围；`tests/tokyo_hlod_route_probe.gd` / `run`汇总失败并退出释放。`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证单像素透明与alpha阈值反例；不修改生产边界或地图。

M15上传粒度：`rendering/tokyo_hlod_manifest.gd` / `split_large_uploads` / `select` 在合格预算切面内完整替换大纹理父页；`rendering/tokyo_hlod_overlay.gd` / `_select_hlod` 仅显式SMALL_UPLOADS接入。`rendering/tokyo_volume_preload.gd` / `start` / `take` / `_begin`冻结其身份；`rendering/tokyo_hlod_stream.gd` / `_audit_texture` / `summary`诊断资源请求、上传与实际退役；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖计费、面数、页数、资格哨兵、输出独立与诊断开关。

M14 HLOD主路径：`rendering/tokyo_hlod_overlay.gd` / `_select_hlod` 将实例内单份工作缓存交给 `rendering/tokyo_hlod_manifest.gd` / `select`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks` 比较三预算原结果与缓存结果、身份快照和提前模式失效。

M14等价CPU优化：`experiments/tokyo_spatial_cut.gd` / `solve` / `pick` / `choose` 分离完整候选生成与预算筛选；`rendering/tokyo_hlod_native.gd` / `select` / `read` 仅同帧同视野复用一个纯值候选；`rendering/tokyo_hlod_overlay.gd` / `debug_state` 输出生成/复用次数。`rendering/tokyo_component_stream.gd` / `_paths` 与overlay的 `_request_target` 以集合去重保持顺序；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks` 覆盖共享顺序、双预算不同完整切面、输出独立及各键失效。

M13 Loading常驻候选：`rendering/tokyo_hlod_stream.gd` / `configure_residency` / `geometry_budget` / `residency_ready` 管理显式384MiB池及固定集；`rendering/tokyo_volume_preload.gd` / `state_ready` 等待常驻完成，默认96MiB不变。`tests/tokyo_map_residency_probe.gd` / `costs` / `counters` / `loaded` / `trial` / `run` 与测试子类 `TrialStream.geometry_budget` 测实际资源、去重计费、保持和释放。`tests/tokyo_hlod_route_probe.gd` / `play_session` 记录载入用时和实验池超额。用户试玩入口 `play_preloaded_map.cmd`；不自动启用候选。

M12完整目标预退役：`rendering/tokyo_hlod_stream.gd` / `prepare_target_space`在`request_textures`更新完整目标后安排无用缓存退役，仍保留两帧计费；`tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks`覆盖满池两份退役但不提前退款。`rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_commit_ready_target`先计算缩放方向，反向放大时拒绝更低资格的降档提交；`commit_ready_checks`有自动反例。

M12空间/缩远交接：`rendering/tokyo_hlod_handoff.gd` / `covers_view`以矩形相减证明旧页覆盖；`catalog_index`接受缩远关闭提前细目录参数；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`解除不完整旧页的预算死等。`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖中间孤岛、缺半屏和完整拼接，`run`覆盖双向选档。`tests/tokyo_hlod_route_probe.gd` / `play_session`显式SETTLED_CAPTURE在测量结束后等待并输出实际切面、合成图和native图，超时不ready失败。

M11交接与预算：`rendering/tokyo_hlod_handoff.gd` / `loading_configuration` / `native_preference` / `scale_limit`；`rendering/tokyo_hlod_manifest.gd` / `retained`与`select`共用提前资格；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`准备边界窄视野，`_commit_ready_target`重验真实视野覆盖。`rendering/tokyo_cell_stream.gd` / `_collect_completed`累计逐帧领取预算，`rendering/tokyo_hlod_stream.gd` / `collect_ready_meshes`仅收已完成资源，`_step_textures`填满原两条Image后台通道。

M11回归与诊断：`tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks` / `handoff_budget_probe` / `pipeline_checks` / `commit_ready_checks`覆盖真实双Image、逐帧领取、预测覆盖及联合预算。两份Image夹具为`resources/maps/tokyo_volume_preview/hlod_stream_fixture.tres`和`hlod_stream_fixture_pair.tres`。`tests/tokyo_volume_combat_runner.gd` / `_ready`仅显式DIAGNOSTIC_VSYNC临时关闭测试同步；`tests/tokyo_render_trace.gd` / `_after_draw` / `summary`记录post_draw间隔；不改变正式默认设置。

M10完整目标先提交：`rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_commit_ready_target`在重选前及帧末尝试同一完整性/尺度检查，成功提交同步合成可见性与旧楼覆盖；`tests/test_tokyo_hlod_stream.gd` / `CommitStream` / `CommitOverlay` / `commit_ready_checks`覆盖缺纹理、过期、可见性恢复与重复提交。`tests/tokyo_hlod_route_probe.gd` / `play_session`显式HANDOFF_TRACE的40份有界快照包含目标/缓存/在途/退役纹理路径，不进入常规性能采样。

M9取消后重载校验 → `tests/test_tokyo_hlod_stream.gd` / `checksum_reload_checks`，使用真实Image异步请求验证新请求不能复用被取消旧请求的摘要；`pipeline_checks`同时覆盖2/8槽及取消释放。`tests/tokyo_hlod_route_probe.gd` / `play_session`显式REPLAY_COMBAT复用36成员混合战场，INPUT_REGION提供north默认/highrise/west，记录演员与炮弹/落点实际激活，不代替完整任务局。

## 血色骑士

| 文件 | 职责 | 入口 |
|---|---|---|
| `survivor/skill_hooks.gd` | 飞机致死前嗜血转换资格，击杀时永久成长与恐惧消费者 | `bloodlust_counts_as_head_on` / `dispatch_on_kill` |
| `tests/bloodlust_head_on_case.gd` | 真实伤害、24 个跨帧终态案例、F4/来源/切控与重放目录审计；all 生命周期复用 | `run` / `_test_catalog` / `_air_case` / `_surface_case` / `_aircraft` / `_check` |
| `tests/bloodlust_head_on_runner.gd` | focused SceneTree 入口 | `_ready` / `_run` |
| `tests/bloodlust_head_on_performance.gd` | C1 原混合战场每秒追加两次真实致死，A/B 只切技能；保存转换/恐惧/成长覆盖与截图 | `start` / `summary` / `coverage_ok` / `capture` |
| `bench/bench_runner.gd` | `bloodlust_head_on` 与 C1 成对场景注册 | `_swap_to_bloodlust_c1` / `bench_finish` |

M9低帧率流送诊断：`tests/tokyo_hlod_route_probe.gd` / `play_session`显式REPLAY_FPS只限制输入专项进程，不作性能证据；`rendering/tokyo_hlod_stream.gd` / `_request_load` / `checksum_after_load`等待后台加载状态后立即校验，主线程仍唯一领取，`_load_status`与硬退出清理复用原流程。

东京后台校验与退出兜底：`rendering/tokyo_hlod_stream.gd` / `checksum_file` / `_load_status` / `_matches` / `_exit_tree`在资源加载完成后后台校验SHA，未完成不ready；`rendering/tokyo_cell_stream.gd` / `_exit_tree`终止节点时领取引擎请求并归还槽；`tests/test_tokyo_hlod_stream.gd` / `shutdown_checks`覆盖没有后续帧的自有线程退出。`rendering/tokyo_hlod_overlay.gd`的`_step_geometry`按20Hz常规/最多60Hz快速缩放选页。

东京有界流水线回归：`tests/test_tokyo_hlod_stream.gd` / `PipelineFixture` / `pipeline_checks`覆盖真实父级2/8槽预约、领取与在途取消释放；I/O替身不作GPU性能证据。`rendering/tokyo_cell_stream.gd` / `_process_stream`按实例宽度与领取耗时限制推进，HLOD Visual由`rendering/tokyo_hlod_stream.gd` / `configure_hlod`启用8共享请求槽、2纹理worker及单帧1份纹理上传；普通流送请求上限2、领取宽度1，Headless原路径不变。

M8正常滚轮交接：`rendering/tokyo_hlod_manifest.gd` / `PREFETCH_RATIO` / `select` / `retained`共用提前资格及可选选页预算；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`优先预留半池、联合预算重选及合格旧页等待；`tests/tokyo_hlod_route_probe.gd` / `play_session`提供10/20Hz正常相机输入回放、覆盖门与有界隐藏区间，预览负载不冒充实战。

东京湾正式安装路由：`rendering/tokyo_installed_map.gd:5 package_path` / `rendering/tokyo_installed_map.gd:15 package_sha`，由原 `tokyo_volume_preload` 和 `tokyo_hlod_overlay` 共同消费；`tests/test_tokyo_hlod_stream.gd:2035 installed_route_checks` 校验显式候选优先与关闭回退。正常手动启动入口 `play_installed.cmd`，没有 bench 或时限。

当前低楼实物合并与安装：`tests/tokyo_solid_native_mesh.gd:27 merge_mesh` / `tests/tokyo_solid_native_mesh.gd:11 checks` 只替换完整连通体；`tests/build_tokyo_solid_native.gd:9 bind` / `tests/build_tokyo_solid_native.gd:12 write_values` / `tests/build_tokyo_solid_native.gd:17 refresh` / `tests/build_tokyo_solid_native.gd:29 run` / `tests/build_tokyo_solid_native.gd:114 collect` 更新物理组件与目录。`tests/package_tokyo_installed.gd:8 binding` / `tests/package_tokyo_installed.gd:11 run` 可逆迁址并重绑覆盖页摘要；`tools/install_tokyo_playable.py` 的 CLI 接 project/package/stage，逐摘要复制、不覆盖异内容。

近景整街坊候选：`tools/build_tokyo_block_lod.py` / `prepare` / `choose`复用road_components及结构障碍，显式street_solid；`tests/build_tokyo_far_clusters.gd` / `group_limit`核验配方；`tools/test_tokyo_block_lod.py` / `test_solid_street_preserves_anchors_and_source`及`tests/test_tokyo_far_clusters.gd`验证保护门与JSON合同。旧配方保持，未默认安装。

不透明图页无重压缩转存：`tests/build_tokyo_hlod_opaque.gd` / `color_blocks` / `opaque_image` / `checks` / `run`逐mip核验BC1/BC3解码一致；`rendering/tokyo_hlod_stream.gd` / `should_defer_mesh_finalize`错开重纹理上传与网格领取，关闭时不延迟。`tests/tokyo_hlod_manifest_audit.gd` / `run`支持native_only及诊断档覆盖；`rendering/tokyo_hlod_native.gd` / `select`可显式诊断configuration_override，运行时默认仍正常档。`rendering/tokyo_hlod_overlay.gd` / `_load_archive` / `_step_geometry`校验并消费prefer_native_above，近景预算内保留原生高楼。

正常局制作包试玩：`tests/tokyo_hlod_route_probe.gd` / `run` / `play_session`显式PLAY_SECONDS走非预览Survivor，记录加载身份、玩家位移、墙钟/非暂停时间、实际地图隐藏/超预算帧和退出释放；不自动选升级，不伪称人工完整局。`tests/tokyo_render_trace.gd` / `begin_frame`仅在显式诊断的慢帧保存同期CPU桶/事件，沿原top32有界记录，不改运行时负载。`tests/tokyo_volume_combat_runner.gd` / `_process` / `_bench_finish_now`另提供WALL_TRACE无渲染信号快照；`rendering/tokyo_hlod_stream.gd` / `_step_textures` / `_matches`及`rendering/tokyo_cell_stream.gd` / `_process_stream`记录流送上传/摘要/领取子桶。

首次飞机淡出暖绘：`experiments/volume_material_warmup.gd` / `configure_instanced`复用原32×32两帧暖绘，提交真实MultiMesh/custom_data三材质；`experiments/volume_world_probe.gd` / `setup`接prewarm_catalog，`_on_material_warmup_finished`保存纯值结果。无新增常驻tick，Headless跳过和取消释放沿原生命周期。

HLOD/原生同池暂留：`rendering/tokyo_hlod_handoff.gd` / `catalog_index` / `native_qualified` / `streaming_bytes` / `combined_bytes` / `qualified`逐物理身份去重计费、提前选细目录及素材资格；`rendering/tokyo_hlod_overlay.gd` / `_committed_qualified` / `_handoff_bytes` / `_target_committed` / `_request_target`在新资源就绪前pins旧显示，完整目标ready与旧画面显示分开。`tests/tokyo_volume_combat_runner.gd` / `_process` / `_bench_finish_now`记录实际HLOD隐藏/等待/超预算帧，`max_transition_triangles`只统计真实提交网格。`rendering/tokyo_hlod_manifest.gd` / `select`显式allow_finer同时提前内部混合精度页；`tests/tokyo_hlod_route_probe.gd` / `patrol`总览及最近尺度巡航均进入报告硬门。

中景与合并街坊颜色同源：`tests/export_tokyo_massing_color.gd` / `run`只读导出真实catalog的16根两槽，复用`tokyo_residential_preview.gd` / `export_attributes`；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式MASSING_COLOR_SOURCE入口。逐页分辨率资格：`rendering/tokyo_hlod_manifest.gd` / `qualified_tree` / `select` / `retained`，低精父页不借更细目录资格；`tests/test_tokyo_hlod_manifest.gd` / `checks`覆盖父页禁止、完整叶切面、非法资格。`tests/build_tokyo_hlod_native_pages.gd` / `run`在geometry reuse时可核对复用父图，叶纹理重打包。

近景同池桥接：`rendering/tokyo_hlod_native.gd` / `read` / `select` / `covered`校验完整catalog/组件/11档覆盖，沿正式投影求完整预算切面；`rendering/tokyo_hlod_surface.gd` / `native_code`在顶点插值前复用旧Palette；HLOD Stream继承ComponentStream，无第二预算池。`tests/tokyo_near_component_audit.gd` / `run`显式COMPARE_LEVELS仅比较旧档成本，不授予跨档资格。

HLOD纯纹理生产：`tests/build_tokyo_hlod_native_pages.gd` / `reuse_geometry`逐页核旧几何/UV/来源、实际Component身份/字节/面数，复用原网格路径，仅压缩并保存新纹理；由GEOMETRY_REUSE显式选择，原生加载器默认不改。

源色板恢复：`tools/restore_tokyo_hlod_palette.py` / `main` / `remap` / `compose` / `checked` / `binding`复用全图未滤波缓存，逐像素复算旧图后在AO前恢复既有Palette，不重建几何；`tools/test_restore_tokyo_hlod_palette.py`覆盖非精确颜色/透明样本保留、不可变输入、重复映射及AO顺序。路径相对scripts。

美术谱系审计：`tools/audit_tokyo_art_lineage.py` / `main` / `roof_colors` / `digest`冻结用户颜色/R3风格/R154造型三类图片摘要，并只读抽查三片向上屋顶旧色板映射是否带入；`tools/test_tokyo_art_lineage.py`覆盖侧墙/底面排除及源载荷不变。此处路径相对scripts，不改运行时。

HLOD重复底色纠偏：`rendering/tokyo_hlod_surface.gd` / `shader_code`仅派生东京湾HLOD材质，默认不重复乘底色，legacy_tint供同场景A/B；`tests/tokyo_hlod_route_probe.gd` / `run`显式COLOR_REVIEW保留两个正常尺度的前后图，不替代全路线。

空子树漏画修复：`experiments/tokyo_spatial_cut.gd` / `_frontier`与`experiments/tokyo_spatial_select.gd` / `choose`只拆非空children；`tests/test_tokyo_hierarchical_pages.gd` / `_test_solver`验证显式空数组叶、嵌套叶和画外叶。`tests/tokyo_near_component_audit.gd` / `run`读取已完成组件树，先跑该反例再按玩家正常视图核原生/guarded档预算，经lifecycle runner显式NEAR_COMPONENT_AUDIT入口。不创建新目录或几何、不授予正式覆盖。

HLOD玩家尺度验收：`tests/tokyo_hlod_gameplay_views.gd` / `poses` / `checks`从CameraController正常范围与出生位置派生八幅视图；`tests/tokyo_hlod_route_probe.gd` / `run`未支持尺度判失败且不保存陈旧原生视口，`patrol`使用正常范围；`tests/test_tokyo_hlod_stream.gd` / `run`接范围反例。纯值helper不引用Loading节点，旧六幅超范围制作尺度不得充当玩家验收。

HLOD预算内闲置复用：`rendering/tokyo_hlod_stream.gd` / `configure_hlod` / `_prune` / `reserve_auxiliary`沿原共享计费计划退役闲置纹理，实际两帧后释放；`tests/test_tokyo_hlod_stream.gd` / `cache_checks`验证复用、pins、预算等待和退出。M8桥接修复后HLOD默认启用，AGL_TOKYO_RETAIN_UNUSED=0显式关闭；非HLOD默认不变，早期退化记录留在工程审计。`tests/tokyo_hlod_route_probe.gd` / `patrol`可关闭截图读回，记录帧间隔与选择/绑定/上传累计时间；`rendering/tokyo_hlod_overlay.gd` / `debug_state`明确实际输出像素尺度。

HLOD同档完整切面保留：`rendering/tokyo_hlod_manifest.gd` / `retained` / `covered_key`沿原求解结果与清单父子关系证明整页覆盖/资格/预算，`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`保留合格已载或在途切面，记录retained_cuts；`tests/test_tokyo_hlod_manifest.gd` / `checks`有效切面、未知页/过尺度/父子缺口反例。

HLOD正式候选视口：`rendering/tokyo_hlod_overlay.gd` / `_load_archive` / `_setup_geometry` / `_step_geometry` / `_bind_target` / `_clear_current` / `bind_legacy` / `_sync_legacy` / `_deactivate` / `_exit_tree` / `debug_state`，Layout.valid；继承原投影/合成并接共享Stream，整图包绑定、实际覆盖、2D回退。`tests/tokyo_hlod_route_probe.gd` / `run` / `patrol`沿正式Loading→Survivor预览六位置、12秒连续巡航及菜单释放，显式MANUAL_SECONDS最多180秒手动检查；`rendering/tokyo_volume_preload.gd` / `script_path` / `start` / `take` / `_begin`冻结HLOD package身份，加载舞台预热合格尺度，不改正式出生镜头。

HLOD实际正式楼领取门：`rendering/tokyo_hlod_coverage.gd` / `bind` / `read` / `matches`绑定完整336页凭据及game/collision，按实际正式槽索引展开float32位置核摘要；`rendering/tokyo_hlod_stream.gd` / `_matches`接原领取门。`rendering/tokyo_volume_preload.gd` / `state_ready`拒绝贴图在途/失败；`tests/test_tokyo_hlod_coverage.gd` / `checks`反例，regional与cells生命周期接入。

HLOD正式加载纯值合同：`rendering/tokyo_hlod_manifest.gd` / `integer` / `sha` / `numbers` / `binding` / `same_numbers` / `texture_valid` / `row_valid` / `normalize` / `tree` / `charges` / `select` / `read`；验证336页完整树、189来源跨深度/父子一致、mip和物理身份，转换原Stream网格描述符及独立纹理租约，沿原SpatialCut真实投影求解。`tests/test_tokyo_hlod_manifest.gd` / `fixture` / `checks`覆盖JSON往返/漂移/缺页/去重；`tests/tokyo_hlod_manifest_audit.gd` / `run`读取实际五套目录和原机位执行求解。无新tick、GPU载入或旧2D隐藏。

HLOD原生页制作对拍：`tests/tokyo_hlod_pages_review.gd` / `valid_pose` / `add_page` / `capture` / `run`；绑定实际组件/纹理，同1600×900机位/切面输出RGBA与BC3及完整墙/低墙参考，记录实际图元、计账及跨帧弱引用释放。不接管正式局，不作完整覆盖/性能证明。

整图HLOD原生页：`tests/build_tokyo_hlod_native_pages.gd` / `valid_input` / `build_mesh` / `reuse_texture` / `checks` / `run`校验336页身份集合，重索引及组件保存回读、原样mip的S3TC/纯色块校正与解码导出；显式TEXTURE_REUSE绑定旧纹理，逐页核mip/UV/摘要与原生解码，不重复压缩。lifecycle runner显式HLOD_NATIVE_PAGES入口；regional focused/all包含空输入、缺页、零网格和错误纹理反例。独立新表示，不授予旧coverage或正式接管身份。

整图最远景制作检查：`tests/tokyo_overview_hlod_review.gd` / `binding` / `material` / `triangle_mesh` / `add_mesh` / `checks` / `run`读取真实高度块面与完整纹理mip，沿正式投影/shader输出四幅整图原生预览及跨帧释放结果；lifecycle runner显式OVERVIEW_HLOD_REVIEW入口，regional focused/all验证空绑定拒绝和保存位置/正面法线/全图UV。仅制作预览，不接管正式地图或充当实战验收。

新固定树与复用重绑：`tests/build_tokyo_semantic_fixed_tree.gd` / `route_valid` / `checks` / `run`复核原叶保留顺序、原生分桶和277固定组件保存；`tests/rebind_tokyo_semantic_fixed_tree.gd` / `entry` / `checks` / `run`只改固定引用和逻辑身份，逐文件核建筑SHA且不改其几何。lifecycle runner显式SEMANTIC_FIXED_TREE/REBIND入口，regional focused/all覆盖错叶/重复删除/旧元数据及建筑来源不变。

语义铁路整图原生删除：`tests/bake_tokyo_semantic_rail_roots.gd` / `record` / `select` / `filtered` / `checks` / `run`按完整角点记录及重复重数匹配，仅删原索引、保存后核其余packed通道不变；独立新资源，未重绑目录或安装。lifecycle runner显式SEMANTIC_RAIL_ROOT入口，regional focused/all含重复面/非轨道/非法面序反例。

完整交互输入认证：`tests/tokyo_interaction_certificate.gd` / `matches` / `certified` / `checks`绑定原候选和选择证明，认证字段可逆且其余值完全相等；`tests/bake_tokyo_full_grid_configuration.gd` / `valid`仅在此认证通过后接受局部精細格完整输入，保留16根/32层/189楼门。不是11档实际保存或安装证明。

交互屋顶落盘诊断：`tests/bake_tokyo_interaction_probe.gd` / `run`绑定独立选择证明与完整源摘要，限定partial、189楼、16根/32层和局部可表示包络，复用Baker/Audit保存与未改数组校验；lifecycle runner显式INTERACTION_PROBE。`tools/build_tokyo_spatial_roof_plan.py` / `ownership`、`tools/audit_tokyo_shared_roofs.py` / `audit`对显式interaction_scope使用精确float32高度语义，旧局部默认不变；空间归属测试含1ULP反例。

Loading完整包身份：`rendering/tokyo_volume_preload.gd` / `start` / `_begin` / `take`冻结规范目录与coverage前缀，变化则释放旧预载；`tests/tokyo_preload_lifecycle_case.gd` / `_catalog_identity`经真实延期开始、原生预热和交接跨帧核释放。相同身份的原有实例复用测试继续保留。

整图实际审图：`tests/tokyo_full_grid_review.gd` / `poses` / `checks` / `run`生成16根、24根共边及总览121机位，显式FULL_GRID_REVIEW经`tests/tokyo_preload_route_probe.gd` / `run`执行；`tests/test_tokyo_regional_native.gd` / `run`核机位覆盖。仅真实画面采集，非实战性能通过。

R370可移植候选：`tests/tokyo_portable_paths.gd` / `rewrite` / `reversible` / `checks` / `full_grid_checks`一对一迁移完整层级与coverage叶token；`tests/build_tokyo_portable_package.gd` / `read_values` / `save_values` / `run`绑定11配置实物coverage、迁址Catalog/组件/覆盖元数据并输出拷贝清单。`tools/install_tokyo_portable_package.py` / `digest` / `child` / `copy_exact` / `install`离线独占bench锁、容量与边界检查、逐文件摘要拷贝且拒绝覆盖异内容；`tools/test_install_tokyo_portable_package.py`为复制/复用/失败保留反例。`tests/verify_tokyo_portable_package.gd` / `run`从项目新路径逐组件加载核对，lifecycle runner提供PORTABLE_INPUT/VERIFY入口；不自行开默认或授予Visual/性能准入。

R369完整目录/覆盖：`tests/build_tokyo_full_grid_catalog.gd` / `run`汇总16根×11配置；`rendering/tokyo_component_page.gd` / `assemble`供ComponentStream.resource及离线共同装配。`tests/build_tokyo_source_coverage.gd` / `_fixed_sha` / `_page_sha` / `_read_page`保留旧读法；`tests/build_tokyo_full_source_coverage.gd` / `run` / `_fixed_sha` / `_page_sha` / `_read_page` / `_audit_cuts`读取真实组件并复用逐面门、补四深度切面。`tests/test_tokyo_component_page.gd` / `checks` / `_coverage_page`验证释放对象/错误映射和完整层级切面；lifecycle runner提供FULL_CATALOG/FULL_COVERAGE入口。

R368实际三层分页：`tests/bake_tokyo_full_grid_configuration.gd` / `valid` / `run`对完整单配置复用Baker/Audit；`tests/build_tokyo_full_grid_root_pages.gd` / `fixed_routes` / `compose` / `run`沿原叶接合原生、固定、正式建筑补面并调用组件树。`tests/test_tokyo_full_root_page_join.gd` / `checks`覆盖完整来源门、重复身份、缺路由及三层归属守恒，经regional focused/all；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`提供FULL_CONFIG_ROOFS和FULL_ROOT_PAGES有界入口。

R367完整组件树：`tests/build_tokyo_full_component_tree.gd` / `build` / `emit`把256原叶三层几何合成277节点，保存独立组件与schema2逻辑身份，共享固定层，不重复页网格归档；`tests/test_tokyo_full_component_tree.gd` / `run`验证完整层级、保存回读、两档固定共享和缺叶拒绝，`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`提供FULL_COMPONENT_TREE_TEST有界入口。组件树不等于coverage或全图安装。

R366整图同高归属：`tools/build_tokyo_spatial_roof_plan.py` / `ownership`仅对FULL_GRID按float32编码匹配同高屋面，保留原高度摘要与排序；`tools/test_tokyo_spatial_roof_plan.py`覆盖真实小数高度、1ULP拒绝和旧局部语义。

R365原叶分包：`experiments/tokyo_spatial_split.gd` / `partition`接受显式原叶桶号，`split`保留原四分切线语义；`tests/build_tokyo_full_native_leaves.gd` / `conserved` / `run`逐角核对并保存原生子组件。`tests/test_tokyo_full_native_leaves.gd` / `checks`覆盖256桶/空叶/错路由与旧四分等价，接regional focused/all；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式FULL_NATIVE_LEAVES分派。不含固定地表或游戏补面。

R364全图屋面float32修正：`tools/build_tokyo_shared_roofs.py` / `build`显式grid参数保留旧默认，`tools/build_tokyo_canonical_roofs.py` / `generate`消费shared_grid；位移/覆盖/重叠门不变。`tests/audit_tokyo_full_root_roof_precision.gd` / `run`为绑定单根计划复用既有Baker/Audit，`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式ROOT_ROOF_PRECISION分派，非法入口接regional focused/all。

R363整图游戏屋面：`tests/export_tokyo_full_root_roofs.gd` / `expected_sources` / `run`绑定完整根并保留正式189楼身份/轮廓/高度，复用既有_extract。`tests/test_tokyo_full_root_roofs.gd` / `checks`验证真实来源与缺项/摘要漂移拒绝，接regional focused/all；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式FULL_ROOT_ROOFS入口。单根仍partial，不能提前隐藏2D。

R362整图根接合：`tests/build_tokyo_full_grid_root.gd` / `selection` / `binding_valid` / `joined_exact` / `run`绑定16片成品及精确布局，复用packed合并并独立逐通道/重基索引核对、保存回读，保留256原叶的连续来源范围。`tests/test_tokyo_full_grid_root.gd` / `triangle` / `checks`覆盖档位、空层、索引/非索引及位置/颜色损坏，进入regional focused/all。`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式FULL_ROOT_INPUT分派；仅原生输入，不是正式全图目录。

R361全图目录格式：`rendering/tokyo_full_grid_contract.gd` / `digest` / `metadata_valid` / `coordinates_valid` / `children` / `valid` / `entry_valid`约束4432节点×11配置。`rendering/tokyo_canonical_catalog.gd` / `valid` / `extension_valid` / `presentation_archive` / `pages_per_configuration` / `gameplay_source_count`分离新旧格式；`rendering/tokyo_canonical_spatial_page.gd` / `valid`和`rendering/tokyo_component_stream.gd` / `resource`传递schema；`rendering/tokyo_component_manifest.gd` / `complete_coverage`、`rendering/tokyo_canonical_overlay.gd` / `_load_archive`使用版本化页数/游戏源数。`tests/test_tokyo_full_grid_contract.gd` / `metadata` / `entry` / `checks`验证完整格式、缺页、身份、预算字节类型与旧格式隔离，经`tests/test_tokyo_regional_native.gd` / `run`进入focused/all。不是全图实装或Visual证明。

R360整图接合布局：`tests/export_tokyo_full_grid_layout.gd` / `run`读取256份原生索引并保存精确Variant二进制/JSON浏览副本，`partition_valid`验证已有4096自适应单元，`rectangle`全精度数值导出；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式FULL_GRID_LAYOUT_OUT分派。`tests/test_tokyo_residential_selection.gd` / `checks`覆盖重叠、越界、缺口与精度回读。无重新切楼、无新增运行时tick。

三图Dummy纹理RID兼容 → `survivor/raster_basemap_renderer.gd` / `_request_target_tiles` / `_poll_pending` / `debug_state`，无头导入纹理主线程隔帧领取，GL仍后台；`tests/raster_capacity_lifecycle_case.gd` / `_map_case`核后端、同帧延后、2绑定限额及在途退出。

全图类别地表技术对照 → `tests/tokyo_indexed_fixed_review.gd` / `run`；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式INDEXED_FIXED_REVIEW入口，固定原生源、三步长/两旋转同机位GL对拍，不改变正式默认。

空层导出及无可合并分片 → `tests/tokyo_residential_preview.gd` / `export_payload`、`export_kept`、`export_attributes`；`tests/build_tokyo_northwest_blocks.gd` / `valid_passthrough`、`build_verified`；纯输入反例由`tests/test_tokyo_residential_selection.gd` / `checks`覆盖，合法空层保留真实零字节摘要，无替代块则保持原网格。

旧底图预热去重 → `survivor/map_vector_preview_renderer.gd` / `_build_packet_definitions` / `_add_polygon`复用柔化合法性检查已有三角化；`tests/test_map_vector_preview.gd` / `run`核直接路径/复用路径packet字节一致，不改变1.60s预热门。

已认可块面批量移入owner → `tests/transfer_tokyo_full_tile_blocks.gd` / `run`绑定联合原生证明和块面候选；复用`tests/build_tokyo_owned_region_blocks.gd` / `transfer`，显式逐格再分配但按区域各档不增；BATCH入口在`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。

全图有限归属批次 → `tests/build_tokyo_regional_native.gd` / `batch_regions` / `read_batch` / `run`沿完整登记选择子集，原owner与路由不变；`tests/audit_tokyo_regional_native.gd` / `run`独立检查同批次，局部只写batch专用证明以隔离正式目录；反例在`tests/test_tokyo_regional_native.gd` / `run`。

全图空楼体分区 → `rendering/tokyo_cell_index.gd` / `valid`显式surface_only与零建筑计账；`tests/build_tokyo_cells.gd`沿原构建器设置；反例在`tests/test_tokyo_cells.gd` / `run`，不新增运行时加载器。

全图块面七档 → `tests/build_tokyo_full_tile_blocks.gd` / `run` 绑定家族/跨格/原生与独立轮廓审计，复用 `tests/build_tokyo_batch_blocks.gd` / `build_paths` 的整层矩阵和逐格守恒；入口仍是 `tokyo_cells_lifecycle_runner.gd` / `_ready` 的BATCH_BLOCKS。来源图别名解析 → `tools/build_tokyo_region_ownership.py` / `connected_components`；原字段不改，仅缺失引用解析唯一别名，规范ID优先；反例在 `tools/test_tokyo_region_ownership.py`。

全图清单导出 → `tests/export_tokyo_batch_layers.gd` / `run` 沿原BATCH_LAYERS入口分派到 `tests/export_tokyo_full_tile_layers.gd` / `run`；核家族闭包、原生报告/索引及source摘要后复用 `tokyo_residential_preview.gd` / `export_index`。既有四片固定配方保持，空输入拒绝由 `test_rail_obstacle_export.gd` / `checks`覆盖。

R342四片七档块面构建：`tests/build_tokyo_batch_blocks.gd` / `run` / `build_region`精确绑定R340/R341、整层矩阵及游戏楼保护；`tests/build_tokyo_northwest_blocks.gd` / `build_verified`供旧区域与批次共用逐格owner/保存重载/计账，旧run配方保持。BATCH_BLOCKS显式入口在`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。

R341批次原生层导出：`tests/export_tokyo_batch_layers.gd:6 run`精确绑定R340清单及四原生报告，`tests/tokyo_residential_preview.gd` / `export_index`复用旧三层保存/重载/属性守恒；旧`export_northwest`仍保持原身份分派。`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`以BATCH_LAYERS显式调用，默认不变。

R337/R338道路候选收尾：`tests/build_tokyo_road_meshopt_catalog.gd:5 run`核原生道路导出摘要、保留层守恒，复用铁路分页保存；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式ROAD_MESHOPT分派。`tests/tokyo_canonical_review.gd:6 run`以ROAD_MESHOPT_REVIEW精确绑定新目录和覆盖，原48机位及预算门不变。

R333节点容量反事实：`tests/tokyo_capacity_probe.gd` / `run`显式精确R324目录、两中心四尺度×16/32/64容量，只调用原Pareto辅助函数作元数据比较；16档核正式choose相等。`tests/tokyo_canonical_cut_probe.gd` / `run`以CAPACITY_PROBE分派，运行时上限不改。

R330有界闲置缓存候选：`rendering/tokyo_cell_stream.gd` / `configure`、`_prune`、`reserve_auxiliary`、`_process_stream`显式RETAIN_UNUSED才启用需求驱动FIFO淘汰，目标/固定资源受保护，原总预算不变；`tests/test_tokyo_hierarchical_stream.gd` / `run`覆盖预留/辅助预算，`tests/test_tokyo_cross_lod_components.gd` / `lifecycle`覆盖保留后的owner退出。

R328路径重复加载诊断：`rendering/tokyo_cell_stream.gd` / `configure`、`_prune`、`_process_stream`、`summary`仅显式STREAM_AUDIT记录物理路径请求/淘汰整数，不保留资源；`tests/test_tokyo_hierarchical_stream.gd` / `run`验证默认关闭、实际淘汰一次及摘要隔离。

R324西南铁路原生接合：`tests/build_tokyo_southwest_rail_catalog.gd:5 run`精确R313数组身份及R324清理计划，按1748面序号划分、保留属性守恒，复用分页/覆盖/组件保存；`tests/build_tokyo_rail_catalog.gd` / `finish_rails`允许配方指定独立coverage目录。`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式RAIL_SOUTHWEST分派；`tests/test_rail_obstacle_export.gd` / `checks`拒绝空输入。

R313十区近档与真实审图：`tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`以SOUTHWEST_LAYOUT绑定R312→R313；`tests/tokyo_canonical_review.gd` / `run`以SOUTHWEST_SEAMS_REVIEW保留旧34位并加14位，预算门不变。

R312十区目录：`tests/build_tokyo_northwest_catalog.gd:12 native_binding` / `build` / `audit_join`绑定R310；`tests/build_tokyo_northwest_catalog.gd:409 southwest_kept`消费R311历史补充差集。`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`精确十区身份与西南实景覆盖；`tests/test_tokyo_regional_native.gd` / `run`覆盖新旧身份及拒绝。

R311西南历史迁移：`tests/tokyo_northwest_boundary.gd:289 southwest`由`run`/`audit`显式SOUTHWEST_BOUNDARY分派，只扣R310新增21条，R203 parent11保留层为输入、历史属性匹配及保存重载守恒；`tests/test_tokyo_regional_native.gd` / `run`覆盖空输入与两种分派拒绝。

R309西南七档块面：`tests/tokyo_residential_preview.gd:490 northwest_matrix`以SOUTHWEST与EXPORT配对导出/保存重载；`tests/build_tokyo_northwest_blocks.gd:9 run`绑定R309审计、选择R307较克制variant0，585块唯一owner与112资源守恒。不更改正式默认。

R308西南三距离预览：`tests/tokyo_residential_preview.gd:100 run`以SOUTHWEST绑定R307来源/计划/选择及游戏楼保护门，复用实际保留低楼网格与双候选九图；不替换正式默认，未验全LOD。

R307西南原生导出：`tests/tokyo_residential_preview.gd` / `export_northwest`以SOUTHWEST_EXPORT精确绑定R305，拒绝邻区export混用，三层保存重载及packed守恒；不改变正式目录。

R300南侧真实审图：`tests/tokyo_canonical_review.gd` / `run`以SOUTH_SEAMS_REVIEW要求九区审图并绑定R299目录/覆盖；原28位追加南侧六位，累计面数门不变，静态审图不代替连续镜头和帧时。

R299南侧近档分页：`tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`以SOUTH_LAYOUT同时要求NEAR_LAYOUT/NINE_REGION_LAYOUT，精确绑定R298→R299布局/目录/新覆盖；只改三近档父11，旧路线保持。

R298南侧九区目录：`tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`以SOUTH_COMBINED全链绑定R297；`rendering/tokyo_canonical_catalog.gd` / `extension_valid`仅增精确新manifest身份，coverage保持；regional native tests覆盖新身份和拒绝。

R296南侧联合归档：`tests/build_tokyo_northwest_blocks.gd` / `run`以SOUTH精确绑定R216联合输入与R293b/R295联合成本，83块唯一原格owner、112资源保存重载；原生未调色输入供后续九区差集。

R295南侧七档保留层：`tests/tokyo_residential_preview.gd` / `northwest_matrix`允许SOUTH独立复用精确R199七档源、绑定R293b选择，逐档保存重载保留网格；run继续拒绝南侧原始导出。未启用正式目录。

R294南侧新块面预览：`tests/tokyo_residential_preview.gd:100 run`的SOUTH显式入口精确绑定R293b，复用西北三层与正式游戏楼保护，三尺度原生/双候选九图；禁止混入旧矩阵/导出路径。

R290分层定位与混合样片：`tests/tokyo_layered_depth_review.gd:6 run`增加DEPTH_LAYER独立正/负源与DEPTH_HYBRID原生道路+负层纹理对照；不改变默认正式地表。

R289倾斜深度夹具：`tests/tokyo_layered_depth_review.gd:6 run`由LAYERED_DEPTH_REVIEW显式入口调用，3732原生固定面与两层PNG/BC3在东京38°投影、相同裁剪和零高度遮挡面下对拍60图；不是正式地图接合或性能验收。

R288纹理实机夹具：`tests/tokyo_layered_texture_review.gd:6 run`由cells生命周期显式入口调用，R286 PNG/R287 BC3及mip修正版双摘要绑定，GL3D视口8组采样对照；`tools/tokyo_premultiplied_mips.py` / `halve`为已预乘颜色逐通道mip生成，独立Python反例覆盖二次预乘。

R282九区备用复用：`rendering/tokyo_canonical_overlay.gd` / `_load_archive`只允许NINE_GUARD2+REUSE_GUARD2与精确R276目录组合，原UNCHANGED_FIXED_LOD12清单不变；复用既有`_prepare_target`算法。

R281九区跨档核验：`tests/tokyo_guard2_catalog_audit.gd:6 run` / `tests/tokyo_guard2_catalog_audit.gd:27 inspect`由`tests/tokyo_canonical_cut_probe.gd` / `run`的GUARD2_CATALOG_AUDIT显式入口调用，精确R276，逐208页核验来源/切线/固定层数组；不放开运行时身份门。

R277九区审图：`tests/tokyo_canonical_review.gd` / `run`的NINE_SEAMS_REVIEW精确绑定R276及新覆盖，保留原八位并追加20位；不再访问旧两中心数组，预算门不变。

R276九区近档：`tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`以NINE_REGION_LAYOUT要求NEAR_LAYOUT，精确绑定R275→R276新布局/目录/覆盖；旧R263路线保持。

R275九区接合：`tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`增加RIGHT并绑定R273/R274，R193减R203一次再加五片；`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`精确九区身份及右翼覆盖；`tests/test_tokyo_regional_native.gd` / `run`验证缺口和身份拒绝。

R273右翼调色：`tests/build_tokyo_north_palette.gd` / `build`以NORTH_RIGHT_PALETTE绑定R272、排斥LEFT，128资源RGB重映射，保存回读保护几何/alpha/高度；不接正式目录。

R272右翼七档：`tests/tokyo_residential_preview.gd` / `northwest_matrix`配对NORTH_RIGHT/EXPORT绑定R268/R270；`tests/build_tokyo_northwest_blocks.gd` / `run`生成164块唯一格归属、112归档保存重载，来源高度不变，未正式接入。

R271右翼块面预览：`tests/tokyo_residential_preview.gd` / `run`增加NORTH_RIGHT互斥路线，绑定R270计划/选择/三层来源，537投影片段、三距离双候选；近档保留层复核通过，尚未全LOD。

R270右翼三层导出：`tests/tokyo_residential_preview.gd` / `export_northwest`增加NORTH_RIGHT_EXPORT，排斥旧邻区开关、精确绑定R268及1276来源；只供新低层块面候选，未接运行时目录。

R269右翼定点检查：`tests/tokyo_cells_visual.gd` / `_capture_sample`增加RIGHT_SOURCE_REVIEW，绑定R268摘要、12源重叠中心各5/8倍三态，默认30图不变，不改资产或来源高度。

R267左翼共边：`tests/tokyo_canonical_review.gd` / `run`以LEFT_SEAMS_REVIEW精确绑定R263，保留原八位并追加两共边16位，首帧/稳态和恢复对拍沿原路径，非连续视频。

R264近档覆盖：`tests/build_tokyo_rebalanced_coverage.gd` / `build`以NEAR_LAYOUT精确绑定R263/R261覆盖身份，11档逐源重证；旧R237默认保留。真实预览静态基本一致但预算未过。

R263近档布局：`tests/tokyo_rebalanced_layout.gd` / `run`及`tests/build_tokyo_rebalanced_catalog.gd` / `build`以NEAR_LAYOUT精确绑定R261/R263，仅LOD4 full/mid与LOD5父11共享新切线，其余173根不变；`tests/tokyo_canonical_cut_probe.gd` / `run`接受精确R263做原48姿态对照。覆盖/Visual仍待验证。

R262左翼成本诊断：`tests/tokyo_canonical_cut_probe.gd` / `run`以NORTH_LEFT_CUT_PROBE精确绑定R261，三处接缝48姿态及逐选中页身份/层成本/包络输出，元数据只读，不修改正式求解器或几何。

R261八区接合：`tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`增加NORTH_LEFT_COMBINED精确R260身份与四区原生聚合；`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`保留未制作缺口；`tests/test_tokyo_regional_native.gd`覆盖错配摘要、缺开关、旧计数及共享索引不变。候选预算失败，非正式默认。

R258左翼全LOD：`tests/tokyo_residential_preview.gd` / `northwest_matrix`以NORTH_LEFT和配对EXPORT精确绑定R256/R257；`tests/build_tokyo_northwest_blocks.gd` / `run`绑定新矩阵，105块固定归属、112归档保存重载。尚未正式接合。R257的`export_northwest`/`run`仍用于完整投影和双候选预览。

R255源缓存边角守恒：`tools/build_tokyo_volume_region.py` / `RegionCollector.load_cache`与area包络筛选一致；`tools/test_tokyo_volume_region.py` / `test_cache_preserves_bbox_only_corner_source`拒绝重放漏源，保留源高度/几何与输入。两翼仅来源阶段，不是原生接入。

R254空层短路：`experiments/tokyo_spatial_select.gd:6 visible`在投影包络前跳过零面层，保留掩码；`tests/test_tokyo_hierarchical_pages.gd` / `_test_visible_equivalence`对照完整描述符与输入不变，覆盖所有空层组合及相机变换。实测未证明整帧加速。

R253组合等价回归：`tests/test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`以256组确定输入对照原_insert路径，比较完整有序frontier及输入不可变，接原run。延迟分配候选已实测撤回，运行时仍为原组合算法。

R252地图更新分段：`rendering/tokyo_canonical_overlay.gd:200 _step_geometry`在现有frame_trace门内记录restore/select/prepare/ready/bind/visibility/legacy_sync；沿用PerfBuckets上下文输出，不改运行时选择或帧根桶。

R249七区目录：`tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`以NORTH_SEAM_COMBINED及旧三开关绑定R247，聚合三片已去重增加层；`test_tokyo_regional_native.gd` / `_extension_contract`覆盖配对及缺开关拒绝。旧五/六区默认保留。

R248七区覆盖门：`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`精确R247登记/原生配对，三矩形实际覆盖不填外包络缺口；`tests/test_tokyo_regional_native.gd` / `_extension_contract`覆盖空缺、旧源不可变和错误身份/数量拒绝。

R246厂棚并集：`tests/build_tokyo_depot_union.gd:12 build`精确绑定R244/R245计划，通过PackedDifference保留源外有向属性、同owner七档重载/来源高度守恒；显式DEPOT_UNION由`tests/tokyo_canonical_cut_probe.gd:11 run`调用。`tests/tokyo_cells_visual.gd` / `_capture_sample`允许该确切摘要对拍；`tests/test_tokyo_regional_native.gd:13 run`拒绝空输入。

R245北侧源问题近景：`tests/tokyo_cells_visual.gd` / `_capture_sample`的NORTH_SOURCE_REVIEW显式分支绑定R244摘要，仅厂棚与休憩建筑两机位三缩放18图；默认30图不变，不修改资产。

R259/R244离线调色：`tests/build_tokyo_north_palette.gd:8 build`默认绑定R243摘要，NORTH_LEFT_PALETTE仅接受R258精确摘要，128资源保存重载；`tests/build_tokyo_north_palette.gd:76 geometry_equal`允许RGB变化、保留alpha与几何；`tests/test_tokyo_palette.gd:10 run`覆盖透明度漂移反例。

R243北侧全LOD：`tests/tokyo_residential_preview.gd` / `northwest_matrix`以NORTH_SEAM及配对EXPORT绑定R241/R242，复用近档导出；`tests/build_tokyo_northwest_blocks.gd` / `run`同开关生成253固定归属块体/112归档，不接正式目录。

R242北侧街区候选：`tests/tokyo_residential_preview.gd` / `export_northwest`显式NORTH_SEAM_EXPORT绑定R241原生；`run`的NORTH_SEAM要求NORTHWEST且排斥旧子片，精确计划/选择/三层身份，三距离双候选；尚不支持新片矩阵制作或正式接入。

R238新切线遮蔽重证：`tests/build_tokyo_rebalanced_coverage.gd:8 build`，显式REBALANCE_COVERAGE经`tests/tokyo_canonical_cut_probe.gd:11 run`调用；精确R237与旧计划/碰撞身份，复用SourceCoverage逐面与缺依赖审计，不迁移旧token。

R237共享布局原生目录：`tests/build_tokyo_rebalanced_catalog.gd:8 build`，显式REBALANCE_BUILD经`tests/tokyo_canonical_cut_probe.gd:11 run`调用；绑定R232/R236，复用Regional._replace和Northwest.audit_entry，11档231页同布局守恒；不迁移旧coverage证明，不启用正式显示。

R236共享空间布局：`tests/tokyo_rebalanced_layout.gd:6 run`，由`tests/tokyo_canonical_cut_probe.gd:11 run`显式REBALANCE_LAYOUT入口调用。只读精确R232父11，复用原生Split及有向属性守恒，生成16叶共享切线；不写地图目录，不启用运行时。

R232六区目录：`tests/build_tokyo_northwest_catalog.gd` / `native_binding`增加三开关精确R230身份；`build`聚合两片成品增加层，`audit_join`独立读取两片核页/组件/coverage；原五区默认不变。

R232共边真实审图：`tests/tokyo_canonical_review.gd` / `run`在NORTHWEST_OUTER_REVIEW定位(-7300,-3520)，复用原八机位/就绪/预算门。

R231六区L形覆盖：`rendering/tokyo_canonical_catalog.gd` / `extension_valid`精确R230身份；`presentation_archive`将包络与两块实际coverage分离，保留西南空缺。`tests/test_tokyo_regional_native.gd` / `_extension_contract`验证空缺、共享索引不变及错误身份/数量拒绝。

R229外围西侧七档：`tests/tokyo_residential_preview.gd` / `northwest_matrix`以OUTER_WEST与EXPORT成对开关绑定R227原始源、R228选择；`tests/build_tokyo_northwest_blocks.gd` / `run`以精确矩阵生成249块/112归档，复用唯一格归属与保存重载守恒。

R228外围西侧：`tests/tokyo_residential_preview.gd` / `export_northwest`以OUTER_WEST_EXPORT精确绑定R227三层；`run`的OUTER_WEST绑定R228计划/2614选择/新来源与机位，要求NORTHWEST且与旧WEST/EAST互斥，复用三距离双候选。

R225旧楼阴影缓存战斗对照：`tests/tokyo_volume_combat_runner.gd` / `_ready`在有界旧楼入口内按SHADOW_CACHE_BENCH开关缓存；`_bench_finish_now`追加shadow_cached/shadow_builds，复用原C1及严格墙钟门。

R224旧楼视图失效：`survivor/building_renderer.gd` / `consume_view_change` / `_process` / `setup`新增zoom/extent触发、保持4px位移门；`tests/tokyo_canonical_review.gd` / `run`有界候选审图期间保持旧楼更新并恢复；测试见`tests/test_tokyo_regional_native.gd` / `run`。

R223旧楼阴影单槽缓存：`survivor/building_renderer.gd` / `shadow_packet` / `_draw_visible_districts`按有序来源/偏移/颜色复用不变数组，`setup` / `_load_data`失效；`tests/test_tokyo_regional_native.gd` / `run`测等价与失效，`tests/tokyo_canonical_review.gd` / `run`显式SHADOW_CACHE_REVIEW逐真实机位验缓存命中与关闭后数组一致。

R221旧楼战斗配对：`tests/tokyo_volume_combat_runner.gd` / `_ready`显式BOUNDED_LEGACY_BENCH要求原BENCH_LEGACY入口，两组保留真实旧楼与同C1负载；`_bench_finish_now`写visible/bounded身份，默认关闭候选。

R220旧楼有界投影候选：`survivor/building_renderer.gd` / `bounded_roof_offset`给径向侧墙连续楼高限幅；`_draw_one`仅显式开关启用。`tests/test_tokyo_regional_native.gd` / `run`测零高/中心/远距界/连续性/方向；`tests/tokyo_canonical_review.gd` / `run`显式BOUNDED_LEGACY_REVIEW启用并恢复，默认不变。

R219旧楼分层：`tests/tokyo_canonical_review.gd` / `run`显式LEGACY_LAYER_REVIEW在远中近三位保存旧楼隐藏/恢复对照，只用于来源诊断，不改变原预算门或生产默认。

R218三片目录：`tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`在COMBINED+EAST_COMBINED下选择认证R217；`rendering/tokyo_canonical_catalog.gd` / `extension_valid`限精确三片身份；`tests/test_tokyo_regional_native.gd` / `_extension_contract`验证缺COMBINED/错边界；`tests/tokyo_canonical_review.gd` / `run`显式NORTHWEST_EAST_REVIEW移到东侧机位。

R216东侧全档及三片联合：`tests/tokyo_residential_preview.gd` / `northwest_matrix`的EAST模式复用原R199七配置；`tests/build_tokyo_northwest_blocks.gd` / `run`以R210联合包为底追加141块，累计中央/西侧净差后逐格核验；WEST/EAST互斥，来源/标高/固定层保持。

R215东侧独立预览：`tests/tokyo_residential_preview.gd` / `run`显式RESIDENTIAL_NORTHWEST_EAST绑定新东侧计划/2181选择/机位，要求NORTHWEST且与WEST互斥；复用原三层/整组件保留和三距离双方案，不替代全LOD或实装。

R214联合墙运行时配对：`rendering/tokyo_low_wall_manifest.gd` / `paired_identity` / `read`仅加入R212/R213精确对、88页计费不改；`tests/test_tokyo_low_walls.gd` / `checks`覆盖四对全部组合；`tests/tokyo_low_wall_review.gd` / `run`显式NORTHWEST_WEST_REVIEW把静态及连续段同置新西侧。

R213墙分页：`tests/build_tokyo_wall_pages.gd` / `run` / `audit`在NORTHWEST+COMBINED下绑定新目录/墙包与8645墙，`tokyo_cells_lifecycle_runner.gd` / `_ready`审计新页目录；原切线/双槽/预算不改，旧配方保留。

R213联合街区墙分层：`tests/build_tokyo_northwest_walls.gd` / `run`显式NORTHWEST_COMBINED以R212目录+R209计划+R205旧墙生成8645墙，逐11配置原生差集/保存重载守恒；默认旧5287配方不变，未接分页或运行时。

R212西侧实际预览：`tests/tokyo_canonical_review.gd` / `run`的NORTHWEST_WEST_REVIEW仅在NORTHWEST_REVIEW内移动八机位锚点至新西侧，载入/就绪/碰撞/24万面预算门保持，不代表全图覆盖或帧时验收。

R210西侧全档：`tests/tokyo_residential_preview.gd` / `northwest_matrix`显式NORTHWEST_WEST仅从精确R199矩阵复用七份原始三层，不重复导出；同1896选择按新条带整组件裁取/保存重载，旧中央矩阵及来源不改。

R210联合独立包：`tests/build_tokyo_northwest_blocks.gd` / `run`同一有限西侧开关改以精确R199中央成品为输入，添加232块并按真实七档净差核验，不从原形覆盖旧中央。仍沿原16格分配整块owner/扩content_bounds，来源高度/标高/固定层不改，非正式跨区目录。

R209西北西侧候选：`tests/tokyo_residential_preview.gd` / `run`显式NORTHWEST_WEST绑定新计划/选择SHA和1896投影组件，复用原生三层/整组件保留/三距离双候选；中心(-7140,-3200)，不替换已认可中央或实际运行目录。

R208固定提交定位：`tests/tokyo_submission_duplicate_audit.gd` / `run`显式SUBMISSION_NORTHWEST绑定R204目录与R206实际峰值SHA，复用有向完整角点去重并增加颜色/父区费用分桶；只读，不把重复或同色直接当删除授权。

`entry_digest`递归目录树取得真实文件SHA（逻辑descriptor不存该字段）；`test_tokyo_regional_native.gd` / `run`覆盖根/叶/缺失与空输出反例。

R207西北实战帧时：`tests/tokyo_volume_combat_runner.gd` / `_ready`显式BENCH_NORTHWEST移动现有C1锚点，人口/武器/镜头节奏不改；同R204目录无墙/有墙渐隐三对，不使用旧目录差异作为控制。

R206西北低墙试验：`rendering/tokyo_low_wall_manifest.gd` / `paired_identity` / `read`精确新旧三组目录与清单配对；`tests/test_tokyo_low_walls.gd` / `checks`覆盖9种交叉组合与未知身份；`tests/tokyo_low_wall_review.gd` / `run`的NORTHWEST_REVIEW使用新片区中心，保留五距离三态和192连续机位原失败门。

R205新目录墙分层：`tests/build_tokyo_northwest_walls.gd` / `partition`仅从认可计划分类屋顶/竖墙，`run`将旧3313与新1974墙面在R204父11全部11配置精确扣取/保存重载守恒；`tokyo_cells_lifecycle_runner.gd` / `_ready`显式NORTHWEST_WALLS入口。不接运行时或移除普通保留楼墙。

`tests/build_tokyo_wall_pages.gd` / `run` / `audit`的NORTHWEST有限入口绑定R204目录及R205完整分层包，仍用`visit`原切线、全低层裁剪框与双槽；测试入口`test_tokyo_regional_native.gd` / `run`覆盖空源/空网格/错色拒绝与屋顶竖墙守恒。

R204/R212五区成品接合：`tests/build_tokyo_northwest_catalog.gd` / `native_binding`以NORTHWEST_COMBINED选择认证R211清单/审计配对，默认R201；`build` / `finish`复用RegionalCatalog._replace原切线/组件/coverage；`audit_join` / `audit_entry`独立核对693页与来源组合，其他13父区不变。`rendering/tokyo_canonical_catalog.gd` / `extension_valid`仅接受两份精确西北扩展身份；`test_tokyo_regional_native.gd` / `_extension_contract`反例；`tokyo_cells_lifecycle_runner.gd` / `_ready`显式构建/审计；`tokyo_canonical_review.gd` / `run`显式NORTHWEST_REVIEW定位真实8机位。

R203历史属性边界迁移：`tests/tokyo_northwest_boundary.gd` / `historical_target`绑定R161近档完整float SHA，`select_historical`精确有向XYZ/颜色唯一选面并收紧实际索引AABB，`audit`另进程核验66项/132网格及玩法保护；`tokyo_cells_lifecycle_runner.gd` / `_ready`显式BOUNDARY_AUDIT，`test_tokyo_regional_native.gd` / `run`覆盖缺参、未知档、重复/颜色与来源守恒。

R202成品边界诊断：`tests/tokyo_northwest_boundary.gd` / `run`绑定R193/R200与69条来源，三父区11配置两层差集/保存重载、玩法保护；`compare_positions`区分位置缺失和属性差异，`decoded_roundtrip`仅复现目标导入编码。入口`tokyo_cells_lifecycle_runner.gd` / `_ready`显式NORTHWEST_BOUNDARY；反例`test_tokyo_regional_native.gd` / `run`。失败配置不得推广。

R201五区归属：`tests/build_tokyo_regional_native.gd` / `subtract` / `conserved`仅索引输入转交既有`experiments/tokyo_packed_mesh_difference.gd`，旧非索引布局保持；`tests/test_tokyo_regional_native.gd` / `run`覆盖索引重数、源不变、超额拒绝、解码守恒与旧布局。

R199西北七档候选：`tests/tokyo_residential_preview.gd` / `export_northwest` 参数化原始level/mid（非法组合拒绝），`northwest_matrix` 同选择真实kept与完整来源；`tests/build_tokyo_northwest_blocks.gd` / `run` 精确输入、109块固定owner、112资源保存重载/源保留/成本矩阵；`tokyo_cells_lifecycle_runner.gd` / `_ready` 显式离线构建入口；`test_tokyo_residential_selection.gd` / `checks` 非法入口反例。不推广正式地图。

R198西北原生块面：`tests/tokyo_residential_preview.gd` / `export_northwest` 精确R197 index三层合并/保存重载守恒与XYZ属性导出；`run` 显式NORTHWEST绑定新计划与选择摘要，复用整组件选择和三距离双候选九图，与旧区域/矩阵互斥。不改正式运行时。

R197西北原生基线：`tests/build_tokyo_cells.gd` / `run` 显式sample输出模式校验与typed矩形列表；`tests/build_tokyo_far_clusters.gd` / `eligible`、`tools/build_tokyo_footprint_lod.py` / `eligible` 排除开放屋盖，原生与Python反例分别扩展现有测试。既有区域样片审计/预览入口继续复用。

R196开放屋盖：`experiments/tokyo_volume_preview_factory.gd` / `_add_ring_building` 按来源roof标签省略自动围墙，保持顶面；`tests/test_tokyo_volume_ring_geometry.gd` / `run` 覆盖三档/内院/普通平顶反例/准备坡顶，显式OPEN_ROOF_SOURCE精确绑定西北17个真实屋盖。

R194缺口定位：`tests/tokyo_coverage_gap_probe.gd` / `run` 只读实际像素地面反投影、原生alpha、archive覆盖矩形和最高档根AABB；`tokyo_low_wall_review.gd` / `run` 在显式COVERAGE_GAP_PROBE的zoom2.2采样，不改生产选择/可见性。

R193北侧分页/实图：`tests/build_tokyo_residential_catalog.gd` / `run` 有限完整包；`build_tokyo_wall_pages.gd` / `run` / `audit` 配对新目录、3313墙与切面费用。`rendering/tokyo_low_wall_manifest.gd` / `read` 新旧身份分别认证、88/66页；`tokyo_component_review.gd`、`tokyo_low_wall_review.gd`、`tokyo_canonical_review.gd` 的 `run` 北侧中心复用原路线与失败门，`test_tokyo_low_walls.gd` / `checks` 增新身份缺件拒绝。

R192北侧联合分层包：`tests/build_tokyo_wall_bundle.gd` / `run` 有限NORTH报告及完整/常驻/墙身份，复用11配置原生保存重载守恒；旧西侧模式不变。

R191北侧住宅预览：`tests/tokyo_residential_preview.gd` / `run` 新增NORTH有限计划/选择身份与北侧同位机位，沿用整组件保留和九图；与WEST及旧矩阵导出互斥，非运行时地图接线。

R189底图容量：`survivor/raster_basemap_renderer.gd` / `_request_target_tiles` 在途预约槽，`_add_tile` / `debug_state` 计已驻留+在途峰，`_remove_resident` 在借用者退役后同步断纹理。`tests/raster_capacity_lifecycle_case.gd` / `run` / `_map_case` 与Fixture的 `_visible_keys` / `_required_keys` 固定集合，三图真实异步请求、旧层保护、补齐、在途退出；接原focused runner及lifecycle gauntlet。`tests/tokyo_low_wall_review.gd` / `run` 原D路线增加每实际draw容量观察。

R188低墙LOD：`rendering/tokyo_low_wall_binding.gd` / `fade_for_scale` / `apply_fade` 只改可见墙与提交缓存；`tokyo_canonical_overlay.gd` / `_refresh_low_wall_lod` / `set_low_wall_full_override` 原tick共享材质、尺度更新和暖绘覆盖。`tests/tokyo_low_wall_review.gd` / `run` 同位自动/完整/恢复与连续缩放旋转，复用已有原生绘制计数探针；`test_tokyo_low_walls.gd` / `checks` / `lifecycle` 增加非法尺度及隐藏/渐隐/恢复守恒。

R187低墙原子所有权：`rendering/tokyo_low_wall_manifest.gd` / `read` / `replace_row` 有限R186副清单；`tokyo_low_wall_binding.gd` / `create_slot` / `bind` / `clear` / `faces` 原低层子节点、完整裁剪框和共同退役。`tokyo_canonical_spatial_page.gd` / `valid`、`tokyo_component_stream.gd` / `resource` 持有两槽原网格；`tokyo_canonical_overlay.gd` / `_load_archive` / `_setup_geometry` / `_bind_target` / `_remove_cell` / `debug_state` 接原事务。`tokyo_volume_preload.gd` / `start` / `take` / `_begin` 增加清单领取身份。测试`test_tokyo_low_walls.gd` / `fixture` / `checks` / `lifecycle` 接focused/all/gauntlet；`tokyo_component_review.gd` / `run` 对拍完整楼与双槽；`tokyo_preload_route_probe.gd` / `run` 查同实例与释放，`tokyo_draw_geometry_probe.gd` / `capture` 独立计父+子真实面。完整墙阶段未启用渐隐。

R186低墙分页归档：`tests/build_tokyo_wall_pages.gd` / `visit` / `run` 沿既有cuts配对常驻/低墙，保存双槽组件、逐页重载守恒及完整低层裁剪框；`cut_cost` / `audit` 按物理去重核算父11低层切面/两切面联合。`tokyo_cells_lifecycle_runner.gd` / `_ready` 显式WALL_PAGES及WALL_PAGES_AUDIT入口。尚未修改运行时三层合同。

R185西侧实际地图机位：`tests/tokyo_canonical_review.gd` / `run` 的RESIDENTIAL_WEST_REVIEW仅将住宅八机位中心换到西侧，保留原就绪/碰撞/预算门。

R185完整西侧目录：`tests/build_tokyo_residential_catalog.gd` / `run` 仅WEST_FULL精确完整分层报告，复用原切线/组件/覆盖/来源守恒流程，不接受只含屋顶的报告。

R185西侧原生分层包：`tests/build_tokyo_wall_bundle.gd` / `run` 有限输入、11配置完整/常驻/低墙守恒，`save_checked` 保存重载签名；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` WALL_BUNDLE入口。

R184低墙连续采样：`tests/tokyo_wall_fade_sequence.gd` / `run` 复用分层与材质、81姿态同位参考/候选和实际视口提交；`tests/tokyo_roof_proxy_review.gd` / `run` WALL_FADE_SEQUENCE分支，不重复R183静态矩阵。

R183低墙候选审图：`tests/tokyo_roof_proxy_review.gd` / `run` 复用原生decode/join、同源父11、实材质三态恢复对拍；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 显式ROOF_PROXY_REVIEW入口。

R182逐楼体候选：`tests/tokyo_retained_lod_probe.gd` / `run` 读取精确88体归属清单，`generate_variants` 复用本机LOD与导出；旧整片反例模式保留。

R181有限保留层LOD：`tests/tokyo_retained_lod_probe.gd` / `run` 验来源、完整属性去重、枚举本机ImporterMesh API、导出各档；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 显式RETAINED_LOD_PROBE入口，不改生产。

R179完整道路区预览：`tests/tokyo_residential_preview.gd` / `run` 接WEST_ROAD有限计划/选择身份与区域边界；复用`retained_mesh`，旧WEST及矩阵隔离不变。

R178西侧资产预览：`tests/tokyo_residential_preview.gd` / `retained_mesh` 接显式region且旧默认不变，`run` 仅WEST精确计划/选择摘要、同原生来源与三距离双候选，禁止套旧矩阵导出；正式地图不变。

R177正常/参考提交分桶：`tests/tokyo_draw_geometry_probe.gd` / `capture` / `_verify_report` / `summary` 保留总峰并追加is_processing阶段及正常峰父包快照；`tests/tokyo_tile_stream_review.gd` / `run` 住宅路线实际pre_draw接入并执行24万门。

R176住宅连续审图：`tests/tokyo_tile_stream_review.gd` / `run` 复用RESIDENTIAL_REVIEW中心，逐draw观察fine应用/0.55外原生恢复/双绘制和借用冲突；默认北侧目标不变。

R175借用地表冲突：`rendering/tokyo_fixed_atlas_layer.gd` / `borrowed_overlap` / `_update_region` 正面积相交拒绝扁平替换，触边仍允许；`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `lifecycle` 验相交、非法范围、跨帧恢复及退出。`tests/tokyo_tile_stream_review.gd` / `projected_check` 隔离固定图集后检查借用底图颜色，再恢复可见性。

R173高清单纹理接线：`rendering/tokyo_fixed_atlas_layer.gd` / `region_contract` / `eligible` / `fixed_configuration` / `manifest_row` / `_bind_region` / `update` / `_update_region` 仅R162父11取step1，保守scale0.55；其他区0.3888。`tests/tokyo_preloaded_ao_review.gd` / `fixed_region_bytes` / `fixed_atlas_bytes` 与 `tools/audit_tokyo_ao_preload.py` / `fixed_atlas_bytes` 独立按来源/步长计费；`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `collection_lifecycle` 及 `tools/test_tokyo_ao.py` / `test_fixed_collection_reservation` 验边界/少计/错源/取消/预算中途回滚。

R172补充LOD3：`tests/tokyo_fixed_atlas_review.gd` / `fine_configuration` / `run` 绑定LOD3 full/guarded两份独立证明摘要并报告实际配置，未证明LOD4/5拒绝；`test_tokyo_tile_ground.gd` / `run` 验配置/非法类型。`export_tokyo_fixed_mesh.gd` / `run` 只读支持同一精确目录的LOD3 full/guarded。

R172高清静态审图：`tests/tokyo_fixed_atlas_review.gd` / `complete_fine` / `run` 只在R162父11精确R167清单与R172同源证明下尝试step1、最大scale0.7776，保留恢复/近景拒绝，要求真正超旧范围应用；`tests/test_tokyo_tile_ground.gd` / `run` 覆盖清晰度界限、粗图、部分覆盖和未认证配置拒绝。不改正式运行时。

R172过渡地表来源导出：`tests/export_tokyo_fixed_mesh.gd` / `run` 显式R162 lod2_guarded逐父区/源SHA命名拒绝覆盖；`tests/tokyo_cells_lifecycle_runner.gd` 的FIXED_EXPORT_CONFIG只传递有限配置，由导出器检查。不修改运行时复用资格。

R171图集热路径：`rendering/tokyo_fixed_atlas_layer.gd` / `REGIONS` / `region_contract` / `eligible` / `update` / `_update_region` 常量合同、资格直接面数查询、单次批次分组，不保存跨帧对象。`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `collection_lifecycle` 验深拷贝隔离、七批次六区组合与近景零扫描。

R170地表跨档同源：`tests/export_tokyo_fixed_mesh.gd` / `run` 增加有限R162的LOD1只读导出，默认LOD2不变；`tests/tokyo_cells_lifecycle_runner.gd` 显式FIXED_EXPORT_LOD1选择。`rendering/tokyo_fixed_atlas_layer.gd` / `fixed_configuration` / `_update_region` 仅对R162接受已证明相同的LOD1；`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `collection_lifecycle` 旧LOD2/新LOD1双矩阵及其他配置拒绝。

R169新目录图集接线：`rendering/tokyo_fixed_atlas_layer.gd` / `region_contract` / `collection_entries` / `eligible` / `manifest_row` / `_bind_region` / `_update_region` 按实例保存目录身份，绑定R168六清单，新面数只用于R162。`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `collection_lifecycle` 覆盖新旧面数隔离、共用许可不变和显式新集合真实纹理取消。

R168六片地表认证：`tools/revalidate_tokyo_auxiliary.py` / `fixed_source_matches` / `revalidate_residential_fixed` 逐完整角点/原生资源摘要认证四片旧源，结合两片新烘焙，另存有限集合和来源报告；`tools/test_tokyo_auxiliary_revalidation.py` / `test_fixed_source_requires_full_identity_and_live_bytes` 验目录/碰撞/归属/数量/路径/载荷变更拒绝。运行时许可不变。

R167静态新源审图：`tests/tokyo_fixed_atlas_review.gd` / `run` 向离线region_contract传入catalog；`test_tokyo_tile_ground.gd` / `_test_fixed_expansion` 覆盖新旧面数、其他区域拒绝和运行时合同不变。

R167地表压缩新源：`tests/build_tokyo_fixed_atlas_bc3.gd` / `region_contract` / `manifest_valid` / `run` 只在离线接受R162父11/12新面数和R166有限manifest，原运行时合同不变。

R166新源拒绝反例：`tools/test_tokyo_fixed_atlas.py` / `FixedAtlasTests.test_residential_source_requires_exact_manifest` 验伪新目录manifest被拒绝；既有目录检查和栅格测试保持。

R166当前地表重新烘焙：`tools/build_tokyo_fixed_atlas.py` / `read_native` 仅额外接受R162目录+R164源manifest精确摘要，复用原生两分辨率生成；不放宽运行时复用门。

R164固定峰值重复审计：`tests/tokyo_submission_duplicate_audit.gd` / `run` 有限目录/快照、实际提交数量和完整有向角点；`tokyo_cells_lifecycle_runner.gd` / `_ready` 显式SUBMISSION_AUDIT。

R163住宅实战锚点：`tests/tokyo_volume_combat_runner.gd` / `_ready` 显式BENCH_RESIDENTIAL移动现有真实混战锚点，不改人口、镜头节拍及墙钟硬门。

R163住宅实际相机：`tests/tokyo_canonical_review.gd` / `run` 显式RESIDENTIAL_REVIEW定位核心并走八个近远/旋转/返回机位；复用Loading路线，不取代连续运动证据。

R162住宅完整目录：`tests/build_tokyo_residential_catalog.gd` / `run` / `verify_pages` 继承既有归档工具，仅替换父11低楼并逐页验证；`tokyo_cells_lifecycle_runner.gd` / `_ready` 显式RESIDENTIAL_CATALOG入口。

R161修正网格输入：`tests/tokyo_residential_patch.gd` / `run` 绑定完整原始源区外报告与full_original_source，共享核心摘要不变，继续复用保存重载与对拍。

R161完整住宅来源：`tests/tokyo_residential_preview.gd` / `run` / `matrix` 显式RESIDENTIAL_MATRIX=source导出未经选择删除的11档低楼角点和属性摘要，原kept模式不变；区外裁切不得继续使用旧kept来源。

R160住宅共享区原生导入：`tests/tokyo_residential_patch.gd` / `checks` / `decode` / `run` / `capture` 有限摘要、角点输入反例、11Mesh保存重载和各档同机位对拍；`test_tokyo_tile_ground.gd` / `run`接反例，`tokyo_cells_lifecycle_runner.gd` / `_ready`接显式RESIDENTIAL_PATCH。

R158完整角点导出：`tests/tokyo_residential_preview.gd` / `export_attributes` / `export_kept` 保留旧XYZ并伴随输出每三角120字节XYZ/NXYZ/RGBA，用于区域裁切属性复核，不修改源包。

R155跨配置住宅预查：`tests/tokyo_residential_preview.gd` / `matrix` 显式RESIDENTIAL_MATRIX从R150父11各配置导出真实kept层，`run`选择该只读路线；不改正式目录。

R153预览接入整组件：`tests/tokyo_residential_preview.gd` / `retained_mesh` 调整为整组件选择，`export_kept` 导出实际保留XYZ供独立交叠检查；`run`仍为独立资产预览。

R342离线选择吞吐 → `tests/tokyo_residential_selection.gd` / `index_shapes` / `indexed_inside` / `partition`：空间桶及重复投影点缓存，精判仍沿`inside`；`root_of`保持完整XYZ组件归属。反例与原算法格点/边缘对照 → `tests/test_tokyo_residential_selection.gd` / `checks`；原生差集与游戏目录行为不变。

R152住宅块面资产预览：`tests/tokyo_residential_preview.gd` / `blocks_mesh` / `retained_mesh` / `run` 从有限C计划挤出屋顶/带孔墙环、保留非选择原生面，独立GL三距离九图；`tokyo_cells_lifecycle_runner.gd` 的显式RESIDENTIAL_PREVIEW入口调用。不改正式目录，不作为游戏材质/LOD验收。

R151铁路目录AO限定认证：`tools/revalidate_tokyo_auxiliary.py` / `revalidate_rail_ao` 只复制精确R143→R150同源窗口的AO载荷，`same_ao_source` 的显式rail模式保持默认旧配方；`tools/test_tokyo_auxiliary_revalidation.py` / `test_rail_pair_is_explicit_and_directed` 拒绝默认混用、范围/半径/来源变化及反向面。不认证固定地表，不修改运行时身份门。

R150相邻铁路归档：`tests/build_tokyo_rail_catalog.gd` / `recipe` 精确R149来源+父11计划合同；`planned_mesh` / `run` / `finish_rails` / `audit` 使用有限父号和对应摘要，原父12流程保持；`tests/test_tokyo_rail_catalog.gd` / `checks` 覆盖两种配方。

R150父11障碍：`tests/export_tokyo_rail_obstacles.gd` / `region_for_parent` 有限父11/12区域，`projected_overlap` / `corners` / `run` 显式区域参数；`tests/test_rail_obstacle_export.gd` / `checks` 验区域隔离/非法父号，原focused/all入口保持。

R149保存审计：`tests/build_tokyo_rail_catalog.gd` / `audit_entry` / `audit` 逐231页核对非轨道有向三角、低楼/标高数组、cuts与其它父包；`tests/tokyo_canonical_review.gd` / `run` 的RAIL_REVIEW为独立父12七机位对拍，不替代历史连续路线或性能。

R149共享铁路归档：`tests/build_tokyo_rail_catalog.gd` / `partition` / `planned_mesh` / `run` / `finish_rails` 复用固定层替换、切线、组件和coverage，父12全配置共用场坪；`tests/test_tokyo_rail_catalog.gd` / `checks` 拒绝同高不同色误删及非法plan，接地表focused/all；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 显式RAIL_CATALOG入口。

R148当前楼体障碍导出：`tests/export_tokyo_rail_obstacles.gd` / `projected_overlap` / `corners` / `run` 读取精确目录全部配置实际低楼/标高投影，按来源页去重、float32 XYZ与摘要输出；`tests/test_rail_obstacle_export.gd` / `mesh` / `checks` 覆盖索引/非索引、范围与跨界/垂直墙/空mesh。`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 显式RAIL_OBSTACLE_EXPORT入口；`tests/test_tokyo_tile_ground.gd` / `run` 接focused及all。

R146独立预算脚本：`tools/audit_tokyo_ao_preload.py` `fixed_atlas_bytes` 支持逐区校验六份图块与已退出暖绘；`tools/test_tokyo_ao.py` `test_fixed_collection_reservation` 验成员缺失/少计/活暖绘。R147用户铁路概括候选复用既有固定图块制作与静态审图入口；配方/源身份及未接近景边界见东京spec与工程审计。

R146有限固定地表集合：`rendering/tokyo_fixed_atlas_layer.gd` / `region_contract` / `collection_entries` / `bind` / `_bind_region` / `members` / `refresh_stats` / `_suspend_region` / `_update_region` / `warm_ready` / `close`，共用Stream与原tick。原生来源合同由离线压缩器同名入口复用。`tests/test_tokyo_fixed_atlas_layer.gd` / `Fixture._add_mesh` / `collection_lifecycle` 验多区恢复/在途取消/真实资源预算回滚；`tests/tokyo_preloaded_ao_review.gd` / `fixed_region_bytes` / `fixed_atlas_bytes` 逐区独立计费；`tests/tokyo_preload_route_probe.gd` / `run` 记录全部同纹理与菜单释放；`tests/tokyo_draw_geometry_probe.gd` / `capture` 独立遍历实际节点；`tests/tokyo_canonical_review.gd` / `run` 追加五区与双旋转接缝，保留历史机位。

R145 Python反例入口：`tools/test_tokyo_fixed_atlas.py` / `test_only_certified_source_catalogs` / `test_opaque_padding_keeps_rectangular_interior_and_shape` / `test_opaque_padding_rejects_subpixel_hole`，对应有限来源、矩形内部颜色不变与真实小孔拒绝。

R145固定地表扩区离线链：`tools/build_tokyo_fixed_atlas.py` / `valid_source_manifest` / `read_native` / `opaque_rectangular_padding` / `raster` / `build` 有限目录身份、真实矩形及边缘延展；`tools/test_tokyo_fixed_atlas.py` 覆盖身份、透明/内部颜色和亚像素孔洞。`tests/build_tokyo_fixed_atlas_bc3.gd` / `region_contract` / `manifest_valid` / `flat_rgb_block` / `patch_flat_blocks` / `run` 有限父包合同与显式纯色块BC3校正。`tests/tokyo_fixed_atlas_review.gd` / `complete_native` / `run` 按原生中心同位对拍、完整LOD2固定层资格、近景拒绝和释放；`tests/test_tokyo_tile_ground.gd` / `_test_fixed_expansion` / `_test_flat_bc3` 接原focused/all；`tests/tokyo_preload_route_probe.gd` / `run` 在显式固定图块对拍时不附带另一套component巡检。仅制作/静态验证，生产父11所有者和默认未扩展；结果见工程审计。

R144近档优势选择：`experiments/tokyo_guarded_pair_reuse.gd` / `near_choice` 复用既有LOD5备用、覆盖门和物理去重成本，`native_index` 从配置树而非计费descriptor取原生包络；`rendering/tokyo_canonical_overlay.gd` / `_load_archive` 精确目录门、`_setup_geometry` 缓存只读索引、`_select_cut` 仅完整LOD4候选、`debug_state` 次数/耗时。`tests/test_tokyo_cut_reuse.gd` / `run` 覆盖成本/归属/完整性/档位/不可变及真实数组/descriptor结构反例，接原focused与all。`tests/tokyo_canonical_review.gd` / `run` 显式NEAR_DOMINANCE_REVIEW保留21位并追加full4六位。原生几何/AO不修改，候选默认关闭。

R143完整目录近层接入：`tests/build_tokyo_street_catalog.gd` / `recipe` / `selected` / `valid_rows` / `inputs` / `run` / `_finish` / `audit` 复用R139差集与切线，显式STREET_NEAR_CATALOG只改北岸LOD5低楼；`tests/test_tokyo_street_catalog.gd` / `run` 覆盖两种配方及JSON矩阵。`tools/revalidate_tokyo_auxiliary.py` / `digest` / `same_ao_source` / `revalidate` 逐摘要/有向三角多重集复核后另存AO/固定图块清单，不重烘；`tools/test_tokyo_auxiliary_revalidation.py` / `test_native_window_identity_and_multiplicity` 拒绝范围/高度/绕序/归属/数量变化。`rendering/tokyo_canonical_catalog.gd` / `UNCHANGED_FIXED_LOD12_CATALOGS` 限定两份已审计来源，`tokyo_canonical_overlay.gd` / `_load_archive` 和 `tokyo_fixed_atlas_layer.gd` / `manifest_row` 消费；图块反例沿用 `tests/test_tokyo_fixed_atlas_layer.gd` / `checks`。`tests/tokyo_volume_combat_runner.gd` / `_ready` 显式BENCH_CLOSE扩近景专项，普通near与C1保持。真实证据见工程审计，不推广默认。

R142近景分组候选：`tools/build_tokyo_block_lod.py` / `contract` / `prepare` 的district24street保留原near误差，复用`road_components`改变初始分组，district24street45再用`shape_acceptable`筛合并形状；`tests/build_tokyo_far_clusters.gd` / `group_limit` / `_convert` 严审原生同源/高度/4点轮廓；`tools/audit_tokyo_far_clusters.py` / `audit` 独立几何与同位像素门。反例`tools/test_tokyo_block_lod.py` / `test_near_street_keeps_existing_near_contract` / `test_near_street_shape_filter_only_restricts_new_groups`及`tests/test_tokyo_far_clusters.gd` / `run`。离线候选，不改正式目录或旧AO。

R141显式备用复用候选：`experiments/tokyo_guarded_pair_reuse.gd` / `family` / `choose` 校验统一家族、同源空间身份、完整投影覆盖与真实联合预算；`rendering/tokyo_canonical_overlay.gd` / `_setup_geometry` 缓存跨档配对，`_prepare_target` 仅超额时替换备用元数据，原流送事务仍拥有资源；`debug_state` / `_restore_original` 记录实际备用家族与检查耗时。`tests/test_tokyo_cut_reuse.gd` / `run` 反例；`tests/tokyo_canonical_review.gd` / `run` 显式追加同序突然放大/缩回/跨区四机位。候选未推广默认，不能用降低峰值冒充通过硬门。

R141同历史与跨档备用诊断：`tests/tokyo_preload_route_probe.gd` / `run` 的显式AO_STRENGTH_REVIEW=0只跳过额外强度机位并登记，保留加载/预算/区域/退出门；`tests/tokyo_canonical_cut_probe.gd` / `handoffs` 从实际恢复快照比较原同分割、增量切面与统一更细备用家族，输出near_contract_proven=false，不接运行时。正式恢复权威仍在`rendering/tokyo_cluster_overlay.gd` / `_prepare_target`和`rendering/tokyo_canonical_overlay.gd` / `_restore_original`。

R141 AO联合接入：`experiments/tokyo_baked_ao.gd` / `track_material` / `strength` / `close` 弱引用同步衍生材质；`rendering/tokyo_fixed_atlas_layer.gd` / `bind` 登记同纹理材质。`tests/tokyo_preloaded_ao_review.gd` / `fixed_atlas_bytes` / `cancelled_loading` / `run` 联合暖绘预算、取消释放与远近强度；`tools/audit_tokyo_ao_preload.py` / `fixed_atlas_bytes` / `audit` 独立像素/预算复核，反例见`test_tokyo_ao`的GDScript/Python入口。

R141显式自动接入：`rendering/tokyo_fixed_atlas_layer.gd` / `shader_code` / `plane` / `eligible` / `manifest_row` / `bind` / `warm_ready` / `suspend` / `update` / `close` 父11预载一次、完整固定层门、近景/退出恢复；`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `lifecycle` 反例与跨帧释放。复用`tokyo_tile_ground_overlay`几何tick/计数、`tokyo_volume_preload`身份/暖绘门和`tokyo_draw_geometry_probe`独立提交计数；非正式默认，真实路线/实战证据与未过门项见工程审计。

R141远景固定层图块：`tests/export_tokyo_fixed_mesh.gd` / `run` 现目录只读来源，`tools/build_tokyo_fixed_atlas.py` / `read_native` / `validate` / `reduce_rgba` / `mip_bytes` / `raster` / `build` 双分辨率最高面/预乘面积滤波与显式未验GPU/扁平高度；`tools/test_tokyo_fixed_atlas.py` / `FixedAtlasTests` 拒绝来源语义和清晰度退化。

R141压缩与原生对拍：`tests/build_tokyo_fixed_atlas_bc3.gd` / `run` 两档BC3实际mip字节/解码误差；`tests/tokyo_fixed_atlas_review.gd` / `shader_code` / `plane` / `run` 显式原生地表控制、正面绕序、真实图元统计、两档/近景拒绝/恢复及纹理弱引用释放，经`tokyo_preload_route_probe`接加载菜单。`test_tokyo_tile_ground`覆盖编译与shader漂移/叠加拒绝，未接正式流送。

R140新西片AO：`tests/export_tokyo_ao.gd` / `region_for` 显式west_extension_density，`tests/test_tokyo_ao.gd` / `run` 守旧选区及新四片范围；沿现有真实规范向上面导出、预烘焙、BC4/高度位打包、GPU解码与预载路线，不新增正式tick。

R140加载取消预算修正：`tests/tokyo_preloaded_ao_review.gd` / `cancelled_loading` / `warmup_bytes` 独立计512KiB暖绘视口的活跃/退出定额，并跨帧核验弱引用释放；`tests/test_tokyo_ao.gd` / `run` 覆盖少计、缺失与queued-free状态，不放宽共同预算。

R139归属补正：`build_tokyo_street_catalog.gd` / `without_transferred` / `disjoint_transferred` 核对旧转交来源先从新旧北岸各移除一次，禁止组含转交来源；`tokyo_canonical_review.gd` / `run` 显式STREET_REVIEW保留西区11机位并追加北岸远近、旋转接缝及返回总览。

R139四片北岸远档替换：`tests/build_tokyo_street_catalog.gd` / `selected` / `valid_rows` / `replace_low` / `inputs` / `run` / `_finish` / `audit` / `_audit_entry` 精确减旧北岸加新街坊、保留西区余量与其他层/配置、沿原切线写入并独立保存审计。`tests/test_tokyo_street_catalog.gd` / `run` / `_check` 经Far测试接focused/all，覆盖来源矩阵和跨区差集反例；`tokyo_cells_lifecycle_runner.gd` 的显式STREET_CATALOG只选择制作工具，不改变正式运行时。

R138邻接街坊候选：`tools/build_tokyo_block_lod.py` / `road_components` / `prepare` 先按结构障碍分隔邻接图，再走既有占地拒绝门；`tools/test_tokyo_block_lod.py` / `test_street_components_cross_grid_not_road` / `test_street_profiles_keep_source_and_structural_anchors` 为跨格/路障/高度/确定性反例。`tests/build_tokyo_far_clusters.gd` / `group_limit` 与 `tests/test_tokyo_far_clusters.gd` / `run` 显式两档原生合同；`tools/audit_tokyo_far_clusters.py` / `audit` 独立查实际接受组与像素，不扩大到近景。

R137岸线真实暖绘：`rendering/tokyo_shoreline_warmup.gd` / `configure` / `_ready` / `_after_draw` / `close` / `_exit_tree` 独立小视口、同Shader样本、真实提交与共同预算释放；`rendering/tokyo_shoreline_layer.gd` / `start_material_warm` / `material_warm_ready` / `close` 持有弱引用和纯值报告；`rendering/tokyo_tile_ground_overlay.gd` / `_setup_geometry` 初始化接入，`rendering/tokyo_volume_preload.gd` / `_process` 放行门；`tests/test_tokyo_shoreline_layer.gd` / `_material_warm_lifecycle` 覆盖预算/空绘制/Shader身份/像素与取消跨帧释放。

R136后端峰定位：`tests/tokyo_render_trace.gd` / `setup`可选飞机视口；`retain_backend_peaks`独立保存固定指标峰及读回序号，不声称同帧。`tests/test_perf_frame_trace.gd` / `_test_backend_peaks`验证快照解耦、无效值、已释放视口和关闭清理。

R135四片规范候选：`tests/build_tokyo_extension_catalog.gd` / `_prepare` / `run` / `_finish_extension` / `audit`继承regional_catalog原切线/组件写入，仅父11精确边界差集与新片合入，独立核对三角守恒/全部页/覆盖。`rendering/tokyo_canonical_catalog.gd` / `extension_valid`接受明确west_corridor身份；`tests/test_tokyo_regional_native.gd` / `_extension_contract`反例。`tokyo_canonical_review.gd` / `run`显式EXTENSION_REVIEW同位11机位；`tokyo_volume_combat_runner.gd` / `_ready`显式BENCH_WEST_EXTENSION只移动标准36人专项锚点。

R134未改区独立复验：`tests/audit_tokyo_regional_native.gd` / `compare_previous`经REGIONAL_STABLE_OUTPUT显式入口，比较旧北岸/横滨224档的所有导出属性、打包surface和解码数组（含原形备用）；不把Resource文件SHA差异直接等同几何改变。

R134多片离线原生：`tests/build_tokyo_regional_native.gd` / `valid_routes` / `read_routes` / `run`支持显式REGIONAL_ROUTES且保留旧三片默认；`tests/audit_tokyo_regional_native.gd` / `run`独立按同摘要路由重载全部区域并再验原来源。`tests/build_tokyo_owned_region_blocks.gd` / `valid_config` / `run`显式REGIONAL_BLOCK_CONFIG分片迁移并累积block_transfers，不改变既有差集/造型/预算；`tests/test_tokyo_regional_native.gd` / `_routes_contract`覆盖缺区、额外区、重复、错误摘要及类型/路径拒绝。

R133独立新区色板：`tests/build_tokyo_region_surface.gd` / `region_for`给出旧默认或显式west_extension，`run` / `append_upward`共享同一选区；`tests/build_tokyo_cells.gd` / `run`只传显式REGION_SURFACE_REGION，`tests/test_tokyo_cells.gd` / `run`守旧默认与未知名称拒绝。不改变规范AO身份门。

R131西片AO：`tests/export_tokyo_ao.gd` / `region_for`增加显式west_density，`tests/test_tokyo_ao.gd` / `run`守坐标与旧选区不变。`tests/tokyo_preloaded_ao_review.gd` / `run`复用规范相机/源瓦片稳定门，暂停观察时保留源瓦片加载，退出恢复process_mode；不改变实际战斗等待。

R130步道远档：`tests/build_tokyo_path_lod.gd` / `run` / `partition` / `subset` / `_finish_catalog`从R129仅生成LOD0–2 full的步道省略固定层；`audit` / `_audit_entry`重载624改变页，核对原生选择、未选配置、组件与coverage。`tests/build_tokyo_block_catalog.gd` / `_replace_layer`复用原切线，只开放低层或固定层替换且逐数组守住其他两层；旧`_replace`继续固定调用低层。`tests/test_tokyo_regional_native.gd` / `_path_lod_contract`覆盖选择/原始数组/索引布局/非法层及surface拒绝。

R129观察场源就绪：`tests/tokyo_canonical_review.gd` / `source_state_ready` / `source_ready`要求源瓦片无待载/缺块、档位一致且可见瓦片淡入完成，再作稳定像素对照；`test_tokyo_regional_native.gd` / `_extension_contract`覆盖待载、缺块和档位未到位反例。只用于显式观察场，真实战斗不等待此门。

R129近景轮廓备用：`tests/build_tokyo_guarded_blocks.gd` / `run` / `group_meshes` / `_save`仅按R111原分组替换北岸LOD0–3备用低层；`audit`独立重载目录、组件、coverage并核对标高/固定层和所有full/mid不变。`tests/test_tokyo_regional_native.gd` / `_guarded_blocks_contract`拒绝高度/调色板/身份及实际float32轮廓漂移；`tests/tokyo_canonical_review.gd` / `run`显式GUARDED_REVIEW抓首个新相机原生帧及稳态图。

R128覆盖反事实与就绪修正：`experiments/tokyo_tile_coverage.gd` / `visible_flat_covered`反推视野内的平坦源范围；`tokyo_tile_ground_candidate` / `resume_fixed`仅显式观察场开关进行对拍（运行时未启用，九机位零收益）。`tests/tokyo_visible_ground_review.gd` / `run`在正式加载路线做同帧源材质/关闭/开启/恢复及实际面数对照；`test_tokyo_tile_ground` / `run`覆盖缝隙/高度投影/非法输入。`tokyo_canonical_review` / `ready_at_canvas` / `run`要求实际相机匹配且绘制帧稳定200ms；`test_tokyo_regional_native` / `_extension_contract`拒绝旧相机就绪。`tokyo_tile_ground_overlay` / `_capture_submission_peak`同峰保存源瓦片和地表状态，区别清晰度兜底与有效借用。

R127三片联合候选：`tests/build_tokyo_regional_catalog.gd` / `run` / `_west_meshes` / `_load` / `_replace` 合并父3/11并重建组件/覆盖身份，`audit`逐页重载比较所有三层；`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`有效扩展时复制表现索引，不改共享R34。`test_tokyo_regional_native` / `_extension_contract`；`tokyo_canonical_review` / `run`显式REGIONAL_REVIEW九机位与24万面硬门，由`tokyo_preload_route_probe` / `run`接正式加载路线；`tokyo_volume_combat_runner` / `_ready`显式BENCH_WEST保留原36人负载，仅移动地图专项锚点。

R126旧边界迁移：`experiments/tokyo_packed_mesh_difference.gd` / `supported` / `subtract` / `conserved`支持16/32位索引及独立解码守恒；`tests/build_tokyo_boundary_transfer.gd` / `run` / `target_meshes` / `audit`按来源ID和各档真实原形导出旧规范父包差集组件，独立重载证明守恒且移除面不接触游戏楼，不产出规范目录。`tests/test_tokyo_regional_native.gd` / `_difference_contract`验证重数/索引宽度/缺面/输入不变。

R125街坊唯一归属：`tests/build_tokyo_owned_region_blocks.gd` / `run` / `disjoint_groups` / `transfer`核对原计划组不触及非owner、重建候选并原生字节差集迁移五档，复用R123三片清单/独立原生审计；`tests/test_tokyo_regional_native.gd` / `run` / `_transfer_contract` / `_toy_cell`补混合owner/重复/未知组及原生迁移不变性反例。

R124游戏楼保护：`tests/tokyo_region_gameplay_guard.gd` / `read_source` / `inspect_bounds` / `include_points` / `write_audit`共用正式接受顺序和碰撞摘要，实际来源/合并顶点扩展保守区域相交门；`tests/build_tokyo_region_blocks.gd` / `run`在输出前拒绝含游戏楼的独立合并，`tests/test_tokyo_regional_native.gd` / `run` / `_compare_candidate`覆盖跨界/包含/共边/非法范围、当前真实来源及五档保存重载不变。

R123三片原生归属：`tests/build_tokyo_regional_native.gd` / `run` / `supported` / `triangle_packets` / `subtract` / `conserved` 认证原生基线并精确裁取非owner三角字节；`tests/audit_tokyo_regional_native.gd` / `run` 独立进程审计336档包/48固定层、来源/原高/父子组。`tests/test_tokyo_regional_native.gd` / `run` / `_check` 新focused/all入口`tokyo_regional_native`，不接正式规范流送。

R122新区色板/AO：`tests/build_tokyo_region_surface.gd` / `run` / `append_upward` 保存128归档逐数组色板审计并导出真实向上面；`tools/build_tokyo_ao.py` / `source_identity` / `build` 明确独立index身份，`tools/test_tokyo_ao.py` / `test_independent_source_does_not_claim_catalog`拒绝伪造规范身份。`tests/tokyo_region_surface_review.gd` / `run` 经`tokyo_cells_visual`显式入口复用正式surface/AO shader对拍，仍非规范合成器或流送验收。

R121形状修整：`tools/build_tokyo_block_lod.py` / `shape_acceptable` / `choose` / `prepare` 仅独立来源可显式选择角度/长宽比/最短边策略；原profile和默认行为不变。`tools/test_tokyo_block_lod.py` / `test_shape_policy_rejects_spikes_not_source`验证尖角、长条、短边、确定性、来源不变及非法策略拒绝。原生与固定观察复用R120，不改运行时。

R120独立新区样片：`tests/build_tokyo_cells.gd` / `run` / `valid_sample_output` 仅regional_sample允许未占用的tmp来源同级输出；`tests/audit_tokyo_region_sample.gd` / `run` / `same_mesh`重载七档逐数组重建及导出真实成本；`tests/tokyo_cells_visual.gd` / `_load_geometry` / `_capture_sample`使用自身范围的无动态阴影基线/瓦片/还原固定观察。并未接第三片生产归属或性能门。

R120街坊B：`tools/build_tokyo_block_lod.py` / `prepare`显式region=None接受无owner完整来源、拒绝已有owner；`tools/test_tokyo_block_lod.py` / `test_standalone_does_not_reinterpret_joined_ownership`反例。`tests/build_tokyo_far_clusters.gd` / `_convert`显式原色分支仍逐面验证，默认旧路径不变；`tests/build_tokyo_region_blocks.gd` / `run`继承单区基线、保存复验五档低层替换，不改标高/地表与三片归属。

R118岸线接线：`rendering/tokyo_shoreline_layer.gd` / `manifest_bytes` / `valid_morph_mesh` / `morph_factor` / `morph_shader_code` / `bind` / `update` / `_show_warm` / `warm_draw` / `close` 支持显式schema2四网格、一次共用变宽与双备用过渡；联合包围盒和三辅助节点显式计数。`tests/tokyo_shoreline_runtime_review.gd` / `run` 从实际UV/uniform投影；`tests/tokyo_preloaded_ao_review.gd` / `shoreline_bytes` 独立计四网格预算；`tests/test_tokyo_shoreline_layer.gd` / `checks` / `lifecycle` 真实加载/静止/预热/释放，`tests/test_tokyo_ao.gd` / `run` JSON数字与额度反例；`rendering/tokyo_tile_ground_overlay.gd` / `debug_state` 分列规范池和辅助池，不把原48规范槽偷改为总节点预算。

R117原生岸线候选：`experiments/tokyo_shoreline_morph_candidate.gd` / `factor` / `shader_code` / `valid_point` / `area` / `orientation_safe` / `build_mesh` 制作共拓扑UV位移网格与三档备用；`tests/build_tokyo_shoreline_morph.gd` / `numbers_equal` / `run` 逐数值合同、保存重载、身份/成本与原生数组导出；`tests/test_tokyo_shoreline_morph.gd` / `fixture` / `checks` 覆盖异常输入、索引、翻面、AABB及着色顺序，由原地表focused/all消费。显式制作入口 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready`，不替换旧岸线加载器。

R116岸线共拓扑离线计划：`tools/build_tokyo_shoreline_morph.py` / `load_source` / `build_plan` / `scoped_shape` / `candidate` / `ring_match` / `orientation_safe` / `coverage` / `fixed_mesh` 校验同源三宽度、分量对应、全区间朝向与采样覆盖，失败分量保留三档原生精度备用；`tools/test_tokyo_shoreline_morph.py` / `MorphTests` 覆盖直线、岛洞、分裂、裁切、Float32和中间翻面反例。仅离线，未接生产。

R115收尾CPU分桶：`rendering/tokyo_tile_ground_overlay.gd` / `_record_submission_peak` 包裹 `_capture_submission_peak`，绘制前异步收尾仍计入原tokyo_map_process根桶，tokyo_map_submission只作明细，避免帧时间比重因移动调用栈而漏算。

R115同帧通知合并：`rendering/tokyo_tile_ground_overlay.gd` / `_queue_submission_peak` 仅变化时注册one-shot绘制前计数，停用/退出撤销；`tests/tokyo_draw_geometry_probe.gd` / `_verify_report` 以pre_draw独立节点数在post_draw核验报告，避免回调注册顺序误报。

R115最终提交峰：`rendering/tokyo_tile_ground_overlay.gd` / `_record_submission_peak` / `_step_geometry` / `_release_tile_ground` / `_deactivate` / `debug_state` 区分准备峰与绘制前终态提交峰，外部瓦片退役也排队一次；`tests/test_tokyo_tile_ground.gd` / `_test_submission_peak` 反例、`tests/test_tokyo_shoreline_layer.gd` / `lifecycle` 保持真实超限失败；`tests/tokyo_draw_geometry_probe.gd` / `capture` / `summary` 逐绘制边界查漏报，未改资源/阈值。

R114绘制边界诊断：`tests/tokyo_draw_geometry_probe.gd` / `setup` / `capture` / `close` / `summary` 为显式bench纯值层计数和弱引用清理；`tests/tokyo_volume_combat_runner.gd` / `_ready` / `_bench_finish_now` 接入，`tests/tokyo_cells_lifecycle_case.gd` / `run` 验真实可见网格、停更跳过、释放后回调与幂等关闭。不修改生产峰值或称GPU证明。

R114远景街坊：`tools/build_tokyo_block_lod.py` / `prepare` / `choose` 与 `tests/build_tokyo_far_clusters.gd` / `group_limit` 增加far8wide/far12wide独立远档合同；`tools/test_tokyo_block_lod.py` / `test_wide_far_preserves_anchors_and_scale`、`tests/test_tokyo_far_clusters.gd` / `run` 检查原高、结构、四点和跨档拒绝；`tools/audit_tokyo_far_clusters.py` / `audit` 检验实际原生组。未接规范目录或改变中近档。

R113远景道路准备：`tools/build_tokyo_road_lod.py` / `locked_points` / `simplify_locked` / `stroke` / `topology` / `accept_shape` / `prepare` / `main` 只保存来源线形计划，端点/共享节点、原宽度、Float32占地、连通/孔洞与障碍/候选间交叠门；`tools/test_tokyo_road_lod.py` / `RoadLODTests` / `fixture` 为离线反例。未做原生固定层重建或运行接线，不把来源面估算称实际减面。

R112异步旧目标精度门：`rendering/tokyo_canonical_overlay.gd` / `_step_geometry` 同时审当前/待提交切面的实际尺度，过期目标立即重选不等时钟；`tests/tokyo_canonical_lifecycle_case.gd` / `run` 真实原形在场+旧目标反例，`tests/tokyo_tile_stream_review.gd` / `run` 保存上限24条实际超尺度绘制纯值记录。

R112四点街坊集成：`tests/build_tokyo_block_catalog.gd` / `input_paths` / `valid_plan_rows` / `matched_baseline_rows` / `run` 仅显式district24wide从R109完整目录替换R106最细低楼，保留mid6与其他档；`tests/test_tokyo_block_catalog.gd` / `run` 拒绝混合路由、旧新来源漂移、跨档及未选候选。新目录AO由既有真实最高档导出/重烘链生成。

R111近景候选：`tools/build_tokyo_block_lod.py` / `choose` / `prepare` 与 `tests/build_tokyo_far_clusters.gd` / `group_limit` / `_convert` 为district20/24及20wide/24wide独立合同；新组至少四点，wide四级闭合半径仅离线使用。`tools/test_tokyo_block_lod.py` / `test_wide_near_deterministic_and_four_corners` 与 `tests/test_tokyo_far_clusters.gd` / `run` 约束结构、原高、跨档、步骤漂移及三角形拒绝；`tools/audit_tokyo_far_clusters.py` / `audit` 核对实际接受组。旧profile/生产目录不改。

R110交接诊断：`rendering/tokyo_canonical_overlay.gd` / `_restore_original` 显式RESTORE_TRACE最多32条值快照，不在实战内跑替代求解；`tests/tokyo_canonical_cut_probe.gd` / `run` / `handoffs` 读取实际组件额度和快照离线比较。`experiments/tokyo_cut_reuse.gd` / `corresponding_cut` / `_corresponding` / `incremental_parents` / `_incremental_entry` 只读同空间身份翻译与增量成本；`tests/test_tokyo_cut_reuse.gd` / `run` 反例，`tokyo_cells_lifecycle_runner` / `_ready` 显式focused入口。诊断结果不能绕过完整覆盖、原形备用、预算或Visual门。

R109中档来源链：`tests/build_tokyo_block_catalog.gd` / `middle_source_chain` 认证R44 full既有轻概括的原形与R34候选原形，随后当前规范低层仍须逐面等于R44；`tests/test_tokyo_block_catalog.gd` / `run` 覆盖原高/ID/档位/低层及标高网格漂移。

R109中档集成：`tests/build_tokyo_block_catalog.gd` / `input_paths` / `valid_plan_rows` 仅mid6从R107规范目录认证原LOD4_full来源并替换；`test_tokyo_block_catalog` / `run` 反例。`tokyo_tile_stream_review` / `run` 记录真实新LOD4绘制与上界；`tokyo_district_finish_review` / `run` 追加原宽视角/最细/返回机位。

R108中档街坊：`tests/export_tokyo_far_costs.gd` / `run` 导出真实LOD4成本；`tools/build_tokyo_block_lod.py` / `prepare` 与 `tests/build_tokyo_far_clusters.gd` / `selected_levels` / `maximum_scale` / `group_limit` 仅mid4/mid6显式进入LOD4。`tools/test_tokyo_block_lod.py` / `test_middle_contract_preserves_anchors_and_rejects_other_scales`、`test_tokyo_far_clusters` / `run` 覆盖结构/跨档合同；`tokyo_far_cluster_review` / `run` 使用中档与退回近档固定机位，`tools/audit_tokyo_far_clusters.py` / `audit` 审查实际接受组。

R107强街坊集成：`tests/build_tokyo_block_catalog.gd` / `input_paths` / `matched_baseline_rows` / `valid_plan_rows` 显式district16三方核对并继承R103完整目录；`test_tokyo_block_catalog` 覆盖强近档来源/矩阵/模式漂移。`tokyo_tile_stream_review` / `run` 记录新LOD5实际draw，`tokyo_district_finish_review` / `run` 追加原受阻1.95宽机位及返回。

R106更强低楼街坊：`tools/build_tokyo_block_lod.py` / `prepare` / `contract` 增加最细档district12/district16；`tests/build_tokyo_far_clusters.gd` / `group_limit` 与 `tools/audit_tokyo_far_clusters.py` / `audit` 拒绝跨档/合同漂移；`tools/test_tokyo_block_lod.py` / `test_stronger_district_fills_small_gap_not_height_or_road` 验证概括幅度、原高及住宅道路保护。复用原生保存/静态对拍，不改变规范目录。

R105高度无损位打包：`tools/pack_tokyo_ao_bits.py` / `pack5` / `unpack5` / `build`，`tools/test_tokyo_ao_bits.py` 离线反例；`experiments/tokyo_height_bits.gd` / `storage_width` 与共享SHADER_CODE，`tokyo_baked_ao` / `row_bytes` / `make_shader` / `bind_ao` / `bind_preloaded` 只对显式R5编码取真实字节与GPU解码。`tests/tokyo_height_bits_visual.gd` / `run` 以实际GL核对全高度场及nearest边界，`tokyo_cells_lifecycle_runner` 显式HEIGHT_BITS_VISUAL入口；AO回归/取消/独立审计纳入R5预算。`tokyo_district_finish_review` 首阻塞点显式调用原容量探针。

R104联合衔接：`tests/tokyo_district_finish_review.gd` / `run` / `low_mask_code` / `replacement` / `restore` 在R103目录同实例比较普通楼试色与裸地源色组合，双绘黑白类别遮罩保留遮挡；`tokyo_preload_route_probe` 显式DISTRICT_FINISH_REVIEW，`test_tokyo_tile_ground` 编译/拒绝漂移门。无生产tick。

R103 AO联合预算：`tests/tokyo_preloaded_ao_review.gd` / `shoreline_bytes` / `run` 从实际三档岸线清单独立算三份额度；`tools/audit_tokyo_ao_preload.py` / `shoreline_bytes` 复核实际驻留面数与预约。反例 `tests/test_tokyo_ao.gd` / `run`，`tools/test_tokyo_ao.py` / `test_joint_shoreline_reservation`。

R103远景接线：`tests/build_tokyo_block_catalog.gd` / `input_paths` / `matched_baseline_rows` / `valid_plan_rows` 以R93完整目录继承近景，三方核对R78当前合并来源与R102 far6，按原切线重建336页；`tests/test_tokyo_block_catalog.gd` / `run` 覆盖混模式/跨来源/矩阵漂移。`tests/tokyo_tile_stream_review.gd` / `run` / `projected_check` 同位参考继承全区域bounds，源色检查隔离并恢复岸线。

R102远档街坊：`tools/build_tokyo_block_lod.py` / `prepare` 新增far4/far6且只准LOD1/2；`tests/build_tokyo_far_clusters.gd` / `group_limit` 与 `tools/audit_tokyo_far_clusters.py` / `audit` 拒绝跨到近档。`tools/test_tokyo_block_lod.py` / `test_far_district_scale_height_and_structural_contract` 与 `tests/test_tokyo_far_clusters.gd` / `run` 覆盖原高/结构/合同反例。

R101街区边界隔离：`tests/tokyo_district_boundary_review.gd` / `run` 固定机位分离低层/标高/全部建筑/借用瓦片/AO并还原，`tokyo_preload_route_probe` 显式DISTRICT_BOUNDARY_REVIEW接线；不作为隐藏建筑后的性能证明。

R101远景低楼试色：`experiments/tokyo_low_tone_candidate.gd` / `weight` / `shader_code` 仅北岸静态两版明度对照，近景原色、原高与轮廓不变；由边界review消费，不接生产tick。

R99实际显示审查：`tests/tokyo_shoreline_runtime_review.gd` / `cancelled_loading` / `run` 覆盖缺岸线拒绝、同实例三档/过渡/瓦片覆盖与恢复；`tests/tokyo_preload_route_probe.gd` / `run` 保存三档预热状态与菜单网格释放。

R99岸线流转：`rendering/tokyo_shoreline_layer.gd` / `levels` / `shader_code` / `bind` / `update` / `begin_warm` / `warm_draw` / `_show_warm` / `hide` / `close` 持有三档资源、两辅助节点与原Stream预约；`rendering/tokyo_tile_ground_overlay.gd` / `setup` / `_setup_geometry` / `_step_geometry` / `_deactivate` / `_exit_tree` / `debug_state` 接原地表更新。`rendering/tokyo_volume_preload.gd` 原start/take/_begin身份及warming回调预热三档；`tests/build_tokyo_shoreline_lod.gd` / `run` 离线保存，`tests/test_tokyo_shoreline_layer.gd` / `checks` / `lifecycle` 静态与真实释放反例。

R98静态岸线：`tools/build_tokyo_shoreline.py` / `collect` / `build` / `parts` / `f32` / `main` 裁切自然岸线、联合等宽网格、Float32审计；`tools/test_tokyo_shoreline.py` / `ShoreTests` / `surface` 反例。`experiments/tokyo_shoreline_candidate.gd` / `build` 原生消费；`tests/tokyo_shoreline_review.gd` / `run` 保存重载与多机位两线宽、mask、恢复。显式入口及focused复用 `tokyo_preload_route_probe` / `test_tokyo_tile_ground`。

R97近景水面候选：`tests/tokyo_water_palette_review.gd` / `run` 冻结首机位平坦源水色，仅水面源色/半量两版、四机位和恢复；`experiments/tokyo_ground_palette_candidate.gd` / `shader_code` 接显式范围和可选类别，默认原窗口与全类别行为保留。测试由 `tests/test_tokyo_tile_ground.gd` / `run` 及 `tests/tokyo_preload_route_probe.gd` / `run` 的显式WATER_PALETTE_REVIEW接线。

R96地表边界审查：`tests/tokyo_ground_boundary_review.gd` / `run` 在同一真实地图实例对比原生、局部同源、归档bounds同源并恢复，记录源图、投影角点、预算、碰撞与释放。`experiments/tokyo_tile_ground_candidate.gd` 新增 `valid_bounds`，`bind` 消费实例 `coverage_bounds`，默认旧窗口不变。入口为 `tests/tokyo_preload_route_probe.gd` / `run` 的显式GROUND_BOUNDARY_REVIEW；反例在 `tests/test_tokyo_tile_ground.gd` / `run`。

> 本节内容原在 CLAUDE.md，2026-05-05 移出。第一次进入仓库或不确定该查哪个索引时，先读
> [Reference Index](_INDEX.md)。本表只回答“哪个脚本负责、类是什么、关键入口有哪些”；按功能找精确锚点去
> [Code Index](code-index.md)，目录边界去 [Repository Layout](repo-layout.md)。

**路径约定**：表内 GDScript 路径默认相对 `scripts/`；同一文件的独立职责可拆成多行，但不得因此复制设计数值。
先在本表搜索文件名 / 类名 / 功能名，找到目标后只读取对应符号附近 50–100 行。只有本表未覆盖或需要验证跨文件引用时才用全仓库搜索。

**模式归属图例**：`[共享]` = 共享层；`[沙盒]` = 只在沙盒模式（**沙盒已废弃**，仅调试留存，验证不必再跑它）；`[生存]` = 只在生存模式（主玩法）。

**禁止**在共享层代码里写 `if in_survivor_mode` / `if in_sandbox`——模式隔离必须走参数资源 `duplicate(true)` 或 PlayableAircraft 档案注入。这条铁律在沙盒废弃后依然有效（它保护的是共享层干净，不是两模式对等）。

| 文件 | 类/类型 | 职责 | 关键入口 |
|------|---------|------|----------|
| `tests/build_tokyo_ao_bc4.gd` / `experiments/tokyo_baked_ao.gd` | 全分辨率AO离线压缩与显式读取 | [R91] 原R8各档完整mip压为BC4，保存重载/解压误差审计，高度索引与调色板不变；加载前按真实三份块数据计预算，RGTC能力及上传回读格式门，旧输入不变 | `run`；`bc4_mip_bytes` `row_bytes` `bind_preloaded` `bind_ao` |
| `tests/tokyo_cut_capacity_probe.gd` | 阻塞切面只读容量预检 | [R90] 显式真实阻塞快照，复用完整树前沿比较16/24/32槽及分两段交接物理并集；生产16槽选择一致且流送状态不变，非运行时上限修改或性能证明 | `run` `_state` `_query` `_pair_frontiers` |
| `rendering/projected_raster_tile.gd` | 静态投影瓦片节点 | [R82] MeshInstance2D单次绑定分行，不叠画Sprite；CPU世界行/UV与真实最大纹素尺寸，三维借用裁同一行段；原Raster保留唯一纹理生命周期 | `configure` `clipped_plane` |
| `experiments/tokyo_raster_projection.gd` / `tests/tokyo_georeference_review.gd` | 墨卡托源地理配准 / 实机诊断 | [R81/R82] 按实际bbox反解纬度、保持OSM/碰撞坐标；验证元数据与世界范围，静态分行Mesh对照仿射与重投影；不推广默认 | `metadata` `world_y` `raw_y` `mesh` `valid_for`；`run` `snapshot` |
| `experiments/tokyo_ground_palette_candidate.gd` / `tests/tokyo_ground_palette_review.gd` | 原生地表分类调色 / 无HUD源对照 | [R80/R83] 仅静态材质候选；内部中位色与配准后平坦源底色两种采样，统一RGB偏移保留类别相对色差；四版固定跨尺度对照，原网格/楼栋/碰撞/区外行为与恢复不变，不推广默认 | `shader_code` `vectors` `semantic_colors`；`run` `source_only` `sample_color` `source_flat` `mask_inside` |
| `experiments/tokyo_tile_ground_candidate.gd` / `tests/test_tokyo_tile_ground.gd` / `tests/tokyo_tile_ground_review.gd` | 同源地表候选 / 反例 / 实际路线对照 | [R71/R73/R76/R77] 当前瓦片Texture/参数/UV只读复用；1.25输出px清晰度、GL近黑补偿；完整覆盖时停固定层提交；实际瓦片矩形限制裁除，暂还原固定层并复用平面/材质；同源Shader跨租约缓存但不留纹理，原网格驻留/近景恢复 | `shader_code` `ground_code` `texture_resolved` `plane` `bind` `resume_fixed` `cached_shader` `suspend_fixed` `close`；`run` `lifecycle` `_check`；`run` `_wait_source` |
| `rendering/tokyo_tile_ground_overlay.gd` / `tests/tokyo_tile_stream_review.gd` | 规范地图派生候选 / 连续路线审查 | [R77/R79/R82] 复用原几何tick，源变更前释放借用；源投影几何纳入联合预算并在退出前归还；连续绘制审查和独立相交/2D源像素核对，不推广默认 | `_sync_tile_source` `_release_tile_ground` `_step_geometry` `_deactivate` `_release_projection_reserve` `_exit_tree` `debug_state`；`run` `projected_check` |
| `survivor/raster_basemap_renderer.gd`（R82 接线） | 唯一瓦片纹理所有者的可选投影节点 | 默认Sprite不变；候选静态网格缓存世界行与UV，拒绝错误来源及超额几何；对象缓存先验证存活 | `_new_tile_node` `_prepare_tile_node` `projected_geometry_bytes` |
| `experiments/tokyo_tile_coverage.gd` | 精确矩形覆盖 | [R76] 逐瓦片扣除未覆盖矩形；缺口/重复面积/无效参数/超高固定结构拒绝，不用包络或面积和替代覆盖 | `covered` `flat_covered` |
| `experiments/tokyo_canvas_color.gd` / `tests/tokyo_ground_color_probe.gd` / `tests/export_tokyo_fixed_mesh.gd` | GL同色桥接 / 因素隔离 / 固定层来源 | [R73] 显式候选逆补偿GL近黑往返；原生灰阶、接影无投影同色及材质因素对照；只读16父包固定层XYZ/法线/RGBA二进制与SHA，不据审计删面 | `finish` `input_for`；`run`；`run` |
| `experiments/tokyo_low_light_candidate.gd` | 北岸低楼静态试色 | [R74] 原轮廓/高度不变；仅ROI单太阳75/25或90/10，范围外保持原shader；`tokyo_tile_ground_review` 显式逐层隔离/两试色/恢复，不推广 | `shader_code` |
| `tests/build_tokyo_block_catalog.gd` / `tests/test_tokyo_block_catalog.gd` | 街坊规范空间目录制作 / 覆盖迁移反例 | [R79/R85/R89/R93] 默认远档，显式LOD3继承R79、LOD5继承R85；额外district8开关仅选已审最细街坊，计划SHA/合同与完整矩阵门；核对源高/父区/标高，沿原切线重分并导出北岸AO，其他配置不变 | `run` `input_paths` `valid_plan_rows` `_load` `_replace` `remap_tokens` `rewrite_coverage`；`run` `_check` |
| `rendering/tokyo_mesh_component.gd` / `rendering/tokyo_component_manifest.gd` / `rendering/tokyo_component_stream.gd` | 物理组件 / 值清单 / 唯一Stream适配 | [R69/R72显式候选] 物理层独立退役；schema1保留LOD2双组合，schema2要求声明配置完整覆盖，支持三层组件跨LOD共享；逻辑页保留原coverage身份，唯一Stream计账 | `valid` `stream_identity`；`read` `valid_row` `complete_coverage`；`configure` `request` `_paths` `resource` `close` `summary` |
| `tests/build_tokyo_cross_lod_components.gd` / `tests/test_tokyo_cross_lod_components.gd` | 全组合组件制作 / 反例与跨LOD终态 | [R72] 逐页验证原目录SHA/身份，以层及原生打包数据/AABB索引；摘要命中后重载对拍数组，所有逻辑来源保留；跨LOD固定层共享及独立释放验证 | `mesh_key` `run` `_collect`；`run` `lifecycle` `_check` |
| `tests/build_tokyo_mesh_components.gd` / `tests/test_tokyo_components.gd` / `tests/tokyo_component_review.gd` | 制作 / 反例及终态 / 正式路线原图对照 | [R69] 623原生组件承载416逻辑页；实际退役、保留共享层、无重读及pending退出；近远旋转与原页逐数组/像素比较，双份几何先预留后释放 | `run` `_save`；`run` `lifecycle` `_check`；`run` |
| `rendering/tokyo_shared_page.gd` | Resource | [R68准备] 普通/原形同空间双组合共用真实Mesh池、独立存储身份与逻辑槽位；不冒充旧规范单页 | `valid` `stream_identity` `variant_meshes` |
| `tests/build_tokyo_shared_pages.gd` / `tests/test_tokyo_shared_page.gd` / `tests/tokyo_shared_stream_case.gd` | 离线制作 / 反例 / 原生加载终态 | [R68未推广] 原packed完全相等才共用、逐源保存重载；唯一Stream实际加载208包与16根驻留、真实在途退出和弱引用释放；AO只预留额度，非地图Visual | `run` `_pair` `same_mesh`；`run` `_check`；`run` `_inspect` |
| `tests/tokyo_low_roof_candidate.gd` | 离线原生低层候选 | [R67未推广] LOD2原形备用屋顶导出/精确合并计划烘焙，保留标高和固定层、源SHA、碰撞与打包属性；不改流送目录 | `run` `_export` `_bake` |
| `experiments/tokyo_baked_ao.gd` / `rendering/tokyo_cell_stream.gd` | 预热纹理所有者 / 共同预算 | [R66候选] 解码前登记纹理保守额，几何请求/领取与规范完整切面均消费剩余额度，退出等纹理与在途排空；Loading领取同一AO实例与mip链 | `bind_preloaded` `close`；`geometry_budget` `reserve_auxiliary` `release_auxiliary` `summary` |
| `tests/tokyo_preloaded_ao_review.gd` / `tools/audit_tokyo_ao_preload.py` | 真实Loading取消与远近检查 / 独立审计 | [R66/R86/R93] 在途取消、缺AO拒绝；九机位三强度与恢复、同资源/几何/碰撞、区外像素和亮度单调，计投影额度及菜单释放；屏外矩形先裁剪拒绝负索引回绕；非全湾或帧时间证明 | `cancelled_loading` `run`；`screen_mask` `audit` |
| `tests/tokyo_ao_review.gd` | 同位AO/高度误差隔离 | [R65] 显式交叉绑定两档AO和接收高度，双档合计预算与原图恢复；不把事件级材质绑定当连续流送/预热已完成 | `run` `_capture` |
| `tools/pack_tokyo_ao_height.py` / `tools/test_tokyo_ao_palette.py` | 精细接收高度无损压缩 | [R65] 原高度码全局R8索引、256项RG16调色板，各档共用2048高度；逐像素往返校验、超256码拒绝不量化 | `pack` `build`；`PaletteTests` |
| `experiments/volume_ground_catalog.gd` | RefCounted | [正式共享] 已完成地面机身与活动部件的双档缓存几何；不拥有玩法 | `keys` `key_for` `build` `_cylinder` `_strategic` `_chassis` `_turret` `_cells` `_wheel` `_carrier` `_train` |
| `experiments/volume_ground_presenter.gd` | RefCounted | [正式共享] 弱引用、阵营色、画面 LOD、真实部件转向、损毁与二维恢复 | `refresh_members` `restore` `_set_override` `sync` `_emit` `detail_mode_for` `body_color_for` `_markers` `_parts` |
| `rendering/ground_volume_foreground.gd` | Node2D | [正式共享] 火车护甲/弱点批量前景，位于三维合成之上 | `sync` `_draw` |
| `tests/test_volume_ground.gd` / `tests/volume_ground_lifecycle_case.gd` / `tests/volume_ground_runtime_runner.gd` | focused / lifecycle / Visual | 地面目录、真实伤害终态、正式合成与甲板驻机；不代表完整局或性能毕业 | `run` `_check`；`run` `_check`；`_ready` `_ground` `_create_enemy` `_capture` `_clear` `_run` `_check` |
| `tests/export_tokyo_ao.gd` / `tools/build_tokyo_ao.py` / `tools/test_tokyo_ao.py` / `tools/audit_tokyo_ao.py` | 真实几何导出 / 离线AO / 反例 / 审计 | [R64/R86局部候选] 默认南部或显式北岸密集片，未知区域拒绝；规范LOD5原生向上面、地平线积分、分档R8遮蔽与接收高度，不改楼体/碰撞，独立源SHA与像素审计 | `run` `region_for`；`height_field` `horizon_ao` `encode_height` `build`；`AOTests`；`audit` |
| `experiments/tokyo_baked_ao.gd` / `tests/test_tokyo_ao.gd` / `tests/tokyo_ao_review.gd` | 局部材质候选 / focused及终态 / 正式路线对拍 | [R64未推广] 原材质槽绑定与回滚，仅补光AO、来源高度/法线门、纹理与几何合计预算；真实多机位无AO/双强度/恢复；不冒充连续共享流送和Loading预热 | `make_shader` `bind_ao` `strength` `close`；`run` `lifecycle` `_check`；`run` `_capture` |
| `tests/export_tokyo_canonical_roofs.gd` | 完整父包离线来源 | [R51] 六LOD、mid及远档备用组合的16父包屋顶，保持48游戏街区与碰撞摘要，不依赖镜头可见节点 | `run` `_extract` |
| `tools/build_tokyo_canonical_roofs.py` / `tools/test_tokyo_canonical_roofs.py` | 相机无关共同分区 / 反例 | [R51] 按原生路径/层/备用/原面排序，拒绝父块或来源缺重，反向来源顺序复验确定性；沿用R50几何门 | `canonicalize` `generate` `digest` `main`；`fixture` `CanonicalTests` |
| `tests/build_tokyo_canonical_roofs.gd` | 独立父包制作与审计 | [R51] 由计划manifest逐组验证摘要、生成原生保存包并在独立进程审计；不接生产流送 | `run` |
| `tools/build_tokyo_spatial_roof_plan.py` / `tools/test_tokyo_spatial_roof_plan.py` | 固定街区归属与反例 | [R52] LOD5同高交集优先，重叠父范围明确后备；11组复用唯一归属且几何不变 | `geometry` `ownership` `partition` `main`；`fixture` `SpatialOwnershipTests` |
| `experiments/tokyo_packed_mesh_join.gd` / `tests/test_tokyo_packed_mesh_join.gd` | 原生单surface无损拼合 | [R52] 保留打包属性，索引扩容，有向三角重数/属性守恒；不增加绘制节点 | `join` `signatures` `conserved`；`run` `_check` |
| `experiments/tokyo_packed_mesh_reindex.gd` / `tests/build_tokyo_reindexed_near.gd` | 离线精确顶点复用 / 八包保存后审计 | [R88未接线] 逐角顺序/打包属性守恒，颜色/法线接缝不焊接；真实北岸LOD5节省0 | `repack` `_read` `_corner` `corner_digest` `decoded_bytes`；`run` |
| `rendering/tokyo_canonical_spatial_page.gd` | 独立规范空间资源 | [R52/R54] 完整三层、组合/层级/来源/碰撞身份验证；显式规范身份接单一Stream，不伪造旧楼高哈希 | `valid` `stream_identity` |
| `rendering/tokyo_canonical_catalog.gd` | Resource | [R54准备] 11组合轻量目录，校验2288页的层级、唯一归属/路径、三层包络及规范身份；不内嵌网格 | `valid` `_entry_valid` |
| `rendering/tokyo_canonical_overlay.gd` | 完整切面/原形兜底候选 | [R63] 11配置+R62旁表接唯一Stream/48节点；低档同档原形和LOD4→5即时备用、超成对预算选完整原形；实际显示层驱动旧楼实例屏蔽，碰撞SHA校验及终态恢复，显式canonical加载路由 | `_load_archive` `_setup_geometry` `_select_cut` `_step_geometry` `_bind_target` `_restore_original` `bind_legacy` `_sync_legacy` `_deactivate` `debug_state` |
| `tests/tokyo_canonical_lifecycle_case.gd` / `tests/tokyo_canonical_review.gd` | 原生生命周期 / 正式城区Visual | [R63] 缺备用、突放大、驻留但未显示、全档/禁用恢复、owner退出；ownership接all；真实Loading/Survivor六机位不伪造屏蔽清单 | `run` `ownership` `_wait` `_check`；`run` |
| `experiments/tokyo_source_coverage.gd` | 纯值显示覆盖判定 | [R62准备] 同配置/碰撞/目录的实际提交页及显示层，整栋屋顶/墙面依赖齐备才可交接；拒绝父子重叠，不消费game_sources来源标签，不自动隐藏旧楼 | `covered_sources` |
| `tests/build_tokyo_source_coverage.gd` | 离线几何凭据制作 | [R62] 从R51屋顶归属和实际逐栋墙面建立原生float32有向面多重集，核对R52根/中间/最细页，输出独立纯值旁表；逐依赖移除反例及来源标签误判统计 | `run` `_expected` `_add` `_faces` `_visit` `_audit_cuts` `_check` |
| `tests/test_tokyo_source_coverage.gd` | focused / all反例 | [R62] 缺页/缺层/错误身份/重叠切面/空依赖拒绝，实际索引面绕序、重复与位移；并入canonical stream现有测试 | `run` `_covered` `_test_faces` `_check` |
| `tests/build_tokyo_canonical_catalog.gd` / `tests/test_tokyo_canonical_stream.gd` / `tests/tokyo_canonical_stream_case.gd` | 制作 / focused / 原生流送验收 | [R54准备] R52原包逐SHA/字节/包络验证后建隔离目录；身份反例接all，显式目录全2288包经唯一Stream轮换及owner退出，不是地图显示交接 | `run` `_convert`；`run` `_check`；`run` |
| `tests/tokyo_canonical_cut_probe.gd` | RefCounted | [R54/R55预检] 共享正式投影/切面求解，区域/倍率/旋转的低层、标高、地表面数及备用包成本；可指定独立输出，不覆盖旧证据 | `run` |
| `tools/build_tokyo_ground_merge.py` / `tools/test_tokyo_ground_merge.py` | 离线地表候选 / 几何反例 | [R55未推广] 同色同高连通分量并集，float32拓扑和有理面积精确门；可另存向内远档概括，不改原包 | `f32` `parts` `exact_area` `merge_component` `plan_records` `main`；`grid` `records` `GroundMergeTests` |
| `tests/bake_tokyo_ground_merge.gd` / `tests/test_tokyo_ground_merge.gd` | 原生烘焙 / packed反例 | [R55未推广] 原属性逐字节继承、压紧顶点、保存后校验与显式类型数组；拒绝不支持的通道/骨骼/混合形状/多surface/内嵌LOD | `run` `_uniform` `compact`；`run` `_check` |
| `tests/tokyo_ground_merge_review.gd` | 真实地图静态对照 | [R55/R56诊断] 原图/候选/恢复、压紧、只改顺序、关阴影和近相机控制组；计旧新驻留与实际提交；地表减面Visual未通过，不接默认 | `run` `_compare` |
| `tests/tokyo_ground_order_probe.gd` | 原生提交顺序控制 | [R56诊断] 只把指定原面移到末尾，原打包属性与所有有向三角不变；越界/重复来源拒绝 | `move_to_end` |
| `tests/build_tokyo_canonical_spatial.gd` | 规范父/子/叶离线生成与重载 | [R52] 旧切线整面分桶，完整AABB及所有打包属性守恒，独立进程重建/目录对照；尚未接正式流送 | `run` `_split` `_page` |
| `tests/export_tokyo_gameplay_roofs.gd` | 原生来源只读导出 | [R50] 真实绑定屋顶、逐面来源/颜色/法线及数组摘要；不修改碰撞缓存 | `run` |
| `tools/build_tokyo_shared_roofs.py` / `tools/test_tokyo_shared_roofs.py` / `tools/audit_tokyo_shared_roofs.py` | 离线共同分区与独立审计 | [R50] 原生屋顶与游戏补面共享精确格网边界、同位属性冲突拒绝、逐来源覆盖；磁盘原生顶点独立重叠/覆盖审计及缺面/重面反例 | `polygon_parts` `canonical_points` `native_attributes` `build` `main`；`roof` `fixture` `SharedRoofsTests`；`key` `audit` `main` |
| `experiments/tokyo_shared_roof_bundle.gd` | Resource | [R50固定切面候选] 来源描述、原生替换网格、单批补面/墙面、字节与来源摘要；不是正式流送包 | 导出字段 |
| `tests/bake_tokyo_shared_roofs.gd` / `tests/audit_tokyo_shared_roof_bundle.gd` | 离线原生烘焙 / 保存后独立审计 | [R50] 保留原生打包法线/切线/颜色与未改面索引；保存重载与逐顶点来源检查，不放宽旧新驻留预算 | `run` `_replace` `_points` `_addition` `_same_arrays` `_retain_material` `_preserve_packed`；`run` |
| `tests/tokyo_shared_roof_review.gd` | 同步固定切面接管 | [R50静态审查] 源摘要全匹配才复用原节点，恢复旧网格，弱引用释放审计及实际提交面计数 | `bind` `restore` `references` `submitted_faces` |
| `experiments/tokyo_gameplay_volume.gd` / `experiments/tokyo_roof_difference.gd` | 静态原生几何 / 凸片差集 | [R49审查候选] 游戏街区原轮廓/米高转原生合批；保留原生屋面、只补未覆盖屋顶，计入所有surface字节和面数；未接连续流送或默认 | `build` `joined` `build_many` `geometry_bytes` `triangles`；`subtract_all` `subtract` `half_plane` `area` |
| `tests/tokyo_region_gameplay_guard.gd` | 离线游戏楼保护导出 | [R358] 正式接受顺序、轮廓/三角/米高、碰撞及来源摘要；相交分片须有完整逐几何不相交证明，不隐藏2D楼 | `protection_data` `export_protection` `preserved_merge_allowed` |
| `tests/test_tokyo_gameplay_volume.gd` / `tests/tokyo_gameplay_review.gd` | 几何反例 / 实际入口区域对拍 | [R49] 凹轮廓/高度/差集覆盖；保留碰撞缓存的静态接管和恢复、实际旋转与投影误差、共面屋顶导出；不冒作完整战斗或连续LOD | `run` `_test_difference` `_check`；`run` `_projection_errors` `_coplanar_roofs` `_capture` `_export_roofs` `_points` |
| `tools/audit_tokyo_gameplay_roofs.py` | 只读独立几何审计 | [R49] 对原生导出的来源/已有屋顶/候选补面核对缺口、越界、重叠与原边浮点残留，保留旧自接触环警告与严格失败 | `main` |
| `experiments/tokyo_cluster_cut.gd` / `rendering/tokyo_cluster_overlay.gd` | 成对切面 / R42派生层 | [R45候选] R44概括与R40原形共用唯一流送器；原形先备齐、即时恢复、完整原形分阶段换区和画外整块退役，不改变默认入口 | `decorate` `original_cut` `paths` `fallback_visible`；`_load_archive` `_setup_geometry` `_select_cut` `_step_geometry` `_prepare_target` `_trim_current` `_restore_original` `_bind_target` `_is_cluster` `_deactivate` `debug_state` |
| `experiments/tokyo_cut_reuse.gd` / `rendering/tokyo_stable_cluster_overlay.gd` | 完整覆盖验证 / R45派生层 | [R46候选] 同档、全部屋顶/阴影可见来源覆盖且实际提交不增加才保留当前或在途切面；不改几何、预算或默认 | `covers` `_validate` `_covered` `faces`；`_load_archive` `_setup_geometry` `_register_lookup` `_select_cut` `_compatible` `debug_state` |
| `tests/test_tokyo_cut_reuse.gd` | RefCounted反例 | 缺块、未知身份、父子重叠、画外高楼投影及真实面数；接东京focused/all | `run` `_entry` `_check` |
| `tests/test_tokyo_cluster_stream.gd` / `tests/tokyo_cluster_lifecycle_case.gd` / `tests/tokyo_cluster_runtime_review.gd` | focused / 生命周期 / Visual | [R45验收] 原形身份/唯一字节/包络反例；真实六档返回、冻结加载急拉近、整块退役、隐藏释放及在途终态；连续实际地图对拍与过渡提交失败记录 | `run` `_check`；`run`；`run` `_wait` |
| `tests/build_tokyo_cluster_pages.gd` / `tests/test_tokyo_cluster_pages.gd` | 离线原生派生 / 保存后审计 | [R44候选] 同父包低层概括，先重建原形守恒；标高/固定层不改，212独立原生文件逐层检查来源、字节及三角守恒 | `run` `rebuild` `face_count`；`run` |
| `tests/tokyo_cluster_review.gd` | RefCounted | [R44静态 Visual] 暂停R42复用原节点池和实际机位对拍，包含参考几何的驻留预算，恢复后才移动；不冒充连续LOD或FPS证据 | `run` `_compare` `_capture` |
| `tools/build_tokyo_cluster_lod.py` / `tools/test_tokyo_cluster_lod.py` | 离线低层概括 / 反例 | [R43/R57/R58/R70/R75候选] 参数化尺度/组上限/制作范围，CLI默认仍为原窗；范围及候选不得越界；正式LOD来源成本/父包约束，min_cost多外形共享原误差/障碍门，同高来源保留 | `mesh_faces` `candidate` `_evaluate` `prepare` `main`；`record` `ClusterTests` |
| `tests/export_tokyo_far_costs.gd` | 原生LOD来源成本导出 | [R58/R84/R88制作] LOD1/2/3/5正式detail/area轮廓及实际父包，身份唯一；最细候选按输出尺度5.0，离线只读原包 | `run` |
| `tools/build_tokyo_static_shadow.py` / `tools/test_tokyo_static_shadow.py` / `tools/audit_tokyo_static_shadow.py` | 静态阴影离线制作 / 反例 / 独立审计 | [R59/R60局部候选] 原高/底高投影、内院及区外投影者；显式矩形/最长边尺度、父外壳先绘保留内院独立岛，来源与区域外像素门 | `sweep` `polygons` `raster` `validate_bounds` `build`；`ShadowTests`；`audit` |
| `experiments/tokyo_static_shadow.gd` / `tests/test_tokyo_static_shadow.gd` / `tests/tokyo_static_shadow_review.gd` | 局部阴影材质 / focused / Visual | [R59/R60未推广] 实际尺度选R8、材质回滚、弱owner跨帧清理；六机位可扩展十机位/双强度，逐网格数组及变换守恒；C1仍保留全局投影 | `choose_row` `shader_code` `bind` `set_strength` `close`；`run` `_check`；`run` `_geometry_state` |
| `tests/build_tokyo_far_clusters.gd` / `tests/test_tokyo_far_clusters.gd` | 分档原生制作 / 反例 | [R57/R58/R78/R84/R88候选] 默认LOD1/2，显式可选LOD3/5；最细按5.0尺度，原低层重建守恒，逐组真实收益一致，保留标高与来源、保存重载；不自动进入运行时备用 | `run` `selected_levels` `maximum_scale` `_convert` `group_limit` `record_for` `eligible`；`run` `record` `_check` |
| `tests/tokyo_far_cluster_review.gd` | 静态分档原生对拍 | [R57/R58/R78/R84/R88未推广] 实际R34镜头/节点/材质；显式LOD3/5增加中近及最细机位；同源投影地表与128KiB源几何上界纳入双份驻留门；替换后恢复，支持独立停影诊断；不等于连续切档 | `run` `_compare` |
| `tools/build_tokyo_block_lod.py` / `tools/test_tokyo_block_lod.py` | 街坊级低楼概括 / 反例 | [R78/R84/R88/R92] 保留gentle/blocks，新增仅最细档district6/district8显式合同；原生成本、道路/铁路/水绿地/标高楼及组间重叠门保持，不延长远档应用距离 | `contract` `protected_road` `polygon` `barriers` `choose` `prepare` `main`；`fixture` `BlockTests` |
| `tools/filter_tokyo_cluster_barriers.py` / `tools/audit_tokyo_far_clusters.py` | 实际障碍过滤 / 独立审计 | [R57] 按准备好的道路描边/铁路/水体三角过滤新增占地；另验实际接受组的身份/高度/其它楼及区域外像素，保留失败 | `filter_plan`；`polygon` `audit` `main` |
| `tests/export_tokyo_roof_ownership.gd` | RefCounted | [R43只读] 导出两档32规范父包的水平屋面float32位值、面ID与来源摘要，仅供覆盖审计，不据此删面 | `run` `_roofs` |
| `rendering/tokyo_spatial_lod_page.gd` / `rendering/tokyo_spatial_lod_index.gd` / `rendering/tokyo_lod_hierarchical_overlay.gd` | 页 / 索引 / R41派生层 | [R42候选] 独立LOD4 full/mid来源身份与层级校验；同一流送器按原迟滞选空间切面，不改标高层、阈值或默认入口 | `valid`；`valid` `_same_package`；`_load_archive` `_setup_geometry` `_register_lod_entry` `_select_cut` |
| `tests/build_tokyo_lod_spatial_pages.gd` / `tests/test_tokyo_lod_spatial_pages.gd` | 离线构建 / 保存后审计 | [R42验收] 两档各16父/64子/128叶独立归档；核对原档来源、高度、原生属性、三角守恒与实际字节，拒绝跨档冒用 | `run` `_split_layers` `_save_page`；`run` `_test_identity` `_test_saved` `_verify_page` `_conserved` `_check` |
| `tests/tokyo_lod_spatial_review.gd` / `tests/tokyo_lod_spatial_probe.gd` | RefCounted | [R42 Visual] 15机位候选/原档/恢复原生对拍，等底图稳定；可选无投影对照和只读覆盖面定位，失败不改阈值 | `run` `_reference` `_capture` `_wait_basemap`；`capture` |
| `rendering/tokyo_hierarchical_overlay.gd` | TokyoCellsOverlay | [R41候选] R40近景完整切面与原R34远中档共用唯一流送器；旧新预算准入、全组就绪后原位重绑48节点，保持原形兜底/阴影/隐藏释放；不推广默认 | `_load_archive` `_setup_geometry` `_register_page` `_step_geometry` `_select_cut` `paths_for` `union_bytes` `_commit_cut` `_apply_precision_guards` `_remove_cell` `_deactivate` `_exit_tree` `debug_state` |
| `tests/test_tokyo_hierarchical_stream.gd` / `tests/tokyo_hierarchical_lifecycle_case.gd` / `tests/tokyo_hierarchical_review.gd` | RefCounted | [R41验收] 路径去重/旧新字节/来源与Packed数组归属反例；真实六档往返、在途取消、缺包保留及释放；实际地图17机位含预算失败报告 | `run` `_check`；`run` `_ready_cut` `_check`；`run` `_wait` |
| `experiments/tokyo_spatial_split.gd` / `experiments/tokyo_spatial_select.gd` | RefCounted | [R38实验] 原生完整三角中位分桶及16活动块粗细覆盖选择，不减楼、不改法线；包络保留画外投影者 | `centers` `cuts` `bucket` `split`；`visible` `choose` |
| `rendering/tokyo_spatial_page.gd` / `rendering/tokyo_spatial_index.gd` | Resource | [R38实验] 近景三层子包及16父/64子轻量目录；来源与高度仍引用父包 | `valid`；`valid` |
| `tests/build_tokyo_spatial_pages.gd` / `tests/test_tokyo_spatial_pages.gd` / `tests/tokyo_spatial_review.gd` | RefCounted | [R38/R39实验] 独立原生构建、保存后逐层多重集/字节/包络复核、节点复用/恢复对拍及像素覆盖面定位；不是正式流送过渡 | `run` `descriptor` `conserved`；`run` `_test_saved` `_test_surface_owner` `_test_covered_walls` `_test_owned_saved` `_test_selection` `_check`；`run` `_capture` `_probe_surfaces` |
| `experiments/tokyo_surface_owner.gd` | RefCounted | [R39离线] 精确有向三角或精确竖直完整矩形覆盖的低墙让位于标高层；保留原缓冲及来源，拒绝近似/半面/缺口 | `keys` `resolve` `wall_records` `wall_rectangles` |
| `tests/build_tokyo_owned_pages.gd` | RefCounted | [R39候选] 原父包先裁决被完整覆盖的低层面，再依R38切线生成独立16父/64子/目录；标高、固定层和来源不变 | `run` |
| `rendering/tokyo_spatial_leaf.gd` / `rendering/tokyo_hierarchical_index.gd` | Resource | [R40候选] 128个北岸二级叶包及严格根/祖先/叶目录；仍限16活动块 | `valid`；`valid` |
| `experiments/tokyo_spatial_cut.gd` | RefCounted | [R40/R86] 完整树切面与活动块/面/字节非支配候选；可行性比较接受实际剩余几何额度，默认保持旧预算；不因零即时收益停止，不丢可见几何 | `choose` `_frontier` `_combine` `_insert` `_better` |
| `tests/build_tokyo_hierarchical_pages.gd` / `tests/test_tokyo_hierarchical_pages.gd` | RefCounted | [R40验收] 独立北岸构建，选择反例、身份与保存后全部有向几何守恒 | `run`；`run` `_test_solver` `_test_saved` `_check` |
| `tests/build_tokyo_coastal_cells.gd` / `tests/test_tokyo_coastal_cells.gd` | RefCounted | [R34候选] R33来源面按R25原块裁片并入R32固定批次，原始角点法线无损展开/索引；建筑七档路径不变，独立17资源及实际成本/来源回归 | `expand` `add_clipped` `run`；`run` `raw_prefix` `_check` |
| `tools/extract_tokyo_coastal_inventory.py` / `tools/build_tokyo_coastal_addendum.py` / `tools/test_tokyo_coastal_addendum.py` | Python离线几何 | [R33准备] 同PBF有界码头/防波堤面线清单；扣除已有陆面/楼体的唯一补充面、float32拓扑/边界/面积门与接边收窄；只写独立tmp侧车，未改原生包或运行时 | `Collector.intersects` `Collector.area` `Collector.way` `main`；`native_faces` `existing_coverage` `prepare` `main`；`CoastalAddendumTests` `record` |
| `experiments/tokyo_palette.gd` / `tests/build_tokyo_palette_cells.gd` / `tests/test_tokyo_palette.gd` | RefCounted | [R32候选] B色板离线写RGBA8 RGB，保留原几何/索引/alpha/LOD/兜底及预算；测试色板与生产派生共用映射权威，不在正式fragment查表 | `recolor`；`run` `_save`；`run` `_same_geometry_and_palette` `_check` |
| `tests/tokyo_ground_review.gd` | RefCounted | [R31/R32静态诊断] 原生地表色板/无羽化/A-B校准及同SceneTree原mesh+材质对照；无影参考保留光源只停投影者，并恢复mesh/材质/投影/处理状态 | `capture` `palette_material` `shadowless` `palette_reference` |
| `tools/build_tokyo_shell_lod.py` / `tools/test_tokyo_shell_lod.py` / `tests/tokyo_shell_review.gd` | Python / RefCounted | [R37实验] 普通低楼中近景双端边界误差、来源保真；单块原生重建审计与同场景替换/恢复对拍，不进入正式归档 | `plain_shell` `simplify_shell` `prepare` `audit` `main`；`ShellTests`；`run` `_build` `_capture` |
| `tools/build_tokyo_area_lod.py` / `tools/test_tokyo_area_lod.py` | Python离线几何 | [R30候选] 远景面积/质心补偿，原生双端误差与源字段保真；仅独立派生数据 | `area_corrected_ring` `prepare` `audit` `main`；`AreaLodTests` |
| `tests/build_tokyo_area_cells.gd` / `tests/tokyo_mesh_signature.gd` / `tests/test_tokyo_area_cells.gd` | RefCounted | [R30候选] 原生低层来源重建、索引多重集审计、受控远景替换及完整原形字节账；近档/标高/固定不变 | `run` `_convert` `_save`；`of_mesh`；`run` `_same_mesh` `_upward` `_check` |
| `experiments/tokyo_cell_pairing.gd` / `tests/test_tokyo_cell_pairing.gd` | RefCounted | [R29候选] 离线屏幕无关全局配对，完整来源/原生逐角与原形预算审计；运行时不执行求解 | `pair_entries` `solve` `_solve_mask`；`run` `_check` |
| `tests/build_tokyo_joined_cells.gd` | RefCounted | [R26联合观察] 同区配对合并R25原生包，单一16批次/唯一来源/完整原形兜底；原几何不减 | `pair_entries` `merge_meshes` `run` `_save` |
| `experiments/tokyo_indexed_mesh.gd` | RefCounted | [R28候选] 离线逐字节重复顶点复用；运行时实际索引面数SSOT，原三角和打包法线不变 | `pack` `triangles` |
| `tests/build_tokyo_indexed_cells.gd` / `tests/test_tokyo_indexed_mesh.gd` | RefCounted | [R28候选] 独立129索引归档，七包/原形逐角展开精确检查，含16/32位及全部字节账；不以顶点数冒充减面 | `run` `_convert` `_save`；`run` `_same_corners` `_check` |
| `tests/tokyo_cells_lifecycle_case.gd` | RefCounted | [R28容量] 真实异步加载全16个LOD3和固定地表，保留96MiB；不代表绘制性能通过 | `_test_full_indexed_mid` |
| `rendering/tokyo_cells_overlay.gd` | TokyoVolumeOverlay | [R26切换] 已显示批次LOD替换优先于新街区，实际绑定后才释放旧包，避免96MiB内的请求饥饿（SEAM-042） | `_sync_requests` |
| `tests/test_tokyo_cells.gd` | RefCounted | [R26验证] 三角/颜色/法线守恒、全域唯一来源、L形空区及兜底字节 | `_test_joined_union_archive` `_meshes_sum` |
| `experiments/tokyo_regional_ownership.gd` / `tests/test_tokyo_regional_ownership.gd` | RefCounted | [R25候选] 联合来源保真与摘要门、单区索引拒绝误加载；离线验证，不接入Overlay | `validate`；`run` `_check` |
| `tests/build_tokyo_cells.gd` / `tests/test_tokyo_cells.gd` | 离线构建 / 原生回归 | [R25候选] 非owner在所有LOD及原形兜底生成前跳过；独立归档三角差集与地表不变验证 | `_load_regional_ownership`；`_test_regional_archive` `_mesh_subtracts` |
| `tools/build_tokyo_region_ownership.py` / `tools/audit_tokyo_region_ownership.py` / `tools/test_tokyo_region_ownership.py` | Python离线数据 | [R24准备] 跨区来源一致性、整栋唯一归属、原始输入保真与联合专用标记；尚无原生消费 | `source_payload` `connected_components` `component_center` `region_distance` `build_registry` `prepare_region` `main`；`audit` `main`；`building` `cities` `OwnershipTests` |
| `tools/build_tokyo_footprint_lod.py` / `tools/test_tokyo_footprint_lod.py` | Python离线几何 | [R22候选] 原生float32的整条双向边界误差、面积与拓扑门；受保护来源不动，远近档单调；只准备独立轮廓 | `f32` `within_error` `simplify_ring` `eligible` `prepare` `main`；`ring` `FootprintTests` |
| `tests/build_tokyo_cells.gd` | 离线构建 / 只读审计 | [R23预检] 显式环境开关导出已验证R22原生地表三角与来源哈希，供离线联合裁剪成本验证；不修改归档或默认地图 | `_export_fixed_for_cell_audit` |
| `rendering/tokyo_cell_archive.gd` / `rendering/tokyo_cells_overlay.gd` / `tests/build_tokyo_cells.gd` | 归档 / 地图层 / 离线构建 | [R22候选] 远景原形兜底计入流送预算，突放大立即绑定常驻原轮廓并更新实际提交统计 | `valid`；`_apply_precision_guards`；`mesh_bytes` |
| `tests/test_tokyo_cells.gd` / `tests/tokyo_cells_lifecycle_case.gd` | RefCounted | [R22验收] 所有来源、高度、固定面/标高楼/近档不变，原形兜底逐数组/内存验证；冻结选档突放大仍恢复原轮廓 | `_test_precision_archive`；`_test_precision_jump` |
| `tools/build_tokyo_strokes.py` / `tools/test_tokyo_strokes.py` | Python离线几何 | [R21候选] 连续等宽道路/轨道，闭环孔洞、自交去重、尖角截角；原建筑/中心线不变，准备数据独立输出 | `stroke` `prepare` `main`；`surface` `StrokeTests` |
| `experiments/tokyo_volume_preview_factory.gd` / `tests/test_tokyo_cells.gd` | 离线工厂 / 回归 | [R21候选] 有准备数据时读取连续道路三角，无数据保持旧线段；原生颜色/高度/接头和全部建筑七包逐数组守恒 | `_path_ribbon`；`_test_joined_paths` `_test_joined_archive` |
| `tests/test_tokyo_cells.gd` / `tests/tokyo_cells_lifecycle_case.gd` | RefCounted | [R20候选] 北岸独立原生归档的完整来源、七包高度、地表裁片面积；正确城区锚点的异步LOD/静止/终态；预算另由真实巡检裁决 | `_test_north_coast_archive`；`_test_north_coast` |
| `tools/audit_tokyo_region_seam.py` / `tools/test_tokyo_region_seam.py` | Python离线审计 | [R20前置] 实际海陆三角共边覆盖、跨界来源高度/孔洞与双绘制归属审计；不填海删楼 | `coast_land` `ring_key` `shape_key` `audit` `main`；`ground` `SeamTests` |
| `experiments/tokyo_duplicate_outline.gd` / `tests/test_tokyo_duplicate_outline.gd` | RefCounted | [R19离线] 精确无孔洞外环去重，明确高度接管冗余估高外壳，保留源ID与高度；父子/特殊顶/冲突拒绝 | `suppressed` `_eligible_key` `_ring_key`；`run` `source_fixture` `_check` |
| `tests/test_tokyo_cells.gd` | RefCounted | [R19验收] 原生七包仅移除已查实冗余外壳，固定面/明确高度楼逐数组不变；来源身份和哈希不变 | `_test_duplicate_archive` |
| `rendering/tokyo_shadow_depth.gd` / `tests/test_tokyo_shadow_depth.gd` | RefCounted | [R18候选] 正交可见面及画外日光投影源的深度包络；多旋转/高度独立射线与原生七包高度范围验证 | `fit`；`run` `_inside` `_check` |
| `rendering/tokyo_shadow_depth.gd` / `tests/test_tokyo_shadow_depth.gd` | RefCounted | [R27候选] 从16块完整源包络挑选可见楼体/画外投影源高度，不依赖当前加载档位；无效元数据回退全局 | `visible_height`；`_test_visible_height` |
| `rendering/tokyo_volume_overlay.gd` / `rendering/tokyo_cells_overlay.gd` | 地图层 | [R18候选] 相机变化时配置深度；独立候选复用R17B包，旧路径不变 | `_configure_camera_depth` |
| `experiments/tokyo_dome_roof.gd` | RefCounted | [R17离线] 来源圆顶截环、误差分段；R17B拒绝底面不明确、孔洞/凹形/缺高，不改源记录 | `build` `_point` `_face` |
| `tests/test_tokyo_dome_roof.gd` / `tests/test_tokyo_cells.gd` | RefCounted | [R17验收] 圆顶高度/朝向/覆盖/误差/源不变；七包低层/固定面逐数组守恒，所有改动三角限制在三个来源圆顶体积内 | `run` `_vector` `_check`；`_test_dome_archive` `_inside_source_dome` |
| `tests/build_tokyo_cells.gd` / `rendering/tokyo_cells_overlay.gd` / `tests/tokyo_cells_runtime_visual.gd` | 离线构建 / 地图层 / Visual | [R17候选] 独立圆顶归档与原生接线；R17B沿用R15C分块/裁剪/LOD，额外Queen/博物馆/信息不足屋顶对拍，不切正式默认 | `run`；`_load_archive`；`_capture_sequence` |
| `rendering/tokyo_volume_archive.gd` | Resource | [地图首区] 东京站离线六档网格归档和输出像素尺度迟滞，不在战斗期间读取 OSM | `choose_level` `valid` |
| `rendering/tokyo_volume_overlay.gd` | Node2D | [地图首区实装] 原生分辨率透明地图层，静止不重绘；R35 bench-only过程/相机/几何/更新请求计时 | `default_enabled` `setup` `_load_archive` `_presentation_bounds` `_should_prewarm` `_setup_geometry` `_add_mesh` `_process` `_process_map` `_step_geometry` `_switch_level` `_deactivate` `set_enabled` `debug_state` |
| `tests/build_tokyo_volume_archive.gd` / `tests/test_tokyo_volume_lod.gd` | RefCounted | [离线/测试] 首区归档构建、来源密度守恒、档位预算和迟滞 | `run` `_bytes`；`run` `_check` |
| `tests/tokyo_volume_lifecycle_case.gd` / `tests/tokyo_volume_lifecycle_runner.gd` | RefCounted / Node | [测试] 真实地图源/相机释放、重启显示、静止零重绘与画外停更；接入默认 gauntlet | `run` `_check`；`_ready` |
| `tests/tokyo_volume_visual_runner.gd` / `tests/tokyo_volume_combat_runner.gd` | Node2D / Survivor | [Visual] 七倍率接线；真实城区C1/C2/近景2D/3D；单调时钟硬门及R58完整性显式的真实P50/P95/P99，bench-only停投影对照；phases/backend诊断不作为同帧GPU证据，截图停采后读回 | `_ready` `_capture_sequence`；`_ready` `_process` `_bench_force_battlefield_atmosphere_stress` `_bench_update_camera_patrol` `_capture_city` `cell_peak_within_budget` `_bench_finish_now` |
| `tests/tokyo_render_clock.gd` / `tests/tokyo_render_trace.gd` | RefCounted | [R36/R58/R94测试] 纯时钟门/最近秩分位数与独立阶段/后端探针；墙钟摘要含P99.9、最慢1%/0.1%平均帧率及超过30fps帧预算的数量；固定32条保留最大wall及策略/省略数，不按前32条截断；弱引用、幂等清理，后端均值不作同帧归因；显式帧率余量诊断拒绝未知刷新率及不高于60的上限 | `partition` `frame_within_budget` `diagnostic_cap` `percentiles_usec` `retain_slowest`；`setup` `begin_frame` `_before_draw` `_after_draw` `close` `summary` |
| `experiments/volume_3d_tokyo_preview.gd` | Node3D | [隔离预览] 东京站小片固定机位真实截图与瓦片对照；不接正式地图、不证明实战性能 | `_ready` `_load_geometry` `_exit_tree` `_configure_environment` `_add_batch` `_set_view` `_capture_sequence` `_settle` `_capture` |
| `experiments/tokyo_volume_preview_factory.gd` | RefCounted | [离线/隔离预览] OSM 建筑按高度来源分批，清晰道路/轨道与离线面地表；R5 内院/分部，R10 来源坡顶及屋面分类；无逐栋节点 | `build` `build_ground` `_add_low` `_add_known` `_add_ring_building` `_prepared_surface` `_triangle_face` `_shell` `_ribbon` `_face` `_points` `_triangles` |
| `experiments/tokyo_preview_ground.gd` | Node3D | [隔离预览] 正式瓦片稳定后的共享纹理快照，无常驻 tick | `snapshot` |
| `tools/build_tokyo_volume_preview.py` / `tools/build_tokyo_preview_ground.py` | Python CLI | [地图离线] 小片 OSM 建筑/道路与面地表，后者保留多面孔洞并裁切三角化 | `main` `PreviewCollector.way` `world_point` `signed_area` `centroid` `parse_measure` `fallback_height` `bbox_intersects` `perpendicular_distance` `simplify` `round_points`；`Collector.area` `Collector.way` `world` `intersects` |
| `tools/build_tokyo_volume_region.py` | Python CLI | [地图离线候选] 参数化区域、关系楼/内院、分部覆盖与高度来源、室内路径过滤；可选同源闭合海岸；区域缓存和原始 JSON 只留 tmp，未接正式全图 | `measure` `heights` `above_ground` `polygons` `vertices` `triangulate` `RegionCollector.intersects` `relation` `area` `consume_area` `way` `consume_path` `load_cache` `source_cache` `resolve_relations` `resolve_parts` `export` `main` |
| `tools/tokyo_coastal_faces.py` / `tools/test_tokyo_coastal_faces.py` | Python 离线几何 / unittest | [R9] 有向岸线闭合海陆，断岸/矛盾拒绝构建 | `coastal_faces`；`test_open_shore` `test_island_and_hole` `test_gap_and_reversed_segment_rejected` |
| `tools/tokyo_tagged_roofs.py` / `tools/build_tokyo_tagged_roofs.py` / `tools/test_tokyo_tagged_roofs.py` | Python 离线几何 / CLI / unittest | [R10] 按明确 roof:height/shape 恢复双坡/四坡/锥顶，坡面半平面裁原轮廓、总高不变、未支持项显式审计 | `tagged_roof`；`main`；`test_shapes_keep_total_height` `test_courtyard_concavity_and_source_bottom` `test_rotated_warehouse` `test_across_and_rejection` |
| `rendering/tokyo_region_archive.gd` / `tests/build_tokyo_region_archive.gd` | Resource / RefCounted | [制作候选] 单档静态网格包；显式离线源目录构建，观察场只加载网格，不把原始 JSON 回流资源目录 | `valid` `packet`；`run`；bench `tokyo_region_build` |
| `rendering/tokyo_cell_archive.gd` / `rendering/tokyo_cell_index.gd` | Resource | [R6 候选] 独立单块单档与轻量路径目录；固定地表不重复，整栋内容范围选块，不内嵌所有档位 | `valid`；`valid` `visible_cells` |
| `rendering/tokyo_cell_stream.gd` | Node | [R53] GL有界后台请求；Dummy后端主线程延后领取，保留预留/取消/退出与每帧上限；R35独立流送根桶；`light_frame_balance`（默认关，HLOD overlay 正式流开启）时非当前可见的完成件领取与纹理上传在含物理步帧有界延后到无步帧（`rendering/tokyo_hlod_stream.gd` 覆写 `_light_defer_exempt` 豁免 `visible_meshes`/`visible_images`） | `configure` `request` `resource` `_prune` `_process` `defer_to_light_frame` `_light_defer_exempt` `_process_stream` `_request_load` `_load_status` `_take_load` `_matches` `close` `summary` |
| `tests/tokyo_rid_repro.gd` / `tests/tokyo_rid_stream_case.gd` | 原生竞争复现 / 生产流送回归 | [R53] 前者仅显式诊断、故意保留旧后台竞争；后者双后端真实几何/RID及终态检查，接默认生命周期 | `run`；`run` `_fingerprint` |
| `rendering/tokyo_cells_overlay.gd` | TokyoVolumeOverlay | [R7–R15候选] 正式相机/合成；选块10Hz、逐块绑定、旧包保留/隐藏预热；R11B按真实尺度切低层过渡包；R12方向裁剪、R13密度/R15覆盖成本分块、R14实际旋转视域；不默认推广 | `_load_archive` `_setup_geometry` `_presentation_bounds` `_should_prewarm` `_step_geometry` `relief_enabled` `_target_entry` `layer_bounds` `projected_layer_bounds` `intersects_view` `_apply_visibility` `_sync_requests` `_remove_cell` `_deactivate` `_exit_tree` `debug_state` |
| `tests/tokyo_cells_lifecycle_case.gd` / `tests/tokyo_cells_lifecycle_runner.gd` / `tests/tokyo_cells_runtime_visual.gd` | RefCounted / Node / TokyoVisual | [R7–R15测试] 异步读取、画外释放、owner退出、在途取消/重开、缺资源保留旧楼、零建筑海面块；均匀/密度/覆盖分块隐藏恢复、静止、旋转及退出；默认gauntlet；正式多倍率截图 | `run` `_test_cancel_reenter` `_test_old_on_missing` `_test_missing` `_test_empty_coastal_cell` `_test_layer_visibility` `_wait_ready` `_wait_gone` `_check`；`_ready`；`_ready` `_capture_sequence` |
| `tests/build_tokyo_cells.gd` | RefCounted | [离线构建] 关系组唯一归属、固定面裁格、六尺度网格、来源/面积审计；R11B追加第4档低层过渡包；R13密度/R15多尺度覆盖成本二分16块，不改楼体 | `run` `cell_rect` `building_bounds` `connected_groups` `partition` `adaptive_rects` `_partition_atoms` `coverage_rects` `_coverage_cost` `_coverage_split` `_split_density` `detail_level` `clip_polygon` `split_fixed` `mesh_area` `finish` `_save`；bench `tokyo_cells_build` |
| `tests/test_tokyo_cells.gd` / `tests/tokyo_cells_visual.gd` | RefCounted / TokyoPreview | [R6–R15验收] 来源/高度/裁切、原网格逐数组；密度/覆盖分块确定性/整栋归属、七包全区无序三角多重集；旋转阴影/视域及过渡包迟滞；固定场不是性能门 | `run` `_test_partition` `_test_clip` `_test_ring_levels` `_test_relief` `_test_yokohama` `_test_tagged_roofs` `_test_layer_bounds` `_test_mid_relief` `_test_density_partition` `_test_adaptive_archive` `_test_rotated_view` `_add_mesh_signature` `_roof_signature` `_same_mesh` `_check`；`_load_geometry` `_set_view` `_select_cells` `_node` `_settle` `_capture_sequence`；bench `tokyo_cells` / `tokyo_cells_visual` |
| `tests/test_tokyo_volume_ring_geometry.gd` / `tools/test_tokyo_volume_region.py` | RefCounted / Python unittest | [测试] 内院屋顶面积/空洞、内壁法线、最低/最高标高、R4 网格不变、原生候选包；高度解析与来源、区域缓存边界、分部接管和保留补面 | `run` `_check`；`RegionTests`；bench `tokyo_volume_rings` |
| `../addons/volume_terrain_export/plugin.gd` | EditorPlugin / EditorExportPlugin | [编辑器] 导出时附带静态地形缓存的原始脚本指纹输入与沙漠.aglmap文档，保留编译映射 | `_enter_tree` `_exit_tree` `_get_name` `_export_begin` |
| `experiments/volume_mesh_factory.gd` | RefCounted | [隔离实验] 可重建 low-poly 机体/母舰部件与同源地图几何；一次构建共享 ArrayMesh，禁止拿技术代理宣称全机型资产完成 | `triangle` `quad` `prism` `box` `loft` `mesh` `material` `aircraft` `map_mesh` `ribbon` `points_from` `stroke_edges` |
| `rendering/aircraft_volume_overlay.gd` | CanvasLayer | [生存/正式表现] 单一原生输出像素透明 SubViewport + 2× MSAA；逐显示帧在正式相机之后同步，无错相/节流；保留共享网格预热、惰性批次和 Shift+F11/环境变量二维 A/B | `default_enabled` `setup` `_process` `set_volume_enabled` `toggle_volume` `is_volume_enabled` `summary` `_sync_size` `_exit_tree` |
| `rendering/desert_volume_presentation.gd` | volume_world_probe 派生 | [生存/正式地图] 内置沙漠正常开局默认启用同视口三维地图与机体，与透明飞机层互斥；不覆写选机、教程、生涯和任务；`AGL_DESERT_VOLUME=off` 显式回退地图 | `enabled_for` `setup_formal` |
| `rendering/desert_map_preload.gd` | Node | [正式载入] 单次沙漠资源所有者，分帧背景/目录准备、近远档各两帧真实提交、复用同节点交接；退出/错误来源/超时释放，不留常驻tick | `eligible` `start` `take` `_ready` `_process` `_switch_lod` `_after_draw` `progress` `arm` `_loading_exited` `cancel` `_exit_tree` |
| `tests/desert_preload_lifecycle_case.gd` / `tests/desert_preload_runner.gd` | RefCounted / Node | [测试] 分帧/同步几何逐数组等价、正式适配器同节点交接、源重绑定、载入退出/半成品取消/超时/错源清理；并入all真实SceneTree终态 | `run` `_wait_ready` `_check` / `_ready`；bench `desert_preload` |
| `experiments/volume_satellite_ground.gd`（预载入交接） | Node3D | [正式地图] 验证原生风格、来源与矩形后改绑真实Raster弱引用，保留预绘制的同一网格/材质；setup可消费分帧背景作业 | `rebind_native_source` `setup` |
| `tests/desert_formal_entry_runner.gd` | Node | [Visual] 隔离存档通过真实主菜单、选图、选机、预加载进入正式 Survivor 两次，验证地图默认接入、机型与生涯保留、点击/Tab、退出释放；实际GL校验高地/地被独立色值、路线覆盖显式开关及三机场1.3近景；截图记录实际canvas/viewport、北侧道路双倍近景及工业四区1.3近景/实际相机与流送状态 | `_ready` `_run` `_wait_scene` `_key` `_check`；bench `desert_formal_entry` |
| `experiments/volume_world_probe.gd` / `experiments/volume_projection.gd` | Node3D / RefCounted | [共享表现后端/隔离地图实验] 按入口配置斜俯视，精确对齐二维地面/点击锚点；正式透明层渲染飞机与已完成地面模型并保留默认角度，隔离实验可另带沙漠三维地图。正式入口预热目录中的 LOD0/LOD1/LOD2/挂载共享网格路由，MultiMeshInstance3D 仅在对应机型/档位/挂载首次真实提交时惰性创建，空批次不常驻 3D 剔除；同一批次以机翼掩码/custom data 保留双通道涂装；所有航空身份按实际输出跨度用 22/18 px 切 LOD0/LOD1、8/11 px 切 LOD1/LOD2，独立挂载仍按 22/18 px，不读取玩家/BOSS/Sentinel/旋翼机身份；LOD0 动态旋翼、Mother Goose 真挂点、远景省略和弱引用终态均由正式状态驱动；机体与母鹅挂点按 DisplayPacing 物理插值显示态（位置 + 航向偏移）摆放 | `setup` `_cache_mesh_route` `_ensure_batch` `_refresh_members` `world_point` `camera_basis` `_sync_camera` `_process` `set_bodies_enabled` `_set_body_override` `mount_detail_mode_for` `body_lod_level_for` `_submit` `livery_ratio_for` `_sync_aircraft_mounts` `_sync_goose_mounts` `_submit_rotor` `_capture` `summary` `_exit_tree`；`top_basis` `camera_basis` `ground_basis` `actor_transform` |
| `experiments/volume_3d_lab.gd` | Node3D | [隔离实验] Mother Goose、三机、沙漠/机场 F6 观察；9 工业斜视、0 三城区轮看、B BOSS、D 完整沙漠实验；复用正式瓦片源，GLB 仅几何导出，不包含运行时流送地表；三峰/工业双倍率光照对拍 AGL_VOLUME_RELIEF_LIGHT_QA 读取实际GL默认值；另有地被LOD/铁路屏幕细节/公铁交叉近远对拍，不代表实战或性能通过 | `_ready` `_add_mesh` `_set_view` `_set_map_view` `_set_aircraft_view` `_set_map_location` `_set_play_map_view` `_set_district_view` `_unhandled_key_input` `_capture_sequence` `_capture_crossings` `_capture_rail_lod` `_capture_cover_lod` `_save_view` `_export_mesh` `_process` `_exit_tree` |
| `experiments/volume_aircraft_catalog.gd` | RefCounted | [隔离实验] 当前动态审计的 71 个规范航空身份均有独立 LOD0 制作源、只读共享缓存、逐型来源许可/概念边界；从完整源的连通组件派生最多 320 面的结构化 LOD1，并保留最多 128 面的 LOD2 极远轮廓。所有身份保留双通道涂装；旋翼机 LOD0 另提供移除静态桨叶的运行时机身，LOD1/LOD2 均合并为含桨盘跨度的单网格；未知 key/档位返回 null | `supported_keys` `build` `build_runtime` `supports_body_lod` `build_runtime_lod` `_build_medium_body_lod` `_build_far_body_lod` `_connected_components` `_directional_outline` `_mirrored_outline` `_support_outline` `metadata_for` 各 `_build_<key>` `_source_record` `_planform` `_closed_loft` `_cap_ring` `_fin` `_outward_triangle` |
| `experiments/volume_aircraft_mount_catalog.gd` | RefCounted | [共享表现后端] 普通飞机共享三维挂载/旋翼网格与互不冲突规范槽；只读正式弹药、装填、释放 CD、充能/光束/过热状态，不拥有武器逻辑或机身涂装；远景可读性 LOD 由 `volume_world_probe.gd` 统一裁决 | `supported_kinds` `normalized_slots` `local_slots` `visible_count` `state_color` `build` |
| `experiments/volume_map_factory.gd` | RefCounted | [沙漠正式/实验共享] 同源静态网格、连续铁路、源建筑及机场/工业/三城区装饰；地面、横向UV清晰线路与七组投影建筑分批，合并版仅校验/导出；机场静态场坪、两处道路短接线及四处公铁交叉面不改玩法地理 | `build` `road_presentation_points` `_line_mesh` `merge_meshes` `configure_instance` `configure_sun` `_add_airport_details` `airport_service_surfaces` `_add_industrial_details` `palette` `face` `stroke_edges` `stroke` `sleeper_poses` `airport_polygon` `_add_runway_markings` `_add_roof` |
| `experiments/volume_rail_crossings.gd` | RefCounted | [沙漠静态显示] 四处交点按实际整线miter轮廓裁切路肩/路心；surface_height与路基共面、height独立排序，同批盖住枕木并保留钢轨；源漂移/重复铁路点拒绝套用，不推断现实桥梁 | `records` |
| `tests/test_volume_rail_crossings.gd` | RefCounted | [测试] 四处交叉实际网格、16面增量/原预算、原线路五通道守恒、共面与提交排序分离、三视角投影、凸轮廓约束、原平地、源不可变及漂移/重复点/source回退反例；由地图focused调用 | `run` `_inside` `_check` |
| `experiments/volume_projection.gd` | RefCounted | [共享表现后端] 参数化斜俯视与地面补偿；默认角度保持正式机体层，沙漠入口显式选用独立角度，保持 Camera2D 点击/标签锚点 | `top_basis` `camera_basis` `ground_basis` `actor_transform` |
| `tests/test_volume_camera_sync.gd` | RefCounted | [测试] 真实SceneTree的重复赋值通知对照、静态地图提交去重与平移/缩放/旋转/resize精确等价 | `run` `_check` `WatchedMesh._notification` |
| `experiments/volume_desert_relief.gd` | RefCounted | [隔离实验] 同bbox表现高程、统一三角曲面、水岸与低矮灰黄地被/有界不对称贴坡岩层；源bounds/UV与共边render_bounds分离，按真实风格只绑定一份归档，失效回退共用边界选择；地被预构建近远档保留岩体通道，不改玩法地理 | `_init` `bind_archive` `height_at` `normal_at` `plane_mesh` `presentation_mesh` `presentation_bounds` `make_details` `make_cover_lod` `_add_outcrop` `outcrop_profile` `_add_surface_triangle` |
| `experiments/volume_terrain_archive.gd` | Resource | [隔离实验] 静态地形与装饰版本指纹、原bbox/gutter匹配；另存独立映射/量化的共享裁剪边，不持有纹理 | `source_fingerprint` `is_current` `matching_mesh` `source_rect` `tile_layouts` `canonical_tile_rect` |
| `tests/build_volume_terrain.gd` | RefCounted | [构建] 显式 volume_terrain_build 输出压缩三维资源、岩面纹理和机场清理用同源纯地形纹理至 bench/results，记录双色彩空间均值及独立预算，不自动改生产资源 | `run` `_mesh_bytes` |
| `tests/test_volume_terrain_archive.gd` | RefCounted | [测试] 预构建资源与运行时生成逐数组等价、失效/错风格拒绝、source/tactical独立归档植被水文守恒及分别核算的内存预算 | `run` `_same_mesh` `_test_tactical_details` `_check` |
| `tests/test_volume_native_surface.gd` | RefCounted | [测试] 145瓦片全部三角形包含于完整地形面，扣除显式底高差后逐顶点比较高度/CUSTOM0法线，并用坏高度/坏法线/越界反证；volume_terrain_archive调用 | `run` `_compare_triangle` `_negative_controls` |
| `tests/test_volume_tile_edges.gd` | RefCounted | [测试] 全部相邻瓦片实际网格共边/高度、原始UV逐顶点映射、有限边界偏移和错配拒绝；volume_world调用 | `run` `_mesh_edge` `_check` |
| `tests/test_volume_tile_visibility.gd` | RefCounted | [测试] 真实视口逆投影选格与独立多边形交集 oracle；旋转/偏移/横竖屏/缩放覆盖、虚角排除、原轴对齐集合与地图外拒绝 | `run` `_check` |
| `tests/volume_desert_route.gd` | Node | [测试] 显式沙漠自然路线探针，强制独立 user 存档；真实 Tab 点击和可用升级按钮，记录任务信号/航迹/退出，不冒充 L1 或 FPS | `is_isolated_profile` `run_route` `_live_mode` `_drive_inputs` `_snapshot` `_on_triggered` `_on_completed` `_on_failed` |
| `tests/volume_map_performance.gd` | Node | [Visual] 同 UGC/战斗的真正纯2D与三维地图配对，复用正式底图 owner；旧 volume_2d 场景不作纯2D基线；显式env启用CPU/GPU及可见/阴影提交诊断，共用FPS帧号窗口，默认无采样 | `setup` `_live_probe` `summary` `_capture` `_sample_render_times` `_accept_render_frame` `_record_render_sample` `_record_render_coverage` `_record_coverage_slot` `_coverage_report` `_timing_report` `_exit_tree` |
| `experiments/volume_terrain_surface.gd` | RefCounted | [隔离实验] 固定世界格网与显式局部 DEM 细分/过渡环；瓦片和岩石裁剪复用唯一三角曲面 | `_init` `_world_node` `_insert_node` `_build_refinement` `cell_triangles` `triangle_weights` `_coordinates` `_value` `_sample_scalar` `height_at` `normal_at` `_node_normal` `clip_to_triangle` `_clip_polygon` `plane_mesh` |
| `tests/test_volume_desert_relief.gd` | RefCounted | [测试] 高程来源、固定格网/面内跨 LOD 一致、道路平地、实际岸线闭合/UV/固定水高、植被/裸岩贴地净空与预算及 owner 清理；局部细分闭合与源节点、地被近远档误差与岩体字节一致；由 volume_world 调用 | `run` `_test_shoreline` `_test_watercourses` `_watercourse_mesh_stats` `_watercourse_coverage` `_test_cover_lod` `_test_outcrops` `_test_refinement` `_test_surface_contract` `_surface_error` `_test_tile_budget` `_check` |
| `experiments/volume_watercourse.gd` | RefCounted | [表现] 已确认河道的共享接头与唯一地形逐面裁分，横向UV不随裁边断裂；UV2保留共享横向向量供军事风格远景最小屏幕覆盖；合入已有水岸静态批次，不改高程或玩法坐标 | `build` `_append_triangle` |
| `tools/build_volume_desert_hydrography.py` | Python | [离线] 保存来源哈希与替换范围，重建保留水面的even-odd条带和地图/湖边裁剪后的源河道；支持--source隔离来源候选；测试见tools/test_volume_desert_hydrography.py | `build` `water_quads` |
| `tools/test_volume_desert_hydrography.py` | Python | [回归] 水面孔洞、独立水池、逐字重建、未分类色块不切断干流；西部48源点/真实汇流，东北102源点/37符号及部分关联保留 | `test_western_supplement_preserves_source_and_confluence` `test_northeast_complete_way_and_partial_contour_preserved` |
| `tests/volume_relief_stress.gd` | Volume3DLab | [测试] S3 地形六区域跨区/缩放/LOD 36 秒专项，逐帧检查绘制提交；AGL_VOLUME_CROSSING_PERF显式选择三交叉区与机场/工业/河道；计时结束后分类可见/预取缺口并等待正式流送收敛；显式诊断记录坏帧绝对时间、限帧/垂直同步/缓存路径与最近后端计时，不作同步因果归因；不替代有参战者 C1 或逐像素覆盖 | `_capture_sequence` `_render_diagnostic` `_streaming_snapshot` `render_sample_valid` |
| `tools/audit_volume_relief.py` | Python 离线工具 | [审计] 复算 R11 植被与三角面落地偏差、跨 LOD 裁边偏差和固定机位覆盖；不运行引擎或改资源 | `audit` |
| `experiments/volume_building_factory.gd` | RefCounted | [地图共享几何] 静态厂房坡屋顶、源工业沿坡金属板/散热口/檐沟/支撑雨棚、退台楼、储罐穹顶/环带、分层塔楼和跑道局部坐标附属设施 | `frame` `rectangle` `scaled_polygon` `add` `industrial_roof_details` `warehouse_surface_point` `_office` `_tower` `_tank` `_warehouse` `_roof_quad` `airport_details` |
| `experiments/volume_district_layout.gd` | RefCounted | [隔离实验] 三个 urban 区域内确定性错列街区，最近源道路定向、实际道路接点、逐栋出入口及铁路/跑道/既有建筑净空过滤；不创建玩法单位或更改源地理 | `layout` `_segments` `_nearest_road` `_protected_rects` `_plot_clear` `_street_clear` `_segment_distance` |
| `tests/test_volume_district_layout.gd` | RefCounted | [测试] 三城区实际覆盖、布局确定性、地块与源道路/铁路/机场/建筑净空、互不重叠、实际道路连接点；由 map focused 调用 | `run` `_check` |
| `experiments/volume_satellite_ground.gd` | Node3D | [隔离实验] 复用RasterBasemapRenderer纹理与归档；照片最多17面，原生候选1完整面；10Hz资源/地被LOD，候选初始化两帧材质预热，原alpha顺序与弱引用清理，不建第二套高清地图 | `setup` `_on_material_warmup_finished` `enable_relief` `setup_lab` `sync` `cover_lod_far` `cover_error_pixels` `_sync_cover_lod` `_apply_cover_lod` `_make_plane` `configure_source_material` `_clear` `debug_state` |
| `experiments/volume_material_warmup.gd` | SubViewport | [沙漠候选] 初始化32×32独立世界、同顶点格式/灯光/阴影实际绘制克制建筑材质，两帧后释放；Headless不冒充GPU完成，提前退出断开回调 | `configure` `_ready` `_after_draw` `_exit_tree` |
| `tests/test_volume_satellite_ground.gd` | RefCounted | [测试] 纹理对象复用、原世界矩形、gutter UV、装饰共享材质与归档隔离、渐变/排序/隐藏与已释放 owner；沙漠克制面色四区域预算/无照片采样/原坐标及释放；背景近远档屋顶/墙/道路精确色板守恒、全部道路顶点原XZ/高度/法线/原色一致，Float32网格接坪覆盖；真实帧由 volume_world_lifecycle_case 覆盖 | `run` `_test_detail_material` `_test_satellite_profile` `_test_tactical_profile` `_test_road_joins` `_check` |
| `tools/build_desert_tactical_context.py` | Python离线工具 | [沙漠候选] 显式OSM/依赖/报告路径，保留源节点和楼体净空，源道路并集按实际地坪裁切；输出四区三角、逐设施轮廓、接坪点与几何差集审计 | `project` `triangles` `region`；CLI `--source` `--deps` `--report-dir` `--output` |
| `experiments/volume_desert_tactical_context.gd` | RefCounted | [沙漠默认] 统一地表/建筑风格选择，空环境变量默认启用，显式source/off回退且不影响其他地图；四区域静态墙/顶/道路；同步与4毫秒分帧共用构图，40000三角上限，不创建玩法实体 | `is_enabled` `build` `begin_build` `step_build` `finish_build` `_height` `_roofs` `_up_triangle` |
| `tests/test_volume_aircraft_catalog.gd` | RefCounted | [测试] 当前已制作机型逐架验证唯一归一化 LOD0 结构、法线/封闭、厚度、真实长宽比、缓存、600 面预算、稳定身份、未知类型拒绝；同时验证每个机型的 LOD1/LOD2 均降面、各自 320/128 面预算、轮廓尺寸、对称性、涂装掩码且 LOD1 严格比 LOD2 复杂，以及挂载槽、弹药/能量状态和旋翼机运行时拆件；由 volume_world 调用 | `run` `_test_runtime_mounts` `_valid_triangles` `_symmetric` `_forward_nose` `_profile_signature` `_expect` |
| `tests/volume_aircraft_multiview_qa_runner.gd` | Node3D | [测试/Visual/导出] LOD0/LOD1/LOD2 均覆盖全 71 型，普通页每页 8 架并为 Mother Goose 保留独立原生尺度页，生成顶/侧/前/游戏倾角四视图，逐架导出分档 GLB 与来源/尺寸/真实面数 manifest；渲染成功不自动等于人工 QA | `_ready` `_build_environment` `_build_models` `_set_page` `_build_overlay` `_set_view` `_capture_sequence` `_export_mesh`；bench `volume_aircraft_multiview` / `volume_aircraft_lod_multiview` / `volume_aircraft_lod2_multiview ... Shadow Visual` |
| `tests/volume_aircraft_runtime_qa_runner.gd` | Node2D | [测试/Visual] 70 个非 Mother Goose 规范 key 逐个加载真实 AircraftParams，分页验证稳定身份、三维批路由、PNG 回退、挂载/四组动态旋翼与释放后缓存清理；渲染成功仍需逐页人工验图 | `_ready` `_spawn_real_aircraft` `_build_overlay` `_set_page` `_run_qa` `_finish` `_check`；bench `volume_aircraft_runtime ... Shadow Visual` |
| `tests/test_volume_map_factory.gd` | RefCounted | [测试] 沙漠工厂不修改源、静态预算、机场/铁路接缝/枕木间距、屋顶高度；透明线路稳定高度顺序及顶点/UV/颜色守恒；铁路屏幕细节与方向一致削边的tactical/source/非卫星隔离；正式Visual入口解析门；两处道路短接线切向/覆盖及旧网格断口反证；全15栋源建筑底座铁路净空、原压轨反证、获准迁移地块的缓存平地/地被净空；机场场坪连通/承托/道路净空/地形边缘/实际提交；由 volume_world 调用 | `run` `_test_line_submission_order` `_test_rail_lod` `_test_road_joins` `_test_industrial_clearance` `_test_airport_services` `_check` |
| `experiments/volume_3d_combat.gd` | SurvivorMode 派生 | [隔离实验] F6 手动 Mother Goose 战斗，复用正式 Boss Debug 的 F-47 编队、输入/暂停/重开/终态；无 bench AI 或自动退出；观察场 B 进入 | `_ready` `_run_volume_smoke` |
| `experiments/volume_3d_desert.gd` | SurvivorMode 派生 | [隔离实验] 观察场 D / F6 进入完整沙漠三维战局，正式战区/地面战线/机场与 BOSS，F8 同场景重开；不记生涯、不消费教程，保留正常功勋结算 | `_ready` `_unhandled_input` `_start_first_run_tutorial` `archive_enabled` `_maybe_start_wingman_switch_tutorial` |
| `tests/volume_desert_smoke.gd` | volume_combat_smoke 派生 | [Visual] 真实沙漠三维入口、地理与任务、Tab/点击、四机位、F8/退出验证；不代表完整局或 FPS 验收 | `run`；bench `volume_3d_desert` |
| `tests/volume_combat_smoke.gd` | Node | [测试] 手动三维实验场实际鼠标/键盘命令、相机、Tab/暂停、F8 重开与返回主菜单的 Visual 冒烟；独立于被释放场景，不计性能毕业 | `run` `_wait_for_scene_release` `_key` `_mouse` `_check` |
| `experiments/volume_3d_desert.gd` | SurvivorMode 派生 | [隔离实验/真实玩法] 在沙漠 MapDocument 正式生存局上叠加三维飞机、卫星地表与三维道路/建筑；保留原 2D 地图权威、玩家输入、AI、武器与 HUD，禁用本轮教程/档案副作用 | `_ready` `_unhandled_input` `_start_first_run_tutorial` `archive_enabled` `_maybe_start_wingman_switch_tutorial` |
| `tests/volume_desert_smoke.gd` | Node | [测试] 三维沙漠真实玩法局的单位/地图/卫星/输入与相机 Visual 冒烟；不替代完整战役与 FPS 正式毕业 | `run` |
| `tests/test_volume_world.gd` / `tests/volume_world_lifecycle_case.gd` | RefCounted | [测试] 几何/法线/投影/地图/卫星与三级 LOD；真实 SceneTree 验证原生分辨率、2× MSAA、各刷新率逐帧提交、死亡保留三维与释放 | `run` `_check` |
| `tests/volume_formal_quality_runner.gd` | Node2D | [Visual] `volume_formal_quality`：正式透明合成与 F6 同源对照、移动/旋转/缩放相机真实投影误差、真实致死伤害后同网格涂装/淡出/释放截图 | `_ready` `_run` `_volume_point` `_capture` `_check` |
| `aircraft.gd` | `Aircraft extends CombatUnit` | [共享] 飞机主控（LOD 路由 + 损伤生命期 + 状态所有者；物理/武器/战斗/编队/热诱弹全部委托 aircraft/ 子模块）；运行时修改器字段、CD 速率和天气采样也集中在此；Cobra/Herbst 高频查询走缓存（`get_maneuver`/`get_herbst` 内联失效判定），子节点顺序变化时自动失效重建；`ac_phys.*` 细分桶只在 PerfBuckets 细分采样帧经 `_perf_lap` 计时，`aircraft_phys` 根桶恒计时；狂化病毒身份门先查技能旗标再取玩家引用；所有阵营有效雷达在类别/平加/高度叠加后统一封顶 9000 px；高密度错帧只做一次 phase 门控并以补偿 delta 完整更新，独占 directive 在父层物理前镜像 | `_physics_process` `take_damage` `_apply_damage` `_check_ground_crash` `_start_destroy` `_update_cobra_skill` `_update_evasion_herbst_skill` `_update_manual_dodge_skill` `try_manual_maneuver` `do_manual_dodge` `is_manual_maneuver_controlled` `set_evasion_mode` `cd_rate` `is_berserk_virus_wingman` `enforce_berserk_virus_free_mode` `_update_evasion` `_update_evasion_motion` `_update_cloud_state` `_refresh_maneuver_cache` `get_maneuver` `get_herbst` `is_lock_immune`（含 `sensor_hidden`）`get_flare_cooldown_ratio` `effective_radar_range_px` `MAX_EFFECTIVE_RADAR_RANGE_PX` `_draw()`（传感器隐藏时抑制本体绘制）+ 敌机/FFA 一梭安全门状态/纯查询 `_ai_gun_pause_timer` / `_ai_gun_burst_allowed` / `_uses_enemy_gun_burst_gate` + 真实出弹短窗 `_gun_muzzle_flash_remaining_s` + 5 个委托壳（`_missile_cannot_hit_but_gun_can` `_should_commit_gun_pass` `_is_gun_pass_finished` `_is_in_missile_envelope` `_choose_dogfight_pursuit_pos`）+ 2 个物理委托壳（`_effective_max_g` `_max_bank_angle_at_speed`） + 编队接口 `set_formation_target(leader, slot, keep_arrival)` / `clear_formation()`（2026-05-04 重构）+ `_ai_ref`（AIController 反向引用，由 AI._ready 设；`manual_control` 是 R 手动/AI 威胁自动机动分流真源）+ `_publish_equipment_to_legacy()`（commit 2/13 起）+ 意图仲裁 `submit_intent(source, ci)` / `withdraw_intent(source)` / `_resolve_intents(delta)` + 敌方护卫反应 `escort_guards` / `_alert_escort_guards()` + 机炮威胁锥淡出 `_gun_threat_fade` / `_update_gun_threat_indicator()` / `_reset_gun_threat()` + 物理插值白名单（`_ready` 开启并延迟重置；`_physics_process` 开头记 `interp_prev_xform` / `interp_prev_tick`，显示态按帧缓存于 `interp_cache_*`，`_notification` 处理重置并清缓存；`clear_trail()` 兼传送收口 `reset_physics_interpolation`，见 DisplayPacing） |
| `aircraft.gd`（加力窗口） | `Aircraft` | [共享] 肉鸽加力技能、专属载荷、签名技能与 HUD 的唯一窗口查询/生命周期边界；与 AI `evasion_mode` 和物理 `is_afterburner` 分离，setter 对称清理雾隐/弹仓计时 | `is_afterburner_mode_active` `set_afterburner_mode_active` |
| `aircraft.gd`（planner 状态） | `Aircraft` | [共享] TacticalPlanner 跨帧 plan / intent / extend 滞回的唯一所有者；AIController 只通过语义 API 请求清理，不了解字段布局 | `reset_tactical_plan_state` `_run_tactical_planner_if_enabled` `_apply_tactical_plan` |
| `aircraft.gd`（主动特殊机动） | `ActiveSpecialManeuver` | [共享] 五向互斥 R 入口的共享协调器；位移滚转/垂直越过动作曲线、10Hz AI 威胁门、命令排队、命中资格与 Squad 冷却；公开唯一技能 id/总冷却/共享剩余冷却供 HUD O(1) 只读 | `aircraft.gd:2494 is_active_special_maneuver` `aircraft.gd:2511 equipped_r_maneuver_id` `aircraft.gd:2525 r_maneuver_cooldown_total` `aircraft.gd:2540 r_maneuver_cooldown_remaining` `aircraft.gd:2592 _try_start_displacement_roll` `aircraft.gd:2617 _try_start_vertical_break` `aircraft.gd:2713 _update_active_special_maneuver` `aircraft.gd:2735 try_manual_maneuver` |
| `aircraft.gd`（高度动作/反制） | `AltitudeAction` | [共享] `NONE/CLIMB/DIVE` 统一运行时真源；玩家普通动作必须由一次真实 LOW/HIGH 命令变化武装且退出即消费，自然漂移/转弯掉高不重入；垂直越过保留显式动作；进入 CLIMB 开一次 4s 反制窗，严格 `GUN_TAILED` 与迫近导弹共用它 | `command_altitude_preference` `_set_altitude_action` `altitude_action_name` `_tick_climb_counter_window` `climb_counter_window_active` `gun_tailed_active` `report_gun_tailed` `try_climb_counter_missile` |
| `aircraft/control_intent.gd` | `ControlIntent extends RefCounted` | [共享] 控制意图值类型（Phase 1 重构，docs/planning/physics-ai-control-refactor.md §5）：SOURCE_TACTIC/EVADE/BRAKE/DIRECTIVE + PRIORITY 表；事件独占 DIRECTIVE=50 压过其它 AI 主张；哨兵 pursuit=INF / speed<0 / ab<0 = 不主张 | 字段 `pursuit_pos` `clear_pursuit` `pursuit_pri`（BRAKE=25 特例） `target_speed_kmh` `afterburner` |
| `aircraft/aircraft_flares.gd` | `AircraftFlares extends RefCounted` | [共享] 热诱弹子系统（静态方法首参 `ac: Aircraft`）；释放与装填倒计时统一消费 `ac.cd_rate("flare")`；玩家、直属僚机与 TEAM_ALLY 友军自卫/护卫共用完整来袭资格 + TTI≤1.0s / 200m 末段门，失导/错目标/同阵营/飞离/追不上时不投，加力窗口内暂缓自动投放；敌机配置失误只保留 10% 为实际不投概率，投焰后建立可命中的 1.25s break，并按有效 AI 水平 80%→95% 采样，不再瞬时 jam/穿透；视觉固定六波 `2/2/1/2/2/1` 共 10 枚、0.90s 左右侧抛、寿命 3.0–4.8s | `update(ac, delta)` `release(ac, target_missile)` `enemy_release_fail_chance_for_configured(configured_fail)` `enemy_flare_break_chance(ac)` `enemy_flare_break_chance_for_skill(skill)` `player_flare_should_trigger(ac, m)` `try_cover_flare(ac, leader)` `release_cover(ac, leader, missile, d_leader_m)` `flare_ready(ac)` `_queue_visual_burst(ac)` `_update_particles(ac, delta)` `_spawn_wave(ac, pos, heading, count, wave)` `calc_jam_chance(ac, m)` `cooldown_ratio(ac)` |
| `aircraft/aircraft_weapons.gd` | `AircraftWeapons extends RefCounted` | [共享] 武器子系统；机炮/火箭/主弹/副槽冷却统一消费 `ac.cd_rate("weapon")`，导弹装填消费 ESM rate × `ac.cd_rate("missile_reload")`；飞机单锁、双方编队机会火控和多锁齐射共用档案 skill/jitter、稳定窗口、两轮前置点与预测包络门；敌方最终机炮梭射/导弹离架经 Encounter Lethal Slot 错峰，跟踪/锁定/阵型导航不受影响；`missile_lead_point` 是发射门、发射前 planner 与离架航向的共享真源（spec: missile-launch-discipline）；统一判定 `GUN_TAILED`，CLIMB 反制锁住已承诺梭的旧世界射向，高度循环弹药含编队早退结算 | `update_weapon_mode(ac)` `auto_gun_scan(ac)`（普通机炮仅 Aircraft 且守交战纪律；炮艇优先射程内玩家 `commanded_target`，含 MountTarget；否则玩家全队各机独立 3Hz 最近 Aircraft/GroundUnit 扫描，不锁普通 planner 目标池）`update_formation_opportunity_weapons(ac, delta)` `_update_formation_opportunity_gun(ac, delta)` `update_passive_gunship(ac, delta)` `update_altitude_cycle_ammo(ac, delta)` `update_gun(ac, delta)`（梭射状态机 + 目标实例锁存/逐 tick 提前点刷新 + HOSTILE/FFA 一次机会一梭/末发后停火 3s，spec: weapons/gun-burst-fire）`_gun_target_from_id` `_gunship_command_target` `_refresh_committed_gun_aim` `_fire_gun_round(ac, gun)`（真实出弹才刷新枪口闪光）`update_ciws(ac, delta)` `update_rocket(ac, delta)` / `rocket_burst_plan` `update_formation_passive_missile(ac, delta)`（双方编队 20Hz 机会火控）`update_missile(ac, delta)` `_missile_skill` `_has_stable_launch_window` `_has_lead_intercept_solution` `missile_lead_point` `_fire_missile_at(..., is_secondary)` `_emit_missile` `_fire_multi_lock_salvo` `update_secondary_radar(ac, delta)` `update_secondary_missile(ac, delta)` |
| `aircraft/aircraft_weapons.gd`（锁数齐射） | `_fire_multi_lock_salvo` / `_salvo_fire_count` | [共享] 一轮覆盖数取有效锁数、合法目标与弹量最小值；每轮统一进入正常导弹冷却 | `aircraft/aircraft_weapons.gd:1338 _fire_multi_lock_salvo` `aircraft/aircraft_weapons.gd:1518 _salvo_fire_count` |
| `aircraft/aircraft_weapons.gd`（发射提交） | `_emit_missile` / `_finish_main_missile_cycle` | [共享] 单发、主弹齐射和副弹共用发射/日志/战报/通知/音效/弹药提交；主弹 cooldown/crank/reload 按一轮单独提交，齐射不按弹数重复冷却 | `aircraft/aircraft_weapons.gd:1295 _emit_missile` `aircraft/aircraft_weapons.gd:1327 _finish_main_missile_cycle` |
| `aircraft/aircraft_physics.gd` | `AircraftPhysics extends RefCounted` | [共享] 物理子系统（每帧演算 + 查询函数 + `effective_*()` buff 注入层）；实飞 / 预测的目标航向、bank、航向、高度、速度演化均走共享纯函数（SEAM-017 单一公式源）；PD 转弯以小角参考低通、解析 LOS 前馈、变化率限制和连续死区吸收追击 / 航点分频台阶，≥20° 新命令立即接管；急刹拖拽以 12px/110px 手势映射持续 G 坡度，绕过普通航点预防性低速坡度帽但服从正式失速/恢复，转向时允许载荷失速；玩家 360 步预测支持有界分段推进；同一函数内 buff 输入不变时以可选参数复用已取值（`effective_max_g(ac, g_buff_mult)` / `effective_max_g_instant(ac, g_buff_mult)` / `corner_speed_kmh(ac, max_g_sustained)` / `_bank_roll_rate_rad_s(..., base_rate)`，缺省 NAN = 现场计算），buff 注入点仍只在 `_g_buff_mult` 与各 `effective_*()` | `update_target_heading(ac)` `_target_heading_state(...)` `brake_steer_input_from_dx(dx)` `_brake_steer_target_bank(...)` `update_bank(ac, delta)` `_filter_heading_reference(...)` `_resolve_turn_lock_state(...)` `_bank_limit_rad(...)` `_bank_roll_rate_rad_s(...)` `_integrate_bank_state(...)` `_apply_bank_recovery(...)` `step_bank(st, delta)` `update_heading(ac, delta)` `_integrate_heading_rad(...)` `update_speed(ac, delta)` `_speed_target_ms(...)` `_integrate_speed_ms(...)` `step_speed(st, delta)` `update_altitude(ac, delta)` `_integrate_altitude_state(...)` `update_stall(ac)` `update_g_load(ac)` `apply_movement(ac, delta)` `update_rotorcraft(ac, delta)` `update_shock_absorb(ac, delta)` `update_fuel(ac, delta)` `update_energy_management(ac)` `set_afterburner(ac, on)` + `PredictionWork` `begin_player_path_prediction` `advance_player_path_prediction` `player_path_prediction_result` `predict_player_path` + `base_stall_kmh` `base_roll_rate` `base_accel` `base_max_speed_kmh` `base_cruise_kmh` `effective_accel_mult` `effective_decel_mult` + 机动守卫 `maneuver_overrides_speed(ac)` / `maneuver_overrides_g(ac)` + 查询 `max_bank_angle` `effective_max_g` `corner_speed_kmh` `stall_speed` `max_speed_at_altitude` `air_density_ratio` `max_bank_angle_at_speed` |
| `aircraft/aircraft_combat_tracking.gd` | `AircraftCombatTracking extends RefCounted` | [共享] 战斗追踪子系统（~654 行，BFM 级目标追踪 + 武器模式判定） | `update_combat(ac, delta)` `update_combat_ground_attack(ac)` `choose_dogfight_pursuit_pos(ac, ...)` `missile_cannot_hit_but_gun_can(ac)` `should_commit_gun_pass(ac)` `is_gun_pass_finished(ac)` `is_in_missile_envelope(ac, tgt, msl)` + 内部日志 `_log_pursuit_snapshot` `_log_enemy_squads_engaging_player` |
| `aircraft/aircraft_formation.gd` | `AircraftFormation extends RefCounted` | [共享] LOD 1 编队托管子系统（阶段流水线；顶部有架构图 + bug 回溯地图 10 条）；玩家僚机追高度本身不发布动作，只镜像长机经 LOW/HIGH 命令或垂直越过发布的 CLIMB/DIVE；非玩家保持按自身实际垂直速度发布 | `update_follow(ac, delta)` 阶段流水线：`_build_context` → `_resolve_target_heading` → `_update_bank_via_pd`（PD 航向+bank 一体，与战斗/巡航同源） → `_update_speed`(20Hz) → `_log_formation_debug` → `_update_altitude`(20Hz，发布高度动作) → `_update_position` → `_periodic_and_visuals`；`Branch` 枚举（旧编队私有 `_update_heading`/`_update_bank`/leader-bank 混合/翻转守卫已随 PD 重写退役，死代码 2026-07-03 删除） |
| `aircraft_renderer.gd` | `AircraftRenderer extends RefCounted` | [共享] 飞机绘制系统；已登记机型优先绘制顶视 PNG 蒙版并运行时换色，滚转用不增加纹理提交的暗色壳层 + 顶面/机腹投影保留 90° 体积，未知/UGC 机型回退旧多边形并复用不归零倍率；所有坠毁继续绘制正式机型轮廓，并把专用缩放/透明度只烘进 icon draw，不污染屏幕空间状态栏；Black Star 走原创低矮升力体 `hyper_a` 轮廓（黑色热防护 / 银色前缘 / 橙色尾焰）；以 `Variant → TYPE_OBJECT → is_instance_valid → Aircraft` 顺序净化跨帧引用（`safe_player_ref` 读强类型 `player_ref` 槽，热路径直接 `is_instance_valid`，失效即清空）；机炮/加力/导弹尾焰/电磁炮抖动走时间+实例 ID 的确定性视觉噪声，不消费战斗 RNG；含任意悬停飞机的雷达/机炮参考范围、敌对 FFA 机炮威胁锥、当前操控机急刹真实机炮参考锥、真实出弹短窗枪口闪光、炮艇 360° 机炮射程圈、ESM 3000m 蓝色淡填充光环、DEADAIR 八段暴露环与尾迹批绘；锁定符号抵消实际视口缩放，并以现有尺寸为高空上限按目标高度连续缩小；飞机标签剥离窗口 stretch 后按真实相机 0.35/0.40 迟滞分档（窗口化/最大化一致），近镜头按机体屏幕半径外移并把文字原点对齐物理像素，折叠档保留机型/代号/速度及当前 buff/debuff，身份+速度批量提交，按住 Alt 临时完整；0.26 以下普通友军目标标记只保留主线，当前操控机/Alt 仍保留端点与 L 角；玩家预测轨迹由 SurvivorMode 单一入口以 24 步/帧推进 360 步物理解算，完成后按 4:1 抽样为最多 91 个显示点，`_draw` 只消费缓存；玩家小队每架飞机各档都显示纯机型编号 + 完整呼号（`F-14 [Ultra]`），长机型名称后缀只留一个首字母，绿色 ALLY 标签只去掉 `ALLY-`、不缩呼号；仅蓝色玩家小队在简略档以 14px 矩形短名反相闪烁 FLR/GUN/MSL，非当前操控机的导弹装填统一白字，完整档显示全部百分比 | `safe_aircraft_ref` `safe_player_ref` `visual_noise01_for` `visual_noise01` `support_range_fill_color` `support_range_ring_color` `inverse_screen_scale_for` `screen_space_inverse_scale` `bank_volume_projection_for` `bank_volume_face_alpha_for` `data_label_screen_offset_for` `data_label_screen_offset` `lock_box_altitude_scale_for` `lock_box_altitude_scale` `label_lod_scale_for` `label_lod_scale` `next_compact_label_state` `should_draw_compact_label` `target_marker_detail_visible_at_scale` `status_label_entries` `draw_data_label_compact` `draw_reload_indicators` `reload_indicator_team_visible` `reload_indicator_style` `reload_indicator_tokens` `weapon_label_color` `secondary_reload_progress` `aircraft_model_designation` `compact_aircraft_name` `ally_identity_label` `airframe_identity_label` `controlled_identity_label` `update_predicted_path_cache` `prediction_display_result` `should_show_hover_radar_range` `should_show_gun_reference` `should_draw_gun_muzzle_flash` `draw_gun_cone` `draw_esm_aura` `draw_deadair_exposure` `draw_radar_cone` `draw_lock_indicator` `draw_lock_box` `draw_secondary_lock_indicators` `draw_aircraft_icon_destroyed` `draw_aircraft_icon` `draw_hyper_a_icon` `draw_data_label` `draw_target_line` `draw_predicted_path` `draw_formation_debug` |
| `aircraft_renderer.gd`（高度动作反馈） | `AircraftRenderer` 静态绘制 | [共享] 详细档把固定英文 CLIMB/DIVE 合并进既有 ALT 行，战略简略档省略动作词；GUN_TAILED 保留独立状态行，不绘制动作专属机体气流 | `status_label_entries` `draw_data_label_minimal` `draw_data_label` |
| `aircraft_renderer.gd`（战斗单位状态栏） | `AircraftRenderer` 静态登记/绘制 | [共享/UI] 飞机、无人机、地面、SAM、雷达、战略目标、舰船和导弹只向统一登记表提交内容；最终标签由独立屏幕空间覆盖层逐帧定位，单位后续旋转且不重绘也不会带歪标签；统一英文 HDG/SPD/ALT/RNG/HP 格式与非英文身份 fail-closed；玩家/僚机受伤反相，非飞机状态也通过 status_label_entries 合入信息牌，旧状态条入口只留 DEADAIR 环，坠毁终态栏复用同一规则 | `status_panel_overlay_transform_for` `install_status_overlay` `uninstall_status_overlay` `clear_unit_status_panel` `draw_registered_status_panels` `draw_unit_status_panel` `status_heading_text` `status_speed_knots_text` `status_ground_speed_text` `status_altitude_text` `status_range_text` `status_hp_text` `english_status_identity` `status_damage_flash_phase_for` `draw_destroyed_status_label` `draw_status_icons` |
| `aircraft_renderer.gd`（机体与战术 UI 配色边界） | `AircraftRenderer` 静态配色 | [共享/UI] `icon_color/wing_color` 只进入机体绘制；状态栏使用阵营/操控语义色，combat target 线对玩家小队统一蓝并保留独立突击黄 | `unit_status_panel_colors` `combat_target_line_color` `draw_target_line` |
| `aircraft_silhouette_catalog.gd` | `RefCounted` 静态目录 | 44 张已审顶视 alpha PNG 的路径、首次解码缓存、同型号显示名别名、24 个原创/虚构旧绘制别名（含 Hyper-A G0–G3 专用 renderer）、特殊尺寸、机体族视觉厚度与壳层/表面双色蒙版绘制；T0/低位 T1 七架现实机全部直接映射，MQ-109/110/111 共用用户批准的 `mq109_family` 并以 0.53 缩放保持旧无人机尺寸；原始 PNG 由 export include filter 随包携带 | `TEXTURE_PATHS` `DISPLAY_KEYS` `LEGACY_DISPLAY_NAMES` `VOLUME_THICKNESS` `key_for` `_texture_for` `prewarm_textures`（Loading 按帧预算解码全部轮廓） `draw_scale_for` `volume_thickness_for` `draw_icon` |
| `aircraft_params.gd` | `AircraftParams extends Resource` | [共享] 飞机数据；含固定翼/旋翼机 flight model、旋翼机角色、真实视觉尺寸与主雷达对空武器能力查询 | `FlightModel` `RotorcraftRole` `visual_length_m` `visual_span_m` `has_lock_capable_weapon` |
| `survivor/sensor_stealth_controller.gd` | `SensorStealthController extends RefCounted` | [生存] 敌机传感器隐形唯一低频所有者；复用主雷达配对登记照射，tick 尾结算 5s 失联，任一玩家机进入 1000px 立即揭露；反隐技能在同一配对内扩距，并复用玩家观察者集合处理被锁现形、combat_target 保持与光学 cloak 覆盖；同 tick 新隐形目标合批后只扫一次玩家观察者；导演演员冻结计时 | `begin_radar_tick` `observe` `finish_radar_tick` `_counter_stealth_extended_contact` `_revealed_by_counter_stealth` `_held_by_ghost_buster` `release_player_sensor_refs_batch` |
| `aircraft.gd`（敌机传感器隐形） | `Aircraft` 状态消费 | [共享] 保存玩家侧接触逻辑态与视觉 alpha；逻辑先切换、单 tween 从当前 alpha 连续反向，完全隐形只画匿名任务 TGT，并停尾迹 process | `is_hidden_from_player_sensors` `set_sensor_contact_hidden` `_set_sensor_contact_visual_alpha` |
| `tests/test_sensor_stealth.gd` / `tests/sensor_stealth_visual_qa_runner.gd` | 专项测试 | [测试] 六型资源（含 F-47/YF-23）、5s 宽限、1000px 近距揭露、隐形目标写入拒绝、左下雷达匿名提示、JAM/锥外/Snowblind/无武器、多目标批量释放、导演演员隔离、双层尾迹、导弹失导与 `TGT + ???` 渐变 Visual | bench `sensor_stealth`（63 项）/ `sensor_stealth_visual` |
| `modifier_trace.gd` | `ModifierTrace extends RefCounted`（全静态） | [Debug] 非热路径运行时修改器追踪器；逐来源临时清空并重读真实 accessor，输出 base→final 与来源差分，调用后完整恢复状态 | `explain(ac)` `print_report(ac)`；生存模式 `Shift+F12` |
| `aircraft_destruction.gd` | `AircraftDestruction extends RefCounted` | [共享] 飞机受击与击毁终态：把真实命中坐标分为机鼻、尾部引擎、左右翼、中心；一次性局部 RNG 改变坠毁时长/旋转/下坠/减速且不消费玩法随机。全部伤害统一按 fighter/bomber/heli 保留模型、状态栏并旋转掉高；失控阶段保持不透明，终点爆炸触发帧仍保留机体，之后继续运动 0.85s（前 0.25s 完全不透明）才淡出释放。普通飞机/无人机终点只播一个小方框，只有 `destruction_class=large`、bomber 或尺寸≥28m 的有人大型机才按受击部位排入五点结构波 | `record_hit` `hit_zone_for_local` `destruction_size_class` `start(ac)` `_configure_crash_motion` `update(ac, delta)` `crash_visual_progress` `_update_post_breakup_linger` `_emit_terminal_breakup` `_large_breakup_route` `_airframe_half_extents` `_emit_airframe_wave` `_stop_trail`；spec `systems/aircraft-destruction-presentation` |
| `cobra_maneuver.gd` | `CobraManeuver extends Node` | [共享] 眼镜蛇机动模块（挂载到 Aircraft 子节点） | `activate` `_physics_process`（三阶段状态机） |
| `herbst_maneuver.gd` | `HerbstManeuver extends Node` | [共享] 赫尔贝特轮 J-Turn 模块；默认可重复，profile 可用 `max_uses` / `requires_flares_empty` 限制次数与 flare 分层（WhiteTea 每机一次） | `activate` `_physics_process`（DECEL→TURN→ACCEL） |
| `ai/tactical/engagement_speed_governor.gd` | `EngagementSpeedGovernor extends RefCounted`（全静态） | [共享] 交战速度治理：反解"要咬住 dist 外目标速度最多多少"，压掉"盘旋半径 > 交战距离 → 机头几何上指不到 → 满 G 绕圈"死结（playtest log 20260720_172222）。地板=角点速度，绝不压到失速螺旋；只改 plan 速度主张，不碰 G/bank/几何。目前只对王牌中队生效 | 常量 `RADIUS_RATIO=0.5` `MAX_GOVERN_DIST_M=6000`；`speed_cap_kmh(dist,max_g,corner)` `apply(s,p)` `is_governed(ac)`；接线在 `aircraft.gd` planner 之后一行 |
| `survivor/ace_tier.gd` | `AceTier extends RefCounted`（全静态） | [生存] **王牌中队 tier 语义的单一归属地**（spec systems/ace-squadron-tier）；收敛原本散在 LOD/缩放/HP cap 三处的判定，调用方只问不判；BOSS ⊂ 王牌中队，tier 待遇一律走本模块不看 `category=="boss"` | 常量 `TIER_META` `TIER_ACE` `MAX_HP=100`；`is_ace_type`（成员名单，加新王牌中队只改这里）`mark` `is_ace` `no_scale` `exempt_from_hp_cap` `apply_hp` |
| `survivor/ace_squad.gd` | `AceSquad extends BossEncounter` | [生存] 王牌中队 BOSS 基类（飞机 BOSS 框架）；纯**小队级状态机**，状态切换才改 AI 字段，不每帧覆盖 → 杜绝 BFM 战术 timer 抖动；Wraith CLOAK 首次及每次结束后严格 60s CD、1s 渐变、当前玩家 1000px 内禁止/打断，逻辑沿清全体玩家 `combat_target`/主副锁、保留点名，并与传感器隐形共同仲裁尾迹；自管世界边缘软收容（2000px 触发→3000px 安全带），并在 40px 触线前硬钳；只守世界外框、**不是锚点 leash** | 状态：`INTRO/PURSUIT/CLOAK`（**无归巢态**，ANCHOR_HOLD 已删）；角色 `AceRole{NONE,KNIGHT,SNIPER}` + `ROLE_META` + `role_of()`；边缘入口 `_update_boundary_recovery` / 纯几何 `boundary_recovery_point`；钩子 `_pursuit_enter` `_pursuit_update`（每 0.5s 软重连）`_should_enter_cloak` `_cloak_enter/exit/update` `_has_close_player_contact`；`spawn` `update` `engage` `set_player_ref` `_apply_role` |
| `survivor/boss_encounter.gd` | `BossEncounter extends RefCounted` | [生存] BOSS encounter 统一接口 + 通关强化次数载体；`prior_defeats` 只在 spawn 前注入；`hud_style` 允许主题型决战选择非 BOSS HUD；复合 BOSS 可覆写 `get_hud_entries()` 提供状态条目；逃脱目标覆写失败协议 | `configure_progression(defeat_count)` `spawn` `update` `engage` `is_defeated` `has_failed` `failure_reason` `set_player_ref` `get_hud_entries` |
| `survivor/boss_registry.gd` | `BossRegistry extends RefCounted` | [生存] 注册 BOSS 的构造器、显示名、四项轮换与登场身份横幅元数据；包含 `BLACK_STAR`，横幅消费 name/role/motto key + callsign + palette token，禁止 UI 按 boss id 分支 | `instantiate` `name_key_for` `banner_metadata_for` `pick_for_map` `pick_by_rotation` `rotation_candidates` |
| `survivor/armored_train_unit.gd` | `ArmoredTrainUnit extends Node2D` | [沙漠/BOSS] 十四节超尺度编组控制器：正式底图矿区 railway 弧长采样；每节以中心前后 88px 转向架双点定姿、18px 活动车钩，接战后全车可锁定但仅尾段可打断，断节惯性脱离并使剩余整车 +60km/h，分段功能当帧清理、当前车尾逃脱；PRE_STAGE 在硬暂停下以 ALWAYS 沿铁路 330→420km/h 驶入，420px 边界 inset 保证 0.26 广角安全区，完整入图才开放全车锁定；电磁炮仅在左右侧舷各 ±50° 锁定，对准保持 1.0s 后才开始海岸巨炮同款 5.5s 蓄力/90px 半径/45伤害直线 AOE | `ARRIVAL_BOUNDARY_INSET_PX` `configure_route` `arm_segments` `begin_arrival_ingress` `finish_arrival_ingress` `is_arrival_fully_inside` `_sample_route_pose` `_sample_segment_pose` `_refresh_segment_poses` `_update_movement` `on_segment_broken` `railgun_side_for_position` `_update_railgun` `_begin_railgun_lock` `_begin_railgun_charge` `_fire_railgun_snapshot` `aggregate_hp` |
| `survivor/armored_train_segment.gd` | `ArmoredTrainSegment extends GroundUnit` | [沙漠/BOSS] 十四节真实锁定/伤害目标；每节 236×84px 重装车体、十四种主题，前后转向架位置由编组双点轨道采样注入；可锁定层与尾节可承伤层独立，非尾段伤害入口 fail-closed，尾节按真实导弹伤害结算；打断后以惯性侧向旋出并回报编组控制器 | `configure` `set_train_pose` `set_targetable` `set_damageable` `can_accept_new_hit` `take_damage` `take_missile_damage` `_start_destroy` `_detach_from_train` `_draw_theme` `_status_label_lines` |
| `survivor/armored_train_boss.gd` | `ArmoredTrainBoss extends BossEncounter` | [沙漠/BOSS] IRON SERPENT encounter；生成即启动铁路进场，engage 时强制整列完整入图并暴露车尾；维护存活/逃脱互斥终态并向通用事件层报告失败 | `spawn` `update` `engage` `has_failed` `failure_reason` `get_display_members` |
| `survivor/the_crucible_boss.gd` | `TheCrucibleEncounter extends BossEncounter` | [沙漠/决战事件] THE CRUCIBLE 是战斗主题而非同名 BOSS/中队/角色；17 支 Ace 队与 Crucible-only Hound 双机共 18 队 73 架以独立 FFA team 接力参战，首发为 2NDWAVE / GIMMICK / GOOFIGHTERS，MARATHON 延后到第 6 批；开场三队先进行 8s 纯 Ace 混战，之后每支活跃队只由 1 名稳定猎手压玩家，其余成员继续 FFA，并可从后半球机会主义抢攻正在缠斗玩家的敌方 Ace；同屏最多三队，一队全灭 3s 后只补一队；出生槽相对玩家航向在 3600–6000px 的 270° 环带按当前镜头外推/侧搜并排除六点钟 ±45°，初次入场进到 3000px 后才交还脱战回收；Hound-1/2 最终入场并以完整模拟/AI 频率运行。越过玩家 7.2km 后暂离编队，以角点速度上限执行独占三层环返场；HUD 快照只含已入场存活成员 | `spawn` `engage` `update` `set_player_ref` `get_display_members` `get_hud_entries` `aggro_score` `rear_attack_opportunity_score` `entry_relative_bearing_deg_for` `entry_position_for` `_entry_spawn_position_for` `is_opening_melee_active` `visible_battle_score` `_spawn_next_squad` `_activate_squad` `_retarget_all` `_assign_player_hunters` `_try_acquire_player` `_acquire_target` `_is_pressuring_player` `_force_reentry_if_strayed` `_complete_reentry` `_active_squad_count` `_target_candidates` `_live_engaged_members` |
| `survivor/ace_battle_bar.gd` | `AceBattleBar extends PanelContainer` | [生存/UI] 常规王牌中队分段命条的唯一视觉实现；普通地图 Ace 与 The Crucible 活跃队伍共用同一构建、徽章、配色和段更新代码 | `set_info` |
| `survivor/land_carrier_unit.gd` | `LandCarrierUnit extends GroundUnit` | [沙漠/BOSS] 独立连续履带陆地航母；620×280px 低矮装甲平台、边界内出生后向中心推进、4 个真实 F/A-18 嵌入式停机位、驻机刚体跟随/起飞与 8 个真实防空挂点；不依赖铁路且禁止海船剪影 | `configure_patrol` `spawn_parked_aircraft` `launch_parked_aircraft` `arm_mounts` `mount_world_pose` `_draw_ground_icon` `take_missile_damage` |
| `survivor/land_carrier_boss.gd` | `LandCarrierBoss extends BossEncounter` | [沙漠/BOSS] BEHEMOTH encounter；初始 4 驻机、接战 2 架起飞、120s 周期弹射、整场创建上限 8；自定义紧凑 Boss HUD | `spawn` `engage` `update` `get_display_members` `get_hud_entries` |
| `survivor/desert_front_controller.gd` | `DesertFrontController extends Node2D` | [沙漠] 集中式 RTS 气氛权威：3v3 初始 SPG、据点产兵、敌军补充、2Hz 火炮快照与 4 机 AH-64 波次；不为每个演员新增决策节点 | `setup` `on_zone_captured` `_update_production` `_update_helicopter_waves` `_update_artillery_fire` `_resolve_shell` |
| `survivor/hyper_a_boss.gd` | `HyperABoss extends BossEncounter` | [生存] Black Star 集中式双根分裂 BOSS：两棵 `1→2→4→8` 节点账本、根机 / G1 / G2 高空再入、AOE、四代独立饱和导弹火控与特殊状态武器静默、G0–G2 冲刺 / 火箭 / 终点急刹扇形冲击波 / 6s 散热 SLOW、分裂、树 HUD 与胜利门；根机真实下降起止发 `root_descent_started/finished` 供事件层同步无线电与玩家演出视觉；循环再入为 40–50s 间隔，越过 15km 语义离场时解除全部目标 / 雷达锁存，树 HUD 保留高空高度倒数，随后独立等待 7–10s 才俯冲；高空序列期间其它分裂体暂停倒数且至少再错峰 12s；冲锋蓄力沿共享物理减速转向，机头对线后才发射；特殊行为集中更新，不为 30 节点新增循环 | `spawn` `engage` `update` `get_hud_entries` `generation_counts` `_spawn_body` `_begin_descent` `_begin_climb` `_begin_high_altitude_hold` `_stagger_other_reentries` `_update_high_altitude_hold` `_begin_dash_telegraph` `_update_telegraph` `_trigger_brake_shockwave` `_point_in_sector` `_fire_lateral_rockets` `_enter_cooldown` `_handle_body_defeated` `_check_victory` |
| `survivor/hyper_a_threat_overlay.gd` | `HyperAThreatOverlay extends Node2D` | [生存/表现] Black Star 同源危险快照绘制：再入 AOE 圆、由机体近端向远端生长的冲刺危险带、仅在线满后显示的终点急刹预警扇区与实际结算后的扩散波、撞击 / 分裂冲击环；无 process，只由 encounter 变更时 `sync` 并重绘 | `sync` `_draw` `_draw_brake_warning` `_draw_brake_flash` `_sector_polygon` |
| `survivor/wraith_tactics.gd` | `WraithTactics extends RefCounted` | [生存] WRAITH 队级战术状态机（spec wraith-squadron §2.3）：PERCH→BRACKET→PRESS→RESET 四相闭环 + 退化检测。**不每帧覆盖 AI 字段**——走位下 AIDirective、包夹写 surround_bearing、PRESS 相完全放手 | `setup` `start` `stop` `update` `_decide_next` `_enter_phase/_exit_phase/_update_phase` `_perch_enter` `_bracket_enter/_bracket_update` `_reset_enter` `_tick_degradation` **纯函数** `pick_bait` `wing_bearings` `axis_heading` `is_biting` `average_nose_off_deg` `perch_tier_for` |
| `survivor/f47_ace_squad.gd` | `F47AceSquad extends AceSquad` | [生存] Wraith 四机战术实现；首败后在 `engage` 追加 2 架可正常锁定的 YF-23，沿玩家→Wraith 轴在队形后方潜伏（离玩家至少 5000px）；不进演出/血条/胜利判定，切控时随 encounter 重定向 | `spawn` `engage` `set_player_ref` `support_count_for_progression` `support_spawn_positions` `configure_progression_support_aircraft` `_spawn_progression_support` `_configure_spawn` `_configure_close_fighter_combat` `_configure_ranged_striker_combat` |
| `survivor/carrier_strike_group.gd` | `CarrierStrikeGroup extends BossEncounter` | [生存] LADON 航母战斗群两阶段 BOSS；通关分层只改 Phase 1 护航编成（初见 0CG+2DDG+6FFG，首败后 2CG+2DDG+8FFG），摆位按实际编成校验水域 | `spawn` `update` `engage` `set_player_ref` `escort_counts_for_progression` `_build_escort_plan` `_pick_water_placement` |
| `survivor/poltergeist_squad.gd` | `PoltergeistSquad extends AceSquad` | [生存] CSG 二阶段 F-14 母舰死守小队；弹射四阶段状态机（FROZEN→FADING→CATAPULT→FLYING）+ 起飞保护期 + 覆写 `_tactics_*` 钩子接 PoltergeistTactics | `spawn` `update` `_tick_phase` `_tactics_enter/_update/_exit` `_configure_spawn` |
| `survivor/poltergeist_tactics.gd` | `PoltergeistTactics extends RefCounted` | [生存] POLTERGEIST 队级战术（spec bosses/poltergeist-squadron）：**死锁单机换手**——共速绕圈达阈值 → 只把最咬不住的**1 架**拽去爬升拉开重整、其余继续压（同时换手上限=1）。区别于 Wraith 全队 RESET；不每帧覆盖 AI 字段，走位下 AIDirective | `setup` `start` `stop` `update` `_sample_and_dispatch` `_begin_reset` `_tick_active_resets` **纯函数** `nose_off_deg` |
| `survivor/ace_squad_profiles.gd` | `AceSquadProfiles`（全静态注册表） | [生存] 17 支常规轮换王牌 + ORION 宿敌 + HOUND 熔炉专属，共 19 份编成/包装/flare/主题数据；`pool_at` 显式排除 nemesis 与 crucible_only，Hound 不污染正常轮换 | `pool_at` `scheduled_wave_count` `advance_scheduled_wave_count` `build_run_order` `defeat_units` `estimated_ttk_s` |
| `survivor/ace_support_squad.gd` | `AceSupportSquad extends AceSquad` | [生存] **非 BOSS 王牌支援中队**：profile 驱动混编/装备/flare/专属机炮或无人机参数资源；挂低频主题控制器；含 WhiteTea 逐机 `gun_lancer` joust + 单次 J-turn 注入 | `_init` `_configure_spawn` `_template`（base/params/gun/flare 只读模板常驻，生成仍 duplicate） `prewarm_templates` `_duplicate_aircraft_params` `_element_of` `_member_type` `_member_role` `update_theme` `set_player_ref` `is_ammo_dry` |
| `survivor/ace_squad_theme_controller.gd` | `AceSquadThemeController extends RefCounted` | [生存/AI] 扩编王牌与 Hound 共用的中队级 2Hz 主题控制层：命运分工、鞭梢接力、IDO 共享 flare、高度链、分配/点杀、表决、镜像、空位复仇与 Hound 远近协同/幸存复仇；The Crucible 可关闭目标写入只保留主题动作，无逐机 Node/tick | `update` `set_player_ref` `_sync_shared_flares` `_deal_player_targets` `_focus_weakest_player` `_apply_whip_relay` `_apply_funeral` `_apply_hound_betrayal` |
| `survivor/mother_goose_boss.gd` | `MotherGooseBoss extends BossEncounter` | [生存] Mother Goose 空中航母 BOSS（10 挂点+弱点、UAV 蜂群、JAM、VLS）；半血 MQ-X 精英对挂三发点射/强化导弹/反导激光/F-22 级隐形并走 joust 攻击跑；初见向蜂群关闭 MQ-111/112，首败后恢复完整型号池 | `spawn` `update` `engage` `get_display_members` `configure_mqx_ai` `_assign_patrol_ring` |
| `survivor/mother_goose_controller.gd` | `MotherGooseController extends Node2D` | [生存] Mother Goose 战斗逻辑控制器（boss 子节点）：每帧 tick jam_shield + uav_swarm，给场内玩家施加 jam；VLS 每 20s 排队且玩家进入 3000m 近身区时整轮停火；SwarmDirector lazy init + 1Hz tick + ATTACKER 角色跳 stray recall | `_process` `_apply_jam_field` `_init_swarm_director` `_update_vls_salvo` `_enqueue_vls_salvo` `vls_can_launch_at_distance` `_update_stray_recall` `_update_designation` |
| `survivor/mother_goose_jam_shield.gd` | `MotherGooseJamShield extends RefCounted` | [生存] 周期性干扰场状态机：COOLDOWN 60s → WARNING 4s → EXPANDING 8s（R=300→1500） → SUSTAIN 8s；完整循环 80s | `start` `update` `is_effect_active` `is_warning_active` `contains_world_point` `draw_into(ci, shield)` |
| `survivor/mother_goose_uav_swarm.gd` | `MotherGooseUAVSwarm extends RefCounted` | [生存] Mother Goose UAV 蜂群管理：起始 12 / 上限 30；常态固定每 20s 补 2，指定猎杀 ACTIVE 内 0.0s/7.5s 两波各 6（固定 2 架/2s drain）；通关门控 MQ-111/112，并仅在开放时执行 MQ-112 最低配额 | `setup` `spawn_initial` `update` `set_replenishing` `request_reinforcement_wave` `stop_replenishing` `alive_count` `variant_weights_for_progression` `_roll_variant` `_spawn_one` |
| `ai/swarm/swarm_director.gd` | `SwarmDirector extends RefCounted` | [生存] Mother Goose UAV 战略层（1Hz）：把 30 架 UAV 分配到 SHOOTER / ATTACKER_N/E/S/W / DECOY / GUARD / RESERVE 角色 + lane 世界角度。AIController.simple_combat 读 swarm_role_override 切楔形攻击点 → 实现 4 轴同步抵达突击。是 Shaw 2v1 Bracket+Sandwich 的 swarm 化身 | `setup` `update(delta)` `_tick` `_pick_shooters` `_pick_attackers` `_pick_decoys` `_pick_guards`；静态 `role_of(uav)` `is_active_attacker(role)` |
| `ai/swarm/swarm_director_params.gd` | `SwarmDirectorParams extends Resource` | [生存] SwarmDirector 可调参数 Resource：策划在 Inspector 里调角色比例、楔形宽、滞回阈值；默认资源 `resources/ace_swarm_director.tres` | `@export var attacker_pct / shooter_count / decoy_pct / guard_pct / wedge_half_deg / converge_distance_* / hysteresis_score_pct ...` |
| `ai/joust_controller.gd` | `JoustController extends RefCounted` | [共享] 攻击跑行为原语（spec joust-attack-run）：RUN_IN 对准进入火力窗（两段速：带外全速/入带稳巡航）→ BREAK 脱离拉开（近图边朝中心 lerp）→ 折返循环；包络动态读装备（railgun>missile>gun）；电磁炮充能保持窗禁切 BREAK；消费方=AIController 双钩子（simple hunter 块 + _process_engage）；MQ-110/112 + Lancer 四型接线 | `update(ai, delta)→bool`（true=movement 已接管）`_resolve_outer_px` `_resolve_inner_px` `_closing_mps` `Phase{RUN_IN,BREAK}`；AIController `joust_*` @export ×7 |
| `rocket_params.gd` | `RocketParams extends Resource` | [共享] 无制导火箭弹参数（齐射数/最终散布/冷却 + 180m 直飞 / 320m 渐进展开距离） | `straight_flight_distance` `spread_transition_distance` |
| `ai_controller.gd` | `AIController extends Node` | [共享] AI 主控（状态机路由 + 状态所有者 + BVR/BOSS 覆盖判定 + 简单 AI 路径 `_process_simple` / `_process_drone_engage` / `_try_engage_simple` / `_try_engage_in_tether_range`；simple/drone/kamikaze 的基础前置点委托 PursuitGeometry；全功能 AI 强制启用 Aircraft 的 TacticalPlanner，规避/目标/编队委托 ai/ 子模块）。事件独占 directive 可关闭战斗并在父 Aircraft tick 前提交 DIRECTIVE 意图。**Phase 2 状态正交化（2026-07-05）**：`AIState` 三值 PATROL/ENGAGE/SQUAD_FOLLOW，EVADE = `_evading` modifier（MissileEvasion 独占进出，背景 _state 保持）；全部 _state 写入走过渡函数；`_ready` 把决策相位 `_tick_phase` 按实例 ID 展开到 `TICK_PHASE_SPAN`（simple_ai 原 %3 相位不变、不耗全局 RNG），拥挤降频后 divisor 2/6 的决策帧不再聚集 | `_ready` `_physics_process` `_process_patrol` `_process_engage` `_process_simple` `_process_drone_engage` `directive_suspends_combat` `prepare_parent_directive_control` **过渡函数** `enter_engage_state(reset_plan)` / `reset_tactical_plan()` / `enter_squad_follow_state(snap)` / `enter_patrol_state(pick_waypoint)` / `is_evading()` **目标仲裁** `get_target_source()` / `acquire_target()` / `release_target()` **约束层** `_apply_constraints(delta)`（分发前统一：combat_zone + 小队 leash 全模态，SEAM-010 根治）`_cmd_engage_active()`（本机点名 + 跟打长机点名目标，豁免普通归队/超距/超时/重评估）`is_range_disengage_exempt()`（BOSS/点名/两种小队交战豁免雷达距脱离）`_set_next_waypoint` `_generate_default_waypoints` `_get_missile_manager` `_find_member_ai` `is_boss_attacker` `_enforce_commanded_target`（玩家命令铁律，见 rts-command spec）`request_overkill_retarget`（仅非机炮优先 TS_SCORED 的超杀即时重评，1s 节流）+ joust_* @export / `_slow_air_joust`（≤100m/s 慢速空目标路由 joust，v4；测试 `scripts/tests/test_fire_discipline.gd` bench `fire_discipline`）（spec joust-attack-run）+ 核心状态字段 `_state / _evading / _current_target` |
| `ai/ai_altitude_policy.gd` | `AIAltitudePolicy extends RefCounted` | [共享] 无状态 AI 飞行高度剖面；状态过渡、规避恢复、legacy BFM 共用，避免外围依赖旧战术执行器 | `match_target(ai)` `use_combat_preference(ai)` `set_patrol(ai)` `altitude_to_tier(altitude)` |
| `ai/pursuit_geometry.gd` | `PursuitGeometry extends RefCounted` | [共享] 无状态追击点几何；机炮 intent、simple UAV、护驾自爆机与忠诚无人机共用，调用方只提供自身战术语义对应的闭合速度、预测窗与 lead 系数 | `forward_vector(heading)` `lead_point(...)` `lead_point_from_forward(...)` `closing_time_lead_point(...)` `projectile_lead_point(...)` |
| `ai/target_selection.gd` | `TargetSelection extends RefCounted` | [共享] 目标选择子系统（可命中性评分：对正/包络/锁定封顶/邻近四因子 + 承诺火力超杀让路〔机炮优先豁免〕+ 守后优先；spec target-engageability-selection）+ 战场引力三带/地板/可行性门/带感知粘性接线（spec battlefield-gravity，仅玩家小队 TS_SCORED 生效） | `try_engage(ai)`（交战地板 ENGAGE_MIN_SCORE）`reevaluate_target(ai)`（地板脱离 ×2 评估；机炮优先不因在途弹失粘性）`disengage(ai)` + `_score_candidate(ai, tgt, escort_leader, guard_ctx)`（引力乘子+三带加性+可行性门；机炮优先不吃 OVERKILL_MULT）`_sticky_for(ai)`（生存带 8.0 / 顺手 0.10）`_envelope_factor(ac, tgt, dist_m)` `_is_guard_rear_context(ai)` `_visibility_score_mult(tgt)` + 常量 `W_ALIGN/W_ENV/W_LOCK/W_PROX/OVERKILL_MULT/STICKY_BONUS/REAR_GUARD_PRIORITY/SWITCH_MARGIN_*` |
| `ai/objective_context.gd` | `ObjectiveContext extends RefCounted`（全静态） | [共享] **战场引力共享上下文**（spec battlefield-gravity）：队级"当前主战场"空间锚 + 三带判据。生存模式填充（BOSS 存活质心 / 最近 triggered 战区 / 兜底操控机实时位），沙盒恒 disabled → 全判据无操作。成员集只认实例表（禁 category 字符串匹配，防误伤 ace_support）；生存层只对空（engaging_me 仅飞机写）。`is_objective` / `is_survival_threat` 是生命周期边界，收 `Variant` 后先判实例有效，允许长期缓存的目标引用已经释放；static 跨场景 → 新局 reset+enable、退局 reset（同 UgcLoader 惯例） | 常量 `SURVIVAL_BONUS(100)/OBJECTIVE_BONUS(40)/R_CORE_PX(2000)/R_FAR_PX(6000)/GRAVITY_FLOOR(0.1)/SURVIVAL_RANGE_PX(3000)/ENGAGE_MIN_SCORE(0.15)/LEASH_FEAS_MARGIN(0.9)/SURVIVAL_STICKY(8)/BRACKET_SLACK_PX(1200)`；`reset` `set_boss_objective` `set_zone_objective` `set_no_objective` `effective_anchor` `gravity_mult(pos)` `is_objective(unit: Variant)` `is_survival_threat(cand: Variant)` `threat01` `band_bonus`；状态 `enabled/has_objective/member_ids/anchor/protectee` |
| `ai/missile_evasion.gd` | `MissileEvasion extends RefCounted` | [共享] 导弹规避与公共 EVADE 生命周期；机炮子状态由 GunEvasion 处理，真导弹可无缝接管。Phase 2：`_evading` modifier 唯一写入者；exit 支持手控/directive 接管时仅清理而不恢复任务；leash 上收 _apply_constraints；CLIMB 反制共用迫近门 | `process_evade(ai, delta)` `enter_evade(ai)` `exit_evade(ai, resume)` `should_enter_evade(ai)` `check_incoming_missile(ai)` `find_nearest_incoming_missile(ai)` `_is_evasion_threat(ac, m, already_evading)` `is_imminent_evasion_threat(ac, m)` `is_missile_from_rear(ai, missile)` |
| `ai/gun_evasion.gd` | `RefCounted` | [共享] 普通玩家僚机机炮自保组件；消费 Aircraft.report_gun_tailed 的来源 ID，固定方向 break、有界计时、安全退出；不扫描全场、不缓存 Object | `eligible` `source` `tick` `process` `_submit` `clear`；AIController `_gun_evasion` / `manual_control` setter / `set_event_directive` / `_physics_process_impl` |
| `tests/test_gun_evasion.gd` | `RefCounted` | [测试] 有效咬尾、第三方夹击、命令恢复、冷却、导弹/手控/directive 优先级与误触发门；bench gun_evasion | `run` `_setup` `_aircraft` `_reset_geometry` `_restart` `_check` |
| `tests/gun_evasion_lifecycle_case.gd` / `tests/gun_evasion_runner.gd` | `RefCounted` / `Node2D` | [测试] 真实威胁上报/AI 分发/飞行/机炮与跨帧来源、长机终态；独立 gun_evasion_flight 与 lifecycle_gauntlet 共用 | case `run` `_aircraft` `_check`；runner `_ready` `_run` |
| `ai/squad_coordination.gd` | `SquadCoordination extends RefCounted` | [共享] 编队协同子系统 + 护卫学说评分 + 守后威胁评分 + 生存层主动回防；`FOLLOW_LEADER` 共享长机目标时进入 `TACTIC_FORMATION_ASSAULT`，目标只交火控，僚机保留 `SQUAD_FOLLOW`/阵型导航；FREE、防御、规避与显式战术仍可 break 后走既有归队 | `process_squad_follow(ai, delta)` `try_defend_protectee(ai)` `_count_defenders(ai, protectee)` `is_escort_wingman(ai)` `escort_target_bonus(leader, candidate)` `scan_leader_rear(ai)` `rear_threat_score(leader, candidate)` `scan_squad_nearby_enemy(ai)` `end_cover_engagement(ai)` `broadcast_salvo(ai)` `process_salvo(ai, delta)` |
| `rts/squad_command_controller.gd` | `SquadCommandController extends Node` | [生存] RTS 指挥单一所有者（命令 + 自动交战逻辑，从 survivor_mode 抽出）；玩家命令(`commanded_target`)走铁律，自动交战(`_auto_engage_target`)可拴绳；轮盘广播命令 + 队级战术状态也在此（spec rts-command / command-wheel） | `setup(mode, params)` `command_attack(enemy)` `command_move(world_pos)` `cancel()` `tick(delta)` `_find_target(center, radius)`（用 `CombatUnit.all_units`）+ 轮盘广播 `command_regroup` `command_evacuate`（3km 圈外不生效）`command_guard` + `_tick_guard`（区域清剿 standing order：全队逐机自主领圈内目标/认领数让路/击杀后接续/出圈×1.15 放弃/清空回防）+ `_end_guard`（只回收任务借用的铁律目标）`command_attack_all(target, posture)`（FOCUS=广播集火+包围轴 `_assign_surround_axes` / SPREAD=`_begin_spread`+`_tick_spread` 池内各自接敌）`_squad_members` + 状态 `fire_allocation` `formation_tight` `_guard_point` `_guard_owned` `_spread_*` `wheel_params`；姿态/包围字段 `Aircraft.attack_posture` `surround_bearing_rad`（随 commanded_target 走）→ Situation 门控透传 → 空中 STANDOFF 走 `AIController._posture_standoff_air` 路由 joust / 面目标走 ground_strafe 分流 / 包围门点 `TacticalPlanner._apply_surround_axis`；集合/撤离全力加速 `Aircraft.command_sprint`（`_tick_sprint` 到达/出圈解除，注入见 aircraft_physics `COMMAND_SPRINT_MULT`）+ 撤离 20s 禁入区（`_in_evac_zone` 过滤 `_find_target`/拴绳 + 内部类 `EvacZoneMarker` 圈框倒计时）+ TIGHT 整队齐射 `_begin_tight_engage`/`_tick_tight_volley`（触发器=长机开火，开窗 1.5s 授予僚机 `Aircraft.volley_fire_active`+临时 combat_target 在编队槽位开火，SquadCoordination 防御清除豁免该标志；安静期 2s 再武装；ASSAULT 豁免）；验收 `--bench=fire_alloc` / `--bench=wheel_orders` / `--bench=tight_volley`；720 批：`_update_guard_zone_buff`（保卫阵地——防守命令激活时按账本给圈内成员打 `guard_zone_buff_active`，减伤/回转注入见 aircraft `_apply_damage` + aircraft_physics `_g_buff_mult`） |
| `rts/rts_command_params.gd` | `RtsCommandParams extends Resource` | [生存] RTS 自动交战可调参数（去硬编码）；默认资源 `resources/rts_command.tres` | `@export auto_engage_radius_px / auto_engage_leash_mult / auto_engage_interval_s` |
| `rts/command_wheel.gd` | `CommandWheel extends CanvasLayer` | [生存] 命令轮盘手势层（spec command-wheel）：长按左键 0.65s 呼出（位移不再提前激活），小队(按空地)/攻击(按敌机)双上下文，0.3x 子弹时间；IDLE 时 set_process(false) 零常驻开销；命令经 `command_selected` 信号交回 survivor_mode（阶段 1 仅 EventLogger stub） | `setup(mode, params)` `begin_press(screen, world, target)` `end_press()`（返回 Outcome CLICK/EXECUTED/CANCELLED + 按下快照）`abort_if_pending()` `_pick_slot` `_draw_wheel` `slot_state_text`；内部类 `WheelCanvas` |
| `rts/command_wheel_params.gd` | `CommandWheelParams extends Resource` | [生存] 轮盘可调参数（去硬编码）；默认资源 `resources/command_wheel.tres` | `@export` 手势（hold 0.65s/死区 30px/一环 110px/流速 0.3）+ 紧急集合(600px)/撤离(1500px+20s)/防守(1500/500px)/火力分配(2000px/45°) |
| `survivor/radio_chatter.gd` | `RadioChatter extends CanvasLayer` | [生存] 无线电通讯显示层（spec radio-chatter），layer=19，屏幕上方"呼号 ▸ 台词"。**一次一条、绝不打断**（优先级只管排队 + 满队淘汰）；类别冷却防刷屏；队列上限 3；过期丢弃但 BOSS 剧本序列豁免。入队即快照呼号+Color，不持有 Aircraft 引用。唯一 `_process` 为 O(1) 计时器 | `say_text(trigger, speaker, color, text)` `say(trigger, speaker, color, fmt_args)` `say_unit(trigger, unit, fmt_args)` `say_boss_sequence(boss_id, phase, prefix)` `notify_enemy_loss()` `color_for_team(team, elite)`（static）`line_duration(text)`（static）；**零可调数值**——权重/冷却/概率/时长全部查 ChatterLines（JSON）。三层节流：全局冷却→冷却桶→概率骰，scripted 类全免 |
| `survivor/chatter_lines.gd` | `ChatterLines extends RefCounted` | [生存] 无线电台词表的**加载器**（本身零数值）。★ 全部触发、权重、冷却和概率住 `resources/chatter/radio_chatter.json`，文本三语住 `i18n/radio.csv` 的 `RADIO_*`。JSON 缺失/损坏 → 报 error 后系统降级静默，不崩游戏；静态缓存全进程解析一次 | `pick(trigger)`（选词防相邻重复）；static 查询 `kind_of` / `is_scripted` / `weight_of` / `cooldown_group_of` / `cooldown_of` / `chance_of` / `lines_of`（支持 lines_ref 复用）/ `global_ambient_cooldown` / `line_gap` / `queue_max` / `queue_stale_sec` / `duration_*` / `boss_sequence` / `type_has_voice` / `attrition_trigger` / `all_line_keys`（校验用）/ `all_trigger_ids` / `reload`；enum `Kind{SCRIPTED, AMBIENT}` |
| `ai/tactical/situation.gd` | `Situation extends RefCounted` | [P4 共享] 纯数据态势快照，TacticalPlanner 输入；玩家高位自然带额外携带玩家小队标志与稳定机号相位 | `from_aircraft(ac)` 工厂；`new_for_test(d)` 测试用；`_recompute()` 几何派生 + **属性感知狗斗画像**（双方 effective G/角点 + roll/decel → BALANCED/ENERGY/TIGHT，spec engagement-discipline §C）；字段：几何 / 锁定 / 武器 / 小队 / `ai_aggression` / `strafe_pass_phase` / `attack_posture` / `is_player_squad` / `altitude_variation_phase` |
| `ai/tactical/tactical_plan.gd` | `TacticalPlan extends RefCounted` | [P4 共享] 决策输出值类型（~80 行） | 13 种 `Intent` 枚举 + `WeaponMode` + `SurfacePhase`（SETUP/RUN/EGRESS）+ 字段（pursuit_pos / target_speed_kmh / afterburner / weapon_mode / allow_gun_fire / allow_missile_fire / target_altitude / trigger_extend_seconds / `strafe_pass_phase` / rationale） |
| `ai/tactical/bfm_intent.gd` | `BfmIntent extends RefCounted` | [P4 共享] 13 个 intent 纯函数；导弹发射前追踪 AircraftWeapons 同源前置点，出弹后才 crank；玩家 PREFER_CLIMB 走中心 8400m、7600–9000m 边界的自然高度带，稳定机号错相慢漂移且大坡度自然掉高，敌机高度不变 | `cruise(s)` `waypoint_move(s, wp)` `passive_auto_fire(s)` `evade_missile(s)` `tail_chase(s)` `close_tail(s)` `lead_turn(s)` `lead_pursuit(s)` `lag_pursuit(s)` `merge_pass(s)` `wide_turn(s)` `extend_recover(s)` `ground_strafe(s)`（对面攻击 pass 状态机 SETUP/RUN/EGRESS + 姿态 STANDOFF/ASSAULT）+ 辅助 `_apply_combat_weapon` `_missile_engage_pos` `_missile_engage_speed` `_apply_squad_lateral_offset`（TIGHT 僚机横移 100m，其余 250m）`_gun_lead_point` `_surface_altitude` `_apply_player_altitude_preference` `player_high_hold_altitude_m` |
| `ai/tactical/tactical_planner.gd` | `TacticalPlanner extends RefCounted` | [P4 共享] 顶层决策入口（~375 行） | `plan(s, waypoint=INF)` 顶层 + `_apply_dogfight_energy_management`（ENERGY 守物理角点）+ 优先级决策树（evade/extend/no-target/surface/overshoot/boom-zoom/**5b.2 co-turn breaker**/slow-target/wide-turn/head-on/rear/side）；TIGHT 画像跳过非过冲脱离、半径占优 LAG→LEAD、僚机在 2×炮距解除外围角色；`_apply_weapon_lock` 后置 + hysteresis |
| `equipment/equipment_params.gd` | `EquipmentParams extends Resource` | [共享] 装备基类（武器+反制+规避统一抽象）；详见 [docs/changelogs/2026-04-28-equipment-scaffolding.md](../changelogs/2026-04-28-equipment-scaffolding.md) | `equipment_kind` 字段；虚方法 `can_fire(ac, target)` `desired_engagement(situation)` `fire(ac, target)` `update(ac, delta)` `ammo_ratio(ac)` `cooldown_ratio(ac)` |
| `equipment/engagement_preference.gd` | `EngagementPreference extends RefCounted` | [共享] 装备投票值类型 | 字段 `preferred_range_m` `preferred_intent` `needs_lock` `needs_los` `priority` `preferred_speed_kmh` `prefers_afterburner` `rationale`；工厂 `make(kind, range, intent, prio)` |
| `equipment/evasion_module.gd` | `EvasionModule extends EquipmentParams` | [共享] 规避模块基类（flare/cobra/herbst 子类） | `should_trigger(ac, missile)` `execute_evasion(ac, missile)` |
| `equipment/gun_equipment.gd` | `GunEquipment extends EquipmentParams` | [共享] 机炮装备包装器（commit 2/13）；持 `gun: GunParams` 引用 + 给 planner 投票 CLOSE_TAIL preference | `_init` 设 `equipment_kind="gun"`；`desired_engagement(s)` 返回 `EngagementPreference(intent=CLOSE_TAIL, range=max_range×0.5, priority=0.6)`；`ammo_ratio(ac)` `cooldown_ratio(ac)` |
| `equipment/rocket_equipment.gd` | `RocketEquipment extends EquipmentParams` | [共享] 火箭弹装备包装器（commit 3/13）；持 `rocket: RocketParams` 引用 | `_init` 设 `equipment_kind="rocket"`；`desired_engagement(s)` 返回 `EngagementPreference(intent=TAIL_CHASE, range=(min+max_fire)/2, priority=0.4)`；`ammo_ratio` `cooldown_ratio` |
| `equipment/missile_equipment.gd` | `MissileEquipment extends EquipmentParams` | [共享] 导弹装备包装器(commit 4/13）；持 `missile: MissileParams` + `is_secondary` 双槽标识 | `_init` 设 `equipment_kind="missile"`；`is_secondary=false` 发布到 `params.missile`，`true` 发布到 `params.secondary_missile`；`desired_engagement(s)` 仅主导弹返回 `EngagementPreference(intent=LEAD_PURSUIT, range=max_range_rear×0.6, priority=0.7)`；`ammo_ratio` `cooldown_ratio` |
| `equipment/flare_equipment.gd` | `FlareEquipment extends EvasionModule` | [共享] 热诱弹装备包装器（commit 5/13）；第一个 EvasionModule 子类 | `_init` 设 `equipment_kind="flare"`；持 `flare: FlareParams`；`should_trigger`/`execute_evasion` 暂留 base no-op，等 commit 7 接入投票后实装；`ammo_ratio` `cooldown_ratio` |
| `equipment/cobra_evasion.gd` | `CobraEvasion extends EvasionModule` | [共享] 眼镜蛇标记装备（commit 6/13）；publish 时若 equipment 含 CobraEvasion 且无 CobraManeuver 子节点，自动 add_child 挂载 | `_init` 设 `equipment_kind="cobra"`；should_trigger / execute_evasion 等 commit 7 实装 |
| `equipment/herbst_evasion.gd` | `HerbstEvasion extends EvasionModule` | [共享] 赫尔贝特轮标记装备（commit 6/13）；publish 时自动挂 HerbstManeuver 子节点 | `_init` 设 `equipment_kind="herbst"`；should_trigger / execute_evasion 等 commit 7 实装 |
| `equipment/railgun_equipment.gd` | `RailgunEquipment extends EquipmentParams` | [共享] 电磁炮（commit 8/13）；telegraph 充能 + hitscan + 闪电视觉 + 穿透 + 玩家版/敌人版双锁定时机；飞机按光束最近投影点进入受击分区；命中导弹只播一次 0.45 小方框后销毁；有效射程读 host `params.radar_range`；充能前统计有效在飞导弹 + 队友充能炮，普通目标及航母/舰船 MountTarget 均避免僚机超杀 | `team_charging_damage` `_try_start_charging` `_effective_max_range_m` `_commit_fire_solution` `_nose_lead_point` `_apply_hitscan_damage` |
| `equipment/laser_equipment.gd` | `LaserEquipment extends EquipmentParams` | [共享] 360° 激光照射器；仅对空，飞机压向动态失速 90%，导弹每秒损失 35% 最大速度且 G×0.5、降至 20% 摧毁；`intercepts_missiles_directly` 令敌方拦截机不依赖玩家技能即可累计扣 `intercept_hp` 并令弹体失效，导弹摧毁只播一次 0.45 小方框；伤害/黑客/过热/云削弱共用同一状态机 | `update` `_pick_targets` `_apply_laser_effect` `_select_hack_focus` `_advance_hack` `_is_hack_eligible` |
| `equipment/esm_pod_equipment.gd` | `EsmPodEquipment extends EquipmentParams` | [共享] 战区 ESM 吊舱；2Hz 扫描 3000m 内友军并刷新锁定 ×1.5、机炮/导弹/热诱弹 reload 时间 ×0.7 的短时 meta | `update` |
| `pilot_personality.gd` | `PilotPersonality extends RefCounted` | [共享] 飞行员心理子系统：压力/态势感知/判断误差（~223 行） | `update_stress(ai, delta)` `update_situational_awareness(ai, delta)` `update_drift(ai, delta)` `effective_skill` `effective_sa` `apply_position_error` `apply_speed_error` `apply_altitude_error` |
| `combat_unit.gd` | `CombatUnit extends Node2D` | [共享] 战斗单位基类（通用接口）；`sensor_hidden/sensor_shroud_id` 是 Snowblind 传感器遮断状态，不改变物理碰撞或阵营；DEADAIR 暴露比率由 5Hz 控制器写入并按八段请求重绘；正式气氛层提供发射快照倍率、固定阵营标记与 TGT 非致死伤害入口；玩家锁框状态只汇总含 PLAYER 的配对 | `set_deadair_exposure_ratio` `ambient_damage_multiplier` `tracks_player_lock_state` `accumulate_player_lock_state` `take_damage` `take_atmosphere_damage` `is_in_radar_cone` `get_altitude_tier` `is_sensor_engagement_obscured(other)` |
| `combat_unit.gd`（命中资格） | `can_accept_new_hit(kind)` | [共享] 新命中建立前的统一查询；默认允许，Aircraft 主动特殊机动 ACTIVE 时按来源拒绝 | `combat_unit.gd:293 can_accept_new_hit`；覆写 `aircraft.gd:2498 can_accept_new_hit` |
| `weapon_hit_resolver.gd` | `WeaponHitResolver extends RefCounted` | [共享] 无状态武器命中边界；统一命中资格、跨帧攻击者清洗、归因及 Aircraft/Ground/Naval/通用目标伤害分派；保留机炮闪避、战斗部软目标一击必杀、气氛 TGT 非致死与舰船倍率参数，不负责碰撞/衰减/VFX | `weapon_hit_resolver.gd:11 can_accept_unit_hit` `weapon_hit_resolver.gd:17 resolve_unit_hit` |
| `missile.gd` | `Missile extends Node2D` | [共享] 导弹飞行物理（PN 制导/SARH）；维护 `active_missiles` 与实际累计路径；敌机 flare break 保存投焰瞬间位置/航向/速度/高度，不持有新增 Object 引用，窗口内继续制导与碰撞，真实转向/横移/增速/高度变化达门且等级 roll 通过后才 jam；连锁弹头保存逐弹命中集合并在命中后直飞；CIWS/激光/电磁炮共用拦截伤害与回收入口；世界与 HUD 复用来袭判定；低缩放提交与 CLIMB 反制保持；物理插值白名单：`_ready` 开启并延迟重置，`_physics_process` 开头记 `interp_prev_xform` / `interp_prev_tick`，显示态按帧缓存于 `interp_cache_*`，`_notification` 处理重置并清缓存 | `begin_enemy_flare_break` `update_enemy_flare_break` `enemy_flare_break_action` `set_deadair_exposure_ratio` `jam_by_deadair` `disrupt_by_climb_break` `_physics_process` `incoming_warning_rule` `is_incoming_warning_for` `remember_penetration_hit` `continue_after_penetration` `already_penetrated` `take_intercept_damage` `destroy_from_intercept` `_start_fade_out` `_guidance_degradation` |
| `rendering/canvas_triangle_packet.gd` | `CanvasTrianglePacket extends RefCounted`（全静态） | [共享/表现] 无领域语义的 Canvas 三角批次原语；统一 points/indices/colors、退化面积门、顺序索引与 Godot 4.7 triangle-array 提交，供地图、尾迹和爆点复用 | `create` `layer` `append_triangle` `append_triangle_colors` `append_rect` `append_indexed` `sequential_indices` `submit_arrays` `submit` |
| `rendering/bullet_presenter.gd` | `BulletPresenter extends RefCounted`（全静态） | [共享/表现] BulletManager 的只读表现端；统一曳光/火箭/炸弹/Flak/命中火星/漂浮雷画法，保留 multiline 合批与确定性视觉噪声，不拥有弹体生命周期 | `draw` `_draw_special_projectiles` `_draw_area_flashes` `_draw_bullet_streams` `_draw_hit_sparks` `_draw_torpedoes` |
| `rendering/explosion_presenter.gd` | `ExplosionPresenter extends RefCounted`（全静态） | [共享/表现] MissileManager 的只读表现端；AOE 圈与统一方框爆点/结构波几何，全场面/棱合批，近轴退化侧面复用共享面积门 | `draw` `hit_flash_draw_packet` `hit_flash_cube_packet` |
| `trail_ribbon.gd` | `TrailRibbon extends Node2D` | [共享/表现] 飞机与导弹的世界坐标丝带；20Hz 采样、80 点上限、屏外剔除与切回淡入不变；自身不进物理插值白名单，每渲染帧把本地变换设为父机【显示态】全局变换之逆（插值关闭时即 identity 全局变换），旧点留在原世界位置、不随插值相位抖动；20Hz 采样点取父机显示态，丝带头不冒出机头；导弹批次尾迹自身 Canvas 不出图、跳过逐帧抵消；retained Canvas 命令只在新采样、淡入/剔除或样式变化时重建；导弹按八个采样相位交给 MissileTrailBatch 合批；传感器完全隐形时清空并停 process，显形从空轨迹恢复；提交复用 CanvasTrianglePacket | `add_point` `clear_trail` `set_emission_enabled` `_process` `_draw` `assign_missile_batch` `missile_batch_phase_slot` `append_to_missile_batch` `geometry_point_step_for` `_desired_geometry_point_step` `_rebuild_cached_geometry` |
| `missile_trail_batch.gd` | `extends Node2D`（内部批次节点） | [共享/表现] 同一采样相位的导弹尾迹缓存合为一次 triangle-array；由 MissileManager 建八个 internal CanvasItem，不进入既有导弹 child-count/get-children 语义；F3 明细开启时仅在外层 `_draw` 计时 | `setup` `_draw` `_draw_impl` |
| `missile_manager.gd` | `MissileManager extends Node2D` | [共享] 导弹生成、命中/伤害/爆炸、连锁弹头生命周期、近炸引信与逐弹覆盖半径/时长的定距空爆 AOE；统一爆炸宿主保存纯值结构波记录，绘制委托 ExplosionPresenter；飞机离架航向复用 AircraftWeapons 共享前置点；定距弹在累计路径到点前不建立直接命中；零伤害气氛导弹跳过全体单位扫描与 AOE；真实导弹命中用每 tick 一次 UnitGrid broad-phase，舰船大半径恒扫；内部八相 Canvas 子树集中提交导弹尾迹 | `spawn_missile` `_compute_lead_launch_heading` `_update_visual_only_ambient_missile` `_rebuild_target_grid` `_ordered_target_candidates` `register_missile_trail` `_physics_process` `distance_airburst_ready` `_detonate_distance_airburst` `_spawn_aoe` `_update_aoe_zones` `_apply_aoe_damage` `spawn_flash` `spawn_airframe_wave` `_spawn_hit_flash` `_update_hit_flashes` `_draw` |
| `bullet_manager.gd` | `BulletManager extends Node2D` | [共享] 子弹/火箭物理+命中与表现数据所有权；机炮、火箭和空爆弹传入真实受击分区，CIWS 击毁导弹只播一次方框；纯视觉普通弹使用 PackedArray SoA；大型舰船候选按阵营预分；轰炸弹、空爆弹与 AOE 生命周期仍在本管理器，绘制统一委托 BulletPresenter | `spawn_bullet` `visual_bullet_count` `total_bullet_count` `_update_visual_bullets` `_rebuild_large_target_buckets` `_large_targets_for_source_team` `spawn_rocket` `rocket_spread_progress` `rocket_straight_phase_complete` `apply_rocket_spread_step` `_apply_projectile_damage` `spawn_bomber_bomb` `spawn_airburst_shell` `_update_special_projectiles` `_explode_airburst_shell` `_physics_process` `_draw` |
| `bullet_manager.gd` / `missile_manager.gd`（主动机动命中门） | `WeaponHitResolver.can_accept_unit_hit` | [共享] 在日志、特效、弹体销毁/引爆和伤害之前查询共享资格门；子弹穿过、导弹保留目标继续飞、AOE 不登记 | `weapon_hit_resolver.gd:11 can_accept_unit_hit`；调用点 `bullet_manager.gd:952 can_accept_unit_hit` `missile_manager.gd:540 can_accept_unit_hit` `missile_manager.gd:751 can_accept_unit_hit` |
| `util/unit_grid.gd` | `UnitGrid extends RefCounted` | [共享] 命中广相：均匀网格空间哈希，把"每弹扫全场"降到"每弹扫 3×3 邻格"；大单位(NavalUnit)进 `large_units` 恒扫、小单位入格（changelog 2026-07-24 航母群掉帧） | `rebuild` `query_into` |
| `util/display_pacing.gd` | 静态服务（无 class_name，消费方 preload 为 `DisplayPacing`） | [共享/表现] 显示节拍：Presentation `_ready` 安装——项目开 `physics/common/physics_interpolation` 但根节点默认 OFF（白名单，仅 Aircraft/Missile 开启），并监听入树把每个 Viewport 强制 OFF（4.7 视口默认是独立插值根，否则子视口 Camera2D 走插值路径、三维合成层被 FTI 插值），`AGL_PHYSICS_INTERP=0/1` 覆盖，插值开时 jitter fix 归零；显示态 = 本 tick 起点 `interp_prev_xform` 按 `Engine.get_physics_interpolation_fraction()` 插值到当前变换（prev 过期/暂停/插值关时回退物理态；同一渲染帧内按“渲染帧号 + 物理帧号”缓存在单位上，多消费方只插值一次），供镜头、状态栏、尾迹、三维机体合成层、bench 巡检镜头与 FrameProbe 消费；可选帧上限 `user://display.cfg [display] max_fps` / `AGL_MAX_FPS`（0=不限，非 0 下限 30） | `install` `_demote_viewport` `set_interpolation_enabled` `interpolation_enabled` `display_time_lag` `is_interpolating` `display_local_transform` `display_global_transform` `display_origin` `display_screen_origin` `display_rotation_offset` `rotation_offset_from` `max_fps` `set_max_fps` `normalized_max_fps` |
| `terrain_renderer.gd` | `TerrainRenderer extends Node2D` | [共享] 地形/网格/云层绘制（子节点，自动 `_draw`） | `setup(camera)` `_draw_terrain` `_draw_grid` `_get_terrain_type` |
| `weather_system.gd` | `WeatherSystem extends Node2D` | [共享] 全局天气：高空普通云（双低频噪声可选均匀化）+ 地图可选的局中黄色低空沙尘暴；正式游戏随机天气，地图完整 viewport Visual bench 可通过 `setup` 的可选种子固定云形，防止把两次天气随机差异误判成底图偏色；官方沙漠沙带 180km/h、10km 宽，完整扫图时长由地图尺度计算；F6 可用 Debug-only 0.5 progress 定位；沙尘暴以气象观测图式流线/观测点/断续锋面符号批绘，不复用云贴图；前后缘使用低频曲边与 720px 六层 Alpha 羽化，渲染与按高度战斗遮蔽同源，加入 group `"weather"` | `setup(camera, deterministic_seed)` `apply_ugc_config` `set_game_time` `set_debug_midgame` `sandstorm_progress` `sandstorm_center_world` `sample_density` `sample_sandstorm_density` `sample_obscurant_density` `is_obscured` `_draw` `_sandstorm_edge_wave` `_sandstorm_band_polygon` `_draw_sandstorm_fill` `_draw_sandstorm_streamlines` `_draw_sandstorm_observations` `_draw_sandstorm_front` |
| `camera_controller.gd` | `CameraController extends Node` | [共享] 缩放/平移/hover/坐标转换；hover 命中半径固定为 30 屏幕像素，缩远时换算成世界半径而不缩水；跟随与演出跟随以 DisplayPacing 物理插值显示态为 lerp 目标（不再追每 tick 跳一次的 global_position） | `setup(camera)` `_update_follow(delta)` `cine_follow_tick(delta)` `is_world_pos_visible` `update_zoom(delta)` `handle_zoom_input(factor)` `screen_to_world(screen_pos)` `handle_drag(relative)` `hover_radius_world_for_zoom(zoom)` `update_hover(screen_pos, units)` |
| `bench/bench_camera_patrol.gd` | `BenchCameraPatrol extends RefCounted` | [测试] C1/C2 与海洋 FINAL WAR 诊断场的确定性观察者巡检轨迹；18 秒覆盖全战线，平移、总览↔近景缩放与双向缓转；调用方可按战区中心与横纵尺度平移/放大，运行时 `sample_into` 复用输出字典，不在性能采样中制造逐帧分配 | `sample` `sample_into` `segment_count` `PERIOD_SECONDS` |
| `main.gd` | `Main extends Node2D` | [沙盒] 沙盒主控：输入/雷达锁定/编队/LOD（地形/相机委托共享模块，~427 行） | `_update_radar_locks` `_spawn_friendly_squad` `_update_lod` |
| `squad.gd` | `Squad extends Resource` | [共享] 6 种阵型偏移计算 + 编队反应延迟常量 + 整队 engage_mode + leader_changed；`members/leader` 为结构真源，换帅/cleanup 原子恢复幸存成员 `AI.squad` 并重排 index；可选 `leader_successors` 为 ADBS 等任务编队提供确定性继任链，空链仍按最高击坠数继任 | `set_leader` `cleanup` `_sync_member_bindings` `get_formation_offset` `get_wingman_target` `cycle_formation` |
| `squad.gd`（主动机动冷却） | `active_maneuver_cooldown_s` | [共享] 玩家小队唯一 R 主动机动冷却账本；切控只换 leader，不复制或重置 | `squad.gd:40 active_maneuver_cooldown_s` |
| `squad_factory.gd` | `SquadFactory extends RefCounted` | [共享] 编队生成统一入口（2026-05-04 重构，替代 9 处散乱的 Squad.new + add_member + ai 串接） | `create(formation, engage_mode, spacing)` `register_leader(sq, leader)` `register_wingman(sq, ac, set_state=true)` `form_up(leader, wingmen, ...)` |
| `ai/escort_behavior.gd` | `EscortBehavior extends RefCounted` | [共享] 护驾行为子系统（Sentinel UAV 绕长机+拦弹+自爆）；2026-05-04 起谓词收口，执行体仍在 ai_controller._process_simple | `is_active(ai)` `cleanup_after_leader_lost(ai)` |
| `ground_unit.gd` | `GroundUnit extends CombatUnit` | [共享] 地面单位基类（机炮+雷达+移动）；正式气氛层可写通用 preferred target，合法且已锁定时优先玩家；数据状态栏只提供兵种内容行与实际图标半径，统一交给 AircraftRenderer 的屏幕空间矢量面板，0.35/0.40 分档且 Alt 临时完整；物理/绘制外层在 F3 明细开启时分桶 | `retire_in_place` `_physics_process` `_physics_process_impl` `_draw` `_draw_impl` `_should_draw_compact_data_label` `_draw_data_label` `_status_label_lines` `_status_label_distance_m` `_status_label_icon_radius_world` `_update_movement` `_update_target_selection` `_update_combat` `_update_gun` |
| `sam_unit.gd` | `SAMUnit extends GroundUnit` | [共享] SAM：360° 雷达 + HQ-7 导弹；选敌与发射双门只接受 Aircraft，不参与地面炮战 | `_update_target_selection:28` `_update_sam_missile:51` `is_in_radar_cone`（覆写圆形） |
| `aa_gun_unit.gd` | `AAGunUnit extends GroundUnit` | [共享] AAA：独立炮塔 + ZU-23；扫描/保持/开火只接受 Aircraft | `_update_turret:74` `_update_aa_target_selection:31` |
| `airburst_aa_unit.gd` | `AirburstAAUnit extends AAGunUnit` | [共享] 远距定时空爆高炮；冻结误差火控解、三连发、只伤飞机；组/单发随机偏角封顶 7°/1.5°；静态采样器由陆基与舰载 Flak 共用 | `_update_aa_target_selection:40` `_update_airburst_weapon:76` `sample_burst_solution:99` `sample_shell_solution:119` `_begin_burst:133` `_fire_airburst_shell:143` |
| `strategic_target.gd` | `StrategicTarget extends GroundUnit` | [共享] 地堡/仓库/导弹井；永久不可锁定，只接受敌对 `bomber_bomb`；护送目标可在预刷阶段启用常驻 TGT 括号与双行轰炸权限提示 | `set_bomber_escort_objective` `take_damage` `take_bomber_damage` `is_lock_immune` `_draw_bomber_escort_hint` `_draw` |
| `radar_station.gd` | `RadarStation extends GroundUnit` | [共享] 雷达站：20km 雷达 + 数据链共享 | `_update_datalink:35` `_update_dish:29` |
| `survivor/survivor_mode.gd` | 生存模式主控 | [生存] 每 3 级基础普通三轴三卡；T0 起手机按 profile 在开局经 `_grant_starting_benefit` 结算一项机场等价技能/武器并即时入库，后来进化到同型机不触发；机体战术适配权益可 15% 追加当前机体身份轴普通第四卡；专属技能不进抽选，停靠规划站以“保留当前机并装备 / 进化”二选一，成功选择立即结束本次停靠；Boss Debug 消费 T4 node/level，把 duplicate 档案最低补为 1 长机 + 3 僚机的正式同型 Squad，从正式三星战区池抽 2~3 件特殊武器并先走 `_claim_weapon_reward` 挂到 ACE/入库，再按真实硬件条件 roll 技能，对整队配置技能/三轴/里程碑并构造 Tab 只读构筑面板；战区四类奖励即时发放，`bomber_escort` 例外绕过普通奖励并按星级只发固定特殊 XP，截击/成功无线电只报告军事态势，XP 数值留在 HUD，且成功不显示停靠结算误导；忠诚僚机“额外”经统一技能获得入口即时部署两机且换型幂等；僚机最多 2 架且不加等级、ESM 挂载；图2/图3内置 MapDocument 读取出生点/调色板、`tile_map_key` 并加载右侧城区炼油厂/西北孤岛火箭基地与机场，预览建筑透视系数 0.015；`map_preview_only` 关闭刷怪、战区、任务、BOSS、教程与生涯入档但保留自由飞行/Tab；候选地图点击战区时在 TacticalMap 真暂停内预热“近侧抵达点→圆心”走廊，任意 Tab 航点预热局部 detail，完成/回退后才下达同一目标；官方三图发布/Debug/bench 统一启用主图与 Tab lossless WebP 正式底图，`Shift+F8` A/B 已删除，外部 UGC 可 vector-only 或自带 PNG；`Shift+F10` 保留冻结纯矢量研究；雷达按 HOSTILE/非 HOSTILE 预分桶后再跑锁定，0.2s 窗口内本相位 shooter 配对分 4 片错峰到不同物理步（片时钟保锁定速率），窗口末单独做 O(N) 收束与玩家可见锁定重建；`_set_player_aircraft` 原子转移所有操控机引用与 `use_tactical_preference` 角色权限；玩家仪表键位 E/G/F/Q/T；底栏进化提示只认“等级与三轴门槛全过 + 当前有可用停靠点”；Shift+F12 输出亲控机修改器追踪 | `_ready` `BOSS_DEBUG_MIN_SQUAD_SIZE` `_spawn_starting_wingmen` `_grant_starting_benefit` `_setup_boss_debug_scenario` `_claim_weapon_reward` `_unhandled_input` `_toggle_map_vector_preview` `_set_player_aircraft` `_on_player_leveled_up` `_roll_axis_cards` `_open_evolution_offer` `_on_settlement_signature` `_on_settlement_evolution` `_on_zone_selected` `_on_zone_mission_completed` `_grant_bomber_escort_xp` `_say_bomber_escort_intercept` `_say_bomber_escort_completed` `_prewarm_zone_detail` `_on_nav_point_selected` `_prewarm_nav_detail` `_rebuild_radar_target_buckets` `_update_radar_locks` `_radar_slices_due` `_run_radar_slice` `_finish_radar_window` `_enforce_player_missile_cap` `_dispatch_regular_oneshot` `has_ready_aircraft_evolution` `archive_enabled` |
| `survivor/survivor_mode.gd`（正式三维表现） | 同上 | [生存/正式表现] 内置沙漠默认创建原生同视口地图+机体后端，其他地图使用透明飞机层；两者互斥。Shift+F11 / `AGL_AIRCRAFT_VOLUME=off` 仅切换机体；沙漠地图回退单独用 `AGL_DESERT_VOLUME=off`。旧 volume_* 实验与派生场景显式抑制重复后端 | `_ready` `_unhandled_input` `_process`；`rendering/aircraft_volume_overlay.gd` / `rendering/desert_volume_presentation.gd` |
| `survivor/survivor_mode.gd`（急刹拖拽输入） | `_unhandled_input` `_begin_hard_brake` `_update_hard_brake_steer` `_set_hard_brake` `_notification` | [生存/操控] 战场右键按下锚定屏幕坐标并取消既有 combat/commanded target，正式场景捕获/隐藏鼠标，MouseMotion 累计相对水平位移并映射到全体 selected 的归一化急刹转向输入；捕获期间冻结 hover；松开、失焦、Tab/Esc、切控、机场进化/规划站接管与场景退出恢复原鼠标模式/位置并原子清理急刹及转向；活跃期间向 HUD 推送当前操控机速度、剩余/最大机炮弹药、免费弹药状态与有效射程 | spec `systems/brake-steering`；focused bench `hard_brake` |
| `survivor/brake_steering_overlay.gd` | `BrakeSteeringOverlay extends Control` | [生存 UI] 急刹虚拟摇杆单实例：锚定右键按下点，显示减速、真实归一化左右舵量、即时速度、明确标名的剩余/最大机炮弹药（免费弹药为 `∞`）、有效射程与失速/恢复锁定；边缘夹紧、鼠标穿透、无 process/扫描，仅状态或取整数值变化时重绘 | `begin` `update_steer` `set_stall_locked` `set_flight_data` `end` `display_center_for` `knob_offset_for` `_draw`；bench `brake_steering_ui` / `brake_steering_overlay_visual` |
| `survivor/survivor_mode.gd`（栅格底图压力场） | `_setup_bench_scenario` `_process` | [测试] 正式瓦片固定 Operational `0.18`、主要战斗 `0.26`、近景 `0.80` 做 52 机压力；transition 场每 `0.8s` 循环 `0.06/0.18/0.26` 三档 | `map_raster_operational_stress` `map_raster_stress` `map_raster_detail_stress` `map_raster_transition_stress` |
| `survivor/survivor_mode.gd`（性能核心混合战场） | `_bench_force_battlefield_atmosphere_stress` `_bench_set_camera_zoom` `_bench_enable_camera_patrol` `_bench_update_camera_patrol` `_bench_camera_patrol_summary` `_bench_auto_pick_upgrade` `_process` | [测试] C1=36 名/8 km 固定翼、旋翼、火炮、舰船、轰炸机、尾迹/标签/弹道 draw 门；C2=48 名/24 km 多战线/LOD 门。两者 3 秒预热后用 18 秒固定轨迹平移、缩放、旋转并强制覆盖 8/8 巡检段，结果写实际 zoom/x/y/rotation；海洋 FINAL WAR 是显式诊断例外，其它 BOSS/武器专项不接入。`performance_hud_visual` 仍复用 C1 人口并锁定 F3 面板截图。统一 seed + 确定性 build，输出 avg/p1/worst/<60；draw 结论必须加 `Visual` | `bench/run.cmd battlefield_atmosphere_stress_36 30 180 Shadow Visual` / `battlefield_atmosphere_stress_48_24km` / `performance_hud_visual 6 180 Shadow Visual` |
| `survivor/survivor_mode.gd`（The Crucible 全员诊断） | `_bench_force_the_crucible_full_roster_stress` `_bench_on_crucible_member_tree_exiting` `_bench_update_crucible_full_roster_diagnostics` `_bench_crucible_full_roster_summary` | [测试] 明确绕过正式三队接力上限，把 18 队 73 架同时激活；stable 锁血保持峰值，attrition 保留真实伤害/死亡。固定无敌观察者，逐秒审计存活、合法退场、失效目标、弹丸峰值、世界边界与连续返场时间；Headless 只证明 CPU/状态，不证明真实 draw/FPS | `bench/run.cmd the_crucible_full_roster_stress 60 240 Shadow Headless` / `the_crucible_full_roster_attrition 60 240 Shadow Headless` |
| `survivor/survivor_hud.gd` | `SurvivorHUD extends CanvasLayer` | [生存 UI] HUD 分层刷新；静态布局只在 viewport 变化时重排；雷达按拥挤度 30/20 Hz 重绘并合批扫线尾迹/TGT 括号，光学/传感器隐形敌机保留低亮度匿名位置环但不恢复火控；接线含即时速度、剩余/最大弹药、免费弹药状态与机炮射程的急刹虚拟摇杆；F3 打开 4 Hz 详细性能面板并只在可见期间启用细分计时；复合 BOSS 支持紧凑树文本，The Crucible 分流到非 BOSS 多 Ace 中队条且击杀事件同拍刷新；F7 只缩放右侧玩家 HUD | `_process` `_layout_ui` `_update_hud_data_layer` `_on_kill_recorded` `begin_brake_steering` `update_brake_steering` `set_brake_steering_stall_locked` `set_brake_steering_flight_data` `end_brake_steering` `set_performance_panel_visible` `_update_debug_panel` `_update_boss_panel` `_format_custom_boss_entries` `RadarDisplay.redraw_interval_for_unit_count` `RadarDisplay.stealth_hint_contact_for` `_ensure_ui_root` `set_player_hud_scale` `_update_display` `_update_player_instrument` `_update_afterburner_ui` `show_level_up` |
| `survivor/zone_hint.gd` | `ZoneHint extends CanvasLayer` | [生存 UI] 双边缘通知通道：通知层固定低于常驻 HUD 一层；顶部紧急信息从完整当前/剩余时间组下沿滑入后常驻；底部临时提示从下方滑入并停靠于 `3u` 常驻栏上沿，计时后退出；两通道可同时显示，BOSS 全屏警告保持独立 | `TOP_RESERVED_HEIGHT` `show_persistent` `hide_persistent` `show_temp` `show_error_temp` `_slide_top` `_slide_bottom` `show_warning_banner` |
| `survivor/survivor_mode.gd`（扩池压力场） | `_bench_force_enemy_pool_stress` | [测试] 直属 9 机对 17 架扩池敌机：Snowblind、F-22、Gripen E、Rafale、Su-57、J-20、F-15；实体无敌且跳过远距清理 | `bench/run.cmd enemy_pool_stress 20 180` |
| `survivor/survivor_mode.gd`（狂化病毒压力场） | `_bench_force_berserk_virus_stress` `_bench_verify_berserk_virus_lod` | [测试] baseline/enabled 同负载：直属 9 机对扩池 17 敌 + Sentinel/5 护卫；enabled 断言 8 僚机动态门、FREE 与既有友军 LOD 0 | `bench/run.cmd berserk_virus_baseline 15 180 Shadow` / `berserk_virus_stress` |
| `survivor/survivor_mode.gd`（Sentinel 凝聚专项） | `_bench_force_sentinel_escort_cohesion` `_bench_update_sentinel_escort_cohesion` | [测试] 正式生成 1+5+1 包并真实飞行；记录自然/返航后最大距，把一架原生护卫拉到 800px 后验证 10s 内回到 450px | `bench/run.cmd sentinel_escort_cohesion 20 180 Shadow Headless` |
| `survivor/survivor_mode.gd`（DEADAIR 压力场） | `_bench_force_deadair_stress` | [测试] 直属 9 机处在干扰圈内，对 DEADAIR 特殊包 + 16 架额外敌机；覆盖 5Hz CombatUnit/Missile 注册表扫描与主物理路径 | `bench/run.cmd deadair_stress 15 180 Shadow` |
| `survivor/survivor_mode.gd`（无头终局与看门狗） | `_bench_setup_survivor_death` `_bench_update_survivor_death` `_bench_wall_watchdog` `_bench_finish_now` | [测试] 压力场统一从地图中心起飞，避免误触边界模态框；墙钟心跳可识别异常 `SceneTree.paused`；`survivor_death` 验证长机阵亡→僚机接管→全队覆灭→Game Over | `bench/run.cmd survivor_death 10 60 Shadow` |
| `survivor/survivor_mode.gd`（Black Star bench） | `_bench_force_spawn_boss_hyper_a` `_bench_force_spawn_boss_hyper_a_arrival` `_bench_force_spawn_boss_hyper_a_lifecycle` `_bench_spawn_hyper_a` `_bench_update_hyper_a_lifecycle` `_bench_force_spawn_boss_hyper_a_stress` | [测试] 正式身份横幅→玩家附近真实下降 / 状态栏 / 根机无线电 Visual、双根时间线、G0 自然后向全向实弹、G1 侧向拒射 / 自然前向实弹、G2 背向冲锋物理对线、G2 终点急刹扇区实伤 / Visual、确定性 `G0→2G1→4G2→8G3` 胜利结算、16 G3+Sentinel/5 最坏压力与 Visual 捕获 | `boss_hyper_a_arrival` `boss_hyper_a` `boss_hyper_a_g0_weapons` `boss_hyper_a_g1_weapons` `boss_hyper_a_dash` `boss_hyper_a_brake_wave` `boss_hyper_a_lifecycle` `boss_hyper_a_stress` |
| `survivor/survivor_mode.gd`（Black Star FINAL WAR） | `_final_war_promote_primary_squad` `_final_war_reference_level` `_setup_final_war_battlefield` `_setup_final_war_bench_overlay` `_bench_final_war_summary` `_final_war_place_primary_squad` `_final_war_support_node_id` `_final_war_spawn_player_squad` `_final_war_apply_support_build` `_final_war_mount_weapon` `_final_war_spawn_regular_squad` `_final_war_spawn_ship` | [Debug/校准] 海洋群岛正式 MapDocument / 底图 / 天气上的关底规模沙盒；PRIMARY 沿所选 T4 出口进 T5，PRIMARY / SUPPORT 均为 Lv26、8 点、3 件三星军械、四机满配队；另生成 4 普通友机、6 先进敌机与敌我各 2 艘舰船，全部使用真实 AI / 武器 / 伤害 / 死亡且不锁血，随后进入正式 Black Star 双根遭遇。自动 A/B 保留手动编成不变；stress 仅在测试层追加 F-35×2 / J-20×2 与海洋横纵尺度 8/8 镜头巡检，输出隐形、LOD、离屏物理和 Boss 代际实况 | Boss Debug Black Star `FINAL WAR // OCEAN`；`final_war_ocean_baseline` / `final_war_ocean_stress`；F8 完整重开 / 重抽 |
| `survivor/survivor_mode.gd`（Wraith/CSG 性能门） | `_bench_force_spawn_boss_wraith_stress` `_bench_force_spawn_boss_csg_stress` `_bench_set_camera_zoom` | [测试] 真实 0.20 战略视距；Wraith/4 + 首败 YF-23/2 + 12 友军；强化 13 舰 CSG 先经真实 CV 击毁生成 Poltergeist/4，保留 12 舰/32 挂点/持续 VLS/CIWS/Flak/机炮导弹 + 12 友军 | `bench/run.cmd boss_wraith_stress 15 180 Shadow Visual` / `boss_csg_stress` |
| `survivor/survivor_tutorial.gd` | `SurvivorTutorial extends CanvasLayer` | [生存] 新存档基础操作教程 + `tutorial.cfg` 持久化；首批轰炸机 3 杀结算。六项操作含 E 加力和双击突击，操作后条目打勾 | `should_show` `mark_done` `should_show_wingman_switch` `mark_wingman_switch_done` `notify_afterburner` `notify_assault` `notify_bomber_killed` |
| `survivor/survivor_wingman_tutorial.gd` | `SurvivorWingmanTutorial extends CanvasLayer` | [生存] 首次获得僚机时的静态固定号机提示；无 `_process`，实际数字键接管后持久化并淡出 | `_ready` `_build_ui` `_layout` `complete` |
| `survivor/survivor_mode.gd`（王牌调度） | 同上 | [生存] 固定两槽：开局 3:30 第一波、BOSS 前最后 3:00 第二波；开局无放回洗牌、连续两局首队防重复、同局不重复；占场时第二槽待触发，终态后无额外冷却 | `_prepare_ace_run_order` `_update_ace_support_event`；时槽纯函数 `AceSquadProfiles.scheduled_wave_count` |
| `survivor/survivor_mode.gd`（王牌音乐） | 同上 | [音频] 非 BOSS 王牌中队血条浮现时从四首可用曲随机抽一首 one-shot；单曲自然结束或终态只在仍持有当前曲且未进 Boss/Game Over 时，从被打断位置继续普通地图歌单 | `begin_ace_battle_music` `end_ace_battle_music` `_on_music_track_finished` `_play_default_battle_music` |
| `survivor/friendly_asset_aggro.gd` | `FriendlyAssetAggro extends RefCounted` | [生存] 玩家接近已解放机场/奖励航母时，1 Hz 激活据点并按共享配额分流有限敌机；退出迟滞、BOSS/队长/事件保护、动态 MountTarget 归组（spec friendly-asset-aggro） | `register_airfield:37` `register_carrier:42` `register_target:51` `unregister_group:62` `tick:76` `quota_for:85` |
| `tests/test_friendly_asset_aggro.gd` | `extends RefCounted` | [测试] 据点 DORMANT/ACTIVE、2000px 进入、8s 退出迟滞、H→Q 配额、重叠组总上限、友军 300/敌方 1200 船体资源隔离 | `run:10`，bench `friendly_asset_aggro` |
| `tests/test_ciws_intercept.gd` | `extends RefCounted` | [测试] 敌方航母 BOSS 四 CIWS 真实弹道审计；V1/V4/V8 孤弹各 100 次，V4 的 2/4/5/8 枚齐射各 20 次；5 枚拦截率下限 90%、8 枚下限 80%，允许 100% 拦截 | `run:16`，bench `ciws_intercept` |
| `tests/test_dogfight_growth.gd` | `extends RefCounted` | [测试] 纯机炮双 AI 狗斗成长沙盒；F-14 六档机动 build × 当前/属性感知候选 planner × 三种开局，逐帧驱动 Situation/TacticalPlanner/AircraftPhysics，统计机炮解算窗、尾位、能量与盘旋半径 | `run` `_run_duel` `_attribute_aware_plan`，bench `dogfight_growth` |
| `tests/test_target_selection.gd` | `extends RefCounted` | [测试] 目标选择 + 战场引力回归（bench `target_sel`，修复前 35 断言；G6b 新增 2 条已释放 `_current_target` 生命周期边界断言） | `run` `_test_gravity_freed_reference_safety` |
| `tests/player_hud_visual_qa_runner.gd` | `extends Node2D` | [测试] 玩家 HUD 可视化验收场景驱动，构造玩家与第一条僚机 HUD 的红色 HP 受伤相位，确认其余框架/仪表不整体蓝白变色，并输出截图；bench key `player_hud_visual`（DisplayMode=`Visual`） | `_ready` |
| `tests/test_player_instrument_hud.gd` | `extends RefCounted` | [测试] 玩家/僚机/三方向/HUD 偏好、云层与击杀状态、受伤蓝白栏/红白 HP 数字、连续伤害续窗、HP 逐位框、SPD+G `3u`、ALT 五格与连续指针、装饰行、武器装填、底部剩余 XP、三轴数字、真实进化就绪门、逐板升级反色、Q/G/F/T、flare 与互斥 R 机动回归；bench `player_hud` | `run` `_test_damage_flash_contract` `_test_layout_contract` `_test_altitude_preference_display` `_test_milestone_axis_counter` `_test_weapon_priority_cycle` `_test_flare_visual_progress` `_test_unique_r_maneuver_cooldown` |
| `tests/test_flare_timing.gd` | `extends RefCounted` | [测试] 玩家末段投焰时机、敌机小概率不投与 80%→95% 等级执行曲线、四种真实 break 门、正式 release 敌我分流、pending 成功/失败/超时/目标释放及双侧视觉数据 41 项回归；bench `flare` | `run` `_test_enemy_break_chance` `_test_enemy_break_actions` `_test_enemy_release_path` `_test_enemy_break_pending` `_test_visual_side_launch` |
| `tests/test_flare_impact_ab.gd` | `extends RefCounted` | [显式测试报告] 用真实 `MissileEvasion → ControlIntent → AircraftPhysics → Missile` 链比较旧即时 jam、调整前低可靠真实 break 与当前高可靠真实 break；按低/中/高/王牌和 3000/800/300m 统计生存率、8s 攻击可用时间、连续尝试投影，并微基准 pending O(1) 成本；不滚入 `all` | `run` `_compare_row` `_simulate_branch` `_print_sequential_projection` `_run_pending_cost_probe`；bench `flare_impact_ab` |
| `tests/flare_visual_qa_runner.gd` | `extends Node2D` | [Visual] 正式 AircraftRenderer 同屏渲染玩家北向与敌机东向完整十枚热诱弹，验证 0.90s 六波左右侧抛及 3.0–4.8s 可见寿命；bench `flare_visual` | `_ready` `_make_aircraft` |
| `ui/ui_dev_outline_overlay.gd` | `UiDevOutlineOverlay extends Control` | [UI Dev] 只按矩形位置与包含关系生成 2 px 紫色诊断框；顶层 A-Z/AA，子框压成 A1/A2 两级定位，黑底紫字标在框内右上角 | `regions` `flatten_descendants` `build_entries` `alphabetic_code` `_draw` |
| `ui/world_unit_status_overlay.gd` | `WorldUnitStatusOverlay extends Node2D` | [共享/UI] 正式战斗场景唯一世界标签 Canvas 所有者；位于独立 CanvasLayer，每帧只重绘 AircraftRenderer 已登记面板，不遍历场景树或全体单位，使最终标签屏幕轴恒为单位矩阵；面板屏幕原点、紫锥与暴露条取 DisplayPacing 物理插值显示态，标签不在 tick 间相对机体抖动 | `_enter_tree` `_exit_tree` `_process` `_draw` |
| `tests/ui_dev_panel_runner.gd` | `extends Node2D` | [UI Dev] 固定 HUD 排版截图场景驱动：实例化正式玩家/七僚机、顶部当前与战区剩余时间、底部等级—三方向—经验常驻栏、双边缘通知及玩家 HUD 缩放滑条，覆盖默认 `0.9×`、手动 FLR、贴右 `0.5×` 与上下通知画面；正式游戏入口为 F7 | `_ready` `_add_time_preview` `_add_bottom_bar` `_add_bottom_experience_panel` `_add_notification_preview` `_add_ui_scale_control` `_apply_player_scale_preview` `_add_dev_overlay` `_save_bench_screenshot`；bench `ui_dev_panel_visual` / `ui_dev_panel_clean_visual` / `ui_dev_panel_manual_flare_visual` / `ui_dev_panel_scale_visual` / `ui_notification_bars_visual` |
| `tests/test_ui_dev_outline.gd` | `extends RefCounted` | [测试] UI Dev 几何编号、去重、A-Z/AA、两级压平、2 px 向内紫框、顶部当前/剩余时间组、正式物理主循环时间注入位置、战区时钟整数秒/BOSS 状态重绘门、底部 `3u` 等宽侧板常驻栏、双边缘通知、玩家 HUD 六档缩放/默认 `0.9×`/右锚/其它 UI 隔离及 F6/F7 热键的 27 项契约；bench key `ui_dev_outline` | `run` `_test_geometry_only_hierarchy` `_test_stable_top_level_letters` `_test_visual_contract` `_test_scale_contract` `_test_edge_bar_contract` `_test_hotkey_contract` |
| `survivor/map_geography.gd` | `MapGeography extends RefCounted` | [生存] 地图数据 API（OSM + 手画陆地混合）；正式地面部署用全图 land mask 减视觉水面环，并要求 50px 连续陆地净空；`HANEDA_RUNWAYS` 保存与港湾 PNG 对齐的四跑道静态视觉中线/宽度 | `ensure_ready` `is_on_land(pos)` `is_on_land_strict(pos)` `is_on_solid_land(pos)` `is_ground_spawn_safe(pos)` `find_ground_spawn_near(anchor, max_radius_px)` `get_land_polygons` `get_land_mask_polygons` `get_road_bands` — 详见 [map-pipeline.md](map-pipeline.md) |
| `survivor/map_geography_data.gd` | `MapGeographyData extends RefCounted` | [生存] OSM 数据加载器：从 `resources/maps/tokyo_bay.json` 读入 URBAN / ROADS_* / COASTLINE / LAND_MASK | `ensure_loaded` `_unpack` |
| `survivor/map_feature_renderer.gd` | `MapFeatureRenderer extends Node2D` | [生存] 主地图渲染：发布/编辑器/Debug 的东京湾/图2/图3统一按 `tile_map_key` 直连 lossless WebP 三档 renderer；缺 manifest/Strategic 时通知并回到矢量地理，外部 UGC 可兼容自带 PNG。正式瓦片共享 64² 静态蓝噪声（强度 0.014、重复 64、无 TIME/hash），港湾静态补画羽田四跑道，UGC 跑道覆盖在底图上方；冻结纯矢量研究仍由 `Shift+F10` 进入 | `basemap_load_failed` `_report_basemap_error` `_prepare_raster_basemap` `_ensure_legacy_basemap_loaded` `_prepare_vector_preview` `prewarm_detail_region` `attach_cached_detail` `set_vector_preview_enabled` `_draw_sea` `_draw_land_mask` `_draw_ugc_overlays` `_draw_haneda_airport` `_draw_ugc_airports` `_draw_highways` `_ugc_color` `_ensure_basemap_loaded` `_apply_basemap_shader_params` |
| `survivor/raster_basemap_renderer.gd` | `RasterBasemapRenderer extends Node2D` | [生存/候选] 东京湾、沙漠、海洋共享的静态 raster 分档 renderer；Strategic 尺寸由 manifest 按图驱动（当前东京 1536²、沙漠/海洋 1504²），Operational/Detail 为 lossless WebP 瓦片，支持 `edge_gain_by_lod` 与 `luma_scale_by_lod` 静态补偿；V35 迟滞为 Strategic `0.08…0.10`、Detail `0.20…0.24`，使主要战斗 `0.26` 直接消费原尺寸层，Operational 独立固定在 `0.18` 验收。0.40s 目标层置顶覆盖淡入、可见格优先/邻格剩余额度、跨两档 Strategic 桥接、异步请求与每 tick 绑定预算、12 格 LRU/16 格硬门；streamed shader 保留 CanvasItem `COLOR/modulate`；三图共享 import 固化 mip 的 `64²` L8 蓝噪声，强度 `0.014`、重复 `64`，世界空间同相位、不按帧重绘地图 | `map_root_for` `manifest_path_for` `load_manifest` `presentation_profile` `shared_strategic_texture` `presentation_tiles` `setup` `set_active` `debug_state` `load_grain_texture` `make_material` `_profile_lod_float` `_initial_lod` `_update_target_lod` `_begin_transition` `_visible_keys` `_tile_candidates` `_reserve_target_capacity` `_request_target_tiles` `_poll_pending` `_evict_unused` `_exit_tree` |
| `survivor/map_vector_preview_renderer.gd` | `MapVectorPreviewRenderer extends Node2D` | [生存/Debug/冻结研究] V44 全东京湾共享候选 renderer；用户于 2026-08-08 否决其生产视觉，不再作为 PNG 替换路径。Operational/Tab packet definitions 跨场景静态缓存并复用 CanvasTrianglePacket 组包/提交；Operational 26 draw calls / 1,236,202 三角。仅供 `Shift+F10` 诊断与 QA 回归 | `setup` `prewarm_lod` `update_lod` `inspect_lod` `_update_operational_feature_opacity` `_build_packet_definitions` `_add_operational_landmarks` `_add_baked_relief_group` `_build_mask_index` |
| `tests/map_visual_qa_runner.gd` | `extends Node2D` | [测试/Visual] 真实 Godot 4.7 GL Compatibility 固定机位采集；PNG 与候选两侧都包含同一正式 `BuildingRenderer` 189 组游戏地标；V44 审计 669 栋常驻高层、暖灰纸模色块、水面越界、六档层次、8 个正式 `×1.10` 滚轮目标和 0.50–0.98 每 0.02 zoom 连续扫频；另从生产同源 `LOD_TAB` 建 1024² `UPDATE_ONCE` 快照 | `_run` `_capture_tab_vector_snapshot` `_capture_operational_layer_diagnostics` `_settle_frame` `_capture_png`；bench `map_visual_qa ... Shadow Visual` |
| `tests/aircraft_silhouette_preview.gd` / `tests/aircraft_silhouette_visual_qa_runner.gd` | `Aircraft` / `Node2D` | [测试/Visual] 禁用物理与武器，仅经真实 `AircraftRenderer` 绘制 29 个代表机型、MQ-109/110/111 同图换色及概念/旋翼/轰炸机样张并保存 PNG；EA-6B 额外检查左右 alpha 差异，防三视图裁切再次只剩半边 | `_ready` `_draw` `_ea6b_symmetry_error`；bench `aircraft_silhouette_visual ... Shadow Visual` |
| `tests/unit_status_label_visual_qa_runner.gd` | `Node2D` | [测试/Visual] 使用真实玩家/僚机 Aircraft、UAV、Ground/SAM/Radar/Naval/Missile/AURORA LANCE 绘制入口，在旋转且非均匀缩放的父节点下验证共享面板与全英文数据契约，并捕获受伤双相及战略折叠 | `_ready` `_spawn_aircraft` `_prime_damage_flash` `_spawn_ground` `_spawn_drone` `_spawn_sam` `_spawn_radar` `_spawn_naval` `_spawn_super_cannon` `_spawn_missile`；bench `unit_status_label_visual ... Shadow Visual` |
| `tests/test_aircraft_bank_volume.gd` / `tests/aircraft_bank_volume_visual_qa_runner.gd` | `RefCounted` / `Node2D` | [测试/Visual/Perf] 验证滚转投影数学边界与机体族厚度；真实渲染器以 5 类机体 × 7 角度并排绘制旧纸片/新体积并对两组各 3150 次重绘计时 | `run` `_test_projection_geometry` `_test_face_fade` `_measure_group` `_write_perf_report`；bench `aircraft_bank_volume` / `aircraft_bank_volume_visual ... Shadow Visual` |
| `tests/map_detail_atlas_qa_runner.gd` | `extends Node2D` | [测试/Visual] V38 全图覆盖与风格预算审计：逐格复用生产 Detail renderer/cache，将 203 个注册格层叠到 16×16 Operational 底图，并在报告列出完整 256 格、53 个省略格、4 个空格与两个显式海岸边缘例外；记录 RGB/亮度/feature/triangle/bake 和 30 条边界额外跳变 | `_run` `_capture_base_atlas` `_thumbnail_stats` `_atlas_style_metrics` `_atlas_seam_metrics`；bench `map_detail_atlas_qa ... Shadow Visual` |
| `survivor/map_detail_vector_renderer.gd` | `MapDetailVectorRenderer extends Node2D` | [生存/Debug] AGDT detail 包的静态 triangle-array 烘焙源；全图沿用横滨锁定 style，小建筑单层概括、中大型暖灰屋顶、大建筑静态冷暗侧墙；只在一次性临时 viewport 使用，无 `_process` / 持续重绘；最终提交复用 CanvasTrianglePacket | `setup` `prewarm` `release_prewarm` `_append_flat_triangle_packet` `_append_line_packet`；bench `map_gold_slice` |
| `survivor/building_renderer.gd` / `survivor/commander_overlay.gd` | `BuildingRenderer` / `CommanderOverlay` | [生存/表现/R63] 三角数组提交走CanvasTrianglePacket；旧楼实例级来源屏蔽与弱owner退出恢复，不改全局碰撞；building_draw只在帧追踪时单列根桶 | `BuildingRenderer.set_volume_coverage` `_clear_volume_coverage` `_draw` `_draw_visible_districts` `_draw_one` / `CommanderOverlay._draw` |
| `survivor/map_detail_tile_cache.gd` | `MapDetailTileCache extends Node2D` | [生存/Debug] 199 包仅在 loading、战区选择或任意 Tab 航点真暂停时预热；多视口并集必须整体装入 12 格 LRU，超过即回退。Detail zoom alpha 直接取 0.50–0.98 的 1.75 次幂连续曲线，资源覆盖完整度另用 `_coverage_alpha` 做 0.18s 整层渐退，最终两者相乘，避免滚轮忽明忽暗；3072²→1536² GPU 两级线性降采样、4 px 过滤外挤、LRU ≤110 MiB；战斗中禁止烘焙/readback | `bake_cache` `bake_region` `bake_regions` `viewport_region` `regions_plan` `attach_cached` `set_detail_zoom` `detail_opacity_for_zoom` `_refresh_viewport_coverage` |
| `tests/test_map_gold_slice.gd` | `extends RefCounted` | [测试] 横滨金样与整图 detail 资产回归：全 203 AGDT、199 非空格、全 256 网格严格陆地采样、精确锁定两个空海岸边缘例外；全 133 AGLW 解压/三角/预算；12 格 LRU/110 MiB 常驻/150 MiB 峰值；raw JSON 必须留在 `tmp/.gdignore` | `run`；bench `map_gold_slice` |
| `survivor/building_preloader.gd` | `BuildingPreloader extends Control` | [生存/Loading] 分帧旧建筑/矢量缓存与真实东京3D预热；进度和放行等待实际准备，同实例交接；Boss Debug/UGC跳过，失败释放后回退原入口；放行另需 `SurvivorRuntimePrewarm` 完成 | `_ready` `_process` `_prewarm_detail_cache` `_finish` `_volume_progress` |
| `survivor/survivor_runtime_prewarm.gd` | `extends Node`（BuildingPreloader 子节点） | [生存/Loading] 事件型一次性冻结提前；BuildingPreloader 自身建筑/矢量/东京地图预载全部就绪后才 `begin`（不与 15s 超时的地图预载争主线程/加载线程）：常规歌单+王牌曲（沙漠追加曲）+全部 `boss*` 曲（按 id 前缀选取，不编译 survivor_mode.gd）与引擎循环音交 AudioManager 排队线程预载、不等待完成，常量战区陆地可用性预算（UGC 跳过）、王牌支援模板常驻、轮廓解码、4 个离屏透明升级弹窗按真实视口缩放分批绘制全部升级文本（中文系统回退字体查找/栅格化/上传） | `begin` `is_done` `progress` `music_ids_for_map` `_process` `_request_audio` `_step_upgrade_text` |
| `rendering/tokyo_volume_preload.gd` | 根节点单次预热所有者 | [R48/R61] 统一候选路由和普通cells/分层/R4就绪协议、实际绘制预热、同实例交接、画外保留及终态释放 | `script_path` `start` `take` `_begin` `_cut_ready` `state_ready` `_after_draw` `_process` `arm` `_claim` `_intersects` `_activate` `_visibility_changed` `_loading_exited` `cancel` `_exit_tree` `progress` |
| `tests/tokyo_cells_preload_case.gd` | 普通cells真实加载回归 | [R61] 不完整/残缺协议拒绝；真实Session与MapFeatureRenderer同资源接管、画外保留、首次进入、隐藏释放及在途退出；由现有preload生命周期加入all | `run` `_test_states` `_handoff` `_cancel_pending` `_wait_ready` `_wait_gone` `_check` |
| `tests/tokyo_preload_lifecycle_case.gd` / `tests/tokyo_preload_route_probe.gd` | 生命周期 / 原生路线探针 | [R48] 实际资源身份、取消/隐藏/退出、Loading→Survivor地图预览→菜单；不是完整战斗或FPS证明 | `run` `_edge_cases` `_wait_ready` `_wait_gone` `_check`；`run` `_native_capture` `_capture` |
| `tests/export_tokyo_ground_planes.gd` | 原生地表只读导出 | [R47准备] 固定平面三角形与来源摘要导出，不修改地图资源 | `run` `records` |
| `survivor/map_manual_background.gd` | `@tool MapManualBackground extends Node2D` | [生存/编辑器] `map_manual.tscn` 的参考底图预览：在 Godot 编辑器里实时画出 OSM 数据作为描边参考 | `_draw_land` `_draw_urban` `_draw_roads` `_draw_info_text` |
| `survivor/axis_bars_panel.gd` | `AxisBarsPanel extends Control` | [生存] 三轴量表控件（spec evolution-attribute-gates §3.2 v6）：10 分格立柱逐格点亮 + 里程碑刻度圈三态 + 轴色（SurvivorData.AXIS_COLORS）；静态绘制仅 show_state 时重绘；Tab 面板与结算坞右栏共用；"+1 轴进度"加成格=半透明+亮边叠在点数格上、柱顶显示 `点+加成`（spec skills-720-rework §1.1） | `show_state(axis_points, profile, milestone_bonus)` `_draw` |
| `survivor/milestone_axis_counter.gd` | `MilestoneAxisCounter extends Control` | [生存/HUD] 主 HUD 底部 `3u` 常驻栏内、经验条上方的 `408 × 36 px` 三方向计数器；三个 `136 px` 等宽区各含上下分格的反色轴名与 `当前/8` 数字、八个常显 `0.5q` 点击格，按玩家实际点击数从左向右点亮；纯显示、无逐帧处理 | `update_display(player)` `_draw` `cell_rect` `name_rect` `axis_title_rect` `axis_value_rect` `point_rect` `grid_regions` |
| `survivor/bottom_experience_panel.gd` | `BottomExperiencePanel extends Control` | [生存/HUD] 底部常驻栏中央 `684 × 54 px` 等宽侧板组合：左侧 LV 与两个正式 `49 × 54 px` 的 `3u` 独立框版等级数字，中部 `408 × 18 px` 经验条，右侧显示距下一级剩余 XP，并在真实可进化且有可用停靠点时点亮独立黄色进化格；升级时按左板→经验条→右板依次反色一次 | `update_display(player, evolution_ready)` `flash_level_up` `flash_index_at` `xp_remaining` `formatted_level_digits` `level_digit_color` `left_panel_rect` `xp_rect` `xp_remaining_rect` `xp_remaining_label_rect` `evolution_ready_rect` `grid_regions` `_draw` |
| `survivor/warzone_time_panel.gd` | `WarzoneTimePanel extends Control` | [生存/HUD] 顶部正中战区剩余时间：四个 `2u` 独立框版数字、居中的冒号分隔格，以及下方同宽 `1u` 本地化说明框 | `update_display` `localized_remaining_label` `formatted_remaining_time` `digit_rect` `separator_rect` `label_rect` `grid_regions` `_draw` `_cached_text_layout`（逐格字号基准查表） |
| `survivor/player_instrument_panel.gd` | `PlayerInstrumentPanel extends Control` | [生存/HUD] 右下角常驻玩家 HUD（类名为兼容保留）；实际受伤后仅 HP 模块红色闪烁，其它框架与仪表保持原色；单发完整播放、连续命中只续窗不重置相位 | `update_display(ac, charge)` `register_damage_event` `damage_flash_phase` `damage_hp_color` `hp_damage_regions` `update_status(in_cloud, kills)` `_process` `_configure_layout` `_draw` `_draw_impl` `grid_regions` `_draw_weapons` |
| `survivor/wingman_instrument_panel.gd` | `WingmanInstrumentPanel extends Control` | [生存/HUD] 玩家 HUD 上方可增减的僚机 HUD 信息行；每行独立消费伤害 token，实际受伤后仅对应 HP 红闪，框架与其它字段不整体变色；连续命中续窗 | `update_display(rows)` `_sync_damage_rows` `damage_flash_active_for_slot` `grid_regions_for_row` `grid_regions` `_apply_row_count` `_draw_row` |
| `ui/hud_preferences.gd` | `HudPreferences extends RefCounted` | [共享/UI] `user://hud.cfg` HUD 偏好持久化：新档默认白色主调，保留绿/青/琥珀/白预设、自定义线框色及 KT/KM/H；已有保存选择不覆盖 | `speed_unit` `set_speed_unit` `cycle_speed_unit` `hud_color` `set_hud_color` |
| `ui/hud_color_settings_panel.gd` | `HudColorSettingsPanel extends CanvasLayer` | [共享/UI] 主菜单白色终端色盘弹层；四预设 + ColorPicker，自身与仪表偏好实时同步 | `open` `close_panel` `_build_ui` `_add_preset` `_on_save` |
| `ui/terminal_text.gd` | `TerminalText extends Control` | [共享/UI] 通用字号规范唯一实现：无内边距、显式对齐、固定 1u Silkscreen 15px、真实字形撑高及固定字号后的整数步长扩宽；字符串结果与最终 glyph 轮廓各有 2048 项有界缓存，均逐项环形淘汰；`resolve_font_layout` 结果（1024 项）与单行宽度（4096 项）按字体身份/文本/精确区域缓存，逐字号试探先比宽度再测轮廓，结果与原算法逐值相同 | `FontFace` `SizeRule` `MAX_INK_BOUNDS_CACHE_ENTRIES` `MAX_GLYPH_BOUNDS_CACHE_ENTRIES` `layout_text` `horizontal_alignment` `_draw` `resolve_font_layout` `_resolve_font_layout_uncached` `_layout_fits_size` `cached_string_width` `reset_measure_caches` `font_size_for_ink_height` `expanded_width_for_fixed_text` `measure_ink_bounds` `_glyph_ink_bounds` |
| `ui/terminal_grid_overlay.gd` | `TerminalGridOverlay extends Control` | [共享/UI] 终端网格统一描边层；属性未变不重画，全部框板边线去重后合为一次 multiline；父子/相邻 u 与 q 的边界共用坐标，缩放后保持 1 个物理像素；F3 明细开启时只在外层 `_draw` 计时 | `SCALE_INVARIANT_LINE_WIDTH` `regions` `override_regions` `edge_insets` `outline_segments_for` `edge_safe_region` `_draw` `_draw_impl` |
| `tests/test_terminal_text.gd` | `RefCounted` 测试脚本 | [测试] 通用字号、共享网格坐标、缩放不变 hairline 与字形轮廓缓存回归；含动态数字复用、直接 TextServer 等价及容量门；bench `terminal_text` | `run` `_check_visible_fill` `_check_ink_bounds_cache` `_check_dynamic_glyph_cache` `_direct_ink_bounds` `_check_one_u_fixed_15` `_check_height_first_q_expansion` `_check_shared_grid_coordinates` `_check_scale_invariant_grid_lines` |
| `tests/test_event_hitch_prewarm.gd` | `RefCounted` 测试脚本 | [测试] 事件型冻结缓存/预热一致性：排版缓存与原逐字号试探逐值对照、计时面板查表、轮廓缓存环形淘汰、战区陆地记忆 vs 原多边形现场计算、ADBS 同种子候选、音频/王牌模板常驻、轮廓预热、升级预热批次不解锁输入；bench `event_hitch_prewarm` | `run` `_legacy_resolve` `_legacy_fits` `_test_layout_equivalence` `_test_zone_land_memo` `_test_adbs_city_candidates` `_legacy_pick_city_center` `_test_audio_resident` `_test_upgrade_prewarm_batch` |
| `survivor/tactical_map.gd` | `TacticalMap extends CanvasLayer` | [生存] 战术缩略图：东京湾、图2、图3发布/Debug 统一按 `tile_map_key` 直接消费同图 Strategic lossless WebP（东京 1536²、沙漠/海洋 1504²）。沿用固定中性乘色，不重复套主地图 shader、不创建第二份快照纹理。`readout_only` 给 Boss Debug 保留实际 ACE 武器/技能/三轴/里程碑面板而跳过地理；普通预览图禁止误载东京湾 Aqua-Line并可在 `ZoneData=null` 时作为无战区导航图；正式瓦片缺失时消费同一 palette 矢量地理，外部 UGC 自带 PNG 仍兼容；港湾补画羽田跑道，UGC 跑道覆盖在底图上方 | `_ensure_raster_basemap` `_on_map_draw` `_ensure_minimap_basemap` `_draw_minimap_raster` `_draw_geography` `_draw_cities` `_rebuild_haneda_runway_cache` `_draw_haneda_airport` `_draw_ugc_airports` `_map_color` `_refresh_weapon_loadout` `refresh_zone_state` `_should_hide_zone` `_draw_one_zone` `_draw_bomber_route_and_target` `_zone_id_at` `_refresh_info` `_draw_deadair_field` `_handle_map_click` |
| `survivor/adbs_manager.gd` | `AdbsManager extends Node` | [生存] ADBS 背景事件调度；教程轰炸机固定锚点；城区 CH-47 每窗 25% 概率、整局最多两次且活跃组互斥，从距玩家 ≥12km / 距边界 ≥8km 的全图城区生成并保留 Tab 实时标记 | `_physics_process` `_trigger_city_heli_event` `city_heli_schedule_allows` `city_heli_spawn_candidate_allowed` `_pick_city_center` `_city_centroids`（城区质心按城区数组身份缓存） `_active_zone_circles`（每次选点快照一次活跃战区圆） `_pos_in_zone_circles` `_track_city_heli_kills` `_award_city_heli_bonus` |
| `survivor/tactical_map.gd`（里程碑数值格式） | `_fmt_milestone_bonus` / `_fmt_milestone_value` | [生存] mult 显示百分比；机炮闪避 additive 0.10 显示 +10%；G additive 0.2 保留一位小数 | `survivor/tactical_map.gd:1615 _fmt_milestone_value` |
| `survivor/zone_data.gd` | `ZoneData extends RefCounted` | [生存] 战区状态/难度/任务/奖励预抽；每局复制默认战区定义并允许 MapDocument 按稳定 id 覆盖地理/名称；正式 A/B 延迟到 60s+Lv3，首个 optional 延迟到 150s+Lv5；可选任务整局配额=保底 1 + 20% 第二次（最多 2）；全局同时只允许一个 3★ 战区；FAILED 无收益终态 | `apply_map_zone_overrides` `get_zone_definitions` `MAX_CONCURRENT_TIER3_ZONES` `active_tier3_zone_ids` `debug_set_difficulty` `initial_reward_unlock_ready` `release_initial_reward_zones` `release_first_optional_mission` `bomber_escort_xp_reward` `mark_cleared` `mark_failed` `zone_has_land`（按 id 记忆，地理数组替换即失效） `prewarm_zone_land` `_zone_land_fraction_ok` |
| `survivor/battlefield_flow.gd` | `BattlefieldFlow extends RefCounted` | [生存] 单局战场规则聚合根；独占净时间轴、战区/BOSS 阶段、超时关闭事务、王牌固定槽/无放回账本与 ORION 一次性门，不持有场景对象 | `reset_run` `advance_time` `remaining_s` `apply_time_cost` `grant_time_extension` `close_warzone_if_due` `prepare_ace_run_order` `claim_next_ace_profile` `claim_orion_if_due` |
| `survivor/survivor_runtime_reset.gd` | `SurvivorRuntimeReset extends RefCounted` | [生存] 新局/退局共用的跨场景 static 清理入口；断开王牌 RefCounted 注册表、技能队级开关与 ObjectiveContext/SkillHooks 局内状态 | `reset_cross_scene_state` |
| `survivor/zone_mission.gd` | `ZoneMission extends Node` | [生存] 战区任务按需生成/触发/成功/失败；未观察的普通 1★/2★ AVAILABLE 只保留战略信息，镜头预加载/选择/进入后一次性 LIVE 并保持到终态，3★公开即投射；终态地面单位低成本留场；飞机沿最近边界物理撤离，出界/远离玩家/持续离开镜头缓冲区后才按 5Hz/每 tick 4 架预算释放；3★ 按地图生成超级巨炮/攻城坦克/远程 VLS/DEADAIR 四类高威胁源，profile 首次查询即按战区固化并供 Tab/开始提示/实体生成共享，来源消失即撤效果但仍须清空全部正式 TGT；Boss 转场与普通战区统一停火退役；画外选中任务保留 6 秒广播，镜头覆盖时绘制前准备且不等待广播；已生成目标不随等级刷新；空战 TGT、普通驻守与 Sentinel 驻守全部从地图边缘入场；普通地图按已激活战区一次性 30% 抽取集中气氛层，决战地图全覆盖；`bomber_escort` 使用独立等时航线与动态追击编成 | `prepare_visible_zones` `_zone_overlaps_view` `_zone_supports_ground` `_build_spawn_road_index` `_index_spawn_road_path` `zone_simulation_should_activate` `resolve_tier3_profile` `mission_desc_key_for` `mission_started_fmt_key_for` `_spawn_tier3_profile` `_register_tier3_sources` `_update_tier3_source_states` `_spawn_tier3_super_cannon` `_spawn_tier3_siege_tank` `_spawn_tier3_deadair` `_tier3_naval_params` `debug_set_tier3_profile` `debug_neutralize_tier3_sources` `_ensure_spawned_for_active_zones` `_spawn_air_squadron` `_spawn_zone_defenders` `_begin_conquered_garrison_egress` `_command_conquered_enemy_exit` `_flush_pending_despawn` `_refresh_retained_ground_views` `_register_zone_atmosphere` `_prepare_bomber_escort` `_start_bomber_escort` `fail_zone` `reset_zone` |
| `survivor/unit_retirement.gd` | `extends RefCounted` 静态工具 | [生存] 飞机退役共同门：真实出界、玩家距离、镜头缓冲与连续离屏宽限；停战导航和静默释放，无常驻节点；ZoneMission/Spawner 各自保留有预算的生命周期队列 | `begin_aircraft_exit` `release_ready` `free_aircraft` |
| `tests/unit_retirement_visual.gd` | `extends survivor_mode.gd` | [测试] 48 地面留场 + 36 飞机撤离，正式失败/镜头/LOD 路径，反复返回验证原实体与真实位移，逐帧帧时与截图 | `_setup_bench_scenario` `_ready` `_process` `_check_retained_roster` `_finish_retirement_visual`；bench `unit_retirement_visual` |
| `survivor/zone_atmosphere_combat.gd` | `ZoneAtmosphereCombat extends Node2D` | [生存] 正式战区集中气氛层（2Hz）：普通地图每区 30% 一次性抽取，海洋群岛决战地图全覆盖；空战零增员复用既有目标，陆战双方固定阵营专用 SPG，并等概率覆盖友/敌武装直升机四种组合；直升机只与地面互殴、不是 TGT，敌军击毁给 XP；海战只补友军；1500/1800px 伤害迟滞、玩家优先与低成本表演弹道 | `ORDINARY_ZONE_CHANCE` `DECISIVE_MAP_IDS` `enabled_for_roll` `cached_enabled` `setup` `register_zone` `helicopter_sides_for_roll` `_spawn_atmosphere_helicopter` `_spawn_artillery_group` `_find_land_artillery_plan` `_mark_actor` `_update_ground_fire` `_resolve_shell` `retire_zone` `retire_all` `actor_count` `terrain_violation_count` |
| `survivor/tier3_super_cannon_part.gd` | `Tier3SuperCannonPart extends GroundUnit` | [生存] 3★ AURORA LANCE 完整单体：英文战术标签；84px 固定圆形基盘承载独立旋转的回转座/设备舱/桁架炮管/后支撑架并共用一个 TGT/HP/销毁；每轮随机瞄准存活长机/僚机，5–88km 预警先 4.0s 从细线扩到 180px，再满宽闪烁 1.5s 后以 90px 半径同拍结算；高速长条弹迹只作表现；2.5 km 内无防空与反击 | `DISPLAY_NAME` `WARNING_FILL_S` `WARNING_FLASH_S` `AOE_RADIUS_PX` `configure` `_eligible_aim_targets` `_choose_aim_target` `_update_body_fire` `_set_body_heading` `warning_fill_ratio` `warning_width_px` `warning_is_flashing` `_begin_warning` `_fire_snapshot` `_draw_stationary_base` `_draw_rotating_turret` `_update_projectile` `cease_tier3_threat` |
| `survivor/tier3_siege_tank.gd` | `Tier3SiegeTank extends GroundUnit` | [生存] 3★ 攻城坦克本体；生成 2×CIWS、1×远程 SAM、1×空爆挂点，并以独立主炮攻击同区友军气氛地面单位，一次可信直击摧毁一个 | `configure` `arm_mounts` `_spawn_ciws` `_spawn_sam` `_spawn_flak` `_nearest_atmosphere_ground_ally` `_begin_shell` `_update_shell` `cease_tier3_threat` |
| `survivor/tier3_siege_ciws.gd` | `Tier3SiegeCIWS extends AAGunUnit` | [生存] 攻城坦克双用途 CIWS 子挂点；优先认领并拦截来袭导弹，无来袭时复用 AA 对空开火；挂点随车移动且不可单独锁定/摧毁 | `_nearest_incoming_missile` `_missile_is_threat` `_update_intercept_fire` `_release_engaged_missile` |
| `survivor/tier3_siege_sam.gd` / `survivor/tier3_siege_flak.gd` | `Tier3SiegeSAM extends SAMUnit` / `Tier3SiegeFlak extends AAGunUnit` | [生存] 攻城坦克远程 SAM 与空爆子挂点；射程属于 SAM 武器本身，挂点保持贴近车体并随车移动，不作为独立 TGT | `configure` `_physics_process` `is_lock_immune` |
| `survivor/bomber_mission.gd` | `BomberMission extends Node` | [生存] 10Hz 集中控制阵营对称轰炸任务；可配置每机投弹数、绑定 StrategicTarget/截止时间，缓存编队质心/朝向并提供成员/存活数/航段只读状态；成功优先于失败，最后一枚在途炸弹保留落地窗口，`abort` 会让幸存编队真实转 EGRESS 后发失败信号 | `setup` `get_live_center` `get_live_heading` `get_release_count` `get_bombers` `get_remaining_time` `get_alive_bomber_count` `get_alive_escort_count` `get_phase_key` `abort` `_update_outcome` |
| `survivor/pause_menu.gd` | `PauseMenu extends CanvasLayer` | [生存/UI] 白色终端暂停确认页；ESC 打开＝硬暂停（走 `Presentation.present("panel_in")`），继续为安全白框、返回主菜单为红色危险框；layer 21 + `PROCESS_MODE_ALWAYS`，退出分支解暂停交给 `Presentation.clear_all()` | `open` `close` `is_open` `get_transition_elements` `_build_ui` `_make_button` `_on_resume_pressed` `_on_quit_pressed` `signal resumed` `signal quit_to_menu` |
| `survivor/map_boundary.gd` | `MapBoundary extends Node2D` | [生存/地图] 三图共同 64km 真边界与旧 60km 核心入口；四边 2km 外缘空域连续停留 2.5s 才发决策，返回核心取消并重新武装；相机内容矩形内收 32px，AI 只在真边界前 300px 收容；静态绘制核心入口、外缘带与真边界 | `get_world_rect` `get_camera_bounds` `get_core_rect` `distance_to_extension_entry` `is_in_extension_zone` `distance_to_edge` `is_safe_inside` `clamp_inside` `_process` `signal approach_warning` `signal boundary_countdown` `signal boundary_crossed` |
| `survivor/boundary_ui.gd` | `BoundaryUI extends CanvasLayer` | [生存/UI] 外缘接近与 2.5s 倒计时提示；耗尽后以既有硬暂停终端页提供补给 / 调头 / 撤退，BOSS 阶段禁用补给；返回核心时只隐藏倒计时，不打开面板 | `on_approach` `on_countdown` `on_crossed` `_open_menu` `_on_supply_pressed` `_on_cancel_pressed` `_on_retreat_pressed` |
| `survivor/encounter_director.gd` | `EncounterDirector extends RefCounted` | [生存] 2Hz 集中 Encounter 账本；从 `CombatUnit.all_units` 统计 Presence/有效 PR，Global Package admission、10–18s 无债务冷却、8–12s Recovery 与普通敌机 Lethal Slot；只读 `RoeDirector.heat`，临时 ALLY 计性能人口但不抬直属小队目标；N≥4 开局驻防稳定为三机完整 Element | `tick` `global_admission` `commit_global_package` `consume_denied_opportunity` `begin_recovery` `pressure_snapshot` `pressure_cost_from_token` `pressure_target_for` `lethal_capacity_for` `resolve_flight_elements` `opening_garrison_size_for` `request_lethal_attack` `shutdown` |
| `survivor/survivor_spawner.gd` | `SurvivorSpawner extends Node` | [生存] 刷怪系统；Global 逐机波改为原子 `Package→Element→Squad/Solo`，沿用玩家 N 软响应、Token/实例/冷却硬门并由 Encounter Director 补 PR admission；4 机可解析双双机 Element；Snowblind/DEADAIR 为支援核心+护卫双机，Sentinel 固定 1+5+1，原生护卫 700px 持续召回且不进全局 hunter 池；正式增援与战区空军复用边缘入场算法 | `_update_spawner` `_try_spawn_global_package` `_admit_global_package` `_global_package_geometry` `_pick_role_companion` `_rollback_package` `_tag_encounter_member` `_bind_support_escort` `_spawn_single` `_spawn_squad` `_spawn_snowblind_squad` `_spawn_deadair_squad` `_spawn_commander_squad` `_ensure_sentinels_escorted` `_recall_detached_sentinel_escort` `_update_hunters` `begin_encounter_recovery` `_create_enemy` `_update_boundary_discipline` `enforce_boss_world_boundary` |
| `survivor/skill_hooks.gd` | `SkillHooks` 静态服务 | [生存] 低频技能事件汇合；Hunter/J36 突击态、JAM/FEAR/命中/击杀钩子；狂化病毒僚机击杀触发标准 BLOODLUST；火控饱和五锁沿；F/A-XX 仅 ACE 本机机炮击杀触发 5s STEALTH、20s CD | `try_trigger_j36_assault` `try_fire_control_saturation` `on_player_jam_landed` `on_player_fear_landed` `dispatch_on_kill` `dispatch_on_hit` `hush_blocks_flare` |
| `survivor/survivor_skill_catalog.gd` | `SurvivorSkillCatalog extends RefCounted` | [生存/技能] `UPGRADES` 的纯规则投影层；统一普通随机候选、三轴分组、单机有效层数与晚入队/换型重放计划，不持有状态、不另建技能表 | `normal_candidates` `candidates_by_axis` `effective_stacks_for_machine` `replay_layers_for_machine` `owned_replay_layers` |
| `survivor/survivor_skill_runtime.gd` | `SurvivorSkillRuntime extends RefCounted` | [生存/技能] 玩家技能总账本到队级加力资源与 static 自动技能开关的唯一同步/新局清零入口 | `sync_team_state` `reset_team_state` |
| `survivor/survivor_skill_effects.gd` | `SurvivorSkillEffects extends RefCounted` | [生存/技能] 获得时静态效果执行器；显式接收目标 Aircraft，集中修改机体、武器 Resource 与玩家级倍率；未知 stat 报警 | `apply` |
| `survivor/enemy_pool_registry.gd` | `EnemyPoolRegistry extends RefCounted` | [生存] 常规敌池 SSOT：57 型中的 43 个可随机条目、五角色权重、解锁/退役/Token/上限/编成/冷却、最近三队防重复；提供 ADBS 护卫零 Token 过滤池与敌版参数走廊审计 | `ROWS` `eligible_rows` `escort_rows` `pick_row` `row_for_type` `audit_enemy_params` |
| `survivor/f22_multilock.gd` | `F22Multilock extends RefCounted` | [生存] F-22 队级四锁控制器；生成边沿登记，5Hz 分配不同直属目标，活跃期只推进 0.15s 队列；近压与齐射后 12s 脱离 | `register` `tick` `shutdown` `allocate_unique_targets` `_logic_step` `_update_execution` `_enter_egress` |
| `survivor/schemer_multilock.gd` | `SchemerMultilock extends RefCounted` | [生存] Gripen C/E、Rafale、F-35 共享低频多锁；只遍历登记的特殊机，team3 队级三目标或 per2 单机双目标 | `register` `has_units` `tick` `shutdown` `_plan_team_three` `_plan_per_aircraft` `_update_queues` |
| `survivor/snowblind_controller.gd` | `SnowblindController extends RefCounted` | [生存] 创建当帧注册本体并立即隐藏，编成后同帧刷新护卫；常态 5Hz 雪幕控制；3★ DEADAIR 入场时可按单一优先支援场规则立即揭露并退役旧场 | `register` `refresh_now` `tick` `retire_for_priority_field` `has_active_state` `shutdown` `next_reveal_state` `_apply_concealment` `_release_cross_boundary_targets` |
| `survivor/snowblind_shroud_visual.gd` | `SnowblindShroudVisual extends RefCounted` | [生存] Snowblind 单圆形 CanvasItem：64 段静态 Polygon2D，本地坐标连续雾团/低对比雪带由 shader `TIME` 驱动，并在圆心画不可交互本体轮廓；世界 Z 固定在地图/地面海面单位之上、所有飞机图标之下，不受宿主/生成顺序影响；破幕/复隐共用 0.80s sine ease-in-out，反向从当前值折返；无 `_process/_draw/queue_redraw` | `attach(host)` `set_concealed(host, concealed, immediate)` |
| `survivor/deadair_controller.gd` | `DeadairController extends RefCounted` | [生存] DEADAIR 唯一 5Hz 累积控制器：敌对 CombatUnit 8s 后标准 JAM，导弹按 4× 在 2s 永久失导；单位离圈 1s 宽限后 2/s 衰减；3★ 来源可替换普通场并在来源消失时立刻撤销全部效果 | `register` `replace_with_priority` `retire` `refresh_now` `tick` `field_snapshot` `next_unit_exposure` `next_missile_exposure` `shutdown` |
| `survivor/deadair_field_visual.gd` | `DeadairFieldVisual extends RefCounted` | [生存] DEADAIR 单 Polygon2D 红紫扫描场，64 段静态 mesh + shader `TIME`；无 `_process/_physics_process/_draw/queue_redraw`，死亡时 0.6s collapse | `attach(host)` `collapse(host)` |
| `survivor/dock_point.gd` | `DockPoint extends Node2D` | [生存] 停靠点组件（spec zone-reward-docking）：600px 圈 + 速度≤250km/h 持续 1s → `docked` 信号；机场/航母甲板共用；减速提示/进度环绘制；`mode` 引用每帧解析当前操控机（1–9 切控安全）；720 批地勤优化=持有 `ground_crew` 时停靠判定耗时减半 | `_process` `_draw` `signal docked` 常量 `LAND_SPEED_KMH/HOLD_SEC` |
| `survivor/battlefield_atmosphere_experiment.gd` | `BattlefieldAtmosphereExperiment extends Node2D` | [生存/Debug] 真实局海陆空气氛实验；画外仍连续开火/保留弹道，1500/1800px 玩家距离迟滞只切真实伤害；零伤害普通弹复用视觉快路径，轰炸炸弹豁免；AH-64 禁火箭，火炮 3v3，海战安全小巡航圈/低伤害必中/无鱼雷；演员 typed 数组的清理/重指派先走 Variant 有效性边界，释放后下一 tick 安全 | `_prime_damage_lod` `_update_damage_lod` `_set_air_damage_enabled` `_spawn_ballistic_shell` `_resolve_ballistic_impact` `_queue_effect_redraw_if_visible` `_cleanup_refs` `_is_live_aircraft` `_is_live_experiment_unit` `launch_stress_battle` |
| `survivor/atmosphere_artillery_unit.gd` | `AtmosphereArtilleryUnit extends GroundUnit` | [生存/Debug] 气氛实验自行火炮外观与 3m/s 解析式椭圆轨道；正式战区可按中心、尺寸与随机初相位配置，位置由方程直接求值、切线定朝向，无 waypoint 过冲/端点掉头/累计漂移；容量 bench 可拒绝正式战区导弹的一击必杀，射击由共享控制器调度 | `take_missile_damage` `configure_rail` `configure_ellipse` `_update_movement` `_draw_ground_icon` |
| `survivor/survivor_debug_spawn.gd` | `SurvivorDebugSpawn extends CanvasLayer` | [生存] F5 刷怪调试面板；普通单机/小队/Sentinel 传 `debug_near_player=true` 即时刷在玩家附近，Snowblind/DEADAIR 特殊包沿用该位置；BOSS/王牌/Adds 仍走各自正式事件航路 | `_build_ui` `_on_type_changed` `_on_spawn_pressed` `_start_ace_event` `_on_atmosphere_pressed` `_on_atmosphere_ground_pressed` `_on_atmosphere_naval_pressed` `_on_atmosphere_status_changed` `_on_clear_pressed` `_on_dump_pressed` |
| `survivor/survivor_debug_skills.gd` | `SurvivorDebugSkills extends CanvasLayer` | [生存] F4 技能/装备调试面板：动态覆盖全技能表；不适配技能仍可强制授予（仅尊重层数上限）；装备区可直挂尾雷/忠诚僚机/火箭/QMAAM/电磁炮/激光/ESM | `_refresh` `_build_skill_row` `_on_add_skill_by_id` `_on_loadout_changed` `debug_skill_ids` `debug_can_force_upgrade` `debug_has_loadout_kind` |
| `survivor/survivor_debug_zone.gd` | `SurvivorDebugZone extends CanvasLayer` | [生存] F6 战区调试面板：巨炮/坦克为原子 `ground + 3★ + profile` 预设并转移唯一 3★槽，其余类型可指定 1–3★重刷；通过真实伤害一键消灭威胁来源；同时保留计时、天气、Boss、机场进化树和 15 项奖励直发 | `normalize_zone_change_request` `_build_ui` `_apply_zone_change` `_on_neutralize_tier3` `_on_grant_reward` `debug_reward_keys` `_on_skip_to_boss` `_on_fast_forward` `_on_skip_midgame` `_on_visit_airfield` |
| `survivor/survivor_player.gd` | `SurvivorPlayer extends Node` | [生存] 经验/等级、三轴里程碑与局内武器库状态；升级公开 API 只校验目标并委托 `SurvivorSkillEffects`，不再临时替换当前操控机引用 | `add_xp` `apply_upgrade` `apply_upgrade_to` `strip_upgrade_from` `add_axis_point` `add_milestone_bonus` `get_axis_points` `get_milestone_progress` `total_axis_points` `milestone_xp_multiplier` `apply_crossed_milestones` `reapply_all_milestones` `record_special_weapons` `remount_weapons` |
| `survivor/survivor_player.gd`（策士 XP 里程碑） | `milestone_xp_multiplier(profile)` | [生存] 从策士里程碑进度动态生成玩家级 XP 乘区，避免全队逐机下发导致按编队人数重复相乘 | `survivor/survivor_player.gd:129 milestone_xp_multiplier` |
| `survivor/survivor_data.gd` | `SurvivorData extends RefCounted` | [生存] 升级表/波次常量/Token 预算/经验曲线 + 三轴里程碑与卡片轴映射；小队规模纯函数；4 级金卡软 pity；机体战术适配 15% 边界、身份轴等概率与第四槽去重；50 机专属槽映射（43 已实装 + 7 不进技能池/商店的空占位）；电子战类别雷达每技 +3% 且 ×1.30 封顶；普通敌机等级只加耐久 | `UPGRADES` `SIGNATURE_PLACEHOLDERS` `is_upgrade_available_for` `upgrade_by_id` `recompute_category_bonuses` `enemy_scale_for_level` `signature_upgrade_id_for_aircraft` `signature_upgrade_for_aircraft` `is_signature_placeholder` `is_signature_upgrade` `is_normal_random_candidate` |
| `survivor/survivor_upgrade_ui.gd` | `SurvivorUpgradeUI extends CanvasLayer` | [生存/UI] 预建四张普通技能介质：基础三轴显示三张，机体战术适配命中时显示第四张与高对比轴色来源条；标签保留技能/稀有度/三轴/限定；词条 hover/focus 旁注、`0.80s` 输入保护与垂直压入确认动作不变 | `populate` `_fill_cards`（徽章多项主题覆盖批量提交、未变字色跳过：在树控件每次写覆盖都会同步重建主题缓存） `_set_font_color` `prewarm_render_batch`（Loading 字形预热批次，不解锁输入） `_build_ui` `_schedule_input_unlock` `_unlock_choice_input` `_note_popup_position` `get_transition_elements` `_description_bbcode` `_set_note_revealed` `schedule_entry_flashes` `_play_media_boot` `_on_choice_pressed` |
| `survivor/upgrade_media_surface.gd` | `UpgradeMediaSurface extends Control` | [生存/UI] 技能介质实体底板；STABLE～EXPERIMENTAL 软盘、CLASSIFIED/NEXT_GEN 光盘，注塑层/滑片/盘面/接口均为状态驱动静态绘制，无 process；软盘底部仅保留写保护口与导轨，不绘制易误读为按钮的圆形轴孔 | `configure` `set_selected` `_draw` `_draw_floppy_media` `_draw_optical_media` |
| `survivor/commander_aura.gd` | `CommanderAura extends Node` | [生存] Sentinel 光环 buff + 招募 UAV；0.5s 全量重算“小队成员∧半径内”，单 owner 仲裁，运行时字段注入且不改永久 params，离队/越界/退出节点撤除 | `_scan_and_buff` `_apply_buff` `_remove_buff` `_remove_all_buffs` `_try_recruit` |
| `playable_aircraft.gd` | `PlayableAircraft extends Resource` | [生存] 主角档案：UI 元数据 + base_params 引用 + 生存模式调味（含逐机 `gun_ammo_override`、单发 cap 后机炮承伤 `bullet_damage_taken_mult`、只在选作本局起手机时结算的 `starting_benefit_id`、属性/武器/战斗/热诱弹覆盖）+ 起始僚机配置 | 全部 `@export` 字段；详见 [playable-aircraft-workflow.md](playable-aircraft-workflow.md) |
| `survivor/survivor_playable_setup.gd` | `SurvivorPlayableSetup extends RefCounted` | [生存] 把 PlayableAircraft 应用到 Aircraft 实例；深拷后注入逐机机炮弹量等覆盖，合并机型代号并在实例 meta 保存战场标签用的纯机型编号 | `display_name_with_codename(base_name, codename)` `apply(aircraft, profile)` `deep_dup_weapons(params)` |
| `survivor/aircraft_db.gd` | `AircraftDB extends RefCounted` | [生存] 50 机档案注册表（含四架 T0 与三架低位 T1；UGC 护栏 2：按 id 取档案唯一入口） | `get_profile(id)` `register(id, path_or_res)` |
| `survivor/evolution_system.gd` | `EvolutionSystem extends RefCounted` | [生存] 进化系统：读 evolution_tree.json + 整机换档案 + 品类身份；换机后导弹/机炮/热诱弹均按新档案装满；发现态由正式局调用方显式传入，bench/僚机进化不污染 AircraftCodex；可用出口统一检查等级与三轴双门 | `node_of` `exits_of` `has_available_exit` `node_id_for_profile` `min_level_of` `evolve(ac, node_id, is_wingman, record_discovery)` `class_identity_of_profile` `CLASS_IDENTITY_BY_CATEGORY` |
| `survivor/evolution_ui.gd` | `EvolutionUI extends CanvasLayer` | [生存/UI] 停靠规划站三栏：左=可滚动进化树，中=所选机体详情，右=三轴量表 + 洋红“保留当前机并装备专属技能”卡 + 白色进化卡；顶部明确二选一，已购未装备时禁止无决策继续；提交后锁定全栏，权威拒绝可恢复输入 | `show_offer` `_build_signature_card` `_build_evolution_card` `_confirm_signature` `_confirm_evolution` `reject_decision` signals `signature_chosen` `evolution_chosen` `closed` |
| `survivor/evolution_tree_view.gd` | `EvolutionTreeView extends Control` | [生存] 机体进化树视图（皇牌空战式自下而上；只布局本局历史链与当前机可达后继，永久不可达旁支不显示；层间线槽正交折线/同来源分支总线，四状态批绘；亮=可进化/灰=门槛未到/金=爬线历史/**剪影？？？=尚未拥有的可达后继**；路线 color code + 门槛 pip + 当前机醒目金色双层框 + 顶部三轴图例，spec aircraft-evolution-tree §4.9.4） | `setup(...)` `_relevant_nodes(all_nodes, current, history)` `set_current(current, history)` `_build_edge_routes` `_orthogonal_path` `_draw_edge_batch` `can_evolve(id)` `_is_revealed(id)` `_gate_gap_text(id)` `_pip_slots(gates)`（测试 evo_detail §F/G/H）`CAT_AXES` signal `node_selected(id)` `interactive` |
| `survivor/evolution_detail_panel.gd` | `EvolutionDetailPanel extends VBoxContainer` | [生存] 停靠机体详情卡四段：抬头 + 该节点专属槽（43 项已实现效果 / 7 项延期占位）+ 8 项机体特性/相对当前机增减 + 进化等级与全部 gates | `show_node(node_id, current_id, team_level, axis_points)` `_build_signature` `_effective_stats`(static) `_can_evolve`(static) `_gate_rows` const `STAT_ROWS` |
| `survivor/aircraft_codex.gd` | `AircraftCodex extends RefCounted` | [生存/局外] 机体图鉴（user://aircraft_codex.cfg，跨局持久）：拥有过=永久揭示树迷雾；低频写盘 | `is_discovered(id)` `mark_discovered(id)` |
| `tests/test_skills_720.gd` | `extends RefCounted` | [测试] 技能 720 专项 bench `skills720`；覆盖归属/轴进度/终端来源/R 动作等契约，并以非 A-10 测试机验收今日 13 张/19 层同机满层共存、忠诚僚机实际生成及复合击杀/阵亡触发；狂化动态身份及技能开关下失效玩家引用的安全返回/清理 | `run` `_test_today_full_build_loadout` `_test_t5_mechanisms` `_test_berserk_virus` `_test_berserk_virus_reference_lifecycle` |
| `tests/test_sig_skills.gd` | `extends RefCounted` | [测试] 机体签名技能无头验收：43 项已实现映射与 7 项保留占位严格分流；覆盖随机池/等级入口隔离/机场 signal 权威入口/前置/milestone/apply/EA-18G 共锁接线/F/A-XX 机炮击杀门与 CD | `run` `_test_offer_rules` `_test_mig31_forward_gate` `_test_new_signatures` |
| `tests/test_skill_audit.gd` | `extends RefCounted` | [测试] 全 158 条技能审计 bench `skill_audit`：直接型逐条 apply 快照、事件型消费点、一次性 dispatch、三语玩家文案、状态构筑公式与 F4/F6 Debug 数据源覆盖 | `run` `_audit_one` `_test_regression_contracts` `_test_debug_surface_coverage` |
| `tests/test_status_notes.gd` | `extends RefCounted` | [测试] 状态词条映射/i18n + 基础三卡/机体适配第四卡技能介质 UI 50 项回归；覆盖四槽条件显隐、来源条、稀有度介质、入场防误触、独立旁注层、瞬时压缩退场与危险红；bench `status_notes` | `run` `_test_mapping` `_test_i18n_coverage` `_test_ui_binding` |
| `tests/upgrade_media_visual_qa_runner.gd` | `extends Node2D` | [测试/Visual] 1920×1080 真实渲染使用正式底部经验/三轴控件，采集基础三卡、机体适配第四卡来源条、侧边词条旁注、读写扫描与卡带直接压入样图；验证四卡无挤压、旁注不与卡面相交及压入时保持不透明；bench `upgrade_media_visual` | `_ready` `_build_progression_target` `_settle` `_note_popup_clear_of_cards` `_capture` `_draw` |
| `tests/evolution_decision_visual_qa_runner.gd` | `extends Node2D` | [测试/Visual] 1920×1080 真实机场规划站采图；以已进化到 F-16 的空图鉴验证历史链 + 可达 `？？？` 保留、F-15/F-14 永久不可达旁支隐藏；覆盖许可有效时洋红留机卡可用且禁止绕过、许可未购时黄色锁定状态与继续出击，并验证三栏尺寸、翻译命中和视口内完整布局；bench `evolution_decision_visual` | `_ready` `_layout_ok` `_tree_scope_ok` `_settle` `_capture` `_draw` |
| `tests/hit_flash_visual_qa_runner.gd` | `extends Node2D` | [测试/Visual] 真实 MissileManager Canvas 语法回归：顶部只在 Tu-160 大型机轮廓展示四条五点结构波的 0.10/0.28/0.50s 三段；中部同屏展示 F-14 机鼻、尾部引擎、左右翼和中心命中后的偏航/侧翻差异；底部展示小型机坠毁 10/40/70/100% 的旋转、缩小、渐隐与终点单方框 | `_ready`；bench `hit_flash_visual ... Shadow Visual` |
| `tests/test_hard_brake.gd` | `extends RefCounted` | [测试] 急刹与拖拽转向 bench `hard_brake`：直线软地板/减速差异、12px/110px 输入映射、捕获鼠标后的相对位移累计/反向归中、左右微调、实飞预测同源、持续整圈、满舵载荷失速、失速/恢复禁用、机场规划站释放鼠标及输入原子清理 | `run` `_make` `_check` |
| `tests/test_turn_physics.gd` | `extends RefCounted` | [测试] 固定翼 PD 转弯 bench `turn_physics`：4 机型 × 大角转弯 / 连续追击 / 3、6 帧 AI 分频 lead / 爬升跟随 / 近点环绕；跨零大坡反转与 0.2s 内 ≥0.75G 峰谷进入自动失败门，慢滚入 / 滚出只作诊断 | `run` `_run_all` `_run_pursuit` `_run_pursuit_aitick` `_report` `_count_sign_reversals` |
| `tests/test_brake_steering_overlay.gd` | `extends RefCounted` | [测试] 急刹虚拟摇杆 bench `brake_steering_ui`：按下/松开生命周期、真实舵量映射、屏幕边缘夹紧、失速锁定、速度/剩余与最大弹药/无限弹药/射程发布及当前操控机急刹机炮射界显示门 | `run` `_test_lifecycle_and_mapping` `_test_edge_clamp` `_test_stall_lock` `_test_flight_data_and_gun_reference` |
| `tests/test_weapon_behavior.gd` | `extends RefCounted` | [测试] 武器行为 bench `weapon`：在飞导弹计伤、急转发射、连锁弹头直穿快照/命中去重、急刹拖拽中普通自动机炮/双翼机炮吊舱/炮艇独立扫描不停火、炮艇对地扫描/侧射炮口/整梭目标锁存、AI 僚机绕过战术目标锁池、四机编队对地独立齐射、炮艇与 CIWS 射界隔离、机炮本体守卫、高速横穿发射前解与出弹后 crank 连续性 | `run` `_test_chain_warhead_snapshot` `_test_gunship_scans_ground_units` `_test_gunship_squad_ground_volley` `_test_prelaunch_tracks_launch_solution` `_test_crank_no_side_flip` |
| `tests/test_player_params.gd` | `extends RefCounted` | [测试] 50 机玩家 params 验收（bench `player_params`）：六层雷达走廊、155 条进化边雷达/机炮/导弹平滑、机炮弹量五档与 180 地板、进化装满、9000 px 最终上限、敌武器成长、特殊武器/热诱弹与资源隔离 | `run` `_test_gun_ammo_profiles` `_test_evolution_edge_smoothing` `_test_effective_radar_cap` `_test_enemy_weapon_scaling` `_test_flare_tiers` `_test_shared_resource_isolation` |
| `tests/test_attribute_gates.gd` | `extends RefCounted` | [测试] 三轴收入/里程碑/卡片/具体轴门；枚举总点数≤8 的全部分配验证 50 节点、155 边、永久不可达边=0；Boss Debug 验证 7 架 T4、节点等级、正式卡池、gates 与 6 点里程碑 | `run` `_test_evolution_gates` `_test_boss_debug_reference_builds`；bench `attr_gates` |
| `tests/test_evolution_detail.gd` | `extends RefCounted` | [测试] 50 节点详情/UI/pip/当前位置与 155 条正交树边验收；保留签名占位可见但不阻断机场继续 | `run` `_test_gate_pips` `_test_tree_routes_and_current_marker`；bench `evo_detail` |
| `tests/test_evolution_growth_benchmark.gd` | `EvolutionGrowthBenchmark extends RefCounted` | [测试] 14 分钟正常规则成长单局：4 条固定进化路线、1/3/5/9 机、固定种子、每 60 秒结算、有效战斗覆盖、KIA 剔除、XP/击杀/首次进化/具体缺轴 JSON | `configure_from_environment` `setup` `handle_level_up` `tick` `finish`；bench `evolution_growth` |
| `tools/aggregate_evolution_growth.py` | Python CLI | [审计] 聚合有效成长样本，输出 runs/group CSV、P50/P75/P90、Tier 到达、缺轴、经验补偿建议与 Markdown/JSON 结论 | `main` `group_row` `build_conclusions` `render_markdown` |
| `tools/audit_evolution_growth.py` | Python CLI | [审计] 读取正式 tree/profile/params/签名表，生成 43 机三轴静态成长 CSV/JSON/Markdown；检查斗士线、主导弹/flare 精确分档及直接跨 Tier 边无倒退 | `main` `load_aircraft` `tier_summary` `ordnance_violations` `render_report` |
| `tools/analysis/agl_quantitative_model.py`（仓库根） | Python CLI | [规划/审计] 从当前 spec、技能表、进化树与集中配置复算玩家上限、敌压、首次体验窗口和内容缺口；可检查基线或重写审计报告，模型输出用于校准而不是运行时数值权威 | `main` `render_report` `validate_sources` `--check` `--write-report` |
| `tools/trace_orthographic_outline.py` / `tools/normalize_aircraft_reference.py` | Python CLI | [资产提取] 从已核实的闭合正投影线稿、alpha 或实色层直接提取轮廓，再统一为 128×128 白色 alpha PNG；不生成或补画飞机几何 | `flood_outside` `large_components` `main` |
| `tools/audit_aircraft_silhouettes.py` | Python CLI | [审计] 检查 reviewed 清单与运行时目录一致、当前 44 张 PNG 的尺寸/模式/透明角/白 RGB/覆盖率/对称性/alpha 哈希，并验证 73 个 PNG 别名与 24 个原创旧绘制别名恰好覆盖当前 AircraftParams | `aircraft_param_files` `main` |
| `scripts/tools/audit_aircraft_volume_models.py` | Python CLI | [审计] 从实际 AircraftParams、二维别名与原创/特种映射重算规范三维 key；核对逐型来源、可编辑源、LOD0/LOD1/LOD2 目录与预算、四视图 QA、AWACS 身份和正式接入状态，输出玩家/敌人/友军/BOSS 覆盖矩阵 | `dictionary_pairs` `supported_keys` `role_for` `main` |
| `tools/raster_basemap_preview.py` | Python CLI/共享模块 | [地图资产] 东京湾、沙漠、海洋正式 PNG/profile 的同位预览、边缘/色彩诊断与候选参数 SSOT；输出只写 `tmp/raster_basemap_preview/` | `MAPS` `render_current` `render_candidate` `main` |
| `tools/remove_admin_boundaries.py` | Python CLI/共享模块 | [地图资产] 以未调色 CARTO 源图的 `#e1c5c7` 边界核心生成窄带 mask，确定性修补东京湾/沙漠/海洋的非实体行政边界；默认只写 `tmp/`，`--write-runtime` 才原子替换母图 | `detect_admin_boundary` `inpaint_narrow` `clean_admin_boundaries` `save_png_atomic` `main` |
| `tools/build_lossless_basemap_pyramid.py` | Python CLI | [地图资产] 从三张正式母版确定性生成 Strategic/Operational/Detail raw-RGB lossless WebP；逐瓦片复解码、gutter 接缝、父子均值、SHA-256 与磁盘门，默认输出 `tmp/`；`--operational-only` / `--strategic-only` 可复制已验证基线并仅重建一档，Strategic 默认 1520 并保留 1024～1536 消融档 | `build_map` `build_operational_only` `build_strategic_only` `cut_processed_level` `seam_metrics` `save_lossless` `main` |
| `tools/audit_raster_survivor_composites.py` | Python CLI | [地图资产/Visual QA] 消费东京湾、沙漠、海洋 PNG/streamed Visual bench 的六张完整 Survivor viewport；对相同天气种子下的玩家、HUD、天气与地图共同合成执行亮度、1.5 px 低通 RGB、8×8 平坦区逐通道色准和低通结构相关可失败门，默认只写 `tmp/map_visual_qa/` | `audit` `_pair_metrics` `_flat_cell_delta` `main` |
| `tests/test_evolution_tree.gd` | 旧 SceneTree 脚本（未接 BenchRunner） | [测试] 进化树完整性冒烟；Agent 日常回归用 wrapper 跑 `evo_detail` + `attr_gates`，不直接启 Godot | `_initialize` |
| `ugc/contour_baker.gd` | `ContourBaker extends RefCounted` | [UGC] 涂格位图→平滑多边形烘焙（spec map-editor §3.1）：边界追踪(含孔洞/鞍点右转)→DP 抽稀(0.8×格)→Taubin 无收缩×3对→Chaikin×3(v6 平滑重做)；逆向栅格化供官方图转换 | `bake_layer(cells,w,h,cell_size,origin)` `rasterize_polygons(…,union)` `taubin_closed` `chaikin_closed` `simplify_closed` |
| `ugc/map_document.gd` | `MapDocument extends RefCounted` | [UGC] 地图文档数据层（spec map-editor §2.3/§2.4）：schema 读写/围栏钳制/style 调色板默认=官方现值/可选 basemap PNG+metadata 路径/地图专属 `railways[{id,points}]` 移动路线 SSOT/layer_dirty 懒烘焙/撤销栈 50/过新 schema 拒载 | `save_to(path)` `load_from(path)` `from_json_dict` `push_undo` `undo` `mark_dirty_and_rebake(layer)` |
| `ugc/official_map_converter.gd` | `OfficialMapConverter extends RefCounted` | [UGC] 官方图→MapDocument 一键转换（spec map-editor §3.4）：矢量 JSON 直通 + 陆地/城区并集消重叠（偶奇自洽）+ 栅格化反推 editor_cells + 战区/出生点 JSON 化 | `build()` |
| `tests/test_map_editor_core.gd` | SceneTree 脚本 | [测试] 地图编辑器阶段1核心冒烟（--script 运行）：Chaikin对拍/烘焙几何/孔洞/栅格化往返/存读闭环/围栏/撤销 7 组 | `_initialize` |
| `ugc/ugc_loader.gd` | `UgcLoader extends RefCounted` | [UGC] 地图运行时注入器（spec map-editor §4）：地理→MapGeographyData.inject_ugc+ugc_mode 偶奇陆判 / 建筑→BuildingRenderer.inject_ugc_districts / 云→WeatherSystem.apply_ugc_config；**退出 UGC 局必调 clear() 防静态残留**；战区/spawn/style 待接线 | `load_map(path)` `apply_geography(doc)` `apply_buildings(doc)` `apply_to_weather(w, doc)` `clear()` |
| `tests/test_official_map_converter.gd` | SceneTree 脚本 | [测试] 官方图转换冒烟（--script 运行）：陆判 22500 格心逐点等价/涂格反推/直通保真/存读闭环/围栏静默 5 组 | `_initialize` |
| `tests/test_ugc_loader.gd` | SceneTree 脚本 | [测试] UgcLoader 注入冒烟（--script 运行）：地理注入偶奇等价/注入量/建筑预热与官方管线零差异/云 mask 三态/clear 还原 5 组 | `_initialize` |
| `ugc/map_editor_scene.gd` | `MapEditorScene extends Node2D` | [UGC] 地图编辑器主场景（scenes/map_editor.tscn，主菜单"地图工坊"入口）：三区 UI + 工具状态机（笔刷/橡皮/矩形/圆形/三角形 v6）+ PNG 垫图导入与亮度阈值提取（v6）+ 文件生命周期 + 试飞（meta ugc_map_path → survivor_mode）；光标/笔画格子/图形预览在本节点轻量 _draw | `_unhandled_input` `_begin_stroke` `_stamp` `_begin_shape` `_commit_shape` `_do_import_image` `_do_extract` `_save` `_test_fly` `_do_autosave` |
| `ugc/map_editor_canvas.gd` | `MapEditorCanvas extends Node2D` | [UGC] 编辑器静态画布：海色/涂格图层多边形（调色板取色）/机场/道路/海岸线/建筑/战区/边界；只在数据变化时 notify_changed 重绘（守则第 1 条） | `notify_changed()` `layer_color(layer)` `_draw` |
| `tests/test_map_editor_scene_smoke.gd` | SceneTree 脚本 | [测试] 编辑器场景冒烟（--script 运行）：tscn 实例化跑 5 帧不炸/程序化涂格烘焙/存读 | `_initialize` `_process` |
| `tests/test_map_vector_preview.gd` | `extends RefCounted` | [测试/冻结研究] V44 候选资源、packet cache、四档水拓扑与历史预算回归；不构成正式 PNG 替换毕业证据。Operational `terrain_context` 三类水面命中 0、669 栋高层 29,688 三角且全 zoom alpha 1；首次预热 ≤1.60s、Operational ≤26 draw calls / ≤1.30M 三角 | `run` `_is_warm_paper` `_rgb_distance` `_test_loading_scene_and_stable_zoom`，bench `map_vector_preview` |
| `survivor/survivor_select.gd` | 生存模式机型选择界面 | [生存/UI] 共享 CRT 白色终端页；左侧固定全息预览复用正式机体轮廓，右侧三列可滚动八卡——既有 F-15/F-14/A-6E/Mirage III 与四架局外采购 T0；悬停/键盘焦点更新预览，锁定卡不加载档案或泄露轮廓；Boss Debug 分流到可滚动 T4 参考编队 | `PLAYABLE_LIST` `_effective_list` `_boss_debug_reference_list` `_unlock_hint_for` `_build_aircraft_card` `_show_aircraft_preview` `_on_aircraft_selected` `_on_back_from_select` |
| `survivor/aircraft_hologram_preview.gd` | `AircraftHologramPreview extends Control` | [生存/UI] 选机页事件驱动全息顶视投影：正式 PNG 轮廓、静态网格/扫描线/准星与双重残影；无逐帧脚本 tick，锁定态显示加密占位 | `show_profile` `show_locked` `has_model_texture` `displayed_airframe` `_draw` |
| `survivor/survivor_map_select.gd` | 生存模式地图选择界面 | [生存/UI] 共享 CRT 白色终端页；五列地图卡消费静态线稿缩略图，东京湾/沙漠铁路/海洋群岛可选、两格锁定；写 map id / MapDocument path / `map_preview_only`；ESC→主菜单，B→Boss Debug | `MAP_LIST` `_build_ui` `_build_map_card` `_on_map_selected` `_on_back_pressed` |
| `survivor/boss_debug_select.gd` | Boss Debug — BOSS 选择界面 | [生存/Debug] BOSS 卡片与 BossRegistry 同步；沙漠列车、陆地航母与 The Crucible 自动装载正式沙漠地图；Black Star 另提供专项直达场景，写 `boss_debug_scenario` meta 并随 F8 重开保留 | `BOSS_LIST` `_build_boss_card` `_on_boss_selected` |
| `survivor/boss_debug_builds.gd` | `BossDebugBuilds extends RefCounted` | [生存/Debug] T4 参考态权威：从正式进化树动态取次顶档节点，按 `min_level` 收入先满足 gates、剩余点投机种主轴；从正式三星战区武器权重池加权无放回抽 2~3 件并保持机尾位互斥；再按 5 主题从对应轴普通卡池生成 5~6 张技能，尊重实际硬件 / 机体身份 / max_stacks / requires / excludes / requires_skill，排除 evolved 与机场专属技能 | `REFERENCE_TIER` `REFERENCE_WEAPON_DIFFICULTY` `reference_nodes` `target_axis_points` `roll_weapon_loadout` `is_weapon_mounted` `roll_reference_build` `roll_build` `roll_for_theme_name` |
| `survivor/afterburner_charge.gd` | `AfterburnerCharge extends RefCounted` | [生存] 加力模式唯一状态机（spec afterburner-mode，**充能制/电池模型**）：`Phase {CHARGING, ACTIVE}`、30s 满能量 / 激活中实时耗能 / 有能量即启动 / 耗尽自动关闭 / 提前关闭保留余量 / 击杀 +0.8s；leader/member 只保留 WeakRef 激活快照，所有退出走对称清理；世界飞行指令统一 `cancel_for_manual_command`，取消不写速度或物理积分态；720 账本、暴风雨 I/II 与 CLIMB 仍在同一资源模块结算 | `update(delta, rate_mult, storm_ii_active, bonus_recharge_per_sec)` `on_kill_charge` `toggle(leader)` `activate` `deactivate` `cancel_for_manual_command` `is_active` `is_available` `ratio` `remaining_seconds` |
| `survivor/player_instrument_panel.gd` | `PlayerInstrumentPanel extends Control` | [生存/UI] 固定高 `24u`、右锚玩家 HUD：SPD/G 整数/FLR 当前值共用固定数字格；AUTOPILOT 以动态空框板吸收手动 FLR 的 R 键；默认武器区含两条有框 `0.5u` 装饰行、两个 `2u` 槽、`0.5q` 辅助空框与竖向装填条；热诱弹 CD 上升沿且加力可用时，复用键帽反色节拍闪烁 E 最多 5s，O(1) 且仅换相重绘 | `update_display(ac, charge)` `_configure_layout` `afterburner_flare_hint_on` `key_flash_on` `_sync_afterburner_flare_hint` `spd_digit_rect` `g_integer_digit_rect` `flare_current_digit_rect` `formatted_speed_digits` `weapon_count_rect` `weapon_aux_empty_rect` `weapon_reload_progress_rect` `weapon_name_rect` `active_control_empty_rect` `grid_regions` `_draw_flight_data` `_draw_weapons` |
| `survivor/wingman_instrument_panel.gd` | `WingmanInstrumentPanel extends Control` | [生存/UI] 玩家 HUD 上方可增减的僚机 HUD 信息行；每行独立消费伤害 token，实际受伤后仅对应 HP 红闪，连续命中续窗；按存活数调整高度并复用相邻 1px 边界 | `update_display(rows)` `_sync_damage_rows` `damage_flash_active_for_slot` `grid_regions_for_row` `grid_regions` `_apply_row_count` `_draw_row` |
| `survivor/damage_vignette.gd` | `DamageVignette extends Control` | [生存/UI] 屏幕外圈状态反馈：红受伤 > 黄锁定/FEAR/JAM/SLOW > 绿治疗；按短边 1.5% 绘制，低于 ThreatOverlay；只存玩家实例 ID 并在跨帧读取时净化，只在颜色或厚度变化时重绘 | `set_player` `_live_player` `advance_alpha` `feedback_color` `band_thickness` `_process` `_draw` |
| `ui/terminal_text.gd` | `TerminalText extends Control` | [生存 UI] “通用字号规范”的唯一实现：无内边距，支持显式左/中/右对齐、最大显示字符串、固定 1u Silkscreen 15px、真实字形撑高，以及固定字号后按整数步长扩宽；TextServer 塑形后按最终 glyph 轮廓校正基线，重复内容命中 2048 项有界缓存；排版结果与宽度另有有界缓存 | `FontFace` `SizeRule` `MAX_INK_BOUNDS_CACHE_ENTRIES` `layout_text` `horizontal_alignment` `_draw` `resolve_font_layout` `cached_string_width` `font_size_for_ink_height` `expanded_width_for_fixed_text` `measure_ink_bounds` |
| `ui/terminal_grid_overlay.gd` | `TerminalGridOverlay extends Control` | [生存 UI] 终端网格统一描边层：所有面板只绘制底色，父子/相邻 u 与 q 的边界在同一坐标系复用 1px；反色只覆盖原线坐标 | `regions` `override_regions` `_draw` |
| `ui/terminal_page_shell.gd` | `TerminalPageShell extends Control` | [共享/UI] 局外整页共用 CRT 物理壳、玻璃后处理与 `23u × 30u` 安全内容区；静态构建，无常驻 tick | `CONTENT_SIZE` `SAFE_MARGIN` `content` `_build_shell` |
| `ui/terminal_ui_style.gd` | `TerminalUiStyle extends RefCounted` | [共享/UI] 局外页面/小弹层白色终端样式唯一入口：黑底 1px 线框、Silkscreen/Chakra 字体、反色按钮/页签、统一页头/正文/页脚 | `accent` `panel_style` `apply_panel` `apply_label` `apply_terminal_label` `apply_button` `apply_tab_container` `build_page` `build_footer_hint` `build_footer_button` |
| `ui/terminal_map_preview.gd` | `TerminalMapPreview extends Control` | [共享/UI] 选图卡静态线稿缩略图：海岸、沙漠铁路、海岛与锁定排线；仅初次绘制，不启用 `_process`/持续重绘 | `_draw` `_draw_coast` `_draw_desert` `_draw_islands` `_draw_locked` |
| `ui/hud_preferences.gd` | `HudPreferences extends RefCounted` | [共享/UI] `user://hud.cfg` 静态偏好服务；默认 KT 与白色主调 `#E8F2E8`，保存 KT/KM/H 和 HUD 强调色，不新增 AutoLoad | `speed_unit` `uses_knots` `cycle_speed_unit` `set_speed_unit` `hud_color` `set_hud_color` `speed_value` |
| `ui/hud_color_settings_panel.gd` | `HudColorSettingsPanel extends CanvasLayer` | [主菜单/UI] 白色终端 HUD 色盘；绿/青/琥珀/白四预设 + 不含 alpha 的 ColorPicker；保存/取消 | `open` `close_panel` `_build_ui` `_add_preset` `_on_save` |
| `ui/hud_first_reveal_sequencer.gd` | `HudFirstRevealSequencer extends RefCounted` | [生存/UI] 固定登记表的本局首次显现状态机；按屏幕 y/x 排序，框板每 `0.02s` 错峰并发启动，各自在 `0.50s` 内两闪后常亮；动态框板中途隐藏不消费首次机会 | `register_panel` `register_callback_panel` `set_panel_available` `set_panel_sort_position` `update` `active_panel_ids` `panel_completed` |
| `ui/hud_board_visibility.gd` + `resources/shaders/hud_board_visibility.gdshader` | `HudBoardVisibility extends RefCounted` | [生存/UI] 在复合绘制 Control 内按逻辑 `Rect2` 切换源框板；新登记区域默认关闭并以 `1px` 外扩覆盖描边外溢，全部常亮时卸下临时材质 | `sync_regions` `set_reveal_alpha` `board_is_visible` `board_screen_position` |
| `ui/main_menu_crt_shell.gd` | `MainMenuCrtShell extends Control` | [主菜单/UI] 静态 Y2K 军用显示器机壳，不启用逐帧处理 | `SHELL_SIZE` `SCREEN_RECT` `_draw` |
| `ui/main_menu_crt_effect.gd` + `resources/shaders/main_menu_crt.gdshader` | `MainMenuCrtEffect extends ColorRect` | [主菜单/UI] 仅覆盖 CRT 内屏的屏幕采样后处理 | `_notification` |
| `ui/main_menu_scope_display.gd` | `MainMenuScopeDisplay extends Control` | [主菜单/UI] 右侧静态航路/雷达示意，仅在强调色变化时重绘 | `accent` `_draw` |
| `main_menu.gd` | 主菜单 | [主菜单] `23u × 30u` CRT 安全显示区；顶部识别、左侧五行模式档案、右侧航路/设置与底部系统记录；焦点反色并跟随 HUD 强调色；`_ready` 幂等淡入 `main_menu` 循环曲，正式战局平滑接管 | `_ready` `_build_terminal_header` `_build_system_panel` `_add_mode_button` `_refresh_mode_button_visual` `_refresh_terminal_palette` `_build_audio_button` `_refresh_hud_settings_buttons` |
| `debug_panel.gd` | 调试面板 | [沙盒] 状态文本/飞行员信息/生成按钮 | `_get_strategy_text:266` `_get_combat_strategy:303` `_get_pilot_info:318` |
| `event_logger.gd` | EventLogger (AutoLoad) | [共享] 全局 300s 事件环形日志 + 本局战报累计；单调序号 Dictionary 使追加/过期删除均为 O(1)，避免长局 `Array.pop_front()` 搬移尖峰；逐机 `AC_TICK` 仍为 10Hz 但由 Aircraft 按实例相位摊开 | `log_event` `dump_to_file` `tally(subject,key,n)` `reset_stats` `format_stats_summary`（F9 末尾追加 KILL/脱靶/命中率汇总）；**signal `kill_recorded`** → survivor_hud 战况栏（spec combat-feed）+ 无线电击坠/弹射/减员台词；**signal `evasion_started(callsign, team)`** → 无线电 break 呼叫（Aircraft.set_evasion_mode 上升沿 emit）；**signal `wingman_joined(callsign, team)`** → 无线电归队呼叫（SquadFactory.register_wingman emit，订阅方按开局时间过滤） |
| `callsign_db.gd` | CallsignDB (`class_name` 静态服务，非 AutoLoad) | [共享] 呼号分配、保留、回收与重置 | `allocate` / `recycle` / `reserve_permanent` / `reset` |
| `locale_manager.gd` | LocaleManager (AutoLoad) | [共享] i18n 控制：启动读 user://locale.cfg（zh/en/ja），主菜单按钮切换+持久化+重载场景 | `_ready` `set_locale_persistent(code)` `get_current_locale()` `trm(key)` — 详见 [docs/reference/i18n.md](i18n.md) |
| `i18n_catalog.gd` | `RefCounted` 静态服务 | [构建/测试] 五份本地化 CSV 清单与统一审计：四列表头、跨表 key 唯一、分表集合漂移；运行时不参与翻译查询 | `csv_paths` `read_source` `audit` `expected_translation_paths` |
| `audio/audio_manager.gd` | AudioManager (AutoLoad) | [共享] 音频总控：4 条 Bus（Music/SFX/UI/Radio）程序化创建，SFX 挂远距无线电效果链；32 SFX 池，屏幕外静音；双播放器 crossfade；playlist 轮播、临时插入曲断点恢复；one-shot 自然结束信号；缺资源可查询；菜单 muffle；玩家引擎环境音 | signal `music_track_finished`；`play_music` `stop_music` `crossfade_music` `has_music` `play_music_playlist` `crossfade_music_playlist` `crossfade_music_interrupt` `resume_interrupted_music` `discard_interrupted_music` `set_music_muffled` `play_sfx_2d` `play_ui` `set_bus_volume_linear` `start_player_engine` `save_settings` `prefetch_music` `prefetch_sfx`（后台线程预载） `is_stream_prefetch_idle` `_resident_stream`（取用过的音乐/非常驻 SFX 常驻持有） — 详见 [docs/systems/audio.md](../systems/audio.md) |
| `util/perf_buckets.gd` | PerfBuckets (AutoLoad) | [共享/Debug] 1 秒滚动性能桶：耗时、调用数与瞬时值快照，供 HUD / F9 当前态读取；F3 可见期间保留最近 120 渲染帧并启用绘制/物理/HUD/系统细桶，按 ms/帧列出前十热点；Visual bench 正确配对上一帧 delta/工作量，最多保留 8 个慢帧的前 120 / 后 30 帧上下文、p95/p99/max 与保守归因，并另算预热后全程根桶均值、活跃帧覆盖与 known/frame 比例，避免用最后 1 秒代表整段；默认每 4 帧采细桶并支持 full/off A/B；显式 `AGL_BENCH_EXTENDED_CPU_TRACE=1` 开启默认关闭的扩展 CPU 诊断，扣除已记录父区间及共享日志/音效/无线电，仅净值加入新增根，负归因记录 invalid；`_process` 起点按引擎物理帧差结算本渲染帧物理步数，供可延后主线程重活择帧 | `tick` `count` `set_value` `physics_steps_this_frame` `frame_has_physics_step` `configure_runtime_panel` `detail_capture_enabled` `begin_render_frame` `runtime_frame_stats` `runtime_engine_snapshot` `ranked_runtime_hotspots` `format_detailed_hud_lines` `configure_frame_trace` `mark_physics_tick` `mark_frame_event` `_update_trace_context` `_trace_frame_percentiles` `_trace_spike_class` `format_full_dump` `format_frame_trace_dump` `finish_extended_cpu` `extended_cpu_root_usec` |
| `missile.gd` / `aa_gun_unit.gd` / `sam_unit.gd` / `airburst_aa_unit.gd` / `radar_station.gd` / `survivor/bomber_mission.gd`（扩展 CPU 诊断） | 独立实体物理回调 | [诊断] 显式扩展开关下计量导弹飞行、AA/SAM/空爆高炮/雷达站与轰炸任务回调；保留原执行顺序与频率，共享事件从净值扣除；导弹实体回调与 MissileManager 碰撞桶分开 | `_physics_process` `_physics_process_missile_untraced` `_physics_process_aa_untraced` `_physics_process_sam_untraced` `_physics_process_airburst_untraced` `_physics_process_radar_station_untraced` `_physics_process_bomber_mission_untraced` |
| `survivor/survivor_mode.gd` / `trail_ribbon.gd`（扩展 CPU 诊断） | 系统与尾迹回调 | [诊断] Survivor 物理余量扣除 cache/radar/LOD/spawner 已计区间及区间外共享事件；预测准备属于 process 工作；尾迹 process 与既有 trail_draw 分开；不改变预测步数或尾迹采样 | `_process` `_physics_process` `_physics_process_survivor_untraced` `_extended_survivor_cover_root` `_process_trail_untraced` |
| `ui/world_unit_status_overlay.gd` / `rendering/aircraft_volume_overlay.gd` / `weather_system.gd` / `survivor/battlefield_atmosphere_experiment.gd`（扩展 CPU 诊断） | 状态栏与画布回调 | [诊断] 单独计量状态栏同步、面板/遮罩绘制、飞机 3D overlay 同步、天气及战区绘制的 CPU 工作；子函数 `function.trail_rebuild` / `function.predicted_path_draw` / `function.canvas_triangle_submit` 仅定位，不重复计入根总和，均不能当作 GPU 耗时 | `_process` `_draw` `_draw_weather_untraced` `_draw_atmosphere_untraced`；`trail_ribbon.gd` `_rebuild_cached_geometry` / `aircraft_renderer.gd` `draw_predicted_path` / `rendering/canvas_triangle_packet.gd` `submit_arrays` |
| `bench/bench_runner.gd` | BenchRunner (AutoLoad) | [测试] 解析 `--bench` / `--duration` 后统一静音 Master 总线（逻辑照常执行、不保存用户设置），注册无头断言、显式 BUILD 报告、Headless 生命周期场、Visual 测试场、图2/图3 MapDocument 探针与海洋 FINAL WAR 性能 A/B；飞机 LOD1/LOD2 四视图复用专属 runner，三维 C2 未实际提交 LOD1 与 LOD2 时 fail closed。FINAL WAR 自动注入 Black Star / F-47→T5 / 正式海图 meta。BUILD 在 AutoLoad `_ready` 后 deferred 一拍，允许挂载真实 SceneTree；`all` 同步断言全绿后强制切入 lifecycle gauntlet；外部只能经 `bench/run.cmd` / `bench/run.sh` 启动 | `UNIT_TESTS` `BUILD_TASKS` `HEADLESS_TEST_SCENES` `VISUAL_TEST_SCENES` `PREVIEW_BENCH_MAPS` `FINAL_WAR_BENCH_SCENARIOS` `_ready` `_run_build_task` `_swap_to_test_scene` `_swap_to_visual_test` `_run_unit_test` `bench_finish` |
| `diagnostics/frame_probe.gd` | FrameProbe（BenchRunner 子节点，默认不加载） | [诊断] 仅 `AGL_FRAME_PROBE=1` 时挂载：两个 ±1e9 优先级边界节点 + `physics_frame`/`process_frame`/`frame_pre_draw`/`frame_post_draw` 把每个引擎迭代拆成物理信号/物理脚本/物理后刷新/process 信号+延迟 `_draw`/process 脚本/渲染前刷新/渲染提交/其余互斥墙钟；同时记节点增删类别、对象/资源/显存、Canvas/3D 绘制、视口 GPU 时间、玩家呈现位置（DisplayPacing 物理插值显示态，行尾另列物理位置 `ply_px/ply_py`、插值分数 `interp_f` 与开关 `interp_on`；顿挫度量由 `tools/frame_probe_motion.py` 计算）与 PerfBuckets 本帧增量；退出时写 `bench/results/frame_probe_<tag>_<utc>.csv` 与 `.hitches.jsonl` | `_boundary` `edge_phys_begin` `edge_phys_end` `edge_proc_begin` `edge_proc_end` `_on_physics_frame` `_on_process_frame` `_on_pre_draw` `_on_post_draw` `_on_node_added` `_finish_frame` `_pb_frame_delta` `_sample_display` `dump` |
| `diagnostics/frame_probe_autoplay.gd` | FrameProbeAutoplay（FrameProbe 子节点） | [诊断] `AGL_FRAME_PROBE_AUTOPLAY=<秒>` 时按正式流程（主菜单 meta → building_preloader → survivor_mode）进入东京湾正式局，玩家机挂 AI、升级卡按真实点击路径选第 1 张、越界面板点取消、规划站直接起飞，到时导出 EventLogger 并 quit；`AGL_FRAME_PROBE_SHOTS=<n>` 时在 40/80/120 秒拉近到 2.5/1.2/0.5 并于 `frame_post_draw` 连续截取玩家周边呈现帧到 `tmp/map_visual_qa/frame_probe_shots/`（会造成停顿，勿与帧时统计混用）；经 `bench/run.cmd probe_play` 守护启动，正式局写 user:// 档案需调用方备份还原 | `_process` `_drive` `_drive_shots` `_on_shot_post_draw` `_finish_shot_burst` `_set_phase` |
| `bench/encounter_difficulty_probe.gd` | `EncounterDifficultyProbe extends Node` | [测试] 仅 `encounter_difficulty` 场景启用的 4Hz 固定 seed 难度探针；统计敌机存量、真正对玩家 ACTIVE 数、首次接敌、击杀、编队保留率与槽位误差，不进入正式局 | `setup` `_physics_process` `_sample` `finish` `_is_active_against_player` |
| `tests/lifecycle_gauntlet_runner.gd` | `extends Node` | [测试] 真实 SceneTree 终态门：护送目标/控制器/截击机、一体化巨炮、王牌 BGM 所有权及飞机统一坠毁释放，完成/失败/退役/威胁解除/重复 finish 仍越过下一帧或缓存 tick并安全收尾；逐项断言 missile/qmaam/rocket/aoe/gun 都保留真实模型、状态栏与尾迹，普通机终点仅一个方框且零结构波；终点爆炸帧机体不消失，覆盖 0.25s 不透明停留、渐隐中段、0.85s 后释放；另验证五受击分区、翼侧镜像、局部随机、无人机 small 与大型机按部位单结构波 | `_ready` `_run` `_test_bomber_cache_after_target_free` `_test_bomber_cache_after_controller_free` `_test_bomber_retire_with_freed_members` `_test_zone_completion_after_deferred_free` `_test_zone_failure_after_deferred_free` `_test_retired_ground_after_real_damage` `_test_super_cannon_destroy_after_deferred_free` `_test_ace_music_cleanup_after_deferred_free` `_test_all_damage_kinds_enter_aircraft_crash` `_test_unified_aircraft_breakup` `_test_hit_location_crash_response` `_test_large_aircraft_structural_breakup` |
| `tests/test_armored_train.gd` / `tests/desert_theater_smoke_runner.gd` | `extends RefCounted` / `extends Node` | [测试/沙漠] 正式底图铁路 provenance、十四节 236×84px / 3538px 总长 / 前后转向架 ≤0.01px 贴轨 / 活动车钩、尾段拒伤与逐节加速、功能退场、电磁炮 AOE、逃脱互斥终态；正式沙漠入口验证 3v3 战线、据点产兵、4 架 AH-64 与支线倒计时效果 | `run` / `_ready`；bench `armored_train` / `desert_theater` |
| `tests/test_land_carrier.gd` | `extends RefCounted` | [测试/沙漠] 列车/陆地航母身份分离、连续舰体尺寸、4 架真实驻机、甲板跟随误差、首波起飞、装甲伤害与 8 挂点 | `run`；bench `land_carrier` |
| `tests/runtime_error_probe.gd` | `extends Node` | [测试基础设施] 故意 `push_error`，并把已释放 Node 传入带类型参数，再让 Godot 退出 0；验证 wrapper 必须改判 86、保留完整调用栈并输出 `FREED_OBJECT_LIFECYCLE`；bench key `runtime_error_probe`，不进入 `all` | `_ready` `_accept_typed_node` |
| `tests/test_local_fix_integration.gd` | `extends RefCounted` | [测试] 小队交战持续、主雷达能力门、CD rate、云中状态联动、Sentinel 光环字段化、规避走位单 tick 与 ModifierTrace 恢复契约 | `run`；bench `local_fixes` |
| `tests/test_perf_frame_trace.gd` | `extends RefCounted` | [测试] 慢帧配对、120/30上下文、根桶均值；地图根/子桶不重算；单调时钟分段/缺样本/60FPS边界/最近秩分位数与输入不变；扩展诊断默认关闭、共享叶/已覆盖父区间扣除、负归因、跨帧根聚合及诊断子桶不重复计入 | `run` `_test_trace_reports_full_run_root_averages` `_test_map_root_and_context` `_test_render_partition` `_test_extended_cpu_trace` `_test_render_timeline`；bench `perf_trace` |
| `tests/test_bench_camera_patrol.gd` | `extends RefCounted` | [测试] 巡检镜头确定性/周期闭环、8 段南北左右覆盖、正式 zoom 边界、双向旋转与分段连续性 | `run`；bench `bench_camera_patrol` |
| `tests/test_predicted_path_incremental.gd` | `extends RefCounted` | [测试] 360 步玩家预测轨迹拆成 15 × 24 步后，完成时机、点列与能量曲线逐项等同单次预测；4:1 显示抽样不超过 91 点且保留终点 | `run`；bench `predicted_path` |
| `tests/test_offscreen_world_simulation.gd` | `extends RefCounted` | [测试] 未观察 AVAILABLE / 镜头观察 / SELECTED / 进入圆内 / 3★ / 终态激活矩阵；观察生成幂等、等级刷新保留身份；120 名未观察潜在成员保持 0 实体 | `run`；bench `offscreen_world` |
| `tests/zone_observation_visual.gd` | SurvivorMode 派生 | [测试] 正式镜头平移/旋转/缩放首帧地面目标、任务不误触发、回看身份与切换帧成本 | `_ready` `_process` `_capture_observation` `_observation_check`；bench `zone_observation_visual` |
| `tests/test_aircraft_component_cache.gd` | `extends RefCounted` | [测试] Cobra/Herbst 缓存命中、缺失、子节点顺序失效与重建 | `run`；bench `component_cache` |
| `tests/test_missile_visual_lod.gd` / `test_trail_ribbon_lod.gd` / `test_target_marker_lod.gd` | `extends RefCounted` | [测试] 战略视距导弹标签/弹体、尾迹点步进及玩家/BOSS/Sentinel 豁免、友军目标主线与舰船挂点批绘合同 | `run`；bench `missile_visual_lod` / `trail_ribbon_lod` / `target_marker_lod` |
| `tests/test_display_pacing.gd` | `extends RefCounted` | [测试] 物理插值白名单（根 OFF、Aircraft/Missile ON、尾迹与 Camera2D OFF）、显示态公式与回退、尾迹抵消父机显示态合成单位矩阵、镜头跟随显示态、`clear_trail` 传送重置、帧上限归一与还原；夹具挂已入树的 BenchRunner | `run`；bench `display_pacing` |
| `tests/test_missile_grid.gd` / `test_visual_bullet_soa.gd` | `extends RefCounted` | [测试] 导弹邻格候选、舰船恒扫、target_list 顺序；纯视觉弹 SoA 移动/寿命/总量与大型目标阵营预分桶 | `run`；bench `missile_grid` / `visual_bullet_soa` |
| `tests/test_rendering_packets.gd` | `extends RefCounted` | [测试] triangle packet 数组对齐/退化面门/提交签名，以及五个近轴航向的爆点面棱几何合同 | `run`；bench `rendering_packets` |
| `addons/runtime_tuner/runtime_tuner.gd` | RuntimeTuner (AutoLoad) | [Debug] 普通 F10 运行时参数面板；Shift+F10 明确放行给生存模式地图 A/B；只改当前实例，不写回 `.tres`，游戏代码不依赖它 | `FIELDS` `_input` `_toggle` `_refresh_target` `_read_field` `_write_field` |
| `audio/audio_settings_panel.gd` | `AudioSettingsPanel extends CanvasLayer` | [共享/UI] 白色终端音频设置弹层：4 条 Bus 滑条、静音、恢复默认与保存到 `user://audio.cfg` | `open` `close_panel` `_build_ui` `_build_slider_row` |
| `meta/archive_ui.gd` | `extends Node2D`（`scenes/archive.tscn`） | [局外/UI] 共享 CRT 白色终端资料库；作战手册/敌情档案双页签、连续表格条目与滚动阅读，业务数据仍来自 GameInfoCodex/EnemyCodex | `_build_ui` `_switch_to` `_rebuild_rows` `_build_enemy_rows` `_build_info_rows` `_on_back_pressed` |
| `meta/merit_ledger.gd` | MeritLedger (AutoLoad) | [共享] 局外货币"功勋"账本：局内 XP × 系数 → user://merit.cfg；MetaShop 从这里扣款 | `get_total` `settle_run(xp, mult)` `spend(amount)` `debug_add` `debug_reset`；常量 `SETTLE_RETREAT=1.0` `SETTLE_KIA=0.8` `SETTLE_VICTORY=1.0`；信号 `merit_changed(total, delta)` |
| `meta/merit_coin_icon.gd` | `MeritCoinIcon extends Control` | [共享] 功勋硬币徽章 — 纯 _draw 绘制（双圈 + 12 边缘齿 + 中心十字），无外部资源依赖 | `@export radius` `coin_color` |
| `meta/career_archive.gd` | CareerArchive (AutoLoad) | [共享/局外] 玩家生涯档案（user://career.cfg，spec career-archive）：分机型击坠/BOSS 接战·击败/通关等；`build_boss_history` 同时输出轮换布尔表与逐 BOSS 完整 `defeat_counts`，供通关强化层在 spawn 前读取；bench/boss_debug 不入档 | `record_*` 系列 `build_boss_history()` `is_achievement_unlocked(id)` `get_air_kill_table()` `flush` `debug_reset`；信号 `achievement_unlocked(id)` |
| `meta/enemy_codex.gd` | `EnemyCodex` | [局外] 敌人图鉴注册表 + 计数路由 + 解锁判定；BOSS 段与 Registry 四项双向对齐并含 Black Star；Debug build 可在本次运行全解锁但不改生涯战绩 | `entries_of` `defeat_count` `encounter_count` `is_unlocked` `debug_set_unlock_all` `progress` |
| `tests/test_career_archive.gd` | `extends RefCounted` | [测试] 生涯档案无头单测 62 断言（含四 BOSS 轮换 / history、图鉴 Debug、五表 1423 key 唯一性和 15 份翻译资源登记），bench key `career_archive` | `run` `_test_rotation_candidates` `_test_codex_alignment` `_test_codex_debug_unlock` |
| `tests/test_zone_rewards.gd` | `extends RefCounted` | [测试] 战区奖励 47 项：七件武器与三档权重、六项次世代且无独立穿透弹头、狂化病毒实验级普通池、重型机炮保留、开局类别保底、整局去重、航母第 4 次 pity、起始机型偏置与门控 | `run` `_test_nextgen_replacement` `_test_achievement_reward_gate` `_test_airfield_zones` |
| `tests/test_spawn_pool.gd` | `extends RefCounted` | [测试] 57 型敌机路径覆盖（43 常规池 + 14 事件/BOSS/王牌专用）、常规池数学可达性与五响应截面 3 万次防重复产出率、高度/参数走廊/ADBS/Snowblind/F-22/Sentinel 回归；bench key `spawn_pool` | `run` `_test_regular_enemy_registry` `_test_enemy_type_route_coverage` `_test_regular_pool_reachability_and_rates` `_test_adbs_escort_pool` `_test_sentinel_escort_cohesion` |
| `tests/snowblind_layer_visual_qa_runner.gd` | `extends Node2D` | [Visual QA] 按正式局“玩家/友军先生成、Snowblind 后生成”顺序组合真实 AircraftRenderer 与实体雪幕 shader；输出实体态、破幕 0.40s、复隐 0.40s 三帧，对 0.80s 双向采样做单调/端点断言，并验证中途反向无跳值；bench key `snowblind_layer_visual` | `_ready` `_add_map_probes` `_add_overlay` `_concealment` `_save_frame` `_is_monotonic` |
| `tests/test_deadair.gd` | `extends RefCounted` | [测试] DEADAIR 20 项规则与真实消费路径：8s/2s 阈值、宽限衰减、PLAYER/ALLY/地面/海军阵营口径、来源退役同拍移除自有 JAM、导弹永久失导不回滚、支援场互斥、敌版审计与自动测试静音；bench key `deadair` | `run` `_test_runtime_jam_path` `_test_support_field_mutual_exclusion` `_test_tier3_priority_replacement` |
| `tests/test_tier3_zone_threats.gd` | `extends RefCounted` | [测试] 3★ 战区 32 项特殊任务契约：全局唯一名额与机场同槽、F6 原子 profile 预设/唯一槽转移、地图/profile 文案共享缓存及安全降级重裁、AURORA LANCE 固定基盘/旋转炮架、4.0s 渐宽 + 1.5s 闪烁、360m 全宽判定、随机小队目标/同拍 AOE/高速淡出表现、坦克四挂点与主炮、远程 VLS 参数隔离、来源先灭与全 TGT 完成分离、Boss 转场退役；bench key `tier3_zone` | `run` `_test_global_tier3_slot` `_test_f6_atomic_profile_preset` `_test_ground_profile_map_gate` `_test_profile_text_contract` `_test_super_cannon_contract` `_test_siege_tank_contract` `_test_long_range_vls_clone` `_test_threat_neutralizes_before_mission_completion` `_test_boss_transition_retirement` |
| `tests/test_weather_system.gd` | `extends RefCounted` | [测试] 图2/3 云配置、Visual bench 固定天气 seed/风向/风速、沙漠新旧云量固定采样、海岛四象限分布、沙尘暴 180km/h/10km 宽/LOW-only、曲边羽化、Debug 中心定位、真实 Aircraft 状态与 MissileManager 高度查询、导弹/锁定/F6 消费链；bench key `weather` | `run` `_test_deterministic_capture_seed` `_test_map_configs` `_test_desert_cloud_reduction` `_test_sandstorm_timeline_and_altitude` `_test_aircraft_runtime_effect` `_test_ocean_distribution` `_test_runtime_consumers` |
| `tests/test_joust.gd` | `extends RefCounted` | [测试] 攻击跑物理步进：MQ-112 锁定/充能窗与真实电磁炮、骑士冲锋-脱离-折返、闭合放弃；附加 MQ-X 生产三路武器/F-22 级隐形/唯一 joust 配置入口与 60s 火力窗回归，bench key `joust` | `run` `_test_railgun_deadlock_fixed` `_test_gun_lancer_rhythm` `_test_giveup` `_test_mqx_attack_run_and_loadout` |
| `tests/test_boss_progression.gd` | `extends RefCounted` | [测试] BOSS 通关强化与 Mother Goose 武器：次数保留、Wraith 恐惧配置/控制器解锁、重复装配与配置隔离、YF-23 后方生成/可锁定、CSG/Goose 分层、VLS 实伤、MQ-111 真实拦截与过热循环；bench key `boss_progression` | `run` `_test_wraith_fear_loadout` `_test_wraith_support_deployment` `_test_goose_vls_distance_airburst` `_test_mq111_cumulative_intercept` `_test_mq111_player_heat_cycle` |
| `meta/meta_shop.gd` | MetaShop (AutoLoad) | [共享/局外] 生涯商店账本：6 学说 + 既有 4 项机体/后勤商品 + 4 项新增 T0 采购案（含 3000 功勋机体战术适配）+ 五项战场支援许可 + 43 条按进化 Tier 定价的机体专属许可（全购 30000）；正式局权益查购买态，非正式局 fail-open | `signature_item_id` `is_signature_owned_for_aircraft` `is_airframe_affinity_entitled` `is_awacs_entitled` `is_zone_air_support_entitled` `is_zone_ground_support_entitled` `is_ace_f15_support_entitled` `is_airfield_sam_entitled` `aircraft_unlock_ok` `item_listed_ok` `doctrine_listed_ok` `is_listed` `is_owned` `buy` `is_upgrade_gated` `migrate_legacy_loadout` |
| `meta/meta_shop_ui.gd` | `extends Node2D`（`scenes/meta_shop.tscn`） | [局外/UI] 共享 CRT 白色终端生涯商店；战术学说/机体专属/战场支援/机体与后勤四分页，已发现专属两列、未知六列，商品三态与余额实时刷新 | `meta_shop_ui.gd:77 _add_page` `meta_shop_ui.gd:130 _build_signature_page` `meta_shop_ui.gd:171 _build_signature_tile` `meta_shop_ui.gd:229 _build_unknown_signature_tile` `_build_doctrine_tile` `_build_item_tile` `_refresh` `_on_back_pressed` |
| `tests/test_meta_shop.gd` | `extends RefCounted` | [测试] 生涯商店无头单测：基础解锁/持久化/doctrine、43 专属目录与 30000 总价、F-14 特例、四项新增 T0 采购解锁、机体战术适配与五项战场支援权益、四分页、legacy 迁移；bench key `meta_shop` | `run` `_test_signature_catalog` `_test_support_entitlements` `_test_shop_categories` |
| `tests/test_boss_phase.gd` | `extends RefCounted` | [测试] BOSS 阶段闸门 + 全场撤离 + BOSS/Debug 演员不计价 无头回归（闸门跟随解锁 / 画面内物理撤离 / 画外也须真实出界后回收 / 豁免名单 / 舰船地面不动 / `no_kill_reward` 含普通 UAV 对照与 Debug 地面演员 / CSG 机库上限 / BOSS 阶段空地 XP 总闸），bench key `boss_phase`；StubMode 替身直调 `_update_boss_phase_purge` + `_detect_kills` | `run` `_test_far_cleanup_and_expired_adds` `_test_offscreen_enemy_freed` |
| `naval/naval_placement.gd` | `NavalPlacement extends RefCounted`（全静态） | [共享] 舰队摆位水域校验：CSG BOSS 舰队 + 战区海上任务共用。刚体整队绕圆心转 → 每艘船走一个**同心圆**，沿圆按 40 px 步长细采 `MapGeography.is_on_land`；窄水域装不下就**降级**（缩盘旋半径 → 0 = 原地驻泊） | `naval/naval_placement.gd:57 score` `naval/naval_placement.gd:98 pick_placement`（其余纯函数见同文件） |
| `naval/weapon_mount_params.gd` / `naval/weapon_mount.gd` | `WeaponMountParams Resource` / `WeaponMount RefCounted` | [共享] 舰载挂点静态参数与运行时状态；`NAVAL_FLAK` 追加在旧枚举末尾，炮组冻结解/余弹/间隔状态存于挂点实例 | `weapon_mount.gd:49 initialize` `weapon_mount.gd:66 apply_damage` |
| `naval/naval_weapons.gd` | `NavalWeapons extends RefCounted`（全静态） | [共享] 舰载武器派发；通用 preferred target 在合法射程内优先玩家；DDG Flak 2Hz 搜敌，800–5000m 内冻结预瞄解，首弹立即 + 0.25s 三连发、6s 冷却，只走 airburst 管线 | `naval_weapons.gd:56 update` `_find_aircraft_in_range` `naval_weapons.gd:365 _update_naval_flak` `naval_weapons.gd:386 _find_aircraft_for_flak` `naval_weapons.gd:402 _begin_naval_flak_burst` `naval_weapons.gd:419 _fire_naval_flak_shell` |
| `naval/naval_unit.gd` | `NavalUnit extends CombatUnit` | [共享] 舰体/部件/移动/绘制；气氛非致死入口只磨 hull 至 1，不触碰挂点/弱点；hover 显示舰载 Flak 包线，战略视距批量保留挂点位置与损毁态；舰船状态栏复用全兵种屏幕空间矢量面板和 0.35/0.40 详情迟滞，并显示舰种/舰名/航向/航速；物理外层在 F3 明细开启时分桶 | `_physics_process` `_physics_process_impl` `take_atmosphere_damage_at` `_draw_flak_envelopes` `_draw_mounts_placeholder` `mount_detail_visible_at_scale` `_draw_alive_mount` `_draw_status_label` |
| `tests/test_naval_zone_water.gd` | `extends RefCounted` | [测试] 舰队不上岸与对舰难度无头单测 26 断言：战区 E 三档 40px 复核、4/5/6 舰型构成、真实六舰实例化、全舰 TGT/旗舰速杀负例、人工缩编、深内陆 fallback、CSG 南北锚点；bench key `naval_zone_water` | `tests/test_naval_zone_water.gd:22 run` `tests/test_naval_zone_water.gd:36 _check_fleet_compositions_and_targets` `tests/test_naval_zone_water.gd:70 _check_spawned_fleet_contract` |
| `tests/test_zone_air_support.gd` | `extends RefCounted` | [测试] 镜头预加载/广播幂等、边缘入场、ALLY 支援契约与真实撤离；地面移开镜头仍保留、飞机图内/近玩家保留、宽限重置、整群分批回收 | `run` `_test_camera_away_retirement` `_test_retirement_distance_and_budget` `_test_conquered_garrison_egress`；bench `zone_air_support` |
| `survivor/survivor_mode.gd`（战区支援压力样本） | 同上 | [bench] `zone_support_stress`：Lv15 玩家 + 常规 31 敌混编 + Sentinel/5 护卫/Aegis + 一支 3★ F-86（4 架）+ 一支 A-10（2 架），用于性能红线与实例泄漏检查 | `_bench_force_zone_support` |
| `survivor/survivor_mode.gd`（对舰压力样本） | 同上 | [bench] `naval_zone_stress`：常规 31 敌混编 + Sentinel/5 护卫 + 3★ 六舰全目标编成，玩家置于舰队交战半径并锁血，持续覆盖 VLS/CIWS/Flak 与 18 个挂点代理 | `survivor/survivor_mode.gd:2508 _bench_force_naval_zone` |
| `survivor/survivor_mode.gd`（3★ 特殊任务样本） | 同上 | [bench] `tier3_super_cannon` / `tier3_super_cannon_d` / `tier3_siege_tank` / `tier3_deadair` / `tier3_long_range_vls`：均走隔离的 ZoneData → ZoneMission 正式生成链并强制气氛层；AURORA LANCE 覆盖东京湾 A/D 连续陆地区，A 在 6.0s 抓渐宽阶段、D 在 8.8s 抓满宽闪烁；巨炮 Visual ≤10s、其它 ≤7.5s 时以真实来源为镜头锚，长时样本追加 31 架混编敌机做专项性能门 | `_bench_new_isolated_zone_data` `_bench_dispose_live_zone_mission` `_bench_force_tier3_zone` |
| `survivor/survivor_mode.gd`（王牌截击压力样本） | 同上 | [bench] `ace_support_stress`：Lv15 玩家 + 常规 31 敌混编 + Sentinel/5 护卫 + MARATHON 五机 + 两架 ALLY F-15，覆盖真实事件入场与 46 机性能红线 | `survivor/survivor_mode.gd:7609 _bench_force_ace_support` |
| `tests/test_naval_formation.gd` | `extends RefCounted` | [测试] 舰队编队运动无头单测 10 断言（CSG 环形巡航 6 / U-turn 转速上限兜底 3 / 独立单船不变 1），bench key `naval_formation`；逐帧真步进 `NavalUnit._update_movement`，守"整支舰队原地旋转"回归 | `run` |
| `tests/test_bomber_rotor_airburst.gd` | `extends RefCounted` | [测试] 轰炸/旋翼机/空爆炮/气氛火炮轨道回归；覆盖可选任务频率/奖励隔离、150/300/450 XP、三语资源、7 条等时航线、低/高响应混编、稳定机型变体、2–4 架实时增援、58% 无人护送中止边界、30 HP 任务 B-1B、单弹摧毁、成功优先和 FAILED 无痕；bench key `bomber_rotor_airburst` | `run` `_test_optional_mission_frequency` `_test_bomber_escort_xp_reward` `_test_bomber_outcome_priority` `_test_failed_zone_contract` `_test_bomber_escort_package_geometry` `_test_airburst_aim_and_effectiveness` `_test_artillery_analytic_rail` |
| `tests/test_squad_command_ui.gd` | `extends RefCounted` | [测试] 小队指挥面板启动条件 + 固定号机映射 + 长机阵亡解绑竞态 + 操控角色战术权限单例无头单测（28 断言），bench key `squad_cmd_ui`；守“指挥 UI 只在 F-14 出现”“换帅后数字键漂移”“继任后全队广播退化单机”“新操控机误吃 35% 导弹坡度 cap”回归 | `run` `_test_leader_down_repairs_squad_bindings` `_test_control_role_transfers_tactical_preference` |
| `tests/test_player_instrument_hud.gd` | `extends RefCounted` | [测试] 玩家/僚机/三轴/HUD 偏好、布局、特殊武器、Q/G/F/T、flare、互斥 R 机动与 HUD 首次两闪状态机回归；覆盖空间排序、错峰并发、动态取消和逐僚机行拆分；bench `player_hud` | `run` `_test_layout_contract` `_test_first_reveal_sequence` `_test_weapon_priority_cycle` `_test_flare_visual_progress` `_test_unique_r_maneuver_cooldown` |
| `tests/player_hud_visual_qa_runner.gd` | `extends Node2D` | [测试] 玩家 HUD 可视化验收场景驱动；输出复合框板关闭态与最终样张，覆盖玩家/第一条僚机 HUD 仅 HP 红闪、其它框架保持原色，以及低于 HUD 的红色受伤外圈；bench key `player_hud_visual`（DisplayMode=`Visual`） | `_ready` |
| `tests/main_menu_visual_qa_runner.gd` | `extends Node2D` | [测试/Visual] 逐一重建中/英/日正式主菜单，审计 CRT 机壳、玻璃滤镜、`23u × 30u` 安全区、五行模式和默认焦点几何，并保存三套真实字体截图；bench key `main_menu_visual`（DisplayMode=`Visual`） | `_ready` `_audit_menu` |
| `tests/ui_iteration_visual_qa_runner.gd` | `extends Node` | [测试/Visual] 逐页实例化选图、选机、资料库、商店、音频、色盘、暂停、Game Over 与通关，校验共享页壳/默认白色并保存 9 张真实截图；bench `ui_iteration_visual ... Shadow Visual` | `_ready` `_capture_scene` `_capture_settings` `_capture_pause` `_capture_result` `_save` |
| `tests/boss_arrival_banner_visual_qa_runner.gd` | `extends Node2D` | [测试] BOSS 登场身份横幅独立可视验收：Mother Goose 逐窗 / 终态、Wraith、CSG 与 Black Star 银黑橙终态，共七张 1920×1080 截图；bench key `boss_arrival_banner_visual`（DisplayMode=`Visual`） | `_ready` `_capture` `_build_backdrop` |
| `tests/boss_debug_select_visual_qa_runner.gd` | `extends Node` | [测试] 走真实 Boss Debug 链路并采集 1920×1080：Boss/Black Star 场景选择、7 个 T4 四机以上参考编队、F-47 实战构筑、海洋 FINAL WAR，以及沙漠十四节列车真实进场（等待演员/实际 zoom/canvas 安全边界；`cine_target=第7节` / 180 屏幕 px 安全区 / 0.26 广角 / ingress）与铁路中段贴轨、120 帧专项性能；bench key `boss_debug_select_visual`（DisplayMode=`Visual`） | `_ready` `_wait_for_train_arrival_state` |
| `ui/ui_dev_outline_overlay.gd` | `UiDevOutlineOverlay extends Control` | [UI Dev] 只按矩形位置与包含关系生成 2 px 紫色诊断框；顶层 A-Z/AA，子框压成 A1/A2 两级定位，黑底紫字标在框内右上角 | `regions` `flatten_descendants` `build_entries` `alphabetic_code` `_draw` |
| `tests/ui_dev_panel_runner.gd` | `extends Node2D` | [UI Dev] 固定 HUD 排版截图场景驱动：实例化正式玩家/七僚机/三轴控件，覆盖纯净总栈与手动 FLR 插键画面，收集自动排版区域并叠加定位框；正式游戏入口为 F7 | `_ready` `_add_dev_overlay` `_append_component_regions` `_save_bench_screenshot`；bench `ui_dev_panel_visual` / `ui_dev_panel_clean_visual` / `ui_dev_panel_manual_flare_visual` |
| `tests/test_ui_dev_outline.gd` | `extends RefCounted` | [测试] UI Dev 几何编号、去重、A-Z/AA、两级压平、2 px 向内紫框及 F6/F7 热键隔离契约；bench key `ui_dev_outline` | `run` `_test_geometry_only_hierarchy` `_test_stable_top_level_letters` `_test_visual_contract` `_test_hotkey_contract` |
| `tests/test_terminal_text.gd` | `extends RefCounted` | [测试] 通用字号规范回归：真实轮廓撑高及缓存、垂直居中、1u 固定 15px、最大字符串基准、显式对齐、共享主要字号的高度优先 `1q` 扩宽与 u/q 共享描边坐标；bench key `terminal_text` | `run` `_check_visible_fill` `_check_ink_bounds_cache` `_check_one_u_fixed_15` `_check_layout_reference_controls_width` `_check_horizontal_alignment_rule` `_check_height_first_q_expansion` `_check_shared_grid_coordinates` |
| `tests/test_waypoint_fire_control.gd` | `extends RefCounted` | [测试] 点地移动火控阶段一回归（bench `waypoint_fire`）：玩家航点 auto-fire 保留、编队僚机不写导航目标的机会发射、SARH/FAF 原质量边界、旧协同齐射旁路阻断，以及锁定/包络/在飞弹/团队超杀/敌方隔离负例 | `run` `_test_player_waypoint_keeps_auto_fire` `_test_formation_fire_without_navigation_takeover` `_test_existing_quality_thresholds` `_test_waste_prevention_gates` |
| `events/ai_directive.gd` | `AIDirective extends RefCounted` | [生存] 事件系统下发给 AI/NavalUnit 的声明式覆盖指令；存在期间 AI 跳过常规 PATROL/ENGAGE 路由 | 工厂 `fly_to(target, on_arrival)` `patrol_ring(center, radius)` `follow_path(wps, loop)` `hold_position()` `engage_target(t)` `passive()` + `is_owner_alive()` |
| `events/game_event.gd` | `GameEvent extends RefCounted` | [生存] 事件基类（一段剧本/一次刷怪/BOSS 流程）；管理 lifecycle + managed_units + 自动撤销 directive | `_start` `_update(delta)` `_finish` `set_directive(unit, d)` `clear_directive(unit)` `clear_all_directives()` `end()` |
| `events/event_director.gd` | `EventDirector extends Node` | [生存] 事件调度器（survivor_mode 子节点；非 AutoLoad）；持 mode/player/spawner 引用，每帧 tick 所有 active 事件 | `start(event)` `find_by_name(name)` `active_count()` `_physics_process` |
| `events/boss_encounter_event.gd` | `BossEncounterEvent extends GameEvent` | [生存] BOSS 战剧本：选定 encounter 即后台预载其 BOSS 曲；从 history 注入通关次数；随后身份横幅 → CINEMATIC（PRE_STAGE）→ ENGAGED → VICTORY，序列缺失 fail-open；custom encounter 走通用 spawn；`has_failed` 在 active 下降胜利沿之前分流；Black Star 身份序列只播横幅，不切固定根机镜头；ENGAGED 后第一根在玩家附近真实下降，事件按双根真实开始信号播 `BLACK STAR-01/02`，第一根倒数期间只隐藏玩家绘制并在撞击 / 异常收尾恢复；接收 Debug scenario | `_init(anchor, heading_deg, map_id, forced_boss_id, boss_history, boss_debug_scenario)` `_start` `_update` `_spawn_custom` `_spawn_hyper_a` `_on_hyper_a_root_descent_started` `_on_hyper_a_root_descent_finished` `_set_arrival_player_visual_hidden` `_apply_pre_stage_directives_hyper_a` `_try_play_arrival_cinematic` `_on_arrival_cinematic_done` `_enter_engaged` |

## ROE 全图察觉与交战规则（2026-07-12，spec global-awareness-roe）

| 文件 | 职责 | 关键入口 |
|---|---|---|
| `scripts/survivor/roe_director.gd` | ROE 指挥部：中队察觉（感知圈/事件/战区聚合/datalink + 15s 记忆）+ 姿态派生标记 + leash 纪律 + 热度账本 → hunter 配额 | `tick()` / `_run_pass()` / `_heat_step()` / 静态 `quota_for_heat()` `heat_floor_for_level()` `step_heat_value()` |
| `scripts/events/faction_transition.gd` | 动态阵营原子事务：IFF、目标/锁定、旧小队、在飞弹药、任务身份、颜色与一次性信号 | `convert()` `_detach_old_combat_state()` `_reassign_in_flight_weapons()` |
| `scripts/events/ally_force.gd` | ALLY 第三方转换兼容包装，统一委托 `FactionTransition` | `convert_aircraft()` / `convert_ground()` |
| `scripts/survivor/hacked_ally_force.gd` | 被黑 MQ 的无 process 编队账本；绑定当前操控长机、切控重定向、战斗至被击毁 | `set_leader()` `adopt()` `shutdown()` |
| `scripts/tests/test_faction_conversion.gd` | 阵营事务、真实激光黑客完成路径、强类型缓存清理、freed 继任引用、黑客护航重绑、激光互斥与 WhiteTea 仲裁定向回归 | `bench/run.cmd faction_conversion`；`_test_laser_hack_runtime_conversion()` `_test_squad_cleanup_skips_freed_successor()` |
| `scripts/tests/build_translations.gd` | 从五张 CSV 逐表重建 15 份跟踪的 `.translation` 资源（隔离输出到 bench/results） | `bench/run.cmd i18n_build` |
| `scripts/events/awacs_support_event.gd` | AWACS 支援事件：绕当前战区南侧的跑道形轨道 + 到点（或 BOSS 解锁）撤离飞出地图 + 进离场无线电 + buff 区（锁定×3 / 导弹 G ×1.25）静态注册表；生成时挂主战场海绿范围层，事件结束当帧隐藏 | `lock_rate_mult_for()` / `missile_g_mult_for()` / `active_awacs()` / `_pick_orbit_center()` / `_begin_egress()` / `_say()`（trigger `awacs_onstation` / `awacs_egress`）；常量 `ON_STATION_S` `EGRESS_TIMEOUT_S` `ORBIT_STANDOFF_PX` `ORBIT_HALF_SPAN_PX` `ORBIT_MARGIN_PX` `BUFF_RADIUS_PX`（逐符号行号见 [code-index.md](code-index.md) 第三方事件段） |
| `scripts/survivor/support_range_overlay.gd` | `SupportRangeOverlay extends Node2D` | [生存/视觉] AWACS 等移动支援源的静态世界范围层；淡填充 + 阵营色描边只构建一次，随父 transform 移动，无 process / 扫描 | `setup(value_px, value_team)` `_ready` `_draw` |
| `scripts/events/ace_reinforcement_event.gd` | 王牌支援中队事件；每局首次非 BOSS 王牌可派 Hound-1/2 两架 3000m 雷达 F-15 并播固定双句；WhiteTea 2→1 时幸存机投降转 ALLY、本人无线电、完整中和 XP 与被动离场；中队血条浮现时取得一首随机 one-shot 专属 BGM，曲终或终态幂等归还且 Boss 优先；终态通知 Encounter Director 进入恢复窗 | `_start` `_update` `should_whitetea_surrender()` `_try_whitetea_surrender()` `_tick_surrender_egress()` `_handle_ace_terminal()` `_begin_ace_battle_music()` `_end_ace_battle_music()` `_spawn_ally_support()` `_begin_withdraw()` |
| `scripts/tests/test_roe_director.gd` | ROE 单测 33 项（热度/配额对拍/姿态派生/感知门/守区 leash），bench key `roe` | `run()` |
| `scripts/tests/test_boss_hunter.gd` | BOSS 猎手化 + Wraith 角色/执行失误/队级战术 单测 127 项（PURSUE_UNIT 执行分支 / 无归巢 / **世界边缘软收容 + 40px 物理硬护栏 + ace_support 撤离负例** / KNIGHT-SNIPER 距离带 / 两个死 meta 已清 / 热诱弹 4 命 / 瞄准误差开门 / 减速迟滞锁存 / cloak 60s 可重复 CD + 近距打断），bench key `boss_hunter` | `run()` `_test_ace_world_boundary()` `_test_wraith_cloak_cadence()` |
| `scripts/tests/test_map_boundary.gd` | 三图 64km 栅格覆盖、严格相机裁切、普通 AI 外缘进入/真边界内收/越线硬钳、三语倒计时格式、2.5s 取消/锁存/重武装及释放玩家引用回归；bench key `map_boundary`，20 项 | `run` `_test_geometry_and_camera_crop` `_test_three_map_raster_coverage` `_test_ai_extension_discipline` `_test_boundary_ui_countdown` `_test_countdown_cancel_latch_and_rearm` `_test_freed_player_reference` |

改动挂点：`combat_unit.gd`（IFF API + TEAM_* 常量）· `ai_controller.gd`（`_roe_allows_scored_engage` 感知门，acquire_target 内）· `survivor_spawner.gd`（`_roe` 持有 / hunter 整队抽调 / 磁吸退役 / 线路巡逻 roll）· `survivor_data.gd`（ROE_* 常量 7 项）· `survivor_mode.gd`（`airfield_ally_plan` / `_try_deploy_airfield_sam` / `_deploy_airfield_ally_gradual`（机场基础 AA×2 + MetaShop 授权 SAM）/ `_update_ally_events` / 攻克热度钩子 / 锁定 buff 注入）· `meta_shop.gd`（机场 SAM 永久权益）· `game_constants.gd`（FactionPalette Token + 三分支色函数）· `missile.gd`+`missile_manager.gd`（awacs_g_mult 快照）· `merit_ledger.gd`（`award()`）

## 表演导演系统（2026-07-20~21，spec ui-transition；编排手册 [cinematic-authoring.md](cinematic-authoring.md)）

| 文件 | 类/类型 | 职责 | 关键入口 |
|---|---|---|---|
| `presentation/presentation_director.gd` | autoload `Presentation` | [生存] 表演导演：序列运行 + 9 通道分发（time/camera/overlay/panel/banner/stage/actor/radio/audio）+ 双遮罩层（压暗动态取位 `min(16, panel.layer−1)` / 特效 25）+ BOSS 横幅层 24 + F8 热重载；IDLE 时 `set_process(false)` 零开销；暂停期代泵镜头；`_ready` 安装 DisplayPacing（物理插值白名单 + 帧上限） | `play_cinematic(seq, ctx)` `present(panel, seq)` `dismiss(panel, seq, hide_node)` `_ch_banner` `clear_all()`（四类泄漏总闸）`bind_camera` `bind_radio` `has_sequence` `debug_replay` 信号 `sequence_finished` |
| `ui/boss_arrival_banner.gd` | `BossArrivalBanner extends CanvasLayer` | [生存/UI] BOSS 镜头前系统入侵身份横幅：5 层警告窗严格逐个压入，主身份最后展开；palette 含终端绿、Wraith 蓝黑电蓝与 Black Star 银黑橙；Boss 名/角色/呼号共用布局 | `show_identity(name_key, role_key, callsign, motto_key, palette_id)` `_apply_palette` `has_palette` `set_reveal_progress` `warning_reveal_progress` `set_dismiss_progress` `hide_immediately` `is_showing` |
| `presentation/time_authority.gd` | `TimeAuthority extends RefCounted` | [生存] 时间请求栈：`Engine.time_scale` + `get_tree().paused` 唯一写入口；最小值获胜、同 id 覆盖；`hard_pause` 幂等写入（不早退，防外部直写后解除失效） | `request(id, scale, blend)` `release(id, blend)` `hard_pause(on)` `solve()` `tick(unscaled_delta)` `clear_all()` |
| `presentation/sequence_player.gd` | `SequencePlayer extends RefCounted` | [生存] 序列时间线运行器：step 推进/插值/瞬时判定/超时检出/强制收尾；**不认识通道**（分发归导演） | `load_sequence` `advance(ud)` `force_finish()` `is_done` `is_timed_out` `total_duration` |
| `presentation/stage_isolator.gd` | `StageIsolator extends RefCounted` | [生存] 空舞台：冻世界下淡出非演员 + 演员唤醒（ALWAYS + `visible=true` + `lod_level=0`，破离屏 LOD 藏机）；restore 重扫全场幂等；CanvasLayer 走 visible（无 modulate） | `clear(actors, extra, t)` `restore(extra, t)` `force_restore(extra)` `_set_alpha`（静态） |
| `presentation/cinematic_cast.gd` | `CinematicCast extends RefCounted` | [生存] 演员班底：通用演员为 CombatUnit（支持 NavalUnit 特写）；bind/release 持有虚拟环境所有权，隔离真实战斗传感器隐形；飞机走位全经 owner(GameEvent) 下 `AIDirective`；尾迹演出覆写（80→240 点） | `bind` `echelon_ingress`（传送+清尾迹+逐机淡入）`converge`（逐机反解速度+包线钳制）`cloak_on_meet`（交汇即隐身+窗口末兜底）`scatter`（背向玩家扇面）`trail_boost/fade/restore` `release()` |
| `presentation/ease_lib.gd` | `EaseLib`（全静态） | [共享] 缓动函数表 6 条（`back_out` 过冲 ~1.10 = 弹入手感） | `apply(name, t)` + 各函数 |
| `resources/presentation/sequences.json` | 数据 | 全部序列定义（升级急刹 / 通用面板 / 注册 BOSS 登场）；arrival 都先播 banner 且 ≤7s：Black Star 因根机仍在 30km 隐藏而在横幅后直接释放；IRON SERPENT 横幅退场后跟随第 7 节编组中部 4s+、0.26 广角保留整列与地图铁路，再回玩家镜头；编辑器 F8 热重载 | 序列名即键；BOSS 登场命名契约 `<boss_id 小写>_arrival` |
| `tests/test_presentation.gd` | 测试 | 回归门 282 断言：时间栈 / 泄漏 / step / 缓动 / 压暗层、注册 BOSS 横幅与 arrival 时序 / 命名、十四节武装列车横幅后切镜 / 编组中部持续跟随 / ≤0.30 广角 / 铁路背景保留、演员战斗状态隔离、i18n、标签 / 轮廓、状态栏组合变换、受伤蓝白相位与正式伤害入口、TypedArray 舞台快照与已释放引用净化 | `run()` `_test_boss_banner_contract` `_test_simple_boss_sequences_wellformed` `_test_armored_train_arrival_sequence` `_test_compact_aircraft_labels` `_test_cast_combat_state_isolation`，bench key `presentation` |
| `tests/test_hyper_a_boss.gd` | 测试 | Black Star 108 项专项契约：Registry、Debug 十入口（含 FINAL WAR）、双根真实下降信号 / 报数无线电、玩家纯视觉隐藏与恢复、400/200/100/70 HP、四代 flare / 4 发弹匣 / 尺寸、拓扑、锁数、G0 在 GUN 模式下全向四目标独立齐射 / 特殊状态静默、G1 首次隐藏下降 / 侧向拒射、40–50s 再入 / 7–10s 高空等待 / 12s 排队错峰、爬升消失时目标 / 雷达锁存解除且状态栏保留高度倒数、火箭 / 6s SLOW、物理对线 / 伸展预警 / 线满才显示扇区、急刹扇区边界 / 实伤 / 单次结算、已释放玩家 / 缺失 meta 崩溃防护与 arrival 顺序；含断言总数门 | `run()`，bench key `hyper_a` |

## 海洋三维地图

| 文件 | 职责 | 入口 |
|---|---|---|
| `rendering/ocean_volume_archive.gd` | 海洋离线归档、编辑器源码指纹与导出数据指纹 | `fingerprint`、`data_fingerprint`、`valid` |
| `experiments/ocean_volume_factory.gd` | 海洋原足迹建筑、发射架、跑道与避障服务路静态合批 | `build`、`_gantry`、`_facade`、`runway`、`service_bands`、`_route_bands`、`_route_clear` |
| `tests/build_ocean_volume.gd` | 海洋固定曲面裁片、连续法线和静态资源离线构建 | `run`、`relief_texture`、`tile_layouts`、`_mesh_bytes` |
| `rendering/ocean_volume_ground.gd` | 借用海洋 Raster 纹理、严格 UV 配准、瓦片生灭与释放 | `setup`、`sync`、`_bind`、`clear`、`debug_state` |
| `rendering/ocean_volume_overlay.gd` | 内置海洋三维入口、共享投影和海洋地表生命周期 | `ocean_enabled`、`_load_archive`、`_setup_geometry`、`_step_geometry`、`_deactivate`、`debug_state` |
| `tests/test_ocean_volume.gd` | 海洋来源、原建筑、裁片接缝、入口回退 focused 门 | `run` |
| `tests/ocean_volume_lifecycle_case.gd` | 真实 SceneTree 旋转投影、源释放和退出回收 | `run` |
| `tests/ocean_volume_visual.gd` | 真实菜单链、同位分区 A/B、Tab、退出重进 | `_run` |
| `tests/ocean_volume_combat.gd` | 海洋 36 混合实战及相机巡航性能门 | `_ready`、`_bench_finish_now` |
| `tools/build_ocean_elevation.py` | 按原母图 UV 重建 Terrarium 高程，默认输出 tmp | `CLI` |

## 地图接触 AO

| 文件 | 职责 | 入口 |
|---|---|---|
| `rendering/map_contact_ao.gd` | 两区只读接触场、源指纹、会话级共享与关闭回退 | `path_for` `fingerprint` `valid` `load_field` `bind` |
| `tests/build_map_contact_ao.gd` | 现有结构三角 BVH 离线有限距离余弦半球烘焙 | `directions` `occlusion` `run` |
| `tests/test_map_contact_ao.gd` | 源指纹、边缘、衰减、容量、材质接线回归 | `run` `_check` |
| `tests/map_contact_ao_visual.gd` | 两图正常菜单、预载入交接、暂停同帧开关与退出 | `_ready` `_run` `_collect` `_changed_pixels` `_wait_scene` `_check` |
| `tests/desert_contact_ao_combat.gd` | 将相同36成员/8段巡检平移到工业区；实际AO材质开关和60FPS门 | `_ready` `_bench_force_battlefield_atmosphere_stress` `_bench_finish_now` |
# HLOD纹理流送接入

`rendering/tokyo_hlod_stream.gd`：`configure_hlod`、`request_textures`、`texture`、`load_image`、`_step_textures`、`_process_stream`、`close`、`summary`，继承CellStream，辅助纹理租约与网格共预算/请求上限/更新循环，异步摘要和Image读取、逐帧上传、跨帧退役。`tests/test_tokyo_hlod_stream.gd`：`run`，真实共享/取消/摘要失败/预算拒绝及owner退出；接cells生命周期与显式HLOD_STREAM_TEST入口。未接默认地图。

## GPU 三维天气样板

- `rendering/weather_density_presentation.gd:9 setup`；`rendering/weather_density_presentation.gd:37 _prewarm_materials`；`rendering/weather_density_presentation.gd:42 _noise_ready`；`rendering/weather_density_presentation.gd:52 set_enabled`；`rendering/weather_density_presentation.gd:63 sync`；`rendering/weather_density_presentation.gd:123 _build_density_chunk`；`rendering/weather_density_presentation.gd:151 _sync_storm`；`rendering/weather_density_presentation.gd:177 summary`：正式 opt-in 密度天气，32×32权威遮罩、共享64³噪声、独立GPU形变、权威风漂与双向沙尘锋面；96块硬上限，异步就绪前二维回退。shader `resources/shaders/weather_density_runtime.gdshader`。


- `tests/weather_density_preview.gd:4 build_gallery`；`tests/weather_density_preview.gd:30 set_time`；`tests/weather_density_preview.gd:35 capture`；`tests/weather_density_preview.gd:42 measure`；`tests/weather_density_preview.gd:85 run`；`tests/weather_density_preview.gd:166 build_storm`；`tests/weather_density_preview.gd:211 check_loop`：AGL_WEATHER_DENSITY=1，GPU云体独立循环/漂移/周期接缝与24/16步耗时；叠加AGL_WEATHER_DUST=1验沙尘锋面与128飞沙。shader `resources/shaders/weather_density_preview.gdshader`、`resources/shaders/weather_dust_streak_preview.gdshader` 与正式透明视口共用的 `resources/shaders/weather_density_composite_preview.gdshader`。

- `tests/weather_cloud_shape_preview.gd:4 build_mesh`；`tests/weather_cloud_shape_preview.gd:32 run`：AGL_WEATHER_COMPARE=1 的离线融合云A/B/C实机比较；生成源 `tools/bake_weather_cloud_shapes.py`，不接入正式天气。
- `tests/weather_holo_preview.gd:4 contour`；`tests/weather_holo_preview.gd:13 mesh_node`；`tests/weather_holo_preview.gd:26 build_gallery`；`tests/weather_holo_preview.gd:69 render_display`；`tests/weather_holo_preview.gd:99 run`：AGL_WEATHER_HOLO=1，同网格展示/实机全息气象样板；材质 `resources/shaders/weather_holo_preview.gdshader`。

- `rendering/weather_volume_presentation.gd:58 _prewarm_materials`：初始化实际shader变体两帧暖绘后释放，不增加常驻视口。

- `rendering/weather_volume_presentation.gd:28 setup`；`rendering/weather_volume_presentation.gd:82 sync`；`rendering/weather_volume_presentation.gd:150 _select_chunks`；`rendering/weather_volume_presentation.gd:170 build_cloud`；`rendering/weather_volume_presentation.gd:215 _mesh`；`rendering/weather_volume_presentation.gd:227 _sync_storm`；`rendering/weather_volume_presentation.gd:275 set_enabled`；`rendering/weather_volume_presentation.gd:290 summary`；`rendering/weather_volume_presentation.gd:300 _exit_tree`。
- `tests/weather_volume_lifecycle_case.gd:3 run`；`tests/weather_volume_lifecycle_case.gd:10 _run_presenter`。
- `tests/weather_volume_runner.gd:3 _ready`；`tests/weather_volume_runner.gd:6 _run`。
- `tests/weather_volume_visual.gd:3 _ready`；`tests/weather_volume_visual.gd:7 _run`。
- 天气规则与二维回退：`weather_system.gd`；共享接入：`experiments/volume_world_probe.gd`、`rendering/aircraft_volume_overlay.gd`。
- shader：`resources/shaders/weather_volume.gdshader`、`resources/shaders/weather_sand.gdshader`、`resources/shaders/weather_grit.gdshader`。
- bench：`weather`、`weather_volume_lifecycle`、`weather_volume_visual`；`volume_map_3d_c1/c2` 配合 `AGL_WEATHER_VOLUME=on/off` 与 `AGL_WEATHER_STORM_TEST=1` 作同场天气对照。试用入口 `play_weather_volume.cmd`。

## ORION 完全体实装入口

行为与数值权威：[ORION 完全体](../specs/bosses/orion-final-form.md)。当前为实装中；本节仅登记代码位置，不表示性能或完整局验收已通过。

- `survivor/orion_airframe_config.gd:4 make_airframe`；`survivor/orion_airframe_config.gd:36 make_admm`。
- `survivor/orion_fang_laser.gd:21 setup`；`survivor/orion_fang_laser.gd:26 stop`；`survivor/orion_fang_laser.gd:34 update`。
- `survivor/orion_final_form.gd:46 spawn`；`survivor/orion_final_form.gd:107 engage`；`survivor/orion_final_form.gd:113 set_player_ref`；`survivor/orion_final_form.gd:117 body`；`survivor/orion_final_form.gd:121 get_members`；`survivor/orion_final_form.gd:130 update`；`survivor/orion_final_form.gd:174 cleanup`；`survivor/orion_final_form.gd:212 _scan_targets`；`survivor/orion_final_form.gd:227 _update_admm`；`survivor/orion_final_form.gd:286 _update_rail`；`survivor/orion_final_form.gd:330 _update_flight_orders`；`survivor/orion_final_form.gd:392 _cancel_invalid_slots`；`survivor/orion_final_form.gd:408 _prune_missiles`；`survivor/orion_final_form.gd:416 _present_weapons`；`survivor/orion_final_form.gd:453 _aircraft`。
- `survivor/orion_fire_control.gd:24 eligible`；`survivor/orion_fire_control.gd:28 should_arrive`；`survivor/orion_fire_control.gd:35 allocate_salvo`；`survivor/orion_fire_control.gd:73 lock_duration`；`survivor/orion_fire_control.gd:83 launch_schedule`；`survivor/orion_fire_control.gd:104 point_segment_distance`；`survivor/orion_fire_control.gd:109 swept_beam_hit`。
- `survivor/orion_weapon_overlay.gd:10 present`；`survivor/orion_weapon_overlay.gd:21 _draw`。
- `tests/test_orion_final_form.gd:9 run`；`tests/test_orion_final_form.gd:71 _measure_turn`；`tests/test_orion_final_form.gd:89 _check`。
- `tests/orion_lifecycle_case.gd:15 run`；`tests/orion_lifecycle_case.gd:143 _create_enemy`；`tests/orion_lifecycle_case.gd:149 _aircraft`；`tests/orion_lifecycle_case.gd:168 _on_kill`；`tests/orion_lifecycle_case.gd:173 _check`。
- `tests/orion_lifecycle_runner.gd:3 _ready`；`tests/orion_lifecycle_runner.gd:6 _run`。
- `tests/orion_visual_runner.gd:12 _ready`；`tests/orion_visual_runner.gd:17 _setup_boss_debug_scenario`；`tests/orion_visual_runner.gd:31 _process`；`tests/orion_visual_runner.gd:54 _capture_orion`；`tests/orion_visual_runner.gd:61 _bench_finish_now`。
- 共用接线：`survivor/the_crucible_boss.gd`、`events/boss_encounter_event.gd`、`survivor/boss_registry.gd`、`survivor/survivor_mode.gd`；导弹：`missile.gd`、`missile_params.gd`、`missile_manager.gd`；模型：`experiments/volume_aircraft_catalog.gd`、`aircraft_silhouette_catalog.gd`、`aircraft_renderer.gd`。
- `survivor/the_crucible_boss.gd:71 configure_debug_scenario`。
- `survivor/the_crucible_boss.gd:78 configure_orion`。
- `survivor/the_crucible_boss.gd:82 cleanup_orion`。
- `survivor/the_crucible_boss.gd:88 _begin_orion`。
- `events/boss_encounter_event.gd:278 _on_orion_arrival_requested`。
- `experiments/volume_aircraft_catalog.gd:2455 _build_orion_final_form`。
- `experiments/volume_aircraft_catalog.gd:2472 _build_orion_far_lod`。
- `experiments/volume_aircraft_catalog.gd:2494 _build_orion_fang`。
- 回归入口：`orion_final_form`、`orion_lifecycle`；真实终态同时进入默认 `lifecycle_gauntlet`。

## 独立 BOSS 战斗对照入口

测试协议与结果：[ORION 独立评估](../audits/2026-09-27-orion-independent-boss-comparison.md)。bench `boss_comparison`；Crucible 的 `orion_solo` 场景不生成王牌中队。

- `tests/boss_comparison_runner.gd:32 _ready`；`tests/boss_comparison_runner.gd:55 _setup_boss_debug_scenario`；`tests/boss_comparison_runner.gd:91 _setup_bench_scenario`；`tests/boss_comparison_runner.gd:105 _on_squad_leader_changed`；`tests/boss_comparison_runner.gd:114 _physics_process`；`tests/boss_comparison_runner.gd:166 _assessment_read_events`；`tests/boss_comparison_runner.gd:179 _assessment_aircraft`；`tests/boss_comparison_runner.gd:185 _assessment_snapshot`；`tests/boss_comparison_runner.gd:223 _assessment_screenshot`；`tests/boss_comparison_runner.gd:236 _bench_finish_now`。

## 全面战争独立试验场

规格：[full-war-prototype](../specs/systems/full-war-prototype.md)。主菜单第五项进入；`full_war`功能验收，`full_war_visual`实际派遣，`full_war_baseline`仅测试夹具恢复旧44单位负载。

| 文件 | 职责 | 入口 |
|---|---|---|
| `rts/war_ledger.gd` | 有限资源、阵亡权重、队列与互斥终态；只持有WeakRef。 | `register_unit` `living_units` `request` `live_count` `cancel` `refund` `tick` `finish` `shutdown` |
| `rts/full_war_mode.gd` | 东京湾场景装配、主动派遣后入场、双王牌接管、双方容量门。 | `_ready` `_prepare_ace` `_ensure_pilot` `_set_patrol` `_spawn_air` `_terrain_position` `_spawn_ship` `_spawn_ground` `_on_dispatch` `_deploy_second_ace` `switch_ace` `_physics_process` `_publish_snapshot` `_unhandled_input` `_try_takeover_after_leader_down` `_on_squad_leader_changed` `_on_player_died` `_on_player_leveled_up` `_spawn_starting_wingmen` `_migrate_ace_field_upgrades` `_on_war_ended` `_exit_tree` |
| `rts/war_command_panel.gd` | 实时Tab面板、后备派遣、地图快照与终局重试。 | `_build_ui` `_text` `_button` `_bar` `open` `close` `refresh` `_on_map_draw` `_on_map_gui_input` `_cancel_first` `_ace_order` `show_result` `_retry` `_menu` |
| `rts/war_sector_overlay.gd` | 控制区世界标记；仅控制权变化时重绘。 | `set_sectors` `_draw` |
| `tests/full_war_runner.gd` | 真实SceneTree功能/容量/终态与开局/交战/Tab分阶段墙钟剖面；接默认all。 | `_process` `_ready` `_run` `run_checks` `_capacity_case` `_run_profile` `_capture` `_check` |

建筑平移重绘误差门：`survivor/building_renderer.gd` / `consume_view_change`，默认维持旧门，仅全面战争装配启用屏幕误差预算；功能回归 `tests/full_war_runner.gd` / `run_checks`，默认全量接入 `tests/lifecycle_gauntlet_runner.gd` / `_run`。

## 地图交接安装与性能复现工具

- `tools/install_tokyo_map_handoff.py`：冻结M20 Release包的只读核验与拒绝覆盖安装；`digest`、`safe_path`、`load_manifest`、`inspect_existing`、`verify_archive`、`install`、`main`。
- `tools/run_tokyo_map_handoff.ps1`：绑定M20身份、隔离调用者AGL环境并经既有bench运行C1/C2/Near/FastWest/FastNorth，保留wrapper结果。
下载与验收边界见[当前运行地图复现](../handoffs/2026-10-14-current-map-runtime-repro.md)。

交接工具回归：`tools/test_map_handoff_delivery.py` / `DeliveryTests`，覆盖损坏包、路径逃逸、已有文件/锁保护、安装读回及模拟bench失败码与环境隔离；不需要实物地图或Godot。

## M20投影覆盖与逐帧交接诊断

旋转视野覆盖与屏外高楼保护：`rendering/tokyo_hlod_handoff.gd:151 covers_projection` / `rendering/tokyo_hlod_handoff.gd:165 _covers_projected_entry`；父子保守包络在 `rendering/tokyo_hlod_manifest.gd:203 tree` 加载期生成，原选页/绘制包络不变。

求解前的在途HLOD快速复用：`rendering/tokyo_map_planner.gd:334 _pending_hlod_covers` / `rendering/tokyo_hlod_overlay.gd:620 _pending_hlod_covers`；普通候选和桥接候选都按既有0.25秒预测检查目录及行级清晰度上限。无解原生回退的最小视野检查：`rendering/tokyo_hlod_overlay.gd:807 _select_native_fallback`，已有原生目标仍走原复用路径。回归：`tests/test_tokyo_hlod_stream.gd:1420 pending_hlod_expiry_checks`、`tests/test_tokyo_hlod_stream.gd:1463 projection_equivalence_checks`，经 `HLOD_STREAM_TEST` + `PROJECTED_COVERAGE_TEST` 聚焦入口，亦接既有all。

逐帧时序：`tests/tokyo_volume_combat_runner.gd:155 _process` / `tests/tokyo_volume_combat_runner.gd:289 _bench_finish_now`；选择状态由 `rendering/tokyo_hlod_overlay.gd:264 _step_geometry` 有界采集。`tools/run_tokyo_map_handoff.ps1 -Trace -Interactive` 显式开启；`-Counterfactual` 额外求解替代方案，不是性能基线。用法见[当前地图复现](../handoffs/2026-10-14-current-map-runtime-repro.md#逐帧诊断)。

## M20联合预算桥接

同池已有资源抵扣与保护带逐档核验：`rendering/tokyo_hlod_overlay.gd:770 _handoff_incremental_costs` / `rendering/tokyo_hlod_overlay.gd:737 _select_handoff_hlod`；完整树按新增物理费用求解：`rendering/tokyo_hlod_manifest.gd:314 select_handoff` / `rendering/tokyo_hlod_manifest.gd:353 incremental_tree`。显示费用和真实联合费用仍独立复核；失格哨兵不可因资源已在内存而降价。

共享父子页、半池以上可行切面、完整费用恢复与过期页反例：`tests/test_tokyo_hlod_stream.gd:1340 handoff_bridge_checks`；经既有投影覆盖 focused 与 all 入口。

快速放大下桥接资格与在途复用共用既有0.25秒预测视窗：`rendering/tokyo_hlod_overlay.gd:731 _handoff_bridge_qualified`；预测失格父页在完整树中提前细化，不拖延下一档加载。

旧视野完整时也允许等大或稍大的合格桥接，只要当前显示与候选的真实物理联合费用仍在原预算内。每档保护带在收窄前先尝试共享资源加权的完整树解；入口沿用两条选择路径的 `_select_hlod`、`_select_handoff_hlod`，`min_guard_px`限制返回同档或更宽的保护带，候选记录 `hlod_guard_shared`。快速路线选择轨迹导出沿用 `tests/tokyo_hlod_route_probe.gd` 的 `play_session`。

## 准备目录、后台地图规划与呈现前重绘

行为约束见[准备目录与后台流送](../specs/systems/tokyo-prepared-streaming.md)。HLOD默认在Loading准备纯值来源，游戏帧提交紧凑请求并重新验收后台结果；`AGL_TOKYO_SYNC_SELECTION=1`（复现工具的`-SynchronousSelectionControl`）保留显式同步对照，GridNative沿原路径。以下入口与回归范围不代表性能验收。

| 文件 | 职责 | 入口 |
|---|---|---|
| `rendering/tokyo_prepared_catalog.gd` | Loading/离线生成并验证来源、格式与算法身份绑定的资格区间；游戏帧只查精确区间，不从缺失缓存重建。 | `build` `validate` `roots_at` `cache_path` `load_or_build` `read` `write` |
| `rendering/tokyo_map_planner.gd` | 独占纯值来源与选择缓存，统一当前切面、原生回退、联合预算桥接和预测；在途HLOD快速复用先验未来资格，各保护带收窄前尝试共享资源加权，原生保护候选失败后保留仍完整合格的已提交切面，未来预取避免重复外推。 | `configure` `plan` `compact_cut` `_pending_hlod_covers` `_select_hlod` `_select_handoff_hlod` `_handoff_incremental_costs` `_select_native` `_predict_prefetch` |
| `rendering/tokyo_map_plan_worker.gd` | 一个后台任务槽；来源/请求隔离，未完成领取立即返回，完成结果按来源代次领取；退出/换源才等待。 | `configure` `busy` `ready` `submit` `take` `close` `summary` `_run` `pure` |
| `rendering/tokyo_hlod_overlay.gd` | Loading装配准备目录与规划器，空闲时重新采样最新请求；主线程重验revision、当前投影视野、清晰度、联合预算和资源就绪。逐帧运动采样在瞬切时清除平移/缩放历史；相同原生资源同步刷新保护元数据，零保护带采用更短重采样间隔；等待后台时先接替已就绪目标，再清理失格旧切面。 | `_step_geometry` `_selection_due` `_prepare_map_planner` `_planning_request` `_step_prepared_selection` `_admit_prepared_plan` `_refresh_native_guard_metadata` `_commit_ready_target` `_finish_display_step` `_exit_tree` `debug_state` |
| `rendering/tokyo_hlod_manifest.gd` / `rendering/tokyo_hlod_native.gd` | 显式后台上下文传入预算/epoch并复用准备树；原生选择快照仅含值，后台缓存不读取主线程帧状态。 | `background_selection` `selection_context_valid` `qualified_roots` / `selection_snapshot` `configure_selection_snapshot` `select` |
| `rendering/tokyo_hlod_handoff.gd` | 共享资源物理费用、当前/前探视野覆盖、清晰度与缩放方向的纯值判定；原生移动查询包含当前视野与预测倍率下的未来视野。 | `append_streaming_bundle` `streaming_bytes` `covers_motion_view` `covers_projection` `prediction_zoom_rate` `pan_lead` `zoom_out_padding` `native_motion_query` |
| `rendering/tokyo_native_predictor.gd` | 原生候选未来预取；`smooth_pan`按经过时间平滑逐帧速度，供默认后台规划入口和既有预测路径共用。 | `smooth_pan` `prepare` `request` `dispatch` `close` |
| `rendering/visual_redraw_queue.gd` | 合并同一呈现前的物理步重绘请求，保留最终状态；WeakRef排除已释放/退出节点，非物理请求保持立即排队。 | `request` `_flush` |
| `tests/test_tokyo_prepared_catalog.gd` | 准备区间与旧资格树差分，来源/格式/摘要/损坏缓存拒绝及只读失效行为。 | `checks` `cache_checks` `run` |
| `tests/test_tokyo_map_planner.gd` | 纯规划/同步差分、原生桥接、混合资格缓存、方向裁页和半池到全池重试；真实原生选择器验证移动/旋转覆盖、已有切面保留、资格/面数/物理预算拒绝、零缩放等价和预取不重复外推。可选安装M20诊断重放Near与C1请求，核对两视野共同切面、瞬切历史对照及物理资源去重后的联合费用。 | `GuardPool` `NativeRetentionOverlay` `differential_checks` `native_bridge_checks` `mixed_cached_hlod_checks` `directional_trim_checks` `guard_budget_retry_checks` `native_motion_guard_checks` `native_motion_retention_checks` `native_motion_query_checks` `native_motion_prefetch_checks` `native_joint_cut` `installed_native_gap_diagnostic` `installed_native_retention_diagnostic` `installed_native_motion_diagnostic` `c1_compact_trace_poses` `c1_compact_pair_bytes` `c1_compact_metrics` `installed_c1_compact_diagnostic` `run` |
| `tests/test_tokyo_selection_context.gd` | 显式上下文预算、缓存epoch、快照隔离、准备目录复用及真实后台调用。 | `manifest_checks` `native_checks` `prepared_checks` `run` |
| `tests/test_tokyo_hlod_stream.gd` | 共享物理资源交接、方向保护、缩远视口增长与预测入口等价；每档保护带收窄前验证共享费用解，普通在途HLOD同样受预测资格门约束。可选安装M20诊断核对FastNorth原请求、联合费用和后续实际覆盖。 | `MotionPlanProbe` `ZoomGuardPool` `ZoomForecastPlanner` `ZoomForecastOverlay` `motion_handoff_checks` `zoom_footprint_checks` `shared_zoom_source` `shared_zoom_guard_checks` `zoom_trace_covered` `zoom_trace_result` `installed_zoom_handoff_diagnostic` `handoff_bridge_checks` `pending_hlod_expiry_checks` `projection_equivalence_checks` |
| `tests/tokyo_map_plan_worker_case.gd` | 真实任务阻塞时非等待领取、单槽、错代次、延迟领取、非法值拒绝和退出/换源生命周期。 | `wait_ready` `run` |
| `tests/tokyo_map_admission_case.gd` | 真实SceneTree覆盖旧结果接纳、停止相机后重试、原生保护元数据刷新和零保护带重采样节奏；真实worker阻塞期间验证20/60/120Hz呈现的运动采样、瞬切历史重置及下一实际请求；另检查显示到期、视野移出、就绪接替、逐帧缩放反转和撤销旧降档。 | `Probe` `StreamProbe` `ReplyPlanner` `empty_display_trace_checks` `direct_checks` `stopped_camera_checks` `native_guard_metadata_checks` `native_guard_cadence_checks` `pending_motion_sampling_checks` `cold_jump_prediction_checks` `pending_display_checks` `pending_coverage_checks` `ready_before_clear_checks` `in_flight_zoom_reversal_checks` `ready_downgrade_reversal_checks` `revision_and_exit_checks` `run` |
| `tests/tokyo_map_planning_case.gd` / `tests/tokyo_map_planning_runner.gd` | 汇总准备目录、规划器、上下文、worker与接纳回归；bench `tokyo_map_planning`，亦接默认生命周期全量入口。 | `run` / `_ready` `_run` |
| `tests/visual_redraw_queue_case.gd` / `tests/visual_redraw_queue_runner.gd` | 多物理步到一次呈现的最终状态；14类真实调用者在draw信号处读取的字段与该帧最终物理状态一致，退出不绘制、重入/禁用节点消费最终状态；bench `visual_redraw_queue`，亦接默认生命周期全量入口。 | `CounterCanvas` `DrawProbe` `PhysicsStateSampler` `LifecycleCanvas` `LifecycleActions` `MountLockDriver` `run` `_test_frame_contract` `_observe` `_test_real_callers` `_test_lifecycle` / `_ready` `_run` |
