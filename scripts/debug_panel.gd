extends CanvasLayer

## Debug 监控面板：显示存活飞机列表、AI 策略、并提供生成敌人按钮

const SPAWN_DISTANCE := 2000.0  ## 生成敌人与玩家的距离（像素）

var _visible := false
var _panel: PanelContainer
var _content_label: RichTextLabel
var _toggle_btn: Button
var _spawn_btn: Button

var _enemy_scene: PackedScene
var _enemy_params: Resource

func _ready() -> void:
	layer = 100
	_enemy_scene = preload("res://scenes/aircraft.tscn")
	_enemy_params = preload("res://resources/enemy_fighter.tres")
	_build_ui()

func _build_ui() -> void:
	# --- 右上角开关按钮 ---
	_toggle_btn = Button.new()
	_toggle_btn.text = "DEBUG"
	_toggle_btn.position = Vector2(0, 0)
	_toggle_btn.custom_minimum_size = Vector2(70, 30)
	_toggle_btn.add_theme_font_size_override("font_size", 12)
	add_child(_toggle_btn)
	_toggle_btn.pressed.connect(_on_toggle)

	# --- 面板 ---
	_panel = PanelContainer.new()
	_panel.visible = false
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.88)
	style.border_color = Color(0.3, 0.6, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "[ DEBUG MONITOR ]"
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# 分割线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 内容
	_content_label = RichTextLabel.new()
	_content_label.bbcode_enabled = true
	_content_label.fit_content = true
	_content_label.custom_minimum_size = Vector2(320, 100)
	_content_label.scroll_active = true
	_content_label.add_theme_font_size_override("normal_font_size", 12)
	_content_label.add_theme_font_size_override("bold_font_size", 12)
	_content_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.85))
	vbox.add_child(_content_label)

	# 分割线
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# 补充弹药按钮
	var reload_btn := Button.new()
	reload_btn.text = "补充弹药"
	reload_btn.custom_minimum_size = Vector2(0, 32)
	reload_btn.add_theme_font_size_override("font_size", 13)
	vbox.add_child(reload_btn)
	reload_btn.pressed.connect(_on_reload_ammo)

	# 生成敌人按钮
	_spawn_btn = Button.new()
	_spawn_btn.text = "生成敌人"
	_spawn_btn.custom_minimum_size = Vector2(0, 32)
	_spawn_btn.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_spawn_btn)
	_spawn_btn.pressed.connect(_on_spawn_enemy)

func _process(_delta: float) -> void:
	_layout_ui()
	if _visible:
		_update_content()

func _layout_ui() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	# 按钮固定在右上角
	_toggle_btn.position = Vector2(vp_size.x - _toggle_btn.size.x - 10, 10)
	# 面板在按钮下方
	if _panel.visible:
		_panel.position = Vector2(vp_size.x - _panel.size.x - 10, 48)

func _on_toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	_toggle_btn.text = "DEBUG ▼" if _visible else "DEBUG"

func _update_content() -> void:
	var main := get_parent()
	if not main:
		return

	var text := ""
	var friendly_count := 0
	var enemy_count := 0

	# 收集飞机
	var aircraft_list: Array = []
	for child in main.get_children():
		if child is Aircraft and not child.is_destroyed:
			aircraft_list.append(child)

	# 统计
	for ac: Aircraft in aircraft_list:
		if ac.team == 0:
			friendly_count += 1
		else:
			enemy_count += 1

	text += "[b]存活飞机[/b]  友军: %d  敌军: %d\n" % [friendly_count, enemy_count]
	text += "[color=#555555]─────────────────────────[/color]\n"

	for ac: Aircraft in aircraft_list:
		var team_color := "#6699ff" if ac.team == 0 else "#ff6655"
		var team_tag := "友" if ac.team == 0 else "敌"
		var display_name: String = ac.params.display_name if ac.params else str(ac.name)

		var hdg_deg := rad_to_deg(ac.heading)
		if hdg_deg < 0:
			hdg_deg += 360.0
		var speed_kmh := ac.speed * 3.6
		var alt := ac.altitude

		text += "[color=%s][b][%s] %s[/b][/color]\n" % [team_color, team_tag, display_name]
		text += "  HDG %03d  SPD %.0f km/h  ALT %.0fm\n" % [roundi(hdg_deg), speed_kmh, alt]
		text += "  HP %.0f  MSL %d  AMM %d\n" % [ac.hp, ac.missiles_remaining, ac.ammo]

		# AI 策略
		var strategy := _get_strategy_text(ac)
		if strategy != "":
			text += "  [color=#aaddaa]策略: %s[/color]\n" % strategy
		text += "\n"

	_content_label.text = text

