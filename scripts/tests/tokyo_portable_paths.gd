extends RefCounted
## 离线迁址只更换完整路径/叶token；数值、类型、几何身份全部保留。


static func rewrite(value: Variant, paths: Dictionary) -> Variant:
	if value is String:
		if paths.has(value):return paths[value]
		for suffix: String in [":0",":1"]:
			if value.ends_with(suffix):
				var base: String=value.trim_suffix(suffix)
				if paths.has(base):return String(paths[base])+suffix
		return value
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:
			var replaced: Variant=rewrite(key,paths)
			if result.has(replaced):return null
			result[replaced]=rewrite(value[key],paths)
		return result
	if value is Array or value is PackedStringArray:
		var result: Variant=value.duplicate()
		for index in result.size():result[index]=rewrite(value[index],paths)
		return result
	return value


static func reversible(value: Variant, paths: Dictionary) -> bool:
	var inverse: Dictionary={}
	for source: String in paths:
		var target: Variant=paths[source]
		if not target is String or inverse.has(target) or paths.has(target):return false
		inverse[target]=source
	return rewrite(rewrite(value,paths),inverse)==value


static func checks() -> bool:
	var paths: Dictionary={"C:/source/a.logical":"res://maps/a.logical","C:/source/mesh.res":"res://maps/mesh.res"}
	var data: Dictionary={"C:/source/a.logical":{"leaves":PackedStringArray(["C:/source/a.logical"]),
		"tokens":[PackedStringArray(["C:/source/a.logical:0","C:/source/a.logical:1"])],
		"mapping":[["C:/source/mesh.res",0]],"identity":{"height":36.160000000000004,"ids":PackedInt32Array([82,83])}},
		"not_a_path":"C:/source/a.logical.extra"}
	var result: Dictionary=rewrite(data,paths)
	return reversible(data,paths) and result.has("res://maps/a.logical") \
		and result["res://maps/a.logical"].tokens[0][1]=="res://maps/a.logical:1" \
		and result.not_a_path==data.not_a_path and data.has("C:/source/a.logical") \
		and not reversible(data,{"C:/source/a.logical":"same","C:/source/mesh.res":"same"}) \
		and not reversible(data,{"C:/source/a.logical":"C:/source/mesh.res","C:/source/mesh.res":"next"})


static func full_grid_checks() -> bool:
	var fixture:=preload("res://scripts/tests/test_tokyo_full_grid_contract.gd")
	var catalog:=fixture.Catalog.new()
	var roots: Array=[]
	for parent in 16:roots.append(fixture.entry(catalog,"lod5_full",parent,-1,-1))
	var paths: Dictionary={}
	for path: String in catalog.descriptors:paths[path]="res://resources/maps/tokyo_full/logical/"+path
	return paths.size()==4432 and reversible(roots,paths) and reversible(catalog.descriptors,paths)
