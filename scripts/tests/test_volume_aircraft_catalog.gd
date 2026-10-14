extends RefCounted
## 首批低模资产的纯几何门；不冒充 Visual 观感与战斗帧率验收。

const Catalog := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const Mounts := preload("res://scripts/experiments/volume_aircraft_mount_catalog.gd")
const Silhouettes := preload("res://scripts/aircraft_silhouette_catalog.gd")


static func run() -> bool:
	var failures: Array[String] = []
	var signatures: Array[int] = []
	var shared_material: Material
	var wing_livery_keys := ["f14", "fa18", "yf23", "mq109_family", "mq112", "mqx",
		"aegis_uav", "af03", "deadair", "hyper_a", "mother_goose", "x02"]
	var keys := Catalog.supported_keys()
	_expect(keys == ["f14", "a10", "f47", "f104", "f15", "f16", "f22", "f35", "yf23", "tu160", "b1b",
		"f4", "f86", "f100", "fa18", "mig29", "su27", "rafale", "typhoon",
		"a6e", "a7", "ea6b", "f15smtd", "fa18e", "fck1", "gripen", "harrier",
		"j20", "j35f", "j7", "jaguar", "mig21f13", "mig23", "mig31", "mirage3",
		"mirage2000", "q5", "su34", "su47", "su57", "tornado", "viggen", "a12",
		"ah64", "ch47", "mq109_family", "mq112", "mqx", "aegis_uav", "loyal_wingman", "probe",
		"faxx", "fcas", "gcap", "j36", "mig41", "af03", "ax00", "cre",
		"deadair", "sentinel", "snowblind", "hyper_a", "mother_goose", "x02", "x09", "x13",
		"x21", "x44", "x77", "x90", "orion_final_form", "orion_fang"],
		"已制作 key 清单确定且没有伪造全量覆盖", failures)
	var canonical_keys: Array[String] = Silhouettes.canonical_model_keys()
	var sorted_canonical_keys := canonical_keys.duplicate()
	sorted_canonical_keys.sort()
	_expect(not canonical_keys.is_empty() and canonical_keys == sorted_canonical_keys,
		"规范三维 key 可稳定枚举且不依赖历史固定总数", failures)
	for produced_key in keys:
		_expect(produced_key in canonical_keys, "%s 属于当前运行时身份矩阵" % produced_key, failures)
	for kind in keys:
		var mesh: ArrayMesh = Catalog.build(kind)
		var metadata := Catalog.metadata_for(kind)
		_expect(mesh != null, "%s 可构建" % kind, failures)
		if mesh == null:
			continue
		_expect(mesh == Catalog.build(kind), "%s 共用已构建缓存" % kind, failures)
		_expect(mesh.get_surface_count() == 1, "%s 单 surface" % kind, failures)
		if mesh.get_surface_count() != 1:
			continue
		var material: Material = mesh.surface_get_material(0)
		_expect(material is StandardMaterial3D, "%s 一个标准材质" % kind, failures)
		if shared_material == null:
			shared_material = material
		_expect(material == shared_material, "%s 已制作机型共享材质" % kind, failures)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var triangles := vertices.size() / 3
		_expect(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES,
			"%s 三角网格" % kind, failures)
		_expect(vertices.size() % 3 == 0 and triangles > 0 and triangles <= Catalog.TRIANGLE_BUDGET,
			"%s 最多 600 三角形" % kind, failures)
		_expect(triangles == int(metadata.get("triangles", -1)), "%s 预算记录等于真实面数" % kind, failures)
		_expect(normals.size() == vertices.size() and colors.size() == vertices.size(),
			"%s 每顶点法线与颜色完整" % kind, failures)
		if normals.size() == vertices.size() and colors.size() == vertices.size():
			_expect(_valid_triangles(vertices, normals, colors), "%s 有效面/向外法线/顺时针正面" % kind, failures)
		if kind in wing_livery_keys:
			_expect(_has_wing_livery_mask(colors), "%s 有可独立着色的机翼掩码" % kind, failures)
		var bounds := mesh.get_aabb()
		_expect(bounds.size.y > 3.0 and bounds.position.y < -0.5 and bounds.end.y > 1.5,
			"%s 机腹到上部结构有真实厚度" % kind, failures)
		_expect(absf(bounds.size.x - float(metadata.get("native_span", -1.0))) < 0.01
			and absf(bounds.size.z - float(metadata.get("native_length", -1.0))) < 0.01,
			"%s 保留参考长宽比而非统一拉满方框" % kind, failures)
		_expect(absf(bounds.get_center().x) < 0.001, "%s 横向中心不漂移" % kind, failures)
		_expect(_symmetric(vertices), "%s 每个顶点均有镜像对应" % kind, failures)
		_expect(_forward_nose(vertices, bounds), "%s 细机鼻在 -Z 且尾部在 +Z" % kind, failures)
		var signature := hash(vertices)
		_expect(not signatures.has(signature), "%s 独立几何而非同网格改名" % kind, failures)
		signatures.append(signature)
		_expect(not String(metadata.get("source", "")).is_empty()
			and not String(metadata.get("fidelity", "")).is_empty(), "%s 来源及非写实边界明确" % kind, failures)
		if Catalog.supports_body_lod(kind):
			var source_mesh := Catalog.build(kind)
			var medium_mesh := Catalog.build_runtime_lod(kind, Catalog.BODY_LOD_MEDIUM)
			var low_mesh := Catalog.build_runtime_lod(kind, Catalog.BODY_LOD_LOW)
			_expect(medium_mesh != null and medium_mesh == Catalog.build_runtime_lod(kind,
				Catalog.BODY_LOD_MEDIUM), "%s 中景专属网格可构建并共享缓存" % kind, failures)
			_expect(low_mesh != null and low_mesh == Catalog.build_runtime_lod(kind,
				Catalog.BODY_LOD_LOW), "%s 最远景专属网格可构建并共享缓存" % kind, failures)
			var lod_records: Array[Dictionary] = [
				{"mesh": medium_mesh, "level": 1,
					"budget": Catalog.BODY_LOD_MEDIUM_TRIANGLE_BUDGET, "label": "中景"},
				{"mesh": low_mesh, "level": 2,
					"budget": Catalog.BODY_LOD_LOW_TRIANGLE_BUDGET, "label": "最远景"},
			]
			for lod_record in lod_records:
				var lod_mesh: ArrayMesh = lod_record.mesh
				if lod_mesh == null or lod_mesh.get_surface_count() != 1:
					continue
				var lod_arrays := lod_mesh.surface_get_arrays(0)
				var lod_vertices: PackedVector3Array = lod_arrays[Mesh.ARRAY_VERTEX]
				var lod_normals: PackedVector3Array = lod_arrays[Mesh.ARRAY_NORMAL]
				var lod_colors: PackedColorArray = lod_arrays[Mesh.ARRAY_COLOR]
				var lod_triangles := lod_vertices.size() / 3
				var source_bounds := source_mesh.get_aabb()
				var lod_bounds := lod_mesh.get_aabb()
				_expect(lod_triangles > 0 and lod_triangles <= int(lod_record.budget)
					and lod_triangles < source_mesh.surface_get_array_len(0) / 3,
					"%s %s网格确实降面且不超过预算" % [kind, lod_record.label], failures)
				_expect(lod_mesh.surface_get_material(0) == shared_material,
					"%s %s网格不增加材质" % [kind, lod_record.label], failures)
				_expect(lod_bounds.size.x >= source_bounds.size.x * 0.94
					and lod_bounds.size.z >= source_bounds.size.z * 0.94,
					"%s %s网格保留本机型主要长宽轮廓" % [kind, lod_record.label], failures)
				_expect(lod_normals.size() == lod_vertices.size()
					and lod_colors.size() == lod_vertices.size()
					and _valid_triangles(lod_vertices, lod_normals, lod_colors),
					"%s %s网格面/法线/颜色有效" % [kind, lod_record.label], failures)
				_expect(_symmetric(lod_vertices),
					"%s %s轮廓保持左右对称" % [kind, lod_record.label], failures)
				if kind in wing_livery_keys:
					_expect(_has_wing_livery_mask(lod_colors),
						"%s %s网格保留双通道涂装" % [kind, lod_record.label], failures)
			if medium_mesh != null and low_mesh != null:
				_expect(medium_mesh.surface_get_array_len(0) > low_mesh.surface_get_array_len(0),
					"%s 中景结构复杂度高于最远景轮廓" % kind, failures)
		print("[Volume catalog] %s triangles=%d bounds=%s" % [kind, triangles, bounds.size])
	# 所有已制作机型均有不同的归一化三维结构，而不是同一模板改尺寸或改名。
	var normalized_signatures: Array[int] = []
	for kind in keys:
		var signature := _profile_signature(Catalog.build(kind))
		_expect(signature not in normalized_signatures,
			"%s 归一化三维结构独立" % kind, failures)
		normalized_signatures.append(signature)
	var identity_probe := Aircraft.new()
	identity_probe.params = AircraftParams.new()
	for raw_display_name: Variant in Silhouettes.LEGACY_MODEL_KEYS:
		var display_name := String(raw_display_name)
		identity_probe.params.display_name = display_name
		_expect(Silhouettes.key_for(identity_probe).is_empty(),
			"%s 仍保留二维 legacy 回退" % display_name, failures)
		_expect(Silhouettes.canonical_model_key_for(identity_probe)
			== String(Silhouettes.LEGACY_MODEL_KEYS[display_name]),
			"%s 有稳定三维规范 key" % display_name, failures)
	identity_probe.params.display_name = "F-14 Tomcat Warhound"
	identity_probe.set_meta("airframe_label", "F-14 Tomcat")
	_expect(Silhouettes.canonical_model_key_for(identity_probe) == "f14",
		"玩家档案后缀不破坏 F-14 三维身份", failures)
	identity_probe.params.display_name = "AWACS"
	identity_probe.set_meta("airframe_label", "Tu-160")
	_expect(Silhouettes.canonical_model_key_for(identity_probe) == "tu160",
		"事件改名 AWACS 保留 Tu-160 三维身份", failures)
	_expect(Catalog.build("unknown") == null and Catalog.build("") == null,
		"未知 key 安全拒绝而非套壳", failures)
	_expect(Catalog.supports_body_lod("f14")
		and Catalog.supports_body_lod("ah64")
		and Catalog.supports_body_lod("ch47")
		and Catalog.supports_body_lod("mother_goose"),
		"视觉机身 LOD 覆盖普通机、旋翼机与 BOSS，不按运行时身份豁免", failures)
	_expect(Catalog.build_runtime_lod("unknown", Catalog.BODY_LOD_LOW) == null
		and Catalog.build_runtime_lod("f14", -1) == null
		and Catalog.build_runtime_lod("f14", 3) == null,
		"未知机型或未定义 LOD 级别显式拒绝", failures)
	_expect(Catalog.metadata_for("unknown").is_empty(), "未知 key 不伪报制作记录", failures)
	_test_runtime_mounts(identity_probe, failures)
	identity_probe.free()
	var altered := Catalog.metadata_for("f14")
	altered["triangles"] = -1
	_expect(int(Catalog.metadata_for("f14").get("triangles", -1)) == 432,
		"调用者修改 metadata 不污染后续查询", failures)
	for failure in failures:
		push_error("Volume aircraft catalog: " + failure)
	print("[Volume catalog] failures=%d (geometry only, not a Visual/FPS gate)" % failures.size())
	return failures.is_empty()


