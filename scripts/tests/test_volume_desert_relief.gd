extends RefCounted
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
const Ground := preload("res://scripts/experiments/volume_satellite_ground.gd")
const Surface := preload("res://scripts/experiments/volume_terrain_surface.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	_test_surface_contract()
	var relief := Relief.new()
	_test_refinement(relief)
	_check(relief.heights.size() == 257 * 257 and relief.data.provenance.tile_sha256.size() > 0,
		"georeferenced DEM grid has source hashes")
	var valid := true
	var peak := 0.0
	for height in relief.heights:
		valid = valid and is_finite(height) and height >= 0 and height <= 500
		peak = maxf(peak, height)
	_check(valid and peak > 400, "bounded vertically exaggerated presentation relief")
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var flat := true
	for line: Dictionary in doc.roads + doc.railways:
		var points: Array = line.points
		for i in range(points.size() - 1):
			var a := Vector2(points[i][0], points[i][1])
			var b := Vector2(points[i + 1][0], points[i + 1][1])
			for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
				# 界外列车延长线不属于底图内容。
				var p := a.lerp(b, fraction)
				if relief.rect.has_point(p):
					if relief.height_at(p) >= 0.01:
						print("[Volume relief flat diagnostic] point=", p, " height=", relief.height_at(p))
					flat = flat and relief.height_at(p) < 0.01
	_check(flat, "source road and railway positions remain flat")
	var closed := true
	for contour: Array in relief.data.water_contours:
		closed = closed and contour.size() >= 4 and contour[0] == contour[-1]
	_check(closed and relief.data.water_contours.size() > 100, "source water outlines closed with hole boundaries preserved")
	var mesh := relief.plane_mesh(relief.rect, Rect2(0, 0, 1, 1), -0.8)
	_check(mesh.surface_get_array_index_len(0) / 3 <= 34000 and mesh.get_aabb().size.y > 100,
		"strategic grid has real geometry within fixed budget")
	var a: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	valid = true
	for normal in normals:
		valid = valid and normal.is_finite() and absf(normal.length() - 1) < 0.001 and normal.y > 0
	_check(valid, "terrain normals finite normalized and upward")
	var split := relief.rect.position.x + relief.rect.size.x * 0.37
	var left := relief.plane_mesh(Rect2(relief.rect.position, Vector2(split - relief.rect.position.x, relief.rect.size.y)), Rect2(0, 0, 0.37, 1), -0.6)
	var right := relief.plane_mesh(Rect2(Vector2(split, relief.rect.position.y), Vector2(relief.rect.end.x - split, relief.rect.size.y)), Rect2(0.37, 0, 0.63, 1), -0.6)
	var edge := {}
	for vertex: Vector3 in left.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.x - split) < 0.01:
			edge[vertex.z] = vertex.y
	valid = true
	var seam_error := 0.0
	for vertex: Vector3 in right.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.x - split) < 0.01:
			# 浮点数在量化桶边界两侧仍可能相距不到 0.002；比较实际距离而非哈希相等。
			var nearest := INF
			for z: float in edge:
				nearest = minf(nearest, Vector2(z, edge[z]).distance_to(Vector2(vertex.z, vertex.y)))
			seam_error = maxf(seam_error, nearest)
			valid = valid and nearest < 0.005
	print("[Volume seam error] max_yz=", seam_error)
	_check(valid and edge.size() > 100, "adjacent tile boundary positions agree without cracks")
	var errors := _surface_error(relief.surface, left, -0.6)
	_check(errors[errors.max_axis_index()] < 0.01, "clipped mesh face interiors preserve canonical height normal and cover")
	var terrain_budget := _test_tile_budget(relief)
	valid = true
	for plant: Array in relief.data.vegetation:
		valid = valid and plant.size() == 5
		for value: float in plant:
			valid = valid and is_finite(value)
		valid = valid and float(plant[3]) >= 0.7 and float(plant[3]) <= 1.4 and absf(float(plant[4])) <= PI + 0.00001
	_check(valid, "bounded deterministic vegetation scale and downhill orientation")
	var details := relief.make_details()
	_test_shoreline(relief, details)
	_check(details.get_child_count() <= 18 and details.get_meta("vegetation_count") == 1200,
		"vegetation capped and region-batched without per-plant nodes")
	valid = true
	for child: Node3D in details.get_children():
		valid = valid and not child.is_processing() and not child.is_physics_processing()
	_check(valid, "all map detail nodes static")
	var root_error := 0.0
	var roots := 0
	var cover_geometry := true
	var max_cover_height := 0.0
	var max_cover_radius := 0.0
	var min_face_clearance := INF
	for child: MeshInstance3D in details.get_children():
		if not String(child.name).begins_with("Scrub_"):
			continue
		var detail_arrays := child.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = detail_arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = detail_arrays[Mesh.ARRAY_COLOR]
		var detail_normals: PackedVector3Array = detail_arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, int(child.get_meta("scrub_vertices")), 3):
			# Geometry.triangle 输出顺序 a/b/crown，前两项是真实底部顶点。
			var crown := points[i + 2]
			var crown_at := Vector2(crown.x, crown.z)
			var clearance := crown.y - relief.height_at(crown_at)
			max_cover_height = maxf(max_cover_height, clearance)
			cover_geometry = cover_geometry and clearance >= 0.19 and clearance <= 0.71
			var face_normal := (points[i + 1] - points[i]).cross(crown - points[i])
			# Geometry.triangle 将向外法线与 Godot 顺时针正面分别写入，叉积符号相反。
			cover_geometry = cover_geometry and face_normal.is_finite() and face_normal.y < -0.01
			cover_geometry = cover_geometry and detail_normals[i].is_finite() and detail_normals[i].y > 0.01
			var centroid := (points[i] + points[i + 1] + crown) / 3.0
			min_face_clearance = minf(min_face_clearance, centroid.y - relief.height_at(Vector2(centroid.x, centroid.z)))
			for j in 3:
				cover_geometry = cover_geometry and colors[i + j].r >= colors[i + j].g and colors[i + j].g > colors[i + j].b
			for offset in 2:
				var p := points[i + offset]
				root_error = maxf(root_error, absf(p.y - relief.height_at(Vector2(p.x, p.z))))
				max_cover_radius = maxf(max_cover_radius, Vector2(p.x, p.z).distance_to(crown_at))
				roots += 1
	print("[Volume scrub geometry] roots=", roots, " root_error=", root_error,
		" max_local_height=", max_cover_height, " max_radius=", max_cover_radius,
		" min_face_clearance=", min_face_clearance)
	_check(roots == 50400 and root_error < 0.01,
		"all 50400 ground-cover bases conform with 25200 triangles reserved for tiny ground-cover silhouettes")
	_check(cover_geometry and max_cover_radius < 2.17 and min_face_clearance >= -0.01,
		"low tawny cover remains terrain-relative, outward and non-buried instead of oversized green trees")
	_test_outcrops(relief, details)
	var detail_triangles := 0
	var water_triangles := 0
	for child: MeshInstance3D in details.get_children():
		if String(child.name).begins_with("Scrub_"):
			detail_triangles += child.mesh.surface_get_array_len(0) / 3
		else:
			water_triangles += child.mesh.surface_get_array_len(0) / 3
	_check(terrain_budget + detail_triangles <= 100000,
		"additional conservative bound: 17 terrain planes plus near rock and scrub stay below 100000 triangles")
	_check(water_triangles <= 10285, "retained water plus continuous terrain-fit rivers stay within the original 10285 triangle budget")
	print("[Volume combined geometry budget] terrain_rock_scrub=", terrain_budget + detail_triangles,
		" water=", water_triangles, " all=", terrain_budget + detail_triangles + water_triangles)
	_test_cover_lod(relief, details)
	details.free()
	var ground := Ground.new()
	ground.enable_relief()
	ground.sync(0.11)
	_check(ground.get_child_count() == 0 and ground.relief == null, "missing owner removes terrain accessories too")
	ground.free()
	print("[Volume relief] pass=%d fail=%d" % [_pass, _fail])
	return _fail == 0


