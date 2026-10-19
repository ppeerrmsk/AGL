extends RefCounted
const Ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	for passed: bool in preload("res://scripts/tests/test_tokyo_low_walls.gd").checks():
		_check(passed,"low wall identity/budget/atomic component reference contract")
	_check(preload("res://scripts/tests/tokyo_residential_patch.gd").checks(),"residential attribute import rejects malformed bytes, normals and color")
	_check(preload("res://scripts/tests/test_tokyo_residential_selection.gd").checks(),"residential whole roof/wall component, height, boundary and directed conservation")
	_check(preload("res://scripts/tests/test_tokyo_rail_catalog.gd").checks(),"rail partition preserves same-height nonrail color and rejects bad plan")
	_check(preload("res://scripts/tests/test_rail_obstacle_export.gd").checks(preload("res://scripts/tests/export_tokyo_rail_obstacles.gd")),"current native rail obstacle indexed/nonindexed and bounds contract")
	_test_fixed_expansion()
	_test_flat_bc3()
	for passed: bool in preload("res://scripts/tests/test_tokyo_fixed_atlas_layer.gd").checks():
		_check(passed,"fixed atlas native/manifest/scale contract")
	var atlas := preload("res://scripts/tests/tokyo_fixed_atlas_review.gd")
	_check(atlas.complete_fine(.7776,28145,28145,true,1.0),"fine atlas static trial includes exact upper screen scale")
	_check(atlas.fine_configuration("lod3_full") and atlas.fine_configuration("lod3_guarded"),"fine static preview includes proven lod3 fixed attributes")
	for configuration: Variant in ["lod0_full","lod4_full","lod4_mid","lod5_full",null,1]:
		_check(not atlas.fine_configuration(configuration),"fine static preview rejects unproven configuration and invalid type")
	for scale: float in [-1,0,NAN,INF,.77761]:
		_check(not atlas.complete_fine(scale,28145,28145,true,1.0),"fine atlas rejects invalid or excessive scale")
	_check(not atlas.complete_fine(.5,28145,28145,true,2.0) and not atlas.complete_fine(.5,28144,28145,true,1.0) and not atlas.complete_fine(.5,28145,28145,false,1.0),"fine atlas rejects coarse texture, partial coverage and unproven source")
	var atlas_source: String = preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	_check(not atlas.shader_code(atlas_source).is_empty(),"fixed atlas keeps native lighting and LOD shader")
	_check(atlas.shader_code("drift").is_empty() and atlas.shader_code(atlas.shader_code(atlas_source)).is_empty(),"fixed atlas source drift and stacking refuse")
	_check(load("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd").can_instantiate(),"fixed atlas offline BC3 fixture compiles")
	var atlas_mesh: ArrayMesh = atlas.plane(Rect2(0,0,10,10),Rect2(0,0,1,1))
	var atlas_arrays := atlas_mesh.surface_get_arrays(0)
	_check(atlas_arrays[Mesh.ARRAY_INDEX]==PackedInt32Array([0,1,2,0,2,3]),"fixed atlas front faces match lit clockwise surfaces")
	_check(not atlas.shader_code(atlas_source).contains("ground_sample.a <") and not atlas.shader_code(atlas_source).contains("cull_disabled"),"rectangular fixed coverage uses mesh MSAA and original face lighting")
	var coverage := preload("res://scripts/experiments/tokyo_tile_coverage.gd")
	_check(load("res://scripts/tests/tokyo_visible_ground_review.gd").can_instantiate(),"visible ground same-camera native pixel review compiles")
	var box := AABB(Vector3(-10,-.5,-10),Vector3(30,1,30))
	var tiles: Array[Rect2] = [Rect2(0,0,10,10)]
	_check(not coverage.flat_covered(box,tiles) and coverage.visible_flat_covered(box,tiles,Rect2(2,2,6,6),Vector2.ZERO),"screen-only coverage permits offscreen native ground remainder")
	_check(not coverage.visible_flat_covered(box,tiles,Rect2(-1,2,6,6),Vector2.ZERO),"one visible uncovered strip retains native geometry")
	_check(not coverage.visible_flat_covered(box,[Rect2(0,0,4.99,10),Rect2(5,0,5,10)],Rect2(2,2,6,6),Vector2.ZERO),"visible subpixel tile gap rejected")
	_check(not coverage.visible_flat_covered(box,tiles,Rect2(0,0,10,10),Vector2(1,0)),"height projection extends required source beyond covered tiles")
	_check(coverage.visible_flat_covered(box,[Rect2(-.5,0,11,10)],Rect2(0,0,10,10),Vector2(1,0)),"both positive and negative height source shifts covered")
	_check(not coverage.visible_flat_covered(AABB(Vector3.ZERO,Vector3(10,2,10)),tiles,Rect2(2,2,6,6),Vector2.ZERO),"nonflat elevated geometry never retired")
	_check(not coverage.visible_flat_covered(box,tiles,Rect2(),Vector2.ZERO) and not coverage.visible_flat_covered(box,tiles,Rect2(0,0,10,10),Vector2(INF,0)),"invalid visible projection rejected")
	for passed: bool in preload("res://scripts/tests/test_tokyo_shoreline_morph.gd").checks():
		_check(passed,"shoreline native morph contract")
	_test_submission_peak()
	var finish := preload("res://scripts/tests/tokyo_district_finish_review.gd")
	var finish_source: String = preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var finish_mask: String = finish.low_mask_code(finish_source)
	_check(not finish_mask.is_empty() and finish_mask.contains("finish_mask_local=VERTEX") and not finish_mask.contains("DIFFUSE_LIGHT +="),"finish mask uses original geometry without illumination")
	_check(finish.low_mask_code(finish_mask).is_empty() and finish.low_mask_code("drift").is_empty(),"finish mask rejects repeated adaptation and drift")
	_check(finish.replacement(ShaderMaterial.new(),"")==null,"finish rejects absent shader code")
	_check(load("res://scripts/tests/tokyo_district_boundary_review.gd").can_instantiate(),"district boundary review compiles")
	var tone := preload("res://scripts/experiments/tokyo_low_tone_candidate.gd")
	_check(tone.weight(.3)==1.0 and tone.weight(.5)==0.0 and is_equal_approx(tone.weight(.4),.5),"far low tone smooth range")
	_check(tone.weight(NAN)==0.0 and tone.weight(-1)==0.0,"invalid tone scale preserves original")
	var tone_code: String = tone.shader_code(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code,.9)
	_check(not tone_code.is_empty() and tone.shader_code(tone_code,.8).is_empty(),"tone adapts once")
	_check(tone.shader_code("drift",.9).is_empty() and tone.shader_code(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code,.5).is_empty(),"tone rejects drift or unknown factor")
	for passed: bool in preload("res://scripts/tests/test_tokyo_shoreline_layer.gd").checks():
		_check(passed,"shoreline LOD/coverage shader contract")
	var shore := preload("res://scripts/experiments/tokyo_shoreline_candidate.gd")
	var shore_data := {"width":1.0,"height":0.03,"rgb":[70,82,83],"triangles":[[0,0],[0,1],[1,0]]}
	var shore_mesh := shore.build(shore_data)
	var shore_json: Dictionary = JSON.parse_string(JSON.stringify(shore_data))
	_check(shore.build(shore_json)!=null,"shoreline accepts JSON roundtrip contract")
	shore_json.rgb[0] = 70.1
	_check(shore.build(shore_json)==null,"shoreline does not truncate fractional color mismatch")
	_check(shore_mesh!=null and shore_mesh.surface_get_array_len(0)==3,"shoreline native fixture builds")
	var shore_arrays := shore_mesh.surface_get_arrays(0)
	var shore_normal: Vector3 = shore_arrays[Mesh.ARRAY_NORMAL][0]
	var shore_vertices: PackedVector3Array = shore_arrays[Mesh.ARRAY_VERTEX]
	# ArrayMesh法线八面体编码有量化误差；另查原生顺时针序，不能用容差掩盖翻面。
	_check(shore_normal.distance_to(Vector3.UP)<0.0001 and (shore_vertices[1]-shore_vertices[0]).cross(shore_vertices[2]-shore_vertices[0]).y<0,"shoreline winding and normal face up: "+str(shore_normal))
	_check(shore.build({})==null,"shoreline rejects absent contract")
	shore_data.triangles = [[0,0],[NAN,1],[1,0]]
	_check(shore.build(shore_data)==null,"shoreline rejects nonfinite coordinates")
	shore_data.triangles = [[0,0],[0,0],[1,0]]
	_check(shore.build(shore_data)==null,"shoreline rejects degenerate faces")
	_check(load("res://scripts/tests/tokyo_shoreline_review.gd").can_instantiate(),"shoreline static review compiles")
	var water_palette := preload("res://scripts/experiments/tokyo_ground_palette_candidate.gd")
	var palette_source: String = preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	_check(water_palette.shader_code(palette_source).contains("ground_palette_only_class = -1"), "semantic-only palette remains opt-in")
	_check(water_palette.shader_code(palette_source,Rect2(-6300,-3700,4000,4000)).contains("<= 300.000000") and water_palette.shader_code(palette_source,Rect2()).is_empty(), "palette bounds expand explicitly and reject invalid extent")
	_check(load("res://scripts/tests/tokyo_water_palette_review.gd").can_instantiate(), "water-only native review compiles")
	_check(Ground.valid_bounds(Ground.BOUNDS) and Ground.new().coverage_bounds == Ground.BOUNDS, "default ground coverage unchanged")
	_check(not Ground.valid_bounds(Rect2()) and not Ground.valid_bounds(Rect2(0,0,-1,1)), "empty or inverted ground coverage rejected")
	_check(not Ground.valid_bounds(Rect2(Vector2(NAN,0),Vector2.ONE)) and not Ground.valid_bounds(Rect2(Vector2.ZERO,Vector2(INF,1))), "nonfinite ground coverage rejected")
	_check(load("res://scripts/tests/tokyo_ground_boundary_review.gd").can_instantiate(), "boundary review compiles")
	var original := preload("res://resources/shaders/basemap_streamed.gdshader").code
	var plain := Ground.shader_code(original)
	var shadow := Ground.shader_code(original,true)
	_check(not plain.is_empty() and plain.contains("render_mode unshaded") and not plain.contains("texture(TEXTURE,"), "same source formula adapted without extra sampler owner")
	_check(shadow.contains("ATTENUATION * 0.25") and not shadow.contains("render_mode unshaded"), "bounded shadow variant")
	_check(Ground.shader_code("drift").is_empty() and Ground.shader_code(plain).is_empty(), "shader drift and repeated ownership rejected")
	var surface := preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var adapted := Ground.ground_code(surface)
	_check(adapted.contains("tile_ground_local.y < 0.0") and adapted.begins_with("shader_type spatial;"), "negative ground only, shader header preserved")
	_check(Ground.ground_code(adapted).is_empty(), "duplicate ground conversion rejected")
	_check(Ground.texture_resolved(Vector2(4,4),.3125) and not Ground.texture_resolved(Vector2(4,4),.3126),"actual pixel footprint includes threshold and rejects stretching")
	for scale: float in [0.0,-1.0,NAN,INF]:
		_check(not Ground.texture_resolved(Vector2.ONE,scale),"invalid output scale rejected")
	_check(not Ground.texture_resolved(Vector2(0,1),1) and not Ground.texture_resolved(Vector2(1,10),.2),"both source axes must resolve")
	var mesh := Ground.plane(Rect2(-5,-7,12,15),Rect2(.1,.2,.3,.4))
	var arrays := mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_VERTEX].size()==4 and arrays[Mesh.ARRAY_INDEX].size()==6, "one tile two triangles")
	for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		_check(point.y==0, "exact original two dimensional ground elevation")
	var ground := Ground.new()
	ground.close()
	ground.close()
	_check(ground._nodes.is_empty() and ground._saved.is_empty() and ground._stream==null,"idempotent rollback")
	_check(load("res://scripts/tests/tokyo_tile_ground_review.gd").can_instantiate(),"actual route review compiles")
	_check(load("res://scripts/tests/export_tokyo_fixed_mesh.gd").can_instantiate(),"fixed native source exporter compiles")
	_check(load("res://scripts/tests/tokyo_ground_color_probe.gd").can_instantiate(),"source color factors and real gray ramp compile")
	var transfer := preload("res://scripts/experiments/tokyo_canvas_color.gd")
	var maximum := 0.0
	var shadow_maximum := 0.0
	var monotonic := true
	var previous := -1.0
	for n in 4097:
		var value := n/4096.0
		var input: float = transfer.input_for(value)
		var ambient: float = transfer.input_for(value,.75)
		var linear := input*(input*(input*.305306011+.682171111)+.012522878)
		var emission := ambient*(ambient*(ambient*.305306011+.682171111)+.012522878)
		maximum = maxf(maximum,absf(maxf(1.055*pow(linear,1.0/2.4)-.055,0.0)-value))
		shadow_maximum = maxf(shadow_maximum,absf(maxf(1.055*pow(emission+.25*linear,1.0/2.4)-.055,0.0)-value))
		monotonic = monotonic and input>=previous and is_finite(input)
		previous = input
	_check(maximum*255<.001 and monotonic,"GL polynomial inverse monotonic including near black")
	_check(shadow_maximum*255<.001,"unoccluded 75/25 linear split has identical target color")
	_check(plain.contains("if(OUTPUT_IS_SRGB)") and not shadow.contains("EMISSION="),"renderer guard and no separately encoded emission")
	_check(not shadow.contains("DIFFUSE_LIGHT += ALBEDO") and shadow.contains("DIFFUSE_LIGHT += vec3(0.75 + ATTENUATION * 0.25)"),"single fixed light applies albedo once and keeps 75 percent occluded baseline")
	var low := preload("res://scripts/experiments/tokyo_low_light_candidate.gd")
	for amount: float in [.1,.25]:
		var low_code: String = low.shader_code(surface,amount)
		_check(low_code.contains("low_light_local=VERTEX") and low_code.contains("else { "+low.LIGHT),"low light changes only bounded region and preserves outside light")
		_check(low_code.contains("EMISSION = vec3(0.0)") and low_code.contains("-6300.0"),"single output preserves low building geometry")
		_check(low.shader_code(low_code,amount).is_empty(),"repeated low light adaptation rejected")
	_check(low.shader_code(surface,.5).is_empty() and low.shader_code("drift",.1).is_empty(),"unreviewed low light strength or source drift rejected")
	var palette := preload("res://scripts/experiments/tokyo_ground_palette_candidate.gd")
	var palette_code: String = palette.shader_code(surface)
	_check(not palette_code.is_empty() and palette_code.contains("else {"+palette.LIGHT),"ground palette preserves outside source light")
	_check(palette_code.contains("ground_palette_base_only && abs(ground_palette_class-9.0)>0.1"),"base only control preserves green road and water original shading")
	_check(palette.shader_code(palette_code).is_empty() and palette.shader_code("drift").is_empty(),"palette source drift and duplicate rejected")
	_check(palette.vectors(palette.COLORS).size()==11 and palette_code.count("distance(COLOR.rgb")==11,"all fixed source categories classified in vertex stage")
	var palette_review := preload("res://scripts/tests/tokyo_ground_palette_review.gd")
	var sample_source := Image.create(8,8,false,Image.FORMAT_RGBA8)
	sample_source.fill(Color8(100,120,140))
	var sample_mask := Image.create(8,8,false,Image.FORMAT_RGBA8)
	sample_mask.fill(Color.WHITE)
	var sample: Dictionary = palette_review.sample_color(sample_source,sample_mask)
	_check(sample.count==4 and sample.rgb==[100,120,140],"interior source median excludes boundaries")
	var flat_sample: Dictionary = palette_review.sample_color(sample_source,sample_mask,2)
	_check(flat_sample.count==4 and flat_sample.rgb==[100,120,140],"flat source retains uniform category interiors")
	sample_source.set_pixel(2,2,Color8(103,120,140))
	_check(not palette_review.source_flat(sample_source,2,2,2),"one RGB channel exceeding flat threshold rejected")
	sample_source.set_pixel(2,2,Color8(102,120,140))
	_check(palette_review.source_flat(sample_source,2,2,2),"flat threshold inclusive in quantized source RGB")
	sample_source.set_pixel(0,2,Color.TRANSPARENT)
	_check(not palette_review.source_flat(sample_source,2,2,2),"transparent neighbor cannot calibrate land")
	var semantic: Array[Color] = palette.semantic_colors(Color8(140,145,139))
	_check(semantic.size()==11 and semantic[9].is_equal_approx(Color8(140,145,139)),"semantic palette anchors actual flat base")
	_check((semantic[7]-semantic[9]).is_equal_approx(palette.COLORS[7]-palette.COLORS[9]),"green versus land RGB differences preserved")
	sample_mask.fill(Color.TRANSPARENT)
	_check(palette_review.sample_color(sample_source,sample_mask).count==0,"empty mask cannot fabricate a palette")
	sample_mask.fill(Color.BLACK)
	_check(palette_review.sample_color(sample_source,sample_mask).count==0,"opaque other category excludes underlying ground")
	var projection := preload("res://scripts/experiments/tokyo_raster_projection.gd")
	var metadata: Dictionary = projection.metadata()
	var projection_error := 0.0
	for y in range(-17000,17001,100):
		projection_error = maxf(projection_error,absf(projection.world_y(projection.raw_y(y,metadata),metadata)-y))
	_check(projection_error<.000001,"Mercator source to OSM latitude roundtrip")
	_check(projection.raw_y(-3500,metadata)+3500>30 and projection.raw_y(-3500,metadata)+3500<32,"north coast affine source drift independently bounded")
	var projected_mesh: ArrayMesh = projection.mesh(Rect2(-100,-16000,200,32000),Rect2(0,0,1,1),metadata)
	var projected_arrays := projected_mesh.surface_get_arrays(0)
	_check(projected_arrays[Mesh.ARRAY_VERTEX].size()==252 and projected_arrays[Mesh.ARRAY_INDEX].size()==750,"strategic source also subdivided with stable UV rows")
	_check(load("res://scripts/tests/tokyo_georeference_review.gd").can_instantiate(),"georeference real route compiles")
	var bbox: Dictionary = metadata.bbox_ll
	var actual_rect := Rect2(Vector2((float(bbox.lon_min)-139.76)*90434.27326522839*.5,-(float(bbox.lat_max)-35.44)*55500),Vector2((float(bbox.lon_max)-float(bbox.lon_min))*90434.27326522839*.5,(float(bbox.lat_max)-float(bbox.lat_min))*55500))
	_check(projection.valid_for(metadata,actual_rect) and not projection.valid_for({},actual_rect) and not projection.valid_for(metadata,Rect2()),"projection requires matching finite metadata and world extent")
	var broken := metadata.duplicate(true)
	broken.bbox_ll.lat_min = NAN
	_check(not projection.valid_for(broken,actual_rect),"nonfinite projected source fails closed")
	var tile := preload("res://scripts/rendering/projected_raster_tile.gd").new()
	tile.texture = ImageTexture.create_from_image(Image.create(16,16,false,Image.FORMAT_RGBA8))
	tile.position = Vector2(-6300,-3700)
	tile.scale = Vector2(125,125)
	tile.configure(metadata)
	_check(tile.projected_rect.position.y<tile.position.y and tile.geometry_bytes<RasterBasemapRenderer.PROJECTED_GEOMETRY_RESERVE,"projected source owns bounded static geometry")
	var clip := Rect2(-6000,-3500,1000,1000)
	var clipped: ArrayMesh = tile.clipped_plane(clip)
	var clipped_arrays := clipped.surface_get_arrays(0)
	var points: PackedVector3Array = clipped_arrays[Mesh.ARRAY_VERTEX]
	var texcoords: PackedVector2Array = clipped_arrays[Mesh.ARRAY_TEX_UV]
	var interpolation_error := 0.0
	var inside := true
	for i in points.size():
		var point := Vector2(points[i].x,points[i].z)
		inside = inside and clip.grow(.001).has_point(point) and points[i].y==0
		for row in tile.world_vertices.size()/2-1:
			var top: Vector2 = tile.world_vertices[row*2]
			var bottom: Vector2 = tile.world_vertices[row*2+3]
			if point.y>=top.y and point.y<=bottom.y:
				var t := (point-top)/(bottom-top)
				var expected: Vector2 = tile.source_uv[row*2]+t*(tile.source_uv[row*2+3]-tile.source_uv[row*2])
				interpolation_error = maxf(interpolation_error,texcoords[i].distance_to(expected))
	_check(inside and points.size()>4 and interpolation_error<.000001,"3D borrowed strips clip the actual 2D source rows and UV")
	_check(tile.maximum_step.x==125 and tile.maximum_step.y>124 and tile.maximum_step.y<126,"clarity checks maximum true source row derivative")
	var stale_source := RasterBasemapRenderer.new()
	stale_source.source_projection = metadata
	var stale_layer := Node2D.new()
	stale_source.add_child(stale_layer)
	stale_source._layers[&"detail"] = stale_layer
	stale_source._sprites[&"detail"] = {"stale":tile}
	stale_source._strategic_sprite = tile
	tile.free()
	_check(stale_source.estimated_texture_bytes()==0 and stale_source.projected_geometry_bytes()==0 and stale_source.presentation_tiles().is_empty(),"freed tile caches are validated before type or field access")
	stale_source._remove_resident("detail:stale")
	stale_source.free()
	var rect := Rect2(0,0,10,10)
	var halves: Array[Rect2] = [Rect2(0,0,5,10),Rect2(5,0,5,10)]
	_check(coverage.covered(rect,halves),"exact adjacent tile coverage")
	halves.reverse()
	_check(coverage.covered(rect,halves),"tile order does not affect coverage")
	_check(not coverage.covered(rect,[Rect2(0,0,4.999,10),Rect2(5,0,5,10)]),"subpixel tile hole fails closed")
	_check(not coverage.covered(rect,[Rect2(0,0,6,10),Rect2(0,0,6,10)]),"overlap area cannot replace missing region")
	_check(coverage.covered(rect,[Rect2(0,0,5,5),Rect2(5,5,5,5),Rect2(0,5,5,5),Rect2(5,0,5,5)]),"four-tile corner and both axes cover exactly")
	_check(not coverage.covered(rect,[Rect2(0,0,10,4),Rect2(0,6,10,4),Rect2(0,4,4,2),Rect2(6,4,4,2)]),"interior uncovered hole cannot retire fixed layer")
	_check(not coverage.covered(rect,[]) and not coverage.covered(Rect2(),halves),"missing or empty coverage rejected")
	_check(not coverage.covered(rect,[Rect2(Vector2(NAN,0),Vector2(10,10))]),"nonfinite coverage rejected")
	_check(adapted.contains("uniform vec4 tile_ground_rects[17]") and adapted.contains("i<tile_ground_count") and not adapted.contains("-6300.0"),"discard only actual borrowed tile coverage, never whole production window")
	_check(load("res://scripts/rendering/tokyo_tile_ground_overlay.gd").can_instantiate(),"continuous owner compiles")
	_check(load("res://scripts/tests/tokyo_tile_stream_review.gd").can_instantiate(),"continuous route and error diagnostics compile")
	var shader_holder := Ground.new()
	var shader_peer := Ground.new()
	shader_peer.shader_cache = shader_holder.shader_cache
	var cached := shader_holder.cached_shader(plain)
	shader_holder.close()
	_check(shader_peer.cached_shader(plain)==cached and shader_peer.shader_cache.size()==1,"same program reused across released texture leases")
	_check(shader_peer.cached_shader(shadow)!=cached and shader_peer.shader_cache.size()==2,"distinct shadow program cannot alias unshaded program")
	cached = null
	shader_holder.shader_cache.clear()
	_check(coverage.flat_covered(AABB(Vector3(0,-.35,0),Vector3(10,.93,10)),halves),"flat map layers can transfer to ready same-source tiles")
	_check(not coverage.flat_covered(AABB(Vector3(0,0,0),Vector3(10,2,10)),halves),"bridge or building height cannot retire as flat ground")
	for original_visible: bool in [false,true]:
		var node := MeshInstance3D.new()
		var original_material := ShaderMaterial.new()
		var replacement := Ground.new()
		replacement._saved.append({"node":weakref(node),"material":original_material,"visible":original_visible})
		node.visible = not original_visible
		replacement.close()
		replacement.close()
		_check(node.visible == original_visible and node.material_override==original_material,"fixed visibility and material restored idempotently")
		node.free()
	print("[R71 ground test] pass=",_pass," fail=",_fail)


