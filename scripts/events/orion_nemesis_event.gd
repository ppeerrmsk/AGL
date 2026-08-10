## 宿敌 ORION 事件（spec events/ace-orion；tier §3.8 宿敌条款唯一实例）
##
## 生命周期：
##   _start   地图边缘随机方位静默生成 Cre 单机（**无提示/无台词/无 Tab 特标**——
##            宿敌条款豁免 §2.6 三件套；伪装普通敌橙）→ 按生涯被击坠计数查档位表
##            覆写 AI/武器/防御/性能 → 死咬玩家**当前操控机**
##   _update  0.5s 软维护 PURSUIT（切控跟着换目标）；被击坠 → 生涯计数 +1（下一局
##            机号进位 Cre-XX、更强）→ end；BOSS 闸 → 撤离（撤离中被杀计数照 +1）
##   独立轨道：不进王牌轮换池、不占"同场 ≤1 支"名额（survivor_mode._update_orion_event）
class_name OrionNemesisEvent
extends GameEvent

const TRIGGER_S := 300.0            ## 中期静默入场（survivor_mode 调度读取）
const MAINTAIN_S := 0.5             ## PURSUIT 软维护间隔
const AB_DIST_PX := 2500.0          ## 距操控机超此距离开加力
const WITHDRAW_FREE_OUTSET_PX := 800.0

## 成长档位表（spec events/ace-orion §2.3 草案）：强度只由生涯被击坠计数 N 决定。
## 档内恒定、档间只在下一次登场生效（局内绝不变身）。
const TIERS := [
	{"min": 0,  "ai": 0.30, "missiles": 0, "flares": 0, "dodge": 0.00, "gun": "keep", "mult": 1.00},
	{"min": 5,  "ai": 0.50, "missiles": 2, "flares": 0, "dodge": 0.10, "gun": "keep", "mult": 1.10},
	{"min": 15, "ai": 0.70, "missiles": 4, "flares": 1, "dodge": 0.20, "gun": "ace",  "mult": 1.20},
	{"min": 30, "ai": 0.90, "missiles": 5, "flares": 1, "dodge": 0.35, "gun": "ace",  "mult": 1.30},
	{"min": 50, "ai": 1.00, "missiles": 6, "flares": 1, "dodge": 0.50, "gun": "ace",  "mult": 1.40},
]

const ACE_GUN_RES := "res://resources/ace_gun.tres"
const SUPPORT_FLARE_RES := "res://resources/ace_support_flare.tres"

var _unit: Aircraft = null
var _maintain := 0.0
var _withdrawing := false

