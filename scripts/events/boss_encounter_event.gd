## BossEncounterEvent —— BOSS 战完整剧本
##
## 三段生命周期（用 phase 驱动 + AIDirective 命令各成员）：
##
##   PRE_STAGE：BOSS 区诞生瞬间触发
##     - 选 encounter（CSG / AceSquad）
##     - 刷出全员
##     - 给所有成员下 directive：
##         · CSG 舰船 → HOLD_POSITION（不开火、保持当前点；旗舰沿初始 waypoints 缓行）
##         · AceSquad → FLY_TO_POINT(anchor, on_arrival=PATROL)（飞到 BOSS 区→巡逻）
##     - 显示 WARNING 横幅 + "BOSS 区域已出现"持久提示
##     - 不切 BGM、不亮血条
##
##   ENGAGED：玩家进入 BOSS 圆 OR 贴近 BOSS 成员（< BOSS_ENGAGE_DISTANCE）
##     - 释放所有 directive → CSG 开火 / AceSquad 进入角色分配（CLOSE_FIGHTER/RANGED_STRIKER）
##     - 切 BOSS 曲、亮 HUD 血条
##     - encounter.hud_visible = true
##     - selected_id = BOSS（启用 boss phase：刷怪/猎手/常规战区任务停摆）
##     - 临时提示 "BOSS 进入战场"
##
##   VICTORY：encounter.active 从 true → false
##     - 触发 mode._on_victory
##     - 事件 end()
##
## 与旧实现对比：
##   - 删掉 AceSquad.TRANSIT/PATROL 状态机（合并到 directive 系统）
##   - 删掉 NavalUnit.passive_mode 路径（统一走 directive.combat_disabled）
##   - 删掉 survivor_mode._update_boss_phase 里的两段 stage if 大块（事件 _update 内聚）

class_name BossEncounterEvent
extends GameEvent

enum Phase { PRE_STAGE, ENGAGED, VICTORY }

# ── 配置（director 启动时由 mode 注入）──
const BOSS_ENGAGE_DISTANCE_PX := 2500.0   ## 玩家距 BOSS 成员的交战触发距离（触发器 T2）
## 猎手进场（spec boss-hunter-doctrine §2.4）：出生在玩家【机头前方】扇面内的固定距离上。
## 取代旧的"离玩家最远的地图角落"—— 60km 图上那能有 40km+，纯粹的空转时间。
const INBOUND_SPAWN_DISTANCE_PX := 6000.0 ## 12 km；F-47 巡航下约 27s 闭合
const INBOUND_SPAWN_FAN_DEG := 30.0       ## 机头前方 ±30° 扇面（守"事件刷在沿途"约定）
const INBOUND_PURSUE_REFRESH_S := 0.5     ## 猎手指令重取玩家位置的间隔

var phase: int = Phase.PRE_STAGE
var encounter: BossEncounter = null
var anchor: Vector2 = Vector2.INF
var heading_deg: float = 0.0
var map_id: String = "default"
var boss_id_override: String = ""    ## Boss Debug 强制指定 boss id，绕过地图池随机
## 生涯档案 BOSS 轮换 history（spec career-archive §3.1；mode 在正式局注入，
## 空 = 旧纯随机。事件层不直读 CareerArchive autoload，保持可测）
var boss_history: Dictionary = {}
var _was_active: bool = false
## INBOUND 相开始时的全员 HP 总和；掉下去就说明挨打了（接战触发器 T4）。
## -1 = 尚未快照。用总和而不是逐机记录：一个 float 就够，且对舰队 BOSS 同样成立
var _inbound_hp_snapshot: float = -1.0
## 当前猎手指令追的那架玩家机。玩家换人（1-4 切控 / 阵亡换帅）时用它检测并重下指令
var _pursue_target: Aircraft = null
## 登场演出进行中：演出自己在下演员指令，此期间猎手软维护必须让位，否则会互相覆盖
var _cinematic_running: bool = false
## 上次推给 encounter 的玩家引用（换人检测，避免每帧重复下推）
var _last_pushed_player: Aircraft = null

