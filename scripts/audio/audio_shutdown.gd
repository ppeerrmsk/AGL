extends RefCounted
## 只在退出边界遍历一次。用 WeakRef 观察音频线程真正归还播放引用，不能只看 playing=false。

static func stop_playbacks(root: Node) -> Array[WeakRef]:
	var probes: Array[WeakRef] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			if node.has_stream_playback():
				probes.append(weakref(node.get_stream_playback()))
			node.stop()
			node.stream = null
	return probes

static func remaining(probes: Array[WeakRef]) -> int:
	var count := 0
	for probe in probes:
		count += int(probe.get_ref() != null)
	return count
