extends RefCounted
## 三维机体共享挂载目录。规范比例只作意向，最终接合点从各机型真实表面求得。
## 只读真实 AircraftParams / 弹药 / 装备状态，不拥有武器逻辑。

const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const Surface := preload("res://scripts/experiments/volume_mount_surface.gd")
const CONTACT_EMBED := 0.08
## 支座与外壳相交，接合端轻微嵌入真实机体表面。
const CONTACTS := {
	"gun": Vector3(0, 0.525, 0.65), "missile": Vector3(0, 0.56, 0),
	"secondary_missile": Vector3(0, 0.61, 0), "rocket": Vector3(0, 0.55, 0),
	"flare": Vector3(0, 0.64, 0), "torpedo": Vector3(0, 0.72, 0),
	"loyal_wingman": Vector3(0, 0.62, 0), "railgun": Vector3(0, 0.59, 0),
	"laser": Vector3(0, -0.675, 0), "esm_pod": Vector3(0, -0.8, 0),
	"special": Vector3(0, -0.925, 0),
}

const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const SUPPORTED_KINDS: Array[String] = [
	"gun", "missile", "secondary_missile", "rocket", "flare",
	"torpedo", "loyal_wingman", "railgun", "laser", "esm_pod", "special", "rotor",
]
const AIRCRAFT_KINDS: Array[String] = [
	"gun", "missile", "secondary_missile", "rocket", "flare",
	"torpedo", "loyal_wingman", "railgun", "laser", "esm_pod", "special",
]
const SPECIAL_EQUIPMENT_KINDS: Array[String] = ["ciws", "ecm", "chaff"]

## X/Z 是半翼展/半机长的布局意向；旧 Y 仅保留槽定义兼容，实际高度由 CONTACTS 与表面求得。
const NORMALIZED_SLOTS: Dictionary = {
	"gun": [Vector3(-0.10, -2.20, -0.70)],
	"railgun": [Vector3(0.0, -2.35, -0.42)],
	"laser": [Vector3(0.14, 2.35, -0.18)],
	"missile": [Vector3(-0.48, -2.10, 0.02), Vector3(0.48, -2.10, 0.02)],
	"secondary_missile": [Vector3(-0.68, -2.00, 0.18), Vector3(0.68, -2.00, 0.18)],
	"rocket": [Vector3(-0.34, -2.25, 0.34), Vector3(0.34, -2.25, 0.34)],
	"flare": [Vector3(-0.20, -1.90, 0.66), Vector3(0.20, -1.90, 0.66)],
	"torpedo": [Vector3(-0.30, -2.55, 0.56), Vector3(0.30, -2.55, 0.56)],
	"loyal_wingman": [Vector3(-0.56, -1.75, 0.54), Vector3(0.56, -1.75, 0.54)],
	"esm_pod": [Vector3(0.0, 2.55, 0.16)],
	"special": [Vector3(0.0, 2.30, 0.48)],
}

static var _meshes: Dictionary = {}
static var _local_slot_cache: Dictionary = {}
static var _goose_cache: Dictionary = {}
static var _material: StandardMaterial3D


static func supported_kinds() -> Array[String]:
	return SUPPORTED_KINDS.duplicate()


static func normalized_slots(kind: String) -> Array:
	return (NORMALIZED_SLOTS.get(kind, []) as Array).duplicate()


static func local_slots(kind: String, airframe_key: String) -> Array[Vector3]:
	var kind_cache: Dictionary = _local_slot_cache.get(airframe_key, {})
	if kind_cache.has(kind):
		return kind_cache[kind] as Array[Vector3]
	var result: Array[Vector3] = []
	var mesh := Airframes.build_runtime(airframe_key)
	if mesh == null or not CONTACTS.has(kind):
		return result
	var dimensions := Airframes.metadata_for(airframe_key)
	var contact: Vector3 = CONTACTS[kind]
	var upper := contact.y < 0.0
	for slot: Vector3 in NORMALIZED_SLOTS.get(kind, []):
		var desired := Vector2(slot.x * float(dimensions.native_span) * 0.5,
			slot.z * float(dimensions.native_length) * 0.5 + contact.z)
		var surface := Surface.closest(mesh, desired, upper)
		assert(surface.is_finite(), "missing aircraft mounting surface: " + airframe_key)
		result.append(surface - contact + Vector3(0, -CONTACT_EMBED if upper else CONTACT_EMBED, 0))
	kind_cache[kind] = result
	_local_slot_cache[airframe_key] = kind_cache
	return result


static func prewarm(airframe_key: String) -> void:
	for kind in AIRCRAFT_KINDS:
		local_slots(kind, airframe_key)
	if airframe_key == "mother_goose":
		for offset in MotherGooseBoss.PROP_OFFSETS_PX:
			goose_layout(offset, true)
		for offset in MotherGooseBoss.VLS_OFFSETS_PX:
			goose_layout(offset, false)


