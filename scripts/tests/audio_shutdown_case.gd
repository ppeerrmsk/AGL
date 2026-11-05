extends RefCounted

static func run(parent: Node) -> int:
	AudioManager.play_music("main_menu", 0.0, true)
	AudioManager.crossfade_music("battle_coast", 1.0, true)
	var positional := AudioStreamPlayer2D.new()
	positional.stream = AudioManager.WEAPON_SFX.gun_fire
	parent.add_child(positional)
	positional.play()
	AudioManager.prefetch_music(["boss", "boss_round_table"])
	await parent.get_tree().physics_frame
	await parent.get_tree().process_frame
	var was_playing: bool = AudioManager.is_music_playing()
	var probes := _capture_music()
	var clean: bool = await AudioManager.prepare_shutdown()
	AudioManager.play_music("main_menu", 0.0)
	AudioManager.play_sfx_2d("gun_fire", Vector2.ZERO)
	AudioManager.prefetch_music(["boss_mothergoose_1"])
	await parent.get_tree().process_frame
	var late_safe: bool = not AudioManager.is_music_playing() \
		and AudioManager.is_stream_prefetch_idle() and AudioManager._stream_cache.is_empty()
	var repeated: bool = await AudioManager.prepare_shutdown()
	var released := preload("res://scripts/audio/audio_shutdown.gd").remaining(probes) == 0
	var ok := was_playing and not probes.is_empty() and clean and repeated \
		and released and late_safe and positional.stream == null and not positional.playing
	positional.queue_free()
	await parent.get_tree().process_frame
	print("[AudioShutdownCase] played=%s released=%s late_safe=%s repeated=%s ok=%s" % [
		was_playing, released, late_safe, repeated, ok])
	return int(not ok)

static func _capture_music() -> Array[WeakRef]:
	# 同步捕获，不能让协程的临时强引用成为被测播放对象的最后持有者。
	var probes: Array[WeakRef] = []
	for player: AudioStreamPlayer in [AudioManager._music_player_a, AudioManager._music_player_b]:
		if player.has_stream_playback():
			probes.append(weakref(player.get_stream_playback()))
	return probes
