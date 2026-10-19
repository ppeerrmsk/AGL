# 代码索引

局部完整楼体移动 → `tests/tokyo_native_joint_preview.gd` / `run`复用实际通道建网格，地表/保留楼/候选侧墙同屏、移动首帧与稳定帧对照，释放检查；`tests/tokyo_vector_roof_compare.gd` / `run`显式分派。

组合减面GPU对照 → `tests/tokyo_local_roof_gpu.gd` / `build`独立encoded_indices绑定校验，原始控制与简化候选拓扑分离。

屋顶局部坐标解码 → `tests/tokyo_local_roof_gpu.gd` / `build`，八字节顶点与RGBAF街区表，实际通道费用和GPU画面对照，正式路径不变。

屋顶减面同位对照 → `tests/tokyo_vector_roof_compare.gd` / `run`，显式vector_roof_compare入口，默认单面、双面须显式诊断；真实原始几何与保存候选GL截图，不改正式地图。

实际分层纹理候选 → `tests/tokyo_layered_sampler.gd` / `sampler_code` / `build` / `apply_updates`，逐行补丁与可选移动相机回调的同姿态更新前后对照；`tests/tokyo_boundary_commit_preview.gd` / `run`显式moving_layer_updates，节奏绑定更新，非任意速度就绪保证；正式默认不变。

浮点层回读定位 → `tests/tokyo_texture_update_probe.gd` / `sample_layered`，整行各通道双层shader采样对拍，非地图覆盖。

分层纹理更新 → `tests/tokyo_texture_update_probe.gd` / `run_layered`，真实127补丁三格式有限层更新与未修改层回读，正式路径不变。

纹理更新接口诊断 → `tests/tokyo_texture_update_probe.gd` / `run`，真实接口签名、三格式同RID更新与回读，显式texture_update_probe入口，正式路径不变。

局部来源包络与连续路线 → `tests/tokyo_boundary_commit_preview.gd` / `local_state` / `run`显式continuous_local及route_x_offset，容量取绑定三层；中心/缩放范围先拒绝再提交。路线像素稳定不替代独立来源覆盖。

四状态全部有向交接 → `tests/tokyo_boundary_commit_preview.gd` / `run`显式four_ready，不加载旧差分/不另分配双输出；原预算内候选所有权替换，12边首帧/稳定帧/114摘要对照。

突发请求等待帧 → `tests/tokyo_boundary_commit_preview.gd` / `prepare_upload` / `run`显式audit_pending，记录每帧旧资源在目标姿态的摘要并对照目标就绪结果，只作缺口反例，不代替独立全图覆盖。

离线展开索引按需加载 → `tests/tokyo_boundary_commit_preview.gd` / `prepare_upload` / `run`，直接读目标状态三层定长上传文件，长度/SHA先验，取消无半成品；显式候选不改变正式地图。

有限时间片准备 → `tests/tokyo_boundary_commit_preview.gd` / `prepare` / `run`，最多2000us调度目标、4096索引段后检查，记录越界与非分段收尾；实际GPU提交前取消像素不变，不认证准备期间覆盖。

局部可见隔离预览 → `tests/tokyo_boundary_commit_preview.gd` / `interactive` / `run`，显式有限输入窗口，左右平移与上下缩放，仅已准备双状态；不是完整覆盖或用户验收结论。

细节恢复阈值交接 → `tests/tokyo_boundary_commit_preview.gd` / `run`显式cross_zoom，同中心双状态三层同帧提交，准备好后连续缩放对拍。

地表高度修复保存 → `tests/tokyo_selectable_geometry_save.gd` / `run`显式single_layer_repair；默认三层合同不变。

边界包实景接入 → `tests/tokyo_boundary_commit_preview.gd` / `pose` / `prepare` / `run`，partition显式boundary_commit_preview入口，实际三层更新、共享纹理采样、稳定/空白对照与资源释放。

候选整包加载释放：`tests/tokyo_staged_resource_probe.gd` / `run`的fixed_cpu_files显式分支，复用保存资源并记录阶段计数；计数不是驱动峰值上界。

稀疏纹理槽拒绝：`tests/tokyo_sparse_mip_sampler.gd` / `sampler_code`，read_tile在mip访问前检查槽编号、mip数量及区间；显式诊断不接正式地图。

差分跨帧取消 → `tests/tokyo_index_recipe_probe.gd` / `run_segmented_frames`，每流真实帧后取消及重新准备发布；只认证CPU值，不认证渲染交接。

差分分段准备 → `tests/tokyo_delta_preparation.gd` / `begin` / `step` / `ready` / `take` / `cancel`；`tests/tokyo_index_recipe_probe.gd` / `run_segmented`核实际流和取消拒绝，未验证跨帧性能。

差分索引还原 → `tests/tokyo_index_recipe_probe.gd` / `decode_delta` / `run_delta`，16位差分/32位逃逸、有界输出及12实际流对拍；不认证实景或峰值。

扩域压缩配方交接 → `tests/tokyo_nine_domain_preview.gd` / `choose` / `run`，显式recipe_indices路径加载共享源/片段、核还原摘要及16位索引转换，三层就绪后同帧更新；旧合同不变。

共享索引片段还原 → `tests/tokyo_index_recipe_probe.gd` / `digest` / `load_bytes` / `assemble` / `run`，54状态字节对拍及非法范围拒绝；不认证物理峰值或FPS。

侧墙临界恢复 → `tests/tokyo_nine_domain_preview.gd` / `choose` / `run`显式恢复合同校验覆盖证书、压缩索引与恢复阈值，同帧提交索引/缩放，完整状态另做原形控制帧，不放宽旧单档合同。

九域原子交接对拍 → `tests/tokyo_nine_domain_preview.gd` / `digest` / `choose` / `run`经partition显式nine_domain_preview请求，验证三层索引同步更新、域外拒绝及移动/稳定画面一致；只覆盖绑定九域。

保存包阶段存活 → `tests/tokyo_staged_resource_probe.gd` / `counters` / `run`经partition显式staged_resource_probe请求，在几何/纹理/释放边界记录真实GL资源计数、CPU工作区与弱引用，不授予192MiB峰值或画面资格。

可选择几何实物 → `tests/tokyo_selectable_geometry_save.gd` / `unpack` / `build` / `run`校验压缩来源、共同容量补零及ArrayMesh打包通道保存回读，经`tests/tokyo_partition_stream_probe.gd` / `run`显式selectable_geometry_save分派。只有几何，不当纹理/显示/内存峰值完成。

无损位编码完整mip → `tests/tokyo_bitpacked_mip_compare.gd` / `run`同源旧/新编码GL对拍；`tools/tokyo_sparse_mip_payload.py` / `build`显式制作开关；`tests/tokyo_sparse_mip_sampler.gd` / `sampler_code`先解码再过滤，支持9/10行游程，显式共享清单支持17/18/21/22/24/26同载荷调色板指针，缺块/未知新模式显式诊断。正式默认不变。

位编码GL像素门 → `tests/tokyo_bitpacked_pixel_probe.gd` / `run`：绑定保存载荷、Shader及逐块摘要，七模式精确回读与对象释放；`tests/tokyo_partition_stream_probe.gd` / `run`显式分派，不接正式地图。

住宅连续移动缩放 → `tests/tokyo_residential_continuous.gd` / `prepare` / `route` / `rejection_checks` / `digest` / `run`：真实位置选域、13类拒绝、移动首帧与独立稳态重放；`experiments/tokyo_cell_index_selector.gd` / `select`仅对显式已核区间包接受连续scale，旧单尺度行为保持。

住宅已存资源加载 → `tests/tokyo_residential_saved_load.gd` / `load_saved` / `live_count` / `run` / `preview`：三网格/四索引/两材质身份与释放，显式GL四域三尺度对拍，已知结构费用非驱动实测；显式分派在`tests/tokyo_partition_stream_probe.gd` / `run`。

住宅区间资源回读 → `tests/tokyo_residential_packet_audit.gd` / `bytes` / `valid_contract` / `run`：完整属性原生网格、四域索引与两组稀疏平面；覆盖/纹理合同须绑定同包，逐平面一致；共同容量可低于预算上限，拒绝零容量/联合超限，8类合同反例；显式分派在`tests/tokyo_partition_stream_probe.gd` / `run`。不接正式默认，不提供Visual资格。

规格302住宅逐源七档导出：`tests/tokyo_residential_native_costs.gd` / `run`；显式请求分派：`tests/tokyo_partition_stream_probe.gd` / `run`。工厂重放不等于正式删除映射或性能通过。

音频退出播放引用检查 → `tests/tokyo_audio_exit_probe.gd` / `run` / `_capture_playbacks`；`tests/tokyo_partition_stream_probe.gd` / `run`显式audio_exit_probe分派。通过不等于正式退出门修复。

连续域合法索引选择 → `experiments/tokyo_cell_index_selector.gd` / `select`；`tests/test_tokyo_cell_index_selector.gd` / `run`检查原始float32相机位置和资源状态，`tests/tokyo_envelope_visual_review.gd` / `_route`可消费route_poses调用选择器而非按采样点套索引。

邻域候选首帧一致性 → `tests/tokyo_envelope_visual_review.gd` / `_route`：记录预载索引数/字节及零路由文件读；GPU读回诊断不得当作严格帧时间证据。

分块地图候选合批 → `tests/tokyo_sparse_mip_sampler.gd` / `build_map`：共享材质和944平面几何，UV2保存去重纹理ID；`tests/tokyo_envelope_visual_review.gd`拆层诊断同样使用texture_index，防止把平面序号当纹理序号。

分块RGBA无损采样 → `tests/tokyo_sparse_mip_sampler.gd` / `build` / `sampler_code`：按字地址读局部调色板/纯色/原RGBA，跨块过滤读取相邻像素各自块描述；测试GL通过不等于空间/深度覆盖通过。

完整邻域无损稀疏mip → `tools/tokyo_sparse_mip_payload.py` / `encode_block` / `decode_block` / `build`：逐块选择表示，源像素不改，四份纹理数据含行填充，尚不代表GPU采样通过。

共享几何与图集联合实物费 → `tests/tokyo_envelope_resource_audit.gd` / `run`：可选atlas输出原生/平面/纹理与索引持有策略字节，joint_budget_verified始终false直至独立完整验收。

正式来源局部成本导出 → `tests/tokyo_export_joined_layers.gd` / `run`：export_layers/export_keys显式选层选页；默认全低楼/地表，局部输出不得冒充全图属性覆盖。

实际mip混合R8/RG8打包 → `tools/tokyo_mixed_palette_atlas.py` / `pack_rectangles` / `save_array` / `build`：颜色索引无损还原、无硬件mip、完整文件字节含打包空隙和metadata。

闭合纹理对应原生余量生成输入 → `tools/tokyo_prepare_native_remainders.py` / `removal_ids` / `build`：终态闭合前拒绝，原生保留集不能删除，按20万来源面分批复用已验证引擎资源生成器。

重烘集合到后继回退集合 → `tools/tokyo_advance_layer_closure.py` / `face_contract` / `verify_replacement` / `build`：来源/高度多重集合守恒、空间边界不漂移、保留原面不再烘入纹理。

回退闭合后的局部纹理重制 → `tools/tokyo_rebake_layer_fallback.py` / `split_members` / `build`：保留原面不得同时存在于新纹理，新增回退须再次闭合。

跨图块原面保留与重烘 → `tools/tokyo_layer_fallback_closure.py` / `mark_group` / `build`：全批完整性门、全局保留索引和重烘清单。

全图实际分层纹理 → `tools/tokyo_bake_full_layer_batch.py` / `build`：有界批次、真实高度、共享来源、缩放清晰度上限与原生回退记录。

全图水平面候选与接缝来源 → `tools/tokyo_full_layer_plan.py` / `eligible` / `tile_sources` / `build`：逐页原面索引与按世界块完整来源收集，不删除几何。

正式全图低楼/地表属性 → `tests/tokyo_export_joined_layers.gd` / `run`：复用export_payload，绑定三层目录、保留高楼原生。

正式三层源闭合与费用 → `tests/tokyo_joined_layers_catalog.gd` / `run`：绑定全图建筑和地表归并，逐源验证三层面数、物理身份去重。

正式地表格网制作 → `tests/build_tokyo_current_grid_batch.gd` / `run`：显式ground_only分支，共用原面属性守恒检查。

正式格网来源闭合 → `tests/build_tokyo_grid_dependencies.gd` / `run`：全片消费唯一性、层面数守恒与缺省原生地表分类。

证书边界交接首帧 → `tests/tokyo_envelope_visual_review.gd` / `_route`：相机与索引同段提交、首帧/稳定帧及第二遍原图对照。

独立过滤器对照 → `tests/tokyo_isolated_sampler_review.gd` / `run`：probe_tiles选择混合R8/RG8样本，同UV独立纹理与图集采样，颜色/alpha分别读回；不验证深度或全图。

Shader致命诊断 → `bench/invoke_godot.ps1` / `Get-BenchRuntimeErrorBlocks`；回放与负对照见`tools/test_bench_shader_gate.ps1`。

独立mip测试材质 → `tests/tokyo_independent_mip_batch.gd` / `build`：显式LOD采样、元数据查表、两实例候选构建。

纹理逐级像素源 → `tests/tokyo_texture_mip_export.gd` / `run`：显式Headless导出，复用原图生成mip并逐片核三份费用。

包络候选实景 → `tests/tokyo_envelope_visual_review.gd` / `run`：显式Visual入口、索引更新与三姿态负对照。

包络资源费用 → `tests/tokyo_envelope_resource_audit.gd` / `run`：mesh逐角回读摘要、实际解码字节与纹理三份费用。

固定容量索引完整视野 → `tests/tokyo_index_hybrid_review.gd` / `run`：三原生批次+分层纹理，与实际原资源同位比较，预留槽计入提交预算。

索引缓冲GPU验证 → `tests/tokyo_index_update_probe.gd` / `run`：实际渲染器与左右三角读回；不操控桌面、不接正式地图。

选择性分层原生余量 → `tests/tokyo_selective_native_cost.gd` / `run`：SHA绑定选择与源导出，逐角守恒、完整组件费用和保存回读；非正式运行入口。

联合分层制作输入 → `tests/tokyo_triangle_visibility_audit.gd` / `count`，单姿态三层实际组件属性导出；旧无导出诊断范围不变。

墙背面提交候选 → `tests/tokyo_layered_roof_review.gd` / `wall_bins`，几何法线与实际投影射线判定，组内任一正向即保留；只用于显式GPU对照。

屋顶分层实景对照 → `tests/tokyo_layered_roof_review.gd` / `run` / `mesh_from_bytes` / `difference`，源SHA、真实层高、同位GL读回与空白负对照；正式F5不启用。

当前地表属性提取 → `tests/tokyo_grid_native_case.gd` / `run`的component_attribute_export与component_slot，SHA绑定资源并只导出指定槽，不改变显示目录。

楼栋失配诊断输入 → `tests/tokyo_block_source_match.gd` / `run`的export_current，真实组件属性连续导出，来源绑定与组件去重后计数。

格网原生来源追踪 → `tests/tokyo_grid_native_case.gd` / `run`的source_trace_rect；读取grid绑定快照、窗口叶和物理映射，用于排查候选来源不匹配。

避免重复合并旧来源 → `tests/tokyo_block_source_match.gd` / `keys` / `run`，完整属性或仅位置的有向三角计数匹配；只有完整匹配才满足此单项，仍不代替视觉与覆盖验收。

块面真实网格费用 → `tests/tokyo_grid_native_case.gd` / `run`的block_source_candidate；复用来源Factory与保存回读，variant编号不等于LOD档位，正式来源保护与连续显示另验。

原生属性导出/来源屋顶样件 → `tests/tokyo_grid_native_case.gd` / `run`的component_attribute_export与roof_detail_candidate；绑定SHA、两档实物回读，不构成原片等价替换或全图验收。

高楼/地表屏外过绘 → `tests/tokyo_triangle_visibility_audit.gd` / `count`；从spatial_group_audit的triangle_visibility调用，实际Mesh逐三角包络投影，不授予实时裁剪或像素等价。

双档空间块样件 → `tests/tokyo_shared_lod_cells.gd` / `run` / `position` / `save_cell`；shared_lod_cells显式离线入口，九格或all_cells完整源根逐档守恒与真实包围盒；`tokyo_spatial_group_audit.run`核shared_low_cells联合下界，只可拒绝超门组合，不自动接入流送。

双档单Mesh样件 → `tests/build_tokyo_shared_lod.gd` / `run` / `pack_indices`；grid_native_case的shared_lod_point显式离线入口，原数组守恒和解码费用，不证明实际缩放选档。

中近景实际几何去重候选 → `tests/tokyo_shared_mesh_audit.gd` / `run` / `register` / `mesh_sha`，从grid_native_case的mesh_share_audit分派，源资源校验后逐数组摘要；完整清单与批次范围分别保存，不能用部分样本声称全图收益。

单一驻留基底选择审计 → `tests/tokyo_grid_native_case.gd` / `run`的resident_basis，`rendering/tokyo_grid_native.gd` / `refine_entries`强制细片分支，拒绝用未驻留整格/中间地表节点补预算。仅离线，不授予F5资格。

固定空间组合引用守恒 → `tests/tokyo_spatial_group_audit.gd` / `run`，经grid_native_case的spatial_group_audit分派；不把逻辑合页当draw减少。

保存缺口驻留费用 → `tests/tokyo_residency_gap_audit.gd` / `run`，摘要绑定原报告，物理身份去重，不以缺件并集代替全部接替或全图资源；经grid_native_case的residency_gap_audit分派。

有损地表合同错源拒绝 → `tests/build_tokyo_simplified_ground.gd` / `rejection_checks`，三种输入错误不得部分登记；随后同一实例恢复合法输入并复算路线。

有损候选证据绑定与原子目录接入 → `rendering/tokyo_simplified_ground.gd` / `read_json` / `attribute_sha` / `attach`，在加载阶段核原正式网格属性、候选根属性与离线证明，复用子树守恒后登记；`rendering/tokyo_grid_native.gd` / `read`独立候选字段，禁止冒充无损ground_partition。

局部回退后跨层连接门 → `tools/verify_tokyo_ground_connections.py` / `verify_sources`，联合STRtree包络查询所有变化线与其他线，保留完整DE9IM关系、共享顶点及端点，不仅统计线数量。

最终地表超距定位与局部恢复 → `tools/locate_tokyo_ground_error.py` / `locate`，基于真实超距集合定位源paths/roads；`tests/build_tokyo_path_replay.gd` / `run`通过reuse_original复用已验证原始回放。回退后仍必须独立检查最终几何与连接关系。

生成后地表误差认证 → `tools/verify_tokyo_simplified_ground.py` / `verify`，直接对原/候选三角并集检查双向集合距离，其他层按同向角多重集核对；`tools/test_verify_tokyo_simplified_ground.py` / `GeneratedGroundTests`。源折线报告不能覆盖此门。

自动原生档有解回退 → `rendering/tokyo_grid_native.gd` / `select`，自动请求且首选超预算才查询lod5，仍核native_qualified和原预算；不是预取或已提交覆盖证明。

简化候选保存路线成本门 → `tests/build_tokyo_simplified_ground.gd` / `install_cost_candidate`与`tests/tokyo_grid_native_case.gd` / `run`；复用真实选择器但只诊断，输出候选分区身份及质量未验证标识，不能把存在合格LOD选项当作自动交接通过。

新候选地表空间划分 → `tests/build_tokyo_simplified_ground.gd` / `partition` 校验组件和属性绑定后复用既有分页器，记录候选守恒基准，不放宽旧分区合同。

候选地表原生资源与实际缓冲成本 → `tests/build_tokyo_simplified_ground.gd` / `run`；校验属性/证明摘要、面数、有限数及保存回读属性，输出单独身份。不是无损 ground_partition 证明或运行时接入。

联合路径/次级道路减面 → `tools/build_tokyo_minor_road_candidate.py` / `build`；`tools/review_tokyo_path_candidate.py` / `ribbon`、`within_ribbon_error`支持实际宽度，`assemble`支持来源绑定的base与minor；`tests/build_tokyo_path_replay.gd` / `run`验证city来源和真实裁分。候选算术预算不等于选择器、交接或正式运行通过。

路径重放与正式地表逐角一致性 → `tools/review_tokyo_path_candidate.py` / `assemble`；旧分区来源由`tests/build_tokyo_path_replay.gd` / `run`校验cell_index摘要及source_hash。保留非目标层，实际候选费用与切面推算分开记录。

路径简化误差与回放 → `tools/review_tokyo_path_candidate.py` / `review` / `ribbon` / `within_ribbon_error`；同源引擎线带制作入口`tests/build_tokyo_path_replay.gd` / `run`由`tests/tokyo_partition_stream_probe.gd` / `run`的path_replay分派。源与候选分别保存，未经生产内部切分回放不得冒充正式成本。

失败地表细碎线带源候选 → `tools/build_tokyo_path_candidate.py` / `build`，生产登记绑定ground/city、复用折线简化并锁记录连接点；输出源JSON候选及未裁切面数估算，不代表实际网格减面或F5通过。

纹理裁空到真实地表网格映射 → `tools/pack_tokyo_layered_ground.py` / `quad_vertices`，纹理padding不能扩大geometry_bounds，保留高度；`pack` 输出分层网格文件，`tools/test_tokyo_layered_ground.py` 验证UV、绕序和边界。

分层纹理减少空白与材质批次 → `tools/pack_tokyo_layered_ground.py` / `crop_pixels` / `pack`；源摘要绑定、逐高度图集、全基级像素回读、不混淆mip估算和实际GPU资源。原几何所有权保留在source字段，裁切与图集像素映射独立登记。

降低静态地表面数的制作候选 → `tools/build_tokyo_layered_ground.py` / `build`、`layer_pixels`；源SHA绑定、分层纹理、面数/未合批surface/纹理mip成本，测试`tools/test_tokyo_layered_ground.py` / `LayeredGroundTests`。近景/覆盖/运行时验收独立，不从理论成本推算FPS。

地表表示是否有预算内解 → `tests/tokyo_grid_native_case.gd` / `run`的ground_cost_model，固定建筑表示后枚举现有地表树前沿，明确无解范围，避免盲目再分块。

后台完成时目标变化 → `rendering/tokyo_cell_stream.gd` / `_collect_completed` / `summary`；反例 `tests/test_tokyo_hlod_stream.gd` / `idle_completion_checks`，保留预算、来源校验和关闭释放，不增加预测范围。

地表分区载入期认证接入 → `rendering/tokyo_ground_partition.gd` / `attach` / `conserved` / `find_entry`；入口`rendering/tokyo_grid_native.gd` / `read`的ground_partition，缺源/错摘要/非守恒拒绝，先完成检查再更新目录。

地表分区覆盖与邻域反例 → `tests/tokyo_ground_split_review.gd` / `run`，`tests/tokyo_grid_native_case.gd` / `run`的ground_split_review入口；49原生及1常驻接替与运行时资格分开报告。

单地表空间分区制作/成本对照 → `tests/tokyo_ground_split_candidate.gd` / `run` / `replace`，入口`tests/tokyo_grid_native_case.gd` / `run`的ground_split_candidate；保存新分区仅tmp，覆盖树与流送接入另验。

地表精确重复面候选 → `tests/tokyo_ground_duplicate_candidate.gd` / `run`；`tests/tokyo_grid_native_case.gd` / `run`显式ground_duplicate_candidate入口。输出仅tmp，保持正式资源不变。

正式16页接替可行性反例 → `tests/tokyo_prefetch_replay_case.gd` / `run`的handoff_feasibility；分别记录native面数/字节/页数/预算资格及foundation_options，不混淆候选预算与正式接入。

同LOD父子预取反例重放及有界未来裸视野对照 → `tests/tokyo_prefetch_replay_case.gd` / `run` / `vector`；入口 → `tests/tokyo_grid_native_case.gd` / `run`的prefetch_replay。费用仅为候选物理网格去重和，不等于完整驻留/贴图交接合格。

需求摆动缓存软保留实验 → `rendering/tokyo_hlod_stream.gd` / `_prune_lru` / `close`；确定性到期与满池反例 → `tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`。默认不开启，不改变真实预算和显示资格。

来源令牌去重复展开 → `experiments/tokyo_source_mask_index.gd` / `configure` / `covered`；冻结层掩码直达最终来源 → `experiments/tokyo_grid_coverage_index.gd` / `_refined_masks` / `compile_sources` / `covered_sources`；共享令牌与重叠叶片反例 → `tests/test_tokyo_grid_coverage.gd` / `mask_checks` / `checks`。

地图提交来源核验去全局投影扫描 → `experiments/tokyo_grid_coverage_index.gd` / `configure` / `_build` / `_visible` / `refined_layers`；初始化/消费 → `rendering/tokyo_grid_native.gd` / `read` / `covered`；新旧来源层差分 → `tests/test_tokyo_grid_coverage.gd` / `index_checks` / `refinement_checks` / `checks`；覆盖CPU子桶 → `rendering/tokyo_hlod_overlay.gd` / `_bind_target`，末端诊断导出 → `tests/tokyo_wasd_audit.gd` / `run`。

地表逻辑页约束诊断 → `tests/tokyo_grid_native_case.gd` / `run`的ground_frontier；取消候选近景烘焙地表交接 → `rendering/tokyo_grid_native.gd` / `read` / `select`的grid_native_ground_only。正式F5页限与默认包保持不变。

独立地表启动接入 → `rendering/tokyo_ground_catalog.gd` / `attach` / `rewrite`，经`rendering/tokyo_grid_native.gd` / `read`显式绑定；实际缓存旧依赖拒绝 → `tests/tokyo_grid_native_case.gd` / `run`。

地表专用加载视图 → `rendering/tokyo_ground_page.gd` / `assemble` / `View.stream_identity`，由`rendering/tokyo_component_page.gd` / `assemble`显式分派；同池加载反例与释放 → `tests/tokyo_ground_stream_case.gd` / `run`。

剥离地表页未绘制楼栋依赖 → `tests/build_tokyo_ground_components.gd` / `run`制作独立组件；`tests/tokyo_grid_native_case.gd` / `run`的ground_sources记录物理目录/mapping/显示mask供核对，不能仅减账本冒充已卸载。

地表组合可行性 → `tests/tokyo_grid_native_case.gd` / `run`的ground_mix/ground_mix_depth，保留原来源树完整覆盖证明，诊断退出0不代表组合有解。

显示费用分层 → `tests/tokyo_grid_native_case.gd` / `run`的cost_breakdown/use_native_ground；地表与建筑分别记面数、费用，原生对照仍须原预算和覆盖门。

区分显示预算拒绝与加载等待 → `tests/tokyo_grid_native_case.gd` / `run`的feasibility_only；精确包绑定、实际尺度、基础层和原生档位分别记录，不作为Visual或性能证据。

实测包容量与来源包区分 → `tests/tokyo_grid_native_case.gd` / `run`，inventory_only/package_override检查当前包身份并物理路径去重；不得把低于4GiB清单费用等同于全缩放基础显示合格。

512原片的无损256细分 → `tests/build_tokyo_grid_detail.gd` / `run`；`rendering/tokyo_grid_detail.gd` / `expand`；`rendering/tokyo_grid_native.gd` / `read`在固定细片视图创建前展开认证子块，仍沿refine_entries择必要层、同Stream计费，正式无grid_detail不变。coverage依赖同时展开，非缓存等同显示。

组件成本与真实入镜范围区分 → `tests/tokyo_grid_selection_case.gd` / `run`，geometry_breakdown/triangle_visibility/split_256显式诊断；保守屏幕盒非遮挡结果，分桶复用原partition/conserved，不改变美术或正式LOD选择。

只加载切面所需原片 → `rendering/tokyo_grid_native.gd` / `subset_entries` / `retire_subsets`；`rendering/tokyo_component_stream.gd` / `register_grid_subset` / `retire_grid_subsets`，不可变子集身份、128登记上限、已认证物理路径复用、在途/旧显示保护；`tests/tokyo_grid_stream_case.gd` / `subset_registry_checks`及`tests/tokyo_grid_native_case.gd` / `run`验登记后实际加载/绑定，非Visual验收。

近景原生地面与空切面安全 → `rendering/tokyo_grid_native.gd` / `select`；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_select_native` / `_predict_prefetch`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`核空结果不崩溃且允许已批准预算重试，非连续画面验收。

新格目录→联合选页→覆盖→实际提交 → `rendering/tokyo_grid_native.gd` / `read` / `read_bound` / `ground_only` / `select` / `refine_entries` / `covers_visible_layers` / `covered`；显式native.grid_candidate，固定粗细描述符、必要边缘细分、逐原片覆盖。`tests/tokyo_grid_native_case.gd` / `run`通过grid_native入口验证真实绑定、缺页/缺片拒绝、稳定身份与粗细交接费用；投影上下文仅从真实包络证明屏外分片，不伪造提交；默认包不启用。

新格联合地表真实成本 → `tests/tokyo_grid_selection_case.gd` / `run` / `ground_tree` / `compare_queries`，grid_selection入口；原地表资源字节不因隐藏建筑层而扣除，联合预算和covers_ground检查。支持实际尺寸多姿态拒绝归因、最低地表前沿、原片选择性细分的面数/新增绘制估算，非运行时接入或GPU验收。

新格空间候选与全扫描差分 → `experiments/tokyo_grid_query.gd` / `build` / `query`；真实AABB跨格索引、8单位边距及高楼/阴影逆投影，复用原Select.visible，避免每次遍历全部空间格。

新格同池加载装配 → `rendering/tokyo_grid_page.gd` / `assemble` / `assemble_group` / `assemble_segmented`，ComponentPage显式tokyo_grid_view路由；`tests/tokyo_grid_stream_case.gd` / `run` / `inspect` / `inspect_group` / `inspect_binding`经grid_stream验证单层/schema2同格双层/schema3原片集合。`rendering/tokyo_hlod_overlay.gd` / `_bind_native_entry`复用正式逐层/逐片绑定，保留高楼材质分派，不授予整切面覆盖资格。

新格提交到旧来源资格 → `experiments/tokyo_grid_coverage.gd` / `source_layers` / `covered_sources` / `refinement_data` / `refined_layers`，`tests/test_tokyo_grid_coverage.gd` / `checks` / `refinement_checks`；缺可见片或显示层不发原来源token，粗细重复提交、未知身份和重叠面区间拒绝。接原source coverage测试及显式grid_coverage_checks入口，不自动隐藏正式建筑。

新格完整来源接合 → `tests/build_tokyo_grid_dependencies.gd` / `run` / `read`，grid_dependencies显式入口，核原分片恰好一次与完整叶层面数；依赖表保留原覆盖凭据但hide_authorized=false，尚未接运行时。

完整来源跨叶归并 → `tests/build_tokyo_joined_grid.gd` / `run` / `run_series`，partition_stream的joined_grid/joined_grid_series显式入口；每格合并不改变原packed属性，连续面区间绑定原批次逐面owners，逐组件保存回读，非正式安装包。

完整来源格网分批制作：`tests/build_tokyo_current_grid_batch.gd` / `run` / `run_series`，current_grid_batch/current_grid_series显式入口；来源摘要、叶范围、512固定格、分桶前后及保存后逐角守恒、批次Variant回读，输出仍非安装包。

完整当前树制作输入：`tests/export_tokyo_current_sources.gd:6 run`，partition_stream的current_sources入口；来源是当前替换树而非原目录或相机切面，保留正式建筑及地表合同，实际几何SHA仍须消费时校验。

多来源地表消费适配：`rendering/tokyo_native_ground.gd:7 surfaces`；`rendering/tokyo_hlod_overlay.gd` / `_bind_ground_surface`。全纹理就绪、最严格尺度及逐面平面费用由`tests/test_tokyo_hlod_stream.gd` / `native_resident_tree_checks`覆盖；目录/覆盖资格接入仍未完成。

固定格离线资源保存/回读：`tests/build_tokyo_grid_resources.gd:9 run`，校验来源摘要，建筑通道守恒和地表顶点/UV/索引保存一致；由partition_stream显式grid_resources派发，不是正式流送接入。

固定网格离线联合成本 → `tests/tokyo_native_massing_cost.gd` / `run` / `_export_layer`，layer0_export与wall_export/ground_export互斥并核对应层面数。

大组合计算悬崖 → `experiments/tokyo_spatial_cut.gd` / `_combine_sweep` / `_pareto_costs`；跨批差分`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`；真实保护带回放`tests/tokyo_handoff_selection_probe.gd` / `run`的size，WASD峰值沿既有LOADED_PHASE_TRACE开关记录。

消除父子前沿重复筛选 → `experiments/tokyo_spatial_cut.gd` / `_merge_parent`；原_insert完整结果差分`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

组合候选排序开销 → `experiments/tokyo_spatial_cut.gd` / `_ordered_costs`：安全64位编码与极端输入比较回退；差分/溢出边界`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

选页组合CPU热点 → `experiments/tokyo_spatial_cut.gd` / `_combine_sweep`；完整候选及稳定顺序差分`tests/test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`与`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。同输入CPU证据走`tokyo_handoff_selection_probe.gd` / `run`。

固定选页CPU查询 → `tests/tokyo_handoff_selection_probe.gd` / `run`的profile_selection输入；记录冷查询墙钟及solver/visible/combine嵌套桶，不能相加冒充CPU/GPU总帧。

缩远地表预取身份 → `rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch`；资格来源`tokyo_hlod_native.gd` / `ground_configuration`；实际函数回归`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`，不改变显示或交接预算。

原生32页bench候选 → `rendering/tokyo_hlod_manifest.gd` / `resolve_native_page_limit` / `native_page_limit`；选择及缓存`tokyo_hlod_native.gd` / `select`，保留`tokyo_hlod_handoff.gd` / `retain_display`，预测`tokyo_native_predictor.gd` / `request` → `tokyo_cut_worker.gd` / `submit` → `tokyo_cut_job.gd` / `run`。正式16页不变，不能把候选门控测试当成实景交接验收。

边缘叶无损细分可行性 → `tests/tokyo_handoff_selection_probe.gd:110 edge_refinement_audit` / `_optimistic_new_ground`，记录三层费用、实际选页及新孩子/全节点地表完整重选下界（忽略所有字节成本），并比较48/96/192像素保护带；范围覆盖与预算分别判定，原树hash不变。不代表实装或性能通过。

失败缓存逐页混合表示求解 → `tests/tokyo_handoff_selection_probe.gd` / `mixed_audit` / `_mixed_frontier`；16页、24万面及192MiB不变，未驻留候选仍保留超预算哨兵，覆盖与就绪分别记录。仅离线诊断，不授予运行时通过。

原生缺层定位 → `tests/tokyo_wasd_audit.gd` / `layer_gaps` / `_collect_layer_gaps` / `layer_gap_snapshot`；反例复用 `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks` 的移动后高楼mask遗漏，用精确数值而非显示字符串保留现场。失败缓存身份→`run`的resident_snapshot；只读复算→`tests/tokyo_handoff_selection_probe.gd` / `run`可选resident_components/resident_textures，不代表GPU提交或联合内存验收。

投机图已解码但等待GPU时归还读取槽 → `rendering/tokyo_hlod_stream.gd` / `_decoded_capacity` / `_detach_speculative`；`tests/test_tokyo_hlod_stream.gd` / `decoded_slot_checks`。同池同上限，独立计数，默认关闭。

空槽且预算足够的当前请求优先 → `rendering/tokyo_hlod_stream.gd` / `visible_dispatch_ready`；`tests/test_tokyo_hlod_stream.gd` / `visible_dispatch_checks`。不扩大父级额度，不越过阻塞前项；与已撤回的满槽候选不同。

撤销预取重复解码 → `rendering/tokyo_hlod_stream.gd` / `_keep_decoded` / `_release_decoded`；`tests/test_tokyo_hlod_stream.gd` / `cancelled_decode_checks`以真实Image工作线程核读取次数/原预约/关闭回收，默认关闭的同池候选不冒充性能通过。

原生缩远不跳过必经表示 → `rendering/tokyo_hlod_handoff.gd` / `native_exit_checkpoint`、`rendering/tokyo_hlod_overlay.gd` / `_predict_prefetch`；反例见 `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。不改变16页/清晰度/缓存限制。

整树地表绑定与显式来源导出 → `tests/tokyo_native_massing_cost.gd` / `run` / `_export_layer`，元数据清单与最多64页完整原始通道独立于相机采样，重复/未知页拒绝。

过期切面即时换目标 → `rendering/tokyo_hlod_overlay.gd` / `_selection_due` / `_step_geometry`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`覆盖上限两侧与纯几何非过期。

容量逐页归因 → `tests/tokyo_handoff_selection_probe.gd` / `capacity_audit`，page_costs绑定实际选中页身份、mask与三层面数，不改变正式选择。

当前联合树碎片化诊断 → `tests/tokyo_handoff_selection_probe.gd` / `capacity_audit`；16页基线逐字段一致，24/32仅反事实，正式页数门不变。

交接费用免固定键表复制 → `rendering/tokyo_hlod_stream.gd` / `handoff_increment` → `tokyo_hlod_handoff.gd` / `append_streaming_bundle`只读fixed；差分反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

预载后CPU/绘制分段 → `tests/tokyo_hlod_route_probe.gd` / `play_session`，显式LOADED_PHASE_TRACE复用`tokyo_render_trace.gd` / `begin_frame` / `close`。

Loading接管后墙钟 → `tests/tokyo_hlod_route_probe.gd` / `play_session`；复用`tokyo_render_clock.gd` / `frame_within_budget`，记录预载ready、初始纹理、VSync与严格慢帧。

固定资源交接增量 → `rendering/tokyo_hlod_overlay.gd` / `_handoff_bytes`；复用固定描述符账本而非重复扣费，保持原池上限；反例 → `tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`。

绘制尖峰触发采样 → `tests/tokyo_render_trace.gd` / `setup` / `_capture_draw_spike`，显式诊断ready/armed握手及单次帧证据；反例 → `tests/test_perf_frame_trace.gd` / `_test_draw_capture`。不改变游戏或严格帧时间标准。

已安装目录全层覆盖反例 → `tests/tokyo_cut_worker_replay.gd` / `_layer_audit`，既有`run`输出layer_audit；走CUT_WORKER_REPLAY_OUT入口，只核真实目录切面，不上传全地图。

原生三层覆盖证明 → `rendering/tokyo_hlod_native.gd` / `covers_visible_layers` / `_covers_layers` / `_layer_complete`（替代旧私有`_ground_complete`）；复用/提交接线 → `rendering/tokyo_hlod_overlay.gd` / `_cut_covers_current_view`；平移mask与层级缺页反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

混合地表可迁址候选 → `tests/stage_tokyo_incremental_package.gd` / `ground` / `partition` / `asset` / `build`；已安装包实物验证 → `tests/verify_tokyo_incremental_package.gd` / `run`（`tests/tokyo_partition_stream_probe.gd` / `run`显式输入路由）；实际安装 → `tools/install_tokyo_incremental.ps1`，不切默认M20。

切面组合分配优化 → `experiments/tokyo_spatial_cut.gd` / `_combine`；差分参照 → `_insert`；完整顺序回归 → `tests/test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`与`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。不改可见性、预算或选页顺序。

异步未来原生预取 → `rendering/tokyo_native_predictor.gd` / `prepare` / `request` / `dispatch` / `usable` / `rejection` / `smooth_pan` / `close`；多来源快照 → `rendering/tokyo_cut_worker.gd` / `configure_sources`；费用装饰 → `rendering/tokyo_hlod_native.gd` / `decorate`；主线程联合费用门 → `rendering/tokyo_hlod_overlay.gd` / `_async_full_prefetch_allowed`。测试覆盖多来源、陈旧结果、延后提交、时间平滑及退出。

纯地图后台任务 → `rendering/tokyo_cut_worker.gd` / `configure` / `submit` / `ready` / `take` / `close` / `_pure`；纯计算 → `rendering/tokyo_cut_job.gd` / `run`及`experiments/tokyo_spatial_cut.gd` / `solve`；生命周期专项 → `tests/test_tokyo_cut_worker.gd` / `run` / `Owner._exit_tree`；真实源差分 → `tests/tokyo_cut_worker_replay.gd` / `run`。单任务，领取前完成检查，旧代次/过期拒绝，已接显式候选预取，正式默认未启用。

同帧多查询与求解内部归因 → `rendering/tokyo_hlod_overlay.gd` / `_select_native` / `_step_geometry`，`experiments/tokyo_spatial_cut.gd` / `solve` / `_frontier`；保护带查询与预测桶嵌套，不重复计总成本。初始零切面沿用首个已筛选分支，后续只读组合。

画外零分支等价优化 → `experiments/tokyo_spatial_cut.gd` / `solve` / `_frontier`；完整候选回归 → `tests/test_tokyo_hierarchical_pages.gd` / `_test_solver`。

武器首播同步读盘 → `audio/audio_manager.gd` / `WEAPON_SFX` / `_get_sfx`；基础页扫描超页数/面数提前拒绝 → `rendering/tokyo_hlod_foundation.gd` / `select`；回归 → `tests/test_missile_grid.gd` / `run`及`tests/test_tokyo_hlod_stream.gd` / `foundation_checks`。

投机上传与可见网格领取调度 → `rendering/tokyo_hlod_stream.gd` / `ready_visible_mesh` / `defer_speculative_upload`；原领取预算不变，summary输出`speculative_upload_deferrals`，默认关闭。

原生缓存身份参与完整切面求解 → `rendering/tokyo_hlod_cached_cut.gd` / `native_tree`、`rendering/tokyo_hlod_native.gd` / `select`；父页/完整子页及缺高度图反例 → `tests/test_tokyo_hlod_stream.gd` / `native_resident_tree_checks`。

屏外保护带阻塞原生提交 → `rendering/tokyo_hlod_overlay.gd` / `_native_screen_bridge`；拒绝反例与预取保留 → `tests/test_tokyo_hlod_stream.gd` / `native_screen_bridge_checks`、`NativeBridgeOverlay`。

预测/实际预算及保护带选择差异 → `tests/tokyo_handoff_selection_probe.gd` / `run`元数据对照，报告裸视野/当前保护带/未来保护带的组件与地表图片；禁用在途复用和旧切面联合预算，仅作定位。

固定坏点输出尺度复验 → `tests/tokyo_hlod_route_probe.gd` / `run`显式NORTH_FIXED_REVIEW按输出/逻辑窗口比例校准新增视图。

无损原生叶面积分桶 → `tests/build_tokyo_lossless_leaf_partitions.gd` / `valid_leaf_plan` / `run`，`tests/tokyo_native_refinement_probe.gd` / `_refine`；显式逐来源计划与生产共享，保留三层守恒及原预算门。

当前图片请求防饥饿 → `rendering/tokyo_hlod_stream.gd` / `image_slot_reserve`及`_process_stream`，显式候选只留一个共享槽、原上传/内存门不变；`rendering/tokyo_hlod_overlay.gd` / `_request_target`接当前图片身份。

实际/预测资源身份对拍 → `tests/tokyo_wasd_audit.gd` / `run`显式HANDOFF_TRACE，最多256条纯观测记录并附逻辑页到物理组件对应；正式加载与预算不变。

可选离线空间切线 → `tests/tokyo_native_refinement_probe.gd` / `planned_cut` / `_split`；候选身份与节点计数绑定 → `tests/build_tokyo_source_massing.gd` / `run`；参数反例 → `tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`；西侧实际路线画面 → `tests/tokyo_hlod_route_probe.gd` / `run`显式WEST_REVIEW。

小额地表交接预算 → `rendering/tokyo_hlod_stream.gd` / `reserve_auxiliary` / `_prune_lru`，反例 → `tests/test_tokyo_hlod_stream.gd` / `ground_lease_pressure_checks`；两帧图片退役/原池限额/当前与目标pins不变。

完整来源低楼分页接合 → `tests/build_tokyo_source_massing.gd` / `split_depth` / `run`，`tests/tokyo_partition_stream_probe.gd` / `run`显式source_massing_package入口。普通层/地表不变、标高层保留通道与三层重打包守恒，旧attachments/proof保留；可选离线二分深度1–4，反例在`tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`；联合切面仍原显示预算。

完整安装来源导出 → `tests/export_tokyo_native_source.gd` / `common_source` / `unchanged_sources` / `run`，由`tests/tokyo_partition_stream_probe.gd` / `run`显式native_source_export入口调用；共同来源定位及部分子树已替换反例 → `tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks`。跨档按树位置配对，各自完整身份独立绑定；禁止覆盖已有替换。

当前树无损细分 → `tests/build_tokyo_lossless_leaf_partitions.gd` / `refinable` / `run`，`tests/tokyo_native_refinement_probe.gd` / `select` / `_refine`；反例 → `tests/test_tokyo_hlod_stream.gd` / `refinement_source_checks` / `RefinementSource`。真实标高层导出 → `tests/tokyo_native_massing_cost.gd` / `run`显式wall_export，不能把该层统称竖墙。

可选地表高度资源 → `rendering/tokyo_ground_height.gd` / `valid_texture` / `descriptor` / `shader_code`；制作 → `tests/build_tokyo_ground_height.gd` / `run`；流送反例 → `tests/test_tokyo_hlod_stream.gd` / `height_texture_checks`。原生资源read/select、overlay预测/绑定与Stream领取共用原有ready/pins/预算，未启用默认地图。`tests/tokyo_native_massing_cost.gd` / `run`支持正常近景5.0成本审计，仍独立判资格，不授予画面通过。

地面压平遮挡诊断 → `tests/tokyo_native_ground_review.gd` / `run`显式高度图与紧凑层索引GPU对照、分项费用记录；仅诊断，不接正式流送。

失败位置地面前后对照 → `tests/tokyo_native_ground_review.gd` / `run`有界poses输入、JSON整数档位校验及GPU原生/候选双图；正式地图验收仍独立。

失败求解不能撤销合格显示 → `rendering/tokyo_hlod_handoff.gd` / `retain_display`、`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；原生显示档传递 → `_select_native` / `_predict_prefetch`；拒绝反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

完整四档基础层容量与资格 → `rendering/tokyo_hlod_cache_policy.gd` / `complete_pool_bytes`、`rendering/tokyo_hlod_foundation.gd` / `plan`、`tests/tokyo_foundation_audit.gd` / `sample` / `run`；四层缺失/预算门 → `tests/test_tokyo_hlod_stream.gd` / `foundation_checks`。

固定组与待加载队列分离 → `rendering/tokyo_component_stream.gd` / `request_partitioned` / `_path_set`；无合格切面仍保护基础层 → `rendering/tokyo_hlod_stream.gd` / `request_residency_only`、`tokyo_hlod_overlay.gd` / `_step_geometry`；等价反例 → `tests/test_tokyo_hlod_stream.gd` / `partitioned_request_checks`；实际固定层覆盖与超预算拒绝 → `tests/tokyo_wasd_audit.gd` / `run`。

不变请求路径复用与分发CPU取证 → `rendering/tokyo_component_stream.gd` / `request` / `configure` / `close`、`rendering/tokyo_hlod_overlay.gd` / `_request_target`；输入修改/重配置/顺序反例 → `tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`。

固定资源增量核算 → `rendering/tokyo_hlod_stream.gd` / `residency_request_ledger`、`tokyo_hlod_overlay.gd` / `_request_target`；只读目录物理路径预展开 → `tokyo_component_stream.gd` / `configure` / `_paths` / `close`；缓存失效/别名/退出反例 → `tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`；路线CPU取证 → `tests/tokyo_hlod_route_probe.gd` / `patrol`。

大常驻集CPU扫描 → `rendering/tokyo_component_stream.gd` / `request`、`rendering/tokyo_hlod_stream.gd` / `_prune_lru`；等价/输入别名与5000项微测 → `tests/test_tokyo_hlod_stream.gd` / `cache_pruning_checks`。

固定叶候选容量边界 → `rendering/tokyo_hlod_cache_policy.gd` / `static_pool_bytes`；反例 `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`；正式路由拒绝/有界加载进度 → `tests/tokyo_hlod_route_probe.gd` / `run`。

固定最细叶加载→战场候选 → `rendering/tokyo_static_hlod_overlay.gd` / `_setup_geometry` / `_build_static` / `_step_geometry` / `_visible_static_cost` / `_sync_legacy` / `debug_state`；显式容量和加载门 → `tokyo_hlod_cache_policy.gd` / `candidate_limit`、`tokyo_volume_preload.gd` / `script_path` / `state_ready`。独立全图GPU预载探针 → `tests/tokyo_static_leaf_probe.gd` / `run`（非游戏性能验收）。

固定最细叶与全树常驻成本 → `tests/tokyo_native_massing_cost.gd` / `run` / `_leaf_cut`；失败时实际在途归属与原生地面纹理等待 → `tests/tokyo_wasd_audit.gd` / `run`。均为诊断，不修改正式选择器预算或认证Visual通过。

原生旧切面真实地面覆盖 → `rendering/tokyo_hlod_native.gd` / `covers_ground` / `_layer_complete`；投影保护带与当前合格地面补选 → `tokyo_hlod_overlay.gd` / `_cut_covers_current_view` / `_select_current_ground`；测试 → `tests/test_tokyo_hlod_stream.gd` / `NativeSelectionProbe.ground_configuration` / `commit_ready_checks`；有界区域地面导出 → `tests/tokyo_native_massing_cost.gd` / `run`；动态证据 → `tests/tokyo_wasd_audit.gd` / `run`。

基础层与邻区同时预载 → `rendering/tokyo_hlod_stream.gd` / `configure_residency`；`tokyo_hlod_overlay.gd` / `_setup_geometry` / `prepare_loading_neighborhood` / `release_loading_neighborhood`；`tokyo_volume_preload.gd` / `_begin`；测试 `tests/test_tokyo_hlod_stream.gd` / `LoadingOverlay._select_native` / `foundation_checks`。

地面偏好到期、投机前探与窄保护带复用 → `rendering/tokyo_hlod_handoff.gd` / `native_preference_qualified` / `pan_lead`、`tokyo_hlod_overlay.gd` / `_select_native` / `_predict_prefetch`；原生求解峰值 → `tokyo_hlod_native.gd` / `select`；测试 `tests/test_tokyo_hlod_stream.gd` / `NativeSelectionProbe.select` / `commit_ready_checks`。安装包无旧制作机位的无损增量 → `tests/build_tokyo_lossless_leaf_partitions.gd` / `run`。

原生地面高度一致性 → `rendering/tokyo_native_ground.gd` / `read` / `tree`、`tokyo_hlod_overlay.gd` / `_bind_target`；延迟候选页列表分配 → `experiments/tokyo_spatial_cut.gd` / `_combine` / `_insert`；等价组合验证 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

混合地面原池交接 → `rendering/tokyo_native_ground.gd` / `read` / `tree`；`tokyo_hlod_native.gd` / `ground_configuration` / `select`；`tokyo_hlod_overlay.gd` / `_resources_ready` / `_handoff_bytes` / `_request_target` / `_commit_ready_target` / `_bind_target`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`验证原生纹理等待与租约失败保留旧画面；资源制作 → `tests/build_tokyo_native_ground_pack.gd` / `run`。

清晰地面＋原生建筑候选 → `tests/tokyo_native_massing_cost.gd` / `run`导出ground_export；`scripts/tools/build_tokyo_native_ground_candidate.py` / `binding` / `bake`生成；`tests/tokyo_native_ground_review.gd` / `run`经partition_stream_probe输出五视野GPU同位对照。未改变正式启动与同步设置。

导弹命中首样本/峰值 → `missile_manager.gd` / `_record_hit_cost`、`tests/tokyo_volume_combat_runner.gd` / `_bench_finish_now`；四种常用命中声预载持有 → `audio/audio_manager.gd` / `IMPACT_SFX` / `_get_sfx`；聚焦回归 → `tests/test_missile_grid.gd` / `run`。

过渡档XZ纹理/方格代理诊断 → `rendering/tokyo_hlod_surface.gd` / `textured_code`、`rendering/tokyo_hlod_overlay.gd` / `_bind_target`、`tests/tokyo_hlod_route_probe.gd` / `run`（六视野WALL_REVIEW同几何前后对照，纯色方案未通过）；原生三层成本核算 → `tests/tokyo_native_massing_cost.gd` / `run`，经`tests/tokyo_partition_stream_probe.gd` / `run`显式分派，资格与预算分别记录。

版本化地图二进制导出过滤回归 → `tests/test_tokyo_component_page.gd` / `export_filter_checks`；读取实际 `export_presets.cfg` 并使用引擎路径匹配。

增量资产复制与回读 → `tools/install_tokyo_incremental.ps1`（inventory SHA、限定tmp来源/全新版本路径、共享owner PID锁、逐文件摘要、默认不切换）。

保留M20底座的增量打包 → `tests/stage_tokyo_incremental_package.gd` / `record` / `asset` / `json` / `partition` / `build` / `run`，由 `tests/tokyo_partition_stream_probe.gd` / `run` 的incremental_package分支调用；原 `tests/package_tokyo_installed.gd` / `run` 拒绝尚未支持的二分替换，不能漏复制后仍报成功。

原生叶无损分区制作与接合 → `tests/build_tokyo_lossless_leaf_partitions.gd` / `run` / `save_json`；沿用正式原网格、拒绝游戏楼栋与已覆盖子树、三层全通道守恒回读、合并既有来源证明并重读完整native入口。仅产生显式候选。

地表预算预约不能晚于旧画面释放 → `rendering/tokyo_hlod_overlay.gd` / `_commit_ready_target`；独立新token预约成功后才清旧租约，失败原样保留显示。反例 `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`；用HLOD_STREAM_TEST入口执行，不以只跑regional_native代替。

同逻辑页三个文件合为一份原生包 → `tests/repack_tokyo_partition.gd` / `run`；数据协议 `rendering/tokyo_partition_bundle.gd` / `valid` / `stream_identity` / `descriptor`，schema3规范化与装配 `tokyo_partition_catalog.gd` / `normalize` / `node`、`tokyo_partition_page.gd` / `assemble`。保留原三层网格，不合并顶点、不降低解码计费；自动反例 `tests/test_tokyo_component_page.gd` / `partition_checks`。

预测视野与边缘预取的预算顺序 → `rendering/tokyo_hlod_handoff.gd` / `prefetch_requests`；真实目标/旧pins仍先计费，投机预测先于扩大保护带，跨目录身份与空清单反例在 `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

正式源绑定及二分子树候选接入 → `rendering/tokyo_partition_override.gd` / `read` / `identity_matches` / `empty_game`，`rendering/tokyo_partition_catalog.gd` / `replace`；摘要、数字身份、原子树与正式来源保护均须通过，接既有Native/Stream。证据生成 `tests/tokyo_partition_attach_probe.gd` / `run` / `cuts`；原生未改面保真 `tests/tokyo_tagged_low_cut_review.gd` / `preserve_known`。`tests/test_tokyo_component_page.gd` / `partition_checks`含JSON数值身份反例。

二分选页输入与GPU像素复核 → `rendering/tokyo_partition_catalog.gd` / `normalize` / `node`；`tests/tokyo_partition_stream_probe.gd` / `run` 使用规范化树交给正式Cut，`tests/tokyo_partition_render_probe.gd` / `compare` / `add_mesh`对实际加载分页和完整根网格截图并逐像素核对，空画面负对照必须生效。

新二分资源装配 → `rendering/tokyo_partition_page.gd` / `assemble` / `View.stream_identity`，经`rendering/tokyo_component_page.gd` / `assemble`显式format接公共流送；反例`tests/test_tokyo_component_page.gd` / `partition_checks`，真实逻辑页验证`tests/tokyo_partition_stream_probe.gd` / `run`的logical_pages。

跨候选LOD同池交接 → `tests/tokyo_partition_stream_probe.gd` / `read_partition` / `run`；两份分区独立SHA校验，旧pins持续到新ready，关闭记录纯值并验证节点释放。

候选分页同池真实资源交接 → `tests/tokyo_partition_stream_probe.gd` / `run`，PARTITION_STREAM显式入口；生产HlodStream加载/旧pins保留/新ready释放/close排空。保存器 `tests/tokyo_partition_page_writer.gd` / `emit` 为schema2写MeshComponent身份，资源通过不是正式画面通过。

完整来源片指定LOD三层导出 → `tests/tokyo_tagged_low_cut_review.gd` / `run` export_index分支、`tests/tokyo_residential_preview.gd` / `export_index`；真实来源/档位与完整16单元，禁止固定视野冒充来源片。

候选二分树的资源落盘与回读 → `tests/tokyo_partition_page_writer.gd` / `emit` / `finish` / `verify_tree`，离线 `tests/tokyo_native_refinement_probe.gd` / `_split` page_sink，入口 `tests/tokyo_tagged_low_cut_review.gd` / `run`。保存成功只证明几何往返，不代表覆盖或运行时接入。

普通标高低楼实际切面与同位画面 → `tests/tokyo_tagged_low_cut_review.gd` / `mesh` / `run` / `capture`；摘要绑定、引擎网格保存、完整分桶守恒与正式16页/24万面选择器，入口 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。只作候选资产证据，不改变游戏安装状态。

东京湾北侧原生成本反例 → `tests/tokyo_native_refinement_probe.gd` / `export_cut` / `select` / `_refine` / `_split`；入口 `tests/tokyo_hlod_manifest_audit.gd` / `run`。导出实际切面、逐通道守恒分桶与诊断预算对照，均非生产目录或运行时覆盖凭据。

四边四角高速输入入口 → `scripts/tests/tokyo_wasd_audit.gd` `anchor_for_route` / `run`，`AGL_TOKYO_WASD_ROUTE`显式八个边缘锚点；反例 → `scripts/tests/test_tokyo_hlod_stream.gd` `foundation_checks`。

同步保留的帧率余量诊断 → `scripts/tests/tokyo_render_clock.gd` `diagnostic_cap`；`scripts/tests/tokyo_volume_combat_runner.gd` `_ready` / `_bench_finish_now` 显式测试上限和实际刷新率/同步状态，不修改正式设置；反例 → `scripts/tests/test_perf_frame_trace.gd` `_test_render_partition`。

仅I/O计划复用与拒绝反例 → `scripts/rendering/tokyo_hlod_prefetch_cache.gd` `reusable` / `checks`；实际显示选择/预测I/O分离 → `scripts/rendering/tokyo_hlod_overlay.gd` `_step_geometry` / `_predict_prefetch`；命中音效耗时分段 → `scripts/audio/audio_manager.gd` `play_sfx_2d`。

中景概括独立候选 → `scripts/tests/build_tokyo_middle_massing.gd` `run` / `component` / `aligned`；实际高楼全通道/UV不变证明与清晰纹理组合，先验预算再写package。常驻接入 → `scripts/rendering/tokyo_hlod_foundation.gd` `plan`；独立recipe身份 → `scripts/rendering/tokyo_hlod_manifest.gd` `normalize`。旧素材资格不变，正式默认未改。

东京湾远景固定常驻候选 → `scripts/rendering/tokyo_hlod_foundation.gd` `plan` / `select`；真实资源只读审计 → `scripts/tests/tokyo_foundation_audit.gd` `run`（`AGL_TOKYO_FOUNDATION_AUDIT=res://tmp/...json`）；预算和空间拒绝反例 → `scripts/tests/test_tokyo_hlod_stream.gd` `foundation_checks`。加载/战场复用同一常驻所有权，尚未获准默认启用。

## 东京湾高速 WASD 闪块

每个预取页重复核算全常驻集 → `scripts/rendering/tokyo_hlod_handoff.gd` `append_streaming_bundle` / `scripts/rendering/tokyo_hlod_overlay.gd` `_request_target`；逐值参考 `streaming_bytes` 差分在 `scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。资源计划与派发子桶均包含在地图总桶内，不能相加当全帧。

完整目标ready与提交共用 → `scripts/rendering/tokyo_hlod_overlay.gd` `_resources_ready`；避免当前目标已就绪仍求跨目录缓存桥接，不放宽资格/预算/空间覆盖门。

常驻层不能延迟非驻留细档 → `scripts/rendering/tokyo_hlod_foundation.gd` `catalog_at`；高显存双层仍走独立显示资格与当前视野覆盖检查，不能全图固定驻留等同全缩放就绪。

显示内存上限独立于缓存池 → `scripts/rendering/tokyo_hlod_cache_policy.gd` `display_bytes` / `display_limit`；原48/96MiB选页优先 → `scripts/rendering/tokyo_hlod_overlay.gd` `_select_hlod`。失败帧是否漏选可用目录 → `scripts/tests/tokyo_wasd_audit.gd` `run`，只读诊断不授予显示资格。

远景提前细档失败却先求原生近景 → `scripts/rendering/tokyo_hlod_handoff.gd` `actual_fallback` / `scripts/rendering/tokyo_hlod_overlay.gd` `_step_geometry`；反例`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。



裁剪重复分配 → `scripts/rendering/tokyo_cells_overlay.gd` `projected_layer_bounds` / `intersects_view`；原循环逐值差分 → `tests/test_tokyo_hlod_stream.gd` `projection_equivalence_checks`。

有界跨目录缓存桥接 → `scripts/rendering/tokyo_hlod_cached_cut.gd` `candidate_catalogs` / `select`；`scripts/rendering/tokyo_hlod_overlay.gd` `_step_geometry`保留原目标物理请求；`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证顺序、去重与资格。

保护带预取被未来预测覆盖 → `scripts/rendering/tokyo_hlod_handoff.gd` `prefetch_requests` / `prefetch_changed`；`scripts/rendering/tokyo_hlod_overlay.gd` `_select_hlod` / `_select_native` / `_request_target`；反例`tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

大池共享逐出 → `scripts/rendering/tokyo_hlod_stream.gd` `_prune_lru` / `touch_display_resources` / `_prune`；反例`scripts/tests/test_tokyo_hlod_stream.gd` `cache_pruning_checks`。

分档缓存与邻区预载 → `scripts/rendering/tokyo_hlod_cache_policy.gd` `pool_bytes` / `candidate_limit` / `append_bundle`；加载构建/解除固定保护 → `scripts/rendering/tokyo_hlod_overlay.gd` `prepare_loading_neighborhood` / `release_loading_neighborhood`；预载同池交接 → `scripts/rendering/tokyo_volume_preload.gd` `_begin` / `_claim`。功能反例 → `scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

滚轮反向预测 → `scripts/rendering/tokyo_hlod_handoff.gd` `prediction_zoom_rate` / `scripts/rendering/tokyo_hlod_overlay.gd` `_step_geometry`；反例 → `scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

远景交错查询CPU复用 → `scripts/rendering/tokyo_hlod_manifest.gd` `select` / `FRAME_SOLUTIONS`；`scripts/rendering/tokyo_hlod_native.gd` `select` / `read`；差分和有界失效回归 → `scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

无效选择不能因诊断键变非空：`scripts/rendering/tokyo_hlod_overlay.gd` `_select_hlod` / `_select_native`；超尺度反例`scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

实际视野优先于预测图片：`scripts/rendering/tokyo_hlod_stream.gd` `can_start_image` / `_step_textures`；`scripts/rendering/tokyo_hlod_overlay.gd` `_request_target`登记实际物理资源；`scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证未排队、在途、缓存、失败及开关关闭分支。

重上传帧最小网格进度对照：`scripts/rendering/tokyo_hlod_stream.gd` `_process_stream` / `summary`（显式开关、临时单项处理、恢复宽度）；`scripts/tests/test_tokyo_hlod_stream.gd` `pipeline_checks`旧失败/新通过反例。

已驻留资源完整切面对照：`scripts/rendering/tokyo_hlod_cached_cut.gd` `select` / `_resident_tree`；`scripts/rendering/tokyo_hlod_overlay.gd` `_step_geometry`显式开关接入，`scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证不可省略缺资源页及父子替换。

反向放大提交保护的空间前提：`scripts/rendering/tokyo_hlod_overlay.gd` `_cut_covers_current_view` / `_commit_ready_target`；`scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`验证完整旧档拒绝降级、缺边旧档允许当前清晰度合格的新档接替。

当前目标纹理上传顺序：`scripts/rendering/tokyo_hlod_stream.gd` `ordered_texture_jobs` / `_step_textures`；顺序反例在 `scripts/tests/test_tokyo_hlod_stream.gd` `commit_ready_checks`。

预取列表跨类型比较与逐区域缺口：`scripts/rendering/tokyo_hlod_handoff.gd` `prefetch_changed` / `uncovered_view`。

预测下一实际视野资源身份：`scripts/rendering/tokyo_hlod_overlay.gd:920 _predict_prefetch`。

| 功能 | 接入点 |
|---|---|
| 真实键盘状态、滚轮及局部透明缺口回放 | `scripts/tests/tokyo_wasd_audit.gd:65 run`；沿 `tokyo_cells_lifecycle` 正式载入入口，通过 `AGL_TOKYO_WASD_AUDIT=1` 启用 |
| 固定地表覆盖证明 | `scripts/rendering/tokyo_hlod_handoff.gd:224 native_covers_view` |
| 移动提前选页与普通提交空间检查 | `scripts/rendering/tokyo_hlod_overlay.gd:672 _select_hlod` / `scripts/rendering/tokyo_hlod_overlay.gd:821 _select_native` / `scripts/rendering/tokyo_hlod_overlay.gd:1037 _target_covers_current_view` |
| 未绑定预取工作集 | `scripts/rendering/tokyo_hlod_overlay.gd:1177 _request_target` |

## 小队恐惧能力

| 功能 | 接入点 |
|---|---|
| 来源 FEAR 的正式申请与免疫 | `scripts/aircraft/fear_response.gd` `apply` / `eligible`；沿用 `CombatUnit.apply_status` |
| 尽可能远离施放者及边界逃逸 | `scripts/aircraft/fear_response.gd` `enforce` / `escape_point`；`scripts/aircraft.gd` `_resolve_intents` |
| 单机强制加力来源聚合 | `scripts/aircraft.gd` `set_afterburner_mode_active`；`scripts/survivor/afterburner_charge.gd` `toggle` / `activate` |
| 可装配配置与小队控制器 | `scripts/survivor/squad_fear_cone_config.gd` `valid`；`scripts/survivor/squad_fear_cone_controller.gd` `setup` / `update` / `dispose` |
| Wraith 原四机强化装配 | `scripts/survivor/f47_ace_squad.gd` `configure_progression` → `scripts/survivor/wraith_progression_loadout.gd` `fear_cone_for_progression` → `resources/wraith_fear_cone.tres`；`scripts/survivor/ace_squad.gd` `engage` / `fear_members` / `fear_targets` / `fear_enabled`；门槛回归 `scripts/tests/test_boss_progression.gd` `_test_wraith_fear_loadout` |
| 信息遮蔽与紫锥 | `scripts/aircraft/fear_response.gd` `obscure`；`scripts/ui/fear_readout_mask.gd` `draw`；`scripts/ui/world_unit_status_overlay.gd` `_draw`；`scripts/aircraft_renderer.gd` `_draw_status_panel_geometry` |
| 玩家、僚机、BOSS 状态栏 | `scripts/survivor/player_instrument_panel.gd` `_draw_impl`；`scripts/survivor/wingman_instrument_panel.gd` `_draw_row`；`scripts/survivor/survivor_hud.gd` `_update_boss_panel`；`scripts/survivor/ace_battle_bar.gd` `set_info` |
| F4 定向验收 | `scripts/survivor/survivor_debug_skills.gd` `_build_fear_controls` / `_refresh_fear_choices` / `_debug_fear_action` |
| 生命周期与真实物理回归 | `scripts/tests/fear_cone_case.gd` `run` / `_flight_and_edges`；`scripts/tests/lifecycle_gauntlet_runner.gd` `_run`；bench `fear_cone` / `all` |
| 同负载性能对照 | `scripts/tests/fear_cone_performance.gd` `start` / `_process` / `summary` / `capture`；`scripts/bench/bench_runner.gd` `_swap_to_fear_probe`，环境变量 `AGL_BENCH_FEAR_PROBE=baseline` / `enabled`，场景 `boss_wraith_stress` / `battlefield_atmosphere_stress_36` |

东京湾ETL对齐入口：`tests/tokyo_render_trace.gd` / `setup` / `begin_frame` / `summary`；单次UTC夹逼锚点与慢帧原始tick，仍用单调时钟判定帧预算；测试见 `tests/test_perf_frame_trace.gd` / `_test_backend_peaks`。

东京湾资格树重复构造优化（R7）：`rendering/tokyo_hlod_manifest.gd` / `qualified_roots` / `select`；等价与失效测试 → `tests/test_tokyo_hlod_manifest.gd` / `checks`；实际构造/复用次数 → `rendering/tokyo_hlod_overlay.gd` / `debug_state`。不缓存跨帧可见性，不改变清晰度/几何/预算。

FINAL WAR 双时钟验收：`tests/final_war_frame_probe.gd` / `_ready` / `_process` / `_bench_finish_now` / `_exit_tree`，继承 `scenes/survivor_mode.tscn`，由 `bench/bench_runner.gd` 的 FINAL_WAR 分支接入。F5 坐标轴 owner 释放：`survivor/survivor_debug_spawn.gd` / `_exit_tree`；`tests/debug_spawn_lifecycle_case.gd` / `run`覆盖未打开、打开后整场退出、单独销毁面板。

海洋事件驱动同步：`rendering/ocean_volume_ground.gd` / `sync` / `source_scans`；120稳定帧零扫描及增删/alpha反例：`tests/ocean_volume_lifecycle_case.gd` / `run`；禁用试验不进入覆盖计算：`rendering/ocean_volume_overlay.gd` / `_step_geometry`。

海洋覆盖抑制诊断（默认关闭）：`rendering/ocean_volume_overlay.gd:61 _set_raster_covered` / `rendering/ocean_volume_overlay.gd:75 _exit_tree`；原生RGBA/MSAA对照：`tests/ocean_volume_visual.gd` / `_capture_msaa_pair`；可选GPU诊断退出：`tests/ocean_volume_combat.gd:17 _exit_tree`。正式路径保持4×MSAA。

两图同标地图验收：`tests/map_lod_acceptance_probe.gd` / `run` / `_place` / `_sample`；`tests/map_frame_clock.gd` / `observe` / `report`；`tests/ocean_volume_lifecycle_runner.gd` / `_ready`。海洋精确退役与下一帧绑定：`survivor/raster_basemap_renderer.gd` / `_add_tile` / `_remove_resident`的版本与实例退役信号，`rendering/ocean_volume_ground.gd` / `sync` / `_on_tile_retiring` / `clear` / `_exit_tree`。两图墙钟：`tests/ocean_volume_combat.gd` / `_process` / `_bench_finish_now`，`tests/volume_map_performance.gd` / `_process` / `summary`；海洋48成员24km为`ocean_volume_c2`。

M20无I/O旧页收缩 → `rendering/tokyo_hlod_manifest.gd` / `visible_subset`、`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；投影保留与不变资源反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M20小纹理有界上传 → `rendering/tokyo_hlod_stream.gd` / `can_upload_texture` / `_step_textures`；并发/预算/释放反例 → `tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks`。

M20有界旧3D显示交接 → `rendering/tokyo_hlod_handoff.gd` / `display_grace`、`rendering/tokyo_hlod_overlay.gd` / `_update_display_grace` / `_record_display_grace`；独立观测 → `tests/tokyo_hlod_route_probe.gd` / `play_session`。

M20反向数值容差 → `rendering/tokyo_hlod_handoff.gd` / `zoom_direction`；`tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M20新档预取优先于旧档重分块 → `rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；提交不变 → `_commit_ready_target`；空间/资格反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M20补资源保持调度策略 → `tools/verify_tokyo_lod_policy.py` / `policy` / `verify`；近景切档有界诊断 → `tests/tokyo_hlod_route_probe.gd` / `patrol`。

M20安装测试环境隔离 → `tests/tokyo_cells_preload_case.gd` / `run`、`tests/tokyo_preload_lifecycle_case.gd` / `run`；真实新增边缘输入 → `tests/tokyo_hlod_route_probe.gd` / `play_session`（north_edge/east_edge/northeast_edge）。

M20不重复保存内部子树 → `tests/build_tokyo_boundary_tree.gd` / `assemble` / `collect`；混合复用切面独立检查 → `tests/audit_tokyo_boundary_coverage.gd` / `verify` / `run`；可回退分版本安装 → `tests/package_tokyo_installed.gd` / `run`、`tools/install_tokyo_playable.py` / `source_path`。

M20统一范围 → `rendering/tokyo_boundary_extent.gd` / `bounds` / `page_bounds` / `full_grid` / `checks`；身份门 → `tokyo_full_grid_contract.gd` / `metadata_valid`；表现范围 → `tokyo_canonical_catalog.gd` / `presentation_archive`、`tokyo_hlod_manifest.gd` / `row_valid` / `normalize`、`tokyo_hlod_overlay.gd` / `_load_archive`。离线整包 → `tests/build_tokyo_boundary_catalog.gd` / `paths` / `read_value` / `run`；实际几何凭据 → `tests/audit_tokyo_boundary_coverage.gd` / `verify` / `token` / `run`。新旧身份/缺摘要反例在`tests/test_tokyo_full_grid_contract.gd` / `checks`。

M20边界生成与接合 → `tests/export_tokyo_boundary_layers.gd` / `run`、`tests/build_tokyo_boundary_blocks.gd` / `run`；精确新边界布局 → `tests/export_tokyo_full_grid_layout.gd` / `run`；增量组件树 → `tests/build_tokyo_boundary_tree.gd` / `collect` / `meshes` / `run`。生产默认不由这些离线入口改变。空入口回归 → `tests/test_rail_obstacle_export.gd` / `checks`，分派 → `tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。

M18预取空间证明 → `rendering/tokyo_hlod_handoff.gd` / `anticipation_scale` / `covers_view`；生产接线 → `rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`；目标资格/资源诊断 → `tests/tokyo_hlod_edge_audit.gd` / `run`；默认安装HLOD可见性门 → `tests/tokyo_volume_combat_runner.gd` / `_bench_finish_now`。can_stage激进释放试验已撤回。

M17边缘覆盖自动验收 → `tests/tokyo_hlod_edge_audit.gd:6 alpha_coverage` / `tests/tokyo_hlod_edge_audit.gd:16 run`；正式载入测试分支 → `tests/tokyo_hlod_route_probe.gd` / `run`（AGL_TOKYO_EDGE_AUDIT）；单透明像素与250/249 alpha边界反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。记录完整玩家视野，不裁到归档边界，不把screen.visible当作无缺口。

M15大上传拆分候选 → `rendering/tokyo_hlod_manifest.gd` / `split_large_uploads` / `select`；沿原完整切面替换全部可见子页，不改变16页/24万面/调用预算。接线及Loading身份 → `rendering/tokyo_hlod_overlay.gd` / `_select_hlod`、`rendering/tokyo_volume_preload.gd` / `start` / `take` / `_begin`。资源身份审计 → `rendering/tokyo_hlod_stream.gd` / `_audit_texture`；反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M14 HLOD实例工作缓存 → `rendering/tokyo_hlod_overlay.gd` / `_select_hlod`，`rendering/tokyo_hlod_manifest.gd` / `select`；预算与候选生成分离，同帧完整身份/视野/提前模式匹配才复用。等价及失效反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M14同帧候选复用 → `experiments/tokyo_spatial_cut.gd` / `solve` / `pick` / `choose`，`rendering/tokyo_hlod_native.gd` / `read` / `select`；同帧/同配置/同中心尺度旋转尺寸才复用，`rendering/tokyo_hlod_overlay.gd` / `debug_state` 计数。集合去重 → `rendering/tokyo_component_stream.gd` / `_paths`、overlay的 `_request_target`；语义反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M13显式Loading常驻试验 → `rendering/tokyo_hlod_stream.gd` / `configure_residency` / `geometry_budget` / `residency_ready`；`rendering/tokyo_volume_preload.gd` / `state_ready` 等固定集就绪并保持候选身份。资源成本/真实驻留探针 → `tests/tokyo_map_residency_probe.gd` / `costs` / `counters` / `loaded` / `trial` / `run`，测试子类 `TrialStream.geometry_budget`；`tests/tokyo_hlod_route_probe.gd` / `play_session` 记录实际Loading用时与实验池预算。手动候选入口 `play_preloaded_map.cmd`，默认入口不变。

M12完整目标预退役 → `rendering/tokyo_hlod_stream.gd` / `prepare_target_space` / `request_textures`；满池退役计费反例 → `tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks`。反向缩放降档提交门 → `rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_commit_ready_target`；自动反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks`。

M12远景矩形缺口 → `rendering/tokyo_hlod_handoff.gd` / `covers_view` / `catalog_index`、`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks` / `run`；结束后静止覆盖取证 → `tests/tokyo_hlod_route_probe.gd` / `play_session`的SETTLED_CAPTURE分支。

M11有界提前交接 → `rendering/tokyo_hlod_overlay.gd` / `_step_geometry` / `_commit_ready_target`；原生偏好及预测尺度 → `rendering/tokyo_hlod_handoff.gd` / `native_preference` / `loading_configuration` / `scale_limit`；逐帧末次领取 → `rendering/tokyo_cell_stream.gd` / `_collect_completed`及`rendering/tokyo_hlod_stream.gd` / `collect_ready_meshes`；真实双Image/预算覆盖反例 → `tests/test_tokyo_hlod_stream.gd` / `texture_pipeline_checks` / `handoff_budget_probe` / `pipeline_checks` / `commit_ready_checks`。渲染完成间隔 → `tests/tokyo_render_trace.gd` / `_after_draw` / `summary`；显式同步对照 → `tests/tokyo_volume_combat_runner.gd` / `_ready`。

M10已完成交接先于重选 → `rendering/tokyo_hlod_overlay.gd` / `_commit_ready_target` / `_step_geometry`；完整性/尺度/可见性反例 → `tests/test_tokyo_hlod_stream.gd` / `commit_ready_checks` / `CommitStream` / `CommitOverlay`；纹理路径时间线 → `tests/tokyo_hlod_route_probe.gd` / `play_session`的显式HANDOFF_TRACE。

M9真实Image取消重载 → `tests/test_tokyo_hlod_stream.gd` / `checksum_reload_checks`；2/8槽有界领取 → `pipeline_checks`；跨区域/36成员战斗输入诊断 → `tests/tokyo_hlod_route_probe.gd` / `play_session`。

## 血色骑士（嗜血敌机击杀视为对头）

| 功能 | 入口 |
|---|---|
| 致死前状态快照，按实际击杀者与 Aircraft 目标类型校验 | `survivor/skill_hooks.gd` `bloodlust_counts_as_head_on`；`aircraft.gd` `_record_kill_attribution` |
| 对头永久成长、恐惧、经验与基础成长共享布尔快照 | `survivor/skill_hooks.gd` `dispatch_on_kill`；`survivor/survivor_spawner.gd` `_detect_kills` / `_check_head_on_kill_bonus` |
| focused 与 all 生命周期同源 | `tests/bloodlust_head_on_case.gd` `run` / `_test_catalog` / `_air_case` / `_surface_case` / `_aircraft` / `_check`；`tests/bloodlust_head_on_runner.gd` `_ready` / `_run` |
| C1 A/B 触发态与截图 | `tests/bloodlust_head_on_performance.gd` `start` / `summary` / `coverage_ok` / `capture`；`bench/bench_runner.gd` `_swap_to_bloodlust_c1` / `bench_finish` |

M9消除校验启动的主帧等待 → `rendering/tokyo_hlod_stream.gd` / `_request_load` / `checksum_after_load` / `_load_status`；60Hz输入诊断 → `tests/tokyo_hlod_route_probe.gd` / `play_session`，不改变正式帧率。

东京后台SHA与硬退出清理 → `rendering/tokyo_hlod_stream.gd` / `checksum_file` / `_load_status` / `_matches` / `_exit_tree`、`rendering/tokyo_cell_stream.gd` / `_exit_tree`；无后续帧退出回归 → `tests/test_tokyo_hlod_stream.gd` / `shutdown_checks`。

HLOD的2/8槽领取/取消终态 → `tests/test_tokyo_hlod_stream.gd` / `pipeline_checks` / `PipelineFixture`；原加载池有限吞吐 → `rendering/tokyo_cell_stream.gd` / `_process_stream`、`rendering/tokyo_hlod_stream.gd` / `configure_hlod`。

正常滚轮交接/空间预留 → `rendering/tokyo_hlod_manifest.gd` / `select` / `retained`；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；输入专项及隐藏区间 → `tests/tokyo_hlod_route_probe.gd` / `play_session`，与实战帧时分开验收。

东京无渲染信号慢帧诊断 → `tests/tokyo_volume_combat_runner.gd` / `_process` / `_bench_finish_now`，WALL_TRACE仅保存既有墙钟及CPU快照；流送子桶 → `rendering/tokyo_hlod_stream.gd` / `_step_textures` / `_matches`与`rendering/tokyo_cell_stream.gd` / `_process_stream`，上传/摘要/领取不重复累加根桶。

正常东京湾安装入口 → `rendering/tokyo_installed_map.gd:5 package_path` / `rendering/tokyo_installed_map.gd:15 package_sha`；路由优先级回归 → `tests/test_tokyo_hlod_stream.gd:2035 installed_route_checks`；真实加载/操作记录 → `tests/tokyo_hlod_route_probe.gd:7 run` / `tests/tokyo_hlod_route_probe.gd:251 play_session`。用户直接启动脚本为 `play_installed.cmd`。

现存低楼网格整块替换 → `tests/tokyo_solid_native_mesh.gd:27 merge_mesh` / `tests/tokyo_solid_native_mesh.gd:11 checks`；真实目录再打包 → `tests/build_tokyo_solid_native.gd:29 run` / `tests/build_tokyo_solid_native.gd:17 refresh` / `tests/build_tokyo_solid_native.gd:114 collect`（`bind`、`write_values` 保存绑定）。生产迁址 → `tests/package_tokyo_installed.gd:11 run` / `tests/package_tokyo_installed.gd:8 binding`；离线复制 → `tools/install_tokyo_playable.py` 的 `add` / `relocate` / `json_output` 与 CLI。均复用既有组件和覆盖协议，不新增常驻渲染所有者。

密集近景整块 → `tools/build_tokyo_block_lod.py` / `prepare` / `choose`的street_solid；原生配方校验 → `tests/build_tokyo_far_clusters.gd` / `group_limit`；保护门测试 → `tools/test_tokyo_block_lod.py` / `test_solid_street_preserves_anchors_and_source`和`tests/test_tokyo_far_clusters.gd`。

BC1不透明等价转换 → `tests/build_tokyo_hlod_opaque.gd` / `color_blocks` / `opaque_image` / `checks` / `run`；上传错峰 → `rendering/tokyo_hlod_stream.gd` / `should_defer_mesh_finalize`；原生只读档比较 → `tests/tokyo_hlod_manifest_audit.gd` / `run`及`rendering/tokyo_hlod_native.gd` / `select`的configuration_override。近景原生优先策略 → `rendering/tokyo_hlod_overlay.gd` / `_load_archive` / `_step_geometry`，只在正常原生切面满足预算时替换细HLOD。

正常局试玩入口 → `tests/tokyo_hlod_route_probe.gd` / `run` / `play_session`，PLAY_SECONDS非零关闭map_preview_only，正常镜头/任务/升级，记录实际位移/非暂停时间/隐藏帧/超预算帧/退出释放。显式慢帧CPU桶/事件快照 → `tests/tokyo_render_trace.gd` / `begin_frame`，沿原有界top32记录。

飞机首次淡出材质编译 → `experiments/volume_world_probe.gd` / `setup` / `_on_material_warmup_finished` → `experiments/volume_material_warmup.gd` / `configure_instanced` / `_after_draw`：实际三材质MultiMesh暖绘，不削减真实淡出/单位/火力。

HLOD/原生换页暂留入口：`rendering/tokyo_hlod_handoff.gd` / `catalog_index` / `native_qualified` / `streaming_bytes` / `combined_bytes` / `qualified`；`rendering/tokyo_hlod_overlay.gd` / `_committed_qualified` / `_handoff_bytes` / `_target_committed` / `_request_target`区分旧显示与目标ready，`_bind_target`记录实际几何峰值。`rendering/tokyo_hlod_manifest.gd` / `select`显式提前混合清晰度页，`tests/test_tokyo_hlod_manifest.gd` / `checks`覆盖共享计费、身份冲突与过尺度拒绝；`tests/test_tokyo_hlod_stream.gd` / `run`覆盖提前选档、目标匹配及pins生命周期；`tests/tokyo_volume_combat_runner.gd` / `_process` / `_bench_finish_now`汇总真实可见性和等待帧；`tests/tokyo_hlod_route_probe.gd` / `patrol`将总览/近景连续隐藏帧纳入顶层fail。

中景合并街坊颜色来源 → `tests/export_tokyo_massing_color.gd` / `run`，复用完整角点导出；逐页纹理资格 → `rendering/tokyo_hlod_manifest.gd` / `qualified_tree` / `select` / `retained`及`tests/test_tokyo_hlod_manifest.gd` / `checks`；只复用父图打包 → `tests/build_tokyo_hlod_native_pages.gd` / `run`。同overlay的正式/原生shader由`tokyo_hlod_overlay.gd` / `_setup_geometry`创建一次，`_bind_target`只复用。

近景同池桥接 → `rendering/tokyo_hlod_native.gd` / `read` / `select` / `covered`；`rendering/tokyo_hlod_surface.gd` / `native_code`沿已有Palette生成插值前顶点映射；`rendering/tokyo_hlod_overlay.gd`原选择/绑定/覆盖入口接受完整原生切面，`rendering/tokyo_hlod_stream.gd`继承ComponentStream共享物理资源预算。

纯纹理更新：`tests/build_tokyo_hlod_native_pages.gd` / `reuse_geometry` / `run`以GEOMETRY_REUSE仅复用来源、UV、实际Component身份/预算均匹配的网格；旧TEXTURE_REUSE默认语义不变。

HLOD颜色合成：`rendering/tokyo_hlod_surface.gd:7 shader_code`移除light阶段重复底色，原公共shader与源资产不变。

组件树显式空叶不可被空切面替换 → `experiments/tokyo_spatial_cut.gd` / `_frontier`、`experiments/tokyo_spatial_select.gd` / `choose`；反例在`tests/test_tokyo_hierarchical_pages.gd` / `_test_solver`。现有近景实物树成本 → `tests/tokyo_near_component_audit.gd` / `run`，正常玩家位置/缩放、原预算、仅元数据。

正常可玩尺度门 → `tests/tokyo_hlod_gameplay_views.gd` / `poses` / `checks`；`tests/tokyo_hlod_route_probe.gd` / `run` / `patrol`沿共享CameraController正常缩放和出生尺度，不用电影切镜绕过限制的远景冒充交付，回退时不保存陈旧原生图。

HLOD闲置复用 → `rendering/tokyo_hlod_stream.gd` / `configure_hlod` / `_prune` / `reserve_auxiliary`；`tests/test_tokyo_hlod_stream.gd` / `cache_checks`。共用原预算，延迟退役及pins保护，HLOD默认开启，AGL_TOKYO_RETAIN_UNUSED=0显式关闭；其他流送默认不变。巡航帧间隔/选择/绑定/上传分桶 → `tests/tokyo_hlod_route_probe.gd` / `patrol`及`rendering/tokyo_hlod_overlay.gd` / `debug_state`，无截图模式不等于实战性能验收。

HLOD同档切面保留 → `rendering/tokyo_hlod_manifest.gd` / `retained` / `covered_key`；`rendering/tokyo_hlod_overlay.gd` / `_step_geometry`；沿原求解结果的整页父子覆盖与原预算，避免无必要整批解绑，保留次数可查。

正式HLOD连续巡航证据 → `tests/tokyo_hlod_route_probe.gd` / `patrol`，12秒位置/尺度/旋转轨迹及连续帧序列；截图读回干扰帧时，不作性能结论。

HLOD正式地图路由 → `rendering/tokyo_hlod_overlay.gd` / `_load_archive` / `_setup_geometry` / `_step_geometry` / `_bind_target` / `_clear_current` / `bind_legacy` / `_sync_legacy` / `_deactivate` / `_exit_tree` / `debug_state`、Layout.valid；`tests/tokyo_hlod_route_probe.gd` / `run`；`rendering/tokyo_volume_preload.gd` / `script_path` / `start` / `take` / `_begin`同实例身份及合格尺度预热。正常游戏读取installed_package；普通bench保持隔离，显式INSTALLED_TEST才验正常安装路由。

HLOD实际覆盖 → `rendering/tokyo_hlod_coverage.gd` / `bind` / `read` / `matches`；`rendering/tokyo_hlod_stream.gd` / `_matches`实际正式槽领取；`rendering/tokyo_volume_preload.gd` / `state_ready`贴图就绪；`tests/test_tokyo_hlod_coverage.gd` / `checks`，绑定错误、面数/摘要及未就绪反例。

HLOD加载描述符/真实切面适配 → `rendering/tokyo_hlod_manifest.gd` / `integer` / `sha` / `numbers` / `binding` / `same_numbers` / `texture_valid` / `row_valid` / `normalize` / `tree` / `charges` / `select` / `read`；`tests/test_tokyo_hlod_manifest.gd` / `fixture` / `checks`；`tests/tokyo_hlod_manifest_audit.gd` / `run`；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式HLOD_MANIFEST_AUDIT入口。纹理独立辅助计账，不充当MeshComponent；源元数据归属通过不等于实际覆盖或实装。

HLOD原生页同位对拍 → `tests/tokyo_hlod_pages_review.gd` / `valid_pose` / `add_page` / `capture` / `run`；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`的HLOD_PAGES_REVIEW显式入口；`tests/test_tokyo_regional_native.gd` / `run`空机位反例。制作控制图可超预算但候选独立计账，不授予实装资格。

HLOD原生资源制作：`tests/build_tokyo_hlod_native_pages.gd` / `valid_input` / `build_mesh` / `reuse_texture` / `checks` / `run`；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式入口；`tests/test_tokyo_regional_native.gd` / `run`接反例。TEXTURE_REUSE按精确摘要、mip/UV及实际解码复用，不改正式加载器默认。

整图远景原生制作预览：`tests/tokyo_overview_hlod_review.gd` / `binding` / `material` / `triangle_mesh` / `add_mesh` / `checks` / `run`；真实mip/网格加载、四整图机位与释放；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`显式OVERVIEW_HLOD_REVIEW接线；`tests/test_tokyo_regional_native.gd` / `run`接保存数组与空输入回归，不影响默认正式地图。

固定层接入：`tests/build_tokyo_semantic_fixed_tree.gd` / `route_valid` / `checks` / `run`；`tests/rebind_tokyo_semantic_fixed_tree.gd` / `entry` / `checks` / `run`；固定源独立树、旧建筑物理文件复用及新逻辑身份。`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`提供有界生产入口，`tests/test_tokyo_regional_native.gd` / `run`接合同反例。

语义铁路：`tests/bake_tokyo_semantic_rail_roots.gd` / `record` / `select` / `filtered` / `checks` / `run`匹配原始有序角点及重复重数，独立落盘核非删除数据不变；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready`提供SEMANTIC_RAIL_ROOT有界入口，`tests/test_tokyo_regional_native.gd` / `run`覆盖非法输入及过滤反例。

完整交互认证：`tests/tokyo_interaction_certificate.gd` / `matches` / `certified` / `checks`；`tests/bake_tokyo_full_grid_configuration.gd` / `valid`使用绑定证明而非单一passed字段放行精细交互格，原全图结构门不变。

交互屋顶原生探针：`tests/bake_tokyo_interaction_probe.gd` / `run`经lifecycle runner显式INTERACTION_PROBE绑定独立选择/原完整源，复用原Baker与磁盘逐通道Audit；`tools/build_tokyo_spatial_roof_plan.py` / `ownership`及`tools/audit_tokyo_shared_roofs.py` / `audit`将显式交互包渲染高度比较与XY格网解耦。此入口不授予完整目录准入。

Loading身份保护：`rendering/tokyo_volume_preload.gd` / `start` / `_begin` / `take`校验规范目录/覆盖前缀；`tests/tokyo_preload_lifecycle_case.gd` / `_catalog_identity`检查开始前漂移取消与已预热实例拒绝交接后的资源释放，不改默认地图或tick。

整图审图：`tests/tokyo_full_grid_review.gd` / `poses` / `checks` / `run`，121机位通过`tests/tokyo_preload_route_probe.gd` / `run`显式FULL_GRID_REVIEW进入正式Loading路线；拒绝旧目录/headless，保存实际图与状态并还原相机。不授予连续巡航或实战帧时通过。

R370可移植打包：`tests/tokyo_portable_paths.gd:5 rewrite`、`tests/tokyo_portable_paths.gd:27 reversible`保留数值与类型，`tests/tokyo_portable_paths.gd:36 checks`、`tests/tokyo_portable_paths.gd:50 full_grid_checks`验证token/冲突和完整层级；`tests/build_tokyo_portable_package.gd:11 read_values`、`tests/build_tokyo_portable_package.gd:19 save_values`、`tests/build_tokyo_portable_package.gd:28 run`绑定原coverage并迁址；`tools/install_tokyo_portable_package.py:6 digest`、`tools/install_tokyo_portable_package.py:11 child`、`tools/install_tokyo_portable_package.py:18 copy_exact`、`tools/install_tokyo_portable_package.py:34 install`离线精确拷贝；`tests/verify_tokyo_portable_package.gd:7 run`核实际新路径资源。无默认准入。

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

R342 BATCH_BLOCKS → `tests/build_tokyo_batch_blocks.gd` / `run` / `build_region` → `tests/build_tokyo_northwest_blocks.gd` / `build_verified`；整层保留计账与逐格构建互核，保留游戏楼门及旧区域固定配方。

R341 BATCH_LAYERS → `tests/export_tokyo_batch_layers.gd:6 run` → `tests/tokyo_residential_preview.gd` / `export_index`；旧`export_northwest`共用导出实现，空输入反例在`tests/test_rail_obstacle_export.gd` / `checks`。

R337/R338 ROAD_MESHOPT → `tests/build_tokyo_road_meshopt_catalog.gd:5 run`；ROAD_MESHOPT_REVIEW → `tests/tokyo_canonical_review.gd:6 run`，保留铁路版本、全部原审图机位和预算拒绝，不改变正式默认。

R333 CAPACITY_PROBE → `tests/tokyo_canonical_cut_probe.gd` / `run` → `tests/tokyo_capacity_probe.gd` / `run`；只读节点容量反事实，不修改正式`tokyo_spatial_cut.choose`的16块断言或预算。

R330 RETAIN_UNUSED → `rendering/tokyo_cell_stream.gd` / `configure`、`_prune`、`reserve_auxiliary`、`_process_stream`；默认关闭的原预算闲置缓存，预算与退出反例见`tests/test_tokyo_hierarchical_stream.gd` / `run`及`tests/test_tokyo_cross_lod_components.gd` / `lifecycle`。

R328 STREAM_AUDIT → `rendering/tokyo_cell_stream.gd` / `configure`、`_process_stream`、`_prune`、`summary`；默认无逐路径记录，不改预算、并发、缓存策略；反例见`tests/test_tokyo_hierarchical_stream.gd` / `run`。

R324 RAIL_SOUTHWEST+RAIL_CATALOG → `tests/build_tokyo_southwest_rail_catalog.gd:5 run`；仅父11精确铁路清单替换，沿既有`tests/build_tokyo_rail_catalog.gd` / `finish_rails`完成独立coverage配对及组件归档。

R313 SOUTHWEST_LAYOUT → `tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`；SOUTHWEST_SEAMS_REVIEW → `tests/tokyo_canonical_review.gd` / `run`，十区48位真实审图及原预算失败保留。

R312 SOUTHWEST_COMBINED → `tests/build_tokyo_northwest_catalog.gd:12 native_binding` / `build` / `audit_join`，历史21条补充层 → `tests/build_tokyo_northwest_catalog.gd:409 southwest_kept`；十区精确身份/覆盖 → `rendering/tokyo_canonical_catalog.gd:35 extension_valid` / `presentation_archive`。

R311 SOUTHWEST_BOUNDARY → `tests/tokyo_northwest_boundary.gd:289 southwest`；11配置两层历史21条补充差集，精确R310/R203身份，不重复旧69条；原生重载及游戏楼保护。

R309 SOUTHWEST全LOD → `tests/tokyo_residential_preview.gd:490 northwest_matrix`；七配置保存重载、近档复用。原生块面 → `tests/build_tokyo_northwest_blocks.gd:9 run`；585块/112资源、各档同owner，已知高度层守恒。

R308 RESIDENTIAL_SOUTHWEST → `tests/tokyo_residential_preview.gd:100 run`；R307精确输入、正式游戏楼保护、原版/双候选三距离与kept导出，拒绝邻区矩阵混用。

R307 RESIDENTIAL_SOUTHWEST_EXPORT → `tests/tokyo_residential_preview.gd` / `export_northwest`；精确R305西南三层导出，保留旧默认，为低楼块面准备原生基准。

R300 SOUTH_SEAMS_REVIEW → `tests/tokyo_canonical_review.gd` / `run`；R299精确目录/覆盖、九区28位+南侧六位，真实Loading/Survivor首帧与稳态图，保留预算失败。

R299 SOUTH_LAYOUT → `tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`；精确南侧新目录三近档切分、几何守恒及逐配置覆盖重证，不改变正式默认。

R298 SOUTH_COMBINED → `tests/build_tokyo_northwest_catalog.gd` / `native_binding`，build/audit共用；精确R297+旧九区全开关，保留R274默认配对。`rendering/tokyo_canonical_catalog.gd` / `extension_valid`接受新九区manifest但不扩大覆盖。

R296 SOUTH + NORTHWEST_BLOCKS_OUT → `tests/build_tokyo_northwest_blocks.gd` / `run`；保护游戏楼、保留旧三片合并，核高度/标高/固定引用与联合面数，不修改默认目录。

R295 SOUTH + NORTHWEST_MATRIX → `tests/tokyo_residential_preview.gd` / `northwest_matrix`；复用旧七配置来源、不重导出，780选择、独立保存及conserved重载核对，邻区组合拒绝。

R294 RESIDENTIAL_SOUTH → `tests/tokyo_residential_preview.gd:100 run`；要求NORTHWEST独立模式，绑定计划/selection SHA、780选择和南侧相机，read_source/inspect_bounds实际保护门通过才渲染。

R290 DEPTH_LAYER / DEPTH_HYBRID → `tests/tokyo_layered_depth_review.gd:6 run`；分别隔离负层遮挡、正层采样和原生道路混合候选，仅LAYERED_DEPTH_REVIEW显式测试消费。

R289 LAYERED_DEPTH_REVIEW → `tests/tokyo_layered_depth_review.gd:6 run`；同原生源对照正负分层、两档分辨率/格式、旋转与高度零遮挡，scale1仅越界诊断；不启用正式地图。

R288 LAYERED_TEXTURE_REVIEW → `tests/tokyo_layered_texture_review.gd:6 run`；LAYERED_MIP_FIX选择精确修正版BC3。`tools/tokyo_premultiplied_mips.py` / `halve`避免RGBA.resize再次处理alpha，不更改旧图块默认。

R282 NINE_GUARD2 → `rendering/tokyo_canonical_overlay.gd` / `_load_archive` / `_prepare_target`；R281核验后的R276显式候选，未知目录/缺双开关拒绝，默认关闭。

R281 GUARD2_CATALOG_AUDIT → `tests/tokyo_guard2_catalog_audit.gd:6 run` / `tests/tokyo_guard2_catalog_audit.gd:27 inspect`；LOD1full与LOD2guarded实际资源配对核验，不冒充近景Visual或预算通过。

R277 NINE_SEAMS_REVIEW → `tests/tokyo_canonical_review.gd` / `run`；28位真实Loading/Survivor静态审图，R276目录/覆盖精确绑定，非连续运动或性能通过。

R276 NINE_REGION_LAYOUT → `tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`、`tests/build_tokyo_rebalanced_coverage.gd` / `build`；九区只改三近档分块、逐配置重证覆盖，非任意目录兼容。

R275 NORTH_RIGHT_COMBINED → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`；west_north_right合同 → `rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`；精确登记/原生/边界身份，不覆盖正式默认。

R273 NORTH_RIGHT_PALETTE → `tests/build_tokyo_north_palette.gd` / `build`；复用既有Palette规则，R272→R273仅RGB变化。

R272 NORTH_RIGHT全LOD → `tests/tokyo_residential_preview.gd` / `northwest_matrix`、`tests/build_tokyo_northwest_blocks.gd` / `run`；复用R270近档导出，七档同块面及保留层复核。

R271 NORTH_RIGHT → `tests/tokyo_residential_preview.gd` / `run`；R270双候选三距离原生材质对照，保留层导出供独立压盖审计。

R270 NORTH_RIGHT_EXPORT → `tests/tokyo_residential_preview.gd` / `export_northwest`；16格三层守恒导出供右翼合并候选，不替换生产默认。

R269 RIGHT_SOURCE_REVIEW → `tests/tokyo_cells_visual.gd` / `_capture_sample`；精确绑定R268，12个重叠中心各5/8倍三态对照，正式默认不变。

R267 LEFT_SEAMS_REVIEW → `tests/tokyo_canonical_review.gd` / `run`；精确R263两共边放大/缩回/双向旋转逐站验收，正式默认不变。

R264 NEAR_LAYOUT覆盖重证 → `tests/build_tokyo_rebalanced_coverage.gd` / `build`；精确R263目录与R261来源依赖，不迁移旧叶token。

R263 NEAR_LAYOUT → `tests/tokyo_rebalanced_layout.gd` / `run`、`tests/build_tokyo_rebalanced_catalog.gd` / `build`；精确近档候选元数据对照 → `tests/tokyo_canonical_cut_probe.gd` / `run`。不改旧R237默认，不复用旧覆盖token。

R262 NORTH_LEFT_CUT_PROBE → `tests/tokyo_canonical_cut_probe.gd` / `run`；精确R261接缝三中心成本诊断，selected_details定位叶页，不是GPU帧时证据。

R261 NORTH_LEFT_COMBINED → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`；west_north_left四矩形覆盖 → `rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`。精确R260身份、旧四开关全部必需，正式默认不变。

R258 NORTH_LEFT + 配对EXPORT七档 → `tests/tokyo_residential_preview.gd` / `northwest_matrix`；105块/112归档 → `tests/build_tokyo_northwest_blocks.gd` / `run`；精确R256/R257及新矩阵SHA，来源/标高保持，尚未正式接合。R257 `export_northwest`/`run`仍为源导出和候选预览入口。

R255缓存重放漏边角来源 → `tools/build_tokyo_volume_region.py` / `RegionCollector.load_cache`；回归 → `tools/test_tokyo_volume_region.py` / `test_cache_preserves_bbox_only_corner_source`。与直接PBF扫描共用包络判定，不改已保存源或正式地图。

R254零面层投影短路 → `experiments/tokyo_spatial_select.gd:6 visible`；等价回归 → `tests/test_tokyo_hierarchical_pages.gd` / `_test_visible_equivalence`。只跳过无效包络，不改非空层覆盖或切面顺序。

R253切面组合差分 → `tests/test_tokyo_hierarchical_pages.gd` / `_test_combine_equivalence`，256组完整有序结果与输入守恒。延迟分配实验见工程手册；未推广运行时。

R252地图子阶段墙钟 → `rendering/tokyo_canonical_overlay.gd:200 _step_geometry`，诊断开启时细分geometry父桶；已有求解器 → `experiments/tokyo_spatial_cut.gd:6 choose`，可见性 → `experiments/tokyo_spatial_select.gd:6 visible`。归因结果见工程手册，不将父子桶重复相加。

R249七区接合 → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`，NORTH_SEAM_COMBINED绑定R247，既有R193-R203主体不变，三片增加层；输出使用R248的west_north_seam覆盖合同。

R248北侧覆盖 → `rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`，west_north_seam明确三矩形而非外包络；专项 → `tests/test_tokyo_regional_native.gd` / `_extension_contract`。

R246厂棚外壳候选 → `tests/build_tokyo_depot_union.gd:12 build`，复用原生有向差集与合批，七档只改owner0；缺输入回归 → `tests/test_tokyo_regional_native.gd:13 run`。不是正式地图推广。

R245源重叠专项 → `tests/tokyo_cells_visual.gd` / `_capture_sample`，NORTH_SOURCE_REVIEW绑定R244精确原生目录，1.95/5/8倍厂棚与休憩建筑三态对照，不是动态镜头验收。

R259/R244北侧调色 → `tests/build_tokyo_north_palette.gd:8 build` / `tests/build_tokyo_north_palette.gd:76 geometry_equal`；NORTH_LEFT_PALETTE绑定R258，默认R243不变；显式入口 → `tests/tokyo_canonical_cut_probe.gd:11 run`的NORTH_PALETTE分支；RGB/alpha守恒回归 → `tests/test_tokyo_palette.gd:10 run`。

R243 NORTH_SEAM七档矩阵 → `tests/tokyo_residential_preview.gd` / `northwest_matrix`；北侧成品归档 → `tests/build_tokyo_northwest_blocks.gd` / `run`，精确R241/R242/矩阵SHA，旧西北与外围西侧默认不变。

R242 NORTH_SEAM_EXPORT / NORTH_SEAM → `tests/tokyo_residential_preview.gd` / `export_northwest` / `run`，新片同源完整属性与整组件保留网格预览，禁止与OUTER_WEST组合；新片全LOD未制作。

R238 REBALANCE_COVERAGE → `tests/tokyo_canonical_cut_probe.gd:11 run` → `tests/build_tokyo_rebalanced_coverage.gd:8 build`；11档原生源面多重集、全中间/最细切面和缺失依赖反例，输出独立coverage供显式Visual读取，不改生产默认。

R237 REBALANCE_BUILD → `tests/tokyo_canonical_cut_probe.gd:11 run` → `tests/build_tokyo_rebalanced_catalog.gd:8 build`；全原生父11重分、原父几何递归对拍，165其他根不变。新目录无coverage，禁止直接接正式覆盖屏蔽。

R236 REBALANCE_LAYOUT → `tests/tokyo_canonical_cut_probe.gd:11 run` → `tests/tokyo_rebalanced_layout.gd:6 run`；精确R232源、原生有向几何守恒和16叶布局输出，仅候选准备，所有LOD共享布局后方可接目录。

R232 NORTHWEST_OUTER_COMBINED → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`，需两个旧COMBINED开关；精确原生/重载配对反例 → `tests/test_tokyo_regional_native.gd` / `_extension_contract`。

R232 NORTHWEST_OUTER_REVIEW共边机位 → `tests/tokyo_canonical_review.gd` / `run`，不改变原预算或正式默认。

R231外围西侧L形覆盖 → `rendering/tokyo_canonical_catalog.gd` / `presentation_archive`；有限六区身份 → `extension_valid`；未制作西南区不覆盖/原索引不变/身份反例 → `tests/test_tokyo_regional_native.gd` / `_extension_contract`。

R229外围西侧六LOD+mid4 → `tests/tokyo_residential_preview.gd` / `northwest_matrix`；249街区固定owner与112原生归档 → `tests/build_tokyo_northwest_blocks.gd` / `run`，旧西北三片不变。

R228 OUTER_WEST_EXPORT → `tests/tokyo_residential_preview.gd` / `export_northwest`；RESIDENTIAL_OUTER_WEST预览 → 同文件`run`，只读R227源及R228计划，正式地图不变。

R225 SHADOW_CACHE_BENCH（需BOUNDED_LEGACY_BENCH）→ `tests/tokyo_volume_combat_runner.gd` / `_ready`；实际缓存身份/重建数 → `_bench_finish_now`，两组保留修正后视图失效逻辑。

R224定点缩放/视口失效 → `survivor/building_renderer.gd` / `consume_view_change` / `_process`；审图暂停例外与恢复 → `tests/tokyo_canonical_review.gd` / `run`，不改变真实碰撞或缓存默认。

R223 SHADOW_CACHE_REVIEW（需BOUNDED_LEGACY_REVIEW）→ `tests/tokyo_canonical_review.gd` / `run`；旧楼阴影缓存 → `survivor/building_renderer.gd` / `shadow_packet`，默认关闭；真实来源数组等价/复用及单元失效门分别保留。

R221 BOUNDED_LEGACY_BENCH + BENCH_LEGACY → `tests/tokyo_volume_combat_runner.gd` / `_ready`；身份与可见性 → `_bench_finish_now`。沿原C1巡检/墙钟硬门，不使用隐藏旧楼组。

R220 BOUNDED_LEGACY_REVIEW → `tests/tokyo_canonical_review.gd` / `run`；连续有界径向投影 → `survivor/building_renderer.gd` / `bounded_roof_offset` / `_draw_one`；几何边界测试 → `tests/test_tokyo_regional_native.gd` / `run`。

R219 LEGACY_LAYER_REVIEW → `tests/tokyo_canonical_review.gd` / `run`，旧楼表现层三机位隐藏/恢复诊断，原碰撞/预算检查保持。

R218 NORTHWEST_COMBINED + NORTHWEST_EAST_COMBINED → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `audit_join`；有限身份 → `rendering/tokyo_canonical_catalog.gd` / `extension_valid`；东侧实际机位 → `tests/tokyo_canonical_review.gd` / `run`，其余接合/预算门不改。

R216 RESIDENTIAL_NORTHWEST_EAST + MATRIX → `tests/tokyo_residential_preview.gd` / `northwest_matrix`；BLOCKS_OUT → `tests/build_tokyo_northwest_blocks.gd` / `run`，绑定R210成品/东侧计划与七档矩阵，112归档保留中央+西侧；空输入 → `test_tokyo_regional_native.gd` / `run`。

R215 RESIDENTIAL_NORTHWEST + RESIDENTIAL_NORTHWEST_EAST → `tests/tokyo_residential_preview.gd` / `run`，认证东侧计划/选择与原R198三层，不覆盖中央/西侧成果；全档矩阵及联合归档后续单验。

R214 LOW_WALL_MANIFEST → `rendering/tokyo_low_wall_manifest.gd` / `paired_identity` / `read`认证R212/R213新对；四对矩阵 → `tests/test_tokyo_low_walls.gd` / `checks`；新西侧静态/连续机位 → `tests/tokyo_low_wall_review.gd` / `run`的NORTHWEST_WEST_REVIEW。

R213 WALL_PAGES_NORTHWEST + NORTHWEST_COMBINED → `tests/build_tokyo_wall_pages.gd` / `run` / `audit`；`tokyo_cells_lifecycle_runner.gd` / `_ready`指向r213-wall-pages-a，验8645墙/33切面及联合字节成本。

R213 NORTHWEST_COMBINED + NORTHWEST_WALLS → `tests/build_tokyo_northwest_walls.gd` / `run`，旧5287墙+新3358墙，沿`partition`/原生差集/保存重载验证；反例 → `test_tokyo_regional_native.gd` / `run`保留旧模式并验双模式空输入拒绝。

R212 NORTHWEST_WEST_REVIEW → `tests/tokyo_canonical_review.gd` / `run`，既有西北八机位在显式开关下检查新西侧；原Loading/组件对拍及预算门保留。

R210 RESIDENTIAL_NORTHWEST_MATRIX + RESIDENTIAL_NORTHWEST_WEST → `tests/tokyo_residential_preview.gd` / `northwest_matrix`，精确R199原始七配置复用与新西侧保留层输出；来源清单/源网格摘要匹配，不从旧kept生成原始来源。

R210 NORTHWEST_BLOCKS_OUT + RESIDENTIAL_NORTHWEST_WEST → `tests/build_tokyo_northwest_blocks.gd` / `run`，在R199中央成品上增加新西侧，计数对照两份认证矩阵真实净差，逐格保存重载，不更改玩法来源。

R209 RESIDENTIAL_NORTHWEST_WEST → `tests/tokyo_residential_preview.gd` / `run`，须同时NORTHWEST，精确新计划/选择身份；原保留层、正式材质与九图流程复用，不启用正式地图。

R208 SUBMISSION_NORTHWEST → `tests/tokyo_submission_duplicate_audit.gd` / `run`，精确R206提交峰120349固定面与R204资源匹配，完整属性重复审计/颜色分桶，不改资源或预算门。

R208文件摘要来源 → 同脚本`entry_digest`目录树递归，不能从逻辑descriptor读取sha256；反例 → `tests/test_tokyo_regional_native.gd` / `run`。

R207 BENCH_NORTHWEST → `tests/tokyo_volume_combat_runner.gd` / `_ready`，相同C1真实负载的西北锚点；不新增tick或改变巡检/性能门。

R206 LOW_WALL_MANIFEST → `rendering/tokyo_low_wall_manifest.gd` / `paired_identity` / `read`精确R204/R205身份；`tests/test_tokyo_low_walls.gd` / `checks`配对矩阵反例；NORTHWEST_REVIEW → `tests/tokyo_low_wall_review.gd` / `run`同位对拍与连续运动，新旧加载器/渐隐算法不变。

R205 NORTHWEST_WALLS → `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` → `tests/build_tokyo_northwest_walls.gd` / `run` / `partition`，复用packed差集、原生subset与save_checked；精确5287墙面成员证明，不单独启用屋顶目录。

R205 WALL_PAGES_NORTHWEST → `tests/build_tokyo_wall_pages.gd` / `run` / `visit` / `audit`原分页及费用审计；`test_tokyo_regional_native.gd` / `run`分层反例和守恒，不新增运行时tick。

R204/R212 NORTHWEST_CATALOG → `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` → `tests/build_tokyo_northwest_catalog.gd` / `native_binding` / `build` / `finish`，NORTHWEST_COMBINED仅切换R211认证来源，默认R201，BOUNDARY保持；AUDIT → `audit_join` / `audit_entry`，693页/组件/coverage/原切线守恒；新旧归档身份 → `rendering/tokyo_canonical_catalog.gd` / `extension_valid`，反例 → `test_tokyo_regional_native.gd` / `_extension_contract`；真实8机位中心 → `tokyo_canonical_review.gd` / `run`的NORTHWEST_REVIEW。

R203成品近档法线来源 → `tests/tokyo_northwest_boundary.gd` / `historical_target` / `select_historical`，复用`tokyo_residential_patch.gd` / `decode`及`build_tokyo_path_lod.gd` / `subset`；原生差集仍精确，`audit`另进程重载、`tokyo_cells_lifecycle_runner.gd` / `_ready`显式调用；`test_tokyo_regional_native.gd` / `run`新增来源选择反例。

R202 NORTHWEST_BOUNDARY → `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` → `tests/tokyo_northwest_boundary.gd` / `run`，复用既有Boundary.target_meshes/Diff与Gameplay检查；`compare_positions`仅诊断，`decoded_roundtrip`目标编码复现不能绕过原生差集门；`test_tokyo_regional_native.gd` / `run`检查重复/高度/颜色/缺参。

R201原生owner迁移索引兼容 → `tests/build_tokyo_regional_native.gd` / `subtract` / `conserved` → `experiments/tokyo_packed_mesh_difference.gd`；旧非索引路径保留，`tests/test_tokyo_regional_native.gd` / `run`补两布局守恒反例。沿既有构建/独立saved audit入口，不新增加载器。

R199西北全原始档位 → `tests/tokyo_residential_preview.gd` / `northwest_matrix` / `export_northwest`；同块面固定分格归属的独立目录 → `tests/build_tokyo_northwest_blocks.gd` / `run`，来源、标高、固定层与真实矩阵成本守恒；非法入口 → `test_tokyo_residential_selection.gd` / `checks`；调用 → `tokyo_cells_lifecycle_runner.gd` / `_ready`。

R198西北近档完整来源 → `tests/tokyo_residential_preview.gd` / `export_northwest`；真实保留层与双候选同位预览 → 同文件`run` / `retained_mesh` / `blocks_mesh`，沿用`tokyo_residential_selection.gd` / `partition`与`tokyo_packed_mesh_join.gd` / `conserved`，不另建选择/合并算法。

R197样片构建输出门 → `tests/build_tokyo_cells.gd` / `run`；开放屋盖不得参与住宅合并 → `tests/build_tokyo_far_clusters.gd` / `eligible`、`tools/build_tokyo_footprint_lod.py` / `eligible`，后者由shell/block规划共用。实际源基线重载和三态截图沿用`audit_tokyo_region_sample.gd` / `run`与`tokyo_cells_visual.gd` / `_capture_sample`。

R196开放屋盖原生生成 → `experiments/tokyo_volume_preview_factory.gd` / `_add_ring_building`；三档几何与显式真实源回归 → `tests/test_tokyo_volume_ring_geometry.gd` / `run`。不改已烘焙地图或玩法权威。

R194模糊矩形责任定位 → `tests/tokyo_coverage_gap_probe.gd` / `run` 的原生像素反投影与实际archive覆盖，`tokyo_low_wall_review.gd` / `run` 显式只读调用；AABB结果不冒充逐三角覆盖证明。

R193北侧目录及双槽清单 → `tests/build_tokyo_residential_catalog.gd` / `run`、`build_tokyo_wall_pages.gd` / `run` / `audit`；认证运行时 → `rendering/tokyo_low_wall_manifest.gd` / `read` 精确新旧配对；北侧实际同位审查 → `tests/tokyo_component_review.gd` / `run`、`tokyo_low_wall_review.gd` / `run`、`tokyo_canonical_review.gd` / `run`。旧默认与预算门不变。

R192北侧联合分层 → `tests/build_tokyo_wall_bundle.gd` / `run` 的WALL_BUNDLE_NORTH入口；仍由 `save_checked` 验原生重载和有向属性守恒，3313墙面独立计数，非运行时目录接线。

R191北侧原生九图 → `tests/tokyo_residential_preview.gd` / `run` 的RESIDENTIAL_NORTH精确计划/205轮廓身份、区域与三距离机位；沿用 `retained_mesh` 的原生整组件保留，禁止与WEST/旧矩阵混用。

R189瓦片超额请求 → `survivor/raster_basemap_renderer.gd` / `_request_target_tiles`、`_add_tile`、`_remove_resident`、`debug_state`；三图容量反例 → `tests/raster_capacity_lifecycle_case.gd` / `run` / `_map_case`（Fixture固定可见集合，加载/绑定/退役仍用正式入口），`tokyo_cells_lifecycle_runner.gd` 的RASTER_CAPACITY_UNIT和`lifecycle_gauntlet_runner.gd`共用。实际急转容量由`tokyo_low_wall_review.gd` / `run`追加frame_post_draw观察，不缩减原路线。

R188低墙LOD → `rendering/tokyo_low_wall_binding.gd` / `fade_for_scale` / `apply_fade`；`tokyo_canonical_overlay.gd` / `_refresh_low_wall_lod` / `set_low_wall_full_override` 接原尺度更新与Loading暖绘，`tokyo_cells_overlay.gd` / `_apply_visibility` 保留逻辑覆盖，`tokyo_hierarchical_overlay.gd` / `debug_state` 区分驻留与提交。`tests/tokyo_low_wall_review.gd` / `run` 为实际地图近远恢复和连续运动检查；原full组件对照独立强制完整墙。

R187低墙接线 → `rendering/tokyo_low_wall_manifest.gd` / `read` / `replace_row`；`tokyo_low_wall_binding.gd` / `create_slot` / `bind` / `clear` / `faces`；`tokyo_component_stream.gd` / `resource` 与 `tokyo_canonical_spatial_page.gd` / `valid` 两槽共享引用。规范overlay `_bind_target` / `_remove_cell` 绑定与清理，Loading身份在 `tokyo_volume_preload.gd` / `start` / `take` / `_begin`。反例与真实退出 → `tests/test_tokyo_low_walls.gd` / `fixture` / `checks` / `lifecycle`；同位原图比较 → `tests/tokyo_component_review.gd` / `run`；原生计数与菜单释放 → `tests/tokyo_draw_geometry_probe.gd` / `capture`、`tests/tokyo_preload_route_probe.gd` / `run`。

R186低墙页所有权资产 → `tests/build_tokyo_wall_pages.gd` / `visit` / `run`，有限R185源、原cuts分桶、双槽组件去重与重载守恒；`cut_cost` / `audit` 审核切面/联合物理字节及墙面守恒。显式制作入口 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。

R185西侧Loading后八机位 → `tests/tokyo_canonical_review.gd` / `run`，显式WEST_REVIEW中心，旧住宅机位不变。

R185完整西侧归档 → `tests/build_tokyo_residential_catalog.gd` / `run` / `verify_pages`，WEST_FULL有限原生报告身份，旧R162配方不变。

R185原生墙层归档准备 → `tests/build_tokyo_wall_bundle.gd` / `run` / `save_checked`；原生重载与三角属性多重集分区守恒，完整层报告复用住宅目录生成器。

R184低墙渐隐序列 → `tests/tokyo_wall_fade_sequence.gd` / `run`；现有材质outgoing/lod_mix、单墙层、隐藏端点和真实视口统计，不作为游戏帧时。

R183低墙原生四尺度三旋转 → `tests/tokyo_roof_proxy_review.gd` / `run`；完整/候选/恢复三态，独立视口不冒充游戏AO/连续路线。

R182完整楼体LOD → `tests/tokyo_retained_lod_probe.gd` / `run` / `generate_variants`；BUILDINGS精确清单索引子集，未归属33面不参与简化。

R181西侧保留层离线简化 → `tests/tokyo_retained_lod_probe.gd` / `run`；有限来源与实际API签名、两角度各档载荷导出，入口 `tests/tokyo_cells_lifecycle_runner.gd` / `_ready`。

R179道路区双候选 → `tests/tokyo_residential_preview.gd` / `run`，WEST_ROAD精确摘要及707组件，保留旧模式与矩阵拒绝。

R178西侧双候选 → `tests/tokyo_residential_preview.gd` / `run` / `retained_mesh`，WEST有限身份、整组件选择、原形同位参考与旧矩阵拒绝。

R177分阶段实际提交 → `tests/tokyo_draw_geometry_probe.gd` / `capture` / `_verify_report` / `summary`；住宅24万面门 → `tests/tokyo_tile_stream_review.gd` / `run`，不清空生产总峰。

R176高清连续边界 → `tests/tokyo_tile_stream_review.gd` / `run`，显式RESIDENTIAL_REVIEW、真实draw两侧应用和恢复计数，保留默认北侧路线。

R175借用地表交接 → `rendering/tokyo_fixed_atlas_layer.gd` / `borrowed_overlap` / `_update_region`；相交及跨帧恢复 → `tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `lifecycle`；源色隔离 → `tests/tokyo_tile_stream_review.gd` / `projected_check`。

R173高清父11预载与切档 → `rendering/tokyo_fixed_atlas_layer.gd` `region_contract` / `eligible` / `fixed_configuration` / `manifest_row` / `_bind_region` / `update` / `_update_region`；独立预算 → `tests/tokyo_preloaded_ao_review.gd` `fixed_region_bytes` / `fixed_atlas_bytes`、`tools/audit_tokyo_ao_preload.py` `fixed_atlas_bytes`；回归 → `tests/test_tokyo_fixed_atlas_layer.gd` `checks` / `collection_lifecycle`。

R172已认证LOD3静态配置 → `tests/tokyo_fixed_atlas_review.gd` `fine_configuration` / `run`；原生导出 → `tests/export_tokyo_fixed_mesh.gd` `run`。

R172高清地表静态资格 → `tests/tokyo_fixed_atlas_review.gd` `complete_fine` / `run`；缩放/覆盖反例 → `tests/test_tokyo_tile_ground.gd` `run`。

R172过渡来源导出 → `tests/export_tokyo_fixed_mesh.gd` `run`（R162 lod2_guarded、唯一载荷名称与拒绝覆盖）；入口 → `tests/tokyo_cells_lifecycle_runner.gd` 的FIXED_EXPORT_CONFIG。

R171单次图集扫描 → `rendering/tokyo_fixed_atlas_layer.gd` `update` / `_update_region`；常量独立查询 → `region_contract` / `eligible`；隔离与多批次 → `tests/test_tokyo_fixed_atlas_layer.gd` `checks` / `collection_lifecycle`。

R170固定属性导出 → `tests/export_tokyo_fixed_mesh.gd` `run`；有限跨档资格 → `rendering/tokyo_fixed_atlas_layer.gd` `fixed_configuration` / `_update_region`；恢复/拒绝 → `tests/test_tokyo_fixed_atlas_layer.gd` `checks` / `collection_lifecycle`。

R169新目录图集合同 → `rendering/tokyo_fixed_atlas_layer.gd` `region_contract` / `collection_entries` / `eligible` / `manifest_row` / `_bind_region` / `_update_region`；拒绝与取消 → `tests/test_tokyo_fixed_atlas_layer.gd` `checks` / `collection_lifecycle`。

R168住宅地表集合 → `tools/revalidate_tokyo_auxiliary.py` `fixed_source_matches` / `revalidate_residential_fixed`；反例 → `tools/test_tokyo_auxiliary_revalidation.py` `test_fixed_source_requires_full_identity_and_live_bytes`。

R167新源对拍及反例 → `tests/tokyo_fixed_atlas_review.gd` `run`；`tests/test_tokyo_tile_ground.gd` `_test_fixed_expansion`。

R167新源BC3 → `tests/build_tokyo_fixed_atlas_bc3.gd` `region_contract` / `manifest_valid` / `run`；仅离线双摘要许可。

R166原生manifest反例 → `tools/test_tokyo_fixed_atlas.py` `test_residential_source_requires_exact_manifest`。

R166地表新源 → `tools/build_tokyo_fixed_atlas.py` `read_native`，精确目录及manifest双摘要，新源重烘而非旧图集兼容声明。

R164固定重复面 → `tests/tokyo_submission_duplicate_audit.gd` `run`；只读快照实际固定层，非运行时去重许可。

R163住宅实战帧时 → `tests/tokyo_volume_combat_runner.gd` `_ready`，BENCH_RESIDENTIAL保留既有C1/near负载。

R163住宅正式审图 → `tests/tokyo_canonical_review.gd` `run`，显式RESIDENTIAL_REVIEW八机位，源就绪/覆盖门复用。

R162住宅归档 → `tests/build_tokyo_residential_catalog.gd` `run` / `verify_pages`，复用原cuts/组件/coverage，逐页重载低楼和未改层。

R161修正原生输入 → `tests/tokyo_residential_patch.gd` `run`，有限报告摘要及full_original_source门；不使用旧kept区外候选。

R161区外原始来源 → `tests/tokyo_residential_preview.gd` `run` / `matrix`；显式source模式导出未删减低楼，保留历史kept反例。

R160原生导入与重载 → `tests/tokyo_residential_patch.gd` `decode` / `run`；同机位 → `capture`；反例 → `checks`，接tile_ground默认回归。

R158裁切属性源 → `tests/tokyo_residential_preview.gd` `export_attributes`，由`export_kept`在XYZ之后追加伴随文件。

R155父11各配置保留层 → `tests/tokyo_residential_preview.gd` `matrix` / `run` 的RESIDENTIAL_MATRIX入口。

R153实际保留层导出 → `tests/tokyo_residential_preview.gd` `export_kept`；整组件预览消费者 → `retained_mesh` / `run`。

R342离线选择吞吐 → `tests/tokyo_residential_selection.gd` / `index_shapes` / `indexed_inside` / `partition`：空间桶及重复投影点缓存，精判仍沿`inside`；`root_of`保持完整XYZ组件归属。反例与原算法格点/边缘对照 → `tests/test_tokyo_residential_selection.gd` / `checks`；原生差集与游戏目录行为不变。

R152住宅原生资产对拍 → `tests/tokyo_residential_preview.gd` `blocks_mesh` / `retained_mesh` / `run`；入口 `tests/tokyo_cells_lifecycle_runner.gd` `_ready` 的RESIDENTIAL_PREVIEW分支。基线/两候选同相机，独立无光照顶点色预览，不是正式游戏渲染路线。

R151限定AO认证 → `tools/revalidate_tokyo_auxiliary.py` `revalidate_rail_ao` / `same_ao_source`；显式配方反例 → `tools/test_tokyo_auxiliary_revalidation.py` `test_rail_pair_is_explicit_and_directed`。只生成新AO辅助清单，不认证固定地表或修改运行时门。

R150父11保留父12归档 → `tests/build_tokyo_rail_catalog.gd` `recipe` / `planned_mesh` / `run` / `finish_rails` / `audit`；配方反例 → `tests/test_tokyo_rail_catalog.gd` `checks`。

R150相邻区域障碍 → `tests/export_tokyo_rail_obstacles.gd` `region_for_parent` / `projected_overlap` / `corners` / `run`；区域隔离反例 → `tests/test_rail_obstacle_export.gd` `checks`。

R149逐页保存核验 → `tests/build_tokyo_rail_catalog.gd` `audit_entry` / `audit`；父12原生七机位 → `tests/tokyo_canonical_review.gd` `run` 的RAIL_REVIEW。

R149全配置共享铁路 → `tests/build_tokyo_rail_catalog.gd` `partition` / `planned_mesh` / `run` / `finish_rails`；分桶反例 → `tests/test_tokyo_rail_catalog.gd` `checks`；显式构建 → `tests/tokyo_cells_lifecycle_runner.gd` `_ready`。复用原固定层归档，不修改默认。

R148原生铁路障碍 → `tests/export_tokyo_rail_obstacles.gd` `projected_overlap` / `corners` / `run`；导出反例 → `tests/test_rail_obstacle_export.gd` `mesh` / `checks`；显式离线入口 → `tests/tokyo_cells_lifecycle_runner.gd` `_ready`；地表focused/all → `tests/test_tokyo_tile_ground.gd` `run`。原生归档尚未替换铁路，进度见东京spec和工程审计。

R146 Python六图块计账 → `tools/audit_tokyo_ao_preload.py` `fixed_atlas_bytes`；反例 → `tools/test_tokyo_ao.py` `test_fixed_collection_reservation`。R147铁路地块候选仍由现有固定图块raster/BC3/review验证，制作脚本与证据在当次工程审计定位，不增加第二个运行时渲染器。

R146有限集合与事务 → `rendering/tokyo_fixed_atlas_layer.gd` `region_contract` / `collection_entries` / `bind` / `_bind_region` / `members` / `refresh_stats` / `_suspend_region` / `_update_region` / `warm_ready` / `close`。多区在途取消/近景恢复/预算拒绝 → `tests/test_tokyo_fixed_atlas_layer.gd` `Fixture._add_mesh` / `collection_lifecycle`；独立逐片预算 → `tests/tokyo_preloaded_ao_review.gd` `fixed_region_bytes` / `fixed_atlas_bytes`。全部纹理交接与释放、实际图元、五区原生接缝分别由 `tests/tokyo_preload_route_probe.gd` `run`、`tests/tokyo_draw_geometry_probe.gd` `capture`、`tests/tokyo_canonical_review.gd` `run` 覆盖。

R145 Python来源/覆盖反例 → `tools/test_tokyo_fixed_atlas.py` `test_only_certified_source_catalogs` / `test_opaque_padding_keeps_rectangular_interior_and_shape` / `test_opaque_padding_rejects_subpixel_hole`。

R145扩区制作与接缝排查 → `tools/build_tokyo_fixed_atlas.py` `valid_source_manifest` / `opaque_rectangular_padding` / `raster` / `build`；原生R143导出仍为`tests/export_tokyo_fixed_mesh.gd` `run`。有限区域/BC3纯色编码 → `tests/build_tokyo_fixed_atlas_bc3.gd` `region_contract` / `manifest_valid` / `flat_rgb_block` / `patch_flat_blocks` / `run`。静态完整层资格与原生恢复 → `tests/tokyo_fixed_atlas_review.gd` `complete_native` / `run`，反例由`tests/test_tokyo_tile_ground.gd` `_test_fixed_expansion` / `_test_flat_bc3`及`tools/test_tokyo_fixed_atlas.py`负责。显式夹具互斥入口在`tests/tokyo_preload_route_probe.gd` `run`；没有扩展生产所有者，不把静态图元节省当实战帧时。

R144显式NEAR_DOMINANCE → `rendering/tokyo_canonical_overlay.gd` `_load_archive` / `_setup_geometry` / `_select_cut` / `debug_state` → `experiments/tokyo_guarded_pair_reuse.gd` `native_index` / `near_choice`，配置树为几何包络权威、descriptor为身份/驻留权威。原切面LOD5备用经完整覆盖/同空间来源/原生可见面量/联合成本门后使用，不新增第二次树求解。反例 `tests/test_tokyo_cut_reuse.gd` `run`；只读依据沿用 `tests/tokyo_canonical_cut_probe.gd` `run` 的48机位，`tests/tokyo_canonical_review.gd` `run`显式追加真实full4六位，不修改原LOD4 mid或正式默认。

R143近层目录 → `tests/build_tokyo_street_catalog.gd` `recipe` / `inputs` / `run` / `_finish` / `audit`，仅STREET_NEAR_CATALOG选择近层配方；`tests/test_tokyo_street_catalog.gd` `run` 验双配方/数字/来源矩阵。已有辅助资产再认证 → `tools/revalidate_tokyo_auxiliary.py` `digest` / `same_ao_source` / `revalidate`，反例 `tools/test_tokyo_auxiliary_revalidation.py` `test_native_window_identity_and_multiplicity`；`rendering/tokyo_canonical_catalog.gd` `UNCHANGED_FIXED_LOD12_CATALOGS` 为有限摘要表，`tokyo_canonical_overlay.gd` `_load_archive` / `tokyo_fixed_atlas_layer.gd` `manifest_row` 保持实际目录与清单绑定。LOD5实战专项 → `tests/tokyo_volume_combat_runner.gd` `_ready` 的BENCH_CLOSE，只改近景倍率，实际当前/峰路径及原门由 `_bench_finish_now` 输出。

R142近景初始分组 → `tools/build_tokyo_block_lod.py` `contract` / `prepare` / `road_components` / `shape_acceptable`，`tests/build_tokyo_far_clusters.gd` `group_limit` / `_convert`，`tools/audit_tokyo_far_clusters.py` `audit`。`tools/test_tokyo_block_lod.py` `test_near_street_keeps_existing_near_contract` / `test_near_street_shape_filter_only_restricts_new_groups`覆盖跨网格、原合同不变、形状及道路/尺度拒绝，GDScript合同/JSON往返反例沿用`tests/test_tokyo_far_clusters.gd` `run`；不以离线省面替代真实提交或帧时验收。

R141备用复用候选 → `experiments/tokyo_guarded_pair_reuse.gd` `family` / `choose`；`rendering/tokyo_canonical_overlay.gd` `_setup_geometry` / `_prepare_target` / `_restore_original` / `debug_state`；`tests/test_tokyo_cut_reuse.gd` `run`、`tests/tokyo_canonical_review.gd` `run` 的显式REUSE_REVERSAL_REVIEW。保留原目标几何与原事务权威，不做运行时增量树求解，实际结论见工程审计末节。

R141同历史归因 → `tests/tokyo_preload_route_probe.gd` `run`（显式跳过额外AO机位并标注）；`tests/tokyo_canonical_cut_probe.gd` `handoffs`（已有切面复用与更细备用跨档离线成本/覆盖）。`rendering/tokyo_cluster_overlay.gd` `_prepare_target` 的旧/新联合超额触发原形恢复，不等同 `rendering/tokyo_canonical_overlay.gd` `_select_cut` 的单独目标超额回退；后续显式候选见上段，未推广默认。

R141 AO联合接入 → `experiments/tokyo_baked_ao.gd` `track_material` / `strength` / `close` 与 `rendering/tokyo_fixed_atlas_layer.gd` `bind`；`tests/tokyo_preloaded_ao_review.gd` `fixed_atlas_bytes` / `cancelled_loading` / `run`、`tools/audit_tokyo_ao_preload.py` `fixed_atlas_bytes` / `audit`。弱引用、晚登记和跨帧释放反例在`tests/test_tokyo_ao.gd` `run` / `lifecycle`，离线预算反例在`tools/test_tokyo_ao.py` `test_joint_fixed_atlas_reservation`。

R141显式固定地表接入 → `rendering/tokyo_fixed_atlas_layer.gd` / `manifest_row` / `eligible` / `bind` / `warm_ready` / `suspend` / `update` / `close`，共用原生静态`shader_code` / `plane`；`tests/test_tokyo_fixed_atlas_layer.gd` / `checks` / `lifecycle` 接原focused/all/gauntlet。`tokyo_tile_ground_overlay`原tick和提交统计、`tokyo_volume_preload`路径身份及就绪门、`tokyo_preload_route_probe`同纹理/退出验证均显式启用，未推广默认。

R141固定地表离线候选 → `tools/build_tokyo_fixed_atlas.py` / `read_native` / `validate` / `raster` / `reduce_rgba` / `mip_bytes` / `build`；`tools/test_tokyo_fixed_atlas.py` / `FixedAtlasTests`。来源与预算/像素审查回链东京湾spec；自动接入是上述显式候选，不是正式默认。

R141 GL对拍 → `tests/build_tokyo_fixed_atlas_bc3.gd` / `run`，`tests/tokyo_fixed_atlas_review.gd` / `shader_code` / `plane` / `run`（原尺寸正面绕序、预乘采样、纹理释放）；`tests/tokyo_cells_lifecycle_runner.gd` / `_ready` 显式制作入口，`tokyo_preload_route_probe.gd` / `run` 显式Visual入口，`test_tokyo_tile_ground.gd` / `run` 拒绝反例。

R140新西片AO选区 → `tests/export_tokyo_ao.gd` / `region_for`；选区反例 → `tests/test_tokyo_ao.gd` / `run`。既有AO导出、压缩、预载/终态及独立像素审计不改身份门。

R140 AO取消暖绘定额 → `tests/tokyo_preloaded_ao_review.gd` / `warmup_bytes` / `cancelled_loading`，活视口512KiB、实际退出归零；`tests/test_tokyo_ao.gd` / `run` 验证欠费、queued-free和未知状态拒绝。

R139旧归属迁移 → `tests/build_tokyo_street_catalog.gd` / `without_transferred` / `disjoint_transferred`；STREET_REVIEW → `tests/tokyo_canonical_review.gd` / `run` 追加北岸真实多缩放/旋转接缝，保留原西区失败机位。

R139显式STREET_CATALOG → `tests/tokyo_cells_lifecycle_runner.gd` / `_ready` → `tests/build_tokyo_street_catalog.gd` / `inputs` / `run` / `replace_low` / `_finish`；来源矩阵门 `selected` / `valid_rows`，独立保存检查 `audit` / `_audit_entry`。`tests/test_tokyo_street_catalog.gd` / `run` / `_check` 由 `test_tokyo_far_clusters.gd` / `run` 纳入focused/all；STREET_AUDIT仅加载检查候选。

R138道路分隔邻接 → `tools/build_tokyo_block_lod.py` `road_components` / `prepare`；`tools/test_tokyo_block_lod.py` `test_street_components_cross_grid_not_road` / `test_street_profiles_keep_source_and_structural_anchors`。原生只接受street6/street8的显式LOD1/2合同：`tests/build_tokyo_far_clusters.gd` `group_limit`、`tests/test_tokyo_far_clusters.gd` `run`；独立几何/像素审计 `tools/audit_tokyo_far_clusters.py` `audit`。

R137岸线暖绘 → `rendering/tokyo_shoreline_warmup.gd` `configure` / `_ready` / `_after_draw` / `close` / `_exit_tree`；`rendering/tokyo_shoreline_layer.gd` `start_material_warm` / `material_warm_ready`；`rendering/tokyo_tile_ground_overlay.gd` `_setup_geometry` 初始化与 `rendering/tokyo_volume_preload.gd` `_process` 真实提交放行；`tests/test_tokyo_shoreline_layer.gd` `_material_warm_lifecycle` 预算拒绝、空提交、共享Shader、原生像素与跨帧释放。

R136显式RENDER_TRACE=backend → `tests/tokyo_volume_combat_runner.gd` / `_ready` → `tests/tokyo_render_trace.gd` / `setup` / `_after_draw` / `retain_backend_peaks` / `summary`，固定三视口七指标峰；`tests/test_perf_frame_trace.gd` / `_test_backend_peaks`独立反例。

R135 EXTENSION_CATALOG_BUILD → `tests/build_tokyo_cells.gd` / `run` → `tests/build_tokyo_extension_catalog.gd` / `_prepare` / `run` / `_finish_extension`；EXTENSION_CATALOG_AUDIT → `test_tokyo_regional_native.gd` / `run` → 新制作器`audit`。正式扩展身份在`rendering/tokyo_canonical_catalog.gd` / `extension_valid`，实际Loading观察复用`tokyo_canonical_review.gd` / `run`的EXTENSION_REVIEW；标准战场通过`tokyo_volume_combat_runner.gd` / `_ready`的BENCH_WEST_EXTENSION定位新片，不改战斗人口。

R134原生文件摘要差异调查 → `tests/test_tokyo_regional_native.gd` / `run`的REGIONAL_STABLE_OUTPUT → `tests/audit_tokyo_regional_native.gd` / `compare_previous`，按当前/旧manifest实际SHA重载224档，全部属性/打包面/解码几何不变才通过。

R134多片归属 → `tests/build_tokyo_regional_native.gd` / `valid_routes` / `read_routes` / `run`；独立原生检查 → `tests/audit_tokyo_regional_native.gd` / `run`。按区域显式街坊迁移 → `tests/build_tokyo_owned_region_blocks.gd` / `valid_config` / `run`，沿用`transfer`原生字节差集；配置反例 → `tests/test_tokyo_regional_native.gd` / `_routes_contract`。旧三片默认不变，不旁路规范Overlay身份门。

R133 REGION_SURFACE_REGION → `tests/build_tokyo_cells.gd` / `run` → `tests/build_tokyo_region_surface.gd` / `region_for` / `run` / `append_upward`，色板与独立AO使用同一显式区域；`tests/test_tokyo_cells.gd` / `run`核验默认/新选区与未知值拒绝。

R131当前西片AO → `tests/export_tokyo_ao.gd` / `region_for`显式west_density → 既有离线高度场/压缩工具。`tests/tokyo_preloaded_ao_review.gd` / `run`在当前相机与源瓦片稳定后抓三强度/恢复，不用旧ready；`tests/test_tokyo_ao.gd` / `run`核验新增范围。

R130 PATH_LOD_BUILD → `tests/build_tokyo_cells.gd` / `run` → `tests/build_tokyo_path_lod.gd` / `run` / `partition` / `subset` / `_finish_catalog`；`build_tokyo_block_catalog.gd` / `_replace_layer`按既有切线只替换一层，`_replace`保留旧低层入口。PATH_LOD_AUDIT → `test_tokyo_regional_native.gd` / `run` → `build_tokyo_path_lod.gd` / `audit` / `_audit_entry`；`_path_lod_contract`为相应反例。仅候选资源，不新增运行时tick。

R129同位像素源就绪 → `tests/tokyo_canonical_review.gd` / `source_state_ready` / `source_ready`核对Raster实际待载/缺块/档位及可见瓦片alpha；`test_tokyo_regional_native.gd` / `_extension_contract`反例。相机首帧仍立即捕获，不能借延迟稳态掩盖切档峰。

R129显式GUARDED_BLOCK_BUILD → `tests/build_tokyo_cells.gd` / `run` → `tests/build_tokyo_guarded_blocks.gd` / `run` / `group_meshes` / `_save`生成低层备用；GUARDED_BLOCK_AUDIT → `test_tokyo_regional_native.gd` / `run` → `build_tokyo_guarded_blocks.gd` / `audit`核验保存资源与未变层。`_guarded_blocks_contract`核验拒绝分支；REGIONAL_REVIEW附加GUARDED_REVIEW → `tokyo_canonical_review.gd` / `run`同时抓新相机首帧/稳态与原预算峰。

R128显式VISIBLE_GROUND_REVIEW → `tests/tokyo_preload_route_probe.gd` / `run` → `tests/tokyo_visible_ground_review.gd` / `run` 同机位关闭/开启/恢复；`experiments/tokyo_tile_ground_candidate.gd` / `resume_fixed`调用`tokyo_tile_coverage.gd` / `visible_flat_covered`，候选没有运行时默认接线。`tests/tokyo_canonical_review.gd` / `ready_at_canvas` / `run`为镜头匹配+稳定绘制就绪门；`test_tokyo_regional_native` / `_extension_contract`反例。`rendering/tokyo_tile_ground_overlay.gd` / `_capture_submission_peak`同一峰新增source/ground纯值元数据，原面数/预算不变。

R127三片联合：`tests/build_tokyo_cells.gd` / `run`显式REGIONAL_CATALOG_BUILD → `tests/build_tokyo_regional_catalog.gd` / `run` / `_west_meshes` / `_load` / `_replace`，REGIONAL_CATALOG_AUDIT → `audit`保存后独立组件数组和coverage核验。`rendering/tokyo_canonical_catalog.gd` / `extension_valid` / `presentation_archive`由`tokyo_canonical_overlay` / `_load_archive`消费；反例`tests/test_tokyo_regional_native.gd` / `_extension_contract`。`tests/tokyo_canonical_review.gd` / `run`显式西片/边界九机位及几何峰硬门；`tests/tokyo_volume_combat_runner.gd` / `_ready`西片C1/near真实战场锚点，原负载/预算不变。

R126边界组件准备：`tests/build_tokyo_cells.gd` / `run`显式BOUNDARY_TRANSFER_BUILD → `tests/build_tokyo_boundary_transfer.gd` / `run` / `target_meshes`；`audit`由BOUNDARY_TRANSFER_AUDIT显式独立调用。`experiments/tokyo_packed_mesh_difference.gd` / `supported` / `subtract` / `conserved`保留打包角点且独立解码审计。反例`tests/test_tokyo_regional_native.gd` / `_difference_contract`，不改正式地图入口。

R125联合街坊迁移：`tests/build_tokyo_cells.gd` / `run`显式REGIONAL_BLOCKS_BUILD → `tests/build_tokyo_owned_region_blocks.gd` / `run` / `disjoint_groups` / `transfer`，复用`build_tokyo_regional_native`的三角差集/独立守恒门；`audit_tokyo_regional_native` / `run`验证完整三片清单及来源/原高；反例在`test_tokyo_regional_native` / `_transfer_contract` / `_toy_cell`，不更改正式规范入口。

R124游戏楼保护：独立`tests/build_tokyo_region_blocks.gd` / `run` → `tests/tokyo_region_gameplay_guard.gd` / `read_source`（调用正式`BuildingRenderer._build_entry_static`）→ `include_points` / `inspect_bounds`，拒绝实际来源及合并轮廓有游戏楼接触的普通低层样片。`write_audit`显式对照R112碰撞/覆盖身份；反例及原生导出入口`tests/test_tokyo_regional_native.gd` / `run` / `_compare_candidate`，不新增运行时tick。

R358全图游戏楼保护数据：`tests/tokyo_region_gameplay_guard.gd` / `protection_data` / `export_protection` 导出全部正式接受轮廓、三角、米高与身份；`preserved_merge_allowed` 仅在来源/碰撞/完整遮罩摘要及逐几何不相交证明匹配时允许相交分片继续；`tests/test_tokyo_regional_native.gd` / `run`检查逐源逐点并提供显式导出入口。不隐藏2D楼，不新增运行时tick。

R123联合来源前置：`tests/build_tokyo_cells.gd` / `run` 的REGIONAL_NATIVE_BUILD → `tests/build_tokyo_regional_native.gd` / `run`；`supported` / `triangle_packets` / `subtract`原生字节差集与`conserved`独立解码多重集门。`tests/test_tokyo_regional_native.gd` / `run`经`bench/bench_runner.gd`新focused/all注册，显式REGIONAL_NATIVE_AUDIT调用`tests/audit_tokyo_regional_native.gd` / `run`。不修改旧单区/规范Overlay身份门。

R122离线新区材质：`tests/build_tokyo_cells.gd` / `run` 的REGION_SURFACE_BUILD → `tests/build_tokyo_region_surface.gd` / `run` / `append_upward`；`tools/build_tokyo_ao.py` / `source_identity` / `build` 独立32来源、index SHA，不改旧规范身份门。固定对拍`tests/tokyo_cells_visual.gd` / `_load_geometry` / `_capture_sample` → `tests/tokyo_region_surface_review.gd` / `run`；反例在`tests/test_tokyo_cells.gd` / `run` 和 `tools/test_tokyo_ao.py` / `test_independent_source_does_not_claim_catalog`。

R121形状修整在`tools/build_tokyo_block_lod.py` / `shape_acceptable` / `choose` / `prepare`，反例`tools/test_tokyo_block_lod.py` / `test_shape_policy_rejects_spikes_not_source`。只对显式独立来源的合并结果生效，不改变原始楼形/高度和默认合同。

R120新区基线：`tests/build_tokyo_cells.gd` / `run` / `valid_sample_output` → `tests/audit_tokyo_region_sample.gd` / `run` / `same_mesh`；固定观察 `tests/tokyo_cells_visual.gd` / `_load_geometry` / `_capture_sample`。`AGL_TOKYO_CELLS_VARIANT=regional_sample`搭配`AGL_TOKYO_REGION_SAMPLE_OUT`仅离线生成独立新目录；`AGL_TOKYO_REGION_SAMPLE_INDEX`仅固定观察，不能代替第三片规范目录/联合流送。

R120街坊B：`tools/build_tokyo_block_lod.py` / `prepare`无owner完整来源参数；`tests/build_tokyo_far_clusters.gd` / `_convert`显式原色对照；`tests/build_tokyo_region_blocks.gd` / `run`受`AGL_TOKYO_REGION_SAMPLE_BLOCKS`控制，校验五档SHA/尺度/成本/标高保存重载。反例在`test_tokyo_block_lod` / `test_standalone_does_not_reinterpret_joined_ownership`与`test_tokyo_far_clusters` / `run`。

R118岸线四网格：`rendering/tokyo_shoreline_layer.gd` `manifest_bytes` / `valid_morph_mesh` / `morph_factor` / `morph_shader_code` / `bind` / `update` / `_show_warm` / `warm_draw` / `close` 拒绝非法身份/UV/预算、联合范围覆盖、共用变宽和三辅助节点；`tests/test_tokyo_shoreline_layer.gd` `checks` / `lifecycle` JSON往返及真实释放；`tests/tokyo_shoreline_runtime_review.gd` `run` 变形后投影，`tests/tokyo_preloaded_ao_review.gd` `shoreline_bytes` 和 `tests/test_tokyo_ao.gd` `run` 独立联合预算；`rendering/tokyo_tile_ground_overlay.gd` `debug_state` 显式总节点明细。

R117原生变宽准备：`experiments/tokyo_shoreline_morph_candidate.gd` `build_mesh` / `orientation_safe` / `factor` / `shader_code` 原生UV位移和变形前后AABB；`tests/build_tokyo_shoreline_morph.gd` `numbers_equal` / `run` 验来源、成本、保存重载并导出真实数组；`tests/test_tokyo_shoreline_morph.gd` `checks` / `fixture` 接 `tests/test_tokyo_tile_ground.gd` `run`；`tests/tokyo_cells_lifecycle_runner.gd` `_ready` 显式SHORELINE_MORPH_BAKE，不接生产bind/update。

R116岸线变宽准备：`tools/build_tokyo_shoreline_morph.py` `load_source` 重验R99来源；`build_plan` / `scoped_shape` 划分完整原岸线组件并守恒成本；`candidate` / `ring_match` / `orientation_safe` / `coverage` 审共同索引、全区间朝向和Float32采样；`fixed_mesh` 保留失败分量三档几何；`tools/test_tokyo_shoreline_morph.py` `MorphTests` 提供分裂/岛洞/世界坐标/中间翻面反例。不接生产着色器或暖绘。

R115地图CPU归属：`rendering/tokyo_tile_ground_overlay.gd` `_record_submission_peak` / `_capture_submission_peak`，外部回调成本归原地图CPU根桶，明细桶不另与根桶累加。

R115绘制时机：`rendering/tokyo_tile_ground_overlay.gd` `_queue_submission_peak` 合并同帧外部源变动与step更新，one-shot `_record_submission_peak` 记录最终层数；`tests/tokyo_draw_geometry_probe.gd` `_verify_report` 在post_draw核对独立pre_draw计数，非GPU计数。

R115地表最终提交统计：`rendering/tokyo_tile_ground_overlay.gd` `_record_submission_peak` 为绘制前历史峰与同帧快照；`_step_geometry` / `_release_tile_ground` / `_deactivate` 控制排队/取消，`debug_state` 独立暴露准备峰。`tests/test_tokyo_tile_ground.gd` `_test_submission_peak`、`tests/test_tokyo_shoreline_layer.gd` `lifecycle` 保留240001反例；`tests/tokyo_draw_geometry_probe.gd` `capture` 独立核对所有绘制边界无低报。

R114绘制边界观察：`tests/tokyo_draw_geometry_probe.gd` `setup` / `capture` / `close` / `summary`；`tests/tokyo_volume_combat_runner.gd` `_ready` / `_bench_finish_now` 只在显式开关时接线；`tests/tokyo_cells_lifecycle_case.gd` `run` 验真实节点及释放终态，原预算门不改。

R114大范围远景街坊候选：`tools/build_tokyo_block_lod.py` `prepare` / `choose`、`tests/build_tokyo_far_clusters.gd` `group_limit` / `_convert` 为far8wide/far12wide来源规划及原生保存；`tools/audit_tokyo_far_clusters.py` `audit` 独立几何/像素检查。`tools/test_tokyo_block_lod.py` `test_wide_far_preserves_anchors_and_scale` 与 `tests/test_tokyo_far_clusters.gd` `run` 拒绝合同漂移，不进入生产流送。

R113道路中心线LOD：`tools/build_tokyo_road_lod.py` `locked_points` / `simplify_locked` 保留源端点与共享路口；`stroke` / `topology` / `accept_shape` / `prepare` 重建原宽描边并检查双向占地、面积/连接/孔洞、原障碍和新候选间冲突；`main` 另存带来源SHA的计划，`tools/test_tokyo_road_lod.py` `RoadLODTests` 反例。尚未接生产或替换原生来源。

R112提交精度：`rendering/tokyo_canonical_overlay.gd` `_step_geometry` 即时失效待提交的超尺度低档；`tests/tokyo_canonical_lifecycle_case.gd` `run` 与 `tests/tokyo_tile_stream_review.gd` `run` 分别验证安全原形期间旧异步目标及真实绘制尺度。

R112最细四点街坊：`tests/build_tokyo_block_catalog.gd` `input_paths` / `valid_plan_rows` / `matched_baseline_rows` / `run` 认证R109当前目录、R106 district16旧层、R111 district24wide候选来源；`tests/test_tokyo_block_catalog.gd` `run` 为路由/矩阵/来源反例。保留中档与全部未选配置，不借旧AO身份。

R111近景概括：`tools/build_tokyo_block_lod.py` `choose` / `prepare` 为独立20/24及wide合同；`tests/build_tokyo_far_clusters.gd` `group_limit` / `_convert` 原生拒绝三角形新组和跨档漂移。`tools/test_tokyo_block_lod.py` `test_wide_near_deterministic_and_four_corners` / `tests/test_tokyo_far_clusters.gd` `run` 为结构与原高反例，`tools/audit_tokyo_far_clusters.py` `audit` 按各版本真实最少轮廓点验证，不扩旧版合同。

R110交接诊断：`rendering/tokyo_canonical_overlay.gd` `_restore_original` 最多32条显式值快照；`tests/tokyo_canonical_cut_probe.gd` `run` / `handoffs` 组件/实际几何额度与离线完整分割比较。`experiments/tokyo_cut_reuse.gd` `corresponding_cut` / `_corresponding` / `incremental_parents` / `_incremental_entry` 为纯值转换与成本，不改变资源身份或生产选档；`tests/test_tokyo_cut_reuse.gd` `run` 与 `tests/tokyo_cells_lifecycle_runner.gd` `_ready` 为focused反例入口。

R109旧中档来源：`tests/build_tokyo_block_catalog.gd` `middle_source_chain` 与 `run` 认证R44→原R42/R34→R108候选的同源关系；不把当前R44轻概括误当未概括原形。测试 `tests/test_tokyo_block_catalog.gd` `run`。

R109实际中档路由：`tests/build_tokyo_block_catalog.gd` `input_paths` / `valid_plan_rows` / `run` 认证R107当前低层与R108 mid6来源；`tests/test_tokyo_block_catalog.gd` `run` 拒绝模式/档位/父区/未选版本漂移。`tests/tokyo_tile_stream_review.gd` `run` 真实新LOD4绘制与尺度门；`tests/tokyo_district_finish_review.gd` `run` 原序追加中档宽镜头、最细和返回。

R108中档概括候选：`tests/export_tokyo_far_costs.gd` `run` → `tools/build_tokyo_block_lod.py` `prepare` / `main` → `tests/build_tokyo_far_clusters.gd` `run` / `selected_levels` / `maximum_scale` / `group_limit`；mid4/mid6不扩散到其它档。反例 `tools/test_tokyo_block_lod.py` `test_middle_contract_preserves_anchors_and_rejects_other_scales` 与 `tests/test_tokyo_far_clusters.gd` `run`；静态机位 `tests/tokyo_far_cluster_review.gd` `run`，独立几何/像素 `tools/audit_tokyo_far_clusters.py` `audit`。

R107强街坊规范接线：`tests/build_tokyo_block_catalog.gd` `input_paths` / `matched_baseline_rows` / `valid_plan_rows` 与 `tests/test_tokyo_block_catalog.gd` `run` 约束district16、R103目录及R92旧低层来源一致；`tests/tokyo_tile_stream_review.gd` `run` 实际LOD5候选绘制计数，`tests/tokyo_district_finish_review.gd` `run` 保留原顺序并追加宽视角。AO使用既有实际几何导出/重烘链。

R106低楼强概括：`tools/build_tokyo_block_lod.py` `contract` / `prepare` 仅LOD5的district12/district16；`tests/build_tokyo_far_clusters.gd` `group_limit`、`tools/audit_tokyo_far_clusters.py` `audit` 独立合同门；`tools/test_tokyo_block_lod.py` `test_stronger_district_fills_small_gap_not_height_or_road` / `tests/test_tokyo_far_clusters.gd` `run` 反例。沿用实际保存重载与静态近景对拍，未进入默认资源。

R105索引压缩：`tools/pack_tokyo_ao_bits.py` `pack5` / `unpack5` / `build`，`experiments/tokyo_height_bits.gd` `storage_width` / SHADER_CODE；正式AO `experiments/tokyo_baked_ao.gd` `row_bytes` / `make_shader` / `bind_ao` / `bind_preloaded`。GPU全场与边界审查 `tests/tokyo_height_bits_visual.gd` `run`，反例 `tests/test_tokyo_ao.gd` `run` / `tools/test_tokyo_ao_bits.py`；预算与取消见 `tests/tokyo_preloaded_ao_review.gd` `cancelled_loading`、`tools/audit_tokyo_ao_preload.py` `audit`。

R104组合审查：`tests/tokyo_district_finish_review.gd` `run` 首机位同源平坦采样后冻结色值，七机位A/B/恢复；`low_mask_code` 保留几何与LOD discard并以独立黑白双绘导出可见范围，`replacement` / `restore` 临时材质所有权。入口 `tests/tokyo_preload_route_probe.gd` `run`，反例 `tests/test_tokyo_tile_ground.gd` `run`。

R103 AO预算审查：`tests/tokyo_preloaded_ao_review.gd` `shoreline_bytes` 与 `tools/audit_tokyo_ao_preload.py` `shoreline_bytes` 纳入已实装三档岸线的准确预约，拒绝非法/缺失/低估；原96MiB门不变。`tests/test_tokyo_ao.gd` `run` / `tools/test_tokyo_ao.py` `test_joint_shoreline_reservation` 验反例。

R103远景目录迁移：`tests/build_tokyo_block_catalog.gd` `input_paths` / `matched_baseline_rows` / `run` / `valid_plan_rows`，显式FAR6只改LOD1/2北岸低层，完整源矩阵对照R78当前版本，所有近景/标高/固定层保持；反例 `tests/test_tokyo_block_catalog.gd` `run`。连续审查 `tests/tokyo_tile_stream_review.gd` `run` / `projected_check` 覆盖全区域参考和独立源色分层。

R102远档街坊概括：`tools/build_tokyo_block_lod.py` `prepare` / `contract`，`tests/build_tokyo_far_clusters.gd` `group_limit` 仅接far4/far6远档；独立 `tools/audit_tokyo_far_clusters.py` `audit` 核对实际组、来源与尺度。反例 `tools/test_tokyo_block_lod.py` `test_far_district_scale_height_and_structural_contract` / `tests/test_tokyo_far_clusters.gd` `run`。

R101街区边界：`tests/tokyo_district_boundary_review.gd` `run`，同实例分层与源图对照；`tests/tokyo_preload_route_probe.gd` `run` 显式入口，`tests/test_tokyo_tile_ground.gd` `run` 编译门。

R101远景试色：`experiments/tokyo_low_tone_candidate.gd` `weight` / `shader_code`；同一边界review复用原几何试两版并恢复，近景权重归零。

R99实际路线：`tests/tokyo_shoreline_runtime_review.gd` `cancelled_loading` / `run`，显式SHORELINE_REVIEW；原预加载探针记录prepared_shoreline及shoreline_released_after_menu，不用静态候选的截图证明实际接线。

R99岸线：`rendering/tokyo_shoreline_layer.gd` `levels` / `shader_code` / `bind` / `update` / `begin_warm` / `warm_draw` / `close`；既有地表 `rendering/tokyo_tile_ground_overlay.gd` `setup` / `_setup_geometry` / `_step_geometry` / `debug_state`，预加载身份 `rendering/tokyo_volume_preload.gd` `start` / `take` / `_begin`，三档暖绘 `_after_draw` / `_process`。反例与制作见 `tests/test_tokyo_shoreline_layer.gd` `checks` / `lifecycle`、`tests/build_tokyo_shoreline_lod.gd` `run`。

R98自然岸线：`tools/build_tokyo_shoreline.py` `collect` / `build` 从原缓存裁切并去重，不描裁切框；`experiments/tokyo_shoreline_candidate.gd` `build` 静态原生面。`tests/tokyo_shoreline_review.gd` `run` 保存重载、源图/两宽度/mask/恢复，入口 `tests/tokyo_preload_route_probe.gd` `run` 的显式SHORELINE_DATA，反例 `tests/test_tokyo_tile_ground.gd` `run` / `tools/test_tokyo_shoreline.py` `ShoreTests`。

按功能主题索引到 `文件:行号 符号`，直接读取对应行段即可获取上下文。不确定功能属于哪个代码域时先读
[Reference Index](_INDEX.md)；已知文件名时先用 [Script Index](script-index.md) 确认职责。

## 快速定位

R97水面校色见 `tests/tokyo_water_palette_review.gd` `run`；`experiments/tokyo_ground_palette_candidate.gd` `shader_code` 的ground_palette_only_class默认-1保留原行为，显式类别10只改水面；来源采样仍走 `tests/tokyo_ground_palette_review.gd` `sample_color` / `source_flat`，不新增地表贴图或生产tick。

R96显式全区域地表由 `rendering/tokyo_tile_ground_overlay.gd` `_step_geometry` 在原绑定阶段选归档bounds，FULL_REGION默认关；`tests/tokyo_ground_boundary_review.gd` `run` 核对自动绑定与手工同范围像素一致，不增加tick。

R96地表边界候选：`experiments/tokyo_tile_ground_candidate.gd` `valid_bounds` / `bind` 保留旧窗口默认，仅显式实例使用有限正面积coverage_bounds；`tests/tokyo_ground_boundary_review.gd` `run` 在真实Loading路线逐项比较原生/局部/归档覆盖与恢复，输出独立源图和边界投影角点。`tests/tokyo_preload_route_probe.gd` `run` 显式GROUND_BOUNDARY_REVIEW接线；`tests/test_tokyo_tile_ground.gd` `run` 覆盖非法范围和默认保持。

R94慢帧明细：`tests/tokyo_render_clock.gd` `retain_slowest` 只保留真实耗时最高32条，晚到长帧替换最小项；`tests/tokyo_render_trace.gd` `begin_frame` / `summary` 接入并明确策略/候选/省略数；`tests/test_perf_frame_trace.gd` `_test_render_partition` 覆盖千帧精确top32与满容量长帧，不改真实时钟硬门。

R93 AO审计边界：`tools/audit_tokyo_ao_preload.py` `screen_mask` 将矩形裁到屏幕后仅接受正面积交集，避免完全在左/上屏外的负切片回绕；`tools/test_tokyo_ao.py` `AOTests` 四方向屏外、部分交集与混合反例。

R93密集街坊集成：`tests/build_tokyo_block_catalog.gd` `input_paths` / `valid_plan_rows` / `run` 仅显式district8最细模式，核对制作计划SHA与合同，继承R85完整规范目录、覆盖及组件，沿原切线替换普通低层并重新导出AO。拒绝混档/混profile，旧blocks路线不变。

R92密集低楼：`tools/build_tokyo_block_lod.py` `contract` / `prepare` 新增仅5.0最细尺度的district6/district8；`tests/build_tokyo_far_clusters.gd` `group_limit` 独立精确合同，`tools/audit_tokyo_far_clusters.py` `audit` 核对计划身份与尺度并独立重建道路障碍。仅静态原生候选，旧blocks与规范目录不变。

R91全分辨率AO压缩：`tests/build_tokyo_ao_bc4.gd:5 run` 编辑器离线生成原生BC4数据及逐档误差/字节报告，保留原高度资产；`experiments/tokyo_baked_ao.gd:34 bc4_mip_bytes` / `experiments/tokyo_baked_ao.gd:44 row_bytes` 独立计算完整mip与三份预算，显式读取验证RGTC能力及上传回读格式，旧R8与shader不变。不在导出游戏中压缩，不把有损压缩说成像素无损。

R90阻塞容量预检：`tests/tokyo_cut_capacity_probe.gd:8 run` 保存真实树、组件与投影；`tests/tokyo_cut_capacity_probe.gd:73 _state` 核对请求/驻留不变；`tests/tokyo_cut_capacity_probe.gd:78 _query` 复用生产前沿并交叉核对16槽；`tests/tokyo_cut_capacity_probe.gd:105 _pair_frontiers` 交叉比较两段交接的真实物理并集。显式测试开关才由预热审查的失败分支调用，24/32仅元数据诊断，不修改运行时容量或宣称全组合无解。

R84中近街坊制作：`tests/build_tokyo_far_clusters.gd:89 selected_levels` 默认远档、显式LOD3，`tests/export_tokyo_far_costs.gd:6 run` 导出正式三档成本；`tools/build_tokyo_block_lod.py:180 main` 显式成本路径和档尺度校验；`tests/tokyo_far_cluster_review.gd:11 run` 为LOD3增加中近实际机位。静态新包不等于规范连续LOD接线。

投影瓦片真实接线：`rendering/projected_raster_tile.gd:16 configure` / `rendering/projected_raster_tile.gd:40 clipped_plane`；`survivor/raster_basemap_renderer.gd:856 _new_tile_node` / `survivor/raster_basemap_renderer.gd:860 _prepare_tile_node` / `survivor/raster_basemap_renderer.gd:871 projected_geometry_bytes`；`_tile_candidates` 原SAT按实际投影行矩形求可见。`experiments/tokyo_raster_projection.gd:62 valid_for`拒绝错误元数据或世界范围。`rendering/tokyo_tile_ground_overlay.gd:152 _release_projection_reserve` / `rendering/tokyo_tile_ground_overlay.gd:158 _exit_tree` 在关闭前归还源几何固定额度，地表`bind`剪原行与计真实面数。`tests/tokyo_tile_stream_review.gd:192 projected_check` 以独立多边形相交及实际2D源像素核对借用；默认source_projection为空仍走原Sprite。

墨卡托地理配准候选：`experiments/tokyo_raster_projection.gd:6 metadata` / `experiments/tokyo_raster_projection.gd:10 world_y` / `experiments/tokyo_raster_projection.gd:23 raw_y` / `experiments/tokyo_raster_projection.gd:36 mesh`；实际静态路线 `tests/tokyo_georeference_review.gd:9 run` / `tests/tokyo_georeference_review.gd:68 snapshot`。旧仿射与地理分行网格共享纹理、UV和原生楼栋，只诊断不推广连续默认。

原生地表分类调色：`experiments/tokyo_ground_palette_candidate.gd:8 shader_code` / `experiments/tokyo_ground_palette_candidate.gd:46 vectors` / `experiments/tokyo_ground_palette_candidate.gd:53 semantic_colors`；静态实际路线 `tests/tokyo_ground_palette_review.gd:9 run` / `tests/tokyo_ground_palette_review.gd:129 source_only` / `tests/tokyo_ground_palette_review.gd:169 sample_color` / `tests/tokyo_ground_palette_review.gd:201 source_flat` / `tests/tokyo_ground_palette_review.gd:213 mask_inside`。无HUD同源诊断视口、内部蒙版中位数及平坦源底色、四种固定色板跨尺度与原始恢复，不作为连续性能证明。

地表程序缓存：`experiments/tokyo_tile_ground_candidate.gd:175 cached_shader` 按完整源码复用Shader；连续地图跨租约保留程序而非Texture/材质，区别帧脚本成本和新程序首次绘制尖峰。

东京连续地表候选：`rendering/tokyo_tile_ground_overlay.gd:44 _sync_tile_source` / `rendering/tokyo_tile_ground_overlay.gd:49 _release_tile_ground` / `rendering/tokyo_tile_ground_overlay.gd:75 _step_geometry` / `rendering/tokyo_tile_ground_overlay.gd:136 _deactivate` / `rendering/tokyo_tile_ground_overlay.gd:173 debug_state`；`experiments/tokyo_tile_ground_candidate.gd:126 resume_fixed` / `experiments/tokyo_tile_ground_candidate.gd:183 suspend_fixed`；`tests/tokyo_tile_stream_review.gd:9 run`。Raster的presentation_changing在源新增/退役/过渡/启停/退出前同步还原借用者；原地图tick复用平面和固定材质，不新增平行流送。

东京固定层纹理接替：`experiments/tokyo_tile_coverage.gd:5 covered` / `experiments/tokyo_tile_coverage.gd:28 flat_covered`；`tokyo_tile_ground_candidate` 的 `bind` 显式replace_fixed，`close`恢复材质/可见性；R71实际路线用AGL_TOKYO_TILE_FIXED_REPLACE记录真实提交面数，不改规划器原数字。

北岸低楼试色：`experiments/tokyo_low_light_candidate.gd:7 shader_code`；`tests/tokyo_tile_ground_review.gd` 的 `run` 以 AGL_TOKYO_GROUND_LAYERS 显式隔离三层、试两种明暗并恢复，不改生产默认。

东京地表同色桥接：`experiments/tokyo_canvas_color.gd:19 finish`、`experiments/tokyo_canvas_color.gd:27 input_for`；实际材质因素/灰阶/无影同色对照 `tests/tokyo_ground_color_probe.gd:22 run`；固定层原生只读导出 `tests/export_tokyo_fixed_mesh.gd:5 run`。仅静态候选，不改原瓦片或原几何。

东京独立组件接线：`rendering/tokyo_mesh_component.gd:10 valid`、`rendering/tokyo_mesh_component.gd:21 stream_identity`；清单 `rendering/tokyo_component_manifest.gd:6 read`、`rendering/tokyo_component_manifest.gd:43 valid_row`、`rendering/tokyo_component_manifest.gd:67 complete_coverage`；流送适配 `rendering/tokyo_component_stream.gd:18 configure`、`rendering/tokyo_component_stream.gd:39 request`、`rendering/tokyo_component_stream.gd:56 _paths`、`rendering/tokyo_component_stream.gd:169 resource`、`rendering/tokyo_component_stream.gd:187 close`、`rendering/tokyo_component_stream.gd:198 summary`。制作 `tests/build_tokyo_mesh_components.gd:7 run`、`tests/build_tokyo_mesh_components.gd:65 _save`；反例/终态 `tests/test_tokyo_components.gd:11 run`、`tests/test_tokyo_components.gd:75 lifecycle`、`tests/test_tokyo_components.gd:128 _check`；真实像素对拍 `tests/tokyo_component_review.gd:8 run`。显式AGL_TOKYO_COMPONENTS，原规范overlay/Session使用同一Stream与原coverage身份。

跨 LOD 原生内容共享：`tests/build_tokyo_cross_lod_components.gd:9 mesh_key`、`tests/build_tokyo_cross_lod_components.gd:16 run`、`tests/build_tokyo_cross_lod_components.gd:82 _collect`；完整组合反例与真实卸载：`tests/test_tokyo_cross_lod_components.gd:11 run`、`tests/test_tokyo_cross_lod_components.gd:57 lifecycle`、`tests/test_tokyo_cross_lod_components.gd:95 _check`。原始逻辑页身份不变，物理层逐项数组一致后才共享。

东京原生双组合共享：`rendering/tokyo_shared_page.gd:11 valid`、`rendering/tokyo_shared_page.gd:64 stream_identity`、`rendering/tokyo_shared_page.gd:69 variant_meshes`；离线制作 `tests/build_tokyo_shared_pages.gd:7 run`、`tests/build_tokyo_shared_pages.gd:31 _pair`、`tests/build_tokyo_shared_pages.gd:99 same_mesh`；反例 `tests/test_tokyo_shared_page.gd:9 run`、`tests/test_tokyo_shared_page.gd:70 _check`；真实加载/退出 `tests/tokyo_shared_stream_case.gd:8 run`、`tests/tokyo_shared_stream_case.gd:99 _inspect`。此为独立候选，尚无运行时逻辑页适配或地图提交接线。

东京低层原形屋顶离线候选：`tests/tokyo_low_roof_candidate.gd:10 run`、`tests/tokyo_low_roof_candidate.gd:22 _export`、`tests/tokyo_low_roof_candidate.gd:45 _bake`；复用地表精确并集计划器与原生打包属性校验，不接默认地图。

地面三维正式接入：`experiments/volume_ground_catalog.gd:12 keys`、`experiments/volume_ground_catalog.gd:22 key_for`、`experiments/volume_ground_catalog.gd:46 build`；真实状态适配与终态恢复：`experiments/volume_ground_presenter.gd:15 refresh_members`、`experiments/volume_ground_presenter.gd:36 restore`、`experiments/volume_ground_presenter.gd:54 sync`、`experiments/volume_ground_presenter.gd:114 detail_mode_for`、`experiments/volume_ground_presenter.gd:118 body_color_for`；弱点合成前景：`rendering/ground_volume_foreground.gd:8 sync`、`rendering/ground_volume_foreground.gd:21 _draw`。验收入口：`volume_ground` / `volume_ground_runtime`，地面生命周期由默认 gauntlet 调用。

本文件按“飞行与战斗 → AI / 编队 → 地面 / 海军 → 生存成长与内容 → 无线电 → 主场景 / 视觉 / UI → 资源 / 场景 → ROE / 演出 / 专项批次”排列。
先搜索二级标题，再搜索符号名；不要从头通读本文件。常用命令：

```powershell
rg -n "^## |^### " docs/reference/code-index.md
rg -n "目标功能名|ClassName|symbol_name" docs/reference/code-index.md
```

> ✅ **2026-08-21 全量校验通过**。当前文档与锚点数量以
> `python tools/verify_doc_anchors.py` 的实时输出为准；禁止在索引里冻结会迅速过期的总数。
> （2026-04-22 拆子模块重构遗留的 218 处失效锚点已批量修复。）
>
> **改代码后同步本文件，并跑校验器**：
> ```
> python tools/verify_doc_anchors.py                     # 全量
> python tools/verify_doc_anchors.py --section 无线电通讯  # 只查你动的那段
> ```
> 退出码 1 = 有锚点对不上。写锚点时**带上符号名**（`aircraft/aircraft_physics.gd:351 update_speed`），
> 校验器才能做强校验；只写行号只能校验"没越界"—— 历史上正是这类弱锚点掩盖了指错文件的错误。
>
> **重构后代码去哪了**（2026-04-22 拆子模块，私有方法搬进模块时**去掉了前导下划线**）：
>
> - **物理**（bank/heading/speed/altitude/stall/fuel/energy）→ `scripts/aircraft/aircraft_physics.gd`
> - **武器**（gun/ciws/rocket/missile/weapon_mode）→ `scripts/aircraft/aircraft_weapons.gd`
> - **战斗追踪**（update_combat / 对地攻击 / 包线判定）→ `scripts/aircraft/aircraft_combat_tracking.gd`
> - **热诱弹**（`AircraftFlares.update` / `.release`）→ `scripts/aircraft/aircraft_flares.gd`
> - **编队** → `scripts/aircraft/aircraft_formation.gd`
> - **BFM 战术 / 目标选择 / 导弹规避 / 编队协同** → `scripts/ai/` 下 4 个子模块
> - **刷怪与建敌**（`_pick_enemy_type` / `_create_enemy` / `_update_spawner`）→ `scripts/survivor/survivor_spawner.gd`
> - **地形绘制**（`_init_noise` / `_draw_grid`）→ `scripts/terrain_renderer.gd`
>
> ⚠ **飞行员耐力（pilot stamina）当前无代码实现**（全仓库 0 处引用），但
> **概念保留** —— 计划在将来的拟真战役模式重新启用。`i18n/skills.csv` 的
> `UPGRADE_PILOT_STAMINA_*` 三语文本**刻意保留，不要当死键清掉**。

---

## 飞行物理

| 功能 | 位置 |
|------|------|
| 物理主循环 | `aircraft.gd:1186` _physics_process |
| 目标航向计算 | `aircraft/aircraft_physics.gd:80` update_target_heading |
| 实飞 / 预测共享目标航向状态 | `aircraft/aircraft_physics.gd` `_target_heading_state` |
| 滚转角更新（G 限制由 tactical_aggression 插值调节）| `aircraft/aircraft_physics.gd` `update_bank` |
| 实飞 / 预测共享滚转公式（小角参考滤波、解析 LOS 前馈、连续 P 死区、方向锁、坡度帽、滚转权限、回正、EMA 积分） | `aircraft/aircraft_physics.gd` `_filter_heading_reference` / `compute_target_bank` / `_resolve_turn_lock_state` / `_bank_limit_rad` / `_bank_roll_rate_rad_s` / `_apply_bank_recovery` / `_integrate_bank_state`；回归 `tests/test_turn_physics.gd`（bench `turn_physics`） |
| 右键急刹拖拽转向（捕获鼠标 / 相对位移、12px 死区 / 110px 满舵、持续 G 坡度、失速禁用、实飞预测同源、机场面板接管释放、速度/射程摇杆、真实机炮射界） | `survivor/survivor_mode.gd` `_begin_hard_brake` / `_update_hard_brake_steer` / `_set_hard_brake` / `_open_evolution_offer` → `aircraft/aircraft_physics.gd` `brake_steer_input_from_dx` / `_brake_steer_target_bank` / `_speed_target_ms`；表现 `survivor/brake_steering_overlay.gd` → `survivor/survivor_hud.gd` `begin_brake_steering` / `set_brake_steering_stall_locked` / `set_brake_steering_flight_data`，飞机前方复用 `aircraft_renderer.gd` `should_show_gun_reference` / `draw_gun_cone`；右键 `SquadCommandController.cancel` 清旧 combat/commanded target，但机炮/炮艇自动扫描继续；spec `systems/brake-steering` |
| 航向更新 ω=g×tan(bank)/speed | `aircraft/aircraft_physics.gd:329` update_heading |
| 实飞 / 预测共享航向积分 | `aircraft/aircraft_physics.gd` `_integrate_heading_rad` |
| 速度更新（含高G阻力、高度耦合） | `aircraft/aircraft_physics.gd:351` update_speed |
| 实飞 / 预测共享速度公式（目标约束 + 积分） | `aircraft/aircraft_physics.gd` `_speed_target_ms` / `_integrate_speed_ms` |
| 高度更新 | `aircraft/aircraft_physics.gd:448` update_altitude |
| 实飞 / 预测共享高度积分 | `aircraft/aircraft_physics.gd` `_integrate_altitude_state` |
| AI 巡逻 / 作战偏好 / 近距匹配高度策略 | `ai/ai_altitude_policy.gd` `set_patrol` / `use_combat_preference` / `match_target` |
| 失速检查 | `aircraft/aircraft_physics.gd:521` update_stall |
| G力计算 | `aircraft/aircraft_physics.gd:543` update_g_load |
| 飞行员耐力 | **代码已移除**（保留概念：将来拟真战役模式再启用；`i18n` 的 `UPGRADE_PILOT_STAMINA_*` 三语文本刻意保留） |
| 位移应用 | `aircraft/aircraft_physics.gd:576` apply_movement |
| 最大 bank 角（物理瞬时上限） | `aircraft/aircraft_physics.gd:585` max_bank_angle |
| 有效最大G（**buff 注入点**，SEAM-001） | `aircraft/aircraft_physics.gd:632` effective_max_g；瞬时结构 G = `:643` effective_max_g_instant |
| 临时光环基线与加减速修改器（实飞/预测同源） | `aircraft/aircraft_physics.gd` `base_stall_kmh` / `base_roll_rate` / `base_accel` / `base_max_speed_kmh` / `base_cruise_kmh` / `effective_accel_mult` / `effective_decel_mult` |
| 角点速度 V=V_stall×1.2×√G | `aircraft/aircraft_physics.gd:725` corner_speed_kmh |
| 失速速度 V_stall×√G | `aircraft/aircraft_physics.gd:824` stall_speed |
| 高空最大速度衰减 | `aircraft/aircraft_physics.gd:833` max_speed_at_altitude |
| 空气密度比 σ=e^(-alt/8500) | `aircraft/aircraft_physics.gd:855` air_density_ratio |
| 旋翼机速度向量/机头解耦运动 | `aircraft/aircraft_physics.gd:1745 update_rotorcraft` |
| 高度档位切换（生存模式） | `aircraft.gd:1821` set_target_tier |

## 主动特殊机动（R 五选一）

| 功能 | 位置 |
|------|------|
| 共享状态/命中资格 | `aircraft.gd:2494 is_active_special_maneuver` / `aircraft.gd:2498 can_accept_new_hit` |
| 位移滚转激活与安全侧评分 | `aircraft.gd:2592 _try_start_displacement_roll` |
| 垂直越过激活与高度边界 | `aircraft.gd:2617 _try_start_vertical_break` |
| 动作推进与 10Hz AI 自动触发 | `aircraft.gd:2713 _update_active_special_maneuver` |
| 垂直越过俯仰投影（纵轴收缩/尾焰锚点） | `aircraft_renderer.gd:1140 draw_muzzle_flash` / `aircraft_renderer.gd:1155 draw_afterburner_glow` / `aircraft_renderer.gd:1263 draw_aircraft_icon` |
| 五向 R 固定优先级入口 | `aircraft.gd:2735 try_manual_maneuver` |
| 小队共享冷却账本 | `squad.gd:40 active_maneuver_cooldown_s` |
| 玩家 HUD 唯一技能/冷却只读状态 | `aircraft.gd:2511 equipped_r_maneuver_id` / `aircraft.gd:2525 r_maneuver_cooldown_total` / `aircraft.gd:2540 r_maneuver_cooldown_remaining` |
| 常规高度物理让位门 | `aircraft/aircraft_physics.gd:448 update_altitude` |
| 弹体/光束命中资格、source 清洗、归因与目标类型分派 | `weapon_hit_resolver.gd:11 can_accept_unit_hit` / `weapon_hit_resolver.gd:17 resolve_unit_hit`；调用方 `bullet_manager.gd` / `missile_manager.gd` / `equipment/laser_equipment.gd` / `equipment/railgun_equipment.gd` |
| 技能数据/五向互斥 | `survivor/survivor_data.gd:1737 displacement_roll` / `survivor/survivor_data.gd:1731 vertical_break` |
| 技能授予 | `survivor/survivor_skill_effects.gd:270 displacement_roll` / `survivor/survivor_skill_effects.gd:273 vertical_break` |
| 聚焦回归 | `tests/test_skills_720.gd:816 _test_t5_mechanisms`（轨迹、边界、命中、共享冷却、AI 自动） |

## 高度动作、爬升反制与能量循环

| 功能 | 位置 |
|------|------|
| CLIMB/DIVE 统一状态、Q 换档一次性闸门、进入沿与 4s 反制窗 | `aircraft.gd` `AltitudeAction` / `altitude_action_command` / `command_altitude_preference` / `_set_altitude_action` / `_tick_climb_counter_window` / `climb_counter_window_active`；`aircraft_physics.gd` `update_altitude`；玩家编队镜像见 `aircraft_formation.gd` `_update_altitude` |
| 普通高度物理与失速排除 | `aircraft/aircraft_physics.gd` `update_altitude`；目标方向 + 实际垂直速度 30m/s 门，失速保持 NONE |
| 编队僚机自身高度动作 | `aircraft/aircraft_formation.gd` `_update_altitude` |
| 严格 GUN_TAILED 火控解与旧射向打空 | `aircraft/aircraft_weapons.gd` `is_gun_tailed_by` / `_refresh_committed_gun_aim` → `aircraft.gd` `report_gun_tailed` |
| 迫近导弹 60m/s、3.5s 共用门与确定性失导 | `ai/missile_evasion.gd` `is_imminent_evasion_threat` → `aircraft.gd` `try_climb_counter_missile` → `missile.gd` `disrupt_by_climb_break` |
| DIVE 每机机炮回复与 2×超储 | `aircraft/aircraft_weapons.gd` `update_altitude_cycle_ammo`；编队早退由 `update_passive_gunship` 结算 |
| CLIMB 共享加力池 +0.2/s（只读当前操控机） | `survivor/survivor_mode.gd` → `survivor/afterburner_charge.gd` `update` |
| 详细 ALT 动作词与 GUN_TAILED 状态 | `aircraft_renderer.gd` `draw_data_label_minimal` / `draw_data_label` / `status_label_entries`；详细档固定英文 CLIMB/DIVE，战略档省略且无动作气流 |
| 聚焦回归 | `tests/test_skills_720.gd` `_test_altitude_actions_and_cycle`；全表/F4 审计 `tests/test_skill_audit.gd` |

## 能量管理

| 功能 | 位置 |
|------|------|
| 能量管理总入口 | `aircraft/aircraft_physics.gd:1055` update_energy_management |
| 加力燃烧器开关 | `aircraft/aircraft_physics.gd:1021` set_afterburner |
| 燃油消耗 | `aircraft/aircraft_physics.gd:1035` update_fuel |

## 战斗追踪（Aircraft 内置）

| 功能 | 位置 |
|------|------|
| 战斗追踪主逻辑（空对空） | `aircraft/aircraft_combat_tracking.gd:60` update_combat |
| 对地攻击（Apache 专用 `_strafe_state`，不经 planner） | `aircraft/aircraft_combat_tracking.gd:273` update_combat_ground_attack |
| 对面攻击 pass 循环（planner 路径：玩家指挥机+迁移 AI+舰船，SETUP/RUN/EGRESS + 姿态 STANDOFF/ASSAULT，spec surface-attack-pass） | `ai/tactical/bfm_intent.gd` ground_strafe + `_strafe_pass_phase`（Aircraft 状态位） |
| 慢速空目标（直升机）交战 pass（spec slow-air-target-pass；与地面 pass 同一台相位机，只换包络） | `ai/tactical/situation.gd` `tgt_is_slow_air` + `SLOW_AIR_SPEED_RATIO` / `ai/tactical/tactical_planner.gd` 优先级 4.5 分流 / `ai/tactical/bfm_intent.gd` `SLOW_AIR_*` 常量 |
| 碰撞航路拦截点（解交会时刻，SETUP 段引导；区别于按弹速算的机炮提前点） | `ai/tactical/bfm_intent.gd` `_intercept_point`（对照 `_gun_lead_point`） |
| 导弹相位坡度软化的适用门（锁定满但仍在发射锥外 → 不降转弯权限，破"锁上了转不动"死锁） | `aircraft.gd` `_get_missile_phase` + `_target_within_launch_cone` |
| planner 统一时钟源（无头 sim 可拨快；intent hysteresis / EXTEND 倒计时都读它） | `ai/tactical/situation.gd` `now` + `sim_time_override`（`aircraft.gd` 写 `_bfm_extend_until` 也走它） |
| 设定战斗目标 | `aircraft.gd:2184` set_combat_target |
| 清除战斗目标 | `aircraft.gd:2203` clear_combat_target |
| CombatParams 获取 | `aircraft.gd:2264` _combat_params |
| 自动扫描机炮目标 | `aircraft/aircraft_weapons.gd` auto_gun_scan（普通机炮守交战纪律；玩家全队炮艇优先射程内 `commanded_target` / MountTarget，失格或超距时各自扫描最近 Aircraft/GroundUnit） |
| 编队 / LOD 提前返回路径的高度循环与炮艇 tick | `aircraft/aircraft_weapons.gd` update_passive_gunship + `aircraft.gd` LOD0/1/2 formation 分支 |

## 武器系统 — 机炮

| 功能 | 位置 |
|------|------|
| 机炮射击更新（梭射状态机，spec: gun-burst-fire） | `scripts/aircraft/aircraft_weapons.gd` update_gun |
| 单发出弹（散布/云雾/多管/音效/弹药） | `scripts/aircraft/aircraft_weapons.gd` _fire_gun_round |
| 梭射常量（DUTY/MIN_INTRA/帧补上限） | `scripts/aircraft/aircraft_weapons.gd` GUN_BURST_* |
| 梭计数与目标锁存状态 | `aircraft.gd` _gun_burst_rounds_left / _auto_gun_target_id / _gun_burst_target_id（_fire_cooldown 旁） |
| 梭目标逐 tick 提前点刷新 | `scripts/aircraft/aircraft_weapons.gd` _gun_target_from_id / _refresh_committed_gun_aim |
| GUN_TAILED 正式火控解 / CLIMB 旧射向冻结 | `scripts/aircraft/aircraft_weapons.gd` is_gun_tailed_by / _refresh_committed_gun_aim + `aircraft.gd` report_gun_tailed |
| 炮艇射向炮口 / CIWS 独立 5° 正面锥 | `scripts/aircraft/aircraft_weapons.gd` _fire_gun_round / AIRCRAFT_CIWS_CONE_HALF_ANGLE_DEG / update_ciws |
| 敌机一次机会一梭安全门（末发后停火 3s；全敌方 Aircraft） | `aircraft.gd` _ai_gun_burst_allowed / _ai_gun_pause_timer + `scripts/aircraft/aircraft_weapons.gd` update_gun |
| 每梭弹数参数 | `scripts/gun_params.gd` burst_count |
| 玩家全队机炮承伤降低 40%（单发 cap 后、护甲前） | `playable_aircraft.gd` bullet_damage_taken_mult → `survivor/survivor_playable_setup.gd` apply → `aircraft.gd` take_bullet_damage；`tests/test_gun_burst.gd` run |
| [GUN_BURST] 梭起始诊断（射向/最近敌机距离快照，追"对空放枪"） | `scripts/aircraft/aircraft_weapons.gd` _log_burst_start |
| [GUN_SCAN] 被动扫描锁存上升沿诊断 | `scripts/aircraft/aircraft_weapons.gd` auto_gun_scan 尾部 |
| 机炮射程（像素） | `aircraft.gd:2293` _gun_range_px |
| 子弹生成 | `bullet_manager.gd:214` spawn_bullet |
| 子弹物理+命中检测 | `bullet_manager.gd` _physics_process |
| 曳光弹/火箭/炸弹/Flak/漂浮雷绘制 | `rendering/bullet_presenter.gd` `draw`；状态宿主 `bullet_manager.gd` `_draw` |
| 真命中火星（闪避不触发；每目标 110ms CD；12 组封顶；两次批量绘制） | `bullet_manager.gd` `_emit_hit_spark` `_update_hit_sparks` → `rendering/bullet_presenter.gd` `_draw_hit_sparks` |

## 武器系统 — 火箭弹（无制导副武器，例：F-86 FFAR）

| 功能 | 位置 |
|------|------|
| RocketParams 定义（齐射数/最终散布/冷却/射程 + 直飞/展开距离）| `scripts/rocket_params.gd` `straight_flight_distance` / `spread_transition_distance` |
| 火箭弹发射主逻辑（敌我共享扫描 + 左右逐发队列）| `scripts/aircraft/aircraft_weapons.gd` `update_rocket` / `rocket_burst_plan` |
| 单发火箭出膛（当帧机体航向 + 左右挂点 + 前向速度全量继承） | `scripts/aircraft/aircraft_weapons.gd` `_launch_rocket` |
| 火箭弹生成与 180m 直飞→320m smoothstep 展开 | `scripts/bullet_manager.gd` `spawn_rocket` / `rocket_spread_progress` / `apply_rocket_spread_step` |
| 火箭弹命中 / 伤害无衰减 / 更大判定半径 | `bullet_manager.gd` _physics_process 分支 `is_rocket` |
| 橙红尾迹 + 白色弹头绘制 | `rendering/bullet_presenter.gd` `_draw_bullet_streams` |
| 火箭弹字段（AircraftParams） | `aircraft_params.gd` `rocket: RocketParams` |
| F-86 火箭资源 | `resources/rocket_ffar.tres` |
| 敌方火箭弹 tier 资源表（V1~V8，等级成长唯一杠杆）| `survivor/survivor_data.gd:3728` ENEMY_ROCKET_TIERS → `resources/weapons/enemy_rocket_v1.tres` ~ `enemy_rocket_v8.tres` |
| └ tier 注入点（`_create_enemy` 内按等级 duplicate 挂载）| `survivor/survivor_spawner.gd:4316` ENEMY_ROCKET_TIERS |
| └ 齐射数实际取 `burst_count_max`（`burst_count_min` 目前未被读取）| `scripts/rocket_params.gd` burst_count_max / `aircraft/aircraft_weapons.gd:814` update_rocket |
| 延迟散开专项回归 / 真实渲染样张 | `scripts/tests/test_rocket_trajectory.gd`（bench `rocket_trajectory`）/ `scripts/tests/rocket_trajectory_visual_qa_runner.gd`（Visual bench `rocket_trajectory_visual`） |

## AI 原型预设（CombatParams）

| 原型 | 文件 | 特征 |
|------|------|------|
| Gladiator（斗士） | `resources/gladiator_combat.tres` | intercept_range_mult=1.6 / 低 six_oclock_offset / 高 bank_aggression / 低 maneuver_speed |
| Lancer（骑士/打带跑） | `resources/lancer_combat.tres` | intercept_range_mult=3.5 / 高 approach_speed / 高 closing_rate_threshold（闭合不够就放弃）|
| F-86 参数 | `resources/enemy_f86.tres` | 亚音速 + 高G + Gladiator combat + FFAR + 6x.50cal |
| F-86 专用机炮 | `resources/f86_gun.tres` | 低伤害低射速（避免秒杀玩家）|
| F-86 生存模式 AI | `scripts/survivor/survivor_mode.gd` EnemyType.F86 分支 | 高 aggression / 低 self_preservation / 长 engage_duration |
| A-7 参数 | `resources/enemy_a7.tres` | 亚音速 + 低G + Lancer combat + Zuni + M61 火神炮（高弹量）|
| A-7 专用机炮 | `resources/a7_gun.tres` | M61A1 20mm（400发，中射速）|
| A-7 火箭弹 | `resources/a7_rocket.tres` | Zuni 5"（高伤害 14，低弹量 16）|
| Q-5 参数 | `resources/enemy_q5.tres` | 微超音速 + 中G + Lancer combat + 57mm + 23mm 双炮 |
| Q-5 专用机炮 | `resources/q5_gun.tres` | 23-2K 23mm x2（200发）|
| Q-5 火箭弹 | `resources/q5_rocket.tres` | 57mm 火箭弹（低伤害 8，高弹量 32，大散布）|

## 武器系统 — 导弹

| 功能 | 位置 |
|------|------|
| 武器模式切换（MISSILE/GUN） | `aircraft/aircraft_weapons.gd:950` update_weapon_mode |
| 战术偏好武器模式（带机炮回退） | `aircraft/aircraft_weapons.gd:1003` _update_weapon_mode_tactical |
| 导弹打不中但机炮能打（有滞回） | `aircraft/aircraft_combat_tracking.gd:578` missile_cannot_hit_but_gun_can |
| 机炮冲锋：进入承诺判定 | `aircraft/aircraft_combat_tracking.gd:611` should_commit_gun_pass |
| 机炮冲锋：冲锋完成判定 | `aircraft/aircraft_combat_tracking.gd:619` is_gun_pass_finished |
| 航点/编队机会火控（不写 combat_target，20Hz） | `aircraft.gd` 三档 formation early-return → `aircraft/aircraft_weapons.gd` update_formation_passive_missile（spec waypoint-fire-control） |
| 导弹发射主逻辑 | `aircraft/aircraft_weapons.gd:1004` update_missile |
| 导弹阻断日志（被锁/RNG/能量等原因） | `aircraft.gd:3035` _log_msl_block |
| 齐射空手日志（auto_fire 实际值 + 各过滤踢除计数） | `aircraft.gd:3055` _log_salvo_skip |
| 单枚/齐射共享发射提交与一轮 cooldown/reload | `aircraft/aircraft_weapons.gd:1295 _emit_missile` / `aircraft/aircraft_weapons.gd:1327 _finish_main_missile_cycle`；包装入口 `aircraft/aircraft_weapons.gd:1286 _fire_missile_at` |
| 多目标齐射（有效锁数截断 + 正常冷却） | `aircraft/aircraft_weapons.gd:1338 _fire_multi_lock_salvo` · `aircraft/aircraft_weapons.gd` `_salvo_fire_count` |
| 飞机导弹发射纪律（档案 skill/jitter、稳定窗口、共享两轮前置点、预测包络） | `combat_params.gd` `missile_skill` / `missile_skill_jitter`；`aircraft/aircraft_weapons.gd` `_missile_skill` / `_has_stable_launch_window` / `_has_lead_intercept_solution` / `missile_lead_point`；`ai/tactical/bfm_intent.gd` `_missile_engage_pos`（未出弹 lead / 出弹后 crank）；`missile_manager.gd` `_compute_lead_launch_heading`；`aircraft/aircraft_combat_tracking.gd` `envelope_pass_at` |
| 最优目标选择（评分） | `aircraft.gd:3119` _select_best_missile_target |
| 射程包线检查 | `aircraft/aircraft_combat_tracking.gd:632` is_in_missile_envelope |
| 导弹阶段判定（接近/照射/保持） | `aircraft.gd:2327` _get_missile_phase |
| 是否应该用机炮 | `aircraft.gd:2354` _should_use_gun |
| Crank 状态查询 | `aircraft.gd:2365` is_cranking |
| 导弹射程（像素） | `aircraft.gd:2299` _missile_range_px |
| 有效导弹射程=min(导弹,雷达)像素 | `aircraft.gd:2309` _effective_missile_range_px |
| 有效射程（像素） | `aircraft.gd:2321` _effective_range_px |
| 导弹飞行物理+PN制导 | `missile.gd:281` _physics_process |
| 导弹低空制导衰减 | `missile.gd:913 _guidance_degradation` |
| 导弹生成 | `missile_manager.gd:128` spawn_missile |
| 飞机导弹前置出筒（相对机头 ±60°；地面/舰载/VLS 隔离） | `missile_manager.gd` `_compute_lead_launch_heading`；`MissileParams.launch_toward_target` 保留 HOBS 直指目标例外 |
| 导弹命中检测 + 连锁弹头直穿 | `missile_manager.gd:440` _physics_process |
| 连锁弹头逐弹去重 + 命中后直飞 | `missile.gd` continue_after_penetration / already_penetrated |
| 连锁弹头发射快照/去重回归 | `tests/test_weapon_behavior.gd` _test_chain_warhead_snapshot |
| 在飞导弹查询 | `missile_manager.gd:264` has_active_missile_at |
| 近炸引信 AOE 生成 | `missile_manager.gd:690` _spawn_aoe |
| AOE 区域更新+伤害 | `missile_manager.gd:716` _update_aoe_zones |
| AOE 红圈渲染 | `rendering/explosion_presenter.gd` `_draw_aoe_zones`；状态宿主 `missile_manager.gd` `_draw` |
| 仅大型飞机使用的四条结构解体路线与全场爆点面/棱合批真实渲染回归 | `missile_manager.gd` `spawn_airframe_wave` `_spawn_hit_flash` `_update_hit_flashes` → `rendering/explosion_presenter.gd` `hit_flash_draw_packet` `hit_flash_cube_packet` / `aircraft_destruction.gd` `destruction_size_class` `_large_breakup_route` `_emit_airframe_wave` / `tests/hit_flash_visual_qa_runner.gd`；Visual bench `hit_flash_visual` |
| 弹跳目标查找 | `missile_manager.gd:877 _find_bounce_target` |

## 热诱弹/反制

| 功能 | 位置 |
|------|------|
| 热诱弹系统更新（含失误判定） | `aircraft/aircraft_flares.gd:58` update |
| 释放热诱弹（target_missile 可选，针对性释放）| `aircraft/aircraft_flares.gd:245` release |
| 干扰成功率计算 | `aircraft/aircraft_flares.gd:520` calc_jam_chance |
| 粒子更新 | `aircraft/aircraft_flares.gd:553` _update_particles |
| 玩家/直属僚机/TEAM_ALLY 统一投焰门（完整来袭资格 + TTI≤1.0s / 200m；加力窗口暂缓；自卫/护卫复用） | `aircraft/aircraft_flares.gd` `player_flare_should_trigger` |
| 敌机小概率不投 + 1.25s 可命中 break + 有效 AI 80%→95% | `aircraft/aircraft_flares.gd` `enemy_release_fail_chance_for_configured` `enemy_flare_break_chance` / `missile.gd` `begin_enemy_flare_break` `update_enemy_flare_break` `enemy_flare_break_action` |
| 固定十枚 0.90s 六波双侧抛射 + 同帧计数 | `aircraft/aircraft_flares.gd` `_queue_visual_burst` `_spawn_wave` / `aircraft.gd` `flare_visual_burst_emitted` |
| 热诱弹聚焦、旧即时/前版/当前生存战力对照与正式 Visual 样张 | `tests/test_flare_timing.gd`（bench `flare`）/ `tests/test_flare_impact_ab.gd`（显式 bench `flare_impact_ab`，不进 `all`）/ `tests/flare_visual_qa_runner.gd`（bench `flare_visual`） |
| 失误概率 / 对头减免（FlareParams 字段） | `flare_params.gd:19-22` fail_chance / head_on_fail_reduction |
| 规避态（底层 evasion_mode：导弹来袭 S 型 + 降高度；AI 自保 + 加力模式共用的底座）| `aircraft.gd:2783` _update_evasion |
| 规避态开关（调用方：AI 自保 enter_evade / 玩家 E 键经 AfterburnerCharge.toggle） | `aircraft.gd:2387` set_evasion_mode |
| 加力模式唯一状态机（WeakRef 小队快照；有能量即开/耗尽自动关/再按关闭；世界飞行指令取消后立即充能且不写速度，spec afterburner-mode） | `survivor/afterburner_charge.gd` `Phase` / `activate` / `deactivate` / `cancel_for_manual_command` / `update`；`survivor/survivor_mode.gd` `_cancel_afterburner_for_manual_control` |
| 加力窗口唯一查询/生命周期边界（全队强 buff、肉鸽技能、TORP/WMN、签名技能、HUD 共用） | `aircraft.gd` `afterburner_window_active` / `is_afterburner_mode_active` / `set_afterburner_mode_active` |
| 加力肉鸽联动消费（超频/蓄势/弹仓/雾隐/供弹） | `aircraft/aircraft_physics.gd` `effective_max_speed_kmh` / `effective_cruise_speed_kmh` / `effective_accel_mult`；`aircraft.gd` `cd_rate` / `_update_evasion`；`aircraft/aircraft_weapons.gd` `update_gun` |
| 加力专属载荷统一门（TORP / WMN，普通规避与物理 AB 不触发） | `aircraft/aircraft_weapons.gd` `afterburner_payload_enabled` / `update_torpedo` / `update_loyal_wingman` |
| 加力机炮 100% 闪避（绕 dodge cap 短路） | `aircraft.gd:3341` effective_dodge |
| 加力滚转甩导弹（90% → is_flare_jammed） | `missile_manager.gd:561` AB_MISSILE_DODGE |
| 加力速度地板 + 加速 ×3 | `aircraft/aircraft_physics.gd:755` AB_WINDOW_ACCEL_MULT |
| 玩家 HUD HP/加力/装填统一绿黄红进度与 0.5s 闪烁；FLR 开始 CD 且加力可用时 E 键反色提示最多 5s | `survivor/player_instrument_panel.gd` `progress_color` / `_draw_progress_bar` / `_draw_afterburner` / `_draw_weapon_row` / `_sync_afterburner_flare_hint` / `afterburner_flare_hint_on` |
| 加力充能条 + 按钮三态刷新 | `survivor/survivor_hud.gd` _update_afterburner_ui |
| 眼镜蛇机动模块 | `cobra_maneuver.gd` CobraManeuver（挂载到 Aircraft 子节点） |
| 眼镜蛇机动激活 | `cobra_maneuver.gd` activate |
| 战术机动查询（通用） | `aircraft.gd` get_maneuver |
| AI 控制器查询 | `aircraft.gd` _get_ai_controller |
| R 统一机动入口（眼镜蛇/J-Turn/胆大妄为） | `aircraft.gd:2735` try_manual_maneuver；`survivor/survivor_mode.gd:3644` KEY_R |
| 当前操控机手动 / AI 僚机自动分流 | `aircraft.gd:1121` is_manual_maneuver_controlled；`:1951` _update_cobra_skill；`:2013` _update_evasion_herbst_skill；`:2040` _update_manual_dodge_skill |
| 三种 R 机动卡池互斥 | `survivor/survivor_data.gd` cobra_skill / evasion_herbst / manual_dodge 的 `excludes` |
| 手动大机动不压制自动 flare | `aircraft/aircraft_flares.gd:160` is_manual_maneuver_controlled 门 |
| 眼镜蛇后方判定（AI） | `ai_controller.gd` _is_missile_from_rear |
| 锁定免疫检查 | `aircraft.gd:3883` is_lock_immune |

## 伤害与击毁

| 功能 | 位置 |
|------|------|
| 受伤（导弹） | `aircraft.gd:3241` take_damage |
| 受伤（机炮，含闪避；返回 bool 表示是否实际结算） | `aircraft.gd:3310` take_bullet_damage |
| 内部伤害应用 | `aircraft.gd:3410` _apply_damage |
| └ 敌方护卫反应（被护送对象挨打 → 护卫同拍脱队扑攻击者） | `aircraft.gd:3577` _alert_escort_guards（`TS_DIRECTIVE` + `clear_formation` + `enter_engage_state`）|
| └ 护卫名单字段 | `aircraft.gd:366` escort_guards（登记方 `survivor/survivor_spawner.gd:2554` _spawn_flee_escort）|
| 地面撞击检查 | `aircraft.gd:3610` _check_ground_crash |
| 击毁流程与受击分区 | `aircraft.gd` `take_damage_at` `take_bullet_damage` `_start_destroy` → `aircraft_destruction.gd` `record_hit` `hit_zone_for_local` `start` |
| 所有伤害统一保留模型并旋转下坠；失控阶段不透明，终点爆炸帧仍显示机体，之后继续运动 0.85s 并连续淡出才释放；部位与局部随机改变下坠/减速/偏航/侧翻；普通机/无人机终点仅一个方框，大型有人机才有结构波 | `aircraft_destruction.gd` `destruction_size_class` `_configure_crash_motion` `update` `crash_visual_progress` `_update_crash_visual_state` `_update_post_breakup_linger` `_emit_terminal_breakup` `_large_breakup_route` `_stop_trail`；`aircraft_renderer.gd` `draw_aircraft_icon_destroyed` `draw_aircraft_icon`；权威 spec `docs/specs/systems/aircraft-destruction-presentation.md` |
| 命中结算共享边界 | `weapon_hit_resolver.gd` `can_accept_unit_hit` / `resolve_unit_hit`；调用方 `bullet_manager.gd` `_apply_projectile_damage` `_physics_process` `_explode_airburst_shell`、`missile_manager.gd` `_physics_process` `_update_aoe_zones` `_apply_aoe_damage`、`equipment/railgun_equipment.gd` `_apply_hitscan_damage`、`equipment/laser_equipment.gd` `_apply_laser_effect` |
| 小型导弹被 CIWS/激光/电磁炮拦截的 HP 与终态 | `missile.gd:577 take_intercept_damage` / `missile.gd:582 destroy_from_intercept`；调用方 `bullet_manager.gd` / `equipment/laser_equipment.gd` / `equipment/railgun_equipment.gd` |
| 坠毁终态真实释放、体型/部位/随机与缩放/透明度回归 | `tests/lifecycle_gauntlet_runner.gd` `_test_all_damage_kinds_enter_aircraft_crash` `_test_unified_aircraft_breakup` `_test_hit_location_crash_response` `_test_large_aircraft_structural_breakup`；Visual 时间片 `tests/hit_flash_visual_qa_runner.gd` `_ready`；bench `lifecycle_gauntlet` / `hit_flash_visual` |
| 基类伤害 | `combat_unit.gd:296` take_damage |

## 雷达系统

| 功能 | 位置 |
|------|------|
| 雷达锥判定（飞机） | `aircraft.gd:3677` is_in_radar_cone |
| 雷达锥判定（地面单位） | `ground_unit.gd:317` is_in_radar_cone |
| 雷达锥判定（SAM，360°） | `sam_unit.gd:116` is_in_radar_cone |
| 全局锁定计算循环 | `main.gd:198` _update_radar_locks |
| Aircraft 主雷达 shooter 能力门（主 AAM/railgun/对空 laser；副槽独立） | `aircraft_params.gd` `has_lock_capable_weapon` → `main.gd` / `survivor/survivor_mode.gd` `_update_radar_locks`；hover 主锥在 `aircraft.gd` `_draw_impl` 共用 |
| 生存模式雷达 ROE 候选预分桶 | `survivor/survivor_mode.gd` `_rebuild_radar_target_buckets` → `_run_radar_slice`（经 `_update_radar_locks` 窗口分片）；HOSTILE 只遍历非 HOSTILE，PLAYER/ALLY 只遍历 HOSTILE，最终仍走 `is_hostile_to` 防御校验 |
| 敌机传感器隐形 / 反隐技能 | `aircraft_params.gd` `sensor_stealth_enabled` → `survivor/sensor_stealth_controller.gd` `observe` / `finish_radar_tick` / `_counter_stealth_extended_contact` / `_revealed_by_counter_stealth` / `_held_by_ghost_buster` / `release_player_sensor_refs_batch` / `_target_is_in_batch`（5s 失联、1000px 近距揭露、反隐 120% 扩距、被锁/交战现形、同 tick 合批；Variant 边界净化玩家 combat/commanded 与 AI current 的已释放引用）→ `aircraft.gd` `set_sensor_contact_hidden` / `set_counter_stealth_revealed` / `set_combat_target` / `sync_stealth_trail_emission`；同向渐变命令幂等，透明度走 CanvasItem 调制，完全隐形非任务目标停止常规 redraw，但 AI/物理/机动/武器及通用 LOD 频率不受隐身状态影响；光学 cloak 周期覆盖见 `ace_squad.gd` `_cloak_update`，击杀队级 +10 HP 见 `skill_hooks.gd` `dispatch_on_kill` / `sync_ghost_buster_team_hp_bonus`；其余观察者门、导演、导弹、Radar/TGT 与尾迹沿用原链；跨帧抗体见 `tests/lifecycle_gauntlet_runner.gd` `_test_sensor_release_with_freed_target_caches` |
| 低空锁定速率衰减 | `main.gd:300` _lock_rate_for_target（静态方法） |
| 玩家可见被锁状态过滤 | `combat_unit.gd` `tracks_player_lock_state` / `accumulate_player_lock_state` → `main.gd` `_update_radar_locks` / `survivor/survivor_mode.gd` `_finish_radar_window`；AI↔AI 的 `radar_targets` 保留，但不写锁框/玩家反应状态 |
| 雷达数据链共享 | `radar_station.gd:35` _update_datalink |

## AI 控制器

| 功能 | 位置 |
|------|------|
| AI 主循环 | `ai_controller.gd:578` _physics_process |
| └ 写入 aircraft.tactical_aggression（effective_skill×aggression）| `ai_controller.gd:200` |
| 有效技能（压力衰减） | `ai_controller.gd:1113` _effective_skill |
| 压力更新 | `pilot_personality.gd:131` update_stress |
| 漂移/判断失误 | `pilot_personality.gd:188` update_drift |
| Simple AI（UAV用） | `ai_controller.gd:1431` _process_simple |
| Simple / drone / kamikaze / 机炮共用追击点几何 | `ai/pursuit_geometry.gd` `closing_time_lead_point` / `projectile_lead_point`；消费方 `ai_controller.gd` `_process_simple` / `_process_drone_engage` 与 `ai/tactical/bfm_intent.gd` `_gun_lead_point` |
| └ 护驾长机失效检测（Sentinel 坠毁）| `ai_controller.gd:384-390` |
| └ Sentinel 持续返航 + 移动轨道点配速（orbit_squad_leader）| `ai_controller.gd` `_process_simple` |
| └ 护驾战斗脱离（tether check）| `ai_controller.gd:436-451` |
| Simple AI 交战 | `ai_controller.gd:2016` _try_engage_simple |
| └ 护驾过滤（目标必须在 tether 内）| `ai_controller.gd:530-536` |
| orbit_squad_leader 导出变量 | `ai_controller.gd:59` |
| 绕长机飞行常量 | `ai_controller.gd` `ORBIT_INNERMOST` / `ORBIT_SPACING` / `ORBIT_MAX_ANGULAR_SPEED_RAD` / `ORBIT_CATCHUP_SPEED_BONUS_KMH` / `ORBIT_TETHER_RADIUS` |
| 巡逻逻辑 | `ai_controller.gd:2072` _process_patrol |
| 编队跟随逻辑 | `ai/squad_coordination.gd:28` process_squad_follow |
| └ 协同攻击触发（反应延迟） | `ai_controller.gd:639` 块内 |
| 掩护扫描（队友后方） | `ai/squad_coordination.gd:421` scan_leader_rear |
| BVR 狙击模式（F-47 专用） | `ai_controller.gd` `bvr_only` 标志 → `_process_engage` 距离检查；机动与武器纪律由 TacticalPlanner 输出 |
| TacticalPlanner 滞回重置 | `aircraft.gd` `reset_tactical_plan_state`（字段所有者）；`ai_controller.gd` `reset_tactical_plan`（目标切换/特殊机动等调用入口） |
| 被追 → Herbst 触发 | `ai_controller.gd` `_process_engage` 内独立于 bvr_only 的后半球检测 + `get_herbst().activate()`；模块自身再检查次数/flare 门 |
| 协同齐射广播 | `ai_controller.gd` broadcast_salvo + process_salvo |
| 赫尔贝特轮机动 | `herbst_maneuver.gd` HerbstManeuver（DECEL→TURN 180°→ACCEL，15s 冷却；默认可重复，profile 可限次数与 flare 分层） |
| 光学隐形（F-47） | `aircraft.gd` is_cloaked / _cloak_alpha → _draw() 淡出 + is_lock_immune() + missile.gd 丢失制导 |
| └ 隐形索敌过滤（各通路） | `ai_controller.gd` _current_target 失效判定 / _try_engage_simple / _try_engage_in_tether_range / 神风扫描；`ai/squad_coordination.gd` scan_squad_nearby_enemy + scan_leader_rear；`ai/target_selection.gd` disengage BOSS 再交战；`aircraft/aircraft_weapons.gd` update_secondary_radar；`aa_gun_unit.gd` 扫描 |
| **交战速度治理**（绕圈死结） | `ai/tactical/engagement_speed_governor.gd` EngagementSpeedGovernor — `R = V²/(g√(n²−1))` 反解速度上限，地板=角点速度；接线在 `aircraft.gd` `TacticalPlanner.plan()` 之后一行；`Situation.max_g` 为其新增字段（经 `effective_max_g()` 注入） |
| **属性感知狗斗画像** | `ai/tactical/situation.gd` `_recompute`（双方转率/角点半径/滚转/减速 → BALANCED/ENERGY/TIGHT）→ `ai/tactical/tactical_planner.gd` `_apply_dogfight_energy_management` + 5b/5b.2/侧翼/僚机角色消费 → `ai/tactical/bfm_intent.gd` `_apply_squad_lateral_offset`（spec engagement-discipline §C） |
| **玩家高位自然高度带**（PREFER_CLIMB 8400m 中心、错相慢漂移、转弯掉高；敌机不变） | `ai/tactical/situation.gd` `is_player_squad` / `altitude_variation_phase` → `ai/tactical/bfm_intent.gd` `_apply_player_altitude_preference` / `player_high_hold_altitude_m`（spec command-wheel §2.5.2） |
| └ 治理回归测试 | `tests/test_speed_governor.gd`（`--bench=speed_governor`，14 断言：7 公式 + 7 裸物理步进 sim 对照） |
| └ 狗斗成长沙盒 | `tests/test_dogfight_growth.gd`（`--bench=dogfight_growth`：六档机动 build × 当前/属性感知候选 planner × 三种开局；机炮解算窗/尾位/能量/盘旋半径 A-B） |
| └ **减速迟滞**（王牌执行失误） | `ai/tactical/engagement_speed_governor.gd` `apply_with_lag()` — 每次新进入治理区掷一次骰，25% 概率延迟 0.6~1.2s 才压速 → 冲过头。状态 `_ace_decel_lag_latched` / `_ace_decel_lag_timer` 在 `aircraft.gd`（spec wraith-squadron §2.4） |
| **BOSS 登场→接战统一契约** | `events/boss_encounter_event.gd` — spawn 后从 `BossRegistry.banner_metadata_for()` 注入身份并播放 `<boss_id>_arrival`；先播系统入侵横幅，Wraith / CSG / Goose 退场后切主体，Black Star 因根机仍在 30km 隐藏而不切固定锚点特写；IRON SERPENT 在 PRE_STAGE 硬暂停下继续沿铁路驶入，横幅退场后镜头跟随第 7 节编组中部，420px 边界 inset 配合 0.26 广角保证首尾与 180 屏幕 px 安全区完整入画，完整入图才接战；镜头回玩家后立即 ENGAGED；缺序列或被 UI 转场覆盖均 fail-open 接战并亮血条；ENGAGED 后猎手持续追玩家（spec ui-transition §2.0 / boss-hunter-doctrine / armored-train §3.4） |
| **Black Star / Hyper-A 双根分裂 BOSS** | `survivor/hyper_a_boss.gd`：双根 `1→2→4→8` 节点账本、G1 首次隐藏下降 / 40–50s 循环再入 / 越过 15km 时解除主副目标、雷达锁存、旧追击点与雷达余辉 / 7–10s 高空等待（HUD 保留 30km 高度倒数）/ 活动序列暂停其它倒数并至少错峰 12s / AOE、四代独立饱和齐射标记与武器静默、G0 全向锁定 / 离轴齐射、G1 普通前向发射、共享物理减速对线后冲刺、终点 `900m / 110° / 45` 急刹扇形冲击波、火箭 / 6s SLOW 散热、分裂与胜利门；`aircraft/aircraft_weapons.gd` 消费 Hyper-A 独立齐射 / G0 全向豁免两层许可；`survivor/hyper_a_threat_overlay.gd` 同源画危险圆 / 由近到远生长的攻击线 / 线满后急刹预警扇区与扩散波 / 冲击；资源 `enemy_hyper_a_g0..g3.tres` + `hyper_a_missile.tres`；spec `bosses/hypersonic-splitter` |
| └ Black Star 正式接入 / 状态栏 / Debug | `survivor/boss_registry.gd` `BLACK_STAR` → `events/boss_encounter_event.gd` `_spawn_hyper_a/_on_hyper_a_root_descent_started/_set_arrival_player_visual_hidden` → `survivor/survivor_spawner.gd` `_spawn_boss`；双根真实下降信号分别驱动 `BLACK STAR-01/02` 无线电，第一根倒数以 `Aircraft.META_PRESENTATION_FORCE_HIDDEN_VISUAL` 隐藏玩家绘制；树 HUD 走 `boss_encounter.gd get_hud_entries` → `survivor_hud.gd _format_custom_boss_entries`；九场景在 `boss_debug_select.gd BOSS_LIST` |
| └ 沙漠十四节超尺度武装列车 / 236×84px 重装车体 / 双转向架贴轨 / 铁路广角进场 / 全车可锁定 + 尾节递进打断脱离 / 侧舷锁定后电磁炮 AOE / 逃脱失败 | `resources/maps/desert_railway_preview.aglmap` `railways/iron_serpent_main`（`source=desert_basemap_primary_rail_corridor`，玩家可读金色双线）为路线 SSOT → `survivor/armored_train_unit.gd` `configure_route/arm_segments/begin_arrival_ingress/finish_arrival_ingress/is_arrival_fully_inside/_sample_route_pose/_sample_segment_pose/_refresh_segment_poses/_update_movement/on_segment_broken/railgun_side_for_position/_update_railgun/_begin_railgun_lock/_begin_railgun_charge/_fire_railgun_snapshot` → `survivor/armored_train_segment.gd` `set_train_pose/set_targetable/set_damageable/can_accept_new_hit/take_damage/_start_destroy/_detach_from_train/_draw_theme` → `survivor/armored_train_boss.gd` `train_route/spawn/engage/has_failed/get_hud_entries` → `events/boss_encounter_event.gd` `_spawn_custom/_enter_engaged/_update` → `survivor/survivor_mode.gd` `on_boss_failure`；进场时序在 `resources/presentation/sequences.json` `armored_train_arrival`（0.26 广角跟随第 7 节）；固定池与 Debug 在 `survivor/boss_registry.gd` / `survivor/boss_debug_select.gd`；focused `tests/test_armored_train.gd` / `tests/test_presentation.gd`，Visual `tests/boss_debug_select_visual_qa_runner.gd` |
| └ The Crucible 18 队 73 架接力混战 / Hound 雇佣兵背叛终局 / 玩家附近交战 / FFA 锁定 / 共享 Ace 中队条 | `survivor/the_crucible_boss.gd` `PROFILE_ORDER/CINEMATIC_SQUAD_COUNT/ACTIVE_SQUAD_CAP/OPENING_MELEE_DURATION_S/ENTRY_DISTANCE_PX/ENTRY_DISTANCE_MAX_PX/ENTRY_JOIN_RADIUS_PX/PLAYER_HUNTERS_PER_SQUAD/BACKSTAB_MAX_RANGE_PX/entry_relative_bearing_deg_for/entry_position_for/_entry_spawn_position_for/is_opening_melee_active/aggro_score/rear_attack_opportunity_score/visible_battle_score/spawn/engage/update/_spawn_next_squad/_activate_squad/_retarget_all/_assign_player_hunters/_try_acquire_player/_acquire_target/_is_pressuring_player/_force_reentry_if_strayed/_complete_reentry/_active_squad_count/_target_candidates/_live_engaged_members/get_hud_entries` → `ai_controller.gd` `directive_suspends_combat/prepare_parent_directive_control` → `aircraft/control_intent.gd` `SOURCE_DIRECTIVE` → `survivor/ace_squad_profiles.gd` `hound/boss_grade/crucible_only` → `survivor/ace_squad_theme_controller.gd` `_apply_hound_betrayal` → `survivor/ace_battle_bar.gd` `set_info`；首发为 2NDWAVE / GIMMICK / GOOFIGHTERS，MARATHON 延后到第 6 批；首发三队以 -110°/0°/+110° 为首选方位，在玩家 3600–6000px 外按当前镜头外推/侧搜，前 8s 只互选 Ace，之后每支活跃队仅 1 名稳定猎手压玩家，其余成员继续 FFA，并在 2600px 内从后半球机会主义抢攻正在缠斗玩家的敌方 Ace；每轮每目标最多 1 名背刺认领者；后续槽均铺在排除六点钟 ±45° 的 270° 环带；初次入场进到 3000px 后才启用 3600px 脱战三层环返场；focused `tests/test_the_crucible.gd` + 真实 SceneTree `tests/desert_theater_smoke_runner.gd`；全员 Headless 诊断审计 73 架状态、退场、目标、弹丸与返场 |
| └ 独立陆地航母 / 边界内向心进场 / 嵌入式停机 / 舰载机起飞 | `survivor/land_carrier_unit.gd` `configure_patrol/spawn_parked_aircraft/launch_parked_aircraft/arm_mounts/_draw_ground_icon` → `survivor/land_carrier_boss.gd` `spawn/engage/update/get_hud_entries` → `survivor/boss_registry.gd` / `survivor/boss_debug_select.gd`；甲板驻机由 `aircraft.gd` 在 `parent_carrier` meta 存续期间隐藏世界数据牌，起飞摘 meta 后恢复；focused `tests/test_land_carrier.gd` |
| **沙漠 RTS 地面战线** | `survivor/desert_front_controller.gd` `setup/on_zone_captured/_update_production/_update_helicopter_waves/_update_artillery_fire`；正式入口 `survivor/survivor_map_select.gd`；攻克沿用 `survivor/survivor_mode.gd` `_on_zone_mission_completed`，不再有沙漠专属支线时间改写；全战区气氛 `survivor/zone_atmosphere_combat.gd` `DECISIVE_MAP_IDS` |
| └ Black Star 回归与压力 | `tests/test_hyper_a_boss.gd`（bench `hyper_a`，107 项）；`survivor_mode.gd` bench `boss_hyper_a_arrival` / `boss_hyper_a` / `boss_hyper_a_dash` / `boss_hyper_a_brake_wave` / `boss_hyper_a_g0_weapons` / `boss_hyper_a_g1_entry` / `boss_hyper_a_g1_weapons` / `boss_hyper_a_lifecycle` / `boss_hyper_a_stress`；正式横幅→玩家附近下降 / 状态栏 / 无线电 Visual、G0 后向全向实弹、G1 侧向拒射 / 普通前向实弹、爬升消失时目标 / 锁存解除、高空状态栏 / 等待 / 俯冲分段与多分裂体排队错峰、冲锋对线、延迟扇区 / 急刹波实伤 Visual、16 G3 + Sentinel/5 终态由 Visual、日志与 `generation_counts` / `get_hud_entries` 输出 |
| **BOSS 通关强化分层** | `meta/career_archive.gd` `build_boss_history()` 输出完整 `defeat_counts` → `events/boss_encounter_event.gd` 在 spawn 前调用 `BossEncounter.configure_progression()`；Wraith 通过 `wraith_progression_loadout.gd` 独立选择恐惧配置，其它 BOSS 保留现有分层（spec boss-clear-progression） |
| └ Wraith 首败后 YF-23 可选支援 | `survivor/f47_ace_squad.gd` `engage/_spawn_progression_support/support_spawn_positions/set_player_ref` + `resources/enemy_yf23.tres`；两架沿玩家→Wraith 轴在队形后方 1800px 潜伏（离玩家至少 5000px），启用传感器隐形但无永久免锁，接触建立后正常可锁定；保持 4–6km BVR，不进演出/血条/胜利判定 |
| └ LADON 护航编成 | `survivor/carrier_strike_group.gd` `escort_counts_for_progression/_build_escort_plan`；初见 0CG+2DDG+6FFG，首败后 2CG+2DDG+8FFG；`_pick_water_placement` 按本局实际 offsets 校验 |
| └ Mother Goose 型号门 | `survivor/mother_goose_boss.gd` spawn 注入 → `mother_goose_uav_swarm.gd` `variant_weights_for_progression/_roll_variant`；初见仅 MQ-109/110，首败后恢复 111/112 与 railgun 保底 |
| └ Mother Goose VLS 远距空爆 | `survivor/mother_goose_controller.gd` `vls_can_launch_at_distance/_enqueue_vls_salvo`（3000m 内停火）→ `resources/goose_vls_missile.tres`（8000m/800m/1.5s）→ `missile.gd` `distance_traveled_px` → `missile_manager.gd` `distance_airburst_ready/_detonate_distance_airburst/_spawn_aoe/_apply_aoe_damage` |
| └ MQ-111 累计反导 + 玩家同款过热 | `resources/uav_mg_laser.tres` 开启 `intercepts_missiles_directly` 并对齐 X-02 热量四参数，复用 `equipment/laser_equipment.gd` `update/_apply_laser_effect`：持续刷新减速并扣 `Missile.intercept_hp`，归零令弹体失效；回归 `tests/test_boss_progression.gd`（bench `boss_progression`） |
| └ MQ-X 绕圈根治 + 三路武器 + F-22 级隐形 | `survivor/mother_goose_boss.gd` `configure_mqx_ai`统一注入 joust 550/2600px 攻击跑 → `resources/enemy_uav_mqx.tres` 聚合 `mqx_pulse_cannon.tres` / `uav_mqx_missile.tres` / `mqx_intercept_laser.tres` 与 `sensor_stealth_enabled`；点射枪口闪光由 `aircraft/aircraft_weapons.gd` `_fire_gun_round` 的真实出弹短窗驱动，FFA 也吃敌机一梭门；回归 `tests/test_joust.gd` `_test_mqx_attack_run_and_loadout` + `tests/test_gun_burst.gd`（bench `joust` / `gun_burst`） |
| └ 猎手指令 verb | `events/ai_directive.gd` `PURSUE_UNIT` + `pursue(target, refresh_interval)`；执行分支 `ai_controller.gd` `_directive_pursue_unit_step`（0.5s 重取、**无抵达态**、目标失效自动释放） |
| └ 玩家引用重定向契约 | `survivor/boss_encounter.gd` `set_player_ref()` 基类虚方法；三子类各自覆写（`ace_squad.gd` / `carrier_strike_group.gd` → 转发 Poltergeist / `mother_goose_boss.gd` → 转发 controller → `ai/swarm/swarm_director.gd`）。SEAM-019 同类，猎手模型下是急性病 |
| └ 母舰巡逻环跟随玩家 | `survivor/mother_goose_boss.gd` `_patrol_center()` / `_update_patrol_follow()` — 环心=玩家实时位置，2s 重算、位移 <800px 不重下航点 |
| └ CSG 舰载机目标指派 | `survivor/carrier_strike_group.gd` `_assign_player_target()` — F/A-18 弹射即挂玩家（`acquire_target(TS_BOSS)`），舰船不猎手（物理追不动） |
| └ CSG 舰队摆位地形校验（护卫舰不落陆地） | `survivor/carrier_strike_group.gd:443` _pick_water_placement（委托 NavalPlacement 挑圆心 + 盘旋半径降级；结果写 EventLogger，仍落地则 push_warning） |
| └ 候选枚举常量 | `survivor/carrier_strike_group.gd:434` PLACEMENT_NUDGE_RADII（1800/3200 八方向）/ `survivor/carrier_strike_group.gd:437` PLACEMENT_RING_CANDIDATES（750→400→0 驻泊） |
| └ CSG 旗舰环形巡航（反"整队原地旋转"） | `survivor/carrier_strike_group.gd:34` CV_PATROL_RING_RADIUS（750 px，出生点即圆周切点）→ 写 `NavalUnit.patrol_center/patrol_radius` |
| **舰队摆位水域校验（共用）** | `naval/naval_placement.gd` NavalPlacement —— CSG 与战区海上任务共用；核心洞察：刚体整队绕圆心转 → **每艘船走的是一个同心圆**，沿这些圆细采即可精确判定，不用猜转位 |
| └ 轨道半径 / 占地半径 | `naval/naval_placement.gd:45` ship_orbit_radii / `naval/naval_placement.gd:20` fleet_reach（= 盘旋半径 + 最外圈偏移） |
| └ 落地计分（ring=0 走静止分支） | `naval/naval_placement.gd:57 score`（沿每艘船的同心轨道按 40 px 步长细采） |
| └ 挑圆心 / 降级挑摆位 | `naval/naval_placement.gd:77 pick_center`（由近及远，全水解即返回）/ `naval/naval_placement.gd:98 pick_placement`（盘旋半径由大到小降级，最后 0 = 原地驻泊） |
| └ 水域/全舰 TGT 回归测试 | `tests/test_naval_zone_water.gd:22 run`（`--bench=naval_zone_water`，26 断言：战区 E 三档 40px 复核 + 4/5/6 编成 + 真实六舰实例化 + 旗舰速杀负例 + 缩编/fallback + CSG 锚点） |
| **战区海上任务舰队** | `survivor/zone_mission.gd:1686 _spawn_naval_formation`（4/5/6 艘；先规划后实例化；`land_hits != 0` 绝不创建）/ `survivor/zone_mission.gd:1785 build_naval_target_roster`（安全方案全舰 TGT）/ `survivor/zone_mission.gd:1798 safe_naval_plan`（缩圈→逐艘减护卫→单旗舰→零舰船退化为空战） |
| └ 编成/几何常量 | `survivor/zone_mission.gd:1629 NAVAL_FLEET_COMPOSITIONS` / `survivor/zone_mission.gd:1642 NAVAL_RING_RADIUS` / `survivor/zone_mission.gd:1644 NAVAL_RING_CANDIDATES` / `survivor/zone_mission.gd:1650 NAVAL_ESCORT_OFFSETS`（1★/2★/3★ 占地 2150/2228/2512） |
| **战区空军边缘入场** | `survivor/zone_mission.gd` `_zone_air_spawn_origin` / `_tag_zone_air_ingress` → `_spawn_air_squadron` / `_spawn_zone_defenders`（正式首刷走 `survivor/zone_spawn_job.gd` `_spawn_member`）/ `_spawn_sentinel_garrison`；抵达清标 `survivor/survivor_spawner.gd` `_tick_zone_air_ingress`；离屏冻结豁免 `survivor/survivor_mode.gd` `_update_offscreen_lod` |
| └ 聚焦回归 | `tests/test_zone_air_support.gd` `_test_visible_spawn_deadlock_recovery` / `_test_hostile_zone_edge_ingress`（纯空战恢复带、静态目标可见门、边界外入口、朝向、LOD meta 生命周期、三条正式消费路径） |
| └ 猎手回归测试 | `tests/test_boss_hunter.gd`（`--bench=boss_hunter`，117 断言：PURSUE_UNIT 执行分支/无归巢/世界边缘软收容+40px 物理硬护栏+ace_support 撤离负例/KNIGHT-SNIPER 角色/死 meta 清除/热诱弹 4 命/瞄准误差开门/减速迟滞） |
| **WRAITH 队级战术状态机** | `survivor/wraith_tactics.gd` WraithTactics — PERCH（爬到玩家+2000m 档 / 1500m 差或 12s）→ BRACKET（BAIT 不开火拉到玩家机头前 3000m，三翼 ≥60° 离轴切入，咬住 4s 收网或 20s）→ PRESS（15s 完全放手 BFM）→ RESET（8s 脱离 3000m+爬升）→ 回 PERCH；退化检测 0.5s 采样、均值 >50° 持续 6s 强制 RESET。**Wraith 专属窄井**（spec wraith-squadron §2.3/§3.1~3.4） |
| └ 战术层钩子 | `survivor/ace_squad.gd` `_tactics_enter/_tactics_update/_tactics_exit` 三个空虚方法（基类不含 Wraith 逻辑）；`survivor/f47_ace_squad.gd` 持有 `tactics` 并转发 |
| └ 包夹的执行端 | 复用命令轮盘的包围轴：`ai/tactical/tactical_planner.gd` `_apply_surround_axis`（>1500m 飞自己扇区的进入门点、近了解除偏置收敛，**真实转弯不挪坐标**）；`ai/tactical/situation.gd` 读取门为 tier=ace 开窄口（敌机没有 commanded_target） |
| └ 战术层纯函数（可单测） | `wraith_tactics.gd` `pick_bait()` / `wing_bearings()` / `axis_heading()`（**heading 约定 0=北**，与 surround_bearing 消费端同源）/ `is_biting()` / `average_nose_off_deg()` / `perch_tier_for()` |
| **POLTERGEIST 队级战术**（死锁换手） | `survivor/poltergeist_tactics.gd` PoltergeistTactics — 共速绕圈死锁（机头偏角 >55° 持续 4s、距玩家 ≤4000m）→ 只派**最咬不住的 1 架**爬升 HIGH + 背离拉开 2200m 重整 3.5s、其余继续压（**同时换手上限=1**=灵魂）。与 `EngagementSpeedGovernor` 互补（治理修速度几何、本层修"谁也咬不住"死锁）。接线在 `poltergeist_squad.gd` `_tactics_*` 钩子。**Poltergeist 专属**，区别于 Wraith 全队 RESET（spec bosses/poltergeist-squadron） |
| └ 死锁换手回归测试 | `tests/test_poltergeist_tactics.gd`（`--bench=poltergeist_tactics`，9 断言：4 纯几何 + 5 换手/上限/排除 sim） |
| └ 战术层纯函数（可单测） | `poltergeist_tactics.gd` `nose_off_deg()`（单机对某点机头偏角，heading 0=北） |
| **王牌角色** KNIGHT / SNIPER | `survivor/ace_squad.gd` `AceRole{NONE,KNIGHT,SNIPER}` + `ROLE_META` + `role_of()` + `_apply_role()` — 前 2 架 KNIGHT（机炮 / `bvr_only=false` 转身对抗），后 2 架 SNIPER（导弹 / `bvr_only=true` 站位带 4~6km）。取代 `combat_specialty`（只写不读）与 `f47_role`（只读不写）两个死 meta |
| └ 角色消费点 | `ai_controller.gd` `is_boss_attacker()` 兜底改读角色 meta；`survivor/survivor_hud.gd` 状态标签 CLOSE/STRIKE（**只显示行为，不暴露角色代号**） |
| **机炮瞄准误差开关** | `aircraft.gd` `gun_aim_error_enabled`（从 `use_tactical_preference` 拆出——那是操控模式标志，兼任导致**全部 AI 敌机零瞄准误差**）；两处门在 `aircraft/aircraft_weapons.gd`；王牌由 `survivor/ace_tier.gd` `mark()` 开启 + 写 `pilot_aim_skill=0.85`（→ ±1.2°） |
| **王牌中队 tier 语义** | `survivor/ace_tier.gd` AceTier — 成员判定 is_ace_type / 打标 mark / 查询 is_ace / 缩放豁免 no_scale / HP cap 豁免 exempt_from_hp_cap / 血量 apply_hp |
| └ tier 回归测试 | `tests/test_ace_tier.gd`（`--bench=ace_tier`，80 断言：成员/缩放/HP cap/残血保证/打标/profile 表/固定两槽边界与倒拨锁存/呼号保留/留档/四曲随机 one-shot/自然曲终恢复/缺资源安全门/母版导出隔离/主菜单曲加载） |
| **王牌编成 profile 注册表 / TTK 预算** | `survivor/ace_squad_profiles.gd` AceSquadProfiles — 19 份单点登记（17 支轮换 + ORION 宿敌 + HOUND 熔炉专属）；`pool_at` 排除后两类，`scheduled_wave_count` 给出两个固定槽，`defeat_units` / `estimated_ttk_s` 统一量化。**加新王牌中队 = 本表加一行** |
| └ 非 BOSS 王牌编成与主题（profile 驱动） | `survivor/ace_support_squad.gd` AceSupportSquad — element 解析 + profile 专属机炮/无人机参数资源；`survivor/ace_squad_theme_controller.gd` 中队级 2Hz 主题；`gun_lancer` 给 WhiteTea 配逐机 joust、4×5 受控短梭与单次 flare 后 J-turn |
| └ 骑士掠袭战术 | `survivor/lancer_squad_tactics.gd` LancerSquadTactics — CHARGE→VOLLEY→EXTEND 三态机 + `assign_targets` round-robin 分配；只管 `ace_tactics_owned` 成员 |
| └ 王牌事件（无线电/血条/留档/弹尽撤离/实测 TTK） | `events/ace_reinforcement_event.gd` — `battle_bar_info()` 支持 Debug 仅强制显示、不污染 `_battle_joined`/TTK；正式事件仍首次交火亮条并起计时 |
| └ 新局调度 | `survivor/survivor_mode.gd` `_prepare_ace_run_order` / `_update_ace_support_event` — 固定 3:30 / BOSS 前 3:00 两槽，无放回洗牌、连续两局首队防重复；同场占用时第二槽待触发且单向锁存，终态 +60s 倒拨不关槽、无冷却 |
| └ 宿敌 ORION | `events/orion_nemesis_event.gd` OrionNemesisEvent — 独立轨道调度（survivor_mode `_update_orion_event`）+ 成长档位表 `tier_for`/机号 `designation` + 生涯计数（CareerArchive `get_orion_kills`） |
| └ 王牌/宿敌回归测试 | `tests/test_lancer_squad.gd`（`--bench=lancer_squad`，52 断言：固定第一槽、静态注册表跨局清理/profile/分配/混编解析/ORION 档位/真物理掠袭 sim） |
| └ 眼镜蛇王牌分层门 | `cobra_maneuver.gd` `activate()` — `AceTier.is_ace && flares>0 → 拒绝`（flare 耗尽后解锁，tier §3.4） |
| └ 王牌线框徽章 | `meta/ace_emblem_icon.gd` AceEmblemIcon — 19 份 profile 独立几何图形（含扩编 11 队、ORION 与 HOUND；血条代号旁 + 图鉴页）；静态绘制仅变更时重画 |
| **敌人图鉴**（spec career-archive §2.6） | `meta/enemy_codex.gd` EnemyCodex — 条目注册表 + 5 分组 + 计数分派 + 完成度；BOSS 段与 `BossRegistry.BOSS_DEFS` 对齐四项并含 Black Star；`is_unlocked` 统一呈现判定，`debug_set_unlock_all` 仅本次运行覆盖。**加新敌人在此加一行** |
| **游戏信息手册**（spec career-archive §2.7） | `meta/game_info_codex.gd` GameInfoCodex — 7 分组 47 条机制说明；`tip` 字段复用 `tactical_map._TIP_KEYS` 译文（单一数据源）。**加机制说明在此加一行** |
| └ 资料库页面（两分类页签） | `meta/archive_ui.gd` + `scenes/archive.tscn` — 共享 CRT 白色终端页；敌人图鉴走 `EnemyCodex.is_unlocked`（0 杀默认剪影，Debug 可覆盖），游戏信息全文开放 |
| └ 机型标识唯一源 | `survivor/survivor_spawner.gd` `type_tag_of()` / `all_type_tags()`（enemy_type meta / 档案键 / 无线电白名单 / 图鉴共用） |
| └ 逐型地面计数 | `meta/career_archive.gd` `record_ground_kill(tag)` / `get_ground_kills_by_type()`（sam/aa/radar） |
| └ tier 调用点 | `survivor/survivor_spawner.gd` 缩放块 + `_create_enemy` 末尾打标；`survivor/survivor_mode.gd` 离屏冻结 + 预算排队两处 LOD 豁免 |
| 王牌中队基类 | `survivor/ace_squad.gd` AceSquad — 通用飞机类 BOSS 框架（角色分配/隐形/force_engage）+ 世界边缘软收容 `_update_boundary_recovery`（2000px 触发→3000px 安全带，40px 触线前硬钳；不是锚点 leash） |
| F-47 王牌小队 | `survivor/f47_ace_squad.gd` F47AceSquad extends AceSquad — 具体战斗参数 + 齐射（Herbst 已转移到 F-14） |
| F-47 隐形系统 | `ace_squad.gd` `_should_enter_cloak` / `_cloak_enter` / `_cloak_update` / `_cloak_exit` / `_has_close_player_contact` — 首次及每次结束后严格 60s CD、可重复、无紧急提前触发 / 5.5s 隐形 / 1.0s 淡入淡出 / 当前玩家 1000px 内禁止或打断 |
| 交战主逻辑 | `ai_controller.gd:2126` _process_engage |
| └ 长机目标丢失宽限（防抖动） | `ai_controller.gd:748` |
| └ 长机目标超射程宽限 | `ai_controller.gd:764` |
| 导弹规避流程 | `ai/missile_evasion.gd:30` process_evade |
| 普通僚机机炮咬尾自保/原任务恢复 | `aircraft.gd` report_gun_tailed → `ai/gun_evasion.gd` eligible / source / tick / process / _submit / clear → `ai/missile_evasion.gd` process_evade / exit_evade；`ai_controller.gd` _physics_process_impl / manual_control / set_event_directive |
| 机炮自保自动/真实飞行/生命周期验收 | `tests/test_gun_evasion.gd` run / _setup / _aircraft / _reset_geometry / _restart / _check；`tests/gun_evasion_lifecycle_case.gd` run / _aircraft / _check；`tests/gun_evasion_runner.gd` _ready / _run；bench gun_evasion / gun_evasion_flight / lifecycle_gauntlet |
| 进入规避 | `ai/missile_evasion.gd:101` enter_evade |
| 退出规避 | `ai/missile_evasion.gd:144` exit_evade |
| 尝试进入交战（含引力交战地板） | `ai/target_selection.gd` try_engage |
| 自动目标超杀即时让路（机炮优先豁免；只禁补弹、不换目标） | `aircraft/aircraft_weapons.gd` TEAM_OVERKILL → `ai_controller.gd` request_overkill_retarget → `ai/target_selection.gd` reevaluate_target |
| 目标重评估（含引力地板脱离 ×2） | `ai/target_selection.gd` reevaluate_target |
| 脱离交战（重置小队交战标志与长机丢目标宽限） | `ai/target_selection.gd` disengage |
| 战场引力上下文（三带判据/引力曲线/交战地板/可行性门常量） | `ai/objective_context.gd` 全模块（`is_objective` / `is_survival_threat` 为 `Variant` 生命周期边界，先拒绝已释放引用；spec battlefield-gravity；生存模式填充在 `survivor/survivor_mode.gd` _update_objective_context；回归 `tests/test_target_selection.gd` G6b） |
| 来袭导弹检查 | `ai/missile_evasion.gd` check_incoming_missile / find_nearest_incoming_missile |
| 规避入口分层门（flare 优先不脱队） | `ai/missile_evasion.gd` should_enter_evade（B1，2026-07-03） |
| 控制意图仲裁（pursuit/speed/AB 写入权收口） | `aircraft/control_intent.gd` + `aircraft.gd` submit_intent/_resolve_intents（Phase 1，2026-07-04） |
| 小队雷达距脱离豁免（协同/自主交战继续由 squad leash 约束） | `ai_controller.gd` `is_range_disengage_exempt` / `_process_engage`；长机丢目标仍用 `LEADER_TARGET_LOST_GRACE` |

## 编队系统

| 功能 | 位置 |
|------|------|
| 阵型偏移计算 | `squad.gd:146` get_formation_offset |
| 僚机世界坐标 | `squad.gd:209` get_wingman_target |
| 阵型循环 | `squad.gd:241` cycle_formation |
| 长机继任原子修复（全员 AI.squad / index / formation leader 缓存） | `squad.gd:81` cleanup / `squad.gd:115` _sync_member_bindings；接管回调 `survivor/survivor_mode.gd` _on_squad_leader_changed |
| 生成友方编队 | `main.gd:324` _spawn_friendly_squad |
| 生成敌方编队 | `main.gd:371` _spawn_enemies |
| 护卫学说开关字段 | `squad.gd` escort_doctrine_enabled（玩家队/F-47/Mother Goose 建队 on，杂兵 off） |
| 护卫僚机判定 / 目标加权 | `ai/squad_coordination.gd` is_escort_wingman / escort_target_bonus（咬长机+近长机加权，squad-ai-escort） |
| engaging_me 维护范围（反向索引） | `ai_controller.gd` _maintains_engaging_me（team0 OR 护卫编队）+ _physics_process_impl 差量同步 |
| 护卫评分常量 | `ai_controller.gd` ATTACKING_LEADER_BONUS / LEADER_PROXIMITY_BONUS_MAX |
| 交战模式（三态 FREE/FOLLOW_LEADER/GUARD_REAR） | `ai_controller.gd` squad_engage_mode（默认 FOLLOW_LEADER）+ `survivor_hud.gd` 交战模式按钮三态循环 + `_squad_engage_mode_label`（squad-cohesion） |
| 守护后方模式 / 自主交战入口 | `ai/squad_coordination.gd` process_squad_follow GUARD_REAR 分支 + `_enter_autonomous_engage` + `_guard_rear_tick`（空中 scan_leader_rear → 否则地面 scan_leader_threat_ground）（squad-cohesion §2.1） |
| 守护者打地面 AA / 守后紧 leash | `ai/squad_coordination.gd` `scan_leader_threat_ground`（SAM/AAA 导弹远射）；`ai_controller.gd` `effective_squad_leash()`（REAR_GUARD_LEASH_DIST=1200 守后紧、打地面放宽 1800）+ REAR_GUARD_RANGE=900 |
| 战场引力 leash 松绑（生存 4200px 锚操控机 / objective 重锚 / 旧行为三态） | `ai_controller.gd` `leash_anchor_and_limit()`（_apply_constraints 消费，spec battlefield-gravity §3.4） |
| 生存层主动回防（操控机被咬 → 僚机反咬，≤2 机） | `ai/squad_coordination.gd` `try_defend_protectee` + `_count_defenders`（SQUAD_FOLLOW 常开 1Hz，spec battlefield-gravity §3.3） |
| 自由机互掩（双重攻击学说） | `ai/squad_coordination.gd` `_should_be_free_fighter`（FOLLOW_LEADER 打飞机非 BOSS+≥2僚机→最高号机守后）+ `_is_boss_target`（squad-cohesion 阶段3） |
| 战术=阵型绑定 / 阵型映射 | `squad.gd` formation_for_engage_mode（自由→Spread/跟随→FingerFour/守后→Wedge）；切模式时 `survivor_hud._on_squad_engage_pressed` 设 sq.formation（玩家手动切阵型已废弃：删按钮 + KEY_5） |
| 敌方随机阵型 | `squad.gd` random_formation（除 Trail）；`survivor_spawner._spawn_squad` 杂鱼登场随机；精英/Boss 建队显式固定 |
| 自由交战搜索范围 | `ai_controller.gd` SQUAD_FREE_SCAN_RANGE=1500px（自由交战只接管约 3km 内靠近敌机） |
| 小队防游走 leash | `ai_controller.gd` `_apply_constraints` 僚机越界 break-off（SQUAD_LEASH_DIST=1800/HYSTERESIS=0.5）；`_cmd_engage_active` 让跟打长机玩家点名目标高于普通归队（squad-cohesion §3.2 / rts-command §3.2） |
| 狂化病毒（僚机动态门 / FREE 锁定 / 禁主动切控 / 机动-CD / 击杀嗜血） | `aircraft.gd` `is_berserk_virus_wingman` / `enforce_berserk_virus_free_mode` / `cd_rate`；`aircraft/aircraft_physics.gd` `_g_buff_mult` / `base_roll_rate` / `effective_accel_mult` / `effective_decel_mult`；`ai_controller.gd` `_physics_process_impl`；`survivor/survivor_mode.gd` `_switch_control_to_slot`；`survivor/survivor_hud.gd` `_on_squad_engage_pressed`；`survivor/skill_hooks.gd` `dispatch_on_kill`；生命周期回归 `tests/test_skills_720.gd` `_test_berserk_virus_reference_lifecycle`（关闭/开启技能时已释放玩家引用，显式安全读取清理） |

## 地面单位

| 功能 | 位置 |
|------|------|
| 地面单位移动 | `ground_unit.gd:84` _update_movement |
| 地面自动目标选择 | `ground_unit.gd:141` _update_target_selection |
| 地面机炮战斗 | `ground_unit.gd:176` _update_combat |
| 地面机炮射击 | `ground_unit.gd:211` _update_gun |
| SAM 只对空选敌 / 导弹发射 | `sam_unit.gd:38` _update_target_selection / `sam_unit.gd:61` _update_sam_missile |
| AA 炮塔转向 | `aa_gun_unit.gd:85` _update_turret |
| AA 目标选择（最近敌机；拒绝地面单位） | `aa_gun_unit.gd:31` _update_aa_target_selection |
| 雷达站数据链 | `radar_station.gd:35` _update_datalink |
| 战略硬目标（不可锁定；仅 bomber_bomb；护送目标预刷常驻 TGT/轰炸权限提示） | `strategic_target.gd` `set_bomber_escort_objective` / `take_bomber_damage` / `_draw_bomber_escort_hint`；场景 `scenes/strategic_target.tscn` |
| 远距空爆高炮（陆基/舰载共用冻结解与偏角采样 + 火光/烟团 VFX） | `airburst_aa_unit.gd:109 sample_burst_solution` / `airburst_aa_unit.gd:129 sample_shell_solution` / `bullet_manager.gd:282 spawn_airburst_shell` / `bullet_manager.gd:713 _explode_airburst_shell` / 战区替换 `survivor/zone_mission.gd:980 _spawn_ground_garrison` |
| 车队管理 | `ground_convoy.gd:12` add_member |

## 海上单位 / 船伤害路由

| 功能 | 位置 |
|------|------|
| NavalUnit 物理主循环（含状态 tick） | `scripts/naval/naval_unit.gd:181` _physics_process |
| 移动（环形巡航 / waypoints / 编队三分支）| `scripts/naval/naval_unit.gd:303` _update_movement |
| 僚舰刚体跟随（复制 leader heading + 自注册到 `_followers`）| `scripts/naval/naval_unit.gd:354` _update_formation_follow |
| **旗舰转速上限**（治"整支舰队原地旋转"）| `scripts/naval/naval_unit.gd:376` _effective_turn_rate —— 有僚舰时 ω ≤ FORMATION_TANGENTIAL_CAP_PXS / r_max；无僚舰原样透传 |
| 位置感知伤害入口（双池：部件 + hull）| `scripts/naval/naval_unit.gd:518` take_damage_at |
| 状态过滤（船只接受 JAM）| `scripts/naval/naval_unit.gd:578` apply_status |
| 弱点暴露判定 | `scripts/naval/naval_unit.gd:588` _check_weak_point_reveal |
| 编队运动回归测试 | `tests/test_naval_formation.gd`（`--bench=naval_formation`，10 断言：环形巡航转位 ≤0.35°/s、僚舰对地 ≤12 px/s、无掉头、U-turn 兜底、单船不变） |
| 武器派发（JAM 早返）| `scripts/naval/naval_weapons.gd:56` update |
| DDG 舰载 Flak（2Hz 搜敌、三连发、6s 冷却、不拦导弹）| `scripts/naval/naval_weapons.gd:365 _update_naval_flak` / `scripts/naval/naval_weapons.gd:386 _find_aircraft_for_flak` / `resources/naval/mount_ddg_flak_s.tres` / `resources/naval/destroyer_ddg.tres` |
| 舰载 Flak hover 包线 / 挂点符号 | `scripts/naval/naval_unit.gd:826 _draw_flak_envelopes` / `scripts/naval/naval_unit.gd:936 _draw_alive_mount` |
| 子弹命中船（机炮 hull 0.15× / 弱点可磨）| `scripts/bullet_manager.gd:748` _physics_process 的 NavalUnit 分支 |
| 火箭弹命中船（hull 0.5× / 可磨弱点）| `scripts/bullet_manager.gd:748` _physics_process 的 is_rocket 分支 |
| 火箭弹 AOE 命中船 | `bullet_manager.gd:600` _explode_rocket |
| 导弹近炸 AOE 命中船（含 alt_ok 例外）| `missile_manager.gd:716` _update_aoe_zones |
| 电磁炮命中船按母舰归并（船体 + MountTarget 代理同挂 all_units → 一发多次结算）| `equipment/railgun_equipment.gd:445` _apply_hitscan_damage |
| └ 伤害归属母舰（代理 → 母舰） | `equipment/railgun_equipment.gd:510` _naval_damage_sink |
| └ 沿弹道取最靠前命中点（一发一舰只结算一次） | `equipment/railgun_equipment.gd:520` _segment_param |

## 状态效果（StatusEffects）

| 功能 | 位置 |
|------|------|
| 状态常量（INVINCIBLE/STEALTH/BLOODLUST/OVERLOAD/JAM/SLOW/FEAR）| `scripts/status_effects.gd:11-22` |
| 通用 tick（倒计时 + 写 status_jam_active）| `scripts/status_effects.gd:119` tick |
| Aircraft 专用 update（所有派生标记 + 副作用）| `scripts/status_effects.gd:140` update |
| 词条一句话说明（升级卡脚注文案 i18n key）| `scripts/status_effects.gd:107` note_i18n_key（表 `status_effects.gd:97` NOTE_I18N_KEY）|
| 技能 → 状态词条映射（keywords + EXTRA + OVERRIDE）| `survivor/survivor_data.gd:2542` status_notes_of |
| Aircraft.apply_status 覆写（UAV 滤 FEAR / OVERLOAD 钩子）| `aircraft.gd:3165` apply_status |
| NavalUnit.apply_status 覆写（只接受 JAM）| `scripts/naval/naval_unit.gd:578` apply_status |
| AOE 状态广播（fear_applies_slow 联动）| `scripts/survivor/aoe_broadcast.gd` apply_status_in_radius |
| 四词条亲和、软聚焦与终端债务纯函数 | `scripts/survivor/survivor_data.gd` compute_status_build_affinity / status_focus_multiplier / select_terminal_service_tag / pick_terminal_for_tag |
| 三轴事件接入终端 ×2/×4/第三次强制 | `scripts/survivor/survivor_mode.gd` _roll_axis_cards |
| 嗜血免机炮弹药 + Ratatat 有效机炮参数 | `scripts/aircraft.gd` bloodlust_gun_ammo_free / effective_gun_range_m / effective_gun_cone_half_angle_deg / effective_gun_fire_interval |
| StormⅠ/Ⅱ实际耗能与免费充放 | `scripts/survivor/afterburner_charge.gd` update |
| 精神错乱 / Hush / Stasis 低频事件 | `scripts/survivor/skill_hooks.gd` on_player_fear_landed / on_player_jam_landed / dispatch_on_hit |
| 火控饱和（五锁上升沿 / 单局 CD / OVERLOAD 期间 +2 锁） | `scripts/survivor/skill_hooks.gd` try_fire_control_saturation → `scripts/survivor/survivor_mode.gd` _finish_radar_window；`scripts/aircraft.gd` effective_max_locks |
| Hush 热诱弹闸门与新弹失导 | `scripts/aircraft/aircraft_flares.gd` update / release；`scripts/missile_manager.gd` spawn_missile |
| CD 速率栈（不改写运行中倒计时） | `aircraft.gd` `cd_rate` → `aircraft/aircraft_weapons.gd` / `aircraft/aircraft_flares.gd` tick 消费 |
| 云中 OVERLOAD 单一 timed 状态入口 | `aircraft.gd` `_update_cloud_state` / `apply_status`；`status_effects.gd` `CLOUD_OVERLOAD_BASE_DURATION` |
| 运行时修改器黑盒差分 | `modifier_trace.gd` `explain` / `print_report`；生存模式 Shift+F12 |

## 生存模式

### survivor_mode.gd — 主控制器（~1450 行）

#### 初始化 & 常量
| 功能 | 位置 |
|------|------|
| 敌机类型枚举 EnemyType | `survivor_mode.gd:843` |
| 敌机参数基 preload | `survivor_mode.gd:104-112` |

#### 主循环
| 功能 | 位置 |
|------|------|
| 相机跟随插值 | `survivor/survivor_mode.gd:4119` _process |
| 物理主循环（总入口） | `survivor/survivor_mode.gd:4188` _physics_process |
| 选中列表清理 | `survivor/survivor_mode.gd:4563` _cleanup_references |
| 飞机列表同步 | `survivor/survivor_mode.gd:4570` _update_aircraft_list |

#### 雷达锁定
| 功能 | 位置 |
|------|------|
| 全局锁定计算 | `survivor/survivor_mode.gd:4646` _update_radar_locks |
| 雷达锁定窗口内错峰分片（0.2s 窗口 × 4 片，独立片时钟 + 窗口末 O(N) 收束） | `survivor/survivor_mode.gd` `_update_radar_locks` → `_radar_slices_due` / `_run_radar_slice`（本相位 shooter 按 `(i / stride) % RADAR_LOCK_SLICES` 分片配对）/ `_finish_radar_window`（失联收束、数据链、火控、围猎、玩家可见锁定清零+重建）；导弹上限压锁 `_enforce_player_missile_cap` 每片与窗口末各跑一次 |
| 近距捕获（距离归一化倍率） | `survivor/survivor_data.gd` `close_range_lock_mult` → `survivor/survivor_mode.gd` `_run_radar_slice` |
| 火控饱和五锁触发 | `survivor/skill_hooks.gd` `try_fire_control_saturation`，由 `_finish_radar_window` 在数据链合并后调用 |

#### 动态性能 / LOD / 清理
| 功能 | 位置 |
|------|------|
| 当前通用性能门（Sentinel 非权威） | `survivor/survivor_mode.gd` `_bench_force_battlefield_atmosphere_stress` / `_bench_enable_camera_patrol` / `_bench_update_camera_patrol` / `_bench_camera_patrol_summary` + `bench/bench_camera_patrol.gd` `sample`：C1 `battlefield_atmosphere_stress_36` 为 8 km 混合 draw 门；C2 `battlefield_atmosphere_stress_48_24km` 为多战线/LOD 门；3 秒预热后 18 秒确定性巡检 8/8 段，覆盖平移、缩放与旋转。海洋专项 `final_war_ocean_baseline/stress` 复用轨迹并按战线中心/横纵尺度变换；统一按 `reference/performance-guidelines.md` 运行 `Shadow Visual` |
| 帧统计与负载摘要 | `survivor/survivor_mode.gd` `_process` / bench 收尾：3s 预热后记录 avg/p1/worst/<60；`battlefield_atmosphere_experiment.gd` `stress_summary` 记录目标/存活成员/跨度/炮弹 |
| 性能热点与人口/弹丸快照 | `util/perf_buckets.gd` `format_hud_lines` / `format_full_dump`；飞机/尾迹/舰船/子弹/导弹/雷达/AI 各自 `PerfBuckets.tick/set_value/count`；飞机 `ac_phys.*` 细分桶与 `aircraft_draw.*` 一样只在 `detail_capture_enabled()` 采样帧计时（`aircraft.gd` `_perf_lap`），`aircraft_phys` 根桶恒计时 |
| 物理步帧 / 无步帧负载均衡 | `util/perf_buckets.gd` `physics_steps_this_frame` / `frame_has_physics_step`（AutoLoad `_process` 起点按引擎物理帧差结算）→ `rendering/tokyo_cell_stream.gd` `defer_to_light_frame`（`light_frame_balance` 默认关，`rendering/tokyo_hlod_overlay.gd` 正式流开启）：非当前可见的完成件领取（`_light_defer_exempt`，HLOD 流按 `visible_meshes` 豁免）与 `rendering/tokyo_hlod_stream.gd` `_step_textures` 非可见纹理上传在含物理步帧有界延后（连续 ≤ `LIGHT_FRAME_MAX_DEFER` 帧，暂停/关闭不延后），计数 `summary.light_frame_deferrals` |
| 地图主线程重活错峰（交接 / 规划准入 / 规划提交同帧互斥、优先无物理步帧） | `rendering/tokyo_hlod_overlay.gd` `_heavy_contested`（只读争用判定，交接仅争用时才算覆盖核验）/ `_heavy_slot`（`map_frame_balance`，由 `survivor/map_feature_renderer.gd` 正式地图开启；每类连续让出 ≤ `MAP_HEAVY_MAX_DEFER`；仅当前切面合格且覆盖视野时可让）→ `_commit_ready_target` / `_step_prepared_selection`；计数 `debug_state.heavy_deferrals` / `heavy_deferrals_by_kind`（流送节点 `process_priority` 先于 overlay，不能用同帧标记反向让流送避让） |
| 正式位置证明核验复用 / 资源存在性缓存 | `rendering/tokyo_hlod_stream.gd` `_matches`（同路径 + 同文件 SHA + 同位置证明本会话已核验即复用，`summary.formal_verify_reuses`）；`rendering/tokyo_cell_stream.gd` `_process_stream` 的 `_known_resources`（已确认存在的路径不再查文件系统）；诊断子桶 `tokyo_map_stream.collect` / `request` / `exists` / `textures` / `coverage_verify`（`rendering/tokyo_hlod_coverage.gd` `matches` 内 arrays / expand / hash）、`tokyo_map_plan_take` / `tokyo_map_plan_request` |
| AI 决策相位展开 | `ai_controller.gd` `_ready`：`_tick_phase` 按实例 ID 展开到 `TICK_PHASE_SPAN`（保持 simple_ai 原 %3 相位、不耗全局 RNG），拥挤降频后的 divisor 2/6 不再集中在同一批物理帧 |
| F3 运行时详细面板 | `survivor/survivor_hud.gd` `set_performance_panel_visible` / `_update_debug_panel` → `util/perf_buckets.gd` `configure_runtime_panel` / `format_detailed_hud_lines`；最近 120 帧 avg/p95/worst/<60、引擎 Canvas/2D physics、海陆空/弹丸/HUD/系统细桶、生存主循环 cache/LOD/spawner、BOSS 阶段、技能事件、人口/调用/内存与前十 CPU 热点；只在面板可见时启用细分计时，`performance_hud_visual` 复用 C1 做真实截图 |
| Visual bench 慢帧事件关联 | `util/perf_buckets.gd` `configure_frame_trace` / `begin_render_frame` / `_update_trace_context` / `_trace_frame_percentiles` / `_trace_spike_class` / `mark_frame_event` / `format_frame_trace_dump`；上一帧 delta 与同帧工作量正确配对，最多 8 个尖峰保留前 120 / 后 30 帧，输出 p95/p99/max、保守根因及预热后全程根桶均值/活跃帧/known share；默认每 4 帧采细桶，`AGL_BENCH_FRAME_TRACE_MODE=full/off` 做 observer-tax A/B；`survivor_mode.gd` 3s 预热后启用并关联 `survivor_cache/lod/spawner`、雷达、气氛、日志、音效、无线电、技能与海陆空/弹丸负载；契约 bench `perf_trace` |
| 显式扩展 CPU 归因（默认关闭） | `util/perf_buckets.gd` `configure_frame_trace` / `finish_extended_cpu` / `extended_cpu_root_usec`；`AGL_BENCH_EXTENDED_CPU_TRACE=1` 与 frame trace 同时启用才注册扩展根；扣除已记录父区间及其外的共享日志/音效/无线电，包装作用域只有 exclusive 加入新根总和，原先独立的 unit_status_overlay 同时列为扩展根，total/covered/shared 与 function 子项仅诊断；负值记录 invalid 并拒绝该次根归因。回归 `tests/test_perf_frame_trace.gd` `_test_extended_cpu_trace` |
| 逐帧引擎阶段分解与卡顿飞行记录（默认关闭） | `diagnostics/frame_probe.gd` `_boundary` / `_finish_frame` / `_pb_frame_delta` / `_sample_display` / `dump`，由 `bench/bench_runner.gd` `_ready` 在 `AGL_FRAME_PROBE=1` 时挂载；`diagnostics/frame_probe_autoplay.gd` `_drive` 自动游玩正式局，`bench/run.cmd probe_play` 场景只经守护启动、不进入任何 bench 分支 |
| 物理插值显示态与帧上限（显示节拍） | `util/display_pacing.gd` `install` / `_demote_viewport`（入树视口强制关闭插值）/ `set_interpolation_enabled` / `is_interpolating` / `display_global_transform` / `display_origin` / `display_screen_origin` / `display_rotation_offset` / `rotation_offset_from` / `display_time_lag` / `set_max_fps`，由 `presentation/presentation_director.gd` `_ready` 安装；白名单单位 `aircraft.gd` / `missile.gd` 的 `_ready` / `_physics_process` / `_notification`；传送收口 `aircraft.gd` `clear_trail`；消费方 `camera_controller.gd` `_update_follow` / `cine_follow_tick`、`ui/world_unit_status_overlay.gd` `update_screen_position` / `_draw`、`experiments/volume_world_probe.gd` `_process` / `_sync_goose_mounts`、`trail_ribbon.gd` `_process_trail_untraced`、`survivor/survivor_mode.gd` `_bench_update_camera_patrol`；子弹批绘与飞机自绘连线保持 60Hz（spec display-pacing §3.4）；顿挫指标 `tools/frame_probe_motion.py`；回归 `tests/test_display_pacing.gd`（bench `display_pacing`） |
| 扩展实体物理与系统余量 | `missile.gd` / `aa_gun_unit.gd` / `sam_unit.gd` / `airburst_aa_unit.gd` / `radar_station.gd` / `survivor/bomber_mission.gd` 的 `_physics_process` 包装；`survivor/survivor_mode.gd` `_physics_process_survivor_untraced` / `_extended_survivor_cover_root` 扣除 cache/radar/LOD/spawner；预测准备在 `_process` 计量；`trail_ribbon.gd` `_process_trail_untraced` 与既有 draw 桶分开。默认执行顺序、频率与画质不变 |
| 扩展画布 CPU 入口及函数诊断 | `ui/world_unit_status_overlay.gd` `_process` / `_draw` 与内部面板 `_draw`；`rendering/aircraft_volume_overlay.gd` `_process`；`weather_system.gd` `_draw_weather_untraced`；`survivor/battlefield_atmosphere_experiment.gd` `_draw_atmosphere_untraced`；`aa_gun_unit.gd` / `sam_unit.gd` 独立 `_draw`；非根函数桶来自 `trail_ribbon.gd` `_rebuild_cached_geometry`、`aircraft_renderer.gd` `draw_predicted_path`、`rendering/canvas_triangle_packet.gd` `submit_arrays`。均为主线程函数墙钟，包含执行期间的等待，不证明同帧 GPU 工作 |
| 诊断记录自身开销 | `util/perf_buckets.gd` `begin_render_frame` 清空后记入新帧；`tests/tokyo_volume_combat_runner.gd` `_process` 跨父类重置保存自段与 RenderTrace.begin 成本；`tests/tokyo_render_trace.gd` `_after_draw` 在原生绘制边界之后计量结果读回；`diagnostic.*` 单列，不重复加入 CPU 根桶 |
| triangle-array 共享组包/提交 | `rendering/canvas_triangle_packet.gd` `append_triangle` `append_indexed` `submit_arrays`；地图静态 packet、尾迹、爆点共用，领域缓存/LOD 各自保留 |
| 尾迹缓存与战略几何 LOD | `trail_ribbon.gd` `_process` / `geometry_point_step_for` / `_desired_geometry_point_step` / `_rebuild_cached_geometry`：父机移动时本地变换取父机显示态之逆（插值关闭时即 identity 全局变换），retained Canvas 命令只在 20Hz 新采样、淡入/剔除或样式变化时重建；0.26 以下普通演员隔点构网格但不缩短路径，玩家/BOSS/Sentinel/玩家导弹豁免 |
| 战略视距 Canvas 提交 LOD | `aircraft_renderer.gd` `target_marker_detail_visible_at_scale` / `draw_target_line`（普通友军保留主线）；`missile.gd` `data_label_visible_at_scale` / `body_detail_visible_at_scale`（来袭与玩家弹豁免）；`naval/naval_unit.gd` `mount_detail_visible_at_scale` / `_draw_mounts_placeholder`（位置与损毁态仍可读） |
| 导弹尾迹八相集中批绘 | `missile_manager.gd` `register_missile_trail` 建 internal 批次子树 → `missile_trail_batch.gd` `_draw` → `trail_ribbon.gd` `append_to_missile_batch`；0.26 以下普通导弹四点构网格，玩家弹/真实来袭弹逐点豁免 |
| 绘制 RNG 隔离 | `aircraft_renderer.gd` `visual_noise01_for` / `visual_noise01`；机炮闪光、加力火焰、导弹尾焰、电磁炮抖动只读时间+实例 ID，不消费战斗全局 RNG |
| 高频飞机组件缓存 | `aircraft.gd` `_refresh_maneuver_cache` / `get_maneuver` / `get_herbst`；子节点顺序变化后失效重建；契约 bench `component_cache` |
| 导弹命中 broad-phase | `missile_manager.gd` `_rebuild_target_grid` / `_ordered_target_candidates`：每 tick 一次 UnitGrid，邻格小单位 + 全部舰船，按旧 target_list 顺序命中；契约 bench `missile_grid` |
| 纯视觉普通弹 SoA | `bullet_manager.gd` `spawn_bullet` / `_update_visual_bullets` / `total_bullet_count`：PackedArray 位置/速度/寿命，同帧到期用单次线性压紧与末尾缩容；真实弹/火箭/CIWS 拦截不降级；大型舰船候选按射手阵营预分；契约 bench `visual_bullet_soa` / `bullet_grid` |
| 性能桶无分配 rollover | `util/perf_buckets.gd` `_process`：窗口/快照 Dictionary 双缓冲交换，避免每秒三次 duplicate |
| 玩家预测轨迹分帧预算 | `aircraft/aircraft_physics.gd` `PredictionWork` / `begin_player_path_prediction` / `advance_player_path_prediction` / `player_path_prediction_result` / `predict_player_path` → `survivor/survivor_mode.gd` `_process` → `aircraft_renderer.gd` `update_predicted_path_cache` / `prediction_display_result` / `draw_predicted_path`；360 步按 24 步/渲染帧推进，完成缓存至少间隔 200ms，显示按 4:1 抽样且 `_draw` 不推进预测；等价性 bench `predicted_path` |
| BOSS 最坏态性能门 | `survivor/survivor_mode.gd` `_bench_force_spawn_boss_wraith_stress` / `_bench_force_spawn_boss_csg_stress`：Wraith+YF-23 与强化 CSG→Poltergeist 二阶段均加 12 友军并用真实 0.20 镜头；`boss_wraith_stress` / `boss_csg_stress` 必须 `Shadow Visual` |
| FPS 采样与动态上限调整 | `survivor/survivor_spawner.gd:375` update_fps_sampling |
| 平均 FPS 查询 | `survivor/survivor_spawner.gd:383` _get_avg_fps |
| 屏幕外 AI/物理降频 | `survivor/survivor_mode.gd` `_update_offscreen_lod`（Sentinel 长机与 `sentinel_native_escort` 原生护卫整组豁免冻结） |
| 未关注普通战区 0 实体层 | `survivor/zone_mission.gd` `zone_simulation_should_activate` / `_ensure_spawned_for_active_zones`；未观察普通 1★/2★ AVAILABLE 只保留 ZoneData，镜头预加载/SELECTED/进入圆内/3★生成；`prepare_visible_zones` 在镜头更新后绘制前执行；回归 `tests/test_offscreen_world_simulation.gd`（bench `offscreen_world`） |
| 攻克后敌机撤离与离屏释放 | `survivor/zone_mission.gd` `_begin_conquered_garrison_egress` / `_command_conquered_enemy_exit` / `_schedule_despawn` / `_flush_pending_despawn`；地面经 `ground_unit.gd` `retire_in_place` 原地留场，`survivor/zone_mission.gd` `_refresh_retained_ground_views` 2Hz 刷新可见读数；飞机经 `survivor/unit_retirement.gd` `begin_aircraft_exit` / `release_ready` 真正出界并远离玩家及镜头后分批释放；Spawner `_queue_aircraft_retirement` / `_update_retiring_aircraft` 复用相同门；回归 `tests/test_zone_air_support.gd` `_test_retirement_distance_and_budget` + `tests/lifecycle_gauntlet_runner.gd` `_test_retired_ground_after_real_damage`；画面/实飞 `tests/unit_retirement_visual.gd` `_process` / `_finish_retirement_visual` |
| 已坠毁敌机清理 | 统一由 `aircraft_destruction.gd update/_update_post_breakup_linger` 持有释放权威；`survivor_mode` 不得按 `_destroy_timer` 旁路释放，否则大型机随机坠毁时长会触发同帧消失 |
| 远距清理（释放 Token） | `survivor/survivor_spawner.gd:3653` _update_far_cleanup |

#### 猎手系统
| 功能 | 位置 |
|------|------|
| 猎手指派主循环 | `survivor/survivor_spawner.gd:3765` _update_hunters |
| BOSS 世界边界物理硬护栏（不接管战术/火控） | `survivor/survivor_spawner.gd:3879` enforce_boss_world_boundary |
| 空闲敌机航点围绕玩家 | `survivor/survivor_spawner.gd:3973` _update_enemy_waypoints |
| 获取 AI 控制器 | `survivor/survivor_mode.gd:5211` _get_ai |
| 导弹上限查询（飞向玩家数）| `survivor/survivor_mode.gd:5383` _count_missiles_targeting_player |
| 筛选未发射敌机 | `survivor/survivor_mode.gd:5392` _get_enemies_without_active_missile_at_player |
| 敌人数统计 | `survivor/survivor_spawner.gd:4289` _count_enemies |

#### 刷怪 & Token 烈度控制
| 功能 | 位置 |
|------|------|
| 刷怪主逻辑（每波间隔/FPS闸/Token 预算）| `survivor/survivor_spawner.gd:682` _update_spawner |
| 当前 Token 预算（随等级增长）| `survivor/survivor_spawner.gd:425` _get_token_budget |
| 重算场景 Token 占用 & 每类数量 | `survivor/survivor_spawner.gd:439` _recalc_token_usage |
| 指定类型是否可生成（预算+实例上限）| `survivor/survivor_spawner.gd:451` _can_spawn_type |
| 按等级选敌机类型（概率 + Token 约束）| `survivor/survivor_spawner.gd:477` _pick_enemy_type |
| └ BOSS/事件专属机型排除（后期随机桶，F-47 / F-14 Poltergeist）| `survivor/survivor_spawner.gd:646` BOSS_ONLY_TYPES（表在 `survivor/survivor_data.gd:3533` BOSS_ONLY_TYPES）|
| 敌人作战高度分档（按机型查权重表，替代均匀 1/3 随机）| `survivor/survivor_spawner.gd:3080` pick_altitude_tier → `survivor/survivor_data.gd:3539` ENEMY_ALTITUDE_WEIGHTS + `survivor/survivor_data.gd:3585` pick_altitude_tier |
| └ 巡逻高度跟随抽到的档（经 Situation.combat_altitude_m 影响战术层交战高度）| `survivor/survivor_spawner.gd:3091` patrol_altitude_for_tier → `survivor/survivor_data.gd:3574` TIER_PATROL_ALTITUDE + `survivor/survivor_data.gd:3580` patrol_altitude_for_tier |
| AF-03 解锁/概率常量（旅途随机池入口） | `survivor/survivor_data.gd:3330` AF03_UNLOCK_LEVEL |
| AF-03 战区池入口（type 17 行） | `survivor/survivor_data.gd:3757` ZONE_ENEMY_TABLE |
| **常规敌机注册表 SSOT**（解锁/退役/Token/上限/编成/角色/冷却/阶段上限） | `survivor/enemy_pool_registry.gd` `ROWS` |
| └ 五角色权重 + 最近三队防重复选型 | `survivor/enemy_pool_registry.gd` `role_weights` / `eligible_rows` / `pick_row` |
| └ ADBS 护卫零 Token 候选池（服从解锁/退役，排除专用编成） | `survivor/enemy_pool_registry.gd` `escort_rows` → `survivor_spawner.gd` `_pick_flee_escort_type` |
| └ 敌版参数审计（无玩家资源依赖；Token 分档 HP/雷达/锁定/flare） | `survivor/enemy_pool_registry.gd` `audit_enemy_params`；bench `spawn_pool` |
| └ 57 型敌机产出路径审计（43 常规池资源/工厂 + 14 专用入口） | `tests/test_spawn_pool.gd` `_test_enemy_type_route_coverage` |
| └ 常规池数学可达性 + 响应 1/4/7/10/13 防重复蒙特卡洛产出率 | `tests/test_spawn_pool.gd` `_test_regular_pool_reachability_and_rates` |
| 玩家编队规模 → 敌方单机/双机/3–4机软倾向 | `survivor/survivor_data.gd` `pick_enemy_formation_class` / `pick_flight_size`；消费点 `survivor/survivor_spawner.gd` `_update_spawner` |
| Snowblind 特殊包（本体 + 两个动态合格护卫） | `survivor/survivor_spawner.gd` `_pick_snowblind_escort_rows` / `_spawn_snowblind_squad` |
| Snowblind 创建当帧注册 + 5Hz 显隐/滞回/跨边界停火 | `survivor/snowblind_controller.gd` `register` / `refresh_now` / `tick` / `next_reveal_state` / `_apply_concealment` / `_release_cross_boundary_targets` |
| Snowblind 单 CanvasItem GPU 连续风雪圈 + 圆心不可交互本体轮廓 + 固定飞机下层世界 Z + 0.80s 破幕/复隐过渡 | `survivor/snowblind_shroud_visual.gd` `attach` / `set_concealed`（无 `_process/_physics_process/_draw/queue_redraw`） |
| Snowblind 生成顺序层级 + 0.80s 双向渐变 Visual QA | `tests/snowblind_layer_visual_qa_runner.gd`；运行 `bench/run.cmd snowblind_layer_visual 1 180 Shadow Visual` |
| DEADAIR 特殊包（HP55 无武装本体 + 两个动态护卫；普通池与 Snowblind 互斥；3★ 来源具有单场优先权） | `survivor/survivor_spawner.gd` `_support_field_blocked` / `_spawn_deadair_squad` / `register_tier3_deadair_squad` / `retire_deadair_source`；`survivor/snowblind_controller.gd` `retire_for_priority_field` |
| DEADAIR 5Hz 累积 JAM（单位 8s；导弹 4×=2s；离圈宽限/衰减/清弹；来源退役同拍移除其自有 JAM，已永久失导弹体不倒带） | `survivor/deadair_controller.gd` `META_DEADAIR_JAM_OWNED` / `replace_with_priority` / `retire` / `tick` / `next_unit_exposure` / `next_missile_exposure` / `_tick_units` / `_tick_missiles` / `_clear_all_exposure` |
| DEADAIR 单 mesh 扫描场 + 世界八段暴露环 + 导弹尾迹插值 + Tab 场快照 | `survivor/deadair_field_visual.gd` `attach`；`aircraft_renderer.gd` `draw_deadair_exposure`；`missile.gd` `set_deadair_exposure_ratio`；`survivor/tactical_map.gd` `_draw_deadair_field` |
| DEADAIR 定向回归（阈值/阵营/地面海军/导弹/互斥/敌版/bench 静音） | `tests/test_deadair.gd` `run`；运行 `bench/run.cmd deadair 5 180 Shadow` |
| DEADAIR 主循环压力场（9 直属友机在圈 + 特殊包 + 16 额外敌机/在途弹） | `survivor/survivor_mode.gd` `_bench_force_deadair_stress`；运行 `bench/run.cmd deadair_stress 15 180 Shadow` |
| F-22 队级不同目标四锁 + 0.15s 齐射 + 12s 脱离 | `survivor/f22_multilock.gd` `register` / `allocate_unique_targets` / `tick` |
| Gripen C/E 队级三目标；Rafale/F-35 单机双目标 | `survivor/schemer_multilock.gd` `register` / `tick` / `_plan_team_three` / `_plan_per_aircraft` |
| 常规扩池原型 AI（Gladiator 持续近战 / Lancer 攻击通场 / Schemer 远距换位） | `survivor/survivor_spawner.gd` `_configure_registry_archetype` |
| 新敌机轮廓家族 / 未登记 UGC 兜底 | `survivor/survivor_spawner.gd` `_regular_silhouette_family` → `aircraft_silhouette_catalog.gd` `key_for` → `aircraft_renderer.gd` `draw_aircraft_icon` |
| 扩池专项性能场（直属9机 vs 17架 Snowblind/F-22/多锁/近远原型） | `survivor/survivor_mode.gd` `_bench_force_enemy_pool_stress`；运行 `bench/run.cmd enemy_pool_stress 20 180` |
| 狂化病毒同负载压力场（直属9机 vs 扩池17敌 + Sentinel/5护卫） | `survivor/survivor_mode.gd` `_bench_force_berserk_virus_stress` / `_bench_verify_berserk_virus_lod`；运行 `bench/run.cmd berserk_virus_baseline 15 180 Shadow` 与 `berserk_virus_stress` |
| 无头异常暂停看门狗 + 阵亡接管终局 | `survivor/survivor_mode.gd` `_bench_wall_watchdog` / `_bench_setup_survivor_death` / `_bench_update_survivor_death`；运行 `bench/run.cmd survivor_death 10 60 Shadow` |
| 单机生成（J-7 / MiG-31 / F-4E 35%）| `survivor/survivor_spawner.gd:1528` _spawn_single |
| 编队生成（MiG-29 / F-86 / MiG-23 / F-100 / A-7 / Q-5 / MQ-109 / MQ-110 / F-4E）| `survivor/survivor_spawner.gd:1574` _spawn_squad |
| 指挥 UAV 小队生成（Sentinel + MQ-109 僚机）| `survivor/survivor_spawner.gd:1829` _spawn_commander_squad |
| └ 初始漏编兜底 + 原生护卫 1Hz 持续返航 + 全局 hunter 隔离 | `survivor/survivor_spawner.gd` `_ensure_sentinels_escorted` / `_recall_detached_sentinel_escort` / `_update_hunters`；`ai_controller.gd` `_process_simple` |
| └ 凝聚策略回归（原生护卫召回 / hunter 豁免 / 真实飞行收敛） | `tests/test_spawn_pool.gd` `_test_sentinel_escort_cohesion`；`survivor/survivor_mode.gd` `_bench_force_sentinel_escort_cohesion` / `_bench_update_sentinel_escort_cohesion`；运行 `bench/run.cmd sentinel_escort_cohesion 20 180 Shadow Headless` |
| F-47 BOSS 小队生成（菱形 4 架 + 登场通场） | `survivor_mode.gd` _spawn_f47_squad |
| F-47 BOSS 狙击循环更新（站位/撤退/全灭检测）| `survivor_mode.gd` _update_f47_squad |
| 创建敌机实体（参数/AI/缩放/Token meta）| `survivor/survivor_spawner.gd:2785` _create_enemy |
| └ base_params match（**新增敌人改这里**） | `:1041` |
| └ enemy_scale 适用判定 | `:1075` |
| └ no_stamina 排除 | `:1103` |
| └ type_tag 映射 | `:1108` |
| └ AI 分支（**F86:1183 / MIG31:1195 / MIG23:1208 / F100:1220 / Sentinel:1233**） | `:1157-1244` |
| 无效分队清理 | `survivor/survivor_spawner.gd:4320 _cleanup_squads` |

> **敌人类型与 archetype 映射**（EnemyType enum + 适用 archetype）：
> - `UAV(0)` MQ-109（机炮）/ `UCAV(1)` MQ-110（导弹）— 无人机杂鱼，1 级一起开局，等权重 50/50
> - `F4E(23)` F-4E — 前期导弹杂鱼（有人机，无机炮），Lv1~6 单机/小队（spec enemies/f-4e）
> - `MIG(2)` MiG-29 — 主力威胁，全能 BFM
> - `INTERCEPTOR(3)` J-7 — Lancer 入门款（轻量、单机）
> - `UAV_COMMANDER(4)` Sentinel — Schemer 指挥支援；常规 Schemer 扩展见 `enemy_pool_registry.gd`
> - `F86(5)` F-86 — Gladiator 入门款（机炮+火箭弹编队）
> - `MIG31(6)` MiG-31 — Lancer 顶级（极速 3200 / 雷达弹 / 单机精英）
> - `MIG23(7)` MiG-23 — Gladiator 综合款（导弹+机炮编队）
> - `F100(8)` F-100 — Lancer 中量编队（雷达弹打带跑）
> - `SU27(9)` Su-27 — Gladiator+眼镜蛇（单机精英）
> - `A7(10)` A-7 — Lancer 亚音速攻击机（M61火神炮+祖尼火箭弹编队）
> - `Q5(11)` Q-5 — Lancer 超音速攻击机（23mm双炮+57mm火箭弹编队）
> - `F47(15)` F-47 — BOSS 王牌狙击小队（BVR 协同齐射 / bvr_only + salvo_leader）
> - `YF23(29)` YF-23 — Wraith 首败后专属可选支援（Wraith 后方潜伏、传感器隐形、无永久免锁、接触建立后正常可锁定、BVR 4–6km、固定 2 架，不进随机池）

> Token 常量表：`survivor_data.gd::TOKEN_COST` / `TOKEN_INSTANCE_CAP` / `TOKEN_BUDGET_BASE/PER_LEVEL/MAX` / `FAR_CLEANUP_DISTANCE` / `FAR_CLEANUP_INTERVAL`。设计要点：
> - 每种敌人有 Token 成本（弱 1~3，顶级可到 10）与可选实例上限；新常规池以 `EnemyPoolRegistry.ROWS` 为权威源。
> - 全局 Token 预算随等级线性增长；用来精细控制同屏战斗烈度。
> - `_update_spawner` 每 tick 重算 `_token_used`，基于场景真实状态。
> - `_update_far_cleanup` 定期静默移除离玩家 > FAR_CLEANUP_DISTANCE 的敌机，不给经验（防止养肥刷怪），自然释放 Token。

#### 击杀/经验/升级
| 功能 | 位置 |
|------|------|
| 击杀检测 & 经验奖励 & 回血（×xp_mult×sig×机体 xp_gain_mult）| `survivor/survivor_spawner.gd:4073` _detect_kills |
| 小队共享经验倍率 `2/(N+1)`（单机1.0、3机0.5、9机0.2；击杀者不独占） | `survivor/survivor_data.gd` `squad_xp_multiplier` → `survivor/survivor_spawner.gd` `_apply_squad_xp_share` |
| 每名僚机 +3 Token、抬热度地板；真实等级与热度共同决定响应等级 | `survivor/survivor_data.gd` `squad_token_bonus` / `response_level`；`survivor/roe_director.gd` `heat_floor_for_level` |
| 猎手在直属小队内按当前承压最少、再按最近分配目标 | `survivor/survivor_data.gd` `least_pressure_target_index` → `survivor/survivor_spawner.gd` `_update_hunters` |
| 玩家升级回调（基础斗士/骑士/策士三张；已购机体适配时 15% 普通第四卡）| `survivor/survivor_mode.gd` `_on_player_leveled_up` → `_roll_axis_cards`；普通候选唯一过滤/轴分组 `survivor/survivor_skill_catalog.gd` `normal_candidates` / `candidates_by_axis`；适配权益仍由 `SurvivorData` / `MetaShop` 决定 |
| 升级选中与生效（技能入账 + 普通 +1 轴点）| `survivor/survivor_mode.gd` `_apply_upgrade_choice` / `_on_upgrade_selected` → `survivor/survivor_skill_catalog.gd` 单机/重放投影 → `survivor/survivor_player.gd` `apply_upgrade_to` → `survivor/survivor_skill_effects.gd` `apply`；队级自动状态 `survivor/survivor_skill_runtime.gd` `sync_team_state` |
| 机场留机装备专属技能 / 进化互斥终态 | `survivor/survivor_mode.gd` `_open_evolution_offer` / `_on_settlement_signature` / `_on_settlement_evolution` |
| 玩家死亡 | `survivor/survivor_mode.gd:6070` _on_player_died |

#### 4 级金卡软 pity

| 功能 | 位置 |
|------|------|
| 倍率 `1+3.5m` / 本轮 3～4 张普通卡后清零或累加 / 奖励与机场专属渠道隔离 | `survivor/survivor_data.gd` `CLASSIFIED_PITY_WEIGHT_PER_MISS` / `classified_pity_weight_multiplier` / `classified_pity_next_misses` / `pick_card_for_axis`；`survivor/survivor_mode.gd` `_classified_pity_misses` / `_roll_axis_cards` |

#### 生涯档案（spec career-archive，2026-07-26）
| 功能 | 位置 |
|------|------|
| 档案 AutoLoad（schema/记录 API/成就/写盘） | `meta/career_archive.gd` 全文件 |
| 入档守卫（bench/boss_debug 排除） | `survivor/survivor_mode.gd:7308` archive_enabled |
| 空中击坠入档（归因过滤+enemy_type 键） | `survivor/survivor_spawner.gd:4073` _detect_kills（空中/地面两分支各一处 record 调用） |
| 停机计数 | `survivor/survivor_mode.gd:7165` _on_dock_docked 头部 |
| BOSS 接战/击败入档 | `survivor/survivor_mode.gd:7422` on_boss_engaged / `:7494` on_boss_victory |
| BOSS 轮换 + 通关次数 history 注入 | `survivor/survivor_mode.gd:7397` _update_boss_phase → `events/boss_encounter_event.gd` `_start`（spawn 前注入 `defeat_counts`） |
| 轮换算法（纯函数） | `survivor/boss_registry.gd` `pick_for_map` / `pick_by_rotation` / `rotation_candidates` |
| BOSS 显示名与登场横幅元数据 | `survivor/boss_registry.gd` `name_key_for` / `banner_metadata_for` → `events/boss_encounter_event.gd` `_try_play_arrival_cinematic` |
| 结算面板 BOSS 名（"XX 已被击毁"） | `survivor/boss_registry.gd` `name_key_for` → `survivor/survivor_hud.gd:2189` show_victory（boss_id 空 → 通用文案） |
| 忠诚僚机奖池门控（构造时注入；缺键 fail-closed） | `survivor/zone_data.gd:861 _assign_reward`（武器子池过滤）+ `survivor/survivor_mode.gd:7294 _build_reward_roll_context`；回归 `tests/test_zone_rewards.gd:189 _test_achievement_reward_gate` |
| 成就 toast | `survivor/survivor_mode.gd:7313 _on_achievement_unlocked` |
| 删存档登记 | `main_menu.gd:366` _on_reset_save_pressed 内 CareerArchive.debug_reset |

#### 生涯商店、专属许可与起手解锁（spec career-shop + aircraft-signature-progression + airfield-sam-network）
| 功能 | 位置 |
|------|------|
| 商店账本（学说/基础商品/AWACS/四项战斗支援/41 专属许可） | `meta/meta_shop.gd:345 is_awacs_entitled`；`meta/meta_shop.gd:349 is_zone_air_support_entitled`；`meta/meta_shop.gd:352 is_zone_ground_support_entitled`；`meta/meta_shop.gd:356 is_ace_f15_support_entitled`；`meta/meta_shop.gd:360 is_airfield_sam_entitled` |
| 商店四分页 + 专属已知/??? 双密度界面 | `meta/meta_shop_ui.gd:77` _add_page / `:130` _build_signature_page；共享 CRT 白色终端页，场景 `scenes/meta_shop.tscn` |
| AWACS 正式局权益消费点 | `survivor/survivor_mode.gd:6764 _update_ally_events` |
| 起手机门控 | `survivor/survivor_select.gd` `_effective_list` / `_unlock_hint_for`（正常八卡：既有四架沿用原门控，新增四架读取局外采购；Boss Debug 改读 T4 参考节点） |
| 停靠送僚机门控 + 首停上新 toast | `survivor/survivor_mode.gd:7165` _on_dock_docked 内 |
| 战区时长 +30s 注入 | `survivor/survivor_mode.gd` _ready 内（WARZONE_PHASE_DURATION 已 const→var） |

#### 噪声/绘制
| 功能 | 位置 |
|------|------|
| 地形噪声初始化 | `terrain_renderer.gd:61` _init_noise |
| 主 _draw 入口 | `terrain_renderer.gd:76` _draw |
| 地形类型判定 | `terrain_renderer.gd:83` _get_terrain_type |
| 地形单元绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 网格绘制 | `terrain_renderer.gd:162` _draw_grid |

### survivor_tutorial.gd — 首次存档与僚机操作教程

| 功能 | 位置 |
|------|------|
| 新存档基础教程（E 加力 / 双击突击 / 三架教学轰炸机结算） | `survivor/survivor_tutorial.gd`；输入接线 `survivor/survivor_mode.gd` `_unhandled_input` / `_execute_left_click` |
| 首次僚机数字键教程（固定号机提示 / 成功切控后永久消失） | `survivor/survivor_wingman_tutorial.gd`；触发与完成 `survivor/survivor_mode.gd` `_maybe_start_wingman_switch_tutorial` / `_first_switchable_wingman_slot` / `_switch_control_to_slot` |

### pause_menu.gd — 暂停菜单（spec pause-menu，2026-07-28）

| 功能 | 位置 |
|------|------|
| ESC 分流（开面板 / 结算态直退 / 选卡中不响应） | `survivor/survivor_mode.gd:3577` _unhandled_input |
| 创建 + 接线（bench 跳过） | `survivor/survivor_mode.gd:496` |
| 确认退出回调（不结算功勋） | `survivor/survivor_mode.gd:6087` _on_pause_quit_to_menu |
| 退出序列（clear_all + stop_music + 切场景） | `survivor/survivor_mode.gd:6094` _quit_to_main_menu |
| 打开（hard_pause 走 panel_in） | `survivor/pause_menu.gd:54` open |
| 关闭＝继续作战（解暂停走 panel_out） | `survivor/pause_menu.gd:56` close |
| 面板构建 | `survivor/pause_menu.gd:75` _build_ui |
| 按钮回调 | `survivor/pause_menu.gd:153` _on_resume_pressed / `:157` _on_quit_pressed |

### survivor_player.gd — 玩家状态（127 行）

| 功能 | 位置 |
|------|------|
| 信号 leveled_up | `survivor_player.gd:7` |
| 经验累加/升级触发 | `survivor/survivor_player.gd:43` add_xp |
| 应用升级公开入口 | `survivor/survivor_player.gd` `apply_upgrade` / `apply_upgrade_to`（显式目标、当前操控机引用稳定） |
| 静态技能效果（机体属性 / 武器资源 / 运行时字段 / 玩家倍率） | `survivor/survivor_skill_effects.gd` `apply` |
| 随机池 / 归属有效层数 / 晚入队与换型重放计划 | `survivor/survivor_skill_catalog.gd` 全模块 |
| 队级自动技能状态同步与新局清零 | `survivor/survivor_skill_runtime.gd` `sync_team_state` / `reset_team_state` |
| HP 查询 | `survivor/survivor_player.gd:441 get_hp` |

### survivor_data.gd — 参数表（322 行）

| 功能 | 位置 |
|------|------|
| 升级定义表 UPGRADES（常量）| `survivor_data.gd:12` |
| 刷怪基础常量（BASE/MIN/SPAWN_DISTANCE，旅途位置已弃用）| `survivor_data.gd` 刷怪参数段 |
| 增援入场常量（INGRESS_*/ANCHOR_*/PATROL_RING_*/EGRESS_*/OPENING_GARRISON，spec reinforcement-ingress）| `survivor_data.gd` SPAWN_DISTANCE 之后 |
| 增援入场逻辑（边缘生成/锚点驻空/EGRESS/开局驻防 + 冻结豁免）| `survivor_spawner.gd` INGRESS 段 + `survivor_mode.gd` LOD 冻结块 reinforcement 分支 |
| 地图扩展无头回归（几何/陆地占比/BOSS 锚点/入场纯函数）| `scripts/tests/test_map_expansion.gd` |
| 三图外缘空域 SSOT（60km 核心入口 / 64km 真边界 / 2.5s 倒计时 / 32px 相机内容内收 / AI 300px 转弯带） | `scripts/survivor/map_boundary.gd` `CORE_HALF_PX` `WORLD_HALF_PX` `EXIT_COUNTDOWN_S` `CAMERA_CONTENT_INSET_PX` `AI_EDGE_TURN_MARGIN_PX` / `_process`；UI 消费 `scripts/survivor/boundary_ui.gd` `on_countdown` `on_crossed` |
| └ 普通敌机与飞机 BOSS 边界纪律 | `scripts/survivor/survivor_spawner.gd` `_update_boundary_discipline` `enforce_boss_world_boundary`；`scripts/survivor/ace_squad.gd` `_update_boundary_recovery`；fear/joust 消费同一真边界与 AI 余量 |
| └ 三图覆盖 / AI / 倒计时回归与最远缩放角落 Visual | `scripts/tests/test_map_boundary.gd`（`--bench=map_boundary`，20 项）+ `bench/bench_runner.gd` `PREVIEW_BENCH_MAPS` + `survivor/survivor_mode.gd` `MAP_PREVIEW_BENCH_SCENARIOS`；Visual keys `map_boundary_crop_tokyo/desert/ocean` |
| 官方底图失败可见报错（控制台 error + 底部红色临时通知 + 旧矢量兜底）| `scripts/survivor/map_feature_renderer.gd` `_report_basemap_error` → `scripts/survivor/survivor_mode.gd` `_on_basemap_load_failed` → `scripts/survivor/zone_hint.gd` `show_error_temp`；契约回归在 `scripts/tests/test_map_expansion.gd` |
| 60km 密度调优旋钮（战区规模/token/间隔/上限/hunter 配额，spec 60km-density-pass）| `survivor_data.gd`（ground_tgt_scale 含 radar_count / ZONE_DEFENDER_* / TOKEN_BUDGET_*）+ `survivor_spawner.gd` _update_hunters + `zone_data.gd` 半径 |
| 战区雷达站 TGT + 空战中队长机高一档 + 盘旋环随半径缩放 | `zone_mission.gd`（_RADAR_SCENE / _spawn_ground_garrison 尾段 / _spawn_air_squadron leader_etype·orbit_r）；驻守 garrison_r 在 `survivor/zone_spawn_job.gd` `_step_defenders` |
| 战区目标镜头预加载 | `survivor/zone_mission.gd` `prepare_visible_zones` / `_zone_overlaps_view` / `_ensure_spawned_for_active_zones` / `_zone_supports_ground` / `_build_spawn_road_index` / `_index_spawn_road_path`；`survivor/survivor_mode.gd` `_process` 镜头更新后接入；`tests/zone_observation_visual.gd` 首帧真实地面工厂与返回身份 |
| 战区首刷分帧（触发帧只生成任务主分支；驻守机逐架 / 3★ / 气氛层与 SPG 阵位搜索按每渲染帧 2.5ms、4 单位预算续段；续段完成前不判攻克；撤销/失败/重置/Debug 重刷先落账已生成驻守；Debug 入口即刻跑完） | `survivor/zone_mission.gd` `_spawn_zone_units` / `_advance_spawn_jobs` / `_finish_spawn_job` / `_cancel_spawn_job` / `_on_spawn_job_finished` / `debug_force_respawn_zone`；`survivor/zone_spawn_job.gd` `run_piece` / `commit_partial`；`survivor/zone_atmosphere_combat.gd` `advance_pending` / `_step_artillery_job` / `ArtilleryPlanSearch`；实测 `tests/zone_spawn_burst_runner.gd`（bench `zone_spawn_burst`），等价 `tests/test_zone_atmosphere_combat.gd` `_test_artillery_search_matches_legacy` / `_test_deferred_artillery_registration` |
| 战区临时支援（已购授权后：每局首次 `air/squadron` 派 2/3/4 架 F-86、首次 `ground` 派 2 架 A-10；两项额度分账；ALLY、短标签、战区 leash、统一物理撤离） | `survivor/zone_mission.gd:1909 _start_air_support_if_needed` / `survivor/zone_mission.gd:2005 _try_spawn_air_support` / `survivor/zone_mission.gd:2078 _create_a10_support` / `survivor/zone_mission.gd:2148 _begin_air_support_egress` / `ai_controller.gd:1010 acquire_target` 的 `air_targets_only` + `ground_targets_only` 门；测试 `tests/test_zone_air_support.gd:53 run` |
| 王牌截击支援（已购授权后：每局首次非 BOSS 王牌轮换派 Hound-1/2 两架 F-15；友军实例雷达 3000m、固定双句无线电，只对空并优先本事件王牌；事件终态物理撤离） | `events/ace_reinforcement_event.gd:190 _spawn_ally_support` / `events/ace_reinforcement_event.gd:308 _maintain_ally_support_targets` / `events/ace_reinforcement_event.gd:352 _begin_ally_support_egress` / `events/ace_reinforcement_event.gd:381 _tick_ally_support_egress`；测试 `tests/test_zone_air_support.gd:53 run` |
| └ 第三方 ALLY 击杀收益隔离（任务销毁照常；不给玩家 XP/击杀数/回血/连击/教程进度） | `survivor/survivor_spawner.gd:4073 _detect_kills` 的 `third_party_kill` |
| └ 双支援最坏压力样本 | `survivor/survivor_mode.gd` `_bench_force_zone_support`（`--bench=zone_support_stress`：Lv15 + 31 敌 + Sentinel 完整机群 + F-86×4 + A-10×2） |
| └ 对舰最坏压力样本 | `survivor/survivor_mode.gd:2508 _bench_force_naval_zone`（`--bench=naval_zone_stress`：39 架飞机 + 3★ 六舰 + 18 挂点代理，持续覆盖 VLS/CIWS/Flak） |
| └ 王牌截击压力样本 | `survivor/survivor_mode.gd:7609 _bench_force_ace_support`（`--bench=ace_support_stress`：Lv15 + 31 敌 + Sentinel 完整机群 + MARATHON×5 + F-15×2） |
| **战场流程聚合根**（净时间轴、战区关闭事务、王牌固定槽/无放回、ORION 门） | `survivor/battlefield_flow.gd` `BattlefieldFlow`：`advance_time` / `apply_time_cost` / `grant_time_extension` / `close_warzone_if_due` / `claim_next_ace_profile` / `claim_orion_if_due`；场景执行仍由 `survivor/survivor_mode.gd` |
| **BOSS 阶段闸门真源**（flow phase ∪ boss_unlocked ∪ selected==BOSS ∪ 已 spawn；子系统一律问 Mode，别直读 ZoneData）| `survivor/battlefield_flow.gd` `is_boss_phase` → `survivor/survivor_mode.gd` `is_boss_phase` / `_is_in_boss_phase` |
| └ 消费点（停摆刷怪/猎手/驻防 · 停随机奖励事件 · 停战区任务 · AWACS 提前撤离）| `survivor_spawner.gd` _is_boss_phase · `survivor/adbs_manager.gd` _physics_process 闸 · `zone_mission.gd` _is_boss_phase · `events/awacs_support_event.gd` _update 顶部 |
| └ BOSS 阶段全场撤离（画内画外均清目标+出界航线+AB，真正飞远后分批释放；舰船地面单位一概不动）| `survivor_spawner.gd` _update_boss_phase_purge / _begin_boss_evacuation（豁免 boss* / ace_support / ace_nemesis / parent_carrier）+ _update_boundary_discipline 的 boss_evac 豁免 |
| └ 无头回归 | `scripts/tests/test_battlefield_flow.gd`（bench `battlefield_flow`，31 断言）+ `scripts/tests/test_boss_phase.gd`（bench `boss_phase`，33 断言）|
| **BOSS 阶段 XP 总闸**（`is_boss_phase()` 从解锁/PRE_STAGE 起生效；空中+地面击杀 XP=0，仍保留击杀数/回血/连击）| `survivor_spawner.gd` `_detect_kills` 的 `boss_phase_no_xp` |
| **击杀不计价开关** `no_kill_reward` meta（全阶段无 XP / 不入生涯档案 / 不给对头永久 +max_hp；仍计击杀数与击杀回血）| 消费点 `survivor_spawner.gd` _detect_kills；打标处 `mother_goose_uav_swarm.gd` _spawn_uav + `mother_goose_boss.gd` _make_mqx + `carrier_strike_group.gd` _launch_fa18 |
| └ CSG 机库累计上限（整场 8 架，击落不退还名额）| `survivor/carrier_strike_group.gd` FA18_TOTAL_CAP / _fa18_launched_total（守卫点在 _launch_fa18 开头 + _update_fa18_periodic_launch）|
| 教程轰炸机锚点（出生点前方派生，扩图安全）| `survivor/adbs_manager.gd` TUTORIAL_BOMBER_ANCHOR |
| 城区直升机调度与探索生成（每窗 25%、整局 ≤2、活跃组互斥；距玩家 ≥12km、距边界 ≥8km 的全图城区）| `survivor/adbs_manager.gd` `city_heli_schedule_allows` / `city_heli_spawn_candidate_allowed` / `_pick_city_center`（`_city_centroids` 质心缓存 + `_active_zone_circles` / `_pos_in_zone_circles` 战区快照）；测试 `tests/test_bomber_rotor_airburst.gd` `_test_city_heli_schedule` |
| 城区直升机全歼奖励（作战时间延长，与王牌中队全灭同一注入点 `grant_time_extension`）| `survivor/adbs_manager.gd:307` _award_city_heli_bonus |
| └ 战果轮询（与 _detect_kills 同模式；逃出地图被回收不算不阻塞）| `survivor/adbs_manager.gd:287` _track_city_heli_kills |
| └ 编队/击落计数状态 | `survivor/adbs_manager.gd:55` _city_heli_group / `survivor/adbs_manager.gd:56` _city_heli_killed |
| └ 奖励时长常量 | `survivor/adbs_manager.gd:44` CITY_HELI_TIME_BONUS_S |
| CH-47 受击散开（scatter_on_damage meta + flock_members 串联）| `survivor/survivor_spawner.gd:2618` spawn_heli_flee |
| 停靠结算（spec zone-reward-docking：DockPoint 组件/攻克全队满血+奖励入库/领奖分发）| `survivor/dock_point.gd` + `survivor_mode.gd`（_on_dock_docked / _claim_*）|
| 机场解放战区（海岸线默认 3 机场；其它地图按稳定 id 覆盖本局名称/坐标；敌占→解放→一次性补给点；友军基础 AA×2，授权追加 SAM×1；难度=热度）| `survivor/zone_data.gd`（AIRFIELD_IDS / apply_map_zone_overrides / get_zone_definitions / is_airfield / liberate_airfield / set_airfield_difficulty）+ `survivor_mode.gd`（MapDocument.zones 注入 / _liberate_airfield）+ `zone_mission.gd`（_spawn_airfield_ground / _airfield_difficulty_from_heat）+ `resources/maps/desert_railway_preview.aglmap`（Pilbara 三机场 SSOT）+ `meta/meta_shop.gd`（is_airfield_sam_entitled）|
| 战区四类奖励 roll（航母/僚机/武器/次世代技能；A/B 每局保底各一武器一技能；航母 pity）| `survivor/zone_data.gd` RUN_GUARANTEED_REWARD_KINDS / REWARD_KIND_WEIGHTS / _assign_reward |
| F6 全战区奖励直发（15 项；绕过 roll/正式门控，技能仍守 max_stacks） | `survivor/survivor_debug_zone.gd` `DEBUG_REWARD_OPTIONS` / `_on_grant_reward` → `survivor_mode.gd` `debug_grant_zone_reward`；`skill_audit` 自动与正式数据源对拍 |
| 新地图云层 / 沙漠沙尘暴（spec weather-clouds-and-sandstorm） | `weather_system.gd` `setup(camera, deterministic_seed)` / `sandstorm_speed_kmh` / `sandstorm_progress` / `sandstorm_center_world` / `set_debug_midgame` / `sample_density` / `sample_sandstorm_density` / `sample_obscurant_density` / `_draw_sandstorm` / `_sandstorm_edge_wave` / `_draw_sandstorm_fill` / `_draw_sandstorm_streamlines` / `_draw_sandstorm_observations` / `_draw_sandstorm_front`（正式随机天气；地图 Visual bench 固定云形；官方沙漠 180km/h、10km 宽；气象图式矢量纹样、曲边 Alpha 羽化，不复用云贴图）；`ugc/map_document.gd` cloud schema；`resources/maps/*_preview.aglmap`；`aircraft.gd` `_update_cloud_state`（focused bench 注入同一 WeatherSystem 验真实对象状态）；`survivor_mode.gd` `_cached_is_in_cloud` / `debug_skip_to_midgame`；`missile.gd` 云中累计失导；`missile_manager.gd` `get_in_cloud` / 命中 miss；`survivor_debug_zone.gd` `_on_skip_midgame`；bench `weather` / `map_raster_tokyo` / `map_raster_desert` / `map_raster_ocean` |
| 战区奖励说明文案（Tab 面板奖励名下方一行；技能类=技能介绍）| `survivor/zone_data.gd` REWARD_WEAPON_DESC_KEYS / reward_desc_key + `tactical_map.gd` _refresh_info（reward_desc）+ i18n `REWARD_*_DESC` |
| 友军航母（南入北上/甲板 DockPoint/限 2 次/友军专属 300 hull/击沉清零；敌方 CV 资源仍 1200）| `survivor_mode.gd:6861 _summon_reward_carrier` / `survivor_mode.gd:6935 _depart_friendly_carrier` |
| 玩家触发的友军设施区域仇恨（机场 2000px/航母 2500px 激活；1 Hz；H→Q 限额；8s 退出；`SCORED < BOSS < ASSET < DIRECTIVE < COMMANDED`）| `survivor/friendly_asset_aggro.gd:76 tick` + `ai_controller.gd:998 TargetSource` / `ai_controller.gd:1003 get_target_source` / `ai_controller.gd:1010 acquire_target` + `combat_unit.gd:74 META_FRIENDLY_ASSET_GROUP` + `naval/mount_target.gd:38 _ready`；测试 `test_friendly_asset_aggro.gd:10 run` |
| 逃跑组护卫编队（adds 语义、普通 XP；独立零 Token 选型；运输机作移动长机、WEDGE 220m、首机阵亡换锚）| `survivor/survivor_spawner.gd` `_pick_flee_escort_type` / `_new_flee_escort_squad` / `_spawn_flee_escort` |
| Tab 停靠/奖励标记 | `survivor/tactical_map.gd` _draw_dock_markers + _draw_one_zone 奖励行 |
| 敌机上限常量（HARD/DEFAULT/MIN/TARGET_FPS）| `survivor_data.gd:215-218` |
| MiG 解锁/概率常量 | `survivor_data.gd:220-222` |
| 截击机 J-7 解锁/概率常量 | `survivor_data.gd:223-225` |
| F-86 解锁/概率常量 | `survivor_data.gd:226-228` |
| MiG-23 解锁/概率常量 | `survivor_data.gd:229-231` |
| F-100 解锁/概率常量 | `survivor_data.gd:232-234` |
| MiG-31 解锁/概率常量 | `survivor_data.gd:235-237` |
| Su-27 解锁/概率常量 | `survivor_data.gd:238-240` |
| A-7 解锁/概率常量 | `survivor_data.gd:241-243` |
| Q-5 解锁/概率常量 | `survivor_data.gd:244-246` |
| 指挥 UAV 解锁/概率/小队规模 | `survivor_data.gd:247-254` |
| **Token 预算常量** (BASE/PER_LEVEL/MAX) | `survivor_data.gd:254-256` |
| **Token 消耗表 TOKEN_COST** | `survivor_data.gd:261` |
| **Token 实例上限表 TOKEN_INSTANCE_CAP** | `survivor_data.gd:276` |
| **远距清理常量** (DISTANCE/INTERVAL) | `survivor_data.gd:289-290` |
| **后期分水岭 LATE_GAME_LEVEL** | `survivor_data.gd:296` |
| MiG/截击机缩放 enemy_scale_for_level | `survivor_data.gd` enemy_scale_for_level |
| UAV 缩放 uav_scale_for_level | `survivor_data.gd` uav_scale_for_level |
| 指挥机缩放 commander_scale_for_level | `survivor_data.gd` commander_scale_for_level |

### commander_aura.gd — 指挥 UAV 光环

**设计要点**：
- 招募范围内的 UAV 加入小队（上限 MAX_WINGMEN=5 僚机）
- 可从**其它普通 UAV 编队中"挖人"**（检查 `ai.orbit_squad_leader` 排除其它指挥小队）
- 小队成员保持 `simple_ai=true`，通过 `orbit_squad_leader` 围绕 Sentinel 飞行
- **不再指派目标**（无 _designate_target）；僚机通过 `_try_engage_simple` 自主扫描并攻击靠近的敌方
- buff 聚焦机动/速度/攻击欲望（不加技能/冷静，simple_ai 用不上）
- buff 强度：+6G、结构 +7G、滚转 ×2.5、速度 ×1.5、加速 ×3、失速 ×0.5；只写 Aircraft 运行时字段，不改 params
- 每 0.5s 全量重算“当前小队成员 ∧ 半径内”，单 owner 仲裁；离队、越界和节点退出均撤除

| 功能 | 位置 |
|------|------|
| 主循环（扫描+招募+buff） | `survivor/commander_aura.gd:44` _physics_process |
| 增益扫描（全量重算小队∧半径） | `survivor/commander_aura.gd` _scan_and_buff |
| 应用 buff（运行时 G/结构/滚转/速度/加速/失速字段）| `survivor/commander_aura.gd` _apply_buff |
| 移除单个 / 全部 buff | `survivor/commander_aura.gd` _remove_buff / _remove_all_buffs |
| 招募新成员（允许从普通编队挖人）| `survivor/commander_aura.gd` _try_recruit |
| 析构时清理 | `survivor/commander_aura.gd` _exit_tree |
| 查找 AI 控制器 | `survivor/commander_aura.gd` _find_ai |

### commander_overlay.gd — 指挥机视觉覆盖（~80 行）

| 功能 | 位置 |
|------|------|
| 颜色常量 | `commander_overlay.gd:10-13` |
| 坠落淡出时长常量 | `commander_overlay.gd:15` DESTROY_FADE_DURATION |
| 绘制（坠落时按 _destroy_timer 淡出） | `commander_overlay.gd:27` _draw |

### survivor_hud.gd — HUD

| 功能 | 位置 |
|------|------|
| UI 构建 | `survivor/survivor_hud.gd` `_build_ui` |
| 主循环与分层刷新 | `survivor/survivor_hud.gd` `_process` / `HUD_DATA_REFRESH_INTERVAL` / `_update_hud_data_layer` |
| 玩家 HUD 框板本局首次两闪 | `ui/hud_first_reveal_sequencer.gd` `register_panel` / `register_callback_panel` / `set_panel_available` / `set_panel_sort_position` / `update`；`ui/hud_board_visibility.gd` + `resources/shaders/hud_board_visibility.gdshader` 直接切换复合控件源框板；`survivor/survivor_hud.gd` `_setup_hud_first_reveal` / `_sync_hud_first_reveal_targets` |
| UI 自适应布局（viewport 未变时不重复写静态底栏/顶部几何） | `survivor/survivor_hud.gd` `_static_layout_viewport` / `_layout_ui` |
| 右键急刹虚拟摇杆（按下减速 / 实际左右舵量 / 即时速度 / 明确标名的剩余与最大机炮弹药或 `∞` / 有效射程 / 失速锁定 / 边缘夹紧） | `survivor/brake_steering_overlay.gd` `begin` / `update_steer` / `set_stall_locked` / `set_flight_data` / `_draw` → `survivor/survivor_hud.gd` `begin_brake_steering` / `update_brake_steering` / `set_brake_steering_stall_locked` / `set_brake_steering_flight_data` / `end_brake_steering`；focused `brake_steering_ui`，Visual `brake_steering_overlay_visual` |
| 顶部粗体 `1u` 当前时间与框版战区剩余时间 | `survivor/survivor_hud.gd` `top_time_rect` / `warzone_time_rect` / `formatted_elapsed_time` / `_layout_ui`；`survivor/warzone_time_panel.gd` `formatted_remaining_time` / `grid_regions` / `_draw` |
| 全屏底部 `3u` 常驻框板与等宽侧板、三方向、剩余经验与进化就绪内部布局 | `survivor/survivor_hud.gd` `BOTTOM_BAR_HEIGHT` / `bottom_bar_rect` / `bottom_progress_rect` / `bottom_axis_rect` / `bottom_xp_rect` / `_layout_ui` / `_update_display` |
| 顶部常驻紧急通知 + 底部临时提示双滑入通道 | `survivor/zone_hint.gd` `TOP_RESERVED_HEIGHT` / `show_persistent` / `hide_persistent` / `show_temp` / `show_error_temp` / `_slide_top` / `_slide_bottom`；精英入场路由在 `events/ace_reinforcement_event.gd` |
| HP/XP/等级、状态行与三方向计数更新 | `survivor/survivor_hud.gd` `_update_display` / `_update_player_instrument` |
| 玩家 HUD 安全引用与刷新 | `survivor/survivor_hud.gd` `_safe_player_aircraft` / `_update_player_instrument` |
| 玩家模块化仪表（右锚；高度针独立重绘层；HP 上方等宽云层/击杀状态，HP/SPD 各带 0.5u 装饰行，武器装填百分比/秒数/底条） | `survivor/player_instrument_panel.gd` `AltimeterNeedleLayer` / `_draw_altimeter_needle` / `_configure_layout` / `update_status` / `cloud_status_rect` / `kill_status_rect` / `hp_decorative_rect` / `spd_decorative_rect` / `weapon_reload_percent_rect` / `weapon_reload_remaining_rect` / `weapon_reload_progress_rect` / `weapon_reload_remaining_seconds` / `weapon_name_rect` / `_draw` |
| 僚机动态行仪表 | `survivor/wingman_instrument_panel.gd` `update_display` / `_draw_row` |
| 底部三个等宽 `2u` 三方向板、`当前/8` 数字与常显 `0.5q` 点击格 | `survivor/milestone_axis_counter.gd` `update_display` / `axis_title_rect` / `axis_value_rect` / `point_rect` / `grid_regions` / `_draw` |
| 底部等级、距下一级 XP 与真实进化就绪格；升级逐板反色 | `survivor/bottom_experience_panel.gd` `update_display` / `xp_remaining` / `evolution_ready_rect` / `flash_level_up` / `flash_index_at` / `grid_regions` / `_draw`；资格入口 `survivor/survivor_mode.gd` `has_ready_aircraft_evolution`；刷新入口 `survivor/survivor_hud.gd` `_update_display` / `show_level_up` |
| 统一共享 1 物理像素网格描边（相等 setter 早退；重合边去重并合为 multiline；HUD 缩放使用 scale-invariant hairline；物理视口边缘半像素内收防裁切） | `ui/terminal_grid_overlay.gd` `TerminalGridOverlay` / `SCALE_INVARIANT_LINE_WIDTH` / `regions` / `override_regions` / `edge_insets` / `outline_segments_for` / `edge_safe_region` / `_draw` |
| 终端文字精确排版、高度优先步进扩宽与轮廓缓存 | `ui/terminal_text.gd` `TerminalText` / `FontFace` / `SizeRule` / `MAX_INK_BOUNDS_CACHE_ENTRIES` / `MAX_GLYPH_BOUNDS_CACHE_ENTRIES` / `resolve_font_layout` / `font_size_for_ink_height` / `expanded_width_for_fixed_text` / `measure_ink_bounds` / `_glyph_ink_bounds`；最终 RID/字号/glyph 复用轮廓；`survivor/player_instrument_panel.gd` `_configure_layout` 预热真实 MSDF 数字与装填符号 |
| 排版求解与单行宽度缓存（同字体/文本/精确区域只试探一次；先比宽度再测轮廓，逐值同原算法）、计时面板逐格布局查表 | `ui/terminal_text.gd` `resolve_font_layout` / `_resolve_font_layout_uncached` / `_layout_fits_size` / `cached_string_width` / `reset_measure_caches`；`survivor/warzone_time_panel.gd` `_cached_text_layout` |
| F7 实际 HUD 几何定位覆盖层与手动 FLR 插键测试 | `survivor/survivor_hud.gd` `toggle_ui_dev_overlay` / `_collect_ui_dev_regions` / `_on_ui_dev_add_manual_flare_pressed`；`ui/ui_dev_outline_overlay.gd` `UiDevOutlineOverlay` / `build_entries`；截图场景 `scenes/tests/ui_dev_panel.tscn` |
| E/G/F/Q/T 键、高度两态与缺失武器跳过 | `survivor/survivor_mode.gd` `_unhandled_input` / `_cycle_player_altitude_preference` / `_cycle_player_weapon_preference` |
| 战术按钮创建、tooltip 与状态刷新 | `survivor/survivor_hud.gd` `_create_tac_button` / `_on_tac_hover` / `_update_tactical_buttons` |
| 王牌中队交战血条（分段命条） | `survivor/ace_battle_bar.gd` `set_info` → `survivor/survivor_hud.gd` `_build_ace_panel/_update_ace_panel` |
| The Crucible 多王牌中队条（最多三条 / 仅已入场存活成员 / 击杀事件即时移除） | 与普通地图精确共用 `survivor/ace_battle_bar.gd` `set_info` → `survivor/survivor_hud.gd` `_set_crucible_ace_entries/_update_boss_panel/_on_kill_recorded` |
| F3 详细性能面板开关与 4 Hz 文字更新 | `survivor/survivor_hud.gd` `set_performance_panel_visible` / `_update_debug_panel`；统计源见动态性能节 |
| Game Over / 通关结算画面 | `survivor/survivor_hud.gd` `show_game_over` / `show_victory`；固定尺寸白色终端板、高层压暗遮罩，失败仅保留红色危险标题 |

### 小队信息行与键盘指挥（启动条件 = 有僚机入队，与机型无关）

| 关注点 | 位置 |
|------|------|
| 旧按钮节点构建（兼容保留、固定隐藏） | `survivor/survivor_hud.gd` _build_squad_panel |
| 僚机值快照 + 信息行显隐刷新（僚机非空才显示） | `survivor/survivor_hud.gd` _update_squad_panel |
| 独立行绘制、固定号机排序与 20Hz 刷新 | `survivor/wingman_instrument_panel.gd` update_display / _draw_row |
| C/V 键盘指挥入口 | `survivor/survivor_mode.gd` _unhandled_input → `survivor/survivor_hud.gd` _on_squad_engage_pressed / _on_squad_weapon_pressed |
| 玩家队反查（扫 `_spawner.get_squads()` 找 leader==玩家）| `survivor/survivor_hud.gd` `_get_player_squad` |
| 存活僚机列表 | `survivor/survivor_hud.gd` `_get_wingmen` |
| **玩家队装配 + 登记进 spawner 队表**（唯一入口，幂等）| `survivor/survivor_mode.gd` `_ensure_player_squad` |
| 起手僚机（`wingman_count>0`，仅 F-14 走）| `survivor/survivor_mode.gd` `_spawn_starting_wingmen` |
| T0 起手机机场等价礼包（MiG-21 机炮吊舱 / F-104C FFAR / J 35F QAAM / EA-6B ESM） | `playable_aircraft.gd` `starting_benefit_id` → 选机说明 `survivor/survivor_select.gd` `STARTING_BENEFIT_NAME_KEYS` / `_build_aircraft_card` → 授予 `survivor/survivor_mode.gd` `_grant_starting_benefit` / `_claim_weapon_reward` → 继承 `survivor/survivor_player.gd` `record_special_weapons` / `remount_weapons`；回归 `tests/test_player_params.gd` / `tests/test_zone_rewards.gd` / `tests/ui_iteration_visual_qa_runner.gd` |
| 懒建队消费方：+1 僚机奖励 / 停靠送僚机 / 双子星克隆 | `survivor/survivor_mode.gd` `_claim_wingman_reward` |
| 固定数字键查询与操控角色权限转移（`squad_slot` 不随换帅变化；`use_tactical_preference` 随当前操控机转移） | `survivor/survivor_mode.gd` _aircraft_for_squad_slot / _switch_control_to_slot / `_set_player_aircraft` |
| 回归测试（bench squad_cmd_ui，28 断言：登记/幂等/HUD 反查/固定号机/长机阵亡解绑竞态/操控角色权限）| `tests/test_squad_command_ui.gd` run |

### survivor_upgrade_ui.gd — 升级选择界面（最多四卡）

| 功能 | 位置 |
|------|------|
| 信号 upgrade_selected | `survivor/survivor_upgrade_ui.gd` `upgrade_selected` |
| UI 构建（4 列预建；3/4 卡统一 `240×300`）| `survivor/survivor_upgrade_ui.gd` `_build_ui` |
| 填充介质标签（技能/稀有度/三轴/限定；浅色软盘稀有度章为 11px 亮字 + 实体深底；高档光盘与 shader 强度）| `survivor/survivor_upgrade_ui.gd` `populate` |
| Loading 字形预热批次（同一套卡片控件填文本，不调度输入解锁） | `survivor/survivor_upgrade_ui.gd` `prewarm_render_batch` / `_fill_cards` |
| 填卡主题覆盖降本（每张卡多项徽章覆盖 `begin/end_bulk_theme_override` 一次提交；未变字色/边框跳过，最终值不变） | `survivor/survivor_upgrade_ui.gd` `_fill_cards` / `_set_font_color` |
| 低档软盘 / 高档光盘实体几何（只按状态重绘；软盘底部无圆形轴孔）| `survivor/upgrade_media_surface.gd` `configure` `_draw_floppy_media` `_draw_optical_media` |
| 明确代价句危险红 + hover/focus 词条独立旁注（卡组右侧、空间不足切左，不覆盖卡面） | `survivor/survivor_upgrade_ui.gd` `_description_bbcode` `_set_note_revealed` `_note_popup_position` |
| 出入场元素表（标题 + 可见卡列）| `survivor/survivor_upgrade_ui.gd` `get_transition_elements` |
| 全卡读写扫描 / CLASSIFIED 闪边 / `0.80s` 入场输入保护 / 卡带保持不透明并垂直压缩写入 `0.055s` → 卡列退场 `0.04s`（无连线、脉冲、横移与透明拖尾） | `survivor/survivor_upgrade_ui.gd` `_schedule_input_unlock` `_unlock_choice_input` `schedule_entry_flashes` `_play_media_boot` `_play_border_flash` `_on_choice_pressed`；`resources/presentation/sequences.json` `upgrade_out` |
| └ UI 回归与真实画面 | `tests/test_status_notes.gd`（bench `status_notes`，50 断言）/ `tests/upgrade_media_visual_qa_runner.gd`（Visual bench `upgrade_media_visual`，正式经验/三轴条 + 基础三卡/机体适配第四卡来源条/浅色稀有度章/无重叠旁注/扫描/输入锁） |

### 技能归属分流（spec skills-720-rework T1）

| 功能 | 位置 |
|------|------|
| 归属字段文档（scope/classes/milestone_plus） | `survivor/survivor_data.gd:79` 附近 UPGRADES 头注释 |
| scope 查询 | `survivor/survivor_data.gd:2503` upgrade_scope |
| 品类数组查询 | `survivor/survivor_data.gd:2568` upgrade_classes |
| "+1 轴进度"目标轴查询 | `survivor/survivor_data.gd:2575` milestone_plus_of |
| 王牌字段型 stat 白名单 | `survivor/survivor_data.gd:2597` ACE_FIELD_STATS |
| 归属生效纯谓词 | `survivor/survivor_data.gd:2611` upgrade_applies_to_machine |
| 品类身份映射表 | `survivor/evolution_system.gd:81` CLASS_IDENTITY_BY_CATEGORY |
| 档案 → 品类身份 | `survivor/evolution_system.gd:95` class_identity_of_profile |
| 定向应用（借指针走同 match） | `survivor/survivor_player.gd:387` apply_upgrade_to |
| 王牌剥离（切控迁移逆操作） | `survivor/survivor_player.gd:394` strip_upgrade_from |
| "+1 轴进度"加成（cap=2） | `survivor/survivor_player.gd:148` add_milestone_bonus |
| 里程碑进度=点+加成 | `survivor/survivor_player.gd:162` get_milestone_progress |
| 队存活成员枚举 | `survivor/survivor_mode.gd:5682` _squad_members_alive |
| 单机品类身份（meta profile_id） | `survivor/survivor_mode.gd:5695` _class_identity_of |
| 队品类并集（卡池门控） | `survivor/survivor_mode.gd:5704` _squad_present_classes |
| 升级归属分流入口 | `survivor/survivor_mode.gd:5714` _distribute_upgrade |
| 普通技能一次性动作（忠诚僚机立即部署） | `survivor/survivor_mode.gd` _dispatch_regular_oneshot |
| "+1 轴进度"发放点 | `survivor/survivor_mode.gd:5821` _grant_milestone_plus |
| 生效子集 meta 重建 | `survivor/survivor_mode.gd:5832` _refresh_squad_effective_stacks |
| 王牌字段技切控迁移 | `survivor/survivor_mode.gd:5845` _migrate_ace_field_upgrades |
| 新僚机入队补挂 build | `survivor/survivor_mode.gd:5861` _apply_build_to_new_member |
| 验收测试（bench skills720） | `tests/test_skills_720.gd:21 run`；`tests/test_skills_720.gd:584 _test_today_full_build_loadout`（今日 13 张/19 层在非 A-10 同机满层共存） |
| 全量生效/文案/收益/Debug 可达性审计（bench skill_audit） | `tests/test_skill_audit.gd` run / `_test_debug_surface_coverage` |

> **技能系统总入口 → [skill-implementation-index.md](skill-implementation-index.md)**（配置字段 × 实装八模式 ×
> 全 stat 消费点速查）。下面按批次的段落只是历史行号锚点，"某技能代码在哪"优先查那份索引。

### 720 批 T3 钩子（僚机阵亡/弹尽/AB 充能/轮盘联动/停靠）

| 功能 | 位置 |
|------|------|
| 备用弹仓（弹尽概率回满） | `survivor/skill_hooks.gd:433` try_gun_reserve_mag |
| 近距捕获（合并副武器后的装填期免耗弹窗口） | `survivor/skill_hooks.gd:450` in_free_missile_window |
| QAAM 强化合并嗜血 / 适应回能（击杀钩子内） | `survivor/skill_hooks.gd:210` 附近 dispatch_on_kill 720 批段 |
| AB 充能静态引用注入 | `survivor/skill_hooks.gd:266` afterburner |
| 僚机阵亡 watcher（0.5s 沿检测） | `survivor/survivor_mode.gd:5882` _tick_squad_watch |
| 复仇之战/刺客复仇/黑匣子分发 | `survivor/survivor_mode.gd:5935` _on_squad_member_down |
| 奖励升级队列/呈现 | `survivor/survivor_mode.gd:5952` _queue_bonus_upgrade |
| 防守此区区域清剿（逐机领目标/击杀接续/越界回防） | `rts/squad_command_controller.gd` `_tick_guard` / `_end_guard`；验收 `tests/test_wheel_orders.gd` D 段 |
| 保卫阵地圈内 buff 维护 | `rts/squad_command_controller.gd:726` _update_guard_zone_buff |
| 阵地转移/保卫阵地/座舱护甲减伤 | `aircraft.gd:3410` _apply_damage 720 批段 |
| 撤离/防守物理注入 | `aircraft/aircraft_physics.gd:609` _g_buff_mult 与 EVAC_SHIFT_SPRINT_BONUS |
| QAAM 击杀归因（kind="qmaam"） | `missile_manager.gd:128` spawn_missile is_secondary |
| 对头击杀经验 ×1.5（历练） | `survivor/survivor_spawner.gd:2514` 附近 headon_xp 段 |

### 720 批 T5 新机制（胆大妄为/机炮吊舱/电磁炮双发/导弹二段）

| 功能 | 位置 |
|------|------|
| R 统一机动（眼镜蛇/J-Turn/胆大妄为） | `aircraft.gd:2735` try_manual_maneuver |
| 胆大妄为动作（i-frame + 滚转 + 投焰） | `aircraft.gd:2763` do_manual_dodge |
| R 键输入入口 | `survivor/survivor_mode.gd:3644` KEY_R 分支 |
| 禁自动 flare 门 | `aircraft/aircraft_flares.gd:125` manual_dodge_active 早退 |
| 机炮吊舱两道翼挂 | `aircraft/aircraft_weapons.gd:392` 附近 gun_extra_barrels 分支 |
| 电磁炮双发补射 | `equipment/railgun_equipment.gd:134` followup_pending 分支 |
| 导弹二段推进（续推+渐强） | `missile.gd:109` _second_stage_g_mult 与动力阶段 elif |

### 722 批机体签名技能 + 50 机专属槽

| 功能 | 位置 |
|------|------|
| 数据表 42 条 sig_* + F-14 围猎特例 | `survivor/survivor_data.gd:1762` sig_f15 起 |
| milestone_plus 数组化 | `survivor/survivor_data.gd:2581` milestone_plus_list_of |
| apply 专用分支（722 段） | `survivor/survivor_skill_effects.gd:414 sig_relaxed_stability` 起 |
| 技能杂项 tick（CD/VIFFing/近太空/三发推力/超速截击） | `aircraft.gd:1852` _update_sig_skills |
| 超速截击选目标（机头前半球 + 当前雷达锥双硬门） | `aircraft.gd:1913` _sig_mig31_pick_target |
| STEALTH 上升沿装填（先敌开火） | `aircraft.gd:3212` _sig_f22_reload_all |
| 隐身多锁齐射消费点 | `aircraft.gd:3228` effective_max_locks |
| 致死拦截（钛浴缸/复活判序） | `aircraft.gd:3491` _try_sig_death_save |
| 负面状态免疫早退（电战预算） | `combat_unit.gd:175` apply_status（头部 sig_status_immune 早退） |
| 全频段压制流速（被锁敌负面 ×0.6） | `status_effects.gd:113` sig_x13_active + tick 内 x13_suppress |
| 锁定管线集中注入（6 技 + viggen 出锥 grace） | `survivor/survivor_mode.gd:4674` _run_radar_slice（722 段在 in_cone/出锥两分支） |
| 一次性特判（f47/x02/ax00） | `survivor/survivor_mode.gd:5759` _dispatch_sig_oneshot |
| 签名 drone 生成（f47/x90，不进离屏 despawn 体系） | `survivor/survivor_mode.gd:5801` _sig_spawn_loyal_drone |
| 联合突击差量重算 | `survivor/survivor_mode.gd:5911` _update_sig_gcap |
| 奖励僚机生成体（双子星复用；尾部 build 补挂） | `survivor/survivor_mode.gd:7035` _spawn_reward_wingman |
| 鲸群血量均摊 | `survivor/skill_hooks.gd:73` whale_pod_share |
| 作战云广播（中继直通防双乘） | `survivor/skill_hooks.gd:96` broadcast_combat_cloud |
| 三发推力触发（突击命令两入口） | `survivor/skill_hooks.gd:116` try_trigger_j36_assault |
| 特殊机动完成事件（急停/落叶飘） | `survivor/skill_hooks.gd:173` on_special_maneuver_done |
| EA-18G 伴随压制（复用全体存活僚机共锁交集，持续 JAM） | `survivor/survivor_mode.gd` `_update_radar_locks` 内 F-14 / EA-18G 共锁段 |
| F/A-XX 穿透打击（仅当前 ACE 本机机炮击杀，5s STEALTH / 20s CD） | `survivor/skill_hooks.gd` `dispatch_on_kill`；`aircraft.gd` `_sig_faxx_cd` |
| f35 越肩发射豁免 | `aircraft/aircraft_weapons.gd:1218` _sig_f35_relay_ok |
| 夜枭静默弹过滤（规避+投焰单点覆盖） | `ai/missile_evasion.gd:276` sig_silent 过滤 |
| 超越地平重索敌 | `missile.gd:604` _sig_find_retarget |
| 验收 bench（43 已实装 + 7 空占位与机场渠道隔离） | `tests/test_sig_skills.gd` `_test_offer_rules` / `_test_new_signatures`；--bench=sig_skills |
| **50 机专属槽 + F-14 特例 + 7 占位** | `survivor/survivor_data.gd` `SIGNATURE_PLACEHOLDERS` / `signature_upgrade_id_for_aircraft` / `signature_upgrade_for_aircraft` / `is_signature_placeholder` / `is_signature_upgrade` |
| **占位不可购买 / 装备 / 阻断出击** | `meta/meta_shop.gd` `signature_item_known` / `signature_nodes`；`survivor/evolution_ui.gd` `show_offer` / `_build_signature_card` |
| **普通升级与奖励池统一排除签名技** | `survivor/survivor_data.gd` `is_normal_random_candidate`：默认排除签名技与 NEXT_GEN，金色 CLASSIFIED 封顶；`zone_data.gd` `_nextgen_candidates` 只显式放行 NEXT_GEN；普通消费点 `survivor_mode.gd` `_roll_upgrade_choices` / `_roll_axis_cards` |
| **机场留机 / 进化二选一调度** | `survivor/survivor_mode.gd` `_current_evolution_node_id` / `_open_evolution_offer` / `_on_settlement_signature` / `_on_settlement_evolution` |
| **机场专属技能视觉与逐机陈列** | `survivor/evolution_ui.gd` `_build_signature_card` / `_build_evolution_card`；`survivor/evolution_detail_panel.gd` `_build_signature` |
| **基础三卡 + 机体适配普通第四卡介质** | `survivor/survivor_upgrade_ui.gd` `populate` / `get_transition_elements` / `schedule_entry_flashes` |

### 728 批 三轴里程碑全队下发（spec evolution-attribute-gates）

| 功能 | 位置 |
|------|------|
| 策士 3 点 XP 玩家级乘区（不按飞机数重复） | `survivor/survivor_player.gd:129` milestone_xp_multiplier |
| 2/3/4/6/8/10 基准里程碑表 | `survivor/survivor_data.gd:3087` MILESTONE_TABLE（斗士 6 点 `max_g +2.0`） |
| Tab 里程碑数值格式（闪避百分比 / G 一位小数） | `survivor/tactical_map.gd:1615` _fmt_milestone_value |

> 语义：里程碑加成**跟玩家不跟机体，且下发全队**（与 UPGRADES 归属分流一致）。
> 记账从玩家级单账本改为**逐机记账**，换帅/换型/晚入队都由构造保证不丢不叠。

| 功能 | 位置 |
|------|------|
| 逐机记账 meta 键 | `survivor/survivor_player.gd:242` MILESTONE_RECORD_META |
| 记账读 / 写（无飞机时落孤儿本） | `survivor/survivor_player.gd:245` _milestone_record / `survivor/survivor_player.gd:252` _set_milestone_record |
| "当前操控机那本账"属性视图（tactical_map 量表读法不变） | `survivor/survivor_player.gd:93` applied_milestones |
| 下发目标提供器（未注入 = 只有当前操控机） | `survivor/survivor_player.gd:101` milestone_targets_provider |
| └ 目标解析 | `survivor/survivor_player.gd:259` _milestone_targets |
| └ 注入点（注 `_squad_members_alive`） | `survivor/survivor_mode.gd:666` milestone_targets_provider |
| 跨档下发（加点后，逐机幂等） | `survivor/survivor_player.gd:273` apply_crossed_milestones_to |
| 全量补挂（新僚机入队 / 僚机换型） | `survivor/survivor_player.gd:289` apply_all_milestones_to |
| └ 新僚机入队调用点 | `survivor/survivor_mode.gd:5875` apply_all_milestones_to |
| 清账重挂（换型；**每机恰好一次**，重复调用会叠两遍） | `survivor/survivor_player.gd:303` reapply_all_milestones_to |
| └ 进化换型调用点（对 `_squad_members_alive()` 逐机） | `survivor/survivor_mode.gd:6595` reapply_all_milestones_to |
| 定向生效（借 self.aircraft 指针走同一 match，同 apply_upgrade_to 手法） | `survivor/survivor_player.gd:309` _apply_milestone_effect_to |
| 无头断言（E2 节：僚机同吃 / 逐机幂等 / 晚入队补挂 / 换帅不丢） | `tests/test_attribute_gates.gd:264` _test_milestone_squad_wide |

### 50 机 T0~T5 进化树与成长审计

| 功能 | 位置 |
|------|------|
| 50 节点 / 155 边 / 具体三轴门派生树 | `resources/evolution/evolution_tree.json`；设计 SSOT `specs/systems/t0-low-t1-aircraft-expansion.md` / `aircraft-evolution-tree.md` |
| 运行时门判定（仅具体三轴 + F/A-18E any）与至少一个可用出口 | `survivor/evolution_system.gd` `gates_passed` `gates_missing` `has_available_exit` |
| Boss Debug T4 参考名单、至少四机同型 Squad、等级、正式三星池 ACE 武器、gates 轴规划与技能 build；Black Star FINAL WAR 自动推进 T5 / Lv26 / 8 点并生成独立 SUPPORT 满配队与海空双方编成 | `survivor/boss_debug_builds.gd` `reference_nodes` `target_axis_points` `roll_weapon_loadout` `roll_reference_build` → `survivor/survivor_select.gd` `_boss_debug_reference_list` → `survivor/survivor_mode.gd` `BOSS_DEBUG_MIN_SQUAD_SIZE` / `_spawn_starting_wingmen` / `_setup_boss_debug_scenario` / `_final_war_promote_primary_squad` / `_setup_final_war_battlefield` / `_setup_final_war_bench_overlay` / `_bench_final_war_summary` / `_final_war_spawn_player_squad` / `_final_war_apply_support_build` / `_claim_weapon_reward` → `survivor/tactical_map.gd` `_refresh_weapon_loadout`；断言 `tests/test_attribute_gates.gd` `_test_boss_debug_reference_builds` + Visual `squad>=4` / 武器实际挂载 / Tab 同屏读数 / FINAL WAR 编成与水域；诊断 A/B 为 `final_war_ocean_baseline/stress` |
| 8 点内全分配枚举、永久不可达边=0 | `tests/test_attribute_gates.gd` `_test_evolution_gates`；bench `attr_gates` |
| 50 节点详情、pip 与 155 条正交树边 | `tests/test_evolution_detail.gd` `_test_gate_pips` `_test_tree_routes_and_current_marker`；bench `evo_detail` |
| 全树雷达 / 机炮 / 导弹局部平滑、9000 px 雷达上限与敌武器成长审计 | `tests/test_player_params.gd` `_test_evolution_edge_smoothing` / `_test_effective_radar_cap` / `_test_enemy_weapon_scaling`；bench `player_params` |
| 玩家机炮弹量五档（180/200/240/280/320）与进化装满 | `playable_aircraft.gd` `gun_ammo_override` → `survivor/survivor_playable_setup.gd` `apply` → `survivor/evolution_system.gd` `evolve`；断言 `tests/test_player_params.gd` `_test_gun_ammo_profiles` |
| 14 分钟成长单局记录器 | `tests/test_evolution_growth_benchmark.gd` `configure_from_environment` `handle_level_up` `tick` `finish`；bench `evolution_growth` |
| 320 局可恢复 Shadow 串行与无效样本补跑 | `bench/run_evolution_growth.ps1`；固定步长入口 `bench/invoke_godot.ps1` `AGL_BENCH_FIXED_FPS` |
| 成长分位数、曲线数据与经验补偿结论 | `scripts/tools/aggregate_evolution_growth.py` `group_row` `build_conclusions` `render_markdown` |

### survivor_debug_skills.gd — F4 技能与装备面板

| 功能 | 位置 |
|------|------|
| F4 开关（打开时暂停）| `survivor/survivor_debug_skills.gd:87` _unhandled_input |
| UI 构建 | `survivor/survivor_debug_skills.gd:84` _build_ui |
| 按钮样式 | `survivor/survivor_debug_skills.gd:370` _apply_btn_style |
| 三轴分组刷新（读取 axis_of_upgrade / AXIS_COLORS） | `survivor/survivor_debug_skills.gd` _refresh / _axis_title / _axis_color |
| 设置等级 | `survivor/survivor_debug_skills.gd:529` _on_set_level |
| 触发升级（+1） | `survivor/survivor_debug_skills.gd:538` _on_levelup |
| 按 ID 强制添加技能（绕过正式门控；保留 max_stacks、正式分流、milestone_plus、对应三轴 +1） | `survivor/survivor_debug_skills.gd` _on_add_skill_by_id |
| 添加选中技能 | `survivor/survivor_debug_skills.gd:513` _on_add_skill |
| 移除技能 | `survivor/survivor_debug_skills.gd:594` _on_remove_skill |
| 装备直挂（含 ESM）与审计入口 | `survivor/survivor_debug_skills.gd` `_LOADOUT_SLOTS` / `_on_loadout_changed` / `debug_skill_ids` / `debug_can_force_upgrade` / `debug_has_loadout_kind` |

### survivor_debug_spawn.gd — F5 刷怪与海陆空气氛实验面板

| 功能 | 位置 |
|------|------|
| 编队类型枚举 FormationType | `survivor/survivor_debug_spawn.gd` FormationType（含全部王牌事件项） |
| 敌机类型标签表 | `survivor/survivor_debug_spawn.gd` ENEMY_TYPE_LABELS |
| F5 开关（不暂停）| `survivor/survivor_debug_spawn.gd` _unhandled_input |
| UI 构建（下拉/规模/空战/炮战/海战/清除按钮）| `survivor/survivor_debug_spawn.gd` _build_ui |
| 类型与编队切换 | `survivor/survivor_debug_spawn.gd` _on_type_changed / _on_formation_changed |
| 刷怪按钮（普通敌机玩家附近即时生成；BOSS/王牌/Adds 保留正式事件航路）| `survivor/survivor_debug_spawn.gd` `_on_spawn_pressed`；`survivor/survivor_spawner.gd` `_debug_spawn_point` / `_set_debug_patrol`；王牌 `_start_ace_event` |
| 气氛实验模式启动与状态 | `survivor/survivor_debug_spawn.gd` _on_atmosphere_pressed / `_on_atmosphere_ground_pressed` / `_on_atmosphere_naval_pressed` / `_on_atmosphere_status_changed` |
| 清空敌人 / 导出日志 | `survivor/survivor_debug_spawn.gd` _on_clear_pressed / _on_dump_pressed |

### battlefield_atmosphere_experiment.gd — 真实局海陆空气氛实验

| 功能 | 位置 |
|------|------|
| 三类样本生成与一键清理 | `survivor/battlefield_atmosphere_experiment.gd` launch_air_battle / `launch_ground_battle` / `launch_naval_battle` / `clear_experiment` |
| 3v3 对向楔形固定翼 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_fighter_wedge |
| 2v2 现有 AH-64 + 专属地面锚 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_heli_pair / `_spawn_ground_anchor`；轮廓强制走现有 `apache`，实验参数副本移除火箭 |
| 双阵营一次性轰炸航线 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_bomber_pair |
| 3v3 火炮解析式椭圆轨道/错峰弹道 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_artillery_line / `_update_artillery_fire_control` / `_update_ballistic_shells`；轨道与外观 `survivor/atmosphere_artillery_unit.gd` |
| DDG+FFG 斜列小巡航圈与低伤害必然命中舰炮 | `survivor/battlefield_atmosphere_experiment.gd` _spawn_naval_group / `_find_water_battle_setup` / `_update_naval_fire_control` / `_resolve_ballistic_impact`；240/120/0 px 降级，`NavalPlacement.score` 每 40px 校验完整同心轨迹；无实验鱼雷数组或逐帧制导 |
| 演员独立武器参数 ×0.10 | `survivor/battlefield_atmosphere_experiment.gd` _duplicate_and_scale_weapons |
| 画外连续开火 / 近距实伤 LOD | `survivor/battlefield_atmosphere_experiment.gd` `_prime_damage_lod` / `_update_damage_lod` / `_set_air_damage_enabled`；1500px 进入、1800px 退出，轰炸炸弹豁免 |
| 零伤害弹丸视觉快路径 | `bullet_manager.gd` `spawn_bullet` / `spawn_rocket` / `spawn_airburst_shell`：仍生成、移动、绘制，普通弹跳过近炸/建筑/单位命中，空爆弹跳过空间网格伤害查询；`missile_manager.gd` `_update_visual_only_ambient_missile`：导弹只检查既定目标并保留爆炸，不扫全体单位、不生成 AOE |
| 2Hz 实验内固定翼/旋翼机重指派 | `survivor/battlefield_atmosphere_experiment.gd:994` _refresh_assignments |
| 已释放实验演员的缓存边界 | `survivor/battlefield_atmosphere_experiment.gd` `_cleanup_refs` / `_is_live_aircraft` / `_is_live_experiment_unit` / `_is_valid_fighter_target` / `_is_valid_ground_target`：typed 数组元素先以 Variant 接收，再按 TYPE_OBJECT → `is_instance_valid` → cast；`tests/volume_world_lifecycle_case.gd` 真实 queue_free 后跨清理与下一指派 tick |
| 8–48km、24–96 名混合容量 bench | `survivor/battlefield_atmosphere_experiment.gd` launch_stress_battle / `stress_summary`；场景路由在 `survivor/survivor_mode.gd` _bench_force_battlefield_atmosphere_stress |
| Headless/Visual 真实场景样本 | `survivor/survivor_mode.gd` _bench_force_battlefield_atmosphere；bench key `battlefield_atmosphere` / `battlefield_atmosphere_ground` / `battlefield_atmosphere_naval` |

### tier-3-zone-global-threats — 3★ 战区特殊任务

| 功能 | 位置 |
|------|------|
| 全局唯一 3★ 名额（正式抽取、机场与 F6 同一闸；F6 可转移但不增加槽） | `survivor/zone_data.gd` `MAX_CONCURRENT_TIER3_ZONES` / `active_tier3_zone_ids` / `has_active_tier3` / `_tier3_allowed_for` / `debug_set_difficulty` / `debug_claim_tier3_slot` |
| 四 profile 分流、来源生命周期与“来源先灭≠任务完成” | `survivor/zone_mission.gd` `_spawn_tier3_profile` / `_register_tier3_sources` / `_update_tier3_source_states` / `_retire_tier3_unit`；信号 `tier3_threat_changed`；正式完成仍走全 TGT 判定 |
| AURORA LANCE 英文状态栏、单体 TGT、固定圆形基盘与独立旋转桁架炮架、4.0s 渐宽 + 1.5s 满宽闪烁、360m 全宽同拍 AOE、随机长机/僚机、5–88km 末端淡出预警与高速长条弹迹 | `survivor/zone_mission.gd` `_spawn_tier3_super_cannon`；`survivor/tier3_super_cannon_part.gd` `DISPLAY_NAME` / `WARNING_FILL_S` / `WARNING_FLASH_S` / `AOE_RADIUS_PX` / `_set_body_heading` / `warning_fill_ratio` / `warning_width_px` / `warning_is_flashing` / `_eligible_aim_targets` / `_choose_aim_target` / `_begin_warning` / `_fire_snapshot` / `_draw_stationary_base` / `_draw_rotating_turret` / `_update_projectile` / `cease_tier3_threat` |
| 攻城坦克 2×CIWS + 远程 SAM + 空爆挂点 | `survivor/tier3_siege_tank.gd` `arm_mounts` / `_spawn_ciws` / `_spawn_sam` / `_spawn_flak`；各挂点实现于 `tier3_siege_ciws.gd` / `tier3_siege_sam.gd` / `tier3_siege_flak.gd` |
| 攻城坦克主炮只打一同区友军气氛地面单位，一次可信直击摧毁 | `survivor/tier3_siege_tank.gd` `_nearest_atmosphere_ground_ally` / `_begin_shell` / `_update_shell` |
| 远程 VLS 只深拷贝 3★ 本舰参数，不污染普通舰队；DEADAIR 替换普通支援场并随来源同拍撤销场、累积与自有 JAM | `survivor/zone_mission.gd` `_tier3_naval_params` / `_spawn_tier3_deadair`；`survivor/survivor_spawner.gd` `register_tier3_deadair_squad` / `retire_deadair_source`；`survivor/deadair_controller.gd` `META_DEADAIR_JAM_OWNED` / `replace_with_priority` / `retire` / `_clear_all_exposure` |
| 持续 HUD 威胁、按内容分流的 Tab/开始提示与 F6 原子 profile/真伤害验收 | `survivor/zone_mission.gd` `resolve_tier3_profile` / `mission_desc_key_for` / `mission_started_fmt_key_for`；`survivor/survivor_mode.gd` `zone_mission_desc_key_for` / `zone_mission_started_fmt_key_for` / `_on_tier3_threat_changed`；`survivor/tactical_map.gd` `_refresh_info`；`survivor/survivor_debug_zone.gd` `normalize_zone_change_request` / `_apply_zone_change` / `_on_neutralize_tier3` |
| 专项契约与正式场景 bench | `tests/test_tier3_zone_threats.gd` `run`（bench `tier3_zone`）；`survivor/survivor_mode.gd` `_bench_force_tier3_zone`（`tier3_super_cannon` / `tier3_super_cannon_d` / `tier3_siege_tank` / `tier3_deadair` / `tier3_long_range_vls`，巨炮覆盖 A/D） |

### zone_atmosphere_combat.gd — 正式战区氛围战斗

| 功能 | 位置 |
|------|------|
| 普通地图每区一次性 30% 抽取并缓存、海洋群岛决战地图全覆盖；生成后登记 / 完成失败重刷取消时注销 | `survivor/zone_atmosphere_combat.gd` `ORDINARY_ZONE_CHANCE` / `DECISIVE_MAP_IDS` / `enabled_for_roll` / `cached_enabled` / `is_decisive_map`；`survivor/zone_mission.gd` `_zone_atmosphere_enabled_for_zone` / `_register_zone_atmosphere` / `_retire_zone_atmosphere` / `_retire_all_zone_atmosphere` |
| 空战零增员复用正式敌军；陆战双方固定阵营专用 SPG，并等概率覆盖无直升机/仅友军/仅敌军/双方都有四种组合；海战只补友军 | `survivor/zone_atmosphere_combat.gd` `register_zone` / `helicopter_sides_for_roll` / `_spawn_atmosphere_helicopter` / `_artillery_seed` / `_spawn_artillery_units` / `_mark_actor` / `_spawn_allied_naval`；`survivor/survivor_spawner.gd` `spawn_atmosphere_ah64` |
| 火炮港池水面排除 + 50px 连续陆地椭圆与舰队 240/120/0 全水降级 | `survivor/zone_atmosphere_combat.gd` `ArtilleryPlanSearch`（`_advance` 逐椭圆采样点验陆地，可分片）/ `_spawn_allied_naval`；`survivor/map_geography.gd` `is_ground_spawn_safe` / `find_ground_spawn_near`；`survivor/atmosphere_artillery_unit.gd` `configure_ellipse`（正式随机轨道）/ `configure_rail`（实验兼容） |
| 2Hz、1500/1800px 伤害迟滞、发射快照与轰炸豁免；60 HP SPG 的近距炮弹为 80px 散布、24px 直击窗、60 点致死伤害，近失/画外零伤害 | `survivor/zone_atmosphere_combat.gd` `update` / `_apply_damage_state` / `_update_artillery_source` / `_resolve_shell`；`combat_unit.gd` `ambient_damage_multiplier` |
| 玩家近距优先且只释放本系统持有的目标权 | `survivor/zone_atmosphere_combat.gd` `_update_player_priority` / `_clear_player_priority`；`ground_unit.gd` `_update_target_selection`；`naval/naval_weapons.gd` `_find_aircraft_in_range` |
| 气氛炮火不能终结正式 TGT | `combat_unit.gd` `take_atmosphere_damage`；`naval/naval_unit.gd` `take_atmosphere_damage_at` |
| 武装直升机永不攻击/命中 Aircraft，只打地面；正式地面 TGT 非致死、气氛地面可击毁；敌军直升机保留经验身份、友军无奖励 | `combat_unit.gd` `META_PROJECTILES_GROUND_ONLY` / `META_AMBIENT_TGT_NONLETHAL`；`bullet_manager.gd` `projectile_allows_target`；`survivor/survivor_spawner.gd` `spawn_atmosphere_ah64` |
| 专项契约 / 真实正式样本 | `tests/test_zone_atmosphere_combat.gd` `run`（bench `zone_atmosphere`）；`survivor/survivor_mode.gd` `_bench_force_zone_atmosphere`（bench `zone_atmosphere_formal`） |

### Optional Zone Mission — 可选战区任务（bomber_escort）

| 功能 | 入口 |
|---|---|
| A/B 在 60s+Lv3 开放；首个 optional 在 150s+Lv5 开放；整局保底 1、20% 第二次、最多 2 | `survivor/zone_data.gd` `initial_reward_unlock_ready` / `optional_mission_unlock_ready` / `release_initial_reward_zones` / `release_first_optional_mission` / `_try_open_followup_optional_mission`；`survivor/survivor_mode.gd` `_update_delayed_zone_unlocks` |
| FAILED 状态、无收益刷新、固定目标/专用航线/任务状态/动态编队缓存、150×星级专属 XP | `survivor/zone_data.gd` `mark_failed` / `bomber_escort_xp_reward` / `get_objective_center` / `get_mission_route` / `get_mission_status` / `get_zone_center` / `set_dynamic_center` |
| 广播后 6 秒生成；独立航线目录、安全陆地目标、七线统一 12500px 航程、场外直线入口、75 HP 单弹目标、3×30 HP B-1B + 2×F-4E；按局势组建截击+扫荡混编计划，轰炸编队先飞完 6% 航程才从实时航迹后方追入，32% 航程前只接近/锁定，40% 无玩家介入才按存活态补一次后方追击增援，58% 仍无玩家介入则中止 | `survivor/zone_mission.gd` `MISSION_SPAWN_RADIO_LEAD_S` / `_ensure_spawned_for_active_zones` / `BOMBER_ESCORT_ROUTE_CATALOG` / `build_bomber_escort_route` / `_prepare_bomber_escort` / `_start_bomber_escort` / `bomber_interceptor_plan` / `bomber_reserve_plan` / `bomber_route_progress` / `bomber_response_should_launch` / `_spawn_bomber_initial_response_if_ready` / `bomber_response_weapons_should_arm` / `_update_bomber_response_fire` / `should_abort_bomber_escort` / `_spawn_bomber_reserve_if_needed` / `_retarget_bomber_interceptors`；`survivor/survivor_mode.gd` `_on_zone_mission_spawn_announced` |
| 150s、每机一弹、成功优先、全灭/离场失败、在途炸弹窗口、无人护送 `abort` 转 EGRESS 与地图/截击层只读成员状态 | `survivor/bomber_mission.gd` `setup` / `abort` / `_force_egress` / `_update_outcome` / `_resolve_failure` / `get_live_center` / `get_live_heading` / `get_bombers` / `get_alive_bomber_count` / `get_alive_escort_count` / `get_phase_key` |
| 纵队槽位、自带护航与按 `{type,count,assignment}` 计划执行的初始/一次性增援后方追击编队；任务实例跳过通用边界 PATROL 接管 | `survivor/survivor_spawner.gd` `spawn_bomber_mission` / `bomber_formation_offset` / `_spawn_bomber_escort_fighters` / `spawn_bomber_interceptors` / `bomber_pursuit_spawn_positions` / `assign_bomber_intercept_target` / `_update_boundary_discipline` |
| 地图失败无痕 / OPTIONAL 类别 + 航线 + 高对比固定 TGT/HP 条/右栏轰炸机、护航机、截击机状态 + 可钳边移动纵队标记 / 准确 XP 预告 | `survivor/tactical_map.gd` `_should_hide_zone` / `_zone_primary_center` / `_draw_bomber_route_and_target` / `_draw_bomber_escort_marker` / `_refresh_info` / `_zone_id_at` |
| 成功绕过普通奖励只发专属 XP；7 秒成功通知显示 XP，无线电只报告截击/目标摧毁/编队撤离等军事态势；失败不发收益且不解释内部介入阈值 | `survivor/survivor_mode.gd` `_on_zone_mission_completed` / `_grant_bomber_escort_xp` / `_say_bomber_escort_intercept` / `_say_bomber_escort_completed` / `_on_zone_mission_failed` |
| F6 强制验收 / 真实 bench | `survivor/survivor_debug_zone.gd` `MISSION_TYPES`；`survivor/survivor_mode.gd` `_bench_force_bomber_escort_zone`；bench key `bomber_escort_zone` |

### survivor_select.gd — 正常八卡起手机 / Boss Debug T4 参考编队选择

| 功能 | 位置 |
|------|------|
| 正常局八张起手机卡（既有四架 + 四架局外采购） | `survivor/survivor_select.gd` `PLAYABLE_LIST` |
| 模式分流 / T4 动态名单 | `survivor/survivor_select.gd` `_effective_list` / `_boss_debug_reference_list` |
| UI / 机型卡片构建（固定全息窗 + 三列卡片） | `survivor/survivor_select.gd` `_build_ui` / `_build_aircraft_card` |
| 悬停 / 键盘焦点预览与卡片高亮；锁定卡不加载档案 | `survivor/survivor_select.gd` `_show_initial_preview` / `_show_aircraft_preview` / `_refresh_card_highlights` |
| 全息投影绘制、正式轮廓复用与加密占位 | `survivor/aircraft_hologram_preview.gd` `show_profile` / `show_locked` / `_draw` → `aircraft_silhouette_catalog.gd` `texture_for_display_name` |
| 选中回调（写资源 + T4 node/level meta） | `survivor/survivor_select.gd` `_on_aircraft_selected` |

## 无线电通讯（spec radio-chatter）

设计权威源：[docs/specs/systems/radio-chatter.md](../specs/systems/radio-chatter.md)。
本节按**"我要改什么 → 去哪"**组织，不按文件罗列。

### ⚡ 最常见的改动（多数不用碰代码）

| 我想…… | 去哪 |
|---|---|
| **加一条台词** | ① `resources/chatter/radio_chatter.json` 对应 trigger 的 `lines` 加 key ② `i18n/radio.csv` 加一行三语。**不碰代码** |
| **改台词文案** | `i18n/radio.csv` 的 `RADIO_*` 行（改完需 Godot 重新导入） |
| **嫌太吵 / 太安静** | JSON `global.ambient_cooldown_sec`（总闸）+ 各 trigger 的 `chance`（主旋钮） |
| **某类语音太频繁** | JSON 该 trigger 的 `chance` 调低 / `cooldown_sec` 调高 |
| **让某类语音必定播出** | JSON 该 trigger 改 `"class": "scripted"`（同时豁免三层节流） |
| **改谁先播** | JSON 该 trigger 的 `weight` |
| **让某机型能/不能说话** | JSON `voiced_enemy_types.types` 增删机型 tag |
| **改 BOSS 登场对话** | JSON `boss_sequences.<BOSS_ID>.spawn`（`slot` = 队内序号，决定谁说） |
| **加新 BOSS 的专属对话** | JSON `boss_sequences` 加一项，key 用 `BossRegistry.BOSS_DEFS` 的 id；不加则走 `_default` |
| **加全新触发场景** | JSON `triggers` 加一项 → 事件点调 `RadioChatter.say("<id>", ...)` |
| **改版式/配色/位置** | `radio_chatter.gd:25-58` 常量区 |

### 数据表结构（`resources/chatter/radio_chatter.json`）

| 段 | 内容 |
|---|---|
| `global` | 全局节流 + 时长 + 队列参数 |
| `triggers.<id>` | `class` / `weight` / `cooldown_group` / `cooldown_sec` / `chance` / `lines` / `lines_ref` |
| `boss_sequences.<BOSS_ID>.{spawn,engage}` | `[{slot, key}]` 多句队内对话；`_default` 为未登记 BOSS 兜底 |
| `voiced_enemy_types.types` | 配无线电的机型 tag 白名单（opt-in，未列 = 沉默） |

### 核心逻辑（`scripts/survivor/radio_chatter.gd`，CanvasLayer layer=19）

| 功能 | 位置 |
|------|------|
| 版式/配色/位置常量 | `radio_chatter.gd:25-58` |
| **三层节流判定**（全局冷却→冷却桶→概率骰） | `radio_chatter.gd:170` say_text 开头 |
| 入队 + 满队按 weight 淘汰 | `radio_chatter.gd:170` say_text |
| 按 trigger 选词 + `%` 格式化 | `radio_chatter.gd:233` say |
| 说话人从单位解析 | `radio_chatter.gd:243` say_unit |
| BOSS 多句序列入队 | `radio_chatter.gd:274` say_boss_sequence |
| 敌方减员里程碑（每 12 架跨档） | `radio_chatter.gd:287` notify_enemy_loss |
| 呼号解析 | `radio_chatter.gd:300` speaker_name_of |
| 阵营色解析（引 FactionPalette） | `radio_chatter.gd:307` color_of / `:313` color_for_team |
| 队列状态机 IDLE/SPEAKING/GAP | `radio_chatter.gd:353` _process |
| 冷却递减（含全局） | `radio_chatter.gd:379` _tick_cooldowns |
| 出队 + 过期丢弃（scripted 豁免） | `radio_chatter.gd:374` _pump |
| 权重排序 | `radio_chatter.gd:406` _best_index |
| 开播（写 Label + 触发音效） | `radio_chatter.gd:399` _begin |
| 显示时长公式 | `radio_chatter.gd:420` line_duration |
| 淡入淡出 | `radio_chatter.gd:443` _apply_alpha |
| 节点构建（PanelContainer + 两 Label） | `radio_chatter.gd:92` _build |
| 渐变底（GradientTexture2D） | `radio_chatter.gd:136` _make_gradient_style |
| 换行后重算高度 | `radio_chatter.gd:158` _relayout |

### 数据加载器（`scripts/survivor/chatter_lines.gd`，**零数值，纯查表**）

| 功能 | 位置 |
|------|------|
| JSON 路径常量 | `chatter_lines.gd:13` DATA_PATH |
| 分类枚举 SCRIPTED/AMBIENT | `chatter_lines.gd:16` Kind |
| 加载 + 静态缓存 + 失败降级静默 | `chatter_lines.gd:28` _ensure_loaded |
| BOSS 序列查询（未登记退 `_default`） | `chatter_lines.gd:129` boss_sequence |
| 说话资格等级门 | `chatter_lines.gd:139` type_has_voice |
| 减员档位映射 | `chatter_lines.gd:148` attrition_trigger |
| 选词防相邻重复 | `chatter_lines.gd:163` pick |
| 校验用全量导出 | `chatter_lines.gd:180` all_line_keys / `:204` all_trigger_ids |

### 说话资格门（无人机不得有台词，spec §2.8）

| 关注点 | 位置 |
|------|------|
| **硬规则**：no_pilot 永不说话 | `aircraft.gd:439` can_speak_on_radio |
| 等级门字段 | `aircraft.gd:435` has_radio_voice |
| 常规敌机赋值（与 no_pilot 同处） | `survivor/survivor_spawner.gd:1796` |
| Mother Goose 蜂群 UAV | `survivor/mother_goose_uav_swarm.gd:250` |
| Mother Goose MQ-X | `survivor/mother_goose_boss.gd:443` |
| 白名单数据 | JSON `voiced_enemy_types.types` |

### 触发接线（每处 ≤4 行，全部挂在既有信号/函数上）

| 触发 | 位置 |
|------|------|
| 系统实例化（**刻意在战区 if 之外**，boss_debug 也要有） | `survivor/survivor_mode.gd:423` |
| 字段声明 | `survivor/survivor_mode.gd:200` _radio |
| BOSS 登场挑衅 | `events/boss_encounter_event.gd` `_try_play_arrival_cinematic`（正式序列）/ `_start`（缺序列时通用 WARNING + 无线电回退）；Black Star 例外由 `_on_hyper_a_root_descent_started` 在两架根机各自真实下降开始时分别播 `BLACK STAR-01/02`，不在身份横幅一次性提前播完 |
| BOSS 交战 | `survivor/survivor_mode.gd:7422` on_boss_engaged |
| 击坠回报 / 弹射 / 减员计数 | `survivor/survivor_mode.gd:7444` _on_radio_kill_recorded |
| break 规避呼叫（真·躲导弹） | `survivor/survivor_mode.gd:7469` _on_radio_evasion_started |
| 加力冲刺呼叫（玩家主动加力，非躲导弹） | `survivor/survivor_mode.gd:7477` _on_radio_afterburner_engaged |
| 僚机归队 | `survivor/survivor_mode.gd:7486` _on_radio_wingman_joined |
| RTS 回令派发 | `rts/squad_command_controller.gd:810` _ack |
| RTS 应答人选取（跳过无人机） | `rts/squad_command_controller.gd:797` _ack_speaker |
| RTS 攻击回令空/地分流（空=追击/包围·地=打击） | `rts/squad_command_controller.gd:825` _strike_or_pursue |
| RTS 目标名解析 | `rts/squad_command_controller.gd:829` _target_label |

### 信号（EventLogger 全局总线）

| 信号 | 声明 |
|------|------|
| `kill_recorded(..., victim_voiced)` | `event_logger.gd:12` kill_recorded |
| `evasion_started(callsign, team)` | `event_logger.gd:16` evasion_started |
| `afterburner_engaged(callsign, team)` | `event_logger.gd:21` afterburner_engaged |
| `wingman_joined(callsign, team)` | `event_logger.gd:25` wingman_joined |

> `kill_recorded` 另有两个订阅方（`survivor_hud` kill feed / `roe_director`），**改签名要同步三处**。

### 音频（Radio 总线）

| 关注点 | 位置 |
|------|------|
| 播放入口 | `audio/audio_manager.gd:757` play_radio |
| 音效 id → 路径 | `audio/audio_manager.gd:93` RADIO_FILES |
| **素材待补** | `res://audio/sfx/radio_beep.wav`（缺失时静默跳过，不 push_warning） |

### 音乐生命周期

| 关注点 | 位置 |
|------|------|
| 非 BOSS 王牌中队血条浮现 / 终态所有权 | `events/ace_reinforcement_event.gd` `_begin_ace_battle_music` / `_end_ace_battle_music` |
| 四曲随机 one-shot（沙漠可追加 `Ace`）、曲终、Boss/Game Over 守卫、地图歌单断点恢复 | `survivor/survivor_mode.gd` `begin_ace_battle_music` / `_on_music_track_finished` / `end_ace_battle_music` / `_play_default_battle_music`；素材 id/path 在 `audio/audio_manager.gd` `MUSIC_FILES` |
| one-shot 完成信号 / 缺资源安全门 / 临时插入曲断点冻结与恢复 | `audio/audio_manager.gd` `music_track_finished` / `has_music` / `crossfade_music_interrupt` / `resume_interrupted_music` / `discard_interrupted_music` |
| 音乐 / 非常驻 SFX 后台线程预载与常驻（Loading 预载常规歌单+王牌曲+全部 `boss*` 曲+引擎循环；BOSS 选定时再补一次预载（已常驻即跳过）；预载只入队、每帧最多发起一个线程请求；取用过的流常驻，切歌帧不再同步解析） | `audio/audio_manager.gd` `prefetch_music` / `prefetch_sfx` / `is_stream_prefetch_idle` / `_prefetch_stream` / `_request_stream` / `_poll_stream_prefetch` / `_resident_stream`；`events/boss_encounter_event.gd` `_start` |
| 音频母版包体隔离 | `audio_intake/.gdignore` + `export_presets.cfg` `exclude_filter` / `patch_delta_exclude_filters`；只排除收件区，不全局排除正式 SFX WAV |
| 主菜单循环曲与战局交接 | `main_menu.gd` `_ready` 幂等 `crossfade_music("main_menu")`；`survivor/survivor_mode.gd` `_play_default_battle_music` → `crossfade_music_playlist` |

### 测试与导出

| 关注点 | 位置 |
|------|------|
| 自动测试音频隔离 | `bench/bench_runner.gd:272` `_ready`：识别 `--bench` 后 mute Master；`tests/test_deadair.gd` `_test_automation_audio_gate` 运行时断言 |
| 无头回归（89 断言） | `scripts/tests/test_radio_chatter.gd`，`--bench=chatter` |
| 航点移动机会火控回归 | `scripts/tests/test_waypoint_fire_control.gd`，`--bench=waypoint_fire` |
| 注册表 | `scripts/bench/bench_runner.gd` UNIT_TESTS |
| **导出必需** | `export_presets.cfg` 的 `include_filter` 必须含 `*.json`，否则数据表不进包 |

## 自动运行时验证

| 关注点 | 位置 |
|------|------|
| 设计权威与覆盖矩阵 | `docs/specs/systems/runtime-validation-workflow.md` |
| Agent 命令、退出码与新增终态清单 | `docs/reference/runtime-validation-workflow.md` |
| 所有 bench 的 stderr 红错改判与自动归因 | `bench/invoke_godot.ps1` `Get-BenchRuntimeErrorBlocks`；Godot 退出 0 但命中致命诊断时退出 86；保留完整 GDScript backtrace，freed-object 族追加 `FREED_OBJECT_LIFECYCLE` 提示 |
| `all` 串联同步断言与终态场 | `scripts/bench/bench_runner.gd` `HEADLESS_TEST_SCENES` / `_ready` / `_swap_to_test_scene` |
| 真实释放终态门 | `scripts/tests/lifecycle_gauntlet_runner.gd` + `scenes/tests/lifecycle_gauntlet.tscn`；含传感器三目标缓存的 A 释放 / B 隐形批清理顺序；bench `lifecycle_gauntlet` |
| 沙漠正式入口冒烟 | `scripts/tests/desert_theater_smoke_runner.gd` + `scenes/tests/desert_theater_smoke.tscn`；真实构造 3v3 地面战线、据点产兵、4 架 AH-64，断言支线不改 600 秒时间轴，并逐一解放三座机场生成三个独立补给点；bench `desert_theater` |
| 错误门自检 | `scripts/tests/runtime_error_probe.gd` + `scenes/tests/runtime_error_probe.tscn`；同时注入普通红错与 freed-object 类型边界，验证完整栈和自动归因；bench `runtime_error_probe` 预期退出 86 |
| bomber 跨帧字典净化 | `scripts/survivor/zone_mission.gd` `_live_bomber_target` / `_live_bomber_controller` → `_start_bomber_escort` / `_update_bomber_escort_caches` / `_retire_bomber_run` |

## 主场景/操控

| 功能 | 位置 |
|------|------|
| 鼠标输入 | `main.gd:66` _unhandled_input |
| 左键点击（锁定/移动） | `main.gd:119` _on_left_click |
| 右键取消 | `main.gd:136` _on_right_click |
| 悬停检测 | `camera_controller.gd` `hover_radius_world_for_zoom/update_hover`（main.gd 调用；30 屏幕像素命中区不随 zoom 缩水） |
| LOD 管理 | `main.gd:454` _update_lod |
| 地形绘制 | `terrain_renderer.gd:116` _draw_terrain |
| 命令轮盘手势层（生存，spec command-wheel） | `scripts/rts/command_wheel.gd`（CommandWheel；参数 `command_wheel_params.gd` + `resources/command_wheel.tres`） |
| 轮盘接线：左键按下/松开仲裁 + 单击回放 | `survivor_mode.gd` `_on_left_press` / `_on_left_release` / `_execute_left_click` / `_on_wheel_command`（阶段 1 stub 打 EventLogger） |
| Mother Goose 本体点击→最近可攻击挂点 | `survivor_mode.gd` `_find_enemy_near` / `_is_inside_mother_goose_hull` / `_find_nearest_mount_target_on` |

## 视觉绘制

### 隔离三维地图与 Mother Goose 实验

东北河道巡检：`tests/volume_relief_stress.gd` `_capture_sequence` 的 `AGL_VOLUME_NORTHEAST_RIVER_PERF=1` 选择东北三处加工业/机场/西河六区域，沿用实际提交计时和流送门，报告显式记录路线身份，不把提交间隔当屏幕FPS。

岸线与路线共用接头：`experiments/volume_mesh_factory.gd` `stroke_edges` 处理开放/闭合边界；`experiments/volume_map_factory.gd` `stroke_edges` 保留原调用入口；`experiments/volume_desert_relief.gd` `make_details` 将保留闭合岸线与固定水面同高，并并入贴坡河线。`tests/test_volume_desert_relief.gd` `_test_shoreline` 检查实际Float32接头、UV和高度；`tests/test_volume_map_factory.gd` `run` 覆盖闭合/重复点/反向尖角；`experiments/volume_3d_lab.gd` `_capture_sequence` 留存三处岸边及三处河道远近机位。

有来源的连续河道见 `experiments/volume_watercourse.gd` `build` / `_append_triangle`，沿唯一地形裁面并保留横向UV；数据 `resources/maps/desert_volume_hydrography.json` 纳入 `experiments/volume_terrain_archive.gd` `source_fingerprint`。`tests/test_volume_desert_relief.gd` `_test_watercourses` / `_watercourse_mesh_stats` / `_watercourse_coverage` 覆盖实际归档、面内贴地及长线跨脊反例。离线生产入口 `tools/build_volume_desert_hydrography.py` `build` / `water_quads`，原始来源在 `tools/map_sources/desert_hydrography/`；`tools/test_volume_desert_hydrography.py` 覆盖孔洞、分离水池和逐字重建，`test_western_supplement_preserves_source_and_confluence` 核对西部源节点/内部汇流，`test_northeast_complete_way_and_partial_contour_preserved` 核对东北完整节点/符号替换与部分关联保留。`experiments/volume_3d_lab.gd` `_capture_sequence` 的 AGL_VOLUME_WEST_WATER_QA 拍三处三缩放实际水系；AGL_VOLUME_WATER_COVERAGE_QA拍实际河线覆盖开关与无线背景，不用于FPS。`resources/shaders/volume_map_line.gdshader` `fragment` 只对UV.x河线调整小尺寸内削边；`tests/volume_relief_stress.gd` `_capture_sequence` 的AGL_VOLUME_WATER_COVERAGE_PERF选择六处水系实际负载，开关不进入正常场景。

河道远景最小覆盖：`experiments/volume_watercourse.gd` `build` / `_append_triangle` 保留共享接头横向UV2；`experiments/volume_desert_relief.gd` `make_details` 只在tactical水线材质启用屏幕覆盖；`resources/shaders/volume_map_line.gdshader` `vertex` 保留深度并补足最小像素宽，不改变原片元透明度。`tests/test_volume_desert_relief.gd` `_test_watercourses` 检查实际UV2；`tests/test_volume_terrain_archive.gd` `_test_tactical_details` 与 `tests/desert_formal_entry_runner.gd` `_run` 检查实际归档/正常开局开关、深度和远近截图。

背景道路接坪：`tools/build_desert_tactical_context.py` 离线分开楼体净空与道路地坪裁切，输出逐设施轮廓和源接坪点；`tests/test_volume_satellite_ground.gd` `_test_road_joins` 用真实建筑工厂复算轮廓，验证接坪点被实际Float32网格覆盖，并逐顶点核对近远道路源XZ/贴地高度/法线/原色不随建筑调色改变。原始OSM路径、依赖目录、报告目录均显式传入构建工具。

沙漠克制面色：`experiments/volume_desert_tactical_context.gd` `build` / `_height` / `_roofs` / `_up_triangle` 构建四个原生背景区域，`ROOF` / `WALL` 与主体设施分开控制背景视觉层级；`experiments/volume_satellite_ground.gd` `setup` / `_sync_cover_lod` 按每区高度误差复用既有tick；`experiments/volume_map_factory.gd` `configure_instance` 绑定沙漠独立哑光材质。`resources/shaders/volume_desert_tactical_surface.gdshaderinc` 无照片采样；`tests/test_volume_satellite_ground.gd` `_test_tactical_profile` 覆盖资源、预算、近远颜色顶点守恒、源坐标与释放。正式四区实际色板绑定、截图及驻留纹理像素反证由 `tests/desert_formal_entry_runner.gd` `_run` 执行。

沙漠坡面明暗：`resources/shaders/volume_desert_tactical_surface.gdshaderinc` `light` 使用 relief_contrast 和连续肩部响应；不改变地被、建筑或接触AO。`experiments/volume_3d_lab.gd` `_capture_sequence` 的 AGL_VOLUME_RELIEF_LIGHT_QA 对三峰/工业两倍率拍实际材质开关；`tests/desert_formal_entry_runner.gd` `_run` 验证正常载入交接后的GL默认值且无测试覆盖，数值合同见 desert-volume-map 的 R118。

| 功能 | 位置 |
|---|---|
| 正式 Survivor 三维飞机合成与二维 A/B | `rendering/aircraft_volume_overlay.gd` `default_enabled` / `setup` / `_process` / `_sync_size` / `set_volume_enabled` / `toggle_volume` / `summary`：原生像素透明 SubViewport + 2× MSAA，正式相机之后逐显示帧同步；`survivor/survivor_mode.gd` `_ready` / `_unhandled_input` 默认接线与 Shift+F11；`AGL_AIRCRAFT_VOLUME=off` 为无空视口二维基线 |
| 正式沙漠地图默认入口 | `survivor/survivor_mode.gd` `_ready` 从成功加载的 `_ugc_source_path` 判定内置沙漠，创建 `_desert_volume_renderer`，与透明飞机层互斥；`rendering/desert_volume_presentation.gd` `enabled_for` / `setup_formal` 接入共享同视口地图后端。正常主菜单→选图→选机→预加载→正式生存，不经过测试派生场景；`AGL_DESERT_VOLUME=off` 回退地图，Shift+F11 只切机体 |
| 正式沙漠菜单链与重入回归 | `scenes/tests/desert_formal_entry.tscn` → `tests/desert_formal_entry_runner.gd` `_ready` / `_run` / `_wait_scene` / `_key` / `_check`；只允许隔离的 `tmp/desert-volume/r53-formal-profile` 存档，验证两次真实菜单链、不同选机、生涯计数、地图后端、输入/Tab、截图和退出释放；追加正式 raster owner 身份与卫星候选 Tab 纹理对象一致性，避免初始化过早进入 Lab fallback；截图旁录实际canvas/viewport，补双倍道路近景及工业四区1.3近景/实际相机与流送状态，不冒充整局或性能验收 |
| 真实卫星候选与单一加载所有者 | `survivor/raster_basemap_renderer.gd` `map_root_for` / `manifest_path_for` / `presentation_profile` / `shared_strategic_texture`；`survivor/tactical_map.gd` `_ensure_raster_basemap` 先借用主图纹理；`survivor/survivor_mode.gd` `_ready` 在 MapFeatureRenderer.setup 完成后创建正式三维表现。`experiments/volume_satellite_ground.gd` `configure_source_material` 在地表/装饰应用来源 profile；`resources/shaders/volume_satellite_surface.gdshaderinc` 卫星来源不重复乘 ALBEDO；`tests/test_volume_satellite_ground.gd` `_test_satellite_profile` 锁住来源隔离、共享、材质和退出 |
| 实验入口与成对正式负载 | `bench/bench_runner.gd` `VOLUME_SCENARIOS` / `VISUAL_TEST_SCENES` / `_swap_to_volume_experiment` / `bench_finish`；三维 C2 未实际提交 LOD1 与 LOD2 时 fail closed；仅经 `bench/run.cmd` 启动，不修改玩法数据 |
| 斜俯视投影、专属 key 选择、网格预热/批次惰性创建、双通道涂装、机身/挂载 LOD 与终态 | `experiments/volume_projection.gd` `top_basis` / `camera_basis` / `ground_basis` / `actor_transform`；`experiments/volume_world_probe.gd` `setup` 的 `prewarm_catalog` / `_cache_mesh_route` / `_ensure_batch` / `_refresh_members` / `world_point` / `_sync_camera` / `_process` / `set_bodies_enabled` / `_set_body_override` / `mount_detail_mode_for` / `body_lod_level_for` / `_submit` / `livery_ratio_for` / `_sync_aircraft_mounts` / `_sync_goose_mounts` / `_submit_rotor` / `_capture` / `summary` / `_exit_tree`；`resources/shaders/volume_aircraft_livery.gdshader` 保留双通道涂装且不拆批次；全部 71 个航空身份按实际输出跨度 22/18 px 切 LOD0/LOD1、8/11 px 切 LOD1/LOD2，独立挂载仍按 22/18 px，画面判定不读取逻辑身份豁免 |
| 可重建几何、静态地图 | `experiments/volume_mesh_factory.gd:9 triangle` / `:18 quad` / `:23 prism` / `:50 box` / `:60 loft` / `:72 mesh` / `:84 material` / `:94 aircraft` / `:147 map_mesh` / `:173 ribbon` / `:181 points_from` |
| 全机型生产目录、逐型 LOD0/LOD1/LOD2 几何与来源许可 | `experiments/volume_aircraft_catalog.gd` `supported_keys` / `build` / `build_runtime` / `supports_body_lod` / `build_runtime_lod` / `_build_medium_body_lod` / `_build_far_body_lod` / `_connected_components` / `_directional_outline` / `_mirrored_outline` / `_support_outline` / `metadata_for` / 各 `_build_<key>` / `_planform` / `_closed_loft` / `_cap_ring` / `_fin` / `_outward_triangle`；LOD1 从完整源保留主要连通结构与局部厚度，最多 320 面；LOD2 为最多 128 面的极远支撑轮廓；当前完成数由 `resources/aircraft_volume_models/reference_manifest.json` 与审计实时报告，不冻结快照总数 |
| 普通飞机真实装备与动态旋翼 | `experiments/volume_aircraft_mount_catalog.gd` `AIRCRAFT_KINDS` / `NORMALIZED_SLOTS` / `local_slots` / `visible_count` / `state_color` / `build` → `experiments/volume_world_probe.gd` `_sync_aircraft_mounts` / `_submit_rotor`；只读 AircraftParams 与弹药/装填/充能/过热状态，所有几何共享批次 |
| 沙漠地图生产网格 | `experiments/volume_map_factory.gd` `build` / `_line_mesh` / `merge_meshes` / `configure_instance` / `configure_sun` / `_add_airport_details` / `_add_industrial_details` / `palette` / `face` / `stroke_edges` / `stroke` / `sleeper_poses` / `airport_polygon` / `_add_runway_markings` / `_add_roof`；同源地理、横向UV连续线路、地面接影与七区域投影；`resources/shaders/volume_map_line.gdshader` 导数边缘、`volume_structure_surface.gdshader` 共享弱风化；卫星模式省略大块平色地表 |
| 斜俯视投影 | `experiments/volume_projection.gd` `top_basis` / `camera_basis` / `ground_basis` / `actor_transform`；世界 probe 按入口配置角度，沙漠不修改正式机体层默认值，不改二维玩法锚点；`tests/test_volume_camera_sync.gd` `run` / `_check` / `WatchedMesh._notification` 校验静态提交去重与两入口镜头状态等价 |
| 工业与机场几何 | `experiments/volume_building_factory.gd` `frame` / `rectangle` / `scaled_polygon` / `add` / `industrial_roof_details` / `warehouse_surface_point` / `_office` / `_tower` / `_tank` / `_warehouse` / `_roof_quad` / `airport_details`；一次写入共享静态网格；`tests/test_volume_map_factory.gd` `_test_industrial_clearance` 验证源建筑/底座铁路净空、原压轨反证、迁移地块缓存平地/地被净空、屋面板贴坡/确定性及设备和雨棚各自局部边界预算 |
| 三城区布局与净空 | `experiments/volume_district_layout.gd` `layout` / `_segments` / `_nearest_road` / `_protected_rects` / `_plot_clear` / `_street_clear` / `_segment_distance`；`tests/test_volume_district_layout.gd` `run` / `_check` |
| 沙漠同源修补与微细节 | `experiments/volume_satellite_ground.gd` `enable_relief` / `_make_plane` / `debug_state` / `_clear`；`resources/shaders/volume_satellite_surface.gdshaderinc` 原机场边界及同源纯地形重建；`resources/shaders/volume_map_water.gdshader` 静态沉积色；`tests/build_volume_terrain.gd` `run` 输出 `resources/maps/desert_clean_terrain_r52.res` 候选，`tests/test_volume_satellite_ground.gd` `_test_detail_material` 校验预算、边界及释放 |
| 同源卫星瓦片三维桥接 | `experiments/volume_satellite_ground.gd` `setup` / `enable_relief` / `setup_lab` / `sync` / `_make_plane` / `_clear` / `debug_state`；`survivor/raster_basemap_renderer.gd` `presentation_tiles` 只读快照；`shaders/volume_satellite_ground.gdshader` 透明过渡 / `volume_satellite_opaque.gdshader` 稳定深度 / `volume_desert_decoration.gdshader` 装饰源图投影 / `volume_satellite_surface.gdshaderinc` 共用接影与有界重建；`tests/test_volume_satellite_ground.gd` `run` / `_test_detail_material` / `_check` |
| DEM 表现高度与源图岸线 | `experiments/volume_desert_relief.gd` `_init` / `height_at` / `normal_at` / `plane_mesh` / `presentation_mesh` / `presentation_bounds` / `make_details` / `_add_outcrop` / `outcrop_profile` / `_add_surface_triangle`；`resources/maps/desert_volume_relief.json`；`tools/build_volume_desert_relief.py` 离线数据提取；`resources/shaders/volume_map_line.gdshader` 连续线 AA；`tests/test_volume_desert_relief.gd` `run` / `_test_outcrops` / `_test_surface_contract` / `_surface_error` / `_test_tile_budget` / `_check` |
| 静态三维地图离线预构建 | `experiments/volume_terrain_archive.gd` `source_fingerprint` / `is_current` / `matching_mesh` / `source_rect` / `tile_layouts` / `canonical_tile_rect`；`experiments/volume_desert_relief.gd` `bind_archive` 在真实风格确定后只加载一份；`tests/build_volume_terrain.gd` `run` / `_mesh_bytes`，显式 bench `volume_terrain_build`；`tests/test_volume_terrain_archive.gd` `run` / `_same_mesh` / `_test_tactical_details` / `_check`，source资源 `resources/maps/desert_volume_terrain.res`、tactical资源 `resources/maps/desert_volume_terrain_tactical.res` 各存唯一装饰场景；`tests/test_volume_tile_edges.gd` `run` / `_mesh_edge` / `_check` 验证共边和源UV不变 |
| 原生面材质地表去重 | `experiments/volume_satellite_ground.gd` `sync` / `_make_plane` 原生候选只用完整归档网格，固定既有Detail底高；`tests/test_volume_native_surface.gd` `run` / `_compare_triangle` / `_negative_controls` 全部145瓦片逐面验证；`tests/test_volume_satellite_ground.gd` `_test_tactical_profile` 验证照片换档不再改变原生地面，`tests/volume_relief_stress.gd` `_streaming_snapshot` 验证实际归档身份与完整源视口覆盖 |
| 地被屏幕误差LOD候选 | `experiments/volume_desert_relief.gd` `make_cover_lod` 预构建同足迹近远档；`experiments/volume_satellite_ground.gd` `cover_error_pixels` / `cover_lod_far` / `_sync_cover_lod` / `_apply_cover_lod` 10Hz投影与切档；`tests/test_volume_desert_relief.gd` `_test_cover_lod` packed误差/岩体一致性；`tests/test_volume_satellite_ground.gd` `run` / `_test_detail_material` 回滞/资源共享；`tests/volume_world_lifecycle_case.gd` `run` 真实相机投影/释放；`experiments/volume_3d_lab.gd` `_capture_cover_lod` 显式env同机位近远对拍 |
| 地形缓存导出指纹及沙漠文档 | `../addons/volume_terrain_export/plugin.gd` `_enter_tree` / `_exit_tree` / `_get_name` / `_export_begin`；`project.godot` editor_plugins 注册，原文附件与 .gdc 映射共存，显式收录FileAccess读取的沙漠.aglmap |
| 预构建岩面材质 | `tests/build_volume_terrain.gd` `run` 读取 `resources/desert_material_source/desert_rock_albedo_r40.png` 并输出 `resources/maps/desert_rock_albedo_r40.res` 的候选；原始prompt同目录。`experiments/volume_desert_relief.gd` `_add_outcrop` 写局部增高混合权重；`experiments/volume_satellite_ground.gd` `_make_plane` 绑定共享纹理与双色彩均值，`resources/shaders/volume_satellite_surface.gdshaderinc` 按渲染色彩空间作有界调制；`tests/test_volume_satellite_ground.gd` `_test_detail_material` 验资源预算/释放 |
| 纯2D与三维地图性能对照 | `tests/volume_map_performance.gd` `setup` / `_live_probe` / `summary` / `_capture` / `_sample_render_times` / `_accept_render_frame` / `_record_render_sample` / `_record_render_coverage` / `_record_coverage_slot` / `_coverage_report` / `_timing_report` / `_exit_tree`；bench `volume_map_2d_c1` / `volume_map_3d_c1` / `volume_map_2d_c2` / `volume_map_3d_c2`，真实沙漠 UGC 加同负载巡检；`AGL_VOLUME_RENDER_TIMING=1` 仅显式CPU/GPU及可见/阴影提交诊断，共用FPS帧号窗口，不能混入无计时的FPS门 |
| 三角曲面与瓦片裁剪权威 | `experiments/volume_terrain_surface.gd` `_init` / `_world_node` / `_insert_node` / `_build_refinement` / `cell_triangles` / `triangle_weights` / `_coordinates` / `_value` / `_sample_scalar` / `height_at` / `normal_at` / `_node_normal` / `clip_to_triangle` / `_clip_polygon` / `plane_mesh`；显式源 DEM 局部细分与闭合过渡环，瓦片/岩石共享三角面，跨 LOD 保留面内高度/法线/颜色和 gutter UV；`tests/test_volume_desert_relief.gd` `_test_refinement` 验源节点、拓扑、裁边面内一致性 |
| 地形跨区/LOD 专项 | `tests/volume_relief_stress.gd` `_capture_sequence` / `_render_diagnostic` / `_streaming_snapshot` / `render_sample_valid`；`scenes/tests/volume_relief_stress.tscn`；bench `volume_relief_stress 36 180 Shadow Visual`，六处机位/帧时/提交检查；计时结束后分类可见/预取缺口与三维绑定并验证静止收敛；诊断另记坏帧wall time与最近后端计时、限帧/vsync/缓存目录，非同步因果证明、混战或逐像素覆盖验收 |
| 地形曲面/落地离线审计 | `tools/audit_volume_relief.py` `audit`；复算 R11 细格点双线性与 Strategic 三角面差异、瓦片裁边高度及植被机位覆盖；输出 CPU 诊断，不能替代 Godot 几何或 Visual 验证 |
| 东京站小片清晰城市候选 | `experiments/volume_3d_tokyo_preview.gd` `_ready` / `_configure_environment` / `_add_batch` / `_set_view` / `_capture_sequence` / `_settle` / `_capture` / `_exit_tree`；`experiments/tokyo_preview_ground.gd` `snapshot`；`experiments/tokyo_volume_preview_factory.gd` `build` / `build_ground` / `_add_low` / `_add_known` / `_shell` / `_ribbon` / `_face` / `_points` / `_triangles`；`tools/build_tokyo_volume_preview.py` `PreviewCollector.way` 与 `tools/build_tokyo_preview_ground.py` `Collector.area` / `Collector.way`；bench `volume_3d_tokyo_preview` 仅固定小片截图，不是正式全图/LOD/性能验收 |
| 东京站首区 LOD 实装 | `survivor/map_feature_renderer.gd` `setup` → `rendering/tokyo_volume_overlay.gd` `default_enabled` / `setup` / `_process` / `_switch_level` / `_deactivate` / `set_enabled` / `debug_state`；`rendering/tokyo_volume_archive.gd` `choose_level` / `valid`；离线 `tests/build_tokyo_volume_archive.gd` `run` / `_bytes`；`tests/test_tokyo_volume_lod.gd` `run`、`tests/tokyo_volume_lifecycle_case.gd` `run`、`tests/tokyo_volume_visual_runner.gd` `_capture_sequence`、`tests/tokyo_volume_combat_runner.gd` `_bench_force_battlefield_atmosphere_stress` / `_bench_update_camera_patrol` / `_capture_city` / `_bench_finish_now`；来源实际地图层保留，原生地图视口不共享飞机低分辨率目标；bench `tokyo_volume_c1/c2/near` 及各自 `_baseline` 为成对入口 |
| 东京相邻城区 R5 候选 | `tools/build_tokyo_volume_region.py` `RegionCollector.resolve_relations` / `resolve_parts` / `source_cache` / `export` 保留来源与内环；`experiments/tokyo_volume_preview_factory.gd` `_add_ring_building` / `_triangle_face` 绘制内院和分部；`rendering/tokyo_region_archive.gd` `valid` / `packet` 与 `tests/build_tokyo_region_archive.gd` `run` 烘焙单档候选；`scenes/tests/tokyo_region_preview.tscn` / `tokyo_region_preview_b.tscn` 使用同位基线/阴影/街区截图；bench `tokyo_region_preview` / `tokyo_region_preview_b`，不代表新增区已通过正式 LOD/性能门 |
| 横滨 R9 港区候选 | `tools/tokyo_coastal_faces.py` `coastal_faces` 从有向岸线闭合海陆；`tools/test_tokyo_coastal_faces.py` 断岸/岛洞反例；`tools/build_tokyo_volume_region.py` `main` 显式 `--coastal --no-baseline`；`tests/build_tokyo_cells.gd` `run` / `rendering/tokyo_cells_overlay.gd` `_load_archive` 的 `AGL_TOKYO_CELLS_VARIANT=yokohama` / `yokohama_color` 对应独立 `r9_cells` / `r9c_cells`；`tests/test_tokyo_cells.gd` `_test_yokohama` 验水色校准不改楼体数组/岸线顶点；`tests/tokyo_cells_lifecycle_case.gd` `_test_empty_coastal_cell` 验零建筑块异步读取及owner退出；`tests/tokyo_cells_runtime_visual.gd` `_capture_sequence` 核对六档及同位瓦片，不覆盖默认 R4 |
| 横滨 R10 来源坡顶候选 | `tools/tokyo_tagged_roofs.py` `tagged_roof` 半平面裁切原 footprint；`tools/build_tokyo_tagged_roofs.py` `main` 保留总高与未支持项审计；`experiments/tokyo_volume_preview_factory.gd` `_prepared_surface` 分离屋面/立面分类；`tests/test_tokyo_cells.gd` `_test_tagged_roofs` 核对固定面、低层、全档来源/高度；显式 `AGL_TOKYO_CELLS_VARIANT=yokohama_roofs` 读取独立 `r10_cells`，不是默认推广 |
| 横滨 R11 分层裁剪/低层过渡候选 | `rendering/tokyo_cells_overlay.gd` `layer_bounds` / `_apply_visibility` / `relief_enabled` / `_target_entry` 保留高楼阴影、按实际输出尺度选择过渡包；`tests/build_tokyo_cells.gd` `run` 为 `yokohama_mid` 输出独立 `r11_cells`；`tests/test_tokyo_cells.gd` `_test_mid_relief` / `_test_layer_bounds` 验来源、原六档逐数组与旋转阴影；`tests/tokyo_cells_lifecycle_case.gd` `_test_layer_visibility` 验隐藏/恢复及同全局档位跨包切换；`tests/tokyo_cells_runtime_visual.gd` `_ready` 显式允许真实旋转 |
| 横滨 R12 当前方向裁剪候选 | `rendering/tokyo_cells_overlay.gd` `projected_layer_bounds` / `_apply_visibility` 合并屋顶投影与日光投影边界；显式 `yokohama_directional` 复用 R11B 归档；`tests/test_tokyo_cells.gd` `_test_layer_bounds` 验24方向屋顶/地面影/中间高度接收面；`tests/tokyo_cells_lifecycle_case.gd` `_test_layer_visibility` 验实际正负旋转刷新、恢复与退出，不代表性能门已过 |
| 横滨 R13 密度分块候选 | `tests/build_tokyo_cells.gd` `connected_groups` / `adaptive_rects` / `_split_density` / `partition` / `split_fixed` 按来源密度分配16格并保持整栋归属；`tests/test_tokyo_cells.gd` `_test_density_partition` / `_test_adaptive_archive` / `_add_mesh_signature` 验分块确定性、完整覆盖与七档无序三角多重集；显式 `yokohama_adaptive` 读取独立 `r13_cells`，原包与默认入口不变 |
| 横滨 R14 旋转视域候选 | `rendering/tokyo_cells_overlay.gd` `intersects_view` / `_apply_visibility` 用地图与实际屏幕坐标的分离轴相交排除角落误报；`tests/test_tokyo_cells.gd` `_test_rotated_view` 验边缘/跨屏薄片和旋转角落反例；`tests/tokyo_cells_lifecycle_case.gd` `_test_layer_visibility` 验真实R14旋转、切档和恢复；`yokohama_frustum`复用R13包，不默认推广 |
| 横滨 R15 覆盖成本分块候选 | `tests/build_tokyo_cells.gd` `_partition_atoms` / `coverage_rects` / `_coverage_cost` / `_coverage_split` 用通用多尺度覆盖面积分配16块；`tests/test_tokyo_cells.gd` `_test_density_partition` / `_test_adaptive_archive` 验确定性/空海面/完整归属和七档几何多重集；`tests/tokyo_cells_lifecycle_case.gd` `_test_layer_visibility` 验R15/A/B/C恢复及跨档；显式 `yokohama_coverage` / `_b` / `_c` 分别读独立 `r15_cells` / `r15b_cells` / `r15c_cells`，继承R14裁剪；`tests/tokyo_volume_combat_runner.gd` `cell_peak_within_budget` / `_bench_finish_now` 对所有非baseline分块战斗入口执行整个移动峰值240k硬门；不默认推广 |
| 东京 R6/R8 分块多档候选 | `rendering/tokyo_cell_index.gd` `visible_cells` 与 `rendering/tokyo_cell_archive.gd` `valid`；`tests/build_tokyo_cells.gd` `partition` / `split_fixed` / `detail_level` / `run` 构建独立档位，不切半栋；`tests/test_tokyo_cells.gd` `_test_relief` / `_roof_signature` / `_same_mesh` 检查来源、高度、低层屋顶、标高楼和近档原几何；R8显式 `AGL_TOKYO_CELLS_VARIANT=relief` 输出独立 `r8_cells`；`tests/tokyo_cells_visual.gd` `_select_cells` / `_capture_sequence` 固定机位按块按档读取及释放，三材质共用；bench `tokyo_cells_build` / `tokyo_cells` / `tokyo_cells_visual` |
| 东京 R7 异步接线候选 | `rendering/tokyo_cell_stream.gd` `request` / `_process` / `close`；`rendering/tokyo_cells_overlay.gd` `_should_prewarm` / `_step_geometry` / `_sync_requests` / `_deactivate`，`rendering/tokyo_volume_overlay.gd` `_should_prewarm` 保留R4默认两帧；`survivor/map_feature_renderer.gd` `setup` 显式 `AGL_TOKYO_VOLUME=cells`，默认仍R4；`tests/tokyo_cells_lifecycle_case.gd` `run` 与 `tests/tokyo_cells_runtime_visual.gd` `_capture_sequence`；bench `tokyo_cells_lifecycle` / `tokyo_cells_runtime_visual` 及 `tokyo_cells_c1/c2/near` 和各自 `_baseline`；不等于中距离预算与平滑过渡已通过 |
| 独立观察、真实沙漠入口与模型导出 | `scenes/tests/volume_3d_lab.tscn` → `experiments/volume_3d_lab.gd` `_ready` / `_add_mesh` / `_set_view` / `_set_map_view` / `_set_aircraft_view` / `_set_map_location` / `_set_play_map_view` / `_set_district_view` / `_unhandled_key_input` / `_capture_sequence` / `_save_view` / `_process` / `_exit_tree` / `_export_mesh`；D 进入 `scenes/tests/volume_3d_desert.tscn` |
| 全机型分档分页四视图与逐型 GLB | `scenes/tests/volume_aircraft_multiview_qa.tscn` → `tests/volume_aircraft_multiview_qa_runner.gd`；LOD0/LOD1/LOD2 均覆盖全 71 型，普通页每页 8 架、Mother Goose 独立原生尺度页，采顶/侧/前/游戏倾角并输出分档 manifest/GLB；bench `volume_aircraft_multiview` / `volume_aircraft_lod_multiview` / `volume_aircraft_lod2_multiview` |
| 全量真实演员分页路由 | `scenes/tests/volume_aircraft_runtime_qa.tscn` → `tests/volume_aircraft_runtime_qa_runner.gd`；70 个非 Mother Goose key 加载真实 AircraftParams，验证稳定身份、每实例双配色 custom data、PNG 回退、挂载、AH-64/CH-47 四组动态旋翼及释放缓存；bench `volume_aircraft_runtime` |
| F6 / 观察场 B 手动战斗 | `scenes/tests/volume_3d_combat.tscn` → `experiments/volume_3d_combat.gd` `_ready` / `_run_volume_smoke`；真实输入与重开退出：`tests/volume_combat_smoke.gd` `run` / `_wait_for_scene_release` / `_key` / `_mouse` / `_check` |
| 三维沙漠真实玩法与冒烟 | `scenes/tests/volume_3d_desert.tscn` → `experiments/volume_3d_desert.gd` `_ready` / `_unhandled_input`；在正式 Survivor 沙漠局保留 2D 权威、输入、AI、武器与 HUD，叠加三维飞机/卫星/地图；`tests/volume_desert_smoke.gd` `run` |
| 验证入口 | `tests/test_volume_world.gd:9 run`；`tests/volume_world_lifecycle_case.gd:19 run` → 默认 `tests/lifecycle_gauntlet_runner.gd` `_run`；生命周期同时覆盖正式透明飞机层和卫星来源释放 |
| 正式/F6 画质与击坠连续性 | `tests/volume_formal_quality_runner.gd` `_run` / `_volume_point` / `_capture`；`volume_formal_quality` Visual 在真实帧验证投影、对照截图与同机体淡出；`resources/shaders/volume_aircraft_fade.gdshader` 为原网格共享透明材质 |
| 逐型 LOD0/LOD1/LOD2 几何/身份/涂装掩码/挂载与地图验收 | `tests/test_volume_aircraft_catalog.gd` `run` / `_test_runtime_mounts` / `_valid_triangles` / `_has_wing_livery_mask` / `_symmetric` / `_forward_nose` / `_profile_signature` / `_expect`；逐型验证两档均降面、320/128 面预算、长宽轮廓、对称性、双通道涂装及 LOD1 复杂度严格高于 LOD2；`tests/test_volume_map_factory.gd`、`tests/test_volume_district_layout.gd`、`tests/test_volume_satellite_ground.gd` 各 `run` / `_check`；并入 `volume_world`；全量静态矩阵 `scripts/tools/audit_aircraft_volume_models.py` |
| 克制建筑材质初始化预热 | `experiments/volume_material_warmup.gd` `configure` / `_ready` / `_after_draw` / `_exit_tree`；`experiments/volume_satellite_ground.gd` `setup` / `_on_material_warmup_finished` / `_clear`；32×32私有世界两帧后释放，`tests/test_volume_satellite_ground.gd` `_test_tactical_profile` 格式/预算、`tests/volume_world_lifecycle_case.gd` `run` 提前退出回调清理 |

机场场坪与服务连接：`experiments/volume_map_factory.gd` `airport_service_surfaces` / `_add_airport_details`；`tests/test_volume_map_factory.gd` `_test_airport_services` 检查三个机场连通、承托、净空和实际网格；`experiments/volume_3d_lab.gd` `_capture_sequence` 输出三个机场0.65/1.30双倍率服务区近景。

透明线路分层：`experiments/volume_map_factory.gd` `_line_mesh` 按既有高度稳定重排提交，路肩先于路心、枕木先于钢轨；`tests/test_volume_map_factory.gd` `_test_line_submission_order` 检查实际整包顺序与逆序合成输入的几何/UV/颜色守恒；`experiments/volume_3d_lab.gd` `_capture_sequence` 保留三处源端点与精确路口的0.26/0.65对照机位。

四处已审查公铁交叉：`experiments/volume_rail_crossings.gd` `records` 以同源整线接头轮廓裁交集；`experiments/volume_map_factory.gd` `build` / `_line_mesh` 同批提交8块16面，source回退不启用；`tests/test_volume_rail_crossings.gd` `run` / `_inside` / `_check` 核对原线路通道、裁切边界、地面与源漂移反例。`experiments/volume_3d_lab.gd` `_capture_crossings` 经AGL_VOLUME_CROSSING_QA同材质对拍三地区四缩放；`tests/desert_formal_entry_runner.gd` `_run` 比较正常菜单实际网格并拍近远六图；`tests/volume_relief_stress.gd` `_capture_sequence` 经AGL_VOLUME_CROSSING_PERF选择对应六区负载，不作屏幕FPS证明。

已审查的道路短断口：`experiments/volume_map_factory.gd` `road_presentation_points` 仅对原生沙漠两处白名单起点沿原切向接收道路，不移动源节点；`tests/test_volume_map_factory.gd` `_test_road_joins` 覆盖实际网格42采样、原网格断口和源漂移反例；`experiments/volume_3d_lab.gd` `_capture_sequence` 的AGL_VOLUME_ROAD_JOIN_QA在同一材质下对拍两处三缩放的原/修复网格；`tests/desert_formal_entry_runner.gd` `_run` 比较正常菜单实际路网顶点并拍两处断口。

铁路屏幕细节：`experiments/volume_map_factory.gd` `build` / `_line_mesh` / `configure_instance` 记录UV2铁路语义并按tactical启用；`resources/shaders/volume_map_line.gdshader` 通过实际像素导数连续过滤细节，独立route_coverage_enabled以二维横向UV导数长度减轻斜线过度削边；`tests/test_volume_map_factory.gd` `_test_rail_lod` 验证实际顶点标记/数量、两个开关与source/非卫星回退；`experiments/volume_3d_lab.gd` `_capture_rail_lod` 通过AGL_VOLUME_RAIL_LOD_QA进行两处铁路五缩放的开关同位截图，不计性能。

默认克制沙漠风格：`experiments/volume_desert_tactical_context.gd` `is_enabled` 是地表/主要建筑共用选择入口；`tests/test_volume_satellite_ground.gd` `run` 验默认启用、其他地图与显式回退；`tests/desert_formal_entry_runner.gd` `_run` 在无风格开关时断言真实菜单中的完整原生面、预热与临时视口释放。

沙漠载入阶段：`rendering/desert_map_preload.gd:33 eligible` / `start` / `take` / `_ready` / `_process` / `_switch_lod` / `_after_draw` / `progress` / `arm` / `_loading_exited` / `cancel` / `_exit_tree`；`survivor/building_preloader.gd` `_ready` / `_volume_progress` / `_finish` 沿用同一载入UI，东京会话之外按地图分派；`rendering/desert_volume_presentation.gd` `setup_formal` 将同节点prepared_map交给 `experiments/volume_world_probe.gd` `setup`，不再现场构图。`experiments/volume_satellite_ground.gd:87 rebind_native_source` 验来源/矩形并换正式弱引用，保留网格与材质；`experiments/volume_desert_tactical_context.gd:27 begin_build` / `step_build` / `finish_build` 只缓存数值与Resource，`build` 复用同一流程。`tests/desert_preload_lifecycle_case.gd` `run` / `_wait_ready` / `_check` 与 `tests/desert_preload_runner.gd` `_ready`，bench `desert_preload`；并入 `tests/lifecycle_gauntlet_runner.gd` `_run`，正常菜单另由 `desert_formal_entry` 检查真正GPU交接和载入文案。

### 正式二维绘制与共用反馈

| 功能 | 位置 |
|------|------|
| 飞机绘制入口 | `aircraft.gd:3697` _draw |
| 已审顶视 PNG、同型号复用、稳定三维身份与运行时换色；MQ-109/110/111 共用用户批准的 `mq109_family`，原创/特种显示名以独立规范 key 登记但未完成时仍保留旧绘制 | `aircraft_silhouette_catalog.gd` `TEXTURE_PATHS` / `DISPLAY_KEYS` / `LEGACY_DISPLAY_NAMES` / `LEGACY_MODEL_KEYS` / `canonical_model_key_for` / `canonical_model_key_for_display_name` / `canonical_model_keys` / `_texture_for` / `draw_icon` → `aircraft_renderer.gd` `draw_aircraft_icon`；二维来源 `resources/aircraft_silhouettes/`，三维矩阵 `resources/aircraft_volume_models/`；审计 `scripts/tools/audit_aircraft_silhouettes.py` / `scripts/tools/audit_aircraft_volume_models.py` |
| 滚转体积投影（暗色壳层 + 顶面/机腹；PNG 最多两次纹理提交；legacy 不归零） | `aircraft_renderer.gd:102 bank_volume_projection_for` / `:112 bank_volume_face_alpha_for` / `:1304 draw_aircraft_icon` → `aircraft_silhouette_catalog.gd:179 volume_thickness_for` / `:213 draw_icon`；回归 `test_aircraft_bank_volume.gd`；Visual/Perf `aircraft_bank_volume_visual` |
| 统一机型尺寸幂律 + 高度倍率 | `aircraft_renderer.gd:567 altitude_base_scale` / `:557 visual_model_scale`；真实尺寸字段 `aircraft_params.gd` |
| 指挥型图标 | `aircraft_renderer.gd:1534 draw_commander_icon` |
| 雷达锥绘制 | `aircraft_renderer.gd:805 draw_radar_cone` |
| 跨帧玩家机引用净化（HUD / 锁定线 / 绘制消费者） | `aircraft_renderer.gd` `safe_aircraft_ref` / `safe_player_ref`；`survivor/survivor_hud.gd` `_safe_player_aircraft`；终局断引用 `survivor/survivor_mode.gd` `_on_player_died` |
| 锁定框闪烁 + 屏幕空间恒定尺寸 | `aircraft_renderer.gd` `screen_space_inverse_scale` / `draw_lock_indicator` / `draw_lock_box` / `draw_secondary_lock_indicators`；地面/舰船/挂点调用同一补偿规则 |
| 真实在途导弹警告（一弹一线一三角；雷达共用判定） | `missile.gd` `incoming_warning_rule` / `is_incoming_warning_for` / `_draw_incoming_warning`；`survivor/survivor_hud.gd` `RadarDisplay` |
| 战斗单位统一矢量状态栏（飞机/无人机/地面/SAM/雷达/战略目标/舰船/导弹；共享英文 HDG/SPD/ALT/RNG/HP 数据契约；唯一屏幕空间覆盖层逐帧持有最终变换，单位不重绘也绝不随单位、父节点或镜头转动/缩放；玩家/僚机受伤整块蓝白反相；加力激活飞机显示 `AB`；非飞机所有状态合入同一信息牌，取消旧头顶进度条） | `ui/world_unit_status_overlay.gd` `_process` / `_draw` → `aircraft_renderer.gd` `install_status_overlay` / `clear_unit_status_panel` / `status_panel_overlay_transform_for` / `draw_registered_status_panels` / `draw_unit_status_panel` / `status_label_entries` / `status_heading_text` / `status_speed_knots_text` / `status_altitude_text` / `status_range_text` / `status_hp_text` / `english_status_identity`；地面/SAM/雷达内容 `_status_label_lines`，舰船 `_draw_status_label`，导弹 `missile.gd` `_draw_data_label`；格式与屏幕轴断言 `tests/test_presentation.gd`，不主动重绘单位的动态旋转 Visual `unit_status_label_visual` |
| 数据标签（完整） | `aircraft_renderer.gd` draw_data_label |
| 数据标签（生存模式简化） | `aircraft_renderer.gd` draw_data_label_minimal |
| 数据标签（剥离窗口 stretch 后按真实相机 0.35/0.40 简略档 + Alt 临时完整；玩家小队每架都显示纯机型编号 + 完整呼号，长机名后缀缩首字母） | `aircraft_renderer.gd` `label_lod_scale_for` / `label_lod_scale` / `next_compact_label_state` / `should_draw_compact_label` / `draw_data_label_compact` / `aircraft_model_designation` / `compact_aircraft_name` / `controlled_identity_label`；地面 `ground_unit.gd` `_should_draw_compact_data_label`，舰船 `naval/naval_unit.gd` `_draw_status_label` |
| 飞机旁数据标签近景避让与高速像素稳定 | `aircraft_renderer.gd` `unit_status_screen_offset_for` / `data_label_screen_offset_for` / `data_label_screen_offset`；5x 真实相机画面 `aircraft_label_visual`，跨兵种组合变换画面 `unit_status_label_visual` |
| 机头闪光 | `aircraft_renderer.gd:1140` draw_muzzle_flash |
| 加力火焰 | `aircraft_renderer.gd:1155` draw_afterburner_glow |
| 热诱弹粒子 | `aircraft_renderer.gd:1190` draw_flare_particles |
| 目标连线（玩家小队统一蓝，与机体 `icon_color/wing_color` 及当前操控权解耦；双击突击=独立黄线） | `aircraft_renderer.gd` `combat_target_line_color` / `draw_target_line` |
| 蓝色玩家小队简略档左上角全部装填武器矩形反相闪烁；完整档显示百分比 | `aircraft_renderer.gd` `draw_reload_indicators` / `reload_indicator_team_visible` / `reload_indicator_style` / `reload_indicator_tokens` / `secondary_reload_progress` |
| 飞机旁状态栏：FLR 弹尽装填行红/琥珀双色闪烁 | `aircraft_renderer.gd:615` _wpn_color（FLR_RELOAD） |
| 玩家 HUD：热诱弹十星投放/短冷却/长装填同步 | `survivor/player_instrument_panel.gd` flare_lit_star_count / _draw_flare_stars |
| 雷达小地图：来袭导弹常亮脉冲标记 + 警示牌/外圈；光学或传感器隐形敌机保留低亮度匿名位置环但不恢复火控；30+ 单位时 20 Hz、其它 30 Hz 重绘，扫线尾迹与 TGT 括号合批 | `survivor/survivor_hud.gd` `RadarDisplay` / `redraw_interval_for_unit_count` / `stealth_hint_contact_for` |
| 预测轨迹（360 步分为 15 × 24 步，显示 4:1 抽样，旧缓存持续显示） | `survivor/survivor_mode.gd` `_process` → `aircraft_renderer.gd` `update_predicted_path_cache` / `prediction_display_result` / `draw_predicted_path` → `aircraft/aircraft_physics.gd` `begin_player_path_prediction` / `advance_player_path_prediction` / `player_path_prediction_result`；回归 `tests/test_predicted_path_incremental.gd`（bench `predicted_path`） |
| 战术提示弹窗 | `aircraft_renderer.gd:2331 draw_tactic_popup` |
| 悬停雷达/机炮范围与机炮意图锥（任意阵营 hover 参考锥 / 敌方含 FFA 威胁锥 / 当前操控机急刹真实射界；炮艇为 360° 环；仅 Mother Goose 蜂群隐藏） | `aircraft_renderer.gd` `should_show_hover_radar_range` / `should_show_enemy_gun_threat` / `should_show_gun_reference` / `draw_gun_cone` → `aircraft.gd` `_update_gun_threat_indicator` |
| └ 威胁锥淡出系数（开火淡出 / 停火淡回） | `aircraft.gd:619` _gun_threat_fade |
| └ 淡出淡回时长常量 | `aircraft.gd:620` GUN_THREAT_FADE_OUT_TIME / `aircraft.gd:621` GUN_THREAT_FADE_IN_TIME |
| └ 每帧推进（威胁条件成立时按 is_firing 增减） | `aircraft.gd:3913` _update_gun_threat_indicator |
| └ 威胁条件中断复位（保留"立即归零防抖"语义） | `aircraft.gd:3916` _reset_gun_threat |

## HUD / UI

| 功能 | 位置 |
|------|------|
| 沙盒 HUD（**沙盒已废弃**，仅调试留存）| `hud.gd:7` _process |
| 生存模式 HUD 构建/更新与 F7 玩家 HUD 六档独立缩放（默认 `0.9×`，其它 UI `1.0×`） | `survivor/survivor_hud.gd` `_build_ui` / `_ensure_ui_root` / `set_player_hud_scale` / `snap_player_hud_scale` / `right_anchored_player_rect` / `_update_display` / `_update_player_instrument` |
| HUD 首次显现（空间顺序、`0.02s` 错峰、逐框 `0.50s` 两闪、动态取消） | `ui/hud_first_reveal_sequencer.gd`；`ui/hud_board_visibility.gd`；`survivor/survivor_hud.gd` `_setup_hud_first_reveal` / `_sync_hud_first_reveal_targets` |
| 屏幕外圈受伤/异常/治疗反馈（红 > 黄 > 绿；低于 ThreatOverlay；释放安全） | `survivor/damage_vignette.gd`；`aircraft.gd` `_apply_damage` 写受伤时刻；`survivor/survivor_hud.gd` `_build_ui` / `_process`；`tests/test_damage_vignette.gd`（bench `damage_vignette`） |
| 玩家/僚机受伤反馈（飞机旁状态栏整块与数字蓝白反相；右下角 HUD 不整体变色、仅对应 HP 红闪；导弹单发完整周期、机炮连续命中续窗不重置相位） | `aircraft.gd` `_apply_damage` 写 `status_bar_damage_started_at` / `status_bar_last_damage_at` → `aircraft_renderer.gd` `status_damage_flash_phase` / `status_damage_flash_phase_for` / `status_damage_panel_colors` / `draw_unit_status_panel`；玩家 HUD `survivor/player_instrument_panel.gd` `register_damage_event` / `damage_hp_color` / `hp_damage_regions`；僚机 HUD `survivor/survivor_hud.gd` `_update_squad_panel` → `survivor/wingman_instrument_panel.gd` `_sync_damage_rows` |
| 玩家模块化仪表（生产 HUD 与 F7 预览共用；401px 根宽、HP 上方云层/击杀状态、2u/3u 数字模板、ALT 反相档位与独立连续指针层、武器装填双读数） | `survivor/player_instrument_panel.gd` `AltimeterNeedleLayer` / `_configure_layout` / `update_status` / `altimeter_target_degrees` / `_draw_altimeter_gauge` / `_draw_altimeter_needle` / `decorative_aligned_width` / `weapon_reload_remaining_seconds` / `active_control_empty_rect` / `update_display` / `_draw` |
| 玩家 HUD 字号与动态扩格 | `ui/terminal_text.gd` `TerminalText`；`survivor/player_instrument_panel.gd` `_cached_text_layout` / `_configure_layout` 缓存并失效不变基准的字号；`_draw_font_text_in_rect` 分离布局/基线/绘制计时；小字 `resources/fonts/Silkscreen-Regular.ttf`，主要数字 `resources/fonts/ChakraPetch-Bold.ttf` |
| 唯一互斥 R 技能常驻百分比充能行 | `aircraft.gd` `equipped_r_maneuver_id` / `r_maneuver_cooldown_total` / `r_maneuver_cooldown_remaining`；`survivor/player_instrument_panel.gd` `_draw_maneuver_charge` |
| 独立 `1q` 操作键与手动 FLR 运行时插列 | `survivor/player_instrument_panel.gd` `grid_regions` / `debug_grant_manual_flare_skill` |
| 僚机动态行仪表（每行 `1q+7u × 3u`） | `survivor/wingman_instrument_panel.gd` `update_display` / `grid_regions` / `_apply_row_count` / `_draw_row` |
| 底部三方向点击格、`当前/8` 数字、等级/剩余经验与进化就绪侧板 | `survivor/milestone_axis_counter.gd` `update_display` / `axis_value_rect` / `point_rect` / `_draw`；`survivor/bottom_experience_panel.gd` `update_display` / `xp_remaining` / `evolution_ready_rect` / `flash_level_up` / `_draw` |
| UI 设计规范（主界面 + 玩家/僚机 HUD + 战斗单位状态栏 SSOT） | `docs/specs/systems/ui-design-guidelines.md` |
| 终端共享网格物理 1px 描边、重合边去重 multiline 与精确文字 | `ui/terminal_grid_overlay.gd` `SCALE_INVARIANT_LINE_WIDTH` / `outline_segments_for` / `ui/terminal_text.gd` |
| HUD 速度单位与线框色持久化 | `ui/hud_preferences.gd` `speed_unit` / `hud_color` / `set_hud_color` |
| 主菜单速度单位、音频与 HUD 色盘 | `main_menu.gd` `_refresh_hud_settings_buttons` / `_on_speed_unit_pressed` / `_on_audio_settings_pressed` / `_on_hud_color_pressed`；`audio/audio_settings_panel.gd` / `ui/hud_color_settings_panel.gd` 均走白色终端弹层 |
| 主菜单 Y2K 军用 CRT 与双栏终端布局 | `main_menu.gd` `_build_terminal_header` / `_build_system_panel` / `_add_mode_button` / `_refresh_terminal_palette`；`ui/main_menu_crt_shell.gd`；`ui/main_menu_crt_effect.gd` + `resources/shaders/main_menu_crt.gdshader`；`ui/main_menu_scope_display.gd`；`tests/main_menu_visual_qa_runner.gd`（bench `main_menu_visual`） |
| 规范后旧 UI 翻修共享管线 | `ui/terminal_page_shell.gd`（CRT/23u×30u）+ `ui/terminal_ui_style.gd`（白色线框/字体/反色控件）+ `ui/terminal_map_preview.gd`（静态线稿）；资料库、商店、选图、选机共用整页壳，音频/色盘/暂停/结算共用小板样式；`tests/ui_iteration_visual_qa_runner.gd`（bench `ui_iteration_visual ... Shadow Visual`） |
| HUD 字体 | `resources/fonts/Silkscreen-Regular.ttf`（1u/1q 拉丁信息）/ `ChakraPetch-Bold.ttf`（主要数字）；缺失字符走当前主题默认字体回退 |
| BOSS 系统入侵身份横幅 | `ui/boss_arrival_banner.gd` `show_identity/_apply_palette/set_reveal_progress/warning_reveal_progress/set_dismiss_progress`（5 窗严格逐个压入、主身份最后展开；默认终端绿 / Wraith 蓝黑电蓝 / Black Star 银黑橙；CSG 包装 `AN AWESOME WAVE`，Black Star 包装 `Blame it on the falling sky`）；身份/motto/palette 数据 `survivor/boss_registry.gd` `banner_metadata_for`；时序 `resources/presentation/sequences.json` 的 `banner` 通道 |
| 玩家 HUD 回归/可视验收 | `tests/test_player_instrument_hud.gd` `run`（bench `player_hud`）；`tests/player_hud_visual_qa_runner.gd`（bench `player_hud_visual`） |
| 五表本地化源、唯一性审计与 15 份资源构建 | `i18n/README.md`；`i18n/interface.csv` / `gameplay.csv` / `skills.csv` / `meta.csv` / `radio.csv`；`scripts/i18n_catalog.gd`；`scripts/tests/build_translations.gd`（bench `i18n_build`） |
| BOSS 横幅 / Debug 回归与可视验收 | `tests/test_presentation.gd` `_test_boss_banner_contract`（bench `presentation`）；`tests/boss_arrival_banner_visual_qa_runner.gd`（bench `boss_arrival_banner_visual`，含 Black Star）；`tests/boss_debug_select_visual_qa_runner.gd`（bench `boss_debug_select_visual`，Boss 选择 → T4 参考编队 → 实战 Tab build → 海洋 FINAL WAR → 沙漠列车真实进场与铁路中段） |
| 终端文字、轮廓缓存与共享网格回归 | `tests/test_terminal_text.gd` `run` / `_check_ink_bounds_cache` / `_check_dynamic_glyph_cache` / `_direct_ink_bounds`；bench `terminal_text` |
| 事件型冻结缓存/预热一致性回归（排版逐值对照、战区陆地记忆、ADBS 同种子、音频/模板常驻、轮廓、升级预热批次、3★ 威胁通知预热） | `tests/test_event_hitch_prewarm.gd` `run` / `_legacy_resolve` / `_legacy_pick_city_center` / `_test_notice_prewarm`；bench `event_hitch_prewarm` |
| UI Dev 定位框与玩家 HUD 缩放回归/可视验收 | `tests/test_ui_dev_outline.gd` `run`（bench `ui_dev_outline`，含正式 `_physics_process` 时间注入位置、战区时钟整数秒/BOSS 状态重绘门、六档吸附、默认 `0.9×`、零右边距轴心、其它 UI `1.0×` 隔离）；`tests/ui_dev_panel_runner.gd`（bench `ui_dev_panel_visual` / `ui_dev_panel_clean_visual` / `ui_dev_panel_manual_flare_visual` / `ui_dev_panel_scale_visual`，最后一项验证玩家 HUD 贴右 `0.5×` 物理 1px 描边且其它 UI 不缩放） |
| 升级 UI 选项展示 | `survivor_upgrade_ui.gd:323` show_choices |
| 进化树层间直角布线（布局期缓存） | `survivor/evolution_tree_view.gd:158` _build_edge_routes / `:196` _orthogonal_path |
| 进化树四状态线批绘 | `survivor/evolution_tree_view.gd:206` _draw / `:315` _draw_edge_batch |
| 进化树隐藏当前机永久不可达旁支 | `survivor/evolution_tree_view.gd:69` `_relevant_nodes`；`tests/test_evolution_detail.gd` `_test_tree_hides_unreachable_routes` |
| 进化选择前的当前机框/候选详情；成功后结束本次停靠 | `survivor/evolution_tree_view.gd:103` set_current + `survivor/evolution_ui.gd` `_on_tree_node_selected` + `survivor/survivor_mode.gd` `_on_settlement_evolution` |
| 调试面板构建 | `debug_panel.gd:41` _build_ui |
| 调试面板内容更新 | `debug_panel.gd:183` _update_content |
| 战斗策略文本 | `debug_panel.gd:336` _get_combat_strategy |
| 飞行员信息 | `debug_panel.gd:373` _get_pilot_info |
| 地面单位生成按钮 | `debug_panel.gd:703` _spawn_ground_unit |
| Game Over 显示 | `survivor/survivor_hud.gd:2171` show_game_over |

## 资源参数文件

> ⚠ **下表是早期基准资源的选摘，远非全量**。现在还有：
> `resources/player/`（41 架玩家机 + 分档热诱弹）· `resources/evolution/`（进化树）·
> `resources/weapons/` · `resources/naval/`（舰船）·
> `resources/chatter/radio_chatter.json`（无线电台词）·
> `resources/presentation/sequences.json`（演出时间线）· 以及 20 多个 `enemy_*.tres`。
>
> 敌机资源的准确对应看 [enemy-index.md](enemy-index.md)；
> 参数数值看 [resources-catalog.md](resources-catalog.md)。

| 资源 | 文件 |
|------|------|
| F-16 早期基准（**非当前玩家起手机**） | `resources/default_fighter.tres` |
| MiG-29（敌方） | `resources/enemy_fighter.tres` |
| J-7 截击机 | `resources/enemy_interceptor.tres` |
| MQ-109（机炮无人机） | `resources/enemy_uav.tres` |
| MQ-110（导弹无人机） | `resources/enemy_uav_missile.tres` |
| F-4E（前期导弹杂鱼） | `resources/enemy_f4e.tres` |
| Sentinel 指挥机 | `resources/enemy_uav_commander.tres` |
| A-7 攻击机 | `resources/enemy_a7.tres` |
| A-7 机炮 | `resources/a7_gun.tres` |
| A-7 火箭弹 | `resources/a7_rocket.tres` |
| Q-5 攻击机 | `resources/enemy_q5.tres` |
| Q-5 机炮 | `resources/q5_gun.tres` |
| Q-5 火箭弹 | `resources/q5_rocket.tres` |
| Probe 侦察机 | `resources/drone_probe.tres` |
| M61A1 机炮 | `resources/default_gun.tres` |
| ZU-23 高炮 | `resources/aa_gun.tres` |
| UAV 机枪 | `resources/uav_gun.tres` |
| AIM-7M 导弹 | `resources/default_missile.tres` |
| AGM-65 对地导弹 | `resources/agm_missile.tres` |
| HQ-7 防空导弹 | `resources/sam_missile.tres` |
| UAV-SAM 导弹 | `resources/uav_missile.tres` |
| 战斗风格 | `resources/default_combat.tres` |
| 热诱弹 | `resources/default_flare.tres` |
| SAM 单位 | `resources/sam_params.tres` |
| AAA 单位 | `resources/aa_gun_params.tres` |
| 雷达站 | `resources/radar_station_params.tres` |
| 空爆高炮 | `resources/airburst_aa_params.tres` + `resources/airburst_aa_gun.tres` |
| 战略硬目标 | `resources/strategic_target_params.tres` |
| 友军 B-1B | `resources/friendly_b1b.tres` |

## 场景文件

| 场景 | 文件 | 节点树 |
|------|------|--------|
| 生存模式（**主玩法**） | `scenes/survivor_mode.tscn` | SurvivorMode + BulletManager + MissileManager + Camera2D |
| 沙盒主场景（**已废弃**，仅调试留存） | `scenes/main.tscn` | Main + BulletManager + MissileManager + Camera2D + PlayerAircraft + DebugPanel |
| 飞机模板 | `scenes/aircraft.tscn` | Aircraft (Node2D + aircraft.gd) |
| 导弹模板 | `scenes/missile.tscn` | Missile (Node2D + missile.gd) |
| SAM 单位 | `scenes/sam_unit.tscn` | SAMUnit + sam_params |
| AA 单位 | `scenes/aa_gun_unit.tscn` | AAGunUnit + aa_gun_params |
| 空爆 AA 单位 | `scenes/airburst_aa_unit.tscn` | AirburstAAUnit + airburst_aa_params |
| 战略硬目标 | `scenes/strategic_target.tscn` | StrategicTarget + strategic_target_params |
| 雷达站 | `scenes/radar_station.tscn` | RadarStation + radar_station_params |
| 主菜单（**入口场景**） | `scenes/main_menu.tscn` | MainMenu |
| 机型选择 | `scenes/survivor_select.tscn` | SurvivorSelect |
| 地图选择 | `scenes/survivor_map_select.tscn` | 生存流程第一步；共享 CRT 白色终端五卡 + 静态地图线稿；B → boss_debug_select |
| BOSS 测试场 | `scenes/boss_debug_select.tscn` | Boss/场景选择 → 7 个 T4 四机以上同型编队 → 节点等级匹配的正式随机 ACE 武器 + gates 技能 build；战斗中 Tab 核对武器、技能与里程碑 |
| 地图编辑器 | `scenes/map_editor.tscn` | UGC |
| 手画地块参考 | `scenes/map_manual.tscn` | @tool 编辑器预览 |

## ROE / 阵营 / 第三方（2026-07-12，spec global-awareness-roe）

- **敌我判定唯一 API**：combat_unit.gd `is_hostile_to()` / `teams_hostile()` / `is_player_squad()`（team 0=PLAYER 1=HOSTILE 2=ALLY；散写 team 直比已收口禁止回潮）
- **动态阵营原子事务**：events/faction_transition.gd `convert()`（统一清 IFF/目标/锁定/旧小队/在飞弹药/任务身份并发 `faction_changed`）；events/ally_force.gd 是兼容包装。
- **WhiteTea 投降**：events/ace_reinforcement_event.gd `should_whitetea_surrender()` / `_try_whitetea_surrender()` / `_tick_surrender_egress()`；2→1 当帧按击破结算，幸存者本人播 `whitetea_surrender`。
- **激光黑客**：equipment/laser_equipment.gd `_select_hack_focus()` / `_advance_hack()`；survivor/hacked_ally_force.gd 负责被黑 MQ 跟随当前长机与切控重绑；技能配置 `survivor/survivor_data.gd` `skill_laser_hack`。
- **阵营转换运行时回归**：tests/test_faction_conversion.gd `_test_laser_hack_runtime_conversion()` / `_test_squad_cleanup_skips_freed_successor()`；必须真实越过 2.5s 黑客完成门，并覆盖 `Array[Aircraft]` 缓存清理与已释放继任引用。
- **感知门**：ai_controller.gd `_roe_allows_scored_engage()`（TS_SCORED 专用；读 roe_posture / roe_aware_until / roe_zone_* meta）
- **察觉/姿态/热度**：survivor/roe_director.gd（写 meta 的唯一方；2s 感知 tick + 1s 热度 tick）
- **Encounter Director / 压力账本**：survivor/encounter_director.gd（2Hz Presence/PR、Recovery、Global admission、Lethal Slot；`opening_garrison_size_for` 令 N≥4 的唯一开局驻防稳定为三机完整 Element）→ survivor/survivor_spawner.gd `_try_spawn_global_package`（Package→Element→Squad 原子生成、无 Spawn Debt）/ `_spawn_opening_garrison`；任务/ACE 终态在 survivor_mode / ace_reinforcement_event 转发恢复窗。
- **编队优先攻击**：ai/squad_coordination.gd `process_squad_follow` 保留 `SQUAD_FOLLOW` 并标记 `TACTIC_FORMATION_ASSAULT`；aircraft/aircraft_weapons.gd `update_formation_opportunity_weapons` 在阵位复用严格机炮/导弹许可；普通敌机最终攻击在 `_emit_missile` / `update_gun` 查询 Lethal Slot。
- **主题遭遇包**：survivor/survivor_spawner.gd `_spawn_snowblind_squad/_spawn_deadair_squad` 为支援核心+独立双机 `ESCORT_SCREEN`，`_spawn_commander_squad/_ensure_sentinels_escorted` 固定验证 Sentinel `1+5+1`；focused `spawn_pool` 真实实例化对拍。
- **hunter 配额**：survivor_spawner.gd `_update_hunters`（配额 = `_roe.hunter_quota()`，整队抽调）
- **第三方事件**：events/ally_force.gd + awacs_support_event.gd（护送直升机事件 `escort_convoy_event.gd` 已于 2026-07-28 删除）；机场解放后 ALLY 基础 AA×2 + MetaShop 永久授权 SAM 渐进部署 survivor_mode `airfield_ally_plan` / `_try_deploy_airfield_sam` / `_deploy_airfield_ally_gradual`（spec airfield-liberation-zones + airfield-sam-network）；调度 `_update_ally_events`
- **AWACS 支援事件**（2026-07-28 改造：绕战区轨道 + 定时撤离 + 进离场无线电）：

| 功能 | 位置 |
|------|------|
| 轨道中心选取（选中战区 → 最近 AVAILABLE 战区 → 兜底南带） | `events/awacs_support_event.gd:172` _pick_orbit_center |
| 到点转撤离（航点改到南界外，飞出/超时即 end） | `events/awacs_support_event.gd:158` _begin_egress |
| 进离场无线电（trigger `awacs_onstation` / `awacs_egress`） | `events/awacs_support_event.gd:204` _say |
| 在站时长 / 撤离兜底 | `events/awacs_support_event.gd:23` ON_STATION_S / `events/awacs_support_event.gd:25` EGRESS_TIMEOUT_S |
| 轨道几何常量（退避 / 半程 / 边界余量，退避须 < BUFF_RADIUS_PX） | `events/awacs_support_event.gd:28` ORBIT_STANDOFF_PX / `events/awacs_support_event.gd:30` ORBIT_HALF_SPAN_PX / `events/awacs_support_event.gd:32` ORBIT_MARGIN_PX |
| buff 半径（锁定×3 / 导弹 G ×1.25 的作用域） | `events/awacs_support_event.gd:16` BUFF_RADIUS_PX |
| 主战场海绿范围层（静态画布随父机移动；结束当帧隐藏） | `survivor/support_range_overlay.gd` `setup` / `_draw`；`events/awacs_support_event.gd` `_start` / `_finish` |
| Tab 图光环圈绘制 | `survivor/tactical_map.gd` _draw_dock_markers AWACS 分支 |
- **阵营色板**：game_constants.gd FactionPalette（COL_FRIEND_PLAYER/ALLY、COL_ENEMY_REGULAR/ELITE + 全部 team_* 函数三分支）

## 表演/演出（转场·镜头·时间·剧情演出）

- **总入口**：编排手册 [cinematic-authoring.md](cinematic-authoring.md)（BOSS 横幅→镜头→接战量产流水线 + 通道/op 全参考 + ctx 契约 + 陷阱表）；设计权威 spec [systems/ui-transition.md](../specs/systems/ui-transition.md)
- 导演/通道分发/遮罩/热重载 → `scripts/presentation/presentation_director.gd`
- BOSS 身份横幅（5 层警告窗/名称/角色/呼号/motto/palette）→ `scripts/ui/boss_arrival_banner.gd`；元数据 `scripts/survivor/boss_registry.gd banner_metadata_for`
- 时间缩放与暂停（唯一写入口，含命令轮盘收编）→ `scripts/presentation/time_authority.gd`；轮盘接线 `scripts/rts/command_wheel.gd _activate/_reset/_exit_tree`
- 演员走位/尾迹/演出隐身/虚拟环境所有权 → `scripts/presentation/cinematic_cast.gd`；bind/release 期间真实战斗传感器隐形冻结并绕过；指令消费端 `scripts/ai_controller.gd _directive_follow_path_step`（`target_speed`/`arrive_radius` 参数）
- 空舞台隔离 → `scripts/presentation/stage_isolator.gd`
- 镜头电影层（`_base_zoom` 拆分/cine_target 跟随/暂停期代泵）→ `scripts/camera_controller.gd`
- BOSS 登场接入样板 + 收尾钩子 → `scripts/events/boss_encounter_event.gd _try_play_arrival_cinematic / _on_arrival_cinematic_done`
- 升级急刹接入 → `scripts/survivor/survivor_mode.gd _on_player_leveled_up / _on_upgrade_selected`；面板协议 `survivor_upgrade_ui.gd get_transition_elements`
- 演出台词时长覆写/ambient 压制 → `scripts/survivor/radio_chatter.gd set_duration_override / suppress_ambient`
- 演出配乐幂等 → `scripts/audio/audio_manager.gd current_music_id`

## 2026-08-04 战区奖励与新技能

| 功能 | 位置 |
|---|---|
| 奖励类别/武器权重、航母第 4 次 pity、起始机型 ×2 偏置 | `survivor/zone_data.gd` `REWARD_KIND_WEIGHTS` `REWARD_WEAPON_WEIGHTS` `_assign_reward` |
| ESM 3000m 光环扫描 | `equipment/esm_pod_equipment.gd` `update`；`aircraft.gd` `esm_*_multiplier` |
| ESM 主战场蓝色范围层（淡填充 + 描边） | `aircraft_renderer.gd` `support_range_fill_color` / `support_range_ring_color` / `draw_esm_aura` |
| ESM 锁定 / reload 消费 | `survivor/survivor_mode.gd` 锁定循环；`aircraft/aircraft_weapons.gd`；`aircraft/aircraft_flares.gd` |
| 连锁弹头直穿与逐目标去重 | `missile_manager.gd` `_physics_process`；`missile.gd` `continue_after_penetration` `already_penetrated` |
| 炮艇模式 / 重型机炮 | `survivor/survivor_player.gd` `apply_upgrade`；`aircraft/aircraft_weapons.gd` `auto_gun_scan`（全队独立；射程内玩家点名 / MountTarget 优先，否则最近 Aircraft/GroundUnit）、`update_gun`（整梭目标锁存）、`_fire_gun_round`（炮口随射向）、`update_ciws`（独立正面锥）；`aircraft_renderer.gd` `draw_gun_cone` |
| Hunter 突击触发与生命周期 | `survivor/skill_hooks.gd` `try_trigger_j36_assault`；`aircraft/aircraft_physics.gd` effective accessors；`aircraft.gd` 伤害管线 |
| 入侵算法 / 逃离 | `survivor/skill_hooks.gd` `on_player_jam_landed` `on_player_fear_landed`；`survivor/survivor_spawner.gd` `grant_flee_neutralization_xp` |
| X-44 机炮贯穿 | `bullet_manager.gd` `spawn_bullet` `_physics_process`；`aircraft.gd` `gun_bullet_penetration_active` |

## 2026-08-08 图2/图3空地图试飞

| 功能 | 位置 |
|---|---|
| 内置地图数据 | `resources/maps/desert_railway_preview.aglmap` / `ocean_islands_preview.aglmap`：64×64 km MapDocument（旧 60km 核心布局不变），zones 为空；沙漠仅右侧 Newman 城区 15 体块炼油厂（中心约 `(4800,400) px`），海洋仅西北孤岛 16 体块火箭基地与 1 条配套跑道，另定义地理、云、出生点、palette、`tile_map_key` 与 bbox metadata |
| 正式栅格底图 | `resources/maps/basemap_tiles/{desert,ocean}/manifest.json` + lossless WebP 三档；原始/增强 PNG 已在瓦片毕业后从仓库删除，manifest 保留源文件名与 SHA-256 provenance |
| 选图与空场守卫 | `survivor/survivor_map_select.gd` `MAP_LIST` / `_on_map_selected` → `survivor/survivor_mode.gd` `_ready` / `_physics_process` / `archive_enabled`；预览图不构造 ZoneData/ZoneMission，不推进 Spawner/BOSS/阶段计时 |
| 主图与 Tab 同源色板 | `survivor/map_feature_renderer.gd` `ugc_palette` `_ugc_color`；`survivor/tactical_map.gd` `ugc_palette` `_map_color`，UGC 模式禁用东京湾专属 Aqua-Line |
| 正式底图失败反馈 | `survivor/map_feature_renderer.gd` `basemap_load_failed` / `_report_basemap_error` → `survivor/survivor_mode.gd` `_on_basemap_load_failed` / `_show_basemap_error`；正式图 fail-open 到矢量层并显示本地化红色 toast，UGC 纯矢量不误报 |
| 栅格上方机场覆盖 | `survivor/map_feature_renderer.gd` `_draw_ugc_airports` / `survivor/tactical_map.gd` `_draw_ugc_airports`：仅 UGC/内置预览图把 MapDocument 跑道静态绘制在底图上方；Tab 几何按面板尺寸缓存，东京湾不重复描画 |
| 港湾羽田跑道覆盖 | `survivor/map_geography.gd` `HANEDA_RUNWAYS` 存冻结 OSM 四跑道中线/宽度；`survivor/map_feature_renderer.gd` `_draw_haneda_airport` 静态叠在正式瓦片上方；`survivor/tactical_map.gd` `_rebuild_haneda_runway_cache` / `_draw_haneda_airport` 以独立八端点缓存绘制 Tab，不作用于图2/图3或任务判定 |
| 预览建筑透视守卫 | `survivor/survivor_mode.gd` `_ready`：MapDocument 预览将 `BuildingRenderer.perspective_k` 设为 `0.015`，防止低缩放时远处侧墙拉成长方块；东京湾保持默认值 |
| 载入与空场探针 | `bench/bench_runner.gd` `PREVIEW_BENCH_MAPS` + 东京默认图分支；`map_raster_tokyo/desert/ocean` 抓中央完整 viewport；`map_boundary_crop_tokyo/desert/ocean` 把相机置于右下内容极限并使用 `ZOOM_MIN=0.2`，逐图证明缩放时不采到底图外黑边 |

## 2026-08-22 三图 lossless WebP 正式底图

| 功能 | 位置 |
|---|---|
| 权威 spec | `docs/specs/systems/raster-basemap-streaming.md`：东京湾/沙漠/海洋统一按 `tile_map_key` 消费正式瓦片；旧 PNG 与 A/B Debug 页已获授权删除 |
| 三档离线数据 | `scripts/tools/build_lossless_basemap_pyramid.py` → `resources/maps/basemap_tiles/{tokyo,desert,ocean}/manifest.json`：Strategic 1520²、Operational 7680² 8×8、Detail 8704² 9×9；1024px 瓦片内容 + 16px gutter，lossless WebP 复解码像素 mismatch=0；工具默认只写 `tmp/`，支持 `--operational-only` / `--strategic-only` 复制基线并只重建一档，1520 为七档消融后仍满足 68 MiB 的最高质量点；`build_shared_blue_noise.py` 另生成不含地图内容的 64² L8 共享颗粒纹理 |
| 静态颗粒 profile | `raster_basemap_renderer.gd.make_material` 从每图 `style_profile` 一次性写入 `noise_strength=0.014` 与 `grain_repeat=64`；共享蓝噪声只采样一次、无 `TIME`。V33 的 `48/32` 真机消融因三图低频误差与结构 F1 单调恶化被否决 |
| 主地图静态 streaming | `survivor/raster_basemap_renderer.gd` `setup` `set_active` `debug_state` `make_material` `_tile_candidates` + `shaders/basemap_streamed.gdshader`：Strategic `0.08…0.10`、Detail `0.20…0.24` 迟滞，使主要战斗 `0.26` 使用原尺寸层，Operational `0.18` 仍独立验收；实际 Canvas 逆投影视口四边形选格/分离轴过滤，覆盖检查在 `tests/test_volume_tile_visibility.gd` `run` / `_check`；manifest 静态采样/低频补偿、0.40s 目标层置顶覆盖淡入与 CanvasItem `COLOR/modulate` 生效；全部可见格优先、跨大档 Strategic 桥接、request 4/tick、bind 2/tick、12 格 LRU/16 格硬门；不在 `_draw` 扫描或持续 redraw |
| 正式 shader 同源风格 | `resources/shaders/basemap_streamed.gdshader`：复用正式 saturation/brightness/contrast/tint/Sobel 参数；Strategic/Detail `edge_gain=1.15/1.20`，Operational 按图使用东京/沙漠 `1.17`、海洋 `1.15`；grain 以世界 `map_uv×64` 采样共享蓝噪声 mip，不使用 `TIME`/fragment hash，不预烘进地图像素 |
| 主图/Tab 正式接线 | `map_feature_renderer.gd` `_prepare_raster_basemap`；`tactical_map.gd` `_ensure_raster_basemap`：官方三图直接按 key 读取 manifest，Tab 复用 Strategic + 固定乘色，无第二份 SubViewport/shader；`Shift+F8` A/B 已删除 |
| 内置三图接线与 UGC 边界 | `survivor_mode.gd` / `map_feature_renderer.gd`：东京湾、沙漠铁路、海洋群岛识别各自 manifest；外部 UGC 可 vector-only 或自带 PNG，禁止误加载官方 raster 内容 |
| 正式 Visual/载入 QA | `map_raster_{tokyo,desert,ocean}` Visual bench 使用同一天气种子抓取三张真实 Survivor viewport，覆盖玩家、HUD、天气、玩法建筑、机场与正式瓦片共同合成 |
| S3 地图性能门 | `survivor_mode.gd` 的 `map_raster_operational_stress`、`map_raster_stress`、`map_raster_detail_stress` 分别固定 `0.18/0.26/0.80`，峰值约 52 架/45 敌；`map_raster_transition_stress` 每 `0.8s` 在 `0.06/0.18/0.26` 三档循环。当前裁定须按 performance-guidelines 与 C1 组合复核，冷启动另记；稳态纹理约 `59.87 MiB`，16 格硬上限约 `76.89 MiB` |

## 2026-08-05 纯矢量地图游戏内预览（V45 冻结研究档案）

| 功能 | 位置 |
|---|---|
| V20 中远景自包含矢量数据 | `scripts/tools/build_vector_preview_data.py` → `resources/maps/tokyo_bay_vector_preview.json`；Operational 密度/建筑为 `tokyo_bay_operational_density.agod.gz` / AGOB v2 `tokyo_bay_operational_buildings.agob.gz`（51,121 大型 + 85,403 中型 + 176,738 小型面积守恒方向体块）；`bake_tokyo_bay_operational_roads.py` 从本地 PBF 生成 15,431 条分区限额街区骨架 `tokyo_bay_operational_roads.agor.gz`，运行时合入既有 packet |
| V21 近景实际高度地标 | `scripts/tools/bake_tokyo_bay_landmark_walls.py` 从本地 PBF 的 `height` / `building:levels` 生成 `resources/maps/detail_landmark_walls/*.aglw.gz` 与 `tokyo_bay_landmark_walls.json`；`MapDetailVectorRenderer._merge_landmark_wall_packet` 在 loading/安全暂停合入既有 large wall packet，缺包回退 8px 低浮雕，不增加 draw call |
| V23 Detail 统一色阶 | `survivor/map_detail_tile_cache.gd` `DETAIL_COLOR_LIFT = Color(1.25, 1.25, 1.24)`；只乘缓存 Sprite RGB，1.40 倍因接缝峰值超门已否决 |
| V25 单层真实街巷 | `tools/bake_tokyo_bay_operational_roads.py` 以 45/75/3/4 分区配额输出 18,874 条、52,633 线段；`map_vector_preview_renderer.gd` neighborhood 仅合入 `road_core`，不复制 casing，Operational 23 draw calls / 1,512,402 三角 |
| V26 中景建筑层次 | `map_vector_preview_renderer.gd` `_add_operational_buildings` / `_add_operational_building_casings`：small 柔和填充，medium/large 外扩 2.1 world px 合批冷暗 casing 后覆盖浅屋顶；Operational 24 draw calls / 1,785,450 三角 |
| V27/V28 远中景概括与性能门 | `map_vector_preview_renderer.gd`：Strategic/Tab 省略全部 AGOB；Operational 只提交 51,121 个 large 屋顶及 casing，中小建筑由 density mass/街区骨架与近景 AGDT 接管，24 draw calls / 1,090,362 三角；`map_visual_qa_runner.gd` 从真实 1024² `LOD_TAB` SubViewport 采集快照 |
| V29 全图视觉覆盖门 | `tests/map_detail_atlas_qa_runner.gd` + `scenes/tests/map_detail_atlas_qa.tscn`：逐格走生产超采样缓存并叠加世界对齐 Operational base，审计 203/203 格与 30 条边界；`bench_runner.gd` 注册显式 Visual 场景，不滚入 `all` |
| V30 静态高层层级 | `bake_tokyo_bay_landmark_walls.py`：普通楼投影仍封顶 52px，仅真实高度 `>=80m` 的少量地标按分段曲线放宽到 122px；投影 bbox 参与跨瓦片分配。6,371 栋 / 186,698 三角 / 1,560,988 bytes，合入既有 wall packet、无新增 draw call |
| V31 高层顶面 | 同一离线工具只为 669 栋真实 `>=80m` 高层耳切 7,291 个偏移顶面三角；米灰顶面 + 实体墙避免悬浮碎片。AGLW 总计 193,989 三角 / 1,603,641 bytes，仍合入既有 packet、无新增 draw call |
| V32 高层屋顶 casing | 同一耳切顶面先画全尺寸冷暗 casing、再画约 1.6px 内缩米灰屋顶；669 栋共 14,582 顶面三角，AGLW 总计 201,280 三角 / 1,657,080 bytes，仍无新增 packet/draw call |
| V40 跨尺度渐进门 | `map_vector_preview_renderer.gd` `_update_operational_feature_opacity`：主地图保持单一不透明 Operational 根；既有 mass/roof/depth packet 分别在 0.18–0.58 / 0.24–0.58 / 0.34–0.74 渐变，完整 Detail 0.50–0.98 感知淡入；不增加几何、draw call 或战斗期 bake |
| V34 整图风格预算门 | `tests/map_detail_atlas_qa_runner.gd` `_atlas_style_metrics`：203 格真实 GL atlas 同时阻断非空格亮度超出 90–146 或单格超过 1,400,000 三角，并报告最暗/最亮/最重格；不逐格调色、不抹平城乡差异 |
| V35 整图色偏门 | `tests/map_detail_atlas_qa_runner.gd` `_thumbnail_stats` / `_atlas_style_metrics`：记录每格 mean RGB，并要求 `G-R=3–12`、`B-G=-10–-1`，阻断发红、发蓝或通道错误；只运行于 Visual QA |
| V36 战区抵达走廊 | `survivor_mode.gd` `_zone_cruise_edge` / `_detail_corridor_region` + `map_detail_tile_cache.gd` `region_plan`：预热与巡航复用同一近侧抵达点；12 格截断先保留可用的抵达点/圆心瓦片，再按中点距离填充；出生区和全部正式战区四向入口由 `map_gold_slice` 回归 |
| V40 无断层视口预热 | `survivor_mode.gd` `_detail_path_view_regions` → `map_feature_renderer.gd` `prewarm_detail_regions` → `map_detail_tile_cache.gd` `bake_regions` / `_refresh_viewport_coverage`：入口/中点/圆心真实视口并集整批装入，超 12 格完整回退；纯海域 0 格成功保持 Operational；当前视口缺格时 Detail 整层渐退 |
| V40 Operational 伪立体楼 | `map_vector_preview_renderer.gd` `_add_operational_building_walls`：51,121 个 large 方向体块统一东南偏移，合入 1 个静态 wall packet；侧墙/casing 与屋顶分阶段、限透明度渐入，避免作战档实心大色块 |
| V41 共享游戏地标与功能色 | `survivor_mode.gd` `_sync_shared_map_gameplay_layers`：PNG/候选两侧始终显示同一 189 组横滨 `BuildingRenderer` 假 3D 地标，视觉与阻挡一致；`map_vector_preview_renderer.gd` `_add_operational_density` / `_build_packet_definitions`：城区、植被、工业使用低饱和分色，工业/停机坪并入既有 mass packet，Operational 24 draw calls / 1,192,604 三角 |
| V43 常驻高层与纸模色块 | `bake_tokyo_bay_operational_landmarks.py` → `tokyo_bay_operational_landmarks.aglw.gz`：669 栋真实 `>=80m` 高层、29,688 三角、227,154 bytes gzip；`MapVectorPreviewRenderer._add_operational_landmarks` 合为 alpha 1 的静态 `landmark` packet。`bake_tokyo_bay_context_relief.py` 离线生成 360 块不规则 6–8 边、非同心三层台地（灰绿 139 / 冷灰 57 / 灰褐 164），按视觉 water 边界精确拒绝相交；Operational 最终 26 draw calls / 1,240,237 三角，水面命中 0 |
| V44 暖灰纸板总平面 | `map_vector_preview_renderer.gd` 的 density/context/relief 锚点统一满足暖纸色序，以明度替代蓝/绿/橙功能分色；`bake_tokyo_bay_context_relief.py` 将台地改为 220 块、1.1k world px 宏观采样与 320–700px 半径，保留呼吸区。`test_map_vector_preview.gd` 守住色族与 `0.02..0.08` 类别距离；Operational 26 draw calls / 1,236,202 三角，`terrain_context` 14,496 三角、水面命中 0 |
| V39 三档调色与边缘阴影 | `map_vector_preview_renderer.gd` `_sea_color` / `_land_color` / `_urban_color` 与 `map_detail_vector_renderer.gd` 既有 coast/building packet：只调 LOD palette/alpha、描边宽度和统一阴影偏移，不新增地图内容、draw call 或三角；制作顺序见 `vector-map-production-playbook.md` §3.1 |
| V38/V41 完整网格与真实建筑对照 | `test_map_gold_slice.gd` 审计完整 16×16 网格并精确锁定 `detail_10_06` / `detail_14_04` 两个海岸边缘空格；`map_detail_atlas_qa_runner.gd` 报告 256 格分类；`map_visual_qa_runner.gd` 在 PNG 与候选两侧加载同一正式 `BuildingRenderer` 189 街区，并对拍两个显式空格 |
| 冻结研究制作规则 | `docs/reference/vector-map-production-playbook.md`：保留金样优先、三档信息预算、建筑层级、全格分类、静态预热、自主多轮迭代与成对性能门；当前不授权东京湾 PNG 退休 |
| 四档静态 triangle-array renderer | `survivor/map_vector_preview_renderer.gd` `setup` `prewarm_lod` `update_lod` `_build_packet_definitions`；组包/提交复用 `rendering/canvas_triangle_packet.gd`，v7 主图固定 Operational 单根，Tab 强制 LOD_TAB；自交主水环回退 `_triangulate_polygon` → `Geometry2D.offset_polygon` 拆环 |
| 已否决的整图淡入/规则道路格 | `docs/specs/systems/pure-vector-map-preview.md` v7；运行时代码已移除，禁止用 alpha 双根或规则网格冒充连续 zoom / 城市肌理 |
| loading 主图+Tab 预热 | `survivor/building_preloader.gd` `_process` → `MapVectorPreviewRenderer.prewarm_lod`；正式场景缓存命中后绑定约 0–1ms |
| loading 事件型一次性冻结提前（音乐/引擎声、战区陆地可用性、王牌模板、机型轮廓、升级弹窗中文字形按真实视口缩放透明绘制、3★ 威胁横幅/解除提示字形经离屏真实 ZoneHint 绘制） | `survivor/survivor_runtime_prewarm.gd` `begin` / `_process` / `music_ids_for_map` / `_request_audio` / `_step_upgrade_text` / `tier3_notice_texts` / `_step_notice_text`（文案来源 `survivor/survivor_mode.gd` `_on_tier3_threat_changed` / `_tier3_profile_name`），由 `survivor/building_preloader.gd` `_ready` 挂载、`_process` 在自身预载就绪后 `begin` 并等待 `is_done`；`survivor/zone_data.gd` `prewarm_zone_land`；`survivor/ace_support_squad.gd` `prewarm_templates`；`aircraft_silhouette_catalog.gd` `prewarm_textures` |
| 主地图 PNG/矢量 A/B | `survivor/map_feature_renderer.gd` `_prepare_vector_preview` `set_vector_preview_enabled` |
| Tab 1024² 一次性矢量快照 | `survivor/tactical_map.gd` `set_vector_preview_enabled` `_draw_minimap_vector_preview` |
| debug 同步开关与失败回滚 | `survivor/survivor_mode.gd` `_toggle_map_vector_preview` `_sync_shared_map_gameplay_layers`；`Shift+F10`，底图切换不隐藏共享假 3D 游戏地标 |
| 数据/cache/LOD/packet 预算回归 | `tests/test_map_vector_preview.gd`；`bench/run.cmd map_vector_preview 5 120 Shadow` |
| 真实 GL Compatibility 对拍 | `tests/map_visual_qa_runner.gd`、`tools/map_visual_qa.py`；`bench/run.cmd map_visual_qa 1 900 Shadow Visual`；V44 固定机位、六档、滚轮落点和 0.02 扫频均通过，PNG 与候选使用同一共享游戏大楼层；`contact_sheet.png` / `progression_sheet.png` 产物仅在 `tmp/map_visual_qa/analysis/`，PNG 继续承担色板与近景层次并排对照 |
| 横滨 4×4 km style 金样 | `tools/bake_yokohama_gold_slice.py` → `resources/maps/yokohama_gold_slice_preview.json`；15,601 栋 OSM 建筑 + landuse/rail/waterway/port；profile `yokohama_gold_v5_locked` |
| 全图 detail 生产与打包 | `tools/bake_tokyo_bay_full_detail.py` 在 `.gdignore` 的 `tmp/full_map_detail/detail_tiles_source/` 生成约 995 MB 构建 JSON；`tools/pack_tokyo_bay_detail_tiles.py` → `tokyo_bay_detail_tiles_full.json` + 199 个非空 `detail_tiles_packed/*.agdt.gz`（约 154.9 MB）。raw JSON 禁止进入 `resources/` |
| detail 一次性瓦片缓存 | `survivor/map_detail_tile_cache.gd`：3072²→1536² GPU 两级线性降采样、4 px 仅过滤外挤、12 格 LRU ≤110 MiB；zoom 0.50–0.98 的 1.75 次幂曲线直接求值，覆盖完整度单独用 `_coverage_alpha` 平滑，最终相乘以消除滚轮亮度滞后；战斗中禁止烘焙/readback，未驻留区保持 Operational |
| 跨战区 detail 安全预热 | `survivor/survivor_mode.gd` `_on_zone_selected` `_prewarm_zone_detail` → `map_feature_renderer.gd` `prewarm_detail_region` → `map_detail_tile_cache.gd` `bake_region`；`tactical_map.gd` `set_detail_prepare_in_progress` 在真暂停中锁住点击/关闭，恢复战斗后 streaming 仍为 false |
| 任意 Tab 航点 detail 安全预热 | `survivor/survivor_mode.gd` `_on_nav_point_selected` 先 await `_prewarm_nav_detail`，以航点为中心预热 4.4 km 方区，成功或回退后再 `command_move`；复用 TacticalMap 同一真暂停事务，战斗主画布不触发 |
| 瓦片/矢量同负载性能门 | `survivor/survivor_mode.gd` `MAP_BENCH_SCENARIOS`；`bench/run.cmd map_raster_stress 120 300 Shadow Visual` / `map_vector_stress`；两侧包含共享 `BuildingRenderer` |
| V46 最终生产裁决 | `docs/specs/systems/pure-vector-map-preview.md`：用户整图视觉验收未通过；正式主地图与 Tab 使用 lossless WebP 瓦片，V44 代码/数据/QA 仅作冻结 debug 研究，未来重启须另立 approved spec |
| 金样 packet 预算回归 | `tests/test_map_gold_slice.gd`；`bench/run.cmd map_gold_slice 1 120 Shadow` |

## 东京湾来源圆顶

R71同源地表：`experiments/tokyo_tile_ground_candidate.gd:20 shader_code` / `experiments/tokyo_tile_ground_candidate.gd:37 ground_code` / `experiments/tokyo_tile_ground_candidate.gd:43 texture_resolved` / `experiments/tokyo_tile_ground_candidate.gd:47 plane` / `experiments/tokyo_tile_ground_candidate.gd:62 bind` / `experiments/tokyo_tile_ground_candidate.gd:193 close` 复用当前纹理/参数并守实际纹素投影门，保守预留与幂等恢复；原生反例/owner退出 `tests/test_tokyo_tile_ground.gd:7 run` / `tests/test_tokyo_tile_ground.gd:260 lifecycle` / `tests/test_tokyo_tile_ground.gd:487 _check` 接focused/all/gauntlet。实际路线 `tests/tokyo_tile_ground_review.gd:8 run` / `tests/tokyo_tile_ground_review.gd:141 _wait_source` 保留未就绪机位、原图/源地表/候选/接影/恢复；`tools/audit_tokyo_tile_ground.py:9 audit` 独立统计同色/区外/恢复。静态候选不等于全湾地表桥接和连续LOD完成。

R65预热前置/误差隔离：`tests/tokyo_ao_review.gd:7 run` 显式AO_COMPONENTS交叉绑定AO与接收高度两档纹理，记录同位四组合与双档保守预算，不改生产渲染或几何；复用R64源资产和真实路线。预热必须与Stream及完整切面共用预算的设计边界见东京spec。

R86北岸AO显式选区：`tests/export_tokyo_ao.gd:55 region_for` 空值保留旧南部，北岸密集片独立坐标，未知名称拒绝；导出不受隐式环境影响。预热审查从实际AO统计读取范围和镜头中心，三强度/恢复与投影额度进入同资源、像素及预算门；旧南部资产不覆盖，单块候选不冒作南北同时常驻。

R86剩余预算口径：`experiments/tokyo_spatial_cut.gd:6 choose` / `experiments/tokyo_spatial_cut.gd:208 _better` 显式byte_budget参与可行性优先及返回判定，默认96MiB不变；规范`_select_cut`两条分支均传Stream余额。这里只约束目标切面，旧/新/备用物理并集门仍独立，不能把本修正冒作所有切换阻塞解除。

R87保留组件准入与旧档紧切面试验未解除北岸阻塞，源码仅留tmp/tokyo-bay-volume/r87-rejected，运行时已恢复上述R86；不能把试验方法列作已接线能力。北岸中近景帧时间/分桶与失败证据见tmp/tokyo-bay-volume/r87-review.md。

R89最细目录：`tests/build_tokyo_block_catalog.gd` `input_paths` / `run` 显式LOD5继承R85，源/候选同父档位、高度ID、标高数组与尺度门；沿原切线替换168北岸低层页，并正式重导出北岸AO。低层游戏楼凭据仍非空即拒绝，默认及非声明配置不变；制作通过不代表连续准入或性能通过。

R88离线近档：`experiments/tokyo_packed_mesh_reindex.gd` `repack` / `_read` / `_corner` / `corner_digest` / `decoded_bytes` 保留逐角打包序列；`tests/build_tokyo_reindexed_near.gd` `run` 八父包保存后复验，实测节省0。`tests/build_tokyo_far_clusters.gd` `selected_levels` / `maximum_scale` 显式最细档按5.0输出尺度，`tests/export_tokyo_far_costs.gd` `run` 导出正式LOD5逐来源成本；`tools/build_tokyo_block_lod.py` `prepare` / `main` 两版最细街坊计划，`tests/tokyo_far_cluster_review.gd` `run` 对拍近景，仍属未接规范目录的独立候选。

R66显式预热：`experiments/tokyo_baked_ao.gd:8 bind_preloaded` 解码前租用共同预算，`rendering/tokyo_cell_stream.gd:80 geometry_budget` / `rendering/tokyo_cell_stream.gd:84 reserve_auxiliary` / `rendering/tokyo_cell_stream.gd:99 release_auxiliary` 提供单一剩余额度与峰值；`rendering/tokyo_canonical_overlay.gd:39 setup` 检查准备失败，`rendering/tokyo_volume_preload.gd:195 state_ready` 等AO与完整切面共同就绪。`tests/tokyo_preloaded_ao_review.gd:7 cancelled_loading` / `tests/tokyo_preloaded_ao_review.gd:99 run` 验证真实在途取消/缺AO拒绝、同资源远近与菜单释放，`tools/audit_tokyo_ao_preload.py:10 audit` 独立像素与预算检查。

R65无损高度索引：`tools/pack_tokyo_ao_height.py:11 pack` / `tools/pack_tokyo_ao_height.py:22 build` 原高度码全局调色板压缩，`tools/test_tokyo_ao_palette.py:7 PaletteTests` 覆盖容量/哨兵/确定性；AO绑定可选同一精细高度及调色板，不改B遮蔽纹理字节。

R64独立审计：`tools/audit_tokyo_ao.py:10 audit` 验证16父包SHA、三档纹理摘要及最高档面积均值、八机位透明度/区外零差和同位精细档差异；不能把局部总均值很低当连续切档已通过。实验绑定拒绝静态阴影等未计共同预算的叠加材质。

R64局部烘焙AO：`tests/export_tokyo_ao.gd:7 run` 读取规范LOD5父包，`tools/build_tokyo_ao.py:11 height_field` / `tools/build_tokyo_ao.py:41 horizon_ao` / `tools/build_tokyo_ao.py:66 encode_height` / `tools/build_tokyo_ao.py:75 build` 离线生成真实高度场局部遮蔽，反例 `tools/test_tokyo_ao.py:6 AOTests`。材质候选 `experiments/tokyo_baked_ao.gd:67 make_shader` / `experiments/tokyo_baked_ao.gd:105 bind_ao` / `experiments/tokyo_baked_ao.gd:239 strength` / `experiments/tokyo_baked_ao.gd:215 close` 复用旧槽并守接收高度、法线、身份与合计预算；`tests/test_tokyo_ao.gd:7 run` / `tests/test_tokyo_ao.gd:155 lifecycle` / `tests/test_tokyo_ao.gd:199 _check` 接focused/all，`tests/tokyo_ao_review.gd:7 run` / `tests/tokyo_ao_review.gd:109 _capture` 在真实Survivor路线做同位对拍与逐数组不变核验。仅水平接触候选，未推广全湾或连续纹理流送。

R63实际规范流送与旧楼交接：`rendering/tokyo_canonical_overlay.gd:43 _load_archive` / `rendering/tokyo_canonical_overlay.gd:109 _setup_geometry` / `rendering/tokyo_canonical_overlay.gd:165 _select_cut` / `rendering/tokyo_canonical_overlay.gd:200 _step_geometry` / `rendering/tokyo_canonical_overlay.gd:314 _bind_target` / `rendering/tokyo_canonical_overlay.gd:332 _restore_original` / `rendering/tokyo_canonical_overlay.gd:360 bind_legacy` / `rendering/tokyo_canonical_overlay.gd:365 _sync_legacy` / `rendering/tokyo_canonical_overlay.gd:393 _deactivate` / `rendering/tokyo_canonical_overlay.gd:398 debug_state`。显式yokohama_canonical经过既有preload路由，Survivor地图setup后绑定真实旧楼；单一Stream与48节点，实际页面档决定投影，元数据体积另列。实例旧楼屏蔽 `survivor/building_renderer.gd:81 set_volume_coverage` / `survivor/building_renderer.gd:90 _clear_volume_coverage`；`survivor/building_renderer.gd:402 _draw` / `survivor/building_renderer.gd:402 _draw_visible_districts`仅在追踪开启时计building_draw根桶，不改碰撞缓存。原生回归 `tests/tokyo_canonical_lifecycle_case.gd:8 run` / `tests/tokyo_canonical_lifecycle_case.gd:123 ownership` / `tests/tokyo_canonical_lifecycle_case.gd:155 _wait` / `tests/tokyo_canonical_lifecycle_case.gd:162 _check`，ownership进既有cells生命周期/all；正式六机位 `tests/tokyo_canonical_review.gd:6 run`由路线探针显式调用，不冒充实战帧时间。

R61普通cells预热兼容：`rendering/tokyo_volume_preload.gd:195 state_ready` 共用普通cells/分层/R4就绪规则，`_cut_ready`与真实路线探针共同消费；不以stream字段存在推断分层协议。回归 `tests/tokyo_cells_preload_case.gd:8 run` / `tests/tokyo_cells_preload_case.gd:28 _test_states` / `tests/tokyo_cells_preload_case.gd:44 _handoff` / `tests/tokyo_cells_preload_case.gd:113 _cancel_pending` / `tests/tokyo_cells_preload_case.gd:136 _wait_ready` / `tests/tokyo_cells_preload_case.gd:150 _wait_gone` / `tests/tokyo_cells_preload_case.gd:152 _check`，接既有preload生命周期/all；显式CELLS_PRELOAD_TEST为聚焦入口，PRELOAD_OUT使路线原生截图独立保存。故障与约束见known-seams SEAM-044，实测结果见spec。

R60高楼区域扩展：`tools/build_tokyo_static_shadow.py:54 validate_bounds` 拒绝非法矩形，以最长边保证近景采样；`raster` 按不扣洞的外壳面积降序绘制，避免内院擦掉独立岛。`tests/tokyo_static_shadow_review.gd:8 run` 从候选范围取机位中心，显式EXTENDED加入负旋转/90度；`tests/tokyo_static_shadow_review.gd:87 _geometry_state` 在固定场检查节点、变换与原生网格数组摘要，独立审计验证几何不变和来源唯一数。资产版本及Visual证据见spec，不按函数编译通过宣称美术或连续流送已过。

R59局部静态阴影：`tools/build_tokyo_static_shadow.py:18 sweep` / `tools/build_tokyo_static_shadow.py:35 polygons` / `tools/build_tokyo_static_shadow.py:39 raster` / `tools/build_tokyo_static_shadow.py:60 build` 依据原来源高度投影并独立分档采样；反例 `tools/test_tokyo_static_shadow.py:6 ShadowTests`，独立来源/纹理/范围外像素门 `tools/audit_tokyo_static_shadow.py:10 audit`。运行候选 `experiments/tokyo_static_shadow.gd:10 choose_row` / `experiments/tokyo_static_shadow.gd:19 shader_code` / `experiments/tokyo_static_shadow.gd:45 bind` / `experiments/tokyo_static_shadow.gd:97 set_strength` / `experiments/tokyo_static_shadow.gd:102 close`；原生反例 `tests/test_tokyo_static_shadow.gd:7 run` / `tests/test_tokyo_static_shadow.gd:24 _check`，六机位原图/双强度/恢复 `tests/tokyo_static_shadow_review.gd:8 run`；跨帧owner释放接现有cells生命周期。显式 `AGL_TOKYO_STATIC_SHADOW` 由runtime Visual和C1测试消费，其他战斗倍率拒绝；全局动态投影pass仍开，不作已省GPU结论或默认推广。

R57/R58/R70/R75远档成组候选：`tools/build_tokyo_cluster_lod.py:20 candidate` / `tools/build_tokyo_cluster_lod.py:44 _evaluate` / `tools/build_tokyo_cluster_lod.py:71 prepare` / `tools/build_tokyo_cluster_lod.py:158 main` 参数化实际尺度与制作范围；R75显式bounds、源范围和候选边界拒绝，默认仍为原窗；R58可选原生成本与同父包约束，扩大组必须增加净收益；R70显式min_cost比较多外形，共享原误差/障碍门，旧默认不变。正式来源成本导出 `tests/export_tokyo_far_costs.gd:6 run`，不另写LOD阈值。真实道路三角过滤 `tools/filter_tokyo_cluster_barriers.py:10 filter_plan`；原生重建/筛组/保存 `tests/build_tokyo_far_clusters.gd:17 run` / `tests/build_tokyo_far_clusters.gd:105 _convert` / `tests/build_tokyo_far_clusters.gd:228 record_for` / `tests/build_tokyo_far_clusters.gd:238 eligible`，逐组与全档成本预测守恒。反例 `tests/test_tokyo_far_clusters.gd:8 run` / `tests/test_tokyo_far_clusters.gd:160 record` / `tests/test_tokyo_far_clusters.gd:58 _check` 接all；实际节点静态对拍及投影控制 `tests/tokyo_far_cluster_review.gd:10 run` / `tests/tokyo_far_cluster_review.gd:92 _compare`。独立源几何/区域外像素门 `tools/audit_tokyo_far_clusters.py:12 polygon` / `tools/audit_tokyo_far_clusters.py:16 audit` / `tools/audit_tokyo_far_clusters.py:89 main`；阈值、失败及不推广裁决见spec。

R78街坊级概括：`tools/build_tokyo_block_lod.py:20 contract` / `tools/build_tokyo_block_lod.py:26 protected_road` / `tools/build_tokyo_block_lod.py:30 polygon` / `tools/build_tokyo_block_lod.py:34 barriers` / `tools/build_tokyo_block_lod.py:68 choose` / `tools/build_tokyo_block_lod.py:101 prepare` / `tools/build_tokyo_block_lod.py:180 main`；两档独立概括契约保护结构要素及真实标高楼，保留近景原形。反例 `tools/test_tokyo_block_lod.py:8 fixture` / `tools/test_tokyo_block_lod.py:18 BlockTests`，原生 `tests/build_tokyo_far_clusters.gd:174 group_limit` 严格验证schema2且不扩大旧契约；复用上段原生制作/静态对拍，新增同源地表组合计数与独立组间重叠审计，不冒充规范连续流送或帧时间验收。

R79/R85街坊规范目录：`tests/build_tokyo_block_catalog.gd:17 run` / `tests/build_tokyo_block_catalog.gd:156 input_paths` / `tests/build_tokyo_block_catalog.gd:195 valid_plan_rows` 默认远档或显式继承R79制作北岸LOD3，校验完整档位父区矩阵。`tests/build_tokyo_block_catalog.gd:249 _load` / `tests/build_tokyo_block_catalog.gd:256 _replace` 逐面同源后沿原切线重分桶，标高/固定层原始数组及其他配置不变；只增低层组件并迁移身份。`tests/build_tokyo_block_catalog.gd:315 remap_tokens` / `tests/build_tokyo_block_catalog.gd:326 rewrite_coverage` 拒绝低层游戏楼依赖，验证旧身份后迁移高层凭据；`tests/test_tokyo_block_catalog.gd:7 run` / `tests/test_tokyo_block_catalog.gd:120 _check` 经far反例接all。AO输入从新目录正式导出并重烘，不伪造旧manifest摘要。显式制作环境入口在cells生命周期runner，运行复用既有yokohama_ground，不更改默认。

R56顺序与阴影/相机消融：`tests/tokyo_ground_order_probe.gd:5 move_to_end` 只移动索引，不改有向面重数；`tests/tokyo_ground_merge_review.gd:11 run` / `tests/tokyo_ground_merge_review.gd:56 _compare` 接独立控制，记录阴影开关/相机前移量，比较后恢复旧相机。保边界地表候选复用下述离线计划，逐float32边界顶点、拓扑、有理面积三门不变。未通过候选不推广，当前实际裁决见东京湾spec。

R55地表诊断：层成本 `tests/tokyo_canonical_cut_probe.gd:11 run`；精确离线计划 `tools/build_tokyo_ground_merge.py:13 f32` / `tools/build_tokyo_ground_merge.py:17 parts` / `tools/build_tokyo_ground_merge.py:25 exact_area` / `tools/build_tokyo_ground_merge.py:32 merge_component` / `tools/build_tokyo_ground_merge.py:74 plan_records` / `tools/build_tokyo_ground_merge.py:121 main`，反例 `tools/test_tokyo_ground_merge.py:22 GroundMergeTests`。原生保存与打包压紧 `tests/bake_tokyo_ground_merge.gd:9 run` / `tests/bake_tokyo_ground_merge.gd:78 _uniform` / `tests/bake_tokyo_ground_merge.gd:102 compact`；focused/all反例 `tests/test_tokyo_ground_merge.gd:9 run` / `tests/test_tokyo_ground_merge.gd:30 _check`。真实多距离对照 `tests/tokyo_ground_merge_review.gd:10 run` / `tests/tokyo_ground_merge_review.gd:56 _compare` 由 `tests/tokyo_cells_runtime_visual.gd:13 _capture_sequence` 显式调用；只压紧顶点控制组复用已驻留源。不改正式默认，Visual与预算失败见spec。

R49游戏街区原生候选见 `experiments/tokyo_gameplay_volume.gd:7 build` / `experiments/tokyo_gameplay_volume.gd:44 joined` / `experiments/tokyo_gameplay_volume.gd:53 build_many` / `experiments/tokyo_gameplay_volume.gd:65 geometry_bytes` / `experiments/tokyo_gameplay_volume.gd:74 triangles`；屋顶差集 `experiments/tokyo_roof_difference.gd:5 subtract_all` / `experiments/tokyo_roof_difference.gd:17 subtract` / `experiments/tokyo_roof_difference.gd:44 half_plane` / `experiments/tokyo_roof_difference.gd:66 area`。

几何反例 `tests/test_tokyo_gameplay_volume.gd:8 run` / `tests/test_tokyo_gameplay_volume.gd:58 _test_difference` / `tests/test_tokyo_gameplay_volume.gd:83 _check` 接东京focused/all；实际入口独立静态审查 `tests/tokyo_gameplay_review.gd:10 run` / `tests/tokyo_gameplay_review.gd:176 _projection_errors` / `tests/tokyo_gameplay_review.gd:190 _coplanar_roofs` / `tests/tokyo_gameplay_review.gd:238 _capture` / `tests/tokyo_gameplay_review.gd:247 _export_roofs` / `tests/tokyo_gameplay_review.gd:268 _points` 由R48路线探针显式环境开关调用。原生导出只读独立审计 `tools/audit_tokyo_gameplay_roofs.py` `main`；生产语义/未完成门回链东京湾spec。

R50共同屋面来源 `tests/export_tokyo_gameplay_roofs.gd:5 run`；离线分区 `tools/build_tokyo_shared_roofs.py`（`polygon_parts` / `canonical_points` / `native_attributes` / `build` / `main`）、反例 `tools/test_tokyo_shared_roofs.py`、磁盘顶点独立几何门 `tools/audit_tokyo_shared_roofs.py`（`key` / `audit` / `main`）。保存格式 `experiments/tokyo_shared_roof_bundle.gd`；烘焙 `tests/bake_tokyo_shared_roofs.gd:8 run` / `tests/bake_tokyo_shared_roofs.gd:84 _replace` / `tests/bake_tokyo_shared_roofs.gd:135 _points` / `tests/bake_tokyo_shared_roofs.gd:146 _addition` / `tests/bake_tokyo_shared_roofs.gd:177 _same_arrays` / `tests/bake_tokyo_shared_roofs.gd:186 _retain_material` / `tests/bake_tokyo_shared_roofs.gd:190 _preserve_packed`；独立保存后审计 `tests/audit_tokyo_shared_roof_bundle.gd:6 run`。

R50保存包静态接管 `tests/tokyo_shared_roof_review.gd:6 bind` / `tests/tokyo_shared_roof_review.gd:33 restore` / `tests/tokyo_shared_roof_review.gd:39 references` / `tests/tokyo_shared_roof_review.gd:47 submitted_faces`；离线制作和保存后审计由 `tests/tokyo_cells_lifecycle_runner.gd:4 _ready` 的显式环境开关调用，默认与正式流送保持不变。

R51完整规范父包导出 `tests/export_tokyo_canonical_roofs.gd:8 run` / `tests/export_tokyo_canonical_roofs.gd:85 _extract`；相机无关排序/共同分区 `tools/build_tokyo_canonical_roofs.py`（`canonicalize` / `generate` / `digest` / `main`）及 `tools/test_tokyo_canonical_roofs.py`。原生保存/独立进程审计 `tests/build_tokyo_canonical_roofs.gd:7 run` 复用R50打包属性与磁盘逐面门，审计导出使用独立输出路径，不覆盖R50证据。父包成功不代表空间子块或连续LOD已接入。

R52固定归属 `tools/build_tokyo_spatial_roof_plan.py`（`geometry` / `ownership` / `partition` / `main`）及8项 `tools/test_tokyo_spatial_roof_plan.py`；无损单surface合并 `experiments/tokyo_packed_mesh_join.gd:5 join` / `experiments/tokyo_packed_mesh_join.gd:63 signatures` / `experiments/tokyo_packed_mesh_join.gd:88 conserved`，反例 `tests/test_tokyo_packed_mesh_join.gd:10 run` / `tests/test_tokyo_packed_mesh_join.gd:58 _check` 接东京focused/all。独立页面 `rendering/tokyo_canonical_spatial_page.gd:22 valid`；生成/独立重建核验 `tests/build_tokyo_canonical_spatial.gd:10 run` / `tests/build_tokyo_canonical_spatial.gd:133 _split` / `tests/build_tokyo_canonical_spatial.gd:144 _page`，由生命周期runner显式开关调用，正式流送仍不变。

R47原生地表只读导出与R48载入交接指针；生产语义见东京湾spec，不能把预览路线/无头通过当作全局FPS通过。

新增入口 `tests/export_tokyo_ground_planes.gd:8 run` / `tests/export_tokyo_ground_planes.gd:34 records`。

新增入口 `survivor/building_preloader.gd:39 _ready` / `survivor/building_preloader.gd:65 _process` / `survivor/building_preloader.gd:104 _prewarm_detail_cache` / `survivor/building_preloader.gd:120 _finish` / `survivor/building_preloader.gd:131 _volume_progress`。

新增入口 `tests/tokyo_preload_route_probe.gd:7 run` / `tests/tokyo_preload_route_probe.gd:242 _native_capture` / `tests/tokyo_preload_route_probe.gd:253 _capture`。

新增入口 `tests/tokyo_preload_lifecycle_case.gd:8 run` / `tests/tokyo_preload_lifecycle_case.gd:112 _edge_cases` / `tests/tokyo_preload_lifecycle_case.gd:200 _wait_ready` / `tests/tokyo_preload_lifecycle_case.gd:213 _wait_gone` / `tests/tokyo_preload_lifecycle_case.gd:221 _check`。

新增入口 `rendering/tokyo_volume_preload.gd:38 script_path` / `rendering/tokyo_volume_preload.gd:54 start` / `rendering/tokyo_volume_preload.gd:86 take` / `rendering/tokyo_volume_preload.gd:110 _begin` / `rendering/tokyo_volume_preload.gd:192 _cut_ready` / `rendering/tokyo_volume_preload.gd:230 _after_draw` / `rendering/tokyo_volume_preload.gd:237 _process` / `rendering/tokyo_volume_preload.gd:229 arm` / `rendering/tokyo_volume_preload.gd:303 _claim` / `rendering/tokyo_volume_preload.gd:314 _intersects` / `rendering/tokyo_volume_preload.gd:332 _activate` / `rendering/tokyo_volume_preload.gd:340 _visibility_changed` / `rendering/tokyo_volume_preload.gd:351 _loading_exited` / `rendering/tokyo_volume_preload.gd:356 cancel` / `rendering/tokyo_volume_preload.gd:367 _exit_tree` / `rendering/tokyo_volume_preload.gd:372 progress`。

R46保守复用见 `experiments/tokyo_cut_reuse.gd:56 covers` / `experiments/tokyo_cut_reuse.gd:76 _validate` / `experiments/tokyo_cut_reuse.gd:88 _covered` / `experiments/tokyo_cut_reuse.gd:101 faces`；独立派生候选 `rendering/tokyo_stable_cluster_overlay.gd:14 _load_archive` / `rendering/tokyo_stable_cluster_overlay.gd:20 _setup_geometry` / `rendering/tokyo_stable_cluster_overlay.gd:32 _register_lookup` / `rendering/tokyo_stable_cluster_overlay.gd:38 _select_cut` / `rendering/tokyo_stable_cluster_overlay.gd:73 _compatible` / `rendering/tokyo_stable_cluster_overlay.gd:88 debug_state`。显式yokohama_cluster_stable接MapFeatureRenderer，原生图/实际生命周期复用R45带候选形参入口。反例 `tests/test_tokyo_cut_reuse.gd:7 run` / `tests/test_tokyo_cut_reuse.gd:105 _entry` / `tests/test_tokyo_cut_reuse.gd:55 _check` 聚合至东京focused/all；复用计数不代表性能通过。

R45成对原形的元数据与路径见 `experiments/tokyo_cluster_cut.gd:8 decorate` / `experiments/tokyo_cluster_cut.gd:35 original_cut` / `experiments/tokyo_cluster_cut.gd:43 paths` / `experiments/tokyo_cluster_cut.gd:55 fallback_visible`。显式 `yokohama_cluster_hierarchy` 从MapFeatureRenderer进入 `rendering/tokyo_cluster_overlay.gd:13 _load_archive` / `rendering/tokyo_cluster_overlay.gd:26 _setup_geometry` / `rendering/tokyo_cluster_overlay.gd:42 _select_cut`；完整切换、预算分阶段与即时恢复见 `rendering/tokyo_cluster_overlay.gd:58 _step_geometry` / `rendering/tokyo_cluster_overlay.gd:104 _prepare_target` / `rendering/tokyo_cluster_overlay.gd:131 _trim_current` / `rendering/tokyo_cluster_overlay.gd:158 _restore_original` / `rendering/tokyo_cluster_overlay.gd:174 _bind_target` / `rendering/tokyo_cluster_overlay.gd:181 _is_cluster`；终态和观测见 `rendering/tokyo_cluster_overlay.gd:185 _deactivate` / `rendering/tokyo_cluster_overlay.gd:191 debug_state`。反例 `tests/test_tokyo_cluster_stream.gd:8 run` / `tests/test_tokyo_cluster_stream.gd:39 _check`；真实生命周期 `tests/tokyo_cluster_lifecycle_case.gd:6 run` 接东京生命周期与all，窄入口使用 `AGL_TOKYO_CLUSTER_LIFECYCLE=1`。连续原生对拍 `tests/tokyo_cluster_runtime_review.gd:7 run` / `tests/tokyo_cluster_runtime_review.gd:59 _wait`；不把静态几何一致性或headless通过当作FPS通过。

R44原生低层合并见 `tests/build_tokyo_cluster_pages.gd:18 run` / `tests/build_tokyo_cluster_pages.gd:95 rebuild` / `tests/build_tokyo_cluster_pages.gd:154 face_count`，经 `tests/build_tokyo_cells.gd:28 run` 的 `AGL_TOKYO_CLUSTER_BUILD=1` 分支派生独立父/子/叶。保存后来源/标高缓冲/实际字节与三角守恒见 `tests/test_tokyo_cluster_pages.gd:6 run`，由东京focused统一入口聚合。静态原生对拍 `tests/tokyo_cluster_review.gd:12 run` / `tests/tokyo_cluster_review.gd:60 _compare` / `tests/tokyo_cluster_review.gd:129 _capture` 由 `tests/tokyo_cells_runtime_visual.gd:13 _capture_sequence` 的 `AGL_TOKYO_CLUSTER_REVIEW=1` 分支进入；复用暂停的R42实际节点池，恢复后才移动机位，不等于连续LOD集成。原形近景立即兜底、实战FPS与全湾仍须单独验收。

R43按用户授权的低层体块概括由 `tools/build_tokyo_cluster_lod.py` 的 `candidate` / `prepare` / `main` 生成独立来源映射，`tools/test_tokyo_cluster_lod.py` 的 `ClusterTests` 检查同高/非标高、道路铁路水体、宽缝/其它楼阻隔和来源唯一性；当前只是离线候选，不等于原生分块或LOD实装。原生屋面只读导出见 `tests/export_tokyo_roof_ownership.gd:7 run` / `tests/export_tokyo_roof_ownership.gd:34 _roofs`，由 `tests/build_tokyo_cells.gd` `run` 的 `AGL_TOKYO_ROOF_EXPORT=1` 分支进入，输出面ID/float32坐标法线/源摘要；不自动删面。

R42显式入口 `yokohama_joined_lod_hierarchy` 继承R41完整切面流程，只为LOD4 full/mid登记独立目录：`rendering/tokyo_lod_hierarchical_overlay.gd:6 _load_archive` / `rendering/tokyo_lod_hierarchical_overlay.gd:22 _setup_geometry` / `rendering/tokyo_lod_hierarchical_overlay.gd:33 _register_lod_entry` / `rendering/tokyo_lod_hierarchical_overlay.gd:40 _select_cut`。页身份见 `rendering/tokyo_spatial_lod_page.gd:6 valid`，目录递归校验见 `rendering/tokyo_spatial_lod_index.gd:6 valid` / `rendering/tokyo_spatial_lod_index.gd:21 _same_package`；Stream的`_matches`核对package_variant。离线入口 `tests/build_tokyo_lod_spatial_pages.gd:13 run` / `tests/build_tokyo_lod_spatial_pages.gd:90 _split_layers` / `tests/build_tokyo_lod_spatial_pages.gd:99 _save_page`；418份独立原生文件保留原LOD4来源/楼高和标高网格，不能用LOD5替代。保存后审计 `tests/test_tokyo_lod_spatial_pages.gd:10 run` / `tests/test_tokyo_lod_spatial_pages.gd:16 _test_identity` / `tests/test_tokyo_lod_spatial_pages.gd:48 _test_saved` / `tests/test_tokyo_lod_spatial_pages.gd:96 _verify_page` / `tests/test_tokyo_lod_spatial_pages.gd:110 _conserved` / `tests/test_tokyo_lod_spatial_pages.gd:117 _check` 已接东京focused；同一层级生命周期夹具接受R42脚本并接入all。原生15机位 `tests/tokyo_lod_spatial_review.gd:7 run` / `tests/tokyo_lod_spatial_review.gd:74 _reference` / `tests/tokyo_lod_spatial_review.gd:132 _capture` / `tests/tokyo_lod_spatial_review.gd:141 _wait_basemap`；只读覆盖定位 `tests/tokyo_lod_spatial_probe.gd:5 capture`。诊断开关不改资源；静态画面/连续性能/余区验收独立，不推广默认。

R41显式生产入口由 `survivor/map_feature_renderer.gd` `setup` 的 `yokohama_joined_hierarchy` 选择；`rendering/tokyo_hierarchical_overlay.gd:22 _load_archive` / `rendering/tokyo_hierarchical_overlay.gd:37 _setup_geometry` / `rendering/tokyo_hierarchical_overlay.gd:55 _register_page` 沿用R34来源深度并登记R40原生页。完整切面选择和预算准入见 `rendering/tokyo_hierarchical_overlay.gd:62 _step_geometry` / `rendering/tokyo_hierarchical_overlay.gd:102 _select_cut` / `rendering/tokyo_hierarchical_overlay.gd:123 paths_for` / `rendering/tokyo_hierarchical_overlay.gd:133 union_bytes`；同帧全组重绑与释放见 `rendering/tokyo_hierarchical_overlay.gd:153 _commit_cut` / `rendering/tokyo_hierarchical_overlay.gd:184 _apply_precision_guards` / `rendering/tokyo_hierarchical_overlay.gd:204 _remove_cell` / `rendering/tokyo_hierarchical_overlay.gd:211 _deactivate` / `rendering/tokyo_hierarchical_overlay.gd:231 _exit_tree` / `rendering/tokyo_hierarchical_overlay.gd:236 debug_state`。`rendering/tokyo_cell_stream.gd` `request` 自持Packed请求/保留数组，`_matches` 追加可选来源校验，仍唯一96MiB预算。反例 `tests/test_tokyo_hierarchical_stream.gd:9 run` / `tests/test_tokyo_hierarchical_stream.gd:46 _check`；跨帧验收 `tests/tokyo_hierarchical_lifecycle_case.gd:8 run` / `tests/tokyo_hierarchical_lifecycle_case.gd:102 _ready_cut` / `tests/tokyo_hierarchical_lifecycle_case.gd:120 _check`；真实预览 `tests/tokyo_hierarchical_review.gd:6 run` / `tests/tokyo_hierarchical_review.gd:71 _wait`。该入口已接真实加载流程，但远中档提交、切换峰值、实战FPS和全湾余区仍分开验收，不默认推广。

R40北岸二级目录：`rendering/tokyo_spatial_leaf.gd:6 valid` / `rendering/tokyo_hierarchical_index.gd:6 valid`；完整树选择见 `experiments/tokyo_spatial_cut.gd:6 choose` / `experiments/tokyo_spatial_cut.gd:47 _frontier` / `experiments/tokyo_spatial_cut.gd:77 _combine` / `experiments/tokyo_spatial_cut.gd:196 _insert` / `experiments/tokyo_spatial_cut.gd:208 _better`。独立129文件入口 `tests/build_tokyo_hierarchical_pages.gd:11 run`；反例与保存后审计 `tests/test_tokyo_hierarchical_pages.gd:10 run` / `tests/test_tokyo_hierarchical_pages.gd:19 _test_solver` / `tests/test_tokyo_hierarchical_pages.gd:164 _test_saved` / `tests/test_tokyo_hierarchical_pages.gd:189 _check`。显式`hierarchy_native`同位试装，不等于生产流送、连续LOD或实战FPS验收。

R39完整墙面覆盖归属：`experiments/tokyo_surface_owner.gd:89 wall_records` / `experiments/tokyo_surface_owner.gd:140 wall_rectangles` 只识别精确端点、法线、绕向与互补对角覆盖；`tests/build_tokyo_owned_pages.gd:12 run` 在父包先裁决再分桶，独立保存81个原生资源。`tests/test_tokyo_spatial_pages.gd:136 _test_covered_walls` / `tests/test_tokyo_spatial_pages.gd:167 _test_owned_saved` 验半面/缺口/近似端点拒绝、完整来源/楼高、保存后父子三层守恒。显式 `owned_native` 对拍真实加载R39，不代表生产流送切换或FPS门已通过。

R38无损空间子包：`experiments/tokyo_spatial_split.gd:5 centers` / `experiments/tokyo_spatial_split.gd:23 cuts` / `experiments/tokyo_spatial_split.gd:43 bucket` / `experiments/tokyo_spatial_split.gd:48 split` 原生逐字节分桶；`experiments/tokyo_spatial_select.gd:6 visible` / `experiments/tokyo_spatial_select.gd:21 choose` 在16活动块内选择完整粗细覆盖。`rendering/tokyo_spatial_page.gd:14 valid` / `rendering/tokyo_spatial_index.gd:10 valid` 区分来源与显示子包；`tests/build_tokyo_spatial_pages.gd:13 run` / `tests/build_tokyo_spatial_pages.gd:74 descriptor` / `tests/build_tokyo_spatial_pages.gd:85 conserved` 独立生成64子包并逐有向三角核验。

R38保存后审计及反例：`tests/test_tokyo_spatial_pages.gd:13 run` / `tests/test_tokyo_spatial_pages.gd:61 _test_saved` / `tests/test_tokyo_spatial_pages.gd:98 _test_surface_owner` / `tests/test_tokyo_spatial_pages.gd:213 _test_selection` / `tests/test_tokyo_spatial_pages.gd:235 _check`。同SceneTree诊断：`tests/tokyo_spatial_review.gd:11 run` / `tests/tokyo_spatial_review.gd:222 _capture` / `tests/tokyo_spatial_review.gd:231 _probe_surfaces`；码头精确重面归属仅显式调用 `experiments/tokyo_surface_owner.gd:5 keys` / `experiments/tokyo_surface_owner.gd:36 resolve`，不覆盖原生包或接入正式流送。

R37原生审计强锚点：`tests/tokyo_shell_review.gd:18 run` / `tests/tokyo_shell_review.gd:97 _build` / `tests/tokyo_shell_review.gd:128 _capture` / `tests/tokyo_shell_review.gd:137 _pixel_error` / `tests/tokyo_shell_review.gd:147 _screen_bounds`；最后一项将_city局部坐标转换为实际世界投影，并独立核对二维合成锚点。

R37中近景单块实验：`tools/build_tokyo_shell_lod.py:15 plain_shell` / `tools/build_tokyo_shell_lod.py:19 simplify_shell` / `tools/build_tokyo_shell_lod.py:41 prepare` / `tools/build_tokyo_shell_lod.py:55 audit` / `tools/build_tokyo_shell_lod.py:92 main`；拒绝门见 `tools/test_tokyo_shell_lod.py:13 ShellTests`。`tests/tokyo_shell_review.gd` 的 `run` / `_build` / `_capture` / `_pixel_error` / `_screen_bounds` 验原生重建、同场景恢复与变化区域；显式 `AGL_TOKYO_SHELL_REVIEW` 仅接 `tests/tokyo_cells_runtime_visual.gd:13 _capture_sequence`，不新增正式LOD或覆盖R34归档。

R36/R58实际时钟硬门见 `tests/tokyo_render_clock.gd:5 partition` / `tests/tokyo_render_clock.gd:11 frame_within_budget` / `tests/tokyo_render_clock.gd:23 percentiles_usec`；全部东京性能入口由 `tests/tokyo_volume_combat_runner.gd:155 _process` / `tests/tokyo_volume_combat_runner.gd:289 _bench_finish_now` 在原预热后累计真实间隔及有界原样本分位数，原delta摘要保留但不能独立判过门。显式探针见 `tests/tokyo_render_trace.gd:41 setup` / `tests/tokyo_render_trace.gd:75 begin_frame` / `tests/tokyo_render_trace.gd:157 _before_draw` / `tests/tokyo_render_trace.gd:162 _after_draw` / `tests/tokyo_render_trace.gd:131 close` / `tests/tokyo_render_trace.gd:231 summary`，追加三段及后端全采样均值。纯时钟反例见 `tests/test_perf_frame_trace.gd:315 _test_render_partition`；释放视口后真实回调与幂等断开见 `tests/tokyo_cells_lifecycle_case.gd:8 run`。不把绘制信号区间或最近后端数值冒充同帧GPU呈现证明。

R35逐帧地图诊断见 `rendering/tokyo_volume_overlay.gd:140 _process` / `rendering/tokyo_volume_overlay.gd:149 _process_map` 与 `rendering/tokyo_cell_stream.gd:122 _process` / `rendering/tokyo_cell_stream.gd:200 _process_stream`；仅bench追踪启用两个非嵌套根桶及相机/几何/绑定/更新请求子桶。共享基类也被海洋地图继承，因此不按桶名前缀判断当前地图。`util/perf_buckets.gd` 的 `format_frame_trace_dump` 在上下文单列全部地图子桶，不以CPU更新请求冒充GPU耗时；反例见 `tests/test_perf_frame_trace.gd:291 _test_map_root_and_context`，根桶不重复累加内部子桶，关闭后清空。

R53 Dummy后端兼容见 `rendering/tokyo_cell_stream.gd:265 _request_load` / `rendering/tokyo_cell_stream.gd:272 _load_status` / `rendering/tokyo_cell_stream.gd:278 _take_load` / `rendering/tokyo_cell_stream.gd:287 _matches` / `rendering/tokyo_cell_stream.gd:304 close` / `rendering/tokyo_cell_stream.gd:323 summary`。独立故意失败反例 `tests/tokyo_rid_repro.gd:5 run`；真实Stream双后端/终态回归 `tests/tokyo_rid_stream_case.gd:6 run` / `tests/tokyo_rid_stream_case.gd:79 _fingerprint`，接默认cells生命周期。`bench/invoke_godot.ps1` 的 `Get-BenchRuntimeErrorBlocks`及 `tools/test_bench_rid_gate.ps1`覆盖精确原生RID诊断；根因/上游修复及证据口径见SEAM-043。

R54规范空间流送准备：`rendering/tokyo_canonical_spatial_page.gd:49 stream_identity`，轻量目录 `rendering/tokyo_canonical_catalog.gd:16 valid` / `rendering/tokyo_canonical_catalog.gd:120 _entry_valid`。离线逐包验证 `tests/build_tokyo_canonical_catalog.gd:8 run` / `tests/build_tokyo_canonical_catalog.gd:55 _convert`；身份反例 `tests/test_tokyo_canonical_stream.gd:9 run` / `tests/test_tokyo_canonical_stream.gd:75 _check` 接东京focused/all；全部原生包轮换与owner退出 `tests/tokyo_canonical_stream_case.gd:7 run` 由runner显式目录入口调用。48机位元数据预检 `tests/tokyo_canonical_cut_probe.gd:11 run` 复用正式投影和切面求解，保留预算失败。原包数据未改，仍未接地图旧新显示交接。

R62逐栋显示覆盖凭据：`experiments/tokyo_source_coverage.gd:5 covered_sources`只接受实际提交页及显示层，来源标签不等于覆盖。制作 `tests/build_tokyo_source_coverage.gd:12 run` / `tests/build_tokyo_source_coverage.gd:72 _expected` / `tests/build_tokyo_source_coverage.gd:111 _add` / `tests/build_tokyo_source_coverage.gd:123 _faces` / `tests/build_tokyo_source_coverage.gd:154 _visit` / `tests/build_tokyo_source_coverage.gd:209 _audit_cuts` / `tests/build_tokyo_source_coverage.gd:247 _check`；原生有向float32面多重集与根/中间/叶守恒，输出纯值旁表。回归 `tests/test_tokyo_source_coverage.gd:7 run` / `tests/test_tokyo_source_coverage.gd:49 _covered` / `tests/test_tokyo_source_coverage.gd:53 _test_faces` / `tests/test_tokyo_source_coverage.gd:73 _check`接既有canonical stream/all。COVERAGE_CONFIG显式离线入口，不接生产BuildingRenderer或增加tick/draw。

R30远景面积补偿由 `tools/build_tokyo_area_lod.py:13 area_corrected_ring` / `tools/build_tokyo_area_lod.py:70 prepare` / `tools/build_tokyo_area_lod.py:93 audit` / `tools/build_tokyo_area_lod.py:128 main`生成并验证独立派生字段；反例见 `tools/test_tokyo_area_lod.py:11 AreaLodTests`。原生归档入口 `tests/build_tokyo_area_cells.gd:16 run` / `tests/build_tokyo_area_cells.gd:60 _convert` / `tests/build_tokyo_area_cells.gd:97 _save`；索引展开多重集见 `tests/tokyo_mesh_signature.gd:5 of_mesh`。近档/标高/固定层、原形兜底及字节账回归见 `tests/test_tokyo_area_cells.gd:10 run` / `tests/test_tokyo_area_cells.gd:73 _same_mesh` / `tests/test_tokyo_area_cells.gd:78 _upward` / `tests/test_tokyo_area_cells.gd:86 _check`，不改变原误差或运行时预算。

R29离线空间配对见 `experiments/tokyo_cell_pairing.gd:6 pair_entries` / `experiments/tokyo_cell_pairing.gd:39 solve` / `experiments/tokyo_cell_pairing.gd:45 _solve_mask`；全局最优反例及原生源包逐角/身份/兜底审计见 `tests/test_tokyo_cell_pairing.gd:11 run` / `tests/test_tokyo_cell_pairing.gd:78 _check`。`tests/build_tokyo_joined_cells.gd` `run` 显式构建R29，`rendering/tokyo_cell_index.gd` `shadow_cells`保留原来源阴影包络；活动节点和预算不增加。

R28无损索引归档见 `experiments/tokyo_indexed_mesh.gd:12 pack`，实际提交面数SSOT为 `experiments/tokyo_indexed_mesh.gd:5 triangles`；离线入口 `tests/build_tokyo_indexed_cells.gd:8 run` / `tests/build_tokyo_indexed_cells.gd:37 _convert` / `tests/build_tokyo_indexed_cells.gd:55 _save`。逐角位置/法线/颜色与16/32位索引验证见 `tests/test_tokyo_indexed_mesh.gd:10 run` / `tests/test_tokyo_indexed_mesh.gd:61 _same_corners` / `tests/test_tokyo_indexed_mesh.gd:86 _check`；全16块LOD3及固定地表真实流送容量见 `tests/tokyo_cells_lifecycle_case.gd:209 _test_full_indexed_mid`。所有原始三角保持，资源字节减少不能算24万提交门通过。

R26联合观察入口：`tests/build_tokyo_joined_cells.gd` `pair_entries` / `merge_meshes` / `run` / `_save`，原生验证 `tests/test_tokyo_cells.gd` `_test_joined_union_archive` / `_meshes_sum`；`rendering/tokyo_cells_overlay.gd` `_load_archive`的显式`yokohama_joined`只使用自包含R26索引及原有单套流送。`tests/tokyo_cells_runtime_visual.gd` `_capture_sequence`覆盖两区共有边多缩放、两侧街区、旋转及未制作角落；几何合并不等于面数/性能通过。

R25原生联合专用归档见 `experiments/tokyo_regional_ownership.gd` `validate`、`tests/build_tokyo_cells.gd` `_load_regional_ownership`，结构门见 `rendering/tokyo_cell_index.gd` `valid`。反例 `tests/test_tokyo_regional_ownership.gd` `run` / `_check`；七档几何差集见 `tests/test_tokyo_cells.gd` `_test_regional_archive` / `_mesh_subtracts`，独立51来源夹具为 `scripts/tests/fixtures/tokyo_r25_nonowners.json`。普通Overlay拒绝联合索引；尚未启用全局多区域流送或Visual验收。

R24跨区归属准备入口：`tools/build_tokyo_region_ownership.py` `source_payload` / `connected_components` / `component_center` / `region_distance` / `build_registry` / `prepare_region` / `main`；只读完整包核验见 `tools/audit_tokyo_region_ownership.py` `audit` / `main`，反例见 `tools/test_tokyo_region_ownership.py` `building` / `cities` / `OwnershipTests`。这里只增加联合专用数据标记；原生构建/加载尚未消费，不能据此宣称双区重复绘制已经修复。

R23近景成本预检的原生地表入口：`tests/build_tokyo_cells.gd` `_export_fixed_for_cell_audit`；`AGL_TOKYO_CELL_EXPORT=1`仅导出R22已验证地表与来源哈希到bench结果，正常构建分支不变。离线模型报告位于`tmp/tokyo-bay-volume/r23-*-probe.json`，不是运行时或Visual验收。

R22误差受控远景见 `tools/build_tokyo_footprint_lod.py` `within_error` / `simplify_ring` / `eligible` / `prepare` / `main`；`tools/test_tokyo_footprint_lod.py` `FootprintTests`含顶点距离漏检的长边中点反例。`rendering/tokyo_cell_archive.gd` `valid`登记原形兜底，`tests/build_tokyo_cells.gd` `mesh_bytes`计入内存，`rendering/tokyo_cells_overlay.gd` `_apply_precision_guards`即刻恢复原形并更新提交统计；`tests/test_tokyo_cells.gd` `_test_precision_archive`、`tests/tokyo_cells_lifecycle_case.gd` `_test_precision_jump`验证归档与冻结选档突放大。独立`kawasaki_lod`读取R22归档，不改正式默认。

R21道路连续接头见 `tools/build_tokyo_strokes.py` `stroke` / `prepare` / `main`，独立反例 `tools/test_tokyo_strokes.py` `surface` / `StrokeTests`；原生消费 `experiments/tokyo_volume_preview_factory.gd:252 _path_ribbon`，原生夹具与建筑七包不变审计 `tests/test_tokyo_cells.gd:441 _test_joined_paths` / `tests/test_tokyo_cells.gd:472 _test_joined_archive`。`kawasaki_strokes` 独立读取R21归档，复用北岸11机位、真实混战中心与生命周期；不推广默认。

R20北岸原生候选由 `tests/build_tokyo_cells.gd` `run` 输出 `r20_cells`，`rendering/tokyo_cells_overlay.gd` `_load_archive` 显式 `kawasaki` 选择；`tests/test_tokyo_cells.gd:498 _test_north_coast_archive` 校验七包，`tests/tokyo_cells_lifecycle_case.gd:241 _test_north_coast` 校验正确区域异步与终态。`tests/tokyo_cells_runtime_visual.gd` `_capture_sequence` 提供七缩放及街区/港区/边界，`tests/tokyo_volume_combat_runner.gd` `_ready` 移动真实混战锚点。`tools/build_tokyo_tagged_roofs.py` `main` 可显式继承水色，原始来源不变。

R20区域接缝前置审计见 `tools/audit_tokyo_region_seam.py` `coast_land` / `ring_key` / `shape_key` / `audit` / `main`；独立反例见 `tools/test_tokyo_region_seam.py` `ground` / `SeamTests`。对比同一共享边上的实际地表三角覆盖及同ID楼高/轮廓，双绘制来源单列待统一归属，不将来源一致误判为可直接双区叠加。

R19重复外壳裁决见 `experiments/tokyo_duplicate_outline.gd:5 suppressed` / `experiments/tokyo_duplicate_outline.gd:25 _eligible_key` / `experiments/tokyo_duplicate_outline.gd:42 _ring_key`；反例与原始几何夹具见 `tests/test_tokyo_duplicate_outline.gd:7 run` / `tests/test_tokyo_duplicate_outline.gd:45 source_fixture` / `tests/test_tokyo_duplicate_outline.gd:53 _check`，原生七包差分见 `tests/test_tokyo_cells.gd:784 _test_duplicate_archive`。`yokohama_dedup`独立读取`r19_cells`，沿用R18阴影；Visual的`AGL_TOKYO_DUPLICATE_REVIEW`提供同位近/中/远三图。

R18阴影深度候选见 `rendering/tokyo_shadow_depth.gd:8 fit`、`rendering/tokyo_volume_overlay.gd:203 _configure_camera_depth`、`rendering/tokyo_cells_overlay.gd:162 _configure_camera_depth`；独立包络/全档高度验证见 `tests/test_tokyo_shadow_depth.gd:8 run` / `tests/test_tokyo_shadow_depth.gd:96 _inside` / `tests/test_tokyo_shadow_depth.gd:101 _check`。R27局部包络见 `rendering/tokyo_shadow_depth.gd:22 visible_height`，画外投影反例及联合七包包含验证见 `tests/test_tokyo_shadow_depth.gd:47 _test_visible_height`。原生同位有影/无影检查复用 `tests/tokyo_cells_runtime_visual.gd` `_capture_sequence` 的 `AGL_TOKYO_SHADOW_REVIEW`，生命周期复用 `_test_layer_visibility` / `_test_north_coast`。不切换正式默认。

东京湾来源圆顶的离线几何见 `experiments/tokyo_dome_roof.gd:6 build` / `experiments/tokyo_dome_roof.gd:82 _point` / `experiments/tokyo_dome_roof.gd:87 _face`；算法反例见 `tests/test_tokyo_dome_roof.gd:7 run` / `tests/test_tokyo_dome_roof.gd:75 _vector` / `tests/test_tokyo_dome_roof.gd:79 _check`，七包差异范围审计见 `tests/test_tokyo_cells.gd:822 _test_dome_archive` / `tests/test_tokyo_cells.gd:856 _inside_source_dome`。独立R17B由`tests/build_tokyo_cells.gd` `run`构建，`rendering/tokyo_cells_overlay.gd` `_load_archive`加载，`tests/tokyo_cells_runtime_visual.gd` `_capture_sequence`提供来源圆顶近景；不切换正式默认。

## 东京湾地表诊断

R34原生近岸补面：`tests/build_tokyo_coastal_cells.gd:16 expand`按原始打包字节展开16/32位索引；`tests/build_tokyo_coastal_cells.gd:57 add_clipped`按原R25块界裁面，`tests/build_tokyo_coastal_cells.gd:73 run`只派生固定包/索引，七档楼体引用R32。`tests/test_tokyo_coastal_cells.gd:11 run` / `tests/test_tokyo_coastal_cells.gd:59 raw_prefix` / `tests/test_tokyo_coastal_cells.gd:73 _check`验证原角点及实际成本。显式`yokohama_joined_coastal`由`rendering/tokyo_cells_overlay.gd`加载，`tests/tokyo_cells_runtime_visual.gd`的`AGL_TOKYO_COASTAL_REVIEW`追加栈桥/防波堤多倍率机位；生命周期复用真实流送入口，不替换默认。

R33近岸源数据准备：`tools/extract_tokyo_coastal_inventory.py:18 intersects` / `tools/extract_tokyo_coastal_inventory.py:23 area` / `tools/extract_tokyo_coastal_inventory.py:34 way` / `tools/extract_tokyo_coastal_inventory.py:43 main`从同PBF提取原城区缓存未收录的构筑物；`tools/build_tokyo_coastal_addendum.py:65 existing_coverage` / `tools/build_tokyo_coastal_addendum.py:86 prepare` / `tools/build_tokyo_coastal_addendum.py:149 main`只输出独立补充面，原文件摘要不变。`tools/build_tokyo_coastal_addendum.py:15 native_faces`先检查float32轮廓再三角化，接边收窄后仍过原边界/面积/拓扑门；`tools/test_tokyo_coastal_addendum.py:13 CoastalAddendumTests`含真实防波堤短接边反例。未接原生固定包/LOD，不能视为Visual或性能通过。

R32审计细目：`tests/test_tokyo_palette.gd:74 _same_geometry_and_palette`独立解码逐顶点核色并保留原始顶点/法线/索引缓冲，`tests/test_tokyo_palette.gd:99 _check`记录断言；`tests/tokyo_ground_review.gd:106 palette_reference`在同SceneTree交替R30原mesh+R31-B材质与R32原生mesh，连续读回排查跨次上下文差异，不进入实战场景。

R32独立原生色板：`experiments/tokyo_palette.gd:8 recolor`只改原生RGBA8 RGB；`tests/build_tokyo_palette_cells.gd:7 run` / `tests/build_tokyo_palette_cells.gd:42 _save`派生完整R30所有LOD与精度原形；`tests/test_tokyo_palette.gd:10 run`核对独立解码颜色和全部原始几何/预算。`rendering/tokyo_cells_overlay.gd`显式`yokohama_joined_palette`沿用原表面shader，只关闭自身合成羽化；旧路径与默认不变。

R31仅显式Visual诊断：`tests/tokyo_ground_review.gd:5 capture`输出原生色板、无羽化与A/B对照；`tests/tokyo_ground_review.gd:64 palette_material`构建测试材质假设；`tests/tokyo_ground_review.gd:86 shadowless`保留光源路径只关闭Mesh投影，修正直接关闭光源阴影导致全域照明变化的假参考。`tests/tokyo_cells_runtime_visual.gd:13 _capture_sequence`的`AGL_TOKYO_GROUND_REVIEW`接线不影响正式局，也不修改归档几何。

## 海洋三维地图

| 功能 | 代码锚点 |
|---|---|
| 海洋离线归档、编辑器源码指纹与导出数据指纹 | `rendering/ocean_volume_archive.gd:21 fingerprint`、`rendering/ocean_volume_archive.gd:28 data_fingerprint`、`rendering/ocean_volume_archive.gd:35 valid` |
| 海洋原足迹建筑、发射架、跑道与避障服务路静态合批 | `experiments/ocean_volume_factory.gd:13 build`、`experiments/ocean_volume_factory.gd:41 _gantry`、`experiments/ocean_volume_factory.gd:59 _facade`、`experiments/ocean_volume_factory.gd:71 runway`、`experiments/ocean_volume_factory.gd:96 service_bands`、`experiments/ocean_volume_factory.gd:139 _route_bands`、`experiments/ocean_volume_factory.gd:148 _route_clear` |
| 海洋固定曲面裁片、连续法线和静态资源离线构建 | `tests/build_ocean_volume.gd:10 run`、`tests/build_ocean_volume.gd:64 relief_texture`、`tests/build_ocean_volume.gd:89 tile_layouts`、`tests/build_ocean_volume.gd:112 _mesh_bytes` |
| 借用海洋 Raster 纹理、严格 UV 配准、瓦片生灭与释放 | `rendering/ocean_volume_ground.gd:19 setup`、`rendering/ocean_volume_ground.gd:28 sync`、`rendering/ocean_volume_ground.gd:88 _bind`、`rendering/ocean_volume_ground.gd:123 clear`、`rendering/ocean_volume_ground.gd:143 debug_state` |
| 内置海洋三维入口、共享投影和海洋地表生命周期 | `rendering/ocean_volume_overlay.gd:15 ocean_enabled`、`rendering/ocean_volume_overlay.gd:21 _load_archive`、`rendering/ocean_volume_overlay.gd:25 _setup_geometry`、`rendering/ocean_volume_overlay.gd:47 _step_geometry`、`rendering/ocean_volume_overlay.gd:79 _deactivate`、`rendering/ocean_volume_overlay.gd:87 debug_state` |
| 海洋来源、原建筑、裁片接缝、入口回退 focused 门 | `tests/test_ocean_volume.gd:9 run` |
| 真实 SceneTree 旋转投影、源释放和退出回收 | `tests/ocean_volume_lifecycle_case.gd:7 run` |
| 真实菜单链、同位分区 A/B、Tab、退出重进 | `tests/ocean_volume_visual.gd:30 _run` |
| 海洋 36 混合实战及相机巡航性能门 | `tests/ocean_volume_combat.gd:23 _ready`、`tests/ocean_volume_combat.gd:86 _bench_finish_now` |

## 地图接触 AO

| 功能 | 代码入口 |
|---|---|
| 两区静态接触场、线性 R8 mip、来源与关闭回退 | `rendering/map_contact_ao.gd` `path_for` / `fingerprint` / `valid` / `load_field` / `bind` |
| 真实结构有限半径 BVH 离线烘焙 | `tests/build_map_contact_ao.gd` `directions` / `occlusion` / `run`；`map_contact_ao_build` |
| 材质读取、不新增绘制或逐帧逻辑 | `resources/shaders/map_contact_ao.gdshaderinc`；海洋专用 `ocean_contact_ao_structure.gdshader`；沙漠 `desert_contact_ao_apron.gdshader` 与既有 tactical shader；接线在 `volume_map_factory.gd` `configure_instance`、`ocean_volume_ground.gd` `_bind`、`ocean_volume_overlay.gd` `_setup_geometry`、`volume_satellite_ground.gd` `_make_plane` |
| 两图正式菜单同帧对照和实际退出 | `tests/map_contact_ao_visual.gd` `_ready` / `_run` / `_collect` / `_changed_pixels` / `_wait_scene` / `_check`；`map_contact_ao_visual` |
| 接触場聚焦回归（默认 all） | `tests/test_map_contact_ao.gd` `run` / `_check`；`map_contact_ao` |
| 工业区AO真实可见的36成员混战 | `tests/desert_contact_ao_combat.gd` `_ready` / `_bench_force_battlefield_atmosphere_stress` / `_bench_finish_now`；`desert_contact_ao_c1`，场景与镜头共同平移到(4800,400)，保留原8段缩放旋转巡检 |
# HLOD纹理流送接入

`rendering/tokyo_hlod_stream.gd`：`configure_hlod`、`request_textures`、`texture`、`load_image`、`_step_textures`、`_process_stream`、`close`、`summary`；`tests/test_tokyo_hlod_stream.gd`：`run`。沿原CellStream控制纹理共享预算/异步读取/逐帧上传/跨帧退役，cells生命周期覆盖共享、取消、来源失败和预算拒绝。未接正式默认。

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

- 有限资源、阵亡权重、队列与互斥终态；只持有WeakRef。 `rts/war_ledger.gd:25 register_unit`；`rts/war_ledger.gd:28 living_units`；`rts/war_ledger.gd:37 request`；`rts/war_ledger.gd:50 live_count`；`rts/war_ledger.gd:57 cancel`；`rts/war_ledger.gd:67 refund`；`rts/war_ledger.gd:71 tick`；`rts/war_ledger.gd:110 finish`；`rts/war_ledger.gd:118 shutdown`。
- 东京湾场景装配、主动派遣后入场、双王牌接管、双方容量门。 `rts/full_war_mode.gd:22 _ready`；`rts/full_war_mode.gd:72 _prepare_ace`；`rts/full_war_mode.gd:85 _ensure_pilot`；`rts/full_war_mode.gd:98 _set_patrol`；`rts/full_war_mode.gd:105 _spawn_air`；`rts/full_war_mode.gd:118 _terrain_position`；`rts/full_war_mode.gd:135 _spawn_ship`；`rts/full_war_mode.gd:158 _spawn_ground`；`rts/full_war_mode.gd:171 _on_dispatch`；`rts/full_war_mode.gd:180 _deploy_second_ace`；`rts/full_war_mode.gd:193 switch_ace`；`rts/full_war_mode.gd:213 _physics_process`；`rts/full_war_mode.gd:240 _publish_snapshot`；`rts/full_war_mode.gd:258 _unhandled_input`；`rts/full_war_mode.gd:263 _try_takeover_after_leader_down`；`rts/full_war_mode.gd:266 _on_squad_leader_changed`；`rts/full_war_mode.gd:270 _on_player_died`；`rts/full_war_mode.gd:273 _on_player_leveled_up`；`rts/full_war_mode.gd:276 _spawn_starting_wingmen`；`rts/full_war_mode.gd:281 _migrate_ace_field_upgrades`；`rts/full_war_mode.gd:285 _on_war_ended`；`rts/full_war_mode.gd:291 _exit_tree`。
- 实时Tab面板、后备派遣、地图快照与终局重试。 `rts/war_command_panel.gd:19 _build_ui`；`rts/war_command_panel.gd:85 _text`；`rts/war_command_panel.gd:95 _button`；`rts/war_command_panel.gd:105 _bar`；`rts/war_command_panel.gd:122 open`；`rts/war_command_panel.gd:128 close`；`rts/war_command_panel.gd:135 refresh`；`rts/war_command_panel.gd:167 _on_map_draw`；`rts/war_command_panel.gd:184 _on_map_gui_input`；`rts/war_command_panel.gd:194 _cancel_first`；`rts/war_command_panel.gd:199 _ace_order`；`rts/war_command_panel.gd:206 show_result`；`rts/war_command_panel.gd:213 _retry`；`rts/war_command_panel.gd:217 _menu`。
- 控制区世界标记；仅控制权变化时重绘。 `rts/war_sector_overlay.gd:7 set_sectors`；`rts/war_sector_overlay.gd:14 _draw`。
- 真实SceneTree功能/容量/终态与开局/交战/Tab分阶段墙钟剖面；接默认all。 `tests/full_war_runner.gd:11 _process`；`tests/full_war_runner.gd:14 _ready`；`tests/full_war_runner.gd:19 _run`；`tests/full_war_runner.gd:27 run_checks`；`tests/full_war_runner.gd:124 _capacity_case`；`tests/full_war_runner.gd:153 _run_profile`；`tests/full_war_runner.gd:224 _capture`；`tests/full_war_runner.gd:230 _check`。
- 主菜单入口：`main_menu.gd:700 _on_full_war_pressed`。

建筑平移重绘误差门：`survivor/building_renderer.gd` / `consume_view_change`，默认维持旧门，仅全面战争装配启用屏幕误差预算；功能回归 `tests/full_war_runner.gd` / `run_checks`，默认全量接入 `tests/lifecycle_gauntlet_runner.gd` / `_run`。
# 共享索引诊断入口补充

`tests/build_tokyo_joined_grid.gd` / `read_reuse`：读取摘要绑定的既有归并页供逐组件顺序比较，正式重绑定仅改变依赖指针，不改变已核几何。

`tests/tokyo_rebind_grid_batches.gd:5 run`：正式全叶格网重绑定，输出既有joined_grid消费的audit。

`tests/tokyo_grid_reuse_inventory.gd:5 run`：正式LOD5已有格网产物身份/摘要复用门及漏项清单。

`tests/export_tokyo_current_sources.gd` / `inventory`：正式/候选来源快照全叶组件身份比较与生产清单，不加载全图Mesh。

颜色表图集：`tests/tokyo_independent_mip_batch.gd:6 build`显式颜色表分支先解码后过滤。`tests/tokyo_envelope_visual_review.gd:104 _route`预先按SHA去重驻留全部路线索引，移动段不读索引文件；仅诊断。

`tests/tokyo_shared_index_audit.gd:4 run`：显式shared_index_audit测试，六叶固定索引回放、64KiB内片段与解码耗时；不授予正式驻留/性能资格。

## 地图交接安装与性能复现工具

当前地图交接包校验/安全落盘 → `tools/install_tokyo_map_handoff.py` / `load_manifest` / `safe_path` / `inspect_existing` / `verify_archive` / `install`；只读模式为`--verify-only`。固定性能复现 → `tools/run_tokyo_map_handoff.ps1` → 原`bench/run.cmd`的Shadow Visual入口；不改渲染或战斗负载。
下载与验收边界见[当前运行地图复现](../handoffs/2026-10-14-current-map-runtime-repro.md)。

交接工具回归：`tools/test_map_handoff_delivery.py` / `DeliveryTests`，覆盖损坏包、路径逃逸、已有文件/锁保护、安装读回及模拟bench失败码与环境隔离；不需要实物地图或Godot。

## M20投影覆盖与逐帧交接诊断

旋转视野覆盖与屏外高楼保护：`rendering/tokyo_hlod_handoff.gd:151 covers_projection` / `rendering/tokyo_hlod_handoff.gd:165 _covers_projected_entry`；父子保守包络在 `rendering/tokyo_hlod_manifest.gd:203 tree` 加载期生成，原选页/绘制包络不变。

求解前的在途HLOD快速复用：`rendering/tokyo_map_planner.gd:334 _pending_hlod_covers` / `rendering/tokyo_hlod_overlay.gd:635 _pending_hlod_covers`；普通候选和桥接候选都按既有0.25秒预测检查目录及行级清晰度上限。无解原生回退的最小视野检查：`rendering/tokyo_hlod_overlay.gd:822 _select_native_fallback`，已有原生目标仍走原复用路径。回归：`tests/test_tokyo_hlod_stream.gd:1420 pending_hlod_expiry_checks`、`tests/test_tokyo_hlod_stream.gd:1463 projection_equivalence_checks`，经 `HLOD_STREAM_TEST` + `PROJECTED_COVERAGE_TEST` 聚焦入口，亦接既有all。

逐帧时序：`tests/tokyo_volume_combat_runner.gd:155 _process` / `tests/tokyo_volume_combat_runner.gd:289 _bench_finish_now`；选择状态由 `rendering/tokyo_hlod_overlay.gd:276 _step_geometry` 有界采集。`tools/run_tokyo_map_handoff.ps1 -Trace -Interactive` 显式开启；`-Counterfactual` 额外求解替代方案，不是性能基线。用法见[当前地图复现](../handoffs/2026-10-14-current-map-runtime-repro.md#逐帧诊断)。

## M20联合预算桥接

同池已有资源抵扣与保护带逐档核验：`rendering/tokyo_hlod_overlay.gd:785 _handoff_incremental_costs` / `rendering/tokyo_hlod_overlay.gd:752 _select_handoff_hlod`；完整树按新增物理费用求解：`rendering/tokyo_hlod_manifest.gd:314 select_handoff` / `rendering/tokyo_hlod_manifest.gd:353 incremental_tree`。显示费用和真实联合费用仍独立复核；失格哨兵不可因资源已在内存而降价。

共享父子页、半池以上可行切面、完整费用恢复与过期页反例：`tests/test_tokyo_hlod_stream.gd:1340 handoff_bridge_checks`；经既有投影覆盖 focused 与 all 入口。

快速放大下桥接资格与在途复用共用既有0.25秒预测视窗：`rendering/tokyo_hlod_overlay.gd:746 _handoff_bridge_qualified`；预测失格父页在完整树中提前细化，不拖延下一档加载。

旧视野完整时也允许等大或稍大的合格桥接，只要当前显示与候选的真实物理联合费用仍在原预算内。每档保护带在收窄前先尝试共享资源加权的完整树解；入口沿用两条选择路径的 `_select_hlod`、`_select_handoff_hlod`，`min_guard_px`限制返回同档或更宽的保护带，候选记录 `hlod_guard_shared`。快速路线选择轨迹导出沿用 `tests/tokyo_hlod_route_probe.gd` 的 `play_session`。

## 准备目录、后台地图规划与呈现前重绘

行为约束见[准备目录与后台流送](../specs/systems/tokyo-prepared-streaming.md)。HLOD默认在Loading准备来源，游戏帧只提交请求并验收后台计划；`AGL_TOKYO_SYNC_SELECTION=1`（`tools/run_tokyo_map_handoff.ps1 -SynchronousSelectionControl`）为显式同步对照，GridNative保持原路径。索引与功能回归不表示性能通过。

墙钟尾部统计：`tests/tokyo_render_clock.gd:23 percentiles_usec`补充P99.9、最慢1%/0.1%平均帧率及超过30fps帧预算的数量；`tests/tokyo_hlod_route_probe.gd:251 play_session`记录真实帧间隔后共用此摘要，断言入口为`tests/test_perf_frame_trace.gd:315 _test_render_partition`。

- 准备目录身份与精确资格区间：`rendering/tokyo_prepared_catalog.gd:17 build`、`rendering/tokyo_prepared_catalog.gd:34 validate`、`rendering/tokyo_prepared_catalog.gd:40 roots_at`；Loading/离线缓存入口：`rendering/tokyo_prepared_catalog.gd:61 cache_path`、`rendering/tokyo_prepared_catalog.gd:66 load_or_build`、`rendering/tokyo_prepared_catalog.gd:79 read`、`rendering/tokyo_prepared_catalog.gd:106 write`。后台树复用：`rendering/tokyo_hlod_manifest.gd:415 qualified_roots`。
- 纯值选择上下文：`rendering/tokyo_hlod_manifest.gd:19 background_selection`、`rendering/tokyo_hlod_manifest.gd:23 display_limit`、`rendering/tokyo_hlod_manifest.gd:31 selection_context_valid`；原生来源快照与配置：`rendering/tokyo_hlod_native.gd:75 selection_snapshot`、`rendering/tokyo_hlod_native.gd:92 configure_selection_snapshot`。基础切面与驻留选择转发上下文：`rendering/tokyo_hlod_foundation.gd:57 select`、`rendering/tokyo_hlod_cached_cut.gd:23 select`。
- 后台完整规划：`rendering/tokyo_map_planner.gd:42 configure`、`rendering/tokyo_map_planner.gd:63 plan`、`rendering/tokyo_map_planner.gd:272 compact_cut`；HLOD/联合预算桥接/原生/预测入口：`rendering/tokyo_map_planner.gd:342 _select_hlod`、`rendering/tokyo_map_planner.gd:415 _select_handoff_hlod`、`rendering/tokyo_map_planner.gd:493 _select_native`、`rendering/tokyo_map_planner.gd:569 _predict_prefetch`。原生保护查询全部失败时，`_select_native`仅保留配置、资格、页数、面数、费用和当前覆盖都合格的已提交绑定，返回`native_retained`与零保护带；`retain_current=false`仍为未来视野独立求解。
- 移动/缩放包络：`rendering/tokyo_hlod_handoff.gd:65 pan_lead`、`rendering/tokyo_hlod_handoff.gd:73 zoom_out_padding`、`rendering/tokyo_hlod_handoff.gd:80 native_motion_query`、`rendering/tokyo_hlod_handoff.gd:137 covers_motion_view`。原生对称保护带失败后按0.35/0.175/0.0875秒检查当前与预测倍率下的未来视野，仍保持当前配置、当前资格和真实联合预算；已经预测的预取入口以`include_zoom_footprint=false`避免重复外推。
- 逐帧移动采样：`rendering/tokyo_native_predictor.gd:21 smooth_pan`按实际经过时间平滑速度；`rendering/tokyo_hlod_overlay.gd:276 _step_geometry`在后台忙时仍更新镜头方向与速度。达到既有160屏幕像素瞬切门时，同步清除平移、缩放和方向历史，不计为连续缩放反转。原请求和领取状态分开记录：`rendering/tokyo_hlod_overlay.gd:1467 _planning_request`、`rendering/tokyo_hlod_overlay.gd:1522 _trace_prepared_state`。
- 单任务与来源代次：`rendering/tokyo_map_plan_worker.gd:27 configure`、`rendering/tokyo_map_plan_worker.gd:39 busy`、`rendering/tokyo_map_plan_worker.gd:44 ready`、`rendering/tokyo_map_plan_worker.gd:48 submit`、`rendering/tokyo_map_plan_worker.gd:62 take`、`rendering/tokyo_map_plan_worker.gd:76 close`、`rendering/tokyo_map_plan_worker.gd:88 summary`；后台结果纯值门：`rendering/tokyo_map_plan_worker.gd:100 _run`、`rendering/tokyo_map_plan_worker.gd:112 pure`。
- 主线程准备/请求/接纳：`rendering/tokyo_hlod_overlay.gd:1427 _prepare_map_planner`、`rendering/tokyo_hlod_overlay.gd:1467 _planning_request`、`rendering/tokyo_hlod_overlay.gd:1485 _step_prepared_selection`、`rendering/tokyo_hlod_overlay.gd:1555 _admit_prepared_plan`；领取时重新检查revision和当前投影视野，过期失败结果不清除当前显示，最终资源提交仍经`rendering/tokyo_hlod_overlay.gd:1083 _commit_ready_target`。逐帧收尾`rendering/tokyo_hlod_overlay.gd:591 _finish_display_step`在后台等待期间仍先接替已就绪目标，再清理缺边或超过宽限的旧切面，并更新显示资格/覆盖状态。
- 原生保护元数据与重采样：`rendering/tokyo_hlod_overlay.gd:1607 _refresh_native_guard_metadata`同步刷新资源身份不变的target/committed保护阶段与余量，单独刷新不触发请求或revision；预取身份变化仍走正常请求。`rendering/tokyo_hlod_overlay.gd:643 _selection_due`将`native_motion_guard`、`native_actual`和`native_retained`的零保护带查询间隔缩短到1/60秒；该计时触发仍须视野或输出改变，其他脏状态可独立重试。
- 呈现前合并物理重绘：`rendering/visual_redraw_queue.gd:7 request`、`rendering/visual_redraw_queue.gd:22 _flush`；最终状态/真实调用者/退出回归：`tests/visual_redraw_queue_case.gd:107 run`、`tests/visual_redraw_queue_case.gd:122 _test_frame_contract`、`tests/visual_redraw_queue_case.gd:200 _test_real_callers`、`tests/visual_redraw_queue_case.gd:310 _test_lifecycle`，独立入口`tests/visual_redraw_queue_runner.gd:6 _run`（bench `visual_redraw_queue`）。真实字段采样由`tests/visual_redraw_queue_case.gd:28 DrawProbe`、`tests/visual_redraw_queue_case.gd:52 PhysicsStateSampler`及`tests/visual_redraw_queue_case.gd:174 _observe`覆盖14类调用者；`tests/visual_redraw_queue_case.gd:59 LifecycleCanvas`验证退出不绘制、重入/禁用后的最终绘制状态。
- 准备目录和同步差分：`tests/test_tokyo_prepared_catalog.gd:16 checks`、`tests/test_tokyo_prepared_catalog.gd:79 cache_checks`、`tests/test_tokyo_map_planner.gd:53 differential_checks`、`tests/test_tokyo_map_planner.gd:96 native_bridge_checks`；`tests/test_tokyo_map_planner.gd:142 mixed_cached_hlod_checks`覆盖混合HLOD缓存的已认证区间复用、资格边界与缺失可见资源的拒绝/恢复。上下文及后台隔离：`tests/test_tokyo_selection_context.gd:57 manifest_checks`、`tests/test_tokyo_selection_context.gd:95 native_checks`、`tests/test_tokyo_selection_context.gd:135 prepared_checks`、`tests/test_tokyo_selection_context.gd:177 run`。
- 自含方向/预算回归：`tests/test_tokyo_map_planner.gd:12 GuardPool`、`tests/test_tokyo_map_planner.gd:199 directional_trim_checks`、`tests/test_tokyo_map_planner.gd:280 guard_budget_retry_checks`；真实原生选择器的移动/旋转覆盖、面数与联合费用拒绝：`tests/test_tokyo_map_planner.gd:359 native_motion_guard_checks`。已有切面保留和同步/后台等价：`tests/test_tokyo_map_planner.gd:19 NativeRetentionOverlay`、`tests/test_tokyo_map_planner.gd:443 native_motion_retention_checks`；当前/未来视野包络及零缩放等价：`tests/test_tokyo_map_planner.gd:523 native_motion_query_checks`；预取不重复外推：`tests/test_tokyo_map_planner.gd:553 native_motion_prefetch_checks`。
- 安装M20后的可选Near请求重放：`tests/test_tokyo_map_planner.gd:651 native_joint_cut`、`tests/test_tokyo_map_planner.gd:699 installed_native_gap_diagnostic`、`tests/test_tokyo_map_planner.gd:754 installed_native_retention_diagnostic`、`tests/test_tokyo_map_planner.gd:796 installed_native_motion_diagnostic`核对两视野共同切面与当前保护层保留。C1原请求姿态、共享物理费用和后续覆盖诊断：`tests/test_tokyo_map_planner.gd:906 c1_compact_trace_poses`、`tests/test_tokyo_map_planner.gd:924 c1_compact_pair_bytes`、`tests/test_tokyo_map_planner.gd:938 c1_compact_metrics`、`tests/test_tokyo_map_planner.gd:965 installed_c1_compact_diagnostic`；`AGL_TOKYO_C1_COMPACT_DIAGNOSTIC=1`比较同一冷进入姿态携带旧缩放历史与清零历史后的切面，不改变生产选择器。
- HLOD移动、缩远及共享资源回归：`tests/test_tokyo_hlod_stream.gd:937 MotionPlanProbe`、`tests/test_tokyo_hlod_stream.gd:941 ZoomGuardPool`、`tests/test_tokyo_hlod_stream.gd:948 ZoomForecastPlanner`、`tests/test_tokyo_hlod_stream.gd:955 ZoomForecastOverlay`；`tests/test_tokyo_hlod_stream.gd:980 zoom_footprint_checks`、`tests/test_tokyo_hlod_stream.gd:1072 shared_zoom_source`、`tests/test_tokyo_hlod_stream.gd:1112 shared_zoom_guard_checks`、`tests/test_tokyo_hlod_stream.gd:1280 motion_handoff_checks`验证同档保护带内的共享费用解与同步/后台等价。显式安装诊断使用原请求核验候选和后续实际覆盖：`tests/test_tokyo_hlod_stream.gd:1064 zoom_trace_covered`、`tests/test_tokyo_hlod_stream.gd:1169 zoom_trace_result`、`tests/test_tokyo_hlod_stream.gd:1182 installed_zoom_handoff_diagnostic`。
- 单槽、代次和关闭回归：`tests/tokyo_map_plan_worker_case.gd:23 run`；真实SceneTree接纳回归：`tests/tokyo_map_admission_case.gd:189 direct_checks`、`tests/tokyo_map_admission_case.gd:223 stopped_camera_checks`、`tests/tokyo_map_admission_case.gd:678 revision_and_exit_checks`、`tests/tokyo_map_admission_case.gd:710 run`。后台阻塞期间的显示安全与逐帧方向：`tests/tokyo_map_admission_case.gd:490 pending_display_checks`验证宽限到期、仅清理一次及新revision重试；`tests/tokyo_map_admission_case.gd:533 pending_coverage_checks`验证移出旧视野后隐藏；`tests/tokyo_map_admission_case.gd:559 ready_before_clear_checks`验证领取资源后先接替就绪目标；`tests/tokyo_map_admission_case.gd:581 in_flight_zoom_reversal_checks`验证等待同一请求时仍识别逐帧缩放反转。聚合入口：`tests/tokyo_map_planning_case.gd:3 run`、`tests/tokyo_map_planning_runner.gd:6 _run`（bench `tokyo_map_planning`）；规划和重绘两组亦由`tests/lifecycle_gauntlet_runner.gd:62 _run`调用。
- 接纳夹具与运动时序：`tests/tokyo_map_admission_case.gd:8 Probe`、`tests/tokyo_map_admission_case.gd:37 StreamProbe`、`tests/tokyo_map_admission_case.gd:64 ReplyPlanner`；`tests/tokyo_map_admission_case.gd:171 empty_display_trace_checks`验证空图追踪，`tests/tokyo_map_admission_case.gd:375 pending_motion_sampling_checks`验证后台阻塞期间20/60/120Hz呈现对同一60Hz权威移动的速度采样，`tests/tokyo_map_admission_case.gd:425 cold_jump_prediction_checks`用真实worker验证瞬切重置平移/缩放/方向历史和下一次实际请求，普通移动/缩放保持原平滑；`tests/tokyo_map_admission_case.gd:609 ready_downgrade_reversal_checks`验证放大反转时撤销旧降档事务。
- 原生元数据与节奏回归：`tests/tokyo_map_admission_case.gd:247 native_guard_metadata_checks`覆盖同资源刷新、预取变化和资源/掩码变化；`tests/tokyo_map_admission_case.gd:312 native_guard_cadence_checks`验证三种零保护带阶段的1/60秒采样、静止无计时请求、普通50ms对照及真实单槽合并。
- 呈现时序夹具：`tests/visual_redraw_queue_case.gd:4 CounterCanvas`记录最终物理状态与绘制次数，`tests/visual_redraw_queue_case.gd:67 LifecycleActions`在物理步中触发释放/退出/重入/禁用，`tests/visual_redraw_queue_case.gd:95 MountLockDriver`驱动真实挂点锁定字段。
