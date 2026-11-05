extends RefCounted
## 走正式暂停页退出按钮，检查解暂停、地图释放及返回后菜单仍可操作。

static func run(battle: Node, stream_ref: WeakRef) -> Dictionary:
	var tree := battle.get_tree()
	var previous: WeakRef = weakref(battle)
	var pause: PauseMenu = battle._pause_menu
	var result := {"fail":0,"route":"pause_button_signal","signal_count":0}
	if not is_instance_valid(pause):
		result.fail=1
		return result
	var signals: Array[int]=[0]
	pause.quit_to_menu.connect(func(): signals[0]+=1,CONNECT_ONE_SHOT)
	var modal_deadline := Time.get_ticks_msec()+3000
	while (tree.paused or battle.is_paused_for_upgrade or Presentation.state!=Presentation.State.SETTLED) and Time.get_ticks_msec()<modal_deadline:
		await tree.process_frame
	pause.open()
	var pause_deadline := Time.get_ticks_msec()+1000
	while not tree.paused and Time.get_ticks_msec()<pause_deadline: await tree.process_frame
	result["pause_opened"]=pause.is_open() and tree.paused
	result.fail+=int(not result.pause_opened)
	var quit_button: Button=null
	for node: Node in pause._root.find_children("*","Button",true,false):
		if node.text==TranslationServer.translate("PAUSE_BTN_QUIT"):
			quit_button=node as Button
			break
	if quit_button==null:
		result.fail+=1
		return result
	var started := Time.get_ticks_usec()
	quit_button.pressed.emit()
	result["handler_ms"]=(Time.get_ticks_usec()-started)/1000.0
	# signal 返回后旧节点可能已脱树；后续只经 WeakRef 检查，不再读取旧对象。
	pause=null;quit_button=null
	var deadline := Time.get_ticks_msec()+6000
	var previous_tick := started
	result["menu_first_ready_ms"]=-1.0
	result["max_exit_frame_ms"]=0.0
	while Time.get_ticks_msec()<deadline:
		await tree.process_frame
		var tick := Time.get_ticks_usec()
		result.max_exit_frame_ms=maxf(result.max_exit_frame_ms,(tick-previous_tick)/1000.0)
		previous_tick=tick
		var scene: Node=tree.current_scene
		if result.menu_first_ready_ms<0.0 and is_instance_valid(scene) and scene.scene_file_path=="res://scenes/main_menu.tscn" and not tree.paused:
			result.menu_first_ready_ms=(tick-started)/1000.0
		if previous.get_ref()==null and stream_ref!=null and stream_ref.get_ref()==null and tree.get_nodes_in_group("tokyo_metadata_retirement").is_empty():
			break
	result["released_ms"]=(Time.get_ticks_usec()-started)/1000.0
	result["signal_count"]=signals[0]
	result["battle_released"]=previous.get_ref()==null
	result["stream_released"]=stream_ref!=null and stream_ref.get_ref()==null
	result["metadata_released"]=tree.get_nodes_in_group("tokyo_metadata_retirement").is_empty()
	for frame in 3: await tree.process_frame
	var current: Node=tree.current_scene
	result["menu_ready"]=is_instance_valid(current) and current.scene_file_path=="res://scenes/main_menu.tscn" and not tree.paused
	result["menu_input_ready"]=false
	if result.menu_ready and not current._mode_buttons.is_empty():
		var first: Button=current._mode_buttons[0]
		first.grab_focus()
		await tree.process_frame
		result.menu_input_ready=first.has_focus() and first.is_visible_in_tree() and not first.disabled
	result.fail+=int(result.signal_count!=1 or not result.battle_released or not result.stream_released \
		or not result.metadata_released or not result.menu_ready or not result.menu_input_ready)
	result.fail+=int(result.max_exit_frame_ms>100.0)
	return result