func _test_shoreline(relief: RefCounted, details: Node3D) -> void:
	var line: MeshInstance3D = details.get_node("Source_Water_Contours")
	var arrays := line.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var cursor := 0
	var joints := 0
	var closed := true
	var bounded := true
	var fixed_height := true
	var prior_float_height := 0.0
	for contour_index: int in relief.hydrography.retained_contours:
		var contour: Array = relief.data.water_contours[contour_index]
		var source := Relief.Geometry.points_from(contour)
		var edges := Relief.Geometry.stroke_edges(source, 4.8, true)
		var count := edges[0].size() - 1
		closed = closed and count == contour.size() - 1
		for i in count:
			var here := cursor + i * 6
			var next := cursor + ((i + 1) % count) * 6
			closed = closed and points[here+1] == points[next] and points[here+2] == points[next+5]
			closed = closed and uvs[here+1] == uvs[next] and uvs[here+2] == uvs[next+5]
			for side in 2:
				bounded = bounded and edges[side][i].distance_to(source[i]) <= 9.601
			for k in 6:
				fixed_height = fixed_height and is_equal_approx(points[here+k].y, 0.8)
				fixed_height = fixed_height and uvs[here+k].x == 0.0
				prior_float_height = maxf(prior_float_height, relief.height_at(Vector2(points[here+k].x, points[here+k].z)))
			joints += 1
		cursor += count * 6
	_check(closed and joints == 1403 and cursor < points.size() and uvs.size() == points.size(),
		"all 217 retained shoreline loops share exact Float32 endpoints and UVs at all 1403 joints")
	_check(bounded and fixed_height and prior_float_height > 100,
		"shore joins retain width/miter budget and fixed water-relative height instead of floating on dry slopes")
	var water: MeshInstance3D = details.get_node("Source_Water_EvenOdd_Fill")
	var water_points: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var water_flat := true
	for point: Vector3 in water_points:
		water_flat = water_flat and is_equal_approx(point.y, 0.6)
	_check(water_flat, "source even-odd water stays at its original height rather than climbing terrain")
	print("[Volume shoreline] joints=", joints, " max_prior_float_height=", prior_float_height)
	_test_watercourses(relief, details, points.slice(cursor), uvs.slice(cursor))


