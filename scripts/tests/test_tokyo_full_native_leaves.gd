extends RefCounted
const Leaves := preload("res://scripts/tests/build_tokyo_full_native_leaves.gd")
const Fixture := preload("res://scripts/tests/test_tokyo_full_grid_root.gd")


static func checks() -> bool:
	if Leaves.run("","","")!=1:
		return false
	var source := Leaves.Root.Join.join([Fixture.triangle(-2,false),Fixture.triangle(4,true)])
	var owners := PackedInt32Array([0,255])
	var pieces := Leaves.Split.partition(source,owners,256)
	if pieces.size()!=256 or not Leaves.conserved(source,pieces,owners) or not Leaves.Root.Join.conserved(source,pieces):
		return false
	if Leaves.conserved(source,pieces,PackedInt32Array([255,0])) or Leaves.conserved(source,pieces,PackedInt32Array([0])):
		return false
	for invalid: PackedInt32Array in [PackedInt32Array([0]),PackedInt32Array([-1,0]),PackedInt32Array([0,256])]:
		if not Leaves.Split.partition(source,invalid,256).is_empty():
			return false
	if not Leaves.Split.partition(source,owners,257).is_empty():
		return false
	var old := Leaves.Split.split(source,PackedFloat32Array([0,0.5,0.5]))
	var mapped := Leaves.Split.partition(source,PackedInt32Array([0,2]),4)
	for n in 4:
		if not Leaves.Root.Same.same_mesh(old[n],mapped[n]):
			return false
	var simple := Fixture.triangle(0,false)
	var single := Leaves.Split.partition(simple,PackedInt32Array([255]),256)
	return Leaves.conserved(simple,single,PackedInt32Array([255])) and Leaves.Root.Join.conserved(simple,single) \
		and Leaves.Split.partition(ArrayMesh.new(),PackedInt32Array(),256).size()==256
