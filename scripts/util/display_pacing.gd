extends RefCounted

## 显示节拍：2D 物理插值（白名单）+ 可选帧上限。静态服务，不新增 AutoLoad。
## 消费方以 `const DisplayPacing := preload("res://scripts/util/display_pacing.gd")` 引用
## （不登记 class_name：Shadow bench 只复用编辑器生成的类缓存）。
##
## 物理固定 60Hz，渲染不限帧时，未插值的位移只在有物理步的渲染帧出现，且按 13–20ms
## 不均匀间隔呈现；镜头在 _process 追逐按 tick 跳变的目标，屏幕滚动逐帧忽快忽慢。
##
## 白名单：project.godot 打开 physics/common/physics_interpolation 后，install() 把 root
## 默认改为关闭插值；只有确认"只在 _physics_process 里移动"的 Aircraft / Missile 显式开启。
## 镜头、UI、VFX、尾迹等在 _process 改变换的节点保持旧语义，不会被引擎按 tick 错误插值。
##
## 显示态：引擎在每个物理步开头把 prev←curr，渲染时按 Engine.get_physics_interpolation_fraction()
## 插值本地变换。Aircraft / Missile 在 _physics_process 开头记录 interp_prev_xform/tick
## （= 引擎 prev），消费方（镜头跟随、世界标签、尾迹、三维机体合成、FrameProbe）经
## display_*() 读取与引擎同一相位的显示位置。游戏逻辑仍只读 global_position。
##
## 环境变量：AGL_PHYSICS_INTERP=0/1 覆盖项目开关（A/B 对比）；AGL_MAX_FPS=<n> 覆盖帧上限。
## 玩家帧上限持久化在 user://display.cfg [display] max_fps（0 = 不限，跟随 VSync）。

const CONFIG_PATH := "user://display.cfg"
const ENV_INTERP := "AGL_PHYSICS_INTERP"
const ENV_MAX_FPS := "AGL_MAX_FPS"
const MIN_MAX_FPS := 30
const JITTER_FIX_SETTING := "physics/common/physics_jitter_fix"

static var _installed: bool = false
static var _enabled: bool = false
static var _max_fps: int = 0


## 启动时由 Presentation._ready 调用一次（AutoLoad 早于任何战斗场景）。
static func install(tree: SceneTree) -> void:
	if _installed or tree == null:
		return
	_installed = true
	# 白名单：根默认关闭；Aircraft / Missile 在 _ready 显式开启。
	tree.root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# 实测 Godot 4.7：SubViewport/Window 会重新成为插值根（子树回到默认开启），其中的 Camera2D 被
	# 强制改走物理插值路径（force_update_scroll 不再立即刷新画布），三维合成层 Node3D 也被 FTI 插值。
	# 节点入树时把 Viewport 显式关闭；node_added 早于其子节点入树，子树随之继承关闭。
	tree.node_added.connect(func(node: Node) -> void: _demote_viewport(node))
	var enabled := bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	var override := OS.get_environment(ENV_INTERP).strip_edges().to_lower()
	if override in ["0", "false", "off"]:
		enabled = false
	elif override in ["1", "true", "on"]:
		enabled = true
	set_interpolation_enabled(tree, enabled)
	var fps := _load_max_fps()
	var env_fps := OS.get_environment(ENV_MAX_FPS).strip_edges()
	if env_fps.is_valid_int():
		fps = int(env_fps)
	_apply_max_fps(fps)


static func _demote_viewport(node: Node) -> void:
	# Viewport 默认模式并非 INHERIT（实测入树后仍为插值根），故不看原模式一律关闭；本项目无需插值的视口。
	if node is Viewport:
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func set_interpolation_enabled(tree: SceneTree, enabled: bool) -> void:
	_enabled = enabled
	tree.physics_interpolation = enabled
	# 插值已吸收 tick 与渲染帧的相位差；jitter fix 只会把 tick 挤到帧边界，按引擎建议关闭。
	# 关闭插值时恢复项目值，A/B 基线与旧行为逐字节一致。
	Engine.physics_jitter_fix = 0.0 if enabled \
		else float(ProjectSettings.get_setting(JITTER_FIX_SETTING, 0.5))


static func interpolation_enabled() -> bool:
	return _enabled


## 显示时刻相对最近物理步末的滞后（秒）：插值画面呈现的是 (1-f) 个 tick 之前的状态。
## 按物理时间驱动的显示消费方（如 bench 巡检镜头）减去它，即与插值后的单位同相位。
static func display_time_lag() -> float:
	if not _enabled:
		return 0.0
	return (1.0 - Engine.get_physics_interpolation_fraction()) \
		* Engine.time_scale / float(Engine.physics_ticks_per_second)