func _get_strategy_text(ac: Aircraft) -> String:
	# 玩家飞机
	if ac.team == 0:
		if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
			return _get_combat_strategy(ac)
		elif ac.target_position != Vector2.INF:
			return "航向指定目标"
		else:
			return "待命"

	# AI 飞机
	if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		return _get_combat_strategy(ac)

	# 检查 AIController
	for child in ac.get_children():
		if child is AIController:
			var ctrl: AIController = child
			if ctrl.waypoints.size() > 0:
				return "巡逻 (航点 %d/%d)" % [ctrl.current_waypoint_index + 1, ctrl.waypoints.size()]
			else:
				return "无航点"
	return "空闲"

func _get_combat_strategy(ac: Aircraft) -> String:
	var target_name := ""
	if ac.combat_target and is_instance_valid(ac.combat_target):
		target_name = ac.combat_target.name

	var mode_str := ""
	if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
		var phase := ac._get_missile_phase()
		var phase_names := ["接近", "照射", "保持/Crank"]
		mode_str = "导弹[%s]" % phase_names[phase]
		if ac.is_cranking():
			mode_str += " (照射中)"
	else:
		mode_str = "机炮"
		if ac.is_firing:
			mode_str += " (开火中)"

	return "交战 → %s  模式: %s" % [target_name, mode_str]

func _on_reload_ammo() -> void:
	var main := get_parent()
	if not main:
		return
	for child in main.get_children():
		if child is Aircraft and not child.is_destroyed:
			if child.params:
				if child.params.gun:
					child.ammo = child.params.gun.max_ammo
				if child.params.missile:
					child.missiles_remaining = child.params.missile.max_count

func _on_spawn_enemy() -> void:
	var main := get_parent()
	if not main:
		return

	# 找到玩家飞机位置
	var player_pos := Vector2.ZERO
	for child in main.get_children():
		if child is Aircraft and child.team == 0 and not child.is_destroyed:
			player_pos = child.global_position
			break

	# 随机方向
	var angle := randf() * TAU
	var spawn_pos := player_pos + Vector2(cos(angle), sin(angle)) * SPAWN_DISTANCE

	# 生成敌机
	var enemy: Aircraft = _enemy_scene.instantiate()
	enemy.params = _enemy_params
	enemy.team = 1
	enemy.position = spawn_pos
	# 朝向玩家
	var to_player := (player_pos - spawn_pos).normalized()
	enemy.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))

	main.add_child(enemy)

	# 注入 bullet/missile manager
	for child in main.get_children():
		if child is BulletManager:
			enemy.bullet_manager = child
		elif child is MissileManager:
			enemy.missile_manager = child

	# 添加 AI 控制器（巡逻航点围绕玩家位置）
	var ai := AIController.new()
	ai.name = "AI_%s" % enemy.name
	ai.aircraft = enemy
	ai.patrol_altitude = randf_range(4000.0, 8000.0)
	ai.waypoints = PackedVector2Array([
		player_pos + Vector2(800, -800),
		player_pos + Vector2(800, 800),
		player_pos + Vector2(-800, 800),
		player_pos + Vector2(-800, -800),
	])
	enemy.add_child(ai)