static func lifecycle(parent: Node) -> int:
	var atlas_failures := await preload("res://scripts/tests/test_tokyo_fixed_atlas_layer.gd").lifecycle(parent)
	var owner := Node3D.new()
	parent.add_child(owner)
	var layer := Ground.new()
	var node := MeshInstance3D.new()
	owner.add_child(node)
	layer._nodes.append(node)
	layer._saved.append({"node": weakref(node), "material": ShaderMaterial.new()})
	var stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	stream.configure(owner,{})
	parent.add_child(stream)
	var ref: WeakRef = weakref(stream)
	var reserved := stream.reserve_auxiliary(layer.get_instance_id(),4096)
	layer._stream = weakref(stream)
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var held: bool = is_instance_valid(stream) and stream.summary().closed and stream.summary().auxiliary_bytes == 4096
	layer.close()
	layer.close()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var ok: bool = reserved and held and ref.get_ref() == null and layer._nodes.is_empty() and layer._saved.is_empty() and layer._stream == null
	var source := RasterBasemapRenderer.new()
	parent.add_child(source)
	source.set_process(false)
	var sprite := Sprite2D.new()
	source.add_child(sprite)
	var texture: Texture2D = ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGBA8))
	var texture_ref: WeakRef = weakref(texture)
	sprite.texture = texture
	source._sprites[&"detail"] = {"test":sprite}
	source._lru.append("detail:test")
	var overlay := preload("res://scripts/rendering/tokyo_tile_ground_overlay.gd").new()
	var borrowed := Ground.new()
	var borrowed_node := MeshInstance3D.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type spatial; uniform sampler2D borrowed_texture;"
	material.set_shader_parameter("borrowed_texture",texture)
	borrowed_node.material_override = material
	texture = null
	material = null
	parent.add_child(borrowed_node)
	borrowed._nodes.append(borrowed_node)
	overlay._tile_ground = borrowed
	source.presentation_changing.connect(overlay._release_tile_ground)
	var observed := [false]
	source.presentation_changing.connect(func() -> void:
		observed[0] = source._sprites[&"detail"].has("test") and not sprite.is_queued_for_deletion() and borrowed._nodes.is_empty() and overlay._tile_ground == null
	,CONNECT_ONE_SHOT)
	source._remove_resident("detail:test")
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	ok = ok and observed[0] and not is_instance_valid(sprite) and overlay._tile_releases==1 and texture_ref.get_ref()==null
	# 再次退出源时允许重复通知；overlay不持有强source引用。
	source.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	borrowed.close()
	overlay.free()
	var projected_source := RasterBasemapRenderer.new()
	projected_source.source_projection = preload("res://scripts/experiments/tokyo_raster_projection.gd").metadata()
	parent.add_child(projected_source)
	projected_source.set_process(false)
	var projected_tile := preload("res://scripts/rendering/projected_raster_tile.gd").new()
	projected_tile.texture = ImageTexture.create_from_image(Image.create(16,16,false,Image.FORMAT_RGBA8))
	projected_tile.position = Vector2(-6300,-3700)
	projected_tile.scale = Vector2(125,125)
	projected_tile.configure(projected_source.source_projection)
	projected_source.add_child(projected_tile)
	projected_source._sprites[&"detail"] = {"test":projected_tile}
	projected_source._lru.append("detail:test")
	var projected_texture: WeakRef = weakref(projected_tile.texture)
	var projected_mesh: WeakRef = weakref(projected_tile.mesh)
	var notified := [false]
	projected_source.presentation_changing.connect(func() -> void:
		notified[0] = not projected_tile.is_queued_for_deletion() and projected_source._sprites[&"detail"].has("test")
	,CONNECT_ONE_SHOT)
	ok = ok and projected_source.estimated_texture_bytes()==16*16*4 and projected_source.projected_geometry_bytes()>0
	projected_source._remove_resident("detail:test")
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	ok = ok and notified[0] and projected_texture.get_ref()==null and projected_mesh.get_ref()==null and projected_source.projected_geometry_bytes()==0
	projected_source.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	print("[R71 ground lifecycle] owner release=",ok)
	return atlas_failures + (0 if ok else 1)


