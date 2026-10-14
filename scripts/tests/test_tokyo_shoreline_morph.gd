extends RefCounted
const Candidate := preload("res://scripts/experiments/tokyo_shoreline_morph_candidate.gd")


static func fixture() -> Array:
	return [{"mode":"morph","mesh":{"wide":[[0,0],[4,0],[0,4]],"narrow":[[0,0],[2,0],[0,2]],"indices":[[0,1,2]],"faces":1}}]


static func checks() -> Array[bool]:
	var results: Array[bool] = []
	var builder := preload("res://scripts/tests/build_tokyo_shoreline_morph.gd")
	results.append(builder.numbers_equal(JSON.parse_string("[70,82,83]"),[70,82,83]))
	results.append(not builder.numbers_equal([70.1,82,83],[70,82,83]))
	results.append(not builder.numbers_equal(["70",82,83],[70,82,83]))
	results.append(not builder.numbers_equal([NAN,82,83],[70,82,83]))
	var mesh := Candidate.build_mesh(fixture(),0)
	results.append(mesh!=null)
	if mesh!=null:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offsets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		results.append(vertices.size()==3 and offsets.size()==3)
		results.append((vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).y<0)
		results.append(offsets[1]==Vector2(-2,0) and offsets[2]==Vector2(0,-2))
		results.append(mesh.custom_aabb.has_point(Vector3(0,.03,4)))
	var data := fixture()
	data[0].mesh.indices[0][1]=.5
	results.append(Candidate.build_mesh(data,0)==null)
	data=fixture()
	data[0].mesh.wide[0][0]=NAN
	results.append(Candidate.build_mesh(data,0)==null)
	data=fixture()
	data[0].mesh.narrow=[[0,0],[-4,0],[0,-4]]
	results.append(Candidate.build_mesh(data,0)==null)
	data=fixture()
	data[0].mesh.indices[0]=[0,0,2]
	results.append(Candidate.build_mesh(data,0)==null)
	results.append(Candidate.build_mesh([],0)==null and Candidate.build_mesh(fixture(),4)==null)
	results.append(Candidate.factor(.85)==0 and Candidate.factor(2.3)==1)
	results.append(is_equal_approx(Candidate.factor(1.15),1.0/1.65))
	results.append(Candidate.factor(NAN)<0 and Candidate.factor(0)<0)
	var original: String = preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var code := Candidate.shader_code(original)
	results.append(not code.is_empty() and code.find("VERTEX.xz += UV")<code.find("shoreline_local=VERTEX.xz"))
	results.append(Candidate.shader_code(code).is_empty() and Candidate.shader_code("drift").is_empty())
	return results
