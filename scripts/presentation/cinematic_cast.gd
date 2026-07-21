class_name CinematicCast
extends RefCounted

## 演出班底：演员走位 / 尾迹覆写 / 隐身（spec ui-transition §2.9~§2.11）
##
## ⚠ 所有走位【只下发航路点】，飞行交给既有物理与转弯控制器。
##    禁止逐帧写 global_position 或预烘焙曲线 —— 俯视全程可见，K 帧出来的轨迹与
##    机身坡度/速度/盘旋半径对不上，跟旁边正常飞的飞机一比立刻穿帮。
##
## ⚠ 指令一律经 owner（GameEvent）下发，复用其 owner_event 弱引用 + clear_all_directives
##    兜底。绝不自建第二套所有权 —— 漏清理 = BOSS 永远停在免战脚本模式且不报错。

const TRAIL_BOOST_POINTS := 240   ## 演出尾迹点数（常规 80 = 仅 4s，画不出长线交汇）
const TRAIL_BOOST_WIDTH := 14.0   ## 演出尾迹宽度（常规 8.0 在广角下只剩 4 屏幕像素）
const TRAIL_BASE_POINTS := 80
const TRAIL_BASE_WIDTH := 8.0

var actors: Array = []            ## Array[Aircraft]
var owner_event = null            ## GameEvent，指令下发的所有权持有者
var _trail_boosted: bool = false
var _ingress_started: bool = false
var _converge_started: bool = false
var _scattered: bool = false

func bind(p_actors: Array, p_owner) -> void:
	actors = p_actors.duplicate()
	owner_event = p_owner
	_trail_boosted = false
	_ingress_started = false
	_converge_started = false
	_scattered = false
	_meet_started.clear()
	_meet_started.clear()

func is_bound() -> bool:
	return owner_event != null and not actors.is_empty()

func alive_actors() -> Array:
	var out: Array = []
	for a in actors:
		if is_instance_valid(a) and not a.is_destroyed:
			out.append(a)
	return out


# ══════════════════════════════════════════════
#  尾迹覆写（§2.11）
# ══════════════════════════════════════════════

## 拉长加粗演员尾迹。分镜第三格"飞机没了、线还在"全靠它撑。
## 只作用于 4 名演员且世界已暂停，240 点完全安全；但 release 必须还原，
## 绝不能把 240 泄漏给常规战斗（那是当初 300→80 性能优化的原因）
func trail_boost() -> void:
	if _trail_boosted:
		return
	_trail_boosted = true
	for a in actors:
		var t = _trail_of(a)
		if t:
			t.max_points = TRAIL_BOOST_POINTS
			t.ribbon_width = TRAIL_BOOST_WIDTH

func trail_fade(t: float) -> void:
	var a_val: float = 1.0 - clampf(t, 0.0, 1.0)
	for a in actors:
		var tr = _trail_of(a)
		if tr:
			tr.modulate.a = a_val

func trail_restore() -> void:
	if not _trail_boosted:
		return
	_trail_boosted = false
	for a in actors:
		var t = _trail_of(a)
		if t:
			t.max_points = TRAIL_BASE_POINTS
			t.ribbon_width = TRAIL_BASE_WIDTH
			t.modulate.a = 1.0

func _trail_of(a) -> TrailRibbon:
	if not is_instance_valid(a):
		return null
	return a.get("_trail_ribbon") as TrailRibbon


# ══════════════════════════════════════════════
#  第一幕：梯队平飞进场（§2.9）
# ══════════════════════════════════════════════

