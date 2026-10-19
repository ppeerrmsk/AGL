extends RefCounted
## 只生成玩家可用的检查位置，不依赖Loading或地图节点，避免测试脚本循环引用。


static func poses() -> Array:
	var spawn := MapBoundary.get_player_start()
	return [[spawn.x,spawn.y,CameraController.START_ZOOM],
		[-4300,-3700,CameraController.ZOOM_MIN],[-4300,-3700,CameraController.START_ZOOM],
		[-4300,-3700,0.7],[-4300,-3700,1.5],[-4300,-3700,3.0],
		[-4300,-3700,CameraController.ZOOM_MAX],[9000,8000,CameraController.START_ZOOM]]


static func checks() -> bool:
	var values := poses()
	if values.size()!=8 or values[0][2]!=CameraController.START_ZOOM: return false
	for pose: Array in values:
		if pose[2]<CameraController.ZOOM_MIN or pose[2]>CameraController.ZOOM_MAX: return false
	return values[1][2]==CameraController.ZOOM_MIN and values[6][2]==CameraController.ZOOM_MAX
