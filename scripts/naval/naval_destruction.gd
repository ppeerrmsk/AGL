class_name NavalDestruction
extends RefCounted

## 船只击毁动画系统（静态工具类 —— 仿 AircraftDestruction 模式）
##
## 四阶段（plan §2）：
##   A (0.0 ~ 1.5s) 连环爆炸：沿船身随机位置 spawn 6 次爆炸特效
##   B (0.5 ~ 2.0s) 白色方块碎片：22 个方块从船心向外喷射 + 重力下坠
##   C (2.0 ~ 5.0s) 沉没：alpha 淡出 + 船体缩小 + 水波圆环扩散
##   D (5.0s+) queue_free
##
## 所有运行时状态（timer / debris 列表 / 水波列表）住在 NavalUnit，本类只做静态推进 + 绘制

const TOTAL_DURATION: float = 5.0

const STAGE_A_DURATION: float = 1.5
const EXPLOSION_COUNT: int = 6
const EXPLOSION_INTERVAL: float = STAGE_A_DURATION / EXPLOSION_COUNT  # ~0.25s

const STAGE_B_START: float = 0.5

const STAGE_C_START: float = 2.0
const STAGE_C_DURATION: float = 3.0   # end at 5.0s

const DEBRIS_COUNT: int = 22
const DEBRIS_MIN_SPEED: float = 80.0
const DEBRIS_MAX_SPEED: float = 150.0
const DEBRIS_GRAVITY: float = 120.0   # px/s² 向下拉
const DEBRIS_MIN_SIZE: float = 3.0
const DEBRIS_MAX_SIZE: float = 6.0
const DEBRIS_LIFE: float = 2.0
const DEBRIS_FADE_START: float = 1.0  # 剩余寿命 < 此值才开始淡出

const RIPPLE_INTERVAL: float = 0.8
const RIPPLE_LIFE: float = 2.2
const RIPPLE_MAX_RADIUS: float = 180.0
const RIPPLE_COLOR: Color = Color(0.65, 0.85, 1.0, 0.55)

const SINK_SHRINK_FACTOR: float = 0.4  # 最终缩小到 60%


## 开始击毁动画 —— 由 NavalUnit._start_destruction 调用
static func start(nu: NavalUnit) -> void:
	EventLogger.log_event("NAVAL", "Destroy",
		"%s sinking (hull=%.0f/%.0f)" % [nu.full_name, nu.hull_hp, nu.hull_hp_max])
	nu._destroy_timer = TOTAL_DURATION
	nu._destroy_explosion_index = 0
	nu._destroy_explosion_cooldown = 0.0
	nu._destroy_debris = []
	nu._destroy_ripples = []
	nu._destroy_ripple_accum = 0.0


## 每帧推进 —— 由 NavalUnit._update_destroy 调用
## 返回 true 表示动画已结束（调用方应 queue_free）
static func update(nu: NavalUnit, delta: float) -> bool:
	nu._destroy_timer = maxf(nu._destroy_timer - delta, 0.0)
	var elapsed: float = TOTAL_DURATION - nu._destroy_timer

	# Stage A：连环爆炸
	if elapsed < STAGE_A_DURATION and nu._destroy_explosion_index < EXPLOSION_COUNT:
		nu._destroy_explosion_cooldown -= delta
		if nu._destroy_explosion_cooldown <= 0.0:
			_spawn_explosion(nu)
			nu._destroy_explosion_index += 1
			nu._destroy_explosion_cooldown = EXPLOSION_INTERVAL * randf_range(0.6, 1.4)

	# Stage B：碎片一次性生成，然后物理更新（生成时机 = Stage B 开始）
	if elapsed >= STAGE_B_START and nu._destroy_debris.is_empty():
		_spawn_debris(nu)
	# 推进碎片
	for d in nu._destroy_debris:
		d["life"] -= delta
		if d["life"] <= 0.0:
			continue
		d["vel"].y += DEBRIS_GRAVITY * delta
		d["pos"] += d["vel"] * delta

	# Stage C：沉没（alpha 淡出 + scale 收缩 + 水波）
	if elapsed >= STAGE_C_START:
		var sink_t: float = clampf((elapsed - STAGE_C_START) / STAGE_C_DURATION, 0.0, 1.0)
		nu.modulate = Color(1.0, 1.0, 1.0, 1.0 - sink_t)
		var sf: float = 1.0 - sink_t * SINK_SHRINK_FACTOR
		nu.scale = Vector2(sf, sf)

		# 水波累加生成
		nu._destroy_ripple_accum += delta
		if nu._destroy_ripple_accum >= RIPPLE_INTERVAL:
			nu._destroy_ripple_accum = 0.0
			nu._destroy_ripples.append({"life": RIPPLE_LIFE})
		# 水波推进
		for r in nu._destroy_ripples:
			r["life"] -= delta

	return nu._destroy_timer <= 0.0