## offsets 为编队相对偏移（沿 inbound 旋转），alt_step 为逐机高度分层。
## 高度分层的作用：交汇时四机不同高度 → 图标缩放不同，既避免糊成一团，
## 也让"四条线交于一点"在物理上说得通
## ⚠ 进场距离必须与飞机真实速度匹配。PIXELS_PER_METER = 0.5 下，1600 km/h ≈ 222 px/s，
##   3.3 秒的进场段只能走约 730px。早期版本写了 5200px —— 那需要 41 秒才飞得完，
##   演出结束时飞机还在画面外。空间尺度必须从"速度 × 可见时长"反推，不能凭感觉给大数
func echelon_ingress(anchor: Vector2, inbound: Vector2, offsets: Array,
		alt_step: float, speed_kmh: float, ingress_dist: float) -> void:
	if _ingress_started or owner_event == null:
		return
	_ingress_started = true
	var live := alive_actors()
	var basis := inbound.normalized()
	var perp := Vector2(-basis.y, basis.x)
	for i in range(live.size()):
		var a = live[i]
		var off: Vector2 = Vector2.ZERO
		if i < offsets.size():
			var o = offsets[i]
			off = basis * float(o[0]) + perp * float(o[1])
		var start := anchor + basis * ingress_dist + off
		a.global_position = start
		# ⚠ 机头朝【飞行方向】：起点在锚点更远侧（anchor + basis*dist），飞向锚点，
		#   行进方向 = -basis。首版写成 +basis —— 四机背对目标出生，开场就地掉头 180°，
		#   梯队平飞直接毁掉（heading 约定：0=北，direction d 的 heading = d.angle()+PI/2）
		a.heading = (-basis).angle() + PI * 0.5
		a.altitude += alt_step * i
		# 传送后必须清尾迹 —— 否则丝带会把"远端出生点→演出起点"连成一条横贯地图的巨线
		var trb := _trail_of(a)
		if trb:
			trb.clear_trail()
		# 起手全透明，由 tick_ingress_fade 逐机错开淡入（复用 Poltergeist 的 FADING 模式）
		a._cloak_alpha = 0.0
		var d := AIDirective.follow_path(PackedVector2Array([anchor + off]), false)
		d.combat_disabled = true
		d.params["target_speed"] = speed_kmh
		owner_event.set_directive(a, d)

## 逐机错开淡入。elapsed 为 echelon_ingress 起始后的秒数（由序列的 step 进度换算）
func tick_ingress_fade(elapsed: float, stagger: float, fade_dur: float) -> void:
	var live := alive_actors()
	for i in range(live.size()):
		var local: float = clampf((elapsed - stagger * i) / maxf(fade_dur, 0.01), 0.0, 1.0)
		live[i]._cloak_alpha = local


# ══════════════════════════════════════════════
#  第二幕：交汇与散开（§2.10）
# ══════════════════════════════════════════════

## 四机同时抵达交汇点 CP。
## ⚠ 速度必须【按各自距离反解】而不是给同一个速度 —— 梯队最后一架距 CP 比长机远约
##    1000px，同速会让四条线依次穿过而不是同时汇于一点，分镜效果全失
func converge(cp: Vector2, dur_sec: float, arrive_radius: float) -> void:
	if _converge_started or owner_event == null:
		return
	_converge_started = true
	for a in alive_actors():
		var dist: float = a.global_position.distance_to(cp)
		# px → km/h：PIXELS_PER_METER=0.5，故 px/s ÷ 0.5 = m/s，再 ×3.6
		var need_kmh: float = (dist / maxf(dur_sec, 0.01)) / CombatUnit.PIXELS_PER_METER * 3.6
		# 钳到机体真实上限。会被钳说明几何超出了包线 —— 那时四机无法同时抵达，
		# 交汇会退化成"依次穿过"，是设计错误而非运行时容错，故留 warning
		var cap: float = a.params.max_speed if a.params else 2800.0
		if need_kmh > cap:
			push_warning("Cinematic converge: 需要 %.0f km/h 超出机体上限 %.0f —— 交汇几何过大" % [need_kmh, cap])
			need_kmh = cap
		var d := AIDirective.follow_path(PackedVector2Array([cp]), false)
		d.combat_disabled = true
		d.params["target_speed"] = need_kmh
		d.params["arrive_radius"] = arrive_radius
		owner_event.set_directive(a, d)

