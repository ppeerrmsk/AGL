class_name TimeAuthority
extends RefCounted

## 时间缩放请求栈 —— Engine.time_scale 与 get_tree().paused 的唯一写入点
## （spec ui-transition §2.2 / §3.8）
##
## 求解规则：所有活跃请求中【最小的 scale 获胜】。这样命令轮盘 0.3× 与升级急刹 0.05×
## 同时存在时不会互相踩；谁先释放都不会把对方的缩放一起撤掉。
##
## ⚠ 泄漏是本模块最高危的失败模式：漏一次 release，玩家就卡在 0.05 倍速的世界里。
## clear_all() 必须在场景切换 / run reset / 导演 _exit_tree 三处强制调用。

const EPSILON := 0.001

var _tree: SceneTree
var _requests: Dictionary = {}      ## StringName → float(scale)
var _current: float = 1.0           ## 当前实际写入 Engine.time_scale 的值
var _blend_from: float = 1.0
var _blend_to: float = 1.0
var _blend_dur: float = 0.0
var _blend_elapsed: float = 0.0
var _paused: bool = false

func _init(p_tree: SceneTree) -> void:
	_tree = p_tree

## 是否还有未完成的混合（导演据此决定能否 set_process(false)）
func is_blending() -> bool:
	return _blend_dur > 0.0 and _blend_elapsed < _blend_dur

func current_scale() -> float:
	return _current

func has_request(id: StringName) -> bool:
	return _requests.has(id)

## 申请一档时间缩放。同 id 重复申请 = 覆盖，不叠加
func request(id: StringName, scale: float, blend: float = 0.0) -> void:
	_requests[id] = clampf(scale, 0.001, 1.0)
	_retarget(blend)

## 释放一档。栈空后目标回 1.0
func release(id: StringName, blend: float = 0.0) -> void:
	if not _requests.has(id):
		return
	_requests.erase(id)
	_retarget(blend)

## 真暂停的唯一入口。与 scale 栈正交——暂停时 scale 仍保留，解除后立刻恢复。
## ⚠ 刻意【不做】`if _paused == on: return` 的早退：debug 面板（F5 刷怪 / 技能面板）
## 仍直写 get_tree().paused，若按自己的 _paused 记账早退，会出现"外部把树暂停了、
## 本模块以为没暂停 → hard_pause(false) 变 no-op → ESC 退出后主菜单卡死在暂停里"。
## 幂等写入无代价，永远以实际树状态为准
func hard_pause(on: bool) -> void:
	_paused = on
	if _tree:
		_tree.paused = on

func is_hard_paused() -> bool:
	return _paused

## 求解目标 = 所有请求的最小值（无请求则 1.0）
func solve() -> float:
	var m := 1.0
	for scale in _requests.values():
		m = minf(m, float(scale))
	return m

func _retarget(blend: float) -> void:
	var target := solve()
	if absf(target - _current) < EPSILON and absf(target - _blend_to) < EPSILON:
		return
	_blend_from = _current
	_blend_to = target
	_blend_dur = maxf(blend, 0.0)
	_blend_elapsed = 0.0
	if _blend_dur <= 0.0:
		_apply(target)

## 每帧推进。必须传 **unscaled** delta——否则时间越慢混合越慢，永远到不了终点
func tick(unscaled_delta: float, ease_name: String = "linear") -> void:
	if not is_blending():
		return
	_blend_elapsed += unscaled_delta
	var t: float = clampf(_blend_elapsed / _blend_dur, 0.0, 1.0)
	_apply(lerpf(_blend_from, _blend_to, EaseLib.apply(ease_name, t)))
	if t >= 1.0:
		_blend_dur = 0.0

func _apply(scale: float) -> void:
	_current = scale
	Engine.time_scale = scale

## 全清：请求栈清空、时间瞬间回 1.0、解除暂停。
## 场景切换 / run reset / _exit_tree 必调——这是防"卡在 0.05 倍速"的最后一道闸
func clear_all() -> void:
	_requests.clear()
	_blend_dur = 0.0
	_blend_elapsed = 0.0
	_blend_from = 1.0
	_blend_to = 1.0
	_apply(1.0)
	hard_pause(false)
