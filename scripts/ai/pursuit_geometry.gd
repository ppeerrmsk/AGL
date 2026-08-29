class_name PursuitGeometry extends RefCounted

## AI 追击点的无状态几何工具。只接收数值快照，不读取 Aircraft / Node / 全局状态。


static func forward_vector(heading: float) -> Vector2:
	return Vector2(sin(heading), -cos(heading))


## 按给定预测窗把目标沿当前速度外推。
static func lead_point(
		target_pos: Vector2, target_heading: float, target_speed_ms: float,
		prediction_s: float, lead_factor: float = 1.0) -> Vector2:
	return lead_point_from_forward(
		target_pos, forward_vector(target_heading), target_speed_ms, prediction_s, lead_factor)


static func lead_point_from_forward(
		target_pos: Vector2, target_forward: Vector2, target_speed_ms: float,
		prediction_s: float, lead_factor: float = 1.0) -> Vector2:
	return target_pos + target_forward \
			* (target_speed_ms * CombatUnit.PIXELS_PER_METER * prediction_s * lead_factor)


## 用闭合速度估算预测窗；max_prediction_s < 0 表示不封顶。
static func closing_time_lead_point(
		my_pos: Vector2, target_pos: Vector2, target_heading: float, target_speed_ms: float,
		closing_speed_ms: float, lead_factor: float = 1.0,
		max_prediction_s: float = -1.0) -> Vector2:
	var dist_px := my_pos.distance_to(target_pos)
	var prediction_s := dist_px \
			/ maxf(closing_speed_ms * CombatUnit.PIXELS_PER_METER, 1.0)
	if max_prediction_s >= 0.0:
		prediction_s = minf(prediction_s, max_prediction_s)
	return lead_point(
		target_pos, target_heading, target_speed_ms, prediction_s, lead_factor)


## 机炮两轮飞行时间迭代；与正式扳机使用同一真实初速输入。
static func projectile_lead_point(
		my_pos: Vector2, target_pos: Vector2, target_forward: Vector2, target_speed_ms: float,
		projectile_speed_ms: float) -> Vector2:
	var projectile_speed_px := maxf(
		projectile_speed_ms * CombatUnit.PIXELS_PER_METER, 100.0)
	var prediction_s := my_pos.distance_to(target_pos) / projectile_speed_px
	var first_lead := lead_point_from_forward(
		target_pos, target_forward, target_speed_ms, prediction_s)
	prediction_s = my_pos.distance_to(first_lead) / projectile_speed_px
	return lead_point_from_forward(
		target_pos, target_forward, target_speed_ms, prediction_s)
