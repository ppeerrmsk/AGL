## GameEvent —— 事件系统的基本单元（一段剧本 / 一次刷怪 / 一段 BOSS 流程）
##
## 由 EventDirector 统一调度。每个事件管自己的：
##   - 生命周期（_start / _update / _finish）
##   - 受控单位列表（managed_units）
##   - 给单位下发的 AIDirective（通过 set_directive 写到 AI / NavalUnit）
##
## 事件结束时（active=false）自动撤销所有未释放的 directive，AI 回到正常状态。
##
## 子类只需关心业务逻辑：何时开始 / 何时结束 / 给谁下什么指令。

class_name GameEvent
extends RefCounted

## 一个简短描述名（log 用，无业务意义）
var name: String = "event"
## false = 事件已结束，EventDirector 在下一帧 finish + 回收
var active: bool = false
## EventDirector 注入：可访问 mode/player/spawner 等共享依赖
var director = null  ## EventDirector

## 受控单位（事件期间持有 directive 的）—— 事件结束时统一清空 directive
var managed_units: Array = []

## ── 调试断点 ──
## 编辑器中跑生存模式时，把这个翻 true → 关键状态切换处会触发 breakpoint，
## 方便单步调试。打包发行版务必保持 false。
## 触发位置（带 _debug_break 调用的）：
##   - GameEvent._start / end
##   - GameEvent.set_directive / clear_directive
##   - BossEncounterEvent _enter_engaged / _on_victory
static var debug_break_enabled: bool = false

func _debug_break(_label: String = "") -> void:
	if debug_break_enabled:
		breakpoint   ## Godot 编辑器调试器附加时会暂停于此

# ──────────────── 生命周期（子类覆盖）────────────────

## 由 EventDirector.start 调用一次
func _start() -> void:
	active = true
	_debug_break("event start: %s" % name)

## 每帧调用（active 期间）；子类在此推进 phase / 下发 directive / 监控完成条件
func _update(_delta: float) -> void:
	pass

## 事件被回收时调用一次（active 翻 false 后下一帧）；子类做收尾 / 通知
func _finish() -> void:
	pass

# ──────────────── Directive 工具 ────────────────

## 给一架飞机下指令：写到其 AIController._directive
## 同步把单位加入 managed_units，事件结束时自动清空指令
func set_directive(unit, directive: AIDirective) -> void:
	if not is_instance_valid(unit) or directive == null:
		return
	directive.owner_event = weakref(self)
	if unit is Aircraft:
		var ai: AIController = unit._get_ai_controller()
		if ai:
			ai.set_event_directive(directive)
	elif unit is NavalUnit:
		(unit as NavalUnit).set_event_directive(directive)
	else:
		push_warning("GameEvent.set_directive: unsupported unit type %s" % unit.get_class())
		return
	if not managed_units.has(unit):
		managed_units.append(unit)
	_debug_break("set_directive type=%d on %s" % [directive.type, unit])

## 清空某单位的 directive（让它回到正常 AI）
func clear_directive(unit) -> void:
	if not is_instance_valid(unit):
		return
	if unit is Aircraft:
		var ai: AIController = unit._get_ai_controller()
		if ai:
			ai.set_event_directive(null)
	elif unit is NavalUnit:
		(unit as NavalUnit).set_event_directive(null)
	managed_units.erase(unit)

## 释放所有 managed_units 的 directive（事件结束时由 EventDirector 自动调用）
func clear_all_directives() -> void:
	for u in managed_units:
		if not is_instance_valid(u):
			continue
		if u is Aircraft:
			var ai: AIController = u._get_ai_controller()
			if ai and ai._directive and ai._directive.owner_event \
					and ai._directive.owner_event.get_ref() == self:
				ai.set_event_directive(null)
		elif u is NavalUnit:
			var nu: NavalUnit = u
			if nu._directive and nu._directive.owner_event \
					and nu._directive.owner_event.get_ref() == self:
				nu.set_event_directive(null)
	managed_units.clear()

## 标记事件结束，下一帧 EventDirector 会 finish + 回收
func end() -> void:
	if active:
		active = false
		EventLogger.log_event("EVENT", name, "end")
		_debug_break("event end: %s" % name)
