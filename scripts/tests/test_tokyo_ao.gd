extends RefCounted
const AO := preload("res://scripts/experiments/tokyo_baked_ao.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var bits := preload("res://scripts/experiments/tokyo_height_bits.gd")
	_check(load("res://scripts/tests/tokyo_height_bits_visual.gd").can_instantiate(),"whole-field GPU decode fixture compiles")
	var bits_manifest := {"height_encoding":"global_palette_r5_lsb","height_size":2048,"height_bits":5,"height_row_bytes":1280,"unique_height_codes":18,"ao_encoding":"bc4_unorm_mips"}
	_check(bits.storage_width(bits_manifest)==1280,"packed height keeps 2048 logical pixels with 1280 byte rows")
	_check(AO.row_bytes(bits_manifest,{"size":2048,"ao_data_bytes":2796216,"conservative_bytes":16254504})==16254504,"packed height charges exact three-copy payload")
	for field: String in ["height_size","height_bits","height_row_bytes","unique_height_codes"]:
		var invalid_bits := bits_manifest.duplicate()
		invalid_bits.erase(field)
		_check(bits.storage_width(invalid_bits)==0,"missing bit contract refused")
	for count: Variant in [0,33,1.5,NAN,true,"18"]:
		var invalid_bits := bits_manifest.duplicate()
		invalid_bits.unique_height_codes=count
		_check(bits.storage_width(invalid_bits)==0,"invalid palette count refused")
	_check(AO.row_bytes(bits_manifest,{"size":2048,"ao_data_bytes":2796216,"conservative_bytes":16254503})==0,"packed lease cannot undercharge")
	var bits_shader: String = AO.make_shader(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code,true,true)
	_check(bits_shader.contains("agl_height_index(local_uv)") and bits_shader.contains("same_surface") and bits_shader.contains("min(byte_x+1,1279)"),"packed GPU lookup preserves height gate and last byte bounds")
	_check(AO.make_shader(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code,false,true).is_empty(),"packed nonpalette shader refused")
	var review := preload("res://scripts/tests/tokyo_preloaded_ao_review.gd")
	var warm := {"state":"pending", "peak_reserved_bytes":524288, "reserved_bytes":524288}
	_check(review.warmup_bytes(warm,true)==524288,"inflight AO cancellation includes live shoreline warm viewport")
	_check(review.warmup_bytes(warm,false)==-1,"missing warm owner cannot retain pending reservation")
	warm.state="ready"
	_check(review.warmup_bytes(warm,true)==524288,"queued warm viewport stays charged until tree exit")
	warm.reserved_bytes=0
	_check(review.warmup_bytes(warm,false)==0 and review.warmup_bytes(warm,true)==-1,"released warm lease is zero only after owner exit")
	warm.state="headless_skipped"
	_check(review.warmup_bytes(warm,false)==0,"headless skip still requires lease release")
	_check(review.warmup_bytes({},false)==-1,"missing warm evidence cannot waive reservation")
	for invalid_bytes: Variant in [-1,524287,524289,true,"524288",NAN]:
		var invalid_warm := {"state":"pending", "peak_reserved_bytes":524288, "reserved_bytes":invalid_bytes}
		_check(review.warmup_bytes(invalid_warm,true)==-1,"invalid or undercharged warm lease rejected")
	var shore := {"meshes":[{"faces":2692},{"faces":2765},{"faces":2768}]}
	var atlas := {"ready":true,"reserved_bytes":1668112,"warm":{"state":"pending","peak_reserved_bytes":524288,"reserved_bytes":524288}}
	_check(review.fixed_atlas_bytes(atlas,true)==2192400,"joint atlas includes live warm viewport")
	_check(review.fixed_atlas_bytes(atlas,false)==-1,"joint atlas refuses missing warm owner")
	atlas.warm.state="ready"
	atlas.warm.reserved_bytes=0
	_check(review.fixed_atlas_bytes(atlas,false)==1668112,"joint atlas retains exact payload after warm release")
	atlas.reserved_bytes-=1
	_check(review.fixed_atlas_bytes(atlas,false)==-1 and review.fixed_atlas_bytes({},false)==-1,"joint atlas missing or undercharged fails")
	_check(review.shoreline_bytes(shore)==4737600,"joint AO review accounts for three resident shoreline meshes")
	var shore_morph := {"schema":2,"meshes":[{"faces":414},{"faces":2278},{"faces":2351},{"faces":2354}],"reserved_bytes":4260672}
	_check(review.shoreline_bytes(shore_morph)==4260672,"joint AO review accounts for four morph shoreline meshes")
	_check(review.shoreline_bytes(JSON.parse_string(JSON.stringify(shore_morph)))==4260672,"morph AO joint budget accepts JSON numeric schema")
	shore_morph.reserved_bytes-=1
	_check(review.shoreline_bytes(shore_morph)==-1,"morph shoreline cannot undercharge")
	_check(review.shoreline_bytes({})==-1 and review.shoreline_bytes({"meshes":[]})==-1,"missing shoreline descriptors cannot waive the charge")
	for faces: Variant in [-1,1.5,NAN,"2692",1000000]:
		var invalid := shore.duplicate(true)
		invalid.meshes[0].faces=faces
		_check(review.shoreline_bytes(invalid)==-1,"invalid shoreline cost rejected")
	_check(AO.bc4_mip_bytes(512)==174776 and AO.bc4_mip_bytes(1024)==699064 and AO.bc4_mip_bytes(2048)==2796216,"BC4 includes smallest padded mip blocks")
	_check(AO.bc4_mip_bytes(0)==0 and AO.bc4_mip_bytes(4096)==0,"unsupported payload sizes refuse")
	var compressed := {"height_encoding":"global_palette_r8","ao_encoding":"bc4_unorm_mips"}
	var packed_row := {"size":2048,"ao_data_bytes":2796216,"conservative_bytes":20973096}
	_check(AO.row_bytes(compressed,packed_row)==20973096,"BC4 conservative lease keeps three copies and full height")
	var broken := packed_row.duplicate()
	broken.ao_data_bytes-=8
	_check(AO.row_bytes(compressed,broken)==0,"truncated mip descriptor refuses")
	broken=packed_row.duplicate()
	broken.conservative_bytes-=1
	_check(AO.row_bytes(compressed,broken)==0,"undercharged compressed lease refuses")
	_check(AO.row_bytes({"height_encoding":"global_palette_r8"},{"size":2048,"conservative_bytes":29361664})==29361664,"old R8 budget remains exact")
	_check(AO.row_bytes({"ao_encoding":"unknown"},packed_row)==0 and AO.row_bytes({"ao_encoding":"bc4_unorm_mips"},packed_row)==0,"unknown encoding and compressed nonpalette input refuse")
	var exporter := preload("res://scripts/tests/export_tokyo_ao.gd")
	_check(exporter.region_for("")==Rect2(-6100,-1300,400,400) and exporter.region_for("south")==exporter.REGION,"default export preserves southern region")
	_check(exporter.region_for("north_density")==Rect2(-5600,-3100,400,400),"north sample has explicit native coordinates")
	_check(exporter.region_for("west_density")==Rect2(-6750,-2400,400,400),"west sample stays inside current native extension")
	_check(exporter.region_for("west_extension_density")==Rect2(-7250,-2600,400,400),"new west sample stays inside four-region corridor without moving old AO")
	_check(not exporter.region_for("unknown").has_area() and not exporter.region_for("NORTH_DENSITY").has_area(),"unknown region rejects without fallback")
	var cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var root := {"key":"parent","boxes":[AABB(Vector3(-10,0,-10),Vector3(20,5,20)),AABB(),AABB()],"triangles":PackedInt32Array([400,0,0]),"bytes":60*1024*1024}
	var child: Dictionary = root.duplicate(true)
	child.key="leaf"
	child.triangles=PackedInt32Array([100,0,0])
	child.bytes=80*1024*1024
	root.children=[child]
	var parents: Array[Dictionary]=[root]
	var full := cut.choose(parents,Rect2(-20,-20,40,40),Transform2D(0,Vector2(20,20)),Vector2(40,40),Vector2.ZERO,Vector2.ZERO)
	var reserved := cut.choose(parents,Rect2(-20,-20,40,40),Transform2D(0,Vector2(20,20)),Vector2(40,40),Vector2.ZERO,Vector2.ZERO,16,71*1024*1024)
	var impossible := cut.choose(parents,Rect2(-20,-20,40,40),Transform2D(0,Vector2(20,20)),Vector2(40,40),Vector2.ZERO,Vector2.ZERO,16,59*1024*1024)
	_check(full.entries[0].key=="leaf" and full.within_budget,"default solver still uses original full budget")
	_check(reserved.entries[0].key=="parent" and reserved.within_budget,"AO lease makes memory-feasible complete cut win over cheaper faces")
	_check(not impossible.within_budget and impossible.active==1,"insufficient remaining budget reports failure without hiding geometry")
	var rows := [{"size": 512, "max_scale": 1.28}, {"size": 1024, "max_scale": 2.56}, {"size": 2048, "max_scale": 5.12}]
	_check(AO.choose_row(rows, 1.28)["size"] == 512, "output resolution inclusive")
	_check(AO.choose_row(rows, 1.281)["size"] == 1024, "closer camera cannot stretch low resolution")
	_check(AO.choose_row(rows, 5.0)["size"] == 2048, "highest supported view")
	for value: float in [0.0, -1.0, INF, NAN, 5.121]:
		_check(AO.choose_row(rows, value).is_empty(), "invalid or unprepared resolution rejected")
	var original := preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var shader := AO.make_shader(original)
	var indexed_shader := AO.make_shader(original, true)
	_check(indexed_shader.contains("baked_height_palette") and indexed_shader.contains("same_surface"), "lossless palette keeps receiver guard")
	_check(AO.make_shader("drift").is_empty(), "source shader drift rejected")
	_check(AO.make_shader(preload("res://scripts/experiments/tokyo_static_shadow.gd").shader_code(original)).is_empty(), "unbudgeted static-shadow stacking rejected")
	_check(AO.make_shader(shader).is_empty(), "second AO owner cannot stack or corrupt rollback")
	_check(shader.contains("ALBEDO = base;") and shader.contains("ALBEDO * ATTENUATION *"), "albedo and direct shadow unchanged")
	_check(shader.contains("ao_local = VERTEX") and shader.contains("same_surface") and shader.contains("ao_up > 0.99"), "source coordinate height and normal receiver guards")
	_check(not shader.contains("TIME") and not shader.contains("SCREEN_TEXTURE"), "bake is not camera/time/screen-space dependent")
	var layer := AO.new()
	layer._texture = ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_R8))
	var derived := ShaderMaterial.new()
	derived.shader = Shader.new()
	derived.shader.code = shader
	_check(not layer.track_material(derived),"foreign material cannot join AO strength owner")
	derived.set_shader_parameter("baked_ao",layer._texture)
	layer.strength(0.25)
	_check(layer.track_material(derived) and is_equal_approx(float(derived.get_shader_parameter("ao_strength")),0.25),"late derived material inherits current AO strength")
	_check(layer.track_material(derived) and layer._derived_materials.size()==1,"duplicate material registration is idempotent")
	layer.strength(0.65)
	_check(is_equal_approx(float(derived.get_shader_parameter("ao_strength")),0.65),"derived material follows strength without a new tick")
	layer.strength(NAN)
	_check(is_equal_approx(float(derived.get_shader_parameter("ao_strength")),0.65),"invalid strength cannot poison derived uniforms")
	var derived_ref: WeakRef = weakref(derived)
	derived = null
	layer.strength(0.45)
	_check(derived_ref.get_ref()==null and layer._derived_materials.is_empty(),"AO registration does not retain a freed derived material")
	layer.close()
	layer.close()
	_check(layer._texture == null and layer._height_texture == null and layer._owner == null, "idempotent empty release")
	_check(load("res://scripts/tests/export_tokyo_ao.gd").can_instantiate(), "native source exporter compiles")
	_check(load("res://scripts/tests/tokyo_ao_review.gd").can_instantiate(), "actual AO route review compiles")
	_check(load("res://scripts/tests/tokyo_preloaded_ao_review.gd").can_instantiate(), "preloaded AO route review compiles")
	_check(load("res://scripts/rendering/tokyo_canonical_overlay.gd").can_instantiate(), "preloaded canonical overlay compiles")
	var stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	stream._bytes = 11
	stream._reserved = 7
	_check(not stream.reserve_auxiliary(1, stream.BUDGET - 17), "aux reserve includes resident and inflight geometry")
	_check(stream.reserve_auxiliary(1, stream.BUDGET - 18), "exact shared limit accepted")
	_check(stream.geometry_budget() == 18 and stream.summary().total_bytes == stream.BUDGET, "geometry admission uses remaining shared limit")
	_check(not stream.reserve_auxiliary(1, 1) and not stream.reserve_auxiliary(2, 1), "duplicate owner and overbudget rejected")
	stream.release_auxiliary(999)
	_check(stream.geometry_budget() == 18, "foreign release cannot erase owner budget")
	stream.release_auxiliary(1)
	stream.release_auxiliary(1)
	_check(stream.geometry_budget() == stream.BUDGET and stream.peak_total_bytes == stream.BUDGET, "idempotent release preserves combined peak")
	_check(not stream.reserve_auxiliary(0, 1) and not stream.reserve_auxiliary(2, -1), "invalid lease refused")
	_check(stream.reserve_auxiliary(layer.get_instance_id(), 1), "actual RefCounted signed instance ID is a valid lease owner")
	stream.release_auxiliary(layer.get_instance_id())
	var session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
	_check(not session.state_ready({"level": 0, "blend": 1.0, "ao_required": true, "ao_ready": false}), "geometry readiness cannot hide missing required AO")
	_check(not session.state_ready({"level": 0, "blend": 1.0, "ao_error": "missing"}), "AO preparation failure prevents ready")
	stream.free()
	print("[R64 AO test] pass=", _pass, " fail=", _fail)


