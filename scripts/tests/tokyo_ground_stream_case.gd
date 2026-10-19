extends RefCounted
const Stream := preload("res://scripts/rendering/tokyo_component_stream.gd")
const Assembly := preload("res://scripts/rendering/tokyo_ground_page.gd")

static func run(parent: Node, input: Dictionary) -> int:
	var binding: Dictionary=input.ground_stream
	if not Assembly.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	if FileAccess.file_exists(input.output): return 1
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var descriptors := {}
	var keys := PackedStringArray()
	var total := 0
	for item: Dictionary in report.rows:
		var part: Dictionary=item.binding.duplicate(true)
		part.bytes=int(part.bytes)
		for field: String in ["schema","slots"]: part.canonical_identity[field]=int(part.canonical_identity[field])
		var key: String="ground-view/"+String(item.page).sha256_text()
		descriptors[key]={"canonical_identity":{"format":"tokyo_ground_view","schema":1,"source":binding.sha256,"parent":item.page},"components":{part.path:part},"mask":[false,false,true],"bytes":part.bytes,"faces":int(item.faces)}
		keys.append(key);total+=int(part.bytes)
	var owner := Node.new();parent.add_child(owner)
	var stream := Stream.new();parent.add_child(stream)
	stream.configure(owner,descriptors);stream.request(keys,PackedStringArray())
	var deadline := Time.get_ticks_msec()+30000
	var ready := false
	while Time.get_ticks_msec()<deadline:
		ready=true
		for key: String in keys:
			if stream.resource(key)==null: ready=false
		if ready: break
		await parent.get_tree().process_frame
	var fail := int(not ready)+int(stream._descriptors.size()!=keys.size())+int(stream._bytes!=total)
	if ready:
		for key: String in keys:
			var row: Dictionary=descriptors[key]
			var page: Resource=stream.resource(key)
			fail+=int(page.meshes[0]!=null or page.meshes[1]!=null or page.meshes[2]==null)
			fail+=int(Assembly.assemble(row,{})!=null)
			var bad: Dictionary=row.duplicate(true);bad.mask=[true,false,true]
			fail+=int(Assembly.assemble(bad,stream._cache)!=null)
			bad=row.duplicate(true);bad.bytes+=1
			fail+=int(Assembly.assemble(bad,stream._cache)!=null)
			bad=row.duplicate(true);bad.faces+=1
			fail+=int(Assembly.assemble(bad,stream._cache)!=null)
	var reference: WeakRef=weakref(stream)
	owner.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	fail+=int(is_instance_valid(reference.get_ref()))
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"fail":fail,"pages":keys.size(),"physical_bytes":total,"ready":ready,"stream_freed":not is_instance_valid(reference.get_ref()),"f5_installed":false},"\t"));file.close()
	print("[Tokyo ground stream] fail=",fail," bytes=",total)
	return fail
