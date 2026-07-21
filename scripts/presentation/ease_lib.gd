class_name EaseLib
extends RefCounted

## 缓动函数表（spec ui-transition §2.5）
##
## 全部满足 f(0)=0, f(1)=1。back_out 会过冲到约 1.10 再回落——
## 这是"弹入"手感的来源，故使用方的终点值必须是最终值本身（例如 scale 终点 1.0），
## 不能再额外放大，否则过冲后会停在偏大的位置。

const BACK_C1 := 1.70158
const BACK_C3 := BACK_C1 + 1.0   ## 2.70158

## 按名字取缓动值。未知名字回退 linear（配合 JSON 热重载：写错曲线名不该让演出崩）
static func apply(ease_name: String, t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	match ease_name:
		"linear": return x
		"cubic_out": return cubic_out(x)
		"cubic_in": return cubic_in(x)
		"cubic_in_out": return cubic_in_out(x)
		"expo_out": return expo_out(x)
		"back_out": return back_out(x)
	return x

static func cubic_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv

static func cubic_in(t: float) -> float:
	return t * t * t

static func cubic_in_out(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	var f := -2.0 * t + 2.0
	return 1.0 - (f * f * f) * 0.5

static func expo_out(t: float) -> float:
	if t >= 1.0:
		return 1.0
	return 1.0 - pow(2.0, -10.0 * t)

## 过冲缓动。注意 back_out(1) 必须精确等于 1.0——
## 浮点上 c3*0 + c1*0 = 0，故恒等成立，无需特判
static func back_out(t: float) -> float:
	var f := t - 1.0
	return 1.0 + BACK_C3 * f * f * f + BACK_C1 * f * f
