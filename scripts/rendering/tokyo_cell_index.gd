extends Resource
## 只含路径/空间范围的轻量目录；禁止在目录内嵌六档 Mesh。
const PATH := "res://resources/maps/tokyo_volume_preview/r6_cells/index.res"
const LEVELS := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const MAX_CELLS := 16
@export var schema_version := 1
@export var bounds := Rect2()
@export var source_hash := ""
@export var source_count := 0
@export var surface_only := false
@export var cells: Array[Dictionary] = []
@export var regional_id := ""
@export var regional_registry_hash := ""
@export var regional_nonowner_ids := PackedStringArray()
@export var joined_sources: Dictionary = {}
@export var coverage_rects: Array[Rect2] = []
@export var shadow_cells: Array[Dictionary] = []


func valid(joined_registry_hash: String = "") -> bool:
	# 联合专用包不允许现有单区Overlay误加载；显式摘要仅供离线结构验证。
	if not regional_id.is_empty() or not regional_registry_hash.is_empty() or not regional_nonowner_ids.is_empty():
		if regional_id.is_empty() or regional_registry_hash.length() != 64 or joined_registry_hash != regional_registry_hash:
			return false
	if schema_version != 1 or not bounds.has_area() or source_count < 0 or (source_count == 0) != surface_only or cells.size() != MAX_CELLS:
		return false
	if not shadow_cells.is_empty() and shadow_cells.size() != MAX_CELLS:
		return false
	if surface_only:
		var hashes := source_hash.split(":")
		if hashes.size()!=2:
			return false
		for digest: String in hashes:
			if digest.length()!=64 or not digest.is_valid_hex_number():
				return false
	for index in cells.size():
		var cell: Dictionary = cells[index]
		if int(cell.get("id", -1)) != index or not cell.get("bounds", Rect2()).has_area():
			return false
		if not cell.get("levels", []) is Array or cell.levels.size() != LEVELS.SCALES.size():
			return false
		if surface_only:
			if int(cell.get("source_count",-1))!=0:
				return false
			var entries: Array = cell.levels.duplicate()
			if cell.has("mid"):
				entries.append(cell.mid)
			for descriptor: Variant in entries:
				if not descriptor is Dictionary or descriptor.get("bytes",-1)!=0 or descriptor.get("triangles",-1)!=0 or descriptor.get("counts")!=[0,0,0,0]:
					return false
		if cell.has("mid"):
			if not cell.mid is Dictionary or String(cell.mid.get("path", "")).is_empty() \
					or int(cell.mid.get("bytes", -1)) < 0 or int(cell.mid.get("triangles", -1)) < 0 \
					or String(cell.mid.get("height_hash", "")) != String(cell.levels[4].get("height_hash", "invalid")):
				return false
	return true


func visible_cells(view: Rect2, margin: float = -1.0) -> PackedInt32Array:
	var result := PackedInt32Array()
	for cell: Dictionary in cells:
		# 内容包围盒含整栋跨格建筑；不能只按 owner 格裁掉高楼。
		var guard: float = cell.get("visibility_margin", 350.0) if margin < 0.0 else margin
		if (cell.content_bounds as Rect2).grow(guard).intersects(view):
			result.append(int(cell.id))
	return result
