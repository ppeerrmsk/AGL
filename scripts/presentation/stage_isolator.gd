class_name StageIsolator
extends RefCounted

## 空舞台隔离（spec ui-transition §2.7 / §3.4）
##
## 把世界"清空"成一片空旷天空：`hard_pause` 冻住全场，只给演员开 PROCESS_MODE_ALWAYS
## 让他们继续飞；其余单位淡到 0、地图压暗。观感即"另一个空间"。
##
## 刻意【不】新建 Viewport / 不重父级 —— 重父级会打断 all_units 注册与雷达累积
## （见 known-seams 的 MountTarget 教训）。视觉隔离靠淡出就够，且非演员被暂停冻住＝零开销。

const MAP_ALPHA := 0.25       ## 演出期间地图/地理层透明度
const HUD_ALPHA := 0.0        ## 演出期间 HUD 全隐

var _actors: Array = []                  ## 演员（Aircraft）
var _dimmed: Array = []                  ## 被压暗的非演员 CanvasItem（含地图/HUD）
var _active: bool = false

func is_active() -> bool:
	return _active

## 清空舞台。t 为 0..1 的进度，由序列驱动逐帧调用
func clear(actors: Array, extra_layers: Array, t: float) -> void:
	if not _active:
		_active = true
		_actors = actors.duplicate()
		_dimmed.clear()
		# 全场扫描【只在起止各一次】，不进每帧（守性能守则第 2 条）
		for u in CombatUnit.all_units:
			if not is_instance_valid(u) or _actors.has(u):
				continue
			_dimmed.append(u)
		for n in extra_layers:
			if is_instance_valid(n):
				_dimmed.append(n)
		# 演员豁免暂停：飞机本体 + 其 AIController 都要开 ALWAYS，否则冻在原地
		for a in _actors:
			_set_actor_awake(a, true)

	var p: float = clampf(t, 0.0, 1.0)
	for n in _dimmed:
		if not is_instance_valid(n):
			continue
		var target: float = HUD_ALPHA if n is CanvasLayer else (MAP_ALPHA if _is_layer(n) else 0.0)
		_set_alpha(n, lerpf(1.0, target, p))

## 世界淡回。
## ⚠ 刻意【不依赖 clear 时的快照】——演出中途可能有单位被 queue_free、也可能新生成单位。
## 直接重扫全场把所有非演员拉回 1.0，幂等且自动覆盖新单位（spec §3.4）
func restore(extra_layers: Array, t: float) -> void:
	# force_restore（release 步骤 / 超时收尾）之后 restore 步骤可能仍在 tick ——
	# 不加这道闸会把刚复原的世界重新压暗一帧再弹回，肉眼可见的闪烁
	if not _active:
		return
	var p: float = clampf(t, 0.0, 1.0)
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or _actors.has(u):
			continue
		u.modulate.a = lerpf(0.0, 1.0, p)
	for n in extra_layers:
		if is_instance_valid(n):
			_set_alpha(n, lerpf(HUD_ALPHA if n is CanvasLayer else MAP_ALPHA, 1.0, p))
	if p >= 1.0:
		_finish_restore()

## 统一的透明度写入口。
## ⚠ CanvasLayer【没有 modulate 属性】（它不是 CanvasItem）—— 直接写会运行时报错并中断
##   整个循环（HUD 藏不掉、后续节点全跳过、错误刷屏）。这正是 survivor_tutorial 当年踩过、
##   spec 里也写了的那条教训，首版实现还是踩了。CanvasLayer 退化为 visible 开关
static func _set_alpha(n: Object, a: float) -> void:
	if n is CanvasLayer:
		n.visible = a > 0.05
	elif n is CanvasItem:
		n.modulate.a = a

func _finish_restore() -> void:
	for a in _actors:
		_set_actor_awake(a, false)
	_actors.clear()
	_dimmed.clear()
	_active = false

## 强制复原（超时收尾 / clear_all）：瞬间把全场 alpha 拉回 1.0
func force_restore(extra_layers: Array) -> void:
	if not _active and _actors.is_empty():
		return
	for u in CombatUnit.all_units:
		if is_instance_valid(u):
			u.modulate.a = 1.0
	for n in extra_layers:
		if is_instance_valid(n):
			_set_alpha(n, 1.0)
	_finish_restore()

func _set_actor_awake(a: Node, on: bool) -> void:
	if not is_instance_valid(a):
		return
	a.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
	if on:
		# ⚠ 远端刷出的敌机被离屏 LOD 藏着（visible=false + lod_level=2，survivor_mode 离屏扫描），
		# 而该扫描在演出 hard_pause 期间不跑 —— 不在这里强制解除，演员全场隐形
		# （探针实锤：alpha 全对、visible 全程 false）。演出结束 LOD 扫描恢复后自行接管
		a.visible = true
		if "lod_level" in a:
			a.lod_level = 0
	# AIController 是 Aircraft 的子节点，INHERIT 会跟着父级走 —— 显式设置更保险
	for c in a.get_children():
		if c is AIController:
			c.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT

func _is_layer(n: Node) -> bool:
	return not (n is CombatUnit) and not _is_hud(n)

func _is_hud(n: Node) -> bool:
	return n is CanvasLayer
