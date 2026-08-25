class_name StrategicTarget
extends GroundUnit

## 轰炸任务专属战略硬目标：不可锁定，且只接受 bomber_bomb 伤害通道。
enum TargetKind { BUNKER, WAREHOUSE, MISSILE_SILO }

@export var target_kind: TargetKind = TargetKind.BUNKER
var bomber_escort_objective: bool = false

func _ready() -> void:
	super._ready()
	max_ground_speed = 0.0
	target_position = Vector2.INF
	set_physics_process(false) # 静态目标不占逐帧预算；被毁后才临时启用回收计时。

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()

func is_lock_immune() -> bool:
	return true

## 护送任务在 AVAILABLE 预刷阶段就必须让玩家认出目标；静态绘制，不新增 process。
func set_bomber_escort_objective(active: bool) -> void:
	bomber_escort_objective = active
	is_mission_target = active
	queue_redraw()

## 常规伤害入口只允许“仍有效且阵营敌对”的轰炸机炸弹；释放者已销毁时走下方显式 team API。
func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if kind != "bomber_bomb" or not is_instance_valid(attacker) or not (attacker is CombatUnit):
		return
	if not CombatUnit.teams_hostile((attacker as CombatUnit).team, team):
		return
	super.take_damage(amount, attacker, kind)

func take_missile_damage(_amount: float) -> void:
	pass

func take_bomber_damage(amount: float, source_team: int, attacker: Node = null) -> void:
	if is_destroyed or not CombatUnit.teams_hostile(source_team, team):
		return
	# 直接走 GroundUnit 实现，允许炸弹在轰炸机已被击落后凭 team 快照继续结算。
	super.take_damage(amount, CombatUnit.safe_attacker(attacker), "bomber_bomb")

func _start_destroy() -> void:
	super._start_destroy()
	set_physics_process(true)
	queue_redraw()

func _draw() -> void:
	if is_destroyed:
		_draw_destroyed()
		return
	var color: Color = params.icon_color if params else Color(0.75, 0.65, 0.35)
	var outline := color.darkened(0.45)
	match target_kind:
		TargetKind.BUNKER:
			draw_colored_polygon(PackedVector2Array([
				Vector2(-24, 12), Vector2(-18, -10), Vector2(-8, -18),
				Vector2(8, -18), Vector2(18, -10), Vector2(24, 12)]), color.darkened(0.25))
			draw_arc(Vector2.ZERO, 18.0, PI, TAU, 20, outline, 2.0)
			draw_rect(Rect2(-5, -4, 10, 16), outline)
		TargetKind.WAREHOUSE:
			draw_rect(Rect2(-34, -20, 68, 40), color.darkened(0.3))
			draw_polyline(PackedVector2Array([Vector2(-34, -20), Vector2(0, -31), Vector2(34, -20)]), outline, 2.0)
			for x in [-20.0, 0.0, 20.0]:
				draw_line(Vector2(x, -18), Vector2(x, 18), outline, 1.0)
		TargetKind.MISSILE_SILO:
			draw_circle(Vector2.ZERO, 24.0, color.darkened(0.35))
			draw_arc(Vector2.ZERO, 24.0, 0, TAU, 32, outline, 2.0)
			draw_line(Vector2(-17, -17), Vector2(17, 17), outline, 2.0)
			draw_line(Vector2(17, -17), Vector2(-17, 17), outline, 2.0)
	# 无锁定框，只保留任务目标括号和血量刻度。
	AircraftRenderer.draw_target_bracket(self, is_mission_target)
	AircraftRenderer.draw_status_icons(self)
	_draw_data_label()
	if bomber_escort_objective and is_mission_target:
		_draw_bomber_escort_hint()
	var hp_ratio: float = clampf(hp / maxf(params.max_hp if params else 150.0, 1.0), 0.0, 1.0)
	draw_rect(Rect2(-24, 28, 48, 3), Color(0.12, 0.12, 0.12, 0.8))
	draw_rect(Rect2(-24, 28, 48 * hp_ratio, 3), color.lightened(0.2))

func _draw_bomber_escort_hint() -> void:
	var accent := Color(1.0, 0.78, 0.18, 0.98)
	var panel := Rect2(-66.0, -84.0, 132.0, 31.0)
	draw_rect(panel, Color(0.055, 0.045, 0.018, 0.92), true)
	draw_rect(panel, accent, false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(-62.0, -69.0),
		tr("BOMBER_TARGET_WORLD_LABEL"), HORIZONTAL_ALIGNMENT_CENTER, 124.0, 13, accent)
	draw_string(ThemeDB.fallback_font, Vector2(-62.0, -57.0),
		tr("BOMBER_TARGET_WORLD_HINT"), HORIZONTAL_ALIGNMENT_CENTER, 124.0, 9,
		Color(1.0, 0.9, 0.58, 0.9))
	draw_line(Vector2(0.0, -53.0), Vector2(0.0, -44.0), accent, 1.5)