func _test_watercourses(relief: RefCounted, details: Node3D, points: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var hydro: Dictionary = relief.hydrography
	var water_material := details.get_node("Source_Water_Contours").material_override as ShaderMaterial
	var coverage_override: Variant = water_material.get_shader_parameter("watercourse_coverage_enabled")
	var coverage_default: Variant = RenderingServer.shader_get_parameter_default(water_material.shader.get_rid(), "watercourse_coverage_enabled")
	print("[Water coverage contract] display=", DisplayServer.get_name(), " renderer_default=", coverage_default,
		" material_override=", coverage_override)
	# 无头Dummy后端不编译shader，默认值的真实GL验证在正常菜单Visual；这里必须仍验证打包的源码和覆盖值。
	_check(water_material.shader.code.contains("uniform bool watercourse_coverage_enabled = true;")
		and (coverage_override == null or coverage_override == true)
		and (DisplayServer.get_name() == "headless" or coverage_default == true),
		"actual archived shader source opts into narrow-line coverage; renderer defaults additionally checked on GL")
	var partition := {}
	var disjoint := true
	for index: int in hydro.removed_contours + hydro.retained_contours:
		disjoint = disjoint and index >= 0 and index < 601 and not partition.has(index)
		partition[index] = true
	_check(disjoint and partition.size() == 601 and hydro.removed_contours.size() == 384
		and hydro.retained_contours.size() == 217 and hydro.rivers.size() == 7
		and hydro.source_relief_sha256 == FileAccess.get_sha256(Relief.DATA_PATH),
		"hydrography partitions the exact source contours without changing or losing unmatched water")
	var regenerated: Dictionary = Relief.Watercourses.build(relief.surface, hydro)
	var line_arrays: Array = details.get_node("Source_Water_Contours").mesh.surface_get_arrays(0)
	var across: PackedVector2Array = line_arrays[Mesh.ARRAY_TEX_UV2]
	var first: int = line_arrays[Mesh.ARRAY_VERTEX].size() - points.size()
	var across_ok: bool = across.size() == line_arrays[Mesh.ARRAY_VERTEX].size()
	for i in across.size():
		across_ok = across_ok and across[i].is_finite() and (across[i] == Vector2.ZERO if i < first else across[i].length() > 0.01)
	_check(across_ok and across.slice(first).to_byte_array() == regenerated.across.to_byte_array()
		and water_material.get_shader_parameter("pixel_width_enabled") == false,
		"source archive preserves exact river cross-vectors and zero shore vectors while disabling screen expansion")
	_check(points.to_byte_array() == regenerated.vertices.to_byte_array()
		and uvs.to_byte_array() == regenerated.uvs.to_byte_array()
		and details.get_meta("watercourse_count") == 7 and details.get_meta("retained_shorelines") == 217
		and regenerated.segments.size() == 700,
		"actual packed archive includes all seven source rivers and 700 clipped segments, not a diagnostic-only mesh")
	var stats := _watercourse_mesh_stats(relief.surface, points, uvs)
	_check(stats.valid and stats.samples > 1000 and stats.max_error < 0.003,
		"all river vertices and face interiors stay at canonical terrain plus 0.12 with finite bounded UVs")
	var coverage := _watercourse_coverage(points, regenerated.segments)
	_check(coverage == 700 * 9, "all nine centerline samples of every river segment are covered after terrain clipping")
	# 两端低、中间高的独立反例：只采端点的长线会穿过山脊。
	var heights := PackedFloat32Array()
	var cover := PackedFloat32Array()
	for z in 5:
		for x in 5:
			heights.append(20.0 if x == 2 else 0.0)
			cover.append(0.0)
	var ridge := Surface.new(Rect2(0, 0, 20, 20), 5, heights, cover)
	var fixture: Dictionary = Relief.Watercourses.build(ridge,
		{"rivers": [{"way_id": 1, "paths": [[[1, 7], [19, 7]]]}]})
	var fixture_stats := _watercourse_mesh_stats(ridge, fixture.vertices, fixture.uvs)
	_check(fixture_stats.valid and fixture_stats.max_error < 0.003
		and _watercourse_coverage(fixture.vertices, fixture.segments) == 9
		and ridge.height_at(Vector2(10, 7)) - ridge.height_at(Vector2(1, 7)) > 15,
		"independent ridge fixture proves face clipping prevents long endpoint-only ribbons from cutting through terrain")
	print("[Volume watercourse] segments=", regenerated.segments.size(), " triangles=", points.size()/3,
		" sampled=", stats.samples, " max_error=", stats.max_error, " centerline_coverage=", coverage)


func _watercourse_mesh_stats(surface: RefCounted, points: PackedVector3Array, uvs: PackedVector2Array) -> Dictionary:
	var result := {"valid": points.size() > 0 and points.size()%3 == 0 and points.size() == uvs.size(),
		"samples": 0, "max_error": 0.0}
	for i in range(0, points.size(), 3):
		for k in 3:
			result.valid = result.valid and points[i+k].is_finite() and uvs[i+k].is_finite()
			result.valid = result.valid and uvs[i+k].x == 1.0 and uvs[i+k].y >= 0 and uvs[i+k].y <= 1
		for p: Vector3 in [points[i], points[i+1], points[i+2], (points[i]+points[i+1]+points[i+2])/3,
			points[i].lerp(points[i+1], 0.5), points[i+1].lerp(points[i+2], 0.5), points[i+2].lerp(points[i], 0.5)]:
			result.max_error = maxf(result.max_error,
				absf(p.y - surface.height_at(Vector2(p.x, p.z)) - Relief.Watercourses.LIFT))
			result.samples += 1
	return result


func _watercourse_coverage(points: PackedVector3Array, segments: Array) -> int:
	var covered := 0
	for segment: Dictionary in segments:
		for sample in 9:
			var p: Vector2 = segment.a.lerp(segment.b, float(sample) / 8.0)
			for i in range(segment.start, segment.start + segment.count, 3):
				var triangle := PackedVector2Array([Vector2(points[i].x, points[i].z),
					Vector2(points[i+1].x, points[i+1].z), Vector2(points[i+2].x, points[i+2].z)])
				if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])) < 0.0001:
					continue
				var weights := Surface.triangle_weights(p, triangle)
				if minf(weights.x, minf(weights.y, weights.z)) >= -0.005:
					covered += 1
					break
	return covered


