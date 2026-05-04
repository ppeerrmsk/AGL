class_name ZoneRewardRegistry
extends RefCounted

## §4 战区奖励映射（占位框架）
##
## 设计意图：
##   - 默认所有战区无技能奖励（攻克只回血 ZONE_CLEAR_HP_RESTORE）
##   - 后续用户按战区 ID 注册专属奖励：register_reward(&"A", "ecm_pod")
##   - 注册的 upgrade 仍然走 SurvivorData.UPGRADES 表，需在该表中存在
##   - 一个战区一个奖励；未注册 → 返回空 dict
##
## 使用：
##   ZoneRewardRegistry.register_reward(&"BOSS_F47", "evasion_cobra")
##   var r = ZoneRewardRegistry.get_reward_for(zone_id)  # → upgrade dict 或 {}
##
## 不在本次实装中硬编码任何战区→技能绑定，留给设计师后续决定。

static var _bindings: Dictionary = {}      ## zone_id (StringName) → upgrade_id (String)


## 注册战区奖励：攻克 zone_id 时发放 upgrade_id 对应的技能
## upgrade_id 必须在 SurvivorData.UPGRADES 中存在，否则 get_reward_for 返回 {}
static func register_reward(zone_id: StringName, upgrade_id: String) -> void:
	_bindings[zone_id] = upgrade_id


## 取消战区奖励
static func unregister_reward(zone_id: StringName) -> void:
	_bindings.erase(zone_id)


## 清空所有绑定（生存模式重开时不一定需要清，但提供给测试用）
static func clear_all() -> void:
	_bindings.clear()


## 查战区对应奖励 upgrade dict；未注册或 upgrade_id 不存在 → 返回空 dict
static func get_reward_for(zone_id: StringName) -> Dictionary:
	if not _bindings.has(zone_id):
		return {}
	var uid: String = _bindings[zone_id]
	for u in SurvivorData.UPGRADES:
		if u.get("id", "") == uid:
			return u
	# 注册过但 upgrade_id 找不到（可能被删了），warn 一次但不崩
	push_warning("ZoneRewardRegistry: zone %s 注册的 upgrade_id '%s' 在 SurvivorData.UPGRADES 中未找到" % [zone_id, uid])
	return {}


## 是否有注册（用于 UI 决定是否展示"未知奖励"提示）
static func has_reward(zone_id: StringName) -> bool:
	return _bindings.has(zone_id)


## ── 默认绑定（占位空，留给后续设计） ─────────────────────────
## 后续用户在此 register_reward(zone_id, upgrade_id) 写表
## 例子（注释；启用时取消注释并自行选合适绑定）：
##   register_reward(&"A", "ecm_pod")
##   register_reward(&"BOSS_F47", "ecm_pod")
static func _init_default_bindings() -> void:
	# TODO: 设计师后续按战区填充
	pass
