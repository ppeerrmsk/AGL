class_name Squad
extends Resource

## 编队数据结构与阵型计算
##
## 升 Resource（2026-05-04 重构）：原 RefCounted。改 Resource 只为以后能 .tres
## 化阵型预设和挂信号；运行时字段 leader/members 不参与序列化（持有 Aircraft Node 引用）。

signal leader_changed(new_leader: Aircraft)

enum Formation { COMBAT_SPREAD, WEDGE, ECHELON, TRAIL, FINGER_FOUR, FLUID_FOUR }

## 整队共享的交战模式：FREE = 僚机可以独立扫描；FOLLOW_LEADER = 只跟长机打。
## 原本散在每架僚机的 AIController.squad_engage_mode，现在收编到 Squad 上整队一份。
enum EngageMode { FREE = 0, FOLLOW_LEADER = 1, GUARD_REAR = 2 }  ## GUARD_REAR: 僚机只守长机后半球（见 AIController.SquadEngageMode）

## 阵型名称使用翻译 key；get_formation_name() 会返回 tr() 后的显示字符串
const FORMATION_NAMES := {
	Formation.COMBAT_SPREAD: "FORMATION_COMBAT_SPREAD",
	Formation.WEDGE: "FORMATION_WEDGE",
	Formation.ECHELON: "FORMATION_ECHELON",
	Formation.TRAIL: "FORMATION_TRAIL",
	Formation.FINGER_FOUR: "FORMATION_FINGER_FOUR",
	Formation.FLUID_FOUR: "FORMATION_FLUID_FOUR",
}

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

## 编队反应延迟与槽位变化阈值（原住 AIController，Step 5 收编到这里整队共享）
const FORMATION_SWITCH_THRESH: float = 30.0   ## 槽位 offset 变化超过此像素 → 触发反应延迟
const FORMATION_REACT_BASE: float = 0.3       ## 反应延迟基准秒
const FORMATION_JITTER_AMP: float = 0.5       ## 个体扰动振幅
const FORMATION_JITTER_ADD: float = 1.0       ## 扰动叠加上限
const WINGMAN_ENGAGE_DELAY_MIN: float = 0.3   ## 僚机协同攻击长机目标的最小反应延迟
const WINGMAN_ENGAGE_DELAY_MAX: float = 1.5

var leader: Aircraft = null
var members: Array[Aircraft] = []
@export var formation: Formation = Formation.FINGER_FOUR
@export var base_spacing_m: float = 300.0  ## 基础间距（米）≈150像素，现实约200-500m
@export var engage_mode: int = EngageMode.FREE

## 护卫学说开关（spec squad-ai-escort）：true 时本队僚机吃"护卫长机/反杀攻击者/守后半球"
## 逻辑——玩家队建队 on、F-47/Mother Goose 等精英 BOSS 队建队 on、普通杂兵队 off。
## off 时护卫评分/engaging_me 登记/守后指派全程跳过，行为与改动前完全一致。
@export var escort_doctrine_enabled: bool = false

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
		leader_changed.emit(leader)

## 显式换帅（玩家切换操控对象时调用）——只换 leader 引用 + 重排 squad_index 记账。
## ★最小扰动原则（spec squad-control-switching §3.5）：禁止遍历 members 强制设
## formation_mode / 强制状态转 SQUAD_FOLLOW。FREE 各自为战的僚机决策路径不读 leader，
## 天然隔离，切换不影响它们；只有处于归位跟随的僚机会在下一帧自然跟随新长机阵型。
## 注意：只动编队角色 squad_index，绝不碰稳定号机号 squad_slot。
func set_leader(new_leader: Aircraft) -> void:
	if new_leader == leader or new_leader not in members:
		return
	leader = new_leader
	# 重排 squad_index：new_leader=0，其余成员按原 members 顺序补 1..N
	var idx := 1
	for ac in members:
		if not is_instance_valid(ac):
			continue
		var target_index := 0 if ac == new_leader else idx
		if ac != new_leader:
			idx += 1
		for child in ac.get_children():
			if child is AIController:
				(child as AIController).squad_index = target_index
				break
	leader_changed.emit(new_leader)

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
			leader_changed.emit(leader)

## 晋升新长机后同步其 AIController.squad_index = 0（防止僚机带旧 index 进 SQUAD_FOLLOW 自转）
## TODO Step 2 起由 SquadFactory 监听 leader_changed 接管，本方法可删
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

## 交战模式 → 绑定阵型（spec squad-cohesion：战术=阵型，玩家不再手动切阵型）
## 自由=战斗展开(搜索/互看六点)；跟随长机=指尖四点(凝聚)；守护后方=楔形(僚机在后方锥内罩六点)
static func formation_for_engage_mode(mode: int) -> int:
	match mode:
		EngageMode.FREE:
			return Formation.COMBAT_SPREAD
		EngageMode.GUARD_REAR:
			return Formation.WEDGE
		_:  # FOLLOW_LEADER 及兜底
			return Formation.FINGER_FOUR

## 随机阵型（敌方杂鱼 spawn 时用）——除 Trail(纵列) 外随机一个。
## Trail 排除：互相支援差、视觉上不像"散兵杂鱼"，留作不用。精英/Boss 不走这里（建队时显式固定）。
static func random_formation() -> int:
	var pool := [Formation.COMBAT_SPREAD, Formation.WEDGE, Formation.ECHELON, Formation.FINGER_FOUR, Formation.FLUID_FOUR]
	return pool[randi() % pool.size()]

## 切换到下一个阵型（沙盒模式 main.gd / debug 仍用；生存模式已废弃手动切阵型，改由战术绑定）
func cycle_formation() -> void:
	var all := [Formation.COMBAT_SPREAD, Formation.WEDGE, Formation.ECHELON, Formation.TRAIL, Formation.FINGER_FOUR, Formation.FLUID_FOUR]
	var idx := all.find(formation)
	formation = all[(idx + 1) % all.size()]
