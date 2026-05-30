class_name AircraftIconManifest
extends RefCounted

## 飞机图标 manifest 加载器（Sprite2D 路径）
##
## 持 silhouette → Texture2D 缓存，由 Aircraft._setup_sprite_icon 查询。
## Manifest 文件由 scripts/tools/bake_aircraft_icons.gd 生成；
## 详见 docs/planning/sprite-multimesh-refactor.md
##
## v1 范围：只有 "fighter" 一个 silhouette 有烘焙纹理；其他 silhouette 返回 null，
## Aircraft 自动回退到 _draw 老路径。

const MANIFEST_PATH := "res://resources/aircraft_icon_manifest.tres"

# 静态缓存：进程级共享，避免每架飞机各自 load
static var _texture_cache: Dictionary = {}     ## silhouette(String) → Texture2D
static var _manifest_loaded: bool = false
static var _silhouette_to_path: Dictionary = {}  ## silhouette(String) → res:// path(String)


## 查询某个 silhouette 对应的 Sprite2D 纹理。
## 返回 null 表示该 silhouette 没有烘焙纹理（调用方应回退到 _draw 老路径）。
static func get_texture(silhouette: String) -> Texture2D:
	if _texture_cache.has(silhouette):
		return _texture_cache[silhouette]
	if not _manifest_loaded:
		_load_manifest()
	if not _silhouette_to_path.has(silhouette):
		return null
	var path: String = _silhouette_to_path[silhouette]
	if not ResourceLoader.exists(path):
		push_warning("[AircraftIconManifest] texture missing: %s (for silhouette '%s')" % [path, silhouette])
		_texture_cache[silhouette] = null
		return null
	var tex := load(path) as Texture2D
	_texture_cache[silhouette] = tex
	return tex


## 强制重新加载 manifest（用于烘焙工具刚跑完后热刷新；运行时不必调用）
static func reload() -> void:
	_manifest_loaded = false
	_silhouette_to_path.clear()
	_texture_cache.clear()


static func _load_manifest() -> void:
	_manifest_loaded = true
	if not ResourceLoader.exists(MANIFEST_PATH):
		# manifest 不存在 → 用户没跑过烘焙工具；保持空 dict，调用方回退到 _draw
		return
	var res: Resource = load(MANIFEST_PATH)
	if res == null:
		push_warning("[AircraftIconManifest] manifest exists but load returned null: %s" % MANIFEST_PATH)
		return
	if not res.has_meta("icons"):
		push_warning("[AircraftIconManifest] manifest missing 'icons' metadata: %s" % MANIFEST_PATH)
		return
	var icons_dict: Dictionary = res.get_meta("icons")
	for k in icons_dict.keys():
		_silhouette_to_path[String(k)] = String(icons_dict[k])
