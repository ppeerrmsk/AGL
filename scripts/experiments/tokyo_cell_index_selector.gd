extends RefCounted
## 候选连续域选择：仅返回已预载身份；无合法索引时拒绝，不沿用旧画面。

static func select(packet: Dictionary, center: Vector2, scale_value: float, rotation_value: float, tilt: float, viewport: Vector2i, resident: Dictionary) -> Dictionary:
	if not center.is_finite() or not is_finite(scale_value) or not is_finite(rotation_value) or not is_finite(tilt):return {}
	if not packet.get("cell_index_union_conservative",false) or not packet.get("continuous_capacity_verified",false):return {}
	if not resident.get("geometry_ready",false) or not resident.get("textures_ready",false):return {}
	if resident.get("vertices_sha256","")!=packet.get("vertices_sha256",""):return {}
	if resident.get("selection_sha256","")!=packet.get("selection_sha256",""):return {}
	var identities: Dictionary=resident.get("index_identities",{})
	for row: Dictionary in packet.get("rows",[]):
		if row.has("scale_interval"):
			var interval: Array=row.scale_interval
			if not packet.get("continuous_scale_capacity_verified",false) or interval.size()!=2:continue
			if not is_finite(float(interval[0])) or not is_finite(float(interval[1])) or float(interval[0])<=0 or float(interval[1])<float(interval[0]):continue
			if scale_value<float(interval[0]) or scale_value>float(interval[1]):continue
		elif float(row.scale)!=scale_value:continue
		if float(row.rotation)!=rotation_value or float(row.tilt_degrees)!=tilt:continue
		if Vector2i(int(row.viewport[0]),int(row.viewport[1]))!=viewport:continue
		var bounds: Array=row.camera_bounds
		if center.x<float(bounds[0]) or center.y<float(bounds[1]) or center.x>float(bounds[2]) or center.y>float(bounds[3]):continue
		if not identities.get(row.sha256,false):continue
		return {"leaf":int(row.certificate_leaf),"index_sha256":row.sha256}
	return {}
