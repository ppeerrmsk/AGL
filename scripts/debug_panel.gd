extends CanvasLayer

## Debug 监控面板：显示存活飞机列表、AI 策略、并提供生成敌人按钮

const SPAWN_DISTANCE := 2000.0  ## 生成敌人与玩家的距离（像素）

var _visible := false
var _left_panel: PanelContainer    ## 左侧按钮面板
var _right_panel: PanelContainer   ## 右侧状态面板
var _content_label: RichTextLabel
var _scroll: ScrollContainer
var _toggle_btn: Button

var _enemy_scene: PackedScene
var _enemy_params: Resource
var _drone_params: Resource
var _ally_params: Resource

# 地面单位
var _sam_scene: PackedScene
var _sam_params: Resource
var _aa_scene: PackedScene
var _aa_params: Resource
var _radar_scene: PackedScene
var _radar_params: Resource

func _ready() -> void:
	layer = 100
	_enemy_scene = preload("res://scenes/aircraft.tscn")
	_enemy_params = preload("res://resources/enemy_fighter.tres")
	_drone_params = preload("res://resources/drone_probe.tres")
	_ally_params = preload("res://resources/default_fighter.tres")
	_sam_scene = preload("res://scenes/sam_unit.tscn")
	_sam_params = preload("res://resources/sam_params.tres")
	_aa_scene = preload("res://scenes/aa_gun_unit.tscn")
	_aa_params = preload("res://resources/aa_gun_params.tres")
	_radar_scene = preload("res://scenes/radar_station.tscn")
	_radar_params = preload("res://resources/radar_station_params.tres")
	_build_ui()

func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.88)
	panel_style.border_color = Color(0.3, 0.6, 0.3, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)

	# --- 右上角开关按钮 ---
	_toggle_btn = Button.new()
	_toggle_btn.text = "DEBUG"
	_toggle_btn.custom_minimum_size = Vector2(70, 30)
	_toggle_btn.add_theme_font_size_override("font_size", 12)
	add_child(_toggle_btn)
	_toggle_btn.pressed.connect(_on_toggle)

	# ═══════════════════════════════════════
	#  左侧面板：操作按钮
	# ═══════════════════════════════════════
	_left_panel = PanelContainer.new()
	_left_panel.visible = false
	_left_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 4)
	_left_panel.add_child(left_vbox)

	var left_title := Label.new()
	left_title.text = "[ CONTROLS ]"
	left_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	left_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(left_title)

	left_vbox.add_child(HSeparator.new())

	# 生成按钮
	var btn_data := [
		["F1: 4机小队", _on_spawn_squad_4],
		["F2: 2机小队", _on_spawn_squad_2],
		["F3: 2架敌机", _on_spawn_enemies_2],
		["F4: 4架敌机", _on_spawn_enemies_4],
		["F5: 切换阵型", _on_cycle_formation],
		["──────────", null],
		["生成 MiG", _on_spawn_enemy],
		["生成 Probe", _on_spawn_probe],
		["生成友军", _on_spawn_ally],
		["──────────", null],
		["SAM (敌)", _on_spawn_enemy_sam],
		["SAM (友)", _on_spawn_friendly_sam],
		["AA炮 (敌)", _on_spawn_enemy_aa],
		["AA炮 (友)", _on_spawn_friendly_aa],
		["雷达站 (敌)", _on_spawn_enemy_radar],
		["雷达站 (友)", _on_spawn_friendly_radar],
	]
	for bd in btn_data:
		if bd[1] == null:
			left_vbox.add_child(HSeparator.new())
			continue
		var btn := Button.new()
		btn.text = bd[0]
		btn.custom_minimum_size = Vector2(120, 30)
		btn.add_theme_font_size_override("font_size", 12)
		left_vbox.add_child(btn)
		btn.pressed.connect(bd[1])

	left_vbox.add_child(HSeparator.new())

	# 工具按钮
	var reload_btn := Button.new()
	reload_btn.text = "补充弹药"
	reload_btn.custom_minimum_size = Vector2(120, 30)
	reload_btn.add_theme_font_size_override("font_size", 12)
	left_vbox.add_child(reload_btn)
	reload_btn.pressed.connect(_on_reload_ammo)

	# ═══════════════════════════════════════
	#  右侧面板：飞机状态（可滚动）
	# ═══════════════════════════════════════
	_right_panel = PanelContainer.new()
	_right_panel.visible = false
	var right_style := panel_style.duplicate()
	_right_panel.add_theme_stylebox_override("panel", right_style)
	add_child(_right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 4)
	_right_panel.add_child(right_vbox)

	var right_title := Label.new()
	right_title.text = "[ STATUS MONITOR ]"
	right_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	right_title.add_theme_font_size_override("font_size", 14)
	right_vbox.add_child(right_title)

	right_vbox.add_child(HSeparator.new())

	# 滚动容器包裹内容
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_vbox.add_child(_scroll)

	_content_label = RichTextLabel.new()
	_content_label.bbcode_enabled = true
	_content_label.fit_content = true
	_content_label.scroll_active = false  # 由外层 ScrollContainer 控制
	_content_label.custom_minimum_size = Vector2(340, 0)
	_content_label.add_theme_font_size_override("normal_font_size", 12)
	_content_label.add_theme_font_size_override("bold_font_size", 12)
	_content_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.85))
	_scroll.add_child(_content_label)