static func _test_runtime_mounts(ac: Aircraft, failures: Array[String]) -> void:
	var expected_kinds := ["gun", "missile", "secondary_missile", "rocket", "flare",
		"torpedo", "loyal_wingman", "railgun", "laser", "esm_pod", "special", "rotor"]
	_expect(Mounts.supported_kinds() == expected_kinds, "共享挂载目录种类固定", failures)
	var shared_mount_material: Material
	for kind in expected_kinds:
		var mesh := Mounts.build(kind)
		_expect(mesh != null and mesh == Mounts.build(kind), "%s 挂件可构建且缓存" % kind, failures)
		if mesh == null:
			continue
		_expect(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) > 0,
			"%s 挂件为单 surface 三角网格" % kind, failures)
		var material: Material = mesh.surface_get_material(0)
		if shared_mount_material == null:
			shared_mount_material = material
		_expect(material == shared_mount_material, "%s 挂件复用一个材质" % kind, failures)
	_expect(Mounts.build("unknown") == null, "未知挂件安全拒绝", failures)
	var occupied: Dictionary = {}
	for kind in Mounts.AIRCRAFT_KINDS:
		for slot: Vector3 in Mounts.normalized_slots(kind):
			var slot_key := Vector3i((slot * 1000.0).round())
			_expect(not occupied.has(slot_key), "%s 三维槽位不与其他装备冲突" % kind, failures)
			occupied[slot_key] = kind
	var ah64_full := Catalog.build("ah64")
	var ah64_runtime := Catalog.build_runtime("ah64")
	var ch47_full := Catalog.build("ch47")
	var ch47_runtime := Catalog.build_runtime("ch47")
	_expect(ah64_runtime != ah64_full and ah64_runtime.surface_get_array_len(0)
		< ah64_full.surface_get_array_len(0), "AH-64 运行时机身移除静态桨叶", failures)
	_expect(ch47_runtime != ch47_full and ch47_runtime.surface_get_array_len(0)
		< ch47_full.surface_get_array_len(0), "CH-47 运行时机身移除静态桨叶", failures)
	var p := AircraftParams.new()
	p.gun = GunParams.new()
	p.missile = MissileParams.new()
	p.secondary_missile = MissileParams.new()
	p.rocket = RocketParams.new()
	p.flare = FlareParams.new()
	p.torpedo = TorpedoParams.new()
	p.loyal_wingman = LoyalWingmanParams.new()
	for equipment_kind in ["railgun", "laser", "esm_pod", "ciws"]:
		var equipment := EquipmentParams.new()
		equipment.equipment_kind = equipment_kind
		p.equipment.append(equipment)
	ac.params = p
	ac.missiles_remaining = 4
	ac.secondary_missiles_remaining = 1
	ac.rockets_remaining = 6
	ac.flares_remaining = 2
	_expect(Mounts.visible_count("gun", ac) == 1
		and Mounts.visible_count("missile", ac) == 2
		and Mounts.visible_count("secondary_missile", ac) == 1
		and Mounts.visible_count("rocket", ac) == 2
		and Mounts.visible_count("flare", ac) == 2
		and Mounts.visible_count("torpedo", ac) == 2
		and Mounts.visible_count("loyal_wingman", ac) == 2
		and Mounts.visible_count("railgun", ac) == 1
		and Mounts.visible_count("laser", ac) == 1
		and Mounts.visible_count("esm_pod", ac) == 1
		and Mounts.visible_count("special", ac) == 1,
		"正式 AircraftParams 决定全部外露装备槽", failures)
	ac.missiles_remaining = 0
	ac.secondary_missiles_remaining = 0
	ac.rockets_remaining = 0
	_expect(Mounts.visible_count("missile", ac) == 0
		and Mounts.visible_count("secondary_missile", ac) == 0
		and Mounts.visible_count("rocket", ac) == 0,
		"消耗掉的外露弹体从三维槽消失", failures)
	var livery := Color("768899")
	ac.is_firing = true
	_expect(Mounts.state_color("gun", ac, livery) != livery, "机炮开火改变挂件状态色", failures)
	ac.is_firing = false
	ac.equipment_state["railgun"] = {"charging": true, "charge_progress": 0.5}
	_expect(Mounts.state_color("railgun", ac, livery) != livery, "电磁炮充能改变挂件状态色", failures)
	ac.equipment_state["laser"] = {"active_beams": [{"alpha": 1.0}], "overheating": false}
	_expect(Mounts.state_color("laser", ac, livery) != livery, "激光开火改变挂件状态色", failures)
	ac.equipment_state["laser"] = {"active_beams": [], "overheating": true}
	_expect(Mounts.state_color("laser", ac, livery) == Color("ff694f"),
		"激光过热有独立警示状态", failures)


