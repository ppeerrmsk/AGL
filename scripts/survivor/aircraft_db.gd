class_name AircraftDB
extends RefCounted

## 机型档案注册表（UGC 护栏 2，见 docs/planning/evolution-vertical-slice.md §0）
## 所有"按 id 取 PlayableAircraft 档案"必须走 get_profile()，禁止散落 preload。
## 将来 UgcLoader 只需调 register() 注入 user:// 内容，进化/生成代码零改动。

## id → 档案资源路径（官方内容内置表；UGC 运行时经 register() 追加）
## 41 机全谱（spec player-aircraft-power-curve §2 v7）：老 13 机保留原路径（base_params 已重指向
## resources/player/），新 28 机 profile 与 params 同住 resources/player/
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
	# 41 机扩谱（resources/player/，2026-07-19）
	&"a6e": "res://resources/player/playable_a6e.tres",
	&"mirage3": "res://resources/player/playable_mirage3.tres",
	&"mirage2000": "res://resources/player/playable_mirage2000.tres",
	&"f15c": "res://resources/player/playable_f15c.tres",
	&"f15e": "res://resources/player/playable_f15e.tres",
	&"fa18e": "res://resources/player/playable_fa18e.tres",
	&"gripen_c": "res://resources/player/playable_gripen_c.tres",
	&"su27": "res://resources/player/playable_su27.tres",
	&"rafale": "res://resources/player/playable_rafale.tres",
	&"tornado": "res://resources/player/playable_tornado.tres",
	&"typhoon": "res://resources/player/playable_typhoon.tres",
	&"viggen": "res://resources/player/playable_viggen.tres",
	&"harrier": "res://resources/player/playable_harrier.tres",
	&"f15smtd": "res://resources/player/playable_f15smtd.tres",
	&"su35": "res://resources/player/playable_su35.tres",
	&"gripen_e": "res://resources/player/playable_gripen_e.tres",
	&"su57": "res://resources/player/playable_su57.tres",
	&"j20": "res://resources/player/playable_j20.tres",
	&"a12": "res://resources/player/playable_a12.tres",
	&"yf23": "res://resources/player/playable_yf23.tres",
	&"f47": "res://resources/player/playable_f47.tres",
	&"mig41": "res://resources/player/playable_mig41.tres",
	&"fcas": "res://resources/player/playable_fcas.tres",
	&"gcap": "res://resources/player/playable_gcap.tres",
	&"j36": "res://resources/player/playable_j36.tres",
	&"x77": "res://resources/player/playable_x77.tres",
	&"x90": "res://resources/player/playable_x90.tres",
	&"ax00": "res://resources/player/playable_ax00.tres",
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

## 机型武器清单文本（选机卡 / 进化规划站共用，用户 2026-07-03：选飞机要看得到带什么武器）。
## 从 base_params + profile 覆盖推导；equipment（电磁炮/激光等）用其 display_name。
## 静态上下文无 tr() → 走 TranslationServer.translate。
static func weapons_summary(profile: PlayableAircraft) -> String:
	if profile == null or profile.base_params == null:
		return ""
	var p: AircraftParams = profile.base_params
	var parts: PackedStringArray = []
	if p.gun:
		parts.append(TranslationServer.translate(&"WEAPON_GUN"))
	if p.missile:
		var cnt: int = profile.missile_count_override if profile.missile_count_override >= 0 else p.missile.max_count
		parts.append("%s×%d" % [TranslationServer.translate(&"WEAPON_MISSILE"), cnt])
	if p.secondary_missile:
		parts.append(TranslationServer.translate(&"WEAPON_SECONDARY"))
	if p.rocket:
		parts.append(TranslationServer.translate(&"WEAPON_ROCKET"))
	if p.flare:
		parts.append(TranslationServer.translate(&"WEAPON_FLARE"))
	for eq in p.equipment:
		if eq and eq.display_name != "":
			parts.append(eq.display_name)
	return " · ".join(parts)

## 注册/覆盖档案路径（未来 UgcLoader 用；也可直接注册已构造的 Resource）
static func register(id: StringName, path_or_res) -> void:
	if path_or_res is String:
		_paths[id] = path_or_res
		_cache.erase(id)
	elif path_or_res is PlayableAircraft:
		_cache[id] = path_or_res
		_paths[id] = "<runtime>"
