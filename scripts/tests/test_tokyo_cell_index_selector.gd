extends RefCounted
const Selector := preload("res://scripts/experiments/tokyo_cell_index_selector.gd")

static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.cell_index_contract
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var resident := {"geometry_ready":true,"textures_ready":true,"vertices_sha256":packet.vertices_sha256,"selection_sha256":packet.selection_sha256,"index_identities":{}}
	for row: Dictionary in packet.rows:
		if FileAccess.get_sha256(row.indices)!=row.sha256:return 1
		resident.index_identities[row.sha256]=true
	var probes := 0
	for row: Dictionary in packet.rows:
		var b: Array=row.camera_bounds
		for x: float in [b[0],(b[0]+b[2])*0.5,b[2]]:
			for y: float in [b[1],(b[1]+b[3])*0.5,b[3]]:
				var center := Vector2(x,y)
				# Godot世界坐标是float32；边界外舍入不冒充合法域，内部中心必须有解。
				var chosen := Selector.select(packet,center,float(row.scale),0,38,Vector2i(1600,900),resident)
				var domain: Array=packet.continuous_cell_bounds
				var inside := center.x>=float(domain[0]) and center.y>=float(domain[1]) and center.x<=float(domain[2]) and center.y<=float(domain[3])
				if inside and chosen.is_empty():return 1
				if not inside and not chosen.is_empty():return 1
				probes+=1
	var row: Dictionary=packet.rows[0]
	var center := Vector2(row.pose[0],row.pose[1])
	for bad: Dictionary in [{"geometry_ready":false},{"textures_ready":false},{"vertices_sha256":"wrong"},{"selection_sha256":"wrong"},{"index_identities":{}}]:
		var state := resident.duplicate(true);state.merge(bad,true)
		if not Selector.select(packet,center,0.625,0,38,Vector2i(1600,900),state).is_empty():return 1
	for pose: Array in [[center,0.624,0.0,38.0,Vector2i(1600,900)],[center,0.625,0.1,38.0,Vector2i(1600,900)],[center,0.625,0.0,37.0,Vector2i(1600,900)],[center,0.625,0.0,38.0,Vector2i(1920,1080)],[center+Vector2(10000,0),0.625,0.0,38.0,Vector2i(1600,900)]]:
		if not Selector.select(packet,pose[0],pose[1],pose[2],pose[3],pose[4],resident).is_empty():return 1
	print("Tokyo cell selector: ",probes," probes, readiness/scope rejection passed; not runtime coverage acceptance")
	return 0
