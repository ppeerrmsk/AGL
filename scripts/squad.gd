class_name Squad
extends RefCounted

## 编队数据结构与阵型计算

enum Formation { COMBAT_SPREAD, WEDGE, ECHELON, TRAIL, FINGER_FOUR, FLUID_FOUR }

## 阵型名称使用翻译 key；get_formation_name() 会返回 tr() 后的显示字符串
const FORMATION_NAMES := {
	Formation.COMBAT_SPREAD: "FORMATION_COMBAT_SPREAD",
	Formation.WEDGE: "FORMATION_WEDGE",
	Formation.ECHELON: "FORMATION_ECHELON",
	Formation.TRAIL: "FORMATION_TRAIL",
	Formation.FINGER_FOUR: "FORMATION_FINGER_FOUR",
	Formation.FLUID_FOUR: "FORMATION_FLUID_FOUR",
}

const PIXELS_PER_METER: float = 0.5

var leader: Aircraft = null
var members: Array[Aircraft] = []
var formation: Formation = Formation.FINGER_FOUR
var base_spacing_m: float = 300.0  ## 基础间距（米）≈150像素，现实约200-500m

## 添加成员
func add_member(ac: Aircraft) -> void:
	if ac not in members:
		members.append(ac)

## 移除成员
func remove_member(ac: Aircraft) -> void:
	members.erase(ac)
	if ac == leader and members.size() > 0:
		leader = members[0]
		_sync_leader_squad_index(leader)

## 清理无效成员
func cleanup() -> void:
	var valid: Array[Aircraft] = []
	for ac in members:
		if is_instance_valid(ac) and not ac.is_destroyed:
			valid.append(ac)
	members = valid
	if leader and (not is_instance_valid(leader) or leader.is_destroyed):
		leader = members[0] if members.size() > 0 else null
		if leader:
			_sync_leader_squad_index(leader)

## 晋升长机后，同步其 AIController.squad_index 到 0
## 防止原僚机带着旧 index (1/2/3) 进入 SQUAD_FOLLOW 时，
## get_wingman_target 计算出相对于自身的 slot → 飞机追自己尾巴原地自转
static func _sync_leader_squad_index(ac: Aircraft) -> void:
	if not ac:
		return
	for child in ac.get_children():
		if child is AIController:
			(child as AIController).squad_index = 0
			return

## 获取成员在编队中的序号（0=长机）
func get_index(ac: Aircraft) -> int:
	return members.find(ac)

## 计算阵型偏移（像素坐标，相对长机本地空间，0=正前方）
## index: 成员序号（0=长机，无偏移）
func get_formation_offset(index: int) -> Vector2:
	if index <= 0:
		return Vector2.ZERO

	var s := base_spacing_m * PIXELS_PER_METER  # 基础间距像素

	## 坐标系：X=右侧, Y=后方（+Y = 飞机正后方）
	match formation:
		Formation.COMBAT_SPREAD:
			# 战斗展开（Line Abreast）：并排，大间距，微后错
			# 现实中约1nm(1852m)间距，游戏中缩短以可视
			# #1右侧, #2左侧, #3右远, #4左远；各自微后错
			var side := 1.0 if index % 2 == 1 else -1.0
			var rank := ceili(float(index) / 2.0)
			return Vector2(side * s * 1.2 * rank, s * 0.15 * rank)

		Formation.WEDGE:
			# 楔形/战斗翼（Fighting Wing）：僚机在后方30-60°位置
			# #1右后45°, #2左后45°, #3右后更远, #4左后更远
			var side := 1.0 if index % 2 == 1 else -1.0
			var rank := ceili(float(index) / 2.0)
			return Vector2(side * s * 0.7 * rank, s * 0.7 * rank)

		Formation.ECHELON:
			# 右梯形：所有僚机在长机右后方阶梯排列
			# 现实中用于单侧转弯或展示飞行
			return Vector2(s * 0.5 * index, s * 0.6 * index)

		Formation.TRAIL:
			# 纵列：正后方，间距约1nm
			return Vector2(0, s * index)

		Formation.FINGER_FOUR:
			# 指尖四点（Finger Four / Schwarm）：
			# 俯视似右手四指指尖，不对称阵型
			# Lead=食指, #1=中指(左后), #2=无名指(右后), #3=小指(右后远)
			# 间距约200-400m，有前后错开
			match index:
				1: return Vector2(-s * 0.6, s * 0.4)    # 左后（中指）
				2: return Vector2(s * 0.8, s * 0.3)     # 右后（无名指）
				3: return Vector2(s * 1.4, s * 0.7)     # 右后远（小指）
				_:
					# 超过4机，额外成员排在后方
					var extra := index - 3
					var side := 1.0 if extra % 2 == 1 else -1.0
					return Vector2(side * s * 0.5 * extra, s * (1.0 + 0.5 * extra))

		Formation.FLUID_FOUR:
			# 流体四机（Fluid Four）：两对战斗翼编队的展开
			# 长机对: Lead + #1(左后45°)
			# 僚机对: #2(右前方平行) + #3(#2的左后45°)
			match index:
				1: return Vector2(-s * 0.6, s * 0.6)    # 长机僚机，左后
				2: return Vector2(s * 1.5, s * 0.1)     # 二号长机，右侧平行
				3: return Vector2(s * 0.9, s * 0.7)     # 二号僚机，二号长机左后
				_:
					var extra := index - 3
					var side := 1.0 if extra % 2 == 0 else -1.0
					return Vector2(side * s * (1.0 + 0.4 * extra), s * (1.0 + 0.4 * extra))

	return Vector2.ZERO

## 计算僚机的世界坐标目标点
func get_wingman_target(index: int) -> Vector2:
	if not leader or not is_instance_valid(leader):
		return Vector2.INF

	var offset := get_formation_offset(index)
	# 按长机航向旋转偏移（heading: 0=北=屏幕上方）
	var rotated := offset.rotated(leader.heading)
	return leader.global_position + rotated

## 获取阵型名称（已 tr() 翻译）
func get_formation_name() -> String:
	var key: String = FORMATION_NAMES.get(formation, "FORMATION_UNKNOWN")
	return TranslationServer.translate(key)

## 切换到下一个阵型
func cycle_formation() -> void:
	var all := [Formation.COMBAT_SPREAD, Formation.WEDGE, Formation.ECHELON, Formation.TRAIL, Formation.FINGER_FOUR, Formation.FLUID_FOUR]
	var idx := all.find(formation)
	formation = all[(idx + 1) % all.size()]