## 只读正式配置和弹药状态。返回 0 表示该外露弹体/挂件当前不应提交；
## 枪、热诱弹盒与能量装备即使耗尽也保留硬件本体，只由颜色表达状态。
static func visible_count(kind: String, ac: Aircraft) -> int:
	if ac == null or ac.params == null:
		return 0
	match kind:
		"gun":
			return 1 if ac.params.has_equipment_of_kind("gun") else 0
		"missile":
			var has_main := ac.params.missile != null or ac.params.get_equipment_of_kind("missile") != null
			return mini(2, maxi(ac.missiles_remaining, 0)) if has_main else 0
		"secondary_missile":
			return mini(2, maxi(ac.secondary_missiles_remaining, 0)) \
				if ac.params.secondary_missile != null else 0
		"rocket":
			return mini(2, maxi(ac.rockets_remaining, 0)) \
				if ac.params.has_equipment_of_kind("rocket") else 0
		"flare":
			return 2 if ac.params.has_equipment_of_kind("flare") else 0
		"torpedo":
			return 2 if ac.params.torpedo != null else 0
		"loyal_wingman":
			return 2 if ac.params.loyal_wingman != null else 0
		"railgun", "laser", "esm_pod":
			return 1 if ac.params.has_equipment_of_kind(kind) else 0
		"special":
			for eq: EquipmentParams in ac.params.equipment:
				if eq != null and eq.equipment_kind in SPECIAL_EQUIPMENT_KINDS:
					return 1
	return 0


## MultiMesh instance color只影响挂件，不改机体/阵营涂装。它让装填、开火、充能、
## 过热和释放冷却在三维层有可见状态，同时不复制任何武器计时或伤害权威。
static func state_color(kind: String, ac: Aircraft, livery: Color) -> Color:
	if ac == null:
		return livery
	match kind:
		"gun":
			if ac.is_firing:
				return Color("ffd77b")
			if ac._gun_reload_active or ac.ammo <= 0:
				return livery.lerp(Color("353b3d"), 0.70)
		"flare":
			if ac.flares_remaining <= 0:
				return livery.lerp(Color("542f27"), 0.70)
		"torpedo":
			if ac._torpedo_cooldown > 0.0:
				return livery.lerp(Color("38585d"), 0.55)
		"loyal_wingman":
			if ac._loyal_wingman_cooldown > 0.0:
				return livery.lerp(Color("404a57"), 0.55)
		"railgun":
			var rail_raw: Variant = ac.equipment_state.get("railgun")
			if typeof(rail_raw) != TYPE_DICTIONARY:
				return livery
			var rail_state: Dictionary = rail_raw
			if float(rail_state.get("beam_fade", 0.0)) > 0.0:
				return Color("efffff")
			if bool(rail_state.get("charging", false)) or bool(rail_state.get("awaiting_fire", false)):
				return Color("5ee9ff").lerp(Color.WHITE,
					clampf(float(rail_state.get("charge_progress", 0.0)), 0.0, 1.0))
		"laser":
			var laser_raw: Variant = ac.equipment_state.get("laser")
			if typeof(laser_raw) != TYPE_DICTIONARY:
				return livery
			var laser_state: Dictionary = laser_raw
			if bool(laser_state.get("overheating", false)):
				return Color("ff694f")
			var active_beams: Variant = laser_state.get("active_beams")
			if typeof(active_beams) == TYPE_ARRAY and not (active_beams as Array).is_empty():
				return Color("c9ffd1")
		"esm_pod":
			return livery.lerp(Color("76d8ff"), 0.55)
	return livery


