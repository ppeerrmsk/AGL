class_name BuildingPreloader
extends Control

## 城市建筑数据预热 loading 场景
## 在选择飞机后、进入 survivor_mode 前显示，分帧处理 BuildingRenderer 的静态缓存
## 完成后切到 survivor_mode.tscn，保证战场启动时秒读
##
## 撤回：survivor_select.gd 改回直接 change_scene_to_file 到 survivor_mode.tscn 即可

const NEXT_SCENE := "res://scenes/survivor_mode.tscn"
const ITEMS_PER_FRAME := 30  # 每帧处理多少个街区（30 → ~7 帧完成 195 个）
const MIN_DISPLAY_FRAMES := 6  # 最少展示 6 帧避免一闪而过

@onready var _label: Label = $Center/VBox/Label
@onready var _bar: ProgressBar = $Center/VBox/Bar
@onready var _hint: Label = $Center/VBox/Hint

var _frames := 0
var _done := false


func _ready() -> void:
	# 缓存可能因为 reset 没生效，强制重置以保证从头跑（对开发期反复测试更稳）
	# 实际玩家进入只走一次，重置成本可忽略
	if not BuildingRenderer.cache_is_ready():
		BuildingRenderer.cache_reset()
	if _label:
		_label.text = tr("PRELOAD_BUILDINGS_LABEL") if TranslationServer else "正在加载城市数据"
	if _hint:
		_hint.text = tr("PRELOAD_BUILDINGS_HINT") if TranslationServer else "横浜 / Yokohama"


func _process(_delta: float) -> void:
	_frames += 1
	if _done:
		return

	# 已经预热好了（场景被重新进入，比如玩家死亡后重开）
	if BuildingRenderer.cache_is_ready():
		if _bar:
			_bar.value = 100.0
		if _frames >= MIN_DISPLAY_FRAMES:
			_finish()
		return

	BuildingRenderer.cache_step(ITEMS_PER_FRAME)
	var pct := BuildingRenderer.cache_progress() * 100.0
	if _bar:
		_bar.value = pct
	if BuildingRenderer.cache_is_ready() and _frames >= MIN_DISPLAY_FRAMES:
		_finish()


func _finish() -> void:
	_done = true
	get_tree().change_scene_to_file(NEXT_SCENE)