func _init(p_anchor: Vector2, p_heading_deg: float, p_map_id: String, p_boss_id_override: String = "",
		p_boss_history: Dictionary = {}) -> void:
	name = "boss_encounter"
	anchor = p_anchor
	heading_deg = p_heading_deg
	map_id = p_map_id
	boss_id_override = p_boss_id_override
	boss_history = p_boss_history

# ──────────────── 生命周期 ────────────────

func _start() -> void:
	active = true
	# 1. 选 encounter（boss_debug 路径走 instantiate 强制指定；否则按地图池 roll）
	if boss_id_override != "":
		encounter = BossRegistry.instantiate(boss_id_override)
	else:
		encounter = BossRegistry.pick_for_map(map_id, anchor, boss_history)
	if encounter == null:
		push_error("BossEncounterEvent: BossRegistry returned null for map '%s'" % map_id)
		end()
		return
	encounter.initial_heading_deg = heading_deg

	# 2. 刷出 + 进 PRE_STAGE
	if encounter is CarrierStrikeGroup:
		_spawn_csg()
		_apply_pre_stage_directives_csg()
	elif encounter is AceSquad:
		_spawn_ace()
		_apply_pre_stage_directives_ace()
	elif encounter is MotherGooseBoss:
		_spawn_mother_goose()
		_apply_pre_stage_directives_mother_goose()
	else:
		push_error("BossEncounterEvent: unsupported encounter type %s" % encounter.get_class())
		end()
		return

	# 3. 登场演出（spec ui-transition §2.8）。成功则台词与镜头全部由序列编排，
	#    跳过下面的横幅/无线电旧路径；失败（无演出定义 / 缺演员）则回落原行为
	if _try_play_arrival_cinematic():
		EventLogger.log_event("EVENT", name,
			"PRE_STAGE: %s 走登场演出" % encounter.display_name)
		return

	# 3b. UI：WARNING + 持久提示
	var hint = director.mode.get("_zone_hint") if director and director.mode else null
	if hint:
		hint.show_warning_banner("WARNING  WARNING")
		hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))

	# 4. 无线电：BOSS 中队登场挑衅（spec radio-chatter §3.3）
	# 说话人呼号由 encounter 的 callsign_prefix 合成，不依赖机体 _ready() 是否已分配呼号。
	var radio = director.mode.get("_radio") if director and director.mode else null
	if radio:
		radio.say_boss_sequence(encounter.boss_id, "spawn", encounter.callsign_prefix)

	EventLogger.log_event("EVENT", name,
		"PRE_STAGE: %s staged at %s" % [encounter.display_name, anchor])

