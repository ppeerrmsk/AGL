extends RefCounted

## 显示节拍（物理插值白名单 + 显示态 + 帧上限）回归。
## 真 SceneTree：夹具挂到已入树的 BenchRunner（AutoLoad _ready 期间 root 仍在装配）。

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 显示节拍 / 物理插值测试 ════════")
	var tree := Engine.get_main_loop() as SceneTree
	var was_enabled := DisplayPacing.interpolation_enabled()
	var project_on := bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	_check("项目开启 2D 物理插值", project_on)
	_check("根节点默认关闭插值（白名单）",
		tree.root.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)
	if OS.get_environment(DisplayPacing.ENV_INTERP).strip_edges() == "":
		_check("未覆盖时运行态跟随项目开关", tree.physics_interpolation == project_on
			and was_enabled == project_on)
	DisplayPacing.set_interpolation_enabled(tree, true)
	_check("插值开启时 jitter fix 归零", is_zero_approx(Engine.physics_jitter_fix))

	var host := Node2D.new()
	host.name = "DisplayPacingFixture"
	host.position = Vector2(1000.0, -500.0)
	tree.root.get_node("BenchRunner").add_child(host)
	var plain := Node2D.new()
	host.add_child(plain)
	_check("普通 Node2D 继承关闭", not plain.is_physics_interpolated())

	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.params = load("res://resources/playable_f14_base.tres")
	host.add_child(ac)
	_check("Aircraft 入白名单开启插值",
		ac.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON
		and ac.is_physics_interpolated())
	var trail: TrailRibbon = ac._trail_ribbon
	_check("尾迹显式关闭插值（每渲染帧自行抵消父机）",
		trail != null and not trail.is_physics_interpolated())

	# 显示态 = prev.interpolate_with(curr, f)，父容器变换照常叠加。
	ac.position = Vector2(200.0, 40.0)
	ac.rotation = 0.6
	ac.interp_prev_xform = Transform2D(0.2, Vector2(100.0, 0.0))
	ac.interp_prev_tick = Engine.get_physics_frames()
	var f := Engine.get_physics_interpolation_fraction()
	var expected_local := Transform2D(0.2, Vector2(100.0, 0.0)).interpolate_with(ac.transform, f)
	_check("本 tick 已记录 prev → 判定为插值中", DisplayPacing.is_interpolating(ac))
	_check("显示原点 = 父变换 × 插值本地原点",
		DisplayPacing.display_origin(ac).is_equal_approx(host.transform * expected_local.origin))
	_check("显示航向差 = 插值旋转 − 物理旋转", is_equal_approx(
		DisplayPacing.display_rotation_offset(ac),
		angle_difference(0.6, expected_local.get_rotation())))
	_check("单次求值航向差与逐项求值一致", is_equal_approx(
		DisplayPacing.rotation_offset_from(ac, DisplayPacing.display_global_transform(ac)),
		DisplayPacing.display_rotation_offset(ac)))
	_check("显示屏幕原点 = 画布变换 × 显示原点",
		DisplayPacing.display_screen_origin(ac).is_equal_approx(
			ac.get_canvas_transform() * DisplayPacing.display_origin(ac)))

	# 尾迹本地变换必须抵消父机显示态，渲染结果恒为世界单位矩阵。
	trail._process_trail_untraced(0.0)
	var composed := DisplayPacing.display_global_transform(ac) * trail.transform
	_check("尾迹抵消父机显示态后合成为单位矩阵",
		composed.origin.length() < 0.001 and is_equal_approx(composed.get_rotation(), 0.0)
		and composed.get_scale().is_equal_approx(Vector2.ONE))

	# 镜头跟随插值显示态（lerp_t 钳到 1 时恰好落在显示位置）。
	var camera := Camera2D.new()
	host.add_child(camera)
	var cam_ctrl := CameraController.new()
	host.add_child(cam_ctrl)
	cam_ctrl.setup(camera)
	cam_ctrl.set_follow_target(ac)
	camera.global_position = Vector2(-9000.0, 0.0)
	cam_ctrl._update_follow(1.0)
	_check("镜头跟随目标取显示态而非物理位置",
		camera.global_position.is_equal_approx(DisplayPacing.display_origin(ac)))
	_check("Camera2D 不进插值白名单（_process 驱动）", not camera.is_physics_interpolated())
	_check_viewport_subtree(host)

	# 过期 prev（本 tick 未跑物理）与插值关闭都回退到物理位置。
	ac.interp_prev_tick = Engine.get_physics_frames() - 1
	_check("prev 过期时回退 global_position",
		DisplayPacing.display_origin(ac).is_equal_approx(ac.global_position))
	ac.interp_prev_tick = Engine.get_physics_frames()
	DisplayPacing.set_interpolation_enabled(tree, false)
	_check("插值关闭时回退 global_position",
		DisplayPacing.display_origin(ac).is_equal_approx(ac.global_position))
	_check("插值关闭时 jitter fix 恢复项目值", is_equal_approx(Engine.physics_jitter_fix,
		float(ProjectSettings.get_setting(DisplayPacing.JITTER_FIX_SETTING, 0.5))))
	DisplayPacing.set_interpolation_enabled(tree, true)

	# 传送收口：clear_trail 重置插值，显示态立即等于新位置。
	ac.position = Vector2(5000.0, 5000.0)
	ac.clear_trail()
	_check("clear_trail 传送收口重置插值起点",
		DisplayPacing.display_origin(ac).is_equal_approx(ac.global_position))

	var missile := Missile.new()
	host.add_child(missile)
	_check("Missile 入白名单开启插值",
		missile.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON
		and missile.is_physics_interpolated())
	missile.position = Vector2(30.0, 0.0)
	missile.interp_prev_xform = Transform2D(0.0, Vector2(10.0, 0.0))
	missile.interp_prev_tick = Engine.get_physics_frames()
	_check("导弹显示原点按 prev→curr 插值", DisplayPacing.display_origin(missile).is_equal_approx(
		host.transform * Vector2(10.0, 0.0).lerp(Vector2(30.0, 0.0), f)))

	# 帧上限：0 = 不限；过低值钳到下限；设置立即作用于 Engine.max_fps。
	var prev_fps := DisplayPacing.max_fps()
	_check("帧上限 0 表示不限", DisplayPacing.normalized_max_fps(0) == 0
		and DisplayPacing.normalized_max_fps(-5) == 0)
	_check("帧上限钳到下限", DisplayPacing.normalized_max_fps(10) == DisplayPacing.MIN_MAX_FPS)
	DisplayPacing.set_max_fps(120, false)
	_check("帧上限写入 Engine.max_fps", Engine.max_fps == 120 and DisplayPacing.max_fps() == 120)
	DisplayPacing.set_max_fps(prev_fps, false)
	_check("帧上限可还原", Engine.max_fps == prev_fps)

	# 诊断脚本只在 AGL_FRAME_PROBE 时运行期加载；此处提前编译，免得 A/B 时才暴露解析错误。
	_check("FrameProbe 与自动驾驶截帧脚本可编译",
		load("res://scripts/diagnostics/frame_probe.gd") != null
		and load("res://scripts/diagnostics/frame_probe_autoplay.gd") != null)

	host.free()
	DisplayPacing.set_interpolation_enabled(tree, was_enabled)
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


