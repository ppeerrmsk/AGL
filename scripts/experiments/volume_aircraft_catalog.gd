extends RefCounted
## 专属低模生产目录。只在受控预热时构建，共享只读网格；不持有单位、不新增 tick。
## 坐标与原型一致：X 向右、Y 向上、机头 -Z；顶点色供现有机体颜色乘算。

const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const TRIANGLE_BUDGET := 600
const BODY_LOD_MEDIUM := 1
const BODY_LOD_LOW := 2
const BODY_LOD_MEDIUM_TRIANGLE_BUDGET := 320
const BODY_LOD_LOW_TRIANGLE_BUDGET := 128
const SUPPORTED_KEYS: Array[String] = [
	"f14", "a10", "f47", "f104", "f15", "f16", "f22", "f35", "yf23", "tu160", "b1b",
	"f4", "f86", "f100", "fa18", "mig29", "su27", "rafale", "typhoon",
	"a6e", "a7", "ea6b", "f15smtd", "fa18e", "fck1", "gripen", "harrier",
	"j20", "j35f", "j7", "jaguar", "mig21f13", "mig23", "mig31", "mirage3",
	"mirage2000", "q5", "su34", "su47", "su57", "tornado", "viggen", "a12",
	"ah64", "ch47", "mq109_family", "mq112", "mqx", "aegis_uav", "loyal_wingman", "probe",
	"faxx", "fcas", "gcap", "j36", "mig41", "af03", "ax00", "cre",
	"deadair", "sentinel", "snowblind", "hyper_a", "mother_goose", "x02", "x09", "x13",
	"x21", "x44", "x77", "x90", "orion_final_form", "orion_fang",
]
const BODY := Color.WHITE
## alpha 只作为正式实例着色器的机翼掩码；不进入透明管线。
const WING_BODY := Color(1.0, 1.0, 1.0, 0.5)
const CANOPY := Color(0.20, 0.30, 0.37)
const ENGINE := Color(0.74, 0.78, 0.80)
const INTAKE := Color(0.16, 0.19, 0.21)

static var _meshes: Dictionary = {}
static var _runtime_meshes: Dictionary = {}
static var _body_lod_meshes: Dictionary = {}
static var _shared_material: StandardMaterial3D


static func supported_keys() -> Array[String]:
	return SUPPORTED_KEYS.duplicate()


## 未制作类型返回 null，由调用者保留原显示，不能悄悄改成另一架飞机。
static func build(kind: String) -> ArrayMesh:
	if not supported_keys().has(kind):
		return null
	if _meshes.has(kind):
		return _meshes[kind] as ArrayMesh
	var builder := Factory.new()
	match kind:
		"f14":
			_build_f14(builder)
		"a10":
			_build_a10(builder)
		"f47":
			_build_f47(builder)
		"f104":
			_build_f104(builder)
		"f15":
			_build_f15(builder)
		"f16":
			_build_f16(builder)
		"f22":
			_build_f22(builder)
		"f35":
			_build_f35(builder)
		"yf23":
			_build_yf23(builder)
		"tu160":
			_build_tu160(builder)
		"b1b":
			_build_b1b(builder)
		"f4":
			_build_f4(builder)
		"f86":
			_build_f86(builder)
		"f100":
			_build_f100(builder)
		"fa18":
			_build_fa18(builder)
		"mig29":
			_build_mig29(builder)
		"su27":
			_build_su27(builder)
		"rafale":
			_build_rafale(builder)
		"typhoon":
			_build_typhoon(builder)
		"a6e":
			_build_a6e(builder)
		"a7":
			_build_a7(builder)
		"ea6b":
			_build_ea6b(builder)
		"f15smtd":
			_build_f15smtd(builder)
		"fa18e":
			_build_fa18e(builder)
		"fck1":
			_build_fck1(builder)
		"gripen":
			_build_gripen(builder)
		"harrier":
			_build_harrier(builder)
		"j20":
			_build_j20(builder)
		"j35f":
			_build_j35f(builder)
		"j7":
			_build_j7(builder)
		"jaguar":
			_build_jaguar(builder)
		"mig21f13":
			_build_mig21f13(builder)
		"mig23":
			_build_mig23(builder)
		"mig31":
			_build_mig31(builder)
		"mirage3":
			_build_mirage3(builder)
		"mirage2000":
			_build_mirage2000(builder)
		"q5":
			_build_q5(builder)
		"su34":
			_build_su34(builder)
		"su47":
			_build_su47(builder)
		"su57":
			_build_su57(builder)
		"tornado":
			_build_tornado(builder)
		"viggen":
			_build_viggen(builder)
		"a12":
			_build_a12(builder)
		"ah64":
			_build_ah64(builder)
		"ch47":
			_build_ch47(builder)
		"mq109_family":
			_build_mq109_family(builder)
		"mq112":
			_build_mq112(builder)
		"mqx":
			_build_mqx(builder)
		"aegis_uav":
			_build_aegis_uav(builder)
		"loyal_wingman":
			_build_loyal_wingman(builder)
		"probe":
			_build_probe(builder)
		"faxx":
			_build_faxx(builder)
		"fcas":
			_build_fcas(builder)
		"gcap":
			_build_gcap(builder)
		"j36":
			_build_j36(builder)
		"mig41":
			_build_mig41(builder)
		"af03":
			_build_af03(builder)
		"ax00":
			_build_ax00(builder)
		"cre":
			_build_cre(builder)
		"orion_final_form":
			_build_orion_final_form(builder)
		"orion_fang":
			_build_orion_fang(builder)
		"deadair":
			_build_deadair(builder)
		"sentinel":
			_build_sentinel(builder)
		"snowblind":
			_build_snowblind(builder)
		"hyper_a":
			_build_hyper_a(builder)
		"mother_goose":
			_build_mother_goose(builder)
		"x02":
			_build_x02(builder)
		"x09":
			_build_x09(builder)
		"x13":
			_build_x13(builder)
		"x21":
			_build_x21(builder)
		"x44":
			_build_x44(builder)
		"x77":
			_build_x77(builder)
		"x90":
			_build_x90(builder)
	var result: ArrayMesh = builder.mesh()
	if _shared_material == null:
		_shared_material = Factory.material()
	result.surface_set_material(0, _shared_material)
	result.resource_name = "AGL_%s_dedicated_volume" % kind
	_meshes[kind] = result
	return result


## 旋翼机运行时用不含静态桨叶的机身网格，桨叶由共享挂载批次按真实时间转动。
## 其它机型直接复用四视图验收网格。
static func build_runtime(kind: String) -> ArrayMesh:
	if kind not in ["ah64", "ch47"]:
		return build(kind)
	if _runtime_meshes.has(kind):
		return _runtime_meshes[kind] as ArrayMesh
	var builder := Factory.new()
	if kind == "ah64":
		_build_ah64(builder, false)
	else:
		_build_ch47(builder, false)
	var result: ArrayMesh = builder.mesh()
	if _shared_material == null:
		_shared_material = Factory.material()
	result.surface_set_material(0, _shared_material)
	result.resource_name = "AGL_%s_runtime_body" % kind
	_runtime_meshes[kind] = result
	return result


## 视觉 LOD 只由最终屏幕占用决定；玩家/BOSS/旋翼机等逻辑身份不构成画质豁免。
static func supports_body_lod(kind: String) -> bool:
	return kind in SUPPORTED_KEYS


## LOD0 复用正式运行时网格；LOD1 把该机型制作源的主要连通体分别压成低成本体块，
## 保留机身、主翼、平尾、座舱/发动机等结构；LOD2 才使用最远景对称轮廓。
## 两档都从本机型制作源派生，不使用跨机型通用代理。未知级别显式拒绝。
static func build_runtime_lod(kind: String, lod_level: int) -> ArrayMesh:
	if lod_level == 0:
		return build_runtime(kind)
	if lod_level not in [BODY_LOD_MEDIUM, BODY_LOD_LOW] or not supports_body_lod(kind):
		return null
	var cache_key := "%d:%s" % [lod_level, kind]
	if _body_lod_meshes.has(cache_key):
		return _body_lod_meshes[cache_key] as ArrayMesh
	# 旋翼机的 LOD0 运行时将桨叶拆到动态批次；两个降级档均从完整制作源
	# 提取包含桨盘跨度的静态网格，避免中远景仍提交动态旋翼。
	var source := build(kind)
	if source == null or source.get_surface_count() != 1:
		return null
	var medium_budget := mini(BODY_LOD_MEDIUM_TRIANGLE_BUDGET,
		floori(float(source.surface_get_array_len(0)) / 3.0 * 0.8)) \
		if kind in ["orion_final_form", "orion_fang"] else BODY_LOD_MEDIUM_TRIANGLE_BUDGET
	var result := _build_medium_body_lod(source, medium_budget) if lod_level == BODY_LOD_MEDIUM \
		else _build_far_body_lod(source)
	if lod_level == BODY_LOD_LOW and kind in ["orion_final_form", "orion_fang"]:
		result = _build_orion_far_lod(kind == "orion_fang")
	if result == null or result.get_surface_count() != 1:
		return null
	if _shared_material == null:
		_shared_material = Factory.material()
	result.surface_set_material(0, _shared_material)
	result.resource_name = "AGL_%s_runtime_lod%d" % [kind, lod_level]
	_body_lod_meshes[cache_key] = result
	return result


## 中景档按制作源的连通部件保留主要体块。左右部件只取正侧再镜像，避免预算截断时
## 偶然只留下单侧发动机/尾翼；中央部件使用对称支撑轮廓。最多保留到 320 三角。
static func _build_medium_body_lod(source: ArrayMesh,
		triangle_budget: int = BODY_LOD_MEDIUM_TRIANGLE_BUDGET) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if vertices.is_empty():
		return null
	var components := _connected_components(vertices, colors)
	var candidates: Array[Dictionary] = []
	var source_bounds := source.get_aabb()
	var center_epsilon := maxf(source_bounds.size.x * 0.025, 0.05)
	for component in components:
		var points: PackedVector2Array = component.points
		if points.size() < 3:
			continue
		var bounds_2d := _points_bounds(points)
		var center_x := bounds_2d.get_center().x
		var crosses_center := bounds_2d.position.x <= center_epsilon \
			and bounds_2d.end.x >= -center_epsilon
		# 负侧部件由对应正侧部件镜像生成；源模型本身已有强制对称几何门。
		if not crosses_center and center_x < 0.0:
			continue
		var outline := _support_outline(points, 10) if crosses_center \
			else _directional_outline(points, 8)
		if outline.size() < 3:
			continue
		var component_bottom := float(component.bottom)
		var component_top := float(component.top)
		var height := component_top - component_bottom
		if height < 0.05:
			var center_y := (component_bottom + component_top) * 0.5
			component_bottom = center_y - 0.025
			component_top = center_y + 0.025
			height = 0.05
		var score := absf(_polygon_area(outline)) \
			+ maxf(bounds_2d.size.x, bounds_2d.size.y) * height * 0.35
		candidates.append({
			"outline": outline,
			"bottom": component_bottom,
			"top": component_top,
			"color": component.color,
			"mirror": not crosses_center,
			"score": score,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score))
	var builder := Factory.new()
	var triangle_count := 0
	for candidate in candidates:
		var outline: PackedVector2Array = candidate.outline
		var cost := _prism_triangle_count(outline.size()) * (2 if bool(candidate.mirror) else 1)
		if triangle_count + cost > triangle_budget:
			continue
		builder.prism(outline, float(candidate.bottom), float(candidate.top), candidate.color)
		if bool(candidate.mirror):
			builder.prism(_mirrored_outline(outline), float(candidate.bottom),
				float(candidate.top), candidate.color)
		triangle_count += cost
	# 极端制作源若无法形成连通体，回退到本机型的远景派生，而不是通用飞机。
	if triangle_count == 0:
		return _build_far_body_lod(source)
	return builder.mesh()