func _process(_delta: float) -> void:
	_layout_ui()
	if _visible:
		_update_content()

func _layout_ui() -> void:
	var vp_size := get_viewport().get_visible_rect().size

	# 开关按钮：左上角
	_toggle_btn.position = Vector2(10, 10)

	if _visible:
		# 左侧按钮面板：左上角按钮下方
		_left_panel.position = Vector2(10, 48)

		# 右侧状态面板：紧贴左侧面板右边
		var left_w := _left_panel.size.x
		var right_x := 10 + left_w + 8
		var right_w := minf(380.0, vp_size.x - right_x - 10)
		var panel_h := vp_size.y - 48 - 10  # 从按钮下方到屏幕底部
		_scroll.custom_minimum_size = Vector2(right_w - 20, panel_h - 60)
		_right_panel.position = Vector2(right_x, 48)

func _on_toggle() -> void:
	_visible = not _visible
	_left_panel.visible = _visible
	_right_panel.visible = _visible
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

	# 编队信息
	if "active_squad" in main and main.active_squad != null:
		var sq: Squad = main.active_squad
		if sq and sq.leader:
			text += "[color=#66aaff][b]编队[/b] %s  成员: %d[/color]\n" % [sq.get_formation_name(), sq.members.size()]
			for i in range(sq.members.size()):
				var m: Aircraft = sq.members[i]
				if not is_instance_valid(m) or m.is_destroyed:
					continue
				var role := "长机" if i == 0 else "僚机%d" % i
				var lod_names: Array[String] = ["完整", "简化", "屏外"]
				var lod_str: String = lod_names[clampi(m.lod_level, 0, 2)]
				# 计算与阵型位置的偏差
				var deviation := 0.0
				if i > 0:
					var slot_pos := sq.get_wingman_target(i)
					if slot_pos != Vector2.INF:
						deviation = m.global_position.distance_to(slot_pos)
				var dev_str := "  偏差%.0fpx" % deviation if i > 0 else ""
				text += "  [color=#88bbff]%s[/color] %s  LOD=%s%s\n" % [role, m.callsign, lod_str, dev_str]
			text += "\n"

	text += "[color=#555555]─────────────────────────[/color]\n"
	text += "[color=#666666]F1:4机队 F2:2机队 F3:2敌 F4:4敌 F5:阵型[/color]\n"
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

		text += "[color=%s][b][%s] %s [%s][/b][/color]\n" % [team_color, team_tag, ac.callsign, display_name]
		text += "  HDG %03d  SPD %.0f km/h  ALT %.0fm\n" % [roundi(hdg_deg), speed_kmh, alt]
		# 弹药：AGM 仅在机型装备副导弹时显示
		if ac.params and ac.params.secondary_missile:
			text += "  HP %.0f  MSL %d  AGM %d  AMM %d  FLR %d\n" % [ac.hp, ac.missiles_remaining, ac.secondary_missiles_remaining, ac.ammo, ac.flares_remaining]
		else:
			text += "  HP %.0f  MSL %d  AMM %d  FLR %d\n" % [ac.hp, ac.missiles_remaining, ac.ammo, ac.flares_remaining]

		# AI 策略
		var strategy := _get_strategy_text(ac)
		if strategy != "":
			text += "  [color=#aaddaa]策略: %s[/color]\n" % strategy

		# 飞行员状态子面板
		var pilot_info := _get_pilot_info(ac)
		if pilot_info != "":
			text += pilot_info

		text += "\n"

	_content_label.text = text