## SubViewport 子树（正式三维飞机合成层、地图瓦片可见性等）同样必须保持非插值：
## 否则 Camera2D 被引擎改走物理插值路径，force_update_scroll 不再立即刷新画布变换。
func _check_viewport_subtree(host: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(viewport)
	var camera := Camera2D.new()
	viewport.add_child(camera)
	var node_3d := Node3D.new()
	viewport.add_child(node_3d)
	print("  · SubViewport mode=%d interp=%s Camera2D interp=%s Node3D interp=%s" % [
		viewport.physics_interpolation_mode, viewport.is_physics_interpolated(), camera.is_physics_interpolated(),
		node_3d.is_physics_interpolated()])
	_check("SubViewport 子树继承关闭插值", not viewport.is_physics_interpolated()
		and not camera.is_physics_interpolated() and not node_3d.is_physics_interpolated())
	camera.position = Vector2(4000.0, -3000.0)
	camera.zoom = Vector2.ONE * 0.5
	camera.force_update_scroll()
	var center := viewport.canvas_transform.affine_inverse() * (Vector2(viewport.size) * 0.5)
	print("  · SubViewport camera center after force_update_scroll = %s" % center)
	_check("SubViewport 镜头 force_update_scroll 立即刷新画布变换",
		center.distance_to(camera.position) < 0.5)
	var root_camera := Camera2D.new()
	host.add_child(root_camera)
	root_camera.make_current()
	root_camera.position = Vector2(-2500.0, 1500.0)
	root_camera.force_update_scroll()
	var root_vp := host.get_viewport()
	var root_center := root_vp.canvas_transform.affine_inverse() \
		* (root_vp.get_visible_rect().size * 0.5)
	print("  · root camera center after force_update_scroll = %s" % root_center)
	_check("主视口镜头 force_update_scroll 立即刷新画布变换",
		root_center.distance_to(root_camera.global_position) < 0.5)
	root_camera.free()
	viewport.free()


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
