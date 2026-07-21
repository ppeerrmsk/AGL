class_name SequencePlayer
extends RefCounted

## 序列时间线运行器（spec ui-transition §2.12 / §3.1）
##
## 职责单一：按 unscaled 时间推进，算出"这一帧哪些 step 处于活跃、各自的缓动进度"。
## 【不认识任何通道】——通道分发是导演的事。这样加新通道不用改本文件。
##
## step 字段：
##   at    起始秒（必填）
##   dur   时长；缺省或 <=0 视为瞬时（只在跨过 at 的那一帧发一次，t=1.0）
##   ease  缓动名；缺省 linear
##   其余字段原样透传给导演

## 一次 advance 的产出
class Tick extends RefCounted:
	var step: Dictionary
	var t: float          ## 缓动后的进度 0..1
	var raw_t: float      ## 线性进度 0..1
	var first: bool       ## 本帧是否首次激活（瞬时 step 永远为 true）
	var last: bool        ## 本帧是否抵达终点

var steps: Array = []
var elapsed: float = 0.0
var max_sec: float = 0.0      ## 0 = 不限；>0 时超时由导演强制收尾
var seq_name: String = ""

var _started: Array[bool] = []
var _finished: Array[bool] = []

func load_sequence(p_name: String, seq: Dictionary) -> void:
	seq_name = p_name
	steps = seq.get("steps", [])
	max_sec = float(seq.get("max_sec", 0.0))
	elapsed = 0.0
	_started.clear()
	_finished.clear()
	_started.resize(steps.size())
	_finished.resize(steps.size())
	for i in range(steps.size()):
		_started[i] = false
		_finished[i] = false

## 序列自身的总时长 = max(at + dur)
func total_duration() -> float:
	var total := 0.0
	for s in steps:
		total = maxf(total, float(s.get("at", 0.0)) + maxf(float(s.get("dur", 0.0)), 0.0))
	return total

func is_done() -> bool:
	if steps.is_empty():
		return true
	return elapsed >= total_duration()

func is_timed_out() -> bool:
	return max_sec > 0.0 and elapsed > max_sec

## 推进一帧，返回本帧需要施加的 Tick 列表（按 step 原顺序）
func advance(unscaled_delta: float) -> Array:
	elapsed += unscaled_delta
	var out: Array = []
	for i in range(steps.size()):
		if _finished[i]:
			continue
		var s: Dictionary = steps[i]
		var at := float(s.get("at", 0.0))
		if elapsed < at:
			continue
		var dur := maxf(float(s.get("dur", 0.0)), 0.0)
		var tk := Tick.new()
		tk.step = s
		tk.first = not _started[i]
		_started[i] = true
		if dur <= 0.0:
			# 瞬时 step：发一次就退休
			tk.raw_t = 1.0
			tk.t = 1.0
			tk.last = true
			_finished[i] = true
		else:
			tk.raw_t = clampf((elapsed - at) / dur, 0.0, 1.0)
			tk.t = EaseLib.apply(String(s.get("ease", "linear")), tk.raw_t)
			tk.last = tk.raw_t >= 1.0
			if tk.last:
				_finished[i] = true
		out.append(tk)
	return out

## 强制把所有未完成的 step 推到终点（超时收尾 / 打断时用）。
## 返回它们的终点 Tick，让导演把通道落到终值而不是停在中途
func force_finish() -> Array:
	var out: Array = []
	for i in range(steps.size()):
		if _finished[i]:
			continue
		var tk := Tick.new()
		tk.step = steps[i]
		tk.raw_t = 1.0
		tk.t = 1.0
		tk.first = not _started[i]
		tk.last = true
		_started[i] = true
		_finished[i] = true
		out.append(tk)
	return out
