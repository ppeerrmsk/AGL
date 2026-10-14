extends RefCounted
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
var _fail := 0
var _pass := 0


func run() -> void:
	var overlay_script: GDScript = load("res://scripts/rendering/tokyo_volume_overlay.gd")
	_check(overlay_script != null and overlay_script.can_instantiate(), "runtime adapter compiles")
	var archive: Resource = load(Archive.PATH)
	_check(archive != null and archive.valid(), "prebuilt archive schema and memory budget")
	if archive == null:
		return
	_check(archive.building_count == 8683, "all approved district buildings retained")
	var input_hash := FileAccess.get_sha256("res://resources/maps/tokyo_volume_preview/r1_tokyo_downtown.json") \
		+ ":" + FileAccess.get_sha256("res://resources/maps/tokyo_volume_preview/r3_ground.json")
	_check(archive.source_hash == input_hash, "compiled archive matches frozen OSM inputs")
	var previous_triangles := 0
	for level in 6:
		var entry: Dictionary = archive.levels[level]
		var total := 0
		for count: int in entry.counts:
			total += count
		_check(total == archive.building_count, "LOD density conservation %d" % level)
		_check(int(entry.triangles) >= previous_triangles and int(entry.triangles) <= 240000, "bounded monotonic geometry %d" % level)
		previous_triangles = int(entry.triangles)
		for key: String in ["low", "known"]:
			var mesh: ArrayMesh = entry[key]
			_check(mesh != null and mesh.get_aabb().size.y > 0, "source height bounds %d %s" % [level, key])
	for index in 5:
		var cut := float(Archive.CUTS[index])
		_check(Archive.choose_level(index, cut * 1.04) == index, "upper jitter does not switch %d" % index)
		_check(Archive.choose_level(index + 1, cut * 0.96) == index + 1, "lower jitter does not switch %d" % index)
		_check(Archive.choose_level(index, cut * 1.081) == index + 1, "enter near %d" % index)
		_check(Archive.choose_level(index + 1, cut * 0.919) == index, "exit near %d" % index)
	_check(Archive.choose_level(5, 0.04) == 0 and Archive.choose_level(0, 2.2) == 5, "large zoom jumps")
	print("[Tokyo LOD] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo LOD: " + label)
