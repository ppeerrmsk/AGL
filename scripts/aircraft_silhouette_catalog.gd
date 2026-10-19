extends RefCounted

## 顶视轮廓 PNG 目录。运行时经 ResourceLoader 读 Godot 导入产物（.ctex），编辑器与导出包同一路径；
## 原图 PNG 不进 PCK。每个 key 只加载一次，失败也只记一次（负缓存），之后直接走旧绘制。
## 只有完成逐机型“来源 + 顶视裁切 + 叠图检查”的轮廓才能进入正式映射。
const TEXTURE_PATHS: Dictionary = {
	"a6e": "res://resources/aircraft_silhouettes/a6e_detail.png",
	"a7": "res://resources/aircraft_silhouettes/a7_detail.png",
	"a10": "res://resources/aircraft_silhouettes/a10_detail.png",
	"ah64": "res://resources/aircraft_silhouettes/ah64_detail.png",
	"b1b": "res://resources/aircraft_silhouettes/b1b_detail.png",
	"ch47": "res://resources/aircraft_silhouettes/ch47_detail.png",
	"ea6b": "res://resources/aircraft_silhouettes/ea6b_detail.png",
	"f4": "res://resources/aircraft_silhouettes/f4_detail.png",
	"f86": "res://resources/aircraft_silhouettes/f86_detail.png",
	"f100": "res://resources/aircraft_silhouettes/f100_detail.png",
	"f104": "res://resources/aircraft_silhouettes/f104_detail.png",
	"f14": "res://resources/aircraft_silhouettes/f14_detail.png",
	"f15": "res://resources/aircraft_silhouettes/f15_detail.png",
	"f15smtd": "res://resources/aircraft_silhouettes/f15smtd_detail.png",
	"f16": "res://resources/aircraft_silhouettes/f16_detail.png",
	"f22": "res://resources/aircraft_silhouettes/f22_detail.png",
	"f35": "res://resources/aircraft_silhouettes/f35_detail.png",
	"fa18": "res://resources/aircraft_silhouettes/fa18_detail.png",
	"fa18e": "res://resources/aircraft_silhouettes/fa18e_detail.png",
	"fck1": "res://resources/aircraft_silhouettes/fck1_detail.png",
	"gripen": "res://resources/aircraft_silhouettes/gripen_detail.png",
	"harrier": "res://resources/aircraft_silhouettes/harrier_detail.png",
	"j35f": "res://resources/aircraft_silhouettes/j35f_detail.png",
	"j7": "res://resources/aircraft_silhouettes/j7_detail.png",
	"jaguar": "res://resources/aircraft_silhouettes/jaguar_detail.png",
	"j20": "res://resources/aircraft_silhouettes/j20_detail.png",
	"mig21f13": "res://resources/aircraft_silhouettes/mig21f13_detail.png",
	"mig29": "res://resources/aircraft_silhouettes/mig29_detail.png",
	"mig23": "res://resources/aircraft_silhouettes/mig23_detail.png",
	"mig31": "res://resources/aircraft_silhouettes/mig31_detail.png",
	"mirage3": "res://resources/aircraft_silhouettes/mirage3_detail.png",
	"mirage2000": "res://resources/aircraft_silhouettes/mirage2000_detail.png",
	"mq109_family": "res://resources/aircraft_silhouettes/mq109_family_detail.png",
	"q5": "res://resources/aircraft_silhouettes/q5_detail.png",
	"rafale": "res://resources/aircraft_silhouettes/rafale_detail.png",
	"su27": "res://resources/aircraft_silhouettes/su27_detail.png",
	"su34": "res://resources/aircraft_silhouettes/su34_detail.png",
	"su47": "res://resources/aircraft_silhouettes/su47_detail.png",
	"su57": "res://resources/aircraft_silhouettes/su57_detail.png",
	"tornado": "res://resources/aircraft_silhouettes/tornado_detail.png",
	"tu160": "res://resources/aircraft_silhouettes/tu160_detail.png",
	"typhoon": "res://resources/aircraft_silhouettes/typhoon_detail.png",
	"viggen": "res://resources/aircraft_silhouettes/viggen_detail.png",
	"yf23": "res://resources/aircraft_silhouettes/yf23_detail.png",
}