## 绘制阶段 —— 由 NavalUnit._draw 在击毁状态下调用
## 本地坐标系，与 NavalUnit._draw 一致
static func draw(nu: NavalUnit) -> void:
	# 水波：同心圆淡出（抵消船体 rotation，让圆保持"水平"）
	for r in nu._destroy_ripples:
		var life_t: float = 1.0 - r["life"] / RIPPLE_LIFE  # 0=刚诞生, 1=消失
		if life_t < 0.0 or life_t > 1.0:
			continue
		var radius: float = life_t * RIPPLE_MAX_RADIUS
		var alpha: float = (1.0 - life_t) * RIPPLE_COLOR.a
		var color: Color = Color(RIPPLE_COLOR.r, RIPPLE_COLOR.g, RIPPLE_COLOR.b, alpha)
		_draw_ring(nu, Vector2.ZERO, radius, color, 24)

	# 碎片：白色小方块（本地坐标）
	for d in nu._destroy_debris:
		if d["life"] <= 0.0:
			continue
		var fade: float = clampf(d["life"] / DEBRIS_FADE_START, 0.0, 1.0)
		var c: Color = Color(1.0, 1.0, 1.0, fade)
		var size: float = d["size"]
		nu.draw_rect(
			Rect2(d["pos"] - Vector2(size * 0.5, size * 0.5), Vector2(size, size)),
			c
		)


# ══════════════════════════════════════════════
#  内部辅助
# ══════════════════════════════════════════════

## 沿船身随机位置 spawn 一个爆炸特效
static func _spawn_explosion(nu: NavalUnit) -> void:
	if nu.params == null:
		return
	var tree := nu.get_tree()
	if tree == null:
		return
	var forward: Vector2 = Vector2(sin(nu.heading), -cos(nu.heading))
	var starboard: Vector2 = Vector2(cos(nu.heading), sin(nu.heading))
	var x_off: float = randf_range(-nu.params.hull_length * 0.4, nu.params.hull_length * 0.4)
	var y_off: float = randf_range(-nu.params.hull_width * 0.3, nu.params.hull_width * 0.3)
	var pos: Vector2 = nu.global_position + forward * x_off + starboard * y_off
	ExplosionVFX.emit(tree, pos, nu.heading, randf_range(0.7, 1.2))

## 一次性生成 DEBRIS_COUNT 个碎片（本地坐标系，从船中心向外）
static func _spawn_debris(nu: NavalUnit) -> void:
	for i in range(DEBRIS_COUNT):
		var angle: float = randf() * TAU
		var speed: float = randf_range(DEBRIS_MIN_SPEED, DEBRIS_MAX_SPEED)
		nu._destroy_debris.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"size": randf_range(DEBRIS_MIN_SIZE, DEBRIS_MAX_SIZE),
			"life": DEBRIS_LIFE,
		})

## 虚线圆（简化版：实线）—— 本地坐标
static func _draw_ring(nu: Node2D, center: Vector2, radius: float, color: Color, segments: int) -> void:
	if radius < 1.0:
		return
	# 抵消船体 rotation，保证水波是屏幕正圆而非跟船头旋转
	var inv_rot: float = -nu.rotation
	for i in range(segments):
		var a0: float = float(i) / segments * TAU
		var a1: float = float(i + 1) / segments * TAU
		var p0: Vector2 = center + Vector2(cos(a0), sin(a0)).rotated(inv_rot) * radius
		var p1: Vector2 = center + Vector2(cos(a1), sin(a1)).rotated(inv_rot) * radius
		nu.draw_line(p0, p1, color, 1.5)
