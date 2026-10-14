extends RefCounted
## 显式候选：容量是包含纹理三份计费的资源池，不是额外可绘制几何。
const MIB := 1024*1024
const MAX_POOL := 1536*MIB
const STATIC_POOL := 3072*MIB
const COMPLETE_POOL := 4096*MIB
const MAX_DISPLAY := 192*MIB
static var _identity := ""
static var _limit := 96*MIB

static func pool_bytes(dedicated_mib: int, available_ram_mib: int) -> int:
	var amount := 384 if dedicated_mib<4096 else (768 if dedicated_mib<8192 else 1536)
	# 未知物理内存也保持保守档；不把共享内存算成独立显存。
	if available_ram_mib<4096: amount=384
	elif available_ram_mib<8192: amount=mini(amount,768)
	return amount*MIB

static func candidate_limit() -> int:
	# 只接受验证工具提供的实测容量，正式自动识别/默认启用须另过验收。
	if OS.get_environment("AGL_TOKYO_TIERED_CACHE")!="1": return 96*MIB
	var measured := OS.get_environment("AGL_TOKYO_DEDICATED_VRAM_MIB")
	var complete := OS.get_environment("AGL_TOKYO_COMPLETE_FOUNDATION")=="1"
	var identity := "enabled:"+measured+":"+OS.get_environment("AGL_TOKYO_STATIC_NATIVE")+":"+str(complete)
	if _identity==identity: return _limit
	var ram: Dictionary=OS.get_memory_info()
	_limit=pool_bytes(measured.to_int() if measured.is_valid_int() else 0,int(ram.get("free",0))/MIB)
	var fixed_pool := static_pool_bytes(OS.get_environment("AGL_TOKYO_STATIC_NATIVE")=="1",measured.to_int() if measured.is_valid_int() else 0,int(ram.get("free",0))/MIB)
	if fixed_pool>0: _limit=fixed_pool
	if complete:
		var complete_pool := complete_pool_bytes(true,measured.to_int() if measured.is_valid_int() else 0,int(ram.get("free",0))/MIB)
		_limit=complete_pool if complete_pool>0 and OS.get_environment("AGL_TOKYO_STATIC_NATIVE")!="1" else 96*MIB
	_identity=identity
	return _limit


static func static_pool_bytes(enabled: bool, dedicated_mib: int, available_ram_mib: int) -> int:
	# 显式试验：3GiB资源池之外保留4GiB目录/场景与安全余量；加载期另有1GiB硬停止门。
	return STATIC_POOL if enabled and dedicated_mib>=10240 and available_ram_mib>=7168 else 0


static func complete_pool_bytes(enabled: bool, dedicated_mib: int, available_ram_mib: int) -> int:
	# 显式完整基础层候选：4GiB三份纹理计费池，另留3.5GiB目录/场景余量。
	# 不与全叶常驻并用；载入期可用RAM低于1GiB时取消。
	return COMPLETE_POOL if enabled and dedicated_mib>=10240 and available_ram_mib>=7680 else 0


static func display_bytes(enabled: bool, dedicated_mib: int, pool: int) -> int:
	return MAX_DISPLAY if enabled and dedicated_mib>=8192 and pool in [MAX_POOL,STATIC_POOL,COMPLETE_POOL] else 96*MIB


static func display_limit() -> int:
	var measured := OS.get_environment("AGL_TOKYO_DEDICATED_VRAM_MIB")
	return display_bytes(OS.get_environment("AGL_TOKYO_DISPLAY_192")=="1",
		measured.to_int() if measured.is_valid_int() else 0,candidate_limit())

static func append_bundle(plan: Dictionary, meshes: PackedStringArray, images: PackedStringArray, geometry: Dictionary, textures: Dictionary, limit: int) -> bool:
	var next_meshes: PackedStringArray=plan.meshes.duplicate()
	var next_images: PackedStringArray=plan.images.duplicate()
	for path: String in meshes:
		if path not in next_meshes: next_meshes.append(path)
	for path: String in images:
		if path not in next_images: next_images.append(path)
	var amount := preload("res://scripts/rendering/tokyo_hlod_handoff.gd").streaming_bytes(geometry,textures,next_meshes,next_images,0)
	if amount<0 or amount>limit: return false
	plan.meshes=next_meshes;plan.images=next_images;plan.bytes=amount
	return true