static func _valid_triangles(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> bool:
	for index in range(0, vertices.size(), 3):
		var cross := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
		if not cross.is_finite() or cross.length_squared() < 0.00000001:
			return false
		for offset in 3:
			var normal := normals[index + offset]
			if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001:
				return false
			if cross.normalized().dot(normal) > -0.999 or colors[index + offset].a < 0.49:
				return false
	return true


static func _has_wing_livery_mask(colors: PackedColorArray) -> bool:
	for color in colors:
		if color.a > 0.49 and color.a < 0.75:
			return true
	return false


static func _symmetric(vertices: PackedVector3Array) -> bool:
	var positions: Dictionary = {}
	for vertex in vertices:
		positions[Vector3i((vertex * 10000.0).round())] = true
	for vertex in vertices:
		var mirror := Vector3i((Vector3(-vertex.x, vertex.y, vertex.z) * 10000.0).round())
		if not positions.has(mirror):
			return false
	return true


static func _forward_nose(vertices: PackedVector3Array, bounds: AABB) -> bool:
	if bounds.position.z >= -0.45 * bounds.size.z or bounds.end.z <= 0.45 * bounds.size.z:
		return false
	for vertex in vertices:
		if vertex.z < bounds.position.z + maxf(0.01, bounds.size.z * 0.001) \
				and absf(vertex.x) > 0.21:
			return false
	return true


static func _profile_signature(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() != 1:
		return 0
	var bounds := mesh.get_aabb()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var occupied: Dictionary = {}
	for vertex in vertices:
		var normalized := (vertex - bounds.position) / bounds.size
		occupied[Vector3i((normalized * 20.0).round())] = true
	var cells := occupied.keys()
	cells.sort()
	return hash(cells)


static func _expect(ok: bool, message: String, failures: Array[String]) -> void:
	if not ok:
		failures.append(message)
