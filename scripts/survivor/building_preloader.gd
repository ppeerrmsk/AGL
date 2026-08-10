class_name BuildingPreloader
extends Control

## 城市建筑 + 正式地图静态 packet 预热 loading 场景
## 在选择飞机后、进入 survivor_mode 前显示，分帧处理 BuildingRenderer 与纯矢量候选缓存
## 完成后切到 survivor_mode.tscn，保证战场启动、首次 A/B 与 Tab 快照不现场构图
##
## 撤回：survivor_select.gd 改回直接 change_scene_to_file 到 survivor_mode.tscn 即可

const NEXT_SCENE := "res://scenes/survivor_mode.tscn"
const ITEMS_PER_FRAME := 30  # 每帧处理多少个街区（30 → ~7 帧完成 195 个）
const MIN_DISPLAY_FRAMES := 6  # 最少展示 6 帧避免一闪而过
const VectorPreviewRenderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const DetailTileCache = preload("res://scripts/survivor/map_detail_tile_cache.gd")
const MAP_LODS := [
	VectorPreviewRenderer.LOD_OPERATIONAL,
	VectorPreviewRenderer.LOD_TAB,
]
const BUILDING_PROGRESS_WEIGHT := 0.35

@onready var _label: Label = $Center/VBox/Label
@onready var _bar: ProgressBar = $Center/VBox/Bar
@onready var _hint: Label = $Center/VBox/Hint

var _frames := 0
var _done := false
var _prewarm_map := false
var _map_lod_index := 0
var _detail_cache_started := false
var _detail_cache_done := false


func _ready() -> void:
	# 缓存可能因为 reset 没生效，强制重置以保证从头跑（对开发期反复测试更稳）
	# 实际玩家进入只走一次，重置成本可忽略
	if not BuildingRenderer.cache_is_ready():
		BuildingRenderer.cache_reset()
	if _label:
		_label.text = tr("PRELOAD_BUILDINGS_LABEL") if TranslationServer else "正在加载城市数据"
	if _hint:
		_hint.text = tr("PRELOAD_BUILDINGS_HINT") if TranslationServer else "横浜 / Yokohama"
	_prewarm_map = OS.is_debug_build() \
		and not get_tree().has_meta("boss_debug_mode") \
		and not get_tree().has_meta("ugc_map_path") \
		and VectorPreviewRenderer.preview_available()
	if _prewarm_map and DetailTileCache.cache_ready():
		_detail_cache_started = true
		_detail_cache_done = true


func _process(_delta: float) -> void:
	_frames += 1
	if _done:
		return

	if not BuildingRenderer.cache_is_ready():
		BuildingRenderer.cache_step(ITEMS_PER_FRAME)
	elif _prewarm_map and _map_lod_index < MAP_LODS.size():
		var half := MapBoundary.WORLD_HALF_PX
		var world_rect := Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0))
		var result: Dictionary = VectorPreviewRenderer.prewarm_lod(
			int(MAP_LODS[_map_lod_index]), world_rect)
		if not bool(result.get("ok", false)):
			push_warning("Vector map prewarm skipped: %s" % result.get("error", "unknown"))
			_prewarm_map = false
		else:
			print("[BuildingPreloader] vector LOD%d prewarmed: triangles=%d cache_hit=%s (%dms)" % [
				int(MAP_LODS[_map_lod_index]), int(result.get("triangles", 0)),
				bool(result.get("cache_hit", false)), int(result.get("build_ms", 0)),
			])
			_map_lod_index += 1
	elif _prewarm_map and not _detail_cache_started:
		_detail_cache_started = true
		call_deferred("_prewarm_detail_cache")

	var building_progress := BuildingRenderer.cache_progress()
	var map_steps_done := _map_lod_index + (1 if _detail_cache_done else 0)
	var map_progress := 1.0 if not _prewarm_map else float(map_steps_done) / float(MAP_LODS.size() + 1)
	if _bar:
		_bar.value = (building_progress * BUILDING_PROGRESS_WEIGHT \
			+ map_progress * (1.0 - BUILDING_PROGRESS_WEIGHT)) * 100.0
	var map_ready := not _prewarm_map or (
		_map_lod_index >= MAP_LODS.size() and _detail_cache_done)
	if BuildingRenderer.cache_is_ready() and map_ready and _frames >= MIN_DISPLAY_FRAMES:
		_finish()


func _prewarm_detail_cache() -> void:
	var detail_cache: Node2D = DetailTileCache.new()
	detail_cache.name = "MapDetailTilePrewarm"
	add_child(detail_cache)
	var result: Dictionary = await detail_cache.bake_cache()
	_detail_cache_done = true
	if bool(result.get("ok", false)):
		print("[BuildingPreloader] detail tile prewarmed: cache=%s bake=%dms resident=%d bytes" % [
			result.get("cache_size", []), int(result.get("bake_ms", 0)),
			int(result.get("cache_bytes_rgba8", 0)),
		])
	else:
		push_warning("Detail tile prewarm skipped: %s" % result.get("error", "unknown"))
	detail_cache.queue_free()


func _finish() -> void:
	_done = true
	get_tree().change_scene_to_file(NEXT_SCENE)
