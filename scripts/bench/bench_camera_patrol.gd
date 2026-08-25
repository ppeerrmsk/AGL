class_name BenchCameraPatrol
extends RefCounted

## 自动战斗性能门的确定性观察者轨迹。
## 位置按战场跨度归一化；同一 elapsed/span/base_zoom 必须得到完全相同的结果。

const PERIOD_SECONDS := 18.0
const ZOOM_MAX := 0.46

const POSITION_KEYS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2.ZERO,
	Vector2(-0.11, -0.40),
	Vector2(0.11, -0.25),
	Vector2.ZERO,
	Vector2(-0.11, 0.18),
	Vector2(0.11, 0.34),
	Vector2(0.00, 0.40),
	Vector2.ZERO,
]
const ZOOM_FACTOR_KEYS: Array[float] = [
	1.00, 1.00, 1.35, 1.65, 1.10, 1.55, 1.70, 1.35, 1.00,
]
const ROTATION_DEG_KEYS: Array[float] = [
	0.0, 0.0, -14.0, 8.0, 0.0, 12.0, -10.0, 6.0, 0.0,
]


static func segment_count() -> int:
	return POSITION_KEYS.size() - 1


static func sample(elapsed: float, span_px: float, base_zoom: float) -> Dictionary:
	var state: Dictionary = {}
	sample_into(state, elapsed, span_px, base_zoom)
	return state


## 真实性能场复用同一个 Dictionary，避免巡检器自己每渲染帧制造分配噪声。
static func sample_into(state: Dictionary, elapsed: float, span_px: float,
		base_zoom: float) -> void:
	var count := segment_count()
	var wrapped := fposmod(maxf(elapsed, 0.0), PERIOD_SECONDS)
	var scaled := wrapped / PERIOD_SECONDS * float(count)
	var segment := mini(int(floor(scaled)), count - 1)
	var local_t := scaled - float(segment)
	var smooth_t := smoothstep(0.0, 1.0, local_t)
	var position := POSITION_KEYS[segment].lerp(POSITION_KEYS[segment + 1], smooth_t) \
		* maxf(span_px, 0.0)
	var zoom_factor := lerpf(ZOOM_FACTOR_KEYS[segment],
		ZOOM_FACTOR_KEYS[segment + 1], smooth_t)
	var zoom := clampf(base_zoom * zoom_factor, CameraController.ZOOM_MIN, ZOOM_MAX)
	var rotation_deg := lerpf(ROTATION_DEG_KEYS[segment],
		ROTATION_DEG_KEYS[segment + 1], smooth_t)
	state["position"] = position
	state["zoom"] = zoom
	state["rotation"] = deg_to_rad(rotation_deg)
	state["segment"] = segment