## 最远景只保留本机型的整体平面轮廓与中央体块。它只在最终输出不足 8 px 时使用。
static func _build_far_body_lod(source: ArrayMesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var planform_points := PackedVector2Array()
	var body_points := PackedVector2Array()
	var average_y := 0.0
	var has_wing_mask := false
	for index in vertices.size():
		var vertex := vertices[index]
		planform_points.append(Vector2(vertex.x, vertex.z))
		average_y += vertex.y
		if index < colors.size() and colors[index].a < 0.75:
			has_wing_mask = true
		elif index < colors.size():
			body_points.append(Vector2(vertex.x, vertex.z))
	if vertices.is_empty():
		return null
	average_y /= float(vertices.size())
	var outline := _support_outline(planform_points, 8)
	if outline.size() < 3:
		return null
	var bounds := source.get_aabb()
	var thickness := clampf(minf(bounds.size.x, bounds.size.z) * 0.025, 0.6, 2.0)
	var builder := Factory.new()
	if has_wing_mask:
		builder.prism(outline, average_y - thickness * 0.5, average_y + thickness * 0.5,
			WING_BODY)
		var body_outline := _support_outline(body_points, 6)
		if body_outline.size() >= 3:
			builder.prism(body_outline, average_y + thickness * 0.35,
				average_y + thickness * 1.15, BODY)
	else:
		builder.prism(outline, average_y - thickness * 0.5, average_y + thickness * 0.5,
			BODY)
	return builder.mesh()


## 三角汤按共享顶点位置分成制作部件；只在预热构建共享 LOD 网格时运行。
static func _connected_components(vertices: PackedVector3Array,
		colors: PackedColorArray) -> Array[Dictionary]:
	var triangle_count := vertices.size() / 3
	var vertex_triangles: Dictionary = {}
	for triangle_index in triangle_count:
		for corner in 3:
			var point := vertices[triangle_index * 3 + corner]
			var touching: Array = vertex_triangles.get(point, [])
			touching.append(triangle_index)
			vertex_triangles[point] = touching
	var visited := PackedByteArray()
	visited.resize(triangle_count)
	visited.fill(0)
	var result: Array[Dictionary] = []
	for seed in triangle_count:
		if visited[seed] != 0:
			continue
		var stack: Array[int] = [seed]
		visited[seed] = 1
		var points := PackedVector2Array()
		var bottom := INF
		var top := -INF
		var component_color := colors[seed * 3] if seed * 3 < colors.size() else BODY
		while not stack.is_empty():
			var triangle_index: int = stack.pop_back()
			for corner in 3:
				var vertex_index := triangle_index * 3 + corner
				var point := vertices[vertex_index]
				points.append(Vector2(point.x, point.z))
				bottom = minf(bottom, point.y)
				top = maxf(top, point.y)
				for neighbor: int in vertex_triangles.get(point, []):
					if visited[neighbor] == 0:
						visited[neighbor] = 1
						stack.append(neighbor)
		result.append({"points": points, "bottom": bottom, "top": top,
			"color": component_color})
	return result


static func _directional_outline(points: PackedVector2Array,
		direction_count: int) -> PackedVector2Array:
	var selected := PackedVector2Array()
	if points.is_empty() or direction_count < 3:
		return selected
	for direction_index in direction_count:
		var angle := TAU * float(direction_index) / float(direction_count)
		var direction := Vector2(cos(angle), sin(angle))
		var best_point := points[0]
		var best_score := -INF
		for point in points:
			var score := point.dot(direction)
			if score > best_score:
				best_score = score
				best_point = point
		if not selected.has(best_point):
			selected.append(best_point)
	var hull := Geometry2D.convex_hull(selected)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


static func _mirrored_outline(outline: PackedVector2Array) -> PackedVector2Array:
	var mirrored := PackedVector2Array()
	for point in outline:
		mirrored.append(Vector2(-point.x, point.y))
	return mirrored


static func _points_bounds(points: PackedVector2Array) -> Rect2:
	var min_point := points[0]
	var max_point := points[0]
	for point in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return Rect2(min_point, max_point - min_point)


static func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


static func _prism_triangle_count(point_count: int) -> int:
	return maxi(0, point_count * 4 - 4)


## 固定方向的支撑点保留机鼻、尾端、翼尖和斜后缘；同时加入镜像点，避免 tie 顺序
## 让远景轮廓偏向一侧。输出最多 2×direction_count 个凸包点。
static func _support_outline(points: PackedVector2Array, direction_count: int) -> PackedVector2Array:
	var selected := PackedVector2Array()
	if points.is_empty() or direction_count < 3:
		return selected
	for direction_index in direction_count:
		var angle := TAU * float(direction_index) / float(direction_count)
		var direction := Vector2(cos(angle), sin(angle))
		var best_point := points[0]
		var best_score := -1.0e30
		for point in points:
			var score := point.dot(direction)
			if score > best_score:
				best_score = score
				best_point = point
		for candidate in [best_point, Vector2(-best_point.x, best_point.y)]:
			var duplicate := false
			for existing in selected:
				if existing.is_equal_approx(candidate):
					duplicate = true
					break
			if not duplicate:
				selected.append(candidate)
	var hull := Geometry2D.convex_hull(selected)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


## 制作记录只描述本批近似模型，不把现有 PNG 的审核结论移植为 3D 写实认证。
static func metadata_for(kind: String) -> Dictionary:
	var record: Dictionary
	match kind:
		"f14":
			record = {
				"name": "F-14", "triangles": 432,
				"source": "res://resources/aircraft_silhouettes/f14_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Grumman_F-14_Tomcat.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Army",
				"attribution": "US Army; AGL simplified 3D reconstruction",
				"shape": "展开翼固定姿态、长鼻双座舱、翼根手套、分离双发与双垂尾",
				"fidelity": "按项目已审展开翼顶视轮廓近似；厚度为本批美术设计，不含变后掠动画",
			}
		"a10":
			record = {
				"name": "A-10", "triangles": 412,
				"source": "res://resources/aircraft_silhouettes/a10_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Fairchild_Republic_A-10_Thunderbolt_II_3-view.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 3.0",
				"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
				"attribution": "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"shape": "宽直翼、短粗机身、后置高双发、H 形尾翼、机鼻炮口",
				"fidelity": "按项目已审顶视比例近似；保留署名与同许可，三维厚度不是测绘数据",
			}
		"f47":
			record = {
				"name": "F-47", "triangles": 416,
				"source": "res://scripts/aircraft_renderer.gd",
				"source_symbol": "draw_aircraft_icon: legacy body / stealth wings / tail polygons",
				"source_license": "AGL project-authored concept geometry",
				"attribution": "AGL project concept; no external F-47 model copied",
				"shape": "宽扁折面机身、菱形后掠翼、低矮双喷口、外倾双垂尾",
				"fidelity": "现有 F-47 无获审 PNG；沿用项目 legacy/stealth 语汇的原创概念，不声称真实 F-47 外形",
			}
		"f104":
			record = {
				"name": "F-104", "triangles": 372,
				"source": "res://resources/aircraft_silhouettes/f104_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Lockheed_F-104C_Starfighter.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 3.0",
				"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
				"attribution": "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"shape": "完整细长机鼻、极短薄主翼、侧进气、单发尾段、梯形平尾与高单垂尾",
				"fidelity": "按完整三视图重建；机头 -Z，不能复用历史误截的后半机身轮廓",
			}
		"f15":
			record = {
				"name": "F-15", "triangles": 448,
				"source": "res://resources/aircraft_silhouettes/f15_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_F-15_Eagle_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Army",
				"attribution": "US Army; AGL simplified 3D reconstruction",
				"shape": "尖长机鼻、肩部翼身融合、梯形主翼、分离双发进气/喷口与双垂尾",
				"fidelity": "按公版三视图与用户批准顶视轮廓重建；不使用曾被否决的通用双尾尖角模板",
			}
		"f16":
			record = {
				"name": "F-16", "triangles": 320,
				"source": "res://resources/aircraft_silhouettes/f16_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:General_Dynamics_F-16_Fighting_Falcon_3-view_line_drawing.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Air Force",
				"attribution": "US Air Force; AGL simplified 3D reconstruction",
				"shape": "单发轻型机身、腹部进气、裁角三角翼、翼根边条、单垂尾和平尾",
				"fidelity": "按公版三视图比例近似；保留单发与腹部进气辨识，不含挂载细节",
			}
		"f22":
			record = {
				"name": "F-22", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/f22_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Lockheed_Martin_F-22A_Raptor_3-view.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 2.0",
				"license_url": "https://creativecommons.org/licenses/by-sa/2.0/",
				"attribution": "Wikimedia F-22A three-view; AGL simplified 3D adaptation, CC BY-SA 2.0",
				"shape": "宽扁菱形机身、长前缘边条、梯形主翼、分离双发和外倾双垂尾",
				"fidelity": "按获审 F-22A 三视图近似；折面与厚度为低模重建，不复制第三方模型",
			}
		"f35":
			record = {
				"name": "F-35", "triangles": 328,
				"source": "res://resources/aircraft_silhouettes/f35_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Lockheed_Martin_F-35A_Lightning_II_3-view_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain orthographic drawing",
				"attribution": "Public-domain F-35A drawing; AGL simplified 3D reconstruction",
				"shape": "单发厚机身、两侧进气、梯形主翼、后置平尾与外倾双垂尾",
				"fidelity": "按公版 F-35A 三视图近似；不表现 B/C 型升力风扇或折翼差异",
			}
		"yf23":
			record = {
				"name": "YF-23", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/yf23_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:YF-22_et_YF-23.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 4.0",
				"license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
				"attribution": "Wikimedia YF-22/YF-23 comparison; AGL simplified 3D adaptation, CC BY-SA 4.0",
				"shape": "长菱形主翼、宽扁前机身、分离双发舱、后缘深切口与外倾 V 尾",
				"fidelity": "按获审 YF-23 顶视比较图与项目三维体量重建；不套用 F-22 梯形翼/平尾",
			}
		"tu160":
			record = {
				"name": "Tu-160", "triangles": 564,
				"source": "res://resources/aircraft_silhouettes/tu160_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Tupolev_Tu-160_and_Rockwell_B-1B_top-view_silhouette_comparison.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain",
				"attribution": "Public-domain Tu-160/B-1B comparison; AGL simplified 3D reconstruction",
				"shape": "白天鹅式长尖鼻、翼根肩部、四具分离发动机、变后掠翼、平尾与高单垂尾",
				"fidelity": "按公版三视图比例近似；采用固定中后掠展示姿态，不含变翼动画",
			}
		"b1b":
			record = {
				"name": "B-1B", "triangles": 564,
				"source": "res://resources/aircraft_silhouettes/b1b_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Tupolev_Tu-160_and_Rockwell_B-1B_top-view_silhouette_comparison.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain",
				"attribution": "Public-domain Tu-160/B-1B comparison; AGL simplified 3D reconstruction",
				"shape": "低矮长机鼻、翼身融合手套、四发双联短舱、变后掠翼、低平尾与单垂尾",
				"fidelity": "按公版三视图比例近似；与 Tu-160 分别制作，采用固定中后掠展示姿态",
			}
		"f4":
			record = {
				"name": "F-4E", "triangles": 444,
				"source": "res://resources/aircraft_silhouettes/f4_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_F-4E_Phantom_II_3-view_line_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US military",
				"attribution": "US military drawing; AGL simplified 3D reconstruction",
				"shape": "宽肩双发机身、折线后掠翼、分离双喷口、低置平尾与高单垂尾",
				"fidelity": "按项目已审 F-4E 三视图近似；保留双发与机翼折线，不复用 F-15 结构",
			}
		"f86":
			record = {
				"name": "F-86F", "triangles": 260,
				"source": "res://resources/aircraft_silhouettes/f86_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:North_American_F-86F_Sabre_3-view_line_drawing.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 4.0 / GFDL",
				"license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
				"attribution": "Steal88; AGL simplified 3D adaptation, CC BY-SA 4.0",
				"shape": "圆形机鼻进气、桶形单发机身、宽后掠翼、低平尾与单垂尾",
				"fidelity": "按获审 F-86F 三视图近似；机鼻进气和近一比一翼展/机长是辨识重点",
			}
		"f100":
			record = {
				"name": "F-100", "triangles": 252,
				"source": "res://resources/aircraft_silhouettes/f100_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:North_American_F-100_Super_Sabre_3-view.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, NASA",
				"attribution": "NASA; AGL simplified 3D reconstruction",
				"shape": "扁椭圆机鼻进气、细长单发机身、大后掠翼、低平尾与高后掠单垂尾",
				"fidelity": "按项目已审 F-100 三视图近似；与 F-86 分别制作并保留更细长比例",
			}
		"fa18":
			record = {
				"name": "F/A-18", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/fa18_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_F-18A_Hornet_3-view.gif",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, NASA",
				"attribution": "NASA; AGL simplified 3D reconstruction",
				"shape": "尖鼻双发机身、长边条翼、梯形主翼、分离进气/喷口与外倾双垂尾",
				"fidelity": "按 NASA F/A-18A 三视图近似；不与 Super Hornet 的更大翼面混为同一几何",
			}
		"mig29":
			record = {
				"name": "MiG-29", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/mig29_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Mikoyan_MiG-29_3-view.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 3.0 / GFDL",
				"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
				"attribution": "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"shape": "宽边条双发机身、后掠梯形翼、分离发动机短舱、双垂尾与大平尾",
				"fidelity": "按获审 MiG-29 三视图近似；短粗翼身和发动机间槽区别于 Su-27",
			}
		"su27":
			record = {
				"name": "Su-27", "triangles": 440,
				"source": "res://resources/aircraft_silhouettes/su27_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Sukhoi_Su-27_3-view_line_drawing.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Army",
				"attribution": "US Army; AGL simplified 3D reconstruction",
				"shape": "长尖鼻、连续弧形边条、宽后掠翼、长分离双发舱、双垂尾与大平尾",
				"fidelity": "按获审 Su-27 三视图近似；以更长鼻段、翼身融合与长尾梁区别 MiG-29",
			}
		"rafale":
			record = {
				"name": "Rafale", "triangles": 412,
				"source": "res://resources/aircraft_silhouettes/rafale_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Dassault_Rafale_silhouette-top.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain dedication",
				"attribution": "Sting; AGL simplified 3D reconstruction",
				"shape": "细长尖鼻、近耦合前翼、大三角翼、双发尾段与单垂尾",
				"fidelity": "按项目已审顶视轮廓和公开侧面结构近似；不把 Typhoon 前翼/进气布局套用过来",
			}
		"typhoon":
			record = {
				"name": "Eurofighter Typhoon", "triangles": 404,
				"source": "res://resources/aircraft_silhouettes/typhoon_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Eurofighter_Typhoon_line_drawing.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain dedication",
				"attribution": "Inductiveload; AGL simplified 3D reconstruction",
				"shape": "尖鼻、前置三角前翼、裁角大三角翼、腹部双进气、双发尾段与单垂尾",
				"fidelity": "按获审 Typhoon 顶视线图近似；主翼后缘、前翼位置和进气结构独立于 Rafale",
			}
		"a6e":
			record = {
				"name": "A-6E", "triangles": 412,
				"source": "res://resources/aircraft_silhouettes/a6e_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Grumman_A-6_Intruder_3-view_line_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "reviewed orthographic source; license recorded at source page",
				"attribution": "Reviewed Wikimedia three-view; AGL simplified 3D reconstruction",
				"shape": "宽钝并列座舱鼻、肩部双进气、宽直后掠翼、双发尾段与高单垂尾",
				"fidelity": "按项目已审 A-6E 三视图近似；保留并列座舱和宽翼，不与 EA-6B 共用几何",
			}
		"a7":
			record = {
				"name": "A-7", "triangles": 272,
				"source": "res://resources/aircraft_silhouettes/a7_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:LTV_A-7_Corsair_II_3-view_line_drawing.gif",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "reviewed orthographic source; license recorded at source page",
				"attribution": "Reviewed Wikimedia three-view; AGL simplified 3D reconstruction",
				"shape": "短粗单发机身、机鼻下方进气、后掠翼、低平尾与高单垂尾",
				"fidelity": "按项目已审 A-7 三视图近似；机鼻下进气和单发结构区别 A-6E",
			}
		"ea6b":
			record = {
				"name": "EA-6B", "triangles": 552,
				"source": "res://resources/aircraft_silhouettes/ea6b_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Grumman_EA-6B_Prowler_3-view_line_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Navy / NAVAIR",
				"attribution": "US Navy NAVAIR; AGL simplified 3D reconstruction",
				"shape": "加长四座舱、宽翼、双发进气、翼尖电战舱与垂尾顶整流罩",
				"fidelity": "按获审完整 NAVAIR 顶视与三视结构近似；不是 A-6E 改显示名",
			}
		"f15smtd":
			record = {
				"name": "F-15 S/MTD", "triangles": 448,
				"source": "res://resources/aircraft_silhouettes/f15smtd_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:MTD_line_drawing.gif",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, NASA",
				"attribution": "NASA; AGL simplified 3D reconstruction",
				"shape": "F-15 宽肩双发布局、独立前翼、梯形主翼、双垂尾与矢量喷口",
				"fidelity": "按 NASA S/MTD 三视图近似；前翼和尾喷口使其拥有独立网格签名",
			}
		"fa18e":
			record = {
				"name": "F/A-18E", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/fa18e_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Northrop_YF-17_McDonnell_Douglas_FA-18_Boeing_FA-18EF_Super_Hornet.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain",
				"attribution": "Greg Goebel and Datumizer; AGL simplified 3D reconstruction",
				"shape": "放大梯形翼、锯齿长边条、矩形双进气、双发、宽平尾与外倾双垂尾",
				"fidelity": "按获审 F/A-18F 轮廓近似；与早期 Hornet 分别制作，Growler 沿用同机体",
			}
		"fck1":
			record = {
				"name": "F-CK-1", "triangles": 456,
				"source": "res://resources/aircraft_silhouettes/fck1_detail.png",
				"source_url": "https://man.fas.org/dod-101/sys/ac/row/idf.htm",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "not stated on archived reference page",
				"attribution": "FAS DOD 101 archive; AGL independently simplified factual geometry",
				"shape": "轻型尖鼻、宽边条、裁角后掠翼、双发尾段、双垂尾与大平尾",
				"fidelity": "按已审档案线图的事实比例近似；不复制线条细节或材质",
			}
		"gripen":
			record = {
				"name": "JAS 39 Gripen", "triangles": 276,
				"source": "res://resources/aircraft_silhouettes/gripen_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Saab_JAS_39_Gripen_3-view.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 3.0 / GFDL",
				"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
				"attribution": "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"shape": "小型单发机身、近耦合前翼、裁角三角翼、两侧进气与单垂尾",
				"fidelity": "按获审 Gripen 三视图近似；C/E 同 key 沿用项目既有家族裁定",
			}
		"harrier":
			record = {
				"name": "Harrier GR.7", "triangles": 332,
				"source": "res://resources/aircraft_silhouettes/harrier_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_AV-8B_Harrier_II_3-view_line_drawing.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Army",
				"attribution": "US Army; AGL simplified 3D reconstruction",
				"shape": "高置小后掠翼、单发宽机身、两侧大进气、四个矢量喷口、低平尾与单垂尾",
				"fidelity": "按获审 AV-8B/GR.7 三视图近似；外部挂载不并入机体网格",
			}
		"j20":
			record = _source_record("J-20", 456, "j20", "https://commons.wikimedia.org/wiki/File:Chengdu_J-20.svg",
				"CC BY-SA 3.0", "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"长尖鼻、前翼、宽菱形主翼、分离双发与外倾双垂尾",
				"按获审 J-20 三视图近似；前翼/尾喷口与 F-22/F-35 分别制作")
		"j35f":
			record = _source_record("J 35F", 260, "j35f", "https://commons.wikimedia.org/wiki/File:Saab_35_Draken_3-view_line_drawing.png",
				"public domain, US Army", "US Army; AGL simplified 3D reconstruction",
				"无平尾双三角翼、单发机身与高单垂尾",
				"按获审 Draken 顶视轮廓近似；保留内外翼两段不同后掠角")
		"j7":
			record = _source_record("J-7FS", 252, "j7", "https://commons.wikimedia.org/wiki/File:Chengdu_J-7FS_two-view_silhouette.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"机鼻进气、细长单发机身、小三角翼、低平尾与高单垂尾",
				"按获审 J-7FS 顶视轮廓近似；与 MiG-21F-13 独立制作")
		"jaguar":
			record = _source_record("Jaguar GR.1A", 412, "jaguar", "https://commons.wikimedia.org/wiki/File:SEPECAT_Jaguar_3-view_line_drawing.png",
				"public domain, US Army", "US Army; AGL simplified 3D reconstruction",
				"细长尖鼻、高置小后掠翼、两侧进气、双发尾段、低平尾与单垂尾",
				"按获审 Jaguar 三视图近似；外挂不并入机体网格")
		"mig21f13":
			record = _source_record("MiG-21F-13", 252, "mig21f13", "https://commons.wikimedia.org/wiki/File:Mikoyan_MiG-21F_and_MiG-21F-13.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"圆形机鼻进气、极细单发机身、小三角翼、低平尾与大单垂尾",
				"按获审 MiG-21F-13 顶视轮廓近似；不把显示中的导弹烘进机体")
		"mig23":
			record = _source_record("MiG-23", 276, "mig23", "https://commons.wikimedia.org/wiki/File:Mikoyan-Gurevich_I-21-11_(MiG-23)_five-view_silhouette.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"侧进气单发机身、固定展开可变后掠翼、低平尾与高单垂尾",
				"按获审展开翼顶视轮廓近似；当前不含变后掠动画")
		"mig31":
			record = _source_record("MiG-31", 424, "mig31", "https://commons.wikimedia.org/wiki/File:Mikoyan_MiG-31_3-view.svg",
				"CC BY-SA 3.0 / GFDL", "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"长双座鼻段、宽矩形进气、双发长机身、后掠翼、双垂尾与平尾",
				"按获审 MiG-31 三视图近似；高速截击机比例独立于 MiG-29")
		"mirage3":
			record = _source_record("Mirage III", 244, "mirage3", "https://commons.wikimedia.org/wiki/File:Dassault_Mirage_III_3-view_line_drawing.png",
				"public domain, US Army", "US Army; AGL simplified 3D reconstruction",
				"无平尾大三角翼、单发细长机身、两侧进气与高单垂尾",
				"按获审 Mirage III 三视图近似；不添加不存在的独立平尾")
		"mirage2000":
			record = _source_record("Mirage 2000", 252, "mirage2000", "https://commons.wikimedia.org/wiki/File:Mirage_2000C_3-view.gif",
				"reviewed orthographic source; license recorded at source page", "Reviewed Wikimedia three-view; AGL simplified 3D reconstruction",
				"无平尾裁角三角翼、单发机身、半圆侧进气与高单垂尾",
				"按获审 Mirage 2000C 三视图近似；翼根/进气与 Mirage III 独立")
		"q5":
			record = _source_record("Q-5I", 412, "q5", "https://commons.wikimedia.org/wiki/File:Nanchang_Q-5I_silhouette.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"尖鼻双侧进气、细长双发机身、后掠翼、平尾与单垂尾",
				"按获审 Q-5I 顶视轮廓近似；外挂不并入机体")
		"su34":
			record = _source_record("Su-34", 424, "su34", "https://commons.wikimedia.org/wiki/File:Sukhoi_Su-34.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"宽扁并列座舱鸭嘴鼻、长边条、宽翼、双发、双垂尾与尾梁",
				"按获审 Su-34 顶视轮廓近似；宽鼻区别于 Su-27 家族战斗型")
		"su47":
			record = _source_record("Su-47", 432, "su47", "https://commons.wikimedia.org/wiki/File:Sukhoi_Su-47_Berkut_top-view_silhouette.png",
				"public domain", "Greg Goebel; AGL simplified 3D reconstruction",
				"前翼、前掠主翼、双发机身、双垂尾与尾梁",
				"按获审 Su-47 顶视轮廓近似；前掠翼是独立网格的主特征")
		"su57":
			record = _source_record("Su-57", 432, "su57", "https://commons.wikimedia.org/wiki/File:Sukhoi_T-50_3-view.svg",
				"CC BY-SA 3.0", "XaHyMaH; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"宽扁折面鼻、长边条、宽梯形翼、分离双发、尾梁与外倾双垂尾",
				"按获审 T-50 三视图近似；不复用 Su-27 曲面或 F-22 几何")
		"tornado":
			record = _source_record("Tornado IDS", 404, "tornado", "https://commons.wikimedia.org/wiki/File:Panavia_Tornado_IDS_3-view_line_drawing.svg",
				"public domain dedication", "A. Khaustova and Flappiefh; AGL simplified 3D reconstruction",
				"长双座鼻、箱形双进气、固定展开可变后掠翼、双发尾段与单垂尾",
				"按获审展开翼三视图近似；当前不含变后掠动画")
		"viggen":
			record = _source_record("AJ 37 Viggen", 276, "viggen", "https://commons.wikimedia.org/wiki/File:Saab_J_37_Viggen_3-view.svg",
				"reviewed orthographic source; license recorded at source page", "Reviewed Wikimedia three-view; AGL simplified 3D reconstruction",
				"大三角前翼、主三角翼、粗单发机身、两侧进气与单垂尾",
				"按获审 Viggen 三视图近似；前翼更大且远离主翼，不套用 Gripen")
		"a12":
			record = {
				"name": "A-12 Avenger II", "triangles": 216,
				"source": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_url": "https://commons.wikimedia.org/wiki/File:A-12_Avenger_comparative_aircraft_size_NAN11-90.jpg",
				"source_license": "project concept reconstruction from published planform only",
				"attribution": "AGL project-authored interpretation; no final real aircraft existed",
				"shape": "宽三角飞翼、埋入式双发尾部、低矮驾驶舱与无垂尾后缘",
				"fidelity": "已取消纸面方案缺少确定最终三视图；只沿用公开平面概念，不声称工程写实",
			}
		"ah64":
			record = _source_record("AH-64 Apache", 516, "ah64", "https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_AH-64_Apache_3-view_line_drawing.png",
				"public domain, US Army", "US Army drawing; AGL simplified 3D reconstruction",
				"纵列座舱、机鼻传感器球、短翼挂架、双发动机舱、细尾梁、主旋翼与尾桨",
				"按公版美军三视图和项目旋翼机 spec 近似；旋翼在几何批只用于四视图辨识，正式运行时动画另行验收")
		"ch47":
			record = _source_record("CH-47 Chinook", 308, "ch47", "https://commons.wikimedia.org/wiki/File:Boeing_Vertol_CH-47_Chinook_3-view_line_drawing.png",
				"public domain, US Army", "US Army drawing; AGL simplified 3D reconstruction",
				"长箱形货舱、斜鼻驾驶舱、两侧浮筒、前后旋翼塔与重叠反转双旋翼",
				"按公版美军三视图和项目旋翼机 spec 近似；不把双旋翼运输机套成固定翼机身")
		"mq109_family":
			record = _source_record("MQ-109 / MQ-110 / MQ-111", 260, "mq109_family", "",
				"user-provided reference retained in project manifest", "User-provided approved top view; AGL simplified 3D reconstruction",
				"短钝无座舱机鼻、宽后掠飞翼、中央传感器脊、双尾喷口与浅 V 尾",
				"按用户批准的家族顶视轮廓制作；三种武器型共享机体但武器挂载须由运行时状态区分")
		"mq112":
			record = {
				"name": "MQ-112", "triangles": 268,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_aircraft_icon / railgun telegraph",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "长尖无人机机身、窄菱翼、背部传感器脊、腹部纵向电磁炮槽与分离双尾",
				"fidelity": "按项目 MQ-112 机头直射电磁炮职责原创；不声称现实原型，也不复用 MQ-109 家族网格",
			}
		"mqx":
			record = {
				"name": "MQ-X", "triangles": 368,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_drone_icon",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "宽扁隐身菱翼、中央无座舱脊、双内埋发动机、锯齿后缘与外倾 V 尾",
				"fidelity": "按项目最强档无人战斗机职责原创；与忠诚僚机、Aegis 和蜂群无人机分别制作",
			}
		"aegis_uav":
			record = {
				"name": "Aegis UAV", "triangles": 248,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_aircraft_icon / laser interceptor role",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "六边形飞翼、中央光电塔、翼端传感器与无尾拦截器机体",
				"fidelity": "按项目专职反导激光定位原创；武器光束不是静态机体几何",
			}
		"loyal_wingman":
			record = {
				"name": "Loyal Wingman", "triangles": 280,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_drone_icon",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "XQ-58/MQ-28 语汇的细长尖鼻、极后掠翼、背部进气与外倾 V 尾",
				"fidelity": "沿用项目已批准忠诚僚机视觉语汇原创；不复制任何现实三维资产",
			}
		"probe":
			record = {
				"name": "Probe", "triangles": 260,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_aircraft_icon / Probe debug spawn",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "圆钝传感器鼻、短机身、直板稳定翼、环形背部传感器与无武器尾段",
				"fidelity": "按项目调试 Probe 的非武装身份原创；不借用战斗无人机尖角轮廓",
			}
		"faxx":
			record = {
				"name": "F/A-XX", "triangles": 392,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T4 F/A-XX attack branch",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "舰载无尾菱翼、折线翼尖、双内埋发动机与低可视特征后缘",
				"fidelity": "项目原创六代舰载攻击机解释，不声称复现尚未定型的现实项目外形",
			}
		"fcas":
			record = {
				"name": "FCAS NGF", "triangles": 260,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T4 FCAS electronic-warfare branch",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "无尾宽体折线三角翼、连续翼身融合、双腹进气与背部作战云节点",
				"fidelity": "项目原创作战云载机解释；不复制厂商渲染，也不宣称现实工程定型",
			}
		"gcap":
			record = {
				"name": "GCAP Tempest", "triangles": 384,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T4 GCAP long-range branch",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "宽肩三角翼、长航程双发机身、后置梯形翼面与外倾双垂尾",
				"fidelity": "项目原创远程六代机解释；只服从现有身份与角色，不冒充现实 Tempest 三维数据",
			}
		"j36":
			record = {
				"name": "J-36", "triangles": 296,
				"source": "res://docs/specs/systems/aircraft-signature-skills.md", "source_symbol": "sig_j36 triple-thrust assault",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "无尾宽菱翼、三条独立尾喷口、长机鼻与锯齿后缘",
				"fidelity": "按项目三发推力身份制作的原创解释；不把网络猜测轮廓当作确定现实三视图",
			}
		"mig41":
			record = {
				"name": "MiG-41 PAK DP", "triangles": 440,
				"source": "res://docs/specs/systems/aircraft-signature-skills.md", "source_symbol": "sig_mig41 near-space sprint",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "极长截击机鼻、窄短主翼、双发长舱、双垂尾与近太空高速机腹",
				"fidelity": "按项目近太空截击定位原创；不声称尚未公开定型的现实 MiG-41 外形",
			}
		"af03":
			record = {
				"name": "AF-03", "triangles": 384,
				"source": "res://resources/enemy_af03.tres", "source_symbol": "railgun equipment and project identity",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "双发试验机身、窄菱翼、腹部纵向电磁炮、双垂尾与长射界机鼻",
				"fidelity": "按正式电磁炮试验机职责原创；与 MQ-112 的无人狙击体型分别制作",
			}
		"ax00":
			record = {
				"name": "AX-00 Starweaver", "triangles": 404,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 all-route legendary apex",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "星形双菱翼、前置控制面、双发矢量尾段、外倾鳍与中央能量脊",
				"fidelity": "按项目多路线传说顶点原创；不复用任何 T4 六代机网格",
			}
		"orion_final_form", "orion_fang":
			record = {
				"name": "ORION" if kind == "orion_final_form" else "FANG",
				"triangles": 344 if kind == "orion_final_form" else 180,
				"source": "res://docs/specs/bosses/orion-final-form.md",
				"source_symbol": "ORION final form and FANG concept",
				"source_license": "AGL project-authored concept geometry",
				"attribution": "AGL project concept",
				"shape": "大型前掠翼与双轨炮本体 / 小型折线翼光剑护卫",
				"fidelity": "按用户 BOSS 设计原创；待多视图与正式实战验收",
			}
		"cre":
			record = {
				"name": "Cre", "triangles": 304,
				"source": "res://resources/enemy_cre.tres", "source_symbol": "project-authored ace identity",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "前翼式长鼻、宽后掠主翼、单发脊背与分叉尾平面",
				"fidelity": "按项目既有橙色王牌身份原创；无现实型号声明",
			}
		"deadair":
			record = {
				"name": "DEADAIR", "triangles": 244,
				"source": "res://docs/specs/enemies/deadair.md", "source_symbol": "mobile JAM support core",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "双菱形电子战核心、短机身、宽后掠翼、三节点干扰阵列与无武装尾段",
				"fidelity": "沿用正式 DEADAIR 双菱形 renderer 与支援机职责原创；不借用 Snowblind 或 Sentinel 网格",
			}
		"sentinel":
			record = {
				"name": "Sentinel", "triangles": 252,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_commander_icon",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "宽扁 V 形指挥飞翼、中央传感器脊、翼尖通信舱与外倾稳定鳍",
				"fidelity": "按项目指挥 UAV 专用 renderer 制作；普通 Sentinel 与 Sentinel X 共享机体，后者只由正式缩放区分",
			}
		"snowblind":
			record = {
				"name": "Snowblind", "triangles": 272,
				"source": "res://docs/specs/enemies/snowblind.md", "source_symbol": "independent non-combat shroud support airframe",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "雪晶折线翼、中央遮蔽发生器、四向场导体、双后置动力舱与单垂尾",
				"fidelity": "按正式雪幕支援职责原创；数值可复用 Sentinel 基线但几何不复用",
			}
		"hyper_a":
			record = {
				"name": "Hyper-A G0-G3", "triangles": 148,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_hyper_a_icon",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept inspired by lifting-body vocabulary",
				"shape": "低矮细长楔形升力体、银色前缘、腹部热防护脊与单一尾喷口",
				"fidelity": "按项目 Black Star 专用 renderer 重建；四代仅改变正式尺寸与战斗阶段，共用同一机体结构",
			}
		"mother_goose":
			record = {
				"name": "Mother Goose", "triangles": 328,
				"source": "res://scripts/aircraft_renderer.gd", "source_symbol": "draw_mother_goose_icon",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "446 像素级巨型 V 形飞翼、中央船桥、六发动机舱、尾部八挂点带与双 VLS 甲板",
				"fidelity": "按项目空中航母正式轮廓与现有挂点坐标重建；挂点/螺旋桨/VLS 仍由独立运行时状态几何承担",
			}
		"x02":
			record = {
				"name": "X-02 Wyvern", "triangles": 404,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 omni Wyvern",
				"source_license": "AGL project-authored gameplay reconstruction", "attribution": "AGL project implementation",
				"shape": "翼龙式前置控制面、可变语汇后掠翼、双发尾段、双垂尾与腹部电磁炮",
				"fidelity": "按项目 X-02 身份和正式武器职责制作的低模解释；不复制第三方游戏三维资产",
			}
		"x09":
			record = {
				"name": "X-09 Thunder Owl", "triangles": 260,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 tailless air-superiority fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "鸮翼无尾飞翼、四向矢量喷口、中央脊背与双腹稳定鳍",
				"fidelity": "按项目无尾飞翼和全向矢量幻想原创；不复用 Sentinel 指挥飞翼",
			}
		"x13":
			record = {
				"name": "X-13 Skyfalcon", "triangles": 428,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 electronic-dominance fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "前翼三角布局、双发隐身机身、翼尖全频段舱、双垂尾与中央电子战脊",
				"fidelity": "按项目自适应隐身与电子统御定位原创；不复用 FCAS 作战云机体",
			}
		"x21":
			record = {
				"name": "X-21 Longreach", "triangles": 424,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 long-range interceptor fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "极长截击机身、窄折线主翼、双发长舱、双尾与两条远程弹舱",
				"fidelity": "按项目超高速超远程弹库定位原创；不复用 MiG-41 机体",
			}
		"x44":
			record = {
				"name": "X-44 Anvil", "triangles": 460,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 armored gunship fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "宽厚装甲机身、近直重载翼、双大发动机舱、双垂尾与三向机炮座",
				"fidelity": "按项目重装甲全向弹幕移动堡垒定位原创；炮口为机体辨识，射界仍由正式武器状态控制",
			}
		"x77":
			record = {
				"name": "X-77 Phantom Raven", "triangles": 376,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 optical-cloak infiltrator fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "渡鸦式深后掠折线翼、扁平双发舱、锯齿后缘、低矮双鳍与无外露挂架",
				"fidelity": "按项目光学迷彩无声渗透定位原创；不复用 YF-23 或 X-09 飞翼",
			}
		"x90":
			record = {
				"name": "X-90 Skywhale", "triangles": 388,
				"source": "res://docs/specs/systems/aircraft-evolution-tree.md", "source_symbol": "T5 airborne-carrier fantasy",
				"source_license": "AGL project-authored concept geometry", "attribution": "AGL project concept",
				"shape": "宽体空中母舰、厚翼身融合、四发动机、腹部六格无人机舱与双外倾尾鳍",
				"fidelity": "按项目鲸群和忠诚僚机母舰定位原创；不缩小复用 Mother Goose 巨型 BOSS 网格",
			}
		_:
			return {}
	record["key"] = kind
	record["triangle_budget"] = TRIANGLE_BUDGET
	record["surface_count"] = 1
	record["material_count"] = 1
	record["native_max_extent"] = 34.0
	match kind:
		"f14":
			record["native_span"] = 34.0
			record["native_length"] = 33.7
		"a10":
			record["native_span"] = 34.0
			record["native_length"] = 30.0
		"f47":
			record["native_span"] = 34.0
			record["native_length"] = 32.8
		"f104":
			record["native_span"] = 13.6
			record["native_length"] = 34.0
		"f15":
			record["native_span"] = 22.6
			record["native_length"] = 34.0
		"f16":
			record["native_span"] = 22.5
			record["native_length"] = 34.0
		"f22":
			record["native_span"] = 24.4
			record["native_length"] = 34.0
		"f35":
			record["native_span"] = 23.2
			record["native_length"] = 34.0
		"yf23":
			record["native_span"] = 22.0
			record["native_length"] = 34.0
		"tu160", "b1b":
			record["native_span"] = 28.0
			record["native_length"] = 34.0
		"f4":
			record["native_span"] = 20.7
			record["native_length"] = 34.0
		"f86":
			record["native_span"] = 33.7
			record["native_length"] = 34.0
		"f100":
			record["native_span"] = 26.4
			record["native_length"] = 34.0
		"fa18":
			record["native_span"] = 24.5
			record["native_length"] = 34.0
		"mig29":
			record["native_span"] = 22.3
			record["native_length"] = 34.0
		"su27":
			record["native_span"] = 22.8
			record["native_length"] = 34.0
		"rafale":
			record["native_span"] = 24.3
			record["native_length"] = 34.0
		"typhoon":
			record["native_span"] = 23.3
			record["native_length"] = 34.0
		"a6e":
			record["native_span"] = 32.9
			record["native_length"] = 34.0
		"a7":
			record["native_span"] = 28.5
			record["native_length"] = 34.0
		"ea6b":
			record["native_span"] = 31.0
			record["native_length"] = 34.0
		"f15smtd":
			record["native_span"] = 22.6
			record["native_length"] = 34.0
		"fa18e":
			record["native_span"] = 25.3
			record["native_length"] = 34.0
		"fck1":
			record["native_span"] = 22.6
			record["native_length"] = 34.0
		"gripen":
			record["native_span"] = 20.3
			record["native_length"] = 34.0
		"harrier":
			record["native_span"] = 18.6
			record["native_length"] = 34.0
		"j20":
			record["native_span"] = 22.6
			record["native_length"] = 34.0
		"j35f":
			record["native_span"] = 20.9
			record["native_length"] = 34.0
		"j7":
			record["native_span"] = 16.3
			record["native_length"] = 34.0
		"jaguar":
			record["native_span"] = 17.6
			record["native_length"] = 34.0
		"mig21f13":
			record["native_span"] = 15.4
			record["native_length"] = 34.0
		"mig23":
			record["native_span"] = 28.4
			record["native_length"] = 34.0
		"mig31":
			record["native_span"] = 20.2
			record["native_length"] = 34.0
		"mirage3":
			record["native_span"] = 18.6
			record["native_length"] = 34.0
		"mirage2000":
			record["native_span"] = 21.6
			record["native_length"] = 34.0
		"q5":
			record["native_span"] = 21.0
			record["native_length"] = 34.0
		"su34":
			record["native_span"] = 21.4
			record["native_length"] = 34.0
		"su47":
			record["native_span"] = 25.1
			record["native_length"] = 34.0
		"su57":
			record["native_span"] = 23.8
			record["native_length"] = 34.0
		"tornado":
			record["native_span"] = 28.3
			record["native_length"] = 34.0
		"viggen":
			record["native_span"] = 22.0
			record["native_length"] = 34.0
		"a12":
			record["native_span"] = 34.0
			record["native_length"] = 30.2
		"ah64":
			record["native_span"] = 32.0
			record["native_length"] = 32.0
		"ch47":
			record["native_span"] = 26.75
			record["native_length"] = 44.0
		"mq109_family":
			record["native_span"] = 30.0
			record["native_length"] = 34.0
		"mq112":
			record["native_span"] = 18.0
			record["native_length"] = 34.0
		"mqx":
			record["native_span"] = 34.0
			record["native_length"] = 31.0
		"aegis_uav":
			record["native_span"] = 34.0
			record["native_length"] = 24.0
		"loyal_wingman":
			record["native_span"] = 26.0
			record["native_length"] = 34.0
		"probe":
			record["native_span"] = 22.0
			record["native_length"] = 30.0
		"faxx":
			record["native_span"] = 34.0
			record["native_length"] = 32.0
		"fcas":
			record["native_span"] = 34.0
			record["native_length"] = 30.0
		"gcap":
			record["native_span"] = 32.0
			record["native_length"] = 34.0
		"j36":
			record["native_span"] = 34.0
			record["native_length"] = 33.0
		"mig41":
			record["native_span"] = 20.0
			record["native_length"] = 34.0
		"af03":
			record["native_span"] = 22.0
			record["native_length"] = 34.0
		"ax00":
			record["native_span"] = 34.0
			record["native_length"] = 34.0
		"cre":
			record["native_span"] = 28.0
			record["native_length"] = 34.0
		"orion_final_form":
			record["native_span"] = 44.0
			record["native_length"] = 36.0
		"orion_fang":
			record["native_span"] = 18.0
			record["native_length"] = 14.0
		"deadair":
			record["native_span"] = 34.0
			record["native_length"] = 30.0
		"sentinel":
			record["native_span"] = 34.0
			record["native_length"] = 30.0
		"snowblind":
			record["native_span"] = 34.0
			record["native_length"] = 32.0
		"hyper_a":
			record["native_span"] = 20.0
			record["native_length"] = 34.0
		"mother_goose":
			record["native_span"] = 446.4
			record["native_length"] = 144.0
		"x02":
			record["native_span"] = 34.0
			record["native_length"] = 34.0
		"x09":
			record["native_span"] = 34.0
			record["native_length"] = 30.0
		"x13":
			record["native_span"] = 32.0
			record["native_length"] = 34.0
		"x21":
			record["native_span"] = 18.0
			record["native_length"] = 34.0
		"x44":
			record["native_span"] = 34.0
			record["native_length"] = 32.0
		"x77":
			record["native_span"] = 34.0
			record["native_length"] = 31.0
		"x90":
			record["native_span"] = 34.0
			record["native_length"] = 34.0
	record["native_max_extent"] = maxf(float(record["native_span"]), float(record["native_length"]))
	record["forward"] = Vector3.FORWARD
	if kind in ["f14", "a10", "f47"]:
		record["production_batch"] = "A"
	elif kind in ["f104", "f15"]:
		record["production_batch"] = "B"
	elif kind in ["f16", "f22", "f35"]:
		record["production_batch"] = "C"
	elif kind in ["yf23", "tu160", "b1b"]:
		record["production_batch"] = "D"
	elif kind in ["f4", "f86", "f100", "fa18", "mig29", "su27", "rafale", "typhoon"]:
		record["production_batch"] = "E"
	elif kind in ["a6e", "a7", "ea6b", "f15smtd", "fa18e", "fck1", "gripen", "harrier"]:
		record["production_batch"] = "F"
	elif kind in ["j20", "j35f", "j7", "jaguar", "mig21f13", "mig23", "mig31", "mirage3"]:
		record["production_batch"] = "G"
	elif kind in ["mirage2000", "q5", "su34", "su47", "su57", "tornado", "viggen", "a12"]:
		record["production_batch"] = "H"
	elif kind in ["ah64", "ch47", "mq109_family", "mq112", "mqx", "aegis_uav", "loyal_wingman", "probe"]:
		record["production_batch"] = "I"
	elif kind in ["faxx", "fcas", "gcap", "j36", "mig41", "af03", "ax00", "cre"]:
		record["production_batch"] = "J"
	elif kind in ["deadair", "sentinel", "snowblind", "hyper_a", "mother_goose", "x02", "x09", "x13"]:
		record["production_batch"] = "K"
	else:
		record["production_batch"] = "L"
	record["status"] = "multiview_runtime_qa_complete_formal_pending"
	if kind in ["orion_final_form", "orion_fang"]:
		record["status"] = "implementation_pending_visual_qa"
	record["editable_source"] = "res://scripts/experiments/volume_aircraft_catalog.gd"
	return record


static func _source_record(name: String, triangles: int, source_key: String, source_url: String,
		license: String, attribution: String, shape: String, fidelity: String) -> Dictionary:
	return {
		"name": name, "triangles": triangles,
		"source": "res://resources/aircraft_silhouettes/%s_detail.png" % source_key,
		"source_url": source_url,
		"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
		"source_license": license, "attribution": attribution,
		"shape": shape, "fidelity": fidelity,
	}


static func _build_f14(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12, 1.05, 1),
		Vector3(-6, 1.65, 1.5), Vector3(-1, 2.9, 1.65), Vector3(8, 3.25, 1.2),
		Vector3(14, 2.35, 0.9), Vector3(16.7, 0.16, 0.14)], BODY)
	_closed_loft(builder, Vector3(0, 1.3, -8), [Vector3(-4.2, 0.07, 0.07),
		Vector3(-2, 1.05, 1), Vector3(1.5, 1.08, 1.1), Vector3(4, 0.2, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -1), Vector2(5.6, 1.7), Vector2(17, 6.8),
			Vector2(16.9, 8.3), Vector2(3.1, 7.2)], side, -0.3, 0.3, BODY)
		_planform(builder, [Vector2(1.8, -5.2), Vector2(4.1, -4.6), Vector2(5.7, 1.7),
			Vector2(3.4, 7.9), Vector2(2.8, 7.3), Vector2(2.1, -1)], side, -0.6, 0.65, BODY)
		_planform(builder, [Vector2(2, 10), Vector2(3.7, 9.8), Vector2(10, 14.8),
			Vector2(9.4, 16.5), Vector2(2.2, 14)], side, -0.1, 0.45, BODY)
		_closed_loft(builder, Vector3(2.85 * side, -0.15, 5),
			[Vector3(-9, 0.9, 0.85), Vector3(-6, 1.2, 1.05),
			Vector3(8, 1.2, 1), Vector3(11.5, 0.8, 0.8)], ENGINE, INTAKE, INTAKE)
		_fin(builder, 3 * side, [Vector2(8.5, 0.5), Vector2(10, 5.4),
			Vector2(12.5, 5), Vector2(15.2, 0.5)], 0.225, side * 0.13, BODY)


