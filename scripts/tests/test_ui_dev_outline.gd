extends RefCounted

const UiDevOutlineOverlayScript := preload("res://scripts/ui/ui_dev_outline_overlay.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const SurvivorDebugZoneScript := preload("res://scripts/survivor/survivor_debug_zone.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ UI Dev 面板定位覆盖层验收 ════════")
	_test_geometry_only_hierarchy()
	_test_stable_top_level_letters()
	_test_visual_contract()
	_test_hotkey_contract()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


func _test_geometry_only_hierarchy() -> void:
	var root := Rect2(0.0, 0.0, 80.0, 36.0)
	var child := Rect2(0.0, 0.0, 40.0, 18.0)
	var grandchild := Rect2(0.0, 0.0, 18.0, 18.0)
	var independent := Rect2(100.0, 0.0, 18.0, 18.0)
	var entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries([
		independent, grandchild, root, child, root,
	])
	_check("重复矩形只生成一个定位框", entries.size() == 4)
	_check("顶层从 A 开始且只按位置排序",
		_code_for_rect(entries, root) == "A"
		and _code_for_rect(entries, independent) == "B")
	_check("包含关系自动生成纯几何层级",
		_code_for_rect(entries, child) == "A.1"
		and _code_for_rect(entries, grandchild) == "A.1.1")
	var flat_entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries([
		independent, grandchild, root, child,
	], true)
	_check("Dev 场景将全部可编辑子框压成两级定位",
		_code_for_rect(flat_entries, child) == "A1"
		and _code_for_rect(flat_entries, grandchild) == "A2")


func _test_stable_top_level_letters() -> void:
	var regions: Array[Rect2] = []
	for index in range(27):
		regions.append(Rect2(float(index) * 20.0, 0.0, 18.0, 18.0))
	var entries: Array[Dictionary] = UiDevOutlineOverlayScript.build_entries(regions)
	_check("前 26 个顶层使用 A-Z",
		String(entries[0]["code"]) == "A"
		and String(entries[25]["code"]) == "Z")
	_check("超过 Z 后稳定延伸为 AA", String(entries[26]["code"]) == "AA")


func _test_visual_contract() -> void:
	_check("定位框固定使用 2px 紫色描边",
		is_equal_approx(UiDevOutlineOverlayScript.OUTLINE_WIDTH, 2.0)
		and UiDevOutlineOverlayScript.OUTLINE_COLOR == Color("b94cff"))
	_check("描边向内缩进避免改变面板占地",
		is_equal_approx(UiDevOutlineOverlayScript.OUTLINE_INSET, 1.0))


func _test_hotkey_contract() -> void:
	_check("F6 继续专用于战区 Debug，F7 专用于 UI Dev",
		SurvivorDebugZoneScript.TOGGLE_KEY == KEY_F6
		and SurvivorHUDScript.UI_DEV_TOGGLE_KEY == KEY_F7)
	var hud = SurvivorHUDScript.new()
	hud._build_ui()
	hud.toggle_ui_dev_overlay()
	_check("F7 入口第一次调用显示实际 HUD 定位层",
		hud.is_ui_dev_overlay_visible()
		and hud._ui_dev_overlay != null
		and hud._ui_dev_overlay.visible)
	_check("F7 同时提供手动添加 FLR 控制键的测试按钮",
		hud._ui_dev_manual_flare_button != null
		and hud._ui_dev_manual_flare_button.visible
		and hud._ui_dev_manual_flare_button.text.contains("MANUAL FLR"))
	hud.toggle_ui_dev_overlay()
	_check("F7 入口第二次调用关闭定位层",
		not hud.is_ui_dev_overlay_visible()
		and not hud._ui_dev_overlay.visible
		and not hud._ui_dev_manual_flare_button.visible)
	hud.free()


func _code_for_rect(entries: Array[Dictionary], target: Rect2) -> String:
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		if rect == target:
			return String(entry["code"])
	return ""


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
