extends RefCounted
const Builder := preload("res://scripts/tests/build_tokyo_rail_catalog.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")


static func checks() -> bool:
	var neighbor := Builder.recipe(true)
	if neighbor.parent != 11 or neighbor.before != 922 or neighbor.after != 525 or Builder.recipe().parent != 12:
		return false
	if Builder.planned_mesh({},true) != null:
		return false
	var geometry := Geometry.new()
	for color: Color in [Color("465253"),Color("858f88")]:
		geometry.triangle(Vector3(0,.5,0),Vector3(0,.5,2),Vector3(2,.5,0),color)
	var split := Builder.partition(geometry.mesh())
	if split.is_empty() or split.count != 1:
		return false
	if Builder.planned_mesh({}) != null:
		return false
	return not Builder.partition(ArrayMesh.new()).has("kept")