func _test_cover_lod(relief: RefCounted, details: Node3D) -> void:
	var tufts := 0
	var valid := true
	var same_rocks := true
	var clearance := INF
	var max_error := 0.0
	for part: MeshInstance3D in details.get_children():
		if not part.has_meta("cover_far_mesh"):
			continue
		var near_arrays := part.mesh.surface_get_arrays(0)
		var far_mesh: ArrayMesh = part.get_meta("cover_far_mesh")
		var far_arrays := far_mesh.surface_get_arrays(0)
		var near_points: PackedVector3Array = near_arrays[Mesh.ARRAY_VERTEX]
		var far_points: PackedVector3Array = far_arrays[Mesh.ARRAY_VERTEX]
		var near_count := int(part.get_meta("scrub_vertices"))
		var far_count := near_count / 3
		valid = valid and far_points.size() == near_points.size() - near_count + far_count
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
			same_rocks = same_rocks and near_arrays[channel].slice(near_count).to_byte_array() == far_arrays[channel].slice(far_count).to_byte_array()
		for i in range(0, far_count, 3):
			var a := far_points[i]
			var b := far_points[i + 1]
			var c := far_points[i + 2]
			var normal := (b - a).cross(c - a)
			valid = valid and normal.y < -0.01
			for j in 3:
				var base: Vector3 = near_points[i * 3 + [0, 1, 4][j]]
				valid = valid and base.x == far_points[i + j].x and base.z == far_points[i + j].z
				max_error = maxf(max_error, absf(far_points[i + j].y - base.y))
			# 原冠顶投到候选平面；旧三面与新一面差值极值在底顶点/冠顶取得。
			var crown := near_points[i * 3 + 2]
			var plane_y := a.y - (normal.x * (crown.x - a.x) + normal.z * (crown.z - a.z)) / normal.y
			max_error = maxf(max_error, absf(crown.y - plane_y))
			for u in 9:
				for v in range(9 - u):
					var p := a + (b - a) * (float(u) / 8.0) + (c - a) * (float(v) / 8.0)
					clearance = minf(clearance, p.y - relief.height_at(Vector2(p.x, p.z)))
			tufts += 1
	_check(valid and tufts == 8400 and max_error <= Relief.COVER_LOD_ERROR,
		"packed far cover keeps every tuft footprint and bounded half-world-pixel geometric error")
	_check(same_rocks, "near/far rock positions normals and material weights are byte-identical")
	_check(clearance > 0.07, "378000 packed-mesh cover samples stay above canonical terrain")
	print("[Volume cover LOD] tufts=", tufts, " saved_triangles=", tufts * 2,
		" max_error=", max_error, " sampled_clearance=", clearance)


