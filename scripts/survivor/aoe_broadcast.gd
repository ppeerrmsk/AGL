class_name AOEBroadcast
extends RefCounted

## §1.3 AOE 状态广播工具：单次扫描全场战斗单位，把状态批量施加给落在指定半径内的目标。
##
## 设计原则（性能守则）：
##   - 仅遍历 CombatUnit.all_units（基类静态列表，~25 单位），不调 get_tree().get_nodes_in_group
##   - 用距离平方比较避免 sqrt
##   - 命中后调用 apply_status，复用 StatusEffects 现有的 max() 合并语义（同 id 取更长持续时间）
##   - is_instance_valid 守卫，防止 victim 死亡当帧扫描时已 freed
##
## 性能（实测预算）：3km 半径 × 25 单位 ≈ 25 次距离平方 + dict 写入 < 10μs / 触发。
## 调用频率假设：低频（击杀触发 / 玩家释放 flare / 导弹爆炸时）—— 不要拿来每帧扫。
##
## 用法：
##   AOEBroadcast.apply_status_in_radius(
##       center=victim.global_position,
##       radius_px=1500.0,           # 3km
##       team_filter=1,              # 只对敌方（1=敌, 0=友, -1=全部）
##       status_id=StatusEffects.FEAR,
##       duration=4.0,
##       source=killer_aircraft,     # 来源（用于日志归因，可为 null）
##   )

## 在以 center 为中心、radius_px 为半径的圆内，给 team_filter 阵营的所有单位施加状态
## 返回命中数（供 EventLogger / 调试用）
##
## 触发表现层：自动 spawn 一个 AOEPulseVFX（紫色圆环 + 命中目标小爆裂，1.2s 淡出）
## 颜色按 status_id 自动选择（FEAR=紫 / JAM=绿 / 默认紫）；可由 vfx_color 显式覆盖
## vfx_disabled=true 用于压力测试或后台广播（不展示视觉）
static func apply_status_in_radius(
		center: Vector2,
		radius_px: float,
		team_filter: int,
		status_id: String,
		duration: float,
		source: Node = null,
		vfx_color: Color = Color(0, 0, 0, 0),  ## 默认空，按 status 自动选色
		vfx_disabled: bool = false,
		) -> int:
	if radius_px <= 0.0 or duration <= 0.0:
		return 0
	var r_sq: float = radius_px * radius_px
	var hit_count: int = 0
	var hit_positions: Array[Vector2] = []
	# 遍历静态列表（CombatUnit.all_units），用距离平方避免 sqrt
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.is_destroyed:
			continue
		if team_filter >= 0 and u.team != team_filter:
			continue
		var d_sq: float = u.global_position.distance_squared_to(center)
		if d_sq > r_sq:
			continue
		u.apply_status(status_id, duration)
		hit_count += 1
		hit_positions.append(u.global_position)
	if hit_count > 0:
		var src_name: String = "AOE"
		if source != null and is_instance_valid(source) and source.has_method("get") and "callsign" in source:
			src_name = source.callsign
		EventLogger.log_event("AOE_STATUS", src_name,
			"%s r=%.0fpx team=%d hit=%d dur=%.1fs" % [status_id, radius_px, team_filter, hit_count, duration])
	# 表现层：即使 hit_count=0 也画范围圈，让玩家看到"我触发了，但没人在范围内"
	if not vfx_disabled:
		var color: Color = vfx_color
		if color.a <= 0.0:
			color = _color_for_status(status_id)
		var scene_root: Node = _resolve_scene_root(source)
		if scene_root:
			AOEPulseVFX.spawn(scene_root, center, radius_px, hit_positions, color)
	return hit_count


## 仅查询命中数，不施加状态（debug 预览 / 流派引导用）
static func count_targets_in_radius(
		center: Vector2,
		radius_px: float,
		team_filter: int,
		) -> int:
	if radius_px <= 0.0:
		return 0
	var r_sq: float = radius_px * radius_px
	var n: int = 0
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if team_filter >= 0 and u.team != team_filter:
			continue
		if u.global_position.distance_squared_to(center) <= r_sq:
			n += 1
	return n


## 根据 status_id 自动选 VFX 颜色
static func _color_for_status(status_id: String) -> Color:
	match status_id:
		"fear": return AOEPulseVFX.COLOR_FEAR
		"jam": return AOEPulseVFX.COLOR_JAM
		"invincible": return AOEPulseVFX.COLOR_INVUL
		_: return AOEPulseVFX.COLOR_FEAR


## 找一个挂 VFX 节点的 parent
##   优先 source.get_parent()（飞机本身的父节点 = 主场景）
##   兜底 AircraftRenderer.player_ref.get_parent()
##   都不行就放弃
static func _resolve_scene_root(source: Node) -> Node:
	if source != null and is_instance_valid(source):
		var p := source.get_parent()
		if p != null and is_instance_valid(p):
			return p
	var pref := AircraftRenderer.player_ref
	if pref != null and is_instance_valid(pref):
		var pp := pref.get_parent()
		if pp != null and is_instance_valid(pp):
			return pp
	return null