static func _build_a10(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, 0.13, 0.14), Vector3(-13, 1.4, 1.35),
		Vector3(-6, 1.6, 1.65), Vector3(4, 1.8, 1.8), Vector3(11.5, 1.2, 1.4),
		Vector3(15, 0.2, 0.15)], BODY)
	_closed_loft(builder, Vector3(0, 1.45, -8), [Vector3(-3, 0.08, 0.08),
		Vector3(-1.5, 1.15, 1.2), Vector3(1.3, 1.05, 1.1), Vector3(3, 0.15, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.1, -2.6), Vector2(8, -3), Vector2(17, -1.9),
			Vector2(17, 1.3), Vector2(15.5, 2.2), Vector2(1.5, 3.1)], side, -0.45, 0.2, BODY)
		_closed_loft(builder, Vector3(4.2 * side, 2.2, 6), [Vector3(-3, 0.95, 1.1),
			Vector3(-2, 1.4, 1.55), Vector3(3.5, 1.4, 1.55), Vector3(4.5, 1.1, 1.2)],
			BODY, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, 1.25, 6), Vector3(2.5, 0.55, 3.5), ENGINE)
		_planform(builder, [Vector2(1, 11.6), Vector2(6.5, 11.3),
			Vector2(6.5, 14.8), Vector2(1, 14.8)], side, 0.4, 0.95, BODY)
		_fin(builder, 6.3 * side, [Vector2(10.8, 0.7), Vector2(11.5, 4),
			Vector2(14.5, 3.7), Vector2(15, 0.7)], 0.2, 0.0, BODY)
	# 中央简化炮口只作识别特征，不是武器/发射点权威。
	builder.box(Vector3(0, -0.9, -13.3), Vector3(0.45, 0.4, 2.4), INTAKE)


