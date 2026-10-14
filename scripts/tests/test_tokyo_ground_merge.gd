extends RefCounted
const Bake := preload("res://scripts/tests/bake_tokyo_ground_merge.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(Bake.compact(ArrayMesh.new()).get_surface_count() == 0, "empty mesh")
	var geometry := Geometry.new()
	geometry.quad(Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1), Vector3.BACK, Color.RED)
	geometry.quad(Vector3.ZERO, Vector3.UP, Vector3(1, 1, 0), Vector3.RIGHT, Color.BLUE)
	var original: ArrayMesh = geometry.mesh()
	var material := StandardMaterial3D.new()
	original.surface_set_material(0, material)
	var vertices := original.surface_get_array_len(0)
	var packed := Bake.compact(original)
	_check(packed != null and Join.conserved(original, [packed]), "packed oriented faces preserved")
	_check(packed.surface_get_array_len(0) < vertices, "duplicate vertices compacted")
	_check(original.surface_get_array_len(0) == vertices, "source unchanged")
	_check(packed.surface_get_material(0) == material, "material retained")
	_check(Join.conserved(packed, [Bake.compact(packed)]), "indexed input remains exact")
	var order := preload("res://scripts/tests/tokyo_ground_order_probe.gd")
	var moved := order.move_to_end(packed, [0])
	_check(moved != null and Join.conserved(packed, [moved]), "order control preserves all packed oriented faces")
	_check(moved.surface_get_arrays(0)[Mesh.ARRAY_INDEX][-3] == packed.surface_get_arrays(0)[Mesh.ARRAY_INDEX][0], "selected face really moves to end")
	_check(order.move_to_end(packed, [999]) == null and order.move_to_end(packed, [0, 0]) == null, "invalid order source rejected")
	original.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original.surface_get_arrays(0))
	_check(Bake.compact(original) == null, "unsupported multiple surfaces fail closed")
	_check(load("res://scripts/tests/tokyo_ground_merge_review.gd").can_instantiate(), "Visual review compiles")
	print("[R55 ground test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R55 " + label)
