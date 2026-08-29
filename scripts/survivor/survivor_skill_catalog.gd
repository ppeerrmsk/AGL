class_name SurvivorSkillCatalog
extends RefCounted

## 肉鸽技能目录的纯规则层。
##
## SurvivorData.UPGRADES 仍是唯一数据源；本模块只负责把总表投影为：
## - 当前构筑可进入普通随机池的候选；
## - 按三轴分组的候选；
## - 某架飞机实际生效的技能层；
## - 晚入队 / 换型重放应执行的升级层。
##
## 不在这里修改 Aircraft、玩家账本或随机数状态，便于 focused bench 直接验证规则。


## 普通随机池的唯一过滤入口。
## doctrine_gate 接受一条升级并返回是否被局外学说门控；测试可不注入。
static func normal_candidates(
		upgrades: Array,
		aircraft_id: StringName,
		params: AircraftParams,
		owned_stacks: Dictionary,
		squad_classes: Array,
		doctrine_gate: Callable = Callable(),
		allow_nextgen: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for upgrade_variant in upgrades:
		var upgrade: Dictionary = upgrade_variant
		if bool(upgrade.get("evolved", false)):
			continue
		if not SurvivorData.is_normal_random_candidate(upgrade, allow_nextgen):
			continue
		if not SurvivorData.is_upgrade_available_for(
				upgrade, aircraft_id, params, owned_stacks, squad_classes):
			continue
		if doctrine_gate.is_valid() and bool(doctrine_gate.call(upgrade)):
			continue
		var uid: String = str(upgrade.get("id", ""))
		if int(owned_stacks.get(uid, 0)) >= int(upgrade.get("max_stacks", 1)):
			continue
		out.append(upgrade)
	return out


## 将已过滤候选按权威三轴分组；未知轴不另造旁路。
static func candidates_by_axis(candidates: Array) -> Dictionary:
	var out: Dictionary = {}
	for axis in SurvivorData.AXES:
		out[axis] = []
	for upgrade_variant in candidates:
		var upgrade: Dictionary = upgrade_variant
		var axis: StringName = SurvivorData.axis_of_upgrade(upgrade)
		if out.has(axis):
			(out[axis] as Array).append(upgrade)
	return out


## 玩家总账本 → 单机有效技能子集。skill_hooks 与各消费点只读这份投影。
static func effective_stacks_for_machine(
		upgrades: Array,
		owned_stacks: Dictionary,
		identity: Array,
		is_controlled: bool) -> Dictionary:
	var out: Dictionary = {}
	for upgrade_variant in upgrades:
		var upgrade: Dictionary = upgrade_variant
		var uid: String = str(upgrade.get("id", ""))
		var stacks: int = int(owned_stacks.get(uid, 0))
		if stacks > 0 and SurvivorData.upgrade_applies_to_machine(
				upgrade, identity, is_controlled):
			out[uid] = stacks
	return out


## 返回某架飞机在入队/换型重放时应执行的升级层。
## 每个元素为 {"upgrade": Dictionary, "stacks": int}；不重新检查抽卡门槛。
static func replay_layers_for_machine(
		upgrades: Array,
		owned_stacks: Dictionary,
		identity: Array,
		is_controlled: bool,
		skip_weapon: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for upgrade_variant in upgrades:
		var upgrade: Dictionary = upgrade_variant
		if skip_weapon and str(upgrade.get("category", "")) == "weapon":
			continue
		var uid: String = str(upgrade.get("id", ""))
		var stacks: int = int(owned_stacks.get(uid, 0))
		if stacks <= 0 or not SurvivorData.upgrade_applies_to_machine(
				upgrade, identity, is_controlled):
			continue
		out.append({"upgrade": upgrade, "stacks": stacks})
	return out


## 玩家总账本的重放计划；由 SurvivorMode 负责按归属下发，以保留 squad_once 与一次性动作语义。
static func owned_replay_layers(
		upgrades: Array,
		owned_stacks: Dictionary,
		skip_weapon: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for upgrade_variant in upgrades:
		var upgrade: Dictionary = upgrade_variant
		if skip_weapon and str(upgrade.get("category", "")) == "weapon":
			continue
		var stacks: int = int(owned_stacks.get(str(upgrade.get("id", "")), 0))
		if stacks > 0:
			out.append({"upgrade": upgrade, "stacks": stacks})
	return out