## N（生涯被击坠数）→ 档位配置（纯函数，bench 直接验单调性）
static func tier_for(n: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if n >= int(t["min"]):
			out = t
	return out

## N → 机号（Cre-01 起步，被击坠一次进一位；封顶 Cre-99）
static func designation(n: int) -> String:
	return "Cre-%02d" % clampi(n + 1, 1, 99)

func _start() -> void:
	super._start()
	name = "orion_nemesis"
	var sp = director.spawner
	var player: Aircraft = director.player
	if sp == null or player == null or not is_instance_valid(player) or player.is_destroyed:
		end()
		return
	# 入场点：边缘随机方位（宿敌条款：猎手不挑正门，不保证玩家前方）
	var half := MapBoundary.world_half_px() - 500.0
	var side := randi() % 4
	var along := randf_range(-half, half)
	var pos: Vector2
	match side:
		0: pos = Vector2(along, -half)
		1: pos = Vector2(half, along)
		2: pos = Vector2(along, half)
		_: pos = Vector2(-half, along)
	var to_player := (player.global_position - pos).normalized()
	var heading_deg := rad_to_deg(atan2(to_player.x, -to_player.y))

	var n: int = CareerArchive.get_orion_kills()
	var t := tier_for(n)
	var ac: Aircraft = sp._create_enemy(SurvivorSpawner.EnemyType.CRE, pos, heading_deg)
	_unit = ac
	managed_units.append(ac)

	# ── 身份：机号即呼号（宿敌条款；固定唯一，不与杂鱼重名——"Cre-XX" 不在池内）──
	CallsignDB.recycle(ac.callsign)
	ac.callsign = designation(n)
	AceTier.mark(ac)
	ac.set_meta("category", "ace_nemesis")
	ac.set_meta("skip_far_cleanup", true)

	# ── 档位应用（一次成型，局内不变身）──
	var p: AircraftParams = ac.params
	if p != null:
		ac.hp = p.max_hp
		# 性能乘数（初始敌机级别 ×1.0 → 王牌档 ×1.4）
		var mult := float(t["mult"])
		p.max_speed *= mult
		p.acceleration *= mult
		p.max_g *= mult
		p.climb_rate_max *= mult
		# 武器：导弹按档位挂载（硬预算不装填）；机炮档 III 起换 ace_gun
		if p.missile != null:
			p.missile.max_count = int(t["missiles"])
			ac.missiles_remaining = p.missile.max_count
			ac.enable_missile_reload = false
		if String(t["gun"]) == "ace":
			p.gun = load(ACE_GUN_RES).duplicate(true)
			ac.ammo = p.gun.max_ammo
		# 防御：档 III 起 1 枚必躲 flare（AceTier.is_ace → jam 1.00 共享判定）
		if int(t["flares"]) <= 0:
			p.flare = null
			ac.flares_remaining = 0
		else:
			p.flare = load(SUPPORT_FLARE_RES).duplicate(true)
			ac.flares_remaining = p.flare.max_flares
		ac.enable_flare_reload = false
	ac.bullet_dodge_chance = float(t["dodge"])

	# ── AI：四维随档位爬升；心气从第一天起就顶着（变的是本事不是心气）──
	var ai: AIController = ac._get_ai_controller()
	if ai:
		var lv := float(t["ai"])
		ai.skill_level = lv
		ai.composure = lv
		ai.focus = lv
		ai.situational_awareness = lv
		ai.aggression = 0.95
		ai.self_preservation = 0.15
		ai.engage_cooldown = 0.5
		ai.engage_duration = 999.0
		ai.boss_attacker = true
	# 生涯档案：遭遇记一笔（静默事件也入档）
	if director.mode and director.mode.has_method("archive_enabled") \
			and director.mode.archive_enabled():
		CareerArchive.record_ace_encounter("orion")
	EventLogger.log_event("EVENT", "Orion",
		"%s inbound (N=%d tier ai=%.2f mult=%.2f) from %s" % [ac.callsign, n, t["ai"], t["mult"], pos.round()])

func _update(delta: float) -> void:
	# 被击坠 → 生涯计数 +1（撤离中被杀也算——杀了就是杀了）
	if _unit == null or not is_instance_valid(_unit) or _unit.is_destroyed:
		if director.mode and director.mode.has_method("archive_enabled") \
				and director.mode.archive_enabled():
			CareerArchive.record_ace_defeat("orion")
		EventLogger.log_event("EVENT", "Orion", "shot down -> career +1")
		end()
		return
	# 撤离：出界静默释放
	if _withdrawing:
		if MapBoundary.distance_to_edge(_unit.global_position) <= -WITHDRAW_FREE_OUTSET_PX:
			_unit.set_meta("xp_granted", true)
			CombatUnit.release_target_refs(_unit)   # 静默释放：没走坠机流程，引用得手动摘
			_unit.queue_free()
			end()
		return
	# BOSS 闸落下 → 撤离（tier §2.9 契约；宿敌无时间奖励本就不存在）
	if director.mode and director.mode._is_in_boss_phase():
		_begin_withdraw()
		return
	# ── PURSUIT 软维护：死咬玩家**当前操控机**（读 mode.player_aircraft 活字段，
	#    切控经 _set_player_aircraft 重定向——SEAM-019 免疫，不缓存引用）──
	_maintain -= delta
	if _maintain > 0.0:
		return
	_maintain = MAINTAIN_S
	# player_aircraft 在终局/切控边界可能短暂保留已释放实例；必须先用 Variant
	# 接住并验证，再收窄成 Aircraft，否则强类型赋值会先于 is_instance_valid 报错。
	var target_value: Variant = null
	if director.mode and "player_aircraft" in director.mode:
		target_value = director.mode.player_aircraft
	if typeof(target_value) != TYPE_OBJECT or not is_instance_valid(target_value) \
			or not (target_value is Aircraft):
		return
	var target := target_value as Aircraft
	if target.is_destroyed:
		return
	var ai: AIController = _unit._get_ai_controller()
	if ai == null:
		return
	var need := ai._current_target == null or not is_instance_valid(ai._current_target) \
			or ai._current_target != target
	if ai._state != AIController.AIState.ENGAGE or need:
		if ai.acquire_target(target, AIController.TargetSource.TS_BOSS, "orion pursuit"):
			ai.enter_engage_state(false)
			ai.boss_attacker = true
	_unit.is_afterburner = _unit.global_position.distance_to(target.global_position) > AB_DIST_PX \
			and _unit.fuel > 0.0

func _begin_withdraw() -> void:
	_withdrawing = true
	var ai: AIController = _unit._get_ai_controller()
	if ai:
		ai.release_target(AIController.TargetSource.TS_BOSS, "orion withdraw")
		ai._state = AIController.AIState.PATROL
		var half := MapBoundary.world_half_px() + WITHDRAW_FREE_OUTSET_PX + 400.0
		var pos := _unit.global_position
		var out: Vector2
		if absf(pos.x) > absf(pos.y):
			out = Vector2(signf(pos.x) * half, pos.y)
		else:
			out = Vector2(pos.x, signf(pos.y) * half)
		ai.waypoints = PackedVector2Array([out])
		ai.current_waypoint_index = 0
	_unit.is_afterburner = true
	EventLogger.log_event("EVENT", "Orion", "withdraw (boss unlocked)")

func _finish() -> void:
	_unit = null
