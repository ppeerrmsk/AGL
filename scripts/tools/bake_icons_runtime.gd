extends Node
## 运行时飞机图标烘焙器（无需编辑器 GUI，可被 godot-mcp run_project 驱动）
##
## 用法：以 scenes/tools/bake_icons.tscn 为主场景运行（命令行 `godot <proj> scenes/tools/bake_icons.tscn`
## 或编辑器「运行指定场景」）。烘焙完自动 quit。
##   - PNG 写到 res://textures/aircraft_icons/
##   - manifest 写到 res://resources/aircraft_icon_manifest.tres
## 详见 docs/planning/sprite-multimesh-refactor.md
##
## 几何与 live _draw 共用 AircraftRenderer.draw_fighter_geometry（单一几何源，避免 drift）。
## 运行时把 SubViewport 挂到自身（活跃 scene tree）即可渲染——区别于编辑器版需要 EditorInterface。
##
## v1 范围：只烘焙 fighter（占多数机型）。颜色烘成白色，运行时 Sprite2D.modulate 染色。
## v2 扩展：commander / bomber / apache / chinook / drone / mother_goose——
##   待 draw_*_icon 子函数首参从 ac:Aircraft 重构为 ci:CanvasItem 后即可在此追加 silhouette。

const OUT_DIR := "res://textures/aircraft_icons"
const MANIFEST_PATH := "res://resources/aircraft_icon_manifest.tres"
const TEXTURE_SIZE := Vector2i(128, 128)
const RENDER_SCALE := GameConstants.SPRITE_ICON_BAKE_SCALE  ## 单一来源，与 Sprite2D 缩回倍率一致
const BAKE_COLOR := Color.WHITE
const BAKE_OUTLINE := Color(0.7, 0.7, 0.7)


func _ready() -> void:
	await _bake_all()
	get_tree().quit()


func _bake_all() -> void:
	print("[bake_icons_runtime] start")
	_ensure_out_dir()
	var entries: Array[Dictionary] = []
	var fighter_path := await _bake_silhouette("fighter")
	if fighter_path != "":
		entries.append({"id": "fighter", "path": fighter_path})
	_write_manifest(entries)
	print("[bake_icons_runtime] done; baked %d entries" % entries.size())


func _ensure_out_dir() -> void:
	var dir_abs := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
		print("[bake_icons_runtime] created %s" % dir_abs)


## 烘焙单个 silhouette → 返回 PNG res:// 路径（失败返回 ""）
func _bake_silhouette(silhouette: String) -> String:
	var viewport := SubViewport.new()
	viewport.size = TEXTURE_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.snap_2d_transforms_to_pixel = false
	viewport.snap_2d_vertices_to_pixel = false
	viewport.msaa_2d = Viewport.MSAA_4X

	var drawer := _RuntimeIconDrawer.new()
	drawer.silhouette = silhouette
	drawer.position = Vector2(TEXTURE_SIZE) * 0.5  # 几何中心对齐纹理中心
	drawer.bake_color = BAKE_COLOR
	drawer.bake_outline = BAKE_OUTLINE
	drawer.render_scale = RENDER_SCALE
	viewport.add_child(drawer)
	add_child(viewport)

	# 等两帧确保渲染完成（一帧太早可能 capture 到空）
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := viewport.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("[bake_icons_runtime] empty viewport image for %s" % silhouette)
		viewport.queue_free()
		return ""

	var rel_path := "%s/%s.png" % [OUT_DIR, silhouette]
	var abs_path := ProjectSettings.globalize_path(rel_path)
	var err := img.save_png(abs_path)
	viewport.queue_free()

	if err != OK:
		push_error("[bake_icons_runtime] save_png failed (%d) for %s" % [err, rel_path])
		return ""

	print("[bake_icons_runtime] saved %s" % rel_path)
	return rel_path


## 写 manifest.tres：silhouette_id → texture path，嵌在 Resource 的 metadata/icons
func _write_manifest(entries: Array[Dictionary]) -> void:
	var lines: PackedStringArray = []
	lines.append("[gd_resource type=\"Resource\" format=3]")
	lines.append("")
	lines.append("[resource]")
	lines.append("script = null")
	var dict_str := "{"
	var first := true
	for e in entries:
		if not first:
			dict_str += ", "
		first = false
		dict_str += "\"%s\": \"%s\"" % [e["id"], e["path"]]
	dict_str += "}"
	lines.append("metadata/icons = %s" % dict_str)
	lines.append("")

	var abs_path := ProjectSettings.globalize_path(MANIFEST_PATH)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("[bake_icons_runtime] cannot open manifest: %s" % abs_path)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("[bake_icons_runtime] wrote manifest %s" % MANIFEST_PATH)


## 内部 drawer：以自身为 Canvas，调共用几何函数（中性 pose：无旋转/bank/机动形变）
class _RuntimeIconDrawer extends Node2D:
	var silhouette: String = "fighter"
	var bake_color: Color = Color.WHITE
	var bake_outline: Color = Color(0.7, 0.7, 0.7)
	var render_scale: float = 3.5

	func _draw() -> void:
		match silhouette:
			"fighter":
				var xform := Transform2D(0.0, Vector2.ZERO).scaled(Vector2(render_scale, render_scale))
				AircraftRenderer.draw_fighter_geometry(self, 16.0, bake_color, bake_outline, bake_color, bake_outline, xform)
			_:
				push_warning("[bake_icons_runtime] unknown silhouette: %s" % silhouette)
