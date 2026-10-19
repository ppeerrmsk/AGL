extends RefCounted
## 真实预载/驻留成本试验；不授予低精图近景资格，不改变正式流送预算。
const Overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd")
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")

class TrialStream extends "res://scripts/rendering/tokyo_hlod_stream.gd":
	var trial_limit := 96*1024*1024
	func geometry_budget() -> int:
		return trial_limit-_auxiliary_bytes

static func costs(geometry: Dictionary, textures: Dictionary, meshes: PackedStringArray, images: PackedStringArray) -> Dictionary:
	var physical: Dictionary={}
	var unique_images: Dictionary={}
	for path: String in meshes:
		for part: String in geometry[path].get("components",{path:geometry[path]}):
			physical[part]=geometry[path].get("components",{path:geometry[path]})[part]
	for path: String in images: unique_images[path]=textures[path]
	var mesh_bytes := 0
	var mip_bytes := 0
	var charged_images := 0
	for row: Dictionary in physical.values(): mesh_bytes+=int(row.bytes)
	for row: Dictionary in unique_images.values():
		mip_bytes+=int(row.mip_bytes)
		charged_images+=int(row.charge)
	return {"geometry_contract_bytes":mesh_bytes,"texture_mip_bytes":mip_bytes,
		"texture_three_copy_charge":charged_images,"contract_bytes_excluding_ground":mesh_bytes+charged_images,
		"physical_meshes":physical.size(),"textures":unique_images.size(),
		"fits_resource_pool":mesh_bytes+charged_images<=Stream.BUDGET}


static func counters() -> Dictionary:
	return {"engine_static_bytes":OS.get_static_memory_usage(),
		"renderer_texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"renderer_buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}


static func loaded(stream: Node, meshes: PackedStringArray, images: PackedStringArray) -> bool:
	for path: String in meshes:
		if stream.resource(path)==null: return false
	for path: String in images:
		if stream.texture(path)==null: return false
	return true


static func trial(parent: Node, geometry: Dictionary, textures: Dictionary, meshes: PackedStringArray, images: PackedStringArray, limit: int = Stream.BUDGET) -> Dictionary:
	var tree := parent.get_tree()
	var owner_node := Node.new()
	parent.add_child(owner_node)
	var stream := TrialStream.new()
	stream.trial_limit=limit
	tree.root.add_child(stream)
	var selected_geometry: Dictionary={}
	var selected_images: Dictionary={}
	for path: String in meshes: selected_geometry[path]=geometry[path]
	for path: String in images: selected_images[path]=textures[path]
	var result := {"before":counters(),"fail":0,"budget":limit,"gameplay_verified":false,
		"experimental_budget":limit!=Stream.BUDGET}
	assert(limit>0 and limit<=256*1024*1024)
	if not stream.configure_hlod(owner_node,selected_geometry,selected_images): result.fail+=1
	var started_at := Time.get_ticks_msec()
	stream.request(meshes,meshes)
	stream.request_textures(images,images)
	while not loaded(stream,meshes,images) and Time.get_ticks_msec()-started_at<30000:
		await tree.process_frame
	result["load_ms"]=Time.get_ticks_msec()-started_at
	result["all_ready"]=loaded(stream,meshes,images)
	result.fail+=int(not result.all_ready)
	for frame in 3: await tree.process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	result["resident"]=counters()
	var started_meshes: int=stream.started
	var started_images: int=stream.texture_started
	# 模拟已预载资源在进入场景后继续被不同可见子集使用，不额外持有返回的Resource。
	for n in 48:
		stream.request(PackedStringArray([meshes[n%meshes.size()]]),meshes)
		stream.request_textures(PackedStringArray([images[n%images.size()]]),images)
		await tree.process_frame
	await tree.create_timer(3.0).timeout
	result["retained_all"]=loaded(stream,meshes,images)
	result["mesh_reloads"]=stream.started-started_meshes
	result["texture_reloads"]=stream.texture_started-started_images
	result["stream"]=stream.summary()
	result.fail+=int(not result.retained_all or result.mesh_reloads!=0 or result.texture_reloads!=0 \
		or stream.peak_total_bytes>limit or not stream._failures.is_empty() or not stream._texture_errors.is_empty())
	var reference: WeakRef=weakref(stream)
	owner_node.queue_free()
	stream=null
	var deadline := Time.get_ticks_msec()+10000
	while reference.get_ref()!=null and Time.get_ticks_msec()<deadline: await tree.process_frame
	for frame in 3: await tree.process_frame
	result["released"]=reference.get_ref()==null and Stream._busy.is_empty()
	result["after_release"]=counters()
	result.fail+=int(not result.released)
	return result


static func run(parent: Node, output: String) -> int:
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var overlay := Overlay.new()
	var archive: Resource=overlay._load_archive()
	if archive==null:
		overlay.free()
		return 1
	var meshes := PackedStringArray()
	var images := PackedStringArray()
	var report := {"schema":1,"headless":DisplayServer.get_name()=="headless","budget":Stream.BUDGET,
		"catalogs":[],"trials":[],"fail":0,"normal_loading_changed":false}
	for n in overlay._catalogs.size():
		var catalog: Dictionary=overlay._catalogs[n]
		for depth in 3:
			var level_meshes := PackedStringArray()
			var level_images := PackedStringArray()
			for row: Dictionary in catalog.rows.values():
				if int(row.depth)!=depth: continue
				level_meshes.append(row.native_geometry.path)
				level_images.append(row.native_texture.path)
			var cost := costs(overlay._geometry,overlay._textures,level_meshes,level_images)
			cost["catalog"]=n;cost["depth"]=depth;cost["range"]=catalog.range
			report.catalogs.append(cost)
			meshes.append_array(level_meshes);images.append_array(level_images)
			if depth==0 and n<2:
				if not cost.fits_resource_pool: report.fail+=1;continue
				var sample := await trial(parent,overlay._geometry,overlay._textures,level_meshes,level_images)
				sample["catalog"]=n
				report.trials.append(sample)
				report.fail+=int(sample.fail)
				print("[Map residency] catalog=",n," load_ms=",sample.load_ms," fail=",sample.fail)
			if n==3 and depth==2 and OS.get_environment("AGL_TOKYO_RESIDENCY_MIDDLE")=="1":
				if int(cost.contract_bytes_excluding_ground)>256*1024*1024: report.fail+=1;continue
				var sample := await trial(parent,overlay._geometry,overlay._textures,level_meshes,level_images,256*1024*1024)
				sample["catalog"]=n;sample["depth"]=depth
				report.trials.append(sample);report.fail+=int(sample.fail)
				print("[Map residency] catalog=",n," depth=",depth," load_ms=",sample.load_ms," fail=",sample.fail)
	report["all_hlod"]=costs(overlay._geometry,overlay._textures,meshes,images)
	var all_geometry := PackedStringArray(overlay._geometry.keys())
	report["all_hlod_and_native"]=costs(overlay._geometry,overlay._textures,all_geometry,images)
	archive=null
	overlay.free()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	return 0 if report.fail==0 else 1
