extends RefCounted
## 真 SceneTree 的静态提交与镜头等价回归；不加载地图或生成战斗单位。
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")

class Host:
	extends Node
	var camera: Camera2D

class WatchedMesh:
	extends MeshInstance3D
	var changes := 0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			changes += 1

var _pass := 0
var _fail := 0


func run() -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# focused 从 AutoLoad._ready 同步调用，此时 root 正在添加 AutoLoad；挂到已入树的 runner。
	(Engine.get_main_loop() as SceneTree).root.get_node("BenchRunner").add_child(viewport)
	if not viewport.is_inside_tree():
		_check(false, "camera fixture entered actual SceneTree")
		viewport.free()
		return false
	var host := Host.new()
	viewport.add_child(host)
	var probe := Probe.new()
	probe.set_process(false)
	var map := WatchedMesh.new()
	var satellite := WatchedMesh.new()
	var leaf := WatchedMesh.new()
	probe._root_map = map
	probe._satellite_ground = satellite
	viewport.add_child(probe)
	probe.add_child(map)
	probe.add_child(satellite)
	satellite.add_child(leaf)
	probe.add_child(probe._camera)
	probe.add_child(probe._sun)
	var reference := Camera3D.new()
	probe.add_child(reference)
	reference.projection = Camera3D.PROJECTION_ORTHOGONAL
	for node in [map, satellite, leaf]:
		node.set_notify_transform(true)
		node.force_update_transform()
		var before: int = node.changes
		node.basis = node.basis
		node.force_update_transform()
		_check(node.changes > before, "same-basis control really propagates transform notification")
	var stable_changes := 0
	var max_depth_error := 0.0
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(913, 677)]:
		viewport.size = size
		for angle in [0.0, 0.21, -0.24, 0.00001]:
			# 两入口角度各自覆盖旋转、平移、缩放与稳定帧；不能让沙漠改动污染正式机体层。
			probe._display_tilt = VolumeProjection.TILT if angle <= 0 else VolumeProjection.DESERT_TILT
			for zoom in [0.2, 0.446, 0.65, 2.0]:
				for pan in [Vector2.ZERO, Vector2(140, 300), Vector2(140.001, 300)]:
					var canvas := Transform2D(angle, pan).scaled_local(Vector2.ONE * zoom)
					viewport.canvas_transform = canvas
					probe._sync_camera(host)
					var inverse := canvas.affine_inverse()
					var screen_size := Vector2(size)
					reference.size = screen_size.y * inverse.y.length()
					var span := reference.size * 0.6 + 1200.0
					reference.near = maxf(0.1, 50000.0 - span)
					reference.far = 50000.0 + span
					max_depth_error = maxf(max_depth_error, absf(reference.near - probe._camera.near))
					max_depth_error = maxf(max_depth_error, absf(reference.far - probe._camera.far))
					var basis := VolumeProjection.camera_basis(canvas, probe._display_tilt)
					var ground := VolumeProjection.ground_basis(canvas, probe._display_tilt)
					var expected := Transform3D(basis,
						ground * Probe.world_point(inverse * (screen_size * 0.5)) + basis.z * 50000.0)
					_check(probe._camera.transform == expected and map.basis == ground and satellite.basis == ground,
						"pan/zoom/rotation/resize retains exact camera and map transforms")
					_check(probe._camera.size == reference.size and probe._camera.near == reference.near
						and probe._camera.far == reference.far and probe._sun.directional_shadow_max_distance == reference.far,
						"combined projection exactly matches former property setters")
					for node in [map, satellite, leaf]:
						node.force_update_transform()
					var before := map.changes + satellite.changes + leaf.changes
					for repeat in 3:
						probe._sync_camera(host)
						for node in [map, satellite, leaf]:
							node.force_update_transform()
					stable_changes += map.changes + satellite.changes + leaf.changes - before
	_check(stable_changes == 0, "stable camera causes zero static subtree notifications")
	print("[Volume camera sync] pass=%d fail=%d stable_notifications=%d max_depth_error=%.9f" % [
		_pass, _fail, stable_changes, max_depth_error])
	viewport.free()
	return _fail == 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume camera sync: " + label)