func _get_strategy_text(ac: Aircraft) -> String:
	# 找 AIController
	var ctrl: AIController = null
	for child in ac.get_children():
		if child is AIController:
			ctrl = child
			break

	# 无 AI（玩家）飞机
	if ctrl == null:
		if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
			return _get_combat_strategy(ac)
		elif ac.target_position != Vector2.INF:
			return "航向指定目标"
		else:
			return "待命"

	# 有 AI 的飞机：优先按 AI 状态判定

	# 交战中
	if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		# 协同攻击长机指定的目标
		if ctrl._squad_attacking_leader_target:
			var tgt_name := ""
			if ac.combat_target.callsign != "":
				tgt_name = ac.combat_target.callsign
			else:
				tgt_name = ac.combat_target.name
			var mode_str := ""
			if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
				var phase := ac._get_missile_phase()
				var phase_names := ["接近", "照射", "保持"]
				mode_str = "导弹[%s]" % phase_names[phase]
			else:
				mode_str = "机炮"
				if ac.is_firing:
					mode_str += " (开火中)"
			return "[color=#ffaa33]协同攻击[/color] → %s  模式: %s" % [tgt_name, mode_str]
		return _get_combat_strategy(ac)

	# 无战斗目标：按 AI 状态
	match ctrl._state:
		AIController.AIState.PATROL:
			if ctrl.waypoints.size() > 0:
				var extra := ""
				if ctrl.enable_combat and ctrl._cooldown_timer > 0.0:
					extra = " (冷却 %.0fs)" % ctrl._cooldown_timer
				return "巡逻 (航点 %d/%d)%s" % [ctrl.current_waypoint_index + 1, ctrl.waypoints.size(), extra]
			else:
				return "无航点"
		AIController.AIState.ENGAGE:
			var tactic_str := ctrl.current_tactic_name if ctrl.current_tactic_name != "" else "---"
			# planner 模式：附带 plan.rationale 解释为什么选了这个 intent（仅 debug 面板可见）
			var rationale_str := ""
			if ctrl.aircraft and ctrl.aircraft.use_tactical_planner and ctrl.aircraft._last_plan:
				var why: String = ctrl.aircraft._last_plan.rationale
				if why != "":
					rationale_str = "\n  └ %s" % why
			return "交战 [%s] (%.0fs)%s" % [tactic_str, ctrl._engage_timer, rationale_str]
		AIController.AIState.EVADE_MISSILE:
			return "[color=#ff6655]规避导弹[/color]"
		AIController.AIState.SQUAD_FOLLOW:
			# 阵型调整 > 归队 > 正常跟随
			if ctrl._formation_react_timer > 0.0:
				return "[color=#ffcc33]阵型调整[/color]"
			if ctrl._rejoining or ctrl._formation_blend < 0.95:
				return "[color=#ffaa66]归队[/color]"
			return "[color=#66aaff]编队跟随[/color]"
	return "空闲"

