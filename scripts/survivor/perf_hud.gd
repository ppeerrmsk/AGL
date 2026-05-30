class_name PerfHUD
extends CanvasLayer

## 性能 baseline HUD（F6 切换）
##
## 用于渲染重构期间 A/B 对比：USE_SPRITE_AIRCRAFT_ICONS / USE_MULTIMESH_BULLETS 改前改后跑同一压力场景，
## 看 FPS / draw_call / canvas_items 三件套的变化。详见 docs/planning/sprite-multimesh-refactor.md。
##
## 初始可见性由 GameConstants.SHOW_PERF_HUD 决定；运行时按 F6 toggle。
## 0.25s 节流采样，避免 HUD 自身变成开销源。
##
## 用法：survivor_mode._ready() 里 add_child(PerfHUD.new())；F6 处理在 survivor_mode 输入分发里调
## set_hud_visible(not _perf_hud.is_hud_visible())

const SAMPLE_INTERVAL: float = 0.25  ## 每 250ms 刷新一次，HUD 自身开销最低
const LABEL_FONT_SIZE: int = 14
const LABEL_MARGIN: Vector2 = Vector2(10, 10)

var _label: Label
var _sample_timer: float = 0.0
var _bullet_manager_ref: BulletManager = null

func _ready() -> void:
	# CanvasLayer.layer 设高让 HUD 压在 UI 之上
	layer = 100
	_label = Label.new()
	_label.position = LABEL_MARGIN
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 3)
	_label.text = "perf hud loading…"
	add_child(_label)
	visible = GameConstants.SHOW_PERF_HUD
	# 不暂停时也刷新，方便升级面板期间继续看
	process_mode = Node.PROCESS_MODE_ALWAYS

## 由 survivor_mode 在初始化阶段塞进来，避免每帧 find_child
func attach_bullet_manager(bm: BulletManager) -> void:
	_bullet_manager_ref = bm

func toggle_visible() -> void:
	visible = not visible

func is_hud_visible() -> bool:
	return visible

func set_hud_visible(v: bool) -> void:
	visible = v

func _process(delta: float) -> void:
	if not visible:
		return
	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer = SAMPLE_INTERVAL
	_refresh_label()

func _refresh_label() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# 飞机 / 敌机分桶（用 CombatUnit.all_units 全局表）
	var ally_ac: int = 0
	var enemy_ac: int = 0
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or u.is_destroyed:
			continue
		if not (u is Aircraft):
			continue
		if u.team == 0:
			ally_ac += 1
		else:
			enemy_ac += 1

	var bullet_n: int = 0
	var torpedo_n: int = 0
	if _bullet_manager_ref != null and is_instance_valid(_bullet_manager_ref):
		bullet_n = _bullet_manager_ref.active_bullet_count()
		torpedo_n = _bullet_manager_ref.active_torpedo_count()

	# Feature flag 当前状态 —— 重构期一眼看清是哪条路径
	var flag_sprite := "ON" if GameConstants.USE_SPRITE_AIRCRAFT_ICONS else "off"
	var flag_mm := "ON" if GameConstants.USE_MULTIMESH_BULLETS else "off"

	_label.text = "PERF (F6 toggle)\nFPS: %.1f  proc %.2fms  phys %.2fms\ndraw_call: %d  objs: %d  prims: %d\nnodes: %d\nAC: %d ally / %d enemy\nbullets: %d  torpedoes: %d\n[sprite: %s | multimesh: %s]" % [
		fps, proc_ms, phys_ms,
		draw_calls, objs, prims,
		node_count,
		ally_ac, enemy_ac,
		bullet_n, torpedo_n,
		flag_sprite, flag_mm,
	]