## 尝试播 <boss_id 小写>_arrival 演出。返回 false 表示没有该 BOSS 的演出定义，
## 调用方回落到"横幅 + 无线电"的旧登场路径。
##
## ⚠ 演员指令的所有权【留在本事件】：只把 self 作为 owner 传给导演，导演转手调
##    self.set_directive() 下发。事件结束时 EventDirector 会自动 clear_all_directives()
##    兜底 —— 绝不让导演自建第二套所有权（spec §3.3）
func _try_play_arrival_cinematic() -> bool:
	if not (encounter is AceSquad):
		return false
	var seq_name: String = "%s_arrival" % encounter.boss_id.to_lower()
	var members: Array = (encounter as AceSquad).get_all_members()
	if members.is_empty():
		return false
	var pres = Engine.get_main_loop().root.get_node_or_null("Presentation")
	if pres == null or not pres.has_method("play_cinematic"):
		return false
	if not pres.has_sequence(seq_name):
		return false

	# 进场方向：从玩家指向锚点的【反】向 —— 让 BOSS 从玩家机头前方飞来，
	# 而不是从背后冒出来（守"事件刷在沿途"约定）
	var player = director.player if director else null
	var inbound := Vector2.RIGHT
	if player and is_instance_valid(player):
		var to_anchor: Vector2 = anchor - player.global_position
		if to_anchor.length_squared() > 1.0:
			inbound = to_anchor.normalized()
	var extra: Array = []
	if director and director.mode:
		for key in ["_map_features", "hud", "_zone_arrow"]:
			var n = director.mode.get(key)
			if n != null and is_instance_valid(n):
				extra.append(n)

	var ok: bool = pres.play_cinematic(seq_name, {
		"owner": self,
		"actors": members,
		"anchor": anchor,
		"cp": anchor + inbound * 250.0,      ## 交汇点：锚点前方 250px（按 1.8s 交汇窗 × 机体包线反推）
		"inbound": inbound,
		"extra_layers": extra,
		"callsign_prefix": encounter.callsign_prefix,
		"scatter_seed": inbound.angle(),
		# BGM 快照：audio 通道在演出开场切 BOSS 曲（导演只拿字符串，不认识 encounter）
		"bgm_layers": encounter.bgm_layers,
		"bgm_track": encounter.bgm_track,
	})
	if ok:
		# 演出期间猎手软维护让位（否则两套指令互相覆盖，编队飞入被打散）
		_cinematic_running = true
		# 演出收尾时恢复 PRE_STAGE 契约（见 _on_arrival_cinematic_done）。
		# release 步骤会 clear_all_directives —— 不接这钩子，事件仍在 PRE_STAGE
		# 但四机既无 directive 又没 engage()，AceSquad 状态机停摆、AI 乱飞
		pres.sequence_finished.connect(_on_arrival_cinematic_done.bind(seq_name),
			CONNECT_ONE_SHOT)
	return ok

## 登场演出结束：重下 PRE_STAGE 巡逻指令（飞回锚点绕环，隐身状态下自然完成
## 分镜的"散开 → 重新合并成阵型"），并补上被演出路径跳过的持久提示
func _on_arrival_cinematic_done(finished_name: String, expected_name: String) -> void:
	if finished_name != expected_name:
		# 理论上不可能（演出期间世界冻结、无其他序列），防御性重挂
		var pres = Engine.get_main_loop().root.get_node_or_null("Presentation")
		if pres:
			pres.sequence_finished.connect(_on_arrival_cinematic_done.bind(expected_name),
				CONNECT_ONE_SHOT)
		return
	_cinematic_running = false
	if not active or phase != Phase.PRE_STAGE or encounter == null:
		return
	_apply_pre_stage_directives_ace()
	var hint = director.mode.get("_zone_hint") if director and director.mode else null
	if hint:
		hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))

func _update(delta: float) -> void:
	if encounter == null:
		end()
		return

	# 玩家引用保鲜（spec boss-hunter-doctrine §3.6 / SEAM-019）。encounter 的 _player 是
	# spawn 时缓存的，而 survivor_mode._set_player_aircraft() 这个 chokepoint 扫不到它
	# （校验脚本只扫 survivor_mode.gd，够不着经 spawner 传参的缓存）。旧模型下这是慢性病，
	# 猎手模型下 BOSS 全程追 _player —— 玩家一切控就会去追一架不再是玩家的飞机
	_refresh_encounter_player()

	# encounter 自己也要 tick（CSG Phase 2 触发 / AceSquad cloak / role assignment）
	encounter.update(delta)

	# BOSS 圈跟着 BOSS 走（spec boss-hunter-doctrine §2.6）。猎手模型下 BOSS 不在锚点上了，
	# 钉死在锚点的洋红圈 + 指向它的 HUD 箭头是假信息。战术地图与 ZoneArrow 都读
	# boss_zone["center"]，故这里同步一次即两处自动跟随，零改动
	_sync_boss_zone_to_members()

	# 阶段推进
	match phase:
		Phase.PRE_STAGE:
			# 首帧快照全员 HP（触发器 T4 的基准）。此刻 BOSS 还在 12km 外，不可能已挨打
			if _inbound_hp_snapshot < 0.0:
				_inbound_hp_snapshot = _members_hp_total()
			_maintain_inbound_pursuit()
			if _check_engagement_trigger():
				_enter_engaged()
		Phase.ENGAGED:
			pass

	# 胜利检测：encounter.active true→false 沿
	if _was_active and not encounter.active:
		phase = Phase.VICTORY
		_on_victory()
	_was_active = encounter.active