func _test_outcrops(relief: RefCounted, details: Node3D) -> void:
	var rocks: Array = relief.data.outcrops
	_check(rocks.size() > 100 and rocks.size() <= 360 and details.get_meta("outcrop_count") == rocks.size(),
		"DEM-constrained outcrops attached within fixed count")
	var valid := true
	var clearance := true
	var terrain_fit := true
	var min_rock_clearance := INF
	var max_rock_height := 0.0
	var profiles := {}
	var profile_valid := true
	var material_mask_valid := true
	var material_mask_error := 0.0
	for i in rocks.size():
		var valid_before := valid
		var fit_before := terrain_fit
		var rock: Array = rocks[i]
		var center := Vector2(rock[0], rock[1])
		valid = valid and rock.size() == 6 and rock[3] >= 80 and rock[3] <= 170 and rock[5] >= 30 and rock[5] <= 90
		for value: float in rock:
			valid = valid and is_finite(value)
		for plant: Array in relief.data.vegetation:
			clearance = clearance and center.distance_to(Vector2(plant[0], plant[1])) >= float(rock[3]) * 1.15 + 100 - 0.02
		for j in i:
			var other: Array = rocks[j]
			clearance = clearance and center.distance_to(Vector2(other[0], other[1])) >= (float(rock[3]) + float(other[3])) * 1.15 + 20 - 0.02
		var builder := Relief.Geometry.new()
		relief._add_outcrop(builder, rock)
		var mesh: ArrayMesh = builder.mesh()
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var rock_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for j in points.size():
			var at := Vector2(points[j].x, points[j].z)
			var expected: float = 1.0 - 0.70 * smoothstep(0.0, float(rock[5]) * 0.35, points[j].y - relief.height_at(at))
			material_mask_error = maxf(material_mask_error, absf(rock_colors[j].a - expected))
			# ArrayMesh COLOR 打包后按8位通道比较，不把浮点源精度当成存储精度。
			material_mask_valid = material_mask_valid and absf(rock_colors[j].a - expected) <= 1.0 / 255.0 + 0.00001
		valid = valid and points.size() >= 72 and points.size() % 3 == 0
		var bases := {}
		for point: Vector3 in points:
			var p := Vector2(point.x, point.z)
			var rise: float = point.y - relief.height_at(p)
			var local := (p - center).rotated(-float(rock[2])) / Vector2(rock[3], rock[4])
			terrain_fit = terrain_fit and local.length_squared() <= 1.0001 and rise >= -0.01 and rise <= float(rock[5]) + 0.01
			max_rock_height = maxf(max_rock_height, rise)
			if absf(rise) < 0.01:
				bases[p] = true
		terrain_fit = terrain_fit and bases.size() >= 8
		var repeat_builder := Relief.Geometry.new()
		relief._add_outcrop(repeat_builder, rock)
		valid = valid and repeat_builder.mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == points
		var projected_area := 0.0
		for j in range(0, points.size(), 3):
			var mid := (points[j] + points[j+1] + points[j+2]) / 3.0
			valid = valid and mid.is_finite() and normals[j].is_finite() and normals[j].length() > 0.99
			var face := (points[j+1] - points[j]).cross(points[j+2] - points[j])
			# 地表裁边可生成合法小面；检查投影面积及总覆盖守恒，不要求原始大面的尺寸。
			valid = valid and face.y < -0.0005
			projected_area += absf(face.y) * 0.5
			valid = valid and normals[j].y > 0.01
			for sample: Vector3 in [mid, mid.lerp(points[j], 0.6), mid.lerp(points[j+1], 0.6), mid.lerp(points[j+2], 0.6)]:
				min_rock_clearance = minf(min_rock_clearance, sample.y - relief.height_at(Vector2(sample.x, sample.z)))
		var profile: PackedVector3Array = Relief.outcrop_profile(rock)
		profiles[profile.to_byte_array().hex_encode()] = true
		profile_valid = profile_valid and profile.size() == 20
		for point: Vector3 in profile:
			profile_valid = profile_valid and point.is_finite() and Vector2(point.x, point.z).length_squared() <= 1.00001
			profile_valid = profile_valid and point.y >= 0.0 and point.y <= 0.76
		for end_row in [0, 16]:
			for j in 4:
				profile_valid = profile_valid and profile[end_row + j].y == 0.0
			profile_valid = profile_valid and profile[end_row + 3].z - profile[end_row].z > 0.5
		# 独立以外围多边形鞋带公式核对实际裁分面积，不照抄网格三角构造。
		var outline := PackedVector2Array()
		for j in 5:
			outline.append(Vector2(profile[j * 4].x, profile[j * 4].z))
		for j in range(4, -1, -1):
			outline.append(Vector2(profile[j * 4 + 3].x, profile[j * 4 + 3].z))
		var expected_area := 0.0
		for j in outline.size():
			expected_area += outline[j].cross(outline[(j + 1) % outline.size()])
		expected_area = absf(expected_area) * 0.5 * float(rock[3]) * float(rock[4])
		valid = valid and absf(projected_area - expected_area) / expected_area < 0.0001
		if (valid_before and not valid) or (fit_before and not terrain_fit):
			print("[Volume ridge diagnostic] index=", i, " triangles=", points.size() / 3,
				" grounded=", bases.size(), " area_error=", absf(projected_area - expected_area) / expected_area,
				" valid=", valid, " terrain_fit=", terrain_fit)
	_check(valid, "all rock meshes finite nondegenerate outward-facing and grounded")
	print("[Volume ridge geometry] min_face_clearance=", min_rock_clearance, " max_local_height=", max_rock_height)
	_check(terrain_fit and min_rock_clearance >= -0.01,
		"deterministic terrain-relative ridges retain grounded boundary, protected footprint and exposed face samples")
	_check(clearance, "outcrops do not overlap each other or scrub footprints")
	_check(profile_valid and profiles.size() == rocks.size(), "all 360 bounded rock profiles have distinct shapes and grounded blunt ends")
	_check(material_mask_valid, "all rock material weights follow local rise and fade to original ground at the boundary")
	print("[Rock material mask] max_packed_error=", material_mask_error)
	var triangles := 0
	for child: MeshInstance3D in details.get_children():
		if String(child.name).begins_with("Scrub_"):
			triangles += child.mesh.surface_get_array_len(0) / 3
	print("[Volume detail budget] total_triangles=", triangles, " ground_cover=25200 rock=", triangles - 25200)
	_check(triangles >= 25200 + rocks.size() * 24 and triangles <= 56400,
		"scrub and rock geometry share sixteen static batches within explicit budget")