## 交汇即隐身（用户分镜 v2）：每架僚机贴上长机（radius 内）的瞬间各自开始淡出，
## 长机在第一架僚机贴上时一同淡出；跨度尾段对未触发者强制淡出兜底（物理抖动可能差几十px）。
## elapsed/span 均为 step 内秒数 —— 用进度换算而非 dt 累加，打断/超时下仍确定
var _meet_started: Dictionary = {}   ## instance_id → 触发时刻

func cloak_on_meet(elapsed: float, span: float, radius: float, fade: float) -> void:
	var live := alive_actors()
	if live.is_empty():
		return
	var lead = live[0]
	var force_at: float = span - fade - 0.05
	for i in range(live.size()):
		var a = live[i]
		var key: int = a.get_instance_id()
		if not _meet_started.has(key):
			var met: bool = elapsed >= force_at
			if not met:
				if i == 0:
					for j in range(1, live.size()):
						if live[j].global_position.distance_to(lead.global_position) < radius:
							met = true
							break
				else:
					met = a.global_position.distance_to(lead.global_position) < radius
			if met:
				_meet_started[key] = elapsed
		if _meet_started.has(key):
			var pr: float = clampf((elapsed - float(_meet_started[key])) / maxf(fade, 0.01), 0.0, 1.0)
			a._cloak_alpha = 1.0 - pr
			a.queue_redraw()

## 集体隐身淡出 —— 【演出专属视觉】（用户裁定 2026-07-20，推翻 spec v3~v9 的"真隐身"方案）。
## 只借隐身的视觉语言，绝不碰 AceSquad 的隐身状态机：`_cloak_enter()` 会置
## `_cloak_in_state = true`，而 PRE_STAGE 下小队状态机休眠、`_cloak_remaining` 永不倒数
## —— 实测四机【永久隐身】，玩家满地图找不到 BOSS。
## release() 时解除全部视觉状态；真隐身仍由战斗中的 110s±jitter 循环自行触发。
func cloak_vanish(t: float) -> void:
	var p: float = clampf(t, 0.0, 1.0)
	for a in alive_actors():
		a._cloak_alpha = 1.0 - p

## 散开：以 away_dir（背向玩家 = inbound）为中心的 fan_deg 扇面。
## ⚠ 不许四向均布 —— 探针实锤：必有一架朝玩家散开、贴脸触发 ENGAGED，
## 演出刚结束就误开战 + engage 摆位造成肉眼可见的瞬移。全员往战区深处包抄
func scatter(cp: Vector2, away_dir: Vector2, fan_deg: float, dist: float) -> void:
	if _scattered or owner_event == null:
		return
	_scattered = true
	var live := alive_actors()
	var center: float = away_dir.angle()
	var half: float = deg_to_rad(fan_deg) * 0.5
	for i in range(live.size()):
		var frac: float = 0.5 if live.size() <= 1 else float(i) / float(live.size() - 1)
		var ang: float = center + lerpf(-half, half, frac)
		var target := cp + Vector2(cos(ang), sin(ang)) * dist
		var d := AIDirective.follow_path(PackedVector2Array([target]), false)
		d.combat_disabled = true
		# 回巡航速：converge 反解的高速（远机 2463 + 加力）不能带出演出 ——
		# 演出后小队状态机可能休眠（PRE_STAGE），没人替它把加力关掉
		d.params["target_speed"] = live[i].params.cruise_speed if live[i].params else 900.0
		owner_event.set_directive(live[i], d)

## 释放全部演员指令 + 还原尾迹 + 解除演出隐身。演出结束 / 超时收尾 / clear_all 都必调
func release() -> void:
	trail_restore()
	# 演出隐身只活在演出里：剧情结束当帧解除（用户裁定）。
	# 三个字段一起复位 —— 只复位 alpha 会留下隐身副作用的尾巴
	for a in alive_actors():
		a._cloak_alpha = 1.0
		a.is_cloaked = false
		a.suppress_flares = false
	if owner_event and owner_event.has_method("clear_all_directives"):
		owner_event.clear_all_directives()
	actors.clear()
	owner_event = null
	_ingress_started = false
	_converge_started = false
	_scattered = false