func _test_submission_peak() -> void:
	var overlay := preload("res://scripts/rendering/tokyo_tile_ground_overlay.gd").new()
	overlay._active=true
	overlay._screen=Sprite2D.new()
	overlay.add_child(overlay._screen)
	var nodes: Array[MeshInstance3D] = []
	for kind in 3:
		var node := MeshInstance3D.new()
		overlay.add_child(node)
		nodes.append(node)
	# 精确计数边界fixture；实际几何和draw对照另走Visual探针。
	overlay._batches["test"]={"nodes":nodes,"layer_triangles":PackedInt32Array([100000,10000,130001]),"path":"fixture"}
	nodes[2].hide()
	var ground := Ground.new()
	ground.stats={"extra_faces":2}
	ground._saved.append({"node":weakref(nodes[2]),"material":null,"visible":true})
	overlay._tile_ground=ground
	overlay.peak_triangles=300000
	overlay._geometry_transaction=true
	overlay._record_submission_peak()
	_check(overlay._tile_peak_faces==0,"no submission sample inside incomplete geometry transaction")
	overlay._geometry_transaction=false
	overlay._record_submission_peak()
	_check(overlay._tile_peak_faces==110002 and overlay.peak_triangles==300000,"final tiles count separately without clearing preparation peak")
	overlay._release_tile_ground()
	_check(nodes[2].visible and overlay._tile_peak_faces==110002 and RenderingServer.frame_pre_draw.is_connected(overlay._record_submission_peak),"external tile retirement schedules final draw count without recording an intermediate state")
	overlay._queue_submission_peak()
	overlay._record_submission_peak()
	_check(overlay._tile_peak_faces==240001 and overlay._submission_samples==2 and not RenderingServer.frame_pre_draw.is_connected(overlay._record_submission_peak),"queued final native over-budget count completes once and disconnects")
	_check(overlay._submission_peak_snapshot.faces==240001 and overlay._submission_peak_snapshot.auxiliary_faces==0,"peak snapshot and count belong to same final state")
	nodes[2].hide()
	overlay._record_submission_peak()
	_check(overlay._tile_peak_faces==240001,"later low count cannot erase previous submitted over-budget peak")
	var next := Ground.new()
	next.stats={"extra_faces":2}
	next._saved.append({"node":weakref(nodes[2]),"material":null,"visible":true})
	overlay._tile_ground=next
	overlay._geometry_transaction=true
	var samples: int=overlay._submission_samples
	overlay._release_tile_ground()
	_check(overlay._submission_dirty and overlay._submission_samples==samples,"internal release defers count until transaction finishes")
	nodes[2].hide()
	overlay._geometry_transaction=false
	overlay._record_submission_peak()
	_check(not overlay._submission_dirty and overlay._submission_samples==samples+1,"deferred dirty state counted once at finalization")
	overlay._active=false
	nodes[2].show()
	overlay._record_submission_peak()
	_check(overlay._submission_samples==samples+1,"hidden deactivation cannot add a temporary submitted peak")
	overlay._active=true
	overlay._queue_submission_peak()
	var callback: Callable=overlay._record_submission_peak
	overlay.free()
	_check(not RenderingServer.frame_pre_draw.is_connected(callback),"owner free disconnects pending draw callback")