func _test_refinement(relief: RefCounted) -> void:
	var surface: RefCounted = relief.surface
	var original := Surface.new(relief.rect, relief.grid_size, relief.heights, relief.cover)
	var source_error := 0.0
	var restored := 0.0
	var in_core := true
	for region: Rect2i in Relief.RIDGE_REGIONS:
		var first: Vector2 = surface._world_node((region.position - Vector2i.ONE) * 2)
		var last: Vector2 = surface._world_node((region.end + Vector2i.ONE) * 2)
		in_core = in_core and minf(first.x, first.y) > -MapBoundary.CORE_HALF_PX and maxf(last.x, last.y) < MapBoundary.CORE_HALF_PX
		for z in range(region.position.y * 2, region.end.y * 2 + 1):
			for x in range(region.position.x * 2, region.end.x * 2 + 1):
				var p: Vector2 = surface._world_node(Vector2i(x, z))
				var expected: float = relief.heights[z * relief.grid_size + x]
				source_error = maxf(source_error, absf(surface.height_at(p) - expected))
				restored = maxf(restored, absf(original.height_at(p) - expected))
	_check(in_core and Relief.RIDGE_REGIONS.size() == 3,
		"every refinement patch and its transition ring are inside the playable 60km core")
	_check(source_error < 0.01 and restored > 76.0 and restored < 77.0,
		"three verified in-core DEM patches restore all source nodes including shared boundary midpoints")
	var triangles := 0
	var edges := {}
	var area := 0.0
	var outside_error := 0.0
	for z in 128:
		for x in 128:
			for triangle: PackedVector2Array in surface.cell_triangles(x, z):
				triangles += 1
				var nodes: Array[Vector2i] = []
				for point: Vector2 in triangle:
					nodes.append(Vector2i(((point - relief.rect.position) / surface.step * 2).round()))
				area += Vector2(nodes[1] - nodes[0]).cross(Vector2(nodes[2] - nodes[0])) * 0.5
				for i in 3:
					var a := nodes[i]
					var b := nodes[(i + 1) % 3]
					if a.x > b.x or (a.x == b.x and a.y > b.y):
						var swap := a
						a = b
						b = swap
					var key := Vector4i(a.x, a.y, b.x, b.y)
					edges[key] = int(edges.get(key, 0)) + 1
			if not surface._refinement.has(Vector2i(x, z)):
				var p: Vector2 = relief.rect.position + (Vector2(x, z) + Vector2(0.31, 0.69)) * surface.step
				outside_error = maxf(outside_error, absf(surface.height_at(p) - original.height_at(p)))
	var boundary := 0
	var closed := true
	for key: Vector4i in edges:
		var outer := (key.x == 0 and key.z == 0) or (key.x == 256 and key.z == 256) or (key.y == 0 and key.w == 0) or (key.y == 256 and key.w == 256)
		closed = closed and edges[key] == (1 if outer else 2)
		if outer:
			boundary += 1
	_check(closed and boundary == 512 and triangles == 33038 and area == 65536.0 and surface._refinement.size() == 63,
		"27 fine plus 36 transition cells form a closed 33038-triangle topology without T-junctions")
	_check(outside_error == 0.0, "height outside the 63 affected cells is unchanged")
	var errors := Vector3.ZERO
	var rock_error := 0.0
	var rock_vertices := 0
	for region: Rect2i in Relief.RIDGE_REGIONS:
		var crop := Rect2(relief.rect.position + (Vector2(region.position) - Vector2(0.63, 0.77)) * surface.step,
			(Vector2(region.size) + Vector2(1.91, 1.39)) * surface.step)
		errors = errors.max(_surface_error(surface, surface.plane_mesh(crop, Rect2(0, 0, 1, 1), -0.6), -0.6))
		var builder := Relief.Geometry.new()
		var a := crop.position
		var b := crop.end
		relief._add_surface_triangle(builder, Vector3(a.x, 5, a.y), Vector3(a.x, 5, b.y), Vector3(b.x, 5, b.y), Color.WHITE)
		var points: PackedVector3Array = builder.mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		rock_vertices += points.size()
		for i in range(0, points.size(), 3):
			for weights: Vector3 in [Vector3.ONE / 3, Vector3(0.2, 0.3, 0.5)]:
				var p := points[i] * weights.x + points[i + 1] * weights.y + points[i + 2] * weights.z
				rock_error = maxf(rock_error, absf(p.y - surface.height_at(Vector2(p.x, p.z)) - 5.0))
	_check(errors[errors.max_axis_index()] < 0.01,
		"three non-aligned crops across fine transition and coarse cells preserve height normal and cover interiors")
	_check(rock_vertices > 300 and rock_error < 0.01,
		"rock clipping in all three patches preserves local rise inside every refined face")
	print("[Volume refinement] source_error=", source_error, " restored=", restored, " triangles=", triangles,
		" outside_error=", outside_error, " crop_errors=", errors, " rock_error=", rock_error)