static var _texture_cache: Dictionary = {}
## 加载失败的 key：draw_icon 每帧都会问，不记下来就会每次重试并刷告警。
static var _texture_failed: Dictionary = {}

const DISPLAY_KEYS: Dictionary = {
	"A-6E Intruder": "a6e", "A-7": "a7", "A-10": "a10", "A-10 Thunderbolt II": "a10",
	"A-12 Avenger II": "a12", "AH-64": "ah64", "B-1B": "b1b", "CH-47": "ch47",
	"EA-6B Prowler": "ea6b", "F-4 Phantom": "f4", "F-4E": "f4", "F-4E Phantom II": "f4",
	"F-86": "f86", "F-100": "f100", "F-104 Starfighter": "f104",
	"F-104C Starfighter": "f104", "F-14": "f14", "F-14 Tomcat": "f14",
	"F-15": "f15", "F-15 Eagle": "f15", "F-15C Eagle": "f15", "F-15E Strike Eagle": "f15",
	"F-15 S/MTD": "f15smtd", "F-16": "f16", "F-16 Fighting Falcon": "f16",
	"F-22 Raptor": "f22", "F-35 Lightning II": "f35", "F-47": "f47", "F-47 NGAD": "f47",
	"F/A-18": "fa18", "F/A-18E Super Hornet": "fa18e", "EA-18G Growler": "fa18e",
	"F/A-XX": "faxx", "FCAS NGF": "fcas", "F-CK-1": "fck1", "GCAP Tempest": "gcap",
	"JAS 39 Gripen C": "gripen", "JAS 39 Gripen E": "gripen", "JAS 39C Gripen": "gripen",
	"JAS 39E Gripen": "gripen", "Harrier GR.7": "harrier", "J 35F Draken": "j35f",
	"J-7": "j7", "Jaguar GR.1A": "jaguar",
	"J-20 Mighty Dragon": "j20", "J-36": "j36", "MiG-23": "mig23", "MiG-29": "mig29",
	"MiG-21F-13": "mig21f13", "MiG-23 Flogger": "mig23", "MiG-31": "mig31",
	"MiG-31 Foxhound": "mig31", "MiG-41 PAK DP": "mig41",
	"Mirage III": "mirage3", "Mirage 2000": "mirage2000",
	"MQ-109": "mq109_family", "MQ-110": "mq109_family", "MQ-111": "mq109_family", "Q-5": "q5",
	"Dassault Rafale": "rafale", "Rafale": "rafale", "Su-27": "su27", "Su-27 Flanker": "su27",
	"Su-35 Super Flanker": "su27", "Su-35 Flanker-E": "su27", "Su-34 Fullback": "su34",
	"Su-47": "su47", "Su-57 Felon": "su57", "Tornado IDS": "tornado", "Tu-160": "tu160",
	"Eurofighter Typhoon": "typhoon", "AJ 37 Viggen": "viggen", "YF-23 Black Widow II": "yf23",
}

## 用户裁定：虚构/原创机不制作 PNG，统一保留它们原本的 polygon/special renderer。
const LEGACY_DISPLAY_NAMES: Array[String] = [
	"X-02", "X-02 Wyvern", "X-09 Thunder Owl", "X-13 Skyfalcon", "X-21 Longreach",
	"X-44 Anvil", "X-77 Phantom Raven", "X-90 Skywhale", "AX-00 Starweaver", "AF-03",
	"Cre", "DEADAIR", "Snowblind", "Sentinel", "MQ-112",
	"Aegis UAV", "MQ-X", "DRONE", "Probe", "Mother Goose",
	"Hyper-A G0", "Hyper-A G1", "Hyper-A G2", "Hyper-A G3",
	"ORION", "FANG", "FANG-1", "FANG-2",
]