static func build(kind: String) -> ArrayMesh:
	if kind == "support":
		if not _meshes.has(kind):
			var support := Factory.new()
			support.box(Vector3.ZERO, Vector3.ONE, Color("687984"))
			_meshes[kind] = support.mesh()
		return _meshes[kind] as ArrayMesh
	if kind not in SUPPORTED_KINDS:
		return null
	if _meshes.has(kind):
		return _meshes[kind] as ArrayMesh
	var builder := Factory.new()
	match kind:
		"gun":
			builder.box(Vector3(0, 0, -1.2), Vector3(.42, .42, 3.2), Color.WHITE)
			builder.box(Vector3(0, .05, .65), Vector3(.82, .65, .70), Color("384047"))
		"missile":
			builder.box(Vector3(0, 0, 0), Vector3(.52, .52, 4.2), Color.WHITE)
			builder.box(Vector3(0, 0, 1.25), Vector3(1.45, .12, 1.0), Color("c4ccd0"))
			builder.box(Vector3(0, 0, 1.25), Vector3(.12, 1.45, 1.0), Color("c4ccd0"))
		"secondary_missile":
			builder.box(Vector3(0, 0, 0), Vector3(.62, .62, 3.5), Color("d9dedf"))
			builder.box(Vector3(0, 0, .95), Vector3(1.65, .14, .82), Color("87949a"))
			builder.box(Vector3(0, 0, .95), Vector3(.14, 1.65, .82), Color("87949a"))
		"rocket":
			builder.prism(PackedVector2Array([Vector2(0, -2.0), Vector2(.48, -.8),
				Vector2(.48, 1.6), Vector2(0, 2.0), Vector2(-.48, 1.6), Vector2(-.48, -.8)]),
				-.25, .25, Color("c7c8b8"))
			builder.box(Vector3(0, 0, 1.25), Vector3(1.25, .14, .8), Color("686d66"))
		"flare":
			builder.box(Vector3.ZERO, Vector3(1.25, .68, 1.8), Color("d87542"))
		"torpedo":
			builder.prism(PackedVector2Array([Vector2(0, -2.2), Vector2(.58, -1.1),
				Vector2(.58, 1.5), Vector2(0, 2.2), Vector2(-.58, 1.5), Vector2(-.58, -1.1)]),
				-.42, .42, Color("78d9e6"))
			builder.box(Vector3(0, .48, .7), Vector3(1.5, .12, 1.2), Color("b9ecf2"))
		"loyal_wingman":
			builder.prism(PackedVector2Array([Vector2(0, -2.0), Vector2(1.5, .9),
				Vector2(.55, .65), Vector2(0, 1.8), Vector2(-.55, .65), Vector2(-1.5, .9)]),
				-.22, .32, Color("9eabb8"))
			builder.box(Vector3(0, 0, .75), Vector3(.44, .55, 1.35), Color("66727d"))
		"railgun":
			builder.box(Vector3(0, 0, -.4), Vector3(.58, .58, 4.8), Color("c8e7ef"))
			builder.box(Vector3(0, 0, -.8), Vector3(1.25, .85, .48), Color("567887"))
			builder.box(Vector3(0, 0, .8), Vector3(1.25, .85, .48), Color("567887"))
		"laser":
			builder.box(Vector3.ZERO, Vector3(1.30, .75, 1.30), Color("93d5a2"))
			builder.box(Vector3(0, .65, -.45), Vector3(.42, .75, 1.55), Color("d8ffd7"))
		"esm_pod":
			builder.box(Vector3.ZERO, Vector3(1.0, 1.0, 2.8), Color("91b8c8"))
			builder.box(Vector3.ZERO, Vector3(2.2, .14, .55), Color("d1e7ec"))
			builder.box(Vector3.ZERO, Vector3(.14, 2.2, .55), Color("d1e7ec"))
		"special":
			builder.box(Vector3.ZERO, Vector3(1.25, 1.25, 2.2), Color("ad8ed4"))
			builder.box(Vector3(0, .65, 0), Vector3(2.0, .18, .42), Color("eadcff"))
		"rotor":
			builder.box(Vector3.ZERO, Vector3(2.0, .08, .16), Color("aeb8b7"))
			builder.box(Vector3.ZERO, Vector3(.16, .08, 2.0), Color("aeb8b7"))
	if CONTACTS.has(kind):
		var contact: Vector3 = CONTACTS[kind]
		var inward := -1.0 if contact.y > 0.0 else 1.0
		builder.box(contact + Vector3(0, inward * 0.20, 0),
			Vector3(0.34, 0.40, 0.54), Color("58646b"))
	var result: ArrayMesh = builder.mesh()
	if _material == null:
		_material = Factory.material()
	result.surface_set_material(0, _material)
	result.resource_name = "AGL_aircraft_mount_%s" % kind
	_meshes[kind] = result
	return result


## 母鹅保留正式可攻击挂点的 XZ；外侧推进舱由真实翼面伸出结构臂连接。
static func goose_layout(offset: Vector2, prop: bool) -> Dictionary:
	var cache_key := Vector3(offset.x, offset.y, 1.0 if prop else 0.0)
	if _goose_cache.has(cache_key):
		return _goose_cache[cache_key]
	var target := Vector3(offset.y, 0, -offset.x)
	var surface := Surface.closest(Airframes.build_runtime("mother_goose"), Vector2(target.x, target.z), true)
	target.y = surface.y + (3.0 if prop else -CONTACT_EMBED)
	var result := {"position": target}
	if prop or Vector2(surface.x, surface.z).distance_to(Vector2(target.x, target.z)) > 0.1:
		var end := target + Vector3(0, 0, -6.0 if prop else 0.0)
		var start := surface - Vector3.UP * 0.5
		var delta := end - start
		var axis := delta.normalized()
		var right := Vector3.UP.cross(axis).normalized()
		if right.length_squared() < 0.1:
			right = Vector3.RIGHT
		var up := axis.cross(right).normalized()
		result["support"] = Transform3D(Basis(right * 2.5, up * 2.5, axis * (delta.length() + 1.0)), (start + end) * 0.5)
	_goose_cache[cache_key] = result
	return result