static func _build_f47(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.05, 0.05), Vector3(-10, 2.1, 1),
		Vector3(-4.6, 4.1, 1.65), Vector3(4, 4.3, 1.55), Vector3(12, 3.3, 1.05),
		Vector3(15.8, 0.12, 0.12)], BODY)
	_closed_loft(builder, Vector3(0, 1.3, -8), [Vector3(-3.8, 0.06, 0.06),
		Vector3(-1.8, 1.35, 0.9), Vector3(1.6, 1.25, 0.85), Vector3(3.8, 0.12, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(3.2, -4), Vector2(17, 4.5),
			Vector2(8.8, 8.3), Vector2(3.5, 5.1)], side, -0.25, 0.3, BODY)
		_planform(builder, [Vector2(1.6, -10), Vector2(4.3, -4.5), Vector2(5.8, 1.1),
			Vector2(3, 4), Vector2(2, -4)], side, -0.45, 0.45, BODY)
		_closed_loft(builder, Vector3(2.6 * side, -0.2, 7), [Vector3(-5, 1.35, 0.9),
			Vector3(-2, 1.6, 0.85), Vector3(6.5, 1.45, 0.65), Vector3(8.4, 1.3, 0.5)],
			ENGINE, INTAKE, INTAKE)
		_planform(builder, [Vector2(2.4, 8.8), Vector2(8.8, 12),
			Vector2(7.2, 13.6), Vector2(2.88, 12.8)], side, 0.1, 0.55, BODY)
		_fin(builder, 3.7 * side, [Vector2(7.6, 0.8), Vector2(10, 4.4),
			Vector2(12, 4), Vector2(14.2, 0.5)], 0.18, side * 0.35, BODY)
		builder.box(Vector3(3 * side, -0.15, -2.5), Vector3(2, 0.85, 2.5), INTAKE)


## F-104C：长度为最大尺度，翼展按 6.68m / 16.69m 比例保留，不能把窄翼放大成普通战斗机。
static func _build_f104(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-13, 0.72, 0.68),
		Vector3(-7, 1.05, 1.05), Vector3(0, 1.15, 1.20), Vector3(8, 1.02, 1.05),
		Vector3(14.5, 0.82, 0.86), Vector3(17, 0.35, 0.42)], BODY)
	_closed_loft(builder, Vector3(0, 1.0, -9.2), [Vector3(-3.5, 0.05, 0.05),
		Vector3(-1.8, 0.72, 0.76), Vector3(1.4, 0.68, 0.70), Vector3(3.2, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(0.9, -2.4), Vector2(6.8, -0.9), Vector2(6.45, 2.0),
			Vector2(1.0, 3.1), Vector2(0.72, -0.4)], side, -0.22, 0.20, BODY)
		_planform(builder, [Vector2(0.72, 10.8), Vector2(3.55, 12.0),
			Vector2(3.25, 14.4), Vector2(0.70, 13.6)], side, -0.10, 0.24, BODY)
		_closed_loft(builder, Vector3(1.28 * side, -0.12, -0.5), [Vector3(-2.5, 0.06, 0.06),
			Vector3(-1.3, 0.48, 0.40), Vector3(1.4, 0.42, 0.36), Vector3(2.5, 0.08, 0.08)],
			ENGINE, INTAKE, ENGINE)
	_fin(builder, 0.0, [Vector2(8.2, 0.45), Vector2(10.2, 6.8),
		Vector2(14.8, 6.1), Vector2(16.4, 0.42)], 0.23, 0.0, BODY)


## F-15：翼展按 13.05m / 19.43m 比例保留；双发、进气和双垂尾均为分离结构。
static func _build_f15(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12, 0.95, 0.85),
		Vector3(-6, 1.55, 1.38), Vector3(0, 2.15, 1.52), Vector3(8, 2.3, 1.35),
		Vector3(14, 1.72, 0.92), Vector3(17, 0.30, 0.28)], BODY)
	_closed_loft(builder, Vector3(0, 1.32, -8.3), [Vector3(-3.5, 0.06, 0.06),
		Vector3(-1.7, 0.88, 0.92), Vector3(1.5, 0.92, 0.86), Vector3(3.4, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -2.8), Vector2(3.8, -2.4), Vector2(11.3, 2.8),
			Vector2(10.8, 7.1), Vector2(2.1, 7.8)], side, -0.34, 0.30, BODY)
		_planform(builder, [Vector2(1.15, -7.8), Vector2(2.3, -6.0), Vector2(3.9, -2.2),
			Vector2(2.1, 1.8), Vector2(1.25, -1.2)], side, -0.42, 0.42, BODY)
		_planform(builder, [Vector2(1.55, 9.5), Vector2(3.2, 9.2), Vector2(7.1, 12.9),
			Vector2(6.7, 15.1), Vector2(1.7, 13.7)], side, -0.10, 0.32, BODY)
		_closed_loft(builder, Vector3(2.65 * side, -0.18, 4.0), [Vector3(-7.0, 0.72, 0.72),
			Vector3(-4.7, 1.2, 1.05), Vector3(8.2, 1.24, 1.05), Vector3(11.7, 0.88, 0.78)],
			ENGINE, INTAKE, ENGINE)
		builder.box(Vector3(2.9 * side, -0.08, -2.6), Vector3(1.55, 1.05, 3.2), INTAKE)
		_fin(builder, 2.85 * side, [Vector2(7.6, 0.5), Vector2(9.2, 5.6),
			Vector2(12.0, 5.1), Vector2(14.6, 0.45)], 0.20, side * 0.16, BODY)


## F-16C：翼展按 9.96m / 15.06m 比例保留；单发、腹部进气与单垂尾是独立结构。
static func _build_f16(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.5, 0.72, 0.68),
		Vector3(-7.0, 1.35, 1.18), Vector3(0.0, 1.72, 1.45), Vector3(8.0, 1.58, 1.30),
		Vector3(14.0, 1.02, 0.92), Vector3(17.0, 0.38, 0.42)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.22, -8.2), [Vector3(-3.4, 0.06, 0.06),
		Vector3(-1.6, 0.82, 0.72), Vector3(1.5, 0.84, 0.75), Vector3(3.2, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.45, -3.0), Vector2(3.9, -2.1), Vector2(11.25, 1.8),
			Vector2(10.9, 4.9), Vector2(1.8, 6.0)], side, -0.27, 0.25, BODY)
		_planform(builder, [Vector2(1.15, -8.0), Vector2(2.4, -6.5), Vector2(4.0, -2.0),
			Vector2(2.0, 0.2), Vector2(1.2, -2.0)], side, -0.34, 0.38, BODY)
		_planform(builder, [Vector2(0.95, 9.7), Vector2(2.4, 9.4), Vector2(5.5, 12.5),
			Vector2(5.15, 14.8), Vector2(1.0, 13.7)], side, -0.10, 0.25, BODY)
		builder.box(Vector3(11.0 * side, 0.0, 1.5), Vector3(0.25, 0.35, 3.0), ENGINE)
	builder.box(Vector3(0, -1.18, -4.9), Vector3(1.8, 0.82, 3.0), INTAKE)
	_fin(builder, 0.0, [Vector2(7.4, 0.52), Vector2(9.0, 5.5),
		Vector2(12.1, 5.0), Vector2(14.7, 0.45)], 0.22, 0.0, BODY)


## F-22A：翼展按 13.56m / 18.92m 比例保留；宽扁机身和双发舱不是 F-15 套壳。
static func _build_f22(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.05), Vector3(-12.0, 1.35, 0.62),
		Vector3(-7.0, 3.15, 1.10), Vector3(0.0, 4.15, 1.42), Vector3(8.0, 3.9, 1.25),
		Vector3(14.0, 2.65, 0.88), Vector3(17.0, 0.45, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.22, -8.2), [Vector3(-3.2, 0.06, 0.05),
		Vector3(-1.5, 0.96, 0.63), Vector3(1.5, 1.02, 0.66), Vector3(3.0, 0.10, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.7, -5.2), Vector2(5.8, -3.1), Vector2(12.2, 4.7),
			Vector2(11.7, 7.4), Vector2(6.2, 8.5), Vector2(3.1, 5.3)], side, -0.30, 0.28, BODY)
		_planform(builder, [Vector2(1.35, -11.5), Vector2(2.7, -8.0), Vector2(5.8, -3.1),
			Vector2(3.6, 1.0), Vector2(1.75, -3.7)], side, -0.38, 0.38, BODY)
		_planform(builder, [Vector2(2.6, 8.8), Vector2(4.3, 8.6), Vector2(8.2, 12.1),
			Vector2(7.5, 15.0), Vector2(2.8, 13.5)], side, -0.10, 0.30, BODY)
		_closed_loft(builder, Vector3(2.45 * side, -0.20, 5.0), [Vector3(-6.0, 1.05, 0.72),
			Vector3(-3.7, 1.38, 0.84), Vector3(7.0, 1.30, 0.68), Vector3(10.4, 0.82, 0.52)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(3.1 * side, -0.20, -2.8), Vector3(1.9, 0.90, 3.0), INTAKE)
		_fin(builder, 3.15 * side, [Vector2(7.1, 0.45), Vector2(9.2, 5.0),
			Vector2(12.2, 4.4), Vector2(14.3, 0.38)], 0.18, side * 0.28, BODY)


## F-35A：翼展按 10.7m / 15.7m 比例保留；单喷口、厚机背和两侧进气区别于 F-22。
static func _build_f35(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.2, 1.08, 0.76),
		Vector3(-6.8, 2.25, 1.48), Vector3(0.0, 2.75, 1.82), Vector3(8.0, 2.48, 1.58),
		Vector3(14.2, 1.55, 1.08), Vector3(17.0, 0.52, 0.48)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.60, -7.9), [Vector3(-3.0, 0.06, 0.06),
		Vector3(-1.3, 0.92, 0.62), Vector3(1.5, 0.98, 0.68), Vector3(3.0, 0.10, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -3.5), Vector2(4.0, -2.4), Vector2(11.6, 3.7),
			Vector2(11.5, 6.5), Vector2(5.3, 7.8), Vector2(2.5, 4.3)], side, -0.32, 0.30, BODY)
		_planform(builder, [Vector2(1.1, -9.8), Vector2(2.3, -7.2), Vector2(4.0, -2.4),
			Vector2(2.6, 1.0), Vector2(1.35, -3.0)], side, -0.38, 0.42, BODY)
		_planform(builder, [Vector2(1.9, 8.7), Vector2(3.2, 8.5), Vector2(6.3, 11.5),
			Vector2(5.9, 14.5), Vector2(2.0, 13.0)], side, -0.12, 0.28, BODY)
		builder.box(Vector3(2.3 * side, -0.12, -2.7), Vector3(1.35, 1.05, 3.0), INTAKE)
		_fin(builder, 2.45 * side, [Vector2(7.2, 0.55), Vector2(9.0, 4.7),
			Vector2(11.6, 4.3), Vector2(13.8, 0.45)], 0.18, side * 0.26, BODY)


## YF-23：无独立平尾，长菱形翼与后部 V 尾共同构成独立轮廓。
static func _build_yf23(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.05), Vector3(-12.0, 1.45, 0.62),
		Vector3(-6.5, 3.35, 1.05), Vector3(0.0, 4.0, 1.32), Vector3(8.0, 3.65, 1.10),
		Vector3(14.5, 2.25, 0.70), Vector3(17.0, 0.38, 0.25)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.15, -8.4), [Vector3(-3.0, 0.05, 0.05),
		Vector3(-1.4, 0.88, 0.58), Vector3(1.5, 0.92, 0.60), Vector3(3.0, 0.08, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -5.0), Vector2(5.5, -2.7), Vector2(11.0, 5.2),
			Vector2(9.0, 10.2), Vector2(5.0, 7.6), Vector2(2.6, 2.0)], side, -0.28, 0.26, BODY)
		_planform(builder, [Vector2(1.25, -11.4), Vector2(2.7, -7.7), Vector2(5.5, -2.7),
			Vector2(3.5, 1.4), Vector2(1.7, -3.8)], side, -0.36, 0.36, BODY)
		_planform(builder, [Vector2(2.1, 2.0), Vector2(4.9, 1.2), Vector2(6.4, 8.3),
			Vector2(3.4, 12.0), Vector2(2.0, 8.0)], side, 0.12, 0.52, BODY)
		_closed_loft(builder, Vector3(2.45 * side, -0.22, 5.0), [Vector3(-6.0, 1.0, 0.68),
			Vector3(-3.8, 1.36, 0.80), Vector3(7.2, 1.30, 0.62), Vector3(10.5, 0.72, 0.42)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(3.0 * side, -0.18, -2.7), Vector3(1.8, 0.82, 3.1), INTAKE)
		_fin(builder, 3.0 * side, [Vector2(7.0, 0.40), Vector2(9.6, 4.7),
			Vector2(13.0, 3.8), Vector2(15.0, 0.34)], 0.17, side * 0.48, BODY)


## Tu-160：四发长航程轰炸机；本体尺寸由 AircraftParams 再按真实 visual_size_m 放大。
static func _build_tu160(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.05, 0.05), Vector3(-12.5, 0.72, 0.66),
		Vector3(-6.5, 1.28, 1.16), Vector3(1.0, 1.72, 1.48), Vector3(9.0, 1.58, 1.30),
		Vector3(14.8, 0.92, 0.78), Vector3(17.0, 0.28, 0.30)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 0.95, -10.1), [Vector3(-2.5, 0.04, 0.04),
		Vector3(-1.2, 0.50, 0.42), Vector3(1.1, 0.52, 0.44), Vector3(2.2, 0.06, 0.05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.15, -2.8), Vector2(3.5, -2.0), Vector2(14.0, 5.6),
			Vector2(13.6, 7.3), Vector2(4.0, 5.6), Vector2(1.4, 2.2)], side, -0.22, 0.20, BODY)
		_planform(builder, [Vector2(0.95, -5.6), Vector2(2.4, -4.3), Vector2(4.0, -1.8),
			Vector2(3.7, 4.8), Vector2(1.2, 2.7)], side, -0.30, 0.34, BODY)
		_planform(builder, [Vector2(0.8, 11.0), Vector2(2.0, 10.8),
			Vector2(5.2, 14.0), Vector2(4.8, 15.8)], side, -0.08, 0.20, BODY)
		for engine_x in [2.3, 3.9]:
			_closed_loft(builder, Vector3(engine_x * side, -0.42, 5.0), [Vector3(-5.0, 0.58, 0.48),
				Vector3(-3.1, 0.78, 0.62), Vector3(6.0, 0.75, 0.56), Vector3(8.8, 0.48, 0.36)],
				ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(3.1 * side, -0.40, -0.4), Vector3(3.4, 0.72, 2.2), INTAKE)
	_fin(builder, 0.0, [Vector2(9.4, 0.36), Vector2(11.0, 5.2),
		Vector2(14.2, 4.6), Vector2(16.2, 0.30)], 0.22, 0.0, BODY)


## B-1B：同为四发变后掠轰炸机，但使用低矮机背、宽手套和短双联发动机舱。
static func _build_b1b(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.05, 0.05), Vector3(-12.0, 0.92, 0.60),
		Vector3(-6.0, 1.55, 1.02), Vector3(1.5, 2.15, 1.22), Vector3(8.0, 1.95, 1.08),
		Vector3(14.5, 1.10, 0.68), Vector3(17.0, 0.30, 0.26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 0.90, -9.2), [Vector3(-2.8, 0.04, 0.04),
		Vector3(-1.3, 0.62, 0.38), Vector3(1.4, 0.66, 0.40), Vector3(2.7, 0.06, 0.05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.5, -1.8), Vector2(4.8, -0.8), Vector2(14.0, 6.6),
			Vector2(13.2, 8.0), Vector2(5.0, 5.5), Vector2(1.8, 2.8)], side, -0.24, 0.20, BODY)
		_planform(builder, [Vector2(1.1, -5.0), Vector2(3.2, -3.6), Vector2(5.0, -0.7),
			Vector2(4.6, 5.0), Vector2(1.5, 3.0)], side, -0.34, 0.36, BODY)
		_planform(builder, [Vector2(0.9, 10.6), Vector2(2.4, 10.4),
			Vector2(6.0, 13.0), Vector2(5.6, 15.2)], side, -0.10, 0.18, BODY)
		for engine_x in [2.2, 3.7]:
			_closed_loft(builder, Vector3(engine_x * side, -0.52, 4.3), [Vector3(-4.3, 0.64, 0.50),
				Vector3(-2.8, 0.82, 0.64), Vector3(4.5, 0.82, 0.60), Vector3(7.0, 0.55, 0.40)],
				ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.95 * side, -0.48, -0.2), Vector3(3.5, 0.78, 2.4), INTAKE)
	_fin(builder, 0.0, [Vector2(8.8, 0.35), Vector2(10.2, 4.4),
		Vector2(13.4, 4.0), Vector2(15.7, 0.28)], 0.22, 0.0, BODY)


## F-4E：宽肩双发的二代重型机，翼尖/平尾轮廓和单垂尾均独立于后来的 F-15。
static func _build_f4(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.5, 0.82, 0.74),
		Vector3(-6.5, 1.55, 1.32), Vector3(0.5, 2.15, 1.58), Vector3(8.0, 2.12, 1.42),
		Vector3(14.2, 1.35, 0.88), Vector3(17, 0.34, 0.32)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.32, -7.2), [Vector3(-4.0, 0.05, 0.05),
		Vector3(-2.0, 0.82, 0.70), Vector3(1.8, 0.90, 0.72), Vector3(3.7, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.8, -2.8), Vector2(4.0, -2.2), Vector2(10.35, 3.1),
			Vector2(10.0, 6.0), Vector2(8.8, 6.8), Vector2(2.0, 6.6)], side, -0.34, 0.28, BODY)
		_planform(builder, [Vector2(1.25, -7.1), Vector2(2.3, -5.4), Vector2(4.0, -2.1),
			Vector2(2.1, 0.8), Vector2(1.25, -1.2)], side, -0.42, 0.40, BODY)
		_planform(builder, [Vector2(1.2, 10.3), Vector2(3.0, 10.0), Vector2(7.1, 13.0),
			Vector2(6.4, 15.4), Vector2(1.3, 13.8)], side, -0.28, 0.12, BODY)
		_closed_loft(builder, Vector3(2.35 * side, -0.30, 4.5), [Vector3(-6.0, 0.68, 0.62),
			Vector3(-3.8, 1.05, 0.92), Vector3(7.5, 1.05, 0.82), Vector3(10.5, 0.72, 0.58)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.55 * side, -0.15, -2.5), Vector3(1.6, 0.92, 2.8), INTAKE)
	_fin(builder, 0.0, [Vector2(7.5, 0.46), Vector2(9.8, 5.8),
		Vector2(12.8, 5.2), Vector2(15.3, 0.38)], 0.23, 0.0, BODY)


## F-86F：近一比一的翼展/机长、圆形机鼻进气与桶形单发机身。
static func _build_f86(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.18, 0.18), Vector3(-15.2, 1.05, 1.08),
		Vector3(-9.0, 1.45, 1.50), Vector3(-1.0, 1.55, 1.58), Vector3(8.5, 1.38, 1.38),
		Vector3(14.5, 0.92, 0.88), Vector3(17, 0.28, 0.30)], BODY, INTAKE, INTAKE)
	_closed_loft(builder, Vector3(0, 1.35, -6.0), [Vector3(-3.0, 0.05, 0.05),
		Vector3(-1.4, 0.72, 0.62), Vector3(1.3, 0.78, 0.64), Vector3(2.8, 0.07, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.2, -2.4), Vector2(6.0, -1.6), Vector2(16.85, 5.2),
			Vector2(16.1, 7.8), Vector2(12.8, 8.8), Vector2(1.5, 4.6)], side, -0.28, 0.24, BODY)
		_planform(builder, [Vector2(0.9, 10.6), Vector2(2.6, 10.4), Vector2(7.0, 13.2),
			Vector2(6.1, 15.2), Vector2(1.0, 13.7)], side, -0.12, 0.22, BODY)
	_fin(builder, 0.0, [Vector2(8.3, 0.42), Vector2(10.0, 4.8),
		Vector2(13.1, 4.3), Vector2(15.7, 0.34)], 0.22, 0.0, BODY)


## F-100：比 F-86 更细长，扁椭圆机鼻进气、后掠翼与高耸单垂尾。
static func _build_f100(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.12, 0.10), Vector3(-14.5, 0.82, 0.72),
		Vector3(-8.0, 1.18, 1.16), Vector3(0.0, 1.35, 1.40), Vector3(9.0, 1.20, 1.22),
		Vector3(15.0, 0.76, 0.76), Vector3(17, 0.26, 0.28)], BODY, INTAKE, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -6.8), [Vector3(-3.0, 0.05, 0.05),
		Vector3(-1.5, 0.68, 0.58), Vector3(1.4, 0.72, 0.60), Vector3(2.9, 0.07, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.1, -1.8), Vector2(4.0, -1.2), Vector2(13.2, 4.2),
			Vector2(12.7, 7.0), Vector2(1.4, 5.2)], side, -0.24, 0.22, BODY)
		_planform(builder, [Vector2(0.8, 10.9), Vector2(2.2, 10.7), Vector2(5.6, 13.2),
			Vector2(5.0, 15.2), Vector2(0.9, 13.9)], side, -0.12, 0.22, BODY)
	_fin(builder, 0.0, [Vector2(7.9, 0.42), Vector2(9.8, 6.2),
		Vector2(12.9, 5.4), Vector2(15.7, 0.32)], 0.22, 0.0, BODY)


## F/A-18A：长边条、双进气/双发与外倾双垂尾；不承担 Super Hornet 放大变体。
static func _build_fa18(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.0, 0.78, 0.72),
		Vector3(-6.0, 1.45, 1.25), Vector3(0.0, 2.05, 1.48), Vector3(8.5, 2.02, 1.32),
		Vector3(14.5, 1.38, 0.82), Vector3(17, 0.34, 0.30)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.30, -7.6), [Vector3(-3.5, 0.05, 0.05),
		Vector3(-1.7, 0.84, 0.70), Vector3(1.6, 0.88, 0.72), Vector3(3.2, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -2.8), Vector2(4.2, -1.9), Vector2(12.25, 2.6),
			Vector2(11.8, 6.4), Vector2(7.8, 7.1), Vector2(2.0, 5.4)], side, -0.30, 0.28, BODY)
		_planform(builder, [Vector2(1.1, -9.5), Vector2(2.4, -7.0), Vector2(4.2, -1.8),
			Vector2(2.8, 1.5), Vector2(1.3, -2.5)], side, -0.40, 0.40, BODY)
		_planform(builder, [Vector2(1.4, 9.1), Vector2(3.0, 8.9), Vector2(6.0, 12.2),
			Vector2(5.5, 14.5), Vector2(1.5, 13.2)], side, -0.12, 0.26, BODY)
		_closed_loft(builder, Vector3(2.25 * side, -0.20, 4.7), [Vector3(-5.5, 0.82, 0.70),
			Vector3(-3.2, 1.14, 0.95), Vector3(7.2, 1.12, 0.82), Vector3(10.2, 0.72, 0.54)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.55 * side, -0.18, -2.8), Vector3(1.5, 0.92, 2.8), INTAKE)
		_fin(builder, 2.65 * side, [Vector2(6.8, 0.44), Vector2(8.5, 4.7),
			Vector2(11.3, 4.2), Vector2(13.5, 0.36)], 0.18, side * 0.22, BODY)


