class_name SquadFactory
extends RefCounted

## 编队生成统一入口
##
## 替代散落在 5 处的 Squad.new() + add_member 循环 + ai.squad/squad_index/_state 手写串接：
##   main.gd:_spawn_friendly_squad / _spawn_enemies
##   survivor_spawner.gd:_spawn_squad / _spawn_commander_squad / _spawn_sentinel_escort_uavs
##   survivor_mode.gd:_spawn_starting_wingmen
##
## 设计：调用方仍负责 Aircraft 实例化、参数配置、AI 性格调参、位置计算
## （这些都是各自领域逻辑）。Factory 只接管 Squad 自身的"组装"环节。
##
## 用法（典型生成循环）：
##   var sq := SquadFactory.create(Squad.Formation.FINGER_FOUR)
##   SquadFactory.register_leader(sq, leader_ac)              # leader 已实例化好
##   for i in range(1, count + 1):
##       var offset := sq.get_formation_offset(i)             # 拿槽位
##       var ac := spawn(... offset ...)                      # 调用方建机
##       SquadFactory.register_wingman(sq, ac)                # 串 AI 引用 + 切 SQUAD_FOLLOW
##
## 一行版（用于已实例化好的全部成员）：
##   SquadFactory.form_up(leader, [wing1, wing2], Squad.Formation.WEDGE)

## 创建空 Squad（仅初始化阵型/间距/交战模式，未挂任何成员）
## 调用方拿到 Squad 后用 get_formation_offset(i) 算槽位，再调 register_*。
static func create(
		formation: int = Squad.Formation.FINGER_FOUR,
		engage_mode: int = Squad.EngageMode.FREE,
		base_spacing_m: float = 300.0) -> Squad:
	var sq := Squad.new()
	sq.formation = formation
	sq.engage_mode = engage_mode
	sq.base_spacing_m = base_spacing_m
	return sq

## 注册长机：写 squad.leader、加入 members[0]、给 AIController 设 squad/squad_index=0
## 不改长机的 _state（保留巡逻 / ENGAGE 等原状态）
static func register_leader(sq: Squad, leader: Aircraft) -> void:
	if not sq or not leader:
		return
	sq.leader = leader
	if leader not in sq.members:
		sq.add_member(leader)
	_attach_ai(leader, sq, 0, false)

## 注册僚机：加入 members 末尾、给 AIController 设 squad/squad_index/(可选 _state=SQUAD_FOLLOW)
## 默认 set_state=true（普通编队跟随）；护航/绕飞型小队传 false 保留 simple_ai 等。
## 返回分配到的 squad_index（= members.size() - 1）。
static func register_wingman(sq: Squad, ac: Aircraft, set_state: bool = true) -> int:
	if not sq or not ac:
		return -1
	var was_member := ac in sq.members
	if not was_member:
		sq.add_member(ac)
	var idx := sq.members.find(ac)
	_attach_ai(ac, sq, idx, set_state)
	# 无线电 "归队" 呼叫（spec radio-chatter §3.3）：只在真正新增成员时 emit。
	# 开局建队也会走这里 —— 订阅方按开局时间过滤，本层不做业务判断。
	if not was_member and ac.callsign != "" and ac.can_speak_on_radio():
		EventLogger.wingman_joined.emit(ac.callsign, ac.team)
	return idx

## 高级一行版：把已有 Aircraft 编为一队（leader 必须已实例化，wingmen 已实例化）
## 调用方负责前序的位置摆放（参考长机航向 + sq.get_formation_offset）
static func form_up(
		leader: Aircraft,
		wingmen: Array[Aircraft],
		formation: int = Squad.Formation.FINGER_FOUR,
		engage_mode: int = Squad.EngageMode.FREE,
		base_spacing_m: float = 300.0,
		set_wingman_state: bool = true) -> Squad:
	var sq := create(formation, engage_mode, base_spacing_m)
	register_leader(sq, leader)
	for ac in wingmen:
		register_wingman(sq, ac, set_wingman_state)
	return sq

## 内部：找到 AIController 子节点，写 squad/squad_index/(可选 _state)
static func _attach_ai(ac: Aircraft, sq: Squad, idx: int, set_state: bool) -> void:
	if not ac:
		return
	for child in ac.get_children():
		if child is AIController:
			var ai := child as AIController
			ai.squad = sq
			ai.squad_index = idx
			if set_state:
				ai._state = AIController.AIState.SQUAD_FOLLOW
			return