func _finish() -> void:
	# 通知 mode（survivor_mode 会做 hud / state 清理）
	if director and director.mode and director.mode.has_method("on_boss_event_finished"):
		director.mode.on_boss_event_finished(self)

# ──────────────── 阶段切换 ────────────────

## ENGAGED：释放 directive → 单位回到正常 AI（CSG 开火、AceSquad 角色分配）
func _enter_engaged() -> void:
	_debug_break("BOSS engaged: %s" % encounter.display_name)
	phase = Phase.ENGAGED
	# 释放所有 directive
	clear_all_directives()
	# 通用 engage()：AceSquad → PURSUIT；CSG → 启动 F/A-18 弹射循环；其他子类按需覆盖
	encounter.engage()
	# HUD + BGM。幂等守卫：登场演出可能已切过 BOSS 曲（audio 通道），
	# crossfade_music 没有同曲早退 —— 不守卫会把正在播的 BOSS 曲重启一遍
	encounter.hud_visible = true
	var want_bgm: String = String(encounter.bgm_layers[0]) if not encounter.bgm_layers.is_empty() 			else encounter.bgm_track
	if want_bgm != "" and AudioManager.current_music_id() != want_bgm:
		if not encounter.bgm_layers.is_empty():
			AudioManager.play_layered_music(encounter.bgm_layers, 2.0, 0)
		else:
			AudioManager.crossfade_music(encounter.bgm_track, 2.0)
	# 进入 boss phase（mode 切 selected_id）
	if director and director.mode and director.mode.has_method("on_boss_engaged"):
		director.mode.on_boss_engaged(self)
	EventLogger.log_event("EVENT", name, "ENGAGED at %s" % anchor)

func _on_victory() -> void:
	_debug_break("BOSS victory: %s" % encounter.display_name)
	if director and director.mode and director.mode.has_method("on_boss_victory"):
		director.mode.on_boss_victory(self)
	end()

# ──────────────── 触发判定 ────────────────

## 接战触发器（spec boss-hunter-doctrine §2.2）：四条，任一满足即切 ENGAGED。
##   T1 玩家进 BOSS 圈  T2 玩家贴近成员  T3 任一成员被锁定  T4 任一成员受伤
##
## T3/T4 是猎手化的核心修复 —— 旧版只认几何距离，玩家用射程 10km+ 的中距弹站在
## 苏醒半径外白嫖，BOSS 连"我被锁定了"都不知道（playtest log 20260722_005100：
## 651.7s 开火 → 660.1s 才苏醒，中间白挨 8.4 秒）。
## T3 取"被锁定"而非"被击中"：锁定发生在发射【之前】，给 BOSS 留出反应时间。
func _check_engagement_trigger() -> bool:
	var player: Aircraft = _live_player()
	# ── T3/T4 不依赖玩家引用：BOSS 挨打就是挨打，哪怕玩家机此刻正在切换 ──
	var hp_now := _members_hp_total()
	if _inbound_hp_snapshot >= 0.0 and hp_now < _inbound_hp_snapshot - 0.01:
		EventLogger.log_event("BOSS", encounter.display_name,
			"engage trigger T4: 成员受伤 (hp %.0f → %.0f)" % [_inbound_hp_snapshot, hp_now])
		return true
	for m in encounter.get_display_members():
		if not is_instance_valid(m) or not (m is CombatUnit):
			continue
		var cu := m as CombatUnit
		if cu.is_destroyed:
			continue
		# 船体锁定免疫的成员（舰队 BOSS）玩家锁的是挂点/弱点代理，直读 is_locked 全盲 ——
		# 用聚合查询把代理锁定态收上来（普通飞机无此方法，回落 is_locked）
		var locked: bool = cu.is_engaged_by_lock() if cu.has_method("is_engaged_by_lock") else cu.is_locked
		if locked:
			EventLogger.log_event("BOSS", encounter.display_name,
				"engage trigger T3: %s 被锁定" % cu.callsign)
			return true

	if player == null:
		return false
	# ── T1 玩家在 BOSS 圈圆内 ──
	var bz_radius: float = 2200.0   ## 兜底值与 ZoneData.BOSS_RADIUS 一致
	if director.mode and "_zone_data" in director.mode and director.mode._zone_data:
		bz_radius = float(director.mode._zone_data.boss_zone.get("radius", 2200.0))
	if player.global_position.distance_to(anchor) <= bz_radius:
		return true
	# ── T2 玩家贴近任一 BOSS 成员 ──
	for m in encounter.get_display_members():
		if not is_instance_valid(m):
			continue
		if "is_destroyed" in m and m.is_destroyed:
			continue
		if player.global_position.distance_to(m.global_position) <= BOSS_ENGAGE_DISTANCE_PX:
			return true
	return false