## MiG-29：短粗翼身、发动机间槽和大平尾；不同于长身 Su-27。
static func _build_mig29(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-11.5, 0.88, 0.76),
		Vector3(-5.5, 1.85, 1.35), Vector3(1.0, 2.65, 1.55), Vector3(8.0, 2.55, 1.35),
		Vector3(14.0, 1.55, 0.82), Vector3(17, 0.36, 0.30)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -7.5), [Vector3(-3.2, 0.05, 0.05),
		Vector3(-1.5, 0.78, 0.66), Vector3(1.5, 0.82, 0.68), Vector3(3.0, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -3.6), Vector2(5.1, -2.5), Vector2(11.15, 2.8),
			Vector2(10.7, 6.8), Vector2(6.4, 7.8), Vector2(2.8, 4.6)], side, -0.30, 0.28, BODY)
		_planform(builder, [Vector2(1.25, -10.0), Vector2(2.8, -7.4), Vector2(5.1, -2.5),
			Vector2(3.5, 1.0), Vector2(1.5, -3.0)], side, -0.40, 0.40, BODY)
		_planform(builder, [Vector2(2.1, 8.7), Vector2(3.7, 8.4), Vector2(7.4, 11.8),
			Vector2(6.8, 14.5), Vector2(2.2, 13.2)], side, -0.12, 0.28, BODY)
		_closed_loft(builder, Vector3(2.55 * side, -0.28, 4.8), [Vector3(-5.8, 0.90, 0.72),
			Vector3(-3.4, 1.22, 0.92), Vector3(7.2, 1.18, 0.78), Vector3(10.5, 0.72, 0.48)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, -0.30, -2.8), Vector3(1.7, 0.86, 2.9), INTAKE)
		_fin(builder, 2.9 * side, [Vector2(6.4, 0.45), Vector2(8.2, 5.0),
			Vector2(11.1, 4.5), Vector2(13.8, 0.35)], 0.18, side * 0.18, BODY)


## Su-27：长鼻与长发动机舱、连续弧形边条、宽翼和后伸尾梁。
static func _build_su27(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.5, 0.82, 0.70),
		Vector3(-6.5, 1.72, 1.25), Vector3(0.5, 2.45, 1.48), Vector3(8.0, 2.40, 1.30),
		Vector3(14.2, 1.42, 0.76), Vector3(17, 0.34, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.24, -8.4), [Vector3(-3.3, 0.05, 0.05),
		Vector3(-1.6, 0.76, 0.64), Vector3(1.6, 0.82, 0.66), Vector3(3.1, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.3, -4.6), Vector2(5.0, -2.9), Vector2(11.4, 3.5),
			Vector2(11.1, 7.0), Vector2(7.1, 8.5), Vector2(2.7, 4.8)], side, -0.30, 0.28, BODY)
		_planform(builder, [Vector2(1.2, -11.0), Vector2(2.5, -8.4), Vector2(5.0, -2.9),
			Vector2(4.1, 1.5), Vector2(2.5, 2.6), Vector2(1.45, -3.5)], side, -0.40, 0.42, BODY)
		_planform(builder, [Vector2(2.0, 8.8), Vector2(3.8, 8.5), Vector2(7.8, 12.0),
			Vector2(7.1, 15.0), Vector2(2.1, 13.5)], side, -0.12, 0.28, BODY)
		_closed_loft(builder, Vector3(2.45 * side, -0.28, 5.4), [Vector3(-6.5, 0.86, 0.70),
			Vector3(-4.0, 1.18, 0.90), Vector3(7.5, 1.15, 0.76), Vector3(10.8, 0.68, 0.46)],
			ENGINE, INTAKE, INTAKE)
		_fin(builder, 2.75 * side, [Vector2(6.5, 0.44), Vector2(8.5, 5.2),
			Vector2(11.8, 4.6), Vector2(14.2, 0.34)], 0.18, side * 0.16, BODY)


## Rafale：近耦合前翼、连续大三角翼、双发尾段与单垂尾。
static func _build_rafale(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-11.8, 0.74, 0.68),
		Vector3(-6.0, 1.48, 1.22), Vector3(0.0, 2.10, 1.50), Vector3(8.5, 2.05, 1.34),
		Vector3(14.5, 1.32, 0.76), Vector3(17, 0.34, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.30, -7.8), [Vector3(-3.3, 0.05, 0.05),
		Vector3(-1.6, 0.80, 0.66), Vector3(1.5, 0.84, 0.68), Vector3(3.0, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -2.6), Vector2(4.4, -1.5), Vector2(12.15, 5.4),
			Vector2(11.8, 8.3), Vector2(3.0, 7.1), Vector2(1.8, 3.5)], side, -0.28, 0.26, BODY)
		_planform(builder, [Vector2(1.25, -6.2), Vector2(2.2, -6.0),
			Vector2(6.0, -3.7), Vector2(5.4, -2.2), Vector2(1.4, -3.6)], side, 0.15, 0.38, BODY)
		_closed_loft(builder, Vector3(1.95 * side, -0.28, 5.0), [Vector3(-5.5, 0.72, 0.62),
			Vector3(-3.2, 1.02, 0.82), Vector3(7.2, 1.00, 0.72), Vector3(10.3, 0.62, 0.44)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.2 * side, -0.22, -2.5), Vector3(1.35, 0.82, 2.6), INTAKE)
	_fin(builder, 0.0, [Vector2(6.8, 0.44), Vector2(8.8, 5.0),
		Vector2(11.8, 4.4), Vector2(14.2, 0.34)], 0.22, 0.0, BODY)


## Typhoon：更前置的三角前翼、裁角大三角翼、腹部双进气和单垂尾。
static func _build_typhoon(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.0, 0.72, 0.66),
		Vector3(-6.0, 1.38, 1.18), Vector3(0.0, 2.0, 1.48), Vector3(8.2, 1.95, 1.30),
		Vector3(14.2, 1.25, 0.72), Vector3(17, 0.32, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -7.6), [Vector3(-3.2, 0.05, 0.05),
		Vector3(-1.5, 0.76, 0.64), Vector3(1.5, 0.82, 0.66), Vector3(3.0, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.8, -1.8), Vector2(4.6, -0.8), Vector2(11.65, 5.0),
			Vector2(11.0, 8.5), Vector2(2.4, 7.0)], side, -0.28, 0.26, BODY)
		_planform(builder, [Vector2(1.15, -8.0), Vector2(2.0, -7.8),
			Vector2(5.5, -5.4), Vector2(5.0, -3.9), Vector2(1.3, -5.0)], side, 0.16, 0.40, BODY)
		_closed_loft(builder, Vector3(1.9 * side, -0.28, 5.2), [Vector3(-5.5, 0.70, 0.60),
			Vector3(-3.0, 1.00, 0.80), Vector3(7.0, 0.98, 0.70), Vector3(10.2, 0.60, 0.42)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(1.95 * side, -0.42, -2.2), Vector3(1.45, 0.72, 2.7), INTAKE)
	_fin(builder, 0.0, [Vector2(6.6, 0.44), Vector2(8.5, 5.2),
		Vector2(11.5, 4.5), Vector2(14.0, 0.34)], 0.22, 0.0, BODY)


## A-6E：并列座舱造成宽钝机鼻，双发进气嵌入翼根，宽翼承担主要平面特征。
static func _build_a6e(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.08, 0.08), Vector3(-13.0, 1.55, 1.15),
		Vector3(-7.0, 2.35, 1.65), Vector3(0.0, 2.65, 1.72), Vector3(8.0, 2.25, 1.42),
		Vector3(14.5, 1.30, 0.78), Vector3(17, 0.34, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.40, -9.0), [Vector3(-3.5, 0.08, 0.06),
		Vector3(-1.8, 1.38, 0.78), Vector3(1.6, 1.45, 0.82), Vector3(3.2, 0.12, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -2.5), Vector2(6.2, -1.5), Vector2(16.45, 3.7),
			Vector2(16.0, 7.2), Vector2(11.5, 8.2), Vector2(2.2, 5.3)], side, -0.34, 0.28, BODY)
		_planform(builder, [Vector2(1.1, 10.0), Vector2(3.0, 9.8), Vector2(7.0, 12.6),
			Vector2(6.3, 15.0), Vector2(1.2, 13.6)], side, -0.12, 0.24, BODY)
		_closed_loft(builder, Vector3(2.55 * side, -0.28, 3.4), [Vector3(-6.0, 0.78, 0.68),
			Vector3(-3.8, 1.12, 0.92), Vector3(7.0, 1.08, 0.78), Vector3(10.4, 0.68, 0.48)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.75 * side, -0.15, -3.1), Vector3(1.7, 0.92, 2.8), INTAKE)
	_fin(builder, 0.0, [Vector2(7.2, 0.46), Vector2(9.0, 5.8),
		Vector2(12.2, 5.2), Vector2(15.3, 0.36)], 0.23, 0.0, BODY)


## A-7：单发、机鼻下进气与短粗机身，不沿用 A-6 的双发宽肩。
static func _build_a7(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.08, 0.06), Vector3(-13.0, 1.05, 0.82),
		Vector3(-7.0, 1.55, 1.35), Vector3(0.0, 1.78, 1.55), Vector3(8.5, 1.52, 1.30),
		Vector3(14.5, 0.96, 0.78), Vector3(17, 0.30, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.32, -7.6), [Vector3(-3.2, 0.06, 0.05),
		Vector3(-1.5, 0.82, 0.68), Vector3(1.5, 0.86, 0.70), Vector3(3.0, 0.08, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.4, -1.8), Vector2(5.0, -1.0), Vector2(14.25, 4.2),
			Vector2(13.8, 7.2), Vector2(9.5, 8.0), Vector2(1.7, 5.0)], side, -0.28, 0.24, BODY)
		_planform(builder, [Vector2(0.9, 10.2), Vector2(2.5, 10.0), Vector2(6.0, 12.8),
			Vector2(5.4, 14.9), Vector2(1.0, 13.6)], side, -0.12, 0.22, BODY)
	builder.box(Vector3(0, -1.22, -7.3), Vector3(1.9, 0.78, 3.1), INTAKE)
	_fin(builder, 0.0, [Vector2(7.5, 0.44), Vector2(9.4, 5.4),
		Vector2(12.3, 4.8), Vector2(15.2, 0.34)], 0.22, 0.0, BODY)


## EA-6B：四座舱、加长机鼻、翼尖电战舱与垂尾顶整流罩均是本体识别结构。
static func _build_ea6b(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.08, 0.08), Vector3(-13.0, 1.62, 1.18),
		Vector3(-7.0, 2.45, 1.72), Vector3(0.0, 2.72, 1.78), Vector3(8.0, 2.28, 1.45),
		Vector3(14.5, 1.32, 0.80), Vector3(17, 0.34, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.48, -7.6), [Vector3(-5.0, 0.08, 0.06),
		Vector3(-3.0, 1.42, 0.82), Vector3(2.7, 1.50, 0.86), Vector3(4.8, 0.12, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -2.3), Vector2(6.0, -1.4), Vector2(15.5, 3.5),
			Vector2(15.1, 7.2), Vector2(11.0, 8.2), Vector2(2.2, 5.3)], side, -0.34, 0.28, BODY)
		_planform(builder, [Vector2(1.1, 10.0), Vector2(3.0, 9.8), Vector2(7.0, 12.6),
			Vector2(6.3, 15.0), Vector2(1.2, 13.6)], side, -0.12, 0.24, BODY)
		_closed_loft(builder, Vector3(2.58 * side, -0.28, 3.4), [Vector3(-6.0, 0.80, 0.70),
			Vector3(-3.8, 1.14, 0.94), Vector3(7.0, 1.10, 0.80), Vector3(10.4, 0.70, 0.50)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, -0.15, -3.0), Vector3(1.75, 0.94, 2.8), INTAKE)
		_closed_loft(builder, Vector3(14.7 * side, 0.28, 5.0), [Vector3(-3.4, 0.22, 0.20),
			Vector3(-2.2, 0.58, 0.52), Vector3(2.2, 0.58, 0.50), Vector3(3.4, 0.20, 0.18)], ENGINE)
	_fin(builder, 0.0, [Vector2(7.2, 0.46), Vector2(9.0, 5.8),
		Vector2(12.2, 5.2), Vector2(15.3, 0.36)], 0.23, 0.0, BODY)
	builder.box(Vector3(0, 5.7, 10.4), Vector3(0.75, 0.32, 2.2), ENGINE)


## F-15 S/MTD：以前翼、粗壮尾喷口和实验型尾段与标准 Eagle 分家。
static func _build_f15smtd(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12, 0.95, 0.85),
		Vector3(-6, 1.55, 1.38), Vector3(0, 2.15, 1.52), Vector3(8, 2.3, 1.35),
		Vector3(14, 1.78, 0.98), Vector3(17, 0.38, 0.34)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.32, -8.3), [Vector3(-3.5, 0.06, 0.06),
		Vector3(-1.7, 0.88, 0.92), Vector3(1.5, 0.92, 0.86), Vector3(3.4, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -2.8), Vector2(3.8, -2.4), Vector2(11.3, 2.8),
			Vector2(10.8, 7.1), Vector2(2.1, 7.8)], side, -0.34, 0.30, BODY)
		_planform(builder, [Vector2(1.2, -7.4), Vector2(2.1, -7.2),
			Vector2(5.8, -4.4), Vector2(5.2, -2.9), Vector2(1.4, -4.3)], side, 0.18, 0.44, BODY)
		_planform(builder, [Vector2(1.55, 9.5), Vector2(3.2, 9.2), Vector2(7.1, 12.9),
			Vector2(6.7, 15.1), Vector2(1.7, 13.7)], side, -0.10, 0.32, BODY)
		_closed_loft(builder, Vector3(2.65 * side, -0.18, 4.0), [Vector3(-7.0, 0.72, 0.72),
			Vector3(-4.7, 1.2, 1.05), Vector3(8.2, 1.24, 1.05), Vector3(11.7, 1.00, 0.92)],
			ENGINE, INTAKE, ENGINE)
		builder.box(Vector3(2.9 * side, -0.08, -2.6), Vector3(1.55, 1.05, 3.2), INTAKE)
		_fin(builder, 2.85 * side, [Vector2(7.6, 0.5), Vector2(9.2, 5.6),
			Vector2(12.0, 5.1), Vector2(14.6, 0.45)], 0.20, side * 0.16, BODY)


## F/A-18E：更大的裁角翼、锯齿 LERX 与矩形进气，不把老 Hornet 等比例放大。
static func _build_fa18e(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.0, 0.82, 0.74),
		Vector3(-6.0, 1.55, 1.30), Vector3(0.0, 2.25, 1.55), Vector3(8.5, 2.20, 1.38),
		Vector3(14.5, 1.45, 0.86), Vector3(17, 0.36, 0.32)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.34, -7.5), [Vector3(-3.5, 0.05, 0.05),
		Vector3(-1.7, 0.86, 0.72), Vector3(1.6, 0.90, 0.74), Vector3(3.2, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.9, -2.4), Vector2(4.8, -1.4), Vector2(12.65, 2.0),
			Vector2(12.4, 6.2), Vector2(8.2, 7.6), Vector2(2.2, 5.5)], side, -0.32, 0.30, BODY)
		_planform(builder, [Vector2(1.1, -9.7), Vector2(2.5, -7.0), Vector2(4.8, -1.4),
			Vector2(3.0, 1.8), Vector2(1.35, -2.6)], side, -0.42, 0.42, BODY)
		_planform(builder, [Vector2(1.5, 9.0), Vector2(3.2, 8.7), Vector2(6.5, 12.0),
			Vector2(6.0, 14.6), Vector2(1.6, 13.2)], side, -0.12, 0.28, BODY)
		_closed_loft(builder, Vector3(2.45 * side, -0.22, 4.8), [Vector3(-5.7, 0.86, 0.72),
			Vector3(-3.3, 1.18, 0.96), Vector3(7.2, 1.16, 0.84), Vector3(10.3, 0.75, 0.56)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, -0.20, -2.7), Vector3(1.8, 0.98, 3.0), INTAKE)
		_fin(builder, 2.9 * side, [Vector2(6.7, 0.44), Vector2(8.5, 4.9),
			Vector2(11.4, 4.3), Vector2(13.7, 0.36)], 0.18, side * 0.24, BODY)


## F-CK-1：轻型双发、较短机鼻与双垂尾；避免退化为 F-16 或 F/A-18。
static func _build_fck1(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-11.8, 0.76, 0.70),
		Vector3(-5.6, 1.45, 1.25), Vector3(0.5, 2.05, 1.48), Vector3(8.5, 2.0, 1.32),
		Vector3(14.5, 1.25, 0.74), Vector3(17, 0.32, 0.28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -7.4), [Vector3(-3.2, 0.05, 0.05),
		Vector3(-1.5, 0.80, 0.66), Vector3(1.5, 0.84, 0.68), Vector3(3.0, 0.08, 0.08)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -2.4), Vector2(4.0, -1.6), Vector2(11.3, 2.4),
			Vector2(10.9, 6.2), Vector2(6.4, 7.1), Vector2(2.0, 5.0)], side, -0.30, 0.28, BODY)
		_planform(builder, [Vector2(1.1, -8.8), Vector2(2.4, -6.4), Vector2(4.0, -1.6),
			Vector2(2.7, 1.0), Vector2(1.3, -2.4)], side, -0.38, 0.40, BODY)
		_planform(builder, [Vector2(1.4, 9.0), Vector2(2.8, 8.8), Vector2(5.8, 11.8),
			Vector2(5.3, 14.2), Vector2(1.5, 12.9)], side, -0.12, 0.26, BODY)
		_closed_loft(builder, Vector3(1.95 * side, -0.24, 4.7), [Vector3(-5.2, 0.68, 0.58),
			Vector3(-3.0, 0.94, 0.78), Vector3(7.0, 0.92, 0.68), Vector3(10.0, 0.58, 0.42)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.15 * side, -0.18, -2.5), Vector3(1.3, 0.80, 2.6), INTAKE)
		_fin(builder, 2.35 * side, [Vector2(6.7, 0.40), Vector2(8.4, 4.2),
			Vector2(11.0, 3.8), Vector2(13.2, 0.32)], 0.17, side * 0.18, BODY)


## Gripen：小型单发鸭翼三角翼，翼展显著窄于 Rafale/Typhoon。
static func _build_gripen(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-11.8, 0.70, 0.64),
		Vector3(-5.8, 1.30, 1.12), Vector3(0.0, 1.65, 1.38), Vector3(8.5, 1.50, 1.22),
		Vector3(14.5, 0.92, 0.68), Vector3(17, 0.28, 0.26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.22, -7.7), [Vector3(-3.1, 0.05, 0.05),
		Vector3(-1.4, 0.72, 0.60), Vector3(1.4, 0.76, 0.62), Vector3(2.9, 0.07, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.3, -1.8), Vector2(3.8, -1.0), Vector2(10.15, 4.3),
			Vector2(9.8, 7.2), Vector2(2.0, 6.2)], side, -0.26, 0.24, BODY)
		_planform(builder, [Vector2(1.0, -6.7), Vector2(1.8, -6.5),
			Vector2(4.7, -4.2), Vector2(4.2, -2.8), Vector2(1.15, -4.1)], side, 0.14, 0.36, BODY)
		builder.box(Vector3(1.65 * side, -0.18, -2.8), Vector3(1.15, 0.76, 2.5), INTAKE)
	_fin(builder, 0.0, [Vector2(6.6, 0.40), Vector2(8.4, 4.7),
		Vector2(11.0, 4.1), Vector2(13.8, 0.32)], 0.21, 0.0, BODY)


## Harrier II：高翼、粗单发机身、两侧大进气和四具矢量喷口构成 VTOL 轮廓。
static func _build_harrier(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12.5, 0.86, 0.78),
		Vector3(-6.0, 1.65, 1.48), Vector3(1.0, 2.15, 1.75), Vector3(8.5, 1.85, 1.45),
		Vector3(14.5, 1.05, 0.72), Vector3(17, 0.30, 0.26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.46, -7.4), [Vector3(-3.2, 0.05, 0.05),
		Vector3(-1.5, 0.78, 0.62), Vector3(1.5, 0.82, 0.64), Vector3(3.0, 0.08, 0.07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -1.8), Vector2(4.2, -1.1), Vector2(9.3, 2.0),
			Vector2(8.9, 5.4), Vector2(5.8, 6.2), Vector2(1.9, 4.5)], side, 0.18, 0.58, BODY)
		_planform(builder, [Vector2(1.0, 10.0), Vector2(2.5, 9.8), Vector2(5.2, 12.5),
			Vector2(4.8, 14.6), Vector2(1.1, 13.3)], side, -0.12, 0.22, BODY)
		builder.box(Vector3(2.0 * side, -0.10, -3.0), Vector3(1.5, 1.35, 2.8), INTAKE)
		for nozzle_z in [-0.5, 5.0]:
			builder.box(Vector3(2.25 * side, -0.65, nozzle_z), Vector3(0.65, 0.75, 1.05), ENGINE)
	_fin(builder, 0.0, [Vector2(7.1, 0.44), Vector2(9.0, 5.3),
		Vector2(12.0, 4.7), Vector2(14.8, 0.34)], 0.22, 0.0, BODY)