## 三维生产使用的稳定规范 key。这里不把 legacy 机型放进 PNG 白名单；
## `key_for()` 仍只返回 DISPLAY_KEYS，保持二维回退与既有测试语义不变。
const LEGACY_MODEL_KEYS: Dictionary = {
	"X-02": "x02", "X-02 Wyvern": "x02", "X-09 Thunder Owl": "x09",
	"X-13 Skyfalcon": "x13", "X-21 Longreach": "x21", "X-44 Anvil": "x44",
	"X-77 Phantom Raven": "x77", "X-90 Skywhale": "x90",
	"AX-00 Starweaver": "ax00", "AF-03": "af03", "Cre": "cre",
	"DEADAIR": "deadair", "Snowblind": "snowblind", "Sentinel": "sentinel",
	"MQ-112": "mq112", "Aegis UAV": "aegis_uav", "MQ-X": "mqx",
	"DRONE": "loyal_wingman", "Probe": "probe", "Mother Goose": "mother_goose",
	"Hyper-A G0": "hyper_a", "Hyper-A G1": "hyper_a",
	"Hyper-A G2": "hyper_a", "Hyper-A G3": "hyper_a",
	"ORION": "orion_final_form", "FANG": "orion_fang",
	"FANG-1": "orion_fang", "FANG-2": "orion_fang",
}

const DRAW_SCALE: Dictionary = {
	"ah64": 1.55, "ch47": 1.85, "b1b": 2.05, "tu160": 2.10,
	"mq109_family": 0.53,
}

## 只控制二维滚转投影；不进入物理、碰撞或传感器判定。
const DEFAULT_VOLUME_THICKNESS: float = 0.22
const VOLUME_THICKNESS: Dictionary = {
	"ah64": 0.30, "ch47": 0.30,
	"b1b": 0.17, "tu160": 0.17,
	"mq109_family": 0.18,
}


static func key_for(ac: Aircraft) -> String:
	if ac.params != null:
		var direct: String = DISPLAY_KEYS.get(ac.params.display_name, "")
		if direct != "":
			return direct
		# 生存模式玩家机会在 display_name 后拼接档案代号（如 F-14 Tomcat Warhound）；
		# SurvivorPlayableSetup 已把拼接前的纯机型名保存在此 meta，轮廓识别必须使用它。
		var airframe_name := String(ac.get_meta("airframe_label", "")).strip_edges()
		var airframe_key: String = DISPLAY_KEYS.get(airframe_name, "")
		if airframe_key != "":
			return airframe_key
	return ""


## 全机型三维目录的规范身份：现实/已登记机沿用 DISPLAY_KEYS，原创/特种机走
## LEGACY_MODEL_KEYS。同型号的玩家、僚机、敌人和显示名后缀必须返回同一 key。
static func canonical_model_key_for(ac: Aircraft) -> String:
	var mapped := key_for(ac)
	if mapped != "":
		return mapped
	if ac.params != null:
		var direct := String(LEGACY_MODEL_KEYS.get(ac.params.display_name, ""))
		if direct != "":
			return direct
	var airframe_name := String(ac.get_meta("airframe_label", "")).strip_edges()
	return String(LEGACY_MODEL_KEYS.get(airframe_name, ""))


## 离线审计、模型画廊和非 Aircraft 载体使用；不接受呼号/品质后缀猜测。
static func canonical_model_key_for_display_name(display_name: String) -> String:
	var normalized := display_name.strip_edges()
	var mapped := String(DISPLAY_KEYS.get(normalized, ""))
	return mapped if mapped != "" else String(LEGACY_MODEL_KEYS.get(normalized, ""))


static func canonical_model_keys() -> Array[String]:
	var result: Array[String] = []
	for raw: Variant in DISPLAY_KEYS.values():
		var key := String(raw)
		if key not in result:
			result.append(key)
	for raw: Variant in LEGACY_MODEL_KEYS.values():
		var key := String(raw)
		if key not in result:
			result.append(key)
	result.sort()
	return result


