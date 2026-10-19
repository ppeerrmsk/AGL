extends RefCounted
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Archive := preload("res://scripts/rendering/tokyo_region_archive.gd")
var _fail := 0


func run() -> void:
	var source_dir := OS.get_environment("AGL_TOKYO_REGION_SOURCE")
	var label := OS.get_environment("AGL_TOKYO_REGION_NAME")
	if source_dir.is_empty() or label not in ["r5", "r5b"]:
		_fail = 1
		push_error("Tokyo region build requires explicit source directory and r5/r5b name")
		return
	var source := source_dir.path_join("city.json")
	var ground := source_dir.path_join("ground.json")
	if not FileAccess.file_exists(source) or not FileAccess.file_exists(ground):
		_fail = 1
		return
	var packet: Dictionary = Factory.build(source)
	var archive := Archive.new()
	for key: String in ["low_mesh", "known_mesh", "road_mesh", "rail_mesh"]:
		archive.meshes.append(packet[key])
		packet.erase(key)
	archive.meshes.append(Factory.build_ground(ground))
	archive.metadata = packet
	archive.metadata["source_hash"] = FileAccess.get_sha256(source) + ":" + FileAccess.get_sha256(ground)
	var output := "res://bench/results/tokyo_region_%s.res" % label
	var error := ResourceSaver.save(archive, output, ResourceSaver.FLAG_COMPRESS)
	_fail = int(not archive.valid() or not bool(packet.ok) or error != OK)
	print("[Tokyo region archive] output=", output, " triangles=", packet.triangles, " fail=", _fail)