func _get_combat_strategy(ac: Aircraft) -> String:
	var target_name := ""
	if ac.combat_target and is_instance_valid(ac.combat_target):
		target_name = ac.combat_target.callsign if ac.combat_target.callsign != "" else ac.combat_target.name

	# 对地攻击（Strafing Run）独立展示
	if ac.combat_target is GroundUnit:
		var strafe_names := ["进入", "攻击", "脱离", "掉头"]
		var strafe_idx: int = clampi(ac._strafe_state, 0, strafe_names.size() - 1)
		var gnd_mode: String
		if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
			var msl_name := ""
			if ac.params and ac.params.secondary_missile:
				msl_name = ac.params.secondary_missile.display_name
			if msl_name == "":
				msl_name = "AGM"
			gnd_mode = "%s导弹" % msl_name
		else:
			gnd_mode = "机炮"
			if ac.is_firing:
				gnd_mode += " (开火中)"
		return "[color=#ffaa55]对地 → %s  %s [%s][/color]" % [target_name, gnd_mode, strafe_names[strafe_idx]]

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

func _get_pilot_info(ac: Aircraft) -> String:
	# 找到 AIController
	var ctrl: AIController = null
	for child in ac.get_children():
		if child is AIController:
			ctrl = child
			break
	if not ctrl:
		return ""

	var skill := ctrl.skill_level
	var comp := ctrl.composure
	var stress: float = ctrl.personality.current_stress if ctrl.personality else 0.0
	var eff := ctrl._effective_skill()

	# 技能评级
	var rank: String
	var rank_color: String
	if skill >= 0.9:
		rank = "王牌"
		rank_color = "#ffd700"  # 金色
	elif skill >= 0.7:
		rank = "老练"
		rank_color = "#88cc88"
	elif skill >= 0.5:
		rank = "合格"
		rank_color = "#aaaaaa"
	elif skill >= 0.3:
		rank = "菜鸟"
		rank_color = "#cc8844"
	else:
		rank = "平民"
		rank_color = "#cc4444"

	# 精神状态
	var mental: String
	var mental_color: String
	if stress < 0.1:
		mental = "冷静"
		mental_color = "#88ccff"
	elif stress < 0.3:
		mental = "专注"
		mental_color = "#88cc88"
	elif stress < 0.5:
		mental = "紧张"
		mental_color = "#cccc44"
	elif stress < 0.7:
		mental = "焦虑"
		mental_color = "#cc8844"
	elif stress < 0.9:
		mental = "慌张"
		mental_color = "#cc4444"
	else:
		mental = "崩溃"
		mental_color = "#ff2222"

	# 压力条：用 █ 和 ░ 拼 10 格
	var bar_filled := roundi(stress * 10)
	var bar_str := ""
	for i in 10:
		bar_str += "[color=%s]%s[/color]" % [mental_color if i < bar_filled else "#333333", "|"]

	# 性格标签
	var fc := ctrl.focus
	var sp := ctrl._effective_self_preservation()
	var personality: String
	var personality_color: String
	if fc >= 0.7 and sp <= 0.3:
		personality = "执着猎手"
		personality_color = "#ff8844"
	elif fc >= 0.7 and sp >= 0.7:
		personality = "冷静职业"
		personality_color = "#88ccff"
	elif fc <= 0.4 and sp >= 0.7:
		personality = "谨慎投机"
		personality_color = "#cccc44"
	elif fc <= 0.4 and sp <= 0.3:
		personality = "莽撞无畏"
		personality_color = "#ff4444"
	elif fc >= 0.6:
		personality = "专注型"
		personality_color = "#aaddaa"
	elif sp >= 0.6:
		personality = "求稳型"
		personality_color = "#aaaadd"
	elif sp <= 0.35:
		personality = "好斗型"
		personality_color = "#ddaaaa"
	else:
		personality = "均衡型"
		personality_color = "#aaaaaa"

	var text := "  [color=#777777]── 飞行员 ──[/color]\n"
	text += "  评级 [color=%s]%s[/color]  性格 [color=%s]%s[/color]\n" % [rank_color, rank, personality_color, personality]
	text += "  技能 %.0f%%  抗压 %.0f%%  专注 %.0f%%  自保 %.0f%%\n" % [skill * 100, comp * 100, fc * 100, sp * 100]
	if sp > ctrl.self_preservation + 0.05:
		text += "  [color=#cc8844](自保基线 %.0f%% → 压力推升至 %.0f%%)[/color]\n" % [ctrl.self_preservation * 100, sp * 100]
	text += "  精神 [color=%s]%s[/color] %s  有效 %.0f%%\n" % [mental_color, mental, bar_str, eff * 100]
	return text

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
				if child.params.secondary_missile:
					child.secondary_missiles_remaining = child.params.secondary_missile.max_count
				if child.params.flare:
					child.flares_remaining = child.params.flare.max_flares

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
	# 启用战斗AI：主动锁定攻击 + 导弹规避
	ai.enable_combat = true
	ai.evade_missiles = true
	ai.aggression = randf_range(0.4, 0.8)
	ai.engage_cooldown = 12.0
	ai.engage_duration = 25.0
	# 随机化飞行员能力和性格
	ai.skill_level = randf_range(0.4, 0.85)
	ai.composure = randf_range(0.3, 0.75)
	ai.focus = randf_range(0.3, 0.9)
	ai.self_preservation = randf_range(0.2, 0.8)
	enemy.add_child(ai)