func _test_fixed_expansion() -> void:
	var codec := preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd")
	var review := preload("res://scripts/tests/tokyo_fixed_atlas_review.gd")
	var source := {"parent":12,"triangles":11867,"source":"fixture.res","source_sha256":"a".repeat(64)}
	var data := {"schema":1,"parent":12,"original_fixed_faces":11867,"source":source,"catalog_sha256":"f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85","rows":[]}
	for step in [2,1]:
		data.rows.append({"world_step":step,"native_bounds":[-5660.0,-2700.0,-4700.0,-1700.0],"max_scale":0.3888,"rectangular_coverage":true,"premultiplied_alpha":true,
			"bounds":[-5664.0,-2704.0,-4696.0,-1696.0] if step==2 else [-5662.0,-2702.0,-4698.0,-1698.0],"height_range":[-0.35,0.58],
			"width":484 if step==2 else 964,"height":504 if step==2 else 1004,"file":"fixed_%d.png"%step,"sha256":"b".repeat(64)})
	_check(codec.manifest_valid(data),"offline expansion current source contract")
	var residential: Dictionary=data.duplicate(true)
	residential.catalog_sha256=codec.RESIDENTIAL_CATALOG
	_check(not codec.manifest_valid(residential),"new catalog rejects old railway face count")
	residential.original_fixed_faces=9705
	residential.source.triangles=9705
	_check(codec.manifest_valid(residential),"new parent12 offline contract accepts current face count")
	_check(codec.region_contract(11,codec.RESIDENTIAL_CATALOG).faces==28145,"new parent11 offline face count")
	_check(codec.region_contract(0,codec.RESIDENTIAL_CATALOG).is_empty(),"new catalog cannot inherit unverified other regions")
	_check(preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").region_contract(12).faces==11867,"offline update does not broaden runtime contract")
	_check(codec.manifest_valid(JSON.parse_string(JSON.stringify(data))),"offline expansion JSON numeric contract")
	_check(not codec.region_contract(12.0).is_empty(),"offline JSON integral float parent accepted")
	for parent: Variant in [0,1,3,11,12,13]:
		_check(not codec.region_contract(parent).is_empty(),"offline audited rectangular region")
	for parent: Variant in [null,true,"12",12.5,8,9,10,15]:
		_check(codec.region_contract(parent).is_empty(),"offline invalid or nonrectangular region refused")
	for mutation: Dictionary in [{"parent":8},{"catalog_sha256":"0".repeat(64)},{"original_fixed_faces":11866},{"source":{}},{"rows":[]}]:
		var broken: Dictionary=data.duplicate(true)
		broken.merge(mutation,true)
		_check(not codec.manifest_valid(broken),"offline identity and completeness drift refused")
	for mutation: Dictionary in [{"native_bounds":[-5660.0,-2700.0,-4699.0,-1700.0]},{"rectangular_coverage":false},{"world_step":3},{"file":"../escape.png"},{"height_range":[NAN,0.58]},{"width":485},{"bounds":[-5664.0,-2704.0,-4695.0,-1696.0]}]:
		var broken: Dictionary=data.duplicate(true)
		broken.rows[0].merge(mutation,true)
		_check(not codec.manifest_valid(broken),"offline bounds sampling or path drift refused")
	_check(review.complete_native(.3888,11867,11867,true),"static whole native fixed layer eligible")
	_check(not review.complete_native(.3888,11866,11867,true) and not review.complete_native(.3888,11868,11867,true),"static partial or duplicate fixed layer cannot hide source")
	_check(not review.complete_native(.3888,11867,11867,false) and not review.complete_native(.3889,11867,11867,true),"static other configuration or near scale keeps source")
	_check(not review.complete_native(NAN,11867,11867,true) and not review.complete_native(.1,0,0,true),"static invalid inputs keep source")


func _test_flat_bc3() -> void:
	var codec := preload("res://scripts/tests/build_tokyo_fixed_atlas_bc3.gd")
	_check(codec.flat_rgb_block(PackedByteArray()).is_empty() and codec.patch_flat_blocks(null,null).is_empty(),"flat BC3 rejects incomplete inputs")
	var original := Image.create(8,8,false,Image.FORMAT_RGBA8)
	original.fill(Color8(126,139,136,255))
	original.set_pixel(4,0,Color.RED)
	original.generate_mipmaps()
	var packed: Image=original.duplicate()
	_check(packed.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA)==OK,"flat BC3 fixture compresses")
	var before := packed.get_data()
	var result: Dictionary=codec.patch_flat_blocks(original,packed)
	_check(not result.is_empty() and result.patched_blocks==3 and result.bytes.size()==before.size(),"flat BC3 touches only three full opaque constant blocks")
	if result.is_empty():
		return
	_check(result.bytes.slice(16,32)==before.slice(16,32) and result.bytes.slice(64)==before.slice(64),"flat BC3 mixed block and smaller mip levels byte-identical")
	var alpha_same := true
	for offset in range(0,before.size(),16):
		alpha_same=alpha_same and before.slice(offset,offset+8)==result.bytes.slice(offset,offset+8)
	_check(alpha_same,"flat BC3 alpha bytes untouched across every mip")
	var restored := Image.create_from_data(8,8,true,Image.FORMAT_DXT5,result.bytes)
	_check(restored.decompress()==OK,"flat BC3 standard decoder accepts patched stream")
	restored.convert(Image.FORMAT_RGBA8)
	var expected := original.get_data()
	var decoded := restored.get_data()
	var maximum := 0
	for y in 4:
		for x in 4:
			for c in 4:
				var offset := (y*8+x)*4+c
				maximum=maxi(maximum,absi(decoded[offset]-expected[offset]))
	_check(maximum<=1,"flat BC3 opaque color preserves source within one decoded level: "+str(maximum))
	var transparent := Image.create(4,4,false,Image.FORMAT_RGBA8)
	transparent.fill(Color8(126,139,136,128))
	var compressed: Image=transparent.duplicate()
	compressed.compress_from_channels(Image.COMPRESS_S3TC,Image.USED_CHANNELS_RGBA)
	var untouched: Dictionary=codec.patch_flat_blocks(transparent,compressed)
	_check(untouched.patched_blocks==0 and untouched.bytes==compressed.get_data(),"flat BC3 never changes translucent blocks")
	_check(codec.patch_flat_blocks(original,compressed).is_empty(),"flat BC3 rejects dimension or mip mismatch")


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R71 "+label)
