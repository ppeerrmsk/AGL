class_name AircraftDB
extends RefCounted

## 机型档案注册表（UGC 护栏 2，见 docs/planning/evolution-vertical-slice.md §0）
## 所有"按 id 取 PlayableAircraft 档案"必须走 get_profile()，禁止散落 preload。
## 将来 UgcLoader 只需调 register() 注入 user:// 内容，进化/生成代码零改动。

## id → 档案资源路径（官方内容内置表；UGC 运行时经 register() 追加）
static var _paths: Dictionary = {
	&"f15": "res://resources/playable_f15.tres",
	&"f16": "res://resources/playable_f16.tres",
	&"f14": "res://resources/playable_f14.tres",
	&"a10": "res://resources/playable_a10.tres",
	&"x02": "res://resources/playable_x02.tres",
	# 进化树切片变体（resources/evolution/）
	&"f22": "res://resources/evolution/playable_f22.tres",
	&"f35": "res://resources/evolution/playable_f35.tres",
	&"mig31": "res://resources/evolution/playable_mig31.tres",
	&"su34": "res://resources/evolution/playable_su34.tres",
	&"x09": "res://resources/evolution/playable_x09.tres",
	&"x13": "res://resources/evolution/playable_x13.tres",
	&"x21": "res://resources/evolution/playable_x21.tres",
	&"x44": "res://resources/evolution/playable_x44.tres",
}

static var _cache: Dictionary = {}

## 按 id 取档案（懒加载 + 缓存）。未注册/加载失败返回 null（调用方自行守卫）。
static func get_profile(id: StringName) -> PlayableAircraft:
	if _cache.has(id):
		return _cache[id]
	var path: String = _paths.get(id, "")
	if path == "":
		push_warning("AircraftDB: 未注册的机型 id=%s" % id)
		return null
	var res := load(path)
	if res == null or not (res is PlayableAircraft):
		push_warning("AircraftDB: 加载失败/类型不符 id=%s path=%s" % [id, path])
		return null
	_cache[id] = res
	return res

## 注册/覆盖档案路径（未来 UgcLoader 用；也可直接注册已构造的 Resource）
static func register(id: StringName, path_or_res) -> void:
	if path_or_res is String:
		_paths[id] = path_or_res
		_cache.erase(id)
	elif path_or_res is PlayableAircraft:
		_cache[id] = path_or_res
		_paths[id] = "<runtime>"