## 存活成员 HP 总和（触发器 T4 的比较量）
func _members_hp_total() -> float:
	var total := 0.0
	for m in encounter.get_display_members():
		if not is_instance_valid(m) or not (m is CombatUnit):
			continue
		var cu := m as CombatUnit
		if cu.is_destroyed:
			continue
		# 舰队 BOSS：船体伤害走 hull_hp/部件，不碰 CombatUnit.hp —— 读聚合池，否则 T4 全盲
		var member_hp: float = cu.boss_hp_pool() if cu.has_method("boss_hp_pool") else cu.hp
		total += member_hp
	return total

## 玩家机的【活引用】（spec boss-hunter-doctrine §3.6 / SEAM-019）。
## 猎手全程追玩家，绝不能读 spawn 时的快照 —— 玩家按 1-4 切控或长机阵亡换帅后，
## 快照会指向一架不再是玩家的飞机，甚至一个已释放的实例（SEAM-020 硬崩）。
## director.player 已在 survivor_mode._set_player_aircraft() chokepoint 登记，是活的。
func _live_player() -> Aircraft:
	var p: Aircraft = director.player if director else null
	if p == null or not is_instance_valid(p) or p.is_destroyed:
		return null
	return p

## 把活的玩家引用推给 encounter（各子类在 set_player_ref 里负责自己的全部缓存）
func _refresh_encounter_player() -> void:
	var p := _live_player()
	if p == null or p == _last_pushed_player:
		return
	_last_pushed_player = p
	encounter.set_player_ref(p)

## BOSS 圈中心同步到存活成员质心（spec §2.6）。无存活成员时不写入，保留上次值 ——
## CSG 二阶段的"航母已沉、F-14 尚未揭幕"窗口靠这条保住它的 _cv_death_position 兜底
func _sync_boss_zone_to_members() -> void:
	if director == null or director.mode == null:
		return
	if not ("_zone_data" in director.mode) or director.mode._zone_data == null:
		return
	var sum := Vector2.ZERO
	var n := 0
	for m in encounter.get_display_members():
		if not is_instance_valid(m) or not (m is CombatUnit):
			continue
		if (m as CombatUnit).is_destroyed:
			continue
		sum += (m as Node2D).global_position
		n += 1
	if n > 0:
		director.mode._zone_data.boss_zone["center"] = sum / float(n)

# ──────────────── 刷出（包装 spawner.._spawn_boss 但走自己路径，不切 BGM / 不打通用 _boss）────────────────

func _spawn_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	director.spawner._spawn_boss(csg, anchor, true)  # skip_bgm

func _spawn_ace() -> void:
	var ace := encounter as AceSquad
	# 猎手进场起点：玩家机头前方扇面 12km（spec boss-hunter-doctrine §2.4）
	var pp: Vector2 = anchor
	var phdg: float = 0.0
	var player := _live_player()
	if player:
		pp = player.global_position
		phdg = player.heading
	ace.entry_origin_override = _inbound_spawn_origin(pp, phdg)
	director.spawner._spawn_boss(ace, anchor, true)  # skip_bgm

