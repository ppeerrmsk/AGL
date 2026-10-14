extends RefCounted
const Export := preload("res://scripts/tests/export_tokyo_full_root_roofs.gd")


static func checks() -> bool:
	if Export.run("","","")!=1 or not Export.expected_sources({}).is_empty():
		return false
	var game := Export.Guard.read_source()
	var expected := Export.expected_sources(game)
	if expected.size()!=189:
		return false
	for id in expected.size():
		if expected[id].source_id!=id or expected[id].height!=float(game.entries[id].max_real_h)*CombatUnit.PIXELS_PER_METER \
				or expected[id].points.size()!=game.entries[id].footprint.size():
			return false
		for n in expected[id].points.size():
			var point: Vector2 = game.entries[id].footprint[n]
			if expected[id].points[n]!=[point.x,point.y]:
				return false
	var changed := game.duplicate()
	changed.source_sha256="c".repeat(64)
	if not Export.expected_sources(changed).is_empty():
		return false
	changed=game.duplicate()
	changed.collision_sha256="c".repeat(64)
	if not Export.expected_sources(changed).is_empty():
		return false
	changed=game.duplicate()
	changed.entries=game.entries.slice(0,188)
	return Export.expected_sources(changed).is_empty()
