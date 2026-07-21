## EventDirector —— 中央事件调度器
##
## 持有所有运行中的 GameEvent，每帧 tick；事件结束时自动清空其 directive。
## 是 survivor_mode 的子节点（不是 AutoLoad —— 沙盒不需要事件系统，避免负担）。
##
## 用法：
##   var ev := BossEncounterEvent.new(...)
##   event_director.start(ev)
##   ...
##   var existing := event_director.find_by_name("boss_encounter")
##
## 事件之间不直接通信，要协同就读 EventDirector.find_by_name 或共享 mode 引用。

class_name EventDirector
extends Node

## 共享依赖（survivor_mode 在 _ready 注入）
var mode: Node = null               ## SurvivorMode
var player: Aircraft = null
var spawner = null                  ## SurvivorSpawner

var _events: Array[GameEvent] = []

# ──────────────── 启动 / 查询 ────────────────

## 启动一个事件 —— 立即调 _start，下一帧开始 _update
func start(event: GameEvent) -> void:
	if event == null:
		return
	event.director = self
	event._start()
	_events.append(event)
	EventLogger.log_event("EVENT", event.name, "start")

## 按 name 找一个活跃事件（重复 name 取第一个）；找不到返回 null
func find_by_name(event_name: String) -> GameEvent:
	for e in _events:
		if e.name == event_name and e.active:
			return e
	return null

## 当前活跃事件数（debug / HUD 显示用）
func active_count() -> int:
	var n := 0
	for e in _events:
		if e.active:
			n += 1
	return n

# ──────────────── 推进 ────────────────

func _physics_process(delta: float) -> void:
	if _events.is_empty():
		return
	# ⚠ 这里【必须用原始 delta】（2026-07-20 审计修正，作废 spec §3.2 的旧论述）：
	# _physics_process 的 delta 是固定步长（1/60，不随 Engine.time_scale 缩放——
	# time_scale 缩的是 tick 频率），累加它天然跟踪【游戏时间】，与飞机物理同一时钟。
	# 若除以 time_scale 改成实时，命令轮盘 0.3× 期间事件计时会比世界快 3.3 倍 ——
	# 护航拦截波次相对航线位置提前触发。hard_pause 期间物理根本不 tick，也无漂移可言。
	# 先 update 所有活跃事件
	for e in _events:
		if e.active:
			e._update(delta)
	# 再扫一遍：active=false 的统一 finish + 释放 directive
	var alive: Array[GameEvent] = []
	for e in _events:
		if e.active:
			alive.append(e)
		else:
			e.clear_all_directives()
			e._finish()
	_events = alive
