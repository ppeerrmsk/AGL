extends RefCounted
## 重用已落盘的独立分区，定位正式建筑凭据失败，不重做网格。
static func run(input: Dictionary) -> int:
	var delta := preload("res://scripts/rendering/tokyo_partition_coverage.gd")
	var package_binding: Dictionary=input.partition_coverage_probe
	if FileAccess.get_sha256(package_binding.path)!=package_binding.sha256: return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package_binding.path))
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	var configuration: String=input.configuration
	var original := preload("res://scripts/tests/tokyo_partition_attach_probe.gd").find_entry(native.catalog.configurations[configuration],input.target)
	var data := delta.read(input.partition)
	var normalized := preload("res://scripts/rendering/tokyo_partition_catalog.gd").normalize(data,input.partition)
	if normalized.is_empty(): return 1
	var certificate := preload("res://scripts/tests/build_tokyo_partition_coverage.gd").new()
	var binding := certificate.build(native,original,normalized,input.partition.sha256,input.expected,input.output)
	print("[Tokyo partition coverage probe] ",binding)
	return int(binding.is_empty())