static func _build_j20(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, 1.0, .68),
		Vector3(-6, 2.4, 1.25), Vector3(1, 3.2, 1.55), Vector3(9, 3.0, 1.25),
		Vector3(15, 1.7, .72), Vector3(17, .34, .26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.25, -8), [Vector3(-3.2, .05, .05),
		Vector3(-1.5, .82, .58), Vector3(1.5, .86, .60), Vector3(3, .08, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.3, -3.8), Vector2(5.0, -2.3), Vector2(11.3, 4.5),
			Vector2(10.4, 8.4), Vector2(4.8, 7.2), Vector2(2.5, 3.0)], side, -.30, .28, BODY)
		_planform(builder, [Vector2(1.2, -9.0), Vector2(2.2, -8.7), Vector2(5.0, -5.8),
			Vector2(4.4, -4.0), Vector2(1.4, -5.2)], side, .14, .42, BODY)
		_planform(builder, [Vector2(2.0, 8.8), Vector2(3.7, 8.5), Vector2(7.0, 12.0),
			Vector2(6.4, 14.7), Vector2(2.1, 13.4)], side, -.10, .28, BODY)
		_closed_loft(builder, Vector3(2.35 * side, -.25, 5.0), [Vector3(-6, .84, .65),
			Vector3(-3.5, 1.16, .82), Vector3(7.2, 1.12, .68), Vector3(10.4, .68, .42)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, -.18, -2.7), Vector3(1.65, .85, 2.8), INTAKE)
		_fin(builder, 2.9 * side, [Vector2(7.0, .42), Vector2(9.2, 4.5),
			Vector2(12.0, 4.0), Vector2(14.2, .32)], .17, side * .28, BODY)


static func _build_j35f(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-11.5, .72, .66),
		Vector3(-5.5, 1.22, 1.15), Vector3(1, 1.50, 1.42), Vector3(9, 1.30, 1.15),
		Vector3(15, .76, .68), Vector3(17, .26, .25)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -7.2), [Vector3(-3, .05, .05),
		Vector3(-1.4, .70, .58), Vector3(1.4, .74, .60), Vector3(2.8, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.0, -4.0), Vector2(3.8, -2.2), Vector2(10.45, 5.0),
			Vector2(9.8, 8.2), Vector2(5.5, 6.8), Vector2(1.2, 3.2)], side, -.24, .22, BODY)
		_planform(builder, [Vector2(1.1, -1.0), Vector2(5.5, 1.5), Vector2(10.0, 7.0),
			Vector2(6.2, 8.2), Vector2(1.2, 5.0)], side, -.18, .28, BODY)
	_fin(builder, 0, [Vector2(7.2, .42), Vector2(9.0, 5.3), Vector2(12.0, 4.7),
		Vector2(15.0, .32)], .22, 0, BODY)


static func _build_j7(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .16, .16), Vector3(-14, .72, .74),
		Vector3(-8, 1.02, 1.08), Vector3(0, 1.16, 1.25), Vector3(9, 1.02, 1.05),
		Vector3(15, .64, .64), Vector3(17, .24, .24)], BODY, INTAKE, INTAKE)
	_closed_loft(builder, Vector3(0, 1.05, -6.4), [Vector3(-2.8, .05, .05),
		Vector3(-1.3, .60, .52), Vector3(1.3, .64, .54), Vector3(2.7, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.8, -1.0), Vector2(3.3, -.4), Vector2(8.15, 4.7),
			Vector2(7.8, 7.0), Vector2(1.0, 5.2)], side, -.18, .18, BODY)
		_planform(builder, [Vector2(.7, 10.3), Vector2(1.8, 10.1), Vector2(4.2, 12.8),
			Vector2(3.8, 14.8), Vector2(.8, 13.4)], side, -.10, .18, BODY)
	_fin(builder, 0, [Vector2(7.4, .36), Vector2(9.3, 5.2), Vector2(12.0, 4.6),
		Vector2(15.1, .28)], .20, 0, BODY)


static func _build_jaguar(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .68, .64),
		Vector3(-6, 1.20, 1.15), Vector3(1, 1.62, 1.42), Vector3(9, 1.45, 1.18),
		Vector3(15, .82, .66), Vector3(17, .28, .24)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.15, -7.5), [Vector3(-3.2, .05, .05),
		Vector3(-1.5, .72, .60), Vector3(1.4, .76, .62), Vector3(2.9, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.3, -1.2), Vector2(3.7, -.6), Vector2(8.8, 2.9),
			Vector2(8.5, 6.0), Vector2(5.0, 6.8), Vector2(1.5, 4.6)], side, .12, .48, BODY)
		_planform(builder, [Vector2(.9, 10.0), Vector2(2.2, 9.8), Vector2(4.8, 12.4),
			Vector2(4.4, 14.5), Vector2(1.0, 13.2)], side, -.10, .22, BODY)
		_closed_loft(builder, Vector3(1.75 * side, -.22, 4.4), [Vector3(-5, .58, .50),
			Vector3(-3, .82, .68), Vector3(6.5, .80, .58), Vector3(9.5, .52, .38)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(1.9 * side, -.16, -2.8), Vector3(1.2, .72, 2.4), INTAKE)
	_fin(builder, 0, [Vector2(7.1, .40), Vector2(8.9, 4.9), Vector2(11.7, 4.3),
		Vector2(14.5, .30)], .21, 0, BODY)


static func _build_mig21f13(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .14, .14), Vector3(-14.5, .66, .70),
		Vector3(-8, .98, 1.02), Vector3(0, 1.10, 1.20), Vector3(9, .96, 1.00),
		Vector3(15, .60, .60), Vector3(17, .22, .22)], BODY, INTAKE, INTAKE)
	_closed_loft(builder, Vector3(0, 1.02, -6.8), [Vector3(-2.8, .05, .05),
		Vector3(-1.3, .58, .50), Vector3(1.3, .62, .52), Vector3(2.7, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.75, -1.5), Vector2(3.0, -.7), Vector2(7.7, 4.4),
			Vector2(7.4, 7.0), Vector2(.9, 5.4)], side, -.17, .17, BODY)
		_planform(builder, [Vector2(.65, 10.0), Vector2(1.7, 9.8), Vector2(4.0, 12.5),
			Vector2(3.6, 14.7), Vector2(.75, 13.2)], side, -.09, .17, BODY)
	_fin(builder, 0, [Vector2(7.0, .34), Vector2(8.8, 5.5), Vector2(11.7, 4.8),
		Vector2(14.8, .26)], .20, 0, BODY)


static func _build_mig23(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .70, .66),
		Vector3(-6, 1.30, 1.20), Vector3(1, 1.72, 1.48), Vector3(9, 1.48, 1.20),
		Vector3(15, .82, .68), Vector3(17, .28, .25)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -7.2), [Vector3(-3, .05, .05),
		Vector3(-1.4, .70, .58), Vector3(1.4, .74, .60), Vector3(2.8, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.4, -1.5), Vector2(4.0, -.8), Vector2(14.2, 3.2),
			Vector2(13.7, 6.3), Vector2(1.6, 5.2)], side, -.25, .23, BODY)
		_planform(builder, [Vector2(.9, 10.0), Vector2(2.3, 9.8), Vector2(5.0, 12.5),
			Vector2(4.6, 14.7), Vector2(1.0, 13.3)], side, -.10, .22, BODY)
		builder.box(Vector3(1.75 * side, -.14, -2.5), Vector3(1.25, .88, 2.8), INTAKE)
	_fin(builder, 0, [Vector2(7.0, .42), Vector2(8.8, 5.6), Vector2(11.8, 4.9),
		Vector2(14.8, .32)], .22, 0, BODY)


static func _build_mig31(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .82, .72),
		Vector3(-6, 1.55, 1.32), Vector3(1, 2.35, 1.62), Vector3(9, 2.30, 1.45),
		Vector3(15, 1.45, .82), Vector3(17, .34, .28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.35, -6.8), [Vector3(-4.5, .05, .05),
		Vector3(-2.5, .92, .70), Vector3(2.3, .96, .72), Vector3(4.2, .08, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.9, -1.8), Vector2(4.5, -1.0), Vector2(10.1, 3.0),
			Vector2(9.8, 6.8), Vector2(5.6, 7.5), Vector2(2.1, 5.2)], side, -.32, .28, BODY)
		_planform(builder, [Vector2(1.5, 9.2), Vector2(3.0, 9.0), Vector2(6.0, 12.0),
			Vector2(5.6, 14.3), Vector2(1.6, 13.0)], side, -.10, .25, BODY)
		_closed_loft(builder, Vector3(2.25 * side, -.26, 4.8), [Vector3(-5.5, .78, .65),
			Vector3(-3.2, 1.10, .88), Vector3(7.2, 1.08, .74), Vector3(10.2, .66, .44)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.55 * side, -.20, -2.5), Vector3(1.7, 1.05, 3.0), INTAKE)
		_fin(builder, 2.65 * side, [Vector2(6.8, .42), Vector2(8.7, 4.8),
			Vector2(11.5, 4.3), Vector2(13.8, .32)], .18, side * .16, BODY)


static func _build_mirage3(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-11.5, .66, .62),
		Vector3(-5.5, 1.10, 1.08), Vector3(1, 1.38, 1.32), Vector3(9, 1.18, 1.06),
		Vector3(15, .66, .60), Vector3(17, .24, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.06, -7), [Vector3(-3, .05, .05),
		Vector3(-1.4, .64, .54), Vector3(1.4, .68, .56), Vector3(2.8, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.9, -2.0), Vector2(3.2, -1.2), Vector2(9.3, 5.4),
			Vector2(8.8, 8.4), Vector2(1.1, 6.6)], side, -.20, .20, BODY)
		builder.box(Vector3(1.35 * side, -.15, -2.8), Vector3(.85, .72, 2.4), INTAKE)
	_fin(builder, 0, [Vector2(6.8, .38), Vector2(8.6, 5.4), Vector2(11.5, 4.7),
		Vector2(14.6, .28)], .21, 0, BODY)


static func _build_mirage2000(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-11.5, .72, .66),
		Vector3(-5.5, 1.18, 1.12), Vector3(1, 1.52, 1.38), Vector3(9, 1.30, 1.10),
		Vector3(15, .72, .62), Vector3(17, .25, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.10, -7.2), [Vector3(-3, .05, .05),
		Vector3(-1.4, .68, .55), Vector3(1.4, .72, .57), Vector3(2.8, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.0, -2.4), Vector2(3.5, -1.4), Vector2(10.8, 4.8),
			Vector2(10.4, 8.2), Vector2(6.8, 8.9), Vector2(1.2, 6.2)], side, -.22, .22, BODY)
		builder.box(Vector3(1.45 * side, -.15, -2.7), Vector3(.95, .78, 2.5), INTAKE)
	_fin(builder, 0, [Vector2(6.6, .40), Vector2(8.5, 5.2), Vector2(11.5, 4.6),
		Vector2(14.5, .30)], .21, 0, BODY)


static func _build_q5(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .70, .64),
		Vector3(-6, 1.35, 1.20), Vector3(1, 1.85, 1.50), Vector3(9, 1.62, 1.25),
		Vector3(15, .92, .70), Vector3(17, .28, .24)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -7.2), [Vector3(-3, .05, .05),
		Vector3(-1.4, .72, .58), Vector3(1.4, .76, .60), Vector3(2.8, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.3, -1.8), Vector2(4.2, -1.0), Vector2(10.5, 3.4),
			Vector2(10.1, 6.6), Vector2(6.5, 7.4), Vector2(1.5, 5.0)], side, -.26, .24, BODY)
		_planform(builder, [Vector2(.9, 9.8), Vector2(2.3, 9.6), Vector2(5.2, 12.4),
			Vector2(4.7, 14.5), Vector2(1.0, 13.1)], side, -.10, .22, BODY)
		_closed_loft(builder, Vector3(1.7 * side, -.24, 4.6), [Vector3(-5, .55, .48),
			Vector3(-3, .78, .65), Vector3(6.5, .76, .56), Vector3(9.4, .50, .36)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(1.9 * side, -.16, -2.6), Vector3(1.15, .75, 2.5), INTAKE)
	_fin(builder, 0, [Vector2(7.0, .40), Vector2(8.8, 4.9), Vector2(11.8, 4.3),
		Vector2(14.6, .30)], .21, 0, BODY)


static func _build_su34(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .08, .06), Vector3(-12.5, 1.45, .72),
		Vector3(-6.5, 2.2, 1.30), Vector3(.5, 2.75, 1.55), Vector3(8, 2.55, 1.34),
		Vector3(14.2, 1.50, .78), Vector3(17, .35, .28)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.30, -8.7), [Vector3(-3.2, .08, .05),
		Vector3(-1.6, 1.15, .62), Vector3(1.6, 1.18, .64), Vector3(3.1, .10, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.3, -4.0), Vector2(5.0, -2.5), Vector2(10.7, 3.4),
			Vector2(10.4, 7.0), Vector2(6.7, 8.2), Vector2(2.6, 4.8)], side, -.30, .28, BODY)
		_planform(builder, [Vector2(1.5, 8.8), Vector2(3.2, 8.5), Vector2(6.8, 11.8),
			Vector2(6.2, 14.8), Vector2(1.6, 13.4)], side, -.12, .28, BODY)
		_closed_loft(builder, Vector3(2.35 * side, -.28, 5.2), [Vector3(-6, .82, .68),
			Vector3(-3.6, 1.15, .88), Vector3(7.4, 1.12, .74), Vector3(10.5, .66, .44)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.7 * side, -.20, -2.4), Vector3(1.7, .90, 2.8), INTAKE)
		_fin(builder, 2.75 * side, [Vector2(6.6, .42), Vector2(8.6, 4.8),
			Vector2(11.5, 4.3), Vector2(13.9, .32)], .18, side * .16, BODY)


static func _build_su47(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .82, .70),
		Vector3(-6, 1.65, 1.25), Vector3(1, 2.45, 1.50), Vector3(9, 2.35, 1.30),
		Vector3(15, 1.35, .72), Vector3(17, .32, .26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.22, -7.8), [Vector3(-3.1, .05, .05),
		Vector3(-1.5, .76, .60), Vector3(1.5, .80, .62), Vector3(3, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -1.2), Vector2(5.0, -.2), Vector2(12.55, -5.2),
			Vector2(11.8, -1.8), Vector2(6.0, 7.6), Vector2(2.3, 5.0)], side, -.30, .28, BODY)
		_planform(builder, [Vector2(1.2, -8.5), Vector2(2.1, -8.3), Vector2(5.0, -5.5),
			Vector2(4.5, -3.8), Vector2(1.4, -4.8)], side, .14, .40, BODY)
		_planform(builder, [Vector2(1.8, 8.7), Vector2(3.5, 8.4), Vector2(7.0, 11.8),
			Vector2(6.4, 14.7), Vector2(1.9, 13.3)], side, -.10, .26, BODY)
		_closed_loft(builder, Vector3(2.25 * side, -.25, 5), [Vector3(-5.8, .80, .64),
			Vector3(-3.4, 1.10, .82), Vector3(7.2, 1.08, .68), Vector3(10.3, .64, .42)],
			ENGINE, INTAKE, INTAKE)
		_fin(builder, 2.7 * side, [Vector2(6.6, .40), Vector2(8.5, 4.5),
			Vector2(11.4, 4.0), Vector2(13.8, .30)], .17, side * .18, BODY)


static func _build_su57(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .05), Vector3(-12, 1.0, .62),
		Vector3(-6, 2.5, 1.10), Vector3(1, 3.5, 1.42), Vector3(9, 3.2, 1.18),
		Vector3(15, 1.8, .68), Vector3(17, .38, .24)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.15, -8.2), [Vector3(-3, .05, .05),
		Vector3(-1.4, .82, .54), Vector3(1.5, .86, .56), Vector3(3, .08, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -4.2), Vector2(5.3, -2.6), Vector2(11.9, 4.0),
			Vector2(11.3, 7.7), Vector2(6.0, 8.4), Vector2(2.8, 4.8)], side, -.30, .28, BODY)
		_planform(builder, [Vector2(1.2, -10.2), Vector2(2.6, -7.8), Vector2(5.3, -2.6),
			Vector2(3.8, 1.2), Vector2(1.5, -3.2)], side, -.38, .38, BODY)
		_planform(builder, [Vector2(2.0, 8.8), Vector2(3.7, 8.5), Vector2(7.2, 11.9),
			Vector2(6.5, 14.6), Vector2(2.1, 13.2)], side, -.10, .28, BODY)
		_closed_loft(builder, Vector3(2.4 * side, -.24, 5.1), [Vector3(-6, .84, .62),
			Vector3(-3.5, 1.16, .78), Vector3(7.2, 1.12, .64), Vector3(10.4, .66, .40)],
			ENGINE, INTAKE, INTAKE)
		_fin(builder, 2.9 * side, [Vector2(7, .38), Vector2(9, 4.2),
			Vector2(11.8, 3.7), Vector2(14, .28)], .17, side * .30, BODY)


static func _build_tornado(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-12, .76, .68),
		Vector3(-6, 1.45, 1.28), Vector3(1, 2.05, 1.50), Vector3(9, 1.85, 1.25),
		Vector3(15, 1.08, .72), Vector3(17, .30, .26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -6.8), [Vector3(-4.5, .05, .05),
		Vector3(-2.5, .88, .66), Vector3(2.4, .92, .68), Vector3(4.3, .08, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.5, -1.5), Vector2(4.2, -.8), Vector2(14.15, 3.2),
			Vector2(13.6, 6.5), Vector2(1.8, 5.2)], side, -.26, .24, BODY)
		_planform(builder, [Vector2(1.2, 9.5), Vector2(2.7, 9.2), Vector2(5.8, 12.1),
			Vector2(5.3, 14.4), Vector2(1.3, 13.0)], side, -.10, .24, BODY)
		_closed_loft(builder, Vector3(1.85 * side, -.24, 4.8), [Vector3(-5.5, .62, .52),
			Vector3(-3.2, .88, .72), Vector3(7, .86, .60), Vector3(10, .54, .38)],
			ENGINE, INTAKE, INTAKE)
		builder.box(Vector3(2.2 * side, -.18, -2.4), Vector3(1.4, .90, 2.8), INTAKE)
	_fin(builder, 0, [Vector2(6.8, .42), Vector2(8.7, 5.2), Vector2(11.7, 4.6),
		Vector2(14.6, .32)], .22, 0, BODY)


static func _build_viggen(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .06, .06), Vector3(-11.8, .74, .66),
		Vector3(-5.8, 1.42, 1.22), Vector3(1, 1.90, 1.50), Vector3(9, 1.65, 1.25),
		Vector3(15, .94, .70), Vector3(17, .28, .24)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.24, -7.2), [Vector3(-3.1, .05, .05),
		Vector3(-1.5, .76, .62), Vector3(1.5, .80, .64), Vector3(3, .07, .07)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.4, -1.5), Vector2(4.2, -.5), Vector2(11, 4.6),
			Vector2(10.5, 7.8), Vector2(2.0, 6.3)], side, -.26, .24, BODY)
		_planform(builder, [Vector2(1.1, -6.6), Vector2(2.0, -6.4), Vector2(6.3, -3.0),
			Vector2(5.6, -.8), Vector2(1.3, -3.4)], side, .12, .38, BODY)
		builder.box(Vector3(1.7 * side, -.16, -2.5), Vector3(1.2, .82, 2.6), INTAKE)
	_fin(builder, 0, [Vector2(6.7, .42), Vector2(8.7, 5.4), Vector2(11.6, 4.8),
		Vector2(14.5, .32)], .22, 0, BODY)


## A-12 只有纸面方案；本体是项目解释的宽三角飞翼，不伪造“官方最终三视图”。
static func _build_a12(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15.1, .05, .05), Vector3(-10, .80, .50),
		Vector3(-4, 1.8, .78), Vector3(3, 2.4, .85), Vector3(10, 1.6, .55),
		Vector3(15.1, .30, .18)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.50, -6.5), [Vector3(-2.8, .05, .05),
		Vector3(-1.2, .72, .86), Vector3(1.2, .76, .90), Vector3(2.7, .07, .06)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.8, -10), Vector2(17, 8.5), Vector2(16.2, 12.5),
			Vector2(6, 10.2), Vector2(1, 13.6)], side, -.70, .45, BODY)
		builder.box(Vector3(3.2 * side, -.25, 8.0), Vector3(2.0, .72, 3.0), INTAKE)


