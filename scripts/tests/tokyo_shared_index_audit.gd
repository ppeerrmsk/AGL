extends RefCounted
## 共享索引的引擎回放与局部解码耗时；不作为实景帧率验收。

static func run(input: Dictionary) -> int:
	var binding: Dictionary = input.shared_index_audit
	if FileAccess.get_sha256(binding.path) != binding.sha256: return 1
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if FileAccess.get_sha256(packet.master) != packet.master_sha256: return 1
	var master := FileAccess.get_file_as_bytes(packet.master)
	if master.size() != int(packet.master_bytes): return 1
	var selections: Array[PackedByteArray] = []
	for row: Dictionary in packet.rows:
		if FileAccess.get_sha256(row.ranges) != row.sha256: return 1
		var ranges := FileAccess.get_file_as_bytes(row.ranges)
		if ranges.size() != int(row.range_count) * 8: return 1
		selections.append(ranges)
	var results: Array[Dictionary] = []
	var scratch_limit := 65532 # 保持完整三角，每次临时片段不超过64KiB。
	for row_id in range(packet.rows.size()):
		var row: Dictionary = packet.rows[row_id]
		var ranges: PackedByteArray = selections[row_id]
		var started := Time.get_ticks_usec()
		var output := PackedByteArray()
		var previous_end := 0
		for i in range(0, ranges.size(), 8):
			var first := int(ranges.decode_u32(i)) * 12
			var end := first + int(ranges.decode_u32(i + 4)) * 12
			if first < previous_end or end > master.size() or end <= first: return 1
			previous_end = end
			while first < end:
				var stop := mini(end, first + scratch_limit)
				output.append_array(master.slice(first, stop))
				first = stop
		if output.size() != int(row.selected_faces) * 12: return 1
		if output.resize(2849856) != OK: return 1
		var elapsed := Time.get_ticks_usec() - started
		var digest := HashingContext.new()
		if digest.start(HashingContext.HASH_SHA256) != OK: return 1
		digest.update(output)
		if digest.finish().hex_encode() != row.decoded_sha256: return 1
		results.append({"leaf": row.leaf, "decode_usec": elapsed, "exact": true})
	var report := {"rows": results, "scratch_limit_bytes": scratch_limit,
		"known_conservative_bytes": int(packet.known_bytes_with_two_output_buffers) + scratch_limit,
		"allocation_peak_verified": false, "performance_accepted": false, "runtime_integrated": false,
		"limitations": "One output builder only; two-output charge reserves resize copying, not another retained CPU buffer. Allocator/driver peak unverified. Headless decode timings are not FPS."}
	if FileAccess.file_exists(input.output): return 1
	var file := FileAccess.open(input.output, FileAccess.WRITE)
	if file == null: return 1
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Shared index audit: ", JSON.stringify(report))
	return 0