func _spawn_mother_goose() -> void:
	var goose := encounter as MotherGooseBoss
	director.spawner._spawn_boss(goose, anchor, true)  # skip_bgm

## 猎手进场起点（spec boss-hunter-doctrine §2.4）：玩家【机头前方】±30° 扇面、12 km 处。
## 守"事件刷在玩家沿途"约定 —— 不从背后冒出、不逼玩家掉头。
## 越界时改指向地图中心（复用 AceSquad.spawn 的同款防越界策略）。
func _inbound_spawn_origin(pp: Vector2, player_heading: float) -> Vector2:
	var ang: float = player_heading \
			+ deg_to_rad(randf_range(-INBOUND_SPAWN_FAN_DEG, INBOUND_SPAWN_FAN_DEG))
	var dir := Vector2(sin(ang), -cos(ang))
	var origin := pp + dir * INBOUND_SPAWN_DISTANCE_PX
	if not MapBoundary.is_safe_inside(origin, 1500.0):
		var inward := Vector2.ZERO - pp
		if inward.length_squared() > 1.0:
			origin = pp + inward.normalized() * INBOUND_SPAWN_DISTANCE_PX
	return origin

# ──────────────── PRE_STAGE Directive 下发 ────────────────

## CSG 全舰：HOLD_POSITION（combat_disabled=true）—— 不开火，旗舰仍跑 waypoints 缓行
## 注：HOLD_POSITION 对舰船的语义是"不变更目标位置"，旗舰原始 waypoints 仍走（CSG 巡逻效果）
##     combat_disabled 才是关键 —— NavalWeapons.update 被跳过
func _apply_pre_stage_directives_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	for ship in csg.get_all_ships():
		set_directive(ship, AIDirective.passive())

## AceSquad 全员：PURSUE_UNIT(玩家)（spec boss-hunter-doctrine §2.1 INBOUND 相）
##
## 旧版是 FLY_TO_POINT(anchor) → PATROL_RING —— BOSS 飞到 BOSS 区绕圈等玩家上门。
## 用户裁定取消"去圈里等"这个概念：BOSS 知道玩家在哪，它朝玩家来。
## combat_disabled=true：接近相武器仍冷，但这不是"和平期"—— 玩家一锁定它（触发器 T3）
## 就立刻切 ENGAGED 开火。
func _apply_pre_stage_directives_ace() -> void:
	var ace := encounter as AceSquad
	var player := _live_player()
	_pursue_target = player
	if player == null:
		# 玩家此刻不可用（切控中 / 已阵亡）：下 PASSIVE 占位，玩家一回来软维护就重下猎手指令
		for member in ace.get_all_members():
			set_directive(member, AIDirective.passive())
		return
	for member in ace.get_all_members():
		set_directive(member, AIDirective.pursue(player, INBOUND_PURSUE_REFRESH_S))

## INBOUND 相软维护：玩家机换人（1-4 切控 / 阵亡换帅）时，把猎手指令重新指向新玩家机。
## 【只在真的换人时重下】—— 每帧重下会清掉 _directive_state 里的目标点快照与节流计时。
## 登场演出期间让位：演出自己在下演员指令（follow_path 编队飞入），两者会互相覆盖。
func _maintain_inbound_pursuit() -> void:
	if _cinematic_running or not (encounter is AceSquad):
		return
	var player := _live_player()
	# 旧目标可能已被释放：先净化再比较，绝不对野指针做属性访问（SEAM-020）
	if _pursue_target != null and not is_instance_valid(_pursue_target):
		_pursue_target = null
	if player == _pursue_target:
		return
	EventLogger.log_event("BOSS", encounter.display_name,
		"猎手目标重定向 → %s" % (player.callsign if player else "(无玩家机)"))
	_apply_pre_stage_directives_ace()

## Mother Goose：v1 简单处理 — 自身已在 patrol ring 上飞，不下 directive；
## UAV 蜂群在 spawn() 时已起飞，自然奔向玩家。事件系统不干预。
func _apply_pre_stage_directives_mother_goose() -> void:
	pass