func _on_spawn_probe() -> void:
	var main := get_parent()
	if not main:
		return

	var player_pos := Vector2.ZERO
	for child in main.get_children():
		if child is Aircraft and child.team == 0 and not child.is_destroyed:
			player_pos = child.global_position
			break

	var angle := randf() * TAU
	var spawn_pos := player_pos + Vector2(cos(angle), sin(angle)) * SPAWN_DISTANCE

	var drone: Aircraft = _enemy_scene.instantiate()
	drone.params = _drone_params
	drone.team = 1
	drone.position = spawn_pos
	# 随机朝向
	drone.initial_heading_deg = randf() * 360.0

	main.add_child(drone)

	# 注入 manager（虽然 Probe 没武器，但 BulletManager 需要它在列表中用于被命中检测）
	for child in main.get_children():
		if child is BulletManager:
			drone.bullet_manager = child
		elif child is MissileManager:
			drone.missile_manager = child

	# 简单直线巡逻：长距离两点来回
	var ai := AIController.new()
	ai.name = "AI_%s" % drone.name
	ai.aircraft = drone
	ai.patrol_altitude = randf_range(3000.0, 5000.0)
	var fwd := Vector2(cos(angle + PI), sin(angle + PI))  # 大致朝玩家飞
	ai.waypoints = PackedVector2Array([
		spawn_pos,
		spawn_pos + fwd * 6000.0,
	])
	ai.enable_combat = false
	ai.evade_missiles = false
	drone.add_child(ai)

func _on_spawn_squad_4() -> void:
	var main := get_parent()
	if main and main.has_method("_spawn_friendly_squad"):
		main._spawn_friendly_squad(4)

func _on_spawn_squad_2() -> void:
	var main := get_parent()
	if main and main.has_method("_spawn_friendly_squad"):
		main._spawn_friendly_squad(2)

func _on_spawn_enemies_2() -> void:
	var main := get_parent()
	if main and main.has_method("_spawn_enemies"):
		main._spawn_enemies(2)

func _on_spawn_enemies_4() -> void:
	var main := get_parent()
	if main and main.has_method("_spawn_enemies"):
		main._spawn_enemies(4)

func _on_cycle_formation() -> void:
	var main := get_parent()
	if main and main.has_method("_cycle_formation"):
		main._cycle_formation()

