extends RefCounted
## 三维机体的共享挂载件目录。挂点坐标是机体原生包围盒的归一化比例，
## 只读真实 AircraftParams / 弹药 / 装备状态，不拥有武器逻辑。

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

## X/Z 是相对半翼展/半机长的比例，Y 是目录原生单位。各类槽位互不重叠。
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
static var _material: StandardMaterial3D


static func supported_kinds() -> Array[String]:
	return SUPPORTED_KINDS.duplicate()


static func normalized_slots(kind: String) -> Array:
	return (NORMALIZED_SLOTS.get(kind, []) as Array).duplicate()


static func local_slots(kind: String, native_span: float, native_length: float) -> Array[Vector3]:
	var dimension_key := Vector2(native_span, native_length)
	var kind_cache: Dictionary = _local_slot_cache.get(kind, {})
	if kind_cache.has(dimension_key):
		return kind_cache[dimension_key] as Array[Vector3]
	var result: Array[Vector3] = []
	for slot: Vector3 in NORMALIZED_SLOTS.get(kind, []):
		result.append(Vector3(slot.x * native_span * 0.5, slot.y, slot.z * native_length * 0.5))
	kind_cache[dimension_key] = result
	_local_slot_cache[kind] = kind_cache
	return result


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
			builder.box(Vector3(0, .75, 0), Vector3(2.0, .18, .42), Color("eadcff"))
		"rotor":
			builder.box(Vector3.ZERO, Vector3(2.0, .08, .16), Color("aeb8b7"))
			builder.box(Vector3.ZERO, Vector3(.16, .08, 2.0), Color("aeb8b7"))
	var result: ArrayMesh = builder.mesh()
	if _material == null:
		_material = Factory.material()
	result.surface_set_material(0, _material)
	result.resource_name = "AGL_aircraft_mount_%s" % kind
	_meshes[kind] = result
	return result