static func lifecycle(parent: Node) -> int:
	var owner := Node.new()
	parent.add_child(owner)
	var layer := AO.new()
	var stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	stream.configure(owner, {})
	parent.add_child(stream)
	var stream_ref: WeakRef = weakref(stream)
	var reserved := stream.reserve_auxiliary(layer.get_instance_id(), 1536)
	layer._budget_stream = weakref(stream)
	layer._owner = weakref(owner)
	layer._original.append(ShaderMaterial.new())
	layer._replacement.append(ShaderMaterial.new())
	layer._height_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RG8))
	layer._height_palette = ImageTexture.create_from_image(Image.create(256, 1, false, Image.FORMAT_RG8))
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var held: bool = is_instance_valid(stream) and stream.summary().closed and stream.summary().auxiliary_bytes == 1536
	var derived := ShaderMaterial.new()
	derived.shader = Shader.new()
	derived.shader.code = AO.make_shader(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code)
	layer._texture = ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_R8))
	derived.set_shader_parameter("baked_ao",layer._texture)
	var tracked := layer.track_material(derived)
	var derived_ref: WeakRef = weakref(derived)
	derived = null
	await parent.get_tree().process_frame
	layer.strength(0.0)
	var derived_released: bool = tracked and derived_ref.get_ref()==null and layer._derived_materials.is_empty()
	layer.close()
	layer.close()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var ok: bool = reserved and held and derived_released and stream_ref.get_ref() == null and layer._budget_stream == null \
		and layer._owner == null and layer._texture == null and layer._height_texture == null \
		and layer._height_palette == null and layer._original.is_empty() and layer._replacement.is_empty()
	print("[R64 AO lifecycle] freed owner cleanup=", ok)
	if not ok:
		print("[R66 lease failure] key=", layer.get_instance_id(), " reserved=", reserved, " held=", held,
			" stream_released=", stream_ref.get_ref() == null, " lease_released=", layer._budget_stream == null)
	return 0 if ok else 1


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R64 AO " + label)
