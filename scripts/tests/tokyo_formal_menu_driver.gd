extends Node
## 测试输入助手：菜单处理与可操控时钟不依赖画面是否继续提交。
var _battle_ref: WeakRef
var started_ms := 0
var active_ms := 0
var modal_generation := 0
var source_released := false
var selections: Array[Dictionary]=[]
var display_changes: Array[Dictionary]=[]
var _previous_ms := 0
var _previous_open := true
var _display_state := ""


func setup(battle: Node, start_ms: int) -> void:
	_battle_ref=weakref(battle);started_ms=start_ms;_previous_ms=Time.get_ticks_msec()
	process_mode=Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var battle: Variant=_battle_ref.get_ref() if _battle_ref!=null else null
	if typeof(battle)!=TYPE_OBJECT or not is_instance_valid(battle):
		source_released=true;_battle_ref=null;set_process(false);return
	var now := Time.get_ticks_msec()
	var open: bool=not get_tree().paused and not battle.is_paused_for_upgrade and is_equal_approx(battle._camera_ctrl.cine_zoom_mult,1.0)
	if open and _previous_open: active_ms+=now-_previous_ms
	if open!=_previous_open: modal_generation+=1
	_previous_ms=now;_previous_open=open
	var display := str(DisplayServer.window_get_mode())+":"+str(DisplayServer.window_is_focused())
	if display!=_display_state:
		_display_state=display
		display_changes.append({"ms":now-started_ms,"mode":DisplayServer.window_get_mode(),"focused":DisplayServer.window_is_focused()})
	if battle.upgrade_ui.visible and not battle.upgrade_ui._input_locked and not battle.upgrade_ui._selection_locked and not battle.upgrade_ui._choices.is_empty():
		selections.append({"ms":now-started_ms,"active_ms":active_ms,"choice":battle.upgrade_ui._choices[0].get("id","")})
		battle.upgrade_ui._on_choice_pressed(0)
	if battle._boundary_ui._menu_visible and Presentation.state==Presentation.State.SETTLED and battle._boundary_ui._menu_root.modulate.a>=0.99:
		selections.append({"ms":now-started_ms,"active_ms":active_ms,"choice":"boundary_cancel"})
		battle._boundary_ui._on_cancel_pressed()