## UI 等非 Aircraft 载体按基础机型名读取同一份正式轮廓，避免另建预览模型目录。
static func texture_for_display_name(display_name: String) -> Texture2D:
	var key := String(DISPLAY_KEYS.get(display_name.strip_edges(), ""))
	return _texture_for(key)


static func draw_scale_for(ac: Aircraft) -> float:
	return float(DRAW_SCALE.get(key_for(ac), 1.0))


static func volume_thickness_for(ac: Aircraft) -> float:
	var key := key_for(ac)
	if VOLUME_THICKNESS.has(key):
		return float(VOLUME_THICKNESS[key])
	var silhouette := String(ac.get_meta("silhouette", ""))
	match silhouette:
		"apache", "chinook":
			return 0.30
		"bomber":
			return 0.17
		"drone":
			return 0.18
		"mother_goose", "hyper_a":
			return 0.14
	return DEFAULT_VOLUME_THICKNESS


## Loading 预热：按 TEXTURE_PATHS 顺序加载尚未缓存的轮廓。budget_usec>0 时本次调用
## 超出预算即返回，留待下一帧继续；返回 true 表示全部 key 已进缓存（或加载失败已告警）。
## 刷怪帧首次出现新机型时不再读盘解码（每机型 1~2ms）。
static func prewarm_textures(budget_usec: int = 0) -> bool:
	var start := Time.get_ticks_usec()
	for key: String in TEXTURE_PATHS:
		if _texture_cache.has(key) or _texture_failed.has(key):
			continue
		_texture_for(key)
		if budget_usec > 0 and Time.get_ticks_usec() - start >= budget_usec:
			return _prewarm_done()
	return _prewarm_done()


static func _prewarm_done() -> bool:
	return _texture_cache.size() + _texture_failed.size() >= TEXTURE_PATHS.size()


static func _texture_for(key: String) -> Texture2D:
	var cached: Variant = _texture_cache.get(key, null)
	if cached is Texture2D:
		return cached as Texture2D
	if _texture_failed.has(key):
		return null
	var path := String(TEXTURE_PATHS.get(key, ""))
	if path == "":
		return null
	return _load_texture(key, path)


## 导入设置为无损、无 mipmap，且 PNG 全部像素 RGB 为白，导入纹理与原图逐像素一致。
static func _load_texture(key: String, path: String) -> Texture2D:
	var texture: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		_texture_failed[key] = true
		push_warning("Aircraft silhouette texture could not be loaded: %s" % path)
		return null
	_texture_cache[key] = texture
	return texture


static func draw_icon(ac: Aircraft, color: Color, size: float,
		face_xform: Transform2D, shell_xform: Transform2D,
		face_alpha: float = 1.0, belly_visible: bool = false) -> bool:
	var key := key_for(ac)
	var texture := _texture_for(key)
	if texture == null:
		return false
	var fill := color
	if ac.params != null and ac.params.wing_color.a > 0.01:
		fill = ac.params.wing_color
		# presentation_alpha 通过 color.a 传入；自定义翼色只替换 RGB/自身 alpha，不能吞掉坠毁渐隐。
		fill.a *= clampf(color.a, 0.0, 1.0)
	var outline := fill.darkened(0.34)
	var half_extent := size * 1.25 * float(DRAW_SCALE.get(key, 1.0))
	var rect := Rect2(Vector2(-half_extent, -half_extent), Vector2.ONE * half_extent * 2.0)
	ac.draw_set_transform_matrix(shell_xform)
	# 同一暗边在滚转时扩展为壳层；仍只消费一次纹理提交。
	var outline_offset := Vector2(0.55, 0.65)
	ac.draw_texture_rect(texture, Rect2(rect.position + outline_offset, rect.size), false, outline)
	if face_alpha > 0.001:
		var face_fill := fill.darkened(0.18) if belly_visible else fill
		face_fill.a *= clampf(face_alpha, 0.0, 1.0)
		ac.draw_set_transform_matrix(face_xform)
		ac.draw_texture_rect(texture, rect, false, face_fill)
	ac.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true
