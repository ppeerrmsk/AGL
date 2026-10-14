extends RefCounted
## 退出残留归因：只检查正式音频实例的播放引用释放，不修改正式退出逻辑。
static func run(parent: Node, input: Dictionary) -> int:
	var output: String = input.get("output", "")
	if output.is_empty() or FileAccess.file_exists(output): return 1
	AudioManager.play_music("main_menu", 0.0, true)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var capture := _capture_playbacks()
	var probes: Array = capture.probes
	var playing: int = capture.playing
	if playing == 0: return 1
	# 手动诊断完整停止；不是仅mute，也不把此操作写回正式游戏行为。
	AudioManager.stop_music(0.0)
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	for frame in 4:
		await parent.get_tree().process_frame
	var remaining := 0
	for probe: WeakRef in probes:
		remaining += int(probe.get_ref() != null)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: return 1
	file.store_string(JSON.stringify({"playing_before":playing,"playback_probes":probes.size(),
		"remaining_after_stop_and_four_frames":remaining,"formal_shutdown_fixed":false},"\t"))
	file.close()
	print("Tokyo audio exit probe: remaining=", remaining)
	return 0 if remaining == 0 else 1

static func _capture_playbacks() -> Dictionary:
	# 同步函数退出后才跨帧，避免诊断协程自身保留get_stream_playback的临时强引用。
	var probes: Array[WeakRef] = []
	var playing := 0
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer and child.has_stream_playback():
			playing += int(child.playing)
			probes.append(weakref(child.get_stream_playback()))
	return {"probes":probes,"playing":playing}
