class_name SquadCommandController
extends Node

## RTS 指挥单一所有者：把"下命令 + 自动交战"逻辑从 survivor_mode 抽出来独立。
## 设计权威源：docs/specs/systems/rts-command.md
##
## 两类目标语义，严格分离：
##   commanded_target  —— 玩家显式点名的攻击命令（铁律）。逐机持有在 Aircraft 上、跨切控持久，
##                        本控制器 + AIController 都不得覆盖；只在目标死/玩家改令时清。
##   _auto_engage_target —— 本控制器自动锁的"贴脸"目标（RTS 自动交战）。可被拴绳/最近目标切换。
##
## 数值全部走 params（RtsCommandParams，resources/rts_command.tres），无硬编码常量。

var params: RtsCommandParams = null
var _mode: Node = null                       ## SurvivorMode（动态访问 selected_aircraft / player_aircraft）
var _auto_engage_target: CombatUnit = null   ## 自动锁的目标（非玩家命令）
var _accum: float = 0.0

func setup(mode: Node, p: RtsCommandParams) -> void:
	_mode = mode
	params = p if p != null else RtsCommandParams.new()

# ══════════════════════════════════════════════
#  指令入口（survivor_mode 输入层转发到这里）
# ══════════════════════════════════════════════

## 玩家点名攻击：给被操控机下达持久命令（铁律目标）。
func command_attack(enemy: CombatUnit) -> void:
	if enemy == null:
		return
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.set_combat_target(enemy)
			ac.commanded_target = enemy   # 逐机持久命令
	_auto_engage_target = null

## 玩家下巡航航点：放弃攻击命令，全队飞向世界坐标点。
func command_move(world_pos: Vector2) -> void:
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			if ac.evasion_mode:
				ac.set_evasion_mode(false)
			ac.commanded_target = null
			ac.clear_combat_target()
			ac.target_position = world_pos

## 玩家取消（右键 / 地图右键）：放弃攻击命令 + 清航向。
func cancel() -> void:
	_auto_engage_target = null
	for ac in _selected():
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.commanded_target = null
			ac.clear_combat_target()
			ac.target_position = Vector2.INF

# ══════════════════════════════════════════════
#  自动交战 tick（每 params.auto_engage_interval_s）
# ══════════════════════════════════════════════

func tick(delta: float) -> void:
	_accum += delta
	if _accum < params.auto_engage_interval_s:
		return
	_accum = 0.0
	var leader := _leader()
	if leader == null:
		_auto_engage_target = null
		return

	# ── 铁律：玩家命令目标存活 → 死咬，重新指回，绝不被自动交战夺走 ──
	var cmd: CombatUnit = leader.commanded_target
	if cmd != null:
		if not is_instance_valid(cmd) or cmd.is_destroyed:
			# 命令目标阵亡 → 解除命令 + 回待命（不飞向死敌 lead 点），落到下面自动交战
			leader.commanded_target = null
			leader.clear_combat_target()
			leader.target_position = Vector2.INF
		else:
			if leader.combat_target != cmd:
				leader.set_combat_target(cmd)
			_auto_engage_target = null
			return

	# ── 自动交战（受 auto_engage_enabled 开关；玩家命令优先级已在上面处理）──
	var pa: Aircraft = _player_aircraft()
	if pa == null or not pa.auto_engage_enabled:
		_auto_engage_target = null
		return
	var ct: CombatUnit = leader.combat_target
	if ct != null and is_instance_valid(ct) and not ct.is_destroyed:
		# 拴绳只对自动锁的目标生效；玩家命令目标已在上面 return，走不到这里
		if ct == _auto_engage_target \
				and leader.global_position.distance_to(ct.global_position) \
					> params.auto_engage_radius_px * params.auto_engage_leash_mult:
			leader.clear_combat_target()
			leader.target_position = Vector2.INF
			_auto_engage_target = null
		return
	# combat_target 空/亡：若是自动锁的目标打完了 → 回待命（清残留 lead 点）
	if _auto_engage_target != null:
		_auto_engage_target = null
		if ct != null:
			leader.clear_combat_target()
		leader.target_position = Vector2.INF
	# 仍在巡航途中（玩家下的航点/战区）→ 不打，保证抵达
	if leader.target_position != Vector2.INF:
		return
	var tgt := _find_target(leader.global_position, params.auto_engage_radius_px)
	if tgt != null:
		leader.set_combat_target(tgt)
		_auto_engage_target = tgt

## 半径内最近的有效敌方目标（飞机/地面/船挂点）。跳过锁定免疫的 NavalUnit 船体。
## 用 CombatUnit.all_units（perf 友好共享表），不扫 mode.get_children()。
func _find_target(center: Vector2, radius: float) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := radius
	for u in CombatUnit.all_units:
		if not is_instance_valid(u) or u.team == 0 or u.is_destroyed:
			continue
		if u.is_lock_immune():
			continue
		var d := center.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ══════════════════════════════════════════════
#  mode 访问辅助
# ══════════════════════════════════════════════

func _selected() -> Array:
	if _mode == null:
		return []
	return _mode.selected_aircraft

func _leader() -> Aircraft:
	var sel := _selected()
	if sel.is_empty():
		return null
	var leader: Aircraft = sel[0]
	if not is_instance_valid(leader) or leader.is_destroyed:
		return null
	return leader

func _player_aircraft() -> Aircraft:
	if _mode == null:
		return null
	var pa: Aircraft = _mode.player_aircraft
	if pa == null or not is_instance_valid(pa) or pa.is_destroyed:
		return null
	return pa
