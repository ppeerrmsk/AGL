extends RefCounted

static func run(parent: Node) -> int:
	var failures := 0
	var previous_deadline := Time.get_ticks_msec()+5000
	while preload("res://scripts/rendering/tokyo_metadata_retirement.gd").pending(parent.get_tree()) and Time.get_ticks_msec()<previous_deadline:
		await parent.get_tree().process_frame
	var owner := Node.new()
	parent.add_child(owner)
	var sink := preload("res://scripts/rendering/tokyo_metadata_retirement.gd").attach(owner)
	var sink_ref: WeakRef=weakref(sink)
	var owner_ref: WeakRef=weakref(owner)
	var shared := {"pages":[{"identity":"still_live","bytes":4096}]}
	sink.hold([shared])
	failures+=int(preload("res://scripts/rendering/tokyo_metadata_retirement.gd").pending(parent.get_tree()))
	await parent.get_tree().process_frame
	failures+=int(sink_ref.get_ref()==null or shared.pages[0].identity!="still_live")
	# 退树后仍有旧消费者时只能等待，不能清空共享表；销毁后才交接后台。
	parent.remove_child(owner)
	failures+=int(not preload("res://scripts/rendering/tokyo_metadata_retirement.gd").pending(parent.get_tree()))
	await parent.get_tree().process_frame
	failures+=int(sink_ref.get_ref()==null or shared.pages[0].bytes!=4096)
	owner.free()
	var deadline := Time.get_ticks_msec()+5000
	while sink_ref.get_ref()!=null and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	# 后台只归还持有引用，不可清空另一个地图消费者仍持有的容器。
	failures+=int(owner_ref.get_ref()!=null or sink_ref.get_ref()!=null or shared.pages[0].bytes!=4096)
	var stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd").new()
	parent.add_child(stream)
	var stream_owner := Node.new()
	parent.add_child(stream_owner)
	stream.configure(stream_owner,{})
	var stream_ref: WeakRef=weakref(stream)
	stream_owner.queue_free()
	deadline=Time.get_ticks_msec()+5000
	while (stream_ref.get_ref()!=null or not parent.get_tree().get_nodes_in_group("tokyo_metadata_retirement").is_empty()) and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	failures+=int(stream_ref.get_ref()!=null or not parent.get_tree().get_nodes_in_group("tokyo_metadata_retirement").is_empty())
	await parent.get_tree().process_frame
	print("[Tokyo metadata retirement] fail=",failures)
	return failures