func _test_surface_contract() -> void:
	var heights := PackedFloat32Array()
	heights.resize(25)
	heights.fill(999.0) # 奇数格点尖峰不得泄入两格渲染曲面。
	for z in range(0, 5, 2):
		for x in range(0, 5, 2):
			heights[z * 5 + x] = 0
	heights[2] = 10
	heights[10] = 30
	heights[12] = 80
	var cover := PackedFloat32Array()
	cover.resize(25)
	cover[12] = 1.0
	var surface := Surface.new(Rect2(0, 0, 4, 4), 5, heights, cover)
	_check(absf(surface.height_at(Vector2(1.5, 0.5)) - 25) < 0.0001
		and absf(surface.height_at(Vector2(0.5, 1.5)) - 35) < 0.0001,
		"hand-computed triangle weights ignore absent odd-grid peaks")
	# 原始三个端点很低，面内跨越80px尖峰；顶点贴地方案必须被这个反例击穿。
	var ridge := Relief.new(false)
	ridge.surface = surface
	ridge.rect = surface.rect
	var ridge_builder := Relief.Geometry.new()
	ridge._add_surface_triangle(ridge_builder, Vector3(0, 5, 0), Vector3(0, 0, 4), Vector3(4, 0, 4), Color.WHITE)
	var ridge_points: PackedVector3Array = ridge_builder.mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ridge_error := 0.0
	for i in range(0, ridge_points.size(), 3):
		for sample: Vector3 in [ridge_points[i], (ridge_points[i] + ridge_points[i+1] + ridge_points[i+2]) / 3.0]:
			var expected: float = surface.height_at(Vector2(sample.x, sample.z)) + 5.0 * (1.0 - sample.z / 4.0)
			ridge_error = maxf(ridge_error, absf(sample.y - expected))
	_check(ridge_points.size() > 3 and ridge_error < 0.0001,
		"rock face across an 80px terrain peak preserves terrain plus linear rise inside every clipped face")
	var mesh := surface.plane_mesh(Rect2(0.37, 0.53, 1.18, 1.23), Rect2(0.1, 0.2, 0.7, 0.6), -0.6)
	var error := _surface_error(surface, mesh, -0.6)
	print("[Volume synthetic surface error] height/normal/cover=", error)
	_check(error[error.max_axis_index()] < 0.0001,
		"non-aligned tile crossing source diagonal preserves surface and interpolants")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var valid := true
	var area := 0.0
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var signed_area := Vector2(b.x - a.x, b.z - a.z).cross(Vector2(c.x - a.x, c.z - a.z)) * 0.5
		valid = valid and signed_area > 0
		area += signed_area
	_check(valid and absf(area - 1.18 * 1.23) < 0.00001, "tile clipping covers full content with consistent front winding")
	valid = true
	for i in vertices.size():
		var p := Vector2(vertices[i].x, vertices[i].z)
		var expected := Vector2(0.1, 0.2) + (p - Vector2(0.37, 0.53)) / Vector2(1.18, 1.23) * Vector2(0.7, 0.6)
		valid = valid and uvs[i].distance_to(expected) < 0.0001
	_check(valid, "clipped intersections retain exact gutter UV mapping")