## 节点当前是否按引擎插值显示（白名单节点 + 本 tick 已记录 prev）。
## 消费方每帧按单位调用：先判全局开关与原生插值标志，再查记录帧号；各 display_* 只判一次。
static func is_interpolating(node: Node2D) -> bool:
	if not _enabled or node == null or not node.is_physics_interpolated():
		return false
	return _prev_tick_of(node) == Engine.get_physics_frames()


## 显示态本地变换：与引擎 TransformInterpolator 同式 prev.interpolate_with(curr, f)。
static func display_local_transform(node: Node2D) -> Transform2D:
	if not is_interpolating(node):
		return node.transform
	return _interpolated_local(node)


## 显示态全局变换。父节点视为不插值（Aircraft / Missile 的容器都是静止节点）。
static func display_global_transform(node: Node2D) -> Transform2D:
	if not is_interpolating(node):
		return node.get_global_transform()
	return _interpolated_global(node)


static func display_origin(node: Node2D) -> Vector2:
	if not is_interpolating(node):
		return node.global_position
	return _interpolated_global(node).origin


## 显示态在所属画布（含 Camera2D）中的屏幕原点；不插值时与 get_global_transform_with_canvas 一致。
static func display_screen_origin(item: Node2D) -> Vector2:
	if not is_interpolating(item):
		return item.get_global_transform_with_canvas().origin
	return item.get_canvas_transform() * _interpolated_global(item).origin


## 显示态相对物理态的旋转差（弧度，通常 ≤ 0 的滞后）；heading 消费方加上它即得显示航向。
static func display_rotation_offset(node: Node2D) -> float:
	if not is_interpolating(node):
		return 0.0
	return angle_difference(node.rotation, _interpolated_local(node).get_rotation())


## 由显示态全局变换求航向偏移（调用方已取到 display_global_transform 时复用，免二次插值）。
static func rotation_offset_from(node: Node2D, display_global: Transform2D) -> float:
	return angle_difference(node.global_rotation, display_global.get_rotation())


## 同一渲染帧内多个消费方读同一单位时只插值一次；物理帧号进键，物理步中途的读取不会复用旧帧结果。
static func _interpolated_global(node: Node2D) -> Transform2D:
	var proc := Engine.get_process_frames()
	var tick := Engine.get_physics_frames()
	if node is Aircraft:
		var ac := node as Aircraft
		if ac.interp_cache_proc != proc or ac.interp_cache_tick != tick:
			ac.interp_cache_xform = _compose_global(node, ac.interp_prev_xform)
			ac.interp_cache_proc = proc
			ac.interp_cache_tick = tick
		return ac.interp_cache_xform
	if node is Missile:
		var missile := node as Missile
		if missile.interp_cache_proc != proc or missile.interp_cache_tick != tick:
			missile.interp_cache_xform = _compose_global(node, missile.interp_prev_xform)
			missile.interp_cache_proc = proc
			missile.interp_cache_tick = tick
		return missile.interp_cache_xform
	return node.get_global_transform()


static func _compose_global(node: Node2D, prev_local: Transform2D) -> Transform2D:
	var local := prev_local.interpolate_with(node.transform, Engine.get_physics_interpolation_fraction())
	var parent_item := node.get_parent() as CanvasItem
	if parent_item == null or node.top_level:
		return local
	return parent_item.get_global_transform() * local


static func _interpolated_local(node: Node2D) -> Transform2D:
	return _prev_xform_of(node).interpolate_with(node.transform,
		Engine.get_physics_interpolation_fraction())


static func _prev_tick_of(node: Node2D) -> int:
	if node is Aircraft:
		return (node as Aircraft).interp_prev_tick
	if node is Missile:
		return (node as Missile).interp_prev_tick
	return -1


static func _prev_xform_of(node: Node2D) -> Transform2D:
	if node is Aircraft:
		return (node as Aircraft).interp_prev_xform
	if node is Missile:
		return (node as Missile).interp_prev_xform
	return node.transform


# ───────────────────────── 帧上限 ─────────────────────────

static func max_fps() -> int:
	return _max_fps


## 0 = 不限（跟随 VSync）；其余值钳到 ≥ MIN_MAX_FPS。插值开启后上限不必是 tick 整数倍，
## 但关闭插值时建议取 60 的整数倍（120/180/240），高刷屏优先取刷新率的整数分之一。
static func set_max_fps(value: int, persist: bool = true) -> void:
	_apply_max_fps(value)
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("display", "max_fps", _max_fps)
	cfg.save(CONFIG_PATH)


static func normalized_max_fps(value: int) -> int:
	return 0 if value <= 0 else maxi(value, MIN_MAX_FPS)


static func _apply_max_fps(value: int) -> void:
	_max_fps = normalized_max_fps(value)
	Engine.max_fps = _max_fps


static func _load_max_fps() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return int(ProjectSettings.get_setting("application/run/max_fps", 0))
	return int(cfg.get_value("display", "max_fps", 0))
