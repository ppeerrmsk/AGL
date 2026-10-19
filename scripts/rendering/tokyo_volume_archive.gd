extends Resource
## 首区离线归档；运行时只绑定 Mesh，不读 JSON 或逐栋构图。
const PATH := "res://resources/maps/tokyo_volume_preview/downtown_lod.res"
const SCALES := [0.10, 0.20, 0.40, 0.80, 1.60, 3.20]
const CUTS := [0.09, 0.18, 0.36, 0.72, 1.44]
const MEMORY_BUDGET := 96 * 1024 * 1024
@export var schema_version := 1
@export var bounds := Rect2()
@export var source_hash := ""
@export var building_count := 0
@export var geometry_bytes := 0
@export var levels: Array[Dictionary] = []
@export var ground: ArrayMesh
@export var roads: ArrayMesh
@export var rails: ArrayMesh


static func choose_level(current: int, output_scale: float) -> int:
	if current < 0:
		var initial := 0
		while initial < CUTS.size() and output_scale >= float(CUTS[initial]):
			initial += 1
		return initial
	var next := clampi(current, 0, SCALES.size() - 1)
	while next < CUTS.size() and output_scale >= float(CUTS[next]) * 1.08:
		next += 1
	while next > 0 and output_scale < float(CUTS[next - 1]) * 0.92:
		next -= 1
	return next


func valid() -> bool:
	return schema_version == 1 and levels.size() == SCALES.size() \
		and ground != null and roads != null and rails != null \
		and building_count > 0 and geometry_bytes <= MEMORY_BUDGET and bounds.has_area()
