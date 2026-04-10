class_name GroundConvoy
extends Node

## 地面车队：一列地面单位跟随头车移动
## 头车按 waypoints 行驶，其余车辆依次跟随前车排成纵队

var leader: GroundUnit = null           ## 头车
var members: Array[GroundUnit] = []     ## 所有成员（含头车，index 0 = 头车）
var follow_distance: float = 40.0       ## 跟随间距（像素）

## 将一个地面单位加入车队（第一个加入的自动成为头车）
func add_member(unit: GroundUnit) -> void:
	if unit in members:
		return
	members.append(unit)
	if members.size() == 1:
		leader = unit
	else:
		# 跟随前一辆车
		var prev := members[members.size() - 2]
		unit.convoy_leader = prev
		unit.convoy_follow_distance = follow_distance

## 移除成员
func remove_member(unit: GroundUnit) -> void:
	var idx := members.find(unit)
	if idx == -1:
		return

	# 如果移除的不是最后一辆，后面的车要改跟前前一辆
	if idx < members.size() - 1:
		var next := members[idx + 1]
		if idx > 0:
			next.convoy_leader = members[idx - 1]
		else:
			# 移除的是头车，下一辆变成新头车
			next.convoy_leader = null

	unit.convoy_leader = null
	members.erase(unit)

	if unit == leader:
		leader = members[0] if not members.is_empty() else null

## 清理已销毁的成员
func cleanup() -> void:
	var i := members.size() - 1
	while i >= 0:
		if not is_instance_valid(members[i]) or members[i].is_destroyed:
			var removed := members[i]
			remove_member(removed)
		i -= 1

## 设置头车的航路点
func set_waypoints(wps: PackedVector2Array) -> void:
	if leader:
		leader.waypoints = wps

## 车队是否仍有效
func is_valid() -> bool:
	cleanup()
	return not members.is_empty() and leader != null
