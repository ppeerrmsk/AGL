extends RefCounted
## 显式静态对拍；原生地表对照，不冒充连续LOD/实际战斗性能。
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Ready := preload("res://scripts/tests/tokyo_canonical_review.gd")
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Codec := preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd")


static func shader_code(source: String) -> String:
	return preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").shader_code(source)


static func plane(rect: Rect2, uv: Rect2) -> ArrayMesh:
	return preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(rect,uv)


static func complete_native(scale_value: float, faces: int, expected: int, compatible: bool) -> bool:
	return is_finite(scale_value) and scale_value>0 and scale_value<=0.3888 and expected>0 and faces==expected and compatible


static func complete_fine(scale_value: float, faces: int, expected: int, compatible: bool, step: float) -> bool:
	return step==1.0 and is_finite(scale_value) and scale_value>0 and scale_value<=0.7776 and expected>0 and faces==expected and compatible


static func fine_configuration(configuration: Variant) -> bool:
	return configuration is String and configuration in ["lod1_full","lod2_full","lod2_guarded","lod3_full","lod3_guarded"]


static func run(battle: Node, map: Node, output: String) -> int:
	var directory := OS.get_environment("AGL_TOKYO_FIXED_ATLAS_REVIEW")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if not Codec.manifest_valid(manifest) or manifest.get("encoding")!="bc3_rgba_mips" or manifest.get("catalog_sha256")!=map._canonical_sha:
		return 1
	if FileAccess.get_sha256(manifest.source.source)!=manifest.source.source_sha256:
		return 1
	var fine := OS.get_environment("AGL_TOKYO_FIXED_FINE_REVIEW")=="1"
	if fine and (map._canonical_sha!=preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").RESIDENTIAL_SHA or manifest.parent!=11 \
			or FileAccess.get_sha256(directory.path_join("manifest.json"))!="420384d7f4cb8a1ebbe2add04a2005548b24bf4eea4554257e53c87b76ffd422" \
			or FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_FIXED_FINE_PROOF"))!="020f78b1e1215adb9ae1f349c32a262a0c81a58d006a7375a58c17d66a0bd0ab"):
		return 1
	if fine and (FileAccess.get_sha256(directory.get_base_dir().path_join("r172-lod3_full-equivalence.json"))!="eb14734a0aaafec97d249957dac9ec20b6283bf94ec2d1f25fd8ae5e5fece346" \
			or FileAccess.get_sha256(directory.get_base_dir().path_join("r172-lod3_guarded-equivalence.json"))!="8c0f989f17fa608665b553fb405f4d26f7e2ce9f1280da23932f9383da64b9f5"):
		return 1
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	var source: Node = battle._map_features._raster_basemap
	var source_mode: int = source.process_mode
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var geometry := preload("res://scripts/tests/tokyo_static_shadow_review.gd").new()
	tree.paused=true
	source.process_mode=Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation=false
	var fail := 0
	var applied_variants := 0
	var near_refusals := 0
	var fine_applications := 0
	var region: Dictionary = Codec.region_contract(manifest.parent,str(manifest.catalog_sha256))
	var center := Vector2((region.bounds[0]+region.bounds[2])*.5,(region.bounds[1]+region.bounds[3])*.5)
	var rows: Array[Dictionary] = []
	var poses := [Vector2(.13,0),Vector2(.26,0),Vector2(.4,0),Vector2(.4,-14),Vector2(.4,14),Vector2(.52,0),Vector2(.98,0),Vector2(.13,0)]
	if fine:
		poses=[Vector2(.4,0),Vector2(.52,0),Vector2(.65,0),Vector2(.65,-14),Vector2(.65,14),Vector2(.98,0),Vector2(1.3,0),Vector2(.4,0)]
	for pose: Vector2 in poses:
		battle.camera.position=center
		battle.camera.zoom=Vector2.ONE*pose.x
		battle.camera.rotation=deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		var deadline := Time.get_ticks_msec()+15000
		var stable := 0
		while Time.get_ticks_msec()<deadline:
			await RenderingServer.frame_post_draw
			if Ready.ready_at_canvas(map._last_canvas,battle.get_viewport().get_canvas_transform(),map.debug_state()) and Ready.source_ready(source):
				if stable==0:
					stable=Time.get_ticks_msec()
				if Time.get_ticks_msec()-stable>=200:
					break
			else:
				stable=0
		if stable==0 or Time.get_ticks_msec()-stable<200:
			fail+=1
			break
		map.set_process(false)
		map._release_tile_ground()
		var before_state := geometry._geometry_state(map)
		var stem := output.path_join("r141_atlas_%02d" % rows.size())
		var original := await Capture._capture(battle,map,stem+"_original")
		var original_primitives: int = map._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		var scale_value: float = map.debug_state().output_scale
		var held: Array[Dictionary] = []
		var saved_faces := 0
		var material: ShaderMaterial
		var compatible := true
		var configurations: Dictionary = {}
		for batch: Dictionary in map._batches.values():
			var identity: Dictionary = map._descriptors[batch.path].canonical_identity
			if int(identity.get("parent",-1))!=int(manifest.parent) or not batch.nodes[2].visible:
				continue
			var configuration := str(identity.get("configuration"))
			configurations[configuration]=int(configurations.get(configuration,0))+int(batch.layer_triangles[2])
			compatible=compatible and (fine_configuration(identity.get("configuration")) if fine else identity.get("configuration")=="lod2_full")
			held.append({"node":weakref(batch.nodes[2]),"visible":true})
			saved_faces+=int(batch.layer_triangles[2])
			material=batch.nodes[2].material_override
		var variants: Array[Dictionary] = []
		var selected_rows: Array = [manifest.rows[1]] if fine else manifest.rows
		for row: Dictionary in selected_rows:
			var eligible := complete_fine(scale_value,saved_faces,int(region.faces),compatible,float(row.world_step)) if fine else complete_native(scale_value,saved_faces,int(region.faces),compatible)
			var info := {"step":row.world_step,"eligible":eligible,"applied":false,"native_faces":saved_faces,"native_configuration_compatible":compatible,"native_configurations":configurations}
			near_refusals+=int(scale_value>(0.7776 if fine else 0.3888) and not eligible)
			if eligible:
				if not row.get("rectangular_coverage",false) or not row.get("premultiplied_alpha",false):
					fail+=1
					break
				var path := directory.path_join(str(row.file))
				if FileAccess.get_sha256(path)!=row.sha256:
					fail+=1
					break
				var image := Image.create_from_data(int(row.width),int(row.height),true,Image.FORMAT_DXT5,FileAccess.get_file_as_bytes(path))
				var charge: int = image.get_data().size()*3+4096 if image!=null else -1
				if image==null or charge!=int(row.conservative_bytes):
					fail+=1
					break
				var texture := ImageTexture.create_from_image(image)
				var lease := texture.get_instance_id()
				if not map._stream.reserve_auxiliary(lease,charge):
					fail+=1
					info["budget_rejected"]=true
					variants.append(info)
					continue
				var code := shader_code(material.shader.code) if material!=null else ""
				var candidate: MeshInstance3D
				var replacement: ShaderMaterial
				if not code.is_empty() and saved_faces>0:
					for saved: Dictionary in held:
						var native: Variant = saved.node.get_ref()
						if typeof(native)==TYPE_OBJECT and is_instance_valid(native):
							native.hide()
						else:
							fail+=1
					var bounds: Array = row.native_bounds
					var rect := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
					var bake_bounds: Array = row.bounds
					var bake_rect := Rect2(float(bake_bounds[0]),float(bake_bounds[1]),float(bake_bounds[2])-float(bake_bounds[0]),float(bake_bounds[3])-float(bake_bounds[1]))
					var uv := Rect2((rect.position-bake_rect.position)/bake_rect.size,rect.size/bake_rect.size)
					var shader := Shader.new()
					shader.code=code
					replacement = material.duplicate()
					replacement.shader=shader
					replacement.set_shader_parameter("fixed_atlas",texture)
					replacement.set_shader_parameter("lod_mix",1.0)
					replacement.set_shader_parameter("outgoing",false)
					if code.contains("fixed_ground_height_range"):
						replacement.set_shader_parameter("fixed_ground_height_range",Vector2(row.height_range[0],row.height_range[1]))
					candidate=map._add_mesh(plane(rect,uv),replacement,false)
					candidate.position.y=float(row.height_range[0])
					applied_variants+=1
					fine_applications+=int(fine and scale_value>0.3888)
					info.merge({"applied":true,"retired_fixed_faces":saved_faces,"added_faces":2,"conservative_bytes":charge,"joint_peak_bytes":map._stream.summary().peak_total_bytes,"gpu_format":texture.get_format(),"bounds":bounds},true)
					var ray: Vector3 = map._city.basis.inverse()*map._camera.basis.z
					info["max_height_shift_output_px"]=(float(row.height_range[1])-float(row.height_range[0]))*Vector2(ray.x,ray.z).length()/absf(ray.y)*scale_value
					info["allowed_screen_bounds"]=Pixels._screen_bounds(map,[{"original":[[rect.position.x,rect.position.y],[rect.end.x,rect.position.y],[rect.end.x,rect.end.y],[rect.position.x,rect.end.y]],"candidate":[],"height_px":1.0}])
				else:
					fail+=1
				await Capture._capture(battle,map,stem+"_step%d" % int(row.world_step))
				info["visible_primitives_before"]=original_primitives
				info["visible_primitives_after"]=map._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
				info["visible_primitives_saved"]=original_primitives-int(info.visible_primitives_after)
				if is_instance_valid(candidate):
					candidate.queue_free()
				for saved: Dictionary in held:
					var node: Variant = saved.node.get_ref()
					if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
						node.visible=saved.visible
					else:
						fail+=1
				var texture_ref: WeakRef = weakref(texture)
				replacement=null
				texture=null
				image=null
				await tree.process_frame
				info["texture_released"]=texture_ref.get_ref()==null
				fail+=int(not info.texture_released)
				map._stream.release_auxiliary(lease)
			variants.append(info)
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var same: bool = before_state==geometry._geometry_state(map) and collision==var_to_bytes(BuildingRenderer._cache_entries)
		var restore_error := Pixels._pixel_error(original,restored)
		fail+=int(not same or restore_error>1)
		rows.append({"pose":str(pose),"center":str(center),"scale":scale_value,"variants":variants,"geometry_collision_restored":same,"restore_max":restore_error,"stem":stem})
		map._viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		map.set_process(true)
		print("[R141 atlas Visual] pose=",pose," variants=",JSON.stringify(variants)," restore=",restore_error)
	tree.paused=paused
	source.process_mode=source_mode
	battle.camera.ignore_rotation=ignore
	fail+=int(applied_variants<2 or near_refusals<2 or rows.size()!=8)
	fail+=int(fine and fine_applications<1)
	var file := FileAccess.open(output.path_join("r141_atlas_review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"parent":manifest.parent,"applied_variants":applied_variants,"fine_applications":fine_applications,"near_refusals":near_refusals,"rows":rows,"static_native_ground_control":true,"fps_evidence":false,"continuous_lod_evidence":false,"catalog_sha256":map._canonical_sha},"\t"))
	file.close()
	return fail
