class_name EscortBehavior
extends RefCounted

## 护驾行为子系统（Sentinel UAV 绕长机飞 + 拦截导弹 + 自爆攻击）
##
## 当前现状（2026-05-04 重构 Step 4 起步）：
##   ⚠ **执行代码仍住在 `ai_controller.gd._process_simple`**（~250 行散在 696-936/1112-1118）。
##   未完成：把执行体迁过来。原因：orbit/shield/kamikaze 与 simple_ai 的 PATROL/ENGAGE
##   分支高度耦合（_current_target 共享 / _scan_timer 复用 / 撤退条件判断），完整搬运
##   要重写整个 _process_simple，超出当前重构作用域。
##
##   本类目前只做 **谓词集中点**：把"护驾态生效"的 5 条件 AND 检查（散布 5 处）收口到
##   `is_active(ai)` 一处。后续把执行体迁过来时调用方不需改。
##
## 接入点：
##   - `ai_controller.gd:699` 长机失效检测
##   - `ai_controller.gd:724` shield 导弹扫描
##   - `ai_controller.gd:820` orbit 主循环
##   - `ai_controller.gd:981` engage 期间 tether 检测
##   - `ai_controller.gd:1114` _try_engage_simple 护驾过滤
##
## 与 Squad 的关系：
##   escort 单位仍占 `squad / squad_index` 槽位（共享 leader 死亡清理 + 编队列表
##   计数），但 _state 保持 simple_ai 路径而非 SQUAD_FOLLOW。
##   用 `SquadFactory.register_wingman(sq, ac, set_state=false)` 显式标识。

## 护驾态是否生效：长机有效 + 设了 orbit_squad_leader 标志
## 替代原本散布 5 处的 5 条件 AND 检查
static func is_active(ai: AIController) -> bool:
	if not ai.orbit_squad_leader:
		return false
	if not ai.squad:
		return false
	var leader: Aircraft = ai.squad.leader
	return leader != null and is_instance_valid(leader) and not leader.is_destroyed

## 长机已阵亡的清理：清 orbit 标志 + buff 还原 + 解 squad 引用
## 调用方在 _process_simple 头部判定，长机消失就走这里
static func cleanup_after_leader_lost(ai: AIController) -> void:
	ai.orbit_squad_leader = false
	ai.shield_leader = false
	ai.aircraft.orbit_speed_cap = 0.0
	ai.aircraft.ai_override_pursuit = false
	# 撤除 Sentinel 光环 buff
	if ai.aircraft.has_meta("commander_buff_originals"):
		var originals: Dictionary = ai.aircraft.get_meta("commander_buff_originals")
		ai.aggression = originals.get("aggression", ai.aggression)
		if ai.aircraft.params:
			ai.aircraft.params.roll_rate = originals.get("roll_rate", ai.aircraft.params.roll_rate)
			ai.aircraft.params.max_g = originals.get("max_g", ai.aircraft.params.max_g)
			ai.aircraft.params.max_g_structural = originals.get("max_g_structural", ai.aircraft.params.max_g_structural)
			ai.aircraft.params.max_speed = originals.get("max_speed", ai.aircraft.params.max_speed)
			ai.aircraft.params.cruise_speed = originals.get("cruise_speed", ai.aircraft.params.cruise_speed)
			ai.aircraft.params.acceleration = originals.get("acceleration", ai.aircraft.params.acceleration)
			ai.aircraft.params.stall_speed_base = originals.get("stall_speed_base", ai.aircraft.params.stall_speed_base)
		ai.aircraft.remove_meta("commander_buff_originals")
		ai.aircraft.remove_meta("commander_buffed_by")
	ai.squad = null
	ai.squad_index = -1