## 旋翼在此作为完整四视图资产的一部分；正式运行时须拆出可转动子件后才解除二维旋翼回退。
static func _build_ah64(builder: RefCounted, include_rotors: bool = true) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-16, .05, .05), Vector3(-13, .78, .82),
		Vector3(-8, 1.25, 1.08), Vector3(-2, 1.55, 1.18), Vector3(4, 1.38, 1.02),
		Vector3(10, .48, .50), Vector3(16, .05, .05)], BODY, BODY, ENGINE)
	_closed_loft(builder, Vector3(0, 1.12, -7.8), [Vector3(-4.2, .05, .05),
		Vector3(-2.3, .64, .62), Vector3(.8, .72, .66), Vector3(3.1, .48, .40),
		Vector3(4.2, .05, .05)], CANOPY)
	_closed_loft(builder, Vector3(0, -.15, -14.0), [Vector3(-1.8, .05, .05),
		Vector3(-.8, .62, .60), Vector3(.8, .62, .60), Vector3(1.8, .05, .05)], INTAKE)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.15, -1.0), Vector2(7.0, -.2), Vector2(7.0, 2.0),
			Vector2(1.1, 2.8)], side, -.30, .18, BODY)
		_planform(builder, [Vector2(.25, 10.2), Vector2(2.6, 11.0), Vector2(2.5, 13.0),
			Vector2(.25, 12.2)], side, -.12, .18, BODY)
		_closed_loft(builder, Vector3(1.55 * side, .12, -.2), [Vector3(-3.0, .05, .05),
			Vector3(-1.8, .74, .64), Vector3(2.0, .72, .60), Vector3(3.2, .05, .05)], ENGINE)
	_fin(builder, 0, [Vector2(10.0, .18), Vector2(11.4, 3.5), Vector2(13.4, 3.0),
		Vector2(15.2, .12)], .16, 0, BODY)
	builder.box(Vector3(0, 2.75, 0), Vector3(.55, .72, .55), ENGINE)
	if include_rotors:
		builder.box(Vector3(0, 3.15, 0), Vector3(32.0, .16, .72), ENGINE)
		builder.box(Vector3(0, 3.15, 0), Vector3(.72, .16, 31.6), ENGINE)
		builder.box(Vector3(0, 1.15, 13.5), Vector3(5.4, .16, .18), ENGINE)
		builder.box(Vector3(0, 1.15, 13.5), Vector3(.18, 5.4, .18), ENGINE)
	builder.box(Vector3(0, -1.10, -10.8), Vector3(.52, 1.2, 3.8), INTAKE)


static func _build_ch47(builder: RefCounted, include_rotors: bool = true) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-22, .05, .05), Vector3(-18, 2.3, 2.0),
		Vector3(-11, 3.25, 2.35), Vector3(0, 3.45, 2.50), Vector3(11, 3.30, 2.42),
		Vector3(18, 2.35, 2.0), Vector3(22, .05, .05)], BODY, BODY, ENGINE)
	_closed_loft(builder, Vector3(0, 1.70, -15.5), [Vector3(-4.2, .05, .05),
		Vector3(-2.5, 1.85, 1.0), Vector3(2.2, 1.65, .92), Vector3(4.0, .05, .05)], CANOPY)
	builder.box(Vector3(0, -.15, 1.0), Vector3(5.6, 3.2, 26.0), BODY)
	for side in [-1.0, 1.0]:
		builder.box(Vector3(3.5 * side, -.55, 3.0), Vector3(1.2, 1.25, 12.0), ENGINE)
		builder.box(Vector3(2.9 * side, .25, 10.0), Vector3(1.0, 1.0, 3.0), INTAKE)
	for rotor_z in [-8.5, 8.5]:
		builder.box(Vector3(0, 3.45, rotor_z), Vector3(.72, 1.2, .72), ENGINE)
		if include_rotors:
			builder.box(Vector3(0, 4.08, rotor_z), Vector3(26.75, .16, .70), ENGINE)
			builder.box(Vector3(0, 4.08, rotor_z), Vector3(.70, .16, 20.5), ENGINE)


static func _build_mq109_family(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, 1.05, .62),
		Vector3(-5, 2.0, 1.02), Vector3(3, 2.15, 1.12), Vector3(11, 1.55, .82),
		Vector3(17, .18, .16)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.05, -3.5), [Vector3(-3.0, .05, .05),
		Vector3(-1.2, .72, .55), Vector3(1.4, .68, .50), Vector3(3.0, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.2, -5.0), Vector2(5.0, -3.4), Vector2(15.0, 4.8),
			Vector2(13.2, 8.2), Vector2(5.0, 6.8), Vector2(1.4, 3.6)], side, -.28, .22, BODY)
		_fin(builder, 2.8 * side, [Vector2(8.0, .24), Vector2(10.0, 3.8),
			Vector2(12.8, 3.1), Vector2(14.0, .18)], .15, side * .20, BODY)
		builder.box(Vector3(1.25 * side, -.15, 10.2), Vector3(1.1, .80, 3.2), ENGINE)
	builder.box(Vector3(0, 1.65, -6.0), Vector3(.36, 1.25, 3.6), INTAKE)


static func _build_mq112(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .60, .50),
		Vector3(-6, 1.15, .82), Vector3(0, 1.42, 1.0), Vector3(8, 1.20, .78),
		Vector3(14, .70, .48), Vector3(17, .18, .16)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.0, -4.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .58, .44), Vector3(1.2, .54, .40), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.9, -3.8), Vector2(3.8, -1.8), Vector2(9.0, 4.2),
			Vector2(8.2, 7.0), Vector2(1.1, 4.6)], side, -.25, .20, BODY)
		_fin(builder, 2.0 * side, [Vector2(8.2, .20), Vector2(10.0, 4.2),
			Vector2(12.8, 3.4), Vector2(14.3, .16)], .14, side * .22, BODY)
	builder.box(Vector3(0, -1.05, -3.8), Vector3(.55, .55, 14.0), INTAKE)
	builder.box(Vector3(0, -1.05, -11.0), Vector3(.82, .82, 1.2), ENGINE)
	builder.box(Vector3(0, -.12, 13.6), Vector3(1.45, .78, 3.2), ENGINE)


static func _build_mqx(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15.5, .05, .05), Vector3(-11.5, 1.0, .56),
		Vector3(-6, 2.5, 1.0), Vector3(0, 3.5, 1.42), Vector3(7, 3.2, 1.15),
		Vector3(12.5, 1.8, .65), Vector3(15.5, .30, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -5.0), [Vector3(-3, .05, .05),
		Vector3(-1.3, .74, .62), Vector3(1.3, .70, .56), Vector3(3, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.2, -6.0), Vector2(5.5, -4.0), Vector2(17.0, 3.8),
			Vector2(14.5, 8.2), Vector2(7.2, 7.0), Vector2(2.5, 3.0)], side, -.34, .26, BODY)
		_closed_loft(builder, Vector3(2.4 * side, -.18, 4.2), [Vector3(-4.6, .05, .05),
			Vector3(-2.5, .92, .64), Vector3(4.0, .88, .58), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 3.2 * side, [Vector2(6.2, .24), Vector2(8.0, 4.5),
			Vector2(11.5, 3.8), Vector2(13.4, .18)], .16, side * .24, BODY)


static func _build_aegis_uav(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-12, .05, .05), Vector3(-8.5, .82, .52),
		Vector3(-3, 1.70, .82), Vector3(3, 1.82, .88), Vector3(8.5, 1.10, .56),
		Vector3(12, .18, .16)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.50, -1.8), [Vector3(-2.6, .05, .05),
		Vector3(-.9, .82, .78), Vector3(.9, .82, .78), Vector3(2.5, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.1, -5.8), Vector2(7.0, -3.6), Vector2(17.0, 1.2),
			Vector2(15.0, 5.4), Vector2(6.2, 4.4), Vector2(1.3, 2.0)], side, -.30, .24, BODY)
		builder.box(Vector3(15.6 * side, .36, 2.2), Vector3(1.5, 1.25, 2.2), ENGINE)
		builder.box(Vector3(1.35 * side, -.20, 7.8), Vector3(1.0, .70, 2.8), INTAKE)


static func _build_loyal_wingman(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .72, .48),
		Vector3(-6, 1.35, .78), Vector3(0, 1.72, .96), Vector3(8, 1.55, .78),
		Vector3(14, .82, .42), Vector3(17, .18, .15)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.0, -7.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .58, .46), Vector3(1.2, .54, .42), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.0, -3.0), Vector2(4.2, -1.5), Vector2(13.0, 6.0),
			Vector2(11.8, 8.6), Vector2(1.2, 4.3)], side, -.24, .20, BODY)
		_fin(builder, 2.1 * side, [Vector2(9.0, .20), Vector2(11.0, 4.0),
			Vector2(13.8, 3.4), Vector2(15.0, .16)], .14, side * .22, BODY)
		builder.box(Vector3(11.8 * side, .08, 7.0), Vector3(1.1, .55, 1.4), ENGINE)
	builder.box(Vector3(0, 1.80, -.8), Vector3(.65, 1.0, 4.2), INTAKE)
	builder.box(Vector3(0, -.12, 14.2), Vector3(1.4, .78, 2.6), ENGINE)


static func _build_probe(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, .05, .05), Vector3(-11, 1.20, 1.05),
		Vector3(-5, 1.75, 1.48), Vector3(0, 1.85, 1.55), Vector3(6, 1.55, 1.25),
		Vector3(12, .82, .65), Vector3(15, .18, .16)], BODY, BODY, ENGINE)
	_closed_loft(builder, Vector3(0, .95, -9.5), [Vector3(-2.0, .05, .05),
		Vector3(-.75, .92, .82), Vector3(.75, .92, .82), Vector3(2.0, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.0, -1.5), Vector2(11.0, -.2), Vector2(10.8, 2.4),
			Vector2(1.1, 3.4)], side, -.24, .22, BODY)
		_planform(builder, [Vector2(.7, 8.8), Vector2(4.5, 9.2), Vector2(4.3, 11.2),
			Vector2(.8, 10.8)], side, -.12, .18, BODY)
	_fin(builder, 0, [Vector2(7.8, .24), Vector2(9.2, 4.2), Vector2(11.8, 3.7),
		Vector2(13.8, .16)], .18, 0, BODY)
	builder.box(Vector3(0, 2.35, -1.5), Vector3(5.0, .18, .38), ENGINE)
	builder.box(Vector3(0, 2.35, -1.5), Vector3(.38, .18, 5.0), ENGINE)


static func _build_faxx(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-16, .05, .05), Vector3(-11.5, .92, .58),
		Vector3(-6, 2.3, 1.02), Vector3(0, 3.2, 1.34), Vector3(7, 2.9, 1.16),
		Vector3(12.8, 1.55, .64), Vector3(16, .30, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.20, -6.4), [Vector3(-3.0, .05, .05),
		Vector3(-1.2, .72, .58), Vector3(1.3, .68, .54), Vector3(3.0, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -5.0), Vector2(5.2, -3.0), Vector2(15.2, 3.4),
			Vector2(14.0, 7.2), Vector2(6.2, 6.5), Vector2(2.3, 3.0)], side, -.32, .26, BODY)
		_planform(builder, [Vector2(14.0, 7.2), Vector2(17.0, 6.2), Vector2(16.2, 9.0),
			Vector2(12.8, 8.8)], side, -.26, .20, BODY)
		_closed_loft(builder, Vector3(2.3 * side, -.20, 4.5), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .88, .62), Vector3(4.0, .84, .56), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 3.0 * side, [Vector2(7.0, .22), Vector2(8.8, 4.2),
			Vector2(11.8, 3.6), Vector2(13.5, .16)], .15, side * .22, BODY)


static func _build_fcas(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, .05, .05), Vector3(-10.5, .92, .54),
		Vector3(-5.0, 2.15, .92), Vector3(0, 3.35, 1.20), Vector3(6.0, 3.0, 1.0),
		Vector3(11.8, 1.6, .55), Vector3(15, .28, .20)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.16, -5.8), [Vector3(-2.8, .05, .05),
		Vector3(-1.1, .72, .52), Vector3(1.2, .68, .48), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.8, -5.0), Vector2(5.2, -3.4), Vector2(17.0, 3.0),
			Vector2(15.0, 7.2), Vector2(9.0, 8.7), Vector2(4.0, 5.0), Vector2(2.0, 2.0)],
			side, -.34, .25, BODY)
		builder.box(Vector3(1.8 * side, -.20, 7.3), Vector3(1.25, .72, 3.4), ENGINE)
	builder.box(Vector3(0, 1.75, -.4), Vector3(.72, 1.0, 5.6), INTAKE)


static func _build_gcap(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .94, .58),
		Vector3(-6, 2.25, 1.02), Vector3(0, 3.0, 1.32), Vector3(8, 2.75, 1.10),
		Vector3(14, 1.55, .62), Vector3(17, .30, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.28, -6.8), [Vector3(-3.6, .05, .05),
		Vector3(-2.0, .82, .66), Vector3(1.7, .86, .68), Vector3(3.3, .62, .48),
		Vector3(4.0, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -4.6), Vector2(5.0, -2.8), Vector2(16.0, 4.2),
			Vector2(14.6, 8.0), Vector2(6.2, 7.0), Vector2(2.2, 3.4)], side, -.32, .26, BODY)
		_closed_loft(builder, Vector3(2.4 * side, -.18, 4.7), [Vector3(-4.8, .05, .05),
			Vector3(-2.8, .90, .64), Vector3(4.2, .88, .58), Vector3(6.2, .05, .05)], ENGINE)
		_fin(builder, 3.2 * side, [Vector2(7.4, .22), Vector2(9.4, 4.8),
			Vector2(12.4, 4.0), Vector2(14.0, .16)], .16, side * .22, BODY)


static func _build_j36(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-16.5, .05, .05), Vector3(-11.5, 1.1, .58),
		Vector3(-5, 2.6, 1.0), Vector3(1, 3.8, 1.28), Vector3(8, 3.4, 1.02),
		Vector3(13.5, 1.8, .58), Vector3(16.5, .32, .20)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.16, -6.0), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .66, .50), Vector3(1.1, .62, .46), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.2, -5.0), Vector2(6.0, -3.0), Vector2(17.0, 3.8),
			Vector2(15.5, 7.6), Vector2(10.0, 9.2), Vector2(4.0, 6.0), Vector2(2.4, 2.5)],
			side, -.35, .24, BODY)
		builder.box(Vector3(3.0 * side, -.34, 3.0), Vector3(1.4, .72, 4.4), INTAKE)
	for engine_x in [-2.3, 0.0, 2.3]:
		builder.box(Vector3(engine_x, -.18, 12.0), Vector3(1.45, .82, 5.0), ENGINE)
	builder.box(Vector3(0, 1.62, -.5), Vector3(.65, .82, 4.8), INTAKE)


static func _build_mig41(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-13.8, .62, .46),
		Vector3(-9, 1.25, .80), Vector3(-3, 1.9, 1.18), Vector3(4, 2.2, 1.30),
		Vector3(10, 2.05, 1.08), Vector3(15, 1.05, .55), Vector3(17, .24, .18)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -7.2), [Vector3(-3.8, .05, .05),
		Vector3(-2.0, .72, .58), Vector3(1.8, .76, .60), Vector3(3.4, .48, .38),
		Vector3(4.2, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.7, -.5), Vector2(4.2, .2), Vector2(10.0, 4.2),
			Vector2(9.4, 7.0), Vector2(2.0, 5.2)], side, -.28, .23, BODY)
		_planform(builder, [Vector2(1.3, 9.0), Vector2(3.0, 9.2), Vector2(5.2, 12.2),
			Vector2(4.8, 14.3)], side, -.14, .20, BODY)
		_closed_loft(builder, Vector3(2.0 * side, -.22, 5.2), [Vector3(-5.0, .05, .05),
			Vector3(-2.8, 1.0, .72), Vector3(4.8, .98, .64), Vector3(7.0, .05, .05)], ENGINE)
		_fin(builder, 2.7 * side, [Vector2(7.2, .24), Vector2(9.0, 4.8),
			Vector2(12.0, 4.2), Vector2(14.2, .18)], .16, side * .20, BODY)
		builder.box(Vector3(2.25 * side, -.20, -1.2), Vector3(1.45, .95, 3.5), INTAKE)


static func _build_af03(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12.5, .72, .48),
		Vector3(-6, 1.45, .92), Vector3(0, 2.2, 1.24), Vector3(8, 2.0, 1.0),
		Vector3(14, 1.0, .52), Vector3(17, .22, .18)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.12, -6.8), [Vector3(-2.8, .05, .05),
		Vector3(-1.1, .68, .54), Vector3(1.2, .64, .50), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.5, -2.0), Vector2(4.0, -1.0), Vector2(11.0, 4.2),
			Vector2(10.2, 7.0), Vector2(1.8, 5.2)], side, -.27, .22, BODY)
		_closed_loft(builder, Vector3(1.8 * side, -.20, 5.0), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .78, .58), Vector3(4.2, .76, .52), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 2.6 * side, [Vector2(7.6, .22), Vector2(9.4, 4.4),
			Vector2(12.0, 3.8), Vector2(14.0, .16)], .15, side * .18, BODY)
	builder.box(Vector3(0, -1.05, -3.8), Vector3(.62, .62, 15.0), INTAKE)
	builder.box(Vector3(0, -1.05, -11.6), Vector3(.92, .86, 1.4), ENGINE)


static func _build_ax00(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .92, .58),
		Vector3(-6, 2.2, 1.0), Vector3(0, 3.1, 1.34), Vector3(8, 2.8, 1.12),
		Vector3(14, 1.45, .60), Vector3(17, .30, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.25, -6.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .70, .58), Vector3(1.2, .68, .54), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.8, -3.2), Vector2(6.0, -5.0), Vector2(17.0, 2.0),
			Vector2(13.0, 7.5), Vector2(6.0, 5.5), Vector2(2.0, 2.8)], side, -.34, .28, BODY)
		_planform(builder, [Vector2(1.0, -9.0), Vector2(5.2, -7.0), Vector2(4.6, -4.5),
			Vector2(1.2, -5.8)], side, -.10, .30, BODY)
		_closed_loft(builder, Vector3(2.2 * side, -.18, 4.7), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .88, .62), Vector3(4.0, .84, .56), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 3.0 * side, [Vector2(7.0, .22), Vector2(8.8, 4.4),
			Vector2(11.8, 3.7), Vector2(13.8, .16)], .15, side * .25, BODY)
	builder.box(Vector3(0, 1.82, -.4), Vector3(.75, .9, 4.6), CANOPY)


static func _build_orion_final_form(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-18, .05, .05), Vector3(-13, .8, .45),
		Vector3(-7, 2.0, 1.0), Vector3(0, 3.2, 1.4), Vector3(8, 3.0, 1.1),
		Vector3(14, 2.2, .7), Vector3(18, .5, .25)], BODY, BODY, INTAKE)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, 1), Vector2(22, -9), Vector2(20, -4),
			Vector2(11, 4), Vector2(5, 8), Vector2(2.5, 6)], side, -.3, .4, BODY)
		_planform(builder, [Vector2(1, -10), Vector2(7, -13), Vector2(6, -10),
			Vector2(1.8, -7)], side, -.1, .25, BODY)
		builder.box(Vector3(side * 2, -.2, 13), Vector3(2, 1, 6), ENGINE)
		builder.box(Vector3(side * 2.2, .6, -8), Vector3(.5, .45, 11), INTAKE)
		_fin(builder, side * 3, [Vector2(7, .3), Vector2(10, 3), Vector2(15, 2),
			Vector2(16, .3)], .15, side * .4, BODY)
		for hatch in range(4):
			builder.box(Vector3(side * 1.7, 1.3, -1 + hatch * 2.4), Vector3(.8, .18, 1.5), INTAKE)


static func _build_orion_far_lod(fang: bool) -> ArrayMesh:
	# 前掠翼与无尾飞翼的凹轮廓必须保留，不能退成整个机体的凸包。
	var builder := Factory.new()
	if fang:
		builder.prism(PackedVector2Array([Vector2(0, -7), Vector2(3, 0), Vector2(2.3, 4),
			Vector2(0, 7), Vector2(-2.3, 4), Vector2(-3, 0)]), -1.6, 1.6, BODY)
	else:
		builder.prism(PackedVector2Array([Vector2(0, -18), Vector2(2, -7), Vector2(3, 8),
			Vector2(2.2, 14), Vector2(0, 18), Vector2(-2.2, 14), Vector2(-3, 8),
			Vector2(-2, -7)]), -1.4, 1.4, BODY)
	for side in [-1.0, 1.0]:
		if fang:
			_planform(builder, [Vector2(1.2, -4), Vector2(9, 1), Vector2(8.7, 3),
				Vector2(5, 3.3), Vector2(3.1, 5.5), Vector2(1.2, 3)], side, -.18, .2, BODY)
		else:
			_planform(builder, [Vector2(2.5, 1), Vector2(22, -9), Vector2(20, -4),
				Vector2(11, 4), Vector2(5, 8), Vector2(2.5, 6)], side, -.3, .4, BODY)
			_planform(builder, [Vector2(1, -10), Vector2(7, -13), Vector2(6, -10),
				Vector2(1.8, -7)], side, -.1, .25, BODY)
	return builder.mesh()