func _on_spawn_ally() -> void:
	var main := get_parent()
	if not main:
		return

	var player_pos := Vector2.ZERO
	for child in main.get_children():
		if child is Aircraft and child.team == 0 and not child.is_destroyed:
			player_pos = child.global_position
			break

	# 在玩家附近生成
	var angle := randf() * TAU
	var spawn_pos := player_pos + Vector2(cos(angle), sin(angle)) * 300.0

	var ally: Aircraft = _enemy_scene.instantiate()
	ally.params = _ally_params
	ally.team = 0
	ally.position = spawn_pos
	ally.initial_heading_deg = randf() * 360.0

	main.add_child(ally)

	for child in main.get_children():
		if child is BulletManager:
			ally.bullet_manager = child
		elif child is MissileManager:
			ally.missile_manager = child

	# 友军AI：巡逻 + 主动交战 + 规避导弹
	var ai := AIController.new()
	ai.name = "AI_%s" % ally.name
	ai.aircraft = ally
	ai.patrol_altitude = randf_range(4000.0, 7000.0)
	ai.waypoints = PackedVector2Array([
		player_pos + Vector2(600, -600),
		player_pos + Vector2(600, 600),
		player_pos + Vector2(-600, 600),
		player_pos + Vector2(-600, -600),
	])
	ai.enable_combat = true
	ai.evade_missiles = true
	ai.aggression = 0.7
	ai.engage_cooldown = 10.0
	ai.engage_duration = 25.0
	# 友军飞行员能力稍高
	ai.skill_level = randf_range(0.6, 0.9)
	ai.composure = randf_range(0.5, 0.8)
	ai.focus = randf_range(0.5, 0.85)
	ai.self_preservation = randf_range(0.4, 0.7)
	ally.add_child(ai)

	# 如果没有可操控的玩家飞机，接管这架友军
	var has_player := false
	if main.has_method("_screen_to_world"):
		for ac in main.selected_aircraft:
			if is_instance_valid(ac) and not ac.is_destroyed:
				has_player = true
				break
		if not has_player:
			ally.selected = true
			main.selected_aircraft.append(ally)
			ai.queue_free()

# ══════════════════════════════════════════════
#  地面单位生成
# ══════════════════════════════════════════════

func _get_player_pos() -> Vector2:
	var main := get_parent()
	if not main:
		return Vector2.ZERO
	for child in main.get_children():
		if child is Aircraft and child.team == 0 and not child.is_destroyed:
			return child.global_position
	return Vector2.ZERO

func _inject_managers(unit: GroundUnit) -> void:
	var main := get_parent()
	if not main:
		return
	for child in main.get_children():
		if child is BulletManager:
			unit.bullet_manager = child
		elif child is MissileManager:
			unit.missile_manager = child

func _spawn_ground_unit(scene: PackedScene, params_res: Resource, team_id: int, distance: float = 800.0) -> void:
	var main := get_parent()
	if not main:
		return
	var player_pos := _get_player_pos()
	var angle := randf() * TAU
	var spawn_pos := player_pos + Vector2(cos(angle), sin(angle)) * distance
	var unit: GroundUnit = scene.instantiate()
	unit.params = params_res
	unit.team = team_id
	unit.position = spawn_pos
	# 朝向玩家
	var to_player := (player_pos - spawn_pos).normalized()
	unit.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))
	main.add_child(unit)
	_inject_managers(unit)

func _on_spawn_enemy_sam() -> void:
	_spawn_ground_unit(_sam_scene, _sam_params, 1, 1500.0)

func _on_spawn_friendly_sam() -> void:
	_spawn_ground_unit(_sam_scene, _sam_params, 0, 500.0)

func _on_spawn_enemy_aa() -> void:
	_spawn_ground_unit(_aa_scene, _aa_params, 1, 800.0)

func _on_spawn_friendly_aa() -> void:
	_spawn_ground_unit(_aa_scene, _aa_params, 0, 300.0)

func _on_spawn_enemy_radar() -> void:
	_spawn_ground_unit(_radar_scene, _radar_params, 1, 2000.0)

func _on_spawn_friendly_radar() -> void:
	_spawn_ground_unit(_radar_scene, _radar_params, 0, 600.0)
