extends RefCounted
## 将原墨卡托瓦片几何重投影到OSM/游戏线性纬度坐标，纹理与UV不改。
const META_PATH := "res://resources/maps/tokyo_bay_bg.json"


static func metadata() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(META_PATH))


static func world_y(raw_y: float, meta: Dictionary) -> float:
	var bbox: Dictionary = meta.bbox_ll
	var factor: float = float(meta.game_world_meters_per_degree_lat)*float(meta.game_world_px_per_meter)
	var center: float = meta.game_world_center_latlon[0]
	var north: float = -(float(bbox.lat_max)-center)*factor
	var south: float = -(float(bbox.lat_min)-center)*factor
	var fraction := (raw_y-north)/(south-north)
	var mercator_north := log(tan(PI/4+deg_to_rad(float(bbox.lat_max))/2))
	var mercator_south := log(tan(PI/4+deg_to_rad(float(bbox.lat_min))/2))
	var latitude := rad_to_deg(2*atan(exp(lerpf(mercator_north,mercator_south,fraction)))-PI/2)
	return -(latitude-center)*factor


static func raw_y(world_value: float, meta: Dictionary) -> float:
	var bbox: Dictionary = meta.bbox_ll
	var factor: float = float(meta.game_world_meters_per_degree_lat)*float(meta.game_world_px_per_meter)
	var center: float = meta.game_world_center_latlon[0]
	var north: float = -(float(bbox.lat_max)-center)*factor
	var south: float = -(float(bbox.lat_min)-center)*factor
	var latitude := center-world_value/factor
	var mercator_north := log(tan(PI/4+deg_to_rad(float(bbox.lat_max))/2))
	var mercator_south := log(tan(PI/4+deg_to_rad(float(bbox.lat_min))/2))
	var mercator_value := log(tan(PI/4+deg_to_rad(latitude)/2))
	return lerpf(north,south,(mercator_north-mercator_value)/(mercator_north-mercator_south))


static func mesh(rect: Rect2, uv: Rect2, meta: Dictionary) -> ArrayMesh:
	# 256世界px行距；全幅战略层同样分段，不靠一个长梯形近似纬度曲线。
	var rows := maxi(1,ceili(rect.size.y/256.0))
	var vertices := PackedVector2Array()
	var texcoords := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows+1:
		var t := float(row)/rows
		var y := world_y(lerpf(rect.position.y,rect.end.y,t),meta)
		vertices.append(Vector2(rect.position.x,y))
		vertices.append(Vector2(rect.end.x,y))
		texcoords.append(Vector2(uv.position.x,lerpf(uv.position.y,uv.end.y,t)))
		texcoords.append(Vector2(uv.end.x,lerpf(uv.position.y,uv.end.y,t)))
		if row<rows:
			var a := row*2
			indices.append_array(PackedInt32Array([a,a+1,a+2,a+1,a+3,a+2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result


static func valid_for(meta: Dictionary, rect: Rect2) -> bool:
	if typeof(meta.get("bbox_ll"))!=TYPE_DICTIONARY or typeof(meta.get("game_world_center_latlon"))!=TYPE_ARRAY or meta.game_world_center_latlon.size()!=2:
		return false
	var bbox: Dictionary = meta.bbox_ll
	for key in ["lat_min","lat_max","lon_min","lon_max"]:
		if typeof(bbox.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(bbox[key])):
			return false
	for key in ["game_world_meters_per_degree_lat","game_world_meters_per_degree_lon_at_center","game_world_px_per_meter"]:
		if typeof(meta.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(meta[key])) or float(meta[key])<=0:
			return false
	for value: Variant in meta.game_world_center_latlon:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)):
			return false
	if float(bbox.lat_min)<=-85 or float(bbox.lat_max)>=85 or float(bbox.lat_min)>=float(bbox.lat_max) or float(bbox.lon_min)>=float(bbox.lon_max):
		return false
	var center: Array = meta.game_world_center_latlon
	var factor: float = meta.game_world_px_per_meter
	var x0 := (float(bbox.lon_min)-float(center[1]))*float(meta.game_world_meters_per_degree_lon_at_center)*factor
	var x1 := (float(bbox.lon_max)-float(center[1]))*float(meta.game_world_meters_per_degree_lon_at_center)*factor
	var y0 := -(float(bbox.lat_max)-float(center[0]))*float(meta.game_world_meters_per_degree_lat)*factor
	var y1 := -(float(bbox.lat_min)-float(center[0]))*float(meta.game_world_meters_per_degree_lat)*factor
	return rect.position.is_finite() and rect.size.is_finite() and rect.position.distance_to(Vector2(x0,y0))<.01 and rect.end.distance_to(Vector2(x1,y1))<.01