static func _build_orion_fang(builder: RefCounted) -> void:
	# 参考无尾飞翼的宽体与折线后缘；高度来自中央机腹，不添加垂尾。
	_closed_loft(builder, Vector3.ZERO, [Vector3(-7, .05, .05), Vector3(-3, 2.1, .8),
		Vector3(0, 3.0, 1.6), Vector3(4, 2.3, .7), Vector3(7, .2, .15)], BODY, INTAKE, ENGINE)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.2, -4), Vector2(9, 1), Vector2(8.7, 3),
			Vector2(5, 3.3), Vector2(3.1, 5.5), Vector2(1.2, 3)], side, -.18, .2, BODY)
		builder.box(Vector3(side * 1.4, .7, 2.5), Vector3(.7, .4, 3), INTAKE)
		builder.box(Vector3(side * .65, -.15, 4.7), Vector3(.6, .5, 2), ENGINE)
	builder.box(Vector3(0, .5, -4.0), Vector3(.35, .35, 4), INTAKE)


static func _build_cre(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12.5, .72, .54),
		Vector3(-6.5, 1.35, .92), Vector3(0, 1.95, 1.22), Vector3(8, 1.75, .98),
		Vector3(14, .92, .50), Vector3(17, .22, .18)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -7.0), [Vector3(-3.5, .05, .05),
		Vector3(-1.8, .75, .60), Vector3(1.5, .78, .62), Vector3(3.0, .54, .42),
		Vector3(3.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.8, -9.0), Vector2(4.2, -7.2), Vector2(3.8, -4.5),
			Vector2(1.0, -5.5)], side, -.10, .32, BODY)
		_planform(builder, [Vector2(1.4, -1.2), Vector2(4.2, -.2), Vector2(14.0, 5.0),
			Vector2(12.8, 8.0), Vector2(6.0, 7.0), Vector2(1.7, 4.2)], side, -.28, .24, BODY)
		_planform(builder, [Vector2(1.0, 9.0), Vector2(4.8, 10.0), Vector2(4.4, 13.0),
			Vector2(1.2, 11.8)], side, -.12, .20, BODY)
	builder.box(Vector3(0, -.15, 11.8), Vector3(1.6, .86, 4.2), ENGINE)
	_fin(builder, 0, [Vector2(7.2, .22), Vector2(9.0, 4.8), Vector2(12.0, 4.0),
		Vector2(14.2, .16)], .18, 0, BODY)


static func _build_deadair(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, .05, .05), Vector3(-10, 1.05, .62),
		Vector3(-3, 2.3, 1.0), Vector3(4, 2.15, .92), Vector3(11, 1.15, .54),
		Vector3(15, .18, .16)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.35, -1.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .86, .78), Vector3(1.0, .86, .78), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.2, -4.2), Vector2(17.0, 1.8), Vector2(10.0, 7.2),
			Vector2(1.4, 3.8)], side, -.32, .24, BODY)
		_planform(builder, [Vector2(7.0, -.2), Vector2(13.5, 1.8), Vector2(9.0, 5.2),
			Vector2(4.5, 2.2)], side, .24, .52, INTAKE)
		builder.box(Vector3(10.5 * side, .72, 2.5), Vector3(1.3, 1.6, 1.3), ENGINE)
	builder.box(Vector3(0, 2.35, -1.2), Vector3(.62, 1.2, 3.8), INTAKE)


static func _build_sentinel(builder: RefCounted) -> void:
	var wing := PackedVector2Array([Vector2(0, -12.0), Vector2(4.0, -8.5),
		Vector2(17.0, -1.0), Vector2(15.5, 4.5), Vector2(7.0, 5.5), Vector2(2.5, 12.0),
		Vector2(0, 10.5), Vector2(-2.5, 12.0), Vector2(-7.0, 5.5), Vector2(-15.5, 4.5),
		Vector2(-17.0, -1.0), Vector2(-4.0, -8.5)])
	builder.prism(wing, -.45, .38, BODY)
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, .05, .05), Vector3(-10, 1.25, .62),
		Vector3(-3, 2.1, .90), Vector3(4, 2.0, .82), Vector3(11, 1.05, .45),
		Vector3(15, .18, .14)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.50, -2.0), [Vector3(-2.5, .05, .05),
		Vector3(-.9, .82, .75), Vector3(.9, .82, .75), Vector3(2.5, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		builder.box(Vector3(14.8 * side, .50, .6), Vector3(1.4, 1.45, 2.4), ENGINE)
		_fin(builder, 3.0 * side, [Vector2(6.0, .20), Vector2(8.0, 4.0),
			Vector2(10.5, 3.4), Vector2(12.0, .15)], .15, side * .24, BODY)


static func _build_snowblind(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-16, .05, .05), Vector3(-11, .88, .62),
		Vector3(-4, 1.8, 1.05), Vector3(4, 1.9, 1.0), Vector3(12, 1.05, .54),
		Vector3(16, .18, .15)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.35, -2.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .84, .80), Vector3(1.0, .84, .80), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.1, -5.0), Vector2(7.0, -3.0), Vector2(17.0, 1.0),
			Vector2(13.0, 4.5), Vector2(7.0, 4.0), Vector2(1.3, 2.0)], side, -.30, .22, BODY)
		_planform(builder, [Vector2(6.0, -2.5), Vector2(13.0, -5.2), Vector2(11.0, .2),
			Vector2(7.0, 2.0)], side, .20, .45, ENGINE)
		builder.box(Vector3(2.0 * side, -.18, 9.5), Vector3(1.2, .75, 3.2), INTAKE)
	_fin(builder, 0, [Vector2(7.0, .22), Vector2(9.0, 4.5), Vector2(12.0, 3.8),
		Vector2(14.0, .16)], .18, 0, BODY)
	builder.box(Vector3(0, 2.45, -2.0), Vector3(.55, 1.25, 4.0), ENGINE)


static func _build_hyper_a(builder: RefCounted) -> void:
	var wedge := PackedVector2Array([Vector2(0, -17.0), Vector2(4.2, -12.5),
		Vector2(10.0, -2.6), Vector2(8.8, 9.0), Vector2(5.2, 16.0), Vector2(0, 17.0),
		Vector2(-5.2, 16.0), Vector2(-8.8, 9.0), Vector2(-10.0, -2.6), Vector2(-4.2, -12.5)])
	builder.prism(wedge, -1.0, 1.0, WING_BODY)
	_closed_loft(builder, Vector3(0, -.10, 8.5), [Vector3(-4.0, .05, .05),
		Vector3(-2.0, 1.25, .70), Vector3(2.0, 1.20, .64), Vector3(4.0, .05, .05)], ENGINE)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -11.0), Vector2(8.8, -1.0), Vector2(8.0, 2.0),
			Vector2(2.5, -7.0)], side, .95, 1.28, ENGINE)
	builder.box(Vector3(0, 1.45, -3.0), Vector3(.65, .9, 8.0), ENGINE)
	builder.box(Vector3(0, -1.35, 2.0), Vector3(.75, .9, 12.0), INTAKE)


static func _build_mother_goose(builder: RefCounted) -> void:
	var wing := PackedVector2Array([Vector2(0, -64.8), Vector2(28.8, -50.4),
		Vector2(201.6, 7.2), Vector2(223.2, 31.68), Vector2(172.8, 43.2), Vector2(79.2, 40.32),
		Vector2(43.2, 72.0), Vector2(14.4, 79.2), Vector2(0, 64.8), Vector2(-14.4, 79.2),
		Vector2(-43.2, 72.0), Vector2(-79.2, 40.32), Vector2(-172.8, 43.2),
		Vector2(-223.2, 31.68), Vector2(-201.6, 7.2), Vector2(-28.8, -50.4)])
	builder.prism(wing, -4.0, 4.0, WING_BODY)
	_closed_loft(builder, Vector3.ZERO, [Vector3(-64, .2, .2), Vector3(-42, 22, 8),
		Vector3(-18, 31, 13), Vector3(10, 34, 17), Vector3(48, 26, 9), Vector3(76, .2, .2)],
		BODY, BODY, ENGINE)
	_closed_loft(builder, Vector3(0, 21, -14), [Vector3(-20, .2, .2), Vector3(-7, 17, 7),
		Vector3(14, 14, 6), Vector3(24, .2, .2)], CANOPY)
	for x in [-172.8, -108.0, -43.2, 43.2, 108.0, 172.8]:
		builder.box(Vector3(x, 6, -7), Vector3(20, 12, 42), ENGINE)
	for side in [-1.0, 1.0]:
		builder.box(Vector3(30.0 * side, 16, 47), Vector3(2.5, 24, 28), BODY)
	builder.box(Vector3(0, 19, -8), Vector3(4.0, 14, 52), INTAKE)


static func _build_x02(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .88, .56),
		Vector3(-6, 1.8, .96), Vector3(0, 2.5, 1.28), Vector3(8, 2.3, 1.06),
		Vector3(14, 1.2, .54), Vector3(17, .26, .20)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.18, -6.8), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .68, .56), Vector3(1.2, .64, .50), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.8, -1.5), Vector2(5.0, -.2), Vector2(17.0, 7.0),
			Vector2(14.0, 9.2), Vector2(6.5, 6.0), Vector2(2.0, 3.6)], side, -.28, .24, BODY)
		_planform(builder, [Vector2(.9, -9.2), Vector2(5.2, -7.0), Vector2(4.8, -4.4),
			Vector2(1.1, -5.8)], side, -.10, .30, BODY)
		_closed_loft(builder, Vector3(2.1 * side, -.20, 5.0), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .84, .60), Vector3(4.0, .82, .54), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 2.9 * side, [Vector2(7.2, .22), Vector2(9.2, 4.5),
			Vector2(12.2, 3.8), Vector2(14.0, .16)], .15, side * .22, BODY)
	builder.box(Vector3(0, -1.02, -3.2), Vector3(.60, .62, 14.0), INTAKE)


static func _build_x09(builder: RefCounted) -> void:
	var owl_wing := PackedVector2Array([Vector2(0, -15.0), Vector2(5.0, -10.5),
		Vector2(17.0, -2.0), Vector2(15.5, 4.0), Vector2(10.5, 7.0), Vector2(5.0, 12.5),
		Vector2(0, 10.0), Vector2(-5.0, 12.5), Vector2(-10.5, 7.0), Vector2(-15.5, 4.0),
		Vector2(-17.0, -2.0), Vector2(-5.0, -10.5), Vector2(-2.0, -13.5), Vector2(2.0, -13.5)])
	builder.prism(owl_wing, -.48, .42, BODY)
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, .05, .05), Vector3(-10, 1.15, .62),
		Vector3(-3, 2.0, .96), Vector3(4, 1.9, .86), Vector3(11, 1.0, .45),
		Vector3(15, .18, .14)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.48, -3.0), [Vector3(-2.5, .05, .05),
		Vector3(-.8, .78, .72), Vector3(.8, .78, .72), Vector3(2.5, .05, .05)], CANOPY)
	for x in [-4.0, -1.35, 1.35, 4.0]:
		builder.box(Vector3(x, -.22, 9.0), Vector3(1.1, .72, 3.0), ENGINE)
	for side in [-1.0, 1.0]:
		_fin(builder, 3.6 * side, [Vector2(6.0, .20), Vector2(8.0, 3.8),
			Vector2(10.5, 3.2), Vector2(12.0, .15)], .14, side * .24, BODY)


static func _build_x13(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-12, .88, .56),
		Vector3(-6, 1.75, .98), Vector3(0, 2.5, 1.30), Vector3(8, 2.3, 1.08),
		Vector3(14, 1.2, .56), Vector3(17, .26, .20)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.20, -6.6), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .70, .58), Vector3(1.2, .66, .52), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(.9, -9.0), Vector2(5.0, -6.8), Vector2(4.5, -4.2),
			Vector2(1.1, -5.6)], side, -.10, .30, BODY)
		_planform(builder, [Vector2(1.6, -2.0), Vector2(5.0, -.8), Vector2(16.0, 5.0),
			Vector2(14.0, 8.5), Vector2(6.0, 7.0), Vector2(1.9, 4.0)], side, -.30, .24, BODY)
		_closed_loft(builder, Vector3(2.1 * side, -.20, 5.0), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .84, .60), Vector3(4.0, .82, .54), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 2.9 * side, [Vector2(7.0, .22), Vector2(9.0, 4.5),
			Vector2(12.0, 3.8), Vector2(14.0, .16)], .15, side * .22, BODY)
		builder.box(Vector3(14.7 * side, .30, 5.8), Vector3(1.5, 1.1, 2.4), ENGINE)
	builder.box(Vector3(0, 1.78, -.5), Vector3(.70, .92, 5.0), INTAKE)


static func _build_x21(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-14, .55, .42),
		Vector3(-10, 1.0, .72), Vector3(-4, 1.55, 1.08), Vector3(3, 1.75, 1.30),
		Vector3(9, 1.62, 1.0), Vector3(14.5, .82, .48), Vector3(17, .20, .16)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.20, -7.5), [Vector3(-3.0, .05, .05),
		Vector3(-1.0, .66, .58), Vector3(1.1, .62, .52), Vector3(3.0, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.4, -.5), Vector2(3.5, .2), Vector2(9.0, 4.0),
			Vector2(8.5, 6.5), Vector2(1.7, 4.8)], side, -.25, .20, BODY)
		_planform(builder, [Vector2(1.0, 9.2), Vector2(3.5, 9.8), Vector2(4.8, 12.8),
			Vector2(1.2, 11.8)], side, -.12, .18, BODY)
		_closed_loft(builder, Vector3(1.75 * side, -.18, 5.3), [Vector3(-5.0, .05, .05),
			Vector3(-2.8, .82, .58), Vector3(4.8, .80, .52), Vector3(7.0, .05, .05)], ENGINE)
		_fin(builder, 2.6 * side, [Vector2(7.5, .22), Vector2(9.2, 4.5),
			Vector2(12.0, 3.8), Vector2(14.2, .16)], .15, side * .18, BODY)
		builder.box(Vector3(4.2 * side, -.90, 1.8), Vector3(1.0, .70, 8.0), INTAKE)


static func _build_x44(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-16, .05, .05), Vector3(-12, 1.25, .90),
		Vector3(-5, 2.7, 1.45), Vector3(2, 3.5, 1.60), Vector3(9, 3.2, 1.40),
		Vector3(14, 1.7, .82), Vector3(16, .35, .26)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.45, -5.8), [Vector3(-3.5, .05, .05),
		Vector3(-1.8, 1.05, .82), Vector3(1.6, 1.08, .84), Vector3(3.0, .76, .58),
		Vector3(3.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -2.0), Vector2(17.0, -.2), Vector2(16.0, 4.8),
			Vector2(2.7, 5.2)], side, -.48, .35, BODY)
		_planform(builder, [Vector2(2.0, 8.0), Vector2(8.0, 9.8), Vector2(7.2, 13.0),
			Vector2(2.2, 11.8)], side, -.20, .28, BODY)
		_closed_loft(builder, Vector3(3.1 * side, -.10, 4.0), [Vector3(-5.0, .05, .05),
			Vector3(-3.0, 1.55, 1.05), Vector3(0, 1.75, 1.18), Vector3(4.5, 1.55, .96),
			Vector3(6.5, .05, .05)], ENGINE)
		_fin(builder, 3.8 * side, [Vector2(6.8, .28), Vector2(8.6, 5.2),
			Vector2(12.0, 4.5), Vector2(13.8, .20)], .20, side * .16, BODY)
	for gun_x in [-5.0, 0.0, 5.0]:
		builder.box(Vector3(gun_x, -.95, -5.0), Vector3(.72, .72, 5.5), INTAKE)


static func _build_x77(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15.5, .05, .05), Vector3(-11, .90, .48),
		Vector3(-5, 2.2, .86), Vector3(1, 3.2, 1.18), Vector3(7, 2.9, .96),
		Vector3(12.5, 1.45, .50), Vector3(15.5, .28, .18)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.30, -5.2), [Vector3(-2.8, .05, .05),
		Vector3(-1.0, .78, .62), Vector3(1.1, .74, .56), Vector3(2.8, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.0, -6.0), Vector2(6.0, -4.0), Vector2(17.0, 2.0),
			Vector2(15.2, 6.2), Vector2(10.0, 8.5), Vector2(5.0, 6.4), Vector2(2.2, 2.5)],
			side, -.34, .24, BODY)
		_closed_loft(builder, Vector3(2.3 * side, -.22, 4.2), [Vector3(-4.5, .05, .05),
			Vector3(-2.4, .88, .58), Vector3(4.0, .84, .50), Vector3(6.0, .05, .05)], ENGINE)
		_fin(builder, 3.0 * side, [Vector2(7.0, .18), Vector2(8.5, 3.5),
			Vector2(11.0, 3.0), Vector2(12.8, .14)], .13, side * .28, BODY)


static func _build_x90(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, .05, .05), Vector3(-13, 1.25, .82),
		Vector3(-8, 2.8, 1.35), Vector3(-2, 4.0, 1.85), Vector3(5, 4.3, 2.0),
		Vector3(10, 3.7, 1.65), Vector3(15, 1.8, .82), Vector3(17, .32, .22)], BODY, BODY, INTAKE)
	_closed_loft(builder, Vector3(0, 1.75, -6.0), [Vector3(-3.2, .05, .05),
		Vector3(-1.3, .92, .72), Vector3(1.3, .88, .68), Vector3(3.2, .05, .05)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(3.0, -4.0), Vector2(7.0, -2.5), Vector2(17.0, 2.0),
			Vector2(16.0, 7.5), Vector2(8.0, 8.5), Vector2(3.2, 4.5)], side, -.50, .38, BODY)
		_fin(builder, 4.5 * side, [Vector2(7.0, .26), Vector2(9.0, 5.0),
			Vector2(12.5, 4.2), Vector2(14.5, .18)], .18, side * .20, BODY)
	for engine_x in [-5.6, -2.0, 2.0, 5.6]:
		builder.box(Vector3(engine_x, -.25, 7.0), Vector3(1.5, 1.0, 5.0), ENGINE)
	for bay_x in [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]:
		builder.box(Vector3(bay_x, -1.65, 1.0), Vector3(1.4, .45, 5.2), INTAKE)
	builder.box(Vector3(0, 2.45, .4), Vector3(1.0, 1.0, 6.0), CANOPY)


static func _planform(builder: RefCounted, points: Array, side: float,
		bottom: float, top: float, color: Color) -> void:
	var mirrored := PackedVector2Array()
	for point: Vector2 in points:
		mirrored.append(Vector2(point.x * side, point.y))
	var wing_color := color
	wing_color.a = 0.5
	builder.prism(mirrored, bottom, top, wing_color)


## 两端封口，避免斜视/大滚转透进空壳；所有端截面保留非零半径，无退化三角形。
static func _closed_loft(builder: RefCounted, center: Vector3, rings: Array, color: Color,
		front_color: Color = Color.TRANSPARENT, back_color: Color = Color.TRANSPARENT) -> void:
	builder.loft(center, rings, color)
	_cap_ring(builder, center, rings[0], true, front_color if front_color.a > 0.0 else color)
	_cap_ring(builder, center, rings[-1], false, back_color if back_color.a > 0.0 else color)


static func _cap_ring(builder: RefCounted, center: Vector3, ring: Vector3,
		front: bool, color: Color) -> void:
	var origin := center + Vector3(0, 0, ring.x)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var next_angle := TAU * float(index + 1) / 8.0
		var a := origin + Vector3(cos(angle) * ring.y, sin(angle) * ring.z, 0)
		var b := origin + Vector3(cos(next_angle) * ring.y, sin(next_angle) * ring.z, 0)
		if front:
			builder.triangle(origin, b, a, color)
		else:
			builder.triangle(origin, a, b, color)


## 侧面轮廓坐标为 (Z, Y)。整体外倾，但两侧仍有真实厚度及封闭边缘。
static func _fin(builder: RefCounted, x: float, points: Array,
		half_thickness: float, lean: float, color: Color) -> void:
	var outline := PackedVector2Array(points)
	var indices := Geometry2D.triangulate_polygon(outline)
	var centroid := Vector2.ZERO
	for point: Vector2 in points:
		centroid += point
	centroid /= float(points.size())
	for side in [-1.0, 1.0]:
		for index in range(0, indices.size(), 3):
			var vertices: Array[Vector3] = []
			for offset in 3:
				var point := outline[indices[index + offset]]
				vertices.append(Vector3(x + side * half_thickness + lean * point.y, point.y, point.x))
			_outward_triangle(builder, vertices[0], vertices[1], vertices[2], Vector3.RIGHT * side, color)
	for index in outline.size():
		var p := outline[index]
		var q := outline[(index + 1) % outline.size()]
		var a := Vector3(x - half_thickness + lean * p.y, p.y, p.x)
		var b := Vector3(x - half_thickness + lean * q.y, q.y, q.x)
		var c := b + Vector3.RIGHT * half_thickness * 2.0
		var d := a + Vector3.RIGHT * half_thickness * 2.0
		var outward := Vector3(0, (p.y + q.y) * 0.5 - centroid.y, (p.x + q.x) * 0.5 - centroid.x)
		_outward_triangle(builder, a, b, c, outward, color)
		_outward_triangle(builder, a, c, d, outward, color)


static func _outward_triangle(builder: RefCounted, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		builder.triangle(a, c, b, color)
	else:
		builder.triangle(a, b, c, color)