func _surface_error(surface: RefCounted, mesh: ArrayMesh, base_y: float) -> Vector3:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var attributes: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var result := Vector3.ZERO
	for i in range(0, indices.size(), 3):
		for weights: Vector3 in [Vector3.ONE / 3, Vector3(0.2, 0.3, 0.5)]:
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var cover := 0.0
			for j in 3:
				p += vertices[indices[i + j]] * weights[j]
				var at := indices[i + j] * 4
				n += Vector3(attributes[at], attributes[at + 1], attributes[at + 2]) * weights[j]
				cover += attributes[at + 3] * weights[j]
			var at := Vector2(p.x, p.z)
			result.x = maxf(result.x, absf(p.y - base_y - surface.height_at(at)))
			result.y = maxf(result.y, n.distance_to(surface.normal_at(at)))
			result.z = maxf(result.z, absf(cover - surface._sample_scalar(at, surface.cover)))
	return result


func _test_tile_budget(relief: RefCounted) -> int:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/basemap_tiles/desert/manifest.json"))
	var counts: Array[int] = []
	var finite := true
	for name: String in ["operational", "detail"]:
		var level: Dictionary = manifest.levels[name]
		var size := Vector2(level["size"][0], level["size"][1])
		for tile: Dictionary in level.tiles:
			var content: Array = tile.content_rect
			var bounds := Rect2(relief.rect.position + Vector2(content[0], content[1]) / size * relief.rect.size,
				Vector2(content[2], content[3]) / size * relief.rect.size)
			var mesh: ArrayMesh = relief.plane_mesh(bounds, Rect2(0, 0, 1, 1), -0.6)
			counts.append(mesh.surface_get_array_index_len(0) / 3)
			for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				finite = finite and vertex.is_finite()
	counts.sort()
	var maximum: int = relief.plane_mesh(relief.rect, Rect2(0, 0, 1, 1), -0.8).surface_get_array_index_len(0) / 3
	for i in 16:
		maximum += counts[counts.size() - 1 - i]
	_check(finite and counts.size() == 145 and maximum <= 100000,
		"all 145 real tiles compile within conservative 17-plane terrain budget")
	print("[Volume terrain budget] all_tiles=%d worst_17_planes=%d" % [counts.size(), maximum])
	return maximum


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume relief: " + label)
